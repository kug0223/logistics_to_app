// ignore_for_file: depend_on_referenced_packages
// [DU292 수입 상세 월 선택 시트(DU-O104) baseline/after] Codex 한도 중 Claude 자체 진행(허브 DU_self_review_hub_2026-11-10).
//   같은 시험을 교정 전(baseline)·후(after)에 한 번씩 돌린다. 시험은 production 을 편집하지 않는다.
//   DU292_RUN=1 이고 DU292_PHASE 가 baseline 또는 after 일 때만 실행한다(기본 skip).
//   실제 IncomeDetailScreen(2026년 10월, 빈 읽기 주입)을 띄우고 연월 칩을 눌러 시트를 연다.
//   장면 A 처음(올해) · B 시트 안 '‹' 로 작년. 누르는 것: 연월 칩, B 의 '‹' 뿐(달을 고르지 않는다).
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ALfit/models/core/application_model.dart';
import 'package:ALfit/models/core/attendance_model.dart';
import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/models/core/user_region.dart';
import 'package:ALfit/providers/notification_provider.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/screens/user/income_detail_reads.dart';
import 'package:ALfit/screens/user/income_detail_screen.dart';
import 'package:ALfit/theme/role_theme.dart';
import 'package:ALfit/utils/text_layout.dart';

import 'support/du1_vq_capture.dart';
import 'support/visible_text.dart';

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

class _UserDouble extends UserProvider {
  @override
  UserModel? get currentUser => UserModel(
        uid: 'u1',
        username: 'u1',
        name: '테스트하나',
        email: 'u1@alfit.local',
        role: UserRole.USER,
        homeRegion: const UserRegion(province: '경기도', city: '평택시', district: '마산리'),
        accountStatus: 'active',
        passVerifiedAt: DateTime.now().subtract(const Duration(days: 30)),
      );
  @override
  bool get isUser => true;
  @override
  bool get isSubAdmin => false;
  @override
  bool get isBusinessAdmin => false;
  @override
  bool get isSuperAdmin => false;
  @override
  bool get isAdminMode => false;
  @override
  bool get permissionsLoaded => true;
}

IncomeDetailReads _emptyReads() => IncomeDetailReads(
      myApplications: (uid) async => const <ApplicationModel>[],
      myMonthlyAttendances: ({required String userId, required int year, required int month}) async => const <AttendanceModel>[],
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

/// 글자 단위 줄 나눔 — 줄마다 보이는 글자, '낱말 안에서 끊긴' 곳 수(DU286·288~291 시험과 같은 규칙).
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
          RegExp('[·,./()~:-]').hasMatch(gap);
      if (!sep && word(raw[lastIdx]) && word(ch)) breaks++;
    }
    buf.write(ch);
    lastTop = top;
    lastIdx = i;
  }
  lines.add(TextLayout.plain(buf.toString()).trim());
  return (lines: lines, sylBreaks: breaks);
}

double _tpHeight(String text, TextStyle? style, TextScaler scaler, Locale? locale) {
  final tp = TextPainter(text: TextSpan(text: text, style: style), textDirection: TextDirection.ltr, textScaler: scaler, locale: locale)
    ..layout();
  final h = tp.height;
  tp.dispose();
  return h;
}

final _monthRe = RegExp('^[0-9]+월\$');
final _yearRe = RegExp('^[0-9]{4}년\$');

void main() {
  final phase = Platform.environment['DU292_PHASE'] ?? '';
  final run = Platform.environment['DU292_RUN'] == '1' && (phase == 'baseline' || phase == 'after');
  final after = phase == 'after';
  final nl = String.fromCharCode(10);

  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
    SharedPreferences.setMockInitialValues({});
    await initializeDateFormatting('ko_KR', null);
  });

  testWidgets('D292 $phase', (t) async {
    await t.runAsync(vqLoadFonts);
    t.platformDispatcher.localesTestValue = const [Locale('ko', 'KR')];
    t.platformDispatcher.localeTestValue = const Locale('ko', 'KR');
    final prevOnError = FlutterError.onError;
    final errors = <String>[];
    FlutterError.onError = (d) => errors.add(d.exceptionAsString().split(nl).first);
    var nPump = 0, nPng = 0, nOpen = 0;
    var cur = '(시작)';
    Never stop(String why) {
      _out('D292-STOP ${jsonEncode({'at': cur, 'why': why, 'errors': errors})}');
      fail('$cur: $why');
    }

    void need(bool ok, String why) {
      if (!ok) stop(why);
    }

    Future<void> frames(int n) async {
      for (var i = 0; i < n; i++) {
        nPump++;
        need(nPump <= 2000 && nPng <= 10 && nOpen <= 10, '사용량 한도');
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

    double r1(double v) => double.parse(v.toStringAsFixed(1));
    double r2(double v) => double.parse(v.toStringAsFixed(2));
    List<double> lt(Rect r) => [r.left, r.top, r.right, r.bottom].map(r1).toList();
    Finder fe(Element e) => find.byElementPredicate((x) => identical(x, e), skipOffstage: false);

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

    Element? nearest(Element e, bool Function(Widget w) p) {
      Element? hit;
      e.visitAncestorElements((a) {
        if (p(a.widget)) {
          hit = a;
          return false;
        }
        return true;
      });
      return hit;
    }

    final key = GlobalKey();
    final rows = <Map<String, Object?>>[];
    try {
      for (final c in const [
        (id: 'W360', w: 360.0, h: 780.0, s: 1.0),
        (id: 'M360', w: 360.0, h: 780.0, s: 1.5),
        (id: 'B320', w: 320.0, h: 640.0, s: 2.0),
      ]) {
        t.view.physicalSize = Size(c.w, c.h);
        t.view.devicePixelRatio = 1.0;
        t.platformDispatcher.textScaleFactorTestValue = c.s;
        for (final sc in const ['A', 'B']) {
          cur = '${c.id} $sc';
          nOpen++;
          await t.pumpWidget(const SizedBox.shrink());
          await frames(1);
          safe('비움');
          await t.pumpWidget(RepaintBoundary(
            key: key,
            child: MultiProvider(
              providers: [
                ChangeNotifierProvider<UserProvider>.value(value: _UserDouble()),
                ChangeNotifierProvider<NotificationProvider>(create: (_) => NotificationProvider()),
              ],
              child: MaterialApp(
                debugShowCheckedModeBanner: false,
                theme: RoleTheme.workerTheme,
                localizationsDelegates: const [
                  GlobalMaterialLocalizations.delegate,
                  GlobalWidgetsLocalizations.delegate,
                  GlobalCupertinoLocalizations.delegate,
                ],
                supportedLocales: const [Locale('ko', 'KR')],
                home: Scaffold(body: IncomeDetailScreen(initialYear: 2026, initialMonth: 10, reads: _emptyReads())),
              ),
            ),
          ));
          await frames(20);
          safe('화면');
          final chip = findVisibleText('2026년 10월');
          need(chip.evaluate().isNotEmpty, '연월 칩 없음');
          await t.tap(chip.first);
          await frames(10);
          safe('시트 열림');
          final sheet = find.byType(BottomSheet);
          need(sheet.evaluate().length == 1, '시트 수 ${sheet.evaluate().length}');
          if (sc == 'B') {
            final prev = find.descendant(of: sheet, matching: find.byIcon(Icons.chevron_left_rounded));
            need(prev.evaluate().length == 1, "'‹' 수 ${prev.evaluate().length}");
            await t.tap(prev);
            await frames(6);
            safe('작년');
          }
          final ctxIn = t.element(sheet);
          final scaler = MediaQuery.textScalerOf(ctxIn);
          final loc = Localizations.maybeLocaleOf(ctxIn);
          final texts = <Map<String, Object?>>[];
          for (final e in find.descendant(of: sheet, matching: find.byType(RichText), skipOffstage: false).evaluate()) {
            if (nearest(e, (w) => w is Icon) != null) continue;
            final rp = t.renderObject<RenderParagraph>(fe(e));
            final plain = TextLayout.plain(rp.text.toPlainText());
            final st = rp.text.style;
            final fg = st?.color;
            final bg = bgOf(e);
            final li = _lineInfo(rp);
            final isMonth = _monthRe.hasMatch(plain);
            final gd = isMonth ? nearest(e, (w) => w is GestureDetector) : null;
            final box = gd == null ? null : t.getRect(fe(gd));
            final tappable = gd == null ? null : (gd.widget as GestureDetector).onTap != null;
            final need0 = _tpHeight(plain, st, scaler, loc);
            texts.add({
              'text': plain, 'kind': isMonth ? 'month' : (_yearRe.hasMatch(plain) ? 'year' : (plain == '기간 선택' ? 'title' : 'other')),
              'rect': lt(t.getRect(fe(e))), 'fontSize': st?.fontSize, 'fg': fg == null ? null : _hex(fg), 'bg': _hex(bg),
              'white': fg?.toARGB32() == Colors.white.toARGB32(),
              'contrast': fg == null ? null : r2(_contrast(fg, bg)), 'lines': li.lines, 'sylBreaks': li.sylBreaks,
              'didExceedMaxLines': rp.didExceedMaxLines, 'need': r1(need0),
              if (box != null) 'boxW': r1(box.width),
              if (box != null) 'boxH': r1(box.height),
              if (tappable != null) 'tappable': tappable,
            });
          }
          final months = texts.where((x) => x['kind'] == 'month').toList();
          final row = {
            'phase': phase, 'cond': c.id, 'scene': sc, 'sheetRect': lt(t.getRect(sheet)), 'months': months.length,
            'overflowSoFar': overflow.length, 'texts': texts,
          };
          if (after) {
            need(months.length == 12, '월 칸 수 ${months.length}');
            final sel = months.where((x) => x['white'] == true).map((x) => x['text']).toList();
            need(sc == 'B' ? sel.isEmpty : (sel.length == 1 && sel.first == '10월'), '선택 칸 $sel');
            if (sc == 'A') {
              final off = months.where((x) => x['tappable'] == false).map((x) => x['text']).toList();
              need(off.length == 1 && off.first == '12월', '고를 수 없는 달 $off');
            } else {
              need(months.every((x) => x['tappable'] == true), 'B 작년은 모두 고를 수 있다');
            }
            for (final x in texts) {
              final at = '${x['kind']} ${x['text']}';
              need(x['didExceedMaxLines'] != true, '$at 말줄임 $x');
              need(x['sylBreaks'] == 0, '$at 음절 끊김 $x');
              if (x['kind'] == 'month') {
                need(((x['boxH'] as double?) ?? 0) >= 48, '$at 칸 높이 $x');
                need((x['lines'] as List).length == 1, '$at 한 줄 아님 $x');
                need((x['need'] as double) <= ((x['boxH'] as double?) ?? 0) + 0.5, '$at 글이 칸보다 높다 $x');
                final cst = x['contrast'];
                need(cst is double && cst >= 4.5, '$at 대비 $x');
              }
              if (x['kind'] == 'year') need((x['lines'] as List).length == 1, '$at 연도 한 줄 아님 $x');
            }
          }
          nPng++;
          await vqCapture(t, key, 'D292-$phase-${c.id}_$sc', conditions: {
            'phase': phase, 'scene': sc, 'viewport': '${c.w.toInt()}x${c.h.toInt()}', 'textScaleFactor(기기)': c.s,
          });
          rows.add(row);
          _out('D292 ${jsonEncode(rows.last)}');
          Navigator.of(ctxIn).pop();
          await frames(8);
          safe('닫힘');
        }
      }
      if (after) {
        need(rows.length == 6, '장면 수 ${rows.length}');
        need(overflow.isEmpty, 'overflow $overflow');
      }
      await t.pumpWidget(const SizedBox.shrink());
      await frames(1);
      safe('END 전');
      _out('D292-END ${jsonEncode({'pump': nPump, 'png': nPng, 'open': nOpen, 'rows': rows.length, 'overflow': overflow})}');
    } finally {
      FlutterError.onError = prevOnError;
      t.platformDispatcher.clearLocalesTestValue();
      t.platformDispatcher.clearLocaleTestValue();
      t.platformDispatcher.clearTextScaleFactorTestValue();
      t.view.reset();
    }
  }, skip: !run, timeout: const Timeout(Duration(minutes: 8)));
}
