// [DU359] 시행본 변경 열람 무효화 전 경로(소급 11 P1) — 하네스(main 앞)는 du1_s001_basic_confirm_350_test 를 글자 그대로(생성기 work/du359-terms-reset/mk_test.py).
//   외국인(복구 · BUSINESS_ADMIN): 스캔 → 정보 확인 → 다음(hook 경로) → 마지막 단계 → 필수 2개 뷰어로 동의 → 가입 완료 →
//     동의 기록이 TERMS_VERSION_STALE → _loadTerms(resetChoices: true) 재조회 각본:
//     R1 정상(v2) · R2 실패 → 다시 시도 → v2 · R3 필수 0 → 다시 시도 → v2. 확인: 필수 행이 '보기 *'(미열람) · 미동의 · 행 체크가 뷰어를 연다.
//   내국인: 정적(_loadTerms 가 reset 이면 조회 전에 동의 · 열람을 지움, 판정 위임) + 지역 미선택 글(W · B 대비 · 끊김).
//   단언(기본): 흐름 · 제품 기대. DU_BEFORE_OBSERVE=359 이면 제품 기대 · 정적 · 시각은 기록만.
// ignore_for_file: depend_on_referenced_packages, unused_element
import 'dart:io';
import 'dart:math' as math;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ALfit/models/core/legal_terms_model.dart';
import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/screens/auth/foreign_register_screen.dart';
import 'package:ALfit/screens/auth/register_screen.dart';
import 'package:ALfit/services/foreign_id_ocr_service.dart';
import 'package:ALfit/theme/role_theme.dart';
import 'package:ALfit/utils/navigation_key.dart';
import 'package:ALfit/widgets/auth/terms_viewer_screen.dart';

import 'support/du1_vq_capture.dart';
import 'support/du_word_break.dart';
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

const kOcrOk = ForeignIdOcrResult(legalName: 'NGUYEN VAN AN', foreignIdRaw: '9001015123456', visaType: 'E-9',
    stayExpiryDate: '2028-12-31', legalNameFailed: false, foreignIdFailed: false, visaTypeFailed: false, stayExpiryFailed: false);

double _lum(Color c) {
  double ch(double v) => v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * ch(c.r) + 0.7152 * ch(c.g) + 0.0722 * ch(c.b);
}

double _contrast(Color a, Color b) {
  final x = _lum(a), y = _lum(b);
  return (math.max(x, y) + 0.05) / (math.min(x, y) + 0.05);
}

Color _overWhite(Color c) => Color.alphaBlend(c, Colors.white);

Color _bgOf(Element e) {
  Color? found;
  e.visitAncestorElements((a) {
    final w = a.widget;
    Color? c;
    if (w is ButtonStyleButton) {
      c = w.style?.backgroundColor?.resolve(w.enabled ? <WidgetState>{} : {WidgetState.disabled});
      if (c == null && w is ElevatedButton) c = Theme.of(a).colorScheme.primary;
      if (c == null) return true;
    } else if (w is Container && w.decoration is BoxDecoration) {
      c = (w.decoration! as BoxDecoration).color;
    } else if (w is Container && w.color != null) {
      c = w.color;
    } else if (w is DecoratedBox && w.decoration is BoxDecoration) {
      c = (w.decoration as BoxDecoration).color;
    } else if (w is Material && w.type != MaterialType.transparency) {
      c = w.color ?? Theme.of(a).colorScheme.surface;
    } else if (w is ColoredBox) {
      c = w.color;
    }
    if (c == null || c.a == 0) return true;
    found = _overWhite(c);
    return false;
  });
  return found ?? Colors.white;
}

Future<void> _settle(WidgetTester t, [int n = 8]) async {
  for (var i = 0; i < n; i++) {
    await t.pump(const Duration(milliseconds: 50));
  }
}



final bool _beforeObs = Platform.environment['DU_BEFORE_OBSERVE'] == '359';

Map<String, Object?> _termItem(String id, String title, bool req, int order, String ver) => <String, Object?>{
      'itemId': id,
      'version': ver,
      'title': title,
      'content': '$title 본문($ver)입니다.',
      'isRequired': req,
      'isActive': true,
      'order': order,
    };

Map<String, Object?> _resp(List<Map<String, Object?>> items) => <String, Object?>{
      'effectiveItems': items,
      'serverNowMs': DateTime.utc(2026, 11, 15).millisecondsSinceEpoch,
      'requiredIntegrity': <String, Object?>{'ok': true},
      'upcomingItems': <Object?>[],
    };

Map<String, Object?> _full(String v) => _resp([
      _termItem('service', '서비스 이용약관', true, 1, v),
      _termItem('privacy', '개인정보 수집 및 이용 동의', true, 2, v),
    ]);
final _optionalOnly = _resp([_termItem('marketing', '마케팅 정보 수신 동의', false, 1, 'v2')]);

void main() {
  var termsCalls = 0;
  var recordCalls = 0;
  var scenario = 'R1';
  setUp(() => SharedPreferences.setMockInitialValues({}));
  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
    final m = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    const codec = StandardMessageCodec();
    m.setMockMessageHandler('dev.flutter.pigeon.cloud_functions_platform_interface.CloudFunctionsHostApi.call', (msg) async {
      final args = (codec.decodeMessage(msg) as List).first as Map;
      final name = args['functionName'] as String;
      if (name == 'callableGetEffectiveLegalTerms') {
        termsCalls++;
        if (termsCalls == 1) return codec.encodeMessage(<Object?>[_full('v1')]);
        if (termsCalls == 2) {
          if (scenario == 'R2') return codec.encodeMessage(<Object?>['du359-terms-fail', '약관 읽기 실패(시험)', null]);
          if (scenario == 'R3') return codec.encodeMessage(<Object?>[_optionalOnly]);
        }
        return codec.encodeMessage(<Object?>[_full('v2')]);
      }
      if (name == 'callableRecordTermsConsent') {
        recordCalls++;
        return codec.encodeMessage(<Object?>['failed-precondition', 'TERMS_VERSION_STALE: 시행본 변경(시험)', null]);
      }
      return codec.encodeMessage(<Object?>['du359-blocked', 'functions 호출 차단(시험)', null]);
    });
    for (final x in const ['registerIdTokenListener', 'registerAuthStateListener']) {
      m.setMockMessageHandler('dev.flutter.pigeon.firebase_auth_platform_interface.FirebaseAuthHostApi.$x',
          (_) async => codec.encodeMessage(<Object?>['du359.fake.$x']));
      m.setMockMethodCallHandler(MethodChannel('du359.fake.$x'), (_) async => null);
    }
  });
  tearDown(ForeignRegisterHooks.reset);

  test('D-S 정적: 두 화면 _loadTerms 가 reset 이면 조회(await) 전에 동의 · 열람을 지운다 · 내국인 판정 위임', () {
    final checks = <String, bool>{};
    for (final p in const ['lib/screens/auth/foreign_register_screen.dart', 'lib/screens/auth/register_screen.dart']) {
      final src = File(p).readAsStringSync();
      final load = src.indexOf('Future<void> _loadTerms(');
      final aw = src.indexOf('await ', load);
      final reset = src.indexOf('if (resetChoices)', load);
      final viewed = src.indexOf('_viewedTermIds.clear()', load);
      checks['${p.split('/').last}: reset 지움이 await 앞'] = load > -1 && reset > -1 && reset < aw && viewed > reset && viewed < aw;
    }
    checks['내국인 판정 위임'] = File('lib/screens/auth/register_screen.dart')
        .readAsStringSync()
        .contains('termsSubmitBlockReason(loading: loading, error: error, terms: terms, consent: consent)');
    // ignore: avoid_print
    print('D-S checks=$checks beforeObs=$_beforeObs');
    // ignore: avoid_print
    print('KNOWN ${checks.values.every((v) => v) ? 'ok' : 'NG'} D-S 정적');
    if (!_beforeObs) {
      for (final e in checks.entries) {
        expect(e.value, isTrue, reason: e.key);
      }
    }
  });

  for (final c in const [(id: 'TR-W', w: 392.0, h: 844.0, s: 1.0), (id: 'TR-B', w: 320.0, h: 640.0, s: 2.0)]) {
    testWidgets('${c.id} 내국인 지역 미선택 글 ${c.w.toInt()}x${c.h.toInt()}@${c.s}', (t) async {
      await t.runAsync(vqLoadFonts);
      t.view.physicalSize = Size(c.w, c.h);
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.reset);
      final key = GlobalKey();
      final terms = EffectiveLegalTerms.fromServer(_full('v1'));
      await t.pumpWidget(ChangeNotifierProvider<UserProvider>(
        create: (_) => UserProvider(),
        child: RepaintBoundary(
          key: key,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: RoleTheme.workerTheme,
            builder: (ctx, child) =>
                MediaQuery(data: MediaQuery.of(ctx).copyWith(textScaler: TextScaler.linear(c.s)), child: child!),
            home: RegisterScreen(termsLoaderForTest: () async => terms, initialUserTermsStepForTest: true),
          ),
        ),
      ));
      await _settle(t, 10);
      final f = findVisibleText('지역을 선택해주세요');
      await t.scrollUntilVisible(f, 120, scrollable: find.byType(Scrollable).first, maxScrolls: 60);
      await _settle(t, 2);
      // [수리 2/3] semanticsLabel 을 주면 Text 가 Semantics 로 감싸진다 — 찾은 것(자기 포함) 아래의 RichText 를 잰다
      final rt = find.descendant(of: f.first, matching: find.byType(RichText), matchRoot: true).first;
      final e = rt.evaluate().first;
      final rp = t.renderObject<RenderParagraph>(rt);
      final col = rp.text.style?.color ?? Colors.black;
      final bg = _bgOf(e);
      final cst = _contrast(Color.alphaBlend(col, bg), bg);
      final br = wordBreaks(rp).where((b) => !b.forced).toList();
      // ignore: avoid_print
      print('${c.id} region color=0x${col.toARGB32().toRadixString(16)} bg=0x${bg.toARGB32().toRadixString(16)} contrast=${cst.toStringAsFixed(2)} avoidable=${br.length} $br');
      await vqCapture(t, key, '${c.id}_region', conditions: {'viewport': '${c.w.toInt()}x${c.h.toInt()}', 'textScaler': c.s, 'state': '내국인 지역 미선택'});
      final ok = cst >= 4.5 && br.isEmpty;
      // ignore: avoid_print
      print('KNOWN ${ok ? 'ok' : 'NG'} ${c.id} 내국인 지역 미선택 글 대비 ${cst.toStringAsFixed(2)} · 끊김 ${br.length}');
      expect(t.takeException(), isNull);
      if (!_beforeObs) {
        expect(cst, greaterThanOrEqualTo(4.5), reason: '${c.id} 지역 미선택 글 대비');
        expect(br, isEmpty, reason: '${c.id} 지역 미선택 글 끊김');
      }
      await t.pumpWidget(const SizedBox.shrink());
    });
  }

  for (final scen in const ['R1', 'R2', 'R3']) {
    for (final c in const [(id: 'TR-W', w: 392.0, h: 844.0, s: 1.0)]) {
      testWidgets('${c.id} 외국인 시행본 변경 $scen ${c.w.toInt()}x${c.h.toInt()}@${c.s}', (t) async {
        await t.runAsync(vqLoadFonts);
        termsCalls = 0;
        recordCalls = 0;
        scenario = scen;
        var uploadCalls = 0, finalizeCalls = 0, markCalls = 0;
        ForeignRegisterHooks.pickAndOcr = () async => (path: '/local/synthetic_pick.jpg', result: kOcrOk);
        ForeignRegisterHooks.reuseOcr = (p) async => throw Exception('합성: 재사용 없음');
        ForeignRegisterHooks.currentUid = () => 'u-local-fr-359';
        ForeignRegisterHooks.upload = (a, b) async => uploadCalls++;
        ForeignRegisterHooks.readUser = (_) async => <String, dynamic>{};
        ForeignRegisterHooks.finalize = (a, b, c2, d, e) async {
          finalizeCalls++;
          return null;
        };
        ForeignRegisterHooks.mark = (_) async => markCalls++;
        ForeignRegisterHooks.collectionEnabled = () => false;
        t.view.physicalSize = Size(c.w, c.h);
        t.view.devicePixelRatio = 1.0;
        addTearDown(t.view.reset);
        final key = GlobalKey();
        void out(String l) {
          // ignore: avoid_print
          print(l);
        }

        await t.pumpWidget(ChangeNotifierProvider<UserProvider>(
          create: (_) => UserProvider(),
          child: RepaintBoundary(
            key: key,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              navigatorKey: navigatorKey,
              theme: RoleTheme.workerTheme,
              builder: (ctx, child) =>
                  MediaQuery(data: MediaQuery.of(ctx).copyWith(textScaler: TextScaler.linear(c.s)), child: child!),
              home: const ForeignRegisterScreen(role: UserRole.BUSINESS_ADMIN, isResume: true),
            ),
          ),
        ));
        await _settle(t, 12);
        final tag = '${c.id}_$scen';
        final steps = <String, bool>{};
        final prod = <String, bool>{};
        Finder body() => find.descendant(of: find.byType(ForeignRegisterScreen), matching: find.byType(Scrollable)).first;
        Finder btnOf(String label) =>
            find.ancestor(of: findVisibleText(label).first, matching: find.byWidgetPredicate((w) => w is ButtonStyleButton)).first;
        Future<void> tapVis(Finder f) async {
          await t.ensureVisible(f);
          await _settle(t, 2);
          await t.tap(f);
        }

        Future<void> typeIn(Finder f, String v) async {
          await t.ensureVisible(f);
          await _settle(t, 2);
          await t.enterText(f, v);
        }

        Future<void> waitToast() async {
          await t.pump(const Duration(milliseconds: 4500));
          await _settle(t, 2);
        }

        Finder rowOf(String title) => find.ancestor(of: findVisibleTextContaining(title).first, matching: find.byType(ListTile)).first;
        Future<void> agreeViaViewer(String title) async {
          final row = rowOf(title);
          await t.ensureVisible(row);
          await _settle(t, 2);
          await t.tap(find.descendant(of: row, matching: find.byType(Checkbox)));
          await _settle(t, 12);
          final agree = find.descendant(of: find.byType(TermsViewerScreen), matching: find.byType(ElevatedButton));
          if (agree.evaluate().isNotEmpty) {
            await t.tap(agree.first);
            await _settle(t, 12);
          }
        }

        await tapVis(findVisibleText('갤러리에서 선택'));
        await _settle(t, 10);
        final f3 = find.byType(TextFormField);
        await typeIn(f3.at(0), 'NGUYEN VAN AN');
        await typeIn(f3.at(2), '9001015123456');
        FocusManager.instance.primaryFocus?.unfocus();
        await _settle(t, 2);
        await t.tap(btnOf('다음'));
        // [수리 1/3] 복구 경로 끝의 임시 파일 삭제(File.delete)는 실제 입출력이라 가짜 시간에서 끝나지 않는다 — 실제 시간을 잠깐 준다
        for (var k = 0; k < 3; k++) {
          await _settle(t, 8);
          await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 150)));
        }
        await _settle(t, 16);
        steps['마지막 단계 도달'] = findVisibleTextContaining('서비스 이용 동의').evaluate().isNotEmpty;
        for (final title in const ['서비스 이용약관', '개인정보 수집 및 이용 동의']) {
          await agreeViaViewer(title);
        }
        steps['v1 필수 동의 → 다시보기'] = findVisibleText('다시보기').evaluate().length == 2;
        await t.tap(btnOf('가입 완료'));
        await _settle(t, 16);
        steps['동의 기록 STALE → 재조회'] = recordCalls == 1 && termsCalls == 2;
        await waitToast();
        if (scen != 'R1') {
          steps['재조회 실패/필수 0 안내'] = findVisibleText('다시 시도').evaluate().isNotEmpty;
          await tapVis(btnOf('다시 시도'));
          await _settle(t, 12);
          steps['일반 재시도 → v2'] = termsCalls == 3;
        }
        steps['v2 항목 표시'] = findVisibleTextContaining('서비스 이용약관').evaluate().isNotEmpty;
        final again = findVisibleText('다시보기').evaluate().length;
        final unseen = findVisibleText('보기 *').evaluate().length;
        final checked = find.byType(Checkbox).evaluate().map((e) => (e.widget as Checkbox).value).toList();
        out('$tag after-reset 다시보기=$again 보기*=$unseen checkbox=$checked termsCalls=$termsCalls recordCalls=$recordCalls');
        await vqCapture(t, key, '${tag}_after_reset', conditions: {'viewport': '${c.w.toInt()}x${c.h.toInt()}', 'textScaler': c.s, 'scenario': scen, 'state': '시행본 변경 뒤'});
        prod['새 버전 필수 행 미열람 표시(보기 *)'] = again == 0 && unseen == 2;
        prod['새 버전 미동의'] = !checked.contains(true);
        // 행 체크 → 뷰어가 열려야 한다(본 적 없음)
        final row = rowOf('서비스 이용약관');
        await t.ensureVisible(row);
        await _settle(t, 2);
        await t.tap(find.descendant(of: row, matching: find.byType(Checkbox)));
        await _settle(t, 12);
        final viewerOpened = find.byType(TermsViewerScreen).evaluate().isNotEmpty;
        out('$tag row-check viewerOpened=$viewerOpened');
        prod['행 체크 → 새 글 뷰어 열림(바로 체크 아님)'] = viewerOpened;
        if (viewerOpened) {
          navigatorKey.currentState!.pop();
          await _settle(t, 12);
        }
        final checked2 = find.byType(Checkbox).evaluate().map((e) => (e.widget as Checkbox).value).toList();
        prod['뷰어를 동의 없이 닫으면 미동의'] = !checked2.contains(true);

        expect(t.takeException(), isNull);
        out('$tag steps=$steps');
        out('$tag prod=$prod');
        out('$tag summary hooks upload=$uploadCalls finalize=$finalizeCalls mark=$markCalls beforeObs=$_beforeObs');
        out('KNOWN ${steps.values.every((v) => v) ? 'ok' : 'NG'} $tag 흐름');
        out('KNOWN ${prod.values.every((v) => v) ? 'ok' : 'NG'} $tag 제품 기대(새 버전 재열람)');
        for (final en in steps.entries) {
          expect(en.value, isTrue, reason: '$tag ${en.key}');
        }
        if (!_beforeObs) {
          for (final en in prod.entries) {
            expect(en.value, isTrue, reason: '$tag ${en.key}');
          }
        }
        await t.pumpWidget(const SizedBox.shrink());
        await t.pump(const Duration(seconds: 5));
      });
    }
  }
}
