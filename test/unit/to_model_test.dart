// test/unit/to_model_test.dart
// TOModel 순수 Dart getter / 계산 단위 테스트
//
// fromFirestore/fromMap은 Timestamp 의존 → 생략.
// 생성자를 직접 사용하여 Firebase 없이 검증.
// 시간 의존 getter(isDeadlinePassed, isPostingExpired, isPendingPublish)는
// 미래/과거 날짜로 사이드-이펙트 없이 검증 가능한 경우만 포함.

import 'package:flutter_test/flutter_test.dart';
import 'package:ALfit/models/core/to_model.dart';

/// 최소 필드로 TOModel 생성
TOModel _make({
  String type = TOType.flex,
  String status = TOStatus.active,
  bool isManualClosed = false,
  int totalRequired = 0,
  int totalConfirmed = 0,
  List<String> workDays = const [],
  String? contractPeriodType,
  DateTime? rangeStart,
  DateTime? rangeEnd,
  int? postingDurationDays,
  DateTime? publishAt,
  bool isPublished = true,
  String publishMode = 'immediate',
  DateTime? applicationDeadline,
}) {
  return TOModel(
    id: 'to-001',
    businessId: 'biz-001',
    businessName: '테스트 사업장',
    title: '테스트 공고',
    type: type,
    status: status,
    isManualClosed: isManualClosed,
    totalRequired: totalRequired,
    totalConfirmed: totalConfirmed,
    workDays: workDays,
    contractPeriodType: contractPeriodType,
    rangeStart: rangeStart,
    rangeEnd: rangeEnd,
    postingDurationDays: postingDurationDays,
    publishAt: publishAt,
    isPublished: isPublished,
    publishMode: publishMode,
    applicationDeadline: applicationDeadline,
    creatorUID: 'uid-001',
    createdAt: DateTime(2026, 1, 1),
  );
}

void main() {
  // ══════════════════════════════════════════════════════
  // 타입 getter
  // ══════════════════════════════════════════════════════
  group('TOModel: 타입 getter', () {
    test('type=flex → isFlexType=true, isContractType=false, isShortTerm=true, isLongTerm=false', () {
      final m = _make(type: TOType.flex);
      expect(m.isFlexType,     isTrue);
      expect(m.isContractType, isFalse);
      expect(m.isShortTerm,    isTrue);
      expect(m.isLongTerm,     isFalse);
    });

    test('type=contract → isContractType=true, isFlexType=false, isLongTerm=true', () {
      final m = _make(type: TOType.contract);
      expect(m.isContractType, isTrue);
      expect(m.isFlexType,     isFalse);
      expect(m.isLongTerm,     isTrue);
      expect(m.isShortTerm,    isFalse);
    });

    test('typeLabel: flex → "단기 근무"', () {
      expect(_make(type: TOType.flex).typeLabel, equals('단기 근무'));
    });

    // [R7-P1-PRODUCT §8] 노출 어휘를 장기로 통일했다.
    //   같은 타입이 공고 카드에서는 고정, 인력 현황에서는 장기였다.
    test('typeLabel: contract → "장기 근무"', () {
      expect(_make(type: TOType.contract).typeLabel, equals('장기 근무'));
    });
  });

  // ══════════════════════════════════════════════════════
  // isActive / isManualClosed
  // ══════════════════════════════════════════════════════
  group('TOModel: 상태 getter', () {
    test('status=ACTIVE, isManualClosed=false → isActive=true', () {
      expect(_make(status: TOStatus.active).isActive, isTrue);
    });

    test('status=CLOSED → isActive=false', () {
      expect(_make(status: TOStatus.closed).isActive, isFalse);
    });
  });

  // ══════════════════════════════════════════════════════
  // isFull
  // ══════════════════════════════════════════════════════
  group('TOModel: isFull', () {
    test('totalRequired=0 → isFull=false (인원 제한 없음)', () {
      expect(_make(totalRequired: 0, totalConfirmed: 0).isFull, isFalse);
    });

    test('totalConfirmed < totalRequired → false', () {
      expect(_make(totalRequired: 5, totalConfirmed: 4).isFull, isFalse);
    });

    test('totalConfirmed == totalRequired → true', () {
      expect(_make(totalRequired: 5, totalConfirmed: 5).isFull, isTrue);
    });

    test('totalConfirmed > totalRequired (초과 확정) → true', () {
      expect(_make(totalRequired: 5, totalConfirmed: 6).isFull, isTrue);
    });

    test('totalRequired=1, totalConfirmed=0 → false', () {
      expect(_make(totalRequired: 1, totalConfirmed: 0).isFull, isFalse);
    });
  });

  // ══════════════════════════════════════════════════════
  // availableSlots
  // ══════════════════════════════════════════════════════
  group('TOModel: availableSlots', () {
    test('totalRequired=10, totalConfirmed=3 → 7', () {
      expect(_make(totalRequired: 10, totalConfirmed: 3).availableSlots, equals(7));
    });

    test('totalRequired=5, totalConfirmed=5 → 0 (마감)', () {
      expect(_make(totalRequired: 5, totalConfirmed: 5).availableSlots, equals(0));
    });

    test('초과 확정 → 0 (음수 클램핑 — A09 버그 수정)', () {
      // (3 - 5).clamp(0, 3) = 0
      expect(_make(totalRequired: 3, totalConfirmed: 5).availableSlots, equals(0));
    });

    test('totalRequired=0 → 0 (clamp(0, 0))', () {
      // (0 - 0).clamp(0, 0) = 0
      expect(_make(totalRequired: 0, totalConfirmed: 0).availableSlots, equals(0));
    });
  });

  // ══════════════════════════════════════════════════════
  // isClosed (시간 의존 없는 케이스)
  // ══════════════════════════════════════════════════════
  group('TOModel: isClosed', () {
    test('isManualClosed=true → isClosed=true', () {
      expect(_make(isManualClosed: true).isClosed, isTrue);
    });

    test('isFull (totalRequired=3, confirmed=3) → isClosed=true', () {
      expect(_make(totalRequired: 3, totalConfirmed: 3).isClosed, isTrue);
    });

    test('status=CLOSED → isClosed=true', () {
      expect(_make(status: TOStatus.closed).isClosed, isTrue);
    });

    test('status=EXPIRED → isClosed=true', () {
      expect(_make(status: TOStatus.expired).isClosed, isTrue);
    });

    test('정상 ACTIVE, 인원 미충족 → isClosed=false', () {
      final m = _make(
        status: TOStatus.active,
        totalRequired: 5,
        totalConfirmed: 3,
        isManualClosed: false,
      );
      expect(m.isClosed, isFalse);
    });
  });

  // ══════════════════════════════════════════════════════
  // computeContractEndDate (월말 오버플로우 안전 계산)
  // ══════════════════════════════════════════════════════
  group('TOModel.computeContractEndDate', () {
    test('15days: 2026-01-01 → 2026-01-15', () {
      final m = _make(type: TOType.contract, contractPeriodType: '15days');
      final result = m.computeContractEndDate(DateTime(2026, 1, 1));
      expect(result, equals(DateTime(2026, 1, 15)));
    });

    // [R7-FS-1 C] 이 그룹의 기대값을 옮겼다.
    //
    //   예전 기대값은 `DateTime(y, startMonth + N + 1, 1) - 1일` 이라는
    //   **당시 구현의 식**을 그대로 옮겨 적은 것이었다. 지운 주석에 그
    //   과정이 남아 있었다 — "1월1일에서 1개월이면 1월31일이어야 함" 이라고
    //   쓰고도 구현을 따라 2월 28일을 기대했다. 그래서 N개월이 사실상
    //   N+1개월이었다.
    //
    //   현재 구현은 `(start + N개월) - 1일` 이고 소스에 규칙으로 적혀 있다.
    //   테스트 **이름**은 처음부터 이쪽(1월 말일)을 말하고 있었다.
    //   달력 의미와 이름이 일치하는 쪽으로 기대값을 맞춘다.
    test('1month: 2026-01-01 → 2026-01-31 (1월 말일)', () {
      final m = _make(type: TOType.contract, contractPeriodType: '1month');
      final result = m.computeContractEndDate(DateTime(2026, 1, 1));
      // 시작일 포함 1개월 = 1/1 ~ 1/31
      expect(result, equals(DateTime(2026, 1, 31)));
    });

    test('1month: 2026-01-31 (월말 시작) → 2026-02-27 (clamp 후 -1일)', () {
      // 구현이 규칙으로 적어 둔 값: 1/31 + 1개월 → 2/28(clamp) - 1일 = 2/27.
      //
      // [OPEN-CONTRACT-MONTHEND] **앞 회차 설명을 정정한다.** 그때
      //   "구현이 명시한 현재 규칙" 이라고 적었는데, 이 함수의 값은
      //   계약 만료일로 **저장되지 않는다.** 확정 시
      //   `callableConfirmApplication` 이 자기 식으로 다시 계산해
      //   `workEndDate` 를 덮어쓴다([M2-FIX]). 그 서버 식에는 `- 1일` 도
      //   월말 clamp 도 없어서 같은 입력에 **2026-03-03** 이 나온다.
      //   계약서 제2조·만료 알림·좌석 판정은 모두 그 값을 쓴다.
      //
      //   즉 이 함수가 만드는 것은 **지원 화면 표시값과 PENDING 저장값**
      //   이고, 열린 질문은 "2/27 vs 2/28" 이 아니라 **두 식의 불일치**다.
      //   전수 대조와 판정은 `test/contract_period_parity_contract_test.dart`
      //   와 `docs/r7-contract-monthend-audit.md` 에 있다.
      //   여기서는 이 함수의 값만 고정한다(식은 고치지 않았다).
      final m = _make(type: TOType.contract, contractPeriodType: '1month');
      final result = m.computeContractEndDate(DateTime(2026, 1, 31));
      expect(result, equals(DateTime(2026, 2, 27)));
    });

    test('3months: 2026-01-01 → 2026-03-31 (3월 말일)', () {
      // 시작일 포함 3개월 = 1/1 ~ 3/31
      final m = _make(type: TOType.contract, contractPeriodType: '3months');
      final result = m.computeContractEndDate(DateTime(2026, 1, 1));
      expect(result, equals(DateTime(2026, 3, 31)));
    });

    test('6months: 2026-01-01 → 2026-06-30', () {
      // 시작일 포함 6개월 = 1/1 ~ 6/30
      final m = _make(type: TOType.contract, contractPeriodType: '6months');
      final result = m.computeContractEndDate(DateTime(2026, 1, 1));
      expect(result, equals(DateTime(2026, 6, 30)));
    });

    test('1year: 2026-01-01 → 2026-12-31 (같은 해 말일)', () {
      // 시작일 포함 1년 = 2026-01-01 ~ 2026-12-31
      final m = _make(type: TOType.contract, contractPeriodType: '1year');
      final result = m.computeContractEndDate(DateTime(2026, 1, 1));
      expect(result, equals(DateTime(2026, 12, 31)));
    });

    test('1year: 2026-07-01 → 2027-06-30', () {
      // 시작일 포함 1년 = 2026-07-01 ~ 2027-06-30
      final m = _make(type: TOType.contract, contractPeriodType: '1year');
      final result = m.computeContractEndDate(DateTime(2026, 7, 1));
      expect(result, equals(DateTime(2027, 6, 30)));
    });

    // [R7-FS-1 C] 위 기대값들의 **뜻**을 한 번 더 못 박는다.
    //   "N개월" 은 시작일 포함 N개월이고, 그래서 같은 날짜 하루 전에서
    //   끝난다. 누가 다시 N+1개월로 밀면 이 셀이 걸린다.
    test('N개월은 시작일 포함이다 — 같은 날짜 하루 전에 끝난다', () {
      const cases = {
        '1month': 1,
        '3months': 3,
        '6months': 6,
        '1year': 12,
      };
      final start = DateTime(2026, 5, 15); // 월말 clamp 가 없는 날
      cases.forEach((type, months) {
        final m = _make(type: TOType.contract, contractPeriodType: type);
        final expected = DateTime(
                start.year + ((start.month + months - 1) ~/ 12),
                ((start.month + months - 1) % 12) + 1,
                start.day)
            .subtract(const Duration(days: 1));
        expect(m.computeContractEndDate(start), equals(expected),
            reason: '$type 은 $months 개월이다');
      });
    });
  });

  // ══════════════════════════════════════════════════════
  // contractPeriodLabel
  // ══════════════════════════════════════════════════════
  group('TOModel: contractPeriodLabel', () {
    test('15days → "15일"', () {
      expect(_make(contractPeriodType: '15days').contractPeriodLabel, equals('15일'));
    });

    test('1month → "1개월"', () {
      expect(_make(contractPeriodType: '1month').contractPeriodLabel, equals('1개월'));
    });

    test('3months → "3개월"', () {
      expect(_make(contractPeriodType: '3months').contractPeriodLabel, equals('3개월'));
    });

    test('6months → "6개월"', () {
      expect(_make(contractPeriodType: '6months').contractPeriodLabel, equals('6개월'));
    });

    test('1year → "1년"', () {
      expect(_make(contractPeriodType: '1year').contractPeriodLabel, equals('1년'));
    });

    test('custom → "직접 입력"', () {
      expect(_make(contractPeriodType: 'custom').contractPeriodLabel, equals('직접 입력'));
    });

    test('null → ""', () {
      expect(_make(contractPeriodType: null).contractPeriodLabel, equals(''));
    });
  });

  // ══════════════════════════════════════════════════════
  // hasPresetPeriod
  // ══════════════════════════════════════════════════════
  group('TOModel: hasPresetPeriod', () {
    test('null → false', () {
      expect(_make(contractPeriodType: null).hasPresetPeriod, isFalse);
    });

    test('"custom" → false', () {
      expect(_make(contractPeriodType: 'custom').hasPresetPeriod, isFalse);
    });

    test('"1month" → true', () {
      expect(_make(contractPeriodType: '1month').hasPresetPeriod, isTrue);
    });

    test('"1year" → true', () {
      expect(_make(contractPeriodType: '1year').hasPresetPeriod, isTrue);
    });
  });

  // ══════════════════════════════════════════════════════
  // workDaysLabel
  // ══════════════════════════════════════════════════════
  group('TOModel: workDaysLabel', () {
    test('flex type → "" (contract 전용)', () {
      final m = _make(type: TOType.flex, workDays: ['월', '화', '수', '목', '금']);
      expect(m.workDaysLabel, equals(''));
    });

    test('workDays 비어있음 → ""', () {
      expect(_make(type: TOType.contract, workDays: []).workDaysLabel, equals(''));
    });

    test('7일 → "매일 근무"', () {
      final m = _make(
        type: TOType.contract,
        workDays: ['월', '화', '수', '목', '금', '토', '일'],
      );
      expect(m.workDaysLabel, equals('매일 근무'));
    });

    test('6일 (일 휴무) → "주 6일 (일 휴무)"', () {
      final m = _make(
        type: TOType.contract,
        workDays: ['월', '화', '수', '목', '금', '토'],
      );
      expect(m.workDaysLabel, equals('주 6일 (일 휴무)'));
    });

    test('6일 (월 휴무) → "주 6일 (월 휴무)"', () {
      final m = _make(
        type: TOType.contract,
        workDays: ['화', '수', '목', '금', '토', '일'],
      );
      expect(m.workDaysLabel, equals('주 6일 (월 휴무)'));
    });

    test('5일 (토,일 휴무) → "주 5일 (토, 일 휴무)"', () {
      final m = _make(
        type: TOType.contract,
        workDays: ['월', '화', '수', '목', '금'],
      );
      expect(m.workDaysLabel, equals('주 5일 (토, 일 휴무)'));
    });

    test('3일 → "주 3일 (월, 수, 금)"', () {
      final m = _make(
        type: TOType.contract,
        workDays: ['월', '수', '금'],
      );
      expect(m.workDaysLabel, equals('주 3일 (월, 수, 금)'));
    });

    test('1일 → "주 1일 (화)"', () {
      final m = _make(
        type: TOType.contract,
        workDays: ['화'],
      );
      expect(m.workDaysLabel, equals('주 1일 (화)'));
    });
  });

  // ══════════════════════════════════════════════════════
  // TOStatus / TOType 상수
  // ══════════════════════════════════════════════════════
  group('TOStatus / TOType 상수', () {
    test('TOType 상수 값', () {
      expect(TOType.flex,     equals('flex'));
      expect(TOType.contract, equals('contract'));
    });

    test('TOStatus 상수 값', () {
      expect(TOStatus.active,   equals('ACTIVE'));
      expect(TOStatus.closed,   equals('CLOSED'));
      expect(TOStatus.full,     equals('FULL'));
      expect(TOStatus.expired,  equals('EXPIRED'));
      expect(TOStatus.scheduled,equals('SCHEDULED'));
    });

    test('TOStatus.openStates 포함 검증', () {
      expect(TOStatus.openStates, containsAll(['ACTIVE', 'FULL', 'SCHEDULED']));
    });

    test('TOStatus.closedStates 포함 검증', () {
      expect(TOStatus.closedStates, containsAll(['CLOSED', 'EXPIRED']));
    });
  });
}
