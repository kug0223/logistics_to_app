// [R6.2] 급여 지급 일정은 공고를 만들 때 검증한다.
//
//   실측: payScheduleType 에 서버 화이트리스트가 없어 임의 문자열이
//   공고 → 슬롯 → 계약서 스냅샷까지 그대로 들어갔고, 사람이 지원하고
//   계약하고 **실제로 일한 뒤** 급여 확정에서야 paymentDueDate 를
//   계산할 수 없다며 막혔다. 비용이 근무 이후에 발생하는 구조였다.
//
//   이 파일은 검증이 writer 쪽에 있고, 기존 downstream 방어가 그대로
//   남아 있다는 계약을 고정한다.
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

String _src() => File('functions/src/index.ts').readAsStringSync();
String _ui() => File(
    'lib/widgets/pickers/create_edit_work_detail_dialog.dart').readAsStringSync();

/// 주석으로 시작하는 줄만 제거한다 (JSDoc 은 남는다).
String _codeOf(String raw) => raw
    .split('\n')
    .where((l) => !l.trimLeft().startsWith('//'))
    .join('\n');

String _flat(String s) => s.replaceAll(RegExp(r'\s+'), ' ');

/// 그룹 수집 시점에도 불리므로 expect 대신 예외로 실패시킨다.
String _sliceOf(String raw, String from, String to) {
  final i = raw.indexOf(from);
  if (i < 0) throw StateError('시작 표지를 찾지 못함: $from');
  final j = raw.indexOf(to, i + from.length);
  if (j < 0) throw StateError('끝 표지를 찾지 못함: $to');
  return raw.substring(i, j);
}

void main() {
  final raw = _src();
  final validator = _sliceOf(raw, 'function srvAssertPayScheduleValid(',
      'function srvAssertUniqueWorkDetailIds(');
  final vFlat = _flat(_codeOf(validator));

  group('PS-1 — canonical enum 은 한 곳에서 온다', () {
    test('PS-10 서버 화이트리스트가 존재한다', () {
      expect(_flat(raw), contains(
          'const PAY_SCHEDULE_TYPES = ["same_day", "next_day", "weekly", "monthly"]'));
    });

    test('PS-11 지급일 계산기가 아는 값과 같다', () {
      final calc = _sliceOf(raw, 'function srvCalculatePaymentDueDate(',
          'export const callableConfirmFinalWage');
      final c = _flat(_codeOf(calc));
      for (final v in ['same_day', 'next_day', 'weekly', 'monthly']) {
        expect(c, contains('case "$v":'), reason: '$v 분기가 있어야 한다');
      }
      // 계산기가 모르는 값을 화이트리스트가 허용하면 안 된다
      expect(c, contains('default: return null'));
    });

    test('PS-12 UI 선택지와 같다 — 서버가 UI 보다 느슨하지 않다', () {
      final u = _flat(_ui());
      for (final v in ['same_day', 'next_day', 'weekly', 'monthly']) {
        expect(u, contains("('$v'"), reason: 'UI 에 $v 선택지가 있어야 한다');
      }
    });
  });

  group('PS-2 — 조합 규칙은 UI 와 같다', () {
    test('PS-20 weekly/monthly 는 지급일이 있어야 한다', () {
      expect(vFlat, contains('if (t === "weekly" || t === "monthly")'));
      expect(vFlat, contains('const maxDay = t === "weekly" ? 7 : 31'));
      expect(vFlat, contains('d < 1 || d > maxDay'));
    });

    test('PS-21 UI 도 같은 조건을 요구한다', () {
      final u = _flat(_ui());
      expect(u, contains(
          "(_payScheduleType == 'weekly' || _payScheduleType == 'monthly') && _payScheduleDay == null"));
    });

    test('PS-22 same_day/next_day 에는 지급일을 요구하지 않는다', () {
      // 조건이 weekly/monthly 로 한정돼 있음을 확인
      expect(vFlat, isNot(contains('t === "same_day" && d')));
      expect(vFlat, isNot(contains('t === "next_day" && d')));
    });
  });

  group('PS-3 — 없는 값을 지어내지 않는다', () {
    test('PS-30 누락 시 임의 기본값을 넣지 않는다', () {
      expect(vFlat, isNot(contains('= "same_day"')));
      expect(vFlat, isNot(contains('?? "same_day"')));
      expect(vFlat, isNot(contains('?? "next_day"')));
    });

    test('PS-31 신규 생성은 누락도 거절한다', () {
      expect(vFlat, contains('if (opts.require) {'));
      expect(vFlat, contains('급여 지급 일정을 선택해주세요'));
    });

    test('PS-32 레거시 수정 경로는 누락을 막지 않는다', () {
      expect(vFlat, contains('continue;'));
    });
  });

  group('PS-4 — writer 에서 강제한다 (클라이언트 dropdown 신뢰 금지)', () {
    test('PS-40 공고 생성 — 누락도 거절', () {
      final create = _sliceOf(raw, 'export const callableCreateTO = onCall(',
          'interface _ToMatchSlot');
      expect(_flat(_codeOf(create)),
          contains('srvAssertPayScheduleValid(toWorkDetailsCreate, {require: true})'));
    });

    test('PS-41 슬롯 생성 — 누락도 거절', () {
      final flex = _sliceOf(raw, 'export const callableCreateFlexSlots = onCall(',
          'export const callableGetAdminAttendances');
      expect(_flat(_codeOf(flex)),
          contains('srvAssertPayScheduleValid(workDetails, {require: true})'));
    });

    test('PS-42 공고 수정 — 값이 있으면 검증', () {
      final upd = _sliceOf(raw, 'export const callableUpdateTO = onCall(',
          'export const callableUpdateSlotWorkDetails = onCall(');
      expect(_flat(_codeOf(upd)),
          contains('srvAssertPayScheduleValid(updates.workDetails as unknown[], {require: false})'));
    });

    test('PS-43 슬롯 수정 — SINGLE·BATCH 양쪽', () {
      final su = _sliceOf(raw, 'export const callableUpdateSlotWorkDetails = onCall(',
          'const oldWDs =');
      final f = _flat(_codeOf(su));
      expect(f, contains('srvAssertPayScheduleValid(data.workDetails as unknown[], {require: false})'));
      expect(f, contains('for (const bu of data.batchUpdates!)'));
      expect(f, contains('srvAssertPayScheduleValid(bu.workDetails as unknown[], {require: false})'));
    });

    test('PS-44 임금 계산 CF — 클라이언트 payload 방어선', () {
      final wage = _sliceOf(raw, 'export const callableCalculateAndConfirmWage = onCall(',
          'function assertBizAdmin(');
      expect(_flat(_codeOf(wage)), contains(
          'srvAssertPayScheduleValid( [{payScheduleType: d.payScheduleType, payScheduleDay: d.payScheduleDay}], {require: false})'));
    });
  });

  group('PS-5 — downstream 방어는 그대로 남는다', () {
    test('PS-50 ConfirmFinalWage PREVALIDATE 유지', () {
      final cf = _sliceOf(raw, 'export const callableConfirmFinalWage = onCall(',
          'export const callableCancelFinalConfirmation');
      final f = _flat(_codeOf(cf));
      expect(f, contains('preValidErrors'));
      expect(f, contains('srvCalculatePaymentDueDate(pvPst, pvPsd, pvWorkDate) === null'));
      expect(f, contains('급여 지급일을 확인할 수 없습니다'));
    });

    test('PS-51 PREVALIDATE 는 confirmed write 0건을 보장한다', () {
      final cf = _sliceOf(raw, 'export const callableConfirmFinalWage = onCall(',
          'export const callableCancelFinalConfirmation');
      expect(_flat(_codeOf(cf)), contains('if (preValidErrors.length > 0)'));
      expect(_flat(_codeOf(cf)), contains('"failed-precondition"'));
    });
  });

  group('PS-6 — domain rejection 이다', () {
    test('PS-60 INTERNAL 이 아니다', () {
      expect(vFlat, contains('"invalid-argument"'));
      expect(vFlat, isNot(contains('"internal"')));
      expect(vFlat, isNot(contains('"unknown"')));
    });

    test('PS-61 사용자가 무엇을 해야 하는지 말한다', () {
      expect(vFlat, contains('당일·익일·주급·월급 중에서 선택해주세요'));
      expect(vFlat, contains('지급 요일(1~7)'));
      expect(vFlat, contains('지급 날짜(1~31)'));
    });
  });
}
