// ignore_for_file: depend_on_referenced_packages
// [DU494 · 자체 판정 셀 · 표시만] DU-S061 리뷰 태그 관리(슈퍼관리자) — 탭 · 구역 머리 · 태그 칩 · 빈 목록 글자와 조작 아이콘 대비.
//   before = 현재 A(review_tags_settings_screen 333ec2cd) / strict = 후보(미선택 탭 보조색 · 제목 본문색 · 칩 · 아이콘 진한 짝).
//   harness 는 DU492 시험(b983a789)과 같다. 앱 테마(RoleTheme.superAdminTheme) · 화면은 load 주입(R62 와 같다).
//   값은 닿은 즉시 지역 값으로 남긴다(preflight v6). 기본 skip — TB before/du494-tb/DU_BEFORE_OBSERVE=494 · TA after/du494-ta/없음.
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
import 'package:ALfit/screens/super_admin/review_tags_settings_screen.dart';
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

/// 지원자 평가 탭: 긍정 2(success) · 개선 1(warning). 사업장 평가 탭: 둘 다 비어 있다(빈 목록 글자).
Future<Map<String, dynamic>?> _load() async => {
      'positiveTags': ['시간 준수', '성실함'],
      'improvementTags': ['집중력'],
      'businessPositiveTags': <String>[],
      'businessImprovementTags': <String>[],
    };

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
  'white': Color(0xFFFFFFFF), 'textPrimary': AppColors.textPrimary, 'textSecondary': AppColors.textSecondary,
  'grey400': AppColors.grey400, 'grey500': AppColors.grey500, 'grey600': AppColors.grey600,
  'success': AppColors.success, 'successDark': AppColors.successDark, 'warning': AppColors.warning, 'warningDark': AppColors.warningDark,
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

final bool _before = Platform.environment['DU_BEFORE_OBSERVE'] == '494';
final Map<String, String> _env = Platform.environment;
final bool _optIn =
    (_env['DU1_VQ_PHASE'] == 'before' && _env['DU1_VQ_RUN'] == 'du494-tb' && _env['DU_BEFORE_OBSERVE'] == '494') ||
        (_env['DU1_VQ_PHASE'] == 'after' && _env['DU1_VQ_RUN'] == 'du494-ta' && _env['DU_BEFORE_OBSERVE'] == null);
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
    testWidgets('S061RT-${v.id}-TAGS 리뷰 태그 관리 — 글자 · 조작 아이콘 대비', (t) async {
      if (_anyFail) fail('앞 사례 실패 — 이 사례 본문 실행 0 · 캡처 0');
      try {
        final tok = 'S061RT-${v.id}-TAGS';
        final mode = _before ? 'before' : 'strict';
        _out('D494 $tok begin mode=$mode phase=${Platform.environment['DU1_VQ_PHASE'] ?? '(unset)'} env=$_envLine manifest=$_manifest');
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
              home: const ReviewTagsSettingsScreen(load: _load),
            ),
          ),
        ));
        for (var i = 0; i < 4; i++) {
          await t.pump(const Duration(milliseconds: 100));
        }
        Finder rt(bool Function(String p) p) => find.byWidgetPredicate((w) => w is RichText && p(_plainOf(w)), skipOffstage: false);
        var shots = 0;
        _out('D494 $tok shot 1top ovf=${overflows.length}');
        await vqCapture(t, key, '${tok}_1top', conditions: {
          'viewport': '${v.w.toInt()}x${v.h.toInt()}', 'textScaler': v.s, 'run': vqRun, 'manifest': _manifest, 'mode': mode, 'fixture': 'TAGS',
          'state': 'review-tags-worker-top',
        });
        shots++;
        // 글자 하나 — 정확히 1개 · (스크롤 주면) 닿게 내린 뒤 · 글자색 · 놓인 면 · 대비.
        Future<(Color?, Color?, double, Finder)> txt(String what, bool Function(String p) p, Finder? scroll) async {
          final f = rt(p);
          must('$what 1', f.evaluate().length == 1, '개수 ${f.evaluate().length}');
          if (scroll != null) {
            await t.scrollUntilVisible(f, 120, scrollable: scroll, maxScrolls: 40);
            await t.pump(const Duration(milliseconds: 50));
          }
          final c = (t.widget(f) as RichText).text.style?.color;
          final bg = _bgOf(f.evaluate().first);
          return (c, bg, _cr(c, bg), f);
        }

        // 같은 Row 안 아이콘 — 색 · 놓인 면 · 대비(조작 아이콘 3:1).
        (Color?, double) icon(Finder near, IconData d) {
          final row = find.ancestor(of: near, matching: find.byType(Row, skipOffstage: false)).first;
          final f = find.descendant(of: row, matching: find.byIcon(d, skipOffstage: false), skipOffstage: false);
          must('아이콘 $d 1', f.evaluate().length == 1, '개수 ${f.evaluate().length}');
          final c = (t.widget(f) as Icon).color;
          return (c, _cr(c, _bgOf(f.evaluate().first)));
        }

        final tabA = await txt('미선택 탭(사업장 평가)', (p) => p == '사업장 평가', null);
        _out('D494 $tok att tab text=${_tok(tabA.$1)} bg=${_tok(tabA.$2)} cr=${_f(tabA.$3)}');
        final pTitleF = rt((p) => p == '긍정 태그 (2개)');
        must('긍정 제목 1', pTitleF.evaluate().length == 1, '개수 ${pTitleF.evaluate().length}');
        final page = find.ancestor(of: pTitleF, matching: find.byType(Scrollable, skipOffstage: false)).first;
        final pt = await txt('긍정 제목', (p) => p == '긍정 태그 (2개)', page);
        final ps = await txt('긍정 부제', (p) => p == '관리자가 지원자에게 부여하는 긍정적 평가', page);
        final pa = icon(pt.$4, Icons.add_circle_outline);
        _out('D494 $tok att phead title=${_tok(pt.$1)} bg=${_tok(pt.$2)} tcr=${_f(pt.$3)} sub=${_tok(ps.$1)} scr=${_f(ps.$3)} add=${_tok(pa.$1)} acr=${_f(pa.$2)}');
        final pc = await txt('긍정 칩', (p) => p == '시간 준수', page);
        final px = icon(pc.$4, Icons.close);
        _out('D494 $tok att pchip text=${_tok(pc.$1)} bg=${_tok(pc.$2)} cr=${_f(pc.$3)} close=${_tok(px.$1)} ccr=${_f(px.$2)}');
        final it = await txt('개선 제목', (p) => p == '개선 태그 (1개)', page);
        final isub = await txt('개선 부제', (p) => p == '관리자가 지원자에게 부여하는 개선점', page);
        final ia = icon(it.$4, Icons.add_circle_outline);
        _out('D494 $tok att ihead title=${_tok(it.$1)} bg=${_tok(it.$2)} tcr=${_f(it.$3)} sub=${_tok(isub.$1)} scr=${_f(isub.$3)} add=${_tok(ia.$1)} acr=${_f(ia.$2)}');
        final ic = await txt('개선 칩', (p) => p == '집중력', page);
        final ix = icon(ic.$4, Icons.close);
        _out('D494 $tok att ichip text=${_tok(ic.$1)} bg=${_tok(ic.$2)} cr=${_f(ic.$3)} close=${_tok(ix.$1)} ccr=${_f(ix.$2)}');
        _out('D494 $tok shot 2imp ovf=${overflows.length}');
        await vqCapture(t, key, '${tok}_2imp', conditions: {
          'viewport': '${v.w.toInt()}x${v.h.toInt()}', 'textScaler': v.s, 'run': vqRun, 'manifest': _manifest, 'mode': mode, 'fixture': 'TAGS',
          'state': 'review-tags-worker-improvement',
        });
        shots++;
        // 사업장 평가 탭으로 — 빈 목록 글자 · 이번에는 '지원자 평가'가 미선택 탭이다.
        await t.tap(rt((p) => p == '사업장 평가'));
        for (var i = 0; i < 6; i++) {
          await t.pump(const Duration(milliseconds: 100));
        }
        final emptyF = rt((p) => p == '등록된 태그가 없습니다');
        must('빈 목록 글자 2', emptyF.evaluate().length == 2, '개수 ${emptyF.evaluate().length}');
        final ec = (t.widget(emptyF.first) as RichText).text.style?.color;
        final eb = _bgOf(emptyF.evaluate().first);
        final ecr = _cr(ec, eb);
        _out('D494 $tok att empty text=${_tok(ec)} bg=${_tok(eb)} cr=${_f(ecr)}');
        final tabB = await txt('미선택 탭(지원자 평가)', (p) => p == '지원자 평가', null);
        _out('D494 $tok att tabb text=${_tok(tabB.$1)} bg=${_tok(tabB.$2)} cr=${_f(tabB.$3)}');
        _out('D494 $tok shot 3biz ovf=${overflows.length}');
        await vqCapture(t, key, '${tok}_3biz', conditions: {
          'viewport': '${v.w.toInt()}x${v.h.toInt()}', 'textScaler': v.s, 'run': vqRun, 'manifest': _manifest, 'mode': mode, 'fixture': 'TAGS',
          'state': 'review-tags-business-empty',
        });
        shots++;
        // 배치는 끝났다 — 넘침 수집기를 먼저 되돌린다(바꾼 채 expect 가 실패하면 tearDownAll 이 멈춘다 · DU475 진단).
        FlutterError.onError = prev;
        if (_before) {
          // 음성 기대(코드 확정 · 산술) — 탭 grey500 · 제목 구역 색 · 부제 grey600 · 칩 · 아이콘 구역 색 · 빈 글자 grey400.
          must('before 미선택 탭 grey500 미달', tabA.$1 == AppColors.grey500 && tabA.$3 < 4.5 && tabB.$1 == AppColors.grey500, '${_f(tabA.$3)} ${_tok(tabB.$1)}');
          must('before 제목 구역 색 미달', pt.$1 == AppColors.success && it.$1 == AppColors.warning && pt.$3 < 4.5 && it.$3 < 4.5, '${_f(pt.$3)} ${_f(it.$3)}');
          must('before 부제 grey600 미달', ps.$1 == AppColors.grey600 && isub.$1 == AppColors.grey600 && ps.$3 < 4.5 && isub.$3 < 4.5, '${_f(ps.$3)} ${_f(isub.$3)}');
          must('before 칩 글자 구역 색 미달', pc.$1 == AppColors.success && ic.$1 == AppColors.warning && pc.$3 < 4.5 && ic.$3 < 4.5, '${_f(pc.$3)} ${_f(ic.$3)}');
          must('before 조작 아이콘 구역 색 3:1 미달', pa.$1 == AppColors.success && ia.$1 == AppColors.warning && px.$1 == AppColors.success && ix.$1 == AppColors.warning
              && [pa.$2, ia.$2, px.$2, ix.$2].every((x) => x < 3.0), [pa.$2, ia.$2, px.$2, ix.$2].map(_f).join(','));
          must('before 빈 글자 grey400 미달', ec == AppColors.grey400 && ecr < 4.5, _f(ecr));
        } else {
          must('strict 미선택 탭 textSecondary ≥ 4.5', tabA.$1 == AppColors.textSecondary && tabB.$1 == AppColors.textSecondary && tabA.$3 >= 4.5 && tabB.$3 >= 4.5,
              '${_f(tabA.$3)} ${_f(tabB.$3)}');
          must('strict 제목 textPrimary ≥ 4.5', pt.$1 == AppColors.textPrimary && it.$1 == AppColors.textPrimary && pt.$3 >= 4.5 && it.$3 >= 4.5, '${_f(pt.$3)} ${_f(it.$3)}');
          must('strict 부제 textSecondary ≥ 4.5', ps.$1 == AppColors.textSecondary && isub.$1 == AppColors.textSecondary && ps.$3 >= 4.5 && isub.$3 >= 4.5,
              '${_f(ps.$3)} ${_f(isub.$3)}');
          must('strict 칩 글자 진한 짝 ≥ 4.5', pc.$1 == AppColors.successDark && ic.$1 == AppColors.warningDark && pc.$3 >= 4.5 && ic.$3 >= 4.5, '${_f(pc.$3)} ${_f(ic.$3)}');
          must('strict 조작 아이콘 진한 짝 ≥ 3', pa.$1 == AppColors.successDark && ia.$1 == AppColors.warningDark && px.$1 == AppColors.successDark && ix.$1 == AppColors.warningDark
              && [pa.$2, ia.$2, px.$2, ix.$2].every((x) => x >= 3.0), [pa.$2, ia.$2, px.$2, ix.$2].map(_f).join(','));
          must('strict 빈 글자 textSecondary ≥ 4.5', ec == AppColors.textSecondary && ecr >= 4.5, _f(ecr));
          must('strict 넘침 0', overflows.isEmpty, overflows.join(' | '));
        }
        must('미처리 framework 예외 0', fwErrors.isEmpty, '오류 $fwErrors');
        final exc = t.takeException();
        _out('D494 $tok done state=TAGS mode=$mode captures=$shots overflows=${overflows.length} exc=${exc != null} ovfRaw=${overflows.isEmpty ? '-' : base64Url.encode(utf8.encode(overflows.join('\n'))).replaceAll('=', '')}');
        must('끝 예외 0', exc == null, '예외 $exc');
        await t.pumpWidget(const SizedBox.shrink());
      } catch (e) {
        _anyFail = true;
        rethrow;
      }
    }, skip: !_optIn);
  }
}
