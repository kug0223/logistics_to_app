// ignore_for_file: depend_on_referenced_packages
// [DU502 · 자체 판정 셀 · 표시만] DU-S063 시스템 설정(슈퍼관리자) — 메뉴 행 부제 · '준비 중' 비활성 제목 글자 대비.
//   before = 현재 A(system_settings_screen 097be3d5) / strict = 후보(부제 textSecondary · 비활성 제목 textTertiary).
//   harness 는 DU495 시험(4dc5972e)과 같다(앱 테마 RoleTheme · 슈퍼관리자 대역). 화면은 정적 메뉴라 데이터 주입이 없다.
//   값은 닿은 즉시 지역 값으로 남긴다(preflight v6). 기본 skip — TB before/du502-tb/DU_BEFORE_OBSERVE=502 · TA after/du502-ta/없음.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';

import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/screens/super_admin/system_settings_screen.dart';
import 'package:ALfit/theme/app_colors.dart';
import 'package:ALfit/theme/role_theme.dart';
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

/// RR57 과 같은 슈퍼관리자 대역.
class _Super extends UserProvider {
  @override
  UserModel? get currentUser => UserModel(
        uid: 'sa1', username: 'sa1', name: '운영자', email: 'sa@alfit.local',
        role: UserRole.SUPER_ADMIN, createdAt: DateTime(2026, 1, 1));
  @override
  bool get isSuperAdmin => true;
  @override
  bool get isBusinessAdmin => false;
  @override
  bool get isSubAdmin => false;
  @override
  bool get isAdminMode => true;
  @override
  bool get permissionsLoaded => true;
}

void _out(String s) {
  // ignore: avoid_print
  print(s);
}

String _f(double v) => v.toStringAsFixed(2);
String _hex(Color? c) => c == null ? 'none' : c.toARGB32().toRadixString(16).padLeft(8, '0');
String _plainOf(Widget w) => w is RichText ? TextLayout.plain(w.text.toPlainText(includeSemanticsLabels: false)) : '';

double _cr(Color? a, Color? b) {
  if (a == null || b == null) return 0;
  final la = a.computeLuminance(), lb = b.computeLuminance();
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

const _tokens = <String, Color>{
  'white': Color(0xFFFFFFFF), 'textSecondary': AppColors.textSecondary, 'textTertiary': AppColors.textTertiary,
  'grey400': AppColors.grey400, 'grey500': AppColors.grey500,
};
String _tok(Color? c) {
  if (c == null) return 'none';
  for (final e in _tokens.entries) {
    if (e.value.toARGB32() == c.toARGB32()) return e.key;
  }
  return 'x${_hex(c)}';
}

/// 놓인 면 — 조상의 칠한 색을 불투명 층까지 모아 합성한다(DU476 과 같다). 면이 없으면 흰 바탕(MaterialApp 기본 Scaffold)으로 본다.
Color? _bgOf(Element e) {
  final layers = <Color>[];
  e.visitAncestorElements((x) {
    final w = x.widget;
    Color? c;
    if (w is Container) {
      c = w.color ?? (w.decoration is BoxDecoration ? (w.decoration! as BoxDecoration).color : null);
    } else if (w is ColoredBox) {
      c = w.color;
    } else if (w is Material && w.type != MaterialType.transparency) {
      c = w.color;
    }
    // preflight v16 — 투명(알파 0) Material 은 칠한 면이 아니다.
    if (c != null && c.a > 0) {
      layers.add(c);
      if (c.a >= 1) return false;
    }
    return true;
  });
  if (layers.isEmpty) return null;
  var out = layers.last;
  for (final c in layers.reversed.skip(1)) {
    out = Color.alphaBlend(c, out);
  }
  return out;
}

final bool _before = Platform.environment['DU_BEFORE_OBSERVE'] == '502';
final Map<String, String> _env = Platform.environment;
final bool _optIn =
    (_env['DU1_VQ_PHASE'] == 'before' && _env['DU1_VQ_RUN'] == 'du502-tb' && _env['DU_BEFORE_OBSERVE'] == '502') ||
        (_env['DU1_VQ_PHASE'] == 'after' && _env['DU1_VQ_RUN'] == 'du502-ta' && _env['DU_BEFORE_OBSERVE'] == null);
var _anyFail = false;
final String _manifest = Platform.environment['DUL_MANIFEST'] ?? '(unset)';
const _envKeys = ['DU_BEFORE_OBSERVE', 'DU1_VQ_PHASE', 'DU1_VQ_OUT', 'DU1_VQ_RUN', 'DU1_VQ_DATE', 'DU397_DIAG', 'DU397_MANIFEST', 'DU400_MANIFEST',
  'DU401_MANIFEST', 'DU398_MANIFEST', 'DU406_MANIFEST', 'DU407_MANIFEST', 'DU296_PHASE', 'DUL_MANIFEST'];
final String _envLine = [for (final k in _envKeys) '$k:${Platform.environment[k] ?? '(unset)'}'].join(',');

void main() {
  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
  });

  const views = [(id: 'W', w: 390.0, h: 844.0, s: 1.0), (id: 'B', w: 320.0, h: 640.0, s: 2.0)];
  for (final v in views) {
    testWidgets('S063SM-${v.id}-MENU 시스템 설정 — 메뉴 행 글자 대비', (t) async {
      if (_anyFail) fail('앞 사례 실패 — 이 사례 본문 실행 0 · 캡처 0');
      try {
        final tok = 'S063SM-${v.id}-MENU';
        final mode = _before ? 'before' : 'strict';
        _out('D502 $tok begin mode=$mode phase=${Platform.environment['DU1_VQ_PHASE'] ?? '(unset)'} env=$_envLine manifest=$_manifest');
        await t.runAsync(vqLoadFonts);
        final overflows = <String>[];
        final fwErrors = <String>[];
        final prev = FlutterError.onError;
        FlutterError.onError = (d) {
          final m = d.exceptionAsString();
          if (m.contains('overflowed')) {
            final full = d.toString();
            final k = full.indexOf('The relevant error-causing widget was');
            final loc = k < 0 ? '' : full.substring(k).split('\n').skip(1).where((l) => l.trim().isNotEmpty).take(2).map((l) => l.trim()).join(' ');
            overflows.add('${m.split('\n').first} @ $loc');
          } else {
            fwErrors.add(m.split('\n').first);
            prev?.call(d);
          }
        };
        addTearDown(() => FlutterError.onError = prev);
        t.view.physicalSize = Size(v.w, v.h);
        t.view.devicePixelRatio = 1.0;
        addTearDown(t.view.reset);
        void must(String k, bool ok, [String why = '']) => expect(ok, isTrue, reason: '$tok $k $why');

        final key = GlobalKey();
        await t.pumpWidget(RepaintBoundary(
          key: key,
          child: ChangeNotifierProvider<UserProvider>(
            create: (_) => _Super(),
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: RoleTheme.superAdminTheme,
              builder: (ctx, child) => MediaQuery(data: MediaQuery.of(ctx).copyWith(textScaler: TextScaler.linear(v.s)), child: child!),
              home: const SystemSettingsScreen(),
            ),
          ),
        ));
        for (var i = 0; i < 4; i++) {
          await t.pump(const Duration(milliseconds: 100));
        }
        Finder rt(bool Function(String p) p) => find.byWidgetPredicate((w) => w is RichText && p(_plainOf(w)), skipOffstage: false);
        var shots = 0;
        // 글자 하나 — 정확히 1개 · 닿게 내린 뒤 · 색 · 놓인 면 · 대비.
        Future<(Color?, Color?, double)> txt(String what, String s) async {
          final f = rt((p) => p == s);
          must('$what 1', f.evaluate().length == 1, '개수 ${f.evaluate().length}');
          final sc = find.ancestor(of: f, matching: find.byType(Scrollable, skipOffstage: false));
          if (sc.evaluate().isNotEmpty) {
            await t.scrollUntilVisible(f, 120, scrollable: sc.first, maxScrolls: 40);
            await t.pump(const Duration(milliseconds: 50));
          }
          final c = (t.widget(f) as RichText).text.style?.color;
          final bg = _bgOf(f.evaluate().first);
          return (c, bg, _cr(c, bg));
        }

        final sub = await txt('메뉴 부제(리뷰 태그)', '긍정/개선 태그 관리');
        _out('D502 $tok att sub text=${_tok(sub.$1)} bg=${_tok(sub.$2)} cr=${_f(sub.$3)}');
        _out('D502 $tok shot 1top ovf=${overflows.length}');
        await vqCapture(t, key, '${tok}_1top', conditions: {
          'viewport': '${v.w.toInt()}x${v.h.toInt()}', 'textScaler': v.s, 'run': vqRun, 'manifest': _manifest, 'mode': mode, 'fixture': 'MENU',
          'state': 'system-menu-top',
        });
        shots++;
        final dt = await txt('비활성 제목(알림 설정)', '알림 설정');
        final ds = await txt('비활성 부제(푸시 알림 규칙)', '푸시 알림 규칙');
        _out('D502 $tok att disabled text=${_tok(dt.$1)} bg=${_tok(dt.$2)} cr=${_f(dt.$3)} sub=${_tok(ds.$1)} scr=${_f(ds.$3)}');
        _out('D502 $tok shot 2disabled ovf=${overflows.length}');
        await vqCapture(t, key, '${tok}_2disabled', conditions: {
          'viewport': '${v.w.toInt()}x${v.h.toInt()}', 'textScaler': v.s, 'run': vqRun, 'manifest': _manifest, 'mode': mode, 'fixture': 'MENU',
          'state': 'system-menu-disabled',
        });
        shots++;
        // 배치는 끝났다 — 넘침 수집기를 먼저 되돌린다(바꾼 채 expect 가 실패하면 tearDownAll 이 멈춘다 · DU475 진단).
        FlutterError.onError = prev;
        if (_before) {
          // 음성 기대(코드 확정) — 부제 grey500 · 비활성 제목 grey400(흰 면 1.88 · 2.68).
          must('before 부제 grey500 미달', sub.$1 == AppColors.grey500 && ds.$1 == AppColors.grey500 && sub.$3 < 4.5, _f(sub.$3));
          must('before 비활성 제목 grey400 미달', dt.$1 == AppColors.grey400 && dt.$3 < 4.5, _f(dt.$3));
        } else {
          must('strict 부제 textSecondary ≥ 4.5', sub.$1 == AppColors.textSecondary && ds.$1 == AppColors.textSecondary && sub.$3 >= 4.5 && ds.$3 >= 4.5,
              '${_f(sub.$3)} ${_f(ds.$3)}');
          must('strict 비활성 제목 textTertiary ≥ 4.5', dt.$1 == AppColors.textTertiary && dt.$3 >= 4.5, _f(dt.$3));
          must('strict 넘침 0', overflows.isEmpty, overflows.join(' | '));
        }
        must('미처리 framework 예외 0', fwErrors.isEmpty, '오류 $fwErrors');
        final exc = t.takeException();
        _out('D502 $tok done state=MENU mode=$mode captures=$shots overflows=${overflows.length} exc=${exc != null} ovfRaw=${overflows.isEmpty ? '-' : base64Url.encode(utf8.encode(overflows.join('\n'))).replaceAll('=', '')}');
        must('끝 예외 0', exc == null, '예외 $exc');
        await t.pumpWidget(const SizedBox.shrink());
      } catch (e) {
        _anyFail = true;
        rethrow;
      }
    }, skip: !_optIn);
  }
}
