// [.62] SA 리뷰 태그 설정 → 작성 창 → 리뷰 카드.
//
// 근거: 리뷰는 태그를 **글자 그대로** 저장한다(monthly_reviews.positiveTags/improvementTags).
//   onReviewCreated(DEV 00118)·통계 함수는 태그를 읽지 않는다(평점·재고용만). 그래서
//   설정 변경은 과거 리뷰를 바꾸지 않고, 결함은 설정 화면의 덮어쓰기·읽기 실패와 표시에 있다.
import 'support/visible_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';

import 'package:ALfit/models/core/monthly_review_model.dart';
import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/models/settings/trust_settings_model.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/screens/super_admin/review_tags_settings_screen.dart';
import 'package:ALfit/widgets/common/review_card.dart';
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

class _Super extends UserProvider {
  @override
  UserModel? get currentUser => UserModel(
      uid: 'sa1', username: 'sa1', name: '운영자', email: 'sa@alfit.local',
      role: UserRole.SUPER_ADMIN, createdAt: DateTime(2026, 1, 1));
  @override
  bool get isSuperAdmin => true;
  @override
  bool get isBusinessAdmin => false;
  @override
  bool get isSubAdmin => false;
  @override
  bool get isAdminMode => true;
  @override
  bool get permissionsLoaded => true;
}

/// 서버 문서 흉내 — 다른 SA 의 변경을 끼워 넣을 수 있다.
class _Store {
  _Store(Map<String, List<String>> init) : data = {for (final e in init.entries) e.key: [...e.value]};
  final Map<String, List<String>> data;
  int reads = 0;
  final calls = <String>[];
  Object? failNext;
  Future<Map<String, dynamic>?> load() async { reads++; return {for (final e in data.entries) e.key: [...e.value]}; }
  Future<void> mutate(String field, String tag, {required bool add}) async {
    calls.add('${add ? '+' : '-'}$field:$tag');
    if (failNext != null) { final e = failNext; failNext = null; throw e!; }
    final l = data.putIfAbsent(field, () => []);
    add ? (l.contains(tag) ? null : l.add(tag)) : l.remove(tag);
  }
}

const _long = '야간 물류 상하차 작업 지시를 정확하게 따름';

Future<void> _pump(WidgetTester t, {Future<Map<String, dynamic>?> Function()? load, _Store? store,
    Size size = const Size(392, 1600), double scale = 1.0}) async {
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(const SizedBox.shrink());
  await t.pumpWidget(ChangeNotifierProvider<UserProvider>(
    create: (_) => _Super(),
    child: MaterialApp(
      builder: (ctx, child) => MediaQuery(
          data: MediaQuery.of(ctx).copyWith(textScaler: TextScaler.linear(scale)), child: child!),
      home: ReviewTagsSettingsScreen(load: load ?? store!.load, mutate: store?.mutate),
    ),
  ));
  await t.pump();
  await t.pump(const Duration(milliseconds: 300));
}

Future<void> _addVia(WidgetTester t, String text) async {
  await t.tap(find.byTooltip('태그 추가').first);
  await t.pump(const Duration(milliseconds: 300));
  await t.enterText(find.byType(TextField), text);
  await t.tap(findVisibleText('추가'));
  await t.pump();
  await t.pump(const Duration(milliseconds: 300));
}

void main() {
  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
  });

  group('R62 SA 설정', () {
    testWidgets('[R62-a] 읽기 실패 — 기본 목록을 현재 설정처럼 보이지 않고 쓰기 입구를 없앤다', (t) async {
      await _pump(t, load: () async => throw Exception('unavailable'));
      expect(findVisibleText('리뷰 태그를 불러오지 못했습니다'), findsOneWidget);
      expect(findVisibleText('시간 준수'), findsNothing);
      expect(find.byTooltip('태그 추가'), findsNothing);
    });

    testWidgets('[R62-b] 추가 — 태그 한 개만 보내고, 그 사이 다른 SA 가 넣은 태그도 화면에 남는다', (t) async {
      final s = _Store({'positiveTags': ['시간 준수']});
      await _pump(t, store: s);
      s.data['positiveTags']!.add('다른 SA 태그'); // 화면이 열린 뒤 다른 SA 가 저장
      await _addVia(t, '꼼꼼함');
      expect(s.calls, ['+positiveTags:꼼꼼함']);
      expect(s.data['positiveTags'], ['시간 준수', '다른 SA 태그', '꼼꼼함']);
      expect(findVisibleText('다른 SA 태그'), findsOneWidget, reason: '저장 뒤 서버 값을 다시 읽는다');
    });

    testWidgets('[R62-c] 중복 — 쓰기 0', (t) async {
      final s = _Store({'positiveTags': ['시간 준수']});
      await _pump(t, store: s);
      await _addVia(t, '시간 준수');
      expect(s.calls, isEmpty);
    });

    testWidgets('[R62-d] 저장 실패 — 화면은 저장된 목록으로 돌아간다(낙관적 표시가 남지 않는다)', (t) async {
      final s = _Store({'positiveTags': ['시간 준수']})..failNext = Exception('denied');
      await _pump(t, store: s);
      await _addVia(t, '새 태그');
      expect(findVisibleText('새 태그'), findsNothing);
      expect(s.data['positiveTags'], ['시간 준수']);
    });

    testWidgets('[R62-e] 삭제 안내 — 이미 작성된 리뷰에는 남는다 · 취소 = 쓰기 0 · 삭제 = 한 개만', (t) async {
      final s = _Store({'positiveTags': ['시간 준수', '성실함']});
      await _pump(t, store: s);
      await t.tap(find.bySemanticsLabel('태그 성실함 삭제'));
      await t.pump(const Duration(milliseconds: 300));
      expect(findVisibleTextContaining('이미 작성된 리뷰에는 이 태그가 그대로 남습니다'), findsOneWidget);
      await t.tap(findVisibleText('취소'));
      await t.pump(const Duration(milliseconds: 300));
      expect(s.calls, isEmpty);
      await t.tap(find.bySemanticsLabel('태그 성실함 삭제'));
      await t.pump(const Duration(milliseconds: 300));
      await t.tap(findVisibleText('삭제'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 300));
      expect(s.calls, ['-positiveTags:성실함']);
      expect(s.data['positiveTags'], ['시간 준수']);
    });

    for (final c in const [(Size(392, 844), 1.0), (Size(320, 640), 1.3), (Size(392, 844), 2.0)]) {
      testWidgets('[R62-f] 긴 태그 — 말줄임 없이 다 보이고 넘침 없음 ${c.$1.width.toInt()}·${c.$2}', (t) async {
        await _pump(t, store: _Store({'positiveTags': [_long, '시간 준수']}), size: c.$1, scale: c.$2);
        expect(t.takeException(), isNull);
        final w = t.widget<Text>(findVisibleTextContaining('정확하게'));
        expect(w.overflow, isNot(TextOverflow.ellipsis));
      });
    }
  });

  group('R62 작성 창', () {
    Future<void> openAdmin(WidgetTester t, {bool unavailable = false, Size size = const Size(392, 1800), double scale = 1.0}) async {
      t.view.physicalSize = size;
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.reset);
      await t.pumpWidget(MaterialApp(
        builder: (ctx, child) => MediaQuery(
            data: MediaQuery.of(ctx).copyWith(textScaler: TextScaler.linear(scale)), child: child!),
        home: Scaffold(body: MonthlyReviewDialog(
          reviewerId: 'A', reviewerName: '관리자', businessId: 'B', businessName: 'QA',
          targetUserId: 'W', targetUserName: '근로자', reviewYear: 2026, reviewMonth: 10,
          workDaysInMonth: 1, requestId: 'R',
          preloadedTags: unavailable ? ReviewTagsModel() : ReviewTagsModel(positiveTags: [_long, '시간 준수'], improvementTags: ['집중력']),
          tagsUnavailable: unavailable,
        )),
      ));
      await t.pump(const Duration(milliseconds: 300));
    }

    testWidgets('[R62-g] 선택은 색만이 아니라 체크 표시와 선택 상태로 알린다', (t) async {
      final h = t.ensureSemantics();
      await openAdmin(t);
      expect(find.byIcon(Icons.check), findsNothing);
      await t.ensureVisible(findVisibleText('시간 준수'));
      await t.tap(findVisibleText('시간 준수'));
      await t.pump(const Duration(milliseconds: 200));
      expect(find.byIcon(Icons.check), findsOneWidget);
      final node = t.getSemantics(find.bySemanticsLabel('시간 준수'));
      expect(node.hasFlag(SemanticsFlag.isSelected), isTrue);
      expect(t.getSemantics(find.bySemanticsLabel('집중력')).hasFlag(SemanticsFlag.isSelected), isFalse);
      h.dispose();
    });

    testWidgets('[R62-h] 태그를 못 읽으면 기본 목록 대신 안내 — 태그 없이 작성 가능', (t) async {
      await openAdmin(t, unavailable: true);
      expect(findVisibleTextContaining('태그 목록을 불러오지 못했습니다'), findsNWidgets(2));
      expect(findVisibleText('시간 준수'), findsNothing);
    });

    testWidgets('[R62-i] 사업장 리뷰 창도 같다', (t) async {
      final h = t.ensureSemantics();
      t.view.physicalSize = const Size(392, 1800);
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.reset);
      await t.pumpWidget(MaterialApp(home: Scaffold(body: BusinessReviewDialog(
        reviewerId: 'W', businessId: 'B', businessName: 'QA', reviewYear: 2026, reviewMonth: 10,
        workDaysInMonth: 1, requestId: 'R',
        preloadedTags: ReviewTagsModel(businessPositiveTags: ['급여 정확'], businessImprovementTags: ['업무 과중']),
      ))));
      await t.pump(const Duration(milliseconds: 300));
      await t.ensureVisible(findVisibleText('급여 정확'));
      await t.tap(findVisibleText('급여 정확'));
      await t.pump(const Duration(milliseconds: 200));
      expect(t.getSemantics(find.bySemanticsLabel('급여 정확')).hasFlag(SemanticsFlag.isSelected), isTrue);
      expect(find.byIcon(Icons.check), findsOneWidget);
      h.dispose();
    });

    for (final c in const [(Size(392, 844), 1.0), (Size(320, 640), 1.3), (Size(392, 844), 2.0)]) {
      testWidgets('[R62-j] 작성 창 긴 태그 넘침 없음 ${c.$1.width.toInt()}·${c.$2}', (t) async {
        await openAdmin(t, size: c.$1, scale: c.$2);
        expect(t.takeException(), isNull);
      });
    }
  });

  group('R62 리뷰 카드', () {
    MonthlyReviewModel review() => MonthlyReviewModel(
        id: 'r', reviewKey: 'r', reviewType: ReviewType.ADMIN_TO_USER, reviewerId: 'A', reviewerName: '관리자',
        businessId: 'B', businessName: 'QA', targetUserId: 'W', targetUserName: '근로자',
        reviewYear: 2026, reviewMonth: 10, workDaysInMonth: 1, rating: 4, wouldRehire: true,
        positiveTags: [_long], improvementTags: ['집중력'], isPublished: true, createdAt: DateTime(2026, 10, 30));

    for (final c in const [(Size(392, 844), 1.0), (Size(320, 640), 1.3), (Size(392, 844), 2.0)]) {
      testWidgets('[R62-k] 좋았던 점/아쉬운 점을 글자(낭독)와 아이콘으로 · 넘침 없음 ${c.$1.width.toInt()}·${c.$2}', (t) async {
        final h = t.ensureSemantics();
        t.view.physicalSize = c.$1;
        t.view.devicePixelRatio = 1.0;
        addTearDown(t.view.reset);
        await t.pumpWidget(MaterialApp(
          builder: (ctx, child) => MediaQuery(
              data: MediaQuery.of(ctx).copyWith(textScaler: TextScaler.linear(c.$2)), child: child!),
          home: Scaffold(body: SingleChildScrollView(child: ReviewCard(review: review(), perspective: ReviewCardPerspective.workerReceived))),
        ));
        await t.pump();
        expect(t.takeException(), isNull);
        expect(find.bySemanticsLabel('아쉬운 점 집중력'), findsOneWidget);
        expect(find.bySemanticsLabel(RegExp('^좋았던 점 야간')), findsOneWidget);
        expect(find.byIcon(Icons.lightbulb_outline), findsOneWidget);
        h.dispose();
      });
    }
  });
}
