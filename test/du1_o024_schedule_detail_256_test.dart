// ignore_for_file: depend_on_referenced_packages
// [DU256 O024 일정 상세 시트 넘침·시안 정렬 baseline/after] Codex 한도 중 Claude 자체 진행(허브 DU_self_review_hub_2026-11-10).
//   같은 시험을 교정 전(baseline)·후(after)에 한 번씩 돌린다. 시험은 production 을 편집하지 않는다.
//   DU256_RUN=1 이고 DU256_PHASE 가 baseline 또는 after 일 때만 실행한다(기본 skip).
//   실제 진입(ScheduleCard)처럼 DialogHelper.showSheet(isScrollControlled·useRootNavigator)로 연다. 조회는 대역(외부 채널 없음).
//   장면 2(detail 끝까지 drag · transport '찾아오는 길' 탭) × W360/1.0·B320/2.0.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:ALfit/models/core/application_model.dart';
import 'package:ALfit/models/core/business_model.dart';
import 'package:ALfit/models/core/business_work_type_model.dart';
import 'package:ALfit/models/core/insurance_rate_model.dart';
import 'package:ALfit/models/core/to_model.dart';
import 'package:ALfit/models/core/work_detail_data.dart';
import 'package:ALfit/services/work_type_guide_resolver.dart';
import 'package:ALfit/theme/role_theme.dart';
import 'package:ALfit/utils/dialog_helper.dart';
import 'package:ALfit/utils/text_layout.dart';
import 'package:ALfit/widgets/dialogs/schedule_detail_dialog.dart';
import 'package:ALfit/widgets/dialogs/schedule_detail_reads.dart';

import 'support/du1_vq_capture.dart';

const _biz = '평택 진위 스마트 물류센터 제2캠퍼스 B동';
const _wtName = '상하차 및 분류 보조';
const _addr = '경기도 평택시 진위면 마산8로 10 스마트 물류단지 B동 2층 출입구';
const _transport = '진위역 2번 출구에서 셔틀버스(08:20·08:40)를 타고 물류단지 정문에서 내립니다.';
const _note = '첫 근무일은 08:50까지 B동 2층 사무실 앞으로 와 주세요. 안전화는 현장에서 빌려 드립니다.';

ApplicationModel _app() => ApplicationModel(
      id: 'app1',
      businessId: 'biz1',
      businessName: _biz,
      toTitle: '단기 모집',
      workDate: DateTime(2026, 11, 3),
      startTime: '09:00',
      endTime: '18:00',
      uid: 'u1',
      selectedWorkType: _wtName,
      workDetailId: 'wd1',
      wage: 12000,
      wageType: 'hourly',
      status: AppStatus.confirmed,
      appliedAt: DateTime(2026, 10, 1),
      workTypeIcon: 'box',
      confirmMessage: _note,
    );

BusinessModel _business() => BusinessModel(
      id: 'biz1',
      name: _biz,
      ownerId: 'admin1',
      businessNumber: '000-00-00000',
      address: _addr,
      category: '물류',
      subCategory: '창고',
      isApproved: true,
      createdAt: DateTime(2025),
      phone: '031-123-4567',
      attendanceType: 'gps',
      parkingAvailable: true,
      mealsProvided: const ['점심'],
      transportDescription: _transport,
      precautions: '편한 운동화와 긴 바지를 준비해 주세요.',
    );

final _wt = BusinessWorkTypeModel(
  id: 'wtA',
  businessId: 'biz1',
  name: _wtName,
  icon: 'box',
  displayOrder: 0,
  isActive: true,
  createdAt: DateTime(2025),
  oneLineIntro: '입고된 상자를 내리고 행선지별로 나누는 일입니다.',
  description: '컨베이어로 들어오는 상자를 내려 행선지 표시에 맞춰 팔레트에 쌓습니다.',
  duties: '하차 · 분류 · 팔레트 적재',
  workEnvironment: '실내 창고(냉난방), 서서 하는 일',
  requirements: '만 18세 이상, 20kg 이하 상자를 들 수 있는 분',
  precautions: '지게차 통로에는 들어가지 않습니다.',
);

TOModel _to() => TOModel(
      id: 'to1',
      businessId: 'biz1',
      businessName: _biz,
      type: 'flex',
      title: '단기 모집',
      creatorUID: 'admin1',
      status: TOStatus.active,
      deadlineType: 'NONE',
      hoursBeforeStart: 0,
      workDetails: [
        WorkDetailData(
          wdId: 'wd1',
          workTypeId: 'wtA',
          workType: _wtName,
          workTypeIcon: 'box',
          wage: 12000,
          requiredCount: 2,
          startTime: '09:00',
          endTime: '18:00',
          breakMinutes: 60,
          payScheduleType: 'next_day',
          payScheduleTime: '17:30',
          taxDeductionType: InsuranceRateModel.typeDailyWorker,
        ),
      ],
      totalRequired: 2,
      totalConfirmed: 1,
      totalPending: 0,
      isPublished: true,
      publishMode: 'immediate',
      createdAt: DateTime(2026, 9, 1),
      storedCreatedAt: DateTime(2026, 9, 1),
      statusUpdatedAt: DateTime(2026, 9, 1),
    );

double _lum(Color c) {
  double ch(double v) => v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * ch(c.r) + 0.7152 * ch(c.g) + 0.0722 * ch(c.b);
}

double _contrast(Color a, Color b) {
  final x = _lum(a);
  final y = _lum(b);
  return (math.max(x, y) + 0.05) / (math.min(x, y) + 0.05);
}

String _hex(Color c) => '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

void _out(String l) {
  // ignore: avoid_print
  print(l);
}

/// 글자 단위 줄 나눔 — 줄마다 보이는 글자, 그리고 '낱말 안에서 끊긴' 곳 수.
///   끊긴 자리 앞뒤가 모두 한글 음절·영숫자이고 그 사이에 공백·ZWSP·줄바꿈·구두점이 없으면 음절 끊김으로 센다.
({List<String> lines, int sylBreaks}) _lineInfo(RenderParagraph rp) {
  final raw = rp.text.toPlainText();
  final wj = String.fromCharCode(0x2060);
  final zw = String.fromCharCode(0x200B);
  bool word(String ch) {
    final u = ch.codeUnitAt(0);
    return (u >= 0xAC00 && u <= 0xD7A3) || (u >= 0x30 && u <= 0x39) || (u >= 0x41 && u <= 0x5A) || (u >= 0x61 && u <= 0x7A);
  }

  final lines = <String>[];
  var buf = StringBuffer();
  int? lastTop;
  var lastIdx = -1;
  var breaks = 0;
  for (var i = 0; i < raw.length; i++) {
    final ch = raw[i];
    if (ch == wj) continue;
    final bx = rp.getBoxesForSelection(TextSelection(baseOffset: i, extentOffset: i + 1));
    if (bx.isEmpty || ch == ' ' || ch == zw) {
      buf.write(ch);
      continue;
    }
    final top = bx.first.top.round();
    if (lastTop != null && top != lastTop) {
      lines.add(TextLayout.plain(buf.toString()).trim());
      buf = StringBuffer();
      final gap = raw.substring(lastIdx, i + 1);
      final sep = gap.contains(' ') || gap.contains(zw) || gap.contains(String.fromCharCode(10)) ||
          RegExp('[·,./()~-]').hasMatch(gap);
      if (!sep && word(raw[lastIdx]) && word(ch)) breaks++;
    }
    buf.write(ch);
    lastTop = top;
    lastIdx = i;
  }
  lines.add(TextLayout.plain(buf.toString()).trim());
  return (lines: lines, sylBreaks: breaks);
}

void main() {
  final phase = Platform.environment['DU256_PHASE'] ?? '';
  final run = Platform.environment['DU256_RUN'] == '1' && (phase == 'baseline' || phase == 'after');
  final after = phase == 'after';
  final nl = String.fromCharCode(10);

  setUpAll(() async {
    await initializeDateFormatting('ko_KR', null);
  });

  testWidgets('D256 $phase', (t) async {
    await t.runAsync(vqLoadFonts);
    t.platformDispatcher.localesTestValue = const [Locale('ko', 'KR')];
    t.platformDispatcher.localeTestValue = const Locale('ko', 'KR');
    final prevOnError = FlutterError.onError;
    final errors = <String>[];
    FlutterError.onError = (d) => errors.add(d.exceptionAsString().split(nl).first);
    var nPump = 0, nDrag = 0, nPng = 0, nTap = 0;
    var cur = '(시작)';
    Never stop(String why) {
      _out('D256-STOP ${jsonEncode({'at': cur, 'why': why, 'errors': errors})}');
      fail('$cur: $why');
    }

    void need(bool ok, String why) {
      if (!ok) stop(why);
    }

    Future<void> frames(int n) async {
      for (var i = 0; i < n; i++) {
        nPump++;
        need(nPump <= 1400 && nDrag <= 80 && nPng <= 100 && nTap <= 12, '사용량 한도'); // [r1] B320 세로 배치로 길어짐
        await t.pump(const Duration(milliseconds: 50));
      }
    }

    final overflow = <String>[];
    void safe(String at) {
      final ex = t.takeException();
      need(ex == null, '$at 예외: $ex');
      for (final e in errors) {
        if (!after && e.startsWith('A RenderFlex overflowed by')) {
          overflow.add('$at $e');
        } else {
          stop('$at 예외/overflow: $e');
        }
      }
      errors.clear();
    }

    Finder rich(bool Function(String p) f) =>
        find.byWidgetPredicate((w) => w is RichText && f(TextLayout.plain(w.text.toPlainText())), skipOffstage: false);
    Finder? nth(Finder f, int i) {
      final els = f.evaluate().toList();
      if (els.isEmpty) return null;
      final e = i < 0 ? els.last : (i < els.length ? els[i] : null);
      if (e == null) return null;
      return find.byElementPredicate((x) => identical(x, e), skipOffstage: false);
    }

    Finder? glyph(IconData icon, int i) {
      final f = find.descendant(of: find.byIcon(icon, skipOffstage: false), matching: find.byType(RichText), skipOffstage: false);
      return nth(f, i);
    }

    double r1(double v) => double.parse(v.toStringAsFixed(1));
    List<double> lt(Rect r) => [r.left, r.top, r.right, r.bottom].map(r1).toList();
    bool inside(Rect r, Rect b) => r.left >= b.left - 0.5 && r.top >= b.top - 0.5 && r.right <= b.right + 0.5 && r.bottom <= b.bottom + 0.5;

    Color bgOf(Element e) {
      final layers = <Color>[];
      e.visitAncestorElements((a) {
        final w = a.widget;
        Color? c;
        if (w is ColoredBox) {
          c = w.color;
        } else if (w is DecoratedBox && w.decoration is BoxDecoration) {
          c = (w.decoration as BoxDecoration).color;
        } else if (w is Material && w.type != MaterialType.transparency) {
          c = w.color ?? Theme.of(a).canvasColor;
        } else if (w is Scaffold) {
          c = w.backgroundColor ?? Theme.of(a).scaffoldBackgroundColor;
        }
        if (c == null || c.a == 0) return true;
        layers.add(c);
        return c.a < 1.0;
      });
      var out = layers.isEmpty ? Colors.white : layers.last;
      for (final c in layers.reversed.skip(1)) {
        out = Color.alphaBlend(c, out);
      }
      return out;
    }

    final key = GlobalKey();
    final reads = ScheduleDetailReads(
      businessById: (_) async => _business(),
      toByApplication: (_) async => _to(),
      workTypeCatalog: (_) async => WorkTypeCatalog(
          businessId: 'biz1', byId: {'wtA': _wt}, nameCounts: const {_wtName: 1}, complete: true),
    );
    try {
      for (final c in const [
        (id: 'W360', w: 360.0, h: 780.0, s: 1.0),
        (id: 'B320', w: 320.0, h: 640.0, s: 2.0),
      ]) {
        for (final sc in const ['detail', 'transport']) {
          cur = '${c.id} $sc';
          await t.pumpWidget(const SizedBox.shrink());
          await frames(1);
          safe('장면 종료');
          overflow.clear();
          t.view.physicalSize = Size(c.w, c.h);
          t.view.devicePixelRatio = 1.0;
          t.platformDispatcher.textScaleFactorTestValue = c.s;
          final screen = Rect.fromLTWH(0, 0, c.w, c.h);
          await t.pumpWidget(RepaintBoundary(
            key: key,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: RoleTheme.workerTheme,
              localizationsDelegates: const [
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              supportedLocales: const [Locale('ko', 'KR')],
              home: Scaffold(
                body: Center(
                  child: Builder(
                    builder: (ctx) => TextButton(
                      onPressed: () => DialogHelper.showSheet<void>(ctx,
                          isScrollControlled: true,
                          useRootNavigator: true,
                          builder: (_) => ScheduleDetailDialog(application: _app(), reads: reads)),
                      child: const Text('열기'),
                    ),
                  ),
                ),
              ),
            ),
          ));
          await frames(2);
          nTap++;
          await t.tap(find.text('열기'));
          await frames(14);
          safe('시트 열림');
          need(find.byType(ScheduleDetailDialog).evaluate().length == 1, '시트가 열리지 않았다');

          final transportFinder = find.byWidgetPredicate((w) => w.runtimeType.toString() == '_TransportSheet', skipOffstage: false);
          Finder? sfOf() {
            final host = sc == 'transport' ? transportFinder : find.byType(ScheduleDetailDialog);
            final f = find.descendant(of: host, matching: find.byType(Scrollable), skipOffstage: false);
            return f.evaluate().isEmpty ? null : nth(f, 0);
          }

          if (sc == 'transport') {
            final link = nth(rich((p) => p == '찾아오는 길'), 0);
            need(link != null, "'찾아오는 길' 줄이 없다");
            await t.ensureVisible(link!);
            await frames(6);
            nTap++;
            await t.tap(find.ancestor(of: link, matching: find.byType(InkWell)).first);
            await frames(14);
            safe('교통 시트 열림');
            need(transportFinder.evaluate().length == 1, '교통 시트가 열리지 않았다');
          }

          Map<String, Object?> info(String nm, Finder? f, {String? kind, bool lines = false, Finder? box}) {
            if (f == null) return {'name': nm, 'kind': kind, 'present': false};
            final rp = t.renderObject<RenderParagraph>(f);
            final r = t.getRect(f);
            final fg = rp.text.style?.color;
            final bg = bgOf(f.evaluate().first);
            final sf = sfOf();
            final inSf = sf != null && find.descendant(of: sf, matching: f, skipOffstage: false).evaluate().isNotEmpty;
            final vp = inSf ? t.getRect(sf) : screen;
            final li = lines ? _lineInfo(rp) : null;
            Rect? br;
            if (box != null && box.evaluate().isNotEmpty) br = t.getRect(box.first);
            return {
              'name': nm, 'kind': kind, 'present': true, 'rect': lt(r), 'visible': inside(r, screen) && inside(r, vp),
              'fontSize': rp.text.style?.fontSize, 'weight': rp.text.style?.fontWeight?.value,
              'fg': fg == null ? null : _hex(fg), 'bg': _hex(bg),
              'contrast': fg == null ? null : double.parse(_contrast(fg, bg).toStringAsFixed(2)),
              'didExceedMaxLines': rp.didExceedMaxLines, 'maxLines': rp.maxLines,
              if (li != null) 'lines': li.lines,
              if (li != null) 'sylBreaks': li.sylBreaks,
              if (br != null) 'boxH': r1(br.height),
            };
          }

          Finder? anc(Finder? f, bool Function(Widget w) p) =>
              f == null ? null : find.ancestor(of: f, matching: find.byWidgetPredicate(p, skipOffstage: false));

          List<Map<String, Object?>> measure() {
            if (sc == 'transport') {
              return [
                info('T 제목', nth(rich((p) => p == '찾아오는 길'), -1), kind: 'title'),
                info('T 라벨 주소', nth(rich((p) => p == '주소'), -1), kind: 'label', lines: true),
                info('T 라벨 안내', nth(rich((p) => p == '찾아오는 길 안내'), -1), kind: 'label', lines: true),
                info('T 주소', nth(rich((p) => p == _addr), -1), kind: 'body', lines: true),
                info('T 안내', nth(rich((p) => p == _transport), -1), kind: 'body', lines: true),
                info('T 주차', nth(rich((p) => p == '주차 가능'), -1), kind: 'ok'),
                info('T 주차 아이콘', glyph(Icons.check_circle_outline, -1), kind: 'okIcon'),
                info('T 머리 아이콘', glyph(Icons.directions_transit_outlined, -1), kind: 'icon'),
                info('T 닫기', glyph(Icons.close, -1), kind: 'icon'),
              ];
            }
            final link = nth(rich((p) => p == '찾아오는 길'), 0);
            final phone = nth(rich((p) => p.startsWith('전화하기')), 0);
            return [
              info('H 사업장명', nth(rich((p) => p == _biz), 0), kind: 'name', lines: true),
              info('H 업무명', nth(rich((p) => p == _wtName), 0), kind: 'sub', lines: true),
              info('H 상태', nth(rich((p) => p == '확정'), 0)),
              info('H 닫기', glyph(Icons.close, 0), kind: 'icon'),
              for (final s in ['근무 정보', '근무 장소', '업무 안내', '관리자 안내'])
                info('S $s', nth(rich((p) => p == s), 0), kind: 'section'),
              for (final l in ['근무일', '근무시간', '급여', '정산', '입금 예정', '공제', '출근 인증'])
                info('L $l', nth(rich((p) => p == l), 0), kind: 'label', lines: true),
              info('V 시간', nth(rich((p) => p == '09:00 ~ 18:00'), 0), kind: 'value'),
              info('V 예정', nth(rich((p) => p.startsWith('· 예정')), 0), kind: 'aux'),
              info('V 급여', nth(rich((p) => p.contains('12,000원')), 0), kind: 'value'),
              info('P 사업장명', nth(rich((p) => p == _biz), 1), kind: 'name', lines: true),
              info('P 주소', nth(rich((p) => p == _addr), 0), kind: 'aux', lines: true),
              info('P 전화', phone, kind: 'action', box: anc(phone, (w) => w is OutlinedButton)),
              info('P 찾아오는 길', link, kind: 'link', box: anc(link, (w) => w is InkWell)),
              info('P 찾아오는 길 아이콘', glyph(Icons.directions_transit_outlined, 0), kind: 'icon'),
              info('P 꺾쇠', glyph(Icons.chevron_right, 0), kind: 'chev'),
              info('P 칩 주차', nth(rich((p) => p == '주차 가능'), 0), kind: 'chip'),
              info('P 칩 식사', nth(rich((p) => p == '식사 점심'), 0), kind: 'chip'),
              info('G 한 줄 소개', nth(rich((p) => p == _wt.oneLineIntro), 0), kind: 'aux', lines: true),
              for (final l in ['업무 설명', '주요 업무', '근무 환경', '자격 요건', '주의사항'])
                info('G 라벨 $l', nth(rich((p) => p == l), 0), kind: 'label', lines: true),
              info('G 설명', nth(rich((p) => p == _wt.description), 0), kind: 'body', lines: true),
              info('G 준비사항', nth(rich((p) => p == '준비사항'), 0)),
              info('M 관리자 안내', nth(rich((p) => p == _note), 0), kind: 'body', lines: true),
            ];
          }

          void afterChecks(List<Map<String, Object?>> xs, String at) {
            if (!after) return;
            for (final x in xs) {
              if (x['present'] != true || x['visible'] != true) continue;
              final k = x['kind'];
              final cst = x['contrast'];
              final fs = x['fontSize'];
              need(x['didExceedMaxLines'] != true, '$at 말줄임/잘림 $x');
              final sb = x['sylBreaks'];
              if (sb is int && k != 'body') need(sb == 0, '$at 음절 끊김 $x');
              switch (k) {
                case 'label' || 'aux':
                  need(x['fg'] == '#60646F' && cst is double && cst >= 4.5, '$at 라벨·보조 글자 $x');
                case 'section':
                  need(x['fg'] == '#21242D' && fs == 16.0 && x['weight'] == 700, '$at 섹션 제목 $x');
                case 'name':
                  need(x['fg'] == '#21242D' && x['maxLines'] == null, '$at 사업장명 $x');
                case 'sub':
                  need(x['fg'] == '#60646F' && x['maxLines'] == null, '$at 업무명 $x');
                case 'icon':
                  need(x['fg'] == '#60646F', '$at 중립 아이콘 $x');
                case 'chev':
                  need(x['fg'] == '#686C77', '$at 꺾쇠 $x');
                case 'chip':
                  need(x['fg'] == '#60646F' && cst is double && cst >= 4.5, '$at 칩 $x');
                case 'action':
                  need(cst is double && cst >= 4.5 && (x['boxH'] as double? ?? 0) >= 48, '$at 전화 버튼 $x');
                case 'link':
                  need(x['fg'] == '#21242D' && (x['boxH'] as double? ?? 0) >= 48, "$at '찾아오는 길' 줄 $x");
                case 'ok' || 'okIcon':
                  need(x['fg'] == '#166534', '$at 주차 가능 $x');
                default:
                  if (cst is double && k != null) need(cst >= 4.5, '$at 대비 $x');
              }
            }
          }

          final shots = <Map<String, Object?>>[];
          Future<void> snap(String suffix) async {
            final xs = measure();
            afterChecks(xs, suffix.isEmpty ? '첫 화면' : suffix);
            // [v2] 고정 머리글이 시트를 차지하지 않는다 — 상세 시트의 스크롤 영역이 화면 높이의 60% 이상(v1 B320 은 약 34%).
            if (after && sc == 'detail' && suffix.isEmpty) {
              final vh = t.getRect(sfOf()!).height;
              need(vh >= c.h * 0.6, '스크롤 영역이 좁다 ${r1(vh)} / ${c.h}');
            }
            nPng++;
            await vqCapture(t, key, 'D256-$phase-${c.id}_$sc$suffix', conditions: {
              'phase': phase, 'scene': sc, 'viewport': '${c.w.toInt()}x${c.h.toInt()}', 'textScaleFactor(기기)': c.s,
            });
            final sf = sfOf();
            shots.add({'shot': suffix.isEmpty ? 'top' : suffix, 'texts': xs,
              'pixels': sf == null ? null : r1(t.state<ScrollableState>(sf).position.pixels)});
          }

          await snap('');
          var atEnd = true;
          if (sfOf() != null) {
            var k = 0;
            while (k < 30) { // [r1] 14 → 30(B320 after 는 세로 배치로 내용이 길다)
              final sf = sfOf()!;
              final vp = t.getRect(sf);
              final pos = t.state<ScrollableState>(sf).position;
              if (pos.pixels >= pos.maxScrollExtent - 0.5) break;
              k++;
              nDrag++;
              await t.dragFrom(Offset(vp.left + 24, vp.top + vp.height * 0.6), Offset(0, -(vp.height * 0.5)));
              await frames(8);
              safe('drag $k 뒤');
              await snap('_d$k');
            }
            final pos = t.state<ScrollableState>(sfOf()!).position;
            atEnd = pos.pixels >= pos.maxScrollExtent - 0.5;
          }
          if (after) need(atEnd, '끝 도달 실패');
          _out('D256 ${jsonEncode({'phase': phase, 'cond': c.id, 'scene': sc, 'overflow': overflow, 'atEnd': atEnd, 'shots': shots,
                'counts': {'pump': nPump, 'drag': nDrag, 'png': nPng, 'tap': nTap}})}');
        }
      }
      await t.pumpWidget(const SizedBox.shrink());
      await frames(1);
      safe('END 전');
      _out('D256-END ${jsonEncode({'pump': nPump, 'drag': nDrag, 'png': nPng, 'tap': nTap})}');
    } finally {
      FlutterError.onError = prevOnError;
      t.platformDispatcher.clearLocalesTestValue();
      t.platformDispatcher.clearLocaleTestValue();
      t.platformDispatcher.clearTextScaleFactorTestValue();
      t.view.reset();
    }
  }, skip: !run, timeout: const Timeout(Duration(minutes: 5)));
}
