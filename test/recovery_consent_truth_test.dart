// [R7-LEGAL.1A] 저장된 동의는 사용자가 실제로 보고 고른 것이어야 한다.
//
// 복구 화면이 활성 약관 전부를 `agreed: true` 로 만들어 보내고 있었다.
// 본문을 보여 주지도, 묻지도 않았고, 선택 항목인 마케팅 수신 동의까지
// 동의로 기록했다. 가입 당시 거부했어도 복구를 거치면 동의로 뒤집혔다.
//
// 여기서 고정하는 것
//   A. 복구 — 본문 표시 · 선택 분리 · 거부 보존 · 선택 없이 진행 불가 ·
//      기존 동의 미덮어쓰기 · 기록 실패 시 성공 화면 금지
//   B. 내국인 가입 — 기록 실패를 조용히 삼키지 않음 · PASS ≠ 동의
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';

import 'package:ALfit/models/core/legal_terms_model.dart';
import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/screens/auth/registration_recovery_reads.dart';
import 'package:ALfit/screens/auth/registration_recovery_screen.dart';
import 'package:ALfit/utils/terms_consent_plan.dart';

const _v = '2026.08';

LegalTermsItem _item(String id, String title, bool required_,
        {String version = _v}) =>
    LegalTermsItem(
      id: id,
      title: title,
      content: '$title 본문입니다.\n' * 3,
      isRequired: required_,
      version: version,
      order: 1,
    );

LegalTerms _terms({String marketingVersion = _v}) => LegalTerms(items: [
      _item('service_terms', '서비스 이용약관', true),
      _item('privacy_policy', '개인정보 처리방침', true),
      _item('marketing_consent', '마케팅 정보 수신 동의 (선택)', false,
          version: marketingVersion),
    ]);

class _FakeApp extends Fake
    with MockPlatformInterfaceMixin
    implements FirebaseAppPlatform {
  @override
  String get name => defaultFirebaseAppName;
  @override
  FirebaseOptions get options => const FirebaseOptions(
      apiKey: 'k', appId: 'a', messagingSenderId: 's', projectId: 'p');
}

class _FakeCore extends FirebasePlatform with MockPlatformInterfaceMixin {
  @override
  FirebaseAppPlatform app([String name = defaultFirebaseAppName]) => _FakeApp();
  @override
  Future<FirebaseAppPlatform> initializeApp(
          {String? name, FirebaseOptions? options}) async =>
      _FakeApp();
  @override
  List<FirebaseAppPlatform> get apps => [_FakeApp()];
}

/// pending 계정이라 `currentUser` 가 null 인 상황을 그대로 흉내낸다.
class _P extends UserProvider {
  @override
  UserModel? get currentUser => null;
  @override
  bool get permissionsLoaded => true;
}

class _Recorder {
  final List<Map<String, dynamic>> calls = [];
  bool shouldFail = false;
}

Future<void> _pump(
  WidgetTester t, {
  required Map<String, dynamic> userDoc,
  required _Recorder recorder,
  LegalTerms? terms,
  Size size = const Size(400, 900),
}) async {
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);

  var current = Map<String, dynamic>.from(userDoc);
  final reads = RegistrationRecoveryReads(
    currentUid: () => 'u1',
    userDoc: (uid) async => current,
    terms: () async => terms ?? _terms(),
    recordConsent: (record) async {
      recorder.calls.add(record);
      if (recorder.shouldFail) throw Exception('network');
      // 서버가 필수 충족 시 active 로 올리는 것을 흉내낸다.
      final items = (terms ?? _terms()).activeItems.where((i) => i.isRequired);
      final ok = items.every((i) => record[i.id]?['agreed'] == true);
      if (ok) current = {...current, 'accountStatus': 'active'};
    },
  );

  await t.pumpWidget(
    // `.value` 를 쓴다 — create 는 lazy 라 화면이 읽지 않으면 만들어지지
    // 않고, 그 상태로 트리가 해체되면 dispose 가 null 을 캐스팅한다.
    ChangeNotifierProvider<UserProvider>.value(
      value: _P(),
      child: MaterialApp(
        home: RegistrationRecoveryScreen(reads: reads),
      ),
    ),
  );
  for (var i = 0; i < 12; i++) {
    await t.pump(const Duration(milliseconds: 60));
  }
}

/// CASE A/E — fingerprint + idCard 가 있어 약관만 남은 상태.
Map<String, dynamic> _caseAE({Object? consent}) => {
      'foreignIdentityFingerprint': 'fp',
      'idCardImagePath': 'id_cards/u1/x.jpg',
      'accountStatus': 'registration_pending',
      'role': 'USER',
      if (consent != null) 'termsConsent': consent,
    };

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
  });

  // ── A. 복구 ────────────────────────────────────────────────────────

  testWidgets('A1 필수 약관이 화면에 표시된다 — 버튼 하나로 끝내지 않는다', (t) async {
    await _pump(t, userDoc: _caseAE(), recorder: _Recorder());

    expect(find.text('서비스 이용약관'), findsOneWidget);
    expect(find.text('개인정보 처리방침'), findsOneWidget);
    expect(find.text('필수'), findsNWidgets(2));
    // 본문을 열 수 있어야 한다.
    expect(find.widgetWithText(TextButton, '보기'), findsNWidgets(3));
    expect(t.takeException(), isNull);
  });

  testWidgets('A2 선택 약관은 선택으로 표시되고 처음부터 꺼져 있다', (t) async {
    await _pump(t, userDoc: _caseAE(), recorder: _Recorder());

    expect(find.text('마케팅 정보 수신 동의 (선택)'), findsOneWidget);
    expect(find.text('선택'), findsOneWidget);

    // 기본 체크 금지 — 아직 받지 못한 동의는 필수든 선택이든 false 다.
    final boxes = t.widgetList<Checkbox>(find.byType(Checkbox)).toList();
    expect(boxes.length, 3);
    expect(boxes.every((b) => b.value == false), isTrue,
        reason: '사용자가 고르지 않은 것을 미리 체크해 두지 않는다');
    expect(t.takeException(), isNull);
  });

  testWidgets('A4 필수를 고르기 전에는 진행할 수 없다', (t) async {
    final rec = _Recorder();
    await _pump(t, userDoc: _caseAE(), recorder: rec);

    final btn = find.widgetWithText(ElevatedButton, '동의하고 가입 완료');
    expect(btn, findsOneWidget);
    expect(t.widget<ElevatedButton>(btn).onPressed, isNull,
        reason: '필수 미선택 상태에서 눌릴 수 있으면 안 된다');

    await t.tap(btn);
    await t.pump();
    expect(rec.calls, isEmpty, reason: '아무것도 보내면 안 된다');
    expect(t.takeException(), isNull);
  });

  testWidgets('A3 선택을 거부하면 거부가 그대로 전송된다', (t) async {
    final rec = _Recorder();
    await _pump(t, userDoc: _caseAE(), recorder: rec);

    // 필수 두 개만 동의한다 — 본문을 먼저 열어야 체크된다.
    for (final title in ['서비스 이용약관', '개인정보 처리방침']) {
      await t.tap(find.descendant(
          of: find.ancestor(
              of: find.text(title), matching: find.byType(Row)),
          matching: find.widgetWithText(TextButton, '보기')));
      await t.pumpAndSettle();
      // 뷰어 — 끝까지 읽고 동의
      await t.tap(find.widgetWithText(ElevatedButton, '동의하고 닫기'));
      await t.pumpAndSettle();
    }

    final btn = find.widgetWithText(ElevatedButton, '동의하고 가입 완료');
    expect(t.widget<ElevatedButton>(btn).onPressed, isNotNull);
    await t.tap(btn);
    await t.pump();
    await t.pump(const Duration(milliseconds: 100));

    expect(rec.calls.length, 1);
    final sent = rec.calls.single;
    expect(sent['service_terms']['agreed'], true);
    expect(sent['privacy_policy']['agreed'], true);
    // 거부는 비워 두지 않고 false 로 보낸다 — "묻지 않았다"와 구별된다.
    expect(sent['marketing_consent']['agreed'], false,
        reason: '선택 거부가 동의로 바뀌면 안 된다');
    expect(t.takeException(), isNull);
  });

  testWidgets('A5 이미 같은 버전으로 동의한 항목은 다시 보내지 않는다', (t) async {
    final rec = _Recorder();
    await _pump(
      t,
      userDoc: _caseAE(consent: {
        'service_terms': {'agreed': true, 'version': _v},
        'privacy_policy': {'agreed': true, 'version': _v},
        'marketing_consent': {'agreed': false, 'version': _v},
      }),
      recorder: rec,
    );

    // 전부 충족돼 있으므로 바로 진행할 수 있다.
    final btn = find.widgetWithText(ElevatedButton, '동의하고 가입 완료');
    expect(t.widget<ElevatedButton>(btn).onPressed, isNotNull);
    // 이미 받은 것은 '동의함'으로 보이고 체크를 바꿀 수 없다.
    expect(find.textContaining('(동의함)'), findsNWidgets(2));

    await t.tap(btn);
    await t.pump();
    await t.pump(const Duration(milliseconds: 100));

    // 보낼 것이 없다 — 최초 동의 시각을 지금으로 밀지 않는다.
    expect(rec.calls, isEmpty,
        reason: '기존 동의를 다시 보내면 agreedAt 이 덮인다');
    expect(t.takeException(), isNull);
  });

  testWidgets('A6 기록이 실패하면 성공으로 넘어가지 않는다', (t) async {
    final rec = _Recorder()..shouldFail = true;
    await _pump(t, userDoc: _caseAE(), recorder: rec);

    for (final title in ['서비스 이용약관', '개인정보 처리방침']) {
      await t.tap(find.descendant(
          of: find.ancestor(
              of: find.text(title), matching: find.byType(Row)),
          matching: find.widgetWithText(TextButton, '보기')));
      await t.pumpAndSettle();
      await t.tap(find.widgetWithText(ElevatedButton, '동의하고 닫기'));
      await t.pumpAndSettle();
    }

    await t.tap(find.widgetWithText(ElevatedButton, '동의하고 가입 완료'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 200));

    // 실패를 동의로 바꾸지 않는다 — 화면에 남아 다시 시도할 수 있다.
    expect(find.textContaining('서버 통신에 실패'), findsOneWidget);
    expect(find.widgetWithText(ElevatedButton, '동의하고 가입 완료'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  // ── 순수 판정 ──────────────────────────────────────────────────────

  test('A5-1 버전이 다른 과거 동의는 "받아 둔 동의"가 아니다', () {
    final items = _terms().activeItems;
    final stored = StoredConsent.parseMap({
      'service_terms': {'agreed': true, 'version': '2025.01'},
    });
    expect(TermsConsentPlan.isSatisfied(items.first, stored), isFalse);
    expect(
        TermsConsentPlan.itemsNeedingChoice(
                activeItems: items, stored: stored)
            .map((i) => i.id),
        containsAll(<String>['service_terms']));
  });

  test('A2-1 초기값은 받아 둔 동의만 true — 나머지는 전부 false', () {
    final items = _terms().activeItems;
    final stored = StoredConsent.parseMap({
      'service_terms': {'agreed': true, 'version': _v},
      'marketing_consent': {'agreed': false, 'version': _v},
    });
    final init = TermsConsentPlan.initialChoices(
        activeItems: items, stored: stored);
    expect(init['service_terms'], isTrue);
    expect(init['privacy_policy'], isFalse);
    expect(init['marketing_consent'], isFalse,
        reason: '거부했던 선택 항목이 다시 켜지면 안 된다');
  });

  test('A3-1 모양이 깨진 기록은 "동의함"으로 읽지 않는다', () {
    final stored = StoredConsent.parseMap({
      'service_terms': {'agreed': 'true', 'version': _v}, // bool 아님
      'privacy_policy': 'yes',
      'marketing_consent': {'version': _v}, // agreed 없음
    });
    expect(stored, isEmpty);
  });

  // ── B. 내국인 가입 ─────────────────────────────────────────────────

  String _registerCode() => File('lib/screens/auth/register_screen.dart')
      .readAsStringSync()
      .split('\n')
      .where((l) => !l.trimLeft().startsWith('//'))
      .join('\n');

  test('B7 동의 기록 실패를 조용히 삼키지 않는다', () {
    final code = _registerCode();
    // 예전 구조: 내국인만 try/catch 로 감싸고 그냥 지나갔다.
    expect(code.contains('무시'), isFalse,
        reason: '실패를 무시하는 경로가 남아 있다');
    // 동의 기록 구간에 국적 분기가 없어야 한다. 파일의 다른 곳(PASS·외국인
    // 신원 처리)에는 `_isKorean` 분기가 당연히 있으므로 구간을 좁혀서 본다.
    final i = code.indexOf('callableRecordTermsConsent');
    final region = code.substring(
        (i - 800).clamp(0, code.length), (i + 800).clamp(0, code.length));
    expect(RegExp(r'if \(!_isKorean\) \{').hasMatch(region), isFalse,
        reason: '국적으로 동의 기록 필수 여부를 가르면 안 된다');
    // 실패하면 사용자가 재시도하거나 그만두기를 고른다.
    expect(code.contains('_showTermsConsentRetryDialog()'), isTrue);
  });

  test('B8 PASS 성공이 동의 성공을 대신하지 않는다', () {
    final code = _registerCode();
    final i = code.indexOf('callableRecordTermsConsent');
    expect(i, greaterThan(0));
    // 기록 호출 주변에 "PASS 로 보완" 류의 우회가 없어야 한다.
    final around = code.substring(
        (i - 1500).clamp(0, code.length), (i + 1500).clamp(0, code.length));
    expect(around.contains('passVerified') && around.contains('catch'), isFalse,
        reason: 'PASS 인증을 동의 기록의 대체로 쓰면 안 된다');
  });

  test('B9 재시도 루프는 성공할 때까지 돈다 — 한 번 실패로 끝나지 않는다', () {
    final code = _registerCode();
    expect(code.contains('while (!recorded)'), isTrue);
    expect(code.contains('recorded = true;'), isTrue);
  });

  test('B10 그만두면 가입 완료로 표현하지 않는다', () {
    final code = _registerCode();
    final loop = code.indexOf('while (!recorded)');
    final success = code.indexOf("ToastHelper.showSuccess('가입을 환영합니다!')");
    expect(loop, greaterThan(0));
    expect(success, greaterThan(loop),
        reason: '성공 토스트는 기록 루프 이후에 와야 한다');
    // 그만두기는 return 이다 — 성공 토스트·HOME 이동에 닿지 않는다.
    final between = code.substring(loop, success);
    expect(between.contains('return;'), isTrue);
  });
}
