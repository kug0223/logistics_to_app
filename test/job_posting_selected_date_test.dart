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
import 'package:ALfit/models/core/business_model.dart';
import 'package:ALfit/models/core/business_work_type_model.dart';
import 'package:ALfit/models/core/slot_model.dart';
import 'package:ALfit/models/core/to_model.dart';
import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/models/core/user_region.dart';
import 'package:ALfit/models/core/work_detail_data.dart';
import 'package:ALfit/models/core/work_detail_model.dart';
import 'package:ALfit/providers/notification_provider.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/screens/common/job_posting_reads.dart';
import 'package:ALfit/screens/common/job_posting_screen.dart';
import 'package:ALfit/utils/format_helper.dart';

/// [R7-P2-2 후속 P22-D] 공고 상세가 **목록에서 고른 하루**를 재조회 결과에서
/// 되찾아 그 날의 업무·임금·정원을 말하는가.
///
///   seed(`to`/`workDetails`)와 재조회 결과를 **일부러 다르게** 주어,
///   무엇이 화면과 지원 판단을 지배하는지 실행으로 본다.

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

class _P extends UserProvider {
  @override
  UserModel? get currentUser => UserModel(
        uid: 'u1',
        username: 'u1',
        name: '김근로',
        email: 'u1@alfit.local',
        role: UserRole.USER,
        homeRegion: const UserRegion(province: '서울특별시', city: '강남구'),
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

enum _Device { kst, utc }

DateTime _kstInstant(int y, int mo, int d) =>
    DateTime.utc(y, mo, d).subtract(const Duration(hours: 9));

/// 기기가 Firestore 값을 읽어들이는 표현.
DateTime _dev(DateTime instant, _Device dv) =>
    dv == _Device.kst ? instant.toLocal() : instant.toUtc();

final _d1 = _kstInstant(2026, 10, 10);
final _d2 = _kstInstant(2026, 10, 11);

WorkDetailData _wd({
  required String id,
  required String type,
  required int wage,
  required int required_,
}) =>
    WorkDetailData(
      wdId: id,
      workType: type,
      workTypeIcon: 'box',
      workTypeColor: '#000000',
      workTypeBackgroundColor: '#FFFFFF',
      wage: wage,
      wageType: 'hourly',
      requiredCount: required_,
      startTime: '09:00',
      endTime: '18:00',
      order: 0,
    );

SlotModel _slot({
  required String id,
  required DateTime date,
  required List<WorkDetailData> details,
  String status = SlotStatus.open,
  int confirmed = 0,
}) =>
    SlotModel(
      id: id,
      toId: 'to1',
      date: date,
      workDetails: details,
      status: status,
      confirmedCount: confirmed,
      createdAt: DateTime(2025),
    );

TOModel _to() => TOModel(
      id: 'to1',
      businessId: 'biz1',
      businessName: '강남 물류센터',
      type: 'flex',
      title: '단기 모집',
      creatorUID: 'admin1',
      status: TOStatus.active,
      deadlineType: 'NONE',
      hoursBeforeStart: 0,
      workDetails: const [],
      totalRequired: 4,
      totalConfirmed: 0,
      totalPending: 0,
      isPublished: true,
      publishMode: 'immediate',
      createdAt: DateTime(2026, 9, 1),
      statusUpdatedAt: DateTime(2026, 9, 1),
    );

BusinessModel _business() => BusinessModel(
      id: 'biz1',
      name: '강남 물류센터',
      ownerId: 'admin1',
      businessNumber: '000-00-00000',
      address: '서울시 강남구',
      category: '물류',
      subCategory: '창고',
      isApproved: true,
      createdAt: DateTime(2025),
    );

JobPostingReads _reads({
  required List<SlotModel> slots,
  Object? slotsError,
  List<WorkDetailModel> seedDetails = const [],
  List<ApplicationModel> myApps = const [],
}) =>
    JobPostingReads(
      toOrFailure: (id) async => (to: _to(), failed: false),
      workDetails: (id) async => seedDetails,
      businessById: (id) async => _business(),
      slots: (id, {bool visibleOnly = true}) async {
        if (slotsError != null) throw slotsError;
        return slots;
      },
      myApplications: (uid) async => myApps,
      businessWorkTypes: (id) async => const <BusinessWorkTypeModel>[],
      applicationOnce: (id) async => null,
    );

Future<void> _pump(
  WidgetTester tester, {
  required JobPostingReads reads,
  DateTime? slotDate,
  Size size = const Size(390, 1600),
  double textScale = 1.0,
  ApplicationModel? myApplication,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 50));
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<UserProvider>(create: (_) => _P()),
        ChangeNotifierProvider<NotificationProvider>(
            create: (_) => NotificationProvider()),
      ],
      child: MaterialApp(
        builder: (ctx, child) => MediaQuery(
          data: MediaQuery.of(ctx)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        // 목록 카드와 같은 모양의 진입 — seed 는 넘기되 상세가 다시 읽는다.
        home: JobPostingScreen(
          to: _to(),
          workDetails: const [],
          slotDate: slotDate,
          myApplication: myApplication,
          reads: reads,
        ),
      ),
    ),
  );
  for (var i = 0; i < 25; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
    await initializeDateFormatting('ko_KR', null);
  });

  // 같은 공고, 날짜별로 **임금·정원이 다른** 업무슬롯.
  List<SlotModel> slotsFor(_Device dv) => [
        _slot(id: 's1', date: _dev(_d1, dv), details: [
          _wd(id: 'wd1', type: '상하차', wage: 11000, required_: 2),
        ]),
        _slot(id: 's2', date: _dev(_d2, dv), details: [
          _wd(id: 'wd2', type: '피킹', wage: 13000, required_: 3),
        ]),
      ];

  for (final dv in _Device.values) {
    final label = dv == _Device.kst ? 'KST 기기' : 'UTC 기기';

    testWidgets('JPD-1 $label · 고른 하루의 업무·임금이 나온다', (tester) async {
      await _pump(
        tester,
        reads: _reads(slots: slotsFor(dv)),
        slotDate: FormatHelper.toKstDate(_d2), // 목록이 넘기는 KST 정규화 키
      );

      expect(tester.takeException(), isNull);
      expect(find.textContaining('10월 11일'), findsWidgets,
          reason: '$label 에서 고른 날짜가 상세의 머리말이어야 한다');
      expect(find.text('피킹'), findsWidgets,
          reason: '그 날짜 슬롯의 업무가 나와야 한다');
      expect(find.text('상하차'), findsNothing,
          reason: '다른 날짜의 업무를 그 날의 것처럼 말하지 않는다');
    });

    testWidgets('JPD-2 $label · 다른 하루를 고르면 그 날의 업무가 나온다',
        (tester) async {
      await _pump(
        tester,
        reads: _reads(slots: slotsFor(dv)),
        slotDate: FormatHelper.toKstDate(_d1),
      );

      expect(find.textContaining('10월 10일'), findsWidgets);
      expect(find.text('상하차'), findsWidgets);
      expect(find.text('피킹'), findsNothing);
    });
  }

  testWidgets('JPD-3 seed 가 비어 있어도 재조회가 화면을 만든다', (tester) async {
    // 카드가 넘긴 workDetails 는 빈 목록이다 — 그래도 그 날짜의 업무가 보인다.
    await _pump(
      tester,
      reads: _reads(slots: slotsFor(_Device.kst), seedDetails: const []),
      slotDate: FormatHelper.toKstDate(_d2),
    );

    expect(find.text('피킹'), findsWidgets,
        reason: '판정 근거는 목적지의 재조회다 — seed 가 아니다');
  });

  testWidgets('JPD-4 슬롯 조회 실패를 "근무 날짜 없음"으로 말하지 않는다',
      (tester) async {
    await _pump(
      tester,
      reads: _reads(slots: const [], slotsError: Exception('slot read failed')),
      slotDate: FormatHelper.toKstDate(_d2),
    );

    expect(tester.takeException(), isNull);
    // ERROR != EMPTY — 실패 상태가 화면에 남는다(`_slotLoadError`).
    final src =
        File('lib/screens/common/job_posting_screen.dart').readAsStringSync();
    expect(src.contains('_slotLoadError = true'), isTrue);
    expect(find.text('피킹'), findsNothing);
  });

  // ══════════════════════════════════════════════════════════
  // D2 — FULL/마감이 기존 약속을 끝난 일로 만들지 않는가
  // ══════════════════════════════════════════════════════════

  ApplicationModel _confirmed() => ApplicationModel(
        id: 'mine1',
        toId: 'to1',
        uid: 'u1',
        businessId: 'biz1',
        businessName: '강남 물류센터',
        toTitle: '단기 모집',
        status: AppStatus.confirmed,
        selectedWorkType: '피킹',
        startTime: '09:00',
        endTime: '18:00',
        wage: 13000,
        workDate: _d2,
        appliedAt: _d1,
      );

  testWidgets('JPD-5 모집중 슬롯은 모집중이라고 말하고 지원 CTA 가 열려 있다',
      (tester) async {
    await _pump(
      tester,
      reads: _reads(slots: slotsFor(_Device.kst)),
      slotDate: FormatHelper.toKstDate(_d2),
    );

    expect(find.text('모집중'), findsWidgets);
    expect(find.text('마감'), findsNothing);
    expect(find.text('마감된 공고입니다'), findsNothing);
  });

  testWidgets('JPD-6 같은 날짜가 FULL 이면 마감이라 말하고 CTA 가 닫힌다',
      (tester) async {
    await _pump(
      tester,
      reads: _reads(slots: [
        _slot(
          id: 's2',
          date: _dev(_d2, _Device.kst),
          details: [_wd(id: 'wd2', type: '피킹', wage: 13000, required_: 3)],
          status: SlotStatus.full,
          confirmed: 3,
        ),
      ]),
      slotDate: FormatHelper.toKstDate(_d2),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('마감된 공고입니다'), findsWidgets,
        reason: 'FULL 이면 지원 CTA 가 닫혀야 한다');
  });

  testWidgets('JPD-7 FULL 이어도 **이미 확정된 내 약속**은 완료·취소로 보이지 않는다',
      (tester) async {
    // 내 지원에서 들어온 경로 — 공고가 마감돼도 내 약속의 CTA 는 지원 CTA 가
    //   아니라 Application 상태의 것이다(`_buildApplicationBottomBar`).
    await _pump(
      tester,
      reads: _reads(
        slots: [
          _slot(
            id: 's2',
            date: _dev(_d2, _Device.kst),
            details: [_wd(id: 'wd2', type: '피킹', wage: 13000, required_: 3)],
            status: SlotStatus.full,
            confirmed: 3,
          ),
        ],
        myApps: [_confirmed()],
      ),
      slotDate: FormatHelper.toKstDate(_d2),
      myApplication: _confirmed(),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('마감된 공고입니다'), findsNothing,
        reason: '모집 마감이 내 확정 근무를 끝난 일로 만들면 안 된다');
    expect(find.text('취소된 지원이에요'), findsNothing);
  });

  for (final size in const [Size(320, 1600), Size(412, 1600)]) {
    for (final scale in const [1.3, 2.0]) {
      testWidgets(
          'JPD-R ${size.width.toInt()}dp × $scale — 날짜·업무·임금이 예외 없이 그려진다',
          (tester) async {
        await _pump(
          tester,
          reads: _reads(slots: [
            _slot(id: 's1', date: _dev(_d2, _Device.kst), details: [
              _wd(
                  id: 'wd2',
                  type: '상하차 및 분류 보조 업무',
                  wage: 1250000,
                  required_: 12),
            ]),
          ]),
          slotDate: FormatHelper.toKstDate(_d2),
          size: size,
          textScale: scale,
        );
        expect(tester.takeException(), isNull);
        expect(find.text('상하차 및 분류 보조 업무'), findsWidgets);
      });
    }
  }
}
