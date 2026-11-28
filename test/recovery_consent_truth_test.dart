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
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

// [.54] 동의 목록·재동의 화면 글자가 낱말 단위(TextLayout)로 바뀌어 보이는 글자로 찾는다.
import 'support/visible_text.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:crypto/crypto.dart';

import 'package:ALfit/models/core/legal_terms_model.dart';
import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/screens/auth/registration_recovery_reads.dart';
import 'package:ALfit/screens/auth/registration_recovery_screen.dart';
import 'package:ALfit/utils/terms_consent_plan.dart';
import 'package:ALfit/theme/app_colors.dart';
import 'package:ALfit/theme/role_theme.dart';
import 'support/du1_vq_capture.dart';

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

// [R7-PAYROLL-POLICY.5B] 서버가 판정한 시행 중 약관을 흉내낸다.
EffectiveLegalTerms _terms({String marketingVersion = _v}) =>
    EffectiveLegalTerms(
      serverNow: DateTime.utc(2026, 10, 8),
      upcoming: const [],
      items: [
      _item('service_terms', '서비스 이용약관', true),
      _item('privacy_policy', '개인정보 처리방침', true),
      _item('marketing_consent', '마케팅 정보 수신 동의 (선택)', false,
          version: marketingVersion),
      ],
    );

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
  EffectiveLegalTerms? terms,
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

    expect(findVisibleText('서비스 이용약관'), findsOneWidget);
    expect(findVisibleText('개인정보 처리방침'), findsOneWidget);
    expect(find.text('필수'), findsNWidgets(2));
    // 본문을 열 수 있어야 한다.
    expect(find.widgetWithText(TextButton, '보기'), findsNWidgets(3));
    expect(t.takeException(), isNull);
  });

  testWidgets('A2 선택 약관은 선택으로 표시되고 처음부터 꺼져 있다', (t) async {
    await _pump(t, userDoc: _caseAE(), recorder: _Recorder());

    expect(findVisibleText('마케팅 정보 수신 동의 (선택)'), findsOneWidget);
    expect(findVisibleText('선택'), findsOneWidget);

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
              of: findVisibleText(title), matching: find.byType(Row)),
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
    expect(findVisibleTextContaining('(동의함)'), findsNWidgets(2));

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
              of: findVisibleText(title), matching: find.byType(Row)),
          matching: find.widgetWithText(TextButton, '보기')));
      await t.pumpAndSettle();
      await t.tap(find.widgetWithText(ElevatedButton, '동의하고 닫기'));
      await t.pumpAndSettle();
    }

    await t.tap(find.widgetWithText(ElevatedButton, '동의하고 가입 완료'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 200));

    // 실패를 동의로 바꾸지 않는다 — 화면에 남아 다시 시도할 수 있다.
    expect(findVisibleTextContaining('서버 통신에 실패'), findsOneWidget);
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

  // [R7-LEGAL.DEPLOY §14] DEV 최초 발행 직후 실제로 터진 경우.
  //
  //   발행 전에는 항목에 발행본 id 가 없어서 version 만 맞으면 "이미 받아 둔
  //   동의" 로 잡혔다. 발행 뒤에도 같은 규칙이면, 1B 이전 기록을 가진
  //   사용자가 재동의 화면에서 체크가 잠긴 채 payload 가 비어 아무것도
  //   보내지 못한다 — 할 일이 영원히 남는다.
  test('A5-2 발행본이 생긴 뒤, 발행본 id 없는 옛 기록은 다시 받아야 한다', () {
    final item = _item('service_terms', '서비스 이용약관', true)
        .copyWith(revisionId: 'service_terms__$_v');
    final stored = StoredConsent.parseMap({
      // 1B 이전 기록 — version 은 같지만 어떤 글인지 모른다.
      'service_terms': {'agreed': true, 'version': _v},
    });

    expect(TermsConsentPlan.isLocked(item, stored), isFalse,
        reason: '증명할 수 없는 기록으로 체크를 잠그면 안 된다');
    expect(
        TermsConsentPlan.itemsNeedingChoice(
                activeItems: [item], stored: stored)
            .map((i) => i.id),
        contains('service_terms'));
    final payload = TermsConsentPlan.buildPayload(
        activeItems: [item], stored: stored,
        choices: {'service_terms': true});
    expect(payload.containsKey('service_terms'), isTrue,
        reason: '보낼 것이 없으면 재동의가 끝나지 않는다');
  });

  test('A5-3 같은 발행본을 가리키는 기록은 다시 보내지 않는다', () {
    final item = _item('service_terms', '서비스 이용약관', true)
        .copyWith(revisionId: 'service_terms__$_v');
    final stored = StoredConsent.parseMap({
      'service_terms': {
        'agreed': true, 'version': _v, 'revisionId': 'service_terms__$_v',
      },
    });
    expect(TermsConsentPlan.isLocked(item, stored), isTrue);
    expect(
        TermsConsentPlan.buildPayload(
            activeItems: [item], stored: stored,
            choices: {'service_terms': true}),
        isEmpty,
        reason: '같은 값을 다시 보내면 최초 동의 시각이 밀린다');
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

  // [DU1 구현169] 기존 A6 경로의 RoleTheme · 320×640 관측 — 아래 _rrbCases
  _rrbCases();

  // [DU-S005-LOCKED-LABEL-176] 기존 A5 데이터의 잠긴 동의 제목 관측 — 아래 _lckQCases(D176_PHASE 없으면 skip)
  _lckQCases();
}

// ── [DU1 구현169 · 후속169] C0-RRB-N / C0-RRB-B — 기존 A6 경로의 서버 실패 배너 관측 ──
// 보기 → 동의하고 닫기 ×2 → 동의하고 가입 완료 → 기록 실패(_Recorder.shouldFail) → 같은 termsOnly 배너.
// RoleTheme.workerTheme · 320×640 · DPR1 · scaler1 / 2 · LOCAL 렌더(login 라우팅 실증 아님).
// 데이터는 _caseAE() · _terms() · _Recorder 그대로다. _pump 는 테마 / 배율을 받지 않아 고치지 않고,
// 아래 reads 는 _pump:101~114 와 같은 동작에 호출 수만 센다. 새 fixture / 서버 seam / flag 0.
// DU1_VQ_PHASE 가 없으면 캡처하지 않는다(H). N 이 실패하면 B 는 아무것도 하기 전에 끝난다.
const _rrbMsg = '서버 통신에 실패했습니다.\n인터넷 연결을 확인하고 다시 시도해주세요.';
bool _rrbFailed = false;

void _rrbCases() {
  for (final c in const [(id: 'C0-RRB-N', s: 1.0), (id: 'C0-RRB-B', s: 2.0)]) {
    testWidgets('${c.id} 복구 기록 실패 배너 320×640@${c.s} — 기존 A6 경로 실제 5 tap', (t) async {
      expect(_rrbFailed, isFalse, reason: '앞 사례 실패 — 이 사례는 진행하지 않는다');
      try {
        await _rrbBody(t, c.id, c.s);
      } catch (_) {
        _rrbFailed = true;
        rethrow;
      }
    });
  }
}

List<double> _rl(Rect r) => <double>[r.left, r.top, r.right, r.bottom];

Future<void> _rrbBody(WidgetTester t, String id, double s) async {
  await t.runAsync(vqLoadFonts);
  final overflows = <String>[];
  final prev = FlutterError.onError;
  FlutterError.onError = (d) {
    final m = d.exceptionAsString();
    if (m.contains('overflowed')) {
      overflows.add(m.split('\n').first);
    } else {
      prev?.call(d);
    }
  };
  addTearDown(() => FlutterError.onError = prev);
  t.view.physicalSize = const Size(320, 640);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);

  final rec = _Recorder()..shouldFail = true;
  var docCalls = 0;
  var termCalls = 0;
  var current = Map<String, dynamic>.from(_caseAE());
  final reads = RegistrationRecoveryReads(
    currentUid: () => 'u1',
    userDoc: (uid) async {
      docCalls++;
      return current;
    },
    terms: () async {
      termCalls++;
      return _terms();
    },
    recordConsent: (record) async {
      rec.calls.add(record);
      if (rec.shouldFail) throw Exception('network');
      final items = _terms().activeItems.where((i) => i.isRequired);
      final ok = items.every((i) => record[i.id]?['agreed'] == true);
      if (ok) current = {...current, 'accountStatus': 'active'};
    },
  );
  final key = GlobalKey();
  await t.pumpWidget(ChangeNotifierProvider<UserProvider>.value(
    value: _P(),
    child: RepaintBoundary(
      key: key,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: RoleTheme.workerTheme,
        builder: (ctx, child) => MediaQuery(
            data: MediaQuery.of(ctx).copyWith(textScaler: TextScaler.linear(s)),
            child: child!),
        home: RegistrationRecoveryScreen(reads: reads),
      ),
    ),
  ));
  void healthy(String where) {
    expect(overflows, isEmpty, reason: '$id $where: overflow ${overflows.join(' | ')}');
    expect(t.takeException(), isNull, reason: '$id $where: 예외');
  }

  healthy('pumpWidget');
  Future<void> frames(int n, [int ms = 60]) async {
    for (var i = 0; i < n; i++) {
      await t.pump(Duration(milliseconds: ms));
      healthy('pump');
    }
  }

  void out(String l) {
    // ignore: avoid_print
    print(l);
  }

  await frames(12);
  expect(findVisibleText('약관 동의가 필요합니다'), findsOneWidget, reason: 'termsOnly 직접 진입');
  final screen = find.byType(RegistrationRecoveryScreen);
  final list = find.descendant(of: screen, matching: find.byType(Scrollable)).first;
  Finder btn(String label) => find
      .ancestor(of: findVisibleText(label), matching: find.byWidgetPredicate((w) => w is ButtonStyleButton))
      .first;
  final cta = btn('동의하고 가입 완료');
  final back = btn('로그인 화면으로 돌아가기');
  var taps = 0;
  var listDrags = 0;
  var viewerDrags = 0;
  bool hits(Finder f) =>
      t.hitTestOnBinding(t.getCenter(f)).path.any((e) => e.target == t.renderObject(f));

  Future<void> tapReal(Finder f, String what) async {
    expect(f, findsOneWidget, reason: what);
    final at = t.getCenter(f);
    expect(hits(f), isTrue, reason: '$what 중심이 그 위젯에 hit 하지 않는다');
    await t.tap(f);
    healthy('tap $what');
    taps++;
    out('$id tap#$taps $what at $at');
  }

  Future<void> listDrag(double dy, String what) async {
    listDrags++;
    expect(listDrags <= 12, isTrue, reason: '$id 목록 drag 한도 12 초과 ($what)');
    expect(dy.abs() <= 200, isTrue, reason: '회당 200dp 이하');
    out('$id drag 목록 #$listDrags dy=$dy ($what)');
    await t.drag(list, Offset(0, dy));
    healthy('drag 목록');
    await frames(6, 50);
  }

  Future<void> intoList(Finder f, String what) async {
    for (;;) {
      final vp = t.getRect(list);
      var dy = -200.0;
      if (f.evaluate().isNotEmpty) {
        final r = t.getRect(f.first);
        if (r.top >= vp.top - 0.01 && r.bottom <= vp.bottom + 0.01) return;
        dy = r.bottom > vp.bottom ? -(r.bottom - vp.bottom + 8) : (vp.top - r.top + 8);
        if (dy.abs() < 60) dy = dy < 0 ? -60.0 : 60.0;
        if (dy < -200) dy = -200.0;
        if (dy > 200) dy = 200.0;
      }
      await listDrag(dy, what);
    }
  }

  Future<void> agreeVia(String title) async {
    final view = find.descendant(
        of: find.ancestor(of: findVisibleText(title), matching: find.byType(Row)),
        matching: find.widgetWithText(TextButton, '보기'));
    await intoList(view, '$title 보기');
    await frames(4, 50);
    await tapReal(view, '$title 보기');
    await frames(12);
    final agree = find.byType(ElevatedButton);
    expect(agree, findsOneWidget, reason: '$title viewer 열림');
    var vd = 0;
    while (t.widget<ElevatedButton>(agree).onPressed == null) {
      expect(vd < 6, isTrue, reason: '$id $title viewer drag 6 안에 동의하고 닫기가 켜지지 않았다');
      vd++;
      viewerDrags++;
      out('$id drag viewer $title #$vd');
      await t.dragFrom(const Offset(160, 320), const Offset(0, -200));
      healthy('drag viewer');
      await frames(6, 50);
    }
    out('$id viewer $title 동의 활성 · viewer drag $vd');
    expect(find.descendant(of: agree, matching: find.text('동의하고 닫기')),
        findsOneWidget, reason: '$title viewer 활성 문구');
    await tapReal(agree, '$title 동의하고 닫기');
    await frames(12);
    expect(screen, findsOneWidget, reason: '$title viewer 닫힘·복구 화면 복귀');
  }

  await agreeVia('서비스 이용약관');
  await agreeVia('개인정보 처리방침');
  List<bool?> boxes() => t.widgetList<Checkbox>(find.byType(Checkbox)).map((b) => b.value).toList();
  expect(boxes(), <bool?>[true, true, false], reason: '필수 2 동의 · 선택 미동의');
  expect(t.widget<ElevatedButton>(cta).onPressed, isNotNull, reason: '제출 전 CTA 활성');
  await tapReal(cta, '동의하고 가입 완료');
  await frames(20);
  expect(taps, 5, reason: '실제 tap 정확 5');
  expect(rec.calls.length, 1, reason: 'recordConsent 1');
  expect(docCalls, 1, reason: 'userDoc 1 — 실패 뒤 fresh 읽기 0');
  expect(termCalls, 1, reason: 'terms 1');
  final sent = rec.calls.single;
  expect(sent.keys.toSet(), <String>{'service_terms', 'privacy_policy', 'marketing_consent'});
  expect(sent['service_terms'], {'agreed': true, 'version': _v});
  expect(sent['privacy_policy'], {'agreed': true, 'version': _v});
  expect(sent['marketing_consent'], {'agreed': false, 'version': _v});
  expect(cta, findsOneWidget, reason: '같은 termsOnly 에 남음');
  expect(findVisibleText('외국인 가입 이어서 완료'), findsNothing, reason: '성공 · 다른 상태 전환 0');
  expect(t.widget<ElevatedButton>(cta).onPressed, isNotNull, reason: '기록 중 해제');
  expect(boxes(), <bool?>[true, true, false], reason: '실패 뒤 선택 보전');

  final msg = find.text(_rrbMsg);
  final banner = find
      .ancestor(
          of: msg,
          matching: find.byWidgetPredicate((w) =>
              w is Container && w.decoration is BoxDecoration && (w.decoration! as BoxDecoration).border != null));
  final icon = find.descendant(of: banner, matching: find.byIcon(Icons.error_outline));
  await intoList(banner, '서버 실패 배너');
  expect(msg, findsOneWidget, reason: '오류 문구 원문 일치');
  expect(icon, findsOneWidget, reason: '배너 아이콘');
  final pos0 = t.state<ScrollableState>(list).position;
  List<double> nums() {
    final p = t.state<ScrollableState>(list).position;
    return <double>[
      p.pixels, p.minScrollExtent, p.maxScrollExtent, p.viewportDimension,
      for (final f in [banner, msg, icon, list, cta, back]) ..._rl(t.getRect(f)),
    ];
  }

  bool flags() {
    final p = t.state<ScrollableState>(list).position;
    return identical(p, pos0) && p.hasContentDimensions && !p.outOfRange &&
        !p.isScrollingNotifier.value && !t.binding.hasScheduledFrame;
  }

  double spread(List<List<double>> w) {
    var m = 0.0;
    for (var k = 0; k < w[0].length; k++) {
      var hi = w[0][k];
      var lo = w[0][k];
      for (final v in w) {
        if (v[k] > hi) hi = v[k];
        if (v[k] < lo) lo = v[k];
      }
      if (hi - lo > m) m = hi - lo;
    }
    return m;
  }

  final samples = <List<double>>[];
  final oks = <bool>[];
  var stableAt = 0;
  for (var i = 1; i <= 20; i++) {
    await t.pump(const Duration(milliseconds: 50));
    healthy('정착 표본');
    samples.add(nums());
    oks.add(flags() && samples.last.every((v) => v.isFinite));
    if (samples.length >= 3 &&
        oks.sublist(oks.length - 3).every((ok) => ok) &&
        spread(samples.sublist(samples.length - 3)) <= 0.1) {
      stableAt = i;
      break;
    }
  }
  out('$id 정착 samples=${samples.length} stableAt=$stableAt flags=${flags()}');
  expect(stableAt > 0, isTrue, reason: '50ms×20 안에 안정 창(3표본 ≤0.1 · inRange · idle)이 없다');
  await t.pump(const Duration(milliseconds: 50));
  healthy('hold');
  final held = nums();
  expect(flags() && spread([samples.last, held]) <= 0.1, isTrue, reason: 'hold 50ms 유지 실패');
  final vpr = t.getRect(list);
  final br = t.getRect(banner);
  final cr = t.getRect(cta);
  final kr = t.getRect(back);
  bool inside(Rect a, Rect b) =>
      a.left >= b.left - 0.01 && a.top >= b.top - 0.01 && a.right <= b.right + 0.01 && a.bottom <= b.bottom + 0.01;
  final scr = Rect.fromLTWH(0, 0, 320, 640);
  expect(inside(br, vpr), isTrue, reason: '배너 전체가 목록 viewport 안');
  expect(inside(cr, scr) && inside(kr, scr), isTrue, reason: 'CTA · 복귀가 화면 안');
  expect(br.bottom <= cr.top + 0.01 && vpr.bottom <= cr.top + 0.01, isTrue, reason: 'footer 겹침 0');
  final dynamic para = t.renderObject(msg);
  final tops = (para.getBoxesForSelection(TextSelection(baseOffset: 0, extentOffset: _rrbMsg.length)) as List)
      .map((b) => (b.top as double).toStringAsFixed(1))
      .toSet();
  final dynamic st = para.text.style;
  final mq = MediaQuery.of(t.element(screen));
  final pz = t.state<ScrollableState>(list).position;
  String j(List<double> v) => v.map((x) => x.toStringAsFixed(4)).join(',');
  final cond = <String, Object?>{
    'entry': 'RegistrationRecoveryScreen(reads) termsOnly — Q 기존 A6 경로, LOCAL(login 라우팅 실증 아님)',
    'theme': 'RoleTheme.workerTheme · light', 'viewport': '320x640', 'dpr': 1.0, 'textScaler': s,
    'mq': 'padding=${mq.padding} viewInsets=${mq.viewInsets}', 'keyboard': '닫힘(inset 0)',
    'fonts': 'vqLoadFonts: NotoSansKR Regular+Bold · Roboto=NotoSansKR · MaterialIcons(SDK)',
    'data': 'Q _caseAE() · _terms() 필수2/선택1 · version $_v · uid u1 · role USER',
    'fixture': 'Q _Recorder(shouldFail=true) · reads = _pump:101~114 동작 + 호출 수',
    'capture': 'RepaintBoundary(MaterialApp) 320x640 전체',
    'state': '서버 실패 배너(termsOnly) 정착 뒤',
    'taps': taps, 'listDrags': listDrags, 'viewerDrags': viewerDrags,
    'recordCalls': rec.calls.length, 'docCalls': docCalls, 'termCalls': termCalls,
  };
  healthy('캡처 직전');
  await vqCapture(t, key, '${id}_banner', conditions: cond);
  final afterCap = nums();
  out('RRB|$id|phase=$vqPhase|scaler=$s|taps=$taps|listDrags=$listDrags|viewerDrags=$viewerDrags'
      '|recordCalls=${rec.calls.length}|docCalls=$docCalls|termCalls=$termCalls'
      '|ctaEnabled=${t.widget<ElevatedButton>(cta).onPressed != null}|checkboxes=${boxes().join(',')}'
      '|lines=${tops.length}|fontSize=${st.fontSize}|fontWeight=${st.fontWeight}|fontFamily=${st.fontFamily}'
      '|color=${st.color}|textScaler=${para.textScaler}|stableAt=$stableAt|overflows=${overflows.length}'
      '|pos=${j(<double>[pz.pixels, pz.minScrollExtent, pz.maxScrollExtent, pz.viewportDimension])}'
      '|banner=${j(_rl(br))}|msg=${j(_rl(t.getRect(msg)))}|icon=${j(_rl(t.getRect(icon)))}'
      '|viewport=${j(_rl(vpr))}|cta=${j(_rl(cr))}|back=${j(_rl(kr))}'
      '|holdDelta=${spread([samples.last, held])}|captureDelta=${spread([held, afterCap])}');
  out('RRB-TEXT|$id|${(para.text.toPlainText() as String).replaceAll(String.fromCharCode(10), String.fromCharCode(92) + 'n')}');
  out('RRB-PAYLOAD|$id|$sent');
  expect(flags() && spread([held, afterCap]) <= 0.1, isTrue, reason: '캡처 전후 유지 실패');
  expect(overflows, isEmpty, reason: 'overflow 0');
  expect(t.takeException(), isNull);
  FlutterError.onError = prev;
}

// ── [DU-S005-LOCKED-LABEL-176 r1] C0-LCK-QN / C0-LCK-QB — 기존 A5 데이터의 잠긴 동의 제목 관측 ──
// 후속175 §5: _caseAE(A5 consent) · _terms() · version _v 그대로(A5 :227~231 과 같은 literal). 새 fixture 0.
// tap · 제출 · 뷰어 진입 0. 목록 안 실제 drag 만(사례당 ≤6, (160,320) 에서 dy ∈ [-160, -40]).
// RoleTheme.workerTheme · 320×640 · DPR1 · scaler 1 / 2 · 키보드 inset 0 · vqLoadFonts · 초기 frame 12×60(RRB 와 같다).
// 색은 단언하지 않고 기록한다(전후 같은 코드, phase 별 기대색은 check176). 진입 guard · 동결 · 중단은 아래 공통 절차.
const _lckLockedQ = <String>['서비스 이용약관 (동의함)', '개인정보 처리방침 (동의함)'];
const _lckOtherQ = <String>['마케팅 정보 수신 동의 (선택)'];

void _lckQCases() {
  _lckCase('C0-LCK-QN', 1.0, '복구 잠긴 동의 제목 320×640@1.0 — A5 데이터 · tap 0', _lckQBody);
  _lckCase('C0-LCK-QB', 2.0, '복구 잠긴 동의 제목 320×640@2.0 — A5 데이터 · tap 0', _lckQBody);
}

Future<void> _lckQBody(WidgetTester t, String id, double s, Map<String, String> inputs) async {
  await t.runAsync(vqLoadFonts);
  final overflows = <String>[];
  final prev = FlutterError.onError;
  FlutterError.onError = (d) {
    final m = d.exceptionAsString();
    if (m.contains('overflowed')) {
      overflows.add(m.split('\n').first);
    } else {
      prev?.call(d);
    }
  };
  addTearDown(() => FlutterError.onError = prev);
  t.view.physicalSize = const Size(320, 640);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);

  final rec = _Recorder();
  var docCalls = 0;
  var termCalls = 0;
  var current = Map<String, dynamic>.from(_caseAE(consent: {
    'service_terms': {'agreed': true, 'version': _v},
    'privacy_policy': {'agreed': true, 'version': _v},
    'marketing_consent': {'agreed': false, 'version': _v},
  }));
  final reads = RegistrationRecoveryReads(
    currentUid: () => 'u1',
    userDoc: (uid) async {
      docCalls++;
      return current;
    },
    terms: () async {
      termCalls++;
      return _terms();
    },
    recordConsent: (record) async {
      rec.calls.add(record);
      final items = _terms().activeItems.where((i) => i.isRequired);
      final ok = items.every((i) => record[i.id]?['agreed'] == true);
      if (ok) current = {...current, 'accountStatus': 'active'};
    },
  );
  final key = GlobalKey();
  await t.pumpWidget(ChangeNotifierProvider<UserProvider>.value(
    value: _P(),
    child: RepaintBoundary(
      key: key,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: RoleTheme.workerTheme,
        builder: (ctx, child) => MediaQuery(
            data: MediaQuery.of(ctx).copyWith(textScaler: TextScaler.linear(s)),
            child: child!),
        home: RegistrationRecoveryScreen(reads: reads),
      ),
    ),
  ));
  void healthy(String where) {
    expect(overflows, isEmpty, reason: '$id $where: overflow ${overflows.join(' | ')}');
    expect(t.takeException(), isNull, reason: '$id $where: 예외');
  }

  healthy('pumpWidget');
  for (var i = 0; i < 12; i++) {
    await t.pump(const Duration(milliseconds: 60));
    healthy('pump');
  }
  final frames = <String>['init:12x60'];
  expect(findVisibleText('약관 동의가 필요합니다'), findsOneWidget, reason: 'termsOnly 직접 진입');
  final screen = find.byType(RegistrationRecoveryScreen);
  final list = find.descendant(of: screen, matching: find.byType(Scrollable)).first;
  final cta = find.widgetWithText(ElevatedButton, '동의하고 가입 완료');
  final back = find
      .ancestor(of: findVisibleText('로그인 화면으로 돌아가기'), matching: find.byWidgetPredicate((w) => w is ButtonStyleButton))
      .first;
  final bg = Theme.of(t.element(screen)).scaffoldBackgroundColor;
  expect(t.widget<Scaffold>(find.descendant(of: screen, matching: find.byType(Scaffold)).first).backgroundColor, isNull,
      reason: 'Q 바탕 = 테마 화면바탕');

  List<bool?> boxes() => t.widgetList<Checkbox>(find.byType(Checkbox)).map((b) => b.value).toList();
  List<bool> editable() => t.widgetList<Checkbox>(find.byType(Checkbox)).map((b) => b.onChanged != null).toList();
  final views = find.widgetWithText(TextButton, '보기');
  bool viewsOn() => t.widgetList<TextButton>(views).every((b) => b.onPressed != null);
  void state(String where) {
    // [repair-TB3] 2.0 진입 직후에는 지연 목록 항목이 캐시 밖이라 아직 만들어지지 않는다(TB2 실측 QB boxes=[]).
    //   진입에서만, 체크 3개가 다 만들어지기 전이면 위젯 상태 단언을 '정착 뒤' 로 미룬다. 호출 수 단언은 항상 본다.
    if (where != '진입' || t.widgetList<Checkbox>(find.byType(Checkbox)).length == 3) {
      expect(boxes(), <bool?>[true, true, false], reason: '$where 체크 [동의, 동의, 거부]');
      expect(editable(), <bool>[false, false, true], reason: '$where 잠긴 필수2 · 선택 편집 가능');
      expect(views, findsNWidgets(3), reason: '$where 보기 3');
      expect(viewsOn(), isTrue, reason: '$where 보기 3 활성');
      expect(t.widget<ElevatedButton>(cta).onPressed, isNotNull, reason: '$where CTA 활성');
    }
    expect(rec.calls.length, 0, reason: '$where recordConsent 0');
    expect(docCalls, 1, reason: '$where userDoc 1');
    expect(termCalls, 1, reason: '$where terms 1');
  }

  state('진입');
  final out = await _lckObserve(t,
      id: id, s: s, key: key, list: list, healthy: healthy, state: state, overflows: overflows,
      locked: _lckLockedQ, others: _lckOtherQ, fixed: <String, Finder>{'cta': cta, 'back': back}, bg: bg,
      cond: <String, Object?>{
        'entry': 'RegistrationRecoveryScreen(reads) termsOnly — Q 기존 A5 데이터, LOCAL(login 라우팅 실증 아님)',
        'data': 'Q _caseAE(A5 consent: 필수2 agreed true · 선택 false · version $_v) · _terms() · uid u1 · role USER',
        'fixture': 'Q _Recorder() · reads = _pump:104~116 동작 + 호출 수',
      },
      counters: () => 'recordCalls=${rec.calls.length}|docCalls=$docCalls|termCalls=$termCalls|checkboxes=${boxes().join(',')}'
          '|editable=${editable().join(',')}|viewsOn=${viewsOn()}|ctaEnabled=${t.widget<ElevatedButton>(cta).onPressed != null}',
      inputs: inputs,
      frames: frames);
  FlutterError.onError = prev;
  _lckFinish(id, out);
}

// ── [DU-S005-LOCKED-LABEL-176 r1] 공통 관측 절차 — 두 소비처(Q · U)가 같은 바이트를 쓴다 ──
// Q 와 U 는 다른 library 라 같은 본문을 각 파일 끝에 둔다(helper 파일 신설 0 · 공통 helper 수정 0).
// 필수 env(없으면 사례를 skip — 일반 시험 실행에 영향 0. 있으면 하나라도 틀리면 진입 실패):
//   D176_PHASE=before|after · D176_DIR=<attempt 폴더(있어야 함)> · DU1_VQ_PHASE=du176-<phase> · DU1_VQ_OUT · DU1_VQ_RUN
//   D176_INPUT_SHA=<경로=sha;…>(runner 가 고정표에서 넘긴 이번 phase 기대 입력) · after 만 D176_FROZEN · D176_FROZEN_SHA.
// 첫 실패 중단(파일 순서 무관): STOP 이 있거나, 이미 시작된(.start) 사례 중 .ok 가 없는 것이 있거나, 자기 .start 가 있으면 진입 실패.
//   실패하면 STOP 에 append 한다(기록). CLI 는 --fail-fast --concurrency=1, 최종 판정은 check176 의 reporter 전수 검산이다.
// 사례 기록(.record.json)과 완료 표식(.ok)은 모든 단언 · 캡처 뒤 마지막 문장으로만 쓴다.
const _lckOrder = <String>['C0-LCK-QN', 'C0-LCK-QB', 'C0-LCK-UN', 'C0-LCK-UB'];
const _lckInputs = <String>[
  'lib/widgets/auth/legal_consent_list.dart',
  'lib/screens/auth/registration_recovery_screen.dart',
  'lib/screens/legal/legal_consent_screen.dart',
  'lib/utils/terms_consent_plan.dart',
  'lib/theme/app_colors.dart',
  'lib/theme/role_theme.dart',
  'test/recovery_consent_truth_test.dart',
  'test/legal_reconsent_consumer_test.dart',
  'test/support/du1_vq_capture.dart',
  'test/support/visible_text.dart',
  'assets/fonts/NotoSansKR-Regular.ttf',
  'assets/fonts/NotoSansKR-Bold.ttf',
];
final Map<String, String> _lckEnv = Platform.environment;
final String _lckPhase = _lckEnv['D176_PHASE'] ?? '';
final String _lckDir = _lckEnv['D176_DIR'] ?? '';
final bool _lckSkip = _lckPhase.isEmpty;

String _lckSha(String p) => sha256.convert(File(p).readAsBytesSync()).toString();
String _lckHex(Color? c) => c == null ? 'null' : '0x${c.toARGB32().toRadixString(16).padLeft(8, '0')}';
List<double> _lckRl(Rect r) => <double>[r.left, r.top, r.right, r.bottom];

void _lckStop(String id, Object e) {
  if (_lckDir.isEmpty) return;
  try {
    File('$_lckDir/STOP').writeAsStringSync('$id ${e.toString().split('\n').first}\n', mode: FileMode.append);
  } catch (_) {}
}

/// 사례 하나를 등록한다. 진입 guard → body → (실패면 STOP append 후 rethrow).
void _lckCase(String id, double s, String desc,
    Future<void> Function(WidgetTester, String, double, Map<String, String>) body) {
  testWidgets('$id $desc', (t) async {
    try {
      final shas = _lckEnter(id);
      await body(t, id, s, shas);
      // body 는 _lckFinish 를 마지막 문장으로 호출한다. 여기서는 완료 표식 존재만 본다.
      expect(File('$_lckDir/$id.ok').existsSync(), isTrue, reason: '$id 완료 표식 없음');
    } catch (e) {
      _lckStop(id, e);
      rethrow;
    }
  }, skip: _lckSkip);
}

/// 진입 guard. 실제 입력 SHA 를 계산해 기대값과 대조하고 돌려준다. .start 를 쓴다.
Map<String, String> _lckEnter(String id) {
  expect(_lckPhase == 'before' || _lckPhase == 'after', isTrue, reason: 'D176_PHASE=$_lckPhase');
  expect(_lckDir.isNotEmpty && Directory(_lckDir).existsSync(), isTrue, reason: 'D176_DIR 없음: $_lckDir');
  expect(vqEnabled && vqPhase == 'du176-$_lckPhase', isTrue, reason: 'DU1_VQ_PHASE=$vqPhase');
  expect((_lckEnv['DU1_VQ_OUT'] ?? '').isNotEmpty && (_lckEnv['DU1_VQ_RUN'] ?? '').isNotEmpty, isTrue,
      reason: 'DU1_VQ_OUT/RUN 필수');
  expect(_lckOrder.contains(id), isTrue);
  expect(File('$_lckDir/STOP').existsSync(), isFalse, reason: '$id 앞 사례 실패(STOP) — 진행하지 않는다');
  expect(File('$_lckDir/$id.start').existsSync(), isFalse, reason: '$id 이미 시작됨 — 재실행 0');
  for (final p in _lckOrder) {
    if (File('$_lckDir/$p.start').existsSync()) {
      expect(File('$_lckDir/$p.ok').existsSync(), isTrue, reason: '$id 앞서 시작한 $p 가 완료되지 않았다 — 첫 실패 중단');
    }
  }
  // 같은 파일 안 순서(QN→QB, UN→UB)
  final k = _lckOrder.indexOf(id);
  if (k.isOdd) {
    expect(File('$_lckDir/${_lckOrder[k - 1]}.ok').existsSync(), isTrue, reason: '$id 앞 배율 사례 미완료');
  }
  final want = <String, String>{};
  for (final kv in (_lckEnv['D176_INPUT_SHA'] ?? '').split(';')) {
    final i = kv.indexOf('=');
    if (i > 0) want[kv.substring(0, i)] = kv.substring(i + 1);
  }
  expect(want.keys.toSet(), _lckInputs.toSet(), reason: 'D176_INPUT_SHA 경로 집합');
  final got = <String, String>{for (final p in _lckInputs) p: _lckSha(p)};
  for (final p in _lckInputs) {
    expect(got[p], want[p], reason: '$id 입력 SHA 불일치 $p');
  }
  if (_lckPhase == 'before') {
    expect(_lckEnv['D176_FROZEN'] ?? '', isEmpty, reason: 'before 에 frozen 을 주지 않는다');
  } else {
    final fz = _lckEnv['D176_FROZEN'] ?? '';
    expect(fz.isNotEmpty && File(fz).existsSync(), isTrue, reason: 'after 는 frozen 필수(탐색으로 바꾸지 않는다)');
    expect(_lckSha(fz), _lckEnv['D176_FROZEN_SHA'], reason: 'frozen SHA 불일치(변조)');
  }
  File('$_lckDir/$id.start').writeAsStringSync('${DateTime.now().toIso8601String()} phase=$_lckPhase');
  return got;
}

Map<String, dynamic>? _lckFrozen(String id) {
  if (_lckPhase != 'after') return null;
  final all = jsonDecode(File(_lckEnv['D176_FROZEN']!).readAsStringSync()) as Map<String, dynamic>;
  final cases = all['cases'] as Map<String, dynamic>;
  expect(cases.keys.toSet(), _lckOrder.toSet(), reason: 'frozen 사례 집합 = 4');
  final m = cases[id] as Map<String, dynamic>;
  expect(m['phase'], 'before', reason: '$id frozen 은 before 기록이어야 한다');
  expect(m['id'], id);
  for (final k in const ['drags', 'geom', 'titles', 'frames', 'counters']) {
    expect(m.containsKey(k), isTrue, reason: '$id frozen 필수 키 $k');
  }
  return m;
}

/// 마지막 문장: 기록과 완료 표식을 쓴다(덮어쓰기 거부).
void _lckFinish(String id, Map<String, Object?> rec) {
  final r = File('$_lckDir/$id.record.json');
  final ok = File('$_lckDir/$id.ok');
  expect(r.existsSync() || ok.existsSync(), isFalse, reason: '$id 기록 덮어쓰기 거부');
  r.writeAsStringSync(jsonEncode(rec));
  ok.writeAsStringSync('ok');
}

Future<Map<String, Object?>> _lckObserve(
  WidgetTester t, {
  required String id,
  required double s,
  required GlobalKey key,
  required Finder list,
  required void Function(String) healthy,
  required void Function(String) state,
  required List<String> overflows,
  required List<String> locked,
  required List<String> others,
  required Map<String, Finder> fixed,
  required Color bg,
  required Map<String, Object?> cond,
  required String Function() counters,
  required Map<String, String> inputs,
  required List<String> frames,
}) async {
  void out(String l) {
    // ignore: avoid_print
    print(l);
  }

  Finder title(String label) => findVisibleText(label);
  // 잠긴 제목 + 보조행(필수/선택 배지 · 보기) = 그 항목 내용 Column
  Finder content(String label) => find.ancestor(of: title(label), matching: find.byType(Column)).first;
  Rect union() => locked.map((l) => t.getRect(content(l))).reduce((a, b) => a.expandToInclude(b));
  bool inside(Rect a, Rect b) =>
      a.left >= b.left - 0.01 && a.top >= b.top - 0.01 && a.right <= b.right + 0.01 && a.bottom <= b.bottom + 0.01;
  ScrollPosition pos() => t.state<ScrollableState>(list).position;

  const start = Offset(160, 320);
  final drags = <double>[];
  Future<void> drag(double dy) async {
    drags.add(dy);
    expect(drags.length <= 6, isTrue, reason: '$id 목록 drag 한도 6 초과');
    expect(dy >= -160 && dy <= -40, isTrue, reason: '$id dy=$dy 범위 밖');
    expect(t.getRect(list).contains(start), isTrue, reason: '$id drag 시작점이 목록 viewport 밖');
    final p0 = pos().pixels;
    out('$id drag 목록 #${drags.length} from $start dy=$dy');
    await t.dragFrom(start, Offset(0, dy));
    healthy('drag');
    for (var i = 0; i < 6; i++) {
      await t.pump(const Duration(milliseconds: 50));
      healthy('drag pump');
    }
    frames.add('drag${drags.length}:6x50');
    expect(pos().pixels > p0, isTrue, reason: '$id drag 뒤 offset 이 움직이지 않았다');
  }

  final frozen = _lckFrozen(id);
  if (_lckPhase == 'after') {
    expect(frozen, isNotNull, reason: '$id after 는 frozen 재생만 한다');
    for (final dy in (frozen!['drags'] as List)) {
      await drag((dy as num).toDouble());
    }
  } else {
    // [repair-TB4] 2.0 진입 직후 잠긴 제목이 지연 목록 캐시 밖이면 element 0(TB3 실측 QB) — 만들어질 때까지
    //   같은 drag 규칙(dy -160 · 한도 6 · drags 기록 → after 가 frozen 으로 그대로 재생)으로 끈다.
    while (locked.any((l) => title(l).evaluate().isEmpty)) {
      await drag(-160);
    }
    for (;;) {
      final vp = t.getRect(list);
      final u = union();
      if (inside(u, vp)) break;
      expect(u.height <= vp.height + 0.01, isTrue, reason: '$id 잠긴 제목·보조행 높이가 viewport 보다 크다');
      expect(u.bottom > vp.bottom + 0.01 && u.top > vp.top, isTrue, reason: '$id 위로 벗어남 — 이 harness 는 위로 끄는 drag 만 쓴다');
      // 필요한 만큼(아래 넘침+8, 위 여유 중 작은 값)만 끈다. 시험 drag 는 touch slop 만큼 덜 움직일 수 있어 |dy| 하한 40.
      var dy = -(u.bottom - vp.bottom + 8 < u.top - vp.top ? u.bottom - vp.bottom + 8 : u.top - vp.top);
      if (dy > -40) dy = -40;
      if (dy < -160) dy = -160;
      await drag(dy);
    }
  }
  expect(inside(union(), t.getRect(list)), isTrue, reason: '$id 잠긴 제목·보조행 완전 노출 실패');
  // [repair-TB4] 제목 원문 · semantics · 비잠김 grey900 단언은 도달 뒤로 옮겼다(내용 무변경).
  for (final l in [...locked, ...others]) {
    expect(title(l), findsOneWidget, reason: '$id 제목 원문 "$l"');
    expect(t.widget<Text>(title(l)).semanticsLabel, l, reason: '$id semantics "$l"');
  }
  for (final l in others) {
    expect(t.renderObject<RenderParagraph>(find.descendant(of: title(l), matching: find.byType(RichText))).text.style?.color, AppColors.grey900,
        reason: '$id 비잠김 제목 grey900 보존 "$l"');
  }

  final pos0 = pos();
  List<double> nums() {
    final p = pos();
    return <double>[
      p.pixels, p.minScrollExtent, p.maxScrollExtent, p.viewportDimension,
      ..._lckRl(t.getRect(list)),
      for (final l in [...locked, ...others]) ...[..._lckRl(t.getRect(title(l))), ..._lckRl(t.getRect(content(l)))],
      for (final f in fixed.values) ..._lckRl(t.getRect(f)),
    ];
  }

  bool flags() {
    final p = pos();
    return identical(p, pos0) && p.hasContentDimensions && !p.outOfRange &&
        !p.isScrollingNotifier.value && !t.binding.hasScheduledFrame;
  }

  double spread(List<List<double>> w) {
    var m = 0.0;
    for (var k = 0; k < w[0].length; k++) {
      var hi = w[0][k];
      var lo = w[0][k];
      for (final v in w) {
        if (v[k] > hi) hi = v[k];
        if (v[k] < lo) lo = v[k];
      }
      if (hi - lo > m) m = hi - lo;
    }
    return m;
  }

  final samples = <List<double>>[];
  final oks = <bool>[];
  var stableAt = 0;
  for (var i = 1; i <= 20; i++) {
    await t.pump(const Duration(milliseconds: 50));
    healthy('정착 표본');
    samples.add(nums());
    oks.add(flags() && samples.last.every((v) => v.isFinite));
    if (samples.length >= 3 && oks.sublist(oks.length - 3).every((ok) => ok) &&
        spread(samples.sublist(samples.length - 3)) <= 0.1) {
      stableAt = i;
      break;
    }
  }
  frames.add('settle:${samples.length}x50');
  expect(stableAt > 0, isTrue, reason: '$id 50ms×20 안에 안정 창(3표본 ≤0.1 · inRange · idle)이 없다');
  await t.pump(const Duration(milliseconds: 50));
  frames.add('hold:1x50');
  healthy('hold');
  final held = nums();
  expect(flags() && spread([samples.last, held]) <= 0.1, isTrue, reason: '$id hold 50ms 유지 실패');
  state('정착 뒤');

  final vpr = t.getRect(list);
  final scr = Rect.fromLTWH(0, 0, 320, 640);
  for (final f in fixed.entries) {
    expect(inside(t.getRect(f.value), scr), isTrue, reason: '$id ${f.key} 화면 안');
    expect(vpr.bottom <= t.getRect(f.value).top + 0.01, isTrue, reason: '$id ${f.key} footer 겹침 0');
  }
  // 차이 mask = 잠긴 제목 Text rect + 1px ∩ 목록 viewport(후속175 §5), 제목별 1개. before 좌표를 production 편집 전에 동결한다.
  final masks = <List<double>>[for (final l in locked) _lckRl(t.getRect(title(l)).inflate(1).intersect(vpr))];
  for (final m in masks) {
    expect(m[2] > m[0] && m[3] > m[1], isTrue, reason: '$id 빈 mask');
  }
  // 제목의 색 외 필드(전후 같아야 한다)와 색(phase 별 기대는 check176 이 판정).
  final titles = <String, Object?>{};
  final colors = <String, String>{};
  for (final l in [...locked, ...others]) {
    final para = t.renderObject<RenderParagraph>(find.descendant(of: title(l), matching: find.byType(RichText)));
    final plain = para.text.toPlainText();
    final tops = para
        .getBoxesForSelection(TextSelection(baseOffset: 0, extentOffset: plain.length))
        .map((b) => b.top.toStringAsFixed(1))
        .toSet();
    final st = para.text.style;
    titles[l] = <String, Object?>{
      'locked': locked.contains(l), 'lines': tops.length, 'fontSize': st?.fontSize, 'fontWeight': '${st?.fontWeight}',
      'fontFamily': st?.fontFamily, 'textScaler': '${para.textScaler}', 'plain': plain,
      'semantics': t.widget<Text>(title(l)).semanticsLabel,
    };
    colors[l] = _lckHex(st?.color);
  }
  final geom = <String, Object?>{'pos': held.sublist(0, 4), 'nums': held, 'masks': masks};
  if (frozen != null) {
    final fz = frozen['geom'] as Map<String, dynamic>;
    void same(String what, List<double> a, List<dynamic> b) {
      expect(a.length, b.length, reason: '$id $what 길이');
      for (var i = 0; i < a.length; i++) {
        expect((a[i] - (b[i] as num).toDouble()).abs() <= 0.01, isTrue, reason: '$id $what[$i] ${a[i]} vs ${b[i]}');
      }
    }

    expect(drags, (frozen['drags'] as List).map((x) => (x as num).toDouble()).toList(), reason: '$id drag 열 동결과 같음');
    same('nums', held, fz['nums'] as List);
    for (var k = 0; k < masks.length; k++) {
      same('mask$k', masks[k], (fz['masks'] as List)[k] as List);
    }
    expect(jsonEncode(titles), jsonEncode(frozen['titles']), reason: '$id 제목 색 외 필드 동결과 같음');
    expect(frames, (frozen['frames'] as List).cast<String>(), reason: '$id frame 기록 동결과 같음');
    expect(counters(), frozen['counters'], reason: '$id 상태·호출 수 동결과 같음');
  }
  final mq = MediaQuery.of(t.element(list));
  final pngPath = '${vqOutDir.path}/${id}_locked.png';
  healthy('캡처 직전');
  await vqCapture(t, key, '${id}_locked', conditions: <String, Object?>{
    ...cond,
    'phase': _lckPhase, 'attempt': _lckDir, 'clock': 'wall ${DateTime.now().toIso8601String()} · 화면 시계 의존 0(terms serverNow 고정)',
    'theme': 'RoleTheme.workerTheme · light', 'viewport': '320x640', 'dpr': 1.0, 'textScaler': s,
    'mq': 'padding=${mq.padding} viewInsets=${mq.viewInsets}', 'keyboard': '닫힘(inset 0)',
    'fonts': 'vqLoadFonts: NotoSansKR Regular+Bold · Roboto=NotoSansKR · MaterialIcons(SDK)',
    'capture': 'RepaintBoundary(MaterialApp) 320x640 전체', 'state': '잠긴 제목·보조행 완전 노출 정착 뒤',
    'bg': _lckHex(bg), 'drags': drags.join(','), 'frozen': frozen != null, 'stableAt': stableAt,
    'offset': held.sublist(0, 4).map((x) => x.toStringAsFixed(4)).join(','), 'frames': frames.join(' '),
    'masks': masks.map((m) => m.map((x) => x.toStringAsFixed(4)).join(',')).join(';'),
    'inputs': inputs.entries.map((e) => '${e.key}=${e.value}').join(';'),
    for (final l in [...locked, ...others]) 'title $l': '${jsonEncode(titles[l])} color=${colors[l]}',
  });
  expect(File(pngPath).existsSync(), isTrue, reason: '$id PNG 없음 $pngPath');
  final afterCap = nums();
  expect(flags() && spread([held, afterCap]) <= 0.1, isTrue, reason: '$id 캡처 전후 유지 실패');
  expect(overflows, isEmpty, reason: '$id overflow 0');
  expect(t.takeException(), isNull);
  String j(List<double> v) => v.map((x) => x.toStringAsFixed(4)).join(',');
  out('LCK|$id|phase=$_lckPhase|scaler=$s|frozen=${frozen != null}|drags=${drags.join(',')}|stableAt=$stableAt'
      '|bg=${_lckHex(bg)}|${counters()}|overflows=${overflows.length}|pos=${j(held.sublist(0, 4))}|viewport=${j(_lckRl(vpr))}'
      '|holdDelta=${spread([samples.last, held])}|captureDelta=${spread([held, afterCap])}');
  return <String, Object?>{
    'id': id, 'phase': _lckPhase, 'scaler': s, 'drags': drags, 'geom': geom, 'titles': titles, 'colors': colors,
    'locked': locked, 'others': others, 'bg': _lckHex(bg), 'frames': frames, 'counters': counters(), 'stableAt': stableAt,
    'png': pngPath, 'sidecar': '${vqOutDir.path}/${id}_locked.run.txt', 'inputs': inputs,
  };
}
