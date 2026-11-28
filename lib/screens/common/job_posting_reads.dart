import '../../models/core/application_model.dart';
import '../../models/core/business_model.dart';
import '../../models/core/slot_model.dart';
import '../../models/core/to_model.dart';
import '../../models/core/work_detail_model.dart';
import '../../services/firestore_service.dart';
import '../../services/tax_identity_service.dart';
import '../../services/work_type_guide_resolver.dart';

/// [R7-P2-2 후속 P22-D] 공고 상세가 **화면을 만들 때** 나가는 읽기 경계.
///
/// 이 화면의 판정 근거는 **목적지의 재조회**다 — 카드가 넘긴 `to`·`workDetails`
/// 는 첫 화면 seed 일 뿐이고, 날짜·정원·마감은 여기서 다시 읽은 값이 만든다.
/// 그 계약을 실제로 확인하려면 재조회 결과를 seed 와 다르게 줄 수 있어야 한다.
///
/// 지원·취소(쓰기)는 이 경계에 넣지 않는다 — 읽기만 갈아끼운다.
class JobPostingReads {
  const JobPostingReads({
    required this.toOrFailure,
    required this.workDetails,
    required this.businessById,
    required this.slots,
    required this.myApplications,
    required this.workTypeCatalog,
    required this.applicationOnce,
    this.taxStatus = TaxIdentityService.loadStatus,
    this.now = DateTime.now,
  });

  final Future<({TOModel? to, bool failed})> Function(String toId) toOrFailure;
  final Future<List<WorkDetailModel>> Function(String toId) workDetails;
  final Future<BusinessModel?> Function(String businessId) businessById;

  /// 슬롯은 **상한 초과·권한·네트워크 실패를 throw** 로 알린다 —
  /// 화면이 `근무 날짜 없음` 과 구분해서 그리기 위해서다.
  final Future<List<SlotModel>> Function(String toId, {bool visibleOnly}) slots;

  final Future<List<ApplicationModel>> Function(String uid) myApplications;
  /// [WORKTYPE-IDENTITY] 업무 안내 원천 — 비활성 포함 전체. 새 공고 선택 목록이 아니다.
  final Future<WorkTypeCatalog> Function(String businessId) workTypeCatalog;
  final Future<ApplicationModel?> Function(String applicationId) applicationOnce;

  /// [R8-PERCEIVED.1] 지원 문턱의 세무 축 — 지원 버튼을 누르면 맨 먼저 이 값을 기다린다.
  ///   읽기 경계에 두어 그 대기를 재현·측정할 수 있게 한다. 실패는 throw 하지 않고
  ///   `TaxIdentityStatus.unknown()` 으로 돌아온다(서비스 계약 그대로).
  final Future<TaxIdentityStatus> Function() taxStatus;

  /// 먼저 받아 둔 세무 값의 나이를 재는 시계(테스트가 60초 경과를 만들 수 있게).
  final DateTime Function() now;

  factory JobPostingReads.of([FirestoreService? service]) {
    final svc = service ?? FirestoreService();
    return JobPostingReads(
      toOrFailure: svc.getTOOrFailure,
      workDetails: svc.getWorkDetails,
      businessById: svc.getBusinessById,
      slots: (toId, {bool visibleOnly = true}) =>
          svc.getSlots(toId, visibleOnly: visibleOnly),
      myApplications: svc.getMyApplications,
      // [L33] 업무 안내 원천은 사업장 단위 기준 정보 — 짧은 TTL 로 공고 상세 재진입마다 다시 읽지 않는다.
      workTypeCatalog: WorkTypeCatalogTtlCache.shared.wrap(svc.getBusinessWorkTypeCatalog),
      applicationOnce: svc.getApplicationOnce,
    );
  }
}

/// [L33 · 탭 분석 §3-7] 공고 상세의 업무 안내 원천(catalog) TTL 캐시 — 사업장 id 단위.
///
///   catalog 는 사업장의 업무 유형 기준 정보다(지원 가능 여부·정원·임금 판정에 쓰지 않는다 — 아이콘·안내 연결만).
///   같은 사업장 공고를 연달아 열 때마다 workTypes 를 페이지로 다시 읽던 것을 [ttl] 안에서는 재사용한다.
///   · 성공한 결과만 담는다 — 실패는 담지 않아 다음 진입에서 다시 읽는다.
///   · 같은 사업장 조회가 날아가 있으면 그 응답을 함께 받는다(in-flight 1).
///   · 사업장이 업무 유형을 바꾸면 최대 [ttl] 동안 옛 안내가 보일 수 있다(판정 영향 0).
class WorkTypeCatalogTtlCache {
  WorkTypeCatalogTtlCache({this.ttl = const Duration(minutes: 5), DateTime Function()? now})
      : _now = now ?? DateTime.now;

  static final WorkTypeCatalogTtlCache shared = WorkTypeCatalogTtlCache();

  final Duration ttl;
  final DateTime Function() _now;
  final Map<String, ({WorkTypeCatalog value, DateTime at})> _hits = {};
  final Map<String, Future<WorkTypeCatalog>> _inFlight = {};

  Future<WorkTypeCatalog> Function(String businessId) wrap(
          Future<WorkTypeCatalog> Function(String businessId) load) =>
      (businessId) => get(businessId, load);

  Future<WorkTypeCatalog> get(
      String businessId, Future<WorkTypeCatalog> Function(String businessId) load) {
    final hit = _hits[businessId];
    if (hit != null && _now().difference(hit.at) < ttl) return Future.value(hit.value);
    final flying = _inFlight[businessId];
    if (flying != null) return flying;
    final request = load(businessId).then((v) {
      _hits[businessId] = (value: v, at: _now());
      return v;
    });
    _inFlight[businessId] = request;
    void release() {
      if (identical(_inFlight[businessId], request)) _inFlight.remove(businessId);
    }
    request.then<void>((_) => release(), onError: (Object _) => release());
    return request;
  }

  void clear() {
    _hits.clear();
    _inFlight.clear();
  }
}
