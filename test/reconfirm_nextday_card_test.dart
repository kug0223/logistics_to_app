// [RECONFIRM-NEXTDAY-CARD] 10/19 21시 리컨펌 알림이 여는 출퇴근 체크 화면 — RA-1~7(reconfirm_upcoming_access_test) 보강.
//   시간 표시 · 이미 응답한 상태 · 다른 지원서 · 오늘 근무와 함께 · 운영 응답 경로 payload.
import 'support/visible_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ALfit/models/core/application_model.dart';
import 'package:ALfit/models/core/attendance_model.dart';
import 'package:ALfit/models/core/business_model.dart' show AttendanceRules;
import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/models/core/user_region.dart';
import 'package:ALfit/providers/notification_provider.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/screens/user/attendance_check_reads.dart';

import 'support/checkin_contract_fixture.dart';
import 'package:ALfit/screens/user/attendance_check_screen.dart';

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

class _P extends UserProvider {
  @override
  UserModel? get currentUser => UserModel(
        uid: 'u1',
        username: 'u1',
        name: '김근로',
        email: 'u1@alfit.local',
        role: UserRole.USER,
        homeRegion: const UserRegion(province: '경기도', city: '평택시'),
        accountStatus: 'active',
      );
  @override
  bool get isSubAdmin => false;
  @override
  bool get isBusinessAdmin => false;
  @override
  bool get isSuperAdmin => false;
  @override
  bool get isAdminMode => false;
  @override
  bool get permissionsLoaded => true;
}

DateTime _kst(int y, int mo, int d, [int h = 0, int mi = 0]) =>
    DateTime.utc(y, mo, d, h, mi).subtract(const Duration(hours: 9));

enum _Device { kst, utc }

DateTime _dev(DateTime utcInstant, _Device d) =>
    d == _Device.kst ? utcInstant.toLocal() : utcInstant.toUtc();

ApplicationModel _app(
  _Device d, {
  required String id,
  required String biz,
  required int day,
  String start = '10:00',
  String end = '11:00',
  String status = AppStatus.confirmed,
  String? reconfirm,
}) =>
    ApplicationModel(
      id: id,
      toId: 'to_$id',
      uid: 'u1',
      businessId: 'biz1',
      businessName: biz,
      toTitle: 'QA',
      status: status,
      selectedWorkType: 'QA 분류',
      startTime: start,
      endTime: end,
      wage: 12000,
      workDate: _dev(_kst(2026, 10, day), d),
      appliedAt: _dev(_kst(2026, 10, 17), d),
      attendancePolicySnapshot: const AttendanceRules(),
      reconfirmStatus: reconfirm,
    );

AttendanceCheckReads _reads(List<ApplicationModel> Function() apps) =>
    AttendanceCheckReads(
      myApplications: (uid) async => apps(),
      // [CONTRACT-BEFORE-CHECKIN] 출근 버튼은 계약 양측 서명 완료일 때만 열린다(2026-10-25) — 이 시험의 전제로 명시
      myContracts: (uid) async => completedContractsFor(apps()),
      todayAttendance: (
              {required String userId, required String applicationId}) async =>
          null as AttendanceModel?,
    );

Future<void> _pump(WidgetTester tester, Widget screen) async {
  tester.view.physicalSize = const Size(390, 2600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<UserProvider>(create: (_) => _P()),
        ChangeNotifierProvider<NotificationProvider>(
            create: (_) => NotificationProvider()),
      ],
      child: MaterialApp(home: screen),
    ),
  );
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}


const _callCh =
    'dev.flutter.pigeon.cloud_functions_platform_interface.CloudFunctionsHostApi.call';

/// 그 사업장 카드 안의 버튼 — 화면에서 사업장 이름 아래에 있는 가장 가까운 버튼.
Finder _buttonUnder(WidgetTester t, String biz, String label) {
  final top = t.getTopLeft(findVisibleText(biz).first).dy;
  final cands = findVisibleText(label).evaluate().toList()
    ..sort((a, b) => t.getTopLeft(find.byWidget(a.widget)).dy
        .compareTo(t.getTopLeft(find.byWidget(b.widget)).dy));
  final below = cands.where((e) => t.getTopLeft(find.byWidget(e.widget)).dy > top);
  return find.byWidget(below.first.widget);
}

Future<void> _settle(WidgetTester t) async {
  for (var i = 0; i < 20; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
    await initializeDateFormatting('ko_KR', null);
  });

  // 리컨펌 OS 알림이 여는 화면 = `const AttendanceCheckScreen()`(fcm_service.dart:649).
  // 같은 위젯에 읽기·시계만 주입한다. 시각은 리컨펌 발송 직후 10/19 21:00:10 KST.
  for (final d in _Device.values) {
    group('기기 ${d.name}', () {
      DateTime now() => _dev(_kst(2026, 10, 19, 21, 0).add(const Duration(seconds: 10)), d);

      testWidgets('RN-1 오늘 0건·내일 Zdn7 pending — 날짜·시간·사업장·가능/불가 버튼', (t) async {
        final apps = [_app(d, id: 'zdn7', biz: '골든패스 사업장', day: 20, reconfirm: 'pending')];
        await _pump(t, AttendanceCheckScreen(
            reads: _reads(() => apps), clock: now, reconfirmResponder: (_, __) async => true));
        expect(findVisibleText('골든패스 사업장'), findsWidgets);
        expect(findVisibleTextContaining('10월 20일'), findsWidgets);
        expect(findVisibleTextContaining('10:00'), findsWidgets, reason: '근무 시작 시각');
        expect(findVisibleTextContaining('11:00'), findsWidgets, reason: '근무 종료 시각');
        expect(findVisibleText('네, 출근합니다'), findsOneWidget);
        expect(findVisibleText('아니요, 취소할게요'), findsOneWidget);
        expect(findVisibleText('오늘 확정된 근무가 없습니다'), findsNothing);
      });

      testWidgets('RN-2 이미 응답한 내일 근무(confirmed·declined)는 응답 카드가 없다', (t) async {
        final apps = [
          _app(d, id: 'zdn7', biz: '골든패스 사업장', day: 20, reconfirm: 'confirmed'),
          _app(d, id: 'other', biz: '다른 사업장', day: 20, reconfirm: 'declined'),
        ];
        await _pump(t, AttendanceCheckScreen(
            reads: _reads(() => apps), clock: now, reconfirmResponder: (_, __) async => true));
        expect(findVisibleText('네, 출근합니다'), findsNothing);
        expect(findVisibleText('오늘 확정된 근무가 없습니다'), findsOneWidget);
      });

      testWidgets('RN-3 내일 pending 두 건 — 누른 카드의 지원서 id 만 한 번 간다', (t) async {
        final apps = [
          _app(d, id: 'zdn7', biz: '골든패스 사업장', day: 20, reconfirm: 'pending'),
          _app(d, id: 'other', biz: '다른 사업장', day: 20, start: '14:00', end: '15:00', reconfirm: 'pending'),
        ];
        final calls = <String>[];
        await _pump(t, AttendanceCheckScreen(
            reads: _reads(() => apps), clock: now,
            reconfirmResponder: (id, r) async { calls.add('$id:$r'); return true; }));
        expect(findVisibleText('네, 출근합니다'), findsNWidgets(2));
        await t.ensureVisible(_buttonUnder(t, '다른 사업장', '네, 출근합니다'));
        await t.tap(_buttonUnder(t, '다른 사업장', '네, 출근합니다'));
        await _settle(t);
        expect(calls, ['other:confirmed']);
      });

      testWidgets('RN-4 오늘 근무와 함께 — 내일 카드 응답은 내일 지원서 id 로 간다', (t) async {
        final apps = [
          _app(d, id: 'today', biz: '오늘 사업장', day: 19, start: '22:00', end: '23:00'),
          _app(d, id: 'zdn7', biz: '골든패스 사업장', day: 20, reconfirm: 'pending'),
        ];
        final calls = <String>[];
        await _pump(t, AttendanceCheckScreen(
            reads: _reads(() => apps), clock: now,
            reconfirmResponder: (id, r) async { calls.add('$id:$r'); return true; }));
        expect(findVisibleText('오늘 사업장'), findsWidgets);
        expect(findVisibleText('네, 출근합니다'), findsOneWidget, reason: '오늘 근무(pending 아님)에는 응답 버튼이 없다');
        await t.ensureVisible(findVisibleText('네, 출근합니다'));
        await t.tap(findVisibleText('네, 출근합니다'));
        await _settle(t);
        expect(calls, ['zdn7:confirmed']);
      });
    });
  }

  testWidgets('RN-5 운영 응답 경로(주입 없음) — callable 에 {applicationId, response} 가 한 번 간다', (t) async {
    final payloads = <Map<Object?, Object?>>[];
    t.binding.defaultBinaryMessenger.setMockMessageHandler(_callCh, (data) async {
      final args = (const StandardMessageCodec().decodeMessage(data) as List).first as Map;
      if (args['functionName'] == 'callableRespondToReconfirm') {
        payloads.add(Map<Object?, Object?>.from(args['parameters'] as Map));
        await Future<void>.delayed(const Duration(milliseconds: 200));
        return const StandardMessageCodec().encodeMessage(<Object?>[
          <String, Object?>{'success': true, 'toId': 'to_zdn7'}
        ]);
      }
      return const StandardMessageCodec().encodeMessage(<Object?>['unavailable', 'mock', null]);
    });
    addTearDown(() => t.binding.defaultBinaryMessenger.setMockMessageHandler(_callCh, null));
    final apps = [_app(_Device.kst, id: 'zdn7', biz: '골든패스 사업장', day: 20, reconfirm: 'pending')];
    await _pump(t, AttendanceCheckScreen(
        reads: _reads(() => apps),
        clock: () => _kst(2026, 10, 19, 21, 0).add(const Duration(seconds: 10)).toLocal()));
    final btn = findVisibleText('네, 출근합니다');
    await t.tap(btn);
    await t.tap(btn, warnIfMissed: false); // 연타
    await _settle(t);
    expect(payloads, hasLength(1));
    expect(payloads.single, {'applicationId': 'zdn7', 'response': 'confirmed'});
    t.takeException();
  });
}
