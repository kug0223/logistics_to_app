// [R7-P4.4E.11C.0C.0a] 치우는 동안에도 상태가 계속 자라고 있었다
//
// .0B 는 계정 소유 Storage 에 write barrier 를 세웠다. 그런데 barrier 가
// **Final 안**에서 만들어졌고, 클라이언트의 실제 순서는
//
//   PreData → Applications cleanup → Final
//
// 이다. 그래서 Applications cleanup 이 끝난 뒤 Final 에 들어가기까지 창이
// 열려 있었다 — 그 사이 다른 기기가 새 지원·초대수락·확정을 만들면
// cleanup 은 이미 지나갔고 Final 은 그것을 보지 않는다. 결과는 user 문서도
// Auth 도 없는 계정에 매달린 확정 근무 약속이다.
//
// 두 가지를 바꾼다.
//
//   ① freeze 를 cleanup **앞**으로 옮긴다. tombstone(canonical)과
//      users/{uid}.accountStatus = "deleting"(live-user projection)을 한
//      트랜잭션에서 맞춘다. freeze 가 commit 된 뒤에는 새 사실이 자라지
//      않으므로, cleanup 은 더 이상 커지지 않는 유한한 집합을 정리한다.
//
//   ② Final 이 cleanup 성공을 **클라이언트에게 묻지 않는다.** 서버가 직접
//      살아 있는 삭제 대상 관계를 세고, 0 이 아니면 identity 를 파괴하지
//      않는다. Applications 는 실패 수를 반환하지 않고 클라이언트는 그
//      응답을 읽지도 않았으므로, 믿을 근거가 애초에 없었다.
//
// projection 값으로 "deleting" 을 고른 이유: 이미 많은 commitment writer 가
// `accountStatus !== "active"` 를 보고 거부한다(Apply·AcceptInvitation·
// InviteWorker·OfferAlternativeWork·ProposeConfirmedReassignment·CheckIn).
// 새 gate 를 여러 함수에 심는 대신 그 gate 를 재사용한다.
//
// 이 파일이 고정하는 것
//   DEL-FREEZE-Axx   freeze atomicity · 멱등 · 수렴
//   DEL-FREEZE-A1x   순서 (freeze < cleanup < identity 파괴)
//   DEL-FREEZE-A2x   PreData/Applications hard-stop
//   DEL-CLEAN-A4x    Final residual gate
//   DEL-STATUS-RULE  accountStatus 권위
//   DEL-FREEZE-NC    건드리지 않은 것
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

/// top-level `);` 까지 — 함수 본문만 자른다.
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
  if (rel < 0) throw StateError('$sig 의 끝을 찾지 못함');
  return _codeOf(raw.substring(a, a + rel));
}

const _cfPath = 'functions/src/index.ts';

void main() {
  final raw = _src(_cfPath);
  final cf = _codeOf(raw);
  final rules = _src('firestore.rules');
  final client = _codeOf(_src('lib/services/auth_service.dart'));

  String preData() => _fn(raw, 'callableDeleteAccountPreData');
  String apps() => _fn(raw, 'callableDeleteAccountApplications');
  String fin() => _fn(raw, 'callableDeleteAccountFinal');
  String freeze() =>
      _helper(raw, 'async function srvEnsureAccountDeletionTombstone(');
  String precond() =>
      _helper(raw, 'async function srvAssertAccountDeletionAllowed(');
  String residual() =>
      _helper(raw, 'async function srvCountDeletionDomainResidual(');

  // ══════════════════════════════════════════════════════════════
  group('DEL-FREEZE-Ax freeze atomicity (§3·§6·§7·§8·§16)', () {
    test('DEL-FREEZE-A01 tombstone + deleting 을 한 트랜잭션에서 맞춘다', () {
      final f = _flat(freeze());
      expect(f, contains('db.runTransaction(async (tx) => {'));
      expect(f, contains('tx.get(tombRef), tx.get(userRef),'));
      expect(f, contains('tx.set(tombRef, {'));
      expect(f, contains('tx.update(userRef, {accountStatus: ACCOUNT_STATUS_DELETING});'));
      expect(cf, contains('const ACCOUNT_STATUS_DELETING = "deleting";'));
      // 쓰기가 트랜잭션 밖에 또 있으면 중간 상태가 관측된다.
      expect(freeze(), isNot(contains('await tombRef.set(')));
      expect(freeze(), isNot(contains('await userRef.update(')));
    });

    test('DEL-FREEZE-A02 재호출 멱등 — 이미 frozen 이면 no-op 성공', () {
      final f = _flat(freeze());
      expect(f, contains('if (!hadTomb) {'));
      expect(f, contains('if (userSnap.exists && status !== ACCOUNT_STATUS_DELETING) {'));
      expect(f, contains('return true;'));
    });

    test('DEL-FREEZE-A03 트랜잭션 실패 시 부분 commit 0', () {
      // 두 쓰기가 같은 트랜잭션 안이라 부분 commit 이 구조적으로 불가능하다.
      final f = freeze();
      final txAt = f.indexOf('db.runTransaction(async (tx) => {');
      expect(f.indexOf('tx.set(tombRef'), greaterThan(txAt));
      expect(f.indexOf('tx.update(userRef'), greaterThan(txAt));
      // 실패는 false 로 돌려주고 호출부가 판단한다 — 삼키지 않는다.
      expect(f, contains('return false;'));
      expect(f, contains('freeze failed'));
    });

    test('DEL-FREEZE-A04 tombstone 있고 active 면 deleting 으로 수렴', () {
      // tombstone 존재 여부와 projection 보정이 독립 분기다.
      final f = _flat(freeze());
      expect(f, contains('const hadTomb = tombSnap.exists;'));
      expect(f, contains('if (userSnap.exists && status !== ACCOUNT_STATUS_DELETING) {'));
    });

    test('DEL-FREEZE-A05 deleting 인데 tombstone 없으면 tombstone 생성', () {
      expect(_flat(freeze()), contains('if (!hadTomb) { tx.set(tombRef, {'));
    });

    test('DEL-FREEZE-A06 barrierAt 을 되돌리지 않는다 (§8)', () {
      final f = freeze();
      // 생성 분기 안에서만 barrierAt 을 쓴다.
      final createBlock = f.substring(
          f.indexOf('if (!hadTomb) {'), f.indexOf('// [§7]') < 0
              ? f.indexOf('let projected') : f.indexOf('let projected'));
      expect(createBlock, contains('barrierAt:'));
      expect('barrierAt:'.allMatches(f).length, 1,
          reason: 'barrierAt 쓰기가 한 곳뿐이어야 재시도에 보존된다');
      expect(f, isNot(contains('merge: true')));
    });

    test('DEL-FREEZE-A07 삭제·되돌리기 경로가 없다 (§7)', () {
      final f = freeze();
      expect(f, isNot(contains('tombRef.delete()')));
      expect(f, isNot(contains('"active"')));
      // user 문서가 없으면 projection 을 되살리지 않는다.
      expect(_flat(f), contains('if (userSnap.exists && status !=='));
    });

    test('DEL-FREEZE-A08 전역 deleting→active 전환 0 (§18)', () {
      // accountStatus 를 active 로 쓰는 CF 는 하나뿐이고 compare-and-set 이다.
      expect('accountStatus: "active"'.allMatches(cf).length, 1);
      expect(cf, contains(
          'if (freshStatus === "registration_pending" || freshStatus === "pending") {'));
      // 그 guard 가 deleting 을 배제한다 — 두 값 중 하나일 때만 active.
      expect(cf, isNot(contains('freshStatus !== "active"')));
    });
  });

  // ══════════════════════════════════════════════════════════════
  group('DEL-FREEZE-A1x 순서 (§0·§4·§9·§22)', () {
    test('DEL-FREEZE-A10 freeze 가 PreData destructive cleanup 보다 앞', () {
      final p = preData();
      final fAt = p.indexOf('await srvEnsureAccountDeletionTombstone(uid)');
      expect(fAt, greaterThan(-1), reason: 'PreData 가 freeze owner 가 아니다');
      for (final later in [
        'db.collection("deleted_accounts").add(recordDocData)',
        'nativeIdentityFingerprints',
        'paginateUpdate(',
        'paginateDelete(',
      ]) {
        expect(p.indexOf(later), greaterThan(fAt),
            reason: '$later 가 freeze 보다 앞이면 안 된다');
      }
    });

    test('DEL-FREEZE-A11 freeze 실패 시 PreData 가 즉시 throw', () {
      final p = _flat(preData());
      expect(p, contains(
          'const frozen = await srvEnsureAccountDeletionTombstone(uid); '
          'if (!frozen) { throw new HttpsError( "internal",'));
      // precondition 이 freeze 보다 앞이다 (§11 — 진입 못 할 사용자를 봉쇄하지 않는다)
      final pr = preData();
      expect(pr.indexOf('srvAssertAccountDeletionAllowed('),
          lessThan(pr.indexOf('srvEnsureAccountDeletionTombstone(')));
    });

    test('DEL-FREEZE-A12 Final: freeze → residual → sweep → user → Auth', () {
      final f = fin();
      final i1 = f.indexOf('srvEnsureAccountDeletionTombstone(uid)');
      final i2 = f.indexOf('srvCountDeletionDomainResidual(uid)');
      final i3 = f.indexOf('srvSweepAccountOwnedStorage(uid)');
      final i4 = f.indexOf('await userRef.delete()');
      final i5 = f.indexOf('admin.auth().deleteUser(uid)');
      expect(i1, greaterThan(-1));
      expect(i2, greaterThan(i1), reason: 'residual 검사가 freeze 뒤');
      expect(i3, greaterThan(i2), reason: 'Storage sweep 이 residual 뒤 (§22)');
      expect(i4, greaterThan(i3));
      expect(i5, greaterThan(i4));
    });

    test('DEL-FREEZE-A13 precondition 을 두 곳에 복제하지 않았다 (§5)', () {
      // 공용 helper 를 PreData·Final 둘이 쓴다.
      expect('srvAssertAccountDeletionAllowed('.allMatches(cf).length, 3,
          reason: '정의 1 + PreData 1 + Final 1');
      expect(preData(), contains('await srvAssertAccountDeletionAllowed('));
      expect(fin(), contains('await srvAssertAccountDeletionAllowed('));
      // Final 안에 옛 인라인 검사가 남아 있지 않다.
      expect(fin(), isNot(contains('const authTime =')));
      expect(fin(), isNot(contains('const subAdminBizIds =')));
      expect(fin(), isNot(contains('workerSignedAt')));
    });

    test('DEL-FREEZE-A14 precondition 이 user 문서에 의존하지 않는다 (§5·§13)', () {
      final c = _flat(precond());
      // auth_time·role 은 토큰 claim 에서 읽는다.
      expect(c, contains('token["auth_time"] as number | undefined'));
      expect(c, contains('const role = (token["role"] as string) || "";'));
      // subAdmin 은 optional chaining — 문서 없으면 빈 배열.
      expect(c, contains('(userDocForBlock.data()?.subAdminBusinessIds ?? []) as string[]'));
      // 문서 부재를 실패로 만들지 않는다.
      expect(precond(), isNot(contains('.exists')));
      expect(precond(), isNot(contains('not-found')));
    });
  });

  // ══════════════════════════════════════════════════════════════
  group('DEL-FREEZE-A2x 클라이언트 hard-stop (§10·§13·§103)', () {
    test('DEL-FREEZE-A20 PreData 실패 → 파이프라인 중단', () {
      final c = _flat(client);
      expect(c, contains('BEGIN(PreData) 실패'));
      expect(c, contains("return '탈퇴 처리를 시작할 수 없습니다. 잠시 후 다시 시도해 주세요.';"));
      // 예전의 code 별 분기와 best-effort 계속이 사라졌다.
      expect(client, isNot(contains("if (e.code == 'internal') rethrow;")));
      expect(client, isNot(contains('개인정보 사전정리 네트워크 오류 (계속 진행)')));
    });

    test('DEL-FREEZE-A21 Applications 실패 → Final 호출 0 (§13·§46)', () {
      final c = _flat(client);
      expect(c, contains('applications 정리 실패'));
      expect(c, contains("return '탈퇴 처리 중 정리 단계가 완료되지 않았습니다. 다시 시도해 주세요.';"));
      expect(client, isNot(contains(r'applications CF 오류 [${e.code}] (계속 진행)')));
      // 중단이 Final 호출보다 앞이다.
      final appAt = client.indexOf('applications 정리 실패');
      final finAt = client.indexOf('deleteFinalCallable');
      expect(appAt, greaterThan(-1));
      expect(finAt, greaterThan(appAt),
          reason: 'Applications 중단 분기가 Final 호출보다 뒤면 막지 못한다');
    });

    test('DEL-FREEZE-A22 Final 성공 확인 gate 는 그대로다 (.0B 계약)', () {
      expect(client, contains("if (finalData['success'] != true) {"));
      expect(client, contains('탈퇴가 완료되지 않았습니다. 데이터 정리를 마치려면 다시 시도해 주세요.'));
      expect(client, contains('await _auth.signOut();'));
    });

    test('DEL-FREEZE-A23 호출 순서가 PreData → Applications → Final 이다', () {
      final i1 = client.indexOf("httpsCallable('callableDeleteAccountPreData'");
      final i2 = client.indexOf("httpsCallable('callableDeleteAccountApplications'");
      final i3 = client.indexOf("httpsCallable('callableDeleteAccountFinal'");
      expect(i1, greaterThan(-1));
      expect(i2, greaterThan(i1));
      expect(i3, greaterThan(i2));
    });
  });

  // ══════════════════════════════════════════════════════════════
  group('DEL-CLEAN-A4x Final residual gate (§15~§23·§48)', () {
    test('DEL-CLEAN-A40 세 status + scheduled 근태를 센다', () {
      final r = _flat(residual());
      expect(r, contains('.where("uid", "==", uid).where("status", "==", "PENDING")'));
      expect(r, contains('.where("uid", "==", uid).where("status", "==", "CONTRACT_PENDING")'));
      expect(r, contains('.where("uid", "==", uid).where("status", "==", "CONFIRMED")'));
      expect(r, contains('.where("userId", "==", uid).where("status", "==", "scheduled")'));
    });

    test('DEL-CLEAN-A41 쿼리 shape 가 기존 cleanup 과 같다 — 신규 인덱스 불필요', () {
      // 같은 shape 를 Applications cleanup 이 이미 실행한다. `in` 으로 바꾸면
      //   인덱스 요구가 달라질 수 있어 equality 조합을 유지한다.
      final a = _flat(apps());
      for (final q in [
        '.where("uid", "==", callerUid).where("status", "==", "PENDING")',
        '.where("uid", "==", callerUid).where("status", "==", "CONTRACT_PENDING")',
        '.where("uid", "==", callerUid).where("status", "==", "CONFIRMED")',
        '.where("userId", "==", callerUid).where("status", "==", "scheduled")',
      ]) {
        expect(a, contains(q), reason: '기존 cleanup 의 shape 가 바뀌었다');
      }
      expect(residual(), isNot(contains('"in"')),
          reason: 'in 은 인덱스 요구가 달라질 수 있다');
    });

    test('DEL-CLEAN-A42 residual > 0 이면 identity 파괴 금지', () {
      final f = _flat(fin());
      expect(f, contains(
          'if (!srvDeletionDomainCleared(domainResidual)) { return { success: false, '
          'partial: true, reason: "DOMAIN_CLEANUP_INCOMPLETE", }; }'));
      final fr = fin();
      final gate = fr.indexOf('if (!srvDeletionDomainCleared(domainResidual)) {');
      for (final later in ['await userRef.delete()', 'admin.auth().deleteUser(uid)',
        'srvSweepAccountOwnedStorage(uid)', 'array-contains']) {
        expect(fr.indexOf(later), greaterThan(gate), reason: later);
      }
    });

    test('DEL-CLEAN-A43 쿼리 실패는 0 이 아니다 (§19)', () {
      final r = residual();
      expect(r, contains('out.queryFailed = true;'));
      // [R7-P4.4E.11C.0C.0a.1 갱신] 판정에 일정변경·지급방식 요청 두 축이
      //   더해졌다. `!queryFailed` 가 선두라는 성질은 그대로다.
      expect(_flat(cf), contains(
          'return !r.queryFailed && r.applications === 0 && r.attendance === 0 && '
          'r.scheduleRequests === 0 && r.paymentRequests === 0;'));
      // 실패를 0 으로 바꾸는 fallback 이 없다.
      expect(r, isNot(contains('out.applications = 0;')));
      expect(r, isNot(contains('catch { return')));
    });

    test('DEL-CLEAN-A44 residual 0 이면 기존 Final 이 계속된다', () {
      final f = fin();
      expect(f, contains('srvSweepAccountOwnedStorage(uid)'));
      expect(f, contains('srvAccountStorageCleared(accSweep)'));
      expect(f, contains('return {success: true};'));
    });

    test('DEL-CLEAN-A45 raw application id 를 응답에 담지 않는다 (§20)', () {
      final f = fin();
      expect(f, contains('reason: "DOMAIN_CLEANUP_INCOMPLETE"'));
      expect(f, isNot(contains('applicationIds')));
      expect(f, isNot(contains('residualIds')));
    });

    test('DEL-CLEAN-A50 Final 단독 호출도 안전하다 (§23·§24)', () {
      // 클라이언트가 Applications 를 건너뛰어도 Final 이 스스로 막는다.
      final f = fin();
      expect(f, contains('await srvEnsureAccountDeletionTombstone(uid)'));
      expect(f, contains('await srvCountDeletionDomainResidual(uid)'));
      // freeze writer 는 PreData 와 같은 helper 다 — drift 없음.
      expect('srvEnsureAccountDeletionTombstone('.allMatches(cf).length, 3,
          reason: '정의 1 + PreData 1 + Final 1');
    });
  });

  // ══════════════════════════════════════════════════════════════
  group('DEL-STATUS-RULE accountStatus 권위 (§20·§21·§26·§27)', () {
    test('DEL-STATUS-RULE-01·02 owner set/clear DENY', () {
      // self-update denylist 에 있다.
      expect(rules, contains("'name', 'legalName', 'koreanName',"));
      final selfBlock = rules.substring(
          rules.indexOf('allow update: if isLoggedIn() &&'),
          rules.indexOf('allow delete:',
              rules.indexOf('allow update: if isLoggedIn() &&')));
      expect(selfBlock, contains("'accountStatus'"));
    });

    test('DEL-STATUS-RULE-03·04 SUPER_ADMIN client set/clear DENY', () {
      final sa = rules.substring(
          rules.indexOf('allow update: if isSuperAdmin() &&'),
          rules.indexOf('allow update: if isLoggedIn() &&'));
      expect(sa, contains("'accountStatus',"),
          reason: '여기 없으면 슈퍼어드민이 deleting 을 해제할 수 있다');
    });

    test('DEL-STATUS-RULE-05 create 허용 집합에 deleting 을 넣지 않았다 (§27)', () {
      expect(rules, contains(
          "in ['active', 'pending', 'registration_pending'] &&"));
      // [R7-P4.4E.11C.0C.0a.1 갱신] 예전에는 rules 전체에 `'deleting'` 이
      //   없다는 것으로 확인했다. 이제 두 request create 규칙이 `deleting`
      //   을 **거부 조건으로** 참조한다 — 그건 허용이 아니라 차단이다.
      //   묻는 것은 그대로다: 클라이언트가 보낸 값으로 `deleting` 을
      //   **지정할 수 없다**(create 허용 집합에 없다).
      expect(rules, isNot(contains("'deleting', 'active'")));
      expect(rules, isNot(contains("'active', 'deleting'")));
      expect(rules, isNot(contains("'registration_pending', 'deleting'")));
      // 그리고 `deleting` 참조는 전부 `!=` 비교(차단)여야 한다.
      final refs = RegExp(r"'deleting'").allMatches(rules).length;
      final denies = RegExp(r"!= 'deleting'").allMatches(rules).length;
      expect(denies, refs,
          reason: 'deleting 참조 $refs 개 중 차단 비교가 $denies 개 — '
              '하나라도 허용 쪽이면 self-lock 이 가능해진다');
    });

    test('DEL-STATUS-RULE-06 UserModel 이 임의 문자열을 수용한다 (§28)', () {
      final m = _src('lib/models/core/user_model.dart');
      expect(m, contains("accountStatus: map['accountStatus'] ?? 'active',"));
      // enum/파서 검증이 없으므로 deleting 이 crash 를 만들지 않는다.
      expect(m, isNot(contains('AccountStatus.values')));
    });
  });

  // ══════════════════════════════════════════════════════════════
  group('DEL-FREEZE-NC 건드리지 않은 것 (§29~§31·§37~§39·§56)', () {
    test('DEL-FREEZE-NC-01 ConfirmApplication ±0 (§31 — .0b owner)', () {
      final c = _fn(raw, 'callableConfirmApplication');
      // 이번 Phase 에서 gate 를 넣지 않았다 — OPEN 으로 남긴다.
      expect(c, isNot(contains('ACCOUNT_STATUS_DELETING')));
      expect(c, isNot(contains('srvAssertAccountDeletionAllowed')));
      // 기존 readiness gate 는 그대로.
      expect(c, contains('const confirmReviewGate = async (): Promise<void> => {'));
    });

    test('DEL-FREEZE-NC-02 이미 안전한 gate 들을 수정하지 않았다 (§30)', () {
      for (final f in ['callableApplyToTO', 'callableAcceptTOInvitation',
        'callableInviteWorker', 'callableOfferAlternativeWork',
        'callableProposeConfirmedReassignment', 'callableCheckIn']) {
        expect(_fn(raw, f), contains('accountStatus'),
            reason: '$f 의 기존 accountStatus gate 가 사라졌다');
      }
    });

    test('DEL-FREEZE-NC-03 CheckOut·급여는 freeze 로 막지 않았다 (§38·§39)', () {
      expect(_fn(raw, 'callableCheckOut'), isNot(contains('accountStatus')),
          reason: '근무 중 퇴근은 freeze 후에도 가능해야 한다');
      expect(_fn(raw, 'callableCheckOut'),
          isNot(contains('ACCOUNT_STATUS_DELETING')));
    });

    test('DEL-FREEZE-NC-04 Storage barrier·tombstone rules ±0 (§56)', () {
      final st = _src('storage.rules');
      expect(st, contains('function accountDeletionBarrierExists(uid)'));
      expect(st, contains('!accountDeletionBarrierExists(uid);'));
      expect(rules, contains('match /account_deletion_tombstones/{uid} {'));
      final tomb = _flat(rules.substring(
          rules.indexOf('match /account_deletion_tombstones/{uid} {')));
      expect(tomb, contains('allow read: if false; allow create: if false;'));
    });

    test('DEL-FREEZE-NC-05 scheduler ±0 (§37)', () {
      expect(cf, contains('export const masterScheduler'));
      final ms = raw.substring(raw.indexOf('export const masterScheduler'));
      expect(ms.substring(0, 4000), isNot(contains('ACCOUNT_STATUS_DELETING')));
    });

    test('DEL-FREEZE-NC-06 UserProvider·AuthWrapper ±0 (§29)', () {
      final up = _src('lib/providers/user_provider.dart');
      expect(up, contains('await _authService.signOut(showToast: false);'));
      expect(up, isNot(contains('account_deletion_tombstones')));
      expect(up, isNot(contains("'deleting'")));
      final main = _src('lib/main.dart');
      expect(main, isNot(contains('deleting')));
      // [정정] `Recovery` 로 넓게 막으면 기존 `_HomeRegionRecoveryScreen`
      //   (거주지 복구 — 계정 삭제와 무관)이 걸린다. 계정 삭제 recovery 가
      //   아직 없다는 것만 본다.
      expect(main, isNot(contains('AccountDeletionRecovery')));
      expect(main, isNot(contains('account_deletion_tombstones')));
      expect(main, contains('_HomeRegionRecoveryScreen'),
          reason: '기존 거주지 복구 화면은 그대로 있어야 한다');
    });

    test('DEL-FREEZE-NC-07 Applications cleanup 정책 ±0 (§56)', () {
      final a = apps();
      expect(a, contains('cancelReason: "USER_DELETED"'));
      expect(a, contains('absentReason: "USER_DELETED"'));
      expect(a, contains('preservedCount:'));
    });

    test('DEL-FREEZE-NC-08 tombstone 삭제·TTL 추가 0 (§101)', () {
      expect(cf, isNot(contains('ACCOUNT_DELETION_TOMBSTONE_COL).doc(uid).delete()')));
      expect(cf, isNot(contains('cleanup_jobs')));
      expect('"account_deletion_tombstones"'.allMatches(cf).length, 1);
    });
  });
}
