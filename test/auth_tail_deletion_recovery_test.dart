// [R7-P4.4E.11C.0C] 삭제가 마지막 Auth 단계에서 멈추면 끝낼 길이 없었다
//
// 삭제 pipeline 의 마지막은 Admin SDK 의 Auth 삭제다. 그 앞은 전부
// fail-closed 로 닫혀 있다. 그런데 Auth 삭제만 실패하면 이 상태가 남는다.
//
//   Auth identity = 존재
//   users/{uid}   = 없음
//   tombstone     = 존재
//
// 그리고 클라이언트는 user 문서가 없으면 **조건 없이 signOut** 했다.
// 다시 로그인해도 같은 자리로 돌아온다.
//
//   login → user doc 없음 → signOut → Login → login → …
//
// 삭제는 미완료인데 삭제를 끝낼 경로에 도달할 수 없었다.
//
// 고친 방식은 최소다. 새 삭제 구현을 만들지 않았다.
//
//   서버: self-only 읽기 전용 callable 하나로 tombstone 존재만 알려준다
//         (그 컬렉션의 클라이언트 read 는 여전히 차단 — rules ±0).
//   클라이언트: signOut 전에 그것을 묻고, 재개 대상이면 세션을 유지한 채
//         **같은 pipeline**(재인증 → PreData → Applications → Final)을
//         재개하는 전용 화면으로 간다.
//
// UNKNOWN 을 "삭제 아님"으로 접지 않는다. 모르면 세션을 유지한다.
//
// 고정하는 것
//   ATR-STATE-*  부분 상태 S1~S6 bootstrap 판정
//   ATR-ROUTE-*  재개 화면이 일반 화면보다 앞
//   ATR-LOGIN-*  로그인 루프 회귀
//   ATR-PIPE-*   같은 pipeline 재개
//   ATR-SRV-*    서버가 S3 에서 실제로 끝낼 수 있는가
//   ATR-SEC-*    self-only · 문서 재생성 0
//   ATR-TOMB-*   tombstone 보존
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
  final serverCode = _codeOf(raw);
  final recoveryFn = _fn(raw, 'callableGetAccountDeletionRecoveryState');
  final finalFn = _fn(raw, 'callableDeleteAccountFinal');
  final assertFn = _helper(raw, 'srvAssertAccountDeletionAllowed');
  final identityKeys = _helper(raw, 'srvResolveDeletionIdentityKeys');
  final main = _src('lib/main.dart');
  final provider = _src('lib/providers/user_provider.dart');
  final authService = _src('lib/services/auth_service.dart');
  // [주의] Dart 소스 pin 중 **코드 모양**을 보는 것은 주석을 제거하고 본다 —
  //   주석 한 줄이 끼면 flatten 결과가 달라져 셀이 깨진다.
  final authCode = _codeOf(authService);
  final rules = _src('firestore.rules');

  group('ATR-STATE — 부분 상태 bootstrap 판정', () {
    test('ATR-STATE-01 정상 계정은 재개 상태가 아니다 (R1·S1)', () {
      // 정상 경로에서 이전 재개 상태를 남겨 두지 않는다.
      expect(_flat(provider), contains(
          '_deletionRecovery = DeletionRecoveryState.none;'));
      expect(_flat(provider), contains(
          'bool get needsDeletionRecovery => '
          '_deletionRecovery != DeletionRecoveryState.none;'));
    });

    test('ATR-STATE-02 deleting 계정은 일반 화면으로 가지 않는다 (R2·S2·§24)', () {
      expect(_flat(provider), contains(
          r"if (_currentUser?.accountStatus == 'deleting') { "
          '_currentUser = null; '
          '_deletionRecovery = DeletionRecoveryState.required;'));
      // _currentUser 를 비우므로 role 라우팅 자체가 성립하지 않는다.
      expect(_at(provider, r"_currentUser?.accountStatus == 'deleting'"),
          lessThan(_at(provider, 'if (_currentUser != null) {')));
    });

    test('ATR-STATE-03 user 문서 없음 — 먼저 서버에 묻는다 (R3·S3·§15)', () {
      // 조건 없는 signOut 이 사라졌다.
      expect(_flat(provider), contains(
          'final recovery = await _authService.getDeletionRecoveryState(); '
          'if (_disposed || _loadGeneration != gen) return; '
          'if (recovery != DeletionRecoveryState.none) {'));
      // 그 질의가 signOut 보다 앞이다.
      final seg = provider.substring(_at(provider, 'if (_currentUser == null) {'));
      expect(_at(seg, 'getDeletionRecoveryState()'),
          lessThan(_at(seg, '_authService.signOut(showToast: false)')));
    });

    test('ATR-STATE-04 tombstone 없으면 기존 동작 그대로 (R4·§28)', () {
      // none 일 때만 기존 signOut 경로로 간다.
      expect(_flat(provider), contains(
          '_deletionRecovery = recovery; _isLoading = false; notifyListeners(); return; } '
          'await _authService.signOut(showToast: false);'));
    });

    test('ATR-STATE-05 UNKNOWN 을 "삭제 아님"으로 접지 않는다 (R6·§27·§51)', () {
      // 서버 판정 실패는 unknown 이고, none 이 아니므로 세션이 유지된다.
      expect(_flat(authService), contains(
          'return DeletionRecoveryState.unknown;'));
      expect(_flat(authService), contains(
          "data['deletionInProgress'] == true ? DeletionRecoveryState.required "
          ': DeletionRecoveryState.none;'));
      expect(authService, contains('enum DeletionRecoveryState {'));
      // 세 값이 전부다 — 모름이 별도 상태다.
      expect(_count(authService, 'DeletionRecoveryState.unknown'), greaterThanOrEqualTo(1));
    });

    test('ATR-STATE-06 로딩 중에는 성급히 라우팅하지 않는다 (R5·§26)', () {
      // 초기 인증 확인 전에는 스플래시가 먼저다.
      expect(_at(main, 'return const SplashLoadingScreen();'),
          lessThan(_at(main, 'if (userProvider.needsDeletionRecovery) {')));
      // 그리고 재개 질의 중에는 isLoading 이 유지된다(응답 후에만 false).
      expect(_flat(provider), contains(
          '_deletionRecovery = recovery; _isLoading = false;'));
    });
  });

  group('ATR-ROUTE — 재개 화면이 일반 화면보다 앞 (§14·§36)', () {
    test('ATR-ROUTE-01 분기 순서가 고정됐다', () {
      final recoveryAt = _at(main, 'if (userProvider.needsDeletionRecovery) {');
      expect(recoveryAt, lessThan(_at(main, '!userProvider.isLoggedIn && !userProvider.isLoading')));
      expect(recoveryAt, lessThan(_at(main, 'if (_isOnboardingCompleted == false')));
      expect(recoveryAt, lessThan(_at(main, 'switch (user.role) {')));
      expect(main, contains('return const _DeletionRecoveryScreen();'));
    });

    test('ATR-ROUTE-02 재개 화면에서 일반 화면으로 가는 길이 없다', () {
      final screen = main.substring(
          _at(main, 'class _DeletionRecoveryScreen extends StatefulWidget'),
          _at(main, 'class _HomeRegionRecoveryScreen extends StatefulWidget'));
      expect(screen, isNot(contains('Navigator.push')));
      expect(screen, isNot(contains('UserRootScreen')));
      expect(screen, isNot(contains('BusinessAdminShell')));
      // 회원가입 유도도 하지 않는다(§39).
      expect(screen, isNot(contains('RegisterScreen')));
      // 완료로 오표시하지 않는다.
      expect(screen, isNot(contains('탈퇴 완료')));
      expect(screen, contains('계정 삭제를 마무리하고 있어요'));
    });

    test('ATR-ROUTE-03 로그아웃하면 재개 상태도 끝난다', () {
      final seg = provider.substring(_at(provider, 'Future<void> signOut() async {'));
      expect(_flat(seg), contains('_deletionRecovery = DeletionRecoveryState.none;'));
    });
  });

  group('ATR-LOGIN — 로그인 루프 회귀 (§46)', () {
    test('ATR-LOGIN-01 로그인 경로도 signOut 전에 묻는다', () {
      final seg = authCode.substring(
          _at(authCode, 'final recovery = await getDeletionRecoveryState();'));
      expect(_at(seg, 'DeletionRecoveryRequiredException()'),
          lessThan(_at(seg, '_auth.signOut();')),
          reason: '재개 판정이 signOut 보다 앞이어야 한다');
    });

    test('ATR-LOGIN-02 세션을 유지한 채 전용 예외를 던진다', () {
      expect(authService, contains('class DeletionRecoveryRequiredException implements Exception'));
      expect(_flat(authCode), contains(
          'if (recovery != DeletionRecoveryState.none) { '
          'throw const DeletionRecoveryRequiredException(); }'));
      // 그 분기에는 signOut 이 없다.
      final branch = authCode.substring(
          _at(authCode, 'final recovery = await getDeletionRecoveryState();'),
          _at(authCode, 'throw const DeletionRecoveryRequiredException();'));
      expect(branch, isNot(contains('signOut')));
    });

    test('ATR-LOGIN-03 provider 가 그 예외를 재개 상태로 옮긴다', () {
      expect(_flat(provider), contains(
          'if (e is DeletionRecoveryRequiredException) { '
          '_deletionRecovery = DeletionRecoveryState.required;'));
    });
  });

  group('ATR-PIPE — 같은 pipeline 재개 (§10·§11·§51)', () {
    test('ATR-PIPE-01 CTA 가 일반 탈퇴와 같은 함수를 부른다', () {
      final screen = main.substring(
          _at(main, 'class _DeletionRecoveryScreenState'),
          _at(main, 'class _HomeRegionRecoveryScreen extends StatefulWidget'));
      expect(_flat(screen), contains(
          'final err = await AuthService().deleteAccountWithPassword(pw);'));
      // 별도 삭제 구현을 만들지 않았다.
      expect(screen, isNot(contains('callableDeleteAccountFinal')));
      expect(screen, isNot(contains('callableDeleteAccountPreData')));
    });

    test('ATR-PIPE-02 Final-only shortcut 이 없다 (§11)', () {
      // 같은 함수가 세 단계를 순서대로 지난다.
      final del = authService.substring(
          _at(authService, 'Future<String?> deleteAccountWithPassword(String password) async {'));
      expect(_at(del, 'reauthenticateWithCredential'),
          lessThan(_at(del, 'callableDeleteAccountPreData')));
      expect(_at(del, 'callableDeleteAccountPreData'),
          lessThan(_at(del, 'callableDeleteAccountApplications')));
      expect(_at(del, 'callableDeleteAccountApplications'),
          lessThan(_at(del, 'callableDeleteAccountFinal')));
    });

    test('ATR-PIPE-03 서버가 명시적으로 성공해야 완료다 (§51)', () {
      final screen = main.substring(
          _at(main, 'class _DeletionRecoveryScreenState'),
          _at(main, 'class _HomeRegionRecoveryScreen extends StatefulWidget'));
      expect(_flat(screen), contains('if (err == null) {'));
      // 실패면 화면을 유지하고 사유를 보여 준다 — 로그아웃하지 않는다.
      expect(_flat(screen), contains('_busy = false; _message = err;'));
      // 서버 쪽도 partial 을 success 로 바꾸지 않는다.
      expect(_flat(authService), contains(
          r"if (finalData['success'] != true) {"));
    });
  });

  group('ATR-SRV — 서버가 S3 에서 끝낼 수 있는가 (§47)', () {
    test('ATR-SRV-01 Final 이 user 문서 없이도 돈다', () {
      // user 문서 삭제는 존재할 때만.
      expect(_flat(finalFn), contains(
          'if (userSnap.exists) { let userDocFail = false;'));
      // role 은 deleted_accounts 에서 복원한다.
      expect(_flat(finalFn), contains('if (!userSnap.exists) {'));
      expect(_flat(finalFn), contains(
          r'.collection("deleted_accounts") .where("uid", "==", uid)'));
      // [§29·§32] 사업장 정리는 복원된 **role** 로 분기한다 — user 문서
      //   존재 여부로 건너뛰지 않는다. 그러지 않으면 재시도에서 사업장
      //   cleanup 재검증이 사라진다.
      expect(_flat(finalFn), contains(
          'let bizCleanupFailed = false; '
          r'if (role === "BUSINESS_ADMIN" || role === "SUPER_ADMIN") {'));
    });

    test('ATR-SRV-02 precondition 이 user 문서를 요구하지 않는다', () {
      expect(_flat(assertFn), contains(
          r'(userDocForBlock.data()?.subAdminBusinessIds ?? []) as string[]'));
      // role 은 토큰 claim 이다.
      expect(_flat(assertFn), contains(
          r'const role = (token["role"] as string) || "";'));
    });

    test('ATR-SRV-03 identity key 는 deleted_accounts 로 복원되고, 못 하면 막는다', () {
      expect(_flat(identityKeys), contains(
          r'const recSnap = await db.collection("deleted_accounts") '
          r'.where("uid", "==", uid).limit(1).get();'));
      final cleared = _helper(raw, 'srvDeletionIdentityCleared');
      expect(_flat(cleared), contains('!r.identityUnresolved'));
      // 그 gate 가 user 문서 삭제보다 앞이다 — 그래서 S3 에 도달한 계정은
      //   이미 identity key 복원이 가능했다는 뜻이다.
      expect(_at(finalFn, 'srvDeletionIdentityCleared(identityResidual)'),
          lessThan(_at(finalFn, 'userRef.delete()')));
    });

    test('ATR-SRV-04 cleanup ordering 을 약화하지 않았다 (§33)', () {
      final order = [
        'srvAssertAccountDeletionAllowed(',
        'srvEnsureAccountDeletionTombstone(uid)',
        'srvDeletionDomainCleared(domainResidual)',
        'srvAccountStorageCleared(accSweep)',
        'if (bizCleanupFailed) {',
        'srvDeletionPersonalCleared(personalResidual)',
        'srvDeletionIdentityCleared(identityResidual)',
        'userRef.delete()',
        'admin.auth().deleteUser(uid)',
      ];
      for (var i = 1; i < order.length; i++) {
        expect(_at(finalFn, order[i - 1]), lessThan(_at(finalFn, order[i])),
            reason: '${order[i - 1]} 가 ${order[i]} 보다 앞이어야 한다');
      }
    });

    test('ATR-SRV-05 user 문서 삭제 실패면 Auth 를 건드리지 않는다 (§20)', () {
      expect(_flat(finalFn), contains(
          'if (userDocFail) { return {success: false, partial: true, '
          'reason: "FIRESTORE_RETRYABLE"}; }'));
      expect(_at(finalFn, 'if (userDocFail) {'),
          lessThan(_at(finalFn, 'admin.auth().deleteUser(uid)')));
    });

    test('ATR-SRV-06 Auth 오류 분류 (§19·§23)', () {
      expect(_flat(finalFn), contains(
          r'if (errCode === "auth/user-not-found") {'));
      // not-found 는 성공 동치, 그 외는 그대로 전달한다 — generic success 금지.
      expect(_flat(finalFn), contains('throw authErr;'));
      expect(_at(finalFn, 'admin.auth().deleteUser(uid)'),
          lessThan(_at(finalFn, 'return {success: true};')));
    });
  });

  group('ATR-SEC — self-only · 재생성 0 (§48·§49)', () {
    test('ATR-SEC-01 재개 상태 질의는 self-only 다', () {
      expect(_flat(recoveryFn), contains('const uid = request.auth.uid;'));
      // 입력 uid 를 받지 않는다 — 타 계정을 물을 방법이 없다.
      expect(recoveryFn, isNot(contains('request.data')));
      expect(recoveryFn, isNot(contains('targetUid')));
      expect(recoveryFn, isNot(contains('isSuperAdmin')));
    });

    test('ATR-SEC-02 rules 를 넓히지 않았다 (§17)', () {
      // tombstone 컬렉션의 클라이언트 접근은 **네 동작 모두 차단** 그대로다.
      expect(_flat(rules), contains(
          'match /account_deletion_tombstones/{uid} { '
          'allow read: if false; allow create: if false; '
          'allow update: if false; allow delete: if false; }'));
      // 클라이언트는 그 컬렉션을 직접 읽지 않는다.
      expect(_src('lib/services/auth_service.dart'),
          isNot(contains('account_deletion_tombstones')));
      expect(_src('lib/main.dart'),
          isNot(contains('account_deletion_tombstones')));
    });

    test('ATR-SEC-03 user 문서를 되살리지 않는다 (§49)', () {
      expect(recoveryFn, isNot(contains('.set(')));
      expect(recoveryFn, isNot(contains('.update(')));
      final screen = main.substring(
          _at(main, 'class _DeletionRecoveryScreenState'),
          _at(main, 'class _HomeRegionRecoveryScreen extends StatefulWidget'));
      expect(screen, isNot(contains("collection('users')")));
    });
  });

  group('ATR-TOMB — tombstone 보존 (§34·§50)', () {
    test('ATR-TOMB-01 재개 경로가 tombstone 을 지우지 않는다', () {
      expect(recoveryFn, isNot(contains('delete()')));
      // 삭제 pipeline 어디에도 tombstone 삭제가 없다.
      expect(serverCode, isNot(contains(
          'ACCOUNT_DELETION_TOMBSTONE_COL).doc(uid).delete()')));
    });

    test('ATR-TOMB-02 tombstone 에 새 필드를 만들지 않았다 (§50)', () {
      final freeze = _helper(raw, 'srvEnsureAccountDeletionTombstone');
      expect(_flat(freeze), contains(
          'tx.set(tombRef, { barrierAt: admin.firestore.FieldValue.serverTimestamp(), '
          'schemaVersion: 1, });'));
      for (final bad in ['phase:', 'retryCount', 'lastError']) {
        expect(freeze, isNot(contains(bad)));
      }
      // 재개 질의도 존재 여부만 본다.
      expect(_flat(recoveryFn), contains('deletionInProgress: tombSnap.exists,'));
    });
  });
}
