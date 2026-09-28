// [R7-P3-4] 지원자 하위 여정의 shell 전환이 **기능을 잃지 않았는지**.
//
// 홈·일정·일자리·MY·내 지원은 이미 흰 flat 화면인데, 그 아래 네 화면과
// 지원자 설정만 파란 그라디언트 헤더로 열렸다. 헤더만 바꾸고 새로고침 버튼이나
// 미서명 계약 Task 를 잃으면 전환이 아니라 손실이다 — 그걸 여기서 잰다.
//
// 쓰기(출퇴근·정산·탈퇴·계약)는 한 번도 실행하지 않는다.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';

import 'package:ALfit/models/core/application_model.dart';
import 'package:ALfit/models/core/attendance_model.dart';
import 'package:ALfit/models/core/employment_contract_model.dart';
import 'package:ALfit/models/core/monthly_review_model.dart';
import 'package:ALfit/services/monthly_review_service.dart';
import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/providers/notification_provider.dart';
import 'package:ALfit/providers/theme_provider.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/screens/common/settings_screen.dart';
import 'package:ALfit/screens/user/attendance_check_reads.dart';
import 'package:ALfit/screens/user/attendance_check_screen.dart';
import 'package:ALfit/screens/user/interim_settlement_reads.dart';
import 'package:ALfit/screens/user/interim_settlement_request_screen.dart';
import 'package:ALfit/screens/user/my_reviews_reads.dart';
import 'package:ALfit/screens/user/my_reviews_screen.dart';
import 'package:ALfit/screens/user/subadmin_leave_screen.dart';
import 'package:ALfit/widgets/common/app_page_scaffold.dart';
import 'package:ALfit/widgets/common/gradient_scaffold.dart';
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

/// 지원자. 미서명 계약이 있는지를 축으로 둔다 — 계약 바는 장식이 아니라 Task 다.
class _Worker extends UserProvider {
  _Worker({this.pending = false, this.subAdmin = false, this.adminMode = false});
  final bool pending;
  final bool subAdmin;
  final bool adminMode;

  @override
  UserModel? get currentUser => UserModel(
        uid: 'u1',
        username: 'u1',
        name: '김근로',
        email: 'u1@alfit.local',
        role: UserRole.USER,
        subAdminBusinessIds: subAdmin ? const ['biz1'] : const [],
        createdAt: DateTime(2026, 1, 1),
      );
  @override
  bool get isUser => true;
  @override
  bool get isSubAdmin => subAdmin;
  @override
  bool get isBusinessAdmin => false;
  @override
  bool get isSuperAdmin => false;
  @override
  bool get isAdminMode => adminMode;
  @override
  bool get permissionsLoaded => true;
  @override
  bool get hasPendingContract => pending;
  @override
  int get pendingContractCount => pending ? 1 : 0;
  @override
  EmploymentContractModel? get nearestPendingContract => null;
}

Widget _wrap(Widget home, UserProvider up,
        {double textScale = 1.0}) =>
    MultiProvider(
      providers: [
        ChangeNotifierProvider<UserProvider>.value(value: up),
        ChangeNotifierProvider<NotificationProvider>(
            create: (_) => NotificationProvider()),
        ChangeNotifierProvider<ThemeProvider>(create: (_) => ThemeProvider()),
      ],
      child: MaterialApp(
        builder: (ctx, child) => MediaQuery(
          data: MediaQuery.of(ctx)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: home,
      ),
    );

Future<void> _pump(
  WidgetTester tester,
  Widget home, {
  required UserProvider up,
  Size size = const Size(390, 1600),
  double textScale = 1.0,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpWidget(_wrap(home, up, textScale: textScale));
  await tester.pump();
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

AttendanceCheckReads _attReads() => AttendanceCheckReads(
      myApplications: (uid) async => <ApplicationModel>[],
      todayAttendance: ({required userId, required applicationId}) async =>
          null as AttendanceModel?,
    );

MyReviewsReads _revReads() => MyReviewsReads(
      reviewsForUserPaged: (
              {required String targetUserId,
              String? startAfterId,
              int pageSize = 30}) async =>
          ReviewPage<MonthlyReviewModel>(
              records: const [], cursor: null, hasMore: false),
    );

ApplicationModel _settlementApp() => ApplicationModel(
      id: 'a1',
      uid: 'u1',
      toId: 'to1',
      slotId: 'slot1',
      businessId: 'biz1',
      businessName: '강남 물류센터 제2물류동',
      toTitle: '단기 모집',
      selectedWorkType: '상하차',
      wdId: 'wd1',
      startTime: '09:00',
      endTime: '18:00',
      wage: 12000,
      wageType: 'hourly',
      status: 'CONFIRMED',
      workDate: DateTime(2026, 9, 29),
      appliedAt: DateTime(2026, 9, 20),
    );

Finder _appBarIcon(IconData icon) => find.descendant(
      of: find.byType(AppBar), matching: find.byIcon(icon));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
  });

  // ══ 소스 사실 ══════════════════════════════════════════════════════════════

  test('[SHU-0] lib 에 GradientScaffold 실제 호출부가 0 이다', () {
    final offenders = <String>[];
    for (final f in Directory('lib').listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart')) continue;
      if (f.path.replaceAll('\\', '/').endsWith(
          'lib/widgets/common/gradient_scaffold.dart')) continue;
      final code = f
          .readAsStringSync()
          .split('\n')
          .where((l) => !l.trimLeft().startsWith('//'))
          .join('\n');
      if (code.contains('GradientScaffold(')) offenders.add(f.path);
    }
    expect(offenders, isEmpty);
  });

  test('[SHU-0b] 컴포넌트 파일은 남겨 둔다 — 호출부 0 이 삭제 사유가 아니다', () {
    expect(File('lib/widgets/common/gradient_scaffold.dart').existsSync(),
        isTrue);
  });

  // ══ 출퇴근 ════════════════════════════════════════════════════════════════

  testWidgets('[SHU-1] 출퇴근 — flat shell 에서 새로고침·홈·알림이 모두 산다',
      (tester) async {
    await _pump(tester, AttendanceCheckScreen(reads: _attReads()),
        up: _Worker());

    expect(find.byType(AppPageScaffold), findsOneWidget);
    expect(find.byType(GradientScaffold), findsNothing);
    expect(find.text('출퇴근 체크'), findsOneWidget);

    // 우상단 버튼 세 개 — 당겨서 새로고침으로 의미가 바뀌지 않았다.
    expect(find.byIcon(Icons.refresh), findsOneWidget);
    expect(find.byIcon(Icons.home_outlined), findsOneWidget);
    expect(find.byIcon(Icons.notifications_outlined), findsOneWidget);
  });

  testWidgets('[SHU-2] 출퇴근 — 미서명 계약 Task 가 상태대로 뜨고 사라진다',
      (tester) async {
    await _pump(tester, AttendanceCheckScreen(reads: _attReads()),
        up: _Worker(pending: true));
    expect(find.byType(PendingContractBar), findsOneWidget);
    expect(find.text('계약서 서명이 필요해요'), findsOneWidget);

    // 서명할 것이 없으면 거짓 대기를 만들지 않는다.
    await _pump(tester, AttendanceCheckScreen(reads: _attReads()),
        up: _Worker(pending: false));
    expect(find.text('계약서 서명이 필요해요'), findsNothing);
  });

  // ══ 내 리뷰 ═══════════════════════════════════════════════════════════════

  testWidgets('[SHU-3] 내 리뷰 — 제목·액션·계약 바가 그대로다', (tester) async {
    await _pump(tester, MyReviewsScreen(reads: _revReads()),
        up: _Worker(pending: true));

    expect(find.byType(AppPageScaffold), findsOneWidget);
    expect(find.text('내 근무 평가'), findsOneWidget);
    expect(find.byIcon(Icons.refresh), findsOneWidget);
    expect(find.byIcon(Icons.home_outlined), findsOneWidget);
    expect(find.byIcon(Icons.notifications_outlined), findsOneWidget);
    expect(find.text('계약서 서명이 필요해요'), findsOneWidget);
    // 본문 내용도 살아 있다.
    expect(find.text('아직 받은 평가가 없습니다'), findsOneWidget);
  });

  // ══ 중간정산 ═══════════════════════════════════════════════════════════════

  testWidgets('[SHU-7] 중간정산 — 긴 제목·액션·계약 바가 320dp 배율 2.0 에서도 산다',
      (tester) async {
    await _pump(
      tester,
      InterimSettlementRequestScreen(
        app: _settlementApp(),
        reads: InterimSettlementReads(
            myMonthlyAttendances: ({required userId, required year, required month}) async =>
                <AttendanceModel>[]),
      ),
      up: _Worker(pending: true),
      size: const Size(320, 2400),
      textScale: 2.0,
    );

    expect(tester.takeException(), isNull);
    expect(find.byType(AppPageScaffold), findsOneWidget);
    expect(_appBarIcon(Icons.refresh), findsOneWidget);
    expect(_appBarIcon(Icons.home_outlined), findsOneWidget);
    expect(_appBarIcon(Icons.notifications_outlined), findsOneWidget);
    expect(find.text('계약서 서명이 필요해요'), findsOneWidget);
  });

  // ══ 서브관리자 탈퇴 ════════════════════════════════════════════════════════

  testWidgets('[SHU-4] 탈퇴 — 홈·알림은 원래 없었고 지금도 없다', (tester) async {
    await _pump(tester, const SubadminLeaveScreen(),
        up: _Worker(subAdmin: true, pending: true));

    expect(find.byType(AppPageScaffold), findsOneWidget);
    expect(find.text('서브관리자 탈퇴'), findsOneWidget);
    // 되돌릴 수 없는 결정 화면에 옆길을 만들지 않는다 — 전환 전과 같다.
    expect(find.byIcon(Icons.home_outlined), findsNothing);
    expect(find.byIcon(Icons.notifications_outlined), findsNothing);
    expect(find.byIcon(Icons.refresh), findsNothing);
    // 계약 Task 는 유지된다.
    expect(find.text('계약서 서명이 필요해요'), findsOneWidget);
  });

  // ══ 공용 설정 — 역할별 ═════════════════════════════════════════════════════

  testWidgets('[SHU-5] 설정(지원자) — flat 이 되었고 홈·알림·계약 바가 남는다',
      (tester) async {
    await _pump(tester, const SettingsScreen(),
        up: _Worker(pending: true));

    expect(find.byType(AppPageScaffold), findsOneWidget);
    expect(find.byType(GradientScaffold), findsNothing);
    expect(find.text('설정'), findsWidgets);
    // 본문 메뉴에도 같은 아이콘이 있으므로 **AppBar 안**만 센다.
    expect(_appBarIcon(Icons.home_outlined), findsOneWidget);
    expect(_appBarIcon(Icons.notifications_outlined), findsOneWidget);
    // 원래 새로고침은 없었다 — 없던 것을 만들지 않았다.
    expect(_appBarIcon(Icons.refresh), findsNothing);
    expect(find.text('계약서 서명이 필요해요'), findsOneWidget);

    // [R7-P4-1 정정] 이전 기록은 '내 리뷰의 상시 입구가 없다(알림·FCM·관리자
    //   Settings 뿐)' 였다. 사실이 아니다 — 지원자 설정의 showUserItems
    //   블록에 '내 평가 확인' 이 상시 있다. F2/VJ14 의 전제를 여기서 고정한다.
    expect(find.text('내 평가 확인'), findsOneWidget);
  });

  testWidgets('[SHU-6] 설정(서브관리자 관리자 모드) — 없던 버튼을 더하지 않았다',
      (tester) async {
    await _pump(tester, const SettingsScreen(),
        up: _Worker(subAdmin: true, adminMode: true, pending: true));

    expect(find.byType(AppPageScaffold), findsOneWidget);
    // 관리자 경로에는 원래 홈·알림·계약 바가 없었다. 그대로다.
    expect(_appBarIcon(Icons.home_outlined), findsNothing);
    expect(_appBarIcon(Icons.notifications_outlined), findsNothing);
    expect(find.text('계약서 서명이 필요해요'), findsNothing);
  });

  // ══ 좁은 화면·큰 배율 ══════════════════════════════════════════════════════

  for (final size in [const Size(320, 2400), const Size(360, 2400),
      const Size(412, 2400)]) {
    for (final scale in [1.3, 2.0]) {
      testWidgets(
          '[SHU-R] ${size.width.toInt()}dp × $scale — 출퇴근 제목·세 버튼이 산다',
          (tester) async {
        await _pump(tester, AttendanceCheckScreen(reads: _attReads()),
            up: _Worker(pending: true),
            size: size,
            textScale: scale);

        expect(tester.takeException(), isNull);
        expect(find.text('출퇴근 체크'), findsOneWidget);
        expect(find.byIcon(Icons.refresh), findsOneWidget);
        expect(find.byIcon(Icons.home_outlined), findsOneWidget);
        expect(find.byIcon(Icons.notifications_outlined), findsOneWidget);
        expect(find.text('계약서 서명이 필요해요'), findsOneWidget);
      });
    }
  }
}
