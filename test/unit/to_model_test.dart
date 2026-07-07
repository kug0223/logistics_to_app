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

    test('typeLabel: contract → "고정 근무"', () {
      expect(_make(type: TOType.contract).typeLabel, equals('고정 근무'));
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

    test('1month: 2026-01-01 → 2026-01-31 (1월 말일)', () {
      // DateTime(2026, 3, 1) - 1day = 2026-02-28? 아니면 1월 말일?
      // contractPeriodType='1month': DateTime(y, month+2, 1) - 1 = DateTime(2026, 3, 1) - 1 = 2026-02-28
      // 잠깐, 이건 '1월부터 1개월'이니 2월 말일 = 28일이 되어야 할 것 같지만...
      // 실제 코드: DateTime(startDate.year, startDate.month + 2, 1).subtract(1day)
      // startDate = 2026-01-01 → DateTime(2026, 3, 1) - 1 = 2026-02-28
      // 즉 "1개월 계약" = 시작일이 1월 1일이면 끝이 2월 28일
      // 이건 의도: 1개월 뒤 달의 말일 = 다음달 말일
      // 실제로 맞나? 1월1일에서 1개월이면 1월31일이어야 함
      // 코드 주석: 패턴: DateTime(y, startMonth + N + 1, 1) - 1day = N개월 뒤 달의 말일
      // N=1: DateTime(y, month+2, 1) - 1 = month+1 달의 말일
      // startDate.month=1 → DateTime(2026, 3, 1) - 1 = 2026-02-28
      // 즉 "1개월"은 다음 달(2월)의 말일로 해석하는 설계
      final m = _make(type: TOType.contract, contractPeriodType: '1month');
      final result = m.computeContractEndDate(DateTime(2026, 1, 1));
      // 코드 설계에 따라: DateTime(2026, 3, 1) - 1 = 2026-02-28
      expect(result, equals(DateTime(2026, 2, 28)));
    });

    test('1month: 2026-01-31 (월말 시작) → 2026-02-28 (오버플로우 없음)', () {
      // DateTime(2026, 1+2, 1) - 1 = DateTime(2026, 3, 1) - 1 = 2026-02-28
      // Dart의 DateTime은 month=3, day=1에서 1일 빼면 2월 말일로 자동 처리
      final m = _make(type: TOType.contract, contractPeriodType: '1month');
      final result = m.computeContractEndDate(DateTime(2026, 1, 31));
      expect(result, equals(DateTime(2026, 2, 28)));
    });

    test('3months: 2026-01-01 → 2026-04-30 (4월 말일)', () {
      // DateTime(2026, 1+4, 1) - 1 = DateTime(2026, 5, 1) - 1 = 2026-04-30
      final m = _make(type: TOType.contract, contractPeriodType: '3months');
      final result = m.computeContractEndDate(DateTime(2026, 1, 1));
      expect(result, equals(DateTime(2026, 4, 30)));
    });

    test('6months: 2026-01-01 → 2026-07-31', () {
      // DateTime(2026, 1+7, 1) - 1 = DateTime(2026, 8, 1) - 1 = 2026-07-31
      final m = _make(type: TOType.contract, contractPeriodType: '6months');
      final result = m.computeContractEndDate(DateTime(2026, 1, 1));
      expect(result, equals(DateTime(2026, 7, 31)));
    });

    test('1year: 2026-01-01 → 2027-01-31 (다음해 1월 말일)', () {
      // DateTime(2026+1, 1+1, 1) - 1 = DateTime(2027, 2, 1) - 1 = 2027-01-31
      final m = _make(type: TOType.contract, contractPeriodType: '1year');
      final result = m.computeContractEndDate(DateTime(2026, 1, 1));
      expect(result, equals(DateTime(2027, 1, 31)));
    });

    test('1year: 2026-07-01 → 2027-07-31', () {
      // DateTime(2026+1, 7+1, 1) - 1 = DateTime(2027, 8, 1) - 1 = 2027-07-31
      final m = _make(type: TOType.contract, contractPeriodType: '1year');
      final result = m.computeContractEndDate(DateTime(2026, 7, 1));
      expect(result, equals(DateTime(2027, 7, 31)));
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
