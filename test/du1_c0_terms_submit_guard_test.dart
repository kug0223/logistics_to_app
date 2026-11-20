// [DU1 C0-TERMS-SUBMIT-GUARD] 약관 준비가 안 됐을 때 가입 진행·가입 시작이 막히는지 — LOCAL.
//   예전: 두 단계 검증이 `_legalTerms?.…toList() ?? []` 로 시작해 읽기 실패·필수 0 이면 빈 목록 every = true → 약관 없이 진행.
//   TG-1 production 판정 registerTermsBlockReason 을 그대로 부른다: 로딩·실패·null·필수 0·필수 미동의 → 막음, 필수 동의(선택 거부 포함) → 통과
//   TG-2 진입부 연결(소스): ADMIN 1단계·USER 3단계 검증이 이 판정을 쓰고, _doRegister 는 계정 생성(signUp)·동의 기록보다 **먼저** 이 판정으로 끝낸다.
//         예전 빈 목록 패턴이 남아 있지 않다. 실제 계정 생성·PASS·CF 호출 없음.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:ALfit/models/core/legal_terms_model.dart';
import 'package:ALfit/screens/auth/register_screen.dart';

LegalTermsItem _item(String id, bool required_) => LegalTermsItem(
    id: id, title: id, content: '$id 본문', isRequired: required_, version: 'b', revisionId: '${id}__b', order: 1);

EffectiveLegalTerms _terms(List<LegalTermsItem> items) =>
    EffectiveLegalTerms(serverNow: DateTime.utc(2026, 11, 1), upcoming: const [], items: items);

String _code(String p) => File(p).readAsLinesSync().where((l) => !l.trimLeft().startsWith('//')).join('\n');

void main() {
  group('TG-1 production 판정', () {
    final ok = _terms([_item('service_terms', true), _item('privacy', true), _item('marketing', false)]);

    test('로딩 중 → 막음', () {
      expect(registerTermsBlockReason(loading: true, error: null, terms: ok, consent: const {}), isNotNull);
    });
    test('읽기 실패 → 막음(동의값이 다 true 여도)', () {
      expect(registerTermsBlockReason(loading: false, error: '약관을 불러오지 못했어요', terms: null,
          consent: const {'service_terms': true, 'privacy': true}), contains('불러오지 못했어요'));
    });
    test('약관 null(오류 문구 없이) → 막음 — 예전 빈 목록 every=true 반례', () {
      expect(registerTermsBlockReason(loading: false, error: null, terms: null, consent: const {}), isNotNull);
    });
    test('필수 0(선택만) → 막음', () {
      expect(registerTermsBlockReason(loading: false, error: null, terms: _terms([_item('marketing', false)]),
          consent: const {'marketing': true}), contains('완전하지 않습니다'));
    });
    test('정상 약관 + 필수 미동의 → 막음', () {
      expect(registerTermsBlockReason(loading: false, error: null, terms: ok,
          consent: const {'service_terms': true, 'privacy': false}), '필수 약관에 모두 동의해주세요');
    });
    test('정상 약관 + 필수 동의 + 선택 거부 → 통과(선택 거부 의미 보존)', () {
      expect(registerTermsBlockReason(loading: false, error: null, terms: ok,
          consent: const {'service_terms': true, 'privacy': true, 'marketing': false}), isNull);
    });
  });

  test('TG-2 진입부 연결 — 두 단계 검증과 가입 시작이 같은 판정을 쓰고, writer 보다 먼저 끝낸다', () {
    final src = _code('lib/screens/auth/register_screen.dart');
    expect(RegExp(r'_termsBlockReason\(\)').allMatches(src).length, greaterThanOrEqualTo(3), reason: 'ADMIN·USER 검증 + _doRegister');
    final reg = src.indexOf('Future<void> _doRegister() async {');
    expect(reg, greaterThan(0));
    final guard = src.indexOf('_termsBlockReason()', reg);
    final submitting = src.indexOf('setState(() => _isSubmitting = true);', reg);
    final signUp = src.indexOf('userProvider.signUp(', reg);
    final consent = src.indexOf('consentRecord', reg);
    expect(guard, greaterThan(reg));
    expect(guard, lessThan(submitting), reason: '제출 중 표시 전에 막는다');
    expect(guard, lessThan(signUp), reason: '계정 생성 writer 보다 먼저');
    expect(guard, lessThan(consent), reason: '동의 기록보다 먼저');
    expect(src.contains("final requiredItems = _legalTerms?.activeItems"), isFalse, reason: '예전 빈 목록 패턴 제거');
  });
}
