// [DU391] S004 내국인 가입 1단계 B 원본 넘침 2곳(DU379 관측 · 소급 17 §2-4 좁은 후속) — 하네스는 du1_s004_pass_gate_379 바탕.
//   W 392x844@1.0 · B 320x640@2.0. 실제 경로: 지원자 선택 → 다음 → 1단계 아이디 · 비밀번호 입력(조건 격자) → '외국인' 전환(안내 카드).
//   제품 기대(기본 단언, DU_BEFORE_OBSERVE=391 은 기록만):
//     ① 비밀번호 조건 격자 4항목('8자 이상' · '영문 포함' · '숫자 포함' · '특수문자 포함') — 말줄임 0 · 보이는 글자 = 원문 · 피할 수 있는 낱말 안 끊김 0
//     ② 외국인 안내 카드 제목 '외국인등록증으로 간편 가입' — 말줄임 0 · 보이는 글자 = 원문 · 카드 폭 안 · 피할 수 있는 낱말 안 끊김 0
//     ③ 넘침 0(이 흐름 전체)
//   흐름(항상 단언): 1단계 도달 · 격자 · 카드 보임 · 예외 0.
// ignore_for_file: depend_on_referenced_packages, unused_element
import 'dart:io';

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
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/screens/auth/register_screen.dart';
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

Future<void> _settle(WidgetTester t, [int n = 8]) async {
  for (var i = 0; i < n; i++) {
    await t.pump(const Duration(milliseconds: 50));
  }
}

final bool _beforeObs = Platform.environment['DU_BEFORE_OBSERVE'] == '391';
const _checks = ['8자 이상', '영문 포함', '숫자 포함', '특수문자 포함'];
const _title = '외국인등록증으로 간편 가입';

Map<String, Object?> _termItem(String id, String title, bool req, int order, String ver) => <String, Object?>{
      'itemId': id,
      'version': ver,
      'title': title,
      'content': '$title 본문($ver)입니다.',
      'isRequired': req,
      'isActive': true,
      'order': order,
    };

Map<String, Object?> _terms() => <String, Object?>{
      'effectiveItems': [
        _termItem('service', '서비스 이용약관', true, 1, 'v1'),
        _termItem('privacy', '개인정보 수집 및 이용 동의', true, 2, 'v1'),
      ],
      'serverNowMs': DateTime.utc(2026, 11, 15).millisecondsSinceEpoch,
      'requiredIntegrity': <String, Object?>{'ok': true},
      'upcomingItems': <Object?>[],
    };

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
      if (name == 'callableGetEffectiveLegalTerms') return codec.encodeMessage(<Object?>[_terms()]);
      return codec.encodeMessage(<Object?>['du391-blocked', 'functions 호출 차단(시험)', null]);
    });
    for (final x in const ['registerIdTokenListener', 'registerAuthStateListener']) {
      m.setMockMessageHandler('dev.flutter.pigeon.firebase_auth_platform_interface.FirebaseAuthHostApi.$x',
          (_) async => codec.encodeMessage(<Object?>['du391.fake.$x']));
      m.setMockMethodCallHandler(MethodChannel('du391.fake.$x'), (_) async => null);
    }
  });

  Finder btnOf(String label) =>
      find.ancestor(of: findVisibleText(label).first, matching: find.byWidgetPredicate((w) => w is ButtonStyleButton)).first;

  for (final c in const [(id: 'W', w: 392.0, h: 844.0, s: 1.0), (id: 'B', w: 320.0, h: 640.0, s: 2.0)]) {
    testWidgets('S004O-${c.id} 1단계 조건 격자 · 외국인 카드 제목 넘침 ${c.w.toInt()}x${c.h.toInt()}@${c.s}', (t) async {
      await t.runAsync(vqLoadFonts);
      final overflows = <String>[];
      final prev = FlutterError.onError;
      FlutterError.onError = (d) {
        final m = d.exceptionAsString();
        if (m.contains('overflowed')) {
          final at = RegExp(r'register_screen\.dart:(\d+)').firstMatch(d.toString())?.group(1) ?? '?';
          overflows.add('${m.split('\n').first} @L$at');
        } else {
          prev?.call(d);
        }
      };
      addTearDown(() => FlutterError.onError = prev);
      t.view.physicalSize = Size(c.w, c.h);
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.reset);
      final key = GlobalKey();
      final terms = EffectiveLegalTerms.fromServer(_terms());
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
            home: RegisterScreen(termsLoaderForTest: () async => terms),
          ),
        ),
      ));
      await _settle(t, 10);
      final tag = 'S004O-${c.id}';
      final cond = {'viewport': '${c.w.toInt()}x${c.h.toInt()}', 'textScaler': c.s};
      final role = findVisibleText('지원자로 이용');
      await t.ensureVisible(role.first);
      await _settle(t, 2);
      await t.tap(role.first);
      await _settle(t, 4);
      await t.tap(btnOf('다음'));
      await _settle(t, 10);
      expect(findVisibleTextContaining('본인인증').evaluate().isNotEmpty, isTrue, reason: '1단계 도달(흐름)');
      Future<void> typeIn(Finder f, String v) async {
        await t.ensureVisible(f);
        await _settle(t, 2);
        await t.enterText(f, v);
      }

      await typeIn(find.widgetWithText(TextFormField, '아이디'), 'worker_01');
      await t.pump(const Duration(milliseconds: 800));
      await _settle(t, 8);
      await typeIn(find.widgetWithText(TextFormField, '비밀번호'), 'abcd1234!');
      FocusManager.instance.primaryFocus?.unfocus();
      await _settle(t, 4);

      final checks = <String, bool>{};
      RenderParagraph para(Finder f) =>
          t.renderObject<RenderParagraph>(find.descendant(of: f, matching: find.byType(RichText), matchRoot: true).first);
      String measure(String label, Finder f) {
        final rp = para(f);
        final avoid = wordBreaks(rp).where((b) => !b.forced).toList();
        final ok = !rp.didExceedMaxLines && visibleText(rp.text.toPlainText()) == label && avoid.isEmpty;
        checks['$label 전문 · 낱말 끊김 0'] = ok;
        return '$label rect=${t.getRect(f)} ell=${rp.didExceedMaxLines} avoid=$avoid';
      }

      // ① 조건 격자
      final first = findVisibleText(_checks.first);
      expect(first, findsOneWidget, reason: '조건 격자 보임(흐름)');
      await t.ensureVisible(first);
      await _settle(t, 4);
      for (final label in _checks) {
        final f = findVisibleText(label);
        expect(f, findsOneWidget, reason: '$label 보임(흐름)');
        _out('$tag ${measure(label, f)}');
      }
      final last = findVisibleText(_checks.last);
      await t.ensureVisible(last);
      await _settle(t, 4);
      await vqCapture(t, key, '${tag}_1pw', conditions: {...cond, 'state': '비밀번호 조건 격자'});
      // ② 외국인 전환 → 안내 카드 제목
      final foreign = findVisibleText('외국인');
      await t.ensureVisible(foreign.first);
      await _settle(t, 2);
      await t.tap(foreign.first);
      await _settle(t, 10);
      final title = findVisibleText(_title);
      expect(title, findsOneWidget, reason: '외국인 안내 카드 보임(흐름)');
      await t.ensureVisible(title);
      await _settle(t, 4);
      _out('$tag ${measure(_title, title)}');
      final card = find.ancestor(of: title, matching: find.byWidgetPredicate((w) => w is Container && w.decoration is BoxDecoration && (w.decoration! as BoxDecoration).gradient != null)).first;
      final cr = t.getRect(card), tr = t.getRect(title);
      checks['카드 제목 카드 폭 안'] = tr.left >= cr.left - 0.5 && tr.right <= cr.right + 0.5;
      _out('$tag card=$cr title=$tr');
      await vqCapture(t, key, '${tag}_2foreign', conditions: {...cond, 'state': '외국인 안내 카드'});
      checks['넘침 0'] = overflows.isEmpty;

      _out('$tag checks=$checks overflows=${overflows.length} ${overflows.toSet()} beforeObs=$_beforeObs');
      final ok = checks.values.every((v) => v);
      _out('KNOWN ${ok ? 'ok' : 'NG'} $tag ${checks.entries.where((e) => !e.value).map((e) => e.key).toList()}');
      final exc = t.takeException();
      await t.pumpWidget(const SizedBox.shrink());
      await t.pump(const Duration(seconds: 1));
      expect(exc, isNull);
      if (!_beforeObs) {
        for (final e in checks.entries) {
          expect(e.value, isTrue, reason: '$tag ${e.key}');
        }
      }
    });
  }
}
