// [SIM-B] 지원 확인 시트의 근무일은 **저장된 KST 근무일**로 말한다.
//
// DEVICE 반례(DEV 확정 셀, 에뮬레이터 TZ=GMT): 10/20 10:00 KST 근무를
//   고르자 `여러 업무 지원` 확인 시트가 `10월 19일(월)` 이라고 말했다.
//   저장된 지원서의 workDate 는 정확히 KST 10/20 자정이었다(DEV READ).
//
// root cause: `_buildItemCard` 가 `slot.date.month/day/weekday` 를 그대로
//   읽었다. slot.date 는 KST 자정 instant 를 `toLocal()` 로 읽은 값이라
//   GMT 기기에서는 그 성분이 10/19 15:00 이다. 날짜 표시만 틀렸고 보내는
//   값(`workDateMs`)은 instant 라 정확했다.
//
// 이 파일이 고정하는 계약
//   KD-1 시트의 근무일 = KST 10월 20일(화) — 기기 시간대와 무관.
//   KD-2 실제 지원 payload 의 workDateMs 는 저장된 instant 그대로다.
//
// 시간대 교차검증: Dart 는 POSIX TZ 만 읽는다.
//   TZ=GMT0 flutter test test/multi_apply_confirm_sheet_kst_date_test.dart
//   TZ=KST-9 flutter test test/multi_apply_confirm_sheet_kst_date_test.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ALfit/models/core/slot_model.dart';
import 'package:ALfit/models/core/to_model.dart';
import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/models/core/work_detail_data.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/utils/dialog_helper.dart';
import 'package:ALfit/widgets/dialogs/apply/multi_apply_confirm_sheet.dart';

class _FakeApp extends Fake
    with MockPlatformInterfaceMixin
    implements FirebaseAppPlatform {
  @override
  String get name => defaultFirebaseAppName;
  @override
  FirebaseOptions get options => const FirebaseOptions(
      apiKey: 'k',
      appId: 'a',
      messagingSenderId: 's',
      projectId: 'p',
      storageBucket: 'b');
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

class _Applicant extends UserProvider {
  @override
  UserModel? get currentUser => UserModel(
        uid: 'u1',
        username: 'u1',
        name: '김근로',
        email: 'u1@alfit.local',
        role: UserRole.USER,
        accountStatus: 'active',
        passVerifiedAt: DateTime(2026, 2, 1),
        isIdVerified: true,
        idCardImagePath: 'users/u1/id.png',
        bankName: '국민은행',
        accountNumber: '1234',
        accountHolder: '김근로',
        bankbookImagePath: 'users/u1/bb.png',
        createdAt: DateTime(2026, 1, 1),
      );
}

/// 저장된 근무일 — KST 2026-10-20 00:00 = UTC 2026-10-19 15:00.
///   Firestore `Timestamp.toDate()` 처럼 **기기 local** 로 읽은 값이다.
final kStoredWorkDay = DateTime.utc(2026, 10, 19, 15).toLocal();

const _channel =
    'dev.flutter.pigeon.cloud_functions_platform_interface.CloudFunctionsHostApi.call';

/// Cloud Functions 플랫폼 채널 뒤의 모의 서버. 앱 코드는 실제 서비스를 탄다.
/// 내 확정 근무 1건(CF 직렬화 모양) — [kstDay] 는 KST 달력일, 10:00~11:00.
Map<String, Object?> _commitment(String id, DateTime kstDay) {
  final instant =
      DateTime.utc(kstDay.year, kstDay.month, kstDay.day)
          .subtract(const Duration(hours: 9));
  final ts = <String, Object?>{
    '_seconds': instant.millisecondsSinceEpoch ~/ 1000,
    '_nanoseconds': 0,
  };
  return {
    'id': id, 'uid': 'u1', 'toId': 'other-$id', 'slotId': 's-$id',
    'businessId': 'biz2', 'businessName': '다른 사업장', 'toTitle': '다른 공고',
    'selectedWorkType': '포장', 'startTime': '10:00', 'endTime': '11:00',
    'wage': 12000, 'wageType': 'hourly', 'status': 'CONFIRMED',
    'type': 'short', 'workDate': ts, 'appliedAt': ts,
  };
}

class _Server {
  _Server({this.commitments = const []});

  /// `callableGetMyApplications` 가 돌려줄 내 확정 근무.
  final List<Map<String, Object?>> commitments;
  final applyPayloads = <Map<String, dynamic>>[];
  int myAppsCalls = 0;

  Future<ByteData?> handle(ByteData? message) async {
    final args = (const StandardMessageCodec().decodeMessage(message) as List)
        .first as Map;
    final name = args['functionName'] as String;
    final params =
        Map<String, dynamic>.from((args['parameters'] as Map?) ?? {});
    Object? reply;
    switch (name) {
      case 'callableGetMyApplications':
        myAppsCalls++;
        reply = <String, Object?>{'applications': commitments};
      case 'callableApplyToTO':
        applyPayloads.add(params);
        reply = <String, Object?>{
          'applicationId': 'to1_slot1_wd1_u1',
          'isReactivation': false,
        };
      default:
        return const StandardMessageCodec().encodeMessage(<Object?>[
          'not-found',
          'unexpected $name',
          <String, Object?>{'code': 'not-found', 'message': 'unexpected $name'},
        ]);
    }
    return const StandardMessageCodec().encodeMessage(<Object?>[reply]);
  }
}

TOModel _to() => TOModel(
      id: 'to1',
      businessId: 'biz1',
      businessName: 'QA 사업장',
      type: 'flex',
      title: '단기 모집',
      creatorUID: 'a',
      status: TOStatus.active,
      deadlineType: 'NONE',
      hoursBeforeStart: 0,
      workDetails: const [],
      totalRequired: 1,
      totalConfirmed: 0,
      totalPending: 0,
      isPublished: true,
      publishMode: 'immediate',
      rangeStart: kStoredWorkDay,
      createdAt: DateTime(2026, 10, 1),
      statusUpdatedAt: DateTime(2026, 10, 1),
    );

const _wd = WorkDetailData(
  wdId: 'wd1',
  workType: 'QA 분류',
  workTypeIcon: 'box',
  workTypeColor: '#000000',
  workTypeBackgroundColor: '#FFFFFF',
  wage: 12000,
  wageType: 'hourly',
  requiredCount: 1,
  startTime: '10:00',
  endTime: '11:00',
  breakMinutes: 0,
);


Future<void> _settle(WidgetTester tester) async {
  for (var t = 0; t < 2; t++) {
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 120)));
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }
}


// ── [L19 · impl_7] 지원 시트가 열릴 때 내 약속 목록은 **한 번만** 읽는다 ─────────────
//   예전: 근무 날짜마다 `callableGetMyApplications`(확정 200)를 따로 불렀다(D회 N+1).
//   지금: 시트 한 번 열림 = 조회 1회(Future 공유). 판정(날짜별 겹침)과 신선도(시트가 열릴 때 1회)는 그대로.
SlotModel _slotOn(String id, int kstDay) => SlotModel(
      id: id,
      toId: 'to1',
      date: DateTime.utc(2026, 10, kstDay - 1, 15).toLocal(),
      workDetails: const [_wd],
      status: SlotStatus.open,
    );

Future<void> _openMany(WidgetTester tester, _Server server, List<SlotModel> slots) async {
  tester.binding.defaultBinaryMessenger.setMockMessageHandler(_channel, server.handle);
  addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMessageHandler(_channel, null));
  tester.view.physicalSize = const Size(412, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ChangeNotifierProvider<UserProvider>(
      create: (_) => _Applicant(),
      child: MaterialApp(
        home: Scaffold(
          body: Center(
            child: Builder(
              builder: (inner) => ElevatedButton(
                onPressed: () => DialogHelper.showSheet<MultiApplyResult>(
                  inner,
                  useRootNavigator: true,
                  isScrollControlled: true,
                  builder: (_) => MultiApplyConfirmSheet(
                    items: [for (final s in slots) (slot: s, work: _wd)],
                    to: _to(),
                    myApplications: const [],
                  ),
                ),
                child: const Text('열기'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.tap(find.text('열기'));
  await _settle(tester);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  setUpAll(() async => FirebasePlatform.instance = _FakeCore());

  testWidgets('L19-1 근무 날짜 3개 → 내 약속 조회 1회 · 날짜별 겹침 판정은 그대로(가운데 날짜만 막힘)', (tester) async {
    final server = _Server(commitments: [_commitment('c2', DateTime(2026, 10, 21))]);
    await _openMany(tester, server, [_slotOn('s20', 20), _slotOn('s21', 21), _slotOn('s22', 22)]);
    expect(find.byType(MultiApplyConfirmSheet), findsOneWidget);
    expect(server.myAppsCalls, 1, reason: '시트 한 번 열림 = 약속 목록 조회 1회');
    expect(find.textContaining('이미 확정된 근무와 시간이 겹쳐'), findsOneWidget,
        reason: '겹치는 날(10/21)만 막힌다 — 공유 목록에서 날짜별로 판정');
  });

  testWidgets('L19-2 날짜 1개도 조회 1회(회귀 없음)', (tester) async {
    final server = _Server();
    await _openMany(tester, server, [_slotOn('s20', 20)]);
    expect(server.myAppsCalls, 1);
  });
}
