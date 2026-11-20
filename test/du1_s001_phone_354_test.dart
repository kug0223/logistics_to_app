// [DU354] S001 외국인 가입 휴대폰 인증 단계(셀 1 나머지, 소급 9 분할) — 하네스(main 앞)는 du1_s001_basic_confirm_350_test 를 글자 그대로
//   (생성기 work/du354-s001-phone/mk_test.py). 아이디 중복 확인만 callableCheckUsername 성공(exists false)으로 답하고 나머지 functions 는 차단한다.
//   휴대폰 인증은 ForeignRegisterHooks.phoneService(DU354 seam)로 합성 서비스를 넣는다(발송 각본 · 확인은 123456 만 성공).
//   흐름: 기본 정보 → 다음 → ① 빈 칸 ② 짧은 번호 ③ 발송 실패 ④ 발송 중(두 번 눌러도 1회) ⑤ 발송 성공(인증번호 칸) ⑥ 키보드(viewInsets)
//   ⑦ 틀린 번호 ⑧ 인증 완료 → 뒤로(입력 보존) → 다음 → 다음(스캔 단계).
//   [수리 3/3] 버튼은 보이게 스크롤한 뒤 누른다(B 에서 칸 아래 버튼).
//   [수리 1/3] 키보드 기준: 포커스 칸이 키보드 위에 보이는가(하단 '다음' 은 Scaffold bottomNavigationBar 표준 동작으로 키보드에 가려진다 — 위치만 기록).
//   단언(기본): 예외 0 · 넘침 0 · writer hook 0 · 흐름(기존 동작) · 끊김 0 · 대비 미달 0 · 잘림 0 · 누르는 영역 48 · 제품 기대(포커스 이동 · 오류 위치 · 진단 코드 미노출 · 번호 줄바꿈).
//   DU_BEFORE_OBSERVE=354 면 흐름 외(시각 · 영역 · 제품 기대)는 기록만.
// ignore_for_file: depend_on_referenced_packages, unused_element
import 'dart:io';
import 'dart:math' as math;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/screens/auth/foreign_register_screen.dart';
import 'package:ALfit/services/foreign_id_ocr_service.dart';
import 'package:ALfit/services/phone_verification_service.dart';
import 'package:ALfit/theme/role_theme.dart';
import 'package:ALfit/utils/navigation_key.dart';

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



final bool _beforeObs = Platform.environment['DU_BEFORE_OBSERVE'] == '354';

class _FakePhone implements PhoneVerificationService {
  _FakePhone(this.sendScript);
  final List<Object> sendScript; // 'ok' 또는 예외
  int sendCalls = 0, verifyCalls = 0;
  @override
  Future<void> sendCode(String phone) async {
    final r = sendScript[sendCalls < sendScript.length ? sendCalls : sendScript.length - 1];
    sendCalls++;
    await Future<void>.delayed(const Duration(milliseconds: 300));
    if (r is Exception) throw r;
  }

  @override
  Future<({bool valid, String? reason})> verifyCode(String phone, String code) async {
    verifyCalls++;
    await Future<void>.delayed(const Duration(milliseconds: 300));
    return code == '123456' ? (valid: true, reason: null) : (valid: false, reason: 'wrong_code');
  }
}

void main() {
  var functionsCalls = 0;
  final fnNames = <String>[];
  setUp(() => SharedPreferences.setMockInitialValues({}));
  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
    final m = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    m.setMockMessageHandler('dev.flutter.pigeon.cloud_functions_platform_interface.CloudFunctionsHostApi.call', (msg) async {
      functionsCalls++;
      final args = (const StandardMessageCodec().decodeMessage(msg) as List).first as Map;
      final name = args['functionName'] as String;
      fnNames.add(name);
      if (name == 'callableCheckUsername') {
        return const StandardMessageCodec().encodeMessage(<Object?>[<String, Object?>{'exists': false}]);
      }
      return const StandardMessageCodec().encodeMessage(<Object?>['du354-blocked', 'functions 호출 차단(시험)', null]);
    });
    const codec = StandardMessageCodec();
    for (final x in const ['registerIdTokenListener', 'registerAuthStateListener']) {
      m.setMockMessageHandler('dev.flutter.pigeon.firebase_auth_platform_interface.FirebaseAuthHostApi.$x',
          (_) async => codec.encodeMessage(<Object?>['du354.fake.$x']));
      m.setMockMethodCallHandler(MethodChannel('du354.fake.$x'), (_) async => null);
    }
  });
  tearDown(ForeignRegisterHooks.reset);

  for (final c in const [(id: 'S001P-W', w: 392.0, h: 844.0, s: 1.0), (id: 'S001P-B', w: 320.0, h: 640.0, s: 2.0)]) {
    testWidgets('${c.id} 외국인 가입 휴대폰 인증 ${c.w.toInt()}x${c.h.toInt()}@${c.s}', (t) async {
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
        fnNames.clear();
        var uploadCalls = 0, finalizeCalls = 0, markCalls = 0;
        final phone = _FakePhone(<Object>[FirebaseAuthException(code: 'too-many-requests', message: '합성'), 'ok']);
        ForeignRegisterHooks.phoneService = () => phone;
        ForeignRegisterHooks.reuseOcr = (p) async => throw Exception('합성: 재사용 없음');
        ForeignRegisterHooks.pickAndOcr = () async => (path: '/local/synthetic_pick.jpg', result: kOcrOk);
        ForeignRegisterHooks.currentUid = () => 'u-local-fr-354';
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
              home: const ForeignRegisterScreen(role: UserRole.USER),
            ),
          ),
        ));
        await _settle(t, 12);
        final tag = c.id;
        final steps = <String, bool>{};
        final prod = <String, bool>{};
        final cond = {'viewport': '${c.w.toInt()}x${c.h.toInt()}', 'textScaler': c.s};
        Finder body() => find.descendant(of: find.byType(ForeignRegisterScreen), matching: find.byType(Scrollable)).first;
        Finder btnOf(String label) =>
            find.ancestor(of: findVisibleText(label).first, matching: find.byWidgetPredicate((w) => w is ButtonStyleButton)).first;
        // [수리 3/3] 좁은 화면(B)에서는 버튼을 칸 아래로 내리므로 하단 '다음' 막대 밑에 있을 수 있다 — 사용자처럼 스크롤해 보이게 한 뒤 누른다
        Future<void> tapBtn(Finder f) async {
          await t.ensureVisible(f);
          await _settle(t, 2);
          await t.tap(f);
        }

        Future<void> waitToast() async {
          await t.pump(const Duration(milliseconds: 4500));
          await _settle(t, 2);
        }

        // 기본 정보 채우기
        final fields = find.byType(TextFormField);
        await t.enterText(fields.at(0), 'worker_01');
        await _settle(t, 2);
        final dup = findVisibleText('아이디 중복 확인');
        await t.scrollUntilVisible(dup, 80, scrollable: body(), maxScrolls: 40);
        await t.tap(dup);
        await _settle(t, 8);
        await t.scrollUntilVisible(fields.at(1), 80, scrollable: body(), maxScrolls: 40);
        await t.enterText(fields.at(1), 'abcd1234!');
        await t.scrollUntilVisible(fields.at(2), 80, scrollable: body(), maxScrolls: 40);
        await t.enterText(fields.at(2), 'abcd1234!');
        await _settle(t, 2);
        FocusManager.instance.primaryFocus?.unfocus();
        await _settle(t, 2);
        await t.tap(btnOf('다음'));
        await _settle(t, 8);
        steps['기본 정보 → 휴대폰 단계'] = findVisibleText('본인 명의 휴대폰 번호로 인증해주세요').evaluate().isNotEmpty ||
            findVisibleTextContaining('본인 명의 휴대폰').evaluate().isNotEmpty;
        out('$tag fn=$fnNames');

        var avoid = 0, low = 0, clipped = 0;
        final seen = <String>{};
        final touch = <String, double>{};
        void dump(String tg) {
          for (final e in find.byType(RichText).evaluate()) {
            final rp = e.renderObject! as RenderParagraph;
            final s = visibleText(rp.text.toPlainText());
            if (s.isEmpty) continue;
            final self = find.byElementPredicate((x) => identical(x, e));
            final r = t.getRect(self);
            if (r.bottom < 0 || r.top > c.h || r.width == 0) continue;
            if (find.ancestor(of: self, matching: find.byType(Icon)).evaluate().isNotEmpty) continue;
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
            final cst = col == null ? 99.0 : _contrast(_overWhite(col), bg);
            if (cst < 4.5) {
              low++;
              out('$tg low "$s" color=0x${col?.toARGB32().toRadixString(16)} bg=0x${bg.toARGB32().toRadixString(16)} contrast=${cst.toStringAsFixed(2)}');
            }
          }
          // 입력 칸 글자가 칸 폭을 넘는가(가로 스크롤로 앞 글자가 잘림)
          for (final e in find.byType(EditableText).evaluate()) {
            final ed = e.widget as EditableText;
            if (ed.controller.text.isEmpty) continue;
            final f = find.byElementPredicate((x) => identical(x, e));
            final r = t.getRect(f);
            if (r.bottom < 0 || r.top > c.h || r.width == 0) continue;
            final tp = TextPainter(
                text: TextSpan(text: ed.obscureText ? '•' * ed.controller.text.length : ed.controller.text, style: ed.style),
                textDirection: TextDirection.ltr,
                textScaler: MediaQuery.textScalerOf(e),
                maxLines: 1)
              ..layout();
            final k = 'edit:${ed.controller.text}@${r.width.toStringAsFixed(0)}';
            if (tp.width > r.width - 2 && !seen.contains(k)) {
              seen.add(k);
              clipped++;
              out('$tg clipped input "${ed.controller.text}" text=${tp.width.toStringAsFixed(1)} box=${r.width.toStringAsFixed(1)}');
            }
            tp.dispose();
          }
          // 누르는 영역(보이는 버튼 전부)
          for (final e in find.byWidgetPredicate((w) => w is ButtonStyleButton).evaluate()) {
            final f = find.byElementPredicate((x) => identical(x, e));
            final r = t.getRect(f);
            if (r.bottom < 0 || r.top > c.h || r.width == 0) continue;
            final lbl = find.descendant(of: f, matching: find.byType(RichText)).evaluate().map((x) => visibleText((x.renderObject! as RenderParagraph).text.toPlainText())).join('/');
            final k = '${e.widget.runtimeType}:$lbl';
            final v = math.min(r.width, r.height);
            if (!touch.containsKey(k) || touch[k]! > v) touch[k] = v;
          }
        }

        Finder phoneField() => find.byType(TextField).first;
        dump('${tag}_1_empty');
        await vqCapture(t, key, '${tag}_1_empty', conditions: {...cond, 'state': '휴대폰 빈 칸'});

        await t.enterText(phoneField(), '0101234');
        await tapBtn(btnOf('인증번호 받기'));
        await _settle(t, 2);
        steps['짧은 번호 오류'] = findVisibleText('올바른 휴대폰 번호를 입력해주세요').evaluate().isNotEmpty && phone.sendCalls == 0;
        dump('${tag}_2_invalid');
        await vqCapture(t, key, '${tag}_2_invalid', conditions: {...cond, 'state': '짧은 번호'});

        await t.enterText(phoneField(), '01012345678');
        await tapBtn(btnOf('인증번호 받기'));
        await t.pump(const Duration(milliseconds: 100));
        steps['발송 중 표시'] = find.byType(CircularProgressIndicator).evaluate().isNotEmpty;
        await _settle(t, 8);
        final failMsg = find.byWidgetPredicate((w) => w is RichText && visibleText(w.text.toPlainText()).contains('too-many-requests'));
        out('$tag sendfail rawCode=${failMsg.evaluate().isNotEmpty} texts=${find.byType(Text).evaluate().map((e) => (e.widget as Text).data).whereType<String>().where((s) => s.contains('발송') || s.contains('잠시')).toList()}');
        steps['발송 실패 안내'] = phone.sendCalls == 1 && find.byType(TextField).evaluate().length == 1;
        prod['발송 실패 문구 진단 코드 미노출 · 안내 보임'] = failMsg.evaluate().isEmpty &&
            (findVisibleTextContaining('다시 시도해주세요').evaluate().isNotEmpty);
        dump('${tag}_3_sendfail');
        await vqCapture(t, key, '${tag}_3_sendfail', conditions: {...cond, 'state': '발송 실패'});

        // [수리 2/3] 발송 중에는 글자가 스피너로 바뀐다 — 버튼 요소를 먼저 잡아 둔다
        final sendBtnEl = btnOf('인증번호 받기').evaluate().single;
        final sendBtn = find.byElementPredicate((x) => identical(x, sendBtnEl));
        await tapBtn(sendBtn);
        await t.pump(const Duration(milliseconds: 50));
        await t.tap(sendBtn, warnIfMissed: false); // 발송 중 두 번째 누름
        await _settle(t, 10);
        steps['중복 발송 방지'] = phone.sendCalls == 2;
        await waitToast();
        steps['발송 성공 → 인증번호 칸'] = phone.sendCalls == 2 && find.byType(TextField).evaluate().length == 2;
        expect(find.byType(TextField), findsNWidgets(2), reason: '$tag 발송 성공 뒤 인증번호 칸(없으면 아래 단계 진행 불가)');
        bool focusedAt(int i) => t
            .widget<EditableText>(find.descendant(of: find.byType(TextField).at(i), matching: find.byType(EditableText)))
            .focusNode
            .hasFocus;
        out('$tag focus phone=${focusedAt(0)} code=${focusedAt(1)}');
        prod['발송 성공 → 포커스 인증번호 칸'] = focusedAt(1);
        dump('${tag}_4_codesent');
        await vqCapture(t, key, '${tag}_4_codesent', conditions: {...cond, 'state': '발송 성공'});

        // 키보드(가상 viewInsets) — 아래 '다음' 과 입력 칸이 키보드 위에 보이는가
        final kb = (c.h * 0.4).roundToDouble();
        t.view.viewInsets = FakeViewPadding(bottom: kb);
        await _settle(t, 8);
        final next = btnOf('다음');
        final nextR = t.getRect(next);
        final codeR = t.getRect(find.byType(TextField).at(1));
        final fi = focusedAt(1) ? 1 : (focusedAt(0) ? 0 : -1);
        final focR = fi < 0 ? null : t.getRect(find.byType(TextField).at(fi));
        out('$tag keyboard kb=$kb next=${nextR.top.toStringAsFixed(1)}–${nextR.bottom.toStringAsFixed(1)} code=${codeR.top.toStringAsFixed(1)}–${codeR.bottom.toStringAsFixed(1)} focused=$fi limit=${(c.h - kb).toStringAsFixed(1)} nextUnderKeyboard=${nextR.top >= c.h - kb}');
        steps['키보드: 포커스 칸이 키보드 위'] = focR != null && focR.bottom <= c.h - kb + 0.5 && focR.top >= 0;
        prod['키보드: 인증번호 칸이 키보드 위'] = codeR.bottom <= c.h - kb + 0.5 && codeR.top >= 0;
        await vqCapture(t, key, '${tag}_5_keyboard', conditions: {...cond, 'state': '키보드 ${kb.toInt()}'});
        t.view.resetViewInsets();
        await _settle(t, 8);

        await t.enterText(find.byType(TextField).at(1), '000000');
        await _settle(t, 10);
        steps['틀린 번호 오류'] = findVisibleText('인증번호가 일치하지 않습니다').evaluate().isNotEmpty && phone.verifyCalls == 1;
        {
          final errR = t.getRect(findVisibleText('인증번호가 일치하지 않습니다').first);
          final codeTop = t.getRect(find.byType(TextField).at(1)).top;
          out('$tag wrong errTop=${errR.top.toStringAsFixed(1)} codeTop=${codeTop.toStringAsFixed(1)}');
          prod['인증 오류가 인증번호 칸 아래'] = errR.top > codeTop;
        }
        await waitToast();
        dump('${tag}_6_wrong');
        await vqCapture(t, key, '${tag}_6_wrong', conditions: {...cond, 'state': '틀린 인증번호'});

        await t.enterText(find.byType(TextField).at(1), '123456');
        await _settle(t, 10);
        await waitToast();
        steps['인증 완료 카드'] = findVisibleText('인증 완료').evaluate().isNotEmpty;
        {
          final num = find.byWidgetPredicate((w) => w is RichText && RegExp(r'^[0-9-]{10,}$').hasMatch(visibleText(w.text.toPlainText())));
          var okNum = false;
          if (num.evaluate().isNotEmpty) {
            final rp = t.renderObject<RenderParagraph>(num.first);
            final txt = visibleText(rp.text.toPlainText());
            final lines = rp.getBoxesForSelection(TextSelection(baseOffset: 0, extentOffset: txt.length)).map((b) => b.top.round()).toSet().length;
            // 줄이 갈리면 경계 앞 글자가 '-' 여야 한다(숫자 묶음 중간 금지)
            var midDigit = false;
            if (lines > 1) {
              for (var i = 1; i < txt.length; i++) {
                final a = rp.getBoxesForSelection(TextSelection(baseOffset: i - 1, extentOffset: i));
                final b2 = rp.getBoxesForSelection(TextSelection(baseOffset: i, extentOffset: i + 1));
                if (a.isNotEmpty && b2.isNotEmpty && b2.first.top > a.first.top + 1 && txt[i - 1] != '-') midDigit = true;
              }
            }
            out('$tag verified number="$txt" lines=$lines midDigitBreak=$midDigit');
            okNum = txt.contains('-') && !midDigit;
          }
          prod['완료 번호 표시 형식 · 숫자 묶음 안 줄바꿈 없음'] = okNum;
        }
        dump('${tag}_7_verified');
        await vqCapture(t, key, '${tag}_7_verified', conditions: {...cond, 'state': '인증 완료'});

        // 뒤로 → 기본 정보(입력 보존) → 다음 → 휴대폰(완료 보존) → 다음
        await t.tap(find.byIcon(Icons.arrow_back).first);
        await _settle(t, 8);
        steps['뒤로 → 기본 정보 · 아이디 보존'] = find.text('worker_01').evaluate().isNotEmpty;
        await t.tap(btnOf('다음'));
        await _settle(t, 8);
        steps['다시 다음 → 인증 완료 보존'] = findVisibleText('인증 완료').evaluate().isNotEmpty;
        await t.tap(btnOf('다음'));
        await _settle(t, 8);
        steps['다음 → 스캔 단계'] = findVisibleTextContaining('촬영하거나 갤러리에서').evaluate().isNotEmpty;

        expect(t.takeException(), isNull);
        final touchLow = touch.entries.where((e) => e.value < 48 - 1e-6).map((e) => '${e.key}=${e.value.toStringAsFixed(1)}').toList();
        final flowOk = steps.values.every((v) => v);
        final prodOk = prod.values.every((v) => v);
        out('$tag steps=$steps');
        out('$tag prod=$prod');
        out('$tag touch=$touch');
        out('$tag summary overflows=${overflows.length} avoidable=$avoid low=$low clipped=$clipped touchLow=$touchLow writer=${uploadCalls + finalizeCalls + markCalls} functions=$functionsCalls fn=$fnNames beforeObs=$_beforeObs');
        out('KNOWN ${flowOk ? 'ok' : 'NG'} $tag 흐름');
        out('KNOWN ${prodOk ? 'ok' : 'NG'} $tag 제품 기대');
        out('KNOWN ${avoid == 0 && low == 0 && clipped == 0 && touchLow.isEmpty ? 'ok' : 'NG'} $tag 끊김 $avoid · 대비 $low · 잘림 $clipped · 영역 ${touchLow.length}');
        expect(overflows, isEmpty, reason: '$tag 넘침');
        expect(uploadCalls + finalizeCalls + markCalls, 0, reason: '$tag writer hook 미진입');
        for (final en in steps.entries) {
          expect(en.value, isTrue, reason: '$tag ${en.key}');
        }
        if (!_beforeObs) {
          expect(avoid, 0, reason: '$tag 피할 수 있는 끊김');
          expect(low, 0, reason: '$tag 대비 미달');
          expect(touchLow, isEmpty, reason: '$tag 누르는 영역');
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
