// ignore_for_file: depend_on_referenced_packages
// [DU293 보강 — 근로자 일정 달력(ScheduleCalendar) 머리 전·후] Codex 한도 중 Claude 자체 진행(허브 DU_self_review_hub_2026-11-10).
//   DU293 WM4(공용 AppCalendar 머리 낱말 단위)가 근로자 일정 달력에 주는 효과를 위젯 단독 렌더로 남긴다(실제 일정 화면 시각 시험은 기존 실패).
//   DU293B_RUN=1 이고 DU293B_PHASE 가 baseline 또는 after 일 때만 실행한다(기본 skip). 시험은 production 을 편집하지 않는다.
//   조건 W360/1.0·M360/1.5·B320/2.0. 누르는 것은 없다.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:ALfit/models/core/application_model.dart';
import 'package:ALfit/theme/role_theme.dart';
import 'package:ALfit/utils/text_layout.dart';
import 'package:ALfit/widgets/calendar/schedule_calendar.dart';

import 'support/du1_vq_capture.dart';

void _out(String l) {
  // ignore: avoid_print
  print(l);
}

void main() {
  final phase = Platform.environment['DU293B_PHASE'] ?? '';
  final run = Platform.environment['DU293B_RUN'] == '1' && (phase == 'baseline' || phase == 'after');
  final after = phase == 'after';
  final nl = String.fromCharCode(10);
  final wj = String.fromCharCode(0x2060);

  setUpAll(() async {
    await initializeDateFormatting('ko_KR', null);
  });

  testWidgets('D293B $phase', (t) async {
    await t.runAsync(vqLoadFonts);
    t.platformDispatcher.localesTestValue = const [Locale('ko', 'KR')];
    t.platformDispatcher.localeTestValue = const Locale('ko', 'KR');
    final prevOnError = FlutterError.onError;
    final errors = <String>[];
    FlutterError.onError = (d) => errors.add(d.exceptionAsString().split(nl).first);
    final key = GlobalKey();
    final rows = <Map<String, Object?>>[];
    final now = DateTime.now();
    final focus = DateTime(now.year, now.month, 15);
    try {
      for (final c in const [
        (id: 'W360', w: 360.0, h: 780.0, s: 1.0),
        (id: 'M360', w: 360.0, h: 780.0, s: 1.5),
        (id: 'B320', w: 320.0, h: 640.0, s: 2.0),
      ]) {
        t.view.physicalSize = Size(c.w, c.h);
        t.view.devicePixelRatio = 1.0;
        t.platformDispatcher.textScaleFactorTestValue = c.s;
        await t.pumpWidget(const SizedBox.shrink());
        await t.pump(const Duration(milliseconds: 50));
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
              body: SingleChildScrollView(
                child: ScheduleCalendar(
                  focusedDay: focus,
                  selectedDay: focus,
                  applications: const <ApplicationModel>[],
                  selectedFilter: 'all',
                  onDaySelected: (_, __) {},
                  onPageChanged: (_) {},
                ),
              ),
            ),
          ),
        ));
        for (var i = 0; i < 6; i++) {
          await t.pump(const Duration(milliseconds: 50));
        }
        final ex = t.takeException();
        if (ex != null) errors.add('$ex');
        final title = '${focus.year}년 ${focus.month}월';
        final head = find.byWidgetPredicate((w) => w is RichText && TextLayout.plain(w.text.toPlainText()) == title, skipOffstage: false);
        final n = head.evaluate().length;
        var lines = -1, joined = false;
        if (n == 1) {
          final rp = t.renderObject<RenderParagraph>(head);
          final raw = rp.text.toPlainText();
          joined = raw.contains(wj);
          final tops = <int>{};
          for (var i = 0; i < raw.length; i++) {
            if (raw[i] == wj || raw[i] == ' ') continue;
            final bx = rp.getBoxesForSelection(TextSelection(baseOffset: i, extentOffset: i + 1));
            if (bx.isNotEmpty) tops.add(bx.first.top.round());
          }
          lines = tops.length;
        }
        // '11 | 월' 끊김: 숫자와 '월' 이 다른 줄
        var monthSplit = false;
        if (n == 1) {
          final rp = t.renderObject<RenderParagraph>(head);
          final raw = rp.text.toPlainText();
          final plainIdx = <int>[];
          for (var i = 0; i < raw.length; i++) {
            if (raw[i] != wj) plainIdx.add(i);
          }
          final p = TextLayout.plain(raw);
          final mi = p.lastIndexOf('월');
          if (mi > 0) {
            final a = rp.getBoxesForSelection(TextSelection(baseOffset: plainIdx[mi - 1], extentOffset: plainIdx[mi - 1] + 1));
            final b = rp.getBoxesForSelection(TextSelection(baseOffset: plainIdx[mi], extentOffset: plainIdx[mi] + 1));
            monthSplit = a.isNotEmpty && b.isNotEmpty && a.first.top.round() != b.first.top.round();
          }
        }
        await vqCapture(t, key, 'D293B-$phase-${c.id}_schedule_calendar', conditions: {
          'phase': phase, 'viewport': '${c.w.toInt()}x${c.h.toInt()}', 'textScaleFactor(기기)': c.s, 'widget': 'ScheduleCalendar 단독',
        });
        rows.add({'phase': phase, 'cond': c.id, 'title': title, 'found': n, 'lines': lines, 'joined': joined, 'monthSplit': monthSplit, 'errors': [...errors]});
        _out('D293B ${jsonEncode(rows.last)}');
        if (after) {
          expect(n, 1, reason: '머리 글 1개');
          expect(monthSplit, isFalse, reason: "'11 | 월' 끊김");
          expect(errors, isEmpty, reason: '$errors');
        }
        errors.clear();
      }
    } finally {
      FlutterError.onError = prevOnError;
      t.platformDispatcher.clearLocalesTestValue();
      t.platformDispatcher.clearLocaleTestValue();
      t.platformDispatcher.clearTextScaleFactorTestValue();
      t.view.reset();
    }
  }, skip: !run, timeout: const Timeout(Duration(minutes: 5)));
}
