// [R8-P9C] 살아 있는 flex 일자리가 근로자 목록에서 사라지지 않는다.
//
//   DEV 에서 서버가 돌려준 공개 flex 공고 4건이 전부 `rangeEnd` 가 없었고,
//   근로자 목록은 `rangeEnd == null` 이면 곧바로 제외하고 있었다.
//   그중 하나(kcwGL5K4)는 ACTIVE·게시중이고 오늘 근무가 열려 있었다.
//   구직자는 그 일을 볼 방법이 없었다.
//
//   P9B 에서 확정한 canonical 모델(Model C)을 그대로 쓴다:
//     명시적 전체 수동 종료 > 슬롯,  파생 CLOSED/EXPIRED < 살아 있는 슬롯,
//     FULL 은 슬롯 공고를 죽이지 않는다.
//
//   뒤처질 수 있는 값으로 숨기지 않는 것이 이 파일의 계약이다.
import 'package:flutter_test/flutter_test.dart';

import 'package:ALfit/models/core/to_model.dart';

const _today = '2026-09-22';

TOModel _flex({
  String status = TOStatus.active,
  bool isPublished = true,
  bool isManualClosed = false,
  List<String> dates = const ['2026-09-22'],
  int? totalSlots,
  int totalRequired = 3,
  int totalConfirmed = 0,
}) {
  return TOModel(
    id: 'to-1',
    businessId: 'biz-1',
    businessName: '테스트 사업장',
    title: '테스트 공고',
    creatorUID: 'admin-1',
    type: TOType.flex,
    status: status,
    isPublished: isPublished,
    isManualClosed: isManualClosed,
    slotDateKeys: dates,
    totalSlots: totalSlots ?? dates.length,
    totalRequired: totalRequired,
    totalConfirmed: totalConfirmed,
    createdAt: DateTime(2026, 9, 1),
  );
}

void main() {
  group('[R8P9C] flex 노출 — 못 믿을 값으로 숨기지 않는다', () {
    test('FLEX-EXP-1 ACTIVE + 게시중 + 오늘 슬롯 + rangeEnd 없음 → 보인다', () {
      final to = _flex(dates: const ['2026-09-21', '2026-09-22']);
      expect(to.rangeEnd, isNull, reason: 'DEV 실제 형상 — rangeEnd 가 없다');
      expect(to.isVisibleToWorkerFlex(_today), isTrue);
    });

    test('FLEX-EXP-2 dates 가 뒤처져 있으면 숨기지 않는다', () {
      // 생성 시 9/18 하나였고, 이후 슬롯 2개가 추가돼 totalSlots 만 늘었다.
      // dates 만 보면 "과거뿐"이지만 그 단정은 틀렸다.
      final to = _flex(dates: const ['2026-09-18'], totalSlots: 3);
      expect(to.slotDatesLookComplete, isFalse,
          reason: 'totalSlots 가 dates 보다 크다 — 기록되지 않은 슬롯이 있다');
      expect(to.isVisibleToWorkerFlex(_today), isTrue,
          reason: '모르는 것을 "과거뿐"으로 단정하면 살아 있는 근무가 사라진다');
    });

    test('FLEX-EXP-3 전체 수동 종료 → 숨긴다 (미래 슬롯이 있어도)', () {
      final to = _flex(
        isManualClosed: true,
        dates: const ['2026-10-01', '2026-10-02'],
      );
      expect(to.isVisibleToWorkerFlex(_today), isFalse,
          reason: 'P9B Model C — 명시적 전체 종료가 슬롯보다 우선한다');
    });

    test('FLEX-EXP-4 미게시 → 숨긴다', () {
      expect(_flex(isPublished: false).isVisibleToWorkerFlex(_today), isFalse);
    });

    test('FLEX-EXP-5 과거 날짜뿐 → 숨긴다', () {
      final to = _flex(dates: const ['2026-09-17', '2026-09-18']);
      expect(to.slotDatesLookComplete, isTrue);
      expect(to.isVisibleToWorkerFlex(_today), isFalse);
    });

    test('FLEX-EXP-6 하나는 과거, 하나는 미래 → 보인다', () {
      final to = _flex(dates: const ['2026-09-18', '2026-09-25']);
      expect(to.isVisibleToWorkerFlex(_today), isTrue,
          reason: '날짜 하나가 지났다고 공고 전체가 죽지 않는다');
    });

    test('FLEX-EXP-7 TO 전체 FULL 이어도 다른 날짜가 남으면 보인다', () {
      final to = _flex(
        status: TOStatus.full,
        totalRequired: 3,
        totalConfirmed: 3,
        dates: const ['2026-09-22', '2026-09-25'],
      );
      expect(to.isFull, isTrue);
      expect(to.isClosed, isTrue, reason: 'TOModel.isClosed 는 FULL 을 포함한다');
      expect(to.isVisibleToWorkerFlex(_today), isTrue,
          reason: '서버 지원 게이트는 슬롯 공고에서 TO-level FULL 을 막지 않는다');
    });

    test('FLEX-EXP-8 status CLOSED / EXPIRED / SCHEDULED → 숨긴다', () {
      for (final s in [TOStatus.closed, TOStatus.expired, TOStatus.scheduled]) {
        expect(_flex(status: s, dates: const ['2026-10-01'])
            .isVisibleToWorkerFlex(_today), isFalse, reason: s);
      }
    });

    test('FLEX-EXP-9 슬롯이 하나도 없으면 숨긴다', () {
      // flex 지원은 서버에서 slotId 가 필수다 — 지원할 대상이 없다.
      final to = _flex(dates: const [], totalSlots: 0);
      expect(to.hasNoSlotsAtAll, isTrue);
      expect(to.isVisibleToWorkerFlex(_today), isFalse);
    });

    test('FLEX-EXP-9b totalSlots 만 0 이면 숨기지 않는다', () {
      // increment 반영 전 순간 0 으로 읽힐 수 있다(모델 주석) — 혼자서는 근거가 못 된다.
      final to = _flex(dates: const ['2026-09-25'], totalSlots: 0);
      expect(to.hasNoSlotsAtAll, isFalse);
      expect(to.isVisibleToWorkerFlex(_today), isTrue);
    });

    test('FLEX-EXP-10 오늘 날짜는 아직 지나지 않았다', () {
      final to = _flex(dates: const [_today]);
      expect(to.isVisibleToWorkerFlex(_today), isTrue,
          reason: '오늘 근무를 어제 것처럼 취급하면 당일 지원 창이 사라진다');
    });
  });

  group('[R8P9C] dates 파싱', () {
    test('PARSE-1 형식이 어긋난 항목은 버리고 나머지는 산다', () {
      final to = TOModel.fromMap({
        'businessId': 'b',
        'businessName': 'n',
        'title': 't',
        'creatorUID': 'c',
        'type': TOType.flex,
        'status': TOStatus.active,
        'dates': ['2026-09-22', 'not-a-date', 42, '2026-09-25'],
      }, 'to-1');
      expect(to.slotDateKeys, ['2026-09-22', '2026-09-25']);
    });

    test('PARSE-2 dates 가 없으면 빈 목록이다', () {
      final to = TOModel.fromMap({
        'businessId': 'b',
        'businessName': 'n',
        'title': 't',
        'creatorUID': 'c',
        'type': TOType.flex,
        'status': TOStatus.active,
      }, 'to-1');
      expect(to.slotDateKeys, isEmpty);
    });
  });

  group('[R8P9C] 회귀 방지', () {
    test('GUARD-1 노출 판정이 rangeEnd 를 보지 않는다', () {
      // rangeEnd 가 한참 과거여도, 살아 있는 슬롯이 있으면 보여야 한다.
      final to = TOModel(
        id: 'to-1', businessId: 'b', businessName: 'n', title: 't',
        creatorUID: 'c', type: TOType.flex, status: TOStatus.active,
        isPublished: true,
        rangeEnd: DateTime(2026, 1, 1),
        slotDateKeys: const ['2026-09-25'],
        totalSlots: 1,
        createdAt: DateTime(2026, 1, 1),
      );
      expect(to.isVisibleToWorkerFlex(_today), isTrue);
    });
  });
}
