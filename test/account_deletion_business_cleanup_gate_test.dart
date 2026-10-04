// [R7-P4.4E.11C.0C.0a.2] 사업장 정리가 실패해도 계정을 지워버렸다
//
// `callableDeleteAccountFinal` 의 사업장 정리는 부가 작업처럼 보이지만 아니다.
// 그것은 관리자 권한과 사업장 소유관계를 **종료하는** canonical mutation 이다.
//
// 그런데 그 블록의 catch 는 이렇게 끝났다.
//
//   } catch (e) {
//     console.error(...);
//     // continue — 사업장 정리 부분 실패도 Auth 삭제는 진행
//   }
//
// 그리고 바로 뒤에서 user 문서를 지우고 Auth 를 지웠다. 남는 상태는 둘이다.
//
//   · 단독 관리자인데 비활성화가 실패 → 주인 없는 사업장이 **계속 활성**
//     상태로 남는다. 근로자는 그 사업장 공고에 계속 지원할 수 있다.
//   · 공동 관리자인데 제거가 실패 → 탈퇴한 uid 가 `adminIds` 에 남는다.
//
// 더 나쁜 것은 **되돌릴 수단이 없다**는 점이다. 이 블록은 `role` 로 분기하고,
// role 은 user 문서에서 읽는다. user 문서를 지운 뒤에는 `deleted_accounts`
// 복구에 의존하고, 그마저 없으면 role = "" 이라 블록 자체를 건너뛴다.
// Auth 까지 지워졌으면 사용자가 CF 를 호출할 수조차 없다. 즉 실패한 정리는
// 영구히 미완으로 남는다.
//
// 그래서 invariant 를 세운다.
//
//   business cleanup 완전 성공  <  user 문서 삭제  <  Auth 삭제
//
// 이 파일이 고정하는 것
//   DEL-BIZ-0x   실패를 삼키지 않는다 / gate 가 존재한다
//   DEL-BIZ-1x   순서 불변 (gate < user 문서 < Auth)
//   DEL-BIZ-2x   재시도 수렴 (멱등·롤백 없음)
//   DEL-BIZ-3x   §17 cleanup 분류 — 어느 실패가 gate 이고 어느 것이 아닌가
//   DEL-INT-0x   §24~§40 중간정산 — Part B 판정 B(SAFE) 의 근거를 고정한다
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

/// 함수 전체를 **원문 그대로**(주석 포함) 떼어낸다.
String _fnRaw(String raw, String name) {
  final a = raw.indexOf('export const $name');
  if (a < 0) throw StateError('$name 을 찾지 못함');
  final rel = raw.substring(a).indexOf('\n);');
  if (rel < 0) throw StateError('$name 의 끝을 찾지 못함');
  return raw.substring(a, a + rel);
}

String _fn(String raw, String name) => _codeOf(_fnRaw(raw, name));

/// 고정폭 창(`substring(i, i + 400)`)은 코드가 길어지면 조용히 깨진다.
/// 그래서 이 파일의 모든 구간 추출은 **경계 문자열**로만 자른다.
int _at(String s, String needle) {
  final i = s.indexOf(needle);
  if (i < 0) throw StateError('구간 경계를 찾지 못함: $needle');
  return i;
}

String _between(String s, String from, String to) {
  final a = _at(s, from);
  final b = s.indexOf(to, a);
  if (b < 0) throw StateError('끝 경계를 찾지 못함: $to (시작: $from)');
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
  final fnRaw = _fnRaw(raw, 'callableDeleteAccountFinal');
  final fn = _fn(raw, 'callableDeleteAccountFinal');

  // 구간 추출을 **셀 안에서** 한다.
  //
  //   처음에는 main() 본문에서 미리 잘라 두었다. 그러자 mutation 테스트에서
  //   gate 를 지우거나 옮기는 순간 파일 구성 자체가 StateError 로 터져 모든
  //   셀이 한꺼번에 죽었다 — "어느 단정이 그 변경을 잡았는가"를 볼 수 없었다.
  //   그래서 필요한 셀에서만 자른다.

  // 사업장 정리 블록: 실패 플래그 선언부터 gate 직전까지.
  String bizBlock() => _between(
        fn,
        'let bizCleanupFailed = false;',
        'if (bizCleanupFailed)',
      );

  // gate 구간: gate 부터 user 문서 삭제 직전까지.
  String gateRegion() =>
      _between(fn, 'if (bizCleanupFailed)', 'userRef.delete()');

  group('DEL-BIZ — 사업장 정리 실패가 계정 파괴를 막는다', () {
    test('DEL-BIZ-01 catch 가 실패를 기록한다 (console.error 로 끝나지 않는다)', () {
      expect(
        _flat(bizBlock()),
        contains(r'catch (e) { bizCleanupFailed = true;'),
        reason: 'catch 가 플래그를 세우지 않으면 뒤의 gate 가 영원히 거짓이다',
      );
    });

    test('DEL-BIZ-02 catch 본문에 "넘어가라"는 지시가 없다', () {
      // 전역 부재로 단정하면 안 된다 — 패치의 주석이 옛 문장을 **인용**하고
      // 있고, 그 인용은 지워야 할 대상이 아니다. 그래서 묻는 범위를
      // catch 본문 이후 ~ gate 직전으로 좁힌다.
      final catchTail = _between(
        fnRaw,
        'bizCleanupFailed = true;',
        'if (bizCleanupFailed)',
      );
      expect(
        catchTail,
        isNot(contains('사업장 정리 부분 실패도 Auth 삭제는 진행')),
        reason: '그 문장이 바로 이 Phase 가 고친 동작이다',
      );
      expect(
        catchTail,
        isNot(contains('// continue')),
        reason: 'catch 가 계속 진행을 지시하면 gate 가 무의미해진다',
      );
    });

    test('DEL-BIZ-03 gate 가 partial 응답으로 중단한다', () {
      final g = _flat(gateRegion());
      expect(g, contains('if (bizCleanupFailed)'));
      expect(g, contains('success: false'));
      expect(g, contains('partial: true'));
    });

    test('DEL-BIZ-04 gate 가 새 reason 을 발명하지 않는다', () {
      expect(_flat(gateRegion()), contains('reason: "FIRESTORE_RETRYABLE"'));

      // Final 이 돌려주는 reason 집합이 커지지 않았음을 함께 고정한다.
      final reasons = RegExp(r'reason: "([A-Z_]+)"')
          .allMatches(fn)
          .map((m) => m.group(1)!)
          .toSet();
      expect(
        reasons,
        {
          'FIRESTORE_RETRYABLE',
          'STORAGE_RETRYABLE',
          'DOMAIN_CLEANUP_INCOMPLETE',
        },
        reason: '클라이언트는 success != true 만 보지만, reason 집합이 조용히 '
            '늘어나면 로그 해석이 어긋난다',
      );
    });

    test('DEL-BIZ-05 쿼리 실패와 개별 update 실패가 같은 catch 로 떨어진다', () {
      // "사업장 0개"와 "모르겠다"를 구별할 수 없으므로 둘 다 막아야 한다.
      final b = bizBlock();
      final iTry = _at(b, 'try {');
      final iQuery = _at(b, '.collection("businesses")');
      final iLoop = _at(b, 'for (const bizDoc');
      final iCatch = _at(b, 'catch (e)');
      expect(iTry, lessThan(iQuery));
      expect(iQuery, lessThan(iLoop));
      expect(iLoop, lessThan(iCatch));
    });

    test('DEL-BIZ-06 gate 가 사업장 정리 블록 뒤에 있다', () {
      expect(
        _at(fn, 'let bizCleanupFailed = false;'),
        lessThan(_at(fn, 'if (bizCleanupFailed)')),
      );
    });
  });

  group('DEL-BIZ-1x — 순서 불변', () {
    test('DEL-BIZ-10 gate < user 문서 삭제 < Auth 삭제', () {
      final iGate = _at(fn, 'if (bizCleanupFailed)');
      final iUser = _at(fn, 'userRef.delete()');
      final iAuth = _at(fn, 'admin.auth().deleteUser(uid)');
      expect(iGate, lessThan(iUser));
      expect(iUser, lessThan(iAuth));
    });

    test('DEL-BIZ-11 파괴 지점이 각각 하나뿐이다 (우회 경로 없음)', () {
      // 순서 단정은 "그 호출이 하나"일 때만 의미가 있다.
      expect(_count(fn, 'userRef.delete()'), 1);
      expect(_count(fn, 'admin.auth().deleteUser(uid)'), 1);
    });

    test('DEL-BIZ-12 gate 와 user 문서 삭제 사이에 성공 반환이 없다', () {
      expect(gateRegion(), isNot(contains('success: true')));
    });

    test('DEL-BIZ-13 클라이언트 분기가 reason 에 무관하다 (§51)', () {
      // 새 gate 를 추가해도 클라이언트를 고칠 필요가 없는 이유를 고정한다.
      // 분기는 reason 을 보지 않고 success 만 본다 — 그래서 사업장 gate 도
      // 기존 "세션 유지 + 재시도" 경로로 그대로 흘러간다.
      final client = _flat(_codeOf(_src('lib/services/auth_service.dart')));
      expect(client, contains(r"if (finalData['success'] != true) {"));
      expect(
        client,
        isNot(contains("reason == 'FIRESTORE_RETRYABLE'")),
        reason: 'reason 별 분기를 만들면 gate 가 늘 때마다 클라이언트가 깨진다',
      );
    });
  });

  group('DEL-BIZ-2x — 재시도 수렴', () {
    test('DEL-BIZ-20 비활성화는 deactivatedAt 존재로 멱등하다', () {
      expect(
        _flat(bizBlock()),
        contains(r'if (bizDoc.data()["deactivatedAt"]) continue;'),
      );
    });

    test('DEL-BIZ-21 공동관리자 제거는 arrayRemove 로 멱등하다', () {
      expect(_flat(bizBlock()), contains('arrayRemove(uid)'));
    });

    test('DEL-BIZ-22 이미 성공한 사업장을 되돌리지 않는다', () {
      // §12 — 롤백은 다른 관리자의 권한까지 되살린다. 하지 않는다.
      final b = bizBlock();
      final g = gateRegion();
      expect(b, isNot(contains('arrayUnion(uid)')));
      expect(g, isNot(contains('arrayUnion(uid)')));
      expect(b, isNot(contains('deactivatedAt: null')));
      expect(
        b,
        isNot(contains('FieldValue.delete()')),
        reason: 'deactivatedAt 을 지우는 되돌림도 금지',
      );
    });

    test('DEL-BIZ-23 gate 가 tombstone·freeze 를 해제하지 않는다', () {
      // 중단해도 계정은 여전히 deleting 이어야 한다 — 그래야 재시도까지
      // 새 지원·새 요청이 막힌다.
      final g = gateRegion();
      expect(g, isNot(contains('account_deletion_tombstones')));
      expect(g, isNot(contains('accountStatus')));
    });
  });

  group('DEL-BIZ-3x — §17 cleanup 분류', () {
    test('DEL-BIZ-30 members 정리 실패는 gate 가 아니다 (위생 등급 유지)', () {
      // 분류 근거: 삭제된 uid 는 인증할 수 없다. 남은 members 문서는
      // 관리자 목록의 유령 항목이지 권한 획득 경로가 아니다.
      // 이 판단은 이번 Phase 가 새로 만든 것이 아니라 기존 코드의 기록이다.
      final members = _between(
        fn,
        'collectionGroup("members")',
        'trust_settings',
      );
      expect(members, contains('console.error'));
      expect(members, isNot(contains('partial:')));
      expect(members, isNot(contains('return {')));
    });

    test('DEL-BIZ-31 trust_settings 정리 실패도 gate 가 아니다', () {
      final trust = _between(
        fn,
        'collection("trust_settings")',
        'srvEnsureAccountDeletionTombstone',
      );
      expect(trust, contains('.catch('));
      expect(trust, isNot(contains('partial:')));
    });

    test('DEL-BIZ-32 분류의 기준선 — gate 인 cleanup 은 네 개다', () {
      // tombstone(freeze) · 도메인 잔여 · Storage · 사업장.
      // 이 집합이 조용히 늘거나 줄면 실패 의미가 바뀐다.
      expect(fn, contains('if (!tombstoneOk)'));
      expect(fn, contains('srvDeletionDomainCleared('));
      expect(fn, contains('srvAccountStorageCleared('));
      expect(fn, contains('if (bizCleanupFailed)'));
      expect(_count(fn, 'partial: true'), 5,
          reason: 'gate 4개 + user 문서 삭제 실패 1개');
    });
  });

  group('DEL-INT — 중간정산 (Part B, 판정 B = SAFE 근거)', () {
    final blockers = _fn(raw, 'callableGetWithdrawBlockers');
    final approve = _fn(raw, 'callableApproveInterimSettlement');
    final process = _fn(raw, 'callableProcessInterimSettlement');

    test('DEL-INT-01 탈퇴 blocker 의 중간정산 쿼리는 businessId 기준이다', () {
      // 즉 **관리자** 탈퇴에만 걸린다. 근로자 탈퇴에는 중간정산 blocker 가
      // 애초에 없다. 이 비대칭을 "누락"으로 읽지 않도록 사실로 고정한다.
      expect(_count(blockers, 'interim_settlement_requests'), 1);
      final q = _between(blockers, 'interim_settlement_requests', '.get()');
      expect(q, contains('"businessId"'));
      expect(q, isNot(contains('workerId')));
    });

    test('DEL-INT-02 승인은 근로자 프로필을 읽지 않는다 (알림 쓰기만)', () {
      expect(
        _flat(approve),
        contains(
          'collection("users").doc(workerId).collection("notifications").add(',
        ),
      );
      expect(_count(approve, 'collection("users")'), 1);
      for (final f in [
        'bankName',
        'accountNumber',
        'accountHolder',
        'wageAccount',
      ]) {
        expect(approve, isNot(contains(f)), reason: '$f 을 읽으면 freeze 가 필요해진다');
      }
    });

    test('DEL-INT-03 지급 금액의 출처는 근태다 (user 문서가 아니다)', () {
      expect(process, contains('ad.finalWage'));
      expect(process, contains('netWage'));
      expect(
        _flat(process),
        contains(r'if (ad.wageStatus !== "confirmed")'),
        reason: '확정된 근태만 지급 — 금액이 탈퇴로 흔들리지 않는 이유',
      );
      expect(_count(process, 'collection("users")'), 1);
      for (final f in [
        'bankName',
        'accountNumber',
        'accountHolder',
        'wageAccount',
      ]) {
        expect(process, isNot(contains(f)));
      }
    });
  });
}
