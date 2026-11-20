// ignore_for_file: depend_on_referenced_packages
// [DU278 O027-3c 지원 대화 장기(계약) 공고 경로 baseline/after] Codex 한도 중 Claude 자체 진행(허브 DU_self_review_hub_2026-11-10).
//   같은 시험을 교정 전(baseline — 읽기 주입 LT0 만 반영한 상태)·후(after)에 한 번씩 돌린다. 시험은 production 을 편집하지 않는다.
//   DU278_RUN=1 이고 DU278_PHASE 가 baseline 또는 after 일 때만 실행한다(기본 skip).
//   장기 공고(type contract, 평일 근무) + reads.confirmedForConflictCheck 주입. 장면 3(lt·ltconf·ltpick) × W360/1.0·B320/2.0.
//   누르는 것: '열기', 장기 충돌 알림 '확인'(PNG 로 남긴다), ltpick 의 선택 가능한 날짜 하나(화면 선택만, 쓰기 없음).
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
import 'package:ALfit/models/core/application_model.dart';
import 'package:ALfit/models/core/to_model.dart';
import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/models/core/work_detail_data.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/services/schedule_conflict_service.dart';
import 'package:ALfit/utils/dialog_helper.dart';
import 'package:ALfit/widgets/dialogs/apply/apply_work_dialog.dart';
import 'package:ALfit/widgets/dialogs/apply/apply_work_reads.dart';

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

final kNow = DateTime.now();
final kWorkDate = DateTime(kNow.year, kNow.month, kNow.day).add(const Duration(days: 5));
DateTime _d(int plus) => kWorkDate.add(Duration(days: plus));
bool _weekday(DateTime d) => d.weekday <= DateTime.friday;
DateTime _nextWeekday(DateTime d) {
  var x = d;
  while (!_weekday(x)) {
    x = x.add(const Duration(days: 1));
  }
  return x;
}

DateTime _nextWeekend(DateTime d) {
  var x = d;
  while (_weekday(x)) {
    x = x.add(const Duration(days: 1));
  }
  return x;
}

/// 선택 가능한 첫 평일(시작일 D+5 이후), 충돌 두 날(그 뒤 평일), 범위 안 주말 하나.
final kPick = _nextWeekday(kWorkDate);
final kConf1 = _nextWeekday(_d(8));
final kConf2 = _nextWeekday(kConf1.add(const Duration(days: 2)));
final kWeekend = _nextWeekend(kWorkDate);

TOModel _to() => TOModel(
      id: 'to1',
      businessId: 'biz1',
      businessName: '강남 물류센터',
      type: 'contract',
      title: '강남 물류센터 상하차 장기 모집',
      creatorUID: 'admin1',
      status: TOStatus.active,
      deadlineType: 'NONE',
      hoursBeforeStart: 0,
      workDetails: const [],
      totalRequired: 4,
      totalConfirmed: 0,
      totalPending: 0,
      isPublished: true,
      publishMode: 'immediate',
      rangeStart: kWorkDate,
      rangeEnd: _d(20),
      workDays: const ['월', '화', '수', '목', '금'],
      createdAt: DateTime(2026, 9, 1),
      statusUpdatedAt: DateTime(2026, 9, 1),
    );

WorkDetailData _work() => WorkDetailData(
      wdId: 'wd1',
      workType: '상하차',
      workTypeIcon: 'box',
      workTypeColor: '#000000',
      workTypeBackgroundColor: '#FFFFFF',
      wage: 12000,
      wageType: 'hourly',
      requiredCount: 4,
      runtimeFull: false,
      startTime: '09:00',
      endTime: '18:00',
    );

/// 근무 기간 안 다른 사업장 확정 단기 근무(같은 시간대 → 장기 충돌).
ApplicationModel _confirmedOn(DateTime day, int i) => ApplicationModel(
      id: 'c$i',
      uid: 'u1',
      toId: 'toOther$i',
      businessId: 'bizOther',
      businessName: '성수 창고',
      toTitle: '다른 공고',
      selectedWorkType: '피킹',
      wdId: 'wdOther$i',
      startTime: '10:00',
      endTime: '15:00',
      wage: 12000,
      wageType: 'hourly',
      status: AppStatus.confirmed,
      workDate: day,
      appliedAt: DateTime(2026, 9, 25),
    );

ApplyWorkReads _reads(String sc) => ApplyWorkReads(
      applicationsForTO: ({required String toId, required String uid}) async => <ApplicationModel>[],
      confirmedSchedules: ({required String uid, required DateTime workDate}) async => <ApplicationModel>[],
      conflictsForWorkDetails: ({required DateTime workDate, required List<WorkDetailData> workDetails}) async =>
          <String, ConflictInfo>{},
      myApplicationsForTOFresh: (toId) async => <ApplicationModel>[],
      businessForPolicy: (businessId) async => null,
      confirmedForConflictCheck: () async =>
          sc == 'ltconf' ? [_confirmedOn(kConf1, 1), _confirmedOn(kConf2, 2)] : <ApplicationModel>[],
    );

ApplyWorkDialog _dialog(String sc) => ApplyWorkDialog(
      mainTO: _to(),
      workDetails: [_work()],
      businessName: '강남 물류센터',
      reads: _reads(sc),
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
  final phase = Platform.environment['DU278_PHASE'] ?? '';
  final run = Platform.environment['DU278_RUN'] == '1' && (phase == 'baseline' || phase == 'after');
  final after = phase == 'after';
  final nl = String.fromCharCode(10);

  setUpAll(() async {
    await initializeDateFormatting('ko_KR', null);
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
  });

  testWidgets('D278 $phase', (t) async {
    await t.runAsync(vqLoadFonts);
    t.platformDispatcher.localesTestValue = const [Locale('ko', 'KR')];
    t.platformDispatcher.localeTestValue = const Locale('ko', 'KR');
    final prevOnError = FlutterError.onError;
    final errors = <String>[];
    FlutterError.onError = (d) => errors.add(d.exceptionAsString().split(nl).first);
    var nPump = 0, nDrag = 0, nPng = 0, nTap = 0;
    var cur = '(시작)';
    Never stop(String why) {
      _out('D278-STOP ${jsonEncode({'at': cur, 'why': why, 'errors': errors})}');
      fail('$cur: $why');
    }

    void need(bool ok, String why) {
      if (!ok) stop(why);
    }

    Future<void> frames(int n) async {
      for (var i = 0; i < n; i++) {
        nPump++;
        need(nPump <= 4000 && nDrag <= 220 && nPng <= 260 && nTap <= 40, '사용량 한도'); // [DU278 r1] 보폭을 줄여 늘림 // [TB 보정] 6장면·긴 스크롤(1차 TB 한도 도달)
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
        for (final sc in const ['lt', 'ltconf', 'ltpick']) {
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
                        builder: (_) => _dialog(sc),
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
          // (DU273 에서 물려받은 처리) ltconf 는 열자마자 장기 충돌 알림(DU275 셸)이 뜬다.
          //   알림을 PNG 로 남기고 '확인'으로 닫은 뒤 시트를 잰다. 알림 넘침은 alertOverflow 로 따로 남긴다.
          final alertErrors = <String>[];
          if (sc == 'ltconf') {
            alertErrors.addAll(errors.where((e) => e.startsWith('A RenderFlex overflowed')));
            errors.removeWhere((e) => e.startsWith('A RenderFlex overflowed'));
            final okBtn = rich((p) => p == '확인');
            if (okBtn.evaluate().isNotEmpty) {
              nPng++;
              await vqCapture(t, key, 'D278-$phase-${c.id}_${sc}_alert', conditions: {
                'phase': phase, 'scene': '$sc 장기 충돌 알림', 'viewport': '${c.w.toInt()}x${c.h.toInt()}', 'textScaleFactor(기기)': c.s,
              });
              nTap++;
              await t.tap(nth(okBtn, -1)!, warnIfMissed: false);
              await frames(10);
              alertErrors.addAll(errors.where((e) => e.startsWith('A RenderFlex overflowed')));
              errors.removeWhere((e) => e.startsWith('A RenderFlex overflowed'));
            }
            need(rich((p) => p == '확인').evaluate().isEmpty, '자동 알림이 닫히지 않았다');
          }
          safe('대화 열림');
          if (sc == 'ltpick') {
            final day = find.byWidgetPredicate((w) => w is RichText && TextLayout.plain(w.text.toPlainText()) == '${kPick.day}');
            if (day.evaluate().isNotEmpty) {
              await t.ensureVisible(day.first);
              await frames(6);
              nTap++;
              await t.tap(day.first, warnIfMissed: false);
              await frames(8);
            }
            safe('날짜 선택 뒤');
          }
          Finder host() => find.byType(ApplyWorkDialog);
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

          List<Map<String, Object?>> measure() {
            final xs = <Map<String, Object?>>[];
            void add(String nm, Finder? f, {String? kind, Finder? box}) => xs.add(info(nm, f, kind: kind, box: box));
            Finder? one(String s, [int i = 0]) => nth(rich((p) => p == s), i);
            final sameMonth = kConf2.month == kWorkDate.month && _d(1).month == kWorkDate.month;
            add('구역 제목', one('희망 시작일을 선택하세요'), kind: 'sec');
            add('월 제목', nth(rich((p) => p.contains('년 ') && p.endsWith('월') && p.length <= 9), 0), kind: 'value');
            add('이전 달', glyph(Icons.chevron_left, 0), kind: 'fg:#60646F');
            add('요일', one('수'), kind: 'detail');
            add('주말', one('일'), kind: 'detail');
            if (sameMonth) {
              add('기간 밖 날', one('${_d(-1).day}'), kind: 'disabledDay');
              add('휴무 날', one('${kWeekend.day}'), kind: 'pair:#686C77/#F5F5F5');
              switch (sc) {
                case 'lt':
                  add('가능 날', one('${kPick.day}'), kind: 'pair:#3859E8/#EEF2FF');
                case 'ltconf':
                  add('충돌 전 근무일', one('${kPick.day}'), kind: 'pair:#686C77/#EEEEEE');
                case 'ltpick':
                  add('선택 날', one('${kPick.day}'), kind: 'cfm:#3859E8');
              }
            }
            add('범례 선택됨', one('선택됨'), kind: 'detail');
            add('범례 가능', one('선택가능'), kind: 'detail');
            add('범례 불가', one('선택불가'), kind: 'detail');
            add('일괄 안내', nth(rich((p) => p.contains('일괄 지원됩니다')), 0), kind: 'pair:#0D47A1/#E3F2FD');
            add('여러 업무 안내', nth(rich((p) => p.startsWith('같은 시간대에')), 0), kind: 'pair:#0D47A1/#E3F2FD');
            if (sc == 'ltconf') {
              add('경고 제목', one('기간 내 확정된 근무가 있습니다'), kind: 'pair:#946200/#FFF5D6');
              add('경고 목록', nth(rich((p) => p.contains('(성수 창고)')), 0), kind: 'warnRaw');
              add('선택 가능일', nth(rich((p) => p.endsWith('부터 선택 가능') || p == '선택 가능한 날짜가 없습니다'), 0),
                  kind: 'pair:#0D47A1/#FFFFFF');
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
            await vqCapture(t, key, 'D278-$phase-${c.id}_$sc$suffix', conditions: {
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
              // [DU278 r1] 보폭 0.5 → 0.4: 높이 0.5~0.6 블록이 어느 화면에도 통째로 들어오지 않을 수 있었다(seenOk 는 0.6)
              pos.jumpTo(math.min(pos.pixels + vp.height * 0.4, pos.maxScrollExtent));
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
          _out('D278 ${jsonEncode({'phase': phase, 'cond': c.id, 'scene': sc, 'overflow': overflow, 'alertOverflow': alertErrors, 'atEnd': atEnd, 'shots': shots,
                'seen': seen.toList(), 'counts': {'pump': nPump, 'drag': nDrag, 'png': nPng, 'tap': nTap}})}');
        }
      }
      await t.pumpWidget(const SizedBox.shrink());
      await frames(1);
      safe('END 전');
      _out('D278-END ${jsonEncode({'pump': nPump, 'drag': nDrag, 'png': nPng, 'tap': nTap})}');
    } finally {
      FlutterError.onError = prevOnError;
      t.platformDispatcher.clearLocalesTestValue();
      t.platformDispatcher.clearLocaleTestValue();
      t.platformDispatcher.clearTextScaleFactorTestValue();
      t.view.reset();
    }
  }, skip: !run, timeout: const Timeout(Duration(minutes: 6)));
}
