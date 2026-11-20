// ignore_for_file: depend_on_referenced_packages
// [DU510 · 후속117 S055 행 · 표시만] DU-S055 도움말 FAQ 관리 행 — 조작 4개를 모든 배율에서 아래 줄로(질문 칸 넓게) · 삭제 진입 중립 ·
//   비활성 질문/답 미리보기/꺼진 토글 읽힘. 최종 삭제 확인 창 위험색 · 확인/취소 · 순서/콜백/writer 는 그대로(취소로만 닫는다 · writer 0).
//   before = 현재 A(help_faq_management_screen 4ca02798 · DU504 r2 채택) / strict = 후보. harness 는 DU504 r2 시험과 같다.
//   기본 skip — TB before/du510-tb/DU_BEFORE_OBSERVE=510 · TA after/du510-ta/없음.
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

import 'package:ALfit/models/core/help_faq_model.dart';
import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/screens/super_admin/help_faq_management_screen.dart';
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
String _f1(double v) => v.toStringAsFixed(1);
double _cr(Color? a, Color? b) {
  if (a == null || b == null) return 0;
  final la = a.computeLuminance(), lb = b.computeLuminance();
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

const _tokens = <String, Color>{
  'white': Color(0xFFFFFFFF), 'textSecondary': AppColors.textSecondary, 'errorDark': AppColors.errorDark, 'grey400': AppColors.grey400,
  'grey500': AppColors.grey500, 'grey600': AppColors.grey600, 'grey50': AppColors.grey50, 'brand': AppColors.brand,
};
String _tok(Color? c) {
  if (c == null) return 'none';
  for (final e in _tokens.entries) {
    if (e.value.toARGB32() == c.toARGB32()) return e.key;
  }
  return 'x${c.toARGB32().toRadixString(16).padLeft(8, '0')}';
}
String _plainOf(Widget w) => w is RichText ? TextLayout.plain(w.text.toPlainText(includeSemanticsLabels: false)) : '';

/// 놓인 면 — 조상의 칠한 색을 불투명 층까지 모아 합성한다(DU476 과 같다). 면이 없으면 흰 바탕(MaterialApp 기본 Scaffold)으로 본다.

final bool _before = Platform.environment['DU_BEFORE_OBSERVE'] == '510';
final Map<String, String> _env = Platform.environment;
final bool _optIn =
    (_env['DU1_VQ_PHASE'] == 'before' && _env['DU1_VQ_RUN'] == 'du510-tb' && _env['DU_BEFORE_OBSERVE'] == '510') ||
        (_env['DU1_VQ_PHASE'] == 'after' && _env['DU1_VQ_RUN'] == 'du510-ta' && _env['DU_BEFORE_OBSERVE'] == null);
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
    testWidgets('S055FR-${v.id}-FAQ 도움말 FAQ 관리 행 — 조작 줄 · 삭제 진입 중립 · 비활성 읽힘', (t) async {
      if (_anyFail) fail('앞 사례 실패 — 이 사례 본문 실행 0 · 캡처 0');
      try {
        final tok = 'S055FR-${v.id}-FAQ';
        final mode = _before ? 'before' : 'strict';
        _out('D510 $tok begin mode=$mode phase=${Platform.environment['DU1_VQ_PHASE'] ?? '(unset)'} env=$_envLine manifest=$_manifest');
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
        Finder rt(bool Function(String p) p) => find.byWidgetPredicate((w) => w is RichText && p(_plainOf(w)), skipOffstage: false);
        Element? nearest(Element e, bool Function(Widget w) test) {
          Element? hit;
          e.visitAncestorElements((a) {
            if (test(a.widget)) {
              hit = a;
              return false;
            }
            return true;
          });
          return hit;
        }

        Finder fe(Element e) => find.byElementPredicate((x) => identical(x, e), skipOffstage: false);
        // 행 = 질문 글을 품은 가장 가까운 테두리 Container.
        Element? rowOf(String qPrefix) {
          final q = rt((p) => p.startsWith(qPrefix)).evaluate().toList();
          if (q.length != 1) return null;
          return nearest(q.first, (w) => w is Container && w.decoration is BoxDecoration && (w.decoration as BoxDecoration).border != null);
        }

        Element? btnIn(Element row, String tip) {
          final l = find.descendant(of: fe(row), matching: find.byWidgetPredicate((w) => w is IconButton && w.tooltip == tip, skipOffstage: false), skipOffstage: false)
              .evaluate()
              .toList();
          return l.length == 1 ? l.first : null;
        }

        Color? iconColorOf(Element? btn) => btn == null ? null : ((btn.widget as IconButton).icon as Icon).color;
        // ── 활성 질문 행(u1) — 질문 칸 폭 · 조작 줄 위치 · 삭제 진입 색 · 답 미리보기 색/대비 · 조작 누르는 자리 ──
        final r1 = rowOf('공고에 지원하려면');
        must('활성 행 1', r1 != null, '없음');
        final qEl = rt((p) => p.startsWith('공고에 지원하려면')).evaluate().first;
        final qRp = qEl.renderObject! as RenderParagraph;
        final avail = qRp.constraints.maxWidth;
        final rowW = (r1!.renderObject! as RenderBox).size.width;
        final del1 = btnIn(r1, '삭제');
        final qRect = t.getRect(fe(qEl));
        final below = del1 != null && t.getRect(fe(del1)).top >= qRect.bottom - 0.5;
        final ansEl = rt((p) => p == '계좌와 통장사본을 등록해야 합니다.').evaluate().toList();
        final ansC = ansEl.isEmpty ? null : (ansEl.first.widget as RichText).text.style?.color;
        final row1Bg = ((r1.widget as Container).decoration as BoxDecoration).color;
        final rx = [for (final tip in const ['비활성화', '수정', '삭제']) btnIn(r1, tip)]
            .map((b) => b == null ? 0.0 : math.min(t.getRect(fe(b)).width, t.getRect(fe(b)).height))
            .reduce(math.min);
        _out('D510 $tok att act avail=${_f1(avail)} rowW=${_f1(rowW)} below=$below del=${_tok(iconColorOf(del1))} ans=${_tok(ansC)} ansCr=${_f(_cr(ansC, row1Bg))} rx=${_f1(rx)}');
        // ── 비활성 질문 행(u2) — 질문 글 · 토글 색 · 대비(회색 면 위) ──
        final r2 = rowOf('급여는 언제');
        must('비활성 행 1', r2 != null, '없음');
        final q2El = rt((p) => p.startsWith('급여는 언제')).evaluate().first;
        final q2C = (q2El.widget as RichText).text.style?.color;
        final row2Bg = ((r2!.widget as Container).decoration as BoxDecoration).color;
        final tog2 = btnIn(r2, '활성화');
        _out('D510 $tok att off q=${_tok(q2C)} qCr=${_f(_cr(q2C, row2Bg))} tog=${_tok(iconColorOf(tog2))}');
        _out('D510 $tok shot 1user ovf=${overflows.length}');
        await vqCapture(t, key, '${tok}_1user', conditions: {
          'viewport': '${v.w.toInt()}x${v.h.toInt()}', 'textScaler': v.s, 'run': vqRun, 'manifest': _manifest, 'mode': mode, 'fixture': 'FAQ',
          'state': 'faq-user-rows',
        });
        shots++;
        // ── 마지막 행(u2) 삭제 진입 — 실제로 굴려 보이게 한 뒤 중심 hit(누르지 않는다) ──
        var lastReach = false;
        if (tog2 != null) {
          final d2 = btnIn(r2, '삭제');
          if (d2 != null) {
            await t.ensureVisible(fe(d2));
            await t.pump(const Duration(milliseconds: 100));
            final d2b = btnIn(rowOf('급여는 언제')!, '삭제');
            final ro = d2b?.renderObject;
            if (ro is RenderBox && ro.hasSize) {
              final c = ro.localToGlobal(ro.size.center(Offset.zero));
              lastReach = (Offset.zero & Size(v.w, v.h)).contains(c) && t.hitTestOnBinding(c).path.any((h) => identical(h.target, ro));
            }
          }
        }
        _out('D510 $tok att last reach=$lastReach');
        // ── 활성 행 삭제 진입 → 최종 확인 창(위험색은 여기만) → 취소(writer 0) ──
        var cOpen = false, cClosed = false;
        Color? cFill;
        final d1 = btnIn(rowOf('공고에 지원하려면')!, '삭제');
        if (d1 != null) {
          await t.ensureVisible(fe(d1));
          await t.pump(const Duration(milliseconds: 100));
          await t.tap(fe(btnIn(rowOf('공고에 지원하려면')!, '삭제')!));
          for (var i = 0; i < 6; i++) {
            await t.pump(const Duration(milliseconds: 100));
          }
          cOpen = rt((p) => p == '항목 삭제').evaluate().isNotEmpty;
          final okT = find.descendant(of: find.byType(Dialog), matching: rt((p) => p == '삭제'), skipOffstage: false).evaluate().toList();
          if (okT.isNotEmpty) {
            final fb = nearest(okT.first, (w) =>
                (w is DecoratedBox && w.decoration is BoxDecoration && (w.decoration as BoxDecoration).color != null) ||
                (w is Material && w.color != null && w.color!.a > 0 && w.type != MaterialType.transparency));
            final fw = fb?.widget;
            cFill = fw is DecoratedBox ? (fw.decoration as BoxDecoration).color : (fw is Material ? fw.color : null);
          }
          _out('D510 $tok shot 2confirm ovf=${overflows.length}');
          await vqCapture(t, key, '${tok}_2confirm', conditions: {
            'viewport': '${v.w.toInt()}x${v.h.toInt()}', 'textScaler': v.s, 'run': vqRun, 'manifest': _manifest, 'mode': mode, 'fixture': 'FAQ',
            'state': 'faq-delete-confirm',
          });
          shots++;
          final cancel = find.descendant(of: find.byType(Dialog), matching: rt((p) => p == '취소'), skipOffstage: false);
          if (cancel.evaluate().isNotEmpty) {
            await t.tap(cancel.first, warnIfMissed: false);
            for (var i = 0; i < 6; i++) {
              await t.pump(const Duration(milliseconds: 100));
            }
          }
          cClosed = find.byType(Dialog).evaluate().isEmpty && rt((p) => p.startsWith('공고에 지원하려면')).evaluate().length == 1;
        } else {
          _out('D510 $tok shot 2confirm ovf=${overflows.length}');
          await vqCapture(t, key, '${tok}_2confirm', conditions: {
            'viewport': '${v.w.toInt()}x${v.h.toInt()}', 'textScaler': v.s, 'run': vqRun, 'manifest': _manifest, 'mode': mode, 'fixture': 'FAQ',
            'state': 'faq-delete-confirm',
          });
          shots++;
        }
        _out('D510 $tok att confirm open=$cOpen fill=${_tok(cFill)} closed=$cClosed');
        // 측정 끝 — 넘침 수집기를 되돌린 뒤 단언한다(DU475 · v34).
        FlutterError.onError = prev;
        if (_before) {
          // 음성 기대(코드 확정 · base 4ca02798) — 삭제 진입 errorDark · 비활성 질문 grey400 · W 는 조작이 오른쪽(아래 줄 아님).
          must('before 삭제 진입 빨강 · 비활성 질문 grey400', _tok(iconColorOf(del1)) == 'errorDark' && _tok(q2C) == 'grey400', '${_tok(iconColorOf(del1))} ${_tok(q2C)}');
          if (v.id == 'W') must('before W 조작 오른쪽(질문 칸 좁음)', !below, 'below $below');
        } else {
          must('strict 조작 아래 줄 · 질문 칸 넓음', below && avail >= rowW * 0.6, 'below $below avail ${_f1(avail)} rowW ${_f1(rowW)}');
          must('strict 삭제 진입 중립 · 답 미리보기 textSecondary ≥ 4.5', _tok(iconColorOf(del1)) == 'textSecondary' && _tok(ansC) == 'textSecondary' && _cr(ansC, row1Bg) >= 4.5,
              '${_tok(iconColorOf(del1))} ${_tok(ansC)} ${_f(_cr(ansC, row1Bg))}');
          must('strict 비활성 질문 · 토글 읽힘 ≥ 4.5', _tok(q2C) == 'textSecondary' && _cr(q2C, row2Bg) >= 4.5 && _tok(iconColorOf(tog2)) == 'textSecondary',
              '${_tok(q2C)} ${_f(_cr(q2C, row2Bg))} ${_tok(iconColorOf(tog2))}');
          must('strict 조작 누르는 자리 ≥ 48 · 마지막 행 도달', rx >= 48 - 0.01 && lastReach, '${_f1(rx)} $lastReach');
          must('strict 최종 확인 창 위험색 · 취소 닫힘', cOpen && _tok(cFill) == 'errorDark' && cClosed, '$cOpen ${_tok(cFill)} $cClosed');
          must('strict 넘침 0', overflows.isEmpty, overflows.join(' | '));
        }
        must('미처리 framework 예외 0', fwErrors.isEmpty, '오류 $fwErrors');
        final exc = t.takeException();
        _out('D510 $tok done state=FAQ mode=$mode captures=$shots overflows=${overflows.length} exc=${exc != null} ovfRaw=${overflows.isEmpty ? '-' : base64Url.encode(utf8.encode(overflows.join('\n'))).replaceAll('=', '')}');
        must('끝 예외 0', exc == null, '예외 $exc');
        await t.pumpWidget(const SizedBox.shrink());
      } catch (e) {
        _anyFail = true;
        rethrow;
      }
    }, skip: !_optIn);
  }
}
