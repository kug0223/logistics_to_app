// [ADMIN-REVIEW-NESTED] 관리자 리뷰 요청 목록 → `작성` 의 안쪽 응답 변환.
//
// 경로: AdminReviewListScreen `미작성` 탭 → 요청 행 `작성` → _openReviewFromRequest
//   → callableGetUsersBatch + callableGetAdminAttendances 병렬 → showMonthlyReviewDialog.
//
// 플러그인(cloud_functions 5.6.2 / platform_interface 5.8.2)은 응답 **최상위만**
//   Map<String, dynamic> 으로 바꾼다. 안쪽 map 은 StandardMessageCodec 이 만든
//   Map<Object?, Object?> 그대로다. 이 하네스는 같은 플랫폼 채널을 거치므로
//   안쪽 타입이 기기와 같다. DEV 호출·리뷰 제출 없음.
//
// DEV 응답 모양(배포본 판독):
//   callableGetUsersBatch      → {users: {uid: {gender, birthDate: {_seconds, _nanoseconds}, …}}}
//   callableGetAdminAttendances → {items: [{id, status, wageStatus, …}]}
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ALfit/models/core/attendance_model.dart';
import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/providers/notification_provider.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/screens/business_admin/admin_review_list_screen.dart';
import 'package:ALfit/utils/navigation_key.dart';
import 'package:ALfit/widgets/dialogs/monthly_review_dialog.dart';

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

class _AdminP extends UserProvider {
  @override
  UserModel? get currentUser => UserModel(
      uid: 'OWNER', username: 'owner', name: '관리자',
      email: 'owner@test.local', role: UserRole.BUSINESS_ADMIN);
  @override
  String? get effectiveBusinessId => 'BIZ';
}

const _channel =
    'dev.flutter.pigeon.cloud_functions_platform_interface.CloudFunctionsHostApi.call';
const _failToast = '추가 정보를 불러오는 데 실패했습니다';

final _now = DateTime.now();
// KST 1995-06-15 00:00
final _birthSeconds =
    DateTime.utc(1995, 6, 14, 15).millisecondsSinceEpoch ~/ 1000;
// 화면 계산식과 같은 식(기기 로컬 연도)
final _expectedAge = DateTime.now().year -
    DateTime.fromMillisecondsSinceEpoch(_birthSeconds * 1000).year;

Map<String, Object?> _ts(DateTime d) => <String, Object?>{
      '_seconds': d.millisecondsSinceEpoch ~/ 1000,
      '_nanoseconds': 0,
    };

enum _Users { full, noEntry, entryWithoutFields, fail }

enum _Att { mixed, empty, missingKey, fail }

class _Server {
  _Server({this.users = _Users.full, this.att = _Att.mixed});
  final _Users users;
  final _Att att;
  final calls = <String>[];

  Future<ByteData?> handle(ByteData? message) async {
    final args = (const StandardMessageCodec().decodeMessage(message) as List)
        .first as Map;
    final name = args['functionName'] as String;
    final params = (args['parameters'] as Map?) ?? const {};
    calls.add(name);
    switch (name) {
      case 'callableGetMonthlyReviewsByBiz':
        return _ok({'reviews': <Object?>[]});
      case 'callableGetReviewRequestsByBiz':
        return _ok({
          'reviewRequests': <Object?>[
            <String, Object?>{
              'id': 'REQ1',
              'requestKey': 'BIZ_W1_${_now.year}_${_now.month}',
              'businessId': 'BIZ',
              'businessName': 'QA 사업장',
              'workerId': 'W1',
              'workerName': 'QA 근로자',
              'reviewYear': _now.year,
              'reviewMonth': _now.month,
              'deadline': _ts(_now.add(const Duration(days: 10))),
              'adminStatus': 'pending',
              'workerStatus': 'pending',
              'isPublished': false,
              'createdAt': _ts(_now.subtract(const Duration(days: 1))),
            }
          ],
        });
      case 'callableGetUsersBatch':
        // 목록 로드 때는 workerName 이 있어 호출되지 않는다 — 여기는 `작성` 경로다.
        expect(params['uids'], ['W1']);
        switch (users) {
          case _Users.fail:
            return _err('permission-denied');
          case _Users.noEntry:
            return _ok({'users': <String, Object?>{}});
          case _Users.entryWithoutFields:
            return _ok({
              'users': <String, Object?>{
                'W1': <String, Object?>{'name': 'QA 근로자', 'personNo': 'P1'},
              }
            });
          case _Users.full:
            return _ok({
              'users': <String, Object?>{
                'W1': <String, Object?>{
                  'name': 'QA 근로자',
                  'gender': 'male',
                  'birthDate': <String, Object?>{
                    '_seconds': _birthSeconds,
                    '_nanoseconds': 0,
                  },
                  'personNo': 'P1',
                },
              }
            });
        }
      case 'callableGetAdminAttendances':
        expect(params['userId'], 'W1');
        switch (att) {
          case _Att.fail:
            return _err('internal');
          case _Att.empty:
            return _ok({'items': <Object?>[]});
          case _Att.missingKey:
            return _ok(<String, Object?>{});
          case _Att.mixed:
            return _ok({
              'items': <Object?>[
                _att('A1', AttendanceModel.statusPresent, AttendanceModel.wageConfirmed),
                _att('A2', AttendanceModel.statusLate, AttendanceModel.wageTransferred),
                // 노쇼도 wageStatus=confirmed(0원 마감) — 근무일이 아니다
                _att('A3', AttendanceModel.statusNoShow, AttendanceModel.wageConfirmed),
                // 미확정
                _att('A4', AttendanceModel.statusPresent, null),
              ],
            });
        }
      default:
        return _err('not-found');
    }
  }

  Map<String, Object?> _att(String id, String status, String? wage) =>
      <String, Object?>{
        'id': id,
        'userId': 'W1',
        'businessId': 'BIZ',
        'status': status,
        'wageStatus': wage,
        'workDate': _ts(_now),
      };

  ByteData? _ok(Map<String, Object?> body) =>
      const StandardMessageCodec().encodeMessage(<Object?>[body]);

  ByteData? _err(String code) => const StandardMessageCodec().encodeMessage(
      <Object?>[code, 'mock $code', <String, Object?>{'code': code}]);
}

void _stubAuthChannels(WidgetTester t) {
  const base =
      'dev.flutter.pigeon.firebase_auth_platform_interface.FirebaseAuthHostApi';
  for (final m in ['registerIdTokenListener', 'registerAuthStateListener']) {
    t.binding.defaultBinaryMessenger.setMockMessageHandler('$base.$m',
        (_) async => const StandardMessageCodec()
            .encodeMessage(<Object?>['test/auth-events']));
  }
  t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('test/auth-events'), (_) async => null);
}

Future<void> _settle(WidgetTester t, [int n = 20]) async {
  for (var i = 0; i < n; i++) {
    await t.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _realAsync(WidgetTester t, [int rounds = 3]) async {
  for (var i = 0; i < rounds; i++) {
    await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)));
    await _settle(t, 5);
  }
}

class _Observed {
  _Observed(this.dialog, this.toastShown, this.workDaysText);
  final MonthlyReviewDialog dialog;
  final bool toastShown;
  final bool workDaysText;
}

Future<_Observed> _openReview(WidgetTester t, _Server server,
    {required int expectedDays}) async {
  t.view.physicalSize = const Size(411, 1600);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  _stubAuthChannels(t);
  t.binding.defaultBinaryMessenger
      .setMockMessageHandler(_channel, server.handle);
  addTearDown(() => t.binding.defaultBinaryMessenger
      .setMockMessageHandler(_channel, null));

  await t.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider<UserProvider>(create: (_) => _AdminP()),
      ChangeNotifierProvider<NotificationProvider>(
          create: (_) => NotificationProvider()),
    ],
    child: MaterialApp(
      navigatorKey: navigatorKey,
      home: const AdminReviewListScreen(businessId: 'BIZ'),
    ),
  ));
  await _realAsync(t);
  await _settle(t);

  await t.tap(find.text('미작성').first);
  await _settle(t);

  final write = find.widgetWithText(ElevatedButton, '작성');
  expect(write, findsOneWidget, reason: '미작성 탭에 요청 행 `작성` 버튼이 있어야 한다');
  await t.tap(write);
  // 병렬 callable + 다이얼로그 전 태그 읽기(Firestore 플러그인 — 실패 시 기본값)
  await _settle(t, 4);
  final toastEarly = find.text(_failToast).evaluate().isNotEmpty;
  await _realAsync(t, 4);
  final toastLate = find.text(_failToast).evaluate().isNotEmpty;
  await _settle(t);

  final dlg = find.byType(MonthlyReviewDialog);
  expect(dlg, findsOneWidget, reason: '실패해도 다이얼로그는 열린다(기존 계약)');
  final w = t.widget<MonthlyReviewDialog>(dlg);
  final daysShown = find
      .descendant(of: dlg, matching: find.text('$expectedDays일'))
      .evaluate()
      .isNotEmpty;
  // 토스트 2초 타이머를 흘려보낸다(다이얼로그는 남는다)
  await t.pump(const Duration(seconds: 3));
  return _Observed(w, toastEarly || toastLate, daysShown);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
  });

  testWidgets('RN-1 채널 모양 정상 응답 — 성별·나이·실근무일이 다이얼로그에 전달되고 오류 안내가 없다',
      (t) async {
    final s = _Server();
    final o = await _openReview(t, s, expectedDays: 2);
    // ignore: avoid_print
    print('RN-1 OBSERVED gender=${o.dialog.targetUserGender} '
        'age=${o.dialog.targetUserAge} days=${o.dialog.workDaysInMonth} '
        'toast=${o.toastShown} calls=${s.calls}');
    expect(s.calls, containsAll(['callableGetUsersBatch', 'callableGetAdminAttendances']));
    expect(o.toastShown, isFalse, reason: '정상 응답에 실패 안내가 뜨면 안 된다');
    expect(o.dialog.targetUserGender, 'male');
    expect(o.dialog.targetUserAge, _expectedAge);
    expect(o.dialog.workDaysInMonth, 2,
        reason: 'present+confirmed, late+transferred 만 — 노쇼·미확정 제외');
    expect(o.workDaysText, isTrue, reason: '근태 요약에 `2일`');
  });

  testWidgets('RN-2 근태 읽기 실패 — 실패 안내 + 근무일 0, 다이얼로그는 열린다', (t) async {
    final o = await _openReview(t, _Server(att: _Att.fail), expectedDays: 0);
    // ignore: avoid_print
    print('RN-2 OBSERVED gender=${o.dialog.targetUserGender} '
        'age=${o.dialog.targetUserAge} days=${o.dialog.workDaysInMonth} '
        'toast=${o.toastShown}');
    expect(o.toastShown, isTrue);
    expect(o.dialog.workDaysInMonth, 0);
  });

  testWidgets('RN-3 사용자 읽기 실패 — 실패 안내, 성별·나이 없음', (t) async {
    final o = await _openReview(t, _Server(users: _Users.fail), expectedDays: 0);
    // ignore: avoid_print
    print('RN-3 OBSERVED gender=${o.dialog.targetUserGender} '
        'age=${o.dialog.targetUserAge} days=${o.dialog.workDaysInMonth} '
        'toast=${o.toastShown}');
    expect(o.toastShown, isTrue);
    expect(o.dialog.targetUserGender, isNull);
    expect(o.dialog.targetUserAge, isNull);
  });

  testWidgets('RN-4 사용자 항목 없음 + 근태 0건 — 실패 아님(안내 없음), 값 없음·0일', (t) async {
    final o = await _openReview(
        t, _Server(users: _Users.noEntry, att: _Att.empty), expectedDays: 0);
    // ignore: avoid_print
    print('RN-4 OBSERVED gender=${o.dialog.targetUserGender} '
        'age=${o.dialog.targetUserAge} days=${o.dialog.workDaysInMonth} '
        'toast=${o.toastShown}');
    expect(o.toastShown, isFalse);
    expect(o.dialog.targetUserGender, isNull);
    expect(o.dialog.targetUserAge, isNull);
    expect(o.dialog.workDaysInMonth, 0);
    expect(o.workDaysText, isTrue);
  });

  testWidgets('RN-5 성별·생일 필드 없음 + items 키 없음 — 안내 없음, 값 없음·0일', (t) async {
    final o = await _openReview(
        t, _Server(users: _Users.entryWithoutFields, att: _Att.missingKey),
        expectedDays: 0);
    // ignore: avoid_print
    print('RN-5 OBSERVED gender=${o.dialog.targetUserGender} '
        'age=${o.dialog.targetUserAge} days=${o.dialog.workDaysInMonth} '
        'toast=${o.toastShown}');
    expect(o.toastShown, isFalse);
    expect(o.dialog.targetUserGender, isNull);
    expect(o.dialog.targetUserAge, isNull);
    expect(o.dialog.workDaysInMonth, 0);
  });
}
