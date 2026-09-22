// [R8-P7.5] 사업장 조회 실패가 "근무 없음"이 되지 않는다.
//
//   P7.4 를 닫으면서 남긴 [OPEN-R8P74-GETMYBUSINESS-EMPTY] 를 여기서 닫는다.
//   근무 관리 화면의 모든 조회는 사업장 목록을 전제로 돈다. 그 목록 하나가
//   실패를 빈 목록으로 바꾸면 그 아래 전부가 조용히 거짓이 된다 —
//   근무자 0, 근무 없음, 오늘 일정 없음.
//
//   더 나쁜 것은 캐시였다. 실패한 빈 목록이 캐시에 앉으면 네트워크가
//   돌아와도 성공한 재조회가 그것을 덮지 못했다.
//
//   두 축으로 고정한다.
//     · replica  — 위상(topology)이 실제로 네 상태를 구분하는가
//     · source   — 실제 파일이 그 위상을 그대로 갖고 있는가
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String p) {
  final f = File(p);
  if (!f.existsSync()) throw StateError('파일을 찾지 못했다: $p');
  return f.readAsStringSync();
}

/// 주석을 지운 코드만 남긴다 — 표지를 주석에 두지 않기 위해.
String _codeOf(String src) => src
    .split('\n')
    .where((l) => !l.trimLeft().startsWith('//'))
    .join('\n');

String _flat(String s) => s.replaceAll(RegExp(r'\s+'), ' ');

/// [open, end] 를 잡아 블록 하나를 잘라 낸다.
String _blockAt(String code, int open) {
  var depth = 0;
  var end = open;
  for (var k = open; k < code.length; k++) {
    if (code[k] == '{') depth++;
    if (code[k] == '}') {
      depth--;
      if (depth == 0) {
        end = k;
        break;
      }
    }
  }
  return code.substring(open, end + 1);
}

/// 함수 본문만 잘라 낸다.
///
/// named parameter 의 `{bool force = false}` 를 본문 시작으로 착각하지 않도록
/// 파라미터 목록의 닫는 괄호 뒤에서 여는 중괄호를 찾는다.
String _bodyOf(String code, String fnStart) {
  final s = code.indexOf(fnStart);
  if (s < 0) throw StateError('함수를 찾지 못했다: $fnStart');
  var depth = 0;
  var close = -1;
  for (var k = s + fnStart.length - 1; k < code.length; k++) {
    if (code[k] == '(') depth++;
    if (code[k] == ')') {
      depth--;
      if (depth == 0) {
        close = k;
        break;
      }
    }
  }
  if (close < 0) throw StateError('파라미터 목록을 닫지 못했다: $fnStart');
  final open = code.indexOf('{', close);
  if (open < 0) throw StateError('본문을 찾지 못했다: $fnStart');
  return _blockAt(code, open);
}

// ══════════════════════════════════════════════════════════════════
// replica — workforce_operational_view 의 사업장 캐시 위상
// ══════════════════════════════════════════════════════════════════

class _Outcome {
  final List<String>? value; // null 이면 실패
  const _Outcome.ok(this.value);
  const _Outcome.fail() : value = null;
}

/// 화면이 사업장에 대해 알 수 있는 상태.
enum _CacheState { notLoaded, loadedNonEmpty, loadedEmpty, error }

class _WorkforceReplica {
  List<String>? cachedBusinesses;
  String? cachedBusinessesScope;
  bool businessesStale = false;

  /// 현재 사용자·사업장 범위. SubAdmin 이 사업장을 바꾸면 여기가 바뀐다.
  String scope = 'uid-1|false|null';

  /// 캐시에 쓴 횟수 — 실패 경로에서 0이어야 한다.
  int cacheWrites = 0;

  String? loadError;
  bool staleNoticeShown = false;
  List<String> applications = const [];

  /// 다음 조회가 성공할지 실패할지. 테스트가 조종한다.
  _Outcome next = const _Outcome.ok(['biz-A']);

  Future<List<String>> ensureBusinesses() async {
    // [§19] 범위가 다르면 이전 캐시는 쓸 수 없다.
    final cached = cachedBusinessesScope == scope ? cachedBusinesses : null;
    if (cached != null && !businessesStale) return cached;

    List<String> result;
    if (next.value == null) {
      // [§9] 이전에 정상으로 읽어 둔 목록이 있으면 지키고 계속 쓴다.
      if (cached != null) {
        staleNoticeShown = true;
        return cached;
      }
      throw Exception('UNAVAILABLE'); // [§5] 캐시에 아무것도 쓰지 않는다
    }
    result = next.value!;

    cachedBusinesses = result;
    cachedBusinessesScope = scope;
    cacheWrites++;
    businessesStale = false;
    return result;
  }

  Future<void> loadDayData() async {
    loadError = null;
    try {
      final businesses = await ensureBusinesses();
      if (businesses.isEmpty) {
        applications = const [];
        loadError = null; // 성공했고 사업장이 정말 0개다
        return;
      }
      applications = ['워커1', '워커2'];
      loadError = null;
    } catch (e) {
      applications = const [];
      loadError = '데이터를 불러오지 못했습니다. 다시 시도해 주세요.';
    }
  }

  void reload() {
    businessesStale = true; // 지우지 않는다
  }

  _CacheState get state {
    if (loadError != null) return _CacheState.error;
    final c = cachedBusinesses;
    if (c == null) return _CacheState.notLoaded;
    return c.isEmpty ? _CacheState.loadedEmpty : _CacheState.loadedNonEmpty;
  }

  /// 화면이 실제로 뱉는 문장.
  String get screenText {
    if (loadError != null) return '오류: $loadError';
    if (applications.isEmpty) return '근무 없음';
    return '근무자 ${applications.length}명';
  }
}

void main() {
  const view =
      'lib/screens/business_admin/workforce_management/workforce_operational_view.dart';
  const bizSvc = 'lib/services/firestore/business_firestore.dart';

  group('[R8P7.5] GMB — empty / error / cache 의미가 갈린다', () {
    test('GMB-1 정상 nonempty', () async {
      final v = _WorkforceReplica()..next = const _Outcome.ok(['biz-A']);
      await v.loadDayData();
      expect(v.state, _CacheState.loadedNonEmpty);
      expect(v.screenText, '근무자 2명');
      expect(v.loadError, isNull);
    });

    test('GMB-2 정상 empty — 사업장이 정말 0개', () async {
      final v = _WorkforceReplica()..next = const _Outcome.ok([]);
      await v.loadDayData();
      expect(v.state, _CacheState.loadedEmpty,
          reason: '성공한 0개는 오류가 아니다');
      expect(v.screenText, '근무 없음', reason: '실제 empty 문구는 유지된다');
      expect(v.loadError, isNull);
      expect(v.cacheWrites, 1, reason: '성공 결과는 캐시해도 된다');
    });

    test('GMB-3 조회 실패는 empty 가 아니다', () async {
      final v = _WorkforceReplica()..next = const _Outcome.fail();
      await v.loadDayData();
      expect(v.state, _CacheState.error);
      expect(v.screenText, startsWith('오류:'),
          reason: '실패가 "근무 없음"으로 보이면 안 된다');
      expect(v.screenText, isNot('근무 없음'));
    });

    test('GMB-4 실패는 빈 목록을 캐시하지 않는다', () async {
      final v = _WorkforceReplica()..next = const _Outcome.fail();
      await v.loadDayData();
      expect(v.cacheWrites, 0, reason: '실패 경로에서 캐시 mutation 0');
      expect(v.cachedBusinesses, isNull,
          reason: '실패는 NOT_LOADED 로 남는다 — LOADED_EMPTY 가 아니다');
      expect(v.state, isNot(_CacheState.loadedEmpty));
    });

    test('GMB-5 이전 정상 캐시는 갱신 실패로 사라지지 않는다', () async {
      final v = _WorkforceReplica()..next = const _Outcome.ok(['biz-A']);
      await v.loadDayData();
      expect(v.cachedBusinesses, ['biz-A']);

      // 사용자가 새로고침했고, 이번 갱신은 실패한다.
      v.reload();
      v.next = const _Outcome.fail();
      await v.loadDayData();

      expect(v.cachedBusinesses, ['biz-A'],
          reason: '오류 때문에 실재하는 사업장을 지우면 안 된다');
      expect(v.screenText, '근무자 2명', reason: '실제 근무가 사라지면 안 된다');
      expect(v.staleNoticeShown, isTrue, reason: '갱신 실패는 알려야 한다');
    });

    test('GMB-6 첫 로드 실패 후 재시도로 복구된다', () async {
      final v = _WorkforceReplica()..next = const _Outcome.fail();
      await v.loadDayData();
      expect(v.state, _CacheState.error);

      // 네트워크 복구 후 재시도.
      v.next = const _Outcome.ok(['biz-A']);
      await v.loadDayData();

      expect(v.state, _CacheState.loadedNonEmpty);
      expect(v.loadError, isNull, reason: 'error state 가 지워져야 한다');
      expect(v.screenText, '근무자 2명');
    });

    test('GMB-6b 빈 캐시가 복구를 막던 회귀', () async {
      // 이전 위상에서는 실패가 []를 캐시해, 성공한 재조회조차 덮지 못했다.
      final v = _WorkforceReplica()..next = const _Outcome.fail();
      await v.loadDayData();
      v.next = const _Outcome.ok(['biz-A']);
      await v.loadDayData();
      expect(v.screenText, '근무자 2명', reason: '빈 캐시가 고착되면 안 된다');
    });

    test('GMB-9 범위가 바뀌면 이전 캐시를 쓰지 않는다 (§19)', () async {
      final v = _WorkforceReplica()..next = const _Outcome.ok(['biz-A']);
      await v.loadDayData();
      expect(v.cachedBusinesses, ['biz-A']);

      // SubAdmin 이 다른 사업장으로 전환했고, 그 직후 갱신이 실패한다.
      v.scope = 'uid-1|true|biz-B';
      v.next = const _Outcome.fail();
      await v.loadDayData();

      expect(v.screenText, startsWith('오류:'),
          reason: '다른 사업장의 목록을 대신 보여주면 안 된다');
      expect(v.staleNoticeShown, isFalse,
          reason: '범위가 다르면 "이전 정보" 자체가 성립하지 않는다');
    });

    test('GMB-9b 범위가 같을 때만 stale 재사용이 성립한다', () async {
      final v = _WorkforceReplica()..next = const _Outcome.ok(['biz-A']);
      await v.loadDayData();
      v.reload();
      v.next = const _Outcome.fail();
      await v.loadDayData();
      expect(v.screenText, '근무자 2명');
      expect(v.staleNoticeShown, isTrue);
    });

    test('GMB-8 권한 실패도 empty 가 아니다', () async {
      // PERMISSION_DENIED / UNAUTHENTICATED 도 같은 실패 경로를 탄다.
      final v = _WorkforceReplica()..next = const _Outcome.fail();
      await v.loadDayData();
      expect(v.state, _CacheState.error);
      expect(v.cacheWrites, 0);
      expect(v.screenText, isNot('근무 없음'));
    });
  });

  group('[R8P7.5] 서비스 — OrThrow 변형과 기존 계약이 함께 있다', () {
    test('GMB-S1 getMyBusinessOrThrow 는 삼키지 않는다', () {
      final code = _codeOf(_read(bizSvc));
      final body = _bodyOf(
          code, 'Future<List<BusinessModel>> getMyBusinessOrThrow(');
      expect(body.contains('return [];'), isFalse,
          reason: 'OrThrow 가 빈 목록을 돌려주면 이름이 거짓말이 된다');
      // 개별 문서 파싱 실패는 계속 건너뛴다 — 한 건 손상이 전체를 막지 않는다.
      expect(body.contains('BusinessModel 파싱 실패'), isTrue);
    });

    test('GMB-S2 getBusinessByIdOrThrow 의 null 은 "부재"만 뜻한다', () {
      final code = _codeOf(_read(bizSvc));
      final body = _bodyOf(
          code, 'Future<BusinessModel?> getBusinessByIdOrThrow(');
      expect(body.contains('} catch'), isFalse,
          reason: '읽기 실패를 null 로 접으면 부재와 구분되지 않는다');
      expect(body.contains('if (!doc.exists)'), isTrue);
    });

    test('GMB-7 기존 관대한 계약이 그대로 남아 있다 (다른 호출부 무회귀)', () {
      final code = _flat(_codeOf(_read(bizSvc)));
      expect(
          code.contains(
              'Future<List<BusinessModel>> getMyBusiness(String uid) async '
              '{ try { return await getMyBusinessOrThrow(uid); }'),
          isTrue,
          reason: '삼키는 변형이 사라지면 27개 호출부가 한꺼번에 영향을 받는다');
      expect(
          code.contains(
              'Future<BusinessModel?> getBusinessById(String businessId) async '
              '{ try { return await getBusinessByIdOrThrow(businessId); }'),
          isTrue);
    });

    test('GMB-7b OrThrow 는 Workforce 밖으로 번지지 않았다', () {
      // 범위를 넓히지 않았다는 확인 — 이번 Phase 는 근무 관리 경로만이다.
      final dir = Directory('lib');
      final users = <String>[];
      for (final f in dir.listSync(recursive: true)) {
        if (f is! File || !f.path.endsWith('.dart')) continue;
        if (f.path.replaceAll('\\', '/').endsWith('business_firestore.dart')) {
          continue;
        }
        final s = f.readAsStringSync();
        if (s.contains('getMyBusinessOrThrow') ||
            s.contains('getBusinessByIdOrThrow')) {
          users.add(f.path.replaceAll('\\', '/'));
        }
      }
      expect(users.length, 1, reason: '사용처: $users');
      expect(users.first.endsWith('workforce_operational_view.dart'), isTrue);
    });
  });

  group('[R8P7.5] 화면 — 실패가 캐시·빈 상태로 붕괴하지 않는다', () {
    test('GMB-V1 캐시는 성공했을 때만 기록된다 (§5 §24)', () {
      final code = _codeOf(_read(view));
      final body =
          _bodyOf(code, 'Future<List<BusinessModel>> _ensureBusinesses(');
      final flat = _flat(body);
      expect(flat.contains('rethrow;'), isTrue,
          reason: '첫 로드 실패는 올려 보내야 한다');
      // catch 블록 **안에서만** 캐시를 쓰지 않는지 본다.
      final ci = body.indexOf('} catch (');
      expect(ci, greaterThan(0));
      final catchBody = _blockAt(body, body.indexOf('{', ci + 2));
      expect(catchBody.contains('_cachedBusinesses ='), isFalse,
          reason: '실패 경로에서 캐시 mutation 0');
      expect(catchBody.contains('rethrow;'), isTrue);
      // 캐시 기록은 try 를 빠져나온 뒤 한 곳에서만 일어난다.
      expect('_cachedBusinesses ='.allMatches(body).length, 1);
    });

    test('GMB-V2 _reload 는 캐시를 지우지 않고 stale 로 표시한다 (§9)', () {
      final code = _flat(_codeOf(_read(view)));
      expect(code.contains('_cachedBusinesses = null;'), isFalse,
          reason: '지워 버리면 갱신 실패 시 실재하는 사업장까지 사라진다');
      expect(code.contains('_businessesStale = true;'), isTrue);
      expect(code.contains('cached != null && !_businessesStale'), isTrue);
    });

    test('GMB-V2b 살아남는 캐시는 같은 범위의 것이어야 한다 (§19)', () {
      final code = _flat(_codeOf(_read(view)));
      expect(code.contains(r"final scope = '$uid|${up.isSubAdmin}|$effectiveBizId';"),
          isTrue, reason: '캐시에 범위 key 가 없으면 사업장 전환 후 이전 목록이 남는다');
      expect(code.contains('_cachedBusinessesScope == scope ? _cachedBusinesses : null'),
          isTrue);
      expect(code.contains('_cachedBusinessesScope = scope;'), isTrue);
    });

    test('GMB-V3 ERROR 분기가 EMPTY 분기보다 먼저 온다 (§23)', () {
      final code = _codeOf(_read(view));
      for (final fn in [
        'Future<void> _loadDayData(',
        'Future<void> _loadMarkerRange(',
      ]) {
        final body = _bodyOf(code, fn);
        final tryAt = body.indexOf('try {');
        final ensureAt = body.indexOf('_ensureBusinesses()');
        final emptyAt = body.indexOf('businesses.isEmpty');
        expect(tryAt, greaterThanOrEqualTo(0), reason: fn);
        expect(ensureAt, greaterThan(tryAt),
            reason: '$fn — 사업장 조회가 try 밖에 있으면 실패가 빈 목록으로 샌다');
        expect(emptyAt, greaterThan(ensureAt), reason: fn);
      }
    });

    test('GMB-V4 성공한 0개는 여전히 "없음"으로 말한다 (§7)', () {
      final code = _flat(_codeOf(_read(view)));
      expect(code.contains("ToastHelper.showWarning('등록된 사업장이 없습니다')"),
          isTrue, reason: '실제 empty 문구를 없애는 것은 목적이 아니다');
      expect(code.contains("ToastHelper.showError('사업장 정보를 불러올 수 없습니다')"),
          isTrue, reason: '실패는 다른 문장으로 말한다');
    });

    test('GMB-V5 다이얼로그 진입부가 실패를 "사업장 0개"로 말하지 않는다', () {
      final code = _codeOf(_read(view));
      for (final fn in [
        'Future<void> _openAttendanceDialog(',
        'Future<void> _openAttendanceDialogForWorker(',
        'Future<void> _openApplicantsDialog(',
        'Future<void> _openFixedWorkerManagement(',
      ]) {
        final body = _bodyOf(code, fn);
        final ensureAt = body.indexOf('_ensureBusinesses()');
        final tryAt = body.indexOf('try {');
        expect(ensureAt, greaterThan(0), reason: fn);
        expect(tryAt, greaterThanOrEqualTo(0),
            reason: '$fn — 사업장 조회 실패를 받을 자리가 없다');
        expect(ensureAt, greaterThan(tryAt), reason: fn);
      }
    });

    test('GMB-V6 기존 오류 표면을 재사용했다 — 새 framework 없다 (§4 §11)', () {
      final code = _flat(_codeOf(_read(view)));
      expect(code.contains('_loadError'), isTrue);
      expect(code.contains('_markerFailed'), isTrue);
      expect(code.contains('Widget _buildErrorState()'), isTrue);
      // 새 상태 enum/클래스를 만들지 않았다.
      expect(code.contains('enum _BusinessCacheState'), isFalse);
      expect(code.contains('class BusinessLoadResult'), isFalse);
    });
  });
}
