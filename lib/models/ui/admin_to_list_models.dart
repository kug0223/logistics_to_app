import '../core/to_model.dart';
import '../core/work_detail_model.dart';

/// 그룹 아이템 (대표 TO + 연결된 TO들)
class TOGroupItem {
  final TOModel masterTO;
  final List<TOItem> groupTOs;
  final bool isGrouped;

  TOGroupItem({
    required this.masterTO,
    required this.groupTOs,
    required this.isGrouped,
  });
}

/// TO 아이템 (TO + WorkDetails + 통계)
class TOItem {
  final TOModel to;
  final List<WorkDetailModel> workDetails;
  final int confirmedCount;
  final int pendingCount;
  final int totalRequired;
  final Map<String, Map<String, int>>? workDetailStats;

  TOItem({
    required this.to,
    required this.workDetails,
    required this.confirmedCount,
    required this.pendingCount,
    required this.totalRequired,
    this.workDetailStats,
  });
}