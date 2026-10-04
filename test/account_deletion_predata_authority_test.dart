// [R7-P4.4E.11C.0C.0a.4] PreData 가 실패해도 "탈퇴 완료"라고 말했다
//
// PreData 는 8개 cleanup 을 `Promise.allSettled` 로 돌린 뒤
// `{success: true, failedOps}` 를 반환한다. 그리고 클라이언트는 그 failedOps 를
// `debugPrint` 만 한다. 즉 **실패해도 아무도 멈추지 않았다.**
//
// 더 나쁜 것이 있었다. identity sentinel 삭제 두 건은 allSettled 밖의 inner
// try 라서 `failedOps` 에조차 들어가지 않았다.
//
//   nativeIdentityFingerprints/{ciHash}_{role}
//   foreignIdFingerprints/{fingerprint}_{role}
//
// 이것이 남으면 그 사람의 CI(또는 외국인등록번호)가 영원히 점유된다 —
// 잔류물 문제가 아니라 **실제 사람이 다시 가입할 수 없게 되는** 문제다.
// 그리고 Auth 가 사라진 뒤에는 되돌릴 주인이 없다.
//
// 그래서 이 Phase 가 바꾸는 것은 PreData 를 더 엄격하게 만드는 것이 아니다.
// **Final 이 같은 truth 를 독립적으로 보증하게** 만드는 것이다.
//
//   PreData success  ≠  account deletion success
//   Final success    =  deletion completion
//
// 이 파일이 고정하는 것
//   DEL-PRE-0x    Final 이 PreData 소관 대상을 직접 정리한다
//   DEL-PRE-1x    실패 주입 → identity 보존
//   DEL-PRE-2x    direct Final / 보존 대상 불변
//   DEL-PRE-3x    identity sentinel (이번에 발견된 MUST_DELETE)
//   DEL-PRE-4x    술어 공유 (PreData ↔ Final drift 금지)
//   DEL-PRE-5x    freeze 이후 재생성 writer gate
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

String _fnRaw(String raw, String name) {
  final a = raw.indexOf('export const $name');
  if (a < 0) throw StateError('$name 을 찾지 못함');
  final rel = raw.substring(a).indexOf('\n);');
  if (rel < 0) throw StateError('$name 의 끝을 찾지 못함');
  return raw.substring(a, a + rel);
}

String _fn(String raw, String name) => _codeOf(_fnRaw(raw, name));

/// 최상위 helper 본문 — 선언부터 컬럼 0 의 `}` 까지. 고정폭 창을 쓰지 않는다.
String _helper(String raw, String name) {
  final a = raw.indexOf('function $name(');
  if (a < 0) throw StateError('$name 을 찾지 못함');
  final rel = raw.substring(a).indexOf('\n}');
  if (rel < 0) throw StateError('$name 의 끝을 찾지 못함');
  return _codeOf(raw.substring(a, a + rel));
}

int _at(String s, String needle) {
  final i = s.indexOf(needle);
  if (i < 0) throw StateError('경계를 찾지 못함: $needle');
  return i;
}

String _between(String s, String from, String to) {
  final a = _at(s, from);
  final b = s.indexOf(to, a);
  if (b < 0) throw StateError('끝 경계를 찾지 못함: $to');
  return s.substring(a, b);
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

void main() {
  final raw = _src('functions/src/index.ts');
  final fn = _fn(raw, 'callableDeleteAccountFinal');
  final preData = _fn(raw, 'callableDeleteAccountPreData');
  final targets = _helper(raw, 'srvDeletionOwnedQueryTargets');
  final cleanup = _helper(raw, 'srvCleanupDeletionOwnedIdentityState');
  final residual = _helper(raw, 'srvCountDeletionIdentityResidual');
  final cleared = _helper(raw, 'srvDeletionIdentityCleared');
  final resolve = _helper(raw, 'srvResolveDeletionIdentityKeys');
  final sentinelIds = _helper(raw, 'srvDeletionSentinelIds');

  group('DEL-PRE-0x — Final 이 PreData 소관을 직접 정리한다', () {
    test('DEL-PRE-01 idCardAccessRequests 두 방향 모두 삭제 대상이다', () {
      // 요청자 방향과 수신자 방향 둘 다 — 한쪽만 지우면 반쪽이다.
      final t = _flat(targets);
      expect(t, contains(
          '{col: "idCardAccessRequests", field: "targetUserId", patch: null}'));
      expect(t, contains(
          '{col: "idCardAccessRequests", field: "requesterId", patch: null}'));
      // 그리고 Final 이 그 목록을 돈다.
      expect(fn, contains('srvCleanupDeletionOwnedIdentityState('));
    });

    test('DEL-PRE-02 taxIdentities 문서를 Final 이 삭제한다', () {
      expect(_flat(cleanup),
          contains('collection(TAX_ID_COL).doc(uid).delete()'));
      expect(_flat(residual),
          contains('collection(TAX_ID_COL).doc(uid).get()'));
      expect(cleared, contains('r.taxIdentity === 0'));
    });

    test('DEL-PRE-03 member_invitations 삭제 대상과 보존 대상을 구분한다', () {
      final t = _flat(targets);
      // 나에게 온 초대 = 삭제 (targetName·targetPhone 보유)
      expect(t, contains(
          '{col: "member_invitations", field: "targetUid", patch: null}'));
      // 내가 보낸 초대 = 보존 + 발신자 익명화 (§21 blanket delete 금지)
      expect(t, contains('field: "invitedBy"'));
      expect(t, contains('invitedByName: "탈퇴한 회원"'));
    });

    test('DEL-PRE-04 Final 은 PreData 의 결과를 읽지 않는다', () {
      // PreData 가 실패했는지 성공했는지 Final 은 알 필요가 없다 —
      // 같은 목록을 다시 돌고 직접 잔존을 센다. 그래서 재시도가 수렴한다.
      expect(fn, isNot(contains('failedOps')));
      expect(fn, isNot(contains('callableDeleteAccountPreData')));
      expect(cleanup, isNot(contains('failedOps')));
    });

    test('DEL-PRE-05 cleanup 실패가 identity 파괴 앞에서 멈춘다', () {
      expect(_flat(fn), contains('if (identityCleanup.failed > 0)'));
      expect(
        _at(fn, 'if (identityCleanup.failed > 0)'),
        lessThan(_at(fn, 'userRef.delete()')),
      );
      expect(
        _at(fn, 'if (identityCleanup.failed > 0)'),
        lessThan(_at(fn, 'admin.auth().deleteUser(uid)')),
      );
    });
  });

  group('DEL-PRE-1x — 실패 주입 → identity 보존', () {
    test('DEL-PRE-10 쿼리 대상 삭제 실패를 집계한다', () {
      final block = _between(cleanup, 'for (const t of', 'TAX_ID_COL');
      expect(block, contains('out.failed++'));
      expect(block, contains('out.queryFailed = true'));
    });

    test('DEL-PRE-11 세무 identity 삭제 실패를 집계한다', () {
      final block = _between(
          cleanup, 'collection(TAX_ID_COL)', 'keys.resolved');
      expect(block, contains('out.failed++'));
    });

    test('DEL-PRE-12 초대 cleanup 실패도 같은 집계를 거친다', () {
      // 초대는 쿼리 대상 목록에 들어 있으므로 같은 루프의 집계를 쓴다 —
      // 컬렉션별로 실패 처리가 갈라지지 않는 것이 요점이다.
      expect(targets, contains('member_invitations'));
      final block = _between(cleanup, 'for (const t of', 'TAX_ID_COL');
      expect(block, contains('out.failed++'));
    });

    test('DEL-PRE-13 잔존 쿼리 실패를 0건으로 읽지 않는다', () {
      expect(residual, contains('out.queryFailed = true'));
      expect(cleared, contains('!r.queryFailed'));
      expect(_flat(fn), contains('srvDeletionIdentityCleared(identityResidual)'));
    });

    test('DEL-PRE-14 중단해도 freeze 를 해제하지 않는다', () {
      final gate = _between(
          fn, 'srvDeletionIdentityCleared(identityResidual)', 'userRef.delete()');
      expect(gate, contains('partial: true'));
      expect(gate, isNot(contains('account_deletion_tombstones')));
      expect(gate, isNot(contains('accountStatus')));
    });

    test('DEL-PRE-15 새 reason 을 발명하지 않았다 (§26)', () {
      final reasons = RegExp(r'reason: "([A-Z_]+)"')
          .allMatches(fn)
          .map((m) => m.group(1)!)
          .toSet();
      expect(reasons, {
        'FIRESTORE_RETRYABLE',
        'STORAGE_RETRYABLE',
        'DOMAIN_CLEANUP_INCOMPLETE',
      });
    });
  });

  group('DEL-PRE-2x — direct Final / 보존 대상 불변', () {
    test('DEL-PRE-20 PreData 0회로도 같은 결론이 나온다', () {
      // Final 의 cleanup 과 잔존 검사는 둘 다 **서버가 직접 읽은 상태**만
      // 근거로 삼는다. 클라이언트 호출 순서를 correctness 근거로 쓰지 않는다.
      expect(fn, contains('srvResolveDeletionIdentityKeys(uid)'));
      expect(fn, contains('srvCleanupDeletionOwnedIdentityState(uid'));
      expect(fn, contains('srvCountDeletionIdentityResidual(uid'));
      // 그리고 §27 순서를 지킨다.
      final order = [
        'srvEnsureAccountDeletionTombstone(',
        'srvCountDeletionDomainResidual(',
        'srvCleanupDeletionOwnedPersonal(',
        'srvCleanupDeletionOwnedIdentityState(',
        'srvSweepAccountOwnedStorage(',
        'let bizCleanupFailed = false;',
        'srvCountDeletionPersonalResidual(',
        'srvCountDeletionIdentityResidual(',
        'userRef.delete()',
        'admin.auth().deleteUser(uid)',
      ];
      var prev = -1;
      for (final m in order) {
        final at = _at(fn, m);
        expect(at, greaterThan(prev), reason: '순서 위반: $m');
        prev = at;
      }
    });

    test('DEL-PRE-21 익명화 대상을 삭제로 승격하지 않았다 (§57)', () {
      final t = _flat(targets);
      for (final keep in [
        'review_requests',
        'trust_score_history',
      ]) {
        expect(t, contains(keep));
        // 그 대상의 patch 가 null(삭제)이 아니다.
        expect(t, isNot(contains('{col: "$keep", field: "workerId", patch: null}')));
        expect(t, isNot(contains('{col: "$keep", field: "userId", patch: null}')));
      }
      expect(t, contains('monthly_reviews'));
      expect(t, isNot(contains('"monthly_reviews", field: "targetUserId", patch: null')));
      // 익명화 문구는 기존 계약 그대로다.
      expect(_count(targets, '탈퇴한 회원'), 5);
    });

    test('DEL-PRE-22 익명화 재실행이 성공 동치다 (§55·§56)', () {
      // 같은 술어로 다시 돌면 이미 익명화된 행은 쿼리에 걸리지 않는다 —
      // field 가 제거되거나 치환됐기 때문이다. 빈 결과는 실패가 아니다.
      final loop = _between(cleanup, 'for (const t of', 'TAX_ID_COL');
      expect(_flat(loop), contains('if (snap.empty) break;'));
    });

    test('DEL-PRE-23 보존 컬렉션을 cleanup 에 넣지 않았다 (§18)', () {
      for (final keep in [
        'deleted_accounts',
        'taxIdentityAuditLogs',
        'attendance',
        'employment_contracts',
        'payroll',
        'money_audit',
      ]) {
        expect(targets, isNot(contains(keep)), reason: '$keep 은 보존 대상이다');
      }
      // deleted_accounts 는 key 복원을 위해 **읽기만** 한다.
      expect(resolve, contains('collection("deleted_accounts")'));
      expect(resolve, isNot(contains('.delete()')));
    });
  });

  group('DEL-PRE-3x — identity sentinel', () {
    test('DEL-PRE-30 두 sentinel 모두 Final 이 해제한다', () {
      expect(cleanup, contains('nativeIdentityFingerprints'));
      expect(cleanup, contains('foreignIdFingerprints'));
      // 경계는 `if (keys.resolved) {` 다 — 맨 위 초기화 줄의 `keys.resolved`
      // 를 잡으면 구간이 비어 단정이 공허해진다.
      final block = _between(cleanup, 'if (keys.resolved) {', 'return out;');
      expect(block, contains('out.failed++'));
    });

    test('DEL-PRE-31 sentinel id 는 uid 가 아니라 key_role 이다', () {
      expect(_flat(sentinelIds), contains(r'`${k.ciHash}_${k.role}`'));
      expect(_flat(sentinelIds),
          contains(r'`${k.foreignFingerprint}_${k.role}`'));
      // role 제한은 기존 PreData 와 같다.
      expect(_flat(sentinelIds), contains(
          r'k.role === "USER" || k.role === "BUSINESS_ADMIN"'));
    });

    test('DEL-PRE-32 key 를 user 문서 → deleted_accounts 순으로 복원한다', () {
      expect(
        _at(resolve, 'collection("users")'),
        lessThan(_at(resolve, 'collection("deleted_accounts")')),
      );
      expect(resolve, contains('out.resolved = true'));
    });

    test('DEL-PRE-33 key 미복원은 "없음"이 아니라 "모름"이다 (§25)', () {
      // 모르는 채 계정을 지우면 남은 sentinel 때문에 그 사람이 다시 가입할
      // 수 없게 되고, 그때는 되돌릴 주인이 없다.
      expect(cleared, contains('!r.identityUnresolved'));
      expect(residual, contains('identityUnresolved: !keys.resolved'));
    });

    test('DEL-PRE-34 잔존 검사가 sentinel 존재를 직접 확인한다', () {
      expect(residual, contains('nativeIdentityFingerprints'));
      expect(residual, contains('foreignIdFingerprints'));
      expect(cleared, contains('r.sentinels === 0'));
    });

    test('DEL-PRE-35 PreData 의 삼김은 더 이상 유일한 방어가 아니다', () {
      // PreData 쪽 inner try/console.warn 은 early cleanup 으로 남는다(§8).
      // 바뀐 것은 "그것이 유일한 보증이었다"는 사실이다.
      expect(preData, contains('nativeIdentityFingerprints'));
      expect(fn, contains('srvCleanupDeletionOwnedIdentityState('));
    });
  });

  group('DEL-PRE-4x — 술어 공유 (drift 금지)', () {
    test('DEL-PRE-40 PreData 가 목록을 하드코딩하지 않는다 (§9)', () {
      expect(preData, contains('srvDeletionOwnedQueryTargets()'));
      // 예전의 인라인 8줄이 사라졌다.
      expect(preData, isNot(contains('paginateDelete("idCardAccessRequests"')));
      expect(preData, isNot(contains('paginateUpdate("review_requests"')));
    });

    test('DEL-PRE-41 Final 도 같은 함수를 호출한다', () {
      expect(cleanup, contains('srvDeletionOwnedQueryTargets()'));
      expect(residual, contains('srvDeletionOwnedQueryTargets()'));
    });

    test('DEL-PRE-42 목록 정의가 한 곳뿐이고 호출부가 셋이다', () {
      expect(_count(raw, 'function srvDeletionOwnedQueryTargets'), 1);
      // 호출부를 개수로 세지 않는다 — 선언 자체가 `name()` 을 포함해서
      // 숫자가 조용히 어긋난다. 각 호출 지점을 그 모양으로 확인한다.
      expect(_flat(preData), contains('srvDeletionOwnedQueryTargets().map('));
      expect(_flat(cleanup),
          contains('for (const t of srvDeletionOwnedQueryTargets())'));
      expect(_flat(residual),
          contains('const targets = srvDeletionOwnedQueryTargets();'));
    });

    test('DEL-PRE-43 삭제와 익명화가 같은 불변식으로 수렴한다', () {
      // patch === null 이면 문서 삭제, 아니면 익명화. 두 경우 모두
      // `where(field, "==", uid)` 가 0 이 된다 — 그래서 잔존 술어가 하나다.
      expect(_flat(cleanup), contains('if (t.patch === null) batch.delete(doc.ref);'));
      expect(_flat(cleanup), contains('else batch.update(doc.ref, t.patch);'));
      expect(_flat(residual), contains('.where(t.field, "==", uid).limit(1).get()'));
    });

    test('DEL-PRE-44 범용 삭제 프레임워크가 아니다 (§7)', () {
      expect(raw, isNot(contains('srvDeleteAnyCollection')));
      expect(cleanup, isNot(contains('recursiveDelete')));
      // 목록이 데이터 상수다 — 컬렉션명을 인자로 받는 공개 삭제기가 아니다.
      expect(raw, contains('type SrvDeletionOwnedQueryTarget = {'));
      expect(_flat(targets),
          contains('srvDeletionOwnedQueryTargets(): SrvDeletionOwnedQueryTarget[]'));
      expect(raw, isNot(contains('export function srvDeletionOwnedQueryTargets')));
      // 삭제 대상을 **밖에서 주입할 수 없다** — 서명이 uid 와 key 뿐이다.
      //   (helper 내부의 지역 배열 타입에 `col: string` 이 나오므로 전역
      //    부재로 단정하면 안 된다. 묻는 것은 서명이다.)
      final sig = _between(
          raw, 'async function srvCleanupDeletionOwnedIdentityState', '{');
      expect(_flat(sig), contains('uid: string'));
      expect(_flat(sig), contains('keys: SrvDeletionIdentityKeys'));
      expect(_flat(sig), isNot(contains('col')));
      expect(_flat(sig), isNot(contains('field')));
    });
  });

  group('DEL-PRE-5x — freeze 이후 재생성 writer gate', () {
    test('DEL-PRE-50 세무 identity 등록이 deleting 을 거부한다', () {
      final f = _fn(raw, 'callableRegisterTaxIdentity');
      expect(f, contains('srvAssertNotDeletingAccount(ud)'));
      // 이미 읽던 snapshot 을 쓴다 — 추가 조회 0.
      expect(_count(f, 'collection("users").doc(uid).get()'), 1);
    });

    test('DEL-PRE-51 세무 identity 변경도 거부한다', () {
      final f = _fn(raw, 'callableUpdateTaxIdentity');
      expect(f, contains('srvAssertNotDeletingAccount(updUd)'));
    });

    test('DEL-PRE-52 외국인 세무 복구도 거부한다', () {
      final f = _fn(raw, 'callableRecoverForeignTaxIdentity');
      expect(f, contains('srvAssertNotDeletingAccount(ud)'));
    });

    test('DEL-PRE-53 외국인 identity finalize 가 sentinel 을 되살리지 않는다', () {
      final f = _fn(raw, 'callableFinalizeForeignIdentity');
      expect(f, contains('srvAssertNotDeletingAccount(userSnap.data())'));
      // registration_pending 은 영향 없다 — gate 는 deleting 만 본다.
      final g = _helper(raw, 'srvAssertNotDeletingAccount');
      expect(g, contains('ACCOUNT_STATUS_DELETING'));
      expect(g, isNot(contains('registration_pending')));
    });

    test('DEL-PRE-54 열람 요청 CF 는 소속 근무자만 대상으로 한다', () {
      // 이 writer 에는 별도 gate 를 넣지 않았다. domain residual gate 가
      // CONFIRMED/CONTRACT_PENDING 을 0 으로 만들면 이 검사가 먼저 막는다.
      // 그 근거를 고정한다 — 근거가 사라지면 gate 가 필요해진다.
      final f = _fn(raw, 'callableCreateIdCardAccessRequest');
      expect(_flat(f), contains(
          '.where("status", "in", ["CONFIRMED", "CONTRACT_PENDING"])'));
      expect(f, contains('이 사업장의 소속 근무자가 아닙니다'));
    });

    test('DEL-PRE-55 세무 review 는 MUST_DELETE 를 만들지 않는다 (§51)', () {
      // taxIdentities 를 읽기만 한다 — 그래서 gate 대상이 아니다.
      final f = _fn(raw, 'callableReviewTaxIdentity');
      expect(f, contains('tx.get(taxRef)'));
      expect(f, isNot(contains('tx.set(taxRef')));
      expect(f, isNot(contains('tx.update(taxRef')));
    });
  });

  group('DEL-PRE-6x — Rules barrier 소스 계약', () {
    final rules = _src('firestore.rules');

    test('DEL-PRE-60 barrier helper 가 tombstone 존재만 본다 (§29·§30)', () {
      final h = _between(rules, 'function accountDeletionBarrierExists', '\n    }');
      expect(h, contains('account_deletion_tombstones'));
      expect(h, contains('exists('));
      // accountStatus 를 두 번째 truth 로 만들지 않는다.
      expect(h, isNot(contains('accountStatus')));
      expect(h, isNot(contains('get(')));
    });

    /// members 블록의 **create 절만** 떼어낸다. match 줄부터 자르면 앞선
    /// `allow get`·`allow list` 의 `isSuperAdmin()` 이 끼어들어 순서 단정이
    /// 엉뚱한 것을 비교한다.
    String membersCreate() {
      final block = _between(
          rules, 'match /businesses/{businessId}/members/{uid}', 'allow update');
      return _flat(_between(block, 'allow create:', ');'));
    }

    test('DEL-PRE-61 members create 의 모든 분기가 barrier 뒤에 있다 (§32·§34)', () {
      final c = membersCreate();
      // barrier 가 분기 괄호 **앞**에 있어야 역할 우회가 불가능하다.
      expect(c, contains(
          'allow create: if isLoggedIn() && !accountDeletionBarrierExists(uid) &&'));
      expect(c, contains('isSuperAdmin()'));
      expect(
        c.indexOf('!accountDeletionBarrierExists(uid)'),
        lessThan(c.indexOf('isSuperAdmin()')),
      );
    });

    test('DEL-PRE-62 members create 가 path↔data identity 를 묶는다 (§35)', () {
      final c = membersCreate();
      expect(c, contains("request.resource.data.get('uid', '') == uid"));
      expect(c, contains(
          "request.resource.data.get('businessId', '') == businessId"));
    });

    test('DEL-PRE-63 초대·열람요청 create 에도 barrier 가 있다 (§45·§49)', () {
      final inv = _flat(_between(
          rules, 'match /member_invitations/{invitationId}', 'allow update'));
      expect(inv, contains(
          '!accountDeletionBarrierExists(request.resource.data.targetUid)'));
      expect(inv, contains('request.resource.data.targetUid is string'));

      final icar = _flat(_between(
          rules, 'match /idCardAccessRequests/{requestId}', 'allow update'));
      expect(icar, contains(
          '!accountDeletionBarrierExists(request.resource.data.targetUserId)'));
      expect(icar, contains('request.resource.data.targetUserId is string'));
    });

    test('DEL-PRE-64 tombstone 클라이언트 접근은 여전히 전면 차단이다 (§40)', () {
      final t = _between(
          rules, 'match /account_deletion_tombstones/{uid}', '\n    }');
      expect(t, contains('allow read: if false;'));
      expect(t, contains('allow create: if false;'));
      expect(t, contains('allow update: if false;'));
      expect(t, contains('allow delete: if false;'));
    });
  });
}
