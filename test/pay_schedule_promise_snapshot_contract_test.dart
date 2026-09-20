// [R6.3] 수락한 지급일정은 이후 공고 수정으로 바뀌지 않는다.
//
//   공고의 현재 조건은 앞으로 뽑을 사람에 대한 사실이고, 이미 수락한
//   사람의 지급일정은 그때 고정된 사실이다. 그런데 급여 계산이 매번
//   현재 슬롯 workDetail 을 다시 읽었다 — 확정된 근로자가 있는 공고에서
//   당일→주급으로 바꾸면 이미 일한 사람의 지급일까지 따라 바뀌었다.
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

String _src() => File('functions/src/index.ts').readAsStringSync();

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

  group('PP-1 — Application 약속에 지급일정이 들어간다', () {
    final snap = _sliceOf(raw, 'export function buildCompensationSnapshot(',
        'function srvLoadMinimumWage');
    final f = _flat(_codeOf(snap));

    test('PP-10 스냅샷 빌더가 지급일정을 얼린다', () {
      expect(f, contains('const ps = srvReadPaySchedule(wd)'));
      expect(f, contains('out.payScheduleType = ps.t'));
      expect(f, contains('out.payScheduleDay = ps.d'));
      expect(f, contains('out.payScheduleTime = ps.tm'));
    });

    test('PP-11 유효하지 않은 값은 약속에 들어가지 않는다', () {
      final rd = _sliceOf(raw, 'function srvReadPaySchedule(',
          'async function srvResolvePromisedPaySchedule(');
      expect(_flat(_codeOf(rd)),
          contains('!PAY_SCHEDULE_TYPES.includes(t)) return null'));
    });

    test('PP-12 네 writer 가 모두 같은 스냅샷 빌더를 쓴다', () {
      // 지원 · 초대 · 대체근무 제안 · 확정 재배치
      expect(raw, contains('buildCompensationSnapshot(promisedWD)'));
      expect(raw, contains('buildCompensationSnapshot(inviteMatchedWD)'));
      expect(raw, contains('buildCompensationSnapshot(targetWD)'));
      expect(raw, contains('buildCompensationSnapshot(crTargetWD)'));
    });
  });

  group('PP-2 — 약속 우선순위', () {
    final res = _sliceOf(raw, 'async function srvResolvePromisedPaySchedule(',
        'function srvAssertUniqueWorkDetailIds(');
    final code = _codeOf(res);
    final f = _flat(code);

    test('PP-20 Application 이 1순위다', () {
      expect(f, contains('const fromApp = srvReadPaySchedule( appData'));
      expect(f, contains('if (fromApp) return mk(fromApp, "APPLICATION")'));
    });

    test('PP-21 Contract 스냅샷이 2순위다 (레거시)', () {
      expect(f, contains('collection("employment_contracts")'));
      expect(f, contains('"applicationId", "==", applicationId'));
      expect(f, contains('return mk(fromCon, "CONTRACT")'));
    });

    test('PP-22 클라이언트 값은 마지막이다', () {
      final appAt = code.indexOf('"APPLICATION"');
      final conAt = code.indexOf('"CONTRACT"');
      final cliAt = code.indexOf('mk(fromClient, "CLIENT")');
      expect(appAt, lessThan(conAt));
      expect(conAt, lessThan(cliAt));
    });

    test('PP-23 아무 근거도 없으면 현재 공고로 덮지 않고 NONE 이다', () {
      expect(f, contains('source: "NONE"'));
      expect(code, isNot(contains('collection("tos")')));
      expect(code, isNot(contains('"slots"')));
    });
  });

  group('PP-3 — 임금 계산이 약속을 쓴다', () {
    final wage = _sliceOf(raw, 'export const callableCalculateAndConfirmWage = onCall(',
        'function assertBizAdmin(');
    final f = _flat(_codeOf(wage));

    test('PP-30 약속 resolver 를 호출한다', () {
      expect(f, contains('await srvResolvePromisedPaySchedule( wagePromiseApp, wageAppId'));
    });

    // [R6.4 갱신] 약속 위에 승인된 변경(amendment)이 얹힌 **실효값**을 쓴다.
    //   약속이 직접 쓰이던 자리를 effectivePaySchedule 이 이어받았고,
    //   승인된 변경이 없으면 그 값은 곧 약속이다(srvResolveEffectivePaySchedule).
    //   변하지 않은 계약: 클라이언트 payload 는 여전히 쓰이지 않는다.
    test('PP-31 wageDetail 에 실효값을 쓴다 — 클라이언트 payload 아님', () {
      expect(f, contains('wd.payScheduleType = effectivePaySchedule.payScheduleType'));
      expect(f, contains('wd.payScheduleDay = effectivePaySchedule.payScheduleDay'));
      expect(f, isNot(contains('wd.payScheduleType = d.payScheduleType')));
      expect(f, isNot(contains('wd.payScheduleDay = d.payScheduleDay')));
      // 실효값의 출발점은 약속이다
      expect(f, contains(
          'await srvResolveEffectivePaySchedule( promisedPaySchedule, wageAppId, d.workDate)'));
    });

    test('PP-32 약속이 없으면 그 사실을 로그로 남긴다', () {
      expect(f, contains('지급일정 약속 스냅샷 없음'));
    });
  });

  group('PP-4 — 계약서가 현재 공고를 다시 읽지 않는다', () {
    final sign = _sliceOf(raw, 'export const callableFinalizeEmployerSignature = onCall(',
        'export const callableVoidContract');
    final f = _flat(_codeOf(sign));

    test('PP-40 계약 스냅샷의 지급일정을 지원서 약속으로 덮는다', () {
      expect(f, contains('const ps = srvReadPaySchedule(appData as Record<string, unknown>)'));
      expect(f, contains('sn["payScheduleType"] = ps.t'));
      expect(f, contains('sn["payScheduleDay"] = ps.d ?? null'));
      expect(f, contains('sn["payScheduleTime"] = ps.tm ?? null'));
    });
  });

  group('PP-5 — 관리자 급여내역 수정도 약속을 못 바꾼다', () {
    final upd = _sliceOf(raw, 'export const callableUpdateWageDetail',
        'export const callableIncrementSlotPending');
    final f = _flat(_codeOf(upd));

    test('PP-50 약속을 해상도한다', () {
      expect(f, contains('const updWagePaySchedule = await srvResolvePromisedPaySchedule('));
    });

    test('PP-51 허용목록 통과 후 약속값으로 덮는다', () {
      expect(f, contains(
          'safeWageDetailMap["payScheduleType"] = updWagePaySchedule.payScheduleType'));
    });
  });

  group('PP-6 — 기존 방어선은 그대로다', () {
    test('PP-60 공고 writer 검증(R6.2) 유지', () {
      expect(_flat(raw),
          contains('srvAssertPayScheduleValid(toWorkDetailsCreate, {require: true})'));
      expect(_flat(raw),
          contains('srvAssertPayScheduleValid(workDetails, {require: true})'));
    });

    test('PP-61 ConfirmFinalWage PREVALIDATE 유지 — wageDetail 에서 읽는다', () {
      final cf = _sliceOf(raw, 'export const callableConfirmFinalWage = onCall(',
          'export const callableCancelFinalConfirmation');
      final f = _flat(_codeOf(cf));
      expect(f, contains('const pvWd = (pvd.wageDetail ?? {}) as Record<string, unknown>'));
      expect(f, contains('srvCalculatePaymentDueDate(pvPst, pvPsd, pvWorkDate) === null'));
      // 공고를 읽지 않는다
      expect(f, isNot(contains('collection("slots")')));
    });

    test('PP-62 paymentDueDate 는 frozen wageDetail 에서 계산된다', () {
      final cf = _sliceOf(raw, 'export const callableConfirmFinalWage = onCall(',
          'export const callableCancelFinalConfirmation');
      final f = _flat(_codeOf(cf));
      expect(f, contains('const payScheduleType = existingWd.payScheduleType as string | undefined'));
      expect(f, contains('srvCalculatePaymentDueDate(payScheduleType, payScheduleDay, workDate)'));
    });
  });
}
