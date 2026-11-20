import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

/// [POSTING-QUOTA-45] 공고 탭 한도 요약 — 서버 `callableGetPostingQuotaSummary` 응답 하나만 믿는다.
///
///   공고 목록 항목을 세지 않는다. 서버 한도는 소유자 전체 사업장에서 관리자·서브관리자가
///   등록한 ACTIVE+FULL(마감·만료·삭제 제외)을 세는데, 목록은 보이는 사업장·탭만 담는다.
///   두 모집단이 다르다(POSTING-V2-02A.1 이 탭 숫자에서 분모를 뗀 이유와 같다).
///
///   소유자가 다른 사업장은 서버가 범위를 나눠 준다 — 여기서 분모를 합치지 않는다.

/// 같은 소유자 범위의 한도. [remaining] 은 서버가 0 아래로 내리지 않는다(한도 하향 시 초과 표시).
@immutable
class PostingQuotaScope {
  const PostingQuotaScope({
    required this.scopeToken,
    required this.businessIds,
    required this.used,
    required this.limit,
    required this.remaining,
  });

  final String scopeToken;
  final List<String> businessIds;
  final int used;
  final int limit;
  final int remaining;

  bool get isAtLimit => remaining <= 0;
  bool get isOverLimit => used > limit;

  static PostingQuotaScope? tryFromMap(Object? raw) {
    if (raw is! Map) return null;
    final token = raw['scopeToken'];
    final ids = raw['businessIds'];
    final used = raw['used'];
    final limit = raw['limit'];
    final remaining = raw['remaining'];
    if (token is! String || ids is! List || used is! num || limit is! num || remaining is! num) {
      return null;
    }
    if (limit <= 0 || used < 0 || remaining < 0) return null;
    return PostingQuotaScope(
      scopeToken: token,
      businessIds: ids.whereType<String>().toList(growable: false),
      used: used.toInt(),
      limit: limit.toInt(),
      remaining: remaining.toInt(),
    );
  }
}

@immutable
class PostingQuotaResult {
  const PostingQuotaResult({required this.scopes, required this.denied, required this.failed});

  final List<PostingQuotaScope> scopes;
  final List<String> denied;
  final List<String> failed;

  /// 이 사업장의 범위. 없으면 null(권한 없음·확인 실패·요청 밖).
  PostingQuotaScope? scopeOf(String businessId) {
    for (final s in scopes) {
      if (s.businessIds.contains(businessId)) return s;
    }
    return null;
  }

  static PostingQuotaResult? tryFromMap(Object? raw) {
    if (raw is! Map) return null;
    final scopes = raw['scopes'];
    if (scopes is! List) return null;
    final parsed = scopes.map(PostingQuotaScope.tryFromMap).toList();
    // 범위 하나라도 읽지 못하면 응답 전체를 실패로 본다 — 일부만 그려 숫자를 지어내지 않는다.
    if (parsed.any((s) => s == null)) return null;
    List<String> ids(Object? v) => v is List ? v.whereType<String>().toList(growable: false) : const [];
    return PostingQuotaResult(
      scopes: parsed.whereType<PostingQuotaScope>().toList(growable: false),
      denied: ids(raw['denied']),
      failed: ids(raw['failed']),
    );
  }

  /// 같은 소유자 범위가 여러 요청(20개씩)에 걸쳐 오면 하나로 합친다 — 사용량·한도는 같은 값이다.
  static PostingQuotaResult merge(List<PostingQuotaResult> parts) {
    final byToken = <String, PostingQuotaScope>{};
    for (final p in parts) {
      for (final s in p.scopes) {
        final prev = byToken[s.scopeToken];
        byToken[s.scopeToken] = prev == null
            ? s
            : PostingQuotaScope(
                scopeToken: s.scopeToken,
                businessIds: {...prev.businessIds, ...s.businessIds}.toList(growable: false),
                used: s.used,
                limit: s.limit,
                remaining: s.remaining,
              );
      }
    }
    return PostingQuotaResult(
      scopes: byToken.values.toList(growable: false),
      denied: [for (final p in parts) ...p.denied],
      failed: [for (final p in parts) ...p.failed],
    );
  }
}

/// [denied] 서버가 호출 자체를 권한으로 거절했다 — 숫자도 '확인 불가'도 그리지 않는다(권한 안내는 공고 탭이 한다).
enum PostingQuotaStatus { idle, loading, loaded, failed, denied }

@immutable
class PostingQuotaSnapshot {
  const PostingQuotaSnapshot({required this.status, required this.key, this.value});
  const PostingQuotaSnapshot.idle() : status = PostingQuotaStatus.idle, key = '', value = null;

  final PostingQuotaStatus status;

  /// 어떤 사업장 집합에 대한 값인가 — 사람(uid)까지 포함한다.
  final String key;

  /// 마지막 성공 값. 같은 집합을 다시 읽는 동안에는 남겨 둔다(깜빡임 없음).
  final PostingQuotaResult? value;
}

typedef PostingQuotaFetch = Future<Object?> Function(List<String> businessIds);

class PostingQuotaStore {
  PostingQuotaStore._();

  static const int _chunk = 20;

  static final ValueNotifier<PostingQuotaSnapshot> current =
      ValueNotifier<PostingQuotaSnapshot>(const PostingQuotaSnapshot.idle());

  /// 테스트가 바꾼다. 기본은 서버 callable.
  @visibleForTesting
  static PostingQuotaFetch fetch = _callServer;

  /// 몇 번 물었는가 — 첫 진입·재진입 호출 수 비교용.
  @visibleForTesting
  static int fetchCount = 0;

  /// [POSTING-QUOTA-46] 한 번의 읽기(나눠 묻기 포함) 전체 대기 상한 — 앱 기준.
  ///   서버 요청을 취소하거나 서버 실패를 증명하는 값이 아니다. 넘으면 숫자 없이 '확인 불가' 다.
  @visibleForTesting
  static Duration budget = const Duration(seconds: 30);

  static Future<void>? _inFlight;
  static String? _inFlightKey;

  /// 읽기마다 번호를 붙인다 — 마지막으로 시작한 읽기만 화면에 쓴다.
  static int _seq = 0;
  static String _lastKey = '';
  static List<String> _lastIds = const [];

  static Future<Object?> _callServer(List<String> businessIds) async {
    final r = await FirebaseFunctions.instanceFor(region: 'asia-northeast3')
        .httpsCallable('callableGetPostingQuotaSummary',
            options: HttpsCallableOptions(timeout: const Duration(seconds: 15)))
        .call<Object?>({'businessIds': businessIds});
    return r.data;
  }

  static String keyOf(String uid, Iterable<String> businessIds) {
    final ids = businessIds.toSet().toList()..sort();
    return '$uid|${ids.join(',')}';
  }

  /// 이 사람·이 사업장 집합의 값이 없으면 읽는다. 같은 집합을 동시에 물으면 한 번만 읽는다.
  ///   집합이 바뀌면 이전 값은 버린다 — 다른 소유자의 숫자를 잠깐이라도 보여 주지 않는다.
  static Future<void> ensure({required String uid, required List<String> businessIds, bool force = false}) {
    final ids = businessIds.where((x) => x.isNotEmpty).toSet().toList()..sort();
    if (ids.isEmpty) {
      reset();
      return Future<void>.value();
    }
    final key = keyOf(uid, ids);
    final snap = current.value;
    if (!force && snap.key == key && snap.status == PostingQuotaStatus.loaded) return Future<void>.value();
    // 같은 집합을 읽는 중이면 합친다. 다시 읽기(force)는 기다렸다 이어 붙이지 않고 **새 읽기로 대체한다** —
    //   이어 붙이면 앞 읽기의 대기(최대 [budget])에 새 대기가 더해진다. 앞 읽기의 늦은 결과는 번호로 버린다.
    if (!force && _inFlight != null && _inFlightKey == key) return _inFlight!;
    _lastKey = key;
    _lastIds = ids;
    current.value = PostingQuotaSnapshot(
      status: PostingQuotaStatus.loading,
      key: key,
      value: snap.key == key ? snap.value : null,
    );
    final f = _load(key, ids);
    _inFlight = f;
    _inFlightKey = key;
    return f.whenComplete(() {
      if (identical(_inFlight, f)) {
        _inFlight = null;
        _inFlightKey = null;
      }
    });
  }

  static Future<PostingQuotaResult> _fetchAll(List<String> ids) async {
    final parts = <PostingQuotaResult>[];
    for (var i = 0; i < ids.length; i += _chunk) {
      fetchCount++;
      final raw = await fetch(ids.sublist(i, i + _chunk > ids.length ? ids.length : i + _chunk));
      final p = PostingQuotaResult.tryFromMap(raw);
      if (p == null) throw const FormatException('한도 요약 응답 형식');
      parts.add(p);
    }
    return PostingQuotaResult.merge(parts);
  }

  static Future<void> _load(String key, List<String> ids) async {
    final mySeq = ++_seq;
    PostingQuotaResult? result;
    var status = PostingQuotaStatus.failed;
    try {
      // 나눠 묻기 전체가 한 상한 안이다 — 묶음마다 새로 주지 않는다.
      result = await _fetchAll(ids).timeout(budget);
      status = PostingQuotaStatus.loaded;
    } on TimeoutException {
      debugPrint('⚠️ [Quota] 한도 요약 대기 상한 초과(${budget.inSeconds}s)');
    } on FirebaseFunctionsException catch (e) {
      debugPrint('⚠️ [Quota] 한도 요약 조회 실패: ${e.code}');
      if (e.code == 'permission-denied' || e.code == 'unauthenticated') status = PostingQuotaStatus.denied;
    } catch (e) {
      debugPrint('⚠️ [Quota] 한도 요약 조회 실패: $e');
    }
    // 더 늦게 시작한 읽기가 있거나(다시 시도) 집합이 바뀌었으면(계정·소유자 전환) 이 결과는 버린다.
    if (mySeq != _seq || current.value.key != key) return;
    current.value = PostingQuotaSnapshot(status: status, key: key, value: result);
  }

  /// 등록·공개·종료·삭제·한도 거절 뒤 — 마지막으로 물은 집합을 다시 읽는다.
  static Future<void> refreshLast() {
    if (_lastIds.isEmpty) return Future<void>.value();
    final uid = _lastKey.split('|').first;
    return ensure(uid: uid, businessIds: _lastIds, force: true);
  }

  /// 로그아웃·계정 전환 경계.
  static void reset() {
    _inFlight = null;
    _inFlightKey = null;
    _seq++;
    _lastKey = '';
    _lastIds = const [];
    current.value = const PostingQuotaSnapshot.idle();
  }
}
