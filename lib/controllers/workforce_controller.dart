import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/ui/admin_to_list_ui_models.dart';
import '../models/core/work_detail_data.dart';
import '../providers/user_provider.dart';
import '../services/firestore_service.dart';

/// 리스트·캘린더 뷰가 공유하는 단일 데이터 소스
///
/// 두 뷰는 이 컨트롤러의 [items]를 읽기만 한다.
/// 수정·삭제·확정 등 모든 데이터 변경 후에는 [reload]를 호출하면
/// 두 뷰가 동시에 갱신된다.
class WorkforceController extends ChangeNotifier {
  final FirestoreService _service = FirestoreService();

  List<TOGroupItem> _items = [];
  bool _isLoading = false;
  final Set<String> _loadingGroupIds = {};

  List<TOGroupItem> get items => _items;
  bool get isLoading => _isLoading;
  bool isGroupLoading(String groupId) => _loadingGroupIds.contains(groupId);

  // ── 초기 로드 / 재로드 ────────────────────────────────────

  Future<void> load(BuildContext context) async {
    if (_isLoading) return;
    _service.invalidateListCache();
    _isLoading = true;
    notifyListeners();

    try {
      final user = Provider.of<UserProvider>(context, listen: false).currentUser;
      final List<String>? businessIds =
          (user?.isSuperAdmin == true) ? null : user?.managedBusinessIds;

      if (businessIds != null && businessIds.isEmpty) {
        _items = [];
        return;
      }

      _items = await _service.getTOGroupItemsLight(
        activeOnly: false,
        closedOnly: false,
        businessIds: businessIds,
      );

      // flex TO 슬롯 날짜 일괄 로드 (캘린더 날짜 필터링용)
      final flexIds =
          _items.where((g) => g.masterTO.isFlexType).map((g) => g.id).toList();
      if (flexIds.isNotEmpty) {
        final datesMap = await _service.getFlexTOSlotDates(flexIds);
        for (final group in _items) {
          final dates = datesMap[group.id];
          if (dates != null) group.setSlotDates(dates);
        }
      }
    } catch (e) {
      debugPrint('❌ WorkforceController.load 실패: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// 데이터 변경 후 호출 — 두 뷰가 동시 갱신된다
  Future<void> reload(BuildContext context) => load(context);

  // ── Lazy Loading ─────────────────────────────────────────

  /// flex TO의 슬롯 목록을 lazy load
  Future<void> loadGroupDetails(BuildContext context, TOGroupItem group) async {
    if (group.isGroupDetailLoaded || _loadingGroupIds.contains(group.id)) return;

    _loadingGroupIds.add(group.id);
    notifyListeners();

    try {
      final toItems =
          await _service.loadGroupTOsLight(group.id, masterTO: group.masterTO);
      group.setGroupTOs(toItems);
    } catch (e) {
      debugPrint('❌ WorkforceController.loadGroupDetails 실패: $e');
    } finally {
      _loadingGroupIds.remove(group.id);
      notifyListeners();
    }
  }

  /// 슬롯의 업무 상세를 lazy load
  Future<void> loadWorkDetails(TOItem slot) async {
    if (!slot.needsWorkDetailLoad) return;
    try {
      final result = await _service.loadTOWorkDetails(
        slot.to,
        slotId: slot.slot?.id,
        slotWorkDetails: slot.slot?.workDetails,
      );
      var workDetails = result['workDetails'] as List<WorkDetailData>;

      // Firestore에 applicationDeadline이 없는 기존 데이터 대응:
      // TO의 deadlineType 설정으로 런타임에 계산해서 채운다.
      final slotDate = slot.slot?.date;
      final to = slot.to;
      if (slotDate != null &&
          to.deadlineType == 'HOURS_BEFORE' &&
          (to.hoursBeforeStart ?? 0) > 0) {
        workDetails = workDetails.map((d) {
          if (d.applicationDeadline != null) return d;
          final parts = d.startTime.split(':');
          if (parts.length != 2) return d;
          final deadline = DateTime(
            slotDate.year, slotDate.month, slotDate.day,
            int.parse(parts[0]), int.parse(parts[1]),
          ).subtract(Duration(hours: to.hoursBeforeStart!));
          return d.copyWith(applicationDeadline: deadline);
        }).toList();
      }

      slot.setWorkDetails(
        workDetails,
        result['workStats'] as Map<String, Map<String, int>>,
      );
      notifyListeners();
    } catch (e) {
      debugPrint('❌ WorkforceController.loadWorkDetails 실패: $e');
    }
  }
}
