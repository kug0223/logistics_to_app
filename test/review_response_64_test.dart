// [.64] 서버 후보 RFU2 의 본인 응답 모양을 앱이 오해하지 않는가 · 공개 기산점 문구.
//
// 근거: RFU2(callableGetReviewsForUser 후보)는 본인에게
//   - 공개 전 리뷰: 머리 정보만(businessId·businessName·reviewYear·reviewMonth·isPublished·createdAt·reviewKey·reviewType·requestId·target*)
//   - 공개 리뷰: 코멘트·재고용 의사·작성 관리자 식별(reviewerId·reviewerName) 없이
//   를 돌려준다(에뮬레이터 실측 c64/rfu64.json). 화면은 그것을 0점·리뷰 없음으로 읽으면 안 된다.
// 공개 계약: 양쪽 제출 즉시(onReviewCreated) 또는 review_requests.deadline(요청을 만든 근무일 + 14일)이 지난 자정 처리.
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
import 'package:ALfit/providers/notification_provider.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/screens/user/my_reviews_reads.dart';
import 'package:ALfit/screens/user/my_reviews_screen.dart';
import 'package:ALfit/services/monthly_review_service.dart';
import 'package:ALfit/services/tooltip_service.dart';

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
  @override
  UserModel? get currentUser => UserModel(
      uid: 'W', username: 'w', name: '김근로', email: 'w@alfit.local', role: UserRole.USER,
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

const _ts = {'_seconds': 1793000000, '_nanoseconds': 0};
// RFU2 본인 응답 실측 키(c64/rfu64.json self.RFU2)
final _pending = <String, dynamic>{'businessId': 'B', 'businessName': '[합성] 사업장', 'createdAt': _ts, 'isPublished': false,
  'requestId': 'R', 'reviewKey': 'k1', 'reviewMonth': 10, 'reviewType': 'ADMIN_TO_USER', 'reviewYear': 2026, 'targetUserId': 'W', 'targetUserName': '김근로'};
final _published = <String, dynamic>{'businessId': 'B', 'businessName': '[합성] 사업장', 'createdAt': _ts, 'improvementTags': ['집중력'], 'isPublished': true,
  'lateDays': 0, 'normalAttendanceDays': 1, 'positiveTags': ['시간 준수'], 'publishedAt': _ts, 'rating': 4, 'requestId': 'R2', 'reviewKey': 'k2',
  'reviewMonth': 9, 'reviewType': 'ADMIN_TO_USER', 'reviewYear': 2026, 'targetUserId': 'W', 'targetUserName': '김근로', 'workDaysInMonth': 1};

String _code(String p) => File(p).readAsStringSync();

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
  });

  test('[P64-a] RFU2 본인 응답 두 모양 모두 파서가 받는다(공개 전 = 미공개 표시, 0점 아님 근거)', () {
    final p = MonthlyReviewModel.tryFromMap(_pending, 'p');
    final q = MonthlyReviewModel.tryFromMap(_published, 'q');
    expect(p, isNotNull);
    expect(p!.isPublished, isFalse);
    expect(q, isNotNull);
    expect((q!.rating, q.wouldRehire, q.comment, q.reviewerId), (4, null, null, null));
  });

  for (final c in const [(Size(392, 1600), 1.0), (Size(320, 1600), 1.3), (Size(392, 1600), 2.0)]) {
    testWidgets('[P64-b] 받은 평가 — 공개 전은 가림(0점·리뷰 없음 아님), 공개는 평점·태그만 · 평균은 공개분만 ${c.$1.width.toInt()}·${c.$2}', (t) async {
      t.view.physicalSize = c.$1;
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.reset);
      final records = [MonthlyReviewModel.tryFromMap(_pending, 'p')!, MonthlyReviewModel.tryFromMap(_published, 'q')!];
      await t.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<UserProvider>(create: (_) => _P()),
          ChangeNotifierProvider<NotificationProvider>(create: (_) => NotificationProvider()),
        ],
        child: MaterialApp(
          builder: (ctx, child) => MediaQuery(data: MediaQuery.of(ctx).copyWith(textScaler: TextScaler.linear(c.$2)), child: child!),
          home: MyReviewsScreen(reads: MyReviewsReads(reviewsForUserPaged: ({required targetUserId, startAfterId, pageSize = 30}) async =>
              ReviewPage(records: records, hasMore: false))),
        ),
      ));
      for (var i = 0; i < 15; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
      expect(t.takeException(), isNull);
      expect(findVisibleText('아직 받은 평가가 없습니다'), findsNothing);
      expect(findVisibleText('4.0'), findsOneWidget, reason: '공개 리뷰 1건만 평균');
      expect(findVisibleTextContaining('관리자가 평가를 작성했습니다'), findsOneWidget, reason: '공개 전은 가림');
      expect(findVisibleTextContaining('시간 준수'), findsOneWidget);
      expect(findVisibleText('재고용'), findsNothing);
      expect(findVisibleText('비고용'), findsNothing);
    });
  }

  test('[P64-c] 공개 문구는 실제 계약(양쪽 제출 즉시 / 요청이 온 근무일 + 14일)', () {
    final tip = _code('lib/services/tooltip_service.dart');
    final adm = _code('lib/widgets/dialogs/monthly_review_dialog.dart');
    final biz = _code('lib/widgets/dialogs/business_review_dialog.dart');
    expect(RegExp("message: '[^']*3일 뒤").hasMatch(tip), isFalse);
    expect(tip.contains('리뷰 요청이 온 근무일로부터 14일이 지난 뒤 공개돼요'), isTrue);
    for (final s in [adm, biz]) {
      expect(RegExp("'[^'\n]*14일 후 자동 공개").hasMatch(s), isFalse);
      expect(s.contains('리뷰 요청이 온 근무일로부터 14일이 지난 뒤 공개'), isTrue);
    }
  });

  for (final c in const [(Size(392, 844), 1.0), (Size(320, 640), 1.3), (Size(392, 844), 2.0)]) {
    testWidgets('[P64-d] 첫 리뷰 안내 창 — 새 문구 넘침 없음 ${c.$1.width.toInt()}·${c.$2}', (t) async {
      t.view.physicalSize = c.$1;
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.reset);
      await t.pumpWidget(MaterialApp(
        builder: (ctx, child) => MediaQuery(data: MediaQuery.of(ctx).copyWith(textScaler: TextScaler.linear(c.$2)), child: child!),
        home: Scaffold(body: Builder(builder: (ctx) => TextButton(onPressed: () => TooltipContents.showFirstReview(ctx), child: const Text('열기')))),
      ));
      await t.runAsync(() => TooltipService.reset(TooltipService.firstReview)); // 앞 크기 실행이 남긴 '이미 봄' 지우기
      await t.tap(find.text('열기'));
      for (var i = 0; i < 10; i++) {
        await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
        await t.pump(const Duration(milliseconds: 100));
      }
      expect(find.byWidgetPredicate((w) => w is Text && (w.data ?? '').replaceAll('⁠', '').contains('양쪽이 모두 작성하면 바로 함께 공개돼요')), findsOneWidget);
      expect(find.byWidgetPredicate((w) => w is Text && (w.data ?? '').replaceAll('⁠', '').contains('상세 코멘트와 재고용 의사는')), findsOneWidget);
      expect(t.takeException(), isNull);
      // 창을 닫아 정적 _pendingKeys 를 비운다(다음 크기 실행에서 다시 뜨게).
      await t.ensureVisible(findVisibleText('확인'));
      await t.tap(findVisibleText('확인'));
      await t.pump(const Duration(milliseconds: 300));
    });
  }
}
