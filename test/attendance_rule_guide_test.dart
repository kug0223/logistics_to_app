import 'package:flutter_test/flutter_test.dart';

import 'package:ALfit/models/core/business_model.dart';
import 'package:ALfit/utils/attendance_policy_disclosure.dart';
import 'package:ALfit/utils/attendance_rounding_helper.dart';

/// [ATTENDANCE-RULE-GUIDE.29-A1] '근태 인정 기준' 문구 ↔ 기존 계산(processCheckin/out) 경계 대조.
///   계산은 바꾸지 않는다 — 문구가 계산과 같은 말을 하는지, 사례가 계산 결과인지 본다.
final _ref = DateTime(2026, 1, 1, 9);
int _in(AttendanceRules r, int offset) =>
    processCheckin(offsetMinutes: offset, referenceAt: _ref, rules: r).roundedOffset;
int _out(AttendanceRules r, int offset) =>
    processCheckout(offsetMinutes: offset, referenceAt: _ref, rules: r).roundedOffset;

List<String> _points(AttendanceRuleGuide g, String item) =>
    g.sections.expand((s) => s.items).firstWhere((i) => i.title == item).points;
List<String> _examples(AttendanceRuleGuide g, String item) => g.sections
    .expand((s) => s.items)
    .firstWhere((i) => i.title == item)
    .examples
    .map(attendanceRuleExampleText)
    .toList();

void main() {
  const r = AttendanceRules(); // 기본값: 조출창 30·조출단위 30·유예 5·지각단위 30·연장창 30·연장단위 10·조퇴단위 30

  group('문구가 말하는 경계 = 계산의 경계', () {
    test('ARG-1 지각 — 유예 전/정확히/1분 후, 올림은 늦은 시간 **전체**(유예를 뺀 나머지 아님)', () {
      expect(_in(r, 4), 0);
      expect(_in(r, 5), 0, reason: "'5분까지는 정시'");
      expect(_in(r, 6), 30, reason: "6분 늦음 → 전체 6분을 30분 단위로 올림 = 30(나머지 1분 올림이어도 30이라 아래로 구분)");
      // 유예 5·단위 5 에서 갈린다: 전체 올림이면 6→10, 나머지 올림이면 6→5.
      const r5 = AttendanceRules(lateGrace: 5, lateUnit: 5);
      expect(_in(r5, 6), 10, reason: "'늦은 시간 전체를 올려' 가 맞다");
      expect(_points(attendanceRuleGuide(r), '지각').last, contains('늦은 시간 전체를 30분 단위로 올려'));
    });

    test("ARG-2 일찍 출근 29/30/31분 — '30분 전까지'는 30분 포함, '30분보다 일찍'은 31분부터", () {
      expect(_in(r, -29), 0);
      expect(_in(r, -30), 0, reason: "'시작 30분 전까지의 출근은 시작 시각부터'");
      expect(_in(r, -31), -30, reason: '31분 일찍 → 일찍 온 31분을 30분 단위로 = 30분 인정');
      expect(_in(r, -59), -30, reason: "'단위에 못 미치는 분은 인정되지 않아요'");
      expect(_points(attendanceRuleGuide(r), '일찍 출근').first, '시작 30분 전까지의 출근은 시작 시각부터 인정해요.');
    });

    test("ARG-3 늦게 퇴근 29/30/31분 — 연장 단위는 기본 10분(30으로 짐작하지 않음)", () {
      expect(_out(r, 29), 0);
      expect(_out(r, 30), 0, reason: "'종료 후 30분까지의 퇴근은 종료 시각까지'");
      expect(_out(r, 31), 30, reason: '31분 → 10분 단위로 내림 = 30');
      expect(_points(attendanceRuleGuide(r), '늦게 퇴근').last, contains('10분 단위로 인정'));
    });

    test('ARG-4 조퇴 1분/정확히 단위/단위+1', () {
      expect(_out(r, -1), -30);
      expect(_out(r, -30), -30);
      expect(_out(r, -31), -60);
      expect(_points(attendanceRuleGuide(r), '조퇴').single, contains('30분 단위로 올려 인정 종료를 앞당겨요'));
    });
  });

  group('사례 = 이 근무 시각으로 돌린 계산 결과(값 복사 아님)', () {
    test('ARG-5 17:35–18:35 기본 기준', () {
      final g = attendanceRuleGuide(r, startHHmm: '17:35', endHHmm: '18:35');
      expect(g.workTime, '17:35–18:35');
      expect(_examples(g, '일찍 출근'), ['17:05 출근 → 인정 시작 17:35', '17:04 출근 → 인정 시작 17:05']);
      expect(_examples(g, '지각'), ['17:40 출근 → 인정 시작 17:35', '17:41 출근 → 인정 시작 18:05']);
      expect(_examples(g, '늦게 퇴근'), ['19:05 퇴근 → 인정 종료 18:35', '19:06 퇴근 → 인정 종료 19:05']);
      expect(_examples(g, '조퇴'), ['18:34 퇴근 → 인정 종료 18:05']);
    });

    test('ARG-6 다른 근무 시각이면 사례도 다르다(17:35 값을 복사하지 않음)', () {
      final g = attendanceRuleGuide(r, startHHmm: '09:00', endHHmm: '18:00');
      expect(_examples(g, '지각'), ['09:05 출근 → 인정 시작 09:00', '09:06 출근 → 인정 시작 09:30']);
      expect(_examples(g, '조퇴'), ['17:59 퇴근 → 인정 종료 17:30']);
    });

    test('ARG-7 자정을 넘는 근무 — 종료는 다음 날', () {
      final g = attendanceRuleGuide(r, startHHmm: '22:00', endHHmm: '06:00');
      expect(g.workTime, '22:00–다음 날 06:00');
      expect(_examples(g, '조퇴'), ['05:59 퇴근 → 인정 종료 05:30']);
      expect(_examples(g, '지각'), ['22:05 출근 → 인정 시작 22:00', '22:06 출근 → 인정 시작 22:30']);
    });

    test('ARG-8 유예 0·창 0·10분 단위 — 문구가 0분을 말하지 않고, 사례는 계산을 따른다', () {
      const z = AttendanceRules(earlyWindow: 0, lateGrace: 0, lateWindow: 0, lateUnit: 10, earlyLeaveUnit: 10, earlyArrivalUnit: 10);
      final g = attendanceRuleGuide(z, startHHmm: '09:00', endHHmm: '18:00');
      final all = g.sections.expand((s) => s.items).expand((i) => i.points).join(' ');
      expect(RegExp(r'(^|[^0-9])0분').hasMatch(all), isFalse, reason: "'0분 전까지' 같은 말을 하지 않는다");
      expect(_points(g, '지각').single, '시작보다 늦으면 늦은 시간을 10분 단위로 올려 인정 시작을 늦춰요.');
      expect(_examples(g, '지각'), ['09:01 출근 → 인정 시작 09:10']);
      expect(_examples(g, '조퇴'), ['17:59 퇴근 → 인정 종료 17:50']);
      expect(_examples(g, '일찍 출근'), ['08:59 출근 → 인정 시작 09:00']);
    });

    test('ARG-9 시각을 모르면 사례 없이 설명만(짐작하지 않음) · 표시용 줄바꿈 문자 없음', () {
      final g = attendanceRuleGuide(r);
      expect(g.workTime, isNull);
      expect(g.hasExamples, isFalse);
      expect(_points(g, '지각'), isNotEmpty);
      final text = g.sections.expand((s) => s.items).expand((i) => [...i.points, i.title]).join();
      expect(RegExp('[\u2060\u200B\u00A0]').hasMatch(text), isFalse, reason: '생성 데이터는 원문 — 표시 위젯만 줄바꿈 문자를 넣는다');
      expect(attendanceRuleGuide(r, startHHmm: '25:00', endHHmm: '18:00').hasExamples, isFalse);
    });
  });
}
