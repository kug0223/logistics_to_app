// [R7-PREDEVICE-STABILIZATION.1] SubAdmin 은 사업장 양식에 닿지 않는다.
//
// ── 무엇이 문제였나 ─────────────────────────────────────────────────
//   `firestore.rules` 의 `businesses` 는 create 에 `isBusinessAdmin()`,
//   update 에 `isAdminOf()` 를 요구한다. SubAdmin 은 `role == 'USER'` +
//   `subAdminBusinessIds` 이므로 **둘 다 거부**된다(서버 fail-closed).
//
//   그런데 목록 화면의 **빈 상태**는 '사업장 등록하기' CTA 를 역할과
//   무관하게 보여줬다. SubAdmin 이 눌러서 3단계를 끝까지 채워도 저장이
//   거부된다 — 할 수 없는 일을 시켜 놓고 마지막에 막는 구조였다.
//
//   SubAdmin 이 빈 상태에 닿는 경로는 셋이다: 배정 없음 · 배정된 사업장이
//   사라짐 · **조회 실패**(catch 가 `_businesses` 를 비운 채 둔다).
//
//   나머지 네 진입구는 이미 막혀 있었다 — 여기서 함께 못 박아 한쪽만
//   되돌아가는 것을 막는다.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ALfit/models/core/business_model.dart';
import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/providers/notification_provider.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/screens/business_admin/business_list_reads.dart';
import 'package:ALfit/screens/business_admin/business_list_screen.dart';

String _read(String p) {
  final f = File(p);
  if (!f.existsSync()) throw StateError('$p 를 찾지 못함');
  return f.readAsStringSync();
}

const _list = 'lib/screens/business_admin/business_list_screen.dart';
const _home = 'lib/screens/business_admin/business_admin_home_screen.dart';
const _detail = 'lib/screens/business_admin/business_detail_screen.dart';

class _FakeApp extends Fake
    with MockPlatformInterfaceMixin
    implements FirebaseAppPlatform {
  @override
  String get name => defaultFirebaseAppName;
  @override
  FirebaseOptions get options => const FirebaseOptions(
      apiKey: 'k',
      appId: 'a',
      messagingSenderId: 's',
      projectId: 'p',
      storageBucket: 'p.appspot.com');
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

/// 읽기 결과를 고른다. 실패는 `throws`, 0개는 빈 목록이다.
///
///   실기기 없이 Firestore 를 실패시킬 방법이 없고, 테스트 환경에서는
///   호출이 던지지 않고 그대로 **매달린다**(로딩에서 끝난다). 그래서
///   화면의 읽기 경계에 주입한다.
BusinessListReads _reads({bool throws = false, List<BusinessModel>? items}) =>
    BusinessListReads(
      businessById: (_) async {
        if (throws) throw StateError('read failed');
        final list = items ?? const <BusinessModel>[];
        return list.isEmpty ? null : list.first;
      },
      businessesByIds: (_) async {
        if (throws) throw StateError('read failed');
        return items ?? const <BusinessModel>[];
      },
    );

/// 배정이 없는 상태를 만든다 — [bizId] 가 null 이면 id 목록이 비고,
/// 주면 SubAdmin 경로(`effectiveBusinessId`)가 열린다.
class _Provider extends UserProvider {
  _Provider({required this.subAdmin, this.bizId});

  final bool subAdmin;
  final String? bizId;

  @override
  UserModel? get currentUser => UserModel(
        uid: 'u1',
        username: 'u1',
        name: '김의관',
        email: 'u1@alfit.local',
        role: subAdmin ? UserRole.USER : UserRole.BUSINESS_ADMIN,
        managedBusinessIds: bizId == null ? const [] : [bizId!],
        subAdminBusinessIds: bizId == null ? const [] : [bizId!],
      );

  @override
  bool get isSubAdmin => subAdmin;

  @override
  bool get isBusinessAdmin => !subAdmin;

  @override
  String? get effectiveBusinessId => bizId;
}

Future<void> _pumpList(
  WidgetTester tester, {
  required bool subAdmin,
  String? bizId,
  BusinessListReads? reads,
  Size size = const Size(390, 900),
  double textScale = 1.0,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<UserProvider>(
            create: (_) => _Provider(subAdmin: subAdmin, bizId: bizId)),
        ChangeNotifierProvider<NotificationProvider>(
            create: (_) => NotificationProvider()),
      ],
      child: MaterialApp(
        builder: (ctx, child) => MediaQuery(
          data: MediaQuery.of(ctx)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: BusinessListScreen(reads: reads ?? _reads()),
      ),
    ),
  );
  for (var i = 0; i < 15; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
  });

  group('SA-FORM 빈 상태가 역할을 구별한다', () {
    testWidgets('SA-FORM-01 SubAdmin 에게는 등록 CTA 가 없다', (tester) async {
      await _pumpList(tester, subAdmin: true);
      expect(tester.takeException(), isNull);

      // 할 수 없는 일을 권하지 않는다.
      expect(find.text('사업장 등록하기'), findsNothing,
          reason: '눌러도 서버가 거부한다 — 보여주면 안 된다');
      expect(find.text('등록된 사업장이 없습니다'), findsNothing,
          reason: '"등록하라" 는 뜻으로 읽힌다 — SubAdmin 은 등록 주체가 아니다');

      // 대신 **사실**을 말한다.
      expect(find.text('배정된 사업장이 없습니다'), findsOneWidget);
      expect(find.text('권한을 부여한 관리자에게 사업장 배정을 확인해 주세요'),
          findsOneWidget);
    });

    testWidgets('SA-FORM-02 BUSINESS_ADMIN 에게는 그대로 등록 CTA 가 있다',
        (tester) async {
      await _pumpList(tester, subAdmin: false);
      expect(tester.takeException(), isNull);
      expect(find.text('등록된 사업장이 없습니다'), findsOneWidget);
      expect(find.text('사업장 등록하기'), findsWidgets,
          reason: '오너의 경로를 같이 막아 버리면 아무도 사업장을 만들 수 없다');
    });

    testWidgets('SA-FORM-03 좁은 화면 · 큰 배율에서도 분기가 유지된다',
        (tester) async {
      await _pumpList(tester,
          subAdmin: true, size: const Size(320, 820), textScale: 2.0);
      expect(tester.takeException(), isNull);
      expect(find.text('사업장 등록하기'), findsNothing);
      expect(find.text('배정된 사업장이 없습니다'), findsOneWidget);
    });
  });

  // ═══════════════════════════════════════════════════════════
  // [R7-PREDEVICE-STABILIZATION.1A] 조회 실패 ≠ 사업장 0개
  //
  //   `.1` 에서 빈 상태의 역할 분기를 고쳤지만, **실패도 같은 빈 상태로**
  //   들어왔다. 더 나쁜 것은 서비스 계층이 실패를 삼켰다는 점이다 —
  //   `getBusinessesByIds` 는 실패를 `[]` 로, `getBusinessById` 는 null 로
  //   바꿔 돌려주므로 화면의 catch 가 돌지 않고 토스트도 뜨지 않았다.
  //   그래서 읽기 실패 한 번이 "등록된 사업장이 없습니다" 라는 전혀 다른
  //   사실로 번졌다.
  // ═══════════════════════════════════════════════════════════
  group('SA-ERR 실패와 0개를 가른다', () {
    testWidgets('SA-ERR-01 조회 실패는 "없음" 이 아니라 **실패**로 보인다',
        (tester) async {
      await _pumpList(tester,
          subAdmin: false, bizId: 'biz1', reads: _reads(throws: true));
      expect(tester.takeException(), isNull);

      expect(find.text('사업장 목록을 불러오지 못했어요'), findsOneWidget);
      expect(find.text('다시 시도'), findsWidgets,
          reason: '실패는 막다른 길이 아니다 — 다시 시도할 수 있어야 한다');
      // 실패를 0개로 말하지 않는다.
      expect(find.text('등록된 사업장이 없습니다'), findsNothing);
      expect(find.text('배정된 사업장이 없습니다'), findsNothing);
    });

    testWidgets('SA-ERR-02 SubAdmin 의 조회 실패도 등록 CTA 를 띄우지 않는다',
        (tester) async {
      await _pumpList(tester,
          subAdmin: true, bizId: 'biz1', reads: _reads(throws: true));
      expect(tester.takeException(), isNull);

      expect(find.text('사업장 목록을 불러오지 못했어요'), findsOneWidget);
      // 실패 화면에도 '사업장 등록하기' 가 새지 않는다.
      expect(find.text('사업장 등록하기'), findsNothing);
      expect(find.text('배정된 사업장이 없습니다'), findsNothing,
          reason: '실패를 배정 0건으로 말하면 근로자·관리자가 잘못 판단한다');
    });

    testWidgets('SA-ERR-03 실제 0개는 여전히 "없음" 이다', (tester) async {
      // 성공했고 결과가 0개다 (SUCCESS_ZERO).
      await _pumpList(tester, subAdmin: false);
      expect(tester.takeException(), isNull);
      expect(find.text('등록된 사업장이 없습니다'), findsOneWidget);
      expect(find.text('사업장 목록을 불러오지 못했어요'), findsNothing,
          reason: '0개를 실패로 말하는 반대 방향 오류도 없어야 한다');
    });

    test('SA-ERR-04 읽기 경계가 **던지는** 변형만 노출한다', () {
      // 삼키는 변형을 쓰면 화면의 catch 가 돌지 않아 실패가 조용히 0개가
      //   된다 — 경계 쪽에서 못 박는다.
      final r = _read('lib/screens/business_admin/business_list_reads.dart');
      expect(r.contains('svc.getBusinessByIdOrThrow'), isTrue);
      expect(r.contains('svc.getBusinessesByIdsOrThrow'), isTrue);
      expect(RegExp(r'svc\.getBusinessById\b(?!OrThrow)').hasMatch(r), isFalse,
          reason: '삼키는 getBusinessById 를 쓴다');
      expect(RegExp(r'svc\.getBusinessesByIds\b(?!OrThrow)').hasMatch(r),
          isFalse,
          reason: '삼키는 getBusinessesByIds 를 쓴다');

      // 화면은 서비스를 직접 쥐지 않는다 — 경계를 우회하면 다시 갈린다.
      final s = _read(_list);
      expect(s.contains('FirestoreService()'), isFalse,
          reason: '화면이 서비스를 직접 들면 경계가 무의미하다');
      expect(s.contains('_reads.businessById('), isTrue);
      expect(s.contains('_reads.businessesByIds('), isTrue);
    });

    test('SA-ERR-04b production 은 주입 없이 기존 경로를 쓴다', () {
      // `reads: null` 이면 실제 서비스로 간다 — 테스트용 경로가 제품에
      //   새지 않는다.
      final s = _read(_list);
      expect(s.contains('widget.reads ?? BusinessListReads.of()'), isTrue);
      // 호출부 세 곳은 인자 없이 그대로 쓴다.
      for (final p in const [
        'lib/screens/business_admin/business_admin_home_screen.dart',
        'lib/screens/business_admin/business_detail_screen.dart',
      ]) {
        final c = _read(p);
        expect(c.contains('BusinessListScreen(reads:'), isFalse,
            reason: '$p 가 테스트 경계를 주입한다');
      }
    });

    test('SA-ERR-05 ERROR 를 SUCCESS_ZERO 보다 먼저 가린다', () {
      final s = _read(_list);
      final err = s.indexOf('_loadFailed');
      final empty = s.indexOf('_buildEmptyState(context, isSubAdmin)');
      expect(err, greaterThan(-1));
      expect(empty, greaterThan(-1));
      // body 분기에서 _loadFailed 가 _businesses.isEmpty 보다 앞이다.
      final branch = s.indexOf('body: _isLoading');
      expect(branch, greaterThan(-1));
      final tail = s.substring(branch, branch + 420);
      expect(tail.indexOf('_loadFailed'),
          lessThan(tail.indexOf('_businesses.isEmpty')),
          reason: '빈 상태를 먼저 보면 실패가 "없음" 으로 샌다');
    });

    test('SA-ERR-06 로그인 정보 부재도 0개로 말하지 않는다', () {
      final s = _read(_list);
      final i = s.indexOf('if (ownerId == null) {');
      expect(i, greaterThan(-1));
      expect(s.substring(i, i + 400).contains('_loadFailed = true'), isTrue,
          reason: '예전에는 그냥 return 해서 빈 상태가 그려졌다');
    });
  });

  group('SA-FORM 나머지 네 진입구도 막혀 있다', () {
    test('SA-FORM-04 빈 상태가 역할을 인자로 받는다', () {
      final s = _read(_list);
      expect(s.contains('_buildEmptyState(context, isSubAdmin)'), isTrue,
          reason: '역할을 모르면 분기할 수 없다');
      expect(s.contains('Widget _buildEmptyState(BuildContext context, bool isSubAdmin)'),
          isTrue);
    });

    test('SA-FORM-05 목록의 추가 타일·수정 메뉴가 막혀 있다', () {
      final s = _read(_list);
      // 추가 타일은 itemCount 에서 빠진다.
      expect(
          s.contains(
              'final itemCount = isSubAdmin ? _businesses.length : _businesses.length + 1;'),
          isTrue);
      // 수정/삭제 메뉴는 `!isSubAdmin` 안에 있다.
      expect('if (!isSubAdmin)'.allMatches(s).length, greaterThanOrEqualTo(2),
          reason: '수정·삭제 두 메뉴가 각각 막혀 있어야 한다');
    });

    test('SA-FORM-06 홈 STATE A 배너와 설정 타일이 막혀 있다', () {
      final s = _read(_home);
      // STATE A: 사업장 없음 배너 — SubAdmin 은 배너 자체를 받지 않는다.
      //   `_businesses.isEmpty` 는 이 파일에 두 번 나온다(다른 경로는 토스트
      //   안내다). 그래서 **호출 지점**을 기준으로 거꾸로 본다.
      final call = s.indexOf('return _stateABanner(context, s, theme);');
      expect(call, greaterThan(-1), reason: 'STATE A 배너 호출을 찾지 못했다');
      final before = s.substring(call - 200, call);
      expect(before.contains('isSubAdmin == true) return const SizedBox.shrink()'),
          isTrue,
          reason: 'SubAdmin 이 _stateABanner 에 닿으면 등록 CTA 를 본다');
      // 첫 공고 설정 카드도 통째로 빠진다.
      final p = s.indexOf('Widget _buildPostingSetupCard(');
      expect(p, greaterThan(-1));
      expect(s.substring(p, p + 400).contains('isSubAdmin == true'), isTrue);
    });

    test('SA-FORM-07 상세 화면의 수정 버튼이 막혀 있다', () {
      final s = _read(_detail);
      final i = s.indexOf('BusinessFormScreen(business: _currentBusiness)');
      expect(i, greaterThan(-1));
      expect(s.substring(i - 400, i).contains('isSubAdmin'), isTrue);
    });

    test('SA-FORM-08 양식 자체는 역할을 알지 않는다 — 서버가 판정한다', () {
      // 화면이 자기 권한을 스스로 판정하기 시작하면 서버 판정과 갈린다.
      //   진입을 막는 것은 호출부의 일이고, 거부는 rules 의 일이다.
      final form =
          _read('lib/screens/business_admin/business_form_screen.dart');
      expect(form.contains('isSubAdmin'), isFalse,
          reason: '양식이 권한 판정을 복제하면 rules 와 갈린다');
    });
  });
}
