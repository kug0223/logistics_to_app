// [impl_10] 세대 가드 재발 방지 + L43(서명 저장 뒤 users 전체 재적재 → 서버 확정 값 로컬 반영).
//
//   GG-1  my_schedule_screen 의 `_monthGeneration++`(세대만 올리는 곳)마다 바로 뒤에 새 월 조회를 시작하거나
//         `_monthLoading = false` 를 직접 내린다 — "세대를 올리고 아무도 로딩을 끄지 않는" 경로를 다시 만들지 않는다
//         (impl_9 §2.2 근본 원인 · 행동 재현은 perf_l5_lazy_tabs_test L5S-1 · L5S-6).
//   L43-1 `UserProvider.applyConfirmedSignature` — 같은 계정만 · 등록/삭제 반영 · 알림 1회 · 전역 로딩 표지 0.
//   L43-2 서명 화면 삭제(서버 성공) → users 전체 재적재(refreshUserData) 0 · 모델에서 서명 사라짐.
//   L43-3 서명 화면 소스 — 등록·삭제 두 경로 모두 서버 성공 뒤 `applyConfirmedSignature` · refreshUserData 호출 0.
// ignore_for_file: depend_on_referenced_packages
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';

import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/models/core/user_region.dart';
import 'package:ALfit/providers/notification_provider.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/screens/user/signature_screen.dart';
import 'package:ALfit/theme/role_theme.dart';
import 'support/visible_text.dart'; // [impl_21] TextLayout 문구는 보이는 글자로 찾는다

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

const _png = 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==';

UserModel _user(String uid, {String? sig}) => UserModel(
      uid: uid, username: uid, name: '김근로', email: '$uid@alfit.local', role: UserRole.USER,
      homeRegion: const UserRegion(province: '서울특별시', city: '강남구'), accountStatus: 'active', signatureBase64: sig);

/// users 전체 재적재를 세는 대역 — 실제 모델 필드(_currentUser)는 debugSetCurrentUser 로 채운다.
class _Spy extends UserProvider {
  int refreshes = 0;
  @override
  Future<void> refreshUserData() async => refreshes++;
  @override
  bool get isSubAdmin => false;
  @override
  bool get isBusinessAdmin => false;
  @override
  bool get isSuperAdmin => false;
  @override
  bool get isAdminMode => false;
  @override
  bool get permissionsLoaded => true;
}

const _callCh = 'dev.flutter.pigeon.cloud_functions_platform_interface.CloudFunctionsHostApi.call';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
  });

  test('GG-1 my_schedule_screen — 세대만 올리는 곳마다 새 조회 시작 또는 로딩 직접 해제(재발 방지)', () {
    final src = File('lib/screens/user/my_schedule_screen.dart').readAsStringSync();
    final sites = RegExp(r'_monthGeneration\+\+;').allMatches(src).toList();
    expect(sites, isNotEmpty);
    final bad = <String>[];
    for (final m in sites) {
      final window = src.substring(m.end, (m.end + 900).clamp(0, src.length));
      // 조건부 조회(`if (…) _loadMonthlyAttendances(`)는 조회하지 않는 갈래에서 로딩을 끌 주인이 없다 — 직접 해제가 있어야 한다.
      final conditionalLoad = RegExp(r'if \([^)]*\)\s*_loadMonthlyAttendances\(').hasMatch(window);
      final ok = window.contains('_monthLoading = false') ||
          (window.contains('_loadMonthlyAttendances(') && !conditionalLoad);
      if (!ok) bad.add('offset ${m.start}: ${src.substring(m.start, (m.start + 120).clamp(0, src.length)).replaceAll('\n', ' ')}');
    }
    // ignore: avoid_print
    print('[GG-1] _monthGeneration++ 위치 ${sites.length} · 위반 ${bad.length}');
    expect(bad, isEmpty, reason: bad.join('\n'));
  });

  group('L43', () {
    test('L43-1 applyConfirmedSignature — 같은 계정만 · 등록/삭제 · 알림 1회 · 로딩 표지 0', () {
      final up = UserProvider();
      up.debugSetCurrentUser(_user('u1'));
      var notes = 0;
      up.addListener(() => notes++);
      up.applyConfirmedSignature(uid: 'u2', signatureBase64: _png);
      expect(up.currentUser!.signatureBase64, isNull, reason: '다른 계정 응답은 반영하지 않는다');
      expect(notes, 0);
      up.applyConfirmedSignature(uid: 'u1', signatureBase64: _png);
      expect(up.currentUser!.signatureBase64, _png);
      expect(notes, 1);
      expect(up.isLoading, isFalse, reason: '전역 로딩 표지를 켜지 않는다');
      up.applyConfirmedSignature(uid: 'u1', signatureBase64: null);
      expect(up.currentUser!.signatureBase64, isNull, reason: '서버가 지운 필드를 지운다');
      expect(notes, 2);
      expect(up.currentUser!.name, '김근로', reason: '다른 필드는 그대로');
    });

    testWidgets('L43-2 서명 삭제(서버 성공) — users 전체 재적재 0 · 모델에서 서명 사라짐 · 서버 호출 1', (t) async {
      final calls = <Map>[];
      final m = t.binding.defaultBinaryMessenger;
      m.setMockMessageHandler(_callCh, (data) async {
        final a = (const StandardMessageCodec().decodeMessage(data) as List).first as Map;
        calls.add(a);
        return const StandardMessageCodec().encodeMessage(<Object?>[
          <String, Object?>{'success': true}
        ]);
      });
      addTearDown(() => m.setMockMessageHandler(_callCh, null));
      final up = _Spy()..debugSetCurrentUser(_user('u1', sig: _png));
      t.view.physicalSize = const Size(390, 900);
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.reset);
      await t.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<UserProvider>.value(value: up),
          ChangeNotifierProvider<NotificationProvider>(create: (_) => NotificationProvider()),
        ],
        child: MaterialApp(
          theme: RoleTheme.workerTheme,
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const [Locale('ko', 'KR')],
          home: const SignatureScreen(),
        ),
      ));
      await t.pump(const Duration(milliseconds: 300));
      await t.tap(find.byIcon(Icons.delete_outline).first); // 화면의 '삭제'(TextButton.icon)
      await t.pump(const Duration(milliseconds: 400));
      // 확인창의 삭제(위험 행동) — 확인창 안의 마지막 '삭제'
      await t.tap(findVisibleText('삭제').last);
      for (var i = 0; i < 10; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
      // ignore: avoid_print
      print('[L43-2] calls=${calls.map((c) => c['functionName']).toList()} refreshes=${up.refreshes} sig=${up.currentUser?.signatureBase64}');
      expect(calls.where((c) => c['functionName'] == 'callableSaveUserSignature').length, 1);
      expect(up.refreshes, 0, reason: '서명 하나 지우는 데 users 전체를 다시 적재하지 않는다');
      expect(up.currentUser?.signatureBase64, isNull, reason: '서버가 지운 서명을 화면 모델에서도 지운다');
      t.takeException();
    });

    test('L43-3 서명 화면 소스 — 등록·삭제 모두 서버 성공 뒤 applyConfirmedSignature · refreshUserData 0', () {
      final src = File('lib/screens/user/signature_screen.dart').readAsStringSync();
      expect(src.contains('refreshUserData('), isFalse);
      expect(src.contains('applyConfirmedSignature(uid: uid, signatureBase64: b64)'), isTrue, reason: '등록');
      expect(src.contains('applyConfirmedSignature(uid: uid, signatureBase64: null)'), isTrue, reason: '삭제');
    });
  });
}
