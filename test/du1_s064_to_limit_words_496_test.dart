// ignore_for_file: depend_on_referenced_packages
// [DU496 · 자체 판정 셀 · 표시만] DU-S064 공고 등록 개수 제한 — B 낱말 조판(안내 띠 둘 · 실패 문구 셋) · 안내 띠 글자 · 개별 한도 칩.
//   before = 현재 A(to_limit_settings_screen 5746f9a4 · DU495 후보) / strict = 후보(keepWords · infoDeep).
//   harness 는 DU495 시험(4dc5972e)과 같고, 낱말 경계 판정은 DU436 _lines 를 옮겼다. 정상 · 읽기 실패 두 대역을 차례로 그린다.
//   값은 닿은 즉시 지역 값으로 남긴다(preflight v6). 기본 skip — TB before/du496-tb/DU_BEFORE_OBSERVE=496 · TA after/du496-ta/없음.
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

/// 정상 — 전역 7 · 관리자 둘(개별 3 · 전역). TOL 대역과 같다.
final _ok = ToLimitReads(
  globalConfigRaw: () async => {'maxActiveTOPerBusiness': 7},
  businessAdminsRaw: () async => [
    {'uid': 'a1', 'name': '박사장', 'businessName': '강남 물류센터', 'managedBizCount': 2, 'maxActiveTOs': 3},
    {'uid': 'a2', 'name': '최사장', 'businessName': '성수 창고', 'managedBizCount': 1},
  ],
);

/// 읽기 실패 — 전역값 · 관리자 목록 둘 다(TOL-3 · TOL-4).
final _fail = ToLimitReads(
  globalConfigRaw: () async => throw Exception('unavailable'),
  businessAdminsRaw: () async => throw Exception('unavailable'),
);

void _out(String s) {
  // ignore: avoid_print
  print(s);
}

String _f(double v) => v.toStringAsFixed(2);
String _hex(Color? c) => c == null ? 'none' : c.toARGB32().toRadixString(16).padLeft(8, '0');
String _plainOf(Widget w) => w is RichText ? TextLayout.plain(w.text.toPlainText(includeSemanticsLabels: false)) : '';

final String _zwsp = String.fromCharCode(0x200B);
final String _wj = String.fromCharCode(0x2060);
final String _nbsp = String.fromCharCode(0x00A0);
bool _visible(String ch) => ch.trim().isNotEmpty && ch != _zwsp && ch != _wj && ch != _nbsp;

double _cr(Color? a, Color? b) {
  if (a == null || b == null) return 0;
  final la = a.computeLuminance(), lb = b.computeLuminance();
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

({List<String> lines, bool ok}) _lines(RenderParagraph rp) {
  final s = rp.text.toPlainText(includeSemanticsLabels: false);
  final tops = <double>[];
  final lineOf = List<int>.filled(s.length, -1);
  var missing = 0;
  for (var i = 0; i < s.length; i++) {
    final boxes = rp.getBoxesForSelection(TextSelection(baseOffset: i, extentOffset: i + 1));
    if (boxes.isEmpty) {
      if (_visible(s[i])) missing++;
      continue;
    }
    var k = tops.indexWhere((x) => (x - boxes.first.top).abs() < 0.5);
    if (k < 0) {
      tops.add(boxes.first.top);
      k = tops.length - 1;
    }
    lineOf[i] = k;
  }
  if (tops.isEmpty) return (lines: const <String>[], ok: false);
  final order = List<int>.generate(tops.length, (i) => i)..sort((a, b) => tops[a].compareTo(tops[b]));
  final rank = List<int>.filled(tops.length, 0);
  for (var r = 0; r < order.length; r++) {
    rank[order[r]] = r;
  }
  final buf = List<StringBuffer>.generate(tops.length, (_) => StringBuffer());
  var ok = true;
  var prev = -1;
  var cur = 0;
  for (var i = 0; i < s.length; i++) {
    if (lineOf[i] >= 0) {
      final ln = rank[lineOf[i]];
      if (prev >= 0 && ln != prev) {
        final b = i > 0 ? s[i - 1] : '';
        if (!(b == ' ' || b == _zwsp || b == '\n' || s[i] == ' ' || s[i] == '\n')) ok = false;
      }
      prev = ln;
      cur = ln;
    }
    buf[cur].write(s[i]);
  }
  return (lines: [for (final b in buf) TextLayout.plain(b.toString()).trim()], ok: ok && missing == 0);
}

const _tokens = <String, Color>{
  'white': Color(0xFFFFFFFF), 'background': AppColors.background, 'infoBg': AppColors.infoBg,
  'info': AppColors.info, 'infoDark': AppColors.infoDark, 'infoDeep': AppColors.infoDeep, 'errorDark': AppColors.errorDark,
  'textSecondary': AppColors.textSecondary,
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

final bool _before = Platform.environment['DU_BEFORE_OBSERVE'] == '496';
final Map<String, String> _env = Platform.environment;
final bool _optIn =
    (_env['DU1_VQ_PHASE'] == 'before' && _env['DU1_VQ_RUN'] == 'du496-tb' && _env['DU_BEFORE_OBSERVE'] == '496') ||
        (_env['DU1_VQ_PHASE'] == 'after' && _env['DU1_VQ_RUN'] == 'du496-ta' && _env['DU_BEFORE_OBSERVE'] == null);
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
    testWidgets('S064TW-${v.id}-LIMIT 공고 등록 개수 제한 — 낱말 조판 · 안내 띠 · 칩', (t) async {
      if (_anyFail) fail('앞 사례 실패 — 이 사례 본문 실행 0 · 캡처 0');
      try {
        final tok = 'S064TW-${v.id}-LIMIT';
        final mode = _before ? 'before' : 'strict';
        _out('D496 $tok begin mode=$mode phase=${Platform.environment['DU1_VQ_PHASE'] ?? '(unset)'} env=$_envLine manifest=$_manifest');
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
        Future<void> pumpWith(ToLimitReads reads) async {
          await t.pumpWidget(const SizedBox.shrink());
          await t.pumpWidget(RepaintBoundary(
            key: key,
            child: ChangeNotifierProvider<UserProvider>(
              create: (_) => _Super(),
              child: MaterialApp(
                debugShowCheckedModeBanner: false,
                theme: RoleTheme.superAdminTheme,
                builder: (ctx, child) => MediaQuery(data: MediaQuery.of(ctx).copyWith(textScaler: TextScaler.linear(v.s)), child: child!),
                home: TOLimitSettingsScreen(reads: reads),
              ),
            ),
          ));
          for (var i = 0; i < 4; i++) {
            await t.pump(const Duration(milliseconds: 100));
          }
        }

        Finder rt(bool Function(String p) p) => find.byWidgetPredicate((w) => w is RichText && p(_plainOf(w)), skipOffstage: false);
        Future<void> toAdmins() async {
          await t.tap(rt((p) => p == '관리자별 한도'));
          for (var i = 0; i < 6; i++) {
            await t.pump(const Duration(milliseconds: 100));
          }
        }

        // 글자 하나 — 정확히 1개 · 닿게 내린 뒤 · 색 · 면 · 대비 · 낱말 경계 · 줄 수.
        Future<(Color?, Color?, double, bool, int)> txt(String what, bool Function(String p) p) async {
          final f = rt(p);
          must('$what 1', f.evaluate().length == 1, '개수 ${f.evaluate().length}');
          final sc = find.ancestor(of: f, matching: find.byType(Scrollable, skipOffstage: false));
          if (sc.evaluate().isNotEmpty) {
            await t.scrollUntilVisible(f, 120, scrollable: sc.first, maxScrolls: 40);
            await t.pump(const Duration(milliseconds: 50));
          }
          final c = (t.widget(f) as RichText).text.style?.color;
          final bg = _bgOf(f.evaluate().first);
          final j = _lines(t.renderObject(f) as RenderParagraph);
          return (c, bg, _cr(c, bg), j.ok, j.lines.length);
        }

        var shots = 0;
        // ── 정상 대역 ──
        await pumpWith(_ok);
        final gb = await txt('전역 안내 띠', (p) => p.startsWith('한도는 한 관리자 계정이'));
        _out('D496 $tok att gban text=${_tok(gb.$1)} bg=${_tok(gb.$2)} cr=${_f(gb.$3)} ok=${gb.$4} n=${gb.$5}');
        _out('D496 $tok shot 1global ovf=${overflows.length}');
        await vqCapture(t, key, '${tok}_1global', conditions: {
          'viewport': '${v.w.toInt()}x${v.h.toInt()}', 'textScaler': v.s, 'run': vqRun, 'manifest': _manifest, 'mode': mode, 'fixture': 'LIMIT',
          'state': 'to-limit-global-banner',
        });
        shots++;
        await toAdmins();
        final ab = await txt('관리자 안내 띠', (p) => p.startsWith('한도는 동시에 진행 중인'));
        _out('D496 $tok att aban text=${_tok(ab.$1)} bg=${_tok(ab.$2)} cr=${_f(ab.$3)} ok=${ab.$4} n=${ab.$5}');
        final ch = await txt('개별 한도 칩', (p) => p == '개별 3개');
        _out('D496 $tok att chip text=${_tok(ch.$1)} bg=${_tok(ch.$2)} cr=${_f(ch.$3)}');
        _out('D496 $tok shot 2admins ovf=${overflows.length}');
        await vqCapture(t, key, '${tok}_2admins', conditions: {
          'viewport': '${v.w.toInt()}x${v.h.toInt()}', 'textScaler': v.s, 'run': vqRun, 'manifest': _manifest, 'mode': mode, 'fixture': 'LIMIT',
          'state': 'to-limit-admins',
        });
        shots++;
        // ── 읽기 실패 대역 ──
        await pumpWith(_fail);
        final gf = await txt('전역값 실패 문구', (p) => p.startsWith('현재 기본 한도를 불러오지'));
        _out('D496 $tok att gfail text=${_tok(gf.$1)} ok=${gf.$4} n=${gf.$5}');
        _out('D496 $tok shot 3gfail ovf=${overflows.length}');
        await vqCapture(t, key, '${tok}_3gfail', conditions: {
          'viewport': '${v.w.toInt()}x${v.h.toInt()}', 'textScaler': v.s, 'run': vqRun, 'manifest': _manifest, 'mode': mode, 'fixture': 'LIMIT',
          'state': 'to-limit-global-failed',
        });
        shots++;
        await toAdmins();
        final at = await txt('관리자 실패 제목', (p) => p == '관리자 목록을 불러오지 못했습니다');
        final asub = await txt('관리자 실패 부제', (p) => p == '등록된 관리자가 없다는 뜻이 아닙니다.');
        _out('D496 $tok att afail tok=${at.$4} sok=${asub.$4} tn=${at.$5} sn=${asub.$5}');
        _out('D496 $tok shot 4afail ovf=${overflows.length}');
        await vqCapture(t, key, '${tok}_4afail', conditions: {
          'viewport': '${v.w.toInt()}x${v.h.toInt()}', 'textScaler': v.s, 'run': vqRun, 'manifest': _manifest, 'mode': mode, 'fixture': 'LIMIT',
          'state': 'to-limit-admins-failed',
        });
        shots++;
        // 배치는 끝났다 — 넘침 수집기를 먼저 되돌린다(바꾼 채 expect 가 실패하면 tearDownAll 이 멈춘다 · DU475 진단).
        FlutterError.onError = prev;
        if (_before) {
          // 음성 기대(코드 확정 · DU495 B 합성) — 안내 띠 infoDark 4.03 · 칩 info 2.80 · B 에서 전역 안내 띠 · 실패 부제가 음절에서 끊긴다.
          must('before 안내 띠 infoDark 미달', gb.$1 == AppColors.infoDark && ab.$1 == AppColors.infoDark && gb.$3 < 4.5 && ab.$3 < 4.5, '${_f(gb.$3)} ${_f(ab.$3)}');
          must('before 칩 info 미달', ch.$1 == AppColors.info && ch.$3 < 4.5, _f(ch.$3));
          if (v.id == 'B') {
            must('before B 음절 끊김 검출(전역 안내 띠 · 실패 부제)', !gb.$4 && !asub.$4, 'gb=${gb.$4} asub=${asub.$4}');
          }
        } else {
          must('strict 안내 띠 infoDeep ≥ 4.5', gb.$1 == AppColors.infoDeep && ab.$1 == AppColors.infoDeep && gb.$3 >= 4.5 && ab.$3 >= 4.5, '${_f(gb.$3)} ${_f(ab.$3)}');
          must('strict 칩 infoDeep ≥ 4.5', ch.$1 == AppColors.infoDeep && ch.$3 >= 4.5, _f(ch.$3));
          must('strict 낱말 경계(안내 띠 둘 · 실패 문구 셋)', gb.$4 && ab.$4 && gf.$4 && at.$4 && asub.$4, '${gb.$4} ${ab.$4} ${gf.$4} ${at.$4} ${asub.$4}');
          must('strict 넘침 0', overflows.isEmpty, overflows.join(' | '));
        }
        must('미처리 framework 예외 0', fwErrors.isEmpty, '오류 $fwErrors');
        final exc = t.takeException();
        _out('D496 $tok done state=LIMIT mode=$mode captures=$shots overflows=${overflows.length} exc=${exc != null} ovfRaw=${overflows.isEmpty ? '-' : base64Url.encode(utf8.encode(overflows.join('\n'))).replaceAll('=', '')}');
        must('끝 예외 0', exc == null, '예외 $exc');
        await t.pumpWidget(const SizedBox.shrink());
      } catch (e) {
        _anyFail = true;
        rethrow;
      }
    }, skip: !_optIn);
  }
}
