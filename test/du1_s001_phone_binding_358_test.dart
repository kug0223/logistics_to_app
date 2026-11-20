// [DU358] S001 휴대폰 결합 오류(소급 11 P1) — 하네스(main 앞)는 du1_s001_basic_confirm_350_test 를 글자 그대로(생성기 work/du358-s001-phone-binding/mk_test.py).
//   합성 휴대폰 서비스: 발송 · 확인을 Completer 로 붙잡을 수 있고, 확인은 번호와 무관하게 '123456' 이면 성공한다(실제 서비스처럼 이전 발송 기준).
//   사례: editAfterSend(W · B) · editDuringSend · editDuringVerify · resendDuringVerify · normalWriter(같은 번호 → 뒤로 보존 → 가입 완료 → signUp 인자) · 정적.
//   흐름(항상): 단계 도달 · 같은 번호 정상 인증 · 뒤로 보존 · signUp 인자 = 인증 번호(같은 번호 경로). 제품 기대(기본 단언, before 기록만): 번호가 바뀐 뒤
//   이전 발송 · 확인 결과로 '인증 완료'가 되지 않는다 · 묶인 흐름 무효화. writer 는 합성 UserProvider.signUp(인자 기록, false 반환)뿐이다.
// ignore_for_file: depend_on_referenced_packages, unused_element
import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/models/core/user_region.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/screens/auth/foreign_register_screen.dart';
import 'package:ALfit/services/foreign_id_ocr_service.dart';
import 'package:ALfit/services/phone_verification_service.dart';
import 'package:ALfit/theme/role_theme.dart';
import 'package:ALfit/utils/navigation_key.dart';
import 'package:ALfit/widgets/auth/terms_viewer_screen.dart';

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



final bool _beforeObs = Platform.environment['DU_BEFORE_OBSERVE'] == '358';

class _Phone implements PhoneVerificationService {
  final sends = <String>[];
  var verifies = 0;
  Completer<void>? holdSend;
  Completer<void>? holdVerify;
  @override
  Future<void> sendCode(String phone) async {
    sends.add(phone);
    final h = holdSend;
    if (h != null) await h.future;
  }

  @override
  Future<({bool valid, String? reason})> verifyCode(String phone, String code) async {
    verifies++;
    final h = holdVerify;
    if (h != null) await h.future;
    return code == '123456' ? (valid: true, reason: null) : (valid: false, reason: 'wrong_code');
  }
}

class _CapUser extends UserProvider {
  final calls = <Map<String, Object?>>[];
  @override
  Future<bool> signUp({
    required String username,
    required String password,
    required String name,
    String? phone,
    required UserRole role,
    String? businessId,
    String? gender,
    DateTime? birthDate,
    String? residentNumber,
    String? ci,
    String? foreignIdNumber,
    String accountStatus = 'active',
    String? authPhone,
    String? phoneVerificationLevel,
    String? address,
    String? detailAddress,
    UserRegion? homeRegion,
    String? idCardImageUrl,
    String? bankbookImageUrl,
    String? businessLicenseImageUrl,
    String? businessNumber,
    String? businessName,
    String? ceoName,
    String? bankName,
    String? accountNumber,
  }) async {
    calls.add({'phone': phone, 'authPhone': authPhone, 'level': phoneVerificationLevel});
    return false;
  }
}

Map<String, Object?> _termItem(String id, String title, bool req, int order) => <String, Object?>{
      'itemId': id,
      'version': 'v1',
      'title': title,
      'content': '$title 본문입니다.',
      'isRequired': req,
      'isActive': true,
      'order': order,
    };

final _fullTerms = <String, Object?>{
  'effectiveItems': [_termItem('service', '서비스 이용약관', true, 1), _termItem('privacy', '개인정보 수집 및 이용 동의', true, 2)],
  'serverNowMs': DateTime.utc(2026, 11, 15).millisecondsSinceEpoch,
  'requiredIntegrity': <String, Object?>{'ok': true},
  'upcomingItems': <Object?>[],
};

const _a = '01012345678';
const _b = '01098765432';

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
      if (name == 'callableGetEffectiveLegalTerms') return codec.encodeMessage(<Object?>[_fullTerms]);
      return codec.encodeMessage(<Object?>['du358-blocked', 'functions 호출 차단(시험)', null]);
    });
    for (final x in const ['registerIdTokenListener', 'registerAuthStateListener']) {
      m.setMockMessageHandler('dev.flutter.pigeon.firebase_auth_platform_interface.FirebaseAuthHostApi.$x',
          (_) async => codec.encodeMessage(<Object?>['du358.fake.$x']));
      m.setMockMethodCallHandler(MethodChannel('du358.fake.$x'), (_) async => null);
    }
  });
  tearDown(ForeignRegisterHooks.reset);

  test('S-0 정적: 진행 · 가입 시작이 인증 번호와 지금 칸 값 동일성을 본다', () {
    final src = File('lib/screens/auth/foreign_register_screen.dart').readAsStringSync();
    final fresh = src.indexOf('Future<void> _commitFreshRegistration() async {');
    final signUp = src.indexOf('userProvider.signUp(', fresh);
    final vp = src.indexOf('bool _validatePhone() {');
    final checks = <String, bool>{
      '가입 시작 전 동일성': fresh > -1 && src.indexOf('_phoneBindingOk', fresh) > -1 && src.indexOf('_phoneBindingOk', fresh) < signUp,
      '단계 진행 동일성': vp > -1 && src.indexOf('_phoneBindingOk', vp) > -1 && src.indexOf('_phoneBindingOk', vp) < src.indexOf('return true;', vp),
      '확인 결과 세대 확인': src.contains('gen != _phoneReqGen'),
    };
    // ignore: avoid_print
    print('S-0 checks=$checks beforeObs=$_beforeObs');
    // ignore: avoid_print
    print('KNOWN ${checks.values.every((v) => v) ? 'ok' : 'NG'} S-0 정적 결합');
    if (!_beforeObs) {
      for (final e in checks.entries) {
        expect(e.value, isTrue, reason: e.key);
      }
    }
  });

  final cases = <({String id, String scen, double w, double h, double s})>[
    (id: 'S001PB-W', scen: 'editAfterSend', w: 392, h: 844, s: 1.0),
    (id: 'S001PB-B', scen: 'editAfterSend', w: 320, h: 640, s: 2.0),
    (id: 'S001PB-W', scen: 'editDuringSend', w: 392, h: 844, s: 1.0),
    (id: 'S001PB-W', scen: 'editDuringVerify', w: 392, h: 844, s: 1.0),
    (id: 'S001PB-W', scen: 'resendDuringVerify', w: 392, h: 844, s: 1.0),
    (id: 'S001PB-W', scen: 'normalWriter', w: 392, h: 844, s: 1.0),
  ];
  for (final c in cases) {
    testWidgets('${c.id} 휴대폰 결합 ${c.scen} ${c.w.toInt()}x${c.h.toInt()}@${c.s}', (t) async {
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
        var uploadCalls = 0, finalizeCalls = 0, markCalls = 0;
        final phone = _Phone();
        final cap = _CapUser();
        ForeignRegisterHooks.phoneService = () => phone;
        ForeignRegisterHooks.pickAndOcr = () async => (path: '/local/synthetic_pick.jpg', result: kOcrOk);
        ForeignRegisterHooks.reuseOcr = (p) async => throw Exception('합성: 재사용 없음');
        ForeignRegisterHooks.currentUid = () => 'u-local-fr-358';
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
          create: (_) => cap,
          child: RepaintBoundary(
            key: key,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              navigatorKey: navigatorKey,
              theme: RoleTheme.workerTheme,
              builder: (ctx, child) =>
                  MediaQuery(data: MediaQuery.of(ctx).copyWith(textScaler: TextScaler.linear(c.s)), child: child!),
              home: const ForeignRegisterScreen(role: UserRole.BUSINESS_ADMIN),
            ),
          ),
        ));
        await _settle(t, 12);
        final tag = '${c.id}_${c.scen}';
        final steps = <String, bool>{};
        final prod = <String, bool>{};
        final cond = {'viewport': '${c.w.toInt()}x${c.h.toInt()}', 'textScaler': c.s, 'scenario': c.scen};
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

        bool verifiedShown() => findVisibleText('인증 완료').evaluate().isNotEmpty;
        int fields() => find.byType(TextField).evaluate().length;
        Finder phoneField() => find.byType(TextField).first;

        // 기본 정보 → 휴대폰
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
        steps['휴대폰 단계'] = findVisibleTextContaining('본인 명의 휴대폰').evaluate().isNotEmpty;

        // 발송 A
        await typeIn(phoneField(), _a);
        if (c.scen == 'editDuringSend') phone.holdSend = Completer<void>();
        await tapVis(btnOf('인증번호 받기'));
        await _settle(t, 4);

        switch (c.scen) {
          case 'editAfterSend':
            await waitToast();
            steps['A 발송 → 인증번호 칸'] = fields() == 2;
            await vqCapture(t, key, '${tag}_1_sentA', conditions: {...cond, 'state': 'A 발송 뒤'});
            await typeIn(phoneField(), _b);
            await _settle(t, 4);
            prod['번호 편집 → 인증번호 칸 무효'] = fields() == 1 && findVisibleText('인증번호 받기').evaluate().isNotEmpty;
            await vqCapture(t, key, '${tag}_2_editedB', conditions: {...cond, 'state': 'B 로 편집'});
            if (fields() == 2) {
              // before: 남아 있는 칸에 A 의 인증번호를 넣으면 B 가 '인증 완료'가 되는가
              await typeIn(find.byType(TextField).at(1), '123456');
              await _settle(t, 8);
              await waitToast();
              out('$tag stale-code verified=${verifiedShown()} shown=${find.byWidgetPredicate((w) => w is RichText && visibleText(w.text.toPlainText()).contains('9876')).evaluate().isNotEmpty}');
            }
            prod['A 인증번호로 B 인증 완료 안 됨'] = !verifiedShown();
            await vqCapture(t, key, '${tag}_3_after_stale', conditions: {...cond, 'state': '편집 뒤 이전 인증번호 시도'});
          case 'editDuringSend':
            steps['발송 중'] = find.byType(CircularProgressIndicator).evaluate().isNotEmpty;
            await typeIn(phoneField(), _b);
            await _settle(t, 2);
            phone.holdSend!.complete();
            phone.holdSend = null;
            await _settle(t, 8);
            await waitToast();
            prod['발송 중 편집 → A 발송 결과로 인증번호 칸 안 생김'] = fields() == 1;
            out('$tag sends=${phone.sends} fields=${fields()}');
          case 'editDuringVerify':
            await waitToast();
            phone.holdVerify = Completer<void>();
            await typeIn(find.byType(TextField).at(1), '123456');
            await _settle(t, 2);
            await typeIn(phoneField(), _b);
            await _settle(t, 2);
            phone.holdVerify!.complete();
            phone.holdVerify = null;
            await _settle(t, 8);
            await waitToast();
            prod['확인 중 편집 → 늦은 성공으로 인증 완료 안 됨'] = !verifiedShown();
            out('$tag verifies=${phone.verifies} verified=${verifiedShown()}');
          case 'resendDuringVerify':
            await waitToast();
            phone.holdVerify = Completer<void>();
            await typeIn(find.byType(TextField).at(1), '123456');
            await _settle(t, 2);
            final resendEl = find.ancestor(of: findVisibleText('재발송').first, matching: find.byWidgetPredicate((w) => w is ButtonStyleButton)).evaluate().single;
            final resend = find.byElementPredicate((x) => identical(x, resendEl));
            final enabled = (t.widget(resend) as ButtonStyleButton).enabled;
            out('$tag resend enabled during verify=$enabled');
            if (enabled) {
              await tapVis(resend);
              await _settle(t, 4);
            }
            phone.holdVerify!.complete();
            phone.holdVerify = null;
            await _settle(t, 8);
            await waitToast();
            prod['확인 중 재발송 → 이전 확인 결과로 인증 완료 안 됨'] = !enabled || !verifiedShown();
            out('$tag sends=${phone.sends} verified=${verifiedShown()}');
          case 'normalWriter':
            await waitToast();
            await typeIn(find.byType(TextField).at(1), '123456');
            await _settle(t, 8);
            await waitToast();
            steps['같은 번호 인증 완료'] = verifiedShown() && findVisibleText('010-1234-5678').evaluate().isNotEmpty;
            await t.tap(btnOf('다음'));
            await _settle(t, 8);
            await t.tap(find.byIcon(Icons.arrow_back).first);
            await _settle(t, 8);
            steps['뒤로 → 인증 완료 보존'] = verifiedShown();
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
            for (final title in const ['서비스 이용약관', '개인정보 수집 및 이용 동의']) {
              final row = find.ancestor(of: findVisibleTextContaining(title).first, matching: find.byType(ListTile)).first;
              await t.ensureVisible(row);
              await _settle(t, 2);
              await t.tap(find.descendant(of: row, matching: find.byType(Checkbox)));
              await _settle(t, 12);
              final agree = find.descendant(of: find.byType(TermsViewerScreen), matching: find.byType(ElevatedButton));
              if (agree.evaluate().isEmpty) break;
              await t.tap(agree.first);
              await _settle(t, 12);
            }
            await t.tap(btnOf('가입 완료'));
            await _settle(t, 12);
            await waitToast();
            out('$tag signUp=${cap.calls}');
            steps['signUp 인자 = 인증 번호'] = cap.calls.length == 1 &&
                cap.calls.single['phone'] == _a &&
                cap.calls.single['authPhone'] == _a &&
                cap.calls.single['level'] == 'otp_verified';
        }

        expect(t.takeException(), isNull);
        final flowOk = steps.values.every((v) => v);
        final prodOk = prod.values.every((v) => v);
        out('$tag steps=$steps');
        out('$tag prod=$prod');
        out('$tag summary overflows=${overflows.length} writer=${uploadCalls + finalizeCalls + markCalls} signUp=${cap.calls.length} sends=${phone.sends} beforeObs=$_beforeObs');
        out('KNOWN ${flowOk ? 'ok' : 'NG'} $tag 흐름');
        out('KNOWN ${prodOk ? 'ok' : 'NG'} $tag 제품 기대(번호 결합)');
        expect(overflows, isEmpty, reason: '$tag 넘침');
        expect(uploadCalls + finalizeCalls + markCalls, 0, reason: '$tag writer hook 미진입');
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
      } finally {
        FlutterError.onError = prev;
      }
    });
  }
}
