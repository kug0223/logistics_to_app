// [R7-P4.4E.11C.0C.1.1] 가입중단이 stale read 로 user 문서를 지울 수 있었다
//
// `.0C.1` 의 Auth-tail 증거는 이것이다.
//
//   tombstone 있음 + users/{uid} 없음
//   = Final 이 모든 pre-Auth gate 를 통과한 뒤 그 문서를 지웠다
//
// 그 추론은 그 조합을 만들 수 있는 주인이 Final 뿐일 때만 성립한다. 그런데
// production 에는 user 문서를 지우는 Admin SDK writer 가 둘이었고, 둘째인
// 외국인 가입중단이 **transaction 밖에서 읽은 snapshot** 으로 지웠다.
//
//   Abort : registration_pending 읽음 (transaction 밖)
//   Freeze: tombstone + accountStatus="deleting" commit
//   Abort : stale read 를 들고 userRef.delete()
//
// 결과는 `tombstone 있음 + user 문서 없음` — 그런데 Final 의 어떤 gate 도
// 통과하지 않았다. 증거가 가짜가 된다.
//
// 그래서 fresh read 와 delete 를 한 transaction 에 넣었다. freeze 가 같은
// `users/{uid}` 를 쓰므로 경합하면 재시도되고, 재시도에서 `deleting` 을
// 관측해 거부된다. tombstone 도 같은 read-set 에 넣어 비정상 상태
// (`tombstone + registration_pending`)에서도 거부한다.
//
// 고정하는 것
//   AFT-BOUND-*  판정과 삭제의 경계
//   AFT-GUARD-*  허용 상태와 거부 semantics
//   AFT-TX-*     transaction 순수성
//   AFT-ORDER-*  side effect 순서
//   AFT-UNIQ-*   deletion journey 의 유일 삭제 주인
//   AFT-REG-*    가입 lifecycle 무변경
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
  final abortFn = _fn(raw, 'callableAbortForeignRegistration');
  final finalFn = _fn(raw, 'callableDeleteAccountFinal');
  final freeze = _helper(raw, 'srvEnsureAccountDeletionTombstone');
  final rulesFlat = _flat(_src('firestore.rules'));

  /// 가입중단의 user 문서 transaction 구간 — Auth 삭제 직전까지.
  String txBody() => abortFn.substring(
        _at(abortFn, 'const tombRefForAbort = db'),
        _at(abortFn, 'let authFail = false;'),
      );

  group('AFT-BOUND — 판정과 삭제의 경계 (§4·§6)', () {
    test('AFT-BOUND-01 삭제가 transaction 안으로 들어왔다', () {
      expect(_flat(abortFn), contains('await db.runTransaction(async (tx) => {'));
      expect(_flat(abortFn), contains('tx.delete(userRef);'));
      // 예전의 transaction 밖 삭제가 사라졌다.
      expect(abortFn, isNot(contains('await userRef.delete()')));
    });

    test('AFT-BOUND-02 판정은 fresh snapshot 으로 한다 — stale read 금지', () {
      expect(_flat(txBody()), contains(
          'const [freshUser, freshTomb] = await Promise.all([ '
          'tx.get(userRef), tx.get(tombRefForAbort), ]);'));
      expect(_flat(txBody()), contains(
          'const freshStatus = freshUser.data()?.accountStatus as string | undefined;'));
      // transaction 안에서 상단의 userSnap 을 다시 쓰지 않는다.
      expect(txBody(), isNot(contains('userSnap')));
    });

    test('AFT-BOUND-03 상단 pre-check 는 남지만 authority 가 아니다', () {
      // 빠른 거부는 유지한다(§10 회귀 금지). 그러나 삭제 판정은 TX 다.
      expect(_flat(abortFn), contains(r'if (status !== "registration_pending") {'));
      expect(_at(abortFn, r'if (status !== "registration_pending") {'),
          lessThan(_at(abortFn, 'const tombRefForAbort = db')));
    });
  });

  group('AFT-GUARD — 허용 상태와 거부 semantics (§9·§21·§22)', () {
    test('AFT-GUARD-01 registration_pending 만 지운다', () {
      expect(_flat(txBody()), contains(
          r'if (freshStatus !== "registration_pending") {'));
      expect(_at(txBody(), r'if (freshStatus !== "registration_pending") {'),
          lessThan(_at(txBody(), 'tx.delete(userRef);')));
    });

    test('AFT-GUARD-02 tombstone 이 있으면 거부한다 (§19·§21)', () {
      expect(_flat(txBody()), contains('if (freshTomb.exists) {'));
      expect(_flat(txBody()), contains('"탈퇴 처리 중인 계정입니다."'));
      // 그 판정이 삭제보다 앞이다.
      expect(_at(txBody(), 'if (freshTomb.exists) {'),
          lessThan(_at(txBody(), 'tx.delete(userRef);')));
    });

    test('AFT-GUARD-03 정책 거부는 throw, 인프라 실패는 partial 이다', () {
      expect(_flat(txBody()), contains(
          'if (fsErr instanceof HttpsError) throw fsErr;'));
      expect(_flat(txBody()), contains(
          'return {success: false, partial: true, reason: "FIRESTORE_RETRYABLE"};'));
      // generic INTERNAL 로 바꾸지 않는다.
      expect(txBody(), contains('"failed-precondition"'));
      expect(txBody(), isNot(contains('"internal"')));
    });

    test('AFT-GUARD-04 user 문서가 없으면 멱등 no-op 이다 (§28-A5)', () {
      expect(_flat(txBody()), contains('if (!freshUser.exists) return;'));
    });
  });

  group('AFT-TX — transaction 순수성 (§24)', () {
    test('AFT-TX-01 callback 안에 외부 I/O 가 없다', () {
      final body = txBody().substring(
          _at(txBody(), 'await db.runTransaction'),
          _at(txBody(), '} catch (fsErr) {'));
      for (final bad in [
        'admin.storage()', 'admin.auth()', 'srvPersistNotification',
        'bucket', 'getFiles', 'fetch(',
      ]) {
        expect(body, isNot(contains(bad)), reason: '$bad 는 transaction 밖이어야 한다');
      }
    });

    test('AFT-TX-02 읽는 문서 둘, 쓰는 것은 삭제 하나다', () {
      expect(_count(txBody(), 'tx.get('), 2);
      expect(_count(txBody(), 'tx.delete('), 1);
      expect(txBody(), isNot(contains('tx.set(')));
      expect(txBody(), isNot(contains('tx.update(')));
    });
  });

  group('AFT-ORDER — side effect 순서 (§11·§23·§25)', () {
    test('AFT-ORDER-01 Storage hard gate 가 user 문서 삭제보다 앞이다', () {
      expect(_at(abortFn, 'if (storageFail) {'),
          lessThan(_at(abortFn, 'const tombRefForAbort = db')));
      expect(_flat(abortFn), contains('reason: "STORAGE_RETRYABLE"'));
    });

    test('AFT-ORDER-02 Auth 삭제는 transaction 뒤다 — 거부되면 도달하지 않는다', () {
      expect(_at(abortFn, 'tx.delete(userRef);'),
          lessThan(_at(abortFn, 'admin.auth().deleteUser(uid)')));
      // 정책 거부는 throw 이므로 그 아래 Auth 삭제에 도달할 수 없다.
      expect(_at(abortFn, 'if (fsErr instanceof HttpsError) throw fsErr;'),
          lessThan(_at(abortFn, 'admin.auth().deleteUser(uid)')));
    });

    test('AFT-ORDER-03 fingerprint·Storage 정리 순서를 바꾸지 않았다 (§10·§12)', () {
      expect(_at(abortFn, 'foreignIdFingerprints'),
          lessThan(_at(abortFn, 'getFiles({prefix:')));
      expect(_at(abortFn, 'getFiles({prefix:'),
          lessThan(_at(abortFn, 'const tombRefForAbort = db')));
    });
  });

  group('AFT-UNIQ — deletion journey 의 유일 삭제 주인 (§14·§26)', () {
    test('AFT-UNIQ-01 writer 는 둘이지만 journey 안에서는 Final 뿐이다', () {
      // 서버 user 문서 삭제 자리: Final 1 + 가입중단 1.
      expect(_count(code, 'userRef.delete()'), 1); // Final
      expect(_count(code, 'tx.delete(userRef)'), 1); // 가입중단
      expect(finalFn, contains('userRef.delete()'));
      expect(abortFn, contains('tx.delete(userRef)'));
      // 그리고 가입중단은 tombstone 이 있으면 지우지 못한다.
      expect(txBody(), contains('if (freshTomb.exists) {'));
    });

    test('AFT-UNIQ-02 abort-first 뒤에는 tombstone 이 생기지 않는다 (§18)', () {
      expect(_flat(freeze), contains(
          'if (!hadTomb && !userSnap.exists) { return {hadTomb, '
          'projected: false, userExists: false, refused: true}; }'));
    });

    test('AFT-UNIQ-03 .0C.1 rules barrier 가 그대로다 (§15)', () {
      expect(rulesFlat, contains(
          'allow delete: if isSuperAdmin() && request.auth.uid != userId && '
          '!accountDeletionBarrierExists(userId);'));
      expect(rulesFlat, contains(
          'allow create: if isLoggedIn() && '
          '!accountDeletionBarrierExists(userId) && ('));
    });

    test('AFT-UNIQ-04 Auth-tail 증거 판정은 그대로다 (§30)', () {
      expect(_flat(finalFn), contains(
          'const authTailProven = !userSnap.exists && '
          '(await db.collection(ACCOUNT_DELETION_TOMBSTONE_COL).doc(uid).get()) '
          '.exists;'));
    });
  });

  group('AFT-REG — 가입 lifecycle 무변경 (§10)', () {
    test('AFT-REG-01 registration 관련 writer 를 건드리지 않았다', () {
      // 상태 의미·fingerprint 유일성·동의 기록 경로가 그대로다.
      expect(code, contains('export const callableFinalizeForeignIdentity'));
      expect(code, contains('export const callableRecordTermsConsent'));
      expect(_flat(abortFn), contains(
          r'const fpDocId = `${ownFingerprint}_${role}`;'));
      expect(_flat(abortFn), contains(
          r'if (fpSnap.exists && (fpSnap.data()?.uid as string | undefined) === uid) {'));
    });

    test('AFT-REG-02 partial/retryable 계약이 그대로다', () {
      expect(_flat(abortFn), contains('reason: "STORAGE_RETRYABLE"'));
      expect(_flat(abortFn), contains('reason: "FIRESTORE_RETRYABLE"'));
      expect(_flat(abortFn), contains(r'if (code === "auth/user-not-found") {'));
    });
  });
}
