import 'package:flutter/material.dart';
import 'my_schedule_reads.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../models/core/application_model.dart';
import '../../models/core/worker_availability_model.dart';
import '../../services/firestore_service.dart';
import '../../services/availability_service.dart';
import '../../providers/user_provider.dart';
import '../../utils/toast_helper.dart';
import '../../utils/calendar_helper.dart';
import '../../utils/responsive_helper.dart';
import '../../utils/format_helper.dart';
import '../../widgets/common/loading_widget.dart';
import '../../widgets/calendar/schedule_calendar.dart';
import '../../widgets/calendar/schedule_card.dart';
import '../../models/core/attendance_model.dart';
import '../../theme/app_colors.dart';
import '../../theme/concept_tokens.dart';
import '../../utils/text_layout.dart';
import '../../utils/expected_daily_wage.dart';
import '../../screens/payroll/payslip_period_helper.dart';
import '../../screens/payroll/payslip_pdf_builder.dart';
import 'package:printing/printing.dart';
import '../../widgets/common/app_empty_state.dart';
import 'tab_revisit_watch.dart';
import 'user_tab_scope.dart';
import '../../models/core/invite_region_preference.dart';
import '../../services/invite_region_service.dart';
import 'invite_region_settings_screen.dart';
import '../../utils/person_label.dart';

class MyScheduleScreen extends StatefulWidget {
  /// 근태 → Map (applicationId + **KST 근무일** 복합키 · 월·일 미패딩).
  ///   [AUD-4 H9 · 판정296] 조회 키는 달력이 고른 날(KST 달력 성분 · S82)이다. 예전에는 근태 쪽 키만 **기기 성분**
  ///   (`att.workDate.year/month/day`)이라 KST 가 아닌 기기에서 그날 카드에 근태가 붙지 않았다(확정 급여 대신 예상 금액 ·
  ///   출근 상태 누락). 저장 근무일은 KST 자정 instant 이므로 KST 날짜로 키를 만든다. KST 기기에서는 결과가 같다.
  static Map<String, AttendanceModel> buildAttendanceMap(List<AttendanceModel> list) {
    final map = <String, AttendanceModel>{};
    for (final att in list) {
      final d = FormatHelper.toKstDate(att.workDate);
      map['${att.applicationId}_${d.year}-${d.month}-${d.day}'] = att;
    }
    return map;
  }

  const MyScheduleScreen({super.key, this.reads, this.clock});

  /// [R7-P2-3 READ] 화면을 만들 때의 읽기 경계. production 은 null.
  final MyScheduleReads? reads;

  /// [PERF-P9] 재방문 신선도의 "지금". production 은 null → `DateTime.now`.
  final DateTime Function()? clock;

  @override
  State<MyScheduleScreen> createState() => _MyScheduleScreenState();
}

class _MyScheduleScreenState extends State<MyScheduleScreen> {
  static final _fmt = NumberFormat('#,###');
  final FirestoreService _firestoreService = FirestoreService();
  final AvailabilityService _availabilityService = AvailabilityService();
  late final MyScheduleReads _reads = widget.reads ??
      MyScheduleReads.of(
          _firestoreService, _availabilityService, _inviteRegionService);
  // [R2.3] 초대 받을 지역 — null = 아직 안 읽음(로딩). UNKNOWN과 구분한다.
  final InviteRegionService _inviteRegionService = InviteRegionService();
  InviteRegionPreference? _invitePref;

  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  // 월 빠른 전환 시 stale 배치 무시 — _loadMonthlyAttendances와 세대 비교
  int _monthGeneration = 0;

  List<ApplicationModel> _applications = [];
  bool _isLoading = true;

  /// [R5-R0.1 §20] 조회 실패 사유 — "없음"과 다른 축이다.
  String? _loadError;

  /// [DU213 C18] 현재 표시월의 월근태 조회 실패 — 일정 실패(_loadError)와 다른 축이다.
  ///   근태 실패를 정상 0 으로 말하지 않는다(실근무·확정수입·예상수입이 모두 근태에 기댄다).
  String? _attError;

  /// [DU213 C17] 현재 표시월의 일정+월근태 조회가 진행 중이다(두 번째 단계·월 이동·재시도).
  bool _monthLoading = false;

  /// [DU213 C17] 일정+월근태가 **모두 성공**한 달. 표시월과 다르면 요약 숫자는 그 달의 사실이 아니다.
  DateTime? _loadedMonth;

  /// [DU213] 표시월 자료가 완결됐는가 — 요약 숫자·일정 표식·카드 목록은 이때만 보인다.
  bool get _monthComplete =>
      !_isLoading &&
      !_monthLoading &&
      _loadError == null &&
      _attError == null &&
      _loadedMonth != null &&
      _loadedMonth!.year == _focusedDay.year &&
      _loadedMonth!.month == _focusedDay.month;
  bool _initialLoadStarted = false;

  // ── [PERF-P9 · 판정291 §8] 재방문 신선도 ─────────────────────────────────
  //   다시 보이거나 보이는 채로 앱이 복귀하면: 계정이 바뀌었으면 처음부터, 지원·근태 무효화 세대가 바뀌었거나
  //   (출퇴근·지원·취소 등) 1분이 지났거나 KST 날짜가 바뀌었으면 **보이는 달력·목록을 둔 채** 표시월을 다시 읽는다.
  //   지난 조회가 실패한 상태면 다시 읽는다. 이미 신선하면 호출 0. 고른 달·날짜·상태 필터·가능일 편집은 건드리지 않는다.
  //   실패는 기존 월 조회 실패 정책 그대로다(DU213 — 미완결 자료를 현재 사실로 두지 않는다).
  static const Duration _freshFor = Duration(minutes: 1);
  late final TabRevisitWatch _revisit = TabRevisitWatch(onRevisit: _onRevisit);
  DateTime? _scheduleLoadedAt;
  Object? _revAtLoad;
  String? _loadedUid;
  DateTime _now() => (widget.clock ?? DateTime.now)();

  void _markFresh(String uid, Object? rev) {
    _scheduleLoadedAt = _now();
    _revAtLoad = rev;
    _loadedUid = uid;
  }

  void _onRevisit() {
    if (!mounted || _isLoading || _monthLoading) return;
    final uid = context.read<UserProvider>().currentUser?.uid;
    if (uid == null) return;
    if (_loadedUid != null && uid != _loadedUid) {
      _loadApplications();
      return;
    }
    if (_loadError != null || _attError != null) {
      _loadMonthlyAttendances(_focusedDay);
      return;
    }
    final at = _scheduleLoadedAt;
    final now = _now();
    final stale = at == null ||
        now.difference(at) >= _freshFor ||
        FormatHelper.toKstDate(now) != FormatHelper.toKstDate(at) ||
        _reads.dataRevision?.call(uid) != _revAtLoad;
    if (stale) _loadMonthlyAttendances(_focusedDay, quiet: true);
  }

  // 필터: ALL / CONFIRMED / PENDING
  String _selectedFilter = 'ALL';

  // 날짜별 인덱스 캐시 (getEventsForDay O(n) → O(1))
  Map<String, List<ApplicationModel>> _dateIndex = {};

  // 출근 기록 — Map으로 O(1) 조회
  // key: "${applicationId}_${yyyy}-${M}-${d}"
  Map<String, AttendanceModel> _attendanceMap = {};

  // ─── Phase 8.1A: 근무 가능일 ────────────────────────────────
  /// 저장된 가능일 날짜 키 Set — 캘린더 윤곽선, 배너 카운트에 사용.
  ///
  /// [E1-AVAIL] 이 값만으로는 **등록이 0일인지 못 읽었는지** 알 수 없다.
  ///   판단은 반드시 [_availLoad] 를 먼저 본다.
  Set<String> _availabilityDates = {};

  /// [E1-AVAIL] 가능일을 **읽었는가**.
  ///
  ///   예전에는 `_loadAvailability` 가 catch 에서 `debugPrint` 만 하고
  ///   `_availabilityDates` 를 `{}` 로 남겼다. 그래서 조회가 실패하면
  ///   화면이 `근무 가능일 0일 등록됨` 과 미등록 안내를 띄웠고, 등록해 둔
  ///   사람에게 **등록을 다시 하라**고 말했다. 더 나쁜 것은 그 상태에서
  ///   수정에 들어가면 `_editingDates` 가 빈 세트로 시작해, 저장 한 번에
  ///   **기존 가능일이 전부 지워진다**는 점이다.
  ///
  ///   같은 화면의 초대 지역은 이미 `InviteRegionPreference.unknown()` 으로
  ///   ERROR 와 OFF 를 가른다([R2.3] §8). 같은 자를 가능일에도 쓴다.
  _AvailLoad _availLoad = _AvailLoad.loading;

  /// 재조회 중이지만 이전에 읽은 값이 남아 있다(stale). 숫자는 보여 주되
  ///   방금 확인한 값이라고 말하지 않는다.
  bool _availRefreshing = false;

  /// [E1-DATE] **지금 유효한** 가능일. 저장 원본(`_availabilityDates`)과 다르다.
  ///
  ///   `callableSetAvailability` 는 `today ~ +90일`(KST) 밖을 떨어내고 60개로
  ///   자른다. 그런데 화면은 저장 원본을 그대로 세어 `2일 등록됨`·`2일 저장`
  ///   이라고 말했고, 그 중 하루는 이미 지난 날이라 저장하면 사라졌다
  ///   (DEV 실측: 원본 2일 · 유효 1일). 사용자는 모르는 채 하루를 잃는다.
  ///
  ///   그래서 **배너·달력·수정 초기 선택·저장 payload 가 모두 이 한 집합**을
  ///   쓴다. 서버 정책을 여기에 다시 적지 않고 canonical
  ///   `WorkerAvailabilityModel.filterValidDates` 를 그대로 호출한다.
  ///
  ///   저장 원본은 지우지 않는다 — 과거 기록의 보관은 별개 문제다.
  Set<String> get _validAvailabilityDates =>
      WorkerAvailabilityModel.filterValidDates(_availabilityDates.toList())
          .toSet();

  /// [E1-DATE] 지금 저장 버튼을 누르면 **서버가 받게 될** 집합.
  ///   버튼 문구와 실제 전송이 같은 값을 쓰도록 한 곳에서 만든다.
  Set<String> get _editingPayload =>
      WorkerAvailabilityModel.filterValidDates(_editingDates.toList()).toSet();
  /// 에디트 모드 활성화 여부
  bool _isEditMode = false;
  /// 에디트 모드에서 현재 선택 중인 날짜 키 Set
  Set<String> _editingDates = {};
  /// 저장 중 상태 (중복 호출 방지)
  bool _isSavingAvailability = false;

  // ─── 월별 통계 캐시 (build()마다 재계산 방지) ─────────────
  int _cachedConfirmedCount = 0;
  int _cachedTotalIncome = 0;
  /// [AUD-3 M3] 예상수입 합계에 넣지 못한 근무 수(약속 휴게 모름 · 월급 · 유형 모름 등).
  int _cachedIncomeUnknown = 0;
  int _cachedActualDays = 0;
  int _cachedConfirmedIncome = 0;
  List<AttendanceModel> _cachedConfirmedWageRecords = []; // H2: getter 대신 캐시
  List<ApplicationModel> _selectedDayEvents = []; // H1: 선택 날짜 이벤트 캐시 (정렬 포함)

  void _recomputeStats() {
    _dateIndex = CalendarHelper.buildDateIndex(_applications, _selectedFilter);

    final thisMonth = CalendarHelper.getThisMonthApplications(_applications, _focusedDay);
    final attendances = _attendanceMap.values.toList();
    _cachedConfirmedCount  = CalendarHelper.getConfirmedCount(thisMonth);
    // [PREDEVICE-INCOME-NOSHOW] 근태를 함께 넘긴다 — NO_SHOW·결근으로 마감된
    //   날이 예상수입에 남지 않도록.
    final income = CalendarHelper.getTotalIncomeDetail(
        thisMonth, _focusedDay, attendances: attendances, now: DateTime.now());
    _cachedTotalIncome     = income.total;
    _cachedIncomeUnknown   = income.unknownShifts;
    _cachedActualDays      = CalendarHelper.getActualWorkDays(attendances, _focusedDay);
    _cachedConfirmedIncome = CalendarHelper.getConfirmedIncome(attendances, _focusedDay);
    // H2: 확정 급여 기록 — 월 기준으로 필터링 후 캐시
    final year = _focusedDay.year;
    final month = _focusedDay.month;
    _cachedConfirmedWageRecords = attendances.where((a) =>
      FormatHelper.isSameKstMonth(a.workDate, DateTime(year, month)) &&
      (a.wageStatus == AttendanceModel.wageConfirmed ||
       a.wageStatus == AttendanceModel.wageTransferred) &&
      a.wageDetail != null,
    ).toList();
    _recomputeSelectedDayEvents(); // H1: dateIndex 갱신 후 선택 날짜 이벤트 재계산
  }

  // H1: 선택 날짜 이벤트를 캐싱 + 정렬 — _buildDayEventCount·_buildSliverScheduleList 공유
  void _recomputeSelectedDayEvents() {
    if (_selectedDay == null) {
      _selectedDayEvents = [];
      return;
    }
    final events = CalendarHelper.getEventsForDayFromIndex(_selectedDay!, _dateIndex);
    events.sort((a, b) => _statusOrder(a.status).compareTo(_statusOrder(b.status)));
    _selectedDayEvents = events;
  }

  @override
  void initState() {
    super.initState();
    _revisit.attach();
    _selectedDay = DateTime(
      _focusedDay.year,
      _focusedDay.month,
      _focusedDay.day,
    );
    // 근무 가능일 백그라운드 로드 (캘린더 로드를 블로킹하지 않음)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _loadAvailability();
      _loadInvitePref(); // [R2.3] 같은 문서라 추가 왕복이 사실상 없다
    });
  }

  @override
  void dispose() {
    _revisit.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _revisit.updateFrom(context);
    final scope = UserTabScope.of(context);
    if (!_initialLoadStarted) {
      _initialLoadStarted = true;
      // [PERF-L5 · 판정290 §7] 첫 생성(지연 생성 뒤 첫 방문)에 받은 날짜·달은 **첫 조회 전에** 동기로 반영한다.
      //   예전에는 첫 조회를 먼저 출발시키고 postFrame 에서 다른 달로 옮겨 세대를 올렸다 — 첫 조회가 세대 검사에서
      //   빠지며 `_isLoading` 을 끄지 못해 화면이 '일정을 불러오고 있어요'에 갇혔다(LOCAL 재현 L5S-1).
      //   이제 첫 조회가 처음부터 그 달을 읽는다(조회 1벌). 소비(clear)만 postFrame 에서 한다.
      final firstDate = scope?.pendingScheduleDate;
      final clearFirstDate = scope?.clearPendingScheduleDate;
      final firstMonth = scope?.pendingScheduleMonth;
      final clearFirstMonth = scope?.clearPendingScheduleMonth;
      if (firstDate != null && clearFirstDate != null) {
        final day = DateTime(firstDate.year, firstDate.month, firstDate.day);
        _selectedFilter = 'ALL';
        _focusedDay = day;
        _selectedDay = day;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) clearFirstDate();
        });
      }
      if (firstMonth != null && clearFirstMonth != null) {
        // 첫 생성의 표시월은 이미 이번 달이다(날짜 지정이 있으면 그쪽이 이긴다 — root 가 둘을 같이 두지 않는다).
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) clearFirstMonth();
        });
      }
      _loadApplications();
      return;
    }
    // pendingScheduleMonth: 홈 "근무 기록 보기" 경유 진입 시 현재 달로 리셋.
    // UserJobTab.didChangeDependencies의 pendingJobDate 소비 패턴과 동일.
    // clearFn을 여기서 캡처 — postFrameCallback 안에서 context 재호출 시
    // debug assertion이 터지므로 클로저로 미리 캡처한다.
    final pending = scope?.pendingScheduleMonth;
    if (pending != null) {
      final clearFn = scope!.clearPendingScheduleMonth;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        clearFn();
        final now = DateTime.now();
        // 이미 현재 달이면 스킵 (불필요한 리로드 방지)
        if (_focusedDay.year == now.year && _focusedDay.month == now.month) return;
        _monthGeneration++;
        setState(() {
          _focusedDay = DateTime(now.year, now.month, now.day);
          _selectedDay = DateTime(now.year, now.month, now.day);
        });
        _loadMonthlyAttendances(_focusedDay);
      });
    }
    // [판정285 §4·§5] 홈 선택일 「내 일정에서 보기」 — 그 날짜의 월·날짜·당일 목록 + 상태 필터 ALL.
    //   이미 열렸던 탭(IndexedStack 이라 이전 선택·필터가 남아 있다)·다른 달·이전 확정/대기 필터 모두 여기서 맞춘다.
    //   소비는 1회(clear) — 이후 일반 탭 전환은 사용자가 고른 상태를 그대로 둔다.
    final pendingDate = scope?.pendingScheduleDate;
    final clearDate = scope?.clearPendingScheduleDate;
    if (pendingDate != null && clearDate != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        clearDate();
        _showScheduleDate(pendingDate);
      });
    }
  }

  /// [판정285 §5] 외부에서 받은 날짜(KST 달력일 — 년·월·일 성분)로 달력·목록을 맞춘다.
  ///   다른 달이면 그 달을 새로 읽는다(기존 월 이동과 같은 경로). 같은 달이면 색인·당일 목록만 다시 계산한다.
  ///   가능일 편집 중이면 편집 내용을 버리지 않는다 — 날짜·필터만 맞추고 편집은 사용자가 끝낸다.
  void _showScheduleDate(DateTime date) {
    final day = DateTime(date.year, date.month, date.day);
    final otherMonth = _focusedDay.year != day.year || _focusedDay.month != day.month;
    setState(() {
      _selectedFilter = 'ALL';
      _focusedDay = day;
      _selectedDay = day;
      _recomputeStats();
    });
    if (otherMonth) {
      _monthGeneration++;
      _loadMonthlyAttendances(day);
    }
  }

  // ─── 데이터 로드 ────────────────────────────────────────────

  Future<void> _loadApplications() async {
    if (!mounted) return;
    final uid = context.read<UserProvider>().currentUser?.uid;
    if (uid == null) {
      ToastHelper.showError('로그인이 필요해요');
      setState(() => _isLoading = false);
      return;
    }
    // [DU213 C17·C19] 이 요청의 세대·표시월 — 늦게 온 응답·오류·toast 가 새 상태를 덮지 않는다.
    final gen = ++_monthGeneration;
    final month = DateTime(_focusedDay.year, _focusedDay.month);
    final revAtStart = _reads.dataRevision?.call(uid);
    setState(() {
      _isLoading = true;
      _loadError = null;
      _attError = null;
      _monthLoading = true;
    });

    // [PERF-L20] 지원 내역과 표시월 근태를 **같이 출발**시킨다(예전: 지원 → 근태 직렬 · 1 왕복).
    //   반영 순서는 그대로 지원 먼저 — 달력·목록이 먼저 서고 근태가 뒤따른다. 두 실패는 각각 붙잡는다
    //   (지원이 실패하면 근태 결과는 버린다 · 처리되지 않은 오류를 남기지 않는다).
    final appsF = _reads
        .myApplications(uid)
        .then<Object?>((v) => v, onError: (Object e) => _ReadFail(e));
    final attsF = _reads
        .myMonthlyAttendances(userId: uid, year: month.year, month: month.month)
        .then<Object?>((v) => v, onError: (Object e) => _ReadFail(e));

    // Phase 1: 지원 내역 반영 (1분 TTL 캐시 — 재방문 시 즉시 반환)
    final appsResult = await appsF;
    if (!mounted || gen != _monthGeneration) return;
    if (appsResult is _ReadFail) {
      debugPrint('❌ 지원 내역 로드 실패: ${appsResult.error}');
      setState(() {
        _isLoading = false;
        _monthLoading = false;
        _loadError = '일정을 불러오지 못했습니다.';
        // [DU213 C19] 실패한 조회의 이전 목록을 현재 사실로 남기지 않는다.
        _applications = [];
        _attendanceMap = {};
        _loadedMonth = null;
        _recomputeStats();
      });
      ToastHelper.showError('일정을 불러오지 못했어요');
      return;
    }
    _applications = appsResult as List<ApplicationModel>;
    _attendanceMap = {};
    _recomputeStats();
    setState(() => _isLoading = false);

    // Phase 2: 출근 기록 반영 (2분 TTL 캐시 · 이미 출발해 있다)
    // [DU213 C18] 실패를 조용히 삼키지 않는다 — 요약은 '확인하지 못함', 목록 자리에 지속 안내·다시 시도.
    final attsResult = await attsF;
    if (!mounted || gen != _monthGeneration) return;
    if (attsResult is _ReadFail) {
      debugPrint('❌ 출근 기록 로드 실패: ${attsResult.error}');
      setState(() {
        _monthLoading = false;
        _attError = '출근 기록을 불러오지 못했습니다';
        _loadedMonth = null;
      });
      return;
    }
    _markFresh(uid, revAtStart); // [PERF-P9] 신선도 기준점
    setState(() {
      _attendanceMap = _buildAttendanceMap(attsResult as List<AttendanceModel>);
      _recomputeStats();
      _monthLoading = false;
      _loadedMonth = month;
    });
  }

  /// [PERF-L20] 당겨서 새로고침 · 일정 카드 변경 뒤 — **달력을 그대로 둔 채**(`_monthLoading`) 표시월만 다시 읽는다.
  ///   예전에는 `_loadApplications` 가 `_isLoading=true` 로 화면 전체를 로딩 표지로 바꿨고(달력이 사라졌다 돌아옴),
  ///   1분/2분 TTL 캐시 때문에 방금 바뀐 서버 값을 못 볼 수 있었다 → 먼저 이 사용자의 두 캐시를 비운다.
  ///   첫 조회 전(`_isLoading`)이나 첫 조회 실패 화면의 '다시 시도'는 기존 전체 경로(`_loadApplications`)다.
  Future<void> _refreshSchedule() async {
    if (!mounted) return;
    if (_isLoading) return _loadApplications();
    final uid = context.read<UserProvider>().currentUser?.uid;
    if (uid != null) _reads.invalidateCaches?.call(uid);
    await _loadMonthlyAttendances(_focusedDay);
  }
  /// 월 이동 시 호출 — 출근 기록 + 지원 내역 모두 갱신
  ///
  /// [B03] 이전 코드는 _loadMonthlyAttendances에서 출근 기록만 재조회하고
  /// _applications(getMyApplications)는 재조회하지 않았다.
  /// TTL 캐시(1분)가 있어 서버 부담이 거의 없고, 장기 지원서는 월별로
  /// isScheduledOnDate 판단이 달라지므로 _applications도 함께 갱신해야
  /// 통계·캘린더 인덱스가 올바르게 갱신된다.
  ///
  /// [quiet] — [PERF-P9] 재방문 재검증. **같은 달**을 다시 읽는 동안 보이는 값·표식을 지우지 않는다
  ///   (DU213 C17 은 다른 달로 옮길 때 이전 달 값을 숨기려는 규칙이다). 결과 반영·실패 처리는 일반 경로와 같다.
  Future<void> _loadMonthlyAttendances(DateTime focusedDay, {bool quiet = false}) async {
    if (!mounted) return;
    final gen = ++_monthGeneration; // 빠른 전환 시 stale 배치 폐기용
    final uid = context.read<UserProvider>().currentUser?.uid;
    if (uid == null) return;
    final month = DateTime(focusedDay.year, focusedDay.month);
    final revAtStart = _reads.dataRevision?.call(uid);
    final sameShownMonth = _loadedMonth != null &&
        _loadedMonth!.year == month.year &&
        _loadedMonth!.month == month.month;
    // [DU213 C17] 새 표시월의 두 read 가 끝나기 전에는 이전 월 값·목록·표식을 보이지 않는다.
    if (!(quiet && sameShownMonth)) {
      setState(() {
        _monthLoading = true;
        _loadError = null;
        _attError = null;
        _loadedMonth = null;
      });
    }
    // 두 read 를 함께 보내고 실패를 각각 붙잡는다 — 먼저 끝난 실패가 처리되지 않은 채 남지 않게.
    final results = await Future.wait<Object?>([
      _reads
          .myApplications(uid)
          .then<Object?>((v) => v, onError: (Object e) => _ReadFail(e)),
      _reads
          .myMonthlyAttendances(
              userId: uid, year: month.year, month: month.month)
          .then<Object?>((v) => v, onError: (Object e) => _ReadFail(e)),
    ]);
    if (!mounted || _monthGeneration != gen) return; // stale — 새 세대의 로딩 상태를 끄지 않는다
    final apps = results[0];
    final atts = results[1];
    if (apps is _ReadFail) {
      debugPrint('❌ 월별 지원 내역 로드 실패: ${apps.error}');
      setState(() {
        _isLoading = false; // [PERF-L5 · 판정290 §7] 현재 세대의 실패도 첫 로딩을 끝낸다
        _monthLoading = false;
        _loadError = '일정을 불러오지 못했습니다.';
        _applications = [];
        _attendanceMap = {};
        _recomputeStats();
      });
      ToastHelper.showError('일정을 불러오지 못했어요');
      return;
    }
    if (atts is _ReadFail) {
      debugPrint('❌ 월별 출근 기록 로드 실패: ${atts.error}');
      setState(() {
        _isLoading = false; // [PERF-L5] 현재 세대 실패
        _monthLoading = false;
        _attError = '출근 기록을 불러오지 못했습니다';
        // 근태를 모르는 카드·표식(미완결 자료)은 노출하지 않는다 — 화면 로컬 자료만 비운다.
        _applications = [];
        _attendanceMap = {};
        _recomputeStats();
      });
      ToastHelper.showError('출근 기록을 불러오지 못했어요');
      return;
    }
    _markFresh(uid, revAtStart); // [PERF-P9] 신선도 기준점
    setState(() {
      _isLoading = false; // [PERF-L5] 현재 세대 성공 — 이 함수가 지원 목록도 다시 읽었다
      _applications = apps as List<ApplicationModel>;
      _attendanceMap = _buildAttendanceMap(atts as List<AttendanceModel>);
      _recomputeStats();
      _monthLoading = false;
      _loadedMonth = month;
    });
  }

  // ─── Phase 8.1A: 근무 가능일 CRUD ──────────────────────────

  /// [E1-AVAIL] 가능일 축의 상태 한 줄. 배너와 같은 자리를 쓰되 숫자를
  ///   주장하지 않는다 — 모르면 모른다고 말하고 다시 시도할 길을 준다.
  Widget _availabilityNotice(
    String text, {
    required IconData icon,
    bool isError = false,
    VoidCallback? onRetry,
  }) {
    final color = isError ? AppColors.errorDark : AppColors.grey600;
    return Container(
      margin: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 12),
        vertical: ResponsiveHelper.spacing(context, 6),
      ),
      padding: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 12),
        vertical: ResponsiveHelper.spacing(context, 8),
      ),
      decoration: BoxDecoration(
        color: isError ? AppColors.errorBg : AppColors.grey100,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(icon, size: ResponsiveHelper.iconSize(context, 18), color: color),
          SizedBox(width: ResponsiveHelper.spacing(context, 8)),
          Expanded(
            child: Text(
              text,
              style: ResponsiveHelper.smallStyle(context, color: color),
            ),
          ),
          if (onRetry != null)
            TextButton(
              onPressed: onRetry,
              style: TextButton.styleFrom(
                padding: EdgeInsets.symmetric(
                    horizontal: ResponsiveHelper.spacing(context, 8)),
                // [DU1 구현67 · 감사67 §5] 가능일 다시 시도 터치 최소 48×48 — 320@2.0 115.6×37.0,
                //   360@1.0 65.7×19.0 였다(Size.zero+shrinkWrap). 배율로 줄이지 않는 고정 하한.
                minimumSize: const Size(48, 48),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text('다시 시도',
                  style: ResponsiveHelper.smallStyle(context,
                      color: AppColors.brand)),
            ),
        ],
      ),
    );
  }

  /// 저장된 근무 가능일 로드.
  ///
  /// [E1-AVAIL] 실패를 조용히 삼키지 않는다 — 삼키면 등록해 둔 날짜가
  ///   `0일` 로 보이고, 그 상태에서 수정에 들어가면 저장 한 번에 지워진다.
  ///   읽은 값이 이미 있으면 유지하되(stale) 새로 읽는 중임을 표시한다.
  Future<void> _loadAvailability() async {
    if (!mounted) return;
    final uid = context.read<UserProvider>().currentUser?.uid;
    if (uid == null) return;
    final hadValue = _availLoad == _AvailLoad.ok;
    setState(() {
      if (hadValue) {
        _availRefreshing = true;
      } else {
        _availLoad = _AvailLoad.loading;
      }
    });
    try {
      final model = await _reads.myAvailability(uid);
      if (!mounted) return;
      setState(() {
        _availabilityDates = model?.dateSet ?? {};
        _availLoad = _AvailLoad.ok;
        _availRefreshing = false;
      });
    } catch (e) {
      debugPrint('❌ 근무 가능일 로드 실패: $e');
      if (!mounted) return;
      setState(() {
        _availRefreshing = false;
        // 이전에 읽은 값이 있으면 지우지 않는다 — 0 으로 덮어쓰는 것이
        //   바로 이 Phase 가 고치는 결함이다.
        if (!hadValue) _availLoad = _AvailLoad.failed;
      });
    }
  }

  /// 에디트 모드 진입. 기존 가능일로 editingDates 초기화.
  ///
  /// [E1-AVAIL] 기존 값을 **모르는 채로** 들어가지 않는다. 읽지 못한 상태에서
  ///   진입하면 `_editingDates` 가 빈 세트로 시작하고, 저장 한 번에 등록해 둔
  ///   날짜가 전부 사라진다. 저장은 `dates` 전체를 덮어쓰는 계약이기 때문이다.
  void _enterEditMode() {
    if (_availLoad != _AvailLoad.ok) {
      ToastHelper.showWarning(
          '등록한 근무 가능일을 불러오지 못해 수정할 수 없어요. 다시 시도해 주세요.');
      _loadAvailability();
      return;
    }
    setState(() {
      _isEditMode = true;
      // [E1-DATE] 수정은 **지금 유효한** 날짜에서 시작한다 — 과거 날짜를
      //   담고 들어가면 저장 버튼이 그만큼 더 큰 수를 말하고, 서버는
      //   그 날짜를 떨어낸다.
      _editingDates = Set<String>.from(_validAvailabilityDates);
    });
  }

  /// 에디트 모드 취소. 변경사항 버림.
  void _cancelEdit() {
    setState(() {
      _isEditMode = false;
      _editingDates = {};
    });
    _ensureMonthLoaded();
  }

  /// [DU213 C17] 에디트 모드에서 달을 옮겼다면 나올 때 그 달을 읽는다 — 이전 월 값을 새 월로 보이지 않게.
  void _ensureMonthLoaded() {
    if (_isLoading || _monthLoading) return;
    if (_loadError != null || _attError != null) return;
    final lm = _loadedMonth;
    if (lm != null && lm.year == _focusedDay.year && lm.month == _focusedDay.month) return;
    _loadMonthlyAttendances(_focusedDay);
  }

  /// 에디트 모드에서 날짜 토글 (tap = 선택/해제)
  void _toggleDate(DateTime day) {
    final key = WorkerAvailabilityModel.dateKeyFrom(day);
    setState(() {
      if (_editingDates.contains(key)) {
        _editingDates.remove(key);
      } else {
        if (_editingDates.length >= 60) {
          ToastHelper.showWarning('최대 60일까지 등록할 수 있어요');
          return;
        }
        _editingDates.add(key);
      }
    });
  }

  /// 에디트 모드에서 저장. Rules에서 city canonical 검증 수행.
  Future<void> _saveAvailability() async {
    if (_isSavingAvailability) return;
    final user = context.read<UserProvider>().currentUser;
    if (user == null) {
      ToastHelper.showError('로그인이 필요해요');
      return;
    }
    final city = user.homeRegion?.city;
    if (city == null || city.isEmpty) {
      ToastHelper.showError('지역 정보가 없어요. 프로필에서 거주 지역을 먼저 설정해 주세요.');
      return;
    }

    final payload = _editingPayload;

    setState(() => _isSavingAvailability = true);
    try {
      await _availabilityService.saveAvailability(
        uid: user.uid,
        // [E1-DATE] 전송 직전에 한 번 더 canonical 필터를 통과시킨다.
        //   수정 화면을 열어 둔 채 KST 자정이 지나면 고를 때는 유효했던
        //   날짜가 과거가 된다. 그대로 보내면 서버가 떨어내는데 화면은
        //   보낸 수를 저장했다고 말해 또 어긋난다.
        dates: payload,
        city: city,
        district: user.homeRegion?.district,
      );
      if (!mounted) return;
      // 서버가 실제로 받은 집합을 화면 상태로 삼는다 — 보낸 것과 저장된 것이
      //   다르면 다음 조회까지 화면이 거짓말을 한다.
      final saved = Set<String>.from(payload);
      setState(() {
        _availabilityDates = saved;
        _isEditMode = false;
        _editingDates = {};
        _isSavingAvailability = false;
      });
      ToastHelper.showSuccess('근무 가능일 ${saved.length}일을 저장했어요');
      _ensureMonthLoaded();
    } catch (e) {
      debugPrint('❌ 근무 가능일 저장 실패: $e');
      if (mounted) {
        setState(() => _isSavingAvailability = false);
        ToastHelper.showError('근무 가능일을 저장하지 못했어요. 다시 시도해 주세요.');
      }
    }
  }

  /// attendance 리스트 → Map 변환 (applicationId + 날짜 복합키)
  ///
  /// 키 포맷: '${applicationId}_${year}-${month}-${day}' (월·일 미패딩)
  /// 동일 applicationId + 날짜가 중복이면 나중 항목이 덮어쓰지만,
  /// docId = '${applicationId}_yyyyMMdd'이므로 Firestore에서 중복 방지됨.
  ///
  /// ⚠️ CalendarHelper.getActualWorkDays의 uniqueDates 키 포맷('year-month-day' 미패딩)과
  ///    스케줄 목록 조회 키 포맷이 이 포맷과 일치해야 함 — 변경 시 세 곳 동시 수정 필요.
  Map<String, AttendanceModel> _buildAttendanceMap(List<AttendanceModel> list) =>
      MyScheduleScreen.buildAttendanceMap(list);

  // ─── Build ───────────────────────────────────────────────────

  /// [DU311 A1] 머리 행동 글자(측정과 표시 공용).
  static const String _kAvailAction = '가능일 설정'; // [DU311 B3] 대상+행동(등록·수정 공용)

  /// [DU311 A1] 머리 높이 — 1.0 기준 kToolbarHeight(56)는 그대로 두고, 실제 사용자 배율의 제목(최대 두 줄)이 56 안에
  ///   들어가지 않으면 줄 높이 + 위아래 8 로 늘린다. 제목 폭은 화면 폭 − 가운데 간격 16×2 − (일반 모드) 행동 폭으로 보수적으로
  ///   잡는다(행동 폭 = 좌우 padding 12×2 + 아이콘 18 + 간격 8 + 같은 배율의 '가능일' 글자 폭). 글자를 줄이거나 자르지 않는다.
  double _titleBarHeight(BuildContext context, TextScaler scaler, String text, TextStyle style) {
    final theme = Theme.of(context);
    // AppBar 의 DefaultTextStyle(바탕 = appBarTheme.titleTextStyle ?? titleLarge) ← style ← boldText 와 같은 병합.
    var base = (theme.appBarTheme.titleTextStyle ?? theme.textTheme.titleLarge ?? const TextStyle()).merge(style);
    if (MediaQuery.boldTextOf(context)) {
      base = base.merge(const TextStyle(fontWeight: FontWeight.bold));
    }
    final width = MediaQuery.sizeOf(context).width;
    var reserve = 32.0;
    if (!_isEditMode) {
      final ap = TextPainter(
        text: TextSpan(text: _kAvailAction, style: theme.textTheme.labelLarge),
        textDirection: Directionality.of(context),
        textScaler: scaler,
        maxLines: 1,
      )..layout();
      reserve += 12 + 18 + 8 + 12 + ap.width;
      ap.dispose();
    }
    final tp = TextPainter(
      text: TextSpan(text: text, style: base),
      textDirection: Directionality.of(context),
      textScaler: scaler,
      locale: Localizations.maybeLocaleOf(context),
      textHeightBehavior: DefaultTextHeightBehavior.maybeOf(context),
      maxLines: 2,
    )..layout(maxWidth: (width - reserve).clamp(48.0, width));
    final need = tp.height + 16;
    tp.dispose();
    return need > kToolbarHeight ? need : kToolbarHeight;
  }

  /// [DU311 A3·A4] 누름 영역 — 보이는 모양·크기는 그대로 두고 receiver 만 최소 48×48(DU310 _chipReceiver 와 같은 방식).
  ///   [alignment] 로 보이는 요소 자리를 고정한다(배너 링크 = 위·오른쪽, 칩 = 가운데). 버튼·선택 의미는 이 노드가 말한다.
  Widget _tapReceiver({
    required Widget child,
    required VoidCallback onTap,
    bool? selected,
    Alignment alignment = Alignment.center,
  }) {
    return Semantics(
      container: true,
      button: true,
      selected: selected,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
          child: Align(alignment: alignment, widthFactor: 1, heightFactor: 1, child: child),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // [DU311 A1] AppBar 바깥의 실제 사용자 배율(AppBar 가 제목에 거는 1.34 상한 적용 전 — DU310 J13 과 같은 방식).
    //   큰 글자에서 제목이 1.34 에 묶이고 '가능일' 행동만 커져 위계가 뒤집히던 것을 바로잡는다.
    final titleScaler = MediaQuery.textScalerOf(context);
    // [DU311 B1] 하단 탭 이름('내 일정')과 같은 머리 제목.
    final titleText = _isEditMode ? '근무 가능일 선택' : '내 일정';
    final titleStyle = ResponsiveHelper.subtitleStyle(context)
        .copyWith(fontWeight: FontWeight.bold, color: AppColors.textPrimary);
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        toolbarHeight: _titleBarHeight(context, titleScaler, titleText, titleStyle),
        title: Text(
          titleText,
          style: titleStyle,
          // [DU311 A1] Text.textScaler 가 AppBar 의 MediaQuery 상한보다 우선한다. 두 줄까지 허용해 말줄임 0.
          textScaler: titleScaler,
          maxLines: 2,
          softWrap: true,
          overflow: TextOverflow.visible,
        ),
        centerTitle: false,
        // 에디트 모드가 아닐 때만 "근무 가능일 등록" CTA 표시
        actions: _isEditMode
            ? null
            : [
                TextButton.icon(
                  onPressed: _enterEditMode,
                  icon: const Icon(Icons.event_available_outlined, size: 18),
                  label: const Text(_kAvailAction),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.brand, // [DU311 B3] 머리 행동은 brand(info 계열 아님)
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                  ),
                ),
              ],
      ),
      // 에디트 모드 하단 sticky 바 (SafeArea(top: false) 필수)
      bottomNavigationBar: _isEditMode
          ? SafeArea(
              top: false,
              child: Container(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                // [DU437 · F113-1] 바 위 그림자 → 옅은 경계선(Standards 그림자 0 기본 · 공용 하단 바와 같은 grey200).
                decoration: const BoxDecoration(
                  color: Colors.white,
                  border: Border(top: BorderSide(color: AppColors.grey200)),
                ),
                // [DU442] B(320 · 2.0)에서 두 버튼 글자 크기가 달라(테마 Elevated · Outlined 기본) 저장 74 · 취소 68 로 높이가 어긋났다.
                //   같은 줄의 두 버튼을 더 큰 쪽 높이로 맞춘다(IntrinsicHeight + stretch). W 는 둘 다 최소 52 라 그대로다.
                child: IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _cancelEdit,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.textSecondary,
                            side: const BorderSide(color: AppColors.grey300),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            // [DU437 · F113-1] 최소 높이 52(주 행동과 같은 줄) · 반경 12(버튼 기준)
                            minimumSize: const Size(0, 52),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Text('취소'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: ElevatedButton(
                          onPressed: _isSavingAvailability ? null : _saveAvailability,
                          style: ElevatedButton.styleFrom(
                            // [DU434] 저장(주 행동) 채움 info(흰 글자 3.12) → brand(5.58) — 같은 화면 머리 행동과 같다([DU311 B3] info 계열 아님).
                            backgroundColor: AppColors.brand,
                            foregroundColor: Colors.white,
                            disabledBackgroundColor: AppColors.grey300,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            // [DU437 · F113-1] W 51 → 최소 52 · 반경 12 · 평면(그림자 0 · 공용 primaryButton 과 같다)
                            minimumSize: const Size(0, 52),
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: _isSavingAvailability
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : Text(
                                  // [E1-DATE] 버튼의 수는 **실제 저장될 수**다.
                                  //   선택 집합을 그대로 세면, 화면을 열어 둔
                                  //   채 자정이 지났을 때 서버가 떨어낼 날짜까지
                                  //   세어 저장되지 않을 수를 약속하게 된다.
                                  _editingPayload.isEmpty
                                      ? '저장 (삭제)'
                                      : '${_editingPayload.length}일 저장',
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            )
          : null,
      body: _isLoading
          ? const LoadingWidget(message: '일정을 불러오고 있어요')
          : _buildContent(),
    );
  }

  // ─── 컨텐츠 ─────────────────────────────────────────────────

  Widget _buildContent() {
    // 에디트 모드: 달력만 보이고 일정 목록 숨김
    if (_isEditMode) {
      return SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: _buildWhiteZone(),
      );
    }

    // SliverFillRemaining(hasScrollBody: false) 은 반드시 마지막 sliver이어야 한다.
    // 뒤에 SliverToBoxAdapter를 추가하면 그 높이만큼 스크롤이 발생한다.
    // 빈 상태(선택 날짜 있고 이벤트 없음)일 때 trailing 여백 sliver를 제외한다.
    // [DU213] 조회 미완결(조회 중·실패)이면 목록 자리는 상태 안내(SliverFillRemaining)다.
    final showEmptyState = !_monthComplete ||
        (_selectedDay != null && _selectedDayEvents.isEmpty);

    return RefreshIndicator(
      onRefresh: _refreshSchedule, // [PERF-L20] 달력 유지 + TTL 무효화
      color: Theme.of(context).primaryColor,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          // ── 흰 구역: 캘린더 + 범례 + 통계 (카드 없이 연결)
          SliverToBoxAdapter(child: _buildWhiteZone()),

          // ── 회색 구역: 필터 칩
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                ResponsiveHelper.spacing(context, 16),
                ResponsiveHelper.spacing(context, 12),
                ResponsiveHelper.spacing(context, 16),
                ResponsiveHelper.spacing(context, 4),
              ),
              child: _buildFilterChipsRow(),
            ),
          ),

          // 선택 날짜 헤더 — 일정이 있을 때만 표시
          // 일정이 없으면 헤더 없이 빈 상태 바로 시작 (헤더가 기대감을 유발하는 문제 방지)
          if (_monthComplete && _selectedDay != null && _selectedDayEvents.isNotEmpty)
            SliverToBoxAdapter(child: _buildDayHeader()),

          // 일정 리스트 or 빈 상태(SliverFillRemaining)
          _buildSliverScheduleList(),

          // 홈 인디케이터 + 하단 여백:
          // 빈 상태(SliverFillRemaining)가 마지막 sliver일 때는 추가하지 않는다.
          // → SafeArea bottom은 AppEmptyState 내부 Padding으로 처리됨
          if (!showEmptyState)
            SliverToBoxAdapter(
              child: SizedBox(
                height: MediaQuery.of(context).padding.bottom +
                    ResponsiveHelper.spacing(context, 16),
              ),
            ),
        ],
      ),
    );
  }

  /// 캘린더 + 범례 + 월 요약을 하나의 흰 배경 구역으로 통합
  Widget _buildWhiteZone() {
    return Container(
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 캘린더
          ScheduleCalendar(
            focusedDay: _focusedDay,
            selectedDay: _isEditMode ? null : _selectedDay,
            // [DU213] 조회가 완결된 달의 일정만 표식으로 그린다(조회 중·실패 달에 이전·미완결 표식 0).
            applications: _monthComplete ? _applications : const [],
            selectedFilter: _selectedFilter,
            dateIndex: _monthComplete ? _dateIndex : const {},
            // Phase 8.1A: 가능일 마커 + 에디트 모드 파라미터
            // [E1-DATE] 달력도 지금 유효한 날짜만 가능일로 강조한다.
            availabilityDates: _validAvailabilityDates,
            editingDates: _isEditMode ? _editingDates : null,
            isEditMode: _isEditMode,
            onDaySelected: (selectedDay, focusedDay) {
              if (_isEditMode) {
                // 에디트 모드: 날짜 tap = 선택/해제
                _toggleDate(selectedDay);
                setState(() => _focusedDay = focusedDay);
              } else {
                setState(() {
                  _selectedDay = selectedDay;
                  _focusedDay  = focusedDay;
                  _recomputeSelectedDayEvents(); // H1
                });
              }
            },
            onPageChanged: (focusedDay) {
              _monthGeneration++;
              if (_isEditMode) {
                // [impl_9 발견·수정 · 근본 원인] 세대를 올리면 진행 중이던 조회는 stale 로 빠지며 **자기가 켠 로딩을 끄지 않는다**.
                //   편집 중에는 새 조회를 시작하지 않으므로 그 로딩을 끌 주인이 없어 `_monthLoading` 이 true 로 남았고,
                //   편집을 끝낼 때 `_ensureMonthLoaded` 가 '조회 중'이라 보고 건너뛰어 목록이 '월 일정을 확인하고 있어요'에 갇혔다.
                //   규칙: 세대를 올리는 곳은 새 조회를 시작하거나(그 조회가 로딩을 끝낸다) 로딩 표지를 직접 내린다.
                setState(() {
                  _focusedDay = focusedDay;
                  _monthLoading = false;
                  _isLoading = false;
                });
                return;
              }
              setState(() => _focusedDay = focusedDay);
              _loadMonthlyAttendances(focusedDay);
            },
          ),

          // 범례 (에디트 모드에서는 간소화 표시)
          _buildLegendRow(),

          // 근무 가능일 배너 (에디트 모드가 아닐 때만 표시)
          if (!_isEditMode) _buildAvailabilityBanner(),

          // [SYSTEM-INTEGRATION-R2.3] 초대 받을 지역 — 근무 제안의 나머지 절반.
          //   가능일(언제)과 초대 지역(어디서)은 같은 질문의 두 축이라
          //   같은 자리에 둔다. 가입 필수 단계로 만들지 않는다(§9).
          if (!_isEditMode) _buildInviteRegionRow(),

          // 에디트 모드 안내 문구
          if (_isEditMode) _buildEditModeHint(),

          // 구분선
          const Divider(height: 1, thickness: 1, color: AppColors.grey100),

          // N월 요약 (2×2 KPI) — 에디트 모드에서는 숨김
          if (!_isEditMode) _buildMonthlySummary(),

          // [DU1 구현72 S073] 8px 회색 띠가 요약과 필터·선택일 목록을 토막냈다(구현69 홈·구현70 상세와 같은 결정 —
          //   한 흰 면 + 제목·간격으로 구분). 띠 대신 같은 높이 간격. 에디트 모드에서 없는 것은 그대로.
          if (!_isEditMode) const SizedBox(height: 8),
        ],
      ),
    );
  }

  /// [SYSTEM-INTEGRATION-R2.3] 초대 받을 지역 진입점.
  ///
  ///   상태를 그대로 말한다:
  ///     UNSET   설정하지 않음  — 안내 (§28 — 여기서만, 반복 압박 없음)
  ///     OFF     받지 않음
  ///     ON      선택한 지역 요약
  ///     UNKNOWN 확인하지 못함  — OFF로 표시하지 않는다
  Widget _buildInviteRegionRow() {
    final pref = _invitePref;
    final (label, color) = switch (pref?.state) {
      // [DU311 C8→Q3] 상태 값은 읽혀야 한다 — grey500(흰 바탕 약 2.68:1) 대신 textSecondary.
      null => ('불러오는 중…', AppColors.textSecondary),
      InvitePreferenceState.unknown => ('확인하지 못함', AppColors.textSecondary),
      InvitePreferenceState.unset => ('설정하기', AppColors.infoDark),
      InvitePreferenceState.off => ('받지 않음', AppColors.grey600),
      InvitePreferenceState.on => (
          pref!.regions.length <= 2
              ? pref.regions.map((r) => r.city).join(' · ')
              : '${pref.regions.first.city} 외 ${pref.regions.length - 1}곳',
          AppColors.infoDark,
        ),
    };

    // [DU311 A5] 행 전체가 누름 영역(최소 48). 물결이 보이도록 행 자체를 Material(흰 바탕 + 둥근 테두리)로 둔다 —
    //   Ink 는 Scaffold 의 ink 층(흰 구역 Container 아래)에 그려져 가려지므로 쓰지 않는다.
    //   상태 값은 최대 45% 폭에서 줄바꿈해 큰 글자·긴 지역명에서도 넘치지 않는다. 바깥 여백은 누름 영역 밖이다.
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 12),
        vertical: ResponsiveHelper.spacing(context, 2),
      ),
      child: Material(
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: const BorderSide(color: AppColors.borderLight),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () async {
            await Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => const InviteRegionSettingsScreen()),
            );
            if (mounted) _loadInvitePref();
          },
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: ResponsiveHelper.spacing(context, 12),
                vertical: ResponsiveHelper.spacing(context, 10),
              ),
              child: Row(
                children: [
                  const Icon(Icons.place_outlined, size: 16, color: AppColors.grey600),
                  SizedBox(width: ResponsiveHelper.spacing(context, 6)),
                  // [DU311 r7 자체검토] 2.0/320 에서 라벨 `초대 받 / 을 지역`·값 `강남구 · 송 / 파구` 처럼 낱말 가운데서 끊겼다 —
                  //   라벨은 낱말 사이에서만(keepWords), 값은 ` · ` 구분점에서만(phrases) 줄을 바꾼다. 의미 이름은 원문.
                  Expanded(
                    child: Text(
                      TextLayout.keepWords('초대 받을 지역'),
                      semanticsLabel: '초대 받을 지역',
                      style: ResponsiveHelper.smallStyle(context)
                          .copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
                  ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.45),
                    child: Text(
                      TextLayout.phrases(label),
                      semanticsLabel: label,
                      textAlign: TextAlign.end,
                      style: ResponsiveHelper.smallStyle(context, color: color)
                          .copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
                  const Icon(Icons.chevron_right, size: 16, color: AppColors.grey400),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _loadInvitePref() async {
    final uid =
        Provider.of<UserProvider>(context, listen: false).currentUser?.uid;
    if (uid == null) return;
    final pref = await _reads.invitePreference(uid);
    if (!mounted) return;
    setState(() => _invitePref = pref);
  }

  /// 근무 가능일 배너 — 평상시에 가능일 현황 표시
  ///
  /// count == 0 : 가능일 미등록 → 근무 제안 안내 타일 표시
  /// count > 0  : 등록된 일 수 표시 + 근무 제안 설명 부제목
  Widget _buildAvailabilityBanner() {
    // [E1-AVAIL] 읽기 전·읽기 실패를 0 일로 말하지 않는다.
    //   아래 등록 유도 타일은 **등록이 없다는 사실을 확인했을 때만** 쓴다.
    if (_availLoad == _AvailLoad.loading) {
      return _availabilityNotice(
        '근무 가능일을 확인하고 있어요',
        icon: Icons.hourglass_empty_rounded,
      );
    }
    if (_availLoad == _AvailLoad.failed) {
      return _availabilityNotice(
        '등록한 근무 가능일을 불러오지 못했어요',
        icon: Icons.error_outline_rounded,
        isError: true,
        onRetry: _loadAvailability,
      );
    }

    final count = _validAvailabilityDates.length;

    // [R7-P2-3] 가능일만으로는 제안이 오지 않는다.
    //
    //   서버가 초대를 허용하는 조건은 세 가지다(`callableInviteWorker`):
    //     ① 그 날짜가 `dates` 에 있다        ← 이 화면의 가능일
    //     ② `inviteEnabled == true`          ← 아래 '초대 받을 지역'
    //     ③ 사업장 근무지역이 `inviteRegionKeys` 에 있다  ← 같은 곳
    //   ②③ 가 없으면 `callableSetAvailability` 가 `inviteKeys` 를 **빈 배열**로
    //   만들어, 관리자 후보 조회에 아예 잡히지 않는다.
    //
    //   그런데 이 배너는 등록을 마친 사람에게도 "제안을 받을 수 있어요"라고
    //   조건 없이 말했다 — **하지 않은 설정을 한 것처럼 확인해 주는 문구**다.
    //   그래서 나머지 절반의 상태를 함께 본다. 모르면 모른다고 말한다.
    // [R7-P2-3 후속 정정] 앞 단계에서 OFF/UNSET 을 "제안이 오지 않아요"로만
    //   말했는데, 그러면 **저장한 날짜가 아무 일도 안 한다**고 읽힌다.
    //   실제로는 `_dispatchToMatchNotifications` 가 초대 설정과 무관하게
    //   `dates` + 거주 도시로 공고 알림을 보낸다(active consumer, 호출부 4곳).
    //   날짜를 지우면 그 알림까지 잃는다 — 두 효과를 갈라서 말한다.
    final inviteState = _invitePref?.state;
    const kMatchAlert = '등록한 날 내 지역에 새 공고가 열리면 알림을 받아요.';
    final String descText;
    if (count == 0) {
      // 아직 등록 전 — 두 이득을 함께 말한다(약속이 아니라 안내다).
      descText = '가능일을 등록하면 그 날 새 공고 알림을 받고, '
          '\'초대 받을 지역\'까지 설정하면 사업장의 근무 제안도 받을 수 있어요.';
    } else {
      descText = switch (inviteState) {
        InvitePreferenceState.on =>
          '$kMatchAlert 조건이 맞는 사업장이 먼저 제안할 수도 있어요.',
        InvitePreferenceState.unset =>
          '$kMatchAlert 사업장이 먼저 제안하게 하려면 아래 \'초대 받을 지역\'을 설정하세요.',
        InvitePreferenceState.off =>
          '$kMatchAlert 지금은 초대를 받지 않도록 설정돼 있어 사업장의 제안은 오지 않아요.',
        _ => '$kMatchAlert 초대 설정은 확인하지 못했어요.',
      };
    }

    if (count == 0) {
      // 미등록 상태 — 등록 유도 타일
      return Container(
        margin: EdgeInsets.symmetric(
          horizontal: ResponsiveHelper.spacing(context, 12),
          vertical: ResponsiveHelper.spacing(context, 6),
        ),
        padding: EdgeInsets.symmetric(
          horizontal: ResponsiveHelper.spacing(context, 12),
          vertical: ResponsiveHelper.spacing(context, 8),
        ),
        decoration: BoxDecoration(
          color: AppColors.grey100,
          borderRadius: BorderRadius.circular(8),
        ),
        // [SCALE-BALANCE.34] 큰 글자에서 안내가 5줄이 되면 아이콘·'등록'이 세로 가운데에 떴다 — 첫 줄에 맞춘다.
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: EdgeInsets.only(top: ((MediaQuery.textScalerOf(context).scale(13) * 1.4 - 16) / 2).clamp(0.0, 30.0)),
              child: const Icon(Icons.info_outline, size: 16, color: AppColors.textSecondary),
            ),
            SizedBox(width: ResponsiveHelper.spacing(context, 6)),
            Expanded(
              // [DU311 B5] '근무 제/안도' 처럼 낱말 가운데서 끊기지 않게 낱말 단위로 줄바꿈. 읽기는 원문.
              child: Text(
                TextLayout.keepWords(descText),
                semanticsLabel: descText,
                style: ResponsiveHelper.smallStyle(
                    context, color: AppColors.textPrimary),
              ),
            ),
            SizedBox(width: ResponsiveHelper.spacing(context, 6)),
            // [DU311 A3] 보이는 '등록' 은 그대로, 누름 영역만 최소 48×48 + 버튼 의미(글자는 첫 줄 위·오른쪽 끝 그대로).
            _tapReceiver(
              alignment: Alignment.topRight,
              onTap: _enterEditMode,
              child: Text(
                '등록',
                style: ResponsiveHelper.smallStyle(
                  context,
                  color: AppColors.brand,
                ).copyWith(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      );
    }

    // 등록 상태 — 현황 + 부제목
    return Container(
      margin: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 12),
        vertical: ResponsiveHelper.spacing(context, 6),
      ),
      padding: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 12),
        vertical: ResponsiveHelper.spacing(context, 8),
      ),
      decoration: BoxDecoration(
        color: AppColors.grey100,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.event_available_outlined,
              size: 16, color: AppColors.textSecondary),
          SizedBox(width: ResponsiveHelper.spacing(context, 6)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  // [E1-AVAIL] 다시 읽는 중이면 지금 숫자가 방금 확인한
                  //   값이라고 말하지 않는다(stale ≠ 최신).
                  _availRefreshing
                      ? '근무 가능일 $count일 등록됨 · 확인 중'
                      : '근무 가능일 $count일 등록됨',
                  // [DU311 A2] '..copyWith' 는 결과를 버려 w600 이 적용되지 않았다 → '.copyWith'.
                  style: ResponsiveHelper.smallStyle(
                      context, color: AppColors.textPrimary)
                    .copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                // [DU311 B5] 낱말 단위 줄바꿈, 읽기는 원문.
                Text(
                  TextLayout.keepWords(descText),
                  semanticsLabel: descText,
                  style: ResponsiveHelper.tinyStyle(
                      context, color: AppColors.textPrimary),
                ),
              ],
            ),
          ),
          SizedBox(width: ResponsiveHelper.spacing(context, 6)),
          // [DU311 A3] 보이는 '수정' 은 그대로, 누름 영역만 최소 48×48 + 버튼 의미(글자는 위·오른쪽 끝 그대로).
          _tapReceiver(
            alignment: Alignment.topRight,
            onTap: _enterEditMode,
            child: Text(
              '수정',
              style: ResponsiveHelper.smallStyle(
                context,
                color: AppColors.brand,
              ).copyWith(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  /// 에디트 모드 안내 문구
  Widget _buildEditModeHint() {
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 12),
        vertical: ResponsiveHelper.spacing(context, 6),
      ),
      // [R7-P2-3 후속] 첫 날짜를 고르기 **전** 에 왜 고르는지 말한다.
      //
      //   저장된 날짜에는 **두 개의 서로 다른 효과**가 있다(CF 실측):
      //     · `_dispatchToMatchNotifications` — 내 지역에 그 날 공고가 열리면
      //       알림. **초대 설정과 무관하게** 동작한다.
      //     · `callableGetAvailableWorkers`/`callableInviteWorker` — 사업장이
      //       먼저 제안. 이쪽은 초대 ON + 초대 받을 지역이 **함께** 있어야 한다.
      //   그리고 어느 쪽도 근무 확정이 아니다 — 제안은 수락해야 성립한다.
      //   저장한 뒤 배너로 뒤늦게 정정하지 않고 여기서 먼저 말한다.
      child: Column(
        children: [
          Text(
            '등록한 날 내 지역에 새 공고가 열리면 알림을 받아요.\n'
            "사업장이 먼저 제안하게 하려면 '초대 받을 지역'도 설정하세요.",
            style: ResponsiveHelper.tinyStyle(context, color: AppColors.grey600),
            textAlign: TextAlign.center,
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 4)),
          Text(
            '제안을 수락해야 근무가 확정돼요 · 최대 60일, 오늘~90일 이내',
            // [DU463] grey500(2.68) → grey600 — 바로 위 첫 줄 · 같은 화면 작은 중립 글자와 같은 짝(4.61).
            style: ResponsiveHelper.tinyStyle(context, color: AppColors.grey600),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  // ─── 캘린더 ─────────────────────────────────────────────────

  // ─── 범례 (풀너비, 카드 없음) ──────────────────────────────────

  Widget _buildLegendRow() {
    final primaryColor = Theme.of(context).primaryColor;
    // 에디트 모드: 파란 원(선택) 안내만 표시
    if (_isEditMode) {
      return Padding(
        padding: EdgeInsets.symmetric(
          horizontal: ResponsiveHelper.spacing(context, 12),
          vertical: ResponsiveHelper.spacing(context, 8),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                color: primaryColor,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              '선택됨',
              style: ResponsiveHelper.tinyStyle(context, color: AppColors.grey600),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 12),
        vertical: ResponsiveHelper.spacing(context, 10),
      ),
      // [R7-P2-3] 범례 다섯 항목이 한 줄 고정이라 배율 2.0 에서 넘쳤다
      //   (320dp 41px · 360dp 4.1px). 어느 표시가 무슨 뜻인지 알려 주는
      //   줄이라 항목을 지우지 않고 줄바꿈을 허용한다.
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: ResponsiveHelper.spacing(context, 10),
        runSpacing: ResponsiveHelper.spacing(context, 6),
        children: [
          // [DU1 구현100 셀B] 달력 단기 확정 점과 같은 successDark(홈과 같은 '확정' 색)
          _legendDot(AppColors.successDark, '확정', star: false),
          // [DU1 후속102 C102-1] 달력 장기 근무 별과 같은 색 #946200(흰 5.24)
          _legendDot(AppColors.warningDark, '장기', star: true),
          // [DU1 후속101 C101-3] 달력 셀과 같은 색: 대기 #E65100(흰 3.79) · 휴무 #757575(흰 4.61)
          _legendDot(AppColors.warningDarkest, '대기', star: false),
          _legendDot(AppColors.grey600, '휴무', star: true),
          // [E1-AVAIL] 가능일은 점이 아니라 **날짜 테두리**다 — 범례도 셀과
          //   같은 형태로 보여야 서로를 가리킨다는 것이 읽힌다.
          //   `가능` 한 글자는 무엇이 가능한지 모호해 이름을 그대로 쓴다.
          _legendOutline('근무 가능일'),
        ],
      ),
    );
  }

  /// [E1-AVAIL] 캘린더 셀의 가능일 윤곽선과 **같은 모양**의 범례 항목.
  Widget _legendOutline(String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.info, width: 1.5),
          ),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: ResponsiveHelper.tinyStyle(context, color: AppColors.grey600),
        ),
      ],
    );
  }

  Widget _legendDot(Color color, String label, {required bool star}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        star
            ? Icon(Icons.star, size: 10, color: color)
            : Container(
                // [DU311 A8] 달력 표식 점(schedule_calendar _dot 7×7)과 같은 크기.
                width: 7,
                height: 7,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
        const SizedBox(width: 4),
        Text(
          label,
          style: ResponsiveHelper.tinyStyle(context, color: AppColors.grey600),
        ),
      ],
    );
  }

  // ─── N월 요약 (2×2 KPI 그리드) ─────────────────────────────────

  Widget _buildMonthlySummary() {
    final month = _focusedDay.month;
    final primaryColor = Theme.of(context).primaryColor;
    // [DU213 C17·C18] 표시월의 일정+월근태가 모두 성공했을 때만 숫자를 말한다.
    //   조회 중은 '확인 중', 실패는 '확인하지 못함'(단위 없음·중립 글자색). 산식은 그대로다.
    final String? unknown = _monthComplete
        ? null
        : (_loadError != null || _attError != null)
            ? '확인하지 못함'
            : '확인 중';
    const unknownColor = AppColors.textSecondary;
    // 값이 0이면 비활성(textTertiary), 값이 있으면 semantic 색상 활성화
    final confirmedWorkColor = _cachedConfirmedCount > 0
        ? AppColors.textPrimary
        : AppColors.textTertiary;
    final actualDaysColor = _cachedActualDays > 0
        ? AppColors.textPrimary
        : AppColors.textTertiary;
    final incomeColor = _cachedTotalIncome > 0 ? primaryColor : AppColors.textTertiary;
    final confirmedIncomeColor = _cachedConfirmedIncome > 0
        ? AppColors.successDark // [DU311 A6] 비토큰 #2E9D45 → 확정 표식과 같은 토큰
        : AppColors.textTertiary;

    return Padding(
      padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // [DU311 B6] 섹션 제목 위계(ConceptText.section 20/w700) — 홈 '오늘의 약속'과 같은 단계.
          Text(
            '$month월 요약',
            style: ConceptText.section(),
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 14)),
          Row(
            children: [
              Expanded(
                // [DEVICE-MISMATCH-FIX] 세는 단위는 지원서(근무 건)다 — 같은 날
                //   두 근무면 2건이다(DEV 실측: 5개 날짜에 6건인데 `6일`).
                child: _kpiItem('확정 근무', unknown ?? '$_cachedConfirmedCount건',
                    unknown != null ? unknownColor : confirmedWorkColor),
              ),
              Expanded(
                child: _kpiItem('실근무', unknown ?? '$_cachedActualDays일',
                    unknown != null ? unknownColor : actualDaysColor),
              ),
            ],
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 12)),
          // [DU217 B] 큰 글자에서 두 수입 값이 간격 없이 붙어 읽히지 않게 한다.
          //   두 값이 각 칸에 최소 간격(spacing 12)을 두고 한 줄로 들어갈 때만 기존 2열을 그대로 쓰고,
          //   아니면 수입 두 항목만 세로로 쌓는다. 글자 축소·말줄임·단위 제거는 하지 않는다.
          LayoutBuilder(
            builder: (context, constraints) {
              // [AUD-3 M3 · 판정296] 계산할 수 없는 근무가 있으면 부분합·0원을 전체처럼 말하지 않는다.
              final expected = unknown ??
                  // [AUD-4 H3] 지원서를 200 건 상한까지만 읽었으면 일부가 빠졌을 수 있다 — 같은 부분합 표기.
                  ((_cachedIncomeUnknown > 0 || _applications.length >= 200)
                      ? ExpectedWageText.partialTotal(
                          _cachedTotalIncome, _cachedIncomeUnknown + (_applications.length >= 200 ? 1 : 0))
                      : '${_fmt.format(_cachedTotalIncome)}원');
              final confirmed = unknown ?? '${_fmt.format(_cachedConfirmedIncome)}원';
              final expectedItem = _kpiItem(
                '예상수입',
                expected,
                unknown != null ? unknownColor : incomeColor,
              );
              final confirmedItem = _kpiItem(
                '확정수입',
                confirmed,
                unknown != null ? unknownColor : confirmedIncomeColor,
              );
              final valueStyle = DefaultTextStyle.of(context).style.merge(
                  ResponsiveHelper.subtitleStyle(context).copyWith(fontWeight: FontWeight.bold));
              final scaler = MediaQuery.textScalerOf(context);
              final direction = Directionality.of(context);
              double widthOf(String s) {
                final tp = TextPainter(
                  text: TextSpan(text: s, style: valueStyle),
                  textDirection: direction,
                  textScaler: scaler,
                  maxLines: 1,
                )..layout();
                final w = tp.width;
                tp.dispose();
                return w;
              }

              final half = constraints.maxWidth / 2;
              final gap = ResponsiveHelper.spacing(context, 12);
              final fits = widthOf(expected) + gap <= half && widthOf(confirmed) <= half;
              if (fits) {
                return Row(
                  children: [
                    Expanded(child: expectedItem),
                    Expanded(child: confirmedItem),
                  ],
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  expectedItem,
                  SizedBox(height: ResponsiveHelper.spacing(context, 12)),
                  confirmedItem,
                ],
              );
            },
          ),
          // [AUD-3 M3] 계산할 수 없는 근무는 예상수입에 0 으로 넣지 않고 건수로 말한다.
          if (unknown == null && _cachedIncomeUnknown > 0) ...[
            SizedBox(height: ResponsiveHelper.spacing(context, 6)),
            Text(
              TextLayout.keepWords('금액 확인 필요 $_cachedIncomeUnknown건 · 예상수입에 넣지 않았어요'),
              semanticsLabel: '금액 확인 필요 $_cachedIncomeUnknown건 · 예상수입에 넣지 않았어요',
              style: ResponsiveHelper.tinyStyle(context, color: AppColors.textSecondary),
            ),
          ],
        ],
      ),
    );
  }

  Widget _kpiItem(String label, String value, Color valueColor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: ResponsiveHelper.tinyStyle(context, color: AppColors.grey600),
        ),
        SizedBox(height: ResponsiveHelper.spacing(context, 3)),
        Text(
          value,
          style: ResponsiveHelper.subtitleStyle(context)
              .copyWith(fontWeight: FontWeight.bold, color: valueColor),
        ),
      ],
    );
  }

  // H2: build()마다 _attendanceMap 재순회 방지 — _recomputeStats()에서 갱신
  List<AttendanceModel> get _confirmedWageRecords => _cachedConfirmedWageRecords;

  // [임금명세서 UI 제거 — 향후 수입 현황/급여 상세 화면에서 재활용 예정]
  // ignore: unused_field
  bool _isGeneratingPayslip = false;

  // ignore: unused_element
  Future<void> _generateMonthlyPayslip() async {
    final records = _confirmedWageRecords;
    if (records.isEmpty) {
      ToastHelper.showWarning('이번 달 확정된 급여 내역이 없습니다');
      return;
    }
    final uid = context.read<UserProvider>().currentUser;
    if (uid == null) {
      ToastHelper.showWarning('로그인이 필요합니다');
      return;
    }

    setState(() => _isGeneratingPayslip = true);
    try {
      final data = AggregatedPayslipData.fromRecords(
        records: records,
        workerName: uid.name,
        issueType: PayslipIssueType.monthly,
        year: _focusedDay.year,
        month: _focusedDay.month,
        periodStart: DateTime(_focusedDay.year, _focusedDay.month, 1),
        periodEnd: DateTime(_focusedDay.year, _focusedDay.month + 1, 0),
        workerBirthDate: uid.birthDate != null
            ? FormatHelper.formatDateDot(uid.birthDate!)
            : '',
      );
      final bytes = await PayslipPdfBuilder.buildAggregated(data);
      // [R7-PRE1A.1] 파일명은 받는 사람 쪽에서 겹치면 하나가 덮인다.
      //   근로자 본인 파일이라 동명이인 문제는 없지만, 두 사업장에서 같은 달
      //   명세서를 받으면 이름이 같아진다 — 사업장으로 가른다.
      //   이름·사업장명은 사용자 입력이라 파일명 금지문자를 걸러 낸다.
      final bizPart = records.isNotEmpty && records.first.businessName.isNotEmpty
          ? '${PersonLabel.safeFileName(records.first.businessName)}_'
          : '';
      final filename = '$bizPart${PersonLabel.safeFileName(uid.name)}_'
          '${_focusedDay.year}년${_focusedDay.month}월_임금명세서.pdf';
      if (!mounted) return;
      await Printing.sharePdf(bytes: bytes, filename: filename);
    } catch (e) {
      if (mounted) ToastHelper.showError('임금명세서 생성에 실패했습니다');
    } finally {
      if (mounted) setState(() => _isGeneratingPayslip = false);
    }
  }

  // ─── 필터 칩 (노출형) ────────────────────────────────────────

  // ─── 필터 칩 ─────────────────────────────────────────────────

  Widget _buildFilterChipsRow() {
    final theme = Theme.of(context);
    const bgSurface = AppColors.grey100;
    final filters = [
      ('ALL', '전체'),
      (AppStatus.confirmed, '확정'),
      (AppStatus.pending, '대기'),
    ];
    return Row(
      children: filters.map((f) {
        final (value, label) = f;
        final selected = _selectedFilter == value;
        return Padding(
          padding: EdgeInsets.only(right: ResponsiveHelper.spacing(context, 8)),
          // [DU311 A4] 보이는 칩은 그대로, 누름 영역만 최소 48×48 + 버튼·선택 의미.
          child: _tapReceiver(
            selected: selected,
            onTap: () => setState(() {
              _selectedFilter = value;
              _recomputeStats();
            }),
            child: Container(
              padding: EdgeInsets.symmetric(
                horizontal: ResponsiveHelper.spacing(context, 14),
                vertical: ResponsiveHelper.spacing(context, 7),
              ),
              decoration: BoxDecoration(
                color: selected ? theme.primaryColor : bgSurface,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                label,
                style: ResponsiveHelper.smallStyle(
                  context,
                  color: selected ? Colors.white : AppColors.grey600,
                ).copyWith(
                  fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  // ─── 날짜 헤더 ───────────────────────────────────────────────

  Widget _buildDayHeader() {
    return Container(
      margin: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 16),
        vertical: ResponsiveHelper.spacing(context, 4),
      ),
      padding: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 12),
        vertical: ResponsiveHelper.spacing(context, 10),
      ),
      decoration: BoxDecoration(
        color: AppColors.grey100,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(
            Icons.calendar_today_outlined,
            color: AppColors.grey600,
            size: ResponsiveHelper.iconSize(context, 16),
          ),
          SizedBox(width: ResponsiveHelper.spacing(context, 8)),
          Text(
            FormatHelper.formatDateKorean(_selectedDay!),
            style: ResponsiveHelper.bodyStyle(context, color: AppColors.textSecondary)
                .copyWith(fontWeight: FontWeight.w600),
          ),
          const Spacer(),
          _buildDayEventCount(),
        ],
      ),
    );
  }

  Widget _buildDayEventCount() {
    // H1: 캐시된 _selectedDayEvents 사용 — getEventsForDayFromIndex 중복 호출 제거
    if (_selectedDayEvents.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: Theme.of(context).primaryColor.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        '${_selectedDayEvents.length}건',
        style: ResponsiveHelper.tinyStyle(
          context,
          // [DU1 구현125 C124-1] brand 글자는 이 알약 바탕(brand 15% · 날짜 칩 #F5F6F8 위 = #D9DEF6)에서 4.18:1 —
          //   작은 글 4.5 미만(구현124 관측). 같은 brand 계열의 진한 토큰으로 글자만 바꾼다(5.73:1). 바탕·크기는 그대로.
          color: AppColors.brandDark,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  // ─── 일정 리스트 ─────────────────────────────────────────────

  Widget _buildSliverScheduleList() {
    // [DU213 C19] 조회 상태(실패·조회 중)가 선택일·이벤트 유무보다 먼저다 — 이전 카드가 오류를 가리지 않는다.
    if (!_monthComplete) return _buildEmptyState();
    if (_selectedDay == null) return const SliverToBoxAdapter(child: SizedBox.shrink());
    // H1: 캐시된 _selectedDayEvents 사용 — 중복 조회·정렬 제거
    if (_selectedDayEvents.isEmpty) return _buildEmptyState();

    return SliverPadding(
      padding: EdgeInsets.fromLTRB(
        ResponsiveHelper.spacing(context, 16),
        ResponsiveHelper.spacing(context, 4),
        ResponsiveHelper.spacing(context, 16),
        ResponsiveHelper.spacing(context, 4), // 하단은 마지막 SliverToBoxAdapter에서 일괄 처리
      ),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            final app = _selectedDayEvents[index];
            final key =
                '${app.id}_${_selectedDay!.year}-${_selectedDay!.month}-${_selectedDay!.day}';
            final attendance = _attendanceMap[key];
            return RepaintBoundary( // L1: 카드별 GPU 재래스터 방지
              child: ScheduleCard(
                application: app,
                attendance: attendance,
                onChanged: _refreshSchedule, // [PERF-L20] 카드 변경 뒤에도 달력 유지
                selectedDay: _selectedDay,
              ),
            );
          },
          childCount: _selectedDayEvents.length,
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    // [R5-ERROR-PARTIAL-R0.1 §20] 조회 실패를 "일정 없음"으로 말하지 않는다.
    //   예전에는 catch에서 로딩만 끄고 토스트를 띄웠다. 목록이 빈 채로
    //   남으니 화면은 '오늘 일정이 없어요'를 띄웠고, 토스트가 사라진 뒤엔
    //   근로자가 자기 근무를 없는 것으로 알게 된다.
    if (_loadError != null) {
      return AppEmptyState(
        icon: Icons.cloud_off_outlined,
        iconColor: AppColors.grey500,
        title: '일정을 불러오지 못했어요',
        subtitle: '일정이 없다는 뜻은 아니에요. 잠시 후 다시 시도해 주세요.',
        action: TextButton.icon(
          onPressed: _isLoading ? null : _loadApplications,
          icon: const Icon(Icons.refresh, size: 18),
          label: const Text('다시 시도'),
        ),
        asSliver: true,
      );
    }
    // [DU213 C18] 월근태 실패 — toast 가 사라져도 남는 안내와 다시 시도(현재 표시월 두 read 재조회).
    if (_attError != null) {
      return AppEmptyState(
        icon: Icons.cloud_off_outlined,
        iconColor: AppColors.grey500,
        title: '출근 기록을 불러오지 못했어요',
        subtitle: '월 요약을 확인할 수 없어요. 잠시 후 다시 시도해 주세요.',
        action: TextButton.icon(
          onPressed:
              _monthLoading ? null : () => _loadMonthlyAttendances(_focusedDay),
          icon: const Icon(Icons.refresh, size: 18),
          label: const Text('다시 시도'),
        ),
        asSliver: true,
      );
    }
    // [DU213 C17] 조회 중(또는 아직 읽지 않은 달) — 이전 월 목록을 보이지 않는다.
    if (!_monthComplete) {
      return AppEmptyState(
        icon: Icons.hourglass_empty_rounded,
        iconColor: AppColors.grey300,
        title: '월 일정을 확인하고 있어요',
        asSliver: true,
      );
    }
    final isFiltered = _selectedFilter != 'ALL';
    final sel = _selectedDay!;
    final dateLabel = '${sel.month}월 ${sel.day}일';

    // 필터 ON — "전체 보기" 텍스트 링크만 제공 (CTA 버튼 불필요)
    // SliverFillRemaining(hasScrollBody: false) → 필터+헤더 아래 남은 영역을 정확히 채워
    // 스크롤 오버플로 없이 콘텐츠를 수직 중앙 정렬
    if (isFiltered) {
      final filterLabel = _selectedFilter == AppStatus.confirmed ? '확정' : '대기';
      return AppEmptyState(
        icon: Icons.filter_list_off,
        iconColor: AppColors.grey300,
        title: "'$filterLabel' 일정이 없어요",
        subtitle: '다른 필터를 선택하거나 전체 보기를 눌러보세요',
        action: TextButton(
          onPressed: () => setState(() {
            _selectedFilter = 'ALL';
            _recomputeStats();
          }),
          child: const Text('전체 보기'),
        ),
        asSliver: true,
      );
    }

    // 필터 OFF — 날짜 포함 제목, 캘린더 유도 문구, CTA 버튼 없음
    // 사용자는 위 캘린더에서 다른 날짜를 선택하면 되고,
    // 일자리는 하단 탭에서 접근 가능 — 빈 상태에서 구직 행동 강요 불필요
    return AppEmptyState(
      icon: Icons.calendar_today_outlined,
      iconColor: AppColors.grey300,
      title: '$dateLabel 일정이 없어요',
      subtitle: '다른 날짜를 선택해 확인해보세요',
      asSliver: true,
    );
  }

  int _statusOrder(String status) {
    switch (status) {
      case AppStatus.confirmed:
      case AppStatus.contractPending:
        return 1;
      case AppStatus.pending:
        return 2;
      case AppStatus.rejected:
        return 3;
      case AppStatus.canceled:
        return 4;
      case AppStatus.autoCanceled:
        return 5;
      default:
        return 6;
    }
  }
}

/// [E1-AVAIL] 근무 가능일을 **읽었는가**. 초대 지역의
///   `InvitePreferenceState` 와 같은 자다 — ERROR 를 0 으로 번역하지 않는다.
enum _AvailLoad {
  /// 아직 읽지 않았다. 0 일이 아니다.
  loading,

  /// 읽었다. `_availabilityDates` 가 사실이다(0 일도 사실이다).
  ok,

  /// 읽지 못했다. 등록 여부를 말할 수 없다.
  failed,
}

/// [DU213] 월 조회 read 실패 표식 — 두 read 를 함께 기다리며 실패를 각각 붙잡는다.
class _ReadFail {
  const _ReadFail(this.error);
  final Object error;
}
