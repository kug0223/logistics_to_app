// [PII-DOC-R1.5.5] BANK MUTATION / VERSION / RULES INTEGRITY
//
// 이 파일이 고정하는 것:
//
//   VS   계좌·통장사본을 바꾸는 writer 는 같은 version semantics 를 쓴다.
//   DL   삭제는 두 canonical state 를 모두 바꾸므로 두 버전을 올린다.
//   GQ   없는 문서는 검토 대기 항목이 아니다 (ghost queue 없음).
//   WG   계좌 없음은 검토 통과가 아니다 (급여 확정 침묵 경로 차단).
//   RL   canonical state 는 client SDK 직접 쓰기로 바뀌지 않는다.
//   LB   writer 없는 필드로 "확인 완료"를 말하지 않는다.
//   KP   R1.5.4 onboarding · R1.5.3 재배치 · 이체 fail-closed 유지.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _src(String p) {
  final f = File(p);
  if (!f.existsSync()) throw StateError('$p 를 찾지 못함');
  return f.readAsStringSync();
}

String _codeOf(String b) =>
    b.split('\n').where((l) => !l.trimLeft().startsWith('//')).join('\n');

String _flat(String b) => b.replaceAll(RegExp(r'\s+'), ' ');

String _sliceOf(String raw, String from, String to) {
  final a = raw.indexOf(from);
  if (a < 0) throw StateError('$from 를 찾지 못함');
  final b = raw.indexOf(to, a + from.length);
  if (b < 0) throw StateError('$to 를 찾지 못함');
  return raw.substring(a, b);
}

const _cfPath = 'functions/src/index.ts';
const _rulesPath = 'firestore.rules';
const _docsPath = 'lib/screens/common/document_management_screen.dart';

/// canonical state 로 취급하는 users 필드 — client SDK 직접 쓰기 금지 대상.
const _serverOwned = [
  'bankName', 'accountNumber', 'accountHolder',
  'bankbookImagePath', 'bankbookImageUrl',
  'bankAccountVersion', 'bankbookDocumentVersion', 'idDocumentVersion',
  'bankbookMatchStatus', 'bankbookMatchEvidenceSource',
  'bankbookMatchAssurance', 'bankbookMatchDocumentVersion',
  'bankbookMatchAccountVersion', 'bankbookMatchEvaluatedAt',
  'idCardMatchStatus', 'idCardMatchEvidenceSource',
  'idCardMatchAssurance', 'idCardMatchDocumentVersion',
  'idCardMatchEvaluatedAt',
  'bankVerificationStatus', 'bankbookUploadedAt',
  'bankbookDocumentState', 'idCardDocumentState',
];

void main() {
  final rawCf = _src(_cfPath);
  final del = _codeOf(_sliceOf(rawCf,
      'export const callableDeleteBankInfo = onCall(', '\n);'));
  final upd = _codeOf(_sliceOf(rawCf,
      'export const callableUpdateBankAccount = onCall(', '\n);'));
  final markBb = _codeOf(_sliceOf(rawCf,
      'export const callableMarkBankbookVerified = onCall(', '\n);'));
  final rules = _src(_rulesPath);

  // ── DL. 삭제 semantics ──────────────────────────────────────────
  group('DL — 삭제는 두 canonical state 를 모두 바꾼다', () {
    test('01 V1 — 두 버전을 함께 올린다', () {
      expect(_flat(del), contains(
          'bankAccountVersion: admin.firestore.FieldValue.increment(1)'));
      expect(_flat(del), contains(
          'bankbookDocumentVersion: admin.firestore.FieldValue.increment(1)'));
    });

    test('02 계좌·통장사본 실체를 지운다', () {
      for (final f in ['bankName', 'accountNumber', 'accountHolder',
        'bankbookImagePath', 'bankbookImageUrl']) {
        expect(_flat(del),
            contains('$f: admin.firestore.FieldValue.delete()'), reason: f);
      }
    });

    test('03 V3 — 그 문서에 대한 자동 판정도 함께 지운다', () {
      for (final f in ['bankbookMatchStatus', 'bankbookMatchEvidenceSource',
        'bankbookMatchAssurance', 'bankbookMatchDocumentVersion',
        'bankbookMatchAccountVersion', 'bankbookMatchEvaluatedAt']) {
        expect(_flat(del),
            contains('$f: admin.firestore.FieldValue.delete()'), reason: f);
      }
    });

    test('04 단일 원자 쓰기다 — 버전과 내용이 갈라지지 않는다', () {
      final updates = RegExp(r'\.update\(').allMatches(del).length;
      expect(updates, 1, reason: '두 번 쓰면 중간 상태가 관측된다');
    });

    test('05 Firestore 를 먼저 쓰고 Storage 는 그 뒤다', () {
      final fs = del.indexOf('.update(');
      final st = del.indexOf('admin.storage()');
      expect(fs, greaterThan(-1));
      expect(st, greaterThan(fs), reason: 'Firestore 실패 시 Storage 는 건드리지 않는다');
    });
  });

  // ── VS. writer 간 semantics 일치 ────────────────────────────────
  group('VS — writer 들이 같은 version semantics 를 쓴다', () {
    test('06 §9 — 계좌 변경은 통장사본 참조를 지우므로 두 버전을 올린다', () {
      // 실측 확인: 같은 update 안에서 bankbookImagePath 를 지운다.
      expect(_flat(upd),
          contains('bankbookImagePath: admin.firestore.FieldValue.delete()'));
      expect(_flat(upd), contains(
          'bankAccountVersion: admin.firestore.FieldValue.increment(1)'));
      expect(_flat(upd), contains(
          'bankbookDocumentVersion: admin.firestore.FieldValue.increment(1)'));
    });

    test('07 통장사본 재업로드는 통장사본 버전만 올린다', () {
      // 계좌는 바뀌지 않았으므로 계좌 버전은 읽기만 한다.
      expect(_flat(markBb), contains('bankbookDocumentVersion: nextBb'));
      expect(_flat(markBb), isNot(contains(
          'bankAccountVersion: admin.firestore.FieldValue.increment')));
      expect(_flat(markBb), contains('bankbookMatchAccountVersion: curAcc'));
    });

    test('08 §10 — 계좌 writer 는 replace mutation 이다 (동일값 재제출도 bump)', () {
      // AES-CBC random IV 라 서버가 동일 계좌 재제출을 판별할 수 없다.
      // 그래서 호출 자체를 변경 신호로 본다 — idempotent 가 아니다.
      // (주석에 근거가 남아 있어야 다음 사람이 "중복 bump 버그"로 오해하지 않는다)
      final rawUpd = _sliceOf(rawCf,
          'export const callableUpdateBankAccount = onCall(', '\n);');
      expect(rawUpd, contains('AES-CBC random IV'));
    });

    test('09 계좌 presence 를 바꾸는 writer 는 이 둘뿐이다', () {
      // 읽어서 응답/맵을 만드는 자리(`u["bankName"]`, `d.bankName`)는 제외한다.
      final owners = <String>[];
      final lines = _codeOf(rawCf).split('\n');
      var cur = '<top>';
      for (final l in lines) {
        final m = RegExp(r'^(?:export const|async function|function) (\w+)')
            .firstMatch(l);
        if (m != null) cur = m.group(1)!;
        if (!RegExp(r'^\s*(bankName|accountNumber|accountHolder):').hasMatch(l)) {
          continue;
        }
        final isRead = l.contains('u["') || l.contains('d.bank') ||
            l.contains('d.account') || l.contains('?? null') ||
            l.contains('ub.');
        if (!isRead) owners.add(cur);
      }
      expect(owners.toSet(),
          equals({'callableDeleteBankInfo', 'callableUpdateBankAccount'}),
          reason: '실제 발견: ${owners.toSet()}');
    });
  });

  // ── GQ. ghost review queue ──────────────────────────────────────
  group('GQ — 없는 문서는 검토 대기 항목이 아니다', () {
    test('10 Q1 — 삭제가 검토 큐 키를 함께 지운다', () {
      // 큐는 bankbookDocumentState 로 조회한다.
      final queue = _codeOf(_sliceOf(rawCf,
          'export const callableGetDocumentsPendingReview = onCall(', '\n);'));
      expect(queue, contains('where("bankbookDocumentState", "in", NEEDS_REVIEW)'));
      expect(_flat(del),
          contains('bankbookDocumentState: admin.firestore.FieldValue.delete()'));
    });

    test('11 검토 흔적도 남기지 않는다', () {
      for (final f in ['bankbookSelfCheck', 'bankbookReviewedBy',
        'bankbookReviewedAt', 'bankbookReviewNote',
        'bankReviewedAt', 'bankReviewedBy']) {
        expect(_flat(del),
            contains('$f: admin.firestore.FieldValue.delete()'), reason: f);
      }
    });

    test('12 계좌 변경 writer 와 정리 범위가 같다', () {
      for (final f in ['bankbookDocumentState', 'bankbookSelfCheck',
        'bankReviewedAt', 'bankReviewedBy']) {
        expect(_flat(upd),
            contains('$f: admin.firestore.FieldValue.delete()'), reason: f);
      }
    });
  });

  // ── WG. 급여 확정 ───────────────────────────────────────────────
  group('WG — 계좌 없음은 검토 통과가 아니다', () {
    final wage = _codeOf(_sliceOf(rawCf,
        'export const callableConfirmFinalWage = onCall(',
        'export const callableCancelFinalConfirmation'));

    test('13 W1 — 빈 스냅샷이 "검토 통과"로 읽히지 않는다', () {
      // 조건이 "객체가 있는가"가 아니라 "계좌가 다 있는가"여야 한다.
      expect(_flat(wage), contains(
          'if (!hasFullAccount) { updateData["wageAccountReviewRequired"] = true;'));
      expect(_flat(wage), isNot(contains(
          'if (!accountSnap) { updateData["wageAccountReviewRequired"] = true;')));
    });

    test('14 hasFullAccount 는 3필드 모두를 본다', () {
      final h = _flat(_sliceOf(wage, 'const hasFullAccount =', ');'));
      for (final f in ['wageAccountBankName', 'wageAccountNumberEncrypted',
        'wageAccountHolder']) {
        expect(h, contains(f), reason: f);
      }
    });

    test('15 검토 freshness 는 여전히 버전 비교로 판정한다', () {
      expect(wage, contains('srvResolveReviewReadiness('));
      final rr = _codeOf(
          _sliceOf(rawCf, 'function srvResolveReviewReadiness(', '\n}'));
      expect(rr, contains('rBbV !== cur.bankbook'));
      expect(rr, contains('rAcV !== cur.account'));
    });

    test('16 W2·§16 — 이체는 그대로 fail-closed', () {
      final xfer = _codeOf(
          _sliceOf(rawCf, 'function srvWageAccountBlockReason(', '\n}'));
      expect(xfer, contains('XFER_REVIEW_REQUIRED'));
      expect(xfer, contains('XFER_NO_ACCOUNT_SNAPSHOT'));
      for (final f in ['wageAccountBankName', 'wageAccountNumberEncrypted',
        'wageAccountHolder', 'wageAccountSnapshotAt']) {
        expect(xfer, contains(f), reason: f);
      }
    });
  });

  // ── RL. Firestore Rules ─────────────────────────────────────────
  group('RL — canonical state 는 client 직접 쓰기로 바뀌지 않는다', () {
    final superBlock = _sliceOf(rules,
        '허용(OR)이므로 순서가 보안에는 영향 없음', 'allow update: if isLoggedIn()');
    final ownerBlock = _sliceOf(rules,
        'allow update: if isLoggedIn() &&', 'allow delete:');
    final createBlock = _sliceOf(rules, 'allow create:', 'allow delete:');

    test('17 §13 — SUPER_ADMIN client update 도 막는다', () {
      for (final f in _serverOwned) {
        expect(superBlock, contains("'$f'"), reason: 'SUPER_ADMIN 차단 목록에 $f');
      }
    });

    test('18 본인 update 차단은 그대로다', () {
      for (final f in _serverOwned) {
        expect(ownerBlock, contains("'$f'"), reason: '본인 차단 목록에 $f');
      }
    });

    test('19 §12 — CREATE 시 버전·판정 주입 차단', () {
      for (final f in [
        'bankAccountVersion', 'bankbookDocumentVersion', 'idDocumentVersion',
        'bankbookMatchDocumentVersion', 'bankbookMatchAccountVersion',
        'idCardMatchDocumentVersion',
        'bankbookMatchStatus', 'idCardMatchStatus',
        'bankbookImagePath', 'bankbookImageUrl',
        'bankbookDocumentState', 'idCardDocumentState',
        'bankbookSelfCheck', 'idCardSelfCheck',
      ]) {
        expect(createBlock, contains("request.resource.data.get('$f', null) == null"),
            reason: 'CREATE 차단에 $f');
      }
    });

    test('20 버전 필드는 클라이언트 모델이 write 하지 않는다', () {
      // toMap 에 없어야 CREATE 규칙과 충돌하지 않는다.
      final model = _src('lib/models/core/user_model.dart');
      final toMap = _sliceOf(model, 'Map<String, dynamic> toMap()', '\n  }');
      for (final f in ['bankAccountVersion', 'bankbookDocumentVersion',
        'idDocumentVersion', 'bankbookMatchStatus', 'idCardMatchStatus']) {
        expect(toMap, isNot(contains("'$f'")), reason: f);
      }
    });
  });

  // ── LB. legacy badge ────────────────────────────────────────────
  group('LB — writer 없는 필드로 확인을 주장하지 않는다', () {
    test('21 §24 — 서류관리에 bankVerificationStatus reader 가 없다', () {
      // 남은 것은 설명 주석뿐이어야 한다 — 실제 필드 접근이 없어야 한다.
      expect(_src(_docsPath), isNot(contains('user.bankVerificationStatus')));
      expect(_src(_docsPath), isNot(contains(".bankVerificationStatus ==")));
    });

    test('22 급여계좌 섹션이 사실만 말한다', () {
      final sec = _codeOf(_sliceOf(_src(_docsPath),
          'Widget _buildBankInfoSection(', '\n  }'));
      for (final banned in ['확인 완료', '제출 완료', '확인 필요',
        '계좌 인증 완료', '금융기관 확인 완료', '지급 준비 완료']) {
        expect(sec, isNot(contains(banned)), reason: banned);
      }
      expect(sec, contains('계좌 등록됨'));
    });

    test('23 서버에 writer 가 없다는 사실 자체를 고정한다', () {
      final writes = _codeOf(rawCf)
          .split('\n')
          .where((l) => l.contains('bankVerificationStatus:'))
          .where((l) => !l.contains('FieldValue.delete'))
          .toList();
      expect(writes, isEmpty);
    });
  });

  // ── KP. 회귀 ────────────────────────────────────────────────────
  group('KP — 앞 Phase 결론 유지', () {
    test('24 §17 — R1.5.4 onboarding gate 그대로', () {
      final apply = _codeOf(_sliceOf(rawCf,
          'export const callableApplyToTO = onCall(', '\n);'));
      final accept = _codeOf(_sliceOf(rawCf,
          'export const callableAcceptTOInvitation = onCall(', '\n);'));
      expect(apply, contains('srvMissingApplicantPayoutRegistration(userData)'));
      expect(accept,
          contains('srvMissingApplicantPayoutRegistration(freshUserData)'));
    });

    test('25 §17 — 삭제가 기존 지원서를 건드리지 않는다', () {
      for (final f in ['applications', 'attendance', 'AUTO_CANCELED']) {
        expect(del, isNot(contains(f)), reason: '$f — 삭제는 연쇄 취소를 하지 않는다');
      }
    });

    test('26 §18 — 직접 확정·재배치 semantics 그대로', () {
      final gate = _flat(_codeOf(
          _sliceOf(rawCf, 'const confirmReviewGate =', '};')));
      expect(gate, isNot(contains('srvMissingApplicantPayoutRegistration')));
      final re = _codeOf(_sliceOf(rawCf,
          'export const callableAcceptConfirmedReassignment = onCall(', '\n);'));
      expect(re, isNot(contains('srvMissingApplicantPayoutRegistration')));
      expect(re, isNot(contains('통장 정보 등록이 필요합니다')));
    });
  });
}
