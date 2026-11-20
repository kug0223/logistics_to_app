import 'dart:async';
import 'dart:io';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ALfit/services/posting_quota_summary.dart';
import 'package:ALfit/widgets/admin/posting_quota_summary_bar.dart';

/// [POSTING-QUOTA-45] 공고 탭 한도 요약 — 저장소(요청 합치기·늦은 응답·실패)와 표시(상태·배치).
Map<String, Object?> scope(String token, List<String> ids, int used, int limit) => {
      'scopeToken': token, 'businessIds': ids, 'used': used, 'limit': limit,
      'remaining': (limit - used) < 0 ? 0 : limit - used, 'limitSource': 'default',
    };
Map<String, Object?> resp(List<Map<String, Object?>> scopes, {List<String> denied = const [], List<String> failed = const []}) =>
    {'scopes': scopes, 'denied': denied, 'failed': failed, 'checkedAtMs': 1};

PostingQuotaScope sc(int used, int limit, {List<String> ids = const ['a']}) =>
    PostingQuotaScope.tryFromMap(scope('t', ids, used, limit))!;

void main() {
  group('저장소', () {
    setUp(() {
      PostingQuotaStore.reset();
      PostingQuotaStore.fetchCount = 0;
    });

    test('QS-1 같은 집합 동시 요청 → 1회 · 재진입(이미 읽음) → 0회 · force → 1회', () async {
      PostingQuotaStore.fetch = (ids) async => resp([scope('t', ids, 3, 4)]);
      await Future.wait([
        PostingQuotaStore.ensure(uid: 'u', businessIds: ['b', 'a']),
        PostingQuotaStore.ensure(uid: 'u', businessIds: ['a', 'b']),
      ]);
      expect(PostingQuotaStore.fetchCount, 1);
      await PostingQuotaStore.ensure(uid: 'u', businessIds: ['a', 'b']);
      expect(PostingQuotaStore.fetchCount, 1);
      await PostingQuotaStore.ensure(uid: 'u', businessIds: ['a', 'b'], force: true);
      expect(PostingQuotaStore.fetchCount, 2);
      expect(PostingQuotaStore.current.value.value!.scopes.single.used, 3);
    });

    test('QS-2 전환 뒤 늦게 온 응답은 버린다 · 이전 집합의 숫자를 새 집합에 비추지 않는다', () async {
      final slow = Completer<Object?>();
      PostingQuotaStore.fetch = (ids) => ids.contains('a') ? slow.future : Future.value(resp([scope('c', ids, 0, 4)]));
      final fa = PostingQuotaStore.ensure(uid: 'u', businessIds: ['a']);
      await PostingQuotaStore.ensure(uid: 'u', businessIds: ['c']);
      expect(PostingQuotaStore.current.value.value!.scopes.single.scopeToken, 'c');
      slow.complete(resp([scope('a', ['a'], 4, 4)]));
      await fa;
      final v = PostingQuotaStore.current.value;
      expect(v.key, PostingQuotaStore.keyOf('u', ['c']));
      expect(v.value!.scopes.single.scopeToken, 'c');
    });

    test('QS-3 실패·형식 오류 → failed, 숫자 없음(0·기본값으로 메우지 않음)', () async {
      PostingQuotaStore.fetch = (ids) async => throw Exception('net');
      await PostingQuotaStore.ensure(uid: 'u', businessIds: ['a']);
      expect(PostingQuotaStore.current.value.status, PostingQuotaStatus.failed);
      expect(PostingQuotaStore.current.value.value, isNull);
      PostingQuotaStore.fetch = (ids) async => {'scopes': [{'scopeToken': 't', 'businessIds': ['a'], 'used': 1}]};
      await PostingQuotaStore.ensure(uid: 'u', businessIds: ['a'], force: true);
      expect(PostingQuotaStore.current.value.status, PostingQuotaStatus.failed);
      expect(PostingQuotaStore.current.value.value, isNull);
    });

    test('QS-4 사업장 21곳 → 20개씩 2회, 같은 범위는 하나로 합친다', () async {
      final ids = [for (var i = 0; i < 21; i++) 'b${i.toString().padLeft(2, '0')}'];
      PostingQuotaStore.fetch = (part) async => resp([scope('same', part, 2, 4)]);
      await PostingQuotaStore.ensure(uid: 'u', businessIds: ids);
      expect(PostingQuotaStore.fetchCount, 2);
      final s = PostingQuotaStore.current.value.value!.scopes.single;
      expect(s.businessIds.length, 21);
      expect(s.used, 2);
    });

    test('QS-5 읽는 중 다시 읽기는 새 읽기로 대체 — 앞 읽기의 늦은 결과는 버린다(대기 합산 없음)', () async {
      final first = Completer<Object?>();
      var n = 0;
      PostingQuotaStore.fetch = (ids) { n++; return n == 1 ? first.future : Future.value(resp([scope('t', ids, 4, 4)])); };
      final f0 = PostingQuotaStore.ensure(uid: 'u', businessIds: ['a']);
      final f1 = PostingQuotaStore.ensure(uid: 'u', businessIds: ['a'], force: true);
      await f1;
      expect(PostingQuotaStore.current.value.value!.scopes.single.used, 4);
      first.complete(resp([scope('t', ['a'], 3, 4)]));
      await f0;
      expect(n, 2);
      expect(PostingQuotaStore.current.value.value!.scopes.single.used, 4, reason: '늦게 끝난 앞 읽기가 회복된 값을 덮었다');
    });

    group('[.46] 대기 상한·늦은 응답·전환', () {
      setUp(() => PostingQuotaStore.budget = const Duration(milliseconds: 60));
      tearDown(() => PostingQuotaStore.budget = const Duration(seconds: 30));

      test('QT-1 즉시 실패(연결 거절 등) → 상한을 기다리지 않고 확인 불가', () async {
        PostingQuotaStore.fetch = (ids) async => throw FirebaseFunctionsException(code: 'unavailable', message: 'x');
        final sw = Stopwatch()..start();
        await PostingQuotaStore.ensure(uid: 'u', businessIds: ['a']);
        expect(sw.elapsedMilliseconds, lessThan(50));
        expect(PostingQuotaStore.current.value.status, PostingQuotaStatus.failed);
      });

      test('QT-2 권한 거절은 즉시 denied 로 구분(숫자·확인 불가 모두 아님)', () async {
        PostingQuotaStore.fetch = (ids) async => throw FirebaseFunctionsException(code: 'permission-denied', message: 'x');
        await PostingQuotaStore.ensure(uid: 'u', businessIds: ['a']);
        expect(PostingQuotaStore.current.value.status, PostingQuotaStatus.denied);
        expect(PostingQuotaStore.current.value.value, isNull);
      });

      test('QT-3 응답 없는 연결 → 상한에서 확인 불가, 나눠 묻기 전체가 한 상한', () async {
        final ids = [for (var i = 0; i < 25; i++) 'b$i'];
        var calls = 0;
        PostingQuotaStore.fetch = (part) { calls++; return calls == 1 ? Future.delayed(const Duration(milliseconds: 40), () => resp([scope('t', part, 1, 4)])) : Completer<Object?>().future; };
        final sw = Stopwatch()..start();
        await PostingQuotaStore.ensure(uid: 'u', businessIds: ids);
        expect(sw.elapsedMilliseconds, lessThan(110), reason: '묶음마다 상한을 새로 주면 합계가 늘어난다');
        expect(PostingQuotaStore.current.value.status, PostingQuotaStatus.failed);
        expect(PostingQuotaStore.current.value.value, isNull);
      });

      test('QT-4 시간 초과 → 다시 시도 성공 → 늦게 도착한 첫 응답이 회복 값을 덮지 않는다', () async {
        final hung = Completer<Object?>();
        var n = 0;
        PostingQuotaStore.fetch = (ids) { n++; return n == 1 ? hung.future : Future.value(resp([scope('t', ids, 2, 4)])); };
        await PostingQuotaStore.ensure(uid: 'u', businessIds: ['a']);
        expect(PostingQuotaStore.current.value.status, PostingQuotaStatus.failed);
        await PostingQuotaStore.ensure(uid: 'u', businessIds: ['a'], force: true);
        expect(PostingQuotaStore.current.value.value!.scopes.single.used, 2);
        hung.complete(resp([scope('t', ['a'], 9, 4)]));
        await Future<void>.delayed(const Duration(milliseconds: 10));
        expect(PostingQuotaStore.current.value.value!.scopes.single.used, 2);
      });

      test('QT-5 소유자 전환 — 이전 소유자 응답이 늦게 와도 새 소유자 숫자를 덮지 않는다, 같은 소유자 재전환은 공유 숫자', () async {
        final slowO1 = Completer<Object?>();
        PostingQuotaStore.fetch = (ids) => ids.first == 'o1biz' ? slowO1.future : Future.value(resp([scope('o2', ids, 0, 6)]));
        final f = PostingQuotaStore.ensure(uid: 'sub', businessIds: ['o1biz']);
        await PostingQuotaStore.ensure(uid: 'sub', businessIds: ['o2biz']);
        slowO1.complete(resp([scope('o1', ['o1biz'], 4, 4)]));
        await f;
        expect(PostingQuotaStore.current.value.value!.scopes.single.scopeToken, 'o2');
        expect(PostingQuotaStore.current.value.value!.scopes.single.limit, 6);
      });

      test('QT-6 다른 계정으로 바뀌면 이전 계정의 늦은 응답은 버린다', () async {
        final slow = Completer<Object?>();
        PostingQuotaStore.fetch = (ids) => slow.future;
        final f = PostingQuotaStore.ensure(uid: 'u1', businessIds: ['a']);
        PostingQuotaStore.reset();
        slow.complete(resp([scope('t', ['a'], 4, 4)]));
        await f;
        expect(PostingQuotaStore.current.value.status, PostingQuotaStatus.idle);
      });
    });

    test('QS-6 refreshLast 는 마지막 집합을 다시 읽는다(한도 거절 뒤)', () async {
      PostingQuotaStore.fetch = (ids) async => resp([scope('t', ids, PostingQuotaStore.fetchCount, 4)]);
      await PostingQuotaStore.ensure(uid: 'u', businessIds: ['a']);
      await PostingQuotaStore.refreshLast();
      expect(PostingQuotaStore.fetchCount, 2);
    });
  });

  group('표시', () {
    Future<void> pump(WidgetTester t, PostingQuotaSnapshot snap, {String? sel, double width = 392, double scale = 1.0, VoidCallback? onShow}) async {
      t.view.physicalSize = Size(width * 2.75, 851 * 2.75);
      t.view.devicePixelRatio = 2.75;
      addTearDown(t.view.reset);
      await t.pumpWidget(MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(size: Size(width, 851), textScaler: TextScaler.linear(scale)),
          child: Scaffold(
            body: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 12, 10),
              child: PostingQuotaSummaryBar(
                snapshot: snap,
                selectedBusinessId: sel,
                businessNameOf: (id) => id == 'a' ? '합성 물류센터 본점' : '다른 소유자 사업장',
                onRetry: () {},
                onShowActivePostings: onShow ?? () {},
              ),
            ),
          ),
        ),
      ));
    }

    PostingQuotaSnapshot loaded(List<Map<String, Object?>> scopes, {List<String> denied = const [], List<String> failed = const []}) =>
        PostingQuotaSnapshot(status: PostingQuotaStatus.loaded, key: 'u|a',
            value: PostingQuotaResult.tryFromMap(resp(scopes, denied: denied, failed: failed)));

    test('QB-1 문장 — 0/4 · 3/4 · 4/4 · 5/4(하향)', () {
      expect(PostingQuotaSummaryBar.sentenceOf(sc(0, 4)), '진행 중 공고 0 / 4개 · 4개 더 등록할 수 있어요 · 관리자·서브관리자 공용 한도');
      expect(PostingQuotaSummaryBar.sentenceOf(sc(3, 4)), '진행 중 공고 3 / 4개 · 1개 더 등록할 수 있어요 · 관리자·서브관리자 공용 한도');
      expect(PostingQuotaSummaryBar.sentenceOf(sc(4, 4)), '진행 중 공고 4 / 4개 · 한도에 도달했어요 · 관리자·서브관리자 공용 한도');
      expect(PostingQuotaSummaryBar.sentenceOf(sc(5, 4)), '진행 중 공고 5 / 4개 · 한도가 낮아져 새 공고는 등록할 수 없어요 · 관리자·서브관리자 공용 한도');
    });

    testWidgets('QB-2 한도 도달 → 진행 중 공고 보기 · 화면 읽기는 한 번', (t) async {
      var shown = 0;
      await pump(t, loaded([scope('t', ['a'], 4, 4)]), onShow: () => shown++);
      expect(find.bySemanticsLabel(RegExp(r'^진행 중 공고 4 / 4개')), findsOneWidget);
      await t.tap(find.byType(TextButton));
      expect(shown, 1);
    });

    testWidgets('QB-3 3/4 에는 보기 링크가 없다 · 등록 가능 문장', (t) async {
      await pump(t, loaded([scope('t', ['a'], 3, 4)]));
      expect(find.byType(TextButton), findsNothing);
      expect(find.bySemanticsLabel(RegExp('1개 더 등록할 수 있어요')), findsOneWidget);
    });

    testWidgets('QB-4 조회 실패 → 한도 확인 불가 + 다시 시도, 숫자 0·4 없음', (t) async {
      await pump(t, const PostingQuotaSnapshot(status: PostingQuotaStatus.failed, key: 'u|a'));
      expect(find.bySemanticsLabel('공고 한도 확인 불가'), findsOneWidget);
      expect(find.byType(TextButton), findsOneWidget);
      final all = t.widgetList<Text>(find.byType(Text)).map((w) => w.data ?? '').join();
      expect(RegExp(r'[0-9]').hasMatch(all), isFalse);
    });

    testWidgets('QB-5 고른 사업장이 권한 없음(denied) → 아무것도 그리지 않는다(권한 안내는 탭이 한다)', (t) async {
      await pump(t, loaded([scope('t', ['a'], 3, 4)], denied: ['b']), sel: 'b');
      expect(find.byType(Text), findsNothing);
    });

    testWidgets('QB-5b 호출 자체 권한 거절(denied) → 아무것도 그리지 않는다', (t) async {
      await pump(t, const PostingQuotaSnapshot(status: PostingQuotaStatus.denied, key: 'u|a'));
      expect(find.byType(Text), findsNothing);
    });

    testWidgets('QB-6 소유자가 다른 두 범위 → 줄 2개, 분모를 합치지 않는다', (t) async {
      await pump(t, loaded([scope('t1', ['a'], 3, 4), scope('t2', ['c'], 0, 6)]));
      expect(find.bySemanticsLabel(RegExp(r'^합성 물류센터 본점 · 진행 중 공고 3 / 4개')), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp(r'^다른 소유자 사업장 · 진행 중 공고 0 / 6개')), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp(r'3 / 10|/ 10개')), findsNothing);
      expect(find.bySemanticsLabel(RegExp('공용 한도')), findsOneWidget);
    });

    testWidgets('QB-7 고른 사업장만 · 일부 사업장 실패는 따로 알린다', (t) async {
      await pump(t, loaded([scope('t1', ['a'], 3, 4)], failed: ['c']));
      expect(find.bySemanticsLabel('일부 사업장은 공고 한도 확인 불가'), findsOneWidget);
      await pump(t, loaded([scope('t1', ['a'], 3, 4)], failed: ['c']), sel: 'a');
      expect(find.bySemanticsLabel('일부 사업장은 공고 한도 확인 불가'), findsNothing);
      await pump(t, loaded([scope('t1', ['a'], 3, 4)], failed: ['c']), sel: 'c');
      expect(find.bySemanticsLabel('공고 한도 확인 불가'), findsOneWidget);
    });

    for (final (w, s) in [(392.0, 1.0), (320.0, 1.3), (392.0, 2.0)]) {
      testWidgets('QB-8 배치 $w·$s — 넘침 없음 · 글자 축소 없음', (t) async {
        await pump(t, loaded([scope('t', ['a'], 4, 4)]), width: w, scale: s);
        expect(t.takeException(), isNull);
        expect(find.byType(FittedBox), findsNothing);
        await pump(t, loaded([scope('t1', ['a'], 5, 4), scope('t2', ['c'], 0, 4)]), width: w, scale: s);
        expect(t.takeException(), isNull);
        await pump(t, const PostingQuotaSnapshot(status: PostingQuotaStatus.failed, key: 'u|a'), width: w, scale: s);
        expect(t.takeException(), isNull);
      });
    }
  });

  group('연결(소스)', () {
    test('QW-1 공고 탭은 목록 읽기 끝에 한도를 다시 묻고, SUPER_ADMIN·범위 모름이면 묻지 않는다', () {
      final src = File('lib/screens/business_admin/jobs_root_screen.dart').readAsStringSync();
      expect(src.contains('if (!_wasLoading && loading) _ensureQuota(force: true);'), isTrue);
      expect(src.contains('if (_wasLoading && !loading) _ensureQuota();'), isTrue);
      expect(src.contains('if (user == null || user.isSuperAdmin) return const [];'), isTrue);
      expect(src.contains('if (up.isSubAdmin) return _controller.requestedScope ?? const [];'), isTrue);
    });
    test('QW-2 한도 거절 3지점(생성·수정·공개)에서 요약을 다시 읽는다 · 목록 항목을 세지 않는다', () {
      final svc = File('lib/services/firestore/to_firestore.dart').readAsStringSync();
      expect('_refreshQuotaOnLimit(e);'.allMatches(svc).length, 3);
      final bar = File('lib/widgets/admin/posting_quota_summary_bar.dart').readAsStringSync();
      expect(bar.contains('items'), isFalse);
    });
  });
}
