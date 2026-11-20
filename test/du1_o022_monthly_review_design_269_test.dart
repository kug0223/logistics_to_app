// ignore_for_file: depend_on_referenced_packages
// [DU269 O022 관리자 월별 리뷰 작성·조회 baseline/after] Codex 한도 중 Claude 자체 진행(허브 DU_self_review_hub_2026-11-10).
//   같은 시험을 교정 전(baseline)·후(after)에 한 번씩 돌린다. 시험은 production 을 편집하지 않는다.
//   DU269_RUN=1 이고 DU269_PHASE 가 baseline 또는 after 일 때만 실행한다(기본 skip).
//   작성은 showDialog(builder: MonthlyReviewDialog(...)), 조회는 showMonthlyReviewViewDialog 로 연다. 첫 리뷰 툴팁은 이미 본 상태.
//   장면 6(w-fresh·w-filled·w-unknown·w-dropped·v-full·v-min) × W360/1.0·B320/2.0. w-dropped 는 저장 전 대조에서 멈춘다(쓰기 0).
//   측정 하네스는 DU269 계승(seenOk·아이콘 규칙·두 선택지 같은 높이).
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
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ALfit/models/core/monthly_review_model.dart';
import 'package:ALfit/models/settings/trust_settings_model.dart';
import 'package:ALfit/widgets/dialogs/monthly_review_dialog.dart';
import 'package:ALfit/widgets/dialogs/styled_dialog.dart';

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

const _pos = ['시간 준수', '성실함', '꼼꼼한 업무 처리'];
const _imp = ['집중력', '소통'];
const _comment = '포장 속도가 빠르고 정확합니다. 다음 달에도 함께하면 좋겠습니다.';

ReviewTagsModel _tagsOf(String sc) => sc == 'w-dropped'
    ? ReviewTagsModel(positiveTags: [..._pos, '지워질 관리자 태그'], improvementTags: _imp)
    : ReviewTagsModel(positiveTags: _pos, improvementTags: _imp);

MonthlyReviewDialog _write(String sc) => MonthlyReviewDialog(
      reviewerId: 'A',
      reviewerName: '관리자',
      businessId: 'B',
      businessName: '평택 물류센터',
      targetUserId: 'W',
      targetUserName: '김근로',
      reviewYear: 2026,
      reviewMonth: 10,
      workDaysInMonth: sc == 'w-unknown' ? 5 : 12,
      normalAttendanceDays: sc == 'w-unknown' ? null : 8,
      lateDays: sc == 'w-unknown' ? null : 1,
      requestId: 'R',
      preloadedTags: sc == 'w-unknown' ? ReviewTagsModel() : _tagsOf(sc),
      tagsUnavailable: sc == 'w-unknown',
      loadLatestTags: () async => ReviewTagsModel(positiveTags: _pos, improvementTags: _imp),
    );

MonthlyReviewModel _review(String sc) => MonthlyReviewModel(
      id: 'r1',
      reviewKey: 'k1',
      reviewType: ReviewType.ADMIN_TO_USER,
      reviewerName: '관리자',
      reviewerId: 'A',
      businessId: 'B',
      businessName: '평택 물류센터',
      targetUserId: 'W',
      targetUserName: '김근로',
      reviewYear: 2026,
      reviewMonth: 10,
      workDaysInMonth: 12,
      rating: 4,
      wouldRehire: sc == 'v-full',
      positiveTags: sc == 'v-full' ? const ['시간 준수', '꼼꼼한 업무 처리'] : const [],
      improvementTags: sc == 'v-full' ? const ['집중력'] : const [],
      comment: sc == 'v-full' ? _comment : null,
      isPublished: sc == 'v-min',
      createdAt: DateTime(2026, 10, 30),
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
  final phase = Platform.environment['DU269_PHASE'] ?? '';
  final run = Platform.environment['DU269_RUN'] == '1' && (phase == 'baseline' || phase == 'after');
  final after = phase == 'after';
  final nl = String.fromCharCode(10);

  setUpAll(() async {
    await initializeDateFormatting('ko_KR', null);
    SharedPreferences.setMockInitialValues(<String, Object>{'tooltip_shown_first_review': true}); // 첫 리뷰 안내 이미 봄
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
  });

  testWidgets('D269 $phase', (t) async {
    await t.runAsync(vqLoadFonts);
    t.platformDispatcher.localesTestValue = const [Locale('ko', 'KR')];
    t.platformDispatcher.localeTestValue = const Locale('ko', 'KR');
    final prevOnError = FlutterError.onError;
    final errors = <String>[];
    FlutterError.onError = (d) => errors.add(d.exceptionAsString().split(nl).first);
    var nPump = 0, nDrag = 0, nPng = 0, nTap = 0;
    var cur = '(시작)';
    Never stop(String why) {
      _out('D269-STOP ${jsonEncode({'at': cur, 'why': why, 'errors': errors})}');
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
        for (final sc in const ['w-fresh', 'w-filled', 'w-unknown', 'w-dropped', 'v-full', 'v-min']) {
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
                      onPressed: () => sc.startsWith('v-')
                          ? showMonthlyReviewViewDialog(ctx, review: _review(sc))
                          : showDialog<bool>(context: ctx, barrierDismissible: false, builder: (_) => _write(sc)),
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
          safe('대화 열림');
          Finder host() => sc.startsWith('v-') ? find.byType(AppModalShell) : find.byType(MonthlyReviewDialog);
          need(host().evaluate().length == 1, '대화가 열리지 않았다');

          Finder? sfOf() {
            final f = find.descendant(of: host(), matching: find.byType(Scrollable), skipOffstage: false);
            return f.evaluate().isEmpty ? null : nth(f, 0);
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
              'didExceedMaxLines': rp.didExceedMaxLines, 'maxLines': rp.maxLines,
              if (li != null) 'lines': li.lines,
              if (li != null) 'sylBreaks': li.sylBreaks,
              if (br != null) 'boxH': r1(br.height),
            };
          }

          Finder? anc(Finder? f, bool Function(Widget w) p) =>
              f == null ? null : find.ancestor(of: f, matching: find.byWidgetPredicate(p, skipOffstage: false));

          bool isGd(Widget w) => w is GestureDetector;
          final w = sc.startsWith('w-');
          List<Map<String, Object?>> measure() {
            final xs = <Map<String, Object?>>[];
            void add(String nm, Finder? f, {String? kind, Finder? box}) => xs.add(info(nm, f, kind: kind, box: box));
            Finder? one(String s, [int i = 0]) => nth(rich((p) => p == s), i);
            add('관리자 전용', one('관리자 전용'), kind: 'pair:#946200/#FFF5D6');
            if (w) {
              add('근태 제목', one('10월 근태 요약'), kind: 'value');
              add('근태 아이콘', glyph(Icons.analytics_outlined, 0), kind: 'hdrIcon');
              for (final s in ['근무일', '정시 출근', '지각']) {
                add('칸 $s', one(s), kind: 'detail');
              }
              if (sc == 'w-unknown') {
                add('근무일 값', one('5일'), kind: 'value');
                add('정시 값', one('확인 불가'), kind: 'detail');
                add('지각 값', one('확인 불가', 1), kind: 'detail');
              } else {
                add('근무일 값', one('12일'), kind: 'value');
                add('정시 값', one('8일'), kind: 'value');
                add('지각 값', one('1회'), kind: 'fg:#946200');
                add('결근 값', one('3일'), kind: 'fg:#B42318');
                add('칸 결근', one('결근'), kind: 'detail');
              }
              for (final s in ['종합 평가', '재고용 의사', '좋았던 점', '아쉬운 점', '상세 코멘트']) {
                add('섹션 $s', one(s), kind: 'sec');
              }
              add('재고용 안내', one('다른 관리자에게만 공개'), kind: 'detail');
              add('코멘트 안내', one('선택 · 다른 관리자에게만 공개'), kind: 'detail');
              add('복수 선택', one('복수 선택'), kind: 'detail');
              final star = glyph(Icons.star_rounded, -1);
              add('채운 별', star, kind: 'star', box: anc(star, isGd));
              if (sc != 'w-filled') add('빈 별', glyph(Icons.star_outline_rounded, 0), kind: 'emptyStar');
              add('점수 라벨', one(sc == 'w-filled' ? '최고' : '좋음'), kind: 'detail');
              final yes = one('재고용');
              final no = one('재고용 안함');
              final sel = sc == 'w-filled' || sc == 'w-dropped';
              add('재고용', yes, kind: sel ? 'choiceSel' : 'choice', box: anc(yes, isGd));
              add('재고용 안함', no, kind: 'choice', box: anc(no, isGd));
              if (sc == 'w-unknown') {
                add('태그 없음', nth(rich((p) => p.startsWith('태그 목록을 불러오지 못했습니다')), 0), kind: 'detail');
              } else {
                for (final g in ['시간 준수', '집중력', '성실함']) {
                  final f = one(g);
                  final on = sc == 'w-filled' && g != '성실함';
                  add('태그 $g', f, kind: on ? 'tagSel' : 'tag', box: anc(f, isGd));
                }
                if (sc == 'w-filled') add('체크', glyph(Icons.check, 0), kind: 'fg:#3859E8');
              }
              add('힌트', one('채용 시 참고할 내용을 작성해주세요.'), kind: 'hint');
              add('공개 안내 제목', one('작성 후 수정이 불가합니다.'), kind: 'fg:#0D47A1');
              add('공개 안내', nth(rich((p) => p.startsWith('신중하게 작성해주세요')), 0), kind: 'fg:#0D47A1');
              add('공개 아이콘', glyph(Icons.info_outline, -1), kind: 'fg:#1976D2');
              if (sc == 'w-dropped') {
                add('빠진 안내', nth(rich((p) => p.startsWith('지금은 고를 수 없는')), 0), kind: 'value');
                add('빠진 아이콘', glyph(Icons.info_outline, 0), kind: 'fg:#946200');
              }
              add('작성 버튼', one('리뷰 작성', -1), kind: 'record');
            } else {
              final full = sc == 'v-full';
              add('조회 빈 별', glyph(Icons.star_border, 0), kind: 'emptyStar');
              add('조회 평점', one('좋음'), kind: 'value');
              add('재고용 결과', one(full ? '재고용 의사 있음' : '재고용 의사 없음'), kind: full ? 'fg:#166534' : 'fg:#B42318');
              add('재고용 아이콘', glyph(full ? Icons.thumb_up : Icons.thumb_down, 0), kind: full ? 'fg:#166534' : 'fg:#B42318');
              if (full) {
                for (final s in ['좋았던 점', '아쉬운 점', '상세 코멘트']) {
                  add('섹션 $s', one(s), kind: 'sec');
                }
                for (final g in ['시간 준수', '꼼꼼한 업무 처리', '집중력']) {
                  add('조회 태그 $g', one(g), kind: 'value');
                }
                add('코멘트', one(_comment), kind: 'body'); // [TB 뒤 보정] 사용자가 쓴 글 — 음절 끊김 예외, 색만 본다
              }
              add('공개 상태', nth(rich((p) => p.startsWith(full ? '공개 대기' : '공개된 리뷰')), 0), kind: 'fg:#0D47A1');
              add('공개 아이콘', glyph(Icons.schedule, 0), kind: 'fg:#1976D2');
              add('닫기 버튼', one('닫기', -1), kind: 'record');
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
              final sb = x['sylBreaks'];
              if (sb is int && k != 'body') need(sb == 0, '$at 음절 끊김 $x');
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

          // 상호작용(측정 전) — 보이게 한 뒤 누르고, 끝나면 맨 위로 돌린다.
          Future<void> tapVis(Finder? f, String what) async {
            need(f != null, '$what 를 찾지 못했다');
            await t.ensureVisible(f!);
            await frames(4);
            nTap++;
            await t.tap(f, warnIfMissed: false);
            await frames(6);
            safe('$what 탭 뒤');
          }

          if (sc == 'w-filled') {
            await tapVis(glyph(Icons.star_outline_rounded, 0), '다섯째 별');
            await tapVis(nth(rich((p) => p == '재고용'), 0), '재고용');
            await tapVis(nth(rich((p) => p == '시간 준수'), 0), '시간 준수');
            await tapVis(nth(rich((p) => p == '집중력'), 0), '집중력');
          }
          if (sc == 'w-dropped') {
            await tapVis(nth(rich((p) => p == '지워질 관리자 태그'), 0), '지워질 태그');
            await tapVis(nth(rich((p) => p == '재고용'), 0), '재고용');
            await tapVis(nth(rich((p) => p == '리뷰 작성'), -1), '리뷰 작성');
            await frames(10);
            need(rich((p) => p.startsWith('지금은 고를 수 없는')).evaluate().isNotEmpty, '빠진 선택 안내가 없다');
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
            // [r3] 두 선택지는 같은 높이다(큰 글자에서 한쪽만 두 줄이 되어도)
            if (after) {
              final hs = xs.where((x) => (x['name'] == '재고용' || x['name'] == '재고용 안함') && x['boxH'] != null)
                  .map((x) => x['boxH'] as double).toList();
              if (hs.length == 2) need((hs[0] - hs[1]).abs() < 0.5, '두 선택지 높이가 다르다 $hs');
            }
            for (final x in xs) {
              if (x['present'] == true && x['seenOk'] == true) seen.add(x['name'] as String);
            }
            if (after && suffix.isEmpty) {
              // 섹션 제목 아이콘을 그리지 않는다(시안 섹션 제목은 글자만)
              for (final ic in [Icons.edit_note, Icons.thumb_up_outlined, Icons.lightbulb_outline]) {
                need(find.byIcon(ic).evaluate().isEmpty, '섹션 아이콘이 남았다 $ic');
              }
            }
            nPng++;
            await vqCapture(t, key, 'D269-$phase-${c.id}_$sc$suffix', conditions: {
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
              await t.dragFrom(Offset(vp.left + 24, vp.top + vp.height * 0.6), Offset(0, -(vp.height * 0.5)));
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
          _out('D269 ${jsonEncode({'phase': phase, 'cond': c.id, 'scene': sc, 'overflow': overflow, 'atEnd': atEnd, 'shots': shots,
                'seen': seen.toList(), 'counts': {'pump': nPump, 'drag': nDrag, 'png': nPng, 'tap': nTap}})}');
        }
      }
      await t.pumpWidget(const SizedBox.shrink());
      await frames(1);
      safe('END 전');
      _out('D269-END ${jsonEncode({'pump': nPump, 'drag': nDrag, 'png': nPng, 'tap': nTap})}');
    } finally {
      FlutterError.onError = prevOnError;
      t.platformDispatcher.clearLocalesTestValue();
      t.platformDispatcher.clearLocaleTestValue();
      t.platformDispatcher.clearTextScaleFactorTestValue();
      t.view.reset();
    }
  }, skip: !run, timeout: const Timeout(Duration(minutes: 6)));
}
