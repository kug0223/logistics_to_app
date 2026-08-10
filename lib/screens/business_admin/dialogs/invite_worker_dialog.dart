import 'package:flutter/material.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:provider/provider.dart';

import '../../../models/ui/admin_to_list_ui_models.dart';
import '../../../services/member_service.dart';
import '../../../providers/user_provider.dart';
import '../../../utils/responsive_helper.dart';
import '../../../utils/format_helper.dart';
import '../../../utils/toast_helper.dart';
import '../../../theme/app_colors.dart';
import '../../../widgets/common/common_widgets.dart';

/// 근로자 초대 다이얼로그
///
/// 관리자가 특정 TO에 전화번호로 근로자를 직접 초대한다.
/// - 단기 TO: 슬롯 날짜 선택 후 초대
/// - 장기 TO: 시작일 + 종료일 지정 후 초대
///
/// 수락 시 CF(callableAcceptInvitation)에서 스케줄 충돌 검증 → CONFIRMED 전환.
class InviteWorkerDialog extends StatefulWidget {
  final TOGroupItem groupItem;
  final String businessId;
  final String businessName;

  const InviteWorkerDialog({
    super.key,
    required this.groupItem,
    required this.businessId,
    required this.businessName,
  });

  @override
  State<InviteWorkerDialog> createState() => _InviteWorkerDialogState();
}

class _InviteWorkerDialogState extends State<InviteWorkerDialog> {
  final _memberService = MemberService();
  final _phoneCtrl = TextEditingController();
  final _phoneFmt = PhoneNumberFormatter();

  // 검색 상태
  Map<String, dynamic>? _found;
  bool _searching = false;
  bool _sending = false;

  // 단기 TO: 선택된 날짜 + slotId (slotId는 CF 연결 시 전달)
  DateTime? _selectedDate;
  String? _selectedSlotId;

  // 장기 TO: 시작일 + 종료일
  DateTime? _startDate;
  DateTime? _endDate;

  bool get _isLong => widget.groupItem.isLongTerm;

  /// 단기 TO 슬롯 날짜 + slotId 쌍 목록
  List<({DateTime date, String? slotId})> get _slotEntries {
    if (_isLong) return [];
    // groupTOs 로드된 경우: 슬롯별 날짜+ID
    final fromTOs = widget.groupItem.groupTOs
        .where((t) => t.slot?.date != null)
        .map((t) => (date: t.slot!.date, slotId: t.slot?.id))
        .toList();
    if (fromTOs.isNotEmpty) {
      fromTOs.sort((a, b) => a.date.compareTo(b.date));
      return fromTOs;
    }
    // fallback: slotDates만 있는 경우 (slotId 미확보)
    final dates = widget.groupItem.slotDates.toList()..sort();
    return dates.map((d) => (date: d, slotId: null)).toList();
  }

  @override
  void initState() {
    super.initState();
    if (_isLong) {
      // 장기 TO 기본값 설정
      final to = widget.groupItem.masterTO;
      final today = DateTime.now();
      final toStart = to.rangeStart ?? today;
      _startDate = toStart.isAfter(today) ? toStart : today;
      _endDate = to.rangeEnd ?? to.postingExpiryDate;
    }
  }

  @override
  void dispose() {
    _phoneCtrl.dispose();
    super.dispose();
  }

  // ── 전화번호 검색 ───────────────────────────────────────────────

  Future<void> _search() async {
    final raw = _phoneCtrl.text.replaceAll('-', '').trim();
    if (raw.length < 10) {
      ToastHelper.showWarning('전화번호를 정확히 입력해주세요');
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _searching = true;
      _found = null;
    });
    try {
      final result = await _memberService.findUserByPhone(raw);
      if (!mounted) return;

      // 자기 자신에게 초대 발송 차단 (SubAdmin → 본인 계정 검색 케이스)
      final currentUid = context.read<UserProvider>().currentUser?.uid;
      if (result != null && result['uid'] == currentUid) {
        ToastHelper.showWarning('자기 자신에게는 초대를 보낼 수 없습니다');
        setState(() => _found = null);
        return;
      }

      setState(() => _found = result);
      if (result == null) {
        _showNotFoundDialog();
      }
    } catch (e) {
      if (mounted) ToastHelper.showError('검색 중 오류가 발생했습니다');
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  void _showNotFoundDialog() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('앱 미가입자'),
        content: const Text(
          '해당 전화번호로 가입된 계정이 없습니다.\n가입 안내 문자를 발송할까요?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              // TODO: SMS 가입 링크 발송 (다날 SMS 인프라 연동 후 구현)
              ToastHelper.showInfo('가입 안내 문자 발송 기능은 준비 중입니다');
            },
            child: const Text('문자 발송'),
          ),
        ],
      ),
    );
  }

  // ── 초대 발송 ───────────────────────────────────────────────────

  bool get _canSend {
    if (_found == null || _sending) return false;
    if (_isLong) return _startDate != null && _endDate != null;
    return _selectedDate != null;
  }

  Future<void> _send() async {
    if (!_canSend) return;
    setState(() => _sending = true);

    try {
      final up = context.read<UserProvider>();
      final adminUid = up.currentUser?.uid;
      if (adminUid == null) {
        ToastHelper.showError('로그인 정보를 찾을 수 없습니다');
        return;
      }

      final callable = FirebaseFunctions.instanceFor(region: 'asia-northeast3')
          .httpsCallable('callableInviteWorker');
      await callable.call({
        'toId': widget.groupItem.masterTO.id,
        'businessId': widget.businessId,
        'targetUid': _found!['uid'],
        if (!_isLong) 'workDate': _selectedDate!.toIso8601String(),
        if (!_isLong && _selectedSlotId != null) 'slotId': _selectedSlotId,
        if (_isLong) 'workDate': _startDate!.toIso8601String(),
        if (_isLong) 'workEndDate': _endDate!.toIso8601String(),
        if (_isLong) 'workDays': widget.groupItem.masterTO.workDays,
      });

      if (!mounted) return;
      ToastHelper.showSuccess('${_found!['name']}님에게 초대를 발송했습니다');
      Navigator.pop(context, true);
    } on FirebaseFunctionsException catch (e) {
      debugPrint('❌ 초대 발송 오류: ${e.code} — ${e.message}');
      if (mounted) ToastHelper.showError(e.message ?? '초대 발송 중 오류가 발생했습니다');
    } catch (e) {
      debugPrint('❌ 초대 발송 오류: $e');
      if (mounted) ToastHelper.showError('초대 발송 중 오류가 발생했습니다');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  // ── 날짜 피커 ───────────────────────────────────────────────────

  Future<void> _pickDate({required bool isStart}) async {
    final to = widget.groupItem.masterTO;
    final now = DateTime.now();
    final toStart = to.rangeStart ?? now;
    final toEnd = to.rangeEnd ?? to.postingExpiryDate;

    final first = isStart
        ? (toStart.isAfter(now) ? toStart : now)
        : (_startDate ?? now);
    final last = toEnd;
    final initial = isStart ? (_startDate ?? first) : (_endDate ?? last ?? first);

    final picked = await showDatePicker(
      context: context,
      initialDate: initial.isBefore(first) ? first : initial,
      firstDate: first,
      lastDate: last ?? DateTime(now.year + 2),
      locale: const Locale('ko'),
    );
    if (!mounted || picked == null) return;
    setState(() {
      if (isStart) {
        _startDate = picked;
        // 시작일이 종료일보다 늦으면 종료일 초기화
        if (_endDate != null && picked.isAfter(_endDate!)) _endDate = null;
      } else {
        _endDate = picked;
      }
    });
  }

  // ── 빌드 ────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = ResponsiveHelper.getScale(context);

    return PopScope(
      canPop: !_sending,
      child: Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        clipBehavior: Clip.antiAlias,
        insetPadding:
            EdgeInsets.symmetric(horizontal: 20 * s, vertical: 40 * s),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildHeader(theme, s),
              _buildBody(theme, s),
            ],
          ),
        ),
      ),
    );
  }

  // ── 헤더 ────────────────────────────────────────────────────────

  Widget _buildHeader(ThemeData theme, double s) {
    final isLong = _isLong;
    return Container(
      padding: EdgeInsets.fromLTRB(20 * s, 18 * s, 16 * s, 18 * s),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [theme.primaryColor, theme.colorScheme.secondary],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: EdgeInsets.all(8 * s),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              Icons.person_add_outlined,
              color: Colors.white,
              size: ResponsiveHelper.iconSize(context, 20),
            ),
          ),
          SizedBox(width: 12 * s),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '근로자 초대',
                  style: ResponsiveHelper.subtitleStyle(context).copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Row(
                  children: [
                    Container(
                      padding: EdgeInsets.symmetric(
                          horizontal: 6 * s, vertical: 1 * s),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.25),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        isLong ? '장기' : '단기',
                        style: ResponsiveHelper.tinyStyle(context,
                            color: Colors.white),
                      ),
                    ),
                    SizedBox(width: 6 * s),
                    Flexible(
                      child: Text(
                        widget.groupItem.title,
                        style: ResponsiveHelper.tinyStyle(context,
                            color: Colors.white.withValues(alpha: 0.9)),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // 닫기 버튼
          Material(
            color: Colors.white.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(8),
            child: InkWell(
              onTap: _sending
                  ? null
                  : () {
                      FocusManager.instance.primaryFocus?.unfocus();
                      Navigator.pop(context, false);
                    },
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: EdgeInsets.all(6 * s),
                child: Icon(
                  Icons.close,
                  color: Colors.white,
                  size: ResponsiveHelper.iconSize(context, 18),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── 본문 ────────────────────────────────────────────────────────

  Widget _buildBody(ThemeData theme, double s) {
    return Container(
      color: AppColors.grey50,
      padding: EdgeInsets.all(16 * s),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildPhoneSearchSection(theme, s),
          if (_found != null) ...[
            SizedBox(height: 12 * s),
            _buildFoundCard(s),
          ],
          SizedBox(height: 12 * s),
          _isLong
              ? _buildLongTermDateSection(theme, s)
              : _buildShortTermSlotSection(theme, s),
          SizedBox(height: 20 * s),
          _buildSendButton(theme, s),
        ],
      ),
    );
  }

  // ── 전화번호 검색 섹션 ──────────────────────────────────────────

  Widget _buildPhoneSearchSection(ThemeData theme, double s) {
    return Container(
      decoration: CommonWidgets.compactCardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding:
                EdgeInsets.fromLTRB(14 * s, 12 * s, 14 * s, 8 * s),
            child: Text(
              '근로자 전화번호',
              style: ResponsiveHelper.smallStyle(context).copyWith(
                fontWeight: FontWeight.w600,
                color: AppColors.grey700,
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(12 * s, 0, 12 * s, 12 * s),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _phoneCtrl,
                    inputFormatters: [_phoneFmt],
                    keyboardType: TextInputType.phone,
                    enabled: !_sending,
                    style: ResponsiveHelper.bodyStyle(context),
                    decoration: InputDecoration(
                      hintText: '010-0000-0000',
                      hintStyle: ResponsiveHelper.bodyStyle(context,
                          color: AppColors.grey400),
                      prefixIcon: Icon(
                        Icons.phone_outlined,
                        color: AppColors.grey400,
                        size: ResponsiveHelper.iconSize(context, 18),
                      ),
                      filled: true,
                      fillColor: AppColors.grey100,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 12 * s,
                        vertical: 10 * s,
                      ),
                    ),
                    onSubmitted: (_) => _search(),
                  ),
                ),
                SizedBox(width: 8 * s),
                SizedBox(
                  height: 42 * s,
                  child: ElevatedButton(
                    onPressed: _searching || _sending ? null : _search,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: theme.primaryColor,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                      padding:
                          EdgeInsets.symmetric(horizontal: 14 * s),
                      elevation: 0,
                    ),
                    child: _searching
                        ? SizedBox(
                            width: 16 * s,
                            height: 16 * s,
                            child: const CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : Text('검색',
                            style:
                                ResponsiveHelper.smallStyle(context).copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            )),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── 검색 결과 카드 ──────────────────────────────────────────────

  Widget _buildFoundCard(double s) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 14 * s, vertical: 12 * s),
      decoration: BoxDecoration(
        color: AppColors.successBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.success.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Container(
            width: 36 * s,
            height: 36 * s,
            decoration: BoxDecoration(
              color: AppColors.success.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text(
              (_found!['name'] as String? ?? '?').isNotEmpty
                  ? (_found!['name'] as String)[0]
                  : '?',
              style: ResponsiveHelper.bodyStyle(context).copyWith(
                fontWeight: FontWeight.bold,
                color: AppColors.successDark,
              ),
            ),
          ),
          SizedBox(width: 10 * s),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _found!['name'] as String? ?? '',
                  style: ResponsiveHelper.bodyStyle(context).copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if ((_found!['phone'] as String?)?.isNotEmpty == true)
                  Text(
                    FormatHelper.formatPhone(_found!['phone'] as String),
                    style: ResponsiveHelper.tinyStyle(context,
                        color: AppColors.grey500),
                  ),
              ],
            ),
          ),
          Icon(
            Icons.check_circle,
            color: AppColors.success,
            size: ResponsiveHelper.iconSize(context, 20),
          ),
        ],
      ),
    );
  }

  // ── 단기: 슬롯 날짜 선택 ───────────────────────────────────────

  Widget _buildShortTermSlotSection(ThemeData theme, double s) {
    final entries = _slotEntries;
    return Container(
      decoration: CommonWidgets.compactCardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(14 * s, 12 * s, 14 * s, 8 * s),
            child: Row(
              children: [
                Icon(Icons.calendar_today_outlined,
                    size: ResponsiveHelper.iconSize(context, 14),
                    color: AppColors.grey500),
                SizedBox(width: 6 * s),
                Text(
                  '초대할 날짜 선택',
                  style: ResponsiveHelper.smallStyle(context).copyWith(
                    fontWeight: FontWeight.w600,
                    color: AppColors.grey700,
                  ),
                ),
              ],
            ),
          ),
          if (entries.isEmpty)
            Padding(
              padding: EdgeInsets.fromLTRB(14 * s, 0, 14 * s, 12 * s),
              child: Text(
                '슬롯 정보를 불러오는 중입니다.\n잠시 후 다시 시도해주세요.',
                style: ResponsiveHelper.smallStyle(context,
                    color: AppColors.grey500),
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: entries.length,
              separatorBuilder: (_, __) => Divider(
                  height: 1, indent: 14 * s, endIndent: 14 * s),
              itemBuilder: (_, i) {
                final entry = entries[i];
                final isSelected =
                    _selectedDate != null &&
                    DateUtils.isSameDay(_selectedDate!, entry.date);
                return InkWell(
                  onTap: _sending
                      ? null
                      : () => setState(() {
                            _selectedDate = entry.date;
                            _selectedSlotId = entry.slotId;
                          }),
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                        horizontal: 14 * s, vertical: 10 * s),
                    child: Row(
                      children: [
                        Icon(
                          isSelected
                              ? Icons.radio_button_checked
                              : Icons.radio_button_unchecked,
                          color: isSelected
                              ? theme.primaryColor
                              : AppColors.grey400,
                          size: ResponsiveHelper.iconSize(context, 18),
                        ),
                        SizedBox(width: 10 * s),
                        Text(
                          FormatHelper.formatDate(entry.date),
                          style: ResponsiveHelper.bodyStyle(context).copyWith(
                            color: isSelected
                                ? theme.primaryColor
                                : AppColors.grey800,
                            fontWeight: isSelected
                                ? FontWeight.w600
                                : FontWeight.normal,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  // ── 장기: 시작일·종료일 선택 ────────────────────────────────────

  Widget _buildLongTermDateSection(ThemeData theme, double s) {
    return Container(
      decoration: CommonWidgets.compactCardDecoration(),
      padding: EdgeInsets.all(14 * s),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.date_range_outlined,
                  size: ResponsiveHelper.iconSize(context, 14),
                  color: AppColors.grey500),
              SizedBox(width: 6 * s),
              Text(
                '근무 기간 지정',
                style: ResponsiveHelper.smallStyle(context).copyWith(
                  fontWeight: FontWeight.w600,
                  color: AppColors.grey700,
                ),
              ),
            ],
          ),
          SizedBox(height: 12 * s),
          Row(
            children: [
              Expanded(
                  child: _buildDatePickerTile(
                      theme, s,
                      label: '첫 출근일',
                      date: _startDate,
                      onTap: () => _pickDate(isStart: true))),
              SizedBox(width: 8 * s),
              Icon(Icons.arrow_forward,
                  size: ResponsiveHelper.iconSize(context, 16),
                  color: AppColors.grey400),
              SizedBox(width: 8 * s),
              Expanded(
                  child: _buildDatePickerTile(
                      theme, s,
                      label: '마지막 근무일',
                      date: _endDate,
                      onTap: () => _pickDate(isStart: false))),
            ],
          ),
          if (widget.groupItem.masterTO.workDays.isNotEmpty) ...[
            SizedBox(height: 10 * s),
            Row(
              children: [
                Icon(Icons.repeat,
                    size: ResponsiveHelper.iconSize(context, 12),
                    color: AppColors.grey400),
                SizedBox(width: 4 * s),
                Text(
                  '근무 요일: ${widget.groupItem.masterTO.workDays.join(', ')}',
                  style: ResponsiveHelper.tinyStyle(context,
                      color: AppColors.grey500),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDatePickerTile(ThemeData theme, double s,
      {required String label,
      required DateTime? date,
      required VoidCallback onTap}) {
    final hasDate = date != null;
    return GestureDetector(
      onTap: _sending ? null : onTap,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 10 * s, vertical: 10 * s),
        decoration: BoxDecoration(
          color: hasDate
              ? theme.primaryColor.withValues(alpha: 0.07)
              : AppColors.grey100,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: hasDate
                ? theme.primaryColor.withValues(alpha: 0.35)
                : AppColors.grey200,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: ResponsiveHelper.tinyStyle(context,
                  color: hasDate ? theme.primaryColor : AppColors.grey500),
            ),
            SizedBox(height: 4 * s),
            Text(
              hasDate
                  ? FormatHelper.formatDateShort(date)
                  : '날짜 선택',
              style: ResponsiveHelper.smallStyle(context).copyWith(
                color: hasDate ? theme.primaryColor : AppColors.grey400,
                fontWeight:
                    hasDate ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── 발송 버튼 ───────────────────────────────────────────────────

  Widget _buildSendButton(ThemeData theme, double s) {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: _sending
                ? null
                : () {
                    FocusManager.instance.primaryFocus?.unfocus();
                    Navigator.pop(context, false);
                  },
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.grey600,
              side: const BorderSide(color: AppColors.grey300),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              padding: EdgeInsets.symmetric(vertical: 13 * s),
            ),
            child: Text('취소',
                style: ResponsiveHelper.bodyStyle(context)
                    .copyWith(color: AppColors.grey600)),
          ),
        ),
        SizedBox(width: 10 * s),
        Expanded(
          flex: 2,
          child: ElevatedButton(
            onPressed: _canSend ? _send : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: theme.primaryColor,
              foregroundColor: Colors.white,
              disabledBackgroundColor: AppColors.grey200,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              padding: EdgeInsets.symmetric(vertical: 13 * s),
              elevation: 0,
            ),
            child: _sending
                ? SizedBox(
                    width: 18 * s,
                    height: 18 * s,
                    child: const CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.send_outlined,
                          size: ResponsiveHelper.iconSize(context, 16),
                          color: Colors.white),
                      SizedBox(width: 6 * s),
                      Text(
                        '초대 발송',
                        style: ResponsiveHelper.bodyStyle(context).copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ],
    );
  }
}
