// ignore_for_file: depend_on_referenced_packages, unused_element, unused_import, unused_element_parameter
// [DU329] S009 관리자 통계 캡처 — 하네스는 admin_stats_content_render_test.dart(1–263행)를 글자 그대로 복사했다(_pump 에 캡처 RepaintBoundary 만 추가).
//   단언은 기존 ASC 시험이 맡는다. 여기서는 넘침 0 · 예외 0 만 보고 PNG 를 남긴다(DU1_VQ_PHASE 켬일 때).
import 'support/visible_text.dart';
import 'support/du1_vq_capture.dart';
import 'package:ALfit/theme/role_theme.dart';
import 'dart:io';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';

import 'package:ALfit/models/core/business_member_model.dart';
import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/providers/notification_provider.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/screens/business_admin/admin_month_detail_screen.dart';
import 'package:ALfit/screens/business_admin/admin_stats_screen.dart';
import 'package:ALfit/services/admin_stats_service.dart';

/// [R7-P1-7 후속 P17-S] 통계 **실제 콘텐츠**를 production widget 으로 그린다.
///
///   이전 보고에서 렌더가 막혔던 이유는 화면의 lifecycle 이 아니라
///   `AdminStatsService.getBusinessOptions` 안의 `Future.timeout(15s)` 였다 —
///   가짜 Firebase 에서 Firestore future 가 끝나지 않으면 그 타이머가 남는다.
///   production 에서는 조회가 끝나거나 15초에 타임아웃되며 타이머가 풀리고,
///   화면은 `mounted` 와 `_statsRequestId` 로 늦은 응답을 이미 버린다.
///   그래서 **timeout 을 줄이거나 로딩을 강제 완료하지 않고** reader 만 주입한다.
///   파싱·파생·문구·필터는 전부 화면의 기존 경로를 그대로 지난다.

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

class _AdminProvider extends UserProvider {
  @override
  UserModel? get currentUser => UserModel(
        uid: 'admin1',
        username: 'admin1',
        name: '김관리',
        email: 'a@alfit.local',
        role: UserRole.BUSINESS_ADMIN,
        managedBusinessIds: const ['biz1', 'biz2'],
      );
  @override
  bool get isBusinessAdmin => true;
  @override
  bool get isSubAdmin => false;
  @override
  PermissionCheck checkCurrentBusiness(
          bool Function(MemberPermissions p) check) =>
      PermissionCheck.allowed;
  @override
  PermissionCheck checkForBusiness(
          String businessId, bool Function(MemberPermissions p) check) =>
      PermissionCheck.allowed;
  @override
  bool can(bool Function(MemberPermissions p) check) => true;
}

/// [ADMIN-STATS-CLOSEOUT] 같은 SubAdmin 이 사업장마다 다른 급여 권한(바꿀 수 있음).
class _SubProvider extends UserProvider {
  _SubProvider(this.perms);
  final Map<String, PermissionCheck> perms;
  @override
  UserModel? get currentUser => UserModel(uid: 'sub1', username: 'sub1', name: '박부관리', email: 's@alfit.local', role: UserRole.USER,
      subAdminBusinessIds: perms.keys.toList());
  @override
  bool get isBusinessAdmin => false;
  @override
  bool get isSubAdmin => true;
  @override
  PermissionCheck checkCurrentBusiness(bool Function(MemberPermissions p) check) => PermissionCheck.allowed;
  @override
  PermissionCheck checkForBusiness(String businessId, bool Function(MemberPermissions p) check) =>
      perms[businessId] ?? PermissionCheck.denied;
  @override
  bool can(bool Function(MemberPermissions p) check) => true;
}

const _longName = '서울특별시 강남구 제1물류센터 야간운영팀 상시근무지';

/// 현행 schema 그대로 — 단위는 원(금액) · 건(근무) · 명(고유 인원).
AnnualStatsData _annual({
  int totalWage = 128400000,
  int totalWorkCount = 1472,
  int totalWorkerCount = 63,
  double attendanceRate = 97.4,
  double noShowRate = 1.2,
  AttendanceStatsState attendance = AttendanceStatsState.available,
  List<MonthlyTrend>? trends,
}) =>
    AnnualStatsData(
      year: 2026,
      totalWage: totalWage,
      totalWorkCount: totalWorkCount,
      totalWorkerCount: totalWorkerCount,
      prevYearTotalWage: 98000000,
      prevYearTotalWorkCount: 1200,
      attendanceRecordCount: totalWorkCount == 0 ? 0 : 1500,
      attendanceRate: attendanceRate,
      prevYearAttendanceRate: 95.0,
      rehireRate: 72.5,
      avgRating: 4.6,
      noShowCount: 18,
      noShowRate: noShowRate,
      prevYearNoShowRate: 2.0,
      wageByWorkType: const {'홀서빙': 64200000, '주방 보조': 64200000},
      monthlyTrends: trends ??
          const [
            MonthlyTrend(
                year: 2026, month: 9, workCount: 140, totalWage: 12840000,
                workerCount: 21),
          ],
      exceptions: const [],
      exceptionMonth: 9,
      attendanceStatsState: attendance,
      prevAttendanceStatsState: attendance,
    );

MonthDetailData _detail({
  int totalWage = 12840000,
  List<WorkerMonthSummary>? workers,
}) =>
    MonthDetailData(
      year: 2026,
      month: 9,
      presentCount: 130,
      lateCount: 7,
      absentCount: 3,
      totalWage: totalWage,
      workers: workers ?? const [],
      avgRating: 4.6,
      rehireCount: 12,
      noRehireCount: 3,
      posTagFreq: const {},
      impTagFreq: const {},
      rawAttendance: const [],
      userInfoMap: const {},
    );

/// 주입 reader — 실제 클래스를 상속해 **읽기 세 메서드만** 대체한다.
class _FakeStats extends AdminStatsService {
  _FakeStats({
    this.annual,
    this.detail,
    this.annualError,
    this.detailError,
    this.options = const [
      BusinessOption(id: 'biz1', name: _longName),
      BusinessOption(id: 'biz2', name: '평택 센터'),
    ],
    this.annualByCall,
  });

  final AnnualStatsData? annual;
  final MonthDetailData? detail;
  final Object? annualError;
  final Object? detailError;
  final List<BusinessOption> options;

  /// 호출 n번째 연간 응답 — 늦은 응답 역전 재현용.
  final List<Future<AnnualStatsData>>? annualByCall;

  int annualCalls = 0;
  int detailCalls = 0;
  final List<String?> filtersSeen = [];
  final List<int> yearsSeen = [];

  @override
  Future<List<BusinessOption>> getBusinessOptions(List<String> ids) async =>
      options;

  @override
  Future<AnnualStatsData> getAnnualStats({
    required List<String> businessIds,
    String? filterBusinessId,
    required int year,
  }) {
    final i = annualCalls++;
    filtersSeen.add(filterBusinessId);
    yearsSeen.add(year);
    if (annualByCall != null && i < annualByCall!.length) {
      return annualByCall![i];
    }
    if (annualError != null) {
      return Future<AnnualStatsData>.error(annualError!);
    }
    return Future<AnnualStatsData>.value(annual ?? _annual());
  }

  @override
  Future<MonthDetailData> getMonthDetail({
    required List<String> businessIds,
    String? filterBusinessId,
    required int year,
    required int month,
  }) {
    detailCalls++;
    if (detailError != null) {
      return Future<MonthDetailData>.error(detailError!);
    }
    return Future<MonthDetailData>.value(detail ?? _detail());
  }
}

Future<void> _pump(
  WidgetTester tester,
  Widget home, {
  Size size = const Size(390, 900),
  double textScale = 1.0,
  UserProvider? provider,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    RepaintBoundary(key: _vqKey, child: MultiProvider(
      providers: [
        ChangeNotifierProvider<UserProvider>(create: (_) => provider ?? _AdminProvider()),
        ChangeNotifierProvider<NotificationProvider>(
            create: (_) => NotificationProvider()),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: RoleTheme.businessAdminTheme,
        builder: (ctx, child) => MediaQuery(
          data: MediaQuery.of(ctx)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        // 같은 타입의 화면을 연달아 pump 하면 State 가 재사용돼 시나리오가 섞인다.
        home: KeyedSubtree(key: UniqueKey(), child: home),
      ),
    )),
  );
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// [STATS-TO-ATTENDANCE.27] 여러 낱말 라벨은 낱말 안에서 줄이 바뀌지 않게 WORD JOINER 가 들어간다 —
///   보이는 글자로 찾는다.
Finder _label(String s) => find.byWidgetPredicate(
    (w) => w is Text && (w.data ?? '').replaceAll('\u2060', '') == s);


final GlobalKey _vqKey = GlobalKey();

void main() {
  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
  });

  for (final c in const [(id: 'S009-W', w: 392.0, h: 900.0, s: 1.0), (id: 'S009-B', w: 320.0, h: 640.0, s: 2.0)]) {
    testWidgets('${c.id} 관리자 통계 정상 ${c.w.toInt()}x${c.h.toInt()}@${c.s}', (tester) async {
      await tester.runAsync(vqLoadFonts);
      await _pump(tester, AdminStatsScreen(businessIds: const ['biz1', 'biz2'], service: _FakeStats()),
          size: Size(c.w, c.h), textScale: c.s);
      expect(tester.takeException(), isNull);
      await vqCapture(tester, _vqKey, '${c.id}_1_top', conditions: {'state': '정상(가짜 서비스)', 'viewport': '${c.w.toInt()}x${c.h.toInt()}', 'textScaler': c.s});
      final sc = find.byType(Scrollable).first;
      await tester.drag(sc, Offset(0, -c.h * 0.6));
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(tester.takeException(), isNull);
      await vqCapture(tester, _vqKey, '${c.id}_2_scrolled', conditions: {'state': '정상 · 아래로 0.6 화면', 'viewport': '${c.w.toInt()}x${c.h.toInt()}', 'textScaler': c.s});
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  // [DU333] 실패 본문에 보이는 '다시 시도'(소급 5 채택). 기본 실행에서 단언, DU_BEFORE_OBSERVE=333 이면 있음만 기록.
  for (final e in const [(id: 'S009-E', w: 392.0, h: 900.0, s: 1.0), (id: 'S009-EB', w: 320.0, h: 640.0, s: 2.0)]) {
    testWidgets('${e.id} 관리자 통계 전체 실패 ${e.w.toInt()}x${e.h.toInt()}@${e.s}', (tester) async {
      await tester.runAsync(vqLoadFonts);
      final svc = _FakeStats(annualError: StateError('stats cf down'));
      await _pump(tester, AdminStatsScreen(businessIds: const ['biz1', 'biz2'], service: svc),
          size: Size(e.w, e.h), textScale: e.s);
      expect(tester.takeException(), isNull);
      final beforeObs = Platform.environment['DU_BEFORE_OBSERVE'] == '333';
      final retry = findVisibleText('다시 시도');
      final has = retry.evaluate().isNotEmpty;
      // ignore: avoid_print
      print('${e.id} KNOWN ${has ? 'ok' : 'NG'} 실패 본문 다시 시도 있음 beforeObs=$beforeObs');
      if (!beforeObs) expect(has, isTrue, reason: '${e.id} 실패 본문 다시 시도');
      await vqCapture(tester, _vqKey, e.id == 'S009-E' ? 'S009-E_failure' : 'S009-EB_failure',
          conditions: {'state': '연간 조회 실패', 'viewport': '${e.w.toInt()}x${e.h.toInt()}', 'textScaler': e.s, 'beforeObserve': beforeObs});
      if (has) {
        final btn = find.ancestor(of: retry.first, matching: find.byWidgetPredicate((w) => w is ButtonStyleButton)).first;
        final r = tester.getRect(btn);
        final hit = HitTestResult();
        WidgetsBinding.instance.hitTestInView(hit, r.center, tester.view.viewId);
        final target = hit.path.any((x) => identical(x.target, tester.renderObject(btn)));
        // ignore: avoid_print
        print('${e.id} retry rect=$r h=${r.height.toStringAsFixed(1)} target=$target calls=${svc.annualCalls}');
        expect(r.top >= -0.5 && r.bottom <= e.h + 0.5, isTrue, reason: '${e.id} 다시 시도 화면 안');
        expect(target, isTrue, reason: '${e.id} 다시 시도 hit 대상');
        expect(r.height, greaterThanOrEqualTo(48 - 1e-6));
        final before = svc.annualCalls;
        await tester.tap(btn);
        for (var i = 0; i < 10; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(tester.takeException(), isNull);
        expect(svc.annualCalls, greaterThan(before), reason: '${e.id} 다시 시도가 다시 조회한다');
        expect(findVisibleText('통계를 불러오지 못했습니다'), findsOneWidget, reason: '다시 실패면 같은 실패 상태');
      }
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
