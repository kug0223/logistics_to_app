// [ALFIT-AUTH-KAKAO-ONBOARDING.1 · 판정281 C281-01 · 앱] 삭제가 시작(BEGIN)된 뒤 실패해도 일반 화면으로 못 돌아간다.
//
//   K281-G  실패 뒤 gate 판정: BEGIN 성공 → required(서버 조회 0) · BEGIN 전/불명 → 서버 복구 상태 그대로(unknown 보존)
//   K281-P  UserProvider.enterDeletionRecovery: 현재 사용자 내림 · 재개 상태 · 일반 화면 스택 제거(1회) · 이미 재개면 재구성 0
//   K281-W  탈퇴 화면(설정에서 push) 통합: PreData 뒤 정리 실패 · Final 미완료 · 증명 만료 · 응답 불명(unknown)
//           → 재개 화면만 남고 뒤로 일반 화면 0 / BEGIN 전 실패(서버 none) · KG 취소 → 일반 복귀 유지
//   K281-M  증명 기억: 재개 화면이 새로 서도 살아 있는 증명이면 KG 재요구 0
//   K281-S  소스 계약: 파이프라인 래퍼 · BEGIN 표시 위치 · 훅 설치
//   실제 Firebase/서버/KG 왕복 = PENDING VERIFICATION. 파이프라인은 대역이 실제 래퍼와 같은 gate 호출을 한다.
// ignore_for_file: depend_on_referenced_packages
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';

import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/screens/common/deletion_reauth_screen.dart';
import 'package:ALfit/services/auth/deletion_reauth_api.dart';
import 'package:ALfit/services/auth_service.dart';
import 'package:ALfit/services/pass_verification_service.dart';
import 'package:ALfit/theme/role_theme.dart';
import 'package:ALfit/utils/navigation_key.dart';

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

class _DelApi implements DeletionReauthApi {
  final log = <String>[];
  @override
  Future<DeletionReauthTicket> start() async {
    log.add('start');
    return const DeletionReauthTicket(requestId: 'del_req');
  }

  @override
  Future<DateTime?> verify(String impUid) async {
    log.add('verify');
    return DateTime.now().add(const Duration(minutes: 10));
  }
}

/// 앱 루트 대역 — AuthWrapper 처럼 재개 상태면 어떤 일반 화면보다 먼저 재개 화면.
class _Root extends StatelessWidget {
  const _Root({required this.settingsBuilder});
  final WidgetBuilder settingsBuilder;
  @override
  Widget build(BuildContext context) {
    final recovering = context.select<UserProvider, bool>((p) => p.needsDeletionRecovery);
    if (recovering) return const Scaffold(body: Center(child: Text('RECOVERY')));
    return Scaffold(
      body: Center(
        child: TextButton(
          onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: settingsBuilder)),
          child: const Text('HOME → 설정'),
        ),
      ),
    );
  }
}

/// 설정 대역 — 실제 설정처럼 탈퇴 화면을 push 하고 true 면 로그아웃(여기선 표시만).
class _Settings extends StatelessWidget {
  const _Settings({required this.screen});
  final Widget screen;
  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: TextButton(
            onPressed: () => Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => screen)),
            child: const Text('SETTINGS 탈퇴'),
          ),
        ),
      );
}

void main() {
  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
  });

  group('K281-G 실패 뒤 gate 판정', () {
    test('K281-G1 BEGIN 성공이면 서버를 묻지 않고 required', () async {
      var asked = 0;
      final s = await AuthService.deletionGateAfterFailure(
          begun: true, query: () async { asked++; return DeletionRecoveryState.none; });
      expect(s, DeletionRecoveryState.required);
      expect(asked, 0);
    });
    test('K281-G2 BEGIN 전/불명이면 서버 복구 상태 그대로(unknown 을 none 으로 접지 않음)', () async {
      for (final v in DeletionRecoveryState.values) {
        expect(await AuthService.deletionGateAfterFailure(begun: false, query: () async => v), v);
      }
    });
    test('K281-G3 sync 는 none 이 아닐 때만 훅을 부른다', () async {
      final got = <DeletionRecoveryState>[];
      AuthService.deletionRecoveryHook = got.add;
      addTearDown(() => AuthService.deletionRecoveryHook = null);
      await AuthService.syncDeletionGateAfterFailure(begun: false, query: () async => DeletionRecoveryState.none);
      await AuthService.syncDeletionGateAfterFailure(begun: false, query: () async => DeletionRecoveryState.unknown);
      await AuthService.syncDeletionGateAfterFailure(begun: true, query: () async => DeletionRecoveryState.none);
      expect(got, [DeletionRecoveryState.unknown, DeletionRecoveryState.required]);
    });
  });

  group('K281-P provider gate', () {
    test('K281-P1 재개 상태 · 사용자 내림 · 일반 화면 제거 1회 · 이미 재개면 재구성 0', () {
      final up = UserProvider();
      var redirects = 0;
      setLoginRedirectCallback(() => redirects++);
      up.enterDeletionRecovery(DeletionRecoveryState.none);
      expect(up.needsDeletionRecovery, isFalse, reason: 'none 은 아무 것도 바꾸지 않는다');
      up.enterDeletionRecovery(DeletionRecoveryState.required);
      expect(up.needsDeletionRecovery, isTrue);
      expect(up.currentUser, isNull);
      expect(up.isLoggedIn, isFalse);
      expect(redirects, 1);
      up.enterDeletionRecovery(DeletionRecoveryState.unknown);
      expect(up.deletionRecovery, DeletionRecoveryState.unknown);
      expect(redirects, 1);
    });
  });

  group('K281-W 탈퇴 화면 통합', () {
    late UserProvider up;
    late _DelApi api;

    Future<void> pumpApp(WidgetTester t, Future<String?> Function() pipeline,
        {PassLaunchOutcome kg = const PassLaunchOutcome.returned('imp')}) async {
      t.view.physicalSize = const Size(392, 820);
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.reset);
      DeletionProofMemo.set('uid-w', null); // 시험 사이 증명 기억을 나누지 않는다
      up = UserProvider();
      api = _DelApi();
      AuthService.deletionRecoveryHook = up.enterDeletionRecovery;
      addTearDown(() => AuthService.deletionRecoveryHook = null);
      Widget root() => _Root(
            settingsBuilder: (_) => _Settings(
              screen: DeletionReauthScreen(
                intent: DeletionReauthIntent.withdraw,
                api: api,
                precheck: () async => null,
                kgLauncher: (id) async => kg,
                pipeline: pipeline,
                proofKey: 'uid-w',
              ),
            ),
          );
      // AuthWrapper 재구성 대역(main.dart 의 redirect 와 같은 pushAndRemoveUntil)
      setLoginRedirectCallback(() => navigatorKey.currentState!
          .pushAndRemoveUntil(MaterialPageRoute(builder: (_) => root()), (r) => false));
      await t.pumpWidget(ChangeNotifierProvider<UserProvider>.value(
        value: up,
        child: MaterialApp(navigatorKey: navigatorKey, theme: RoleTheme.workerTheme, home: root()),
      ));
      await t.pumpAndSettle();
      await t.tap(find.text('HOME → 설정'));
      await t.pumpAndSettle();
      await t.tap(find.text('SETTINGS 탈퇴'));
      await t.pumpAndSettle();
      await t.tap(findVisibleText('본인확인하고 탈퇴하기'));
      await t.pumpAndSettle();
      await t.tap(find.text('탈퇴하기')); // 확인창
      await t.pumpAndSettle();
    }

    Future<void> expectRecoveryOnly(WidgetTester t) async {
      expect(find.text('RECOVERY'), findsOneWidget);
      expect(find.text('SETTINGS 탈퇴'), findsNothing);
      expect(find.byType(DeletionReauthScreen), findsNothing);
      expect(navigatorKey.currentState!.canPop(), isFalse, reason: '뒤로 갈 일반 화면이 없다');
      await navigatorKey.currentState!.maybePop();
      await t.pumpAndSettle();
      expect(find.text('RECOVERY'), findsOneWidget);
      expect(find.text('HOME → 설정'), findsNothing);
    }

    // 실제 _runDeletionPipeline 과 같은 순서: 단계 실패 → syncDeletionGateAfterFailure(begun) → 문장 반환
    Future<String?> Function() failing(String err, {required bool begun, DeletionRecoveryState q = DeletionRecoveryState.required}) =>
        () async {
          await AuthService.syncDeletionGateAfterFailure(begun: begun, query: () async => q);
          return err;
        };

    testWidgets('K281-W1 PreData 성공 뒤 정리(Applications) 실패 → 재개 화면만 · 뒤로 일반 0', (t) async {
      await pumpApp(t, failing('탈퇴 처리 중 정리 단계가 완료되지 않았습니다. 다시 시도해 주세요.', begun: true));
      expect(api.log, ['start', 'verify']);
      await expectRecoveryOnly(t);
    });
    testWidgets('K281-W2 Final 미완료(partial) → 재개 화면만', (t) async {
      await pumpApp(t, failing('탈퇴가 완료되지 않았습니다. 데이터 정리를 마치려면 다시 시도해 주세요.', begun: true));
      await expectRecoveryOnly(t);
    });
    testWidgets('K281-W3 BEGIN 뒤 증명 만료(Final DELETION_REAUTH_REQUIRED) → 재개 화면만', (t) async {
      await pumpApp(t, failing(kDeletionReauthExpiredMessage, begun: true));
      await expectRecoveryOnly(t);
    });
    testWidgets('K281-W4 PreData 응답 불명 + 서버 상태 모름(unknown) → 재개 화면(unknown 보존)', (t) async {
      await pumpApp(t, failing('탈퇴 처리를 시작할 수 없습니다. 잠시 후 다시 시도해 주세요.',
          begun: false, q: DeletionRecoveryState.unknown));
      expect(up.deletionRecovery, DeletionRecoveryState.unknown);
      await expectRecoveryOnly(t);
    });
    testWidgets('K281-W5 BEGIN 전 실패이고 서버도 삭제중 아님(none) → 탈퇴 화면에 머물고 뒤로 일반 복귀', (t) async {
      await pumpApp(t, failing('탈퇴 처리를 시작할 수 없습니다. 잠시 후 다시 시도해 주세요.',
          begun: false, q: DeletionRecoveryState.none));
      expect(up.needsDeletionRecovery, isFalse);
      expect(find.byType(DeletionReauthScreen), findsOneWidget);
      await t.pageBack();
      await t.pumpAndSettle();
      expect(find.text('SETTINGS 탈퇴'), findsOneWidget);
    });
    testWidgets('K281-W6 PreData 전 KG 취소 → 파이프라인 0 · 일반 복귀 유지', (t) async {
      var piped = 0;
      await pumpApp(t, () async { piped++; return null; }, kg: const PassLaunchOutcome.canceled());
      expect(piped, 0);
      expect(up.needsDeletionRecovery, isFalse);
      await t.pageBack();
      await t.pumpAndSettle();
      expect(find.text('SETTINGS 탈퇴'), findsOneWidget);
    });
  });

  group('K281-M 증명 기억', () {
    test('K281-M1 BEGIN 뒤 실패로 화면이 바뀌어도 살아 있는 증명이면 재개는 삭제만 다시', () async {
      final api1 = _DelApi();
      final first = DeletionReauthController(
        api: api1,
        proofKey: 'uid-m',
        kgLauncher: (id) async => const PassLaunchOutcome.returned('imp'),
        pipeline: () async => '탈퇴가 완료되지 않았습니다. 데이터 정리를 마치려면 다시 시도해 주세요.',
      );
      await first.run();
      first.dispose();
      final api2 = _DelApi();
      var kg = 0;
      final resume = DeletionReauthController(
        api: api2,
        proofKey: 'uid-m',
        kgLauncher: (id) async { kg++; return const PassLaunchOutcome.returned('imp'); },
        pipeline: () async => null,
      );
      expect(resume.proofAlive, isTrue);
      await resume.run();
      expect(api2.log, isEmpty);
      expect(kg, 0);
      expect(resume.phase, DeletionReauthPhase.done);
      expect(DeletionProofMemo.get('uid-m'), isNull, reason: '완료 뒤 기억을 지운다');
      resume.dispose();
    });
  });

  group('K281-R 서버 rules fence(판정281 서버 확정 뒤 · 앱 시험이 함께 고정)', () {
    test('K281-R1 비-false 클라 쓰기 규칙 62 개 전부 fence — 61 감싸기 + 예외 1(본인 로그인 시각·FCM 토큰만)', () {
      final raw = File('firestore.rules').readAsStringSync();
      final code = raw.split('\n').where((l) => !l.trimLeft().startsWith('//')).join('\n');
      final flat = code.replaceAll(RegExp(r'\s+'), ' ');
      final stmts = RegExp(r'allow ([a-z, ]+): if (.*?);').allMatches(flat).toList();
      final writes = stmts.where((m) => RegExp('create|update|delete|write').hasMatch(m.group(1)!)).toList();
      final open = writes.where((m) => !m.group(2)!.trimLeft().startsWith('false')).toList();
      // [rules_302 갱신 · rules_297 §B-5] schedule_change_requests delete 가 `callerNotDeleting() && isSuperAdmin()`
      //   (괄호 없는 인자 없는 단일 호출)로 좁혀졌다 — 최상위 `||` 가 없어 `&& (isSuperAdmin())` 와 같은 뜻, 펜스가 맨 앞.
      //   그 꼴만 추가로 fence 로 센다(functions auth_kakao_b281 R-1 과 같은 기준).
      final fenced = open.where((m) => m.group(2)!.startsWith('callerNotDeleting() && (') ||
          RegExp(r'^callerNotDeleting\(\) && [A-Za-z_]\w*\(\)$').hasMatch(m.group(2)!.trim())).toList();
      final exception = open.where((m) => m.group(2)!.startsWith('(callerNotDeleting() ||')).toList();
      // [impl_29 · J1] 공고 업무 상태 전용 update 문 1 개 추가(fence 꼴 `callerNotDeleting() && (` 확인) → 61/60 → 62/61.
      expect(open.length, 62, reason: '비-false 클라 쓰기 규칙 수가 달라졌다 — fence 대상 재확인');
      expect(fenced.length, 61);
      expect(exception.length, 1, reason: '예외는 users 본인 update 하나뿐이어야 한다');
      expect(open.length, fenced.length + exception.length, reason: 'fence 없는 쓰기 규칙이 있다');
      expect(exception.single.group(2)!, startsWith(
          "(callerNotDeleting() || request.resource.data.diff(resource.data).affectedKeys() "
          ".hasOnly(['lastLoginAt', 'fcmToken', 'fcmTokens', 'fcmTokenUpdatedAt'])) && (isLoggedIn() && isOwner(userId) &&"));
      expect(flat, contains(
          'function callerNotDeleting() { return request.auth == null || !accountDeletionBarrierExists(request.auth.uid); }'));
    });
  });

  group('K281-S 소스 계약', () {
    test('K281-S1 래퍼가 실패마다 gate 를 맞추고 BEGIN 표시는 PreData 성공 직후 · Applications 앞', () {
      final a = File('lib/services/auth_service.dart').readAsStringSync();
      final w = a.substring(a.indexOf('Future<String?> _runDeletionPipeline() async {'),
          a.indexOf('static Future<DeletionRecoveryState> deletionGateAfterFailure('));
      expect(w, contains('_deletionBegun = false;'));
      expect(w, contains('if (err != null) await syncDeletionGateAfterFailure(begun: _deletionBegun);'));
      final steps = a.substring(a.indexOf('Future<String?> _runDeletionPipelineSteps() async {'));
      final pre = steps.indexOf("'callableDeleteAccountPreData'");
      final begun = steps.indexOf('_deletionBegun = true;');
      final apps = steps.indexOf("'callableDeleteAccountApplications'");
      expect(pre, greaterThan(0));
      expect(begun, greaterThan(pre));
      expect(apps, greaterThan(begun));
      // KG · 비밀번호 두 입구가 모두 래퍼를 지난다
      expect('_runDeletionPipeline();'.allMatches(a).length, 2);
    });
    test('K281-S2 UserProvider.initialize 가 훅을 설치한다', () {
      final u = File('lib/providers/user_provider.dart').readAsStringSync();
      final init = u.substring(u.indexOf('  void initialize() {'));
      expect(init.indexOf('AuthService.deletionRecoveryHook = enterDeletionRecovery;'),
          lessThan(init.indexOf('_authSubscription =')));
    });
  });
}
