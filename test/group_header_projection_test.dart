import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ALfit/models/core/slot_model.dart';
import 'package:ALfit/models/core/to_model.dart';
import 'package:ALfit/models/core/work_detail_data.dart';
import 'package:ALfit/models/ui/admin_to_list_ui_models.dart';
import 'package:ALfit/models/ui/group_header_totals.dart';

/// [R7-5 §7] 공고 카드 머리말과 업무 행이 갈라지는 자리.
///
///   사용자가 본 것: 날짜 타일이 `1/1` 이었다가 그 날짜를 고르면 `0/1` 이 되고,
///   위쪽 요약은 `1` 을 그대로 붙들고 있었다.
///
///   두 축이 있다.
///     1) **무엇을 계산하는가** — 머리말 수치 projection. 여기서 실행해 본다.
///     2) **언제 다시 계산하는가** — 카드의 `didUpdateWidget` 캐시 무효화.
///        정원 집계는 같은 인스턴스 안에 채워지므로(`setWorkDetails` 는 제자리
///        수정) `identical` 로 거르면 갱신이 일어나지 않는다.

String _src(String p) => File(p).readAsStringSync();
String _codeOf(String b) => b
    .split('\n')
    .where((l) => !l.trimLeft().startsWith('//'))
    .join('\n');

const _cardPath = 'lib/widgets/admin/cards/admin_to_group_card.dart';

TOModel _to({int totalConfirmed = 0, int totalRequired = 1}) => TOModel(
      id: 'to1',
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

WorkDetailData _wd({String? wdId, int requiredCount = 1}) => WorkDetailData(
      wdId: wdId,
      workType: '홀서빙',
      startTime: '09:00',
      endTime: '18:00',
      requiredCount: requiredCount,
      wage: 12000,
      wageType: 'hourly',
    );

/// 9/29 슬롯 하나. 슬롯 카운터는 `확정 1 / 정원 1` 이다.
TOItem _slotItem({
  int confirmedCount = 1,
  int totalRequired = 1,
}) =>
    TOItem(
      to: _to(totalConfirmed: confirmedCount, totalRequired: totalRequired),
      slot: SlotModel(
        id: 'slot-0929',
        toId: 'to1',
        date: DateTime(2026, 9, 29),
        workDetails: [_wd(wdId: 'wd-slot-1')],
      ),
      confirmedCount: confirmedCount,
      pendingCount: 0,
      totalRequired: totalRequired,
    );

void main() {
  group('GHP-A 머리말 projection', () {
    test('A-1 슬롯 하나 — 집계 없으면 카운터로 1/1', () {
      final item = _slotItem();
      final t = projectGroupHeaderTotals(
          targetTOs: [item], singleFallback: () => item);
      expect(t.confirmed, 1);
      expect(t.required, 1);
      expect(t.shortage, 0);
      expect(t.isFull, isTrue);
    });

    test('A-2 집계가 오면 집계를 쓴다 — 같은 인스턴스에 채워도 반영된다', () {
      final item = _slotItem();
      final before = projectGroupHeaderTotals(
          targetTOs: [item], singleFallback: () => item);
      expect(before.confirmed, 1);

      // 정원 집계 도착 — **제자리 수정**이다. 새 인스턴스가 아니다.
      item.setWorkDetails(
        [_wd(wdId: 'wd-slot-1')],
        {
          'wd-slot-1': {'confirmed': 0, 'pending': 0}
        },
      );

      final after = projectGroupHeaderTotals(
          targetTOs: [item], singleFallback: () => item);
      expect(after.confirmed, 0, reason: '집계가 0이라고 말하면 머리말도 0이다');
      expect(after.required, 1);
      expect(after.shortage, 1);
      expect(after.isFull, isFalse);
    });

    test('A-3 identity 가 빗나가면 집계를 쓰지 않는다 — 카운터로 남는다', () {
      final item = _slotItem();
      // 원장은 slot wdId 로 세는데 화면이 다른 wdId 를 들고 있는 상황.
      item.setWorkDetails(
        [_wd(wdId: 'wd-master-다른값')],
        {
          'wd-slot-1': {'confirmed': 1, 'pending': 0}
        },
      );
      final t = projectGroupHeaderTotals(
          targetTOs: [item], singleFallback: () => item);
      expect(t.confirmed, 1, reason: 'lookup miss 를 0 으로 접지 않는다');
      expect(t.isFull, isTrue);
    });

    test('A-4 통계 실패는 카운터로 폴백한다', () {
      final item = _slotItem();
      item.setWorkDetails(
        [_wd(wdId: 'wd-slot-1')],
        {
          'wd-slot-1': {'confirmed': 0, 'pending': 0}
        },
        statsFailed: true,
      );
      final t = projectGroupHeaderTotals(
          targetTOs: [item], singleFallback: () => item);
      expect(t.confirmed, 1, reason: '실패한 0 을 사실로 쓰지 않는다');
    });

    test('A-5 여러 날짜는 합산되고 전부 찬 경우에만 FULL', () {
      final a = _slotItem(confirmedCount: 1, totalRequired: 1);
      final b = _slotItem(confirmedCount: 0, totalRequired: 1);
      final t = projectGroupHeaderTotals(
          targetTOs: [a, b], singleFallback: () => a);
      expect(t.confirmed, 1);
      expect(t.required, 2);
      expect(t.shortage, 1);
      expect(t.isFull, isFalse, reason: '한 날짜라도 비면 FULL 이 아니다');
    });

    test('A-6 대상이 비면 단건 폴백을 쓴다', () {
      final single = _slotItem(confirmedCount: 1);
      var calls = 0;
      final t = projectGroupHeaderTotals(
          targetTOs: const [], singleFallback: () { calls++; return single; });
      expect(calls, 1);
      expect(t.confirmed, 1);
    });

    test('A-7 대상이 있으면 단건 폴백을 만들지 않는다', () {
      final item = _slotItem();
      var calls = 0;
      projectGroupHeaderTotals(
          targetTOs: [item], singleFallback: () { calls++; return item; });
      expect(calls, 0, reason: '쓰지 않을 합성 item 을 만들지 않는다');
    });
  });

  group('GHP-B 언제 다시 계산하는가', () {
    final card = _codeOf(_src(_cardPath));

    test('B-1 카드가 같은 projection 함수를 쓴다', () {
      expect(card.contains('projectGroupHeaderTotals('), isTrue);
      // 카드 안에 같은 덧셈을 또 두지 않는다.
      expect(card.contains('_isFull = _targetTOs.every((t) => t.resolvedIsFull);'),
          isFalse, reason: '판정이 두 군데 있으면 또 갈라진다');
    });

    test('B-2 부모가 다시 그리면 무조건 다시 계산한다', () {
      final i = card.indexOf('void didUpdateWidget(TOGroupCard old) {');
      expect(i, greaterThan(0));
      final body = card.substring(i, i + 1400);
      expect(body.contains('_updateGroupCache();'), isTrue);
      // identical 로 거르면 제자리 수정이 반영되지 않는다.
      expect(body.contains('!identical(widget.groupItem, old.groupItem)'), isFalse,
          reason: '집계는 같은 인스턴스 안에 채워진다');
    });

    test('B-3 집계 주입이 제자리 수정이라는 사실이 그대로다', () {
      final m = _codeOf(_src('lib/models/ui/admin_to_list_ui_models.dart'));
      final i = m.indexOf('void setWorkDetails(');
      expect(i, greaterThan(0));
      final body = m.substring(i, i + 400);
      // 필드를 갈아끼운다 — 새 TOItem 을 만들지 않는다.
      expect(body.contains('_workDetails = details;'), isTrue);
      expect(body.contains('workDetailStats = stats;'), isTrue);
    });
  });
}
