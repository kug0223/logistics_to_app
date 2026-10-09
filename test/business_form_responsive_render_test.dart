// [R7-PREDEVICE-STABILIZATION.1] 사업장 등록·수정 폼 — 반응형 렌더.
//
// ── 왜 필요한가 ─────────────────────────────────────────────────────
//   이 화면은 관리자가 **사업장을 만드는 유일한 입구**이고 3단계 · 3,400줄
//   이다. 그런데 이 Phase 전까지 `pumpWidget` 으로 한 번도 그려 본 적이
//   없었다(`BusinessFormScreen` 을 언급하는 테스트 2개 모두 소스 문자열만
//   검사한다). 즉 좁은 화면·큰 배율에서 무엇이 넘치는지 **아무도 몰랐다.**
//
//   금지된 해법(프로젝트 규약): `FittedBox` · `Transform.scale` ·
//   `maxLines:1`+ellipsis · clip · 고정 높이 봉투 · 폭별 magic number 분기 ·
//   타이포 토큰 축소. 자리가 없으면 **자연스러운 줄바꿈 + 세로 확장**이
//   정답이다.
//
// ── 하네스 ──────────────────────────────────────────────────────────
//   수정 모드(`business:` 전달)로 띄운다. `_loadBusinessData()` 는
//   `widget.business` 만 읽고 Firestore 를 치지 않으므로 실제 화면을 그대로
//   그릴 수 있다. 신규 모드는 `initState` 에서 `UserProvider` 를 읽으므로
//   provider 를 함께 넣는다.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ALfit/models/core/business_model.dart';
import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/providers/notification_provider.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/screens/business_admin/business_form_screen.dart';

class _FakeApp extends Fake
    with MockPlatformInterfaceMixin
    implements FirebaseAppPlatform {
  @override
  String get name => defaultFirebaseAppName;
  // `storageBucket` 을 넣어야 한다 — 이 폼은 `StorageService()` 를 필드로
  // 들고 있어서, 빠지면 렌더 전에
  // `[firebase_storage/no-bucket]` 로 죽는다(넘침과 무관한 하네스 결함).
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
  Future<FirebaseAppPlatform> initializeApp({
    String? name,
    FirebaseOptions? options,
  }) async =>
      _FakeApp();
  @override
  List<FirebaseAppPlatform> get apps => [_FakeApp()];
}

class _AdminProvider extends UserProvider {
  @override
  UserModel? get currentUser => UserModel(
        uid: 'admin1',
        username: 'admin1',
        name: '김의관',
        email: 'admin1@alfit.local',
        role: UserRole.BUSINESS_ADMIN,
        managedBusinessIds: const ['biz1'],
      );

  @override
  bool get isBusinessAdmin => true;

  @override
  bool get isSubAdmin => false;
}

/// 좌표까지 갖춘 사업장 — `_validateStep2` 의 위치 게이트를 통과해야
/// 3단계(근태·급여 기준)까지 그려 볼 수 있다.
BusinessModel _business() => BusinessModel(
      id: 'biz1',
      name: '중앙물류센터 수도권 1센터',
      ownerId: 'admin1',
      // 2단계 폼 검증이 요구하는 값들 — 비면 `_validateStep2` 가 막아
      // 3단계(근태·급여 기준)까지 가 보지 못한다.
      companyName: '주식회사 중앙물류',
      ownerName: '김의관',
      businessNumber: '0000000000',
      address: '경기도 화성시 동탄순환대로 1길 23',
      detailAddress: '3층 물류동 A구역',
      category: '물류',
      subCategory: '창고',
      phone: '031-000-0000',
      latitude: 37.2,
      longitude: 127.07,
      city: '화성시',
      district: '동탄면',
      isApproved: true,
      createdAt: DateTime(2026, 1, 1),
    );

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// 폼을 [size] · [textScale] 로 띄운다. [newMode] 면 등록(신규) 경로다.
///
///   `business: null` 로 구별하지 않는다 — 기본값 합치기(`?? _business()`)
///   때문에 null 을 넘겨도 수정 모드가 되어, 신규 경로를 한 번도 그리지
///   않은 채 통과할 수 있다. 플래그로 분명히 가른다.
Future<void> _pumpForm(
  WidgetTester tester, {
  Size size = const Size(390, 900),
  double textScale = 1.0,
  bool newMode = false,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<UserProvider>(create: (_) => _AdminProvider()),
        ChangeNotifierProvider<NotificationProvider>(
            create: (_) => NotificationProvider()),
      ],
      child: MaterialApp(
        builder: (ctx, child) => MediaQuery(
          data: MediaQuery.of(ctx)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: BusinessFormScreen(business: newMode ? null : _business()),
      ),
    ),
  );
  await _settle(tester);
}

/// '다음' 을 눌러 한 단계 넘긴다. 눌러지지 않으면(검증 실패) false.
Future<bool> _goNext(WidgetTester tester) async {
  final next = find.text('다음');
  if (next.evaluate().isEmpty) return false;
  await tester.ensureVisible(next.first);
  await tester.pump();
  await tester.tap(next.first, warnIfMissed: false);
  await _settle(tester);
  return true;
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
  });

  // ═══════════════════════════════════════════════════════════
  // 하네스 충실도 — 기준 조건에서 0 이어야 아래 표를 믿을 수 있다
  // ═══════════════════════════════════════════════════════════
  group('[R7-PREDEVICE-STABILIZATION.1] 하네스가 실제 화면을 그린다', () {
    testWidgets('BF-R-00 390dp 배율 1.0 에서 폼이 그려지고 넘침이 없다',
        (tester) async {
      await _pumpForm(tester);
      expect(tester.takeException(), isNull);
      // 수정 모드 제목과 단계 라벨이 실제로 있다 — 빈 화면을 통과로 세지 않는다.
      expect(find.text('사업장 수정'), findsWidgets);
      expect(find.text('업종 선택'), findsWidgets);
      expect(find.text('기본 정보'), findsWidgets);
      expect(find.text('상세 정보'), findsWidgets);
    });

    testWidgets('BF-R-01 세 단계 전부에 도달한다', (tester) async {
      await _pumpForm(tester);
      expect(await _goNext(tester), isTrue, reason: '1단계 → 2단계');
      expect(find.text('이전'), findsWidgets, reason: '2단계에 왔다');
      // 사업자등록증 업로드 자리(고정 높이 160 봉투를 고친 지점)가 실제로
      // 그려진다 — 그리지 않은 것을 "넘침 0" 으로 세지 않기 위해 못 박는다.
      expect(find.text('사업자등록증 이미지 업로드'), findsWidgets,
          reason: '2단계에 업로드 자리가 있어야 그 수정이 검증된 것이다');
      expect(await _goNext(tester), isTrue, reason: '2단계 → 3단계');
      expect(find.text('저장하기'), findsWidgets, reason: '3단계(마지막)에 왔다');
      // 3단계에 근태·급여 기준 섹션이 있다.
      expect(find.text('출근 처리 규칙'), findsWidgets);
      expect(find.text('퇴근 처리 규칙'), findsWidgets);
      // 고정 높이 봉투를 고친 나머지 두 지점(추가사진·교통편 '사진 추가'
      // 타일)과 GPS 눈금도 3단계에 실제로 그려진다.
      expect(find.text('사진 추가'), findsWidgets,
          reason: '사진 타일이 그려져야 그 수정이 검증된 것이다');
      expect(find.text('GPS 허용 반경'), findsWidgets);
      expect(find.text('30m'), findsWidgets, reason: 'GPS 눈금 힌트');
      expect(tester.takeException(), isNull);
    });
  });

  // ═══════════════════════════════════════════════════════════
  // 폭 × 배율 × 단계 — 넘침 0
  // ═══════════════════════════════════════════════════════════
  group('[R7-PREDEVICE-STABILIZATION.1] 반응형 — 넘침 0', () {
    for (final w in const [320.0, 360.0, 411.0]) {
      for (final scale in const [1.0, 1.3, 2.0]) {
        testWidgets('BF-UX ${w.toInt()}dp × 배율 $scale — 3단계 전부',
            (tester) async {
          await _pumpForm(tester,
              size: Size(w, 820), textScale: scale);
          expect(tester.takeException(), isNull,
              reason: '${w.toInt()}dp × $scale — 1단계');

          await _goNext(tester);
          expect(tester.takeException(), isNull,
              reason: '${w.toInt()}dp × $scale — 2단계');

          await _goNext(tester);
          expect(tester.takeException(), isNull,
              reason: '${w.toInt()}dp × $scale — 3단계');
        });
      }
    }

    testWidgets('BF-UX-NEW 신규 모드도 좁은 화면 · 큰 배율에서 넘치지 않는다',
        (tester) async {
      // 신규 모드는 `initState` 에서 UserProvider 를 읽는 다른 경로다.
      await _pumpForm(tester,
          size: const Size(320, 820), textScale: 2.0, newMode: true);
      expect(tester.takeException(), isNull);
      expect(find.text('사업장 등록'), findsWidgets,
          reason: '신규 경로가 실제로 그려졌는지 — 제목으로 확인한다');
    });
  });

  // ═══════════════════════════════════════════════════════════
  // 금지된 해법으로 막지 않았다
  // ═══════════════════════════════════════════════════════════
  group('[R7-PREDEVICE-STABILIZATION.1] 자리를 줄여 숨기지 않았다', () {
    final src =
        File('lib/screens/business_admin/business_form_screen.dart')
            .readAsStringSync();

    test('BF-GUARD-01 FittedBox · Transform.scale 로 눌러 담지 않았다', () {
      for (final bad in const ['FittedBox', 'Transform.scale']) {
        expect(src.contains(bad), isFalse,
            reason: '$bad 는 글자를 물리적으로 줄인다 — 접근성 배율을 무력화한다');
      }
    });

    test('BF-GUARD-02 단계 라벨을 잘라내지 않았다', () {
      final i = src.indexOf("const stepLabels = ['업종 선택', '기본 정보', '상세 정보']");
      expect(i, greaterThan(-1), reason: '단계 라벨 선언을 찾지 못했다');
      final block = src.substring(i, i + 2600);
      expect(block.contains('overflow: TextOverflow.ellipsis'), isFalse,
          reason: '라벨을 … 로 자르면 어느 단계인지 알 수 없다');
      expect(block.contains('maxLines: 1'), isFalse,
          reason: '한 줄로 고정하면 큰 배율에서 잘린다 — 줄바꿈이 정답이다');
    });
  });
}
