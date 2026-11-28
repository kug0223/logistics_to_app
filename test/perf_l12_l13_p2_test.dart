// [PERF-FIRST-LOAD-1 · 판정289] L12 App Check 공유 future · L13 테마 1회 생성/알림 가드 · P2 추천 캐시 모듈.
import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:ALfit/providers/theme_provider.dart';
import 'package:ALfit/services/app_check_ready.dart';
import 'package:ALfit/services/home_recommend_cache.dart';
import 'package:ALfit/theme/role_theme.dart';

String _code(String p) => File(p)
    .readAsStringSync()
    .replaceAll('\r\n', '\n')
    .split('\n')
    .where((l) => !l.trimLeft().startsWith('//'))
    .join('\n');

String _bodyOf(String src, String sig) {
  final at = src.indexOf(sig);
  expect(at, isNot(-1), reason: '$sig 가 없다');
  final m = RegExp(r'\)\s*(async\s*)?\{').firstMatch(src.substring(at));
  final open = at + m!.end - 1;
  var depth = 0;
  for (var i = open; i < src.length; i++) {
    if (src[i] == '{') depth++;
    if (src[i] == '}') {
      depth--;
      if (depth == 0) return src.substring(at, i + 1);
    }
  }
  return src.substring(at);
}

const _scope = HomeRecommendScope(env: 'dev', role: 'USER', regionKey: '강남구', queryKey: 'none');

HomeRecommendCard _card(String id) => HomeRecommendCard(
      toId: id,
      title: '물류센터 상하차',
      businessName: '강남 물류센터',
      regionLabel: '강남구 역삼동',
      dateLabel: '11월 30일',
      wageLabel: '시급 12,000원',
    );

/// 쓰기를 붙잡아 둘 수 있는 저장소 — 늦은 write 재현용.
class _GateStore extends RamHomeRecommendStore {
  Completer<void>? holdSet;
  bool failRemove = false;
  final raw = <String, String>{};
  @override
  Future<void> set(String key, String value) async {
    final h = holdSet;
    if (h != null) await h.future;
    await super.set(key, value);
  }

  @override
  Future<String?> get(String key) async => raw[key] ?? await super.get(key);

  @override
  Future<void> removeWhere(bool Function(String key) test) async {
    if (failRemove) throw StateError('disk');
    raw.removeWhere((k, _) => test(k));
    await super.removeWhere(test);
  }

  @override
  Future<void> remove(String key) async {
    raw.remove(key);
    await super.remove(key);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ── L12 ─────────────────────────────────────────────────────────────
  group('[L12] App Check 첫 토큰 — runApp 비차단 · 첫 요청 합류', () {
    setUp(AppCheckReady.debugReset);

    test('AC-1 토큰 받기는 한 번만 · 대기자는 같은 future 에 합류', () async {
      var calls = 0;
      final token = Completer<String>();
      AppCheckReady.start(() {
        calls++;
        return token.future;
      });
      AppCheckReady.start(() {
        calls++;
        return token.future;
      });
      expect(calls, 1, reason: '"Too many attempts" — 토큰 요청이 겹쳤다');
      var joined = 0;
      final waits = [for (var i = 0; i < 5; i++) AppCheckReady.wait().then((_) => joined++)];
      await Future<void>.delayed(Duration.zero);
      expect(joined, 0, reason: '토큰 전에 요청이 나갔다');
      token.complete('t');
      await Future.wait(waits);
      expect(joined, 5);
      expect(AppCheckReady.settled, isTrue);
      expect(calls, 1);
    });

    test('AC-2 실패는 삼키고 대기자는 진행 · 시작 전이면 즉시 · 상한 뒤 진행', () async {
      await AppCheckReady.wait(); // 시작 전 — 바로 끝난다
      AppCheckReady.start(() => Future<String>.error(StateError('network')));
      await AppCheckReady.wait();
      expect(AppCheckReady.settled, isTrue);
      AppCheckReady.debugReset();
      AppCheckReady.start(() => Completer<String>().future); // 끝나지 않는 토큰
      final sw = Stopwatch()..start();
      await AppCheckReady.wait(timeout: const Duration(milliseconds: 50));
      expect(sw.elapsedMilliseconds, lessThan(2000));
    });

    test('AC-3 소스 — runApp 앞 토큰 await 0 · 첫 요청들이 합류', () {
      final m = _code('lib/main.dart');
      final mainFn = _bodyOf(m, 'void main() async');
      expect(mainFn.contains('await FirebaseAppCheck.instance.getToken()'), isFalse);
      expect(mainFn.contains('AppCheckReady.start(() => FirebaseAppCheck.instance.getToken())'), isTrue);
      expect(mainFn.indexOf('await FirebaseAppCheck.instance.activate('),
          lessThan(mainFn.indexOf('AppCheckReady.start(')));
      expect(mainFn.contains('AppCheckReady.wait().then((_) => AuthService().getUserData(uid))'), isTrue);
      final wage = mainFn.indexOf('WageCalculator.loadMinimumWages();');
      expect(mainFn.lastIndexOf('AppCheckReady.wait()', wage), greaterThan(-1));
      final up = _code('lib/providers/user_provider.dart');
      final load = _bodyOf(up, 'Future<void> _loadUserData(String uid)');
      expect(load.indexOf('await AppCheckReady.wait();'),
          lessThan(load.indexOf('await _authService.getUserData(uid)')));
      for (final sig in ['Future<bool> signIn(String username', 'Future<bool> signInWithCustomToken(']) {
        final b = _bodyOf(up, sig);
        expect(b.indexOf('await AppCheckReady.wait();'), allOf(isNot(-1), lessThan(b.indexOf('_authService.signIn'))),
            reason: sig);
      }
    });
  });

  // ── L13 ─────────────────────────────────────────────────────────────
  group('[L13] 테마 1회 생성 · 같은 값이면 알림 0', () {
    test('TH-1 통합 테마는 같은 객체다', () {
      expect(identical(RoleTheme.workerTheme, RoleTheme.workerTheme), isTrue);
      expect(identical(RoleTheme.workerTheme, RoleTheme.businessAdminTheme), isTrue);
      expect(identical(RoleTheme.getThemeByRole('USER'), RoleTheme.getThemeByRole(null)), isTrue);
    });

    test('TH-2 역할 설정·초기화가 같은 테마면 MaterialApp 을 다시 만들게 하지 않는다', () {
      final p = ThemeProvider();
      var notified = 0;
      p.addListener(() => notified++);
      p.setRole('USER');
      expect(p.currentRole, 'USER', reason: '역할 값은 바뀐다');
      p.setRole('BUSINESS_ADMIN');
      p.reset();
      p.reset();
      expect(p.currentRole, isNull);
      expect(notified, 0, reason: '테마가 같은데 알렸다');
      expect(identical(p.theme, RoleTheme.workerTheme), isTrue);
    });
  });

  // ── P2 ──────────────────────────────────────────────────────────────
  group('[P2] 추천 표시 캐시 — 경계', () {
    final t0 = DateTime.utc(2026, 11, 26, 9);

    test('RC-1 성공 저장 → 같은 uid·범위에서 읽기 · 최대 2장 · 표시 문구만', () async {
      final c = HomeRecommendCache(clock: () => t0);
      await c.saveSuccess(uid: 'u1', scope: _scope, cards: [_card('a'), _card('b'), _card('c')], fromCompleteSuccess: true);
      final s = await c.read(uid: 'u1', scope: _scope);
      expect(s!.cards.map((x) => x.toId), ['a', 'b']);
      expect(s.savedAt, t0);
      final src = _code('lib/services/home_recommend_cache.dart');
      // [impl_12 의도적 갱신 · 판정291 D291-02] 공개 사업장 대표사진 `imageUrl` 하나만 조건부 허용(출처·경로 검사 생성자).
      //   그 밖의 URL·사람 정보·숫자 필드는 여전히 0 이다.
      final card = src
          .substring(src.indexOf('class HomeRecommendCard'), src.indexOf('class HomeRecommendSnapshot'))
          .replaceAll('final String? imageUrl;', '');
      for (final banned in ['Url', 'url', 'uid', 'phone', 'count', 'applicant', 'contract', 'wage:']) {
        expect(RegExp('final \\w+ ${RegExp.escape(banned)}|final String\\? \\w*$banned').hasMatch(card), isFalse,
            reason: '표시 DTO 에 $banned');
      }
      expect(card.contains('isAllowedImageUrl(imageUrl)'), isTrue, reason: '사진 URL 은 출처·경로 검사를 거쳐서만 들어온다');
    });

    test('RC-2 다른 uid · 범위(env/역할/지역/조회) 변경은 쓰지 않는다', () async {
      final c = HomeRecommendCache(clock: () => t0);
      await c.saveSuccess(uid: 'u1', scope: _scope, cards: [_card('a')], fromCompleteSuccess: true);
      expect(await c.read(uid: 'u2', scope: _scope), isNull);
      for (final s in const [
        HomeRecommendScope(env: 'other', role: 'USER', regionKey: '강남구', queryKey: 'none'),
        HomeRecommendScope(env: 'dev', role: 'BUSINESS_ADMIN', regionKey: '강남구', queryKey: 'none'),
        HomeRecommendScope(env: 'dev', role: 'USER', regionKey: '서초구', queryKey: 'none'),
        HomeRecommendScope(env: 'dev', role: 'USER', regionKey: '강남구', queryKey: '2026-11-30'),
      ]) {
        await c.saveSuccess(uid: 'u1', scope: _scope, cards: [_card('a')], fromCompleteSuccess: true);
        expect(await c.read(uid: 'u1', scope: s), isNull, reason: '$s');
        expect(await c.read(uid: 'u1', scope: _scope), isNull, reason: '조건이 바뀐 값은 그 자리에서 지운다');
      }
    });

    test('RC-3 24시간 잠정 상한 · 시계 역행 · 손상 · 스키마 변경 → 버리고 지운다', () async {
      var now = t0;
      final store = _GateStore();
      final c = HomeRecommendCache(store: store, clock: () => now);
      await c.saveSuccess(uid: 'u1', scope: _scope, cards: [_card('a')], fromCompleteSuccess: true);
      now = t0.add(HomeRecommendCache.ttl);
      expect(await c.read(uid: 'u1', scope: _scope), isNotNull, reason: '경계 안');
      now = t0.add(HomeRecommendCache.ttl + const Duration(seconds: 1));
      expect(await c.read(uid: 'u1', scope: _scope), isNull, reason: '만료');
      expect(store.debugLength, 0);
      now = t0;
      await c.saveSuccess(uid: 'u1', scope: _scope, cards: [_card('a')], fromCompleteSuccess: true);
      now = t0.subtract(const Duration(minutes: 1));
      expect(await c.read(uid: 'u1', scope: _scope), isNull, reason: '시계 역행');
      now = t0;
      // [impl_12 의도적 갱신 · C291-P2] 키에 세대 namespace 가 붙었다 — 지금 키(debugKey)에 넣어야 손상을 실제로 시험한다.
      store.raw[c.debugKey('u1')] = '{"v":1,"uid":"u1"'; // 손상
      expect(await c.read(uid: 'u1', scope: _scope), isNull);
      store.raw[c.debugKey('u1')] =
          '{"v":0,"uid":"u1","scope":{"env":"dev","role":"USER","region":"강남구","query":"none"},"savedAtMs":${t0.millisecondsSinceEpoch},"cards":[{"toId":"a","title":"t","biz":"b","region":"r","date":"d","wage":"w"}]}';
      expect(await c.read(uid: 'u1', scope: _scope), isNull, reason: '옛 스키마');
    });

    test('RC-4 오류·부분·0장은 저장하지 않고, 최신 성공 0장은 옛 값을 지운다', () async {
      final c = HomeRecommendCache(clock: () => t0);
      await c.saveSuccess(uid: 'u1', scope: _scope, cards: [_card('a')], fromCompleteSuccess: false);
      expect(await c.read(uid: 'u1', scope: _scope), isNull, reason: '부분/오류 결과 저장 0');
      await c.saveSuccess(uid: 'u1', scope: _scope, cards: [_card('a')], fromCompleteSuccess: true);
      await c.saveSuccess(uid: 'u1', scope: _scope, cards: const [], fromCompleteSuccess: true);
      expect(await c.read(uid: 'u1', scope: _scope), isNull, reason: '정상 0 스냅샷을 만들거나 옛 추천을 남기지 않는다');
    });

    test('RC-5 로그아웃·전환·탈퇴(invalidateAll) 뒤 늦은 write 는 값을 되살리지 못한다', () async {
      final store = _GateStore();
      final c = HomeRecommendCache(store: store, clock: () => t0);
      store.holdSet = Completer<void>();
      final late = c.saveSuccess(uid: 'u1', scope: _scope, cards: [_card('a')], fromCompleteSuccess: true);
      await Future<void>.delayed(Duration.zero);
      expect(await c.invalidateAll(), isTrue);
      store.holdSet!.complete();
      await late;
      store.holdSet = null;
      expect(store.debugLength, 0, reason: '삭제 뒤 늦게 끝난 저장이 파일(값)을 다시 만들었다');
      expect(await c.read(uid: 'u1', scope: _scope), isNull);
    });

    test('RC-6 삭제 실패는 성공으로 보고하지 않고, 진행 중 저장도 무효화한다', () async {
      final store = _GateStore()..failRemove = true;
      final c = HomeRecommendCache(store: store, clock: () => t0);
      final e0 = c.debugEpoch;
      expect(await c.invalidateAll(), isFalse);
      expect(c.debugEpoch, e0 + 1, reason: '실패해도 세대는 올라간다');
    });

    test('RC-7 기본 저장소는 RAM — 새 인스턴스(재시작)는 비어 있다', () async {
      final a = HomeRecommendCache(clock: () => t0);
      await a.saveSuccess(uid: 'u1', scope: _scope, cards: [_card('a')], fromCompleteSuccess: true);
      final b = HomeRecommendCache(clock: () => t0);
      expect(await b.read(uid: 'u1', scope: _scope), isNull);
      final src = _code('lib/services/home_recommend_cache.dart');
      expect(src.contains('SharedPreferences'), isFalse, reason: '디스크 조건 확인 전 디스크 저장 0');
      expect(src.contains('path_provider'), isFalse);
    });
  });
}
