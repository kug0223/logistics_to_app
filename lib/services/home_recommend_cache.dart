import 'dart:convert';

import 'package:flutter/foundation.dart';

/// [PERF-P2 · 판정289 §6 C289-05] 홈 추천 카드 "마지막 성공" 표시 캐시 — **모듈만**(홈 통합은 P1 뒤 별도 셀).
///
/// ## 무엇을 담는가 (allowlist)
///   추천 카드 **최대 2장**의 공개 표시 문구뿐이다([HomeRecommendCard]). 원시 user/business 문서 ·
///   이미지/서명 URL · 계약/지원자 정보 · 지원 숫자 · 약속/퇴근/해지/초대/신분증 요청 · 정상 0 은 담지 않는다.
///   `_applications`·`_attendances`·`_contracts` 같은 홈 원천 목록에 넣지 않는다 — 표시 전용 경로로만 그린다
///   (재계산으로 약속·숫자가 간접 복원되지 않게).
///
/// ## 언제 쓰고 버리는가
///   · 저장: 이번 진입의 **신선한 성공** 결과가 1장 이상일 때만([saveSuccess]). 오류·부분·기본값은 저장 0.
///     최신 성공이 0장이면 옛 추천을 **지우고** 0장 스냅샷은 만들지 않는다.
///   · 읽기: uid · 범위([HomeRecommendScope]: 환경 · 역할 · 지역 · 조회 조건) · 스키마가 모두 같고,
///     저장 후 [ttl](24시간 · **잠정 최대 보관 시간**이지 24시간 동안 믿어도 된다는 뜻이 아님) 안이며,
///     시계가 거꾸로 가지 않았을 때만. 화면은 이 값을 "마지막 확인 HH:MM · 확인 중" 으로만 보이고
///     매 진입 즉시 live 로 다시 확인한다(지원·자격·정원은 서버가 다시 판정).
///   · 손상 · 만료 · 조건 변경 · 시계 역행 → 그 자리에서 지운다.
///   · 로그아웃(성공·실패 모두) · 계정/역할 전환 · 탈퇴 BEGIN/재개 → [invalidateAll]. 세대가 올라가
///     **그 전에 시작한 저장은 끝나도 쓰지 않거나 곧바로 지운다**(늦은 write 가 삭제 뒤 다시 만들지 못함).
///     삭제 실패는 세대 무효화로 다음 계정 표시를 막고, 성공으로 보고하지 않는다([invalidateAll] 의 반환값).
///
/// ## 저장 위치 — 지금은 RAM 만
///   디스크 저장 조건이 확인되지 않았다: AndroidManifest 에 `allowBackup`/`dataExtractionRules` 가 없어
///   Android 기본 자동 백업이 켜져 있고(SharedPreferences 포함), 백업 제외 · Play 데이터 안전 문서 delta 가
///   아직 없다. 그래서 기본 저장소는 [RamHomeRecommendStore] 다 — 앱을 다시 켜면 비어 있다(재시작 = 캐시 없음).
///   디스크 저장소는 [HomeRecommendStore] 를 구현해 넣을 수 있지만, 백업 제외 · 앱 전용 저장소 ·
///   정책 delta 가 확인되기 전에는 켜지 않는다.
class HomeRecommendCache {
  HomeRecommendCache({
    HomeRecommendStore? store,
    DateTime Function()? clock,
  })  : _store = store ?? RamHomeRecommendStore(),
        _clock = clock ?? DateTime.now;

  /// [impl_12] 앱 프로세스 하나의 공용 인스턴스(RAM) — 홈이 읽고 쓰고, UserProvider 가 로그아웃·전환·탈퇴에서 무효화한다.
  static final HomeRecommendCache shared = HomeRecommendCache();

  /// 담는 카드 최대 수 — 홈이 보이는 수와 같다.
  static const int maxCards = 2;

  /// 잠정 최대 보관 시간(판정289 §6).
  static const Duration ttl = Duration(hours: 24);

  /// 저장 모양 버전 — 바뀌면 옛 값을 버린다.
  static const int schemaVersion = 1;

  static const String _prefix = 'home_recommend_cache_v$schemaVersion:';

  final HomeRecommendStore _store;
  final DateTime Function() _clock;

  /// 무효화 세대 — 로그아웃·전환·탈퇴마다 올라간다.
  int _epoch = 0;

  /// [impl_12 · 판정291 C291-P2] 사용자별 폐기 세대 — `clear`·성공 0장마다 올라간다.
  final Map<String, int> _gen = {};

  /// [impl_12 · C291-P2] 사용자별 저장 순번 — 나중에 시작한 저장만 유효하다.
  final Map<String, int> _saveSeq = {};

  /// [impl_12 · 판정291 C291-P2] 키에 **세대를 넣는다**(namespace). 무효화·폐기가 삭제에 실패해도 다음 읽기는
  ///   새 세대 키를 보므로 옛 값에 닿지 않는다 — 실패 삭제 뒤 같은 uid 재로그인 · 같은 범위 재읽기 보호.
  ///   (RAM 저장소라 세대가 재시작에 초기화돼도 값도 같이 사라진다. 디스크 저장을 켤 때는 세대 영속이 선행 조건.)
  String _key(String uid) => '${_prefix}e$_epoch:g${_gen[uid] ?? 0}:$uid';

  @visibleForTesting
  String debugKey(String uid) => _key(uid);

  /// [impl_12] 현재 세대 키의 마지막 **확인된** 스냅샷(동기 거울). 저장 성공·읽기 성공 때만 채우고,
  ///   폐기·무효화·만료·조건 불일치면 비운다 — 홈 첫 프레임이 기다리지 않고 [peek] 할 수 있게.
  final Map<String, HomeRecommendSnapshot> _mirror = {};

  bool _usable(HomeRecommendSnapshot? snap, String uid, HomeRecommendScope scope, DateTime now) =>
      snap != null &&
      snap.schema == schemaVersion &&
      snap.uid == uid &&
      snap.scope == scope &&
      !snap.savedAt.isAfter(now) &&
      now.difference(snap.savedAt) <= ttl &&
      snap.cards.isNotEmpty &&
      snap.cards.length <= maxCards;

  /// [impl_12] 동기 확인 — [read] 와 같은 규칙. 쓸 수 없으면 null(거울에서도 지운다).
  HomeRecommendSnapshot? peek({required String uid, required HomeRecommendScope scope}) {
    if (uid.isEmpty) return null;
    final key = _key(uid);
    final snap = _mirror[key];
    if (_usable(snap, uid, scope, _clock())) return snap;
    _mirror.remove(key);
    return null;
  }

  /// 마지막 성공 스냅샷. 없거나 쓸 수 없으면 null(그 경우 지울 것은 지운다).
  Future<HomeRecommendSnapshot?> read({
    required String uid,
    required HomeRecommendScope scope,
  }) async {
    if (uid.isEmpty) return null;
    final epoch = _epoch;
    final gen = _gen[uid] ?? 0;
    final key = _key(uid);
    String? raw;
    try {
      raw = await _store.get(key);
    } catch (_) {
      return null;
    }
    if (epoch != _epoch || gen != (_gen[uid] ?? 0) || raw == null) return null;
    final snap = HomeRecommendSnapshot._tryDecode(raw);
    final now = _clock();
    // 손상 · 스키마 · uid · 범위 · 시계 역행 · 만료 · 장수 — [_usable] 하나가 [peek] 과 같은 규칙으로 본다.
    if (!_usable(snap, uid, scope, now)) {
      _mirror.remove(key);
      await _safeRemove(key);
      return null;
    }
    _mirror[key] = snap!;
    return snap;
  }

  /// 신선한 **성공** 결과를 저장한다. [cards] 가 비면 옛 값을 지운다(0장 스냅샷 저장 0).
  ///   부분·오류·기본값 결과로는 부르지 않는다(호출부 책임 · [fromCompleteSuccess] 가 false 면 저장 0).
  Future<void> saveSuccess({
    required String uid,
    required HomeRecommendScope scope,
    required List<HomeRecommendCard> cards,
    required bool fromCompleteSuccess,
  }) async {
    if (uid.isEmpty || !fromCompleteSuccess) return;
    // [impl_12 · C291-P2] 이 저장의 순번 — 성공 0장(=폐기)도 순번을 올려 그 전에 시작한 저장을 무효로 만든다.
    final seq = (_saveSeq[uid] ?? 0) + 1;
    _saveSeq[uid] = seq;
    if (cards.isEmpty) {
      await clear(uid); // 세대를 올려 옛 키에 닿지 않게 한 뒤 지운다
      return;
    }
    final epoch = _epoch;
    final gen = _gen[uid] ?? 0;
    final key = _key(uid);
    bool stillMine() => epoch == _epoch && gen == (_gen[uid] ?? 0) && seq == _saveSeq[uid];
    final token = 'e$epoch:g$gen:s$seq';
    final snap = HomeRecommendSnapshot._(
      schema: schemaVersion,
      uid: uid,
      scope: scope,
      savedAt: _clock(),
      cards: List.unmodifiable(cards.take(maxCards)),
      token: token,
    );
    if (!stillMine()) return; // 이미 무효화·폐기됐거나 더 새 저장이 시작됐다 — 쓰지 않는다
    try {
      await _store.set(key, snap._encode());
    } catch (_) {
      return;
    }
    // 쓰는 사이 무효화·폐기·새 저장이 있었으면 **내가 쓴 값만** 지운다(늦은 옛 save 가 삭제·새 결과 뒤 값을 되살리지 못하게 ·
    //   더 새 저장의 값은 건드리지 않는다 — 내 token 일 때만 지운다).
    if (!stillMine()) {
      await _removeIfOwned(key, token);
      return;
    }
    _mirror[key] = snap;
  }

  Future<void> _removeIfOwned(String key, String token) async {
    try {
      final raw = await _store.get(key);
      if (raw == null) return;
      final cur = HomeRecommendSnapshot._tryDecode(raw);
      if (cur == null || cur.token == token) await _store.remove(key);
    } catch (_) {}
  }

  /// 한 사용자 값만 지운다(최신 성공 0장 · 조건 변경 등).
  Future<bool> clear(String uid) async {
    if (uid.isEmpty) return true;
    // [impl_12 · C291-P2] 지우기 전에 세대를 올린다 — 삭제가 실패해도 다음 읽기·진행 중 저장은 옛 키에 닿지 않는다.
    final oldKey = _key(uid);
    _mirror.remove(oldKey);
    _gen[uid] = (_gen[uid] ?? 0) + 1;
    _saveSeq[uid] = (_saveSeq[uid] ?? 0) + 1;
    return _safeRemove(oldKey);
  }

  /// 로그아웃(성공·실패) · 계정/역할 전환 · 탈퇴 BEGIN/재개. 세대를 먼저 올린 뒤 모두 지운다.
  ///   삭제가 실패해도 세대는 이미 올라가 진행 중 저장은 쓰이지 않는다. 반환 = 삭제까지 확인됐는가.
  Future<bool> invalidateAll() async {
    _epoch++; // 키 namespace 가 바뀐다 — 삭제가 실패해도 옛 값은 다시 읽히지 않는다
    _saveSeq.updateAll((_, v) => v + 1);
    _mirror.clear();
    try {
      await _store.removeWhere((k) => k.startsWith('home_recommend_cache_v'));
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _safeRemove(String key) async {
    try {
      await _store.remove(key);
      return true;
    } catch (_) {
      return false;
    }
  }

  @visibleForTesting
  int get debugEpoch => _epoch;
}

/// 캐시 범위 — 하나라도 다르면 옛 값을 쓰지 않는다.
@immutable
class HomeRecommendScope {
  const HomeRecommendScope({
    required this.env,
    required this.role,
    required this.regionKey,
    required this.queryKey,
  });

  /// Firebase 프로젝트 등 실행 환경(DEV/다른 환경 값이 섞이지 않게).
  final String env;

  /// 역할(USER 만 쓸 예정 — 역할이 바뀌면 버린다).
  final String role;

  /// 지역 판정 입력(시·군·구). 없으면 ''.
  final String regionKey;

  /// 추천 조회 조건(선택 날짜 · 정렬 규칙 판 등).
  final String queryKey;

  Map<String, String> _toMap() =>
      {'env': env, 'role': role, 'region': regionKey, 'query': queryKey};

  static HomeRecommendScope? _fromMap(Object? m) {
    if (m is! Map) return null;
    final env = m['env'], role = m['role'], region = m['region'], query = m['query'];
    if (env is! String || role is! String || region is! String || query is! String) return null;
    return HomeRecommendScope(env: env, role: role, regionKey: region, queryKey: query);
  }

  @override
  bool operator ==(Object other) =>
      other is HomeRecommendScope &&
      other.env == env &&
      other.role == role &&
      other.regionKey == regionKey &&
      other.queryKey == queryKey;

  @override
  int get hashCode => Object.hash(env, role, regionKey, queryKey);
}

/// 추천 카드 한 장의 **공개 표시 문구**만. URL · 사람 정보 · 숫자 판정 근거는 넣지 않는다.
@immutable
class HomeRecommendCard {
  HomeRecommendCard({
    required this.toId,
    required this.title,
    required this.businessName,
    required this.regionLabel,
    required this.dateLabel,
    required this.wageLabel,
    this.workTypeIcon,
    String? imageUrl,
  }) : imageUrl = imageUrl != null && isAllowedImageUrl(imageUrl) ? imageUrl : null;

  /// 탭 시 live 상세로 가기 위한 공고 id(표시 근거 아님).
  final String toId;
  final String title;
  final String businessName;
  final String regionLabel;
  final String dateLabel;
  final String wageLabel;

  /// 사진 자리표시 아이콘 키.
  final String? workTypeIcon;

  /// [impl_12 · 판정291 D291-02] 공개 추천 카드가 이미 보이는 **사업장 대표사진**(`BusinessModel.mainImageUrl`) 하나만 조건부 허용.
  ///   허용: https · `firebasestorage.googleapis.com` · 객체 경로가 `businesses/` 아래 · 길이 ≤ [_maxUrl].
  ///   그 밖(신분증·통장·서명·계약·프로필·임시 서명 URL 등 다른 출처·경로)은 생성 시 버린다(null → 자리표시).
  ///   URL 은 로그에 남기지 않는다. RAM 표시 DTO 에만 있다(새 디스크 저장 0 — 이미지 위젯의 자체 캐시는 별개).
  final String? imageUrl;

  static const int _maxUrl = 2048;

  /// 공개 대표사진 출처·경로 검사(판정291 D291-02). 토큰이 붙었다는 사실만으로 허용·거부하지 않는다 — 출처·경로로 판정.
  static bool isAllowedImageUrl(String url) {
    if (url.length > _maxUrl) return false;
    final u = Uri.tryParse(url);
    if (u == null || u.scheme != 'https' || u.host != 'firebasestorage.googleapis.com') return false;
    final segs = u.pathSegments; // v0 / b / {bucket} / o / {encoded object path}
    if (segs.length < 5 || segs[0] != 'v0' || segs[1] != 'b' || segs[3] != 'o') return false;
    final object = segs.sublist(4).join('/');
    return object.startsWith('businesses/') && !object.contains('..');
  }

  static const int _maxText = 80;

  Map<String, Object?> _toMap() => {
        'toId': toId,
        'title': title,
        'biz': businessName,
        'region': regionLabel,
        'date': dateLabel,
        'wage': wageLabel,
        if (workTypeIcon != null) 'icon': workTypeIcon,
        if (imageUrl != null) 'img': imageUrl,
      };

  static HomeRecommendCard? _fromMap(Object? m) {
    if (m is! Map) return null;
    String? s(String k) {
      final v = m[k];
      return v is String && v.length <= _maxText ? v : null;
    }
    final toId = s('toId'), title = s('title'), biz = s('biz'),
        region = s('region'), date = s('date'), wage = s('wage');
    if (toId == null || toId.isEmpty || title == null || biz == null ||
        region == null || date == null || wage == null) {
      return null;
    }
    final icon = m['icon'];
    final img = m['img'];
    return HomeRecommendCard(
      toId: toId,
      title: title,
      businessName: biz,
      regionLabel: region,
      dateLabel: date,
      wageLabel: wage,
      workTypeIcon: icon is String && icon.length <= _maxText ? icon : null,
      imageUrl: img is String ? img : null, // 생성자가 다시 검사한다
    );
  }

  @override
  bool operator ==(Object other) =>
      other is HomeRecommendCard &&
      other.toId == toId &&
      other.title == title &&
      other.businessName == businessName &&
      other.regionLabel == regionLabel &&
      other.dateLabel == dateLabel &&
      other.wageLabel == wageLabel &&
      other.workTypeIcon == workTypeIcon &&
      other.imageUrl == imageUrl;

  @override
  int get hashCode => Object.hash(
      toId, title, businessName, regionLabel, dateLabel, wageLabel, workTypeIcon, imageUrl);
}

/// 읽은 스냅샷 — 화면은 [savedAt] 으로 "마지막 확인 HH:MM" 을 말한다.
@immutable
class HomeRecommendSnapshot {
  const HomeRecommendSnapshot._({
    required this.schema,
    required this.uid,
    required this.scope,
    required this.savedAt,
    required this.cards,
    this.token = '',
  });

  /// [impl_12] 이 값을 쓴 저장의 표지(세대·순번) — 늦은 저장이 자기 값만 지우게 한다.
  final String token;

  final int schema;
  final String uid;
  final HomeRecommendScope scope;
  final DateTime savedAt;
  final List<HomeRecommendCard> cards;

  String _encode() => jsonEncode({
        'v': schema,
        'uid': uid,
        'scope': scope._toMap(),
        'savedAtMs': savedAt.toUtc().millisecondsSinceEpoch,
        'cards': [for (final c in cards) c._toMap()],
        'tok': token,
      });

  static HomeRecommendSnapshot? _tryDecode(String raw) {
    try {
      final m = jsonDecode(raw);
      if (m is! Map) return null;
      final v = m['v'], uid = m['uid'], ms = m['savedAtMs'], list = m['cards'];
      final scope = HomeRecommendScope._fromMap(m['scope']);
      if (v is! int || uid is! String || ms is! int || list is! List || scope == null) {
        return null;
      }
      final cards = <HomeRecommendCard>[];
      for (final c in list) {
        final card = HomeRecommendCard._fromMap(c);
        if (card == null) return null; // 한 장이라도 손상 → 통째로 버린다
        cards.add(card);
      }
      return HomeRecommendSnapshot._(
        schema: v,
        uid: uid,
        scope: scope,
        savedAt: DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true),
        cards: List.unmodifiable(cards),
        token: m['tok'] is String ? m['tok'] as String : '',
      );
    } catch (_) {
      return null;
    }
  }
}

/// 저장소 경계 — 기본은 RAM. 디스크 구현은 백업 제외·정책 확인 뒤에만 넣는다.
abstract class HomeRecommendStore {
  Future<String?> get(String key);
  Future<void> set(String key, String value);
  Future<void> remove(String key);
  Future<void> removeWhere(bool Function(String key) test);
}

/// 프로세스 메모리 저장소 — 앱을 다시 켜면 비어 있다.
class RamHomeRecommendStore implements HomeRecommendStore {
  final Map<String, String> _m = {};

  @override
  Future<String?> get(String key) async => _m[key];

  @override
  Future<void> set(String key, String value) async => _m[key] = value;

  @override
  Future<void> remove(String key) async => _m.remove(key);

  @override
  Future<void> removeWhere(bool Function(String key) test) async =>
      _m.removeWhere((k, _) => test(k));

  @visibleForTesting
  int get debugLength => _m.length;
}
