// ignore_for_file: depend_on_referenced_packages
// [DU489 · 자체 판정 셀 · 표시만] DU-S053 배지 설정(슈퍼관리자) — 목록 행 글자: 조건 설명 · '비활성' 칩 · 비활성 이름.
//   before = 현재 A(badge_settings_screen cb0e7686) / strict = 후보. 문구 · 순서 · 메뉴는 그대로다.
//   harness 는 badge_settings_61_test 렌더 방식(BadgeSettingsScreen(load:) 주입 · 슈퍼관리자 대역 · Firebase core 대역)에 DU 캡처 · 측정을 붙였다.
//   상태 1(LIST · 기본 배지 + 비활성 사용자 배지 1).
//   값은 닿은 즉시 지역 값으로 남긴다(preflight v6). 기본 skip — TB before/du489-tb/DU_BEFORE_OBSERVE=489 · TA after/du489-ta/없음.
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

final bool _before = Platform.environment['DU_BEFORE_OBSERVE'] == '489';
final Map<String, String> _env = Platform.environment;
final bool _optIn =
    (_env['DU1_VQ_PHASE'] == 'before' && _env['DU1_VQ_RUN'] == 'du489-tb' && _env['DU_BEFORE_OBSERVE'] == '489') ||
        (_env['DU1_VQ_PHASE'] == 'after' && _env['DU1_VQ_RUN'] == 'du489-ta' && _env['DU_BEFORE_OBSERVE'] == null);
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
    testWidgets('S053BL-${v.id}-LIST 배지 설정 — 목록 행 글자 대비', (t) async {
      if (_anyFail) fail('앞 사례 실패 — 이 사례 본문 실행 0 · 캡처 0');
      try {
        final tok = 'S053BL-${v.id}-LIST';
        final mode = _before ? 'before' : 'strict';
        _out('D489 $tok begin mode=$mode phase=${Platform.environment['DU1_VQ_PHASE'] ?? '(unset)'} env=$_envLine manifest=$_manifest');
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
        // 비활성 배지 행 — 이름에서 가장 가까운 ListTile 조상 안에서 칩 · 조건 설명을 찾는다(위치 기준).
        final nameF = rt((p) => p == _inactiveName);
        // [진단 수리 1/3] 목록은 ListView(지연 생성)라 맨 아래 '경험' 구역 행은 아직 그려지지 않았다(진단 개수 0) — 먼저 내린다(DU485 와 같은 API).
        final list = find.descendant(of: find.byType(BadgeSettingsScreen), matching: find.byType(Scrollable), skipOffstage: false).first;
        await t.scrollUntilVisible(nameF, 200, scrollable: list, maxScrolls: 60);
        for (var i = 0; i < 2; i++) {
          await t.pump(const Duration(milliseconds: 50));
        }
        must('비활성 배지 이름 1', nameF.evaluate().length == 1, '개수 ${nameF.evaluate().length}');
        final tileF = find.ancestor(of: nameF, matching: find.byType(ListTile, skipOffstage: false)).first;
        final chipF = find.descendant(of: tileF, matching: rt((p) => p == '비활성'), skipOffstage: false);
        final listTile = t.widget(tileF) as ListTile;
        final subF = find.descendant(of: find.byWidget(listTile.subtitle!, skipOffstage: false), matching: find.byType(RichText, skipOffstage: false),
            skipOffstage: false);
        must('칩 1 · 부제 1', chipF.evaluate().length == 1 && subF.evaluate().length == 1, '${chipF.evaluate().length}/${subF.evaluate().length}');
        await t.ensureVisible(tileF);
        for (var i = 0; i < 3; i++) {
          await t.pump(const Duration(milliseconds: 50));
        }
        _out('D489 $tok shot 1list ovf=${overflows.length}');
        await vqCapture(t, key, '${tok}_1list', conditions: {
          'viewport': '${v.w.toInt()}x${v.h.toInt()}', 'textScaler': v.s, 'run': vqRun, 'manifest': _manifest, 'mode': mode, 'fixture': 'LIST',
          'state': 'badge-list-with-inactive',
        });
        // 배치는 끝났다 — 넘침 수집기를 먼저 되돌린다(바꾼 채 expect 가 실패하면 tearDownAll 이 멈춘다 · DU475 진단).
        FlutterError.onError = prev;
        const white = Color(0xFFFFFFFF);
        final nameC = (t.widget(nameF) as RichText).text.style?.color;
        final nameCr = _cr(nameC, _bgOf(nameF.evaluate().first) ?? white);
        final chipC = (t.widget(chipF) as RichText).text.style?.color;
        final chipBg = _bgOf(chipF.evaluate().first);
        final chipCr = _cr(chipC, chipBg);
        final subC = (t.widget(subF) as RichText).text.style?.color;
        final subBg = _bgOf(subF.evaluate().first) ?? white;
        final subCr = _cr(subC, subBg);
        _out('D489 $tok att name text=${_tok(nameC)} cr=${_f(nameCr)}');
        _out('D489 $tok att chip text=${_tok(chipC)} bg=${_tok(chipBg)} cr=${_f(chipCr)}');
        _out('D489 $tok att sub text=${_tok(subC)} bg=${_tok(subBg)} cr=${_f(subCr)}');
        if (_before) {
          // 음성 기대(코드 확정) — 이름 grey400(1.88) · 칩 grey500/grey200(2.31) · 부제 grey500(2.68).
          must('before 이름 grey400 · 칩 grey500/grey200 · 부제 grey500 · 대비 미달 검출',
              nameC == AppColors.grey400 && chipC == AppColors.grey500 && chipBg == AppColors.grey200 && subC == AppColors.grey500 &&
                  nameCr < 4.5 && chipCr < 4.5 && subCr < 4.5,
              '${_tok(nameC)} ${_tok(chipC)}/${_tok(chipBg)} ${_tok(subC)} ${_f(nameCr)}/${_f(chipCr)}/${_f(subCr)}');
        } else {
          must('strict 이름 textTertiary · 칩 textSecondary/grey100 · 부제 textSecondary · 대비 ≥ 4.5',
              nameC == AppColors.textTertiary && chipC == AppColors.textSecondary && chipBg == AppColors.grey100 && subC == AppColors.textSecondary &&
                  nameCr >= 4.5 && chipCr >= 4.5 && subCr >= 4.5,
              '${_tok(nameC)} ${_tok(chipC)}/${_tok(chipBg)} ${_tok(subC)} ${_f(nameCr)}/${_f(chipCr)}/${_f(subCr)}');
          must('strict 넘침 0', overflows.isEmpty, overflows.join(' | '));
        }
        must('미처리 framework 예외 0', fwErrors.isEmpty, '오류 $fwErrors');
        final exc = t.takeException();
        _out('D489 $tok done state=LIST mode=$mode captures=1 overflows=${overflows.length} exc=${exc != null} ovfRaw=${overflows.isEmpty ? '-' : base64Url.encode(utf8.encode(overflows.join('\n'))).replaceAll('=', '')}');
        must('끝 예외 0', exc == null, '예외 $exc');
        await t.pumpWidget(const SizedBox.shrink());
      } catch (e) {
        _anyFail = true;
        rethrow;
      }
    }, skip: !_optIn);
  }
}
