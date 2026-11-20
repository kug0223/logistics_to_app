// [.63] 근로자 본인의 받은 평가 입구 · 관리자 전용 필드 · 작성 창 태그 대조.
//
// 근거: MyReviewsScreen 은 로그인 사용자 uid 로만 callableGetReviewsForUser 를 부른다.
//   서버(DEV 00051)는 본인에게 미공개 리뷰와 코멘트·재고용 의사까지 돌려준다 — 화면이 가린다.
//   태그는 글자 스냅샷이라 대조는 '고른 글자가 지금 그 분류 목록에 있는가' 하나다.
import 'dart:io';

import 'support/visible_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ALfit/models/core/monthly_review_model.dart';
import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/models/core/user_region.dart';
import 'package:ALfit/models/settings/trust_settings_model.dart';
import 'package:ALfit/providers/notification_provider.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/screens/user/my_reviews_reads.dart';
import 'package:ALfit/screens/user/my_reviews_screen.dart';
import 'package:ALfit/services/monthly_review_service.dart';
import 'package:ALfit/widgets/dialogs/business_review_dialog.dart';
import 'package:ALfit/widgets/dialogs/monthly_review_dialog.dart';

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

class _P extends UserProvider {
  _P(this.uid);
  final String uid;
  @override
  UserModel? get currentUser => UserModel(
      uid: uid, username: uid, name: '김근로', email: '$uid@alfit.local', role: UserRole.USER,
      homeRegion: const UserRegion(province: '서울특별시', city: '강남구'), accountStatus: 'active');
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

MonthlyReviewModel _review({required bool published, String comment = '관리자끼리만 보는 메모'}) => MonthlyReviewModel(
    id: 'r1', reviewKey: 'r1', reviewType: ReviewType.ADMIN_TO_USER, reviewerId: 'A', reviewerName: '관리자',
    businessId: 'B', businessName: '[합성] 사업장', targetUserId: 'u1', targetUserName: '김근로',
    reviewYear: 2026, reviewMonth: 10, workDaysInMonth: 1, rating: 4, wouldRehire: false,
    positiveTags: ['옛 태그 T62'], improvementTags: ['집중력'], comment: comment,
    isPublished: published, createdAt: DateTime(2026, 10, 30));

Future<void> _pumpReviews(WidgetTester t, MyReviewsReads reads, {String uid = 'u1', Size size = const Size(392, 1600), double scale = 1.0}) async {
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(const SizedBox.shrink());
  await t.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider<UserProvider>(create: (_) => _P(uid)),
      ChangeNotifierProvider<NotificationProvider>(create: (_) => NotificationProvider()),
    ],
    child: MaterialApp(
      builder: (ctx, child) => MediaQuery(data: MediaQuery.of(ctx).copyWith(textScaler: TextScaler.linear(scale)), child: child!),
      home: MyReviewsScreen(reads: reads),
    ),
  ));
  for (var i = 0; i < 20; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  // 첫 리뷰 안내 툴팁이 탭을 가리지 않게 '이미 봄'으로 둔다.
  setUp(() => SharedPreferences.setMockInitialValues({'tooltip_shown_first_review': true}));
  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
  });

  group('A63 받은 평가', () {
    test('[A63-a] MY 근무 관리에 받은 평가 입구가 하나 있다', () {
      final src = File('lib/screens/user/tabs/user_my_tab.dart').readAsStringSync();
      expect(RegExp("label: '받은 평가'").allMatches(src).length, 1);
      expect(src.contains('const MyReviewsScreen()'), isTrue, reason: '인자 없이 연다 — uid 는 화면이 로그인 사용자에서 읽는다');
    });

    testWidgets('[A63-b] 로그인 사용자 uid 로만 읽고, 공개 리뷰의 태그는 당시 글자 그대로 · 코멘트·재고용 의사는 그리지 않는다', (t) async {
      final asked = <String>[];
      await _pumpReviews(t, MyReviewsReads(reviewsForUserPaged: ({required targetUserId, startAfterId, pageSize = 30}) async {
        asked.add(targetUserId);
        return ReviewPage(records: [_review(published: true)], hasMore: false);
      }), uid: 'u-other-login');
      expect(asked, ['u-other-login']);
      expect(findVisibleTextContaining('옛 태그 T62'), findsOneWidget);
      expect(findVisibleTextContaining('관리자끼리만'), findsNothing);
      expect(findVisibleText('비고용'), findsNothing);
      expect(findVisibleText('재고용'), findsNothing);
    });

    testWidgets('[A63-c] 공개 전 리뷰는 내용을 가린다', (t) async {
      await _pumpReviews(t, MyReviewsReads(reviewsForUserPaged: ({required targetUserId, startAfterId, pageSize = 30}) async =>
          ReviewPage(records: [_review(published: false)], hasMore: false)));
      expect(findVisibleTextContaining('옛 태그 T62'), findsNothing);
    });

    testWidgets('[A63-d] 실패 ≠ 0건 · 다시 시도로 회복', (t) async {
      var fail = true;
      await _pumpReviews(t, MyReviewsReads(reviewsForUserPaged: ({required targetUserId, startAfterId, pageSize = 30}) async {
        if (fail) throw Exception('unavailable');
        return ReviewPage(records: [_review(published: true)], hasMore: false);
      }));
      expect(findVisibleText('리뷰를 불러오지 못했습니다'), findsOneWidget);
      expect(findVisibleText('아직 받은 평가가 없습니다'), findsNothing);
      fail = false;
      await t.tap(findVisibleText('다시 시도'));
      for (var i = 0; i < 10; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
      expect(findVisibleTextContaining('옛 태그 T62'), findsOneWidget);
    });

    testWidgets('[A63-e] 0건은 빈 안내', (t) async {
      await _pumpReviews(t, MyReviewsReads(reviewsForUserPaged: ({required targetUserId, startAfterId, pageSize = 30}) async =>
          const ReviewPage(records: [], hasMore: false)));
      expect(findVisibleText('아직 받은 평가가 없습니다'), findsOneWidget);
    });

    for (final c in const [(Size(392, 844), 1.0), (Size(320, 640), 1.3), (Size(392, 844), 2.0)]) {
      testWidgets('[A63-f] 받은 평가 화면 넘침 없음 ${c.$1.width.toInt()}·${c.$2}', (t) async {
        await _pumpReviews(t, MyReviewsReads(reviewsForUserPaged: ({required targetUserId, startAfterId, pageSize = 30}) async =>
            ReviewPage(records: [_review(published: true), _review(published: false)], hasMore: false)), size: c.$1, scale: c.$2);
        expect(t.takeException(), isNull);
      });
    }
  });

  group('C63 태그 대조', () {
    final latest = ReviewTagsModel(positiveTags: ['시간 준수'], improvementTags: ['집중력'],
        businessPositiveTags: ['급여 정확'], businessImprovementTags: ['업무 과중']);

    test('[C63-a] 분류·방향 목록으로만 본다(다른 분류에 있어도 통과 안 함)', () {
      expect(MonthlyReviewService.unavailableTags(latest, positive: ['시간 준수'], improvement: ['집중력'], business: false), isEmpty);
      expect(MonthlyReviewService.unavailableTags(latest, positive: ['집중력'], improvement: [], business: false), ['집중력']);
      expect(MonthlyReviewService.unavailableTags(latest, positive: ['시간 준수'], improvement: [], business: true), ['시간 준수']);
      expect(MonthlyReviewService.unavailableTags(latest, positive: ['급여 정확'], improvement: ['T62'], business: true), ['T62']);
    });

    Future<int> openAdmin(WidgetTester t, Future<ReviewTagsModel> Function() loadLatest, {Size size = const Size(392, 1800), double scale = 1.0}) async {
      t.view.physicalSize = size;
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.reset);
      await t.pumpWidget(MaterialApp(
        builder: (ctx, child) => MediaQuery(data: MediaQuery.of(ctx).copyWith(textScaler: TextScaler.linear(scale)), child: child!),
        home: Scaffold(body: MonthlyReviewDialog(
          reviewerId: 'A', reviewerName: '관리자', businessId: 'B', businessName: 'QA',
          targetUserId: 'W', targetUserName: '근로자', reviewYear: 2026, reviewMonth: 10, workDaysInMonth: 1, requestId: 'R',
          preloadedTags: ReviewTagsModel(positiveTags: ['시간 준수', 'T62 삭제될 태그'], improvementTags: ['집중력']),
          loadLatestTags: loadLatest,
        )),
      ));
      await t.pump(const Duration(milliseconds: 300));
      return 0;
    }

    Future<void> tapVisible(WidgetTester t, Finder f) async {
      await t.ensureVisible(f);
      await t.pump();
      await t.tap(f);
      await t.pump(const Duration(milliseconds: 200));
    }

    testWidgets('[C63-b] 창을 연 사이 지워진 선택 → 저장하지 않고 무엇이 빠졌는지 알린다 · 남은 선택은 유지', (t) async {
      await openAdmin(t, () async => ReviewTagsModel(positiveTags: ['시간 준수'], improvementTags: ['집중력']));
      await tapVisible(t, findVisibleText('T62 삭제될 태그'));
      await tapVisible(t, findVisibleText('시간 준수'));
      await tapVisible(t, findVisibleText('재고용'));
      await tapVisible(t, findVisibleText('리뷰 작성').last);
      for (var i = 0; i < 5; i++) {
        await t.pump(const Duration(milliseconds: 200));
      }
      expect(findVisibleTextContaining('지금은 고를 수 없는 태그를 선택에서 뺐습니다'), findsOneWidget);
      expect(findVisibleTextContaining('"T62 삭제될 태그"'), findsOneWidget);
      expect(findVisibleText('T62 삭제될 태그'), findsNothing, reason: '최신 목록으로 바뀌었다');
      expect(find.byIcon(Icons.check), findsNWidgets(1), reason: "'시간 준수' 선택은 남는다");
      expect(find.byType(MonthlyReviewDialog), findsOneWidget, reason: '저장 단계로 가지 않았다(서비스 호출 시 가짜 Firebase 가 실패한다)');
    });

    testWidgets('[C63-c] 최신 목록을 못 읽으면 제출하지 않는다(기본 목록으로 바꾸지 않는다)', (t) async {
      await openAdmin(t, () async => throw Exception('unavailable'));
      await tapVisible(t, findVisibleText('시간 준수'));
      await tapVisible(t, findVisibleText('재고용'));
      await tapVisible(t, findVisibleText('리뷰 작성').last);
      await t.pump(const Duration(milliseconds: 500));
      expect(find.byType(MonthlyReviewDialog), findsOneWidget);
      expect(find.byIcon(Icons.check), findsNWidgets(1), reason: '선택은 그대로');
    });

    testWidgets('[C63-d] 사업장 리뷰 창도 같은 대조(사업장 목록 기준)', (t) async {
      t.view.physicalSize = const Size(392, 1800);
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.reset);
      await t.pumpWidget(MaterialApp(home: Scaffold(body: BusinessReviewDialog(
        reviewerId: 'W', businessId: 'B', businessName: 'QA', reviewYear: 2026, reviewMonth: 10, workDaysInMonth: 1, requestId: 'R',
        preloadedTags: ReviewTagsModel(businessPositiveTags: ['급여 정확', '지워질 사업장 태그'], businessImprovementTags: ['업무 과중']),
        loadLatestTags: () async => ReviewTagsModel(businessPositiveTags: ['급여 정확'], businessImprovementTags: ['업무 과중']),
      ))));
      await t.pump(const Duration(milliseconds: 300));
      await tapVisible(t, findVisibleText('지워질 사업장 태그'));
      await tapVisible(t, findVisibleText('네, 좋아요'));
      await tapVisible(t, findVisibleText('리뷰 작성').last);
      for (var i = 0; i < 5; i++) {
        await t.pump(const Duration(milliseconds: 200));
      }
      expect(findVisibleTextContaining('"지워질 사업장 태그"'), findsOneWidget);
    });

    for (final c in const [(Size(392, 844), 1.0), (Size(320, 640), 1.3), (Size(392, 844), 2.0)]) {
      testWidgets('[C63-e] 빠진 선택 안내 넘침 없음 ${c.$1.width.toInt()}·${c.$2}', (t) async {
        await openAdmin(t, () async => ReviewTagsModel(positiveTags: ['시간 준수'], improvementTags: ['집중력']), size: const Size(392, 3200), scale: c.$2);
        t.view.physicalSize = Size(c.$1.width, 3200);
        await tapVisible(t, findVisibleText('T62 삭제될 태그'));
        await tapVisible(t, findVisibleText('재고용'));
        await tapVisible(t, findVisibleText('리뷰 작성').last);
        for (var i = 0; i < 5; i++) {
          await t.pump(const Duration(milliseconds: 200));
        }
        expect(findVisibleTextContaining('지금은 고를 수 없는'), findsOneWidget);
        expect(t.takeException(), isNull);
      });
    }
  });
}
