// [R7-PAYROLL-POLICY.5B] 시행 경계에서 앱·웹·서버가 같은 판을 말하는가.
//
// `.5A` 가 발행과 시행을 분리하고 나서 남은 구멍이 있었다.
//
//   앱은 `app_settings/legal_terms` 의 base 를 직접 읽었다. 비로그인 가입
//   화면도 그 경로를 쓰므로 서버 시각을 알 수 없고, 그래서 base 를 그대로
//   현재 약관으로 썼다. base 는 정기 정합화가 올려 주기 전까지 낡아 있을
//   수 있다. 그 사이 앱은 A 를 보여 주고 서버는 B 를 요구한다.
//
//   그리고 가입 화면은 조회가 실패하면 **코드 기본값**을 현재 약관처럼
//   보여 준 뒤 동의를 받았고, 동의 제출이 거절되면 같은 payload 로
//   무한히 재시도했다.
//
// 이 파일이 고정하는 것
//
//   BP-1  동의를 받는 화면은 서버가 판정한 시행 중 약관만 쓴다
//   BP-2  조회 실패·부분 응답을 기본값/정상으로 위장하지 않는다
//   BP-3  "동의하는 사이에 약관이 바뀌었다" 판별은 한 곳이다
//   BP-4  STALE 이면 새 글을 다시 보여 주고 사용자가 다시 고른다 (행동)
//   BP-5  STALE 을 무한 재시도하지 않는다
//   BP-6  시행 예정은 현재 약관이 아니다

import 'dart:io';

import 'package:ALfit/models/core/legal_readiness.dart';
import 'package:ALfit/models/core/legal_terms_model.dart';
import 'package:ALfit/screens/legal/legal_consent_reads.dart';
import 'package:ALfit/screens/legal/legal_consent_screen.dart';
import 'package:ALfit/services/legal_terms_service.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

String _read(String p) {
  final f = File(p);
  if (!f.existsSync()) throw StateError('$p 를 찾지 못함');
  return f.readAsStringSync();
}

/// 주석을 뺀 소스 — 설명문을 코드로 오인하지 않게.
String _code(String p) => _read(p)
    .split('\n')
    .where((l) {
      final t = l.trimLeft();
      return !t.startsWith('//') && !t.startsWith('///') && !t.startsWith('*');
    })
    .join('\n');

/// 동의를 **받는** 화면들. 여기서는 기본값 대체가 허용되지 않는다.
const _consentSurfaces = <String>[
  'lib/screens/auth/register_screen.dart',
  'lib/screens/auth/foreign_register_screen.dart',
  'lib/screens/auth/registration_recovery_screen.dart',
  'lib/screens/auth/registration_recovery_reads.dart',
  'lib/screens/legal/legal_consent_screen.dart',
  'lib/screens/legal/legal_consent_reads.dart',
];

/// 약관 본문을 **보여 주는** 화면들. 동의는 받지 않지만 같은 판이어야 한다.
const _viewerSurfaces = <String>[
  'lib/screens/common/settings_screen.dart',
  'lib/screens/user/user_settings_screen.dart',
];

LegalTermsItem _item(String id, String title, bool required_,
        {String version = '2026.08', String? body}) =>
    LegalTermsItem(
      id: id,
      title: title,
      content: body ?? '$title 본문입니다.\n' * 3,
      isRequired: required_,
      version: version,
      revisionId: '${id}__$version',
      order: 1,
    );

EffectiveLegalTerms _terms({
  String version = '2026.08',
  String? body,
  List<UpcomingLegalItemInfo> upcoming = const [],
}) =>
    EffectiveLegalTerms(
      serverNow: DateTime.utc(2026, 10, 8),
      upcoming: upcoming,
      items: [
        _item('service_terms', '서비스 이용약관', true,
            version: version, body: body),
        _item('marketing_consent', '마케팅 수신 동의 (선택)', false,
            version: version),
      ],
    );

LegalReadiness _reconsent() => const LegalReadiness(
      status: LegalReadinessStatus.reconsentRequired,
      reconsentRequired: ['service_terms'],
    );

FirebaseFunctionsException _stale() => FirebaseFunctionsException(
      code: 'failed-precondition',
      message: 'TERMS_VERSION_STALE 약관이 변경되었습니다. 다시 확인하고 동의해 주세요.',
    );

void main() {
  // ───────────────────────────────────────────────────────────
  group('BP-1 시행 중 약관만 쓴다', () {
    test('01 약관을 불러오는 화면은 모두 서버 판정 경로를 쓴다', () {
      // 약관을 **불러오는** 자리만 본다. `legal_consent_screen` 은 불러오기를
      // `legal_consent_reads` 에 맡기고 STALE 판별만 서비스에서 가져온다.
      for (final p in <String>[
        'lib/screens/auth/register_screen.dart',
        'lib/screens/auth/foreign_register_screen.dart',
        'lib/screens/auth/registration_recovery_reads.dart',
        'lib/screens/legal/legal_consent_reads.dart',
      ]) {
        expect(_code(p).contains('fetchEffectiveTerms'), isTrue,
            reason: '$p 가 서버 판정 경로를 쓰지 않는다');
      }
    });

    test('02 동의 화면이 편집용 경로를 쓰지 않는다', () {
      // 편집용은 발행되지 않은 기본값까지 꺼내 준다 — 동의에 쓰면 안 된다.
      for (final p in [..._consentSurfaces, ..._viewerSurfaces]) {
        expect(_code(p).contains('getTermsForEditing'), isFalse, reason: p);
      }
      // 발행 화면만 쓴다.
      expect(
          _code('lib/screens/super_admin/legal_terms_management_screen.dart')
              .contains('getTermsForEditing'),
          isTrue);
    });

    test('03 동의 화면이 projection 을 직접 읽지 않는다', () {
      // base 를 직접 읽으면 시행 시각이 지난 뒤에도 옛 판을 쓴다.
      // (import 경로에 `legal_terms` 가 들어가므로 **문서 접근 모양**만 본다.)
      for (final p in [..._consentSurfaces, ..._viewerSurfaces]) {
        final src = _code(p);
        expect(src.contains("collection('app_settings')"), isFalse, reason: p);
        expect(src.contains("doc('legal_terms')"), isFalse, reason: p);
      }
      // projection 을 읽는 곳은 서비스 하나다.
      expect(
          _code('lib/services/legal_terms_service.dart')
              .contains("doc(_docId)"),
          isTrue);
    });

    test('04 약관 뷰어도 같은 판을 보여 준다', () {
      for (final p in _viewerSurfaces) {
        expect(_code(p).contains('fetchEffectiveTerms'), isTrue, reason: p);
      }
    });

    test('05 서버 판정 경로는 하나다', () {
      final svc = _code('lib/services/legal_terms_service.dart');
      expect(svc.contains("httpsCallable('callableGetEffectiveLegalTerms'"),
          isTrue);
      // 화면이 callable 을 직접 부르지 않는다 — 부르면 해석이 두 벌이 된다.
      for (final p in [..._consentSurfaces, ..._viewerSurfaces]) {
        expect(_code(p).contains('callableGetEffectiveLegalTerms'), isFalse,
            reason: p);
      }
    });
  });

  // ───────────────────────────────────────────────────────────
  group('BP-2 ERROR ≠ EMPTY, UNKNOWN ≠ CURRENT', () {
    test('06 동의 화면에 기본값 대체가 없다', () {
      // 발행되지 않은 코드 기본값을 현재 약관처럼 보여 주고 동의를 받으면,
      // 그 동의는 사용자가 본 글을 가리키지 않는다.
      for (final p in _consentSurfaces) {
        expect(_code(p).contains('LegalTerms.defaultTerms()'), isFalse,
            reason: '$p 가 기본값을 현재 약관으로 쓴다');
      }
    });

    test('07 응답 모양이 다르면 throw — 조용히 비우지 않는다', () {
      for (final bad in <Map<dynamic, dynamic>?>[
        null,
        <String, Object?>{},
        {'effectiveItems': 'x', 'serverNowMs': 1},
        {'effectiveItems': <Object>[], 'serverNowMs': 'now'},
        {'serverNowMs': 1},
        {'effectiveItems': <Object>[]},
        // [R7-PAYROLL-POLICY.5B.1] 무결성 판정이 없으면 "문제 없음" 이
        //   아니다 — 검사가 조용히 꺼지면 안 된다.
        {'effectiveItems': <Object>[], 'serverNowMs': 1},
        {'effectiveItems': <Object>[], 'serverNowMs': 1,
          'requiredIntegrity': 'x'},
        {'effectiveItems': <Object>[], 'serverNowMs': 1,
          'requiredIntegrity': {'ok': 'yes'}},
      ]) {
        expect(() => EffectiveLegalTerms.fromServer(bad),
            throwsA(isA<FormatException>()),
            reason: '$bad');
      }
    });

    test('08 필수 항목이 없으면 정상 상태가 아니다', () {
      final none = EffectiveLegalTerms.fromServer({
        'effectiveItems': <Object>[],
        'requiredIntegrity': {'ok': true},
        'serverNowMs': 0,
      });
      expect(none.hasRequiredItems, isFalse);

      final onlyOptional = EffectiveLegalTerms.fromServer({
        'effectiveItems': [
          {
            'itemId': 'marketing_consent',
            'version': '2026.08',
            'isRequired': false,
          },
        ],
        'requiredIntegrity': {'ok': true},
        'serverNowMs': 0,
      });
      expect(onlyOptional.hasRequiredItems, isFalse,
          reason: '선택 항목만 있는 응답을 "동의할 것이 없다" 로 읽지 않는다');

      expect(_terms().hasRequiredItems, isTrue);
    });

    // [R7-PAYROLL-POLICY.5B.1] 정책이 뒤집혔다. 예전에는 깨진 항목을
    //   버리고 남은 것만 썼다 — 서버가 보낸 필수 약관 하나가 전송 중
    //   망가져도 앱은 정상 화면을 그렸다. PARTIAL != SUCCESS.
    test('09 모양이 깨진 항목이 있으면 전체가 ERROR 다', () {
      for (final broken in <Object>[
        'junk',
        42,
        {'itemId': '', 'version': 'v'},
        {'itemId': 'a', 'version': ''},
        {'version': 'v'},
        {'itemId': 'a'},
      ]) {
        expect(
            () => EffectiveLegalTerms.fromServer({
                  'effectiveItems': [
                    {'itemId': 'service_terms', 'version': '2026.08'},
                    broken,
                  ],
                  'requiredIntegrity': {'ok': true},
                  'serverNowMs': 1700000000000,
                }),
            throwsA(isA<FormatException>()),
            reason: '$broken 를 조용히 버렸다');
      }
    });

    test('10 화면들이 조회 실패를 상태로 들고 있다', () {
      expect(_code('lib/screens/auth/register_screen.dart')
          .contains('_termsError'), isTrue);
      expect(_code('lib/screens/auth/foreign_register_screen.dart')
          .contains('_termsError'), isTrue);
      // 재동의 화면은 기존 ERROR 상태를 쓴다.
      expect(_code('lib/screens/legal/legal_consent_screen.dart')
          .contains('LegalReadiness.error'), isTrue);
    });
  });

  // ───────────────────────────────────────────────────────────
  group('BP-7 필수 발행본 무결성 — 동의 차단', () {
    EffectiveLegalTerms withIntegrity(RequiredLegalIntegrity i) =>
        EffectiveLegalTerms(
          serverNow: DateTime.utc(2026, 10, 9),
          upcoming: const [],
          integrity: i,
          items: [
            _item('service_terms', '서비스 이용약관', true),
            _item('marketing_consent', '마케팅 수신 동의 (선택)', false),
          ],
        );

    test('22 판정이 false 면 필수 완전성이 깨진다', () {
      expect(
          withIntegrity(const RequiredLegalIntegrity(ok: true))
              .hasRequiredItems,
          isTrue);
      expect(
          withIntegrity(const RequiredLegalIntegrity(
                  ok: false, mismatchedItemIds: ['service_terms']))
              .hasRequiredItems,
          isFalse,
          reason: '발행본이 어긋난 필수 약관으로 동의를 받을 수 없다');
      expect(
          withIntegrity(const RequiredLegalIntegrity(
                  ok: false, emptyItemIds: ['service_terms']))
              .hasRequiredItems,
          isFalse,
          reason: '본문이 비어 있는 필수 약관으로 동의를 받을 수 없다');
    });

    test('23 서버 응답의 판정을 그대로 읽는다', () {
      final t = EffectiveLegalTerms.fromServer({
        'effectiveItems': [
          {'itemId': 'service_terms', 'version': '2026.08'},
        ],
        'requiredIntegrity': {
          'ok': false,
          'mismatchedItemIds': ['service_terms', 'junk', 42],
          'emptyItemIds': ['privacy_policy'],
        },
        'serverNowMs': 1700000000000,
      });
      expect(t.integrity.ok, isFalse);
      expect(t.integrity.mismatchedItemIds, ['service_terms', 'junk']);
      expect(t.integrity.emptyItemIds, ['privacy_policy']);
      expect(t.hasRequiredItems, isFalse);
    });

    test('24 판정이 없으면 "문제 없음" 으로 읽지 않는다', () {
      // 검사가 조용히 꺼지는 경로를 만들지 않는다.
      for (final bad in <Object?>[
        null,
        'x',
        42,
        <String, Object?>{},
        {'ok': 'yes'},
        {'mismatchedItemIds': <String>[]},
      ]) {
        expect(() => RequiredLegalIntegrity.parse(bad),
            throwsA(isA<FormatException>()),
            reason: '$bad');
      }
    });

    testWidgets('25 무결성 실패면 재동의 화면이 체크박스를 그리지 않는다',
        (t) async {
      t.view.physicalSize = const Size(400, 900);
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.reset);
      final sent = <Map<String, dynamic>>[];
      final reads = LegalConsentReads(
        readiness: () async => _reconsent(),
        terms: () async => withIntegrity(const RequiredLegalIntegrity(
            ok: false, mismatchedItemIds: ['service_terms'])),
        storedConsent: () async => <String, dynamic>{},
        recordConsent: (r) async => sent.add(r),
      );
      await t.pumpWidget(MaterialApp(home: LegalConsentScreen(reads: reads)));
      for (var i = 0; i < 10; i++) {
        await t.pump(const Duration(milliseconds: 60));
      }
      expect(find.textContaining('약관 상태를 확인하지 못했어요'), findsOneWidget);
      expect(find.byType(Checkbox), findsNothing,
          reason: '발행본을 확인할 수 없는 필수 약관으로 동의를 받지 않는다');
      expect(sent, isEmpty);
    });

    test('26 네 동의 화면이 모두 같은 술어로 막는다', () {
      // `hasRequiredItems` 하나에 판정이 묶여 있으므로, 그것을 보는 화면은
      // 전부 자동으로 막힌다. 보지 않는 화면이 생기면 여기서 깨진다.
      for (final p in <String>[
        'lib/screens/auth/register_screen.dart',
        'lib/screens/auth/foreign_register_screen.dart',
        'lib/screens/auth/registration_recovery_screen.dart',
        'lib/screens/legal/legal_consent_screen.dart',
      ]) {
        expect(_code(p).contains('hasRequiredItems'), isTrue, reason: p);
      }
    });
  });

  // ───────────────────────────────────────────────────────────
  group('BP-3 STALE 판별은 한 곳', () {
    test('11 서비스가 판별하고, 화면은 그것만 쓴다', () {
      expect(LegalTermsService.isTermsVersionStale(_stale()), isTrue);
      expect(
          LegalTermsService.isTermsVersionStale(
              FirebaseFunctionsException(code: 'internal', message: 'boom')),
          isFalse);
      expect(LegalTermsService.isTermsVersionStale(Exception('network')),
          isFalse);

      for (final p in _consentSurfaces) {
        final src = _code(p);
        // 화면이 문자열을 다시 비교하지 않는다 — 한쪽만 고치면 갈라진다.
        expect(src.contains("'TERMS_VERSION_STALE'"), isFalse, reason: p);
        expect(src.contains('"TERMS_VERSION_STALE"'), isFalse, reason: p);
      }
    });

    test('12 동의를 제출하는 세 화면이 모두 그 판별을 쓴다', () {
      for (final p in [
        'lib/screens/auth/register_screen.dart',
        'lib/screens/auth/foreign_register_screen.dart',
        'lib/screens/auth/registration_recovery_screen.dart',
        'lib/screens/legal/legal_consent_screen.dart',
      ]) {
        expect(_code(p).contains('LegalTermsService.isTermsVersionStale'),
            isTrue, reason: '$p 가 약관 변경을 평범한 오류로 다룬다');
      }
    });
  });

  // ───────────────────────────────────────────────────────────
  group('BP-4 STALE 복구 — 행동', () {
    /// 재동의 화면을 띄운다. `recordConsent` 가 첫 호출에서 STALE 을 던진다.
    Future<_Probe> pump(WidgetTester t, {required bool staleOnFirst}) async {
      t.view.physicalSize = const Size(400, 900);
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.reset);

      final probe = _Probe();
      final reads = LegalConsentReads(
        readiness: () async {
          probe.readinessCalls++;
          return _reconsent();
        },
        terms: () async {
          probe.termsCalls++;
          // 두 번째 조회부터는 **새 판**을 돌려준다 — 시행된 B 다.
          return probe.termsCalls == 1
              ? _terms(version: '2026.08', body: '옛 판 A 본문')
              : _terms(version: '2026-11-08', body: '새 판 B 본문');
        },
        storedConsent: () async => <String, dynamic>{},
        recordConsent: (r) async {
          probe.sent.add(r);
          if (staleOnFirst && probe.sent.length == 1) throw _stale();
        },
      );
      await t.pumpWidget(MaterialApp(home: LegalConsentScreen(reads: reads)));
      for (var i = 0; i < 10; i++) {
        await t.pump(const Duration(milliseconds: 60));
      }
      return probe;
    }

    /// 필수 항목을 **열람하고** 동의한 뒤 제출한다.
    ///
    /// 열람이 동의가 되지 않는 구조라 본문을 먼저 열어야 체크가 된다
    /// (`LegalConsentList._open`). 기존 재동의 테스트와 같은 경로다.
    Future<void> agreeAndSubmit(WidgetTester t, {String title = '서비스 이용약관'}) async {
      await t.tap(find.descendant(
          of: find.ancestor(
              of: find.textContaining(title), matching: find.byType(Row)),
          matching: find.widgetWithText(TextButton, '보기')));
      await t.pumpAndSettle();
      await t.tap(find.widgetWithText(ElevatedButton, '동의하고 닫기'));
      await t.pumpAndSettle();
      await t.tap(find.widgetWithText(ElevatedButton, '동의하고 계속하기'));
      await t.pump();
      for (var i = 0; i < 12; i++) {
        await t.pump(const Duration(milliseconds: 60));
      }
    }

    testWidgets('13 STALE 이면 새 글을 다시 불러온다', (t) async {
      final probe = await pump(t, staleOnFirst: true);
      expect(probe.termsCalls, 1, reason: '첫 진입에 한 번만 조회한다');
      await agreeAndSubmit(t);

      expect(probe.sent, hasLength(1), reason: 'STALE 뒤 같은 payload 를 다시 보내지 않는다');
      expect(probe.termsCalls, greaterThan(1), reason: '새 글을 다시 묻지 않았다');
      // 머리글("이용약관이 변경되었습니다")과 겹치지 않는 **복구 안내** 문장으로 본다.
      expect(find.textContaining('변경된 내용을 확인하고 다시 동의해'), findsOneWidget,
          reason: '무슨 일이 있었는지 말해야 한다');
    });

    testWidgets('14 A 동의가 B 동의로 자동 승격되지 않는다', (t) async {
      final probe = await pump(t, staleOnFirst: true);
      await agreeAndSubmit(t);
      // 보낸 것은 옛 판 한 번뿐이고, 새 판에 대한 동의는 아직 없다.
      expect(probe.sent, hasLength(1));
      expect(probe.sent.first['service_terms']?['version'], '2026.08');
      // 새 판 동의가 자동으로 기록되지 않았다.
      expect(probe.sent.where((r) =>
          r['service_terms']?['version'] == '2026-11-08'), isEmpty);
    });

    testWidgets('15 STALE 아닌 실패는 평범한 저장 실패로 남는다', (t) async {
      t.view.physicalSize = const Size(400, 900);
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.reset);
      var termsCalls = 0;
      final reads = LegalConsentReads(
        readiness: () async => _reconsent(),
        terms: () async { termsCalls++; return _terms(); },
        storedConsent: () async => <String, dynamic>{},
        recordConsent: (r) async => throw Exception('network'),
      );
      await t.pumpWidget(MaterialApp(home: LegalConsentScreen(reads: reads)));
      for (var i = 0; i < 10; i++) {
        await t.pump(const Duration(milliseconds: 60));
      }
      await agreeAndSubmit(t);
      expect(find.textContaining('저장에 실패했습니다'), findsOneWidget);
      expect(find.textContaining('변경된 내용을 확인하고 다시 동의해'), findsNothing,
          reason: '네트워크 실패를 약관 변경으로 말하지 않는다');
      expect(termsCalls, 1, reason: '평범한 실패에 약관을 다시 묻지 않는다');
    });

    testWidgets('16 필수 항목이 빠진 응답은 ERROR 다', (t) async {
      t.view.physicalSize = const Size(400, 900);
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.reset);
      final reads = LegalConsentReads(
        readiness: () async => _reconsent(),
        terms: () async => EffectiveLegalTerms(
          serverNow: DateTime.utc(2026, 10, 8),
          upcoming: const [],
          items: [_item('marketing_consent', '마케팅', false)],
        ),
        storedConsent: () async => <String, dynamic>{},
        recordConsent: (r) async {},
      );
      await t.pumpWidget(MaterialApp(home: LegalConsentScreen(reads: reads)));
      for (var i = 0; i < 10; i++) {
        await t.pump(const Duration(milliseconds: 60));
      }
      expect(find.textContaining('약관 상태를 확인하지 못했어요'), findsOneWidget);
      expect(find.byType(Checkbox), findsNothing,
          reason: '불완전한 약관으로 동의를 받지 않는다');
    });
  });

  // ───────────────────────────────────────────────────────────
  group('BP-5 무한 재시도 금지', () {
    test('17 가입 화면의 재시도 루프가 STALE 에서 빠져나온다', () {
      for (final p in [
        'lib/screens/auth/register_screen.dart',
        'lib/screens/auth/foreign_register_screen.dart',
      ]) {
        final src = _code(p);
        final i = src.indexOf('isTermsVersionStale');
        expect(i, greaterThan(-1), reason: p);
        // 그 분기는 재시도 다이얼로그에 닿지 않고 **빠져나가야** 한다.
        final branch = src.substring(i, i + 700);
        expect(branch.contains('return;'), isTrue,
            reason: '$p 의 STALE 분기가 루프를 벗어나지 않는다');
        expect(branch.contains('resetChoices: true'), isTrue,
            reason: '$p 가 고른 것을 지우지 않는다 — 이전 선택은 다른 글에 대한 것이다');
      }
    });

    test('18 가입 정보를 지우지 않는다', () {
      // STALE 복구가 컨트롤러를 비우거나 화면을 리셋하지 않는다.
      for (final p in [
        'lib/screens/auth/register_screen.dart',
        'lib/screens/auth/foreign_register_screen.dart',
      ]) {
        final src = _code(p);
        final i = src.indexOf('isTermsVersionStale');
        final branch = src.substring(i, i + 700);
        for (final bad in [
          '.clear()',
          'popUntil',
          'pushReplacement',
          'signOut',
        ]) {
          expect(branch.contains(bad), isFalse,
              reason: '$p STALE 분기가 $bad 를 한다');
        }
      }
    });
  });

  // ───────────────────────────────────────────────────────────
  group('BP-6 시행 예정은 현재가 아니다', () {
    test('19 upcoming 은 activeItems 에 섞이지 않는다', () {
      final t = _terms(upcoming: [
        UpcomingLegalItemInfo(
          itemId: 'service_terms',
          version: '2026-11-08',
          effectiveAt: DateTime.utc(2026, 11, 7, 15),
        ),
      ]);
      expect(t.upcoming, hasLength(1));
      expect(t.activeItems.map((i) => i.version), everyElement('2026.08'),
          reason: '예정 판 버전이 현재 목록에 들어왔다');
      expect(t.hasRequiredItems, isTrue);
    });

    test('20 서버 응답의 upcoming 을 그대로 읽는다', () {
      final t = EffectiveLegalTerms.fromServer({
        'effectiveItems': [
          {'itemId': 'service_terms', 'version': '2026.08'},
        ],
        'upcomingItems': [
          {
            'itemId': 'service_terms',
            'version': '2026-11-08',
            'effectiveAtMs': 1762524000000,
          },
          'junk',
          {'itemId': '', 'version': 'x'},
        ],
        'requiredIntegrity': {'ok': true},
        'serverNowMs': 1700000000000,
      });
      expect(t.upcoming, hasLength(1));
      expect(t.upcoming.first.version, '2026-11-08');
      expect(t.upcoming.first.effectiveAt, isNotNull);
      expect(t.serverNow.millisecondsSinceEpoch, 1700000000000);
    });

    test('21 서버 시각을 기기 시계로 대신하지 않는다', () {
      final svc = _code('lib/services/legal_terms_service.dart');
      expect(svc.contains('DateTime.now()'), isFalse,
          reason: '시행 판정에 기기 시계를 쓰면 안 된다');
      final model = _code('lib/models/core/legal_terms_model.dart');
      final i = model.indexOf('class EffectiveLegalTerms');
      final j = model.indexOf('class LegalTermsItem');
      expect(model.substring(i, j).contains('DateTime.now()'), isFalse);
    });
  });
}

class _Probe {
  int readinessCalls = 0;
  int termsCalls = 0;
  final List<Map<String, dynamic>> sent = [];
}
