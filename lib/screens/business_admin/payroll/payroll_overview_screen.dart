import 'dart:async';

import 'package:flutter/material.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:provider/provider.dart';

import '../../../models/core/attendance_model.dart';
import '../../../models/core/payroll_summary_model.dart';
import 'payroll_overview_reads.dart';
import '../../../providers/user_provider.dart';
import '../../../theme/app_colors.dart';
import '../../../utils/dialog_helper.dart';
import '../../../utils/format_helper.dart';
import '../../../utils/responsive_helper.dart';
import '../../../utils/toast_helper.dart';
import 'payroll_worker_detail_screen.dart';
import 'payroll_payment_dashboard_screen.dart';
import '../../../screens/common/notification_screen.dart';
import '../../../utils/navigation_helper.dart';
import '../../../widgets/common/app_page_scaffold.dart';
import '../../../widgets/common/notification_badge.dart';
import '../../../widgets/common/skeleton_widget.dart';
import '../../../widgets/common/app_search_bar.dart';
import '../../../widgets/common/app_empty_state.dart';
import '../../../utils/business_picker_helper.dart';

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
  bool _isLoading = true;
  bool _noData = false; // Tab 루트에서 picker 취소 / 사업장 없음 시 empty state
  bool _accessDenied = false; // [5C.1A-SCREEN-01] canManageWage=false SubAdmin
  // [CROSS-DOMAIN-R5.1F.5] 권한을 확인하지 못한 상태 — 거부와 다른 말이다.
  bool _accessUnverified = false;
  String? _loadError;
  List<PayrollSummaryModel> _summaries = [];
  int _todayPaymentCount = 0; // null(조회실패) 시 이전 값 유지

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

    if (!_accessDenied) return;

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
        // Tab 루트일 때 pop 불가 → noData empty state. Push 컨텍스트에서도 empty state가 더 명확함.
        if (mounted) setState(() { _isLoading = false; _noData = true; });
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
      await Future.wait([
        _loadYear(_selectedYear),
        _loadTodayCount(),
      ]);
    } catch (e) {
      if (mounted) setState(() { _isLoading = false; _loadError = e.toString(); });
    }
  }

  /// [R7-P1-5 PAY-1] 출근 집계 CF 가 실패했는가.
  ///
  ///   월별 `미확정`·`미이체` 건수는 `callableGetAdminAttendances` 에서만 온다.
  ///   그 호출이 실패하면 예전에는 12개월 전부 0 이 되어, 금액은 그대로인데
  ///   미이체 줄이 사라졌다 — **다 이체된 달처럼** 보였다. 0 과 모름을 구분한다.
  bool _attCountsUnknown = false;

  Future<void> _loadYear(int year) async {
    final bizId = _businessId;
    if (bizId == null) return;
    if (!mounted) return;
    setState(() { _isLoading = true; _loadError = null; });

    try {
      // [PERF] 두 CF 병렬 호출 — 순차 최대 90초 → 병렬로 절반 단축
      ({List<Map<String, dynamic>> items, bool limitReached})? attResult;
      final results = await Future.wait<Object?>([
        _reads.payrollSummaries(businessId: bizId, year: year),
        () async {
          try {
            attResult = await _reads.adminAttendances(
              businessId: bizId,
              yearMonthGte: '$year-01',
              yearMonthLte: '$year-12',
            );
          } catch (e) {
            debugPrint('⚠️ 출근 집계 CF 실패: $e');
            if (mounted) ToastHelper.showWarning('출근 집계를 불러오지 못했습니다. 새로고침 해주세요.');
          }
          return null;
        }(),
      ]);
      final psItemsRaw = results[0] as List<Map<String, dynamic>>;
      // [R7-P1-5 PAY-1] 출근 집계 실패 → 건수는 **모름**이다(0 이 아니다).
      // [R7-P1-5 후속] 상한에 걸린 응답도 모름이다 — 실제보다 작은 합계를
      //   사실처럼 보여주지 않는다(통계 서비스와 같은 fail-closed).
      final attUnknown = attResult == null || attResult!.limitReached;
      if (attResult?.limitReached == true) {
        debugPrint('⚠️ 출근 집계 상한 도달 — 월별 건수를 모름으로 둔다');
      }

      // 1. payroll_summaries 파싱
      // [RULE-FIX-CF 2026-07-13] 직접 Firestore → CF 이전, year 서버 필터링으로 전환
      final summaryMap = <int, PayrollSummaryModel>{};
      for (final e in psItemsRaw) {
        final raw = Map<String, dynamic>.from(e);
        final id = raw.remove('id') as String? ?? '';
        final m = PayrollSummaryModel.tryFromMap(raw, id);
        if (m != null) summaryMap[m.month] = m;
      }

      // 2. 미확정·미이체 — **원장 하나**에서 센다(공유 reading).
      final ledger = _LedgerMonthCounts.of(
          attResult?.items ?? const <Map<String, dynamic>>[]);
      final pendingByMonth      = ledger.pending;
      final confirmedByMonth    = ledger.notTransferred;
      final transferredByMonth  = ledger.transferred;
      final totalPayoutByMonth  = ledger.payout;
      final workersByMonth      = ledger.workers;
      final pendingResults        = pendingByMonth;
      final notTransferredResults = confirmedByMonth;

      // 3. 12개 PayrollSummaryModel 구성
      final summaries = List.generate(12, (i) {
        final month = i + 1;
        final mm    = month.toString().padLeft(2, '0');
        final pCount  = pendingResults[i];
        final ntCount = notTransferredResults[i];
        final tCount  = transferredByMonth[i]; // 이체완료 건수
        final existing = summaryMap[month];

        if (existing != null) {
          return PayrollSummaryModel(
            id: existing.id,
            businessId: existing.businessId,
            yearMonth: existing.yearMonth,
            year: existing.year,
            month: existing.month,
            totalPayout: existing.totalPayout,
            // [R7-P1-5 후속] `이체 완료` 는 `확정 - 미이체` 로 파생된다.
            //   두 항이 다른 owner 면 그 뺄셈은 한쪽의 지연을 다른 쪽에 섞는다.
            //   원장을 쓸 수 있으면 **같은 원장의 확정 건수**를 넣어 파생이
            //   정확히 이체완료 건수가 되게 한다(문서 없는 달의 식과 동일).
            confirmedCount:
                attUnknown ? existing.confirmedCount : (ntCount + tCount),
            workerCount: existing.workerCount,
            pendingCount: pCount,
            notTransferredCount: ntCount,
            workers: existing.workers,
            updatedAt: existing.updatedAt,
          );
        }

        // payroll_summaries 문서 없음 — transferred 포함해서 빈 달 여부 판단
        if (pCount == 0 && ntCount == 0 && tCount == 0) {
          return PayrollSummaryModel.empty(businessId: bizId, year: year, month: month);
        }

        // attendance에서 직접 집계 (confirmed + transferred 합산)
        return PayrollSummaryModel(
          id: '${bizId}_$year-$mm',
          businessId: bizId,
          yearMonth: '$year-$mm',
          year: year,
          month: month,
          totalPayout: totalPayoutByMonth[i],
          confirmedCount: ntCount + tCount, // 확정+이체완료 합계
          workerCount: workersByMonth[i].length,
          pendingCount: pCount,
          notTransferredCount: ntCount,
          workers: {},
          updatedAt: DateTime.now(),
        );
      });

      if (mounted) {
        setState(() {
          _summaries = summaries;
          _attCountsUnknown = attUnknown;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() { _loadError = e.toString(); _isLoading = false; });
    }
  }

  Future<void> _loadTodayCount() async {
    final bizId = _businessId;
    if (bizId == null) return;
    try {
      final count = await _reads.todayPaymentCount(bizId);
      if (mounted && count != null) setState(() => _todayPaymentCount = count);
    } catch (e) {
      debugPrint('⚠️ 오늘 급여 건수 조회 실패: $e');
    }
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
    // refresh / home / notification — PayrollPaymentDashboardScreen canonical order
    return AppPageScaffold(
      title: '급여 관리',
      actions: [
        IconButton(
          icon: const Icon(Icons.refresh_rounded),
          onPressed: () => _loadYear(_selectedYear),
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
      ],
      body: Column(
        children: [
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
            if (_todayPaymentCount > 0 && _businessId != null)
              _TodayPaymentBanner(
                count: _todayPaymentCount,
                onTap: () async {
                  final now = DateTime.now();
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => PayrollPaymentDashboardScreen(
                        businessId: _businessId!,
                        year: now.year,
                        month: now.month,
                      ),
                    ),
                  );
                  if (!mounted) return;
                  _loadTodayCount();
                },
              ),
            Expanded(child: _buildMonthGrid(theme)),
          ],
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

  Widget _buildMonthGrid(ThemeData theme) {
    final now = _now; // [PERF-7] 캐시된 필드 사용
    final gridPadding = ResponsiveHelper.spacing(context, 16);
    final columnSpacing = ResponsiveHelper.spacing(context, 12);
    return LayoutBuilder(
      builder: (context, constraints) {
        final itemWidth = (constraints.maxWidth - gridPadding * 2 - columnSpacing) / 2;
        // [R7-P1-5 PAY-4] 높이를 100dp 로 못박고 있었다. 기기 폭과 무관하게
        //   일정한 것은 맞지만 **OS 글자 배율은 반영되지 않는다** — 카드 안의
        //   네 줄(월·금액·인원/건수·미이체)이 배율을 그대로 받으므로 1.3 배만
        //   돼도 아래가 잘렸고, 기본 배율에서도 1px 이 모자랐다.
        //   글자를 줄이거나 배율을 무효화해서 덮지 않는다 — 줄 높이만큼 늘린다.
        //   네 줄의 base font 합(13+13+12+12=50)이 배율을 받는 부분이다.
        const baseTextPx = 50.0;
        final scaledText = MediaQuery.textScalerOf(context).scale(baseTextPx);
        // 글자는 font size 보다 줄 높이(≈1.25배)만큼 자리를 차지한다.
        final itemHeight = 104.0 + (scaledText - baseTextPx) * 1.25;
        final ratio = itemWidth / itemHeight;
        return GridView.builder(
          padding: ResponsiveHelper.listPadding(context),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: columnSpacing,
            mainAxisSpacing: ResponsiveHelper.spacing(context, 12),
            childAspectRatio: ratio,
          ),
          itemCount: 12,
          itemBuilder: (context, i) {
            final summary = _summaries[i];
            final isFuture = _selectedYear > now.year ||
                (_selectedYear == now.year && (i + 1) > now.month);
            return _buildMonthCard(theme, summary, isFuture);
          },
        );
      },
    );
  }

  Widget _buildMonthCard(ThemeData theme, PayrollSummaryModel summary, bool isFuture) {
    final isEmpty = summary.isEmpty || isFuture;
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
                    countsUnknown: _attCountsUnknown,
                  ),
                ),
              );
              if (!mounted) return;
              // 이체 처리/취소 등 변경사항이 있을 수 있으므로 항상 리로드
              _loadYear(_selectedYear);
            },
      child: Container(
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
                    color: isEmpty ? AppColors.grey400 : theme.primaryColor,
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
                  _attCountsUnknown ? '확인 못함' : '데이터 없음',
                  style: ResponsiveHelper.tinyStyle(context).copyWith(
                    color: AppColors.grey400,
                  ),
                )
            else ...[
              Text(
                summary.formattedTotalPayout,
                style: ResponsiveHelper.smallStyle(context).copyWith(
                  fontWeight: FontWeight.bold,
                  color: AppColors.successDark,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              SizedBox(height: ResponsiveHelper.spacing(context, 2)),
              Text(
                '${summary.workerCount}명 · ${summary.confirmedCount}건',
                style: ResponsiveHelper.tinyStyle(context).copyWith(
                  color: AppColors.grey500,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              // [R7-P1-5 PAY-1] 모름을 0 으로 말하지 않는다. 출근 집계가 실패하면
              //   미이체 줄을 지우지 않고 **확인하지 못했다**고 말한다 —
              //   줄이 없는 것과 0 건인 것은 관리자에게 같은 뜻이기 때문이다.
              if (_attCountsUnknown) ...[
                SizedBox(height: ResponsiveHelper.spacing(context, 2)),
                Text(
                  '미이체 확인 못함',
                  style: ResponsiveHelper.tinyStyle(context).copyWith(
                    color: AppColors.grey500,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ] else if (summary.notTransferredCount > 0) ...[
                SizedBox(height: ResponsiveHelper.spacing(context, 2)),
                Text(
                  '미이체 ${summary.notTransferredCount}',
                  style: ResponsiveHelper.tinyStyle(context).copyWith(
                    color: AppColors.error,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
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

/// [R7-P1-5 후속] 미이체·미확정의 **canonical 계산 하나**.
///
///   같은 `미이체` 를 개요는 출근 집계에서, 월 상세는 새로고침 때 집계 문서에서
///   읽고 있었다. 두 경로는 모집단·기간·단위가 같은 계약인데(둘 다 KST 월의
///   attendance 문서 수, confirmed 만, 노쇼·결근 0원 제외) 트리거 지연·누락으로
///   값이 갈릴 수 있었다 — 이체 취소 직후 복귀하면 낡은 값이 확정 사실로 보였다.
///   그래서 **원장(attendance)** 을 owner 로 정하고 두 화면이 이 계산을 공유한다.
///   집계 문서는 금액·인원의 owner 로 남는다(트랜잭션 delta + 복구 CF).
///
///   서버 `srvPayrollContribution` 과 같은 식이다 — 한쪽만 바꾸지 않는다.
class _LedgerMonthCounts {
  final List<int> pending;        // wagePending + wageCalculated (미확정)
  final List<int> notTransferred; // wageConfirmed (미이체)
  final List<int> transferred;    // wageTransferred (이체완료)
  final List<int> payout;         // 지급 대상 finalWage 합
  final List<Set<String>> workers;

  _LedgerMonthCounts._(
      this.pending, this.notTransferred, this.transferred, this.payout, this.workers);

  factory _LedgerMonthCounts.of(Iterable<Map<String, dynamic>> items) {
    final counts = _LedgerMonthCounts._(
      List.filled(12, 0),
      List.filled(12, 0),
      List.filled(12, 0),
      List.filled(12, 0),
      List.generate(12, (_) => <String>{}),
    );
    for (final data in items) {
      final ym = data['yearMonth'] as String?;
      final ws = data['wageStatus'] as String?;
      if (ym == null) continue;
      final parts = ym.split('-');
      if (parts.length != 2) continue;
      final month = int.tryParse(parts[1]);
      if (month == null || month < 1 || month > 12) continue;
      final idx = month - 1;
      if (ws == 'pending' || ws == 'calculated') {
        counts.pending[idx]++;
      } else if (ws == 'confirmed' || ws == 'transferred') {
        // [.6-P1] 노쇼·결근 0원은 근무일도 미이체 건수도 만들지 않는다.
        if (AttendanceModel.isNonPayableZeroOf(
            data['status'] as String?, data['finalWage'] as num?)) {
          continue;
        }
        if (ws == 'confirmed') {
          counts.notTransferred[idx]++;
        } else {
          counts.transferred[idx]++;
        }
        counts.payout[idx] += (data['finalWage'] as num?)?.toInt() ?? 0;
        final uid = data['userId'] as String?;
        if (uid != null) counts.workers[idx].add(uid);
      }
    }
    return counts;
  }
}

enum _SortOrder { amountDesc, amountAsc, nameAsc, workDaysDesc }

class PayrollMonthScreen extends StatefulWidget {
  final PayrollSummaryModel summary;

  /// [R7-P1-5 PAY-1] `미확정`·`미이체` 건수를 확인하지 못한 채 들어왔는가.
  ///   true 면 이 화면은 이체 완료 건수를 **계산해서 주장하지 않는다.**
  final bool countsUnknown;

  /// [R7-P1-5 PAY-4] 원시 외부 읽기 경계(개요에서 그대로 내려받는다).
  final PayrollOverviewReads? reads;

  const PayrollMonthScreen({
    super.key,
    required this.summary,
    this.countsUnknown = false,
    this.reads,
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
  bool _isRepairing = false;

  // 이체 취소 후 notTransferredCount가 변경될 수 있으므로 mutable로 유지
  late PayrollSummaryModel _liveSummary;

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
      final ledgerUnknown =
          ledgerResult == null || ledgerResult.limitReached;
      final monthIdx = _liveSummary.month - 1;
      final ledger = ledgerUnknown
          ? null
          : _LedgerMonthCounts.of(ledgerResult.items);

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
              : ledger.notTransferred[monthIdx] + ledger.transferred[monthIdx],
          workerCount: base.workerCount,
          pendingCount:
              ledger == null ? base.pendingCount : ledger.pending[monthIdx],
          notTransferredCount: ledger == null
              ? base.notTransferredCount
              : ledger.notTransferred[monthIdx],
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
        _cachedFiltered = null;
      });
    } catch (e) {
      // payroll_summaries 문서 미존재 시 workers 서브컬렉션 접근이 PERMISSION_DENIED 됨
      // → 에러 토스트 대신 조용히 실패 후 UI에서 "집계 데이터 복원" 버튼으로 처리
      debugPrint('⚠️ workers 서브컬렉션 로드 실패 (payroll_summaries 미존재 가능): $e');
      if (!mounted) return;
      setState(() {
        _workersLoading = false;
        _workersLoadFailed = true;
      });
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
                    ? _workersLoadFailed
                        ? Column(
                            children: [
                              Expanded(
                                child: AppEmptyState(
                                  icon: Icons.cloud_off_outlined,
                                  title: '근무자 목록을 불러오지 못했습니다',
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
                    : (_searchQuery.isEmpty && widget.summary.confirmedCount > 0
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
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.payments_outlined,
                      size: 16, color: AppColors.successDark),
                  SizedBox(width: ResponsiveHelper.spacing(context, 6)),
                  Flexible(
                    child: Text(
                      _liveSummary.formattedTotalPayout,
                      style: ResponsiveHelper.titleStyle(context,
                          color: AppColors.successDark),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  SizedBox(width: ResponsiveHelper.spacing(context, 6)),
                  Flexible(
                    child: Text('총 지급액',
                        style: ResponsiveHelper.tinyStyle(context,
                            color: AppColors.grey700),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                  ),
                ]),
              ),
              SizedBox(width: ResponsiveHelper.spacing(context, 6)),
              OutlinedButton.icon(
                onPressed: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => PayrollPaymentDashboardScreen(
                        businessId: widget.summary.businessId,
                        year: widget.summary.year,
                        month: widget.summary.month,
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
              ),
            ],
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
              Text(countsUnknown ? '확인 못함' : '$transferredCount건',
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
              Text(countsUnknown ? '확인 못함' : '$pendingCount건',
                  style: ResponsiveHelper.smallStyle(context,
                      color: countsUnknown
                          ? AppColors.grey500
                          : (hasPending ? AppColors.warningDark : AppColors.grey400),
                      fontWeight: FontWeight.w700)),
            ]),
            Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.people_outline, size: 12, color: AppColors.grey400),
              SizedBox(width: ResponsiveHelper.spacing(context, 4)),
              Text('${widget.summary.workerCount}명',
                  style: ResponsiveHelper.tinyStyle(context,
                      color: AppColors.grey500,
                      fontWeight: FontWeight.w600)),
              SizedBox(width: ResponsiveHelper.spacing(context, 10)),
              Icon(Icons.receipt_outlined, size: 12, color: AppColors.grey400),
              SizedBox(width: ResponsiveHelper.spacing(context, 4)),
              Text('${_liveSummary.confirmedCount}건',
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
              child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              worker.name.isNotEmpty ? worker.name : '(이름 없음)',
                              style: ResponsiveHelper.bodyStyle(context)
                                  .copyWith(fontWeight: FontWeight.w600),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            SizedBox(height: ResponsiveHelper.spacing(context, 2)),
                            Text(
                              // [R7-P1-5 PAY-1] projection 의 workDays 는 확정·이체된
                              //   attendance 1건당 +1 이다(서버 srvPayrollContribution).
                              //   같은 날 두 근무를 확정받으면 2 가 되므로 날짜 수가 아니다.
                              '확정 근무 ${worker.workDays}건',
                              style: ResponsiveHelper.tinyStyle(context,
                                  color: AppColors.grey500),
                            ),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            FormatHelper.formatWage(worker.totalPayout),
                            style: ResponsiveHelper.bodyStyle(context).copyWith(
                              fontWeight: FontWeight.bold,
                              color: AppColors.successDark,
                            ),
                          ),
                          SizedBox(height: ResponsiveHelper.spacing(context, 2)),
                          Icon(Icons.chevron_right,
                              size: ResponsiveHelper.iconSize(context, 16),
                              color: AppColors.grey300),
                        ],
                      ),
                    ],
                  ),
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
  final int count;
  final VoidCallback onTap;

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
        child: Row(
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
                  Text(
                    '지급 예정일이 오늘 이하인 확정 급여 $count건',
                    style: ResponsiveHelper.smallStyle(context, color: AppColors.warningDark),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: AppColors.warningDark),
          ],
        ),
      ),
    );
  }
}

