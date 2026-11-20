// ignore_for_file: depend_on_referenced_packages
// [DU495 · 자체 판정 셀 · 표시만] DU-S064 공고 등록 개수 제한(슈퍼관리자) — 헤더 두 탭(이름 잘림 · 미선택 글자)과 관리자 목록 읽기 실패 안내 글자.
//   before = 현재 A(to_limit_settings_screen 6efadd61) / strict = 후보(안 들어가면 가로 스크롤 · 미선택 보조색 · 안내 보조색).
//   harness 는 DU494 시험(28ff5969)과 같다. 앱 테마(RoleTheme.superAdminTheme) · 화면은 ToLimitReads 주입(TOL-4 와 같다).
//   값은 닿은 즉시 지역 값으로 남긴다(preflight v6). 기본 skip — TB before/du495-tb/DU_BEFORE_OBSERVE=495 · TA after/du495-ta/없음.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';

import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/screens/super_admin/to_limit_reads.dart';
import 'package:ALfit/screens/super_admin/to_limit_settings_screen.dart';
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

/// 전역 기본값 7 · 관리자 목록 읽기 실패(TOL-4 와 같다).
final _reads = ToLimitReads(
  globalConfigRaw: () async => {'maxActiveTOPerBusiness': 7},
  businessAdminsRaw: () async => throw Exception('unavailable'),
);

/// 탭 이름이 잘렸는가 — 그려진 폭이 한 줄 고유 폭보다 좁다(Tab 글자는 softWrap 없음 · fade).
bool _clipped(RenderParagraph rp) => rp.size.width + 0.5 < rp.getMaxIntrinsicWidth(double.infinity);

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
  'white': Color(0xFFFFFFFF), 'background': AppColors.background, 'textSecondary': AppColors.textSecondary,
  'grey500': AppColors.grey500, 'grey600': AppColors.grey600,
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

final bool _before = Platform.environment['DU_BEFORE_OBSERVE'] == '495';
final Map<String, String> _env = Platform.environment;
final bool _optIn =
    (_env['DU1_VQ_PHASE'] == 'before' && _env['DU1_VQ_RUN'] == 'du495-tb' && _env['DU_BEFORE_OBSERVE'] == '495') ||
        (_env['DU1_VQ_PHASE'] == 'after' && _env['DU1_VQ_RUN'] == 'du495-ta' && _env['DU_BEFORE_OBSERVE'] == null);
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
    testWidgets('S064TL-${v.id}-LIMIT 공고 등록 개수 제한 — 탭 · 실패 안내 글자', (t) async {
      if (_anyFail) fail('앞 사례 실패 — 이 사례 본문 실행 0 · 캡처 0');
      try {
        final tok = 'S064TL-${v.id}-LIMIT';
        final mode = _before ? 'before' : 'strict';
        _out('D495 $tok begin mode=$mode phase=${Platform.environment['DU1_VQ_PHASE'] ?? '(unset)'} env=$_envLine manifest=$_manifest');
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
              home: TOLimitSettingsScreen(reads: _reads),
            ),
          ),
        ));
        for (var i = 0; i < 4; i++) {
          await t.pump(const Duration(milliseconds: 100));
        }
        Finder rt(bool Function(String p) p) => find.byWidgetPredicate((w) => w is RichText && p(_plainOf(w)), skipOffstage: false);
        var shots = 0;
        _out('D495 $tok shot 1tabs ovf=${overflows.length}');
        await vqCapture(t, key, '${tok}_1tabs', conditions: {
          'viewport': '${v.w.toInt()}x${v.h.toInt()}', 'textScaler': v.s, 'run': vqRun, 'manifest': _manifest, 'mode': mode, 'fixture': 'LIMIT',
          'state': 'to-limit-global',
        });
        shots++;
        // 탭 글자 — 정확히 1개 · 색 · 놓인 면 · 대비 · 잘림.
        (Color?, Color?, double, bool) tab(String what, String label) {
          final f = rt((p) => p == label);
          must('$what 1', f.evaluate().length == 1, '개수 ${f.evaluate().length}');
          final c = (t.widget(f) as RichText).text.style?.color;
          final bg = _bgOf(f.evaluate().first);
          return (c, bg, _cr(c, bg), _clipped(t.renderObject(f) as RenderParagraph));
        }

        final g0 = tab('전역 탭', '전역 기본값');
        final a0 = tab('관리자 탭(미선택)', '관리자별 한도');
        _out('D495 $tok att tabs gclip=${g0.$4} aclip=${a0.$4} un=${_tok(a0.$1)} bg=${_tok(a0.$2)} cr=${_f(a0.$3)}');
        await t.tap(rt((p) => p == '관리자별 한도'));
        for (var i = 0; i < 6; i++) {
          await t.pump(const Duration(milliseconds: 100));
        }
        final g1 = tab('전역 탭(미선택)', '전역 기본값');
        final e1F = rt((p) => p == '관리자 목록을 불러오지 못했습니다');
        final e2F = rt((p) => p == '등록된 관리자가 없다는 뜻이 아닙니다.');
        must('실패 안내 1/1', e1F.evaluate().length == 1 && e2F.evaluate().length == 1, '${e1F.evaluate().length}/${e2F.evaluate().length}');
        final e1c = (t.widget(e1F) as RichText).text.style?.color;
        final e1b = _bgOf(e1F.evaluate().first);
        final e1r = _cr(e1c, e1b);
        final e2c = (t.widget(e2F) as RichText).text.style?.color;
        final e2r = _cr(e2c, _bgOf(e2F.evaluate().first));
        _out('D495 $tok att err title=${_tok(e1c)} bg=${_tok(e1b)} tcr=${_f(e1r)} sub=${_tok(e2c)} scr=${_f(e2r)} un=${_tok(g1.$1)} ucr=${_f(g1.$3)}');
        _out('D495 $tok shot 2err ovf=${overflows.length}');
        await vqCapture(t, key, '${tok}_2err', conditions: {
          'viewport': '${v.w.toInt()}x${v.h.toInt()}', 'textScaler': v.s, 'run': vqRun, 'manifest': _manifest, 'mode': mode, 'fixture': 'LIMIT',
          'state': 'to-limit-admins-failed',
        });
        shots++;
        // 배치는 끝났다 — 넘침 수집기를 먼저 되돌린다(바꾼 채 expect 가 실패하면 tearDownAll 이 멈춘다 · DU475 진단).
        FlutterError.onError = prev;
        if (_before) {
          // 음성 기대(코드 확정) — 미선택 grey500 · 안내 grey600/grey500. 탭 잘림은 B 에서만(W 는 잘리지 않는다).
          must('before 미선택 탭 grey500 미달', a0.$1 == AppColors.grey500 && g1.$1 == AppColors.grey500 && a0.$3 < 4.5 && g1.$3 < 4.5, '${_f(a0.$3)} ${_f(g1.$3)}');
          must('before 안내 grey600 · grey500 미달', e1c == AppColors.grey600 && e2c == AppColors.grey500 && e1r < 4.5 && e2r < 4.5, '${_f(e1r)} ${_f(e2r)}');
          final clip = g0.$4 || a0.$4;
          must('before 탭 잘림 = B 에서만', v.id == 'B' ? clip : !clip, 'g=${g0.$4} a=${a0.$4}');
        } else {
          must('strict 미선택 탭 textSecondary ≥ 4.5', a0.$1 == AppColors.textSecondary && g1.$1 == AppColors.textSecondary && a0.$3 >= 4.5 && g1.$3 >= 4.5,
              '${_f(a0.$3)} ${_f(g1.$3)}');
          must('strict 안내 textSecondary ≥ 4.5', e1c == AppColors.textSecondary && e2c == AppColors.textSecondary && e1r >= 4.5 && e2r >= 4.5, '${_f(e1r)} ${_f(e2r)}');
          must('strict 탭 이름 잘림 0', !g0.$4 && !a0.$4 && !g1.$4, 'g=${g0.$4} a=${a0.$4} g1=${g1.$4}');
          must('strict 넘침 0', overflows.isEmpty, overflows.join(' | '));
        }
        must('미처리 framework 예외 0', fwErrors.isEmpty, '오류 $fwErrors');
        final exc = t.takeException();
        _out('D495 $tok done state=LIMIT mode=$mode captures=$shots overflows=${overflows.length} exc=${exc != null} ovfRaw=${overflows.isEmpty ? '-' : base64Url.encode(utf8.encode(overflows.join('\n'))).replaceAll('=', '')}');
        must('끝 예외 0', exc == null, '예외 $exc');
        await t.pumpWidget(const SizedBox.shrink());
      } catch (e) {
        _anyFail = true;
        rethrow;
      }
    }, skip: !_optIn);
  }
}
