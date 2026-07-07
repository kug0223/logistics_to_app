// test/simulation/wage_confirm_tab_simulation_test.dart
//
// WageConfirmDialog 3탭 분류 로직 시뮬레이션
// 목적: _initData의 wageStatus 기반 탭 분류 로직을 순수 함수로 재구현하여
//       상수값 일관성 및 AttendanceModel getter 동작을 종합 검증한다.

import 'package:flutter_test/flutter_test.dart';
import 'package:ALfit/models/core/attendance_model.dart';

// ── 탭 분류 헬퍼 (WageConfirmDialog._initData 로직 재구현) ──
//
// 실제 코드:
//   if (wageStatus == wageTransferred)                       → _transferredWorkers (탭 2)
//   else if (wageStatus == wageCalculated || wageConfirmed)  → _calculatedWorkers  (탭 1)
//   else if (wageStatus == wagePending)                      → _pendingWorkers      (탭 0)
//   else                                                     → 분류 안됨 (-1)
//
// 주의: attendance.checkOut == null 인 경우 분류 자체를 건너뜀
//       → 여기서는 wageStatus 분류 로직만 검증, checkOut 조건은 별도 검증

/// -1 = 분류 안됨, 0 = 미확정, 1 = 확정내역, 2 = 마감내역
int classifyWageTab(String? wageStatus) {
  if (wageStatus == AttendanceModel.wageTransferred) return 2;
  if (wageStatus == AttendanceModel.wageCalculated ||
      wageStatus == AttendanceModel.wageConfirmed) return 1;
  if (wageStatus == AttendanceModel.wagePending) return 0;
  return -1;
}

DateTime? _parseTime(DateTime date, String? hhmm) {
  if (hhmm == null) return null;
  final parts = hhmm.split(':');
  return DateTime(date.year, date.month, date.day,
      int.parse(parts[0]), int.parse(parts[1]));
}

/// 최소 AttendanceModel 생성 헬퍼
AttendanceModel _att({
  String wageStatus = 'pending',
  String? checkOut,
}) {
  final workDate = DateTime(2026, 6, 15);
  return AttendanceModel(
    id: 'test-id',
    applicationId: 'app-id',
    userId: 'user-id',
    businessId: 'biz-id',
    businessName: '테스트 사업장',
    workDate: workDate,
    workType: '서빙',
    status: 'present',
    createdAt: DateTime(2026, 6, 15, 9),
    wageStatus: wageStatus,
    checkOutAt: _parseTime(workDate, checkOut),
  );
}

void main() {
  // ════════════════════════════════════════════════════════════════════
  // 상수값 일관성 검증
  // ════════════════════════════════════════════════════════════════════
  group('AttendanceModel wageStatus 상수 일관성', () {
    test("wagePending == 'pending'", () {
      expect(AttendanceModel.wagePending, 'pending');
    });

    test("wageCalculated == 'calculated'", () {
      expect(AttendanceModel.wageCalculated, 'calculated');
    });

    test("wageConfirmed == 'confirmed'", () {
      expect(AttendanceModel.wageConfirmed, 'confirmed');
    });

    test("wageTransferred == 'transferred'", () {
      expect(AttendanceModel.wageTransferred, 'transferred');
    });

    test('4개 상수가 모두 서로 다른 값', () {
      final constants = {
        AttendanceModel.wagePending,
        AttendanceModel.wageCalculated,
        AttendanceModel.wageConfirmed,
        AttendanceModel.wageTransferred,
      };
      expect(constants.length, 4);
    });
  });

  // ════════════════════════════════════════════════════════════════════
  // 탭 0: 미확정 탭 (wagePending)
  // ════════════════════════════════════════════════════════════════════
  group('탭 0 — 미확정 탭 (pending)', () {
    test("wageStatus='pending' → 탭 0", () {
      expect(classifyWageTab('pending'), 0);
    });

    test('wagePending 상수값 → 탭 0', () {
      expect(classifyWageTab(AttendanceModel.wagePending), 0);
    });

    test('기본 AttendanceModel (wageStatus 생략) → wagePending → 탭 0', () {
      final att = _att(); // wageStatus 기본값 = 'pending'
      expect(classifyWageTab(att.wageStatus), 0);
    });

    test('미확정 상태에서 isWagePending=true', () {
      final att = _att(wageStatus: 'pending');
      expect(att.isWagePending, isTrue);
    });

    test('미확정 상태에서 isWageCalculated=false', () {
      final att = _att(wageStatus: 'pending');
      expect(att.isWageCalculated, isFalse);
    });

    test('미확정 상태에서 isWageConfirmed=false', () {
      final att = _att(wageStatus: 'pending');
      expect(att.isWageConfirmed, isFalse);
    });

    test('미확정 상태에서 isWageTransferred=false', () {
      final att = _att(wageStatus: 'pending');
      expect(att.isWageTransferred, isFalse);
    });
  });

  // ════════════════════════════════════════════════════════════════════
  // 탭 1: 확정내역 탭 (calculated 또는 confirmed)
  // ════════════════════════════════════════════════════════════════════
  group('탭 1 — 확정내역 탭 (calculated / confirmed)', () {
    test("wageStatus='calculated' → 탭 1", () {
      expect(classifyWageTab('calculated'), 1);
    });

    test("wageStatus='confirmed' → 탭 1", () {
      expect(classifyWageTab('confirmed'), 1);
    });

    test('wageCalculated 상수값 → 탭 1', () {
      expect(classifyWageTab(AttendanceModel.wageCalculated), 1);
    });

    test('wageConfirmed 상수값 → 탭 1', () {
      expect(classifyWageTab(AttendanceModel.wageConfirmed), 1);
    });

    test('calculated → isWageCalculated=true, 나머지 false', () {
      final att = _att(wageStatus: 'calculated');
      expect(att.isWageCalculated, isTrue);
      expect(att.isWagePending, isFalse);
      expect(att.isWageConfirmed, isFalse);
      expect(att.isWageTransferred, isFalse);
    });

    test('confirmed → isWageConfirmed=true, 나머지 false', () {
      final att = _att(wageStatus: 'confirmed');
      expect(att.isWageConfirmed, isTrue);
      expect(att.isWagePending, isFalse);
      expect(att.isWageCalculated, isFalse);
      expect(att.isWageTransferred, isFalse);
    });

    test('calculated 상태 AttendanceModel → 탭 1', () {
      final att = _att(wageStatus: AttendanceModel.wageCalculated, checkOut: '18:00:00');
      expect(classifyWageTab(att.wageStatus), 1);
    });

    test('confirmed 상태 AttendanceModel → 탭 1', () {
      final att = _att(wageStatus: AttendanceModel.wageConfirmed, checkOut: '18:00:00');
      expect(classifyWageTab(att.wageStatus), 1);
    });

    test('calculated 와 confirmed 모두 탭 1로 같은 버킷에 속함', () {
      expect(classifyWageTab('calculated'), classifyWageTab('confirmed'));
    });
  });

  // ════════════════════════════════════════════════════════════════════
  // 탭 2: 마감내역 탭 (transferred)
  // ════════════════════════════════════════════════════════════════════
  group('탭 2 — 마감내역 탭 (transferred)', () {
    test("wageStatus='transferred' → 탭 2", () {
      expect(classifyWageTab('transferred'), 2);
    });

    test('wageTransferred 상수값 → 탭 2', () {
      expect(classifyWageTab(AttendanceModel.wageTransferred), 2);
    });

    test('transferred → isWageTransferred=true, 나머지 false', () {
      final att = _att(wageStatus: 'transferred');
      expect(att.isWageTransferred, isTrue);
      expect(att.isWagePending, isFalse);
      expect(att.isWageCalculated, isFalse);
      expect(att.isWageConfirmed, isFalse);
    });

    test('transferred 상태 AttendanceModel → 탭 2', () {
      final att = _att(wageStatus: AttendanceModel.wageTransferred, checkOut: '18:00:00');
      expect(classifyWageTab(att.wageStatus), 2);
    });

    test('transferred 는 pending/calculated/confirmed 와 다른 탭', () {
      expect(classifyWageTab('transferred'), isNot(0));
      expect(classifyWageTab('transferred'), isNot(1));
    });
  });

  // ════════════════════════════════════════════════════════════════════
  // 분류 불가 케이스 (-1)
  // ════════════════════════════════════════════════════════════════════
  group('분류 불가 (-1)', () {
    test('null wageStatus → -1', () {
      expect(classifyWageTab(null), -1);
    });

    test("알 수 없는 값 'unknown' → -1", () {
      expect(classifyWageTab('unknown'), -1);
    });

    test("빈 문자열 '' → -1", () {
      expect(classifyWageTab(''), -1);
    });
  });

  // ════════════════════════════════════════════════════════════════════
  // AttendanceModel.wageStatusLabel 검증
  // ════════════════════════════════════════════════════════════════════
  group('wageStatusLabel getter', () {
    test("pending → '미계산'", () {
      final att = _att(wageStatus: 'pending');
      expect(att.wageStatusLabel, '미계산');
    });

    test("calculated → '검토중'", () {
      final att = _att(wageStatus: 'calculated');
      expect(att.wageStatusLabel, '검토중');
    });

    test("confirmed → '확정'", () {
      final att = _att(wageStatus: 'confirmed');
      expect(att.wageStatusLabel, '확정');
    });

    test("transferred → '송금완료'", () {
      final att = _att(wageStatus: 'transferred');
      expect(att.wageStatusLabel, '송금완료');
    });

    test("unknown wageStatus → '미계산' (default fallback)", () {
      final att = _att(wageStatus: 'some_unknown');
      expect(att.wageStatusLabel, '미계산');
    });
  });

  // ════════════════════════════════════════════════════════════════════
  // 각 상태별 getter 상호 배타성 종합 검증
  // ════════════════════════════════════════════════════════════════════
  group('wageStatus getter 상호 배타성', () {
    final statuses = [
      AttendanceModel.wagePending,
      AttendanceModel.wageCalculated,
      AttendanceModel.wageConfirmed,
      AttendanceModel.wageTransferred,
    ];

    for (final ws in statuses) {
      test('wageStatus=$ws → 해당 getter만 true, 나머지 false', () {
        final att = _att(wageStatus: ws);
        final getters = {
          'isWagePending':     att.isWagePending,
          'isWageCalculated':  att.isWageCalculated,
          'isWageConfirmed':   att.isWageConfirmed,
          'isWageTransferred': att.isWageTransferred,
        };
        final trueCount = getters.values.where((v) => v).length;
        expect(trueCount, 1,
            reason: 'wageStatus=$ws 일 때 정확히 하나의 getter만 true 여야 함, 실제: $getters');
      });
    }
  });

  // ════════════════════════════════════════════════════════════════════
  // checkOut 유무와 탭 분류의 관계 (실제 _initData는 checkOut==null 건너뜀)
  // ════════════════════════════════════════════════════════════════════
  group('checkOut 유무 영향', () {
    test('checkOut 있음, wageStatus=pending → 탭 0으로 분류됨', () {
      final att = _att(wageStatus: 'pending', checkOut: '18:00:00');
      // checkOut이 있어야 _initData가 분류 로직에 진입
      expect(att.hasCheckedOut, isTrue);
      expect(classifyWageTab(att.wageStatus), 0);
    });

    test('checkOut 없음 → _initData에서 건너뜀 (분류 로직 미진입)', () {
      final att = _att(wageStatus: 'pending', checkOut: null);
      // checkOut이 없으면 _initData는 continue → 탭 분류 자체를 안 함
      expect(att.hasCheckedOut, isFalse);
      // classifyWageTab은 호출되지 않아야 하는 케이스임을 문서화
      // (테스트에서는 wageStatus는 여전히 pending → 탭 0이지만
      //  실제 UI에서는 이 근무자가 어떤 탭에도 나타나지 않음)
      expect(classifyWageTab(att.wageStatus), 0); // 로직 자체는 0 반환
    });
  });
}
