// [AUD-5 ①-1 · impl_61] 알림 탭 이동의 공통 문 — 로그아웃이면 이동 0 · 수신자(recipientUid)가 다르면 이동 0 · 없으면 기존 동작.
// ignore_for_file: depend_on_referenced_packages
import 'dart:convert';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'package:ALfit/services/fcm_service.dart';

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

class _PushCounter extends NavigatorObserver {
  int pushes = 0;
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) => pushes++;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
  });

  group('판정', () {
    test('로그아웃 → 이동 0', () {
      expect(FCMService.payloadNavigable({'type': 'applicationConfirmed', 'applicationId': 'a1'}, null), isFalse);
    });
    test('수신자가 다르면 이동 0 · 같으면 이동', () {
      expect(FCMService.payloadNavigable({'type': 'x', 'recipientUid': 'A'}, 'B'), isFalse);
      expect(FCMService.payloadNavigable({'type': 'x', 'recipientUid': 'B'}, 'B'), isTrue);
    });
    test('수신자 키가 없으면(구서버) 기존 동작', () {
      expect(FCMService.payloadNavigable({'type': 'x'}, 'B'), isTrue);
      expect(FCMService.payloadNavigable({'type': 'x', 'recipientUid': ''}, 'B'), isTrue);
    });
  });

  group('탭 경로(로컬 알림)', () {
    Future<_PushCounter> pump(WidgetTester t) async {
      final key = GlobalKey<NavigatorState>();
      final obs = _PushCounter();
      FCMService().setNavigatorKey(key);
      await t.pumpWidget(MaterialApp(navigatorKey: key, navigatorObservers: [obs], home: const SizedBox()));
      obs.pushes = 0; // 첫 화면 push 는 세지 않는다
      return obs;
    }

    testWidgets('로그아웃 상태에서 트레이 알림을 눌러도 아무 화면도 열지 않는다(알림 목록 폴백 포함)', (t) async {
      final obs = await pump(t);
      FCMService().debugCurrentUserId = null;
      FCMService().debugHandleTapPayload(jsonEncode({'type': 'applicationConfirmed', 'applicationId': 'a1'}));
      FCMService().debugHandleTapPayload(null);
      await t.pump();
      expect(obs.pushes, 0);
    });

    testWidgets('다른 계정(recipientUid ≠ 현재) 알림은 열지 않는다', (t) async {
      final obs = await pump(t);
      FCMService().debugCurrentUserId = 'B';
      FCMService().debugHandleTapPayload(jsonEncode({'type': 'applicationConfirmed', 'applicationId': 'a1', 'recipientUid': 'A'}));
      await t.pump();
      expect(obs.pushes, 0);
      FCMService().debugCurrentUserId = null;
    });
  });

  test('로그아웃(clearToken)이 트레이 로컬 알림을 지운다(원문 보조)', () {
    final c = File('lib/services/fcm_service.dart').readAsStringSync();
    final i = c.indexOf('Future<bool> clearToken(');
    final body = c.substring(i, c.indexOf('Future<bool> removeToken()', i));
    expect(body.contains('_localNotifications.cancelAll()'), isTrue);
  });
}
