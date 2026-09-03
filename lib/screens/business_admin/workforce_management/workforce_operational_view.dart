// lib/screens/business_admin/workforce_management/workforce_operational_view.dart
//
// PHASE 5B.1 — 인력 탭 운영 UX
//
// 역할: 선택 날짜의 근무 예정 근로자를 직접 노출, 근태 처리로 빠른 진입
//
// IA: WeekStrip → DateHeader(일괄 근태) → DailySummaryFilter → WorkGroupSection × N
//
// 데이터:
//   applications: getConfirmedWorkersByDateAndBusiness (CF)
//   attendances : getAttendanceByDate (CF)
//   summary     : 위 두 데이터셋에서 in-memory aggregate — 신규 backend query ZERO
//
// 변경 금지:
//   - Attendance authority / NoShow / Payroll / Contract lifecycle
//   - AttendanceStatusDialog (기존 그대로 사용)
//   - WorkforceController (기존 그대로 사용)
//   - Firestore schema

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../controllers/workforce_controller.dart';
import '../../../models/core/application_model.dart';
import '../../../models/core/attendance_model.dart';
import '../../../models/core/business_model.dart';
import '../../../models/core/user_model.dart';
import '../../../providers/user_provider.dart';
import '../../../services/firestore_service.dart';
import '../../../theme/app_colors.dart';
import '../../../utils/dialog_helper.dart';
import '../../../utils/format_helper.dart';
import '../../../utils/responsive_helper.dart';
import '../../../utils/toast_helper.dart';
import '../../../widgets/calendar/app_calendar.dart';
import '../../../widgets/common/loading_widget.dart';
import '../dialogs/attendance_status_dialog.dart';
import '../dialogs/day_applicants_dialog.dart';
import '../dialogs/fixed_worker_management_dialog.dart';

// ── 내부 데이터 구조 ────────────────────────────────────────────

/// 선택 날짜 기준 근태 상태 (화면 표시용)
enum _AttStatus {
  notCheckedIn, // 미출근 — 체크인 없음
  present,      // 출근
  late,         // 지각
  checkedOut,   // 퇴근
  noShow,       // 노쇼
  absent,       // 결근 (관리자 확정 absent)
}

/// 근로자 1명 행 데이터
class _WorkerEntry {
  final ApplicationModel application;
  final AttendanceModel? attendance;

  _WorkerEntry({required this.application, this.attendance});

  String get name => application.applicantName ?? application.uid;
  String get uid => application.uid;
  bool get isContractPending => application.status == AppStatus.contractPending;

  /// 출근 상태 계산 — AttendanceModel 실제 필드 기반
  _AttStatus get attStatus {
    final att = attendance;
    if (att == null) return _AttStatus.notCheckedIn;
    if (att.status == AttendanceModel.statusNoShow) return _AttStatus.noShow;
    if (att.status == AttendanceModel.statusAbsent) return _AttStatus.absent;
    if (att.checkOutAt != null) return _AttStatus.checkedOut;
    if (att.status == AttendanceModel.statusLate) return _AttStatus.late;
    if (att.checkInAt != null) return _AttStatus.present;
    return _AttStatus.notCheckedIn;
  }

  /// 정렬 우선순위 — 미출근이 최상단
  int get sortPriority {
    switch (attStatus) {
      case _AttStatus.notCheckedIn: return 0;
      case _AttStatus.late:         return 1;
      case _AttStatus.noShow:       return 2;
      case _AttStatus.present:      return 3;
      case _AttStatus.absent:       return 4;
      case _AttStatus.checkedOut:   return 5;
    }
  }
}

/// 업무 그룹
///
/// [5B.1B] group identity는 표시값(workType+time)이 아닌
/// 실제 데이터 ID(businessId|toId|slotId|workDetailId) 기준.
/// - businessId: non-nullable → cross-business merge 불가
/// - toId: nullable(레거시 대비) → 없으면 workType_time fallback
/// - slotId/workDetailId: nullable → 없으면 빈 문자열
///
/// 동일 사업장·동일 TO라도 slotId 또는 workDetailId가 다르면 별도 그룹.
class _WorkGroup {
  final String workType;
  final String startTime;
  final String endTime;
  final String toTitle;      // UI 표시: TO 제목
  final String businessName; // UI 표시: 사업장명
  // ── identity fields ────────────────────────────────────────────
  final String businessId;   // 항상 존재 — cross-business 분리 보장
  final String? toId;        // cross-TO 분리 (null = 레거시)
  final String? slotId;      // cross-slot 분리 (null = 장기/레거시)
  final String? workDetailId; // cross-workDetail 분리 (null = 레거시)
  // ───────────────────────────────────────────────────────────────
  final bool isClosedTO;
  final List<_WorkerEntry> workers;

  _WorkGroup({
    required this.workType,
    required this.startTime,
    required this.endTime,
    required this.toTitle,
    required this.businessName,
    required this.businessId,
    this.toId,
    this.slotId,
    this.workDetailId,
    required this.isClosedTO,
    required this.workers,
  });

  /// Canonical group key — [5B.1B]
  ///
  /// businessId + toId + slotId + workDetailId 조합.
  /// toId가 없는 레거시 데이터는 workType_startTime_endTime을 toSegment로 사용해
  /// 최소한 businessId로 cross-business 분리를 보장하고,
  /// workType+time이 같은 레거시 간에는 자연스럽게 grouping.
  String get key {
    final toSeg = toId ?? '${workType}_${startTime}_$endTime';
    final slotSeg = slotId ?? '';
    final wdSeg = workDetailId ?? '';
    return '$businessId|$toSeg|$slotSeg|$wdSeg';
  }

  int get workerCount => workers.length;
}

// ── 필터 열거형 ─────────────────────────────────────────────────

enum _SummaryFilter { all, checkedIn, notCheckedIn, noShow }

// ══════════════════════════════════════════════════════════════════
// WorkforceOperationalView
// ══════════════════════════════════════════════════════════════════

class WorkforceOperationalView extends StatefulWidget {
  const WorkforceOperationalView({super.key});

  @override
  State<WorkforceOperationalView> createState() =>
      _WorkforceOperationalViewState();
}

class _WorkforceOperationalViewState extends State<WorkforceOperationalView> {
  final FirestoreService _firestoreService = FirestoreService();

  // ── 날짜 상태 ──────────────────────────────────────────────────
  DateTime _selectedDay = _today();

  // ── 데이터 상태 ────────────────────────────────────────────────
  List<ApplicationModel> _applications = [];
  List<AttendanceModel> _attendances = [];
  bool _isLoadingData = false;
  String? _loadError;

  // ── 필터 상태 (load 시 리셋 안 함 — 날짜 변경 시 all로 초기화) ──
  _SummaryFilter _activeFilter = _SummaryFilter.all;

  // ── 사업장 캐시 ────────────────────────────────────────────────
  List<BusinessModel>? _cachedBusinesses;

  // ── 스크롤 ─────────────────────────────────────────────────────
  final ScrollController _scrollController = ScrollController();

  // ── 사용자 이름 캐시 (P0: UID 직접 노출 방지) ─────────────────
  Map<String, UserModel> _userMap = {};

  // ── 정렬 고정 ─────────────────────────────────────────────────
  // 로드 완료 시 1회 정렬. 실시간 재정렬 금지 (처리 중 row 이동 방지).
  List<_WorkGroup>? _sortedGroups;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _loadDayData(_selectedDay);
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  // ── 날짜 유틸 ──────────────────────────────────────────────────

  static DateTime _today() {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  bool get _isToday => DateUtils.isSameDay(_selectedDay, _today());
  bool get _isFuture => _selectedDay.isAfter(_today());

  /// 선택 날짜를 포함하는 주의 월요일
  DateTime get _weekMonday {
    final d = _selectedDay;
    final diff = (d.weekday - DateTime.monday) % 7;
    return DateTime(d.year, d.month, d.day - diff);
  }

  // ── 이름 해결 helpers (P0) ────────────────────────────────────

  /// 근로자 표시 이름 — UID 직접 노출 절대 금지
  /// 우선순위: UserModel.displayName → Application.applicantName → '이름 없음'
  String _workerDisplayName(_WorkerEntry worker) {
    final user = _userMap[worker.uid];
    if (user != null) return user.displayName;
    final snapshot = worker.application.applicantName;
    if (snapshot != null && snapshot.isNotEmpty) return snapshot;
    return '이름 없음';
  }

  // ── 근무 시간 display helpers ──────────────────────────────────

  /// 출퇴근 기록 표시 문자열
  /// 출근 있음: "HH:mm 출근" 또는 "HH:mm 출근 · HH:mm 퇴근"
  /// 출근 없음: "HH:mm 출근 예정"
  String _workerTimeText(_WorkerEntry worker) {
    final att = worker.attendance;
    if (att?.checkIn != null) {
      final ci = _hhmmOf(att!.checkIn!);
      if (att.checkOut != null) {
        return '$ci 출근 · ${_hhmmOf(att.checkOut!)} 퇴근';
      }
      return '$ci 출근';
    }
    if (worker.application.startTime.isNotEmpty) {
      return '${_hhmmOf(worker.application.startTime)} 출근 예정';
    }
    return '';
  }

  /// "HH:mm:ss" → "HH:mm" (초 제거)
  String _hhmmOf(String t) {
    final s = t.trim();
    return s.length >= 5 ? s.substring(0, 5) : s;
  }

  // ── 출근 시간 기준 helpers (오늘 날짜 시간 의미론) ────────────

  /// "출근 전/예정" 판단 — 미출근 집계·필터·상태 칩에서 제외해야 하는 경우
  ///
  /// • 미래 날짜 → 항상 true (모든 근로자가 출근 전/예정)
  /// • 오늘 날짜 + scheduled startTime 미경과 → true
  /// • 과거 날짜 → false (미체크인 = 미출근)
  bool _isBeforeStart(ApplicationModel app) {
    if (_isFuture) return true;      // [WF.1A] 미래 날짜: 전체 "출근 전/예정"
    if (!_isToday) return false;     // 과거 날짜: 미출근으로 집계
    final parts = app.startTime.split(':');
    if (parts.length < 2) return false;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null) return false;
    final now = DateTime.now();
    return now.isBefore(DateTime(now.year, now.month, now.day, h, m));
  }

  // ── 데이터 로드 ────────────────────────────────────────────────

  Future<void> _loadDayData(DateTime day) async {
    if (!mounted) return;

    final businesses = await _ensureBusinesses();
    if (!mounted) return;
    if (businesses.isEmpty) {
      setState(() {
        _applications = [];
        _attendances = [];
        _sortedGroups = [];
        _loadError = null;
      });
      return;
    }

    setState(() {
      _isLoadingData = true;
      _loadError = null;
      _activeFilter = _SummaryFilter.all; // 날짜 변경 시 필터 초기화
    });

    try {
      // 사업장이 여러 개인 경우 병렬 조회, 결과 합산
      final appFutures = businesses.map((b) =>
          _firestoreService.getConfirmedWorkersByDateAndBusiness(
            date: day,
            businessId: b.id,
          ));
      final attFutures = businesses.map((b) =>
          _firestoreService.getAttendanceByDate(
            businessId: b.id,
            date: day,
          ));

      final results = await Future.wait([
        Future.wait(appFutures),
        Future.wait(attFutures),
      ]);

      if (!mounted) return;

      final apps = (results[0] as List<List<ApplicationModel>>)
          .expand((l) => l)
          .toList();
      final atts = (results[1] as List<List<AttendanceModel>>)
          .expand((l) => l)
          .toList();

      // Attendance를 uid 기준으로 Map화 (uid당 당일 최신 1건 — workDate 동일)
      final attMap = <String, AttendanceModel>{};
      for (final att in atts) {
        final existing = attMap[att.userId];
        if (existing == null) {
          attMap[att.userId] = att;
        } else {
          // 동일 근로자에 복수 근태 존재하면 가장 최근 체크인 우선
          final existingCI = existing.checkInAt?.millisecondsSinceEpoch ?? 0;
          final newCI = att.checkInAt?.millisecondsSinceEpoch ?? 0;
          if (newCI > existingCI) attMap[att.userId] = att;
        }
      }

      // WorkerEntry 생성
      final entries = apps.map((app) => _WorkerEntry(
            application: app,
            attendance: attMap[app.uid],
          ));

      // 업무 그룹 빌드 [5B.1B] canonical identity
      // key = businessId|toId|slotId|workDetailId
      // — cross-business / cross-TO / cross-slot / cross-workDetail merge 방지
      final groupMap = <String, _WorkGroup>{};
      for (final entry in entries) {
        final app = entry.application;
        final group = _WorkGroup(
          workType: app.selectedWorkType,
          startTime: app.startTime,
          endTime: app.endTime,
          toTitle: app.toTitle,
          businessName: app.businessName,
          businessId: app.businessId,
          toId: app.toId,
          slotId: app.slotId,
          workDetailId: app.workDetailId,
          isClosedTO: false, // 현재 API 응답에 TO 상태 미포함 → 표시 안 함
          workers: [],
        );
        final gKey = group.key;
        if (groupMap.containsKey(gKey)) {
          groupMap[gKey]!.workers.add(entry);
        } else {
          groupMap[gKey] = group..workers.add(entry);
        }
      }

      // 그룹 내 workers 정렬 (1회) — 첫 로드 시만, 실시간 재정렬 금지
      final groups = groupMap.values.toList()
        ..sort((a, b) => a.startTime.compareTo(b.startTime));
      for (final g in groups) {
        g.workers.sort((a, b) => a.sortPriority.compareTo(b.sortPriority));
      }

      // [P0] 사용자 이름 batch 조회 — UID 직접 노출 방지
      // businessId별로 UID를 그룹화하여 CF 권한 검증 통과
      final byBusiness = <String, List<String>>{};
      for (final app in apps) {
        byBusiness.putIfAbsent(app.businessId, () => []).add(app.uid);
      }
      final userMapResults = await Future.wait(
        byBusiness.entries.map((e) => _firestoreService.getUsersBatch(
          e.value.toSet().toList(),
          businessId: e.key,
        )),
      );
      final resolvedUsers = <String, UserModel>{};
      for (final m in userMapResults) {
        resolvedUsers.addAll(m);
      }

      if (!mounted) return;
      setState(() {
        _applications = apps;
        _attendances = atts;
        _sortedGroups = groups;
        _userMap = resolvedUsers;
        _isLoadingData = false;
      });
    } catch (e) {
      debugPrint('❌ [WorkforceOperationalView] 데이터 로드 실패: $e');
      if (!mounted) return;
      setState(() {
        _isLoadingData = false;
        _loadError = '데이터를 불러오지 못했습니다. 다시 시도해 주세요.';
      });
    }
  }

  Future<void> _reload() async {
    _cachedBusinesses = null; // 사업장 캐시 무효화
    await _loadDayData(_selectedDay);
  }

  Future<List<BusinessModel>> _ensureBusinesses() async {
    if (_cachedBusinesses != null) return _cachedBusinesses!;
    final up = context.read<UserProvider>();
    final uid = up.currentUser?.uid;
    if (uid == null) return [];
    List<BusinessModel> result;
    final effectiveBizId = up.effectiveBusinessId;
    if (up.isSubAdmin && effectiveBizId != null) {
      final biz = await _firestoreService.getBusinessById(effectiveBizId);
      result = biz != null ? [biz] : [];
    } else {
      result = await _firestoreService.getMyBusiness(uid);
    }
    _cachedBusinesses = result;
    return result;
  }

  // ── Summary 집계 (in-memory, 신규 query ZERO) ──────────────────

  int get _totalScheduled => _applications.length;

  int get _checkedInCount => _applications.where((app) {
        final att = _attMapByUid[app.uid];
        if (att == null) return false;
        return att.checkInAt != null &&
            att.status != AttendanceModel.statusNoShow;
      }).length;

  int get _notCheckedInCount => _applications.where((app) {
        final att = _attMapByUid[app.uid];
        // 이미 출근한 경우 제외
        if (att?.checkInAt != null) return false;
        // 노쇼 제외
        if (att?.status == AttendanceModel.statusNoShow) return false;
        // 출근 전/예정인 경우 → 미출근 집계 제외 (_isBeforeStart가 미래/오늘 모두 처리)
        if (_isBeforeStart(app)) return false;
        return true;
      }).length;

  int get _noShowCount => _attendances
      .where((a) => a.status == AttendanceModel.statusNoShow)
      .length;

  Map<String, AttendanceModel> get _attMapByUid {
    final m = <String, AttendanceModel>{};
    for (final a in _attendances) {
      m.putIfAbsent(a.userId, () => a);
    }
    return m;
  }

  // ── 필터 적용 ──────────────────────────────────────────────────

  List<_WorkGroup> get _filteredGroups {
    final groups = _sortedGroups ?? [];
    if (_activeFilter == _SummaryFilter.all) return groups;
    return groups
        .map((g) {
          final filtered = g.workers.where((w) {
            switch (_activeFilter) {
              case _SummaryFilter.checkedIn:
                return w.attStatus == _AttStatus.present ||
                    w.attStatus == _AttStatus.late ||
                    w.attStatus == _AttStatus.checkedOut;
              case _SummaryFilter.notCheckedIn:
                // 출근 전/예정 근로자 (오늘 미경과·미래 날짜)는 미출근 필터 제외
                if (w.attStatus == _AttStatus.notCheckedIn &&
                    _isBeforeStart(w.application)) {
                  return false;
                }
                return w.attStatus == _AttStatus.notCheckedIn ||
                    w.attStatus == _AttStatus.absent;
              case _SummaryFilter.noShow:
                return w.attStatus == _AttStatus.noShow;
              case _SummaryFilter.all:
                return true;
            }
          }).toList();
          if (filtered.isEmpty) return null;
          return _WorkGroup(
            workType: g.workType,
            startTime: g.startTime,
            endTime: g.endTime,
            toTitle: g.toTitle,
            businessName: g.businessName,
            businessId: g.businessId,
            toId: g.toId,
            slotId: g.slotId,
            workDetailId: g.workDetailId,
            isClosedTO: g.isClosedTO,
            workers: filtered,
          );
        })
        .whereType<_WorkGroup>()
        .toList();
  }

  // ══════════════════════════════════════════════════════════════
  // BUILD
  // ══════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    // WorkforceController 로딩 중이면 대기
    final controller = context.watch<WorkforceController>();
    if (controller.isLoading) {
      return const LoadingWidget(message: '인력 정보를 불러오는 중...');
    }

    final bottom = MediaQuery.paddingOf(context).bottom;

    return CustomScrollView(
      controller: _scrollController,
      slivers: [
        SliverToBoxAdapter(child: _buildWeekStrip()),
        SliverToBoxAdapter(child: _buildDateHeader()),
        SliverToBoxAdapter(child: _buildSummaryFilter()),
        const SliverToBoxAdapter(
          child: Divider(height: 1, color: AppColors.grey100),
        ),
        if (_isLoadingData)
          const SliverFillRemaining(
            child: Center(child: LoadingWidget(message: '근무 인력을 불러오는 중...')),
          )
        else if (_loadError != null)
          SliverFillRemaining(child: _buildErrorState())
        else
          _buildSliverWorkerList(),
        if (bottom > 0)
          SliverPadding(padding: EdgeInsets.only(bottom: bottom)),
      ],
    );
  }

  // ── Week Strip ─────────────────────────────────────────────────

  Widget _buildWeekStrip() {
    final monday = _weekMonday;
    final screenWidth = MediaQuery.sizeOf(context).width;
    // 360dp 미만: 요일 생략 (숫자만)
    final showDayLabel = screenWidth >= 360;

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              // 7일 day chips
              Expanded(
                child: Row(
                  children: List.generate(7, (i) {
                    final day = monday.add(Duration(days: i));
                    return Expanded(child: _buildDayChip(day, showDayLabel));
                  }),
                ),
              ),
              // 月 버튼
              GestureDetector(
                onTap: _openMonthCalendar,
                child: Container(
                  width: 36,
                  height: 52,
                  alignment: Alignment.center,
                  child: Icon(
                    Icons.calendar_month_outlined,
                    size: 20,
                    color: AppColors.grey500,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Divider(height: 1, color: AppColors.grey100),
        ],
      ),
    );
  }

  Widget _buildDayChip(DateTime day, bool showDayLabel) {
    final isSelected = DateUtils.isSameDay(day, _selectedDay);
    final isTodayDay = DateUtils.isSameDay(day, _today());
    final isSunday = day.weekday == DateTime.sunday;
    final isSaturday = day.weekday == DateTime.saturday;

    Color dayNumColor = AppColors.textPrimary;
    if (isSunday) dayNumColor = AppColors.error;
    if (isSaturday) dayNumColor = AppColors.info;

    return GestureDetector(
      onTap: () => _selectDay(day),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        height: 52,
        decoration: BoxDecoration(
          color: isSelected
              ? Theme.of(context).primaryColor
              : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (showDayLabel)
              Text(
                _weekdayLabel(day.weekday),
                style: TextStyle(
                  fontSize: 10,
                  color: isSelected
                      ? Colors.white.withValues(alpha: 0.8)
                      : AppColors.grey500,
                  fontWeight: FontWeight.w500,
                ),
              ),
            const SizedBox(height: 2),
            Text(
              '${day.day}',
              style: TextStyle(
                fontSize: 15,
                fontWeight:
                    isSelected ? FontWeight.w700 : FontWeight.w400,
                color: isSelected ? Colors.white : dayNumColor,
              ),
            ),
            // 오늘 indicator dot (선택 상태와 별개)
            const SizedBox(height: 2),
            if (isTodayDay && !isSelected)
              Container(
                width: 4,
                height: 4,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Theme.of(context).primaryColor,
                ),
              )
            else
              const SizedBox(height: 4),
          ],
        ),
      ),
    );
  }

  String _weekdayLabel(int weekday) {
    const labels = ['', '월', '화', '수', '목', '금', '토', '일'];
    return labels[weekday];
  }

  void _selectDay(DateTime day) {
    final normalized = DateTime(day.year, day.month, day.day);
    if (DateUtils.isSameDay(normalized, _selectedDay)) return;
    setState(() => _selectedDay = normalized);
    _loadDayData(normalized);
  }

  Future<void> _openMonthCalendar() async {
    await DialogHelper.showSheet<DateTime>(
      context,
      isScrollControlled: true,
      builder: (ctx) => _MonthCalendarSheet(
        initialDay: _selectedDay,
        onDaySelected: (day) {
          Navigator.of(ctx).pop();
          // 다른 주면 WeekStrip 주간도 이동
          _selectDay(day);
        },
      ),
    );
  }

  // ── Date Header ────────────────────────────────────────────────

  Widget _buildDateHeader() {
    final theme = Theme.of(context);
    final month = _selectedDay.month;
    final day = _selectedDay.day;
    final weekday = FormatHelper.weekday(_selectedDay);

    String dateLabel;
    String? suffixLabel;
    if (_isToday) {
      dateLabel = '오늘 · $month월 $day일 $weekday요일';
    } else {
      dateLabel = '$month월 $day일 $weekday요일';
      final diff = _selectedDay.difference(_today()).inDays;
      if (diff == 1) {
        suffixLabel = '내일';
      } else if (diff == -1) {
        suffixLabel = '어제';
      } else if (diff > 0) {
        suffixLabel = '$diff일 후';
      }
    }

    return Container(
      color: Colors.white,
      padding: EdgeInsets.fromLTRB(
        ResponsiveHelper.spacing(context, 16),
        ResponsiveHelper.spacing(context, 10),
        ResponsiveHelper.spacing(context, 12),
        ResponsiveHelper.spacing(context, 10),
      ),
      child: Row(
        children: [
          Expanded(
            child: Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 6,
              children: [
                Text(
                  dateLabel,
                  style: TextStyle(
                    fontSize: ResponsiveHelper.getFontSize(context, 14),
                    fontWeight: _isToday ? FontWeight.w700 : FontWeight.w500,
                    color: _isToday ? theme.primaryColor : AppColors.textPrimary,
                  ),
                ),
                if (suffixLabel != null)
                  Text(
                    suffixLabel,
                    style: TextStyle(
                      fontSize: ResponsiveHelper.getFontSize(context, 12),
                      color: AppColors.grey500,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // 일괄 근태 처리 — 미래 날짜: 숨김
          if (!_isFuture)
            _buildBatchButton(theme),
          // 지원자 보기 버튼
          const SizedBox(width: 6),
          _buildIconButton(
            icon: Icons.people_outline,
            tooltip: '지원자 명단',
            onTap: _openApplicantsDialog,
          ),
          // 고정 근로자 관리
          _buildIconButton(
            icon: Icons.settings_outlined,
            tooltip: '고정 근로자',
            onTap: _openFixedWorkerManagement,
          ),
        ],
      ),
    );
  }

  Widget _buildBatchButton(ThemeData theme) {
    return GestureDetector(
      onTap: _openAttendanceDialog,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: theme.primaryColor,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          '일괄 근태',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
      ),
    );
  }

  Widget _buildIconButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Icon(icon, size: 20, color: AppColors.grey500),
        ),
      ),
    );
  }

  // ── Summary Filter ─────────────────────────────────────────────

  Widget _buildSummaryFilter() {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final use2x2 = screenWidth < 400;

    final chips = [
      _SummaryChipData(
        filter: _SummaryFilter.all,
        label: '확정',
        count: _totalScheduled,
        color: Theme.of(context).primaryColor, // spec: 확정 → brand primary
      ),
      _SummaryChipData(
        filter: _SummaryFilter.checkedIn,
        label: '출근',
        count: _checkedInCount,
        color: AppColors.successDark,
      ),
      _SummaryChipData(
        filter: _SummaryFilter.notCheckedIn,
        label: '미출근',
        count: _notCheckedInCount,
        color: AppColors.warningDark,
      ),
      _SummaryChipData(
        filter: _SummaryFilter.noShow,
        label: '노쇼',
        count: _noShowCount,
        color: AppColors.errorDark,
      ),
    ];

    return Container(
      color: Colors.white,
      padding: EdgeInsets.fromLTRB(
        ResponsiveHelper.spacing(context, 12),
        ResponsiveHelper.spacing(context, 6),
        ResponsiveHelper.spacing(context, 12),
        ResponsiveHelper.spacing(context, 8),
      ),
      child: use2x2
          ? Column(
              children: [
                Row(
                  children: [
                    Expanded(child: _buildSummaryChip(chips[0])),
                    const SizedBox(width: 6),
                    Expanded(child: _buildSummaryChip(chips[1])),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(child: _buildSummaryChip(chips[2])),
                    const SizedBox(width: 6),
                    Expanded(child: _buildSummaryChip(chips[3])),
                  ],
                ),
              ],
            )
          : Row(
              children: chips
                  .map((c) => Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 3),
                          child: _buildSummaryChip(c),
                        ),
                      ))
                  .toList(),
            ),
    );
  }

  Widget _buildSummaryChip(_SummaryChipData data) {
    final isSelected = _activeFilter == data.filter;
    return GestureDetector(
      onTap: () => setState(() => _activeFilter = data.filter),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
        decoration: BoxDecoration(
          color: isSelected ? data.color.withValues(alpha: 0.08) : Colors.transparent,
          border: Border.all(
            color: isSelected ? data.color : AppColors.grey200,
            width: isSelected ? 1.5 : 1,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${_isLoadingData ? '-' : data.count}',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: data.color,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              data.label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                color: isSelected ? data.color : AppColors.grey500,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  // ── Worker List ────────────────────────────────────────────────

  Widget _buildSliverWorkerList() {
    final groups = _filteredGroups;

    if (groups.isEmpty) {
      return SliverFillRemaining(
        // [5B.2A] filter-aware empty state — all/filter 기준으로 다른 메시지
        child: _buildEmptyState(filter: _activeFilter),
      );
    }

    // 60명 수준 대응: SliverList lazy rendering
    // 각 group은 section header + N worker rows
    // item index → (groupIdx, workerIdx | -1 for header)
    final items = <_ListItem>[];
    for (final g in groups) {
      items.add(_ListItemHeader(g));
      for (final w in g.workers) {
        items.add(_ListItemWorker(g, w));
      }
    }

    return SliverPadding(
      padding: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 0),
        vertical: ResponsiveHelper.spacing(context, 8),
      ),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
          (ctx, i) {
            final item = items[i];
            if (item is _ListItemHeader) {
              return _buildGroupHeader(item.group);
            } else if (item is _ListItemWorker) {
              return _buildWorkerRow(item.group, item.worker);
            }
            return const SizedBox.shrink();
          },
          childCount: items.length,
        ),
      ),
    );
  }

  // ── Group Header ───────────────────────────────────────────────

  Widget _buildGroupHeader(_WorkGroup group) {
    return Container(
      color: AppColors.grey50,
      padding: EdgeInsets.fromLTRB(
        ResponsiveHelper.spacing(context, 16),
        ResponsiveHelper.spacing(context, 10),
        ResponsiveHelper.spacing(context, 16),
        ResponsiveHelper.spacing(context, 6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 6,
                  children: [
                    Text(
                      group.workType,
                      style: TextStyle(
                        fontSize: ResponsiveHelper.getFontSize(context, 13),
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    Text(
                      '${group.startTime}–${group.endTime}',
                      style: TextStyle(
                        fontSize: ResponsiveHelper.getFontSize(context, 12),
                        color: AppColors.grey600,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.grey100,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${group.workerCount}명',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: AppColors.grey600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          // TO 제목 secondary
          if (group.toTitle.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                group.toTitle,
                style: TextStyle(
                  fontSize: 11,
                  color: AppColors.grey400,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
      ),
    );
  }

  // ── Worker Row ─────────────────────────────────────────────────

  Widget _buildWorkerRow(_WorkGroup group, _WorkerEntry worker) {
    final displayName = _workerDisplayName(worker);
    final timeText = _workerTimeText(worker);

    return Material(
      color: Colors.white,
      child: InkWell(
        onTap: () => _openAttendanceDialogForWorker(worker),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: ResponsiveHelper.spacing(context, 16),
            vertical: ResponsiveHelper.spacing(context, 10),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── 이름 + 시간 + 상태 칩 ──
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      displayName,
                      style: TextStyle(
                        fontSize: ResponsiveHelper.getFontSize(context, 14),
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    if (timeText.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        timeText,
                        style: TextStyle(
                          fontSize: ResponsiveHelper.getFontSize(context, 12),
                          color: AppColors.grey600,
                        ),
                      ),
                    ],
                    if (worker.isContractPending) ...[
                      const SizedBox(height: 2),
                      Text(
                        '계약 미작성',
                        style: TextStyle(
                          fontSize: ResponsiveHelper.getFontSize(context, 10),
                          fontWeight: FontWeight.w500,
                          color: AppColors.warningDark,
                        ),
                      ),
                    ],
                    const SizedBox(height: 6),
                    _buildStatusChip(worker),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // ── Action button (우측 상단 고정) ──
              _buildWorkerAction(worker),
            ],
          ),
        ),
      ),
    );
  }

  /// 상태 칩 — 정보 표시 전용, InkWell 없음
  /// status vs action 시각 구분: 작은 radius(6), soft bg, no elevation
  Widget _buildStatusChip(_WorkerEntry worker) {
    // 출근 전/예정 (미래 날짜 포함) → "출근 전" 표시
    final isBeforeStart = worker.attStatus == _AttStatus.notCheckedIn &&
        _isBeforeStart(worker.application);

    final String pillText;
    final Color pillColor;
    final Color pillBg;

    if (isBeforeStart) {
      pillText = '출근 전';
      pillColor = AppColors.grey400;
      pillBg = AppColors.grey50;
    } else {
      pillText = _statusPillText(worker.attStatus);
      pillColor = _statusPillColor(worker.attStatus);
      pillBg = _statusPillBg(worker.attStatus);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: pillBg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: pillColor.withValues(alpha: 0.35), width: 1),
      ),
      child: Text(
        pillText,
        style: TextStyle(
          fontSize: ResponsiveHelper.getFontSize(context, 11),
          fontWeight: FontWeight.w600,
          color: pillColor,
        ),
      ),
    );
  }

  Widget _buildWorkerAction(_WorkerEntry worker) {
    if (_isFuture) return const SizedBox.shrink();

    final status = worker.attStatus;
    String label = '';
    Color bg = Colors.transparent;
    Color fg = AppColors.grey500;
    bool isOutline = false;

    if (_isToday) {
      switch (status) {
        case _AttStatus.notCheckedIn:
          label = '근태 처리';
          bg = Theme.of(context).primaryColor;
          fg = Colors.white;
        case _AttStatus.late:
        case _AttStatus.present:
          label = '근태 확인';
          isOutline = true;
          fg = Theme.of(context).primaryColor;
        case _AttStatus.checkedOut:
          label = '확인';
          isOutline = true;
          fg = AppColors.grey600;
        case _AttStatus.noShow:
          label = '상세';
          isOutline = true;
          fg = AppColors.errorDark;
        case _AttStatus.absent:
          return const SizedBox.shrink();
      }
    } else {
      // 과거
      label = '수정';
      isOutline = true;
    }

    return GestureDetector(
      onTap: () => _openAttendanceDialogForWorker(worker),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(8),
          border: isOutline
              ? Border.all(color: fg)
              : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: ResponsiveHelper.getFontSize(context, 11),
            fontWeight: FontWeight.w600,
            color: fg,
          ),
        ),
      ),
    );
  }

  // ── Status pill helpers ────────────────────────────────────────

  String _statusPillText(_AttStatus s) {
    switch (s) {
      case _AttStatus.notCheckedIn: return '미출근';
      case _AttStatus.present:      return '근무 중';
      case _AttStatus.late:         return '지각';
      case _AttStatus.checkedOut:   return '퇴근 완료';
      case _AttStatus.noShow:       return '노쇼';
      case _AttStatus.absent:       return '결근';
    }
  }

  Color _statusPillColor(_AttStatus s) {
    switch (s) {
      case _AttStatus.notCheckedIn: return AppColors.grey500;
      case _AttStatus.present:      return AppColors.successDark;
      case _AttStatus.late:         return AppColors.warningDark;
      case _AttStatus.checkedOut:   return AppColors.grey600;
      case _AttStatus.noShow:       return AppColors.errorDark;
      case _AttStatus.absent:       return AppColors.grey500;
    }
  }

  Color _statusPillBg(_AttStatus s) {
    switch (s) {
      case _AttStatus.notCheckedIn: return AppColors.grey100;
      case _AttStatus.present:      return AppColors.successBg;
      case _AttStatus.late:         return AppColors.warningBg;
      case _AttStatus.checkedOut:   return AppColors.grey100;
      case _AttStatus.noShow:       return AppColors.errorBg;
      case _AttStatus.absent:       return AppColors.grey100;
    }
  }

  // ── Empty / Error States ───────────────────────────────────────

  /// [5B.2A] filter-aware empty state.
  /// filter == all  → 전체 데이터 없음 (날짜 기준 메시지)
  /// filter != all  → 필터 결과 없음 (필터 기준 메시지)
  Widget _buildEmptyState({_SummaryFilter filter = _SummaryFilter.all}) {
    final String message;
    if (filter == _SummaryFilter.all) {
      message = _isToday
          ? '오늘 확정된 인력이 없습니다.'
          : '이 날짜에 확정된 인력이 없습니다.';
    } else {
      switch (filter) {
        case _SummaryFilter.checkedIn:
          message = '출근한 인원이 없습니다.';
          break;
        case _SummaryFilter.notCheckedIn:
          message = '미출근 인원이 없습니다.';
          break;
        case _SummaryFilter.noShow:
          message = '노쇼 인원이 없습니다.';
          break;
        default:
          message = '해당 인원이 없습니다.';
      }
    }
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.people_outline,
                size: 48, color: AppColors.grey300),
            const SizedBox(height: 12),
            Text(
              message,
              style: TextStyle(
                fontSize: ResponsiveHelper.getFontSize(context, 14),
                color: AppColors.grey500,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 40, color: AppColors.grey400),
            const SizedBox(height: 10),
            Text(
              _loadError ?? '오류가 발생했습니다.',
              style:
                  TextStyle(fontSize: 13, color: AppColors.grey500),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 14),
            TextButton(
              onPressed: _reload,
              child: const Text('다시 시도'),
            ),
          ],
        ),
      ),
    );
  }

  // ── Dialog 진입 ────────────────────────────────────────────────

  Future<void> _openAttendanceDialog() async {
    final businesses = await _ensureBusinesses();
    if (!mounted) return;
    if (businesses.isEmpty) {
      ToastHelper.showWarning('등록된 사업장이 없습니다');
      return;
    }
    final up = context.read<UserProvider>();
    final changed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AttendanceStatusDialog(
        date: _selectedDay,
        businessIds: businesses.map((b) => b.id).toList(),
        initialBusinessId: up.effectiveBusinessId,
        businesses: businesses,
      ),
    );
    if (changed == true && mounted) _reload();
  }

  Future<void> _openAttendanceDialogForWorker(_WorkerEntry worker) async {
    // [5B.2A] focused individual mode — worker의 applicationId를 전달해 해당 탭으로 자동 이동 + 행 강조
    final businesses = await _ensureBusinesses();
    if (!mounted) return;
    if (businesses.isEmpty) {
      ToastHelper.showWarning('등록된 사업장이 없습니다');
      return;
    }
    final up = context.read<UserProvider>();
    final changed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AttendanceStatusDialog(
        date: _selectedDay,
        businessIds: businesses.map((b) => b.id).toList(),
        initialBusinessId: up.effectiveBusinessId,
        businesses: businesses,
        initialApplicationId: worker.application.id,
      ),
    );
    if (changed == true && mounted) _reload();
  }

  Future<void> _openApplicantsDialog() async {
    if (_selectedDay == DateTime(0)) return;
    try {
      final businesses = await _ensureBusinesses();
      if (businesses.isEmpty) {
        if (mounted) ToastHelper.showWarning('등록된 사업장이 없습니다');
        return;
      }
      if (!mounted) return;
      final changed = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => DayApplicantsDialog(
          date: _selectedDay,
          businessIds: businesses.map((b) => b.id).toList(),
          businesses: businesses,
        ),
      );
      if (changed == true && mounted) _reload();
    } catch (e) {
      debugPrint('❌ 지원명단 조회 실패: $e');
      if (mounted) ToastHelper.showError('사업장 정보를 불러올 수 없습니다');
    }
  }

  Future<void> _openFixedWorkerManagement() async {
    final up = context.read<UserProvider>();
    if (!up.can((p) => p.canManageWorkers)) return;
    try {
      final businesses = await _ensureBusinesses();
      if (businesses.isEmpty) {
        if (mounted) ToastHelper.showWarning('등록된 사업장이 없습니다');
        return;
      }
      if (!mounted) return;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => FixedWorkerManagementDialog(
          businessIds: businesses.map((b) => b.id).toList(),
          businesses: businesses,
          focusDate: _selectedDay,
          onChanged: _reload,
        ),
      );
    } catch (e) {
      debugPrint('❌ 사업장 조회 실패: $e');
      if (mounted) ToastHelper.showError('사업장 정보를 불러올 수 없습니다');
    }
  }
}

// ══════════════════════════════════════════════════════════════════
// 내부 리스트 아이템 타입 (SliverList lazy rendering용)
// ══════════════════════════════════════════════════════════════════

abstract class _ListItem {}

class _ListItemHeader extends _ListItem {
  final _WorkGroup group;
  _ListItemHeader(this.group);
}

class _ListItemWorker extends _ListItem {
  final _WorkGroup group;
  final _WorkerEntry worker;
  _ListItemWorker(this.group, this.worker);
}

// ══════════════════════════════════════════════════════════════════
// Summary Chip 데이터
// ══════════════════════════════════════════════════════════════════

class _SummaryChipData {
  final _SummaryFilter filter;
  final String label;
  final int count;
  final Color color;
  const _SummaryChipData({
    required this.filter,
    required this.label,
    required this.count,
    required this.color,
  });
}

// ══════════════════════════════════════════════════════════════════
// 月 캘린더 Bottom Sheet
// ══════════════════════════════════════════════════════════════════

class _MonthCalendarSheet extends StatefulWidget {
  final DateTime initialDay;
  final void Function(DateTime) onDaySelected;

  const _MonthCalendarSheet({
    required this.initialDay,
    required this.onDaySelected,
  });

  @override
  State<_MonthCalendarSheet> createState() => _MonthCalendarSheetState();
}

class _MonthCalendarSheetState extends State<_MonthCalendarSheet> {
  late DateTime _focusedDay;
  late DateTime _selectedDay;

  @override
  void initState() {
    super.initState();
    _focusedDay = widget.initialDay;
    _selectedDay = widget.initialDay;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Handle
        Container(
          margin: const EdgeInsets.only(top: 12, bottom: 8),
          width: 36,
          height: 4,
          decoration: BoxDecoration(
            color: AppColors.grey300,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '날짜 선택',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close, size: 20),
                color: AppColors.grey500,
              ),
            ],
          ),
        ),
        AppCalendar(
          focusedDay: _focusedDay,
          selectedDay: _selectedDay,
          onDaySelected: (selectedDay, focusedDay) {
            widget.onDaySelected(selectedDay);
          },
          onPageChanged: (focusedDay) {
            setState(() => _focusedDay = focusedDay);
          },
          eventLoader: (_) => const [],
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}
