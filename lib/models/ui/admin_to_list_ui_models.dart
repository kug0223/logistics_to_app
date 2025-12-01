import '../core/to_model.dart';
import '../core/work_detail_model.dart';

/// 그룹 아이템 (대표 TO + 연결된 TO들)
class TOGroupItem {
  final TOModel masterTO;
  final bool isGrouped;
  
  // ✨ Lazy Loading 지원
  List<TOItem>? _groupTOs;  // nullable - 필요할 때 로드
  bool isGroupDetailLoaded;  // 그룹 상세(개별 TO 목록) 로드 여부

  TOGroupItem({
    required this.masterTO,
    List<TOItem>? groupTOs,
    required this.isGrouped,
    this.isGroupDetailLoaded = false,
  }) : _groupTOs = groupTOs;
  
  // Getter
  List<TOItem> get groupTOs => _groupTOs ?? [];
  
  // 그룹 상세 설정 (로드 후 호출)
  void setGroupTOs(List<TOItem> items) {
    _groupTOs = items;
    isGroupDetailLoaded = true;
  }
  
  // 로드 필요 여부
  bool get needsGroupDetailLoad => isGrouped && !isGroupDetailLoaded;
}

/// TO 아이템 (TO + WorkDetails + 통계)
class TOItem {
  final TOModel to;
  
  // ✨ Lazy Loading 지원
  List<WorkDetailModel>? _workDetails;  // nullable - 필요할 때 로드
  bool isWorkDetailLoaded;  // 업무 상세 로드 여부
  
  // 통계 (겉 카드용 - TO 문서에서 가져옴)
  final int confirmedCount;
  final int pendingCount;
  final int totalRequired;
  
  // 업무별 통계 (펼쳤을 때 로드)
  Map<String, Map<String, int>>? workDetailStats;

  TOItem({
    required this.to,
    List<WorkDetailModel>? workDetails,
    required this.confirmedCount,
    required this.pendingCount,
    required this.totalRequired,
    this.workDetailStats,
    this.isWorkDetailLoaded = false,
  }) : _workDetails = workDetails;
  
  // Getter
  List<WorkDetailModel> get workDetails => _workDetails ?? [];
  
  // 업무 상세 설정 (로드 후 호출)
  void setWorkDetails(List<WorkDetailModel> details, Map<String, Map<String, int>> stats) {
    _workDetails = details;
    workDetailStats = stats;
    isWorkDetailLoaded = true;
  }
  
  // 로드 필요 여부
  bool get needsWorkDetailLoad => !isWorkDetailLoaded;
}