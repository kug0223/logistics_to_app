// [R6.4] 승인은 효력이어야 한다.
//
//   payment_change_requests 는 applicationId 단위로 지급일정 변경을 담고
//   관리자가 승인하면 APPROVED 가 됐다. 그런데 그 승인을 읽는 곳이
//   아무 데도 없었다 — 승인 버튼은 눌리는데 근로자에게 달라지는 것이
//   없었다.
//
//   원래 약속은 덮지 않는다. 승인된 요청이 그 위에 얹히는 수정이다.
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
  final res = _sliceOf(raw, 'async function srvResolveEffectivePaySchedule(',
      'function srvAssertUniqueWorkDetailIds(');
  final code = _codeOf(res);
  final f = _flat(code);

  group('PA-1 — 승인된 요청이 effect source 다', () {
    test('PA-10 resolver 가 요청 문서를 읽는다', () {
      expect(f, contains('collection("payment_change_requests")'));
      expect(f, contains('"applicationId", "==", applicationId'));
      expect(f, contains('r["requestedPayScheduleType"]'));
    });

    test('PA-11 APPROVED 만 효력이 있다', () {
      expect(f, contains('if (r["status"] !== "APPROVED") continue'));
    });

    test('PA-12 별도 effect collection 을 만들지 않았다', () {
      expect(f, isNot(contains('payment_schedule_amendments')));
      expect(f, isNot(contains('effective_pay_schedules')));
    });
  });

  group('PA-2 — effectiveFrom 을 지킨다', () {
    test('PA-20 효력 전이면 적용하지 않는다', () {
      expect(f, contains('if (ef > workDateKst) continue'));
    });

    test('PA-21 비교 기준은 근무일이다', () {
      expect(f, contains('workDateKst: string'));
      final wage = _sliceOf(raw, 'export const callableCalculateAndConfirmWage = onCall(',
          'function assertBizAdmin(');
      // [.6-P3] 그 근무일은 근태에서 파생한다 — 클라이언트 payload 가 아니다.
      expect(_flat(_codeOf(wage)), contains(
          'await srvResolveEffectivePaySchedule( promisedPaySchedule, wageAppId, canon.date)'));
      expect(_flat(_codeOf(wage)), contains('srvWorkDateParts(canonWorkTs)'));
    });

    test('PA-22 형식이 아닌 effectiveFrom 은 무시한다', () {
      expect(f, contains('!DATE_RE.test(ef)) continue'));
    });
  });

  group('PA-3 — 여러 승인 사이의 우선순위', () {
    test('PA-30 늦은 effectiveFrom 이 이기고, 같으면 나중 처리분이 이긴다', () {
      expect(f, contains('if (!best || ef > best.ef || (ef === best.ef && pAt > best.pAt))'));
    });

    test('PA-31 유효하지 않은 요청 내용은 건너뛴다', () {
      expect(f, contains('const ps = srvReadPaySchedule({'));
      expect(f, contains('if (!ps) continue'));
    });
  });

  group('PA-4 — 원래 약속은 보존된다', () {
    test('PA-40 resolver 는 Application/Contract 를 쓰지 않는다', () {
      expect(code, isNot(contains('collection("applications")')));
      expect(code, isNot(contains('collection("employment_contracts")')));
      expect(code, isNot(contains('tx.update')));
      expect(code, isNot(contains('.set(')));
    });

    test('PA-41 변경이 없으면 원래 약속을 그대로 돌려준다', () {
      expect(f, contains('const base: SrvEffectivePaySchedule = { ...promise,'));
      expect(f, contains('amended: false'));
      expect(f, contains('return base'));
    });

    test('PA-42 약속 resolver(R6.3)는 그대로 살아 있다', () {
      expect(raw, contains('async function srvResolvePromisedPaySchedule('));
      expect(_flat(raw), contains('if (fromApp) return mk(fromApp, "APPLICATION")'));
    });

    test('PA-43 변경 시 지급 시각을 지어내지 않는다', () {
      expect(f, contains('payScheduleTime: undefined'));
    });
  });

  group('PA-5 — 승인이 곧 효력이 되도록 검증한다', () {
    final ap = _sliceOf(raw, 'export const callableApprovePaymentChangeRequest = onCall(',
        'export const callableRejectPaymentChangeRequest');
    final af = _flat(_codeOf(ap));

    test('PA-50 대상 근무가 없으면 승인하지 않는다', () {
      expect(af, contains('typeof reqData.applicationId !== "string"'));
      expect(af, contains('대상 근무 정보가 없어 승인할 수 없습니다'));
    });

    test('PA-51 효력 시작일 형식을 검증한다', () {
      expect(af, contains('reqData.effectiveFrom'));
      expect(af, contains('효력 시작일이 올바르지 않아 승인할 수 없습니다'));
    });

    test('PA-52 요청 내용이 유효한 지급일정인지 검증한다', () {
      expect(af, contains('srvAssertPayScheduleValid([{'));
      expect(af, contains('payScheduleType: reqData.requestedPayScheduleType'));
      expect(af, contains('{require: true}'));
    });

    test('PA-53 domain rejection 이다', () {
      expect(af, contains('"failed-precondition"'));
      expect(af, isNot(contains('"internal"')));
    });

    test('PA-54 승인은 단일 write 다 — 반쪽 성공이 없다', () {
      // 요청 문서 자체가 effect source 이므로 tx 안의 write 는 그것 하나다
      expect('tx.update('.allMatches(_codeOf(ap)).length, 1);
    });
  });

  group('PA-6 — 기존 방어선 유지', () {
    test('PA-60 ConfirmFinalWage 는 frozen wageDetail 을 쓴다', () {
      final cf = _sliceOf(raw, 'export const callableConfirmFinalWage = onCall(',
          'export const callableCancelFinalConfirmation');
      final c = _flat(_codeOf(cf));
      expect(c, contains('const pvWd = (pvd.wageDetail ?? {}) as Record<string, unknown>'));
      expect(c, isNot(contains('payment_change_requests')));
    });

    test('PA-61 승인 permission 은 canManageWage 그대로다', () {
      final ap = _sliceOf(raw, 'export const callableApprovePaymentChangeRequest = onCall(',
          'export const callableRejectPaymentChangeRequest');
      expect(_flat(_codeOf(ap)), contains('memberPerms.canManageWage !== true'));
    });

    test('PA-62 REJECTED 경로는 손대지 않았다', () {
      final rj = _sliceOf(raw, 'export const callableRejectPaymentChangeRequest = onCall(',
          'export const callableGetInterimSettlements');
      expect(_flat(_codeOf(rj)), contains('status: "REJECTED"'));
      expect(_codeOf(rj), isNot(contains('srvResolveEffectivePaySchedule')));
    });
  });
}
