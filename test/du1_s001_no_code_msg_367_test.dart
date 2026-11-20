// [DU367] 외국인 휴대폰 확인 no_code 문구 — du1_s001_verify_owner_363_test 하네스 바탕(생성기 work/du367-phone-p2/mk_scr.py).
//   합성 서비스가 확인 결과 (false, no_code) · (false, wrong_code) 를 돌려줄 때 인증번호 칸 아래 문구를 본다.
//   제품 기대(기본 단언, DU_BEFORE_OBSERVE=367 은 기록만): no_code = '인증번호를 다시 발송한 뒤 확인해주세요', wrong_code = '인증번호가 일치하지 않습니다'(그대로).
// ignore_for_file: depend_on_referenced_packages, unused_element
import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/models/core/user_region.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/screens/auth/foreign_register_screen.dart';
import 'package:ALfit/services/foreign_id_ocr_service.dart';
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

const kOcrOk = ForeignIdOcrResult(legalName: 'NGUYEN VAN AN', foreignIdRaw: '9001015123456', visaType: 'E-9',
    stayExpiryDate: '2028-12-31', legalNameFailed: false, foreignIdFailed: false, visaTypeFailed: false, stayExpiryFailed: false);

double _lum(Color c) {
  double ch(double v) => v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * ch(c.r) + 0.7152 * ch(c.g) + 0.0722 * ch(c.b);
}

double _contrast(Color a, Color b) {
  final x = _lum(a), y = _lum(b);
  return (math.max(x, y) + 0.05) / (math.min(x, y) + 0.05);
}

Color _overWhite(Color c) => Color.alphaBlend(c, Colors.white);

Color _bgOf(Element e) {
  Color? found;
  e.visitAncestorElements((a) {
    final w = a.widget;
    Color? c;
    if (w is ButtonStyleButton) {
      c = w.style?.backgroundColor?.resolve(w.enabled ? <WidgetState>{} : {WidgetState.disabled});
      if (c == null && w is ElevatedButton) c = Theme.of(a).colorScheme.primary;
      if (c == null) return true;
    } else if (w is Container && w.decoration is BoxDecoration) {
      c = (w.decoration! as BoxDecoration).color;
    } else if (w is Container && w.color != null) {
      c = w.color;
    } else if (w is DecoratedBox && w.decoration is BoxDecoration) {
      c = (w.decoration as BoxDecoration).color;
    } else if (w is Material && w.type != MaterialType.transparency) {
      c = w.color ?? Theme.of(a).colorScheme.surface;
    } else if (w is ColoredBox) {
      c = w.color;
    }
    if (c == null || c.a == 0) return true;
    found = _overWhite(c);
    return false;
  });
  return found ?? Colors.white;
}

Future<void> _settle(WidgetTester t, [int n = 8]) async {
  for (var i = 0; i < n; i++) {
    await t.pump(const Duration(milliseconds: 50));
  }
}




final bool _beforeObs = Platform.environment['DU_BEFORE_OBSERVE'] == '367';

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

class _CapUser extends UserProvider {
  final calls = <Map<String, Object?>>[];
  @override
  Future<bool> signUp({
    required String username,
    required String password,
    required String name,
    String? phone,
    required UserRole role,
    String? businessId,
    String? gender,
    DateTime? birthDate,
    String? residentNumber,
    String? ci,
    String? foreignIdNumber,
    String accountStatus = 'active',
    String? authPhone,
    String? phoneVerificationLevel,
    String? address,
    String? detailAddress,
    UserRegion? homeRegion,
    String? idCardImageUrl,
    String? bankbookImageUrl,
    String? businessLicenseImageUrl,
    String? businessNumber,
    String? businessName,
    String? ceoName,
    String? bankName,
    String? accountNumber,
  }) async {
    calls.add({'phone': phone, 'authPhone': authPhone, 'level': phoneVerificationLevel});
    return false;
  }
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
      return codec.encodeMessage(<Object?>['du367-blocked', 'functions 호출 차단(시험)', null]);
    });
    for (final x in const ['registerIdTokenListener', 'registerAuthStateListener']) {
      m.setMockMessageHandler('dev.flutter.pigeon.firebase_auth_platform_interface.FirebaseAuthHostApi.$x',
          (_) async => codec.encodeMessage(<Object?>['du367.fake.$x']));
      m.setMockMethodCallHandler(MethodChannel('du367.fake.$x'), (_) async => null);
    }
  });
  tearDown(ForeignRegisterHooks.reset);

  for (final reason in const ['no_code', 'wrong_code']) {
    testWidgets('S001NC-W 확인 결과 $reason 문구', (t) async {
      await t.runAsync(vqLoadFonts);
      final phone = _Phone();
      ForeignRegisterHooks.phoneService = () => phone;
      ForeignRegisterHooks.collectionEnabled = () => false;
      t.view.physicalSize = const Size(392, 844);
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.reset);
      final key = GlobalKey();
      await t.pumpWidget(ChangeNotifierProvider<UserProvider>(
        create: (_) => _CapUser(),
        child: RepaintBoundary(
          key: key,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            navigatorKey: navigatorKey,
            theme: RoleTheme.workerTheme,
            home: const ForeignRegisterScreen(role: UserRole.BUSINESS_ADMIN),
          ),
        ),
      ));
      await _settle(t, 12);
      Finder btnOf(String label) =>
          find.ancestor(of: findVisibleText(label).first, matching: find.byWidgetPredicate((w) => w is ButtonStyleButton)).first;
      Future<void> typeIn(Finder f, String v) async {
        await t.ensureVisible(f);
        await _settle(t, 2);
        await t.enterText(f, v);
      }

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
      await typeIn(find.byType(TextField).first, '01012345678');
      await t.tap(btnOf('인증번호 받기'));
      await _settle(t, 8);
      await t.pump(const Duration(milliseconds: 4500));
      await typeIn(find.byType(TextField).at(1), '111111');
      await _settle(t, 4);
      phone.verifies[0].complete((valid: false, reason: reason));
      await _settle(t, 8);
      final expected = reason == 'no_code' ? '인증번호를 다시 발송한 뒤 확인해주세요' : '인증번호가 일치하지 않습니다';
      final shown = findVisibleText(expected).evaluate().isNotEmpty;
      final codeTop = t.getRect(find.byType(TextField).at(1)).top;
      final under = shown && t.getRect(findVisibleText(expected).first).top > codeTop;
      // ignore: avoid_print
      print('S001NC-W_$reason shown=$shown under=$under beforeObs=$_beforeObs');
      // ignore: avoid_print
      print('KNOWN ${shown && under ? 'ok' : 'NG'} S001NC-W_$reason 문구');
      await vqCapture(t, key, 'S001NC-W_$reason', conditions: {'viewport': '392x844', 'textScaler': 1.0, 'state': '확인 결과 $reason'});
      expect(t.takeException(), isNull);
      if (reason == 'wrong_code') {
        expect(shown && under, isTrue, reason: 'wrong_code 문구 그대로(흐름)');
      } else if (!_beforeObs) {
        expect(shown && under, isTrue, reason: 'no_code 문구');
      }
      await t.pump(const Duration(seconds: 5));
      await t.pumpWidget(const SizedBox.shrink());
      await t.pump(const Duration(seconds: 5));
    });
  }
}
