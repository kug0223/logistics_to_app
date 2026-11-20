import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../../../models/core/application_model.dart';
import '../../../models/core/attendance_model.dart';
import '../../../models/core/user_model.dart';
import '../../../models/core/wage_detail_model.dart';
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
import '../../../services/firestore_service.dart';
import '../../../utils/person_label.dart';
import '../../../utils/text_layout.dart';

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

/// [PAYROLL-DETAIL.32] 시험 전용 — 원장 조회(callableGetAdminAttendances payload → items)와
///   인력번호 조회를 바꿔 끼운다. production 은 둘 다 null.
@visibleForTesting
class PayrollWorkerDetailScreenTestHooks {
  PayrollWorkerDetailScreenTestHooks._();
  static Future<List<Map<String, dynamic>>> Function(Map<String, dynamic> payload)? attendance;
  static Future<String?> Function(String businessId, String workerId)? personNo;
  static void reset() {
    attendance = null;
    personNo = null;
  }
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
      _loadPersonNo();
    });
  }

  /// [R7-PRE1A.1] 이 사업장에서의 사람 번호 — 파일명에 들어간다.
  ///
  ///   호출부에서 받아 오지 않고 여기서 직접 읽는다. 진입 경로가 여럿이라
  ///   한 곳이라도 빠지면 그 경로로 만든 파일만 번호가 없어지고, 그러면
  ///   같은 사람의 파일이 두 이름으로 남는다.
  ///
  ///   실패해도 화면은 그대로다 — 번호가 없으면 파일명에서 빠질 뿐이다.
  String? _personNo;

  Future<void> _loadPersonNo() async {
    try {
      if (PayrollWorkerDetailScreenTestHooks.personNo != null) {
        final no = await PayrollWorkerDetailScreenTestHooks.personNo!(widget.businessId, widget.workerId);
        if (!mounted || no == null) return;
        setState(() => _personNo = no);
        return;
      }
      final users = await FirestoreService().getUsersBatch(
        [widget.workerId],
        businessId: widget.businessId,
        purpose: FirestoreService.purposeWorkerDirectory,
      );
      final label = users[widget.workerId]?.personLabel;
      if (!mounted || label == null) return;
      setState(() => _personNo = label);
    } catch (e) {
      debugPrint('⚠️ 근로자번호 조회 실패 (파일명에서 생략): $e');
    }
  }

  /// [PAYROLL-DETAIL.32] 새로고침·다시 시도 — 원장과 함께, 실패로 비어 있던 인력번호도 다시 읽는다
  ///   (기기: 조회 실패 뒤 회복했는데 머리말의 P-번호만 빠져 있었다).
  void _reload() {
    _loadRecords();
    if (_personNo == null) _loadPersonNo();
  }

  Future<void> _loadRecords() async {
    if (mounted) setState(() { _isLoading = true; _loadError = null; });
    try {
      // [TZ-FIX] KST 월 경계 정규화 — device-local timezone 독립적
      // attendance.workDate는 KST 자정을 UTC로 저장하므로 query boundary도 동일 기준 필요.
      // DateTime.utc(y,m,1).subtract(9h) = KST m월 1일 00:00:00의 UTC instant
      // Dart: DateTime.utc(year, 13, 1) → 자동 연도 올림 처리
      final monthStart = DateTime.utc(widget.year, widget.month, 1)
          .subtract(const Duration(hours: 9));
      final monthEnd = DateTime.utc(widget.year, widget.month + 1, 1)
          .subtract(const Duration(hours: 9));

      // confirmed + transferred 모두 표시 (송금 완료된 레코드도 포함)
      // CF 경유: attendance allow list: if false 이후 서버사이드 권한 검증
      final payload = <String, dynamic>{
        'businessId': widget.businessId,
        'startMs': monthStart.millisecondsSinceEpoch,
        'endMs': monthEnd.millisecondsSinceEpoch,
        'userId': widget.workerId,
      };
      final List<dynamic> cfItems;
      if (PayrollWorkerDetailScreenTestHooks.attendance != null) {
        cfItems = await PayrollWorkerDetailScreenTestHooks.attendance!(payload);
      } else {
        final callable = FirebaseFunctions.instanceFor(region: 'asia-northeast3')
            .httpsCallable('callableGetAdminAttendances',
                options: HttpsCallableOptions(timeout: const Duration(seconds: 30)));
        final cfResult = await callable.call<Map<String, dynamic>>(payload);
        cfItems = (cfResult.data['items'] as List<dynamic>? ?? []);
      }
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
          .toList()
        // [PAYROLL-DETAIL.32] 근무일·출근 순 — 같은 날 두 근무가 오전·오후 순서로 읽힌다.
        ..sort((a, b) {
          final d = a.workDate.compareTo(b.workDate);
          if (d != 0) return d;
          return (a.checkInAt ?? a.workDate).compareTo(b.checkInAt ?? b.workDate);
        });

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
  /// [PAYROLL-DETAIL.32] 개요(서버 srvPayrollContribution)가 세는 확정 근무 — 노쇼·결근 0원 제외.
  ///   이 화면은 그 기록도 **목록에 보인다**(지급 없음 표시). 건수만 개요와 같은 식으로 센다.
  int _payableCount = 0;
  int _nonPayableCount = 0;

  int _netOf(AttendanceModel r) => r.wageDetail?.effectiveNetWage ?? 0;

  void _computeTotals(List<AttendanceModel> records) {
    _nonPayableCount = records.where((r) => r.isNonPayableZero).length;
    _payableCount = records.length - _nonPayableCount;
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
          onPressed: _reload,
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
          // [PAYROLL-DETAIL.32] 누구의 어느 달인가 — 개요에서 누른 사람과 같은지 인력번호로 확인한다
          //   (이름만으로는 동명이인을 가를 수 없다). 번호를 모르면 이름·기간만.
          Text(
            TextLayout.phrases([
              if (_personNo != null) _personNo!,
              widget.workerName,
              '${widget.year}년 ${widget.month}월',
            ].join(' · ')),
            semanticsLabel: [
              if (_personNo != null) _personNo!,
              widget.workerName,
              '${widget.year}년 ${widget.month}월',
            ].join(' · '),
            style: ResponsiveHelper.smallStyle(context,
                color: AppColors.grey700, fontWeight: FontWeight.w600),
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 6)),
          // ── 1행: 실수령 합계(히어로) + 명세서 버튼
          // [PAYROLL-DETAIL.32] 큰 글자에서 한 줄로 넘치지 않게 Wrap — 금액과 라벨은 한 덩어리.
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: ResponsiveHelper.spacing(context, 8),
            runSpacing: ResponsiveHelper.spacing(context, 6),
            children: [
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
          // [PAYROLL-DETAIL.32] 좁은 폭·큰 글자에서 두 묶음이 넘치지 않게 Wrap(구분선은 줄이 바뀌면 빠진다).
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: ResponsiveHelper.spacing(context, 12),
            runSpacing: ResponsiveHelper.spacing(context, 4),
            children: [
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

          // ── 3행: 확정 근무 건수 | 총 근무시간
          // [R7-P1-5 PAY-1] `_records` 는 이 달의 **확정·이체된 근무 기록**이다
          //   (`allowedStatuses`). 두 가지를 라벨이 말하지 않고 있었다.
          //   1) 한 사람이 같은 날 겹치지 않는 두 근무를 확정받을 수 있어
          //      기록 수는 달력 날짜 수가 아니다 — `N일` 은 없는 날을 센다.
          //   2) 아직 확정되지 않은 근무는 여기 없다. 실제로 4일 일했는데
          //      2건만 확정돼 있으면 `2일` 로 보였고, 그것이 근무일 오류처럼
          //      읽혔다. 세는 대상을 이름에 넣어 그 오해를 없앤다.
          // [PAYROLL-DETAIL.32] 320·1.3 / 392·2.0 에서 이 Row 가 13~47px 넘쳤다(안쪽 Row 가 줄지 않는다).
          //   두 묶음을 Wrap 으로 — 폭이 모자라면 아래 줄로 내려간다. 숫자와 라벨은 한 묶음.
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: ResponsiveHelper.spacing(context, 16),
            runSpacing: ResponsiveHelper.spacing(context, 4),
            children: [
              Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.calendar_today_outlined,
                    size: 12, color: theme.primaryColor),
                SizedBox(width: ResponsiveHelper.spacing(context, 4)),
                Text('$_payableCount건',
                    style: ResponsiveHelper.smallStyle(context,
                        color: theme.primaryColor, fontWeight: FontWeight.w600)),
                SizedBox(width: ResponsiveHelper.spacing(context, 4)),
                Text('확정 근무',
                    style: ResponsiveHelper.tinyStyle(context, color: AppColors.grey700)),
              ]),
              Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.schedule_outlined, size: 12, color: theme.primaryColor),
                SizedBox(width: ResponsiveHelper.spacing(context, 4)),
                Text(workTimeStr,
                    style: ResponsiveHelper.smallStyle(context,
                        color: theme.primaryColor, fontWeight: FontWeight.w600)),
                SizedBox(width: ResponsiveHelper.spacing(context, 4)),
                Text('총 근무시간',
                    style: ResponsiveHelper.tinyStyle(context, color: AppColors.grey700)),
              ]),
            ],
          ),
          // [PAYROLL-DETAIL.32] 노쇼·결근 0원 기록은 지급 대상이 아니다 — 개요의 '확정 근무 N건'과 같은 식으로
          //   세고, 목록에 남아 있는 이유를 한 줄로 말한다(숨기지 않는다).
          if (_nonPayableCount > 0) ...[
            SizedBox(height: ResponsiveHelper.spacing(context, 6)),
            Text(
              TextLayout.phrases('노쇼·결근 $_nonPayableCount건 · 지급 없음(건수·합계에서 제외)'),
              semanticsLabel: '노쇼·결근 $_nonPayableCount건 · 지급 없음(건수·합계에서 제외)',
              style: ResponsiveHelper.tinyStyle(context, color: AppColors.grey600),
            ),
          ],
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
          onPressed: _reload,
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
    // [PAYROLL-DETAIL.32] workDate 는 KST 자정 instant 다 — 기기 시간대(GMT 등)로 읽으면 하루 앞 날짜가 된다.
    final workDate = FormatHelper.toKstDate(record.workDate);
    final dateStr = '${workDate.month}/${workDate.day} (${_weekday(workDate.weekday)})';
    final netWage = wage?.effectiveNetWage ?? 0;
    final nonPayable = record.isNonPayableZero;
    return _buildRecordTileBody(context, theme, record,
        wage: wage, dateStr: dateStr, netWage: netWage, nonPayable: nonPayable);
  }

  /// [PAYROLL-DETAIL.32] 근무 카드 — 날짜·업무·시간을 왼쪽에 다 보이고, 금액·상태·명세서는 오른쪽.
  ///   폭이 모자라면(큰 글자·좁은 폭) 금액·상태·명세서를 아래 줄로 내린다. 날짜·시간·금액을 말줄임하지 않는다.
  Widget _buildRecordTileBody(BuildContext context, ThemeData theme, AttendanceModel record, {
    required WageDetailModel? wage,
    required String dateStr,
    required int netWage,
    required bool nonPayable,
  }) {
    final head = [dateStr, if (record.workType.isNotEmpty) record.workType].join(' · ');
    final time = (record.checkIn != null && record.checkOut != null)
        ? TextLayout.range(record.checkIn!, record.checkOut!)
        : null;
    final amountText = FormatHelper.formatWage(netWage); // 확정 0원은 '0원' — '-'(모름)와 구분
    final info = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(TextLayout.phrases(head),
            semanticsLabel: head,
            style: ResponsiveHelper.bodyStyle(context).copyWith(fontWeight: FontWeight.w600)),
        if (time != null)
          Text(time,
              semanticsLabel: '${record.checkIn} ~ ${record.checkOut}',
              style: ResponsiveHelper.smallStyle(context).copyWith(color: AppColors.grey700)),
        if (wage != null && !nonPayable)
          Text('실근무 ${wage.workMinutes ~/ 60}h ${wage.workMinutes % 60}m',
              style: ResponsiveHelper.tinyStyle(context).copyWith(color: AppColors.grey500)),
        if (record.businessName.isNotEmpty)
          Text(TextLayout.identity(record.businessName),
              semanticsLabel: record.businessName,
              style: ResponsiveHelper.tinyStyle(context, color: AppColors.grey500)),
      ],
    );
    final side = <Widget>[
      Text(amountText,
          style: ResponsiveHelper.bodyStyle(context).copyWith(
            fontWeight: FontWeight.bold,
            color: nonPayable ? AppColors.grey500 : AppColors.successDark,
          )),
      _WageStatusBadge(wageStatus: record.wageStatus, nonPayable: nonPayable, status: record.status),
      if (record.wageDetail != null && !nonPayable)
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
    ];

    return GestureDetector(
      onTap: () => _openWageDetail(context, record),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
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
        child: LayoutBuilder(builder: (context, c) {
          // 배율 1.0 기준 오른쪽 묶음(금액·상태) 약 110 + 왼쪽 최소 170.
          final sideBySide = TextLayout.fits(context, c.maxWidth, 280);
          if (sideBySide) {
            return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: info),
              SizedBox(width: ResponsiveHelper.spacing(context, 12)),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (var i = 0; i < side.length; i++) ...[
                    if (i > 0) SizedBox(height: ResponsiveHelper.spacing(context, 4)),
                    side[i],
                  ],
                ],
              ),
            ]);
          }
          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            info,
            SizedBox(height: ResponsiveHelper.spacing(context, 8)),
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: ResponsiveHelper.spacing(context, 8),
              runSpacing: ResponsiveHelper.spacing(context, 4),
              children: side,
            ),
          ]);
        }),
      ),
    );
  }

  Future<void> _openWageDetail(BuildContext context, AttendanceModel record) async {
    if (record.wageDetail == null) return;

    // [RULES-FIX] users/{uid} GET은 isOwner || isSuperAdmin 전용 (SEC-FIX 2026-08-10).
    // 관리자 경로에서 users 직접 get은 PERMISSION_DENIED → 두 read를 분리해 독립 처리.
    //
    // Step A: application read (필수) — isAdminOf / isSubAdminOf 허용
    ApplicationModel? app;
    try {
      final appDoc = await FirebaseFirestore.instance
          .collection('applications')
          .doc(record.applicationId)
          .get();
      if (!context.mounted) return;
      if (appDoc.exists) app = ApplicationModel.tryFromFirestore(appDoc);
    } catch (e) {
      debugPrint('❌ 지원서 정보 로드 실패: $e');
      if (context.mounted) ToastHelper.showError('데이터를 불러오는데 실패했습니다.');
      return;
    }
    if (app == null || !context.mounted) return;

    // Step B: user read (선택) — 관리자는 PERMISSION_DENIED → null 허용(이름 미표시 fallback)
    // WageDetailDialog: user?.name ?? '이름 없음'. wage 계산에는 user 불필요.
    UserModel? user;
    try {
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(record.userId)
          .get();
      if (!context.mounted) return;
      final userData = userDoc.data();
      if (userDoc.exists && userData != null) {
        user = UserModel.fromMap(userData, userDoc.id);
      }
    } catch (_) {
      // users GET 권한 없음 — user=null로 계속 진행 (wage 상세는 attendance에서 표시)
    }

    await WageDetailDialog.show(
      context: context,
      app: app,
      user: user,
      attendance: record,
      wage: record.wageDetail!,
      mode: WageDialogMode.confirmed,
      businessName: app.businessName,
      scheduledBreakMinutes: record.wageDetail!.scheduledBreakMinutes,
      // [PAYROLL-DETAIL.32] 관리자는 users 를 읽지 못해 '이름 없음'이 떴다 — 개요에서 받은 이름을 쓴다.
      fallbackName: widget.workerName,
    );
  }

  /// 중간정산 처리 다이얼로그
  Future<void> _showInterimSettlementDialog(BuildContext ctx) async {
    if (_isSettling) return;
    // 확정 상태 (아직 이체 안 된) 기록만 대상 — 날짜 오름차순 정렬 후 first/last 사용
    // [PAYROLL-DETAIL.32] 이체 대상 판정은 Home·이체 목록과 같은 식(isPayableForTransfer) —
    //   노쇼·결근 0원은 '이체 완료'로 바꿀 급여가 아니다(서버 중간정산은 이 판정을 하지 않는다: OPEN).
    final settleableRecords = _records.where((r) =>
        r.isPayableForTransfer &&
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
        personNo: _personNo,
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

  /// [R7-PRE1A.1] 파일명 앞에 붙는 사업장 내 사람 번호. 모르면 null.
  final String? personNo;

  final List<AttendanceModel> records;

  const _PayslipIssueSheet({
    required this.year,
    required this.month,
    required this.workerName,
    this.personNo,
    required this.records,
  });

  @override
  State<_PayslipIssueSheet> createState() => _PayslipIssueSheetState();
}

class _PayslipIssueSheetState extends State<_PayslipIssueSheet> {
  /// `W-014_김지현_` — 번호가 없으면 `김지현_`.
  ///
  ///   동명이인 둘의 명세서를 차례로 내보내면 받는 쪽에서 같은 파일명이 되어
  ///   하나가 덮인다. raw uid 는 쓰지 않는다 — 28자 난수는 운영 문서에서
  ///   읽히지 않고, 사업장 밖으로 나가는 파일에 내부 식별자를 실을 이유도 없다.
  String get _fileNamePrefix {
    final name = PersonLabel.safeFileName(widget.workerName);
    final no = widget.personNo;
    return no == null ? '${name}_' : '${no}_${name}_';
  }

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
          ? '$_fileNamePrefix${widget.month}월$_selectedWeekNo주차_임금명세서.pdf'
          : '$_fileNamePrefix${widget.year}년${widget.month}월_임금명세서.pdf';
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
  /// [PAYROLL-DETAIL.32] 노쇼·결근 0원 — '미이체'가 아니라 지급할 것이 없는 기록이다.
  final bool nonPayable;
  final String? status;
  const _WageStatusBadge({required this.wageStatus, this.nonPayable = false, this.status});

  @override
  Widget build(BuildContext context) {
    final isTransferred = wageStatus == AttendanceModel.wageTransferred;
    final color = nonPayable
        ? AppColors.grey600
        : (isTransferred ? AppColors.success : AppColors.warning);
    // '이체 완료'는 앱에서 이체 처리로 기록된 상태다(은행 송금 확인이 아니다) — 문구는 기존 그대로.
    final label = nonPayable
        ? '${status == AttendanceModel.statusAbsent ? '결근' : '노쇼'} · 지급 없음'
        : (isTransferred ? '이체 완료' : '미이체'); // [5C.2-P3] 용어 통일
    final icon  = nonPayable
        ? Icons.remove_circle_outline
        : isTransferred
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
