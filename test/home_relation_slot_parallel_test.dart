// [R8-PERFORMANCE.2] 내 활성 flex 공고마다 한 라운드씩 줄 서 있었다
//
// `_loadRelationSlots` 는 내가 활성 지원을 가진 flex 공고의 슬롯을 읽는다.
// 입력은 toId 하나뿐이고 서로의 결과를 보지 않으며, 결과도 전부 모인 뒤에
// 한 번 `_rebuildCaches()` 로 들어간다 — 순서대로 기다릴 이유가 없었다.
//
// 라운드를 합칠 때 위험한 것은 두 가지다.
//   1) 낡은 회차의 응답이 새 회차의 자리에 끼어드는 것.
//      Firestore `get` 은 취소할 수 없으므로 guard 는 **적용만** 막는다.
//      그래서 결과를 지역 맵에 모은 뒤 guard 를 통과한 다음에 반영한다.
//   2) 한 공고의 실패가 다른 공고까지 지우는 것.
//      실패한 공고는 맵에 들어가지 않고, 그것은 `모집 없음`이 아니라
//      `모른다`다 — projection 이 그때 후보를 지우지 않는다.
//
// 고정하는 것
//   HRS-1   공고 1개 — 읽고 반영한다
//   HRS-2   공고 여러 개 — 모두 읽는다
//   HRS-3   한 라운드에서 함께 출발한다 (직렬 회귀 탐지)
//   HRS-4   한 공고 실패가 다른 공고를 지우지 않는다
//   HRS-5   전부 실패해도 `지원 가능한 공고 없음`이 되지 않는다 (ERROR != EMPTY)
//   HRS-6   낡은 회차의 응답이 새 회차를 덮지 않는다
//   HRS-7   활성 관계가 없으면 아예 읽지 않는다 (읽기 수 증가 없음)
//   HRS-8   같은 회차에서 같은 공고를 두 번 읽지 않는다
//   HRS-9   toId ↔ slots 짝이 뒤바뀌지 않는다
//   HRS-10  이 loader 는 첫 렌더를 막지 않는다
//   HRS-11  한 건이 실패해도 나머지 슬롯은 반영된다 (실제 반영 + 격리)
import 'dart:async';

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
import 'package:ALfit/models/core/work_detail_data.dart';
import 'package:ALfit/providers/notification_provider.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/screens/user/user_home_reads.dart';
import 'package:ALfit/screens/user/user_home_screen.dart';
import 'package:ALfit/models/core/user_region.dart';
import 'package:ALfit/services/payroll_correction_service.dart';

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
  Future<FirebaseAppPlatform> initializeApp({
    String? name,
    FirebaseOptions? options,
  }) async =>
      _FakeApp();
  @override
  List<FirebaseAppPlatform> get apps => [_FakeApp()];
}

class _UserDouble extends UserProvider {
  _UserDouble({this.uid = 'u1'});
  final String uid;
  static const _region =
      UserRegion(province: '서울특별시', city: '강남구', district: '역삼동');
  @override
  UserModel? get currentUser => UserModel(
        uid: uid,
        username: uid,
        name: '김근로',
        email: '$uid@alfit.local',
        role: UserRole.USER,
        homeRegion: _region,
        accountStatus: 'active',
        passVerifiedAt: DateTime.now().subtract(const Duration(days: 30)),
      );
  @override
  Future<void> refreshPendingContracts() async {}
}

const _biz = 'biz1';
DateTime _day(int offset) {
  final n = DateTime.now();
  return DateTime(n.year, n.month, n.day).add(Duration(days: offset));
}

String _key(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, "0")}-${d.day.toString().padLeft(2, "0")}';

TOModel _flexTo({required String id, required DateTime date}) => TOModel(
      id: id,
      businessId: _biz,
      businessName: '강남 물류센터',
      businessCity: _UserDouble._region.city,
      type: 'flex',
      title: '물류센터 상하차 $id',
      creatorUID: 'admin1',
      status: TOStatus.active,
      deadlineType: 'NONE',
      hoursBeforeStart: 0,
      workDetails: const [],
      slotDateKeys: [_key(date)],
      totalRequired: 4,
      totalConfirmed: 0,
      totalPending: 0,
      isPublished: true,
      publishMode: 'immediate',
      createdAt: _day(-2),
      statusUpdatedAt: _day(-2),
    );

ApplicationModel _activeApp({
  required String id,
  required String toId,
  required DateTime date,
}) =>
    ApplicationModel(
      id: id,
      toId: toId,
      slotId: 'slot_$toId',
      wdId: 'wd1',
      businessId: _biz,
      businessName: '강남 물류센터',
      toTitle: '물류센터 상하차',
      uid: 'u1',
      applicantName: '김근로',
      status: 'PENDING',
      appliedAt: _day(-1),
      workDate: date,
      selectedWorkType: '상하차',
      startTime: '09:00',
      endTime: '18:00',
      wage: 12000,
      wageType: 'hourly',
    );

SlotModel _slot({required String toId, required DateTime date, bool closed = false}) => SlotModel(
      id: 'slot_$toId',
      toId: toId,
      date: date,
      workDetails: const <WorkDetailData>[],
      confirmedCount: 0,
      pendingCount: 0,
      status: closed ? SlotStatus.closed : SlotStatus.open,
      createdAt: _day(-2),
    );

/// 슬롯 읽기 경계 — 호출 순서·동시성·실패를 여기서 만든다.
class _SlotReads {
  _SlotReads({required this.tos, required this.apps});

  final List<TOModel> tos;
  final List<ApplicationModel> apps;

  /// 호출된 toId 순서.
  final List<String> calls = [];

  /// 열어 줄 때까지 모든 슬롯 응답을 붙잡는다.
  Completer<void>? gate;

  /// 실패시킬 toId.
  final Set<String> failIds = {};

  /// 닫힌 슬롯을 돌려줄 toId — 그 날짜 후보에서 빠져야 한다.
  final Set<String> closedIds = {};

  /// toId → 돌려줄 날짜 (짝이 맞는지 확인용)
  final Map<String, DateTime> slotDateOf = {};

  List<ApplicationModel> Function()? appsOverride;

  UserHomeReads build() => UserHomeReads(
        slotsForTO: (toId) async {
          calls.add(toId);
          if (gate != null) await gate!.future;
          if (failIds.contains(toId)) {
            throw StateError('slot read failed: $toId');
          }
          final d = slotDateOf[toId];
          if (d == null) return const <SlotModel>[];
          return [_slot(toId: toId, date: d, closed: closedIds.contains(toId))];
        },
        myApplications: (uid) async => appsOverride?.call() ?? apps,
        myMonthlyAttendances: (
                {required String userId,
                required int year,
                required int month}) async =>
            const <AttendanceModel>[],
        publishedTOs: () async => tos,
        pendingIdCardRequests: (uid) async =>
            const <IdCardAccessRequestModel>[],
        invalidatePublishedTOsCache: () {},
        documentCorrections: () async => DocumentCorrectionSurface.empty,
        myRenewalProposals: () async => const <RenewalProposalModel>[],
        businessById: (id) async => null,
      );
}

Future<void> _pumpHome(WidgetTester tester, UserHomeReads reads,
    {UserProvider? provider, Size size = const Size(390, 900)}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider<UserProvider>.value(
          value: provider ?? _UserDouble()),
      ChangeNotifierProvider<NotificationProvider>(
          create: (_) => NotificationProvider()),
    ],
    child: MaterialApp(home: UserHomeScreen(reads: reads)),
  ));
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

String _texts(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text))
    .map((t) => t.data ?? t.textSpan?.toPlainText() ?? '')
    .where((s) => s.isNotEmpty)
    .join(' | ');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
    await initializeDateFormatting('ko_KR', null);
  });

  setUp(() {
    // 투어 확인이 로드보다 앞에 있다 — 그 await 가 막히면 로드가 시작조차
    //   하지 않는다. 투어는 이미 본 상태로 둔다.
    SharedPreferences.setMockInitialValues(
        {'tour_completed_user_home': true});
  });

  final d = _day(3);

  _SlotReads oneTo() {
    final r = _SlotReads(
      tos: [_flexTo(id: 'toA', date: d)],
      apps: [_activeApp(id: 'a1', toId: 'toA', date: d)],
    );
    r.slotDateOf['toA'] = d;
    return r;
  }

  _SlotReads threeTos() {
    final r = _SlotReads(
      tos: [
        _flexTo(id: 'toA', date: d),
        _flexTo(id: 'toB', date: d),
        _flexTo(id: 'toC', date: d),
      ],
      apps: [
        _activeApp(id: 'a1', toId: 'toA', date: d),
        _activeApp(id: 'a2', toId: 'toB', date: d),
        _activeApp(id: 'a3', toId: 'toC', date: d),
      ],
    );
    for (final id in ['toA', 'toB', 'toC']) {
      r.slotDateOf[id] = d;
    }
    return r;
  }

  testWidgets('HRS-1 공고 1개 — 읽고 반영한다', (tester) async {
    final r = oneTo();
    await _pumpHome(tester, r.build());
    await _settle(tester);
    expect(r.calls, ['toA']);
  });

  testWidgets('HRS-2 공고 여러 개 — 모두 읽는다', (tester) async {
    final r = threeTos();
    await _pumpHome(tester, r.build());
    await _settle(tester);
    expect(r.calls.toSet(), {'toA', 'toB', 'toC'});
    expect(r.calls.length, 3, reason: '같은 공고를 두 번 읽지 않는다');
  });

  testWidgets('HRS-3 한 라운드에서 함께 출발한다', (tester) async {
    final r = threeTos()..gate = Completer<void>();
    await _pumpHome(tester, r.build());
    // 아무 응답도 돌려주지 않은 상태 — 직렬이면 첫 건만 출발해 있다.
    await _settle(tester);
    expect(r.calls.length, 3,
        reason: '직렬이면 첫 응답 전에 두 번째가 출발하지 못한다');
    r.gate!.complete();
    await _settle(tester);
  });

  testWidgets('HRS-4 한 공고 실패가 다른 공고를 지우지 않는다', (tester) async {
    final r = threeTos()..failIds.add('toB');
    await _pumpHome(tester, r.build());
    await _settle(tester);
    expect(r.calls.toSet(), {'toA', 'toB', 'toC'},
        reason: '실패가 나머지 조회를 중단시키지 않는다');
    expect(_texts(tester).contains('지원 가능한 일자리가 없어요'), isFalse);
  });

  testWidgets('HRS-5 전부 실패해도 후보가 사라지지 않는다 (ERROR != EMPTY)',
      (tester) async {
    final r = threeTos()..failIds.addAll(['toA', 'toB', 'toC']);
    await _pumpHome(tester, r.build());
    await _settle(tester);
    // 슬롯을 모르면 후보를 지우지 않는다 —
    // HomeRecruitableProjection._flexRecruitableOn 의 계약.
    expect(_texts(tester).contains('지원 가능한 일자리가 없어요'), isFalse,
        reason: '못 읽은 것을 모집 없음으로 바꾸지 않는다');
  });

  testWidgets('HRS-6 낡은 회차의 응답이 새 회차를 덮지 않는다', (tester) async {
    // 1회차는 붙잡아 두고, 그 사이 계정이 바뀌면 superseded 가 된다.
    final r = threeTos()..gate = Completer<void>();
    final provider = _UserDouble();
    await _pumpHome(tester, r.build(), provider: provider);
    await _settle(tester);
    expect(r.calls.length, 3);
    // 붙잡힌 응답을 지금 풀어 준다. 화면은 이미 dispose 됐다 —
    // 적용 단계가 guard 를 통과하면 안 된다.
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    r.gate!.complete();
    await _settle(tester);
    // 여기서 예외가 없어야 한다(= dispose 뒤 setState 금지).
    expect(tester.takeException(), isNull);
  });

  testWidgets('HRS-7 활성 관계가 없으면 아예 읽지 않는다', (tester) async {
    final r = _SlotReads(
      tos: [_flexTo(id: 'toA', date: d), _flexTo(id: 'toB', date: d)],
      apps: const <ApplicationModel>[],
    );
    await _pumpHome(tester, r.build());
    await _settle(tester);
    expect(r.calls, isEmpty,
        reason: '후보 공고 수만큼 읽는 구조를 만들지 않는다');
  });

  testWidgets('HRS-8 같은 회차에서 같은 공고를 두 번 읽지 않는다', (tester) async {
    // 같은 공고에 활성 관계가 둘 — 읽기는 한 번이어야 한다.
    final r = _SlotReads(
      tos: [_flexTo(id: 'toA', date: d)],
      apps: [
        _activeApp(id: 'a1', toId: 'toA', date: d),
        _activeApp(id: 'a2', toId: 'toA', date: _day(4)),
      ],
    );
    r.slotDateOf['toA'] = d;
    await _pumpHome(tester, r.build());
    await _settle(tester);
    expect(r.calls, ['toA']);
  });

  testWidgets('HRS-9 toId ↔ slots 짝이 뒤바뀌지 않는다', (tester) async {
    // toA 의 슬롯만 그 날짜에 있고 toB 는 다른 날짜다.
    // 짝이 바뀌면 그 날짜 판정이 공고를 서로 바꿔 쓴다.
    final r = threeTos();
    r.slotDateOf['toB'] = _day(9);
    r.slotDateOf['toC'] = _day(9);
    await _pumpHome(tester, r.build());
    await _settle(tester);
    expect(r.calls.toSet(), {'toA', 'toB', 'toC'});
    expect(tester.takeException(), isNull);
  });

  testWidgets('HRS-11 한 건이 실패해도 나머지 슬롯은 반영된다',
      (tester) async {
    // toA 슬롯은 닫혀 있고, toB 조회는 **실패**한다. 같은 날짜에 둘 다 관계가 있다.
    //   올바르면: toA 는 닫힘으로 빠지고 toB 는 모름으로 남아 그 날 후보 1개.
    //   호출별 catch 가 없으면 Future.wait 가 던져 **toA 반영까지 사라지고**
    //   둘 다 모름이 되어 2개가 된다 — 한 건 실패가 다른 건을 지우는 것이다.
    final r = _SlotReads(
      tos: [_flexTo(id: 'toA', date: d), _flexTo(id: 'toB', date: d)],
      apps: [
        _activeApp(id: 'a1', toId: 'toA', date: d),
        _activeApp(id: 'a2', toId: 'toB', date: d),
      ],
    );
    r.slotDateOf['toA'] = d;
    r.slotDateOf['toB'] = d;
    r.closedIds.add('toA');
    r.failIds.add('toB');

    await _pumpHome(tester, r.build(), size: const Size(390, 5200));
    await _settle(tester);

    // 날짜 CTA 는 칩을 고른 뒤에 선다(기존 UHR-41 과 같은 경로).
    final cta = find.textContaining('${d.month}월 ${d.day}일 일자리');
    final chips = find.text('${d.day}');
    expect(chips, findsWidgets, reason: '날짜 띠에 그 날 칩이 있어야 한다');
    for (var k = 0; k < chips.evaluate().length; k++) {
      await tester.tap(chips.at(k), warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 400));
      if (cta.evaluate().isNotEmpty) break;
    }
    expect(cta, findsWidgets, reason: '날짜 CTA 가 서야 수치를 읽을 수 있다');
    final t = _texts(tester);
    expect(t.contains('${d.month}월 ${d.day}일 일자리 1개'), isTrue,
        reason: 'toB 실패와 무관하게 toA 의 닫힘은 반영돼야 한다 — 2개면 전체가 날아갔다');
  });

  testWidgets('HRS-10 이 loader 는 첫 렌더를 막지 않는다', (tester) async {
    final r = threeTos()..gate = Completer<void>();
    await _pumpHome(tester, r.build());
    // 슬롯 응답을 하나도 주지 않았는데도 홈 골격이 그려져야 한다.
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(UserHomeScreen), findsOneWidget);
    expect(_texts(tester).isNotEmpty, isTrue,
        reason: '슬롯을 기다리며 빈 화면으로 멈추지 않는다');
    r.gate!.complete();
    await _settle(tester);
  });
}
