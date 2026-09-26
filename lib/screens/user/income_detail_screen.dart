import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/core/application_model.dart';
import '../../models/core/attendance_model.dart';
import '../../providers/user_provider.dart';
import '../../services/firestore_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';
import '../../utils/calendar_helper.dart';
import '../../utils/dialog_helper.dart';
import '../../utils/format_helper.dart';
import '../../utils/toast_helper.dart';
import '../../widgets/section_header.dart';
import 'wage_detail_screen.dart';

/// [.6-P2] 근무 내역 한 줄.
///
/// 예전에는 이 목록이 **지원서**였다. 그래서 지원서가 취소·해지되면
/// 실제로 일한 과거 근무까지 목록에서 사라졌다 — 월 합계는 근태에서
/// 나오므로 "이번 달 32만원"이라고 써 놓고 아래 목록은 비어 있었다.
///
/// 과거에 일했다는 사실은 근태가 갖고 있고, 지원서는 지금의 약속 상태일
/// 뿐이다. 그래서 줄의 근거를 둘로 나눈다.
class _IncomeRow {
  const _IncomeRow({required this.date, this.app, this.att});

  /// 줄에 찍히는 날짜. 과거 근무는 실제 일한 날, 예정은 지원서 기준일.
  final DateTime date;

  /// 표시용 맥락(사업장명·업무명·예정 금액). 없을 수 있다.
  final ApplicationModel? app;

  /// 실제 근무·급여의 canonical 출처. 예정 줄에는 없다.
  final AttendanceModel? att;

  bool get isHistorical => att != null;
}

/// 수입 상세 화면
///
/// 홈 수입 현황 섹션에서 "N년 N월 ›"을 눌러 진입.
/// 상단 월 네비게이터(< 2026년 8월 >)로 이전/다음 달 이동.
/// 가운데 연/월 탭 → 기간 선택 바텀시트 (연도 이동 + 월 그리드).
class IncomeDetailScreen extends StatefulWidget {
  final int initialYear;
  final int initialMonth;

  const IncomeDetailScreen({
    super.key,
    required this.initialYear,
    required this.initialMonth,
  });

  @override
  State<IncomeDetailScreen> createState() => _IncomeDetailScreenState();
}

class _IncomeDetailScreenState extends State<IncomeDetailScreen> {
  final _firestore = FirestoreService();

  late int _year;
  late int _month;

  List<ApplicationModel> _allApplications = [];
  List<AttendanceModel> _attendances = [];
  bool _isLoading = false;

  /// [PREDEVICE-INCOME-ERROR-NOT-ZERO] 마지막 조회가 실패했는가.
  /// 실패를 0원으로 그리면 일한 돈이 사라진 것처럼 보인다.
  bool _loadFailed = false;

  /// 조회에 실패했으면 금액 대신 모른다고 말한다.
  ///
  /// 0원은 "그 달에 번 돈이 없다"는 사실이고, 조회 실패는 "얼마인지 모른다"는
  /// 전혀 다른 상태다. 둘을 같은 화면으로 그리면 근로자는 일한 돈이 사라진
  /// 것으로 읽는다.
  String _amountOrUnknown(int amount) =>
      _loadFailed ? '확인 불가' : FormatHelper.formatWage(amount);

  /// 일했지만 금액이 아직 확정되지 않은 근무 건수 (이 달 기준).
  int get _settlementPending => CalendarHelper.settlementPendingCount(
      _attendances, DateTime(_year, _month));

  @override
  void initState() {
    super.initState();
    _year = widget.initialYear;
    _month = widget.initialMonth;
    _loadAll();
  }

  // 최초 진입: 지원서 전체 + 이번 달 출근기록 병렬 로드
  Future<void> _loadAll() async {
    final uid = context.read<UserProvider>().currentUser?.uid;
    if (uid == null) return;
    setState(() => _isLoading = true);
    try {
      final results = await Future.wait([
        _firestore.getMyApplications(uid),
        _firestore.getMyMonthlyAttendances(
            userId: uid, year: _year, month: _month),
      ]);
      if (!mounted) return;
      setState(() {
        _allApplications = results[0] as List<ApplicationModel>;
        _attendances = results[1] as List<AttendanceModel>;
        _isLoading = false;
        _loadFailed = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _loadFailed = true;
        });
        ToastHelper.showError('데이터를 불러오지 못했습니다.');
      }
    }
  }

  // 월 이동 시: 출근기록만 재로드 (지원서는 전체 보유)
  Future<void> _reloadAttendances() async {
    final uid = context.read<UserProvider>().currentUser?.uid;
    if (uid == null) return;
    setState(() => _isLoading = true);
    try {
      final atts = await _firestore.getMyMonthlyAttendances(
          userId: uid, year: _year, month: _month);
      if (!mounted) return;
      setState(() {
        _attendances = atts;
        _isLoading = false;
        _loadFailed = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _loadFailed = true;
        });
        ToastHelper.showError('수입 정보를 불러오지 못했습니다.');
      }
    }
  }

  void _prevMonth() {
    setState(() {
      if (_month == 1) {
        _year--;
        _month = 12;
      } else {
        _month--;
      }
    });
    _reloadAttendances();
  }

  void _nextMonth() {
    final now = DateTime.now();
    if (_year == now.year && _month >= now.month) return; // 미래 이동 방지
    setState(() {
      if (_month == 12) {
        _year++;
        _month = 1;
      } else {
        _month++;
      }
    });
    _reloadAttendances();
  }

  bool get _isCurrentOrFuture {
    final now = DateTime.now();
    return _year > now.year || (_year == now.year && _month >= now.month);
  }

  /// 미래에 확정 근무가 있는 연월 Set — 기간 선택 월 활성화 판단에 사용
  ///
  /// AppStatus.confirmedStatuses(confirmed, contractPending)만 포함.
  /// pending/검토중 지원서는 "확정 근무"가 아니므로 제외.
  /// 반환 형식: {'2026-9', '2026-11', '2027-2', ...}
  Set<String> get _confirmedFutureYearMonths {
    final now = DateTime.now();
    final result = <String>{};
    for (final app in _allApplications) {
      if (!AppStatus.confirmedStatuses.contains(app.status)) continue;
      final wd = app.workDate;
      // 현재 월 이후(엄격히 미래)만 포함 — 현재 월은 항상 조회 가능이므로 불필요
      if (wd.year > now.year ||
          (wd.year == now.year && wd.month > now.month)) {
        result.add('${wd.year}-${wd.month}');
      }
    }
    return result;
  }

  /// 기간 선택에서 이동할 수 있는 최대 연도
  /// = 현재 연도 또는 확정 미래 근무가 있는 가장 먼 연도 중 큰 값
  int get _maxAccessibleYear {
    final now = DateTime.now();
    int maxYear = now.year;
    for (final app in _allApplications) {
      if (!AppStatus.confirmedStatuses.contains(app.status)) continue;
      if (app.workDate.year > maxYear) maxYear = app.workDate.year;
    }
    return maxYear;
  }

  // ── 기간 선택 바텀시트 ─────────────────────────────────────────
  //
  // 동작 원칙:
  //   과거 월 + 현재 월: 항상 선택 가능 (데이터 없어도 조회 가능)
  //   미래 월: _confirmedFutureYearMonths에 포함된 경우만 활성
  //            (pending/검토중 지원서는 제외, 확정 근무만)
  //   연도 이동: 과거 제한 없음, 미래는 _maxAccessibleYear까지
  //   월 선택 즉시 적용 — 확인 버튼 없음
  //   useRootNavigator: true — AppBar/BottomNavBar 포함 전체 Dim 처리
  Future<void> _showMonthPicker() async {
    final now = DateTime.now();
    final futureActive = _confirmedFutureYearMonths; // 미리 계산 (불변)
    final maxYear = _maxAccessibleYear;

    int pickerYear = _year;
    int? resultYear;
    int? resultMonth;

    // 해당 연월이 선택 가능한지 판단
    bool isSelectable(int year, int month) {
      // 과거 연도 전체 → 항상 가능
      if (year < now.year) return true;
      // 현재 연도: 현재 월 포함 이전 → 항상 가능
      if (year == now.year && month <= now.month) return true;
      // 미래: 확정 근무가 있는 월만 활성
      return futureActive.contains('$year-$month');
    }

    await DialogHelper.showSheet<void>(
      context,
      isScrollControlled: true,
      useRootNavigator: true, // BottomNavigationBar까지 Dim 처리
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setInner) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Handle bar
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 20),
                    decoration: BoxDecoration(
                      color: AppColors.grey300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Text('기간 선택', style: AppTextStyles.sectionTitle()),
                const SizedBox(height: 20),

                // 연도 네비게이터
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.chevron_left_rounded,
                          color: AppColors.textPrimary),
                      onPressed: () => setInner(() => pickerYear--),
                    ),
                    SizedBox(
                      width: 120,
                      child: Text(
                        '$pickerYear년',
                        textAlign: TextAlign.center,
                        style: AppTextStyles.sectionTitle(),
                      ),
                    ),
                    IconButton(
                      icon: Icon(
                        Icons.chevron_right_rounded,
                        color: pickerYear >= maxYear
                            ? AppColors.textDisabled
                            : AppColors.textPrimary,
                      ),
                      onPressed: pickerYear >= maxYear
                          ? null
                          : () => setInner(() => pickerYear++),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // 월 그리드 (4×3) — 터치 즉시 적용, 확인 버튼 없음
                GridView.count(
                  crossAxisCount: 4,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  childAspectRatio: 1.7,
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  children: List.generate(12, (i) {
                    final m = i + 1;
                    final selectable = isSelectable(pickerYear, m);
                    // 현재 화면에 표시 중인 월이 선택 표시됨
                    final isSelected =
                        m == _month && pickerYear == _year;
                    return GestureDetector(
                      onTap: !selectable
                          ? null
                          : () {
                              // 즉시 적용: 닫은 뒤 결과값 캡처
                              resultYear = pickerYear;
                              resultMonth = m;
                              Navigator.pop(ctx);
                            },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: isSelected
                              ? AppColors.brand
                              : AppColors.background,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '$m월',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: isSelected
                                ? FontWeight.w700
                                : FontWeight.w500,
                            color: !selectable
                                ? AppColors.textDisabled
                                : isSelected
                                    ? Colors.white
                                    : AppColors.textPrimary,
                          ),
                        ),
                      ),
                    );
                  }),
                ),
                const SizedBox(height: 16),
              ],
            ),
          );
        },
      ),
    );

    // 시트가 닫힌 뒤 결과 적용
    if (!mounted) return;
    if (resultYear != null &&
        resultMonth != null &&
        (resultYear != _year || resultMonth != _month)) {
      setState(() {
        _year = resultYear!;
        _month = resultMonth!;
      });
      _reloadAttendances();
    }
  }

  // ── 데이터 계산 헬퍼 ─────────────────────────────────────────

  /// 이번 달 지원서 목록 (CalendarHelper 사용)
  List<ApplicationModel> get _monthApps {
    final focusedDay = DateTime(_year, _month, 1);
    return CalendarHelper.getThisMonthApplications(_allApplications, focusedDay);
  }

  /// 근무 완료 = 관리자 임금 확정/지급 처리된 출근기록 합계
  int get _wageCompleted {
    final focusedDay = DateTime(_year, _month, 1);
    return CalendarHelper.getConfirmedIncome(_attendances, focusedDay);
  }

  /// 근무 예정 = 확정된 지원서 중 아직 벌 예정인 것 (시급→일당 환산)
  ///
  /// [PREDEVICE-INCOME-NOSHOW] NO_SHOW·결근으로 마감된 날은 제외한다 —
  /// 판정은 홈과 같은 CalendarHelper.isScheduledIncome을 쓴다.
  int get _wageScheduled {
    return _monthApps
        .where((a) => AppStatus.confirmedStatuses.contains(a.status))
        .where((a) => CalendarHelper.isScheduledIncome(a, _attendances))
        .fold(0, (sum, a) => sum + _dailyWageOf(a));
  }

  /// 시급 타입을 일당으로 환산 (CalendarHelper._dailyWage와 동일 로직)
  static int _dailyWageOf(ApplicationModel app) {
    if (app.wageType == 'hourly') {
      int toMin(String t) {
        final p = t.split(':');
        if (p.length < 2) return 0;
        return (int.tryParse(p[0]) ?? 0) * 60 + (int.tryParse(p[1]) ?? 0);
      }
      int startMin = toMin(app.startTime);
      int endMin = toMin(app.endTime);
      if (endMin <= startMin) endMin += 1440; // 야간 교대
      return ((endMin - startMin) / 60 * app.wage).round();
    }
    return app.wage;
  }

  /// [.6-P2] 실제로 일한 근무인가 — 서버 ACTUAL_WORK_STATUSES 와 같은 집합.
  ///
  /// 노쇼·결근은 일반 근무 내역이 아니다(신뢰도 쪽이 따로 본다).
  static bool _isActualWork(AttendanceModel a) =>
      a.status == AttendanceModel.statusPresent ||
      a.status == AttendanceModel.statusLate ||
      a.status == AttendanceModel.statusEarlyLeave;

  /// 이 달에 실제로 일한 근태. 지원서 상태를 보지 않는다.
  List<AttendanceModel> get _workedThisMonth => _attendances
      .where((a) =>
          a.workDate.year == _year &&
          a.workDate.month == _month &&
          _isActualWork(a))
      .toList();

  /// 근무 내역 목록 (과거 실근무 + 현재 약속, 날짜 ASC)
  ///
  /// [.6-P2] 과거 근무는 근태가 근거다 — 지원서가 취소됐든 조회에서 빠졌든
  /// 일한 사실은 남는다. 앞으로의 약속만 지원서 상태로 고른다.
  List<_IncomeRow> get _incomeRows {
    final rows = <_IncomeRow>[];
    final seenAppIds = <String>{};

    // 1) 지금 유효한 약속 — 기존 규칙 그대로(장기는 달에 한 줄).
    for (final a in _monthApps) {
      if (!AppStatus.confirmedStatuses.contains(a.status) &&
          a.status != AppStatus.pending) {
        continue;
      }
      rows.add(_IncomeRow(date: a.workDate, app: a));
      seenAppIds.add(a.id);
    }

    // 2) 실제로 일한 기록 — 1)에 이미 잡힌 지원서는 중복시키지 않는다.
    //    같은 지원서의 여러 근무일은 기존 구조대로 한 줄로 묶는다
    //    (장기 근무를 날짜별로 펼치는 것은 이번 범위가 아니다).
    final byApp = <String, AttendanceModel>{};
    for (final att in _workedThisMonth) {
      if (seenAppIds.contains(att.applicationId)) continue;
      final prev = byApp[att.applicationId];
      if (prev == null || att.workDate.isBefore(prev.workDate)) {
        byApp[att.applicationId] = att;
      }
    }
    for (final att in byApp.values) {
      // 지원서는 표시용 맥락일 뿐이다. 없으면 근태가 가진 것으로 그린다.
      final app = _allApplications
          .where((x) => x.id == att.applicationId)
          .firstOrNull;
      rows.add(_IncomeRow(date: att.workDate, app: app, att: att));
    }

    rows.sort((a, b) => a.date.compareTo(b.date));
    return rows;
  }

  double _s(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    if (w < 360) return 0.82;
    if (w < 400) return 0.92;
    if (w < 480) return 1.0;
    return 1.08;
  }

  @override
  Widget build(BuildContext context) {
    final s = _s(context);
    final wageCompleted = _wageCompleted;
    final wageScheduled = _wageScheduled;
    final wageTotal = wageCompleted + wageScheduled;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(
          '수입 현황',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
        // leading을 명시해야 흰 배경에서 아이콘이 보임
        // foregroundColor만 지정하면 테마 오버라이드에 묻혀 흰색으로 렌더링될 수 있음
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new,
            color: AppColors.textPrimary,
            size: 20,
          ),
          padding: const EdgeInsets.all(14), // 48dp 터치 영역 확보
          onPressed: () => Navigator.pop(context),
        ),
        backgroundColor: Colors.white,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: AppColors.borderLight),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _loadAll,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics()),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── 월 네비게이터 ─────────────────────────────────────
              Container(
                color: Colors.white,
                padding: EdgeInsets.symmetric(vertical: 10 * s),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      icon: Icon(Icons.chevron_left_rounded,
                          size: 28 * s, color: AppColors.textPrimary),
                      onPressed: _prevMonth,
                    ),
                    GestureDetector(
                      onTap: _showMonthPicker,
                      child: Container(
                        padding: EdgeInsets.symmetric(
                            horizontal: 16 * s, vertical: 6 * s),
                        decoration: BoxDecoration(
                          color: AppColors.background,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Text(
                            '$_year년 $_month월',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          SizedBox(width: 4 * s),
                          Icon(Icons.keyboard_arrow_down_rounded,
                              size: 18 * s, color: AppColors.textSecondary),
                        ]),
                      ),
                    ),
                    IconButton(
                      icon: Icon(
                        Icons.chevron_right_rounded,
                        size: 28 * s,
                        color: _isCurrentOrFuture
                            ? AppColors.textDisabled
                            : AppColors.textPrimary,
                      ),
                      onPressed: _isCurrentOrFuture ? null : _nextMonth,
                    ),
                  ],
                ),
              ),
              Container(height: 1, color: AppColors.borderLight),

              // ── 수입 요약 카드 ─────────────────────────────────────
              Container(
                color: Colors.white,
                padding: EdgeInsets.all(16 * s),
                child: Container(
                  padding: EdgeInsets.all(16 * s),
                  decoration: BoxDecoration(
                    color: AppColors.background,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.borderLight),
                  ),
                  child: Column(
                    children: [
                      _incomeRow(
                        s: s,
                        label: '근무 완료',
                        value: _isLoading ? null : _amountOrUnknown(wageCompleted),
                      ),
                      SizedBox(height: 10 * s),
                      _incomeRow(
                        s: s,
                        label: '근무 예정',
                        value: _isLoading ? null : _amountOrUnknown(wageScheduled),
                      ),
                      // [PREDEVICE-PENDING-WAGE-VISIBILITY] 홈에서 '정산 중 N건'을
                      //   보고 들어온 사람이 여기서 같은 사실을 확인할 수 있어야
                      //   한다. 아래 근무 내역에 '근무 완료' 행으로 실제 건들이
                      //   있다. 조회 실패 시에는 0건이라고 말하지 않는다.
                      if (_isLoading || _loadFailed || _settlementPending > 0) ...[
                        SizedBox(height: 10 * s),
                        _incomeRow(
                          s: s,
                          label: '정산 중',
                          value: _isLoading
                              ? null
                              : (_loadFailed ? '확인 불가' : '$_settlementPending건'),
                        ),
                      ],
                      SizedBox(height: 12 * s),
                      Divider(height: 1, color: AppColors.borderLight),
                      SizedBox(height: 12 * s),
                      _incomeRow(
                        s: s,
                        label: '예상 수입',
                        value: _isLoading ? null : _amountOrUnknown(wageTotal),
                        isTotalRow: true,
                      ),
                    ],
                  ),
                ),
              ),
              Container(height: 8, color: AppColors.background),

              // ── 근무 내역 ─────────────────────────────────────────
              Container(
                color: Colors.white,
                padding:
                    EdgeInsets.fromLTRB(20 * s, 20 * s, 20 * s, 12 * s),
                child: SectionHeader(
                  title: '$_year년 $_month월 근무 내역',
                ),
              ),
              if (_isLoading)
                Container(
                  color: Colors.white,
                  padding: EdgeInsets.symmetric(vertical: 48 * s),
                  child: const Center(child: CircularProgressIndicator()),
                )
              // [.6-P2] 조회 실패는 "수입이 없다"가 아니다. 모르는 것과
              //   없는 것을 같은 화면으로 그리면 일한 돈이 사라진 것으로
              //   읽힌다.
              else if (_loadFailed && _incomeRows.isEmpty)
                _buildLoadErrorState(s)
              else if (_incomeRows.isEmpty)
                Container(
                  color: Colors.white,
                  padding: EdgeInsets.symmetric(
                      horizontal: 20 * s, vertical: 56 * s),
                  child: Column(
                    children: [
                      Icon(Icons.receipt_long_outlined,
                          size: 40 * s, color: AppColors.textTertiary),
                      SizedBox(height: 16 * s),
                      Text(
                        '아직 이번 달 수입이 없어요',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      SizedBox(height: 6 * s),
                      Text(
                        '첫 근무를 마치면 여기에 수입이 표시돼요',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w400,
                          color: AppColors.textTertiary,
                        ),
                      ),
                    ],
                  ),
                )
              else
                Container(
                  color: Colors.white,
                  child: Column(
                    children: [
                      // 이전 데이터는 남기고, 지금 것이 최신이 아님을 말한다.
                      if (_loadFailed) _buildStaleBanner(s),
                      ..._incomeRows.asMap().entries.map((e) {
                        final i = e.key;
                        return _buildWorkRecord(
                            s, e.value, i < _incomeRows.length - 1);
                      }),
                    ],
                  ),
                ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  // ── 수입 행 위젯 ──────────────────────────────────────────────
  //
  // isTotalRow=false (기본): 근무 완료 / 근무 예정
  //   라벨: 16sp w500 textSecondary  |  금액: 16sp w600 textPrimary
  //
  // isTotalRow=true: 예상 수입 합계
  //   라벨: 17sp w700 brand          |  금액: 20sp w700 brand
  //
  // 금액 색상으로 행 종류를 구분하지 않는다 — Typography + 배치로 위계 표현.
  // (근무 완료에서 초록 제거: 초록은 결제 상태 뱃지 전용으로 남김)
  Widget _incomeRow({
    required double s,
    required String label,
    required String? value,
    bool isTotalRow = false,
  }) {
    final labelStyle = isTotalRow
        ? TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: AppColors.brand,
          )
        : TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w500,
            color: AppColors.textSecondary,
          );
    final valueStyle = isTotalRow
        ? TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: AppColors.brand,
            letterSpacing: -0.5,
          )
        : TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
            letterSpacing: -0.3,
          );

    return Row(children: [
      Text(label, style: labelStyle),
      const Spacer(),
      value == null
          ? SizedBox(
              width: 80 * s,
              height: 16 * s,
              child: LinearProgressIndicator(
                borderRadius: BorderRadius.circular(4),
                color: AppColors.brand.withValues(alpha: 0.25),
                backgroundColor: AppColors.borderLight,
              ))
          : Text(value, style: valueStyle),
    ]);
  }

  // ── 근무 내역 행 ──────────────────────────────────────────────
  //
  // 급여 지급 상태 레이블 매핑 (AttendanceModel.wageStatus 기준):
  //   transferred → '이체 처리 완료'  (관리자가 앱 내 이체처리 완료)
  //   confirmed   → '지급 예정'       (급여 확정, 이체 전)
  //   calculated  → '급여 계산 완료'  (관리자가 금액 계산 완료, 확정 전)
  //   checkIn 있음 → '근무 완료'      (출근 기록 있음, 급여 미처리)
  //   확정 지원, checkIn 없음 → '근무 예정'
  //   기타(pending) → '검토중'
  //
  // PAID 상태(실제 금융 API 연결 후 → '입금 완료')는 AttendanceModel에
  // wageStatus = 'paid' 상수 추가 후 아래 분기에 추가 예정.
  /// [.6-P2] 조회 자체가 실패한 상태 — 비어 있는 것과 구분해 그린다.
  Widget _buildLoadErrorState(double s) => Container(
        color: Colors.white,
        padding:
            EdgeInsets.symmetric(horizontal: 20 * s, vertical: 48 * s),
        child: Column(
          children: [
            Icon(Icons.cloud_off_outlined,
                size: 40 * s, color: AppColors.textTertiary),
            SizedBox(height: 16 * s),
            Text(
              '근무 내역을 불러오지 못했어요',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
              ),
            ),
            SizedBox(height: 6 * s),
            Text(
              '수입이 없는 것이 아니라, 지금 확인할 수 없는 상태예요',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w400,
                color: AppColors.textTertiary,
              ),
            ),
            SizedBox(height: 16 * s),
            OutlinedButton.icon(
              onPressed: _isLoading ? null : _loadAll,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('다시 시도'),
            ),
          ],
        ),
      );

  /// [.6-P2] 이전 데이터는 살아 있지만 방금 조회가 실패한 상태.
  Widget _buildStaleBanner(double s) => Container(
        width: double.infinity,
        padding: EdgeInsets.symmetric(horizontal: 16 * s, vertical: 10 * s),
        color: AppColors.warning.withValues(alpha: 0.10),
        child: Row(
          children: [
            Icon(Icons.info_outline, size: 16 * s, color: AppColors.warning),
            SizedBox(width: 8 * s),
            Expanded(
              child: Text(
                '최신 정보를 불러오지 못했어요. 아래는 마지막으로 확인된 내역이에요.',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
            TextButton(
              onPressed: _isLoading ? null : _loadAll,
              child: const Text('새로고침'),
            ),
          ],
        ),
      );

  /// [.6-P2] 업무명 — 지원서가 없으면 근태가 가진 것을 쓴다.
  static String _workTypeLabel(ApplicationModel? app, AttendanceModel? att) {
    if (app != null && app.selectedWorkType.isNotEmpty) {
      return app.selectedWorkType;
    }
    return att?.workType ?? '';
  }

  Widget _buildWorkRecord(double s, _IncomeRow row, bool showDivider) {
    const dowLabels = ['', '월', '화', '수', '목', '금', '토', '일'];
    final app = row.app;
    final d = row.date;
    final dateStr =
        '${d.month}/${d.day.toString().padLeft(2, '0')}(${dowLabels[d.weekday]})';

    // [.6-P2] 과거 줄은 자기 근태를 들고 온다. 예정 줄만 지원서로 찾는다.
    final att = row.att ??
        (app == null
            ? null
            : _attendances.where((a) => a.applicationId == app.id).firstOrNull);

    // 지급 상태별 레이블 — AttendanceModel 상수 사용, 타입 프로모션 보장
    final int displayWage;
    final String statusLabel;
    final Color statusColor;

    if (att != null &&
        att.wageStatus == AttendanceModel.wageTransferred &&
        att.finalWage != null) {
      displayWage = att.finalWage!;
      statusLabel = '이체 처리 완료';
      statusColor = AppColors.successDark; // 결제 완료 → 초록 유지
    } else if (att != null &&
        att.wageStatus == AttendanceModel.wageConfirmed &&
        att.finalWage != null) {
      displayWage = att.finalWage!;
      statusLabel = '지급 예정';
      statusColor = AppColors.brand;
    } else if (att != null &&
        att.wageStatus == AttendanceModel.wageCalculated &&
        att.finalWage != null) {
      displayWage = att.finalWage!;
      statusLabel = '급여 계산 완료';
      statusColor = AppColors.success; // 처리 진행 중 → 연한 초록 유지
    } else if (att?.checkInAt != null) {
      // [.6-P2] 지원서가 없으면 예정 일당을 계산할 근거가 없다.
      //   없는 금액을 지어내지 않고 모른다고 말한다.
      displayWage = app == null ? 0 : _dailyWageOf(app);
      statusLabel = app == null ? '근무 완료 · 금액 확인 필요' : '근무 완료';
      statusColor = AppColors.textSecondary; // 급여 미처리 → 중립 회색
    } else if (app != null &&
        AppStatus.confirmedStatuses.contains(app.status)) {
      displayWage = _dailyWageOf(app);
      statusLabel = '근무 예정';
      statusColor = AppColors.brand;
    } else if (app != null) {
      displayWage = _dailyWageOf(app);
      statusLabel = '검토중';
      statusColor = AppColors.warning;
    } else {
      // 근태만 남은 과거 근무 — 지원서를 못 찾았다. 조용히 빼지 않는다.
      displayWage = 0;
      statusLabel = '근무 기록 · 상세 확인 필요';
      statusColor = AppColors.textSecondary;
    }

    return Column(
      children: [
        // 전체 행 탭 → 급여 상세 화면 (WageDetailScreen)
        InkWell(
          // 지원서가 없으면 상세를 구성할 수 없다 — 탭을 열지 않는다.
          onTap: app == null
              ? null
              : () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => WageDetailScreen(
                        application: app,
                        attendance: att,
                      ),
                    ),
                  ),
          child: Padding(
            padding:
                EdgeInsets.symmetric(horizontal: 16 * s, vertical: 14 * s),
            child: Row(
              children: [
                // 날짜
                SizedBox(
                  width: 72 * s,
                  child: Text(
                    dateStr,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
                // 사업장 · 업무유형
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        // [.6-P2] 지원서가 없으면 근태가 가진 이름을 쓴다.
                        //   둘 다 없으면 없는 이름을 지어내지 않는다.
                        app?.businessName.isNotEmpty == true
                            ? app!.businessName
                            : (att?.businessName.isNotEmpty == true
                                ? att!.businessName
                                : '사업장 정보 없음'),
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (_workTypeLabel(app, att).isNotEmpty) ...[
                        SizedBox(height: 2 * s),
                        Text(
                          _workTypeLabel(app, att),
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w400,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                SizedBox(width: 8 * s),
                // 금액 + 상태
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      FormatHelper.formatWage(displayWage),
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                        letterSpacing: -0.3,
                      ),
                    ),
                    SizedBox(height: 2 * s),
                    Text(
                      statusLabel,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: statusColor,
                      ),
                    ),
                  ],
                ),
                SizedBox(width: 4 * s),
                Icon(Icons.chevron_right,
                    size: 18 * s, color: AppColors.textTertiary),
              ],
            ),
          ),
        ),
        if (showDivider)
          Divider(
              height: 1,
              indent: 16 * s,
              endIndent: 16 * s,
              color: AppColors.borderLight),
      ],
    );
  }
}
