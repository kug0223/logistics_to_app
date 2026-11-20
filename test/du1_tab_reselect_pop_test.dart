// ignore_for_file: depend_on_referenced_packages
// [DU1 R8-TAB-RESELECT] 탭 재탭·딥링크 정규화(popTabToRoot)가 화면 PopScope 를 따르는지 — LOCAL 실제 위젯.
//   TR-1 실제 ProfileEditScreen 미변경 → 첫 화면까지 비움
//   TR-2 실제 ProfileEditScreen dirty → 멈추고 확인 창, 계속 편집 → 입력 유지, 다시 재탭 → 나가기 → 첫 화면
//   TR-3 결과 반환 화면(큐와 같은 PopScope 형태: canPop:false + Navigator.pop(context, _hasChanges)) → 부모가 true 를 받는다
//   TR-4 [root, A, dirty] → dirty 에서 멈추고 아래 A 를 강제로 걷어내지 않는다
//   TR-5 두 shell 소스 계약 — 재탭/딥링크에 popUntil 이 남지 않는다
//   저장 중(_isLoading) 보호는 실제 저장(DEV 쓰기)이 필요해 소스(canPop: !_hasChanges && !_isLoading)만 — 미실행.
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';

import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/screens/common/profile_edit_screen.dart';
import 'package:ALfit/utils/tab_navigator_pop.dart';

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

class _Worker extends UserProvider {
  @override
  UserModel? get currentUser => UserModel(
      uid: 'w1', username: 'w1', name: '김근로', email: 'w1@test.local', role: UserRole.USER);
}

class _ResultScreen extends StatefulWidget {
  const _ResultScreen();
  @override
  State<_ResultScreen> createState() => _ResultScreenState();
}

/// support_review_queue_screen.dart:555 / unclosed_action_queue_screen.dart:209 와 같은 형태.
class _ResultScreenState extends State<_ResultScreen> {
  final bool _hasChanges = true;
  @override
  Widget build(BuildContext context) => PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) Navigator.pop(context, _hasChanges);
        },
        child: const Scaffold(body: Text('큐')),
      );
}

final _navKey = GlobalKey<NavigatorState>();
final _results = <Object?>[];

Future<void> _pumpTab(WidgetTester t) async {
  _results.clear();
  t.view.physicalSize = const Size(392, 844);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(ChangeNotifierProvider<UserProvider>(
    create: (_) => _Worker(),
    child: MaterialApp(
      home: Navigator(
        key: _navKey,
        onGenerateRoute: (s) => MaterialPageRoute(settings: s, builder: (_) => const Scaffold(body: Text('탭 첫 화면'))),
      ),
    ),
  ));
}

Future<void> _push(WidgetTester t, Widget w) async {
  _navKey.currentState!.push<Object?>(MaterialPageRoute(builder: (_) => w)).then(_results.add);
  await t.pumpAndSettle();
}

Future<bool> _reselect(WidgetTester t) async {
  final f = popTabToRoot(_navKey.currentState!);
  await t.pumpAndSettle();
  return f;
}

void main() {
  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
  });

  testWidgets('TR-1 미변경 프로필 → 첫 화면까지', (t) async {
    await _pumpTab(t);
    await _push(t, const ProfileEditScreen());
    expect(findVisibleText('프로필 관리'), findsOneWidget);
    expect(await _reselect(t), isTrue);
    expect(find.text('탭 첫 화면'), findsOneWidget);
  });

  testWidgets('TR-2 dirty 프로필 → 확인 창, 계속 편집 유지, 다시 재탭 후 나가기', (t) async {
    await _pumpTab(t);
    await _push(t, const ProfileEditScreen());
    await t.enterText(find.byType(TextField).last, '101호');
    await t.pumpAndSettle();
    expect(await _reselect(t), isFalse, reason: '거절 — 확인에 맡기고 멈춘다');
    expect(findVisibleText('변경 취소'), findsOneWidget);
    await t.tap(find.text('계속 편집'));
    await t.pumpAndSettle();
    expect(findVisibleText('프로필 관리'), findsOneWidget);
    expect(find.text('101호'), findsOneWidget, reason: '입력 유지');
    await _reselect(t);
    await t.tap(find.text('나가기'));
    await t.pumpAndSettle();
    expect(find.text('탭 첫 화면'), findsOneWidget);
  });

  testWidgets('TR-3 결과 반환 화면 → 부모가 true 를 받는다(popUntil 은 null)', (t) async {
    await _pumpTab(t);
    await _push(t, const _ResultScreen());
    expect(await _reselect(t), isTrue);
    expect(find.text('탭 첫 화면'), findsOneWidget);
    expect(_results, [true]);
  });

  testWidgets('TR-4 [첫 화면, A, dirty] → dirty 에서 멈추고 A 는 남는다', (t) async {
    await _pumpTab(t);
    await _push(t, const Scaffold(body: Text('A')));
    await _push(t, const ProfileEditScreen());
    await t.enterText(find.byType(TextField).last, '202호');
    await t.pumpAndSettle();
    expect(await _reselect(t), isFalse);
    await t.tap(find.text('나가기'));
    await t.pumpAndSettle();
    expect(find.text('A'), findsOneWidget, reason: '확인 전에 아래 route 를 강제로 걷어내지 않는다');
    expect(await _reselect(t), isTrue);
    expect(find.text('탭 첫 화면'), findsOneWidget);
  });

  test('TR-5 두 shell 재탭·딥링크에 popUntil 이 남지 않는다', () {
    for (final p in const ['lib/screens/user/user_root_screen.dart', 'lib/screens/business_admin/business_admin_shell.dart']) {
      final src = File(p).readAsLinesSync().where((l) => !l.trimLeft().startsWith('//') && !l.trimLeft().startsWith('///')).join('\n');
      expect(src.contains('popUntil('), isFalse, reason: p);
      expect(src.contains('popTabToRoot('), isTrue, reason: p);
    }
  });
}
