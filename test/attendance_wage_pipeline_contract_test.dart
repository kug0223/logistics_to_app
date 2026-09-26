// [PREDEVICE-ATTENDANCE-WAGE.1] 시간이 돈이 되는 순서를 고정한다
//
// READ + DEV runtime으로 확인된 canonical pipeline:
//
//   raw punch (now, 서버 시각)
//     → 서버가 businesses/{id}.attendanceRules로 반올림 (_processCheckin/_processCheckout)
//     → checkIn / checkOut 에 저장, originalCheckIn / originalCheckOut 은 원본 보존
//     → [선택] 관리자 시간 보정 (callableBatchAdjustAttendanceTime)
//     → actualMinutes = checkOut - checkIn
//     → payable(workMinutes) = max(0, actualMinutes - breakMinutes)
//     → 금액
//
// 즉 반올림은 펀치 때 한 번만 일어나고 급여 계산은 다시 반올림하지 않는다.
// 휴게 차감은 반올림 **뒤**다. 이 순서가 바뀌면 금액이 바뀐다.
//
// 급여 계산의 기준 시각(actualStart/actualEnd)은 관리자가 보내는 값이다
// ([DESIGN-F-M1] 재탐색 금지 — 반올림·야간교대·기기 오류 때문에 관리자 재량을
// 허용한 설계). 그래서 이 테스트는 "서버가 checkIn을 다시 읽는다"를 요구하지
// 않고, 대신 금액의 기준이 되는 임금 단가가 snapshot으로 잠겨 있음을 고정한다.
//
// DEV 실측 요약:
//   출근 offset ≤ -31 → 조출(trunc, 0 방향) / -30..+5 → 예정시각 / +6↑ → 지각(ceil)
//   퇴근 offset ≤ -1  → 조퇴(ceil) / 0..+30 → 예정시각 / +31↑ → 연장(floor)
//   시급 480분 × 11,000 = 88,000 · 일급은 근무시간 비례(450/480 → 93,750)
//   야간 22:00~06:00 → payable 420, 야간 420분, 88,000 대신 115,500
//   snapshotWage 15,000이 전송된 13,000을 이긴다

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _fnsPath = 'functions/src/index.ts';

String _src(String p) {
  final f = File(p);
  if (!f.existsSync()) throw StateError('$p 를 찾지 못함');
  return f.readAsStringSync();
}

String _codeOf(String b) =>
    b.split('\n').where((l) => !l.trimLeft().startsWith('//')).join('\n');

String _flat(String b) => b.replaceAll(RegExp(r'\s+'), ' ');

String _fnSlice(String source, String decl) {
  final start = source.indexOf(decl);
  if (start < 0) throw StateError('$decl 을 찾지 못함');
  final next = source.indexOf('\nfunction ', start + decl.length);
  final next2 = source.indexOf('\nexport ', start + decl.length);
  final end = [next, next2].where((i) => i > 0).fold<int>(source.length,
      (a, b) => b < a ? b : a);
  return source.substring(start, end);
}

void main() {
  final fns = _src(_fnsPath);
  final code = _codeOf(fns);
  final flat = _flat(code);

  group('반올림은 펀치 시점에 서버가 한 번만 한다', () {
    test('규칙은 사업장 문서에서 서버가 직접 읽는다 — 클라이언트 값 불신', () {
      expect(flat.contains('bizSnap.data()?.attendanceRules'), true,
          reason: '반올림 규칙을 클라이언트가 보내면 임금을 조작할 수 있다');
      expect(flat.contains('_clampAttendanceRules('), true,
          reason: '단위 0/음수는 division-by-zero와 판정 뒤집기를 만든다');
    });

    test('원본 펀치 시각이 보존된다', () {
      expect(flat.contains('originalCheckIn: admin.firestore.Timestamp.fromDate(now)'),
          true);
      expect(code.contains('originalCheckOut'), true);
    });

    test('출근 반올림 방향 — 조출 trunc, 정시 0, 지각 ceil', () {
      final f = _codeOf(_fnSlice(fns, 'function _processCheckin('));
      expect(f.contains('Math.trunc(offsetMinutes / earlyArrivalUnit)'), true,
          reason: '음수 오프셋에 floor를 쓰면 근로자에게 유리한 쪽으로 밀린다');
      expect(f.contains('Math.ceil(offsetMinutes / lateUnit)'), true);
      expect(f.contains('offsetMinutes <= lateGrace'), true,
          reason: 'earlyWindow 이내 조기 도착은 예정 시각으로 정규화된다');
      expect(f.contains('isLate: offsetMinutes > lateGrace'), true,
          reason: '지각 판정과 반올림이 같은 lateGrace를 공유한다');
    });

    test('퇴근 반올림 방향 — 연장 floor, 정시 0, 조퇴 ceil', () {
      final f = _codeOf(_fnSlice(fns, 'function _processCheckout('));
      expect(f.contains('Math.floor(offsetMinutes / overtimeUnit)'), true);
      expect(f.contains('Math.ceil(earlyDiff / earlyLeaveUnit)'), true);
      expect(f.contains('offsetMinutes > lateWindow'), true,
          reason: 'lateWindow 이내 연장은 예정 종료로 clamp된다 — 무급',
      );
    });
  });

  group('payable minutes는 반올림 뒤에 휴게를 뺀다', () {
    final w = _codeOf(_fnSlice(fns, 'function srvWageCalculate('));

    test('순서: actualMinutes → 휴게 차감 → workMinutes', () {
      expect(
        _flat(w).contains(
            'const workMinutes = Math.max(0, actualMinutes - p.breakMinutes);'),
        true,
        reason: '휴게를 반올림 전에 빼면 금액이 달라진다',
      );
    });

    test('payable은 음수가 될 수 없다', () {
      expect(w.contains('Math.max(0, actualMinutes - p.breakMinutes)'), true);
      // 입력 단계에서도 막는다 — 휴게가 체류시간을 넘으면 계산 자체를 거부.
      expect(code.contains('실제 근무 체류시간'), true,
          reason: '휴게 > 체류시간을 조용히 0으로 만들지 않고 거부한다');
    });

    test('급여 계산은 다시 반올림하지 않는다', () {
      expect(w.contains('attendanceRules'), false);
      expect(w.contains('_processCheckin'), false);
      expect(w.contains('_processCheckout'), false);
    });
  });

  group('임금 단가는 snapshot이 이긴다', () {
    test('체크인 시점 snapshotWage가 전송된 baseWage를 덮는다', () {
      expect(
        _flat(code).contains(
          'const effectiveBaseWage = (snapshotWage != null && snapshotWage > 0) '
          '? snapshotWage : d.baseWage;',
        ),
        true,
        reason: '공고 임금을 고치면 기존 확정자 급여가 바뀌는 경로가 된다',
      );
      expect(flat.contains('snapshotWage: typeof appData.wage === "number"'), true,
          reason: '스냅샷은 체크인 시점에 지원서 임금으로 찍힌다');
    });
  });

  group('돈이 확정된 뒤에는 근태가 조용히 바뀌지 않는다', () {
    final adj = _codeOf(
        _fnSlice(fns, 'export const callableBatchAdjustAttendanceTime'));

    test('confirmed·transferred는 시간 수정 자체를 건너뛴다', () {
      expect(
        _flat(adj).contains(
            'if (serverStatus === "confirmed" || serverStatus === "transferred")'),
        true,
        reason: '이미 확정·이체된 금액과 시간이 갈라지면 안 된다',
      );
    });

    test('calculated는 수정 시 금액이 무효화된다 — stale 금지', () {
      expect(
        _flat(adj).contains(
            'const effectiveResetWageDetail = resetWageDetail || serverStatus === "calculated";'),
        true,
      );
      for (final f in ['wageStatus', 'wageDetail', 'finalWage', 'yearMonth']) {
        expect(adj.contains('updates["$f"]'), true,
            reason: '$f 가 남으면 시간과 금액이 어긋난 채 보인다');
      }
    });

    test('누가 언제 고쳤는지 남는다', () {
      for (final f in ['isModified', 'modifiedAt', 'modifiedBy']) {
        expect(adj.contains('$f:'), true);
      }
    });
  });

  group('NO_SHOW·결근은 정상 급여가 되지 않는다', () {
    test('실제 근무로 집계되는 상태는 세 가지뿐이다', () {
      expect(
        flat.contains(
            'const ACTUAL_WORK_STATUSES = ["present", "late", "early_leave"];'),
        true,
        reason: 'NO_SHOW도 wageStatus가 confirmed라 그것만 보면 근무로 오해된다',
      );
    });

    test('NO_SHOW·결근은 finalWage 0으로 마감된다', () {
      expect(flat.contains('status: "NO_SHOW", wageStatus: "confirmed", finalWage: 0'),
          true);
      expect(
        flat.contains('status: "absent", finalWage: 0, wageStatus: "confirmed"'),
        true,
      );
    });

    test('미이체 집계에서 0원 비지급 건을 제외한다', () {
      // [.6-P1] 판정이 canonical helper 로 옮겨가고, Home·이체목록·배지·
      //   카운트·summary 가 모두 그것을 쓴다.
      final flat = _flat(code);
      expect(flat.contains('function srvIsNonPayableZero('), true);
      expect(flat.contains('srvPayableForTransfer('), true);
    });
  });

  group('주휴수당을 자동으로 더하지 않는다', () {
    test('계산식에 주휴 가산이 없다', () {
      final w = _codeOf(_fnSlice(fns, 'function srvWageCalculate('));
      expect(
        w.contains(
            'const totalAmount = baseAmount + overtimeAmount + nightAmount + p.additionalAmount;'),
        true,
        reason: '총액은 기본·연장·야간·추가 네 항뿐이다 — 주휴 항이 생기면 정책 변경이다',
      );
      expect(w.contains('weeklyHoliday'), false,
          reason: '주휴수당 자동계산은 도입하지 않는다');
    });
  });
}
