// lib/screens/business_admin/dialogs/attendance_status_dialog.dart
// 당일명단 다이얼로그 - 출퇴근 관리 기능 포함
// 
// 주요 기능:
// - 사업장별 확정 인원 조회
// - 업무별 그룹화 + 성별/나이순 정렬
// - 전체/개별 체크박스 선택
// - 일괄/개별 출근/퇴근 시간 입력
// - 노쇼 처리 및 해제
// - 지각 자동 감지
// - (추후) 명단 출력

import 'dart:async' show unawaited;
import 'dart:typed_data';
import 'package:flutter/material.dart';
// [DU305] 선택 직후 맞춤의 최소 이동 계산(getOffsetToReveal) — material/widgets 는 이 이름을 다시 내보내지 않는다.
import 'package:flutter/rendering.dart' show RenderAbstractViewport;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:intl/intl.dart';
import '../../../providers/user_provider.dart';
// Models
import '../../../models/core/application_model.dart';
import '../../../models/core/attendance_model.dart';
import '../../../models/core/business_model.dart';
import '../../../models/core/user_model.dart';
import '../../../models/core/business_work_type_model.dart';

// Services
import '../../../services/firestore_service.dart';

// Utils
import '../../../utils/person_label.dart';
import '../../../utils/toast_helper.dart';
import '../../../utils/text_layout.dart';
import '../../../utils/responsive_helper.dart';
import '../../../utils/dialog_helper.dart';
import '../../../utils/format_helper.dart';
import '../../../utils/attendance_badge_helper.dart';
import '../../../utils/attendance_status_helper.dart';
import '../../../utils/attendance_review_helper.dart';
import '../../../utils/work_detail_helper.dart';
import '../../../theme/app_colors.dart';
import '../../../widgets/common/app_checkbox.dart';
import '../../../widgets/common/app_tab_label.dart';

// Widgets
import '../../../widgets/common/app_empty_state.dart';
import '../../../widgets/common/loading_widget.dart';
import '../../../widgets/dialogs/worker_detail_dialog.dart';
import '../../../widgets/work_type_icon.dart';
import '../../../widgets/pickers/time_picker_bottom_sheet.dart';
import '../../../widgets/pickers/attendance_quick_time_sheet.dart';

// PDF
import '../../../utils/attendance_list_pdf.dart';
import '../../../utils/attendance_rounding_helper.dart';
// Dialogs
import 'wage_confirm_dialog.dart';
import '../../../widgets/dialogs/styled_dialog.dart';
import '../../../widgets/app_select_field.dart';
// [R5.2] NO_SHOW 대체 인력 충원 recovery dialog
import 'day_applicants_dialog.dart';
// [ISG2-REFRESH] 좌석 반납 후 연 지원자 명단에서의 변경도 다른 화면에 알린다.
import '../../../controllers/workforce_controller.dart';
import 'attendance_reads.dart';
// [REISSUE-RECOVERY] 계약 상태 조회 결과(모름/없음 구별) 타입.
import '../../../services/contract_service.dart';
import '../../../utils/action_guard.dart';
import '../../../utils/server_reject_codes.dart';

/// [ROUNDING-PREVIEW.27] 근태 기준 적용 확인 창의 한 줄 — 근로자 · 근무 시간대 · 입력 시각 · 적용 시 시각.
///   같은 사람이 같은 날 두 근무를 하면 이름만으로는 줄이 갈리지 않아 시간대를 함께 둔다.
typedef RoundingPreviewRow = ({String name, String shift, String raw, String applied});

/// 당일명단 다이얼로그 - 출퇴근 관리 기능 포함
class AttendanceStatusDialog extends StatefulWidget {
  /// [CONTRACT-DISPATCH-B2-APP] 서버가 출근 기록이 없어 건너뛴 행(notCheckedIn)을 결과 문구에 붙인다.
  @visibleForTesting
  static String checkoutFailureNote(Object? data) {
    final failures = data is Map ? data['failures'] : null;
    if (failures is! List) return '';
    final n = failures.where((f) => f is Map && f['reason'] == 'notCheckedIn').length;
    return n > 0 ? '\n출근 기록이 없어 건너뛴 근무 $n건' : '';
  }

  final DateTime date;
  final List<String> businessIds;
  final String? initialBusinessId;
  final List<BusinessModel>? businesses;
  /// [5B.2A] focused individual mode — WorkerRow에서 진입 시 해당 ApplicationModel.id를 전달.
  /// null이면 기존 batch mode. userId가 아닌 applicationId 기준 (동일 uid 복수 application 대응).
  final String? initialApplicationId;

  /// [R7-P1-3 P13-R] 바깥에서 읽어오는 것들의 경계. 주지 않으면 기존 구현이다.
  ///   분류·병합·그룹·수치는 이 화면이 그대로 한다 — 여기로 옮기지 않는다.
  final AttendanceReads? reads;

  const AttendanceStatusDialog({
    super.key,
    required this.date,
    required this.businessIds,
    this.initialBusinessId,
    this.businesses,
    this.initialApplicationId,
    this.reads,
  });

  @override
  State<AttendanceStatusDialog> createState() => _AttendanceStatusDialogState();
}

class _AttendanceStatusDialogState extends State<AttendanceStatusDialog>
    with TickerProviderStateMixin {
  // ═══════════════════════════════════════════════════════════
  // 상태 변수
  // ═══════════════════════════════════════════════════════════

  static final _parenRe = RegExp(r'\(.*?\)');

  final FirestoreService _firestoreService = FirestoreService();
  /// [R7-P1-3 P13-R] 바깥 읽기 경계 — 주지 않으면 기존 구현.
  late final AttendanceReads _reads =
      widget.reads ?? AttendanceReads.of(_firestoreService);

  // 데이터
  List<ApplicationModel> _confirmedWorkers = [];
  Map<String, AttendanceModel> _attendanceMap = {};
  Map<String, UserModel> _userMap = {};
  Map<String, String> _businessNameMap = {};
  Map<String, BusinessWorkTypeModel> _workTypeMap = {};  // 업무유형 정보
  Map<String, dynamic> _workDetailTimeMap = {};  // 업무별 근무시간 (WorkDetail)
  // 계약서 서명 상태. [REISSUE-RECOVERY] 조회 실패는 `unresolved` 로 분리된다 —
  //   `계약미작성` 배지는 **없다고 확인된** 경우에만 띄운다.
  ContractStatusBatch _contractStatusMap = const ContractStatusBatch();

  /// [CROSS-SLICE-1A] wdId → 그 모집 단위가 종료됐는가.
  ///
  /// null = 아직 모른다(조회 실패). 모르는 것을 '종료됨'으로 바꾸지 않는다 —
  /// 대체충원 CTA는 그대로 두고, 서버가 사유와 함께 최종 판정한다.
  Map<String, bool>? _closedUnitByWdId;
  AttendanceRules? _attendanceRules;            // 현재 사업장 반올림 정책
  String? _rulesLoadedForBusinessId;           // 마지막으로 정책을 로드한 businessId (캐싱용)
  Map<String, ApplicationModel> _workerIdMap = {};   // id → worker (O(1) 조회용)
  Map<String, Map<String, dynamic>> _statusCache = {};  // _computeStatus 결과 캐시
  List<List<ApplicationModel>> _tabWorkers = List.generate(4, (_) => []); // 탭별 근로자 캐시
  String? _highlightedAppId; // [5B.2A] focused individual mode — 진입 시 해당 row 강조
  /// [5B.2B] focused row scroll — highlighted card에 부여, Scrollable.ensureVisible에 사용
  final GlobalKey _focusedCardKey = GlobalKey();

  /// [DU305] 선택 직후 맞춤 대상 — 일괄 버튼 첫 줄(출근·퇴근 또는 4열 한 줄)과, 현재 탭에서 화면 순서상 첫 선택 근무자 카드.
  final GlobalKey _batchStepRowKey = GlobalKey();
  final GlobalKey _firstSelectedCardKey = GlobalKey();

  /// [DU305] 현재 탭 목록을 만드는 동안에만 true — 그 탭에서 처음 만나는 선택 카드 하나에 [_firstSelectedCardKey] 를 준다.
  ///   선택은 현재 탭에만 생기고(탭 전환 시 초기화), 한 근무는 한 탭에만 있으므로 키는 한 곳에만 붙는다.
  bool _firstSelectedPending = false;

  // UI 상태
  bool _isLoading = true;

  /// [R5-R0 §14] 조회 실패 사유. null 이면 "실패하지 않았다"는 뜻이지
  /// "결과가 있다"는 뜻이 아니다 — 빈 결과와는 별개 축이다.
  String? _loadError;
  String? _selectedBusinessId;
  bool _hasChanges = false;  // ✅ 변경 여부 추적
  
  // 선택 상태
  final Set<String> _selectedIds = {};
  bool _selectAll = false;

  // 탭 / 검색
  int _currentTabIndex = 0;
  late TabController _tabController;
  String _nameFilter = '';
  bool _showSearch = false;
  final TextEditingController _searchController = TextEditingController();

  // 파트별 정렬 모드: 0=상태순, 1=배지순, 2=이름순
  final Map<String, int> _groupSortMode = {};
  // [R5.2] NO_SHOW 대체 인력 충원 진행 중 방어 (이중 탭 방지)
  bool _isSeatReleasing = false;

  // ═══════════════════════════════════════════════════════════
  // 처리현황 계산
  // ═══════════════════════════════════════════════════════════

  /// 처리 완료된 인원 수 (급여확정 또는 노쇼 - 마감 대기 상태)
  int get _processedCount {
    int count = 0;
    for (var app in _confirmedWorkers) {
      final attendance = _attendanceMap[app.id];
      if (attendance == null) continue;
      
      // 노쇼 처리됨
      if (attendance.status == AttendanceModel.statusNoShow) {
        count++;
      }
      // 급여확정 (calculated) - 마감 대기
      else if (attendance.wageStatus == AttendanceModel.wageCalculated) {
        count++;
      }
      // 최종확정 (confirmed) / 송금완료 (transferred) - 이미 마감됨
      else if (attendance.wageStatus == AttendanceModel.wageConfirmed ||
          attendance.wageStatus == AttendanceModel.wageTransferred) {
        count++;
      }
    }
    return count;
  }

  /// 선택된 최종확정 근무자 목록 (마감취소 대상)
  List<ApplicationModel> get _selectedFinalConfirmedApps {
    return _confirmedWorkers.where((app) {
      if (!_selectedIds.contains(app.id)) return false;
      final attendance = _attendanceMap[app.id];
      return attendance?.wageStatus == AttendanceModel.wageConfirmed;
    }).toList();
  }

  late final String _dateStr;

  /// [R7-P1-3] 이 화면이 다루는 **KST 달력일** 하나.
  ///
  ///   호출부가 넘기는 `date` 는 두 종류였다.
  ///     · 홈: `FormatHelper.toKstDate(DateTime.now())` → `DateTime.utc(y,m,d)`
  ///     · 미처리 큐 / 근무 탭: `DateTime(y,m,d)` — **기기 local 자정**
  ///
  ///   그런데 이 화면은 그 값을 **instant** 로 쓴다 — `FormatHelper.kstDayRange`,
  ///   `toKstDate`, 그리고 서버로 보내는 `workDateMs` 다. `kstDayRange` 문서가
  ///   그 경우를 직접 경고한다: "`DateTime(d.year, d.month, d.day)` 로 만든 기기
  ///   local 자정을 쓰면 KST가 아닌 기기에서 창이 통째로 어긋난다."
  ///   `workDateMs` 는 더 나아가 서버에서 **근태 문서 id** 를 정한다
  ///   (`callableBatchSetNoShow`: `${applicationId}_${KST(workDateMs)}`) —
  ///   즉 기기 시간대에 따라 다른 날짜의 기록을 만들 수 있었다.
  ///
  ///   그래서 들어온 값의 **달력 성분**을 KST 달력일로 못박아 한 번만 정규화하고,
  ///   그 뒤로는 이것만 쓴다. 시간 계산 helper 들은 모두 성분 기반
  ///   (`DateTime(workDate.year, …)`)이라 KST 기기에서의 동작은 그대로다.
  late final DateTime _kstDay =
      FormatHelper.kstDayKeyOfCivil(widget.date);

  /// [R7-P1-3] 과거/미래 판정의 기준 — `_kstDay` 와 **같은 달력**이어야 한다.
  ///   기기 local 자정과 섞으면 시간대 offset 만큼 어긋난 비교가 된다.
  ///   이쪽은 **실제 현재 시각**을 KST 달력일로 바꾸는 변환이다(`toKstDate`).
  ///   위 `_kstDay` 의 성분 추출과 방향이 다르다 — 섞어 쓰지 않는다.
  DateTime get _todayKst => FormatHelper.toKstDate(DateTime.now());

  /// [R7-P1-3] 서버로 보내는 `workDateMs` — 그 KST 하루의 **자정 instant**.
  ///
  ///   서버는 이 값으로 두 가지를 정한다.
  ///     · 근태 문서 id: `${applicationId}_${KST(workDateMs) 날짜}`
  ///     · 저장되는 `attendance.workDate`: `Timestamp.fromDate(new Date(workDateMs))`
  ///
  ///   두 번째가 이 프로젝트의 DATE_ONLY canonical(= **KST 자정 instant**)이다.
  ///   그래서 `_kstDay.millisecondsSinceEpoch`(= 00:00Z, KST 09:00)를 그대로 보내면
  ///   날짜는 맞아도 저장 형태가 canonical 을 벗어난다 — 홈에서 열었을 때가
  ///   그랬다(홈은 처음부터 `toKstDate` 값을 넘겼다).
  ///   조회 창을 만드는 `kstDayRange` 의 시작값을 그대로 쓴다 — 창과 저장값과
  ///   문서 id 가 **같은 하루**를 가리킨다.
  int get _kstDayStartMs =>
      FormatHelper.kstDayRange(_kstDay).$1.millisecondsSinceEpoch;

  @override
  void initState() {
    super.initState();
    _dateStr = DateFormat('MM월 dd일 (E)', 'ko_KR').format(_kstDay);
    _tabController = TabController(length: 4, vsync: this);
    _selectedBusinessId = widget.initialBusinessId ??
        (widget.businessIds.isNotEmpty ? widget.businessIds.first : null);
    _highlightedAppId = widget.initialApplicationId; // [5B.2A]
    if (widget.businesses != null) {
      _businessNameMap = {for (final b in widget.businesses!) b.id: b.name};
    }
    _applySavedBusinessThenLoad();
  }

  Future<void> _applySavedBusinessThenLoad() async {
    if (widget.businessIds.length > 1) {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString('alfit_last_business_id');
      if (saved != null && widget.businessIds.contains(saved) && mounted) {
        setState(() => _selectedBusinessId = saved);
      }
    }
    // SharedPreferences await 이후 두 번째 mounted 체크 — initState에서 호출되므로
    //           다이얼로그가 빠르게 닫힐 경우 dispose 후 _initializeData()가 실행되는 것을 방지.
    if (!mounted) return;
    _initializeData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  /// 초기 데이터 로드 (병렬)
  Future<void> _initializeData() async {
    try {
      await Future.wait([
        // businesses가 생성자로 전달된 경우 Firestore 이름 조회 생략
        if (widget.businesses == null) _loadBusinessNames(),
        _loadData(),
      ]);
    } catch (e) {
      debugPrint('❌ [당일명단] 초기화 실패: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════
  // 데이터 로드
  // ═══════════════════════════════════════════════════════════

  /// 사업장명 조회 (30개 초과 청크 처리)
  Future<void> _loadBusinessNames() async {
    try {
      final nameMap = await _reads.businessNames(widget.businessIds);
      if (!mounted) return;
      setState(() {
        _businessNameMap = nameMap;
      });
    } catch (e) {
      debugPrint('❌ 사업장명 조회 실패: $e');
    }
  }

  /// [R8-P1C] 근태만 다시 읽는 요청의 세대 번호.
  ///   빠르게 이어지는 mutation에서 늦게 도착한 옛 응답이 최신 화면을
  ///   덮지 않게 한다. 전체 로드도 이 번호를 올려 진행 중인 부분 갱신을
  ///   무효화한다.
  int _attRefreshSeq = 0;

  /// [R8-P1C] 근태 행만 서버에서 다시 읽는다.
  ///
  ///   출퇴근·시간수정·노쇼·리셋·마감취소는 서버에서 attendance 문서만
  ///   바꾼다. 그런데 지금까지는 그 뒤에 _loadData()를 통째로 다시 돌려
  ///   지원서·업무유형·근로자 프로필·계약 상태·모집단위 종료 여부까지 전부
  ///   다시 읽었다. 출근 한 번에 7개 쿼리가 나갔고, 그중 6개는 바뀐 것이
  ///   없는 데이터였다.
  ///
  ///   성공한 행만 골라 갱신하지 않고 그 날 근태를 통째로 다시 읽는다.
  ///   어차피 조회는 한 번이고, 그래야 같은 시간에 다른 관리자가 바꾼 행도
  ///   함께 최신이 된다. 서버 응답을 근거로 상태를 추측하지 않는다.
  /// [impl_58] 서버가 일괄 처리를 **거절**한 뒤(처리 0) 근태만 다시 읽는다. [_refreshAttendanceOnly] 와 달리
  ///   읽기 실패에 '처리는 완료됐어요'를 말하지 않는다(처리된 것이 없다) — 거절 안내는 이미 떠 있다.
  Future<void> _reloadAttendanceAfterReject() async {
    if (!mounted) return;
    final appIds = _confirmedWorkers.map((a) => a.id).toList();
    if (appIds.isEmpty) return;
    final seq = ++_attRefreshSeq;
    try {
      final map = await _getAttendanceRecords(appIds);
      if (!mounted || seq != _attRefreshSeq) return;
      setState(() {
        _attendanceMap = map;
        _rebuildStatusCache();
        _rebuildTabWorkers();
      });
    } catch (e) {
      debugPrint('⚠️ 거절 뒤 근태 재조회 실패: $e');
    }
  }

  Future<void> _refreshAttendanceOnly() async {
    if (!mounted) return;
    final appIds = _confirmedWorkers.map((a) => a.id).toList();
    if (appIds.isEmpty) return;
    final seq = ++_attRefreshSeq;
    try {
      final map = await _getAttendanceRecords(appIds);
      if (!mounted || seq != _attRefreshSeq) return;
      setState(() {
        _attendanceMap = map;
        _rebuildStatusCache();
        _rebuildTabWorkers();
      });
    } catch (e) {
      // [§26] 처리는 됐는데 새로 못 읽은 것이다 — mutation이 실패한 것처럼
      //   말하지 않는다. 그리고 낡은 화면을 그대로 두지 않고 전체를 다시 건다.
      debugPrint('❌ 근태 갱신 실패 (처리 자체는 완료): $e');
      if (!mounted || seq != _attRefreshSeq) return;
      ToastHelper.showWarning('처리는 완료됐어요. 최신 상태를 불러오지 못해 다시 불러옵니다.');
      await _loadData();
    }
  }

  /// 전체 데이터 로드 (병렬 처리로 최적화)
  // [D05 설계] 데이터 새로고침 시 선택 상태(_selectedIds)를 초기화한다.
  // 의도된 동작: 새로고침 후 서버 데이터가 변경되면 이전 선택이 유효하지 않을 수 있으므로,
  // 잘못된 배치 처리를 방지하기 위해 항상 초기화한다.
  Future<void> _loadData() async {
    if (!mounted) return;
    // [R8-P1C] 진행 중인 부분 갱신을 무효화한다 — 옛 응답이 뒤늦게 덮지 않게.
    _attRefreshSeq++;
    setState(() {
      _isLoading = true;
      // 재시도 시작 — 이전 실패 표시를 지운다.
      _loadError = null;
      _selectedIds.clear();
      _selectAll = false;
      _nameFilter = '';
      _searchController.clear();
    });

    try {
      // ✅ 1단계: 근무자 목록과 업무유형 정보 병렬 로드
      //
      // [R8-P.1] 모집 단위 종료 여부와 반올림 정책도 이 라운드에서 함께 읽는다.
      //   둘 다 **이전 결과를 쓰지 않는다** — 필요한 입력은 사업장(과 날짜)뿐인데,
      //   예전에는 2단계가 끝난 뒤 각자 자기 라운드를 차지했다.
      //   DEV 실측에서 dayStaffing 은 웜 920ms 로 이 감사의 최장 읽기였고,
      //   콜드에서는 라운드마다 함수별 콜드스타트가 더해졌다.
      //
      //   실패는 합치지 않는다. 아래 두 클로저가 각자 try/catch 를 들고 있어
      //   자기 칸만 모름으로 내린다 — 근태 명단은 그대로 살아 있다.
      final bizIdForLoad = _selectedBusinessId ?? '';
      // 반올림 정책은 사업장이 바뀐 회차에만 읽는다(기존 동작 유지).
      final needsRules = _rulesLoadedForBusinessId != bizIdForLoad;

      // [CROSS-SLICE-1A] 이 날짜 모집 단위의 종료 여부 — 지원자 화면이 쓰는
      //   것과 같은 canonical source(callableGetDayStaffingDetail)에서 읽는다.
      //   여기서 슬롯 상태를 따로 캐시하거나 추측하지 않는다.
      //   실패하면 null로 둔다 — 모르는 것을 '종료됨'으로 바꾸지 않는다.
      //   (서버가 최종 권위이고, 모르는 채로 눌러도 사유와 함께 거절된다.)
      Map<String, bool>? closedByUnit;

      final step1Results = await Future.wait<Object?>([
        _getConfirmedWorkersForDate(),  // [0] 확정 근무자
        _getWorkTypeInfo(),              // [1] 업무유형 정보
        () async {
          try {
            final (dayStart, _) = FormatHelper.kstDayRange(_kstDay);
            final rows = await _reads.dayStaffing(
              businessId: bizIdForLoad,
              dayStartMs: dayStart.millisecondsSinceEpoch,
            );
            closedByUnit = {for (final r in rows) r.wdId: r.isClosed};
          } catch (e) {
            debugPrint('⚠️ [당일명단] 모집 단위 종료 여부 조회 실패: $e');
          }
          return null;
        }(),
        () async {
          if (!needsRules) return null;
          // [PERF-L27] 여는 쪽이 이미 읽은 사업장 문서를 넘겼으면 그 반올림 정책을 쓴다 — 같은 문서를
          //   다시 읽지 않는다(예전엔 받은 목록이 있어도 businessById 를 한 번 더 불렀다).
          final given = widget.businesses?.where((b) => b.id == bizIdForLoad).firstOrNull;
          if (given != null) {
            _attendanceRules = given.attendanceRules;
            _rulesLoadedForBusinessId = bizIdForLoad;
            return null;
          }
          try {
            final business = await _reads.businessById(bizIdForLoad);
            _attendanceRules = business?.attendanceRules;
            // 읽은 사업장과 같은 id 로만 표식을 남긴다 — 실패하면 표식을
            //   남기지 않아 다음 회차가 다시 읽는다(기존 동작).
            _rulesLoadedForBusinessId = bizIdForLoad;
          } catch (e) {
            debugPrint('⚠️ 반올림 정책 로드 실패: $e');
          }
          return null;
        }(),
      ]);

      final confirmedWorkers = step1Results[0] as List<ApplicationModel>;
      final workTypeMap = step1Results[1] as Map<String, BusinessWorkTypeModel>;

      // ✅ 2단계: 근무자 기반 쿼리들 병렬 실행
      // _getWorkDetailTimes()는 confirmedWorkers의 toId/slotId가 필요하므로 1단계 완료 후 실행
      final uids = confirmedWorkers.map((app) => app.uid).toSet().toList();
      final appIds = confirmedWorkers.map((app) => app.id).toList();

      final step2Results = await Future.wait([
        _getAttendanceRecords(appIds),                              // [0] 출근 기록
        // [1] 사용자 정보 — [PII-DOC-R0.1 / INV-1] 근태 현황은 이름·나이·성별만 쓴다.
        _reads.usersBatch(uids: uids, businessId: _selectedBusinessId ?? ''),
        _getWorkDetailTimes(confirmedWorkers),                        // [2] WorkDetail 시간 정보 (근무자 목록 전달)
        _reads.contractStatus(appIds: appIds, businessId: _selectedBusinessId ?? ''),  // [3] 계약 서명 상태
      ]);

      final attendanceMap = step2Results[0] as Map<String, AttendanceModel>;
      final userMap = step2Results[1] as Map<String, UserModel>;
      final workDetailTimeMap = step2Results[2] as Map<String, dynamic>;
      final contractStatusMap = step2Results[3] as ContractStatusBatch;

      if (!mounted) return;
      setState(() {
        _confirmedWorkers = confirmedWorkers;
        _workerIdMap = {for (final a in confirmedWorkers) a.id: a};
        _attendanceMap = attendanceMap;
        _userMap = userMap;
        _workTypeMap = workTypeMap;
        _workDetailTimeMap = workDetailTimeMap;
        _contractStatusMap = contractStatusMap;
        _closedUnitByWdId = closedByUnit;
        _isLoading = false;
        _rebuildStatusCache();
        _rebuildTabWorkers();
      });

      // [5B.2A] focused individual mode: 데이터 로드 완료 후 해당 application의 탭으로 이동
      if (_highlightedAppId != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _jumpToFocusedApp());
      }

      debugPrint('✅ 당일명단 로드 완료: ${confirmedWorkers.length}명');
    } catch (e) {
      // [R5-ERROR-PARTIAL-R0 §16] 조회 실패를 "근무자 없음"으로 말하지 않는다.
      //
      //   이전에는 여기서 로딩만 끄고 끝냈다. _confirmedWorkers 가 빈
      //   채로 남으니 화면은 '확정된 근무자가 없습니다' 를 띄웠다. 토스트는
      //   사라지고, 그 뒤로는 "오늘 일하는 사람이 없다" 고 단언하는 화면만
      //   남는다 — 실제로는 모르는 상태였다.
      debugPrint('❌ 당일명단 데이터 로드 실패: $e');
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _loadError = '근무자 명단을 불러오지 못했습니다.';
      });
      ToastHelper.showError('데이터 로드 실패');
    }
  }

  /// 확정 근무자 조회 (해당 날짜) - 최적화
  Future<List<ApplicationModel>> _getConfirmedWorkersForDate() async {
    // [PREDEVICE-ATTENDANCE-KST] 영업일은 Asia/Seoul 달력 날짜다.
    //   이 쿼리 창만 기기 로컬 자정으로 만들고 아래 비교 키는 KST로 만들면
    //   두 달력이 섞인다 — 비KST 기기에서 창이 통째로 밀려 그 날 확정 근무자가
    //   0명으로 보이거나 하루 어긋난 사람이 잡힌다. 같은 날짜에 대해 창과
    //   비교 키는 반드시 같은 달력에서 나와야 한다.
    final (dateStart, dateEnd) = FormatHelper.kstDayRange(_kstDay);
    // 날짜 비교용 — startDateOnly/endDateOnly와 동일한 UTC-midnight(KST) 포맷
    final dateKeyKst = FormatHelper.toKstDate(_kstDay);
    
    final result = <ApplicationModel>[];
    final seenIds = <String>{};  // 단기/장기 중복 entry 방어

    // ✅ 1+2. 단기/장기 CF 동시 호출 (병렬화)
    // [CF 이전 2026-07-13] Firestore 보안규칙 PERMISSION_DENIED 근본 해결
    // [R8-P7.1] cap 에서 잘린 것을 전부로 오해하지 않도록 페이징 헬퍼 경유.
    final cfResults = await Future.wait([
      // [R7-P1-2.3] 근태 현황 — 이 화면의 조작 게이트와 같은 canManageWorkers.
      _reads.applicationsPaged({
        'businessId': _selectedBusinessId,
        'workDateGteMs': dateStart.millisecondsSinceEpoch,
        'workDateLtMs': dateEnd.millisecondsSinceEpoch,
        'purpose': FirestoreService.purposeWorkerOperation,
        'limit': 2000,
      }),
      _reads.applicationsPaged({
        'businessId': _selectedBusinessId,
        'type': AppType.longTerm,
        'purpose': FirestoreService.purposeWorkerOperation,
        'limit': 2000,
      }),
    ]);
    final shortTermCFResult = cfResults[0];
    final longTermCFResult = cfResults[1];

    const confirmedStatuses = {AppStatus.confirmed, AppStatus.contractPending};
    for (final e in (shortTermCFResult)) {
      final m = Map<String, dynamic>.from(e as Map);
      final docId = m.remove('id') as String? ?? '';
      final app = ApplicationModel.tryFromMap(m, docId);
      if (app == null) continue;
      if (!confirmedStatuses.contains(app.status)) continue;
      if (app.workDays == null || app.workDays!.isEmpty) {
        if (seenIds.add(app.id)) result.add(app);
      }
    }

    debugPrint('📋 [당일명단] 단기 확정자: ${result.length}명');
    final longTermRaw = List.from(
        longTermCFResult);

    int longTermCount = 0;
    for (final e in longTermRaw) {
      final m = Map<String, dynamic>.from(e as Map);
      final docId = m.remove('id') as String? ?? '';
      final app = ApplicationModel.tryFromMap(m, docId);
      if (app == null) continue;
      if (!confirmedStatuses.contains(app.status)) continue;
      
      // 🔥 퇴사일이 있으면 그 날짜까지만
      final endDate = app.actualResignDate ?? app.workEndDate;

      // 🔥 시작일 계산: desiredStartDate 우선 → confirmedAt → workDate
      DateTime effectiveStartDate = app.desiredStartDate ?? app.workDate;
      if (app.confirmedAt != null && app.desiredStartDate == null) {
        final confirmedDate = FormatHelper.toKstDate(app.confirmedAt!);
        if (confirmedDate.isAfter(FormatHelper.toKstDate(app.workDate))) {
          effectiveStartDate = confirmedDate;
        }
      }

      // 기간 체크 (시간 제거하고 날짜만 비교)
      final startDateOnly = FormatHelper.toKstDate(effectiveStartDate);

      if (endDate != null) {
        final endDateOnly = FormatHelper.toKstDate(endDate);
        if (dateKeyKst.isBefore(startDateOnly) || dateKeyKst.isAfter(endDateOnly)) {
          continue;
        }
      } else {
        // 퇴사일 없음 = 오픈 엔드 계약, 시작일 이후는 모두 포함
        if (dateKeyKst.isBefore(startDateOnly)) {
          continue;
        }
        // 퇴사/계약해지 승인 완료 근무자 제외
        if (app.isTerminationApproved) continue;
      }

      // 🔥 휴무일 체크 - 휴무일이면 제외
      if (app.isLeaveDateOn(dateKeyKst)) continue;

      // extraWorkDates 우선 확인 — 추가 근무 승인일은 정규 요일 외에도 포함
      final isExtraWorkDay = app.isExtraWorkDateOn(dateKeyKst);
      // 요일 체크 — workDays가 없으면 요일 불문 포함 (스케줄 미지정 고정근무자)
      final dayWeekday = FormatHelper.weekday(dateKeyKst);
      if (isExtraWorkDay || app.workDays == null || app.workDays!.isEmpty || app.workDays!.contains(dayWeekday)) {
        if (seenIds.add(app.id)) {
          result.add(app);
          longTermCount++;
        }
      }
    }
    
    debugPrint('📋 [당일명단] 장기 확정자: $longTermCount명');
    debugPrint('📋 [당일명단] 총 확정자: ${result.length}명');

    return result;
  }

  /// 출근 기록 조회
  ///
  /// [C01 설계] applicationIds를 받지만 whereIn 필터로 사용하지 않는다.
  /// 대신 businessId + workDate 범위 쿼리로 당일 사업장 전체 출근 기록을 한 번에 가져온다.
  /// 이유: whereIn은 최대 30개 제한이 있어 N+1 문제를 유발할 수 있고,
  ///       당일 한 사업장의 출근 기록은 수십~수백 건 수준으로 단일 쿼리가 더 효율적이다.
  ///       applicationIds는 결과가 빈 경우 조기 반환을 위한 가드 조건으로만 사용된다.
  ///
  /// [BUG-수정] 야간 단기근무자 당일명단 미반영:
  ///   근무자 앱은 work.workDate(어제) 기준으로 attendance docId를 생성하므로,
  ///   오늘 자정 이후 퇴근하는 야간 단기근무자는 workDate가 전날로 저장됨.
  ///   쿼리 범위를 전날(dateStart - 1일)부터 오늘 자정까지로 확장하여 이를 포함함.
  Future<Map<String, AttendanceModel>> _getAttendanceRecords(
    List<String> applicationIds,
  ) async {
    if (applicationIds.isEmpty) return {};

    // [PREDEVICE-ATTENDANCE-KST] 근태 조회 창도 KST 영업일 기준으로 만든다.
    //   서버는 workDate를 KST 자정 instant로 저장하므로 기기 로컬 자정으로
    //   창을 만들면 비KST 기기에서 하루가 밀린다.
    final (dateStart, dateEnd) = FormatHelper.kstDayRange(_kstDay);
    // [BUG-수정] 전날 야간 단기근무자 포함: workDate 조회 범위를 전날부터 시작
    final queryRangeStart = dateStart.subtract(const Duration(days: 1));

    // CF 경유: callableGetAdminAttendances (Admin SDK 서버사이드 권한 검증)
    final cfItems = await _reads.adminAttendances(
      businessId: _selectedBusinessId ?? '',
      startMs: queryRangeStart.millisecondsSinceEpoch,
      endMs: dateEnd.millisecondsSinceEpoch,
    );

    final Map<String, AttendanceModel> attendanceMap = {};
    for (final e in cfItems) {
      final m = Map<String, dynamic>.from(e as Map);
      final id = m.remove('id') as String? ?? '';
      // [ATTENDANCE-UNKNOWN-DEST.28] status 가 없는 근태를 fromMap 기본값('absent')으로 읽어 결근 →
      //   '처리완료' 탭에 두었다. 통계는 같은 문서를 '근태 확인 필요'라 안내한다 — 같은 판정을 쓴다.
      m['status'] = AttendanceModel.displayStatusOfRaw(m['status']);
      final attendance = AttendanceModel.tryFromMap(m, id);
      if (attendance == null) continue;
      // applicationIds에 포함된 근무자만 맵에 저장 (전날 기록이 오늘 명단에 섞이지 않도록 필터)
      if (applicationIds.contains(attendance.applicationId)) {
        attendanceMap[attendance.applicationId] = attendance;
      }
    }

    return attendanceMap;
  }


  /// 업무유형 정보 조회
  Future<Map<String, BusinessWorkTypeModel>> _getWorkTypeInfo() async {
    final Map<String, BusinessWorkTypeModel> workTypeMap = {};
    
    if (_selectedBusinessId == null) return workTypeMap;

    try {
      final docs = await _reads.workTypeDocs(_selectedBusinessId!);

      for (final e in docs.entries) {
        final workType = BusinessWorkTypeModel.tryFromMap(e.value, e.key);
        if (workType != null) workTypeMap[workType.name] = workType;
      }
    } catch (e) {
      debugPrint('업무유형 조회 실패: $e');
    }

    return workTypeMap;
  }

  // ═══════════════════════════════════════════════════════════
  // 유틸리티 메서드
  // ═══════════════════════════════════════════════════════════

  /// 사용자 표시명 (이름만)
  String _getDisplayName(String uid) {
    final user = _userMap[uid];
    return user?.name ?? '이름 없음';
  }

  /// 성별/나이 표시 문자열
  String _getGenderAge(String uid) {
    final user = _userMap[uid];
    if (user == null) return '';

    final parts = <String>[];
    if (user.age != null) parts.add('${user.age}');
    if (user.gender != null) {
      final genderShort = user.gender == '남성' ? '남' : '여';
      parts.add(genderShort);
    }
    
    // [R7-PRE1A.1] 번호를 이 보조 줄 맨 앞에 둔다 — `(W-014, 30대, 여)`.
    //   당일명단은 현장에서 사람을 호명하며 쓰는 화면이라, 동명이인이 있으면
    //   이름만으로는 누구에게 출근을 찍는지 알 수 없다.
    final withNo = PersonLabel.secondary(user.personNo, parts.join(', '));
    return withNo.isNotEmpty ? '($withNo)' : '';
  }

  /// 확인 문구용 — `김지현(W-014)`. 번호가 없으면 이름만.
  String _getIdentifiedName(String uid) =>
      _userMap[uid]?.nameWithPersonNo ?? '이름 없음';

  /// 캐시된 출퇴근 상태 반환 (build당 260회 호출 방지용)
  Map<String, dynamic> _getAttendanceStatus(ApplicationModel app) {
    return _statusCache[app.id] ?? _computeStatus(app);
  }

  /// 전체 statusCache 재빌드 — _confirmedWorkers/_attendanceMap/_workDetailTimeMap 변경 후 호출
  void _rebuildStatusCache() {
    _statusCache = {
      for (final app in _confirmedWorkers) app.id: _computeStatus(app),
    };
  }

  /// 탭별 근로자 캐시 재빌드 — _rebuildStatusCache() 직후 항상 호출
  void _rebuildTabWorkers() {
    _tabWorkers = List.generate(4, (i) => _workersByTab(i));
  }

  /// [5B.2A/5B.2B] focused mode — 해당 application의 탭으로 이동 + row ensureVisible
  /// initialApplicationId가 속한 탭을 찾아 animateTo.
  /// 탭 전환 완료 후 _scrollToFocusedCard()로 해당 row를 viewport에 표시.
  void _jumpToFocusedApp() {
    if (!mounted || _highlightedAppId == null) return;
    for (int i = 0; i < 4; i++) {
      if (_tabWorkers[i].any((a) => a.id == _highlightedAppId)) {
        if (_currentTabIndex != i) {
          _tabController.animateTo(i);
          setState(() => _currentTabIndex = i);
          // 탭 전환 애니메이션 완료 후 scroll (300ms 정도 여유)
          Future.delayed(const Duration(milliseconds: 350), _scrollToFocusedCard);
        } else {
          // 이미 올바른 탭 — 바로 scroll
          WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToFocusedCard());
        }
        return;
      }
    }
    // 탭에서 못 찾으면 — 이미 완료/제거된 상태. highlight만 유지.
    // [STATS-TO-ATTENDANCE.27] 다른 근무로 옮기지 않고 이유를 한 번 말한다(재조회마다 반복하지 않는다).
    if (!_focusMissReported) {
      _focusMissReported = true;
      ToastHelper.showWarning('선택한 근무를 이 날짜 명단에서 찾지 못했어요. 취소·삭제됐거나 명단에 없는 근무일 수 있어요');
    }
  }

  bool _focusMissReported = false;

  /// [5B.2B] _focusedCardKey를 통해 해당 row를 viewport에 보이게 scroll
  void _scrollToFocusedCard() {
    if (!mounted || _highlightedAppId == null) return;
    final ctx = _focusedCardKey.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
        alignment: 0.2, // 상단 20% 위치에 표시 (완전 상단보다 맥락 있게)
      );
    }
  }

  /// 출퇴근 상태 실제 계산 (UI 레벨 — DB status와 별개)
  Map<String, dynamic> _computeStatus(ApplicationModel app) {
    final attendance = _attendanceMap[app.id];
    final expectedStart = WorkDetailHelper.effectiveStart(app, _workDetailTimeMap);
    final expectedEnd   = WorkDetailHelper.effectiveEnd(app, _workDetailTimeMap);

    // 노쇼
    if (attendance?.status == AttendanceModel.statusNoShow) {
      return {
        'status': 'noshow',
        'color': AppColors.error,
        'icon': Icons.cancel,
        'text': '노쇼',
        'timeText': null,
        'isPast': false,
      };
    }

    // 퇴근 완료
    if (attendance?.checkOut != null) {
      final checkInDisplay = attendance!.checkIn != null
          ? _trimSeconds(attendance.checkIn!)
          : '-';
      final timeText = '$checkInDisplay ~ ${_trimSeconds(attendance.checkOut!)}';

      // 조퇴 판단 — 출근 시간 기준으로 익일 자정 넘김 보정
      final isEarly = AttendanceStatusHelper.isEarlyLeave(
          attendance.checkOut!, expectedEnd, checkIn: attendance.checkIn);

      // 송금 완료 (transferred) — 최종확정보다 우선 표시
      if (attendance.wageStatus == AttendanceModel.wageTransferred) {
        return {
          'status': 'transferred',
          'color': AppColors.teal,
          'icon': Icons.check_circle_outline,
          'text': '송금완료',
          'timeText': timeText,
          'isPast': false,
        };
      }
      // 최종 확정
      if (attendance.wageStatus == AttendanceModel.wageConfirmed) {
        return {
          'status': 'final_confirmed',
          'color': AppColors.success,
          'icon': Icons.verified,
          'text': isEarly ? '최종확정(조퇴)' : '최종확정',
          'timeText': timeText,
          'isPast': false,
        };
      }
      // 급여 확정
      if (attendance.wageStatus == AttendanceModel.wageCalculated) {
        return {
          'status': 'wage_confirmed',
          'color': AppColors.warning,
          'icon': Icons.paid,
          'text': isEarly ? '급여확정(조퇴)' : '급여확정',
          'timeText': timeText,
          'isPast': false,
        };
      }
      // 조퇴
      if (isEarly) {
        return {
          'status': 'early_leave',
          'color': AppColors.warningDark,
          'icon': Icons.directions_run,
          'text': '조퇴',
          'timeText': timeText,
          'isPast': false,
        };
      }
      // 정상 퇴근 — [5B.2A] Root pill(grey600)과 동일한 neutral 색상으로 통일
      return {
        'status': 'checkout',
        'color': AppColors.grey600,
        'icon': Icons.home,
        'text': '퇴근',
        'timeText': timeText,
        'isPast': false,
      };
    }

    // 출근 완료 (퇴근 미체크)
    if (attendance?.checkIn != null) {
      final isLate = AttendanceStatusHelper.isLate(
        attendance!.checkIn!, expectedStart,
        isNextDay: AttendanceStatusHelper.isNextDayCheckIn(attendance.checkIn!, expectedStart),
      );
      // 과거 날짜이거나 당일 퇴근 예정 시간 초과 → 퇴근 미체크 경고
      final today = _todayKst;
      final isPastDay = _kstDay.isBefore(today);
      bool isOverdue = false;
      if (!isPastDay && expectedEnd.isNotEmpty) {
        final endParts = expectedEnd.split(':');
        if (endParts.length == 2) {
          final endH = int.tryParse(endParts[0]);
          final endM = int.tryParse(endParts[1]);
          if (endH != null && endM != null) {
            final workDay = _kstDay;
            var endAt = DateTime(workDay.year, workDay.month, workDay.day, endH, endM);
            final startParts = expectedStart.split(':');
            final startH = int.tryParse(startParts.first) ?? 0;
            final startM = startParts.length > 1 ? (int.tryParse(startParts[1]) ?? 0) : 0;
            if (endH < startH || (endH == startH && endM < startM)) endAt = endAt.add(const Duration(days: 1));
            isOverdue = DateTime.now().isAfter(endAt);
          }
        }
      }
      if (isPastDay || isOverdue) {
        return {
          'status': 'missed_checkout',
          'color': AppColors.error,
          'icon': Icons.logout,
          'text': isLate ? '지각·퇴근미체크' : '퇴근미체크',
          'timeText': _trimSeconds(attendance.checkIn!),
          'isPast': true,
        };
      }
      if (isLate) {
        return {
          'status': 'late',
          'color': AppColors.warning,
          'icon': Icons.warning_amber,
          'text': '지각',
          'timeText': _trimSeconds(attendance.checkIn!),
          'isPast': false,
        };
      }
      return {
        'status': 'checkin',
        'color': AppColors.success,
        'icon': Icons.check_circle,
        'text': '출근',
        'timeText': _trimSeconds(attendance.checkIn!),
        'isPast': false,
      };
    }

    // 미출근
    return {
      'status': 'pending',
      'color': AppColors.grey500,
      'icon': Icons.schedule,
      'text': '미출근',
      'timeText': null,
      'isPast': false,
    };
  }

  /// 상태 우선순위 (낮을수록 상단 — 처리 필요 순)
  int _workerSortPriority(ApplicationModel app) {
    final status = _getAttendanceStatus(app)['status'] as String;
    const p = {
      'pending':         0,  // 미출근
      'missed_checkout': 1,  // 퇴근미체크
      'late':            2,  // 지각
      'checkin':         3,  // 출근 중
      'early_leave':     4,  // 조퇴
      'checkout':        5,  // 퇴근
      'wage_confirmed':  6,  // 급여확정
      'final_confirmed': 7,  // 최종확정
      'transferred':     8,  // 송금완료
      'noshow':          9,  // 노쇼
    };
    return p[status] ?? 10;
  }

  /// 배지 개수/무게 기반 정렬 키 (배지순 모드)
  /// 지각(4) + 연장(3) + 심야(2) + 조퇴(1) 가중치 합산 — 높을수록 상단
  int _badgeWeight(ApplicationModel app) {
    final statusInfo = _getAttendanceStatus(app);
    final attendance = _attendanceMap[app.id];
    if (attendance == null) return 0;

    final effStart = WorkDetailHelper.effectiveStart(app, _workDetailTimeMap);
    final effEnd   = WorkDetailHelper.effectiveEnd(app, _workDetailTimeMap);
    final flags = AttendanceBadgeHelper.compute(
      checkIn:  attendance.checkIn,
      checkOut: attendance.checkOut,
      effStart: effStart,
      effEnd:   effEnd,
      wageDetail: attendance.wageDetail,
    );

    int weight = 0;
    if (flags.isLate)       weight += 4;
    if (flags.isOvertime)   weight += 3;
    if (flags.isNight)      weight += 2;
    if (flags.isEarlyLeave) weight += 1;
    // 처리 필요한 상태도 가중치에 반영
    final status = statusInfo['status'] as String;
    if (status == 'pending')         weight += 16;
    if (status == 'missed_checkout') weight += 12;
    return weight;
  }

  /// "HH:mm:ss" → "HH:mm"  (초 제거)
  String _trimSeconds(String timeStr) {
    final parts = timeStr.split(':');
    if (parts.length < 2) return timeStr;
    return '${parts[0]}:${parts[1]}';
  }

  /// 탭별 근로자 분류
  /// 0=검토(지금 처리 필요), 1=정상, 2=확인(adminConfirmed), 3=완료(급여확정·노쇼·결근)
  ///
  /// [AH-V2-04A] 검토 탭 = AttendanceReviewHelper.requiresReviewNow.
  ///   관리자 Home의 `근태 확인`과 동일한 canonical 판정을 쓴다.
  ///   이전 조건은 근무 시작 전 인원까지 '미출근'으로 검토 탭에 넣어,
  ///   아직 출근할 시간도 안 된 사람에게 노쇼 칩이 열려 있었다.
  ///   결근(absent)은 시스템 확정 결과이므로 검토가 아니라 완료 탭에 둔다.
  List<ApplicationModel> _workersByTab(int tabIndex) {
    const doneUiStatuses = {'transferred', 'final_confirmed', 'wage_confirmed', 'noshow'};
    final now = DateTime.now();
    return _confirmedWorkers.where((app) {
      final s = _getAttendanceStatus(app)['status'] as String;
      final attendance = _attendanceMap[app.id];
      final isDone = doneUiStatuses.contains(s) ||
                     attendance?.wageStatus == AttendanceModel.wageCalculated ||
                     attendance?.wageStatus == AttendanceModel.wageConfirmed ||
                     attendance?.wageStatus == AttendanceModel.wageTransferred ||
                     attendance?.status == AttendanceModel.statusNoShow ||
                     attendance?.status == AttendanceModel.statusAbsent;
      final isAdminConfirmed = attendance?.adminConfirmed == true;
      final needsReview = AttendanceReviewHelper.requiresReviewNow(
        now: now,
        workDate: _kstDay,
        scheduledStart: WorkDetailHelper.effectiveStart(app, _workDetailTimeMap),
        scheduledEnd:   WorkDetailHelper.effectiveEnd(app, _workDetailTimeMap),
        attendance: attendance,
      );
      switch (tabIndex) {
        case 0: return needsReview;
        case 1: return !needsReview && !isDone && !isAdminConfirmed;
        case 2: return isAdminConfirmed && !isDone;
        case 3: return isDone;
        default: return true;
      }
    }).toList();
  }



  /// 통계 계산 — [workers]를 지정하면 해당 목록만 집계 (탭별 통계)
  Map<String, int> _calculateStats({List<ApplicationModel>? workers}) {
    final list = workers ?? _confirmedWorkers;
    int total = list.length;
    int checkedIn = 0;
    int checkedOut = 0;
    int late = 0;
    int earlyArrival = 0;
    int earlyLeave = 0;
    int missedCheckout = 0;
    int noShow = 0;

    for (var app in list) {
      final statusMap = _getAttendanceStatus(app);
      final s = statusMap['status'] as String;
      final attendance = _attendanceMap[app.id];

      switch (s) {
        case 'checkout':
        case 'wage_confirmed':
        case 'final_confirmed':
        case 'transferred':
          checkedIn++;
          checkedOut++;
          break;
        case 'early_leave':
          checkedIn++;
          checkedOut++;
          earlyLeave++;
          break;
        case 'checkin':
          checkedIn++;
          break;
        case 'late':
          checkedIn++;
          late++;
          break;
        case 'missed_checkout':
          checkedIn++;
          missedCheckout++;
          break;
        case 'noshow':
          noShow++;
          break;
      }

      // 조출 카운트 (출근 기록 있고 30분 이상 일찍 찍힌 경우)
      if (attendance?.checkIn != null) {
        final effStart = WorkDetailHelper.effectiveStart(app, _workDetailTimeMap);
        if (AttendanceStatusHelper.isEarlyArrival(attendance!.checkIn!, effStart)) {
          earlyArrival++;
        }
      }
    }

    return {
      'total': total,
      'checkedIn': checkedIn,
      'checkedOut': checkedOut,
      'notCheckedIn': total - checkedIn - noShow,
      'late': late,
      'earlyArrival': earlyArrival,
      'earlyLeave': earlyLeave,
      'missedCheckout': missedCheckout,
      'noShow': noShow,
    };
  }

  // ═══════════════════════════════════════════════════════════
  // BUILD 메서드
  // ═══════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dateStr = _dateStr;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        // [ATT-POPSCOPE-01] TextField 포커스 해제 — 배리어 tap(didPop=true)·back(didPop=false) 모두 처리
        FocusScope.of(context).unfocus();
        if (!didPop) {
          Navigator.pop(context, _hasChanges);
        }
      },
      child: AppModalShell(
        children: [
          // 헤더
          _buildHeader(theme, dateStr),

          // 내용 (하단 버튼 포함 — 스크롤 영역 안에 위치)
          Flexible(
            child: _isLoading
                ? const LoadingWidget(message: '당일명단 조회 중...')
                : _loadError != null
                    ? _buildErrorState()
                    : _confirmedWorkers.isEmpty
                        ? _buildEmptyState()
                        : _buildContent(theme),
          ),

          // 선택 인원 확인/취소 고정 바 (선택 + 대상 있을 때만 표시)
          if (!_isLoading && _loadError == null && _selectedIds.isNotEmpty)
            _buildSelectionConfirmBar(theme),

          // 하단 고정 바 (명단 출력 / 급여관리 / 처리현황)
          //   [R5-R0 §18] 명단을 모르는 상태에서는 그 명단을 전제로 한
          //   동작을 열지 않는다 — 빈 명단을 출력하거나 급여 화면으로
          //   보내면 "없음"을 사실처럼 굳힌다.
          if (!_isLoading && _loadError == null)
            _buildBottomBar(theme),
        ],
      ),
    );
  }

  /// 헤더 (flat white + accent bar + 사업장 드롭다운)
  Widget _buildHeader(ThemeData theme, String dateStr) {
    return AppModalHeader(
      title: '당일명단',
      subtitle: dateStr,
      onClose: () {
        FocusScope.of(context).unfocus();
        Navigator.pop(context, _hasChanges);
      },
      trailing: widget.businessIds.length > 1
          ? AppSelectField<String>(
              value: _selectedBusinessId,
              hintText: '사업장을 선택하세요',
              sheetTitle: '사업장 선택',
              items: widget.businessIds,
              labelOf: (id) => _businessNameMap[id] ?? id,
              prefixIcon: Icons.business,
              // [DU623b · 장부143 · 판정206 :53 · :61] 이 칸만 긴 사업장 이름을 낱말 단위로 줄을 넘겨 보인다(O002 DU520 · DU521 선례 opt-in) — 공용 기본값 · 시트 · 콜백 그대로.
              wrapLabel: true,
              onChanged: (value) {
                if (value != null && value != _selectedBusinessId) {
                  setState(() => _selectedBusinessId = value);
                  SharedPreferences.getInstance().then(
                    (prefs) => prefs.setString('alfit_last_business_id', value),
                  );
                  _loadData();
                }
              },
            )
          : null,
    );
  }

  /// 빈 상태 — **조회에 성공했고 결과가 0명**일 때만 쓴다.
  Widget _buildEmptyState() {
    return const AppEmptyState(
      icon: Icons.people_outline,
      title: '확정된 근무자가 없습니다',
    );
  }

  /// [R5-R0 §14·§30] 조회 실패 상태 — 없음과 다른 말을 하고, 다시 시도할
  /// 길을 준다. 자동 재시도·폴링은 두지 않는다.
  Widget _buildErrorState() {
    return AppEmptyState(
      icon: Icons.cloud_off_outlined,
      iconColor: AppColors.grey500,
      title: _loadError ?? '명단을 확인하지 못했습니다',
      subtitle: '근무자가 없다는 뜻이 아닙니다. 잠시 후 다시 시도해주세요.',
      action: TextButton.icon(
        onPressed: _isLoading ? null : _loadData,
        icon: const Icon(Icons.refresh, size: 18),
        label: const Text('다시 시도'),
      ),
    );
  }

  /// 메인 콘텐츠
  Widget _buildContent(ThemeData theme) {
    final padding = ResponsiveHelper.cardPadding(context);
    final needsReview = _tabWorkers[0];
    final normal = _tabWorkers[1];
    final adminConfirmedWorkers = _tabWorkers[2];
    final done = _tabWorkers[3];

    // [DU304] 고정 상단(탭·통계·일괄 액션)이 가용 높이를 다 쓰면 목록(TabBarView)이 0 이 된다
    //   (B320·배율 2.0 실측: 가용 325.4, 상단 348.15–421.65 → 목록 0·넘침 22.75–96.25).
    //   상단은 자연 높이가 상한 이하이면 지금처럼 고정으로 다 보이고, 넘칠 때만 상한 안에서 따로 스크롤된다.
    //   목록은 남은 높이를 쓴다. 상한은 실제 가용 높이의 비율이라 화면 폭·배율 상수 분기가 아니다.
    return LayoutBuilder(builder: (context, hostC) {
      const topShare = 0.5;
      final topMax = hostC.maxHeight.isFinite ? hostC.maxHeight * topShare : double.infinity;
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 탭 바 + 통계 + 액션바 — 스크롤 영역 밖 고정(상한을 넘을 때만 그 안에서 스크롤)
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: topMax),
            child: SingleChildScrollView(
            primary: false,
            child: Padding(
            padding: EdgeInsets.fromLTRB(
                padding.left, ResponsiveHelper.spacing(context, 6),
                padding.right, 0),
            child: Column(
              children: [
                // 탭 바 — 압축 라벨로 4개 탭 항상 표시 (360dp 오버플로우 없음)
                // [COMMON-TEXT-LAYOUT.28] 글자가 크면 4개가 한 줄에 안 들어가 '확인 / 필요' 로 갈렸다 —
                //   그때만 가로 스크롤(탭 이름은 한 줄).
                LayoutBuilder(builder: (context, c) {
                final tabsFit = TextLayout.tabsFit(context, c.maxWidth, 4);
                return TabBar(
                  controller: _tabController,
                  isScrollable: !tabsFit,
                  tabAlignment: tabsFit ? null : TabAlignment.start,
                  labelPadding: tabsFit
                      ? EdgeInsets.zero
                      : EdgeInsets.symmetric(horizontal: ResponsiveHelper.spacing(context, 12)),
                  labelStyle: ResponsiveHelper.smallStyle(context, fontWeight: FontWeight.bold),
                  unselectedLabelStyle: ResponsiveHelper.smallStyle(context),
                  onTap: (index) {
                    final hadSelection = _selectedIds.isNotEmpty;
                    setState(() {
                      _currentTabIndex = index;
                      _selectedIds.clear();
                      _selectAll = false;
                      _showSearch = false;
                      _nameFilter = '';
                      _searchController.clear();
                    });
                    if (hadSelection) {
                      ToastHelper.showInfo('탭 전환으로 선택이 초기화됐습니다.');
                    }
                  },
                  tabs: [
                    Tab(child: AppTabLabel(label: '확인필요', count: needsReview.length, urgent: needsReview.isNotEmpty)),
                    Tab(child: AppTabLabel(label: '정상', count: normal.length)),
                    // [5B.2B] "확인완료": 관리자가 근태 확인한 사람들의 탭
                    Tab(child: AppTabLabel(label: '확인완료', count: adminConfirmedWorkers.length, badgeColor: AppColors.brand)),
                    Tab(child: AppTabLabel(label: '처리완료', count: done.length, badgeColor: AppColors.grey500)),
                  ],
                );
                }),
                SizedBox(height: ResponsiveHelper.spacing(context, 8)),
                _buildCompactStats(theme, _confirmedWorkers),
                SizedBox(height: ResponsiveHelper.spacing(context, 8)),
                _buildBatchActionBar(theme),
                SizedBox(height: ResponsiveHelper.spacing(context, 8)),
              ],
            ),
          ),
            ),
          ),

          // 탭별 콘텐츠 — 스크롤
          Flexible(
            child: TabBarView(
              controller: _tabController,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                _buildTabContent(theme, needsReview, padding),
                _buildTabContent(theme, normal, padding),
                _buildTabContent(theme, adminConfirmedWorkers, padding),
                _buildTabContent(theme, done, padding),
              ],
            ),
          ),
        ],
      );
    });
  }

  /// 탭 라벨 위젯 (카운트 배지 포함)
  /// 탭별 콘텐츠 (빈 상태 또는 업무 그룹 목록)
  Widget _buildTabContent(ThemeData theme, List<ApplicationModel> tabWorkers, EdgeInsets padding) {
    if (tabWorkers.isEmpty) {
      return const AppEmptyState(
        icon: Icons.people_outline,
        title: '해당 근무자가 없습니다',
      );
    }
    // [DU305] 현재 탭이면 이 목록을 만드는 동안 첫 선택 카드 표시를 켠다(화면 순서 = 만드는 순서).
    _firstSelectedPending = identical(tabWorkers, _tabWorkers[_currentTabIndex]);
    final groups = _buildWorkTypeGroups(theme, workers: tabWorkers);
    _firstSelectedPending = false;
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(padding.left, 0, padding.right, 0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          groups,
        ],
      ),
    );
  }

  /// 통계 컴팩트 스트립 — 현재 탭 기준 수치만 표시
  Widget _buildCompactStats(ThemeData theme, List<ApplicationModel> tabWorkers) {
    final stats = _calculateStats(workers: tabWorkers);
    final badges = <_StatChip>[];
    if ((stats['earlyArrival'] ?? 0) > 0) badges.add(_StatChip('조출', stats['earlyArrival']!, AppColors.success));
    if ((stats['late'] ?? 0) > 0)              badges.add(_StatChip('지각', stats['late']!, AppColors.warningDark));
    if ((stats['earlyLeave'] ?? 0) > 0)        badges.add(_StatChip('조퇴', stats['earlyLeave']!, AppColors.amber));
    if ((stats['missedCheckout'] ?? 0) > 0)    badges.add(_StatChip('미퇴근', stats['missedCheckout']!, AppColors.error));

    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 4),
        vertical: ResponsiveHelper.spacing(context, 6),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 주요 4개 — Expanded로 균등 분배 (오버플로우 방지)
          // [DU305] 균등 칸에 모든 칸(건수 줄·이름 줄 중 넓은 쪽)이 한 줄로 들어가면 지금 그대로다.
          //   안 들어가고(B320·배율 2.0 관측 '미출 / 근') 필요폭 합이 가용폭 이하이면, 칸마다 need + 남는 폭 균등분을
          //   그대로 준다 — 반올림이 없어 모든 칸 폭 ≥ need(한 줄)다. 필요폭 합이 가용폭보다 크면 need 비율로 나누며,
          //   이때는 한 줄을 보장하지 않는다(지금처럼 줄바꿈, 잘림·축소 없음).
          //   글자 크기·문구·색·구분선·순서는 그대로다. 필요폭은 실제 렌더 위치의 유효 스타일로 잰다([_lineWidth]).
          LayoutBuilder(builder: (lctx, c) {
            // [UI-3] 확정·출근은 사실(기본 글자색), 미출근·노쇼는 양수일 때만
            //   경고색 — 0은 평온한 회색(근무 탭 집계와 같은 규칙).
            final cells = <(String, int, Color)>[
              ('확정',   stats['total']!,        AppColors.textPrimary),
              ('출근',   stats['checkedIn']!,    AppColors.textPrimary),
              ('미출근', stats['notCheckedIn']!, AppColors.warningDark),
              ('노쇼',   stats['noShow']!,       AppColors.errorDark),
            ];
            final dividerW = 1 + 2 * ResponsiveHelper.spacing(context, 4);
            final avail = c.maxWidth - dividerW * (cells.length - 1);
            final needs = [for (final cell in cells) _statCellNeed(lctx, cell.$1, cell.$2)];
            if (needs.every((w) => w <= avail / cells.length)) {
              return Row(
                children: [
                  for (var i = 0; i < cells.length; i++) ...[
                    if (i > 0) _buildStatDivider(),
                    Expanded(child: _buildStatCell(cells[i].$1, cells[i].$2, cells[i].$3)),
                  ],
                ],
              );
            }
            final sumNeed = needs.fold<double>(0, (a, b) => a + b);
            final slack = avail - sumNeed;
            return Row(
              children: [
                for (var i = 0; i < cells.length; i++) ...[
                  if (i > 0) _buildStatDivider(),
                  SizedBox(
                    width: slack >= 0 ? needs[i] + slack / cells.length : avail * needs[i] / sumNeed,
                    child: _buildStatCell(cells[i].$1, cells[i].$2, cells[i].$3),
                  ),
                ],
              ],
            );
          }),
          // 보조 통계 — 이상 있을 때만 두 번째 줄
          if (badges.isNotEmpty) ...[
            SizedBox(height: ResponsiveHelper.spacing(context, 4)),
            Wrap(
              spacing: ResponsiveHelper.spacing(context, 10),
              runSpacing: 0,
              children: badges.map((b) => _buildMiniDot(b)).toList(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStatCell(String label, int count, Color color) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$count건',
          style: ResponsiveHelper.smallStyle(context).copyWith(
            fontWeight: FontWeight.bold,
            color: count > 0 ? color : AppColors.grey500,
          ),
        ),
        Text(label, style: ResponsiveHelper.tinyStyle(context, color: AppColors.grey500)),
      ],
    );
  }

  Widget _buildStatDivider() => Container(
    width: 1, height: 24, color: AppColors.grey200,
    margin: EdgeInsets.symmetric(horizontal: ResponsiveHelper.spacing(context, 4)),
  );

  /// [DU305] 통계 칸 하나가 줄바꿈 없이 필요한 폭 — 건수 줄과 이름 줄 중 넓은 쪽.
  ///   [_buildStatCell] 과 같은 글자 스타일로 잰다(색은 폭과 무관).
  double _statCellNeed(BuildContext c, String label, int count) {
    final countW = _lineWidth(c, '$count건',
        ResponsiveHelper.smallStyle(context).copyWith(fontWeight: FontWeight.bold));
    final labelW = _lineWidth(c, label, ResponsiveHelper.tinyStyle(context));
    return countW > labelW ? countW : labelW;
  }

  /// [DU305] 한 줄 필요폭 — `Text.build` 와 같은 유효 스타일로 잰다: inherit 이면 DefaultTextStyle 병합,
  ///   `MediaQuery.boldTextOf` 이면 굵게, 그리고 TextScaler·locale·방향·textWidthBasis·textHeightBehavior.
  ///   [c] 는 그 글자가 그려질 자리의 context(대화상자 Material 안)여야 한다.
  ///   화면 폭·글자 배율 임계값으로 나누지 않는다([DU303] 시각 줄 판정과 같은 방식).
  double _lineWidth(BuildContext c, String text, TextStyle style) {
    final dts = DefaultTextStyle.of(c);
    var effective = style.inherit ? dts.style.merge(style) : style;
    if (MediaQuery.boldTextOf(c)) {
      effective = effective.merge(const TextStyle(fontWeight: FontWeight.bold));
    }
    final tp = TextPainter(
      text: TextSpan(text: text, style: effective),
      textDirection: Directionality.of(c),
      textScaler: MediaQuery.textScalerOf(c),
      locale: Localizations.maybeLocaleOf(c),
      textWidthBasis: dts.textWidthBasis,
      textHeightBehavior: dts.textHeightBehavior,
      maxLines: 1,
    )..layout();
    final w = tp.maxIntrinsicWidth;
    tp.dispose();
    return w;
  }

  /// [DU305] 그룹 머리 아이콘 상자 안 글리프 폭 — `WorkTypeIcon.build` 의 세 경로를 그대로 따른다.
  ///   업무 정보 없음·Material 아이콘 → Icon(size) 폭 = size. 아이콘 문자열 없음 → 이름 첫 글자 Text(굵게),
  ///   이모지 → 그 문자열 Text — 둘 다 배율·굵게를 받으므로 [_lineWidth] 로 실측한다.
  double _workTypeGlyphWidth(BuildContext c, BusinessWorkTypeModel? info, double size) {
    if (info == null) return size;
    if (info.icon.isEmpty) {
      final first = info.name.isNotEmpty ? info.name.characters.first : '?';
      return _lineWidth(c, first, TextStyle(fontSize: size, fontWeight: FontWeight.bold));
    }
    if (WorkTypeIcon.isEmoji(info.icon)) {
      return _lineWidth(c, info.icon, TextStyle(fontSize: size));
    }
    return size;
  }

  /// [DU305] 시각 범위 표시 — 'A ~ B' 는 '~' 뒤에서만 줄을 바꾸고 각 시각 안에서는 끊지 않는다([TextLayout.range]).
  ///   범위가 아니면(시각 하나·'시간 N종 — 행에서 확인' 등) 원문 그대로다. 화면 읽기는 호출부가 원문을 준다.
  String _rangeDisplay(String s) {
    final i = s.indexOf(' ~ ');
    if (i <= 0 || s.indexOf(' ~ ', i + 3) >= 0) return s;
    return TextLayout.range(s.substring(0, i), s.substring(i + 3));
  }

  Widget _buildMiniDot(_StatChip c) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 6, height: 6, decoration: BoxDecoration(color: c.color, shape: BoxShape.circle)),
        const SizedBox(width: 3),
        Text('${c.label} ${c.count}건', style: ResponsiveHelper.tinyStyle(context, color: AppColors.grey600)),
      ],
    );
  }

  /// 일괄 처리 액션 바
  Widget _buildBatchActionBar(ThemeData theme) {
    // 서브어드민 권한 체크 — canManageWorkers=false이면 모든 조작 버튼 비활성화
    final canManage = Provider.of<UserProvider>(context, listen: false)
        .checkCurrentBusiness((p) => p.canManageWorkers) == PermissionCheck.allowed;

    int checkInCount = 0;
    int adjustCount = 0;
    int checkOutCount = 0;
    int resetCount = 0;

    for (final id in _selectedIds) {
      final app = _workerIdMap[id];
      if (app == null) continue;
      final s = _getAttendanceStatus(app)['status'] as String;
      final att = _attendanceMap[app.id];
      if (s == 'pending') {
        checkInCount++;
      } else {
        // final_confirmed / transferred 는 급여확정 완료 상태 — 시간 조정 불가이므로 카운트 제외
        if (s != 'final_confirmed' && s != 'transferred') {
          adjustCount++;
        }
        if (s == 'checkin' || s == 'late' || s == 'missed_checkout') checkOutCount++;
      }
      // [GAP-ATT-RESET-ABSENT-01] statusAbsent(결근) 근로자는 checkIn이 없어도 리셋 대상
      // _showBatchResetDialog H-3 설계와 일치: att.checkIn != null || att.status == statusAbsent
      // [ATTENDANCE-UNKNOWN-DEST.28] status 없음은 예전엔 결근으로 읽혀 리셋 대상이었다 — 그대로 둔다.
      if (att?.checkIn != null || att?.status == AttendanceModel.statusAbsent ||
          att?.status == AttendanceModel.statusUnconfirmed) {
        resetCount++;
      }
    }

    // 탭별 조건부 칩
    final tabWorkers = _tabWorkers[_currentTabIndex];
    // [R7-NOSHOW-ADMIN-ELIGIBILITY] 버튼이 서버보다 먼저 말하지 않게 한다.
    //   서버는 예정 시작 + 지각 유예 이후에만 미출근을 확정한다. 이전에는 이
    //   칩이 근무일 00:00부터 떠서, 시작 전에 눌러도 되는 것처럼 보였다.
    //   판정식을 새로 만들지 않고 서버와 같은 규칙 해석을 쓴다
    //   (`effectiveAttendanceRules` = snapshot 우선, 서버 srvEffectiveAttendanceRules).
    final noShowTargets = _currentTabIndex == 0
        ? tabWorkers.where((a) =>
            _getAttendanceStatus(a)['status'] == 'pending' && _noShowJudgeable(a)).toList()
        : <ApplicationModel>[];
    final cancelNoShowTargets = _currentTabIndex == 3
        ? tabWorkers.where((a) => _attendanceMap[a.id]?.status == AttendanceModel.statusNoShow).toList()
        : <ApplicationModel>[];

    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 4),
        vertical: ResponsiveHelper.spacing(context, 6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Row 1: 전체 선택 + 조건부 칩 + 검색
          Row(
            children: [
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _toggleSelectAll(!_selectAll),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AppCheckbox(value: _selectAll, onTap: () => _toggleSelectAll(!_selectAll)),
                    SizedBox(width: ResponsiveHelper.spacing(context, 6)),
                    Text('전체', style: ResponsiveHelper.smallStyle(context)),
                    Builder(builder: (ctx) {
                      // 현재 탭 workers 중 선택된 수만 표시
                      final tabSelectedCount = tabWorkers
                          .where((a) => _selectedIds.contains(a.id))
                          .length;
                      if (tabSelectedCount == 0) return const SizedBox.shrink();
                      return Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(width: ResponsiveHelper.spacing(context, 4)),
                          Container(
                            padding: EdgeInsets.symmetric(
                              horizontal: ResponsiveHelper.spacing(context, 6),
                              vertical: ResponsiveHelper.spacing(context, 2),
                            ),
                            decoration: BoxDecoration(
                              color: theme.primaryColor.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text('$tabSelectedCount',
                                style: ResponsiveHelper.tinyStyle(context, color: theme.primaryColor, fontWeight: FontWeight.bold)),
                          ),
                        ],
                      );
                    }),
                  ],
                ),
              ),
              const Spacer(),
              // 노쇼 칩 (검토 탭) — canManageWorkers 없는 서브어드민 숨김
              // [5A.1] 미래 날짜 노쇼 차단 — server future guard defense-in-depth
              if (noShowTargets.isNotEmpty && canManage &&
                  !_kstDay.isAfter(_todayKst))
                _buildActionChip(
                  label: '노쇼 (${noShowTargets.length})',
                  color: AppColors.error,
                  onTap: () => _showBatchNoShowDialog(noShowTargets),
                ),
              // 노쇼취소 칩 (완료 탭)
              if (cancelNoShowTargets.isNotEmpty && canManage)
                _buildActionChip(
                  label: '노쇼취소 (${cancelNoShowTargets.length})',
                  color: AppColors.brand,
                  onTap: () => _showBatchCancelNoShowDialog(cancelNoShowTargets),
                ),
              SizedBox(width: ResponsiveHelper.spacing(context, 6)),
              // 이름 검색 돋보기
              InkWell(
                onTap: () => setState(() {
                  _showSearch = !_showSearch;
                  if (!_showSearch) { _nameFilter = ''; _searchController.clear(); }
                }),
                borderRadius: BorderRadius.circular(6),
                child: Padding(
                  padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 4)),
                  child: Icon(
                    _showSearch ? Icons.search_off : Icons.search,
                    size: ResponsiveHelper.iconSize(context, 18),
                    color: _showSearch ? theme.primaryColor : AppColors.grey500,
                  ),
                ),
              ),
            ],
          ),

          // 검색 필드 (토글)
          if (_showSearch) ...[
            SizedBox(height: ResponsiveHelper.spacing(context, 6)),
            TextField(
              controller: _searchController,
              autofocus: true,
              style: ResponsiveHelper.tinyStyle(context),
              decoration: InputDecoration(
                hintText: '이름 검색',
                hintStyle: ResponsiveHelper.tinyStyle(context, color: AppColors.grey400),
                isDense: true,
                contentPadding: EdgeInsets.symmetric(
                  horizontal: ResponsiveHelper.spacing(context, 10),
                  vertical: ResponsiveHelper.spacing(context, 7),
                ),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: AppColors.border)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: AppColors.border)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: theme.primaryColor)),
                filled: true,
                fillColor: Colors.white,
                suffixIconConstraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                suffixIcon: _nameFilter.isNotEmpty
                    ? GestureDetector(
                        onTap: () => setState(() { _nameFilter = ''; _searchController.clear(); }),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          child: Icon(Icons.clear, size: ResponsiveHelper.iconSize(context, 14), color: AppColors.grey400),
                        ),
                      )
                    : null,
              ),
              onChanged: (v) => setState(() => _nameFilter = v.trim()),
            ),
          ],

          // 검토 탭에서 상태별 빠른 선택 칩
          if (_currentTabIndex == 0) ...[
            SizedBox(height: ResponsiveHelper.spacing(context, 6)),
            Builder(builder: (ctx) {
              final reviewWorkers = _tabWorkers[0];
              final pendingList = reviewWorkers.where((a) => _getAttendanceStatus(a)['status'] == 'pending').toList();
              final lateList    = reviewWorkers.where((a) => _getAttendanceStatus(a)['status'] == 'late').toList();
              final missedList  = reviewWorkers.where((a) => _getAttendanceStatus(a)['status'] == 'missed_checkout').toList();
              if (pendingList.isEmpty && lateList.isEmpty && missedList.isEmpty) return const SizedBox.shrink();
              return Wrap(
                spacing: ResponsiveHelper.spacing(context, 6),
                children: [
                  if (pendingList.isNotEmpty)
                    _buildActionChip(
                      label: '미출근 ${pendingList.length}건',
                      color: AppColors.warning,
                      onTap: () {
                        final grows = pendingList.any((a) => !_selectedIds.contains(a.id)); // [DU305] 선택이 늘 때만 맞춘다
                        setState(() {
                          _selectedIds.addAll(pendingList.map((a) => a.id));
                          _selectAll = _selectedIds.length >= reviewWorkers.length;
                        });
                        if (grows) _revealAfterSelection(list: true);
                      },
                    ),
                  if (lateList.isNotEmpty)
                    _buildActionChip(
                      label: '지각 ${lateList.length}건',
                      color: AppColors.error,
                      onTap: () {
                        final grows = lateList.any((a) => !_selectedIds.contains(a.id)); // [DU305] 선택이 늘 때만 맞춘다
                        setState(() {
                          _selectedIds.addAll(lateList.map((a) => a.id));
                          _selectAll = _selectedIds.length >= reviewWorkers.length;
                        });
                        if (grows) _revealAfterSelection(list: true);
                      },
                    ),
                  if (missedList.isNotEmpty)
                    _buildActionChip(
                      label: '퇴근미기록 ${missedList.length}건',
                      color: AppColors.warningDark,
                      onTap: () {
                        final grows = missedList.any((a) => !_selectedIds.contains(a.id)); // [DU305] 선택이 늘 때만 맞춘다
                        setState(() {
                          _selectedIds.addAll(missedList.map((a) => a.id));
                          _selectAll = _selectedIds.length >= reviewWorkers.length;
                        });
                        if (grows) _revealAfterSelection(list: true);
                      },
                    ),
                ],
              );
            }),
          ],

          SizedBox(height: ResponsiveHelper.spacing(context, 8)),

          // Row 2: 출근 / 조정 / 퇴근 / 리셋 — canManage=false·미래 날짜면 모두 비활성화
          // [5A.1] 미래 날짜 UX guard — server authority defense-in-depth
          Builder(builder: (ctx2) {
            final today = _todayKst;
            final isFutureDate = _kstDay.isAfter(today);
            return Column(
              children: [
                // 반응형 배치: LayoutBuilder 실측 후 분기
                // maxWidth < 380dp → 2×2 그리드 (폰 전체 범위)
                // maxWidth ≥ 380dp → 4열 (태블릿)
                // 근거: '시간 조정' 라벨이 폰 크기(320~430dp)에서 우측 오버플로우
                //   유발 (실측 5.5px @ 380dp). 레이아웃 전환이 font 축소보다 우선(§1).
                LayoutBuilder(builder: (_, constraints) {
                  final isNarrow = constraints.maxWidth < 380;

                  // [UI-3] 네 행동을 색 네 가지로 같은 무게로 두지 않는다 —
                  //   현재 단계(출근·퇴근)는 채움, 시간 조정은 테두리 보조, 리셋은
                  //   테두리 + 빨간 글자로 맨 끝에 둔다(확인 창은 그대로).
                  final ci = Expanded(child: _buildActionButton(icon: Icons.login,   label: '출근',     role: _BatchRole.step,        count: checkInCount,  onPressed: (checkInCount  > 0 && canManage && !isFutureDate) ? _showBatchCheckInDialog    : null));
                  final ad = Expanded(child: _buildActionButton(icon: Icons.tune,    label: '시간 조정', role: _BatchRole.secondary,   count: adjustCount,   onPressed: (adjustCount   > 0 && canManage && !isFutureDate) ? _showBatchAdjustTimeDialog : null));
                  final co = Expanded(child: _buildActionButton(icon: Icons.logout,  label: '퇴근',     role: _BatchRole.step,        count: checkOutCount, onPressed: (checkOutCount > 0 && canManage && !isFutureDate) ? _showBatchCheckOutDialog   : null));
                  final rs = Expanded(child: _buildActionButton(icon: Icons.refresh, label: '리셋',     role: _BatchRole.destructive, count: resetCount,    onPressed: (resetCount    > 0 && canManage && !isFutureDate) ? _showBatchResetDialog     : null));

                  if (isNarrow) {
                    // 2×2 그리드: 각 버튼이 절반 폭을 차지해 '시간 조정' 완전 표시
                    //   윗줄 = 단계 행동(출근·퇴근), 아랫줄 = 보조(시간 조정)·위험(리셋)
                    return Column(mainAxisSize: MainAxisSize.min, children: [
                      // [DU305] 선택 직후 맞춤 대상 — 단계 행동(출근·퇴근) 줄
                      KeyedSubtree(
                        key: _batchStepRowKey,
                        child: Row(children: [
                          ci,
                          SizedBox(width: ResponsiveHelper.spacing(context, 5)),
                          co,
                        ]),
                      ),
                      SizedBox(height: ResponsiveHelper.spacing(context, 5)),
                      Row(children: [
                        ad,
                        SizedBox(width: ResponsiveHelper.spacing(context, 5)),
                        rs,
                      ]),
                    ]);
                  }
                  // 4열 (태블릿): Flexible 안전망이 _buildActionButton 내부에 적용됨
                  // [DU305] 선택 직후 맞춤 대상 — 네 행동이 한 줄
                  return KeyedSubtree(
                    key: _batchStepRowKey,
                    child: Row(children: [
                      ci,
                      SizedBox(width: ResponsiveHelper.spacing(context, 5)),
                      co,
                      SizedBox(width: ResponsiveHelper.spacing(context, 5)),
                      ad,
                      SizedBox(width: ResponsiveHelper.spacing(context, 5)),
                      rs,
                    ]),
                  );
                }),
                if (isFutureDate) ...[
                  SizedBox(height: ResponsiveHelper.spacing(context, 4)),
                  Text(
                    '근무일 당일부터 근태 처리가 가능합니다.',
                    style: ResponsiveHelper.smallStyle(context, color: AppColors.grey500),
                    textAlign: TextAlign.center,
                  ),
                ],
              ],
            );
          }),
        ],
      ),
    );
  }

  Widget _buildActionChip({required String label, required Color color, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: ResponsiveHelper.spacing(context, 8),
          vertical: ResponsiveHelper.spacing(context, 4),
        ),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Text(label, style: ResponsiveHelper.tinyStyle(context, color: color, fontWeight: FontWeight.bold)),
      ),
    );
  }

  /// 액션 버튼
  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required _BatchRole role,
    int count = 0,
    VoidCallback? onPressed,
  }) {
    final isEnabled = onPressed != null;
    final color = switch (role) {
      _BatchRole.step => Colors.white,
      _BatchRole.secondary => AppColors.textPrimary,
      _BatchRole.destructive => AppColors.errorDark,
    };
    final bg = !isEnabled
        ? AppColors.grey100
        : role == _BatchRole.step
            ? AppColors.brand
            : Colors.white;
    final border = !isEnabled || role == _BatchRole.step
        ? BorderSide.none
        : BorderSide(
            color: role == _BatchRole.destructive
                ? AppColors.errorDark.withValues(alpha: 0.5)
                : AppColors.grey300);

    return Material(
      color: bg,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8), side: border),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: ResponsiveHelper.spacing(context, 8),
            vertical: ResponsiveHelper.spacing(context, 8),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    icon,
                    size: ResponsiveHelper.iconSize(context, 15),
                    color: isEnabled ? color : AppColors.grey400,
                  ),
                  SizedBox(width: ResponsiveHelper.spacing(context, 4)),
                  // Flexible: 4열 레이아웃에서 긴 라벨('시간 조정' 등)이
                  // Row 경계를 넘지 않도록 수축 허용 (안전망 — 주요 fix는 2×2 전환)
                  Flexible(
                    child: Text(
                      label,
                      style: ResponsiveHelper.smallStyle(
                        context,
                        color: isEnabled ? color : AppColors.grey400,
                      ).copyWith(fontWeight: FontWeight.w600),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  ),
                ],
              ),
              if (_selectedIds.isNotEmpty) ...[
                SizedBox(height: ResponsiveHelper.spacing(context, 3)),
                Text(
                  isEnabled ? '$count건' : '0건',
                  style: ResponsiveHelper.tinyStyle(
                    context,
                    color: isEnabled ? color : AppColors.grey400,
                  ).copyWith(fontWeight: FontWeight.bold),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// 시간 문자열 정규화 — HH:mm 앞 5자리만 사용 (HH:mm:ss 형식 차이 제거)
  String _normalizeTimeKey(String t) {
    final s = t.trim();
    return s.length >= 5 ? s.substring(0, 5) : s;
  }

  /// 업무별 그룹
  Widget _buildWorkTypeGroups(ThemeData theme, {List<ApplicationModel>? workers}) {
    // ✅ workType + 시간 조합으로 그룹화 (장기/단기 합침)
    final Map<String, List<ApplicationModel>> workTypeGroups = {};

    final sourceWorkers = workers ?? _confirmedWorkers;
    final filteredSource = _nameFilter.isEmpty
        ? sourceWorkers
        : sourceWorkers.where((app) {
            final name = _userMap[app.uid]?.name ?? '';
            return name.contains(_nameFilter);
          }).toList();

    for (var app in filteredSource) {
      // [5B.2B] canonical group identity — Root 5B.1B와 동일 원칙.
      // workType_startTime_endTime 단독 key는 동일 business 내 다른 TO(다른 toId)가
      // 같은 workType·시간대를 가질 경우 cross-TO merge를 유발.
      //
      // canonical: businessId | toId | slotId | workDetailId
      // legacy fallback (toId 없음): businessId | workType_startTime_endTime | '' | ''
      final normStart = _normalizeTimeKey(app.startTime);
      final normEnd   = _normalizeTimeKey(app.endTime);
      final toSeg = app.toId ?? '${app.selectedWorkType.trim()}_${normStart}_$normEnd';
      final slotSeg = app.slotId ?? '';
      final wdSeg = app.workDetailId ?? '';
      final groupKey = '${app.businessId}|$toSeg|$slotSeg|$wdSeg';

      workTypeGroups.putIfAbsent(groupKey, () => []);
      workTypeGroups[groupKey]!.add(app);
    }

    // 업무명 → 시작시간 → 종료시간 순 정렬
    final sortedEntries = workTypeGroups.entries.toList()
      ..sort((a, b) {
        final appA = a.value.first;
        final appB = b.value.first;

        final typeCompare = appA.selectedWorkType.compareTo(appB.selectedWorkType);
        if (typeCompare != 0) return typeCompare;

        final timeCompare = AttendanceStatusHelper.timeToMinutes(appA.startTime)
            .compareTo(AttendanceStatusHelper.timeToMinutes(appB.startTime));
        if (timeCompare != 0) return timeCompare;

        return AttendanceStatusHelper.timeToMinutes(appA.endTime)
            .compareTo(AttendanceStatusHelper.timeToMinutes(appB.endTime));
      });

    return Column(
      children: sortedEntries.map((entry) {
        final firstApp = entry.value.first;
        return Padding(
          padding: EdgeInsets.only(bottom: ResponsiveHelper.spacing(context, 12)),
          child: _buildWorkTypeSection(
            theme,
            firstApp.selectedWorkType,
            entry.value,
            groupKey: entry.key,
            startTime: _normalizeTimeKey(firstApp.startTime),
            endTime: _normalizeTimeKey(firstApp.endTime),
          ),
        );
      }).toList(),
    );
  }

  /// [R7-P1-3] 이 그룹에 **서로 다른 관계**가 섞여 있는가.
  ///
  ///   그룹 키의 조각은 `workDetailId` 이고, 그것이 없는 구 문서는 빈 문자열이
  ///   되어 같은 슬롯의 다른 업무가 한 그룹으로 합쳐진다. 그때 헤더가 첫 관계의
  ///   업무명만 말하면 나머지 행이 그 업무인 것처럼 읽히고, 행끼리도 구별되지
  ///   않는다(미출근 행은 시간 표시가 없다).
  ///   섞였는지는 **그 그룹이 실제로 들고 있는 값**으로만 판단한다.
  bool _isMixedRelationGroup(List<ApplicationModel> workers) {
    if (workers.length < 2) return false;
    final types = workers
        .map((a) => a.selectedWorkType.trim())
        .where((t) => t.isNotEmpty)
        .toSet();
    final ranges = workers.map(_scheduledRangeOf).where((r) => r.isNotEmpty).toSet();
    return types.length > 1 || ranges.length > 1;
  }

  /// [R7-P1-3] 그 관계의 **예정 근무시간** — 모르면 빈 문자열.
  ///
  ///   `WorkDetailHelper.effectiveStart/End` 는 값이 없을 때 '09:00'·'18:00' 을
  ///   돌려준다(입력 기본값 용도). 여기서는 사실 표시라서 그 기본값을 쓰지 않는다 —
  ///   모르는 것을 시간처럼 보여주지 않는다.
  String _scheduledRangeOf(ApplicationModel app) {
    final resolved = WorkDetailHelper.resolve(app, _workDetailTimeMap);
    final rs = (resolved?['startTime'] as String?)?.trim() ?? '';
    final re = (resolved?['endTime'] as String?)?.trim() ?? '';
    final st = rs.isNotEmpty ? rs : app.startTime.trim();
    final en = re.isNotEmpty ? re : app.endTime.trim();
    if (st.isEmpty || en.isEmpty) return '';
    return '$st ~ $en';
  }

  /// [R7-P1-3] 혼합 그룹의 행에 붙이는 문맥 — 업무명 · 예정 시간.
  ///   없는 값은 추정하지 않고 모른다고 적는다.
  String _relationContextOf(ApplicationModel app) {
    final type = app.selectedWorkType.trim();
    final range = _scheduledRangeOf(app);
    final typeLabel = type.isNotEmpty ? type : '업무 정보 없음';
    final rangeLabel = range.isNotEmpty ? range : '예정 시간 정보 없음';
    return '$typeLabel · $rangeLabel';
  }

  /// 업무 유형 섹션
  Widget _buildWorkTypeSection(
    ThemeData theme,
    String workType,
    List<ApplicationModel> workers, {
    required String groupKey,
    String? startTime,
    String? endTime,
  }) {
    // 정렬 모드: 0=상태순, 1=배지순, 2=이름순
    final sortMode = _groupSortMode[groupKey] ?? 0;
    final sortedWorkers = [...workers];
    switch (sortMode) {
      case 2: // 이름순
        sortedWorkers.sort((a, b) {
          final na = _userMap[a.uid]?.name ?? '';
          final nb = _userMap[b.uid]?.name ?? '';
          return na.compareTo(nb);
        });
        break;
      case 1: // 배지순 (배지 무게 높을수록 상단)
        sortedWorkers.sort((a, b) {
          final wa = _badgeWeight(a);
          final wb = _badgeWeight(b);
          if (wa != wb) return wb.compareTo(wa); // 무게 내림차순
          final na = _userMap[a.uid]?.name ?? '';
          final nb = _userMap[b.uid]?.name ?? '';
          return na.compareTo(nb);
        });
        break;
      default: // 0: 상태순 (처리 필요 순)
        sortedWorkers.sort((a, b) {
          final pa = _workerSortPriority(a);
          final pb = _workerSortPriority(b);
          if (pa != pb) return pa.compareTo(pb);
          // 동일 상태면 배지 무게 내림차순 (복잡한 케이스 우선)
          final wa = _badgeWeight(a);
          final wb = _badgeWeight(b);
          if (wa != wb) return wb.compareTo(wa);
          final na = _userMap[a.uid]?.name ?? '';
          final nb = _userMap[b.uid]?.name ?? '';
          return na.compareTo(nb);
        });
    }
    // ✅ 파라미터로 받은 시간 우선 사용
    String timeStr = '';
    if (startTime != null && startTime.isNotEmpty && 
        endTime != null && endTime.isNotEmpty) {
      timeStr = '$startTime ~ $endTime';
    }
    
    // 폴백: WorkDetail에서 시간 조회 (composite key 우선, workType 폴백)
    if (timeStr.isEmpty) {
      final compositeKey = startTime != null && endTime != null
          ? '${workType}_${startTime}_$endTime'
          : null;
      final workDetailTime = (compositeKey != null ? _workDetailTimeMap[compositeKey] : null)
          ?? _workDetailTimeMap[workType];
      if (workDetailTime != null) {
        final wdStartTime = workDetailTime['startTime'] ?? '';
        final wdEndTime = workDetailTime['endTime'] ?? '';
        if (wdStartTime.isNotEmpty && wdEndTime.isNotEmpty) {
          timeStr = '$wdStartTime ~ $wdEndTime';
        }
      }
    }
    
    // 최종 폴백: Application에서 시간 정보 가져오기
    // isNotEmpty 가드 내부 — workers.first 안전
    if (timeStr.isEmpty && workers.isNotEmpty) {
      final firstApp = workers.first;
      if (firstApp.startTime.isNotEmpty && firstApp.endTime.isNotEmpty) {
        timeStr = '${firstApp.startTime} ~ ${firstApp.endTime}';
      }
    }
    
    // [R7-P1-3] 혼합 그룹이면 제목·시간을 첫 관계로 말하지 않는다.
    //   개수는 그 그룹이 들고 있는 값에서 센다 — 없는 정보를 만들지 않는다.
    final isMixedGroup = _isMixedRelationGroup(workers);
    final mixedTypeCount = workers
        .map((a) => a.selectedWorkType.trim())
        .where((t) => t.isNotEmpty)
        .toSet()
        .length;
    final mixedRangeCount =
        workers.map(_scheduledRangeOf).where((r) => r.isNotEmpty).toSet().length;
    final headerTitle =
        (isMixedGroup && mixedTypeCount > 1) ? '여러 업무 $mixedTypeCount종' : workType;
    final headerTime = (isMixedGroup && mixedRangeCount > 1)
        ? '시간 $mixedRangeCount종 — 행에서 확인'
        : timeStr;

    // 업무유형 정보 가져오기
    final workTypeInfo = _workTypeMap[workType];
    final iconColor = workTypeInfo?.color != null 
        ? FormatHelper.parseColor(workTypeInfo!.color!)
        : theme.primaryColor;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.grey200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 업무 유형 헤더
          Builder(builder: (ctx) {
            // 파트 내 출근 현황 계산
            final checkedInCount = workers.where((a) {
              final s = _getAttendanceStatus(a)['status'] as String;
              return s != 'pending' && s != 'noshow';
            }).length;
            final noShowCount = workers.where((a) {
              return (_getAttendanceStatus(a)['status'] as String) == 'noshow';
            }).length;
            final selectableWorkers = workers.where((a) {
              return (_getAttendanceStatus(a)['status'] as String) != 'noshow';
            }).toList();
            final allSelected = selectableWorkers.isNotEmpty &&
                selectableWorkers.every((a) => _selectedIds.contains(a.id));

            final attendBadgeColor = checkedInCount == workers.length - noShowCount
                ? AppColors.success
                : checkedInCount > 0
                    ? AppColors.warning
                    : AppColors.grey500;

            return GestureDetector(
              onTap: () {
                setState(() {
                  if (allSelected) {
                    for (final a in selectableWorkers) { _selectedIds.remove(a.id); }
                  } else {
                    for (final a in selectableWorkers) { _selectedIds.add(a.id); }
                  }
                  // [BUG-FIX] 그룹 선택 후 _selectAll은 현재 탭의 selectable workers 기준으로 계산
                  // (_confirmedWorkers 전체 기준이면 탭 필터에 따라 checkbox 상태 불일치 발생)
                  final tabSelectable = _tabWorkers[_currentTabIndex]
                      .where((a) => (_getAttendanceStatus(a)['status'] as String) != 'noshow')
                      .toList();
                  _selectAll = tabSelectable.isNotEmpty &&
                      tabSelectable.every((a) => _selectedIds.contains(a.id));
                });
                // [DU305] 그룹을 선택했으면 처리 진입(일괄 버튼 첫 줄)만 맞춘다 — 목록은 사용자가 보고 있는 그 자리다.
                if (!allSelected) _revealAfterSelection(list: false);
              },
              child: Container(
                padding: EdgeInsets.symmetric(
                  horizontal: ResponsiveHelper.spacing(context, 12),
                  vertical: ResponsiveHelper.spacing(context, 10),
                ),
                decoration: const BoxDecoration(
                  color: AppColors.grey50,
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(12),
                    topRight: Radius.circular(12),
                  ),
                ),
                // [DU305] 출근·정렬 칩 열을 제목 오른쪽에 둘 때 시간 문구가 한 줄로 들어가면 지금 배치 그대로다.
                //   안 들어가면(B320·배율 2.0 관측: 시간이 '22:30 / ~ / 23:30' 세 줄로 갈림) 두 칩을
                //   제목·시간 아래 한 줄로 내린다 — 글자·문구·색·정보·탭 동작은 그대로, 배치만 바꾼다.
                //   시간 범위는 '~' 뒤에서만 줄을 바꾼다([_rangeDisplay]). 폭 판정은 실제 렌더와 같은 유효 스타일로
                //   잰 값이다([_lineWidth]·[_workTypeGlyphWidth]). 화면 폭·배율 임계값으로 나누지 않는다.
                child: LayoutBuilder(builder: (lctx, hc) {
                  final sm = _groupSortMode[groupKey] ?? 0;
                  const labels = ['상태순', '배지순', '이름순'];
                  const icons  = [Icons.swap_vert, Icons.filter_list, Icons.sort_by_alpha];
                  final isActive = sm != 0;
                  final badgeText = '출근 $checkedInCount/${workers.length - noShowCount}';
                  final badgeStyle = ResponsiveHelper.tinyStyle(context, color: attendBadgeColor)
                      .copyWith(fontWeight: FontWeight.bold);
                  final sortStyle = ResponsiveHelper.tinyStyle(
                    context,
                    color: isActive ? theme.primaryColor : AppColors.grey500,
                  ).copyWith(fontWeight: FontWeight.w600);
                  final timeStyle = ResponsiveHelper.smallStyle(context, color: AppColors.grey600);
                  final timeShown = _rangeDisplay(headerTime);
                  final glyphSize = ResponsiveHelper.iconSize(context, 14);

                  final lead = <Widget>[
                    // 파트 체크박스
                    AppCheckbox(value: allSelected),
                    SizedBox(width: ResponsiveHelper.spacing(context, 10)),
                    // 업무유형 아이콘 (소형)
                    Container(
                      padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 4)),
                      decoration: BoxDecoration(
                        color: iconColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: workTypeInfo != null
                          ? WorkTypeIcon.build(
                              workTypeInfo,
                              color: iconColor,
                              size: glyphSize,
                            )
                          : Icon(
                              Icons.work_outline,
                              color: iconColor,
                              size: glyphSize,
                            ),
                    ),
                    SizedBox(width: ResponsiveHelper.spacing(context, 10)),
                  ];
                  final titleCol = Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          headerTitle,
                          style: ResponsiveHelper.subtitleStyle(context).copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (headerTime.isNotEmpty)
                          Text(
                            timeShown,
                            semanticsLabel: headerTime,
                            style: timeStyle,
                          ),
                      ],
                    ),
                  );
                  // 출근 현황 배지
                  final badge = Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: ResponsiveHelper.spacing(context, 10),
                      vertical: ResponsiveHelper.spacing(context, 5),
                    ),
                    decoration: BoxDecoration(
                      color: attendBadgeColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: attendBadgeColor.withValues(alpha: 0.4)),
                    ),
                    child: Text(badgeText, style: badgeStyle),
                  );
                  // 정렬 토글 버튼 (탭마다 순환: 상태순→배지순→이름순)
                  final sortToggle = GestureDetector(
                    onTap: () => setState(() =>
                        _groupSortMode[groupKey] = (sm + 1) % 3),
                    child: Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: ResponsiveHelper.spacing(context, 7),
                        vertical: ResponsiveHelper.spacing(context, 4),
                      ),
                      decoration: BoxDecoration(
                        color: isActive
                            ? theme.primaryColor.withValues(alpha: 0.12)
                            : Colors.white,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: isActive
                              ? theme.primaryColor.withValues(alpha: 0.4)
                              : AppColors.border,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            icons[sm],
                            size: ResponsiveHelper.iconSize(context, 11),
                            color: isActive ? theme.primaryColor : AppColors.grey500,
                          ),
                          SizedBox(width: ResponsiveHelper.spacing(context, 3)),
                          Text(labels[sm], style: sortStyle),
                        ],
                      ),
                    ),
                  );

                  // 한 줄 판정: 앞부분(체크박스 Icon + 간격 + 아이콘 상자 + 간격) + 시간 한 줄 + 칩 열(넓은 칩) ≤ 머리 폭.
                  //   칩 폭 = 좌우 padding + 테두리 1+1 + 내용. 가운데 열 폭은 Row 가 정확히 이 차이로 준다.
                  final leadW = ResponsiveHelper.iconSize(context, 22) +
                      ResponsiveHelper.spacing(context, 10) * 2 +
                      ResponsiveHelper.spacing(context, 4) * 2 +
                      _workTypeGlyphWidth(lctx, workTypeInfo, glyphSize);
                  final badgeW = ResponsiveHelper.spacing(context, 10) * 2 + 2 +
                      _lineWidth(lctx, badgeText, badgeStyle);
                  final sortW = ResponsiveHelper.spacing(context, 7) * 2 + 2 +
                      ResponsiveHelper.iconSize(context, 11) + ResponsiveHelper.spacing(context, 3) +
                      _lineWidth(lctx, labels[sm], sortStyle);
                  final chipsW = badgeW > sortW ? badgeW : sortW;
                  final timeW = headerTime.isEmpty ? 0.0 : _lineWidth(lctx, timeShown, timeStyle);
                  final rowFits = leadW + timeW + chipsW <= hc.maxWidth;

                  if (rowFits) {
                    return Row(
                      children: [
                        ...lead,
                        titleCol,
                        // 출근현황 + 전체확인/취소 칩 + 정렬 토글
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            badge,
                            SizedBox(height: ResponsiveHelper.spacing(context, 6)),
                            sortToggle,
                          ],
                        ),
                      ],
                    );
                  }
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [...lead, titleCol]),
                      SizedBox(height: ResponsiveHelper.spacing(context, 6)),
                      Wrap(
                        spacing: ResponsiveHelper.spacing(context, 6),
                        runSpacing: ResponsiveHelper.spacing(context, 4),
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [badge, sortToggle],
                      ),
                    ],
                  );
                }),
              ),
            );
          }),

          // 근무자 목록
          Padding(
            padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 8)),
            child: Column(
              children: sortedWorkers
                  .map((app) =>
                      _buildWorkerCard(app, showRelationContext: isMixedGroup))
                  .toList(),
            ),
          ),
        ],
      ),
    );
  }

  /// 퇴근 미처리 여부: 출근은 했으나 퇴근 미처리 + 예정 퇴근시간 초과
  bool _isMissedCheckout(ApplicationModel app) {
    final s = _getAttendanceStatus(app)['status'] as String;
    if (s != 'checkin' && s != 'late') return false;
    final effEnd = WorkDetailHelper.effectiveEnd(app, _workDetailTimeMap);
    if (effEnd.isEmpty) return false;
    final parts = effEnd.split(':');
    if (parts.length != 2) return false;
    final endH = int.tryParse(parts[0]);
    final endM = int.tryParse(parts[1]);
    if (endH == null || endM == null) return false;
    // _kstDay 기준으로 퇴근 예정시각 계산 (야간 자정 넘김 보정)
    final workDay = _kstDay;
    var endAt = DateTime(workDay.year, workDay.month, workDay.day, endH, endM);
    final effStart = WorkDetailHelper.effectiveStart(app, _workDetailTimeMap);
    final startParts = effStart.split(':');
    final startH = int.tryParse(startParts.first) ?? 0;
    final startM = startParts.length > 1 ? (int.tryParse(startParts[1]) ?? 0) : 0;
    if (endH < startH || (endH == startH && endM < startM)) endAt = endAt.add(const Duration(days: 1));
    return DateTime.now().isAfter(endAt);
  }

  /// 근무자 카드
  Widget _buildWorkerCard(ApplicationModel app,
      {bool showRelationContext = false}) {
    final theme = Theme.of(context);
    final statusInfo = _getAttendanceStatus(app);
    final isSelected = _selectedIds.contains(app.id);
    // [5B.2A] focused mode — 진입 시 해당 application 강조 (5초 후 자동 해제는 미구현, 탭 이동으로 맥락 제공)
    final isFocused = _highlightedAppId == app.id;
    final displayName = _getDisplayName(app.uid);
    final genderAge = _getGenderAge(app.uid);
    final overdueCheckout = _isMissedCheckout(app);
    // [DU305] 현재 탭에서 화면 순서상 첫 선택 카드 — 선택 직후 목록 맞춤 대상([_revealAfterSelection]).
    final isFirstSelected = isSelected && _firstSelectedPending;
    if (isFirstSelected) _firstSelectedPending = false;

    return KeyedSubtree(
      key: isFirstSelected ? _firstSelectedCardKey : null,
      child: Container(
      // [5B.2B] focused card에 GlobalKey 부여 → Scrollable.ensureVisible 대상
      key: isFocused ? _focusedCardKey : null,
      margin: EdgeInsets.only(bottom: ResponsiveHelper.spacing(context, 6)),
      decoration: BoxDecoration(
        color: isSelected
            ? theme.primaryColor.withValues(alpha: 0.08)
            : isFocused
                ? AppColors.info.withValues(alpha: 0.06)
                : overdueCheckout
                    ? AppColors.warning.withValues(alpha: 0.04)
                    : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isSelected
              ? theme.primaryColor
              : isFocused
                  ? AppColors.info
                  : overdueCheckout
                      ? AppColors.warning.withValues(alpha: 0.6)
                      : AppColors.border,
          width: isSelected || isFocused || overdueCheckout ? 1.5 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            final user = _userMap[app.uid];
            if (user != null) {
              final statusInfo = _getAttendanceStatus(app);
              WorkerDetailDialog.show(
                context: context,
                user: user,
                application: app,
                businessId: _selectedBusinessId,
                isConfirmed: true,
                showApprovalButtons: false,
                attendanceStatus: statusInfo['status'] as String,
                onStatusChanged: () {
                  _hasChanges = true;
                  _loadData();
                },
              );
            }
          },
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: ResponsiveHelper.spacing(context, 12),
              vertical: ResponsiveHelper.spacing(context, 8),
            ),
            // [DU584b r2 · 판정172 §4 (가)] 노쇼 결원 복구 행동 = 카드 줄(체크박스 · 정보 · 확인/취소) 아래 카드 안 다음 줄 · 카드 안쪽 전체 폭(_withRecoveryLine).
            child: _withRecoveryLine(app, statusInfo['status'] == 'noshow' && !app.isStaffingReleased, Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // 체크박스 — GestureDetector로 격리하여 카드 탭과 분리
                // [DU305 후속 ①] 누름 영역을 최소 48×48 로(불투명). 체크 그림의 위치·크기는 그대로(왼쪽 padding 유지)이고,
                //   늘어난 영역이 예전 뒤 간격(8s)을 대신하므로 그 간격은 뺀다. 카드 보기 탭은 이 영역 밖에서 그대로다.
                GestureDetector(
                  onTap: () => _toggleSelection(app.id),
                  behavior: HitTestBehavior.opaque,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      widthFactor: 1,
                      heightFactor: 1,
                      child: Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: ResponsiveHelper.spacing(context, 8),
                          vertical: ResponsiveHelper.spacing(context, 10),
                        ),
                        child: AppCheckbox(value: isSelected),
                      ),
                    ),
                  ),
                ),

                // 정보
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 장기 태그 + 이름 + 성별/나이
                      Row(
                        children: [
                          // 장기 배지 (이름 앞에)
                          if (app.isLongTermApplication) ...[
                            Container(
                              padding: EdgeInsets.symmetric(
                                horizontal: ResponsiveHelper.spacing(context, 6),
                                vertical: ResponsiveHelper.spacing(context, 2),
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.longTermBg,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                '장기',
                                style: ResponsiveHelper.tinyStyle(
                                  context,
                                  color: AppColors.longTermDark,
                                ).copyWith(fontWeight: FontWeight.bold),
                              ),
                            ),
                            SizedBox(width: ResponsiveHelper.spacing(context, 6)),
                          ],
                          // [COMMON-TEXT-LAYOUT.28] 이름 + (인력번호·나이, 성별) 을 한 문단으로 — 이름은 말줄임하지 않는다.
                          //   320dp·글자 1.3 에서 괄호가 폭을 먼저 차지해 이름이 '합성 …' 이 됐다.
                          //   괄호는 한 덩어리로 다음 줄로 넘어간다.
                          Expanded(
                            child: Text.rich(
                              TextSpan(children: [
                                TextSpan(
                                  text: TextLayout.identity(displayName),
                                  semanticsLabel: displayName,
                                  style: ResponsiveHelper.bodyStyle(context).copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                if (genderAge.isNotEmpty)
                                  TextSpan(
                                    text: ' ${genderAge.replaceAll(' ', '\u00A0')}',
                                    semanticsLabel: ' $genderAge',
                                    style: ResponsiveHelper.smallStyle(context, color: AppColors.grey600),
                                  ),
                              ]),
                            ),
                          ),
                        ],
                      ),

                      // [R7-P1-3] Row 1.5: 관계 문맥 — 혼합 그룹에서만.
                      //   미출근 행은 아래 '시간 정보' 가 비어 있어서, 같은 사람의
                      //   다른 관계와 구별할 단서가 없었다. 그 그룹에서만 붙인다.
                      if (showRelationContext)
                        Padding(
                          padding: EdgeInsets.only(
                              top: ResponsiveHelper.spacing(context, 3)),
                          child: Row(
                            children: [
                              Icon(Icons.work_outline,
                                  size: ResponsiveHelper.iconSize(context, 13),
                                  color: AppColors.grey500),
                              SizedBox(width: ResponsiveHelper.spacing(context, 4)),
                              Expanded(
                                child: Text(
                                  _relationContextOf(app),
                                  style: ResponsiveHelper.smallStyle(context,
                                      color: AppColors.grey600),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),

                      // Row 2: 시간 정보
                      Builder(builder: (context) {
                        final timeText = statusInfo['timeText'] as String?;
                        final attendance = _attendanceMap[app.id];
                        if (timeText == null) return const SizedBox.shrink();
                        return Padding(
                          padding: EdgeInsets.only(top: ResponsiveHelper.spacing(context, 4)),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    Icons.access_time,
                                    size: ResponsiveHelper.iconSize(context, 13),
                                    color: AppColors.grey500,
                                  ),
                                  SizedBox(width: ResponsiveHelper.spacing(context, 4)),
                                  // [DU305] 출퇴근 시각 범위를 말줄임으로 숨기지 않는다(Standards §3, B320·2.0 관측 '06:00 ···').
                                  //   줄은 '~' 뒤에서만 바꾸고 시각 안에서는 끊지 않는다. 화면 읽기·검색은 원문이다.
                                  Flexible(
                                    child: Text(
                                      _rangeDisplay(timeText),
                                      semanticsLabel: timeText,
                                      style: ResponsiveHelper.smallStyle(context, color: AppColors.grey600),
                                    ),
                                  ),
                                ],
                              ),
                              if (attendance != null &&
                                  (attendance.originalCheckIn != null ||
                                   attendance.originalCheckOut != null ||
                                   attendance.isModified == true))
                                Padding(
                                  padding: EdgeInsets.only(
                                    top: ResponsiveHelper.spacing(context, 2),
                                    left: ResponsiveHelper.spacing(context, 17),
                                  ),
                                  child: _buildOriginalTimeHint(attendance),
                                ),
                            ],
                          ),
                        );
                      }),

                      SizedBox(height: ResponsiveHelper.spacing(context, 4)),

                      // Row 3: 상태 배지 + 추가 플래그 배지
                      Wrap(
                        spacing: ResponsiveHelper.spacing(context, 6),
                        runSpacing: ResponsiveHelper.spacing(context, 4),
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          // 메인 상태 배지 (출근/퇴근/급여확정/최종확정 등)
                          _buildMainStatusBadge(statusInfo, theme),

                          // [ATTENDANCE-UNKNOWN-DEST.28] 기록된 근태 상태가 없다 — 통계의 '근태 확인 필요'와 같은 말.
                          //   위 배지는 출퇴근 시각으로 고른 것이라, 상태가 없다는 사실은 따로 둔다(추정하지 않는다).
                          if (_attendanceMap[app.id]?.status == AttendanceModel.statusUnconfirmed)
                            Container(
                              key: ValueKey('att-unconfirmed-${app.id}'),
                              padding: EdgeInsets.symmetric(
                                horizontal: ResponsiveHelper.spacing(context, 5),
                                vertical: ResponsiveHelper.spacing(context, 2),
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.purple.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text('근태 확인 필요',
                                  softWrap: false,
                                  style: ResponsiveHelper.tinyStyle(context,
                                      color: AppColors.purple, fontWeight: FontWeight.w600)),
                            ),

                          // 계약서 서명 상태 배지 (미작성·서명대기만 표시)
                          _buildContractBadge(app.id),

                          // 리컨펌 상태 배지 (출근확인/미응답)
                          _buildReconfirmBadge(app),

                          // 추가 플래그 배지 (지각/조퇴/연장/심야)
                          ..._buildExtraBadges(app),

                          // 출근 방식 배지 (GPS/비콘/수동)
                          _buildCheckInMethodBadge(_attendanceMap[app.id]),

                          // GPS 의심 출근 배지 (CF 서버 검증 결과)
                          if (_attendanceMap[app.id]?.checkInSuspicious == true)
                            _buildCheckInSuspiciousBadge(_attendanceMap[app.id]!),

                          // [R5.2] 대체 충원 진행 중 배지 — staffingReleasedAt 설정된 NO_SHOW
                          if (statusInfo['status'] == 'noshow' && app.isStaffingReleased)
                            _buildStaffingReleasedBadge(),

                          // 퇴근 미처리 경고 배지
                          if (overdueCheckout)
                            Container(
                              padding: EdgeInsets.symmetric(
                                horizontal: ResponsiveHelper.spacing(context, 7),
                                vertical: ResponsiveHelper.spacing(context, 2),
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.warning.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(
                                    color: AppColors.warning.withValues(alpha: 0.4)),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.warning_amber_rounded,
                                      size: ResponsiveHelper.iconSize(context, 11),
                                      color: AppColors.warning),
                                  SizedBox(width: ResponsiveHelper.spacing(context, 3)),
                                  Text(
                                    '퇴근 미처리',
                                    style: ResponsiveHelper.tinyStyle(context,
                                            color: AppColors.warning)
                                        .copyWith(fontWeight: FontWeight.w600),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),

                      // [DU584b r2] 결원 복구 행동(같은 조건 · 같은 _buildNoshowRecoveryButton)은 정보 열 밖 카드 다음 줄로 옮겼다 — _withRecoveryLine.
                    ],
                  ),
                ),

                // 확인/취소 버튼
                _buildConfirmButton(app),
              ],
            )),
          ),
        ),
      ),
    ),
    );
  }

  // [R5.2] NO_SHOW 대체 인력 충원 행동 줄 — 조건: status==noshow + !released(그 밖 !longTerm · canManageTo · 당일 · 모집 단위 열림은 _buildNoshowRecoveryButton 안).
  // [DU584b r2 · 판정172 §4 (가) · F172-B-OATT-ACTION-VIS] 행동은 카드 줄(체크박스 · 정보 · 확인/취소) 아래 카드 안 다음 줄에 카드 안쪽 전체 폭으로 둔다.
  //   정보 열(Expanded) 안 · 왼쪽 32 들여쓰기에서는 320 · 글자 2.0 에서 글이 단추 밖으로 넘쳤다(g2 TB 넘침 43px). 조건이 아니면 카드 줄을 그대로 돌려준다(배치 불변).
  Widget _withRecoveryLine(ApplicationModel app, bool showRecovery, Widget row) {
    if (!showRecovery) return row;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [row, _buildNoshowRecoveryButton(app)],
    );
  }

  // [R5.2] NO_SHOW 대체 인력 충원 버튼 구성
  // 조건: today + !isLongTerm + !isStaffingReleased + canManageTo + 모집 단위 open
  // [GAP-ATT-NOSHOW-RECOVERY-DATE-01] 당일 운영 복구 전용 — 과거 날짜 미노출
  // 이미 released: Wrap에 _buildStaffingReleasedBadge() 표시 (위에서 처리)
  Widget _buildNoshowRecoveryButton(ApplicationModel app) {
    final up = Provider.of<UserProvider>(context, listen: false);
    final canManageTo = up.checkCurrentBusiness((p) => p.canManageTo) == PermissionCheck.allowed;
    if (!canManageTo) return const SizedBox.shrink();
    if (app.isLongTermApplication) return const SizedBox.shrink();
    if (app.isStaffingReleased) return const SizedBox.shrink();
    // [CROSS-SLICE-1A] 종료된 모집 단위에는 권하지 않는다 — 반납해도 채울 수
    //   없고 서버도 같은 이유로 거절한다. 지원자 화면과 같은 판정이다.
    //   모르는 상태(null)는 숨기지 않는다 — 서버가 최종 판정한다.
    final wdId = app.wdId;
    if (wdId != null && _closedUnitByWdId?[wdId] == true) {
      return const SizedBox.shrink();
    }
    // 당일 날짜 게이트 (연/월/일 비교 — 시간값 비교 금지)
    final todayKst = FormatHelper.toKstDate(DateTime.now());
    final dialogDateKst = FormatHelper.toKstDate(_kstDay);
    if (dialogDateKst.year != todayKst.year ||
        dialogDateKst.month != todayKst.month ||
        dialogDateKst.day != todayKst.day) {
      return const SizedBox.shrink(); // 과거/미래 날짜 → CTA 숨김
    }

    return Padding(
      padding: EdgeInsets.only(
        top: ResponsiveHelper.spacing(context, 8),
        // [DU584b r2] 왼쪽 32 들여쓰기(체크박스 보정) 없음 — 이 행동 줄은 이제 카드 안쪽 전체 폭이다(_withRecoveryLine).
      ),
      child: SizedBox(
        width: double.infinity,
        child: OutlinedButton(
          onPressed: _isSeatReleasing
              ? null
              : () => unawaited(_releaseNoshowSeat(app)),
          style: OutlinedButton.styleFrom(
            // [DU584b] 진입 = brand 글 · brand 외곽선(알파 그대로) · brand 아이콘 — 판정170 §5 · O002 같은 행동과 맞춤. 노쇼 배지 · 당일/종료 가드 · 확인창 그대로.
            foregroundColor: AppColors.brand,
            side: BorderSide(color: AppColors.brand.withValues(alpha: 0.7)),
            padding: EdgeInsets.symmetric(
              horizontal: ResponsiveHelper.spacing(context, 10),
              vertical: ResponsiveHelper.spacing(context, 6),
            ),
            minimumSize: Size.zero,
            // [R7.4-C] visual compact 유지 + touch target >= 48dp
            tapTargetSize: MaterialTapTargetSize.padded,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8)),
            textStyle: ResponsiveHelper.smallStyle(context)
                .copyWith(fontWeight: FontWeight.w600),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.group_add_outlined,
                size: ResponsiveHelper.iconSize(context, 14),
                color: AppColors.brand),
            SizedBox(width: ResponsiveHelper.spacing(context, 4)),
            // [DU584b r2] 글은 줄이지 않는다(말줄임 · 숨김 0) — 자리가 모자라면 단추 밖으로 넘치지 않고 단추 안에서 줄을 바꾼다(안전망).
            // [DU618b · 장부067 · 판정160 :54 · 169 :47] O002 같은 행동과 같은 글 — 낱말 안 끊김 0(읽는 이름 원문). 조건 · 색 · 아이콘 · 콜백 그대로.
            Flexible(child: Text(TextLayout.keepWords('빈자리 다시 모집'), semanticsLabel: '빈자리 다시 모집')),
          ]),
        ),
      ),
    );
  }

  /// [R5.2] 대체 충원 진행 중 배지 — Wrap 내 인라인 (staffingReleasedAt 설정된 상태)
  Widget _buildStaffingReleasedBadge() {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 6),
        vertical: ResponsiveHelper.spacing(context, 2),
      ),
      decoration: BoxDecoration(
        color: AppColors.grey100,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: AppColors.grey300),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.people_outline,
            size: ResponsiveHelper.iconSize(context, 11),
            color: AppColors.grey500),
        SizedBox(width: ResponsiveHelper.spacing(context, 3)),
        // [DU618b · 장부067 · 판정169 :47 · J144] 처리 결과 이름(O002 배지와 같은 글) — 조건(노쇼 + 좌석 반납 처리 이력) · 회색 칩 · 크기 · 자리 그대로. 지금 모집 중이라고 말하지 않는다.
        // [DU623b · F206-OATT-BADGE-OVERFLOW · 판정206 :49 · :61] 칩 안 글이 남은 폭보다 길면 칩 밖으로 넘치지 않고 낱말(띄어쓰기)에서만 줄을 바꾼다 — 글 · 색 · 크기 · 조건 그대로 · 읽는 이름 원문.
        Flexible(
          child: Text(TextLayout.keepWords('자리 비움 처리됨'),
              semanticsLabel: '자리 비움 처리됨',
              style: ResponsiveHelper.tinyStyle(context, color: AppColors.grey500)
                  .copyWith(fontWeight: FontWeight.w500)),
        ),
      ]),
    );
  }

  /// [R5.2] NO_SHOW 좌석 반납 → seat release CF 호출 → 성공 시 DayApplicantsDialog(오늘)
  // [I9 · impl_16] 확인·선택 창(첫 await) **전에** 같은 화면의 같은 잠금 묶음을 잠근다 — 창이 뜨기 전 연타의
  //   두 번째 진입이 창·mutation 을 한 번 더 내지 않게(본문 `_releaseNoshowSeatLocked` 은 그대로 · 화면 플래그는 진행 표시로 유지).
  Future<void> _releaseNoshowSeat(ApplicationModel app) =>
      ActionGuard.runVoid(ActionGuard.ownerKey('attendanceStatus._isSeatReleasing', this), () => _releaseNoshowSeatLocked(app));

  Future<void> _releaseNoshowSeatLocked(ApplicationModel app) async {
    if (_isSeatReleasing) return;

    // [DU618b · 장부067 · 판정160 :50–:54] O002 확인창과 같은 제목 · 본문 · 확인 글(이름 = 이 창의 근로자 이름 · 없으면 해당 근무자). 셸 기본 brand · 뒤 실행 · 가드 그대로.
    final confirmed = await DialogHelper.showConfirm(
      context,
      title: '빈자리 다시 모집',
      message:
          '${_userMap[app.uid]?.name ?? '해당 근무자'}님의 오늘 근무가 노쇼로 기록됐어요. 이 자리를 비우고 다시 모집해요.\n'
          '확정 기록은 그대로 남고, 이 근무가 차지하던 1자리를 모집 정원으로 돌려요.',
      confirmText: '다시 모집',
      cancelText: '취소',
    );
    if (!confirmed || !mounted) return;

    setState(() => _isSeatReleasing = true);

    final success = await _firestoreService.releaseNoshowSeat(
        applicationId: app.id);

    if (!mounted) return;
    setState(() => _isSeatReleasing = false);

    // §17: 실패 시 dialog 미오픈, 현재 화면에 남음
    if (!success) return;

    // Reload to reflect staffingReleasedAt
    _hasChanges = true;
    unawaited(_loadData()); // non-blocking refresh

    // §13: seat release 성공 → DayApplicantsDialog(오늘) 오픈
    // [GAP-ATT-NOSHOW-RECOVERY-DATE-01] _buildNoshowRecoveryButton isToday gate 통과 후
    // 이 경로에 도달하므로 _kstDay == today 보장. DateTime.now() ambient clock 불필요.
    if (!mounted) return;
    final bizId = _selectedBusinessId ??
        (widget.businessIds.isEmpty ? null : widget.businessIds.first);
    if (bizId == null) return;
    // [ISG2-REFRESH] 이 진입점은 결과를 버리고 있었다 — 여기서 확정·초대를
    //   해도 공고 탭·Home 은 모르고 있었다(좌석 반납 직후라 바뀌는 쪽이다).
    final changed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => DayApplicantsDialog(
        date: _kstDay,
        businessIds: [bizId],
        businesses: widget.businesses ?? [],
      ),
    );
    if (changed == true && mounted) {
      WorkforceController.notifyDataChanged(
        origin: AdminMutationOrigin.workforce,
      );
    }
  }

  /// 계약서 서명 상태 배지 — 미작성·서명대기만 표시, 완료는 생략
  Widget _buildContractBadge(String appId) {
    final status = _contractStatusMap.statuses[appId];
    final IconData icon;
    final String label;
    final Color color;
    // [REISSUE-RECOVERY] `계약미작성` 은 "없다고 확인됐다"는 말이다.
    //   조회하지 못한 것을 그렇게 적으면 있는 계약을 또 만들러 가고,
    //   배지를 아예 지우면(이 화면은 완료 시 배지를 생략한다) 다 됐다고 읽힌다.
    if (_contractStatusMap.isUnresolved(appId)) {
      icon = Icons.help_outline;
      label = '계약확인불가';
      color = AppColors.grey600;
    } else if (_contractStatusMap.isMissingContract(appId)) {
      icon = Icons.assignment_late_outlined;
      label = '계약미작성';
      color = AppColors.error;
    } else if (status == 'pending_worker') {
      icon = Icons.draw_outlined;
      label = '서명대기';
      color = AppColors.warningDark;
    } else {
      return const SizedBox.shrink();
    }
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 5),
        vertical: ResponsiveHelper.spacing(context, 2),
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 9, color: color),
          const SizedBox(width: 2),
          Text(
            label,
            style: ResponsiveHelper.tinyStyle(context, color: color)
                .copyWith(fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  /// 리컨펌(재확인) 상태 배지 — confirmed(출근확인)/pending(미응답)만 표시
  Widget _buildReconfirmBadge(ApplicationModel app) {
    final status = app.reconfirmStatus;
    if (status == null || status == 'declined') return const SizedBox.shrink();
    // [RECONFIRM-ADMIN-BADGE] 응답 없이 출근해도 서버는 reconfirmStatus 를 바꾸지 않는다
    //   (출퇴근 writer 는 이 필드를 쓰지 않는다) — 퇴근까지 끝난 지원서도 pending 이다.
    //   출근 기록이 있으면 '미응답'은 더 이상 운영 신호가 아니므로 숨긴다.
    //   판정은 이 화면이 이미 가진 그 지원서의 근태(_attendanceMap[app.id])로만 한다.
    if (status == 'pending' && _attendanceMap[app.id]?.checkInAt != null) {
      return const SizedBox.shrink();
    }

    final IconData icon;
    final String label;
    final Color color;

    if (status == 'confirmed') {
      icon = Icons.check_circle_outline_rounded;
      label = '출근확인';
      color = AppColors.successDark;
    } else {
      // 'pending' — H-2 알림 발송됨, 아직 미응답
      icon = Icons.help_outline_rounded;
      label = '미응답';
      color = AppColors.warningDark;
    }

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 5),
        vertical: ResponsiveHelper.spacing(context, 2),
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 9, color: color),
          const SizedBox(width: 2),
          Text(
            label,
            style: ResponsiveHelper.tinyStyle(context, color: color)
                .copyWith(fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  /// 메인 상태 배지 (출근/퇴근/급여확정/최종확정 등 워크플로 단계)
  Widget _buildMainStatusBadge(Map<String, dynamic> statusInfo, ThemeData theme) {
    final status = statusInfo['status'] as String;
    final Color color;
    final String text;

    switch (status) {
      case 'late':
        text = '출근';
        color = theme.primaryColor;
        break;
      case 'early_leave':
        text = '퇴근';
        color = AppColors.purple;
        break;
      default:
        // wage_confirmed(조퇴) 같은 조합 텍스트에서 괄호 제거
        text = (statusInfo['text'] as String)
            .replaceAll(_parenRe, '')
            .trim();
        color = statusInfo['color'] as Color;
    }

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 8),
        vertical: ResponsiveHelper.spacing(context, 2),
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: ResponsiveHelper.tinyStyle(context, color: color)
            .copyWith(fontWeight: FontWeight.w600),
      ),
    );
  }

  /// 추가 플래그 배지 목록 (지각/조퇴/연장/심야)
  List<Widget> _buildExtraBadges(ApplicationModel app) {
    final attendance = _attendanceMap[app.id];
    if (attendance == null) return [];
    if (attendance.status == AttendanceModel.statusNoShow) return [];

    final flags = AttendanceBadgeHelper.compute(
      checkIn: attendance.checkIn,
      checkOut: attendance.checkOut,
      effStart: WorkDetailHelper.effectiveStart(app, _workDetailTimeMap),
      effEnd: WorkDetailHelper.effectiveEnd(app, _workDetailTimeMap),
      wageDetail: attendance.wageDetail,
    );

    return [
      if (flags.isEarlyArrival) _buildFlagBadge('조출', AppColors.success),
      if (flags.isLate) _buildFlagBadge('지각', AppColors.warningDark),
      if (flags.isEarlyLeave) _buildFlagBadge('조퇴', AppColors.amber),
      if (flags.isOvertime) _buildFlagBadge('연장', AppColors.info),
      if (flags.isNight) _buildFlagBadge('심야', AppColors.purple),
    ];
  }

  Widget _buildFlagBadge(String text, Color color) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 6),
        vertical: ResponsiveHelper.spacing(context, 2),
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(
        text,
        style: ResponsiveHelper.tinyStyle(context, color: color)
            .copyWith(fontWeight: FontWeight.w600),
      ),
    );
  }

  /// 관리자가 시간 수정 시 원본 근무자 기록을 작은 텍스트로 표시
  Widget _buildOriginalTimeHint(AttendanceModel attendance) {
    // 초(秒) 제거 후 비교: originalCheckIn은 "HH:mm:ss", checkIn은 반올림 후 "HH:mm"일 수 있음
    final hasOriginalIn = attendance.originalCheckIn != null &&
        _trimSeconds(attendance.originalCheckIn!) != _trimSeconds(attendance.checkIn ?? '');
    final hasOriginalOut = attendance.originalCheckOut != null &&
        _trimSeconds(attendance.originalCheckOut!) != _trimSeconds(attendance.checkOut ?? '');
    if (!hasOriginalIn && !hasOriginalOut) return const SizedBox.shrink();

    final parts = <String>[];
    if (hasOriginalIn) parts.add('출근 ${_trimSeconds(attendance.originalCheckIn!)}');
    if (hasOriginalOut) parts.add('퇴근 ${_trimSeconds(attendance.originalCheckOut!)}');

    return Tooltip(
      message: '근무자 원본 기록: ${parts.join(' / ')}',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.history, size: ResponsiveHelper.iconSize(context, 10),
              color: AppColors.grey400),
          SizedBox(width: ResponsiveHelper.spacing(context, 2)),
          Text(
            parts.join(' / '),
            style: ResponsiveHelper.tinyStyle(context, color: AppColors.grey400),
          ),
        ],
      ),
    );
  }

  /// 출근 방식 배지 (GPS / 비콘 / 수동)
  Widget _buildCheckInMethodBadge(AttendanceModel? attendance) {
    final method = attendance?.checkInMethod;
    if (method == null || method.isEmpty) return const SizedBox.shrink();

    final (IconData icon, String label, Color color) = switch (method) {
      'gps'    => (Icons.gps_fixed, 'GPS', AppColors.info),
      'beacon' => (Icons.bluetooth, '비콘', AppColors.purple),
      'manual' => (Icons.edit_outlined, '수동', AppColors.grey500),
      _        => (Icons.help_outline, method, AppColors.grey400),
    };

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 6),
        vertical: ResponsiveHelper.spacing(context, 2),
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: ResponsiveHelper.iconSize(context, 11), color: color),
          SizedBox(width: ResponsiveHelper.spacing(context, 3)),
          Text(
            label,
            style: ResponsiveHelper.tinyStyle(context, color: color,
                fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  /// GPS 의심 출근 배지 — CF 서버 검증에서 반경 초과로 마킹된 경우 표시
  Widget _buildCheckInSuspiciousBadge(AttendanceModel attendance) {
    final distance = attendance.checkInDistance;
    final label = distance != null ? '위치의심 ${distance}m' : '위치의심';
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 6),
        vertical: ResponsiveHelper.spacing(context, 2),
      ),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.location_off_outlined,
              size: ResponsiveHelper.iconSize(context, 11),
              color: AppColors.error),
          SizedBox(width: ResponsiveHelper.spacing(context, 3)),
          Text(
            label,
            style: ResponsiveHelper.tinyStyle(context,
                color: AppColors.error, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  /// 확인/취소 버튼
  /// - 완료 탭(isDone): 숨김
  /// - 확인 탭(adminConfirmed): ✕ 버튼
  /// - 그 외 + 출퇴근 둘 다 있음: ✓ 버튼
  Widget _buildConfirmButton(ApplicationModel app) {
    final attendance = _attendanceMap[app.id];
    final isDone = attendance?.wageStatus == AttendanceModel.wageCalculated ||
                   attendance?.wageStatus == AttendanceModel.wageConfirmed ||
                   attendance?.wageStatus == AttendanceModel.wageTransferred ||
                   attendance?.status == AttendanceModel.statusNoShow;
    if (isDone) return const SizedBox.shrink();
    // [UI-3] 글자 없는 빨간 X 는 삭제·리셋처럼 읽혔다 — 무엇을 하는지 이름으로 말한다.
    //   확인 = 정산 준비 1차 확인(브랜드), 확인 취소 = 그 표시만 되돌림(중립 글자).
    final isAdminConfirmed = attendance?.adminConfirmed == true;
    if (isAdminConfirmed) {
      return _rowTextAction('확인 취소', AppColors.textSecondary,
          () => _unconfirmWorker(app));
    }
    final canConfirm = attendance?.checkIn != null && attendance?.checkOut != null;
    if (!canConfirm) return const SizedBox.shrink();
    return _rowTextAction('확인', AppColors.brand, () => _confirmWorker(app));
  }

  Widget _rowTextAction(String label, Color color, VoidCallback onTap) {
    return TextButton(
      onPressed: _isLoading ? null : onTap,
      style: TextButton.styleFrom(
        foregroundColor: color,
        padding: EdgeInsets.symmetric(
            horizontal: ResponsiveHelper.spacing(context, 8)),
        minimumSize: const Size(0, 36),
      ),
      child: Text(label,
          style: ResponsiveHelper.smallStyle(context, color: color)
              .copyWith(fontWeight: FontWeight.w600)),
    );
  }

  // adminConfirmed는 관리자 내부 워크플로 전용 필드다.
  // 지원자 앱(schedule_card)은 wageStatus/checkIn/checkOut/status 기준으로만 상태를 표시하며
  // adminConfirmed를 참조하지 않는다 — 의도된 설계.
  // 알림도 발송하지 않는다: 1차 확인은 관리자 정산 준비 단계이고,
  // 지원자에게는 최종 마감(wageConfirmed) 시점에만 급여 알림이 전송된다.
  Future<void> _confirmWorker(ApplicationModel app) async {
    if (_isLoading) return;
    final attendance = _attendanceMap[app.id];
    if (attendance == null) return;
    setState(() => _isLoading = true);
    try {
      await FirebaseFunctions.instanceFor(region: 'asia-northeast3')
          .httpsCallable('callableBatchAdminConfirm')
          .call({'businessId': _selectedBusinessId, 'attendanceIds': [attendance.id], 'confirmed': true});
      if (!mounted) return;
      setState(() {
        _attendanceMap[app.id] = attendance.copyWith(adminConfirmed: true);
        _selectedIds.remove(app.id);
        _hasChanges = true;
        _rebuildStatusCache();
        _rebuildTabWorkers();
      });
    } catch (e) {
      debugPrint('❌ 확인 처리 실패: $e');
      if (mounted) ToastHelper.showError('확인 처리 실패');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _unconfirmWorker(ApplicationModel app) async {
    if (_isLoading) return;
    final attendance = _attendanceMap[app.id];
    if (attendance == null) return;
    setState(() => _isLoading = true);
    try {
      await FirebaseFunctions.instanceFor(region: 'asia-northeast3')
          .httpsCallable('callableBatchAdminConfirm')
          .call({'businessId': _selectedBusinessId, 'attendanceIds': [attendance.id], 'confirmed': false});
      if (!mounted) return;
      setState(() {
        _attendanceMap[app.id] = attendance.copyWith(adminConfirmed: false);
        _hasChanges = true;
        _rebuildStatusCache();
        _rebuildTabWorkers();
      });
    } catch (e) {
      debugPrint('❌ 확인 취소 실패: $e');
      if (mounted) ToastHelper.showError('확인 취소 실패');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// 선택 인원 기반 확인/취소 고정 바 — 선택된 근무자 중 대상이 있을 때만 표시
  Widget _buildSelectionConfirmBar(ThemeData theme) {
    final tabWorkers = _tabWorkers[_currentTabIndex];
    final selectedWorkers = tabWorkers.where((a) => _selectedIds.contains(a.id)).toList();

    final confirmable = selectedWorkers.where((a) {
      final att = _attendanceMap[a.id];
      final isDone = att?.wageStatus == AttendanceModel.wageCalculated ||
                     att?.wageStatus == AttendanceModel.wageConfirmed ||
                     att?.wageStatus == AttendanceModel.wageTransferred ||
                     att?.status == AttendanceModel.statusNoShow;
      return !isDone &&
          att?.checkIn != null && att?.checkOut != null &&
          att?.adminConfirmed != true &&
          att?.status != AttendanceModel.statusNoShow;
    }).toList();

    final cancellable = selectedWorkers.where((a) {
      final att = _attendanceMap[a.id];
      final isDone = att?.wageStatus == AttendanceModel.wageCalculated ||
                     att?.wageStatus == AttendanceModel.wageConfirmed ||
                     att?.wageStatus == AttendanceModel.wageTransferred ||
                     att?.status == AttendanceModel.statusNoShow;
      return !isDone && att?.adminConfirmed == true;
    }).toList();

    if (confirmable.isEmpty && cancellable.isEmpty) return const SizedBox.shrink();

    return SafeArea(
      top: false,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: ResponsiveHelper.spacing(context, 16),
          vertical: ResponsiveHelper.spacing(context, 10),
        ),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: AppColors.border)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 8,
              offset: const Offset(0, -3),
            ),
          ],
        ),
        child: Row(
          children: [
            if (confirmable.isNotEmpty) Expanded(
              child: ElevatedButton.icon(
                onPressed: () => _batchGroupConfirm(confirmable),
                icon: Icon(Icons.check_circle_outline, size: ResponsiveHelper.iconSize(context, 16)),
                // [5B.2B] adminConfirmed action: "확인 N명" → "근태 확인 N명" (Application/급여 확정과 구분)
                label: Text('근태 확인 ${confirmable.length}건'),
                // [DU305] 행동색은 누른 결과를 말한다(Standards §9.1·§12.2) — 일반 확인 진행은 brand 채움.
                //   확정 상태의 녹색은 상태 표시(처리현황·배지)에만 둔다.
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.brand,
                  foregroundColor: Colors.white,
                  // [DU305 r3] 주 CTA 시각 높이 최소 52(Standards §82) — 테마 최소 48 위에 이 바만 올린다. 내용이 크면 그대로 늘어난다.
                  minimumSize: const Size(64, 52),
                  padding: EdgeInsets.symmetric(vertical: ResponsiveHelper.spacing(context, 12)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  textStyle: ResponsiveHelper.bodyStyle(context).copyWith(fontWeight: FontWeight.w600),
                ),
              ),
            ),
            if (confirmable.isNotEmpty && cancellable.isNotEmpty)
              SizedBox(width: ResponsiveHelper.spacing(context, 8)),
            if (cancellable.isNotEmpty) Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _batchGroupCancelConfirm(cancellable),
                icon: Icon(Icons.undo_outlined, size: ResponsiveHelper.iconSize(context, 16)),
                label: Text('취소 ${cancellable.length}건'),
                // [DU305] 근태 확인 표시만 되돌린다(서버 confirmed:false, 급여 처리된 건은 대상 밖) — 손실·책임 행동이 아니므로
                //   경고색이 아닌 보조 외곽선(일괄 바 보조 행동과 같은 textPrimary·grey300)으로 둔다.
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.textPrimary,
                  side: const BorderSide(color: AppColors.grey300),
                  // [DU305 r3] 같은 바의 근태 확인과 높이를 맞춘다(두 버튼이 한 줄에 함께 설 때 어긋나지 않게).
                  minimumSize: const Size(64, 52),
                  padding: EdgeInsets.symmetric(vertical: ResponsiveHelper.spacing(context, 12)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  textStyle: ResponsiveHelper.bodyStyle(context).copyWith(fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // [B01/B02 설계 검토] WriteBatch 500 ops 제한 관련:
  // 그룹 확인/취소는 당일 한 사업장의 한 파트(업무유형+시간대) 단위로 실행된다.
  // 실제 서비스에서 단일 파트에 500명이 동시에 근무하는 경우는 현실적으로 불가능하다.
  // (일반 아르바이트 사업장 최대 규모 기준 파트당 50~100명 수준)
  // 따라서 단순 batch 1개 사용으로 충분하다. 분할 처리 불필요.
  // [I9 · impl_16] 확인·선택 창(첫 await) **전에** 같은 화면의 같은 잠금 묶음을 잠근다 — 창이 뜨기 전 연타의
  //   두 번째 진입이 창·mutation 을 한 번 더 내지 않게(본문 `_batchGroupConfirmLocked` 은 그대로 · 화면 플래그는 진행 표시로 유지).
  Future<void> _batchGroupConfirm(List<ApplicationModel> confirmable) =>
      ActionGuard.runVoid(ActionGuard.ownerKey('attendanceStatus._isLoading', this), () => _batchGroupConfirmLocked(confirmable));

  Future<void> _batchGroupConfirmLocked(List<ApplicationModel> confirmable) async {
    if (_isLoading) return;
    final ok = await DialogHelper.showConfirm(
      context,
      title: '근태 일괄 확인',
      message: '${confirmable.length}명의 근태를 확인 완료 처리합니까?',
      confirmText: '근태 확인',
      icon: Icons.check_circle_outline,
      confirmColor: AppColors.brand, // [DU305] 일반 확인 진행 = brand(§9.1)
    );
    if (!ok || !mounted) return;
    setState(() => _isLoading = true);
    try {
      final attendanceIds = confirmable
          .map((a) => _attendanceMap[a.id]?.id)
          .whereType<String>()
          .toList();
      await FirebaseFunctions.instanceFor(region: 'asia-northeast3')
          .httpsCallable('callableBatchAdminConfirm')
          .call({'businessId': _selectedBusinessId, 'attendanceIds': attendanceIds, 'confirmed': true});
      if (!mounted) return;
      setState(() {
        for (final a in confirmable) {
          final att = _attendanceMap[a.id];
          if (att != null) _attendanceMap[a.id] = att.copyWith(adminConfirmed: true);
          _selectedIds.remove(a.id);
        }
        _isLoading = false;
        _hasChanges = true;
        _rebuildStatusCache();
        _rebuildTabWorkers();
      });
    } catch (e) {
      debugPrint('❌ 그룹 전체 확인 실패: $e');
      if (!mounted) return;
      ToastHelper.showError('그룹 전체 확인 실패');
    } finally {
      if (mounted && _isLoading) setState(() => _isLoading = false);
    }
  }

  // [I9 · impl_16] 확인·선택 창(첫 await) **전에** 같은 화면의 같은 잠금 묶음을 잠근다 — 창이 뜨기 전 연타의
  //   두 번째 진입이 창·mutation 을 한 번 더 내지 않게(본문 `_batchGroupCancelConfirmLocked` 은 그대로 · 화면 플래그는 진행 표시로 유지).
  Future<void> _batchGroupCancelConfirm(List<ApplicationModel> cancellable) =>
      ActionGuard.runVoid(ActionGuard.ownerKey('attendanceStatus._isLoading', this), () => _batchGroupCancelConfirmLocked(cancellable));

  Future<void> _batchGroupCancelConfirmLocked(List<ApplicationModel> cancellable) async {
    if (_isLoading) return;
    final ok = await DialogHelper.showConfirm(
      context,
      title: '그룹 전체 취소',
      message: '${cancellable.length}명의 확인을 일괄 취소합니까?',
      confirmText: '취소 처리',
      icon: Icons.undo_outlined,
      confirmColor: AppColors.brand, // [DU305] 되돌릴 수 있는 확인 표시 해제 — 손실 행동이 아니므로 brand(§9.1)
    );
    if (!ok || !mounted) return;
    setState(() => _isLoading = true);
    try {
      final attendanceIds = cancellable
          .map((a) => _attendanceMap[a.id]?.id)
          .whereType<String>()
          .toList();
      await FirebaseFunctions.instanceFor(region: 'asia-northeast3')
          .httpsCallable('callableBatchAdminConfirm')
          .call({'businessId': _selectedBusinessId, 'attendanceIds': attendanceIds, 'confirmed': false});
      if (!mounted) return;
      setState(() {
        for (final a in cancellable) {
          final att = _attendanceMap[a.id];
          if (att != null) _attendanceMap[a.id] = att.copyWith(adminConfirmed: false);
        }
        _isLoading = false;
        _hasChanges = true;
        _rebuildStatusCache();
        _rebuildTabWorkers();
      });
    } catch (e) {
      debugPrint('❌ 그룹 전체 취소 실패: $e');
      if (!mounted) return;
      ToastHelper.showError('그룹 전체 확인 취소 실패');
    } finally {
      if (mounted && _isLoading) setState(() => _isLoading = false);
    }
  }

  /// 하단 버튼 바
  /// [DU305 후속 V7] footer 두 보조 행동(명단 출력·급여관리).
  ///   큰 글자에서 아이콘이 버튼 왼쪽 테두리에 붙었다(안쪽 가로 여백 0). 안쪽 가로 여백을 4(4/8 그리드)로 둔다.
  ///   두 버튼 모두 [아이콘 + 간격 + 한 줄 글자]가 실제 버튼 안쪽 폭에 들어가면 기존 가로 배치를 그대로 쓰고,
  ///   하나라도 안 들어가면 둘 다 아이콘 위·글자 아래로 바꾼다(두 행동의 위계를 같게, 글자 축소·말줄임 0).
  ///   판단은 실제 폭(LayoutBuilder)과 실제 글자 배율·버튼 글자 스타일(위젯 → 버튼 테마 → 기본값 순)로 한 줄 폭을 잰다.
  Widget _buildFooterActions(BuildContext context, ThemeData theme) {
    final enabled = _confirmedWorkers.isNotEmpty;
    final wageAllowed = enabled &&
        context.read<UserProvider>().checkCurrentBusiness((p) => p.canManageWage) == PermissionCheck.allowed;
    final between = ResponsiveHelper.spacing(context, 12);
    final iconSize = ResponsiveHelper.iconSize(context, 18);
    final scaler = MediaQuery.textScalerOf(context);
    final iconGap = scaler.scale(1) <= 1.0 ? 8.0 : 4.0;
    const hPad = 4.0;
    final printLabel = TextLayout.keepWords('명단 출력');
    const wageLabel = '급여관리';
    final labelStyle = OutlinedButtonTheme.of(context).style?.textStyle?.resolve(const <WidgetState>{}) ??
        const OutlinedButton(onPressed: null, child: SizedBox.shrink()).defaultStyleOf(context).textStyle?.resolve(const <WidgetState>{}) ??
        DefaultTextStyle.of(context).style;
    double oneLine(String s) {
      final tp = TextPainter(
        text: TextSpan(text: s, style: labelStyle),
        textDirection: Directionality.of(context),
        textScaler: scaler,
        locale: Localizations.maybeLocaleOf(context),
        maxLines: 1,
      )..layout();
      final w = tp.width;
      tp.dispose();
      return w;
    }

    ButtonStyle style(Color fg, Color side) => OutlinedButton.styleFrom(
          foregroundColor: fg,
          side: BorderSide(color: side),
          padding: EdgeInsets.symmetric(horizontal: hPad, vertical: ResponsiveHelper.spacing(context, 12)),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        );

    return LayoutBuilder(builder: (lctx, c) {
      final inner = (c.maxWidth - between) / 2 - 2 * hPad;
      final inRow = iconSize + iconGap + oneLine(printLabel) <= inner && iconSize + iconGap + oneLine(wageLabel) <= inner;
      Widget body(IconData icon, Widget label) => inRow
          ? Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon, size: iconSize),
              SizedBox(width: iconGap),
              Flexible(child: label),
            ])
          : Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon, size: iconSize),
              const SizedBox(height: 4),
              label,
            ]);
      return Row(
        children: [
          // 명단 출력 버튼 — [DU305] 줄은 낱말 사이에서만 바꾼다. 화면 읽기·검색·시험 기준은 원문 그대로다.
          Expanded(
            child: OutlinedButton(
              onPressed: enabled ? _showPrintPreview : null,
              style: style(enabled ? theme.primaryColor : AppColors.grey500, enabled ? theme.primaryColor : AppColors.grey300),
              child: body(Icons.print_outlined, Text(printLabel, semanticsLabel: '명단 출력', textAlign: TextAlign.center)),
            ),
          ),
          SizedBox(width: between),
          // 급여관리 버튼 — OutlinedButton (보조 액션)
          Expanded(
            child: OutlinedButton(
              onPressed: wageAllowed ? _showWageConfirmDialog : null,
              style: style(enabled ? theme.primaryColor : AppColors.grey400, enabled ? theme.primaryColor : AppColors.grey300),
              child: body(Icons.payments, const Text(wageLabel, textAlign: TextAlign.center)),
            ),
          ),
        ],
      );
    });
  }

  Widget _buildBottomBar(ThemeData theme) {
    return AppModalFooter(
      child: Builder(builder: (context) {
        final selectedFinal = _selectedFinalConfirmedApps;
        return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 처리현황 + 마감 버튼
          _buildProgressRow(theme),
          // 마감취소 버튼 (최종확정 근무자 선택 시 표시)
          if (selectedFinal.isNotEmpty) ...[
            SizedBox(height: ResponsiveHelper.spacing(context, 8)),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _batchCancelFinal,
                icon: Icon(
                  Icons.lock_open_outlined,
                  size: ResponsiveHelper.iconSize(context, 18),
                ),
                label: Text('마감취소 (${selectedFinal.length}명)'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.brand,
                foregroundColor: Colors.white,
                padding: EdgeInsets.symmetric(
                  vertical: ResponsiveHelper.spacing(context, 12),
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
        SizedBox(height: ResponsiveHelper.spacing(context, 12)),
        // 기존 버튼들 — [DU305 후속 V7] 배치·여백은 _buildFooterActions
        _buildFooterActions(context, theme),
        ],
        );
      }),
    );
  }

  /// 처리현황 Row
  Widget _buildProgressRow(ThemeData theme) {
    final processedCount = _processedCount;
    final isAllProcessed = _confirmedWorkers.isNotEmpty && processedCount == _confirmedWorkers.length;
    // [SUMMARY-PATCH] Tab 2 (확인완료) 실제 인원
    // _tabWorkers[2] = adminConfirmed==true && !isDone — Tab 표시 인원과 항상 동일
    // raw adminConfirmed count 미사용:
    //   isDone 이동 후에도 attendanceMap의 adminConfirmed=true가 잔존할 수 있어
    //   처리완료 인원과 중복 집계될 위험을 차단
    final confirmedTabCount = _tabWorkers[2].length;

    // [COMMON-TEXT-LAYOUT.28] 큰 글자에서 한 줄을 넘쳤다(9px) — 두 묶음으로 나눠, 모자라면
    //   '· 확인완료 N건' 묶음이 통째로 다음 줄로 간다.
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      runSpacing: 2,
      children: [
        Row(mainAxisSize: MainAxisSize.min, children: [
        if (isAllProcessed) ...[
          const Icon(Icons.check_circle, size: 14, color: AppColors.success),
          const SizedBox(width: 4),
        ],
        const Text('처리 완료 ',
            style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
        Text(
          '$processedCount/${_confirmedWorkers.length}건',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: isAllProcessed ? AppColors.success : theme.primaryColor,
          ),
        ),
        ]),
        if (confirmedTabCount > 0)
          Row(mainAxisSize: MainAxisSize.min, children: [
          const Text('  ·  ',
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
          Text(
            '확인완료 $confirmedTabCount건',
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.info,
            ),
          ),
          ]),
      ],
    );
  }

  /// 급여 확정 다이얼로그 열기
  Future<void> _showWageConfirmDialog() async {
    if (_isLoading) return;
    if (_confirmedWorkers.isEmpty) {
      ToastHelper.showWarning('급여 확정할 인원이 없습니다');
      return;
    }

    if (_selectedBusinessId == null) {
      ToastHelper.showWarning('사업장을 선택해주세요');
      return;
    }

    final businessName = _businessNameMap[_selectedBusinessId] ?? '사업장';

    // 최신 출퇴근 기록·workDetail을 Firestore에서 재조회
    setState(() => _isLoading = true);
    try {
      final appIds = _confirmedWorkers.map((w) => w.id).toList();
      final attendanceFuture = _getAttendanceRecords(appIds);
      final workDetailFuture = _getWorkDetailTimes();
      // [ROOT-FUTURE] 나중에 await 하는(또는 앞에서 return 하면 아예 await 하지 않는) future — 먼저 실패해도 '처리되지 않은 오류'(Crashlytics fatal)로 새지 않게. await 하는 곳은 그대로 같은 오류를 받는다.
      workDetailFuture.ignore();
      _attendanceMap = await attendanceFuture;
      if (!mounted) return;
      _workDetailTimeMap = await workDetailFuture;
      if (!mounted) return;
    } catch (e) {
      debugPrint('❌ 출퇴근 기록 재조회 실패: $e');
      if (mounted) ToastHelper.showError('출퇴근 기록을 불러오는 데 실패했습니다');
      return;
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
    _rebuildStatusCache();
    _rebuildTabWorkers();

    final hasChanges = await showDialog<bool>(
      context: context,
      barrierDismissible: false, // [M-3] 외부 탭으로 null 반환 시 부모 _hasChanges 미갱신 → 목록 UI 미반영 버그
      builder: (context) => WageConfirmDialog(
        date: _kstDay,
        businessId: _selectedBusinessId!,
        businessName: businessName,
        workers: _confirmedWorkers,
        attendanceMap: _attendanceMap,
        userMap: _userMap,
        workDetailTimeMap: _workDetailTimeMap,
        // onConfirmed/onClose에서 _loadData() 미호출
        // — 다이얼로그 열려 있는 동안은 부모 화면이 보이지 않으므로 갱신 불필요
        // — 다이얼로그 닫힌 후 hasChanges 반환값으로 아래에서 1회만 호출
      ),
    );

    // 변경사항 있으면 당일명단도 변경 표시
    if (hasChanges == true && mounted) {
      _hasChanges = true;
      await _loadData();
    }
  }

  // ═══════════════════════════════════════════════════════════
  // 명단 출력
  // ═══════════════════════════════════════════════════════════

  /// PDF 명단 미리보기 표시
  Future<void> _showPrintPreview() async {
    if (_isLoading) return;
    if (_confirmedWorkers.isEmpty) {
      ToastHelper.showWarning('출력할 인원이 없습니다');
      return;
    }

    final rootNav = Navigator.of(context, rootNavigator: true);

    // 로딩 다이얼로그 표시
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (loadingContext) => PopScope(
        canPop: false,
        child: Center(
          child: Container(
            padding: ResponsiveHelper.cardPadding(loadingContext),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(ResponsiveHelper.spacing(loadingContext, 16)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const LoadingWidget(),
                SizedBox(height: ResponsiveHelper.spacing(loadingContext, 16)),
                Text(
                  '명단 생성 중...',
                  style: ResponsiveHelper.bodyStyle(loadingContext),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    AttendanceListData? data;
    Uint8List? pdfBytes;
    try {
      // 사업장 이름 가져오기
      final businessName = _businessNameMap[_selectedBusinessId] ?? '사업장';

      // 데이터 변환 (이미 로드된 _workDetailTimeMap 사용)
      data = AttendanceListPdf.convertFromDialogData(
        businessName: businessName,
        date: _kstDay,
        confirmedWorkers: _confirmedWorkers,
        userMap: _userMap,
        workTypeMap: _workDetailTimeMap,
      );

      // ✅ PDF 생성 (폰트는 generatePdf 내부에서 자동 로드)
      // [PERF impl_19] 문서 만들기는 별도 isolate(로딩 창이 도는 동안 화면이 멈칫하지 않게 · 실패 시 이 자리)
      pdfBytes = await AttendanceListPdf.generatePdf(data, offMain: true);
    } catch (e, stack) {
      debugPrint('❌ 명단 출력 실패: $e\n$stack');
      if (mounted) ToastHelper.showError('명단 출력 실패');
    } finally {
      if (rootNav.mounted && rootNav.canPop()) rootNav.pop();
    }

    if (data == null || pdfBytes == null) return;

    await Future<void>.delayed(Duration.zero);

    // ✅ 미리 생성된 PDF로 바로 미리보기 표시
    if (mounted) {
      await AttendanceListPdf.showPreviewWithBytes(
        context: context,
        data: data,
        pdfBytes: pdfBytes,
        confirmedWorkers: _confirmedWorkers,
        userMap: _userMap,
        businessName: data.businessName,
        date: _kstDay,
      );
    }
  }

  /// 슬롯별 workDetails에서 업무유형별 시간·급여 정보 조회
  ///
  /// TO 템플릿이 아닌 슬롯 문서를 우선 읽어 날짜별 수정 사항을 반영한다.
  /// workers를 넘기면 해당 근무자들의 slotId 기반으로 조회; null이면 _confirmedWorkers 사용.
  /// [AH-V2-04A.1] 실제 로딩은 WorkDetailTimeService가 담당한다.
  ///   관리자 Home도 같은 서비스를 써서 동일한 근무시간 기준을 갖는다.
  Future<Map<String, dynamic>> _getWorkDetailTimes([List<ApplicationModel>? workers]) =>
      _reads.workDetailTimes(workers ?? _confirmedWorkers);


  // ═══════════════════════════════════════════════════════════
  // 선택 관련 메서드
  // ═══════════════════════════════════════════════════════════

  /// 전체 선택/해제 — 검색 필터가 활성화된 경우 화면에 보이는 인원만 대상
  void _toggleSelectAll(bool value) {
    final before = Set<String>.of(_selectedIds); // [DU305] 선택이 늘 때만 맞춘다
    setState(() {
      _selectAll = value;
      if (value) {
        _selectedIds.clear();
        final tabWorkers = _tabWorkers[_currentTabIndex];
        final visibleWorkers = _nameFilter.isEmpty
            ? tabWorkers
            : tabWorkers.where((app) {
                final name = _userMap[app.uid]?.name ?? '';
                return name.contains(_nameFilter);
              }).toList();
        for (var app in visibleWorkers) {
          final status = _getAttendanceStatus(app);
          if (status['status'] != 'noshow') {
            _selectedIds.add(app.id);
          }
        }
      } else {
        _selectedIds.clear();
      }
    });
    if (value && _selectedIds.any((id) => !before.contains(id))) _revealAfterSelection(list: true); // [DU305]
  }

  /// [DU305] 선택 직후 맞춤 — 상단이 넘쳐 따로 스크롤되는 상태(상단 창의 maxScrollExtent > 0)에서만 움직인다.
  ///   상단이 다 보이는 배치(W BASE 등)에서는 아무것도 움직이지 않는다.
  ///   1) 상단 창: 일괄 버튼 첫 줄(출근·퇴근, 선택 건수 포함)이 다 보이게 최소 거리로 맞춘다.
  ///   2) [list] 이면 목록 창: 화면 순서상 첫 선택 카드의 위쪽 min(카드 높이, 창 높이) 구간이 다 보이게 최소 거리로 맞춘다.
  ///   이미 다 보이면 그 창은 움직이지 않는다. 다음 frame(선택 확인 바·건수 줄이 반영된 배치)에서 잰다.
  ///   선택·권한·근태 처리·서버 경로는 바꾸지 않는다 — 스크롤 위치만 바꾼다.
  void _revealAfterSelection({required bool list}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _selectedIds.isEmpty) return;
      final stepCtx = _batchStepRowKey.currentContext;
      if (stepCtx == null) return;
      final top = Scrollable.maybeOf(stepCtx)?.position;
      if (top == null || !top.hasContentDimensions || top.maxScrollExtent <= 0) return;
      _revealInScrollable(stepCtx);
      if (list) {
        final cardCtx = _firstSelectedCardKey.currentContext;
        if (cardCtx != null) _revealInScrollable(cardCtx);
      }
    });
  }

  /// [DU305] [target] 의 위쪽 min(높이, 창 높이) 구간이 가장 가까운 스크롤 창 안에 다 보이게 최소 거리로 움직인다.
  ///   아래에 있으면 그 구간 아래끝을 창 아래끝에, 위에 있으면 위끝을 창 위끝에 맞춘다. 이미 보이면 그대로다.
  void _revealInScrollable(BuildContext target) {
    final box = target.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return;
    final pos = Scrollable.maybeOf(target)?.position;
    final viewport = RenderAbstractViewport.maybeOf(box);
    if (pos == null || viewport == null || !pos.hasContentDimensions) return;
    final h = box.size.height < pos.viewportDimension ? box.size.height : pos.viewportDimension;
    final rect = Rect.fromLTWH(0, 0, box.size.width, h);
    final alignTop = viewport.getOffsetToReveal(box, 0.0, rect: rect).offset;
    final alignBottom = viewport.getOffsetToReveal(box, 1.0, rect: rect).offset;
    double? goal;
    if (pos.pixels < alignBottom - 0.5) {
      goal = alignBottom;
    } else if (pos.pixels > alignTop + 0.5) {
      goal = alignTop;
    }
    if (goal == null) return;
    final clamped = goal.clamp(pos.minScrollExtent, pos.maxScrollExtent).toDouble();
    if ((clamped - pos.pixels).abs() <= 0.5) return;
    pos.animateTo(clamped, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
  }

  /// 상태 기반 스마트 선택
  // ─── 배치 노쇼 처리 ───────────────────────────────────────────

  // [F-32/A02 설계 검토] 노쇼 배치 WriteBatch 500 ops 제한:
  // 노쇼 대상은 당일 단일 사업장의 '미출근(pending)' 인원에 한정된다.
  // 레코드가 없는 경우 set(), 있는 경우 update() 1 op씩이므로 targets.length개의 op가 발생한다.
  // 현실적 최대 규모(하루 수백 명)는 단일 batch(500 ops)로 충분하다.
  // [I9 · impl_16] 확인·선택 창(첫 await) **전에** 같은 화면의 같은 잠금 묶음을 잠근다 — 창이 뜨기 전 연타의
  //   두 번째 진입이 창·mutation 을 한 번 더 내지 않게(본문 `_showBatchNoShowDialogLocked` 은 그대로 · 화면 플래그는 진행 표시로 유지).
  Future<void> _showBatchNoShowDialog(List<ApplicationModel> targets) =>
      ActionGuard.runVoid(ActionGuard.ownerKey('attendanceStatus._isLoading', this), () => _showBatchNoShowDialogLocked(targets));

  Future<void> _showBatchNoShowDialogLocked(List<ApplicationModel> targets) async {
    if (_isLoading) return; // 중복 실행 방어
    final names = targets.map((a) => _getIdentifiedName(a.uid)).join(', ');
    final confirmed = await DialogHelper.showDangerConfirm(
      context,
      title: '일괄 노쇼 처리',
      message: '미출근 ${targets.length}명을 노쇼 처리합니다.\n'
          '노쇼 이력이 기록되며, 최근 90일 내 노쇼가 3회 발생하면\n'
          '24시간 동안 새로운 일자리 지원이 제한됩니다.\n\n$names',
      confirmText: '노쇼 처리',
    );
    if (!confirmed || !mounted) return;
    setState(() => _isLoading = true);

    // CF callableBatchSetNoShow 경유 — 서버에서 권한 재검증 후 배치 처리
    final entries = targets.map((app) {
      final att = _attendanceMap[app.id];
      return {
        'applicationId': app.id,
        'workDateMs': _kstDayStartMs,
        'userId': app.uid,
        'businessName': app.businessName,
        'workType': app.selectedWorkType,
        if (att != null) 'attendanceId': att.id,
      };
    }).toList();

    try {
      final result = await FirebaseFunctions.instanceFor(region: 'asia-northeast3')
          .httpsCallable('callableBatchSetNoShow')
          .call({'businessId': _selectedBusinessId, 'entries': entries});
      // TrustScore noShowCount/trustScore는 onAttendanceWageStatusChanged CF 트리거에서 서버 자동 처리
      if (!mounted) return;
      _hasChanges = true;
      // [R7-NOSHOW-START-BOUNDARY] 서버가 건너뛴 건을 성공으로 말하지 않는다.
      //   서버는 근무 시작 전·급여 확정·이미 출근한 건을 skip으로 돌려준다.
      //   이전에는 응답을 읽지 않고 항상 `완료 (N명)`을 띄웠다 — 아무것도
      //   처리되지 않아도 같은 문구였다. 노쇼취소 쪽은 이미 skipped를 읽는다.
      final processed = result.data['processed'] as int? ?? targets.length;
      final skippedCount = (result.data['skipped'] as List?)?.length ?? 0;
      if (processed > 0) ToastHelper.showSuccess('노쇼 처리 완료 ($processed명)');
      if (skippedCount > 0) {
        ToastHelper.showWarning('$skippedCount명 제외 — 아직 미출근으로 확정할 '
            '시각이 아니거나, 이미 출근·급여 처리된 건입니다');
      }
      // [R8-P1C] 서버가 바꾼 것은 근태 문서뿐이다 (노쇼).
      await _refreshAttendanceOnly();
    } catch (e) {
      debugPrint('❌ 배치 노쇼 실패: $e');
      if (!mounted) return;
      ToastHelper.showError('노쇼 처리 실패');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // [F-33/A03 설계 검토] 노쇼 취소 배치 WriteBatch 500 ops 제한:
  // 노쇼 취소 대상은 status == 'NO_SHOW'인 인원만이며, 1인당 1 op.
  // 현실적 규모(하루 수백 명)로 단일 batch 범위 내이다.
  // [I9 · impl_16] 확인·선택 창(첫 await) **전에** 같은 화면의 같은 잠금 묶음을 잠근다 — 창이 뜨기 전 연타의
  //   두 번째 진입이 창·mutation 을 한 번 더 내지 않게(본문 `_showBatchCancelNoShowDialogLocked` 은 그대로 · 화면 플래그는 진행 표시로 유지).
  Future<void> _showBatchCancelNoShowDialog(List<ApplicationModel> targets) =>
      ActionGuard.runVoid(ActionGuard.ownerKey('attendanceStatus._isLoading', this), () => _showBatchCancelNoShowDialogLocked(targets));

  Future<void> _showBatchCancelNoShowDialogLocked(List<ApplicationModel> targets) async {
    if (_isLoading) return; // 중복 실행 방어
    final names = targets.map((a) => _getIdentifiedName(a.uid)).join(', ');
    final confirmed = await DialogHelper.showConfirm(
      context,
      title: '노쇼 취소',
      message: '잘못 처리된 노쇼를 취소합니다.\n'
          '해당 노쇼 기록은 최근 90일 집계에서 제외됩니다.\n\n$names',
      confirmText: '취소 확인',
    );
    if (!confirmed || !mounted) return;
    setState(() => _isLoading = true);

    // CF callableBatchCancelNoShow 경유 — 서버에서 wageTransferred 건 재차 방어
    final attendanceIds = targets
        .map((app) => _attendanceMap[app.id]?.id)
        .whereType<String>()
        .toList();

    try {
      final result = await FirebaseFunctions.instanceFor(region: 'asia-northeast3')
          .httpsCallable('callableBatchCancelNoShow')
          .call({'businessId': _selectedBusinessId, 'attendanceIds': attendanceIds});
      // TrustScore noShowCount/trustScore는 onAttendanceWageStatusChanged CF 트리거에서 서버 자동 처리
      if (!mounted) return;
      final processed = result.data['processed'] as int? ?? 0;
      final skippedCount = (result.data['skipped'] as List?)?.length ?? 0;
      _hasChanges = true;
      if (processed > 0) ToastHelper.showSuccess('노쇼 취소 완료 ($processed명)');
      if (skippedCount > 0) {
        ToastHelper.showWarning('이체 완료 건 $skippedCount명 제외 — 급여 시스템에서 처리 필요');
      }
      await _loadData();
    } catch (e) {
      debugPrint('❌ 노쇼 취소 실패: $e');
      if (!mounted) return;
      ToastHelper.showError('노쇼 취소 실패');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ─── 배치 리셋 ───────────────────────────────────────────────

  // [F-34/A05 설계 검토] 리셋 배치 WriteBatch 500 ops 제한:
  // 당일 단일 사업장 전체 인원 대상이며, 리셋은 출근 기록이 있는 인원(checkIn != null)
  // 또는 결근(statusAbsent) 처리된 인원을 대상으로 한다. 일반 아르바이트 사업장
  // 최대 규모 기준 하루 수백 명 수준으로 단일 batch(500 ops) 내에서 충분히 처리 가능하다.
  // [I9 · impl_16] 확인·선택 창(첫 await) **전에** 같은 화면의 같은 잠금 묶음을 잠근다 — 창이 뜨기 전 연타의
  //   두 번째 진입이 창·mutation 을 한 번 더 내지 않게(본문 `_showBatchResetDialogLocked` 은 그대로 · 화면 플래그는 진행 표시로 유지).
  Future<void> _showBatchResetDialog() =>
      ActionGuard.runVoid(ActionGuard.ownerKey('attendanceStatus._isLoading', this), () => _showBatchResetDialogLocked());

  Future<void> _showBatchResetDialogLocked() async {
    if (_isLoading) return;
    final targets = _selectedIds
        .map((id) => _workerIdMap[id])
        .whereType<ApplicationModel>()
        .where((app) {
          final att = _attendanceMap[app.id];
          if (att == null) return false;
          // H-3: statusAbsent(결근)도 리셋 대상에 포함 — checkIn이 없어도 처리
          return att.checkIn != null ||
              att.status == AttendanceModel.statusAbsent ||
              // [ATTENDANCE-UNKNOWN-DEST.28] status 없음도 예전처럼 리셋 대상
              att.status == AttendanceModel.statusUnconfirmed;
        })
        .toList();
    if (targets.isEmpty) return;

    // [HIGH-04] 급여 1차확정(calculated) · 마감(confirmed) · 이체 완료(transferred) 건은 리셋 제외
    // calculated는 관리자가 계산 검토 중인 상태 — 리셋 시 급여 계산 결과 소실됨
    final wageFinalized = targets.where((app) {
      final s = _attendanceMap[app.id]?.wageStatus;
      return s == AttendanceModel.wageCalculated ||
          s == AttendanceModel.wageConfirmed ||
          s == AttendanceModel.wageTransferred;
    }).toList();

    final resetTargets = targets
        .where((app) => !wageFinalized.contains(app))
        .toList();

    if (resetTargets.isEmpty) {
      ToastHelper.showWarning('선택한 인원 모두 급여가 계산됐거나 확정/이체 완료 상태라 리셋할 수 없습니다.');
      return;
    }

    final skipMsg = wageFinalized.isNotEmpty
        ? '\n\n⚠️ 급여 확정·이체 완료 ${wageFinalized.length}명은 제외됩니다.'
        : '';
    final names = resetTargets.map((a) => _getIdentifiedName(a.uid)).join(', ');
    final confirmed = await DialogHelper.showDangerConfirm(
      context,
      title: '출퇴근 기록 리셋',
      message: '${resetTargets.length}명의 출퇴근 기록을 초기화합니다.\n'
          '출근·퇴근 시간, 급여 계산 결과가 모두 삭제됩니다.$skipMsg\n\n$names',
      confirmText: '리셋',
    );
    if (!confirmed || !mounted) return;
    setState(() => _isLoading = true);

    // CF callableBatchResetAttendance 경유 — 서버에서 급여확정 건 재차 방어
    final resetIds = resetTargets
        .map((app) => _attendanceMap[app.id]?.id)
        .whereType<String>()
        .toList();

    try {
      final result = await FirebaseFunctions.instanceFor(region: 'asia-northeast3')
          .httpsCallable('callableBatchResetAttendance')
          .call({'businessId': _selectedBusinessId, 'attendanceIds': resetIds});
      if (!mounted) return;
      final processed = result.data['processed'] as int? ?? 0;
      _hasChanges = true;
      ToastHelper.showSuccess('리셋 완료 ($processed명)');
      // [R8-P1C] 서버가 바꾼 것은 근태 문서뿐이다 (리셋).
      await _refreshAttendanceOnly();
    } catch (e) {
      debugPrint('❌ 리셋 실패: $e');
      if (mounted) ToastHelper.showError('리셋 실패');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// 개별 선택/해제
  void _toggleSelection(String appId) {
    // [DU305] 이 근무를 새로 선택하면 처리 진입(일괄 버튼 첫 줄)만 맞춘다 — 목록은 사용자가 보고 있는 그 자리다.
    if (!_selectedIds.contains(appId)) _revealAfterSelection(list: false);
    setState(() {
      if (_selectedIds.contains(appId)) {
        _selectedIds.remove(appId);
        _selectAll = false;
      } else {
        _selectedIds.add(appId);
        // selectableCount는 _confirmedWorkers 전체가 아닌 현재 탭 기준으로 산정.
        //           _toggleSelectAll()과 동일한 기준을 써야 _selectAll 동기화가 정확함.
        final tabWorkers = _tabWorkers[_currentTabIndex];
        final selectableCount = tabWorkers.where((app) {
          final status = _getAttendanceStatus(app);
          return status['status'] != 'noshow';
        }).length;
        _selectAll = _selectedIds.length == selectableCount;
      }
    });
  }

  // ═══════════════════════════════════════════════════════════
  // 시간 입력 다이얼로그
  // ═══════════════════════════════════════════════════════════

  /// 시간 선택 다이얼로그 (휠 피커 바텀시트)
  Future<String?> _showTimePickerDialog({
    required String title,
    String? initialTime,
  }) async {
    TimeOfDay initial = TimeOfDay.now();
    
    if (initialTime != null) {
      try {
        final parts = initialTime.split(':');
        initial = TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
      } catch (e) {
        // 파싱 실패 시 현재 시간 사용
      }
    }

    final picked = await TimePickerBottomSheet.show(
      context: context,
      initialTime: initial,
      title: title,
      minuteInterval: 5,
      use24HourFormat: true,
    );

    if (picked != null) {
      return FormatHelper.formatHourMinute(picked.hour, picked.minute);
    }
    return null;
  }

  /// 일괄 시간 조정 다이얼로그 (이미 출근/퇴근한 인원의 시간을 일괄 수정)
  Future<void> _showBatchAdjustTimeDialog() async {
    if (_isLoading) return;
    if (_selectedIds.isEmpty) return;

    // 선택된 인원 중 출근 기록이 있는 인원만 대상
    final targets = _selectedIds
        .map((id) => _workerIdMap[id])
        .whereType<ApplicationModel>()
        .where((app) {
          final s = _getAttendanceStatus(app)['status'] as String;
          // 'transferred'(wageTransferred)는 'final_confirmed'(wageConfirmed)와 별개 UI 상태 —
          // 두 상태 모두 시간 수정 불가
          return s != 'pending' && s != 'noshow' &&
              s != 'final_confirmed' && s != 'transferred';
        })
        .toList();

    if (targets.isEmpty) {
      ToastHelper.showWarning('시간 조정 가능한 인원이 없습니다\n(출근 처리된 인원만 조정 가능)');
      return;
    }

    // 대표 예정 시간 (첫 번째 대상자 기준)
    final sampleApp = targets.first;
    final defaultCheckIn  = sampleApp.startTime.isNotEmpty ? sampleApp.startTime : '09:00';
    final defaultCheckOut = sampleApp.endTime.isNotEmpty   ? sampleApp.endTime   : '18:00';

    String? adjustCheckIn;
    String? adjustCheckOut;
    bool dialogApplyRounding = false;

    // [NDB-1 · DU-O001 디자인·브랜드 판정(11-18)] 직접 Dialog(M3 기본 연보라 면 · 독자 머리/구분선 · 높이 상한/본문 스크롤 없는 Column)를
    //   공용 StyledDialog 로 옮긴다 — 흰 셸 · 공용 머리/부제(큰 글자 낱말 재배치) · 높이 상한 + 본문 스크롤 · 공용 취소/주행동(큰 글자 세로 전환).
    //   안내 문장 · 대상 수 · 혼합 기준 경고 · 근태 기준 토글/미리보기 · 활성 조건 · 반환(true/false · 닫기 null = 미조정)은 그대로다.
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (ctx, setDialogState) => StyledDialog(
          title: '일괄 시간 조정',
          subtitle: '${targets.length}명 대상',
          icon: Icons.tune,
          headerColor: AppColors.brand,
          showCloseButton: true,
          maxWidth: 340,
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 안내 — 파랑 상자 대신 중립 본문 + 작은 공통 아이콘(문장 그대로)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: EdgeInsets.only(top: ResponsiveHelper.spacing(ctx, 1)),
                    child: Icon(Icons.info_outline, color: AppColors.textSecondary, size: ResponsiveHelper.iconSize(ctx, 16)),
                  ),
                  SizedBox(width: ResponsiveHelper.spacing(ctx, 8)),
                  Expanded(
                    child: Text(
                      _adjustKeepWords('입력한 시간으로만 조정됩니다.\n비워두면 해당 시간은 변경되지 않습니다.'),
                      semanticsLabel: '입력한 시간으로만 조정됩니다.\n비워두면 해당 시간은 변경되지 않습니다.',
                      style: ResponsiveHelper.tinyStyle(ctx, color: AppColors.textSecondary),
                    ),
                  ),
                ],
              ),

              // [R7-PAYROLL-POLICY.4] 대상자마다 **약속된 기준이 다를 수
              //   있다** — 지원 시점 기준이 지원서에 고정되기 때문이다.
              //   사업장 현재 설정 하나로 안내하면 관리자가 착각한다.
              if (_batchTargetsHaveMixedPolicy(targets)) ...[
                SizedBox(height: ResponsiveHelper.spacing(ctx, 8)),
                Text(
                  _adjustKeepWords('대상자마다 적용되는 근태 기준이 다릅니다.\n'
                      '각 근무에 약속된 기준으로 처리됩니다.'),
                  semanticsLabel: '대상자마다 적용되는 근태 기준이 다릅니다.\n'
                      '각 근무에 약속된 기준으로 처리됩니다.',
                  style: ResponsiveHelper.tinyStyle(ctx,
                      color: AppColors.warningDark),
                ),
              ],

              // 반올림 정책 토글 (정책 설정된 사업장에서만 표시)
              //   [NDB-1] 켜짐 강조 info(파랑) → 공통 선택 강조 brand · 꺼짐은 중립(흰 면 · 옅은 선 · M3 연보라 기본 트랙 대신 회색).
              if (_attendanceRules != null) ...[
                SizedBox(height: ResponsiveHelper.spacing(ctx, 10)),
                InkWell(
                  onTap: () => setDialogState(() => dialogApplyRounding = !dialogApplyRounding),
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    constraints: const BoxConstraints(minHeight: 48),
                    padding: EdgeInsets.symmetric(
                      horizontal: ResponsiveHelper.spacing(ctx, 12),
                      vertical: ResponsiveHelper.spacing(ctx, 6),
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: dialogApplyRounding ? AppColors.brand : AppColors.borderLight,
                        width: dialogApplyRounding ? 1.5 : 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.auto_fix_high,
                          size: ResponsiveHelper.iconSize(ctx, 16),
                          color: dialogApplyRounding ? AppColors.brand : AppColors.textSecondary,
                        ),
                        SizedBox(width: ResponsiveHelper.spacing(ctx, 8)),
                        Expanded(
                          child: Text(
                            // [R7-PAYROLL-POLICY.4] 적용되는 것은 **이 근무에
                            //   약속된 기준**이다. 확정 뒤 설정을 바꾼
                            //   사업장에서 '사업장 정책' 은 틀린 말이 된다.
                            // [ROUNDING-PREVIEW.27] 짧게 — 확인 창 제목과 같은 말.
                            _adjustKeepWords('근태 기준 적용'),
                            semanticsLabel: '근태 기준 적용',
                            style: ResponsiveHelper.smallStyle(ctx).copyWith(
                              fontWeight: FontWeight.w600,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ),
                        Switch(
                          value: dialogApplyRounding,
                          onChanged: (v) => setDialogState(() => dialogApplyRounding = v),
                          activeThumbColor: AppColors.surface,
                          activeTrackColor: AppColors.brand,
                          inactiveThumbColor: AppColors.grey500,
                          inactiveTrackColor: AppColors.grey200,
                          trackOutlineColor: WidgetStateProperty.resolveWith(
                            (s) => s.contains(WidgetState.selected) ? AppColors.brand : AppColors.border,
                          ),
                          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                      ],
                    ),
                  ),
                ),
                // [ROUNDING-PREVIEW.27] 켜면 무엇으로 기록되는지 조정 전에 보여 준다.
                if (dialogApplyRounding && (adjustCheckIn != null || adjustCheckOut != null))
                  Builder(builder: (_) {
                    final rows = _adjustPreviews(targets, adjustCheckIn, adjustCheckOut);
                    final changed = rows.where((r) => r.applied != r.raw).toList();
                    return Padding(
                      padding: EdgeInsets.only(top: ResponsiveHelper.spacing(ctx, 6)),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (changed.isEmpty)
                            Text(_adjustKeepWords('적용해도 입력한 시각 그대로예요'),
                                semanticsLabel: '적용해도 입력한 시각 그대로예요',
                                style: ResponsiveHelper.tinyStyle(ctx, color: AppColors.textSecondary)),
                          for (final r in changed.take(3))
                            Text(_adjustKeepWords('${r.name} ${r.shift}: ${r.applied}'),
                                semanticsLabel: '${r.name} ${r.shift}: ${r.applied}',
                                style: ResponsiveHelper.tinyStyle(ctx, color: AppColors.textPrimary)
                                    .copyWith(fontWeight: FontWeight.w600)),
                          if (changed.length > 3)
                            Text(_adjustKeepWords('외 ${changed.length - 3}명도 바뀌어요'),
                                semanticsLabel: '외 ${changed.length - 3}명도 바뀌어요',
                                style: ResponsiveHelper.tinyStyle(ctx, color: AppColors.textPrimary)),
                          if (changed.isNotEmpty && rows.length > changed.length)
                            Text(_adjustKeepWords('나머지 ${rows.length - changed.length}명은 입력한 시각 그대로예요'),
                                semanticsLabel: '나머지 ${rows.length - changed.length}명은 입력한 시각 그대로예요',
                                style: ResponsiveHelper.tinyStyle(ctx, color: AppColors.textSecondary)),
                        ],
                      ),
                    );
                  }),
              ],

              SizedBox(height: ResponsiveHelper.spacing(ctx, 16)),

              // 출근 시간 조정
              _buildAdjustRow(
                icon: Icons.login,
                label: '출근 시간',
                value: adjustCheckIn,
                quickLabel: '예정($defaultCheckIn)',
                onQuickTap: () => setDialogState(() => adjustCheckIn = defaultCheckIn),
                onTap: () async {
                  final t = await _showTimePickerDialog(
                    title: '출근 시간 조정',
                    initialTime: adjustCheckIn ?? defaultCheckIn,
                  );
                  if (t != null) setDialogState(() => adjustCheckIn = t);
                },
                onClear: adjustCheckIn != null ? () => setDialogState(() => adjustCheckIn = null) : null,
              ),

              SizedBox(height: ResponsiveHelper.spacing(ctx, 10)),

              // 퇴근 시간 조정
              _buildAdjustRow(
                icon: Icons.logout,
                label: '퇴근 시간',
                value: adjustCheckOut,
                quickLabel: '예정($defaultCheckOut)',
                onQuickTap: () => setDialogState(() => adjustCheckOut = defaultCheckOut),
                onTap: () async {
                  final t = await _showTimePickerDialog(
                    title: '퇴근 시간 조정',
                    initialTime: adjustCheckOut ?? defaultCheckOut,
                  );
                  if (t != null) setDialogState(() => adjustCheckOut = t);
                },
                onClear: adjustCheckOut != null ? () => setDialogState(() => adjustCheckOut = null) : null,
              ),
            ],
          ),
          actions: [
            StyledDialogButton.cancel(
              onPressed: () => Navigator.pop(dialogContext, false),
            ),
            // [DU505] 흰 글자 채움 brand(5.58) 유지 — 비활성은 공용 비활성(grey200 · textSecondary).
            StyledDialogButton.primary(
              text: '조정하기',
              backgroundColor: AppColors.brand,
              onPressed: (adjustCheckIn != null || adjustCheckOut != null)
                  ? () => Navigator.pop(dialogContext, true)
                  : null,
            ),
          ],
        ),
      ),
    );

    if (confirmed == true) {
      if (!context.mounted) return;
      await _processBatchAdjustTime(targets, adjustCheckIn, adjustCheckOut, applyRounding: dialogApplyRounding);
    }
  }

  /// [NDB-1] 일괄 시간 조정 창 글 — 줄('\n')마다 낱말 단위로 묶는다(큰 글자 음절 끊김 방지). 읽기 이름은 호출부가 원문으로 준다.
  static String _adjustKeepWords(String s) => s.split('\n').map(TextLayout.keepWords).join('\n');

  /// 일괄 시간 조정 행 위젯
  ///   [NDB-1 · DU-O001 판정] 출근 초록 · 퇴근 보라가 아이콘 · 행 면/선 · 시간 글자 · 예정 칩까지 번지던 것을 같은 중립 계열로 —
  ///   출근/퇴근 구분은 라벨과 login/logout 아이콘. 값 있음 = 진한 시간 글자 + brand 선(공통 선택 강조) · 미설정 = 읽히는 보조 글자 + 옅은 선.
  ///   라벨/값 줄과 조작(예정 · 직접) 줄을 나눠 좁은 폭 · 큰 글자에서 한 줄로 밀어 넣지 않는다(Wrap). 조작 · 지우기 터치 48.
  ///   글자 축소 · 말줄임 · 배율 제한 없음. 콜백 · 값 · '필터 삭제' 읽기 이름은 그대로다.
  Widget _buildAdjustRow({
    required IconData icon,
    required String label,
    required String? value,
    required String quickLabel,
    required VoidCallback onQuickTap,
    required VoidCallback onTap,
    VoidCallback? onClear,
  }) {
    final has = value != null;
    Widget action(String text, VoidCallback onPressed) => InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(8),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48, minWidth: 48),
            child: Align(
              widthFactor: 1,
              heightFactor: 1,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.border),
                ),
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: ResponsiveHelper.spacing(context, 12),
                    vertical: ResponsiveHelper.spacing(context, 6),
                  ),
                  child: Text(
                    _adjustKeepWords(text),
                    semanticsLabel: text,
                    style: ResponsiveHelper.smallStyle(context, color: AppColors.textPrimary).copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ),
          ),
        );
    return Container(
      padding: EdgeInsets.fromLTRB(
        ResponsiveHelper.spacing(context, 12),
        ResponsiveHelper.spacing(context, 8),
        ResponsiveHelper.spacing(context, 4),
        ResponsiveHelper.spacing(context, 8),
      ),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: has ? AppColors.brand : AppColors.borderLight,
          width: has ? 1.5 : 1,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 8)),
                decoration: BoxDecoration(color: AppColors.grey100, borderRadius: BorderRadius.circular(8)),
                child: Icon(icon, color: AppColors.textSecondary, size: ResponsiveHelper.iconSize(context, 18)),
              ),
              SizedBox(width: ResponsiveHelper.spacing(context, 10)),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _adjustKeepWords(label),
                      semanticsLabel: label,
                      style: ResponsiveHelper.tinyStyle(context, color: AppColors.textSecondary),
                    ),
                    Text(
                      value ?? '미설정',
                      style: ResponsiveHelper.bodyStyle(context).copyWith(
                        fontWeight: has ? FontWeight.w700 : FontWeight.w400,
                        color: has ? AppColors.textPrimary : AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              if (onClear != null)
                Semantics(
                  button: true,
                  label: '필터 삭제',
                  child: GestureDetector(
                    onTap: onClear,
                    behavior: HitTestBehavior.opaque,
                    child: SizedBox(
                      width: 48,
                      height: 48,
                      child: Center(
                        child: Icon(Icons.close, color: AppColors.textSecondary, size: ResponsiveHelper.iconSize(context, 18)),
                      ),
                    ),
                  ),
                )
              else
                const SizedBox(height: 48),
            ],
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 4)),
          Wrap(
            spacing: ResponsiveHelper.spacing(context, 8),
            children: [
              action(quickLabel, onQuickTap),
              action('직접', onTap),
            ],
          ),
        ],
      ),
    );
  }

  /// 일괄 시간 조정 처리 — CF callableBatchAdjustAttendanceTime 경유
  Future<void> _processBatchAdjustTime(
    List<ApplicationModel> targets,
    String? newCheckIn,
    String? newCheckOut, {
    bool applyRounding = false,
  }) async {
    if (_isLoading) return;
    setState(() => _isLoading = true);
    try {
      // 로컬 검증 후 CF에 전달할 entries 빌드
      final entries = <Map<String, dynamic>>[];
      final lateChanges = <({ApplicationModel app, String oldCheckIn, bool wasLate, bool isNowLate})>[];
      int skipCount = 0;

      for (final app in targets) {
        final attendance = _attendanceMap[app.id];
        if (attendance == null) continue;

        // 클라이언트 사전 필터 (서버에서도 재검증)
        if (attendance.wageStatus == AttendanceModel.wageConfirmed ||
            attendance.wageStatus == AttendanceModel.wageTransferred) {
          skipCount++;
          continue;
        }

        // 반올림 적용 시 per-worker 유효 시간 결정
        final resolvedCheckIn = (applyRounding && newCheckIn != null)
            ? _roundedCheckIn(app, newCheckIn)
            : newCheckIn;

        final effectiveCheckIn = resolvedCheckIn ?? attendance.checkIn ?? WorkDetailHelper.effectiveStart(app, _workDetailTimeMap);

        // 퇴근 반올림: 출근 기준 DateTime 먼저 결정
        final checkInDtForOut = resolvedCheckIn != null
            ? _hmToDateTime(_kstDay, resolvedCheckIn)
            : attendance.checkInAt ?? _hmToDateTime(_kstDay, effectiveCheckIn);

        final resolvedCheckOut = (applyRounding && newCheckOut != null)
            ? _roundedCheckOut(app, checkInDtForOut, newCheckOut)
            : newCheckOut;

        final effectiveCheckOut = resolvedCheckOut ?? attendance.checkOut;

        // 시간 역전 검사 (출퇴근 모두 있을 때만)
        if (effectiveCheckOut != null &&
            !AttendanceStatusHelper.isValidWorkPeriod(effectiveCheckIn, effectiveCheckOut)) {
          skipCount++;
          continue;
        }

        final entry = <String, dynamic>{
          'attendanceId': attendance.id,
          'status': _deriveStatus(app, effectiveCheckIn, effectiveCheckOut),
          'resetWageDetail': attendance.wageStatus == AttendanceModel.wageCalculated,
        };
        if (newCheckIn != null) {
          entry['checkInMs'] = _hmToKstEpochMs(_kstDay, effectiveCheckIn);
        }
        if (newCheckOut != null) {
          entry['checkOutMs'] = _hmCheckoutToKstEpochMs(_kstDay, checkInDtForOut, resolvedCheckOut!);
        }
        if (effectiveCheckOut != null) {
          entry['workHours'] = _calcWorkHoursCompat(effectiveCheckIn, effectiveCheckOut);
        }
        entries.add(entry);

        // 지각 변동 사전 계산 (CF 성공 후 처리) — 반올림 적용 시 resolvedCheckIn 기준
        if (newCheckIn != null) {
          final expectedStartTime = WorkDetailHelper.effectiveStart(app, _workDetailTimeMap);
          final oldCheckIn = attendance.checkIn;
          final wasLate = oldCheckIn != null &&
              AttendanceStatusHelper.isLate(
                oldCheckIn, expectedStartTime,
                isNextDay: AttendanceStatusHelper.isNextDayCheckIn(oldCheckIn, expectedStartTime),
              );
          final isNowLate = AttendanceStatusHelper.isLate(
            effectiveCheckIn, expectedStartTime,
            isNextDay: AttendanceStatusHelper.isNextDayCheckIn(effectiveCheckIn, expectedStartTime),
          );
          if (wasLate != isNowLate) {
            lateChanges.add((app: app, oldCheckIn: oldCheckIn ?? '', wasLate: wasLate, isNowLate: isNowLate));
          }
        }
      }

      if (entries.isEmpty) {
        if (!mounted) return;
        if (skipCount > 0) ToastHelper.showWarning('$skipCount명은 급여 확정/이체 완료로 수정 불가');
        return;
      }

      // [PREDEVICE-ADJUST-REASON] 근태 시간을 바꾸는 것은 곧 금액을 바꾸는 일이다.
      //   누가 언제 고쳤는지는 남지만 왜 고쳤는지가 없으면, 나중에 그 금액이
      //   맞았는지 아무도 되짚을 수 없다. 서버도 같은 이유로 사유 없는 시간
      //   변경을 거절하므로, 여기서 받지 않으면 저장 자체가 실패한다.
      //   실제로 시각이 달라지는 건이 하나라도 있을 때만 묻는다.
      if (!mounted) return;
      final reason = await DialogHelper.showTextInput(
        context,
        title: '근태 수정 사유',
        message: '왜 시간을 바꾸는지 적어주세요. 급여 확인에 사용됩니다.',
        hintText: '예: 실제 업무 시작 시각 확인',
        maxLines: 2,
        maxLength: 200,
        icon: Icons.edit_calendar_outlined,
        validator: (v) => (v ?? '').trim().isNotEmpty,
      );
      if (reason == null || reason.trim().isEmpty) {
        // 취소 — 아무것도 바꾸지 않는다.
        return;
      }
      for (final e in entries) {
        e['reason'] = reason.trim();
      }

      final result = await FirebaseFunctions.instanceFor(region: 'asia-northeast3')
          .httpsCallable('callableBatchAdjustAttendanceTime',
              options: HttpsCallableOptions(timeout: const Duration(seconds: 60)))
          .call({'businessId': _selectedBusinessId, 'entries': entries});

      final processed = result.data['processed'] as int? ?? 0;
      final skipped = (result.data['skipped'] as List?)?.length ?? 0;
      final totalSkip = skipCount + skipped;

      if (!mounted) return;
      if (processed > 0) ToastHelper.showSuccess('$processed명 시간 조정 완료');
      if (totalSkip > 0) ToastHelper.showWarning('$totalSkip명 처리 불가 (급여 확정/이체 완료)');

      // [LATE-CANCEL] CF 성공 후 지각 신뢰도 연동
      final lateCallable = FirebaseFunctions.instanceFor(region: 'asia-northeast3')
          .httpsCallable('callableReportLate',
              options: HttpsCallableOptions(timeout: const Duration(seconds: 10)));
      await Future.wait(lateChanges.map((change) async {
        final attendanceId = _attendanceMap[change.app.id]?.id;
        if (attendanceId == null) {
          debugPrint('⚠️ callableReportLate 건너뜀: attendanceId 없음 (appId=${change.app.id})');
          return;
        }
        try {
          await lateCallable.call({
            'userId': change.app.uid,
            'businessId': change.app.businessId,
            'mode': change.wasLate && !change.isNowLate ? 'late_canceled' : 'late',
            'attendanceId': attendanceId,
          });
        } catch (cfErr) {
          debugPrint('⚠️ callableReportLate 실패 (무시): $cfErr');
        }
      }));

      _hasChanges = true;
      // [R8-P1C] 서버가 바꾼 것은 근태 문서뿐이다 (시간수정).
      await _refreshAttendanceOnly();
    } catch (e) {
      debugPrint('❌ 일괄 시간 조정 실패: $e');
      if (mounted) ToastHelper.showError('일괄 시간 조정 실패');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// 일괄 출근 다이얼로그
  Future<void> _showBatchCheckInDialog() async {
    if (_isLoading || _selectedIds.isEmpty) return;

    // 파트별 그룹화
    final Map<String, List<ApplicationModel>> groups = {};
    for (final id in _selectedIds) {
      final app = _workerIdMap[id];
      if (app == null) continue;
      final key = '${app.selectedWorkType}_${app.startTime}_${app.endTime}';
      groups.putIfAbsent(key, () => []).add(app);
    }

    if (groups.length <= 1) {
      // 단일 파트 → 기존 시트
      final scheduledTimes = _selectedIds
          .map((id) {
            final app = _workerIdMap[id];
            if (app == null) return '';
            return WorkDetailHelper.effectiveStart(app, _workDetailTimeMap);
          })
          .where((t) => t.isNotEmpty)
          .toSet()
          .toList();
      final time = await AttendanceQuickTimeSheet.show(
        context: context,
        title: '일괄 출근 (${_selectedIds.length}명)',
        scheduledTimes: scheduledTimes.isEmpty ? null : scheduledTimes,
        isCheckIn: true,
      );
      if (time != null) {
        if (!mounted) return;
        // 반올림 정책 있을 때 — 달라지는 케이스 있으면 프리뷰 다이얼로그 표시
        bool applyRounding = false;
        if (_attendanceRules != null) {
          final pendingApps = _selectedIds
              .map((id) => _workerIdMap[id])
              .whereType<ApplicationModel>()
              .where((app) => _getAttendanceStatus(app)['status'] == 'pending')
              .toList();
          final wouldChange = pendingApps.any((app) => _roundedCheckIn(app, time) != time);
          if (wouldChange) {
            final choice = await _showRoundingPreviewDialog(
                isCheckIn: true, rows: _checkInPreviews(pendingApps, time));
            if (!mounted) return;
            if (choice == null) return;
            applyRounding = choice;
          }
        }
        await _processBatchCheckIn(time, applyRounding: applyRounding);
      }
    } else {
      // 복수 파트 → 파트별 다이얼로그
      final groupTimes = await _showBatchByGroupDialog(groups, isCheckIn: true);
      if (groupTimes != null) {
        if (!mounted) return;
        bool applyRounding = false;
        if (_attendanceRules != null) {
          final wouldChange = groupTimes.entries.any((e) =>
            (groups[e.key] ?? []).any((app) => _roundedCheckIn(app, e.value) != e.value)
          );
          if (wouldChange) {
            final choice = await _showRoundingPreviewDialog(isCheckIn: true, rows: [
              for (final e in groupTimes.entries)
                ..._checkInPreviews(
                    (groups[e.key] ?? const <ApplicationModel>[])
                        .where((a) => _selectedIds.contains(a.id)),
                    e.value),
            ]);
            if (!mounted) return;
            if (choice == null) return;
            applyRounding = choice;
          }
        }
        await _processBatchCheckInByGroup(groupTimes, applyRounding: applyRounding);
      }
    }
  }

  /// 일괄 퇴근 다이얼로그
  Future<void> _showBatchCheckOutDialog() async {
    if (_isLoading || _selectedIds.isEmpty) return;

    // 출근했으나 퇴근 미처리 인원만 필터 (checkin / late / missed_checkout)
    final checkedInIds = _selectedIds.where((id) {
      final app = _workerIdMap[id];
      if (app == null) return false;
      final s = _getAttendanceStatus(app)['status'] as String;
      return s == 'checkin' || s == 'late' || s == 'missed_checkout';
    }).toList();

    if (checkedInIds.isEmpty) {
      ToastHelper.showWarning('출근 처리된 인원만 퇴근 처리할 수 있습니다');
      return;
    }

    // 파트별 그룹화 (퇴근 가능 인원 기준)
    final Map<String, List<ApplicationModel>> groups = {};
    for (final id in checkedInIds) {
      final app = _workerIdMap[id];
      if (app == null) continue;
      final key = '${app.selectedWorkType}_${app.startTime}_${app.endTime}';
      groups.putIfAbsent(key, () => []).add(app);
    }

    if (groups.length <= 1) {
      // 단일 파트 → 기존 시트
      final scheduledTimes = checkedInIds
          .map((id) {
            final app = _workerIdMap[id];
            if (app == null) return '';
            return WorkDetailHelper.effectiveEnd(app, _workDetailTimeMap);
          })
          .where((t) => t.isNotEmpty)
          .toSet()
          .toList();
      final time = await AttendanceQuickTimeSheet.show(
        context: context,
        title: '일괄 퇴근 (${checkedInIds.length}명)',
        scheduledTimes: scheduledTimes.isEmpty ? null : scheduledTimes,
        isCheckIn: false,
      );
      if (time != null) {
        if (!mounted) return;
        bool applyRounding = false;
        if (_attendanceRules != null) {
          final checkedInApps = checkedInIds
              .map((id) => _workerIdMap[id])
              .whereType<ApplicationModel>()
              .toList();
          final wouldChange = checkedInApps.any((app) {
            final attendance = _attendanceMap[app.id];
            if (attendance == null) return false;
            final checkInDt = attendance.checkInAt ??
                _hmToDateTime(_kstDay, attendance.checkIn ?? WorkDetailHelper.effectiveStart(app, _workDetailTimeMap));
            return _roundedCheckOut(app, checkInDt, time) != time;
          });
          if (wouldChange) {
            final choice = await _showRoundingPreviewDialog(
                isCheckIn: false, rows: _checkOutPreviews(checkedInApps, time));
            if (!mounted) return;
            if (choice == null) return;
            applyRounding = choice;
          }
        }
        await _processBatchCheckOut(time, checkedInIds, applyRounding: applyRounding);
      }
    } else {
      // 복수 파트 → 파트별 다이얼로그
      final groupTimes = await _showBatchByGroupDialog(groups, isCheckIn: false);
      if (groupTimes != null) {
        if (!mounted) return;
        bool applyRounding = false;
        if (_attendanceRules != null) {
          final wouldChange = groupTimes.entries.any((e) {
            final apps = groups[e.key] ?? [];
            return apps.any((app) {
              final attendance = _attendanceMap[app.id];
              if (attendance == null) return false;
              final checkInDt = attendance.checkInAt ??
                  _hmToDateTime(_kstDay, attendance.checkIn ?? WorkDetailHelper.effectiveStart(app, _workDetailTimeMap));
              return _roundedCheckOut(app, checkInDt, e.value) != e.value;
            });
          });
          if (wouldChange) {
            final choice = await _showRoundingPreviewDialog(isCheckIn: false, rows: [
              for (final e in groupTimes.entries)
                ..._checkOutPreviews(
                    (groups[e.key] ?? const <ApplicationModel>[])
                        .where((a) => checkedInIds.contains(a.id)),
                    e.value),
            ]);
            if (!mounted) return;
            if (choice == null) return;
            applyRounding = choice;
          }
        }
        await _processBatchCheckOutByGroup(groupTimes, checkedInIds, applyRounding: applyRounding);
      }
    }
  }

  /// 파트별 시간 설정 다이얼로그 (출근/퇴근 공용)
  /// Returns: groupKey → time 맵, 취소 시 null
  Future<Map<String, String>?> _showBatchByGroupDialog(
    Map<String, List<ApplicationModel>> groups, {
    required bool isCheckIn,
  }) async {
    // [UI-4] 기본 시각은 KST 벽시계 — 기기 시간대의 시·분이 아니다(단일 파트 시트와 같은 함수).
    final now = AttendanceQuickTimeSheet.roundedKstNow();
    final nowStr = FormatHelper.formatHourMinute(now.hour, now.minute);

    final Map<String, String> selectedTimes = {};
    for (final entry in groups.entries) {
      final firstApp = entry.value.first;
      final effT = isCheckIn
          ? WorkDetailHelper.effectiveStart(firstApp, _workDetailTimeMap)
          : WorkDetailHelper.effectiveEnd(firstApp, _workDetailTimeMap);
      selectedTimes[entry.key] = effT.isNotEmpty ? effT : nowStr;
    }

    final actionColor = isCheckIn ? AppColors.success : AppColors.purple;
    final actionLabel = isCheckIn ? '출근' : '퇴근';
    final actionIcon = isCheckIn ? Icons.login : Icons.logout;
    // [DU303] 출근/퇴근 의미는 머리 아이콘에만 둔다(자식 시트와 같은 짝) — 출근 success 전경 → successDark, 퇴근 purple 그대로.
    final actionIconColor = isCheckIn ? AppColors.successDark : AppColors.purple;
    final totalCount = groups.values.fold(0, (s, l) => s + l.length);

    // [DU303 가2] 시각 줄 필요폭 — 실제 렌더와 같은 상속 스타일(DefaultTextStyle 병합)·TextScaler·locale·방향으로 잰다.
    //   화면 폭·글자 배율 임계값으로 나누지 않는다. 비선형 배율도 TextPainter 가 그대로 받는다.
    double textWidthIn(BuildContext c, String text, TextStyle style) {
      final dts = DefaultTextStyle.of(c);
      final tp = TextPainter(
        text: TextSpan(text: text, style: style),
        textDirection: Directionality.of(c),
        textScaler: MediaQuery.textScalerOf(c),
        locale: Localizations.maybeLocaleOf(c),
        textWidthBasis: dts.textWidthBasis,
        textHeightBehavior: dts.textHeightBehavior,
      )..layout();
      final w = tp.maxIntrinsicWidth;
      tp.dispose();
      return w;
    }

    return showDialog<Map<String, String>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final theme = Theme.of(ctx);
          return Dialog(
            // [DU308 Standards §12.2] 본문 배경을 명시한다 — 미지정이면 M3 기본(colorScheme.surfaceContainerHigh)의
            //   옅은 보라 기운이 넓은 본문 전체에 깔렸다. 공용 확인창(StyledDialog)과 같은 흰 바탕.
            backgroundColor: AppColors.surface,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(ctx).size.height * AppDialogSize.subSheetHeightRatio,
                maxWidth: 420,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // ── 헤더 ──
                  // [DU308 §12.2] 머리 전체 의미색 면(출근 success / 퇴근 purple α.10)을 걷는다 — 흰 바탕 그대로.
                  //   출근/퇴근 의미는 아래 작은 아이콘 타일(α.15)과 제목 글자가 계속 말한다(자식 시트와 같은 짝).
                  Container(
                    padding: ResponsiveHelper.cardPadding(ctx),
                    child: Row(
                      children: [
                        Container(
                          padding: EdgeInsets.all(ResponsiveHelper.spacing(ctx, 10)),
                          decoration: BoxDecoration(
                            color: actionColor.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(actionIcon, color: actionIconColor,
                              size: ResponsiveHelper.iconSize(ctx, 22)),
                        ),
                        SizedBox(width: ResponsiveHelper.spacing(ctx, 12)),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // [DU308 · 감사303 §4 BACKLOG] B320/2.0 의 `일괄 출 / 근` — 표시만 낱말 사이에서 줄바꿈(의미 이름 원문).
                              Text(TextLayout.keepWords('파트별 일괄 $actionLabel'),
                                  semanticsLabel: '파트별 일괄 $actionLabel',
                                  style: ResponsiveHelper.subtitleStyle(ctx)
                                      .copyWith(fontWeight: FontWeight.bold)),
                              // [R7-P1-3] 일괄 처리 대상은 근무 건이다 —
                              //   한 사람이 하루에 두 파트를 가질 수 있고,
                              //   workDetailId 가 없는 구 문서는 한 파트로 합쳐진다.
                              // [DU308] 구분점 조각 사이에서만 줄바꿈(`3건 선택`·`2개 파트` 안을 끊지 않는다).
                              Text(TextLayout.phrases('$totalCount건 선택 · ${groups.length}개 파트'),
                                  semanticsLabel: '$totalCount건 선택 · ${groups.length}개 파트',
                                  style: ResponsiveHelper.smallStyle(ctx,
                                      color: AppColors.grey600)),
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.pop(dialogContext),
                          // [DU303] 닫기 누름 48×48·중립 보조색(자식 시트와 같음)
                          constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                          icon: const Icon(Icons.close, color: AppColors.textSecondary),
                          padding: EdgeInsets.zero,
                        ),
                      ],
                    ),
                  ),

                  // ── 바디 ──
                  Flexible(
                    child: SingleChildScrollView(
                      padding: ResponsiveHelper.cardPadding(ctx),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // 현재 시간 전체 설정 버튼
                          OutlinedButton.icon(
                            onPressed: () {
                              final n = AttendanceQuickTimeSheet.roundedKstNow();
                              final t = FormatHelper.formatHourMinute(n.hour, n.minute);
                              setDialogState(() {
                                for (final k in selectedTimes.keys.toList()) {
                                  selectedTimes[k] = t;
                                }
                              });
                            },
                            icon: Icon(Icons.access_time,
                                size: ResponsiveHelper.iconSize(ctx, 16),
                                color: AppColors.grey700),
                            // [DU308 · 감사303 §4 BACKLOG] `현재 시간으로 전 / 체 설정` — 낱말 사이에서만 줄바꿈(의미 이름 원문).
                            label: Text(TextLayout.keepWords('현재 시간으로 전체 설정'),
                                semanticsLabel: '현재 시간으로 전체 설정',
                                style: ResponsiveHelper.smallStyle(ctx,
                                    color: AppColors.grey700)),
                            style: OutlinedButton.styleFrom(
                              side: BorderSide(color: AppColors.border),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10)),
                              padding: EdgeInsets.symmetric(
                                  vertical: ResponsiveHelper.spacing(ctx, 10)),
                            ),
                          ),

                          SizedBox(height: ResponsiveHelper.spacing(ctx, 14)),

                          // 파트별 행
                          ...groups.entries.map((entry) {
                            final groupKey = entry.key;
                            final workers = entry.value;
                            // groups는 putIfAbsent(...).add() 로 생성 — 각 value 최소 1개 보장, .first 안전
                            final firstApp = workers.first;
                            final workTypeInfo = _workTypeMap[firstApp.selectedWorkType];
                            final dotColor = workTypeInfo?.color != null
                                ? FormatHelper.parseColor(workTypeInfo!.color!)
                                : theme.primaryColor;

                            return Container(
                              margin: EdgeInsets.only(
                                  bottom: ResponsiveHelper.spacing(ctx, 10)),
                              padding: ResponsiveHelper.cardPadding(ctx),
                              decoration: BoxDecoration(
                                color: AppColors.grey50,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: AppColors.border),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // 파트명 + 근무 건수
                                  Row(
                                    children: [
                                      Container(
                                        width: 10, height: 10,
                                        decoration: BoxDecoration(
                                            color: dotColor, shape: BoxShape.circle),
                                      ),
                                      SizedBox(width: ResponsiveHelper.spacing(ctx, 8)),
                                      Expanded(
                                        child: Text(
                                          // [R7-P1-3] 혼합 파트를 첫 업무로 말하지 않는다.
                                          _isMixedRelationGroup(workers)
                                              ? '여러 업무 ${workers.map((a) => a.selectedWorkType.trim()).where((t) => t.isNotEmpty).toSet().length}종'
                                              : firstApp.selectedWorkType,
                                          style: ResponsiveHelper.bodyStyle(ctx)
                                              .copyWith(fontWeight: FontWeight.bold),
                                        ),
                                      ),
                                      Container(
                                        padding: EdgeInsets.symmetric(
                                          horizontal: ResponsiveHelper.spacing(ctx, 8),
                                          vertical: ResponsiveHelper.spacing(ctx, 3),
                                        ),
                                        decoration: BoxDecoration(
                                          color: theme.primaryColor.withValues(alpha: 0.1),
                                          borderRadius: BorderRadius.circular(10),
                                        ),
                                        child: Text('${workers.length}건',
                                            style: ResponsiveHelper.tinyStyle(ctx,
                                                color: theme.primaryColor)),
                                      ),
                                    ],
                                  ),
                                  SizedBox(height: ResponsiveHelper.spacing(ctx, 4)),
                                  Text(
                                    '예정 ${firstApp.startTime} ~ ${firstApp.endTime}',
                                    style: ResponsiveHelper.smallStyle(ctx,
                                        color: AppColors.grey500),
                                  ),
                                  SizedBox(height: ResponsiveHelper.spacing(ctx, 10)),
                                  // 시간 표시 + 변경 버튼
                                  // [DU303 가2] 실제 필요폭이 이 줄의 가용폭을 넘을 때만 세로로 놓는다:
                                  //   위 전폭 시각 상자 → 기존 8 간격 → 끝쪽 정렬 변경(전폭으로 늘리지 않음).
                                  //   들어가면 기존 Expanded(시각 상자) + 간격 + 변경 Row 그대로다.
                                  LayoutBuilder(builder: (rowCtx, rowCons) {
                                    final timeText = selectedTimes[groupKey] ?? '--:--';
                                    final timeStyle = ResponsiveHelper.bodyStyle(ctx).copyWith(
                                      color: AppColors.textPrimary,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 1,
                                    );
                                    final changeTextStyle = ResponsiveHelper.smallStyle(ctx,
                                            color: AppColors.brand)
                                        .copyWith(fontWeight: FontWeight.bold);
                                    final boxPadH = ResponsiveHelper.spacing(ctx, 14);
                                    final iconSize = ResponsiveHelper.iconSize(ctx, 15);
                                    final iconGap = ResponsiveHelper.spacing(ctx, 6);
                                    final rowGap = ResponsiveHelper.spacing(ctx, 8);
                                    final changePadH = ResponsiveHelper.spacing(ctx, 14);
                                    const changeMin = Size(64, 48);
                                    // [DU303] 의미색 면·선 → 중립 단색 면 + 본문색 숫자(자식 시트와 같은 표현). 크기·반경 그대로
                                    final timeBox = Container(
                                      padding: EdgeInsets.symmetric(
                                        horizontal: boxPadH,
                                        vertical: ResponsiveHelper.spacing(ctx, 10),
                                      ),
                                      decoration: BoxDecoration(
                                        color: AppColors.grey100,
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(color: AppColors.border),
                                      ),
                                      child: Row(
                                        children: [
                                          Icon(Icons.check_circle_outline,
                                              size: iconSize,
                                              color: AppColors.textSecondary),
                                          SizedBox(width: iconGap),
                                          Text(timeText, style: timeStyle),
                                        ],
                                      ),
                                    );
                                    final changeButton = OutlinedButton(
                                      onPressed: () async {
                                        final t = await AttendanceQuickTimeSheet.show(
                                          context: ctx,
                                          title:
                                              '${firstApp.selectedWorkType} $actionLabel 시간',
                                          scheduledTimes: (() {
                                            final t = isCheckIn
                                                ? WorkDetailHelper.effectiveStart(firstApp, _workDetailTimeMap)
                                                : WorkDetailHelper.effectiveEnd(firstApp, _workDetailTimeMap);
                                            return t.isNotEmpty ? [t] : null;
                                          })(),
                                          isCheckIn: isCheckIn,
                                        );
                                        if (t != null) {
                                          setDialogState(() => selectedTimes[groupKey] = t);
                                        }
                                      },
                                      // [DU303] 변경은 일반 진행 — brand 글자·외곽선, 누름 최소 64×48(테마 하한 유지)
                                      style: OutlinedButton.styleFrom(
                                        side: const BorderSide(color: AppColors.brand),
                                        foregroundColor: AppColors.brand,
                                        minimumSize: changeMin,
                                        shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(10)),
                                        padding: EdgeInsets.symmetric(
                                          horizontal: changePadH,
                                          vertical: ResponsiveHelper.spacing(ctx, 10),
                                        ),
                                      ),
                                      child: Text('변경', style: changeTextStyle),
                                    );
                                    // 필요폭: 상자(좌우 padding + 테두리 1×2 + 아이콘 + 간격 + 실제 시각 글자) + 줄 간격 + 변경 실제 폭.
                                    //   변경 글자는 버튼이 까는 글자 스타일(로컬 → 테마 → SDK 기본 labelLarge)에 병합해 잰다.
                                    //   변경 폭은 그 글자 + 좌우 padding(밀도 보정 포함)과 최소 폭(밀도 보정 포함) 중 큰 값이다.
                                    final rowDts = DefaultTextStyle.of(rowCtx).style;
                                    final timeW = textWidthIn(rowCtx, timeText, rowDts.merge(timeStyle));
                                    final buttonBase = OutlinedButtonTheme.of(rowCtx).style?.textStyle?.resolve(const <WidgetState>{}) ??
                                        Theme.of(rowCtx).textTheme.labelLarge ??
                                        const TextStyle();
                                    final changeW = textWidthIn(rowCtx, '변경', buttonBase.merge(changeTextStyle));
                                    final density = Theme.of(rowCtx).visualDensity.baseSizeAdjustment;
                                    final densityDx = density.dx > 0 ? density.dx : 0.0;
                                    final contentW = changeW + changePadH * 2 + densityDx * 2;
                                    final minW = changeMin.width + density.dx;
                                    final buttonW = contentW > minW ? contentW : minW;
                                    final boxNeed = boxPadH * 2 + 2 + iconSize + iconGap + timeW;
                                    final fits = boxNeed + rowGap + buttonW <= rowCons.maxWidth;
                                    if (fits) {
                                      return Row(
                                        children: [
                                          Expanded(child: timeBox),
                                          SizedBox(width: rowGap),
                                          changeButton,
                                        ],
                                      );
                                    }
                                    return Column(
                                      mainAxisSize: MainAxisSize.min,
                                      crossAxisAlignment: CrossAxisAlignment.stretch,
                                      children: [
                                        timeBox,
                                        SizedBox(height: rowGap),
                                        Align(
                                          alignment: AlignmentDirectional.centerEnd,
                                          child: changeButton,
                                        ),
                                      ],
                                    );
                                  }),
                                ],
                              ),
                            );
                          }),
                        ],
                      ),
                    ),
                  ),

                  // ── 푸터 ──
                  Padding(
                    padding: ResponsiveHelper.cardPadding(ctx),
                    child: Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(dialogContext),
                            style: OutlinedButton.styleFrom(
                              // [DU303] 취소 누름 최소 64×52(같은 줄 주 행동 높이)
                              minimumSize: const Size(64, 52),
                              side: BorderSide(color: AppColors.grey300),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
                              padding: EdgeInsets.symmetric(
                                  vertical: ResponsiveHelper.spacing(ctx, 14)),
                            ),
                            child: Text('취소',
                                style: ResponsiveHelper.bodyStyle(ctx,
                                    color: AppColors.grey700)
                                    .copyWith(fontWeight: FontWeight.w600)),
                          ),
                        ),
                        SizedBox(width: ResponsiveHelper.spacing(ctx, 12)),
                        Expanded(
                          flex: 2,
                          child: ElevatedButton(
                            onPressed: () => Navigator.pop(
                                dialogContext, Map<String, String>.from(selectedTimes)),
                            // [DU303] 최종 처리는 일반 진행 — brand 면·흰 글(자식 확정과 같음), 주 행동 최소 64×52
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.brand,
                              foregroundColor: Colors.white,
                              minimumSize: const Size(64, 52),
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
                              padding: EdgeInsets.symmetric(
                                  vertical: ResponsiveHelper.spacing(ctx, 14)),
                            ),
                            // [DU308] 주 행동 이름도 낱말 사이에서만 줄바꿈(`처 / 리` 방지, 의미 이름 원문).
                            child: Text(TextLayout.keepWords('$actionLabel 처리 ($totalCount명)'),
                                semanticsLabel: '$actionLabel 처리 ($totalCount명)',
                                textAlign: TextAlign.center,
                                style: ResponsiveHelper.bodyStyle(ctx,
                                    color: Colors.white)
                                    .copyWith(fontWeight: FontWeight.bold)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }


  // ═══════════════════════════════════════════════════════════
  // 출퇴근 처리 로직
  // ═══════════════════════════════════════════════════════════

  /// 근무 시간 계산 (HH:mm(:ss) → 시간 단위 double)
  double _calcWorkHoursCompat(String checkIn, String checkOut) =>
      AttendanceStatusHelper.workMinutes(checkIn, checkOut) / 60.0;

  /// workDate + "HH:mm" → DateTime (로컬 시간, 반올림 차이 계산 전용)
  DateTime _hmToDateTime(DateTime workDate, String hhmm) {
    final parts = hhmm.split(':');
    return DateTime(workDate.year, workDate.month, workDate.day,
        int.parse(parts[0]), int.parse(parts[1]));
  }

  /// workDate + checkIn DateTime + checkOut "HH:mm" → DateTime (야간 자동 처리, 반올림 전용)
  DateTime _hmToDateTimeCheckout(
      DateTime workDate, DateTime checkInDt, String checkOutHHmm) {
    var dt = _hmToDateTime(workDate, checkOutHHmm);
    if (!dt.isAfter(checkInDt)) dt = dt.add(const Duration(days: 1));
    return dt;
  }

  /// HH:mm → KST 기준 UTC epoch (CF 전송용)
  /// 기기 시간대(UTC 시뮬레이터 등)와 무관하게 항상 KST 기준으로 epoch 계산
  int _hmToKstEpochMs(DateTime workDate, String hhmm) {
    final parts = hhmm.split(':');
    return DateTime.utc(workDate.year, workDate.month, workDate.day,
            int.parse(parts[0]), int.parse(parts[1]))
        .subtract(const Duration(hours: 9))
        .millisecondsSinceEpoch;
  }

  /// 퇴근 시간 → KST 기준 UTC epoch (CF 전송용, 야간교대 자동처리)
  int _hmCheckoutToKstEpochMs(
      DateTime workDate, DateTime checkInDt, String checkOutHHmm) {
    final checkoutLocal = _hmToDateTime(workDate, checkOutHHmm);
    final isNextDay = !checkoutLocal.isAfter(checkInDt);
    var ms = _hmToKstEpochMs(workDate, checkOutHHmm);
    if (isNextDay) ms += const Duration(days: 1).inMilliseconds;
    return ms;
  }

  /// [R7-PAYROLL-POLICY.4] 일괄 대상자들의 적용 기준이 서로 다른가.
  ///
  ///   지원 시점 기준이 지원서에 고정되므로, 사업장이 그 사이 기준을 바꿨다면
  ///   같은 날 같은 사업장 안에서도 근무마다 기준이 다를 수 있다.
  ///   읽기를 추가하지 않는다 — 이미 들고 있는 지원서와 사업장 설정만 쓴다.
  bool _batchTargetsHaveMixedPolicy(List<ApplicationModel> targets) {
    if (targets.length < 2) return false;
    final first = targets.first.effectiveAttendanceRules(_attendanceRules);
    if (first == null) return false;
    return targets.skip(1).any((app) {
      final r = app.effectiveAttendanceRules(_attendanceRules);
      return r == null || !r.sameRulesAs(first);
    });
  }

  /// 지금 이 근무를 '미출근'으로 확정할 수 있는가 — 서버와 같은 경계.
  ///
  /// [R7-NOSHOW-ADMIN-ELIGIBILITY] 서버 `srvNoShowJudgeableFromMs` 와 같은 식:
  ///   예정 시작 + 지각 유예. 유예 안에 도착하면 지각조차 아니므로 그 시간
  ///   안에서는 "오지 않았다"가 아직 성립하지 않는다. 근로자의 직전 취소
  ///   정책(시작 5분 **전**)과는 다른 사건이라 그 값을 빌려 쓰지 않는다.
  ///   규칙이 없으면 서버가 메우는 기본값(5분)과 같은 값을 쓴다.
  bool _noShowJudgeable(ApplicationModel app) {
    final rules = app.effectiveAttendanceRules(_attendanceRules);
    final startTime = WorkDetailHelper.effectiveStart(app, _workDetailTimeMap);
    final judgeableFrom = contractStartAt(_kstDay, startTime)
        .add(Duration(minutes: rules?.lateGrace ?? 5));
    return !DateTime.now().isBefore(judgeableFrom);
  }

  /// 출근 반올림 — 정책 미설정 시 입력값 그대로 반환
  ///
  /// [R7-PAYROLL-POLICY.4] 기준은 **이 근무의 약속**에서 온다.
  ///   사업장 현재 설정으로 미리보기를 만들면, 확정 뒤 설정이 바뀐 근무에서
  ///   화면이 말하는 처리 시각과 서버가 실제로 적용하는 시각이 달라진다
  ///   (서버는 `srvEffectiveAttendanceRules` — snapshot 우선).
  String _roundedCheckIn(ApplicationModel app, String rawTime) {
    final rules = app.effectiveAttendanceRules(_attendanceRules);
    if (rules == null) return rawTime;
    final startTime = WorkDetailHelper.effectiveStart(app, _workDetailTimeMap);
    final contractStart = contractStartAt(_kstDay, startTime);
    final punchAt = _hmToDateTime(_kstDay, rawTime);
    final offsetMin = punchAt.difference(contractStart).inMinutes;
    return processCheckin(
      offsetMinutes: offsetMin,
      referenceAt: contractStart,
      rules: rules,
    ).rounded;
  }

  /// 퇴근 반올림 — 정책 미설정 시 입력값 그대로 반환
  ///
  /// [R7-PAYROLL-POLICY.4] 출근과 같은 출처를 쓴다 — 한 근무에 두 기준이
  ///   생기면 안 된다.
  String _roundedCheckOut(ApplicationModel app, DateTime checkInDt, String rawCheckOutTime) {
    final rules = app.effectiveAttendanceRules(_attendanceRules);
    if (rules == null) return rawCheckOutTime;
    final startTime = WorkDetailHelper.effectiveStart(app, _workDetailTimeMap);
    final endTimeStr = app.endTime.isNotEmpty ? app.endTime : rawCheckOutTime;
    final contractEnd = contractEndAt(_kstDay, startTime, endTimeStr);
    final punchAt = _hmToDateTimeCheckout(_kstDay, checkInDt, rawCheckOutTime);
    final offsetMin = punchAt.difference(contractEnd).inMinutes;
    return processCheckout(
      offsetMinutes: offsetMin,
      referenceAt: contractEnd,
      rules: rules,
    ).rounded;
  }

  /// [ROUNDING-PREVIEW.27] 확인 창에 보여 줄 근로자별 결과 — 실제 처리(`_process*`)와 **같은 함수**로 만든다.
  /// 파트별 창 머리말과 같은 시간대(지원서의 근무 시간) — 비어 있으면 업무 정의의 시간.
  String _previewShift(ApplicationModel app) {
    final s = app.startTime.isNotEmpty ? app.startTime : WorkDetailHelper.effectiveStart(app, _workDetailTimeMap);
    final e = app.endTime.isNotEmpty ? app.endTime : WorkDetailHelper.effectiveEnd(app, _workDetailTimeMap);
    return '$s~$e';
  }

  String _previewName(ApplicationModel app) {
    final u = _userMap[app.uid];
    final name = u?.name ?? '근무자';
    final p = u?.personLabel;
    return p == null ? name : '$name ($p)';
  }

  /// 출근 처리 대상(미출근)의 [time] → 기준 적용 결과.
  List<RoundingPreviewRow> _checkInPreviews(Iterable<ApplicationModel> apps, String time) => [
        for (final app in apps)
          if (_getAttendanceStatus(app)['status'] == 'pending')
            (name: _previewName(app), shift: _previewShift(app), raw: time, applied: _roundedCheckIn(app, time)),
      ];

  /// 퇴근 처리 대상의 [time] → 기준 적용 결과. 처리에서 건너뛰는 건(급여 확정·출근 기록 없음)은 빼고,
  ///   출근 시각도 처리와 같은 식(`checkInAt ?? checkIn`)으로 잡는다.
  List<RoundingPreviewRow> _checkOutPreviews(Iterable<ApplicationModel> apps, String time) => [
        for (final app in apps)
          if (_attendanceMap[app.id] case final att?
              when att.checkIn != null &&
                  att.wageStatus != AttendanceModel.wageConfirmed &&
                  att.wageStatus != AttendanceModel.wageTransferred)
            (
              name: _previewName(app),
              shift: _previewShift(app),
              raw: time,
              applied: _roundedCheckOut(app, att.checkInAt ?? _hmToDateTime(_kstDay, att.checkIn!), time),
            ),
      ];

  /// 일괄 시간 조정의 기준 적용 결과 — `_processBatchAdjustTime` 과 같은 식(출근 먼저, 그 결과로 퇴근).
  List<RoundingPreviewRow> _adjustPreviews(
      List<ApplicationModel> targets, String? newIn, String? newOut) {
    String span(String? i, String? o) => [
          if (i != null) '출근 $i',
          if (o != null) '퇴근 $o',
        ].join(' · ');
    return [
      for (final app in targets)
        if (_attendanceMap[app.id] case final att?
            when att.wageStatus != AttendanceModel.wageConfirmed &&
                att.wageStatus != AttendanceModel.wageTransferred)
          () {
            final rIn = newIn != null ? _roundedCheckIn(app, newIn) : null;
            final effIn = rIn ?? att.checkIn ?? WorkDetailHelper.effectiveStart(app, _workDetailTimeMap);
            final inDt = rIn != null
                ? _hmToDateTime(_kstDay, rIn)
                : att.checkInAt ?? _hmToDateTime(_kstDay, effIn);
            final rOut = newOut != null ? _roundedCheckOut(app, inDt, newOut) : null;
            return (name: _previewName(app), shift: _previewShift(app), raw: span(newIn, newOut), applied: span(rIn, rOut));
          }(),
    ];
  }

  /// 근태 기준 적용 여부 선택 — 적용 시 true, 그대로 시 false, 취소 시 null.
  ///
  ///   [ROUNDING-PREVIEW.27] 예전 창은 "일부 근로자에게 다르게 적용될 수 있습니다" 만 말해서,
  ///   적용을 눌러 처리가 끝난 뒤에야 몇 시로 기록됐는지 알 수 있었다. 이제 근로자별로
  ///   `입력 → 적용 시` 를 먼저 보여 주고, 결과가 하나면 버튼에 그 시각을 적는다.
  ///   기준은 이 근무에 약속된 근태 기준이다(설정 화면 '근태 및 급여 처리 기준') — '사업장 정책' 이라
  ///   부르지 않는다(확정 뒤 설정이 바뀐 사업장에서 틀린 말이 된다).
  Future<bool?> _showRoundingPreviewDialog({
    required bool isCheckIn,
    required List<RoundingPreviewRow> rows,
  }) {
    final label = isCheckIn ? '출근' : '퇴근';
    final changed = rows.where((r) => r.applied != r.raw).toList();
    final unchanged = rows.length - changed.length;
    final raws = rows.map((r) => r.raw).toSet();
    final applieds = rows.map((r) => r.applied).toSet();
    const maxRows = 5;
    final keepLabel = raws.length == 1 ? '${raws.first} 그대로' : '입력한 시각 그대로';
    final applyLabel = applieds.length == 1 ? '${applieds.first}으로 기록' : '기준 적용';
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(Icons.auto_fix_high, color: AppColors.brand, size: 20),
            SizedBox(width: 8),
            Flexible(
              child: Text('근태 기준 적용',
                  style: ResponsiveHelper.subtitleStyle(ctx).copyWith(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('이 근무의 근태 기준을 적용하면 $label 시각이 이렇게 기록돼요.',
                style: ResponsiveHelper.smallStyle(ctx, color: AppColors.grey700)),
            SizedBox(height: ResponsiveHelper.spacing(ctx, 10)),
            Container(
              padding: EdgeInsets.all(ResponsiveHelper.spacing(ctx, 10)),
              decoration: BoxDecoration(
                color: AppColors.brandSurface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.brand.withValues(alpha: 0.2)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final r in changed.take(maxRows))
                    Padding(
                      padding: EdgeInsets.symmetric(vertical: ResponsiveHelper.spacing(ctx, 3)),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(r.name,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: ResponsiveHelper.smallStyle(ctx, color: AppColors.textPrimary)),
                                Text(r.shift,
                                    style: ResponsiveHelper.tinyStyle(ctx, color: AppColors.grey500)),
                              ],
                            ),
                          ),
                          SizedBox(width: ResponsiveHelper.spacing(ctx, 8)),
                          Text(r.raw,
                              style: ResponsiveHelper.smallStyle(ctx, color: AppColors.grey500)),
                          Icon(Icons.arrow_right_alt,
                              size: ResponsiveHelper.iconSize(ctx, 16), color: AppColors.grey500),
                          Text(r.applied,
                              style: ResponsiveHelper.smallStyle(ctx, color: AppColors.brandDark)
                                  .copyWith(fontWeight: FontWeight.w700)),
                        ],
                      ),
                    ),
                  if (changed.length > maxRows)
                    Text('외 ${changed.length - maxRows}명도 바뀌어요',
                        style: ResponsiveHelper.tinyStyle(ctx, color: AppColors.brandDark)),
                  if (unchanged > 0)
                    Padding(
                      padding: EdgeInsets.only(top: ResponsiveHelper.spacing(ctx, 4)),
                      child: Text('나머지 $unchanged명은 입력한 시각 그대로예요',
                          style: ResponsiveHelper.tinyStyle(ctx, color: AppColors.grey600)),
                    ),
                ],
              ),
            ),
          ],
          ),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        actions: [
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  style: OutlinedButton.styleFrom(
                    padding: EdgeInsets.symmetric(vertical: ResponsiveHelper.spacing(ctx, 12)),
                    side: BorderSide(color: AppColors.grey300),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: Text(keepLabel,
                      textAlign: TextAlign.center,
                      style: ResponsiveHelper.bodyStyle(ctx, color: AppColors.grey600)),
                ),
              ),
              SizedBox(width: ResponsiveHelper.spacing(ctx, 10)),
              Expanded(
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  style: ElevatedButton.styleFrom(
                    // [DU618b · 장부092 · 판정113 :77 · 114 :39 N1 둘째 창] 주 행동 채움 info → brand(흰 글 대비) — 두 글 갈래 같은 단추. 선택 시각 · 반올림 · 반환값 · 콜백 그대로.
                    backgroundColor: AppColors.brand,
                    foregroundColor: Colors.white,
                    padding: EdgeInsets.symmetric(vertical: ResponsiveHelper.spacing(ctx, 12)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: Text(
                    applyLabel,
                    textAlign: TextAlign.center,
                    style: ResponsiveHelper.bodyStyle(ctx, color: Colors.white).copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 출근/퇴근 시간으로 DB status 결정 — effectiveStart/End 우선 적용
  String _deriveStatus(ApplicationModel app, String checkIn, String? checkOut) =>
      AttendanceStatusHelper.deriveStatus(
        app, checkIn, checkOut,
        effStart: WorkDetailHelper.effectiveStart(app, _workDetailTimeMap),
        effEnd:   WorkDetailHelper.effectiveEnd(app, _workDetailTimeMap),
      );

  /// 일괄 출근 처리 — CF callableBatchCheckIn 경유
  Future<void> _processBatchCheckIn(String time, {bool applyRounding = false}) async {
    if (_isLoading) return;
    setState(() => _isLoading = true);
    try {
      final entries = <Map<String, dynamic>>[];
      final lateApps = <ApplicationModel>[];

      for (var appId in _selectedIds) {
        final idx = _confirmedWorkers.indexWhere((a) => a.id == appId);
        if (idx == -1) continue;
        final app = _confirmedWorkers[idx];
        final status = _getAttendanceStatus(app);
        if (status['status'] != 'pending') continue;

        // 반올림 정책 적용 여부에 따라 유효 시간 결정
        final effectiveTime = applyRounding ? _roundedCheckIn(app, time) : time;
        final existing = _attendanceMap[app.id];
        final checkInMs = _hmToKstEpochMs(_kstDay, effectiveTime);
        final entry = <String, dynamic>{
          'applicationId': app.id,
          'workDateMs': _kstDayStartMs,
          'userId': app.uid,
          'businessId': app.businessId,
          'businessName': app.businessName,
          'workType': app.selectedWorkType,
          'status': _deriveStatus(app, effectiveTime, null),
          'checkInMs': checkInMs,
        };
        if (existing != null) entry['attendanceId'] = existing.id;
        entries.add(entry);

        final expectedStartTime = WorkDetailHelper.effectiveStart(app, _workDetailTimeMap);
        if (AttendanceStatusHelper.isLate(
          effectiveTime, expectedStartTime,
          isNextDay: AttendanceStatusHelper.isNextDayCheckIn(effectiveTime, expectedStartTime),
        )) {
          lateApps.add(app);
        }
      }

      if (entries.isEmpty) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      final result = await FirebaseFunctions.instanceFor(region: 'asia-northeast3')
          .httpsCallable('callableBatchCheckIn',
              options: HttpsCallableOptions(timeout: const Duration(seconds: 60)))
          .call({'businessId': _selectedBusinessId, 'entries': entries});

      final processed = result.data['processed'] as int? ?? 0;
      // [R5-R0.1 §14] 처리하지 못한 건을 성공 옆에 묻지 않는다.
      final failed = result.data['failed'] as int? ?? 0;

      // 지각 신뢰도 연동 — CF 성공 후, 단건 실패는 무시
      final lateCallable = FirebaseFunctions.instanceFor(region: 'asia-northeast3')
          .httpsCallable('callableReportLate',
              options: HttpsCallableOptions(timeout: const Duration(seconds: 10)));
      await Future.wait(lateApps.map((app) async {
        final attendanceId = _attendanceMap[app.id]?.id;
        if (attendanceId == null) {
          debugPrint('⚠️ callableReportLate 건너뜀: attendanceId 없음 (appId=${app.id})');
          return;
        }
        try {
          await lateCallable.call({
            'userId': app.uid,
            'businessId': app.businessId,
            'mode': 'late',
            'attendanceId': attendanceId,
          });
        } catch (cfErr) {
          debugPrint('⚠️ callableReportLate 실패 (무시): $cfErr');
        }
      }));

      if (!mounted) return;
      // [R5-R0.1 §14] 처리하지 못한 건이 있으면 그 사실을 함께 말한다.
      if (failed > 0) {
        ToastHelper.showWarning(
            '$processed명 출근 처리 · $failed명 처리하지 못했습니다');
      } else if (processed > 0) {
        ToastHelper.showSuccess('$processed명 출근 처리 완료');
      }
      if (processed > 0) {
        _hasChanges = true;
      }
      if (entries.length - processed > 0) {
        ToastHelper.showWarning('${entries.length - processed}명 처리 실패');
      }

      // [R8-P1C] 서버가 바꾼 것은 근태 문서뿐이다 (일괄출근).
      await _refreshAttendanceOnly();
    } catch (e) {
      debugPrint('❌ 일괄 출근 처리 실패: $e');
      if (!mounted) return;
      // [impl_58 · server_296 A9] 같은 근태에 내용이 다른 두 항목 → 서버가 요청 전체를 거절(처리 0). 이유를 말하고 최신 근태를 다시 읽는다.
      if (batchCheckInRejectMessageOf(e) case final conflictMsg?) {
        ToastHelper.showError(conflictMsg);
        await _reloadAttendanceAfterReject();
        return;
      }
      ToastHelper.showError('일괄 출근 처리 실패');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  static String _checkoutFailureNote(Object? data) =>
      AttendanceStatusDialog.checkoutFailureNote(data);

  /// 일괄 퇴근 처리 — CF callableBatchCheckOut 경유
  Future<void> _processBatchCheckOut(String time, List<String> targetIds, {bool applyRounding = false}) async {
    if (_isLoading) return;
    setState(() => _isLoading = true);
    try {
      final entries = <Map<String, dynamic>>[];
      int skipCount = 0;
      int noCheckInCount = 0;

      for (var appId in targetIds) {
        final idx = _confirmedWorkers.indexWhere((a) => a.id == appId);
        if (idx == -1) continue;
        final app = _confirmedWorkers[idx];
        final attendance = _attendanceMap[app.id];
        if (attendance == null) continue;

        if (attendance.wageStatus == AttendanceModel.wageConfirmed ||
            attendance.wageStatus == AttendanceModel.wageTransferred) {
          skipCount++;
          continue;
        }
        // [CONTRACT-DISPATCH-B2-APP] 출근 기록이 없으면 퇴근을 만들지 않는다 — 예정 시작으로 메우면
        //   일하지 않은 사람에게 근무시간이 생긴다(서버도 notCheckedIn 으로 거절한다).
        if (attendance.checkIn == null) {
          noCheckInCount++;
          continue;
        }

        final checkIn = attendance.checkIn!;
        final checkInDtForOut = attendance.checkInAt ?? _hmToDateTime(_kstDay, checkIn);
        final effectiveTime = applyRounding ? _roundedCheckOut(app, checkInDtForOut, time) : time;
        final minutes = AttendanceStatusHelper.workMinutes(checkIn, effectiveTime);
        if (minutes <= 0) {
          skipCount++;
          continue;
        }
        if (minutes > 16 * 60) {
          skipCount++;
          continue;
        }

        entries.add({
          'attendanceId': attendance.id,
          'checkOutMs': _hmCheckoutToKstEpochMs(_kstDay, checkInDtForOut, effectiveTime),
          'workHours': _calcWorkHoursCompat(checkIn, effectiveTime),
          'status': _deriveStatus(app, checkIn, effectiveTime),
          'resetWageDetail': attendance.wageStatus == AttendanceModel.wageCalculated,
        });
      }

      if (entries.isEmpty) {
        if (!mounted) return;
        if (noCheckInCount > 0) ToastHelper.showWarning('출근 기록이 없는 근무 $noCheckInCount건은 퇴근을 처리할 수 없어요');
        if (skipCount > 0) ToastHelper.showWarning('$skipCount명은 처리 불가 (시간 역전 또는 16시간 초과)');
        return;
      }

      final result = await FirebaseFunctions.instanceFor(region: 'asia-northeast3')
          .httpsCallable('callableBatchCheckOut',
              options: HttpsCallableOptions(timeout: const Duration(seconds: 60)))
          .call({'businessId': _selectedBusinessId, 'entries': entries});

      if (noCheckInCount > 0 && mounted) {
        ToastHelper.showWarning('출근 기록이 없는 근무 $noCheckInCount건은 퇴근을 처리하지 않았어요');
      }
      final processed = result.data['processed'] as int? ?? 0;
      // [R5-R0.2 §8·§9] 서버가 분류한 실패 건수를 그대로 쓴다.
      //   클라이언트가 미리 센 skipCount는 "급여 확정/이체" 하나만 알고,
      //   나머지 사유(근태 없음·다른 사업장·미래 날짜 등)는 몰랐다.
      final failed = result.data['failed'] as int? ?? 0;

      if (!mounted) return;
      if (failed > 0) {
        // 전부 실패한 경우도 성공처럼 말하지 않는다.
        ToastHelper.showWarning((processed > 0
                ? '$processed명 퇴근 처리 · $failed명 처리하지 못했습니다'
                : '$failed명 모두 처리하지 못했습니다') +
            _checkoutFailureNote(result.data));
      } else if (processed > 0) {
        ToastHelper.showSuccess('$processed명 퇴근 처리 완료');
      }
      if (processed > 0) _hasChanges = true;

      // [R8-P1C] 서버가 바꾼 것은 근태 문서뿐이다 (일괄퇴근).
      await _refreshAttendanceOnly();
    } catch (e) {
      debugPrint('❌ 일괄 퇴근 처리 실패: $e');
      if (!mounted) return;
      ToastHelper.showError('일괄 퇴근 처리 실패');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// 파트별 일괄 출근 처리 — CF callableBatchCheckIn 경유
  Future<void> _processBatchCheckInByGroup(Map<String, String> groupTimes, {bool applyRounding = false}) async {
    if (_isLoading) return;
    setState(() => _isLoading = true);
    try {
      final entries = <Map<String, dynamic>>[];
      final lateApps = <ApplicationModel>[];

      for (final appId in _selectedIds) {
        final idx = _confirmedWorkers.indexWhere((a) => a.id == appId);
        if (idx == -1) continue;
        final app = _confirmedWorkers[idx];
        final groupKey = '${app.selectedWorkType}_${app.startTime}_${app.endTime}';
        final time = groupTimes[groupKey];
        if (time == null) continue;

        final status = _getAttendanceStatus(app);
        if (status['status'] != 'pending') continue;

        final effectiveTime = applyRounding ? _roundedCheckIn(app, time) : time;
        final existing = _attendanceMap[app.id];
        final entry = <String, dynamic>{
          'applicationId': app.id,
          'workDateMs': _kstDayStartMs,
          'userId': app.uid,
          'businessId': app.businessId,
          'businessName': app.businessName,
          'workType': app.selectedWorkType,
          'status': _deriveStatus(app, effectiveTime, null),
          'checkInMs': _hmToKstEpochMs(_kstDay, effectiveTime),
        };
        if (existing != null) entry['attendanceId'] = existing.id;
        entries.add(entry);

        final expectedStartTime = WorkDetailHelper.effectiveStart(app, _workDetailTimeMap);
        if (AttendanceStatusHelper.isLate(
          effectiveTime, expectedStartTime,
          isNextDay: AttendanceStatusHelper.isNextDayCheckIn(effectiveTime, expectedStartTime),
        )) {
          lateApps.add(app);
        }
      }

      if (entries.isNotEmpty) {
        final result = await FirebaseFunctions.instanceFor(region: 'asia-northeast3')
            .httpsCallable('callableBatchCheckIn',
                options: HttpsCallableOptions(timeout: const Duration(seconds: 60)))
            .call({'businessId': _selectedBusinessId, 'entries': entries});

        final processed = result.data['processed'] as int? ?? 0;
        // [R5-R0.1 §14] 처리하지 못한 건을 성공 옆에 묻지 않는다.
        final failed = result.data['failed'] as int? ?? 0;

        final lateCallableGroup = FirebaseFunctions.instanceFor(region: 'asia-northeast3')
            .httpsCallable('callableReportLate',
                options: HttpsCallableOptions(timeout: const Duration(seconds: 10)));
        await Future.wait(lateApps.map((app) async {
          final attendanceId = _attendanceMap[app.id]?.id;
          if (attendanceId == null) {
            debugPrint('⚠️ callableReportLate 건너뜀: attendanceId 없음 (appId=${app.id})');
            return;
          }
          try {
            await lateCallableGroup.call({
              'userId': app.uid,
              'businessId': app.businessId,
              'mode': 'late',
              'attendanceId': attendanceId,
            });
          } catch (cfErr) {
            debugPrint('⚠️ callableReportLate 실패 (무시): $cfErr');
          }
        }));

        if (!mounted) return;
        if (processed > 0) {
          if (failed > 0) {
            ToastHelper.showWarning('$processed명 출근 처리 · $failed명 처리하지 못했습니다');
          } else {
            ToastHelper.showSuccess('$processed명 출근 처리 완료');
          }
          _hasChanges = true;
        }
        if (entries.length - processed > 0) ToastHelper.showWarning('${entries.length - processed}명 처리 실패');
      }

      // [R8-P1C] 서버가 바꾼 것은 근태 문서뿐이다 (파트별출근).
      await _refreshAttendanceOnly();
    } catch (e) {
      debugPrint('❌ 파트별 일괄 출근 처리 실패: $e');
      if (!mounted) return;
      // [impl_58 · server_296 A9] 위 일괄 출근과 같은 거절 처리.
      if (batchCheckInRejectMessageOf(e) case final conflictMsg?) {
        ToastHelper.showError(conflictMsg);
        await _reloadAttendanceAfterReject();
        return;
      }
      ToastHelper.showError('일괄 출근 처리 실패');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// 파트별 일괄 퇴근 처리 — CF callableBatchCheckOut 경유
  Future<void> _processBatchCheckOutByGroup(
      Map<String, String> groupTimes, List<String> targetIds, {bool applyRounding = false}) async {
    if (_isLoading) return;
    setState(() => _isLoading = true);
    try {
      final entries = <Map<String, dynamic>>[];
      // [W-3] 실패 이유를 이름과 함께 수집 — 시간 역전 vs 16시간 초과 구별
      final List<String> failMessages = [];

      for (final appId in targetIds) {
        final idx = _confirmedWorkers.indexWhere((a) => a.id == appId);
        if (idx == -1) continue;
        final app = _confirmedWorkers[idx];
        final groupKey = '${app.selectedWorkType}_${app.startTime}_${app.endTime}';
        final time = groupTimes[groupKey];
        if (time == null) continue;

        final attendance = _attendanceMap[app.id];
        if (attendance == null) continue;

        final workerName = _userMap[app.uid]?.name ?? '근무자';
        if (attendance.wageStatus == AttendanceModel.wageConfirmed ||
            attendance.wageStatus == AttendanceModel.wageTransferred) {
          failMessages.add('$workerName: 급여 확정/이체 완료 건은 수정 불가');
          continue;
        }
        // [CONTRACT-DISPATCH-B2-APP] 출근 기록 없음 — 예정 시작으로 메우지 않는다.
        if (attendance.checkIn == null) {
          failMessages.add('$workerName: 출근 기록이 없어 퇴근을 처리할 수 없어요');
          continue;
        }

        final checkIn = attendance.checkIn!;
        final checkInDtForOut = attendance.checkInAt ?? _hmToDateTime(_kstDay, checkIn);
        final effectiveTime = applyRounding ? _roundedCheckOut(app, checkInDtForOut, time) : time;
        final minutes = AttendanceStatusHelper.workMinutes(checkIn, effectiveTime);
        if (minutes <= 0) {
          failMessages.add('$workerName: 퇴근 시간이 출근 시간보다 앞서 있습니다');
          continue;
        }
        if (minutes > 16 * 60) {
          failMessages.add('$workerName: 16시간 초과 (${minutes ~/ 60}시간 ${minutes % 60}분)');
          continue;
        }

        entries.add({
          'attendanceId': attendance.id,
          'checkOutMs': _hmCheckoutToKstEpochMs(_kstDay, checkInDtForOut, effectiveTime),
          'workHours': _calcWorkHoursCompat(checkIn, effectiveTime),
          'status': _deriveStatus(app, checkIn, effectiveTime),
          'resetWageDetail': attendance.wageStatus == AttendanceModel.wageCalculated,
        });
      }

      if (entries.isNotEmpty) {
        final result = await FirebaseFunctions.instanceFor(region: 'asia-northeast3')
            .httpsCallable('callableBatchCheckOut',
                options: HttpsCallableOptions(timeout: const Duration(seconds: 60)))
            .call({'businessId': _selectedBusinessId, 'entries': entries});

        final processed = result.data['processed'] as int? ?? 0;
        // [R5-R0.2 §8·§9] 그룹 경로도 같은 분기를 쓴다.
        final failed = result.data['failed'] as int? ?? 0;

        if (!mounted) return;
        if (failed > 0) {
          ToastHelper.showWarning((processed > 0
                  ? '$processed명 퇴근 처리 · $failed명 처리하지 못했습니다'
                  : '$failed명 모두 처리하지 못했습니다') +
              _checkoutFailureNote(result.data));
        } else if (processed > 0) {
          ToastHelper.showSuccess('$processed명 퇴근 처리 완료');
        }
        if (processed > 0) _hasChanges = true;
      }

      if (!mounted) return;
      if (failMessages.isNotEmpty) {
        ToastHelper.showWarning('${failMessages.length}명 처리 실패\n${failMessages.join('\n')}');
      }

      // [R8-P1C] 서버가 바꾼 것은 근태 문서뿐이다 (파트별퇴근).
      await _refreshAttendanceOnly();
    } catch (e) {
      debugPrint('❌ 파트별 일괄 퇴근 처리 실패: $e');
      if (mounted) ToastHelper.showError('일괄 퇴근 처리 실패');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }






  // ═══════════════════════════════════════════════════════════
  // 노쇼 처리
  // ═══════════════════════════════════════════════════════════





  /// 일괄 마감 취소 (선택된 최종확정 근무자 전체)
  // [설계] WriteBatch 500 ops 제한 검토:
  // 1인당 attendance + users 2 ops → 249명까지 단일 batch로 처리 가능.
  // 마감 취소는 선택된 wageConfirmed 근무자 대상으로 관리자가 수동 선택 후 실행하므로
  // 한 번에 수백 명을 선택하는 경우는 현실적으로 없다.
  // [I9 · impl_16] 확인·선택 창(첫 await) **전에** 같은 화면의 같은 잠금 묶음을 잠근다 — 창이 뜨기 전 연타의
  //   두 번째 진입이 창·mutation 을 한 번 더 내지 않게(본문 `_batchCancelFinalLocked` 은 그대로 · 화면 플래그는 진행 표시로 유지).
  Future<void> _batchCancelFinal() =>
      ActionGuard.runVoid(ActionGuard.ownerKey('attendanceStatus._isLoading', this), () => _batchCancelFinalLocked());

  Future<void> _batchCancelFinalLocked() async {
    // PERM-02: 마감취소 권한 확인 — 급여 관련이므로 canManageWage
    if (context.read<UserProvider>().checkCurrentBusiness((p) => p.canManageWage) != PermissionCheck.allowed) {
      ToastHelper.showWarning('마감취소 권한이 없습니다.');
      return;
    }
    if (_isLoading) return;
    final targets = _selectedFinalConfirmedApps;
    if (targets.isEmpty) return;

    final names = targets
        .map((a) => _userMap[a.uid]?.name ?? '알수없음')
        .join(', ');
    final confirmed = await DialogHelper.showConfirm(
      context,
      title: '마감취소 (${targets.length}명)',
      message: '$names\n\n위 근무자들의 마감을 취소하시겠습니까?\n급여확정 상태로 되돌아가며, 지원자에게 급여가 숨겨집니다.',
      confirmText: '마감취소', confirmColor: AppColors.errorDark,
    );
    if (!confirmed || !mounted) return;
    setState(() => _isLoading = true);

    // CF callableCancelFinalConfirmation 경유 — 서버에서 wageTransferred 건 재차 방어
    final attendanceIds = targets
        .map((app) => _attendanceMap[app.id]?.id)
        .whereType<String>()
        .toList();

    try {
      final result = await FirebaseFunctions.instanceFor(region: 'asia-northeast3')
          .httpsCallable('callableCancelFinalConfirmation')
          .call({'businessId': _selectedBusinessId, 'attendanceIds': attendanceIds});
      if (!mounted) return;
      final processed = result.data['processed'] as int? ?? 0;

      // [R8-P3B.2] 마감취소 알림은 callableCancelFinalConfirmation 가 보낸다.
      //   취소 CF 가 끝난 뒤 인원수만큼 알림 callable 을 다시 불렀다 —
      //   화면이 그걸 await 했고, 같은 이벤트의 문구를 급여 화면도 따로
      //   만들고 있었다. 이제 CF 한 곳에서 처리한다.
      //   (TrustScore 는 onAttendanceWageStatusChanged 트리거가 그대로 처리)

      if (!mounted) return;
      _hasChanges = true;
      ToastHelper.showSuccess('$processed명 마감취소 완료');
      // [R8-P1C] 서버가 바꾼 것은 근태 문서뿐이다 (마감취소).
      await _refreshAttendanceOnly();
    } catch (e) {
      debugPrint('❌ 마감 취소 실패: $e');
      if (mounted) ToastHelper.showError('마감취소에 실패했습니다');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }


}

/// 컴팩트 통계 칩 데이터 클래스 (내부용)
/// [UI-3] 일괄 근태 행동의 역할 — 단계(출근·퇴근) / 보조(시간 조정) / 위험(리셋).
enum _BatchRole { step, secondary, destructive }

class _StatChip {
  final String label;
  final int count;
  final Color color;
  const _StatChip(this.label, this.count, this.color);
}
