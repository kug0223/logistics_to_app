// test/unit/slot_model_test.dart
// SlotModel 순수 Dart getter 단위 테스트
//
// fromFirestore/fromMap은 Timestamp 의존 → 생략.
// const 생성자를 직접 사용하여 Firebase 없이 검증.
// isDatePast는 고정 날짜(과거/미래)로 검증.

import 'package:flutter_test/flutter_test.dart';
import 'package:ALfit/models/core/slot_model.dart';
import 'package:ALfit/models/core/work_detail_data.dart';

SlotModel _make({
  String status = SlotStatus.open,
  DateTime? date,
  List<WorkDetailData> workDetails = const [],
  bool isManualClosed = false,
  DateTime? applicationDeadline,
}) {
  return SlotModel(
    id: 'slot-001',
    toId: 'to-001',
    date: date ?? DateTime(2026, 6, 10),
    workDetails: workDetails,
    status: status,
    isManualClosed: isManualClosed,
    applicationDeadline: applicationDeadline,
    createdAt: DateTime(2026, 6, 1),
  );
}

/// 최소 WorkDetailData 생성
WorkDetailData _detail({
  String workType = '피킹',
  int requiredCount = 3,
  bool isManualClosed = false,
  DateTime? applicationDeadline,
}) {
  return WorkDetailData(
    workType: workType,
    wageType: 'hourly',
    wage: 10320,
    requiredCount: requiredCount,
    startTime: '09:00',
    endTime: '18:00',
    isManualClosed: isManualClosed,
    applicationDeadline: applicationDeadline,
  );
}

void main() {
  // ══════════════════════════════════════════════════════
  // 상태 Boolean getter
  // ══════════════════════════════════════════════════════
  group('SlotModel: 상태 getter', () {
    test('open → isOpen=true, isFull=false, isClosed=false', () {
      final m = _make(status: SlotStatus.open);
      expect(m.isOpen,   isTrue);
      expect(m.isFull,   isFalse);
      expect(m.isClosed, isFalse);
    });

    test('full → isFull=true만', () {
      final m = _make(status: SlotStatus.full);
      expect(m.isOpen,   isFalse);
      expect(m.isFull,   isTrue);
      expect(m.isClosed, isFalse);
    });

    test('closed → isClosed=true만', () {
      final m = _make(status: SlotStatus.closed);
      expect(m.isOpen,   isFalse);
      expect(m.isFull,   isFalse);
      expect(m.isClosed, isTrue);
    });
  });

  // ══════════════════════════════════════════════════════
  // isDatePast
  // ══════════════════════════════════════════════════════
  group('SlotModel: isDatePast', () {
    test('과거 날짜 → true', () {
      expect(_make(date: DateTime(2020, 1, 1)).isDatePast, isTrue);
    });

    test('미래 날짜 → false', () {
      expect(_make(date: DateTime(2099, 12, 31)).isDatePast, isFalse);
    });

    test('시간이 포함된 과거 날짜 → 날짜 기준으로 비교 (시간 무시)', () {
      // 2020-01-01 23:59는 과거 날짜
      expect(_make(date: DateTime(2020, 1, 1, 23, 59)).isDatePast, isTrue);
    });
  });

  // ══════════════════════════════════════════════════════
  // totalRequired
  // ══════════════════════════════════════════════════════
  group('SlotModel: totalRequired', () {
    test('workDetails 비어있음 → 0', () {
      expect(_make(workDetails: []).totalRequired, equals(0));
    });

    test('workDetail 1개 → requiredCount 그대로', () {
      final m = _make(workDetails: [_detail(requiredCount: 5)]);
      expect(m.totalRequired, equals(5));
    });

    test('workDetail 여러 개 → requiredCount 합계', () {
      final m = _make(workDetails: [
        _detail(workType: '피킹', requiredCount: 3),
        _detail(workType: '패킹', requiredCount: 2),
      ]);
      expect(m.totalRequired, equals(5));
    });

    test('requiredCount=0 포함 → 0 처리', () {
      final m = _make(workDetails: [
        _detail(requiredCount: 0),
        _detail(requiredCount: 4),
      ]);
      expect(m.totalRequired, equals(4));
    });
  });

  // ══════════════════════════════════════════════════════
  // isEffectivelyClosed
  // ══════════════════════════════════════════════════════
  group('SlotModel: isEffectivelyClosed', () {
    test('closed 상태 → true', () {
      expect(_make(status: SlotStatus.closed).isEffectivelyClosed, isTrue);
    });

    test('full 상태 → true', () {
      expect(_make(status: SlotStatus.full).isEffectivelyClosed, isTrue);
    });

    test('과거 날짜 → isDatePast=true → true', () {
      expect(_make(date: DateTime(2020, 1, 1)).isEffectivelyClosed, isTrue);
    });

    test('open + 미래 날짜 + 마감 없음 + workDetails 없음 → false', () {
      final m = _make(
        status: SlotStatus.open,
        date: DateTime(2099, 12, 31),
        workDetails: [],
        applicationDeadline: null,
      );
      expect(m.isEffectivelyClosed, isFalse);
    });

    test('workDetails 있고 모두 isManualClosed → true', () {
      final m = _make(
        status: SlotStatus.open,
        date: DateTime(2099, 12, 31),
        workDetails: [
          _detail(isManualClosed: true),
          _detail(workType: '패킹', isManualClosed: true),
        ],
      );
      expect(m.isEffectivelyClosed, isTrue);
    });

    test('workDetails 있고 일부만 isManualClosed → false', () {
      final m = _make(
        status: SlotStatus.open,
        date: DateTime(2099, 12, 31),
        workDetails: [
          _detail(isManualClosed: true),
          _detail(workType: '패킹', isManualClosed: false),
        ],
      );
      expect(m.isEffectivelyClosed, isFalse);
    });

    test('workDetails 없고 applicationDeadline 과거 → isDeadlinePassed=true → true', () {
      final m = _make(
        status: SlotStatus.open,
        date: DateTime(2099, 12, 31),
        workDetails: [],
        applicationDeadline: DateTime(2020, 1, 1),
      );
      expect(m.isEffectivelyClosed, isTrue);
    });
  });

  // ══════════════════════════════════════════════════════
  // isDeadlinePassed
  // ══════════════════════════════════════════════════════
  group('SlotModel: isDeadlinePassed', () {
    test('applicationDeadline=null → false', () {
      expect(_make(applicationDeadline: null).isDeadlinePassed, isFalse);
    });

    test('applicationDeadline 과거 → true', () {
      expect(_make(applicationDeadline: DateTime(2020, 1, 1)).isDeadlinePassed, isTrue);
    });

    test('applicationDeadline 미래 → false', () {
      expect(_make(applicationDeadline: DateTime(2099, 12, 31)).isDeadlinePassed, isFalse);
    });
  });

  // ══════════════════════════════════════════════════════
  // SlotStatus 상수
  // ══════════════════════════════════════════════════════
  group('SlotStatus 상수', () {
    test('상수 값 검증', () {
      expect(SlotStatus.open,   equals('open'));
      expect(SlotStatus.full,   equals('full'));
      expect(SlotStatus.closed, equals('closed'));
    });
  });
}
