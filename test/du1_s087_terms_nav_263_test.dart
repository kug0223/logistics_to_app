// ignore_for_file: depend_on_referenced_packages
// [DU263 S087 약관 읽기 — 실패 경로 baseline/after] Codex 한도 중 Claude 자체 진행(허브 DU_self_review_hub_2026-11-10).
//   같은 시험을 교정 전(baseline)·후(after)에 한 번씩 돌린다. 시험은 production 을 편집하지 않는다.
//   DU263_RUN=1 이고 DU263_PHASE 가 baseline 또는 after 일 때만 실행한다(기본 skip).
//   근로자 설정(UserSettingsScreen)에서 '서비스 이용약관' 을 눌러 연다. Firestore·Functions 통신은 즉시 오류로 막는다
//   (DU244 하네스 방식) — 약관 조회가 실패한 상태다. 알림 권한은 거부. W360/1.0·B320/2.0.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:cloud_firestore_platform_interface/cloud_firestore_platform_interface.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/screens/user/user_settings_screen.dart';
import 'package:ALfit/theme/role_theme.dart';
import 'package:ALfit/utils/navigation_key.dart';
import 'package:ALfit/utils/text_layout.dart';

import 'support/du1_vq_capture.dart';

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

class _Worker extends UserProvider {
  @override
  UserModel? get currentUser => UserModel(uid: 'u-d263', username: 'qa_worker', name: 'QA 근로자', email: 'qa@test.local',
      role: UserRole.USER, createdAt: DateTime(2026, 1, 1));
  @override
  bool get isAdminMode => false;
  @override
  bool get isSubAdmin => false;
  @override
  bool get isSuperAdmin => false;
  @override
  bool get isBusinessAdmin => false;
  @override
  String? get effectiveBusinessId => null;
}

double _lum(Color c) {
  double ch(double v) => v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * ch(c.r) + 0.7152 * ch(c.g) + 0.0722 * ch(c.b);
}

double _contrast(Color a, Color b) {
  final x = _lum(a);
  final y = _lum(b);
  return (math.max(x, y) + 0.05) / (math.min(x, y) + 0.05);
}

String _hex(Color c) => '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

void _out(String l) {
  // ignore: avoid_print
  print(l);
}

void main() {
  final phase = Platform.environment['DU263_PHASE'] ?? '';
  final run = Platform.environment['DU263_RUN'] == '1' && (phase == 'baseline' || phase == 'after');
  final after = phase == 'after';
  final nl = String.fromCharCode(10);
  const base = 'dev.flutter.pigeon.cloud_firestore_platform_interface.FirebaseFirestoreHostApi';
  const fnChannel = 'dev.flutter.pigeon.cloud_functions_platform_interface.CloudFunctionsHostApi.call';
  final blocked = <String>[];

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    PackageInfo.setMockInitialValues(
        appName: 'ALfit', packageName: 'com.alfit.app', version: '1.0.0', buildNumber: '1', buildSignature: '');
  });
  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
  });

  void stubChannels() {
    final m = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    m.setMockMethodCallHandler(const MethodChannel('flutter.baseflow.com/permissions/methods'), (call) async => 0);
    const codec = FirebaseFirestoreHostApi.codec;
    for (final op in const ['queryGet', 'documentReferenceGet', 'documentReferenceSet', 'documentReferenceUpdate',
      'documentReferenceDelete', 'writeBatchCommit', 'transactionCreate', 'transactionStoreResult', 'transactionGet',
      'querySnapshot', 'documentReferenceSnapshot', 'aggregateQuery']) {
      m.setMockMessageHandler('$base.$op', (msg) async {
        blocked.add('firestore $op');
        return codec.encodeMessage(<Object?>['du263-blocked', '$op 차단', null]);
      });
    }
    m.setMockMessageHandler(fnChannel, (msg) async {
      blocked.add('fn');
      return const StandardMessageCodec().encodeMessage(<Object?>['not-found', 'du263-blocked', null]);
    });
  }

  testWidgets('D263 $phase', (t) async {
    await t.runAsync(vqLoadFonts);
    t.platformDispatcher.localesTestValue = const [Locale('ko', 'KR')];
    t.platformDispatcher.localeTestValue = const Locale('ko', 'KR');
    final prevOnError = FlutterError.onError;
    final errors = <String>[];
    FlutterError.onError = (d) => errors.add(d.exceptionAsString().split(nl).first);
    var cur = '(시작)';
    var nPump = 0;
    Never stop(String why) {
      _out('D263-STOP ${jsonEncode({'at': cur, 'why': why, 'errors': errors})}');
      fail('$cur: $why');
    }

    void need(bool ok, String why) {
      if (!ok) stop(why);
    }

    Future<void> frames(int n) async {
      for (var i = 0; i < n; i++) {
        nPump++;
        need(nPump <= 600, '사용량 한도');
        await t.pump(const Duration(milliseconds: 50));
      }
    }

    final overflow = <String>[];
    void safe(String at) {
      final ex = t.takeException();
      need(ex == null, '$at 예외: $ex');
      for (final e in errors) {
        if (!after && e.startsWith('A RenderFlex overflowed by')) {
          overflow.add('$at $e');
        } else {
          stop('$at 예외/overflow: $e');
        }
      }
      errors.clear();
    }

    Finder rich(bool Function(String p) f) =>
        find.byWidgetPredicate((w) => w is RichText && f(TextLayout.plain(w.text.toPlainText())), skipOffstage: false);

    Color bgOf(Element e) {
      final layers = <Color>[];
      e.visitAncestorElements((a) {
        final w = a.widget;
        Color? c;
        if (w is ColoredBox) {
          c = w.color;
        } else if (w is DecoratedBox && w.decoration is BoxDecoration) {
          c = (w.decoration as BoxDecoration).color;
        } else if (w is Material && w.type != MaterialType.transparency) {
          c = w.color ?? Theme.of(a).canvasColor;
        } else if (w is Scaffold) {
          c = w.backgroundColor ?? Theme.of(a).scaffoldBackgroundColor;
        }
        if (c == null || c.a == 0) return true;
        layers.add(c);
        return c.a < 1.0;
      });
      var out = layers.isEmpty ? Colors.white : layers.last;
      for (final c in layers.reversed.skip(1)) {
        out = Color.alphaBlend(c, out);
      }
      return out;
    }

    Map<String, Object?> info(String nm, Finder f) {
      if (f.evaluate().isEmpty) return {'name': nm, 'present': false};
      final rp = t.renderObject<RenderParagraph>(f.first);
      final fg = rp.text.style?.color;
      final bg = bgOf(f.evaluate().first);
      return {
        'name': nm, 'present': true, 'fg': fg == null ? null : _hex(fg), 'bg': _hex(bg),
        'contrast': fg == null ? null : double.parse(_contrast(fg, bg).toStringAsFixed(2)),
        'fontSize': rp.text.style?.fontSize, 'didExceedMaxLines': rp.didExceedMaxLines,
      };
    }

    final key = GlobalKey();
    try {
      for (final c in const [
        (id: 'W360', w: 360.0, h: 780.0, s: 1.0),
        (id: 'B320', w: 320.0, h: 640.0, s: 2.0),
      ]) {
        cur = c.id;
        await t.pumpWidget(const SizedBox.shrink());
        await frames(1);
        safe('장면 종료');
        overflow.clear();
        blocked.clear();
        stubChannels();
        t.view.physicalSize = Size(c.w, c.h);
        t.view.devicePixelRatio = 1.0;
        t.platformDispatcher.textScaleFactorTestValue = c.s;
        await t.pumpWidget(MultiProvider(
          providers: [ChangeNotifierProvider<UserProvider>(create: (_) => _Worker())],
          child: RepaintBoundary(
            key: key,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              navigatorKey: navigatorKey,
              theme: RoleTheme.workerTheme,
              localizationsDelegates: const [
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              supportedLocales: const [Locale('ko', 'KR'), Locale('en', 'US')],
              home: const UserSettingsScreen(),
            ),
          ),
        ));
        await frames(20);
        safe('설정 첫 화면');
        final row = rich((p) => p == '서비스 이용약관');
        need(row.evaluate().isNotEmpty, "'서비스 이용약관' 줄이 없다");
        await t.ensureVisible(row.first);
        await frames(4);
        await t.tap(row.first, warnIfMissed: false);
        // 조회 실패 응답은 실제 시간이 필요할 수 있다 — 약관 화면 제목이 보일 때까지 최대 20회.
        for (var w = 0; w < 20 && find.byIcon(Icons.close).evaluate().isEmpty; w++) {
          await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
          await frames(2);
        }
        await frames(10);
        safe('약관 화면 열림');
        need(find.byIcon(Icons.close).evaluate().isNotEmpty, '약관 화면이 열리지 않았다');

        final sel = find.byWidgetPredicate((w) => w is SelectableText, skipOffstage: false);
        final selText = sel.evaluate().isEmpty ? null : (t.widget<SelectableText>(sel.first).data ?? '');
        final selColor = sel.evaluate().isEmpty ? null : t.widget<SelectableText>(sel.first).style?.color;
        final xs = [
          info('앱바 제목', rich((p) => p == '서비스 이용약관')),
          info('실패 제목', rich((p) => p == '약관을 불러오지 못했습니다')),
          info('실패 부제', rich((p) => p == '잠시 후 다시 시도해주세요.')),
        ];
        final r = {
          'phase': phase, 'cond': c.id, 'overflow': overflow, 'blocked': blocked.toSet().toList()..sort(),
          'selectable': selText == null ? null : {'text': selText, 'fg': selColor == null ? null : _hex(selColor)},
          'texts': xs,
        };
        if (after) {
          need(selText == null, '실패 문장이 본문(SelectableText)으로 그려졌다 $r');
          for (final x in xs.skip(1)) {
            need(x['present'] == true, '실패 상태 문구가 없다 $x');
            final cst = x['contrast'];
            need(cst is double && cst >= 4.5 && x['didExceedMaxLines'] != true, '실패 상태 문구 대비 $x');
          }
        }
        await vqCapture(t, key, 'D263-$phase-${c.id}_failed', conditions: {
          'phase': phase, 'scene': 'failed', 'viewport': '${c.w.toInt()}x${c.h.toInt()}', 'textScaleFactor(기기)': c.s,
        });
        _out('D263 ${jsonEncode(r)}');
      }
      await t.pumpWidget(const SizedBox.shrink());
      await frames(1);
      safe('END 전');
      _out('D263-END');
    } finally {
      FlutterError.onError = prevOnError;
      t.platformDispatcher.clearLocalesTestValue();
      t.platformDispatcher.clearLocaleTestValue();
      t.platformDispatcher.clearTextScaleFactorTestValue();
      t.view.reset();
    }
  }, skip: !run, timeout: const Timeout(Duration(minutes: 4)));
}
