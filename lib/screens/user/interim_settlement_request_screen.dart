// lib/screens/user/interim_settlement_request_screen.dart
//
// 근로자가 급여 확정된 출근기록 중 일부를 선택해 중간정산을 요청하는 화면.
// 서버사이드 검증: callableRequestInterimSettlement CF (ownership, duplicate 방어).

import 'dart:async';
import 'interim_settlement_reads.dart';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../models/core/application_model.dart';
import '../../models/core/attendance_model.dart';
import '../../providers/user_provider.dart';
import '../../services/firestore_service.dart';
import '../../services/payroll_payment_service.dart';
import '../../theme/app_colors.dart';
import '../../utils/format_helper.dart';
import '../../utils/responsive_helper.dart';
import '../../utils/text_layout.dart';
import '../../utils/toast_helper.dart';
import '../../widgets/common/app_batch_action_bar.dart';
import '../../widgets/common/app_empty_state.dart';
import '../../widgets/common/app_page_actions.dart';
import '../../widgets/common/app_page_scaffold.dart';
import '../../widgets/user/pending_contract_bar.dart';
import '../../widgets/common/loading_widget.dart';

class InterimSettlementRequestScreen extends StatefulWidget {
  final ApplicationModel app;

  const InterimSettlementRequestScreen(
      {super.key, required this.app, this.reads});

  /// [R7-P2-4 P24-Q] 정산 후보를 읽는 경계. production 은 null.
  final InterimSettlementReads? reads;

  @override
  State<InterimSettlementRequestScreen> createState() =>
      _InterimSettlementRequestScreenState();
}

class _InterimSettlementRequestScreenState
    extends State<InterimSettlementRequestScreen> {
  // ─── 포맷터 캐싱 ─────────────────────────────────────────────
  static final _timeFmt = DateFormat('HH:mm');

  final FirestoreService _firestoreService = FirestoreService();
  late final InterimSettlementReads _reads =
      widget.reads ?? InterimSettlementReads.of(_firestoreService);

  /// [R7-P2-4 P24-Q] 정산 후보를 **읽지 못했다**.
  ///
  ///   catch 가 로딩만 껐고 토스트조차 없었다. `_records` 가 빈 채로 남아
  ///   화면은 `정산 가능한 출근기록이 없습니다` 를 그렸고, 부제는 한술 더 떠
  ///   **이유까지 단정했다** — "급여 확정된 근무일이 없거나 이미 모두 정산
  ///   처리되었습니다." 조회 한 번 실패했을 뿐인데 사용자는 받을 돈이 없다고
  ///   믿고 돌아간다. 돈을 다루는 화면에서 ERROR 를 EMPTY 로 접지 않는다.
  Object? _loadError;
  final PayrollPaymentService _payService = PayrollPaymentService();
  final TextEditingController _reasonController = TextEditingController();

  List<AttendanceModel> _records = [];
  final Set<String> _selectedIds = {};
  int _cachedNetAmount = 0; // _selectedIds 변경 시 갱신 — build()마다 O(n) 재계산 방지
  bool _isLoading = false; // 초기값 false — initState에서 _loadConfirmedAttendances() 첫 호출 시 재진입 방어에 걸리지 않도록
  bool _isSubmitting = false;

  // 로드 대상 최근 개월 수 (최대 3개월치)
  static const int _monthsToLoad = 3;

  /// [DU257] 안내 배너 문구 — 낱말 단위 줄바꿈을 위해 상수로 옮겼다(내용 같음).
  static const _bannerText = '급여 확정된 근무일 중 정산받을 날짜를 선택하세요.\n'
      '관리자 승인 후 이체 예정일이 안내됩니다.';

  @override
  void initState() {
    super.initState();
    _loadConfirmedAttendances();
  }

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  Future<void> _loadConfirmedAttendances() async {
    if (!mounted) return;
    if (_isLoading) return; // pull-to-refresh 재진입 방어
    final uid = context.read<UserProvider>().currentUser?.uid;
    if (uid == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }
    setState(() { _isLoading = true; _selectedIds.clear(); });

    try {
      final now = DateTime.now();
      // 최근 _monthsToLoad개월 병렬 조회
      final futures = <Future<List<AttendanceModel>>>[];
      for (var i = 0; i < _monthsToLoad; i++) {
        final target = DateTime(now.year, now.month - i);
        futures.add(
          _reads.myMonthlyAttendances(
            userId: uid,
            year: target.year,
            month: target.month,
          ),
        );
      }
      final results = await Future.wait(futures);
      if (!mounted) return;

      final businessId = widget.app.businessId;
      final all = results
          .expand((list) => list)
          .where((a) =>
              a.businessId == businessId && a.isWageConfirmed)
          .toList()
        ..sort((a, b) => b.workDate.compareTo(a.workDate));

      setState(() {
        _records = all;
        _isLoading = false;
        _loadError = null;
      });
    } catch (e) {
      debugPrint('❌ 중간정산 출근기록 로드 실패: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _loadError = e;
        });
      }
    }
  }

  // ── 선택 계산 ──────────────────────────────────────────────

  List<AttendanceModel> get _selectedRecords =>
      _records.where((a) => _selectedIds.contains(a.id)).toList();

  /// setState 시점에 한 번만 계산 — build()마다 재계산하지 않음
  void _recalcNetAmount() {
    _cachedNetAmount = _selectedRecords
        .fold(0, (s, a) => s + (a.wageDetail?.effectiveNetWage ?? 0));
  }

  void _toggleAll(bool select) {
    setState(() {
      if (select) {
        _selectedIds.addAll(_records.map((a) => a.id));
      } else {
        _selectedIds.clear();
      }
      _recalcNetAmount();
    });
  }

  // ── 제출 ───────────────────────────────────────────────────

  Future<void> _submit() async {
    if (_selectedIds.isEmpty) {
      ToastHelper.showWarning('정산할 출근기록을 선택해주세요.');
      return;
    }
    if (_isSubmitting) return;

    setState(() => _isSubmitting = true);
    try {
      final records = _selectedRecords;
      final requestedAmount = records.fold<int>(0, (s, a) => s + (a.wageDetail?.totalAmount ?? 0));
      final netAmount = records.fold<int>(0, (s, a) => s + (a.wageDetail?.effectiveNetWage ?? 0));
      final dates = records.map((a) => a.workDate);
      final periodStart = dates.reduce((a, b) => a.isBefore(b) ? a : b);
      final periodEnd = dates.reduce((a, b) => a.isAfter(b) ? a : b);
      await _payService.requestInterimSettlement(
        applicationId: widget.app.id,
        businessId: widget.app.businessId,
        attendanceIds: _selectedIds.toList(),
        requestedAmount: requestedAmount,
        netAmount: netAmount,
        requestReason: _reasonController.text.trim().isNotEmpty
            ? _reasonController.text.trim()
            : null,
        periodStart: periodStart,
        periodEnd: periodEnd,
      );
      if (!mounted) return;
      ToastHelper.showSuccess('중간정산 요청이 접수되었습니다.');
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        final msg = e.toString().replaceFirst('Exception: ', '');
        ToastHelper.showError(msg.isNotEmpty ? msg : '중간정산 요청에 실패했습니다');
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  // ── 빌드 ───────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final netAmount = _cachedNetAmount;
    // [R7-P3-4] 내 지원(flat)에서 들어오는데 이 화면만 파란 헤더였다.
    //   제목에 사업장명이 붙어 길어질 수 있어 좁은 화면 렌더를 함께 확인한다.
    return AppPageScaffold(
      // [DU257] 제목은 짧게. 공용 스캐폴드가 긴 제목을 두 줄 '…' 로 줄여 사업장명이 잘렸다(B320 '강남 물류센터 …').
      //   사업장명은 본문 첫 줄(_buildBusinessHeader)에 말줄임 없이 둔다.
      title: '중간정산 요청',
      actions: appPageActions(context, onRefresh: _loadConfirmedAttendances),
      bottomNavigationBar: const PendingContractBar(useSafeArea: true),
      body: SafeArea(
        top: false,
        left: false,
        right: false,
        child: _isLoading
          ? const LoadingWidget(message: '출근기록 로딩 중...')
          : _records.isEmpty
              ? (_loadError != null
                  ? AppEmptyState(
                      icon: Icons.cloud_off_outlined,
                      iconColor: AppColors.grey500,
                      title: '정산 가능한 근무를 확인하지 못했습니다',
                      subtitle: '정산할 근무가 없다는 뜻이 아닙니다.\n'
                          '잠시 후 다시 시도해주세요.',
                      action: TextButton.icon(
                        onPressed: _isLoading ? null : _loadConfirmedAttendances,
                        icon: const Icon(Icons.refresh, size: 18),
                        label: const Text('다시 시도'),
                      ),
                    )
                  : AppEmptyState(
                      icon: Icons.account_balance_wallet_outlined,
                      title: '정산 가능한 출근기록이 없습니다',
                      subtitle: '급여 확정된 근무일이 없거나\n이미 모두 정산 처리되었습니다.',
                      action: TextButton(
                        onPressed: _loadConfirmedAttendances,
                        child: const Text('새로고침'),
                      ),
                    ))
              : Column(
                  children: [
                    // [DU257] 사업장명·안내·사유·출근기록을 **한 스크롤**로 묶는다(일괄 선택 바만 아래 고정).
                    //   이전에는 배너·사유 칸이 고정이고 목록만 Expanded 였다. 그래서 B320(2배)에서 고정 부분이
                    //   화면을 다 차지해 목록 높이가 0 이 됐다(카드가 보이지도·눌리지도 않았고 26px 넘쳤다).
                    Expanded(
                      child: ListView.builder(
                        padding: EdgeInsets.only(
                          bottom: ResponsiveHelper.spacing(context, 8),
                        ),
                        itemCount: _records.length + 3,
                        itemBuilder: (ctx, i) {
                          if (i == 0) return _buildBusinessHeader();
                          if (i == 1) return _buildInfoBanner();
                          if (i == 2) return _buildReasonField();
                          return Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: ResponsiveHelper.spacing(context, 12),
                            ),
                            child: _buildAttendanceCard(_records[i - 3]),
                          );
                        },
                      ),
                    ),

                    // 일괄 선택 바 — SafeArea(top:false)로 하단 홈버튼 영역 처리
                    SafeArea(
                      top: false,
                      child: AppBatchActionBar(
                        selectedCount: _selectedIds.length,
                        selectedAmount: netAmount,
                        onSelectAll: () => _toggleAll(true),
                        onDeselectAll: () => _toggleAll(false),
                        onAction: _selectedIds.isEmpty || _isSubmitting ? null : _submit,
                        actionLabel: _isSubmitting ? '요청 중...' : '중간정산 요청',
                        actionIcon: Icons.account_balance_wallet,
                      ),
                    ),
                  ],
                ),
      ),
    );
  }

  /// [DU257] 어느 사업장의 정산인지 — 제목에서 잘리던 사업장명을 본문 첫 줄에 다 보인다.
  Widget _buildBusinessHeader() {
    final name = widget.app.businessName;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        ResponsiveHelper.spacing(context, 16),
        ResponsiveHelper.spacing(context, 16),
        ResponsiveHelper.spacing(context, 16),
        0,
      ),
      child: Text(
        TextLayout.identity(name),
        semanticsLabel: name,
        style: ResponsiveHelper.subtitleStyle(context).copyWith(
            fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
      ),
    );
  }

  /// 요청 사유 입력(선택) — [DU257] 본문 스크롤 안으로 옮겼다(내용 같음).
  Widget _buildReasonField() {
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 16),
        vertical: ResponsiveHelper.spacing(context, 8),
      ),
      child: TextField(
        controller: _reasonController,
        // [DU257] 테두리 덮어쓰기(반경 8·grey300)는 테마의 enabled/focused 테두리(반경 12)에 가려 쓰이지 않았다
        //   — 지우고 테마 하나로 둔다. 힌트는 낱말 단위 줄바꿈, 앞 아이콘 grey500(2.5) → textSecondary.
        decoration: InputDecoration(
          hintText: TextLayout.keepWords('요청 사유 (선택사항)'),
          contentPadding: EdgeInsets.symmetric(
            horizontal: ResponsiveHelper.spacing(context, 12),
            vertical: ResponsiveHelper.spacing(context, 10),
          ),
          prefixIcon: Icon(Icons.edit_note,
              color: AppColors.textSecondary,
              size: ResponsiveHelper.iconSize(context, 20)),
        ),
        style: ResponsiveHelper.bodyStyle(context),
        maxLines: 2,
        maxLength: 100,
      ),
    );
  }

  Widget _buildInfoBanner() {
    return Container(
      margin: EdgeInsets.all(ResponsiveHelper.spacing(context, 16)),
      padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 12)),
      // [DU257] 청록 면·선 → 대표색 옅은 면(홈 안내 상자와 같은 brandSurface)·반경 12·선 없음.
      //   아이콘 대표색, 글자 12 청록 → 13 보조색·낱말 단위 줄바꿈(B320 '선택하/세요' 끊김).
      decoration: BoxDecoration(
        color: AppColors.brandSurface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline,
              color: AppColors.brand,
              size: ResponsiveHelper.iconSize(context, 16)),
          SizedBox(width: ResponsiveHelper.spacing(context, 8)),
          Expanded(
            child: Text(
              TextLayout.keepWords(_bannerText),
              semanticsLabel: _bannerText,
              style: ResponsiveHelper.smallStyle(context, color: AppColors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAttendanceCard(AttendanceModel att) {
    final selected = _selectedIds.contains(att.id);
    final wage = att.wageDetail;
    final netWage = wage?.effectiveNetWage ?? 0;
    final totalAmount = wage?.totalAmount ?? 0;
    final hasWage = wage != null && netWage > 0;

    return GestureDetector(
      onTap: () {
        if (!hasWage) return; // 급여 정보 없으면 선택 불가
        setState(() {
          if (selected) {
            _selectedIds.remove(att.id);
          } else {
            _selectedIds.add(att.id);
          }
          _recalcNetAmount();
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        margin: EdgeInsets.only(bottom: ResponsiveHelper.spacing(context, 6)),
        // [DU257] 선택 = 대표색(청록 → brandSurface 면·brand 선). 반경 10 → 16(S042 목록 카드와 같음).
        decoration: BoxDecoration(
          color: selected
              ? AppColors.brandSurface
              : hasWage
                  ? AppColors.surface
                  : AppColors.grey50,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? AppColors.brand : AppColors.grey200,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: ResponsiveHelper.spacing(context, 12),
            vertical: ResponsiveHelper.spacing(context, 10),
          ),
          child: Row(
            children: [
              // 체크박스
              Icon(
                selected
                    ? Icons.check_circle
                    : hasWage
                        ? Icons.radio_button_unchecked
                        : Icons.lock_outline,
                // [DU257] 청록·grey400(1.9)·grey300(1.3) → 대표색·textTertiary(5.25)
                color: selected
                    ? AppColors.brand
                    : AppColors.textTertiary,
                size: ResponsiveHelper.iconSize(context, 22),
              ),
              SizedBox(width: ResponsiveHelper.spacing(context, 10)),

              // 날짜 + 시간
              Expanded(
                flex: 3,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      DateFormat('MM.dd (E)', 'ko').format(att.workDate),
                      style: ResponsiveHelper.bodyStyle(context).copyWith(
                        fontWeight: FontWeight.w600,
                        // [DU257] 급여 없는 줄 grey400(1.8) → textTertiary
                        color: hasWage ? AppColors.textPrimary : AppColors.textTertiary,
                      ),
                    ),
                    if (att.checkInAt != null || att.checkOutAt != null)
                      Text(
                        _formatTimeRange(att.checkInAt, att.checkOutAt),
                        style: ResponsiveHelper.tinyStyle(
                            context, color: AppColors.textSecondary), // [DU257] grey500(2.68)
                      ),
                  ],
                ),
              ),

              // 금액
              if (hasWage)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      FormatHelper.formatWage(netWage),
                      style: ResponsiveHelper.bodyStyle(context).copyWith(
                        fontWeight: FontWeight.bold,
                        // [DU257] 선택은 면·선·아이콘이 보여 준다 — 금액은 늘 본문색
                        color: AppColors.textPrimary,
                      ),
                    ),
                    if (totalAmount != netWage)
                      Text(
                        '세전 ${FormatHelper.formatWage(totalAmount)}',
                        style: ResponsiveHelper.tinyStyle(
                            context, color: AppColors.textSecondary), // [DU257] grey500(2.68)
                      ),
                  ],
                )
              else
                Text(
                  '급여 정보 없음',
                  style:
                      ResponsiveHelper.tinyStyle(context, color: AppColors.textTertiary), // [DU257] grey400(1.8)
                ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatTimeRange(DateTime? checkIn, DateTime? checkOut) {
    if (checkIn != null && checkOut != null) {
      return '${_timeFmt.format(checkIn)} ~ ${_timeFmt.format(checkOut)}';
    } else if (checkIn != null) {
      return '출근 ${_timeFmt.format(checkIn)}';
    }
    return '';
  }
}
