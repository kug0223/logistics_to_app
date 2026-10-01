// [R7-P4.4E.3A] 계약서 사업주란에 들어가는 날인은 **사업장 owner 의 것**이다.
//
//   P4.4C 에서 Home·CreateTO·서버·계약 writer 를 그 하나로 정렬했는데,
//   관리 탭의 인감 카드만 `users/{callerUid}.sealBase64` 를 그리고 있었다.
//   BUSINESS_ADMIN 은 보통 본인이 owner 라 드러나지 않았고, SubAdmin 에서만
//   갈렸다 — 개인 날인이 있으면 '등록됨' 이라고 말했다. 그 날인은 계약
//   writer 가 쓰지 않으므로, 준비되지 않았는데 되었다고 말한 것이다.
//   등록 버튼을 눌러도 사업주란은 채워지지 않는다.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:ALfit/models/core/business_model.dart';
import 'package:ALfit/services/business_posting_readiness.dart';

String _settings() =>
    File('lib/screens/common/settings_screen.dart').readAsStringSync();
String _home() =>
    File('lib/screens/business_admin/business_admin_home_screen.dart')
        .readAsStringSync();
String _resolver() =>
    File('lib/services/business_posting_readiness.dart').readAsStringSync();
String _rules() => File('firestore.rules').readAsStringSync();

BusinessPostingReadiness _biz({
  bool hasEmployerSeal = false,
  bool employerSealUnknown = false,
}) =>
    BusinessPostingReadiness(
      bizId: 'b1',
      isApproved: true,
      hasCanonicalLicense: true,
      hasOwnerLegacyLicense: false,
      hasActiveWorkTypes: true,
      workTypesUnknown: false,
      hasEmployerSeal: hasEmployerSeal,
      employerSealUnknown: employerSealUnknown,
    );

Future<FirstPostingReadiness> _resolve(
    Map<String, BusinessPostingReadiness> map) async {
  final r = await FirstPostingReadinessResolver.resolve(
    businesses: [
      BusinessModel(
        id: 'b1',
        name: '테스트 사업장',
        ownerId: 'owner1',
        businessNumber: '000-00-00000',
        address: '서울시 어딘가',
        category: '물류',
        subCategory: '창고',
        isApproved: true,
        createdAt: DateTime(2026, 1, 1),
      ),
    ],
    postingReadiness: (_) async => map,
    contractTemplates: (_) async => const [],
    selectableForNewContract: (_) => true,
    callerHasSeal: false,
  );
  return r.readiness;
}

void main() {
  group('[R7-P4.4E.3A] 왜 SubAdmin 이 owner 날인을 못 읽는가', () {
    test('SEAL-ROLE-00 users 문서는 본인·SUPER_ADMIN 만 읽는다', () {
      final i = _rules().indexOf('match /users/{userId} {');
      expect(i, greaterThan(-1));
      final block = _rules().substring(i, i + 1400);
      expect(block.contains('isOwner(userId) ||'), isTrue);
      expect(block.contains('isSuperAdmin()'), isTrue,
          reason: '이 규칙 때문에 SubAdmin 은 owner 날인을 직접 확인할 수 없다');
    });
  });

  group('[R7-P4.4E.3A] 모름과 없음을 구분한다', () {
    test('SEAL-ROLE-07 읽기 실패를 미등록으로 접지 않는다', () async {
      final r = await _resolve({'b1': _biz(employerSealUnknown: true)});
      expect(r.sealReady, isFalse, reason: '모르는 것을 준비됨으로 올리지 않는다');
      expect(r.sealUnknown, isTrue, reason: '그렇다고 "없다" 고 단정하지도 않는다');
    });

    test('SEAL-ROLE-07b 진짜 없을 때는 unknown 이 아니다', () async {
      final r = await _resolve({'b1': _biz()});
      expect(r.sealReady, isFalse);
      expect(r.sealUnknown, isFalse,
          reason: '읽어서 없는 것과 못 읽은 것은 다른 말이다');
    });

    test('SEAL-ROLE-07c 등록돼 있으면 unknown 이 아니다', () async {
      final r = await _resolve({'b1': _biz(hasEmployerSeal: true)});
      expect(r.sealReady, isTrue);
      expect(r.sealUnknown, isFalse);
    });

    test('SEAL-ROLE-07d 모름이 준비 완료를 열지 않는다 (fail-closed)', () async {
      final r = await _resolve({'b1': _biz(employerSealUnknown: true)});
      expect(r.isDone(FirstPostingTask.seal), isFalse,
          reason: '서버가 최종 gate 다 — 모름으로 공고를 열지 않는다');
      expect(r.allReady, isFalse);
    });
  });

  group('[R7-P4.4E.3A] 관리 탭 — 역할별로 다른 것을 본다', () {
    test('SEAL-ROLE-05 SubAdmin 은 상태만 본다 (등록/변경/삭제 없음)', () {
      final s = _settings();
      expect(s.contains("if (user?.isSubAdmin == true) {"), isTrue);
      expect(s.contains('return _buildEmployerSealStatusCard(context);'), isTrue,
          reason: '본인 날인 카드로 내려가지 않는다');

      // 상태 카드 안에는 쓰기 입구가 없다.
      final i = s.indexOf('Widget _buildEmployerSealStatusCard');
      final j = s.indexOf('Widget _buildSealCard', i);
      final card = s.substring(i, j);
      for (final cta in ['_registerSeal', '_deleteSeal', '_callSaveSeal']) {
        expect(card.contains(cta), isFalse, reason: '$cta 입구가 남아 있다');
      }
    });

    test('SEAL-ROLE-03/04 상태는 owner 날인에서 온다 — 본인 것이 아니다', () {
      final i = _settings().indexOf('Widget _buildEmployerSealStatusCard');
      final j = _settings().indexOf('Widget _buildSealCard', i);
      final card = _settings().substring(i, j);
      expect(card.contains('r.sealReady'), isTrue);
      expect(card.contains('r.sealUnknown'), isTrue);
      expect(card.contains('sealBase64'), isFalse,
          reason: '호출자 개인 날인을 다시 끌어오지 않는다');
    });

    test('SEAL-ROLE-07e 네 상태를 구분한다', () {
      final i = _settings().indexOf('Widget _buildEmployerSealStatusCard');
      final j = _settings().indexOf('Widget _buildSealCard', i);
      final card = _settings().substring(i, j);
      expect(card.contains('FirstPostingReadinessStatus.failed'), isTrue);
      expect(card.contains('확인 중이에요'), isTrue);
      expect(card.contains('등록됨 · 계약서 사업주란에 사용됩니다'), isTrue);
      expect(card.contains('상태를 확인할 수 없어요'), isTrue);
      expect(card.contains('미등록 · 사업장 관리자에게 등록을 요청하세요'), isTrue);
    });

    test('SEAL-ROLE-01/02 owner 는 기존대로 등록·변경할 수 있다', () {
      final s = _settings();
      final i = s.indexOf('Widget _buildSealCard');
      // 다음 top-level 메서드 직전까지 — 고정 길이 창을 쓰지 않는다.
      final next = s.indexOf('\n  Future<void> _registerSeal', i);
      final card = s.substring(i, next > i ? next + 2000 : s.length);
      expect(card.contains('final sealBase64 = user?.sealBase64;'), isTrue,
          reason: 'owner 는 caller == owner 라 본인 날인이 곧 고용주 날인이다');
      expect(card.contains('_registerSeal(context, user)'), isTrue);
      expect(card.contains('_deleteSeal(context, user)'), isTrue);
    });

    test('SEAL-ROLE-06 상태는 새 조회가 아니라 같은 판정을 읽는다', () {
      final s = _settings();
      expect(s.contains('FirstPostingReadinessStore.current'), isTrue,
          reason: 'Home 과 같은 진실 — 새 listener·polling 을 만들지 않는다');
      expect(s.contains('Timer.periodic'), isFalse);
      // store 는 uid·scopeKey 로 묶여 있어 계정·사업장 전환 시 stale 하지 않다.
      expect(_resolver().contains('bool matches(String? currentUid'), isTrue);
    });
  });

  group('[R7-P4.4E.3A] Home 도 헛된 요청을 시키지 않는다', () {
    test('SEAL-ROLE-08 모를 때 본인 날인 등록을 권하지 않는다', () {
      final h = _home();
      expect(h.contains("pendingHint: r.sealUnknown ? '사업장 관리자에게 확인하세요' : null"),
          isTrue);
      expect(h.contains('onTap: r.sealUnknown'), isTrue,
          reason: '눌러도 사업주란이 채워지지 않는 경로를 열어 두지 않는다');
    });
  });

  group('[R7-P4.4E.3A] 회귀 — owner seal 이 canonical 인 축은 그대로다', () {
    test('SEAL-ROLE-09 판정은 사업장 owner 날인을 본다', () {
      expect(_resolver().contains("ownerData?['sealBase64']"), isTrue);
      expect(_resolver().contains('readinessMap.values.any((r) => r.hasEmployerSeal)'),
          isTrue);
    });

    test('SEAL-ROLE-10 저장 writer 는 그대로 호출자 문서다', () {
      final cf = File('functions/src/index.ts').readAsStringSync();
      final i = cf.indexOf('export const callableSaveSeal');
      expect(i, greaterThan(-1));
      final body = cf.substring(i, i + 1800);
      expect(body.contains('const uid = request.auth.uid;'), isTrue);
      expect(body.contains('collection("users").doc(uid).update('), isTrue,
          reason: 'owner-target write API 로 넓히지 않았다 — owner 가 부를 때 caller == owner 다');
    });
  });
}
