// [R7-P4.4C.2A] 계약을 끝까지 만들 수 없는 상태에서 **새 약속을 만들지 않는다.**
//
// ── 남아 있던 구멍 ─────────────────────────────────────────────────
//   P4.4C.2 가 신규 **지원**(=새 관심)을 막았다. 그런데 prerequisite 상실
//   **전에** 이미 들어온 PENDING 은 그대로 있고, 관리자가 그것을 확정하면
//   `CONTRACT_PENDING`(=좌석 점유 = 약속)이 새로 생겼다. 근로자는 확정
//   통보를 받은 뒤 계약 단계에서 막힌다 — 확정 이후에 계약 준비를 다시
//   요구하지 않는다는 정책 위반이다.
//
// ── 무엇을 하지 않았는가 ────────────────────────────────────────────
//   기존 PENDING 을 자동취소하지 않는다(지원 = 관심). 이미 CONFIRMED /
//   CONTRACT_PENDING 인 약속도 풀지 않는다. 공고도 내리지 않는다.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:ALfit/utils/posting_readiness_reason.dart';

String _src(String p) {
  final f = File(p);
  expect(f.existsSync(), isTrue, reason: '$p 를 찾지 못함');
  return f.readAsStringSync().replaceAll('\r\n', '\n');
}

String _fns() => File('functions/src/index.ts').readAsStringSync();

/// `evaluateContractCapability` 본문.
String _capBody() {
  final s = _fns();
  final i = s.indexOf('async function evaluateContractCapability(');
  expect(i, greaterThan(-1));
  final end = s.indexOf('/**\n * [P4.4C.1] 공고를 **새로 낼 수 있는**', i);
  expect(end, greaterThan(i));
  return s.substring(i, end);
}

/// 지정 callable 본문.
String _callable(String name) {
  final s = _fns();
  final i = s.indexOf('export const $name');
  expect(i, greaterThan(-1), reason: name);
  final end = s.indexOf('\nexport const ', i + 10);
  expect(end, greaterThan(i), reason: name);
  return s.substring(i, end);
}

void main() {
  // ══════════════════════════════════════════════════════════════
  // WRITER. CONFIRMED / 약속을 만드는 전이 전수
  // ══════════════════════════════════════════════════════════════
  group('WRITER 약속 생성 전이', () {
    test('WRITER-01 확정은 PENDING → CONTRACT_PENDING 이다', () {
      // 좌석 점유 상태 집합에 CONTRACT_PENDING 이 들어 있으므로, 이 전이가
      // 곧 **새 약속**이다. CONFIRMED 는 계약 서명 뒤에 온다.
      final s = _fns();
      expect(
          s.contains('const CONFIRMED_STATUSES = ["CONFIRMED", '
              '"CONTRACT_PENDING"];'),
          isTrue);
      final c = _callable('callableConfirmApplication');
      expect(c.contains('status: "CONTRACT_PENDING",'), isTrue);
    });

    test('WRITER-02 초대 수락은 INVITED → CONFIRMED 로 바로 간다', () {
      final c = _callable('callableAcceptTOInvitation');
      expect(c.contains('action: "INVITE_ACCEPTED"'), isTrue);
      expect(c.contains('status: "CONFIRMED"'), isTrue);
    });

    test('WRITER-03 서명 후 CONFIRMED 는 gate 대상이 아니다', () {
      // 계약이 이미 존재하므로 그 시점에 계약 능력을 다시 묻지 않는다.
      final c = _callable('callableFinalizeWorkerSignature');
      expect(c.contains('action: "CONTRACT_SIGNED"'), isTrue);
      expect(c.contains('evaluateContractCapability('), isFalse,
          reason: '이미 만들어진 계약을 서명하는 것을 막으면 근로자가 갇힌다');
    });
  });

  // ══════════════════════════════════════════════════════════════
  // CAP. 계약 능력 축 — 추측으로 다섯 축을 복사하지 않았다
  // ══════════════════════════════════════════════════════════════
  group('CAP 계약 능력 축', () {
    late final String body;
    setUpAll(() => body = _capBody());

    test('CAP-01 계약 writer 의존성 세 축만 본다', () {
      expect(body.contains('BUSINESS_NOT_APPROVED'), isTrue);
      expect(body.contains('NO_CONTRACT_TEMPLATE'), isTrue);
      expect(body.contains('NO_EMPLOYER_SEAL'), isTrue);
      expect(body.contains('deactivatedAt'), isTrue);
    });

    test('CAP-02 활성 업무는 보지 않는다 — TO 가 자기 workDetails 를 들고 있다', () {
      expect(body.contains('collection("workTypes")'), isFalse);
      expect(body.contains('NO_ACTIVE_WORK_TYPE'), isFalse);
      // 그 사실의 근거: 계약 snapshot 의 workDetail 이 TO 에서 온다.
      final day = _src(
          'lib/screens/business_admin/dialogs/day_applicants_dialog.dart');
      expect(day.contains('workDetail = to.workDetails'), isTrue);
    });

    test('CAP-03 등록증도 보지 않는다', () {
      expect(body.contains('hasValidBusinessLicense'), isFalse);
      expect(body.contains('BUSINESS_LICENSE_NOT_READY'), isFalse);
    });

    test('CAP-04 공고 readiness 가 이 함수를 재사용한다 — 정책 중복 없음', () {
      final s = _fns();
      final i = s.indexOf('async function evaluatePostingReadinessFirestore(');
      final end = s.indexOf('/** [P4.4C.1] `db` 와 `transaction`', i);
      final posting = s.substring(i, end);
      expect(posting.contains('return evaluateContractCapability('), isTrue);
      // 공고 쪽만 업무 축을 더한다.
      expect(posting.contains('NO_ACTIVE_WORK_TYPE'), isTrue);
      // 템플릿·날인 검사가 두 벌로 복제되지 않았다.
      expect(posting.contains('contract_templates'), isFalse);
      expect(posting.contains('sealBase64'), isFalse);
    });

    test('CAP-05 apply gate 도 같은 함수를 쓴다', () {
      final s = _fns();
      final i = s.indexOf('async function assertBusinessCanAcceptApplications(');
      final body2 = s.substring(i, i + 900);
      expect(body2.contains('evaluateContractCapability('), isTrue);
      expect(body2.contains('contract_templates'), isFalse);
    });
  });

  // ══════════════════════════════════════════════════════════════
  // CONF. 확정 gate — server writer 가 현재 상태를 다시 본다
  // ══════════════════════════════════════════════════════════════
  group('CONF 확정 gate', () {
    late final String c;
    setUpAll(() => c = _callable('callableConfirmApplication'));

    test('CONF-READY-01~03 확정 전에 계약 능력을 본다', () {
      expect(c.contains('const cfmBlocked = await evaluateContractCapability('),
          isTrue);
      expect(c.contains('POSTING_NOT_READY:'), isTrue);
      expect(c.contains('사업장 계약 준비가 완료되지 않아 확정할 수 없습니다'), isTrue);
    });

    test('CONF-RACE-01/02 transaction 안에서 본다 — read-set', () {
      // 확인과 commit 사이에 템플릿·날인이 지워지면 재시도돼야 한다.
      final tx = c.indexOf('await db.runTransaction(async (tx) => {');
      final gate = c.indexOf('evaluateContractCapability(');
      expect(tx, greaterThan(-1));
      expect(gate, greaterThan(tx));
      expect(c.contains('txReadinessReader(tx)'), isTrue);
      expect(c.contains('const cfmBizSnap = await tx.get(cfmBizRef);'), isTrue);
    });

    test('CONF-READY-06 모든 읽기가 쓰기보다 앞이다 — 부분 mutation 없음', () {
      // Firestore transaction 규칙이기도 하고, gate 가 write 뒤에 있으면
      // 이미 좌석을 점유한 뒤에 거부하는 셈이 된다.
      final gate = c.indexOf('evaluateContractCapability(');
      final firstWrite = c.indexOf('tx.update(');
      expect(firstWrite, greaterThan(gate),
          reason: 'gate 가 write 뒤면 실패해도 좌석·카운트가 움직인다');
    });

    test('CONF-READY-05 이미 확정된 약속은 건드리지 않는다', () {
      // gate 는 읽기만 한다. 기존 CONFIRMED/CONTRACT_PENDING 을 풀거나
      // 취소하는 코드가 gate 블록에 없다.
      final i = c.indexOf('// [P4.4C.2A] 새 약속을 만들기 전에');
      expect(i, greaterThan(-1));
      final block = c.substring(i, c.indexOf('// R2. 직렬화 lock', i));
      expect(block.contains('.update('), isFalse);
      expect(block.contains('.set('), isFalse);
      expect(block.contains('.delete('), isFalse);
      // 재시도 경로(이미 CONTRACT_PENDING)는 기존 규칙 그대로다.
      expect(c.contains('if (status === "CONTRACT_PENDING")'), isTrue);
    });

    test('CONF-READY-04 초대 수락도 같은 gate 를 지난다', () {
      final inv = _callable('callableAcceptTOInvitation');
      expect(inv.contains('evaluateContractCapability('), isTrue);
      expect(inv.contains('txReadinessReader(tx)'), isTrue);
      // 이미 CONFIRMED 면 그대로 반환 — 재수락으로 상태를 흔들지 않는다.
      expect(inv.contains('if (freshStatus === "CONFIRMED") return;'), isTrue);
      // 근로자가 누르는 버튼이므로 문구도 근로자 쪽이다.
      expect(inv.contains('지금은 수락할 수 없는 초대예요'), isTrue);
      expect(inv.contains('POSTING_NOT_READY'), isFalse,
          reason: '근로자에게 고용주 설정 코드를 보내지 않는다');
    });
  });

  // ══════════════════════════════════════════════════════════════
  // COPY. 관리자 문구 — 책임 owner + 지원 보존
  // ══════════════════════════════════════════════════════════════
  group('COPY 확정 차단 안내', () {
    test('COPY-01 지원이 유지된다는 사실을 말한다', () {
      for (final r in PostingNotReadyReason.values) {
        for (final can in const [true, false]) {
          final m = PostingNotReady(r).confirmBlockedNotice(canSetUp: can);
          expect(m.contains('지원은 그대로 유지됩니다'), isTrue, reason: '$r/$can');
          expect(m.contains('POSTING_NOT_READY'), isFalse, reason: '$r');
        }
      }
    });

    test('COPY-02 SubAdmin 에게 인감을 등록하라고 하지 않는다', () {
      final sub = const PostingNotReady(PostingNotReadyReason.noEmployerSeal)
          .confirmBlockedNotice(canSetUp: false);
      expect(sub.contains('사업장 관리자에게 확인'), isTrue);
      expect(sub.contains('다시 확정할 수 있어요'), isFalse);
      final owner = const PostingNotReady(PostingNotReadyReason.noEmployerSeal)
          .confirmBlockedNotice(canSetUp: true);
      expect(owner.contains('준비를 완료하면 다시 확정할 수 있어요'), isTrue);
    });

    test('COPY-03 세 안내가 서로 다른 상황을 말한다', () {
      const r = PostingNotReady(PostingNotReadyReason.noContractTemplate);
      final three = {
        r.message,
        r.blockedNotice(canSetUp: true),
        r.confirmBlockedNotice(canSetUp: true),
      };
      expect(three.length, 3, reason: '준비 지시 · 예약 공개 보류 · 확정 차단');
    });

    test('COPY-04 두 확정 화면이 서버 문장을 그대로 띄우지 않는다', () {
      for (final p in const [
        'lib/screens/business_admin/dialogs/day_applicants_dialog.dart',
        'lib/screens/business_admin/dialogs/work_applicants_dialog.dart',
      ]) {
        final s = _src(p);
        expect(s.contains('PostingNotReady.parse(e) case final blocked?'),
            isTrue, reason: p);
        expect(s.contains('blocked.confirmBlockedNotice(canSetUp: canSetUp)'),
            isTrue, reason: p);
      }
    });
  });

  // ══════════════════════════════════════════════════════════════
  // PRESERVE. 실패 시 아무것도 변하지 않는다
  // ══════════════════════════════════════════════════════════════
  test('PRESERVE-01 gate 블록에 자동취소·알림이 없다', () {
    final c = _callable('callableConfirmApplication');
    final i = c.indexOf('// [P4.4C.2A] 새 약속을 만들기 전에');
    final block = c.substring(i, c.indexOf('// R2. 직렬화 lock', i));
    for (final banned in const [
      'autoCancel',
      'CANCELED',
      'sendNotification',
      'fcm',
      'totalConfirmed',
      'confirmedCount',
    ]) {
      expect(block.contains(banned), isFalse, reason: banned);
    }
  });
}
