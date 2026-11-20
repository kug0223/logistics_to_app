// [REVIEW-WORKED-DAYS-NOSHOW] 관리자 월간 리뷰의 `근무일` — 노쇼·결근은 근무일이 아니다.
//
// 저장 필드 workDaysInMonth 의 의미는 **실제 근무일**이다:
//   · 리뷰 카드가 `근무 N일` 로 그린다(review_card).
//   · 리뷰 목록 경로는 [R7-P1-4 §11] 에서 이미 canonical 실근무 판정
//     (AttendanceModel.isActualFinalizedWork = 서버 srvIsActualFinalizedWork)으로 바꿨다.
//     callableBatchSetNoShow·자동 노쇼는 wageStatus 를 confirmed(0원 마감)로 쓰므로
//     wageStatus 만 보면 오지 않은 날이 근무일로 세어진다.
//
// 이 파일이 고정하는 것 — 같은 근태(채널 모양)를 두 진입점에 넣으면 같은 수가 나온다:
//   세계 A: present/confirmed 1 + NO_SHOW/confirmed 1                     → 1
//   세계 B: late/transferred · early_leave/confirmed · absent/confirmed ·
//           present/pending · present/calculated · NO_SHOW/transferred   → 2
//
// 진입점: 리뷰 목록 `미작성 → 작성` · 알림 `리뷰 작성 요청` 탭.
//   세 번째 진입점(근로자 상세)은 서버 callableGetWorkerReviewSummary 가 센 수를
//   그대로 쓴다 — 서버 수정 범위라 여기서는 고정하지 않는다(보고서 참조).
//
// 플랫폼 채널(cloud_functions · cloud_firestore pigeon)을 그대로 거친다. DEV 호출 없음.
import 'support/visible_text.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_firestore_platform_interface/cloud_firestore_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ALfit/models/core/attendance_model.dart';
import 'package:ALfit/models/core/notification_model.dart';
import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/providers/notification_provider.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/screens/business_admin/admin_review_list_screen.dart';
import 'package:ALfit/screens/common/notification_screen.dart';
import 'package:ALfit/utils/navigation_key.dart';
import 'package:ALfit/widgets/dialogs/monthly_review_dialog.dart';

class _FakeApp extends Fake
    with MockPlatformInterfaceMixin
    implements FirebaseAppPlatform {
  @override
  String get name => defaultFirebaseAppName;
  @override
  FirebaseOptions get options => const FirebaseOptions(
      apiKey: 'k', appId: 'a', messagingSenderId: 's', projectId: 'p',
      storageBucket: 'p.appspot.com');
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
      email: 'owner@test.local', role: UserRole.BUSINESS_ADMIN,
      createdAt: DateTime(2026, 1, 1));
  @override
  String? get effectiveBusinessId => 'BIZ';
  @override
  bool get isUser => false;
  @override
  bool get isBusinessAdmin => true;
  @override
  bool get isSubAdmin => false;
  @override
  bool get isAdminMode => true;
  @override
  bool get permissionsLoaded => true;
}

class _NotifDouble extends NotificationProvider {
  _NotifDouble(this.items);
  final List<NotificationModel> items;
  @override
  List<NotificationModel> get notifications => items;
  @override
  bool get isLoading => false;
  @override
  bool get hasError => false;
  @override
  bool get hasMore => false;
  @override
  bool get isLoadingMore => false;
  @override
  bool get loadMoreFailed => false;
  @override
  Future<void> markAsRead(String id) async {}
}

const _fnChannel =
    'dev.flutter.pigeon.cloud_functions_platform_interface.CloudFunctionsHostApi.call';
const _fsGet =
    'dev.flutter.pigeon.cloud_firestore_platform_interface.FirebaseFirestoreHostApi.documentReferenceGet';

final _now = DateTime.now();
final _reqKey = 'BIZ_W1_${_now.year}_${_now.month}';

typedef _Row = (String status, String? wage);

const _worldA = <_Row>[
  (AttendanceModel.statusPresent, AttendanceModel.wageConfirmed),
  (AttendanceModel.statusNoShow, AttendanceModel.wageConfirmed),
];
const _worldB = <_Row>[
  (AttendanceModel.statusLate, AttendanceModel.wageTransferred),
  (AttendanceModel.statusEarlyLeave, AttendanceModel.wageConfirmed),
  (AttendanceModel.statusAbsent, AttendanceModel.wageConfirmed),
  (AttendanceModel.statusPresent, AttendanceModel.wagePending),
  (AttendanceModel.statusPresent, AttendanceModel.wageCalculated),
  (AttendanceModel.statusNoShow, AttendanceModel.wageTransferred),
];

Map<String, Object?> _ts(DateTime d) => <String, Object?>{
      '_seconds': d.millisecondsSinceEpoch ~/ 1000,
      '_nanoseconds': 0,
    };

Map<String, Object?> _request() => <String, Object?>{
      'requestKey': _reqKey,
      'businessId': 'BIZ',
      'businessName': 'QA 사업장',
      'workerId': 'W1',
      'workerName': 'QA 근로자',
      'reviewYear': _now.year,
      'reviewMonth': _now.month,
      'adminStatus': 'pending',
      'workerStatus': 'pending',
      'isPublished': false,
    };

/// callable 서버 — DEV callableGetAdminAttendances 와 같은 모양({items:[{id,status,wageStatus,…}]}).
class _Fn {
  _Fn(this.rows);
  final List<_Row> rows;
  final calls = <String>[];

  Future<ByteData?> handle(ByteData? message) async {
    final args = (const StandardMessageCodec().decodeMessage(message) as List)
        .first as Map;
    final name = args['functionName'] as String;
    calls.add(name);
    switch (name) {
      case 'callableGetMonthlyReviewsByBiz':
        return _ok({'reviews': <Object?>[]});
      case 'callableGetReviewRequestsByBiz':
        return _ok({
          'reviewRequests': <Object?>[
            <String, Object?>{
              'id': _reqKey,
              ..._request(),
              'deadline': _ts(_now.add(const Duration(days: 10))),
              'createdAt': _ts(_now.subtract(const Duration(days: 1))),
            }
          ],
        });
      case 'callableGetUsersBatch':
        return _ok({
          'users': <String, Object?>{
            'W1': <String, Object?>{'name': 'QA 근로자'},
          }
        });
      case 'callableGetAdminAttendances':
        var i = 0;
        return _ok({
          'items': <Object?>[
            for (final (s, w) in rows)
              <String, Object?>{
                'id': 'A${++i}',
                'userId': 'W1',
                'businessId': 'BIZ',
                'status': s,
                'wageStatus': w,
                'workDate': _ts(_now),
              }
          ],
        });
      default:
        return const StandardMessageCodec().encodeMessage(
            <Object?>['not-found', 'mock', <String, Object?>{'code': 'not-found'}]);
    }
  }

  ByteData? _ok(Map<String, Object?> body) =>
      const StandardMessageCodec().encodeMessage(<Object?>[body]);
}

/// Firestore 단건 읽기 — 알림 경로가 review_requests·users 를 직접 읽는다.
Future<ByteData?> _fsHandle(ByteData? message) async {
  const codec = FirebaseFirestoreHostApi.codec;
  final args = codec.decodeMessage(message) as List;
  final req = args[1] as DocumentReferenceRequest;
  Map<String?, Object?>? data;
  if (req.path == 'review_requests/$_reqKey') {
    data = <String?, Object?>{
      ..._request(),
      'deadline': Timestamp.fromDate(_now.add(const Duration(days: 10))),
      'createdAt': Timestamp.fromDate(_now.subtract(const Duration(days: 1))),
    };
  } else if (req.path == 'users/W1') {
    data = <String?, Object?>{
      'name': 'QA 근로자', 'username': 'w1', 'email': 'w1@test.local',
      'role': 'USER',
    };
  }
  return codec.encodeMessage(<Object?>[
    PigeonDocumentSnapshot(
      path: req.path,
      data: data,
      metadata: PigeonSnapshotMetadata(hasPendingWrites: false, isFromCache: false),
    ),
  ]);
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

void _install(WidgetTester t, _Fn fn) {
  t.view.physicalSize = const Size(411, 1600);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  _stubAuthChannels(t);
  final m = t.binding.defaultBinaryMessenger;
  m.setMockMessageHandler(_fnChannel, fn.handle);
  m.setMockMessageHandler(_fsGet, _fsHandle);
  addTearDown(() {
    m.setMockMessageHandler(_fnChannel, null);
    m.setMockMessageHandler(_fsGet, null);
  });
}

/// 마지막으로 연 작성창의 근태 요약 — 진입점이 넘긴 값과 화면의 `결근` 칸.
({int workDays, int? onTime, int? late, bool absenceShown, String? absenceText})? lastStats;

Future<int> _dialogDays(WidgetTester t) async {
  final dlg = find.byType(MonthlyReviewDialog);
  expect(dlg, findsOneWidget, reason: '리뷰 작성 다이얼로그가 열려야 한다');
  final w = t.widget<MonthlyReviewDialog>(dlg);
  final days = w.workDaysInMonth;
  final absence = find.descendant(of: dlg, matching: find.text('결근'));
  String? absenceText;
  if (absence.evaluate().isNotEmpty) {
    final col = find.ancestor(of: absence.first, matching: find.byType(Column)).first;
    absenceText = t.widgetList<Text>(find.descendant(of: col, matching: find.byType(Text)))
        .map((x) => x.data ?? '').where((x) => x.endsWith('일')).join(',');
  }
  lastStats = (
    workDays: days,
    onTime: w.normalAttendanceDays,
    late: w.lateDays,
    absenceShown: absence.evaluate().isNotEmpty,
    absenceText: absenceText,
  );
  // 화면 표기도 같은 수다
  expect(
      find.descendant(of: dlg, matching: find.text('$days일')), findsWidgets);
  await t.pump(const Duration(seconds: 3)); // 토스트 타이머 비우기
  return days;
}

/// 진입점 1 — 리뷰 목록 `미작성` → `작성`
Future<int> _viaList(WidgetTester t, List<_Row> rows) async {
  final fn = _Fn(rows);
  _install(t, fn);
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
  await t.tap(find.widgetWithText(ElevatedButton, '작성'));
  await _settle(t, 4);
  await _realAsync(t, 4);
  await _settle(t);
  expect(fn.calls, contains('callableGetAdminAttendances'));
  return _dialogDays(t);
}

/// 진입점 2 — 알림 `리뷰 작성 요청` 탭
Future<int> _viaNotification(WidgetTester t, List<_Row> rows) async {
  final fn = _Fn(rows);
  _install(t, fn);
  final n = NotificationModel(
    id: 'N1', userId: 'OWNER', type: NotificationType.reviewRequest,
    title: '리뷰 작성 요청', body: 'QA 근로자님의 리뷰를 작성해 주세요.',
    isRead: false,
    createdAt: _now.subtract(const Duration(minutes: 5)),
    data: {'requestKey': _reqKey, 'businessId': 'BIZ'},
  );
  await t.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider<NotificationProvider>.value(
          value: _NotifDouble([n])),
      ChangeNotifierProvider<UserProvider>.value(value: _AdminP()),
    ],
    child: MaterialApp(
      navigatorKey: navigatorKey,
      home: const NotificationScreen(),
    ),
  ));
  await t.pump();
  await t.pump(const Duration(milliseconds: 100));
  // [.66] 알림 카드 제목은 keepWords(낱말 결합 문자)로 그린다 — 보이는 글자로 찾는다.
  await t.tap(findVisibleText('리뷰 작성 요청').first);
  await _settle(t, 4);
  await _realAsync(t, 5);
  await _settle(t);
  expect(fn.calls, contains('callableGetAdminAttendances'));
  return _dialogDays(t);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));
  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
    await initializeDateFormatting('ko_KR', null);
  });

  for (final (label, rows, expected) in [
    ('A present1+NO_SHOW1', _worldA, 1),
    ('B 경계 6행', _worldB, 2),
  ]) {
    testWidgets('WD-LIST $label — 리뷰 목록 진입점 = $expected일', (t) async {
      final d = await _viaList(t, rows);
      // ignore: avoid_print
      print('WD-LIST $label OBSERVED days=$d');
      expect(d, expected);
    });
    testWidgets('WD-NOTIF $label — 알림 진입점 = $expected일', (t) async {
      final d = await _viaNotification(t, rows);
      // ignore: avoid_print
      print('WD-NOTIF $label OBSERVED days=$d');
      expect(d, expected);
    });
  }

  // [REVIEW-ABSENCE-METRIC] 정시·지각·결근 — 근무일과 같은 원장(items)에서 센다.
  //   정시 = 실근무 확정 중 present·early_leave (월간 통계 `admin_stats_service` 와 같은 분류)
  //   지각 = 실근무 확정 중 late
  //   결근 = 작성창은 근무일 − 정시 − 지각 으로 계산한다. 근무일이 실근무만이라
  //          정확한 입력에서는 0 이고 칸이 뜨지 않아야 한다. 노쇼·결근 status 는
  //          근무일에 없으므로 이 식으로 셀 수 없다(별도 데이터·제품 정의 필요 — UNKNOWN).
  const worldC = <_Row>[
    (AttendanceModel.statusPresent, AttendanceModel.wageConfirmed),
    (AttendanceModel.statusLate, AttendanceModel.wageConfirmed),
    (AttendanceModel.statusNoShow, AttendanceModel.wageConfirmed),
  ];
  const worldD = <_Row>[
    (AttendanceModel.statusPresent, AttendanceModel.wageTransferred),
    (AttendanceModel.statusEarlyLeave, AttendanceModel.wageConfirmed),
    (AttendanceModel.statusLate, AttendanceModel.wageConfirmed),
    (AttendanceModel.statusLate, AttendanceModel.wagePending), // 미확정 — 세지 않는다
    (AttendanceModel.statusAbsent, AttendanceModel.wageConfirmed),
  ];
  for (final (label, rows, wd, onTime, late) in [
    ('C 근무1·지각1·노쇼1', worldC, 2, 1, 1),
    ('D 조퇴·미확정·결근 status 섞임', worldD, 3, 2, 1),
  ]) {
    for (final (entry, run) in [('LIST', _viaList), ('NOTIF', _viaNotification)]) {
      testWidgets('AM-$entry $label — 근무일 $wd · 정시 $onTime · 지각 $late · 결근 칸 없음', (t) async {
        await run(t, rows);
        final s = lastStats!;
        // ignore: avoid_print
        print('AM-$entry $label OBSERVED $s');
        expect(s.workDays, wd);
        expect(s.onTime, onTime, reason: '정시 출근');
        expect(s.late, late, reason: '지각');
        expect(s.absenceShown, isFalse,
            reason: '근무일이 실근무라 근무일−정시−지각 은 0 — 근무한 날을 결근으로 그리면 안 된다');
      });
    }
  }
}
