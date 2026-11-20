// ignore_for_file: depend_on_referenced_packages
// [DU257 S068 중간정산 요청 + 공용 AppBatchActionBar 시안 정렬 baseline/after] Codex 한도 중 Claude 자체 진행(허브 DU_self_review_hub_2026-11-10).
//   같은 시험을 교정 전(baseline)·후(after)에 한 번씩 돌린다. 시험은 production 을 편집하지 않는다.
//   DU257_RUN=1 이고 DU257_PHASE 가 baseline 또는 after 일 때만 실행한다(기본 skip).
//   standalone(home: InterimSettlementRequestScreen(reads: 대역)) + UserProvider·NotificationProvider. 제출(쓰기) 없음.
//   장면 5(list·selected(카드 2개 탭)·empty·error·bar(공용 바 단독 — 관리자 '이체 완료 처리' 모양)) × W360/1.0·B320/2.0.
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
import 'package:ALfit/models/core/wage_detail_model.dart';
import 'package:ALfit/providers/notification_provider.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/screens/user/interim_settlement_reads.dart';
import 'package:ALfit/screens/user/interim_settlement_request_screen.dart';
import 'package:ALfit/theme/role_theme.dart';
import 'package:ALfit/utils/format_helper.dart';
import 'package:ALfit/utils/text_layout.dart';
import 'package:ALfit/widgets/common/app_batch_action_bar.dart';

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
      uid: 'u1', username: 'u1', name: '김근로', email: 'u1@alfit.local', role: UserRole.USER,
      homeRegion: const UserRegion(province: '서울특별시', city: '강남구'), accountStatus: 'active');
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

const _bizName = '강남 물류센터 제2물류동 야간 분류팀';
final DateTime _today = FormatHelper.toKstDate(DateTime.now());
DateTime _day(int o) => _today.add(Duration(days: o));

ApplicationModel _app() => ApplicationModel(
      id: 'a1', toId: 'to1', uid: 'u1', businessId: 'biz1', businessName: _bizName, toTitle: '단기 공고',
      status: AppStatus.confirmed, selectedWorkType: '상하차', startTime: '09:00', endTime: '18:00',
      wage: 12000, workDate: _day(-3), appliedAt: _day(-10));

AttendanceModel _att(String id, DateTime d, {int? total, int? tax}) => AttendanceModel(
      id: id, applicationId: 'a1', userId: 'u1', businessId: 'biz1', businessName: _bizName, workDate: d,
      workType: '상하차', status: AttendanceModel.statusPresent, wageStatus: AttendanceModel.wageConfirmed,
      adminConfirmed: true, finalWage: total, checkInAt: d.add(const Duration(hours: 9)),
      checkOutAt: d.add(const Duration(hours: 18)), createdAt: d,
      wageDetail: total == null
          ? null
          : WageDetailModel(wageType: 'hourly', baseWage: 12000, totalAmount: total, incomeTaxDeduction: tax ?? 0,
              netWage: total - (tax ?? 0)),
    );

// 실수령 104,436 · 52,218(세전 108,000 · 54,000), 그리고 급여 상세가 없는 확정 근무 1건.
final _atts = [
  _att('w1', _day(-3), total: 108000, tax: 3564),
  _att('w2', _day(-4), total: 54000, tax: 1782),
  _att('w3', _day(-5)),
];

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

/// 글자 단위 줄 나눔 — 줄마다 보이는 글자, 그리고 '낱말 안에서 끊긴' 곳 수(DU256 과 같은 규칙).
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
    if (bx.isEmpty || ch == ' ' || ch == zw || ch == String.fromCharCode(10)) {
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
  final phase = Platform.environment['DU257_PHASE'] ?? '';
  final run = Platform.environment['DU257_RUN'] == '1' && (phase == 'baseline' || phase == 'after');
  final after = phase == 'after';
  final nl = String.fromCharCode(10);

  setUp(() => SharedPreferences.setMockInitialValues({}));
  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
    await initializeDateFormatting('ko_KR', null);
  });

  testWidgets('D257 $phase', (t) async {
    await t.runAsync(vqLoadFonts);
    t.platformDispatcher.localesTestValue = const [Locale('ko', 'KR')];
    t.platformDispatcher.localeTestValue = const Locale('ko', 'KR');
    final prevOnError = FlutterError.onError;
    final errors = <String>[];
    FlutterError.onError = (d) => errors.add(d.exceptionAsString().split(nl).first);
    var nPump = 0, nDrag = 0, nPng = 0, nTap = 0;
    var cur = '(시작)';
    Never stop(String why) {
      _out('D257-STOP ${jsonEncode({'at': cur, 'why': why, 'errors': errors})}');
      fail('$cur: $why');
    }

    void need(bool ok, String why) {
      if (!ok) stop(why);
    }

    Future<void> frames(int n) async {
      for (var i = 0; i < n; i++) {
        nPump++;
        need(nPump <= 1200 && nDrag <= 60 && nPng <= 80 && nTap <= 12, '사용량 한도');
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

    Finder? glyph(IconData icon, int i) =>
        nth(find.descendant(of: find.byIcon(icon, skipOffstage: false), matching: find.byType(RichText), skipOffstage: false), i);
    Finder? anc(Finder? f, bool Function(Widget w) p) =>
        f == null ? null : find.ancestor(of: f, matching: find.byWidgetPredicate(p, skipOffstage: false));

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
        for (final sc in const ['list', 'selected', 'empty', 'error', 'bar']) {
          cur = '${c.id} $sc';
          await t.pumpWidget(const SizedBox.shrink());
          await frames(1);
          safe('장면 종료');
          overflow.clear();
          t.view.physicalSize = Size(c.w, c.h);
          t.view.devicePixelRatio = 1.0;
          t.platformDispatcher.textScaleFactorTestValue = c.s;
          final screen = Rect.fromLTWH(0, 0, c.w, c.h);
          final reads = InterimSettlementReads(
            myMonthlyAttendances: ({required String userId, required int year, required int month}) async {
              if (sc == 'error') throw Exception('du257-read-failed');
              if (sc == 'empty') return <AttendanceModel>[];
              return _atts.where((a) => a.workDate.year == year && a.workDate.month == month).toList();
            },
          );
          final Widget home = sc == 'bar'
              ? Scaffold(
                  body: const SizedBox.expand(),
                  bottomNavigationBar: SafeArea(
                    top: false,
                    child: AppBatchActionBar(
                      selectedCount: 12,
                      selectedAmount: 123456789,
                      onSelectAll: () {},
                      onDeselectAll: () {},
                      onAction: () {},
                      actionLabel: '이체 완료 처리',
                      actionIcon: Icons.send,
                    ),
                  ),
                )
              : InterimSettlementRequestScreen(app: _app(), reads: reads);
          await t.pumpWidget(MultiProvider(
            providers: [
              ChangeNotifierProvider<UserProvider>(create: (_) => _P()),
              ChangeNotifierProvider<NotificationProvider>(create: (_) => NotificationProvider()),
            ],
            child: RepaintBoundary(
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
                home: home,
              ),
            ),
          ));
          await frames(14);
          safe('첫 화면');

          final amt1 = FormatHelper.formatWage(104436);
          final amt2 = FormatHelper.formatWage(52218);
          if (sc == 'selected') {
            for (final a in [amt1, amt2]) {
              final f = nth(rich((p) => p == a), 0);
              need(f != null, '카드 금액 $a 없음');
              await t.ensureVisible(f!);
              await frames(4);
              nTap++;
              await t.tap(f, warnIfMissed: false);
              await frames(4);
              safe('카드 탭');
            }
          }

          Finder? sfOf() {
            final f = find.descendant(of: find.byType(ListView), matching: find.byType(Scrollable), skipOffstage: false);
            return f.evaluate().isEmpty ? null : nth(f, 0);
          }

          Map<String, Object?> info(String nm, Finder? f, {String? kind, bool lines = false, Finder? box, bool deco = false}) {
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
            String? radius, side, face;
            if (deco) {
              f.evaluate().first.visitAncestorElements((a) {
                final w = a.widget;
                if (w is DecoratedBox && w.decoration is BoxDecoration && (w.decoration as BoxDecoration).borderRadius != null) {
                  final d = w.decoration as BoxDecoration;
                  radius = (d.borderRadius! as BorderRadius).topLeft.x.toString();
                  side = d.border == null ? 'none' : _hex((d.border! as Border).top.color);
                  face = d.color == null ? null : _hex(d.color!);
                  return false;
                }
                return true;
              });
            }
            return {
              'name': nm, 'kind': kind, 'present': true, 'rect': lt(r), 'visible': inside(r, screen) && inside(r, vp),
              'fontSize': rp.text.style?.fontSize, 'weight': rp.text.style?.fontWeight?.value,
              'fg': fg == null ? null : _hex(fg), 'bg': _hex(bg),
              'contrast': fg == null ? null : double.parse(_contrast(fg, bg).toStringAsFixed(2)),
              'didExceedMaxLines': rp.didExceedMaxLines, 'maxLines': rp.maxLines,
              if (li != null) 'lines': li.lines,
              if (li != null) 'sylBreaks': li.sylBreaks,
              if (br != null) 'boxH': r1(br.height),
              if (deco) 'radius': radius,
              if (deco) 'side': side,
              if (deco) 'face': face,
            };
          }

          final datePat = RegExp('^[0-9]{2}[.][0-9]{2} [(]');
          List<Map<String, Object?>> measure() {
            final selAll = nth(rich((p) => p == '전체선택'), 0);
            final clear = nth(rich((p) => p == '해제'), 0);
            final act = nth(rich((p) => p.endsWith('중간정산 요청') || p.endsWith('이체 완료 처리')), 0);
            final actEnabled = act != null &&
                (anc(act, (w) => w is ElevatedButton)!.evaluate().isNotEmpty) &&
                t.widget<ElevatedButton>(anc(act, (w) => w is ElevatedButton)!.first).onPressed != null;
            if (sc == 'bar') {
              return [
                info('바 전체선택', selAll, kind: 'barText', lines: true, box: anc(selAll, (w) => w is TextButton)),
                info('바 해제', clear, kind: 'barText', lines: true, box: anc(clear, (w) => w is TextButton)),
                info('바 금액', nth(rich((p) => p == FormatHelper.formatWage(123456789)), 0), kind: 'amount'),
                info('바 실행', act, kind: actEnabled ? 'action' : 'actionDisabled', lines: true, box: anc(act, (w) => w is ElevatedButton)),
              ];
            }
            if (sc == 'empty' || sc == 'error') {
              return [
                info('빈 제목', nth(rich((p) => p == '정산 가능한 출근기록이 없습니다'), 0)),
                info('오류 제목', nth(rich((p) => p == '정산 가능한 근무를 확인하지 못했습니다'), 0)),
              ];
            }
            final dates = rich((p) => datePat.hasMatch(p));
            return [
              // [v1 보강] 앱바 제목·본문 첫 줄 사업장명(P9)
              info('제목', nth(rich((p) => p.startsWith('중간정산 요청') && !p.contains('건')), 0), kind: 'title', lines: true),
              info('사업장명', nth(rich((p) => p == _bizName), 0), kind: 'name', lines: true),
              info('배너', nth(rich((p) => p.startsWith('급여 확정된 근무일 중')), 0), kind: 'aux', lines: true, deco: true),
              info('배너 아이콘', glyph(Icons.info_outline, 0), kind: 'brandIcon'),
              info('입력 힌트', nth(rich((p) => p == '요청 사유 (선택사항)'), 0), kind: 'hint', lines: true),
              info('입력 아이콘', glyph(Icons.edit_note, 0), kind: 'icon2'),
              info('입력 글자수', nth(rich((p) => p == '0/100'), 0)),
              info('C1 날짜', nth(dates, 0), kind: 'date', deco: true),
              info('C1 시각', nth(rich((p) => p.contains(' ~ ') && p.length <= 13), 0), kind: 'aux'),
              info('C1 금액', nth(rich((p) => p == amt1), 0), kind: 'amount'),
              info('C1 세전', nth(rich((p) => p.startsWith('세전 ')), 0), kind: 'aux'),
              info('C2 날짜', nth(dates, 1), kind: 'date', deco: true),
              info('C3 날짜', nth(dates, 2), kind: 'dim', deco: true),
              info('C3 없음', nth(rich((p) => p == '급여 정보 없음'), 0), kind: 'dim'),
              info('원 아이콘', glyph(Icons.radio_button_unchecked, 0), kind: 'dimIcon'),
              info('체크 아이콘', glyph(Icons.check_circle, 0), kind: 'checkIcon'),
              info('자물쇠', glyph(Icons.lock_outline, 0), kind: 'dimIcon'),
              info('바 전체선택', selAll, kind: 'barText', lines: true, box: anc(selAll, (w) => w is TextButton)),
              info('바 해제', clear, kind: 'barText', lines: true, box: anc(clear, (w) => w is TextButton)),
              info('바 금액', nth(rich((p) => p == FormatHelper.formatWage(156654)), 0), kind: 'amount'),
              info('바 실행', act, kind: actEnabled ? 'action' : 'actionDisabled', lines: true, box: anc(act, (w) => w is ElevatedButton)),
            ];
          }

          void afterChecks(List<Map<String, Object?>> xs, String at) {
            if (!after) return;
            for (final x in xs) {
              if (x['present'] != true || x['visible'] != true) continue;
              final k = x['kind'];
              final cst = x['contrast'];
              need(x['didExceedMaxLines'] != true, '$at 말줄임/잘림 $x');
              final sb = x['sylBreaks'];
              if (sb is int) need(sb == 0, '$at 음절 끊김 $x');
              final h = x['boxH'] as double?;
              switch (k) {
                case 'aux':
                  need(x['fg'] == '#60646F' && cst is double && cst >= 4.5, '$at 보조 글자 $x');
                case 'brandIcon' || 'checkIcon':
                  need(x['fg'] == '#3859E8', '$at 대표색 아이콘 $x');
                case 'icon2':
                  need(x['fg'] == '#60646F', '$at 입력 아이콘 $x');
                case 'date' || 'amount':
                  need(x['fg'] == '#21242D' && cst is double && cst >= 4.5, '$at 본문색 $x');
                case 'dim' || 'dimIcon':
                  need(x['fg'] == '#686C77', '$at 흐린 줄 $x');
                case 'barText':
                  need(x['fg'] == '#3859E8' && x['bg'] == '#FFFFFF' && cst is double && cst >= 4.5 && (h ?? 0) >= 48, '$at 바 선택 행동 $x');
                case 'action':
                  need(x['fg'] == '#FFFFFF' && x['bg'] == '#3859E8' && (h ?? 0) >= 48, '$at 바 실행 $x');
                case 'actionDisabled':
                  need((h ?? 0) >= 48, '$at 바 실행(비활성) 높이 $x');
                case 'title': // [v1] 제목은 짧게(P9)
                  need(TextLayout.plain((x['lines'] as List).join(' ')) == '중간정산 요청', '$at 제목 $x');
                case 'name': // [v1] 본문 첫 줄 사업장명(P9)
                  need(x['fg'] == '#21242D' && x['maxLines'] == null && x['fontSize'] == 16.0, '$at 사업장명 $x');
              }
              if (x.containsKey('radius') && (k == 'date' || k == 'dim')) {
                final selectedCard = sc == 'selected' && k == 'date';
                need(x['radius'] == '16.0', '$at 카드 반경 $x');
                need(x['side'] == (selectedCard ? '#3859E8' : '#EEEEEE'), '$at 카드 선 $x');
                need(x['face'] == (selectedCard ? '#EEF2FF' : (k == 'dim' ? '#FAFAFA' : '#FFFFFF')), '$at 카드 면 $x');
              }
              if (x['name'] == '배너') {
                need(x['face'] == '#EEF2FF' && x['radius'] == '12.0' && x['side'] == 'none', '$at 배너 면 $x');
              }
            }
          }

          final shots = <Map<String, Object?>>[];
          Future<void> snap(String suffix) async {
            final xs = measure();
            afterChecks(xs, suffix.isEmpty ? '첫 화면' : suffix);
            nPng++;
            await vqCapture(t, key, 'D257-$phase-${c.id}_$sc$suffix', conditions: {
              'phase': phase, 'scene': sc, 'viewport': '${c.w.toInt()}x${c.h.toInt()}', 'textScaleFactor(기기)': c.s,
            });
            final sf = sfOf();
            shots.add({'shot': suffix.isEmpty ? 'top' : suffix, 'texts': xs,
              'pixels': sf == null ? null : r1(t.state<ScrollableState>(sf).position.pixels)});
          }

          await snap('');
          var atEnd = true;
          if ((sc == 'list' || sc == 'selected') && sfOf() != null) {
            var k = 0;
            while (k < 12) {
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
          _out('D257 ${jsonEncode({'phase': phase, 'cond': c.id, 'scene': sc, 'overflow': overflow, 'atEnd': atEnd, 'shots': shots,
                'counts': {'pump': nPump, 'drag': nDrag, 'png': nPng, 'tap': nTap}})}');
        }
      }
      await t.pumpWidget(const SizedBox.shrink());
      await frames(1);
      safe('END 전');
      _out('D257-END ${jsonEncode({'pump': nPump, 'drag': nDrag, 'png': nPng, 'tap': nTap})}');
    } finally {
      FlutterError.onError = prevOnError;
      t.platformDispatcher.clearLocalesTestValue();
      t.platformDispatcher.clearLocaleTestValue();
      t.platformDispatcher.clearTextScaleFactorTestValue();
      t.view.reset();
    }
  }, skip: !run, timeout: const Timeout(Duration(minutes: 5)));
}
