// [STAGE-B × VERSION-GATE] 두 통제가 **한 흐름**에서 충돌하지 않는다.
//
//   Journey: 앱 실행 → 버전 판정 → 로그인 → 계약 진입 → Signed URL →
//            PDF·서명 조회 → 복귀 → 정책 재확인
//
//   이 파일이 고정하는 세 문장.
//
//     판정 전에는 어디로도 가지 않는다.
//     막아 둔 앱은 **알림으로도** 열리지 않는다.
//     계약 문서는 그때그때 받은 링크로만 본다 — 영구 URL 로 내려앉지 않는다.
//
//   실제로 있던 우회: 알림 딥링크가 root navigator 에 **직접 push** 해서
//   차단 화면 **위로** 올라왔다. 게이트는 라우트를 대체해 막는데, push 는
//   그 위에 쌓인다 — 막아 둔 앱이 알림 한 번으로 열렸다.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ALfit/screens/common/forced_update_screen.dart';
import 'package:ALfit/screens/common/splash_screen.dart';
import 'package:ALfit/services/app_version_service.dart';

String _read(String p) => File(p).readAsStringSync();

/// 주석을 지운다 — 설명에 인용한 옛 코드가 스캔에 걸린다.
String _codeOf(String dart) => dart
    .split('\n')
    .where((l) => !l.trimLeft().startsWith('//'))
    .join('\n');

String _flat(String s) => s.replaceAll(RegExp(r'\s+'), ' ');

String _slice(String src, String start, String end) {
  final i = src.indexOf(start);
  if (i < 0) throw StateError('구간 시작을 찾지 못했다: $start');
  final j = src.indexOf(end, i + start.length);
  if (j < 0) throw StateError('구간 끝을 찾지 못했다: $end');
  return src.substring(i, j);
}

const _blocked = VersionGateResult(
  status: VersionGateStatus.updateRequired,
  source: VersionPolicySource.remote,
  fromCache: false,
  currentVersion: '1.3.0',
  minVersion: '1.4.0',
  updateUrl: 'https://store.example/app',
);
const _supported = VersionGateResult(
  status: VersionGateStatus.supported,
  source: VersionPolicySource.remote,
  fromCache: false,
  currentVersion: '1.4.0',
  minVersion: '1.0.0',
);

void main() {
  final fcm = _codeOf(_read('lib/services/fcm_service.dart'));
  final svc = _codeOf(_read('lib/services/contract_service.dart'));
  final sign = _codeOf(_read('lib/screens/contract/contract_sign_screen.dart'));
  final gateSvc = _codeOf(_read('lib/services/app_version_service.dart'));

  setUp(() {
    AppVersionService.lastResult = null;
    AppVersionService.lastFetchAt = null;
  });

  group('SBV-1 — 게이트가 계약 화면보다 앞선다', () {
    testWidgets('SBV-01 판정 전에는 어떤 화면으로도 가지 않는다', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: SplashScreen(versionEvaluator: () async {
          await Future<void>.delayed(const Duration(seconds: 2));
          return _supported;
        }),
      ));
      await tester.pump(const Duration(milliseconds: 900));
      expect(find.byType(ForcedUpdateScreen), findsNothing);
      expect(find.byType(SplashScreen), findsOneWidget,
          reason: '아직 스플래시여야 한다 — 판정 전 진입 금지');
      // 화면을 치운 뒤 타이머를 흘려보낸다 — 통과 경로의 목적지(AuthWrapper)는
      //   Provider 가 필요하고, 이 셀이 보는 것은 **판정 전 이동 없음** 이다.
      await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('SBV-02 UPDATE_REQUIRED 면 차단 화면이 라우트를 대체한다',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: SplashScreen(versionEvaluator: () async => _blocked),
      ));
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();
      expect(find.byType(ForcedUpdateScreen), findsOneWidget);
      // 스플래시가 **남아 있지 않다** — push 가 아니라 replace 다.
      expect(find.byType(SplashScreen), findsNothing);
    });
  });

  group('SBV-2 — 막아 둔 앱은 알림으로도 열리지 않는다', () {
    test('SBV-10 차단 여부를 서비스가 한 곳에서 답한다', () {
      expect(_flat(gateSvc), contains(
          'static bool get entryBlocked => lastResult?.status == '
          'VersionGateStatus.updateRequired;'));
    });

    test('SBV-11 `unknown` 은 알림을 막지 않는다 (쓰던 사용자를 끊지 않는다)', () {
      AppVersionService.lastResult = const VersionGateResult(
        status: VersionGateStatus.unknown,
        source: VersionPolicySource.localDefault,
        fromCache: true,
        currentVersion: '1.4.0',
        minVersion: '1.0.0',
      );
      expect(AppVersionService.entryBlocked, isFalse);

      AppVersionService.lastResult = _blocked;
      expect(AppVersionService.entryBlocked, isTrue);

      AppVersionService.lastResult = _supported;
      expect(AppVersionService.entryBlocked, isFalse);
    });

    test('SBV-12 FCM 의 **모든** navigator push 에 가드가 있다', () {
      // push 가 몇 곳이든, 가드 없는 곳이 하나라도 있으면 우회가 산다.
      final pushes = RegExp(r'_navigatorKey!\.currentState!\.push')
          .allMatches(fcm).length;
      final guards = RegExp(r'if \(AppVersionService\.entryBlocked\)')
          .allMatches(fcm).length;
      expect(pushes, greaterThan(0));
      expect(guards, pushes,
          reason: 'push $pushes곳 / 가드 $guards곳 — 가드 없는 push 가 남았다');
    });

    test('SBV-13 가드가 push **앞**에 온다', () {
      for (final m in RegExp(r'_navigatorKey!\.currentState!\.push')
          .allMatches(fcm)) {
        // 같은 함수 안에서 push 보다 앞에 가드가 있어야 한다.
        final before = fcm.substring(0, m.start);
        final lastGuard = before.lastIndexOf('AppVersionService.entryBlocked');
        final lastFnStart = before.lastIndexOf('\n  void ');
        expect(lastGuard, greaterThan(lastFnStart),
            reason: '이 push 앞에 가드가 없다');
      }
    });
  });

  group('SBV-3 — 계약 조회는 그때 받은 링크로만', () {
    test('SBV-20 Signed URL 호출부는 ContractService 하나다', () {
      final callers = <String>[];
      for (final f in Directory('lib').listSync(recursive: true)) {
        if (f is! File || !f.path.endsWith('.dart')) continue;
        final c = _codeOf(f.readAsStringSync());
        if (c.contains('callableGetContractPdfSignedUrl') ||
            c.contains('callableGetContractSignatureUrl')) {
          callers.add(f.path);
        }
      }
      expect(callers.length, 1, reason: '정책이 흩어졌다: $callers');
    });

    test('SBV-21 PDF 공유는 계약 **ID** 로 요청한다 (저장된 URL 아님)', () {
      final share = _slice(sign, 'Future<void> _sharePdf() async {',
          'Future<void> _sign()');
      expect(_flat(share),
          contains('_service.fetchContractPdfUrl(widget.contract.id)'));
      expect(share.contains('widget.contract.pdfUrl'), isFalse);
    });

    test('SBV-22 서명 이미지는 role 로 구분해 받는다', () {
      final f = _slice(svc, 'Future<ContractSignatureLink> fetchContractSignature',
          'Future<Uint8List> fetchContractSignatureBytes');
      expect(_flat(f), contains("'contractId': contractId"));
      expect(_flat(f), contains("'role': role"));
    });

    test('SBV-23 만료는 재발급으로 푼다 — 영구 URL 로 내려앉지 않는다', () {
      final f = _slice(svc, 'Future<Uint8List> fetchContractSignatureBytes',
          'Future<void> voidContract(String contractId)');
      expect(_flat(f), contains('resp.statusCode == 401 || resp.statusCode == 403'));
      expect(f.contains('SignatureUrl'), isFalse);
      expect(f.contains('pdfUrl'), isFalse);
    });

    test('SBV-24 캐시 키는 **판**이다 — 계정이 바뀌어도 인가를 다시 받는다', () {
      final img = _slice(sign, 'class _ContractSignatureImage', 'Widget _retry(');
      expect(_flat(img), contains(r"cacheKey: 'contract_sig_${widget.contractId}_'"));
      expect(_flat(img), contains(r'${link.version}'));
      // 링크를 못 받으면 그림이 아니라 재시도 UI — 캐시된 bytes 로 새지 않는다.
      expect(_flat(img),
          contains('if (_failed || link == null) return _retry(context);'));
    });
  });

  group('SBV-4 — resume 재확인과 복귀', () {
    test('SBV-30 차단 상태에서는 resume 재확인을 돌리지 않는다', () {
      AppVersionService.lastResult = _blocked;
      AppVersionService.lastFetchAt = DateTime(2020, 1, 1);
      expect(AppVersionService.shouldRecheckOnResume(DateTime(2026, 10, 13)),
          isFalse, reason: '차단에서 정상 화면으로 돌아갈 길을 만들지 않는다');
    });

    test('SBV-31 복귀 버튼은 **강제 재조회**로 다시 판정한다', () {
      // resume watcher 가 건너뛰어도 사용자가 직접 길을 낼 수 있어야 한다.
      final sp = _codeOf(_read('lib/screens/common/splash_screen.dart'));
      expect(_flat(sp), contains('AppVersionService.evaluate(forceFetch: true)'));
      final main = _codeOf(_read('lib/main.dart'));
      expect(_flat(main), contains('AppVersionService.evaluate(forceFetch: true)'));
    });

    test('SBV-32 재확인 중 중복 실행을 막는다', () {
      expect(_flat(gateSvc), contains('if (_running) return;'));
      expect(_flat(gateSvc), contains('whenComplete(() => _running = false)'));
    });

    test('SBV-33 resume 차단은 라우트를 **전부 치우고** 올린다', () {
      final main = _codeOf(_read('lib/main.dart'));
      final watch = _slice(main, 'AppVersionService.startResumeWatch(',
          '});');
      expect(_flat(watch), contains('pushAndRemoveUntil'));
      expect(_flat(watch), contains('(route) => false'));
    });
  });

  group('SBV-5 — DEV 환경이 섞여 있지 않다', () {
    test('SBV-40 Dart 기본 옵션과 google-services 가 같은 프로젝트다', () {
      final dev = _read('lib/firebase_options_dev.dart');
      expect(dev, contains("projectId: 'alfit-89567'"));
      expect(dev, contains("storageBucket: 'alfit-89567.firebasestorage.app'"));
      final gs = _read('android/app/google-services.json');
      expect(gs, contains('"project_id": "alfit-89567"'));
      expect(gs, contains('com.alfit.app'));
      // PROD 는 **다른 프로젝트**이고 기본값이 아니다.
      final router = _read('lib/firebase_options.dart');
      expect(router, contains("bool.fromEnvironment('IS_PROD', defaultValue: false)"));
      expect(_read('lib/firebase_options_prod.dart'),
          contains("projectId: 'alfit-prod'"));
    });

    test('SBV-41 Functions region 이 한 벌이다', () {
      final offenders = <String>[];
      for (final f in Directory('lib').listSync(recursive: true)) {
        if (f is! File || !f.path.endsWith('.dart')) continue;
        final c = _codeOf(f.readAsStringSync());
        for (final m in RegExp(r"instanceFor\(region: '([^']+)'").allMatches(c)) {
          if (m.group(1) != 'asia-northeast3') offenders.add('${f.path}:${m.group(1)}');
        }
      }
      expect(offenders, isEmpty, reason: 'region 이 갈렸다: $offenders');
    });

    test('SBV-42 App Check 는 디버그/릴리스가 나뉜다', () {
      final main = _codeOf(_read('lib/main.dart'));
      expect(_flat(main), contains('androidProvider: kDebugMode ? AndroidProvider.debug : AndroidProvider.playIntegrity'));
    });
  });
}
