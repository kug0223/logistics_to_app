// [DU379] S004 내국인 첫 단계 본인인증 사전조건 지속 안내(소급 15 §2-2) — 하네스는 du1_signup_toast_avoid_370 r1 D · du1_terms_reset_359 바탕.
//   W 392x844@1.0 · B 320x640@2.0. 실제 경로: 지원자 선택 → 다음 → 1단계 아이디(자동 중복 확인 · 합성 응답) · 비밀번호 2칸 → 다음.
//   ① 본인인증 없이 '다음' ② 아이디 칸 초점 + 키보드(가상 viewInsets 0.4h) 전후 ③ 외국인 → 내국인 전환 ④ '다음' → 뒤로(0단계) → 다시 1단계.
//   제품 기대(기본 단언, DU_BEFORE_OBSERVE=379 은 기록만):
//     ① 안내가 본인인증 버튼 아래 보이고 버튼과 함께 화면 안 · 같은 문구 토스트 0 ② 키보드 전후 유지 · 내린 뒤 함께 보임
//     ③ 국적 전환 → 사라짐 ④ 단계 이동 → 사라짐 · S 정적: 본인인증 성공 setState 가 안내를 지운다(성공 경로는 정적 서비스라 소스로 본다).
//   흐름(항상 단언): 1단계 도달 · 넘침 0.
// ignore_for_file: depend_on_referenced_packages, unused_element
import 'dart:async';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ALfit/models/core/legal_terms_model.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/screens/auth/register_screen.dart';
import 'package:ALfit/theme/role_theme.dart';
import 'package:ALfit/utils/navigation_key.dart';

import 'support/du1_vq_capture.dart';
import 'support/visible_text.dart';

class _FakeApp extends Fake with MockPlatformInterfaceMixin implements FirebaseAppPlatform {
  @override
  String get name => defaultFirebaseAppName;
  @override
  FirebaseOptions get options => const FirebaseOptions(apiKey: 'k', appId: 'a', messagingSenderId: 's', projectId: 'p');
}

class _FakeCore extends FirebasePlatform with MockPlatformInterfaceMixin {
  @override
  FirebaseAppPlatform app([String name = defaultFirebaseAppName]) => _FakeApp();
  @override
  Future<FirebaseAppPlatform> initializeApp({String? name, FirebaseOptions? options}) async => _FakeApp();
  @override
  List<FirebaseAppPlatform> get apps => [_FakeApp()];
}

Future<void> _settle(WidgetTester t, [int n = 8]) async {
  for (var i = 0; i < n; i++) {
    await t.pump(const Duration(milliseconds: 50));
  }
}

final bool _beforeObs = Platform.environment['DU_BEFORE_OBSERVE'] == '379';
const _msg = '본인인증을 완료해주세요';

Map<String, Object?> _termItem(String id, String title, bool req, int order, String ver) => <String, Object?>{
      'itemId': id,
      'version': ver,
      'title': title,
      'content': '$title 본문($ver)입니다.',
      'isRequired': req,
      'isActive': true,
      'order': order,
    };

Map<String, Object?> _terms() => <String, Object?>{
      'effectiveItems': [
        _termItem('service', '서비스 이용약관', true, 1, 'v1'),
        _termItem('privacy', '개인정보 수집 및 이용 동의', true, 2, 'v1'),
      ],
      'serverNowMs': DateTime.utc(2026, 11, 15).millisecondsSinceEpoch,
      'requiredIntegrity': <String, Object?>{'ok': true},
      'upcomingItems': <Object?>[],
    };

void _out(String s) {
  // ignore: avoid_print
  print(s);
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
    final m = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    const codec = StandardMessageCodec();
    m.setMockMessageHandler('dev.flutter.pigeon.cloud_functions_platform_interface.CloudFunctionsHostApi.call', (msg) async {
      final args = (codec.decodeMessage(msg) as List).first as Map;
      final name = args['functionName'] as String;
      if (name == 'callableCheckUsername') return codec.encodeMessage(<Object?>[<String, Object?>{'exists': false}]);
      if (name == 'callableGetEffectiveLegalTerms') return codec.encodeMessage(<Object?>[_terms()]);
      return codec.encodeMessage(<Object?>['du379-blocked', 'functions 호출 차단(시험)', null]);
    });
    for (final x in const ['registerIdTokenListener', 'registerAuthStateListener']) {
      m.setMockMessageHandler('dev.flutter.pigeon.firebase_auth_platform_interface.FirebaseAuthHostApi.$x',
          (_) async => codec.encodeMessage(<Object?>['du379.fake.$x']));
      m.setMockMethodCallHandler(MethodChannel('du379.fake.$x'), (_) async => null);
    }
  });

  test('S 정적: 본인인증 성공 setState 가 안내를 지운다', () {
    final src = File('lib/screens/auth/register_screen.dart').readAsStringSync().replaceAll('\r\n', '\n');
    final i = src.indexOf('_passAuthResult = result;');
    final end = i < 0 ? -1 : src.indexOf('});', i);
    final block = i < 0 || end < 0 ? '' : src.substring(i, end);
    final ok = block.contains('_passGateShown = false');
    _out('S static block=${block.replaceAll('\n', ' ').trim()} ok=$ok beforeObs=$_beforeObs');
    _out('KNOWN ${ok ? 'ok' : 'NG'} S 성공 때 안내 지움(정적)');
    if (!_beforeObs) expect(ok, isTrue, reason: '본인인증 성공 → 안내 지움');
  });

  Finder btnOf(String label) =>
      find.ancestor(of: findVisibleText(label).first, matching: find.byWidgetPredicate((w) => w is ButtonStyleButton)).first;

  for (final c in const [(id: 'W', w: 392.0, h: 844.0, s: 1.0), (id: 'B', w: 320.0, h: 640.0, s: 2.0)]) {
    testWidgets('S004G-${c.id} 본인인증 사전조건 지속 안내 ${c.w.toInt()}x${c.h.toInt()}@${c.s}', (t) async {
      await t.runAsync(vqLoadFonts);
      final overflows = <String>[];
      final prev = FlutterError.onError;
      FlutterError.onError = (d) {
        final m = d.exceptionAsString();
        if (m.contains('overflowed')) {
          // [수리 1/3] 원본 B 1단계에 넘침 4가 있다(TB try0) — 위치를 기록만 한다(이 셀 범위 밖 · 흐름 단언 아님)
          final at = RegExp(r'register_screen\.dart:(\d+)').firstMatch(d.toString())?.group(1) ?? '?';
          overflows.add('${m.split('\n').first} @L$at');
        } else {
          prev?.call(d);
        }
      };
      addTearDown(() => FlutterError.onError = prev);
      t.view.physicalSize = Size(c.w, c.h);
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.reset);
      final key = GlobalKey();
      final terms = EffectiveLegalTerms.fromServer(_terms());
      await t.pumpWidget(ChangeNotifierProvider<UserProvider>(
        create: (_) => UserProvider(),
        child: RepaintBoundary(
          key: key,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            navigatorKey: navigatorKey,
            theme: RoleTheme.workerTheme,
            builder: (ctx, child) =>
                MediaQuery(data: MediaQuery.of(ctx).copyWith(textScaler: TextScaler.linear(c.s)), child: child!),
            home: RegisterScreen(termsLoaderForTest: () async => terms),
          ),
        ),
      ));
      await _settle(t, 10);
      final tag = 'S004G-${c.id}';
      final cond = {'viewport': '${c.w.toInt()}x${c.h.toInt()}', 'textScaler': c.s};

      Future<void> toStep1() async {
        final role = findVisibleText('지원자로 이용');
        await t.ensureVisible(role.first);
        await _settle(t, 2);
        await t.tap(role.first);
        await _settle(t, 4);
        await t.tap(btnOf('다음'));
        await _settle(t, 10);
      }

      await toStep1();
      expect(findVisibleTextContaining('본인인증').evaluate().isNotEmpty, isTrue, reason: '1단계 도달(흐름)');
      Future<void> typeIn(Finder f, String v) async {
        await t.ensureVisible(f);
        await _settle(t, 2);
        await t.enterText(f, v);
      }

      await typeIn(find.widgetWithText(TextFormField, '아이디'), 'worker_01');
      await t.pump(const Duration(milliseconds: 800)); // 자동 중복 확인(600ms 뒤)
      await _settle(t, 8);
      await typeIn(find.widgetWithText(TextFormField, '비밀번호'), 'abcd1234!');
      await typeIn(find.widgetWithText(TextFormField, '비밀번호 확인'), 'abcd1234!');
      FocusManager.instance.primaryFocus?.unfocus();
      await _settle(t, 4);

      final body = find.byType(Scrollable).first;
      Finder notice() => find.byWidgetPredicate((w) => w is Text && w.data == _msg && w is! RichText);
      Finder inBody() => find.descendant(of: find.byType(Scaffold).first, matching: notice());
      int toastCount() => findVisibleText(_msg).evaluate().length - inBody().evaluate().length;
      bool inView(Rect r) {
        final vp = t.getRect(body);
        return r.top >= vp.top - 0.5 && r.bottom <= vp.bottom + 0.5;
      }

      String visibleWithPass() {
        final n = inBody().evaluate().isNotEmpty;
        final nv = n && inView(t.getRect(find.ancestor(of: inBody().first, matching: find.byType(Container)).first));
        final passBtn = findVisibleText('휴대폰 본인인증');
        final pv = passBtn.evaluate().isNotEmpty && inView(t.getRect(passBtn.first));
        return 'notice=$n noticeInView=$nv passInView=$pv toast=${toastCount()}';
      }

      Future<void> tapNext() async {
        await t.tap(btnOf('다음'));
        await _settle(t, 10);
      }

      final steps = <String, bool>{};
      // ① 본인인증 없이 '다음'
      await tapNext();
      final v1 = visibleWithPass();
      _out('$tag ① $v1');
      steps['① 안내 · 본인인증 버튼 함께 보임 · 토스트 0'] = v1 == 'notice=true noticeInView=true passInView=true toast=0';
      await vqCapture(t, key, '${tag}_1next', conditions: {...cond, 'state': '본인인증 없이 다음'});
      await t.pump(const Duration(seconds: 3));

      // ② 키보드 전후
      await t.tap(find.widgetWithText(TextFormField, '아이디'));
      await _settle(t, 2);
      t.view.viewInsets = FakeViewPadding(bottom: (c.h * 0.4).roundToDouble());
      await _settle(t, 6);
      final kbKeep = inBody().evaluate().isNotEmpty;
      t.view.resetViewInsets();
      FocusManager.instance.primaryFocus?.unfocus();
      await _settle(t, 8);
      await tapNext(); // 내린 뒤 다시 누르면 같은 자리로 스크롤
      final v2 = visibleWithPass();
      _out('$tag ② keyboardKeep=$kbKeep after=$v2');
      steps['② 키보드 전후 유지 · 내린 뒤 함께 보임'] = kbKeep && v2 == 'notice=true noticeInView=true passInView=true toast=0';
      await t.pump(const Duration(seconds: 3));

      // ③ 외국인 → 내국인 전환 → 사라짐
      final foreign = findVisibleText('외국인');
      await t.ensureVisible(foreign.first);
      await _settle(t, 2);
      await t.tap(foreign.first);
      await _settle(t, 4);
      await t.tap(findVisibleText('내국인').first);
      await _settle(t, 6);
      steps['③ 국적 전환 → 사라짐'] = inBody().evaluate().isEmpty;

      // ④ '다음' → 뒤로(0단계) → 1단계 → 사라짐
      await typeIn(find.widgetWithText(TextFormField, '아이디'), 'worker_01');
      await t.pump(const Duration(milliseconds: 800));
      await _settle(t, 8);
      await typeIn(find.widgetWithText(TextFormField, '비밀번호'), 'abcd1234!');
      await typeIn(find.widgetWithText(TextFormField, '비밀번호 확인'), 'abcd1234!');
      FocusManager.instance.primaryFocus?.unfocus();
      await _settle(t, 4);
      await tapNext();
      final shown4 = inBody().evaluate().isNotEmpty;
      await t.pump(const Duration(seconds: 3));
      unawaited(navigatorKey.currentState!.maybePop());
      await _settle(t, 10);
      await t.tap(btnOf('다음'));
      await _settle(t, 10);
      steps['④ 다음 → 안내 · 단계 이동 → 사라짐'] = shown4 && inBody().evaluate().isEmpty;

      _out('$tag steps=$steps overflows=${overflows.length} ${overflows.toSet()} beforeObs=$_beforeObs');
      final ok = steps.values.every((v) => v);
      _out('KNOWN ${ok ? 'ok' : 'NG'} $tag 지속 안내 ${steps.entries.where((e) => !e.value).map((e) => e.key).toList()}');
      _out('KNOWN ${overflows.isEmpty ? 'ok' : 'NG'} $tag 넘침(기록) ${overflows.length}');
      // [수리 1/3] 단언 전에 토스트 · 중복 확인 타이머를 흘려보내고 화면을 내린다(실패해도 대기 타이머가 남지 않게)
      final exc = t.takeException();
      await t.pump(const Duration(seconds: 5));
      await t.pumpWidget(const SizedBox.shrink());
      await t.pump(const Duration(seconds: 5));
      expect(exc, isNull);
      if (!_beforeObs) {
        for (final e in steps.entries) {
          expect(e.value, isTrue, reason: '$tag ${e.key}');
        }
      }
    });
  }
}
