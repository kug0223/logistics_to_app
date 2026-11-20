// [DU1 후속21 §1] 급여 일자 후보(B) 응답의 소비 구현 — **격리**(기본 네트워크 reader·화면·확정 버튼에 연결하지 않는다).
//   후속20 의 시험 전용 소비경계(test/support/du1_candb_wire_consumer.dart)를 이 파일 한 곳으로 옮겼다 — support 는 이것을 다시 내보낸다.
//   세 사실을 **따로** 돌려준다:
//     (1) 근태 분류 — 기존 WageDayInputsAdapter.classify 그대로(projection 키를 뺀 행)
//     (2) 응답 완전성 — 서버 wageDay(complete·missing·mismatch·inputIncomplete·사유) 원문 보존
//     (3) 행별 지원서·업무 입력 연결 — 기존 cfHydrateResponse(_cfHydrate)·ApplicationModel·WorkDetailHelper 재사용
//   일자 응답이 불완전하면 **일괄 처리 가능 판정을 보류**한다(행별 허용 정책·확정 실행은 정하지 않는다).
//   applicationVerified(기존 상수 false)를 바꾸지 않는다. applications/TO/slot 직접 read fallback 은 없다.
import '../../../models/core/application_model.dart';
import '../../../models/core/attendance_model.dart';
import '../../../services/firestore_service.dart';
import '../../../utils/format_helper.dart';
import '../../../utils/work_detail_helper.dart';
import 'wage_day_inputs_loader.dart';

/// 행별 projection 입력 연결 상태.
enum CandidateLink {
  /// 서버가 projection 을 붙이지 않았다(missing·mismatch·부모거절·불완전 — 사유는 wageDay 가 말한다)
  none,

  /// projection 은 있으나 기존 모델로 파싱되지 않았다
  unparsed,

  /// 파싱됐으나 근태와 관계(envelope id·uid·사업장·KST 근무일)가 맞지 않는다
  relationMismatch,

  /// 관계가 맞고, 그 지원서 문맥의 workDetailId 키로 live 업무가 resolve 됐다
  linked,

  /// 관계는 맞지만 live 업무를 resolve 하지 못했다(약속 값만 — live 조회 성공으로 치지 않는다)
  liveMissing,
}

class CandidateRow {
  CandidateRow(this.attendanceId, this.link, {this.application, this.resolved});
  final String attendanceId;
  final CandidateLink link;
  final ApplicationModel? application;

  /// 기존 WorkDetailHelper.resolve 결과(live ∪ 약속, 약속 우선) — linked 일 때만
  final Map<String, dynamic>? resolved;
}

class CandidateWageDay {
  CandidateWageDay({required this.attendance, required this.wageDay, required this.rows});

  /// 기존 근태 분류(지원서와 무관). isComplete=true 여도 응답 불완전은 지워지지 않는다.
  final WageDayClassification attendance;

  /// 서버 wageDay 원문(재수화 뒤 그대로). 없으면 null — 후보 응답이 아니다.
  final Map<String, dynamic>? wageDay;
  final Map<String, CandidateRow> rows;

  /// 서버가 일자 응답 전체를 완전하다고 말했는가. wageDay 가 없으면 false(모른다 ≠ 완전).
  bool get responseComplete => wageDay?['complete'] == true;

  /// 일괄 처리 가능 판정을 보류해야 하는 이유. 비어 있을 때만 '보류 사유 없음' — 그래도 처리 가능 **보증은 아니다**
  /// (adminConfirmed 등 근태 전제는 [attendance] 가 따로 말한다).
  List<String> get batchHoldReasons => [
        if (wageDay == null) 'noCandidateResponse',
        if (wageDay != null && !responseComplete) 'responseIncomplete',
        if (!attendance.isComplete) 'attendanceClassificationIncomplete',
        if (rows.values.any((r) => r.link != CandidateLink.linked)) 'rowNotLinked',
      ];
}

/// [wire] = callable 응답 원문(JSON decode 결과). 재수화는 production `_cfHydrate`(cfHydrateResponse)를 그대로 쓴다.
CandidateWageDay consumeCandidateWageDay(Map<String, dynamic> wire, {required String businessId, required DateTime civilDay}) {
  final h = cfHydrateResponse(wire);
  final items = (h['items'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
  final bare = items.map((e) => Map<String, dynamic>.from(e)..remove('wageApplication')..remove('wageWorkDetail')).toList();
  final attendance = WageDayInputsAdapter.classify(
      items: bare, limitReached: h['limitReached'] as bool, businessId: businessId, civilDay: civilDay);
  final rows = <String, CandidateRow>{};
  for (final it in items) {
    final id = it['id'] as String;
    final rawApp = it['wageApplication'];
    if (rawApp is! Map) {
      rows[id] = CandidateRow(id, CandidateLink.none);
      continue;
    }
    final attMap = Map<String, dynamic>.from(it)..remove('wageApplication')..remove('wageWorkDetail')..remove('id');
    attMap['status'] = AttendanceModel.displayStatusOfRaw(attMap['status']);
    final att = AttendanceModel.tryFromMap(attMap, id);
    final pa = Map<String, dynamic>.from(rawApp);
    final envelopeId = pa.remove('applicationId');
    final app = envelopeId is String ? ApplicationModel.tryFromMap(pa, envelopeId) : null;
    if (att == null || app == null) {
      rows[id] = CandidateRow(id, CandidateLink.unparsed);
      continue;
    }
    final related = envelopeId == att.applicationId &&
        app.uid == att.userId &&
        app.businessId == businessId &&
        att.businessId == businessId &&
        FormatHelper.toKstDate(app.workDate) == FormatHelper.toKstDate(att.workDate);
    if (!related) {
      rows[id] = CandidateRow(id, CandidateLink.relationMismatch, application: app);
      continue;
    }
    // 서버가 **이 지원서에** 붙인 업무 projection 을 그 지원서의 workDetailId 키로만 둔다(전역 cache·이름 추정 없음).
    //   기존 resolve 는 composite → workDetailId → workType 순으로 찾는다 — 여기서는 두 번째 단계가 이 projection 을 집는다.
    final wd = it['wageWorkDetail'];
    final wid = app.workDetailId;
    final timeMap = <String, dynamic>{
      if (wd is Map && wid != null && wid.isNotEmpty) wid: Map<String, dynamic>.from(wd),
    };
    final live = WorkDetailHelper.resolveLive(app, timeMap);
    rows[id] = live == null
        ? CandidateRow(id, CandidateLink.liveMissing, application: app)
        : CandidateRow(id, CandidateLink.linked, application: app, resolved: WorkDetailHelper.resolve(app, timeMap));
  }
  final wd = h['wageDay'];
  return CandidateWageDay(attendance: attendance, wageDay: wd is Map ? Map<String, dynamic>.from(wd) : null, rows: rows);
}

/// 후보 응답 read — **필수 주입**(기본 네트워크 구현 없음). 인자는 callable data 와 같은 모양의 요청 map.
typedef WageDayCandidateRead = Future<Map<String, dynamic>> Function(Map<String, dynamic> request);

/// [DU1 후속21 §1.1] 격리 loader — 주입 read 에 정확한 KST 일자 요청을 한 번 보내고 그 응답을 [consumeCandidateWageDay] 로 소비한다.
///   read 오류는 **그대로 던진다**(명시적 로드 실패) — 빈 결과·정상 0 으로 바꾸지 않는다.
class WageDayCandidateLoader {
  const WageDayCandidateLoader._();

  /// 주입 read 에 보낼 요청 — 창은 기존 [WageDayInputsAdapter.queryWindow](달력일 → KST 하루)를 그대로 쓴다.
  static Map<String, dynamic> requestFor({required String businessId, required DateTime civilDay}) {
    final w = WageDayInputsAdapter.queryWindow(civilDay);
    return {'purpose': 'wageDay', 'businessId': businessId, 'startMs': w.startMs, 'endMs': w.endMs};
  }

  static Future<CandidateWageDay> load({
    required WageDayCandidateRead read,
    required String businessId,
    required DateTime civilDay,
  }) async {
    final raw = await read(requestFor(businessId: businessId, civilDay: civilDay));
    return consumeCandidateWageDay(raw, businessId: businessId, civilDay: civilDay);
  }
}
