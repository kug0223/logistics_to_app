import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/ui/admin_to_list_ui_models.dart';
import '../models/core/to_model.dart';
import '../models/core/user_model.dart';
import '../models/core/work_detail_data.dart';
import '../providers/user_provider.dart';
import '../services/firestore_service.dart';
import '../utils/close_state_utils.dart';

/// [POSTING-V2-02B.2] mutation이 일어난 화면.
///
/// 자기 화면은 이미 성공 콜백으로 local refresh를 끝냈으므로,
/// global invalidation으로 자기 자신을 다시 갱신하지 않는다.
enum AdminMutationOrigin { home, jobs, workforce }

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

  // ── [POSTING-V2-01B] ERROR != EMPTY ─────────────────────────────────
  // 조회 실패를 '결과 0건'으로 커밋하지 않는다. 실패는 별도 상태로 남기고
  // items는 건드리지 않는다 — refresh 실패가 기존 목록을 지우면 그것도 empty다.
  //
  // 소비자 계약:
  //   isLoading == true                    → LOADING
  //   loadError != null && items.isEmpty   → ERROR (본문 전체)
  //   loadError != null && items.isNotEmpty→ 마지막 성공 데이터 + 실패 알림
  //   loadError == null && items.isEmpty   → 정상 EMPTY
  //   loadError == null && items.isNotEmpty→ SUCCESS
  Object? _loadError;
  final Set<String> _groupDetailErrorIds = {};

  /// 마지막 목록 조회 실패. 성공하면 반드시 null로 돌아간다.
  Object? get loadError => _loadError;

  // ── [POSTING-V2-03P.1] NOT LOADED != TRUE EMPTY ─────────────────────
  //
  // 생성 직후 상태(items=[] · isLoading=false · loadError=null)는 "성공적으로
  // 조회했는데 0건"과 글자 그대로 같았다. 그래서 첫 load가 시작되기 전 프레임이
  // ROOT_EMPTY로 그려졌고, 소비자는 "아직 안 불러왔다"를 말할 방법이 없었다.
  bool _hasLoadedOnce = false;
  bool _lastSuccessfulWasEmpty = false;

  /// canonical 공고 목록을 **한 번이라도 성공적으로** 받아본 적이 있는가.
  /// 실패만 한 첫 시도는 여기 포함되지 않는다.
  bool get hasLoadedOnce => _hasLoadedOnce;

  /// 마지막 **성공** 스냅샷이 0건이었는가.
  ///
  /// 이것이 필요한 이유: items가 0이라는 사실만으로는 "서버가 확인해 준 0건"과
  /// "회수 prune 직후 재조회 중이라 잠시 0"을 구분할 수 없다. 후자를
  /// ROOT_EMPTY로 확정하면 관리자에게 "공고가 없습니다"를 잘못 말하게 된다.
  bool get lastSuccessfulWasEmpty => _lastSuccessfulWasEmpty;

  // [POSTING-V2-03P.1] _loadError는 재시도 시작 시 지워진다(01B). 이전에는 그
  //   사이 본문이 통째로 LoadingWidget이었으므로 stale 데이터가 화면에 없었다.
  //   이제 새로고침 중에도 기존 카드를 유지하므로, 그 창 동안 실패로 낡아 있던
  //   데이터가 아무 표시 없이 최신인 것처럼 보인다. 재시도 결과가 나오기 전까지
  //   "아직 최신이 아니다"는 여전히 참이므로 그 사실을 따로 들고 있는다.
  bool _lastLoadFailed = false;

  /// 마지막으로 **끝난** 조회가 실패했는가. 재시도가 시작돼도 내려가지 않고,
  /// 다음 성공에서만 내려간다.
  bool get lastLoadFailed => _lastLoadFailed;

  /// 특정 공고의 슬롯/상세 조회가 실패한 상태인지 여부.
  bool hasGroupDetailError(String groupId) =>
      _groupDetailErrorIds.contains(groupId);

  // ── [POSTING-V2-02B.2] Cross-entry mutation invalidation ─────────────
  //
  // dataRevision은 **성공한 business mutation** 전용 신호다.
  //
  // 이전에는 reload()가 revision을 올렸는데, reload()는 FCM·앱 복귀·
  // 당겨서 새로고침·에러 재시도에서도 호출된다. 그래서 데이터가 바뀌지 않았는데도
  // 다른 탭이 로드됐고, FCM 1건이 Jobs·Workforce를 각각 두 번 로드시킬 수 있었다.
  // 세 화면 모두 자기 FCM 콜백과 자기 resume 옵저버를 이미 갖고 있어
  // 그 cross-sync는 처음부터 중복이었다.
  //
  // 이제 producer는 notifyDataChanged() 하나뿐이고, 서버 write 성공 이후에만 호출된다.
  // consumer는 load()로 갱신한다 — load()는 revision을 올리지 않으므로 루프가 없다.
  //
  // origin: mutation이 일어난 화면. 그 화면은 이미 자기 성공 콜백으로 갱신을
  // 끝냈으므로 자기 신호를 무시한다. Home full refresh는 2 callable + 약 4N query라
  // 자기 mutation마다 한 번 더 지불할 이유가 없다.
  static int _globalReloadCounter = 0;
  static final ValueNotifier<int> dataRevision = ValueNotifier<int>(0);
  static AdminMutationOrigin? _lastMutationOrigin;

  /// 가장 최근 [dataRevision] 증가를 유발한 화면.
  /// ValueNotifier는 동기 통지이므로 리스너는 자기 차례의 origin을 정확히 읽는다.
  static AdminMutationOrigin? get lastMutationOrigin => _lastMutationOrigin;

  /// 성공한 business mutation을 관련 화면에 알린다.
  ///
  /// 반드시 **서버 write 성공 이후**에만 호출한다.
  /// [origin] 화면은 이 신호를 무시하므로, 자기 local refresh는 따로 유지해야 한다.
  ///
  /// 모든 mutation에 호출하지 않는다 — 다른 화면의 truth가 실제로 바뀌는
  /// action에서만 호출한다. (예: 공고 탭 인력 초대는 Home staffing/summary를
  /// 바꾸지 않으므로 Posting local refresh만 하고 이 신호를 보내지 않는다)
  static void notifyDataChanged({required AdminMutationOrigin origin}) {
    _lastMutationOrigin = origin;
    dataRevision.value = ++_globalReloadCounter;
  }

  // 사업장 이름 캐시 — items가 0건이어도 마지막 성공 로드의 이름 유지 (scope chip용)
  List<String> _knownBusinessNames = [];

  /// 마지막 성공 로드에서 확보한 사업장 이름 목록.
  /// items가 비어 있어도 scope label 표시에 사용할 수 있다.
  List<String> get knownBusinessNames => List.unmodifiable(_knownBusinessNames);

  List<TOGroupItem> get items => _items;
  bool get isLoading => _isLoading;
  bool isGroupLoading(String groupId) => _loadingGroupIds.contains(groupId);

  // ── [POSTING-V2-02A.1] 공고 한도는 controller가 들고 있지 않는다 ──────
  // 이전에는 maxActiveTOs(+ activeToCount)를 load()에서 읽어 공고 탭이
  // '진행중 (N/max)'와 한도 초과 경고색을 그렸다. 그 두 값은 서버 quota와
  // 다른 모집단이었다 — 서버는 owner 전체 scope에서 ACTIVE+FULL을 세고
  // DRAFT/SCHEDULED를 빼는데, 클라이언트는 FULL을 빼고 DRAFT/SCHEDULED를
  // 포함하며 한도는 오너가 아닌 호출자 문서에서 읽었다.
  //
  // 한도의 canonical source는 서버 하나뿐이고, 실제로 작동하는 순간
  // (callableCreateTO / callablePublishTO / reopen)에 MAX_ACTIVE_TO_LIMIT로
  // 정확한 값을 돌려준다. 클라이언트가 미리 추정하지 않는다.
  // 탭 숫자는 WorkforceListView가 렌더 목록에서 직접 센다.

  // ── 필터 상태 ─────────────────────────────────────────────────
  DateTimeRange? _selectedDateRange;
  // [PATCH-IDENTITY] business filter semantic = businessId (not businessName).
  // 동명 사업장 충돌 방지: businessId로 비교해야 canonical identity 보장.
  String? _selectedBusinessId;
  String? _selectedTOType;
  String? _selectedPublishStatus;

  DateTimeRange? get selectedDateRange => _selectedDateRange;
  String? get selectedBusinessId => _selectedBusinessId;
  String? get selectedTOType => _selectedTOType;
  String? get selectedPublishStatus => _selectedPublishStatus;

  bool get hasActiveFilters =>
      _selectedBusinessId != null ||
      _selectedDateRange != null ||
      _selectedTOType != null ||
      _selectedPublishStatus != null;

  int get activeFilterCount {
    int count = 0;
    if (_selectedBusinessId != null) count++;
    if (_selectedDateRange != null) count++;
    if (_selectedTOType != null) count++;
    if (_selectedPublishStatus != null) count++;
    return count;
  }

  /// business filter setter — value는 businessId (businessName 아님).
  void setBusinessIdFilter(String? businessId) {
    _selectedBusinessId = businessId;
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

  /// [POSTING-V2-02E.1] 네 필터를 한 번에 해제한다 — 순수 편의 helper.
  ///
  /// setter를 연달아 호출하면 notifyListeners가 네 번 돌아 목록이 네 번
  /// 다시 그려진다. 같은 field를 null로 되돌린 뒤 한 번만 알린다.
  /// 새 filter model도, persisted state도, Firestore 접근도 없다 —
  /// 이미 로드된 items를 다시 거를 뿐이다.
  void clearFilters() {
    if (!hasActiveFilters) return;
    _selectedBusinessId = null;
    _selectedDateRange = null;
    _selectedTOType = null;
    _selectedPublishStatus = null;
    notifyListeners();
  }

  // ── 필터 다이얼로그 콜백 (WorkforceListView에서 등록) ──────────
  VoidCallback? _showFilterCallback;

  void registerShowFilterCallback(VoidCallback cb) => _showFilterCallback = cb;
  void unregisterShowFilterCallback() => _showFilterCallback = null;
  void requestShowFilter() => _showFilterCallback?.call();

  // ── 외부 reload 콜백 — FCM/lifecycle reload 시 WorkforceListView 확장 상태 초기화 ──
  VoidCallback? _onExternalReloadCallback;

  void registerOnExternalReload(VoidCallback cb) => _onExternalReloadCallback = cb;
  void unregisterOnExternalReload() => _onExternalReloadCallback = null;

  // ── 초기 로드 / 재로드 ────────────────────────────────────

  /// [POSTING-V2-03N.1] scope가 줄었을 때 서버가 돌려줄 수 있는 코드.
  ///
  /// 서버는 요청한 businessId마다 `assertBizAdmin`을 부르고, 두 가지로 거절한다.
  ///   · `permission-denied` — 사업장은 있는데 더 이상 내 것이 아니다(배정 회수,
  ///     SUPER_ADMIN의 adminIds 변경)
  ///   · `not-found` — 사업장 문서 자체가 없다(사업장 삭제).
  ///     `onBusinessDeleted` 트리거가 `managedBusinessIds`·`subAdminBusinessIds`
  ///     에서 그 id를 빼지만, 문서 삭제가 먼저이고 정리는 뒤따르므로
  ///     그 사이 stale scope가 삭제된 id를 계속 보낸다.
  ///
  /// **코드만으로 회수를 단정하지 않는다.** 아래 복구는 canonical scope를 다시
  /// 읽어 실제로 줄어든 것이 확인됐을 때만 캐시를 건드린다.
  static const _scopeShrinkCandidates = {'permission-denied', 'not-found'};

  /// Posting 목록 READ scope — 02G canonical.
  List<String>? _scopeOf(UserModel user) {
    if (user.isSuperAdmin) return null; // 서버가 전체를 조회한다
    if (user.isSubAdmin) return user.subAdminBusinessIds;
    return user.managedBusinessIds;
  }

  /// [POSTING-V2-03N.1] 권한 회수로 stale해진 scope에서 빠져나온다.
  ///
  /// 서버는 요청한 businessId를 **전부** 검증하고 하나라도 어긋나면 요청 전체를
  /// 거부한다(MODEL A). 그래서 배정이 회수된 사업장 하나가 목록에 남아 있으면
  /// 멀쩡한 사업장 공고까지 갱신되지 않는다. 선택하지 않은 사업장에는 realtime
  /// listener가 없어, 당겨서 새로고침이나 앱 복귀 전에는 그 사실을 알 수 없었다.
  ///
  /// 여기서 닫는다 — 모든 load 진입점이 이 한 곳을 지나므로 initState·FCM·
  /// cross-tab revision 어디서 들어와도 같은 계약이 적용된다.
  ///
  /// **정상 경로 비용은 0이다.** 성공하면 아무것도 더 하지 않고, 아래 복구는
  /// [_scopeShrinkCandidates]에서만 돈다. 네트워크·타임아웃 등 일시적 실패는
  /// 01B/03F의 기존 stale 계약 그대로 예외를 다시 던진다.
  Future<List<TOGroupItem>> _loadWithScopeRecovery({
    required UserProvider userProvider,
    required List<String>? requestedScope,
  }) async {
    try {
      return await _service.getTOGroupItemsLight(
        activeOnly: false,
        closedOnly: false,
        businessIds: requestedScope,
      );
    } on FirebaseFunctionsException catch (e) {
      if (!_scopeShrinkCandidates.contains(e.code) || requestedScope == null) {
        rethrow;
      }

      // canonical scope를 다시 읽는다. 실패하면 회수를 **확인하지 못한** 것이므로
      //   기존 데이터를 임의로 지우지 않고 원래 실패로 끝낸다.
      await userProvider.refreshAdminScopeState();
      final refreshed = userProvider.currentUser;
      if (refreshed == null) rethrow;
      final newScope = _scopeOf(refreshed);
      if (newScope == null) rethrow; // SUPER_ADMIN으로 바뀌는 경우는 없다

      final revoked =
          requestedScope.where((id) => !newScope.contains(id)).toSet();
      if (revoked.isEmpty) {
        // scope가 그대로다 — membership 회수라고 단정하지 않는다.
        //   다른 이유(전파 지연 등)일 수 있으므로 캐시를 건드리지 않는다.
        rethrow;
      }

      // 회수가 확인됐다. 재시도 성공 여부와 무관하게, 접근 권한이 사라진
      //   사업장의 데이터는 더 보여주지 않는다 — 이것은 network stale이 아니다.
      _pruneRevokedItems(revoked);

      if (newScope.isEmpty) {
        // 남은 scope가 없다 — 같은 실패를 다시 만들지 않는다.
        return [];
      }
      // 새 scope로 **정확히 한 번** 재시도한다. 여기서 또 실패하면 그대로 던진다.
      return _service.getTOGroupItemsLight(
        activeOnly: false,
        closedOnly: false,
        businessIds: newScope,
      );
    }
  }

  /// 접근 권한이 사라진 사업장의 캐시를 즉시 비운다.
  void _pruneRevokedItems(Set<String> revokedBusinessIds) {
    if (revokedBusinessIds.isEmpty) return;
    _items = _items
        .where((g) => !revokedBusinessIds.contains(g.businessId))
        .toList();
    _knownBusinessNames = _items
        .map((g) => g.businessName)
        .where((n) => n.isNotEmpty)
        .toSet()
        .toList();
    // 사라진 사업장을 가리키던 필터는 목록을 영원히 비워 둔다.
    if (_selectedBusinessId != null &&
        revokedBusinessIds.contains(_selectedBusinessId)) {
      _selectedBusinessId = null;
    }
  }

  // ── [POSTING-V2-03O.1] load coalescing ──────────────────────────────
  //
  // 이전에는 `if (_isLoading) return;`으로 두 번째 요청을 **버렸다**. 그래서
  // 진행 중인 load가 mutation보다 앞선 데이터를 들고 있어도, 그 mutation이
  // 유발한 reload가 사라지고 화면이 낡은 채로 고착될 수 있었다.
  // (같은 origin이면 revision self-skip 때문에 재시도도 오지 않는다)
  //
  // 이제 요청은 버리지 않는다. 진행 중이면 pending으로 접고, 현재 사이클이
  // 끝난 뒤 **한 번 더** 돈다. 여러 요청이 겹쳐도 follow-up은 하나로 합쳐진다.
  // 불변식: 요청이 들어왔는데 아무 fetch도 예정되지 않은 상태는 없다.
  Future<void>? _loadCycle;
  bool _pendingLoad = false;

  /// [context]는 동기적으로 UserProvider를 꺼내는 데만 쓴다.
  /// pending follow-up은 async gap 뒤에 돌므로 context를 들고 가지 않는다.
  Future<void> load(BuildContext context) {
    final userProvider = Provider.of<UserProvider>(context, listen: false);
    return _requestLoad(userProvider);
  }

  Future<void> _requestLoad(UserProvider userProvider) {
    final cycle = _loadCycle;
    if (cycle != null) {
      // 버리지 않는다 — 현재 사이클이 끝나면 최신 상태로 한 번 더 돈다.
      _pendingLoad = true;
      // caller가 await하면 follow-up까지 끝난 뒤 완료된다.
      return cycle;
    }
    final started = _runLoadCycle(userProvider);
    _loadCycle = started;
    return started;
  }

  /// pending이 남아 있는 한 순차로 반복한다.
  /// 순차이므로 오래된 결과가 최신 결과를 덮을 수 없다.
  Future<void> _runLoadCycle(UserProvider userProvider) async {
    try {
      do {
        _pendingLoad = false;
        // scope는 매 회차에 다시 계산된다 — pending 사이에 배정이 바뀌었어도
        //   첫 요청의 낡은 scope를 재사용하지 않는다(03N).
        await _runOneLoad(userProvider);
      } while (_pendingLoad);
    } finally {
      _loadCycle = null;
      // 회차가 예기치 않게 던져도 로딩 상태가 갇히지 않게 한다.
      if (_isLoading) {
        _isLoading = false;
        if (!_disposed) notifyListeners();
      }
    }

    // [POSTING-V2-01B] 실패한 로드의 stale items로 후처리를 돌리지 않는다.
    // 특히 cascade close는 write이므로 신뢰할 수 없는 상태에서 실행하지 않는다.
    if (_loadError != null) return;

    // [POSTING-V2-02D.1] 모든 슬롯이 만료됐는데 TO가 ACTIVE면 Firestore cascade close.
    //   write이므로 load 전체가 성공한 뒤에만 실행한다(01B: 신뢰할 수 없는
    //   상태에서 write 금지). 슬롯 로드에 실패한 그룹은 isGroupDetailLoaded가
    //   false로 남아 대상에서 빠진다 — '슬롯 없음'으로 오인해 마감하지 않는다.
    for (final group in _items.where(
        (g) => g.masterTO.isFlexType && g.isGroupDetailLoaded)) {
      _maybeCascadeCloseExpiredTO(group, group.groupTOs);
    }

    // contract TO 게시 만료 자동 마감
    _maybeCascadeCloseExpiredContractTOs();
  }

  /// 한 회차. 실패해도 던지지 않는다 — [_loadError]로 표현하고 pending을 살린다.
  Future<void> _runOneLoad(UserProvider userProvider) async {
    _service.invalidateListCache();
    _isLoading = true;
    // [POSTING-V2-01B] 새 시도 시작 — 이전 실패 상태를 먼저 지운다.
    // 성공으로 끝나면 그대로 null, 실패하면 catch에서 다시 채워진다.
    _loadError = null;
    notifyListeners();

    try {
      final user = userProvider.currentUser;
      if (user == null) {
        _items = [];
        // [POSTING-V2-03P.1] 사용자를 모르는 상태는 canonical 결과가 아니다 —
        //   hasLoadedOnce를 세우지 않는다.
        return;
      }

      // businessIds를 먼저 동기적으로 결정 (await 불필요)
      final List<String>? businessIds = _scopeOf(user);

      if (businessIds != null && businessIds.isEmpty) {
        _items = [];
        // early return 하지 않고 finally + 후처리(_preload 등)가 실행되도록 통과
      } else {
      // [POSTING-V2-02A.1] 한도 조회 제거 — 탭 표시 외에 소비자가 없었다
      _items = await _loadWithScopeRecovery(
        userProvider: userProvider,
        requestedScope: businessIds,
      );
      // [POSTING-V2-01B] items가 새 인스턴스로 교체되므로 이전 detail 실패도 무효.
      // 남겨두면 복구된 공고가 계속 error로 보인다.
      _groupDetailErrorIds.clear();
      // 사업장 이름 캐시 업데이트 — items 0건이어도 이전 캐시 유지
      final loadedNames = _items
          .map((g) => g.businessName)
          .where((n) => n.isNotEmpty)
          .toSet()
          .toList();
      if (loadedNames.isNotEmpty) _knownBusinessNames = loadedNames;
      // [POSTING-V2-02D.1] flex 슬롯을 TO당 정확히 한 번 읽는다.
      //
      // 이전에는 날짜용 query(getFlexTOSlotDates)와 전체 모델용 preload가
      // 같은 slots 컬렉션을 각각 읽어 TO당 2회였다. Dart SDK에 projection이
      // 없어 날짜용 query도 문서 전량을 받았으므로 절반이 순수 낭비였다.
      //
      // 첫 렌더 전에 await한다 — slotDates가 비어 있으면 모든 슬롯이 지난
      // flex 공고가 진행중 탭에 잘못 남는다(TOGroupItem.isClosed 폴백).
      final flexGroups =
          _items.where((g) => g.masterTO.isFlexType).toList();
      if (flexGroups.isNotEmpty) {
        await Future.wait(flexGroups.map((group) async {
          try {
            final loaded = await _service.loadFlexSlots(
              group.id,
              masterTO: group.masterTO,
            );
            group.setGroupTOs(loaded.groupTOs);
            // setGroupTOs 뒤에 둔다 — 최종 _slotDates는 raw snapshot 기준이어야
            // 모델 파싱에 실패한 슬롯의 날짜도 살아남는다.
            // ([POSTING-V2-03D.1 TC2] createdAt 결측은 더 이상 파싱 실패가 아니다)
            group.setSlotDates(loaded.slotDates);
          } catch (e) {
            // [POSTING-V2-01B] TO 하나의 실패가 목록 전체를 ERROR로 만들지 않는다.
            //   해당 그룹만 detail error로 표시하고 펼침 시 재시도 경로를 쓴다.
            debugPrint('❌ flex 슬롯 로드 실패 ${group.id}: $e');
            _groupDetailErrorIds.add(group.id);
          }
        }));
      }
      } // else 블록 닫힘
      // [POSTING-V2-03P.1] 여기 도달 = canonical 결과를 확보했다.
      //   (scope가 비어 0건인 경우도 "서버 기준 0건"이라는 확정된 답이다)
      _hasLoadedOnce = true;
      _lastSuccessfulWasEmpty = _items.isEmpty;
      _lastLoadFailed = false;
    } catch (e) {
      debugPrint('❌ WorkforceController.load 실패: $e');
      // [POSTING-V2-01B] _items = [] 금지.
      // 실패를 빈 결과로 커밋하면 '공고 0건'과 구분할 수 없고,
      // refresh 실패에서는 멀쩡하던 목록까지 사라진다.
      _loadError = e;
      _lastLoadFailed = true;
    } finally {
      // pending follow-up이 남아 있으면 곧바로 다음 회차가 이어지므로
      //   그 사이에 idle로 보이게 만들지 않는다.
      if (!_pendingLoad) _isLoading = false;
      if (!_disposed) notifyListeners();
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
    // [POSTING-V2-03E.1] 화면이 만료로 판단한 그 시점의 revision을 넘긴다.
    //   그 사이 다른 관리자가 공고를 수정했다면 이 자동 마감은 실패해야 한다.
    _service
        .markTOAsExpired(to.id, expectedEditRevision: to.editRevision)
        .then((_) {
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

      // [POSTING-V2-03E.1] 위와 동일 — stale revision이면 덮어쓰지 않는다.
      _service
          .markTOAsExpired(to.id, expectedEditRevision: to.editRevision)
          .then((_) {
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

  /// 이 controller만 다시 로드한다 — [POSTING-V2-02B.2] local only.
  ///
  /// 더 이상 dataRevision을 올리지 않는다. reload()는 mutation뿐 아니라
  /// FCM·앱 복귀·당겨서 새로고침·에러 재시도에서도 호출되므로,
  /// 여기서 전역 신호를 내보내면 데이터가 안 바뀐 경우까지 다른 탭을 로드시킨다.
  /// 다른 화면에 알려야 하는 mutation은 호출부가
  /// [notifyDataChanged]를 명시적으로 호출한다.
  Future<void> reload(BuildContext context) {
    _onExternalReloadCallback?.call();
    return load(context);
  }

  // ── Lazy Loading ─────────────────────────────────────────

  /// flex TO의 슬롯 목록을 lazy load
  Future<void> loadGroupDetails(BuildContext context, TOGroupItem group) async {
    if (group.isGroupDetailLoaded || _loadingGroupIds.contains(group.id)) return;

    _loadingGroupIds.add(group.id);
    // [POSTING-V2-01B] 재시도 시작 — 이전 실패 표시를 먼저 지운다
    _groupDetailErrorIds.remove(group.id);
    notifyListeners();

    try {
      // [POSTING-V2-02D.1] root load와 같은 single-snapshot loader를 쓴다.
      //   이전에는 slotDates를 toItems에서 파생했는데, 모델 파싱에 실패한
      //   슬롯의 날짜가 여기서 함께 사라졌다.
      //   ([POSTING-V2-03D.1 TC2] 그 원인이던 createdAt 필수 요구는 해소됐다)
      final loaded =
          await _service.loadFlexSlots(group.id, masterTO: group.masterTO);
      group.setGroupTOs(loaded.groupTOs);
      group.setSlotDates(loaded.slotDates);
    } catch (e) {
      debugPrint('❌ WorkforceController.loadGroupDetails 실패: $e');
      // [POSTING-V2-01B] 실패를 '슬롯 없음'으로 커밋하지 않는다.
      // setGroupTOs([])를 호출하지 않으므로 isGroupDetailLoaded도 false로 남는다.
      _groupDetailErrorIds.add(group.id);
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
        // [POSTING-V2-01B] 통계 조회 실패를 0으로 표시하지 않도록 전달
        statsFailed: result['statsFailed'] == true,
      );
      if (!_disposed) notifyListeners();
    } catch (e) {
      debugPrint('❌ WorkforceController.loadWorkDetails 실패: $e');
      // [POSTING-V2-01B] 실패를 '확정 0 / 대기 0'으로 커밋하지 않는다
      slot.markWorkDetailStatsFailed();
      if (!_disposed) notifyListeners();
    }
  }
}
