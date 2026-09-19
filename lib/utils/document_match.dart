// lib/utils/document_match.dart
//
// [PII-DOC-R1.4] 자동 문서 정합성 — canonical business state의 **읽는 쪽**.
//
// 세 축을 섞지 않는다:
//
//   자동 판정   idCardMatchStatus / bankbookMatchStatus     ← 이 파일
//   사람 판정   businessApplicantDocumentReviews
//   보완 요청   documentCorrectionRequests
//
// 그리고 이 상태는 **아직 어떤 게이트도 읽지 않는다.** 확정 readiness 연결은
// R1.5, 급여 readiness는 그 다음이다. 지금 하는 일은 상태를 정확히 만들고
// 정확히 읽는 것뿐이다.

import 'package:flutter/foundation.dart';

import '../models/core/user_model.dart';

/// 자동 정합성 상태.
///
/// 다섯 개가 서로 다른 사실이다. `MATCHED`가 아닌 것을 전부 "문제 있음"으로
/// 뭉뚱그리면 사용자에게 없는 잘못을 붙이게 된다.
enum DocumentMatchStatus {
  /// 문서 자체가 없다.
  missing,

  /// 문서는 있으나 비교할 기준·근거가 부족했다. 불일치가 아니다.
  unassessed,

  /// 필수 비교를 모두 수행했고 통과했다.
  matched,

  /// 비교를 수행했고 명확히 달랐다.
  mismatch,

  /// 비교 기준은 있었으나 서류에서 필요한 값을 읽지 못했다.
  ocrUncertain,
}

extension DocumentMatchStatusWire on DocumentMatchStatus {
  /// 서버 문자열과 **같은 값**이어야 한다.
  String get wire => switch (this) {
        DocumentMatchStatus.missing => 'MISSING',
        DocumentMatchStatus.unassessed => 'UNASSESSED',
        DocumentMatchStatus.matched => 'MATCHED',
        DocumentMatchStatus.mismatch => 'MISMATCH',
        DocumentMatchStatus.ocrUncertain => 'OCR_UNCERTAIN',
      };
}

/// 서버 문자열 → 상태. 모르는 값은 **통과로 읽지 않는다**.
DocumentMatchStatus documentMatchStatusOf(String? wire) => switch (wire) {
      'MISSING' => DocumentMatchStatus.missing,
      'MATCHED' => DocumentMatchStatus.matched,
      'MISMATCH' => DocumentMatchStatus.mismatch,
      'OCR_UNCERTAIN' => DocumentMatchStatus.ocrUncertain,
      _ => DocumentMatchStatus.unassessed,
    };

/// 근거의 출처. 서버는 이미지를 OCR하지 않으므로 지금은 하나뿐이다.
const String kMatchSourceClientOcr = 'CLIENT_OCR';

/// 보증 수준. `SERVER_VERIFIED`는 **존재하지 않는다** — 서버가 독립적으로
/// 관측한 것이 없기 때문이다.
const String kMatchAssuranceClientEvidence = 'CLIENT_EVIDENCE';

/// 한 문서에 대한 판정 결과.
@immutable
class DocumentMatchSnapshot {
  /// 지금 유효한 상태. 낡았으면 [DocumentMatchStatus.unassessed]다.
  final DocumentMatchStatus status;

  /// 저장돼 있던 상태 — 진단용. 판정에 쓰지 않는다.
  final DocumentMatchStatus? storedStatus;

  final String? evidenceSource;
  final String? assurance;

  /// 평가 당시 버전과 현재 버전이 다른가.
  final bool isStale;

  const DocumentMatchSnapshot({
    required this.status,
    this.storedStatus,
    this.evidenceSource,
    this.assurance,
    this.isStale = false,
  });

  static const DocumentMatchSnapshot missing =
      DocumentMatchSnapshot(status: DocumentMatchStatus.missing);

  static const DocumentMatchSnapshot unassessed =
      DocumentMatchSnapshot(status: DocumentMatchStatus.unassessed);

  /// [PII-DOC-R1.4 §26] 화면에 쓸 수 있는 문구.
  ///
  /// 금지된 표현(`신분증 인증 완료`·`계좌 인증 완료`·`금융기관 검증 완료`)을
  /// 쓰지 않는다. 지금 확인된 것은 **제출한 정보와 제출한 서류가 같다**는
  /// 사실뿐이고, 그건 공적 진위 확인도 금융기관 실명 확인도 아니다.
  String labelFor({required bool isBank}) => switch (status) {
        DocumentMatchStatus.matched =>
          isBank ? '급여계좌 정보 일치' : '서류 정보 일치',
        DocumentMatchStatus.mismatch => '서류 정보 불일치',
        DocumentMatchStatus.ocrUncertain => '서류 정보를 정확히 읽지 못함',
        DocumentMatchStatus.unassessed => '서류 확인 필요',
        DocumentMatchStatus.missing => '서류 미등록',
      };
}

/// 신분증 자동 정합성 — 읽는 시점에 버전을 비교한다.
///
/// 저장된 `MATCHED`를 그대로 믿지 않는다. 문서가 바뀌면 그 판정은 다른
/// 문서에 대한 것이 된다. 서버 `srvResolveIdCardMatch`와 같은 규칙이다.
DocumentMatchSnapshot resolveIdCardMatch(UserModel u) {
  if (!u.hasIdDocument) return DocumentMatchSnapshot.missing;
  final stored = u.idCardMatchStatus;
  if (stored == null) return DocumentMatchSnapshot.unassessed;

  final isStale = (u.idCardMatchDocumentVersion ?? -1) != (u.idDocumentVersion ?? 0);
  final parsed = documentMatchStatusOf(stored);
  return DocumentMatchSnapshot(
    status: isStale ? DocumentMatchStatus.unassessed : parsed,
    storedStatus: parsed,
    evidenceSource: u.idCardMatchEvidenceSource,
    assurance: u.idCardMatchAssurance,
    isStale: isStale,
  );
}

/// 통장사본 자동 정합성.
///
/// 축이 **둘**이다 — 통장사본과 등록 계좌. 계좌만 바뀌어도 그 통장사본과의
/// 대조는 유효하지 않으므로 버전 하나로는 표현할 수 없다.
DocumentMatchSnapshot resolveBankbookMatch(UserModel u) {
  if (!u.hasBankbookDocument) return DocumentMatchSnapshot.missing;
  final stored = u.bankbookMatchStatus;
  if (stored == null) return DocumentMatchSnapshot.unassessed;

  final isStale =
      (u.bankbookMatchDocumentVersion ?? -1) != (u.bankbookDocumentVersion ?? 0) ||
          (u.bankbookMatchAccountVersion ?? -1) != (u.bankAccountVersion ?? 0);
  final parsed = documentMatchStatusOf(stored);
  return DocumentMatchSnapshot(
    status: isStale ? DocumentMatchStatus.unassessed : parsed,
    storedStatus: parsed,
    evidenceSource: u.bankbookMatchEvidenceSource,
    assurance: u.bankbookMatchAssurance,
    isStale: isStale,
  );
}
