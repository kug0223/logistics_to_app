import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../models/core/application_model.dart';
import '../../models/core/attendance_model.dart';
import '../../models/core/business_model.dart';
import '../../models/core/employment_contract_model.dart';
import '../../widgets/common/loading_button.dart';
import '../../services/firestore_service.dart';
import '../../services/analytics_service.dart';
import '../../utils/format_helper.dart';
import 'attendance_check_reads.dart';
import 'checkin_contract_gate.dart';
import '../../providers/user_provider.dart';
import '../../utils/beacon_helper.dart';
import '../../utils/location_helper.dart';
import '../../utils/toast_helper.dart';
import '../../utils/dialog_helper.dart';
import '../../utils/responsive_helper.dart';
import '../../theme/app_colors.dart';
import '../../widgets/common/loading_widget.dart';
import '../../widgets/common/app_page_actions.dart';
import '../../widgets/common/app_page_scaffold.dart';
import '../../widgets/user/pending_contract_bar.dart';
import '../../services/device_integrity_service.dart';
import '../../widgets/common/app_empty_state.dart';
import '../../widgets/dialogs/apply/confirm_cancel_dialog.dart';
import '../../widgets/common/privacy_inline_notice.dart';
import '../../screens/contract/contract_sign_screen.dart';
import '../../utils/text_layout.dart';
import 'user_tab_scope.dart';

/// 출퇴근 체크 화면
class AttendanceCheckScreen extends StatefulWidget {
  /// [BUSINESS-ARCHIVE] 운영을 종료한 사업장의 장기 근무는 종료일부터 새로 출근하지
  /// 않는다(서버 callableCheckIn 과 같은 판정 — 서버가 최종 권위다). 단기 근무는
  /// 해당 없음. 이미 출근한 날의 퇴근은 이 판정을 거치지 않는다.
  @visibleForTesting
  static bool closedForNewCheckIn(
      BusinessModel business, ApplicationModel work, DateTime kstToday) {
    if (!work.isLongTermApplication) return false;
    final closedAt = business.deactivatedAt;
    if (closedAt == null) return false;
    return !kstToday.isBefore(FormatHelper.toKstDate(closedAt));
  }

  /// [SIM-CHECKIN-EARLY] 이 근무의 본인 출근을 서버가 **받기 시작하는 시각**.
  ///
  ///   서버 callableCheckIn 과 같은 식이다 — 근무일(단기: 저장된 KST 근무일,
  ///   장기: 오늘 KST)의 예정 시작 − earlyWindow(0~120 으로 clamp).
  ///   earlyWindow 는 확정 때 고정된 정책 스냅샷에서 읽는다. 스냅샷이 없으면
  ///   서버는 사업장 설정을 보는데 이 화면은 그 값을 갖고 있지 않으므로 null —
  ///   모르는 기준으로 막지 않고 서버 판정에 맡긴다. 시작 시각을 못 읽어도 null.
  @visibleForTesting
  static DateTime? checkInOpensAt(ApplicationModel work, DateTime now) {
    final snap = work.attendancePolicySnapshot;
    if (snap == null) return null;
    final day = work.isLongTermApplication
        ? FormatHelper.toKstDate(now)
        : FormatHelper.toKstDate(work.workDate);
    final start = FormatHelper.kstWallClockInstant(day, work.startTime);
    if (start == null) return null;
    final early = snap.earlyWindow.clamp(0, 120);
    return start.subtract(Duration(minutes: early));
  }

  const AttendanceCheckScreen(
      {super.key, this.reads, this.clock, this.reconfirmResponder});

  /// [SIM-RECONFIRM-ACCESS] 리컨펌 응답의 쓰기 경계. production 은 null →
  ///   `FirestoreService.respondToReconfirm`(callableRespondToReconfirm).
  ///   응답 뒤 카드가 다시 읽힌 원장대로 바뀌는지를 렌더로 확인하기 위한 자리다.
  final Future<bool> Function(String applicationId, String response)?
      reconfirmResponder;

  /// [R7-P2-1 잔여] 목록을 만들 때의 읽기 경계. production 은 null.
  final AttendanceCheckReads? reads;

  /// [R7-P2-1 잔여] "지금"의 출처. production 은 null → `DateTime.now`.
  ///
  ///   시간대 경계를 **기기 조작 없이** 검증하기 위한 자리다. 비-KST 기기를
  ///   흉내 낼 때는 그 기기의 로컬 필드를 가진 시각을 넣는다.
  final DateTime Function()? clock;

  @override
  State<AttendanceCheckScreen> createState() => _AttendanceCheckScreenState();
}

class _AttendanceCheckScreenState extends State<AttendanceCheckScreen> {
  static final _fmt = NumberFormat('#,###'); // 카드 build마다 인스턴스 생성 방지
  final FirestoreService _firestoreService = FirestoreService();
  late final AttendanceCheckReads _reads =
      widget.reads ?? AttendanceCheckReads.of(_firestoreService);
  DateTime _now() => (widget.clock ?? DateTime.now)();

  List<ApplicationModel> _todayWorks = [];

  /// [SIM-RECONFIRM-ACCESS] **내일** 근무 중 리컨펌 응답을 기다리는 것.
  ///
  ///   서버는 리컨펌 요청을 workDate(KST 자정) 기준 창으로 보낸다 — 10/20 근무면
  ///   10/19 21:00 이다. 그런데 이 화면은 오늘·어제 근무만 실어서, 요청을 받은
  ///   그날 밤에는 응답 버튼이 어디에도 없었다(22:00 관리자 '미응답' 경고가 사실상
  ///   항상 나갔다). 응답 카드만 따로 보여 준다 — 출근 요청 영역(위치·GPS)은
  ///   이 목록에 붙이지 않는다. 내일 근무의 출근은 그날 오늘 근무로 열린다.
  List<ApplicationModel> _upcomingReconfirmWorks = [];
  final Map<String, AttendanceModel?> _attendanceMap = {};

  /// [CONTRACT-BEFORE-CHECKIN] 이번 읽기의 내 계약 목록. null = 읽지 못함(또는 아직 안 읽음)
  ///   — 그때 출근 버튼은 닫힌다. 목록을 다시 읽을 때마다 함께 새로 받는다.
  List<EmploymentContractModel>? _contracts;
  bool _isLoading = false; // 초기값 false — initState에서 _loadTodayWorks() 첫 호출 시 재진입 방어에 걸리지 않도록

  /// [R7-P2-3 P23-E] 오늘 근무를 **읽지 못했다**.
  ///
  ///   예전에는 catch 에서 로딩만 끄고 토스트를 띄웠다. `_todayWorks` 는 빈
  ///   채로 남으니 화면이 `오늘 확정된 근무가 없습니다` 를 그렸고, 토스트가
  ///   사라진 뒤에는 **확정된 근무가 있는 사람이 없다고 믿는다** — 그날 출근을
  ///   놓치고 노쇼가 된다. 일정 탭은 이미 같은 구분을 한다(`_loadError`).
  Object? _loadError;
  bool _isProcessing = false;
  bool _isReconfirming = false;

  /// [SIM-CHECKIN-EARLY] 아직 열리지 않은 출근 버튼을 그 시각에 다시 그린다.
  Timer? _opensAtTimer;

  /// [DEVICE-MISMATCH-FIX] 화면을 연 채 근무 종료 시각이 지나면 버튼을 닫으러
  ///   그 시각에 한 번 다시 그린다.
  Timer? _shiftEndTimer;

  @override
  void dispose() {
    _opensAtTimer?.cancel();
    _shiftEndTimer?.cancel();
    super.dispose();
  }

  void _scheduleShiftEndRebuild(DateTime endsAt) {
    if (_shiftEndTimer?.isActive ?? false) return;
    final wait = endsAt.difference(_now());
    if (wait.isNegative) return;
    _shiftEndTimer = Timer(wait + const Duration(milliseconds: 50), () {
      _shiftEndTimer = null;
      if (mounted) setState(() {});
    });
  }

  /// 가장 먼저 열릴 시각에 한 번 다시 그린다 — 주기 polling 은 두지 않는다.
  void _scheduleOpensAtRebuild(DateTime opensAt) {
    if (_opensAtTimer?.isActive ?? false) return;
    final wait = opensAt.difference(_now());
    _opensAtTimer = Timer(
      wait.isNegative ? Duration.zero : wait + const Duration(milliseconds: 50),
      () {
        _opensAtTimer = null;
        if (mounted) setState(() {});
      },
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _loadTodayWorks();
    });
  }

  /// 오늘 확정된 근무 조회
  // finally 블록 없음 — 정상 경로(149행)와 catch(160행) 양쪽에서 _isLoading=false 처리되어 실질 고착 없음
  Future<void> _loadTodayWorks() async {
    if (!mounted) return;
    if (_isLoading) return; // [M-2] pull-to-refresh + 체크인 완료 후 자동 재조회 동시 재진입 방어
    setState(() => _isLoading = true);

    try {
      final userProvider = Provider.of<UserProvider>(context, listen: false);
      final uid = userProvider.currentUser?.uid;

      if (uid == null) {
        ToastHelper.showError('로그인이 필요합니다.');
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      final allApplications = await _reads.myApplications(uid);

      // [R7-P2-1 잔여 · VERIFY-ATTENDANCE-LOCAL-MIDNIGHT]
      //   여기는 `DateTime(today.year, today.month, today.day)` 였다 —
      //   **기기 로컬 자정**이다. 저장된 근무일은 KST 자정 instant 이고
      //   `Timestamp.toDate().toLocal()` 로 읽히므로, 비-KST 기기에서는
      //   그 필드가 KST 날짜와 하루 어긋난다. 그러면 홈이 "퇴근이 남았다"고
      //   보낸 바로 그 근무가 이 목록에서 빠져 **퇴근할 방법이 사라진다.**
      //   날짜 owner(P1-3)의 KST 기준으로 맞춘다 — 같은 날을 두 화면이
      //   같은 이름으로 부른다.
      final today = _now();
      final todayStart = FormatHelper.toKstDate(today);
      // [C-001] yesterday를 루프 밖으로 — 퇴근 완료 필터에서도 사용
      final yesterday = todayStart.subtract(const Duration(days: 1));
      final tomorrow = todayStart.add(const Duration(days: 1));
      final todayWorks = <ApplicationModel>[];
      final upcomingReconfirm = <ApplicationModel>[];

      for (final app in allApplications) {
        if (!AppStatus.confirmedStatuses.contains(app.status)) continue;

        // [SIM-RECONFIRM-ACCESS] 내일 단기 근무 + 응답 대기 리컨펌 → 응답 카드만.
        //   서버 응답 함수가 받는 조건(확정 상태·단기)과 같은 범위다.
        if (!app.isLongTermApplication &&
            app.reconfirmStatus == 'pending' &&
            FormatHelper.toKstDate(app.workDate) == tomorrow) {
          upcomingReconfirm.add(app);
          continue;
        }

        // [A-H1-FIX] isLongTermApplication 게터 사용 — applicationType·workDays·workEndDate 3조건 모두 반영
      final isReallyLongTerm = app.isLongTermApplication;

        if (!isReallyLongTerm) {
          // 어제 시작한 야간 근무(자정 이후 퇴근 대기)도 포함
          final wd = FormatHelper.toKstDate(app.workDate);
          if (wd == todayStart || wd == yesterday) {
            todayWorks.add(app);
          }
          continue;
        }

        // isWorkingOnDate: actualResignDate·leaveDates·extraWorkDates·workDays 모두 반영
        if (app.isWorkingOnDate(todayStart)) {
          todayWorks.add(app);
        }
      }

      // 각 근무의 출근 기록 병렬 조회 — 로컬 맵으로 수집 후 한번에 반영
      // (클로저 내 직접 변이 시 부분 실패 때 stale/new 데이터 혼재 방지)
      final tempMap = <String, AttendanceModel?>{};
      // [CONTRACT-BEFORE-CHECKIN] 출근 gate 근거. 실패는 목록 실패로 키우지 않고 null(=모름)로 둔다
      //   — 퇴근·리컨펌은 계약과 무관하게 계속 보여야 한다. 모름이면 출근 버튼만 닫힌다.
      final contractsFuture = todayWorks.isEmpty
          ? Future<List<EmploymentContractModel>?>.value(null)
          : _reads.myContracts(uid).then<List<EmploymentContractModel>?>(
              (v) => v,
              onError: (Object e) {
                debugPrint('❌ 출근 화면 계약 조회 실패: $e');
                return null;
              });
      await Future.wait(
        todayWorks.map((work) async {
          final attendance = await _reads.todayAttendance(
            userId: uid,
            applicationId: work.id,
          );
          tempMap[work.id] = attendance;
        }),
      );
      // [FIX] addAll은 기존 키를 삭제하지 않음 — 재로드 시 이전 근무의 stale 데이터가 남아
      // _showRoundingFeedback에서 잘못된 시간을 읽을 수 있으므로 clear() 후 교체.
      // setState 내부로 이동해 _todayWorks와 원자적으로 반영.

      // [C-001] 어제 날짜 출근 기록이 퇴근 완료인 항목은 오늘 화면에서 제외 (stale 방지)
      // work.workDate 대신 att.workDate 기준으로 어제를 판단:
      //   - 단기: att.workDate = work.workDate (실제 근무일) → 동일하게 동작
      //   - 장기: work.workDate = 계약 시작일(고정값)이라 isSameDay(work.workDate, yesterday) 항상 false
      //           → att.workDate = checkIn 시점 오늘 날짜로 기록 → 어제 기록을 정확히 식별 가능
      // [M-1 수정] tempMap 사용 — _attendanceMap은 아직 setState 전이라 이전 값(stale)을 가리킴
      //   최초 로드 시 _attendanceMap={} → att=null → 어제 완료 기록이 필터 통과 → 오늘 목록에 표시됨
      final visibleWorks = todayWorks.where((work) {
        final att = tempMap[work.id];
        if (att == null) return true;
        if (FormatHelper.toKstDate(att.workDate) == yesterday) {
          // [G-3 수정] 어제 기록은 퇴근 완료 또는 missed_checkout 상태 모두 오늘 화면에서 숨김
          // [BUG-M2 수정 2026-07-27] NO_SHOW/absent 상태도 어제 기록이면 숨김
          // — 배치 자동처리 후 어제 카드가 "출근하기" 버튼과 함께 오늘 화면에 남는 UX 버그 방지
          if (att.checkOut != null ||
              att.status == 'missed_checkout' ||
              att.status == AttendanceModel.statusNoShow ||
              att.status == AttendanceModel.statusAbsent) {
            return false;
          }
        }
        return true;
      }).toList();
      final contracts = await contractsFuture;

      if (mounted) {
        setState(() {
          _attendanceMap.clear();       // stale 키 제거
          _attendanceMap.addAll(tempMap);
          _contracts = contracts;
          _todayWorks = visibleWorks;
          _upcomingReconfirmWorks = upcomingReconfirm;
          _isLoading = false;
          _loadError = null;
        });
      }

      debugPrint('✅ 오늘 근무: ${visibleWorks.length}개 (전체 후보: ${todayWorks.length}개)');
    } catch (e) {
      debugPrint('❌ 오늘 근무 조회 실패: $e');
      if (mounted) {
        // 실패를 **화면에 남는 상태**로 둔다 — 토스트는 사라진다.
        setState(() {
          _isLoading = false;
          _loadError = e;
        });
        ToastHelper.showError('근무 정보를 불러오는데 실패했습니다.');
      }
    }
  }

  /// 출근 체크 — 사업장 attendanceType에 따라 GPS/비콘 자동 분기
  Future<void> _checkIn(ApplicationModel work) async {
    if (_isProcessing) return;
    setState(() => _isProcessing = true);

    final uid = Provider.of<UserProvider>(context, listen: false).currentUser?.uid;
    if (uid == null) { setState(() => _isProcessing = false); return; }

    try {
      // 0. 기기 시간 변조 감지 (서버 시각과 5분 이상 차이 시 차단)
      final timeValid = await DeviceIntegrityService().isDeviceTimeValid();
      if (!timeValid) {
        if (mounted) {
          await DialogHelper.showError(
            context,
            message: '기기 시간이 실제 시간과 크게 다릅니다.\n'
                '설정에서 "자동 날짜/시간"을 켠 후 다시 시도해주세요.',
          );
        }
        return;
      }

      // 1. 사업장 정보 로드 (attendanceType 확인)
      final business = await _firestoreService.getBusinessById(work.businessId);
      if (business == null) {
        if (mounted) await DialogHelper.showError(context, message: '사업장 정보를 찾을 수 없습니다.');
        return;
      }

      // [BUSINESS-ARCHIVE] 위치 확인 전에 막는다 — 닫힌 사업장에서 GPS 를 요구하지 않는다.
      if (AttendanceCheckScreen.closedForNewCheckIn(
          business, work, FormatHelper.toKstDate(_now()))) {
        if (mounted) {
          await DialogHelper.showError(
            context,
            message: '사업장이 운영을 종료해 오늘은 출근할 수 없어요.\n'
                '지난 근무의 급여는 그대로 처리됩니다.',
          );
        }
        return;
      }

      final type = business.attendanceType; // 'gps' | 'beacon' | 'both' | 'manual'

      // 2. 방식별 검증
      String usedMethod = type;
      double? lat, lng;

      // 수동 방식: 관리자만 처리 가능, 근로자는 직접 체크 불가
      if (type == 'manual') {
        if (mounted) {
          await DialogHelper.showError(
            context,
            title: '수동 출근 방식',
            message: '이 사업장은 관리자가 직접 출퇴근을 처리합니다.\n관리자에게 문의해주세요.',
          );
        }
        return;
      }

      if (type == 'gps') {
        // ── GPS 전용 ───────────────────────────────────────────
        final ok = await _verifyByGPS(business, loadingMsg: 'GPS 확인 중...');
        if (ok == null) return; // 권한 거부 등
        if (!ok.$1) return;    // 범위 밖
        lat = ok.$2; lng = ok.$3;
        usedMethod = 'gps';

      } else if (type == 'beacon') {
        // ── 비콘 전용 ─────────────────────────────────────────
        // [LOCATION-GATE] 비콘 스캔 후 GPS도 획득 — server GPS 거리 검증에 사용
        final ok = await _verifyByBeacon(business);
        if (!ok.$1 || !mounted) return;
        lat = ok.$2; lng = ok.$3;
        usedMethod = 'beacon';

      } else {
        // ── GPS + 비콘 병행 (both) ─────────────────────────────
        // GPS를 먼저 시도
        final gpsResult = await _verifyByGPS(business, silent: true);

        if (gpsResult != null && gpsResult.$1) {
          // GPS 성공
          lat = gpsResult.$2; lng = gpsResult.$3;
          usedMethod = 'gps';
        } else {
          // GPS 실패 또는 권한 없음 → 비콘 폴백
          // Toast를 먼저 표시하고 잠시 후 비콘 스캔 (로딩 다이얼로그와 겹침 방지)
          if (mounted) ToastHelper.showInfo('GPS 확인 불가 — 비콘으로 재시도합니다.');
          await Future.delayed(const Duration(milliseconds: 600));
          if (!mounted) return;
          // [LOCATION-GATE] 비콘 폴백도 GPS 좌표 획득 필수
          final beaconOk = await _verifyByBeacon(business);
          if (!beaconOk.$1 || !mounted) return;
          lat = beaconOk.$2; lng = beaconOk.$3;
          usedMethod = 'beacon';
        }
      }

      // 3. Firestore 출근 기록 저장 (비콘 방식은 lat/lng null — 불필요)
      // 단기 근무: work.workDate 사용 — 야간 근무 자정 이후 체크인 시 docId가 다음 날로 밀리는 것 방지 [060]
      // 장기 근무: 오늘 날짜 사용 — work.workDate는 계약 시작일(고정값)이라 날짜별 docId 분리 불가
      // [R7-P2-1 잔여] 장기 근무의 근무일도 **KST 자정**으로 만든다 —
      //   서버가 docId 를 KST 로 만들고(callableCheckIn), 홈·목록도 KST 로
      //   읽는다. 여기만 기기 로컬 자정이면 비-KST 기기에서 하루 밀린
      //   근무일이 저장된다.
      final attendanceWorkDate = work.isLongTermApplication
          ? FormatHelper.toKstDate(_now())
          : work.workDate;
      final attendanceId = await _firestoreService.checkIn(
        applicationId: work.id,
        userId: uid,
        businessId: work.businessId,
        businessName: work.businessName,
        workDate: attendanceWorkDate,
        workType: work.selectedWorkType,
        latitude: lat,
        longitude: lng,
        scheduledStartTime: work.startTime.isNotEmpty ? work.startTime : null,
        scheduledEndTime: work.endTime.isNotEmpty ? work.endTime : null,
        method: usedMethod,
        attendanceRules: business.attendanceRules,
      );

      if (attendanceId != null && mounted) {
        ToastHelper.showSuccess('출근이 완료되었습니다!');
        AnalyticsService.logCheckIn(method: usedMethod);
        if (!mounted) return;
        await _loadTodayWorks();
        if (!mounted) return;
        _showRoundingFeedback(work.id, isCheckIn: true);
      }
    } catch (e) {
      debugPrint('❌ 출근 체크 실패: $e');
      if (mounted) {
        await DialogHelper.showError(
          context,
          message: e.toString().replaceAll('Exception: ', ''),
        );
      }
      // [BUG-M1 수정 2026-07-27] 에러 후에도 재조회 — 배치 선처리(NO_SHOW 등)로 상태가 바뀐 경우 UI 동기화
      if (mounted) await _loadTodayWorks();
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      } else {
        _isProcessing = false; // mounted 아닐 때도 잠금 해제
      }
    }
  }

  // ── 반올림 피드백 ──────────────────────────────────────────────
  /// _loadTodayWorks() 완료 후 호출. 반올림이 발생한 경우에만 안내 토스트 표시.
  void _showRoundingFeedback(String workId, {required bool isCheckIn}) {
    final att = _attendanceMap[workId];
    if (att == null) return;

    final String? original;
    final String? rounded;
    if (isCheckIn) {
      original = att.originalCheckIn;
      rounded = att.checkIn;
    } else {
      original = att.originalCheckOut;
      rounded = att.checkOut;
    }

    if (original == null || rounded == null || rounded.isEmpty) return;
    final originalTrimmed = original.split(':').take(2).join(':');
    final roundedTrimmed  = rounded.split(':').take(2).join(':');
    if (originalTrimmed == roundedTrimmed) return;

    final label = isCheckIn ? '출근' : '퇴근';
    ToastHelper.showInfo('$label 시간 $originalTrimmed → $roundedTrimmed 으로 처리됐어요');
  }

  // ── GPS 검증 헬퍼 ──────────────────────────────────────────────
  /// 반환: null=권한없음/오류, (bool verified, double? lat, double? lng)
  Future<(bool, double?, double?)?> _verifyByGPS(
    BusinessModel business, {
    String loadingMsg = 'GPS 확인 중...',
    bool silent = false,
  }) async {
    // [RELEASE-CORRECTION-PRIVACY-INLINE-DISCLOSURE]
    //   OS 권한 팝업이 뜨기 **직전에** 위치를 왜·언제 쓰는지 먼저 말한다.
    //   이미 허용했거나 silent 폴백 분기면 뜨지 않는다 — 매번 묻지 않는다.
    //   여기서 물러나면 OS 팝업도 띄우지 않고 조용히 돌아간다(거부 안내 없음).
    if (!silent && await LocationHelper.willPromptForPermission()) {
      if (!mounted) return null;
      final agreed = await DialogHelper.showConfirm(
        context,
        title: PrivacyDisclosure.location.title,
        message: PrivacyDisclosure.location.asMessage,
        confirmText: '계속',
        icon: Icons.my_location,
        // [DU628b · 판정207 §4] 위치 고지 머리 아이콘 = brand — 행동 '계속'(brand)과 같은 계열 · 같은 화면 '퇴근 확인' 창의 기본 머리색과 같다.
        iconColor: AppColors.brand,
      );
      if (!agreed) return null;
    }

    // GPS 권한/서비스 상세 체크 — silent 모드에서는 OS 팝업 억제(both 모드 폴백 분기)
    final locationResult = await LocationHelper.checkAndRequestPermissionDetailed(
      requestIfNeeded: !silent,
    );
    if (locationResult != LocationCheckResult.ok) {
      if (!silent && mounted) {
        final isServiceOff  = locationResult == LocationCheckResult.serviceDisabled;
        final isDeniedForever = locationResult == LocationCheckResult.permissionDeniedForever;
        final goToSettings = await DialogHelper.showConfirm(
          context,
          title: isServiceOff ? 'GPS를 켜주세요' : '위치 권한 필요',
          message: isServiceOff
              ? '기기의 위치 서비스(GPS)가 꺼져 있습니다.\n설정 앱에서 위치 서비스를 켜주세요.'
              : isDeniedForever
                  ? '위치 권한이 영구적으로 거부되었습니다.\n설정 앱에서 위치 권한을 허용해주세요.'
                  : '출퇴근 체크를 위해 위치 권한이 필요합니다.',
          confirmText: '설정 열기',
          icon: isServiceOff ? Icons.gps_off : Icons.location_off,
          iconColor: AppColors.warning,
        );
        if (goToSettings) {
          if (isServiceOff) {
            LocationHelper.openLocationSettings();
          } else {
            LocationHelper.openAppSettings();
          }
        }
      }
      return null;
    }

    bool loadingDialogShown = false;
    NavigatorState? loadingNav;
    if (!silent && mounted) {
      loadingNav = Navigator.of(context, rootNavigator: true);
      DialogHelper.showLoading(context, message: loadingMsg);
      loadingDialogShown = true;
    }
    final position = await LocationHelper.getCurrentPosition().whenComplete(() {
      if (loadingDialogShown && loadingNav != null &&
          loadingNav.mounted && loadingNav.canPop()) {
        loadingNav.pop();
      }
    });

    if (position == null) {
      // LocationHelper.getCurrentPosition이 null 반환 = GPS 실패 또는 Mock GPS 감지
      if (!silent && mounted) {
        await DialogHelper.showError(
          context,
          message: 'GPS 위치를 가져올 수 없습니다.\n가짜 GPS 앱을 사용 중이거나 위치 서비스에 문제가 있습니다.',
        );
      }
      return null;
    }

    // GPS 정확도 경고 (100m 초과 시 — 실내 GPS 등)
    if (!silent && position.accuracy > 100 && mounted) {
      ToastHelper.showWarning(
        'GPS 정확도가 낮습니다 (${position.accuracy.toStringAsFixed(0)}m).\n'
        '야외에서 다시 시도하면 더 정확합니다.',
      );
    }

    // 사업장 GPS 좌표 미설정 체크
    if (business.latitude == null || business.longitude == null) {
      if (!silent && mounted) {
        await DialogHelper.showError(
          context,
          title: '사업장 위치 미설정',
          message: '사업장의 GPS 위치가 등록되어 있지 않습니다.\n관리자에게 사업장 위치 등록을 요청하세요.',
        );
      }
      return null;
    }

    // [BUG-M3 수정 2026-07-27] gpsRadius=0(미설정) 시 GPS 검증 항상 실패하는 버그 — 100m 기본값 적용
    final gpsRadius = business.gpsRadius > 0 ? business.gpsRadius.toDouble() : 100.0;
    final isNearby = LocationHelper.isWithinRadius(
      currentLat: position.latitude,
      currentLon: position.longitude,
      businessLat: business.latitude!,
      businessLon: business.longitude!,
      radiusInMeters: gpsRadius,
    );

    if (!isNearby && !silent && mounted) {
      final distance = LocationHelper.calculateDistance(
        lat1: position.latitude, lon1: position.longitude,
        lat2: business.latitude!, lon2: business.longitude!,
      );
      await DialogHelper.showError(
        context,
        title: '출근 위치 오류',
        message: '사업장에서 너무 멉니다.\n'
            '현재 거리: ${LocationHelper.formatDistance(distance)}\n'
            '사업장 근처(${gpsRadius.toInt()}m 이내)에서 출근해주세요.',
      );
    }

    return (isNearby, position.latitude, position.longitude);
  }

  // ── 비콘 검증 헬퍼 ─────────────────────────────────────────────
  /// 반환: (verified, lat, lng)
  /// [LOCATION-GATE] 비콘 스캔 성공 후 GPS 좌표도 필수 획득 — server GPS radius 검증에 사용
  /// bare beacon(GPS 좌표 없음) 원격 체크인 차단 목적
  Future<(bool, double?, double?)> _verifyByBeacon(BusinessModel business) async {
    final uuid = business.beaconUUID;
    if (uuid == null || uuid.isEmpty) {
      if (mounted) {
        await DialogHelper.showError(
          context,
          title: '비콘 설정 오류',
          message: '사업장에 비콘 UUID가 등록되어 있지 않습니다.\n관리자에게 문의하세요.',
        );
      }
      return (false, null, null);
    }

    // [FIX-HIGH] getBusinessById 이후 unmount 가능 — mounted 체크 후 Navigator.of(context) 호출
    if (!mounted) return (false, null, null);
    final nav = Navigator.of(context, rootNavigator: true);
    // [FIX-HIGH] GPS와 동일하게 loadingShown 플래그 도입 — mounted=false 시 다이얼로그가
    //            표시되지 않았음에도 nav.pop()이 실행돼 다른 라우트를 팝하는 버그 방지
    bool loadingShown = false;
    if (mounted) {
      DialogHelper.showLoading(context, message: '비콘 스캔 중...\n(최대 10초 소요)');
      loadingShown = true;
    }

    final result = await BeaconHelper.isBeaconNearby(
      uuid: uuid,
      major: business.beaconMajor,
      minor: business.beaconMinor,
      rssiThreshold: business.beaconRssiThreshold,
    );

    if (loadingShown && nav.canPop()) nav.pop(); // 로딩 다이얼로그를 열었을 때만 닫기
    if (!mounted) return (false, null, null);

    if (result == null) {
      if (mounted) {
        await DialogHelper.showError(
          context,
          title: '블루투스 오류',
          message: '블루투스 권한이 없거나 비콘 스캔에 실패했습니다.\n'
              '블루투스가 켜져 있는지 확인해주세요.',
        );
      }
      return (false, null, null);
    }

    if (!result) {
      if (mounted) {
        await DialogHelper.showError(
          context,
          title: '비콘 미감지',
          message: '사업장 비콘을 감지하지 못했습니다.\n'
              '사업장 내부에서 다시 시도해주세요.',
        );
      }
      return (false, null, null);
    }

    // [LOCATION-GATE] 비콘 근접 확인 후 GPS 좌표도 획득 — server-side GPS 검증에 필요
    // GPS가 없으면 server에서 위치 검증 불가 → 체크인 차단
    if (!mounted) return (false, null, null);
    DialogHelper.showLoading(context, message: 'GPS 확인 중...');
    final gpsPosition = await LocationHelper.getCurrentPosition();
    if (mounted && Navigator.of(context, rootNavigator: true).canPop()) {
      Navigator.of(context, rootNavigator: true).pop();
    }
    if (!mounted) return (false, null, null);

    if (gpsPosition == null) {
      if (mounted) {
        await DialogHelper.showError(
          context,
          title: 'GPS 필요',
          message: '비콘 출근 시 GPS 위치도 확인이 필요합니다.\n'
              'GPS를 활성화하고 다시 시도해주세요.',
        );
      }
      return (false, null, null);
    }

    return (true, gpsPosition.latitude, gpsPosition.longitude);
  }

  /// 퇴근 체크 — attendanceType에 따라 GPS/비콘 분기
  Future<void> _checkOut(ApplicationModel work, AttendanceModel attendance) async {
    if (_isProcessing) return;
    setState(() => _isProcessing = true);

    try {
      final confirmed = await DialogHelper.showConfirm(
        context,
        title: '퇴근 확인',
        message: '퇴근 처리하시겠습니까?',
        confirmText: '퇴근',
      );
      if (!confirmed || !mounted) return;
      final business = await _firestoreService.getBusinessById(work.businessId);
      if (business == null) {
        if (mounted) await DialogHelper.showError(context, message: '사업장 정보를 찾을 수 없습니다.');
        return;
      }

      final type = business.attendanceType;
      String usedMethod = type;
      double? lat, lng;

      if (type == 'manual') {
        if (mounted) {
          await DialogHelper.showError(
            context,
            title: '수동 출근 방식',
            message: '이 사업장은 관리자가 직접 출퇴근을 처리합니다.\n관리자에게 문의해주세요.',
          );
        }
        return;
      }

      if (type == 'beacon') {
        // 비콘 전용: [LOCATION-GATE] 비콘 스캔 후 GPS도 획득 — server GPS 거리 검증에 사용
        final ok = await _verifyByBeacon(business);
        if (!ok.$1 || !mounted) return;
        lat = ok.$2; lng = ok.$3;
        usedMethod = 'beacon';
      } else if (type == 'both') {
        // GPS + 비콘 병행: 출근과 동일하게 GPS 먼저, 실패 시 비콘 폴백
        final gpsResult = await _verifyByGPS(business, silent: true);
        if (gpsResult != null && gpsResult.$1) {
          lat = gpsResult.$2; lng = gpsResult.$3;
          usedMethod = 'gps';
        } else {
          if (mounted) ToastHelper.showInfo('GPS 확인 불가 — 비콘으로 재시도합니다.');
          await Future.delayed(const Duration(milliseconds: 600));
          if (!mounted) return;
          // [LOCATION-GATE] 비콘 폴백도 GPS 좌표 획득 필수
          final beaconOk = await _verifyByBeacon(business);
          if (!beaconOk.$1 || !mounted) return;
          lat = beaconOk.$2; lng = beaconOk.$3;
          usedMethod = 'beacon';
        }
      } else {
        // GPS 전용: 반경 확인 후 퇴근 처리
        final result = await _verifyByGPS(business, loadingMsg: 'GPS 확인 중...');
        if (result == null) return;
        final (ok, resultLat, resultLng) = result;
        if (!ok) return;
        lat = resultLat;
        lng = resultLng;
        usedMethod = 'gps';
      }

      // endTime < startTime 검증은 _firestoreService.checkOut() 내부에만 있음.
      //           클라이언트에서는 사전 차단 없이 서비스 계층의 에러 응답에만 의존.
      final success = await _firestoreService.checkOut(
        attendanceId: attendance.id,
        workDate: attendance.workDate,
        latitude: lat,
        longitude: lng,
        method: usedMethod,
        scheduledEndTime: work.endTime.isNotEmpty ? work.endTime : null,
        scheduledStartTime: work.startTime.isNotEmpty ? work.startTime : null,
        attendanceRules: business.attendanceRules,
      );

      if (success && mounted) {
        final uid = context.read<UserProvider>().currentUser?.uid;
        if (uid != null) _firestoreService.invalidateMyAttendanceCache(uid);
        AnalyticsService.logCheckOut(method: usedMethod);
        await _loadTodayWorks();
        if (!mounted) return;

        // [R7-ATTENDANCE-SHORT-SHIFT-BOUNDARY.2] 두 사실을 구분해 말한다.
        //
        //   사업장의 계산 단위가 남은 근무보다 크면 인정 시간이 0분이 된다
        //   (20분 근무 · 조퇴 단위 30분, 또는 유예 초과 지각 · 지각 단위 30분).
        //   예전에는 이 경우 퇴근 요청이 **실패**해서 근로자가 근무를 끝낼 수
        //   없었고 실제 퇴근 증거도 남지 않았다. 이제 증거는 기록되지만,
        //   그것을 "퇴근이 완료되었습니다" 로만 말하면 인정 0분과 관리자
        //   확인이 필요하다는 사실이 가려진다.
        //
        //   근로자 잘못이 아니므로 그렇게 읽히는 문구를 쓰지 않는다.
        final att = _attendanceMap[work.id];
        if (att?.isZeroWork == true) {
          await DialogHelper.showAlert(
            context,
            title: '퇴근 시각은 기록됐어요',
            message: '퇴근하신 시각은 그대로 저장됐습니다.\n\n'
                '다만 이 사업장의 근태 계산 기준으로는 인정 근무시간이 '
                '0분으로 계산돼, 관리자 확인이 필요합니다.\n'
                '관리자가 근태를 확인하면 급여가 계산됩니다.',
            icon: Icons.schedule,
            iconColor: AppColors.warning,
          );
        } else {
          ToastHelper.showSuccess('퇴근이 완료되었습니다!');
          _showRoundingFeedback(work.id, isCheckIn: false);
        }
      }
    } catch (e) {
      debugPrint('❌ 퇴근 체크 실패: $e');
      if (mounted) {
        await DialogHelper.showError(
          context,
          message: e.toString().replaceAll('Exception: ', ''),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  /// 리컨펌 응답 처리 — confirmed: 출근 확인, declined: 취소 후 목록 갱신
  Future<void> _respondToReconfirm(ApplicationModel work, String response) async {
    if (_isReconfirming) return;
    setState(() => _isReconfirming = true);
    try {
      final responder = widget.reconfirmResponder;
      final success = responder != null
          ? await responder(work.id, response)
          : await _firestoreService.respondToReconfirm(
              work.id,
              response: response,
            );
      if (!mounted) return;
      if (success) {
        if (response == 'confirmed') {
          ToastHelper.showSuccess('출근 확인이 완료되었습니다!');
        } else {
          ToastHelper.showInfo('근무가 취소되었습니다.');
        }
        await _loadTodayWorks();
      }
    } finally {
      if (mounted) setState(() => _isReconfirming = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // [R7-P3-4] 홈(flat)에서 들어오는데 이 화면만 파란 헤더였다.
    //   기능은 그대로 옮긴다 — 우상단 새로고침 버튼·홈·알림(배지 포함)과
    //   미서명 계약 바. 본문 SafeArea(top:false) 도 같은 자리에 둔다.
    return AppPageScaffold(
      title: '출퇴근 체크',
      actions: appPageActions(context, onRefresh: _loadTodayWorks),
      bottomNavigationBar: const PendingContractBar(useSafeArea: true),
      body: SafeArea(
        top: false,
        left: false,
        right: false,
        child: _isLoading
            ? const LoadingWidget(message: '근무 정보를 불러오는 중...')
            : (_todayWorks.isEmpty && _upcomingReconfirmWorks.isEmpty)
                ? (_loadError != null ? _buildErrorState() : _buildEmptyState())
                : RefreshIndicator(
                    onRefresh: _loadTodayWorks,
                    child: ListView.builder(
                      padding: ResponsiveHelper.listPadding(context),
                      // 오늘 근무(출근·퇴근)가 먼저, 내일 근무 리컨펌 응답은 그 뒤.
                      itemCount:
                          _todayWorks.length + _upcomingReconfirmWorks.length,
                      itemBuilder: (context, index) {
                        if (index >= _todayWorks.length) {
                          return _buildUpcomingReconfirmCard(
                              _upcomingReconfirmWorks[index - _todayWorks.length]);
                        }
                        final work = _todayWorks[index];
                        final attendance = _attendanceMap[work.id];
                        return _buildWorkCard(work, attendance);
                      },
                    ),
                  ),
      ),
    );
  }

  /// [R7-P2-3 P23-E] 읽지 못한 상태 — "근무 없음" 과 구분한다.
  Widget _buildErrorState() {
    return AppEmptyState(
      icon: Icons.cloud_off_outlined,
      iconColor: AppColors.grey500,
      title: '근무 정보를 불러오지 못했습니다',
      subtitle: '확정된 근무가 없다는 뜻이 아닙니다.\n잠시 후 다시 시도해주세요.',
      action: TextButton.icon(
        onPressed: _isLoading ? null : _loadTodayWorks,
        icon: const Icon(Icons.refresh, size: 18),
        label: const Text('다시 시도'),
      ),
    );
  }

  /// 빈 상태
  Widget _buildEmptyState() {
    return AppEmptyState(
      icon: Icons.event_busy,
      title: '오늘 확정된 근무가 없습니다',
      subtitle: '새로운 공고에 지원해보세요',
      action: FilledButton.icon(
        onPressed: () {
          final scope = UserTabScope.of(context);
          Navigator.of(context).pop();
          scope?.switchToTab(1);
        },
        icon: const Icon(Icons.search, size: 18),
        label: const Text('공고 보러가기'),
      ),
    );
  }

  /// 출근 버튼 영역 — 이 근무의 근로계약에 동의(양측 서명 완료)해야 열린다.
  ///
  /// [CONTRACT-BEFORE-CHECKIN] 2026-10-25 사용자 지시로 계약 동의를 출근 조건으로 되돌린다.
  ///
  ///   연혁: 2026-09-16 a713dbc([PREDEVICE-CONTRACT-GATE])는 이 화면의 계약 gate 를
  ///   걷어 냈다. 당시 서버 callableCheckIn 은 계약을 읽지 않았고(계약 없는
  ///   CONTRACT_PENDING 도 출근 성공), gate 는 pending_worker 만 막는 뒤집힌
  ///   모양이었으며, 앱만 막아 놓고 다음 날 06:00 자동 NO_SHOW 가 벌점을 주는
  ///   구조라는 이유였다.
  ///
  ///   지금은 사용자 지시("관리자가 확정 시 계약서를 보내고, 지원자가 동의하지
  ///   않으면 출근 버튼 비활성화")에 따라:
  ///     · 서버 callableCheckIn 이 같은 판정(계약 문서 기준)으로 출근을 거절한다.
  ///     · 판정은 지원서 status 가 아니라 계약 문서다 — 초대 수락은 계약 전 CONFIRMED.
  ///     · 계약 없음·사업주 서명 대기·근로자 동의 대기·무효·읽기 실패 → 모두 닫힘.
  ///   자동 노쇼는 바꾸지 않는다(2026-10-25 R1) — 동의하지 않아 출근 기록이 없으면
  ///   기존대로 결근 처리되고, 실제로 일했다면 관리자 근태 정정으로 고친다.
  ///   그래서 안내 문구도 그 결과를 숨기지 않는다.
  Widget _buildCheckInArea(ApplicationModel work) {
    final userProvider = Provider.of<UserProvider>(context, listen: false);
    final uid = userProvider.currentUser?.uid ?? '';
    final gate = CheckInContractGate.evaluate(
        work: work, uid: uid, contracts: _contracts);

    // [SIM-CHECKIN-EARLY] 서버가 아직 받지 않는 시각에는 요청 버튼을 열지 않는다.
    //   그 전에 누르면 위치 안내·권한·GPS 를 다 치른 뒤 서버 거절을 듣는다.
    //   판정의 권위는 그대로 서버다 — 이 화면은 같은 기준으로 미리 말할 뿐이다.
    final opensAt = AttendanceCheckScreen.checkInOpensAt(work, _now());
    final notYetOpen = opensAt != null && _now().isBefore(opensAt);
    if (notYetOpen && gate.allowsCheckIn) _scheduleOpensAtRebuild(opensAt);

    final button = LoadingButton.primary(
      text: '출근하기',
      icon: Icons.login,
      expand: true,
      isLoading: _isProcessing,
      onPressed:
          (notYetOpen || !gate.allowsCheckIn) ? null : () async => _checkIn(work),
    );
    final Widget checkInButton = (notYetOpen && gate.allowsCheckIn)
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              button,
              SizedBox(height: ResponsiveHelper.spacing(context, 6)),
              Text(
                '${FormatHelper.formatKstMonthDayTime(opensAt).split(' ').last}'
                '부터 출근할 수 있어요',
                textAlign: TextAlign.center,
                style: ResponsiveHelper.smallStyle(context,
                    color: AppColors.textSecondary),
              ),
            ],
          )
        : gate.allowsCheckIn
            // [UI-4] 지금 상태와 다음 단계를 말한다 — 버튼 하나만 있으면 출근 전인지,
            //   누르면 무엇을 하는지(위치 1회 확인) 화면에서 알 수 없었다.
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '아직 출근 전이에요 · 누르면 현재 위치를 한 번 확인해요',
                    textAlign: TextAlign.center,
                    style: ResponsiveHelper.smallStyle(context,
                        color: AppColors.textSecondary),
                  ),
                  SizedBox(height: ResponsiveHelper.spacing(context, 8)),
                  button,
                ],
              )
            : button;

    if (gate.allowsCheckIn) return checkInButton;

    final (String title, String body) = switch (gate.state) {
      CheckInContractState.workerPending => (
          '근로계약서에 동의해야 출근할 수 있어요',
          '계약서를 확인하고 동의(서명)하면 출근 버튼이 열려요. '
              '출근 기록이 없으면 기존 기준대로 결근 처리될 수 있어요.',
        ),
      CheckInContractState.employerPending => (
          '사업주 서명을 기다리고 있어요',
          '사업주가 서명한 계약서를 받으면 동의 후 출근할 수 있어요. '
              '근무가 가까우면 사업장 관리자에게 문의해 주세요.',
        ),
      CheckInContractState.missing => (
          '아직 근로계약서를 받지 않았어요',
          '사업장에서 계약서를 보내면 동의 후 출근할 수 있어요. '
              '근무가 가까우면 사업장 관리자에게 문의해 주세요.',
        ),
      CheckInContractState.unknown => (
          '계약서 상태를 확인하지 못했어요',
          '확인되기 전에는 출근할 수 없어요. 다시 시도해 주세요.',
        ),
      CheckInContractState.completed => ('', ''),
    };
    final signable = gate.signable;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          key: const ValueKey('checkin-contract-gate'),
          padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 12)),
          decoration: BoxDecoration(
            // [DU581b] 근로자 서명 필요(signable)일 때만 warningBg 면 · warningDark 아이콘/제목 · 설명 textSecondary(판정139 §4 545-R6) — 사업주 서명 대기 · 계약 없음 · 확인 실패 안내와 테두리는 그대로.
            color: signable != null ? AppColors.warningBg : AppColors.yellowWarnBg,
            borderRadius: BorderRadius.circular(8),
            // [DU581c] 서명 필요 안내 테두리 = 중립선 grey200(판정171 §4 DU581b '후속 중립선 정렬 가능' · 감사171 하위 선택) — 그 밖 갈래 테두리는 그대로.
            border: Border.all(color: signable != null ? AppColors.grey200 : AppColors.yellowWarnBorder),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.draw_outlined,
                  color: signable != null ? AppColors.warningDark : AppColors.yellowWarnDark, size: 18),
              SizedBox(width: ResponsiveHelper.spacing(context, 8)),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: ResponsiveHelper.smallStyle(context).copyWith(
                        color: signable != null ? AppColors.warningDark : AppColors.yellowWarnText,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(height: ResponsiveHelper.spacing(context, 2)),
                    Text(
                      body,
                      style: ResponsiveHelper.smallStyle(context).copyWith(
                        color: signable != null ? AppColors.textSecondary : AppColors.yellowWarnText,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        SizedBox(height: ResponsiveHelper.spacing(context, 8)),
        if (signable != null) ...[
          // [DU581c] 이 안내가 보이는 동안 하단 서명 띠를 중립면으로 낮춘다(대표 주의 = 이 안내 · 판정171 §4 DU581b) — 크기 0 · 누르기 0.
          const _SignNoticeHold(),
          OutlinedButton.icon(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ContractSignScreen(
                  contract: signable,
                  role: 'worker',
                ),
              ),
            ).then((_) async {
              // 서명 결과는 화면이 다시 읽은 계약 문서로만 판단한다(돌아온 값·캐시를 믿지 않는다).
              if (!mounted) return;
              await userProvider.refreshPendingContracts();
              if (!mounted) return;
              await _loadTodayWorks();
            }),
            icon: const Icon(Icons.description_outlined, size: 18),
            label: const Text('계약서 확인하고 동의하기'),
            style: OutlinedButton.styleFrom(
              // [DU581b] 계약서 확인하고 동의하기 = brand 글 · brand 외곽선(판정139 §4 545-R6 조작 brand · 이 단추는 서명 필요일 때만 있다).
              foregroundColor: AppColors.brand,
              side: const BorderSide(color: AppColors.brand),
              minimumSize: const Size(double.infinity, 44),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 8)),
        ] else if (gate.state == CheckInContractState.unknown) ...[
          TextButton.icon(
            onPressed: _isLoading ? null : _loadTodayWorks,
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('다시 시도'),
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 8)),
        ],
        checkInButton,
      ],
    );
  }

  /// 근무 카드
  Widget _buildWorkCard(ApplicationModel work, AttendanceModel? attendance) {
    final hasCheckedIn = attendance?.hasCheckedIn ?? false;
    final hasCheckedOut = attendance?.hasCheckedOut ?? false;
    // [DEVICE-MISMATCH-FIX] 출근 기록 없이 예정 시간이 끝난 단기 근무.
    //   DEV 실측 Zdn7(10:00~11:00): 14:58 에도 `출근하기`·`네, 출근합니다`·
    //   `아니요, 취소할게요`가 모두 눌릴 수 있었다. 이 화면에서 닫는다.
    //   ※ 배포 서버 callableCheckIn 에는 종료 상한이 없다 — 이 UI 차단은
    //     서버 결함을 고친 것이 아니다(별도 서버 수정 필요).
    final shiftEnded = !hasCheckedIn && work.hasShiftEndedAt(_now());
    if (!hasCheckedIn && !shiftEnded) {
      final endsAt = work.shiftEndInstant;
      if (endsAt != null) _scheduleShiftEndRebuild(endsAt);
    }

    // [DU253] 그림자 카드 → 흰 면·반경 16·grey200 선(S010·S082 와 같은 평평한 카드).
    return Card(
      margin: EdgeInsets.only(bottom: ResponsiveHelper.spacing(context, 16)),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppColors.grey200),
      ),
      color: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      child: Padding(
        padding: ResponsiveHelper.listPadding(context),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 사업장 정보
            Row(
              crossAxisAlignment: CrossAxisAlignment.start, // [DU253 v2] 이름이 여러 줄이면 배지는 첫 줄에
              children: [
                // 단기/장기 배지
                Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: ResponsiveHelper.spacing(context, 8),
                    vertical: ResponsiveHelper.spacing(context, 4),
                  ),
                  decoration: BoxDecoration(
                    color: work.isLongTermApplication
                        ? AppColors.longTermBg
                        : AppColors.shortTermBg,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    work.isLongTermApplication ? '장기' : '단기',
                    style: ResponsiveHelper.smallStyle(context).copyWith(
                      fontWeight: FontWeight.bold,
                      color: work.isLongTermApplication
                          ? AppColors.longTermDark
                          : AppColors.shortTermDark,
                    ),
                  ),
                ),
                SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                Expanded(
                  // [DU253] 말줄임 없이 줄을 바꾼다(식별 정보 — 잘리면 어느 근무인지 모른다).
                  //   [v2] 이름은 낱말 단위로(긴 낱말은 가운데에서만) — 'TextLayout.identity'. 읽기 도구에는 원문.
                  child: Text(
                    TextLayout.identity(work.businessName),
                    semanticsLabel: work.businessName,
                    style: ResponsiveHelper.subtitleStyle(context).copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),

            SizedBox(height: ResponsiveHelper.spacing(context, 12)),

            // 근무 정보
            _buildInfoRow(Icons.work_outline, work.selectedWorkType),
            SizedBox(height: ResponsiveHelper.spacing(context, 6)),
            // [DU253] 시안 '오늘의 약속'처럼 근무 시간을 크게 — 이 화면에서 가장 먼저 확인하는 값이다.
            _buildBigTime('${work.startTime} ~ ${work.endTime}'),
            SizedBox(height: ResponsiveHelper.spacing(context, 6)),
            _buildInfoRow(
              Icons.payments_outlined,
              '${_fmt.format(work.wage)}원/${work.wageType == 'daily' ? '일' : '시간'}',
            ),

            Divider(
              height: ResponsiveHelper.spacing(context, 24),
              color: AppColors.dividerLight,
            ),

            // 리컨펌 요청 섹션 (단기 미출근 + reconfirmStatus=='pending'일 때만)
            if (!work.isLongTermApplication &&
                !hasCheckedIn &&
                !shiftEnded &&
                work.reconfirmStatus == 'pending')
              _buildReconfirmSection(work),

            // 출근 상태 정보
            if (hasCheckedIn) ...[
              _buildAttendanceInfo(attendance!),
              SizedBox(height: ResponsiveHelper.spacing(context, 12)),
            ],

            // 출근/퇴근 버튼
            if (attendance?.status == AttendanceModel.statusNoShow ||
                attendance?.status == AttendanceModel.statusAbsent)
              _buildNoShowBanner(attendance!.status)
            else if (shiftEnded)
              _buildShiftEndedBanner()
            else if (!hasCheckedIn)
              _buildCheckInArea(work)
            else if (!hasCheckedOut)
              LoadingButton(
                text: '퇴근하기',
                icon: Icons.logout,
                expand: true,
                // [UI-4] 지금 할 행동 하나 = 브랜드 채움(홈 Hero 와 같은 색). 출근·퇴근은
                //   글자·아이콘·위 `출근 완료` 상자로 구별되고, 확인 단계는 그대로다.
                backgroundColor: AppColors.brand,
                isLoading: _isProcessing,
                onPressed: () async => _checkOut(work, attendance!),
              )
            else
              Container(
                width: double.infinity,
                padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 12)),
                decoration: BoxDecoration(
                  color: AppColors.successBg,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.successLight),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.check_circle,
                      color: AppColors.successDark,
                      size: ResponsiveHelper.iconSize(context, 20),
                    ),
                    SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                    Text(
                      '출퇴근 완료',
                      style: ResponsiveHelper.bodyStyle(context).copyWith(
                        fontWeight: FontWeight.bold,
                        color: AppColors.successDark,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// 리컨펌 섹션 — 단기 근무 중 reconfirmStatus=='pending'이고 미출근일 때 카드 내 표시
  /// [SIM-RECONFIRM-ACCESS] 내일 근무의 리컨펌 응답 카드 — 응답만 받는다.
  ///
  ///   근무 카드와 같은 모양이되 출근 요청 영역(`_buildCheckInArea`)·출근 기록
  ///   조회를 붙이지 않는다. 그 근무의 출근은 당일 오늘 근무 카드에서, 기존
  ///   허용 시각(`checkInOpensAt`)부터 열린다.
  Widget _buildUpcomingReconfirmCard(ApplicationModel work) {
    const dow = ['월', '화', '수', '목', '금', '토', '일'];
    final d = FormatHelper.toKstDate(work.workDate);
    final dateLabel = '${d.month}월 ${d.day}일(${dow[d.weekday - 1]})';
    // [DU253] 근무 카드와 같은 평평한 흰 카드.
    return Card(
      margin: EdgeInsets.only(bottom: ResponsiveHelper.spacing(context, 16)),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppColors.grey200),
      ),
      color: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      child: Padding(
        padding: ResponsiveHelper.listPadding(context),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '내일 근무 · $dateLabel',
              // [DU628b · 판정207 §4] '내일 근무 · 날짜' 머리 글 = 일반 강조 brand(같은 카드의 두 번째 파랑 infoDark 정리 · 흰 카드 위 5.58).
              style: ResponsiveHelper.smallStyle(context, color: AppColors.brand)
                  .copyWith(fontWeight: FontWeight.bold),
            ),
            SizedBox(height: ResponsiveHelper.spacing(context, 6)),
            Text(
              TextLayout.identity(work.businessName), // [DU253 v2]
              semanticsLabel: work.businessName,
              style: ResponsiveHelper.subtitleStyle(context)
                  .copyWith(fontWeight: FontWeight.bold),
            ),
            SizedBox(height: ResponsiveHelper.spacing(context, 8)),
            _buildInfoRow(Icons.work_outline, work.selectedWorkType),
            SizedBox(height: ResponsiveHelper.spacing(context, 4)),
            SizedBox(height: ResponsiveHelper.spacing(context, 2)),
            _buildBigTime('${work.startTime} ~ ${work.endTime}'), // [DU253]
            Divider(
              height: ResponsiveHelper.spacing(context, 24),
              color: AppColors.dividerLight,
            ),
            _buildReconfirmSection(work,
                question: '$dateLabel 근무에 출근하실 수 있으신가요?'),
          ],
        ),
      ),
    );
  }

  Widget _buildReconfirmSection(ApplicationModel work, {String? question}) {
    return Container(
      width: double.infinity,
      margin: EdgeInsets.only(bottom: ResponsiveHelper.spacing(context, 12)),
      padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 14)),
      decoration: BoxDecoration(
        color: AppColors.infoBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.infoLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.help_outline_rounded,
                color: AppColors.infoDark,
                size: ResponsiveHelper.iconSize(context, 16),
              ),
              SizedBox(width: ResponsiveHelper.spacing(context, 6)),
              Text(
                '출근 확인 요청',
                style: ResponsiveHelper.smallStyle(context).copyWith(
                  fontWeight: FontWeight.bold,
                  color: AppColors.infoDark,
                ),
              ),
            ],
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 8)),
          Text(
            question ?? '오늘 근무에 출근하실 수 있으신가요?',
            style: ResponsiveHelper.smallStyle(context, color: AppColors.grey700),
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 10)),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _isReconfirming
                      ? null
                      : () async {
                          // [SIM-RECONFIRM-DECLINE-ALIGN] 서버는 '출근 불가'를 기존 확정취소와
                          //   같은 기준(시작 5분 전부터 노쇼 제재)으로 처리한다. 누르기 전에
                          //   같은 안내·같은 시각 기준을 보여 준다 — 기존 확정취소 확인창 그대로.
                          final noShows = Provider.of<UserProvider>(context, listen: false)
                                  .currentUser
                                  ?.recentNoShowCount ??
                              0;
                          final result = await ConfirmCancelDialog.show(
                            context: context,
                            workDate: work.workDate,
                            workType: work.selectedWorkType,
                            timeRange: '${work.startTime}~${work.endTime}',
                            businessName: work.businessName,
                            currentNoShowCount: noShows,
                            scheduledStartTime: work.startTime,
                            now: _now(),
                          );
                          if (result == ConfirmCancelResult.proceed && mounted) {
                            await _respondToReconfirm(work, 'declined');
                          }
                        },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.grey600,
                    side: BorderSide(color: AppColors.grey300),
                    padding: EdgeInsets.symmetric(
                      vertical: ResponsiveHelper.spacing(context, 8),
                    ),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                  ),
                  child: Text(
                    '아니요, 취소할게요',
                    style: ResponsiveHelper.smallStyle(context, color: AppColors.grey600),
                  ),
                ),
              ),
              SizedBox(width: ResponsiveHelper.spacing(context, 8)),
              Expanded(
                child: FilledButton(
                  onPressed: _isReconfirming
                      ? null
                      : () => _respondToReconfirm(work, 'confirmed'),
                  style: FilledButton.styleFrom(
                    // [DU628b · 판정207 §4] '네, 출근합니다' = 대표 행동 brand 채움(흰 글 5.58 · 출근하기 · 퇴근하기와 같은 색).
                    backgroundColor: AppColors.brand,
                    padding: EdgeInsets.symmetric(
                      vertical: ResponsiveHelper.spacing(context, 8),
                    ),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                  ),
                  child: Text(
                    '네, 출근합니다',
                    style: ResponsiveHelper.smallStyle(context)
                        .copyWith(color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 노쇼/결근 안내 배너
  /// [DEVICE-MISMATCH-FIX] 출근 기록 없이 근무 시간이 끝났다 — 누를 것이 없다.
  ///   노쇼 확정은 서버 자동 처리(다음 날 06:00) 또는 관리자 몫이므로
  ///   여기서 `노쇼`라고 단정하지 않는다.
  Widget _buildShiftEndedBanner() {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 12)),
      decoration: BoxDecoration(
        color: AppColors.warningBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.warningLight),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.event_busy,
            color: AppColors.warningDark,
            size: ResponsiveHelper.iconSize(context, 20),
          ),
          SizedBox(width: ResponsiveHelper.spacing(context, 8)),
          Flexible(
            child: Text(
              '근무 시간이 지났어요 · 출근 기록이 없어요',
              textAlign: TextAlign.center,
              style: ResponsiveHelper.bodyStyle(context).copyWith(
                fontWeight: FontWeight.bold,
                color: AppColors.warningDark,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNoShowBanner(String status) {
    final isNoShow = status == AttendanceModel.statusNoShow;
    // [DU596b · 판정139 §3 :44 PP-STATUS-PAIR · 판정177 §6 :60] 명시 결근 결과 = 노쇼와 같은 error 짝(면 errorBg · 선 errorLight · 아이콘/글 errorDark).
    //   시간이 지난 미출근 배너(_buildShiftEndedBanner)는 warning 그대로 — 노쇼/결근 문구만 isNoShow 로 가른다.
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 12)),
      decoration: BoxDecoration(
        color: AppColors.errorBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: AppColors.errorLight,
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.block,
            color: AppColors.errorDark,
            size: ResponsiveHelper.iconSize(context, 20),
          ),
          SizedBox(width: ResponsiveHelper.spacing(context, 8)),
          Text(
            isNoShow ? '노쇼 처리됨' : '결근 처리됨',
            style: ResponsiveHelper.bodyStyle(context).copyWith(
              fontWeight: FontWeight.bold,
              color: AppColors.errorDark,
            ),
          ),
        ],
      ),
    );
  }

  /// 정보 행
  Widget _buildInfoRow(IconData icon, String text) {
    return Row(
      children: [
        Icon(
          icon,
          size: ResponsiveHelper.iconSize(context, 16),
          color: AppColors.grey600,
        ),
        SizedBox(width: ResponsiveHelper.spacing(context, 8)),
        Expanded(
          // [DU253] 보조색, 말줄임 없이 줄바꿈(큰 글자에서 업무명·시급이 잘리지 않게).
          child: Text(
            text,
            style: ResponsiveHelper.bodyStyle(context, color: AppColors.textSecondary),
          ),
        ),
      ],
    );
  }

  /// [DU253] 근무 시간 — 시안 '오늘의 약속'의 큰 시간 글자(22 bold 본문색). 문자열은 그대로다.
  Widget _buildBigTime(String text) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 22,
        fontWeight: FontWeight.bold,
        color: AppColors.textPrimary,
        letterSpacing: -0.3,
      ),
    );
  }

  /// "HH:mm:ss" → "HH:mm"
  String _trimSeconds(String? t) {
    if (t == null) return '-';
    final parts = t.split(':');
    return parts.length >= 2 ? '${parts[0]}:${parts[1]}' : t;
  }

  /// 출근 정보 카드
  Widget _buildAttendanceInfo(AttendanceModel attendance) {
    // 상태에 따른 색상/아이콘/라벨
    final Color bgColor;
    final Color borderColor;
    final Color iconColor;
    final IconData icon;
    final String label;

    if (attendance.hasCheckedOut) {
      if (attendance.isEarlyLeave) {
        bgColor = AppColors.warningBg;
        borderColor = AppColors.warningLight;
        iconColor = AppColors.warningDark;
        icon = Icons.directions_run;
        label = '조퇴';
      } else {
        bgColor = AppColors.successBg;
        borderColor = AppColors.successLight;
        iconColor = AppColors.successDark;
        icon = Icons.check_circle;
        label = '출퇴근 완료';
      }
    } else if (attendance.isLate) {
      bgColor = AppColors.warningBg;
      borderColor = AppColors.warningLight;
      iconColor = AppColors.warningDark;
      icon = Icons.warning_amber_rounded;
      label = '지각';
    } else {
      bgColor = AppColors.infoBg;
      borderColor = AppColors.infoLight;
      iconColor = AppColors.infoDark;
      icon = Icons.check_circle;
      label = '출근 완료';
    }

    return Container(
      padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 12)),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: iconColor, size: ResponsiveHelper.iconSize(context, 20)),
              SizedBox(width: ResponsiveHelper.spacing(context, 8)),
              Text(
                label,
                style: ResponsiveHelper.bodyStyle(context).copyWith(
                  fontWeight: FontWeight.bold,
                  color: iconColor,
                ),
              ),
            ],
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 8)),
          Text(
            '출근 시각: ${_trimSeconds(attendance.checkIn)}',
            style: ResponsiveHelper.smallStyle(context, color: AppColors.grey700),
          ),
          if (attendance.hasCheckedOut) ...[
            SizedBox(height: ResponsiveHelper.spacing(context, 4)),
            Text(
              '퇴근 시각: ${_trimSeconds(attendance.checkOut)}',
              style: ResponsiveHelper.smallStyle(context, color: AppColors.grey700),
            ),
            SizedBox(height: ResponsiveHelper.spacing(context, 4)),
            Text(
              '근무 시간: ${attendance.workHours?.toStringAsFixed(1) ?? '-'}시간',
              style: ResponsiveHelper.smallStyle(context).copyWith(
                fontWeight: FontWeight.bold,
                color: AppColors.grey800,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// [DU581c] 근로자 서명 필요 출근 안내(_buildCheckInArea 의 signable 갈래)가 **보이는 화면에** 붙어 있는 동안 PendingContractBar.bodyNoticeCount 를 하나 올린다.
//   보임 = TickerMode 켜짐 — 불투명 화면에 덮인 route 와 셸의 숨은 탭(user_root_screen 이 탭마다 TickerMode 로 감싼다)에서는 내린다.
//   ContractSignScreen.openCount 와 같은 꼴 — 빌드 · 폐기 도중 띠를 다시 그리게 하지 않도록 한 박자 뒤(microtask)에 바꾼다.
//   표시만: 글 · 분기 · 진입 · 쓰기 0. 셸 띠(UserRootScreen) · 화면 띠(셸 밖) 둘 다 같은 값을 본다(판정171 §4 DU581b).
class _SignNoticeHold extends StatefulWidget {
  const _SignNoticeHold();

  @override
  State<_SignNoticeHold> createState() => _SignNoticeHoldState();
}

class _SignNoticeHoldState extends State<_SignNoticeHold> {
  bool _held = false;

  void _hold(bool on) {
    if (on == _held) return;
    _held = on;
    Future.microtask(() => PendingContractBar.bodyNoticeCount.value += on ? 1 : -1);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _hold(TickerMode.of(context));
  }

  @override
  void dispose() {
    _hold(false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}