// [R7-PREDEVICE-STABILIZATION.1A] 고지 문구가 **주장하는 것**이 사실인가.
//
// ── 왜 필요한가 ─────────────────────────────────────────────────────
//   `.1` 은 근로자 문구에 "1분 늦어도 30분" 을 적었다. 유예(`lateGrace`)
//   5분인 사업장에서 1분 지각은 **정시로 처리**되고 차감이 0 이다 —
//   거짓 고지였다. `.1` 의 테스트는 계산을 `grace + 1` 로 확인하면서
//   문구는 "1분" 으로 핀했기 때문에 둘이 어긋난 것을 잡지 못했다.
//
//   그래서 여기서는 **문구에서 숫자를 뽑아** 같은 설정의 canonical 계산과
//   맞춘다. 사람이 고른 예시 문장이 아니라 기계가 읽은 숫자를 비교하므로,
//   문구든 계산식이든 한쪽만 바뀌면 깨진다.
//
//   급여 계산식과 7개 관리자 설정은 이 Phase 에서 바꾸지 않았다 — 여기서
//   확인하는 것은 **설명이 계산과 같은 말을 하는가** 뿐이다.
import 'package:flutter_test/flutter_test.dart';

import 'package:ALfit/models/core/business_model.dart';
import 'package:ALfit/utils/attendance_policy_disclosure.dart';
import 'package:ALfit/utils/attendance_rounding_helper.dart';

final _ref = DateTime.utc(2026, 1, 1, 9);

RoundingResult _in(int offset, AttendanceRules r) =>
    processCheckin(offsetMinutes: offset, referenceAt: _ref, rules: r);
RoundingResult _out(int offset, AttendanceRules r) =>
    processCheckout(offsetMinutes: offset, referenceAt: _ref, rules: r);

String _value(AttendanceRules r, String label) {
  final hit = attendancePolicyLines(r).where((l) => l.label == label);
  expect(hit, isNotEmpty, reason: '"$label" 줄이 없다');
  return hit.first.value;
}

/// 설정 조합 — 유예가 단위보다 큰 경우(6분 지각 → 10분 차감)를 포함한다.
List<AttendanceRules> _matrix() {
  final out = <AttendanceRules>[];
  for (final grace in const [0, 1, 5, 10, 30]) {
    for (final unit in const [5, 10, 30, 60]) {
      for (final window in const [0, 30, 60]) {
        out.add(AttendanceRules.defaults().copyWith(
          earlyWindow: 30,
          earlyArrivalUnit: unit,
          lateGrace: grace,
          lateUnit: unit,
          lateWindow: window,
          overtimeUnit: unit,
          earlyLeaveUnit: unit,
        ));
      }
    }
  }
  return out;
}

String _desc(AttendanceRules r) =>
    'grace=${r.lateGrace} unit=${r.lateUnit} window=${r.lateWindow} '
    'ewin=${r.earlyWindow} eunit=${r.earlyArrivalUnit} '
    'ounit=${r.overtimeUnit} elunit=${r.earlyLeaveUnit}';

void main() {
  group('PDC 지각 — 사례 숫자가 설정을 따른다', () {
    test('PDC-01 "N분 늦으면 M분" 의 N·M 이 실제 계산과 같다', () {
      final re = RegExp(r'\((\d+)분 늦으면 (\d+)분\)');
      for (final r in _matrix()) {
        final v = _value(r, '지각 처리');
        final m = re.firstMatch(v);
        expect(m, isNotNull,
            reason: '사례 문구 형식을 찾지 못했다 [${_desc(r)}]: $v');

        final offset = int.parse(m!.group(1)!);
        final deduction = int.parse(m.group(2)!);

        // ① 그 도착이 **실제로 지각으로 인정되는가** — 유예 안이면 거짓이다.
        final res = _in(offset, r);
        expect(res.type, RoundingType.late,
            reason: '$offset분 도착은 지각이 아니다(${res.type.name}) '
                '— 문구가 거짓이다 [${_desc(r)}]');

        // ② 차감 분이 문구와 같은가.
        expect(res.roundedOffset, deduction,
            reason: '$offset분 지각의 실제 차감은 ${res.roundedOffset}분인데 '
                '문구는 $deduction분이라고 말한다 [${_desc(r)}]');

        // ③ 유예 **안**(경계 포함)은 차감이 없다 — N 이 최소값이어야 한다.
        final atGrace = _in(r.lateGrace, r);
        expect(atGrace.roundedOffset, 0,
            reason: '유예 경계가 차감된다 [${_desc(r)}]');
        expect(offset, r.lateGrace + 1,
            reason: '첫 지각 사례는 유예를 1분 넘긴 시점이다 [${_desc(r)}]');
      }
    });

    test('PDC-02 유예 5분 사업장은 "1분" 을 사례로 쓰지 않는다', () {
      final r = AttendanceRules.defaults()
          .copyWith(lateGrace: 5, lateUnit: 30);
      final v = _value(r, '지각 처리');
      expect(v.contains('1분 늦으면'), isFalse, reason: v);
      expect(v.contains('1분 늦어도'), isFalse,
          reason: '`.1` 의 거짓 문구가 돌아왔다: $v');
      expect(v.contains('6분 늦으면 30분'), isTrue, reason: v);
      // 실제로 1분 지각은 정시다.
      expect(_in(1, r).type, RoundingType.lateGrace);
      expect(_in(1, r).roundedOffset, 0);
    });

    test('PDC-03 유예 0분 사업장은 "1분" 이 맞는 사례다', () {
      final r = AttendanceRules.defaults()
          .copyWith(lateGrace: 0, lateUnit: 30);
      expect(_value(r, '지각 처리').contains('1분 늦으면 30분'), isTrue);
      expect(_in(1, r).type, RoundingType.late);
    });

    test('PDC-04 유예+1 이 단위보다 크면 차감도 단위와 다르다', () {
      // 유예 5 · 단위 5 → 6분 지각은 ceil(6/5)*5 = 10분 차감이다.
      final r = AttendanceRules.defaults()
          .copyWith(lateGrace: 5, lateUnit: 5);
      expect(_in(6, r).roundedOffset, 10, reason: '계산 전제 확인');
      final v = _value(r, '지각 처리');
      expect(v.contains('6분 늦으면 10분'), isTrue,
          reason: '단위(5분)를 그대로 적으면 거짓이다: $v');
    });
  });

  group('PDC 조퇴 — 유예가 없다', () {
    test('PDC-05 "1분 일찍 가도 M분" 의 M 이 실제 차감과 같다', () {
      final re = RegExp(r'\(1분 일찍 가도 (\d+)분\)');
      for (final r in _matrix()) {
        final v = _value(r, '조퇴 처리');
        final m = re.firstMatch(v);
        expect(m, isNotNull, reason: '사례 문구를 찾지 못했다 [${_desc(r)}]: $v');
        final deduction = int.parse(m!.group(1)!);

        final res = _out(-1, r);
        expect(res.type, RoundingType.earlyLeave,
            reason: '1분 일찍 퇴근이 조퇴가 아니다 [${_desc(r)}]');
        expect(-res.roundedOffset, deduction,
            reason: '실제 차감 ${-res.roundedOffset}분 ≠ 문구 $deduction분 '
                '[${_desc(r)}]');
      }
    });
  });

  group('PDC 조출·연장 — "남는 시간은 인정되지 않아요" 가 사실이다', () {
    test('PDC-06 연장 인정분은 단위의 배수이고 실제보다 크지 않다', () {
      for (final r in _matrix()) {
        // 창을 1분 넘긴 시점부터 창+3단위까지 훑는다.
        for (var extra = 1; extra <= r.overtimeUnit * 3 + 1; extra++) {
          final offset = r.lateWindow + extra;
          final res = _out(offset, r);
          if (res.type != RoundingType.overtime) continue;
          expect(res.roundedOffset % r.overtimeUnit, 0,
              reason: '$offset분 연장 인정 ${res.roundedOffset}분이 '
                  '${r.overtimeUnit}분 배수가 아니다 [${_desc(r)}]');
          expect(res.roundedOffset, lessThanOrEqualTo(offset),
              reason: '실제보다 많이 인정했다 — "남는 시간은 인정되지 않아요" 와 '
                  '반대다 [${_desc(r)}]');
        }
      }
    });

    test('PDC-07 조출 인정분도 단위의 배수이고 실제보다 크지 않다', () {
      for (final r in _matrix()) {
        for (var extra = 1; extra <= r.earlyArrivalUnit * 3 + 1; extra++) {
          final offset = -(r.earlyWindow + extra);
          final res = _in(offset, r);
          if (res.type != RoundingType.earlyArrival) continue;
          final recognized = -res.roundedOffset;
          expect(recognized % r.earlyArrivalUnit, 0,
              reason: '${-offset}분 조출 인정 $recognized분이 '
                  '${r.earlyArrivalUnit}분 배수가 아니다 [${_desc(r)}]');
          expect(recognized, lessThanOrEqualTo(-offset),
              reason: '실제보다 많이 인정했다 [${_desc(r)}]');
        }
      }
    });
  });

  group('PDC 경계 문구 — "까지는 정시" 가 사실이다', () {
    test('PDC-08 earlyWindow·lateGrace·lateWindow 경계가 모두 정시다', () {
      for (final r in _matrix()) {
        // 시작 earlyWindow 분 전 도착 → 정시(조출 아님).
        expect(_in(-r.earlyWindow, r).type, isNot(RoundingType.earlyArrival),
            reason: '"시작 ${r.earlyWindow}분 전까지는 정시" 가 거짓 '
                '[${_desc(r)}]');
        expect(_in(-r.earlyWindow, r).roundedOffset, 0, reason: _desc(r));

        // 유예 경계 도착 → 지각 아님.
        expect(_in(r.lateGrace, r).type, isNot(RoundingType.late),
            reason: '"${r.lateGrace}분까지는 정시" 가 거짓 [${_desc(r)}]');

        // 종료 후 lateWindow 경계 퇴근 → 연장 아님.
        expect(_out(r.lateWindow, r).type, isNot(RoundingType.overtime),
            reason: '"종료 후 ${r.lateWindow}분까지는 정시" 가 거짓 '
                '[${_desc(r)}]');
        expect(_out(r.lateWindow, r).roundedOffset, 0, reason: _desc(r));
      }
    });
  });

  group('PDC 고지 계약 유지', () {
    test('PDC-09 줄 수 7 · 필드 7 이 모두 문장에 나타난다', () {
      const base = AttendanceRules();
      expect(attendancePolicyLines(base).length, 7);
      String render(AttendanceRules r) => attendancePolicyLines(r)
          .map((l) => '${l.label}=${l.value}')
          .join('|');
      final baseText = render(base);
      final variants = <String, AttendanceRules>{
        'earlyWindow': base.copyWith(earlyWindow: 45),
        'earlyArrivalUnit': base.copyWith(earlyArrivalUnit: 15),
        'lateGrace': base.copyWith(lateGrace: 9),
        'lateUnit': base.copyWith(lateUnit: 15),
        'lateWindow': base.copyWith(lateWindow: 45),
        'overtimeUnit': base.copyWith(overtimeUnit: 25),
        'earlyLeaveUnit': base.copyWith(earlyLeaveUnit: 15),
      };
      variants.forEach((k, v) {
        expect(render(v) == baseText, isFalse, reason: '$k 가 고지에 없다');
      });
      for (final bad in ['earlyWindow', 'lateUnit', 'overtimeUnit']) {
        expect(baseText.contains(bad), isFalse);
      }
    });

    test('PDC-10 사례 숫자를 formatter 가 직접 계산하지 않는다', () {
      // 식을 두 곳에 두면 갈린다 — 계산 모듈의 함수를 쓴다.
      final d = attendancePolicyLines(const AttendanceRules());
      expect(d, isNotEmpty);
      final r = AttendanceRules.defaults().copyWith(lateGrace: 7, lateUnit: 20);
      expect(firstLateOffsetMinutes(r), 8);
      expect(firstLateDeductionMinutes(r), _in(8, r).roundedOffset);
      expect(firstEarlyLeaveDeductionMinutes(r), -_out(-1, r).roundedOffset);
    });
  });
}
