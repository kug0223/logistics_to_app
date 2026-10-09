// [R7-PAYROLL-DISCLOSURE.1] 설정 화면 문구가 **실제 계산**과 같은 말을 하는가.
//
// 관리자는 이 숫자들을 슬라이더로 고르고, 그 결과가 그대로 지급액이 된다.
// 설명이 실제 계산과 어긋나면 관리자는 자기가 고른 것이 무엇인지 모른 채
// 고르는 셈이다.
//
// 이 파일이 고정하는 것
//
//   RW-1  경계 — "이내 / 이상 / 넘겨" 가 코드의 비교 연산자와 같다
//   RW-2  방향 — "올림 / 내림" 이 실제 반올림 방향과 같다
//   RW-3  설정 화면 문구와 근로자 고지 문구가 같은 계산을 말한다
//   RW-4  미리보기는 canonical helper 로 만든다 (손으로 적은 예시 금지)

import 'dart:io';

import 'package:ALfit/models/core/business_model.dart';
import 'package:ALfit/utils/attendance_rounding_helper.dart';
import 'package:ALfit/utils/contract_period.dart';
import 'package:flutter_test/flutter_test.dart';

String _read(String p) {
  final f = File(p);
  if (!f.existsSync()) throw StateError('$p 를 찾지 못함');
  return f.readAsStringSync();
}

const _form = 'lib/screens/business_admin/business_form_screen.dart';

/// 09:00~18:00 하루. 날짜는 결과에 영향을 주지 않는다.
final _day = DateTime(2026, 1, 1);
DateTime get _start => contractStartAt(_day, '09:00');
DateTime get _end => contractEndAt(_day, '09:00', '18:00');

AttendanceRules _rules({
  int earlyWindow = 30,
  int earlyArrivalUnit = 30,
  int lateGrace = 5,
  int lateUnit = 30,
  int lateWindow = 30,
  int overtimeUnit = 10,
  int earlyLeaveUnit = 30,
}) =>
    AttendanceRules.defaults().copyWith(
      earlyWindow: earlyWindow,
      earlyArrivalUnit: earlyArrivalUnit,
      lateGrace: lateGrace,
      lateUnit: lateUnit,
      lateWindow: lateWindow,
      overtimeUnit: overtimeUnit,
      earlyLeaveUnit: earlyLeaveUnit,
    );

RoundingResult _in(int offset, AttendanceRules r) =>
    processCheckin(offsetMinutes: offset, referenceAt: _start, rules: r);
RoundingResult _out(int offset, AttendanceRules r) =>
    processCheckout(offsetMinutes: offset, referenceAt: _end, rules: r);

void main() {
  // ───────────────────────────────────────────────────────────
  group('RW-1 경계 — 이내 / 넘겨', () {
    test('01 earlyWindow 는 "이내" 가 정시, 그것을 **넘겨야** 조출이다', () {
      final r = _rules(earlyWindow: 30, earlyArrivalUnit: 30);
      // 정확히 30분 일찍 = 아직 조출이 아니다 (코드: offset < -earlyWindow)
      expect(_in(-30, r).type, RoundingType.onTime,
          reason: '30분 일찍은 경계 안이다 — "30분 이상 일찍" 이 아니다');
      expect(_in(-30, r).roundedOffset, 0);
      // 31분 일찍부터 조출
      expect(_in(-31, r).type, RoundingType.earlyArrival);
    });

    test('02 lateGrace 는 "이내" 가 정시다', () {
      final r = _rules(lateGrace: 5, lateUnit: 30);
      expect(_in(5, r).type, RoundingType.lateGrace,
          reason: '정확히 5분은 유예 안이다');
      expect(_in(5, r).roundedOffset, 0);
      expect(_in(6, r).type, RoundingType.late);
    });

    test('03 lateWindow 는 "이내" 가 정시 퇴근이다', () {
      final r = _rules(lateWindow: 30, overtimeUnit: 10);
      expect(_out(30, r).type, RoundingType.onTimeOut,
          reason: '정확히 30분 초과 체류는 경계 안이다');
      expect(_out(30, r).roundedOffset, 0);
      expect(_out(31, r).type, RoundingType.overtime);
    });
  });

  // ───────────────────────────────────────────────────────────
  group('RW-2 방향 — 올림 / 내림', () {
    test('04 지각은 올림 — 근로자에게 불리한 방향', () {
      final r = _rules(lateGrace: 5, lateUnit: 30);
      expect(_in(6, r).roundedOffset, 30, reason: '6분 지각 → 30분');
      expect(_in(30, r).roundedOffset, 30);
      expect(_in(31, r).roundedOffset, 60);
    });

    test('05 연장은 내림 — 근로자에게 불리한 방향', () {
      final r = _rules(lateWindow: 30, overtimeUnit: 10);
      expect(_out(45, r).roundedOffset, 40, reason: '45분 연장 → 40분');
      expect(_out(39, r).roundedOffset, 30);
    });

    test('06 조퇴는 **시간이 올림** 된다 — 설명의 "내림" 은 시각 기준이다', () {
      final r = _rules(earlyLeaveUnit: 30);
      // 10분 일찍 퇴근 → 30분 조퇴로 인정된다(조퇴 시간 올림).
      expect(_out(-10, r).roundedOffset, -30,
          reason: '조퇴 10분이 30분으로 늘어난다 — 조퇴 시간은 올림이다');
      expect(_out(-1, r).roundedOffset, -30);
      expect(_out(-31, r).roundedOffset, -60);
      // 인정 퇴근 **시각**은 그만큼 앞으로 당겨진다(=시각 기준 내림).
      expect(_out(-10, r).roundedAt, _end.subtract(const Duration(minutes: 30)));
    });

    test('07 조출은 **인정 시각이 올림** 된다 — 조출 시간은 줄어든다', () {
      final r = _rules(earlyWindow: 30, earlyArrivalUnit: 30);
      // 47분 일찍 도착 → 조출 30분만 인정(시각은 08:30 으로 올림).
      expect(_in(-47, r).roundedOffset, -30,
          reason: '조출 47분이 30분으로 줄어든다');
      expect(_in(-47, r).roundedAt, _start.subtract(const Duration(minutes: 30)));
      expect(_in(-61, r).roundedOffset, -60);
    });

    test('08 10분 단위와 30분 단위가 다른 결과를 낸다', () {
      // 관리자 A = 30분 / 관리자 B = 10분
      final a = _rules(lateGrace: 5, lateUnit: 30);
      final b = _rules(lateGrace: 5, lateUnit: 10);
      expect(_in(6, a).roundedOffset, 30);
      expect(_in(6, b).roundedOffset, 10);
      final a2 = _rules(lateWindow: 30, overtimeUnit: 30);
      final b2 = _rules(lateWindow: 30, overtimeUnit: 10);
      expect(_out(45, a2).roundedOffset, 30);
      expect(_out(45, b2).roundedOffset, 40);
    });
  });

  // ───────────────────────────────────────────────────────────
  group('RW-3 설정 화면 문구', () {
    late String form;
    setUpAll(() => form = _read(_form));

    test('09 경계 문구가 "이상" 이 아니다', () {
      // 정확히 earlyWindow 만큼 일찍 도착한 것은 조출이 **아니다**(위 01).
      // "N분 이상 일찍" 은 경계를 한 칸 틀리게 말한다.
      expect(form.contains('정시보다 N분 이상 일찍 도착하면 조출 처리'), isFalse,
          reason: '실제 코드는 초과(>)다 — "이상"(>=) 이 아니다');
      expect(form.contains('조출 인정 범위'), isTrue);
    });

    test('10 조퇴 문구가 조퇴 시간을 "내림" 이라고 말하지 않는다', () {
      // 조퇴 10분 → 30분(올림). "조퇴 시간을 내림" 은 반대로 읽힌다.
      expect(form.contains('조퇴 시간을 N분 단위로 내림 처리'), isFalse,
          reason: '조퇴 시간은 올림된다(위 06)');
    });

    test('11 소급 적용 여부를 말한다', () {
      // 관리자가 가장 먼저 묻는 질문이다. 실제로는 확정된 근무에
      // 소급되지 않는다(Application snapshot).
      expect(form.contains('이미 확정된 근무'), isTrue,
          reason: '기준을 바꿨을 때 기존 근무가 어떻게 되는지 말해야 한다');
    });

    test('12 ALfit 이 법적 적합성을 인증한다고 말하지 않는다', () {
      for (final bad in <String>[
        '법적으로 적합', '적법성을 확인', '법적 검토 완료', 'ALfit이 보증',
        '어떠한 책임도', '일체의 책임',
      ]) {
        expect(form.contains(bad), isFalse, reason: bad);
      }
      // 책임 주체는 사업장이라고만 말한다.
      expect(form.contains('사업장은 근로계약·취업규칙 및 관련 법령에 맞는 기준을 설정해야 합니다'),
          isTrue);
    });
  });

  // ───────────────────────────────────────────────────────────
  group('RW-4 미리보기는 canonical helper 로 만든다', () {
    test('13 설정 화면이 공용 미리보기 함수를 쓴다', () {
      final form = _read(_form);
      expect(form.contains('attendancePolicyPreviewLines('), isTrue,
          reason: '화면이 미리보기 줄을 직접 만들면 실행으로 확인할 수 없다');
      // 화면 안에서 다시 계산하거나 예시를 손으로 적지 않는다.
      expect(form.contains('processCheckin('), isFalse);
      expect(form.contains('processCheckout('), isFalse);
      expect(RegExp(r"'09:[0-9][0-9] 출근 →").hasMatch(form), isFalse,
          reason: '미리보기 결과를 문자열로 박아 두면 알고리즘과 갈라진다');
    });

    test('17 미리보기 줄이 helper 결과를 그대로 쓴다 — 30분 / 10분', () {
      // 변이 D4 가 노린 자리다. 줄 하나라도 손으로 적으면 여기서 깨진다.
      for (final r in [
        _rules(),                                        // 30분 단위
        _rules(lateUnit: 10, overtimeUnit: 10, earlyLeaveUnit: 10),
      ]) {
        final lines =
            attendancePolicyPreviewLines(r, start: _start, end: _end);
        expect(lines, hasLength(4));
        String hhmm(DateTime t) =>
            '${t.hour.toString().padLeft(2, '0')}:'
            '${t.minute.toString().padLeft(2, '0')}';
        final g = r.lateGrace;
        final w = r.lateWindow;
        expect(lines[0],
            '${hhmm(_start.add(Duration(minutes: g)))} 출근 → '
            '${hhmm(_in(g, r).roundedAt)} 부터 인정');
        expect(lines[1],
            '${hhmm(_start.add(Duration(minutes: g + 1)))} 출근 → '
            '${hhmm(_in(g + 1, r).roundedAt)} 부터 인정');
        expect(lines[2],
            '${hhmm(_end.add(Duration(minutes: w + 1)))} 퇴근 → '
            '${hhmm(_out(w + 1, r).roundedAt)} 까지 인정');
        expect(lines[3],
            '${hhmm(_end.subtract(const Duration(minutes: 1)))} 퇴근 → '
            '${hhmm(_out(-1, r).roundedAt)} 까지 인정');
      }
    });

    test('18 단위를 바꾸면 미리보기도 바뀐다', () {
      final a = attendancePolicyPreviewLines(
          _rules(lateUnit: 30), start: _start, end: _end);
      final b = attendancePolicyPreviewLines(
          _rules(lateUnit: 10), start: _start, end: _end);
      expect(a[1], isNot(b[1]),
          reason: '지각 단위를 바꿨는데 미리보기가 같으면 설정이 반영되지 않는다');
      expect(a[1].contains('09:30'), isTrue);
      expect(b[1].contains('09:10'), isTrue);
    });

    test('15 설명이 긴 문구에서 잘리지 않는다 — 자연 줄바꿈', () {
      // 설명을 고치면서 길어졌다. 좁은 화면에서 자리가 없으면 **세로로**
      //   늘어나야 한다 — maxLines·ellipsis·FittedBox 로 깎지 않는다.
      final form = _read(_form);
      final i = form.indexOf('Widget _buildRuleSlider(');
      expect(i, greaterThan(-1));
      // `\n  }` 로 끊으면 파라미터 목록을 닫는 `\n  }) {` 에 먼저 걸린다.
      final body = form.substring(i, form.indexOf('\n  }\n', i));
      expect(body.contains('Expanded('), isTrue,
          reason: '라벨·설명이 Expanded 안에 있어야 값 칩과 나란히 줄어든다');
      for (final clamp in <String>[
        'maxLines:', 'TextOverflow.ellipsis', 'FittedBox', 'Transform.scale',
      ]) {
        expect(body.contains(clamp), isFalse,
            reason: '설명을 $clamp 로 깎으면 관리자가 계산 의미를 못 읽는다');
      }
      // 섹션 안내도 같은 규칙.
      final note = form.indexOf('기준을 바꾸면 이후의 새 지원·초대부터 적용되고');
      expect(note, greaterThan(-1));
      final around = form.substring(note - 400, note + 300);
      expect(around.contains('maxLines'), isFalse);
    });

    test('16 근로자 고지 문구는 바꾸지 않았다 — 계약서가 같은 글을 쓴다', () {
      // 공용 formatter 는 계약서·PDF 와 공유된다. 이번 Phase 에서 건드리면
      //   이미 서명된 계약과 새 계약이 같은 숫자를 다른 말로 적게 된다.
      final d = _read('lib/utils/attendance_policy_disclosure.dart');
      expect(d.contains('시작 \${r.earlyWindow}분 전까지는 정시 처리'), isTrue);
      expect(d.contains('\${r.earlyWindow}분을 넘겨 도착하면 \${r.earlyArrivalUnit}분 단위'),
          isTrue);
      expect(d.contains('\${r.lateGrace}분까지는 정시 처리'), isTrue);
      expect(d.contains('종료 후 \${r.lateWindow}분까지는 정시 처리'), isTrue);
    });

    test('14 미리보기 네 줄이 실제 계산과 같은 값이다', () {
      // 화면이 만드는 네 줄과 같은 입력으로 helper 를 돌려 비교한다.
      final r = _rules();
      final grace = r.lateGrace;
      final window = r.lateWindow;
      expect(_in(grace, r).roundedAt, _start,
          reason: '유예 경계는 정시로 인정된다');
      expect(_in(grace + 1, r).roundedAt,
          _start.add(Duration(minutes: r.lateUnit)));
      expect(_out(window + 1, r).roundedAt,
          _end.add(Duration(minutes: ((window + 1) ~/ r.overtimeUnit) * r.overtimeUnit)));
      expect(_out(-1, r).roundedAt,
          _end.subtract(Duration(minutes: r.earlyLeaveUnit)));
    });
  });
}
