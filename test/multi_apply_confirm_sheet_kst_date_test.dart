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
import 'support/visible_text.dart'; // [DU255] keepWords 문구는 보이는 글자로 찾는다
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

  Future<ByteData?> handle(ByteData? message) async {
    final args = (const StandardMessageCodec().decodeMessage(message) as List)
        .first as Map;
    final name = args['functionName'] as String;
    final params =
        Map<String, dynamic>.from((args['parameters'] as Map?) ?? {});
    Object? reply;
    switch (name) {
      case 'callableGetMyApplications':
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

SlotModel _slot() => SlotModel(
      id: 'slot1',
      toId: 'to1',
      date: kStoredWorkDay,
      workDetails: const [_wd],
      status: SlotStatus.open,
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

Future<_Server> _open(WidgetTester tester, {_Server? with_}) async {
  final server = with_ ?? _Server();
  tester.binding.defaultBinaryMessenger
      .setMockMessageHandler(_channel, server.handle);
  addTearDown(() => tester.binding.defaultBinaryMessenger
      .setMockMessageHandler(_channel, null));

  tester.view.physicalSize = const Size(412, 1200);
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
                // production 과 같은 인자다 — 공고 상세가 이렇게 띄운다.
                onPressed: () => DialogHelper.showSheet<MultiApplyResult>(
                  inner,
                  useRootNavigator: true,
                  isScrollControlled: true,
                  builder: (_) => MultiApplyConfirmSheet(
                    items: [(slot: _slot(), work: _wd)],
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
  return server;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  setUpAll(() async => FirebasePlatform.instance = _FakeCore());

  final offset = kStoredWorkDay.timeZoneOffset;

  test('KD-0 이 실행의 기기 시간대 — 비-KST 면 local 성분이 하루 앞이다', () {
    // 반례가 살아 있는 실행인지 기록한다(TZ=GMT0 에서 10/19).
    if (offset != const Duration(hours: 9)) {
      expect(kStoredWorkDay.day, isNot(20),
          reason: 'offset $offset 에서 local 성분은 KST 날짜와 다르다');
    } else {
      expect(kStoredWorkDay.day, 20);
    }
  });

  testWidgets('KD-1 시트의 근무일은 KST 10월 20일(화)이다 (offset $offset)',
      (tester) async {
    await _open(tester);
    expect(find.byType(MultiApplyConfirmSheet), findsOneWidget);
    expect(find.textContaining('10월 20일(화)'), findsOneWidget,
        reason: '저장된 KST 근무일로 말해야 한다');
    expect(find.textContaining('10월 19일'), findsNothing,
        reason: '기기 시간대 성분(GMT 10/19)을 근무일로 말하면 안 된다');
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('KD-2 지원 payload 의 workDateMs 는 저장된 instant 그대로다',
      (tester) async {
    final server = await _open(tester);
    // 1건이면 CTA 는 `지원하기` 다(2건 이상만 `N개 업무 지원하기`).
    final cta = findVisibleText('지원하기');
    expect(cta, findsOneWidget, reason: '제출 버튼에 도달해야 한다');
    await tester.ensureVisible(cta);
    await tester.pump();
    await tester.tap(cta);
    await _settle(tester);

    expect(server.applyPayloads, hasLength(1),
        reason: '지원은 정확히 한 번 나간다');
    final p = server.applyPayloads.single;
    expect(p['workDateMs'],
        DateTime.utc(2026, 10, 19, 15).millisecondsSinceEpoch,
        reason: '표시만 고쳤다 — 보내는 근무일 instant 는 바뀌지 않는다');
    expect(p['slotId'], 'slot1');
    // 업무 식별자는 기존 그대로(WorkDetailModel.id) — 이 수정과 무관하다.
    expect(p['workDetailId'], _wd.id);
    await tester.pump(const Duration(seconds: 5));
  });

  // ── [SIM-ADJ-1] 일정 겹침 확인도 저장된 KST 근무일로 묻는다 ─────────
  //   예전 그룹 키 `DateTime(raw.year, raw.month, raw.day)` 는 기기 local
  //   성분이라 GMT 기기에서 10/20 지원을 **10/19** 확정 근무와 비교했다.
  testWidgets('KC-1 10/19 확정 근무와는 겹치지 않는다 (offset $offset)',
      (tester) async {
    final server = await _open(tester,
        with_: _Server(commitments: [_commitment('c19', DateTime(2026, 10, 19))]));
    expect(findVisibleText('지원 불가'), findsNothing,
        reason: '다른 날(10/19)의 근무와 겹친다고 말하면 안 된다');
    expect(findVisibleText('지원하기'), findsOneWidget,
        reason: '지원할 수 있어야 한다');
    expect(server.applyPayloads, isEmpty);
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('KC-2 실제 10/20 확정 근무와는 겹친다고 말한다 (offset $offset)',
      (tester) async {
    final server = await _open(tester,
        with_: _Server(commitments: [_commitment('c20', DateTime(2026, 10, 20))]));
    expect(find.textContaining('이미 확정된 근무와 시간이 겹쳐'), findsOneWidget,
        reason: '막힌 이유를 말해야 한다');
    expect(findVisibleText('지원 불가'), findsWidgets,
        reason: '같은 날 같은 시간의 확정 근무를 놓치면 안 된다');
    expect(findVisibleText('지원하기'), findsNothing,
        reason: '막힌 건은 제출 대상이 아니다');
    expect(server.applyPayloads, isEmpty);
    await tester.pump(const Duration(seconds: 5));
  });
}
