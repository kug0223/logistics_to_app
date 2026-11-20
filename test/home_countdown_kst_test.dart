// [E1-TZ] 근무 시각 안내는 기기 시간대가 아니라 canonical KST 를 따른다.
//
// ── 에뮬레이터에서 본 것 ──────────────────────────────────────────────
//   기기 TZ=GMT(12:26) · KST 21:26. 10:00~11:00 근무의 Home 카운트다운이
//   KST 기준 근무 시각과 약 9시간 어긋났다.
//
// ── 원인 ──────────────────────────────────────────────────────────────
//   `startTime`/`endTime` 은 **KST 벽시계 문자열**인데, 이것을
//   `DateTime(now.year, now.month, now.day)` 즉 **기기 local 자정**에
//   더했다. KST 기기에서는 우연히 맞고, 그 밖에서는 기기 offset 만큼
//   통째로 어긋난다. 날짜도 '오늘' 을 썼지 그 근무의 KST 날짜가 아니었다.
//
// ── 고친 것 ───────────────────────────────────────────────────────────
//   `FormatHelper.kstWallClockInstant(kstDayKey, 'HH:MM')` — 그 날의 KST
//   자정 instant(`kstMidnightOfKstDay`)에서 출발하는 canonical 변환 하나.
//   화면마다 식을 다시 적지 않는다.
//
// ── 이 파일을 두 시간대에서 돌린다 ────────────────────────────────────
//   `flutter test` (개발 기기 = KST) 와 `TZ=UTC flutter test` 둘 다
//   통과해야 한다. 수정 전 코드는 TZ=UTC 에서 실패한다(실측).
//   Dart 는 IANA 이름을 무시하고 POSIX TZ 만 읽는다 — `TZ=UTC` 로 offset 이
//   0 이 되는 것을 확인했다(`timeZoneName` 은 캐시된 옛 이름이 남는다).
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ALfit/models/core/application_model.dart';
import 'package:ALfit/models/core/attendance_model.dart';
import 'package:ALfit/models/core/id_card_access_request_model.dart';
import 'package:ALfit/models/core/renewal_proposal_model.dart';
import 'package:ALfit/models/core/slot_model.dart';
import 'package:ALfit/models/core/to_model.dart';
import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/models/core/user_region.dart';
import 'package:ALfit/providers/notification_provider.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/screens/user/user_home_reads.dart';
import 'package:ALfit/screens/user/user_home_screen.dart';
import 'package:ALfit/screens/user/user_tab_scope.dart';
import 'package:ALfit/services/payroll_correction_service.dart';
import 'support/checkin_contract_fixture.dart';
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

class _Worker extends UserProvider {
  @override
  UserModel? get currentUser => UserModel(
        uid: _kUid,
        username: _kUid,
        name: 'QA 지원자',
        email: '$_kUid@alfit.local',
        role: UserRole.USER,
        homeRegion: const UserRegion(province: '경기도', city: '평택시'),
        accountStatus: 'active',
        createdAt: DateTime(2026, 1, 1),
      );
}

/// KST 달력일 키. 기기 TZ 와 무관한 `DateTime.utc(y, m, d)`.
DateTime _kstDay(int y, int m, int d) => DateTime.utc(y, m, d);

ApplicationModel _app({
  required DateTime workDate,
  String start = '10:00',
  String end = '11:00',
}) =>
    ApplicationModel(
      id: 'app-1',
      uid: _kUid,
      businessId: 'biz1',
      businessName: 'QA 사업장',
      toId: 'to1',
      toTitle: 'QA 공고',
      selectedWorkType: 'QA 분류',
      startTime: start,
      endTime: end,
      workDate: workDate,
      status: AppStatus.confirmed,
      appliedAt: workDate.subtract(const Duration(days: 2)),
      wage: 53000,
      wageType: 'daily',
    );

AttendanceModel _att({
  required DateTime workDate,
  DateTime? checkIn,
  DateTime? checkOut,
}) =>
    AttendanceModel(
      id: 'att-1',
      applicationId: 'app-1',
      userId: _kUid,
      businessId: 'biz1',
      businessName: 'QA 사업장',
      workDate: workDate,
      workType: 'QA 분류',
      checkInAt: checkIn,
      checkOutAt: checkOut,
      status: AttendanceModel.statusPresent,
      createdAt: workDate,
    );

UserHomeReads _reads(
  List<ApplicationModel> apps, {
  List<AttendanceModel> attendances = const [],
}) =>
    UserHomeReads(
      // [CONTRACT-DISPATCH-B4] 홈 CTA 는 계약 동의 판정을 함께 본다 — 이 시험의 전제: 오늘 근무 계약은 양측 서명 완료
      myContracts: (uid) async => completedContractsFor(apps),
      myApplications: (uid) async => apps,
      myMonthlyAttendances: (
              {required String userId,
              required int year,
              required int month}) async =>
          attendances,
      publishedTOs: () async => const <TOModel>[],
      pendingIdCardRequests: (uid) async => const <IdCardAccessRequestModel>[],
      myRenewalProposals: () async => const <RenewalProposalModel>[],
      businessById: (id) async => null,
      slotsForTO: (toId) async => const <SlotModel>[],
      invalidatePublishedTOsCache: () {},
      documentCorrections: () async => DocumentCorrectionSurface.empty,
    );

Future<void> _pump(
  WidgetTester t, {
  required DateTime clock,
  required UserHomeReads reads,
}) async {
  t.view.physicalSize = const Size(390, 2400);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<UserProvider>(create: (_) => _Worker()),
        ChangeNotifierProvider<NotificationProvider>(
            create: (_) => NotificationProvider()),
      ],
      child: MaterialApp(
        home: UserTabScope(
          switchToTab: (_) {},
          switchToTabWithDate: (_, __) {},
          pendingJobDate: null,
          clearPendingJobDate: () {},
          pendingScheduleMonth: null,
          clearPendingScheduleMonth: () {},
          switchToScheduleNow: () {},
          child: UserHomeScreen(reads: reads, clock: () => clock),
        ),
      ),
    ),
  );
  await t.pumpAndSettle(const Duration(seconds: 3));
}

String _shown(WidgetTester t) => t
    .widgetList<Text>(find.byType(Text))
    .map((w) => w.data ?? '')
    .where((s) => s.isNotEmpty)
    .join('\n');

void main() {
  // 투어 코치마크가 Home 을 통째로 가리면 모든 단정이 거짓으로 통과한다.
  setUp(() => SharedPreferences.setMockInitialValues(
      {'tour_completed_user_home': true}));
  setUpAll(() async {
    initializeDateFormatting('ko');
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
  });

  group('[TZ-A] canonical 변환 — 기기 시간대와 무관한 절대 시각', () {
    test('TZ-1 KST 10:00 은 UTC 01:00 이다', () {
      final i = FormatHelper.kstWallClockInstant(_kstDay(2026, 10, 13), '10:00');
      expect(i, isNotNull);
      expect(i!.toUtc().toIso8601String(), '2026-10-13T01:00:00.000Z');
    });

    test('TZ-2 기기 local 자정 방식과 다르다 — 그 차이가 이번 결함이었다', () {
      final canonical =
          FormatHelper.kstWallClockInstant(_kstDay(2026, 10, 13), '10:00')!;
      // 예전 방식: 기기 local 자정 + 10시간.
      final deviceLocal =
          DateTime(2026, 10, 13).add(const Duration(hours: 10));
      final gap = canonical.difference(deviceLocal);
      // KST 기기에서는 0, 그 밖에서는 기기 offset 만큼 벌어진다.
      final expected =
          DateTime(2026, 10, 13).timeZoneOffset - const Duration(hours: 9);
      expect(gap, expected,
          reason: '예전 방식의 오차는 정확히 (기기 offset - 9시간) 이다');
    });

    test('TZ-3 KST 00:30 은 UTC 로 전날이다', () {
      final i = FormatHelper.kstWallClockInstant(_kstDay(2026, 10, 13), '00:30');
      expect(i!.toUtc().toIso8601String(), '2026-10-12T15:30:00.000Z');
    });

    test('TZ-4 KST 자정은 그 날 00:00 이다', () {
      final i = FormatHelper.kstWallClockInstant(_kstDay(2026, 10, 13), '00:00');
      expect(i, FormatHelper.kstMidnightOfKstDay(_kstDay(2026, 10, 13)),
          reason: '기존 helper 와 같은 자를 쓴다');
    });

    test('TZ-5 형식이 어긋나면 null — 숫자를 지어내지 않는다', () {
      final day = _kstDay(2026, 10, 13);
      expect(FormatHelper.kstWallClockInstant(day, '24:00'), isNull);
      expect(FormatHelper.kstWallClockInstant(day, '10'), isNull);
      expect(FormatHelper.kstWallClockInstant(day, 'abc'), isNull);
      expect(FormatHelper.kstWallClockInstant(day, ''), isNull);
      expect(FormatHelper.kstWallClockInstant(day, '10:99'), isNull);
    });

    test('TZ-6 같은 날짜 키는 어느 시간대에서도 같은 instant 를 준다', () {
      // `toKstDate` 는 실제 시각을 KST 달력일로, `kstDayKeyOfCivil` 은 달력
      //   성분을 키로 바꾼다 — 둘 다 같은 키를 주면 결과도 같아야 한다.
      final a = FormatHelper.kstWallClockInstant(
          FormatHelper.toKstDate(DateTime.utc(2026, 10, 13, 5)), '10:00');
      final b = FormatHelper.kstWallClockInstant(
          FormatHelper.kstDayKeyOfCivil(DateTime(2026, 10, 13)), '10:00');
      expect(a, b);
    });
  });

  group('[TZ-B] Home 카운트다운이 KST 근무 시각을 따른다', () {
    // 근무: 2026-10-13 KST 10:00~11:00. 시계는 **절대 시각**으로 준다.
    final workDay = _kstDay(2026, 10, 13);

    testWidgets('TZ-7 출근 30분 전 (KST 09:30 = UTC 00:30)', (t) async {
      await _pump(t,
          clock: DateTime.utc(2026, 10, 13, 0, 30),
          reads: _reads([_app(workDate: workDay)]));
      expect(_shown(t).contains('출근까지 30분'), isTrue,
          reason: '기기 시간대와 무관하게 KST 근무 시각까지 30분이다');
      expect(_shown(t).contains('출근까지 9시간'), isFalse);
    });

    testWidgets('TZ-8 근무 중 (KST 10:30 = UTC 01:30) — 퇴근까지 30분', (t) async {
      await _pump(t,
          clock: DateTime.utc(2026, 10, 13, 1, 30),
          reads: _reads(
            [_app(workDate: workDay)],
            attendances: [
              _att(
                  workDate: workDay,
                  checkIn: DateTime.utc(2026, 10, 13, 1, 2)),
            ],
          ));
      expect(_shown(t).contains('퇴근까지 30분'), isTrue);
    });

    testWidgets('TZ-9 심야 근무 23:00~01:00 은 종료가 다음 날이다', (t) async {
      // KST 23:30(= UTC 14:30)이면 아직 근무 중이다. 예전 식은 종료를
      //   같은 날 01:00 으로 봐서 이미 끝난 것으로 읽었다.
      await _pump(t,
          clock: DateTime.utc(2026, 10, 13, 14, 30),
          reads: _reads(
            [_app(workDate: workDay, start: '23:00', end: '01:00')],
            attendances: [
              _att(
                  workDate: workDay,
                  checkIn: DateTime.utc(2026, 10, 13, 14, 2)),
            ],
          ));
      expect(_shown(t).contains('퇴근까지'), isTrue,
          reason: '자정을 넘기는 근무가 시작하자마자 끝난 것으로 보이면 안 된다');
      expect(_shown(t).contains('퇴근 기록이 필요해요'), isFalse);
    });

    testWidgets('TZ-10 KST 자정 직후 근무(00:30) — UTC 로 전날이어도 오늘 근무다',
        (t) async {
      await _pump(t,
          clock: DateTime.utc(2026, 10, 12, 15, 10), // KST 10-13 00:10
          reads: _reads(
              [_app(workDate: workDay, start: '00:30', end: '01:30')]));
      expect(_shown(t).contains('출근까지 20분'), isTrue);
    });
  });

  group('[TZ-C] 계산식을 화면에 다시 적지 않는다', () {
    test('TZ-11 Home 은 기기 local 자정으로 근무 시각을 만들지 않는다', () {
      final src = File('lib/screens/user/user_home_screen.dart')
          .readAsStringSync()
          .replaceAll('\r\n', '\n');
      expect(src.contains('DateTime(now.year, now.month, now.day)'), isFalse,
          reason: '기기 local 자정 + KST 벽시계 조합이 이번 결함이었다');
      expect(src.contains('kstWallClockInstant'), isTrue,
          reason: 'canonical 변환 하나를 쓴다');
    });
  });
}
