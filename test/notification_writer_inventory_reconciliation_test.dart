// [R7-P4.4E.11C.0C.0a.5.1] 숫자가 서로 맞지 않았다
//
// `.0a.5` 최종 보고에서 네 분류의 합계가 어긋났다.
//
//   persistent create = 67
//   random 42 + deterministic 25 = 67     ← 이 두 숫자가 실측이 아니었다
//   migrated 64 + raw in-TX 3 = 67
//   coupling: 60 + 5 + 1 + 3 = 69         ← **마이그레이션 전** 수치였다
//
// 합계가 맞지 않는 inventory 는 "새 raw writer 가 없다"를 보증하지 못한다.
// 그래서 이 파일은 숫자를 **소스에서 다시 세고**, 네 분류가 동시에 같아지는지
// 기계적으로 확인한다. 하드코딩한 숫자 하나를 맞추는 테스트가 아니라
// callsite 집합을 비교한다.
//
// 그리고 두 번째 결함 — domain rollback 격리 — 를 field 단위로 고정한다.
//
//   알림은 domain event 의 **파생 결과**다. 알림 저장 실패·중복·tombstone
//   읽기 실패가 지원·확정·계약·근태·급여 같은 canonical business truth 를
//   되돌리면 안 된다.
//
// 고정하는 것
//   INV-SUM-*    네 분류 합계 reconciliation
//   INV-SET-*    source-contract approved set ↔ inventory 1:1
//   INV-DOM-*    domain transaction 3곳의 write field 집합
//   INV-POST-*   post-commit 분리 4곳
//   INV-DUP-*    deterministic ALREADY_EXISTS 가 domain 을 깨지 않는다
//   INV-LOST-*   알림이 유실돼도 domain 상태는 화면에 남는다
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _src(String p) {
  final f = File(p);
  if (!f.existsSync()) throw StateError('소스를 찾지 못했다: $p');
  return f.readAsStringSync();
}

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

/// 앵커를 **포함하는** transaction 콜백 블록 전체.
///
///   끝 경계를 `indexOf('});')` 로 잡으면 안 된다 — 블록 안의 첫
///   `tx.set(ref, {...})` 가 먼저 닫히면서 구간이 잘리고, 그러면 뒤에 오는
///   `tx.update(...)` 를 못 본다. 그래서 `{` 를 세어 균형으로 닫는다.
String _txBlockOf(String src, String anchor) {
  final a = _at(src, anchor);
  final start = src.lastIndexOf('runTransaction(async (tx) => {', a);
  if (start < 0) throw StateError('앵커를 감싸는 transaction 이 없다: $anchor');
  final open = src.indexOf('{', start);
  var depth = 0;
  for (var i = open; i < src.length; i++) {
    final c = src[i];
    if (c == '{') depth++;
    if (c == '}') {
      depth--;
      if (depth == 0) return src.substring(start, i + 1);
    }
  }
  throw StateError('transaction 끝을 찾지 못함: $anchor');
}

// ─── canonical inventory 분류기 ─────────────────────────────────────────

class _Site {
  _Site(this.line, this.fn, this.shape, this.path, this.coupling);
  final int line;
  final String fn;

  /// `random` | `deterministic`
  final String shape;

  /// `helper` | `raw-in-TX`
  final String path;

  /// `standalone` | `notification-only-fanout` |
  /// `post-commit-separated` | `domain-transaction`
  final String coupling;
}

class _NonCreate {
  _NonCreate(this.line, this.fn, this.kind);
  final int line;
  final String fn;

  /// 왜 CREATE 가 아닌가
  final String kind;
}

class _Inventory {
  _Inventory(this.creates, this.nonCreates);
  final List<_Site> creates;
  final List<_NonCreate> nonCreates;
}

const _postCommitFns = {
  'processWorkDetailExpiry',
  'processSlotWorkDetailExpiry',
  'processTOExpiry',
};

String _enclosingFn(List<String> lines, int i) {
  final re = RegExp(r'^(?:export const (\w+)|async function (\w+)|function (\w+))');
  for (var k = i; k >= 0; k--) {
    final m = re.firstMatch(lines[k]);
    if (m != null) {
      return m.group(1) ?? m.group(2) ?? m.group(3) ?? '?';
    }
  }
  return '?';
}

String _win(List<String> lines, int i, int n) {
  final end = i + n > lines.length ? lines.length : i + n;
  return lines.sublist(i, end).join(' ').replaceAll(RegExp(r'\s+'), ' ');
}

_Inventory _buildInventory(String raw) {
  final lines = raw.split(RegExp(r'\r?\n'));
  final creates = <_Site>[];
  final nonCreates = <_NonCreate>[];

  // 1) canonical helper 경유
  for (var i = 0; i < lines.length; i++) {
    final l = lines[i];
    if (RegExp(r'^(async )?function srvPersistNotification').hasMatch(l.trim())) {
      continue;
    }
    final fn = _enclosingFn(lines, i);
    if (fn == 'srvPersistNotification' ||
        fn == 'srvPersistNotificationWithId') {
      continue;
    }
    final withId = l.contains('srvPersistNotificationWithId(');
    final plain = l.contains('srvPersistNotification(') && !withId;
    if (!withId && !plain) continue;
    final coupling = fn == 'createNotification'
        ? (l.contains('newRecipients')
            ? 'notification-only-fanout'
            : 'standalone')
        : (_postCommitFns.contains(fn) ? 'post-commit-separated' : 'standalone');
    creates.add(_Site(
        i + 1, fn, withId ? 'deterministic' : 'random', 'helper', coupling));
  }

  // 2) raw callsite + 비-CREATE
  for (var i = 0; i < lines.length; i++) {
    if (!lines[i].contains('collection("notifications")')) continue;
    final fn = _enclosingFn(lines, i);
    if (fn == 'srvPersistNotificationWithId') {
      nonCreates.add(_NonCreate(i + 1, fn, 'HELPER-SELF'));
      continue;
    }
    final w = _win(lines, i, 10);
    final head = w.length > 170 ? w.substring(0, 170) : w;
    if (RegExp(r'\.where\(|\.orderBy\(|\.limit\(\d').hasMatch(head)) {
      nonCreates.add(_NonCreate(i + 1, fn, 'READ'));
      continue;
    }
    if (RegExp(r'collection\("notifications"\);$').hasMatch(lines[i].trim())) {
      nonCreates.add(_NonCreate(i + 1, fn, 'CLEANUP-REF'));
      continue;
    }
    // fcmSent update — 이 ref 로 create/set 을 하지 않는다.
    if (lines[i].contains('.doc(notificationId)')) {
      final fnRe = RegExp(r'^(?:export const \w+|async function \w+|function \w+)');
      var s = 0;
      for (var k = i; k >= 0; k--) {
        if (fnRe.hasMatch(lines[k])) {
          s = k;
          break;
        }
      }
      var e = lines.length;
      for (var k = i + 1; k < lines.length; k++) {
        if (fnRe.hasMatch(lines[k])) {
          e = k;
          break;
        }
      }
      final body = lines.sublist(s, e).join('\n');
      final usesCreate = RegExp(r'notifRef\.(create|set)\(').hasMatch(body);
      final usesUpdate = body.contains('notifRef.update(');
      if (usesUpdate && !usesCreate) {
        nonCreates.add(_NonCreate(i + 1, fn, 'UPDATE-FCMSENT'));
        continue;
      }
    }
    final det = RegExp(r"\.doc\(`|\.doc\('|\.doc\(\x22").hasMatch(w);
    creates.add(_Site(i + 1, fn, det ? 'deterministic' : 'random', 'raw-in-TX',
        'domain-transaction'));
  }

  return _Inventory(creates, nonCreates);
}

Map<String, int> _tally(List<_Site> s, String Function(_Site) key) {
  final t = <String, int>{};
  for (final x in s) {
    t[key(x)] = (t[key(x)] ?? 0) + 1;
  }
  return t;
}

int _sum(Map<String, int> t) => t.values.fold(0, (a, b) => a + b);

void main() {
  final raw = _src('functions/src/index.ts');
  final inv = _buildInventory(raw);

  group('INV-SUM — 네 분류 합계가 동시에 같다', () {
    test('INV-SUM-01 total = shape = path = coupling', () {
      final total = inv.creates.length;
      final shape = _tally(inv.creates, (s) => s.shape);
      final path = _tally(inv.creates, (s) => s.path);
      final coupling = _tally(inv.creates, (s) => s.coupling);
      expect(_sum(shape), total, reason: 'write shape 합계 불일치');
      expect(_sum(path), total, reason: 'persistence path 합계 불일치');
      expect(_sum(coupling), total, reason: 'coupling 합계 불일치');
      // 한 callsite 가 coupling 하나에만 속한다 — 분류가 상호배타임을 보장.
      expect(coupling.keys.toSet(), {
        'standalone',
        'notification-only-fanout',
        'post-commit-separated',
        'domain-transaction',
      });
    });

    test('INV-SUM-02 persistence path 는 helper 와 승인된 raw-in-TX 뿐이다', () {
      final path = _tally(inv.creates, (s) => s.path);
      expect(path.keys.toSet(), {'helper', 'raw-in-TX'});
      // raw-in-TX 는 coupling 상 반드시 domain-transaction 이다.
      for (final s in inv.creates.where((s) => s.path == 'raw-in-TX')) {
        expect(s.coupling, 'domain-transaction',
            reason: 'L${s.line} ${s.fn} 의 raw 쓰기가 transaction 밖이다');
      }
    });

    test('INV-SUM-03 비-CREATE 는 근거와 함께 분류돼 있다', () {
      // read / cleanup ref / fcmSent update / helper 자신 — 이 넷만 허용.
      final kinds = inv.nonCreates.map((n) => n.kind).toSet();
      expect(kinds.difference({
        'READ',
        'CLEANUP-REF',
        'UPDATE-FCMSENT',
        'HELPER-SELF',
      }), isEmpty, reason: '분류되지 않은 notifications 참조가 있다');
      // fcmSent update 는 정확히 한 곳(trigger)이다.
      expect(
          inv.nonCreates.where((n) => n.kind == 'UPDATE-FCMSENT')
              .map((n) => n.fn).toList(),
          ['onNotificationCreated']);
    });

    test('INV-SUM-04 상위 notifications 컬렉션은 서브컬렉션이 아니다', () {
      // `db.collection("notifications")` (users 접두 없음)는 다른 컬렉션이고
      // 이 inventory 대상이 아니다. 한 곳뿐이며 삭제 쿼리다.
      expect(_count(raw, 'db.collection("notifications")'), 1);
      final i = _at(raw, 'db.collection("notifications")');
      // 고정폭 창을 쓰지 않는다 — 그 while 루프 블록까지만 자른다.
      final seg = _flat(_between(raw.substring(i), '.where("toId"', 'last ='));
      expect(seg, contains('.where("toId", "=="'));
      expect(seg, contains('batch.delete(d.ref)'),
          reason: '삭제 쿼리다 — create 가 아니다');
    });
  });

  group('INV-SET — source-contract approved set ↔ inventory 1:1', () {
    test('INV-SET-01 raw 쓰기 함수 집합이 정확히 일치한다', () {
      // `NOTIF-BYPASS-01` 이 고정한 집합 = helper 자신 + fcmSent update +
      //   같은 transaction 에서 barrier 를 읽는 두 함수.
      final approved = {
        'srvPersistNotificationWithId',
        'onNotificationCreated',
        'sendWorkReminders',
        'processContractRenewalChecks',
      };
      final rawCreateFns =
          inv.creates.where((s) => s.path == 'raw-in-TX').map((s) => s.fn).toSet();
      final nonCreateFns = inv.nonCreates
          .where((n) => n.kind == 'HELPER-SELF' || n.kind == 'UPDATE-FCMSENT')
          .map((n) => n.fn)
          .toSet();
      expect(rawCreateFns.union(nonCreateFns), approved,
          reason: 'inventory 와 source-contract approved set 이 어긋났다');
    });

    test('INV-SET-02 누락·중복 counting 이 없다', () {
      // 같은 (line) 이 두 번 세어지지 않는다.
      final lines = inv.creates.map((s) => s.line).toList();
      expect(lines.length, lines.toSet().length, reason: '중복 counting');
      final nonLines = inv.nonCreates.map((n) => n.line).toList();
      expect(nonLines.length, nonLines.toSet().length);
      // CREATE 와 비-CREATE 가 같은 줄을 공유하지 않는다.
      expect(lines.toSet().intersection(nonLines.toSet()), isEmpty);
    });

    test('INV-SET-03 helper 호출 수가 소스 호출 수와 맞는다', () {
      // 선언 1 + thin wrapper 내부 호출 1 을 제외한 수가 inventory 와 같다.
      final withIdCalls = _count(raw, 'srvPersistNotificationWithId(') - 2;
      // `srvPersistNotification(` 는 `...WithId(` 를 포함하지 않는다
      //   (서로 다른 문자열). 그래서 빼지 않는다 — 선언 1 만 뺀다.
      final plainCalls = _count(raw, 'srvPersistNotification(') - 1;
      final det = inv.creates
          .where((s) => s.path == 'helper' && s.shape == 'deterministic')
          .length;
      final rnd = inv.creates
          .where((s) => s.path == 'helper' && s.shape == 'random')
          .length;
      expect(det, withIdCalls);
      expect(rnd, plainCalls);
    });
  });

  group('INV-DOM — domain transaction 3곳의 write field 집합', () {
    /// 그 transaction 의 **알림 외** write 들이 허용된 marker field 뿐인가.
    void expectMarkerOnly(String tx, Set<String> allowedFields) {
      final updates = RegExp(r'tx\.update\(([^,]+), \{([^}]*)\}\)')
          .allMatches(_flat(tx));
      expect(updates, isNotEmpty, reason: 'marker write 가 없다');
      for (final m in updates) {
        final fields = m
            .group(2)!
            .split(',')
            .map((s) => s.trim().split(':').first.trim())
            .where((s) => s.isNotEmpty)
            .toSet();
        expect(fields.difference(allowedFields), isEmpty,
            reason: 'domain business truth 를 같은 transaction 에서 쓴다: $fields');
      }
      // canonical business truth field 가 없다.
      for (final bad in [
        'status:',
        'wageStatus',
        'terminationStatus',
        'resignStatus',
        'renewalDecision',
        'finalWage',
        'confirmedAt',
        'canceledAt',
        'cancelReason',
      ]) {
        expect(tx, isNot(contains(bad)),
            reason: '$bad 가 알림과 같은 transaction 에 있다');
      }
    }

    test('INV-DOM-01 sendWorkReminders — reminderSentDate 뿐이다', () {
      final tx = _txBlockOf(raw, 'srvDeletionBarrierExistsInTx(tx, userId)');
      expect(tx, contains('tx.set(notifRef,'));
      expectMarkerOnly(tx, {'reminderSentDate'});
    });

    test('INV-DOM-02 D-15 — renewalNotifiedAt 뿐이다', () {
      final tx = _txBlockOf(raw, 'srvDeletionBarrierExistsInTx(tx, adminId)');
      expect(tx, contains('tx.set(notifRef,'));
      expectMarkerOnly(tx, {'renewalNotifiedAt'});
    });

    test('INV-DOM-03 D-0 — terminationCompletionNotifiedAt 뿐이다', () {
      final tx = _txBlockOf(
          raw, 'srvDeletionBarrierExistsInTx(tx, freshData.uid as string)');
      expect(tx, contains('tx.set(notifRef,'));
      expectMarkerOnly(tx, {'terminationCompletionNotifiedAt'});
    });

    test('INV-DOM-04 세 곳 모두 barrier read 가 모든 write 보다 앞이다', () {
      // Firestore 는 transaction 안에서 모든 읽기가 모든 쓰기보다 앞이어야
      // 한다. 다중 수신자 자리는 루프 밖에서 한 번에 읽는다.
      for (final anchor in [
        'srvDeletionBarrierExistsInTx(tx, userId)',
        'srvDeletionBarrierExistsInTx(tx, adminId)',
        'srvDeletionBarrierExistsInTx(tx, freshData.uid as string)',
      ]) {
        final tx = _txBlockOf(raw, anchor);
        final firstWrite = [
          tx.indexOf('tx.set('),
          tx.indexOf('tx.update('),
          tx.indexOf('tx.create('),
        ].where((i) => i >= 0).reduce((a, b) => a < b ? a : b);
        expect(_at(tx, 'srvDeletionBarrierExistsInTx'), lessThan(firstWrite),
            reason: '$anchor — 읽기가 쓰기 뒤에 있다');
      }
    });
  });

  group('INV-DUP — deterministic 중복이 domain 을 깨지 않는다', () {
    test('INV-DUP-01 domain transaction 의 알림은 set(random)이다', () {
      // `create` 는 문서가 이미 있으면 ALREADY_EXISTS(6)로 **commit 전체**를
      // 실패시킨다. 그 transaction 에 marker write 가 같이 있으므로, 알림
      // 중복이 marker 갱신까지 되돌리면 스케줄러가 영원히 재시도한다.
      // 그래서 이 세 자리는 random id + `set` 이다 — 중복이 구조적으로 없다.
      for (final anchor in [
        'srvDeletionBarrierExistsInTx(tx, userId)',
        'srvDeletionBarrierExistsInTx(tx, adminId)',
        'srvDeletionBarrierExistsInTx(tx, freshData.uid as string)',
      ]) {
        final tx = _txBlockOf(raw, anchor);
        expect(tx, contains('tx.set('), reason: anchor);
        expect(tx, isNot(contains('tx.create(')),
            reason: '$anchor — create 면 중복이 marker 까지 abort 한다');
      }
      // 세 ref 는 transaction **밖에서** random id 로 미리 만든다
      //   (`.doc()` 인자 없음) — 결정적 id 가 아니므로 중복 자체가 없다.
      expect(_flat(raw), contains(
          'const notifRef = db.collection("users").doc(userId)'
          '.collection("notifications").doc();'));
      expect(_flat(raw), contains(
          'const notifRefs = adminIds.map((adminId) => '
          'db.collection("users").doc(adminId).collection("notifications").doc()'));
    });

    test('INV-DUP-02 helper 의 create 는 domain write 가 없는 transaction 이다', () {
      // 결정적 id 19곳은 helper 를 거친다. helper 의 transaction 에는
      // 알림 create 하나만 있으므로, ALREADY_EXISTS 는 그 알림 transaction만
      // 실패시킨다 — 어떤 business mutation 도 되돌리지 않는다.
      final hi = _at(raw, 'async function srvPersistNotificationWithId(');
      final body = raw.substring(hi, raw.indexOf('\n}', hi));
      final tx = _between(body, 'runTransaction(async (tx) => {', '});');
      expect(tx, contains('tx.create(ref, payload)'));
      // 그 transaction 의 write 는 알림 하나뿐이다.
      expect(_count(tx, 'tx.create('), 1);
      expect(_count(tx, 'tx.set('), 0);
      expect(_count(tx, 'tx.update('), 0);
      expect(_count(tx, 'tx.delete('), 0);
    });

    test('INV-DUP-03 호출부의 code 6 처리가 그대로다', () {
      // 결정적 id 호출부는 ALREADY_EXISTS 를 "이미 보냈다"로 읽는다.
      // helper 가 그 오류를 그대로 전파하므로 계약이 유지된다.
      final h = _at(raw, 'async function srvNotifyWageEvent');
      final body = raw.substring(h, raw.indexOf('\n}', h));
      expect(_flat(body),
          contains(r'if ((r.reason as {code?: number})?.code === 6) return;'));
    });
  });

  group('INV-POST — post-commit 분리 4곳', () {
    test('INV-POST-01 알림 발송이 domain commit 뒤에 있다', () {
      final dispatches = <String>[
        'await Promise.allSettled(pendingNotifs.map(',
        'await Promise.allSettled(expiryNotifs.map(',
      ];
      // pendingNotifs 3곳 + expiryNotifs 1곳 = 4.
      expect(_count(raw, dispatches[0]), 3);
      expect(_count(raw, dispatches[1]), 1);
      for (final d in dispatches) {
        var i = 0;
        while (true) {
          final k = raw.indexOf(d, i);
          if (k < 0) break;
          final before = raw.substring(k - 160 < 0 ? 0 : k - 160, k);
          expect(before, contains('.commit();'),
              reason: '알림 발송이 domain commit 뒤에 와야 한다');
          i = k + d.length;
        }
      }
    });

    test('INV-POST-02 batch 안에 알림 쓰기가 남아 있지 않다', () {
      for (final bad in [
        'cancelBatch.set(',
        'contractBatch.set(notifRef',
        'reminderBatch',
      ]) {
        expect(raw, isNot(contains(bad)), reason: '$bad 가 남아 있다');
      }
    });

    test('INV-POST-03 domain batch 는 business truth 를 그대로 쓴다', () {
      // 분리로 domain 쪽이 약해지지 않았음을 확인한다.
      expect(_flat(raw), contains('cancelBatch.update(appDoc.ref, { status: "AUTO_CANCELED",'));
      expect(_flat(raw), contains('contractBatch.update(doc.ref, { status: "CLOSED",'));
    });
  });

  group('INV-LOST — 알림이 유실돼도 domain 상태는 화면에 남는다', () {
    test('INV-LOST-01 자동취소 세 사유가 「내 지원」에 문장으로 있다', () {
      final s = _src('lib/screens/user/my_applications_screen.dart');
      for (final r in [
        'WORK_DETAIL_EXPIRED',
        'SLOT_WORK_DETAIL_EXPIRED',
        'TO_EXPIRED',
      ]) {
        expect(s, contains("case '$r':"),
            reason: '$r 이 사용자에게 설명되지 않는다');
      }
    });

    test('INV-LOST-02 CLOSED 공고가 관리자 목록 탭에 있다', () {
      final s = _src('lib/screens/business_admin/widgets/to_list_tab_bar.dart');
      expect(s, contains('TOStatus.closed'));
    });
  });
}
