// [R7-P4.4E.11C.0C.0a.1] "지원서는 다 정리했다"와 "업무 요청까지 다 정리했다"는
// 같은 사실이 아니었다
//
// .0a 의 Final residual gate 는 지원서 세 상태와 예정 근태만 셌다. 그런데
// 계정삭제 cleanup 의 책임에는 일정변경 요청과 지급방식 변경 요청 정리도
// 들어 있다. 그 둘이 남아 있는데 Final 이 그냥 지나가면, user 문서도 Auth 도
// 없는 계정에 **아직 실행 가능한** 요청이 매달린 채 남는다.
//
// 그리고 더 나쁜 것이 있었다.
//
//   cleanup 쿼리:  where("status", "==", "pending")   ← 소문자
//   생성 writer:   status: "PENDING"                  ← 대문자
//   승인 writer:   status !== "PENDING" 이면 거부      ← 대문자
//
// Firestore 쿼리는 대소문자를 구분한다. 즉 그 cleanup 은 **한 건도 취소하지
// 못했다** — 쿼리가 항상 공집합이었다. 그래서 "cleanup 이 돌았다"는 사실이
// "요청이 정리됐다"를 전혀 보장하지 않았다.
//
// 두 요청이 왜 inert 가 아닌가:
//
//   일정변경 승인은 트랜잭션에서 지원서를 읽지만 **존재만** 확인하고
//   `status` 를 보지 않는다. 그래서 지원서가 CANCELED 여도 승인되어
//   `leaveDates`/`extraWorkDates` 를 바꾼다.
//
//   지급방식 승인은 트랜잭션에서 요청 문서만 fresh-read 한다. 지원서 상태도
//   `accountStatus` 도 보지 않는다. 그리고 APPROVED 결과는 지급일 계산의
//   source 다 — 돈이다.
//
// 그래서 residual gate 에 둘을 넣고, freeze 이후 **새 요청 생성**도 막는다.
// residual 로 0 을 확인해도 그 직후 새 요청이 생기면 race 가 다시 열린다.
//
// 이 파일이 고정하는 것
//   DEL-REQ-0x   일정변경 residual
//   DEL-REQ-1x   지급방식 residual
//   DEL-REQ-2x   freeze 이후 생성 차단
//   DEL-REQ-3x   cleanup predicate 정합성
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _src(String p) {
  final f = File(p);
  if (!f.existsSync()) throw StateError('소스를 찾지 못했다: $p');
  return f.readAsStringSync();
}

String _codeOf(String src) => src
    .split(RegExp(r'\r?\n'))
    .where((l) {
      final t = l.trimLeft();
      return !t.startsWith('//') && !t.startsWith('*') && !t.startsWith('/*');
    })
    .join('\n');

String _flat(String s) => s.replaceAll(RegExp(r'\s+'), ' ');

String _fn(String raw, String name) {
  final a = raw.indexOf('export const $name');
  if (a < 0) throw StateError('$name 을 찾지 못함');
  final rel = raw.substring(a).indexOf('\n);');
  if (rel < 0) throw StateError('$name 의 끝을 찾지 못함');
  return _codeOf(raw.substring(a, a + rel));
}

String _helper(String raw, String sig) {
  final a = raw.indexOf(sig);
  if (a < 0) throw StateError('$sig 를 찾지 못함');
  final rel = raw.substring(a).indexOf('\n}');
  return _codeOf(raw.substring(a, a + rel));
}

const _cfPath = 'functions/src/index.ts';

void main() {
  final raw = _src(_cfPath);
  final cf = _codeOf(raw);
  final rules = _src('firestore.rules');

  String residual() =>
      _helper(raw, 'async function srvCountDeletionDomainResidual(');
  String cleanup() => _fn(raw, 'callableDeleteAccountApplications');
  String fin() => _fn(raw, 'callableDeleteAccountFinal');
  String schedApprove() => _fn(raw, 'callableApproveScheduleChangeRequest');
  String payApprove() => _fn(raw, 'callableApprovePaymentChangeRequest');
  String schedCreate() => _fn(raw, 'callableCreateScheduleChangeRequest');

  // ══════════════════════════════════════════════════════════════
  group('DEL-REQ-0x 일정변경 요청 residual (§1~§6·§17)', () {
    test('DEL-REQ-01 actionable 일정변경 요청이 Final 을 막는다', () {
      final r = _flat(residual());
      expect(r, contains(
          'db.collection("schedule_change_requests") '
          '.where("applicantUid", "==", uid).where("status", "==", "PENDING").get(),'));
      expect(r, contains('out.scheduleRequests = schedReq.size;'));
      expect(_flat(cf), contains(
          'r.scheduleRequests === 0 && r.paymentRequests === 0;'));
    });

    test('DEL-REQ-02 과거 기록은 막지 않는다 (§6·§12·§19)', () {
      final r = residual();
      // PENDING 만 센다 — APPROVED·REJECTED·CANCELED 는 세지 않는다.
      expect(r, isNot(contains('"APPROVED"')));
      expect(r, isNot(contains('"REJECTED"')));
      expect(r, isNot(contains('"CANCELED"')));
      // collection 전체 count 를 쓰지 않는다 (§12).
      expect(r, isNot(contains('.count()')));
      // [정정] residual 에는 지원서 PENDING 도 있으므로 3 이다.
      expect('where("status", "==", "PENDING")'.allMatches(r).length, 3,
          reason: 'applications + schedule + payment 각각 하나씩');
    });

    test('DEL-REQ-03 쿼리 실패는 Final 을 막는다 (§15)', () {
      expect(residual(), contains('out.queryFailed = true;'));
      expect(_flat(cf), contains('return !r.queryFailed &&'));
      // 실패를 0 으로 바꾸는 fallback 이 없다.
      expect(residual(), isNot(contains('out.scheduleRequests = 0;')));
      expect(residual(), isNot(contains('out.paymentRequests = 0;')));
    });

    test('DEL-REQ-04 왜 inert 가 아닌가 — 승인이 지원서 status 를 보지 않는다', () {
      final s = schedApprove();
      // 트랜잭션에서 지원서를 읽지만 존재만 확인한다.
      expect(s, contains('appSnap = await tx.get(appRef);'));
      expect(s, contains('"연결된 지원서를 찾을 수 없습니다. 스케줄 변경을 적용할 수 없습니다."'));
      // 지원서 status 를 보는 조건이 없다 — CANCELED 여도 통과한다.
      expect(s, isNot(contains('appSnap.data()!.status')));
      expect(s, isNot(contains('"CANCELED"')));
      // 그리고 canonical mutation 을 만든다.
      expect(_flat(s), contains('tx.update(requestRef, updateData);'));
    });

    test('DEL-REQ-05 승인의 canonical status 는 대문자 PENDING 이다', () {
      expect(schedApprove(), contains('!== "PENDING"'));
      expect(schedCreate(), contains('status: "PENDING",'));
      // rules 도 같은 값을 요구한다.
      expect(rules, contains("request.resource.data.status == 'PENDING' &&"));
    });
  });

  // ══════════════════════════════════════════════════════════════
  group('DEL-REQ-1x 지급방식 변경 요청 residual (§7~§10·§18)', () {
    test('DEL-REQ-10 actionable 지급방식 요청이 Final 을 막는다', () {
      final r = _flat(residual());
      expect(r, contains(
          'db.collection("payment_change_requests") '
          '.where("workerId", "==", uid).where("status", "==", "PENDING").get(),'));
      expect(r, contains('out.paymentRequests = payReq.size;'));
    });

    test('DEL-REQ-11 과거 기록은 막지 않는다', () {
      // 위 DEL-REQ-02 와 같은 술어를 공유한다 — PENDING 만.
      expect(_flat(residual()), contains(
          '.where("workerId", "==", uid).where("status", "==", "PENDING")'));
    });

    test('DEL-REQ-12 승인이 지원서·accountStatus 를 보지 않는다 (§9)', () {
      final p = payApprove();
      // 트랜잭션에서 요청 문서만 fresh-read 한다.
      expect(p, contains('const reqSnap = await tx.get(reqRef);'));
      expect(p, contains('if (reqData.status !== "PENDING") {'));
      expect(p, isNot(contains('accountStatus')));
      expect(p, isNot(contains('collection("applications")')));
      // 그리고 APPROVED 를 쓴다.
      expect(p, contains('status: "APPROVED",'));
    });

    test('DEL-REQ-13 APPROVED 가 지급일의 source 다 (§8)', () {
      // 단순 UI 요청이 아니라 돈 계산의 입력이다.
      expect(cf, contains('function srvResolveEffectivePaySchedule('));
      final rs = _helper(raw, 'function srvResolveEffectivePaySchedule(');
      expect(rs, contains('payment_change_requests'));
    });
  });

  // ══════════════════════════════════════════════════════════════
  group('DEL-REQ-2x freeze 이후 신규 생성 차단 (§32~§36)', () {
    test('DEL-REQ-20 freeze 후 새 일정변경 요청 생성 DENY', () {
      final h = _flat(rules.substring(
          rules.indexOf('function isValidSCRCreator(businessId) {'),
          rules.indexOf('}', rules.indexOf('function isValidSCRCreator(businessId) {'))));
      expect(h, contains("u.data.get('accountStatus', 'active') != 'deleting' &&"));
      // 이미 읽고 있는 같은 문서를 본다 — 추가 read 없음.
      expect(h, contains('let u = get(/databases/\$(database)/documents/users/\$(request.auth.uid));'));
      expect('get(/databases'.allMatches(h).length, 1,
          reason: 'create 평가에서 user 문서를 한 번만 읽는다');
      // 그 helper 가 실제로 create 규칙에 쓰인다.
      expect(rules, contains('isValidSCRCreator(request.resource.data.businessId) &&'));
    });

    test('DEL-REQ-21 freeze 후 새 지급방식 요청 생성 DENY', () {
      final pay = rules.substring(
          rules.indexOf('match /payment_change_requests/{reqId} {'),
          rules.indexOf('match /interim_settlement_requests/{reqId} {'));
      expect(pay, contains(
          "get(/databases/\$(database)/documents/users/\$(request.auth.uid))"
          ".data.get('accountStatus', 'active') != 'deleting' &&"));
      // self 분기에만 넣었다 — 관리자 분기는 .0b 소관(target 축).
      expect(pay, contains('request.resource.data.workerId == request.auth.uid &&'));
    });

    test('DEL-REQ-22 residual gate 와 create gate 가 한 세트다 (§36)', () {
      // residual 로 0 을 봐도 그 직후 생성되면 race 다. 둘 다 있어야 닫힌다.
      expect(_flat(residual()), contains('schedule_change_requests'));
      expect(_flat(residual()), contains('payment_change_requests'));
      expect(rules, contains("!= 'deleting' &&"));
    });

    test('DEL-REQ-23 다른 collection 의 create 규칙을 건드리지 않았다', () {
      // interim_settlement_requests 는 하드블록이 탈퇴 진입을 막으므로
      //   cleanup 대상이 아니다 — 이번에 gate 를 넣지 않았다.
      final interim = rules.substring(
          rules.indexOf('match /interim_settlement_requests/{reqId} {'));
      expect(interim.substring(0, 1200), isNot(contains("'deleting'")));
    });
  });

  // ══════════════════════════════════════════════════════════════
  group('DEL-REQ-3x cleanup predicate 정합성 (§2·§13·§30)', () {
    test('DEL-REQ-30 cleanup 의 status 대소문자가 고쳐졌다', () {
      final c = _flat(cleanup());
      // [정정] 원문이 `.where(...)` 를 줄바꿈으로 이어 쓰므로 flatten 후
      //   사이에 공백이 들어간다.
      expect(c, contains(
          '.where("applicantUid", "==", callerUid) .where("status", "==", "PENDING")'));
      expect(c, contains(
          '.where("workerId", "==", callerUid) .where("status", "==", "PENDING")'));
      // 소문자가 남아 있으면 cleanup 이 다시 공집합이 된다.
      expect(cleanup(), isNot(contains('"status", "==", "pending"')));
    });

    test('DEL-REQ-31 cleanup predicate == residual predicate (§13)', () {
      final c = _flat(cleanup());
      final r = _flat(residual());
      // field 와 status 가 양쪽에서 같다 — uid 변수명만 다르다.
      for (final pair in [
        ['applicantUid', 'schedule_change_requests'],
        ['workerId', 'payment_change_requests'],
      ]) {
        expect(c, contains('.where("${pair[0]}", "==", callerUid)'),
            reason: 'cleanup 의 ${pair[1]} key');
        expect(r, contains('.where("${pair[0]}", "==", uid)'),
            reason: 'residual 의 ${pair[1]} key');
      }
      // [정정] 양쪽 모두 지원서 PENDING 을 포함해 3 이다.
      expect('"status", "==", "PENDING"'.allMatches(c).length, 3);
      expect('"status", "==", "PENDING"'.allMatches(r).length, 3);
    });

    test('DEL-REQ-32 Final 로그가 두 축을 보고한다', () {
      expect(_flat(fin()), contains(
          'schedReq=\${domainResidual.scheduleRequests}'));
      expect(_flat(fin()), contains(
          'payReq=\${domainResidual.paymentRequests}'));
    });

    test('DEL-REQ-33 신규 인덱스가 필요 없다 — cleanup 과 같은 shape', () {
      // 같은 shape 가 이미 production 에서 돌고 있다는 것이 인덱스 증거다.
      expect(residual(), isNot(contains('"in"')));
      expect(residual(), isNot(contains('orderBy')));
      // indexes 파일을 건드리지 않았다.
      final idx = _src('firestore.indexes.json');
      expect(idx, isNot(contains('schedule_change_requests_deletion')));
    });

    test('DEL-REQ-34 cleanup 의 나머지 정책 ±0 (§30)', () {
      final c = cleanup();
      // [R7-P4.4E.11C.0C.0a.1] 소문자 "canceled" 였다 — 클라이언트 파서의
      //   default 가 PENDING 이라 정리된 요청이 UI 에 대기 중으로 보였다.
      expect(c, contains('status: "CANCELED",'));
      expect(c, isNot(contains('status: "canceled",')));
      expect(c, contains('cancelReason: "USER_DELETED"'));
      expect(c, contains('absentReason: "USER_DELETED"'));
      expect(c, contains('preservedCount:'));
    });
  });

  // ══════════════════════════════════════════════════════════════
  group('DEL-REQ-NC 건드리지 않은 것 (§28~§31)', () {
    test('DEL-REQ-NC-01 ConfirmApplication ±0 (§28)', () {
      final c = _fn(raw, 'callableConfirmApplication');
      expect(c, isNot(contains('ACCOUNT_STATUS_DELETING')));
      expect(c, contains('const confirmReviewGate = async (): Promise<void> => {'));
    });

    test('DEL-REQ-NC-02 freeze boundary ±0 (§29)', () {
      expect(cf, contains('const ACCOUNT_STATUS_DELETING = "deleting";'));
      expect(cf, contains('async function srvAssertAccountDeletionAllowed('));
      expect(_fn(raw, 'callableDeleteAccountPreData'),
          contains('await srvEnsureAccountDeletionTombstone(uid)'));
      expect(_flat(cf), contains(
          'tx.update(userRef, {accountStatus: ACCOUNT_STATUS_DELETING});'));
    });

    test('DEL-REQ-NC-03 storage.rules ±0 (§30)', () {
      final st = _src('storage.rules');
      expect(st, contains('function accountDeletionBarrierExists(uid)'));
      expect(st, contains('!accountDeletionBarrierExists(uid);'));
      expect(st, isNot(contains('deleting')));
    });

    test('DEL-REQ-NC-04 Auth-tail UI — owner Phase 가 닫았다', () {
      // [R7-P4.4E.11C.0C 갱신] "아직 없다"는 기록이었다. 이제 재개 경로가
      //   있고, signOut 은 tombstone 이 없을 때만 일어난다.
      final up = _src('lib/providers/user_provider.dart');
      expect(up, contains('await _authService.signOut(showToast: false);'));
      expect(up, contains('DeletionRecoveryState'));
      expect(_src('lib/main.dart'), contains('_DeletionRecoveryScreen'));
    });

    test('DEL-REQ-NC-05 승인 writer 자체를 고치지 않았다', () {
      // residual/create gate 로 닫았다 — 승인 로직은 .0b 와 별개로 그대로.
      expect(schedApprove(), isNot(contains('ACCOUNT_STATUS_DELETING')));
      expect(payApprove(), isNot(contains('ACCOUNT_STATUS_DELETING')));
    });
  });
}
