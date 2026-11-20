// ignore_for_file: depend_on_referenced_packages
// [DU289 일자리 탭 필터 시트(DU-O100 _JobFilterSheet) baseline/after] Codex 한도 중 Claude 자체 진행(허브 DU_self_review_hub_2026-11-10).
//   같은 시험을 교정 전(baseline)·후(after)에 한 번씩 돌린다. 시험은 production 을 편집하지 않는다.
//   DU289_RUN=1 이고 DU289_PHASE 가 baseline 또는 after 일 때만 실행한다(기본 skip).
//   실제 UserJobTab 을 읽기 주입(UserJobTabReads: 장기 공고 3, 한 페이지)으로 띄우고 필터 아이콘(Icons.tune)으로 시트를 연다.
//   장면 A 처음 열기 · B 홈 날짜 진입 D+2(날짜 행 정해짐) · C 홈 날짜 진입 D+40(결과 0, 비활성) · D B 에서 날짜 지우기 누름.
//   조건 W360/1.0·M360/1.5·B320/2.0. 누르는 것: 필터 아이콘, D 의 지우기 '×' 뿐이다(조회 결과는 주입 읽기, 쓰기 없음).
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
import 'package:ALfit/models/core/to_model.dart';
import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/models/core/user_region.dart';
import 'package:ALfit/providers/notification_provider.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/screens/user/tabs/user_job_tab.dart';
import 'package:ALfit/screens/user/tabs/user_job_tab_reads.dart';
import 'package:ALfit/screens/user/user_tab_scope.dart';
import 'package:ALfit/theme/app_colors.dart';
import 'package:ALfit/theme/role_theme.dart';
import 'package:ALfit/utils/format_helper.dart';
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

class _P extends UserProvider {
  @override
  UserModel? get currentUser => UserModel(
        uid: 'u1',
        username: 'u1',
        name: '김근로',
        email: 'u1@alfit.local',
        role: UserRole.USER,
        homeRegion: const UserRegion(province: '서울특별시', city: '강남구'),
        accountStatus: 'active',
      );
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

final DateTime _today = FormatHelper.toKstDate(DateTime.now());
DateTime _day(int o) => _today.add(Duration(days: o));

TOModel _to(String id, String title) => TOModel(
      id: id,
      businessId: 'biz1',
      businessName: '강남 물류센터',
      type: 'contract',
      title: title,
      creatorUID: 'admin1',
      status: TOStatus.active,
      deadlineType: 'NONE',
      hoursBeforeStart: 0,
      workDetails: const [],
      totalRequired: 3,
      totalConfirmed: 0,
      totalPending: 0,
      isPublished: true,
      publishMode: 'immediate',
      rangeStart: _day(1),
      rangeEnd: _day(30),
      createdAt: _day(-5),
      statusUpdatedAt: _day(-5),
    );

UserJobTabReads _reads() => UserJobTabReads(
      publishedTOsPaged: ({String? lastToId, filter}) async => {
        'items': [_to('t1', '물류 분류 장기'), _to('t2', '상품 포장 장기'), _to('t3', '입출고 검수 장기')],
        'lastToId': null,
        'hasMore': false,
      },
      myApplications: (uid) async => const <ApplicationModel>[],
      tosByIds: (ids) async => const <TOModel>[],
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

/// 글자 단위 줄 나눔 — 줄마다 보이는 글자, '낱말 안에서 끊긴' 곳 수(DU286·288 시험과 같은 규칙).
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

double _tpWidth(String text, TextStyle? style, TextScaler scaler, Locale? locale) {
  final tp = TextPainter(text: TextSpan(text: text, style: style), textDirection: TextDirection.ltr, textScaler: scaler, locale: locale)
    ..layout();
  final w = tp.width;
  tp.dispose();
  return w;
}

const _sections = {'즐겨찾기', '근무 유형', '지역', '날짜 범위', '정렬'};
const _chips = {'♥ 즐겨찾기만 보기', '전체', '단기', '장기', '최신순', '마감임박순'};

void main() {
  final phase = Platform.environment['DU289_PHASE'] ?? '';
  final run = Platform.environment['DU289_RUN'] == '1' && (phase == 'baseline' || phase == 'after');
  final after = phase == 'after';
  final nl = String.fromCharCode(10);

  setUp(() => SharedPreferences.setMockInitialValues({}));
  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
    await initializeDateFormatting('ko_KR', null);
  });

  testWidgets('D289 $phase', (t) async {
    await t.runAsync(vqLoadFonts);
    t.platformDispatcher.localesTestValue = const [Locale('ko', 'KR')];
    t.platformDispatcher.localeTestValue = const Locale('ko', 'KR');
    final prevOnError = FlutterError.onError;
    final errors = <String>[];
    FlutterError.onError = (d) => errors.add(d.exceptionAsString().split(nl).first);
    var nPump = 0, nPng = 0, nOpen = 0;
    var cur = '(시작)';
    Never stop(String why) {
      _out('D289-STOP ${jsonEncode({'at': cur, 'why': why, 'errors': errors})}');
      fail('$cur: $why');
    }

    void need(bool ok, String why) {
      if (!ok) stop(why);
    }

    Future<void> frames(int n, [int ms = 50]) async {
      for (var i = 0; i < n; i++) {
        nPump++;
        need(nPump <= 3000 && nPng <= 20 && nOpen <= 20, '사용량 한도');
        await t.pump(Duration(milliseconds: ms));
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
        final screen = Rect.fromLTWH(0, 0, c.w, c.h);
        for (final sc in const ['A', 'B', 'C', 'D']) {
          cur = '${c.id} $sc';
          if (sc == 'D' && c.id != 'W360' && c.id != 'B320') continue;
          nOpen++;
          await t.pumpWidget(const SizedBox.shrink());
          await frames(1);
          safe('비움');
          DateTime? pending = switch (sc) { 'B' || 'D' => _day(2), 'C' => _day(40), _ => null };
          await t.pumpWidget(RepaintBoundary(
            key: key,
            child: MultiProvider(
              providers: [
                ChangeNotifierProvider<UserProvider>(create: (_) => _P()),
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
                home: UserTabScope(
                  switchToTab: (_) {},
                  switchToTabWithDate: (_, __) {},
                  pendingJobDate: pending,
                  clearPendingJobDate: () => pending = null,
                  pendingScheduleMonth: null,
                  clearPendingScheduleMonth: () {},
                  switchToScheduleNow: () {},
                  child: UserJobTab(reads: _reads()),
                ),
              ),
            ),
          ));
          await frames(25, 100);
          safe('탭 띄움');
          final tune = find.byIcon(Icons.tune);
          need(tune.evaluate().length == 1, '필터 아이콘 ${tune.evaluate().length}');
          await t.tap(tune);
          await frames(10);
          safe('시트 열림');
          final sheet = find.byType(BottomSheet);
          need(sheet.evaluate().length == 1, '시트 수 ${sheet.evaluate().length}');

          String? dRow;
          var dPicker = -1;
          if (sc == 'D') {
            final x = find.descendant(of: sheet, matching: find.byIcon(Icons.close));
            need(x.evaluate().length == 1, '지우기 아이콘 ${x.evaluate().length}');
            // [r1] 스크롤 안의 행이면 먼저 보이게 한다(스크롤 없는 교정 전에는 아무 일도 하지 않는다). 그리고 실제로 눌리는 자리인지 본다.
            await t.ensureVisible(x);
            await frames(4);
            need(x.hitTestable().evaluate().isNotEmpty, '지우기가 눌리는 자리가 아니다');
            await t.tap(x);
            await frames(8);
            safe('지우기');
            dPicker = find.byType(BottomSheet).evaluate().length;
            dRow = find.descendant(of: sheet, matching: find.text('전체 날짜')).evaluate().isEmpty ? 'not-cleared' : '전체 날짜';
          }

          final ctxIn = t.element(sheet);
          final scaler = MediaQuery.textScalerOf(ctxIn);
          final loc = Localizations.maybeLocaleOf(ctxIn);
          final sheetR = t.getRect(sheet);
          final texts = <Map<String, Object?>>[];
          final rich = find.descendant(of: sheet, matching: find.byType(RichText), skipOffstage: false).evaluate().where((e) {
            return nearest(e, (w) => w is Icon) == null;
          }).toList()
            ..sort((a, b) => t.getRect(fe(a)).top.compareTo(t.getRect(fe(b)).top));
          for (final e in rich) {
            final rp = t.renderObject<RenderParagraph>(fe(e));
            final raw = rp.text.toPlainText();
            final plain = TextLayout.plain(raw);
            final st = rp.text.style;
            final fg = st?.color;
            final bg = bgOf(e);
            final r = t.getRect(fe(e));
            final li = _lineInfo(rp);
            final avail = rp.constraints.maxWidth;
            var maxTok = 0.0;
            for (final tok in plain.split(RegExp('[ $nl]+'))) {
              if (tok.isEmpty) continue;
              maxTok = math.max(maxTok, _tpWidth(tok, st, scaler, loc));
            }
            final kind = _sections.contains(plain)
                ? 'section'
                : _chips.contains(plain)
                    ? 'chip'
                    : plain == '초기화'
                        ? 'reset'
                        : plain == '필터'
                            ? 'title'
                            : (plain.startsWith('전체 ') || plain.contains(' ~ '))
                                ? 'row'
                                : (nearest(e, (w) => w is ElevatedButton) != null ? 'apply' : 'other');
            // 누름 상자
            Rect? box;
            final gd = kind == 'chip' ? nearest(e, (w) => w is GestureDetector) : null;
            final tb = kind == 'reset' ? nearest(e, (w) => w is TextButton) : null;
            final iw = kind == 'row' ? nearest(e, (w) => w is InkWell) : null;
            final eb = kind == 'apply' ? nearest(e, (w) => w is ElevatedButton) : null;
            final hitEl = gd ?? tb ?? iw;
            if (hitEl != null) box = t.getRect(fe(hitEl));
            Rect? visBox;
            if (eb != null) {
              box = t.getRect(fe(eb));
              final m = find.descendant(of: fe(eb), matching: find.byType(Material)).evaluate();
              if (m.isNotEmpty) visBox = t.getRect(fe(m.first));
            }
            texts.add({
              'text': plain, 'kind': kind, 'rect': lt(r), 'visible': r.top >= -0.5 && r.bottom <= c.h + 0.5,
              'fontSize': st?.fontSize, 'weight': st?.fontWeight?.value,
              'fg': fg == null ? null : _hex(fg), 'bg': _hex(bg), 'white': fg?.toARGB32() == Colors.white.toARGB32(),
              'contrast': fg == null ? null : r2(_contrast(fg, bg)),
              'lines': li.lines, 'sylBreaks': li.sylBreaks, 'avail': avail.isFinite ? r1(avail) : -1, 'maxTok': r1(maxTok),
              'longToken': avail.isFinite && maxTok > avail + 0.5,
              'didExceedMaxLines': rp.didExceedMaxLines,
              if (box != null) 'box': lt(box),
              if (box != null) 'boxH': r1(box.height),
              if (visBox != null) 'visH': r1(visBox.height),
              if (kind == 'apply') 'dataRaw': (t.widget<Text>(find.descendant(of: fe(eb!), matching: find.byType(Text)).first)).data,
            });
          }
          // 아이콘(꺾쇠·지우기)
          final icons = <Map<String, Object?>>[];
          for (final ic in const [Icons.chevron_right, Icons.close]) {
            for (final e in find.descendant(of: sheet, matching: find.byIcon(ic), skipOffstage: false).evaluate()) {
              final w = e.widget as Icon;
              final bg = bgOf(e);
              final ib = nearest(e, (w) => w is IconButton);
              final gd = nearest(e, (w) => w is GestureDetector);
              final hit = ib ?? gd;
              icons.add({
                'icon': ic == Icons.close ? 'close' : 'chevron', 'size': w.size, 'fg': w.color == null ? null : _hex(w.color!), 'bg': _hex(bg),
                'contrast': w.color == null ? null : r2(_contrast(w.color!, bg)),
                'hit': hit == null ? null : lt(t.getRect(fe(hit))), 'hitW': hit == null ? null : r1(t.getRect(fe(hit)).width),
                'hitH': hit == null ? null : r1(t.getRect(fe(hit)).height), 'hitKind': ib != null ? 'IconButton' : (gd != null ? 'GestureDetector' : null),
              });
            }
          }
          final applyF = find.descendant(of: sheet, matching: find.byType(ElevatedButton));
          final nApply = applyF.evaluate().length;
          final applyR = nApply == 1 ? t.getRect(applyF) : Rect.zero;
          final applyHit = nApply == 1 && find.descendant(of: sheet, matching: find.byType(ElevatedButton)).hitTestable().evaluate().isNotEmpty;
          final applyEnabled = nApply == 1 && t.widget<ElevatedButton>(applyF).onPressed != null;
          final sel = texts.where((x) => x['kind'] == 'chip' && x['white'] == true).map((x) => x['text']).toList();

          final row = {
            'phase': phase, 'cond': c.id, 'scene': sc, 'sheetRect': lt(sheetR), 'nApply': nApply, 'applyRect': lt(applyR),
            'applyOnScreen': applyR.top >= screen.top - 0.5 && applyR.bottom <= screen.bottom + 0.5, 'applyHit': applyHit,
            'applyEnabled': applyEnabled, 'selectedWhite': sel, 'dRow': dRow, 'dSheets': dPicker,
            'overflowSoFar': overflow.length, 'texts': texts, 'icons': icons,
          };

          if (after) {
            need(nApply == 1, '적용 버튼 수 $nApply');
            need(row['applyOnScreen'] == true && applyHit, '적용 버튼이 첫 화면 밖/누를 수 없음 ${lt(applyR)}');
            for (final x in texts) {
              final at = '${x['kind']} ${x['text']}';
              final cst = x['contrast'];
              need(x['didExceedMaxLines'] != true, '$at 말줄임 $x');
              if (x['longToken'] != true) need(x['sylBreaks'] == 0, '$at 음절 끊김 $x');
              switch (x['kind']) {
                case 'section':
                  need(x['fontSize'] == 16 && x['weight'] == 700 && x['fg'] == _hex(AppColors.textPrimary), '$at 구역 제목 $x');
                case 'chip':
                  need(((x['boxH'] as double?) ?? 0) >= 48, '$at 칩 누름 높이 $x');
                  if (x['white'] != true) need(x['fg'] == _hex(AppColors.textSecondary) && cst is double && cst >= 4.5, '$at 비선택 칩 글 $x');
                case 'reset':
                  need(x['fg'] == _hex(AppColors.textSecondary) && cst is double && cst >= 4.5, '$at 초기화 글 $x');
                  need(((x['boxH'] as double?) ?? 0) >= 48, '$at 초기화 누름 높이 $x');
                case 'row':
                  need(((x['boxH'] as double?) ?? 0) >= 52, '$at 행 높이 $x');
                  need(cst is double && cst >= 4.5, '$at 행 글 대비 $x');
                case 'apply':
                  need(((x['visH'] as double?) ?? 0) >= 52, '$at 적용 버튼 높이 $x');
                  need(cst is double && cst >= 4.5, '$at 적용 버튼 글 대비 $x');
              }
            }
            for (final i in icons) {
              if (i['icon'] == 'chevron') {
                need(i['fg'] == _hex(AppColors.textTertiary) && (i['contrast'] as double) >= 3, '꺾쇠 $i');
              } else {
                need(i['hitKind'] == 'IconButton' && (i['hitW'] as double) >= 48 && (i['hitH'] as double) >= 48, '지우기 누름 $i');
                need(i['fg'] == _hex(AppColors.textSecondary), '지우기 색 $i');
              }
            }
            // 계약
            final ap = texts.where((x) => x['kind'] == 'apply').toList();
            need(ap.length == 1, '적용 버튼 글 수 ${ap.length}');
            final label = ap.first['dataRaw'];
            final want = switch (sc) { 'C' => '조건에 맞는 공고 없음', _ => '3개 일자리 보기' };
            need(label == want, '적용 버튼 Text.data $label != $want');
            need(applyEnabled == (sc != 'C'), '적용 버튼 활성 $applyEnabled');
            need(sel.length == 2 && sel.contains('전체') && sel.contains('최신순'), '선택 칩(흰 글) $sel');
            final rowsTxt = texts.where((x) => x['kind'] == 'row').map((x) => x['text']).toList();
            final dKey = '${_day(sc == 'C' ? 40 : 2).month}/${_day(sc == 'C' ? 40 : 2).day}';
            final wantDate = (sc == 'A' || sc == 'D') ? '전체 날짜' : '$dKey ~ $dKey';
            need(rowsTxt.contains('전체 지역') && rowsTxt.contains(wantDate), '행 글 $rowsTxt');
            if (sc == 'D') need(dRow == '전체 날짜' && dPicker == 1, '지우기 결과 $dRow 시트 수 $dPicker');
          }

          final shot = sc != 'D' || c.id == 'W360';
          if (shot) {
            nPng++;
            await vqCapture(t, key, 'D289-$phase-${c.id}_$sc', conditions: {
              'phase': phase, 'scene': sc, 'viewport': '${c.w.toInt()}x${c.h.toInt()}', 'textScaleFactor(기기)': c.s,
              'pendingJobDate': pending == null ? null : FormatHelper.toKstDateKey(pending!),
            });
          }
          rows.add(row..['shot'] = shot);
          _out('D289 ${jsonEncode(rows.last)}');
        }
      }
      if (after) {
        need(rows.length == 3 * 3 + 2, '장면 수 ${rows.length}');
        need(overflow.isEmpty, 'overflow $overflow');
      }
      await t.pumpWidget(const SizedBox.shrink());
      await frames(2);
      safe('END 전');
      _out('D289-END ${jsonEncode({'pump': nPump, 'png': nPng, 'open': nOpen, 'rows': rows.length, 'overflow': overflow})}');
    } finally {
      FlutterError.onError = prevOnError;
      t.platformDispatcher.clearLocalesTestValue();
      t.platformDispatcher.clearLocaleTestValue();
      t.platformDispatcher.clearTextScaleFactorTestValue();
      t.view.reset();
    }
  }, skip: !run, timeout: const Timeout(Duration(minutes: 8)));
}
