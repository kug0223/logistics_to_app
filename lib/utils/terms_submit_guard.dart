import '../models/core/legal_terms_model.dart';

/// [DU356] 가입 진행 · 가입 시작 직전의 **약관 준비** 판정 — 외국인 가입(ForeignRegisterScreen)이 쓴다.
///
/// 내국인 가입의 `registerTermsBlockReason`(DU1 C0-TERMS-SUBMIT-GUARD, register_screen.dart)도 [DU359]부터 이 함수에 위임한다
/// (단일 소유 — 같은 입력에 같은 답, `test/du1_s001_final_setup_356_test.dart` G-1 이 대조한다).
/// 예전 외국인 가입 판정은 `_legalTerms?.…toList() ?? []` 로 시작해 읽기 실패 · 필수 0 일 때 빈 목록 every = true 가 되어
/// 약관 없이 가입이 진행될 수 있었다. 로딩 · 실패 · null · 필수 0 · 필수 미동의를 막고, 선택 항목 거부는 막지 않는다.
/// 막을 이유 문구, 통과면 null.
String? termsSubmitBlockReason({
  required bool loading,
  required String? error,
  required EffectiveLegalTerms? terms,
  required Map<String, bool> consent,
}) {
  if (loading) return '약관을 불러오는 중이에요. 잠시 후 다시 시도해 주세요.';
  if (error != null || terms == null) return '약관을 불러오지 못했어요. 약관을 다시 불러온 뒤 진행해 주세요.';
  final required = terms.activeItems.where((t) => t.isRequired).toList();
  if (required.isEmpty) return '약관 정보가 완전하지 않습니다. 잠시 후 다시 시도해 주세요.';
  if (!required.every((t) => consent[t.id] == true)) return '필수 약관에 모두 동의해주세요';
  return null;
}
