// test/unit/document_match_test.dart
//
// [PII-DOC-R1.4] 자동 문서 정합성 — 클라이언트 resolver.
//
//   서버 `srvResolveIdCardMatch` / `srvResolveBankbookMatch`와 같은 규칙이다.
//   저장된 MATCHED를 그대로 믿지 않고 읽는 시점에 버전을 비교한다.

import 'package:flutter_test/flutter_test.dart';

import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/utils/document_match.dart';

UserModel user({
  String? idPath = 'users/u/idCard.jpg',
  String? idMatch,
  int? idMatchV,
  int? idV,
  String? bbPath = 'users/u/bankbook.jpg',
  String? bbMatch,
  int? bbMatchV,
  int? bbMatchAccV,
  int? bbV,
  int? accV,
}) =>
    UserModel(
      uid: 'u',
      username: 'u',
      email: 'u@example.com',
      name: '홍길동',
      role: UserRole.USER,
      createdAt: DateTime(2026, 1, 1),
      idCardImagePath: idPath,
      bankbookImagePath: bbPath,
      idCardMatchStatus: idMatch,
      idCardMatchEvidenceSource: idMatch == null ? null : kMatchSourceClientOcr,
      idCardMatchAssurance:
          idMatch == null ? null : kMatchAssuranceClientEvidence,
      idCardMatchDocumentVersion: idMatchV,
      idDocumentVersion: idV,
      bankbookMatchStatus: bbMatch,
      bankbookMatchEvidenceSource:
          bbMatch == null ? null : kMatchSourceClientOcr,
      bankbookMatchAssurance:
          bbMatch == null ? null : kMatchAssuranceClientEvidence,
      bankbookMatchDocumentVersion: bbMatchV,
      bankbookMatchAccountVersion: bbMatchAccV,
      bankbookDocumentVersion: bbV,
      bankAccountVersion: accV,
    );

void main() {
  group('상태 어휘', () {
    test('다섯 값이 서로 다르고 서버 문자열과 같다', () {
      expect(DocumentMatchStatus.values.length, 5);
      expect(DocumentMatchStatus.missing.wire, 'MISSING');
      expect(DocumentMatchStatus.unassessed.wire, 'UNASSESSED');
      expect(DocumentMatchStatus.matched.wire, 'MATCHED');
      expect(DocumentMatchStatus.mismatch.wire, 'MISMATCH');
      expect(DocumentMatchStatus.ocrUncertain.wire, 'OCR_UNCERTAIN');
    });

    test('모르는 문자열을 통과로 읽지 않는다', () {
      for (final w in [null, '', 'SERVER_VERIFIED', 'PASSED', 'APPROVED']) {
        expect(documentMatchStatusOf(w), DocumentMatchStatus.unassessed,
            reason: w.toString());
      }
    });

    test('사람 판정·보완요청 값이 이 어휘에 없다', () {
      for (final w in [
        'MANUAL_APPROVED', 'MANUAL_REJECTED', 'REUPLOAD_REQUIRED',
        'SELF_CHECK_PASSED', 'SELF_CHECK_OVERRIDDEN', 'REVIEWED_OK',
      ]) {
        expect(documentMatchStatusOf(w), DocumentMatchStatus.unassessed,
            reason: '$w 는 다른 축의 값이다');
      }
    });
  });

  group('문구 — 과장하지 않는다', () {
    test('MATCHED는 "일치"이지 "인증 완료"가 아니다', () {
      const m = DocumentMatchSnapshot(status: DocumentMatchStatus.matched);
      expect(m.labelFor(isBank: false), '서류 정보 일치');
      expect(m.labelFor(isBank: true), '급여계좌 정보 일치');
    });

    test('금지 문구를 쓰지 않는다', () {
      for (final s in DocumentMatchStatus.values) {
        for (final isBank in [true, false]) {
          final t = DocumentMatchSnapshot(status: s).labelFor(isBank: isBank);
          for (final banned in ['인증 완료', '검증 완료', '본인 명의 인증']) {
            expect(t.contains(banned), isFalse, reason: '$s → $t');
          }
        }
      }
    });

    test('다섯 상태가 서로 다른 말을 한다', () {
      final all = DocumentMatchStatus.values
          .map((s) => DocumentMatchSnapshot(status: s).labelFor(isBank: false))
          .toSet();
      expect(all.length, 5);
    });
  });

  group('I — 신분증', () {
    test('I1 문서 없음 → MISSING', () {
      final s = resolveIdCardMatch(user(idPath: null, idMatch: 'MATCHED'));
      expect(s.status, DocumentMatchStatus.missing,
          reason: '삭제 후 잔존 필드가 MATCHED로 읽히면 안 된다');
    });

    test('I2 MATCHED + 버전 동일 → MATCHED', () {
      final s = resolveIdCardMatch(user(idMatch: 'MATCHED', idMatchV: 3, idV: 3));
      expect(s.status, DocumentMatchStatus.matched);
      expect(s.evidenceSource, kMatchSourceClientOcr);
      expect(s.assurance, kMatchAssuranceClientEvidence);
      expect(s.isStale, isFalse);
    });

    test('I3 MISMATCH 보존', () {
      final s = resolveIdCardMatch(user(idMatch: 'MISMATCH', idMatchV: 1, idV: 1));
      expect(s.status, DocumentMatchStatus.mismatch);
    });

    test('I4 OCR_UNCERTAIN 보존', () {
      final s =
          resolveIdCardMatch(user(idMatch: 'OCR_UNCERTAIN', idMatchV: 1, idV: 1));
      expect(s.status, DocumentMatchStatus.ocrUncertain);
    });

    test('평가 기록이 없으면 UNASSESSED (기존 사용자)', () {
      final s = resolveIdCardMatch(user(idMatch: null, idV: 2));
      expect(s.status, DocumentMatchStatus.unassessed);
      expect(s.isStale, isFalse, reason: '낡은 게 아니라 없는 것이다');
    });
  });

  group('B — 통장사본', () {
    test('B1 MATCHED + 두 버전 동일 → MATCHED', () {
      final s = resolveBankbookMatch(user(
          bbMatch: 'MATCHED', bbMatchV: 2, bbMatchAccV: 5, bbV: 2, accV: 5));
      expect(s.status, DocumentMatchStatus.matched);
      expect(s.isStale, isFalse);
    });

    test('문서 없음 → MISSING', () {
      final s = resolveBankbookMatch(user(bbPath: null, bbMatch: 'MATCHED'));
      expect(s.status, DocumentMatchStatus.missing);
    });
  });

  group('V — 버전 결속', () {
    test('V1 신분증 재업로드 → 이전 MATCHED 무효', () {
      final s = resolveIdCardMatch(user(idMatch: 'MATCHED', idMatchV: 1, idV: 2));
      expect(s.isStale, isTrue);
      expect(s.status, DocumentMatchStatus.unassessed);
      expect(s.storedStatus, DocumentMatchStatus.matched,
          reason: '무엇이 저장돼 있었는지는 진단용으로 남는다');
    });

    test('V2 계좌 변경 → 통장 MATCHED 무효', () {
      final s = resolveBankbookMatch(user(
          bbMatch: 'MATCHED', bbMatchV: 2, bbMatchAccV: 3, bbV: 2, accV: 4));
      expect(s.isStale, isTrue);
      expect(s.status, DocumentMatchStatus.unassessed);
    });

    test('V3 통장사본 재업로드 → MATCHED 무효', () {
      final s = resolveBankbookMatch(user(
          bbMatch: 'MATCHED', bbMatchV: 2, bbMatchAccV: 3, bbV: 3, accV: 3));
      expect(s.isStale, isTrue);
      expect(s.status, DocumentMatchStatus.unassessed);
    });

    test('통장은 축이 둘 — 하나만 맞아도 낡음', () {
      // 문서 버전만 맞고 계좌 버전이 다름
      expect(
          resolveBankbookMatch(user(
                  bbMatch: 'MATCHED',
                  bbMatchV: 2, bbMatchAccV: 1, bbV: 2, accV: 9))
              .isStale,
          isTrue);
      // 계좌 버전만 맞고 문서 버전이 다름
      expect(
          resolveBankbookMatch(user(
                  bbMatch: 'MATCHED',
                  bbMatchV: 1, bbMatchAccV: 3, bbV: 9, accV: 3))
              .isStale,
          isTrue);
    });

    test('버전 필드가 없으면 낡은 것으로 본다 (fail-closed)', () {
      final s = resolveIdCardMatch(user(idMatch: 'MATCHED', idMatchV: null, idV: 1));
      expect(s.status, DocumentMatchStatus.unassessed);
    });
  });

  group('L — legacy', () {
    test('기존 문서 + 평가 없음 → UNASSESSED (MATCHED 승격 없음)', () {
      final s = resolveIdCardMatch(user(idMatch: null));
      expect(s.status, DocumentMatchStatus.unassessed);
      expect(s.status, isNot(DocumentMatchStatus.matched));
    });

    test('문서 자체가 없으면 MISSING', () {
      expect(resolveIdCardMatch(user(idPath: null, idMatch: null)).status,
          DocumentMatchStatus.missing);
      expect(resolveBankbookMatch(user(bbPath: null, bbMatch: null)).status,
          DocumentMatchStatus.missing);
    });
  });

  group('보안 — toMap에 canonical 필드가 없다', () {
    test('서버 소유 필드가 클라이언트 write payload에 실리지 않는다', () {
      final m = user(
        idMatch: 'MATCHED', idMatchV: 1, idV: 1,
        bbMatch: 'MATCHED', bbMatchV: 1, bbMatchAccV: 1, bbV: 1, accV: 1,
      ).toMap();
      for (final k in [
        'idCardMatchStatus', 'idCardMatchEvidenceSource',
        'idCardMatchAssurance', 'idCardMatchDocumentVersion',
        'idCardMatchEvaluatedAt', 'idDocumentVersion',
        'bankbookMatchStatus', 'bankbookMatchEvidenceSource',
        'bankbookMatchAssurance', 'bankbookMatchDocumentVersion',
        'bankbookMatchAccountVersion', 'bankbookMatchEvaluatedAt',
        'bankbookDocumentVersion', 'bankAccountVersion',
      ]) {
        expect(m.containsKey(k), isFalse,
            reason: '$k 가 toMap에 실리면 rules가 정상 업데이트를 막는다');
      }
    });

    test('SERVER_VERIFIED는 존재하지 않는다', () {
      expect(kMatchAssuranceClientEvidence, 'CLIENT_EVIDENCE');
      expect(documentMatchStatusOf('SERVER_VERIFIED'),
          DocumentMatchStatus.unassessed);
    });
  });
}
