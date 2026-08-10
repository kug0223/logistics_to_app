// lib/screens/user/interim_settlement_request_screen.dart
//
// 근로자가 급여 확정된 출근기록 중 일부를 선택해 중간정산을 요청하는 화면.
// 서버사이드 검증: callableRequestInterimSettlement CF (ownership, duplicate 방어).

import 'dart:async';

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
import '../../utils/toast_helper.dart';
import '../../widgets/common/app_batch_action_bar.dart';
import '../../widgets/common/app_empty_state.dart';
import '../../widgets/common/gradient_scaffold.dart';
import '../../widgets/common/loading_widget.dart';

class InterimSettlementRequestScreen extends StatefulWidget {
  final ApplicationModel app;

  const InterimSettlementRequestScreen({super.key, required this.app});

  @override
  State<InterimSettlementRequestScreen> createState() =>
      _InterimSettlementRequestScreenState();
}

class _InterimSettlementRequestScreenState
    extends State<InterimSettlementRequestScreen> {
  // ─── 포맷터 캐싱 ─────────────────────────────────────────────
  static final _timeFmt = DateFormat('HH:mm');

  final FirestoreService _firestoreService = FirestoreService();
  final PayrollPaymentService _payService = PayrollPaymentService();
  final TextEditingController _reasonController = TextEditingController();

  List<AttendanceModel> _records = [];
  final Set<String> _selectedIds = {};
  int _cachedNetAmount = 0; // _selectedIds 변경 시 갱신 — build()마다 O(n) 재계산 방지
  bool _isLoading = false; // 초기값 false — initState에서 _loadConfirmedAttendances() 첫 호출 시 재진입 방어에 걸리지 않도록
  bool _isSubmitting = false;

  // 로드 대상 최근 개월 수 (최대 3개월치)
  static const int _monthsToLoad = 3;

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
          _firestoreService.getMyMonthlyAttendances(
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
      });
    } catch (e) {
      debugPrint('❌ 중간정산 출근기록 로드 실패: $e');
      if (mounted) setState(() => _isLoading = false);
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
    return GradientScaffold(
      title: '중간정산 요청 · ${widget.app.businessName}',
      onRefresh: _loadConfirmedAttendances,
      body: _isLoading
          ? const LoadingWidget(message: '출근기록 로딩 중...')
          : _records.isEmpty
              ? AppEmptyState(
                  icon: Icons.account_balance_wallet_outlined,
                  title: '정산 가능한 출근기록이 없습니다',
                  subtitle: '급여 확정된 근무일이 없거나\n이미 모두 정산 처리되었습니다.',
                  action: TextButton(
                    onPressed: _loadConfirmedAttendances,
                    child: const Text('새로고침'),
                  ),
                )
              : Column(
                  children: [
                    // 안내 배너
                    _buildInfoBanner(),

                    // 이유 입력
                    Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: ResponsiveHelper.spacing(context, 16),
                        vertical: ResponsiveHelper.spacing(context, 8),
                      ),
                      child: TextField(
                        controller: _reasonController,
                        decoration: InputDecoration(
                          hintText: '요청 사유 (선택사항)',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(color: AppColors.grey300),
                          ),
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: ResponsiveHelper.spacing(context, 12),
                            vertical: ResponsiveHelper.spacing(context, 10),
                          ),
                          prefixIcon: Icon(Icons.edit_note,
                              color: AppColors.grey500,
                              size: ResponsiveHelper.iconSize(context, 20)),
                        ),
                        style: ResponsiveHelper.bodyStyle(context),
                        maxLines: 2,
                        maxLength: 100,
                      ),
                    ),

                    // 출근기록 목록
                    Expanded(
                      child: ListView.builder(
                        padding: EdgeInsets.symmetric(
                          horizontal: ResponsiveHelper.spacing(context, 12),
                          vertical: ResponsiveHelper.spacing(context, 8),
                        ),
                        itemCount: _records.length,
                        itemBuilder: (ctx, i) => _buildAttendanceCard(_records[i]),
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
    );
  }

  Widget _buildInfoBanner() {
    return Container(
      margin: EdgeInsets.all(ResponsiveHelper.spacing(context, 16)),
      padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 12)),
      decoration: BoxDecoration(
        color: AppColors.tealBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.teal.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline,
              color: AppColors.tealDark,
              size: ResponsiveHelper.iconSize(context, 16)),
          SizedBox(width: ResponsiveHelper.spacing(context, 8)),
          Expanded(
            child: Text(
              '급여 확정된 근무일 중 정산받을 날짜를 선택하세요.\n'
              '관리자 승인 후 이체 예정일이 안내됩니다.',
              style: ResponsiveHelper.tinyStyle(context, color: AppColors.tealDark),
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
        decoration: BoxDecoration(
          color: selected
              ? AppColors.tealBg
              : hasWage
                  ? Colors.white
                  : AppColors.grey50,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? AppColors.teal : AppColors.grey200,
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
                color: selected
                    ? AppColors.teal
                    : hasWage
                        ? AppColors.grey400
                        : AppColors.grey300,
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
                        color: hasWage ? null : AppColors.grey400,
                      ),
                    ),
                    if (att.checkInAt != null || att.checkOutAt != null)
                      Text(
                        _formatTimeRange(att.checkInAt, att.checkOutAt),
                        style: ResponsiveHelper.tinyStyle(
                            context, color: AppColors.grey500),
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
                        color: selected ? AppColors.tealDark : AppColors.grey800,
                      ),
                    ),
                    if (totalAmount != netWage)
                      Text(
                        '세전 ${FormatHelper.formatWage(totalAmount)}',
                        style: ResponsiveHelper.tinyStyle(
                            context, color: AppColors.grey500),
                      ),
                  ],
                )
              else
                Text(
                  '급여 정보 없음',
                  style:
                      ResponsiveHelper.tinyStyle(context, color: AppColors.grey400),
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
