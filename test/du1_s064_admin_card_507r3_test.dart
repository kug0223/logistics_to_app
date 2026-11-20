// ignore_for_file: depend_on_referenced_packages
// [DU507 r3 · 후속117 N117-1 · 표시만] DU-S064 '관리자별 한도' 카드 — 값 든 입력칸이 숨은 3줄 힌트 높이를 잡던 것(V8 · F117-1) 제거.
//   before = 현재 A(to_limit_settings_screen e5a36ceb · 507 r2 채택) / strict = 후보(maintainHintSize: false 한 줄). harness 는 r2(1e290c06)와 같다.
//   W/B · 값 있음/없음 칸 높이 · 줄 상자 · 여백 · 접미 개 · 빈 칸 힌트 전문 · 마지막 저장 실제 도달/중심 hit(누르지 않음 · writer 0).
//   기본 skip — TB before/du507-tb/DU_BEFORE_OBSERVE=507 · TA after/du507-ta/없음.
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

void _out(String s) {
  // ignore: avoid_print
  print(s);
}

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

final bool _before = Platform.environment['DU_BEFORE_OBSERVE'] == '507';
final Map<String, String> _env = Platform.environment;
final bool _optIn =
    (_env['DU1_VQ_PHASE'] == 'before' && _env['DU1_VQ_RUN'] == 'du507-tb' && _env['DU_BEFORE_OBSERVE'] == '507') ||
        (_env['DU1_VQ_PHASE'] == 'after' && _env['DU1_VQ_RUN'] == 'du507-ta' && _env['DU_BEFORE_OBSERVE'] == null);
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
    testWidgets('S064AC-${v.id}-LIMIT 공고 등록 개수 제한 — 관리자 카드 부제 · 힌트', (t) async {
      if (_anyFail) fail('앞 사례 실패 — 이 사례 본문 실행 0 · 캡처 0');
      try {
        final tok = 'S064AC-${v.id}-LIMIT';
        final mode = _before ? 'before' : 'strict';
        _out('D507 $tok begin mode=$mode phase=${Platform.environment['DU1_VQ_PHASE'] ?? '(unset)'} env=$_envLine manifest=$_manifest');
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
        await pumpWith(_ok);
        await toAdmins();
        // 부제 — 낱말 경계 · 줄 수(r2 그대로).
        final sub = await txt('사업장 수 부제', (p) => p == '2개 사업장 관리 중');
        bool shown(Element e) {
          var vis = true;
          e.visitAncestorElements((a) {
            final w = a.widget;
            if (w is Opacity && w.opacity == 0) vis = false;
            if (w is AnimatedOpacity && w.opacity == 0) vis = false;
            return vis;
          });
          return vis;
        }

        // [r3 · 후속117 N117-1] 두 입력칸 — 값 든 칸(박사장 '3') · 빈 칸(최사장). 높이 = InputDecorator 상자 · 줄 상자 = EditableText ·
        //   여백 = contentPadding.vertical · chrome = 높이 − 여백 − 줄 상자. 숨은 힌트가 크기를 남기면 값 든 칸의 chrome 이 힌트 줄만큼 커진다.
        final fields = find.byType(TextField, skipOffstage: false).evaluate().toList();
        must('입력칸 2', fields.length == 2, '개수 ${fields.length}');
        Element? fieldOf(bool filled) {
          for (final e in fields) {
            final tf = e.widget as TextField;
            if ((tf.controller?.text.isNotEmpty ?? false) == filled) return e;
          }
          return null;
        }

        Future<({double h, double edit, double pad, double chrome, bool suffix})> measure(String what, Element? e) async {
          must('$what 칸 1', e != null, '없음');
          final f = find.byElementPredicate((x) => identical(x, e));
          final sc = find.ancestor(of: f, matching: find.byType(Scrollable, skipOffstage: false));
          if (sc.evaluate().isNotEmpty) {
            await t.scrollUntilVisible(f, 120, scrollable: sc.first, maxScrolls: 40);
            await t.pump(const Duration(milliseconds: 50));
          }
          final dbox = t.renderObject(find.descendant(of: f, matching: find.byType(InputDecorator, skipOffstage: false)).first) as RenderBox;
          final ebox = t.renderObject(find.descendant(of: f, matching: find.byType(EditableText, skipOffstage: false)).first) as RenderBox;
          final tf = e!.widget as TextField;
          final pad = tf.decoration!.contentPadding!.resolve(TextDirection.ltr).vertical;
          final suffix = find.descendant(of: f, matching: rt((p) => p == '개'), skipOffstage: false).evaluate().isNotEmpty;
          return (h: dbox.size.height, edit: ebox.size.height, pad: pad, chrome: dbox.size.height - pad - ebox.size.height, suffix: suffix);
        }

        final fv = await measure('값 든', fieldOf(true));
        final fe0 = await measure('빈', fieldOf(false));
        // 빈 칸 힌트 — 보이는 힌트 1 · 전문(말줄임 0) · 낱말 경계 · 문자열 · 칸 안에 다 들어감.
        final hEls = rt((p) => p.startsWith('비워두면 전역값')).evaluate().where(shown).toList();
        must('보이는 힌트 1', hEls.length == 1, '개수 ${hEls.length}');
        final hrp = hEls.first.renderObject! as RenderParagraph;
        final hEx = hrp.didExceedMaxLines;
        final hj = _lines(hrp);
        final hTxt = TextLayout.plain(hrp.text.toPlainText(includeSemanticsLabels: false));
        final hTxtOk = hTxt == '비워두면 전역값 7개 사용';
        final hFit = hrp.size.height <= fe0.h - fe0.pad + 0.5;
        _out('D507 $tok att sub ok=${sub.$4} n=${sub.$5}');
        _out('D507 $tok att hint ex=$hEx ok=${hj.ok} n=${hj.lines.length} txt=$hTxtOk fit=$hFit');
        _out('D507 $tok att fval h=${fv.h.toStringAsFixed(1)} edit=${fv.edit.toStringAsFixed(1)} pad=${fv.pad.toStringAsFixed(1)} chrome=${fv.chrome.toStringAsFixed(1)} suffix=${fv.suffix}');
        _out('D507 $tok att femp h=${fe0.h.toStringAsFixed(1)} edit=${fe0.edit.toStringAsFixed(1)} pad=${fe0.pad.toStringAsFixed(1)} chrome=${fe0.chrome.toStringAsFixed(1)} suffix=${fe0.suffix}');
        // 마지막 '저장' — 실제로 굴려 보이게 한 뒤 중심 hit(누르지 않는다 · writer 0).
        final saves = find.byWidgetPredicate((w) => w is ElevatedButton, skipOffstage: false).evaluate().where((e) =>
            find.descendant(of: find.byElementPredicate((x) => identical(x, e), skipOffstage: false), matching: rt((p) => p == '저장'), skipOffstage: false)
                    .evaluate()
                    .length ==
                1).toList();
        var saveReach = false;
        var saveH = 0.0;
        if (saves.isNotEmpty) {
          final last = find.byElementPredicate((x) => identical(x, saves.last));
          final sc = find.ancestor(of: last, matching: find.byType(Scrollable, skipOffstage: false));
          if (sc.evaluate().isNotEmpty) {
            await t.scrollUntilVisible(last, 120, scrollable: sc.first, maxScrolls: 40);
            await t.pump(const Duration(milliseconds: 50));
          }
          final sbox = t.renderObject(last) as RenderBox;
          saveH = sbox.size.height;
          final c = sbox.localToGlobal(sbox.size.center(Offset.zero));
          saveReach = (Offset.zero & Size(v.w, v.h)).contains(c) && t.hitTestOnBinding(c).path.any((h) => identical(h.target, sbox));
        }
        _out('D507 $tok att save n=${saves.length} reach=$saveReach h=${saveH.toStringAsFixed(1)}');
        _out('D507 $tok shot 1admins ovf=${overflows.length}');
        await vqCapture(t, key, '${tok}_1admins', conditions: {
          'viewport': '${v.w.toInt()}x${v.h.toInt()}', 'textScaler': v.s, 'run': vqRun, 'manifest': _manifest, 'mode': mode, 'fixture': 'LIMIT',
          'state': 'to-limit-admin-cards',
        });
        shots++;
        // 배치는 끝났다 — 넘침 수집기를 먼저 되돌린다(DU475 진단).
        FlutterError.onError = prev;
        if (_before) {
          // 음성 기대(507 r2 B 합성 · SDK maintainHintSize 기본 true) — B 값 든 칸이 숨은 3줄 힌트 높이를 잡는다.
          if (v.id == 'B') must('before B 값 든 칸 chrome > 20(숨은 힌트 높이)', fv.chrome > 20, 'chrome ${fv.chrome.toStringAsFixed(1)}');
        } else {
          must('strict 값 든 칸 chrome ≤ 2(숨은 힌트 높이 0) · 접미 개', fv.chrome <= 2.0 && fv.suffix, 'chrome ${fv.chrome.toStringAsFixed(1)} suffix ${fv.suffix}');
          must('strict 빈 칸 접미 개 · 힌트 전문(말줄임 0) · 경계 · 문자열 · 칸 안', fe0.suffix && !hEx && hj.ok && hTxtOk && hFit,
              'suffix ${fe0.suffix} ex $hEx ok ${hj.ok} txt "$hTxt" fit $hFit');
          must('strict 부제 낱말 경계', sub.$4, 'sub ${sub.$4}');
          must('strict 저장 2 · 마지막 저장 도달 · 중심 hit', saves.length == 2 && saveReach, 'n ${saves.length} reach $saveReach');
          must('strict 넘침 0', overflows.isEmpty, overflows.join(' | '));
        }
        must('미처리 framework 예외 0', fwErrors.isEmpty, '오류 $fwErrors');
        final exc = t.takeException();
        _out('D507 $tok done state=LIMIT mode=$mode captures=$shots overflows=${overflows.length} exc=${exc != null} ovfRaw=${overflows.isEmpty ? '-' : base64Url.encode(utf8.encode(overflows.join('\n'))).replaceAll('=', '')}');
        must('끝 예외 0', exc == null, '예외 $exc');
        await t.pumpWidget(const SizedBox.shrink());
      } catch (e) {
        _anyFail = true;
        rethrow;
      }
    }, skip: !_optIn);
  }
}
