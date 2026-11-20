// [DEVICE-GOLDEN-PATH §7] 못 읽는 인감·서명 이미지를 **Flutter 예외 위젯**으로
// 보여주면 안 된다.
//
// ── 기기에서 본 것 ─────────────────────────────────────────────────────
//   Pixel_5 에뮬레이터, QA 관리자 `관리` 탭의 인감/서명 카드에
//     빨간 X 상자 + `Exception: Invalid image data`
//   가 그대로 보였다. 저장된 base64 는 PNG 머리는 맞지만 IDAT 가 깨진
//   값이었고(테스트 fixture 가 그렇게 만들어졌다), 앱은 그 디코드 실패를
//   사용자에게 **영어 예외 문구**로 전달했다.
//
//   계약 서명란은 같은 상황을 `서명 불러오기 실패 · 다시 시도` 로 말한다.
//   인감/서명 카드도 같은 약속을 지켜야 한다.
import 'dart:convert';
import 'dart:typed_data';

import 'package:ALfit/models/core/business_member_model.dart';
import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/providers/notification_provider.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/screens/common/settings_screen.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 정상 1×1 PNG.
const _kValidPng =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAC'
    'hwGA60e6kgAAAABJRU5ErkJggg==';

/// base64 는 멀쩡한데 **PNG 로는 못 읽는** 값 — 기기 fixture 와 같은 모양.
String _corruptPng() {
  final b = Uint8List.fromList(base64Decode(_kValidPng));
  // IHDR 뒤(=IDAT 구간) 한 바이트를 뒤집는다. 머리는 PNG 그대로다.
  b[40] = b[40] ^ 0xFF;
  b[41] = b[41] ^ 0xFF;
  return base64Encode(b);
}

/// base64 로도 못 읽는 값 — build 중 decode 가 던지던 자리.
const _kNotBase64 = '!!! 이건 base64 가 아니다 !!!';

class _FakeApp extends Fake
    with MockPlatformInterfaceMixin
    implements FirebaseAppPlatform {
  @override
  String get name => defaultFirebaseAppName;
  @override
  FirebaseOptions get options => const FirebaseOptions(
      apiKey: 'k',
      appId: 'a',
      messagingSenderId: 's',
      projectId: 'p',
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

class _P extends UserProvider {
  _P({required this.role, this.seal, this.signature});

  final UserRole role;
  final String? seal;
  final String? signature;

  @override
  UserModel? get currentUser => UserModel(
        uid: 'u1',
        username: 'u1',
        name: 'QA 관리자',
        email: 'u1@alfit.local',
        role: role,
        managedBusinessIds:
            role == UserRole.BUSINESS_ADMIN ? const ['biz1'] : const [],
        sealBase64: seal,
        sealType: 'stamp',
        signatureBase64: signature,
      );

  /// 날인 카드는 선택된 사업장이 있어야 미리보기를 그린다.
  @override
  String? get effectiveBusinessId => 'biz1';

  @override
  PermissionCheck checkCurrentBusiness(
          bool Function(MemberPermissions p) check) =>
      PermissionCheck.allowed;

  @override
  bool can(bool Function(MemberPermissions p) check) => true;
}

Future<void> _pump(WidgetTester t, UserProvider p) async {
  t.view.physicalSize = const Size(393, 1400);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<UserProvider>.value(value: p),
        ChangeNotifierProvider<NotificationProvider>(
            create: (_) => NotificationProvider()),
      ],
      child: const MaterialApp(home: SettingsScreen()),
    ),
  );
  for (var i = 0; i < 20; i++) {
    await t.pump(const Duration(milliseconds: 80));
  }
}

/// 화면에 실제로 그려진 문자열 전부.
List<String> _texts(WidgetTester t) => t
    .widgetList<Text>(find.byType(Text))
    .map((w) => w.data ?? '')
    .where((s) => s.isNotEmpty)
    .toList();

const _kNote = '이미지를 읽지 못했어요';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  setUpAll(() async {
    initializeDateFormatting('ko');
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
  });

  group('인감 카드 (BUSINESS_ADMIN)', () {
    testWidgets('S-1 깨진 PNG — 한국어 안내를 말하고 영어 예외를 노출하지 않는다',
        (t) async {
      await _pump(t, _P(role: UserRole.BUSINESS_ADMIN, seal: _corruptPng()));
      final shown = _texts(t).join('\n');
      expect(shown, contains(_kNote), reason: '못 읽었다는 말을 하지 않았다');
      expect(shown.contains('Invalid image data'), isFalse,
          reason: 'Flutter 내부 예외 문구가 사용자에게 보인다');
      expect(shown.contains('Exception'), isFalse);
      // 카드 자체는 살아 있다 — 다시 등록할 수 있어야 한다.
      expect(find.text('변경'), findsWidgets);
    });

    testWidgets('S-2 base64 가 아예 깨져도 화면을 잃지 않는다', (t) async {
      await _pump(t, _P(role: UserRole.BUSINESS_ADMIN, seal: _kNotBase64));
      expect(t.takeException(), isNull, reason: 'build 중 decode 가 던졌다');
      final shown = _texts(t).join('\n');
      expect(shown.contains(_kNote), isTrue);
      expect(shown.contains('인감/서명'), isTrue, reason: '카드가 사라졌다');
    });

    testWidgets('S-3 정상 PNG 면 안내를 띄우지 않는다', (t) async {
      await _pump(t, _P(role: UserRole.BUSINESS_ADMIN, seal: _kValidPng));
      expect(_texts(t).join('\n').contains(_kNote), isFalse,
          reason: '멀쩡한 이미지에 실패 안내를 붙였다');
      expect(find.byType(Image), findsWidgets);
    });

    testWidgets('S-4 등록된 인감이 없으면 미리보기 자리도 안내도 없다', (t) async {
      await _pump(t, _P(role: UserRole.BUSINESS_ADMIN));
      expect(_texts(t).join('\n').contains(_kNote), isFalse,
          reason: '등록한 적 없는 것과 못 읽는 것은 다르다');
    });
  });

  group('서명 카드 (USER)', () {
    testWidgets('S-5 깨진 서명 base64 — 같은 안내, 같은 침묵', (t) async {
      await _pump(t, _P(role: UserRole.USER, signature: _corruptPng()));
      final shown = _texts(t).join('\n');
      expect(shown.contains(_kNote), isTrue);
      expect(shown.contains('Invalid image data'), isFalse);
    });

    testWidgets('S-6 base64 가 아닌 서명도 화면을 잃지 않는다', (t) async {
      await _pump(t, _P(role: UserRole.USER, signature: _kNotBase64));
      expect(t.takeException(), isNull);
      expect(_texts(t).join('\n').contains(_kNote), isTrue);
    });
  });
}
