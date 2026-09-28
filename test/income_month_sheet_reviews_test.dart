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
import 'package:ALfit/models/core/monthly_review_model.dart';
import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/models/core/user_region.dart';
import 'package:ALfit/providers/notification_provider.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/screens/user/income_detail_reads.dart';
import 'package:ALfit/screens/user/income_detail_screen.dart';
import 'package:ALfit/screens/user/my_reviews_reads.dart';
import 'package:ALfit/screens/user/my_reviews_screen.dart';
import 'package:ALfit/services/monthly_review_service.dart';

/// [R7-P2-4 P24-I/R] 남아 있던 두 칸만 실행한다.
///   · 수입 상세의 **월 선택 시트 제스처** → 라벨·조회 연월·금액이 같은 달인가
///   · 내 근무 평가의 **본문 렌더** → 빈 목록과 읽기 실패를 구분하는가

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

// ── 수입 상세 ────────────────────────────────────────────────
final _now = DateTime.now();
final int _curY = _now.year;
final int _curM = _now.month;
// 지난달(명시 선택 대상) — 연 경계도 넘는다.
final int _prevY = _curM == 1 ? _curY - 1 : _curY;
final int _prevM = _curM == 1 ? 12 : _curM - 1;

AttendanceModel _att({
  required String id,
  required int year,
  required int month,
  required int finalWage,
}) =>
    AttendanceModel(
      id: id,
      applicationId: 'a1',
      userId: 'u1',
      businessId: 'biz1',
      businessName: '강남 물류센터',
      workDate: DateTime(year, month, 10),
      workType: '상하차',
      status: AttendanceModel.statusPresent,
      wageStatus: AttendanceModel.wageConfirmed,
      adminConfirmed: true,
      finalWage: finalWage,
      checkInAt: DateTime(year, month, 10, 9),
      checkOutAt: DateTime(year, month, 10, 18),
      createdAt: DateTime(year, month, 10),
    );

/// 달마다 **다른 액수** — 잘못된 달을 보면 금액이 어긋난다.
IncomeDetailReads _incomeReads({Map<String, int>? calls}) => IncomeDetailReads(
      myApplications: (uid) async => const <ApplicationModel>[],
      myMonthlyAttendances: (
          {required String userId, required int year, required int month}) async {
        calls?['$year-$month'] = (calls['$year-$month'] ?? 0) + 1;
        if (year == _curY && month == _curM) {
          return [_att(id: 'cur', year: year, month: month, finalWage: 110000)];
        }
        if (year == _prevY && month == _prevM) {
          return [_att(id: 'prev', year: year, month: month, finalWage: 220000)];
        }
        return const <AttendanceModel>[];
      },
    );

Future<void> _pumpIncome(
  WidgetTester tester, {
  required IncomeDetailReads reads,
  Size size = const Size(390, 1800),
  double textScale = 1.0,
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
        home: IncomeDetailScreen(
            initialYear: _curY, initialMonth: _curM, reads: reads),
      ),
    ),
  );
  for (var i = 0; i < 25; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

// ── 내 근무 평가 ──────────────────────────────────────────────
MonthlyReviewModel _review({
  required String id,
  required String businessName,
  required int year,
  required int month,
  int rating = 5,
}) =>
    MonthlyReviewModel(
      id: id,
      reviewKey: 'k_$id',
      reviewType: ReviewType.ADMIN_TO_USER,
      reviewerName: businessName,
      businessId: 'biz_$id',
      businessName: businessName,
      targetUserId: 'u1',
      reviewYear: year,
      reviewMonth: month,
      workDaysInMonth: 5,
      rating: rating,
      isPublished: true,
      createdAt: DateTime(year, month, 28),
    );

MyReviewsReads _reviewReads({
  List<MonthlyReviewModel> records = const [],
  Object? error,
}) =>
    MyReviewsReads(
      reviewsForUserPaged: (
          {required String targetUserId,
          String? startAfterId,
          int pageSize = 30}) async {
        if (error != null) throw error;
        return ReviewPage<MonthlyReviewModel>(records: records, hasMore: false);
      },
    );

Future<void> _pumpReviews(
  WidgetTester tester, {
  required MyReviewsReads reads,
  Size size = const Size(390, 1600),
  double textScale = 1.0,
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
        home: MyReviewsScreen(reads: reads),
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

  // ══════════════════════════════════════════════════════════
  // P24-I — 월 선택 시트 제스처
  // ══════════════════════════════════════════════════════════

  testWidgets('IMS-1 상세는 넘겨받은 달을 라벨·조회·금액으로 일치시킨다',
      (tester) async {
    final calls = <String, int>{};
    await _pumpIncome(tester, reads: _incomeReads(calls: calls));

    expect(tester.takeException(), isNull);
    expect(find.text('$_curY년 $_curM월'), findsOneWidget);
    expect(calls.containsKey('$_curY-$_curM'), isTrue);
    expect(find.textContaining('110,000'), findsWidgets);
    expect(find.textContaining('220,000'), findsNothing);
  });

  testWidgets('IMS-2 월 선택 시트를 **실제로 열어** 다른 달을 고르면 그 달이 된다',
      (tester) async {
    final calls = <String, int>{};
    await _pumpIncome(tester, reads: _incomeReads(calls: calls));

    // 상세 안의 월 버튼 탭 → 기간 선택 바텀시트
    await tester.tap(find.text('$_curY년 $_curM월'));
    for (var i = 0; i < 15; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    // 시트가 열렸는지 — 월 칩이 보인다
    expect(find.text('$_prevM월'), findsWidgets,
        reason: '시트가 열리지 않으면 이 행동은 PASS 가 아니다');

    await tester.tap(find.text('$_prevM월').last);
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    // 라벨·조회 연월·금액이 **같은 달**을 가리킨다.
    expect(find.text('$_prevY년 $_prevM월'), findsOneWidget,
        reason: '고른 달이 머리말이어야 한다');
    expect(calls.containsKey('$_prevY-$_prevM'), isTrue,
        reason: '고른 달로 원장을 다시 읽어야 한다');
    expect(find.textContaining('220,000'), findsWidgets,
        reason: '그 달의 금액이어야 한다');
    expect(find.textContaining('110,000'), findsNothing,
        reason: '이전 달 금액이 남으면 다른 달을 보고 판단한다');
  });

  testWidgets('IMS-3 미래 월은 고를 수 없고 잘못된 조회를 만들지 않는다',
      (tester) async {
    final calls = <String, int>{};
    await _pumpIncome(tester, reads: _incomeReads(calls: calls));

    await tester.tap(find.text('$_curY년 $_curM월'));
    for (var i = 0; i < 15; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    final futureM = _curM == 12 ? null : _curM + 1;
    if (futureM != null) {
      final before = Map<String, int>.from(calls);
      await tester.tap(find.text('$futureM월').last, warnIfMissed: false);
      for (var i = 0; i < 15; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(calls.containsKey('$_curY-$futureM'), isFalse,
          reason: '확정 근무가 없는 미래 월은 조회를 만들지 않는다');
      expect(calls.length, before.length);
    }
  });

  // ══════════════════════════════════════════════════════════
  // P24-R — 내 근무 평가 본문
  // ══════════════════════════════════════════════════════════

  testWidgets('MRV-1 받은 평가가 있으면 어느 사업장의 평가인지 보인다',
      (tester) async {
    await _pumpReviews(
      tester,
      reads: _reviewReads(records: [
        _review(
            id: 'r1', businessName: '강남 물류센터', year: _curY, month: _curM),
        _review(
            id: 'r2', businessName: '역삼 편의점', year: _prevY, month: _prevM),
      ]),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('강남 물류센터'), findsWidgets);
    expect(find.text('역삼 편의점'), findsWidgets,
        reason: '두 사업장의 평가가 한 줄로 섞이면 안 된다');
    expect(find.text('아직 받은 평가가 없습니다'), findsNothing);
  });

  testWidgets('MRV-2 정말 없을 때만 "아직 받은 평가가 없습니다"', (tester) async {
    await _pumpReviews(tester, reads: _reviewReads(records: const []));

    expect(find.text('아직 받은 평가가 없습니다'), findsOneWidget);
    expect(find.text('리뷰를 불러오지 못했습니다'), findsNothing);
  });

  testWidgets('MRV-3 읽기 실패를 "평가 없음"으로 바꾸지 않는다', (tester) async {
    await _pumpReviews(tester, reads: _reviewReads(error: Exception('network')));

    expect(find.text('리뷰를 불러오지 못했습니다'), findsOneWidget);
    expect(find.text('다시 시도'), findsOneWidget);
    expect(find.text('아직 받은 평가가 없습니다'), findsNothing);
  });

  testWidgets('MRV-4 320dp × 2.0 — 긴 사업장명·상태가 예외 없이 그려진다',
      (tester) async {
    await _pumpReviews(
      tester,
      reads: _reviewReads(records: [
        _review(
            id: 'r1',
            businessName: '서울특별시 강남구 테헤란로 물류센터 제2창고',
            year: _curY,
            month: _curM),
      ]),
      size: const Size(320, 1600),
      textScale: 2.0,
    );

    expect(tester.takeException(), isNull);
    expect(find.text('서울특별시 강남구 테헤란로 물류센터 제2창고'), findsWidgets);
  });
}
