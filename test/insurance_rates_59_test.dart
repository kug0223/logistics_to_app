// [.59] SA 보험료율 설정 — 읽기 실패·저장값 없음·앱 계산 상한·저장 직전 대조·연도 목록 큰 글자.
//
// 기기(Pixel 5, 11-02): 저장값이 없는데 내장값을 저장값처럼 보였고, 연도 목록이 '2026/년'으로 갈렸다.
// 서버 확정(callableCalculateAndConfirmWage 00099)은 저장값을 형식·범위 검사 없이 쓴다 — 앱이 저장하는 값의 범위를
//   앱 계산 상한과 맞춘다(서버 후보 INS 는 별도).
import 'dart:io';

import 'support/visible_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';

import 'package:ALfit/models/core/insurance_rate_model.dart';
import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/screens/super_admin/insurance_rate_settings_screen.dart';
import 'package:ALfit/services/insurance_rate_service.dart';

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

// 합성 요율 — 시험용
final _a = InsuranceRateModel.defaults2026().copyWith(nationalPensionRate: 5.0, healthInsuranceRate: 4.0);

class _Calls {
  int loads = 0;
  final saves = <(InsuranceRateModel, InsuranceRateModel?)>[];
}

Future<_Calls> _pump(
  WidgetTester tester, {
  required Future<Map<int, InsuranceRateModel>> Function() load,
  Future<void> Function(InsuranceRateModel, InsuranceRateModel?)? save,
  Size size = const Size(392, 1400),
  double textScale = 1.0,
}) async {
  final calls = _Calls();
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpWidget(ChangeNotifierProvider<UserProvider>(
    create: (_) => _Super(),
    child: MaterialApp(
      builder: (ctx, child) => MediaQuery(
          data: MediaQuery.of(ctx).copyWith(textScaler: TextScaler.linear(textScale)), child: child!),
      home: InsuranceRateSettingsScreen(
        loadStored: () { calls.loads++; return load(); },
        save: (r, e) async { calls.saves.add((r, e)); if (save != null) await save(r, e); },
      ),
    ),
  ));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump(const Duration(milliseconds: 100));
  return calls;
}

Finder _field(String label) => find.byKey(ValueKey('rate-$label'));

Future<void> _tapSave(WidgetTester tester) async {
  final btn = findVisibleTextContaining('년 저장');
  await tester.ensureVisible(btn);
  await tester.tap(btn);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  final year = DateTime.now().year;
  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
  });

  testWidgets('[IR59-a] 읽기 실패 — 내장값을 보이지 않고 편집·저장을 막는다', (tester) async {
    await _pump(tester, load: () async => throw Exception('permission-denied'));
    expect(findVisibleText('보험료율을 불러오지 못했습니다'), findsOneWidget);
    expect(findVisibleTextContaining('년 저장'), findsNothing);
    expect(_field('국민연금'), findsNothing);
    expect(findVisibleText('다시 시도'), findsOneWidget);
  });

  testWidgets('[IR59-b] 저장값 없음 — 내장값임을 알린다 / 저장값 있으면 알리지 않는다', (tester) async {
    await _pump(tester, load: () async => {});
    expect(findVisibleTextContaining('저장된 $year년 요율이 없습니다'), findsOneWidget);
    await _pump(tester, load: () async => {year: _a.copyWith(year: year)});
    expect(findVisibleTextContaining('저장된 $year년 요율이 없습니다'), findsNothing);
    expect((tester.widget<TextField>(_field('국민연금'))).controller!.text, '5.0');
  });

  testWidgets('[IR59-c] 앱 계산 상한을 넘는 값(25%)은 저장하지 않는다', (tester) async {
    final calls = await _pump(tester, load: () async => {});
    await tester.enterText(_field('국민연금'), '25');
    await _tapSave(tester);
    expect(calls.saves, isEmpty);
    await tester.enterText(_field('국민연금'), '20');
    await _tapSave(tester);
    expect(calls.saves.length, 1);
    expect(calls.saves.single.$1.nationalPensionRate, 20);
  });

  testWidgets('[IR59-d] 저장은 화면을 연 시점의 저장값을 기대값으로 보낸다', (tester) async {
    var calls = await _pump(tester, load: () async => {});
    await _tapSave(tester);
    expect(calls.saves.single.$2, isNull); // 없던 연도
    final stored = _a.copyWith(year: year);
    calls = await _pump(tester, load: () async => {year: stored});
    await tester.enterText(_field('건강보험'), '3.0');
    await _tapSave(tester);
    expect(calls.saves.single.$2!.toMap(), stored.toMap());
    expect(calls.saves.single.$1.healthInsuranceRate, 3.0);
  });

  testWidgets('[IR59-e] 그 사이 바뀌었으면 덮지 않고 다시 읽는다', (tester) async {
    final calls = await _pump(tester,
        load: () async => {year: _a.copyWith(year: year)},
        save: (r, e) async => throw InsuranceRatesChangedException(r.year));
    await _tapSave(tester);
    await tester.pump(const Duration(milliseconds: 100));
    expect(calls.saves.length, 1);
    expect(calls.loads, 2);
  });

  for (final c in const [(Size(392, 844), 1.0), (Size(320, 640), 1.3), (Size(392, 844), 2.0)]) {
    testWidgets('[IR59-f] 연도 목록·안내 넘침 없음 ${c.$1.width.toInt()}·${c.$2}', (tester) async {
      await _pump(tester, load: () async => {}, size: c.$1, textScale: c.$2);
      expect(tester.takeException(), isNull);
      // 연도 글자는 한 덩어리(낱말 묶음)다.
      expect(findVisibleText('$year년'), findsOneWidget);
      final t = tester.widget<Text>(findVisibleText('$year년'));
      expect(t.data!.contains('⁠'), isTrue);
      // 한 줄이다 — 칸이 좁으면 낱말 묶음도 강제로 끊긴다(기기 392·1.0 '2026/년').
      final p = tester.renderObject<RenderParagraph>(find.descendant(of: findVisibleText('$year년'), matching: find.byType(RichText)));
      final tops = p.getBoxesForSelection(TextSelection(baseOffset: 0, extentOffset: t.data!.length)).map((b) => b.top.round()).toSet();
      expect(tops.length, 1, reason: '연도 글자가 줄바꿈됐다');
      // 칸 이름은 잘리지 않고 다 보인다(떠 있는 라벨은 한 줄이라 2.0 에서 말줄임됐다).
      for (final l in ['장기요양 (건보료 대비 %)', '일용직 비과세 한도 (원)', '지방소득세 (소득세 대비 %)']) {
        expect(findVisibleText(l), findsOneWidget, reason: '$l 이 칸 위 글자로 없다');
      }
    });
  }

  test('[IR59-g] 로그인 뒤 보험료율을 다시 읽는다(최저시급과 같은 자리) — 소스 계약', () {
    final src = File('lib/providers/user_provider.dart').readAsStringSync();
    final i = src.indexOf('if (loaded != null) unawaited(WageCalculator.loadMinimumWages());');
    final j = src.indexOf('if (loaded != null) unawaited(InsuranceRateService.loadRates());');
    expect(i, greaterThan(0));
    expect(j, greaterThan(i));
  });
}
