// ignore_for_file: depend_on_referenced_packages
// [DU492 · 자체 판정 셀 · 표시만] DU-S052 전체 사용자 목록(슈퍼관리자 · all_users_screen) — 카드 역할 칩 · 상태 미니 칩 글자.
//   before = 현재 A(all_users_screen b61d083e · DU491 후보) / strict = 후보(역할 칩 글자 진한 짝 · 미니 칩 Bg 짝 면 + 진한 짝 글자).
//   harness 는 DU491 시험(78240e71)과 같다. 앱 테마(RoleTheme.superAdminTheme)로 카드 면을 앱과 같게 둔다.
//   값은 닿은 즉시 지역 값으로 남긴다(preflight v6). 기본 skip — TB before/du492-tb/DU_BEFORE_OBSERVE=492 · TA after/du492-ta/없음.
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
import 'package:ALfit/screens/super_admin/all_users_reads.dart';
import 'package:ALfit/screens/super_admin/all_users_screen.dart';
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

// callable 응답 모양 그대로(RR57) — Timestamp 는 {_seconds, _nanoseconds}.
Map<String, int> _ts(DateTime t) => {'_seconds': t.millisecondsSinceEpoch ~/ 1000, '_nanoseconds': 0};
final _auto = DateTime.fromMillisecondsSinceEpoch((DateTime.now().add(const Duration(days: 1)).millisecondsSinceEpoch ~/ 1000) * 1000);

/// 네 사람 — 역할 칩 셋(지원자 success · 사업장관리자 purple · 슈퍼관리자 error) · 미니 칩 셋(블랙리스트 error · 제재중 warning · 승인대기 info).
List<Map<String, dynamic>> _users() => [
      {'uid': 'u1', 'username': 'worker01', 'name': '김지원', 'email': 'u1@alfit.local', 'role': 'USER', 'createdAt': _ts(DateTime(2026, 1, 1)),
       'totalWorkDays': 12, 'noShowCount': 3, 'recentNoShowCount': 3, 'isBlacklisted': true, 'blacklistReason': '시험',
       'restrictedUntil': _ts(_auto), 'restrictionSource': 'auto', 'restrictionParts': {'auto': _ts(_auto)}},
      {'uid': 'u2', 'username': 'worker02', 'name': '이대기', 'email': 'u2@alfit.local', 'role': 'USER', 'createdAt': _ts(DateTime(2026, 2, 1)),
       'accountStatus': 'registration_pending'},
      {'uid': 'b1', 'username': 'boss01', 'name': '박사장', 'email': 'b1@alfit.local', 'role': 'BUSINESS_ADMIN', 'createdAt': _ts(DateTime(2026, 3, 1))},
      {'uid': 's1', 'username': 'ops01', 'name': '최운영', 'email': 's1@alfit.local', 'role': 'SUPER_ADMIN', 'createdAt': _ts(DateTime(2026, 4, 1))},
    ];

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
  'white': Color(0xFFFFFFFF), 'textPrimary': AppColors.textPrimary,
  'success': AppColors.success, 'successDark': AppColors.successDark, 'error': AppColors.error, 'errorDark': AppColors.errorDark,
  'errorBg': AppColors.errorBg, 'warning': AppColors.warning, 'warningDark': AppColors.warningDark, 'warningBg': AppColors.warningBg,
  'info': AppColors.info, 'infoBg': AppColors.infoBg, 'purple': AppColors.purple,
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

final bool _before = Platform.environment['DU_BEFORE_OBSERVE'] == '492';
final Map<String, String> _env = Platform.environment;
final bool _optIn =
    (_env['DU1_VQ_PHASE'] == 'before' && _env['DU1_VQ_RUN'] == 'du492-tb' && _env['DU_BEFORE_OBSERVE'] == '492') ||
        (_env['DU1_VQ_PHASE'] == 'after' && _env['DU1_VQ_RUN'] == 'du492-ta' && _env['DU_BEFORE_OBSERVE'] == null);
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
    testWidgets('S052UL-${v.id}-USERS 전체 사용자 목록 — 카드 칩 글자 대비', (t) async {
      if (_anyFail) fail('앞 사례 실패 — 이 사례 본문 실행 0 · 캡처 0');
      try {
        final tok = 'S052UL-${v.id}-USERS';
        final mode = _before ? 'before' : 'strict';
        _out('D492 $tok begin mode=$mode phase=${Platform.environment['DU1_VQ_PHASE'] ?? '(unset)'} env=$_envLine manifest=$_manifest');
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
              home: AllUsersScreen(reads: AllUsersReads(allUsersRaw: () async => _users())),
            ),
          ),
        ));
        for (var i = 0; i < 4; i++) {
          await t.pump(const Duration(milliseconds: 100));
        }
        Finder rt(bool Function(String p) p) => find.byWidgetPredicate((w) => w is RichText && p(_plainOf(w)), skipOffstage: false);
        final firstName = rt((p) => p == '김지원');
        must('첫 카드 이름 1', firstName.evaluate().length == 1, '개수 ${firstName.evaluate().length}');
        final scroll = find.ancestor(of: firstName, matching: find.byType(Scrollable, skipOffstage: false)).first;
        var shots = 0;
        _out('D492 $tok shot 1list ovf=${overflows.length}');
        await vqCapture(t, key, '${tok}_1list', conditions: {
          'viewport': '${v.w.toInt()}x${v.h.toInt()}', 'textScaler': v.s, 'run': vqRun, 'manifest': _manifest, 'mode': mode, 'fixture': 'USERS',
          'state': 'user-list-chips',
        });
        shots++;
        // 한 칩 — 그 사람 카드 안 정확히 1개(차례로 내려 닿게 한다) · 글자색 · 놓인 면 · 대비.
        Future<(Color?, Color?, double)> meas(String what, String name, String chip) async {
          final nameF = rt((p) => p == name);
          await t.scrollUntilVisible(nameF, 120, scrollable: scroll, maxScrolls: 40);
          await t.pump(const Duration(milliseconds: 50));
          final card = find.ancestor(of: nameF, matching: find.byType(Card, skipOffstage: false));
          must('$what 카드 1', card.evaluate().length == 1, '개수 ${card.evaluate().length}');
          final f = find.descendant(of: card, matching: find.byWidgetPredicate((w) => w is RichText && _plainOf(w) == chip, skipOffstage: false), skipOffstage: false);
          must('$what 1', f.evaluate().length == 1, '개수 ${f.evaluate().length}');
          final c = (t.widget(f) as RichText).text.style?.color;
          final bg = _bgOf(f.evaluate().first);
          return (c, bg, _cr(c, bg));
        }

        final roleU = await meas('지원자 칩', '김지원', '지원자');
        _out('D492 $tok att roleu text=${_tok(roleU.$1)} bg=${_tok(roleU.$2)} cr=${_f(roleU.$3)}');
        final black = await meas('블랙리스트 칩', '김지원', '블랙리스트');
        _out('D492 $tok att black text=${_tok(black.$1)} bg=${_tok(black.$2)} cr=${_f(black.$3)}');
        final restrict = await meas('제재중 칩', '김지원', '제재중');
        _out('D492 $tok att restrict text=${_tok(restrict.$1)} bg=${_tok(restrict.$2)} cr=${_f(restrict.$3)}');
        final pending = await meas('승인대기 칩', '이대기', '승인대기');
        _out('D492 $tok att pending text=${_tok(pending.$1)} bg=${_tok(pending.$2)} cr=${_f(pending.$3)}');
        final roleB = await meas('사업장관리자 칩', '박사장', '사업장관리자');
        _out('D492 $tok att roleb text=${_tok(roleB.$1)} bg=${_tok(roleB.$2)} cr=${_f(roleB.$3)}');
        final roleS = await meas('슈퍼관리자 칩', '최운영', '슈퍼관리자');
        _out('D492 $tok att roles text=${_tok(roleS.$1)} bg=${_tok(roleS.$2)} cr=${_f(roleS.$3)}');
        _out('D492 $tok shot 2end ovf=${overflows.length}');
        await vqCapture(t, key, '${tok}_2end', conditions: {
          'viewport': '${v.w.toInt()}x${v.h.toInt()}', 'textScaler': v.s, 'run': vqRun, 'manifest': _manifest, 'mode': mode, 'fixture': 'USERS',
          'state': 'user-list-chips-end',
        });
        shots++;
        // 배치는 끝났다 — 넘침 수집기를 먼저 되돌린다(바꾼 채 expect 가 실패하면 tearDownAll 이 멈춘다 · DU475 진단).
        FlutterError.onError = prev;
        // 기존 결함(진단 실측) — B 에서 칩 줄 Row 가 오른쪽으로 넘친다(9.1px · 이름 · 칩 둘). 후보는 배치를 바꾸지 않아 두 모드가 같다.
        final known = v.id == 'B' ? 1 : 0;
        must('넘침 = 기존 결함만(W 0 · B 1 · 오른쪽 · Row)', overflows.length == known && overflows.every((o) => o.contains('on the right') && o.contains('@ Row')),
            overflows.join(' | '));
        if (_before) {
          // 음성 기대(코드 확정) — 같은 색 면 위 같은 색. 사업장관리자 purple 은 이미 넘는다.
          must('before 지원자 칩 success 미달', roleU.$1 == AppColors.success && roleU.$3 < 4.5, _f(roleU.$3));
          must('before 블랙리스트 error 미달', black.$1 == AppColors.error && black.$3 < 4.5, _f(black.$3));
          must('before 제재중 warning 미달', restrict.$1 == AppColors.warning && restrict.$3 < 4.5, _f(restrict.$3));
          must('before 승인대기 info 미달', pending.$1 == AppColors.info && pending.$3 < 4.5, _f(pending.$3));
          must('before 사업장관리자 purple 통과', roleB.$1 == AppColors.purple && roleB.$3 >= 4.5, _f(roleB.$3));
          must('before 슈퍼관리자 error 미달', roleS.$1 == AppColors.error && roleS.$3 < 4.5, _f(roleS.$3));
        } else {
          must('strict 지원자 칩 successDark ≥ 4.5', roleU.$1 == AppColors.successDark && roleU.$3 >= 4.5, _f(roleU.$3));
          must('strict 블랙리스트 errorDark/errorBg ≥ 4.5', black.$1 == AppColors.errorDark && black.$2 == AppColors.errorBg && black.$3 >= 4.5, _f(black.$3));
          must('strict 제재중 warningDark/warningBg ≥ 4.5', restrict.$1 == AppColors.warningDark && restrict.$2 == AppColors.warningBg && restrict.$3 >= 4.5, _f(restrict.$3));
          must('strict 승인대기 textPrimary/infoBg ≥ 4.5', pending.$1 == AppColors.textPrimary && pending.$2 == AppColors.infoBg && pending.$3 >= 4.5, _f(pending.$3));
          must('strict 사업장관리자 purple ≥ 4.5', roleB.$1 == AppColors.purple && roleB.$3 >= 4.5, _f(roleB.$3));
          must('strict 슈퍼관리자 errorDark ≥ 4.5', roleS.$1 == AppColors.errorDark && roleS.$3 >= 4.5, _f(roleS.$3));
        }
        must('미처리 framework 예외 0', fwErrors.isEmpty, '오류 $fwErrors');
        final exc = t.takeException();
        _out('D492 $tok done state=USERS mode=$mode captures=$shots overflows=${overflows.length} exc=${exc != null} ovfRaw=${overflows.isEmpty ? '-' : base64Url.encode(utf8.encode(overflows.join('\n'))).replaceAll('=', '')}');
        must('끝 예외 0', exc == null, '예외 $exc');
        await t.pumpWidget(const SizedBox.shrink());
      } catch (e) {
        _anyFail = true;
        rethrow;
      }
    }, skip: !_optIn);
  }
}
