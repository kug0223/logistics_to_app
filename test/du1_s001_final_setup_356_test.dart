// [DU356] S001 외국인 가입 셀 3(지역 · 약관 · 동의, 소급 9 채택 · 소급 10 §3-3) — 하네스(main 앞)는 du1_s001_basic_confirm_350_test 를 글자 그대로
//   (생성기 work/du356-s001-final-setup/mk_test.py). 신규 가입 경로(기본 정보 → 휴대폰(DU354 seam) → 스캔 → 정보 확인 → 마지막 단계)는 writer 0 이다.
//   약관 읽기(callableGetEffectiveLegalTerms)는 호출 순서 각본: ① 실패 ② 필수 0(선택만) ③ 붙잡음(로딩) → 정상(필수 2 · 선택 1).
//   역할 USER(지역 선택 포함) · BUSINESS_ADMIN(지역 없음) × W · B. '가입 완료'는 누르지 않는다(writer).
//   제품 기대: 약관 실패 · 필수 0 · 로딩 동안 '가입 완료' 꺼짐(약관 준비 guard) · 읽기색. 대조 시험: termsSubmitBlockReason == registerTermsBlockReason.
//   정적 시험: writer 직전 같은 판정 · 시행본 변경 재로딩이 열람 표시도 지움.
//   단언(기본): 예외 0 · 넘침 0 · writer hook 0 · 흐름 · 끊김 0 · 대비 0 · 잘림 0 · 제품 기대. DU_BEFORE_OBSERVE=356 이면 흐름 외는 기록만.
// ignore_for_file: depend_on_referenced_packages, unused_element
import 'dart:async';
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
import 'package:ALfit/screens/auth/register_screen.dart' show registerTermsBlockReason;
import 'package:ALfit/services/foreign_id_ocr_service.dart';
import 'package:ALfit/services/phone_verification_service.dart';
import 'package:ALfit/theme/role_theme.dart';
import 'package:ALfit/utils/navigation_key.dart';
import 'package:ALfit/utils/terms_submit_guard.dart';
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



final bool _beforeObs = Platform.environment['DU_BEFORE_OBSERVE'] == '356';

class _FakePhone implements PhoneVerificationService {
  @override
  Future<void> sendCode(String phone) async {}
  @override
  Future<({bool valid, String? reason})> verifyCode(String phone, String code) async =>
      code == '123456' ? (valid: true, reason: null) : (valid: false, reason: 'wrong_code');
}

Map<String, Object?> _termItem(String id, String title, bool req, int order) => <String, Object?>{
      'itemId': id,
      'version': 'v1',
      'title': title,
      'content': '$title 본문입니다. 시험용 짧은 글입니다.',
      'isRequired': req,
      'isActive': true,
      'order': order,
    };

Map<String, Object?> _termsResp(List<Map<String, Object?>> items) => <String, Object?>{
      'effectiveItems': items,
      'serverNowMs': DateTime.utc(2026, 11, 15).millisecondsSinceEpoch,
      'requiredIntegrity': <String, Object?>{'ok': true},
      'upcomingItems': <Object?>[],
    };

final _fullTerms = _termsResp([
  _termItem('service', '서비스 이용약관', true, 1),
  _termItem('privacy', '개인정보 수집 및 이용 동의', true, 2),
  _termItem('marketing', '마케팅 정보 수신 동의', false, 3),
]);
final _optionalOnly = _termsResp([_termItem('marketing', '마케팅 정보 수신 동의', false, 1)]);

String _code(String p) => File(p).readAsStringSync();

void main() {
  var functionsCalls = 0;
  var termsCalls = 0;
  Completer<void>? holdTerms;
  setUp(() => SharedPreferences.setMockInitialValues({}));
  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
    final m = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    const codec = StandardMessageCodec();
    m.setMockMessageHandler('dev.flutter.pigeon.cloud_functions_platform_interface.CloudFunctionsHostApi.call', (msg) async {
      functionsCalls++;
      final args = (codec.decodeMessage(msg) as List).first as Map;
      final name = args['functionName'] as String;
      if (name == 'callableCheckUsername') {
        return codec.encodeMessage(<Object?>[<String, Object?>{'exists': false}]);
      }
      if (name == 'callableGetEffectiveLegalTerms') {
        termsCalls++;
        if (termsCalls == 1) return codec.encodeMessage(<Object?>['du356-terms-fail', '약관 읽기 실패(시험)', null]);
        if (termsCalls == 2) return codec.encodeMessage(<Object?>[_optionalOnly]);
        if (holdTerms != null) await holdTerms!.future;
        return codec.encodeMessage(<Object?>[_fullTerms]);
      }
      return codec.encodeMessage(<Object?>['du356-blocked', 'functions 호출 차단(시험)', null]);
    });
    for (final x in const ['registerIdTokenListener', 'registerAuthStateListener']) {
      m.setMockMessageHandler('dev.flutter.pigeon.firebase_auth_platform_interface.FirebaseAuthHostApi.$x',
          (_) async => codec.encodeMessage(<Object?>['du356.fake.$x']));
      m.setMockMethodCallHandler(MethodChannel('du356.fake.$x'), (_) async => null);
    }
  });
  tearDown(ForeignRegisterHooks.reset);

  group('DU356 약관 준비 판정', () {
    test('G-1 termsSubmitBlockReason == registerTermsBlockReason(내국인 C0) — 같은 입력 같은 답', () {
      final ok = EffectiveLegalTerms.fromServer(_fullTerms);
      final optOnly = EffectiveLegalTerms.fromServer(_optionalOnly);
      final cases = <({bool loading, String? error, EffectiveLegalTerms? terms, Map<String, bool> consent})>[
        (loading: true, error: null, terms: ok, consent: const {}),
        (loading: false, error: '약관을 불러오지 못했어요', terms: null, consent: const {}),
        (loading: false, error: null, terms: null, consent: const {}),
        (loading: false, error: null, terms: optOnly, consent: const {'marketing': true}),
        (loading: false, error: null, terms: ok, consent: const {'service': true}),
        (loading: false, error: null, terms: ok, consent: const {'service': true, 'privacy': true}),
        (loading: false, error: null, terms: ok, consent: const {'service': true, 'privacy': true, 'marketing': false}),
        (loading: false, error: null, terms: ok, consent: const {'service': true, 'privacy': true, 'marketing': true}),
      ];
      for (final c in cases) {
        final a = termsSubmitBlockReason(loading: c.loading, error: c.error, terms: c.terms, consent: c.consent);
        final b = registerTermsBlockReason(loading: c.loading, error: c.error, terms: c.terms, consent: c.consent);
        expect(a, b, reason: '$c');
      }
      expect(termsSubmitBlockReason(loading: false, error: null, terms: ok, consent: const {'service': true, 'privacy': true}), isNull);
      expect(termsSubmitBlockReason(loading: false, error: null, terms: optOnly, consent: const {'marketing': true}), isNotNull);
    });

    test('G-2 화면이 진행 · 활성 · writer 직전에 같은 판정을 쓴다 · 시행본 변경 재로딩이 열람 표시도 지운다(정적)', () {
      final src = _code('lib/screens/auth/foreign_register_screen.dart');
      final checks = <String, bool>{};
      checks['공용 판정 사용'] = src.contains('termsSubmitBlockReason(');
      checks['빈 목록 every 판정 제거'] = !src.contains("_legalTerms?.activeItems.where((t) => t.isRequired).toList() ?? []");
      int at(String s, [int from = 0]) => src.indexOf(s, from);
      final fresh = at('Future<void> _commitFreshRegistration() async {');
      final fin = at('Future<void> _finalizeRegistration() async {');
      // [수리 1/3] 주석 속 '_validateFinalSetup()' 언급을 세지 않도록 실제 문장 그대로 찾는다
      const guard = 'if (!_validateFinalSetup()) return;';
      checks['fresh: writer 전 판정'] = fresh > -1 && at(guard, fresh) > -1 &&
          at(guard, fresh) < at('setState(', fresh) && at(guard, fresh) < fin;
      checks['finalize: writer 전 판정'] = fin > -1 && at(guard, fin) > -1 &&
          at(guard, fin) < at('updateUserDocument', fin) &&
          at(guard, fin) < at('callableRecordTermsConsent', fin);
      final load = at('Future<void> _loadTerms(');
      final reset = at('if (resetChoices)', load);
      checks['재로딩 열람 표시 지움'] = reset > -1 && at('_viewedTermIds.clear()', reset) > -1 &&
          at('_viewedTermIds.clear()', reset) < at('_termsLoading = false', reset);
      // ignore: avoid_print
      print('G-2 checks=$checks beforeObs=$_beforeObs');
      // ignore: avoid_print
      print('KNOWN ${checks.values.every((v) => v) ? 'ok' : 'NG'} G-2 정적 guard');
      if (!_beforeObs) {
        for (final e in checks.entries) {
          expect(e.value, isTrue, reason: e.key);
        }
      }
    });
  });

  for (final c in const [(id: 'S001F-W', w: 392.0, h: 844.0, s: 1.0), (id: 'S001F-B', w: 320.0, h: 640.0, s: 2.0)]) {
    for (final role in const [UserRole.USER, UserRole.BUSINESS_ADMIN]) {
      testWidgets('${c.id} 외국인 가입 마지막 단계 ${role.name} ${c.w.toInt()}x${c.h.toInt()}@${c.s}', (t) async {
        await t.runAsync(vqLoadFonts);
        final overflows = <String>[];
        final prev = FlutterError.onError;
        FlutterError.onError = (d) {
          final m = d.exceptionAsString();
          if (m.contains('overflowed')) {
            overflows.add(m.split('\n').first);
          } else {
            prev?.call(d);
          }
        };
        addTearDown(() => FlutterError.onError = prev);
        try {
          functionsCalls = 0;
          termsCalls = 0;
          holdTerms = null;
          var uploadCalls = 0, finalizeCalls = 0, markCalls = 0;
          ForeignRegisterHooks.phoneService = () => _FakePhone();
          ForeignRegisterHooks.pickAndOcr = () async => (path: '/local/synthetic_pick.jpg', result: kOcrOk);
          ForeignRegisterHooks.reuseOcr = (p) async => throw Exception('합성: 재사용 없음');
          ForeignRegisterHooks.currentUid = () => 'u-local-fr-356';
          ForeignRegisterHooks.upload = (a, b) async => uploadCalls++;
          ForeignRegisterHooks.readUser = (_) async => <String, dynamic>{};
          ForeignRegisterHooks.finalize = (a, b, c2, d, e) async {
            finalizeCalls++;
            return 'fp';
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
                home: ForeignRegisterScreen(role: role),
              ),
            ),
          ));
          await _settle(t, 12);
          final tag = '${c.id}_${role.name}';
          final steps = <String, bool>{};
          final prod = <String, bool>{};
          final cond = {'viewport': '${c.w.toInt()}x${c.h.toInt()}', 'textScaler': c.s, 'role': role.name};
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

          // ── 기본 정보 → 휴대폰 → 스캔 → 정보 확인 → 마지막 단계(신규, writer 0)
          final f0 = find.byType(TextFormField);
          await typeIn(f0.at(0), 'worker_01');
          await tapVis(findVisibleText('아이디 중복 확인'));
          await _settle(t, 8);
          await typeIn(f0.at(1), 'abcd1234!');
          await typeIn(f0.at(2), 'abcd1234!');
          FocusManager.instance.primaryFocus?.unfocus();
          await _settle(t, 2);
          await t.tap(btnOf('다음'));
          await _settle(t, 8);
          await typeIn(find.byType(TextField).first, '01012345678');
          await tapVis(btnOf('인증번호 받기'));
          await _settle(t, 8);
          await typeIn(find.byType(TextField).at(1), '123456');
          await _settle(t, 8);
          await waitToast();
          await t.tap(btnOf('다음'));
          await _settle(t, 8);
          await tapVis(findVisibleText('갤러리에서 선택'));
          await _settle(t, 10);
          final f3 = find.byType(TextFormField);
          await typeIn(f3.at(0), 'NGUYEN VAN AN');
          await typeIn(f3.at(2), '9001015123456');
          FocusManager.instance.primaryFocus?.unfocus();
          await _settle(t, 2);
          await t.tap(btnOf('다음'));
          await _settle(t, 8);
          steps['마지막 단계 도달'] = findVisibleTextContaining(role == UserRole.USER ? '일자리 시작 설정' : '서비스 이용 동의').evaluate().isNotEmpty;
          out('$tag termsCalls=$termsCalls');

          var avoid = 0, low = 0, clipped = 0;
          final seen = <String>{};
          final lowList = <String>[];
          Future<void> dump(String tg, {bool walk = true}) async {
            void once() {
              for (final e in find.byType(RichText).evaluate()) {
                final rp = e.renderObject! as RenderParagraph;
                final s = visibleText(rp.text.toPlainText());
                if (s.isEmpty) continue;
                final self = find.byElementPredicate((x) => identical(x, e));
                final r = t.getRect(self);
                if (r.bottom < 0 || r.top > c.h || r.width == 0) continue;
                if (find.ancestor(of: self, matching: find.byType(Icon)).evaluate().isNotEmpty) continue;
                // 비활성 버튼 글자는 대비 기준 밖(WCAG 비활성 예외)
                final btn = find.ancestor(of: self, matching: find.byWidgetPredicate((w) => w is ButtonStyleButton && !w.enabled));
                final col = rp.text.style?.color;
                final bg = _bgOf(e);
                final k = '$s@${bg.toARGB32()}@${col?.toARGB32()}';
                if (seen.contains(k)) continue;
                seen.add(k);
                for (final b in wordBreaks(rp)) {
                  if (!b.forced) {
                    avoid++;
                    out('$tg avoidable $b');
                  }
                }
                if (rp.didExceedMaxLines) {
                  clipped++;
                  out('$tg clipped "$s" w=${r.width.toStringAsFixed(1)}');
                }
                if (btn.evaluate().isNotEmpty) continue;
                final cst = col == null ? 99.0 : _contrast(Color.alphaBlend(col, bg), bg);
                if (cst < 4.5) {
                  low++;
                  lowList.add(s);
                  out('$tg low "$s" color=0x${col?.toARGB32().toRadixString(16)} bg=0x${bg.toARGB32().toRadixString(16)} contrast=${cst.toStringAsFixed(2)}');
                }
              }
            }

            once();
            if (walk) {
              final pos = t.state<ScrollableState>(body()).position;
              var guard = 0;
              while (pos.pixels < pos.maxScrollExtent - 0.5 && guard++ < 30) {
                pos.jumpTo(math.min(pos.pixels + c.h * 0.5, pos.maxScrollExtent));
                await t.pump(const Duration(milliseconds: 50));
                once();
              }
              pos.jumpTo(0);
              await t.pump(const Duration(milliseconds: 50));
            }
          }

          bool ctaOn() {
            final f = find.ancestor(of: findVisibleText('가입 완료').first, matching: find.byType(ElevatedButton));
            return t.widget<ElevatedButton>(f.first).onPressed != null;
          }

          // 지역(USER)
          if (role == UserRole.USER) {
            steps['지역 미선택 표시'] = findVisibleText('지역을 선택해주세요').evaluate().isNotEmpty;
            await dump('${tag}_0_region_empty');
            await vqCapture(t, key, '${tag}_0_region_empty', conditions: {...cond, 'state': '지역 미선택 · 약관 실패'});
            await tapVis(findVisibleText('지역을 선택해주세요'));
            await _settle(t, 10);
            await t.tap(findVisibleText('서울특별시').first);
            await _settle(t, 8);
            await t.tap(findVisibleText('강남구').first);
            await _settle(t, 10);
            steps['지역 선택됨'] = findVisibleTextContaining('서울특별시 강남구').evaluate().isNotEmpty;
          }
          // ① 약관 실패
          steps['약관 실패 안내'] = findVisibleTextContaining('약관을 불러오지 못했어요').evaluate().isNotEmpty;
          prod['약관 실패 중 가입 완료 꺼짐'] = !ctaOn();
          out('$tag error cta=${ctaOn()}');
          await dump('${tag}_1_terms_error');
          await vqCapture(t, key, '${tag}_1_terms_error', conditions: {...cond, 'state': '약관 실패'});
          // ② 필수 0
          await tapVis(btnOf('다시 시도'));
          await _settle(t, 10);
          steps['필수 0 → 불완전 안내'] = findVisibleTextContaining('약관 정보가 완전하지 않습니다').evaluate().isNotEmpty && termsCalls == 2;
          prod['필수 0 중 가입 완료 꺼짐'] = !ctaOn();
          out('$tag incomplete cta=${ctaOn()}');
          await dump('${tag}_2_terms_incomplete', walk: false);
          // ③ 로딩
          holdTerms = Completer<void>();
          await tapVis(btnOf('다시 시도'));
          await t.pump(const Duration(milliseconds: 100));
          steps['로딩 표시'] = find.byType(CircularProgressIndicator).evaluate().isNotEmpty;
          prod['로딩 중 가입 완료 꺼짐'] = !ctaOn();
          out('$tag loading cta=${ctaOn()}');
          await vqCapture(t, key, '${tag}_3_terms_loading', conditions: {...cond, 'state': '약관 로딩'});
          holdTerms!.complete();
          await _settle(t, 12);
          steps['정상 약관 → 동의 행'] = findVisibleTextContaining('서비스 이용약관').evaluate().isNotEmpty && termsCalls == 3;
          steps['필수 미동의 → 가입 완료 꺼짐'] = !ctaOn();
          await dump('${tag}_4_terms_ready');
          await vqCapture(t, key, '${tag}_4_terms_ready', conditions: {...cond, 'state': '약관 정상 · 미동의'});
          // ④ 필수 두 항목: 행 체크 → 뷰어 → 동의
          for (final title in const ['서비스 이용약관', '개인정보 수집 및 이용 동의']) {
            final row = find.ancestor(of: findVisibleTextContaining(title).first, matching: find.byType(ListTile)).first;
            await t.ensureVisible(row);
            await _settle(t, 2);
            await t.tap(find.descendant(of: row, matching: find.byType(Checkbox)));
            await _settle(t, 12);
            final agree = find.descendant(of: find.byType(TermsViewerScreen), matching: find.byType(ElevatedButton));
            steps['$title 뷰어 열림'] = agree.evaluate().isNotEmpty;
            if (agree.evaluate().isEmpty) break;
            await t.tap(agree.first);
            await _settle(t, 12);
          }
          steps['필수 동의(선택 거부) → 가입 완료 켜짐'] = ctaOn();
          await dump('${tag}_5_agreed');
          await vqCapture(t, key, '${tag}_5_agreed', conditions: {...cond, 'state': '필수 동의 · 선택 미동의'});

          expect(t.takeException(), isNull);
          final flowOk = steps.values.every((v) => v);
          final prodOk = prod.values.every((v) => v);
          out('$tag steps=$steps');
          out('$tag prod=$prod');
          out('$tag summary overflows=${overflows.length} avoidable=$avoid low=$low clipped=$clipped writer=${uploadCalls + finalizeCalls + markCalls} functions=$functionsCalls termsCalls=$termsCalls lowList=$lowList beforeObs=$_beforeObs');
          out('KNOWN ${flowOk ? 'ok' : 'NG'} $tag 흐름');
          out('KNOWN ${prodOk ? 'ok' : 'NG'} $tag 제품 기대(약관 준비 guard)');
          out('KNOWN ${avoid == 0 && low == 0 && clipped == 0 ? 'ok' : 'NG'} $tag 끊김 $avoid · 대비 $low · 잘림 $clipped');
          expect(overflows, isEmpty, reason: '$tag 넘침');
          expect(uploadCalls + finalizeCalls + markCalls, 0, reason: '$tag writer hook 미진입');
          for (final en in steps.entries) {
            expect(en.value, isTrue, reason: '$tag ${en.key}');
          }
          if (!_beforeObs) {
            expect(avoid, 0, reason: '$tag 피할 수 있는 끊김');
            expect(low, 0, reason: '$tag 대비 미달');
            expect(clipped, 0, reason: '$tag 잘림');
            for (final en in prod.entries) {
              expect(en.value, isTrue, reason: '$tag ${en.key}');
            }
          }
          await t.pumpWidget(const SizedBox.shrink());
          await t.pump(const Duration(seconds: 5));
        } finally {
          FlutterError.onError = prev;
        }
      });
    }
  }
}
