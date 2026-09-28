import '../../models/core/application_model.dart';
import '../../models/core/business_model.dart';
import '../../models/core/business_work_type_model.dart';
import '../../models/core/slot_model.dart';
import '../../models/core/to_model.dart';
import '../../models/core/work_detail_model.dart';
import '../../services/firestore_service.dart';

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
    required this.businessWorkTypes,
    required this.applicationOnce,
  });

  final Future<({TOModel? to, bool failed})> Function(String toId) toOrFailure;
  final Future<List<WorkDetailModel>> Function(String toId) workDetails;
  final Future<BusinessModel?> Function(String businessId) businessById;

  /// 슬롯은 **상한 초과·권한·네트워크 실패를 throw** 로 알린다 —
  /// 화면이 `근무 날짜 없음` 과 구분해서 그리기 위해서다.
  final Future<List<SlotModel>> Function(String toId, {bool visibleOnly}) slots;

  final Future<List<ApplicationModel>> Function(String uid) myApplications;
  final Future<List<BusinessWorkTypeModel>> Function(String businessId)
      businessWorkTypes;
  final Future<ApplicationModel?> Function(String applicationId) applicationOnce;

  factory JobPostingReads.of([FirestoreService? service]) {
    final svc = service ?? FirestoreService();
    return JobPostingReads(
      toOrFailure: svc.getTOOrFailure,
      workDetails: svc.getWorkDetails,
      businessById: svc.getBusinessById,
      slots: (toId, {bool visibleOnly = true}) =>
          svc.getSlots(toId, visibleOnly: visibleOnly),
      myApplications: svc.getMyApplications,
      businessWorkTypes: svc.getBusinessWorkTypes,
      applicationOnce: svc.getApplicationOnce,
    );
  }
}
