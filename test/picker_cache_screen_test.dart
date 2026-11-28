// [SIM-PICKER-CACHE] 실제 화면 동작으로 picker cache 정리 시점을 본다 — 인감·외국인 신분증.
//
//   · 인감(SettingsScreen 날인 카드 → 도장 이미지 → 등록): 성공·서버 오류·취소 모두
//     이 선택이 만든 UUID 사본·scaled_ 를 남기지 않는다.
//   · 외국인 신분증(ForeignRegisterScreen resume → 갤러리): picker 경로를 업로드까지
//     들고 가므로 OCR 오류·단계 이동·취소 동안 **보존**하고, 같은 사진 재선택에도
//     지금 쓰는 파일을 지우지 않으며, 화면이 닫히면 정리한다.
//   · 대조군: 다른 선택의 UUID 폴더·다른 흐름의 scaled_·사업장 staging·WebView 는 남는다.
//
// 모든 파일은 합성 바이트다(실제 서류 이미지 없음). DEV 호출 없음.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ALfit/models/core/business_member_model.dart';
import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/providers/notification_provider.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/screens/auth/foreign_register_screen.dart';
import 'package:ALfit/screens/common/settings_screen.dart';
import 'package:ALfit/utils/navigation_key.dart';

import 'picker_cache_ownership_test.dart' as own;
import 'support/visible_text.dart'; // [DU1 구현47] keepWords 레이블은 보이는 글자로 찾는다

class _FakeApp extends Fake
    with MockPlatformInterfaceMixin
    implements FirebaseAppPlatform {
  @override
  String get name => defaultFirebaseAppName;
  @override
  FirebaseOptions get options => const FirebaseOptions(
      apiKey: 'k', appId: 'a', messagingSenderId: 's', projectId: 'p',
      storageBucket: 'p.appspot.com');
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

class _Admin extends UserProvider {
  int refreshes = 0;
  @override
  UserModel? get currentUser => UserModel(
        uid: 'u1', username: 'u1', name: '관리자', email: 'u1@alfit.local',
        role: UserRole.BUSINESS_ADMIN, managedBusinessIds: const ['biz1'],
      );
  @override
  bool get isBusinessAdmin => true;
  @override
  String? get effectiveBusinessId => 'biz1';
  @override
  bool get isAdminMode => false;
  @override
  bool get subAdminPermissionsLoaded => true;
  @override
  PermissionCheck checkCurrentBusiness(bool Function(MemberPermissions p) check) =>
      PermissionCheck.allowed;
  @override
  bool can(bool Function(MemberPermissions p) check) => true;
  @override
  Future<void> refreshUserData() async => refreshes++;
}

const _fnChannel =
    'dev.flutter.pigeon.cloud_functions_platform_interface.CloudFunctionsHostApi.call';

/// callable — callableSaveSeal 만 응답을 고른다. 나머지는 not-found.
class _Fn {
  bool sealFails = false;
  int sealCalls = 0;
  Future<ByteData?> handle(ByteData? m) async {
    final args = (const StandardMessageCodec().decodeMessage(m) as List).first as Map;
    final name = args['functionName'] as String;
    if (name == 'callableSaveSeal') {
      sealCalls++;
      if (sealFails) return _err('invalid-argument');
      return const StandardMessageCodec().encodeMessage(<Object?>[<String, Object?>{'success': true}]);
    }
    return _err('not-found');
  }

  ByteData? _err(String c) => const StandardMessageCodec()
      .encodeMessage(<Object?>[c, 'mock $c', <String, Object?>{'code': c}]);
}

Future<void> _real(WidgetTester t, [int rounds = 6]) async {
  for (var i = 0; i < rounds; i++) {
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
    await t.pump();
  }
}

Future<void> _waitFor(WidgetTester t, Finder f, {int max = 200}) async {
  for (var i = 0; i < max && f.evaluate().isEmpty; i++) {
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 25)));
    await t.pump();
  }
}

/// 대조군 — 정리 대상이 아닌 것들.
({Directory otherPick, File otherScaled, File bizStaged}) _controls(own.Harness h) {
  final other = Directory('${h.cache.path}/aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee')..createSync();
  File('${other.path}/99.jpg').writeAsBytesSync([1]);
  final scaled = File('${h.cache.path}/scaled_99.jpg')..writeAsBytesSync([1]);
  Directory('${h.cache.path}/WebView').createSync();
  final st = Directory('${h.support.path}/image_staging')..createSync(recursive: true);
  final biz = File('${st.path}/staged_777.jpg')..writeAsBytesSync([2]);
  return (otherPick: other, otherScaled: scaled, bizStaged: biz);
}

void _expectControls(own.Harness h, ({Directory otherPick, File otherScaled, File bizStaged}) c) {
  expect(c.otherPick.existsSync(), isTrue, reason: '다른 선택의 UUID 폴더');
  expect(c.otherScaled.existsSync(), isTrue, reason: '다른 흐름의 scaled_');
  expect(c.bizStaged.existsSync(), isTrue, reason: '사업장 등록 staging');
  expect(Directory('${h.cache.path}/WebView').existsSync(), isTrue);
}

List<String> _mine(own.Harness h) => h.cacheEntries()
    .where((e) => e != 'WebView' && e != 'aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee' && e != 'scaled_99.jpg')
    .toList();

void main() {
  final h = own.Harness();
  final fn = _Fn();

  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
  });
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    PackageInfo.setMockInitialValues(appName: 'ALfit', packageName: 'com.alfit.app', version: '1.0.21', buildNumber: '25', buildSignature: '');
    await h.setUp();
  });
  tearDown(h.tearDown);

  group('SEAL — 설정 > 날인 카드 > 도장 이미지 등록', () {
    Future<_Admin> pumpSettings(WidgetTester t) async {
      t.view.physicalSize = const Size(400, 2400);
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.reset);
      t.binding.defaultBinaryMessenger.setMockMessageHandler(_fnChannel, fn.handle);
      addTearDown(() => t.binding.defaultBinaryMessenger.setMockMessageHandler(_fnChannel, null));
      // 설정 화면이 시작 시 알림 권한을 읽는다 — 거부(0)로 답해 Firestore 조회(이 셀 범위 밖)를 건너뛴다.
      const perm = MethodChannel('flutter.baseflow.com/permissions/methods');
      t.binding.defaultBinaryMessenger.setMockMethodCallHandler(perm, (c) async => 0);
      addTearDown(() => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(perm, null));
      final p = _Admin();
      await t.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<UserProvider>.value(value: p),
          ChangeNotifierProvider<NotificationProvider>(create: (_) => NotificationProvider()),
        ],
        child: MaterialApp(navigatorKey: navigatorKey, home: const SettingsScreen()),
      ));
      await _real(t, 10);
      return p;
    }

    Future<void> runSeal(WidgetTester t) async {
      // OutlinedButton.icon 은 하위 타입이라 byType 으로 안 잡힌다 — 날인 카드의 버튼 글자로 찾는다.
      final reg = find.ancestor(of: findVisibleText('등록'), matching: find.byWidgetPredicate((w) => w is OutlinedButton));
      await _waitFor(t, reg);
      await t.ensureVisible(reg.first);
      await t.tap(reg.first);
      await _waitFor(t, findVisibleText('갤러리에서 선택'));
      await t.pumpAndSettle();
      await t.tap(findVisibleText('갤러리에서 선택'));
      // 선택 → bytes → 서버 응답 → 토스트까지 실제 시간으로 기다린다(취소면 picker 호출 뒤 끝).
      for (var i = 0; i < 120; i++) {
        await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 25)));
        await t.pump();
        final settled = h.picker.cancel ? i > 20 : (fn.sealCalls > 0 && i > 20);
        if (settled) break;
      }
      await _real(t, 8);
      await t.pump(const Duration(seconds: 6)); // 토스트 타이머(오류 토스트 포함)
    }

    for (final (label, fails) in [('성공', false), ('서버 오류', true)]) {
      testWidgets('SEAL-$label: 이 선택의 UUID 사본·scaled_ 를 남기지 않고, 대조군은 남는다', (t) async {
        fn.sealFails = fails;
        fn.sealCalls = 0;
        final c = _controls(h);
        await pumpSettings(t);
        await runSeal(t);
        expect(fn.sealCalls, 1, reason: '실제 등록 경로를 탔다');
        expect(h.picker.created, isNotEmpty, reason: 'picker 가 cache 에 만들었다');
        expect(_mine(h), isEmpty, reason: '$label 후에도 남지 않는다');
        _expectControls(h, c);
      });
    }

    testWidgets('SEAL-취소: 선택 창 취소 — 서버 호출 없고 남은 것 없음', (t) async {
      fn.sealCalls = 0;
      h.picker.cancel = true;
      final c = _controls(h);
      await pumpSettings(t);
      await runSeal(t);
      expect(fn.sealCalls, 0);
      expect(_mine(h), isEmpty);
      _expectControls(h, c);
    });
  });

  group('FRN — 외국인 신분증(resume) — 업로드까지 보존, 종료 시 정리', () {
    Future<void> pumpForeign(WidgetTester t) async {
      t.view.physicalSize = const Size(400, 2000);
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.reset);
      await t.pumpWidget(MaterialApp(
        navigatorKey: navigatorKey,
        home: const ForeignRegisterScreen(role: UserRole.USER, isResume: true),
      ));
      await _real(t, 6);
    }

    Future<void> pickGallery(WidgetTester t) async {
      final g = findVisibleText('갤러리에서 선택');
      await _waitFor(t, g);
      await t.ensureVisible(g.first);
      await t.tap(g.first);
      await _real(t, 12); // 선택 → OCR(플러그인 없음 → 예외) → 채택
    }

    testWidgets('FRN-1 OCR 오류에도 채택된 파일은 남고(업로드용), 화면이 닫히면 정리된다', (t) async {
      final c = _controls(h);
      await pumpForeign(t);
      await pickGallery(t);
      final held = File('${h.cache.path}/scaled_64.jpg');
      expect(held.existsSync(), isTrue, reason: 'OCR 오류 뒤 확인 단계로 갔고, 업로드까지 이 경로를 쓴다');
      expect(_mine(h).length, 2, reason: 'UUID 사본 + scaled_ — 아직 소유 중');

      await t.pumpWidget(const SizedBox()); // 화면 종료(dispose)
      await _real(t, 4);
      expect(_mine(h), isEmpty, reason: '화면이 닫히면 놓는다');
      _expectControls(h, c);
    });

    testWidgets('FRN-2 같은 사진 재선택 — 앞 선택만 놓고 지금 쓰는 scaled_ 는 지우지 않는다', (t) async {
      await pumpForeign(t);
      await pickGallery(t);
      final firstDirs = h.picker.created.where((p) => !p.endsWith('.jpg')).toList();

      await t.binding.handlePopRoute(); // 확인 → 촬영 단계로
      await _real(t, 4);
      await pickGallery(t); // 같은 MediaStore id → 같은 scaled_64 덮어씀
      final held = File('${h.cache.path}/scaled_64.jpg');
      expect(held.existsSync(), isTrue, reason: '새 선택이 업로드까지 쓸 파일');
      for (final d in firstDirs) {
        expect(Directory(d).existsSync(), isFalse, reason: '앞 선택의 UUID 사본은 놓았다');
      }
      expect(_mine(h).length, 2);

      await t.pumpWidget(const SizedBox());
      await _real(t, 4);
      expect(_mine(h), isEmpty);
    });

    testWidgets('FRN-3 재선택 창 취소 — 들고 있던 파일은 그대로 남는다', (t) async {
      await pumpForeign(t);
      await pickGallery(t);
      await t.binding.handlePopRoute();
      await _real(t, 4);
      h.picker.cancel = true;
      await pickGallery(t);
      expect(File('${h.cache.path}/scaled_64.jpg').existsSync(), isTrue);
      expect(_mine(h).length, 2);
      await t.pumpWidget(const SizedBox());
      await _real(t, 4);
      expect(_mine(h), isEmpty);
    });
  });
}
