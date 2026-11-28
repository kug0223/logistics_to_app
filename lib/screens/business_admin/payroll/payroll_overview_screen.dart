import 'dart:async';

import 'package:flutter/material.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_core/firebase_core.dart' show FirebaseException;
import 'package:provider/provider.dart';

import '../../../models/core/attendance_model.dart';
import '../../../models/core/payroll_summary_model.dart';
import '../../../utils/payroll_due_scope.dart';
import 'payroll_overview_reads.dart';
import 'payroll_month_ledger.dart';
import '../../../providers/user_provider.dart';
import '../../../theme/app_colors.dart';
import '../../../utils/dialog_helper.dart';
import '../../../utils/format_helper.dart';
import '../../../utils/responsive_helper.dart';
import '../../../utils/toast_helper.dart';
import 'payroll_worker_detail_screen.dart';
import 'payroll_payment_dashboard_screen.dart';
import '../../../screens/common/notification_screen.dart';
import '../../../utils/admin_tab_switcher.dart';
import '../../../utils/navigation_helper.dart';
import '../../../widgets/common/app_page_scaffold.dart';
import '../../../widgets/common/notification_badge.dart';
import '../../../widgets/common/skeleton_widget.dart';
import '../../../widgets/common/app_search_bar.dart';
import '../../../widgets/common/app_empty_state.dart';
import '../../../utils/business_picker_helper.dart';
import '../../../utils/text_layout.dart';
import '../../../widgets/common/amount_text.dart';

class PayrollOverviewScreen extends StatefulWidget {
  /// [R7-P1-5 PAY-4] 원시 외부 읽기 경계. production 은 null → `PayrollOverviewReads.of`.
  final PayrollOverviewReads? reads;

  const PayrollOverviewScreen({super.key, this.reads});

  @override
  State<PayrollOverviewScreen> createState() => _PayrollOverviewScreenState();
}

class _PayrollOverviewScreenState extends State<PayrollOverviewScreen> {
  late final PayrollOverviewReads _reads =
      widget.reads ?? PayrollOverviewReads.of();

  // [PERF-7] DateTime.now()를 필드에 1회만 캡처 — _buildMonthGrid build()마다 재생성 방지
  final DateTime _now = DateTime.now();
  int _selectedYear = DateTime.now().year;
  String? _businessId;
  /// [DU238 D5] 고른 사업장 이름 — 같은 선택(picked)에서 id 와 함께 저장한다. 새 조회는 없다.
  String? _businessName;
  bool _isLoading = true;
  /// Tab 루트에서 **사업장 선택을 취소**했을 때. 고를 사업장은 있다.
  bool _noData = false;

  /// [P4.2-SETUP-01] 사업장이 **하나도 없다** — 급여 관리 이전 단계다.
  ///
  ///   `_noData` 와 합쳐 두면 "사업장을 선택해주세요" 가 신규 관리자에게
  ///   뜨고, 고를 것이 없으니 [선택하기] 가 같은 화면으로 되돌아온다.
  ///   SETUP_REQUIRED 와 "선택 안 함" 은 다음 행동이 다르므로 나눠 둔다.
  bool _noBusiness = false;
  bool _accessDenied = false; // [5C.1A-SCREEN-01] canManageWage=false SubAdmin
  // [CROSS-DOMAIN-R5.1F.5] 권한을 확인하지 못한 상태 — 거부와 다른 말이다.
  bool _accessUnverified = false;
  String? _loadError;
  int _todayPaymentCount = 0;
  /// [PAYROLL-BANNER-COMPLETENESS] 송금 대상을 끝까지 세지 못했다(실패·상한) — 0건이 아니다.
  bool _todayPaymentUnknown = false;

  /// [PERF-L22] 배너 숫자를 센 전 기간 미이체 목록과 그 시각 — 배너를 누르면 대시보드에 그대로 넘긴다.
  ({String bizId, List<AttendanceModel> records, DateTime at})? _outstandingSeed;

  /// 배너 → 대시보드에 넘길 수 있는 최대 나이. 넘으면 대시보드가 스스로 다시 읽는다.
  static const Duration _seedMaxAge = Duration(minutes: 2);

  // [ACCESS-DENIED-REGRESSION-01] permission hydration race 복구용 listener
  // initState에서 등록, dispose에서 해제
  late UserProvider _userProvider;

  static const List<String> _monthLabels = [
    '1월', '2월', '3월', '4월', '5월', '6월',
    '7월', '8월', '9월', '10월', '11월', '12월',
  ];

  @override
  void initState() {
    super.initState();
    // [ACCESS-DENIED-REGRESSION-01] provider 캡처 후 listener 등록
    // → false-negative _accessDenied 상태를 permission hydration 완료 시 복구
    _userProvider = context.read<UserProvider>();
    _userProvider.addListener(_onPermissionChanged);
    _init();
  }

  // [ACCESS-DENIED-REGRESSION-01] permission hydration race 복구 handler
  // 조건: _accessDenied=true 상태에서 provider가 canManageWage=true를 전달할 때만 복구
  // gate는 _init() 내부에 그대로 유지 — unauthorized hidden tab은 계속 차단됨
  void _onPermissionChanged() {
    if (!mounted) return;
    // [DU238 R1] 갱신 전 상태를 기억한다 — 아래에서 _accessUnverified 를 지우기 때문이다.
    final wasUnverified = _accessUnverified;
    // [CROSS-DOMAIN-R5.1F.5] 네 상태로 본다 — 확인 실패를 권한 없음으로
    //   바꾸지 않는다. 확인된 허용에서만 화면을 연다.
    final check = _userProvider.checkCurrentBusiness((p) => p.canManageWage);
    final allowed = check == PermissionCheck.allowed;
    final unverified = check == PermissionCheck.error ||
        check == PermissionCheck.unknown;
    if (_accessUnverified != unverified) {
      setState(() => _accessUnverified = unverified);
    }

    // [CROSS-DOMAIN-R5.1F.1] 회수 방향도 본다.
    //   이 handler는 grant(false→true) 복구만 하고 있었다. 화면을 열어 둔 채
    //   권한이 회수되면 급여 화면과 그 action이 그대로 남아, 서버 403을
    //   받아봐야 알 수 있었다. 권한은 지금 값으로 즉시 다시 판정한다.
    if (!allowed) {
      if (_accessDenied) return;
      setState(() {
        _accessDenied = true;
        _isLoading = false;
        _loadError = null;
      });
      return;
    }

    // [DU238 R1] 진입 때 확인 실패·모름이었고 아직 사업장을 고르지 않았다면, 첫 확인된 허용에서 조회를 시작한다.
    //   거부→허용은 예전대로다. 같은 허용이 다시 와도 wasUnverified 가 false 라 다시 시작하지 않는다.
    if (!_accessDenied && !(wasUnverified && _businessId == null)) return;

    setState(() {
      _accessDenied = false;
      _isLoading = true;
      _loadError = null;
    });
    unawaited(_init());
  }

  Future<void> _init() async {
    final userProvider = context.read<UserProvider>();
    // [5C.1A-SCREEN-01] canManageWage=false SubAdmin 직접 진입 차단
    // PERMISSION_DENIED를 정상 UX로 사용하지 않도록 Firestore 쿼리 전 선행 체크
    // [CROSS-DOMAIN-R5.1F.5] 확인된 허용에서만 조회한다. 확인 실패는
    //   거부와 다른 상태로 표시한다 — ERROR를 DENIED로 바꾸지 않는다.
    final entryCheck = userProvider.checkCurrentBusiness((p) => p.canManageWage);
    if (entryCheck != PermissionCheck.allowed) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _accessUnverified = entryCheck == PermissionCheck.error ||
              entryCheck == PermissionCheck.unknown;
          _accessDenied = entryCheck == PermissionCheck.denied;
        });
      }
      return;
    }
    final uid = userProvider.currentUser?.uid;
    if (uid == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    try {
      // SubAdmin은 adminIds에 없으므로 effectiveBusinessId로 직접 조회
      final businesses = await _reads.businesses(
        isSubAdmin: userProvider.isSubAdmin,
        effectiveBusinessId: userProvider.effectiveBusinessId,
        managedIds: userProvider.currentUser?.managedBusinessIds ?? [],
      );
      if (!mounted) return;
      if (businesses.isEmpty) {
        // [P4.2-SETUP-01] 사업장이 0개다 — **아직 급여 관리가 시작되지 않은
        //   상태**이지 "선택을 안 한 상태"가 아니다. 예전에는 둘 다
        //   `_noData` 하나로 묶여 '사업장을 선택해주세요 → [선택하기]' 가
        //   떴는데, 고를 사업장이 없으므로 눌러도 같은 화면으로 돌아왔다.
        if (mounted) setState(() { _isLoading = false; _noBusiness = true; });
        return;
      }
      // C-08: N사업장 지원 — BusinessPickerHelper로 선택 (1개면 자동 선택)
      if (!mounted) return;
      final picked = await BusinessPickerHelper.pickFromList(context, businesses);
      if (!mounted) return;
      if (picked == null) {
        // picker 취소 — pop 대신 empty state (tab 루트에서 pop 불가)
        setState(() { _isLoading = false; _noData = true; });
        return;
      }
      _businessId = picked.id;
      _businessName = picked.name;
      await Future.wait([
        _loadYear(_selectedYear),
        _loadTodayCount(),
      ]);
    } catch (e) {
      if (mounted) setState(() { _isLoading = false; _loadError = e.toString(); });
    }
  }

  /// [PAYROLL-ANNUAL-READ.48] 월별 미확정·미이체의 확인 상태. 키는 1~12월.
  ///
  ///   예전에는 출근 원장을 1~12월 한 번에 읽고, 실패하거나 서버 상한(10,000건)에 걸리면
  ///   `_attCountsUnknown` 하나로 **12개월 전부**를 '확인 못함'으로 만들었다. 이제 달마다
  ///   따로 읽고([loadMonthLedgers]) 달마다 따로 말한다 — 9월이 실패해도 10월은 보인다.
  ///   미래 달은 읽지 않는다(어차피 그리지 않는다).
  Map<int, MonthLedgerState> _ledger = const {};

  /// 집계 문서(금액·인원 owner). 달 → 문서.
  Map<int, PayrollSummaryModel> _summaryDocs = const {};
  bool _summariesLoaded = false;

  /// 서버 월 집계 배포 여부(이 화면에서 한 번 확인하면 다시 묻지 않는다).
  final MonthLedgerCountsCapability _countsCapability = MonthLedgerCountsCapability();

  /// 조회 세대 — 사업장·연도 전환, 새로고침, 다시 확인마다 올린다. 늦게 끝난 이전 응답은 버린다.
  int _loadGen = 0;

  /// 지금 화면의 숫자가 어느 사업장·연도 것인가 — 같은 범위를 다시 읽을 때만 이전 숫자를 '이전 조회'로 쓴다.
  String? _ledgerScope;

  List<int> _monthsToRead(int year) {
    final now = _now;
    if (year > now.year) return const [];
    final last = year == now.year ? now.month : 12;
    return [for (var m = 1; m <= last; m++) m];
  }

  /// 12개월 카드 — 집계 문서 + 그 달 원장 상태로 만든다.
  List<PayrollSummaryModel> get _summaries {
    final bizId = _businessId;
    if (!_summariesLoaded || bizId == null) return const [];
    return List.generate(12, (i) => _composeMonth(bizId, _selectedYear, i + 1));
  }

  PayrollSummaryModel _composeMonth(String bizId, int year, int month) {
    final mm = month.toString().padLeft(2, '0');
    final st = _ledger[month];
    // known 은 이번 조회의 사실, stale 은 이전 조회의 숫자(표시만). loading·unknown 은 숫자 없음.
    final c = (st?.status == MonthLedgerStatus.known || st?.status == MonthLedgerStatus.stale) ? st!.counts : null;
    final complete = st?.isComplete ?? false;
    final pCount = c?.pending ?? 0;
    final ntCount = c?.notTransferred ?? 0;
    final tCount = c?.transferred ?? 0;
    final existing = _summaryDocs[month];
    if (existing != null) {
      return PayrollSummaryModel(
        id: existing.id,
        businessId: existing.businessId,
        yearMonth: existing.yearMonth,
        year: existing.year,
        month: existing.month,
        totalPayout: existing.totalPayout,
        // [R7-P1-5 후속] `이체 완료` = 확정 - 미이체. 이번 조회로 끝까지 센 달만 원장 숫자로 맞춘다.
        confirmedCount: complete ? (ntCount + tCount) : existing.confirmedCount,
        workerCount: existing.workerCount,
        pendingCount: pCount,
        notTransferredCount: ntCount,
        workers: existing.workers,
        updatedAt: existing.updatedAt,
      );
    }
    if (pCount == 0 && ntCount == 0 && tCount == 0) {
      return PayrollSummaryModel.empty(businessId: bizId, year: year, month: month);
    }
    return PayrollSummaryModel(
      id: '${bizId}_$year-$mm',
      businessId: bizId,
      yearMonth: '$year-$mm',
      year: year,
      month: month,
      totalPayout: c?.payout ?? 0,
      confirmedCount: ntCount + tCount,
      workerCount: c?.workerCount ?? 0,
      pendingCount: pCount,
      notTransferredCount: ntCount,
      workers: {},
      updatedAt: DateTime.now(),
    );
  }

  /// 원장을 이번 조회로 끝까지 세지 못한 달(읽는 중 제외) — 다시 확인 대상.
  List<int> get _unresolvedMonths => [
        for (final e in _ledger.entries)
          if (e.value.status == MonthLedgerStatus.unknown || e.value.status == MonthLedgerStatus.stale) e.key,
      ]..sort();

  bool get _anyMonthLoading => _ledger.values.any((s) => s.status == MonthLedgerStatus.loading);

  Future<void> _loadYear(int year) async {
    final bizId = _businessId;
    if (bizId == null) return;
    if (!mounted) return;
    final gen = ++_loadGen;
    final scope = '$bizId|$year';
    // 같은 사업장·연도를 다시 읽을 때만 이전 숫자를 들고 간다 — 다른 범위의 숫자는 버린다.
    final previous = <int, MonthLedgerCounts>{
      if (_ledgerScope == scope)
        for (final e in _ledger.entries)
          if (e.value.counts != null && e.value.status != MonthLedgerStatus.loading) e.key: e.value.counts!,
    };
    final months = _monthsToRead(year);
    setState(() {
      _isLoading = true;
      _loadError = null;
      _ledgerScope = scope;
      _ledger = {for (final m in months) m: MonthLedgerState.loading(previous[m])};
      if (!_summaryDocs.values.every((d) => d.businessId == bizId && d.year == year)) {
        _summaryDocs = const {};
        _summariesLoaded = false;
      }
    });

    // 원장은 집계 문서와 **나란히** 읽는다. 달마다 끝나는 대로 카드에 반영된다.
    final ledgerDone = _readMonths(gen, bizId, year, months, previous);

    try {
      final psItemsRaw = await _reads.payrollSummaries(businessId: bizId, year: year);
      if (!mounted || gen != _loadGen) return;
      final summaryMap = <int, PayrollSummaryModel>{};
      for (final e in psItemsRaw) {
        final raw = Map<String, dynamic>.from(e);
        final id = raw.remove('id') as String? ?? '';
        final m = PayrollSummaryModel.tryFromMap(raw, id);
        if (m != null) summaryMap[m.month] = m;
      }
      setState(() {
        _summaryDocs = summaryMap;
        _summariesLoaded = true;
        _isLoading = false;
      });
    } catch (e) {
      if (mounted && gen == _loadGen) setState(() { _loadError = e.toString(); _isLoading = false; });
    }
    await ledgerDone;
  }

  Future<void> _readMonths(int gen, String bizId, int year, List<int> months,
      Map<int, MonthLedgerCounts> previous) {
    return loadMonthLedgers(
      months: months,
      yearMonthOf: (m) => '$year-${m.toString().padLeft(2, '0')}',
      read: (ym) => _reads.adminAttendances(businessId: bizId, yearMonthGte: ym, yearMonthLte: ym),
      countsRead: _reads.monthLedgerCounts == null
          ? null
          : (ym) => _reads.monthLedgerCounts!(businessId: bizId, yearMonth: ym),
      previousOf: (m) => previous[m],
      capability: _countsCapability,
      isCurrent: () => mounted && gen == _loadGen && _businessId == bizId && _selectedYear == year,
      onMonth: (m, st) => setState(() => _ledger = {..._ledger, m: st}),
    );
  }

  /// [PERF-L22] 월 상세에서 돌아왔을 때 — 그 달 원장과 연 요약(금액·인원 문서)만 다시 읽는다.
  Future<void> _reloadMonthAfterReturn(int month) async {
    final bizId = _businessId;
    if (bizId == null || !mounted) return;
    if (_isLoading || _anyMonthLoading || _ledgerScope != '$bizId|$_selectedYear') {
      await _loadYear(_selectedYear);
      return;
    }
    final year = _selectedYear;
    final gen = ++_loadGen;
    final previous = <int, MonthLedgerCounts>{
      if (_ledger[month]?.counts != null) month: _ledger[month]!.counts!,
    };
    setState(() => _ledger = {..._ledger, month: MonthLedgerState.loading(previous[month])});
    final ledgerDone = _readMonths(gen, bizId, year, [month], previous);
    try {
      final psItemsRaw = await _reads.payrollSummaries(businessId: bizId, year: year);
      if (!mounted || gen != _loadGen) return;
      final summaryMap = <int, PayrollSummaryModel>{};
      for (final e in psItemsRaw) {
        final raw = Map<String, dynamic>.from(e);
        final id = raw.remove('id') as String? ?? '';
        final m = PayrollSummaryModel.tryFromMap(raw, id);
        if (m != null) summaryMap[m.month] = m;
      }
      setState(() {
        _summaryDocs = summaryMap;
        _summariesLoaded = true;
      });
    } catch (e) {
      // 이전 요약은 남긴다(화면을 오류로 바꾸지 않는다) — 새로 읽지 못했다는 사실만 알린다.
      debugPrint('⚠️ 급여 요약 다시 읽기 실패(이전 값 유지): $e');
      if (mounted && gen == _loadGen) ToastHelper.showWarning('급여 요약을 새로 불러오지 못했어요');
    }
    await ledgerDone;
  }

  /// 확인하지 못한 달만 다시 읽는다 — 이미 끝까지 센 달은 다시 읽지 않는다.
  Future<void> _retryUnresolvedMonths() async {
    final bizId = _businessId;
    if (bizId == null || _anyMonthLoading) return;
    final months = _unresolvedMonths;
    if (months.isEmpty) return;
    final year = _selectedYear;
    final gen = ++_loadGen;
    final previous = <int, MonthLedgerCounts>{
      for (final m in months)
        if (_ledger[m]?.counts != null) m: _ledger[m]!.counts!,
    };
    setState(() => _ledger = {
          ..._ledger,
          for (final m in months) m: MonthLedgerState.loading(previous[m]),
        });
    await _readMonths(gen, bizId, year, months, previous);
  }

  /// [PAYROLL-V3-CONNECTED] 배너 조회 세대 — 진입 조회와 목록에서 돌아온 뒤 재조회가 겹치면
  ///   늦게 끝난 옛 응답이 새 숫자를 덮지 않는다.
  int _todayCountGen = 0;

  Future<void> _loadTodayCount() async {
    final bizId = _businessId;
    if (bizId == null) return;
    final gen = ++_todayCountGen;
    int? count;
    List<AttendanceModel>? records;
    try {
      final readAll = _reads.outstandingRecords;
      if (readAll != null) {
        // [PERF-L22] 같은 전 기간 조회로 숫자를 세고 목록을 보관한다(배너 → 대시보드 전달).
        records = await readAll(bizId);
        count = PayrollDueScope.dueByToday(records, PayrollDueScope.now()).length;
      } else {
        count = await _reads.todayPaymentCount(bizId);
      }
    } catch (e) {
      debugPrint('⚠️ 오늘 급여 건수 조회 실패: $e');
      count = null;
      records = null;
    }
    if (!mounted || _businessId != bizId || gen != _todayCountGen) return;
    _outstandingSeed = records == null
        ? null
        : (bizId: bizId, records: List.unmodifiable(records), at: DateTime.now());
    // [PAYROLL-BANNER-COMPLETENESS] 예전에는 실패하면 이전 값(처음엔 0)을 그대로 둬
    //   배너가 사라졌다 — "오늘 보낼 것 없음"처럼 보였다. 모르면 모른다고 보인다.
    setState(() {
      _todayPaymentUnknown = count == null;
      if (count != null) _todayPaymentCount = count;
    });
  }

  void _onYearChanged(int delta) {
    if (_isLoading) return; // 로드 중 연타 방지 — race condition 예방
    final newYear = _selectedYear + delta;
    if (newYear < 2015 || newYear > DateTime.now().year + 1) return;
    setState(() => _selectedYear = newYear);
    _loadYear(newYear);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // [DESIGN-PATCH-1] GradientScaffold → AppPageScaffold — 관리자 Shell 정규화
    // refresh / notification
    //
    // [P4.2-NAV-01] 홈 버튼을 뺐다. 이 화면은 **root tab** 이고, shell 안에서
    //   `NavigationHelper.goHome` 은 `switchToTab(homeTab)` 뿐이다 —
    //   바로 아래 하단 탭의 '홈' 과 같은 동작이다. push 로 열린 하위 화면
    //   (예: 월별 급여현황)에는 돌아갈 길이 필요하므로 그대로 둔다.
    //   그 화면의 순서를 복사해 오면서 root 에는 맞지 않는 action 이 따라왔다.
    // [P4.2B-NAV-03] 알림 벨도 뺐다. 다섯 root 중 알림이 있던 곳은 홈과 이
    //   화면 둘뿐이었고, 공고·근무·관리에는 없었다. 알림은 특정 탭의 데이터가
    //   아니라 **전역 수신함**이라, 어떤 탭에서 열든 같은 화면이 나온다.
    //   그런 진입점이 다섯 중 둘에만 있으면 관리자는 규칙을 배울 수 없다.
    //   해결은 두 방향인데, 다섯 탭 전부에 벨을 붙이는 쪽은 택하지 않는다 —
    //   모든 root 의 우상단을 같은 버튼으로 채우면 각 탭 고유 action(이 화면의
    //   새로고침, 공고의 필터·등록)이 묻힌다.
    //   그래서 **canonical owner 를 홈 하나로** 둔다. 홈 헤더의 벨은 배지까지
    //   그대로 남아 있고, 하단 탭에서 한 번에 닿는다.
    //   push 로 열리는 하위 화면(월별 급여현황)은 root 가 아니므로 건드리지
    //   않는다 — 거기서는 하단 탭이 가려지지 않아도 돌아갈 길이 필요하다.
    return AppPageScaffold(
      title: '급여 관리',
      actions: [
        IconButton(
          icon: const Icon(Icons.refresh_rounded),
          // [PAYROLL-ANNUAL-READ.48] 화면 읽기 이름이 없던 버튼.
          tooltip: '새로고침',
          onPressed: () => _loadYear(_selectedYear),
          color: AppColors.textSecondary,
        ),
      ],
      body: Column(
        children: [
          // [DU238 D5] 어느 사업장의 급여인지 — 확인된 허용에서 고른 사업장이 있을 때만 연도 띠 바로 위에 보인다.
          if (_showBusinessName) _buildBusinessLine(),
          _buildYearSelector(theme),
          if (_isLoading)
            const Expanded(child: PayrollGridSkeleton())
          else if (_accessUnverified)
            // [CROSS-DOMAIN-R5.1F.5] 확인 실패 — "권한 없음"이 아니다.
            Expanded(
              child: AppEmptyState(
                icon: Icons.sync_problem_outlined,
                title: '권한 정보를 확인하지 못했습니다',
                subtitle: '잠시 후 다시 시도해주세요.',
                subtitleColor: AppColors.textSecondary, // [DU238 D4]
                action: TextButton(
                  onPressed: () =>
                      unawaited(_userProvider.refreshSubAdminAccessState()),
                  child: const Text('다시 확인'),
                ),
              ),
            )
          else if (_accessDenied)
            // [5C.1A-SCREEN-01] canManageWage=false SubAdmin 접근 차단 상태
            const Expanded(
              child: AppEmptyState(
                icon: Icons.lock_outline,
                title: '접근 권한이 없습니다',
                subtitle: '급여 관리 권한이 있는 관리자에게 문의하세요.',
                subtitleColor: AppColors.textSecondary, // [DU238 D4]
              ),
            )
          else if (_noBusiness)
            // [P4.2-SETUP-01] SETUP_REQUIRED — 사업장이 없어서 급여 관리가
            //   아직 시작되지 않았다. "선택해주세요" 가 아니다(고를 것이 없다).
            Expanded(
              child: AppEmptyState(
                icon: Icons.storefront_outlined,
                title: '아직 급여를 관리할 사업장이 없어요',
                subtitle: '사업장을 등록하면 근무·급여 관리를 시작할 수 있어요.',
                subtitleColor: AppColors.textSecondary, // [DU238 D4]
                action: TextButton(
                  // [P4.2B-CTA-01] '준비 계속하기'는 어디로 가는지 말하지
                  //   않았다. 목적지는 홈이고, 사업장이 0개인 홈은 곧 준비
                  //   단계 목록이다. 라벨이 그 화면을 그대로 가리키게 한다.
                  //   '사업장 등록'으로 쓰지 않는 이유: 이 버튼은 등록 폼이
                  //   아니라 홈으로 가고, 등록 직후에도 운영팀 검토 대기가
                  //   남는다 — 그 사실을 설명하는 곳이 홈이다.
                  onPressed: () => AdminTabSwitcher.instance
                      .switchToTab(AdminTabSwitcher.homeTab),
                  child: const Text('준비 단계 보기'),
                ),
              ),
            )
          else if (_noData)
            Expanded(
              child: AppEmptyState(
                icon: Icons.business_outlined,
                title: '사업장을 선택해주세요',
                action: TextButton(
                  onPressed: () {
                    setState(() { _isLoading = true; _noData = false; });
                    _init();
                  },
                  child: const Text('선택하기'),
                ),
              ),
            )
          else if (_loadError != null || _summaries.length != 12)
            Expanded(
              child: AppEmptyState(
                icon: Icons.error_outline,
                title: '데이터를 불러오지 못했습니다',
                action: TextButton(
                  onPressed: () => _loadYear(_selectedYear),
                  child: const Text('다시 시도'),
                ),
              ),
            )
          else ...[
            if (_todayPaymentUnknown && _businessId != null)
              _TodayPaymentBanner(
                count: null,
                onTap: _loadTodayCount, // 다시 시도
              )
            else if (_todayPaymentCount > 0 && _businessId != null)
              _TodayPaymentBanner(
                count: _todayPaymentCount,
                onTap: () async {
                  final now = DateTime.now();
                  // [PERF-L22] 배너를 센 그 목록을 넘긴다(같은 사업장 · 2분 안). 대시보드는 첫 화면에
                  //   다시 전 기간을 읽지 않는다 — 새로고침·처리 뒤 갱신은 대시보드가 평소대로 읽는다.
                  final seed = _outstandingSeed;
                  final seedOk = seed != null &&
                      seed.bizId == _businessId &&
                      DateTime.now().difference(seed.at) <= _seedMaxAge;
                  var mutated = false;
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      // [PAYROLL-BANNER-DUE-SCOPE] 배너가 센 집합을 그대로 연다.
                      //   예전에는 인자 없이 열어 `지급 예정일 == 오늘` 날짜 화면이
                      //   떴고, 기한 지난 건이 빠져 `2건` → `0명` 이 됐다.
                      builder: (_) => PayrollPaymentDashboardScreen(
                        businessId: _businessId!,
                        year: now.year,
                        month: now.month,
                        showAllOutstanding: true,
                        outstandingDueByToday: true,
                        initialOutstanding: seedOk ? seed.records : null,
                        onMutated: () => mutated = true,
                      ),
                    ),
                  );
                  if (!mounted) return;
                  // [PERF-L22] 대시보드에서 아무것도 바꾸지 않았으면 전 기간 재조회(2020~)를 하지 않는다.
                  //   바꿨으면 배너 숫자와 그 달들의 원장을 다시 읽는다(예전엔 숫자만 다시 읽었다).
                  if (!mutated) return;
                  _loadTodayCount();
                  _loadYear(_selectedYear);
                },
              ),
            if (_unresolvedMonths.isNotEmpty && !_anyMonthLoading) _buildUnresolvedBanner(),
            Expanded(child: _buildMonthGrid(theme)),
          ],
        ],
      ),
    );
  }

  /// [PAYROLL-ANNUAL-READ.48] 확인하지 못한 달이 있다 — 몇 달인지와, 그 달만 다시 읽는 버튼.
  ///   연간 합계를 따로 그리지 않는다(그런 숫자를 이 화면은 보여 주지 않는다).
  Widget _buildUnresolvedBanner() {
    final months = _unresolvedMonths;
    final anyLimit = months.any((m) => _ledger[m]?.failure == MonthLedgerFailure.limit);
    final label = months.map((m) => _monthLabels[m - 1]).join('·');
    final text = anyLimit
        ? '$label 미이체를 확인하지 못했어요. 건수가 많은 달이 있어요.'
        : '$label 미이체를 확인하지 못했어요.';
    return Padding(
      padding: EdgeInsets.fromLTRB(ResponsiveHelper.spacing(context, 16),
          ResponsiveHelper.spacing(context, 8), ResponsiveHelper.spacing(context, 8), 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(Icons.info_outline, size: ResponsiveHelper.iconSize(context, 16), color: AppColors.grey500),
          SizedBox(width: ResponsiveHelper.spacing(context, 6)),
          Expanded(
            child: Text(
              TextLayout.keepWords(text),
              semanticsLabel: text,
              style: ResponsiveHelper.smallStyle(context, color: AppColors.textSecondary),
            ),
          ),
          TextButton(
            onPressed: _retryUnresolvedMonths,
            style: TextButton.styleFrom(minimumSize: const Size(48, 44)),
            child: Text(TextLayout.keepWords('다시 확인'), semanticsLabel: '다시 확인'),
          ),
        ],
      ),
    );
  }

  /// [DU238 D5] 이름은 확인된 허용에서 고른 사업장이 있을 때만 보인다 — 권한 안내·사업장 없음·선택 안 함에는
  ///   이전 이름을 붙이지 않는다.
  bool get _showBusinessName =>
      _businessId != null &&
      _businessName != null &&
      !_accessDenied &&
      !_accessUnverified &&
      !_noBusiness &&
      !_noData;

  /// [DU238 D5] 사업장 이름 한 줄 영역 — 길면 낱말 단위로 줄을 늘린다(말줄임 없음).
  Widget _buildBusinessLine() {
    final name = _businessName!;
    return Padding(
      padding: EdgeInsets.fromLTRB(ResponsiveHelper.spacing(context, 16), ResponsiveHelper.spacing(context, 8),
          ResponsiveHelper.spacing(context, 16), ResponsiveHelper.spacing(context, 8)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.storefront_outlined,
              size: ResponsiveHelper.iconSize(context, 16), color: AppColors.textSecondary),
          SizedBox(width: ResponsiveHelper.spacing(context, 6)),
          Expanded(
            child: Text(
              TextLayout.keepWords(name),
              semanticsLabel: name,
              style: ResponsiveHelper.smallStyle(context, color: AppColors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildYearSelector(ThemeData theme) {
    // [DESIGN-PATCH-1] headerContent(파란 그라디언트) → flat body header
    // 흰색 icon/text 제거 → admin dark token.
    // Dashboard _buildYearMonthHeader와 동일한 primaryColor α0.04 tint 컨테이너.
    return Container(
      color: theme.primaryColor.withValues(alpha: 0.04),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left),
            color: AppColors.textSecondary,
            tooltip: '이전 연도',
            onPressed: () => _onYearChanged(-1),
          ),
          SizedBox(width: ResponsiveHelper.spacing(context, 24)),
          Text(
            '$_selectedYear년',
            style: ResponsiveHelper.titleStyle(context).copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(width: ResponsiveHelper.spacing(context, 24)),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            color: AppColors.textSecondary,
            tooltip: '다음 연도',
            onPressed: () => _onYearChanged(1),
          ),
        ],
      ),
    );
  }

  /// [DEVICE-MISMATCH-FIX] 월 카드 높이를 **계산해 고정하지 않는다.**
  ///
  ///   예전에는 그리드 비율을 `104 + 배율 보정` 으로 못박았다(R7-P1-5 PAY-4).
  ///   보정식은 줄 높이를 font size 의 1.25 배로 **추정**했는데, 기기 한글
  ///   폰트의 실제 줄 높이가 그보다 커서 Pixel 5 기본 배율에서도
  ///   `BOTTOM OVERFLOWED BY 1.00 PIXELS` 로 `미이체 2` 줄이 잘렸다.
  ///   추정을 고치는 대신 **내용이 높이를 정하게** 한다 — 두 칸씩 한 줄,
  ///   한 줄의 두 카드는 같은 높이(IntrinsicHeight), 최소 높이만 둔다.
  Widget _buildMonthGrid(ThemeData theme) {
    final now = _now; // [PERF-7] 캐시된 필드 사용
    final columnSpacing = ResponsiveHelper.spacing(context, 12);
    final rowSpacing = ResponsiveHelper.spacing(context, 12);
    Widget cell(int i) {
      final summary = _summaries[i];
      final isFuture = _selectedYear > now.year ||
          (_selectedYear == now.year && (i + 1) > now.month);
      return _buildMonthCard(theme, summary, isFuture);
    }

    return ListView.builder(
      padding: ResponsiveHelper.listPadding(context),
      itemCount: 6,
      itemBuilder: (context, row) => Padding(
        padding: EdgeInsets.only(bottom: row == 5 ? 0 : rowSpacing),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: cell(row * 2)),
              SizedBox(width: columnSpacing),
              Expanded(child: cell(row * 2 + 1)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMonthCard(ThemeData theme, PayrollSummaryModel summary, bool isFuture) {
    final isEmpty = summary.isEmpty || isFuture;
    // [PAYROLL-ANNUAL-READ.48] 이 달 하나의 원장 상태 — 다른 달의 실패·상한이 섞이지 않는다.
    final ledgerState = _ledger[summary.month];
    final ledgerStatus = ledgerState?.status ?? MonthLedgerStatus.unknown;
    return GestureDetector(
      onTap: isEmpty
          ? null
          : () async {
              await Navigator.push<bool>(
                context,
                MaterialPageRoute(
                  builder: (_) => PayrollMonthScreen(
                    summary: summary,
                    reads: _reads,
                    // [R7-P1-5 PAY-1] 건수를 모르는 상태를 그대로 넘긴다 —
                    //   상세 화면이 `이체 완료`를 계산해 말하지 않도록.
                    // 이번 조회로 끝까지 센 달만 '모름 아님'이다(이전 조회·확인 중 포함 모름).
                    countsUnknown: !(ledgerState?.isComplete ?? false),
                    // [DU1 SubAdmin §5] 집계 문서가 실제로 있는 달인가(급여 권한 CF 결과).
                    //   없는 달은 하위 workers 를 읽지 않는다 — rule 이 부모를 get 해 판정하므로
                    //   권한이 있어도 PERMISSION_DENIED 가 되어 '불러오지 못함'으로 보였다.
                    summaryDocExists: _summaryDocs[summary.month] != null,
                  ),
                ),
              );
              if (!mounted) return;
              // [PERF-L22] 예전에는 결과와 무관하게 11개월 원장 + 요약 전체를 다시 읽었다.
              //   이 달 화면에서 일어난 변경(이체·취소·복원)은 이 달 것이다 — 이 달 원장 + 연 요약만 다시 읽는다.
              //   다른 범위가 진행 중이면 예전처럼 연 전체를 읽는다(세대가 겹치지 않게).
              _reloadMonthAfterReturn(summary.month);
            },
      child: Container(
        // 최소 높이만 둔다 — 내용이 더 길면(큰 글자 배율 등) 카드가 늘어난다.
        constraints: const BoxConstraints(minHeight: 104),
        decoration: BoxDecoration(
          color: isEmpty ? AppColors.grey100 : AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isEmpty ? AppColors.grey200 : theme.primaryColor.withValues(alpha: 0.2),
          ),
          boxShadow: isEmpty
              ? null
              : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
        ),
        padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 10)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Text(
                  _monthLabels[summary.month - 1],
                  style: ResponsiveHelper.smallStyle(context).copyWith(
                    fontWeight: FontWeight.bold,
                    // [DU238 D1] 미래 달만 비활성 grey400 — 지난·이번 빈 달 라벨은 읽기색.
                    color: isFuture
                        ? AppColors.grey400
                        : (isEmpty ? AppColors.textTertiary : theme.primaryColor),
                  ),
                ),
                if (!isEmpty) ...[
                  const Spacer(),
                  Icon(Icons.chevron_right,
                      size: ResponsiveHelper.iconSize(context, 13),
                      color: AppColors.grey400),
                ],
              ],
            ),
            SizedBox(height: ResponsiveHelper.spacing(context, 6)),
            if (isEmpty)
              if (isFuture)
                const SizedBox.shrink()
              else
                Text(
                  // [R7-P1-5 후속] 집계 문서도 없고 원장도 못 읽은 달은
                  //   **빈 달이 아니라 모르는 달**이다. 근무가 없었다고 말하지 않는다.
                  switch (ledgerStatus) {
                    MonthLedgerStatus.known => '데이터 없음',
                    MonthLedgerStatus.loading => '확인 중',
                    _ => '확인 못함',
                  },
                  style: ResponsiveHelper.tinyStyle(context).copyWith(
                    // [DU238 D1] 데이터 없음·확인 중·확인 못함은 읽어야 하는 상태다(grey100 위 5.43).
                    color: AppColors.textSecondary,
                  ),
                )
            else ...[
              // [UI-INTEGRATION.33] 대량 사업장(12억대·1,234명·12,345건) — 금액을 말줄임하지 않는다.
              //   카드 높이는 내용이 정하므로(위 _buildMonthGrid) 쉼표 뒤에서 줄을 바꾼다.
              AmountText(
                summary.formattedTotalPayout,
                style: ResponsiveHelper.smallStyle(context).copyWith(
                  fontWeight: FontWeight.bold,
                  color: AppColors.successDark,
                ),
              ),
              SizedBox(height: ResponsiveHelper.spacing(context, 2)),
              Text(
                TextLayout.phrases('${FormatHelper.formatNumber(summary.workerCount)}명'
                    ' · ${FormatHelper.formatNumber(summary.confirmedCount)}건'),
                semanticsLabel: '${FormatHelper.formatNumber(summary.workerCount)}명'
                    ' · ${FormatHelper.formatNumber(summary.confirmedCount)}건',
                style: ResponsiveHelper.tinyStyle(context).copyWith(
                  color: AppColors.textSecondary, // [DU238 D2]
                ),
              ),
              // [R7-P1-5 PAY-1] 모름을 0 으로 말하지 않는다. 출근 집계가 실패하면
              //   미이체 줄을 지우지 않고 **확인하지 못했다**고 말한다 —
              //   줄이 없는 것과 0 건인 것은 관리자에게 같은 뜻이기 때문이다.
              if (ledgerStatus == MonthLedgerStatus.loading ||
                  ledgerStatus == MonthLedgerStatus.unknown) ...[
                SizedBox(height: ResponsiveHelper.spacing(context, 2)),
                Text(
                  TextLayout.keepWords(ledgerStatus == MonthLedgerStatus.loading
                      ? '미이체 확인 중'
                      : '미이체 확인 못함'),
                  semanticsLabel: ledgerStatus == MonthLedgerStatus.loading
                      ? '미이체 확인 중'
                      : '미이체 확인 못함',
                  style: ResponsiveHelper.tinyStyle(context).copyWith(
                    color: AppColors.textSecondary, // [DU238 D2]
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ] else if (ledgerStatus == MonthLedgerStatus.stale) ...[
                // [PAYROLL-ANNUAL-READ.48] 이번 새로고침은 실패했다 — 숫자는 이전 조회 것이라고 말한다.
                SizedBox(height: ResponsiveHelper.spacing(context, 2)),
                Text(
                  TextLayout.phrases(
                      '미이체 ${FormatHelper.formatNumber(summary.notTransferredCount)} · 이전 조회'),
                  semanticsLabel:
                      '미이체 ${FormatHelper.formatNumber(summary.notTransferredCount)} · 이전 조회',
                  style: ResponsiveHelper.tinyStyle(context).copyWith(
                    color: AppColors.textSecondary, // [DU238 D2]
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ] else if (summary.notTransferredCount > 0) ...[
                SizedBox(height: ResponsiveHelper.spacing(context, 2)),
                Text(
                  '미이체 ${FormatHelper.formatNumber(summary.notTransferredCount)}',
                  style: ResponsiveHelper.tinyStyle(context).copyWith(
                    color: AppColors.errorDark, // [DU238 D3] 빨강 계열 유지, 흰 카드 위 6.57
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    // [ACCESS-DENIED-REGRESSION-01] permission listener 해제
    _userProvider.removeListener(_onPermissionChanged);
    super.dispose();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 월별 근무자 목록 화면
// ─────────────────────────────────────────────────────────────────────────────

// [PAYROLL-ANNUAL-READ.48] 미이체·미확정의 canonical 계산은 `MonthLedgerCounts`(payroll_month_ledger.dart)
//   하나다 — 개요(달마다)와 월 상세(새로고침)가 같이 쓴다. 서버 `srvPayrollContribution` 과 같은 식이다.

enum _SortOrder { amountDesc, amountAsc, nameAsc, workDaysDesc }

class PayrollMonthScreen extends StatefulWidget {
  final PayrollSummaryModel summary;

  /// [R7-P1-5 PAY-1] `미확정`·`미이체` 건수를 확인하지 못한 채 들어왔는가.
  ///   true 면 이 화면은 이체 완료 건수를 **계산해서 주장하지 않는다.**
  final bool countsUnknown;

  /// [R7-P1-5 PAY-4] 원시 외부 읽기 경계(개요에서 그대로 내려받는다).
  final PayrollOverviewReads? reads;

  /// [DU1 SubAdmin §5] 집계 문서(`payroll_summaries/{id}`)가 실제로 있는가.
  ///   false 면 근무자 하위 목록을 읽지 않고 원장 건수로 빈 화면을 말한다.
  final bool summaryDocExists;

  const PayrollMonthScreen({
    super.key,
    required this.summary,
    this.countsUnknown = false,
    this.reads,
    this.summaryDocExists = true,
  });

  @override
  State<PayrollMonthScreen> createState() => _PayrollMonthScreenState();
}

class _PayrollMonthScreenState extends State<PayrollMonthScreen> {
  final _searchCtrl = TextEditingController();
  Timer? _searchDebounce;
  String _searchQuery = '';
  _SortOrder _sortOrder = _SortOrder.amountDesc;
  List<PayrollWorkerSummary> _workers = [];
  bool _workersLoading = true;

  /// [R7-P1-5 PAY-1] 근무자 목록 **조회가 실패**했는가.
  ///
  ///   예전에는 실패도 빈 목록이 되어, 확정 건수가 있으면 `집계 데이터가 없습니다`
  ///   (+ 복원 버튼)로, 없으면 `확정된 급여가 없습니다`로 보였다. 둘 다 사실이
  ///   아닐 수 있고, 앞의 경우는 조회 실패에 **서버 재집계**를 권한다.
  bool _workersLoadFailed = false;

  /// [DU1 SubAdmin §5] 빈 목록의 이유 — 부모 없음 / 권한 거부 / 권한 확인 불가.
  ///   읽기 실패(`_workersLoadFailed`)와 섞지 않는다.
  bool _parentMissing = false;
  bool _accessDenied = false;
  bool _accessUnknown = false;
  bool _isRepairing = false;

  // 이체 취소 후 notTransferredCount가 변경될 수 있으므로 mutable로 유지
  late PayrollSummaryModel _liveSummary;

  /// [PAYROLL-DETAIL.32] 같은 이름이 둘 이상일 때만 채운다(uid → 'P-301'). 실패하면 비어 있고 이름만 보인다.
  Map<String, String> _personLabels = const {};

  /// [R7-P1-5 PAY-1] 건수를 모르는 상태. 집계 문서를 실제로 받으면 해제된다.
  late bool _countsUnknown = widget.countsUnknown;

  late final PayrollOverviewReads _reads =
      widget.reads ?? PayrollOverviewReads.of();

  // 필터·정렬 결과 캐시 — _workers/sort/search 변경 시 null로 무효화
  List<PayrollWorkerSummary>? _cachedFiltered;

  List<PayrollWorkerSummary> get _filteredWorkers {
    if (_cachedFiltered != null) return _cachedFiltered!;
    final workers = List<PayrollWorkerSummary>.of(_workers);
    switch (_sortOrder) {
      case _SortOrder.amountDesc:
        workers.sort((a, b) => b.totalPayout.compareTo(a.totalPayout));
      case _SortOrder.amountAsc:
        workers.sort((a, b) => a.totalPayout.compareTo(b.totalPayout));
      case _SortOrder.nameAsc:
        workers.sort((a, b) => a.name.compareTo(b.name));
      case _SortOrder.workDaysDesc:
        workers.sort((a, b) => b.workDays.compareTo(a.workDays));
    }
    if (_searchQuery.isEmpty) {
      return _cachedFiltered = workers;
    }
    final q = _searchQuery.toLowerCase();
    return _cachedFiltered = workers
        .where((w) => w.name.toLowerCase().contains(q))
        .toList();
  }

  @override
  void initState() {
    super.initState();
    _liveSummary = widget.summary;
    _searchCtrl.addListener(() {
      _searchDebounce?.cancel();
      _searchDebounce = Timer(const Duration(milliseconds: 300), () {
        if (!mounted) return;
        final q = _searchCtrl.text.trim();
        if (q == _searchQuery) return;
        setState(() { _searchQuery = q; _cachedFiltered = null; });
      });
    });
    _loadWorkers();
  }

  /// 지급현황 화면에서 돌아올 때 notTransferredCount 재조회
  ///
  /// [R5-RESIDUAL.1] 직접 Firestore get 에서 서버 경로로 옮겼다.
  ///
  ///   이 조회는 **있을 수도 없을 수도 있는** 문서를 본다. 아직 집계가
  ///   만들어지지 않은 달을 열어 두고 돌아올 수 있기 때문이다. 그런데 없는
  ///   문서에는 businessId 가 없어 Firestore rule 이 권한을 판정할 수 없다.
  ///   예전에는 그래서 "없으면 누구나 통과"로 열어 뒀고, 그 결과 권한 없는
  ///   사람이 존재 여부를 알아낼 수 있었다.
  ///
  ///   서버는 호출자가 준 businessId 를 급여 권한으로 검증한 뒤 답하므로
  ///   그 문제가 없다. 없음·권한 없음·실패를 각각 다르게 다룬다.
  Future<void> _refreshSummary() async {
    try {
      // [R7-P1-5 후속] **건수의 owner 는 원장이다.**
      //
      //   예전에는 집계 문서만 다시 읽어 `notTransferredCount` 까지 그 값으로
      //   덮었다. 트리거는 비동기라, 지급 현황에서 **이체를 취소하고 돌아오면**
      //   아직 반영되지 않은 낡은 값이 그 자리에 앉았고 P1-5 이후로는 그것이
      //   `확인 못함` 도 아닌 **확정된 사실**로 보였다(모름 해제).
      //   그래서 이 갱신도 개요 로더와 **같은 원장·같은 계산**을 쓴다.
      //   금액·인원은 집계 문서가 owner 로 남는다(트랜잭션 delta + 복구 CF).
      final ym = _liveSummary.yearMonth;
      final ledgerFuture = _reads.adminAttendances(
        businessId: _liveSummary.businessId,
        yearMonthGte: ym,
        yearMonthLte: ym,
      );
      // [ROOT-FUTURE] 나중에 await 하는(또는 앞에서 return 하면 아예 await 하지 않는) future — 먼저 실패해도 '처리되지 않은 오류'(Crashlytics fatal)로 새지 않게. await 하는 곳은 그대로 같은 오류를 받는다.
      ledgerFuture.ignore();
      final items = await _reads.payrollSummaries(
        businessId: _liveSummary.businessId,
        year: _liveSummary.year,
      );
      if (!mounted) return;
      final hit = items.firstWhere(
        (m) => m['id']?.toString() == _liveSummary.id,
        orElse: () => const <String, dynamic>{},
      );

      // 원장 — 실패·상한은 '모름'이고, 그때는 들고 있던 값을 건드리지 않는다.
      ({List<Map<String, dynamic>> items, bool limitReached})? ledgerResult;
      try {
        ledgerResult = await ledgerFuture;
      } catch (e) {
        debugPrint('⚠️ 미이체 원장 재조회 실패: $e');
      }
      if (!mounted) return;
      MonthLedgerCounts? counts = ledgerResult == null || ledgerResult.limitReached
          ? null
          : MonthLedgerCounts.fromItems(ledgerResult.items, _liveSummary.month);
      // [PAYROLL-ANNUAL-READ.48] 한 달이 원장 상한을 넘었으면 서버 월 집계로 센다(있을 때만).
      if (ledgerResult != null && ledgerResult.limitReached && _reads.monthLedgerCounts != null) {
        try {
          counts = MonthLedgerCounts.tryFromServer(await _reads.monthLedgerCounts!(
              businessId: _liveSummary.businessId, yearMonth: ym));
        } catch (e) {
          debugPrint('⚠️ 월 집계 재조회 실패: $e');
        }
        if (!mounted) return;
      }
      final ledger = counts;
      // 끝까지 세지 못했으면 들고 있던 숫자를 **사실로 다시 확인하지 않는다**.
      if (ledger == null && (ledgerResult == null || ledgerResult.limitReached)) {
        setState(() => _countsUnknown = true);
      }

      // 없는 것은 정상이다 — 아직 집계가 만들어지지 않은 달이다.
      //   화면이 들고 있는 금액·인원을 빈 값으로 덮지 않는다.
      final fresh = hit.isEmpty
          ? null
          : PayrollSummaryModel.tryFromMap(
              Map<String, dynamic>.from(hit)..remove('id'), _liveSummary.id);

      if (fresh == null && ledger == null) return;
      setState(() {
        final base = fresh ?? _liveSummary;
        _liveSummary = PayrollSummaryModel(
          id: base.id,
          businessId: base.businessId,
          yearMonth: base.yearMonth,
          year: base.year,
          month: base.month,
          totalPayout: base.totalPayout,
          // 파생(`확정 - 미이체`)이 한 owner 안에서 끝나게 둘 다 원장에서.
          confirmedCount: ledger == null
              ? base.confirmedCount
              : ledger.notTransferred + ledger.transferred,
          workerCount: base.workerCount,
          pendingCount:
              ledger == null ? base.pendingCount : ledger.pending,
          notTransferredCount: ledger == null
              ? base.notTransferredCount
              : ledger.notTransferred,
          workers: base.workers,
          updatedAt: base.updatedAt,
        );
        // 원장을 실제로 받았을 때만 모름이 풀린다.
        if (ledger != null) _countsUnknown = false;
      });
    } on FirebaseFunctionsException catch (e) {
      // 권한 없음과 통신 실패를 "집계 없음"으로 바꾸지 않는다.
      debugPrint('❌ 급여 요약 새로고침 실패(${e.code}): ${e.message}');
      if (!mounted) return;
      ToastHelper.showError(e.code == 'permission-denied'
          ? '급여 정보를 볼 권한이 없습니다'
          : '새로고침에 실패했습니다');
    } catch (e) {
      debugPrint('❌ 급여 요약 새로고침 실패: $e');
      if (mounted) ToastHelper.showError('새로고침에 실패했습니다');
    }
  }

  Future<void> _loadWorkers() async {
    // [DU1 SubAdmin §5] 집계 문서가 없는 달 — 읽으면 권한이 있어도 거부된다. 읽지 않는다.
    if (!widget.summaryDocExists) {
      setState(() {
        _workers = [];
        _workersLoading = false;
        _workersLoadFailed = false;
        _parentMissing = true;
        _accessDenied = false;
        _accessUnknown = false;
        _cachedFiltered = null;
      });
      return;
    }
    try {
      final rows = await _reads.workerSummaries(widget.summary.id);
      final loaded = rows
          .map((r) => PayrollWorkerSummary.tryFromMap(r.id, r.data))
          .whereType<PayrollWorkerSummary>()
          .toList();
      if (!mounted) return;
      setState(() {
        _workers = loaded;
        _workersLoading = false;
        _workersLoadFailed = false;
        _parentMissing = false;
        _accessDenied = false;
        _accessUnknown = false;
        _cachedFiltered = null;
      });
      unawaited(_loadPersonLabelsForDuplicates(loaded));
    } on FirebaseException catch (e) {
      debugPrint('⚠️ workers 서브컬렉션 로드 실패(${e.code}): ${e.message}');
      if (e.code == 'permission-denied') {
        // rule 거부는 '권한 없음'과 '그 사이 부모 삭제'를 가르지 못한다 → 급여 권한 CF 로 다시 본다.
        await _resolveWorkersDenied();
        return;
      }
      _markWorkersReadFailed();
    } catch (e) {
      // timeout 등 — 읽기 실패다(없음·권한 없음으로 바꾸지 않는다).
      debugPrint('⚠️ workers 서브컬렉션 로드 실패: $e');
      _markWorkersReadFailed();
    }
  }

  void _markWorkersReadFailed() {
    if (!mounted) return;
    setState(() {
      _workersLoading = false;
      _workersLoadFailed = true;
      _parentMissing = false;
      _accessDenied = false;
      _accessUnknown = false;
    });
  }

  /// [DU1 SubAdmin §5] 하위 목록 거부 뒤 서버(급여 권한 검증)로 사실을 가른다.
  ///   CF 거부 → 권한 없음 · CF 에 그 달 없음 → 부모 없음 · CF 에 있음 → 판정 불일치(권한 확인 불가).
  Future<void> _resolveWorkersDenied() async {
    bool denied = false, missing = false, unknown = false, failed = false;
    try {
      final items = await _reads.payrollSummaries(
        businessId: widget.summary.businessId,
        year: widget.summary.year,
      );
      final has = items.any((m) => m['id']?.toString() == widget.summary.id);
      missing = !has;
      unknown = has;
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') {
        denied = true;
      } else {
        failed = true;
      }
    } catch (_) {
      failed = true;
    }
    if (!mounted) return;
    setState(() {
      _workers = [];
      _cachedFiltered = null;
      _workersLoading = false;
      _workersLoadFailed = failed;
      _parentMissing = missing;
      _accessDenied = denied;
      _accessUnknown = unknown;
    });
  }

  /// [DU1 SubAdmin §5] 부모 없는 달의 빈 화면 문장 — 원장 건수를 owner 로 쓴다.
  ///   확정분이 있으면 기존 '집계 데이터 없음 + 복원' 분기로 보낸다(여기서 null).
  ({IconData icon, String title, String? subtitle})? _parentMissingCopy() {
    if (!_parentMissing || _searchQuery.isNotEmpty) return null;
    // [DU1 MONTH-COUNT-UNKNOWN] 모름이 먼저다 — 원장 재조회가 실패/상한이면 들고 있는 확정 건수는
    //   이전 값이라 현재 사실이 아니다. 그 숫자로 '집계 누락·복원'을 권하지 않는다.
    if (_countsUnknown) {
      return (icon: Icons.help_outline, title: '이 달 급여 건수를 확인하지 못했어요', subtitle: null);
    }
    if (_liveSummary.confirmedCount > 0) return null; // 원장이 센 확정분 — 기존 집계 누락·복원 분기
    final pending = _liveSummary.pendingCount;
    if (pending > 0) {
      return (
        icon: Icons.hourglass_empty_rounded,
        title: '확정 전 급여 ${FormatHelper.formatNumber(pending)}건이 있어요',
        subtitle: '급여가 확정되면 이 목록에 나와요',
      );
    }
    return null; // 원장을 끝까지 셌고 0 — 기존 '확정된 급여가 없습니다'
  }

  /// [PAYROLL-DETAIL.32] 동명이인 구분 — 같은 이름을 가진 사람들의 인력번호만 읽는다.
  ///   실패는 조용히 넘긴다(목록·금액은 그대로, 번호만 없다).
  Future<void> _loadPersonLabelsForDuplicates(List<PayrollWorkerSummary> workers) async {
    final read = _reads.personLabels;
    if (read == null) return;
    final byName = <String, List<String>>{};
    for (final w in workers) {
      byName.putIfAbsent(w.name, () => []).add(w.workerId);
    }
    final uids = [
      for (final e in byName.entries)
        if (e.key.isNotEmpty && e.value.length > 1) ...e.value,
    ];
    if (uids.isEmpty) return;
    try {
      final labels = await read(businessId: widget.summary.businessId, uids: uids);
      if (!mounted) return;
      setState(() => _personLabels = labels);
    } catch (e) {
      debugPrint('⚠️ 동명이인 인력번호 조회 실패(번호 없이 표시): $e');
    }
  }

  // payroll_summaries 문서 누락 시 서버에서 재집계 후 overview 리로드 신호 반환
  Future<void> _repairSummary() async {
    setState(() => _isRepairing = true);
    try {
      await _reads.repairSummary(
        businessId: widget.summary.businessId,
        yearMonth: widget.summary.yearMonth,
      );
      if (!mounted) return;
      ToastHelper.showSuccess('집계가 복원되었습니다.');
      Navigator.pop(context, true); // overview에서 true 수신 시 리로드
    } catch (e) {
      if (!mounted) return;
      ToastHelper.showError('복원 실패: $e');
    } finally {
      if (mounted) setState(() => _isRepairing = false);
    }
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final filtered = _filteredWorkers;
    final parentMissingCopy = _parentMissingCopy();

    // [DESIGN-PATCH-1] GradientScaffold → AppPageScaffold — 관리자 Shell 정규화
    // home / notification — refresh 없음 (현 상태 유지)
    return AppPageScaffold(
      title: '${widget.summary.year}년 ${widget.summary.month}월 급여현황',
      actions: [
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
      ],
      body: Column(
        children: [
          _buildSummaryHeader(context, theme),
          // 검색 바 + 정렬 버튼
          Row(
            children: [
              Expanded(
                child: AppSearchBar(
                  controller: _searchCtrl,
                  hintText: '근무자 이름으로 검색',
                  padding: EdgeInsets.fromLTRB(
                    ResponsiveHelper.spacing(context, 16),
                    ResponsiveHelper.spacing(context, 8),
                    0,
                    ResponsiveHelper.spacing(context, 8),
                  ),
                ),
              ),
              IconButton(
                onPressed: _showSortSheet,
                icon: Icon(
                  Icons.sort,
                  color: _sortOrder == _SortOrder.amountDesc
                      ? AppColors.grey400
                      : theme.primaryColor,
                ),
              ),
            ],
          ),
          Expanded(
            child: _workersLoading
                ? const PayrollWorkerListSkeleton()
                : filtered.isEmpty
                    // [R7-P1-5 PAY-1] 조회 실패를 먼저 가른다. 실패에 서버 재집계
                    //   (복원)를 권하면 원인을 틀리게 말하는 것이다.
                    // [DU1 SubAdmin §5] 읽기 실패·권한 확인 불가는 다시 시도, 권한 거부는 안내만,
                    //   부모 없는 달은 원장 건수로 말한다(확정분이 있으면 아래 복원 분기).
                    ? (_workersLoadFailed || _accessUnknown)
                        ? Column(
                            children: [
                              Expanded(
                                child: AppEmptyState(
                                  icon: _accessUnknown
                                      ? Icons.help_outline
                                      : Icons.cloud_off_outlined,
                                  title: _accessUnknown
                                      ? '권한을 확인하지 못했어요'
                                      : '근무자 목록을 불러오지 못했습니다',
                                ),
                              ),
                              SafeArea(
                                top: false,
                                child: Padding(
                                  padding: EdgeInsets.fromLTRB(
                                    ResponsiveHelper.spacing(context, 24),
                                    0,
                                    ResponsiveHelper.spacing(context, 24),
                                    ResponsiveHelper.spacing(context, 24),
                                  ),
                                  child: SizedBox(
                                    width: double.infinity,
                                    child: OutlinedButton.icon(
                                      onPressed: () {
                                        setState(() {
                                          _workersLoading = true;
                                          _workersLoadFailed = false;
                                          _accessUnknown = false;
                                        });
                                        unawaited(_loadWorkers());
                                      },
                                      icon: const Icon(Icons.refresh),
                                      label: const Text('다시 시도'),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          )
                    : _accessDenied
                        ? const AppEmptyState(
                            icon: Icons.lock_outline,
                            title: '급여 정보를 볼 권한이 없습니다',
                          )
                    : parentMissingCopy != null
                        ? AppEmptyState(
                            icon: parentMissingCopy.icon,
                            title: parentMissingCopy.title,
                            subtitle: parentMissingCopy.subtitle,
                          )
                    // [DU1 MONTH-COUNT-UNKNOWN] 확정 건수 owner 는 원장 갱신을 받는 _liveSummary 다.
                    : (_searchQuery.isEmpty && _liveSummary.confirmedCount > 0
                        // payroll_summaries 문서 누락 — 집계 복원 버튼 노출
                        ? Column(
                            children: [
                              // Expanded로 감싸야 AppEmptyState 내 LayoutBuilder.maxHeight가 유한값
                              Expanded(
                                child: AppEmptyState(
                                  icon: Icons.warning_amber_outlined,
                                  title: '집계 데이터가 없습니다',
                                ),
                              ),
                              SafeArea(
                                top: false,
                                child: Padding(
                                  padding: EdgeInsets.fromLTRB(
                                    ResponsiveHelper.spacing(context, 24),
                                    0,
                                    ResponsiveHelper.spacing(context, 24),
                                    ResponsiveHelper.spacing(context, 24),
                                  ),
                                  child: SizedBox(
                                    width: double.infinity,
                                    child: ElevatedButton.icon(
                                      onPressed: _isRepairing ? null : _repairSummary,
                                      icon: _isRepairing
                                          ? const SizedBox(
                                              width: 14, height: 14,
                                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                          : const Icon(Icons.refresh),
                                      label: Text(_isRepairing ? '복원 중…' : '집계 데이터 복원'),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          )
                        : AppEmptyState(
                            icon: _searchQuery.isNotEmpty
                                ? Icons.search_off
                                : Icons.inbox_outlined,
                            title: _searchQuery.isNotEmpty
                                ? '"$_searchQuery" 검색 결과 없음'
                                : '확정된 급여가 없습니다',
                          ))
                    : ListView.separated(
                        padding: EdgeInsets.all(
                            ResponsiveHelper.spacing(context, 16)),
                        itemCount: filtered.length,
                        separatorBuilder: (_, __) =>
                            SizedBox(height: ResponsiveHelper.spacing(context, 8)),
                        itemBuilder: (context, i) =>
                            _buildWorkerTile(context, theme, filtered[i]),
                      ),
          ),
        ],
      ),
    );
  }

  void _showSortSheet() {
    final options = [
      (_SortOrder.amountDesc,   '지급액 높은순',   Icons.arrow_downward),
      (_SortOrder.amountAsc,    '지급액 낮은순',   Icons.arrow_upward),
      (_SortOrder.nameAsc,      '이름순',          Icons.sort_by_alpha),
      (_SortOrder.workDaysDesc, '근무 건수 많은순',  Icons.calendar_today),
    ];
    DialogHelper.showSheet(
      context,
      isScrollControlled: true,
      builder: (ctx) {
        final theme = Theme.of(context);
        return Container(
          decoration: const BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 핸들
              Container(
                margin: const EdgeInsets.only(top: 12),
                width: 40, height: 4,
                decoration: BoxDecoration(
                  color: AppColors.grey300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              // 타이틀 + 닫기 버튼
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 8, 10),
                child: Row(children: [
                  Expanded(
                    child: Text('정렬',
                        style: ResponsiveHelper.subtitleStyle(context)
                            .copyWith(fontWeight: FontWeight.bold)),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(ctx),
                    icon: const Icon(Icons.close, color: AppColors.grey600),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ]),
              ),
              const Divider(height: 1, color: AppColors.grey100),
              // 옵션 목록
              ...options.map((e) {
                final (order, label, icon) = e;
                final isSelected = _sortOrder == order;
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () {
                          setState(() { _sortOrder = order; _cachedFiltered = null; });
                          Navigator.pop(ctx);
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 20, vertical: 14),
                          child: Row(children: [
                            Icon(icon,
                                size: 18,
                                color: isSelected
                                    ? theme.primaryColor
                                    : AppColors.grey500),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Text(label,
                                  style: ResponsiveHelper.bodyStyle(context,
                                      color: isSelected
                                          ? theme.primaryColor
                                          : AppColors.grey800,
                                      fontWeight: isSelected
                                          ? FontWeight.w700
                                          : FontWeight.normal)),
                            ),
                            if (isSelected)
                              Icon(Icons.check_rounded,
                                  size: 18, color: theme.primaryColor),
                          ]),
                        ),
                      ),
                    ),
                    const Divider(height: 1, color: AppColors.grey100),
                  ],
                );
              }),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSummaryHeader(BuildContext context, ThemeData theme) {
    // CF 트리거(비동기) 갱신 지연으로 confirmedCount < notTransferredCount 가능 → clamp
    final transferredCount = (_liveSummary.confirmedCount - _liveSummary.notTransferredCount).clamp(0, 999999);
    final pendingCount     = _liveSummary.notTransferredCount;
    // [R7-P1-5 PAY-1] 건수를 모를 때는 `이체 완료 N건`을 빼서 만들지 않는다 —
    //   미이체가 0 으로 들어오므로 그 뺄셈은 **전부 이체됐다**고 말해 버린다.
    //   새로고침(`_refreshSummary`)이 집계 문서를 실제로 받아오면 해제된다.
    final countsUnknown    = _countsUnknown;
    final hasPending       = !countsUnknown && pendingCount > 0;

    final payButton = OutlinedButton.icon(
      onPressed: () async {
        await Navigator.push(
          context,
          MaterialPageRoute(
            // [.81 MONTH-PENDING-SCOPE] 이 달의 `미이체 N건`을 그대로 연다 — 오늘 날짜 보기로 열면
            //   지난 지급 예정일 건이 빠져 `미이체 2` 아래 `0명`이 됐다(DEV 재현).
            builder: (_) => PayrollPaymentDashboardScreen(
              businessId: widget.summary.businessId,
              year: widget.summary.year,
              month: widget.summary.month,
              pendingWholeMonth: true,
            ),
          ),
        );
        if (mounted) await _refreshSummary();
      },
      icon: Icon(Icons.receipt_long_outlined,
          size: ResponsiveHelper.iconSize(context, 13),
          color: theme.primaryColor),
      label: Text('지급 현황',
          style: ResponsiveHelper.tinyStyle(context,
              color: theme.primaryColor,
              fontWeight: FontWeight.w600)),
      style: OutlinedButton.styleFrom(
        padding: EdgeInsets.symmetric(
          horizontal: ResponsiveHelper.spacing(context, 10),
          vertical: ResponsiveHelper.spacing(context, 5),
        ),
        side: BorderSide(color: theme.primaryColor.withValues(alpha: 0.4)),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20)),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );

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
          // ── 1행: 총 지급액 히어로 + 지급 현황 버튼
          // [R7-P1-5 PAY-4] 왼쪽 묶음에 flex 가 없어서 실제 금액(7자리)과 버튼이
          //   함께 서면 가로로 넘쳤다(390dp 에서 18px). 금액은 줄이지 않고
          //   남는 공간을 차지하게 하되, 모자라면 **라벨부터** 줄인다.
          // [AMOUNT-LAYOUT.34] 채택 — 라벨·버튼 줄과 금액 줄을 나눈다(기기 비교: 392·2.0 에서 '1,322,099,' / '341원' 대신 한 줄). 금액은 전체 폭을 받고, 한 줄에
          //   안 들어가면 기본 크기만 19→16 범위에서 낮춘 뒤(사용자 배율 유지), 그래도 길면 쉼표 뒤 줄바꿈.
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(Icons.payments_outlined, size: 16, color: AppColors.successDark),
              SizedBox(width: ResponsiveHelper.spacing(context, 6)),
              Expanded(
                child: Text(TextLayout.keepWords('총 지급액'),
                    semanticsLabel: '총 지급액',
                    style: ResponsiveHelper.smallStyle(context, color: AppColors.grey700)),
              ),
              SizedBox(width: ResponsiveHelper.spacing(context, 6)),
              payButton,
            ],
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 4)),
          AmountText.total(
            _liveSummary.formattedTotalPayout,
            style: ResponsiveHelper.titleStyle(context, color: AppColors.textPrimary),
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 8)),
          const Divider(height: 1, color: AppColors.grey200),
          SizedBox(height: ResponsiveHelper.spacing(context, 8)),
          // ── 2행: 이체완료 | 미이체 상태
          // [R7-P1-5 PAY-4] 세 묶음(이체완료 · 미이체 · 인원/건수)이 flex 없이
          //   한 Row 에 있고 사이에 Spacer 가 있었다. 값이 길어지면(확인 못함,
          //   네 자리 건수) 가로로 넘쳐 오른쪽 칩이 잘렸다 — 프로젝트 규칙대로
          //   Wrap 으로 줄바꿈을 허용한다. 짝인 이체완료·미이체는 붙여 둔다.
          Wrap(
            spacing: ResponsiveHelper.spacing(context, 12),
            runSpacing: ResponsiveHelper.spacing(context, 6),
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
            Row(mainAxisSize: MainAxisSize.min, children: [
              Container(
                width: 8, height: 8,
                decoration: BoxDecoration(
                  color: countsUnknown ? AppColors.grey300 : AppColors.success,
                  shape: BoxShape.circle),
              ),
              SizedBox(width: ResponsiveHelper.spacing(context, 5)),
              Text('이체 완료',
                  style: ResponsiveHelper.tinyStyle(context,
                      color: AppColors.grey500)),
              SizedBox(width: ResponsiveHelper.spacing(context, 4)),
              Text(countsUnknown ? '확인 못함' : '${FormatHelper.formatNumber(transferredCount)}건',
                  style: ResponsiveHelper.smallStyle(context,
                      color: countsUnknown
                          ? AppColors.grey500
                          : AppColors.successDark,
                      fontWeight: FontWeight.w700)),
            ]),
            Row(mainAxisSize: MainAxisSize.min, children: [
              Container(
                width: 8, height: 8,
                decoration: BoxDecoration(
                  color: hasPending ? AppColors.warning : AppColors.grey300,
                  shape: BoxShape.circle,
                ),
              ),
              SizedBox(width: ResponsiveHelper.spacing(context, 5)),
              Text('미이체',
                  style: ResponsiveHelper.tinyStyle(context,
                      color: AppColors.grey500)),
              SizedBox(width: ResponsiveHelper.spacing(context, 4)),
              Text(countsUnknown ? '확인 못함' : '${FormatHelper.formatNumber(pendingCount)}건',
                  style: ResponsiveHelper.smallStyle(context,
                      color: countsUnknown
                          ? AppColors.grey500
                          : (hasPending ? AppColors.warningDark : AppColors.grey400),
                      fontWeight: FontWeight.w700)),
            ]),
            Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.people_outline, size: 12, color: AppColors.grey400),
              SizedBox(width: ResponsiveHelper.spacing(context, 4)),
              Text('${FormatHelper.formatNumber(widget.summary.workerCount)}명',
                  style: ResponsiveHelper.tinyStyle(context,
                      color: AppColors.grey500,
                      fontWeight: FontWeight.w600)),
              SizedBox(width: ResponsiveHelper.spacing(context, 10)),
              Icon(Icons.receipt_outlined, size: 12, color: AppColors.grey400),
              SizedBox(width: ResponsiveHelper.spacing(context, 4)),
              Text('${FormatHelper.formatNumber(_liveSummary.confirmedCount)}건',
                  style: ResponsiveHelper.tinyStyle(context,
                      color: AppColors.grey500,
                      fontWeight: FontWeight.w600)),
            ]),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildWorkerTile(
    BuildContext context,
    ThemeData theme,
    PayrollWorkerSummary worker,
  ) {
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => PayrollWorkerDetailScreen(
            businessId: widget.summary.businessId,
            workerId: worker.workerId,
            workerName: worker.name,
            year: widget.summary.year,
            month: widget.summary.month,
          ),
        ),
      ),
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
        clipBehavior: Clip.hardEdge,
        child: Stack(
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(
                4 + ResponsiveHelper.spacing(context, 14),
                ResponsiveHelper.spacing(context, 13),
                ResponsiveHelper.spacing(context, 14),
                ResponsiveHelper.spacing(context, 13),
              ),
              // [UI-INTEGRATION.33] 이름·건수 | 금액 한 줄이 들어가면 예전 배치 그대로(금액은 자기 폭),
              //   안 들어가면(큰 글자·억 단위) 금액을 이름 아래로 내린다 — 금액 칸이 이름 칸을 반으로
              //   자르지도('합성 / 대량0334'), 금액이 말줄임되지도 않는다. 판단은 행에서 한 번.
              child: Builder(builder: (context) {
                final amountStyle = ResponsiveHelper.bodyStyle(context).copyWith(
                  fontWeight: FontWeight.bold,
                  color: AppColors.successDark,
                );
                // [AMOUNT-LAYOUT.34] 목록 행은 .33 배치 유지(기기 비교: 1.0 에서 금액을 늘 아래로 내리면 행이 길어져 훑기 어렵다).
                //   한 줄에 들어가면 오른쪽, 아니면 이름 아래 — 공통 AmountText.list(기본 15→13 범위).
                final Widget amountText = AmountText.list(FormatHelper.formatWage(worker.totalPayout),
                        style: amountStyle);
                final chevron = Icon(Icons.chevron_right,
                    size: ResponsiveHelper.iconSize(context, 16),
                    color: AppColors.grey300);
                final oneLine = TextLayout.fits(context, MediaQuery.sizeOf(context).width - 72, 280);
                return Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // [PAYROLL-DETAIL.32] 같은 이름이면 인력번호를 붙인다 — 누구의 상세로 가는지 가른다.
                            //   이름은 말줄임하지 않고 낱말 단위로 줄을 바꾼다.
                            Builder(builder: (context) {
                              final name = worker.name.isNotEmpty ? worker.name : '(이름 없음)';
                              final label = _personLabels[worker.workerId];
                              final shown = label == null ? name : '$name · $label';
                              return Text(
                                TextLayout.phrases(shown),
                                semanticsLabel: shown,
                                style: ResponsiveHelper.bodyStyle(context)
                                    .copyWith(fontWeight: FontWeight.w600),
                              );
                            }),
                            SizedBox(height: ResponsiveHelper.spacing(context, 2)),
                            Text(
                              // [R7-P1-5 PAY-1] projection 의 workDays 는 확정·이체된
                              //   attendance 1건당 +1 이다(서버 srvPayrollContribution).
                              //   같은 날 두 근무를 확정받으면 2 가 되므로 날짜 수가 아니다.
                              '확정 근무 ${FormatHelper.formatNumber(worker.workDays)}건',
                              style: ResponsiveHelper.tinyStyle(context,
                                  color: AppColors.grey500),
                            ),
                            if (!oneLine) ...[
                              SizedBox(height: ResponsiveHelper.spacing(context, 4)),
                              amountText,
                            ],
                          ],
                        ),
                      ),
                      if (oneLine)
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            amountText,
                            SizedBox(height: ResponsiveHelper.spacing(context, 2)),
                            chevron,
                          ],
                        )
                      else
                        chevron,
                    ],
                  );
              }),
            ),
            Positioned(
              top: 0, left: 0, bottom: 0,
              child: Container(
                width: 4,
                color: theme.primaryColor.withValues(alpha: 0.6),
              ),
            ),
          ],
        ),
      ),
    );
  }

}

// ── 오늘 처리할 송금 배너 ────────────────────────────────────────────

class _TodayPaymentBanner extends StatelessWidget {
  /// null = 끝까지 세지 못했다 — 숫자 대신 조회 미완료와 다시 시도를 보인다.
  final int? count;
  final VoidCallback onTap;

  static const String unknownText = '송금 대상을 끝까지 확인하지 못했어요 · 눌러서 다시 시도';

  const _TodayPaymentBanner({required this.count, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        margin: EdgeInsets.fromLTRB(ResponsiveHelper.spacing(context, 16), ResponsiveHelper.spacing(context, 12), ResponsiveHelper.spacing(context, 16), 0),
        padding: EdgeInsets.symmetric(horizontal: ResponsiveHelper.spacing(context, 16), vertical: ResponsiveHelper.spacing(context, 12)),
        decoration: BoxDecoration(
          color: AppColors.warningBg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.warning.withValues(alpha: 0.4)),
        ),
        // [SCALE-BALANCE.34] 큰 글자에서 설명이 2~3줄이면 아이콘이 세로 가운데에 떠 제목과 어긋났다 — 첫 줄에 맞춘다.
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.warning.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.payment,
                  size: ResponsiveHelper.iconSize(context, 20), color: AppColors.warningDark),
            ),
            SizedBox(width: ResponsiveHelper.spacing(context, 12)),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '오늘 처리할 송금',
                    style: ResponsiveHelper.smallStyle(context, color: AppColors.warningDark, fontWeight: FontWeight.w700),
                  ),
                  // [UI-BALANCE.38] 큰 글자에서 '이하|인' 으로 끊겼다 — 낱말 단위(표시만).
                  Text(
                    TextLayout.keepWords(count == null
                        ? unknownText
                        : '지급 예정일이 오늘 이하인 확정 급여 $count건'),
                    semanticsLabel: count == null
                        ? unknownText
                        : '지급 예정일이 오늘 이하인 확정 급여 $count건',
                    style: ResponsiveHelper.smallStyle(context, color: AppColors.warningDark),
                  ),
                ],
              ),
            ),
            Icon(count == null ? Icons.refresh : Icons.chevron_right,
                color: AppColors.warningDark),
          ],
        ),
      ),
    );
  }
}

