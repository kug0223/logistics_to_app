// ignore_for_file: depend_on_referenced_packages
// [DU490 · 자체 판정 셀 · 표시만] DU-S053 배지 설정(슈퍼관리자) — 구역 머리 제목 글자 4곳(신뢰도 · 근태 · 전문 · 경력).
//   before = 현재 A(badge_settings_screen 02594ccf · DU489 후보) / strict = 후보(구역 색 → textPrimary). 아이콘 · 머리 면은 그대로다.
//   harness 는 DU489 시험(4f93b1b0)과 같고 측정을 구역 머리 4곳으로 바꿨다(ListView 지연 생성이라 차례로 내려 잰다).
//   값은 닿은 즉시 지역 값으로 남긴다(preflight v6). 기본 skip — TB before/du490-tb/DU_BEFORE_OBSERVE=490 · TA after/du490-ta/없음.
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
import 'package:ALfit/models/settings/trust_settings_model.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/screens/super_admin/badge_settings_screen.dart';
import 'package:ALfit/theme/app_colors.dart';
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

/// badge_settings_61_test 와 같은 슈퍼관리자 대역.
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

const _inactiveName = '야간 근무 휴면 배지';
final _inactive = BadgeModel(
  id: 'custom_off', name: _inactiveName, icon: '🌙', type: BadgeType.experience,
  conditionType: BadgeConditionType.workDays, conditionValue: 5, isActive: false, createdAt: DateTime(2026, 10, 1), order: 0);

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
  'grey400': AppColors.grey400, 'grey500': AppColors.grey500, 'grey600': AppColors.grey600, 'grey50': AppColors.grey50,
  'grey100': AppColors.grey100, 'grey200': AppColors.grey200, 'background': AppColors.background, 'surface': AppColors.surface,
  'textPrimary': AppColors.textPrimary, 'amber': AppColors.amber, 'success': AppColors.success, 'info': AppColors.info,
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

final bool _before = Platform.environment['DU_BEFORE_OBSERVE'] == '490';
final Map<String, String> _env = Platform.environment;
final bool _optIn =
    (_env['DU1_VQ_PHASE'] == 'before' && _env['DU1_VQ_RUN'] == 'du490-tb' && _env['DU_BEFORE_OBSERVE'] == '490') ||
        (_env['DU1_VQ_PHASE'] == 'after' && _env['DU1_VQ_RUN'] == 'du490-ta' && _env['DU_BEFORE_OBSERVE'] == null);
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
    testWidgets('S053BS-${v.id}-LIST 배지 설정 — 구역 머리 제목 글자 대비', (t) async {
      if (_anyFail) fail('앞 사례 실패 — 이 사례 본문 실행 0 · 캡처 0');
      try {
        final tok = 'S053BS-${v.id}-LIST';
        final mode = _before ? 'before' : 'strict';
        _out('D490 $tok begin mode=$mode phase=${Platform.environment['DU1_VQ_PHASE'] ?? '(unset)'} env=$_envLine manifest=$_manifest');
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
              builder: (ctx, child) => MediaQuery(data: MediaQuery.of(ctx).copyWith(textScaler: TextScaler.linear(v.s)), child: child!),
              home: BadgeSettingsScreen(load: () async => [_inactive, ...BadgeModel.defaultBadges()]),
            ),
          ),
        ));
        for (var i = 0; i < 6; i++) {
          await t.pump(const Duration(milliseconds: 100));
        }

        Finder rt(bool Function(String p) p) => find.byWidgetPredicate((w) => w is RichText && p(_plainOf(w)), skipOffstage: false);
        // ── 구역 머리 4곳(값은 닿은 즉시) — 제목 글자 · 놓인 면(구역 색 10% 합성) · 대비 · 아이콘 색 ──
        final list = find.descendant(of: find.byType(BadgeSettingsScreen), matching: find.byType(Scrollable), skipOffstage: false).first;
        final heads = <(String, String, Color)>[
          ('trust', '신뢰도 배지 (', AppColors.amber),
          ('attend', '근태 배지 (', AppColors.success),
          ('special', '전문 배지 (', AppColors.info),
          ('exp', '경력 배지 (', AppColors.amber),
        ];
        final cols = <Color?>[];
        final crs = <double>[];
        final icons = <Color?>[];
        var shots = 0;
        for (final h in heads) {
          final f = rt((p) => p.startsWith(h.$2));
          await t.scrollUntilVisible(f, 200, scrollable: list, maxScrolls: 60);
          for (var i = 0; i < 2; i++) {
            await t.pump(const Duration(milliseconds: 50));
          }
          must('구역 머리 ${h.$1} 1', f.evaluate().length == 1, '개수 ${f.evaluate().length}');
          if (h.$1 == 'trust' || h.$1 == 'exp') {
            final sub = h.$1 == 'trust' ? '1trust' : '2exp';
            _out('D490 $tok shot $sub ovf=${overflows.length}');
            await vqCapture(t, key, '${tok}_$sub', conditions: {
              'viewport': '${v.w.toInt()}x${v.h.toInt()}', 'textScaler': v.s, 'run': vqRun, 'manifest': _manifest, 'mode': mode, 'fixture': 'LIST',
              'state': 'badge-section-${h.$1}',
            });
            shots++;
          }
          final c = (t.widget(f) as RichText).text.style?.color;
          final bg = _bgOf(f.evaluate().first);
          final cr = _cr(c, bg);
          final rowF = find.ancestor(of: f, matching: find.byType(Row, skipOffstage: false)).first;
          final iconF = find.descendant(of: rowF, matching: find.byType(Icon, skipOffstage: false), skipOffstage: false);
          final ic = iconF.evaluate().length == 1 ? (t.widget(iconF) as Icon).color : null;
          cols.add(c);
          crs.add(cr);
          icons.add(ic);
          if (h.$1 == 'trust') {
            _out('D490 $tok att trust text=${_tok(c)} bg=${_tok(bg)} cr=${_f(cr)} icon=${_tok(ic)}');
          } else if (h.$1 == 'attend') {
            _out('D490 $tok att attend text=${_tok(c)} bg=${_tok(bg)} cr=${_f(cr)} icon=${_tok(ic)}');
          } else if (h.$1 == 'special') {
            _out('D490 $tok att special text=${_tok(c)} bg=${_tok(bg)} cr=${_f(cr)} icon=${_tok(ic)}');
          } else {
            _out('D490 $tok att exp text=${_tok(c)} bg=${_tok(bg)} cr=${_f(cr)} icon=${_tok(ic)}');
          }
        }
        // 배치는 끝났다 — 넘침 수집기를 먼저 되돌린다(바꾼 채 expect 가 실패하면 tearDownAll 이 멈춘다 · DU475 진단).
        FlutterError.onError = prev;
        final iconsKept = [for (var i = 0; i < heads.length; i++) icons[i] == heads[i].$3].every((x) => x);
        must('아이콘은 구역 색 그대로', iconsKept, icons.map(_tok).join(','));
        if (_before) {
          // 음성 기대(코드 확정) — 제목 글자 = 구역 색 · 같은 색 10% 면 위 약 1.4–2.9.
          final ok = [for (var i = 0; i < heads.length; i++) cols[i] == heads[i].$3 && crs[i] < 4.5].every((x) => x);
          must('before 제목 = 구역 색 · 대비 미달 검출', ok, '${cols.map(_tok).join(',')} ${crs.map(_f).join(',')}');
        } else {
          final ok = [for (var i = 0; i < heads.length; i++) cols[i] == AppColors.textPrimary && crs[i] >= 4.5].every((x) => x);
          must('strict 제목 textPrimary · 대비 ≥ 4.5', ok, '${cols.map(_tok).join(',')} ${crs.map(_f).join(',')}');
          must('strict 넘침 0', overflows.isEmpty, overflows.join(' | '));
        }
        must('미처리 framework 예외 0', fwErrors.isEmpty, '오류 $fwErrors');
        final exc = t.takeException();
        _out('D490 $tok done state=LIST mode=$mode captures=$shots overflows=${overflows.length} exc=${exc != null} ovfRaw=${overflows.isEmpty ? '-' : base64Url.encode(utf8.encode(overflows.join('\n'))).replaceAll('=', '')}');
        must('끝 예외 0', exc == null, '예외 $exc');
        await t.pumpWidget(const SizedBox.shrink());
      } catch (e) {
        _anyFail = true;
        rethrow;
      }
    }, skip: !_optIn);
  }
}
