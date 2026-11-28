// ignore_for_file: depend_on_referenced_packages
// [I9 · impl_18 · 2026-11-26] 늦은 잠금 남은 곳 — 확인 창이 먼저 떠도 터치 차단막은 **다음 프레임**에 덮인다.
//
//   R1 같은 프레임 연타 2회 → 확인 창 1개(서명 삭제 · 실제 화면)
//   R2 창을 닫으면 잠금이 풀려 다시 누를 수 있다(영구 잠금 0)
//   R3 소스 계약 — 다섯 곳 모두 바깥 잠금(ActionGuard.runVoid · ownerKey) 안에서만 본문이 불린다 · 원문 핀 유지
import 'dart:convert';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/providers/notification_provider.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/screens/user/signature_screen.dart';
import 'package:ALfit/utils/action_guard.dart';
import 'support/visible_text.dart'; // [impl_21] TextLayout 문구는 보이는 글자로 찾는다

class _FakeApp extends Fake
    with MockPlatformInterfaceMixin
    implements FirebaseAppPlatform {
  @override
  String get name => defaultFirebaseAppName;
  @override
  FirebaseOptions get options => const FirebaseOptions(
      apiKey: 'k', appId: 'a', messagingSenderId: 's', projectId: 'p');
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

/// 1×1 PNG — 등록된 서명이 있는 상태.
const _png =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==';

class _P extends UserProvider {
  @override
  UserModel? get currentUser => UserModel(
        uid: 'u1',
        username: 'u1',
        name: '김근로',
        email: 'u1@alfit.local',
        role: UserRole.USER,
        accountStatus: 'active',
        signatureBase64: _png,
      );
  @override
  bool get isAdminMode => false;
}

String _code(String p) => File(p)
    .readAsStringSync()
    .split('\n')
    .map((l) {
      final i = l.indexOf('//');
      return i >= 0 ? l.substring(0, i) : l;
    })
    .join('\n');

/// TextButton.icon 은 TextButton 의 하위 형식이다 — 정확한 형식 일치가 아니라 `is` 로 찾는다.
Finder _deleteButton() => find.ancestor(
    of: findVisibleText('삭제'), matching: find.byWidgetPredicate((w) => w is TextButton)).first;

Future<void> _pump(WidgetTester t) async {
  t.view.physicalSize = const Size(390, 1200);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider<UserProvider>(create: (_) => _P()),
      ChangeNotifierProvider<NotificationProvider>(create: (_) => NotificationProvider()),
    ],
    child: const MaterialApp(home: SignatureScreen()),
  ));
  await t.pump(const Duration(milliseconds: 100));
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    ActionGuard.resetForTest();
  });
  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
  });

  testWidgets('R1 같은 프레임 연타 2회 → 확인 창 1개', (t) async {
    await _pump(t);
    final del = _deleteButton();
    expect(del, findsOneWidget);
    // 같은 프레임 — 사이에 프레임 없이 버튼 콜백이 두 번 불린 경우(차단막은 다음 프레임에 덮인다).
    //   시험 환경의 포인터 경로는 두 번째 탭을 늘 전달하지는 않아, 버튼이 받는 콜백을 그대로 두 번 부른다.
    final onPressed = t.widget<ButtonStyleButton>(del).onPressed!;
    onPressed();
    onPressed();
    await t.pump();
    await t.pump(const Duration(milliseconds: 300));
    expect(find.text('서명 삭제'), findsOneWidget, reason: '창이 하나만 떠야 한다');
    expect(ActionGuard.inFlightCount, 1, reason: '두 번째 진입은 잠금에서 돌아간다');
  });

  testWidgets('R2 창을 닫으면 잠금이 풀린다(영구 잠금 0)', (t) async {
    await _pump(t);
    await t.tap(_deleteButton());
    await t.pump();
    await t.pump(const Duration(milliseconds: 300));
    await t.tap(findVisibleText('취소').last);
    await t.pump();
    await t.pump(const Duration(milliseconds: 300));
    expect(ActionGuard.inFlightCount, 0);
    await t.tap(_deleteButton());
    await t.pump();
    await t.pump(const Duration(milliseconds: 300));
    expect(find.text('서명 삭제'), findsOneWidget);
  });

  test('R3 다섯 곳 모두 바깥 잠금 · 원문 핀 유지', () {
    final jp = _code('lib/screens/common/job_posting_screen.dart');
    expect(jp, contains("ActionGuard.ownerKey('jobPosting._isCancellingApplication', this)"));
    expect(jp, contains('() => _cancelApplicationFromDetail());'));
    expect(jp, contains("ActionGuard.ownerKey('jobPosting._isDecliningInvite', this)"));
    expect(jp, contains('() => _declineInviteFromDetail());'));
    expect(jp, contains('Future<void> _declineInviteFromDetail() async {'),
        reason: '수락 확인창 원문 시험이 이 줄을 끝 표지로 쓴다');
    expect(RegExp(r'\? null : _declineInviteFromDetailTap,').allMatches(jp).length, 2);
    final my = _code('lib/screens/user/my_applications_screen.dart');
    expect(my, contains('() => _declineInviteLocked(applicationId));'));
    expect(my, contains('_declineInvite(app.id)'), reason: '호출부 원문 시험');
    final st = _code('lib/screens/common/settings_screen.dart');
    expect(st, contains("ActionGuard.ownerKey('settingsDelete._isLoading', this), () => _doDeleteLocked());"));
    final sg = _code('lib/screens/user/signature_screen.dart');
    expect(sg, contains("ActionGuard.ownerKey('signature._isSaving', this), () => _deleteLocked(context));"));
    // census 넘김 목록에서 지웠다.
    final census = File('test/action_guard_late_lock_census_test.dart').readAsStringSync();
    for (final k in [
      'job_posting_screen.dart:_cancelApplicationFromDetail',
      'job_posting_screen.dart:_declineInviteFromDetail',
      'settings_screen.dart:_doDelete',
      'signature_screen.dart:_delete',
    ]) {
      expect(census.contains("'lib/screens/${k.startsWith('signature') ? 'user' : 'common'}/$k'"), isFalse, reason: k);
    }
    expect(base64Decode(_png).isNotEmpty, isTrue);
  });
}
