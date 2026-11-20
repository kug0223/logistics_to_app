import '../../../models/core/attendance_model.dart';
import '../../../utils/format_helper.dart';

/// [DU1 SubAdmin §3] 급여 권한만(W ∧ ¬K) 가진 관리자의 **일자 급여 입력** — 허용 범위 안의 adapter.
///
/// 허용 reader 만 쓴다:
///   - 근태: `callableGetAdminAttendances`(K‖W, W 호출자는 금액 원문 포함) — 정확히 그 KST 하루.
///   - 이름: `callableGetUsersBatch(purpose: workerDirectory)` — 이 파일은 uid 목록만 만든다.
/// 쓰지 않는 것(DU_followup_4 §3): `workerOperation`·`capacity` 목적 지원서 조회, 지원서 문서 전체 GET.
///
/// 그 결과 [WageConfirmDialog] 의 `workers`(ApplicationModel)가 요구하는 **일정 필드**
/// ([scheduleFieldsUnavailable])는 허용 reader 어디에도 없다 — 근태 writer 두 곳
/// (`index.ts` 관리자 출근 35537·앱 출근 41786)이 applicationId·userId·workType·snapshotWage/Type 만
/// 저장하고, 미마감 큐 CF 는 건수만 준다. 그래서 이 adapter 는 급여창을 열지 않고
/// **그 날 급여 행을 분류**해 "급여에서 처리 가능 / 인력 확인 필요"를 숫자로 말할 근거만 만든다.
/// 급여창 연결은 일정 필드 공급원(서버 최소안: 급여 목적 지원서 allowlist)이 정해진 뒤다.
///
/// 분류 술어는 급여창 `_initData`(wage_confirm_dialog.dart)와 같다 — 복제가 아니라 읽기 전용 사전 집계다:
///   퇴근 없음 → 제외(미마감이면 인력 확인 필요) · confirmed/transferred → 마감(adminConfirmed 무관) ·
///   adminConfirmed=false 인 pending/calculated → 인력 확인 필요(adminConfirm 은 K 전용) ·
///   나머지 pending → 미확정, calculated → 확정내역.
///
/// [DU1 followup_5 §4] 날짜 입력은 **달력일(civil)** 이다 — 미마감 큐 `item.workDate`
/// (unclosed_action_queue_screen.dart:39)·당일명단 `kstDayKeyOfCivil(widget.date)`
/// (attendance_status_dialog.dart:229)와 같다. 성분을 KST 달력일로 못박은 뒤에만 창·키를 만든다.
/// (instant 로 해석하면 UTC+13 기기의 `DateTime(2026,11,3)` 이 KST 11/2 가 된다.)
/// 근태 `workDate` 는 반대로 **실제 instant**(KST 자정)라 `toKstDate` 로 읽는다.
class WageDayClassification {
  const WageDayClassification({
    required this.pending,
    required this.calculated,
    required this.settled,
    required this.needsWorkerOps,
    required this.settledWithoutCheckout,
    required this.missingCheckIn,
    required this.otherStatus,
    required this.ambiguousApplicationIds,
    required this.unparsed,
    required this.userIds,
  });

  /// 급여창 미확정 탭에 들어갈 행(퇴근·출근 있음 ∧ adminConfirmed ∧ pending).
  final int pending;

  /// 확정내역 탭(퇴근·출근 있음 ∧ adminConfirmed ∧ calculated).
  final int calculated;

  /// 마감내역(confirmed/transferred) — adminConfirmed 와 관계없이.
  final int settled;

  /// 퇴근 전이거나 관리자 근태 확인 전 — 인력 관리 권한자가 먼저 처리해야 한다.
  final int needsWorkerOps;

  /// 마감(confirmed/transferred)이지만 퇴근 기록이 없어 급여창에 나오지 않는 행.
  final int settledWithoutCheckout;

  /// 탭에는 들어가지만 출근 시각이 없어 계산이 실패할 행(급여창 :543 · 서버 :27740). [tabRowsWithCheckIn] 에서 뺀다.
  final int missingCheckIn;

  /// pending/calculated/confirmed/transferred 가 아닌 급여 상태 — 창이 어느 탭에도 넣지 않는다.
  final int otherStatus;

  /// 같은 지원서·같은 날 근태가 둘 이상이고 정본 id(`{appId}_{YYYYMMDD}`)가 없는 지원서 — 조용히 고르지 않는다.
  final Set<String> ambiguousApplicationIds;

  /// 파싱 실패(필수 필드 누락 등) 건수.
  final int unparsed;

  /// 이름 조회용(workerDirectory) uid.
  final Set<String> userIds;

  /// [DU1 followup_6 §3] 급여창 pending/calculated 탭에 **실제로 편입되는** 행 수 — 출근 기록 없는 행도 탭에는 들어간다
  /// (급여창 _initData 는 checkIn 을 보지 않는다). 처리 가능 보증이 아니다.
  int get wageTabRows => pending + calculated + missingCheckIn;

  /// 그중 **출근 기록이 있는** pending/calculated — 근태 쪽 계산 전제는 갖춘 행. 이것도 처리 가능 보증은 아니다 —
  /// 지원서 존재·약속 조건은 이 adapter 가 확인하지 못한다([applicationVerified] = false).
  int get tabRowsWithCheckIn => pending + calculated;

  /// 이 분류가 그 날 **근태**를 빠짐없이 설명하는가(근태 분류 완전성 — 지원서·처리 가능과 무관). 파싱 실패·모호가 있으면 false —
  /// 그때 0 이나 작은 숫자를 '정상 0'·'처리 가능 N'으로 말하지 않는다.
  bool get isComplete => unparsed == 0 && ambiguousApplicationIds.isEmpty;

  /// 지원서(약속·일정 키)를 확인했는가 — 허용 reader 가 없어 항상 false.
  bool get applicationVerified => false;

  /// 급여창 `workers` 가 요구하지만 허용 reader 가 주지 않는 지원서 필드.
  static const scheduleFieldsUnavailable = <String>{
    'toId', 'slotId', 'workDetailId', 'startTime', 'endTime',
  };

  /// [DU1 followup_5 §4 · followup_6 §3] 급여 목적 지원서 응답의 **후보 allowlist**(미구현·미배포) — 검증된 최소 집합이 아니다.
  ///   개별 필수성이 시험으로 확인된 것: workDate·appliedAt(파싱), toId·slotId·startTime·endTime·workDetailId·selectedWorkType
  ///   (급여창 직접 사용), wage·breakMinutes·baseHourlyWage·nightAllowanceApplied·nightIncluded·taxDeductionType(약속 resolve).
  ///   나머지(uid·businessId·status·wdId·businessName·wageType·baseHourlyWageMode)는 소비처는 있으나 개별 제거 반례가 없다.
  ///   지급일정: 서버 우선순위는 지원서 약속 → 계약 스냅샷 → **클라이언트 fallback**(srvResolvePromisedPaySchedule).
  ///   급여창은 live 업무의 지급일정을 보낸다 — 후보 B 는 이를 live 업무 projection(payScheduleType/Day/Time)으로 공급한다.
  ///   레거시 약속은 wageType 도 공고 현재보다 우선한다(daily 지원서 vs hourly 공고 반례, candB v2).
  ///   메시지·취소/퇴사 사유·근태 정책 동의·충돌 정보·아이콘 등은 넣지 않는다(급여창 미소비).
  ///   응답 계약(서버가 지켜야 할 것): 문서 id 는 envelope 로 따로 주고 **attendance.applicationId 와 같아야** 하며,
  ///   지원서의 uid == attendance.userId · businessId == 요청 사업장 · workDate(단기) 가 그 근태의 KST 근무일과 맞는 것만 준다.
  ///   못 맞추면 그 행은 빼고 **불완전**(missing/불일치 건수)으로 알린다 — 빈 결과를 정상 0 으로 만들지 않는다.
  static const candidateApplicationProjection = <String>{
    // 파싱 필수
    'workDate', 'appliedAt', 'uid', 'businessId', 'status',
    // 관계·일정 키
    'toId', 'slotId', 'workDetailId', 'wdId', 'selectedWorkType', 'startTime', 'endTime', 'businessName',
    // 약속 조건(promisedCompensation)
    'wage', 'wageType', 'baseHourlyWage', 'baseHourlyWageMode', 'breakMinutes',
    'nightAllowanceApplied', 'nightIncluded', 'taxDeductionType',
  };
}

class WageDayInputsAdapter {
  const WageDayInputsAdapter._();

  /// 달력일 → KST 하루의 조회 창(ms). 당일명단과 달리 전날로 넓히지 않는다 — 단위가 미마감 큐와 같은 business × workDate 다.
  static ({int startMs, int endMs}) queryWindow(DateTime civilDay) {
    final (s, e) = FormatHelper.kstDayRange(FormatHelper.kstDayKeyOfCivil(civilDay));
    return (startMs: s.millisecondsSinceEpoch, endMs: e.millisecondsSinceEpoch);
  }

  /// 달력일의 정본 근태 id 날짜 키(서버 `srvHomeDateStr` 과 같은 YYYYMMDD) — 성분 그대로.
  static String civilDayKey(DateTime civilDay) => _ymd(civilDay.year, civilDay.month, civilDay.day);

  /// 근태 `workDate`(KST 자정 instant)의 날짜 키 — instant 를 KST 달력일로.
  static String instantDayKey(DateTime instant) {
    final d = FormatHelper.toKstDate(instant);
    return _ymd(d.year, d.month, d.day);
  }

  static String _ymd(int y, int m, int d) =>
      '${y.toString().padLeft(4, '0')}${m.toString().padLeft(2, '0')}${d.toString().padLeft(2, '0')}';

  /// `limitReached` 면 모른다 — 0 으로 만들지 않고 throw 한다.
  static WageDayClassification classify({
    required List<Map<String, dynamic>> items,
    required bool limitReached,
    required String businessId,
    required DateTime civilDay,
  }) {
    if (limitReached) {
      throw StateError('wage-day attendance limit reached');
    }
    final key = civilDayKey(civilDay);
    final byApp = <String, List<AttendanceModel>>{};
    var unparsed = 0;
    for (final raw in items) {
      final m = Map<String, dynamic>.from(raw);
      final id = m.remove('id') as String? ?? '';
      m['status'] = AttendanceModel.displayStatusOfRaw(m['status']);
      final a = AttendanceModel.tryFromMap(m, id);
      if (a == null || a.applicationId.isEmpty) {
        unparsed++;
        continue;
      }
      if (a.businessId != businessId) continue; // 방어 — 다른 사업장 행은 세지 않는다
      if (instantDayKey(a.workDate) != key) continue; // 창 경계 밖(다른 KST 날)
      byApp.putIfAbsent(a.applicationId, () => []).add(a);
    }

    var pending = 0, calculated = 0, settled = 0, needsOps = 0;
    var settledWithoutCheckout = 0, missingCheckIn = 0, otherStatus = 0;
    final ambiguous = <String>{};
    final uids = <String>{};
    for (final entry in byApp.entries) {
      AttendanceModel a;
      if (entry.value.length == 1) {
        a = entry.value.single;
      } else {
        final canonical = entry.value.where((x) => x.id == '${entry.key}_$key').toList();
        if (canonical.length != 1) {
          ambiguous.add(entry.key);
          continue;
        }
        a = canonical.single;
      }
      uids.add(a.userId);
      final ws = a.wageStatus;
      final isSettled = ws == AttendanceModel.wageConfirmed || ws == AttendanceModel.wageTransferred;
      // 급여창과 같은 순서: 퇴근 없음이 가장 먼저 걸러진다(마감분이라도 창에 나오지 않는다).
      if (a.checkOut == null) {
        if (isSettled) {
          settledWithoutCheckout++;
        } else {
          needsOps++;
        }
      } else if (isSettled) {
        settled++;
      } else if (a.adminConfirmed != true) {
        needsOps++;
      } else if (ws != AttendanceModel.wageCalculated && ws != AttendanceModel.wagePending) {
        otherStatus++; // 창이 어느 탭에도 넣지 않는 값 — 미확정으로 세지 않는다
      } else if (a.checkInAt == null) {
        missingCheckIn++; // 탭에는 들어가나 계산이 실패한다 — 처리 가능으로 세지 않는다
      } else if (ws == AttendanceModel.wageCalculated) {
        calculated++;
      } else {
        pending++;
      }
    }
    return WageDayClassification(
      pending: pending,
      calculated: calculated,
      settled: settled,
      needsWorkerOps: needsOps,
      settledWithoutCheckout: settledWithoutCheckout,
      missingCheckIn: missingCheckIn,
      otherStatus: otherStatus,
      ambiguousApplicationIds: ambiguous,
      unparsed: unparsed,
      userIds: uids,
    );
  }
}
