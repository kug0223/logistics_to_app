// [R7-P4.4E.11C.0C.0a.5] 탈퇴한 사람에게 알림이 계속 생겼다
//
// 가장 분명한 경로는 급여였다. 근로자는 미이체 급여를 남긴 채 탈퇴할 수 있고
// (탈퇴 blocker 에서 warning 이지 hardBlock 이 아니다), 보존된 근태에 대해
// 나중에 관리자가 급여를 확정하면 `srvNotifyWageEvent` 가 돈다. 그때는 user
// 문서도 Auth 도 없다 — 그래서 `accountStatus` 로는 막을 수 없었고, 만들어진
// 알림을 지울 주인도 없었다.
//
// Final 에서 한 번 더 지우는 것은 해결책이 아니다. 지운 뒤에 오는 사건이
// 문제이기 때문이다. **writer authority** 를 막아야 한다.
//
// 그런데 persistent notification writer 는 약 68곳이었다. 그래서 emitter 마다
// `if (user exists)` 를 심지 않고, persistence 자체에 canonical authority 를
// 하나 두었다.
//
//   srvPersistNotification / srvPersistNotificationWithId
//     → 같은 transaction 에서 tombstone 을 읽고 create 한다
//
// 이미 domain transaction 안에서 알림을 쓰는 세 자리는 그 결합을 풀지 않고
// **같은 transaction** 에서 `srvDeletionBarrierExistsInTx` 를 읽는다.
//
// 고정하는 것
//   NOTIF-AUTH-*   canonical helper 계약
//   NOTIF-TX-*     원자성 (읽기-쓰기 같은 transaction)
//   NOTIF-WAGE-*   확정된 BLOCKER 경로
//   NOTIF-FAN-*    fanout 은 수신자별 독립
//   NOTIF-EMIT-*   emitter family 대표
//   NOTIF-BYPASS-* raw writer 가 남지 않았다 (미래 회귀 탐지)
//   NOTIF-TRIG-*   onNotificationCreated 가 삭제된 문서를 되살리지 않는다
//   NOTIF-REG-*    기존 계약 회귀
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

String _fn(String raw, String name) {
  final a = raw.indexOf('export const $name');
  if (a < 0) throw StateError('$name 을 찾지 못함');
  final rel = raw.substring(a).indexOf('\n);');
  if (rel < 0) throw StateError('$name 의 끝을 찾지 못함');
  return _codeOf(raw.substring(a, a + rel));
}

String _helper(String raw, String name) {
  final a = raw.indexOf('function $name(');
  if (a < 0) throw StateError('$name 을 찾지 못함');
  final rel = raw.substring(a).indexOf('\n}');
  if (rel < 0) throw StateError('$name 의 끝을 찾지 못함');
  return _codeOf(raw.substring(a, a + rel));
}

/// 앵커를 **포함하는** transaction 블록.
String _txBlock(String src, String anchor) {
  final a = _at(src, anchor);
  final t = src.lastIndexOf('runTransaction(async (tx) => {', a);
  if (t < 0) throw StateError('앵커를 감싸는 transaction 이 없다: $anchor');
  final end = src.indexOf('});', a);
  return src.substring(t, end < 0 ? src.length : end);
}

/// `users/{uid}/notifications` 에 **직접** 쓰는 자리를 찾아 enclosing 함수명과
/// 함께 돌려준다.
///
///   문자열 개수만 세지 않는다(§87). 각 callsite 의 enclosing 함수를 분류해서
///   "허용된 자리"가 아닌 곳이 생기면 잡는다.
List<_RawSite> _rawNotificationWrites(String raw) {
  final lines = raw.split(RegExp(r'\r?\n'));
  final out = <_RawSite>[];
  for (var i = 0; i < lines.length; i++) {
    if (!lines[i].contains('collection("notifications")')) continue;
    final win = lines
        .sublist(i, i + 8 > lines.length ? lines.length : i + 8)
        .join(' ')
        .replaceAll(RegExp(r'\s+'), ' ');
    // 읽기 전용 chain 은 제외
    final head = win.length > 140 ? win.substring(0, 140) : win;
    if (RegExp(r'\.where\(|\.orderBy\(|\.limit\(\d').hasMatch(head)) continue;
    if (!RegExp(r'\.add\(|\.create\(|\.set\(|\.doc\(').hasMatch(win)) continue;
    var fn = '?';
    for (var k = i; k >= 0; k--) {
      final m = RegExp(r'^(?:export const (\w+)|async function (\w+)|function (\w+))')
          .firstMatch(lines[k]);
      if (m != null) {
        fn = m.group(1) ?? m.group(2) ?? m.group(3) ?? '?';
        break;
      }
    }
    out.add(_RawSite(i + 1, fn, win));
  }
  return out;
}

class _RawSite {
  _RawSite(this.line, this.fn, this.window);
  final int line;
  final String fn;
  final String window;
}

void main() {
  final raw = _src('functions/src/index.ts');
  final code = _codeOf(raw);

  group('NOTIF-AUTH — canonical helper 계약', () {
    test('NOTIF-AUTH-01 helper 가 tombstone 을 유일한 근거로 본다 (§2·§3·§4)', () {
      final h = _helper(raw, 'srvPersistNotificationWithId');
      expect(h, contains('srvDeletionBarrierExistsInTx(tx, recipientUid)'));
      // accountStatus·user 문서 존재·role·fcmToken 은 근거가 아니다.
      for (final bad in [
        'accountStatus',
        'userSnap',
        '.exists',
        'fcmToken',
        'role',
      ]) {
        expect(h, isNot(contains(bad)), reason: '$bad 을 근거로 쓰면 안 된다');
      }
    });

    test('NOTIF-AUTH-02 suppression 은 오류가 아니다 (§21·§28)', () {
      final h = _helper(raw, 'srvPersistNotificationWithId');
      expect(_flat(h), contains('suppressed: !created'));
      expect(h, isNot(contains('throw new HttpsError')));
    });

    test('NOTIF-AUTH-03 random id 의미를 보존한다 (§14)', () {
      final h = _helper(raw, 'srvPersistNotificationWithId');
      expect(_flat(h), contains('notificationId ? col.doc(notificationId) : col.doc()'));
      final thin = _helper(raw, 'srvPersistNotification');
      expect(_flat(thin),
          contains('srvPersistNotificationWithId(recipientUid, null, payload)'));
    });

    test('NOTIF-AUTH-04 결정적 id 의 중복 방지 의미를 보존한다 (§15·§16·§55)', () {
      // `create` 는 문서가 이미 있으면 ALREADY_EXISTS(code 6)로 실패한다.
      // set/merge 로 바꾸면 기존 dedupe 계약이 깨진다.
      final h = _helper(raw, 'srvPersistNotificationWithId');
      expect(h, contains('tx.create(ref, payload)'));
      expect(h, isNot(contains('tx.set(')));
      expect(h, isNot(contains('merge')));
    });

    test('NOTIF-AUTH-05 수신자를 특정할 수 없으면 쓰지 않는다', () {
      final h = _flat(_helper(raw, 'srvPersistNotificationWithId'));
      expect(h, contains('recipientUid.includes("/")'));
      expect(h, contains('return {created: false, suppressed: true, notificationId: null};'));
    });
  });

  group('NOTIF-TX — 원자성 (§17·§18·§19)', () {
    test('NOTIF-TX-01 barrier read 와 create 가 같은 transaction 이다', () {
      final h = _helper(raw, 'srvPersistNotificationWithId');
      final tx = _txBlock(h, 'srvDeletionBarrierExistsInTx');
      expect(tx, contains('srvDeletionBarrierExistsInTx(tx, recipientUid)'));
      expect(tx, contains('tx.create(ref, payload)'));
      expect(_at(tx, 'srvDeletionBarrierExistsInTx'),
          lessThan(_at(tx, 'tx.create(ref, payload)')));
    });

    test('NOTIF-TX-02 transaction 밖 precheck 를 authority 로 쓰지 않는다', () {
      // [R7-P4.4E.11C.0C 갱신] 상수 선언 + ensure helper + in-tx helper +
      //   삭제 재개 상태 질의(읽기 전용) = 4. 알림 생성 경로는 여전히
      //   in-tx helper 하나만 쓴다.
      // [R7-P4.4E.11C.0C.1 갱신] + Final 의 Auth-tail 증거 읽기 = 5.
      expect(_count(code, 'ACCOUNT_DELETION_TOMBSTONE_COL'), 5);
      expect(_fn(raw, 'callableGetAccountDeletionRecoveryState'),
          isNot(contains('srvPersistNotification')));
      final h = _helper(raw, 'srvDeletionBarrierExistsInTx');
      expect(h, contains('await tx.get('));
      expect(h, isNot(contains('catch')));
    });

    test('NOTIF-TX-03 barrier 읽기 실패를 "수신 가능"으로 바꾸지 않는다 (§20)', () {
      final h = _flat(_helper(raw, 'srvDeletionBarrierExistsInTx'));
      // 형식 이상 → fail-closed(true). 읽기 실패는 throw 되어 호출부로 간다.
      expect(h, contains('return true;'));
      expect(h.indexOf('return true;'), lessThan(h.indexOf('await tx.get(')));
    });
  });

  group('NOTIF-WAGE — 확정된 BLOCKER 경로 (§10·§41·§42)', () {
    test('NOTIF-WAGE-01 srvNotifyWageEvent 가 canonical helper 를 거친다', () {
      final h = _helper(raw, 'srvNotifyWageEvent');
      expect(h, contains('srvPersistNotificationWithId(r.userId,'));
      // 직접 쓰기가 남아 있지 않다.
      expect(h, isNot(contains('collection("notifications")')));
    });

    test('NOTIF-WAGE-02 결정적 id 와 code 6 처리가 그대로다', () {
      final h = _helper(raw, 'srvNotifyWageEvent');
      expect(_flat(h),
          contains(r'`${idPrefix}_${r.attendanceId}_${r.userId}`'));
      expect(_flat(h), contains(r'if ((r.reason as {code?: number})?.code === 6) return;'));
    });

    test('NOTIF-WAGE-03 급여 truth 는 바뀌지 않았다 (§43)', () {
      // 알림 억제가 근태·이체 상태를 건드리지 않는다.
      final h = _helper(raw, 'srvNotifyWageEvent');
      for (final bad in ['wageStatus', 'finalWage', 'transferredAt']) {
        expect(h, isNot(contains(bad)));
      }
    });
  });

  group('NOTIF-FAN — fanout 은 수신자별 독립 (§33·§34·§59)', () {
    test('NOTIF-FAN-01 createNotification fanout 이 helper 를 거친다', () {
      final f = _fn(raw, 'createNotification');
      expect(_flat(f), contains('newRecipients.map((subAdminUid) => srvPersistNotification('));
      // batch 직접 쓰기가 사라졌다.
      expect(f, isNot(contains('batch.set(ref,')));
    });

    test('NOTIF-FAN-02 한 수신자 억제가 전체를 실패시키지 않는다', () {
      final f = _fn(raw, 'createNotification');
      expect(f, contains('Promise.allSettled'));
      expect(_flat(f), contains('suppressed=\${fanoutSuppressed}'));
    });

    test('NOTIF-FAN-03 primary recipient 도 같은 authority 를 거친다 (§32)', () {
      final f = _fn(raw, 'createNotification');
      expect(f, contains('await srvPersistNotification(userId, payload)'));
    });

    test('NOTIF-FAN-04 관리자 다중 수신 transaction 이 수신자별로 판정한다', () {
      // D-15 계약 만료 알림 — marker 결합을 유지한 채 같은 TX 에서 수신자별
      // barrier 를 읽는다. 모든 읽기가 쓰기보다 앞이어야 하므로 루프 밖에서
      // 한 번에 읽는다.
      final sched = _between(
          code, 'async function processContractRenewalChecks', 'export const');
      expect(_flat(sched), contains(
          'adminIds.map((adminId) => srvDeletionBarrierExistsInTx(tx, adminId))'));
      expect(_flat(sched), contains('if (adminBlocked[i]) continue;'));
    });

    test('NOTIF-FAN-05 SubAdmin 권한 정책은 바뀌지 않았다 (§60·§61)', () {
      final f = _fn(raw, 'createNotification');
      expect(f, contains('getSubAdminsWithPermission(fanoutBizId, requiredPerm)'));
      expect(f, contains('!bizAdminIds.includes(id)'));
    });
  });

  group('NOTIF-EMIT — emitter family 대표 (§40·§78)', () {
    test('NOTIF-EMIT-01 대표 emitter 들이 canonical helper 를 거친다', () {
      // application · contract · schedule · termination/resignation ·
      // review · scheduler · ID-card/member 각 하나씩.
      final reps = <String, String>{
        'callableApplyToTO': 'srvPersistNotification(',
        'callableFinalizeEmployerSignature': 'srvPersistNotification',
        'callableApproveScheduleChangeRequest': 'srvPersistNotification(',
        'callableApproveTermination': 'srvPersistNotification(',
        'callableApproveResignation': 'srvPersistNotification(',
        'callableRespondIdCardAccessRequest': 'srvPersistNotification(',
        'callableAcceptInvitation': 'srvPersistNotification(',
        'callableInviteWorker': 'srvPersistNotification',
      };
      reps.forEach((fnName, needle) {
        expect(_fn(raw, fnName), contains(needle),
            reason: '$fnName 이 canonical helper 를 거치지 않는다');
      });
    });

    test('NOTIF-EMIT-02 scheduler 계열도 helper 를 거친다', () {
      final rev = _helper(raw, '_sendReviewRequestNotification');
      expect(rev, contains('srvPersistNotification('));
      final match = _between(
          code, 'async function _dispatchToMatchNotifications', '\n}');
      expect(match, contains('srvPersistNotificationWithId(uid,'));
    });

    test('NOTIF-EMIT-03 payload field 가 유실되지 않았다 (§79)', () {
      // prefix 만 치환했으므로 payload literal 은 그대로여야 한다.
      final h = _helper(raw, 'srvNotifyWageEvent');
      // `body` 는 위에서 계산해 shorthand(`body,`)로 넘긴다 — `body:` 가 아니다.
      for (final k in ['userId:', 'type:', 'title:', 'body,', 'data:',
        'category:', 'isRead:', 'createdAt:']) {
        expect(h, contains(k), reason: '$k 가 사라졌다');
      }
    });
  });

  group('NOTIF-BYPASS — raw writer 가 남지 않았다 (§84·§86·§87)', () {
    test('NOTIF-BYPASS-01 직접 쓰는 자리는 허용 목록뿐이다', () {
      final sites = _rawNotificationWrites(raw);
      final fns = sites.map((s) => s.fn).toSet();
      // 허용: canonical helper 자신 · FCM 플래그 update · 같은 transaction
      // 안에서 barrier 를 읽는 세 자리.
      expect(fns, {
        'srvPersistNotificationWithId',
        'onNotificationCreated',
        'sendWorkReminders',
        'processContractRenewalChecks',
      }, reason: '새 raw notification writer 가 생겼다: ${sites.map((s) => "${s.fn}@${s.line}").toList()}');
    });

    test('NOTIF-BYPASS-02 허용된 in-TX 자리는 같은 TX 에서 barrier 를 읽는다', () {
      // sendWorkReminders
      final wr = _between(code, 'async function sendWorkReminders', '\n}');
      final wrTx = _txBlock(wr, 'srvDeletionBarrierExistsInTx(tx, userId)');
      expect(wrTx, contains('tx.set(notifRef,'));
      expect(_at(wrTx, 'srvDeletionBarrierExistsInTx'),
          lessThan(_at(wrTx, 'tx.set(notifRef,')));

      // processContractRenewalChecks — 두 자리 모두
      final pc = _between(
          code, 'async function processContractRenewalChecks', 'export const');
      expect(_count(pc, 'srvDeletionBarrierExistsInTx(tx,'), 2);
      expect(pc, isNot(contains('await notifRef.create(')));
    });

    test('NOTIF-BYPASS-03 onNotificationCreated 는 create 가 아니다', () {
      final f = _fn(raw, 'onNotificationCreated');
      expect(f, contains('notifRef.update('));
      expect(f, isNot(contains('notifRef.create(')));
      expect(f, isNot(contains('notifRef.set(')));
    });

    test('NOTIF-BYPASS-04 batch 직접 쓰기가 사라졌다', () {
      for (final bad in [
        'cancelBatch.set(',
        'contractBatch.set(notifRef',
        'reminderBatch.set(notifRef',
      ]) {
        expect(code, isNot(contains(bad)), reason: '$bad 가 남아 있다');
      }
    });
  });

  group('NOTIF-TRIG — trigger 가 삭제된 문서를 되살리지 않는다 (§45·§46)', () {
    test('NOTIF-TRIG-01 fcmSent 기록은 update 뿐이다', () {
      final f = _fn(raw, 'onNotificationCreated');
      expect(_flat(f), contains('await notifRef.update({ fcmSent: true,'));
      // set merge 로 바꾸면 삭제된 문서가 되살아난다.
      expect(f, isNot(contains('{merge: true}')));
    });

    test('NOTIF-TRIG-02 문서가 없으면 발송하지 않는다', () {
      final f = _fn(raw, 'onNotificationCreated');
      expect(_flat(f), contains('if (!doc.exists) return true;'));
    });
  });

  group('NOTIF-REG — 기존 계약 회귀', () {
    test('NOTIF-REG-01 createNotification 반환 스키마가 유지된다 (§30)', () {
      final f = _fn(raw, 'createNotification');
      expect(f, contains('return {id: persisted.notificationId};'));
      // 새 상태값을 노출하지 않는다(§29).
      for (final bad in ['ACCOUNT_DELETED', 'DELETING_USER', 'TOMBSTONED']) {
        expect(f, isNot(contains(bad)));
      }
    });

    test('NOTIF-REG-02 Final 의 notification cleanup 이 그대로다 (§64·§65·§66)', () {
      final cleanup = _helper(raw, 'srvCleanupDeletionOwnedPersonal');
      expect(cleanup, contains('collection("notifications")'));
      expect(_flat(cleanup), contains('.limit(200)'));
      final residual = _helper(raw, 'srvCountDeletionPersonalResidual');
      expect(residual, contains('collection("notifications")'));
    });

    test('NOTIF-REG-03 dedupe marker family 가 그대로다 (§54)', () {
      for (final marker in [
        'fcmSent',
        'renewalNotifiedAt',
        'terminationCompletionNotifiedAt',
        'reminderSentDate',
        'reconfirmSentAt',
      ]) {
        expect(code, contains(marker), reason: '$marker 가 사라졌다');
      }
    });

    test('NOTIF-REG-04 억제 때 marker 는 세운다 (§56·§57)', () {
      final pc = _between(
          code, 'async function processContractRenewalChecks', 'export const');
      final sup = _between(pc, 'if (blocked) {', 'return "SUPPRESSED";');
      expect(sup, contains('terminationCompletionNotifiedAt: now'));
      // domain truth 는 건드리지 않는다.
      for (final bad in ['status:', 'wageStatus', 'terminationStatus']) {
        expect(sup, isNot(contains(bad)));
      }
    });

    test('NOTIF-REG-05 domain mutation 이 알림 때문에 롤백되지 않는다 (§1·§22·§25)', () {
      // cancelBatch 3곳: 알림은 commit **이후** allSettled 다.
      //
      //   `cancelBatch.commit()` 는 파일 전체에 7곳이다(다른 함수 포함).
      //   그래서 commit 쪽에서 세지 않고, 알림 발송 쪽에서 "바로 앞이
      //   domain commit 인가"를 묻는다 — 그것이 실제 불변식이다.
      final dispatches = RegExp(r'await Promise\.allSettled\(pendingNotifs\.map\(')
          .allMatches(code)
          .toList();
      expect(dispatches.length, 3);
      for (final m in dispatches) {
        final before = code.substring(
            m.start - 120 < 0 ? 0 : m.start - 120, m.start);
        expect(before, contains('await cancelBatch.commit();'),
            reason: '알림 발송이 domain commit 뒤에 와야 한다');
      }
    });

    test('NOTIF-REG-06 FCM-only 경로는 이번 범위가 아니다 (§9·§52)', () {
      // 외국인 승인/거절은 Firestore 문서 없이 직접 FCM 이다 — persistent
      // residue 대상이 아니므로 건드리지 않았다.
      expect(code, contains('sendEachForMulticast'));
    });
  });
}
