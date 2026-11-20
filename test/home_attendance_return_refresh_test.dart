// [ATTENDANCE-SCREEN-REFRESH] 홈 → 출퇴근 화면 → 복귀 시 Hero 가 새 근태로 다시 그려지는가.
//   DEVICE 10/20 12:37: 출근 성공 뒤 홈 복귀에도 '출근까지 32분 · 출근하기' 가 남았다(앱 복귀·새로고침 전까지).
//   하네스는 user_home_attendance_cta_test 와 같다(실제 UserHomeScreen + 읽기 주입). 서버 쓰기 없음.

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
import 'package:ALfit/screens/user/attendance_check_screen.dart';
import 'package:ALfit/screens/user/user_home_reads.dart';
import 'package:ALfit/screens/user/user_home_screen.dart';
import 'package:ALfit/screens/user/user_tab_scope.dart';
import 'package:ALfit/services/payroll_correction_service.dart';
import 'support/checkin_contract_fixture.dart';
import 'package:ALfit/utils/format_helper.dart';

// ── Firebase 가짜 코어 ──────────────────────────────────────────────────
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

// ── 고정 시계 ───────────────────────────────────────────────────────────
//   기기에서 본 그 근무: 10:00 ~ 11:00. 시각만 바꿔 네 구간을 만든다.
//   TZ 가정을 하지 않는다 — 근무일은 이 시계에서 `toKstDate` 로 역산한다.
/// KST 벽시계 h:m 에 해당하는 **절대 시각**.
///    로 쓰면 기기 시간대에 따라 다른 순간이 되고,
///   Home 이 canonical KST 로 계산하므로 TZ=UTC 에서 어긋난다.
DateTime _clockAt(int hour, int minute) =>
    DateTime.utc(2026, 10, 13, hour, minute)
        .subtract(const Duration(hours: 9));

DateTime _workDateFor(DateTime clock) => FormatHelper.toKstDate(clock);

const _kAppId = 'app-today';

ApplicationModel _confirmedToday(DateTime clock) => ApplicationModel(
      id: _kAppId,
      uid: _kUid,
      businessId: 'biz1',
      businessName: 'QA 사업장',
      toId: 'to1',
      toTitle: 'QA 공고',
      selectedWorkType: 'QA 분류',
      startTime: '10:00',
      endTime: '11:00',
      workDate: _workDateFor(clock),
      status: AppStatus.confirmed,
      appliedAt: _workDateFor(clock).subtract(const Duration(days: 2)),
      wage: 53000,
      wageType: 'daily',
    );

/// 근태 fixture. 기본은 "그 지원서 · 그 사용자 · 오늘".
AttendanceModel _att(
  DateTime clock, {
  String status = AttendanceModel.statusPresent,
  DateTime? checkIn,
  DateTime? checkOut,
  String applicationId = _kAppId,
  String userId = _kUid,
  DateTime? workDate,
}) =>
    AttendanceModel(
      id: 'att-1',
      applicationId: applicationId,
      userId: userId,
      businessId: 'biz1',
      businessName: 'QA 사업장',
      workDate: workDate ?? _workDateFor(clock),
      workType: 'QA 분류',
      checkInAt: checkIn,
      checkOutAt: checkOut,
      status: status,
      createdAt: _workDateFor(clock),
    );

Future<void> _pumpHome(
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
      // `UserTabScope` 없이 그리면 섹션이 통째로 빠져 부정 단정이
      //   거짓으로 통과한다.
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

List<String> _texts(WidgetTester t) => t
    .widgetList<Text>(find.byType(Text))
    .map((w) => w.data ?? '')
    .where((s) => s.isNotEmpty)
    .toList();

String _shown(WidgetTester t) => _texts(t).join('\n');

bool _hasText(WidgetTester t, String s) => _texts(t).contains(s);

/// Hero 의 진행 바 — Home 에서 유일한 `LinearProgressIndicator` 다.
Finder _bar() => find.byType(LinearProgressIndicator);

/// Hero 진행 상자 안의 라벨. 진행 바와 **같은 Column** 의 첫 Text 다.
///
///   전체 화면 문자열로 검사하면 안 된다 — `근무 완료` 는 수입 섹션의
///   금액 라벨에도 쓰이는 말이라, Hero 가 멀쩡해도 단정이 걸린다(실측).
///   이 Phase 가 보는 것은 **Hero 가 무엇을 주장하는가** 하나다.
String? _progressLabel(WidgetTester t) {
  if (_bar().evaluate().isEmpty) return null;
  final col = find.ancestor(of: _bar().first, matching: find.byType(Column));
  final texts = t.widgetList<Text>(
      find.descendant(of: col.first, matching: find.byType(Text)));
  return texts.isEmpty ? null : texts.first.data;
}

/// Hero CTA 버튼. `ElevatedButton.icon` 은 비공개 서브클래스를 만들어
///   `find.byType(ElevatedButton)` 에 **잡히지 않는다**(런타임 타입 정확 비교).
Finder _cta() => find.byWidgetPredicate((w) => w is ElevatedButton);

// 목적지 화면과 같은 문구만 쓴다 — 새 상태 이름을 만들지 않는다.
const _kDone = '출퇴근 완료';
const _kCheckIn = '출근하기';
const _kCheckOut = '퇴근하기';

/// 서버 상태를 바꿀 수 있는 읽기 — 출퇴근 화면에서 일어난 일을 흉내낸다.
class _Ledger {
  _Ledger(this.apps);
  final List<ApplicationModel> apps;
  List<AttendanceModel> attendances = const [];
  bool fail = false;
  int reads = 0;
  UserHomeReads get reads0 => UserHomeReads(
        // [CONTRACT-DISPATCH-B4] 홈 CTA 는 계약 동의 판정을 함께 본다 — 이 시험의 전제: 오늘 근무 계약은 양측 서명 완료
        myContracts: (uid) async => completedContractsFor(apps),
        myApplications: (uid) async => apps,
        myMonthlyAttendances: ({required String userId, required int year, required int month}) async {
          reads++;
          if (fail) throw StateError('근태 조회 실패(테스트)');
          return attendances;
        },
        publishedTOs: () async => const <TOModel>[],
        pendingIdCardRequests: (uid) async => const <IdCardAccessRequestModel>[],
        myRenewalProposals: () async => const <RenewalProposalModel>[],
        businessById: (id) async => null,
        slotsForTO: (toId) async => const <SlotModel>[],
        invalidatePublishedTOsCache: () {},
        documentCorrections: () async => DocumentCorrectionSurface.empty,
      );
}

/// Hero CTA 를 눌러 실제 AttendanceCheckScreen 으로 갔다가, [during] 동안 서버가 바뀌고 돌아온다.
Future<void> _visitAttendanceScreen(WidgetTester t, void Function() during) async {
  await t.tap(_cta().first);
  await t.pump();
  await t.pump(const Duration(milliseconds: 500));
  expect(find.byType(AttendanceCheckScreen), findsOneWidget);
  during();
  Navigator.of(t.element(find.byType(AttendanceCheckScreen))).pop();
  await t.pumpAndSettle(const Duration(seconds: 3));
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({'tour_completed_user_home': true}));
  setUpAll(() async {
    initializeDateFormatting('ko');
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
  });

  testWidgets('RH-1 출근하고 돌아오면 퇴근하기', (t) async {
    final clock = _clockAt(10, 30);
    final l = _Ledger([_confirmedToday(clock)]);
    await _pumpHome(t, clock: clock, reads: l.reads0);
    expect(_hasText(t, _kCheckIn), isTrue);
    final before = l.reads;
    await _visitAttendanceScreen(t, () => l.attendances = [_att(clock, checkIn: _clockAt(10, 2))]);
    expect(l.reads, greaterThan(before), reason: '복귀 뒤 근태를 다시 읽지 않았다');
    expect(_hasText(t, _kCheckOut), isTrue);
    expect(_hasText(t, _kCheckIn), isFalse);
    expect(_progressLabel(t), contains('퇴근까지'));
  });

  testWidgets('RH-2 퇴근하고 돌아오면 출퇴근 완료', (t) async {
    final clock = _clockAt(11, 10);
    final l = _Ledger([_confirmedToday(clock)])..attendances = [_att(clock, checkIn: _clockAt(10, 0))];
    await _pumpHome(t, clock: clock, reads: l.reads0);
    expect(_hasText(t, _kCheckOut), isTrue);
    await _visitAttendanceScreen(t, () => l.attendances = [_att(clock, checkIn: _clockAt(10, 0), checkOut: _clockAt(11, 0))]);
    expect(_progressLabel(t), _kDone);
    expect(_hasText(t, _kCheckOut), isFalse);
    expect(_hasText(t, '출퇴근 기록 보기'), isTrue);
  });

  testWidgets('RH-3 아무것도 하지 않고 돌아오면 그대로(오류 없음)', (t) async {
    final clock = _clockAt(10, 30);
    final l = _Ledger([_confirmedToday(clock)]);
    await _pumpHome(t, clock: clock, reads: l.reads0);
    final before = l.reads;
    await _visitAttendanceScreen(t, () {});
    expect(l.reads, before + 1, reason: '복귀 1회 = 다시 읽기 1회');
    expect(_hasText(t, _kCheckIn), isTrue);
    expect(_progressLabel(t), '출근 기록이 없어요');
  });

  testWidgets('RH-4 복귀 뒤 근태 조회 실패 → 모른다고 말한다(출근 전으로 단정하지 않음), 다음 복귀에 회복', (t) async {
    final clock = _clockAt(10, 30);
    final l = _Ledger([_confirmedToday(clock)]);
    await _pumpHome(t, clock: clock, reads: l.reads0);
    await _visitAttendanceScreen(t, () { l.attendances = [_att(clock, checkIn: _clockAt(10, 2))]; l.fail = true; });
    expect(_progressLabel(t), '근태 기록을 불러오지 못했어요');
    expect(_hasText(t, _kCheckIn), isFalse);
    expect(_hasText(t, '출퇴근 화면에서 확인'), isTrue);
    await _visitAttendanceScreen(t, () => l.fail = false);
    expect(_hasText(t, _kCheckOut), isTrue);
  });

  // ── [DEVICE-MISMATCH-FIX] 예정 시간이 끝난 미출근 근무 ──────────────────
  testWidgets('RH-5 [DEV 재현 Zdn7] 10:00~11:00 · 근태 없음 · 14:58 — 출근하기를 권하지 않는다',
      (t) async {
    final clock = _clockAt(14, 58);
    final l = _Ledger([_confirmedToday(clock)]);
    await _pumpHome(t, clock: clock, reads: l.reads0);
    expect(_hasText(t, _kCheckIn), isFalse);
    expect(_progressLabel(t), '근무 시간이 지났어요 · 출근 기록이 없어요');
    expect(_hasText(t, '근태 기록 확인'), isTrue);
    // 예상수입에서도 빠진다 — 근무 예정 0원.
    expect(_shown(t), isNot(contains('53,000원')),
        reason: '일하지 않은 끝난 근무를 벌 예정으로 세지 않는다');
  });

  testWidgets('RH-6 오늘 근무 둘 — 끝난 미출근보다 아직 남은 근무가 현재 할 일', (t) async {
    final clock = _clockAt(14, 58);
    final ended = _confirmedToday(clock);
    final upcoming = ApplicationModel(
      id: 'app-later',
      uid: _kUid,
      businessId: 'biz1',
      businessName: 'QA 사업장',
      toId: 'to2',
      toTitle: 'QA 공고 2',
      selectedWorkType: 'QA 분류',
      startTime: '16:00',
      endTime: '17:00',
      workDate: _workDateFor(clock),
      status: AppStatus.confirmed,
      appliedAt: _workDateFor(clock).subtract(const Duration(days: 2)),
      wage: 53000,
      wageType: 'daily',
    );
    // 목록 순서상 끝난 근무가 먼저 와도 Hero 는 남은 근무를 고른다.
    final l = _Ledger([ended, upcoming]);
    await _pumpHome(t, clock: clock, reads: l.reads0);
    expect(_progressLabel(t), contains('출근까지'));
    expect(_hasText(t, _kCheckIn), isTrue);
  });

  testWidgets('RH-7 [DEV 재현 10-20] 둘 다 끝남 — 오전 미출근보다 오후에 마친 근무를 보인다',
      (t) async {
    final clock = _clockAt(14, 58);
    final zdn7 = _confirmedToday(clock); // 10:00~11:00, 근태 없음
    final rube = ApplicationModel(
      id: 'app-rube',
      uid: _kUid,
      businessId: 'biz1',
      businessName: 'QA 사업장',
      toId: 'to3',
      toTitle: 'QA 공고 3',
      selectedWorkType: 'QA 분류',
      startTime: '13:00',
      endTime: '14:00',
      workDate: _workDateFor(clock),
      status: AppStatus.confirmed,
      appliedAt: _workDateFor(clock).subtract(const Duration(days: 1)),
      wage: 12000,
      wageType: 'hourly',
    );
    final l = _Ledger([zdn7, rube])
      ..attendances = [
        _att(clock,
            applicationId: 'app-rube',
            checkIn: _clockAt(13, 0),
            checkOut: _clockAt(14, 0)),
      ];
    await _pumpHome(t, clock: clock, reads: l.reads0);
    expect(_progressLabel(t), _kDone);
    expect(_hasText(t, _kCheckIn), isFalse);
  });

  // [DEVICE-MISMATCH-FIX] Hero 제목도 근태 사실을 말한다.
  //   DEVICE(10-20 새 APK): RUBE 출퇴근 완료인데 제목이 `오늘 13:00 출근이에요`.
  group('RH-8 Hero 제목', () {
    Future<String?> titleAt(WidgetTester t, DateTime clock,
        List<AttendanceModel> atts) async {
      final l = _Ledger([_confirmedToday(clock)])..attendances = atts;
      await _pumpHome(t, clock: clock, reads: l.reads0);
      for (final c in const [
        '오늘 10:00 출근이에요',
        '오늘 근무 중이에요',
        '오늘 근무를 마쳤어요',
        '오늘 10:00 근무 시간이 지났어요',
        '오늘 근무가 노쇼 처리됐어요',
        '오늘 근무가 결근 처리됐어요',
        '오늘 10:00 근무가 있어요',
      ]) {
        if (_hasText(t, c)) return c;
      }
      return null;
    }

    testWidgets('RH-8a 출근 전 — 출근이에요', (t) async {
      expect(await titleAt(t, _clockAt(9, 0), const []), '오늘 10:00 출근이에요');
    });
    testWidgets('RH-8b 출근 후 퇴근 전 — 근무 중', (t) async {
      final c = _clockAt(10, 30);
      expect(await titleAt(t, c, [_att(c, checkIn: _clockAt(10, 0))]),
          '오늘 근무 중이에요');
    });
    testWidgets('RH-8c [DEVICE 재현] 퇴근 후 — 마쳤어요(출근이에요 아님)', (t) async {
      final c = _clockAt(14, 58);
      expect(
          await titleAt(t, c,
              [_att(c, checkIn: _clockAt(10, 0), checkOut: _clockAt(11, 0))]),
          '오늘 근무를 마쳤어요');
      expect(_hasText(t, '오늘 10:00 출근이에요'), isFalse);
    });
    testWidgets('RH-8d 출근 기록 없이 종료 — 근무 시간이 지났어요', (t) async {
      expect(await titleAt(t, _clockAt(14, 58), const []),
          '오늘 10:00 근무 시간이 지났어요');
    });
    testWidgets('RH-8e 노쇼 — 노쇼 처리됐어요', (t) async {
      final c = _clockAt(14, 58);
      expect(
          await titleAt(t, c, [_att(c, status: AttendanceModel.statusNoShow)]),
          '오늘 근무가 노쇼 처리됐어요');
    });
    testWidgets('RH-8f 근태 조회 실패 — 단정하지 않는다', (t) async {
      final c = _clockAt(14, 58);
      final l = _Ledger([_confirmedToday(c)])..fail = true;
      await _pumpHome(t, clock: c, reads: l.reads0);
      expect(_hasText(t, '오늘 10:00 근무가 있어요'), isTrue);
      expect(_hasText(t, '오늘 10:00 출근이에요'), isFalse);
      expect(_hasText(t, '오늘 근무를 마쳤어요'), isFalse);
    });
  });
}
