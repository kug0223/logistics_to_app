// [AUD-5 · impl_42] 근로자 정상 사용 결함 — 네트워크 중간 실패 · 로그인 없는 진입.
//   ①-2 내 지원: 사용자 없이 열려도 스켈레톤에 갇히지 않는다(잠금 해제 · 실패 본문).
//   ②-2 퇴사 요청: 서비스가 실패 사유를 false 로 접지 않는다(호출자가 '이미 접수' · '결과 모름' 을 구분).
//   ②-1 · ②-3 · ②-4 는 해당 흐름의 원문 보조(동작 재현은 보고서 참조).
// ignore_for_file: depend_on_referenced_packages
import 'dart:io';

import 'package:cloud_functions/cloud_functions.dart';
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
import 'package:ALfit/models/core/employment_contract_model.dart';
import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/providers/notification_provider.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/screens/user/my_applications_reads.dart';
import 'package:ALfit/screens/user/my_applications_screen.dart';
import 'package:ALfit/services/firestore_service.dart';
import 'package:ALfit/services/tax_identity_service.dart';

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

/// 로그인하지 않은(세션이 끝난) 상태.
class _NoUser extends UserProvider {
  @override
  UserModel? get currentUser => null;
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

String _code(String p) => File(p).readAsStringSync().replaceAll('\r\n', '\n');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
    await initializeDateFormatting('ko', null);
    await initializeDateFormatting('ko_KR', null);
  });

  testWidgets('①-2 내 지원 · 사용자 없음 — 스켈레톤에 갇히지 않고 실패 본문(다시 시도) · 목록 읽기 0', (t) async {
    var reads = 0;
    t.view.physicalSize = const Size(390, 1400);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    await t.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<UserProvider>(create: (_) => _NoUser()),
        ChangeNotifierProvider<NotificationProvider>(create: (_) => NotificationProvider()),
      ],
      child: MaterialApp(
        home: MyApplicationsScreen(
          reads: MyApplicationsReads(
            myApplicationsPaged: ({required String uid, required int pageSize, String? startAfterDocId}) async {
              reads++;
              return {'items': <ApplicationModel>[], 'lastDocId': null, 'hasMore': false};
            },
            toOrFailure: (toId) async => (to: null, failed: false),
            contractsByWorker: (uid) async => const <EmploymentContractModel>[],
            autoExpirePending: (uid) async {},
            monthlyAttendances: ({required String userId, required int year, required int month}) async => const [],
            reviewById: (key) async => null,
            taxStatus: () async => const TaxIdentityStatus.unknown(),
          ),
        ),
      ),
    ));
    for (var i = 0; i < 30; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    expect(reads, 0);
    expect(find.text('다시 시도'), findsWidgets, reason: '실패 본문의 다시 시도가 있어야 한다(스켈레톤에 갇히지 않음)');
    expect(t.takeException(), isNull);
  });

  test('②-2 퇴사 요청 실패는 던진다(false 로 접지 않는다) · 서버 코드 · 문구 보존', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMessageHandler(_cf, (msg) async =>
        const StandardMessageCodec().encodeMessage(
            <Object?>['failed-precondition', '이미 진행 중인 퇴사 요청이 있습니다: PENDING',
                <String, Object?>{'code': 'failed-precondition'}]));
    addTearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMessageHandler(_cf, null));
    Object? thrown;
    try {
      await FirestoreService().requestResignation(applicationId: 'app1');
    } catch (e) {
      thrown = e;
    }
    expect(thrown, isA<FirebaseFunctionsException>());
    expect((thrown as FirebaseFunctionsException).code, 'failed-precondition');
    expect(thrown.message, contains('이미 진행 중인 퇴사 요청'));
  });

  group('원문 보조 — 흐름이 실패를 성공으로 · 결과 모름을 실패로 말하지 않는다', () {
    test('②-1 확정 취소: 서비스 결과가 false 면 성공 안내 · 노쇼 수 증가 없이 상태만 다시 읽는다', () {
      final c = _code('lib/widgets/dialogs/apply/apply_work_dialog.dart');
      final i = c.indexOf('final canceled = await _firestoreService.cancelConfirmedApplication(');
      expect(i, greaterThan(0));
      final w = c.substring(i, i + 1400);
      final guard = w.indexOf('if (!canceled) {');
      expect(guard, greaterThan(0));
      expect(w.indexOf('return;', guard), lessThan(w.indexOf('_userNoShowCount++')),
          reason: '실패 분기가 노쇼 수 증가 · 성공 안내보다 먼저 끝난다');
    });

    test('②-3 통장사본: 결과를 모르는 실패는 지우지 않고 users 로 확인한다', () {
      final c = _code('lib/screens/common/document_management_screen.dart');
      expect(c.contains('if (_bankbookMarkDefinitelyFailed(e)) {'), isTrue);
      expect(c.contains('committed = userProvider.currentUser?.bankbookImagePath == newBankbookPath;'), isTrue);
      final set = c.substring(c.indexOf('static bool _bankbookMarkDefinitelyFailed'), c.indexOf('Future<void> _uploadBankbookImage()'));
      for (final unknown in ['deadline-exceeded', 'unavailable', 'internal', 'unknown', 'cancelled']) {
        expect(set.contains("'$unknown'"), isFalse, reason: '$unknown 은 결과를 모른다 — 지우면 안 된다');
      }
    });

    test('②-4 퇴근 실패 뒤에도 다시 읽는다(출근과 같다)', () {
      final c = _code('lib/screens/user/attendance_check_screen.dart');
      final i = c.indexOf("debugPrint('❌ 퇴근 체크 실패: \$e');");
      expect(i, greaterThan(0));
      final w = c.substring(i, i + 900);
      expect(w.contains('if (mounted) await _loadTodayWorks(quiet: true);'), isTrue);
    });

    test('②-2 퇴사 창: 이미 접수 · 결과 모름 · 서버 사유를 구분한다', () {
      final c = _code('lib/widgets/dialogs/long_term_work_management_dialog.dart');
      expect(c.contains("} on FirebaseFunctionsException catch (e) {"), isTrue);
      expect(c.contains("msg.contains('이미 진행 중인 퇴사 요청')"), isTrue);
      expect(c.contains("'deadline-exceeded', 'unavailable', 'internal', 'unknown', 'cancelled'"), isTrue);
    });
  });
}
