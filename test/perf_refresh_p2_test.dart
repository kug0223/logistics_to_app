// [impl_12] (1) 부분 변경 뒤 users 전체 재적재(refreshUserData) 근본 원인 정리 · (2) P2 추천 표시 캐시 홈 연결.
//
//   RF-1  lib 전체 `refreshUserData()` 호출부 = 허용 목록(가입·복구·초대 수락 — 계정 상태/권한이 바뀌어 전체 재적재가 필요한 곳)만.
//         서명·날인 저장 화면은 0 · 서버 확정 값 반영 함수만(재발 방지).
//   RF-2  `applyConfirmedSeal` — 서버 규칙 그대로(값 있으면 sealBase64+sealType · 없으면 지우고 'stamp') · 같은 계정만 · 로딩 0.
//   P2C   캐시 모듈 판정291 C291-P2 — 실패 삭제 뒤 같은 uid 재읽기 0 · clear 뒤 늦은 옛 save 0 · 옛 save 대 새 성공 0장 · 새 save 우선 ·
//         D291-02 대표사진 URL 허용/거부.
//   P2H   홈 연결 — 캐시 히트 첫 프레임 · live 로 교체(캐시 갱신) · live 0장/실패/부분 → 캐시 표시 0 · 로그아웃/탈퇴/전환/계정 바뀜 폐기(소스+행동).
// ignore_for_file: depend_on_referenced_packages, avoid_print
import 'dart:async';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ALfit/models/core/application_model.dart';
import 'package:ALfit/models/core/attendance_model.dart';
import 'package:ALfit/models/core/business_model.dart';
import 'package:ALfit/models/core/legal_readiness.dart';
import 'package:ALfit/models/core/slot_model.dart';
import 'package:ALfit/models/core/to_model.dart';
import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/models/core/work_detail_data.dart';
import 'package:ALfit/providers/notification_provider.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/screens/user/user_home_reads.dart';
import 'package:ALfit/screens/user/user_home_screen.dart';
import 'package:ALfit/screens/user/user_tab_scope.dart';
import 'package:ALfit/services/auth_service.dart' show DeletionRecoveryState;
import 'package:ALfit/services/home_recommend_cache.dart';
import 'package:ALfit/services/payroll_correction_service.dart';
import 'package:ALfit/theme/role_theme.dart';
import 'package:ALfit/utils/navigation_key.dart';

import 'support/visible_text.dart';

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

String _src(String p) => File(p).readAsStringSync();

/// 쓰기를 붙잡을 수 있는 저장소 — 늦은 write 재현.
class _Gate extends RamHomeRecommendStore {
  final holds = <Completer<void>>[];
  bool hold = false;
  bool failRemove = false;
  @override
  Future<void> set(String key, String value) async {
    if (hold) {
      final c = Completer<void>();
      holds.add(c);
      await c.future;
    }
    await super.set(key, value);
  }

  @override
  Future<void> removeWhere(bool Function(String key) test) async {
    if (failRemove) throw StateError('disk');
    await super.removeWhere(test);
  }

  @override
  Future<void> remove(String key) async {
    if (failRemove) throw StateError('disk');
    await super.remove(key);
  }
}

const _scope = HomeRecommendScope(env: 'p', role: 'USER', regionKey: '', queryKey: 'home-recommend-v1:unselected');
const _okUrl =
    'https://firebasestorage.googleapis.com/v0/b/alfit-dev.appspot.com/o/businesses%2Fb1%2Fmain.jpg?alt=media&token=abc';

HomeRecommendCard _card(String id, {String? img}) => HomeRecommendCard(
    toId: id, title: '캐시 공고 $id', businessName: '캐시 사업장', regionLabel: '강남구', dateLabel: '11/28', wageLabel: '시급 12,000원',
    imageUrl: img);

// ── 홈 하네스 ─────────────────────────────────────────────────────────
class _W extends UserProvider {
  _W(this.user);
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

UserModel _worker() => UserModel(
    uid: 'u1', username: '', name: '김알핏', email: '', role: UserRole.USER, accountStatus: 'active',
    passVerifiedAt: DateTime(2026, 11, 25), nationalityStatus: 'unknown', authProviders: const ['kakao'], signupSource: 'kakao_v1');

final DateTime _clock = DateTime.utc(2026, 11, 26, 1); // KST 10:00
DateTime _k(int m, int d) => DateTime.utc(2026, m, d);
const _wd = WorkDetailData(wdId: 'wd1', workType: '상하차', wage: 12000, requiredCount: 1, startTime: '10:00', endTime: '15:00');

TOModel _flex(String id, String title, String dateKey) => TOModel(
      id: id, businessId: 'b$id', businessName: '사업장 $id', businessCity: '강남구', type: 'flex',
      title: title, creatorUID: 'admin1', status: TOStatus.active, deadlineType: 'NONE', hoursBeforeStart: 0,
      workDetails: const [_wd], slotDateKeys: [dateKey], totalSlots: 1, totalRequired: 1,
      totalConfirmed: 0, totalPending: 0, isPublished: true, publishMode: 'immediate',
      createdAt: _k(11, 20), statusUpdatedAt: _k(11, 20),
    );

UserHomeReads _reads({
  List<TOModel> tos = const [],
  bool tosFail = false,
  int ms = 600,
  List<ApplicationModel> apps = const [],
  String? image,
}) =>
    UserHomeReads(
      slotsForTO: (_) async => const <SlotModel>[],
      myContracts: (_) async => const [],
      myApplications: (_) async {
        await Future<void>.delayed(Duration(milliseconds: ms));
        return apps;
      },
      myMonthlyAttendances: ({required String userId, required int year, required int month}) async {
        await Future<void>.delayed(Duration(milliseconds: ms));
        return const <AttendanceModel>[];
      },
      publishedTOs: () async {
        await Future<void>.delayed(Duration(milliseconds: ms));
        if (tosFail) throw Exception('P2H 공고 조회 실패 fixture');
        return tos;
      },
      pendingIdCardRequests: (_) async => const [],
      myRenewalProposals: () async => const [],
      businessById: (id) async => BusinessModel(
          id: id, name: 'b', ownerId: 'o', businessNumber: '0', address: 'a', category: 'c', subCategory: 's',
          isApproved: true, createdAt: DateTime(2026), mainImageUrl: image),
      invalidatePublishedTOsCache: () {},
      documentCorrections: () async => DocumentCorrectionSurface.empty,
      legalReadiness: () async => const LegalReadiness(status: LegalReadinessStatus.current),
    );

Future<void> _mount(WidgetTester t, UserHomeReads reads, HomeRecommendCache cache) async {
  t.view.physicalSize = const Size(390, 2400);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(const SizedBox.shrink());
  await t.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider<UserProvider>.value(value: _W(_worker())),
      ChangeNotifierProvider<NotificationProvider>(create: (_) => NotificationProvider()),
    ],
    child: MaterialApp(
      theme: RoleTheme.workerTheme,
      home: UserTabScope(
        switchToTab: (_) {},
        switchToTabWithDate: (_, __) {},
        pendingJobDate: null,
        clearPendingJobDate: () {},
        pendingScheduleMonth: null,
        clearPendingScheduleMonth: () {},
        switchToScheduleNow: () {},
        switchToScheduleDate: (_) {},
        child: UserHomeScreen(reads: reads, clock: () => _clock, tourCompleted: () async => true, recommendCache: cache),
      ),
    ),
  ));
}

Future<void> _pumpFor(WidgetTester t, int ms) async {
  for (var e = 0; e < ms; e += 50) {
    await t.pump(const Duration(milliseconds: 50));
  }
}

final _cached = find.byKey(const ValueKey('worker-home-recommend-cached'));
final _jobs = find.byKey(const ValueKey('worker-home-jobs-section'));

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
    await initializeDateFormatting('ko_KR');
  });
  setUp(() => SharedPreferences.setMockInitialValues({'tour_completed_user_home': true}));

  // ── (1) refreshUserData 근본 원인 ─────────────────────────────────────
  test('RF-1 lib 전체 refreshUserData() 호출부 = 허용 목록뿐 · 서명/날인 저장은 확정 값 반영', () {
    const allowed = {
      'lib/screens/auth/foreign_register_screen.dart', // 가입 완료 → 계정 상태 전환(전체 재적재 필요 · auth 담당)
      'lib/screens/auth/register_screen.dart', // 〃
      'lib/screens/auth/registration_recovery_screen.dart', // 복구 → active 전환
      'lib/screens/common/notification_screen.dart', // 초대 수락 → SubAdmin 권한 부여(역할 변화 · CF 트리거 폴링)
    };
    final hits = <String>{};
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'))) {
      final p = f.path.replaceAll('\\', '/');
      if (p.endsWith('lib/providers/user_provider.dart')) continue;
      final lines = f.readAsLinesSync();
      for (final l in lines) {
        final code = l.split('//').first; // 주석은 세지 않는다
        if (code.contains('refreshUserData()')) hits.add(p);
      }
    }
    print('[RF-1] $hits');
    expect(hits.difference(allowed), isEmpty, reason: '새 호출부는 전체 재적재가 정말 필요한지 판정 뒤 허용 목록에 넣는다');
    final settings = _src('lib/screens/common/settings_screen.dart');
    expect(RegExp(r'applyConfirmedSignature\(').allMatches(settings).length, 2);
    expect(RegExp(r'applyConfirmedSeal\(').allMatches(settings).length, 3);
    final sig = _src('lib/screens/user/signature_screen.dart');
    expect(RegExp(r'applyConfirmedSignature\(').allMatches(sig).length, 2);
  });

  test('RF-2 applyConfirmedSeal — 서버 규칙 · 같은 계정만 · 로딩 0', () {
    final up = UserProvider();
    up.debugSetCurrentUser(UserModel(uid: 'u1', username: 'u1', name: '사장', email: '', role: UserRole.BUSINESS_ADMIN));
    var notes = 0;
    up.addListener(() => notes++);
    up.applyConfirmedSeal(uid: 'u2', sealBase64: 'AAAA', sealType: 'signature');
    expect(up.currentUser!.sealBase64, isNull);
    up.applyConfirmedSeal(uid: 'u1', sealBase64: 'AAAA', sealType: 'signature');
    expect(up.currentUser!.sealBase64, 'AAAA');
    expect(up.currentUser!.sealType, 'signature');
    up.applyConfirmedSeal(uid: 'u1', sealBase64: null, sealType: 'signature');
    expect(up.currentUser!.sealBase64, isNull);
    expect(up.currentUser!.sealType, 'stamp', reason: '서버는 날인을 지우면 sealType 을 stamp 로 둔다');
    expect(notes, 2);
    expect(up.isLoading, isFalse);
  });

  // ── (2) 캐시 모듈 C291-P2 · D291-02 ───────────────────────────────────
  group('P2C 캐시 모듈(판정291 C291-P2 · D291-02)', () {
    final t0 = DateTime.utc(2026, 11, 26, 1);

    test('P2C-1 무효화 삭제 실패 뒤 같은 uid·범위 재읽기 0(세대 namespace)', () async {
      final store = _Gate();
      final c = HomeRecommendCache(store: store, clock: () => t0);
      await c.saveSuccess(uid: 'u1', scope: _scope, cards: [_card('a')], fromCompleteSuccess: true);
      store.failRemove = true;
      expect(await c.invalidateAll(), isFalse, reason: '삭제 실패를 성공으로 보고하지 않는다');
      expect(store.debugLength, 1, reason: '전제: 옛 값이 저장소에 남았다');
      expect(await c.read(uid: 'u1', scope: _scope), isNull, reason: '로그아웃 뒤 같은 uid 재로그인에도 옛 값 0');
      expect(c.peek(uid: 'u1', scope: _scope), isNull);
    });

    test('P2C-2 clear(성공 0장) 뒤 늦게 끝난 옛 save 는 값을 되살리지 못한다', () async {
      final store = _Gate()..hold = true;
      final c = HomeRecommendCache(store: store, clock: () => t0);
      final old = c.saveSuccess(uid: 'u1', scope: _scope, cards: [_card('old')], fromCompleteSuccess: true);
      await Future<void>.delayed(Duration.zero);
      store.hold = false;
      await c.saveSuccess(uid: 'u1', scope: _scope, cards: const [], fromCompleteSuccess: true); // 새 성공 0장
      store.holds.single.complete();
      await old;
      expect(await c.read(uid: 'u1', scope: _scope), isNull, reason: '옛 save 대 새 성공 0장 → 0');
      expect(c.peek(uid: 'u1', scope: _scope), isNull);
    });

    test('P2C-3 나중에 시작한 save 가 이긴다 — 늦게 끝난 옛 save 가 새 값을 덮지 않는다', () async {
      final store = _Gate()..hold = true;
      final c = HomeRecommendCache(store: store, clock: () => t0);
      final old = c.saveSuccess(uid: 'u1', scope: _scope, cards: [_card('old')], fromCompleteSuccess: true);
      await Future<void>.delayed(Duration.zero);
      store.hold = false;
      await c.saveSuccess(uid: 'u1', scope: _scope, cards: [_card('new')], fromCompleteSuccess: true);
      store.holds.single.complete();
      await old;
      final snap = await c.read(uid: 'u1', scope: _scope);
      expect(snap?.cards.single.toId, anyOf('new', isNull), reason: '옛 값(old)으로 되돌아가지 않는다');
      expect(snap?.cards.single.toId, isNot('old'));
    });

    test('P2C-4 대표사진 URL — 공개 사업장 사진만 · 다른 출처/경로/형식은 버림', () {
      expect(HomeRecommendCard.isAllowedImageUrl(_okUrl), isTrue);
      for (final bad in [
        'http://firebasestorage.googleapis.com/v0/b/x/o/businesses%2Fb1.jpg', // https 아님
        'https://evil.example.com/v0/b/x/o/businesses%2Fb1.jpg', // 다른 출처
        'https://firebasestorage.googleapis.com/v0/b/x/o/users%2Fu1%2FidCard.jpg', // 신분증 등 다른 경로
        'https://firebasestorage.googleapis.com/v0/b/x/o/contracts%2Fc1%2Fsignature_employer.png',
        'https://storage.googleapis.com/x/businesses/b1.jpg?X-Goog-Signature=abc', // 임시 서명 URL
        'https://firebasestorage.googleapis.com/v0/b/x/o/businesses%2F..%2Fusers%2Fu1.jpg',
        'https://firebasestorage.googleapis.com/v0/b/x/o/businesses%2F${'a' * 2100}',
      ]) {
        expect(HomeRecommendCard.isAllowedImageUrl(bad), isFalse, reason: bad.substring(0, bad.length.clamp(0, 90)));
        expect(_card('x', img: bad).imageUrl, isNull);
      }
      expect(_card('x', img: _okUrl).imageUrl, _okUrl);
    });
  });

  // ── (2) 홈 연결 ─────────────────────────────────────────────────────
  group('P2H 홈 연결', () {
    Future<HomeRecommendCache> primed() async {
      final c = HomeRecommendCache(clock: () => DateTime.now().toUtc());
      await c.saveSuccess(uid: 'u1', scope: _scope, cards: [_card('a', img: _okUrl), _card('b')], fromCompleteSuccess: true);
      expect(c.peek(uid: 'u1', scope: _scope), isNotNull, reason: '전제: 캐시 있음');
      return c;
    }

    testWidgets('P2H-1 캐시 히트 — 첫 프레임에 마지막 성공 추천 2장 + 확인 중 · 누름 0', (t) async {
      final c = await primed();
      await _mount(t, _reads(tos: [_flex('L1', '라이브 공고 하나', '2026-11-28')]), c);
      expect(_cached, findsOneWidget, reason: '첫 프레임(조회 전)');
      expect(find.descendant(of: _jobs, matching: findVisibleText('캐시 공고 a')), findsOneWidget);
      expect(find.descendant(of: _jobs, matching: findVisibleTextContaining('확인 중')), findsOneWidget);
      await _pumpFor(t, 1500);
      t.takeException();
    });

    testWidgets('P2H-2 live 결과가 오면 교체 · 캐시도 live 로 갱신', (t) async {
      final c = await primed();
      await _mount(t, _reads(tos: [_flex('L1', '라이브 공고 하나', '2026-11-28')]), c);
      await _pumpFor(t, 1500);
      expect(_cached, findsNothing);
      expect(find.descendant(of: _jobs, matching: findVisibleText('라이브 공고 하나')), findsOneWidget);
      expect(find.descendant(of: _jobs, matching: findVisibleText('캐시 공고 a')), findsNothing);
      expect(c.peek(uid: 'u1', scope: _scope)?.cards.map((x) => x.toId).toList(), ['L1']);
      t.takeException();
    });

    testWidgets('P2H-3 live 0장 → 캐시 표시 0 · 정상0 안내 · 캐시 지움', (t) async {
      final c = await primed();
      await _mount(t, _reads(tos: const []), c);
      await _pumpFor(t, 1500);
      expect(_cached, findsNothing);
      expect(findVisibleText('지금 표시할 일자리가 없어요'), findsOneWidget);
      expect(c.peek(uid: 'u1', scope: _scope), isNull, reason: '0장 스냅샷 저장 0 · 옛 추천 남김 0');
      t.takeException();
    });

    testWidgets('P2H-4 live 공고 조회 실패 → 캐시 표시 0(오류를 캐시로 가리지 않음)', (t) async {
      final c = await primed();
      await _mount(t, _reads(tosFail: true), c);
      await _pumpFor(t, 1500);
      expect(_cached, findsNothing);
      expect(find.descendant(of: _jobs, matching: findVisibleText('캐시 공고 a')), findsNothing);
      t.takeException();
    });

    testWidgets('P2H-5 지원 200건(부분) → live 표시는 그대로 · 캐시에 저장 0', (t) async {
      final c = HomeRecommendCache(clock: () => DateTime.now().toUtc());
      final many = [
        for (var i = 0; i < 200; i++)
          ApplicationModel(
              id: 'p$i', toId: 'to_p$i', uid: 'u1', businessId: 'bp', businessName: 'b', toTitle: 't', status: AppStatus.pending,
              selectedWorkType: '피킹', startTime: '09:00', endTime: '18:00', wage: 12000, wageType: 'hourly',
              workDate: _k(12, 1 + (i % 20)), appliedAt: _k(11, 20), applicationType: AppType.shortTerm)
      ];
      await _mount(t, _reads(tos: [_flex('L1', '라이브 공고 하나', '2026-11-28')], apps: many), c);
      await _pumpFor(t, 1500);
      expect(c.peek(uid: 'u1', scope: _scope), isNull, reason: '부분 결과로 저장하지 않는다');
      t.takeException();
    });

    testWidgets('P2H-6 캐시 없음(무효화 뒤) → 첫 프레임은 기존 뼈대 · 캐시 표시 0', (t) async {
      final c = await primed();
      await c.invalidateAll(); // 로그아웃·전환·탈퇴와 같은 경로
      await _mount(t, _reads(tos: [_flex('L1', '라이브 공고 하나', '2026-11-28')]), c);
      expect(_cached, findsNothing);
      await _pumpFor(t, 1500);
      t.takeException();
    });

    test('P2H-7 UserProvider 폐기 지점 — 로그아웃 · 탈퇴 재개 · 계정 바뀜 · 역할(모드) 전환(소스) + 탈퇴 재개 행동', () {
      final src = _src('lib/providers/user_provider.dart');
      expect(RegExp(r'HomeRecommendCache\.shared\.invalidateAll\(\)').allMatches(src).length, greaterThanOrEqualTo(5));
      int fnHas(String sig) {
        final a = src.indexOf(sig);
        expect(a, greaterThan(0), reason: sig);
        return src.substring(a, (a + 2500).clamp(0, src.length)).indexOf('HomeRecommendCache.shared.invalidateAll()');
      }
      for (final sig in ['Future<void> signOut() async {', 'void enterDeletionRecovery(', 'void toggleAdminMode() {',
          'Future<void> switchToAdminMode(String businessId) async {']) {
        expect(fnHas(sig), greaterThanOrEqualTo(0), reason: '$sig 에서 폐기');
      }
      expect(src.contains('if (_currentUser?.uid != loaded?.uid) unawaited(HomeRecommendCache.shared.invalidateAll());'), isTrue);
      // 행동: 탈퇴 재개 진입 → 공용 캐시 세대 증가
      setLoginRedirectCallback(() {});
      final up = UserProvider()..debugSetCurrentUser(_worker());
      final e0 = HomeRecommendCache.shared.debugEpoch;
      up.enterDeletionRecovery(DeletionRecoveryState.required);
      expect(HomeRecommendCache.shared.debugEpoch, e0 + 1);
    });
  });
}
