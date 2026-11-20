// [E1-HOME-FIRST-ENTRY] 로그인 직후 Home 이 **읽기 전**을 0 건으로 말하지 않는다.
//
// ── 기기에서 본 것 (DEV QA 지원자1) ────────────────────────────────────
//   로그인 직후 Home   `지원 현황 — 아직 지원한 일자리가 없어요`
//                     `지금 지원 가능한 일자리가 없어요`, 오늘 출근 Hero 없음
//   같은 시점 내 지원   전체 8 · 진행중 1 · 확정 5 · 종료 2
//   탭 왕복 후 Home    오늘 10:00 출근 Hero · 주간 확정 점 · 수입 정상
//
// ── 계측으로 가른 원인 (분류 C — 초기 상태) ───────────────────────────
//   `[E1M]` 임시 로그 실측:
//     home.initState            11:34:37.123
//     home.postFrame tourDone   11:34:38.092   ← SharedPreferences 대기
//     load.enter uid=U#42515    11:34:38.097
//     load.await-done apps=8 appsErr=false atts=4 tos=1
//     load.commit apps=8
//   uid 는 **있었고**(분류 A 아님), 조회도 성공했으며(B 아님),
//   seq=1·superseded=false 로 덮어쓰기도 없었다(D 아님).
//   문제는 `initState` 와 첫 `load.enter` 사이 **969ms** 동안
//   `_isLoadingData` 가 false 라 그 창이 SUCCESS_ZERO 로 보인 것이다.
//   `_isLoadingData = true` 는 `_loadHomeData()` **안에서** 비로소 켜진다.
//
//   그래서 고친 것은 둘뿐이다.
//     ① `_isLoadingData` 초기값 true — 읽기 전은 LOADING 이다.
//     ② 지원 현황이 LOADING 을 **먼저** 가른다 — 예전에는 로딩 중에도
//        `검토중 0 · 확정 0` 을 그렸다.
import 'dart:async';
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
import 'package:ALfit/models/core/business_model.dart';
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
import 'support/checkin_contract_fixture.dart';
import 'package:ALfit/services/payroll_correction_service.dart';

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

class _Worker extends UserProvider {
  _Worker({this.uid = 'u1'});
  final String uid;
  @override
  UserModel? get currentUser => UserModel(
        uid: uid,
        username: uid,
        name: 'QA 지원자',
        email: '$uid@alfit.local',
        role: UserRole.USER,
        homeRegion: const UserRegion(province: '경기도', city: '평택시'),
        accountStatus: 'active',
        createdAt: DateTime(2026, 1, 1),
      );
}

// ── fixture ─────────────────────────────────────────────────────────────
DateTime _today() {
  final n = DateTime.now().toUtc().add(const Duration(hours: 9));
  return DateTime.utc(n.year, n.month, n.day);
}

ApplicationModel _app({
  required String id,
  required String status,
  DateTime? workDate,
}) =>
    ApplicationModel(
      id: id,
      uid: 'u1',
      businessId: 'biz1',
      businessName: 'QA 사업장',
      toId: 'to1',
      toTitle: 'QA 공고',
      selectedWorkType: 'QA 분류',
      startTime: '10:00',
      endTime: '11:00',
      workDate: workDate ?? _today(),
      status: status,
      appliedAt: _today().subtract(const Duration(days: 2)),
      wage: 53000,
      wageType: 'daily',
    );

/// 지원서 응답을 **우리가 열어 줄 때까지** 붙잡아 두는 reads.
///   로그인 직후의 "아직 읽지 않음" 창을 테스트가 직접 재현한다.
UserHomeReads _reads({
  required Future<List<ApplicationModel>> apps,
  List<AttendanceModel> attendances = const [],
  List<TOModel> tos = const [],
}) =>
    UserHomeReads(
      // [CONTRACT-DISPATCH-B4] 홈 CTA 는 계약 동의 판정을 함께 본다 — 이 시험의 전제: 오늘 근무 계약은 양측 서명 완료
      myContracts: (uid) async => completedContractsFor(await apps),
      myApplications: (uid) => apps,
      myMonthlyAttendances: (
              {required String userId,
              required int year,
              required int month}) async =>
          attendances,
      publishedTOs: () async => tos,
      pendingIdCardRequests: (uid) async =>
          const <IdCardAccessRequestModel>[],
      myRenewalProposals: () async => const <RenewalProposalModel>[],
      businessById: (id) async => null,
      slotsForTO: (toId) async => const <SlotModel>[],
      invalidatePublishedTOsCache: () {},
      documentCorrections: () async => DocumentCorrectionSurface.empty,
    );

Future<void> _pumpHome(WidgetTester t, UserHomeReads reads) async {
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
      // `UserTabScope` 없이 그리면 섹션이 통째로 빠져 "없음" 문구가
      //   아예 트리에 없다 — 그러면 부정 단정이 거짓으로 통과한다.
      child: MaterialApp(
        home: UserTabScope(
          switchToTab: (_) {},
          switchToTabWithDate: (_, __) {},
          pendingJobDate: null,
          clearPendingJobDate: () {},
          pendingScheduleMonth: null,
          clearPendingScheduleMonth: () {},
          switchToScheduleNow: () {},
          child: UserHomeScreen(reads: reads),
        ),
      ),
    ),
  );
}

/// 화면에 실제로 그려진 문자열.
List<String> _texts(WidgetTester t) => t
    .widgetList<Text>(find.byType(Text))
    .map((w) => w.data ?? '')
    .where((s) => s.isNotEmpty)
    .toList();

const _kEmpty = '아직 지원한 일자리가 없어요';
const _kFirstApply = '원하는 날짜의 일을 찾아 첫 지원을 해보세요';
const _kError = '지원 현황을 불러오지 못했어요';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  setUpAll(() async {
    initializeDateFormatting('ko');
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
  });

  group('[FE-A] 읽기 전은 0 건이 아니다', () {
    testWidgets('FE-1 첫 프레임에서 "지원한 일자리가 없어요" 를 말하지 않는다',
        (t) async {
      final gate = Completer<List<ApplicationModel>>();
      // `pumpWidget` 이 그린 **첫 프레임**이다. postFrame 콜백은 아직 돌지
      //   않았고 `_loadHomeData()` 도 시작 전이다 — 기기에서 969ms 동안
      //   사용자가 본 바로 그 화면.
      await _pumpHome(t, _reads(apps: gate.future));
      final shown = _texts(t).join('\n');
      expect(shown.contains(_kEmpty), isFalse,
          reason: '읽기 전을 "없다"고 단정하면 지원서 8건이 사라진다');
      expect(shown.contains(_kFirstApply), isFalse);
      gate.complete(const <ApplicationModel>[]);
      await t.pumpAndSettle(const Duration(seconds: 2));
    });

    testWidgets('FE-2 로드가 끝날 때까지 "없음" 이 나오지 않는다', (t) async {
      final gate = Completer<List<ApplicationModel>>();
      await _pumpHome(t, _reads(apps: gate.future));
      // 첫 프레임부터 로드가 끝날 때까지 **한 프레임도** "없다"고 하지 않는다.
      //   (테스트의 SharedPreferences 는 즉시 응답하므로 기기에서 969ms 였던
      //    창이 여기서는 1 프레임 미만이다 — 그래서 첫 프레임이 핵심이다.)
      expect(_texts(t).join('\n').contains(_kEmpty), isFalse,
          reason: '첫 프레임부터 "없다"고 말했다');
      for (var i = 0; i < 20; i++) {
        await t.pump(const Duration(milliseconds: 100));
        expect(_texts(t).join('\n').contains(_kEmpty), isFalse,
            reason: '로드가 아직 끝나지 않았는데 "없다"고 말했다');
      }
      gate.complete(const <ApplicationModel>[]);
      await t.pumpAndSettle(const Duration(seconds: 2));
    });

    testWidgets('FE-3 로딩 중에 "검토중 0 · 확정 0" 통계도 그리지 않는다', (t) async {
      final gate = Completer<List<ApplicationModel>>();
      await _pumpHome(t, _reads(apps: gate.future));
      // 첫 프레임 — 섹션 자리는 지키되 숫자를 주장하지 않는다.
      expect(_texts(t).contains('지원 현황'), isTrue,
          reason: '섹션 자리는 지킨다');
      expect(_texts(t).join('\n').contains(_kEmpty), isFalse);
      expect(_texts(t).join('\n').contains(_kFirstApply), isFalse);
      gate.complete(const <ApplicationModel>[]);
      await t.pumpAndSettle(const Duration(seconds: 2));
    });
  });

  group('[FE-B] 읽고 난 뒤에는 사실대로 말한다', () {
    testWidgets('FE-4 지원서가 있으면 "없음" 을 말하지 않는다', (t) async {
      final apps = [
        _app(id: 'a1', status: AppStatus.confirmed),
        _app(id: 'a2', status: AppStatus.pending),
      ];
      await _pumpHome(t, _reads(apps: Future.value(apps)));
      await t.pumpAndSettle(const Duration(seconds: 3));
      expect(_texts(t).join('\n').contains(_kEmpty), isFalse);
    });

    // SUCCESS_ZERO(진짜 0건 → `아직 지원한 일자리가 없어요`)와
    //   ERROR(→ `지원 현황을 불러오지 못했어요`)는
    //   `user_home_content_render_test.dart` 가 **이미** 고정한다(583·593행).
    //   같은 것을 여기서 다시 쓰지 않는다 — 이 파일은 그 표에 없던
    //   **"아직 읽지 않음"** 한 칸만 맡고, 그 칸이 다른 칸을 가리지
    //   않는지는 아래 회귀(기존 파일 전체 통과)로 확인한다.
  });

  group('[FE-C] 상태 계약이 소스에 적혀 있다', () {
    String src() => File('lib/screens/user/user_home_screen.dart')
        .readAsStringSync()
        .replaceAll('\r\n', '\n');

    test('FE-7 `_isLoadingData` 는 true 로 시작한다', () {
      expect(src().contains('bool _isLoadingData = true;'), isTrue,
          reason: 'false 로 되돌리면 읽기 전 창이 다시 SUCCESS_ZERO 가 된다');
    });

    test('FE-8 지원 현황이 LOADING 을 가장 먼저 가른다', () {
      final code = src()
          .split('\n')
          .where((l) => !l.trimLeft().startsWith('//'))
          .join('\n')
          .replaceAll(RegExp(r'\s+'), ' ');
      final loadingAt =
          code.indexOf('if (_isLoadingData && _applications.isEmpty)');
      final errorAt = code.indexOf('_applicationStatusErrorCard(s)');
      final emptyAt = code.indexOf("'아직 지원한 일자리가 없어요'");
      expect(loadingAt, greaterThan(-1));
      expect(loadingAt, lessThan(errorAt),
          reason: 'LOADING 을 ERROR 보다 먼저 가른다');
      expect(loadingAt, lessThan(emptyAt),
          reason: 'LOADING 을 EMPTY 보다 먼저 가른다');
    });

    test('FE-9 폴링·고정 지연을 넣지 않았다', () {
      final code = src();
      expect(code.contains('Timer.periodic'), isFalse);
      expect(RegExp(r'Future\.delayed\(const Duration\(seconds:').hasMatch(code),
          isFalse);
    });
  });
}
