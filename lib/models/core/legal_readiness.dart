// lib/models/core/legal_readiness.dart
//
// [R7-LEGAL.1B.1] 화면이 읽는 **법적 준비 상태**.
//
//   판정은 서버(`callableGetLegalReadiness`)가 한다. 화면이
//   `user.version != terms.version` 같은 비교를 직접 하면 정책이 두 벌이
//   되고, 두 벌은 언젠가 다른 답을 말한다. 그래서 이 모델은 서버가 내려준
//   값을 **해석만** 한다 — 스스로 계산하지 않는다.
//
//   그리고 네 가지를 섞지 않는다.
//
//     CURRENT                 현재 필수 약관을 전부 수락했다
//     RECONSENT_REQUIRED      새 판이 발행됐다. 다시 받아야 한다
//     LEGACY_CONSENT_UNKNOWN  옛 기록이라 무엇에 동의했는지 모른다
//     OPTIONAL_UNANSWERED     필수는 충족. 선택만 답하지 않았다
//
//   여기에 조회 실패(`error`)와 조회 중(`loading`)이 더해진다.
//   **조회 실패는 미동의가 아니다.** 모르는 것을 "동의하지 않았다" 로
//   그리면 서버 장애가 곧 전원 차단이 된다.

enum LegalReadinessStatus {
  loading,
  current,
  reconsentRequired,
  legacyConsentUnknown,
  optionalUnanswered,
  error,
}

/// [R7-PAYROLL-POLICY.5A] 고지는 됐지만 아직 시행되지 않은 약관 한 건.
///
/// 발행과 시행은 다른 사건이다. 이 값은 **안내용**이다 — 할 일도, 차단
/// 사유도 아니다. 아직 효력이 없는 약관에 동의하지 않으면 앱을 못 쓰게
/// 만드는 것이 `.5A` 가 고치는 결함이다.
class UpcomingLegalItem {
  const UpcomingLegalItem({
    required this.itemId,
    required this.version,
    required this.effectiveAt,
  });

  final String itemId;
  final String version;

  /// 시행 시각. 서버가 보낸 값이다 — 기기 시계로 계산하지 않는다.
  final DateTime? effectiveAt;

  /// 모양이 다르면 **없는 것으로 친다.** 모르는 것을 시행 예정으로 그리면
  /// 사용자에게 오지 않을 변경을 예고하게 된다.
  static List<UpcomingLegalItem> parseList(Object? raw) {
    if (raw is! List) return const [];
    final out = <UpcomingLegalItem>[];
    for (final e in raw) {
      if (e is! Map) continue;
      final id = e['itemId'];
      final version = e['version'];
      if (id is! String || id.isEmpty) continue;
      if (version is! String || version.isEmpty) continue;
      final ms = e['effectiveAtMs'];
      out.add(UpcomingLegalItem(
        itemId: id,
        version: version,
        effectiveAt: ms is int
            ? DateTime.fromMillisecondsSinceEpoch(ms).toLocal()
            : null,
      ));
    }
    return out;
  }
}

class LegalReadiness {
  const LegalReadiness({
    required this.status,
    this.reconsentRequired = const [],
    this.legacyUnknown = const [],
    this.optionalUnanswered = const [],
    this.upcoming = const [],
  });

  final LegalReadinessStatus status;
  final List<String> reconsentRequired;
  final List<String> legacyUnknown;
  final List<String> optionalUnanswered;

  /// 시행 예정 약관. `status` 와 섞지 않는다.
  final List<UpcomingLegalItem> upcoming;

  static const loading = LegalReadiness(status: LegalReadinessStatus.loading);
  static const error = LegalReadiness(status: LegalReadinessStatus.error);

  /// 서버 응답 해석. 모르는 값은 **error** 다 — 모르는 것을 정상으로
  /// 올리면, 응답이 바뀐 날 조용히 "준비됨" 이 된다.
  factory LegalReadiness.fromServer(Map<dynamic, dynamic>? data) {
    if (data == null) return LegalReadiness.error;
    List<String> list(Object? v) => v is List
        ? v.whereType<String>().toList(growable: false)
        : const <String>[];
    final status = switch (data['status']) {
      'CURRENT' => LegalReadinessStatus.current,
      'RECONSENT_REQUIRED' => LegalReadinessStatus.reconsentRequired,
      'LEGACY_CONSENT_UNKNOWN' => LegalReadinessStatus.legacyConsentUnknown,
      'OPTIONAL_UNANSWERED' => LegalReadinessStatus.optionalUnanswered,
      _ => LegalReadinessStatus.error,
    };
    return LegalReadiness(
      status: status,
      reconsentRequired: list(data['reconsentRequired']),
      legacyUnknown: list(data['legacyUnknown']),
      optionalUnanswered: list(data['optionalUnanswered']),
      upcoming: UpcomingLegalItem.parseList(data['upcoming']),
    );
  }

  /// 사용자가 할 일이 있는가 — 홈에 남겨야 하는가.
  ///
  /// 선택 항목만 남은 경우는 할 일로 만들지 않는다. 선택은 선택이고,
  /// 마케팅 수신 같은 항목을 할 일로 띄우면 사실상 강요가 된다.
  /// 조회 실패도 할 일이 아니다 — 사용자가 할 수 있는 일이 없다.
  bool get needsAttention =>
      status == LegalReadinessStatus.reconsentRequired ||
      status == LegalReadinessStatus.legacyConsentUnknown;

  /// **새 법적 약속**(지원·확정·계약)을 만들 수 있는가.
  ///
  /// 막는 것은 새 판이 발행된 경우뿐이다. 증명할 수 없는 옛 기록은 막지
  /// 않는다 — 사용자가 만든 상태가 아니고, 발행이 아직 새 경로를 거치지
  /// 않았다면 모든 사용자가 그 상태라 제품이 멈춘다.
  /// 서버가 같은 규칙을 갖고 있고, 이 값은 UX 선반영일 뿐이다.
  bool get blocksNewCommitment =>
      status == LegalReadinessStatus.reconsentRequired;

  /// 이번에 사용자가 다시 봐야 하는 항목들.
  List<String> get attentionItems => [...reconsentRequired, ...legacyUnknown];
}
