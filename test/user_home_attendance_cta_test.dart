// [E1-HOME-ATTENDANCE-CTA] Home Hero 의 상태·진행·CTA 가 **같은 근태 하나**를
//   말한다.
//
// ── 기기에서 본 것 (DEV QA 지원자1, 2026-10-13) ────────────────────────
//   Hero 제목   `오늘의 근무`  10:00 ~ 11:00
//   진행 라벨   `근무 완료` + 진행 바 100%
//   그 아래     `출근하기` 버튼
//   같은 카드가 "끝났다"와 "이제 출근하라"를 동시에 말했다.
//
// ── 원장 대조 (READ ONLY) ─────────────────────────────────────────────
//   지원서 1건  status=CONFIRMED · workDate 2026-10-13 KST · 10:00~11:00
//               staffingReleasedAt 없음
//   근태 문서   그 지원서에 대해 **0 건** (WORKER_01 의 다른 4건은 10/10·10/11)
//   → canonical 상태는 `확정 · 체크인 전`. `근무 완료` 는 거짓이었다.
//
// ── 원인 (분류 A + C) ────────────────────────────────────────────────
//   `_buildHeroStateB` 가 진행 라벨·진행 값·CTA 를 **시계만 보고** 정했다.
//     now.isAfter(endDt) → progressLabel = '근무 완료', progressValue = 1.0
//   근태는 읽지 않았다 — `_attendances`(이번 달 전체)가 **이미 메모리에
//   있는데도** Hero 안에서 한 번도 참조되지 않았다. CTA 는 상태와 무관한
//   고정 `출근하기` 였다.
//
// ── 고친 것 ──────────────────────────────────────────────────────────
//   ① `_todayAttendanceFor(app)` — 기존 술어 재사용(`userId` + `applicationId`,
//      `_openOvernightAttendance` 와 동일, 목적지 화면의 조회 키와 동일).
//      **읽기를 추가하지 않는다** — 오늘은 이번 달 안이다.
//   ② 진행 라벨·값: 완료는 **퇴근 기록이 있을 때만**. 시계는 아직 하지 않은
//      일의 남은 시간만 말한다.
//   ③ CTA: 목적지(`attendance_check_screen`)의 4분기와 같은 순서·같은 술어.
//      목적지 화면과 Attendance writer 는 건드리지 않았다.
//   ④ 근태를 못 읽으면(ERROR) 완료도 미출근도 단정하지 않는다.
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
import 'package:ALfit/models/core/employment_contract_model.dart';
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

UserHomeReads _reads({
  required List<ApplicationModel> apps,
  List<AttendanceModel> attendances = const [],
  bool attendanceFails = false,
  List<EmploymentContractModel>? contracts,
  bool contractsFail = false,
}) =>
    UserHomeReads(
      // [CONTRACT-DISPATCH-B4] 홈 CTA 는 계약 동의 판정을 함께 본다 — 기본 전제: 오늘 근무 계약은 양측 서명 완료
      myContracts: (uid) async {
        if (contractsFail) throw StateError('계약 조회 실패(테스트)');
        return contracts ?? completedContractsFor(apps);
      },
      myApplications: (uid) async => apps,
      myMonthlyAttendances: (
          {required String userId,
          required int year,
          required int month}) async {
        if (attendanceFails) {
          throw StateError('근태 조회 실패(테스트)');
        }
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

/// 진행 바의 값 — "100% 로 그렸는가" 를 직접 본다.
double? _progressValue(WidgetTester t) {
  if (_bar().evaluate().isEmpty) return null;
  return t.widget<LinearProgressIndicator>(_bar().first).value;
}

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
const _kNoShow = '노쇼 처리됨';
const _kAbsent = '결근 처리됨';
const _kDone = '출퇴근 완료';
const _kCheckIn = '출근하기';
const _kCheckOut = '퇴근하기';
// 시계만 보고 완료를 주장했던 옛 문구 — Hero 진행 라벨에 다시 나오면 안 된다.
const _kOldDone = '근무 완료';

void main() {
  // 투어 코치마크가 떠 있으면 Home 내용이 가려져 모든 단정이 거짓으로 통과한다.
  setUp(() => SharedPreferences.setMockInitialValues(
      {'tour_completed_user_home': true}));
  setUpAll(() async {
    initializeDateFormatting('ko');
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
  });

  group('[HC-A] 근태 기록이 없다 — 시간이 지나도 완료가 아니다', () {
    testWidgets('HC-1 시작 전: 출근까지 남은 시간 · CTA 출근하기', (t) async {
      final clock = _clockAt(9, 30);
      await _pumpHome(t,
          clock: clock, reads: _reads(apps: [_confirmedToday(clock)]));
      expect(_hasText(t, '오늘의 근무'), isTrue, reason: 'Hero STATE B 가 떠야 한다');
      expect(_progressLabel(t), contains('출근까지'));
      expect(_hasText(t, _kCheckIn), isTrue);
      expect(_progressLabel(t), isNot(_kOldDone));
      expect(_progressValue(t), 0.0);
    });

    testWidgets('HC-2 근무 시간 중 · 미출근: 완료가 아니라 출근 기록 없음', (t) async {
      final clock = _clockAt(10, 30);
      await _pumpHome(t,
          clock: clock, reads: _reads(apps: [_confirmedToday(clock)]));
      // 출근 기록이 없으므로 "퇴근까지" 로 말하지 않는다 — 아직 출근 차례다.
      expect(_progressLabel(t), '출근 기록이 없어요');
      expect(_progressLabel(t), isNot(contains('퇴근까지')));
      expect(_hasText(t, _kCheckIn), isTrue);
      expect(_hasText(t, _kCheckOut), isFalse);
      expect(_progressValue(t), 0.0);
    });

    testWidgets('HC-3 [기기 재현] 종료 후 · 근태 0건: "근무 완료" 와 100% 를 말하지 않는다',
        (t) async {
      final clock = _clockAt(11, 30);
      await _pumpHome(t,
          clock: clock, reads: _reads(apps: [_confirmedToday(clock)]));
      // 이번 Phase 가 고친 바로 그 셀.
      expect(_progressLabel(t), isNot(_kOldDone),
          reason: '출근 기록이 없는데 끝났다고 말하면 안 된다');
      expect(_progressLabel(t), isNot(_kDone));
      expect(_progressValue(t), 0.0, reason: '시간 경과만으로 100% 를 그리지 않는다');
      // [DEVICE-MISMATCH-FIX 10-20] 예전 계약은 "종료 후에도 출근은 할 수
      //   있다 — 버튼을 숨기지 않는다" 였다. 사용자 지시(종료된 근무의 출근·
      //   취소·리컨펌 버튼을 화면에서 막는다)로 바뀌었다. 모순을 덮는 것이
      //   아니라 사실(시간이 지났고 출근 기록이 없다)을 말하고 출근을 권하지
      //   않는다. 서버 callableCheckIn 종료 상한 부재는 별도 결함으로 남는다.
      expect(_progressLabel(t), '근무 시간이 지났어요 · 출근 기록이 없어요');
      expect(_hasText(t, _kCheckIn), isFalse);
      expect(_hasText(t, '근태 기록 확인'), isTrue);
    });
  });

  group('[HC-B] 근태 기록이 상태를 정한다', () {
    testWidgets('HC-4 출근 O · 퇴근 X · 근무 중: 퇴근까지 · CTA 퇴근하기', (t) async {
      final clock = _clockAt(10, 30);
      await _pumpHome(t,
          clock: clock,
          reads: _reads(
            apps: [_confirmedToday(clock)],
            attendances: [_att(clock, checkIn: _clockAt(10, 2))],
          ));
      expect(_progressLabel(t), contains('퇴근까지'));
      expect(_hasText(t, _kCheckOut), isTrue);
      expect(_hasText(t, _kCheckIn), isFalse, reason: '이미 출근했다');
      final v = _progressValue(t)!;
      expect(v, greaterThan(0.0));
      expect(v, lessThan(1.0));
    });

    testWidgets('HC-5 출근 O · 퇴근 X · 종료 후: 퇴근을 자동 확정하지 않는다', (t) async {
      final clock = _clockAt(11, 30);
      await _pumpHome(t,
          clock: clock,
          reads: _reads(
            apps: [_confirmedToday(clock)],
            attendances: [_att(clock, checkIn: _clockAt(10, 2))],
          ));
      expect(_progressLabel(t), '퇴근 기록이 필요해요');
      expect(_progressLabel(t), isNot(_kDone),
          reason: '시간이 지났다고 퇴근을 기록해 주지 않는다');
      expect(_progressLabel(t), isNot(_kOldDone));
      expect(_hasText(t, _kCheckOut), isTrue);
    });

    testWidgets('HC-6 출근 O · 퇴근 O: 출퇴근 완료 · 100% · 출근/퇴근 CTA 없음',
        (t) async {
      final clock = _clockAt(11, 30);
      await _pumpHome(t,
          clock: clock,
          reads: _reads(
            apps: [_confirmedToday(clock)],
            attendances: [
              _att(clock,
                  checkIn: _clockAt(10, 2), checkOut: _clockAt(11, 1))
            ],
          ));
      expect(_progressLabel(t), _kDone);
      expect(_progressValue(t), 1.0);
      expect(_hasText(t, _kCheckIn), isFalse);
      expect(_hasText(t, _kCheckOut), isFalse);
      expect(_hasText(t, '출퇴근 기록 보기'), isTrue);
    });

    testWidgets('HC-7 퇴근했지만 근태 확정 전 — "근태 확정" 이라고 말하지 않는다',
        (t) async {
      final clock = _clockAt(11, 30);
      await _pumpHome(t,
          clock: clock,
          reads: _reads(
            apps: [_confirmedToday(clock)],
            attendances: [
              // wageStatus 기본값 'pending' — 급여·근태 확정 전이다.
              _att(clock,
                  checkIn: _clockAt(10, 2), checkOut: _clockAt(11, 1))
            ],
          ));
      expect(_hasText(t, _kDone), isTrue, reason: '출퇴근은 끝났다');
      expect(_progressLabel(t), isNot(contains('근태 확정')),
          reason: '출퇴근 완료와 근태·급여 확정을 같은 말로 합치지 않는다');
      expect(_progressLabel(t), isNot(contains('정산 완료')));
    });
  });

  group('[HC-C] 노쇼·결근을 근무 완료로 바꿔 말하지 않는다', () {
    testWidgets('HC-8 NO_SHOW: 노쇼 처리됨 · 출근 요구 없음', (t) async {
      final clock = _clockAt(11, 30);
      await _pumpHome(t,
          clock: clock,
          reads: _reads(
            apps: [_confirmedToday(clock)],
            attendances: [_att(clock, status: AttendanceModel.statusNoShow)],
          ));
      expect(_progressLabel(t), _kNoShow);
      expect(_progressLabel(t), isNot(_kOldDone));
      expect(_progressLabel(t), isNot(_kDone));
      expect(_hasText(t, _kCheckIn), isFalse,
          reason: '노쇼 처리된 근무에 출근하라고 하지 않는다');
      expect(_hasText(t, '근태 기록 확인'), isTrue);
      expect(_progressValue(t), 0.0);
    });

    testWidgets('HC-9 absent: 결근 처리됨', (t) async {
      final clock = _clockAt(11, 30);
      await _pumpHome(t,
          clock: clock,
          reads: _reads(
            apps: [_confirmedToday(clock)],
            attendances: [_att(clock, status: AttendanceModel.statusAbsent)],
          ));
      expect(_progressLabel(t), _kAbsent);
      expect(_progressLabel(t), isNot(_kNoShow), reason: '노쇼와 결근을 섞지 않는다');
      expect(_progressLabel(t), isNot(_kDone));
      expect(_hasText(t, _kCheckIn), isFalse);
    });
  });

  group('[HC-D] 못 읽었으면 완료도 미출근도 단정하지 않는다', () {
    testWidgets('HC-10 근태 조회 실패: ERROR ≠ ZERO', (t) async {
      final clock = _clockAt(11, 30);
      await _pumpHome(t,
          clock: clock,
          reads: _reads(
            apps: [_confirmedToday(clock)],
            attendanceFails: true,
          ));
      expect(_progressLabel(t), '근태 기록을 불러오지 못했어요');
      expect(_progressLabel(t), isNot(_kOldDone));
      expect(_progressLabel(t), isNot(_kDone));
      expect(_progressLabel(t), isNot('출근 기록이 없어요'),
          reason: '못 읽은 것을 미출근이라고 말하지 않는다');
      expect(_progressLabel(t), isNot(_kNoShow));
      expect(_progressValue(t), 0.0);
    });
  });

  group('[HC-E] 다른 사건의 근태를 끌어다 쓰지 않는다', () {
    testWidgets('HC-11 다른 지원서의 근태는 매칭하지 않는다', (t) async {
      final clock = _clockAt(11, 30);
      await _pumpHome(t,
          clock: clock,
          reads: _reads(
            apps: [_confirmedToday(clock)],
            attendances: [
              _att(clock,
                  applicationId: 'other-app',
                  checkIn: _clockAt(10, 2),
                  checkOut: _clockAt(11, 1))
            ],
          ));
      expect(_progressLabel(t), isNot(_kDone),
          reason: '다른 지원서의 퇴근 기록으로 이 근무를 완료 처리했다');
      // [DEVICE-MISMATCH-FIX] 11:30 은 종료(11:00) 뒤다.
      expect(_progressLabel(t), '근무 시간이 지났어요 · 출근 기록이 없어요');
    });

    testWidgets('HC-12 다른 사용자의 근태는 매칭하지 않는다', (t) async {
      final clock = _clockAt(11, 30);
      await _pumpHome(t,
          clock: clock,
          reads: _reads(
            apps: [_confirmedToday(clock)],
            attendances: [
              _att(clock,
                  userId: 'someone-else',
                  checkIn: _clockAt(10, 2),
                  checkOut: _clockAt(11, 1))
            ],
          ));
      expect(_progressLabel(t), isNot(_kDone));
      // [DEVICE-MISMATCH-FIX] 11:30 은 종료(11:00) 뒤다.
      expect(_progressLabel(t), '근무 시간이 지났어요 · 출근 기록이 없어요');
    });

    testWidgets('HC-13 다른 날짜의 근태는 매칭하지 않는다', (t) async {
      final clock = _clockAt(11, 30);
      await _pumpHome(t,
          clock: clock,
          reads: _reads(
            apps: [_confirmedToday(clock)],
            attendances: [
              // 같은 지원서·같은 사용자지만 어제 기록(장기 근무의 흔한 경우).
              _att(clock,
                  workDate:
                      _workDateFor(clock).subtract(const Duration(days: 1)),
                  checkIn: _clockAt(10, 2),
                  checkOut: _clockAt(11, 1))
            ],
          ));
      expect(_progressLabel(t), isNot(_kDone),
          reason: '어제 퇴근 기록으로 오늘을 완료 처리했다');
      // [DEVICE-MISMATCH-FIX] 11:30 은 종료(11:00) 뒤다.
      expect(_progressLabel(t), '근무 시간이 지났어요 · 출근 기록이 없어요');
    });
  });

  // [CONTRACT-DISPATCH-B4] 출근 전 CTA 는 출퇴근 화면과 같은 계약 판정을 쓴다 (2026-10-25).
  //   기기 관찰: 계약 미동의인데 홈은 '출근하기', 목적지 화면은 출근 버튼 비활성 — 같은 근무를 두 화면이 다르게 말했다.
  group('[HC-G] 계약 동의 전에는 출근을 권하지 않는다', () {
    testWidgets('HC-16 근로자 동의 대기 → 계약서 확인하고 동의하기', (t) async {
      final clock = _clockAt(9, 50);
      final app = _confirmedToday(clock);
      await _pumpHome(t, clock: clock, reads: _reads(apps: [app],
          contracts: [checkInContractFor(app, status: ContractStatus.pendingWorker)]));
      expect(_hasText(t, '계약서 확인하고 동의하기'), isTrue);
      expect(_hasText(t, _kCheckIn), isFalse);
      expect(t.widget<ElevatedButton>(_cta().first).onPressed, isNotNull);
    });

    for (final (name, contracts) in <(String, List<EmploymentContractModel> Function(ApplicationModel))>[
      ('계약 없음', (a) => const []),
      ('사업주 서명 대기', (a) => [checkInContractFor(a, status: ContractStatus.pendingEmployer)]),
      ('무효만', (a) => [checkInContractFor(a, status: ContractStatus.voided)]),
      ('다른 지원서 완료', (a) => [checkInContractFor(a, applicationId: 'other')]),
    ]) {
      testWidgets('HC-17 $name → 근로자에게 할 수 없는 일을 시키지 않는다', (t) async {
        final clock = _clockAt(9, 50);
        final app = _confirmedToday(clock);
        await _pumpHome(t, clock: clock, reads: _reads(apps: [app], contracts: contracts(app)));
        expect(_hasText(t, '계약서를 기다리고 있어요'), isTrue);
        expect(_hasText(t, _kCheckIn), isFalse);
        expect(_hasText(t, '계약서 확인하고 동의하기'), isFalse);
      });
    }

    testWidgets('HC-18 계약 조회 실패 → 출근을 권하지 않고 화면에서 확인', (t) async {
      final clock = _clockAt(9, 50);
      await _pumpHome(t, clock: clock, reads: _reads(apps: [_confirmedToday(clock)], contractsFail: true));
      expect(_hasText(t, '출퇴근 화면에서 확인'), isTrue);
      expect(_hasText(t, _kCheckIn), isFalse);
    });

    testWidgets('HC-19 이미 출근했으면 계약 상태로 퇴근을 막지 않는다', (t) async {
      final clock = _clockAt(10, 30);
      final app = _confirmedToday(clock);
      await _pumpHome(t, clock: clock, reads: _reads(apps: [app],
          attendances: [_att(clock, checkIn: _clockAt(10, 2))],
          contracts: [checkInContractFor(app, status: ContractStatus.pendingWorker)]));
      expect(_hasText(t, _kCheckOut), isTrue);
      expect(_hasText(t, '계약서 확인하고 동의하기'), isFalse);
    });

    testWidgets('HC-20 양측 서명 완료(직접·초대 모두) → 출근하기', (t) async {
      final clock = _clockAt(9, 50);
      final app = _confirmedToday(clock); // 초대 수락 = CONFIRMED
      await _pumpHome(t, clock: clock, reads: _reads(apps: [app], contracts: [checkInContractFor(app)]));
      expect(_hasText(t, _kCheckIn), isTrue);
    });
  });

  group('[HC-F] 바꾸지 않은 것', () {
    testWidgets('HC-14 제목과 목적지는 네 분기에서 모두 같다', (t) async {
      final clock = _clockAt(11, 30);
      for (final atts in <List<AttendanceModel>>[
        const [],
        [_att(clock, checkIn: _clockAt(10, 2))],
        [_att(clock, checkIn: _clockAt(10, 2), checkOut: _clockAt(11, 1))],
        [_att(clock, status: AttendanceModel.statusNoShow)],
      ]) {
        await _pumpHome(t,
            clock: clock,
            reads: _reads(apps: [_confirmedToday(clock)], attendances: atts));
        expect(_hasText(t, '오늘의 근무'), isTrue,
            reason: '제목은 상태 주장이 아니라 사실 서술이다');
        // CTA 는 네 분기 모두에서 **눌릴 수 있다** — 버튼만 숨겨 모순을
        //   덮지 않는다. 목적지는 출퇴근 canonical 화면 하나다.
        final btn = t.widget<ElevatedButton>(_cta().first);
        expect(btn.onPressed, isNotNull, reason: 'CTA 는 항상 눌릴 수 있다');
      }
    });

    testWidgets('HC-15 Attendance writer·목적지 화면은 건드리지 않았다', (t) async {
      // 이 Phase 는 Home 의 **표현**만 고쳤다. 출퇴근 mutation 은 목적지
      //   화면에만 있고, Home 은 그 화면으로 보낼 뿐이다.
      final home = File('lib/screens/user/user_home_screen.dart')
          .readAsStringSync()
          .replaceAll('\r\n', '\n');
      for (final w in ['_checkIn(', '_checkOut(', 'checkInAt:', 'checkOutAt:']) {
        expect(home.contains(w), isFalse,
            reason: 'Home 이 근태를 직접 쓰면 writer 가 둘이 된다 ($w)');
      }
      // 목적지 화면 참조는 유지된다.
      expect(home.contains('AttendanceCheckScreen'), isTrue);
      expect(AttendanceCheckScreen, isNotNull);
    });
  });
}
