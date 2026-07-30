import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/ui/admin_to_list_ui_models.dart';
import '../models/core/to_model.dart';
import '../models/core/work_detail_data.dart';
import '../providers/user_provider.dart';
import '../services/firestore_service.dart';
import '../utils/close_state_utils.dart';

/// 리스트·캘린더 뷰가 공유하는 단일 데이터 소스
///
/// 두 뷰는 이 컨트롤러의 [items]를 읽기만 한다.
/// 수정·삭제·확정 등 모든 데이터 변경 후에는 [reload]를 호출하면
/// 두 뷰가 동시에 갱신된다.
class WorkforceController extends ChangeNotifier {
  final FirestoreService _service = FirestoreService();

  List<TOGroupItem> _items = [];
  bool _isLoading = false;
  bool _disposed = false;
  final Set<String> _loadingGroupIds = {};

  List<TOGroupItem> get items => _items;
  bool get isLoading => _isLoading;
  bool isGroupLoading(String groupId) => _loadingGroupIds.contains(groupId);

  // ── 공고 카운트 ───────────────────────────────────────────────
  // SUPER_ADMIN이 settings/app_config.maxActiveTOPerBusiness로 동적 설정.
  // load() 시 Firestore에서 읽어온 값으로 갱신되며, 로드 전에는 기본값 4 사용.
  int _maxActiveTOs = 4;
  int get maxActiveTOs => _maxActiveTOs;

  /// 현재 진행중(active) 공고 수
  int get activeToCount => _items.where((g) => !g.isClosed).length;

  // ── 필터 상태 ─────────────────────────────────────────────────
  DateTimeRange? _selectedDateRange;
  String? _selectedBusiness;
  String? _selectedTOType;
  String? _selectedPublishStatus;

  DateTimeRange? get selectedDateRange => _selectedDateRange;
  String? get selectedBusiness => _selectedBusiness;
  String? get selectedTOType => _selectedTOType;
  String? get selectedPublishStatus => _selectedPublishStatus;

  bool get hasActiveFilters =>
      _selectedBusiness != null ||
      _selectedDateRange != null ||
      _selectedTOType != null ||
      _selectedPublishStatus != null;

  int get activeFilterCount {
    int count = 0;
    if (_selectedBusiness != null) count++;
    if (_selectedDateRange != null) count++;
    if (_selectedTOType != null) count++;
    if (_selectedPublishStatus != null) count++;
    return count;
  }

  void setBusinessFilter(String? value) {
    _selectedBusiness = value;
    notifyListeners();
  }

  void setDateRangeFilter(DateTimeRange? value) {
    _selectedDateRange = value;
    notifyListeners();
  }

  void setTOTypeFilter(String? value) {
    _selectedTOType = value;
    notifyListeners();
  }

  void setPublishStatusFilter(String? value) {
    _selectedPublishStatus = value;
    notifyListeners();
  }

  // ── 필터 다이얼로그 콜백 (WorkforceListView에서 등록) ──────────
  VoidCallback? _showFilterCallback;

  void registerShowFilterCallback(VoidCallback cb) => _showFilterCallback = cb;
  void unregisterShowFilterCallback() => _showFilterCallback = null;
  void requestShowFilter() => _showFilterCallback?.call();

  // ── 초기 로드 / 재로드 ────────────────────────────────────

  /// [context]는 첫 번째 await 이전에 uid/role 추출에만 사용됩니다.
  /// async gap 이후 context 재사용 없으므로 mounted 체크가 불필요합니다.
  Future<void> load(BuildContext context) async {
    if (_isLoading) return;
    _service.invalidateListCache();
    _isLoading = true;
    notifyListeners();

    try {
      // context는 첫 번째 await 이전에 추출 — async gap 이후 재사용 금지
      final user = Provider.of<UserProvider>(context, listen: false).currentUser;
      if (user == null) {
        _items = [];
        return;
      }

      // businessIds를 먼저 동기적으로 결정 (await 불필요)
      final List<String>? businessIds;
      if (user.isSuperAdmin) {
        businessIds = null;
      } else if (user.isSubAdmin) {
        businessIds = user.subAdminBusinessIds;
      } else {
        businessIds = user.managedBusinessIds;
      }

      if (businessIds != null && businessIds.isEmpty) {
        // 아이템은 없지만 한도는 로드
        _maxActiveTOs = await _service.getMaxActiveTOLimit(adminUID: user.uid);
        _items = [];
        // early return 하지 않고 finally + 후처리(_preload 등)가 실행되도록 통과
      } else {
      // 두 호출은 서로 독립 — 동시에 실행
      final limitFuture = _service.getMaxActiveTOLimit(adminUID: user.uid);
      final itemsFuture = _service.getTOGroupItemsLight(
        activeOnly: false,
        closedOnly: false,
        businessIds: businessIds,
      );
      _maxActiveTOs = await limitFuture;
      _items = await itemsFuture;
      // flex TO 슬롯 날짜 일괄 로드 (캘린더 날짜 필터링용)
      final flexIds =
          _items.where((g) => g.masterTO.isFlexType).map((g) => g.id).toList();
      if (flexIds.isNotEmpty) {
        // Firestore whereIn 30개 제한 대응 — 청크 분할 병렬 처리
        const chunkSize = 30;
        final allDatesMap = <String, List<DateTime>>{};
        final chunks = <List<String>>[];
        for (int i = 0; i < flexIds.length; i += chunkSize) {
          chunks.add(flexIds.sublist(
              i, i + chunkSize > flexIds.length ? flexIds.length : i + chunkSize));
        }
        final results = await Future.wait(
          chunks.map((chunk) => _service.getFlexTOSlotDates(chunk)),
        );
        for (final map in results) {
          allDatesMap.addAll(map);
        }
        for (final group in _items) {
          final dates = allDatesMap[group.id];
          if (dates != null) group.setSlotDates(dates);
        }
      }
      } // else 블록 닫힘
    } catch (e) {
      debugPrint('❌ WorkforceController.load 실패: $e');
      _items = [];
    } finally {
      _isLoading = false;
      if (!_disposed) notifyListeners();
    }

    // flex TO 슬롯 데이터를 백그라운드에서 사전 로드
    // → collapsed 상태에서도 slot.workDetails 기반 마감 판단 가능
    _preloadFlexTOSlots();

    // contract TO 게시 만료 자동 마감
    _maybeCascadeCloseExpiredContractTOs();
  }

  /// flex TO 슬롯 목록을 백그라운드에서 모두 로드
  /// 로딩 인디케이터 없이 조용히 실행, 완료마다 UI 갱신
  void _preloadFlexTOSlots() {
    for (final group in _items.where(
        (g) => g.masterTO.isFlexType && !g.isGroupDetailLoaded)) {
      if (_loadingGroupIds.contains(group.id)) continue;
      _loadingGroupIds.add(group.id);
      _service
          .loadGroupTOsLight(group.id, masterTO: group.masterTO)
          .then((toItems) {
        if (_disposed) return;
        group.setGroupTOs(toItems);
        // slotDates도 동기화 — groupTOs와 slotDates 불일치 방지
        group.setSlotDates(toItems.map((t) => t.slotDate).whereType<DateTime>().toList());
        notifyListeners();

        // 모든 슬롯이 만료됐는데 TO가 여전히 ACTIVE면 Firestore cascade close
        _maybeCascadeCloseExpiredTO(group, toItems);
      }).whenComplete(() {
        _loadingGroupIds.remove(group.id);
      }).catchError((e) {
        debugPrint('❌ 슬롯 사전로드 실패 ${group.id}: $e');
      });
    }
  }

  /// 모든 슬롯이 시간만료 + TO가 ACTIVE 상태인 경우 자동 cascade close
  ///
  /// ⚠️ F-074: markTOAsExpired 실패 시 Firestore 미갱신 — 낙관적 갱신 설계 (fire-and-forget).
  /// UI는 로컬 isClosed 기준으로 이미 닫힘 처리하므로 사용자 체감 영향 없음. 다음 reload 시 재시도됨.
  void _maybeCascadeCloseExpiredTO(TOGroupItem group, List<TOItem> toItems) {
    final to = group.masterTO;
    if (to.isClosed) return; // 이미 닫힘
    if (to.status == TOStatus.scheduled) return; // 미공개 예약 TO — 건드리지 않음
    if (toItems.isEmpty) return;

    final now = DateTime.now();
    final allExpired = toItems.every(
      (toItem) => CloseStateUtils.isToItemClosed(toItem, to, now),
    );

    if (!allExpired) return;

    // 모두 만료 → Firestore TO 상태를 CLOSED로 업데이트 (cascade)
    _service.markTOAsExpired(to.id).then((_) {
      if (_disposed) return;
      debugPrint('✅ 시간만료 TO 자동 마감: ${to.id}');
      // 다음 reload 시 CLOSED 탭으로 이동됨
    }).catchError((e) {
      debugPrint('❌ 시간만료 TO 자동마감 실패: $e');
    });
  }

  /// contract TO 게시 만료 → Firestore status 동기화
  /// TOModel.isClosed가 이미 런타임 마감으로 판단하지만,
  /// Firestore status가 ACTIVE인 채로 남으면 다른 클라이언트(유저 앱)에 노출되므로
  /// Firestore도 명시적으로 CLOSED로 업데이트한다.
  void _maybeCascadeCloseExpiredContractTOs() {
    for (final group in _items) {
      final to = group.masterTO;
      if (!to.isContractType) continue;
      // Firestore status 기준으로 체크 — isClosed는 이미 isPostingExpired를 포함하므로
      // 'status가 아직 ACTIVE인 것'만 대상으로 Firestore 업데이트
      if (TOStatus.closedStates.contains(to.status)) continue;
      if (to.status == TOStatus.scheduled) continue;
      if (to.status == TOStatus.draft) continue; // 미공개 TO는 만료 처리 대상 아님
      if (!to.isPostingExpired && !to.isDeadlinePassed) continue;

      _service.markTOAsExpired(to.id).then((_) {
        if (_disposed) return;
        debugPrint('✅ 게시만료 고정TO Firestore 동기화: ${to.id}');
      }).catchError((e) {
        debugPrint('❌ 게시만료 고정TO Firestore 동기화 실패: $e');
      });
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
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
      group.setSlotDates(toItems.map((t) => t.slotDate).whereType<DateTime>().toList());
    } catch (e) {
      debugPrint('❌ WorkforceController.loadGroupDetails 실패: $e');
    } finally {
      _loadingGroupIds.remove(group.id);
      if (!_disposed) notifyListeners();
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
      // 데이터 초기화 후 applicationDeadline은 항상 저장되어 있으므로 backfill 불필요
      final workDetails = result['workDetails'] as List<WorkDetailData>;

      slot.setWorkDetails(
        workDetails,
        result['workStats'] as Map<String, Map<String, int>>,
      );
      if (!_disposed) notifyListeners();
    } catch (e) {
      debugPrint('❌ WorkforceController.loadWorkDetails 실패: $e');
    }
  }
}
