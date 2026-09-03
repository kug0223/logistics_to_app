import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../../../models/core/application_model.dart';
import '../../../models/core/attendance_model.dart';
import '../../../models/core/user_model.dart';
import '../../../theme/app_colors.dart';
import '../../../utils/format_helper.dart';
import '../../../utils/responsive_helper.dart';
import '../../../widgets/dialogs/wage/wage_detail_dialog.dart';
import '../../../screens/payroll/payslip_view_screen.dart';
import '../../../screens/payroll/payslip_period_helper.dart';
import '../../../screens/payroll/payslip_pdf_builder.dart';
import '../../../utils/toast_helper.dart';
import '../../../utils/dialog_helper.dart';
import '../../../services/payroll_payment_service.dart';
import 'package:printing/printing.dart';
import '../../../utils/navigation_helper.dart';
import '../../../widgets/common/app_page_scaffold.dart';
import '../../../widgets/common/notification_badge.dart';
import '../../../screens/common/notification_screen.dart';
import '../../../widgets/common/app_empty_state.dart';
import '../../../widgets/common/loading_widget.dart';

class PayrollWorkerDetailScreen extends StatefulWidget {
  final String businessId;
  final String workerId;
  final String workerName;
  final int year;
  final int month;

  const PayrollWorkerDetailScreen({
    super.key,
    required this.businessId,
    required this.workerId,
    required this.workerName,
    required this.year,
    required this.month,
  });

  @override
  State<PayrollWorkerDetailScreen> createState() =>
      _PayrollWorkerDetailScreenState();
}

class _PayrollWorkerDetailScreenState extends State<PayrollWorkerDetailScreen> {
  bool _isLoading = true;
  bool _isSettling = false;
  List<AttendanceModel> _records = [];
  String? _loadError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _loadRecords();
    });
  }

  Future<void> _loadRecords() async {
    if (mounted) setState(() { _isLoading = true; _loadError = null; });
    try {
      final monthStart = DateTime(widget.year, widget.month, 1);
      final monthEnd = DateTime(widget.year, widget.month + 1, 1);

      // confirmed + transferred 모두 표시 (송금 완료된 레코드도 포함)
      // CF 경유: attendance allow list: if false 이후 서버사이드 권한 검증
      final callable = FirebaseFunctions.instanceFor(region: 'asia-northeast3')
          .httpsCallable('callableGetAdminAttendances',
              options: HttpsCallableOptions(timeout: const Duration(seconds: 30)));
      final cfResult = await callable.call<Map<String, dynamic>>({
        'businessId': widget.businessId,
        'startMs': monthStart.millisecondsSinceEpoch,
        'endMs': monthEnd.millisecondsSinceEpoch,
        'userId': widget.workerId,
      });
      final cfItems = (cfResult.data['items'] as List<dynamic>? ?? []);
      const allowedStatuses = {
        AttendanceModel.wageConfirmed,
        AttendanceModel.wageTransferred,
      };
      final records = cfItems.whereType<Map>().map((e) {
        final m = Map<String, dynamic>.from(e);
        final id = m.remove('id') as String? ?? '';
        return AttendanceModel.tryFromMap(m, id);
      }).whereType<AttendanceModel>()
          .where((r) => allowedStatuses.contains(r.wageStatus))
          .toList();

      if (mounted) {
        _computeTotals(records);
        setState(() { _records = records; _isLoading = false; });
      }
    } catch (e) {
      if (mounted) setState(() { _loadError = e.toString(); _isLoading = false; });
    }
  }

  // 빌드마다 재계산 방지 — 레코드 로드 후 한 번만 계산
  int _totalPayout      = 0;
  int _totalWorkMinutes = 0;
  int _transferredAmount = 0; // 송금 완료 금액
  int _pendingAmount     = 0; // 미송금 금액 (확정됐지만 아직 미이체)

  int _netOf(AttendanceModel r) => r.wageDetail?.effectiveNetWage ?? 0;

  void _computeTotals(List<AttendanceModel> records) {
    _totalPayout      = records.fold(0, (acc, r) => acc + _netOf(r));
    _totalWorkMinutes = records.fold(0, (acc, r) => acc + (r.wageDetail?.workMinutes ?? 0));
    _transferredAmount = records
        .where((r) => r.wageStatus == AttendanceModel.wageTransferred)
        .fold(0, (acc, r) => acc + _netOf(r));
    // 미송금 = 쿼리에 포함된 레코드 중 아직 이체되지 않은 것 (wageConfirmed 상태)
    // ※ wageCalculated는 쿼리 자체에서 제외되므로 여기 포함되지 않음
    _pendingAmount = records
        .where((r) => r.wageStatus != AttendanceModel.wageTransferred)
        .fold(0, (acc, r) => acc + _netOf(r));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // [DESIGN-PATCH-1] GradientScaffold → AppPageScaffold — 관리자 Shell 정규화
    // parent screens(PayrollOverviewScreen, PayrollMonthScreen)와 동일 flat admin language
    return AppPageScaffold(
      title: '${widget.workerName} · ${widget.month}월',
      actions: [
        IconButton(
          icon: const Icon(Icons.refresh_rounded),
          onPressed: _loadRecords,
          color: AppColors.textSecondary,
        ),
        IconButton(
          icon: const Icon(Icons.home_outlined),
          onPressed: () => NavigationHelper.goHome(context),
          color: AppColors.textSecondary,
        ),
        NotificationBadge(
          child: IconButton(
            icon: const Icon(Icons.notifications_outlined),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const NotificationScreen()),
            ),
            color: AppColors.textSecondary,
          ),
        ),
        if (_records.isNotEmpty)
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (v) {
              if (v == 'interim') _showInterimSettlementDialog(context);
            },
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: 'interim',
                child: Row(children: [
                  Icon(Icons.monetization_on_outlined, size: 18),
                  SizedBox(width: 8),
                  Text('중간정산 처리'),
                ]),
              ),
            ],
          ),
      ],
      body: Column(
        children: [
          if (!_isLoading && _loadError == null) _buildSummaryHeader(context, theme),
          Expanded(child: _buildBody(context, theme)),
        ],
      ),
    );
  }

  Widget _buildSummaryHeader(BuildContext context, ThemeData theme) {
    final hours = _totalWorkMinutes ~/ 60;
    final mins  = _totalWorkMinutes % 60;
    final workTimeStr = mins == 0 ? '${hours}h' : '${hours}h ${mins}m';
    final hasTransfer = _transferredAmount > 0;
    final hasPending  = _pendingAmount > 0;

    return Container(
      color: theme.primaryColor.withValues(alpha: 0.06),
      padding: EdgeInsets.fromLTRB(
        ResponsiveHelper.spacing(context, 16),
        ResponsiveHelper.spacing(context, 14),
        ResponsiveHelper.spacing(context, 16),
        ResponsiveHelper.spacing(context, 12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── 1행: 실수령 합계(히어로) + 명세서 버튼
          Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
            Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.payments_outlined, size: 16, color: AppColors.successDark),
              SizedBox(width: ResponsiveHelper.spacing(context, 6)),
              Text(_formatAmount(_totalPayout),
                  style: ResponsiveHelper.titleStyle(context,
                      color: AppColors.successDark)),
            ]),
            SizedBox(width: ResponsiveHelper.spacing(context, 6)),
            Text('실수령 합계',
                style: ResponsiveHelper.tinyStyle(context, color: AppColors.grey700)),
            const Spacer(),
            if (_records.isNotEmpty)
              OutlinedButton.icon(
                onPressed: () => _showPayslipSheet(context),
                icon: Icon(Icons.receipt_long_outlined,
                    size: 14, color: theme.primaryColor),
                label: Text('명세서',
                    style: ResponsiveHelper.tinyStyle(context,
                        color: theme.primaryColor, fontWeight: FontWeight.w600)),
                style: OutlinedButton.styleFrom(
                  padding: EdgeInsets.symmetric(
                    horizontal: ResponsiveHelper.spacing(context, 10),
                    vertical: ResponsiveHelper.spacing(context, 5),
                  ),
                  side: BorderSide(color: theme.primaryColor.withValues(alpha: 0.4)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                ),
              ),
          ]),

          SizedBox(height: ResponsiveHelper.spacing(context, 8)),
          const Divider(height: 1, color: AppColors.grey200),
          SizedBox(height: ResponsiveHelper.spacing(context, 8)),

          // ── 2행: 송금 상태 (NEW)
          Row(children: [
            // 송금완료
            Row(mainAxisSize: MainAxisSize.min, children: [
              Container(
                width: 8, height: 8,
                decoration: BoxDecoration(
                  color: hasTransfer ? AppColors.success : AppColors.grey300,
                  shape: BoxShape.circle,
                ),
              ),
              SizedBox(width: ResponsiveHelper.spacing(context, 5)),
              Text('이체 완료',
                  style: ResponsiveHelper.tinyStyle(context, color: AppColors.grey500)),
              SizedBox(width: ResponsiveHelper.spacing(context, 4)),
              Text(
                _formatAmount(_transferredAmount),
                style: ResponsiveHelper.smallStyle(context,
                    color: hasTransfer ? AppColors.successDark : AppColors.grey400,
                    fontWeight: FontWeight.w700),
              ),
            ]),
            Container(
                width: 1, height: 12,
                color: AppColors.grey200,
                margin: EdgeInsets.symmetric(
                    horizontal: ResponsiveHelper.spacing(context, 12))),
            // 미송금
            Row(mainAxisSize: MainAxisSize.min, children: [
              Container(
                width: 8, height: 8,
                decoration: BoxDecoration(
                  color: hasPending ? AppColors.warning : AppColors.grey300,
                  shape: BoxShape.circle,
                ),
              ),
              SizedBox(width: ResponsiveHelper.spacing(context, 5)),
              Text('미이체', // [5C.2-P3] 용어 통일
                  style: ResponsiveHelper.tinyStyle(context, color: AppColors.grey500)),
              SizedBox(width: ResponsiveHelper.spacing(context, 4)),
              Text(
                _formatAmount(_pendingAmount),
                style: ResponsiveHelper.smallStyle(context,
                    color: hasPending ? AppColors.warningDark : AppColors.grey400,
                    fontWeight: FontWeight.w700),
              ),
            ]),
          ]),

          SizedBox(height: ResponsiveHelper.spacing(context, 8)),
          const Divider(height: 1, color: AppColors.grey200),
          SizedBox(height: ResponsiveHelper.spacing(context, 8)),

          // ── 3행: 근무일수 | 총 근무시간
          // 외부 Row에 Flexible 없으면 장기근무(100시간+) 시 overflow 가능
          Row(children: [
            Flexible(
              fit: FlexFit.loose,
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.calendar_today_outlined,
                    size: 12, color: theme.primaryColor),
                SizedBox(width: ResponsiveHelper.spacing(context, 4)),
                Text('${_records.length}일',
                    style: ResponsiveHelper.smallStyle(context,
                        color: theme.primaryColor, fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis),
                SizedBox(width: ResponsiveHelper.spacing(context, 4)),
                Text('근무일수',
                    style: ResponsiveHelper.tinyStyle(context, color: AppColors.grey700),
                    overflow: TextOverflow.ellipsis),
              ]),
            ),
            Container(
                width: 1, height: 14,
                color: AppColors.grey200,
                margin: EdgeInsets.symmetric(
                    horizontal: ResponsiveHelper.spacing(context, 12))),
            Flexible(
              fit: FlexFit.loose,
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.schedule_outlined, size: 12, color: theme.primaryColor),
                SizedBox(width: ResponsiveHelper.spacing(context, 4)),
                Text(workTimeStr,
                    style: ResponsiveHelper.smallStyle(context,
                        color: theme.primaryColor, fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis),
                SizedBox(width: ResponsiveHelper.spacing(context, 4)),
                Text('총 근무시간',
                    style: ResponsiveHelper.tinyStyle(context, color: AppColors.grey700),
                    overflow: TextOverflow.ellipsis),
              ]),
            ),
          ]),
        ],
      ),
    );
  }

  Widget _buildBody(BuildContext context, ThemeData theme) {
    if (_isLoading) return const LoadingWidget();
    if (_loadError != null) {
      return AppEmptyState(
        icon: Icons.error_outline,
        title: '데이터를 불러오지 못했습니다',
        iconColor: AppColors.error,
        action: TextButton.icon(
          onPressed: _loadRecords,
          icon: const Icon(Icons.refresh),
          label: const Text('다시 시도'),
        ),
      );
    }
    if (_records.isEmpty) {
      return AppEmptyState(
        icon: Icons.receipt_long_outlined,
        title: '확정된 급여 내역이 없습니다',
        subtitle: '${widget.year}년 ${widget.month}월 확정된 급여가 없습니다',
      );
    }

    return ListView.separated(
      padding: ResponsiveHelper.listPadding(context),
      itemCount: _records.length,
      separatorBuilder: (_, __) =>
          SizedBox(height: ResponsiveHelper.spacing(context, 8)),
      itemBuilder: (context, i) => _buildRecordTile(context, theme, _records[i]),
    );
  }

  Widget _buildRecordTile(BuildContext context, ThemeData theme, AttendanceModel record) {
    final wage = record.wageDetail;
    final workDate = record.workDate;
    final dateStr = '${workDate.month}/${workDate.day} (${_weekday(workDate.weekday)})';
    final netWage = wage?.effectiveNetWage ?? 0;

    return GestureDetector(
      onTap: () => _openWageDetail(context, record),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 4,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        padding: EdgeInsets.symmetric(
          horizontal: ResponsiveHelper.spacing(context, 16),
          vertical: ResponsiveHelper.spacing(context, 14),
        ),
        child: Row(
          children: [
            // 날짜
            SizedBox(
              width: ResponsiveHelper.spacing(context, 70),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    dateStr,
                    style: ResponsiveHelper.bodyStyle(context).copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                    // 70px SizedBox 초과 시 2줄로 wrap → 행 높이 불일치 방지
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (record.workType.isNotEmpty)
                    Text(
                      record.workType,
                      style: ResponsiveHelper.tinyStyle(context).copyWith(
                        color: AppColors.grey500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            SizedBox(width: ResponsiveHelper.spacing(context, 12)),
            // 근무 시간
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (record.businessName.isNotEmpty)
                    Text(
                      record.businessName,
                      style: ResponsiveHelper.tinyStyle(context,
                          color: AppColors.grey500),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  if (record.checkIn != null && record.checkOut != null)
                    Text(
                      '${record.checkIn} ~ ${record.checkOut}',
                      style: ResponsiveHelper.smallStyle(context).copyWith(
                        color: AppColors.grey600,
                      ),
                    ),
                  if (wage != null)
                    Text(
                      '실근무 ${wage.workMinutes ~/ 60}h ${wage.workMinutes % 60}m',
                      style: ResponsiveHelper.tinyStyle(context).copyWith(
                        color: AppColors.grey400,
                      ),
                    ),
                ],
              ),
            ),
            // 금액 + 배지
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  _formatAmount(netWage),
                  style: ResponsiveHelper.bodyStyle(context).copyWith(
                    fontWeight: FontWeight.bold,
                    color: AppColors.successDark,
                  ),
                ),
                SizedBox(height: ResponsiveHelper.spacing(context, 4)),
                // 송금 상태 배지
                _WageStatusBadge(wageStatus: record.wageStatus),
                SizedBox(height: ResponsiveHelper.spacing(context, 4)),
                // 임금명세서 버튼
                if (record.wageDetail != null)
                  GestureDetector(
                    onTap: () => _openPayslip(context, record),
                    child: Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: ResponsiveHelper.spacing(context, 6),
                        vertical: ResponsiveHelper.spacing(context, 2),
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.infoBg,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.receipt_outlined,
                            size: ResponsiveHelper.iconSize(context, 11),
                            color: AppColors.infoDark),
                        SizedBox(width: ResponsiveHelper.spacing(context, 2)),
                        Text('명세서',
                            style: ResponsiveHelper.tinyStyle(context,
                                color: AppColors.infoDark)),
                      ]),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openWageDetail(BuildContext context, AttendanceModel record) async {
    if (record.wageDetail == null) return;

    // ApplicationModel + UserModel 병렬 조회
    ApplicationModel? app;
    UserModel? user;
    try {
      final docs = await Future.wait([
        FirebaseFirestore.instance
            .collection('applications')
            .doc(record.applicationId)
            .get(),
        FirebaseFirestore.instance
            .collection('users')
            .doc(record.userId)
            .get(),
      ]);
      if (!context.mounted) return;
      final appDoc = docs[0];
      final userDoc = docs[1];
      if (appDoc.exists) app = ApplicationModel.tryFromFirestore(appDoc);
      final userData = userDoc.data();
      if (userDoc.exists && userData != null) {
        user = UserModel.fromMap(userData, userDoc.id);
      }
    } catch (e) {
      debugPrint('❌ 지원서/사용자 정보 로드 실패: $e');
      if (context.mounted) ToastHelper.showError('데이터를 불러오는데 실패했습니다.');
      return;
    }

    if (app == null || !context.mounted) return;

    await WageDetailDialog.show(
      context: context,
      app: app,
      user: user,
      attendance: record,
      wage: record.wageDetail!,
      mode: WageDialogMode.confirmed,
      businessName: app.businessName,
      scheduledBreakMinutes: record.wageDetail!.scheduledBreakMinutes,
    );
  }

  /// 중간정산 처리 다이얼로그
  Future<void> _showInterimSettlementDialog(BuildContext ctx) async {
    if (_isSettling) return;
    // 확정 상태 (아직 이체 안 된) 기록만 대상 — 날짜 오름차순 정렬 후 first/last 사용
    final settleableRecords = _records.where((r) =>
        r.wageStatus == AttendanceModel.wageConfirmed &&
        r.wageDetail != null)
      .toList()
      ..sort((a, b) => a.workDate.compareTo(b.workDate));

    if (settleableRecords.isEmpty) {
      ToastHelper.showWarning('중간정산 가능한 확정 급여가 없습니다');
      return;
    }

    // 전체 금액 합산
    int totalNet = settleableRecords.fold(0, (acc, r) => acc + _netOf(r));

    setState(() => _isSettling = true);
    try {
      final ok = await DialogHelper.showConfirm(
        ctx,
        title: '중간정산 처리',
        message: '${widget.workerName}님의 확정 급여 ${settleableRecords.length}건을\n'
            '중간정산 처리하시겠습니까?\n\n'
            '대상 금액: ${FormatHelper.formatWage(totalNet)}\n'
            '처리 후 "이체 완료" 상태로 변경됩니다.',
        confirmText: '이체 완료 처리', // [5C.2-P3] ACTION 용어 통일
        cancelText: '취소',
      );
      if (ok != true || !mounted) return;
      // [CF-MIGRATION 2026-08-10] 클라이언트 직접 쓰기 → CF 경유로 전환
      // attendance 이체 + 정산 문서 생성을 서버에서 원자적으로 처리
      final svc = PayrollPaymentService();
      await svc.adminDirectSettlement(
        businessId:    widget.businessId,
        workerId:      widget.workerId,
        workerName:    widget.workerName,
        businessName:  settleableRecords.first.businessName,
        applicationId: settleableRecords.first.applicationId,
        attendanceIds: settleableRecords.map((r) => r.id).toList(),
        netAmount:     totalNet,
      );

      // [D-003] async gap 후 mounted 체크
      if (!mounted) return;
      ToastHelper.showSuccess('중간정산이 처리되었습니다');
      await _loadRecords();
    } catch (e) {
      if (mounted) ToastHelper.showError('처리에 실패했습니다: $e');
      // [WARN-PAY-01] 이체 성공 + 상태 업데이트 실패 시 화면 갱신 — 재시도 시 zombie PENDING 방지
      if (mounted) await _loadRecords();
    } finally {
      if (mounted) setState(() => _isSettling = false);
    }
  }

  /// 임금명세서 발행 유형/기간 선택 바텀시트
  Future<void> _showPayslipSheet(BuildContext ctx) async {
    await DialogHelper.showSheet(
      ctx,
      isScrollControlled: true,
      builder: (_) => _PayslipIssueSheet(
        year: widget.year,
        month: widget.month,
        workerName: widget.workerName,
        records: _records,
      ),
    );
  }

  /// 일별 임금명세서 화면으로 이동 (workerName을 알고 있으므로 Firestore 재조회 최소화)
  void _openPayslip(BuildContext context, AttendanceModel record) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PayslipViewScreen(
          attendance: record,
          workerNameOverride: widget.workerName,
        ),
      ),
    );
  }

  String _formatAmount(int amount) =>
      amount == 0 ? '-' : FormatHelper.formatWage(amount);

  String _weekday(int wd) {
    const days = ['월', '화', '수', '목', '금', '토', '일'];
    return days[(wd - 1) % 7];
  }
}

// ─── 임금명세서 발행 유형/기간 선택 바텀시트 ─────────────────────────

class _PayslipIssueSheet extends StatefulWidget {
  final int year;
  final int month;
  final String workerName;
  final List<AttendanceModel> records;

  const _PayslipIssueSheet({
    required this.year,
    required this.month,
    required this.workerName,
    required this.records,
  });

  @override
  State<_PayslipIssueSheet> createState() => _PayslipIssueSheetState();
}

class _PayslipIssueSheetState extends State<_PayslipIssueSheet> {
  PayslipIssueType _issueType = PayslipIssueType.monthly;
  int _selectedWeekNo = 1;
  bool _isGenerating = false;
  // [PERF-8] 주차 목록·카운트를 initState에서 1회만 계산 — build()마다 weeksOfMonth·filterByWeek 반복 방지
  late List<WeekPeriod> _weeks;
  late Map<int, int> _weekRecordCounts; // weekNo → records.length

  @override
  void initState() {
    super.initState();
    _weeks = PayslipPeriodHelper.weeksOfMonth(widget.year, widget.month);
    if (_weeks.isNotEmpty) _selectedWeekNo = _weeks.first.weekNo;
    _weekRecordCounts = {
      for (final w in _weeks)
        w.weekNo: PayslipPeriodHelper.filterByWeek(widget.records, w).length,
    };
  }

  List<AttendanceModel> get _filteredRecords {
    if (_issueType == PayslipIssueType.monthly) return widget.records;
    if (_weeks.isEmpty) return widget.records;
    final week = _weeks.firstWhere(
      (w) => w.weekNo == _selectedWeekNo,
      orElse: () => _weeks.first,
    );
    return PayslipPeriodHelper.filterByWeek(widget.records, week);
  }

  Future<void> _generate() async {
    final filtered = _filteredRecords;
    if (filtered.isEmpty) {
      ToastHelper.showWarning('해당 기간에 확정된 급여 내역이 없습니다');
      return;
    }
    final week = (_issueType == PayslipIssueType.weekly && _weeks.isNotEmpty)
        ? _weeks.firstWhere((w) => w.weekNo == _selectedWeekNo,
            orElse: () => _weeks.first)
        : null;

    final data = AggregatedPayslipData.fromRecords(
      records: filtered,
      workerName: widget.workerName,
      issueType: _issueType,
      year: widget.year,
      month: widget.month,
      weekNo: week?.weekNo,
      periodStart: week?.start ?? DateTime(widget.year, widget.month, 1),
      periodEnd: week?.end ?? DateTime(widget.year, widget.month + 1, 0),
    );

    setState(() => _isGenerating = true);
    try {
      final bytes = await PayslipPdfBuilder.buildAggregated(data);
      final filename = _issueType == PayslipIssueType.weekly
          ? '${widget.workerName}_${widget.month}월$_selectedWeekNo주차_임금명세서.pdf'
          : '${widget.workerName}_${widget.year}년${widget.month}월_임금명세서.pdf';
      if (!mounted) return;
      // [UX-FIX 2026-07-16] Navigator.pop을 sharePdf 이후로 이동
      //   pop이 먼저 실행되면 위젯이 언마운트 → catch의 if(mounted) 항상 false → 에러 토스트 무음 소멸
      await Printing.sharePdf(bytes: bytes, filename: filename);
      if (!mounted) return;
      Navigator.pop(context);
    } catch (e) {
      if (mounted) ToastHelper.showError('임금명세서 생성에 실패했습니다');
    } finally {
      if (mounted) setState(() => _isGenerating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      top: false,
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: EdgeInsets.fromLTRB(
          ResponsiveHelper.spacing(context, 20),
          ResponsiveHelper.spacing(context, 8),
          ResponsiveHelper.spacing(context, 20),
          ResponsiveHelper.spacing(context, 16),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36, height: 4,
                margin: EdgeInsets.only(bottom: ResponsiveHelper.spacing(context, 16)),
                decoration: BoxDecoration(
                    color: AppColors.grey300,
                    borderRadius: BorderRadius.circular(2)),
              ),
            ),
            Text('임금명세서 발행',
                style: ResponsiveHelper.subtitleStyle(context)
                    .copyWith(fontWeight: FontWeight.bold)),
            Text(
              '${widget.workerName} · ${widget.year}년 ${widget.month}월',
              style: ResponsiveHelper.smallStyle(context, color: AppColors.grey500),
            ),
            SizedBox(height: ResponsiveHelper.spacing(context, 20)),

            Text('발행 유형',
                style: ResponsiveHelper.smallStyle(context)
                    .copyWith(fontWeight: FontWeight.w600)),
            SizedBox(height: ResponsiveHelper.spacing(context, 8)),
            Row(children: [
              _TypeChip(
                label: '월간',
                selected: _issueType == PayslipIssueType.monthly,
                onTap: () => setState(() => _issueType = PayslipIssueType.monthly),
                color: theme.primaryColor,
              ),
              SizedBox(width: ResponsiveHelper.spacing(context, 8)),
              _TypeChip(
                label: '주간',
                selected: _issueType == PayslipIssueType.weekly,
                onTap: () => setState(() => _issueType = PayslipIssueType.weekly),
                color: theme.primaryColor,
              ),
            ]),

            if (_issueType == PayslipIssueType.weekly) ...[
              SizedBox(height: ResponsiveHelper.spacing(context, 16)),
              Text('주차 선택',
                  style: ResponsiveHelper.smallStyle(context)
                      .copyWith(fontWeight: FontWeight.w600)),
              SizedBox(height: ResponsiveHelper.spacing(context, 8)),
              Wrap(
                spacing: ResponsiveHelper.spacing(context, 8),
                runSpacing: ResponsiveHelper.spacing(context, 8),
                children: _weeks.map((w) {
                  final cnt = _weekRecordCounts[w.weekNo] ?? 0; // [PERF-8] 캐시 사용
                  return _TypeChip(
                    label: '${w.weekNo}주차',
                    selected: _selectedWeekNo == w.weekNo,
                    onTap: cnt > 0
                        ? () => setState(() => _selectedWeekNo = w.weekNo)
                        : null,
                    color: theme.primaryColor,
                    subtitle: cnt > 0 ? '$cnt일' : '없음',
                    disabled: cnt == 0,
                  );
                }).toList(),
              ),
            ],

            SizedBox(height: ResponsiveHelper.spacing(context, 20)),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isGenerating ? null : _generate,
                icon: _isGenerating
                    ? const SizedBox(
                        width: 16, height: 16,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2))
                    : const Icon(Icons.picture_as_pdf_outlined),
                label: Text(_isGenerating ? '생성 중...' : 'PDF 생성 및 공유'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: theme.primaryColor,
                  foregroundColor: Colors.white,
                  padding: EdgeInsets.symmetric(
                      vertical: ResponsiveHelper.spacing(context, 14)),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  elevation: 0,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── 유형/주차 선택 칩 ───────────────────────────────────────────

class _TypeChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final Color color;
  final String? subtitle;
  final bool disabled;

  const _TypeChip({
    required this.label,
    required this.selected,
    required this.onTap,
    required this.color,
    this.subtitle,
    this.disabled = false,
  });

  @override
  Widget build(BuildContext context) {
    final bg = disabled
        ? AppColors.grey100
        : selected
            ? color.withValues(alpha: 0.12)
            : Colors.white;
    final borderColor = disabled
        ? AppColors.grey300
        : selected
            ? color
            : AppColors.grey300;
    final textColor = disabled
        ? AppColors.grey400
        : selected
            ? color
            : AppColors.grey700;

    return GestureDetector(
      onTap: disabled ? null : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: EdgeInsets.symmetric(
          horizontal: ResponsiveHelper.spacing(context, 14),
          vertical: ResponsiveHelper.spacing(context, 8),
        ),
        decoration: BoxDecoration(
          color: bg,
          border: Border.all(color: borderColor, width: selected ? 1.5 : 1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label,
                textAlign: TextAlign.center,
                style: ResponsiveHelper.smallStyle(context, color: textColor)
                    .copyWith(
                        fontWeight: selected ? FontWeight.w700 : FontWeight.normal)),
            if (subtitle != null) ...[
              SizedBox(height: ResponsiveHelper.spacing(context, 2)),
              Text(subtitle!,
                  style: ResponsiveHelper.tinyStyle(context,
                      color: disabled ? AppColors.grey400 : AppColors.grey500)),
            ],
          ],
        ),
      ),
    );
  }
}

/// 송금 상태 배지 (각 근무 카드에 표시)
class _WageStatusBadge extends StatelessWidget {
  final String wageStatus;
  const _WageStatusBadge({required this.wageStatus});

  @override
  Widget build(BuildContext context) {
    final isTransferred = wageStatus == AttendanceModel.wageTransferred;
    final color = isTransferred ? AppColors.success : AppColors.warning;
    final label = isTransferred ? '이체 완료' : '미이체'; // [5C.2-P3] 용어 통일
    final icon  = isTransferred
        ? Icons.check_circle_outline
        : Icons.schedule_outlined;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 6),
        vertical: ResponsiveHelper.spacing(context, 2),
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon,
            size: ResponsiveHelper.iconSize(context, 10), color: color),
        SizedBox(width: ResponsiveHelper.spacing(context, 3)),
        Text(label,
            style: ResponsiveHelper.tinyStyle(context,
                color: color, fontWeight: FontWeight.w600)),
      ]),
    );
  }
}
