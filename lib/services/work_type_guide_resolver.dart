import '../models/core/business_work_type_model.dart';

/// [WORKTYPE-IDENTITY] 사업장 업무유형 **전체**(비활성 포함) — 기존 공고·일정이 최신 안내를 읽는 원천.
///
/// 새 공고의 선택 목록(`getBusinessWorkTypes`, 활성만)과 다르다. 비활성화는 새 공고에서 고를 수
/// 없게 할 뿐이고, 이미 그 업무로 만든 공고와 근무는 계속 같은 업무의 안내를 본다.
class WorkTypeCatalog {
  /// 이 목록을 읽은 사업장(businesses/{businessId}/workTypes).
  final String businessId;

  /// 읽을 수 있었던 문서 — id → 모델.
  final Map<String, BusinessWorkTypeModel> byId;

  /// 이름별 문서 수 — 파싱에 실패한 문서까지 센다(유일성 판정이 그 문서를 빠뜨리지 않게).
  final Map<String, int> nameCounts;

  /// 전체를 끝까지 읽었는가. false 면(상한 도달 등) 이름 유일성을 **모른다** — 레거시 연결 금지.
  final bool complete;

  const WorkTypeCatalog({
    required this.businessId,
    required this.byId,
    required this.nameCounts,
    required this.complete,
  });

  static const empty =
      WorkTypeCatalog(businessId: '', byId: {}, nameCounts: {}, complete: false);

  /// 페이지를 끝까지 읽어 목록을 만든다. 한 페이지라도 실패하면 그대로 던진다(일부만 읽은 목록으로
  ///   유일성을 판정하지 않는다). [maxDocs] 에 닿았는데 더 있을 수 있으면 `complete:false`.
  /// [fetchPage] 는 문서 id 오름차순으로 [afterId] 다음부터 [pageSize] 개를 돌려준다.
  static Future<WorkTypeCatalog> load({
    required String businessId,
    required Future<List<(String, Map<String, dynamic>)>> Function(String? afterId, int pageSize) fetchPage,
    int pageSize = 200,
    int maxDocs = 1000,
  }) async {
    final byId = <String, BusinessWorkTypeModel>{};
    final nameCounts = <String, int>{};
    String? after;
    var read = 0;
    var complete = true;
    while (true) {
      final page = await fetchPage(after, pageSize);
      for (final (id, data) in page) {
        final name = data['name'];
        if (name is String) nameCounts[name] = (nameCounts[name] ?? 0) + 1;
        final m = BusinessWorkTypeModel.tryFromMap(data, id);
        if (m != null) byId[id] = m;
      }
      read += page.length;
      if (page.length < pageSize) break;
      if (read >= maxDocs) {
        complete = false;
        break;
      }
      after = page.last.$1;
    }
    return WorkTypeCatalog(
        businessId: businessId, byId: byId, nameCounts: nameCounts, complete: complete);
  }
}

/// 근무(공고·슬롯 workDetails 의 한 칸)에 붙일 업무 안내를 고른다. **유일한 판정 지점.**
///
/// 확인하지 못한 것은 연결하지 않는다 — 다른 업무의 안내를 붙이느니 안내를 숨긴다.
/// 업무명·임금·시간은 근무 저장본이라 이 판정과 무관하게 그대로 보인다.
///
/// · workTypeId 가 있으면 그 문서만. 목록이 이 근무의 사업장 것이고 문서의 businessId 가 다르지
///   않아야 한다. 이름이 같은 다른 문서는 보지 않는다. 문서가 없으면(삭제) null.
/// · 레거시(workTypeId 없음)는 아래가 **모두** 참일 때만 연결한다:
///     1) 목록을 끝까지 읽었다(상한·일부 실패 없음)
///     2) 공고 문서에 createdAt 이 실제로 저장돼 있다(화면 모델의 '현재 시각' 기본값은 쓰지 않는다)
///     3) 그 이름의 문서가 사업장 전체(비활성·파싱 실패 포함)에 정확히 하나
///     4) 그 문서가 공고보다 먼저(같거나 이전) 만들어졌다
///   남는 한계: 정책 이전의 이름 바꾸기(두 문서가 이름을 맞바꾼 경우)는 기록이 없어 구별할 수 없다.
class WorkTypeGuideResolver {
  static BusinessWorkTypeModel? resolve({
    required String? workTypeId,
    required String workTypeName,
    required WorkTypeCatalog catalog,
    required String businessId,
    required DateTime? postedAt,
  }) {
    if (businessId.isEmpty || catalog.businessId != businessId) return null;
    if (workTypeId != null) {
      final doc = catalog.byId[workTypeId];
      if (doc == null) return null;
      if (doc.businessId.isNotEmpty && doc.businessId != businessId) return null;
      return doc;
    }
    if (!catalog.complete || postedAt == null) return null;
    if ((catalog.nameCounts[workTypeName] ?? 0) != 1) return null;
    final only = catalog.byId.values.where((w) => w.name == workTypeName).firstOrNull;
    if (only == null) return null;
    if (only.businessId.isNotEmpty && only.businessId != businessId) return null;
    if (only.createdAt.isAfter(postedAt)) return null;
    return only;
  }
}
