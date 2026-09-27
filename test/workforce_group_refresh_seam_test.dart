import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:ALfit/controllers/workforce_controller.dart';
import 'package:ALfit/models/core/to_model.dart';
import 'package:ALfit/models/ui/admin_to_list_ui_models.dart';
import 'package:ALfit/services/firestore_service.dart';

/// [R7-4 §3C] 실제 [WorkforceController] 를 돌려서 본다.
///
///   사용자가 반복해서 본 것은 `9/29 = 1/1` → 다른 날짜 → 돌아오니 `0/1`
///   같은 장면이다. 그런 장면은 대개 **늦게 온 응답이 최신 상태를 덮을 때**
///   생긴다. 그래서 순수 helper 만 따로 부르지 않고, controller 의 세대 토큰·
///   stale 판정·목록 교체·리스너 통지를 그대로 태운다.
///
///   서버 읽기 두 곳만 주입한다. 그 외는 production 코드 그대로다.

TOModel _to(String id, {int totalConfirmed = 1, bool flex = true}) => TOModel(
      id: id,
      businessId: 'biz1',
      businessName: '테스트 사업장',
      type: flex ? 'flex' : 'contract',
      title: '공고 $id',
      creatorUID: 'uid1',
      status: 'ACTIVE',
      workDetails: const [],
      totalRequired: 1,
      totalConfirmed: totalConfirmed,
      totalPending: 0,
      isPublished: true,
      publishMode: 'immediate',
      createdAt: DateTime(2026, 9, 1),
      statusUpdatedAt: DateTime(2026, 9, 1),
    );

const FlexSlotLoad _emptySlots =
    (groupTOs: <TOItem>[], slotDates: <DateTime>[]);

void main() {
  group('WGR-A 늦게 온 응답이 최신을 덮지 않는다', () {
    test('A-1 빠른 연속 갱신 — 먼저 요청한 쪽이 늦게 와도 superseded', () async {
      final gate1 = Completer<({TOModel? to, bool failed})>();
      final gate2 = Completer<({TOModel? to, bool failed})>();
      var call = 0;

      final c = WorkforceController(
        loadTO: (toId) {
          call++;
          return call == 1 ? gate1.future : gate2.future;
        },
        loadSlots: (toId, {TOModel? masterTO}) async => _emptySlots,
      );
      c.seedItemsForTest([TOGroupItem(singleTO: _to('to1', totalConfirmed: 1))]);

      final first = c.refreshGroup('to1');   // 9/29 선택
      final second = c.refreshGroup('to1');  // 곧바로 9/30 선택

      // 응답이 **뒤집혀** 도착한다 — 나중 요청이 먼저 온다.
      gate2.complete((to: _to('to1', totalConfirmed: 7), failed: false));
      expect(await second, TOGroupRefreshOutcome.refreshed);

      gate1.complete((to: _to('to1', totalConfirmed: 99), failed: false));
      expect(await first, TOGroupRefreshOutcome.superseded,
          reason: '늦게 온 첫 응답은 버려야 한다');

      expect(c.items.single.masterTO.totalConfirmed, 7,
          reason: '99 가 들어왔으면 화면이 과거로 되돌아간 것이다');
      c.dispose();
    });

    test('A-2 돌아왔을 때 같은 값이면 같은 값이다', () async {
      var n = 0;
      final c = WorkforceController(
        loadTO: (toId) async => (to: _to('to1', totalConfirmed: ++n), failed: false),
        loadSlots: (toId, {TOModel? masterTO}) async => _emptySlots,
      );
      c.seedItemsForTest([TOGroupItem(singleTO: _to('to1'))]);

      await c.refreshGroup('to1');
      final a = c.items.single.masterTO.totalConfirmed;
      await c.refreshGroup('to1');
      await c.refreshGroup('to1');
      final b = c.items.single.masterTO.totalConfirmed;

      expect(a, 1);
      expect(b, 3, reason: '매 갱신이 서버가 준 값을 그대로 반영한다');
      c.dispose();
    });
  });

  group('WGR-B 실패를 0 으로 커밋하지 않는다', () {
    test('B-1 읽기 실패 — 기존 목록을 그대로 둔다', () async {
      final c = WorkforceController(
        loadTO: (toId) async => (to: null, failed: true),
        loadSlots: (toId, {TOModel? masterTO}) async => _emptySlots,
      );
      c.seedItemsForTest([TOGroupItem(singleTO: _to('to1', totalConfirmed: 5))]);

      expect(await c.refreshGroup('to1'), TOGroupRefreshOutcome.failed);
      expect(c.items.length, 1, reason: '실패로 목록을 비우면 그것도 EMPTY 다');
      expect(c.items.single.masterTO.totalConfirmed, 5);
      c.dispose();
    });

    test('B-2 실패 → 재시도 성공이면 최신으로 바뀐다', () async {
      var attempt = 0;
      final c = WorkforceController(
        loadTO: (toId) async {
          attempt++;
          if (attempt == 1) return (to: null, failed: true);
          return (to: _to('to1', totalConfirmed: 4), failed: false);
        },
        loadSlots: (toId, {TOModel? masterTO}) async => _emptySlots,
      );
      c.seedItemsForTest([TOGroupItem(singleTO: _to('to1', totalConfirmed: 5))]);

      expect(await c.refreshGroup('to1'), TOGroupRefreshOutcome.failed);
      expect(await c.refreshGroup('to1'), TOGroupRefreshOutcome.refreshed);
      expect(c.items.single.masterTO.totalConfirmed, 4);
      c.dispose();
    });

    test('B-3 예외를 던져도 실패로 다루고 기존 목록을 지킨다', () async {
      final c = WorkforceController(
        loadTO: (toId) async => throw StateError('network'),
        loadSlots: (toId, {TOModel? masterTO}) async => _emptySlots,
      );
      c.seedItemsForTest([TOGroupItem(singleTO: _to('to1', totalConfirmed: 5))]);

      expect(await c.refreshGroup('to1'), TOGroupRefreshOutcome.failed);
      expect(c.items.single.masterTO.totalConfirmed, 5);
      c.dispose();
    });

    test('B-4 문서가 없어진 것과 읽기 실패는 다른 결과다', () async {
      final c = WorkforceController(
        loadTO: (toId) async => (to: null, failed: false),
        loadSlots: (toId, {TOModel? masterTO}) async => _emptySlots,
      );
      c.seedItemsForTest([TOGroupItem(singleTO: _to('to1'))]);

      expect(await c.refreshGroup('to1'), TOGroupRefreshOutcome.removed);
      expect(c.items, isEmpty);
      c.dispose();
    });
  });

  group('WGR-C dispose 와 목록 밖', () {
    test('C-1 응답 도착 전에 닫히면 아무것도 쓰지 않는다', () async {
      final gate = Completer<({TOModel? to, bool failed})>();
      final c = WorkforceController(
        loadTO: (toId) => gate.future,
        loadSlots: (toId, {TOModel? masterTO}) async => _emptySlots,
      );
      c.seedItemsForTest([TOGroupItem(singleTO: _to('to1', totalConfirmed: 5))]);

      final f = c.refreshGroup('to1');
      c.dispose(); // 다이얼로그를 닫았다
      gate.complete((to: _to('to1', totalConfirmed: 42), failed: false));

      expect(await f, TOGroupRefreshOutcome.superseded);
      expect(c.items.single.masterTO.totalConfirmed, 5,
          reason: 'dispose 뒤에 상태를 건드리면 안 된다');
    });

    test('C-2 목록에 없는 공고는 "없음"으로 단정하지 않는다', () async {
      var called = false;
      final c = WorkforceController(
        loadTO: (toId) async { called = true; return (to: null, failed: false); },
        loadSlots: (toId, {TOModel? masterTO}) async => _emptySlots,
      );
      c.seedItemsForTest([TOGroupItem(singleTO: _to('to1'))]);

      expect(await c.refreshGroup('to-없는것'), TOGroupRefreshOutcome.notInList);
      expect(called, isFalse, reason: '읽으러 가지도 않는다');
      expect(c.items.length, 1);
      c.dispose();
    });
  });

  group('WGR-D 뷰가 갱신을 알아챌 수 있다', () {
    test('D-1 목록은 새 인스턴스로 교체된다 — 제자리 수정이 아니다', () async {
      final c = WorkforceController(
        loadTO: (toId) async => (to: _to('to1', totalConfirmed: 3), failed: false),
        loadSlots: (toId, {TOModel? masterTO}) async => _emptySlots,
      );
      c.seedItemsForTest([TOGroupItem(singleTO: _to('to1'))]);
      final before = c.items;

      await c.refreshGroup('to1');

      expect(identical(before, c.items), isFalse,
          reason: '뷰의 필터 캐시가 identical 로 무효화를 판단한다');
      c.dispose();
    });

    test('D-2 성공하면 리스너에게 알린다 / 실패하면 알리지 않는다', () async {
      var ok = 0;
      final okCtrl = WorkforceController(
        loadTO: (toId) async => (to: _to('to1', totalConfirmed: 3), failed: false),
        loadSlots: (toId, {TOModel? masterTO}) async => _emptySlots,
      )..seedItemsForTest([TOGroupItem(singleTO: _to('to1'))]);
      okCtrl.addListener(() => ok++);
      await okCtrl.refreshGroup('to1');
      expect(ok, greaterThan(0));
      okCtrl.dispose();

      var bad = 0;
      final failCtrl = WorkforceController(
        loadTO: (toId) async => (to: null, failed: true),
        loadSlots: (toId, {TOModel? masterTO}) async => _emptySlots,
      )..seedItemsForTest([TOGroupItem(singleTO: _to('to1'))]);
      failCtrl.addListener(() => bad++);
      await failCtrl.refreshGroup('to1');
      expect(bad, 0, reason: '바뀐 것이 없으면 다시 그릴 이유도 없다');
      failCtrl.dispose();
    });

    test('D-3 flex 공고는 슬롯까지 다시 읽는다', () async {
      var slotReads = 0;
      final c = WorkforceController(
        loadTO: (toId) async => (to: _to('to1', flex: true), failed: false),
        loadSlots: (toId, {TOModel? masterTO}) async {
          slotReads++;
          return _emptySlots;
        },
      );
      c.seedItemsForTest([TOGroupItem(singleTO: _to('to1'))]);
      await c.refreshGroup('to1');
      expect(slotReads, 1);
      c.dispose();
    });

    test('D-4 contract 공고는 슬롯을 읽지 않는다', () async {
      var slotReads = 0;
      final c = WorkforceController(
        loadTO: (toId) async => (to: _to('to1', flex: false), failed: false),
        loadSlots: (toId, {TOModel? masterTO}) async {
          slotReads++;
          return _emptySlots;
        },
      );
      c.seedItemsForTest([TOGroupItem(singleTO: _to('to1', flex: false))]);
      await c.refreshGroup('to1');
      expect(slotReads, 0);
      c.dispose();
    });
  });
}
