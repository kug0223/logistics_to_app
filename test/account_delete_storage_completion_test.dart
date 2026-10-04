// [R7-P4.4E.11C] 탈퇴가 끝났다고 말했지만 민감 파일은 남아 있었다
//
// 이전 `callableDeleteAccountFinal` 의 순서는 이랬다.
//
//   users 문서 삭제
//     → Storage `users/{uid}/` sweep  (개별 실패는 console.warn)
//     → Auth 삭제
//     → {success: true}
//
// 그리고 sweep 의 catch 에는 이렇게 적혀 있었다 —
//   "continue — 파일 고아 잔류는 허용, Auth 삭제 우선".
//
// 그 결과 신분증·통장사본·프로필 이미지가 남아도 탈퇴는 성공으로 끝났고,
// 그때 남은 것은 **object 뿐**이었다. 가리키는 포인터도, cleanup 주인
// (`bankbookCleanupPendingPaths`·`idDocumentOrphanPaths`)도, 재시도할 경로도
// user 문서와 함께 사라졌다. 아무도 그 파일의 존재를 모른다.
//
// 게다가 `files.length === 0` 과 "목록 조회 실패"가 구별되지 않았다 —
// 열거가 실패하면 "지울 것이 없다"로 읽혔다. ERROR ≠ ZERO.
//
// 이 파일이 고정하는 것
//   ACC-DEL-0x    Storage 가 0 임을 확인한 뒤에만 identity 를 파괴한다
//   ACC-DEL-1x    실패·미지(unknown)·잔존이 모두 identity 파괴를 막는다
//   ACC-DEL-2x    exact own prefix 만 — queue 경로를 따라가지 않는다
//   ACC-DEL-3x    클라이언트가 미완료를 성공으로 말하지 않는다
//   ACC-DEL-NC-xx 이번 patch 가 건드리지 않은 것
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

const _cfPath = 'functions/src/index.ts';
const _authPath = 'lib/services/auth_service.dart';
const _settingsPath = 'lib/screens/user/user_settings_screen.dart';

void main() {
  final raw = _src(_cfPath);
  final cf = _codeOf(raw);

  /// Final 전체 본문.
  String fin() => _codeOf(_slice(
      raw, 'export const callableDeleteAccountFinal', '\n// ─── callableCheckIdCardAccess'));
  String sweep() => _codeOf(_slice(
      raw, 'async function srvSweepAccountOwnedStorage(', '\n}'));
  String gate() => _codeOf(_slice(
      raw, 'function srvAccountStorageCleared(', '\n}'));
  String client() => _codeOf(_src(_authPath));

  // ══════════════════════════════════════════════════════════════
  group('ACC-DEL-0x Storage 완료가 identity 파괴의 전제다 (§0·§13·§34)', () {
    test('ACC-DEL-01 Final 은 전용 sweep helper 를 쓴다 (§49)', () {
      expect(fin(), contains('const accSweep = await srvSweepAccountOwnedStorage(uid);'));
      // 범용 prefix 삭제기로 확장하지 않았다.
      expect(cf, isNot(contains('srvDeleteAnyPrefix')));
      expect('async function srvSweepAccountOwnedStorage('.allMatches(cf).length, 1);
    });

    test('ACC-DEL-02 Storage 정리가 user 문서 삭제보다 **앞**이다', () {
      final f = fin();
      final sweepAt = f.indexOf('await srvSweepAccountOwnedStorage(uid)');
      final userDelAt = f.indexOf('await userRef.delete()');
      expect(sweepAt, greaterThan(-1));
      expect(userDelAt, greaterThan(sweepAt),
          reason: 'user 문서가 cleanup 주인이다 — 먼저 지우면 주인을 잃는다');
    });

    test('ACC-DEL-03 user 문서 삭제가 Auth 삭제보다 앞이다', () {
      final f = fin();
      expect(f.indexOf('await userRef.delete()'),
          lessThan(f.indexOf('admin.auth().deleteUser(uid)')));
    });

    test('ACC-DEL-04 Storage 실패는 둘 다 막는다 (§28)', () {
      final f = fin();
      final gateAt = f.indexOf('if (!srvAccountStorageCleared(accSweep)) {');
      final userDelAt = f.indexOf('await userRef.delete()');
      final authAt = f.indexOf('admin.auth().deleteUser(uid)');
      expect(gateAt, greaterThan(-1));
      expect(userDelAt, greaterThan(gateAt));
      expect(authAt, greaterThan(gateAt));
      // 게이트가 return 으로 끝난다 — 삼키고 계속 가지 않는다.
      expect(_flat(f), contains(
          'if (!srvAccountStorageCleared(accSweep)) { return { success: false, '
          'partial: true, reason: "STORAGE_RETRYABLE", residual: accSweep.residual, }; }'));
    });

    test('ACC-DEL-05 옛 best-effort 주석·구조가 사라졌다', () {
      final f = _flat(fin());
      expect(f, isNot(contains('Storage file skip')),
          reason: '개별 파일 실패를 warn 으로 삼키던 경로');
      expect(f, isNot(contains('파일 고아 잔류는 허용')),
          reason: '이 주석이 결함을 그대로 말하고 있었다');
      expect(f, isNot(contains(r'bucket.getFiles({prefix: `users/${uid}/`})')),
          reason: 'Final 안에 인라인 sweep 이 남아 있으면 안 된다');
    });
  });

  // ══════════════════════════════════════════════════════════════
  group('ACC-DEL-1x 실패·미지·잔존 판정 (§15·§16·§17·§18)', () {
    test('ACC-DEL-10 목록 조회 실패는 0건이 아니다 — ERROR ≠ ZERO', () {
      final s = sweep();
      expect(s, contains('out.listFailed = true;'));
      expect(s, contains('out.failed++;'));
      // 조회 실패 시 즉시 반환하고, residual 은 -1(알 수 없음)로 남는다.
      expect(_flat(s), contains('residual: -1,'));
      expect(s, isNot(contains('out.residual = 0;')),
          reason: '어디서도 잔존을 0 으로 단정하지 않는다');
    });

    test('ACC-DEL-11 not-found 는 성공 동치다 (§16)', () {
      expect(sweep(), contains('await f.delete({ignoreNotFound: true});'));
    });

    test('ACC-DEL-12 삭제 후 **재열거**로 실제 잔존을 센다 (§17)', () {
      final s = sweep();
      expect('bucket.getFiles({prefix})'.allMatches(_flat(s)).length, 2,
          reason: '첫 열거 + 최종 재열거 두 번이어야 한다');
      expect(_flat(s), contains(
          'out.residual = again.filter((f) => f.name.startsWith(prefix)).length;'));
    });

    test('ACC-DEL-13 게이트는 세 축을 모두 본다', () {
      expect(_flat(gate()), contains(
          'return s.failed === 0 && !s.listFailed && s.residual === 0;'));
      // residual === 0 이므로 -1(미지)은 통과하지 못한다.
      expect(gate(), isNot(contains('s.residual <= 0')));
      expect(gate(), isNot(contains('s.residual !== -1')));
    });

    test('ACC-DEL-14 pagination 을 잘라 쓰지 않는다 (§18)', () {
      final s = sweep();
      // @google-cloud/storage 7.x 의 getFiles 는 autoPaginate 기본 true 다.
      //   그래서 수동 nextPageToken 이 필요 없고, 대신 잘라 쓰지 않는 것이
      //   계약이다 — 주면 일부 페이지만 지우고 성공이라 말한다.
      expect(s, isNot(contains('autoPaginate')));
      expect(s, isNot(contains('maxResults')));
      expect(s, isNot(contains('pageToken')));
      // 설치된 버전이 실제로 그 기본값을 갖는지 함께 고정한다.
      final pkg = _src('functions/node_modules/@google-cloud/storage/package.json');
      expect(RegExp(r'"version":\s*"7\.').hasMatch(pkg), true,
          reason: '메이저가 바뀌면 pagination 기본값을 다시 확인해야 한다');
    });

    test('ACC-DEL-15 집계 필드가 진단에 필요한 축을 갖는다 (§50)', () {
      final t = _flat(_codeOf(_slice(raw, 'type SrvAccountStorageSweep = {', '\n};')));
      for (final k in ['listed:', 'deleted:', 'failed:', 'residual:', 'listFailed:']) {
        expect(t, contains(k), reason: '$k 가 없으면 실패 원인을 구별할 수 없다');
      }
    });
  });

  // ══════════════════════════════════════════════════════════════
  group('ACC-DEL-2x exact own prefix 만 (§9·§36·§39·§40)', () {
    test('ACC-DEL-20 권위는 users/{uid}/ 하나다', () {
      final s = sweep();
      expect(s, contains(r'const prefix = `users/${uid}/`;'));
      // 구분자까지 포함한 접두다 — users/abc 가 users/abc2 를 잡지 않는다.
      expect(s, isNot(contains(r'`users/${uid}`')));
    });

    test('ACC-DEL-21 안전하지 않은 uid 로는 아무것도 지우지 않는다', () {
      final s = _flat(sweep());
      expect(s, contains('uid.includes("/") || uid.includes("..")'));
      expect(s, contains('console.error("[accountStorageSweep] uid 형식이 안전하지 않다 — 삭제 0");'));
    });

    test('ACC-DEL-22 목록 결과도 접두를 다시 확인한다 (§39)', () {
      expect(_flat(sweep()), contains(
          'if (!f.name.startsWith(prefix)) { out.failed++;'),
          reason: '목록 API 를 믿고 지우면 cross-user 삭제가 가능해진다');
    });

    test('ACC-DEL-23 cleanup queue 경로를 따라가지 않는다 (§9·§36)', () {
      final f = fin();
      final s = sweep();
      for (final q in ['bankbookCleanupPendingPaths', 'idDocumentOrphanPaths',
        'BANKBOOK_CLEANUP_FIELD']) {
        expect(f, isNot(contains(q)), reason: 'Final 이 $q 를 읽으면 안 된다');
        expect(s, isNot(contains(q)), reason: 'sweep 이 $q 를 읽으면 안 된다');
      }
    });

    test('ACC-DEL-24 business/contracts 네임스페이스를 건드리지 않는다 (§6·§7·§40)', () {
      final s = sweep();
      expect(s, isNot(contains('businesses/')));
      expect(s, isNot(contains('contracts/')));
      // Final 의 사업장 처리는 Firestore 필드 수준뿐이다 — Storage 삭제 0.
      final f = fin();
      expect(f, isNot(contains('businessLicenseImageUrl')));
      expect(f, isNot(contains('businessImageUrls')));
      expect('getFiles('.allMatches(f).length, 0,
          reason: 'Final 안에서 직접 열거하지 않는다 — helper 하나로 수렴');
    });
  });

  // ══════════════════════════════════════════════════════════════
  group('ACC-DEL-3x 클라이언트 계약 (§29·§33·§69·§71)', () {
    test('ACC-DEL-30 클라이언트가 Final 응답을 **읽는다**', () {
      final c = _flat(client());
      expect(c, contains(
          'final finalResult = await deleteFinalCallable.call<Map<String, dynamic>>({});'));
      expect(c, contains("if (finalData['success'] != true) {"));
      // 예전처럼 응답을 버리지 않는다.
      expect(c, isNot(contains(
          'await deleteFinalCallable.call<Map<String, dynamic>>({}); } on FirebaseFunctionsException')),
          reason: '응답을 읽지 않으면 미완료가 성공으로 보인다');
    });

    test('ACC-DEL-31 미완료면 signOut·로컬정리·이동을 하지 않는다 (§33·§71)', () {
      final c = client();
      // 미완료 분기는 **return** 으로 끝난다 — 아래 signOut 에 도달하지 않는다.
      final branchAt = c.indexOf("if (finalData['success'] != true) {");
      final signOutAt = c.indexOf('await _auth.signOut();\n\n      return null;');
      expect(branchAt, greaterThan(-1));
      expect(signOutAt, greaterThan(branchAt),
          reason: '성공 signOut 이 미완료 분기보다 뒤에 있어야 한다');
      final branch = c.substring(branchAt, c.indexOf('}', branchAt));
      expect(branch, contains('return '));
      expect(branch, isNot(contains('signOut')));
      expect(branch, isNot(contains('clear')));
    });

    test('ACC-DEL-32 안내 문구가 완료라고 말하지 않는다 (§69)', () {
      final c = client();
      expect(c, contains('탈퇴가 완료되지 않았습니다. 데이터 정리를 마치려면 다시 시도해 주세요.'));
      for (final bad in ['탈퇴 완료', '로그아웃 완료', '계정 삭제 성공']) {
        expect(c, isNot(contains("'$bad'")), reason: '$bad 문구 금지');
      }
    });

    test('ACC-DEL-33 화면은 오류를 띄우고 그 자리에 머문다', () {
      final s = _flat(_codeOf(_src(_settingsPath)));
      expect(s, contains(
          'final err = await AuthService().deleteAccountWithPassword(password); '
          'if (!mounted) return; if (err != null) { ToastHelper.showError(err); } '
          'else { await context.read<UserProvider>().signOut(); }'),
          reason: 'err != null 에서 signOut·이동이 없어야 재시도가 가능하다');
    });

    test('ACC-DEL-34 성공 응답에서만 세션을 정리한다 (§33)', () {
      final c = client();
      // 성공 경로는 그대로 유지된다.
      expect(c, contains('await _auth.signOut();'));
      expect(c, contains('return null; // 성공'));
    });
  });

  // ══════════════════════════════════════════════════════════════
  group('ACC-DEL-4x 재시도 멱등성 (§42·§43·§44·§45·§48)', () {
    test('ACC-DEL-40 user 문서 삭제 실패는 Auth 를 막는다 (§45)', () {
      final f = _flat(fin());
      expect(f, contains('if (userDocFail) { return {success: false, partial: true, '
          'reason: "FIRESTORE_RETRYABLE"}; }'));
      final fr = fin();
      expect(fr.indexOf('reason: "FIRESTORE_RETRYABLE"'),
          lessThan(fr.indexOf('admin.auth().deleteUser(uid)')));
    });

    test('ACC-DEL-41 Auth not-found 는 성공 동치다 (§48)', () {
      final f = fin();
      expect(f, contains('if (errCode === "auth/user-not-found") {'));
      expect(f, contains('return {success: true};'));
    });

    test('ACC-DEL-42 user 문서가 이미 없어도 진행된다 (§47 identity split)', () {
      final f = fin();
      // role 을 deleted_accounts 에서 되살리는 기존 경로가 유지된다.
      expect(f, contains('db.collection("deleted_accounts")'));
      expect(f, contains('if (userSnap.exists) {'));
      // 그리고 sweep 은 user 문서 존재와 무관하게 prefix 로만 동작한다.
      expect(sweep(), isNot(contains('userSnap')));
      expect(sweep(), isNot(contains('collection("users").doc')));
    });

    test('ACC-DEL-43 사업장 side effect 멱등성이 유지된다 (§41·§42)', () {
      final f = fin();
      expect(f, contains('if (bizDoc.data()["deactivatedAt"]) continue;'));
      expect(f, contains('adminIds: admin.firestore.FieldValue.arrayRemove(uid),'));
      // 사업장 처리가 Storage 게이트 **뒤**다 — 미완료 호출에서 반복되지 않는다.
      expect(f.indexOf('if (!srvAccountStorageCleared(accSweep)) {'),
          lessThan(f.indexOf('array-contains')));
    });

    test('ACC-DEL-44 재인증 최근성·하드블록 전제가 그대로다', () {
      // [R7-P4.4E.11C.0C.0a 갱신] 이 세 전제는 Final 안에 인라인으로
      //   있었다. PreData 가 BEGIN owner 가 되면서 **같은 정책을 공유**해야
      //   했고(복제하면 한쪽만 고쳐질 때 갈라진다), 공용 helper 로 옮겼다.
      //   전제가 사라진 것이 아니라 한 곳으로 모였다 — 그래서 helper 에서
      //   확인하고, Final·PreData 가 둘 다 그것을 부르는지 본다.
      final helper = _codeOf(_slice(raw,
          'async function srvAssertAccountDeletionAllowed(', '\n}'));
      for (final keep in [
        '"재인증 후 10분이 초과되었습니다. 다시 시도해주세요."',
        '서브관리자로 등록된 사업장',
        '미서명 계약서',
      ]) {
        expect(helper, contains(keep), reason: '$keep 전제가 바뀌면 안 된다');
      }
      expect(fin(), contains('await srvAssertAccountDeletionAllowed('));
      final pre = _codeOf(_slice(raw,
          'export const callableDeleteAccountPreData', '\n);'));
      expect(pre, contains('await srvAssertAccountDeletionAllowed('),
          reason: 'BEGIN 도 같은 전제를 통과해야 한다');
    });
  });

  // ══════════════════════════════════════════════════════════════
  group('ACC-DEL-5x 로그 privacy (§51)', () {
    test('ACC-DEL-50 sweep 로그에 전체 경로·전체 uid 가 없다', () {
      final s = sweep();
      // scope 라벨은 마스킹된다.
      expect(s, contains(r'const scope = `users/${uid.slice(0, 4)}…/`;'));
      // 오류는 code 만 찍는다 — GCS 오류 메시지에는 전체 경로가 들어 있다.
      expect(s, isNot(contains(r'— ${e}')),
          reason: 'GCS 오류 문자열을 그대로 찍으면 전체 object 경로가 로그로 샌다');
      expect(s, isNot(contains(r'${f.name}')));
      expect(s, isNot(contains(r'${prefix}')));
      expect(s, contains(r'code=${(e as {code?: unknown})?.code ?? "unknown"}'));
    });

    test('ACC-DEL-51 Final 의 sweep 요약도 수치만 남긴다', () {
      final f = fin();
      expect(f, contains(r'`[deleteAccountFinal] storage listed=${accSweep.listed} `'));
      expect(f, isNot(contains('accSweep.paths')));
    });
  });

  // ══════════════════════════════════════════════════════════════
  group('ACC-DEL-NC 이번 patch 가 건드리지 않은 것 (§75·§76·§82)', () {
    test('ACC-DEL-NC-01 bankbook lifecycle semantics ±0', () {
      expect(cf, contains('const BANKBOOK_CLEANUP_FIELD = "bankbookCleanupPendingPaths";'));
      expect(cf, contains('const BANKBOOK_CLEANUP_DRAIN_CAP = 20;'));
      expect(cf, contains('async function srvResetBankStateWithCleanupOwner('));
      expect(cf, contains('async function srvDrainBankbookCleanup('));
    });

    test('ACC-DEL-NC-02 bankbook·ID reader 네임스페이스 ±0', () {
      for (final f in ['callableGetBankbookSignedUrl', 'callableGetPayrollBankbookUrl',
        'callableGetApplicantDocumentUrl']) {
        final body = _codeOf(_slice(raw, 'export const $f', '\n// ──'));
        expect(body, contains('srvResolveOwnedBankbookStoragePath('), reason: f);
      }
      expect(cf, contains('function srvIsOwnedStoragePath('));
      expect(cf, contains('function srvIsOwnedBankbookStoragePath('));
    });

    test('ACC-DEL-NC-03 ID 문서 lifecycle ±0', () {
      expect(cf, contains('async function srvDrainOrphanPaths('));
      expect(cf, contains('function srvIsOwnedIdDocumentStoragePath('));
      expect(cf, contains('export const callableDeleteIdCard'));
    });

    test('ACC-DEL-NC-04 사업장 삭제·비활성 lifecycle ±0', () {
      expect(cf, contains('export const onBusinessDeleted'));
      expect(cf, contains('export const onBusinessDeactivated'));
      expect(cf, contains('function srvBusinessCleanupVerdict('));
    });

    test('ACC-DEL-NC-05 global scheduler·sweeper 추가 0 (§53)', () {
      expect(cf, isNot(contains('cleanup_jobs')));
      expect(sweep(), isNot(contains('onSchedule')));
      // sweep 은 계정 하나의 prefix 만 본다 — 버킷 전역 스캔이 아니다.
      expect(sweep(), isNot(contains('getFiles()')));
    });

    test('ACC-DEL-NC-06 PreData/Applications 정책 ±0 (§67)', () {
      final pre = _codeOf(_slice(raw,
          'export const callableDeleteAccountPreData', '\n// ─── callableDeleteAccountFinal'));
      expect(pre, contains('db.collection("deleted_accounts").add(recordDocData)'));
      expect(pre, contains('nativeIdentityFingerprints'));
      expect(pre, contains('foreignIdFingerprints'));
      expect(pre, contains('canReregisterAt'));
      final app = _codeOf(_slice(raw,
          'export const callableDeleteAccountApplications', '\n// ──'));
      expect(app, contains('cancelReason: "USER_DELETED"'));
      expect(app, contains('absentReason: "USER_DELETED"'));
    });

    test('ACC-DEL-NC-07 Firestore 역사 기록 보존 정책 ±0 (§66)', () {
      final f = fin();
      // 근태·급여·계약을 삭제하지 않는다.
      for (final col in ['"attendance"', '"employment_contracts"', '"payrolls"']) {
        expect(f, isNot(contains('db.collection($col).doc')),
            reason: 'Final 이 $col 을 지우면 안 된다');
      }
      expect(f, isNot(contains('deleteByBusinessId')));
    });
  });
}
