// [PERF impl_24 · 2026-11-27] impl_22 에서 찾은 같은 꼴 결함 + L49 남은 부분.
//
//   RV  기기 토큰 폐기(DeviceTokenRevoker._run) — 동기로 던진 폐기가 끝난 future 로 남아 isInFlight 가 굳던 결함
//   RQ  급여 지급 현황 변경요청 탭 — 처리 뒤 재조회 중 잠금 · 처리 전에 출발한 조회가 앉아도 한 번 더 읽음 ·
//       조회 실패를 '요청 없음'으로 그리지 않음(서비스가 삼키던 결함)
// ignore_for_file: depend_on_referenced_packages
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';

import 'package:ALfit/models/core/business_member_model.dart' show MemberPermissions;
import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/providers/notification_provider.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/screens/business_admin/payroll/payroll_payment_dashboard_screen.dart';
import 'package:ALfit/services/fcm_token_revoker.dart';

import 'support/visible_text.dart';

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

const _fnCh =
    'dev.flutter.pigeon.cloud_functions_platform_interface.CloudFunctionsHostApi.call';
const _biz = 'BIZ';

class _AdminP extends UserProvider {
  @override
  UserModel? get currentUser => UserModel(
      uid: 'OWNER', username: 'owner', name: '관리자',
      email: 'owner@test.local', role: UserRole.BUSINESS_ADMIN);
  @override
  bool get isBusinessAdmin => true;
  @override
  bool get isSubAdmin => false;
  @override
  bool can(bool Function(MemberPermissions p) check) => true;
  @override
  bool canForBusiness(String businessId, bool Function(MemberPermissions p) check) => true;
  @override
  PermissionCheck checkForBusiness(
          String businessId, bool Function(MemberPermissions p) check) =>
      PermissionCheck.allowed;
}

Map<String, Object?> _ts(DateTime d) =>
    {'_seconds': d.millisecondsSinceEpoch ~/ 1000, '_nanoseconds': 0};

/// 서버: 요청 목록은 **도착 시각**의 상태로 만들고 [listDelay] 뒤에 답한다.
class _Srv {
  final pending = <String>{'cr1', 'cr2'};
  int listDelay = 200;
  bool listFails = false;
  final calls = <String>[];

  Map<String, Object?> _cr(String id) => {
        'id': id, 'applicationId': 'app-$id', 'businessId': _biz, 'businessName': 'QA',
        'workerId': 'w-$id', 'workerName': '근로$id',
        'currentPayScheduleType': 'daily', 'requestedPayScheduleType': 'weekly',
        'effectiveFrom': '2026-11-01', 'status': 'pending',
        'createdAt': _ts(DateTime(2026, 10, 1)),
      };

  Future<ByteData?> handle(ByteData? data) async {
    final args = (const StandardMessageCodec().decodeMessage(data) as List).first as Map;
    final fn = args['functionName'] as String;
    final p = Map<Object?, Object?>.from(args['parameters'] as Map? ?? const {});
    calls.add(fn);
    Object? body;
    switch (fn) {
      case 'callableGetPaymentChangeRequests':
        final snapshot = [for (final id in pending.toList()..sort()) _cr(id)]; // 도착 시각의 상태
        final fail = listFails;
        await Future<void>.delayed(Duration(milliseconds: listDelay));
        if (fail) {
          return const StandardMessageCodec().encodeMessage(<Object?>['unavailable', 'mock', null]);
        }
        body = {'items': snapshot};
      case 'callableApprovePaymentChangeRequest':
        await Future<void>.delayed(const Duration(milliseconds: 50));
        pending.remove(p['requestId']);
        body = {'success': true};
      case 'callableGetAdminAttendances':
        await Future<void>.delayed(const Duration(milliseconds: 50));
        body = {'items': <Object?>[], 'limitReached': false};
      default:
        await Future<void>.delayed(const Duration(milliseconds: 50));
        body = {'requests': <Object?>[], 'items': <Object?>[], 'users': <String, Object?>{}};
    }
    return const StandardMessageCodec().encodeMessage(<Object?>[body]);
  }

  int listCalls() => calls.where((c) => c == 'callableGetPaymentChangeRequests').length;
}

Future<void> _advance(WidgetTester t, int ms) async {
  for (var e = 0; e < ms; e += 10) {
    await t.pump(const Duration(milliseconds: 10));
  }
}

Future<void> _mount(WidgetTester t, _Srv s) async {
  t.view.physicalSize = const Size(1080, 3000);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  t.binding.defaultBinaryMessenger.setMockMessageHandler(_fnCh, s.handle);
  addTearDown(() => t.binding.defaultBinaryMessenger.setMockMessageHandler(_fnCh, null));
  await t.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider<UserProvider>(create: (_) => _AdminP()),
      ChangeNotifierProvider<NotificationProvider>(create: (_) => NotificationProvider()),
    ],
    child: const MaterialApp(
      home: PayrollPaymentDashboardScreen(
          businessId: _biz, businessName: 'QA', year: 2026, month: 10),
    ),
  ));
  await _advance(t, 1500);
  await t.tap(find.descendant(of: find.byType(TabBar), matching: findVisibleText('변경요청')));
  await _advance(t, 500);
}

Finder _approveOf(String worker) => find.descendant(
    of: find.ancestor(
        of: findVisibleTextContaining('$worker · 지급방식 변경'),
        matching: find.byWidgetPredicate((w) => w.runtimeType.toString() == '_RequestCard')),
    matching: find.text('승인'));

Future<void> _approve(WidgetTester t, String worker) async {
  await t.tap(_approveOf(worker));
  await _advance(t, 300);
  await t.tap(find.descendant(of: find.byType(Dialog), matching: find.text('승인')).last);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
  });

  group('RV 기기 토큰 폐기(Q31 같은 꼴)', () {
    test('RV1 폐기가 동기로 던져도 진행 중으로 굳지 않는다 — 다음 settle 이 다시 폐기한다', () async {
      var deletes = 0;
      var pendingMark = false;
      var throwSync = true;
      final r = DeviceTokenRevoker(
        deleteToken: () {
          deletes++;
          if (throwSync) throw StateError('messaging 준비 전'); // 동기 throw
          return Future<void>.value();
        },
        readPending: () async => pendingMark,
        writePending: (v) async => pendingMark = v,
      );
      expect(await r.revoke(timeout: const Duration(milliseconds: 100)), isFalse);
      expect(r.isInFlight, isFalse, reason: '끝난(실패한) 폐기가 진행 중으로 남았다');
      expect(pendingMark, isTrue, reason: '표식은 남아 다음 로그인이 이어 받는다');
      throwSync = false;
      expect(await r.settle(timeout: const Duration(milliseconds: 100)), isTrue,
          reason: '같은 실패 future 만 돌려받아 다시 폐기하지 않았다');
      expect(deletes, 2);
      expect(pendingMark, isFalse);
    });

    test('RV2 비동기 실패도 같다 — 끝나면 진행 중 아님 · 다음 시도는 새 폐기', () async {
      var deletes = 0;
      var fail = true;
      final r = DeviceTokenRevoker(
        deleteToken: () async {
          deletes++;
          if (fail) throw StateError('offline');
        },
        readPending: () async => true,
        writePending: (v) async {},
      );
      expect(await r.revoke(timeout: const Duration(milliseconds: 100)), isFalse);
      expect(r.isInFlight, isFalse);
      fail = false;
      expect(await r.settle(timeout: const Duration(milliseconds: 100)), isTrue);
      expect(deletes, 2);
    });
  });

  group('RQ 변경요청 탭(L49 남음)', () {
    testWidgets('RQ1 승인 뒤 재조회 중 — 목록 유지 · 진행 표시 · 다른 요청 승인 잠금 → 새 목록이 앉으면 풀림', (t) async {
      final s = _Srv();
      await _mount(t, s);
      expect(_approveOf('근로cr1'), findsOneWidget);
      expect(_approveOf('근로cr2'), findsOneWidget);
      s.listDelay = 1500;
      await _approve(t, '근로cr1');
      await _advance(t, 300); // 승인 호출 끝 → 처리 뒤 재조회 출발
      expect(find.byKey(const ValueKey('payroll-refresh-after-mutation')), findsOneWidget);
      expect(findVisibleTextContaining('근로cr2 · 지급방식 변경'), findsOneWidget, reason: '재조회 중 목록이 사라졌다');
      await t.tap(_approveOf('근로cr2'), warnIfMissed: false);
      await _advance(t, 300);
      expect(find.byType(Dialog), findsNothing, reason: '처리 뒤 재조회 중 처리 전 목록으로 다시 승인할 수 있다');
      await _advance(t, 2000);
      expect(find.byKey(const ValueKey('payroll-refresh-after-mutation')), findsNothing);
      expect(findVisibleTextContaining('근로cr1 · 지급방식 변경'), findsNothing);
      expect(_approveOf('근로cr2'), findsOneWidget);
    });

    testWidgets('RQ2 처리 전에 출발한 조회가 진행 중이면 — 끝난 뒤 한 번 더 읽어 처리한 요청이 남지 않는다', (t) async {
      final s = _Srv();
      await _mount(t, s);
      final before = s.listCalls();
      s.listDelay = 1200;
      // 새로고침 — 월 목록(짧음) 뒤 요청 목록 재조회가 느리게 진행 중
      await t.tap(find.byIcon(Icons.refresh_rounded));
      await _advance(t, 400);
      expect(s.listCalls(), before + 1);
      // 그 조회가 끝나기 전에 승인(조회는 승인 전 상태를 들고 온다)
      s.listDelay = 200;
      await _approve(t, '근로cr1');
      await _advance(t, 3000);
      expect(findVisibleTextContaining('근로cr1 · 지급방식 변경'), findsNothing,
          reason: '처리 전에 출발한 조회가 앉아 방금 승인한 요청이 승인 버튼과 함께 남았다');
      expect(s.listCalls(), before + 2, reason: '처리 뒤 상태로 한 번 더 읽는다');
      expect(find.byKey(const ValueKey('payroll-refresh-after-mutation')), findsNothing);
    });

    testWidgets('RQ3 변경요청 조회 실패는 "요청이 없습니다"가 아니다', (t) async {
      final s = _Srv()..listFails = true;
      await _mount(t, s);
      expect(findVisibleText('지급방식 변경 요청이 없습니다'), findsNothing,
          reason: '조회 실패를 요청 없음으로 그렸다');
      expect(findVisibleText('변경 요청을 불러오지 못했습니다.'), findsOneWidget);
      expect(findVisibleText('다시 시도'), findsOneWidget);
    });
  });
}
