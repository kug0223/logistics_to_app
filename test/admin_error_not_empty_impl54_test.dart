// [impl_54 · AUD-4 H2/H5] 관리자 화면 — 조회 실패를 '없음'으로 말하지 않는다.
//   H2  사업장 리뷰 페이지 2종(작성·받은) 실패 → 던진다(화면 _hasError · 더 불러오기 실패 토스트가 받는다)
//   H5  퇴사 요청 조회 실패 → 던진다 · 퇴사 요청 관리 창 = '불러오지 못했어요' + 다시 시도(‘퇴사 요청이 없습니다’ 0)
//   실패 주입은 AUD-4 재현(D:/AlFit-evidence/aud4/zz_aud4_repro_test.dart)과 같은 방식(Functions 채널 unavailable).
// ignore_for_file: depend_on_referenced_packages
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'package:ALfit/screens/business_admin/dialogs/resign_request_management_dialog.dart';
import 'package:ALfit/services/firestore_service.dart';
import 'package:ALfit/services/monthly_review_service.dart';

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

const _cf = 'dev.flutter.pigeon.cloud_functions_platform_interface.CloudFunctionsHostApi.call';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final calls = <String>[];
  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMessageHandler(_cf, (msg) async {
      final args = (const StandardMessageCodec().decodeMessage(msg) as List).first as Map;
      calls.add(args['functionName'] as String);
      return const StandardMessageCodec().encodeMessage(<Object?>['unavailable', '주입 실패', null]);
    });
  });

  test('H2 사업장 리뷰 페이지 2종 — 실패를 빈 페이지로 접지 않고 던진다', () async {
    await expectLater(MonthlyReviewService().getReviewsByBusinessPaged(businessId: 'b1'), throwsA(anything));
    await expectLater(MonthlyReviewService().getPublishedReviewsForBusinessPaged(businessId: 'b1'), throwsA(anything));
    expect(calls, contains('callableGetMonthlyReviewsByBiz'));
    final scr = File('lib/screens/business_admin/admin_review_list_screen.dart').readAsStringSync();
    expect(scr.contains('setState(() { _isLoading = false; _hasError = true; });'), isTrue, reason: '화면 실패 상태가 받는다');
  });

  test('H5 퇴사 요청 조회 — 실패를 [] 로 접지 않고 던진다', () async {
    await expectLater(FirestoreService().getResignRequests('b1'), throwsA(anything));
  });

  for (final (w, s) in [(320.0, 1.0), (320.0, 2.0), (392.0, 2.0)]) {
    testWidgets('H5 ${w.toInt()}·$s 퇴사 요청 관리 창 — 실패 화면 + 다시 시도 · "없습니다" 0', (t) async {
      t.view.physicalSize = Size(w, 900);
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.reset);
      await t.pumpWidget(MaterialApp(
        builder: (ctx, c) => MediaQuery(data: MediaQuery.of(ctx).copyWith(textScaler: TextScaler.linear(s)), child: c!),
        home: Scaffold(body: ResignRequestManagementDialog(businessId: 'b1', onChanged: () {})),
      ));
      for (var i = 0; i < 10; i++) {
        await t.pump(const Duration(milliseconds: 50));
      }
      expect(find.byKey(const ValueKey('resign-load-failed')), findsOneWidget);
      expect(findVisibleText('퇴사 요청을 불러오지 못했어요'), findsOneWidget);
      expect(findVisibleText('다시 시도'), findsOneWidget);
      expect(findVisibleText('퇴사 요청이 없습니다'), findsNothing);
      // 토스트 타이머 정리
      await t.pump(const Duration(seconds: 5));
      final errs = <Object>[];
      Object? e;
      while ((e = t.takeException()) != null) {
        errs.add(e!);
      }
      expect(errs.where((x) => x.toString().contains('overflowed')), isEmpty);
    });
  }
}
