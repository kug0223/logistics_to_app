// ignore_for_file: depend_on_referenced_packages
// [DU446+447 합본 · 재배정 대비 정적 준비] DU-S041 공고 상세 '내 지원 일정' 요약 — 머리 배치 · 날짜 줄 · 글자 토큰 · 빈/오류 안내 · 오류 줄 칸 안 · 사업장명 경계.
//   before = 현재 A(apply_summary_section 642c2876) / strict = 합본 후보(03515962). DU446(ba63babf) · DU447(90f9e68a) 측정을 합쳤다.
//   실제 화면과 같은 좌우 gutter(ConceptSpace.gutter)로 요약 3개(지원 3건 · 빈 상태 · 불러오기 실패)를 한 화면에 그린다.
//   지원 fixture 는 apply_summary_expired_invite_test 와 같은 모양이다. 누르기 0 · 쓰기 0.
//   값은 닿은 즉시 지역 값으로 남긴다(preflight v6). 기본 skip — TB before/du446-tb/DU_BEFORE_OBSERVE=446 · TA after/du446-ta/없음.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:ALfit/models/core/application_model.dart';
import 'package:ALfit/theme/app_colors.dart';
import 'package:ALfit/theme/concept_tokens.dart';
import 'package:ALfit/theme/role_theme.dart';
import 'package:ALfit/utils/text_layout.dart';
import 'package:ALfit/widgets/dialogs/apply/apply_summary_section.dart';

import 'support/du1_vq_capture.dart';

DateTime _day(int offset) {
  final n = DateTime.now();
  return DateTime(n.year, n.month, n.day).add(Duration(days: offset));
}

ApplicationModel _app(String id, String toId, String status, String work, String start, String end, int dayOffset, String biz) => ApplicationModel(
      id: id, toId: toId, slotId: 'slot_$id', wdId: 'wd_$id', businessId: 'biz_$id', businessName: biz,
      toTitle: '공고 $id', uid: 'u1', applicantName: '김근로', status: status, appliedAt: _day(-1),
      workDate: _day(dayOffset), selectedWorkType: work, startTime: start, endTime: end, wage: 12000, wageType: 'hourly',
    );

final _apps = [
  _app('a1', 'to_cur', AppStatus.pending, '상차', '09:00', '18:00', 2, '골든패스 테스트 사업장 평택 제2물류센터'),
  _app('a2', 'to_x', AppStatus.confirmed, '검수', '13:00', '17:00', 3, '중앙물류센터 수도권 1센터'),
  _app('a3', 'to_y', AppStatus.pending, '포장', '10:00', '15:00', 5, '동탄 냉장창고'),
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

final bool _before = Platform.environment['DU_BEFORE_OBSERVE'] == '446';
final Map<String, String> _env = Platform.environment;
final bool _optIn =
    (_env['DU1_VQ_PHASE'] == 'before' && _env['DU1_VQ_RUN'] == 'du446-tb' && _env['DU_BEFORE_OBSERVE'] == '446') ||
        (_env['DU1_VQ_PHASE'] == 'after' && _env['DU1_VQ_RUN'] == 'du446-ta' && _env['DU_BEFORE_OBSERVE'] == null);
var _anyFail = false;
final String _manifest = Platform.environment['DUL_MANIFEST'] ?? '(unset)';
const _envKeys = ['DU_BEFORE_OBSERVE', 'DU1_VQ_PHASE', 'DU1_VQ_OUT', 'DU1_VQ_RUN', 'DU1_VQ_DATE', 'DU397_DIAG', 'DU397_MANIFEST', 'DU400_MANIFEST',
  'DU401_MANIFEST', 'DU398_MANIFEST', 'DU406_MANIFEST', 'DU407_MANIFEST', 'DU296_PHASE', 'DUL_MANIFEST'];
final String _envLine = [for (final k in _envKeys) '$k:${Platform.environment[k] ?? '(unset)'}'].join(',');

const _tokens = <String, Color>{
  'white': Color(0xFFFFFFFF), 'textSecondary': AppColors.textSecondary, 'textTertiary': AppColors.textTertiary,
  'grey400': AppColors.grey400, 'grey500': AppColors.grey500, 'grey50': AppColors.grey50, 'infoBg': AppColors.infoBg,
  'infoDark': AppColors.infoDark, 'infoDeep': AppColors.infoDeep, 'background': AppColors.background,
};
String _tok(Color? c) {
  if (c == null) return 'none';
  for (final e in _tokens.entries) {
    if (e.value.toARGB32() == c.toARGB32()) return e.key;
  }
  return 'x${_hex(c)}';
}

/// 글이 그려진 면 — 가장 가까운 조상 Container 색(decoration 또는 color), 없으면 화면 바탕.
Color _faceOf(Element e) {
  Color? c;
  e.visitAncestorElements((a) {
    final w = a.widget;
    if (w is Container && w.decoration is BoxDecoration && (w.decoration! as BoxDecoration).color != null) {
      c = (w.decoration! as BoxDecoration).color;
      return false;
    }
    if (w is Container && w.color != null) {
      c = w.color;
      return false;
    }
    return true;
  });
  return c ?? AppColors.background;
}

/// 글자 상자 top 으로 줄을 가른다 — 줄바꿈이 공백 · NBSP · 이름 가운데 표시(ZWSP) 뒤에서만 일어났는가.
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

void main() {
  setUpAll(() async => initializeDateFormatting('ko_KR', null));

  const views = [(id: 'W', w: 390.0, h: 844.0, s: 1.0), (id: 'B', w: 320.0, h: 640.0, s: 2.0)];
  for (final v in views) {
    testWidgets('S041AS-${v.id}-SUMMARY 공고 상세 내 지원 일정 — 머리 배치 · 날짜 줄 · 글자 토큰 · 빈/오류 안내', (t) async {
      if (_anyFail) fail('앞 사례 실패 — 이 사례 본문 실행 0 · 캡처 0');
      try {
        final tok = 'S041AS-${v.id}-SUMMARY';
        final mode = _before ? 'before' : 'strict';
        _out('D446 $tok begin mode=$mode phase=${Platform.environment['DU1_VQ_PHASE'] ?? '(unset)'} env=$_envLine manifest=$_manifest');
        await t.runAsync(vqLoadFonts);
        final overflows = <String>[];
        final fwErrors = <String>[];
        final prev = FlutterError.onError;
        FlutterError.onError = (d) {
          final m = d.exceptionAsString();
          if (m.contains('overflowed')) {
            // 넘침 출처(error-causing widget 다음 두 줄)를 함께 남긴다(DU446 · 447 교훈).
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

        final g = ConceptSpace.gutter(v.w);
        final key = GlobalKey();
        await t.pumpWidget(RepaintBoundary(
          key: key,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: RoleTheme.workerTheme,
            builder: (ctx, child) => MediaQuery(data: MediaQuery.of(ctx).copyWith(textScaler: TextScaler.linear(v.s)), child: child!),
            home: Scaffold(
              backgroundColor: AppColors.background,
              body: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(g, 16, g, 16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  ApplySummarySection(myApplications: _apps, currentToId: 'to_cur'),
                  const SizedBox(height: 24),
                  const ApplySummarySection(myApplications: []),
                  const SizedBox(height: 24),
                  const ApplySummarySection(myApplications: [], isLoadError: true),
                ]),
              ),
            ),
          ),
        ));
        for (var i = 0; i < 6; i++) {
          await t.pump(const Duration(milliseconds: 50));
        }
        var shots = 0;
        Future<void> shot(String sub, String state) async {
          _out('D446 $tok shot $sub ovf=${overflows.length}');
          await vqCapture(t, key, '${tok}_$sub', conditions: {
            'viewport': '${v.w.toInt()}x${v.h.toInt()}', 'textScaler': v.s, 'run': vqRun, 'manifest': _manifest, 'mode': mode, 'fixture': 'SUMMARY',
            'state': state,
          });
          shots++;
        }

        Finder rt(bool Function(String p) p) => find.byWidgetPredicate((w) => w is RichText && p(_plainOf(w)), skipOffstage: false);
        await shot('1list', 'three-sections');

        // ── 머리(값은 즉시) — 지원 3건 요약의 '전체보기 >' 와 같은 줄의 제목 ──
        final titleF = rt((p) => p == '내 지원 일정');
        final moreF = rt((p) => p == '전체보기 >');
        must('제목 3 · 전체보기 1', titleF.evaluate().length == 3 && moreF.evaluate().length == 1,
            '${titleF.evaluate().length}/${moreF.evaluate().length}');
        final title0 = titleF.evaluate().first;
        final t0 = t.getRect(find.byElementPredicate((x) => identical(x, title0), skipOffstage: false));
        final mR = t.getRect(moreF);
        final moreBelow = mR.top >= t0.bottom - 0.5;
        _out('D446 $tok att head moreBelow=$moreBelow titleW=${_f(t0.width)} moreRight=${_f(v.w - g - mR.right)}');

        // ── 날짜 줄 · 현재 공고 칩 ──
        final curF = rt((p) => p == '현재 공고');
        must('현재 공고 1', curF.evaluate().length == 1, '개수 ${curF.evaluate().length}');
        final curColor = (t.widget(curF) as RichText).text.style?.color;
        final curBg = _faceOf(curF.evaluate().first);
        final curCr = _cr(curColor, curBg);
        _out('D446 $tok att current color=${_tok(curColor)} bg=${_tok(curBg)} cr=${_f(curCr)}');

        // ── 업무/시간 · 사업장명 글자 ──
        final workF = rt((p) => p.startsWith('상차  09:00 ~ 18:00'));
        final bizF = rt((p) => p == '골든패스 테스트 사업장 평택 제2물류센터');
        must('업무/시간 · 사업장명 1/1', workF.evaluate().length == 1 && bizF.evaluate().length == 1,
            '${workF.evaluate().length}/${bizF.evaluate().length}');
        final workColor = (t.widget(workF) as RichText).text.style?.color;
        final bizColor = (t.widget(bizF) as RichText).text.style?.color;
        final face = _faceOf(workF.evaluate().first);
        final workCr = _cr(workColor, face);
        final bizCr = _cr(bizColor, face);
        _out('D446 $tok att item work=${_tok(workColor)} biz=${_tok(bizColor)} face=${_tok(face)} workCr=${_f(workCr)} bizCr=${_f(bizCr)}');

        // ── 빈 · 오류 안내 ──
        final emptyF = rt((p) => p == '오늘 이후 예정된 지원 건이 없습니다');
        final errF = rt((p) => p == '지원 현황을 불러오지 못했습니다');
        must('빈 · 오류 안내 1/1', emptyF.evaluate().length == 1 && errF.evaluate().length == 1,
            '${emptyF.evaluate().length}/${errF.evaluate().length}');
        final emptyColor = (t.widget(emptyF) as RichText).text.style?.color;
        final errColor = (t.widget(errF) as RichText).text.style?.color;
        final emptyCr = _cr(emptyColor, _faceOf(emptyF.evaluate().first));
        final errCr = _cr(errColor, _faceOf(errF.evaluate().first));
        _out('D446 $tok att quiet empty=${_tok(emptyColor)} err=${_tok(errColor)} emptyCr=${_f(emptyCr)} errCr=${_f(errCr)}');

        // 빈 · 오류 요약이 보이게 굴려 한 장 더 — 측정은 위에서 끝났다.
        await t.ensureVisible(errF);
        for (var i = 0; i < 6; i++) {
          await t.pump(const Duration(milliseconds: 50));
        }
        await shot('2quiet', 'empty-error');

        // ── [DU447] 사업장명 경계 · 오류 줄 칸 안 · 아이콘 첫 줄(굴린 뒤 새로 잡는다) ──
        final nameJ = <({int lines, bool ok})>[];
        for (final n in const ['골든패스 테스트 사업장 평택 제2물류센터', '중앙물류센터 수도권 1센터']) {
          final nf = rt((p) => p == n);
          nameJ.add(nf.evaluate().length == 1 ? _breaks(t.renderObject(nf) as RenderParagraph) : (lines: 0, ok: false));
        }
        final erp = t.renderObject(errF) as RenderParagraph;
        final ej = _breaks(erp);
        final eR = t.getRect(errF);
        final iF = find.byIcon(Icons.cloud_off_outlined, skipOffstage: false);
        final b0 = erp.getBoxesForSelection(const TextSelection(baseOffset: 0, extentOffset: 1)).first;
        final dFirst = iF.evaluate().length == 1 ? t.getRect(iF).center.dy - (eR.top + (b0.top + b0.bottom) / 2) : double.nan;
        final inside = eR.right <= v.w - g + 0.5;
        _out('D446 $tok att names lines=${nameJ.map((j) => j.lines).join('/')} ok=${nameJ.every((j) => j.ok)}');
        _out('D446 $tok att error lines=${ej.lines} ok=${ej.ok} inside=$inside dFirst=${_f(dFirst)}');

        if (_before) {
          // 음성 기대(코드 확정) — 빈 안내 · 사업장명 grey400 · 업무/시간 · 오류 grey500 · 현재 공고 infoDark.
          must('before 옅은 글자 검출', emptyColor == AppColors.grey400 && bizColor == AppColors.grey400 && workColor == AppColors.grey500 &&
              errColor == AppColors.grey500 && curColor == AppColors.infoDark,
              '${_tok(emptyColor)} ${_tok(bizColor)} ${_tok(workColor)} ${_tok(errColor)} ${_tok(curColor)}');
        } else {
          must('strict 글자 토큰 · 대비 ≥ 4.5',
              emptyColor == AppColors.textTertiary && bizColor == AppColors.textTertiary && workColor == AppColors.textSecondary &&
                  errColor == AppColors.textTertiary && curColor == AppColors.infoDeep &&
                  [emptyCr, bizCr, workCr, errCr, curCr].every((x) => x >= 4.5),
              '${_f(emptyCr)} ${_f(bizCr)} ${_f(workCr)} ${_f(errCr)} ${_f(curCr)}');
          must('strict 머리(W 같은 줄 · B 전체보기 아래 줄)', moreBelow == (v.id == 'B'), '아래 $moreBelow');
          must('strict 사업장명 경계 · 오류 줄 칸 안 · 낱말 경계 · 아이콘 첫 줄(±2)', nameJ.every((j) => j.ok) && inside && ej.ok && dFirst.abs() <= 2,
              '이름 ${nameJ.map((j) => j.ok)} 안 $inside 경계 ${ej.ok} ${_f(dFirst)}');
          must('strict 넘침 0', overflows.isEmpty, overflows.join(' | '));
        }
        must('미처리 framework 예외 0', fwErrors.isEmpty, '오류 $fwErrors');
        final exc = t.takeException();
        _out('D446 $tok done state=SUMMARY mode=$mode captures=$shots overflows=${overflows.length} exc=${exc != null} ovfRaw=${overflows.isEmpty ? '-' : base64Url.encode(utf8.encode(overflows.join('\n'))).replaceAll('=', '')}');
        must('끝 예외 0', exc == null, '예외 $exc');
        await t.pumpWidget(const SizedBox.shrink());
      } catch (e) {
        _anyFail = true;
        rethrow;
      }
    }, skip: !_optIn);
  }
}
