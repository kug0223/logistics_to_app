// ignore_for_file: depend_on_referenced_packages
// [.61] SA 배지 관리 — 읽기 실패·기본 배지 삭제 되살아남·삭제 안내·긴 이름.
//
// 근거: 사용자 배지(users.badges)는 callableEvaluateAndUpdateBadges(DEV 00050) 만 쓰고(조건 평가·arrayUnion·회수 없음),
//   이 화면은 배지 **정의**(badges 컬렉션, 규칙 SA 전용)만 다룬다. 쓰기는 한 번도 호출하지 않는다.
import 'support/visible_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';

import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/models/settings/trust_settings_model.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/screens/super_admin/badge_settings_screen.dart';

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

class _Super extends UserProvider {
  @override
  UserModel? get currentUser => UserModel(
        uid: 'sa1', username: 'sa1', name: '운영자', email: 'sa@alfit.local',
        role: UserRole.SUPER_ADMIN, createdAt: DateTime(2026, 1, 1));
  @override
  bool get isSuperAdmin => true;
  @override
  bool get isBusinessAdmin => false;
  @override
  bool get isSubAdmin => false;
  @override
  bool get isAdminMode => true;
  @override
  bool get permissionsLoaded => true;
}

final _defaults = BadgeModel.defaultBadges();
final _custom = BadgeModel(
  id: 'custom_long', name: '야간 물류 상하차 장기 근속 우수 근무자', icon: '🌙', type: BadgeType.experience,
  conditionType: BadgeConditionType.workDays, conditionValue: 5, createdAt: DateTime(2026, 10, 1), order: 99);

Future<void> _pump(WidgetTester tester, Future<List<BadgeModel>> Function() load,
    {Size size = const Size(392, 1600), double textScale = 1.0}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpWidget(ChangeNotifierProvider<UserProvider>(
    create: (_) => _Super(),
    child: MaterialApp(
      builder: (ctx, child) => MediaQuery(
          data: MediaQuery.of(ctx).copyWith(textScaler: TextScaler.linear(textScale)), child: child!),
      home: BadgeSettingsScreen(load: load),
    ),
  ));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 200));
}

Future<void> _openMenuOf(WidgetTester tester, String name) async {
  final tile = find.ancestor(of: findVisibleText(name), matching: find.byType(ListTile)).first;
  await tester.ensureVisible(tile);
  await tester.tap(find.descendant(of: tile, matching: find.byType(PopupMenuButton<String>)));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
  });

  testWidgets('[B61-a] 읽기 실패 — 기본 배지를 현재 설정처럼 보이지 않고 추가·수정을 막는다', (tester) async {
    await _pump(tester, () async => throw Exception('unavailable'));
    expect(findVisibleText('배지 정보를 불러오지 못했습니다'), findsOneWidget);
    expect(findVisibleText(_defaults.first.name), findsNothing);
    // [DU503 · 감사48] FAB 대신 목록 머리 '+ 배지 추가' 글자 행동 — 읽기 실패면 목록이 없으므로 추가 입구도 없다(예전: FAB 비활성).
    expect(findVisibleText('배지 추가'), findsNothing);
    expect(find.byType(FloatingActionButton), findsNothing);
  });

  testWidgets('[B61-b] 기본 배지는 삭제를 열지 않는다 · 사용자 배지는 연다', (tester) async {
    await _pump(tester, () async => [..._defaults, _custom], size: const Size(392, 6000)); // 떠 있는 '배지 추가' 버튼이 메뉴 버튼을 가리지 않게
    await _openMenuOf(tester, _defaults.first.name);
    expect(findVisibleText('기본 배지는 삭제 대신 비활성화를 쓰세요'), findsOneWidget);
    expect(findVisibleText('삭제'), findsNothing);
    await tester.tapAt(const Offset(5, 5));
    await tester.pump(const Duration(milliseconds: 400));
    await _openMenuOf(tester, _custom.name);
    expect(findVisibleText('삭제'), findsOneWidget);
  });

  testWidgets('[B61-c] 사용자 배지 삭제 확인 — 받은 사람 화면에서도 사라진다고 말한다(취소 = 쓰기 0)', (tester) async {
    await _pump(tester, () async => [..._defaults, _custom], size: const Size(392, 6000)); // 떠 있는 '배지 추가' 버튼이 메뉴 버튼을 가리지 않게
    await _openMenuOf(tester, _custom.name);
    await tester.tap(findVisibleText('삭제'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(findVisibleTextContaining('이미 받은 사람의 화면에서도 이 배지가 더 이상 보이지 않습니다'), findsOneWidget);
    expect(findVisibleTextContaining('영향이 없습니다'), findsNothing);
    await tester.tap(findVisibleText('취소'));
    await tester.pump(const Duration(milliseconds: 400));
  });

  testWidgets('[B61-d] 안내 — 직접 부여·회수 기능이 없다는 사실', (tester) async {
    await _pump(tester, () async => _defaults);
    expect(findVisibleTextContaining('특정 사람에게 배지를 직접 주거나 회수하는 기능은 없습니다.'), findsOneWidget);
    expect(findVisibleTextContaining('이미 받은 사람에게는 그대로 보입니다'), findsOneWidget);
  });

  testWidgets('[B61-g] 수정 — 유형·조건은 잠긴다(받은 사람 화면 문구가 조건에서 나온다) · 추가는 열린다', (tester) async {
    await _pump(tester, () async => [..._defaults, _custom], size: const Size(392, 6000));
    await _openMenuOf(tester, _custom.name);
    await tester.tap(findVisibleText('수정'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(findVisibleTextContaining('유형과 조건은 바꿀 수 없습니다'), findsOneWidget);
    final fields = tester.widgetList<TextField>(find.byType(TextField)).toList();
    final value = fields.firstWhere((f) => f.controller?.text == '5');
    expect(value.enabled, isFalse);
    final name = fields.firstWhere((f) => f.controller?.text == _custom.name);
    expect(name.enabled, isNot(false), reason: '이름·아이콘·혜택 설명은 그대로 고칠 수 있다');
    expect(find.byIcon(Icons.expand_more), findsNothing, reason: '잠긴 선택 칸은 열릴 것처럼 보이지 않는다');
    await tester.tap(findVisibleText('취소'));
    await tester.pump(const Duration(milliseconds: 400));
    // [DU503] FAB 대신 목록 머리 '배지 추가' 글자 행동을 누른다(보이게 내린 뒤).
    final add = findVisibleText('배지 추가');
    await tester.ensureVisible(add);
    await tester.pump();
    await tester.tap(add);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(findVisibleTextContaining('유형과 조건은 바꿀 수 없습니다'), findsNothing);
    final added = tester.widgetList<TextField>(find.byType(TextField)).firstWhere((f) => f.controller?.text == '50');
    expect(added.enabled, isNot(false));
    expect(find.byIcon(Icons.expand_more), findsNWidgets(2));
  });

  // 폭(392·320)과 글자 배율이 넘침을 가른다. 높이는 떠 있는 '배지 추가' 버튼이 메뉴를 가리지 않게만 늘린다(창 본문은 스크롤).
  for (final c in const [(Size(392, 2400), 1.0), (Size(320, 2400), 1.3), (Size(392, 2400), 2.0)]) {
    testWidgets('[B61-h] 수정 창 잠금 안내 — 넘침 없음 ${c.$1.width.toInt()}·${c.$2}', (tester) async {
      await _pump(tester, () async => [_custom], size: c.$1, textScale: c.$2);
      await _openMenuOf(tester, _custom.name);
      await tester.tap(findVisibleText('수정'));
      await tester.pump(const Duration(milliseconds: 400));
      expect(findVisibleTextContaining('유형과 조건은 바꿀 수 없습니다'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  for (final c in const [(Size(392, 844), 1.0), (Size(320, 640), 1.3), (Size(392, 844), 2.0)]) {
    testWidgets('[B61-e] 긴 배지 이름 — 말줄임 없이 다 보이고 넘침 없음 ${c.$1.width.toInt()}·${c.$2}', (tester) async {
      await _pump(tester, () async => [_custom], size: c.$1, textScale: c.$2);
      expect(tester.takeException(), isNull);
      final t = tester.widget<Text>(findVisibleText(_custom.name));
      expect(t.overflow, isNot(TextOverflow.ellipsis));
    });
  }
}
