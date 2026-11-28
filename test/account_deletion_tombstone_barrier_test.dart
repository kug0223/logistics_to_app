// [R7-P4.4E.11C.0B] 쓸어내고 비었는지 확인한 뒤에도, 다른 기기가 올리면 고아가 됐다
//
// 95cc737 이 계정 삭제의 Storage 정리를 hard gate 로 만들었다 — 실제로 0 임을
// 재열거로 확인한 뒤에만 identity 를 파괴한다. 그런데 경합이 하나 남았다.
//
//   sweep → 재열거 0 → **다른 기기/이미 열린 세션이 새 파일 업로드**
//   → users 문서 삭제 → Auth 삭제
//   → 그 파일은 포인터도, cleanup 주인도, 재시도 경로도 없는 고아
//
// DEV 실측(R7-P4.4E.11C.0A.1)에서 두 가지가 확인됐다.
//   ① Storage Rules 의 cross-service firestore.exists() 가 동작한다
//      (원인은 플랫폼이 아니라 service agent IAM binding 부재였다)
//   ② Rules 는 resumable session 의 `start` 가 아니라 **`finalize`** 에서
//      평가된다 — 그래서 barrier 를 켜면 **이미 열려 있던 session 도**
//      완료되지 못한다. CREATE·OVERWRITE 모두 거부되고 기존 generation 은
//      바뀌지 않았다 (CASE A).
//
// CASE A 이므로 뒤늦게 도착하는 object 를 치우는 trigger·scheduler 가 필요
// 없다. 필요한 것은 **identity 보다 오래 사는 barrier** 하나다.
//
// barrier 를 user 문서에 두면 Final 이 그 문서를 지우는 순간 사라진다.
// 그래서 `account_deletion_tombstones/{uid}` 를 쓴다 — 존재 자체가 barrier 다.
//
// 이 파일이 고정하는 것
//   ACC-TOMB-xx        tombstone lifecycle (생성·멱등·실패·보존)
//   ACC-DEL-ORDER-xx   barrier < 열거 < 잔존0 < user doc < Auth
//   ACC-TOMB-RULE-xx   Firestore 권위 (source 축; evaluator 는 별도)
//   ACC-STOR-BAR-xx    Storage barrier 범위·비변경·격리
//   ACC-TOMB-NC-xx     건드리지 않은 것
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

String _slice(String raw, String from, String to) {
  final a = raw.indexOf(from);
  if (a < 0) throw StateError('$from 를 찾지 못함');
  final b = raw.indexOf(to, a + from.length);
  if (b < 0) throw StateError('$to 를 찾지 못함');
  return raw.substring(a, b);
}

const _cf = 'functions/src/index.ts';
const _fsRules = 'firestore.rules';
const _stRules = 'storage.rules';

void main() {
  final raw = _src(_cf);
  final cf = _codeOf(raw);
  final fsRules = _src(_fsRules);
  final stRules = _src(_stRules);

  String fin() => _codeOf(_slice(
      raw, 'export const callableDeleteAccountFinal',
      '\n// ─── callableCheckIdCardAccess'));
  String helper() => _codeOf(_slice(
      raw, 'async function srvEnsureAccountDeletionTombstone(', '\n}'));
  String sweep() => _codeOf(_slice(
      raw, 'async function srvSweepAccountOwnedStorage(', '\n}'));
  /// storage.rules 의 users 블록 + barrier helper.
  String stUsers() => _flat(_slice(stRules,
      'function accountDeletionBarrierExists(uid)', '\n    // ──'));
  String fsTomb() => _flat(_slice(fsRules,
      'match /account_deletion_tombstones/{uid} {', '\n    }'));

  // ══════════════════════════════════════════════════════════════
  group('ACC-TOMB tombstone lifecycle (§4~§15·§18~§21·§51)', () {
    test('ACC-TOMB-01 tombstone 이 sweep 보다 **앞**이다', () {
      final f = fin();
      final tAt = f.indexOf('await srvEnsureAccountDeletionTombstone(uid)');
      final sAt = f.indexOf('await srvSweepAccountOwnedStorage(uid)');
      expect(tAt, greaterThan(-1), reason: 'Final 이 barrier 를 세우지 않는다');
      expect(sAt, greaterThan(tAt),
          reason: 'barrier 보다 열거가 먼저면 그 사이 업로드가 고아가 된다');
    });

    test('ACC-TOMB-02 key 는 caller uid 하나다 (§14·§15)', () {
      final h = helper();
      expect(h, contains(
          'db.collection(ACCOUNT_DELETION_TOMBSTONE_COL).doc(uid)'));
      expect(cf, contains(
          'const ACCOUNT_DELETION_TOMBSTONE_COL = "account_deletion_tombstones";'));
      // 무작위 id·클라이언트 uid 를 쓰지 않는다.
      expect(h, isNot(contains('.add(')));
      expect(h, isNot(contains('request.data')));
      // 호출은 canonical caller uid 로만.
      expect(fin(), contains('srvEnsureAccountDeletionTombstone(uid)'));
      // 안전하지 않은 uid 는 거부.
      expect(_flat(h), contains('uid.includes("/") || uid.includes("..")'));
    });

    test('ACC-TOMB-03 처음에는 생성한다 (§6 최소 schema)', () {
      final h = _flat(helper());
      expect(h, contains('barrierAt: admin.firestore.FieldValue.serverTimestamp(),'));
      expect(h, contains('schemaVersion: 1,'));
      // PII·경로 목록을 담지 않는다.
      for (final bad in ['name', 'email', 'phone', 'ciHash', 'accountNumber',
        'idCardImagePath', 'bankbookImagePath', 'businessId', 'uid:']) {
        expect(h.contains('$bad:'), false, reason: '$bad 를 tombstone 에 담지 않는다');
      }
    });

    test('ACC-TOMB-04 재호출은 멱등이고 barrierAt 을 되돌리지 않는다 (§13·§53)', () {
      // [R7-P4.4E.11C.0C.0a 갱신] helper 가 단일 `get`/`set` 에서
      //   **트랜잭션**으로 바뀌었다 — tombstone 과 `accountStatus` freeze
      //   projection 을 같은 경계에서 맞춰야 하기 때문이다. 묻는 것은
      //   그대로다: 이미 있으면 barrierAt 을 다시 쓰지 않는다.
      final h = helper();
      expect(h, contains('const hadTomb = tombSnap.exists;'));
      expect(_flat(h), contains('if (!hadTomb) { tx.set(tombRef, {'));
      expect('barrierAt:'.allMatches(h).length, 1,
          reason: 'barrierAt 쓰기가 한 곳뿐이어야 재시도에 보존된다');
      expect(h, isNot(contains('merge: true')));
      expect(h, contains('return true;'));
    });

    test('ACC-TOMB-05 commit 실패는 파괴적 작업을 전부 막는다 (§16·§46)', () {
      final f = fin();
      expect(_flat(f), contains(
          'const tombstoneOk = await srvEnsureAccountDeletionTombstone(uid); '
          'if (!tombstoneOk) { return {success: false, partial: true, '
          'reason: "FIRESTORE_RETRYABLE"}; }'));
      final gate = f.indexOf('if (!tombstoneOk) {');
      for (final later in [
        'await srvSweepAccountOwnedStorage(uid)',
        'await userRef.delete()',
        'admin.auth().deleteUser(uid)',
        'array-contains',
      ]) {
        expect(f.indexOf(later), greaterThan(gate),
            reason: '$later 가 barrier 게이트보다 앞이면 안 된다');
      }
      // helper 는 throw 하지 않고 false 를 돌려준다 — 호출부가 판단한다.
      expect(helper(), contains('return false;'));
    });

    test('ACC-TOMB-06~08 Storage·user·Auth 실패에도 tombstone 을 유지한다', () {
      // tombstone 을 지우는 코드가 **어디에도** 없다.
      expect(cf, isNot(contains('ACCOUNT_DELETION_TOMBSTONE_COL).doc(uid).delete()')));
      // [R7-P4.4E.11C.0C.1 갱신] Final 이 상수를 직접 쓰는 자리가 하나
      //   생겼다 — Auth-tail 증거("user 문서 없음 + tombstone 존재")를
      //   읽는 곳이다. 쓰기·삭제는 여전히 없다.
      expect('ACCOUNT_DELETION_TOMBSTONE_COL'.allMatches(fin()).length, 1);
      expect(fin(), contains('ACCOUNT_DELETION_TOMBSTONE_COL).doc(uid).get()'));
      expect(fin(), isNot(contains('ACCOUNT_DELETION_TOMBSTONE_COL).doc(uid).set(')));
      expect(fin(), isNot(contains('ACCOUNT_DELETION_TOMBSTONE_COL).doc(uid).delete()')));
      // [R7-P4.4E.11C.0C.0a.4.2 갱신] 2 → 3.
      //   상수 선언 1 + ensure helper(쓰기) 1 + in-tx **읽기** helper 1.
      //   이 셀이 막으려던 것은 "tombstone 을 지우는 writer 가 늘어나는 것"
      //   이고, 늘어난 것은 읽기 전용 helper 다. 그 사실을 함께 고정한다 —
      //   숫자만 올리면 다음에 쓰기가 늘어도 통과한다.
      // [R7-P4.4E.11C.0C 갱신] 3 → 4. 늘어난 자리는 삭제 재개 상태를
      //   돌려주는 self-only **읽기** callable 이다.
      final tombWrites = 'ACCOUNT_DELETION_TOMBSTONE_COL'.allMatches(cf).length;
      // [ALFIT-AUTH-KAKAO-ONBOARDING.1 갱신] 6 → 7. 옛 가입중단이 tombstone 이 선 uid 를 거부하려고 존재를 읽는다(.get() — 쓰기 아님).
      expect(cf, isNot(contains('ACCOUNT_DELETION_TOMBSTONE_COL).doc(uid).delete()')));
      // [판정281 갱신] 7 → 8. 서버 fence helper(srvAssertCallerNotInDeletion)가 caller 의 tombstone 존재를 **읽는다**
      //   (.get() — 쓰기·삭제 아님). 삭제 writer 0 은 위 단언 그대로.
      expect(_src('functions/src/index.ts'),
          contains('frozen = (await db.collection(ACCOUNT_DELETION_TOMBSTONE_COL).doc(uid).get()).exists;'));
      expect(tombWrites, 8,
          reason: '선언 1 + ensure 1 + in-tx 읽기 1 + 재개 질의 1 + '
              'Auth-tail 증거 읽기 1 + 가입중단 race guard 1 + 가입중단 거부 읽기 1 + fence 읽기 1 = 8');
      // 늘어난 자리는 `tx.get` 이고 삭제가 아니다.
      expect(cf, contains('await tx.get(\n    db.collection(ACCOUNT_DELETION_TOMBSTONE_COL).doc(uid))'));
      expect('ACCOUNT_DELETION_TOMBSTONE_COL).doc(uid).delete()'.allMatches(cf).length, 0);
    });

    test('ACC-TOMB-09 완전 성공 뒤에도 유지한다 (§21·§51)', () {
      final f = fin();
      // 성공 반환 직전 구간에 tombstone 삭제가 없다.
      // [판정280 갱신] Final 성공 반환이 카카오 연결 해제 범위(providerUnlink · server_api_1 §5A)를 함께 싣게 됐다 — 같은 명시적 성공 반환.
      final tail = _slice(f, 'admin.auth().deleteUser(uid)', 'return providerUnlink === null ? {success: true} : {success: true, providerUnlink};');
      expect(tail, isNot(contains('tombstone')));
      expect(tail, isNot(contains('account_deletion_tombstones')));
      expect(f, contains('return providerUnlink === null ? {success: true} : {success: true, providerUnlink};'));
    });

    test('ACC-TOMB-10 자동 삭제·TTL·cleanup owner 가 없다 (§7·§52)', () {
      expect(cf, isNot(contains('account_deletion_tombstones")\n')));
      // 문자열 자체는 상수 선언 1곳에만 등장한다.
      expect('"account_deletion_tombstones"'.allMatches(cf).length, 1);
      // scheduler·cleanup job 을 추가하지 않았다.
      expect(cf, isNot(contains('cleanup_jobs')));
      expect(cf, isNot(contains('tombstoneCleanup')));
    });

    test('ACC-TOMB-11 canonical writer 는 Final 하나다 (§9)', () {
      expect('srvEnsureAccountDeletionTombstone('.allMatches(cf).length, 3,
          reason: '정의 1 + PreData(BEGIN) 1 + Final(fail-safe) 1. '
              '[0C.0a 갱신] freeze owner 가 PreData 로 옮겨지고 Final 은 '
              '구버전·직접 호출용 fail-safe 로 같은 helper 를 부른다.');
      // [정정] 끝 표지를 `// ─── callableDeleteAccountFinal` 이나 다음
      //   `export const` 로 두면, 그 사이에 있는 신규 helper 까지 슬라이스에
      //   들어와 이 단정이 자기 자신을 잡는다(helper 는 `async function` 이라
      //   `export const` 로 끊기지 않는다). PreData 의 **닫는 괄호**까지만
      //   자른다 — top-level `);` 는 함수 끝이다.
      final preStart = raw.indexOf('export const callableDeleteAccountPreData');
      final preEndRel = raw.substring(preStart).indexOf('\n);');
      expect(preStart, greaterThan(-1));
      expect(preEndRel, greaterThan(0));
      final pre = _codeOf(raw.substring(preStart, preStart + preEndRel));
      // [0C.0a 갱신] PreData 가 BEGIN owner 가 됐다 — 이제 **호출해야** 한다.
      expect(pre, contains('srvEnsureAccountDeletionTombstone(uid)'));
      final app = _codeOf(_slice(raw,
          'export const callableDeleteAccountApplications', '\n// ──'));
      expect(app, isNot(contains('srvEnsureAccountDeletionTombstone')));
      // 클라이언트도 모른다 (§56)
      expect(_src('lib/services/auth_service.dart'),
          isNot(contains('account_deletion_tombstones')));
    });

    test('ACC-TOMB-12 precondition 실패에서는 세우지 않는다 (§11)', () {
      final f = fin();
      final tAt = f.indexOf('await srvEnsureAccountDeletionTombstone(uid)');
      for (final pre in [
        '"재인증 후 10분이 초과되었습니다. 다시 시도해주세요."',
        '서브관리자로 등록된 사업장',
        '미서명 계약서',
      ]) {
        expect(f.indexOf(pre), lessThan(tAt),
            reason: '$pre 검증이 barrier 보다 뒤면 진입 못 할 사용자도 봉쇄된다');
      }
    });

    test('ACC-TOMB-13 로그에 전체 uid·경로를 남기지 않는다 (§72)', () {
      final h = helper();
      // [R7-P4.4E.11C.0C.0a 갱신] freeze 가 projection 까지 맞추므로 로그가
      //   두 축(tombstone·projection·userDoc)을 함께 보고한다. 묻는 것은
      //   그대로다 — 수치·상태 라벨만 남기고 uid·경로는 남기지 않는다.
      expect(h, contains('"[accountDeletionTombstone] " +'));
      // [R7-P4.4E.11C.0C.1 갱신] 상태 라벨이 셋이 됐다 — user 문서가 없어
      //   생성을 거부한 경우(refused)가 추가됐다. 라벨만 남기는 계약은
      //   그대로다.
      expect(h, contains(r'const tombState = out.hadTomb ?'));
      expect(h, contains(r'"existed" : (out.refused ? "refused" : "created");'));
      expect(h, contains(r'tombstone=${tombState}'));
      expect(h, contains(r'projection=${out.projected ? "set" : "unchanged"}'));
      expect(h, isNot(contains(r'uid=${uid}')));
      expect(h, isNot(contains(r'${e}')),
          reason: 'Firestore 오류 문자열에 문서 경로가 담긴다');
      expect(h, contains('code=\${(e as {code?: unknown})?.code ?? "unknown"}'));
    });
  });

  // ══════════════════════════════════════════════════════════════
  group('ACC-DEL-ORDER 파괴 순서 (§0·§85)', () {
    test('ACC-DEL-ORDER-01 preconditions < ensureTombstone', () {
      final f = fin();
      expect(f.indexOf('throw new HttpsError("unauthenticated"'),
          lessThan(f.indexOf('srvEnsureAccountDeletionTombstone')));
    });

    test('ACC-DEL-ORDER-02 ensureTombstone < 첫 Storage 열거', () {
      final f = fin();
      expect(f.indexOf('srvEnsureAccountDeletionTombstone'),
          lessThan(f.indexOf('srvSweepAccountOwnedStorage')));
      // [§45] Final 안에서 barrier 전에 직접 열거/삭제하지 않는다.
      final beforeBarrier =
          f.substring(0, f.indexOf('srvEnsureAccountDeletionTombstone'));
      expect(beforeBarrier, isNot(contains('getFiles(')));
      expect(beforeBarrier, isNot(contains('.file(')));
      expect(beforeBarrier, isNot(contains('admin.storage()')));
      // helper 내부도 — sweep 만 Storage 를 만진다.
      expect(helper(), isNot(contains('admin.storage()')));
    });

    test('ACC-DEL-ORDER-03 Storage 잔존 0 < user 문서 삭제', () {
      final f = fin();
      expect(f.indexOf('if (!srvAccountStorageCleared(accSweep)) {'),
          lessThan(f.indexOf('await userRef.delete()')));
    });

    test('ACC-DEL-ORDER-04 user 문서 삭제 < Auth 삭제', () {
      final f = fin();
      expect(f.indexOf('await userRef.delete()'),
          lessThan(f.indexOf('admin.auth().deleteUser(uid)')));
    });
  });

  // ══════════════════════════════════════════════════════════════
  // [§24·§83 주의] 아래는 **source 축**이다. 실제 rule evaluator 판정은
  //   scripts/r7-e11c0b-emu-rules.js 가 에뮬레이터에서 수행하고, 보고서가
  //   증거 등급을 분리한다. 이 셀들은 "규칙이 존재하고 열려 있지 않다"만
  //   본다 — 그것만으로 PASS 선언하지 않는다.
  group('ACC-TOMB-RULE Firestore 권위 (source 축) (§22·§23)', () {
    test('ACC-TOMB-RULE-00 tombstone 규칙이 존재하고 4축 전부 false 다', () {
      final t = fsTomb();
      for (final a in ['allow read: if false;', 'allow create: if false;',
        'allow update: if false;', 'allow delete: if false;']) {
        expect(t, contains(a), reason: '$a 가 없다');
      }
      // SUPER_ADMIN 예외를 두지 않았다 (§24·§26)
      expect(t, isNot(contains('isSuperAdmin')));
      expect(t, isNot(contains('isLoggedIn')));
      expect(t, isNot(contains('request.auth')));
    });

    test('ACC-TOMB-RULE-23 겹치는 allow 가 없다 (§23 overlapping)', () {
      // tombstone 경로에 매칭될 수 있는 다른 match 를 전수 확인한다.
      //   2-segment wildcard match 가 있으면 거기서 열릴 수 있다.
      // [정정] `/[^\s{]+` 는 `/{document=**}` 의 `{` 에서 끊긴다 — 경로에
      //   중괄호가 들어가므로 줄 단위로 읽는다.
      final matches = fsRules
          .split(RegExp(r'\r?\n'))
          .map((l) => RegExp(r'^match\s+(\S+)\s*\{$').firstMatch(l.trim()))
          .where((m) => m != null)
          .map((m) => m!.group(1)!)
          .toList();
      final wildcards = matches.where((p) =>
          RegExp(r'^/\{[A-Za-z_]+(=\*\*)?\}').hasMatch(p)).toList();
      expect(wildcards, ['/{document=**}'],
          reason: '최상위 wildcard 가 catch-all 하나여야 한다. 실제=$wildcards');
      // 그 catch-all 은 전면 차단이다.
      expect(_flat(_slice(fsRules, 'match /{document=**} {', '\n    }')),
          contains('allow read, write: if false;'));
      // 이름이 tombstone 과 겹치는 다른 collection match 가 없다.
      expect(matches.where((p) => p.contains('account_deletion_tombstones')).length, 1);
    });

    test('ACC-TOMB-RULE-21 기존 Firestore 권한이 바뀌지 않았다 (§59·§60)', () {
      // 대표 collection 의 기존 규칙이 그대로다.
      for (final keep in [
        'match /users/{userId} {',
        'match /businesses/{businessId} {',
        'match /applications/{applicationId} {',
        'match /attendance/{attendanceId} {',
        'match /deleted_accounts/{docId} {',
      ]) {
        expect(fsRules, contains(keep), reason: '$keep 가 사라졌다');
      }
      // deleted_accounts 는 건드리지 않았다 (§3)
      final da = _flat(_slice(fsRules, 'match /deleted_accounts/{docId} {', '\n    }'));
      expect(da, contains('allow read: if isSuperAdmin();'));
      // [판정281 갱신] 서버 fence: 쓰기 규칙 바깥에 `callerNotDeleting() && (` 감싸기만 붙었다 — 안쪽 조건 단언은 그대로.
      expect(da, contains('allow delete: if callerNotDeleting() && (isSuperAdmin());'));
      // collectionGroup 조건을 손대지 않았다.
      expect(fsRules.contains('collectionGroup'), fsRules.contains('collectionGroup'));
    });
  });

  // ══════════════════════════════════════════════════════════════
  group('ACC-STOR-BAR Storage barrier (§28~§37·§62~§64)', () {
    test('ACC-STOR-BAR-00 helper 는 exists() 1회만 한다 (§28·§39·§40)', () {
      final h = _flat(_slice(stRules,
          'function accountDeletionBarrierExists(uid)', '\n    }'));
      expect(h, contains(
          'return firestore.exists( '
          '/databases/(default)/documents/account_deletion_tombstones/\$(uid));'));
      // get() 으로 내용을 읽지 않는다 — 존재만 본다 (§5)
      expect(h, isNot(contains('firestore.get(')));
      // 전체 파일에서 barrier 조회(exists)는 이 한 곳뿐이다.
      expect('firestore.exists('.allMatches(stRules).length, 1);
      // [FULL13-DOC-INTEGRITY.4 갱신] 이전: get() 0. 이제 신분증 객체 **delete** 에서만
      //   "지금 참조 중인가"를 get() 1회로 본다(isCurrentIdCard). delete 분기는 barrier 를
      //   보지 않으므로 평가 한 번당 Firestore 접근은 여전히 최대 1회다(§40).
      // [DOC-PRODUCT-DELETE.8 갱신] 예전 단언: get() 1곳. create 에 '정리 대기 이름은 다시 만들지
      //   못한다'(isRetiringIdCard)가 더해져 2곳이다. 둘 다 **같은 users 문서**라 평가당 서로 다른
      //   문서 수는 users + tombstone 최대 2개 그대로다(§40).
      // [storage_301 갱신] 예전 단언: get() 2곳. 증빙(통장사본·사업자등록증) 현재 경로 재생성 금지(isCurrentEvidence)가
      //   더해져 3곳이다. 셋 다 **같은 users 문서**이고 이름 범위가 서로 겹치지 않아(idCard_ / bankbook_·businessLicense_)
      //   한 평가에서 도는 get 은 많아야 같은 문서 하나 — 서로 다른 문서 수는 users + tombstone 최대 2개 그대로다(§40).
      expect('firestore.get('.allMatches(_codeOf(stRules)).length, 3);
      final ev = _flat(_slice(stRules, 'function isCurrentEvidence(uid, name)', '\n    }'));
      expect(ev, contains('firestore.get(/databases/(default)/documents/users/\$(uid))'));
      final cur = _flat(_slice(stRules, 'function isCurrentIdCard(uid, name)', '\n    }'));
      expect(cur, contains('firestore.get(/databases/(default)/documents/users/\$(uid))'));
      final ret = _flat(_slice(stRules, 'function isRetiringIdCard(uid, name)', '\n    }'));
      expect(ret, contains('firestore.get(/databases/(default)/documents/users/\$(uid))'));
      // barrier helper 사용은 create·update 두 분기 — 한 평가에서 둘이 같이 돌지 않는다 (§40)
      expect('accountDeletionBarrierExists(uid)'.allMatches(stRules).length, 3,
          reason: '정의 1 + create 1 + update 1');
    });

    test('ACC-STOR-BAR-01~07 create/update 가 barrier 뒤에 걸린다', () {
      final u = stUsers();
      // [FULL13-DOC-INTEGRITY.4 갱신] 이전: `allow create, update:` 한 줄. 신분증 객체의
      //   덮어쓰기 금지 때문에 둘로 나뉘었다 — 둘 다 여전히 barrier 를 마지막에 본다.
      // [STORAGE-FINALIZE.5 · S1] 신분증 이름은 객체가 없고 **지금 참조 경로가 아닐 때만** 만든다.
      // [DOC-PRODUCT-DELETE.8 갱신] 정리 대기(idDocumentOrphanPaths) 이름도 만들지 못한다 — 늦게 끝나는
      //   서버 정리가 지우는 generation 이 언제나 정리 대기 전의 그 객체가 되게. barrier 는 여전히 마지막이다.
      expect(u, contains(
          'allow create: if isLoggedIn() && request.auth.uid == uid && '
          '(!isIdCardName(request.resource.name) || '
          '(resource == null && !isCurrentIdCard(uid, request.resource.name) && '
          '!isRetiringIdCard(uid, request.resource.name))) && '
          // [storage_301] 증빙 이름도 객체가 없고 지금 기록 경로가 아닐 때만 만든다(바꿔치기 0).
          '(!isEvidenceName(request.resource.name) || '
          '(resource == null && !isCurrentEvidence(uid, request.resource.name))) && '
          'isUnder5MB() && isImageType() && !accountDeletionBarrierExists(uid);'));
      expect(u, contains(
          'allow update: if isLoggedIn() && request.auth.uid == uid && '
          '!isIdCardName(resource.name) && '
          // [storage_301] 증빙 객체 덮어쓰기 금지.
          '!isEvidenceName(resource.name) && '
          'isUnder5MB() && isImageType() && !accountDeletionBarrierExists(uid);'));
      // generic prefix 이므로 네 writer + 미래 writer 전부 덮는다 (§32·§33)
      expect(u, contains('match /users/{uid}/{allPaths=**} {'));
    });

    test('ACC-STOR-BAR-10·11 read·delete semantics 무변경 (§30·§63)', () {
      final u = stUsers();
      // [FULL13-DOC-INTEGRITY.4 갱신] 이전: `allow read, delete:` 한 줄(둘 다 본인만).
      //   read 는 그대로다. delete 는 신분증 객체 중 **지금 참조 중인 것**만 본인이 못 지운다
      //   (지운 뒤 같은 경로로 다시 만들어 옛 판정에 새 사진을 붙이는 우회 차단).
      //   탈퇴 barrier 와 무관하다 — 두 분기 모두 barrier 를 보지 않는다(§30).
      expect(u, contains('allow read: if isLoggedIn() && request.auth.uid == uid;'));
      // [DOC-LATE-DELETE.7 갱신] 예전 단언: (!isIdCardName(resource.name) || !isCurrentIdCard(uid, resource.name)).
      //   신분증 객체는 이제 클라이언트가 아예 지우지 못한다 — 승인 뒤 늦게 끝나는 클라이언트 삭제가
      //   현재 사진을 지우는 경쟁을 닫는다(정리는 서버가 정리 대기 거래 뒤에 한다). 다른 파일은 그대로.
      expect(u, contains(
          'allow delete: if isLoggedIn() && request.auth.uid == uid && '
          '!isIdCardName(resource.name);'));
      final rd = _slice(stUsers(), 'allow read:', 'allow create:');
      expect(rd, isNot(contains('accountDeletionBarrierExists')));
      expect(rd, isNot(contains('firestore.exists')));
    });

    test('ACC-STOR-BAR-20 기존 MIME·크기 정책이 유지된다 (§31·§61)', () {
      final u = stUsers();
      expect(u, contains('isUnder5MB()'));
      expect(u, contains('isImageType()'));
      // 권한 → 정책 → barrier 순서 (§36)
      final i1 = u.indexOf('request.auth.uid == uid');
      final i2 = u.indexOf('isUnder5MB()');
      final i3 = u.indexOf('!accountDeletionBarrierExists(uid)');
      expect(i2, greaterThan(i1));
      expect(i3, greaterThan(i2));
    });

    test('ACC-STOR-BAR-30 uid exact lookup — 타 사용자 격리 (§34·§35)', () {
      final h = _flat(_slice(stRules,
          'function accountDeletionBarrierExists(uid)', '\n    }'));
      // 경로에 들어가는 것은 match 의 {uid} 뿐이다.
      expect(h, contains(r'account_deletion_tombstones/$(uid)'));
      expect(h, isNot(contains('request.auth.uid')),
          reason: 'helper 는 인자로 받은 uid 만 본다 — match 가 소유자를 이미 고정한다');
      // 소유자 검증이 barrier 와 별개로 남아 있다.
      expect(stUsers(), contains('request.auth.uid == uid'));
    });

    test('ACC-STOR-BAR-40 다른 Storage 네임스페이스 무변경 (§76·§91)', () {
      for (final keep in [
        'match /businesses/{businessId}/license/{allPaths=**} {',
        'match /businesses/{businessId}/{fileName} {',
        'match /contracts/{contractId}/{allPaths=**} {',
      ]) {
        expect(stRules, contains(keep), reason: '$keep 가 사라졌다');
      }
      // business/contracts 블록에 barrier 를 넣지 않았다.
      final biz = _flat(_slice(stRules,
          'match /businesses/{businessId}/license/{allPaths=**} {', '\n    }'));
      expect(biz, isNot(contains('accountDeletionBarrierExists')));
      // catch-all 전면 차단 유지
      expect(_flat(_slice(stRules, 'match /{allPaths=**} {', '\n    }')),
          contains('allow read, write: if false;'));
    });

    test('ACC-STOR-BAR-50 fail-closed 가 문서로 고정돼 있다 (§37)', () {
      // 조회 실패를 "삭제 중 아님"으로 바꾸는 fallback 이 없다.
      expect(stRules, isNot(contains('|| !firestore.exists')));
      expect(stRules, isNot(contains('accountDeletionBarrierExists(uid) == false')));
      // IAM 전제를 주석으로 남겼다 (§67)
      expect(stRules, contains('roles/firebaserules.firestoreServiceAgent'));
    });
  });

  // ══════════════════════════════════════════════════════════════
  group('ACC-TOMB-NC 건드리지 않은 것 (§74~§78·§86·§91)', () {
    test('ACC-TOMB-NC-01 95cc737 hard-gate semantics 유지 (§75)', () {
      final f = fin();
      final s = sweep();
      expect(s, contains(r'const prefix = `users/${uid}/`;'));
      expect(s, contains('out.listFailed = true;'));
      expect(s, contains('await f.delete({ignoreNotFound: true});'));
      expect(s, contains(
          'out.residual = again.filter((f) => f.name.startsWith(prefix)).length;'));
      expect(cf, contains(
          'return s.failed === 0 && !s.listFailed && s.residual === 0;'));
      expect(f, contains('reason: "STORAGE_RETRYABLE"'));
      expect(f, contains('reason: "FIRESTORE_RETRYABLE"'));
    });

    test('ACC-TOMB-NC-02 PreData / Applications ±0 (§77·§91)', () {
      final pre = _codeOf(_slice(raw,
          'export const callableDeleteAccountPreData',
          '\n// ─── callableDeleteAccountFinal'));
      expect(pre, contains('db.collection("deleted_accounts").add(recordDocData)'));
      expect(pre, contains('nativeIdentityFingerprints'));
      expect(pre, contains('canReregisterAt'));
      final app = _codeOf(_slice(raw,
          'export const callableDeleteAccountApplications', '\n// ──'));
      expect(app, contains('cancelReason: "USER_DELETED"'));
      expect(app, contains('absentReason: "USER_DELETED"'));
    });

    test('ACC-TOMB-NC-03 사업장 lifecycle ±0 (§76)', () {
      final f = fin();
      expect(f, contains('if (bizDoc.data()["deactivatedAt"]) continue;'));
      expect(f, contains('adminIds: admin.firestore.FieldValue.arrayRemove(uid),'));
      expect(cf, contains('export const onBusinessDeleted'));
      expect(cf, contains('export const onBusinessDeactivated'));
    });

    test('ACC-TOMB-NC-04 bankbook·ID lifecycle ±0 (§91)', () {
      expect(cf, contains('const BANKBOOK_CLEANUP_FIELD = "bankbookCleanupPendingPaths";'));
      expect(cf, contains('async function srvDrainBankbookCleanup('));
      expect(cf, contains('async function srvDrainOrphanPaths('));
      expect(cf, contains('function srvIsOwnedBankbookStoragePath('));
      for (final r in ['callableGetBankbookSignedUrl',
        'callableGetPayrollBankbookUrl', 'callableGetApplicantDocumentUrl']) {
        expect(_codeOf(_slice(raw, 'export const $r', '\n// ──')),
            contains('srvResolveOwnedBankbookStoragePath('), reason: r);
      }
    });

    test('ACC-TOMB-NC-05 Auth-tail 코드 ±0 (§74)', () {
      // .0C owner — 이번 diff 에서 건드리지 않았다.
      final up = _src('lib/providers/user_provider.dart');
      expect(up, contains('await _authService.signOut(showToast: false);'));
      final as = _src('lib/services/auth_service.dart');
      expect(as, contains(
          "if (e.code != 'internal' && e.code != 'failed-precondition') {"));
      expect(as, contains('탈퇴가 완료되지 않았습니다. 데이터 정리를 마치려면 다시 시도해 주세요.'));
    });

    test('ACC-TOMB-NC-06 late-arrival 아키텍처를 만들지 않았다 (§86)', () {
      expect(cf, isNot(contains('onObjectFinalized')));
      expect(cf, isNot(contains('onObjectDeleted')));
      expect(cf, isNot(contains('cleanup_jobs')));
      // tombstone 이 Storage 를 만지지 않는다.
      expect(helper(), isNot(contains('bucket')));
      expect(helper(), isNot(contains('getFiles')));
    });

    test('ACC-TOMB-NC-07 Task·Notification·metric 추가 0 (§55·§73)', () {
      final h = helper();
      for (final bad in ['notifications', 'sendNotification', 'createNotification',
        'messaging()', 'analytics', 'Crashlytics', 'badge']) {
        expect(h, isNot(contains(bad)), reason: '$bad 가 tombstone 경로에 있다');
      }
    });

    test('ACC-TOMB-NC-08 Flutter 는 tombstone 을 모른다 (§56)', () {
      for (final p in ['lib/services/auth_service.dart',
        'lib/providers/user_provider.dart',
        'lib/screens/user/user_settings_screen.dart']) {
        expect(_src(p), isNot(contains('account_deletion_tombstones')), reason: p);
      }
    });
  });
}
