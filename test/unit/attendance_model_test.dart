// test/unit/attendance_model_test.dart
// AttendanceModel 순수 Dart getter 단위 테스트
//
// fromFirestore/fromMap은 Timestamp·DocumentSnapshot 의존 → 생략.
// 생성자를 직접 사용하여 Firebase 없이 검증.

import 'package:flutter_test/flutter_test.dart';
import 'package:ALfit/models/core/attendance_model.dart';

final _workDate = DateTime(2026, 6, 1);

/// DateTime 헬퍼 — 작업일 + 시:분
DateTime _dt(int h, int m) => DateTime(2026, 6, 1, h, m);

/// 최소 필드로 AttendanceModel 생성 (v2 DateTime 기반)
AttendanceModel _make({
  DateTime? checkInAt,
  DateTime? checkOutAt,
  String status = AttendanceModel.statusPresent,
  String wageStatus = AttendanceModel.wagePending,
  int? finalWage,
}) {
  return AttendanceModel(
    id: 'att-001',
    applicationId: 'app-001',
    userId: 'uid-001',
    businessId: 'biz-001',
    businessName: '테스트 사업장',
    workDate: _workDate,
    workType: '피킹',
    checkInAt: checkInAt,
    checkOutAt: checkOutAt,
    status: status,
    wageStatus: wageStatus,
    finalWage: finalWage,
    createdAt: DateTime(2026, 6, 1, 9, 0),
  );
}

void main() {
  // ══════════════════════════════════════════════════════
  // 출퇴근 여부
  // ══════════════════════════════════════════════════════
  group('AttendanceModel: 출퇴근 여부 getter', () {
    test('checkInAt/checkOutAt 모두 null → hasCheckedIn=false, hasCheckedOut=false', () {
      final m = _make();
      expect(m.hasCheckedIn,  isFalse);
      expect(m.hasCheckedOut, isFalse);
    });

    test('checkInAt만 있음 → hasCheckedIn=true, hasCheckedOut=false', () {
      final m = _make(checkInAt: _dt(9, 5));
      expect(m.hasCheckedIn,  isTrue);
      expect(m.hasCheckedOut, isFalse);
    });

    test('checkInAt/checkOutAt 모두 있음 → 둘 다 true', () {
      final m = _make(checkInAt: _dt(9, 5), checkOutAt: _dt(18, 10));
      expect(m.hasCheckedIn,  isTrue);
      expect(m.hasCheckedOut, isTrue);
    });
  });

  // ══════════════════════════════════════════════════════
  // checkIn / checkOut getter ("HH:mm" 표시)
  // ══════════════════════════════════════════════════════
  group('AttendanceModel: 시각 표시 getter', () {
    test('checkInAt=null → checkIn getter=null', () {
      expect(_make().checkIn, isNull);
    });

    test('checkInAt=09:05 → checkIn="09:05"', () {
      expect(_make(checkInAt: _dt(9, 5)).checkIn, equals('09:05'));
    });

    test('checkOutAt=18:10 → checkOut="18:10"', () {
      expect(_make(checkOutAt: _dt(18, 10)).checkOut, equals('18:10'));
    });

    test('자정: checkInAt=00:00 → checkIn="00:00"', () {
      expect(_make(checkInAt: _dt(0, 0)).checkIn, equals('00:00'));
    });

    test('단일자리 시분: checkInAt=08:05 → checkIn="08:05"', () {
      expect(_make(checkInAt: _dt(8, 5)).checkIn, equals('08:05'));
    });
  });

  // ══════════════════════════════════════════════════════
  // 상태 Boolean getter
  // ══════════════════════════════════════════════════════
  group('AttendanceModel: 상태 getter', () {
    test('present → isLate=false, isEarlyLeave=false, isNoShow=false, isAbsent=false', () {
      final m = _make(status: AttendanceModel.statusPresent);
      expect(m.isLate,       isFalse);
      expect(m.isEarlyLeave, isFalse);
      expect(m.isNoShow,     isFalse);
      expect(m.isAbsent,     isFalse);
    });

    test('late → isLate=true만', () {
      final m = _make(status: AttendanceModel.statusLate);
      expect(m.isLate,       isTrue);
      expect(m.isEarlyLeave, isFalse);
      expect(m.isNoShow,     isFalse);
      expect(m.isAbsent,     isFalse);
    });

    test('early_leave → isEarlyLeave=true만', () {
      final m = _make(status: AttendanceModel.statusEarlyLeave);
      expect(m.isEarlyLeave, isTrue);
      expect(m.isLate,       isFalse);
      expect(m.isAbsent,     isFalse);
      expect(m.isNoShow,     isFalse);
    });

    test('absent → isAbsent=true만', () {
      final m = _make(status: AttendanceModel.statusAbsent);
      expect(m.isAbsent,     isTrue);
      expect(m.isLate,       isFalse);
      expect(m.isEarlyLeave, isFalse);
      expect(m.isNoShow,     isFalse);
    });

    test('NO_SHOW → isNoShow=true만', () {
      final m = _make(status: AttendanceModel.statusNoShow);
      expect(m.isNoShow,     isTrue);
      expect(m.isLate,       isFalse);
      expect(m.isEarlyLeave, isFalse);
      expect(m.isAbsent,     isFalse);
    });
  });

  // ══════════════════════════════════════════════════════
  // isMissedCheckout
  // ══════════════════════════════════════════════════════
  group('AttendanceModel: isMissedCheckout', () {
    test('checkInAt 없음 → false', () {
      expect(_make().isMissedCheckout, isFalse);
    });

    test('checkInAt 있고 checkOutAt 있음 → false', () {
      expect(_make(checkInAt: _dt(9, 0), checkOutAt: _dt(18, 0)).isMissedCheckout, isFalse);
    });

    test('checkInAt 있고 checkOutAt 없음, 정상 status → true', () {
      expect(
        _make(checkInAt: _dt(9, 0), status: AttendanceModel.statusPresent).isMissedCheckout,
        isTrue,
      );
    });

    test('checkInAt 있고 checkOutAt 없음, NO_SHOW → false (노쇼 제외)', () {
      expect(
        _make(checkInAt: _dt(9, 0), status: AttendanceModel.statusNoShow).isMissedCheckout,
        isFalse,
      );
    });
  });

  // ══════════════════════════════════════════════════════
  // statusLabel
  // ══════════════════════════════════════════════════════
  group('AttendanceModel: statusLabel', () {
    test('present → 출근', () {
      expect(_make(status: AttendanceModel.statusPresent).statusLabel, equals('출근'));
    });

    test('late → 지각', () {
      expect(_make(status: AttendanceModel.statusLate).statusLabel, equals('지각'));
    });

    test('absent → 결근', () {
      expect(_make(status: AttendanceModel.statusAbsent).statusLabel, equals('결근'));
    });

    test('early_leave → 조퇴', () {
      expect(_make(status: AttendanceModel.statusEarlyLeave).statusLabel, equals('조퇴'));
    });

    test('NO_SHOW → 노쇼', () {
      expect(_make(status: AttendanceModel.statusNoShow).statusLabel, equals('노쇼'));
    });

    test('알 수 없는 status → 미출근', () {
      expect(_make(status: 'unknown_status').statusLabel, equals('미출근'));
    });
  });

  // ══════════════════════════════════════════════════════
  // 급여 상태 Boolean getter
  // ══════════════════════════════════════════════════════
  group('AttendanceModel: 급여 상태 getter', () {
    test('pending → isWagePending=true만', () {
      final m = _make(wageStatus: AttendanceModel.wagePending);
      expect(m.isWagePending,     isTrue);
      expect(m.isWageCalculated,  isFalse);
      expect(m.isWageConfirmed,   isFalse);
      expect(m.isWageTransferred, isFalse);
    });

    test('calculated → isWageCalculated=true만', () {
      final m = _make(wageStatus: AttendanceModel.wageCalculated);
      expect(m.isWagePending,     isFalse);
      expect(m.isWageCalculated,  isTrue);
      expect(m.isWageConfirmed,   isFalse);
      expect(m.isWageTransferred, isFalse);
    });

    test('confirmed → isWageConfirmed=true만', () {
      final m = _make(wageStatus: AttendanceModel.wageConfirmed);
      expect(m.isWagePending,     isFalse);
      expect(m.isWageCalculated,  isFalse);
      expect(m.isWageConfirmed,   isTrue);
      expect(m.isWageTransferred, isFalse);
    });

    test('transferred → isWageTransferred=true만', () {
      final m = _make(wageStatus: AttendanceModel.wageTransferred);
      expect(m.isWagePending,     isFalse);
      expect(m.isWageCalculated,  isFalse);
      expect(m.isWageConfirmed,   isFalse);
      expect(m.isWageTransferred, isTrue);
    });
  });

  // ══════════════════════════════════════════════════════
  // wageStatusLabel
  // ══════════════════════════════════════════════════════
  group('AttendanceModel: wageStatusLabel', () {
    test('pending → 미계산', () {
      expect(_make(wageStatus: AttendanceModel.wagePending).wageStatusLabel, equals('미계산'));
    });

    test('calculated → 검토중', () {
      expect(_make(wageStatus: AttendanceModel.wageCalculated).wageStatusLabel, equals('검토중'));
    });

    test('confirmed → 확정', () {
      expect(_make(wageStatus: AttendanceModel.wageConfirmed).wageStatusLabel, equals('확정'));
    });

    test('transferred → 송금완료', () {
      expect(_make(wageStatus: AttendanceModel.wageTransferred).wageStatusLabel, equals('송금완료'));
    });

    test('알 수 없는 wageStatus → 미계산 (기본값)', () {
      expect(_make(wageStatus: 'unknown').wageStatusLabel, equals('미계산'));
    });
  });

  // ══════════════════════════════════════════════════════
  // displayWage
  // ══════════════════════════════════════════════════════
  group('AttendanceModel: displayWage', () {
    test('pending → null (미공개)', () {
      final m = _make(wageStatus: AttendanceModel.wagePending, finalWage: 100000);
      expect(m.displayWage, isNull);
    });

    test('calculated → null (관리자 검토 중, 미공개)', () {
      final m = _make(wageStatus: AttendanceModel.wageCalculated, finalWage: 100000);
      expect(m.displayWage, isNull);
    });

    test('confirmed → finalWage 반환', () {
      final m = _make(wageStatus: AttendanceModel.wageConfirmed, finalWage: 100000);
      expect(m.displayWage, equals(100000));
    });

    test('transferred → finalWage 반환', () {
      final m = _make(wageStatus: AttendanceModel.wageTransferred, finalWage: 80000);
      expect(m.displayWage, equals(80000));
    });

    test('confirmed이지만 finalWage=null → null', () {
      final m = _make(wageStatus: AttendanceModel.wageConfirmed);
      expect(m.displayWage, isNull);
    });
  });

  // ══════════════════════════════════════════════════════
  // formattedDisplayWage
  // ══════════════════════════════════════════════════════
  group('AttendanceModel: formattedDisplayWage', () {
    test('displayWage=null → "-"', () {
      final m = _make(wageStatus: AttendanceModel.wagePending, finalWage: 100000);
      expect(m.formattedDisplayWage, equals('-'));
    });

    test('100000 → "100,000원"', () {
      final m = _make(wageStatus: AttendanceModel.wageConfirmed, finalWage: 100000);
      expect(m.formattedDisplayWage, equals('100,000원'));
    });

    test('1000 → "1,000원"', () {
      final m = _make(wageStatus: AttendanceModel.wageConfirmed, finalWage: 1000);
      expect(m.formattedDisplayWage, equals('1,000원'));
    });

    test('999 → "999원" (천단위 없음)', () {
      final m = _make(wageStatus: AttendanceModel.wageConfirmed, finalWage: 999);
      expect(m.formattedDisplayWage, equals('999원'));
    });

    test('1234567 → "1,234,567원"', () {
      final m = _make(wageStatus: AttendanceModel.wageTransferred, finalWage: 1234567);
      expect(m.formattedDisplayWage, equals('1,234,567원'));
    });

    test('0 → "0원"', () {
      final m = _make(wageStatus: AttendanceModel.wageConfirmed, finalWage: 0);
      expect(m.formattedDisplayWage, equals('0원'));
    });
  });
}
