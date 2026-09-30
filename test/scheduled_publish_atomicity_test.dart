// [R7-P4.4C.1] 예약 공개 — readiness 를 commit 과 같은 transaction 에서 본다.
//
// ── P4.4C 가 남긴 것 ───────────────────────────────────────────────
//   P4.4C 는 readiness 를 transaction **밖에서** 한 번 확인했다. 그러면
//   확인과 commit 사이에 창이 남는다 — 그 사이 계약서 템플릿이나 사업주
//   날인이 지워져도 그대로 ACTIVE 가 된다(TOCTOU). 근로자에게는 "확정해도
//   계약을 만들 수 없는 공고" 가 열린다.
//
// ── 그리고 내 P4.4C 보고를 정정한다 ────────────────────────────────
//   "scheduler 가 gate 를 부르지 않았다" 는 **부분적으로 틀렸다.**
//   scheduler 에는 자기 손으로 쓴 **부분** readiness 검사가 이미 있었다 —
//   승인 + 등록증(필드 truthy 만, Storage provenance 없음) + 활성 업무.
//   빠져 있던 것은 **계약서 템플릿과 고용주 날인**이고, 게다가 canonical
//   gate 와 **다른 판정 코드**였다. P4.4C 가 그 위에 두 번째 사전 검사를
//   얹어 N+1 이 됐다. 이번에 하나로 합쳤다.
//
// ── 여기서 볼 수 없는 것 ────────────────────────────────────────────
//   실제 transaction interleaving(RACE-A/B 를 동시에 일으키는 것)은
//   Firestore 에뮬레이터가 필요하다. 이 파일은 **read-set 에 들어가는가**를
//   소스 계약으로 고정한다 — 그것이 TOCTOU 를 막는 기제다.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:ALfit/utils/posting_readiness_reason.dart';

String _src(String p) {
  final f = File(p);
  expect(f.existsSync(), isTrue, reason: '$p 를 찾지 못함');
  return f.readAsStringSync().replaceAll('\r\n', '\n');
}

String _fns() => File('functions/src/index.ts').readAsStringSync();

/// `processScheduledPublish` 본문만 자른다.
String _schedBody() {
  final s = _fns();
  final i = s.indexOf('async function processScheduledPublish(');
  expect(i, greaterThan(-1));
  final end = s.indexOf('\nasync function ', i + 10);
  expect(end, greaterThan(i));
  return s.substring(i, end);
}

void main() {
  // ══════════════════════════════════════════════════════════════
  // SCHED-01. 판정 코드가 한 벌이다
  // ══════════════════════════════════════════════════════════════
  group('SCHED-01 canonical 판정 한 벌', () {
    test('SCHED-01a scheduler 가 자기 readiness 판정을 복제하지 않는다', () {
      final body = _schedBody();
      // 예전에는 여기서 직접 workTypes 를 조회하고 license 필드를 truthy 로
      // 봤다 — canonical gate 와 다른 판정이 두 벌 있었다.
      expect(body.contains('bizReadinessMap'), isFalse,
          reason: '손으로 쓴 부분 readiness 가 남아 있으면 canonical 과 또 갈라진다');
      expect(body.contains('hasCanonicalLicense'), isFalse);
      // canonical evaluator 를 쓴다.
      expect(body.contains('evaluatePostingReadinessFirestore('), isTrue);
    });

    test('SCHED-01b evaluator 는 Firestore 축 네 개를 본다', () {
      final s = _fns();
      final i = s.indexOf('async function evaluatePostingReadinessFirestore(');
      expect(i, greaterThan(-1));
      final end = s.indexOf('\ninterface PostingReadinessReader', i);
      expect(end, greaterThan(i));
      final body = s.substring(i, end);
      for (final axis in const [
        'BUSINESS_NOT_APPROVED',
        'NO_ACTIVE_WORK_TYPE',
        'NO_CONTRACT_TEMPLATE',
        'NO_EMPLOYER_SEAL',
      ]) {
        expect(body.contains(axis), isTrue, reason: axis);
      }
      // 등록증은 여기 없다 — Storage 호출이라 read-set 에 못 넣는다.
      expect(body.contains('hasValidBusinessLicense'), isFalse);
      // 그리고 reader 를 주입받는다(db 또는 tx).
      expect(body.contains('reader.getQuery('), isTrue);
      expect(body.contains('reader.getDoc('), isTrue);
    });

    test('SCHED-01c callable gate 도 같은 evaluator 를 쓴다', () {
      final s = _fns();
      final i = s.indexOf('async function assertBusinessPostingReady(');
      final end = s.indexOf('\nfunction postingNotReadyMessage(', i);
      expect(end, greaterThan(i));
      final body = s.substring(i, end);
      expect(body.contains('evaluatePostingReadinessFirestore('), isTrue);
      expect(body.contains('dbReadinessReader'), isTrue);
      // 등록증만 여기서 본다.
      expect(body.contains('hasValidBusinessLicense(bizId, bizData)'), isTrue);
    });
  });

  // ══════════════════════════════════════════════════════════════
  // SCHED-02. read-set — TOCTOU 를 막는 기제
  // ══════════════════════════════════════════════════════════════
  group('SCHED-02 transaction read-set', () {
    late final String body;
    setUpAll(() => body = _schedBody());

    test('SCHED-02a readiness 가 transaction **안에서** 돈다', () {
      final txStart = body.indexOf('await db.runTransaction(async (tx) => {');
      expect(txStart, greaterThan(-1));
      final eval = body.indexOf('evaluatePostingReadinessFirestore(', txStart);
      expect(eval, greaterThan(txStart),
          reason: 'transaction 밖에서 보면 확인과 commit 사이에 창이 남는다');
      expect(body.contains('txReadinessReader(tx)'), isTrue);
    });

    test('SCHED-02b tx reader 가 읽은 문서는 read-set 에 들어간다', () {
      final s = _fns();
      final i = s.indexOf('function txReadinessReader(');
      expect(i, greaterThan(-1));
      final block = s.substring(i, i + 400);
      expect(block.contains('getDoc: (ref) => tx.get(ref)'), isTrue);
      expect(block.contains('getQuery: (q) => tx.get(q)'), isTrue);
    });

    test('SCHED-02c 모든 read 가 write 보다 앞이다', () {
      // Firestore transaction 규칙. readiness read 가 write 뒤로 가면 터진다.
      final eval = body.indexOf('evaluatePostingReadinessFirestore(');
      final firstWrite = body.indexOf('tx.update(');
      expect(eval, greaterThan(-1));
      expect(firstWrite, greaterThan(eval));
    });

    test('SCHED-02d 등록증 축만 transaction 밖이다 — 이유가 적혀 있다', () {
      // Storage 객체 존재는 Firestore read-set 에 넣을 수 없다.
      expect(body.contains('licenseBlockedBizIds'), isTrue);
      final i = body.indexOf('const licenseBlockedBizIds');
      final head = body.substring((i - 900).clamp(0, i), i);
      expect(head.contains('Storage'), isTrue,
          reason: '왜 이 축만 밖인지 근거가 코드에 남아야 한다');
      // 그리고 fail closed — 못 읽으면 공개하지 않는다.
      final tail = body.substring(i, i + 900);
      expect(tail.contains('licenseBlockedBizIds.add(bizId);'), isTrue);
    });
  });

  // ══════════════════════════════════════════════════════════════
  // SCHED-03. per-business fail closed (P4.4C behavior 유지)
  // ══════════════════════════════════════════════════════════════
  group('SCHED-03 그룹 전체를 막지 않는다', () {
    late final String body;
    setUpAll(() => body = _schedBody());

    test('SCHED-03a 사업장별 이유 map 을 만든다', () {
      expect(body.contains('const blockedReasonByBiz = new Map<string, string>();'),
          isTrue);
    });

    test('SCHED-03b 막힌 사업장의 TO 만 건너뛴다', () {
      expect(
          body.contains('blockedReasonByBiz.get(freshData.businessId as string)'),
          isTrue);
      expect(body.contains('continue;'), isTrue);
    });

    test('SCHED-03c readiness 미충족으로 throw 하지 않는다', () {
      // A 가 준비되지 않았다고 B 까지 공개 실패하면 안 된다.
      final loopStart = body.indexOf('for (let bi = 0; bi < groupBizIds.length; bi++)');
      expect(loopStart, greaterThan(-1));
      final loopEnd = body.indexOf('// owner capacity context', loopStart);
      expect(loopEnd, greaterThan(loopStart));
      expect(body.substring(loopStart, loopEnd).contains('throw'), isFalse);
    });

    test('SCHED-03d 상태는 SCHEDULED 그대로 — 자동 마감하지 않는다', () {
      // blocked 분기에서 status/isPublished 를 건드리지 않는다.
      final i = body.indexOf('if (blockedReason) {');
      expect(i, greaterThan(-1));
      final block = body.substring(i, body.indexOf('continue;', i));
      expect(block.contains('isPublished'), isFalse);
      expect(block.contains('status:'), isFalse);
      expect(block.contains('closedAt'), isFalse);
    });
  });

  // ══════════════════════════════════════════════════════════════
  // SCHED-04. 막힌 이유 기록 — 판정과 같은 transaction
  // ══════════════════════════════════════════════════════════════
  group('SCHED-04 blocked 기록', () {
    late final String body;
    setUpAll(() => body = _schedBody());

    test('SCHED-04a 이유를 TO 에 적는다', () {
      expect(body.contains('publishBlockedReason: blockedReason,'), isTrue);
      expect(body.contains('publishBlockedAt: now,'), isTrue);
    });

    test('SCHED-04b 판정과 기록이 같은 transaction 이다', () {
      // 갈라지면 화면이 낡은 이유를 말한다.
      final txStart = body.indexOf('await db.runTransaction(async (tx) => {');
      final write = body.indexOf('publishBlockedReason: blockedReason,');
      expect(write, greaterThan(txStart));
    });

    test('SCHED-04c 같은 이유면 다시 쓰지 않는다', () {
      // 매 tick 마다 같은 값을 쓰면 문서가 계속 흔들린다.
      expect(body.contains('freshData.publishBlockedReason !== blockedReason'),
          isTrue);
    });

    test('SCHED-04d 공개에 성공하면 흔적을 지운다', () {
      final i = body.indexOf('isPublished: true,');
      expect(i, greaterThan(-1));
      final block = body.substring(i, i + 700);
      expect(
          block.contains('publishBlockedReason: '
              'admin.firestore.FieldValue.delete()'),
          isTrue,
          reason: '남겨 두면 이미 해결된 이유를 화면이 계속 말한다');
    });

    test('SCHED-04e 자동 재시도 — 조회 조건이 그대로다', () {
      // 준비를 끝내면 다음 실행에서 다시 잡힌다. 안내 문구가 그것을 약속한다.
      expect(body.contains('.where("publishMode", "==", "scheduled")'), isTrue);
      expect(body.contains('.where("isPublished", "==", false)'), isTrue);
      expect(body.contains('.where("publishAt", "<=", now)'), isTrue);
    });
  });

  // ══════════════════════════════════════════════════════════════
  // VIS-01. 운영자 visibility + 책임 owner
  // ══════════════════════════════════════════════════════════════
  group('VIS-01 blocked visibility', () {
    test('VIS-01a 모델이 이유를 읽는다 (쓰지 않는다)', () {
      final s = _src('lib/models/core/to_model.dart');
      expect(s.contains('final String? publishBlockedReason;'), isTrue);
      expect(
          s.contains("publishBlockedReason: data['publishBlockedReason'] "
              'as String?,'),
          isTrue);
      // 클라이언트가 이 필드를 서버로 되돌려 쓰지 않는다.
      expect(s.contains("'publishBlockedReason':"), isFalse);
    });

    test('VIS-01b 공고 수정 화면이 그 사실을 말한다', () {
      final s =
          _src('lib/screens/business_admin/to_management/edit_to_screen.dart');
      expect(s.contains('_buildPublishBlockedNotice(context)'), isTrue);
      expect(s.contains('PostingNotReady.fromCode(widget.to.publishBlockedReason)'),
          isTrue);
    });

    test('VIS-01c SubAdmin 에게 개인 인감 등록을 지시하지 않는다', () {
      // §8 책임 owner: 고용주 날인 준비는 business.ownerId 쪽이다.
      final notice = const PostingNotReady(PostingNotReadyReason.noEmployerSeal)
          .blockedNotice(canSetUp: false);
      expect(notice.contains('사업장 관리자에게 확인'), isTrue);
      expect(notice.contains('등록해주세요'), isFalse,
          reason: 'SubAdmin 은 사업주 날인을 스스로 등록할 수 없다');
      // setup owner 에게는 다음 처리에서 공개된다고 말한다(자동 재시도 사실).
      final ownerNotice =
          const PostingNotReady(PostingNotReadyReason.noEmployerSeal)
              .blockedNotice(canSetUp: true);
      expect(ownerNotice.contains('다음 예약 처리에서 다시 공개'), isTrue);
    });

    test('VIS-01d 화면이 setup owner 여부로 문구를 가른다', () {
      final s =
          _src('lib/screens/business_admin/to_management/edit_to_screen.dart');
      expect(s.contains('canSetUp: canSetUp'), isTrue);
      expect(s.contains('!context.read<UserProvider>().isSubAdmin'), isTrue);
    });

    test('VIS-01e 다섯 이유 모두 문장이 있고 코드가 새지 않는다', () {
      for (final r in PostingNotReadyReason.values) {
        for (final can in const [true, false]) {
          final m = PostingNotReady(r).blockedNotice(canSetUp: can);
          expect(m.isNotEmpty, isTrue);
          expect(m.contains('POSTING_NOT_READY'), isFalse, reason: '$r');
          expect(m.contains('_'), isFalse, reason: '$r 코드가 그대로 노출됨');
        }
      }
    });

    test('VIS-01f 저장된 코드에서 이유를 만든다 — 모르면 null', () {
      expect(PostingNotReady.fromCode('NO_CONTRACT_TEMPLATE')?.reason,
          PostingNotReadyReason.noContractTemplate);
      expect(PostingNotReady.fromCode('WHAT'), isNull);
      expect(PostingNotReady.fromCode(null), isNull);
      expect(PostingNotReady.fromCode(''), isNull);
    });
  });

  // ══════════════════════════════════════════════════════════════
  // REG-01. 수동 경로 무변경 (§15)
  // ══════════════════════════════════════════════════════════════
  test('REG-01 create / publish / reopen gate 가 그대로다', () {
    final s = _fns();
    for (final fn in const [
      'export const callableCreateTO',
      'export const callablePublishTO',
      'export const callableUpdateTO',
    ]) {
      final i = s.indexOf(fn);
      expect(i, greaterThan(-1), reason: fn);
      final end = s.indexOf('export const', i + 10);
      expect(s.substring(i, end).contains('assertBusinessPostingReady('), isTrue,
          reason: fn);
    }
    // reopen 전용 — 일반 수정은 여전히 gate 없다.
    final ui = s.indexOf('export const callableUpdateTO');
    final ubody = s.substring(ui, s.indexOf('export const', ui + 10));
    final reopen = ubody.indexOf('if (wantsReopen) {');
    expect(ubody.indexOf('assertBusinessPostingReady('), greaterThan(reopen));
  });
}
