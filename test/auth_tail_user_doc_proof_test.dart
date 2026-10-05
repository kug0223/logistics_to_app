// [R7-P4.4E.11C.0C.1] "user 문서가 없다" 를 증거로 쓸 수 있는가
//
// `.0C` 는 client reachability 를 닫았다. 그런데 서버 쪽 S3 재개가
// `deleted_accounts` 에서 role·identity key 를 복원하는 구조였고, 그 문서는
// canonical authority 가 아니다 — random auto-ID, SUPER_ADMIN 삭제 가능,
// 생존 보장 없음. 그래서 이 경로가 남아 있었다.
//
//   Final 최초 실행 → gate 통과 → user 문서 삭제 → Auth 실패 → S3
//   시간 경과로 deleted_accounts 소실
//   재시작 → 재개 → role/identity 복원 실패 → FIRESTORE_RETRYABLE 반복
//   → 영구 deletion lockout
//
// 이번 Phase 의 증명은 한 줄이다.
//
//   tombstone 있음 + users/{uid} 없음
//   = Final 이 모든 pre-Auth gate 를 통과한 뒤 그 문서를 지웠다
//
// 그 추론은 **그 조합을 만들 수 있는 주인이 하나**일 때만 성립한다. 그래서
// 두 구멍을 막았다.
//
//   · SUPER_ADMIN 클라이언트의 임의 user 문서 삭제 (tombstone 있을 때)
//   · 같은 uid 로 user 문서 재생성 (→ registration_pending → abort 삭제)
//
// 그리고 tombstone 은 user 문서가 살아 있을 때만 생성된다. 이 셋이 모이면
// S3 는 Final 만이 만들 수 있는 상태가 되고, 그때 남은 비가역 작업은 Auth
// 삭제 하나뿐이다 — role 도 identity key 도 다시 복원할 필요가 없다.
//
// 고정하는 것
//   TAIL-W-*      user 문서 DELETE writer 전수
//   TAIL-RULES-*  클라이언트 우회 차단 (emulator 셀과 쌍)
//   TAIL-ORD-*    모든 gate 가 user 문서 삭제보다 앞
//   TAIL-S3-*     검증된 Auth-tail 분기
//   TAIL-S2-*     S2 는 전체 pipeline 유지
//   TAIL-SEC-*    재생성 0 · tombstone 보존 · self-only
//   TAIL-DEP-*    deleted_accounts 의존 제거
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

int _at(String s, String needle) {
  final i = s.indexOf(needle);
  if (i < 0) throw StateError('경계를 찾지 못함: $needle');
  return i;
}

int _lastAt(String s, String needle) {
  final i = s.lastIndexOf(needle);
  if (i < 0) throw StateError('경계를 찾지 못함: $needle');
  return i;
}

int _count(String s, String needle) {
  var n = 0;
  var i = 0;
  while (true) {
    final k = s.indexOf(needle, i);
    if (k < 0) return n;
    n++;
    i = k + needle.length;
  }
}

String _fn(String raw, String name) {
  final a = raw.indexOf('export const $name =');
  if (a < 0) throw StateError('$name 을 찾지 못함');
  var b = raw.indexOf('\nexport const', a + 10);
  if (b < 0) b = raw.length;
  return _codeOf(raw.substring(a, b));
}

String _helper(String raw, String name) {
  final a = raw.indexOf('function $name(');
  if (a < 0) throw StateError('$name 을 찾지 못함');
  final rel = raw.substring(a).indexOf('\n}');
  if (rel < 0) throw StateError('$name 의 끝을 찾지 못함');
  return _codeOf(raw.substring(a, a + rel));
}

void main() {
  final raw = _src('functions/src/index.ts');
  final code = _codeOf(raw);
  final finalFn = _fn(raw, 'callableDeleteAccountFinal');
  final abortFn = _fn(raw, 'callableAbortForeignRegistration');
  final freeze = _helper(raw, 'srvEnsureAccountDeletionTombstone');
  final rules = _src('firestore.rules');
  final rulesFlat = _flat(rules);
  final authService = _src('lib/services/auth_service.dart');

  group('TAIL-W — user 문서 DELETE writer 전수 (§5·§40)', () {
    test('TAIL-W-01 서버에서 user 문서를 지우는 자리는 둘뿐이다', () {
      // [R7-P4.4E.11C.0C.1.1 갱신] 두 자리의 **모양**이 달라졌다.
      //   Final 은 gate 통과 뒤의 직접 삭제, 가입중단은 transaction 안의
      //   compare-delete 다. 자리 수는 그대로 둘이다.
      expect(_count(code, 'userRef.delete()'), 1); // Final
      expect(finalFn, contains('userRef.delete()'));
      expect(_count(code, 'tx.delete(userRef)'), 1); // 가입중단
      expect(abortFn, contains('tx.delete(userRef)'));
      // 다른 모양의 user 문서 삭제가 없다.
      expect(code, isNot(contains('batch.delete(userRef')));
      expect(code, isNot(contains('recursiveDelete')));
      expect(code, isNot(contains('bulkWriter')));
    });

    test('TAIL-W-02 가입 중단 writer 는 freeze 된 계정을 지울 수 없다', () {
      // user 문서가 있으면 `registration_pending` 만 허용한다.
      //   freeze 된 계정은 `deleting` 이므로 거부된다.
      expect(_flat(abortFn), contains(
          r'if (status !== "registration_pending") {'));
      expect(_flat(abortFn), contains('가입 대기 중인 계정에만 중단 요청이 허용됩니다.'));
      // [R7-P4.4E.11C.0C.1.1 갱신] 그 판정이 **commit 시점**으로 올라갔다.
      //   삭제와 같은 transaction 에서 fresh read 로 다시 본다. 그래서
      //   freeze 가 먼저 commit 되면 재시도에서 거부된다.
      expect(_flat(abortFn), contains(
          r'if (freshStatus !== "registration_pending") {'));
      expect(_at(abortFn, r'if (freshStatus !== "registration_pending") {'),
          lessThan(_at(abortFn, 'tx.delete(userRef)')));
      // tombstone 도 같은 read-set 에 있다 — deletion journey 면 거부다.
      expect(_flat(abortFn), contains('if (freshTomb.exists) {'));
      expect(_at(abortFn, 'if (freshTomb.exists) {'),
          lessThan(_at(abortFn, 'tx.delete(userRef)')));
    });

    test('TAIL-W-03 Auth trigger·대량 삭제 utility 가 없다 (§22·§23)', () {
      for (final bad in [
        'beforeUserDeleted', 'onAuthDelete', 'functions.auth.user',
        'deleteUserProfile', 'adminDeleteUser', 'cleanupUserDocument',
      ]) {
        expect(code, isNot(contains(bad)));
      }
    });

    test('TAIL-W-04 클라이언트 롤백 삭제는 rules 가 막는다 — 실효 writer 아님', () {
      // 내국인 가입 롤백이 user 문서를 직접 지우려 한다. 그러나 삭제
      //   권한은 SUPER_ADMIN 전용이라 본인 호출은 항상 거부되고, 코드는
      //   그 실패를 로그로만 남긴다(orphan 가능성을 스스로 적어 두었다).
      expect(authService, contains(
          "await _firestore.collection('users').doc(uid).delete();"));
      expect(authService, contains('Firestore 롤백 실패 (orphan 문서 가능)'));
      expect(rulesFlat, contains('allow delete: if isSuperAdmin() &&'));
    });
  });

  group('TAIL-RULES — 클라이언트 우회 차단 (§19·§20)', () {
    test('TAIL-RULES-01 tombstone 있는 user 문서는 삭제할 수 없다', () {
      expect(rulesFlat, contains(
          'allow delete: if isSuperAdmin() && request.auth.uid != userId && '
          '!accountDeletionBarrierExists(userId);'));
    });

    test('TAIL-RULES-02 tombstone 있는 uid 로 user 문서를 만들 수 없다', () {
      expect(rulesFlat, contains(
          'allow create: if isLoggedIn() && '
          '!accountDeletionBarrierExists(userId) && ('));
    });

    test('TAIL-RULES-03 barrier 판정은 기존 helper 하나다', () {
      expect(rulesFlat, contains(
          'function accountDeletionBarrierExists(uid) { '
          'return uid is string && uid.size() > 0 && exists('));
      // tombstone 컬렉션 접근은 여전히 전면 차단이다.
      expect(rulesFlat, contains(
          'match /account_deletion_tombstones/{uid} { '
          'allow read: if false; allow create: if false; '
          'allow update: if false; allow delete: if false; }'));
    });
  });

  group('TAIL-ORD — 모든 gate 가 user 문서 삭제보다 앞 (§41)', () {
    test('TAIL-ORD-01~07 순서가 source 로 고정된다', () {
      final order = [
        // O6 money/promise + 재인증 + 서브관리자
        'srvAssertAccountDeletionAllowed(',
        // freeze
        'srvEnsureAccountDeletionTombstone(uid)',
        // O1 domain residual
        'srvDeletionDomainCleared(domainResidual)',
        // O2 personal cleanup (실패 종류 수 > 0 이면 파괴 금지)
        'if (personalCleanup.failed > 0) {',
        // O3 identity cleanup
        'if (identityCleanup.failed > 0) {',
        // O4 Storage sweep
        'srvAccountStorageCleared(accSweep)',
        // O5 business cleanup hard gate
        'if (bizCleanupFailed) {',
        // 파괴 직전 재확인
        'srvDeletionPersonalCleared(personalResidual)',
        'srvDeletionIdentityCleared(identityResidual)',
        // user 문서
        'userRef.delete()',
      ];
      for (var i = 1; i < order.length; i++) {
        expect(_at(finalFn, order[i - 1]), lessThan(_at(finalFn, order[i])),
            reason: '${order[i - 1]} 가 ${order[i]} 보다 앞이어야 한다');
      }
      // O7 Auth 는 **마지막**이다. tail 분기에도 같은 호출이 있으므로
      //   전체 pipeline 의 것은 마지막 등장으로 본다.
      expect(_at(finalFn, 'userRef.delete()'),
          lessThan(_lastAt(finalFn, 'admin.auth().deleteUser(uid);')));
    });

    test('TAIL-ORD-02 각 gate 실패는 진행이 아니라 반환이다 (§8 ERROR ≠ ZERO)', () {
      // user 문서 삭제 **앞** 구간에 partial 반환이 여러 개 있고,
      //   best-effort 로 넘어가는 경로가 없다.
      final head = finalFn.substring(0, _at(finalFn, 'userRef.delete()'));
      expect(_count(head, 'partial: true'), greaterThanOrEqualTo(6));
      expect(_count(head, 'reason: "FIRESTORE_RETRYABLE"'),
          greaterThanOrEqualTo(4));
      expect(head, contains('reason: "DOMAIN_CLEANUP_INCOMPLETE"'));
      expect(head, contains('reason: "STORAGE_RETRYABLE"'));
    });

    test('TAIL-ORD-03 user 문서 삭제 실패면 Auth 를 건드리지 않는다', () {
      expect(_flat(finalFn), contains(
          'if (userDocFail) { return {success: false, partial: true, '
          'reason: "FIRESTORE_RETRYABLE"}; }'));
      expect(_at(finalFn, 'if (userDocFail) {'),
          lessThan(_lastAt(finalFn, 'admin.auth().deleteUser(uid);')));
    });
  });

  group('TAIL-S3 — 검증된 Auth-tail (§42)', () {
    test('TAIL-S3-01 증거 조건은 user 문서 없음 + tombstone 존재다', () {
      expect(_flat(finalFn), contains(
          'const authTailProven = !userSnap.exists && '
          '(await db.collection(ACCOUNT_DELETION_TOMBSTONE_COL).doc(uid).get()) '
          '.exists;'));
    });

    test('TAIL-S3-02 그 증거가 deleted_accounts 에 기대지 않는다 (§13·§14·§24)', () {
      // 판정식에 role·identity key·deleted_accounts 가 없다.
      final decl = finalFn.substring(
          _at(finalFn, 'const authTailProven ='),
          _at(finalFn, 'const tombstoneOk ='));
      expect(decl, isNot(contains('deleted_accounts')));
      expect(decl, isNot(contains('identityKeys')));
      // 그리고 그 증거가 **면제하는 것은 identity 복원 하나**다.
      expect(_count(finalFn, 'authTailProven'), 3);
      expect(_flat(finalFn), contains(
          'if (!srvDeletionIdentityCleared(identityResidual) && '
          '!(authTailProven && identityResidual.identityUnresolved &&'));
    });

    test('TAIL-S3-03 면제는 이미 지나간 단계뿐이다 — 모르면 통과가 아니다', () {
      // 쿼리 실패·잔존 행·tax·sentinel 은 그대로 막는다.
      expect(_flat(finalFn), contains('!identityResidual.queryFailed &&'));
      expect(_flat(finalFn), contains('identityResidual.queryRows === 0 &&'));
      expect(_flat(finalFn), contains('identityResidual.taxIdentity === 0 &&'));
      expect(_flat(finalFn), contains('identityResidual.sentinels === 0)) {'));
    });

    test('TAIL-S3-04 tombstone 이 없으면 증거가 아니다 (§32)', () {
      // freeze 는 user 문서가 없으면 tombstone 을 새로 만들지 않는다 —
      //   그래서 tombstone 없는 user-missing 은 fail-closed 로 수렴한다.
      expect(_flat(freeze), contains(
          'if (!hadTomb && !userSnap.exists) { return {hadTomb, '
          'projected: false, userExists: false, refused: true}; }'));
      expect(_flat(freeze), contains('if (out.refused) {'));
      expect(_flat(finalFn), contains(
          'if (!tombstoneOk) { return {success: false, partial: true, '
          'reason: "FIRESTORE_RETRYABLE"}; }'));
    });

    test('TAIL-S3-05 파괴 지점은 여전히 각각 하나다', () {
      // Auth-tail 을 위해 두 번째 삭제 자리를 만들지 않았다 — 나머지
      //   gate 도 그대로 실행된다(§17).
      expect(_count(finalFn, 'admin.auth().deleteUser(uid)'), 1);
      expect(_count(finalFn, 'userRef.delete()'), 1);
      expect(_at(finalFn, 'const authTailProven ='),
          lessThan(_at(finalFn, 'const tombstoneOk =')));
      expect(_at(finalFn, 'srvAssertAccountDeletionAllowed('),
          lessThan(_at(finalFn, 'const authTailProven =')));
    });

    test('TAIL-S3-06 Auth 오류 semantics 는 기존 계약 그대로다 (§34)', () {
      expect(_flat(finalFn), contains(
          r'if (errCode === "auth/user-not-found") {'));
      expect(_flat(finalFn), contains('throw authErr;'));
      expect(_flat(finalFn), contains('return {success: true};'));
    });
  });

  group('TAIL-S2 — S2 는 전체 pipeline 유지 (§15·§43·§44)', () {
    test('TAIL-S2-01 user 문서가 있으면 증거가 성립하지 않는다 (§15)', () {
      // 판정의 첫 항이 `!userSnap.exists` 다 — tombstone 만으로는 어떤
      //   면제도 생기지 않는다. S2 는 전체 pipeline 을 그대로 지난다.
      expect(_flat(finalFn),
          contains('const authTailProven = !userSnap.exists &&'));
    });

    test('TAIL-S2-02 S2 에서 잔존이 있으면 user·Auth 파괴 0', () {
      // 전체 pipeline 의 gate 가 모두 그대로 있고, 면제는 identity 복원
      //   하나뿐이다(TAIL-S3-02·03 과 쌍).
      expect(finalFn, contains('srvCountDeletionDomainResidual(uid)'));
      expect(finalFn, contains('srvCleanupDeletionOwnedPersonal(uid)'));
      expect(finalFn, contains('srvSweepAccountOwnedStorage(uid)'));
      expect(finalFn, contains('srvCountDeletionPersonalResidual(uid)'));
      expect(finalFn,
          contains('srvCountDeletionIdentityResidual(uid, identityKeys)'));
      // 그 gate 들은 authTailProven 과 무관하게 평가된다.
      expect(_flat(finalFn), contains(
          'if (!srvDeletionDomainCleared(domainResidual)) {'));
      expect(_flat(finalFn), contains(
          'if (!srvDeletionPersonalCleared(personalResidual)) {'));
      expect(_flat(finalFn), contains(
          'if (!srvAccountStorageCleared(accSweep)) {'));
      expect(_flat(finalFn), contains('if (bizCleanupFailed) {'));
    });
  });

  group('TAIL-SEC — 재생성 0 · tombstone 보존 · self-only (§37·§38·§48)', () {
    test('TAIL-SEC-01 증거 판정은 읽기 전용이다', () {
      final decl = finalFn.substring(
          _at(finalFn, 'const authTailProven ='),
          _at(finalFn, 'const tombstoneOk ='));
      expect(decl, isNot(contains('.set(')));
      expect(decl, isNot(contains('.update(')));
      expect(decl, isNot(contains('.delete()')));
    });

    test('TAIL-SEC-02 tombstone 을 지우지 않는다', () {
      expect(code, isNot(contains(
          'ACCOUNT_DELETION_TOMBSTONE_COL).doc(uid).delete()')));
    });

    test('TAIL-SEC-03 uid 는 호출자 자신이다', () {
      expect(_flat(finalFn), contains('const uid = request.auth.uid;'));
      expect(finalFn, isNot(contains('request.data')));
    });
  });

  group('TAIL-DEP — deleted_accounts 의존 제거 (§24·§F)', () {
    test('TAIL-DEP-01 tail 경로는 deleted_accounts 없이 완료된다', () {
      // role 복원은 전체 pipeline 경로에만 남는다(S2 재시도용).
      expect(finalFn, contains('deleted_accounts'));
      // role 복원은 전체 pipeline(S2 재시도)용으로 그대로 남는다.
      expect(_at(finalFn, 'deleted_accounts'),
          lessThan(_at(finalFn, 'const authTailProven =')));
      // 그러나 tail 분기 안에서는 그것을 쓰지 않는다(TAIL-S3-02 와 쌍).
      // 그리고 identity 복원 helper 는 그대로다 — 재설계하지 않았다.
      final keys = _helper(raw, 'srvResolveDeletionIdentityKeys');
      expect(_flat(keys), contains(
          r'const recSnap = await db.collection("deleted_accounts") '
          r'.where("uid", "==", uid).limit(1).get();'));
    });
  });
}
