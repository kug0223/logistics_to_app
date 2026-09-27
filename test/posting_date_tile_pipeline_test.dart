import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:ALfit/controllers/workforce_controller.dart';
import 'package:ALfit/models/core/slot_model.dart';
import 'package:ALfit/models/core/to_model.dart';
import 'package:ALfit/models/core/work_detail_data.dart';
import 'package:ALfit/models/ui/admin_to_list_ui_models.dart';
import 'package:ALfit/models/ui/group_header_totals.dart';

/// [R7-6 §5] 사용자가 보고한 그 순서를 실제 owner 로 돌린다.
///
///   `9/29 타일 1/1` → 선택 → 상세 `1/1` → `9/30 = 0/1` → `9/29` 복귀 →
///   다이얼로그 열고 닫기 → 탭 복귀.
///
///   파이프라인은 이렇다: 타일을 고르면 부모가 `selectedDate`/`calendarSlot` 을
///   바꾸고, `WorkforceController.loadWorkDetails(slot)` 가 집계를 읽어
///   **그 TOItem 인스턴스 안에** 채우고(제자리 수정), 부모가 다시 그리면
///   카드가 `projectGroupHeaderTotals` 로 머리말을 다시 만든다.
///
///   여기서는 그 controller 와 그 projection 을 **그대로** 쓴다. 읽기 하나만
///   주입한다. 화면을 복제한 테스트용 위젯을 만들지 않는다.
///
///   위젯 렌더 자체(`TOGroupCard`)는 Provider·FirestoreService 결합으로
///   이 층에서 실행하지 않는다 — 그 범위는 보고서에 명시한다.

TOModel _to(String id, {int totalConfirmed = 0, int totalRequired = 1}) => TOModel(
      id: id,
      businessId: 'biz1',
      businessName: '테스트 사업장',
      type: 'flex',
      title: '테스트 공고',
      creatorUID: 'uid1',
      status: 'ACTIVE',
      workDetails: const [],
      totalRequired: totalRequired,
      totalConfirmed: totalConfirmed,
      totalPending: 0,
      isPublished: true,
      publishMode: 'immediate',
      createdAt: DateTime(2026, 9, 1),
      statusUpdatedAt: DateTime(2026, 9, 1),
    );

WorkDetailData _wd(String wdId, {int requiredCount = 1}) => WorkDetailData(
      wdId: wdId,
      workType: '홀서빙',
      startTime: '09:00',
      endTime: '18:00',
      requiredCount: requiredCount,
      wage: 12000,
      wageType: 'hourly',
    );

/// 날짜 하나의 슬롯 item. 카운터만 들고 시작한다(집계는 아직 안 읽었다).
TOItem _slot(String slotId, DateTime date, {required int confirmed}) => TOItem(
      to: _to('to1', totalConfirmed: confirmed),
      slot: SlotModel(
        id: slotId,
        toId: 'to1',
        date: date,
        workDetails: [_wd('wd-$slotId')],
      ),
      confirmedCount: confirmed,
      pendingCount: 0,
      totalRequired: 1,
    );

Map<String, dynamic> _statsResult(String slotId,
        {required int confirmed, int pending = 0, bool failed = false}) =>
    {
      'workDetails': [_wd('wd-$slotId')],
      'workStats': {
        'wd-$slotId': {'confirmed': confirmed, 'pending': pending}
      },
      'statsFailed': failed,
    };

/// 부모가 선택한 날짜로 카드가 보는 대상. 카드의 `_updateGroupCache` 와 같은 규칙.
GroupHeaderTotals _header(List<TOItem> all, DateTime? selected) {
  final targets = selected == null
      ? all
      : all
          .where((t) =>
              t.slot!.date.year == selected.year &&
              t.slot!.date.month == selected.month &&
              t.slot!.date.day == selected.day)
          .toList();
  return projectGroupHeaderTotals(
    targetTOs: targets,
    singleFallback: () => all.first,
  );
}

void main() {
  final d929 = DateTime(2026, 9, 29);
  final d930 = DateTime(2026, 9, 30);

  group('PDT-A 원래 재현 순서', () {
    test('A-1 9/29=1/1 → 선택 → 상세 1/1 → 9/30=0/1 → 9/29 복귀 1/1', () async {
      final s929 = _slot('0929', d929, confirmed: 1);
      final s930 = _slot('0930', d930, confirmed: 0);
      final all = [s929, s930];

      final loads = <String>[];
      final c = WorkforceController(
        loadWorkDetailStats: (to, {slotId, slotWorkDetails}) async {
          loads.add(slotId!);
          return _statsResult(slotId, confirmed: slotId == '0929' ? 1 : 0);
        },
      );

      // 목록 상태 — 아직 집계 없음. 타일이 카운터로 1/1 을 말한다.
      expect(_header(all, d929).confirmed, 1);
      expect(_header(all, d929).required, 1);

      // 9/29 선택 → 상세 로드 (실제 controller 가 제자리 수정한다)
      await c.loadWorkDetails(s929);
      expect(loads, ['0929']);
      final h929 = _header(all, d929);
      expect(h929.confirmed, 1, reason: '선택 후에도 1 이어야 한다 — 0 이 되면 그 증상이다');
      expect(h929.isFull, isTrue);
      // 같은 snapshot 에서 업무 상세도 같은 값을 말한다
      expect(s929.resolveStats().confirmed, 1);

      // 9/30 선택
      await c.loadWorkDetails(s930);
      final h930 = _header(all, d930);
      expect(h930.confirmed, 0);
      expect(h930.required, 1);
      expect(h930.shortage, 1);

      // 9/29 복귀 — 되돌아가도 1/1
      final back = _header(all, d929);
      expect(back.confirmed, 1);
      expect(back.required, 1);

      // 다이얼로그 열고 닫기 · 탭 복귀 = 같은 인스턴스를 다시 읽는다.
      // `needsWorkDetailLoad` 가 false 이므로 재조회하지 않고, 값도 그대로다.
      await c.loadWorkDetails(s929);
      expect(loads, ['0929', '0930'], reason: '이미 읽은 것을 다시 읽지 않는다');
      expect(_header(all, d929).confirmed, 1);
      expect(_header(all, d930).confirmed, 0);

      // 전체(날짜 미선택) 요약은 두 날짜의 합이다 — 날짜별과 어긋나지 않는다.
      final summary = _header(all, null);
      expect(summary.confirmed, 1);
      expect(summary.required, 2);
      expect(summary.shortage, 1);
      c.dispose();
    });

    test('A-2 새 정상 응답은 반영된다 — 카운터가 아니라 집계를 말한다', () async {
      final s = _slot('0929', d929, confirmed: 1);
      final c = WorkforceController(
        loadWorkDetailStats: (to, {slotId, slotWorkDetails}) async =>
            _statsResult(slotId!, confirmed: 0),
      );
      expect(_header([s], d929).confirmed, 1, reason: '집계 전에는 카운터');
      await c.loadWorkDetails(s);
      expect(_header([s], d929).confirmed, 0,
          reason: '집계가 0 이라고 하면 머리말도 0 이다');
      expect(_header([s], d929).shortage, 1);
      c.dispose();
    });
  });

  group('PDT-B 빠른 전환·응답 역전·실패 재시도', () {
    test('B-1 응답이 뒤집혀 도착해도 날짜별 값이 섞이지 않는다', () async {
      final s929 = _slot('0929', d929, confirmed: 1);
      final s930 = _slot('0930', d930, confirmed: 0);
      final g929 = Completer<Map<String, dynamic>>();
      final g930 = Completer<Map<String, dynamic>>();

      final c = WorkforceController(
        loadWorkDetailStats: (to, {slotId, slotWorkDetails}) =>
            slotId == '0929' ? g929.future : g930.future,
      );

      final f929 = c.loadWorkDetails(s929); // 9/29 먼저 시작
      final f930 = c.loadWorkDetails(s930); // 곧바로 9/30

      // 나중 요청이 먼저 도착한다
      g930.complete(_statsResult('0930', confirmed: 0, pending: 2));
      await f930;
      g929.complete(_statsResult('0929', confirmed: 1));
      await f929;

      expect(_header([s929, s930], d929).confirmed, 1);
      expect(_header([s929, s930], d930).confirmed, 0);
      expect(s930.resolveStats().pending, 2);
      expect(s929.resolveStats().pending, 0,
          reason: '9/30 의 대기 2 가 9/29 로 새면 안 된다');
      c.dispose();
    });

    test('B-2 로드 실패는 0 이 아니라 카운터로 떨어지고, 재시도가 반영된다', () async {
      final s = _slot('0929', d929, confirmed: 1);
      var attempt = 0;
      final c = WorkforceController(
        loadWorkDetailStats: (to, {slotId, slotWorkDetails}) async {
          attempt++;
          if (attempt == 1) throw StateError('network');
          return _statsResult(slotId!, confirmed: 0);
        },
      );

      await c.loadWorkDetails(s);
      expect(s.workDetailStatsFailed, isTrue);
      expect(_header([s], d929).confirmed, 1,
          reason: '실패를 확정 0 으로 커밋하지 않는다');

      // 재시도 — 실패 후에는 다시 읽을 수 있어야 한다
      await c.loadWorkDetails(s);
      expect(attempt, 2, reason: '실패한 로드는 재시도 가능해야 한다');
      expect(_header([s], d929).confirmed, 0);
      expect(s.workDetailStatsFailed, isFalse);
      c.dispose();
    });

    test('B-3 dispose 후 도착한 응답이 상태를 바꾸지 않는다', () async {
      final s = _slot('0929', d929, confirmed: 1);
      final gate = Completer<Map<String, dynamic>>();
      var notified = 0;
      final c = WorkforceController(
        loadWorkDetailStats: (to, {slotId, slotWorkDetails}) => gate.future,
      );
      c.addListener(() => notified++);
      final f = c.loadWorkDetails(s);
      c.dispose();
      gate.complete(_statsResult('0929', confirmed: 0));
      await f;
      expect(notified, 0, reason: 'dispose 뒤에 알리지 않는다');
      c.dispose;
    });
  });
}
