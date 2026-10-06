// [BOTTOM-SURFACE-FILL] 수입 현황 화면 하단에 남던 빈 영역의 소유자 계약.
//
// 기기 화면에서 빈 상태 아래로 탭바까지 회색 띠가 보였다. 측정해 보니 그
// 띠는 숨은 widget이 예약한 공간이 아니었다 — 흰 섹션 면이 내용 높이에서
// 끝나고, 그 아래는 아무도 그리지 않아 Scaffold 배경색이 드러난 것이었다.
// 띠 높이는 화면 높이에 비례했고(360x640 24.9 / 360x780 164.9 / 360x800
// 184.9) 흰 면의 끝은 557.1로 고정이었다. 즉 **자연스러운 남은 뷰포트**다.
//
// 그래도 그대로 두지 않는다. 전폭 흰 섹션 구성에서 면이 중간에 끊기면
// "여기에 무언가 들어올 자리가 비어 있다"로 읽힌다. 내용이 없다는 말과
// 자리가 비어 있다는 말은 다르다. 그래서 면을 뷰포트 끝까지 잇는다.
//
// 아래 셀은 두 층으로 나뉜다.
//   BSP-01~03, BSP-08 : ViewportFillSurface 자체의 계약
//   BSP-04~07, BSP-09 : 화면에 적용된 결과(빈 상태·실패 상태·배율·하단 inset)
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ALfit/models/core/application_model.dart';
import 'package:ALfit/models/core/attendance_model.dart';
import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/models/core/user_region.dart';
import 'package:ALfit/providers/notification_provider.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/screens/user/income_detail_reads.dart';
import 'package:ALfit/screens/user/income_detail_screen.dart';
import 'package:ALfit/screens/user/wage_detail_screen.dart';
import 'package:ALfit/widgets/common/viewport_fill_surface.dart';
import 'package:ALfit/widgets/user/pending_contract_bar.dart';

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

class _UserDouble extends UserProvider {
  _UserDouble({this.pending = 0});
  final int pending;
  @override
  UserModel? get currentUser => UserModel(
        uid: 'u1',
        username: 'u1',
        name: '테스트하나',
        email: 'u1@alfit.local',
        role: UserRole.USER,
        homeRegion:
            const UserRegion(province: '경기도', city: '평택시', district: '마산리'),
        accountStatus: 'active',
        passVerifiedAt: DateTime.now().subtract(const Duration(days: 30)),
      );
  @override
  bool get isUser => true;
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
  @override
  bool get hasPendingContract => pending > 0;
  @override
  int get pendingContractCount => pending;
}

/// 빈 상태 — 조회는 성공했고 결과가 없다.
IncomeDetailReads _emptyReads() => IncomeDetailReads(
      myApplications: (uid) async => const <ApplicationModel>[],
      myMonthlyAttendances: (
              {required String userId,
              required int year,
              required int month}) async =>
          const <AttendanceModel>[],
    );

/// 실패 상태 — 근태를 못 읽었다. "수입이 없다"로 그려선 안 되는 경우.
IncomeDetailReads _failingReads() => IncomeDetailReads(
      myApplications: (uid) async => const <ApplicationModel>[],
      myMonthlyAttendances: (
              {required String userId,
              required int year,
              required int month}) async =>
          throw Exception('network'),
    );

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
    SharedPreferences.setMockInitialValues({});
  });

  // ───────────────────────────────────────────────────────────────────
  // 1층 — ViewportFillSurface 자체의 계약
  // ───────────────────────────────────────────────────────────────────

  /// 뷰포트 높이를 알고 있는 봉투에 위젯을 올린다. bodyHeight는 Scaffold
  /// body가 받는 높이 — 여기서는 SizedBox로 직접 고정한다.
  Future<void> pumpSurface(
    WidgetTester t, {
    required double bodyHeight,
    required Widget child,
  }) async {
    // 기본 테스트 화면은 800x600 이다 — 뷰포트를 그보다 크게 두려면
    // 화면 자체를 넓혀야 한다. 그러지 않으면 봉투가 600으로 깎인다.
    t.view.physicalSize = Size(400, bodyHeight + 40);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        backgroundColor: const Color(0xFFEEEEEE),
        body: Center(
          child: SizedBox(
            width: 360,
            height: bodyHeight,
            child: ViewportFillSurface(child: child),
          ),
        ),
      ),
    ));
    await t.pump();
  }

  testWidgets('BSP-01 내용이 짧으면 면이 뷰포트 끝까지 이어진다', (t) async {
    const marker = Key('short');
    await pumpSurface(t,
        bodyHeight: 700,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: const [SizedBox(key: marker, height: 120)],
        ));

    final body = t.getRect(find.byType(ViewportFillSurface));
    final surface = t.getRect(find
        .descendant(
            of: find.byType(ViewportFillSurface), matching: find.byType(Column))
        .first);

    // 내용은 120인데 면은 뷰포트 높이다 — 남는 공간의 주인이 면이 됐다.
    expect(t.getRect(find.byKey(marker)).height, 120);
    expect(surface.height, 700);
    expect(surface.bottom, closeTo(body.bottom, 0.5));

    // 자리만 차지하면 소용없다 — 남은 영역에 면 색이 실제로 입혀져야
    // 회색이 드러나지 않는다.
    final painted = find
        .descendant(
            of: find.byType(ViewportFillSurface),
            matching: find.byType(Container))
        .first;
    expect(t.widget<Container>(painted).color, Colors.white,
        reason: '공간만 차지하고 색을 입히지 않으면 회색이 그대로 보인다');
    expect(t.getRect(painted).height, 700);
    expect(t.takeException(), isNull);
  });

  testWidgets('BSP-02 내용이 길면 상한 없이 그대로 넘어가 스크롤된다', (t) async {
    await pumpSurface(t,
        bodyHeight: 700,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: const [SizedBox(height: 2000)],
        ));

    final surface = t.getRect(find
        .descendant(
            of: find.byType(ViewportFillSurface), matching: find.byType(Column))
        .first);
    // 뷰포트로 깎이지 않는다 — minHeight만 줬다는 증거.
    expect(surface.height, 2000);

    final pos = t.state<ScrollableState>(find.byType(Scrollable)).position;
    expect(pos.maxScrollExtent, closeTo(1300, 0.5));
    expect(t.takeException(), isNull);
  });

  testWidgets('BSP-03 남는 높이의 주인은 뷰포트다 — 고정값·화면별 분기가 아니다', (t) async {
    final seen = <double, double>{};
    for (final h in [500.0, 700.0, 900.0]) {
      await pumpSurface(t,
          bodyHeight: h,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: const [SizedBox(height: 120)],
          ));
      seen[h] = t
          .getRect(find
              .descendant(
                  of: find.byType(ViewportFillSurface),
                  matching: find.byType(Column))
              .first)
          .height;
    }
    // 면 높이가 뷰포트를 그대로 따라간다. 어떤 숫자도 코드에 박혀 있지 않다.
    expect(seen, {500.0: 500.0, 700.0: 700.0, 900.0: 900.0});
    expect(t.takeException(), isNull);
  });

  test('BSP-08 소스 계약 — 고정 높이 봉투·상한·intrinsic 패스를 쓰지 않는다', () {
    final src = File('lib/widgets/common/viewport_fill_surface.dart')
        .readAsStringSync();
    // 주석에 든 낱말이 계약 판정을 흔들지 않게 코드만 남긴다.
    final code = src
        .split('\n')
        .where((l) => !l.trimLeft().startsWith('//'))
        .join('\n');

    expect(code.contains('minHeight: viewport.maxHeight'), isTrue,
        reason: '남는 공간의 주인은 뷰포트여야 한다');
    expect(code.contains('Container(color: color'), isTrue,
        reason: '남은 영역에 면 색을 입혀야 한다');
    expect(RegExp(r'\bheight:\s*\d').hasMatch(code), isFalse,
        reason: '고정 높이 봉투 금지');
    expect(code.contains('maxHeight:'), isFalse, reason: '상한을 주면 긴 내용이 깎인다');
    expect(code.contains('IntrinsicHeight'), isFalse,
        reason: '스크롤 본문 전체에 intrinsic 패스를 추가하지 않는다');
    expect(code.contains('FittedBox'), isFalse);
    expect(code.contains('Transform.scale'), isFalse);
    // alignment를 주면 Container가 제약을 가로채 자식이 내용 높이로 줄어든다.
    expect(code.contains('alignment'), isFalse);
  });

  // ───────────────────────────────────────────────────────────────────
  // 2층 — 화면에 적용된 결과
  // ───────────────────────────────────────────────────────────────────

  Future<void> pumpScreen(
    WidgetTester t, {
    Size size = const Size(360, 800),
    double scale = 1.0,
    int pending = 0,
    double bottomInset = 0,
    bool failing = false,
  }) async {
    t.view.physicalSize = size;
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<UserProvider>.value(
              value: _UserDouble(pending: pending)),
          ChangeNotifierProvider<NotificationProvider>(
              create: (_) => NotificationProvider()),
        ],
        child: MaterialApp(
          builder: (ctx, child) => MediaQuery(
            data: MediaQuery.of(ctx).copyWith(
              textScaler: TextScaler.linear(scale),
              padding: EdgeInsets.only(bottom: bottomInset),
              viewPadding: EdgeInsets.only(bottom: bottomInset),
            ),
            child: child!,
          ),
          // 지원자 shell 을 흉내낸다 — 이 화면은 탭 안에서 push 되므로
          // 하단 배너·탭바가 그대로 남는다.
          home: Scaffold(
            body: IncomeDetailScreen(
              initialYear: 2026,
              initialMonth: 10,
              reads: failing ? _failingReads() : _emptyReads(),
            ),
            bottomNavigationBar: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const PendingContractBar(),
                BottomNavigationBar(
                  currentIndex: 0,
                  type: BottomNavigationBarType.fixed,
                  elevation: 0,
                  backgroundColor: Colors.white,
                  items: const [
                    BottomNavigationBarItem(
                        icon: Icon(Icons.home_outlined), label: '홈'),
                    BottomNavigationBarItem(
                        icon: Icon(Icons.work_outline_rounded), label: '일자리'),
                    BottomNavigationBarItem(
                        icon: Icon(Icons.calendar_month_outlined), label: '일정'),
                    BottomNavigationBarItem(
                        icon: Icon(Icons.person_outline_rounded), label: 'MY'),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
    for (var i = 0; i < 20; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
  }

  /// 흰 섹션 면의 바닥.
  ///
  /// 기준점을 `ViewportFillSurface` 가 아니라 `Scrollable` 로 잡는다. 그래야
  /// 봉투를 예전 `SingleChildScrollView` 로 되돌려도 측정이 계속 성립하고,
  /// 셀이 "위젯이 있는가"가 아니라 "면이 어디서 끝나는가"를 말한다.
  double surfaceBottom(WidgetTester t) => t
      .getRect(find
          .descendant(
              of: find.byType(Scrollable), matching: find.byType(Column))
          .first)
      .bottom;

  double navTop(WidgetTester t) =>
      t.getRect(find.byType(BottomNavigationBar)).top;

  testWidgets('BSP-04 빈 상태 — 화면 높이가 달라도 회색 띠가 남지 않는다', (t) async {
    for (final h in [640.0, 780.0, 800.0]) {
      await pumpScreen(t, size: Size(360, h));
      expect(find.text('아직 이번 달 수입이 없어요'), findsOneWidget);
      // 예전에는 각각 24.9 / 164.9 / 184.9px 가 남았다.
      expect(surfaceBottom(t), closeTo(navTop(t), 0.5),
          reason: '화면 높이 ${h.toStringAsFixed(0)} 에서 면이 탭바까지 이어져야 한다');
      expect(t.takeException(), isNull);
    }
  });

  testWidgets('BSP-05 조회 실패 상태에서도 면이 끊기지 않는다', (t) async {
    await pumpScreen(t, size: const Size(360, 800), failing: true);
    // 모르는 것을 없는 것으로 바꾸지 않는다 — 문구는 그대로 실패를 말한다.
    expect(find.text('근무 내역을 불러오지 못했어요'), findsOneWidget);
    expect(find.text('아직 이번 달 수입이 없어요'), findsNothing);
    expect(surfaceBottom(t), closeTo(navTop(t), 0.5));
    expect(t.takeException(), isNull);
  });

  testWidgets('BSP-06 접근성 배율을 키워도 면이 이어지고 넘침이 없다', (t) async {
    for (final scale in [1.0, 1.3, 2.0]) {
      await pumpScreen(t, size: const Size(360, 800), scale: scale);
      expect(surfaceBottom(t), greaterThanOrEqualTo(navTop(t) - 0.5),
          reason: '배율 $scale');
      expect(t.takeException(), isNull, reason: '배율 $scale 에서 넘침');
    }
  });

  testWidgets('BSP-07 하단 시스템 inset — 여백을 두 번 먹지 않는다', (t) async {
    final navHeights = <double, double>{};
    for (final inset in [0.0, 48.0]) {
      await pumpScreen(t, size: const Size(360, 800), bottomInset: inset);
      navHeights[inset] =
          t.getRect(find.byType(BottomNavigationBar)).height;
      // 면은 탭바 위에서 끝난다 — 그 아래를 또 비워 두지 않는다.
      expect(surfaceBottom(t), closeTo(navTop(t), 0.5), reason: 'inset $inset');
      expect(t.takeException(), isNull);
    }
    // inset 은 탭바가 정확히 한 번만 흡수한다.
    expect(navHeights[48.0]! - navHeights[0.0]!, closeTo(48.0, 0.5));
  });

  // ───────────────────────────────────────────────────────────────────
  // 3층 — 같은 구성을 쓰는 이웃 화면
  //
  // 전폭 흰 섹션 + `Container(height: 8, color: AppColors.background)`
  // 구분선 + 회색 Scaffold + 채우지 않는 스크롤 본문. 이 구성을 쓰는 화면은
  // 수입 현황과 급여 상세 둘뿐이고(lib/screens 전수 스캔), 급여 상세는
  // 수입 현황에서 바로 들어가는 다음 화면이다. 한쪽만 고치면 같은 흐름
  // 안에서 면이 끊기는 화면과 이어지는 화면이 섞인다.
  // ───────────────────────────────────────────────────────────────────

  ApplicationModel _wageApp() => ApplicationModel(
        id: 'app1',
        businessId: 'b1',
        businessName: '테스트사업장',
        toTitle: '테스트공고',
        workDate: DateTime(2026, 10, 5),
        startTime: '09:00',
        endTime: '18:00',
        uid: 'u1',
        selectedWorkType: '피킹',
        wage: 12000,
        status: 'CONFIRMED',
        appliedAt: DateTime(2026, 10, 1),
      );

  testWidgets('BSP-10 급여 상세 — 같은 구성이므로 같은 계약을 따른다', (t) async {
    t.view.physicalSize = const Size(360, 800);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: WageDetailScreen(application: _wageApp()),
        bottomNavigationBar: BottomNavigationBar(
          currentIndex: 0,
          type: BottomNavigationBarType.fixed,
          elevation: 0,
          backgroundColor: Colors.white,
          items: const [
            BottomNavigationBarItem(icon: Icon(Icons.home_outlined), label: '홈'),
            BottomNavigationBarItem(
                icon: Icon(Icons.person_outline_rounded), label: 'MY'),
          ],
        ),
      ),
    ));
    await t.pump();

    expect(surfaceBottom(t), closeTo(navTop(t), 0.5),
        reason: '근태가 없는 짧은 급여 상세에서 면이 중간에 끊겼다');
    expect(t.takeException(), isNull);
  });

  test('BSP-11 소스 계약 — 이 구성을 쓰는 화면이 봉투 없이 남아 있지 않다', () {
    String codeOf(String p) => File(p)
        .readAsStringSync()
        .split('\n')
        .where((l) => !l.trimLeft().startsWith('//'))
        .join('\n');

    for (final p in const [
      'lib/screens/user/income_detail_screen.dart',
      'lib/screens/user/wage_detail_screen.dart',
    ]) {
      final code = codeOf(p);
      expect(code.contains('ViewportFillSurface('), isTrue, reason: p);
      expect(RegExp(r'body:\s*SingleChildScrollView').hasMatch(code), isFalse,
          reason: '$p — 봉투를 거치지 않는 스크롤 본문으로 되돌아갔다');
    }

    // 전수 스캔. 같은 구성(회색 Scaffold + 8px 회색 구분선으로 나뉜 전폭
    // 섹션 + 스크롤 본문)의 화면이 새로 생기면 여기서 걸린다.
    //
    // 스크롤 판정을 `body:` 모양으로 하지 않는다 — 관리자 홈처럼
    // `body: SafeArea(RefreshIndicator(SingleChildScrollView(...)))` 로
    // 한 겹 더 감싼 화면을 놓친다. 파일 안에 수직 스크롤이 있는지만 본다.
    //
    // 판별의 핵심은 8px 전폭 구분선이다. 카드-온-회색 화면(관리자 홈·
    // 일자리탭)은 회색이 정상적인 캔버스이므로 고칠 대상이 아니고, 그
    // 화면들은 1px hairline 만 쓴다.
    final offenders = <String>[];
    for (final f in Directory('lib/screens')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))) {
      final code = codeOf(f.path);
      final greyScaffold =
          code.contains('backgroundColor: AppColors.background') ||
              code.contains('backgroundColor: AppColors.grey50');
      final fullBleedSections =
          code.contains('Container(height: 8, color: AppColors.background)');
      // 가로 칩 스트립(`scrollDirection: Axis.horizontal`)은 세지 않는다.
      final verticalScroll = code
          .split('SingleChildScrollView(')
          .skip(1)
          .any((rest) => !rest
              .substring(0, rest.length < 120 ? rest.length : 120)
              .contains('Axis.horizontal'));
      if (greyScaffold &&
          fullBleedSections &&
          verticalScroll &&
          !code.contains('ViewportFillSurface(')) {
        offenders.add(f.path);
      }
    }
    expect(offenders, isEmpty,
        reason: '면이 중간에 끊기는 화면이 남아 있다');
  });

  testWidgets('BSP-09 미서명 계약 배너가 뜨면 면이 그 위에서 끝난다', (t) async {
    await pumpScreen(t, size: const Size(360, 800), pending: 1);
    final bar = t.getRect(find.byType(PendingContractBar));
    expect(bar.height, greaterThan(0), reason: '배너가 보이는 조건이어야 한다');
    // 겹치지 않고, 그 위를 비워 두지도 않는다.
    expect(surfaceBottom(t), closeTo(bar.top, 0.5));
    expect(find.text('아직 이번 달 수입이 없어요'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
}
