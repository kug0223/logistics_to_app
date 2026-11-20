// [SIM-FULL-FLEX-HOME] 정원이 찬 flex 공고가 관계 없는 근로자의 홈에 "모집중"으로 보였다
//
// DEVICE(10-18, 원본 APK): DEV 에서 FULL(정원 1·확정 1)인 공고가 홈 추천 카드에
//   "모집중"으로 나왔다. 공고 상세는 "인원 마감"·지원 버튼 비활성으로 정상 차단했다.
//
// 원인: 홈은 읽기를 아끼려고 **내가 활성 지원을 가진 flex 공고의 슬롯만** 읽는다
//   (`_loadRelationSlots`). 관계가 없으면 슬롯을 모르므로 projection 이 "모른다 →
//   남긴다"로 판정하고, flex 카드 배지는 늘 "모집중"이다.
//
// 고친 것: 서버가 FULL 이라고 적은 flex 후보도 슬롯을 읽는다. status 를 정답으로
//   쓰지 않는다 — 읽은 슬롯으로 기존 projection 이 판정한다(status 가 낡았으면 남는다).
//   늘어나는 읽기 = FULL 로 표시된 flex 후보 수(회차당 1회). ACTIVE 공고는 여전히 읽지 않는다.
//
//   HFF-1  FULL + 슬롯도 모두 확정 → 홈에서 빠진다 (반례)
//   HFF-2  ACTIVE + 자리 있음, 관계 없음 → 보이고 슬롯을 읽지 않는다 (대조군 · 읽기 비용)
//   HFF-3  FULL 표시지만 슬롯엔 자리 있음(낡은 status) → 남는다 (status 를 정답으로 쓰지 않음)
//   HFF-4  FULL 인데 슬롯 읽기 실패 → 남는다 (ERROR != EMPTY)
//   HFF-5  FULL 공고 슬롯은 회차당 한 번만 읽는다
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ALfit/models/core/application_model.dart';
import 'package:ALfit/models/core/attendance_model.dart';
import 'package:ALfit/models/core/id_card_access_request_model.dart';
import 'package:ALfit/models/core/renewal_proposal_model.dart';
import 'package:ALfit/models/core/slot_model.dart';
import 'package:ALfit/models/core/to_model.dart';
import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/models/core/user_region.dart';
import 'package:ALfit/models/core/work_detail_data.dart';
import 'package:ALfit/providers/notification_provider.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/screens/user/user_home_reads.dart';
import 'package:ALfit/screens/user/user_home_screen.dart';
import 'support/checkin_contract_fixture.dart';
import 'package:ALfit/services/payroll_correction_service.dart';

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

const _region = UserRegion(province: '서울특별시', city: '강남구', district: '역삼동');

class _UserDouble extends UserProvider {
  @override
  UserModel? get currentUser => UserModel(
        uid: 'u1', username: 'u1', name: '김근로', email: 'u1@alfit.local', role: UserRole.USER,
        homeRegion: _region, accountStatus: 'active', passVerifiedAt: DateTime.now().subtract(const Duration(days: 30)),
      );
  @override
  Future<void> refreshPendingContracts({bool joinInFlight = false}) async {}
}

DateTime _day(int offset) {
  final n = DateTime.now();
  return DateTime(n.year, n.month, n.day).add(Duration(days: offset));
}

String _key(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, "0")}-${d.day.toString().padLeft(2, "0")}';

const _wd = WorkDetailData(wdId: 'wd1', workType: '상하차', wage: 12000, requiredCount: 1, startTime: '10:00', endTime: '11:00');

TOModel _flexTo({required String id, required DateTime date, required String status}) => TOModel(
      id: id, businessId: 'biz1', businessName: '강남 물류센터', businessCity: _region.city, type: 'flex',
      title: '물류센터 상하차 $id', creatorUID: 'admin1', status: status, deadlineType: 'NONE', hoursBeforeStart: 0,
      workDetails: const [_wd], slotDateKeys: [_key(date)], totalSlots: 1, totalRequired: 1,
      totalConfirmed: status == TOStatus.full ? 1 : 0, totalPending: 0, isPublished: true, publishMode: 'immediate',
      createdAt: _day(-2), statusUpdatedAt: _day(-2),
    );

SlotModel _slot(String toId, DateTime date, {required int confirmed}) => SlotModel(
      id: 'slot_$toId', toId: toId, date: date, workDetails: const [_wd],
      workDetailCounts: {'wd1': SlotWorkTypeCount(confirmedCount: confirmed)},
      confirmedCount: confirmed, pendingCount: 0,
      status: confirmed >= 1 ? SlotStatus.full : SlotStatus.open, createdAt: _day(-2),
    );

class _Reads {
  _Reads(this.tos);
  final List<TOModel> tos;
  final List<String> calls = [];
  final Map<String, int> confirmedOf = {};
  final Set<String> failIds = {};
  final Map<String, DateTime> dateOf = {};

  UserHomeReads build() => UserHomeReads(
        slotsForTO: (toId) async {
          calls.add(toId);
          if (failIds.contains(toId)) throw StateError('slot read failed: $toId');
          final d = dateOf[toId];
          if (d == null) return const <SlotModel>[];
          return [_slot(toId, d, confirmed: confirmedOf[toId] ?? 0)];
        },
        myContracts: (uid) async => const [],
        myApplications: (uid) async => const <ApplicationModel>[],
        myMonthlyAttendances: ({required String userId, required int year, required int month}) async => const <AttendanceModel>[],
        publishedTOs: () async => tos,
        pendingIdCardRequests: (uid) async => const <IdCardAccessRequestModel>[],
        invalidatePublishedTOsCache: () {},
        documentCorrections: () async => DocumentCorrectionSurface.empty,
        myRenewalProposals: () async => const <RenewalProposalModel>[],
        businessById: (id) async => null,
      );
}

Future<void> _pumpHome(WidgetTester tester, UserHomeReads reads) async {
  tester.view.physicalSize = const Size(390, 5200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider<UserProvider>.value(value: _UserDouble()),
      ChangeNotifierProvider<NotificationProvider>(create: (_) => NotificationProvider()),
    ],
    child: MaterialApp(home: UserHomeScreen(reads: reads)),
  ));
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

bool _cardShown(WidgetTester tester, String toId) => find.textContaining('물류센터 상하차 $toId').evaluate().isNotEmpty;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
    await initializeDateFormatting('ko_KR', null);
  });
  setUp(() => SharedPreferences.setMockInitialValues({'tour_completed_user_home': true}));

  final d = _day(3);

  testWidgets('HFF-1 FULL + 슬롯도 모두 확정 → 홈 카드에서 빠진다', (tester) async {
    final r = _Reads([_flexTo(id: 'full', date: d, status: TOStatus.full), _flexTo(id: 'open', date: d, status: TOStatus.active)])
      ..dateOf['full'] = d
      ..confirmedOf['full'] = 1;
    await _pumpHome(tester, r.build());
    expect(_cardShown(tester, 'open'), isTrue, reason: '대조군: 자리 있는 공고는 보인다');
    expect(_cardShown(tester, 'full'), isFalse, reason: '정원이 찬 공고를 지원 가능한 일자리로 보이지 않는다');
  });

  testWidgets('HFF-2 ACTIVE + 자리 있음, 관계 없음 → 보이고 슬롯을 읽지 않는다', (tester) async {
    final r = _Reads([_flexTo(id: 'open', date: d, status: TOStatus.active)])..dateOf['open'] = d;
    await _pumpHome(tester, r.build());
    expect(_cardShown(tester, 'open'), isTrue);
    expect(r.calls, isEmpty, reason: 'ACTIVE 후보마다 읽는 구조를 만들지 않는다');
  });

  testWidgets('HFF-3 FULL 표시지만 슬롯엔 자리 있음 → 남는다', (tester) async {
    final r = _Reads([_flexTo(id: 'stale', date: d, status: TOStatus.full)])
      ..dateOf['stale'] = d
      ..confirmedOf['stale'] = 0;
    await _pumpHome(tester, r.build());
    expect(r.calls, ['stale']);
    expect(_cardShown(tester, 'stale'), isTrue, reason: '공고 status 가 아니라 읽은 슬롯이 판정한다');
  });

  testWidgets('HFF-4 FULL 인데 슬롯 읽기 실패 → 남는다 (ERROR != EMPTY)', (tester) async {
    final r = _Reads([_flexTo(id: 'full', date: d, status: TOStatus.full)])
      ..dateOf['full'] = d
      ..failIds.add('full');
    await _pumpHome(tester, r.build());
    expect(_cardShown(tester, 'full'), isTrue, reason: '못 읽은 것을 마감으로 바꾸지 않는다');
  });

  // [SIM-FULL-FLEX-COST] 추가 슬롯 요청 수 = 관계 없는 FULL flex 후보 수. 홈 공고 조회는 최대 50건.
  for (final n in [0, 1, 50]) {
    testWidgets('HFF-6 관계 없는 FULL flex 후보 $n개 → 슬롯 요청 $n회 (ACTIVE 후보는 0회)', (tester) async {
      final tos = [
        for (var i = 0; i < n; i++) _flexTo(id: 'f$i', date: d, status: TOStatus.full),
        for (var i = 0; i < 50 - n; i++) _flexTo(id: 'a$i', date: d, status: TOStatus.active),
      ];
      final r = _Reads(tos);
      for (final t in tos) {
        r.dateOf[t.id] = d;
      }
      await _pumpHome(tester, r.build());
      expect(r.calls.length, n);
      expect(r.calls.every((id) => id.startsWith('f')), isTrue, reason: 'ACTIVE 공고는 읽지 않는다');
    });
  }

  testWidgets('HFF-5 FULL 공고 슬롯은 회차당 한 번만 읽는다', (tester) async {
    final r = _Reads([_flexTo(id: 'full', date: d, status: TOStatus.full)])
      ..dateOf['full'] = d
      ..confirmedOf['full'] = 1;
    await _pumpHome(tester, r.build());
    expect(r.calls, ['full']);
  });
}
