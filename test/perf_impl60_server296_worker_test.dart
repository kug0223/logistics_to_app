// [서버296 근로자 화면 연결 · impl_60] ① activeIncluded 표식 · ② 탈퇴 미리보기 UNSIGNED_CONTRACT 경고 · ③ ID_CARD_EMPTY 안내.
// ignore_for_file: depend_on_referenced_packages
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ALfit/models/core/application_model.dart';
import 'package:ALfit/models/core/attendance_model.dart';
import 'package:ALfit/models/core/employment_contract_model.dart';
import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/providers/notification_provider.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/screens/user/attendance_check_reads.dart';
import 'package:ALfit/screens/user/attendance_check_screen.dart';
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

class _P extends UserProvider {
  @override
  UserModel? get currentUser =>
      UserModel(uid: 'u1', username: 'u1', name: '김근로', email: 'u1@alfit.local', role: UserRole.USER, accountStatus: 'active');
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

const _cf = 'dev.flutter.pigeon.cloud_functions_platform_interface.CloudFunctionsHostApi.call';

DateTime _kst(int y, int mo, int d, [int h = 0]) => DateTime.utc(y, mo, d, h).subtract(const Duration(hours: 9));

List<ApplicationModel> _pastConfirmed(int n) => [
      for (var i = 0; i < n; i++)
        ApplicationModel(
          id: 'p$i', toId: 'to$i', uid: 'u1', businessId: 'biz1', businessName: 'QA 사업장', toTitle: '지난 근무',
          status: AppStatus.confirmed, selectedWorkType: '분류', startTime: '09:00', endTime: '10:00', wage: 10000,
          workDate: _kst(2026, 9, 1).add(Duration(days: i % 30)), appliedAt: _kst(2026, 8, 1),
        ),
    ];

Future<void> _pumpCheck(WidgetTester t, {required bool? liveComplete}) async {
  t.view.physicalSize = const Size(390, 1600);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  final now = _kst(2026, 11, 27, 12);
  await t.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider<UserProvider>(create: (_) => _P()),
      ChangeNotifierProvider<NotificationProvider>(create: (_) => NotificationProvider()),
    ],
    child: MaterialApp(
      home: AttendanceCheckScreen(
        reads: AttendanceCheckReads(
          myApplications: (uid) async => _pastConfirmed(200),
          todayAttendance: ({required String userId, required String applicationId}) async => null as AttendanceModel?,
          myContracts: (uid) async => const <EmploymentContractModel>[],
          myApplicationsLiveComplete: liveComplete == null ? null : (uid) => liveComplete,
        ),
        clock: () => now,
      ),
    ),
  ));
  for (var i = 0; i < 20; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

String _code(String p) => File(p).readAsStringSync().replaceAll('\r\n', '\n');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
    await initializeDateFormatting('ko_KR', null);
  });

  group('① activeIncluded', () {
    Future<void> respond(Map<String, Object?> data) async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMessageHandler(_cf, (msg) async =>
          const StandardMessageCodec().encodeMessage(<Object?>[data]));
    }

    tearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMessageHandler(_cf, null));

    test('응답에 activeIncluded 가 있으면(새 서버) 진행 중 근무 완결 · 없으면(구서버) false', () async {
      await respond({'applications': <Object?>[], 'hasMore': true, 'lastDocId': null, 'activeIncluded': 0});
      await FirestoreService().getMyApplications('impl60_new');
      expect(FirestoreService().myApplicationsLiveComplete('impl60_new'), isTrue);
      await respond({'applications': <Object?>[], 'hasMore': true, 'lastDocId': null});
      await FirestoreService().getMyApplications('impl60_old');
      expect(FirestoreService().myApplicationsLiveComplete('impl60_old'), isFalse);
      expect(FirestoreService().myApplicationsLiveComplete('impl60_unread'), isFalse);
    });

    testWidgets('상한 200 건 · 표식 있음 → 경고 없이 기존 빈 상태', (t) async {
      await _pumpCheck(t, liveComplete: true);
      expect(findVisibleText('오늘 확정된 근무가 없습니다'), findsOneWidget);
      expect(findVisibleText('오늘 근무를 모두 확인하지 못했어요'), findsNothing);
    });

    testWidgets('상한 200 건 · 표식 없음(구서버) → 기존 방어 유지', (t) async {
      await _pumpCheck(t, liveComplete: false);
      expect(findVisibleText('오늘 근무를 모두 확인하지 못했어요'), findsOneWidget);
    });

    testWidgets('상한 200 건 · 판정 함수 없음(null) → 기존 방어 유지', (t) async {
      await _pumpCheck(t, liveComplete: null);
      expect(findVisibleText('오늘 근무를 모두 확인하지 못했어요'), findsOneWidget);
    });
  });

  group('② · ③ 원문 보조', () {
    test('② 탈퇴 미리보기 경고에 UNSIGNED_CONTRACT 안내(무효 · 사업주 알림) · 구서버 hard 문구 보존', () {
      final c = _code('lib/screens/common/settings_screen.dart');
      final w = c.substring(c.indexOf('String warnLabel('), c.indexOf('String? blockNavKey('));
      expect(w.contains("'UNSIGNED_CONTRACT' => '서명하지 않은 계약서 \$n건 — 탈퇴하면 무효 처리되고 사업주에게 알려요'"), isTrue);
      expect(c.contains("'UNSIGNED_CONTRACT' => '미서명 계약서 \$n건',"), isTrue, reason: '구서버 hardBlocks 문구');
    });

    test('③ 0바이트 신분증(ID_CARD_EMPTY)은 다시 올리라고 안내한다', () {
      final c = _code('lib/screens/common/document_management_screen.dart');
      expect(c.contains("(e.details as Map)['code'] == 'ID_CARD_EMPTY'"), isTrue);
      expect(c.contains('신분증 사진 파일이 비어 있어요. 다시 찍거나 골라 주세요.'), isTrue);
    });
  });

  test('리뷰(근로자) 페이지 조회 실패는 던진다 — 내 근무 평가 화면이 실패와 평가 없음을 구분한다', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMessageHandler(_cf, (msg) async =>
        const StandardMessageCodec().encodeMessage(<Object?>['unavailable', 'impl_60 주입 실패', null]));
    addTearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMessageHandler(_cf, null));
    await expectLater(MonthlyReviewService().getAllReviewsForUserPaged(targetUserId: 'u1'), throwsA(anything));
    await expectLater(MonthlyReviewService().getPublishedReviewsForUserPaged(targetUserId: 'u1'), throwsA(anything));
  });
}
