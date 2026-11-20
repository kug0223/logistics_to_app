// ignore_for_file: depend_on_referenced_packages
// [DU503 · 자체 판정 셀 · 표시만] DU-S053 배지 설정 — 떠 있는 '배지 추가' FAB → 목록 머리 '+ 배지 추가' 글자 행동(감사48 (가)) · 안내 띠 글자 infoDeep.
//   before = 현재 A(badge_settings_screen 0c0410ae) / strict = 후보(FAB 0 · 글자 행동 · infoDeep).
//   harness · 대역은 DU501 시험(7a4703fe)과 같고 앱 테마(RoleTheme.superAdminTheme)로 렌더한다.
//   값은 닿은 즉시 지역 값으로 남긴다(preflight v6). 기본 skip — TB before/du503-tb/DU_BEFORE_OBSERVE=503 · TA after/du503-ta/없음.
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

String _plainOf(Widget w) => w is RichText ? TextLayout.plain(w.text.toPlainText(includeSemanticsLabels: false)) : '';
String _f(double v) => v.toStringAsFixed(2);

double _cr(Color? a, Color? b) {
  if (a == null || b == null) return 0;
  final la = a.computeLuminance(), lb = b.computeLuminance();
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

/// 놓인 면 — 조상의 칠한 색을 불투명 층까지 모아 합성한다(DU476 과 같다). 면이 없으면 흰 바탕(MaterialApp 기본 Scaffold)으로 본다.

final bool _before = Platform.environment['DU_BEFORE_OBSERVE'] == '503';
final Map<String, String> _env = Platform.environment;
final bool _optIn =
    (_env['DU1_VQ_PHASE'] == 'before' && _env['DU1_VQ_RUN'] == 'du503-tb' && _env['DU_BEFORE_OBSERVE'] == '503') ||
        (_env['DU1_VQ_PHASE'] == 'after' && _env['DU1_VQ_RUN'] == 'du503-ta' && _env['DU_BEFORE_OBSERVE'] == null);
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
    testWidgets('S053BA-${v.id}-LIST 배지 설정 — 추가 행동 · 안내 띠', (t) async {
      if (_anyFail) fail('앞 사례 실패 — 이 사례 본문 실행 0 · 캡처 0');
      try {
        final tok = 'S053BA-${v.id}-LIST';
        final mode = _before ? 'before' : 'strict';
        _out('D503 $tok begin mode=$mode phase=${Platform.environment['DU1_VQ_PHASE'] ?? '(unset)'} env=$_envLine manifest=$_manifest');
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
              home: BadgeSettingsScreen(load: () async => [_inactive, ...BadgeModel.defaultBadges()]),
            ),
          ),
        ));
        for (var i = 0; i < 6; i++) {
          await t.pump(const Duration(milliseconds: 100));
        }

        Finder rt(bool Function(String p) p) => find.byWidgetPredicate((w) => w is RichText && p(_plainOf(w)), skipOffstage: false);
        var shots = 0;
        final fabs = find.byType(FloatingActionButton, skipOffstage: false).evaluate().length;
        // 안내 띠 글자 — 색 · 대비(면 infoBg).
        final infoF = rt((p) => p.startsWith('배지 정의와 조건을 관리합니다.'));
        must('안내 띠 1', infoF.evaluate().length == 1, '개수 ${infoF.evaluate().length}');
        final ic = (t.widget(infoF) as RichText).text.style?.color;
        final icr = _cr(ic, AppColors.infoBg);
        // 글자 행동 '배지 추가' — 개수 · 색 · 눌리는 크기 · 첫 구역 머리보다 위 · 오른쪽 맞춤(같은 상태에서 잰다).
        final addF = rt((p) => p == '배지 추가');
        final adds = addF.evaluate().length;
        var pos = 'none';
        var tap = 0.0;
        Color? ac;
        if (adds == 1) {
          ac = (t.widget(addF) as RichText).text.style?.color;
          final btn = find.ancestor(of: addF, matching: find.byWidgetPredicate((w) => w is TextButton, skipOffstage: false));
          if (btn.evaluate().isNotEmpty) {
            final br = t.getRect(btn.first);
            tap = br.height < br.width ? br.height : br.width;
            final head = rt((p) => p.startsWith('신뢰도 배지 ('));
            final hr = t.getRect(head);
            final screenRight = t.getRect(find.byType(BadgeSettingsScreen)).right;
            pos = (br.bottom <= hr.top + 0.5 && br.right >= screenRight - 40) ? 'head-right' : 'other';
          }
        }
        _out('D503 $tok att add fab=$fabs n=$adds pos=$pos tap=${_f(tap)} brand=${ac == RoleTheme.superAdminTheme.primaryColor} info=${ic == AppColors.infoDeep} icr=${_f(icr)}');
        _out('D503 $tok shot 1top ovf=${overflows.length}');
        await vqCapture(t, key, '${tok}_1top', conditions: {
          'viewport': '${v.w.toInt()}x${v.h.toInt()}', 'textScaler': v.s, 'run': vqRun, 'manifest': _manifest, 'mode': mode, 'fixture': 'LIST',
          'state': 'badge-add-action',
        });
        shots++;
        // 배치는 끝났다 — 넘침 수집기를 먼저 되돌린다(바꾼 채 expect 가 실패하면 tearDownAll 이 멈춘다 · DU475 진단).
        FlutterError.onError = prev;
        if (_before) {
          // 음성 기대(코드 확정) — 떠 있는 FAB 1 · 글자 행동 0 · 안내 띠 infoDark(4.03).
          must('before FAB 1 · 글자 행동 0', fabs == 1 && adds <= 1 && pos != 'head-right', 'fab $fabs n $adds pos $pos');
          must('before 안내 띠 infoDark 미달', ic == AppColors.infoDark && icr < 4.5, _f(icr));
        } else {
          must('strict FAB 0', fabs == 0, 'fab $fabs');
          must('strict 글자 행동 1 · 첫 구역 위 오른쪽 · 48 · brand', adds == 1 && pos == 'head-right' && tap >= 48 && ac == RoleTheme.superAdminTheme.primaryColor,
              'n $adds pos $pos tap ${_f(tap)} c $ac');
          must('strict 안내 띠 infoDeep ≥ 4.5', ic == AppColors.infoDeep && icr >= 4.5, _f(icr));
          must('strict 넘침 0', overflows.isEmpty, overflows.join(' | '));
        }
        must('미처리 framework 예외 0', fwErrors.isEmpty, '오류 $fwErrors');
        final exc = t.takeException();
        _out('D503 $tok done state=LIST mode=$mode captures=$shots overflows=${overflows.length} exc=${exc != null} ovfRaw=${overflows.isEmpty ? '-' : base64Url.encode(utf8.encode(overflows.join('\n'))).replaceAll('=', '')}');
        must('끝 예외 0', exc == null, '예외 $exc');
        await t.pumpWidget(const SizedBox.shrink());
      } catch (e) {
        _anyFail = true;
        rethrow;
      }
    }, skip: !_optIn);
  }
}
