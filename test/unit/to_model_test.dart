// test/unit/to_model_test.dart
// TOModel 순수 Dart getter / 계산 단위 테스트
//
// fromFirestore/fromMap은 Timestamp 의존 → 생략.
// 생성자를 직접 사용하여 Firebase 없이 검증.
// 시간 의존 getter(isDeadlinePassed, isPostingExpired, isPendingPublish)는
// 미래/과거 날짜로 사이드-이펙트 없이 검증 가능한 경우만 포함.

import 'package:flutter_test/flutter_test.dart';
import 'package:ALfit/models/core/to_model.dart';
import 'package:ALfit/utils/format_helper.dart';

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
  // computeContractEndDate — 규칙 v2 (KST 달력일 · 민법 160②③)
  // ══════════════════════════════════════════════════════
  //
  // [CONTRACT-PERIOD-RULE] 이 그룹을 두 번 옮겼다.
  //   ① 예전 기대값은 당시 구현식(`month + N + 1`)을 옮겨 적어
  //      N개월이 사실상 N+1개월이었다 → 달력 의미로 정정(R7-FS-1).
  //   ② 그 다음 감사에서 **이 함수의 값이 저장되지 않는다**는 것이
  //      드러났다. 확정 서버가 다른 식으로 덮어썼다.
  //      이번에 두 식을 하나로 모았다 — 규칙은
  //      `lib/utils/contract_period.dart` 이고 서버와 공유 벡터로 묶인다.
  //
  //   그래서 여기서는 **이 모델이 그 규칙을 지난다**는 것만 본다.
  //   규칙 자체의 전수 대조는
  //   `test/contract_period_parity_contract_test.dart` 가 한다.
  //
  //   반환값은 그 KST 달력일의 **KST 자정 instant** 다(저장소의 DATE_ONLY
  //   관례). 그래서 기대값도 로컬 `DateTime` 이 아니라 KST 달력일로 읽는다 —
  //   섞으면 KST 가 아닌 기기에서 하루 밀린다.
  group('TOModel.computeContractEndDate', () {
    String endOf(String periodType, DateTime start) =>
        FormatHelper.formatDateISO(_make(
                type: TOType.contract, contractPeriodType: periodType)
            .computeContractEndDate(start));

    test('15days: 2026-01-01 → 2026-01-15 (시작일 포함 15일)', () {
      expect(endOf('15days', DateTime(2026, 1, 1)), '2026-01-15');
    });

    test('1month: 2026-01-01 → 2026-01-31 (해당일 2/1 의 전일)', () {
      expect(endOf('1month', DateTime(2026, 1, 1)), '2026-01-31');
    });

    test('1month: 2026-01-31 (월말 시작) → 2026-02-28 (민법 160③ 말일)', () {
      // [CONTRACT-PERIOD-RULE] 기대값을 2/27 에서 2/28 로 옮겼다.
      //   2월에 31일이 없다 — 민법 제160조 ③ 은 그 경우 **그 월의 말일**로
      //   기간이 만료한다고 정한다. 예전 식은 말일로 clamp 한 뒤 또 하루를
      //   빼서 2/27 이었다(하루 짧았다). 서버는 반대로 3/3 이었다.
      expect(endOf('1month', DateTime(2026, 1, 31)), '2026-02-28');
    });

    test('1month: 2028-01-31 (윤년) → 2028-02-29', () {
      expect(endOf('1month', DateTime(2028, 1, 31)), '2028-02-29');
    });

    test('3months: 2026-01-01 → 2026-03-31', () {
      expect(endOf('3months', DateTime(2026, 1, 1)), '2026-03-31');
    });

    test('6months: 2026-01-01 → 2026-06-30', () {
      expect(endOf('6months', DateTime(2026, 1, 1)), '2026-06-30');
    });

    test('1year: 2026-01-01 → 2026-12-31 (같은 해 말일)', () {
      expect(endOf('1year', DateTime(2026, 1, 1)), '2026-12-31');
    });

    test('1year: 2026-07-01 → 2027-06-30', () {
      expect(endOf('1year', DateTime(2026, 7, 1)), '2027-06-30');
    });

    // 해당일이 **있는** 달에서는 그 전일이다 — 규칙의 정상 경로.
    //   누가 다시 N+1개월로 밀면 이 셀이 걸린다.
    test('해당일이 있으면 그 전일이다 (N개월은 시작일 포함)', () {
      const cases = {
        '1month': 1,
        '3months': 3,
        '6months': 6,
        '1year': 12,
      };
      final start = DateTime(2026, 5, 15); // 어느 달에도 15일은 있다
      cases.forEach((type, months) {
        final anniversary = DateTime.utc(
            start.year + ((start.month + months - 1) ~/ 12),
            ((start.month + months - 1) % 12) + 1,
            start.day);
        final expected = FormatHelper.formatDateISO(
            anniversary.subtract(const Duration(days: 1)));
        expect(endOf(type, start), expected,
            reason: '$type 은 $months 개월이다');
      });
    });

    test('custom·미지정은 rangeEnd 가 정한다 — 날짜를 지어내지 않는다', () {
      final fixed = DateTime(2026, 9, 30);
      final m = _make(
          type: TOType.contract, contractPeriodType: 'custom',
          rangeEnd: fixed);
      expect(FormatHelper.formatDateISO(
              m.computeContractEndDate(DateTime(2026, 1, 1))),
          '2026-09-30');
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
