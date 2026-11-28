// [DU549 · 배치만] 공고 날짜 선택기(TODateSelector) 큰 글자 B 넘침 교정 — 감사138 F138-DATESELECTOR-B-LAYOUT 중 감사141 §5가 정한 '확정 39px Row' 하나.
//   장기 preset(PERIOD)의 '근무 시작 가능기간' 제목 + '필수' 표지 Row(to_date_selector.dart:1054:9 · DU542b TA 39px 오른쪽 넘침) → Wrap(표지만 다음 줄).
//   판정(감사141:74–76): B 는 전문 · reflow · 말줄임/숨김/글자축소 0 · FittedBox/clamp 금지. 문구 · 색 · 조건 · 콜백 · 값 변경 0.
//   before = 현재 A(to_date_selector 49f75c2e = DU542b 채택판) 기록 · strict = 후보(b062e68c).
//   하네스 = du542b-todateselector-followup 시험 그대로(위젯 직접 pump · RoleTheme · 상태 부모 _Host · 플랫폼 메시지 전수 관찰 · HTTP 차단 · 수정 화면 소스 읽기).
//     더한 것: PERIOD 의 att lay(제목 · 표지가 화면 ∩ 스크롤 칸 안 · 제목 한 줄 · 표지 자리 · 선택기 기준 좌표) · strict 화면 전체 넘침 0(W · B 모두).
//   사례 6: EMPTY · MULTI · RANGE · LOCKED · PERIOD · CUSTOM. 누르는 것: MULTI · RANGE 의 오늘 날짜 칸 1번씩만(그 밖 버튼 · 저장 · 게시 0).
//   W 390×844@1.0(7열 달력) · B 320×640@2.0(날짜 목록). 실행일 의존(주말 칸 수 · 선택 칸 수)은 need 로 막는다.
//   W 배치 변화 0 은 att lay 의 tg/cg/dg(선택기 기준 좌표)를 TB · TA 에서 손으로 대조한다.
//   기본 skip — TB before/du549-tb/DU_BEFORE_OBSERVE=549 · TA after/du549-ta/없음.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:ALfit/screens/business_admin/to_management/widgets/to_date_selector.dart';
import 'package:ALfit/theme/app_colors.dart';
import 'package:ALfit/theme/role_theme.dart';
import 'package:ALfit/utils/format_helper.dart';
import 'package:ALfit/utils/navigation_key.dart';

import 'support/du1_vq_capture.dart';
import 'support/visible_text.dart';

/// 원래 경로로 보내는 Flutter 기반 채널과 이유(DU536 · DU540 · DU542 와 같은 표).
const _frameworkAllow = <String, String>{
  'flutter/assets': 'AssetBundle(아이콘 글꼴 · 이미지 매니페스트) 읽기',
  'flutter/platform': 'MaterialApp Title · SystemSound/Haptic(InkWell 탭 피드백)',
  'flutter/navigation': '루트 Navigator 경로 보고',
  'flutter/mousecursor': 'MouseRegion 커서 갱신(시험 포인터)',
  'flutter/restoration': 'RootRestorationScope 상태 복원 조회',
  'flutter/keyboard': 'HardwareKeyboard 상태 동기화',
  'flutter/accessibility': '의미 트리/알림 전달',
};

/// 모든 플랫폼 메시지 관찰 — 기반 채널은 원래 경로, 나머지(CF · Firestore · 그 밖)는 이름을 기록하고 응답 null.
class _Wire {
  final unexpected = <String>[];

  Future<ByteData?>? route(TestDefaultBinaryMessenger m, String channel, MessageHandler? handler, ByteData? message) {
    if (_frameworkAllow.containsKey(channel)) {
      return handler != null ? handler(message) : m.delegate.send(channel, message);
    }
    unexpected.add(channel);
    return null;
  }
}

/// 외부 HTTP 차단 — 만들려는 시도를 기록하고 실패시킨다.
class _NoHttp extends HttpOverrides {
  final tries = <String>[];

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    tries.add('createHttpClient');
    throw const SocketException('DU549 관측 — 외부 HTTP 차단');
  }
}

Future<void> _loadFonts() async {
  Future<ByteData> b(String p) => File(p).readAsBytes().then((x) => ByteData.view(x.buffer));
  for (final fam in const ['NotoSansKR', 'Roboto']) {
    await (FontLoader(fam)
          ..addFont(b('assets/fonts/NotoSansKR-Regular.ttf'))
          ..addFont(b('assets/fonts/NotoSansKR-Bold.ttf')))
        .load();
  }
  await (FontLoader('FlutterTest')..addFont(b('assets/fonts/NotoSansKR-Regular.ttf'))).load();
  await (FontLoader('MaterialIcons')
        ..addFont(b('C:/Users/kug02/flutter/bin/cache/artifacts/material_fonts/materialicons-regular.otf')))
      .load();
}

void _out(String s) {
  // ignore: avoid_print
  print(s);
}

String _enc(String s) => s.isEmpty ? '-' : base64Url.encode(utf8.encode(s)).replaceAll('=', '');

String _hex(Color col) {
  String h(double x) => (x * 255).round().toRadixString(16).padLeft(2, '0');
  return '${h(col.a)}${h(col.r)}${h(col.g)}${h(col.b)}';
}

String _h(Color? c) => c == null ? '-' : _hex(c);

/// WCAG 대비 — [fg] 글자(알파 있으면 바탕에 얹는다) · [bg] 불투명 바탕.
double _contrast(Color fg, Color bg) {
  final a = Color.alphaBlend(fg, bg).computeLuminance();
  final b = bg.computeLuminance();
  final hi = a > b ? a : b;
  final lo = a > b ? b : a;
  return (hi + 0.05) / (lo + 0.05);
}

/// 면 [face] 를 섹션 카드 흰 바탕(TOSectionContainer = Colors.white)에 얹었을 때 [fg] 대비 ≥ 4.5.
bool _ok(Color fg, Color face) => _contrast(fg, Color.alphaBlend(face, Colors.white)) >= 4.5;

/// 값이 모두 같으면 그 값, 아니면 '-'.
String _one(Iterable<String> xs) {
  final s = xs.toSet();
  return s.length == 1 ? s.first : '-';
}

/// 시각 오류 수집 — 넘침은 원문 + 위치, 그 밖 framework 오류는 원문.
class _Seen {
  final overflows = <String>[];
  final other = <String>[];

  void add(FlutterErrorDetails d) {
    final m = d.exceptionAsString();
    if (m.contains('overflowed')) {
      final full = d.toString();
      final k = full.indexOf('The relevant error-causing widget was');
      final loc = k < 0
          ? ''
          : full.substring(k).split('\n').skip(1).where((l) => l.trim().isNotEmpty).take(2).map((l) => l.trim()).join(' ');
      overflows.add('${m.split('\n').first} @ $loc');
    } else {
      other.add(m);
    }
  }
}

/// Text 하나의 글자색(style 에 색이 없으면 검정으로 적는다).
Color _fgOf(WidgetTester t, Finder f) => t.widget<Text>(f).style?.color ?? Colors.black;

/// [f] 에서 가장 가까운 Container 의 면 색 · 테두리 색(Border 윗변 · 없으면 '-').
({Color face, String bd}) _boxOf(WidgetTester t, Finder f) {
  final box = t.widget<Container>(find.ancestor(of: f, matching: find.byType(Container)).first);
  final d = box.decoration;
  final face = d is BoxDecoration ? (d.color ?? Colors.transparent) : (box.color ?? Colors.transparent);
  final b = d is BoxDecoration ? d.border : null;
  return (face: face, bd: b is Border ? _hex(b.top.color) : '-');
}

/// [f] 에서 가장 가까운 Material 의 색.
Color _matOf(WidgetTester t, Finder f) => t.widget<Material>(find.ancestor(of: f, matching: find.byType(Material)).first).color ?? Colors.transparent;

/// [box] 안 아이콘 [icon] 하나의 색 — 하나가 아니면 null.
Color? _iconIn(WidgetTester t, Finder box, IconData icon) {
  final f = find.descendant(of: box, matching: find.byIcon(icon), skipOffstage: true);
  if (f.evaluate().length != 1) return null;
  return t.widget<Icon>(f).color;
}

bool _inside(Rect a, Rect b) => a.left >= b.left - 0.5 && a.top >= b.top - 0.5 && a.right <= b.right + 0.5 && a.bottom <= b.bottom + 0.5;

/// 하나가 끌기 없이 보이고 눌리는가 — 화면 ∩ 가까운 Scrollable 칸 안 + 중심 hit(DU537 · DU538 r2 · DU540 · DU542 `_tapNow` 와 같은 식).
({bool vis, bool hit}) _tapNow(WidgetTester t, Finder f, Rect screen) {
  var area = screen;
  final scF = find.ancestor(of: f, matching: find.byType(Scrollable));
  if (scF.evaluate().isNotEmpty) area = area.intersect(t.getRect(scF.first));
  final r = t.getRect(f);
  final vis = _inside(r, area);
  final hit = t.hitTestOnBinding(r.center).path.any((x) => identical(x.target, t.renderObject(f)));
  return (vis: vis, hit: hit);
}

bool _sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

DateTime _day(DateTime today, int add) => DateTime(today.year, today.month, today.day + add);

/// 날짜 하나의 칸 — 목록(B · 확대 글자)은 '11월 20일 (금)' 줄 글, 7열(W)은 날짜 숫자 글.
Finder _dayFinder(Finder calF, DateTime d, bool list) => list
    ? find.descendant(of: calF, matching: findVisibleText(FormatHelper.formatDateKorean(d)), skipOffstage: true)
    : find.descendant(of: calF, matching: find.text(d.day.toString()), skipOffstage: true);

/// 달력이 날짜 목록 모양인가(오늘 줄 글이 있으면 목록 · 7열에는 숫자만 있다).
bool _isList(Finder calF, DateTime today) =>
    find.descendant(of: calF, matching: findVisibleText(FormatHelper.formatDateKorean(today)), skipOffstage: true).evaluate().length == 1;

final String _wBrand = _hex(AppColors.brand);
final String _wWhite = _hex(Colors.white);
final String _wClear = _hex(Colors.transparent);
final String _wLine = _hex(AppColors.border);
final String _wText1 = _hex(AppColors.textPrimary);
final String _wText2 = _hex(AppColors.textSecondary);
final String _wText3 = _hex(AppColors.textTertiary);
final String _wGrey50 = _hex(AppColors.grey50);
final String _wGrey100 = _hex(AppColors.grey100);
final String _wGrey300 = _hex(AppColors.grey300);
final String _wGrey600 = _hex(AppColors.grey600);
final String _wGrey700 = _hex(AppColors.grey700);
final String _wErrBg = _hex(AppColors.errorBg);
final String _wErrDark = _hex(AppColors.errorDark);
final String _wWarnDark = _hex(AppColors.warningDark);

/// 사례 설정 — 작성 화면(create_to_screen.dart:1959) · 수정 화면(edit_to_screen.dart:1402)이 넘기는 인자와 같은 모양.
typedef _Cfg = ({bool longTerm, bool readOnly, List<DateTime> dates, String? period, DateTime? start, DateTime? from, DateTime? until, List<String> weekdays, List<String>? workDays});

_Cfg _cfgOf(String id, DateTime today) {
  switch (id) {
    case 'MULTI':
      return (longTerm: false, readOnly: false, dates: [for (var i = 1; i <= 14; i++) _day(today, i)], period: null, start: null, from: null, until: null,
          weekdays: const <String>[], workDays: null);
    case 'LOCKED':
      return (longTerm: true, readOnly: true, dates: const <DateTime>[], period: '3months', start: _day(today, 3), from: _day(today, 3), until: _day(today, 14),
          weekdays: const <String>[], workDays: const <String>['월', '화', '수', '목', '금']);
    case 'PERIOD':
      return (longTerm: true, readOnly: false, dates: const <DateTime>[], period: '1month', start: null, from: _day(today, 3), until: _day(today, 17),
          weekdays: const <String>['월', '수', '금', '토'], workDays: null);
    case 'CUSTOM':
      return (longTerm: true, readOnly: false, dates: const <DateTime>[], period: 'custom', start: _day(today, 3), from: null, until: null,
          weekdays: const <String>[], workDays: null);
    default:
      return (longTerm: false, readOnly: false, dates: const <DateTime>[], period: null, start: null, from: null, until: null, weekdays: const <String>[], workDays: null);
  }
}

/// 상태를 든 작은 부모 — 날짜 토글 · 전체 해제는 선택 목록을 바꾸고(작성 화면과 같은 동작), 모든 콜백은 이름별로 센다.
class _Host extends StatefulWidget {
  const _Host({super.key, required this.cfg, required this.calls});
  final _Cfg cfg;
  final Map<String, int> calls;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  late List<DateTime> _dates = List<DateTime>.of(widget.cfg.dates);

  void _hit(String k) => widget.calls[k] = (widget.calls[k] ?? 0) + 1;

  @override
  Widget build(BuildContext context) {
    final c = widget.cfg;
    return TODateSelector(
      isLongTerm: c.longTerm,
      isReadOnly: c.readOnly,
      selectedDates: _dates,
      onDateToggle: (d) {
        _hit('toggle');
        setState(() {
          final had = _dates.any((x) => _sameDay(x, d));
          _dates = had ? _dates.where((x) => !_sameDay(x, d)).toList() : <DateTime>[..._dates, d];
        });
      },
      onClearAll: () {
        _hit('clear');
        setState(() => _dates = <DateTime>[]);
      },
      rangeStart: c.start,
      selectedWeekdays: c.weekdays,
      onRangeStartChanged: (_) => _hit('rangeStart'),
      onRangeEndChanged: (_) => _hit('rangeEnd'),
      onWeekdayToggle: (_) => _hit('weekday'),
      contractPeriodType: c.period,
      onContractPeriodTypeChanged: (_) => _hit('period'),
      workStartAvailableFrom: c.from,
      workStartAvailableUntil: c.until,
      onWorkStartAvailableFromChanged: (_) => _hit('from'),
      onWorkStartAvailableUntilChanged: (_) => _hit('until'),
      displayWorkDays: c.workDays,
    );
  }
}

// ── 측정(위젯 값만 · rect 는 _tapNow 한 곳) — 출력 줄은 sub 마다 하나 ──

typedef _QuickObs = ({int n, int act, String face, String icon, String fg, bool cr});

/// 빠른 선택 세 칸(오늘 · 이번 주 · 다음 주) — 고른 것(면 = primaryColor) 수와 고르지 않은 것의 면 · 아이콘 · 글 색.
_QuickObs _quickLine(WidgetTester t, String tok, Color prim) {
  final faces = <String>[];
  final icons = <String>[];
  final fgs = <String>[];
  var n = 0;
  var act = 0;
  var cr = true;
  for (final ic in const [Icons.today, Icons.view_week, Icons.next_week]) {
    final iF = find.byIcon(ic);
    if (iF.evaluate().length != 1) continue;
    n++;
    final face = _matOf(t, iF);
    if (face == prim) {
      act++;
      continue;
    }
    final iconC = t.widget<Icon>(iF).color ?? Colors.black;
    final txt = find.descendant(of: find.ancestor(of: iF, matching: find.byType(Column)).first, matching: find.byType(Text), skipOffstage: true);
    final fgC = txt.evaluate().length == 1 ? _fgOf(t, txt) : Colors.black;
    faces.add(_hex(face));
    icons.add(_hex(iconC));
    fgs.add(_hex(fgC));
    cr = cr && _ok(fgC, face) && _ok(iconC, face);
  }
  final faceAll = _one(faces);
  final iconAll = _one(icons);
  final fgAll = _one(fgs);
  final crOk = cr && faces.isNotEmpty;
  _out('D549 $tok att quick n=$n act=$act face=$faceAll icon=$iconAll fg=$fgAll cr45=$crOk');
  return (n: n, act: act, face: faceAll, icon: iconAll, fg: fgAll, cr: crOk);
}

typedef _NavObs = ({int n, String face, String icon, String title, bool cr});

/// 달력 머리 — 월 이동 두 원(면 · 화살표 색)과 월 제목 글 색(그대로).
_NavObs _navLine(WidgetTester t, String tok, DateTime month) {
  final faces = <String>[];
  final icons = <String>[];
  var n = 0;
  var cr = true;
  for (final ic in const [Icons.chevron_left, Icons.chevron_right]) {
    final iF = find.byIcon(ic);
    if (iF.evaluate().length != 1) continue;
    n++;
    final face = _boxOf(t, iF).face;
    final iconC = t.widget<Icon>(iF).color ?? Colors.black;
    faces.add(_hex(face));
    icons.add(_hex(iconC));
    cr = cr && _ok(iconC, face);
  }
  final tF = find.text(FormatHelper.formatYearMonth(month));
  final titleC = tF.evaluate().length == 1 ? _fgOf(t, tF) : null;
  final title = _h(titleC);
  final crOk = cr && n == 2 && titleC != null && _ok(titleC, Colors.white);
  final faceAll = _one(faces);
  final iconAll = _one(icons);
  _out('D549 $tok att nav n=$n face=$faceAll icon=$iconAll title=$title cr45=$crOk');
  return (n: n, face: faceAll, icon: iconAll, title: title, cr: crOk);
}

typedef _ToggleObs = ({int n, String face, String fg, bool cr});

/// '캘린더 접기' 줄(그대로).
_ToggleObs _toggleLine(WidgetTester t, String tok) {
  final tF = find.text('캘린더 접기');
  final n = tF.evaluate().length;
  var face = '-';
  var fg = '-';
  var cr = false;
  if (n == 1) {
    final fc = _matOf(t, tF);
    final gc = _fgOf(t, tF);
    face = _hex(fc);
    fg = _hex(gc);
    cr = _ok(gc, fc);
  }
  _out('D549 $tok att toggle n=$n face=$face fg=$fg cr45=$cr');
  return (n: n, face: face, fg: fg, cr: cr);
}

typedef _WkhObs = ({int n, String wkd, String wke, double worst});

/// 요일 머리(7열만) — 평일 · 주말 글 색과 7칸 중 가장 낮은 흰 바탕 대비(감사138 4-1 · 7칸 grey600).
_WkhObs _wkhLine(WidgetTester t, String tok, Finder selF) {
  final wkd = <String>[];
  final wke = <String>[];
  var n = 0;
  var worst = 99.0;
  for (final d in const ['일', '월', '화', '수', '목', '금', '토']) {
    final f = find.descendant(of: selF, matching: find.text(d), skipOffstage: true);
    if (f.evaluate().length != 1) continue;
    n++;
    final col = _fgOf(t, f);
    final r = _contrast(col, Colors.white);
    if (r < worst) worst = r;
    if (d == '일' || d == '토') {
      wke.add(_hex(col));
    } else {
      wkd.add(_hex(col));
    }
  }
  final ecr = n == 0 ? '-' : worst.toStringAsFixed(2);
  final o = (n: n, wkd: _one(wkd), wke: _one(wke), worst: worst);
  _out('D549 $tok att wkh n=${o.n} wkd=${o.wkd} wke=${o.wke} ecr=$ecr');
  return o;
}

typedef _DaysObs = ({int todayN, String mark, String todayFg, int pastN, int wkN, String wkFg, double wkWorst});

/// 이 달 날짜 칸 — 지난 날(흐림 기록) · 오늘 표시(7열 = 외곽선 색 · 목록 = '오늘' 글 색) · 고를 수 있고 고르지 않은 주말 날짜 글 색 · 대비.
_DaysObs _daysLine(WidgetTester t, String tok, Finder calF, DateTime today, bool list) {
  final last = DateTime(today.year, today.month + 1, 0).day;
  final pastFg = <String>[];
  final wkFg = <String>[];
  var pastWorst = 99.0;
  var wkWorst = 99.0;
  var todayN = 0;
  var mark = '-';
  var todayFg = '-';
  for (var d = 1; d <= last; d++) {
    final date = DateTime(today.year, today.month, d);
    final f = _dayFinder(calF, date, list);
    if (f.evaluate().length != 1) continue;
    final fg = _fgOf(t, f);
    if (date.isBefore(today)) {
      pastFg.add(_hex(fg));
      final r = _contrast(fg, Colors.white);
      if (r < pastWorst) pastWorst = r;
      continue;
    }
    if (_sameDay(date, today)) {
      todayN++;
      todayFg = _hex(fg);
      if (list) {
        final row = find.ancestor(of: f, matching: find.byType(Row)).first;
        final lab = find.descendant(of: row, matching: findVisibleText('오늘'), skipOffstage: true);
        if (lab.evaluate().length == 1) mark = _hex(_fgOf(t, lab));
      } else {
        final stack = find.ancestor(of: f, matching: find.byType(Stack)).first;
        for (final e in find.descendant(of: stack, matching: find.byType(Container), skipOffstage: true).evaluate()) {
          final dd = (e.widget as Container).decoration;
          if (dd is BoxDecoration && dd.shape == BoxShape.circle && dd.border is Border) mark = _hex((dd.border as Border).top.color);
        }
      }
      continue;
    }
    if (date.weekday == DateTime.saturday || date.weekday == DateTime.sunday) {
      wkFg.add(_hex(fg));
      final r = _contrast(fg, Colors.white);
      if (r < wkWorst) wkWorst = r;
    }
  }
  final pastCr = pastFg.isEmpty ? '-' : pastWorst.toStringAsFixed(2);
  final wkCr = wkFg.isEmpty ? '-' : wkWorst.toStringAsFixed(2);
  final wkOne = _one(wkFg);
  _out('D549 $tok att today n=$todayN mark=$mark fg=$todayFg');
  _out('D549 $tok att past n=${pastFg.length} fg=${_one(pastFg)} cr=$pastCr');
  _out('D549 $tok att wkend n=${wkFg.length} fg=$wkOne cr=$wkCr');
  return (todayN: todayN, mark: mark, todayFg: todayFg, pastN: pastFg.length, wkN: wkFg.length, wkFg: wkOne, wkWorst: wkWorst);
}

typedef _SelObs = ({int n, int want, String face, String fg});

/// 이 달에 보이는 선택 날짜 — 면(7열 = 칸 Container · 목록 = 줄 Material)이 primaryColor 인 수 · 면 · 글 색. 기대 수 = 이 달 안 선택 날짜 수.
_SelObs _selObs(WidgetTester t, Finder calF, List<DateTime> dates, DateTime today, Color prim, bool list) {
  final inMonth = dates.where((d) => d.year == today.year && d.month == today.month).toList();
  final faces = <String>[];
  final fgs = <String>[];
  var n = 0;
  for (final d in inMonth) {
    final f = _dayFinder(calF, d, list);
    if (f.evaluate().length != 1) continue;
    final face = list ? _matOf(t, f) : _boxOf(t, f).face;
    if (face == prim) n++;
    faces.add(_hex(face));
    fgs.add(_hex(_fgOf(t, f)));
  }
  return (n: n, want: inMonth.length, face: _one(faces), fg: _one(fgs));
}

_SelObs _selLine(WidgetTester t, String tok, Finder calF, List<DateTime> dates, DateTime today, Color prim, bool list) {
  final so = _selObs(t, calF, dates, today, prim, list);
  _out('D549 $tok att sel n=${so.n} want=${so.want} face=${so.face} fg=${so.fg}');
  return so;
}

typedef _ChipObs = ({int n, String face, String fg, bool cr});

/// 선택 건수 칩('14일' · 그대로 · 감사138 4-3 유지).
_ChipObs _countLine(WidgetTester t, String tok, Finder selF, String label) {
  final f = find.descendant(of: selF, matching: find.text(label), skipOffstage: true);
  final n = f.evaluate().length;
  var face = '-';
  var fg = '-';
  var cr = false;
  if (n == 1) {
    final fc = _boxOf(t, f).face;
    final gc = _fgOf(t, f);
    face = _hex(fc);
    fg = _hex(gc);
    cr = _ok(gc, fc);
  }
  _out('D549 $tok att count n=$n face=$face fg=$fg cr45=$cr');
  return (n: n, face: face, fg: fg, cr: cr);
}

typedef _ClearObs = ({int n, String face, String icon, String fg, bool cr, bool vis, bool hit});

/// '전체 해제' — 면(Material) · 아이콘 · 글 색 · 대비 · 보임(Opacity 1 · 화면 칸 안) · 중심 hit. 누르지 않는다.
_ClearObs _clearLine(WidgetTester t, String tok, Finder selF, Rect screen) {
  final f = find.descendant(of: selF, matching: find.text('전체 해제'), skipOffstage: true);
  final n = f.evaluate().length;
  var face = '-';
  var icon = '-';
  var fg = '-';
  var cr = false;
  var vis = false;
  var hit = false;
  if (n == 1) {
    final ink = find.ancestor(of: f, matching: find.byType(InkWell)).first;
    final fc = _matOf(t, f);
    final gc = _fgOf(t, f);
    final ic = _iconIn(t, ink, Icons.clear_all);
    final op = t.widget<Opacity>(find.ancestor(of: f, matching: find.byType(Opacity)).first).opacity;
    final tn = _tapNow(t, ink, screen);
    face = _hex(fc);
    icon = _h(ic);
    fg = _hex(gc);
    cr = _ok(gc, fc) && ic != null && _ok(ic, fc);
    vis = tn.vis && op == 1.0;
    hit = tn.hit;
  }
  _out('D549 $tok att clear n=$n face=$face icon=$icon fg=$fg cr45=$cr vis=$vis hit=$hit');
  return (n: n, face: face, icon: icon, fg: fg, cr: cr, vis: vis, hit: hit);
}

const _maxText = '최대 14일까지 선택 가능합니다';

/// 경고 토스트(E-TOAST · 그대로) — 수 · 면 · 글 색 · 대비. 출력은 부르는 쪽(선택 수 · 콜백 수와 한 줄).
_ChipObs _toastObs(WidgetTester t) {
  final f = find.text(_maxText);
  final n = f.evaluate().length;
  if (n != 1) return (n: n, face: '-', fg: '-', cr: false);
  final fc = _boxOf(t, f).face;
  final gc = _fgOf(t, f);
  return (n: n, face: _hex(fc), fg: _hex(gc), cr: _contrast(gc, fc.a > 0 ? Color.alphaBlend(fc, Colors.white) : Colors.white) >= 4.5);
}

typedef _HintObs = ({int n, String face, String bd, String icon, String fg, String close, bool cr});

/// 범위 선택 중 머리 안내(key 'hint') — 면 · 선 · 손 아이콘 · 글(RichText 바탕 스타일) · 닫기 아이콘.
_HintObs _hintLine(WidgetTester t, String tok) {
  final hF = find.byKey(const ValueKey('hint'));
  final n = hF.evaluate().length;
  var face = '-';
  var bd = '-';
  var icon = '-';
  var fg = '-';
  var close = '-';
  var cr = false;
  if (n == 1) {
    final d = t.widget<Container>(hF).decoration;
    final fc = d is BoxDecoration ? (d.color ?? Colors.transparent) : Colors.transparent;
    final b = d is BoxDecoration ? d.border : null;
    final ic = _iconIn(t, hF, Icons.touch_app);
    final cc = _iconIn(t, hF, Icons.close);
    // 글 RichText 만 — Icon 도 안에서 RichText(글리프)로 그려지므로 Icon 아래 것은 뺀다(is Icon 조상 검사).
    final rts = find.descendant(of: hF, matching: find.byType(RichText), skipOffstage: true).evaluate().where((e) {
      var under = false;
      e.visitAncestorElements((a) {
        if (a.widget is Icon) under = true;
        return !under;
      });
      return !under;
    }).toList();
    final tc = rts.length == 1 ? ((rts.first.widget as RichText).text as TextSpan).style?.color : null;
    face = _hex(fc);
    bd = b is Border ? _hex(b.top.color) : '-';
    icon = _h(ic);
    fg = _h(tc);
    close = _h(cc);
    cr = tc != null && cc != null && _ok(tc, fc) && _ok(cc, fc);
  }
  _out('D549 $tok att hint n=$n face=$face bd=$bd icon=$icon fg=$fg close=$close cr45=$cr');
  return (n: n, face: face, bd: bd, icon: icon, fg: fg, close: close, cr: cr);
}

typedef _InlineObs = ({int n, String face, String icon, String fg, bool cr});

/// 탭 자리 끝 날짜 안내(key 'inline-range-hint') — 면 · 손 아이콘 · 글 색.
_InlineObs _inlineLine(WidgetTester t, String tok) {
  final iF = find.byKey(const ValueKey('inline-range-hint'));
  final n = iF.evaluate().length;
  var face = '-';
  var icon = '-';
  var fg = '-';
  var cr = false;
  if (n == 1) {
    final d = t.widget<Container>(iF).decoration;
    final fc = d is BoxDecoration ? (d.color ?? Colors.transparent) : Colors.transparent;
    final txt = find.descendant(of: iF, matching: find.byType(Text), skipOffstage: true);
    final gc = txt.evaluate().length == 1 ? _fgOf(t, txt) : null;
    face = _hex(fc);
    icon = _h(_iconIn(t, iF, Icons.touch_app));
    fg = _h(gc);
    cr = gc != null && _ok(gc, fc);
  }
  _out('D549 $tok att inline n=$n face=$face icon=$icon fg=$fg cr45=$cr');
  return (n: n, face: face, icon: icon, fg: fg, cr: cr);
}

typedef _TileObs = ({int n, String face, String shadow, String icon});

/// 읽기 전용 머리 아이콘 칸(calendar_today) — 면 · 그림자 색 · 아이콘 색(그대로).
_TileObs _tileLine(WidgetTester t, String tok) {
  final iF = find.byIcon(Icons.calendar_today);
  final n = iF.evaluate().length;
  var face = '-';
  var shadow = '-';
  var icon = '-';
  if (n == 1) {
    final d = t.widget<Container>(find.ancestor(of: iF, matching: find.byType(Container)).first).decoration;
    final sh = d is BoxDecoration ? d.boxShadow : null;
    face = d is BoxDecoration ? _hex(d.color ?? Colors.transparent) : '-';
    shadow = sh == null || sh.isEmpty ? '-' : _hex(sh.first.color);
    icon = _h(t.widget<Icon>(iF).color);
  }
  _out('D549 $tok att tile n=$n face=$face shadow=$shadow icon=$icon');
  return (n: n, face: face, shadow: shadow, icon: icon);
}

/// 수정 불가 안내 — 옛 장기 문장(DU542 채택판 · 지금 A 에 없음 = 0) · 새 장기 문장(DU542b 채택 · 지금 A · 두 모드 1).
const _oldLock = '계약 기간과 근무 요일은(는) 수정할 수 없습니다';
const _newLock = '공고 생성 후 계약 기간과 근무 요일은 변경할 수 없어요.';

/// 조사 보간 흔적('은(는)' · '을(를)' · '이(가)' · '와(과)' · '(으)로' 와 뒤바뀐 꼴).
final RegExp _badJosa = RegExp(r'(은\(는\)|는\(은\)|을\(를\)|를\(을\)|이\(가\)|가\(이\)|와\(과\)|과\(와\)|\(으\)로)');

typedef _LockObs = ({int n, String face, String bd, String icon, String fg, bool cr, String shape, String isz});

/// 수정 불가 띠 — 옛/새 문장 중 보이는 것 하나의 띠(가장 가까운 Container) 면 · 선 · 아이콘 색 · 모양(잠금/경고) · 크기 · 글 색.
_LockObs _lockLine(WidgetTester t, String tok, Finder selF) {
  final oldF = find.descendant(of: selF, matching: findVisibleText(_oldLock), skipOffstage: true);
  final newF = find.descendant(of: selF, matching: findVisibleText(_newLock), skipOffstage: true);
  final nOld = oldF.evaluate().length;
  final nNew = newF.evaluate().length;
  final n = nOld + nNew;
  var face = '-';
  var bd = '-';
  var icon = '-';
  var fg = '-';
  var cr = false;
  var shape = '-';
  var isz = '-';
  if (n == 1) {
    final f = nNew == 1 ? newF : oldF;
    final boxF = find.ancestor(of: f, matching: find.byType(Container)).first;
    final bx = _boxOf(t, f);
    final gc = _fgOf(t, f);
    final lockF = find.descendant(of: boxF, matching: find.byIcon(Icons.lock_outline), skipOffstage: true);
    final warnF = find.descendant(of: boxF, matching: find.byIcon(Icons.warning_amber), skipOffstage: true);
    final nl = lockF.evaluate().length;
    final nw = warnF.evaluate().length;
    shape = nl == 1 && nw == 0 ? 'lock' : (nw == 1 && nl == 0 ? 'warn' : '-');
    if (nl + nw == 1) {
      final iw = t.widget<Icon>(nl == 1 ? lockF : warnF);
      final ic = iw.color;
      icon = _h(ic);
      isz = iw.size == null ? '-' : iw.size!.toStringAsFixed(1);
      cr = _ok(gc, bx.face) && ic != null;
    }
    face = _hex(bx.face);
    bd = bx.bd;
    fg = _hex(gc);
  }
  _out('D549 $tok att lock n=$n face=$face bd=$bd icon=$icon fg=$fg cr45=$cr shape=$shape isz=$isz');
  return (n: n, face: face, bd: bd, icon: icon, fg: fg, cr: cr, shape: shape, isz: isz);
}

typedef _CopyObs = ({int old, int neu, int bad, bool sem});

/// 안내 문장 — 옛 보간 문장 수 · 새 완전한 문장 수 · 선택기 안 모든 Text 중 조사 보간 흔적 수 · 새 문장의 읽기 도구 이름 = 원문.
_CopyObs _copyLine(WidgetTester t, String tok, Finder selF) {
  final oldN = find.descendant(of: selF, matching: findVisibleText(_oldLock), skipOffstage: true).evaluate().length;
  final newF = find.descendant(of: selF, matching: findVisibleText(_newLock), skipOffstage: true);
  final newN = newF.evaluate().length;
  var bad = 0;
  for (final e in find.descendant(of: selF, matching: find.byType(Text), skipOffstage: true).evaluate()) {
    final w = e.widget as Text;
    final d = w.data ?? w.textSpan?.toPlainText() ?? '';
    if (_badJosa.hasMatch(visibleText(d))) bad++;
  }
  final sem = newN == 1 && t.widget<Text>(newF).semanticsLabel == _newLock;
  _out('D549 $tok att copy old=$oldN new=$newN bad=$bad sem=$sem');
  return (old: oldN, neu: newN, bad: bad, sem: sem);
}

const _editPath = 'lib/screens/business_admin/to_management/edit_to_screen.dart';

typedef _DupObs = ({int win, int ui, int src, int total});

/// 수정 화면의 같은 뜻 안내 — edit_to_screen.dart(읽기만)에서 주석 줄을 뺀 코드의 'TODateSelector(' ~ 'TOTitleSection(' 창(읽기 전용 날짜 선택기 바로 뒤)의
///   Text 위젯 수(src) + 선택기 안에 그려진 안내 수(ui) = 수정 화면에서 같은 뜻 안내 개수(total).
_DupObs _dupLine(String tok, int ui) {
  final raw = File(_editPath).readAsStringSync();
  final code = raw.split('\n').where((l) => !l.trimLeft().startsWith('//')).join('\n');
  final nSel = 'TODateSelector('.allMatches(code).length;
  final i0 = code.indexOf('TODateSelector(');
  final i1 = i0 < 0 ? -1 : code.indexOf('TOTitleSection(', i0);
  final win = nSel == 1 && i1 > i0 ? 1 : 0;
  final src = win == 1 ? RegExp(r'(^|[^A-Za-z_])Text\(').allMatches(code.substring(i0, i1)).length : 99;
  final total = ui + src;
  _out('D549 $tok att dup win=$win ui=$ui src=$src total=$total');
  return (win: win, ui: ui, src: src, total: total);
}

typedef _BandObs = ({int n, String face, String bd, String icon, String fg, bool cr});

/// 글 [text] 를 든 안내 띠 — 띠(가장 가까운 Container) 면 · 선 · 띠 안 아이콘 [ic] · 글 색.
_BandObs _bandObs(WidgetTester t, Finder selF, String text, IconData ic) {
  final f = find.descendant(of: selF, matching: find.text(text), skipOffstage: true);
  final n = f.evaluate().length;
  if (n != 1) return (n: n, face: '-', bd: '-', icon: '-', fg: '-', cr: false);
  final boxF = find.ancestor(of: f, matching: find.byType(Container)).first;
  final bx = _boxOf(t, f);
  final gc = _fgOf(t, f);
  return (n: n, face: _hex(bx.face), bd: bx.bd, icon: _h(_iconIn(t, boxF, ic)), fg: _hex(gc), cr: _ok(gc, bx.face));
}

const _infoText = '지원자는 이 기간 안에서 희망 근무 시작일을 선택할 수 있습니다.';

_BandObs _infoLine(WidgetTester t, String tok, Finder selF) {
  final o = _bandObs(t, selF, _infoText, Icons.info_outline);
  _out('D549 $tok att info n=${o.n} face=${o.face} bd=${o.bd} icon=${o.icon} fg=${o.fg} cr45=${o.cr}');
  return o;
}

const _periodLabels = ['15일', '1개월', '3개월', '6개월', '1년', '직접 입력'];

typedef _PeriodObs = ({int n, int sel, String sface, String sfg, String uface, String ubd, String ufg, bool cr});

/// 계약 기간 칩 6 — 고른 것(면 = primaryColor) · 고르지 않은 것의 면 · 선 · 글 색(그대로).
_PeriodObs _periodLine(WidgetTester t, String tok, Finder selF, Color prim) {
  final sf = <String>[];
  final sg = <String>[];
  final uf = <String>[];
  final ub = <String>[];
  final ug = <String>[];
  var n = 0;
  var cr = true;
  for (final lab in _periodLabels) {
    final f = find.descendant(of: selF, matching: find.text(lab), skipOffstage: true);
    if (f.evaluate().length != 1) continue;
    n++;
    final bx = _boxOf(t, f);
    final gc = _fgOf(t, f);
    cr = cr && _ok(gc, bx.face);
    if (bx.face == prim) {
      sf.add(_hex(bx.face));
      sg.add(_hex(gc));
    } else {
      uf.add(_hex(bx.face));
      ub.add(bx.bd);
      ug.add(_hex(gc));
    }
  }
  final o = (n: n, sel: sf.length, sface: _one(sf), sfg: _one(sg), uface: _one(uf), ubd: _one(ub), ufg: _one(ug), cr: cr && n > 0);
  _out('D549 $tok att period n=${o.n} sel=${o.sel} sface=${o.sface} sfg=${o.sfg} uface=${o.uface} ubd=${o.ubd} ufg=${o.ufg} cr45=${o.cr}');
  return o;
}

/// '필수' 표지(그대로).
_ChipObs _reqLine(WidgetTester t, String tok, Finder selF) {
  final f = find.descendant(of: selF, matching: find.text('필수'), skipOffstage: true);
  final n = f.evaluate().length;
  var face = '-';
  var fg = '-';
  var cr = false;
  if (n == 1) {
    final fc = _boxOf(t, f).face;
    final gc = _fgOf(t, f);
    face = _hex(fc);
    fg = _hex(gc);
    cr = _ok(gc, fc);
  }
  _out('D549 $tok att req n=$n face=$face fg=$fg cr45=$cr');
  return (n: n, face: face, fg: fg, cr: cr);
}

typedef _FieldObs = ({int n, int filled, String fface, String fbd, String fbw, String vfg, String eface, String ebd, String hfg, bool cr});

/// 날짜 칸 2(시작일 · 종료일) — 값 있는 칸의 면 · 선 · 선 두께 · 값 글, 빈 칸('선택하세요')의 면 · 선 · 글 색.
_FieldObs _fieldLine(WidgetTester t, String tok, Finder selF) {
  final ff = <String>[];
  final fb = <String>[];
  final fws = <String>[];
  final vf = <String>[];
  final ef = <String>[];
  final eb = <String>[];
  final hf = <String>[];
  var n = 0;
  var cr = true;
  for (final lab in const ['시작일', '종료일']) {
    final lf = find.descendant(of: selF, matching: find.text(lab), skipOffstage: true);
    if (lf.evaluate().length != 1) continue;
    final texts = find
        .descendant(of: find.ancestor(of: lf, matching: find.byType(Column)).first, matching: find.byType(Text), skipOffstage: true)
        .evaluate()
        .map((e) => e.widget as Text)
        .toList();
    if (texts.length != 2) continue;
    n++;
    final bx = _boxOf(t, lf);
    final dd = t.widget<Container>(find.ancestor(of: lf, matching: find.byType(Container)).first).decoration;
    final bw = dd is BoxDecoration && dd.border is Border ? (dd.border as Border).top.width : -1.0;
    final vc = texts[1].style?.color ?? Colors.black;
    cr = cr && _ok(vc, bx.face);
    if (texts[1].data == '선택하세요') {
      ef.add(_hex(bx.face));
      eb.add(bx.bd);
      hf.add(_hex(vc));
    } else {
      ff.add(_hex(bx.face));
      fb.add(bx.bd);
      fws.add(bw.toStringAsFixed(1));
      vf.add(_hex(vc));
    }
  }
  final o = (n: n, filled: ff.length, fface: _one(ff), fbd: _one(fb), fbw: _one(fws), vfg: _one(vf), eface: _one(ef), ebd: _one(eb), hfg: _one(hf), cr: cr && n > 0);
  _out('D549 $tok att field n=${o.n} filled=${o.filled} fface=${o.fface} fbd=${o.fbd} fbw=${o.fbw} vfg=${o.vfg} eface=${o.eface} ebd=${o.ebd} hfg=${o.hfg} cr45=${o.cr}');
  return o;
}

/// 두 날짜 칸 사이 화살표(장식 · 그대로).
({int n, String icon}) _arrowLine(WidgetTester t, String tok) {
  final iF = find.byIcon(Icons.arrow_forward);
  final n = iF.evaluate().length;
  final icon = n == 1 ? _h(t.widget<Icon>(iF).color) : '-';
  _out('D549 $tok att arrow n=$n icon=$icon');
  return (n: n, icon: icon);
}

const _wkLabels = ['월', '화', '수', '목', '금', '토', '일'];

typedef _WkbObs = ({int n, int sel, String sface, String sfg, String uface, String ufg, String eface, String efg, String ecr, double worst});

/// 근무 요일 버튼 7 — 고른 것 · 고르지 않은 평일 · 고르지 않은 주말의 면 · 글 색과 고르지 않은 칸 중 가장 낮은 대비.
_WkbObs _wkbLine(WidgetTester t, String tok, Finder selF, Color prim) {
  final sf = <String>[];
  final sg = <String>[];
  final uf = <String>[];
  final ug = <String>[];
  final ef = <String>[];
  final eg = <String>[];
  var n = 0;
  var worst = 99.0;
  for (final d in _wkLabels) {
    final f = find.descendant(of: selF, matching: find.text(d), skipOffstage: true);
    if (f.evaluate().length != 1) continue;
    n++;
    final face = _boxOf(t, f).face;
    final gc = _fgOf(t, f);
    if (face == prim) {
      sf.add(_hex(face));
      sg.add(_hex(gc));
      continue;
    }
    final r = _contrast(gc, Color.alphaBlend(face, Colors.white));
    if (r < worst) worst = r;
    if (d == '토' || d == '일') {
      ef.add(_hex(face));
      eg.add(_hex(gc));
    } else {
      uf.add(_hex(face));
      ug.add(_hex(gc));
    }
  }
  final ecr = (uf.isEmpty && ef.isEmpty) ? '-' : worst.toStringAsFixed(2);
  final o = (n: n, sel: sf.length, sface: _one(sf), sfg: _one(sg), uface: _one(uf), ufg: _one(ug), eface: _one(ef), efg: _one(eg), ecr: ecr, worst: worst);
  _out('D549 $tok att wkb n=${o.n} sel=${o.sel} sface=${o.sface} sfg=${o.sfg} uface=${o.uface} ufg=${o.ufg} eface=${o.eface} efg=${o.efg} ecr=${o.ecr}');
  return o;
}

const _sumTitle = '주 4일 근무';
const _sumDetail = '선택된 요일: 월, 수, 금, 토';

typedef _SumObs = ({int n, String face, String bd, String icon, String tfg, String dfg, bool cr});

/// '주 N일 근무' 요약 띠(그대로) — 면 · 선 · 체크 아이콘 · 제목 · 상세 글 색.
_SumObs _sumLine(WidgetTester t, String tok, Finder selF) {
  final f = find.descendant(of: selF, matching: find.text(_sumTitle), skipOffstage: true);
  final dF = find.descendant(of: selF, matching: find.text(_sumDetail), skipOffstage: true);
  final n = f.evaluate().length == 1 && dF.evaluate().length == 1 ? 1 : 0;
  var face = '-';
  var bd = '-';
  var icon = '-';
  var tfg = '-';
  var dfg = '-';
  var cr = false;
  if (n == 1) {
    final bx = _boxOf(t, f);
    final tc = _fgOf(t, f);
    final dc = _fgOf(t, dF);
    face = _hex(bx.face);
    bd = bx.bd;
    icon = _h(_iconIn(t, find.ancestor(of: f, matching: find.byType(Container)).first, Icons.check_circle));
    tfg = _hex(tc);
    dfg = _hex(dc);
    cr = _ok(tc, bx.face) && _ok(dc, bx.face);
  }
  _out('D549 $tok att sum n=$n face=$face bd=$bd icon=$icon tfg=$tfg dfg=$dfg cr45=$cr');
  return (n: n, face: face, bd: bd, icon: icon, tfg: tfg, dfg: dfg, cr: cr);
}

typedef _LayObs = ({bool n, bool tvis, bool cvis, bool one, String place, String gap});

const _rangeTitle = '근무 시작 가능기간';
const _rangeDesc = '지원자가 희망 시작일로 선택할 수 있는 기간입니다.';

/// 상자 하나의 선택기 기준 좌표(l,t,r,b · 소수 1자리) — 스크롤 위치와 무관하게 TB · TA 를 손으로 대조한다(DU538 `_rs` 와 같은 꼴 · 원점만 선택기 왼쪽 위).
String _rs(Rect r, Rect o) =>
    '${(r.left - o.left).toStringAsFixed(1)},${(r.top - o.top).toStringAsFixed(1)},${(r.right - o.left).toStringAsFixed(1)},${(r.bottom - o.top).toStringAsFixed(1)}';

/// [DU549] 근무 시작 가능기간 제목 + '필수' 표지 배치 — 범위 칸 묶음(제목의 가장 가까운 Column)을 끌어 보이게 한 뒤(t.ensureVisible · RANGE 와 같은 길) 잰다.
///   tvis · cvis = 제목 · 표지(가장 가까운 Container — _reqLine 과 같은 상자)가 화면 ∩ 스크롤 칸 안에 다 들어오는가(_tapNow 의 vis 식).
///   one = 제목이 한 줄인가(같은 글자 크기 15 의 기간 칩 글 '15일' 과 높이 같음 · 번들 NotoSansKR Regular/Bold 세로 metrics 같음).
///   place = 표지 자리(side = 제목 오른쪽 · 세로 가운데 같음 / below = 제목 아래 · 왼쪽 같음 / 그 밖 '-') · gap = side 일 때 제목 끝 ~ 표지 사이.
///   tg · cg · dg = 제목 · 표지 · 그 아래 설명 글의 선택기 기준 좌표(W 는 TB = TA 여야 한다 — 손 대조). 개수가 1 이 아니면 재지 않고 n false.
Future<_LayObs> _layLine(WidgetTester t, String tok, Finder selF, Rect screen) async {
  final titleF = find.descendant(of: selF, matching: find.text(_rangeTitle), skipOffstage: true);
  final reqF = find.descendant(of: selF, matching: find.text('필수'), skipOffstage: true);
  final descF = find.descendant(of: selF, matching: find.text(_rangeDesc), skipOffstage: true);
  final labF = find.descendant(of: selF, matching: find.text('15일'), skipOffstage: true);
  final ok = titleF.evaluate().length == 1 && reqF.evaluate().length == 1 && descF.evaluate().length == 1 && labF.evaluate().length == 1;
  if (!ok) return (n: false, tvis: false, cvis: false, one: false, place: '-', gap: '-');
  final chipF = find.ancestor(of: reqF, matching: find.byType(Container)).first;
  await t.ensureVisible(find.ancestor(of: titleF, matching: find.byType(Column)).first);
  await t.pump(const Duration(milliseconds: 100));
  final o = t.getRect(selF);
  final tr = t.getRect(titleF);
  final kr = t.getRect(chipF);
  final dr = t.getRect(descF);
  final lr = t.getRect(labF);
  final tvis = _tapNow(t, titleF, screen).vis;
  final cvis = _tapNow(t, chipF, screen).vis;
  final one = (tr.height - lr.height).abs() < 0.5;
  final side = kr.left >= tr.right - 0.5 && (kr.center.dy - tr.center.dy).abs() < 0.5;
  final below = kr.top >= tr.bottom - 0.5 && (kr.left - tr.left).abs() < 0.5;
  final place = side ? 'side' : (below ? 'below' : '-');
  final gap = side ? (kr.left - tr.right).toStringAsFixed(1) : '-';
  _out('D549 $tok att lay tvis=$tvis cvis=$cvis one=$one place=$place gap=$gap tg=${_rs(tr, o)} cg=${_rs(kr, o)} dg=${_rs(dr, o)}');
  return (n: true, tvis: tvis, cvis: cvis, one: one, place: place, gap: gap);
}

typedef _V = ({String id, double w, double h, double s});
const _views = <_V>[(id: 'W', w: 390.0, h: 844.0, s: 1.0), (id: 'B', w: 320.0, h: 640.0, s: 2.0)];
const _cases = <({String id, int shots})>[(id: 'EMPTY', shots: 2), (id: 'MULTI', shots: 2), (id: 'RANGE', shots: 2), (id: 'LOCKED', shots: 1), (id: 'PERIOD', shots: 2), (id: 'CUSTOM', shots: 1)];

final bool _before = Platform.environment['DU_BEFORE_OBSERVE'] == '549';
final Map<String, String> _env = Platform.environment;
final bool _optIn =
    (_env['DU1_VQ_PHASE'] == 'before' && _env['DU1_VQ_RUN'] == 'du549-tb' && _env['DU_BEFORE_OBSERVE'] == '549') ||
        (_env['DU1_VQ_PHASE'] == 'after' && _env['DU1_VQ_RUN'] == 'du549-ta' && _env['DU_BEFORE_OBSERVE'] == null);

/// 첫 실패 뒤 사례는 본문에 들어가지 않는다(진입 0 · 캡처 0).
String? _halt;
final String _manifest = Platform.environment['DUL_MANIFEST'] ?? '(unset)';
const _envKeys = ['DU_BEFORE_OBSERVE', 'DU1_VQ_PHASE', 'DU1_VQ_OUT', 'DU1_VQ_RUN', 'DU1_VQ_DATE', 'DU397_DIAG', 'DU397_MANIFEST', 'DU400_MANIFEST',
  'DU401_MANIFEST', 'DU398_MANIFEST', 'DU406_MANIFEST', 'DU407_MANIFEST', 'DU296_PHASE', 'DUL_MANIFEST'];
final String _envLine = [for (final k in _envKeys) '$k:${Platform.environment[k] ?? '(unset)'}'].join(',');

void main() {
  setUpAll(() async {
    final m = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final wire = _Wire();
    final net = _NoHttp();
    final prevAll = m.allMessagesHandler;
    final prevHttp = HttpOverrides.current;
    m.allMessagesHandler = (channel, handler, message) => wire.route(m, channel, handler, message);
    HttpOverrides.global = net;
    try {
      await initializeDateFormatting('ko_KR');
      await _loadFonts();
    } finally {
      m.allMessagesHandler = prevAll;
      HttpOverrides.global = prevHttp;
    }
    final nUnexp = wire.unexpected.length;
    final nHttp = net.tries.length;
    _out('R549 setup init unexpected=$nUnexp http=$nHttp un64=${_enc(wire.unexpected.join('|'))}');
    final initOk = nUnexp == 0 && nHttp == 0;
    if (!initOk) _halt = 'setUpAll 초기화 안전 대역';
    expect(initOk, isTrue, reason: 'setUpAll 초기화 중 예상 밖 채널 0 · HTTP 0 — [${wire.unexpected.join(' | ')}]');
  });

  for (final v in _views) {
    for (final c in _cases) {
      testWidgets('S949TB-${v.id}-${c.id} TO 날짜 선택기 큰 글자 배치 — 근무 시작 가능기간 제목 · 필수 표지 줄바꿈', (t) async {
        final tok = 'S949TB-${v.id}-${c.id}';
        if (_halt != null) fail('$tok 진입 0 — 앞 실패: $_halt');

        final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        final wire = _Wire();
        final net = _NoHttp();
        final prevAll = messenger.allMessagesHandler;
        final prevHttp = HttpOverrides.current;
        final prevOnError = FlutterError.onError;
        messenger.allMessagesHandler = (channel, handler, message) => wire.route(messenger, channel, handler, message);
        HttpOverrides.global = net;
        addTearDown(() {
          messenger.allMessagesHandler = prevAll;
          HttpOverrides.global = prevHttp;
          FlutterError.onError = prevOnError;
        });
        t.view.physicalSize = Size(v.w, v.h);
        t.view.devicePixelRatio = 1.0;
        addTearDown(t.view.reset);
        final mode = _before ? 'before' : 'strict';
        _out('D549 $tok begin mode=$mode phase=${Platform.environment['DU1_VQ_PHASE'] ?? '(unset)'} env=$_envLine manifest=$_manifest');
        final seen = _Seen();
        void need(String k, bool ok, [String why = '']) => expect(ok, isTrue, reason: '$tok $k $why');
        final checks = <(String, bool, String)>[];
        void chk(String k, bool ok, [String why = '']) => checks.add((k, ok, why));

        final calls = <String, int>{};
        final now = DateTime.now();
        final today = DateTime(now.year, now.month, now.day);
        final cfg = _cfgOf(c.id, today);
        final chipText = '${cfg.dates.length}일';
        Object? failure;
        StackTrace? failureSt;
        var shots = 0;
        try {
          FlutterError.onError = seen.add;
          final key = GlobalKey();
          await t.pumpWidget(RepaintBoundary(
            key: key,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              navigatorKey: navigatorKey,
              theme: RoleTheme.businessAdminTheme,
              locale: const Locale('ko', 'KR'),
              supportedLocales: const [Locale('ko', 'KR'), Locale('en', 'US')],
              localizationsDelegates: const [
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              builder: (ctx, child) => MediaQuery(data: MediaQuery.of(ctx).copyWith(textScaler: TextScaler.linear(v.s)), child: child!),
              home: Scaffold(
                body: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: _Host(key: UniqueKey(), cfg: cfg, calls: calls),
                ),
              ),
            ),
          ));
          for (var i = 0; i < 20; i++) {
            await t.pump(const Duration(milliseconds: 50));
          }
          final selF = find.byType(TODateSelector);
          final nSel = selF.evaluate().length;
          need('날짜 선택기 1', nSel == 1, '개수 $nSel');
          final scF = find.byType(Scrollable);
          final nSc = scF.evaluate().length;
          need('스크롤 칸 1', nSc == 1, '개수 $nSc');
          final pos = t.state<ScrollableState>(scF).position;
          final screen = Offset.zero & Size(v.w, v.h);

          Future<void> shot(String id, String state) async {
            _out('D549 $tok shot $id ovf=${seen.overflows.length}');
            await vqCapture(t, key, '${tok}_$id', conditions: {
              'viewport': '${v.w.toInt()}x${v.h.toInt()}', 'textScaler': v.s, 'run': vqRun, 'manifest': _manifest, 'mode': mode,
              'fixture': c.id, 'state': state,
            });
            shots++;
          }

          // 테마 primaryColor = brand(RoleTheme — 제품 값). 선택 · 고른 것 판정의 기준색이다.
          final prim = Theme.of(t.element(selF)).primaryColor;
          final primHex = _hex(prim);
          _out('D549 $tok att prim c=$primHex');
          need('테마 primaryColor = AppColors.brand', primHex == _wBrand, primHex);

          // 그려진 글 집합(숫자는 # · 보이지 않는 낱말 묶음 문자 제거). 기록용: TB · TA 의 set 을 손으로 대조한다(바뀐 문구 0 — TB = TA).
          final words = <String>{};
          for (final e in find.descendant(of: selF, matching: find.byType(Text), skipOffstage: true).evaluate()) {
            final d = (e.widget as Text).data;
            if (d != null && d.isNotEmpty) words.add(visibleText(d).replaceAll(RegExp(r'\d+'), '#'));
          }
          final wordList = words.toList()..sort();
          _out('D549 $tok att txt n=${wordList.length} set=${_enc(wordList.join('|'))}');

          if (c.id == 'EMPTY') {
            final calF = find.descendant(of: selF, matching: find.byType(LayoutBuilder), skipOffstage: true);
            need('달력 1', calF.evaluate().length == 1, '개수 ${calF.evaluate().length}');
            final list = _isList(calF, today);
            final qo = _quickLine(t, tok, prim);
            final no = _navLine(t, tok, today);
            final go = _toggleLine(t, tok);
            final wh = _wkhLine(t, tok, selF);
            final dy = _daysLine(t, tok, calF, today, list);
            need('빠른 선택 3 · 고른 것 0', qo.n == 3 && qo.act == 0, 'n ${qo.n} act ${qo.act}');
            need('월 이동 2 · 월 제목 1', no.n == 2 && no.title != '-', 'n ${no.n} title ${no.title}');
            need('캘린더 접기 1', go.n == 1, 'n ${go.n}');
            need('오늘 칸 1', dy.todayN == 1, 'n ${dy.todayN} list $list');
            need('요일 머리 = 7열 7칸 · 목록 0칸', list ? wh.n == 0 : wh.n == 7, 'n ${wh.n} list $list');
            need('실행일 뒤 이 달에 고를 수 있는 주말 칸 ≥ 1(주말 색을 실제로 잰다)', dy.wkN >= 1, 'n ${dy.wkN}');
            if (!_before) {
              chk('strict 빠른 선택 그대로 = grey100 면 · grey700 아이콘/글 · 대비', qo.face == _wGrey100 && qo.icon == _wGrey700 && qo.fg == _wGrey700 && qo.cr,
                  '${qo.face}/${qo.icon}/${qo.fg}/${qo.cr}');
              chk('strict 달력 머리 그대로 = grey100 원 · brand 화살표 · textPrimary 월 제목 · 대비', no.face == _wGrey100 && no.icon == _wBrand && no.title == _wText1 && no.cr,
                  '${no.face}/${no.icon}/${no.title}/${no.cr}');
              chk('strict 캘린더 접기 그대로 = grey100/grey700 · 대비', go.face == _wGrey100 && go.fg == _wGrey700 && go.cr, '${go.face}/${go.fg}/${go.cr}');
              chk('strict 오늘 표시 그대로 = brand(7열 외곽선 · 목록 오늘 글)', dy.mark == _wBrand, 'mark ${dy.mark}');
              chk('strict 요일 머리 7칸 = grey600(주말 빨강 없음) · 흰 바탕 대비 ≥4.5(7열만)',
                  list || (wh.wkd == _wGrey600 && wh.wke == _wGrey600 && wh.worst >= 4.5), '${wh.wkd}/${wh.wke}/${wh.worst.toStringAsFixed(2)} list $list');
              chk('strict 고를 수 있고 고르지 않은 주말 날짜 = textPrimary · 대비 ≥4.5', dy.wkFg == _wText1 && dy.wkWorst >= 4.5,
                  '${dy.wkFg}/${dy.wkWorst.toStringAsFixed(2)} n ${dy.wkN}');
            }
            await shot('1empty', 'empty-top');
            pos.jumpTo(pos.maxScrollExtent);
            await t.pump(const Duration(milliseconds: 100));
            await shot('2emptyend', 'empty-end');
          } else if (c.id == 'MULTI') {
            final calF = find.descendant(of: selF, matching: find.byType(LayoutBuilder), skipOffstage: true);
            need('달력 1', calF.evaluate().length == 1, '개수 ${calF.evaluate().length}');
            final list = _isList(calF, today);
            final co = _countLine(t, tok, selF, chipText);
            final cl = _clearLine(t, tok, selF, screen);
            final so = _selLine(t, tok, calF, cfg.dates, today, prim, list);
            need('선택 건수 칩 1 · 전체 해제 1', co.n == 1 && cl.n == 1, 'count ${co.n} clear ${cl.n}');
            need('실행일이 월 마지막 날이 아님(이 달에 보이는 선택 날짜 ≥ 1)', so.want >= 1, 'want ${so.want}');
            need('보이는 선택 칸 수 = 이 달 선택 날짜 수', so.n == so.want, 'n ${so.n} want ${so.want} list $list');
            if (!_before) {
              chk('strict 선택 건수 칩 그대로 = brand 채움 · 흰 글 · 대비(감사138 4-3 유지)', co.face == _wBrand && co.fg == _wWhite && co.cr, '${co.face}/${co.fg}/${co.cr}');
              chk('strict 전체 해제 그대로 = 면 없음 · textSecondary 아이콘/글 · 대비', cl.face == _wClear && cl.icon == _wText2 && cl.fg == _wText2 && cl.cr,
                  '${cl.face}/${cl.icon}/${cl.fg}/${cl.cr}');
              chk('strict 전체 해제 보이고 눌림', cl.vis && cl.hit, 'vis ${cl.vis} hit ${cl.hit}');
              chk('strict 선택 날짜 그대로 = brand 면 · 흰 글(주말 포함)', so.face == _wBrand && so.fg == _wWhite, '${so.face}/${so.fg}');
            }
            await shot('1multi', 'multi-selected');
            // 오늘 칸 탭(이미 14일 = 최대) → 경고 토스트 · 선택 그대로 · 콜백 0.
            final todayF = _dayFinder(calF, today, list);
            need('오늘 칸 1', todayF.evaluate().length == 1, '개수 ${todayF.evaluate().length}');
            await t.ensureVisible(todayF);
            await t.pump(const Duration(milliseconds: 100));
            final tn = _tapNow(t, todayF, screen);
            need('오늘 칸 보이고 눌림', tn.vis && tn.hit, 'vis ${tn.vis} hit ${tn.hit}');
            await t.tap(todayF);
            for (var i = 0; i < 6; i++) {
              await t.pump(const Duration(milliseconds: 50));
            }
            final to = _toastObs(t);
            final seln = _selObs(t, calF, cfg.dates, today, prim, list).n;
            final cb = calls.values.fold<int>(0, (a, b) => a + b);
            _out('D549 $tok att toast n=${to.n} face=${to.face} fg=${to.fg} cr45=${to.cr} seln=$seln cb=$cb');
            need('경고 토스트 1 · 콜백 0 · 선택 수 그대로', to.n == 1 && cb == 0 && seln == so.n, 'toast ${to.n} cb $cb seln $seln/${so.n}');
            if (!_before) chk('strict 경고 토스트 그대로 = warningDark 면 · 흰 글(E-TOAST)', to.face == _wWarnDark && to.fg == _wWhite && to.cr, '${to.face}/${to.fg}/${to.cr}');
            await shot('2toast', 'max-days-toast');
            for (var i = 0; i < 3; i++) {
              await t.pump(const Duration(seconds: 1));
            }
          } else if (c.id == 'RANGE') {
            final calF = find.descendant(of: selF, matching: find.byType(LayoutBuilder), skipOffstage: true);
            need('달력 1', calF.evaluate().length == 1, '개수 ${calF.evaluate().length}');
            final list = _isList(calF, today);
            // 오늘 칸 탭 = 범위 시작(작성 화면처럼 부모가 오늘을 선택에 넣는다) → 머리 안내 · 탭 자리 안내.
            final todayF = _dayFinder(calF, today, list);
            need('오늘 칸 1', todayF.evaluate().length == 1, '개수 ${todayF.evaluate().length}');
            await t.ensureVisible(todayF);
            await t.pump(const Duration(milliseconds: 100));
            final tn = _tapNow(t, todayF, screen);
            need('오늘 칸 보이고 눌림', tn.vis && tn.hit, 'vis ${tn.vis} hit ${tn.hit}');
            await t.tap(todayF);
            for (var i = 0; i < 12; i++) {
              await t.pump(const Duration(milliseconds: 50));
            }
            final ho = _hintLine(t, tok);
            final io = _inlineLine(t, tok);
            final so = _selLine(t, tok, calF, <DateTime>[today], today, prim, list);
            need('머리 안내 1 · 칸 안내 1 · 선택 1', ho.n == 1 && io.n == 1 && so.n == 1 && so.want == 1, 'hint ${ho.n} inline ${io.n} sel ${so.n}/${so.want}');
            if (!_before) {
              chk('strict 머리 범위 안내 그대로 = grey100 면 · border 선 · grey600 아이콘 · textPrimary 글 · textSecondary 닫기 · 대비',
                  ho.face == _wGrey100 && ho.bd == _wLine && ho.icon == _wGrey600 && ho.fg == _wText1 && ho.close == _wText2 && ho.cr,
                  '${ho.face}/${ho.bd}/${ho.icon}/${ho.fg}/${ho.close}/${ho.cr}');
              chk('strict 칸 안내 그대로 = grey100 면 · grey600 아이콘 · textPrimary 글 · 대비', io.face == _wGrey100 && io.icon == _wGrey600 && io.fg == _wText1 && io.cr,
                  '${io.face}/${io.icon}/${io.fg}/${io.cr}');
              chk('strict 범위 시작 날짜 그대로 = brand 면 · 흰 글', so.face == _wBrand && so.fg == _wWhite, '${so.face}/${so.fg}');
            }
            pos.jumpTo(0);
            await t.pump(const Duration(milliseconds: 100));
            await shot('1range', 'range-start-header');
            await t.ensureVisible(find.byKey(const ValueKey('inline-range-hint')));
            await t.pump(const Duration(milliseconds: 100));
            await shot('2inline', 'range-start-inline');
          } else if (c.id == 'LOCKED') {
            final ti = _tileLine(t, tok);
            final lo = _lockLine(t, tok, selF);
            final cp = _copyLine(t, tok, selF);
            final du = _dupLine(tok, lo.n);
            need('머리 아이콘 칸 1 · 수정 불가 띠 1(옛/새 문장 중 하나)', ti.n == 1 && lo.n == 1 && cp.old + cp.neu == 1, 'tile ${ti.n} lock ${lo.n} old ${cp.old} new ${cp.neu}');
            need('수정 화면 소스 창(날짜 선택기 → 제목 칸) 1', du.win == 1, 'win ${du.win}');
            if (!_before) {
              chk('strict 머리 아이콘 칸 그대로 = grey100 면 · 그림자 색 투명 · grey600 아이콘', ti.face == _wGrey100 && ti.shadow == _wClear && ti.icon == _wGrey600,
                  '${ti.face}/${ti.shadow}/${ti.icon}');
              chk('strict 수정 불가 띠 = grey100 면 · border 선 · grey600 잠금 아이콘(삼각형 0) · textSecondary 글 · 대비',
                  lo.face == _wGrey100 && lo.bd == _wLine && lo.icon == _wGrey600 && lo.fg == _wText2 && lo.cr && lo.shape == 'lock',
                  '${lo.face}/${lo.bd}/${lo.icon}/${lo.fg}/${lo.cr}/${lo.shape}/${lo.isz}');
              chk('strict 안내 = 완전한 문장 1 · 옛 보간 문장 0 · 조사 보간 흔적 0 · 읽기 도구 이름 = 원문', cp.old == 0 && cp.neu == 1 && cp.bad == 0 && cp.sem,
                  'old ${cp.old} new ${cp.neu} bad ${cp.bad} sem ${cp.sem}');
              chk('strict 수정 화면 같은 뜻 안내 = 1(선택기 안 1 + 부모 반복 0)', du.ui == 1 && du.src == 0 && du.total == 1, 'ui ${du.ui} src ${du.src} total ${du.total}');
            }
            await shot('1locked', 'read-only');
          } else if (c.id == 'PERIOD') {
            final pe = _periodLine(t, tok, selF, prim);
            final rq = _reqLine(t, tok, selF);
            final fd = _fieldLine(t, tok, selF);
            final ar = _arrowLine(t, tok);
            final inf = _infoLine(t, tok, selF);
            final wk = _wkbLine(t, tok, selF, prim);
            final sm = _sumLine(t, tok, selF);
            need('기간 칩 6 · 고른 것 1 · 필수 1 · 날짜 칸 2(채움 2) · 화살표 1 · 안내 띠 1 · 요일 7(고른 것 4) · 요약 1',
                pe.n == 6 && pe.sel == 1 && rq.n == 1 && fd.n == 2 && fd.filled == 2 && ar.n == 1 && inf.n == 1 && wk.n == 7 && wk.sel == 4 && sm.n == 1,
                'period ${pe.n}/${pe.sel} req ${rq.n} field ${fd.n}/${fd.filled} arrow ${ar.n} info ${inf.n} wkb ${wk.n}/${wk.sel} sum ${sm.n}');
            if (!_before) {
              chk('strict 기간 칩 그대로(고른 것 brand/흰 · 나머지 grey100/grey300/grey700 · 대비)',
                  pe.sface == _wBrand && pe.sfg == _wWhite && pe.uface == _wGrey100 && pe.ubd == _wGrey300 && pe.ufg == _wGrey700 && pe.cr,
                  '${pe.sface}/${pe.sfg}/${pe.uface}/${pe.ubd}/${pe.ufg}/${pe.cr}');
              chk("strict '필수' 그대로 = errorBg/errorDark · 대비", rq.face == _wErrBg && rq.fg == _wErrDark && rq.cr, '${rq.face}/${rq.fg}/${rq.cr}');
              chk('strict 값 있는 날짜 칸 = 흰 면 · border 선 · 두께 2 그대로 · textPrimary 값 · 대비(감사138 4-2)',
                  fd.fface == _wWhite && fd.fbd == _wLine && fd.fbw == '2.0' && fd.vfg == _wText1 && fd.cr, '${fd.fface}/${fd.fbd}/${fd.fbw}/${fd.vfg}/${fd.cr}');
              chk('strict 화살표 그대로 = grey600', ar.icon == _wGrey600, ar.icon);
              chk('strict 시작 가능기간 안내 띠 그대로 = grey100 면 · border 선 · grey600 아이콘 · textSecondary 글 · 대비',
                  inf.face == _wGrey100 && inf.bd == _wLine && inf.icon == _wGrey600 && inf.fg == _wText2 && inf.cr, '${inf.face}/${inf.bd}/${inf.icon}/${inf.fg}/${inf.cr}');
              chk('strict 요일 버튼 = 고른 것 brand/흰(토 포함) · 고르지 않은 평일 · 주말 모두 grey100/textPrimary · 대비 ≥4.5',
                  wk.sface == _wBrand && wk.sfg == _wWhite && wk.uface == _wGrey100 && wk.ufg == _wText1 && wk.eface == _wGrey100 && wk.efg == _wText1 && wk.worst >= 4.5,
                  '${wk.sface}/${wk.sfg}/${wk.uface}/${wk.ufg}/${wk.eface}/${wk.efg}/${wk.ecr}');
              chk('strict 요일 요약 띠 그대로 = grey100 면 · border 선 · grey600 아이콘 · textPrimary 제목 · textSecondary 상세 · 대비',
                  sm.face == _wGrey100 && sm.bd == _wLine && sm.icon == _wGrey600 && sm.tfg == _wText1 && sm.dfg == _wText2 && sm.cr,
                  '${sm.face}/${sm.bd}/${sm.icon}/${sm.tfg}/${sm.dfg}/${sm.cr}');
            }
            // [DU549] 제목 + 필수 표지 배치(감사138 F138-DATESELECTOR-B-LAYOUT · 39px Row) — 범위 칸 묶음을 끌어 보이게 하고 잰 뒤 맨 위로 되돌린다.
            final wantPlace = v.id == 'W' ? 'side' : 'below';
            final ly = await _layLine(t, tok, selF, screen);
            need('제목 · 필수 · 설명 글 · 15일 칩 글 각 1', ly.n, 'n ${ly.n}');
            if (!_before) {
              chk('strict 제목 · 필수 표지 전문이 화면 ∩ 스크롤 칸 안 · 제목 한 줄(같은 크기 칩 글과 높이 같음 — 낱말 안 끊김 0)', ly.tvis && ly.cvis && ly.one,
                  'tvis ${ly.tvis} cvis ${ly.cvis} one ${ly.one}');
              chk('strict 표지 자리 = W 제목 오른쪽 같은 줄(이전과 같음) · B 제목 아래 줄 왼쪽(줄바꿈)', ly.place == wantPlace, 'place ${ly.place} want $wantPlace gap ${ly.gap}');
            }
            pos.jumpTo(0);
            await t.pump(const Duration(milliseconds: 100));
            await shot('1period', 'period-top');
            pos.jumpTo(pos.maxScrollExtent);
            await t.pump(const Duration(milliseconds: 100));
            await shot('2weekdays', 'period-weekdays');
          } else {
            final pe = _periodLine(t, tok, selF, prim);
            final fd = _fieldLine(t, tok, selF);
            final ar = _arrowLine(t, tok);
            final wk = _wkbLine(t, tok, selF, prim);
            need('기간 칩 6 · 고른 것 1 · 날짜 칸 2(채움 1) · 화살표 1 · 요일 7(고른 것 0)',
                pe.n == 6 && pe.sel == 1 && fd.n == 2 && fd.filled == 1 && ar.n == 1 && wk.n == 7 && wk.sel == 0,
                'period ${pe.n}/${pe.sel} field ${fd.n}/${fd.filled} arrow ${ar.n} wkb ${wk.n}/${wk.sel}');
            if (!_before) {
              chk('strict 기간 칩 그대로(직접 입력 = 고른 것 brand/흰 · 나머지 grey100/grey300/grey700 · 대비)',
                  pe.sface == _wBrand && pe.sfg == _wWhite && pe.uface == _wGrey100 && pe.ubd == _wGrey300 && pe.ufg == _wGrey700 && pe.cr,
                  '${pe.sface}/${pe.sfg}/${pe.uface}/${pe.ubd}/${pe.ufg}/${pe.cr}');
              chk("strict 빈 날짜 칸 '선택하세요' 그대로 = textTertiary · grey50 면 · border 선 · 대비",
                  fd.hfg == _wText3 && fd.eface == _wGrey50 && fd.ebd == _wLine && fd.cr, '${fd.hfg}/${fd.eface}/${fd.ebd}/${fd.cr}');
              chk('strict 값 있는 날짜 칸 = 흰 면 · border 선 · 두께 2 그대로 · textPrimary 값(감사138 4-2)',
                  fd.fface == _wWhite && fd.fbd == _wLine && fd.fbw == '2.0' && fd.vfg == _wText1, '${fd.fface}/${fd.fbd}/${fd.fbw}/${fd.vfg}');
              chk('strict 화살표 그대로 = grey600', ar.icon == _wGrey600, ar.icon);
              chk('strict 요일 버튼(고른 것 0) = 평일 · 주말 모두 grey100/textPrimary · 대비 ≥4.5',
                  wk.uface == _wGrey100 && wk.ufg == _wText1 && wk.eface == _wGrey100 && wk.efg == _wText1 && wk.worst >= 4.5,
                  '${wk.uface}/${wk.ufg}/${wk.eface}/${wk.efg}/${wk.ecr}');
            }
            await shot('1custom', 'custom-start-only');
          }
        } catch (e, st) {
          failure = e;
          failureSt = st;
        } finally {
          FlutterError.onError = prevOnError;
        }

        // 성공 · 실패 공통 정리 — 화면을 내리고 남은 timer(토스트 2초 · 애니메이션)가 끝날 시간을 준다.
        var cleanupErr = '';
        try {
          await t.pumpWidget(const SizedBox.shrink());
          for (var i = 0; i < 3; i++) {
            await t.pump(const Duration(seconds: 1));
          }
        } catch (e, st) {
          cleanupErr = e.toString();
          if (failure == null) {
            failure = e;
            failureSt = st;
          }
        }

        // 집계 — 예상 밖 플랫폼 채널(서버 · 저장소 포함) · HTTP · 부모 콜백 수(오늘 칸 탭이 부른 것).
        final nUnexp = wire.unexpected.length;
        final nHttp = net.tries.length;
        final nCb = calls.values.fold<int>(0, (a, b) => a + b);
        _out('D549 $tok att wire unexpected=$nUnexp http=$nHttp cb=$nCb');

        messenger.allMessagesHandler = prevAll;
        HttpOverrides.global = prevHttp;
        final exc = t.takeException();
        if (exc != null && failure == null) {
          failure = exc;
          failureSt = StackTrace.current;
        }
        final nOvf = seen.overflows.length;
        final nFw = seen.other.length;
        final ovfRaw = seen.overflows.take(8).join('\n----\n');
        final fwRaw = seen.other.take(4).map((m) => m.length > 400 ? m.substring(0, 400) : m).join('\n----\n');
        _out('R549 $tok raw calls=${_enc(calls.toString())} ovf64=${_enc(ovfRaw)} fw64=${_enc(fwRaw)} un64=${_enc(wire.unexpected.join(' | '))} '
            'cleanup64=${_enc(cleanupErr)} fail64=${_enc(failure?.toString() ?? '')}');
        _out('D549 $tok att fw n=$nFw');
        _out('D549 $tok done state=${c.id} mode=$mode captures=$shots overflows=$nOvf exc=${exc != null}');

        final f0 = failure;
        if (f0 != null) {
          _halt ??= '$tok ${f0.toString().split('\n').first}';
          Error.throwWithStackTrace(f0, failureSt ?? StackTrace.current);
        }
        final wantCb = c.id == 'RANGE' ? 1 : 0;
        chk('예상 밖 채널 0 · HTTP 0 · 콜백 = 오늘 칸 탭이 부른 수', nUnexp == 0 && nHttp == 0 && nCb == wantCb, 'unexpected $nUnexp http $nHttp cb $nCb/$wantCb');
        // [DU549] before B PERIOD 는 그 Row 39px 1건(DU542b TA.jsonl:178 — 기록만). 후보는 W · B 모든 사례 0.
        if (!_before) chk('strict 화면 전체 넘침 0(W · B — B PERIOD 제목 · 필수 표지 39px Row 교정 · 감사138 F138-DATESELECTOR-B-LAYOUT)', nOvf == 0, ovfRaw);
        if (!_before) chk('strict 미처리 framework 예외 0', nFw == 0, fwRaw);
        chk('캡처 수 = 선언', shots == c.shots, 'shots $shots want ${c.shots}');
        final bad = checks.where((x) => !x.$2).toList();
        if (bad.isNotEmpty) _halt ??= '$tok ${bad.first.$1}';
        for (final x in checks) {
          expect(x.$2, isTrue, reason: '$tok ${x.$1} ${x.$3}');
        }
      }, skip: !_optIn);
    }
  }
}
