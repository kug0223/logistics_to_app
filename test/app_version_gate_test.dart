// [VERSION-GATE] 최소 버전 게이트 — **모르는 것을 최신이라고 말하지 않는다.**
//
//   예전 동작과 그 결과:
//     · `timeout(500ms, onTimeout: () => true)` — 느린 Remote Config 는
//       **확인되지 않은 채 통과**였다. 콜드 스타트에서 흔한 일이다.
//     · 늦게 끝난 판정은 `mounted == false` 라 차단 창을 띄우지도 못했다.
//     · `check()` 의 catch 가 모든 예외를 `upToDate` 로 돌려줬다.
//   → 게이트가 코드에는 있었지만 **강제되지 않았다.**
//
//   고정하는 세 문장.
//
//     UNKNOWN ≠ SUPPORTED
//     NETWORK ERROR ≠ UPDATE REQUIRED
//     NO CACHE ≠ LATEST VERSION
//
//   판정은 **실제 `AppVersionService.decide`** 를 부른다(조건식 복제 없음).
//   Navigation 은 **실제 SplashScreen** 을 띄워 확인한다.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/visible_text.dart'; // [DU255] keepWords 문구는 보이는 글자로 찾는다

import 'package:ALfit/screens/common/forced_update_screen.dart';
import 'package:ALfit/screens/common/splash_screen.dart';
import 'package:ALfit/services/app_version_service.dart';

/// 주석을 지운다 — 설명에 인용한 옛 코드가 스캔에 걸린다.
String _codeOf(String dart) => dart
    .split('\n')
    .where((l) => !l.trimLeft().startsWith('//'))
    .join('\n');

VersionGateResult _decide({
  required String current,
  required String min,
  String latest = '1.0.0',
  VersionPolicySource source = VersionPolicySource.remote,
  bool fetchedNow = true,
  String url = 'https://store.example/app',
  String? pkg = 'com.alfit.app',
}) =>
    AppVersionService.decide(
      currentVersion: current,
      minVersion: min,
      latestVersion: latest,
      source: source,
      fetchedNow: fetchedNow,
      configuredUpdateUrl: url,
      packageName: pkg,
    );

/// 실제 SplashScreen 을 띄우고 판정 결과만 주입한다.
Future<void> _pumpSplash(
  WidgetTester tester,
  Future<VersionGateResult> Function() evaluator,
) async {
  await tester.pumpWidget(MaterialApp(
    home: SplashScreen(versionEvaluator: evaluator),
  ));
}

void main() {
  group('VG-1 — 버전 비교 정확성 (§8 표)', () {
    test('VG-01 같은 버전은 통과', () {
      expect(_decide(current: '1.4.0', min: '1.4.0').status,
          VersionGateStatus.supported);
    });

    test('VG-02 한 자리 낮으면 차단', () {
      expect(_decide(current: '1.3.9', min: '1.4.0').status,
          VersionGateStatus.updateRequired);
    });

    test('VG-03 사전순 비교가 아니다 — 1.10.0 > 1.9.0', () {
      expect(_decide(current: '1.10.0', min: '1.9.0').status,
          VersionGateStatus.supported,
          reason: '문자열 비교면 "1.10.0" < "1.9.0" 이 되어 멀쩡한 앱을 막는다');
    });

    test('VG-04 메이저가 크면 통과', () {
      expect(_decide(current: '2.0.0', min: '1.9.9').status,
          VersionGateStatus.supported);
    });

    test('VG-05 빌드 번호는 비교에 쓰지 않는다 (기존 계약 유지)', () {
      // `PackageInfo.version` 은 `1.4.0+10` 의 앞부분만 준다 —
      //   정책도 버전명 기준이다. 근거 없이 바꾸지 않는다.
      expect(_decide(current: '1.4.0+10', min: '1.4.0').status,
          VersionGateStatus.supported);
      expect(_decide(current: '1.4.0', min: '1.4.0+99').status,
          VersionGateStatus.supported);
    });

    test('VG-06 현재 버전 형식 오류 → UNKNOWN', () {
      for (final bad in ['', 'abc', '1.x.0', '1.2.3.4', '..']) {
        expect(_decide(current: bad, min: '1.4.0').status,
            VersionGateStatus.unknown, reason: bad);
      }
    });

    test('VG-07 정책 값 형식 오류 → UNKNOWN (차단도 통과도 아니다)', () {
      expect(_decide(current: '1.4.0', min: 'latest').status,
          VersionGateStatus.unknown);
      expect(_decide(current: '1.4.0', min: '').status,
          VersionGateStatus.unknown);
    });

    test('VG-08 자리수가 모자라면 0 으로 채운다', () {
      expect(AppVersionService.parseVersion('2'), [2, 0, 0]);
      expect(AppVersionService.parseVersion('2.1'), [2, 1, 0]);
      expect(AppVersionService.parseVersion('2.1.3+7'), [2, 1, 3]);
      expect(AppVersionService.parseVersion('v2.1.3'), isNull);
    });

    test('VG-09 권장 업데이트는 차단이 아니다', () {
      final r = _decide(current: '1.4.0', min: '1.0.0', latest: '1.5.0');
      expect(r.status, VersionGateStatus.supported);
      expect(r.recommendUpdate, isTrue);
      expect(r.blocksEntry, isFalse);
    });
  });

  group('VG-2 — 정책 출처: 로컬 기본값은 정책이 아니다', () {
    test('VG-10 한 번도 받은 적 없으면 UNKNOWN (통과시키지 않는다)', () {
      final r = _decide(
          current: '9.9.9', min: '1.0.0',
          source: VersionPolicySource.localDefault);
      expect(r.status, VersionGateStatus.unknown,
          reason: 'setDefaults 의 1.0.0 으로 통과시키면 정책이 없는 앱이 늘 통과한다');
    });

    test('VG-11 받은 정책이면 fetch 실패여도 **캐시로 판정**한다', () {
      // 오프라인 + 캐시 최소 1.4.0 + 현재 1.3.0 → 차단
      final blocked = _decide(
          current: '1.3.0', min: '1.4.0', fetchedNow: false);
      expect(blocked.status, VersionGateStatus.updateRequired);
      expect(blocked.fromCache, isTrue);

      // 오프라인 + 캐시 기준 충족 → 통과하되 **최신 검증과 구별**된다.
      final ok = _decide(current: '1.4.0', min: '1.3.0', fetchedNow: false);
      expect(ok.status, VersionGateStatus.supported);
      expect(ok.fromCache, isTrue, reason: '캐시 통과와 최신 검증 성공은 다르다');
    });

    test('VG-12 이번에 받았으면 fromCache 가 아니다', () {
      expect(_decide(current: '1.4.0', min: '1.3.0').fromCache, isFalse);
    });
  });

  group('VG-3 — 업데이트 목적지', () {
    test('VG-20 설정값이 있으면 그대로 쓴다', () {
      expect(
          AppVersionService.resolveUpdateUrl('https://x.example/a', 'com.a.b'),
          'https://x.example/a');
    });

    test('VG-21 비어 있으면 **실행 중인 앱의 패키지명**으로 스토어를 연다', () {
      // 패키지명을 지어내지 않는다 — PackageInfo 가 준 값이다.
      expect(AppVersionService.resolveUpdateUrl('', 'com.alfit.app'),
          'https://play.google.com/store/apps/details?id=com.alfit.app');
      expect(AppVersionService.resolveUpdateUrl('   ', 'com.alfit.app'),
          contains('id=com.alfit.app'));
    });

    test('VG-22 패키지명도 없으면 null — 화면이 다른 행동을 준다', () {
      expect(AppVersionService.resolveUpdateUrl('', null), isNull);
      expect(AppVersionService.resolveUpdateUrl('', ''), isNull);
    });
  });

  group('VG-4 — resume 재확인 주기', () {
    setUp(() {
      AppVersionService.lastResult = null;
      AppVersionService.lastFetchAt = null;
    });

    test('VG-30 받은 적 없으면 재확인한다', () {
      expect(AppVersionService.shouldRecheckOnResume(DateTime(2026, 10, 13)),
          isTrue);
    });

    test('VG-31 주기 안이면 네트워크를 두드리지 않는다', () {
      AppVersionService.lastFetchAt = DateTime(2026, 10, 13, 12, 0);
      expect(
          AppVersionService.shouldRecheckOnResume(DateTime(2026, 10, 13, 12, 10)),
          isFalse);
      expect(
          AppVersionService.shouldRecheckOnResume(DateTime(2026, 10, 13, 12, 31)),
          isTrue);
    });

    test('VG-32 이미 차단 상태면 다시 확인하지 않는다', () {
      AppVersionService.lastFetchAt = DateTime(2020, 1, 1);
      AppVersionService.lastResult = const VersionGateResult(
        status: VersionGateStatus.updateRequired,
        source: VersionPolicySource.remote,
        fromCache: false,
        currentVersion: '1.0.0',
        minVersion: '2.0.0',
      );
      expect(AppVersionService.shouldRecheckOnResume(DateTime(2026, 10, 13)),
          isFalse, reason: '차단에서 정상 화면으로 돌아갈 수 없다');
    });
  });

  group('VG-5 — 실제 Splash navigation', () {
    const supported = VersionGateResult(
      status: VersionGateStatus.supported,
      source: VersionPolicySource.remote,
      fromCache: false,
      currentVersion: '1.4.0',
      minVersion: '1.0.0',
    );
    const blocked = VersionGateResult(
      status: VersionGateStatus.updateRequired,
      source: VersionPolicySource.remote,
      fromCache: false,
      currentVersion: '1.3.0',
      minVersion: '1.4.0',
      updateUrl: 'https://store.example/app',
    );
    const unknown = VersionGateResult(
      status: VersionGateStatus.unknown,
      source: VersionPolicySource.localDefault,
      fromCache: true,
      currentVersion: '1.4.0',
      minVersion: '1.0.0',
    );

    testWidgets('VG-40 느린 응답 + 업데이트 필요 — 500ms 에 통과하지 않는다',
        (tester) async {
      // 예전 코드라면 500ms 에 `true` 를 돌려주고 홈으로 갔다.
      await _pumpSplash(tester, () async {
        await Future<void>.delayed(const Duration(seconds: 3));
        return blocked;
      });
      await tester.pump(const Duration(milliseconds: 900));
      expect(find.byType(ForcedUpdateScreen), findsNothing);
      expect(findVisibleText('앱 업데이트가 필요합니다'), findsNothing,
          reason: '아직 판정 전 — 어떤 화면으로도 가지 않는다');

      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      expect(find.byType(ForcedUpdateScreen), findsOneWidget);
      expect(findVisibleText('앱 업데이트가 필요합니다'), findsOneWidget);
    });

    testWidgets('VG-41 빠른 응답 + 최신 — 차단 화면이 뜨지 않는다', (tester) async {
      await _pumpSplash(tester, () async => supported);
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(ForcedUpdateScreen), findsNothing);
      // SplashScreen 은 AuthWrapper 로 교체된다(Firebase 미초기화로 그 뒤는
      //   렌더되지 않을 수 있으므로 **차단되지 않았다**는 사실만 본다).
    });

    testWidgets('VG-42 UNKNOWN 은 통과가 아니라 확인 실패 화면이다', (tester) async {
      await _pumpSplash(tester, () async => unknown);
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();
      expect(find.byType(ForcedUpdateScreen), findsOneWidget);
      expect(findVisibleText('앱 버전을 확인하지 못했습니다'), findsOneWidget);
      expect(findVisibleText('다시 확인'), findsOneWidget,
          reason: '복구 경로가 있어야 한다');
      expect(findVisibleText('앱 업데이트가 필요합니다'), findsNothing,
          reason: '네트워크 오류를 업데이트 필요로 말하지 않는다');
    });

    testWidgets('VG-43 판정이 예외를 던져도 통과시키지 않는다', (tester) async {
      // 타입을 명시한다 —  는 Future<Never> 로 추론돼
      //   timeout 의 onTimeout 서명과 어긋난다(테스트 측 인공물).
      await _pumpSplash(tester,
          () => Future<VersionGateResult>.error(StateError('rc down')));
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();
      expect(find.byType(ForcedUpdateScreen), findsOneWidget);
      expect(findVisibleText('앱 버전을 확인하지 못했습니다'), findsOneWidget);
    });

    testWidgets('VG-44 타임아웃도 UNKNOWN 이다 (무한 로딩 아님)', (tester) async {
      await _pumpSplash(
          tester, () => Future<VersionGateResult>.delayed(
              const Duration(minutes: 5), () => supported));
      await tester.pump(const Duration(seconds: 13));
      await tester.pumpAndSettle();
      expect(find.byType(ForcedUpdateScreen), findsOneWidget);
      expect(findVisibleText('앱 버전을 확인하지 못했습니다'), findsOneWidget);
      // 남은 타이머를 정리한다.
      await tester.pump(const Duration(minutes: 5));
    });

    testWidgets('VG-45 Splash dispose 이후 응답이 화면을 건드리지 않는다',
        (tester) async {
      await _pumpSplash(tester, () async {
        await Future<void>.delayed(const Duration(seconds: 2));
        return blocked;
      });
      await tester.pump(const Duration(milliseconds: 300));
      // 화면을 치운다 — 늦게 끝난 판정이 죽은 화면에 Navigator 를 부르면 터진다.
      await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(ForcedUpdateScreen), findsNothing);
    });

    testWidgets('VG-46 차단 화면은 뒤로 가기로 우회할 수 없다', (tester) async {
      await _pumpSplash(tester, () async => blocked);
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();
      expect(find.byType(ForcedUpdateScreen), findsOneWidget);

      final popScope = tester.widget<PopScope>(
          find.descendant(of: find.byType(ForcedUpdateScreen),
              matching: find.byType(PopScope)));
      expect(popScope.canPop, isFalse);
    });

    testWidgets('VG-47 목적지가 없어도 누를 수 있는 버튼이 있다', (tester) async {
      const noUrl = VersionGateResult(
        status: VersionGateStatus.updateRequired,
        source: VersionPolicySource.remote,
        fromCache: false,
        currentVersion: '1.3.0',
        minVersion: '1.4.0',
      );
      await _pumpSplash(tester, () async => noUrl);
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();
      expect(findVisibleText('앱 업데이트가 필요합니다'), findsOneWidget);
      expect(findVisibleText('다시 확인'), findsOneWidget);
      final btn = tester.widget<ElevatedButton>(find.byType(ElevatedButton));
      expect(btn.onPressed, isNotNull,
          reason: '비활성 버튼만 남기면 사용자가 아무것도 할 수 없다');
      expect(findVisibleTextContaining('직접 검색'), findsOneWidget);
    });
  });

  group('VG-6 — 옛 동작이 남아 있지 않다', () {
    test('VG-50 500ms 통과 우회가 사라졌다', () {
      // [함정] 왜 바꿨는지 적은 **주석에 옛 코드가 인용돼 있다** —
      //   주석을 지우고 본다. 안 그러면 자기 설명에 걸려 넘어진다.
      final splash = _codeOf(File(
          'lib/screens/common/splash_screen.dart').readAsStringSync());
      expect(splash.contains('onTimeout: () => true'), isFalse,
          reason: '확인되지 않은 채 통과하는 경로');
      // 타임아웃은 통과가 아니라 UNKNOWN 으로 간다.
      expect(splash, contains('status: VersionGateStatus.unknown'));
      expect(splash.contains('_versionFuture'), isFalse,
          reason: 'boolean 하나로 판정하던 구조가 남아 있다');
    });

    test('VG-51 예외를 upToDate 로 바꾸지 않는다', () {
      final svc = _codeOf(File(
          'lib/services/app_version_service.dart').readAsStringSync());
      expect(svc.contains('return VersionCheckResult.upToDate;'), isFalse);
      // 정책 출처를 실제로 본다.
      expect(svc, contains('ValueSource.valueRemote'));
    });

    test('VG-52 캐시 주기를 0 으로 바꾸지 않았다', () {
      final svc = _codeOf(File(
          'lib/services/app_version_service.dart').readAsStringSync());
      expect(svc, contains('releaseFetchInterval = Duration(hours: 1)'));
      expect(svc, contains('kDebugMode ? Duration.zero'));
    });
  });
}
