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
      });
    } catch (_) {
      if (mounted) {
        setState(() => _isLoading = false);
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
      });
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
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

  /// 근무 예정 = 확정된 지원서 중 아직 미출근인 것 (시급→일당 환산)
  int get _wageScheduled {
    return _monthApps
        .where((a) => AppStatus.confirmedStatuses.contains(a.status))
        .where((a) => !_attendances
            .any((att) => att.applicationId == a.id && att.checkInAt != null))
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

  /// 근무 내역 목록 (확정 + 검토중, 날짜 ASC)
  List<ApplicationModel> get _workRecords {
    final records = _monthApps
        .where((a) =>
            AppStatus.confirmedStatuses.contains(a.status) ||
            a.status == AppStatus.pending)
        .toList()
      ..sort((a, b) => a.workDate.compareTo(b.workDate));
    return records;
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
            fontSize: 20 * s,
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
                              fontSize: 20 * s,
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
                        value: _isLoading ? null : FormatHelper.formatWage(wageCompleted),
                      ),
                      SizedBox(height: 10 * s),
                      _incomeRow(
                        s: s,
                        label: '근무 예정',
                        value: _isLoading ? null : FormatHelper.formatWage(wageScheduled),
                      ),
                      SizedBox(height: 12 * s),
                      Divider(height: 1, color: AppColors.borderLight),
                      SizedBox(height: 12 * s),
                      _incomeRow(
                        s: s,
                        label: '예상 수입',
                        value: _isLoading ? null : FormatHelper.formatWage(wageTotal),
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
                  s: s,
                  title: '$_year년 $_month월 근무 내역',
                ),
              ),
              if (_isLoading)
                Container(
                  color: Colors.white,
                  padding: EdgeInsets.symmetric(vertical: 48 * s),
                  child: const Center(child: CircularProgressIndicator()),
                )
              else if (_workRecords.isEmpty)
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
                          fontSize: 16 * s,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      SizedBox(height: 6 * s),
                      Text(
                        '첫 근무를 마치면 여기에 수입이 표시돼요',
                        style: TextStyle(
                          fontSize: 14 * s,
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
                    children: _workRecords.asMap().entries.map((e) {
                      final i = e.key;
                      final app = e.value;
                      return _buildWorkRecord(
                          s, app, i < _workRecords.length - 1);
                    }).toList(),
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
            fontSize: 17 * s,
            fontWeight: FontWeight.w700,
            color: AppColors.brand,
          )
        : TextStyle(
            fontSize: 16 * s,
            fontWeight: FontWeight.w500,
            color: AppColors.textSecondary,
          );
    final valueStyle = isTotalRow
        ? TextStyle(
            fontSize: 20 * s,
            fontWeight: FontWeight.w700,
            color: AppColors.brand,
            letterSpacing: -0.5,
          )
        : TextStyle(
            fontSize: 16 * s,
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
  Widget _buildWorkRecord(double s, ApplicationModel app, bool showDivider) {
    const dowLabels = ['', '월', '화', '수', '목', '금', '토', '일'];
    final d = app.workDate;
    final dateStr =
        '${d.month}/${d.day.toString().padLeft(2, '0')}(${dowLabels[d.weekday]})';

    final att = _attendances
        .where((a) => a.applicationId == app.id)
        .firstOrNull;

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
      displayWage = _dailyWageOf(app);
      statusLabel = '근무 완료';
      statusColor = AppColors.textSecondary; // 급여 미처리 → 중립 회색
    } else if (AppStatus.confirmedStatuses.contains(app.status)) {
      displayWage = _dailyWageOf(app);
      statusLabel = '근무 예정';
      statusColor = AppColors.brand;
    } else {
      displayWage = _dailyWageOf(app);
      statusLabel = '검토중';
      statusColor = AppColors.warning;
    }

    return Column(
      children: [
        // 전체 행 탭 → 급여 상세 화면 (WageDetailScreen)
        InkWell(
          onTap: () => Navigator.push(
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
                      fontSize: 15 * s,
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
                        app.businessName,
                        style: TextStyle(
                          fontSize: 16 * s,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (app.selectedWorkType.isNotEmpty) ...[
                        SizedBox(height: 2 * s),
                        Text(
                          app.selectedWorkType,
                          style: TextStyle(
                            fontSize: 14 * s,
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
                        fontSize: 16 * s,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                        letterSpacing: -0.3,
                      ),
                    ),
                    SizedBox(height: 2 * s),
                    Text(
                      statusLabel,
                      style: TextStyle(
                        fontSize: 13 * s,
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
