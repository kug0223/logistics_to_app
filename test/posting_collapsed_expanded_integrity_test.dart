// [COLLAPSED-EXPANDED] 접힌 카드와 펼친 상세가 **같은 사실**을 말한다.
//
//   사용자가 본 것:
//     접힌 카드  `충원 1 / 필요 미설정 · 대기 0`
//     펼친 상세  냉동분류·냉장분류 업무별 정원과 마감
//
//   DEV 실측(READ ONLY)으로 원인을 확정했다 —
//   `[P4B-RAS] 재배치 상속`(`6jVlL4bryVe5M0dJNNyf`):
//
//     TO 문서      totalRequired = 0
//     업무 정의     냉동분류 req 1 · 냉장분류 req 1
//     slot wd[].id **없음**
//     slot.workDetailCounts 키 `tHuiL1kRoID6AEFxXKrm` · `7FlxQQOG7OmaUuLUfzpw`
//
//   두 결함이 겹친다.
//     ① 업무 정의에 `wdId` 가 없어 집계 identity 가 맞지 않는다
//        → `_aggregateUsable == false` → **카운터 폴백**
//     ② 그 폴백이 `required` 를 `TO.totalRequired`(= 0) 에서 읽었다
//        → `필요 미설정`. 같은 화면의 펼친 행은 `work.requiredCount` 를 읽는다.
//
//   그래서 **required 의 출처를 한 벌로** 만들었다. 펼친 행이 읽는 그곳
//   (업무 정의)을 접힌 요약도 읽는다. 스키마·writer 는 건드리지 않았다.
//
//   테스트는 실제 `resolveStats` / `projectGroupHeaderTotals` 를 부른다 —
//   판정식을 복사하지 않는다.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ALfit/models/core/slot_model.dart';
import 'package:ALfit/models/core/to_model.dart';
import 'package:ALfit/models/core/work_detail_data.dart';
import 'package:ALfit/models/ui/admin_to_list_ui_models.dart';
import 'package:ALfit/models/ui/group_header_totals.dart';

String _codeOf(String b) => b
    .split('\n')
    .where((l) => !l.trimLeft().startsWith('//'))
    .join('\n');

TOModel _to({
  int totalRequired = 0,
  int totalConfirmed = 0,
  int totalPending = 0,
  List<WorkDetailData> master = const [],
  String status = 'ACTIVE',
  String title = '[P4B-RAS] 재배치 상속',
}) =>
    TOModel(
      id: 'to-p4b',
      businessId: 'GlyuWgjOxmlY0wSCAG6H',
      businessName: '신세계푸드 평택센터',
      type: 'flex',
      title: title,
      creatorUID: 'uid1',
      status: status,
      workDetails: master,
      totalRequired: totalRequired,
      totalConfirmed: totalConfirmed,
      totalPending: totalPending,
      isPublished: true,
      publishMode: 'immediate',
      createdAt: DateTime(2026, 10, 8),
      statusUpdatedAt: DateTime(2026, 10, 8),
    );

/// DEV 실측 모양: `wdId` 가 **없는** 업무 정의.
WorkDetailData _wd({
  String? wdId,
  required String workType,
  required int requiredCount,
  String start = '15:51',
  String end = '15:52',
}) =>
    WorkDetailData(
      wdId: wdId,
      workType: workType,
      startTime: start,
      endTime: end,
      requiredCount: requiredCount,
      wage: 12000,
      wageType: 'hourly',
    );

/// `6jVlL4bryVe5M0dJNNyf` 과 같은 모양의 TOItem.
TOItem _devShapedItem({
  String? wdId,
  int totalRequired = 0,
  int confirmedCount = 0,
  int pendingCount = 0,
}) {
  final details = [
    _wd(wdId: wdId == null ? null : '${wdId}_1', workType: '냉동분류', requiredCount: 1),
    _wd(wdId: wdId == null ? null : '${wdId}_2', workType: '냉장분류', requiredCount: 1),
  ];
  return TOItem(
    to: _to(totalRequired: totalRequired, totalConfirmed: confirmedCount),
    slot: SlotModel(
      id: 'LAhbsIfR8oFzTzul84JE',
      toId: 'to-p4b',
      date: DateTime(2026, 10, 8),
      workDetails: details,
    ),
    workDetails: details,
    confirmedCount: confirmedCount,
    pendingCount: pendingCount,
    totalRequired: totalRequired,
  );
}

void main() {
  group('PCE-1 재현 — 같은 공고에서 정원이 갈렸다', () {
    test('PCE-01 wdId 없음 + totalRequired 0 → 요약도 업무 정의를 읽는다', () {
      final item = _devShapedItem();           // DEV 실측 모양
      final s = item.resolveStats();
      // 집계 identity 가 맞지 않아 폴백이지만 **정원은 안다**.
      expect(item.hasLoadedStats, isFalse,
          reason: '집계를 쓸 수 없는 상태가 재현돼야 의미가 있다');
      expect(s.required, 2,
          reason: '펼친 행은 1+1=2 를 보여 준다 — 요약도 같아야 한다');
      expect(s.shortage, 2);
      expect(item.isRequiredKnown, isTrue);
    });

    test('PCE-02 머리말 projection 도 같은 값을 말한다', () {
      final item = _devShapedItem();
      final t = projectGroupHeaderTotals(
          targetTOs: [item], singleFallback: () => item);
      expect(t.required, 2);
      expect(t.requiredKnown, isTrue);
      expect(t.confirmed, 0);
      expect(t.isFull, isFalse, reason: '정원 2 에 충원 0 이면 FULL 이 아니다');
    });

    test('PCE-04 **펼치기 전** 합성 item 도 같은 정원을 말한다', () {
      // 접힌 카드는 슬롯을 아직 안 불러왔을 때 master TO 로 합성 item 을
      //   만든다(`_getSingleTOItem`: slot 없음 · workDetails 없음).
      //   그 경로가 `statsAlignedWorkDetails` → `to.workDetails` 다.
      //   업무 상세 통계는 **펼칠 때** lazy load 되므로, 펼치기 전에도
      //   정원을 말할 수 있어야 요약이 상세와 어긋나지 않는다.
      final master = [
        _wd(workType: '냉동분류', requiredCount: 1),
        _wd(workType: '냉장분류', requiredCount: 1),
      ];
      final synthesized = TOItem(
        to: _to(master: master, totalRequired: 0),
        confirmedCount: 0,
        pendingCount: 0,
        totalRequired: 0,
      );
      expect(synthesized.isRequiredKnown, isTrue);
      final s = synthesized.resolveStats();
      expect(s.required, 2, reason: '펼치기 전에도 `필요 미설정` 이 아니다');
      expect(s.shortage, 2);
    });

    test('PCE-03 펼친 행이 읽는 값과 **합이 같다**', () {
      final item = _devShapedItem();
      // 펼친 행은 `work.requiredCount` 를 그대로 쓴다.
      final perRow =
          item.workDetails.fold<int>(0, (a, w) => a + w.requiredCount);
      expect(item.resolveStats().required, perRow);
    });
  });

  group('PCE-2 정원을 **모를 때**와 **미설정**을 가른다', () {
    test('PCE-10 업무 정의도 없고 카운터도 0 → 모름', () {
      final item = TOItem(
        to: _to(),
        slot: SlotModel(
          id: 'slot-empty',
          toId: 'to-p4b',
          date: DateTime(2026, 10, 8),
          workDetails: const [],
        ),
        confirmedCount: 0,
        pendingCount: 0,
        totalRequired: 0,
      );
      expect(item.isRequiredKnown, isFalse,
          reason: '못 읽은 것을 `미설정` 으로 말하면 조회 실패가 운영 사실이 된다');
      final t = projectGroupHeaderTotals(
          targetTOs: [item], singleFallback: () => item);
      expect(t.requiredKnown, isFalse);
    });

    test('PCE-11 업무 정의를 읽었고 합이 0 → 진짜 미설정', () {
      final details = [_wd(workType: '냉동분류', requiredCount: 0)];
      final item = TOItem(
        to: _to(master: details),
        slot: SlotModel(
          id: 'slot-zero',
          toId: 'to-p4b',
          date: DateTime(2026, 10, 8),
          workDetails: details,
        ),
        workDetails: details,
        confirmedCount: 0,
        pendingCount: 0,
        totalRequired: 0,
      );
      expect(item.isRequiredKnown, isTrue, reason: '정의를 읽었다');
      expect(item.resolveStats().required, 0, reason: '그 정의가 0 이라고 말한다');
    });

    test('PCE-12 카운터만 있어도 안다 (장기 등 정의 없는 경로)', () {
      final item = TOItem(
        to: _to(totalRequired: 5),
        confirmedCount: 1,
        pendingCount: 0,
        totalRequired: 5,
      );
      expect(item.isRequiredKnown, isTrue);
      expect(item.resolveStats().required, 5);
    });

    test('PCE-13 그룹 합계는 **하나만 몰라도** 모른다', () {
      final known = _devShapedItem();
      final unknown = TOItem(
        to: _to(),
        slot: SlotModel(
          id: 'slot-empty',
          toId: 'to-p4b',
          date: DateTime(2026, 10, 8),
          workDetails: const [],
        ),
        confirmedCount: 0,
        pendingCount: 0,
        totalRequired: 0,
      );
      final t = projectGroupHeaderTotals(
          targetTOs: [known, unknown], singleFallback: () => known);
      expect(t.requiredKnown, isFalse,
          reason: '아는 것만 더해 `필요 2` 라고 하면 그것이 전체인 줄 읽힌다');
    });
  });

  group('PCE-3 기존 계약이 깨지지 않았다', () {
    test('PCE-20 집계가 맞으면 여전히 집계를 쓴다', () {
      final item = _devShapedItem(wdId: 'wd');
      item.setWorkDetails(
        item.workDetails,
        {
          'wd_1': {'confirmed': 1, 'pending': 0},
          'wd_2': {'confirmed': 0, 'pending': 1},
        },
      );
      expect(item.hasLoadedStats, isTrue);
      final s = item.resolveStats();
      expect(s.confirmed, 1);
      expect(s.pending, 1);
      expect(s.required, 2);
      expect(s.shortage, 1, reason: '냉동 1/1 충족 · 냉장 0/1 부족');
    });

    test('PCE-21 통계 조회 실패는 0 이 아니라 카운터 + 정의다', () {
      final item = _devShapedItem(confirmedCount: 1, pendingCount: 2);
      item.markWorkDetailStatsFailed();
      final s = item.resolveStats();
      expect(item.hasLoadedStats, isFalse);
      expect(s.confirmed, 1, reason: '슬롯 카운터는 별도 유효 source');
      expect(s.pending, 2);
      expect(s.required, 2, reason: '정원은 정의에서 — 0 으로 떨어지지 않는다');
    });

    test('PCE-22 FULL 판정이 정원 0 으로 참이 되지 않는다', () {
      final item = _devShapedItem();            // required 2, confirmed 0
      expect(item.resolvedIsFull, isFalse);
      // 예전에는 required 가 0 이라 `required > 0` 가 false → FULL 도 false 였다.
      //   값은 같지만 이유가 다르다 — 이제 정원을 알고 부족을 말한다.
      expect(item.resolveStats().shortage, 2);
    });

    test('PCE-23 같은 제목 다른 공고는 서로 다른 entity 다', () {
      // DEV 실측: `[P4B-RAS] 재배치 상속` 이 toId 3개로 존재한다.
      //   제목이 같다는 것은 결함이 아니다 — 합치지 않는다.
      final a = _devShapedItem();
      final b = _devShapedItem();
      expect(a.to.id, b.to.id, reason: 'fixture 는 같은 id 를 쓴다');
      final t = projectGroupHeaderTotals(
          targetTOs: [a, b], singleFallback: () => a);
      expect(t.required, 4, reason: '두 공고는 각자의 정원을 갖는다');
    });
  });

  group('PCE-4 배선 — 요약 문구가 세 상태를 구별한다', () {
    final card = _codeOf(
        File('lib/widgets/admin/cards/admin_to_group_card.dart')
            .readAsStringSync());

    test('PCE-30 `확인 불가` · `미설정` · `필요 N` 세 분기', () {
      expect(card, contains("' / 필요 확인 불가'"));
      expect(card, contains("' / 필요 미설정'"));
      expect(card, contains(r"' / 필요 $required'"));
      expect(card, contains('!requiredKnown'));
    });

    test('PCE-31 요약이 projection 의 requiredKnown 을 받는다', () {
      expect(card, contains('_requiredKnown  = totals.requiredKnown;'));
      expect(card, contains('requiredKnown: _requiredKnown,'));
    });

    test('PCE-32 required 출처가 한 곳이다', () {
      final models = _codeOf(
          File('lib/models/ui/admin_to_list_ui_models.dart').readAsStringSync());
      // 폴백 경로가 더는 `totalRequired` 를 직접 쓰지 않는다.
      expect(models, contains('int get _requiredFromDefinitions'));
      expect(models.contains('required: totalRequired,'), isFalse,
          reason: 'required 를 카운터에서 직접 읽는 경로가 남았다');
      expect(models, contains('bool get isRequiredKnown'));
    });
  });
}
