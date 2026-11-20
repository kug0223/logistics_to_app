// [DU475 r2 · 후속114 합본 · 표시만] 색 3곳 + 응답 기한 Row 전문/낱말 조판(strict 넘침 0). r1(70266d19)에서 기한 블록 · rendering import · _breaks 만 바꿨다.
// [DU475 · 자체 판정 셀 · 표시만] DU-S041 공고 상세 — 초대 약속 카드(InvitationPromiseCard) '다른 업무 제안' 상자(면 grey50) 글자 대비.
//   '기존 지원' grey500 → textTertiary · 기존 지원 줄(취소선) grey600 → textTertiary · 정리 안내 grey600 → textSecondary.
//   before = 현재 A(invitation_promise_card b5f5d51f) / strict = 후보. harness 는 DU464 시험 구조(값 즉시 · 넘침 출처)를 카드 단독 렌더로 옮겼다.
//   카드는 Firebase · Provider 를 쓰지 않는다(invitation_promise_card_kst_test 와 같다). 상태 1(ALT · 다른 업무 제안 · 원 지원 있음).
//   기본 skip — TB before/du475-tb/DU_BEFORE_OBSERVE=475 · TA after/du475-ta/없음.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:ALfit/models/core/application_model.dart';
import 'package:ALfit/models/ui/invitation_projection.dart';
import 'package:ALfit/theme/app_colors.dart';
import 'package:ALfit/theme/role_theme.dart';
import 'package:ALfit/utils/text_layout.dart';
import 'package:ALfit/widgets/user/invitation_promise_card.dart';

import 'support/du1_vq_capture.dart';

/// KST 벽시계 → 절대 시각(기기 local) — invitation_promise_card_kst_test 와 같다.
DateTime _kst(int y, int m, int d, [int h = 0, int min = 0]) => DateTime.utc(y, m, d, h - 9, min).toLocal();

ApplicationModel _app({
  required String id,
  required String workType,
  required String start,
  required String end,
  required int wage,
  required String status,
  String? offerKind,
  String? sourceWorkType,
  String? compensationOption,
  DateTime? inviteExpiresAt,
}) =>
    ApplicationModel(
      id: id, businessId: 'b1', businessName: '골든패스 테스트 사업장', toTitle: '물류센터 공고', workDate: _kst(2026, 11, 20),
      startTime: start, endTime: end, uid: '7oZZ', selectedWorkType: workType, wage: wage, wageType: 'hourly', breakMinutes: 0,
      status: status, appliedAt: _kst(2026, 11, 17, 10), invitedAt: _kst(2026, 11, 18, 9), inviteExpiresAt: inviteExpiresAt,
      offerKind: offerKind, sourceWorkType: sourceWorkType, compensationOption: compensationOption,
    );

// 다른 업무 제안(B) · 원 지원(A) — 서버 기록 그대로의 모양.
final _offer = _app(
  id: 'B_offer', workType: '상차', start: '14:00', end: '18:00', wage: 13000, status: 'INVITED',
  offerKind: 'ALTERNATIVE_WORK', sourceWorkType: '분류', compensationOption: 'MATCH_SOURCE_WAGE',
  inviteExpiresAt: _kst(2026, 11, 19, 22),
);
final _source = _app(id: 'A_source', workType: '분류', start: '09:00', end: '13:00', wage: 12000, status: 'PENDING');

final _cases = <({String id, List<(String, bool Function(String p), Color before, Color after)> lines})>[
  (id: 'ALT', lines: [
    ('label', (p) => p == '기존 지원', AppColors.grey500, AppColors.textTertiary),
    ('src', (p) => p.startsWith('분류 · 09:00~13:00'), AppColors.grey600, AppColors.textTertiary),
    ('note', (p) => p.startsWith('수락하면 기존 지원은'), AppColors.grey600, AppColors.textSecondary),
  ]),
];

void _out(String s) {
  // ignore: avoid_print
  print(s);
}

String _f(double v) => v.toStringAsFixed(2);
String _hex(Color? c) => c == null ? 'none' : c.toARGB32().toRadixString(16).padLeft(8, '0');
String _plainOf(Widget w) => w is RichText ? TextLayout.plain(w.text.toPlainText(includeSemanticsLabels: false)) : '';

/// 글자 상자 top 으로 줄을 가른다 — 줄바꿈이 공백 · NBSP · ZWSP 뒤에서만 일어났는가(r446 시험과 같다).
({int lines, bool ok}) _breaks(RenderParagraph rp) {
  final s = rp.text.toPlainText(includeSemanticsLabels: false);
  final tops = <double>[];
  double? prevTop;
  var ok = true;
  for (var i = 0; i < s.length; i++) {
    final bx = rp.getBoxesForSelection(TextSelection(baseOffset: i, extentOffset: i + 1));
    if (bx.isEmpty) continue;
    final tp = bx.first.top;
    if (!tops.any((x) => (x - tp).abs() < 0.5)) tops.add(tp);
    if (prevTop != null && (tp - prevTop).abs() >= 0.5) {
      final raw = s.substring(0, i);
      if (!(raw.endsWith(' ') || raw.endsWith(String.fromCharCode(0x00A0)) || raw.endsWith(String.fromCharCode(0x200B)))) ok = false;
    }
    prevTop = tp;
  }
  return (lines: tops.length, ok: ok);
}

double _cr(Color? a, Color? b) {
  if (a == null || b == null) return 0;
  final la = a.computeLuminance(), lb = b.computeLuminance();
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

final bool _before = Platform.environment['DU_BEFORE_OBSERVE'] == '475';
final Map<String, String> _env = Platform.environment;
final bool _optIn =
    (_env['DU1_VQ_PHASE'] == 'before' && _env['DU1_VQ_RUN'] == 'du475-tb' && _env['DU_BEFORE_OBSERVE'] == '475') ||
        (_env['DU1_VQ_PHASE'] == 'after' && _env['DU1_VQ_RUN'] == 'du475-ta' && _env['DU_BEFORE_OBSERVE'] == null);
var _anyFail = false;
final String _manifest = Platform.environment['DUL_MANIFEST'] ?? '(unset)';
const _envKeys = ['DU_BEFORE_OBSERVE', 'DU1_VQ_PHASE', 'DU1_VQ_OUT', 'DU1_VQ_RUN', 'DU1_VQ_DATE', 'DU397_DIAG', 'DU397_MANIFEST', 'DU400_MANIFEST',
  'DU401_MANIFEST', 'DU398_MANIFEST', 'DU406_MANIFEST', 'DU407_MANIFEST', 'DU296_PHASE', 'DUL_MANIFEST'];
final String _envLine = [for (final k in _envKeys) '$k:${Platform.environment[k] ?? '(unset)'}'].join(',');

const _tokens = <String, Color>{
  'white': Color(0xFFFFFFFF), 'textSecondary': AppColors.textSecondary, 'textTertiary': AppColors.textTertiary,
  'grey50': AppColors.grey50, 'grey100': AppColors.grey100, 'grey300': AppColors.grey300, 'grey400': AppColors.grey400,
  'grey500': AppColors.grey500, 'grey600': AppColors.grey600, 'surface': AppColors.surface, 'background': AppColors.background,
};
String _tok(Color? c) {
  if (c == null) return 'none';
  for (final e in _tokens.entries) {
    if (e.value.toARGB32() == c.toARGB32()) return e.key;
  }
  return 'x${_hex(c)}';
}

/// 놓인 면 — 가장 가까운 조상의 칠한 색(Container color · BoxDecoration color · ColoredBox · Material(투명 아님)).
Color? _bgOf(Element e) {
  Color? found;
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
      found = c;
      return false;
    }
    return true;
  });
  return found;
}

void main() {
  // lgate hidden 계약(setUpAll 1개) — 카드는 Firebase 를 쓰지 않으므로 날짜 기호만 준비한다.
  setUpAll(() async {
    await initializeDateFormatting('ko_KR', null);
  });

  const views =[(id: 'W', w: 390.0, h: 844.0, s: 1.0), (id: 'B', w: 320.0, h: 640.0, s: 2.0)];
  for (final v in views) {
    for (final c in _cases) {
    testWidgets('S041IO-${v.id}-${c.id} 초대 약속 카드 — 다른 업무 제안 상자 글자 대비', (t) async {
      if (_anyFail) fail('앞 사례 실패 — 이 사례 본문 실행 0 · 캡처 0');
      try {
        final tok = 'S041IO-${v.id}-${c.id}';
        final mode = _before ? 'before' : 'strict';
        _out('D475 $tok begin mode=$mode phase=${Platform.environment['DU1_VQ_PHASE'] ?? '(unset)'} env=$_envLine manifest=$_manifest');
        await t.runAsync(vqLoadFonts);
        final overflows = <String>[];
        final fwErrors = <String>[];
        final prev = FlutterError.onError;
        FlutterError.onError = (d) {
          final m = d.exceptionAsString();
          if (m.contains('overflowed')) {
            // 넘침 출처(파일:줄)를 함께 남긴다(DU446 · 447 교훈).
            final full = d.toString();
            final k = full.indexOf('The relevant error-causing widget was');
            final loc = k < 0 ? '' : full.substring(k).split('\n').skip(1).firstWhere((l) => l.trim().isNotEmpty, orElse: () => '').trim();
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
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: RoleTheme.workerTheme,
            builder: (ctx, child) => MediaQuery(data: MediaQuery.of(ctx).copyWith(textScaler: TextScaler.linear(v.s)), child: child!),
            home: Scaffold(
              backgroundColor: AppColors.grey50,
              body: SingleChildScrollView(
                child: InvitationPromiseCard(
                  projection: InvitationProjection(
                    application: _offer,
                    contextState: InvitationContextState.loaded,
                    acceptability: InvitationAcceptability.acceptable,
                    drift: const InvitationDrift(),
                  ),
                  sourceApplication: _source,
                ),
              ),
            ),
          ),
        ));
        for (var i = 0; i < 8; i++) {
          await t.pump(const Duration(milliseconds: 50));
        }
        Finder rt(bool Function(String p) p) => find.byWidgetPredicate((w) => w is RichText && p(_plainOf(w)), skipOffstage: false);
        // 상자가 화면 위쪽에 오게 한다(B 큰 글자에서 카드가 화면보다 길다).
        await t.ensureVisible(rt(c.lines.first.$2));
        for (var i = 0; i < 4; i++) {
          await t.pump(const Duration(milliseconds: 50));
        }
        var shots = 0;
        Future<void> shot(String sub, String state) async {
          _out('D475 $tok shot $sub ovf=${overflows.length}');
          await vqCapture(t, key, '${tok}_$sub', conditions: {
            'viewport': '${v.w.toInt()}x${v.h.toInt()}', 'textScaler': v.s, 'run': vqRun, 'manifest': _manifest, 'mode': mode, 'fixture': c.id,
            'state': state,
          });
          shots++;
        }

        await shot('1box', 'alternative-offer');
        // 배치는 끝났다 — 넘침 수집기를 먼저 되돌린다. 바꾼 채 expect 가 실패하면 binding assert 로 tearDownAll 이 멈춘다(진단 rc 124).
        FlutterError.onError = prev;

        // ── 다른 업무 제안 상자 글자(값은 즉시) — 글자색 · 놓인 면 · 대비 ──
        for (final l in c.lines) {
          final f = rt(l.$2);
          must('${l.$1} 1', f.evaluate().length == 1, '개수 ${f.evaluate().length}');
          final col = (t.widget(f) as RichText).text.style?.color;
          final bg = _bgOf(f.evaluate().first);
          final cr = _cr(col, bg);
          if (l.$1 == 'label') {
            _out('D475 $tok att label text=${_tok(col)} bg=${_tok(bg)} cr=${_f(cr)}');
          } else if (l.$1 == 'src') {
            _out('D475 $tok att src text=${_tok(col)} bg=${_tok(bg)} cr=${_f(cr)}');
          } else {
            _out('D475 $tok att note text=${_tok(col)} bg=${_tok(bg)} cr=${_f(cr)}');
          }
          if (_before) {
            // 음성 기대(코드 확정) — grey500 약 2.6 · grey600 4.42(면 grey50).
            must('before ${l.$1} ${_tok(l.$3)} · 대비 미달 검출', col == l.$3 && cr < 4.5, '${_tok(col)} ${_f(cr)}');
          } else {
            must('strict ${l.$1} ${_tok(l.$4)} · 대비 ≥ 4.5', col == l.$4 && cr >= 4.5, '${_tok(col)} ${_f(cr)}');
          }
        }
        // [r2 · 후속114 §3] 응답 기한 줄 — 가용폭 안에서 낱말 단위 전문 표시. 기존 'B 1 허용'은 이어가지 않는다(strict 넘침 0).
        final dl = rt((p) => p.endsWith('까지 응답'));
        must('응답 기한 줄 1', dl.evaluate().length == 1, '개수 ${dl.evaluate().length}');
        final dlFull = _plainOf(t.widget(dl)) == '11월 19일 22:00까지 응답';
        final dlRight = t.getRect(dl).right;
        final rowRight = t.getRect(find.ancestor(of: dl, matching: find.byType(Row, skipOffstage: false)).first).right;
        final dj = _breaks(t.renderObject(dl) as RenderParagraph);
        final inside = dlRight <= rowRight + 0.5;
        _out('D475 $tok att deadline full=$dlFull lines=${dj.lines} ok=${dj.ok} inside=$inside');
        if (_before) {
          // 음성 기대(진단 · 원PNG 확인) — B 는 응답 기한 글자가 제 Row 오른쪽을 넘는다(넘침 1) · W 는 칸 안.
          must('before 응답 기한 B 칸 밖 · W 칸 안', inside == (v.id == 'W'), '오른쪽 ${_f(dlRight)} · Row ${_f(rowRight)}');
        } else {
          must('strict 응답 기한 전문 · 칸 안 · 낱말 경계', dlFull && inside && dj.ok, 'full $dlFull inside $inside ok ${dj.ok} 줄 ${dj.lines}');
          must('strict 넘침 0', overflows.isEmpty, overflows.join(' | '));
        }
        must('미처리 framework 예외 0', fwErrors.isEmpty, '오류 $fwErrors');
        final exc = t.takeException();
        _out('D475 $tok done state=${c.id} mode=$mode captures=$shots overflows=${overflows.length} exc=${exc != null} ovfRaw=${overflows.isEmpty ? '-' : base64Url.encode(utf8.encode(overflows.join('\n'))).replaceAll('=', '')}');
        must('끝 예외 0', exc == null, '예외 $exc');
        await t.pumpWidget(const SizedBox.shrink());
      } catch (e) {
        _anyFail = true;
        rethrow;
      }
    }, skip: !_optIn);
    }
  }
}
