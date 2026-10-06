// lib/utils/terms_consent_plan.dart
//
// [LEGAL-1A] 저장된 동의는 **사용자가 실제로 보고 고른 것**이어야 한다.
//
// 복구 화면이 "기록이 비어 있으니 채운다"는 생각으로 활성 약관 전부에
// `agreed: true` 를 만들고 있었다. 사용자는 본문을 보지도, 고르지도 않았고,
// 선택 항목인 마케팅 수신 동의까지 동의로 기록됐다. 가입 당시 거부했더라도
// 복구를 거치면 동의로 뒤집혔다.
//
// 이 모듈은 그 판단을 한 곳으로 모은다. 화면은 여기서 나온 목록과 초기값을
// 그리기만 하고, 스스로 동의를 만들어 내지 않는다.
//
// 세 가지를 섞지 않는다.
//   · 이미 받아 둔 동의        — 다시 묻지 않고, 덮어쓰지도 않는다
//   · 아직 받지 못한 동의      — 본문을 보여 주고 사용자가 고른다
//   · 기록에 실패한 동의       — 성공으로 바꾸지 않는다(화면의 몫)
//
// 재동의(버전 변경) 정책 자체는 여기서 만들지 않는다 — LEGAL.1B 의 몫이다.
// 다만 저장된 버전이 현재 버전과 다르면 "아직 받지 못한 동의"로 둔다.
// 그래야 옛 버전 동의를 새 버전 동의로 둔갑시키지 않는다.

import '../models/core/legal_terms_model.dart';

/// `users/{uid}.termsConsent.{id}` 한 건.
class StoredConsent {
  const StoredConsent({required this.agreed, required this.version});

  final bool agreed;
  final String version;

  /// Firestore 맵을 읽는다. 모양이 다르면 **없는 것으로 친다** —
  /// 읽지 못한 것을 동의로 해석하지 않는다.
  static Map<String, StoredConsent> parseMap(Object? raw) {
    if (raw is! Map) return const {};
    final out = <String, StoredConsent>{};
    raw.forEach((key, value) {
      if (key is! String || value is! Map) return;
      final agreed = value['agreed'];
      if (agreed is! bool) return;
      final version = value['version'];
      out[key] = StoredConsent(
        agreed: agreed,
        version: version is String ? version : '',
      );
    });
    return out;
  }
}

class TermsConsentPlan {
  const TermsConsentPlan._();

  /// 이 버전에 대한 **기록이 이미 있는가**. 동의든 거부든 기록은 기록이다.
  ///
  /// 거부도 사용자가 한 선택이다. 같은 값을 다시 보내면 그 선택의 시각만
  /// 지금으로 밀린다 — 바뀐 것이 없는데 증거를 고쳐 쓰는 일이다.
  static StoredConsent? recordFor(
      LegalTermsItem item, Map<String, StoredConsent> stored) {
    final s = stored[item.id];
    return (s != null && s.version == item.version) ? s : null;
  }

  /// 필수 요건을 **이미 충족한** 항목인가 — 같은 버전에 동의한 기록만.
  static bool isSatisfied(LegalTermsItem item, Map<String, StoredConsent> stored) =>
      recordFor(item, stored)?.agreed == true;

  /// 체크를 바꿀 수 없는 항목. 이미 동의한 것은 이 화면에서 취소하지 않는다
  /// (서버도 true→false 를 막는다). 거부 기록은 잠그지 않는다 — 선택 항목을
  /// 지금 받아들이고 싶을 수 있다.
  static bool isLocked(LegalTermsItem item, Map<String, StoredConsent> stored) =>
      isSatisfied(item, stored);

  /// 사용자에게 물어야 하는 항목. 이미 동의한 것은 빠진다.
  static List<LegalTermsItem> itemsNeedingChoice({
    required List<LegalTermsItem> activeItems,
    required Map<String, StoredConsent> stored,
  }) =>
      activeItems.where((i) => !isSatisfied(i, stored)).toList();

  /// 체크박스 초기값.
  ///
  /// **아직 받지 못한 동의는 필수든 선택이든 false 로 시작한다.** 기본 체크는
  /// 사용자의 선택이 아니다. 이미 받아 둔 항목만 true 로 보이고, 그것은
  /// 기록을 다시 쓰지 않는다(아래 [buildPayload] 참고).
  static Map<String, bool> initialChoices({
    required List<LegalTermsItem> activeItems,
    required Map<String, StoredConsent> stored,
  }) =>
      {
        for (final i in activeItems)
          // 기록이 있으면 그 값을 그대로 보여 준다 — 거부는 거부로 남는다.
          i.id: recordFor(i, stored)?.agreed ?? false,
      };

  /// 진행할 수 있는가 — 필수 항목이 전부 충족됐는가.
  /// 선택 항목은 거부해도 막지 않는다.
  static bool allRequiredChosen({
    required List<LegalTermsItem> activeItems,
    required Map<String, StoredConsent> stored,
    required Map<String, bool> choices,
  }) =>
      activeItems
          .where((i) => i.isRequired)
          .every((i) => isSatisfied(i, stored) || choices[i.id] == true);

  /// 서버로 보낼 payload — **바뀐 것만** 보낸다.
  ///
  /// 같은 버전에 같은 값이 이미 기록돼 있으면 넣지 않는다. 동의든 거부든
  /// 다시 보내면 그 선택의 시각만 지금으로 밀린다 — 바뀐 것이 없는데 법적
  /// 증거를 고쳐 쓰는 일이다.
  ///
  /// 기록이 없는 항목은 거부(`agreed: false`)도 **보낸다**. 거부도 선택이고,
  /// 비워 두면 "묻지 않았다"와 구별되지 않는다.
  static Map<String, Map<String, Object>> buildPayload({
    required List<LegalTermsItem> activeItems,
    required Map<String, StoredConsent> stored,
    required Map<String, bool> choices,
  }) {
    final out = <String, Map<String, Object>>{};
    for (final item in activeItems) {
      final chosen = choices[item.id] == true;
      final record = recordFor(item, stored);
      if (record != null && record.agreed == chosen) continue;
      out[item.id] = {'agreed': chosen, 'version': item.version};
    }
    return out;
  }
}
