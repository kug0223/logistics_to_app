// ignore_for_file: depend_on_referenced_packages
// [ISG2] 초대 수락 **마감**을 지원자에게 정확히 말한다.
//
// ── 무엇이 틀려 있었나 ────────────────────────────────────────────────
//   서버 계약은 `min(초대 + 24시간, 근무 시작)` 인데, 화면은 저장된
//   `inviteExpiresAt` 을 그대로 읽었다. 그래서 그 계약 **이전에 만들어진**
//   기록에서 근무가 끝난 다음 날까지 수락 가능한 것처럼 보였다.
//   DEV 실측 1건: 근무 2026-10-15 20:00~22:00 / 저장 만료 10-16 10:09.
//
//   홈 배너는 반대 방향으로 틀렸다 — `근무 시작 전까지` 라고만 해서
//   근무가 다음 주면 24시간이 **먼저** 끝난다는 것을 숨겼다.
//
// ── 이 테스트가 보는 것 ───────────────────────────────────────────────
//   IDL-A  식(`effectiveInviteDeadlineOf`) — 실제 계산
//   IDL-B  분류(`isLongTermInvite`) — slotId 가 있으면 단기
//   IDL-C  실제 `MyApplicationsScreen` 을 띄워 카드 문구·버튼 상태
//   IDL-D  홈 배너 문구가 한쪽만 말하지 않는다

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';

import 'package:ALfit/models/core/application_model.dart';
import 'package:ALfit/models/ui/invite_capacity_state.dart';
import 'package:ALfit/models/ui/invite_accept_readiness.dart';
import 'package:ALfit/models/core/attendance_model.dart';
import 'package:ALfit/models/core/employment_contract_model.dart';
import 'package:ALfit/models/core/to_model.dart';
import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/models/core/user_region.dart';
import 'package:ALfit/providers/notification_provider.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/screens/user/my_applications_reads.dart';
import 'package:ALfit/screens/user/my_applications_screen.dart';
import 'package:ALfit/services/tax_identity_service.dart';
import 'package:ALfit/utils/format_helper.dart';

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

const _kUid = 'u1';

class _P extends UserProvider {
  @override
  UserModel? get currentUser => UserModel(
        uid: _kUid,
        username: _kUid,
        name: 'QA 지원자',
        email: '$_kUid@alfit.local',
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

// ── DEV 실측값을 그대로 쓴다 ──────────────────────────────────────────
//   근무일 2026-10-15(KST), 20:00~22:00, 저장 만료 10-16 10:09.
final DateTime _workDayKst = FormatHelper.toKstDate(DateTime.utc(2026, 10, 15));
final DateTime _shiftStart =
    FormatHelper.kstWallClockInstant(_workDayKst, '20:00')!;
final DateTime _storedExpiryAfterShift =
    FormatHelper.kstWallClockInstant(_workDayKst, '22:00')!
        .add(const Duration(hours: 12, minutes: 9));

ApplicationModel _invite({
  String id = 'inv1',
  DateTime? expiry,
  DateTime? workDate,
  String startTime = '20:00',
  String? slotId = 'slot1',
  List<String>? workDays,
  DateTime? workEndDate,
}) =>
    ApplicationModel(
      id: id,
      toId: 'to1',
      slotId: slotId,
      wdId: 'wd-B',
      uid: _kUid,
      businessId: 'biz1',
      businessName: 'QA 사업장',
      toTitle: 'QA 공고',
      status: AppStatus.invited,
      selectedWorkType: 'QA 분류',
      startTime: startTime,
      endTime: '22:00',
      wage: 53000,
      workDate: workDate ?? _workDayKst,
      workDays: workDays,
      workEndDate: workEndDate,
      appliedAt: _workDayKst.subtract(const Duration(days: 1)),
      inviteExpiresAt: expiry,
      // 자리 상태가 unknown 이면 카드는 수락 UI 대신 `확인하지 못했어요`를
      //   보여 준다(별도 계약, 이번 변경과 무관). 마감 표시를 보려면
      //   자리가 있다고 확인된 상태여야 한다.
      workInstanceCapacityState: InviteCapacityState.available,
      // [INVITE-PARITY] 마감 표시를 보는 테스트 — 수락 가능한 초대로 둔다.
      inviteAcceptReadiness: InviteAcceptReadiness.ready,
    );

TOModel _to() => TOModel(
      id: 'to1',
      businessId: 'biz1',
      businessName: 'QA 사업장',
      type: 'flex',
      title: 'QA 공고',
      creatorUID: 'admin1',
      status: TOStatus.active,
      deadlineType: 'NONE',
      hoursBeforeStart: 0,
      workDetails: const [],
      totalRequired: 3,
      totalConfirmed: 0,
      totalPending: 0,
      isPublished: true,
      publishMode: 'immediate',
      createdAt: _workDayKst.subtract(const Duration(days: 10)),
      statusUpdatedAt: _workDayKst.subtract(const Duration(days: 10)),
    );

MyApplicationsReads _reads(List<ApplicationModel> apps) => MyApplicationsReads(
      myApplicationsPaged: (
              {required String uid,
              required int pageSize,
              String? startAfterDocId}) async =>
          {'items': apps, 'lastDocId': null, 'hasMore': false},
      toOrFailure: (id) async => (to: _to(), failed: false),
      contractsByWorker: (uid) async => const <EmploymentContractModel>[],
      autoExpirePending: (uid) async {},
      monthlyAttendances: (
              {required String userId,
              required int year,
              required int month}) async =>
          const <AttendanceModel>[],
      reviewById: (key) async => null,
      taxStatus: () async => const TaxIdentityStatus.unknown(),
    );

Future<void> _pump(
    WidgetTester t, List<ApplicationModel> apps, DateTime clock) async {
  t.view.physicalSize = const Size(390, 2400);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(const SizedBox.shrink());
  await t.pump(const Duration(milliseconds: 50));
  await t.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<UserProvider>(create: (_) => _P()),
        ChangeNotifierProvider<NotificationProvider>(
            create: (_) => NotificationProvider()),
      ],
      child: MaterialApp(
        home: MyApplicationsScreen(
          reads: _reads(apps),
          clock: () => clock,
          initialTabIndex: 6, // 구 인덱스 6 = 초대 그룹
        ),
      ),
    ),
  );
  for (var i = 0; i < 25; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

List<String> _texts(WidgetTester t) => t
    .widgetList<Text>(find.byWidgetPredicate((w) => w is Text))
    .map((w) => w.data ?? '')
    .where((s) => s.isNotEmpty)
    .toList();

/// `수락하기` 라벨을 품은 가장 가까운 GestureDetector 의 onTap.
VoidCallback? _acceptOnTap(WidgetTester t) {
  final label = find.text('수락하기');
  if (label.evaluate().isEmpty) return null;
  final gd = find.ancestor(of: label, matching: find.byType(GestureDetector));
  if (gd.evaluate().isEmpty) return null;
  return t.widget<GestureDetector>(gd.first).onTap;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
    await initializeDateFormatting('ko_KR', null);
    // 폰트: 번들 NotoSansKR 로 실제 폭을 쓴다(테스트 기본 폰트는 더 넓다).
    final f = File('assets/fonts/NotoSansKR-Regular.ttf');
    if (f.existsSync()) {
      final loader = FontLoader('NotoSansKR')..addFont(f.readAsBytes().then(
          (b) => ByteData.view(b.buffer)));
      await loader.load();
    }
  });

  group('IDL-A 마감 식', () {
    test('IDL-01 저장 만료가 근무 뒤면 근무 시작이 마감이다', () {
      final d = effectiveInviteDeadlineOf(
        storedExpiry: _storedExpiryAfterShift,
        shiftStart: _shiftStart,
        isLongTerm: false,
      );
      expect(d, _shiftStart);
    });

    test('IDL-02 저장 만료가 근무보다 이르면 저장 만료가 마감이다', () {
      final early = _shiftStart.subtract(const Duration(hours: 5));
      final d = effectiveInviteDeadlineOf(
        storedExpiry: early,
        shiftStart: _shiftStart,
        isLongTerm: false,
      );
      expect(d, early, reason: '24시간이 먼저 끝나는 경우를 숨기지 않는다');
    });

    test('IDL-03 장기 초대는 좁히지 않는다', () {
      final d = effectiveInviteDeadlineOf(
        storedExpiry: _storedExpiryAfterShift,
        shiftStart: _shiftStart,
        isLongTerm: true,
      );
      expect(d, _storedExpiryAfterShift);
    });

    test('IDL-04 모르면 null — 모름을 마감으로 바꾸지 않는다', () {
      expect(
          effectiveInviteDeadlineOf(
              storedExpiry: null, shiftStart: null, isLongTerm: false),
          isNull);
      expect(
          effectiveInviteDeadlineOf(
              storedExpiry: null, shiftStart: _shiftStart, isLongTerm: false),
          _shiftStart);
      expect(
          effectiveInviteDeadlineOf(
              storedExpiry: _storedExpiryAfterShift,
              shiftStart: null,
              isLongTerm: false),
          _storedExpiryAfterShift);
    });
  });

  group('IDL-B 분류 — 서버 srvIsLongTermInvite 와 같은 식', () {
    test('IDL-05 slotId 가 있으면 workDays 가 있어도 단기다', () {
      final a = _invite(workDays: const ['월', '화']);
      expect(a.isLongTermInvite, isFalse);
      // 기존 getter 는 slotId 를 보지 않아 장기로 읽는다 — 그래서 분리했다.
      expect(a.isLongTermApplication, isTrue);
    });

    test('IDL-06 slot 없고 workDays 있으면 장기', () {
      expect(_invite(slotId: null, workDays: const ['월']).isLongTermInvite,
          isTrue);
    });

    test('IDL-07 slot 없고 단서 없으면 단기', () {
      expect(_invite(slotId: null).isLongTermInvite, isFalse);
    });

    test('IDL-08 근무 시작 instant 는 KST 벽시계로 계산된다', () {
      expect(_invite().shiftStartInstant, _shiftStart);
    });

    test('IDL-09 모델 getter 가 식과 같은 답을 준다', () {
      expect(_invite(expiry: _storedExpiryAfterShift).effectiveInviteDeadline,
          _shiftStart);
    });
  });

  group('IDL-C 실제 화면 — 초대 카드', () {
    testWidgets('IDL-10 저장 만료가 근무 뒤여도 카드는 근무 시작을 말한다',
        (t) async {
      await _pump(t, [_invite(expiry: _storedExpiryAfterShift)],
          _shiftStart.subtract(const Duration(hours: 2)));
      final texts = _texts(t);
      expect(texts, contains('~10.15 20:00 만료'));
      expect(texts.any((s) => s.contains('10.16')), isFalse,
          reason: '저장된 다음 날 만료를 그대로 보여 주면 안 된다');
    });

    testWidgets('IDL-11 마감 전에는 수락 버튼이 살아 있다', (t) async {
      await _pump(t, [_invite(expiry: _storedExpiryAfterShift)],
          _shiftStart.subtract(const Duration(minutes: 1)));
      expect(_acceptOnTap(t), isNotNull);
      expect(_texts(t).any((s) => s.contains('수락 기한이 지났어요')), isFalse);
    });

    testWidgets('IDL-12 근무 시작 뒤에는 기한 경과를 말하고 버튼을 막는다',
        (t) async {
      await _pump(t, [_invite(expiry: _storedExpiryAfterShift)],
          _shiftStart.add(const Duration(minutes: 1)));
      expect(_texts(t).any((s) => s.startsWith('수락 기한이 지났어요')), isTrue,
          reason: '서버가 거절할 버튼을 그대로 두지 않는다');
      expect(_acceptOnTap(t), isNull);
    });

    testWidgets('IDL-13 24시간이 먼저 끝나는 초대는 그 시각을 말한다', (t) async {
      // 근무는 멀고(같은 20:00) 저장 만료가 이른 경우.
      final early = _shiftStart.subtract(const Duration(hours: 6));
      await _pump(t, [_invite(expiry: early)],
          early.subtract(const Duration(hours: 1)));
      expect(_texts(t), contains('~10.15 14:00 만료'));
    });

    testWidgets('IDL-14 초대 카드는 390dp 폭에서 넘치지 않는다', (t) async {
      await _pump(t, [_invite(expiry: _storedExpiryAfterShift)],
          _shiftStart.add(const Duration(minutes: 1)));
      expect(testerHasOverflow(), isFalse);
    });

    testWidgets('IDL-15 마감 표기는 기기 시간대에 흔들리지 않는다', (t) async {
      // 표기는 KST 고정이어야 한다. `DateFormat.format` 을 직접 쓰면 이
      //   값이 UTC 성분(11:00)으로 찍혔다 — 실제로 그렇게 났었다.
      expect(FormatHelper.formatKstMonthDayTime(_shiftStart), '10.15 20:00');
      expect(
          FormatHelper.formatKstMonthDayTime(_shiftStart.toLocal()),
          '10.15 20:00');
      expect(
          FormatHelper.formatKstMonthDayTime(_shiftStart,
              dateSeparator: '/'),
          '10/15 20:00');
    });
  });

  group('IDL-D 홈 배너 문구', () {
    // 배너는 건별 시각을 모른다(초대 개수만 안다). 그래서 **규칙**을
    //   말해야 하고, 한쪽 경계만 말하면 다른 쪽이 먼저 끝나는 경우를 숨긴다.
    final src =
        File('lib/screens/user/user_home_screen.dart').readAsStringSync();

    test('IDL-16 두 경계를 함께 말한다', () {
      expect(src.contains('초대 후 24시간과 근무 시작 중 빠른 때까지 수락할 수 있어요'),
          isTrue);
    });

    test('IDL-17 한쪽만 말하던 옛 문구는 남아 있지 않다', () {
      expect(src.contains('24시간 내 수락하지 않으면 자동 만료됩니다'), isFalse);
      expect(src.contains('근무 시작 전까지 수락하지 않으면 자동 만료됩니다'), isFalse);
    });
  });
}

/// 렌더 중 오버플로가 있었는가 — FlutterError 수집 대신 예외 기록을 본다.
bool testerHasOverflow() {
  final e = TestWidgetsFlutterBinding.instance.takeException();
  if (e == null) return false;
  return e.toString().contains('overflowed');
}
