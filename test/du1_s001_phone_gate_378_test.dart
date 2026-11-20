// [DU378] S001 휴대폰 단계 사전조건 지속 안내(소급 15 후보 (b)) — 하네스는 du1_signup_toast_avoid_370(r2) 바탕.
//   W 392x844@1.0 · B 320x640@2.0. 휴대폰 단계 실제 경로(합성 서비스는 발송 · 확인 결과만 대신한다).
//   ① 인증 없이 '다음' ② 번호 칸 초점 + 키보드(가상 viewInsets 0.4h) 전후 ③ 번호 편집 ④ '다음' → 새 발송
//   ⑤ 발송 뒤 맨 위로 스크롤 → '다음' ⑥ 인증 성공 → '다음' → 스캔 단계.
//   제품 기대(기본 단언, DU_BEFORE_OBSERVE=378 은 기록만):
//     ①⑤ 안내가 본문에 보이고 바로 위 행동('인증번호 받기' · '확인')과 함께 화면 안 · 같은 문구 토스트 0
//     ② 키보드 전후 안내 유지 · 내린 뒤 함께 보임 ③④⑥ 편집 · 새 발송 · 성공 때 안내 사라짐.
//   흐름(항상 단언): 휴대폰 단계 도달 · 발송 1 · 인증 성공 뒤 스캔 단계 · 넘침 0.
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

import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/screens/auth/foreign_register_screen.dart';
import 'package:ALfit/services/phone_verification_service.dart';
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

final bool _beforeObs = Platform.environment['DU_BEFORE_OBSERVE'] == '378';
const _msg = '휴대폰 번호 인증을 완료해주세요';

class _Phone implements PhoneVerificationService {
  final sends = <String>[];
  final verifies = <Completer<({bool valid, String? reason})>>[];
  @override
  Future<void> sendCode(String phone) async {
    sends.add(phone);
  }

  @override
  Future<({bool valid, String? reason})> verifyCode(String phone, String code) {
    final c = Completer<({bool valid, String? reason})>();
    verifies.add(c);
    return c.future;
  }
}

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
      return codec.encodeMessage(<Object?>['du378-blocked', 'functions 호출 차단(시험)', null]);
    });
    for (final x in const ['registerIdTokenListener', 'registerAuthStateListener']) {
      m.setMockMessageHandler('dev.flutter.pigeon.firebase_auth_platform_interface.FirebaseAuthHostApi.$x',
          (_) async => codec.encodeMessage(<Object?>['du378.fake.$x']));
      m.setMockMethodCallHandler(MethodChannel('du378.fake.$x'), (_) async => null);
    }
  });
  tearDown(ForeignRegisterHooks.reset);

  Finder btnOf(String label) =>
      find.ancestor(of: findVisibleText(label).first, matching: find.byWidgetPredicate((w) => w is ButtonStyleButton)).first;

  for (final c in const [(id: 'W', w: 392.0, h: 844.0, s: 1.0), (id: 'B', w: 320.0, h: 640.0, s: 2.0)]) {
    testWidgets('S001G-${c.id} 휴대폰 사전조건 지속 안내 ${c.w.toInt()}x${c.h.toInt()}@${c.s}', (t) async {
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
      final phone = _Phone();
      ForeignRegisterHooks.phoneService = () => phone;
      ForeignRegisterHooks.collectionEnabled = () => false;
      ForeignRegisterHooks.currentUid = () => 'u-local-fr-378';
      ForeignRegisterHooks.readUser = (_) async => <String, dynamic>{};
      t.view.physicalSize = Size(c.w, c.h);
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.reset);
      final key = GlobalKey();
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
            home: const ForeignRegisterScreen(role: UserRole.BUSINESS_ADMIN),
          ),
        ),
      ));
      await _settle(t, 12);
      final tag = 'S001G-${c.id}';
      final cond = {'viewport': '${c.w.toInt()}x${c.h.toInt()}', 'textScaler': c.s};
      Future<void> typeIn(Finder f, String v) async {
        await t.ensureVisible(f);
        await _settle(t, 2);
        await t.enterText(f, v);
      }

      // 휴대폰 단계로
      final f0 = find.byType(TextFormField);
      await typeIn(f0.at(0), 'worker_01');
      await t.ensureVisible(findVisibleText('아이디 중복 확인'));
      await t.tap(findVisibleText('아이디 중복 확인'));
      await _settle(t, 8);
      await typeIn(f0.at(1), 'abcd1234!');
      await typeIn(f0.at(2), 'abcd1234!');
      FocusManager.instance.primaryFocus?.unfocus();
      await _settle(t, 2);
      await t.tap(btnOf('다음'));
      await _settle(t, 8);
      expect(findVisibleText('인증번호 받기'), findsWidgets, reason: '휴대폰 단계 도달(흐름)');
      await t.pump(const Duration(milliseconds: 4500));

      final body = find.byType(SingleChildScrollView).first;
      Finder notice() => find.descendant(of: body, matching: findVisibleText(_msg));
      int toastCount() => findVisibleText(_msg).evaluate().length - notice().evaluate().length;
      bool inView(Rect r) {
        final vp = t.getRect(body);
        return r.top >= vp.top - 0.5 && r.bottom <= vp.bottom + 0.5;
      }

      String visibleWith(String action) {
        final n = notice().evaluate().isNotEmpty;
        final nv = n && inView(t.getRect(find.ancestor(of: notice().first, matching: find.byType(Container)).first));
        final av = findVisibleText(action).evaluate().isNotEmpty && inView(t.getRect(btnOf(action)));
        return 'notice=$n noticeInView=$nv actionInView=$av toast=${toastCount()}';
      }

      final steps = <String, bool>{};
      Future<void> tapNext() async {
        await t.tap(btnOf('다음'));
        await _settle(t, 10); // 안내 · 끝 정렬 스크롤(200ms)
      }

      // ① 인증 없이 '다음'
      FocusManager.instance.primaryFocus?.unfocus();
      await _settle(t, 2);
      await tapNext();
      final v1 = visibleWith('인증번호 받기');
      _out('$tag ① $v1');
      steps['① 안내 · 인증번호 받기 함께 보임 · 토스트 0'] = v1 == 'notice=true noticeInView=true actionInView=true toast=0';
      await vqCapture(t, key, '${tag}_1next', conditions: {...cond, 'state': '인증 없이 다음'});
      await t.pump(const Duration(seconds: 3));

      // ② 키보드 전후
      await t.tap(find.byType(TextField).first);
      await _settle(t, 2);
      t.view.viewInsets = FakeViewPadding(bottom: (c.h * 0.4).roundToDouble());
      await _settle(t, 6);
      final kbKeep = notice().evaluate().isNotEmpty;
      await vqCapture(t, key, '${tag}_2keyboard', conditions: {...cond, 'state': '번호 칸 초점 + 키보드'});
      t.view.resetViewInsets();
      FocusManager.instance.primaryFocus?.unfocus();
      await _settle(t, 8);
      final v2 = visibleWith('인증번호 받기');
      _out('$tag ② keyboardKeep=$kbKeep after=$v2');
      steps['② 키보드 전후 유지 · 내린 뒤 함께 보임'] = kbKeep && v2 == 'notice=true noticeInView=true actionInView=true toast=0';

      // ③ 번호 편집 → 사라짐
      await typeIn(find.byType(TextField).first, '010');
      await _settle(t, 4);
      steps['③ 번호 편집 → 사라짐'] = notice().evaluate().isEmpty;
      FocusManager.instance.primaryFocus?.unfocus();
      await _settle(t, 2);

      // ④ '다음' → 안내, 새 발송 → 사라짐
      await tapNext();
      final shown4 = notice().evaluate().isNotEmpty;
      await t.pump(const Duration(seconds: 3));
      await typeIn(find.byType(TextField).first, '01012345678');
      FocusManager.instance.primaryFocus?.unfocus();
      await _settle(t, 2);
      await t.tap(btnOf('인증번호 받기'));
      await _settle(t, 8);
      expect(phone.sends, hasLength(1), reason: '발송 1회(흐름)');
      steps['④ 다음 → 안내 · 새 발송 → 사라짐'] = shown4 && notice().evaluate().isEmpty;
      await t.pump(const Duration(milliseconds: 4500));

      // ⑤ 발송 뒤 맨 위로 스크롤 → '다음'
      FocusManager.instance.primaryFocus?.unfocus();
      await _settle(t, 2);
      await t.drag(body, const Offset(0, 2000));
      await _settle(t, 6);
      await tapNext();
      final v5 = visibleWith('확인');
      _out('$tag ⑤ $v5');
      steps['⑤ 발송 뒤 안내 · 확인 함께 보임 · 토스트 0'] = v5 == 'notice=true noticeInView=true actionInView=true toast=0';
      await vqCapture(t, key, '${tag}_5afterSend', conditions: {...cond, 'state': '발송 뒤 인증 없이 다음'});
      await t.pump(const Duration(seconds: 3));

      // ⑥ 인증 성공 → 사라짐 → 다음 → 스캔 단계
      await typeIn(find.byType(TextField).at(1), '111111');
      await _settle(t, 4);
      expect(phone.verifies, isNotEmpty, reason: '확인 요청(흐름)');
      phone.verifies.last.complete((valid: true, reason: null));
      await _settle(t, 8);
      steps['⑥ 인증 성공 → 사라짐'] = notice().evaluate().isEmpty;
      await t.pump(const Duration(seconds: 3));
      FocusManager.instance.primaryFocus?.unfocus();
      await _settle(t, 2);
      await t.tap(btnOf('다음'));
      await _settle(t, 10);
      expect(findVisibleText('인증번호 받기'), findsNothing, reason: '스캔 단계로 이동(흐름)');

      _out('$tag steps=$steps overflows=${overflows.length} beforeObs=$_beforeObs');
      final ok = steps.values.every((v) => v);
      _out('KNOWN ${ok ? 'ok' : 'NG'} $tag 지속 안내 ${steps.entries.where((e) => !e.value).map((e) => e.key).toList()}');
      expect(t.takeException(), isNull);
      expect(overflows, isEmpty, reason: '$tag 넘침(흐름)');
      if (!_beforeObs) {
        for (final e in steps.entries) {
          expect(e.value, isTrue, reason: '$tag ${e.key}');
        }
      }
      await t.pump(const Duration(seconds: 5));
      await t.pumpWidget(const SizedBox.shrink());
      await t.pump(const Duration(seconds: 5));
    });
  }
}
