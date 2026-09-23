import 'package:flutter/material.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:provider/provider.dart';

import '../../../models/core/work_detail_data.dart';
import '../../../models/ui/admin_to_list_ui_models.dart';
import '../../../services/member_service.dart';
import '../../../providers/user_provider.dart';
import '../../../utils/responsive_helper.dart';
import '../../../utils/format_helper.dart';
import '../../../utils/toast_helper.dart';
import '../../../theme/app_colors.dart';
import '../../../widgets/common/common_widgets.dart';
import '../../../widgets/dialogs/styled_dialog.dart';

/// 근로자 초대 다이얼로그
///
/// 관리자가 특정 TO에 전화번호로 근로자를 직접 초대한다.
///
/// ## 일반 모드 (general mode)
/// TOGroupCard 메뉴 → [인력 초대] 에서 진입.
/// - 단기 TO: 슬롯 날짜 선택 → 업무(시간대) 선택 후 근무 제안
/// - 장기 TO: 시작일 + 종료일 지정 → 업무(시간대) 선택 후 근무 제안
///
/// ## [POSTING-V2-01A] workDetail identity 필수
/// 일반 모드도 contextual 모드와 동일하게
/// `selectedWorkType` + `workDetailStartTime` + `workDetailEndTime`를 전송한다.
/// 이 3개가 없으면 서버(callableInviteWorker)가 exact workDetail resolve 블록을
/// 통째로 건너뛰어 wdId / wage / wageType 없는 Application이 생성되고,
/// 수락 시 업무별 capacity 재검증도 skip된다.
/// 따라서 업무를 선택하지 않으면 발송 자체를 막는다 — 임의 첫 번째 선택 금지.
///
/// ## 컨텍스트 모드 (contextual mode) — [Phase 8.1B.3]
/// DayApplicantsDialog → [인력 초대] → [직접 초대] 에서 진입.
/// 날짜·슬롯·업무 정보가 이미 확정되어 있으므로 재선택 UI를 표시하지 않는다.
/// [InviteWorkerDialog.contextual] 팩토리로 생성.
///
/// 수락 시 CF(callableAcceptTOInvitation)에서 스케줄 충돌 검증 → CONFIRMED 전환.
class InviteWorkerDialog extends StatefulWidget {
  // ── 공통 필드 ────────────────────────────────────────────────────
  final String businessId;
  final String businessName;

  // ── 일반 모드 전용 ───────────────────────────────────────────────
  final TOGroupItem? groupItem;

  // ── 컨텍스트 모드 전용 (DayApplicantsDialog exact context) ───────
  final String? contextualToId;
  final DateTime? prefilledDate;
  final String? prefilledSlotId;
  final String? prefilledWorkType;
  final String? prefilledStartTime;
  final String? prefilledEndTime;

  /// [R7-P1R §14] 장기 모집 단위의 약속 범위.
  ///
  ///   contextual 모드는 groupItem이 null이라 isLongTerm이 항상 false로
  ///   계산됐고, workEndDate·workDays를 싣는 분기는 groupItem에 의존했다.
  ///   그래서 이 경로로 장기 공고에 초대를 보내면 **하루짜리 지원서**가
  ///   만들어졌고, 그 위험 때문에 장기 CTA 자체를 막아 두어야 했다.
  ///
  ///   groupItem 전체를 끌어오지 않는다 — 필요한 두 값만 받는다.
  ///   null이면 단기다.
  final DateTime? prefilledWorkEndDate;
  final List<String>? prefilledWorkDays;

  /// 이 contextual 초대가 장기 약속인가.
  bool get isContextualLongTerm =>
      isContextualMode && prefilledWorkEndDate != null;

  /// 컨텍스트 모드 여부 — [contextualToId] + [prefilledDate] 존재 시 true
  bool get isContextualMode =>
      contextualToId != null && prefilledDate != null;

  /// 일반 모드 생성자 — TOGroupCard 메뉴에서 사용
  const InviteWorkerDialog({
    super.key,
    required this.groupItem,
    required this.businessId,
    required this.businessName,
  })  : contextualToId = null,
        prefilledDate = null,
        prefilledSlotId = null,
        prefilledWorkType = null,
        prefilledStartTime = null,
        prefilledEndTime = null,
        prefilledWorkEndDate = null,
        prefilledWorkDays = null;

  /// 컨텍스트 모드 생성자 — DayApplicantsDialog exact work-group에서 사용.
  ///
  /// [date], [slotId], [workType] 이 pre-filled되어
  /// 날짜·업무 재선택 UI를 표시하지 않는다.
  static InviteWorkerDialog contextual({
    Key? key,
    required String toId,
    required String businessId,
    required String businessName,
    required DateTime date,
    String? slotId,
    String? workType,
    String? startTime,
    String? endTime,
    // [R7-P1R §14] 장기면 둘을 함께 넘긴다. 없으면 단기다.
    DateTime? workEndDate,
    List<String>? workDays,
  }) {
    return InviteWorkerDialog._contextual(
      key: key,
      contextualToId: toId,
      businessId: businessId,
      businessName: businessName,
      prefilledDate: date,
      prefilledSlotId: slotId,
      prefilledWorkType: workType,
      prefilledStartTime: startTime,
      prefilledEndTime: endTime,
      prefilledWorkEndDate: workEndDate,
      prefilledWorkDays: workDays,
    );
  }

  const InviteWorkerDialog._contextual({
    super.key,
    required this.contextualToId,
    required this.businessId,
    required this.businessName,
    required this.prefilledDate,
    this.prefilledSlotId,
    this.prefilledWorkType,
    this.prefilledStartTime,
    this.prefilledEndTime,
    this.prefilledWorkEndDate,
    this.prefilledWorkDays,
  }) : groupItem = null;

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

  // [POSTING-V2-01A] 선택된 업무(workDetail) key — WorkDetailData.id
  // ('${workType}_${startTime}_$endTime'). 일반 모드 전용.
  String? _selectedWorkDetailKey;

  // 컨텍스트 모드에서는 항상 단기(슬롯 있는) 케이스
  bool get _isLong => widget.isContextualMode
      ? false
      : (widget.groupItem?.isLongTerm ?? false);

  /// 단기 TO 슬롯 날짜 + slotId 쌍 목록 — 일반 모드에서만 사용
  List<({DateTime date, String? slotId})> get _slotEntries {
    if (_isLong) return [];
    final gi = widget.groupItem;
    if (gi == null) return [];
    // groupTOs 로드된 경우: 슬롯별 날짜+ID
    final fromTOs = gi.groupTOs
        .where((t) => t.slot?.date != null)
        .map((t) => (date: t.slot!.date, slotId: t.slot?.id))
        .toList();
    if (fromTOs.isNotEmpty) {
      fromTOs.sort((a, b) => a.date.compareTo(b.date));
      return fromTOs;
    }
    // fallback: slotDates만 있는 경우 (slotId 미확보)
    final dates = gi.slotDates.toList()..sort();
    return dates.map((d) => (date: d, slotId: null)).toList();
  }

  // ── [POSTING-V2-01A] 업무(workDetail) 후보 ───────────────────────
  //
  // 서버 callableInviteWorker 5.5 블록의 canonical source와 동일한 우선순위를 쓴다:
  //   slotId 있음 → slot.workDetails, 비어 있으면 TO.workDetails
  //   slotId 없음(장기) → TO.workDetails
  // 추가 Firestore 조회를 하지 않는다 — 목록 로드 시 이미 확보된 데이터만 사용.
  List<WorkDetailData> get _workDetailOptions {
    final gi = widget.groupItem;
    if (gi == null) return const [];
    if (!_isLong && _selectedSlotId != null) {
      final matched = gi.groupTOs
          .where((t) => t.slot?.id == _selectedSlotId)
          .firstOrNull;
      final slotWds = matched?.slot?.workDetails ?? const <WorkDetailData>[];
      if (slotWds.isNotEmpty) return slotWds;
    }
    return gi.masterTO.workDetails;
  }

  /// 현재 선택된 workDetail. 미선택이거나 후보에서 사라졌으면 null.
  WorkDetailData? get _selectedWorkDetail {
    final key = _selectedWorkDetailKey;
    if (key == null) return null;
    return _workDetailOptions.where((w) => w.id == key).firstOrNull;
  }

  /// 날짜(=슬롯)가 바뀌면 업무 후보 집합 자체가 달라지므로 선택을 초기화한다.
  /// 단, 후보가 정확히 1개면 선택의 여지가 없으므로 그것으로 확정한다
  /// (임의 first-match가 아니라 유일 후보 — 화면에도 선택된 상태로 보인다).
  void _syncWorkDetailSelection() {
    final options = _workDetailOptions;
    if (options.length == 1) {
      _selectedWorkDetailKey = options.first.id;
      return;
    }
    if (_selectedWorkDetailKey != null &&
        !options.any((w) => w.id == _selectedWorkDetailKey)) {
      _selectedWorkDetailKey = null;
    }
  }

  @override
  void initState() {
    super.initState();
    if (_isLong) {
      // 장기 TO 기본값 설정 (일반 모드에서만 도달)
      final to = widget.groupItem!.masterTO;
      final today = DateTime.now();
      final toStart = to.rangeStart ?? today;
      _startDate = toStart.isAfter(today) ? toStart : today;
      _endDate = to.rangeEnd ?? to.postingExpiryDate;
    }
    // [POSTING-V2-01A] 장기는 후보가 고정이라 여기서 1회 확정 가능.
    // 단기는 날짜(슬롯) 선택 시점에 _syncWorkDetailSelection()을 다시 호출한다.
    if (!widget.isContextualMode) _syncWorkDetailSelection();
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
    // 컨텍스트 모드: date/workDetail pre-filled → 재선택 불필요
    if (widget.isContextualMode) return true;
    // [POSTING-V2-01A] 업무(workDetail)가 확정되지 않으면 발송 금지.
    // 서버가 workType만으로 임의 resolve하지 않도록 클라이언트에서 먼저 막는다.
    if (_selectedWorkDetail == null) return false;
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

      // [POSTING-V2-01A] 일반 모드 fail-closed:
      // workDetail이 확정되지 않은 초대는 보내지 않는다. wage/wdId 없는
      // Application이 생성되면 급여 기준액이 0으로 떨어진다.
      final generalWd =
          widget.isContextualMode ? null : _selectedWorkDetail;
      if (!widget.isContextualMode && generalWd == null) {
        ToastHelper.showWarning('초대할 업무를 선택해주세요');
        return;
      }

      final callable = FirebaseFunctions.instanceFor(region: 'asia-northeast3')
          .httpsCallable('callableInviteWorker');

      // toId: 컨텍스트 모드는 contextualToId, 일반 모드는 groupItem에서 취득
      final toId = widget.isContextualMode
          ? widget.contextualToId!
          : widget.groupItem!.masterTO.id;

      await callable.call({
        'toId': toId,
        'businessId': widget.businessId,
        'targetUid': _found!['uid'],
        if (widget.isContextualMode) ...{
          // 컨텍스트 모드: pre-filled date/slotId/workType 전달
          'workDate': widget.prefilledDate!.toIso8601String(),
          if (widget.prefilledSlotId != null && widget.prefilledSlotId!.isNotEmpty)
            'slotId': widget.prefilledSlotId,
          // [R7-P1R §14] 장기는 하루가 아니라 **기간**에 대한 제안이다.
          //   이 두 줄이 없어서 장기 공고에 하루짜리 지원서가 만들어졌고,
          //   그 때문에 장기 초대 CTA를 막아 두어야 했다. 일반 모드의
          //   장기 분기와 **같은 키·같은 의미**를 쓴다.
          if (widget.prefilledWorkEndDate != null)
            'workEndDate': widget.prefilledWorkEndDate!.toIso8601String(),
          if (widget.prefilledWorkDays != null &&
              widget.prefilledWorkDays!.isNotEmpty)
            'workDays': widget.prefilledWorkDays,
          // [6.1 INV-01/02] selectedWorkType → 서버가 wage/wageType 파생
          // [Phase 8.1B.4] workDetailStartTime/End → 동일 workType 복수 시 정확한 WorkDetail 식별
          if (widget.prefilledWorkType != null && widget.prefilledWorkType!.isNotEmpty)
            'selectedWorkType': widget.prefilledWorkType,
          if (widget.prefilledStartTime != null && widget.prefilledStartTime!.isNotEmpty)
            'workDetailStartTime': widget.prefilledStartTime,
          if (widget.prefilledEndTime != null && widget.prefilledEndTime!.isNotEmpty)
            'workDetailEndTime': widget.prefilledEndTime,
        } else if (!_isLong) ...{
          'workDate': _selectedDate!.toIso8601String(),
          if (_selectedSlotId != null) 'slotId': _selectedSlotId,
          // [POSTING-V2-01A] contextual 모드와 동일한 3중 매칭 payload
          'selectedWorkType': generalWd!.workType,
          'workDetailStartTime': generalWd.startTime,
          'workDetailEndTime': generalWd.endTime,
        } else ...{
          'workDate': _startDate!.toIso8601String(),
          'workEndDate': _endDate!.toIso8601String(),
          'workDays': widget.groupItem!.masterTO.workDays,
          // [POSTING-V2-01A] 장기도 동일 — TO.workDetails 기준 exact resolve
          'selectedWorkType': generalWd!.workType,
          'workDetailStartTime': generalWd.startTime,
          'workDetailEndTime': generalWd.endTime,
        },
      });

      if (!mounted) return;
      final name = _found!['name'] as String? ?? '';
      // 컨텍스트 모드: "근무 제안" / 일반 모드: "초대 발송" (기존 표현 유지)
      if (widget.isContextualMode) {
        ToastHelper.showSuccess('$name님에게 근무 제안을 보냈습니다');
      } else {
        ToastHelper.showSuccess('$name님에게 초대를 발송했습니다');
      }
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
    // 일반 모드에서만 호출됨 — groupItem 보장
    final to = widget.groupItem!.masterTO;
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

    // subtitle: 컨텍스트 모드 → 사업장명 / 단기 → '단기 · TO제목' / 장기 → '장기 · TO제목'
    final subtitle = widget.isContextualMode
        ? widget.businessName
        : _isLong
            ? '장기 · ${widget.groupItem?.title ?? ''}'
            : '단기 · ${widget.groupItem?.title ?? ''}';

    return PopScope(
      canPop: !_sending,
      child: AppModalShell(
        children: [
          AppModalHeader(
            title: widget.isContextualMode ? '직접 초대' : '인력 초대',
            subtitle: subtitle,
            onClose: _sending
                ? null
                : () {
                    FocusManager.instance.primaryFocus?.unfocus();
                    Navigator.pop(context, false);
                  },
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.all(16 * s),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 컨텍스트 모드: 근무 정보 요약 (날짜·슬롯 재선택 불필요)
                  if (widget.isContextualMode) _buildContextSummary(s),
                  _buildPhoneSearchSection(theme, s),
                  if (_found != null) ...[
                    SizedBox(height: 12 * s),
                    _buildFoundCard(s),
                  ],
                  // 일반 모드에서만 날짜/슬롯 선택 섹션 표시
                  if (!widget.isContextualMode) ...[
                    SizedBox(height: 12 * s),
                    _isLong
                        ? _buildLongTermDateSection(theme, s)
                        : _buildShortTermSlotSection(theme, s),
                    // [POSTING-V2-01A] 업무(시간대) 선택 — 단기는 날짜 확정 후 표시.
                    // 날짜에 따라 슬롯 workDetails가 달라지므로 순서를 지킨다.
                    if (_isLong || _selectedDate != null) ...[
                      SizedBox(height: 12 * s),
                      _buildWorkDetailSection(theme, s),
                    ],
                  ],
                ],
              ),
            ),
          ),
          AppModalFooter(child: _buildSendButton(theme, s)),
        ],
      ),
    );
  }

  // ── [Phase 8.1B.3] 컨텍스트 모드 근무 정보 요약 카드 ────────────

  Widget _buildContextSummary(double s) {
    final workType = widget.prefilledWorkType ?? '';
    final dateStr = widget.prefilledDate != null
        ? FormatHelper.formatDateShort(widget.prefilledDate!)
        : '';
    final startT = widget.prefilledStartTime ?? '';
    final endT = widget.prefilledEndTime ?? '';
    final timeStr = (startT.isNotEmpty && endT.isNotEmpty)
        ? '$startT ~ $endT'
        : '';

    return Padding(
      padding: EdgeInsets.only(bottom: 12 * s),
      child: Container(
        padding: EdgeInsets.all(14 * s),
        decoration: CommonWidgets.compactCardDecoration(),
        child: Row(
          children: [
            Container(
              padding: EdgeInsets.all(8 * s),
              decoration: BoxDecoration(
                color: AppColors.info.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                Icons.work_outline,
                size: ResponsiveHelper.iconSize(context, 16),
                color: AppColors.info,
              ),
            ),
            SizedBox(width: 10 * s),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (workType.isNotEmpty)
                    Text(
                      workType,
                      style: ResponsiveHelper.bodyStyle(context)
                          .copyWith(fontWeight: FontWeight.w600),
                    ),
                  if (dateStr.isNotEmpty || timeStr.isNotEmpty)
                    Text(
                      [dateStr, timeStr]
                          .where((v) => v.isNotEmpty)
                          .join(' · '),
                      style: ResponsiveHelper.smallStyle(context,
                          color: AppColors.grey500),
                    ),
                ],
              ),
            ),
          ],
        ),
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
                            // [POSTING-V2-01A] 슬롯이 바뀌면 업무 후보 집합도 바뀐다
                            _syncWorkDetailSelection();
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

  // ── [POSTING-V2-01A] 업무(시간대) 선택 ──────────────────────────
  //
  // 같은 workType이 시간대별로 여러 개일 수 있으므로 workType만으로 고르지 않는다.
  // 후보가 1개면 유일 후보로 확정 표시, 2개 이상이면 명시적 선택을 요구한다.
  Widget _buildWorkDetailSection(ThemeData theme, double s) {
    final options = _workDetailOptions;
    return Container(
      decoration: CommonWidgets.compactCardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(14 * s, 12 * s, 14 * s, 8 * s),
            child: Row(
              children: [
                Icon(Icons.work_outline,
                    size: ResponsiveHelper.iconSize(context, 14),
                    color: AppColors.grey500),
                SizedBox(width: 6 * s),
                Expanded(
                  child: Text(
                    options.length > 1 ? '초대할 업무 선택' : '초대할 업무',
                    style: ResponsiveHelper.smallStyle(context).copyWith(
                      fontWeight: FontWeight.w600,
                      color: AppColors.grey700,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (options.isEmpty)
            Padding(
              padding: EdgeInsets.fromLTRB(14 * s, 0, 14 * s, 12 * s),
              child: Text(
                '업무 정보를 불러오지 못했습니다.\n공고를 새로고침한 뒤 다시 시도해주세요.',
                style: ResponsiveHelper.smallStyle(context,
                    color: AppColors.error),
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: options.length,
              separatorBuilder: (_, __) =>
                  Divider(height: 1, indent: 14 * s, endIndent: 14 * s),
              itemBuilder: (_, i) {
                final wd = options[i];
                final isSelected = _selectedWorkDetailKey == wd.id;
                return InkWell(
                  onTap: _sending
                      ? null
                      : () =>
                          setState(() => _selectedWorkDetailKey = wd.id),
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
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                wd.workType,
                                style: ResponsiveHelper.bodyStyle(context)
                                    .copyWith(
                                  color: isSelected
                                      ? theme.primaryColor
                                      : AppColors.grey800,
                                  fontWeight: isSelected
                                      ? FontWeight.w600
                                      : FontWeight.normal,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              SizedBox(height: 2 * s),
                              Text(
                                '${wd.startTime} ~ ${wd.endTime}'
                                '  ·  ${wd.wageTypeLabel} '
                                '${FormatHelper.formatWage(wd.wage)}',
                                style: ResponsiveHelper.tinyStyle(context,
                                    color: AppColors.grey500),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
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
          // groupItem 보장 — _buildLongTermDateSection은 일반 모드에서만 호출됨
          if ((widget.groupItem?.masterTO.workDays ?? []).isNotEmpty) ...[
            SizedBox(height: 10 * s),
            Row(
              children: [
                Icon(Icons.repeat,
                    size: ResponsiveHelper.iconSize(context, 12),
                    color: AppColors.grey400),
                SizedBox(width: 4 * s),
                Text(
                  '근무 요일: ${(widget.groupItem?.masterTO.workDays ?? []).join(', ')}',
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
                        // 컨텍스트 모드: "근무 제안" / 일반 모드: "초대 발송"
                        widget.isContextualMode ? '근무 제안' : '초대 발송',
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
