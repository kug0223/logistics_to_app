// ignore_for_file: depend_on_referenced_packages
// [DU274 O027-2 지원 대화 업무 카드 baseline/after] Codex 한도 중 Claude 자체 진행(허브 DU_self_review_hub_2026-11-10).
//   같은 시험을 교정 전(baseline)·후(after)에 한 번씩 돌린다. 시험은 production 을 편집하지 않는다.
//   DU274_RUN=1 이고 DU274_PHASE 가 baseline 또는 after 일 때만 실행한다(기본 skip).
//   시트 안에 WorkSelectionCard 하나를 그린다(지원 대화와 같은 폭·글꼴). 장면 7(카드 상태) × W360/1.0·B320/2.0. 버튼은 누르지 않는다.
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

import 'package:ALfit/theme/role_theme.dart';
import 'package:ALfit/utils/text_layout.dart';
import 'package:provider/provider.dart';
import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/models/core/work_detail_data.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/services/schedule_conflict_service.dart';
import 'package:ALfit/utils/dialog_helper.dart';
import 'package:ALfit/utils/format_helper.dart';
import 'package:ALfit/widgets/dialogs/apply/work_selection_card.dart';

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

class _Applicant extends UserProvider {
  @override
  UserModel? get currentUser => UserModel(
        uid: 'u1',
        username: 'u1',
        name: '김근로',
        email: 'u1@alfit.local',
        role: UserRole.USER,
        createdAt: DateTime(2026, 1, 1),
      );
}

final kWorkDate = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day).add(const Duration(days: 5));

WorkDetailData _work(String sc) => WorkDetailData(
      wdId: 'wd1',
      workType: '상하차',
      workTypeIcon: 'box',
      workTypeColor: '#000000',
      workTypeBackgroundColor: '#FFFFFF',
      wage: 12000,
      wageType: 'hourly',
      requiredCount: 4,
      runtimeFull: sc == 'closed',
      startTime: '09:00',
      endTime: '18:00',
      breakMinutes: 60,
      applicationDeadline: sc == 'open' ? kWorkDate.subtract(const Duration(hours: 6)) : null,
      payScheduleType: sc == 'open' ? 'same_day' : null,
      payScheduleTime: sc == 'open' ? '18:00' : null,
    );

Widget _cardSheet(String sc) => SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: WorkSelectionCard(
        workDetail: _work(sc),
        status: switch (sc) {
          'pending' => WorkApplicationStatus.pending,
          'confirmed' => WorkApplicationStatus.confirmed,
          'invited' => WorkApplicationStatus.invited,
          'auto' => WorkApplicationStatus.autoCanceled,
          _ => WorkApplicationStatus.notApplied,
        },
        conflictInfo: sc == 'blocked'
            ? const ConflictInfo(level: ConflictLevel.blocked, message: '같은 시간에 확정된 근무가 있어 지원할 수 없어요')
            : ConflictInfo.ok,
        onApply: () {},
        onCancelApplication: () {},
        onCancelConfirm: () {},
        slotDate: kWorkDate,
      ),
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
  final phase = Platform.environment['DU274_PHASE'] ?? '';
  final run = Platform.environment['DU274_RUN'] == '1' && (phase == 'baseline' || phase == 'after');
  final after = phase == 'after';
  final nl = String.fromCharCode(10);

  setUpAll(() async {
    await initializeDateFormatting('ko_KR', null);
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
  });

  testWidgets('D274 $phase', (t) async {
    await t.runAsync(vqLoadFonts);
    t.platformDispatcher.localesTestValue = const [Locale('ko', 'KR')];
    t.platformDispatcher.localeTestValue = const Locale('ko', 'KR');
    final prevOnError = FlutterError.onError;
    final errors = <String>[];
    FlutterError.onError = (d) => errors.add(d.exceptionAsString().split(nl).first);
    var nPump = 0, nDrag = 0, nPng = 0, nTap = 0;
    var cur = '(시작)';
    Never stop(String why) {
      _out('D274-STOP ${jsonEncode({'at': cur, 'why': why, 'errors': errors})}');
      fail('$cur: $why');
    }

    void need(bool ok, String why) {
      if (!ok) stop(why);
    }

    Future<void> frames(int n) async {
      for (var i = 0; i < n; i++) {
        nPump++;
        need(nPump <= 3200 && nDrag <= 160 && nPng <= 200 && nTap <= 40, '사용량 한도'); // [TB 보정] 6장면·긴 스크롤(1차 TB 한도 도달)
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
    try {
      for (final c in const [
        (id: 'W360', w: 360.0, h: 780.0, s: 1.0),
        (id: 'B320', w: 320.0, h: 640.0, s: 2.0),
      ]) {
        for (final sc in const ['open', 'pending', 'confirmed', 'invited', 'blocked', 'closed', 'auto']) {
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
            child: ChangeNotifierProvider<UserProvider>(
              create: (_) => _Applicant(),
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
                      onPressed: () => DialogHelper.showSheet<void>(
                        ctx,
                        isScrollControlled: true,
                        builder: (_) => _cardSheet(sc),
                      ),
                      child: const Text('열기'),
                    ),
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
          // (DU273 에서 물려받은 자동 알림 처리 — 이 시험의 카드 장면에는 자동 알림이 없어 돌지 않는다.)
          final alertErrors = <String>[];
          if (sc == '__none__') {
            alertErrors.addAll(errors.where((e) => e.startsWith('A RenderFlex overflowed')));
            errors.removeWhere((e) => e.startsWith('A RenderFlex overflowed'));
            final okBtn = rich((p) => p == '확인');
            if (okBtn.evaluate().isNotEmpty) {
              nTap++;
              await t.tap(nth(okBtn, -1)!, warnIfMissed: false);
              await frames(10);
              alertErrors.addAll(errors.where((e) => e.startsWith('A RenderFlex overflowed')));
              errors.removeWhere((e) => e.startsWith('A RenderFlex overflowed'));
            }
            need(rich((p) => p == '확인').evaluate().isEmpty, '자동 알림이 닫히지 않았다');
          }
          safe('대화 열림');
          Finder host() => find.byType(WorkSelectionCard);
          need(host().evaluate().length == 1, '대화가 열리지 않았다');
          Finder? sfOf() {
            final f = find.descendant(of: host(), matching: find.byType(Scrollable), skipOffstage: false);
            return f.evaluate().isEmpty ? null : nth(f, 0);
          }

          double opOf(Element e) {
            var o = 1.0;
            e.visitAncestorElements((a) {
              final w = a.widget;
              if (w is Opacity) o *= w.opacity;
              return true;
            });
            return o;
          }

          Map<String, Object?> info(String nm, Finder? f, {String? kind, bool lines = true, Finder? box}) {
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
            // [TB 뒤 보정] 화면 높이 60% 이상인 긴 블록(B320 공개 안내 12줄)은 통째로 들어오는 순간이 없을 수 있다 —
            //   화면에 걸쳐 보이면 본 것으로 친다(seenOk). 짧은 글자는 여전히 통째로 안에 있어야 한다.
            final vis = inside(r, screen) && inside(r, vp);
            final tall = r.height >= vp.height * 0.6 && r.overlaps(vp) && r.overlaps(screen);
            return {
              'name': nm, 'kind': kind, 'present': true, 'rect': lt(r), 'visible': vis, 'seenOk': vis || tall,
              'fontSize': rp.text.style?.fontSize, 'weight': rp.text.style?.fontWeight?.value,
              'fg': fg == null ? null : _hex(fg), 'bg': _hex(bg),
              'contrast': fg == null ? null : double.parse(_contrast(fg, bg).toStringAsFixed(2)),
              'didExceedMaxLines': rp.didExceedMaxLines, 'maxLines': rp.maxLines, 'opacity': r1(opOf(f.evaluate().first)),
              if (li != null) 'lines': li.lines,
              if (li != null) 'sylBreaks': li.sylBreaks,
              if (br != null) 'boxH': r1(br.height),
            };
          }

          Finder? anc(Finder? f, bool Function(Widget w) p) =>
              f == null ? null : find.ancestor(of: f, matching: find.byWidgetPredicate(p, skipOffstage: false));

          bool isInk(Widget w) => w is InkWell;
          List<Map<String, Object?>> measure() {
            final xs = <Map<String, Object?>>[];
            void add(String nm, Finder? f, {String? kind, Finder? box}) => xs.add(info(nm, f, kind: kind, box: box));
            Finder? one(String s, [int i = 0]) => nth(rich((p) => p == s), i);
            // 업무명 글자 + 카드 면: 고를 수 있는 카드는 흰 면, 고를 수 없는 카드(차단·마감)는 바탕색 면(WC1).
            final cardBg = (sc == 'blocked' || sc == 'closed') ? '#F6F7FA' : '#FFFFFF';
            add('업무명', one('상하차'), kind: 'pair:#21242D/$cardBg');
            final (bt, bfg, bbg) = switch (sc) {
              'pending' => ('지원완료', '#0D47A1', '#E3F2FD'),
              'confirmed' => ('확정', '#166534', '#EAF7EF'),
              'invited' => ('초대 확인', '#946200', '#FFF5D6'),
              'blocked' => ('시간충돌', '#B42318', '#FEEDEA'),
              'closed' => ('마감', '#60646F', '#F5F5F5'),
              'auto' => ('자동취소', '#946200', '#FFF5D6'),
              _ => ('모집중', '#0D47A1', '#E3F2FD'),
            };
            add('상태 배지', one(bt), kind: 'pair:$bfg/$bbg');
            switch (sc) {
              case 'open' || 'auto':
                final b = one(sc == 'open' ? '지원' : '재지원');
                add('주 행동', b, kind: 'priBtn', box: anc(b, isInk));
              case 'pending':
                final b = one('취소');
                add('보조 행동', b, kind: 'secBtn2', box: anc(b, isInk));
              case 'confirmed':
                final b = one('확정취소');
                add('위험 행동', b, kind: 'dangerBtn', box: anc(b, isInk));
              case 'invited':
                add('표시 초대', one('초대 확인', 1), kind: 'disp');
              case 'blocked':
                add('표시 불가', one('불가'), kind: 'disp');
                add('충돌 메시지', nth(rich((p) => p.startsWith('같은 시간에')), 0), kind: 'pair:#B42318/#FEEDEA');
              case 'closed':
                add('표시 마감', one('마감', 1), kind: 'disp');
            }
            add('시간', one(_work(sc).timeRange), kind: 'valueRaw');
            add('순근무', nth(rich((p) => p.startsWith('(') && p.endsWith(')')), 0), kind: 'detailRaw');
            add('급여', one('${FormatHelper.formatNumber(12000)}원/시급'), kind: 'fg:#166534');
            add('인원', one('4명 모집'), kind: 'detailRaw');
            add('시간 아이콘', glyph(Icons.access_time, 0), kind: 'fg:#60646F');
            if (sc == 'open') {
              add('마감 시각', nth(rich((p) => p.startsWith('전날') || p.startsWith('마감 ')), 0), kind: 'fg:#946200');
              add('정산 배지', one('당일'), kind: 'fg:#166534');
              add('입금', one('당일 18:00 입금'), kind: 'detailRaw');
            }
            return xs;
          }

          void afterChecks(List<Map<String, Object?>> xs, String at) {
            if (!after) return;
            for (final x in xs) {
              if (x['present'] != true || x['seenOk'] != true) continue;
              final k = (x['kind'] as String?) ?? '';
              final cst = x['contrast'];
              final ok45 = cst is double && cst >= 4.5;
              need(x['didExceedMaxLines'] != true, '$at 말줄임/잘림 $x');
              need(((x['opacity'] as double?) ?? 1.0) >= 0.99, '$at 흐림 $x');
              final sb = x['sylBreaks'];
              if (sb is int && k != 'body' && !k.endsWith('Raw')) need(sb == 0, '$at 음절 끊김 $x');
              final h = x['boxH'] as double?;
              if (k == 'sec') {
                need(x['fg'] == '#21242D' && ok45 && x['fontSize'] == 16.0 && x['weight'] == 700, '$at 섹션 제목 $x');
              } else if (k == 'value') {
                need(x['fg'] == '#21242D' && ok45, '$at 본문색 $x');
              } else if (k == 'detail') {
                need(x['fg'] == '#60646F' && ok45, '$at 보조색 $x');
              } else if (k == 'hdrIcon') {
                need(x['fg'] == '#60646F', '$at 아이콘 $x');
              } else if (k == 'req') {
                need(x['fg'] == '#B42318' && ok45, '$at 필수 $x');
              } else if (k == 'emptyStar') {
                need(x['fg'] == '#686C77' && cst is double && cst >= 3.0, '$at 빈 별 $x');
              } else if (k == 'star') {
                need((h ?? 0) >= 48, '$at 별 터치 $x');
              } else if (k == 'choice' || k == 'tag') {
                need(x['fg'] == '#21242D' && ok45 && (h ?? 0) >= 48, '$at 미선택 $x');
              } else if (k == 'choiceSel' || k == 'tagSel') {
                need(x['fg'] == '#3859E8' && x['bg'] == '#EEF2FF' && ok45 && (h ?? 0) >= 48, '$at 선택 $x');
              } else if (k == 'body') {
                need(x['fg'] == '#21242D' && ok45, '$at 본문 $x');
              } else if (k == 'label') {
                need(x['fg'] == '#686C77' && ok45, '$at 줄 이름 $x');
              } else if (k == 'muted') {
                need(x['fg'] == '#60646F' && ok45, '$at 현재 값 $x');
              } else if (k == 'hi') {
                need(x['fg'] == '#3859E8' && ok45 && x['weight'] == 700, '$at 바뀐 값 $x');
              } else if (k == 'outBtn') {
                need(x['fg'] == '#3859E8' && ok45 && (h ?? 0) >= 48, '$at 유지 버튼 $x');
              } else if (k == 'priBtn') {
                need(x['fg'] == '#FFFFFF' && x['bg'] == '#3859E8' && ok45 && (h ?? 0) >= 48, '$at 수락 버튼 $x');
              } else if (k == 'neutralBtn') {
                need(x['fg'] == '#60646F' && ok45 && (h ?? 0) >= 48, '$at 진입 버튼 $x');
              } else if (k == 'empty') {
                need(ok45, '$at 빈 상태 $x');
              } else if (k == 'closeIcon') {
                need(x['fg'] == '#60646F' && (h ?? 0) >= 48, '$at 닫기 $x');
              } else if (k == 'disabledCta') {
                need(x['fg'] == '#60646F' && x['bg'] == '#EEEEEE' && ok45 && (h ?? 0) >= 48, '$at 비활성 CTA $x');
              } else if (k == 'textBtn') {
                need(x['fg'] == '#3859E8' && ok45 && (h ?? 0) >= 48, '$at 글자 버튼 $x');
              } else if (k == 'disabledDay') {
                need(x['fg'] == '#686C77' && ok45, '$at 선택 불가 날 $x');
              } else if (k == 'valueRaw') {
                need(x['fg'] == '#21242D' && ok45, '$at 본문색(원문) $x');
              } else if (k == 'detailRaw') {
                need(x['fg'] == '#60646F' && ok45, '$at 보조색(원문) $x');
              } else if (k == 'warnRaw') {
                need(x['fg'] == '#946200' && x['bg'] == '#FFF5D6' && ok45, '$at 경고(원문) $x');
              } else if (k == 'disp') {
                need(ok45, '$at 표시 $x');
              } else if (k == 'dangerBtn') {
                need(x['fg'] == '#B42318' && ok45 && (h ?? 0) >= 48, '$at 위험 행동 $x');
              } else if (k == 'secBtn2') {
                need(x['fg'] == '#60646F' && ok45 && (h ?? 0) >= 48, '$at 보조 행동 $x');
              } else if (k == 'hint') {
                need(ok45, '$at 힌트 $x');
              } else if (k.startsWith('pair:')) {
                final p = k.substring(5).split('/');
                need(x['fg'] == p[0] && x['bg'] == p[1] && ok45, '$at 배지 $x');
              } else if (k.startsWith('fg:')) {
                need(x['fg'] == k.substring(3) && cst is double && cst >= 3.0, '$at 의미색 $x');
                // [r1] 아이콘 이름이 '…아이콘'·'체크' 다(DU267 은 '아이콘…' 으로 시작) — 아이콘은 3:1, 글자만 4.5
                final nm = x['name'] as String;
                if (!nm.contains('아이콘') && nm != '체크') need(ok45, '$at 의미색 글자 $x');
              } else if (k.startsWith('cfm:')) {
                need(x['fg'] == '#FFFFFF' && x['bg'] == k.substring(4) && ok45, '$at 확인 버튼 $x');
              }
            }
          }

          if (sfOf() != null) {
            t.state<ScrollableState>(sfOf()!).position.jumpTo(0);
            await frames(4);
          }

          final shots = <Map<String, Object?>>[];
          final seen = <String>{};
          Future<void> snap(String suffix) async {
            final xs = measure();
            afterChecks(xs, suffix.isEmpty ? '첫 화면' : suffix);
            for (final x in xs) {
              if (x['present'] == true && x['seenOk'] == true) seen.add(x['name'] as String);
            }
            nPng++;
            await vqCapture(t, key, 'D274-$phase-${c.id}_$sc$suffix', conditions: {
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
            while (k < 30) {
              final sf = sfOf()!;
              final vp = t.getRect(sf);
              final pos = t.state<ScrollableState>(sf).position;
              if (pos.pixels >= pos.maxScrollExtent - 0.5) break;
              k++;
              nDrag++;
              // [DU272 TB 보정] 달력(TableCalendar)이 세로 드래그를 가로채 바깥 스크롤이 0 에서 움직이지 않았다 —
              //   위치를 직접 화면 반 높이씩 옮긴다(측정·캡처는 같다).
              pos.jumpTo(math.min(pos.pixels + vp.height * 0.5, pos.maxScrollExtent));
              await frames(8);
              safe('drag $k 뒤');
              await snap('_d$k');
            }
            final pos = t.state<ScrollableState>(sfOf()!).position;
            atEnd = pos.pixels >= pos.maxScrollExtent - 0.5;
          }
          if (after) {
            need(atEnd, '끝 도달 실패');
            // 빈 단언 방지 — 이 장면에서 잰 이름(기록용 제외)은 한 번 이상 화면 안에서 보여야 한다.
            for (final x in shots.first['texts'] as List<Map<String, Object?>>) {
              final nm = x['name'] as String;
              if (x['kind'] == 'record') continue;
              need(seen.contains(nm), '한 번도 보이지 않음: $nm');
            }
          }
          _out('D274 ${jsonEncode({'phase': phase, 'cond': c.id, 'scene': sc, 'overflow': overflow, 'alertOverflow': alertErrors, 'atEnd': atEnd, 'shots': shots,
                'seen': seen.toList(), 'counts': {'pump': nPump, 'drag': nDrag, 'png': nPng, 'tap': nTap}})}');
        }
      }
      await t.pumpWidget(const SizedBox.shrink());
      await frames(1);
      safe('END 전');
      _out('D274-END ${jsonEncode({'pump': nPump, 'drag': nDrag, 'png': nPng, 'tap': nTap})}');
    } finally {
      FlutterError.onError = prevOnError;
      t.platformDispatcher.clearLocalesTestValue();
      t.platformDispatcher.clearLocaleTestValue();
      t.platformDispatcher.clearTextScaleFactorTestValue();
      t.view.reset();
    }
  }, skip: !run, timeout: const Timeout(Duration(minutes: 6)));
}
