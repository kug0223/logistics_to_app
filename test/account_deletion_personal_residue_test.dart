// [R7-P4.4E.11C.0C.0a.3] 탈퇴가 끝났는데 위치·이름·전화번호·근무가능일이 남았다
//
// Final 은 identity 를 파괴하기 전에 개인 데이터를 치우고 있었다. 그런데 그
// cleanup 들은 전부 이렇게 끝났다.
//
//   } catch (e) { console.error(...); }   ← 그리고 계속 진행
//
// 그 뒤에서 user 문서와 Auth 를 지웠다. 그러면 남은 개인정보에 **주인이
// 없다** — 본인은 인증할 수 없어 CF 를 다시 부를 수 없고, 이 프로젝트는
// 전역 sweeper 를 만들지 않는다. 즉 실패 한 번이 영구 잔류가 된다.
//
// 그리고 더 나쁜 것: `worker_availability/{uid}` 는 **어느 단계에서도 지우지
// 않았다.** PreData·Applications·Final 전부 참조 0건이었다. 거주 시/군과
// 근무가능일 달력이 계정과 함께 사라지지 않았다.
//
// 분류가 뒤집힌 것도 둘 있다.
//
//   members   "인증 불가 → 권한 위험 없음 → 위생" 으로 적혀 있었다.
//             권한 측면에서는 맞다. 그러나 그 행에는 name 과 phone 이 있다.
//   순서      개인 cleanup 이 freeze **앞**에 있었다. barrier 가 서기 전에
//             지우기 시작하면, 그 창에서 다른 기기가 만든 행은 빠져나간다.
//
// 이 파일이 고정하는 것
//   DEL-PERS-0x    worker_locations
//   DEL-PERS-1x    trust_settings
//   DEL-PERS-2x    members
//   DEL-PERS-3x    notifications
//   DEL-PERS-4x    worker_availability (이번에 추가된 cleanup)
//   DEL-PERS-5x    순서 / 잔존 확실성
//   DEL-PERS-RACE  freeze 이후 재생성 차단
//   DEL-PERS-6x    보존 대상 불변 (RETAIN_WITH_POLICY)
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

/// `from` 부터 그 뒤 첫 `to` 직전까지. 한 cleanup 블록만 떼어낼 때 쓴다.
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
  final cleanup = _helper(raw, 'srvCleanupDeletionOwnedPersonal');
  final residual = _helper(raw, 'srvCountDeletionPersonalResidual');
  final cleared = _helper(raw, 'srvDeletionPersonalCleared');

  group('DEL-PERS-0x — worker_locations (GPS, 보존 근거 없음)', () {
    test('DEL-PERS-01 소유 술어로 전수 삭제한다', () {
      final block = _between(cleanup, 'collection("worker_locations")', '} catch');
      expect(_flat(block), contains('.where("userId", "==", uid)'));
      expect(_flat(block), contains('batch.delete(doc.ref)'));
      expect(_flat(block), contains('.limit(100)'),
          reason: '페이지네이션 없이 전수 삭제를 주장할 수 없다');
    });

    test('DEL-PERS-02 삭제 실패가 user 문서 삭제를 막는다', () {
      // 실패가 집계되고, 그 집계가 파괴 앞에서 멈춘다.
      final block = _between(cleanup, 'collection("worker_locations")', 'collectionGroup');
      expect(block, contains('out.failed++'));
      expect(_flat(fn), contains('if (personalCleanup.failed > 0)'));
      expect(
        _at(fn, 'if (personalCleanup.failed > 0)'),
        lessThan(_at(fn, 'userRef.delete()')),
      );
    });

    test('DEL-PERS-03 삭제 실패가 Auth 삭제를 막는다', () {
      expect(
        _at(fn, 'if (personalCleanup.failed > 0)'),
        lessThan(_at(fn, 'admin.auth().deleteUser(uid)')),
      );
      // 파괴 지점이 각각 하나뿐일 때만 순서 단정이 의미를 갖는다.
      expect(_count(fn, 'userRef.delete()'), 1);
      expect(_count(fn, 'admin.auth().deleteUser(uid)'), 1);
    });

    test('DEL-PERS-04 재시도가 수렴한다 (이미 없으면 성공 동치)', () {
      // 빈 결과는 실패가 아니라 종료다.
      final block = _between(cleanup, 'collection("worker_locations")', '} catch');
      expect(_flat(block), contains('if (snap.empty) break;'));
      // 그리고 Final 이 삼키던 단독 블록은 사라졌다.
      expect(fn, isNot(contains('worker_locations cleanup failed')));
    });
  });

  group('DEL-PERS-1x — trust_settings', () {
    test('DEL-PERS-10 cleanup 실패가 identity 를 보존한다', () {
      final block = _between(
          cleanup, 'collection("trust_settings")', 'return out;');
      expect(block, contains('out.failed++'));
    });

    test('DEL-PERS-11 없는 문서 삭제는 성공 동치다', () {
      // Firestore delete 는 문서가 없어도 성공한다 — 별도 exists 분기를
      // 두지 않는 것이 이 계약이다.
      final block = _between(
          cleanup, 'collection("trust_settings")', 'return out;');
      expect(block, contains('.doc(uid).delete()'));
      expect(block, isNot(contains('.exists')));
    });

    test('DEL-PERS-12 잔존 확인이 같은 문서를 다시 읽는다', () {
      expect(_flat(residual), contains('collection("trust_settings").doc(uid).get()'));
      expect(cleared, contains('r.trustSettings === 0'));
    });
  });

  group('DEL-PERS-2x — members (name·phone 포함 → MUST_DELETE)', () {
    test('DEL-PERS-20 관련 구성원 행을 전수 삭제한다', () {
      final block = _between(cleanup, 'collectionGroup("members")', '} catch');
      expect(_flat(block), contains('.where("uid", "==", uid)'));
      expect(_flat(block), contains('batch.delete(doc.ref)'));
      expect(_flat(block), contains('CHUNK = 499'),
          reason: 'batch 상한을 넘기면 많은 사업장 소속에서 조용히 끊긴다');
    });

    test('DEL-PERS-21 실패가 gate 다 (위생 분류 폐기)', () {
      final block = _between(cleanup, 'collectionGroup("members")', 'worker_availability');
      expect(block, contains('out.failed++'));
      expect(block, contains('out.queryFailed = true'),
          reason: '쿼리 실패를 0건으로 읽으면 안 된다');
    });

    test('DEL-PERS-22 다른 사람의 구성원 행은 건드리지 않는다', () {
      // 술어는 uid 동등 하나뿐이다 — businessId 범위 삭제나 전체 열거가 없다.
      final block = _between(cleanup, 'collectionGroup("members")', '} catch');
      expect(_count(block, '.where('), 1);
      expect(block, isNot(contains('recursiveDelete')));
    });
  });

  group('DEL-PERS-3x — notifications', () {
    test('DEL-PERS-30 여러 건을 끝까지 지운다', () {
      final block = _between(cleanup, 'collection("notifications")', '} catch');
      expect(_flat(block), contains('.limit(200)'));
      expect(_flat(block), contains('more = snap.docs.length === 200'),
          reason: '한 페이지만 지우고 성공이라 하면 안 된다');
      expect(_flat(block), contains('batch.delete(doc.ref)'));
    });

    test('DEL-PERS-31 부분 삭제 실패가 Final 을 멈춘다', () {
      final block = _between(cleanup, 'collection("notifications")', 'trust_settings');
      expect(block, contains('out.failed++'));
      expect(_flat(fn), contains('if (personalCleanup.failed > 0)'));
    });

    test('DEL-PERS-32 재시도가 남은 것을 비운다', () {
      // 루프는 매번 새로 조회한다 — 커서를 들고 다니지 않으므로 이미 지운
      // 것을 다시 세지 않고, 남은 것부터 계속 지운다.
      final block = _between(cleanup, 'collection("notifications")', '} catch');
      expect(_flat(block), contains('while (more)'));
      expect(_flat(block), contains('await notifRef.limit(200).get()'));
    });

    test('DEL-PERS-33 열거 실패를 0건으로 읽지 않는다', () {
      final block = _between(cleanup, 'collection("notifications")', 'trust_settings');
      expect(block, contains('out.queryFailed = true'));
      expect(cleared, contains('!r.queryFailed'));
    });

    test('DEL-PERS-34 상위 문서 삭제보다 먼저 비운다', () {
      // 서브컬렉션은 상위 문서를 지워도 남는다. 순서가 계약이다.
      expect(
        _at(fn, 'srvCleanupDeletionOwnedPersonal('),
        lessThan(_at(fn, 'userRef.delete()')),
      );
    });
  });

  group('DEL-PERS-4x — worker_availability (이번에 추가된 cleanup)', () {
    test('DEL-PERS-40 cleanup 에 포함됐다', () {
      expect(_flat(cleanup),
          contains('collection("worker_availability").doc(uid).delete()'));
    });

    test('DEL-PERS-41 실패가 identity 파괴를 막는다', () {
      final block = _between(
          cleanup, 'collection("worker_availability")', 'collection("users")');
      expect(block, contains('out.failed++'));
    });

    test('DEL-PERS-42 잔존 확인에도 포함됐다', () {
      expect(_flat(residual),
          contains('collection("worker_availability").doc(uid).get()'));
      expect(cleared, contains('r.availability === 0'));
    });
  });

  group('DEL-PERS-5x — 순서와 잔존 확실성', () {
    test('DEL-PERS-50 freeze < 개인 cleanup (§38)', () {
      // 예전에는 개인 cleanup 이 freeze 앞에 있었다. barrier 가 서기 전에
      // 지우면 그 창의 재생성을 막을 수 없다.
      expect(
        _at(fn, 'srvEnsureAccountDeletionTombstone('),
        lessThan(_at(fn, 'srvCleanupDeletionOwnedPersonal(')),
      );
    });

    test('DEL-PERS-51 §38 전체 순서', () {
      final order = [
        'srvEnsureAccountDeletionTombstone(',
        'srvCountDeletionDomainResidual(',
        'srvCleanupDeletionOwnedPersonal(',
        'srvSweepAccountOwnedStorage(',
        'let bizCleanupFailed = false;',
        'srvCountDeletionPersonalResidual(',
        'userRef.delete()',
        'admin.auth().deleteUser(uid)',
      ];
      var prev = -1;
      for (final marker in order) {
        final at = _at(fn, marker);
        expect(at, greaterThan(prev), reason: '순서 위반: $marker');
        prev = at;
      }
    });

    test('DEL-PERS-52 user 문서 삭제 직전 잔존 0 을 확인한다 (§40)', () {
      expect(fn, contains('srvDeletionPersonalCleared(personalResidual)'));
      expect(
        _at(fn, 'srvDeletionPersonalCleared('),
        lessThan(_at(fn, 'userRef.delete()')),
      );
    });

    test('DEL-PERS-53 잔존 확인이 cleanup 집계를 믿지 않는다', () {
      // 같은 술어로 **다시 읽는다**. 집계 변수를 재사용하면 cleanup 이후의
      // 새 행을 영원히 못 본다.
      expect(residual, contains('collectionGroup("members")'));
      expect(residual, contains('collection("worker_locations")'));
      expect(residual, contains('collection("notifications")'));
      expect(
        _flat(fn),
        isNot(contains('srvDeletionPersonalCleared(personalCleanup)')),
        reason: 'cleanup 집계를 잔존 판정에 재사용하면 안 된다',
      );
    });

    test('DEL-PERS-54 중단해도 freeze 를 해제하지 않는다', () {
      final gate = _between(
          fn, 'srvDeletionPersonalCleared(personalResidual)', 'userRef.delete()');
      expect(gate, contains('partial: true'));
      expect(gate, isNot(contains('account_deletion_tombstones')));
      expect(gate, isNot(contains('accountStatus')));
    });

    test('DEL-PERS-55 새 reason 을 발명하지 않았다 (§34)', () {
      final reasons = RegExp(r'reason: "([A-Z_]+)"')
          .allMatches(fn)
          .map((m) => m.group(1)!)
          .toSet();
      expect(reasons, {
        'FIRESTORE_RETRYABLE',
        'STORAGE_RETRYABLE',
        'DOMAIN_CLEANUP_INCOMPLETE',
      });
      expect(fn, isNot(contains('LOCATION_RETRYABLE')));
      expect(fn, isNot(contains('NOTIFICATION_RETRYABLE')));
    });
  });

  group('DEL-PERS-RACE — freeze 이후 재생성 차단 (§27·§31)', () {
    test('DEL-PERS-RACE-01 근무가능일 writer 가 deleting 을 거부한다', () {
      final f = _fn(raw, 'callableSetAvailability');
      expect(f, contains('srvAssertNotDeletingAccount(uSnap.data())'));
      // 이미 읽던 snapshot 으로 판단한다 — 추가 조회 0.
      expect(_count(f, 'collection("users").doc(uid).get()'), 1);
    });

    test('DEL-PERS-RACE-02 초대지역 writer 도 같은 gate 를 쓴다', () {
      final f = _fn(raw, 'callableSetInviteRegions');
      expect(f, contains('srvAssertNotDeletingAccount(uSnap.data())'));
    });

    test('DEL-PERS-RACE-03 구성원 수락이 deleting 을 거부한다', () {
      final f = _fn(raw, 'callableAcceptInvitation');
      expect(f, contains('srvAssertNotDeletingAccount(userSnap.data())'));
      // gate 가 members 행 생성보다 앞이어야 한다.
      expect(_at(f, 'srvAssertNotDeletingAccount('),
          lessThan(_at(f, 'tx.set(memberRef')));
    });

    test('DEL-PERS-RACE-04 gate 는 canonical 상태값 하나만 본다', () {
      final g = _helper(raw, 'srvAssertNotDeletingAccount');
      expect(g, contains('ACCOUNT_STATUS_DELETING'));
      expect(g, isNot(contains("'deleting'")),
          reason: '리터럴을 복제하면 상태값이 갈라진다');
      expect(g, contains('failed-precondition'));
    });

    test('DEL-PERS-RACE-05 복구 도구는 문서를 되살릴 수 없다', () {
      // callableSyncInviteKeys 는 존재하는 문서만 갱신한다 — cleanup 이후에는
      // 쓰지 못하므로 별도 gate 가 필요 없다. 그 근거를 고정한다.
      final f = _fn(raw, 'callableSyncInviteKeys');
      expect(_flat(f), contains('if (!snap.exists) return'));
      expect(f, isNot(contains('{merge: true}')),
          reason: '없는 문서를 merge 로 만들면 재생성 경로가 된다');
    });
  });

  group('DEL-PERS-6x — 보존 대상 불변 (§41·§42·§43)', () {
    test('DEL-PERS-60 개인 cleanup 이 보존 컬렉션을 건드리지 않는다', () {
      for (final keep in [
        'attendance',
        'employment_contracts',
        'interim_settlement_requests',
        'payroll',
        'money_audit',
        'monthly_reviews',
        'review_requests',
        'trust_score_history',
        'deleted_accounts',
      ]) {
        expect(cleanup, isNot(contains(keep)), reason: '$keep 은 보존 대상이다');
      }
    });

    test('DEL-PERS-61 익명화 정책을 확장하지 않았다', () {
      expect(cleanup, isNot(contains('탈퇴한 회원')));
      expect(residual, isNot(contains('탈퇴한 회원')));
    });

    test('DEL-PERS-62 범용 삭제 프레임워크가 아니다 (§57)', () {
      // 대상 다섯이 코드에 고정되어 있어야 한다.
      expect(raw, isNot(contains('srvDeleteAnyCollection')));
      expect(cleanup, isNot(contains('recursiveDelete')));
      // 컬렉션 이름이 인자로 들어오지 않는다.
      final sig = _between(raw, 'async function srvCleanupDeletionOwnedPersonal', '{');
      expect(sig, contains('uid: string'));
      expect(sig, isNot(contains('col')));
    });
  });
}
