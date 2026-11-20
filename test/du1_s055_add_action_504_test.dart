// ignore_for_file: depend_on_referenced_packages
// [DU504 · 자체 판정 셀 · 표시만] DU-S055 도움말 FAQ 관리 — 탭마다 떠 있는 '항목 추가' FAB → 목록 머리 '+ 항목 추가' 글자 행동(감사48 (가)).
//   before = 준비판 A(help_faq_management_screen 02b20f16 · 읽기 경계 load 만) / strict = 후보(4ca02798 · FAB 0 · 글자 행동).
//   harness 는 DU497 시험(27dad096)과 같고, 읽기 경계로 지원자 3행 · 관리자 2행 목록을 그린다(DU497 은 읽기 실패 화면).
//   값은 닿은 즉시 지역 값으로 남긴다(preflight v6). 기본 skip — TB before/du504-tb/DU_BEFORE_OBSERVE=504 · TA after/du504-ta/없음.
import 'dart:convert';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';

import 'package:ALfit/models/core/help_faq_model.dart';
import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/screens/super_admin/help_faq_management_screen.dart';
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

/// 읽기 경계로 넣는 목록 — 지원자: 구역 머리 · 질문 · 비활성 질문 / 관리자: 구역 머리 · 질문.
const _userItems = [
  HelpFaqModel(id: 'u0', role: 'user', order: 0, category: '지원 · 근무', question: '', answer: '', isHeader: true, isActive: true),
  HelpFaqModel(id: 'u1', role: 'user', order: 1, category: '지원 · 근무', question: '공고에 지원하려면 무엇이 필요한가요?',
      answer: '계좌와 통장사본을 등록해야 합니다.', isHeader: false, isActive: true),
  HelpFaqModel(id: 'u2', role: 'user', order: 2, category: '급여', question: '급여는 언제 들어오나요?',
      answer: '사업장이 정한 날에 들어옵니다.', isHeader: false, isActive: false),
];
const _adminItems = [
  HelpFaqModel(id: 'a0', role: 'admin', order: 0, category: '공고 관리', question: '', answer: '', isHeader: true, isActive: true),
  HelpFaqModel(id: 'a1', role: 'admin', order: 1, category: '공고 관리', question: '지원자를 확정하려면 어떻게 하나요?',
      answer: '지원자 목록에서 확정을 누릅니다.', isHeader: false, isActive: true),
];

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

/// 탭 이름이 잘렸는가 — 그려진 폭이 한 줄 고유 폭보다 좁다(Tab 글자는 softWrap 없음 · fade).

void _out(String s) {
  // ignore: avoid_print
  print(s);
}

String _f(double v) => v.toStringAsFixed(2);
String _plainOf(Widget w) => w is RichText ? TextLayout.plain(w.text.toPlainText(includeSemanticsLabels: false)) : '';

/// 놓인 면 — 조상의 칠한 색을 불투명 층까지 모아 합성한다(DU476 과 같다). 면이 없으면 흰 바탕(MaterialApp 기본 Scaffold)으로 본다.

final bool _before = Platform.environment['DU_BEFORE_OBSERVE'] == '504';
final Map<String, String> _env = Platform.environment;
final bool _optIn =
    (_env['DU1_VQ_PHASE'] == 'before' && _env['DU1_VQ_RUN'] == 'du504-tb' && _env['DU_BEFORE_OBSERVE'] == '504') ||
        (_env['DU1_VQ_PHASE'] == 'after' && _env['DU1_VQ_RUN'] == 'du504-ta' && _env['DU_BEFORE_OBSERVE'] == null);
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
    testWidgets('S055FA-${v.id}-FAQ 도움말 FAQ 관리 — 추가 행동', (t) async {
      if (_anyFail) fail('앞 사례 실패 — 이 사례 본문 실행 0 · 캡처 0');
      try {
        final tok = 'S055FA-${v.id}-FAQ';
        final mode = _before ? 'before' : 'strict';
        _out('D504 $tok begin mode=$mode phase=${Platform.environment['DU1_VQ_PHASE'] ?? '(unset)'} env=$_envLine manifest=$_manifest');
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
              home: HelpFaqManagementScreen(load: (r) async => r == 'user' ? _userItems : _adminItems),
            ),
          ),
        ));
        for (var i = 0; i < 8; i++) {
          await t.pump(const Duration(milliseconds: 100));
        }
        var shots = 0;
        final screenRight = t.getRect(find.byType(HelpFaqManagementScreen)).right;
        // 보이는 탭 하나의 추가 입구 — 화면에 보이는 FAB 수 · '항목 추가' 글자 수 · 첫 질문 행 위 오른쪽 · 눌리는 짧은 변 · 글자 색(같은 상태에서 잰다).
        (int, int, String, double, bool) addOf(String firstRowPrefix) {
          final fabs = find.byType(FloatingActionButton).evaluate().length;
          final addF = find.byWidgetPredicate((w) => w is RichText && _plainOf(w) == '항목 추가');
          final adds = addF.evaluate().length;
          var pos = 'none';
          var tap = 0.0;
          var brand = false;
          if (adds == 1) {
            final ac = (t.widget(addF) as RichText).text.style?.color;
            brand = ac == RoleTheme.superAdminTheme.primaryColor;
            final btn = find.ancestor(of: addF, matching: find.byWidgetPredicate((w) => w is TextButton));
            final row = find.byWidgetPredicate((w) => w is RichText && _plainOf(w).startsWith(firstRowPrefix));
            if (btn.evaluate().isNotEmpty && row.evaluate().length == 1) {
              final br = t.getRect(btn.first);
              tap = br.height < br.width ? br.height : br.width;
              final rr = t.getRect(row);
              pos = (br.bottom <= rr.top + 0.5 && br.right >= screenRight - 40) ? 'head-right' : 'other';
            } else {
              pos = 'fab-or-missing';
            }
          }
          return (fabs, adds, pos, tap, brand);
        }

        final u = addOf('공고에 지원하려면');
        _out('D504 $tok att addu fab=${u.$1} n=${u.$2} pos=${u.$3} tap=${_f(u.$4)} brand=${u.$5}');
        _out('D504 $tok shot 1user ovf=${overflows.length}');
        await vqCapture(t, key, '${tok}_1user', conditions: {
          'viewport': '${v.w.toInt()}x${v.h.toInt()}', 'textScaler': v.s, 'run': vqRun, 'manifest': _manifest, 'mode': mode, 'fixture': 'FAQ',
          'state': 'faq-user-add',
        });
        shots++;
        await t.tap(find.byWidgetPredicate((w) => w is RichText && _plainOf(w) == '관리자 FAQ'));
        for (var i = 0; i < 6; i++) {
          await t.pump(const Duration(milliseconds: 100));
        }
        final a = addOf('지원자를 확정하려면');
        _out('D504 $tok att adda fab=${a.$1} n=${a.$2} pos=${a.$3} tap=${_f(a.$4)} brand=${a.$5}');
        _out('D504 $tok shot 2admin ovf=${overflows.length}');
        await vqCapture(t, key, '${tok}_2admin', conditions: {
          'viewport': '${v.w.toInt()}x${v.h.toInt()}', 'textScaler': v.s, 'run': vqRun, 'manifest': _manifest, 'mode': mode, 'fixture': 'FAQ',
          'state': 'faq-admin-add',
        });
        shots++;
        // 배치는 끝났다 — 넘침 수집기를 먼저 되돌린다(바꾼 채 expect 가 실패하면 tearDownAll 이 멈춘다 · DU475 진단).
        FlutterError.onError = prev;
        if (_before) {
          // 음성 기대(코드 확정) — 보이는 탭마다 떠 있는 FAB 1 · 머리 오른쪽 글자 행동 아님.
          must('before 탭마다 FAB 1 · 머리 글자 행동 아님', u.$1 == 1 && a.$1 == 1 && u.$3 != 'head-right' && a.$3 != 'head-right',
              'u ${u.$1}/${u.$3} a ${a.$1}/${a.$3}');
        } else {
          for (final (k, x) in [('지원자', u), ('관리자', a)]) {
            must('strict $k FAB 0 · 글자 행동 1 · 첫 행 위 오른쪽 · 48 · brand', x.$1 == 0 && x.$2 == 1 && x.$3 == 'head-right' && x.$4 >= 48 - 0.01 && x.$5,
                'fab ${x.$1} n ${x.$2} pos ${x.$3} tap ${_f(x.$4)} brand ${x.$5}');
          }
          must('strict 넘침 0', overflows.isEmpty, overflows.join(' | '));
        }
        must('미처리 framework 예외 0', fwErrors.isEmpty, '오류 $fwErrors');
        final exc = t.takeException();
        _out('D504 $tok done state=FAQ mode=$mode captures=$shots overflows=${overflows.length} exc=${exc != null} ovfRaw=${overflows.isEmpty ? '-' : base64Url.encode(utf8.encode(overflows.join('\n'))).replaceAll('=', '')}');
        must('끝 예외 0', exc == null, '예외 $exc');
        await t.pumpWidget(const SizedBox.shrink());
      } catch (e) {
        _anyFail = true;
        rethrow;
      }
    }, skip: !_optIn);
  }
}
