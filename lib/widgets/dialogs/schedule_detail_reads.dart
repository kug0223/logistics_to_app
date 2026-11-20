import '../../models/core/application_model.dart';
import '../../models/core/business_model.dart';
import '../../models/core/to_model.dart';
import '../../services/firestore_service.dart';
import '../../services/work_type_guide_resolver.dart';

/// [WORKTYPE-SCHEDULE-GUIDANCE] 근로자 일정 상세가 읽는 세 가지.
///
/// 화면이 FirestoreService 를 직접 만들던 자리를 주입 가능하게 했다 — 저장된 업무명과
/// 현재 업무유형 목록이 어긋날 때 무엇을 그리는지 렌더로 고정하기 위해서다.
/// 기본값은 기존 구현 그대로다.
class ScheduleDetailReads {
  final Future<BusinessModel?> Function(String businessId) businessById;
  final Future<TOModel?> Function(ApplicationModel application) toByApplication;
  /// [WORKTYPE-IDENTITY] 업무 안내 원천 — 비활성 포함 전체.
  final Future<WorkTypeCatalog> Function(String businessId) workTypeCatalog;

  const ScheduleDetailReads({
    required this.businessById,
    required this.toByApplication,
    required this.workTypeCatalog,
  });

  /// 기존 구현 — 제품 기본값.
  factory ScheduleDetailReads.of(FirestoreService svc) => ScheduleDetailReads(
        businessById: svc.getBusinessById,
        toByApplication: svc.getTOByApplication,
        workTypeCatalog: svc.getBusinessWorkTypeCatalog,
      );
}
