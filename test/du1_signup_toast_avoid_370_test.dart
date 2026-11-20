// [DU370 r2] 외국인 휴대폰 단계 고정 '다음' 영역 ToastAvoidArea(소급 14 §2-4 좁은 후속) — r1(두 화면 전 단계)은 E 에 보존.
//   하네스는 du1_s001_no_code_msg_367 바탕. W 392x844@1.0 · B 320x640@2.0.
//   F(휴대폰 단계, 실제 경로):
//     ① 인증 없이 '다음' → 경고 ② 키보드(가상 viewInsets 0.4h) 위 오류 토스트 ③ 키보드 내린 뒤 '다음' → 경고
//     ④ 인증번호 발송 → 본문 끝까지 스크롤 → '다음' → 경고 ⑤ 대화상자 위 → 기본 위치 ⑥ 인증 완료 → '다음' → 스캔 단계: 등록 해제 · 기본 위치.
//   I(기본 정보 단계) · S(복구 스캔 단계): 다른 단계는 기본 위치 그대로(불변).
//   제품 기대(기본 단언, DU_BEFORE_OBSERVE=370 은 기록만): ①③④ 토스트 ↔ 실제 '다음' 버튼 겹침 0 · 간격 ≥ 8 · 화면 안.
//   불변(항상 단언): ② 키보드 위 · ⑤ 위 route 기본 위치 · ⑥ 단계 이동 뒤 해제 · I · S 기본 위치.
//   본문 버튼 · 입력 칸과의 겹침은 KNOWN 기록(IgnorePointer 통과는 가시성 보장이 아니다 — 보고에서 따로 판단).
// ignore_for_file: depend_on_referenced_packages, unused_element
import 'dart:async';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/screens/auth/foreign_register_screen.dart';
import 'package:ALfit/services/phone_verification_service.dart';
import 'package:ALfit/theme/role_theme.dart';
import 'package:ALfit/utils/navigation_key.dart';
import 'package:ALfit/utils/toast_helper.dart';

import 'support/du1_vq_capture.dart';
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

Future<void> _settle(WidgetTester t, [int n = 8]) async {
  for (var i = 0; i < n; i++) {
    await t.pump(const Duration(milliseconds: 50));
  }
}

final bool _beforeObs = Platform.environment['DU_BEFORE_OBSERVE'] == '370';

class _Phone implements PhoneVerificationService {
  final sends = <String>[];
  final verifies = <Completer<({bool valid, String? reason})>>[];
  @override
  Future<void> sendCode(String phone) async {
    sends.add(phone);
  }

  @override
  Future<({bool valid, String? reason})> verifyCode(String phone, String code) {
    final c = Completer<({bool valid, String? reason})>();
    verifies.add(c);
    return c.future;
  }
}

// [DU378 추종] 같은 문구의 본문 안 지속 안내(DU378)와 구별 — 토스트는 화면(Scaffold) 밖 오버레이 항목이다
Finder _toastText(String m) => find.byElementPredicate((e) {
      final w = e.widget;
      if (w is! RichText || visibleText(w.text.toPlainText()) != m) return false;
      var inScaffold = false;
      e.visitAncestorElements((a) {
        if (a.widget is Scaffold) {
          inScaffold = true;
          return false;
        }
        return true;
      });
      return !inScaffold;
    });

Rect _toastRect(WidgetTester t, String m) =>
    t.getRect(find.ancestor(of: _toastText(m).first, matching: find.byType(Container)).first);

double _overlapH(Rect a, Rect b) {
  final i = a.intersect(b);
  return (i.width > 0 && i.height > 0) ? i.height : 0.0;
}

void _out(String s) {
  // ignore: avoid_print
  print(s);
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
    final m = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    const codec = StandardMessageCodec();
    m.setMockMessageHandler('dev.flutter.pigeon.cloud_functions_platform_interface.CloudFunctionsHostApi.call', (msg) async {
      final args = (codec.decodeMessage(msg) as List).first as Map;
      final name = args['functionName'] as String;
      if (name == 'callableCheckUsername') return codec.encodeMessage(<Object?>[<String, Object?>{'exists': false}]);
      return codec.encodeMessage(<Object?>['du370-blocked', 'functions 호출 차단(시험)', null]);
    });
    for (final x in const ['registerIdTokenListener', 'registerAuthStateListener']) {
      m.setMockMessageHandler('dev.flutter.pigeon.firebase_auth_platform_interface.FirebaseAuthHostApi.$x',
          (_) async => codec.encodeMessage(<Object?>['du370.fake.$x']));
      m.setMockMethodCallHandler(MethodChannel('du370.fake.$x'), (_) async => null);
    }
  });
  tearDown(ForeignRegisterHooks.reset);

  Widget app(GlobalKey key, double s, Widget home) => ChangeNotifierProvider<UserProvider>(
        create: (_) => UserProvider(),
        child: RepaintBoundary(
          key: key,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            navigatorKey: navigatorKey,
            theme: RoleTheme.workerTheme,
            builder: (ctx, child) =>
                MediaQuery(data: MediaQuery.of(ctx).copyWith(textScaler: TextScaler.linear(s)), child: child!),
            home: home,
          ),
        ),
      );

  Finder btnOf(String label) =>
      find.ancestor(of: findVisibleText(label).first, matching: find.byWidgetPredicate((w) => w is ButtonStyleButton)).first;

  Future<void> endCase(WidgetTester t) async {
    await t.pump(const Duration(seconds: 5));
    await t.pumpWidget(const SizedBox.shrink());
    await t.pump(const Duration(seconds: 5));
    _out('avoidTop after unmount=${ToastHelper.avoidTop.value}');
  }

  // 본문 버튼 · 입력 칸과의 겹침(기록) — 하단 '다음'(nextTop 아래) 제외
  List<String> bodyOverlap(WidgetTester t, Rect tr, double nextTop) {
    final out = <String>[];
    for (final e in find.byWidgetPredicate((w) => w is TextField || w is ButtonStyleButton).evaluate()) {
      final r = t.getRect(find.byWidget(e.widget).first);
      if (r.top >= nextTop - 0.5) continue;
      final o = _overlapH(tr, r);
      if (o > 0) out.add('${e.widget.runtimeType}@${r.top.toStringAsFixed(1)}–${r.bottom.toStringAsFixed(1)}:${o.toStringAsFixed(1)}');
    }
    return out;
  }

  // 토스트 ↔ 실제 '다음' 버튼(제품 기대) + 본문 겹침(기록)
  void judgeNext(WidgetTester t, String id, String msg, double h) {
    final tr = _toastRect(t, msg);
    final br = t.getRect(btnOf('다음'));
    final ov = _overlapH(tr, br);
    final gap = br.top - tr.bottom;
    final onScreen = tr.top >= 0 && tr.bottom <= h;
    final body = bodyOverlap(t, tr, br.top);
    _out('$id toast=${tr.top.toStringAsFixed(1)}–${tr.bottom.toStringAsFixed(1)} next=${br.top.toStringAsFixed(1)}–${br.bottom.toStringAsFixed(1)} '
        'overlap=${ov.toStringAsFixed(1)} gap=${gap.toStringAsFixed(1)} onScreen=$onScreen avoidTop=${ToastHelper.avoidTop.value?.toStringAsFixed(1)} beforeObs=$_beforeObs');
    final ok = ov == 0 && gap >= 8 - 0.01 && onScreen;
    _out('KNOWN ${ok ? 'ok' : 'NG'} $id 토스트 ↔ 실제 다음 겹침 ${ov.toStringAsFixed(1)} · 간격 ${gap.toStringAsFixed(1)}');
    _out('KNOWN ${body.isEmpty ? 'ok' : 'NG'} $id 본문 버튼 · 칸 겹침(기록) $body');
    if (!_beforeObs) {
      expect(ov, 0, reason: '$id 토스트가 실제 다음을 덮지 않음');
      expect(gap, greaterThanOrEqualTo(8 - 0.01), reason: '$id 다음 윗변과 간격');
      expect(onScreen, isTrue, reason: '$id 토스트 화면 안');
    }
  }

  // 불변: 기본 위치(아래 끝 = h - 24) · 등록 없음
  void judgeDefault(WidgetTester t, String id, String msg, double h, {bool expectNoArea = true}) {
    final tr = _toastRect(t, msg);
    final at = ToastHelper.avoidTop.value;
    final ok = (tr.bottom - (h - 24)).abs() <= 0.5 && (!expectNoArea || at == null);
    _out('$id toast=${tr.top.toStringAsFixed(1)}–${tr.bottom.toStringAsFixed(1)} expect bottom=${(h - 24).toStringAsFixed(1)} avoidTop=$at');
    _out('KNOWN ${ok ? 'ok' : 'NG'} $id 기본 위치(불변)');
    expect(ok, isTrue, reason: '$id 기본 위치(불변)');
  }

  Future<void> typeIn(WidgetTester t, Finder f, String v) async {
    await t.ensureVisible(f);
    await _settle(t, 2);
    await t.enterText(f, v);
  }

  Future<void> toPhoneStep(WidgetTester t) async {
    final f0 = find.byType(TextFormField);
    await typeIn(t, f0.at(0), 'worker_01');
    await t.ensureVisible(findVisibleText('아이디 중복 확인'));
    await t.tap(findVisibleText('아이디 중복 확인'));
    await _settle(t, 8);
    await typeIn(t, f0.at(1), 'abcd1234!');
    await typeIn(t, f0.at(2), 'abcd1234!');
    FocusManager.instance.primaryFocus?.unfocus();
    await _settle(t, 2);
    await t.tap(btnOf('다음'));
    await _settle(t, 8);
    expect(findVisibleText('인증번호 받기'), findsWidgets, reason: '휴대폰 단계 도달(흐름)');
    await t.pump(const Duration(milliseconds: 4500));
  }

  // [DU378 추종] 인증 없이 '다음'은 이제 토스트가 아니라 본문 지속 안내다(DU378) — 휴대폰 단계 토스트 위치(ToastAvoidArea)는
  //   같은 경고 토스트를 직접 띄워 잰다(위치 계산은 호출 경로와 무관). 함수 이름은 원물 대조를 위해 그대로 둔다.
  Future<void> tapNextWarn(WidgetTester t) async {
    ToastHelper.showWarning('휴대폰 번호 인증을 완료해주세요');
    await t.pump(const Duration(milliseconds: 100));
    await t.pump(const Duration(milliseconds: 100));
  }

  const warn = '휴대폰 번호 인증을 완료해주세요';

  for (final c in const [(id: 'W', w: 392.0, h: 844.0, s: 1.0), (id: 'B', w: 320.0, h: 640.0, s: 2.0)]) {
    final cond = <String, Object?>{'viewport': '${c.w.toInt()}x${c.h.toInt()}', 'textScaler': c.s};

    testWidgets('F-${c.id} 외국인 휴대폰 단계 토스트 ↔ 실제 다음 ${c.w.toInt()}x${c.h.toInt()}@${c.s}', (t) async {
      await t.runAsync(vqLoadFonts);
      final phone = _Phone();
      ForeignRegisterHooks.phoneService = () => phone;
      ForeignRegisterHooks.collectionEnabled = () => false;
      ForeignRegisterHooks.currentUid = () => 'u-local-fr-370';
      ForeignRegisterHooks.readUser = (_) async => <String, dynamic>{};
      t.view.physicalSize = Size(c.w, c.h);
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.reset);
      final key = GlobalKey();
      await t.pumpWidget(app(key, c.s, const ForeignRegisterScreen(role: UserRole.BUSINESS_ADMIN)));
      await _settle(t, 12);

      // I(기본 정보 단계) 불변 — 이 단계는 바꾸지 않는다
      const im = '아이디 중복 확인을 해주세요';
      ToastHelper.showWarning(im);
      await t.pump(const Duration(milliseconds: 100));
      judgeDefault(t, 'I-${c.id}', im, c.h);
      await t.pump(const Duration(seconds: 3));

      await toPhoneStep(t);
      FocusManager.instance.primaryFocus?.unfocus();
      await _settle(t, 2);

      // ① 인증 없이 '다음'
      await tapNextWarn(t);
      expect(_toastText(warn), findsOneWidget, reason: '경고 토스트(흐름)');
      judgeNext(t, 'F-${c.id}-1', warn, c.h);
      await vqCapture(t, key, 'S001TA2-${c.id}_1_next', conditions: {...cond, 'state': '휴대폰 단계 인증 없이 다음 → 경고'});
      await t.pump(const Duration(seconds: 3));

      // ② 키보드 위(번호 칸 초점 · 하단 바는 키보드에 덮인다)
      await t.tap(find.byType(TextField).first);
      await _settle(t, 2);
      final kb = (c.h * 0.4).roundToDouble();
      t.view.viewInsets = FakeViewPadding(bottom: kb);
      await _settle(t, 4);
      const km = '인증번호 발송에 실패했습니다. 잠시 후 다시 시도해주세요';
      ToastHelper.showError(km);
      await t.pump(const Duration(milliseconds: 100));
      final kr = _toastRect(t, km);
      final kOk = kr.bottom <= c.h - kb + 0.5 && kr.top >= 0;
      _out('F-${c.id}-2 keyboard toast=${kr.top.toStringAsFixed(1)}–${kr.bottom.toStringAsFixed(1)} limit=${(c.h - kb).toStringAsFixed(1)} body=${bodyOverlap(t, kr, c.h - kb)}');
      _out('KNOWN ${kOk ? 'ok' : 'NG'} F-${c.id}-2 키보드 위(불변)');
      expect(kOk, isTrue, reason: 'F-${c.id}-2 키보드 위(불변)');
      await vqCapture(t, key, 'S001TA2-${c.id}_2_keyboard', conditions: {...cond, 'state': '키보드 ${kb.toInt()} 위 오류 토스트'});
      await t.pump(const Duration(seconds: 5));

      // ③ 키보드 내린 뒤 '다음'
      t.view.resetViewInsets();
      FocusManager.instance.primaryFocus?.unfocus();
      await _settle(t, 6);
      await tapNextWarn(t);
      judgeNext(t, 'F-${c.id}-3', warn, c.h);
      await t.pump(const Duration(seconds: 3));

      // ④ 인증번호 발송 → 본문 끝까지 스크롤 → '다음'
      await typeIn(t, find.byType(TextField).first, '01012345678');
      FocusManager.instance.primaryFocus?.unfocus();
      await _settle(t, 2);
      await t.tap(btnOf('인증번호 받기'));
      await _settle(t, 8);
      await t.pump(const Duration(milliseconds: 4500));
      expect(phone.sends, hasLength(1), reason: '발송 1회(흐름)');
      final sc = find.byType(SingleChildScrollView).first;
      await t.drag(sc, const Offset(0, -600));
      await _settle(t, 8);
      final sp = t.state<ScrollableState>(find.descendant(of: sc, matching: find.byType(Scrollable)).first).position;
      _out('F-${c.id}-4 scroll pixels=${sp.pixels.toStringAsFixed(1)} max=${sp.maxScrollExtent.toStringAsFixed(1)}');
      await tapNextWarn(t);
      judgeNext(t, 'F-${c.id}-4', warn, c.h);
      await vqCapture(t, key, 'S001TA2-${c.id}_4_scrolled', conditions: {...cond, 'state': '발송 뒤 끝까지 스크롤 · 인증 없이 다음 → 경고'});
      await t.pump(const Duration(seconds: 3));

      // ⑤ 대화상자 위 → 기본 위치
      unawaited(showDialog<void>(
          context: navigatorKey.currentContext!,
          builder: (_) => const AlertDialog(content: Text('시험 대화상자'))));
      await _settle(t, 8);
      const rm = '대화상자 위 안내';
      ToastHelper.showInfo(rm);
      await t.pump(const Duration(milliseconds: 100));
      judgeDefault(t, 'F-${c.id}-5', rm, c.h);
      navigatorKey.currentState!.pop();
      await _settle(t, 8);
      await t.pump(const Duration(seconds: 3));

      // ⑥ 인증 완료 → '다음' → 스캔 단계: 등록 해제 · 기본 위치
      await typeIn(t, find.byType(TextField).at(1), '111111');
      await _settle(t, 4);
      expect(phone.verifies, isNotEmpty, reason: '확인 요청(흐름)');
      phone.verifies.last.complete((valid: true, reason: null));
      await _settle(t, 8);
      await t.pump(const Duration(seconds: 3));
      FocusManager.instance.primaryFocus?.unfocus();
      await _settle(t, 2);
      await t.tap(btnOf('다음'));
      await _settle(t, 10);
      expect(findVisibleText('인증번호 받기'), findsNothing, reason: '스캔 단계로 이동(흐름)');
      const sm = '외국인등록증 사진을 먼저 촬영해주세요';
      ToastHelper.showWarning(sm);
      await t.pump(const Duration(milliseconds: 100));
      judgeDefault(t, 'F-${c.id}-6', sm, c.h);
      expect(t.takeException(), isNull);
      await endCase(t);
    });

    testWidgets('S-${c.id} 외국인 복구 스캔 단계 토스트 기본 위치 ${c.w.toInt()}x${c.h.toInt()}@${c.s}', (t) async {
      await t.runAsync(vqLoadFonts);
      ForeignRegisterHooks.phoneService = () => _Phone();
      ForeignRegisterHooks.collectionEnabled = () => false;
      ForeignRegisterHooks.currentUid = () => 'u-local-fr-370';
      ForeignRegisterHooks.readUser = (_) async => <String, dynamic>{};
      t.view.physicalSize = Size(c.w, c.h);
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.reset);
      final key = GlobalKey();
      await t.pumpWidget(app(key, c.s, const ForeignRegisterScreen(role: UserRole.BUSINESS_ADMIN, isResume: true)));
      await _settle(t, 12);
      expect(findVisibleText('다음'), findsNothing, reason: '스캔 단계 하단 버튼 없음(흐름)');
      const sm = '외국인등록증 사진을 먼저 촬영해주세요';
      ToastHelper.showWarning(sm);
      await t.pump(const Duration(milliseconds: 100));
      judgeDefault(t, 'S-${c.id}', sm, c.h);
      expect(t.takeException(), isNull);
      await endCase(t);
    });
  }
}
