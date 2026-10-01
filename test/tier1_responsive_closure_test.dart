// [R7-P4.4E.6B] 6A 에서 A등급(TIER-1 RENDER REQUIRED)으로 남긴 후보를
// 실제 render evidence 로 판별한다.
//
// 정적 Row 구조만 보고 고치지 않는다 — production 부모 제약을 세우고
// 가장 좁은 폭·가장 큰 배율·대표 정상 셀을 실제로 그려 본 뒤 판정한다.
// 넘침 예외가 없다는 것만으로 PASS 시키지 않는다. surface 마다 핵심 사실이
// **전부 보이는지** 를 같이 단언한다.
//
// 6A 정정: `to_detail_dialogs.dart:164` 는 이 파일에 없다.
//   `TODetailDialogs` 는 lib 전체에서 인스턴스화되지 않는 dead code 였다
//   (R7-P1-2 DEVICE.1H 가 이미 같은 결론을 기록해 뒀다).
//   6A 에서 도달성을 확인하지 않고 A 로 분류한 것이 오류다. NO PATCH.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';

import 'package:ALfit/models/core/application_model.dart';
import 'package:ALfit/models/core/attendance_model.dart';
import 'package:ALfit/models/core/business_model.dart';
import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/models/core/work_detail_data.dart';
import 'package:ALfit/models/ui/day_staffing_row.dart';
import 'package:ALfit/providers/notification_provider.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/screens/business_admin/dialogs/day_applicants_dialog.dart';
import 'package:ALfit/screens/business_admin/dialogs/day_applicants_reads.dart';
import 'package:ALfit/screens/business_admin/dialogs/wage_confirm_dialog.dart';
import 'package:ALfit/screens/business_admin/to_management/widgets/to_date_selector.dart';
import 'package:ALfit/screens/user/income_detail_reads.dart';
import 'package:ALfit/screens/user/income_detail_screen.dart';

// ── Firebase core 가짜 — 실제 읽기·쓰기 없음 ──────────────────────
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

/// 넘침 메시지를 전부 모은다 — `takeException` 은 첫 건만 준다.
class _OverflowCollector {
  final List<String> hits = [];
  void Function(FlutterErrorDetails)? _prev;

  void start() {
    _prev = FlutterError.onError;
    FlutterError.onError = (d) {
      final s = d.exception.toString();
      if (s.contains('overflowed')) {
        // 어느 위젯인지 같이 남긴다 — 수치만으로는 어디를 고칠지 모른다.
        final where = d
            .toString()
            .split('\n')
            .where((l) => l.contains('.dart:'))
            .map((l) => l.trim())
            .take(1)
            .join();
        hits.add('${s.split('\n').first} @ $where');
      } else {
        _prev?.call(d);
      }
    };
  }

  void stop() => FlutterError.onError = _prev;
}

const kBiz = 'biz1';
final kDate = DateTime(2026, 9, 29);

// 요청된 matrix: 가장 좁은 폭 · 가장 큰 배율 · 대표 정상 셀을 반드시 포함한다.
const kCells = <List<double>>[
  [320, 1.0], // 가장 좁음 · 정상 배율
  [320, 2.0], // 가장 좁음 · 가장 큰 배율
  [360, 1.0], // 대표 정상
  [360, 1.3],
  [411, 2.0],
];

// ════════════════════════════════════════════════════════════════
// 1) TODateSelector 헤더 — `근무 날짜 선택` + 선택 일수 + 전체 해제
// ════════════════════════════════════════════════════════════════

/// 선택 일수의 canonical 상한. 두 호출부(`create_to_screen:1931`,
/// `edit_to_screen:1348`) 모두 `maxSelectableDays` 를 넘기지 않으므로
/// 기본값 14 가 실제 상한이다 — `99일` 같은 값은 제품에 존재하지 않는다.
const int kMaxSelectableDays = 14;

List<DateTime> _dates(int n) =>
    List.generate(n, (i) => DateTime(2026, 10, 1).add(Duration(days: i)));

Future<_OverflowCollector> _pumpDateSelector(
  WidgetTester tester, {
  required double width,
  required double textScale,
  required int selectedCount,
}) async {
  final col = _OverflowCollector()..start();
  addTearDown(col.stop);

  tester.view.physicalSize = Size(width, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      builder: (ctx, child) => MediaQuery(
        data: MediaQuery.of(ctx)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Scaffold(
        body: SingleChildScrollView(
          // 실제 화면의 좌우 거터를 유지한다.
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: TODateSelector(
            isLongTerm: false,
            selectedDates: _dates(selectedCount),
            onDateToggle: (_) {},
            onClearAll: () {},
          ),
        ),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 100));
  col.stop();
  return col;
}

// ════════════════════════════════════════════════════════════════
// 2) IncomeDetailScreen 월 네비게이터 — 연/월 + 좌우 이동
// ════════════════════════════════════════════════════════════════

class _Worker extends UserProvider {
  @override
  UserModel? get currentUser => UserModel(
        uid: 'u1',
        username: 'u1',
        name: '김근로',
        email: 'u1@alfit.local',
        role: UserRole.USER,
        createdAt: DateTime(2026, 1, 1),
      );
}

AttendanceModel _att({required int year, required int month}) =>
    AttendanceModel(
      id: 'att1',
      applicationId: 'a1',
      userId: 'u1',
      businessId: kBiz,
      businessName: '강남 물류센터',
      workDate: DateTime(year, month, 10),
      workType: '상하차',
      status: AttendanceModel.statusPresent,
      wageStatus: AttendanceModel.wageConfirmed,
      adminConfirmed: true,
      // 일곱 자리 금액 — 자릿수가 많을수록 넓다.
      finalWage: 1234560,
      checkInAt: DateTime(year, month, 10, 9),
      checkOutAt: DateTime(year, month, 10, 18),
      createdAt: DateTime(year, month, 10),
    );

/// 12월을 쓴다 — `2026년 12월` 이 두 자리 월로 가장 넓다.
const int kIncomeYear = 2026;
const int kIncomeMonth = 12;

IncomeDetailReads _incomeReads() => IncomeDetailReads(
      myApplications: (uid) async => const <ApplicationModel>[],
      myMonthlyAttendances: (
              {required String userId,
              required int year,
              required int month}) async =>
          [_att(year: year, month: month)],
    );

Future<_OverflowCollector> _pumpIncome(
  WidgetTester tester, {
  required double width,
  required double textScale,
}) async {
  final col = _OverflowCollector()..start();
  addTearDown(col.stop);

  tester.view.physicalSize = Size(width, 1800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<UserProvider>(create: (_) => _Worker()),
        ChangeNotifierProvider<NotificationProvider>(
            create: (_) => NotificationProvider()),
      ],
      child: MaterialApp(
        builder: (ctx, child) => MediaQuery(
          data: MediaQuery.of(ctx)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: const IncomeDetailScreen(
          initialYear: kIncomeYear,
          initialMonth: kIncomeMonth,
          reads: null,
        ),
      ),
    ),
  );
  for (var i = 0; i < 25; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  col.stop();
  return col;
}

// ════════════════════════════════════════════════════════════════
// 3) DayApplicantsDialog 통계 요약 — 지원 수 / 확정 수
// ════════════════════════════════════════════════════════════════

class _Owner extends UserProvider {
  @override
  UserModel? get currentUser => UserModel(
        uid: 'owner1',
        username: 'owner1',
        name: '박사장',
        email: 'owner1@alfit.local',
        role: UserRole.BUSINESS_ADMIN,
        businessId: kBiz,
        createdAt: DateTime(2026, 1, 1),
      );
}

BusinessModel _business() => BusinessModel(
      id: kBiz,
      name: '강남 물류센터',
      ownerId: 'owner1',
      businessNumber: '000-00-00000',
      category: '음식점',
      subCategory: '한식',
      address: '서울특별시 강남구 테헤란로 1',
      createdAt: DateTime(2026, 9, 1),
    );

ApplicationModel _app(String id, String uid, String status) => ApplicationModel(
      id: id,
      uid: uid,
      toId: 'to1',
      slotId: 'slot1',
      businessId: kBiz,
      businessName: '강남 물류센터',
      toTitle: '단기 모집',
      selectedWorkType: '상하차',
      wdId: 'wd1',
      startTime: '09:00',
      endTime: '18:00',
      wage: 12000,
      wageType: 'hourly',
      status: status,
      workDate: kDate,
      appliedAt: DateTime(2026, 9, 27),
    );

DayStaffingRow _row(int required, int confirmed, int pending) => DayStaffingRow(
      toId: 'to1',
      toTitle: '단기 모집',
      slotId: 'slot1',
      wdId: 'wd1',
      workType: '상하차',
      startTime: '09:00',
      endTime: '18:00',
      requiredCount: required,
      confirmedCount: confirmed,
      pendingCount: pending,
    );

/// 제품에 지원 수 상한이 없다 — 대규모 사업장의 현실적 stress fixture 를 쓴다.
/// 한 날짜 한 슬롯에 지원 120건·확정 48건은 물류센터 성수기에서 실재한다.
DayApplicantsReads _reads({
  required int pendingN,
  required int confirmedN,
}) {
  final pending = List.generate(
      pendingN, (i) => _app('p$i', 'pu$i', 'PENDING'));
  final confirmed = List.generate(
      confirmedN, (i) => _app('c$i', 'cu$i', 'CONFIRMED'));
  return DayApplicantsReads(
    pendingApplications: ({required date, required businessId, purpose}) async =>
        pending,
    confirmedWorkers: ({required date, required businessId}) async => confirmed,
    dayStaffing: ({required businessId, required dayStartMs}) async =>
        [_row(confirmedN, confirmedN, pendingN)],
    dayInvitations: ({required date, required businessId}) async =>
        const <ApplicationModel>[],
    hasWorkedMap: ({required businessId, required date}) async => const {},
    noShowApplicationIds: ({required businessId, required date}) async =>
        <String>{},
    usersBatch: (uids, {required businessId, purpose}) async => {
      for (final u in uids)
        u: UserModel(
            uid: u,
            username: u,
            name: '근로자 $u',
            email: '$u@test.local',
            role: UserRole.USER),
    },
    weeklyAttendance: (
            {required businessId,
            required weekStart,
            required weekEnd}) async =>
        <String, List<AttendanceModel>>{},
    slotWorkDetailCapacities: (toId, slotId) async => {'wd1': confirmedN},
    slotWorkDetails: (toId, slotId) async => <WorkDetailData>[],
    to: (toId) async => null,
    contractStatusBatch: (ids, {required businessId}) async =>
        <String, String?>{},
  );
}

Future<_OverflowCollector> _pumpDayApplicants(
  WidgetTester tester, {
  required double width,
  required double textScale,
  required int pendingN,
  required int confirmedN,
}) async {
  final col = _OverflowCollector()..start();
  addTearDown(col.stop);

  tester.view.physicalSize = Size(width, 2000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpWidget(
    ChangeNotifierProvider<UserProvider>(
      create: (_) => _Owner(),
      child: MaterialApp(
        builder: (ctx, child) => MediaQuery(
          data: MediaQuery.of(ctx)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: Scaffold(
          body: DayApplicantsDialog(
            key: ValueKey('$width-$textScale-$pendingN-$confirmedN'),
            date: kDate,
            businessIds: const [kBiz],
            businesses: [_business()],
            reads: _reads(pendingN: pendingN, confirmedN: confirmedN),
          ),
        ),
      ),
    ),
  );
  for (var i = 0; i < 30; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  col.stop();
  return col;
}

// ════════════════════════════════════════════════════════════════
// 4) WageConfirmDialog 휴게 배지 — 임금 산정 근거
// ════════════════════════════════════════════════════════════════

/// 계약 휴게 90분. `_formatBreakBadgeText` 가 읽는 값이다.
const int kScheduledBreak = 90;

/// 근무자 카드가 읽는 공고 조건 — 복합키 `workType_start_end`.
Map<String, dynamic> _timeMap() => {
      '상하차_09:00_18:00': <String, dynamic>{
        'breakMinutes': kScheduledBreak,
        'wage': 12000,
        'wageType': 'hourly',
        'requiredCount': 3,
      },
    };

/// 계약보다 짧게 근무한 표본 — 휴게 확인 필요 문구(가장 긴 계열)를 띄운다.
AttendanceModel _shortAtt(String appId) => AttendanceModel(
      id: 'att_$appId',
      applicationId: appId,
      userId: 'wu1',
      businessId: kBiz,
      businessName: '강남 물류센터',
      workDate: kDate,
      workType: '상하차',
      status: AttendanceModel.statusPresent,
      // `_initData` 가 미확정 탭에 올리는 조건 — 둘 다 있어야 카드가 그려진다.
      wageStatus: AttendanceModel.wagePending,
      adminConfirmed: true,
      checkInAt: DateTime(2026, 9, 29, 9),
      // 계약 9시간 중 5시간만 머물렀다 → 휴게 확인 필요 경로.
      checkOutAt: DateTime(2026, 9, 29, 14),
      createdAt: kDate,
    );

Future<_OverflowCollector> _pumpWageConfirm(
  WidgetTester tester, {
  required double width,
  required double textScale,
}) async {
  final col = _OverflowCollector()..start();
  addTearDown(col.stop);

  tester.view.physicalSize = Size(width, 2000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final worker = _app('wa1', 'wu1', 'CONFIRMED');

  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpWidget(
    ChangeNotifierProvider<UserProvider>(
      create: (_) => _Owner(),
      child: MaterialApp(
        builder: (ctx, child) => MediaQuery(
          data: MediaQuery.of(ctx)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: Scaffold(
          body: WageConfirmDialog(
            key: ValueKey('$width-$textScale'),
            date: kDate,
            businessId: kBiz,
            businessName: '강남 물류센터',
            workers: [worker],
            attendanceMap: {worker.id: _shortAtt(worker.id)},
            userMap: {
              'wu1': UserModel(
                  uid: 'wu1',
                  username: 'wu1',
                  name: '김근로',
                  email: 'wu1@test.local',
                  role: UserRole.USER),
            },
            workDetailTimeMap: _timeMap(),
          ),
        ),
      ),
    ),
  );
  for (var i = 0; i < 30; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  col.stop();
  return col;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    FirebasePlatform.instance = _FakeCore();
  });

  // ── 1) TODateSelector ─────────────────────────────────────────
  group('근무 날짜 선택 헤더', () {
    for (final c in kCells) {
      final w = c[0], s = c[1];
      testWidgets('${w.toInt()}dp 배율 $s — 넘침 0 + 제목·일수·해제 전부 보임',
          (tester) async {
        final col = await _pumpDateSelector(tester,
            width: w, textScale: s, selectedCount: kMaxSelectableDays);

        expect(col.hits, isEmpty,
            reason: '${w.toInt()}dp 배율 $s 에서 넘쳤다: ${col.hits}');

        expect(find.text('근무 날짜 선택'), findsOneWidget,
            reason: '제목이 사라졌다');
        expect(find.text('$kMaxSelectableDays일'), findsOneWidget,
            reason: '선택 일수가 사라졌다 — 몇 일을 골랐는지가 핵심 사실이다');
        expect(find.text('전체 해제'), findsOneWidget,
            reason: '전체 해제 action 이 사라졌다');
      });
    }
  });

  // ── 2) IncomeDetailScreen ─────────────────────────────────────
  group('수입 상세 월 네비게이터', () {
    for (final c in kCells) {
      final w = c[0], s = c[1];
      testWidgets('${w.toInt()}dp 배율 $s — 넘침 0 + 연월·금액·이동 전부 보임',
          (tester) async {
        final col = await _pumpIncome(tester, width: w, textScale: s);

        expect(col.hits, isEmpty,
            reason: '${w.toInt()}dp 배율 $s 에서 넘쳤다: ${col.hits}');

        // 선택 연/월이 통째로 남아야 한다 — 두 자리 월이 가장 넓다.
        expect(find.text('$kIncomeYear년 $kIncomeMonth월'), findsOneWidget,
            reason: '선택 연월이 사라졌거나 잘렸다');

        // 월 이동 action 이 눌릴 수 있어야 한다.
        for (final icon in [
          Icons.chevron_left_rounded,
          Icons.chevron_right_rounded
        ]) {
          expect(find.byIcon(icon), findsWidgets,
              reason: '$icon 월 이동 버튼이 사라졌다');
        }
      });
    }
  });

  // ── 3) DayApplicantsDialog ────────────────────────────────────
  group('날짜별 지원자 통계 요약', () {
    // 대표 정상 표본
    for (final c in kCells) {
      final w = c[0], s = c[1];
      testWidgets('${w.toInt()}dp 배율 $s — 넘침 0 (지원 8 / 확정 3)',
          (tester) async {
        final col = await _pumpDayApplicants(tester,
            width: w, textScale: s, pendingN: 8, confirmedN: 3);
        expect(col.hits, isEmpty,
            reason: '${w.toInt()}dp 배율 $s 에서 넘쳤다: ${col.hits}');

        // 지원 수·확정 수는 운영 판단의 근거다 — 좁다고 사라지면 안 된다.
        expect(find.text('지원 8'), findsWidgets, reason: '지원 수가 사라졌다');
        expect(find.text('확정 3'), findsWidgets, reason: '확정 수가 사라졌다');
      });
    }

    // stress — 제품에 상한이 없으므로 성수기 대규모 표본을 따로 둔다.
    testWidgets('320dp 배율 2.0 — 지원 120 / 확정 48 에서도 넘침 0',
        (tester) async {
      final col = await _pumpDayApplicants(tester,
          width: 320, textScale: 2.0, pendingN: 120, confirmedN: 48);
      expect(col.hits, isEmpty, reason: '대규모 표본에서 넘쳤다: ${col.hits}');
      expect(find.text('지원 120'), findsWidgets,
          reason: '세 자리 지원 수가 사라졌다');
      expect(find.text('확정 48'), findsWidgets, reason: '확정 수가 사라졌다');
    });
  });

  // ── 4) WageConfirmDialog ──────────────────────────────────────
  group('급여 확정 휴게 배지', () {
    for (final c in kCells) {
      final w = c[0], s = c[1];
      testWidgets('${w.toInt()}dp 배율 $s — 넘침 0 + 휴게 문구·CTA 보임',
          (tester) async {
        final col = await _pumpWageConfirm(tester, width: w, textScale: s);

        expect(col.hits, isEmpty,
            reason: '${w.toInt()}dp 배율 $s 에서 넘쳤다: ${col.hits}');

        // 휴게시간은 임금 산정 근거다 — 공간 부족으로 숨기지 않는다.
        expect(find.textContaining('휴게'), findsWidgets,
            reason: '휴게 관련 문구가 사라졌다');
        expect(find.textContaining('계약 1.5h 공제 예정'), findsOneWidget,
            reason: '계약 휴게 공제 예정 안내가 사라졌다 — 가장 긴 문구다');

        // 임금 산정에 영향을 주는 값과 결과 금액.
        expect(find.textContaining('12,000원'), findsWidgets,
            reason: '시급 산정 근거가 사라졌다');
        expect(find.text('42,000원'), findsOneWidget,
            reason: '계산된 금액이 사라졌다');

        // 확인 CTA.
        expect(find.textContaining('전체 일괄 확정'), findsOneWidget,
            reason: '일괄 확정 CTA 가 사라졌다');
      });
    }
  });
}
