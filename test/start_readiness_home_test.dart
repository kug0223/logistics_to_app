// [ALFIT-AUTH-KAKAO-ONBOARDING.1 · 대표 결정 2026-11-25] 가입 후 흐름 — 지역 gate 제거 · 홈 「시작 준비」 카드.
//
//   SR-H1  새 카카오 근무자(지역 · 서류 0) → 홈이 열리고 카드 3 줄(지역 → 신분증/외국인등록증 → 급여) · 넘침 0
//   SR-H2  320dp · 글자 2.0 넘침 0
//   SR-H3  전부 끝나면 카드 없음
//   SR-H4  옛 QA 세대(지역 있음 · 신분증 없음) → 지역 줄 '완료' · '신분증 등록'(외국인등록증 문구 0) · 홈 정상
//   SR-H5  '일할 지역 고르기' → 지역 설정 화면(뒤로 가능 · '저장하기' · 로그아웃 줄 0)
//   SR-C*  카드 위젯 단독: 남은 수 · 완료 표시 · 탭 · allDone
//   SR-S*  소스 계약: AuthWrapper 지역 gate 0 · 카드 판정은 기존 값 · 홈 상단 배치
//   캡처는 DU1_VQ_PHASE 가 있을 때만(→ records/work/auth-kakao-1/screens_2).
// ignore_for_file: depend_on_referenced_packages
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ALfit/models/core/business_model.dart';
import 'package:ALfit/models/core/slot_model.dart';
import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/models/core/user_region.dart';
import 'package:ALfit/providers/notification_provider.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/screens/user/user_home_reads.dart';
import 'package:ALfit/screens/user/user_home_screen.dart';
import 'package:ALfit/services/payroll_correction_service.dart';
import 'package:ALfit/theme/role_theme.dart';
import 'package:ALfit/widgets/home/start_readiness_card.dart';

import 'support/du1_vq_capture.dart';
import 'support/visible_text.dart';

class _FakeApp extends Fake with MockPlatformInterfaceMixin implements FirebaseAppPlatform {
  @override
  String get name => defaultFirebaseAppName;
  @override
  FirebaseOptions get options =>
      const FirebaseOptions(apiKey: 'k', appId: 'a', messagingSenderId: 's', projectId: 'p');
}

class _FakeCore extends FirebasePlatform with MockPlatformInterfaceMixin {
  @override
  FirebaseAppPlatform app([String name = defaultFirebaseAppName]) => _FakeApp();
  @override
  Future<FirebaseAppPlatform> initializeApp({String? name, FirebaseOptions? options}) async => _FakeApp();
  @override
  List<FirebaseAppPlatform> get apps => [_FakeApp()];
}

class _U extends UserProvider {
  _U(this.user);
  final UserModel user;
  @override
  UserModel? get currentUser => user;
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

const _region = UserRegion(province: '서울특별시', city: '강남구', district: '역삼동');

/// 새 카카오 가입 직후 근무자 — 지역 · 서류 · 계좌 없음 · 국적 미확정.
UserModel _kakaoNew() => UserModel(
      uid: 'k1', username: '', name: '김알핏', email: '', role: UserRole.USER,
      accountStatus: 'active', passVerifiedAt: DateTime(2026, 11, 25),
      nationalityStatus: 'unknown', authProviders: const ['kakao'], signupSource: 'kakao_v1',
    );

/// 모두 끝난 근무자.
UserModel _allDone() => UserModel(
      uid: 'k2', username: '', name: '김알핏', email: '', role: UserRole.USER,
      accountStatus: 'active', passVerifiedAt: DateTime(2026, 11, 25),
      nationalityStatus: 'domestic', authProviders: const ['kakao'], signupSource: 'kakao_v1',
      homeRegion: _region, idCardImagePath: 'users/k2/idCard_1.jpg',
      bankName: '국민은행', accountNumber: 'enc', accountHolder: '김알핏', bankbookImagePath: 'users/k2/bankbook_1.jpg',
    );

/// 옛 QA 세대(아이디 계정) — 지역 있음(옛 gate) · 신분증 없음 · 계좌 있음.
UserModel _legacy() => UserModel(
      uid: 'q1', username: 'qa_user', name: '이큐에이', email: 'qa_user@ALfit-system.com', role: UserRole.USER,
      accountStatus: 'active', passVerifiedAt: DateTime(2026, 1, 1), homeRegion: _region,
      bankName: '국민은행', accountNumber: 'enc', accountHolder: '이큐에이', bankbookImagePath: 'users/q1/bankbook_1.jpg',
    );

UserHomeReads _reads() => UserHomeReads(
      slotsForTO: (toId) async => const <SlotModel>[],
      myContracts: (uid) async => const [],
      myApplications: (uid) async => const [],
      myMonthlyAttendances: ({required String userId, required int year, required int month}) async => const [],
      publishedTOs: () async => const [],
      pendingIdCardRequests: (uid) async => const [],
      myRenewalProposals: () async => const [],
      businessById: (id) async => BusinessModel(
          id: id, name: 'b', ownerId: 'o', businessNumber: '0', address: 'a', category: 'c',
          subCategory: 's', isApproved: true, createdAt: DateTime(2026)),
      invalidatePublishedTOsCache: () {},
      documentCorrections: () async => DocumentCorrectionSurface.empty,
    );

final _cap = GlobalKey();

Future<void> _pumpHome(WidgetTester t, UserModel u, {double width = 392, double scale = 1.0}) async {
  t.view.physicalSize = Size(width, 1600);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(RepaintBoundary(
    key: _cap,
    child: MultiProvider(
      providers: [
        ChangeNotifierProvider<UserProvider>.value(value: _U(u)),
        ChangeNotifierProvider<NotificationProvider>(create: (_) => NotificationProvider()),
      ],
      child: MaterialApp(
        theme: RoleTheme.workerTheme,
        debugShowCheckedModeBanner: false,
        builder: (ctx, child) => MediaQuery(
          data: MediaQuery.of(ctx).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: UserHomeScreen(reads: _reads()),
      ),
    ),
  ));
  for (var i = 0; i < 20; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _shot(WidgetTester t, String id, Map<String, Object?> cond) async {
  await t.pump(const Duration(milliseconds: 200));
  await vqCapture(t, _cap, id, conditions: {...cond, 'kind': 'LOCAL widget render (모의 데이터)'});
}

void main() {
  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
    SharedPreferences.setMockInitialValues({'tour_completed_user_home': true});
    if (vqEnabled) await vqLoadFonts();
  });

  group('SR-H 홈', () {
    testWidgets('SR-H1 지역·서류 없는 새 근무자 — 홈이 열리고 카드 3 줄', (t) async {
      await _pumpHome(t, _kakaoNew());
      expect(t.takeException(), isNull);
      expect(findVisibleText('시작 준비'), findsOneWidget);
      expect(findVisibleText('3개 남았어요'), findsOneWidget);
      final region = t.getTopLeft(findVisibleText('일할 지역 고르기'));
      final id = t.getTopLeft(findVisibleText('신분증 또는 외국인등록증 등록'));
      final wage = t.getTopLeft(findVisibleText('급여 계좌 · 통장사본 등록'));
      expect(region.dy < id.dy && id.dy < wage.dy, isTrue, reason: '지역 → 신분 → 급여 순서');
      await _shot(t, 'H1_home_new_worker_392', {'w': 392, 'scale': 1.0});
    });

    testWidgets('SR-H2 320dp · 글자 2.0 넘침 0', (t) async {
      await _pumpHome(t, _kakaoNew(), width: 320, scale: 2.0);
      expect(t.takeException(), isNull);
      expect(findVisibleText('일할 지역 고르기'), findsOneWidget);
      await _shot(t, 'H2_home_new_worker_320x2', {'w': 320, 'scale': 2.0});
    });

    testWidgets('SR-H3 전부 끝나면 카드 없음', (t) async {
      await _pumpHome(t, _allDone());
      expect(t.takeException(), isNull);
      expect(findVisibleText('시작 준비'), findsNothing);
      expect(find.byType(StartReadinessCard), findsNothing);
    });

    testWidgets('SR-H4 옛 QA 세대 — 지역 완료 · 신분증만 남음 · 외국인등록증 문구 0', (t) async {
      await _pumpHome(t, _legacy());
      expect(t.takeException(), isNull);
      expect(findVisibleText('1개 남았어요'), findsOneWidget);
      expect(findVisibleText('신분증 등록'), findsOneWidget);
      expect(findVisibleText('신분증 또는 외국인등록증 등록'), findsNothing);
      expect(find.text('완료'), findsNWidgets(2));
      await _shot(t, 'H4_home_legacy_partial_392', {'w': 392, 'scale': 1.0});
    });

    testWidgets('SR-H5 일할 지역 고르기 → 지역 설정 화면(뒤로 가능 · 로그아웃 줄 0)', (t) async {
      await _pumpHome(t, _kakaoNew());
      await t.tap(findVisibleText('일할 지역 고르기'));
      await t.pumpAndSettle();
      expect(findVisibleText('주로 일할 지역을 알려주세요'), findsOneWidget);
      expect(findVisibleText('저장하기'), findsOneWidget);
      expect(findVisibleText('로그아웃'), findsNothing);
      expect(find.byType(BackButton), findsOneWidget);
      await _shot(t, 'H5_region_setup_pushed_392', {'w': 392, 'scale': 1.0});
      await t.pageBack();
      await t.pumpAndSettle();
      expect(findVisibleText('시작 준비'), findsOneWidget);
    });
  });

  group('SR-C 카드 위젯', () {
    testWidgets('SR-C1 남은 수 · 완료 표시 · 탭 · allDone · 320×2.0 넘침 0', (t) async {
      t.view.physicalSize = const Size(320, 900);
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.reset);
      final taps = <String>[];
      final items = [
        StartReadinessItem(icon: Icons.store_outlined, title: '사업장 등록', done: true, onTap: () => taps.add('b')),
        StartReadinessItem(icon: Icons.badge_outlined, title: '사업자등록증 올리기', subtitle: '공고 전에 준비해요', done: false, onTap: () => taps.add('l')),
      ];
      await t.pumpWidget(MaterialApp(
        builder: (ctx, child) => MediaQuery(
          data: MediaQuery.of(ctx).copyWith(textScaler: const TextScaler.linear(2.0)),
          child: child!,
        ),
        home: Scaffold(body: SingleChildScrollView(child: StartReadinessCard(items: items))),
      ));
      expect(t.takeException(), isNull);
      expect(findVisibleText('1개 남았어요'), findsOneWidget);
      expect(find.text('완료'), findsOneWidget);
      await t.tap(findVisibleText('사업자등록증 올리기'));
      expect(taps, ['l']);
      expect(StartReadinessCard.allDone(items), isFalse);
      expect(StartReadinessCard.allDone([items.first]), isTrue);
    });
  });

  group('SR-S 소스 계약', () {
    test('SR-S1 AuthWrapper 지역 gate 없음 · 지역 화면은 홈에서 여는 화면으로 재사용', () {
      final m = File('lib/main.dart').readAsStringSync()
          .split('\n').where((l) => !l.trimLeft().startsWith('//')).join('\n');
      expect(m.contains('if (user.homeRegion == null)'), isFalse);
      expect(m.contains('return const _HomeRegionRecoveryScreen();'), isFalse);
      expect(m, contains('Future<void> openHomeRegionSetup(BuildContext context)'));
      expect(m, contains('const _HomeRegionRecoveryScreen(pushed: true)'));
    });
    test('SR-S2 카드 판정은 기존 값만(새 판정 0) · 검수 상태 읽기 0 · 홈 상단(날짜 Hero 위)', () {
      final h = File('lib/screens/user/user_home_screen.dart').readAsStringSync();
      final a = h.indexOf('Widget _buildReadinessCard(');
      final card = h.substring(a, h.indexOf('\n  }\n', a));
      expect(card, contains('final hasRegion = user.homeRegion != null;'));
      expect(card, contains('final hasId = user.hasIdDocument;'));
      expect(card, contains('final hasWage = user.hasBankAccount && user.hasBankbookDocument;'));
      expect(card, contains('if (completed == 3) return const SizedBox.shrink();'));
      for (final f in ['bankVerificationStatus', 'bankbookMatchStatus', 'hasWageDocumentsReady']) {
        expect(card.contains(f), isFalse, reason: f);
      }
      final body = h.substring(h.indexOf('Widget _buildUserBody('));
      // [판정285 §2 갱신 2026-11-26] 시작 준비는 실제 약속(B/A) **바로 뒤 한 자리**다 — 약속이 없으면 그 자리가 비어
      //   필수응답 바로 뒤가 된다(정상0 큰 약속 카드는 없앴다). 약속 유무 두 분기 배치 대신 슬롯 하나 · 통합 날짜 영역보다 앞.
      //   대표 결정 2026-11-25(근무 응답이 밀리지 않게 약속이 먼저)는 그대로다.
      const slot = '_RhythmSlot(kind: _Rhythm.card, child: _buildReadinessCard(context, s, up)),';
      final bodyFn = body.substring(0, body.indexOf('\n  }\n'));
      expect(slot.allMatches(bodyFn).length, 1, reason: '준비 카드 한 번');
      expect(bodyFn.indexOf(slot), greaterThan(bodyFn.indexOf('_buildPriorityCard(context, s, theme)')));
      expect(bodyFn.indexOf(slot), lessThan(bodyFn.indexOf('_buildDateExplorer(context, s, theme)')));
      expect(bodyFn.contains('if (!_hasPromiseHero)'), isFalse);
      expect(h, contains('bool get _hasPromiseHero => _heroTodayApp != null || _heroNewConfirmApp != null;'));
    });
  });

  // [판정284 C284-02] 행별 단일 버튼 의미 노드 + 그 노드의 tap action 이 일반 터치와 같은 콜백에 닿는다.
  group('SR-A11Y', () {
    testWidgets('SR-A11Y-01 행마다 버튼 하나 · 접근성 tap = 같은 목적지', (t) async {
      final handle = t.ensureSemantics();
      final hits = <String>[];
      final items = [
        StartReadinessItem(icon: Icons.place_outlined, title: '일할 지역 고르기', subtitle: '선택한 지역의 일자리를 먼저 보여 드려요' /* [판정287 C287-02] 홈 문구와 같게 */, done: false, onTap: () => hits.add('region')),
        StartReadinessItem(icon: Icons.badge_outlined, title: '신분증 또는 외국인등록증 등록', subtitle: '지원하기 전에 한 번 등록해요', done: false, onTap: () => hits.add('id')),
        StartReadinessItem(icon: Icons.account_balance_outlined, title: '급여 계좌·통장사본 등록', subtitle: '급여를 받을 본인 계좌예요', done: false, onTap: () => hits.add('bank')),
      ];
      await t.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(child: StartReadinessCard(items: items)))));
      await t.pumpAndSettle();
      for (final (label, key) in [('일할 지역 고르기', 'region'), ('신분증 또는 외국인등록증 등록', 'id'), ('급여 계좌·통장사본 등록', 'bank')]) {
        final f = find.bySemanticsLabel(label);
        expect(f, findsOneWidget, reason: '$label — 의미 노드 하나');
        expect(t.getSemantics(f), containsSemantics(isButton: true, hasTapAction: true),
            reason: '$label — 버튼 + 접근성 tap action');
        t.semantics.tap(find.semantics.byLabel(label));
        await t.pump();
        expect(hits.last, key, reason: '$label — 접근성 tap 이 같은 콜백');
      }
      // 일반 터치도 같은 목적지(대체가 아니라 함께 확인).
      // 화면 글자는 keepWords(낱말 붙임 문자)라 원문 find.text 로는 못 찾는다 — 같은 행의 의미 노드 위치를 누른다.
      await t.tap(find.bySemanticsLabel('급여 계좌·통장사본 등록'));
      await t.pump();
      expect(hits.last, 'bank');
      expect(hits, ['region', 'id', 'bank', 'bank']);
      handle.dispose();
    });
  });
}
