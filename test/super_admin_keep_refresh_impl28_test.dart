// [L48 · impl_28 · 2026-11-27] super_admin 7 화면 — 처리 뒤 다시 읽기 = 목록 유지 + 잠금 · 차례 번호 · 값 미리 표시 0.
//
//   KR-1  (보험료율 화면 · 실제 위젯) 저장 충돌 뒤 다시 읽기: 로딩 화면 0 · 얇은 진행 표시 · 본문 잠금 ·
//         입력칸은 마지막으로 읽은 값으로 즉시 되돌아간다(서버가 거절한 입력값을 보이지 않는다) → 새 값이 앉으면 잠금 해제
//   KR-2  (공용 mixin) 늦게 도착한 옛 응답은 착지하지 않는다 · 첫 읽기와 실패 뒤 다시 시도는 전체 로딩 · 정상 뒤엔 유지
//   KR-3  (공용 본문) 잠금을 켜고 꺼도 같은 AbsorbPointer · 스크롤 위치 그대로 · 잠금 중 탭이 아래에 닿지 않는다
//   KR-4  (소스) 7 화면 모두 같은 꼴 — 차례 번호 · 유지면 전체 로딩 0 · 본문 KeepContentBody · 잠금 대상 버튼
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
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
import 'package:ALfit/utils/keep_content_refresh.dart';
import 'package:ALfit/widgets/common/keep_content_body.dart';
import 'package:ALfit/widgets/common/loading_widget.dart';

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

Finder _field(String label) => find.byKey(ValueKey('rate-$label'));
String _text(WidgetTester t, String label) => t.widget<TextField>(_field(label)).controller!.text;

/// KR-2 — 공용 mixin 을 쓰는 가장 작은 화면(화면들과 같은 꼴의 _load).
class _Harness extends StatefulWidget {
  const _Harness({required this.loads, this.keepAlways = false});
  final List<Completer<String>> loads;

  /// all_businesses 처럼 실패 뒤에도 canKeep 을 true 로 넘기는 화면 — 유지 여부는 mixin 의 마지막 결과(shown)가 정한다.
  final bool keepAlways;
  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> with KeepContentRefreshMixin {
  bool isLoading = true;
  bool failed = false;
  String? value;
  int calls = 0;

  Future<void> load() async {
    final t = beginContentLoad(canKeep: widget.keepAlways || !failed);
    if (!t.keep) setState(() { isLoading = true; failed = false; });
    var shown = false;
    try {
      final v = await widget.loads[calls++].future;
      if (!isCurrentContentLoad(t.gen)) return;
      setState(() => value = v);
      shown = true;
    } catch (_) {
      if (!isCurrentContentLoad(t.gen)) return;
      setState(() => failed = true);
    } finally {
      if (isCurrentContentLoad(t.gen)) {
        setState(() => isLoading = false);
        finishContentLoad(t.gen, shown: shown);
      }
    }
  }

  @override
  Widget build(BuildContext context) => Directionality(
        textDirection: TextDirection.ltr,
        child: isLoading
            ? const Text('LOADING')
            : failed
                ? const Text('FAILED')
                : KeepContentBody(refreshing: refreshingKeep, child: Text('V:$value')),
      );
}

String _code(String p) => File(p)
    .readAsStringSync()
    .replaceAll('\r\n', '\n')
    .split('\n')
    .where((l) => !l.trimLeft().startsWith('//'))
    .join('\n');

String _bodyOf(String src, String sig) {
  final at = src.indexOf(sig);
  expect(at, greaterThan(-1), reason: sig);
  final open = src.indexOf('{', src.indexOf(')', at));
  var d = 0;
  for (var i = open; i < src.length; i++) {
    if (src[i] == '{') d++;
    if (src[i] == '}') {
      d--;
      if (d == 0) return src.substring(at, i + 1);
    }
  }
  return src.substring(at);
}

/// 완료된 Completer 의 이어짐은 다음 microtask 에서 setState 한다 — 프레임 하나를 더 돌려 화면에 반영한다.
Future<void> _two(WidgetTester t) async {
  await t.pump();
  await t.pump();
}

void main() {
  final year = DateTime.now().year;
  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
  });

  testWidgets('KR-1 보험료율 — 저장 충돌 뒤 다시 읽기: 목록 유지 · 잠금 · 입력값은 마지막 읽은 값으로 · 새 값이 앉으면 해제', (t) async {
    final loads = <Completer<Map<int, InsuranceRateModel>>>[Completer(), Completer()];
    var n = 0;
    t.view.physicalSize = const Size(392, 1400);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    await t.pumpWidget(ChangeNotifierProvider<UserProvider>(
      create: (_) => _Super(),
      child: MaterialApp(
        home: InsuranceRateSettingsScreen(
          loadStored: () => loads[n++].future,
          save: (r, e) async => throw InsuranceRatesChangedException(r.year),
        ),
      ),
    ));
    await t.pump();
    expect(find.byType(LoadingWidget), findsOneWidget, reason: '첫 읽기는 예전처럼 로딩 화면');
    loads[0].complete({year: InsuranceRateModel.defaults2026().copyWith(year: year, nationalPensionRate: 5.0)});
    await t.pump();
    await t.pump(const Duration(milliseconds: 100));
    expect(_text(t, '국민연금'), '5.0');

    await t.enterText(_field('국민연금'), '6.0'); // 서버가 아직 받지 않은 값
    final btn = find.textContaining('년 저장');
    await t.ensureVisible(btn);
    await t.tap(btn);
    await t.pump();
    await t.pump(const Duration(milliseconds: 100));
    expect(n, 2, reason: '충돌 → 다시 읽기');
    expect(find.byType(LoadingWidget), findsNothing, reason: '처리 뒤 전체 로딩 화면 0 — 목록 유지');
    expect(find.byKey(KeepContentBody.progressKey), findsOneWidget);
    final absorb = t.widget<AbsorbPointer>(
        find.descendant(of: find.byType(KeepContentBody), matching: find.byType(AbsorbPointer)).first);
    expect(absorb.absorbing, isTrue, reason: '다시 읽는 동안 본문 잠금');
    expect(_text(t, '국민연금'), '5.0', reason: '거절된 입력값(6.0)을 다시 읽는 동안 보이지 않는다');

    loads[1].complete({year: InsuranceRateModel.defaults2026().copyWith(year: year, nationalPensionRate: 7.0)});
    await t.pump();
    await t.pump(const Duration(milliseconds: 100));
    expect(_text(t, '국민연금'), '7.0', reason: '새로 읽은 서버 값');
    expect(find.byKey(KeepContentBody.progressKey), findsNothing);
    expect(t.widget<AbsorbPointer>(
            find.descendant(of: find.byType(KeepContentBody), matching: find.byType(AbsorbPointer)).first).absorbing,
        isFalse);
  });

  testWidgets('KR-2 공용 mixin — 늦은 옛 응답 착지 0 · 첫 읽기/실패 뒤 다시 시도 = 전체 로딩 · 정상 뒤 = 유지', (t) async {
    final loads = List.generate(5, (_) => Completer<String>());
    await t.pumpWidget(_Harness(loads: loads));
    final s = t.state<_HarnessState>(find.byType(_Harness));
    unawaited(s.load());
    await _two(t);
    expect(find.text('LOADING'), findsOneWidget);
    loads[0].complete('A');
    await _two(t);
    expect(find.text('V:A'), findsOneWidget);

    // 다시 읽기 두 번이 겹친다 — 먼저 시작한 것(1)이 늦게 온다.
    unawaited(s.load());
    unawaited(s.load());
    await _two(t);
    expect(find.text('V:A'), findsOneWidget, reason: '유지 — 로딩 화면 0');
    expect(s.refreshingKeep, isTrue);
    loads[2].complete('C');
    await _two(t);
    expect(find.text('V:C'), findsOneWidget);
    expect(s.refreshingKeep, isFalse);
    loads[1].complete('B-old');
    await _two(t);
    expect(find.text('V:C'), findsOneWidget, reason: '늦게 온 옛 응답(B-old)이 새 값(C)을 덮었다');

    // 실패 → 실패 화면 · 그 뒤 다시 시도는 유지가 아니라 전체 로딩
    unawaited(s.load());
    await _two(t);
    loads[3].completeError(StateError('x'));
    await _two(t);
    expect(find.text('FAILED'), findsOneWidget);
    unawaited(s.load());
    await _two(t);
    expect(find.text('LOADING'), findsOneWidget);
    expect(s.refreshingKeep, isFalse);
    loads[4].complete('E');
    await _two(t);
    expect(find.text('V:E'), findsOneWidget);
  });

  testWidgets('KR-2b 공용 mixin — 실패로 끝난 뒤에는 화면이 canKeep 을 true 로 넘겨도 다음 읽기는 전체 로딩', (t) async {
    final loads = List.generate(3, (_) => Completer<String>());
    await t.pumpWidget(_Harness(loads: loads, keepAlways: true));
    final s = t.state<_HarnessState>(find.byType(_Harness));
    unawaited(s.load());
    await _two(t);
    loads[0].complete('A');
    await _two(t);
    expect(find.text('V:A'), findsOneWidget);
    unawaited(s.load());
    await _two(t);
    expect(s.refreshingKeep, isTrue, reason: '정상 뒤 = 유지');
    loads[1].completeError(StateError('x'));
    await _two(t);
    expect(find.text('FAILED'), findsOneWidget);
    unawaited(s.load());
    await _two(t);
    expect(s.refreshingKeep, isFalse, reason: '실패 뒤 다시 읽기를 유지로 하면 실패 화면 위에 진행 표시만 뜬다');
    expect(find.text('LOADING'), findsOneWidget);
    loads[2].complete('C');
    await _two(t);
    expect(find.text('V:C'), findsOneWidget);
  });

  testWidgets('KR-3 공용 본문 — 같은 AbsorbPointer · 스크롤 그대로 · 잠금 중 탭 0', (t) async {
    final ctrl = ScrollController();
    var taps = 0;
    Widget host(bool refreshing) => MaterialApp(
          home: Scaffold(
            body: KeepContentBody(
              refreshing: refreshing,
              child: ListView(controller: ctrl, children: [
                for (var i = 0; i < 60; i++)
                  ListTile(title: Text('행 $i'), onTap: () => taps++),
              ]),
            ),
          ),
        );
    await t.pumpWidget(host(false));
    ctrl.jumpTo(600);
    await t.pump();
    final before = t.element(find.byType(AbsorbPointer).first);
    await t.pumpWidget(host(true));
    expect(identical(t.element(find.byType(AbsorbPointer).first), before), isTrue, reason: '잠글 때 하위 트리를 새로 만들면 스크롤을 잃는다');
    expect(ctrl.offset, 600);
    // 600 만큼 내린 상태 — 화면에 보이는 행을 누른다
    await t.tap(find.text('행 14'), warnIfMissed: false);
    expect(taps, 0, reason: '다시 읽는 동안 목록 버튼에 닿지 않는다');
    await t.pumpWidget(host(false));
    await t.tap(find.text('행 14'));
    expect(taps, 1);
    expect(ctrl.offset, 600);
  });

  test('KR-4 소스 — 7 화면 같은 꼴', () {
    const sa = 'lib/screens/super_admin/';
    final specs = <(String, String, String)>[
      ('all_users_screen.dart', 'Future<void> _loadAllUsers(', 'refreshing: refreshingKeep,'),
      ('all_businesses_screen.dart', 'Future<void> _loadAllBusinesses(', 'refreshing: refreshingKeep,'),
      ('badge_settings_screen.dart', 'Future<void> _loadBadges(', 'refreshing: refreshingKeep,'),
      ('help_faq_management_screen.dart', 'Future<void> _load(', 'refreshing: refreshingKeep,'),
      ('insurance_rate_settings_screen.dart', 'Future<void> _load(', 'refreshing: refreshingKeep,'),
      ('legal_terms_management_screen.dart', 'Future<void> _loadTerms(', 'refreshing: refreshingKeep || _isMutating,'),
      ('minimum_wage_settings_screen.dart', 'Future<void> _load(', 'refreshing: refreshingKeep,'),
    ];
    for (final (f, sig, refreshing) in specs) {
      final c = _code('$sa$f');
      expect(c.contains('KeepContentRefreshMixin'), isTrue, reason: f);
      final b = _bodyOf(c, sig);
      final begin = b.indexOf('final t = beginContentLoad(canKeep:');
      expect(begin, greaterThan(-1), reason: '$f — 차례 번호');
      final firstAwait = b.indexOf('await ');
      expect(begin, lessThan(firstAwait), reason: '$f — 번호는 기다리기 전에');
      expect('isCurrentContentLoad(t.gen)'.allMatches(b).length, greaterThanOrEqualTo(2), reason: '$f — 성공·실패 착지 모두 최신 확인');
      expect(b.contains('finishContentLoad(t.gen, shown:'), isTrue, reason: f);
      expect(RegExp(r'if \(!t\.keep\)|if \(t\.keep\)').hasMatch(b), isTrue, reason: '$f — 유지면 전체 로딩을 켜지 않는다');
      expect(c.replaceAll(RegExp(r'\s+'), ' ').contains('KeepContentBody( $refreshing'), isTrue, reason: '$f — 본문');
    }
    // 처리 잠금이 목록을 로딩 화면으로 바꾸지 않는다(약관 발행·활성 전환)
    final legal = _code('${sa}legal_terms_management_screen.dart');
    expect(_bodyOf(legal, 'Future<void> _toggleActive(').contains('_isLoading = true'), isFalse);
    expect(_bodyOf(legal, 'Future<void> _editItemLocked(').contains('_isLoading = true'), isFalse);
    expect(legal.contains('setState(() => _isMutating = true);'), isTrue);
    // 값 미리 표시 0 — 유지하는 동안 마지막으로 읽은 값으로 되돌린다
    final mw = _bodyOf(_code('${sa}minimum_wage_settings_screen.dart'), 'Future<void> _load(');
    expect(mw.contains('_wages = Map.of(_lastShownWages);'), isTrue);
    expect(mw.contains('_lastShownWages = Map.of(_wages);'), isTrue);
    final ir = _bodyOf(_code('${sa}insurance_rate_settings_screen.dart'), 'Future<void> _load(');
    expect(ir.contains('setState(_updateControllers);'), isTrue);
    // 다시 읽는 동안 본문 밖 행동도 잠근다
    final mwAll = _code('${sa}minimum_wage_settings_screen.dart');
    expect(mwAll.contains('(_isSaving || _loadFailed || refreshingKeep) ? null : _save'), isTrue);
    expect(mwAll.contains('floatingActionButton: _isLoading || refreshingKeep'), isTrue);
    expect(_code('${sa}insurance_rate_settings_screen.dart').contains('_isLoading || refreshingKeep || _loadError != null ? null : _addYear'), isTrue);
  });
}
