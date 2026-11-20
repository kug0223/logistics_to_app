// ignore_for_file: depend_on_referenced_packages
// [DU301 출퇴근 빠른 시각 시트(DU-O037) 표시 교정 baseline/after] 감사300 §다음301.
//   같은 시험을 교정 전(baseline)·후(after)에 한 번씩 돌린다. 시험은 production 을 편집하지 않는다.
//   DU301_RUN=1 이고 DU301_PHASE 가 baseline 또는 after 일 때만 실행한다(기본 skip).
//   작은 독립 host 의 '열기' 버튼으로 공개 AttendanceQuickTimeSheet.show 를 실제로 열고 반환 Future 를 관측한다.
//   표본 IN1·IN2·OUT1·NUL × W360/1.0·B320/2.0. 행동은 실제 tap(열기 포함 최대 4)·실제 drag 다. Navigator.pop 직접 호출 없음.
//   baseline 의 사전 예외는 원본 Column 세로 RenderFlex overflow 와 그로 인한 비도달(UNREACHABLE_BASELINE)뿐이다.
// [DU302 감사301 §다음302] 같은 파일을 재사용한다. 단계: diag(원본 B320_IN1 열기 1 — 오류 원문·소유 위치 귀속) ·
//   baseline(B320 4표본만, 원본 ±10 두 Row 우측 0.150px 와 본체 Column 세로 overflow 만 소유 위치로 허용) · after(8조건, overflow 0).
//   최소치 판정은 반올림 전 기하로 하고, 주요 글은 실제 clip(화면·시트 카드·스크롤 창) 안 전문 가시를 따로 본다.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show DiagnosticsTreeStyle, TextTreeRenderer, shortHash;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ALfit/theme/app_colors.dart';
import 'package:ALfit/theme/role_theme.dart';
import 'package:ALfit/utils/responsive_helper.dart';
import 'package:ALfit/utils/text_layout.dart';
import 'package:ALfit/widgets/pickers/attendance_quick_time_sheet.dart';

import 'support/du1_vq_capture.dart';

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

/// 네트워크 접근 guard(HttpClient 생성 계수). reader/writer 전용 guard 가 아니다.
class _NoNet extends HttpOverrides {
  int created = 0;
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    created++;
    throw StateError('DU301 network guard');
  }
}

String _hm(int m) {
  final t = ((m % 1440) + 1440) % 1440;
  return '${(t ~/ 60).toString().padLeft(2, '0')}:${(t % 60).toString().padLeft(2, '0')}';
}

int _min(String hm) {
  final p = hm.split(':');
  return int.parse(p[0]) * 60 + int.parse(p[1]);
}

const _host = 'DU301-HOST';
const _samples = [
  (id: 'IN1', checkIn: true, title: '일괄 출근 (1명)', times: <String>['23:50'], pick: '예정  23:50', delta: 10, finalAct: 'confirm', expect: '00:00'),
  (id: 'IN2', checkIn: true, title: '홀서빙 및 매장 정리 출근 시간', times: <String>['18:00', '09:00', '09:00'], pick: '예정  09:00', delta: 10, finalAct: 'confirm', expect: '09:10'),
  (id: 'OUT1', checkIn: false, title: '일괄 퇴근 (1명)', times: <String>['00:00'], pick: '예정  00:00', delta: -10, finalAct: 'confirm', expect: '23:50'),
  (id: 'NUL', checkIn: true, title: '일괄 출근 (1명)', times: null, pick: '현재', delta: 10, finalAct: 'cancelOrX', expect: null),
];

void main() {
  final phase = Platform.environment['DU301_PHASE'] ?? '';
  final run = Platform.environment['DU301_RUN'] == '1' && (phase == 'diag' || phase == 'baseline' || phase == 'after');
  final after = phase == 'after';
  final diag = phase == 'diag';
  // 단계별 한도(감사301 §D 표): open·mount·pump+mount·tap·drag·PNG
  final lim = diag
      ? (open: 1, mount: 3, pm: 50, tap: 1, drag: 0, png: 0)
      : after
          ? (open: 8, mount: 24, pm: 800, tap: 32, drag: 16, png: 12)
          : (open: 4, mount: 12, pm: 400, tap: 16, drag: 16, png: 8);
  // 원본 소스의 소유 위치(진단으로 확인한 뒤에만 baseline 예외로 쓴다): ±10 Row 281·335, 본체 Column 147
  const rightOwners = {281, 335};
  const bottomOwner = 147;
  final nl = String.fromCharCode(10);

  testWidgets('D301 $phase', (t) async {
    await t.runAsync(vqLoadFonts);
    final sem = t.ensureSemantics();
    t.platformDispatcher.localesTestValue = const [Locale('ko', 'KR')];
    t.platformDispatcher.localeTestValue = const Locale('ko', 'KR');
    final prevOnError = FlutterError.onError;
    final prevHttp = HttpOverrides.current;
    final net = _NoNet();
    HttpOverrides.global = net;
    // 오류는 첫 줄과 원문 전체(정보 수집·creator·RenderFlex 서술 포함)를 함께 남긴다.
    final errors = <({String first, String full})>[];
    FlutterError.onError = (d) => errors.add((
          first: d.exceptionAsString().split(nl).first,
          full: TextTreeRenderer(wrapWidth: 400).render(d.toDiagnosticsNode(style: DiagnosticsTreeStyle.error)).trimRight(),
        ));
    var nPump = 0, nMount = 0, nPng = 0, nTap = 0, nDrag = 0, nOpen = 0;
    var cur = '(시작)';
    final baselineOverflow = <String>[];
    Map<String, Object?>? lastReach; // [DU302 r3] 마지막 도달 시도 상태(STOP·FINAL 에 남긴다)
    var reachAttempts = 0;
    Map<String, Object?> counts() =>
        {'phase': phase, 'pump': nPump, 'mount': nMount, 'pumpMount': nPump + nMount, 'png': nPng, 'tap': nTap, 'drag': nDrag, 'open': nOpen};
    Never stop(String why) {
      _out('D301-STOP ${jsonEncode({'at': cur, 'why': why, 'errors': errors.map((e) => e.first).toList(), 'counts': counts(), 'reachAttempts': reachAttempts, 'lastReach': lastReach})}');
      for (final e in errors) {
        _out('D301-STOPERR ${jsonEncode({'at': cur, 'full': e.full})}');
      }
      fail('$cur: $why');
    }

    void need(bool ok, String why) {
      if (!ok) stop(why);
    }

    void budget() => need(
        nPump + nMount <= lim.pm && nMount <= lim.mount && nPng <= lim.png && nTap <= lim.tap && nDrag <= lim.drag && nOpen <= lim.open,
        '한도 ${counts()}');

    // 넘침 오류 귀속: 방향·값·소스 줄(위젯 생성 위치)·RenderFlex 해시
    ({String? dir, String? val, int? line, String? hash}) owner(({String first, String full}) e) {
      final m = RegExp(r'^A RenderFlex overflowed by ([0-9.]+) pixels on the (right|bottom|left|top)\.$').firstMatch(e.first);
      final loc = RegExp(r'attendance_quick_time_sheet\.dart:(\d+):\d+').firstMatch(e.full);
      final h = RegExp(r'RenderFlex#([0-9a-f]{5})').firstMatch(e.full);
      return (dir: m?.group(2), val: m?.group(1), line: loc == null ? null : int.parse(loc.group(1)!), hash: h?.group(1));
    }

    Future<void> frames(int n) async {
      for (var i = 0; i < n; i++) {
        nPump++;
        budget();
        await t.pump(const Duration(milliseconds: 50));
      }
    }

    Future<void> mount(Widget w) async {
      nMount++;
      budget();
      await t.pumpWidget(w);
    }

    // baseline 사전 예외(DU302): 원본 ±10 두 Row(소스 281·335) 우측 0.150px — 행동 프레임당 최대 2건,
    //   원본 본체 Column(소스 147) 세로 overflow. 소유 위치·방향·값이 다르면 즉시 중단. after 는 예외 0.
    void safe(String at) {
      final ex = t.takeException();
      need(ex == null, '$at 예외: $ex');
      var rightThisFrame = 0;
      for (final e in errors) {
        final o = owner(e);
        final okRight = phase == 'baseline' && o.dir == 'right' && o.val == '0.150' && rightOwners.contains(o.line);
        final okBottom = phase == 'baseline' && o.dir == 'bottom' && o.line == bottomOwner;
        if (okRight) {
          rightThisFrame++;
          need(rightThisFrame <= 2, '$at 우측 0.150 프레임당 2건 초과');
        }
        if (okRight || okBottom) {
          baselineOverflow.add('$cur $at ${e.first} owner:${o.line} #${o.hash}');
          _out('D301-BASEERR ${jsonEncode({'at': '$cur $at', 'dir': o.dir, 'val': o.val, 'line': o.line, 'hash': o.hash, 'full': e.full})}');
        } else {
          stop('$at 예외/overflow: ${e.first} owner:${o.line} #${o.hash}');
        }
      }
      errors.clear();
    }

    double r1(double v) => double.parse(v.toStringAsFixed(1));
    double r2(double v) => double.parse(v.toStringAsFixed(2));
    List<double> lt(Rect r) => [r.left, r.top, r.right, r.bottom].map(r1).toList();
    Finder fe(Element e) => find.byElementPredicate((x) => identical(x, e), skipOffstage: false);
    bool inside(Rect a, Rect b) => a.left >= b.left - 0.5 && a.top >= b.top - 0.5 && a.right <= b.right + 0.5 && a.bottom <= b.bottom + 0.5;

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

    Color? boxColorOf(Element e) {
      final el = nearest(e, (w) => w is DecoratedBox && w.decoration is BoxDecoration &&
          ((w.decoration as BoxDecoration).color != null || (w.decoration as BoxDecoration).gradient != null));
      if (el == null) return null;
      final d = (el.widget as DecoratedBox).decoration as BoxDecoration;
      final c = d.color ?? (d.gradient is LinearGradient ? (d.gradient as LinearGradient).colors.first : null);
      return c == null ? null : Color.alphaBlend(c, Colors.white);
    }

    final key = GlobalKey();
    final openKey = GlobalKey();
    final brand = AppColors.brand;
    final rows = <Map<String, Object?>>[];
    final visited = <String>[];
    try {
      const allConds = [
        (id: 'W360', w: 360.0, h: 780.0, s: 1.0),
        (id: 'B320', w: 320.0, h: 640.0, s: 2.0),
      ];
      // diag·baseline 은 B320 만(W360 before 4 는 DU301 baseline-r1 재사용), after 는 8조건
      final conds = after ? allConds : allConds.where((x) => x.id == 'B320').toList();
      for (final c in conds) {
        for (final s in diag ? _samples.where((x) => x.id == 'IN1').toList() : _samples) {
          cur = '${c.id}_${s.id}';
          t.view.physicalSize = Size(c.w, c.h);
          t.view.devicePixelRatio = 1.0;
          t.platformDispatcher.textScaleFactorTestValue = c.s;
          final screen = Rect.fromLTWH(0, 0, c.w, c.h);
          var done = 0;
          String? result;
          var gotResult = false;
          await mount(RepaintBoundary(
            key: key,
            child: MaterialApp(
              key: ValueKey('D301-$cur'), // 표본마다 새 Navigator(앞 표본 상태가 섞이지 않게)
              debugShowCheckedModeBanner: false,
              theme: RoleTheme.businessAdminTheme,
              localizationsDelegates: const [
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              supportedLocales: const [Locale('ko', 'KR')],
              home: Scaffold(body: Builder(builder: (ctx) {
                return Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    const Text(_host),
                    ElevatedButton(
                      key: openKey,
                      onPressed: () {
                        nOpen++;
                        AttendanceQuickTimeSheet.show(context: ctx, title: s.title, scheduledTimes: s.times, isCheckIn: s.checkIn).then((v) {
                          done++;
                          result = v;
                          gotResult = true;
                        });
                      },
                      child: const Text('열기'),
                    ),
                  ]),
                );
              })),
            ),
          ));
          await frames(2);
          safe('host');
          nTap++;
          budget();
          await t.tap(find.byKey(openKey));
          await frames(10);
          if (diag) {
            // ── 진단(DU302 D): 열림 프레임의 오류 묶음 원문과 후보 RenderFlex 기하. 더 진행하지 않는다 ──
            final sheetD = find.byType(BottomSheet);
            need(sheetD.evaluate().length == 1, '진단 시트 수 ${sheetD.evaluate().length}');
            Map<String, Object?> flexInfo(RenderFlex rf) {
              final kids = <double>[];
              var ch = rf.firstChild;
              while (ch != null) {
                kids.add(rf.direction == Axis.horizontal ? ch.size.width : ch.size.height);
                ch = rf.childAfter(ch);
              }
              final mainExt = rf.direction == Axis.horizontal ? rf.size.width : rf.size.height;
              final sum = kids.fold<double>(0, (a, b) => a + b);
              return {'hash': shortHash(rf), 'dir': rf.direction.name, 'constraints': rf.constraints.toString(), 'size': rf.size.toString(),
                'kids': kids, 'sum': sum, 'main': mainExt, 'over': sum - mainExt, 'creator': rf.debugCreator?.toString()};
            }

            RenderFlex flexIn(IconData icon) {
              final ink = find.descendant(of: sheetD, matching: find.byType(InkWell)).evaluate()
                  .firstWhere((e) => find.descendant(of: fe(e), matching: find.byIcon(icon)).evaluate().isNotEmpty);
              return t.renderObject<RenderFlex>(find.descendant(of: fe(ink), matching: find.byType(Row)).first);
            }

            final minusRf = flexIn(Icons.remove);
            final plusRf = flexIn(Icons.add);
            final bodyRf = t.renderObject<RenderFlex>(find.ancestor(of: find.text('빠른 선택'), matching: find.byType(Column)).first);
            final overflowing = <Map<String, Object?>>[];
            for (final e in find.descendant(of: sheetD, matching: find.byWidgetPredicate((w) => w is Flex)).evaluate()) {
              final info = flexInfo(e.renderObject as RenderFlex);
              if ((info['over'] as double) > 0.0001) overflowing.add(info);
            }
            final errs = <Map<String, Object?>>[];
            for (final e in errors) {
              final o = owner(e);
              errs.add({'first': e.first, 'dir': o.dir, 'val': o.val, 'line': o.line, 'hash': o.hash, 'full': e.full});
            }
            final exD = t.takeException();
            _out('D301-DIAG ${jsonEncode({'cond': c.id, 'sample': s.id, 'exception': exD?.toString(), 'errors': errs, 'minus': flexInfo(minusRf),
              'plus': flexInfo(plusRf), 'body': flexInfo(bodyRf), 'overflowingFlex': overflowing, 'counts': counts()})}');
            // 잇는 조건: 우측 0.150 두 건 = 원본 ±10 두 Row(281·335, 해시 일치), 하단 한 건 = 본체 Column(147, 해시 일치), 다른 예외 0
            final rights = errs.where((x) => x['dir'] == 'right').toList();
            final bottoms = errs.where((x) => x['dir'] == 'bottom').toList();
            need(exD == null && errs.length == 3 && rights.length == 2 && bottoms.length == 1, '진단 오류 구성 ${errs.map((x) => x['first']).toList()}');
            need(rights.every((x) => x['val'] == '0.150') &&
                rights.map((x) => x['line']).toSet().containsAll(rightOwners) &&
                rights.map((x) => x['hash']).toSet().containsAll({shortHash(minusRf), shortHash(plusRf)}), '진단 우측 소유 불일치');
            need(bottoms.first['line'] == bottomOwner && bottoms.first['hash'] == shortHash(bodyRf), '진단 하단 소유 불일치');
            errors.clear();
            visited.add(cur);
            await mount(const SizedBox.shrink());
            await frames(2);
            final exT = t.takeException();
            need(exT == null && errors.isEmpty, '진단 teardown 예외 $exT ${errors.map((e) => e.first).toList()}');
            continue;
          }
          safe('열림');
          final sheet = find.byType(BottomSheet);
          need(sheet.evaluate().length == 1, '시트 수 ${sheet.evaluate().length}');
          final card = find.descendant(of: sheet, matching: find.byType(Material)).first;
          final cardRect = t.getRect(card);
          final ctxIn = t.element(sheet);
          final scroll = find.descendant(of: sheet, matching: find.byType(SingleChildScrollView));
          final hasScroll = scroll.evaluate().isNotEmpty;

          // ── 필수 요소 찾기 ──
          Finder textF(bool Function(String p) p) => find.descendant(
              of: sheet, matching: find.byWidgetPredicate((w) => w is RichText && p(TextLayout.plain(w.text.toPlainText()))));
          Finder inkWithText(bool Function(String p) p) {
            final els = find.descendant(of: sheet, matching: find.byType(InkWell)).evaluate().where((e) => find
                .descendant(of: fe(e), matching: find.byWidgetPredicate((w) => w is RichText && p(TextLayout.plain(w.text.toPlainText()))))
                .evaluate()
                .isNotEmpty).toList();
            return find.byElementPredicate((x) => els.contains(x), skipOffstage: false);
          }
          final titleF = textF((p) => p == s.title);
          final schedChips = inkWithText((p) => p.startsWith('예정'));
          final nowChips = inkWithText((p) => p.startsWith('현재'));
          final minus = find.descendant(of: sheet, matching: find.byWidgetPredicate((w) => w is InkWell))
              .evaluate().where((e) => find.descendant(of: fe(e), matching: find.byIcon(Icons.remove)).evaluate().isNotEmpty).toList();
          final plus = find.descendant(of: sheet, matching: find.byWidgetPredicate((w) => w is InkWell))
              .evaluate().where((e) => find.descendant(of: fe(e), matching: find.byIcon(Icons.add)).evaluate().isNotEmpty).toList();
          final cancelF = find.descendant(of: sheet, matching: find.widgetWithText(OutlinedButton, '취소'));
          final ctaF = find.descendant(of: sheet, matching: find.byType(ElevatedButton));
          final closeF = find.descendant(of: sheet, matching: find.widgetWithIcon(IconButton, Icons.close));
          final schedLabels = [
            for (final e in schedChips.evaluate())
              TextLayout.plain((find.descendant(of: fe(e), matching: find.byType(RichText)).evaluate().first.widget as RichText).text.toPlainText())
          ];
          final expectSched = s.times == null ? 0 : s.times!.toSet().length;
          need(titleF.evaluate().length == 1, '제목 수 ${titleF.evaluate().length}');
          need(schedChips.evaluate().length == expectSched && nowChips.evaluate().length == 1, '칩 수 예정 ${schedChips.evaluate().length} 현재 ${nowChips.evaluate().length}');
          if (s.id == 'IN2') need(schedLabels.join('|') == '예정  09:00|예정  18:00', 'IN2 예정 정렬·중복제거 $schedLabels');
          need(minus.length == 1 && plus.length == 1, '±10 수 ${minus.length}/${plus.length}');
          need(cancelF.evaluate().length == 1 && ctaF.evaluate().length == 1 && closeF.evaluate().length == 1,
              '취소/확정/X 수 ${cancelF.evaluate().length}/${ctaF.evaluate().length}/${closeF.evaluate().length}');

          // 화면에 보이고 누를 수 있는가(스크롤이 있으면 실제 drag 로 보이게 한다).
          Rect? viewport() => hasScroll ? t.getRect(find.descendant(of: scroll, matching: find.byType(Scrollable)).first) : null;
          bool visibleNow(Finder f) {
            if (f.evaluate().isEmpty) return false;
            final r = t.getRect(f);
            final vp = viewport();
            final inScroll = hasScroll && find.ancestor(of: f, matching: find.byWidget(scroll.evaluate().first.widget)).evaluate().isNotEmpty;
            return inside(r, screen) && inside(r, cardRect) && (!inScroll || vp == null || inside(r, vp)) && f.hitTestable().evaluate().isNotEmpty;
          }

          // [DU302 r3] 실제 drag 계약: 시작 이동 kDragSlopDefault(20)는 내용 이동이 아니다 → 필요한 거리 d 에 slop+16 을 더한다.
          //   시도마다 대상·화면·카드·창 rect, 포함 여부, 중심 hit, 예정 dy, 실제 pixels 변화, extent 를 남긴다(D301-REACH).
          Map<String, Object?> scrollState() {
            if (!hasScroll) return {'scroll': false};
            final pos = t.state<ScrollableState>(find.descendant(of: scroll, matching: find.byType(Scrollable)).first).position;
            return {'pixels': pos.pixels, 'min': pos.minScrollExtent, 'max': pos.maxScrollExtent, 'vpDim': pos.viewportDimension};
          }

          Map<String, Object?> judge(Finder f) {
            if (f.evaluate().isEmpty) return {'present': false};
            final r = t.getRect(f);
            final vp = viewport();
            final inScroll = hasScroll && find.ancestor(of: f, matching: find.byWidget(scroll.evaluate().first.widget)).evaluate().isNotEmpty;
            final inScreen = inside(r, screen), inCard = inside(r, cardRect), inVp = !inScroll || vp == null || inside(r, vp);
            final hit = f.hitTestable().evaluate().isNotEmpty;
            return {'present': true, 'rect': [r.left, r.top, r.right, r.bottom], 'vp': vp == null ? null : [vp.left, vp.top, vp.right, vp.bottom],
              'card': [cardRect.left, cardRect.top, cardRect.right, cardRect.bottom], 'inScroll': inScroll, 'inScreen': inScreen, 'inCard': inCard,
              'inVp': inVp, 'hit': hit, 'ok': inScreen && inCard && inVp && hit, 'taller': vp != null && r.height > vp.height + 0.5};
          }

          Future<bool> reach(Finder f, String target) async {
            Map<String, Object?> last = {};
            for (var i = 0; i < 3; i++) {
              final j = judge(f);
              if (j['ok'] == true) {
                lastReach = {'at': cur, 'target': target, 'attempt': i, 'result': 'ok', ...j, ...scrollState()};
                if (i > 0) _out('D301-REACH ${jsonEncode(lastReach)}');
                return true;
              }
              if (!hasScroll || j['present'] != true) break;
              final vp = viewport()!;
              final r = t.getRect(f);
              final down = r.bottom > vp.bottom;
              final d = down ? r.bottom - vp.bottom : vp.top - r.top;
              final dy = down ? -(d + kDragSlopDefault + 16) : (d + kDragSlopDefault + 16);
              final before = scrollState();
              nDrag++;
              reachAttempts++;
              budget();
              await t.drag(scroll, Offset(0, dy));
              await frames(3);
              safe('drag');
              final afterS = scrollState();
              final moved = ((afterS['pixels'] as double?) ?? 0) - ((before['pixels'] as double?) ?? 0);
              last = {'at': cur, 'target': target, 'attempt': i + 1, 'judgeBefore': j, 'd': d, 'dy': dy, 'scrollBefore': before, 'scrollAfter': afterS, 'moved': moved};
              lastReach = last;
              _out('D301-REACH ${jsonEncode(last)}');
            }
            final jf = judge(f);
            final sf = scrollState();
            String reason = 'ok';
            if (jf['ok'] != true) {
              final atEnd = sf['pixels'] is double && sf['max'] is double && (sf['pixels'] as double) >= (sf['max'] as double) - 0.5;
              reason = jf['present'] != true
                  ? 'absent'
                  : jf['taller'] == true
                      ? 'target>viewport'
                      : (jf['inScreen'] == true && jf['inCard'] == true && jf['inVp'] == true)
                          ? 'bounds-ok-hit-fail'
                          : atEnd
                              ? 'end-extent'
                              : (last['moved'] is double && ((last['moved'] as double).abs() < 0.01))
                                  ? 'no-move'
                                  : 'not-reached';
            }
            lastReach = {'at': cur, 'target': target, 'final': true, 'reason': reason, ...jf, ...sf};
            if (jf['ok'] != true || reachAttempts > 0) _out('D301-REACH ${jsonEncode(lastReach)}');
            return jf['ok'] == true;
          }

          // [DU302 r3] receiver 는 그 대상이 실제 도달한 프레임에서 잰다(판정은 반올림 전 기하)
          Map<String, Object?> recvNow(Finder f) {
            if (f.evaluate().isEmpty) return {'n': 0};
            final r = t.getRect(f);
            final j = judge(f);
            return {'w': r1(r.width), 'h': r1(r.height), 'wRaw': r.width, 'hRaw': r.height, 'hit': j['hit'] == true, 'visible': j['ok'] == true};
          }

          // 큰 숫자: 선택 시각과 같은 글 중 가장 큰 글자
          Map<String, Object?> bigNumber() {
            final es = find.descendant(of: sheet, matching: find.byType(RichText)).evaluate().where((e) =>
                RegExp(r'^[0-9]{2}:[0-9]{2}$').hasMatch(TextLayout.plain((e.widget as RichText).text.toPlainText()))).toList();
            es.sort((a, b) => ((b.widget as RichText).text.style?.fontSize ?? 0).compareTo((a.widget as RichText).text.style?.fontSize ?? 0));
            if (es.isEmpty) return {'n': 0};
            final rt = es.first.widget as RichText;
            final fg = rt.text.style?.color;
            final bg = boxColorOf(es.first);
            return {'n': es.length, 'text': TextLayout.plain(rt.text.toPlainText()), 'fs': r1(rt.text.style?.fontSize ?? 0), 'fg': fg == null ? null : _hex(fg),
              'bg': bg == null ? null : _hex(bg), 'contrast': (fg == null || bg == null) ? null : r2(_contrast(fg, bg))};
          }

          final row = <String, Object?>{'phase': phase, 'cond': c.id, 'sample': s.id, 'hasScroll': hasScroll, 'card': lt(cardRect), 'sched': schedLabels};
          final steps = <String>[];
          var unreachable = false;

          // 머리 아이콘
          final headIcon = find.descendant(of: sheet, matching: find.byWidgetPredicate((w) => w is Icon && (w.icon == Icons.login || w.icon == Icons.logout)));
          need(headIcon.evaluate().length == 1, '머리 아이콘 수');
          final hiColor = (headIcon.evaluate().first.widget as Icon).color;
          final hiBg = boxColorOf(headIcon.evaluate().first);
          row['headIcon'] = {'fg': hiColor == null ? null : _hex(hiColor), 'bg': hiBg == null ? null : _hex(hiBg),
            'contrast': (hiColor == null || hiBg == null) ? null : r2(_contrast(hiColor, hiBg))};
          // 제목 글자 크기·말줄임
          final titleRp = t.renderObject<RenderParagraph>(titleF);
          row['title'] = {'fs': r1(titleRp.text.style?.fontSize ?? 0), 'fsExpect': r1(ResponsiveHelper.subtitleStyle(ctxIn).fontSize ?? 0),
            'lines': titleRp.getBoxesForSelection(TextSelection(baseOffset: 0, extentOffset: titleRp.text.toPlainText().length)).map((b) => b.top.round()).toSet().length,
            'ellipsis': titleRp.didExceedMaxLines, 'semTree': find.bySemanticsLabel(s.title).evaluate().length};
          // 확정 버튼(하단 고정 여부는 열린 직후 도달로 본다)
          row['ctaReachAtOpen'] = visibleNow(ctaF);
          // [DU302] 주요 글의 실제 clip(화면·시트 카드·스크롤 창) 안 전문 가시 — didExceedMaxLines 와 따로 본다
          bool textVisible(Finder f) {
            if (f.evaluate().isEmpty) return false;
            final r = t.getRect(f);
            final vp = viewport();
            final inScroll = hasScroll && find.ancestor(of: f, matching: find.byWidget(scroll.evaluate().first.widget)).evaluate().isNotEmpty;
            return inside(r, screen) && inside(r, cardRect) && (!inScroll || vp == null || inside(r, vp));
          }

          final bigEls = find.descendant(of: sheet, matching: find.byType(RichText)).evaluate().where((e) =>
              RegExp(r'^[0-9]{2}:[0-9]{2}$').hasMatch(TextLayout.plain((e.widget as RichText).text.toPlainText()))).toList()
            ..sort((a, b) => ((b.widget as RichText).text.style?.fontSize ?? 0).compareTo((a.widget as RichText).text.style?.fontSize ?? 0));
          row['visAtOpen'] = {
            'title': textVisible(titleF),
            'big': bigEls.isNotEmpty && textVisible(fe(bigEls.first)),
            'ctaLabel': textVisible(find.descendant(of: ctaF, matching: find.byType(RichText))),
          };
          // [DU302 r3] 고정 행동(취소·X·확정)은 열린 직후 프레임에서, 칩은 각 칩이 실제 도달한 프레임에서 잰다
          final recvFixed = {'cancel': recvNow(cancelF), 'close': recvNow(closeF), 'cta': recvNow(ctaF)};
          final recvSched = <Map<String, Object?>>[];
          for (final e in schedChips.evaluate().toList()) {
            final ok = await reach(fe(e), 'measure:sched');
            recvSched.add({...recvNow(fe(e)), 'reached': ok});
          }
          final nowOk = await reach(nowChips, 'measure:now');
          final recvNowChip = {...recvNow(nowChips), 'reached': nowOk};

          // ── 1) 칩 선택 ──
          final chipF = s.pick == '현재' ? nowChips : inkWithText((p) => p == s.pick);
          need(chipF.evaluate().length == 1, '고를 칩 수 ${chipF.evaluate().length}');
          final chipLabel = TextLayout.plain((find.descendant(of: chipF, matching: find.byType(RichText)).evaluate().first.widget as RichText).text.toPlainText());
          final pickedTime = chipLabel.split(' ').last;
          if (await reach(chipF, 'chip')) {
            row['visChipLabel'] = textVisible(find.descendant(of: chipF, matching: find.byType(RichText)));
            nTap++;
            budget();
            await t.tap(chipF);
            await frames(3);
            safe('칩');
            steps.add('chip:$chipLabel');
          } else {
            need(!after, 'TA 칩 비도달');
            unreachable = true;
            steps.add('UNREACHABLE_BASELINE chip:$chipLabel');
          }
          // 선택 칩 단계 캡처(비도달이면 미선택 프레임)
          final chipMat = nearest(chipF.evaluate().first, (w) => w is Material);
          final chipFill = chipMat == null ? null : (chipMat.widget as Material).color;
          final chipText = (find.descendant(of: chipF, matching: find.byType(RichText)).evaluate().first.widget as RichText).text.style?.color;
          final chipRect = t.getRect(chipF);
          row['chip'] = {'label': chipLabel, 'selectedFrame': !unreachable, 'fill': chipFill == null ? null : _hex(chipFill), 'fg': chipText == null ? null : _hex(chipText),
            'contrast': (chipFill == null || chipText == null) ? null : r2(_contrast(chipText, chipFill)), 'w': r1(chipRect.width), 'h': r1(chipRect.height)};
          row['bigAfterChip'] = bigNumber();
          nPng++;
          budget();
          await vqCapture(t, key, 'D301-$phase-${c.id}_${s.id}',
              conditions: {'phase': phase, 'viewport': '${c.w.toInt()}x${c.h.toInt()}', 'textScaleFactor(기기)': c.s, 'sample': s.id, 'step': unreachable ? 'unselected(UNREACHABLE_BASELINE)' : 'chip-selected'});

          // ── 2) ±10 ── [DU302 r3] ±10 두 receiver 는 조정 바가 도달한 프레임에서 잰다
          final adj = s.delta > 0 ? fe(plus.first) : fe(minus.first);
          String? expectShown;
          Map<String, Object?> recvMinus = recvNow(fe(minus.first)), recvPlus = recvNow(fe(plus.first));
          if (!unreachable) {
            if (await reach(adj, 'adj')) {
              recvMinus = recvNow(fe(minus.first));
              recvPlus = recvNow(fe(plus.first));
              row['visAdjLabel'] = textVisible(find.descendant(
                  of: adj, matching: find.byWidgetPredicate((w) => w is RichText && TextLayout.plain(w.text.toPlainText()) == '10분')));
              nTap++;
              budget();
              await t.tap(adj);
              await frames(3);
              safe('±10');
              steps.add('adj:${s.delta}');
              expectShown = _hm(_min(pickedTime) + s.delta);
            } else {
              need(!after, 'TA ±10 비도달');
              unreachable = true;
              steps.add('UNREACHABLE_BASELINE adj:${s.delta}');
            }
          }
          row['recv'] = {
            'sched': recvSched,
            'now': recvNowChip,
            'minus': recvMinus,
            'plus': recvPlus,
            ...recvFixed,
          };
          final big = bigNumber();
          row['bigAfterAdj'] = big;
          // 확정 버튼 색·글·읽기 이름
          final ctaMat = find.descendant(of: ctaF, matching: find.byType(Material)).evaluate().first.widget as Material;
          final ctaRtEl = find.descendant(of: ctaF, matching: find.byType(RichText)).evaluate().first;
          final ctaRp = t.renderObject<RenderParagraph>(fe(ctaRtEl));
          final ctaLabel = TextLayout.plain(ctaRp.text.toPlainText());
          final ctaFg = ctaRp.text.style?.color;
          row['cta'] = {'label': ctaLabel, 'fill': ctaMat.color == null ? null : _hex(ctaMat.color!), 'fg': ctaFg == null ? null : _hex(ctaFg),
            'contrast': (ctaMat.color == null || ctaFg == null) ? null : r2(_contrast(ctaFg, ctaMat.color!)), 'ellipsis': ctaRp.didExceedMaxLines,
            'semTree': find.bySemanticsLabel(ctaLabel).evaluate().length};
          if (expectShown != null) {
            need(big['text'] == expectShown, '선택 숫자 ${big['text']} ≠ $expectShown');
            need(ctaLabel.startsWith('$expectShown 로 '), '확정 글 $ctaLabel ≠ $expectShown');
          }
          // B 끝 장면(스크롤이 있으면 실제 drag 로 끝까지)
          if (c.id == 'B320' && hasScroll) {
            final pos = t.state<ScrollableState>(find.descendant(of: scroll, matching: find.byType(Scrollable)).first).position;
            row['scrollMax'] = r1(pos.maxScrollExtent);
            if (pos.maxScrollExtent - pos.pixels > 0.5) {
              nDrag++;
              budget();
              await t.drag(scroll, Offset(0, -(pos.maxScrollExtent - pos.pixels + 40)));
              await frames(3);
              safe('끝 drag');
              row['atEnd'] = (pos.maxScrollExtent - pos.pixels).abs() < 0.5;
              nPng++;
              budget();
              await vqCapture(t, key, 'D301-$phase-${c.id}_${s.id}_end',
                  conditions: {'phase': phase, 'viewport': '${c.w.toInt()}x${c.h.toInt()}', 'textScaleFactor(기기)': c.s, 'sample': s.id, 'scroll': 'end'});
            }
          }

          // ── 3) 마지막 행동 ──
          final Finder finalF = s.finalAct == 'confirm' ? ctaF : (c.id == 'W360' ? cancelF : closeF);
          final finalName = s.finalAct == 'confirm' ? 'confirm' : (c.id == 'W360' ? 'cancel' : 'close');
          if (!unreachable) {
            if (await reach(finalF, 'final:$finalName')) {
              nTap++;
              budget();
              await t.tap(finalF);
              await frames(10);
              safe('마지막');
              steps.add('final:$finalName');
              row['afterFinal'] = {'done': done, 'gotResult': gotResult, 'result': result, 'sheets': find.byType(BottomSheet).evaluate().length,
                'host': find.text(_host).evaluate().length};
              need(done == 1 && find.byType(BottomSheet).evaluate().isEmpty && find.text(_host).evaluate().length == 1, '닫힘 ${row['afterFinal']}');
              if (s.expect != null) {
                need(result == s.expect && result == expectShown, '반환 $result ≠ ${s.expect}/$expectShown');
              } else {
                need(result == null, '반환 null 아님 $result');
              }
            } else {
              need(!after, 'TA 마지막 행동 비도달');
              unreachable = true;
              steps.add('UNREACHABLE_BASELINE final:$finalName');
            }
          }
          row['steps'] = steps;
          row['unreachable'] = unreachable;
          if (unreachable) row['afterTeardownNote'] = 'host teardown 은 닫기/null 반환 성공으로 세지 않는다(done=$done)';

          // 모든 글: 말줄임 0
          var ellipsis = 0;
          for (final e in find.byType(RichText).evaluate()) {
            if ((e.renderObject as RenderParagraph).didExceedMaxLines) ellipsis++;
          }
          row['ellipsis'] = ellipsis;

          if (after) {
            final rc = row['recv'] as Map<String, Object?>;
            final big0 = row['bigAfterChip'] as Map<String, Object?>;
            final hi = row['headIcon'] as Map<String, Object?>;
            final ttl = row['title'] as Map<String, Object?>;
            final cta = row['cta'] as Map<String, Object?>;
            final chip = row['chip'] as Map<String, Object?>;
            need(row['ctaReachAtOpen'] == true, '열린 직후 확정 버튼 도달');
            need(chip['fill'] == _hex(brand) && chip['fg'] == _hex(AppColors.surface) && (chip['contrast'] as double) >= 4.5, '선택 칩 $chip');
            need(cta['fill'] == _hex(brand) && cta['fg'] == _hex(AppColors.surface) && (cta['contrast'] as double) >= 4.5, '확정 버튼 $cta');
            need(big0['bg'] == _hex(AppColors.grey100) && big0['fg'] == _hex(AppColors.textPrimary) && (big0['contrast'] as double) >= 4.5, '시각 카드 $big0');
            final expIcon = s.checkIn ? AppColors.successDark : AppColors.purple;
            final expBg = Color.alphaBlend((s.checkIn ? AppColors.success : AppColors.purple).withValues(alpha: 0.1), Colors.white);
            need(hi['fg'] == _hex(expIcon) && hi['bg'] == _hex(expBg) && (hi['contrast'] as double) >= 3.0, '머리 아이콘 $hi');
            need(ttl['fs'] == ttl['fsExpect'] && ttl['ellipsis'] == false && (ttl['semTree'] as int) >= 1, '제목 $ttl');
            need(cta['ellipsis'] == false && (cta['semTree'] as int) >= 1, '확정 글 $cta');
            bool ok48(Object? m) => m is Map && (m['wRaw'] as double) >= 48 && (m['hRaw'] as double) >= 48 && m['hit'] == true;
            need((rc['sched'] as List).every(ok48) && ok48(rc['now']) && ok48(rc['minus']) && ok48(rc['plus']) && ok48(rc['cancel']) && ok48(rc['close']), 'receiver 48 $rc');
            final ctaR = rc['cta'] as Map;
            need((ctaR['hRaw'] as double) >= 52 && (ctaR['wRaw'] as double) >= 48 && ctaR['hit'] == true, '확정 52 $ctaR');
            need(ellipsis == 0, '말줄임 $ellipsis');
            need(!unreachable, '비도달');
            final vis = row['visAtOpen'] as Map<String, Object?>;
            need(vis['title'] == true && vis['big'] == true && vis['ctaLabel'] == true && row['visChipLabel'] == true && row['visAdjLabel'] == true,
                '전문 가시 open $vis chip ${row['visChipLabel']} adj ${row['visAdjLabel']}');
          }
          visited.add(cur);
          rows.add(row);
          _out('D301 ${jsonEncode(row)}');
          if (find.byType(BottomSheet).evaluate().isNotEmpty) {
            // baseline 비도달: 시트가 남은 채 host 를 내린다(닫기 성공으로 세지 않음).
            await mount(const SizedBox.shrink());
            await frames(2);
            safe('teardown');
          }
        }
      }
      // [DU302] 단계별 방문 집합: diag B320_IN1 · baseline 정확 B4 · after 8
      final expVisited = diag
          ? ['B320_IN1']
          : after
              ? ['W360_IN1', 'W360_IN2', 'W360_OUT1', 'W360_NUL', 'B320_IN1', 'B320_IN2', 'B320_OUT1', 'B320_NUL']
              : ['B320_IN1', 'B320_IN2', 'B320_OUT1', 'B320_NUL'];
      need(visited.join('|') == expVisited.join('|'), '방문 표본 $visited');
      need(nOpen == expVisited.length, '열기 $nOpen');
      if (after) need(baselineOverflow.isEmpty, 'TA overflow $baselineOverflow');
      await mount(const SizedBox.shrink());
      await frames(1);
      safe('END 전');
      _out('D301-END ${jsonEncode({'pump': nPump, 'mount': nMount, 'png': nPng, 'tap': nTap, 'drag': nDrag, 'open': nOpen, 'visited': visited,
        'http': net.created, 'baselineOverflow': baselineOverflow})}');
    } finally {
      // [DU302] STOP·정상 모두 시점별 계수를 남긴다(정상 END 가 없으면 이 줄이 유일한 계수다)
      _out('D301-FINAL ${jsonEncode({...counts(), 'http': net.created, 'visited': visited, 'baselineOverflow': baselineOverflow.length, 'reachAttempts': reachAttempts, 'lastReach': lastReach})}');
      sem.dispose();
      FlutterError.onError = prevOnError;
      HttpOverrides.global = prevHttp;
      t.platformDispatcher.clearLocalesTestValue();
      t.platformDispatcher.clearLocaleTestValue();
      t.platformDispatcher.clearTextScaleFactorTestValue();
      t.view.reset();
    }
  }, skip: !run, timeout: const Timeout(Duration(minutes: 3)));
}
