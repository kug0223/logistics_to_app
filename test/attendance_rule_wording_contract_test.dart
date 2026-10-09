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
import 'package:ALfit/utils/attendance_policy_disclosure.dart';
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

    test('16 근로자 고지의 **경계 문구**는 그대로다 — 설정 화면과 같은 말을 쓴다', () {
      // [R7-PREDEVICE-STABILIZATION.1] 이 테스트는 원래 "근로자 문구를
      //   전혀 바꾸지 않았다" 를 지켰다. 그 Phase 에서는 단위 설명의 방향을
      //   근로자에게 말하지 않기로 **미뤘기** 때문이다.
      //
      //   이번 Phase 가 그 미룬 항목을 처리했다(아래 RW-5). 그래서 지키는
      //   대상을 좁힌다 — **경계** 문구(이내/넘겨)는 설정 화면 문구와 쌍을
      //   이루므로 여전히 고정이고, **단위** 문구는 방향을 더해 바뀌었다.
      final d = _read('lib/utils/attendance_policy_disclosure.dart');
      expect(d.contains('시작 \${r.earlyWindow}분 전까지는 정시 처리'), isTrue);
      expect(d.contains('\${r.lateGrace}분까지는 정시 처리'), isTrue);
      expect(d.contains('종료 후 \${r.lateWindow}분까지는 정시 처리'), isTrue);
      // 경계 자체는 "이상" 이 아니라 "넘겨/넘기면" 이다.
      expect(d.contains('\${r.earlyWindow}분을 넘겨 도착하면'), isTrue);
      expect(d.contains('\${r.lateWindow}분을 넘기면'), isTrue);
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

  // ═══════════════════════════════════════════════════════════
  // [R7-PREDEVICE-STABILIZATION.1] 근로자가 **방향**을 안다
  //
  //   네 단위 항목은 모두 근로자에게 불리한 한 방향으로 끊는다. 그런데
  //   근로자가 보던 문장은 "N분 단위" 뿐이었다 — 중립 반올림으로 읽힌다.
  //   여기서는 문장이 **주장하는 것**을 실제 계산으로 검증한다. 문구만
  //   고정하면 계산이 바뀌어도 아무도 모른다.
  // ═══════════════════════════════════════════════════════════
  group('RW-5 근로자 고지가 방향을 말한다', () {
    /// 근로자가 실제로 보는 한 줄을 라벨로 찾는다.
    String line(AttendanceRules r, String label) {
      final hit = attendancePolicyLines(r).where((l) => l.label == label);
      expect(hit, isNotEmpty, reason: '"$label" 줄이 없다');
      return hit.first.value;
    }

    test('19 지각 — "올려서 차감" 이 실제 계산과 같다', () {
      // [R7-PREDEVICE-STABILIZATION.1A] `.1` 은 여기서 "1분 늦어도 30분" 을
      //   핀했다. 유예 5분이면 1분 지각은 **정시**이므로 거짓이었고, 이
      //   테스트는 계산을 `grace + 1` 로 확인하면서 문구는 "1분" 으로
      //   핀해 둘이 어긋난 것을 잡지 못했다. 이제 같은 수를 본다.
      final r = _rules(lateUnit: 30, lateGrace: 5);
      final v = line(r, '지각 처리');
      expect(v.contains('올려서 차감'), isTrue, reason: '방향을 말해야 한다: $v');
      // 유예 5분 + 단위 30분 → 첫 지각은 6분, 차감은 30분이다.
      expect(v.contains('6분 늦으면 30분'), isTrue, reason: v);
      expect(v.contains('1분 늦어도'), isFalse,
          reason: '유예를 무시한 거짓 사례가 돌아왔다: $v');
      // 그 약속이 사실인가.
      expect(_in(6, r).roundedAt, _start.add(const Duration(minutes: 30)),
          reason: '6분 지각은 30분 차감된다 — 문구와 같아야 한다');
      // 그리고 1분 지각은 정말로 차감이 없다.
      expect(_in(1, r).roundedAt, _start,
          reason: '유예 안이면 정시 처리다');
    });

    test('20 조퇴 — "올려서 차감" 이 실제 계산과 같다', () {
      final r = _rules(earlyLeaveUnit: 30);
      final v = line(r, '조퇴 처리');
      expect(v.contains('올려서 차감'), isTrue, reason: v);
      expect(v.contains('1분 일찍 가도 30분'), isTrue, reason: v);
      expect(_out(-1, r).roundedAt,
          _end.subtract(const Duration(minutes: 30)),
          reason: '1분 일찍 퇴근해도 30분 차감된다');
    });

    test('21 연장 — "남는 시간은 인정되지 않아요" 가 실제 계산과 같다', () {
      final r = _rules(lateWindow: 30, overtimeUnit: 30);
      final v = line(r, '연장 인정');
      expect(v.contains('남는 시간은 인정되지 않아요'), isTrue, reason: v);
      // 59분 더 일해도 30분만 인정된다 — 남는 29분이 사라진다.
      expect(_out(59, r).roundedAt, _end.add(const Duration(minutes: 30)),
          reason: '내림이므로 29분이 인정되지 않는다');
    });

    test('22 조출 — "남는 시간은 인정되지 않아요" 가 실제 계산과 같다', () {
      final r = _rules(earlyWindow: 30, earlyArrivalUnit: 30);
      final v = line(r, '조출 인정');
      expect(v.contains('남는 시간은 인정되지 않아요'), isTrue, reason: v);
      // 47분 일찍 와도 30분만 조출로 인정된다.
      expect(_in(-47, r).roundedAt,
          _start.subtract(const Duration(minutes: 30)),
          reason: '시작 쪽으로 끊으므로 17분이 인정되지 않는다');
    });

    test('23 네 줄 모두 방향을 말한다 — 중립 반올림으로 읽히지 않는다', () {
      final r = _rules();
      for (final label in const ['조출 인정', '지각 처리', '연장 인정', '조퇴 처리']) {
        final v = line(r, label);
        final saysDirection = v.contains('올려서 차감') ||
            v.contains('남는 시간은 인정되지 않아요');
        expect(saysDirection, isTrue,
            reason: '"$label" 이 방향 없이 "$v" 라고만 말한다');
      }
    });

    test('24 방향 문구가 7개 숫자 고지를 깨지 않았다', () {
      // 줄 수(7)와 "한 항목만 바꿔도 문장이 달라진다" 는 성질을 유지한다.
      const base = AttendanceRules();
      String render(AttendanceRules r) => attendancePolicyLines(r)
          .map((l) => '${l.label}=${l.value}')
          .join('|');
      expect(attendancePolicyLines(base).length, 7);
      final variants = <String, AttendanceRules>{
        'earlyWindow': base.copyWith(earlyWindow: 45),
        'earlyArrivalUnit': base.copyWith(earlyArrivalUnit: 15),
        'lateGrace': base.copyWith(lateGrace: 9),
        'lateUnit': base.copyWith(lateUnit: 15),
        'lateWindow': base.copyWith(lateWindow: 45),
        'overtimeUnit': base.copyWith(overtimeUnit: 25),
        'earlyLeaveUnit': base.copyWith(earlyLeaveUnit: 15),
      };
      final baseText = render(base);
      variants.forEach((k, v) {
        expect(render(v) == baseText, isFalse,
            reason: '$k 변경이 근로자 문장에 나타나지 않는다');
      });
      // 내부 필드 이름을 노출하지 않는다.
      for (final bad in ['earlyWindow', 'lateUnit', 'overtimeUnit']) {
        expect(baseText.contains(bad), isFalse);
      }
    });

    test('25 계약서·PDF·공고도 같은 문장을 쓴다 — 복제하지 않았다', () {
      // 방향 문구를 한 곳에서만 고쳤는데 어떤 화면이 자기 목록을 따로
      //   들고 있으면, 그 화면만 방향을 말하지 않는 상태로 남는다.
      for (final p in const [
        'lib/screens/contract/contract_pdf_builder.dart',
        'lib/screens/contract/contract_sign_screen.dart',
        'lib/screens/user/my_applications_screen.dart',
        'lib/screens/common/job_posting_screen.dart',
        'lib/widgets/dialogs/application_policy_acknowledge_sheet.dart',
        'lib/widgets/dialogs/apply/apply_confirm_dialog.dart',
      ]) {
        final s = _read(p);
        final usesShared = s.contains('attendancePolicyLines(') ||
            s.contains('attendancePolicyGroups(');
        expect(usesShared, isTrue, reason: '$p 가 공용 목록을 쓰지 않는다');
        // 자기 라벨 목록을 만들지 않는다.
        expect(s.contains("AttendancePolicyLine('"), isFalse,
            reason: '$p 가 고지 줄을 직접 만든다 — 방향이 갈린다');
      }
    });
  });
}
