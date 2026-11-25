// ignore_for_file: depend_on_referenced_packages
// [E1-MYA] `내 지원`이 시간 경과를 실제 근무 완료로 말하지 않는다.
//
// ── DEV 원장 (READ ONLY) ──────────────────────────────────────────────
//   attendance 21건 중 NO_SHOW 12건. 그중 과거 날짜 + `app.status ==
//   CONFIRMED` 조합이 여럿이고, QA 지원자1(U#7oZZ)의 10/10·10/11 두 건이
//   거기 속한다.
//
// ── 에뮬레이터에서 본 것 ───────────────────────────────────────────────
//   그 노쇼 근무 3건이 모두 배지 `확정` + **`리뷰를 작성해 주세요`** 로
//   보였다. 노쇼한 근무에 리뷰 작성을 권한 것이다.
//
// ── 원인 ──────────────────────────────────────────────────────────────
//   `_buildContextRow` 의 confirmed 분기가 `rdDate.isBefore(today)` 하나로
//   완료를 판정했고, 이 화면은 목록 시점에 근태를 **전혀 읽지 않았다**
//   (`getMyMonthlyAttendances` 호출은 리뷰 다이얼로그를 열 때뿐이고 그
//   결과도 저장하지 않는다).
//
// ── 고친 것 ───────────────────────────────────────────────────────────
//   판정이 필요한 달의 근태만 기존 read model 로 읽어(캐시 공유, N+1 없음),
//   출퇴근 화면·홈과 **같은 술어**로 말한다. 완료 기준은 리뷰 자격이 이미
//   쓰던 `isWageConfirmed || isWageTransferred` 를 그대로 따른다.
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

// ── 고정 시계 ───────────────────────────────────────────────────────────
//   확정 근무가 '지났는가' 는 이 한 값으로 갈린다. TZ 가정을 하지 않도록
//   근무일은 이 시계에서 `toKstDate` 로 역산한다.
final DateTime _clock = DateTime(2026, 10, 13, 21, 30);
DateTime _todayKst() => FormatHelper.toKstDate(_clock);
DateTime _dayOffset(int d) => _todayKst().add(Duration(days: d));

ApplicationModel _app({
  required String id,
  required String status,
  required DateTime workDate,
  String startTime = '10:00',
  String endTime = '11:00',
}) =>
    ApplicationModel(
      id: id,
      toId: 'to1',
      uid: _kUid,
      businessId: 'biz1',
      businessName: 'QA 사업장',
      toTitle: 'QA 공고',
      status: status,
      selectedWorkType: 'QA 분류',
      startTime: startTime,
      endTime: endTime,
      wage: 53000,
      workDate: workDate,
      appliedAt: _dayOffset(-5),
    );

AttendanceModel _att({
  required String applicationId,
  required DateTime workDate,
  String status = AttendanceModel.statusPresent,
  DateTime? checkIn,
  DateTime? checkOut,
  String wageStatus = 'pending',
  String userId = _kUid,
}) =>
    AttendanceModel(
      id: 'att-$applicationId',
      applicationId: applicationId,
      userId: userId,
      businessId: 'biz1',
      businessName: 'QA 사업장',
      workDate: workDate,
      workType: 'QA 분류',
      checkInAt: checkIn,
      checkOutAt: checkOut,
      status: status,
      wageStatus: wageStatus,
      createdAt: workDate,
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
      createdAt: _dayOffset(-10),
      statusUpdatedAt: _dayOffset(-10),
    );

/// 읽은 (year, month) 를 기록해 **몇 번 나갔는지** 셀 수 있게 한다.
class _ReadLog {
  final List<String> months = [];
}

MyApplicationsReads _reads(
  List<ApplicationModel> apps, {
  List<AttendanceModel> attendances = const [],
  Object? attendanceError,
  _ReadLog? log,
}) =>
    MyApplicationsReads(
      myApplicationsPaged: (
              {required String uid,
              required int pageSize,
              String? startAfterDocId}) async =>
          {'items': apps, 'lastDocId': null, 'hasMore': false},
      toOrFailure: (id) async => (to: _to(), failed: false),
      contractsByWorker: (uid) async => const <EmploymentContractModel>[],
      autoExpirePending: (uid) async {},
      monthlyAttendances: (
          {required String userId, required int year, required int month}) async {
        log?.months.add('$year-$month');
        if (attendanceError != null) throw attendanceError;
        return attendances
            .where((a) =>
                a.workDate.toUtc().year == year &&
                a.workDate.toUtc().month == month)
            .toList();
      },
      reviewById: (key) async => null,
      taxStatus: () async => const TaxIdentityStatus.unknown(),
    );

Future<void> _pump(WidgetTester t, MyApplicationsReads reads) async {
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
        home: MyApplicationsScreen(reads: reads, clock: () => _clock),
      ),
    ),
  );
  // 이 화면은 멈추지 않는 애니메이션이 있어 pumpAndSettle 이 끝나지 않는다
  //   (기존 my_applications 테스트들과 같은 방식으로 프레임을 전진시킨다).
  for (var i = 0; i < 25; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

List<String> _texts(WidgetTester t) => t
    .widgetList<Text>(find.byWidgetPredicate((w) => w is Text))
    .map((w) => w.data ?? '')
    .where((s) => s.isNotEmpty)
    .toList();

bool _has(WidgetTester t, String s) => _texts(t).contains(s);

const _kReview = '리뷰를 작성해 주세요';
const _kDone = '근무 완료';
const _kNoShow = '노쇼 처리됐어요';
const _kAbsent = '결근 처리됐어요';
const _kNoRecord = '근무 기록이 없어요';
const _kNoCheckIn = '출근 기록이 없어요';
const _kWorking = '근무 중이에요';
// [DEVICE-MISMATCH-FIX] 홈·수입의 `정산 중`과 같은 이름으로 바뀌었다.
const _kEnded = '근무가 끝났어요 · 정산 중';
const _kMissed = '근무 시간이 지났어요 · 출근 기록이 없어요';
const _kContractPreparing = '관리자가 계약서를 준비 중이에요';
const _kUnknown = '근무 상태를 확인하지 못했어요';
const _kTodayPlanned = '오늘 근무 예정이에요';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  setUpAll(() async {
    initializeDateFormatting('ko');
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
  });

  group('[MA-A] 지난 확정 근무 — 근태가 말한다', () {
    testWidgets('MA-1 [기기 재현] NO_SHOW 는 완료도 아니고 리뷰 대상도 아니다',
        (t) async {
      final wd = _dayOffset(-2);
      await _pump(
        t,
        _reads(
          [_app(id: 'a1', status: AppStatus.confirmed, workDate: wd)],
          attendances: [
            _att(
                applicationId: 'a1',
                workDate: wd,
                status: AttendanceModel.statusNoShow,
                wageStatus: 'confirmed'),
          ],
        ),
      );
      expect(_has(t, _kNoShow), isTrue);
      expect(_has(t, _kReview), isFalse,
          reason: '노쇼한 근무에 리뷰를 권하면 안 된다');
      expect(_has(t, _kDone), isFalse);
    });

    testWidgets('MA-2 ABSENT 는 결근으로 말한다', (t) async {
      final wd = _dayOffset(-2);
      await _pump(
        t,
        _reads(
          [_app(id: 'a1', status: AppStatus.confirmed, workDate: wd)],
          attendances: [
            _att(
                applicationId: 'a1',
                workDate: wd,
                status: AttendanceModel.statusAbsent,
                wageStatus: 'confirmed'),
          ],
        ),
      );
      expect(_has(t, _kAbsent), isTrue);
      expect(_has(t, _kNoShow), isFalse, reason: '노쇼와 결근을 섞지 않는다');
      expect(_has(t, _kReview), isFalse);
      expect(_has(t, _kDone), isFalse);
    });

    testWidgets('MA-3 근태 문서가 없으면 완료를 단정하지 않는다', (t) async {
      final wd = _dayOffset(-2);
      await _pump(
        t,
        _reads([_app(id: 'a1', status: AppStatus.confirmed, workDate: wd)]),
      );
      expect(_has(t, _kNoRecord), isTrue);
      expect(_has(t, _kDone), isFalse);
      expect(_has(t, _kReview), isFalse);
    });

    testWidgets('MA-4 출근 기록이 없으면 완료가 아니다', (t) async {
      final wd = _dayOffset(-2);
      await _pump(
        t,
        _reads(
          [_app(id: 'a1', status: AppStatus.confirmed, workDate: wd)],
          attendances: [_att(applicationId: 'a1', workDate: wd)],
        ),
      );
      expect(_has(t, _kNoCheckIn), isTrue);
      expect(_has(t, _kDone), isFalse);
      expect(_has(t, _kReview), isFalse);
    });

    testWidgets('MA-5 퇴근 기록이 없으면 근무 중이다', (t) async {
      final wd = _dayOffset(-1);
      await _pump(
        t,
        _reads(
          [_app(id: 'a1', status: AppStatus.confirmed, workDate: wd)],
          attendances: [
            _att(
                applicationId: 'a1',
                workDate: wd,
                checkIn: wd.add(const Duration(hours: 10))),
          ],
        ),
      );
      expect(_has(t, _kWorking), isTrue);
      expect(_has(t, _kDone), isFalse);
    });

    testWidgets('MA-6 퇴근했지만 근태 확정 전 — 완료와 합치지 않는다', (t) async {
      final wd = _dayOffset(-2);
      await _pump(
        t,
        _reads(
          [_app(id: 'a1', status: AppStatus.confirmed, workDate: wd)],
          attendances: [
            _att(
                applicationId: 'a1',
                workDate: wd,
                checkIn: wd.add(const Duration(hours: 10)),
                checkOut: wd.add(const Duration(hours: 11))),
          ],
        ),
      );
      expect(_has(t, _kEnded), isTrue);
      expect(_has(t, _kDone), isFalse,
          reason: '근무 종료와 근태 확정은 같은 상태가 아니다');
      expect(_has(t, _kReview), isFalse,
          reason: '확정 전에는 리뷰를 권하지 않는다');
    });

    testWidgets('MA-7 근태가 확정되면 비로소 완료 · 리뷰를 권한다', (t) async {
      final wd = _dayOffset(-2);
      await _pump(
        t,
        _reads(
          [_app(id: 'a1', status: AppStatus.confirmed, workDate: wd)],
          attendances: [
            _att(
                applicationId: 'a1',
                workDate: wd,
                checkIn: wd.add(const Duration(hours: 10)),
                checkOut: wd.add(const Duration(hours: 11)),
                wageStatus: 'confirmed'),
          ],
        ),
      );
      expect(_has(t, _kReview), isTrue);
      expect(_has(t, _kNoShow), isFalse);
      expect(_has(t, _kEnded), isFalse);
    });

    testWidgets('MA-8 이체까지 끝난 근무도 완료로 본다', (t) async {
      final wd = _dayOffset(-2);
      await _pump(
        t,
        _reads(
          [_app(id: 'a1', status: AppStatus.confirmed, workDate: wd)],
          attendances: [
            _att(
                applicationId: 'a1',
                workDate: wd,
                checkIn: wd.add(const Duration(hours: 10)),
                checkOut: wd.add(const Duration(hours: 11)),
                wageStatus: 'transferred'),
          ],
        ),
      );
      expect(_has(t, _kReview), isTrue);
      expect(_has(t, _kNoRecord), isFalse);
    });
  });

  group('[MA-B] 오늘·미래 근무', () {
    testWidgets('MA-9 오늘 · 근태 없음 · 아직 끝나지 않음: 예정 (완료 주장 아님)',
        (t) async {
      // [DEVICE-MISMATCH-FIX] 시계 21:30 — 22:00~23:00 근무는 아직 앞이다.
      await _pump(
        t,
        _reads([
          _app(
              id: 'a1',
              status: AppStatus.confirmed,
              workDate: _todayKst(),
              startTime: '22:00',
              endTime: '23:00')
        ]),
      );
      expect(_has(t, _kTodayPlanned), isTrue);
      expect(_has(t, _kMissed), isFalse);
      expect(_has(t, _kDone), isFalse);
      expect(_has(t, _kNoRecord), isFalse);
    });

    testWidgets('MA-9b [DEV 재현 Zdn7] 오늘 · 근태 없음 · 예정 시간 종료: 예정이 아니다',
        (t) async {
      // 시계 21:30, 근무 10:00~11:00, 근태 없음 — 기기에서 `오늘 근무 예정이에요`.
      await _pump(
        t,
        _reads([
          _app(id: 'a1', status: AppStatus.confirmed, workDate: _todayKst())
        ]),
      );
      expect(_has(t, _kMissed), isTrue);
      expect(_has(t, _kTodayPlanned), isFalse);
    });

    testWidgets('MA-10 오늘 · 체크인 완료: 근무 중', (t) async {
      final wd = _todayKst();
      await _pump(
        t,
        _reads(
          [_app(id: 'a1', status: AppStatus.confirmed, workDate: wd)],
          attendances: [
            _att(
                applicationId: 'a1',
                workDate: wd,
                checkIn: wd.add(const Duration(hours: 10))),
          ],
        ),
      );
      expect(_has(t, _kWorking), isTrue);
      expect(_has(t, _kTodayPlanned), isFalse,
          reason: '이미 출근했는데 예정이라고 하지 않는다');
    });

    testWidgets('MA-11 오늘 · NO_SHOW: 예정이라고 하지 않는다', (t) async {
      final wd = _todayKst();
      await _pump(
        t,
        _reads(
          [_app(id: 'a1', status: AppStatus.confirmed, workDate: wd)],
          attendances: [
            _att(
                applicationId: 'a1',
                workDate: wd,
                status: AttendanceModel.statusNoShow),
          ],
        ),
      );
      expect(_has(t, _kNoShow), isTrue);
      expect(_has(t, _kTodayPlanned), isFalse);
    });

    testWidgets('MA-12 미래 확정은 근태를 보지 않고 예정으로 말한다', (t) async {
      final log = _ReadLog();
      await _pump(
        t,
        _reads(
          [_app(id: 'a1', status: AppStatus.confirmed, workDate: _dayOffset(2))],
          log: log,
        ),
      );
      expect(_texts(t).any((s) => s.contains('출근 예정이에요')), isTrue);
      expect(_has(t, _kDone), isFalse);
      expect(log.months, isEmpty,
          reason: '아직 오지 않은 근무 때문에 근태를 읽지 않는다');
    });
  });

  group('[MA-C] 못 읽은 것과 없는 것', () {
    testWidgets('MA-13 근태 조회 실패: ERROR ≠ ZERO', (t) async {
      final wd = _dayOffset(-2);
      await _pump(
        t,
        _reads(
          [_app(id: 'a1', status: AppStatus.confirmed, workDate: wd)],
          attendanceError: StateError('근태 조회 실패(테스트)'),
        ),
      );
      expect(_has(t, _kUnknown), isTrue);
      expect(_has(t, _kDone), isFalse);
      expect(_has(t, _kReview), isFalse);
      expect(_has(t, _kNoRecord), isFalse,
          reason: '못 읽은 것을 기록이 없다고 말하지 않는다');
      expect(_has(t, _kNoShow), isFalse);
    });
  });

  group('[MA-D] 다른 사건의 근태를 끌어다 쓰지 않는다', () {
    testWidgets('MA-14 다른 지원서의 근태는 매칭하지 않는다', (t) async {
      final wd = _dayOffset(-2);
      await _pump(
        t,
        _reads(
          [_app(id: 'a1', status: AppStatus.confirmed, workDate: wd)],
          attendances: [
            _att(
                applicationId: 'other',
                workDate: wd,
                checkIn: wd.add(const Duration(hours: 10)),
                checkOut: wd.add(const Duration(hours: 11)),
                wageStatus: 'confirmed'),
          ],
        ),
      );
      expect(_has(t, _kNoRecord), isTrue);
      expect(_has(t, _kReview), isFalse);
    });

    testWidgets('MA-15 다른 사용자의 근태는 매칭하지 않는다', (t) async {
      final wd = _dayOffset(-2);
      await _pump(
        t,
        _reads(
          [_app(id: 'a1', status: AppStatus.confirmed, workDate: wd)],
          attendances: [
            _att(
                applicationId: 'a1',
                userId: 'someone-else',
                workDate: wd,
                checkIn: wd.add(const Duration(hours: 10)),
                checkOut: wd.add(const Duration(hours: 11)),
                wageStatus: 'confirmed'),
          ],
        ),
      );
      expect(_has(t, _kNoRecord), isTrue,
          reason: '남의 근태로 내 근무를 완료 처리하지 않는다');
      expect(_has(t, _kReview), isFalse);
    });
  });

  group('[MA-F] 장기 근무 · 날짜 경계 · 같은 날 여러 건', () {
    testWidgets('MA-18 장기 근무는 종료일 기준으로 판정하고 그 근태를 쓴다',
        (t) async {
      // 장기의 `workDate` 는 계약 시작일 고정값이라 완료 기준이 될 수 없다.
      //   `_reviewDate` 가 쓰는 종료일(workEndDate)로 판정한다.
      final start = _dayOffset(-20);
      final end = _dayOffset(-2);
      final app = ApplicationModel(
        id: 'L1',
        toId: 'to1',
        uid: _kUid,
        businessId: 'biz1',
        businessName: 'QA 사업장',
        toTitle: 'QA 장기',
        status: AppStatus.confirmed,
        selectedWorkType: 'QA 분류',
        startTime: '10:00',
        endTime: '11:00',
        wage: 53000,
        workDate: start,
        workEndDate: end,
        applicationType: AppType.longTerm,
        workDays: const ['월', '화', '수', '목', '금'],
        appliedAt: _dayOffset(-25),
      );
      await _pump(
        t,
        _reads([app], attendances: [
          _att(
              applicationId: 'L1',
              workDate: end,
              status: AttendanceModel.statusNoShow),
        ]),
      );
      expect(_has(t, _kNoShow), isTrue);
      expect(_has(t, _kReview), isFalse);
      expect(_has(t, _kDone), isFalse);
    });

    testWidgets('MA-19 KST 자정 경계 — 어제 23:59 근무도 지난 근무로 판정한다',
        (t) async {
      // 근무일 비교는 `toKstDate`(= toUtc + 9h 후 날짜만) 한 자로만 한다.
      //   기기 timezone 이 무엇이든 같은 날짜가 나온다.
      final wd = _dayOffset(-1);
      await _pump(
        t,
        _reads(
          [_app(id: 'a1', status: AppStatus.confirmed, workDate: wd)],
          attendances: [
            _att(
                applicationId: 'a1',
                workDate: wd,
                status: AttendanceModel.statusNoShow),
          ],
        ),
      );
      expect(_has(t, _kNoShow), isTrue);
      expect(_has(t, _kTodayPlanned), isFalse,
          reason: '어제 근무를 오늘로 읽으면 안 된다');
    });

    testWidgets('MA-20 같은 날짜의 두 지원서는 각자의 근태를 쓴다', (t) async {
      final wd = _dayOffset(-2);
      await _pump(
        t,
        _reads(
          [
            _app(id: 'a1', status: AppStatus.confirmed, workDate: wd),
            _app(id: 'a2', status: AppStatus.confirmed, workDate: wd),
          ],
          attendances: [
            _att(
                applicationId: 'a1',
                workDate: wd,
                status: AttendanceModel.statusNoShow),
            _att(
                applicationId: 'a2',
                workDate: wd,
                checkIn: wd.add(const Duration(hours: 10)),
                checkOut: wd.add(const Duration(hours: 11)),
                wageStatus: 'confirmed'),
          ],
        ),
      );
      // 한 건은 노쇼, 다른 건은 완료 — 섞이면 둘 중 하나가 거짓이 된다.
      expect(_has(t, _kNoShow), isTrue);
      expect(_has(t, _kReview), isTrue);
    });

    testWidgets('MA-21 홈과 같은 사실에는 같은 단어를 쓴다', (t) async {
      // 두 화면이 같은 근태를 두고 다른 이름을 붙이면 사용자는 다른 사건으로
      //   읽는다. 홈(Hero)의 문구와 어휘를 맞춘다.
      final wd = _dayOffset(-2);
      await _pump(
        t,
        _reads(
          [_app(id: 'a1', status: AppStatus.confirmed, workDate: wd)],
          attendances: [_att(applicationId: 'a1', workDate: wd)],
        ),
      );
      // 홈 Hero 도 미출근을 `출근 기록이 없어요` 로 말한다.
      expect(_has(t, _kNoCheckIn), isTrue);
      final home = File('lib/screens/user/user_home_screen.dart')
          .readAsStringSync();
      expect(home.contains('출근 기록이 없어요'), isTrue,
          reason: '홈과 내 지원이 같은 사실을 다른 말로 하지 않는다');
      expect(home.contains('노쇼'), isTrue);
    });
  });

  group('[MA-E] 읽기 비용', () {
    testWidgets('MA-16 같은 달의 여러 지원서는 한 번만 읽는다 (N+1 없음)',
        (t) async {
      final log = _ReadLog();
      final wd = _dayOffset(-2);
      await _pump(
        t,
        _reads(
          [
            _app(id: 'a1', status: AppStatus.confirmed, workDate: wd),
            _app(id: 'a2', status: AppStatus.confirmed, workDate: wd),
            _app(id: 'a3', status: AppStatus.confirmed, workDate: _dayOffset(-3)),
          ],
          log: log,
        ),
      );
      expect(log.months.length, 1,
          reason: '지원서 3건이 같은 달이면 조회는 한 번이다 (실제: ${log.months})');
    });

    testWidgets('MA-17 확정이 아닌 지원서 때문에 근태를 읽지 않는다', (t) async {
      final log = _ReadLog();
      await _pump(
        t,
        _reads(
          [
            _app(
                id: 'a1',
                status: AppStatus.canceled,
                workDate: _dayOffset(-2)),
            _app(
                id: 'a2',
                status: AppStatus.rejected,
                workDate: _dayOffset(-3)),
          ],
          log: log,
        ),
      );
      expect(log.months, isEmpty);
      expect(_has(t, _kDone), isFalse);
    });
  });

  // ── [DEVICE-MISMATCH-FIX] 계약 진행 중이어도 근태 결말이 먼저다 ───────────
  //   DEV 실측(10-20): QAvG·Zujr·XNjJ 는 CONTRACT_PENDING + 근태 NO_SHOW 인데
  //   배지 `계약 진행 중` · 문구 `관리자가 계약서를 준비 중이에요` 였다.
  group('[MA-F] CONTRACT_PENDING 근태 우선', () {
    testWidgets('MA-22 [DEV 재현] 지난 CONTRACT_PENDING + NO_SHOW: 노쇼로 말한다',
        (t) async {
      final wd = _dayOffset(-3);
      await _pump(
        t,
        _reads(
          [_app(id: 'a1', status: AppStatus.contractPending, workDate: wd)],
          attendances: [
            _att(
                applicationId: 'a1',
                workDate: wd,
                status: AttendanceModel.statusNoShow),
          ],
        ),
      );
      expect(_has(t, _kNoShow), isTrue);
      expect(_has(t, '노쇼'), isTrue, reason: '상태 배지도 근태 결말을 말한다');
      expect(_has(t, _kContractPreparing), isFalse);
      expect(_has(t, '계약 진행 중'), isFalse);
    });

    testWidgets('MA-23 지난 CONTRACT_PENDING + ABSENT: 결근으로 말한다', (t) async {
      final wd = _dayOffset(-3);
      await _pump(
        t,
        _reads(
          [_app(id: 'a1', status: AppStatus.contractPending, workDate: wd)],
          attendances: [
            _att(
                applicationId: 'a1',
                workDate: wd,
                status: AttendanceModel.statusAbsent),
          ],
        ),
      );
      expect(_has(t, _kAbsent), isTrue);
      expect(_has(t, '결근'), isTrue);
      expect(_has(t, _kContractPreparing), isFalse);
    });

    testWidgets('MA-24 지난 CONTRACT_PENDING + 출퇴근 완료·급여 전: 정산 중',
        (t) async {
      final wd = _dayOffset(-3);
      await _pump(
        t,
        _reads(
          [_app(id: 'a1', status: AppStatus.contractPending, workDate: wd)],
          attendances: [
            _att(
                applicationId: 'a1',
                workDate: wd,
                checkIn: wd.add(const Duration(hours: 10)),
                checkOut: wd.add(const Duration(hours: 11))),
          ],
        ),
      );
      expect(_has(t, _kEnded), isTrue);
      expect(_has(t, _kContractPreparing), isFalse);
    });

    testWidgets('MA-25 지난 CONTRACT_PENDING + 근태 없음 + 시간 종료: 출근 기록 없음',
        (t) async {
      final wd = _dayOffset(-3);
      await _pump(
        t,
        _reads(
            [_app(id: 'a1', status: AppStatus.contractPending, workDate: wd)]),
      );
      expect(_has(t, _kMissed), isTrue);
      expect(_has(t, _kContractPreparing), isFalse);
    });

    testWidgets('MA-26 미래 CONTRACT_PENDING 은 그대로 계약 진행을 말한다', (t) async {
      await _pump(
        t,
        _reads([
          _app(
              id: 'a1',
              status: AppStatus.contractPending,
              workDate: _dayOffset(3))
        ]),
      );
      expect(_has(t, _kContractPreparing), isTrue);
      expect(_has(t, '계약 진행 중'), isTrue);
      expect(_has(t, _kMissed), isFalse);
    });

    testWidgets('MA-27 근태 조회 실패: 결말을 지어내지 않고 원래 문구를 쓴다',
        (t) async {
      final wd = _dayOffset(-3);
      await _pump(
        t,
        _reads(
          [_app(id: 'a1', status: AppStatus.contractPending, workDate: wd)],
          attendanceError: Exception('boom'),
        ),
      );
      expect(_has(t, _kMissed), isFalse, reason: 'ERROR 를 미출근으로 말하지 않는다');
      expect(_has(t, _kNoShow), isFalse);
    });
  });
}
