// [DU545 · 색만] 지원자 근무 일정 카드(ScheduleCard) 색 예산 1차 — 상태 칩 = StatusBadge 짝(옅은 면 + 진한 글) · 업무 아이콘 없음 칸 중립 ·
//   고정근무 띠 중립(면 grey100 · 별 grey600 · 제목 textPrimary · 상세 textSecondary) · 급여 명세서 아이콘 버튼 brand(행동).
//   근거 = 요청 (2) 판정 규칙 · 같은 의미 = 같은 토큰(my_applications_screen.dart:2048–2105 · :600–607 · schedule_detail_dialog.dart:136–149 ·
//     income_detail_screen.dart:934) · DU425–427(칩 바탕 = StatusBadge Bg 짝 · 글 = 진한 짝) · 감사138 §5(checkedOut 계열 · 업무 저장색 보존).
//   before = 현재 A(schedule_card 01898993) 기록 전용 · strict = 후보(d97c2899).
//   하네스 = worker_display_truth_fix_test.dart 의 대역 방식(_app · _att 고정값 · UserProvider 하위 클래스 _P 를 ChangeNotifierProvider 로 · ScheduleCard 직접 pump)
//     — 단 Firebase 코어 대역 대신 AuthService 를 Fake 로 넘겨(auth_session_boundary_test.dart:59 와 같은 방식) Firebase 를 아예 만들지 않는다.
//     카드는 그릴 때 서버를 부르지 않는다(급여 명세서 · 상세 시트는 누를 때만) — 플랫폼 메시지 전수 관찰(기반 채널만 원래 경로)과 외부 HTTP 차단으로 0 을 확인한다.
//   사례 16 = 상태 칩 갈래 전부(그려지는 15 갈래 · 정산 완료/송금 완료는 같은 갈래의 두 글). 누르는 것 0. W 390×844@1.0 · B 320×640@2.0.
//   계약 서명 줄(yellowWarn · pending_contract_bar 와 같은 짝)은 바꾸지 않고 그리지 않는다(서명 대기 계약 대역 0 — 미관측).
//   기본 skip — TB before/du545-tb/DU_BEFORE_OBSERVE=545 · TA after/du545-ta/없음.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';

import 'package:ALfit/models/core/application_model.dart';
import 'package:ALfit/models/core/attendance_model.dart';
import 'package:ALfit/models/core/wage_detail_model.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/services/auth_service.dart';
import 'package:ALfit/theme/app_colors.dart';
import 'package:ALfit/theme/role_theme.dart';
import 'package:ALfit/utils/responsive_helper.dart';
import 'package:ALfit/widgets/calendar/schedule_card.dart';

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

/// 모든 플랫폼 메시지 관찰 — 기반 채널은 원래 경로, 나머지(CF · Firestore · Auth · 그 밖)는 이름을 기록하고 응답 null.
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
    throw const SocketException('DU545 관측 — 외부 HTTP 차단');
  }
}

/// 인증 대역 — 카드는 인증을 읽지 않는다(UserProvider 생성자가 기본 AuthService 로 FirebaseAuth 를 만들지 않게 할 뿐).
class _NoAuth extends Fake implements AuthService {}

/// worker_display_truth_fix_test.dart:99 의 _P 와 같은 자리 — 서명 대기 계약 0(pendingContractForTo = null).
class _P extends UserProvider {
  _P() : super(authService: _NoAuth());
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

/// Container 하나의 면 색(BoxDecoration.color · 없으면 투명).
Color _faceOf(WidgetTester t, Finder box) {
  final c = t.widget<Container>(box);
  final d = c.decoration;
  return d is BoxDecoration ? (d.color ?? Colors.transparent) : (c.color ?? Colors.transparent);
}

/// [box] 안 Icon 이 하나면 그 색, 아니면 null.
Color? _oneIcon(WidgetTester t, Finder box) {
  final f = find.descendant(of: box, matching: find.byType(Icon), skipOffstage: true);
  if (f.evaluate().length != 1) return null;
  return t.widget<Icon>(f).color;
}

// ── 고정값 — worker_display_truth_fix_test.dart:25–76 의 _kst · _app · _att 틀(업무 아이콘 · 장기 · 급여 상세 인자만 더했다) ──

DateTime _kst(int y, int mo, int d, [int h = 0, int mi = 0]) => DateTime.utc(y, mo, d, h, mi).subtract(const Duration(hours: 9));

final DateTime _future = _kst(2099, 1, 5);
final DateTime _past = _kst(2026, 10, 12);

const _biz = '골든패스 사업장';
const _wt = 'QA 분류';

ApplicationModel _app(
  String id, {
  required DateTime workDate,
  String status = AppStatus.confirmed,
  String? icon,
  String? iconColor,
  String? iconBg,
  List<String>? workDays,
  DateTime? workEndDate,
}) =>
    ApplicationModel(
      id: id,
      toId: 'to_$id',
      uid: 'u1',
      businessId: 'biz1',
      businessName: _biz,
      toTitle: 'QA',
      status: status,
      selectedWorkType: _wt,
      startTime: '10:00',
      endTime: '11:00',
      wage: 12000,
      wageType: 'hourly',
      workDate: workDate,
      appliedAt: workDate.subtract(const Duration(days: 3)),
      workTypeIcon: icon,
      workTypeColor: iconColor,
      workTypeBackgroundColor: iconBg,
      workDays: workDays,
      workEndDate: workEndDate,
    );

AttendanceModel _att(
  String appId, {
  required DateTime workDate,
  String status = AttendanceModel.statusPresent,
  bool checkIn = false,
  bool checkOut = false,
  String wageStatus = 'pending',
  bool wage = false,
}) =>
    AttendanceModel(
      id: 'att-$appId',
      applicationId: appId,
      userId: 'u1',
      businessId: 'biz1',
      businessName: _biz,
      workDate: workDate,
      workType: _wt,
      checkInAt: checkIn ? workDate.add(const Duration(hours: 10)) : null,
      checkOutAt: checkOut ? workDate.add(const Duration(hours: 11)) : null,
      status: status,
      wageStatus: wageStatus,
      finalWage: wage ? 12000 : null,
      wageDetail: wage ? WageDetailModel(wageType: 'hourly', baseWage: 12000) : null,
      createdAt: workDate,
    );

typedef _Fx = ({ApplicationModel app, AttendanceModel? att});

/// 상태 칩 갈래마다 한 장 — schedule_card.dart _getDisplayStatus(:465–553) · _getStatusInfo(:417–462) 의 분기 순서를 그대로 밟는 입력.
_Fx _fixOf(String id) {
  switch (id) {
    case 'PLAN': // 확정 · 근태 없음 · 아직 오지 않은 근무(:502–508) — 업무 저장색 칸(E-USERCOLOR)
      return (app: _app('plan', workDate: _future, icon: 'inventory', iconColor: '#1565C0', iconBg: '#E3F2FD'), att: null);
    case 'READY': // 확정 · 근태 있음 · 출근 전(:547–552) — 장기(고정근무 띠) · 업무 아이콘 없음 칸
      return (
        app: _app('ready', workDate: _future, workDays: const ['월', '수', '금'], workEndDate: _kst(2099, 2, 5)),
        att: _att('ready', workDate: _future),
      );
    case 'NOREC': // 확정 · 근태 없음 · 예정 시간 끝남(:493–500)
      return (app: _app('norec', workDate: _past), att: null);
    case 'WORKING': // 출근만(:539–545)
      return (app: _app('work', workDate: _past), att: _att('work', workDate: _past, checkIn: true));
    case 'SETTLING': // 퇴근 · 급여 pending(:530–536)
      return (app: _app('settle', workDate: _past), att: _att('settle', workDate: _past, checkIn: true, checkOut: true));
    case 'CALC': // 급여 calculated(:520–526)
      return (app: _app('calc', workDate: _past), att: _att('calc', workDate: _past, checkIn: true, checkOut: true, wageStatus: 'calculated'));
    case 'PAID': // 급여 confirmed(:511–517) — 급여 명세서 아이콘 버튼(:364–379)
      return (app: _app('paid', workDate: _past), att: _att('paid', workDate: _past, checkIn: true, checkOut: true, wageStatus: 'confirmed', wage: true));
    case 'SENT': // 급여 transferred(:511–517)
      return (app: _app('sent', workDate: _past), att: _att('sent', workDate: _past, checkIn: true, checkOut: true, wageStatus: 'transferred', wage: true));
    case 'NOSHOW': // 계약 대기 + 노쇼(:468–476 · DEV 재현 SC-1 과 같은 입력)
      return (
        app: _app('noshow', workDate: _past, status: AppStatus.contractPending),
        att: _att('noshow', workDate: _past, status: AttendanceModel.statusNoShow),
      );
    case 'ABSENT': // 확정 + 결근(:477–483)
      return (app: _app('absent', workDate: _past), att: _att('absent', workDate: _past, status: AttendanceModel.statusAbsent));
    case 'PENDING':
      return (app: _app('pend', workDate: _future, status: AppStatus.pending), att: null);
    case 'CONTRACT':
      return (app: _app('contract', workDate: _future, status: AppStatus.contractPending), att: null);
    case 'REJECTED':
      return (app: _app('rej', workDate: _future, status: AppStatus.rejected), att: null);
    case 'CANCELED':
      return (app: _app('can', workDate: _future, status: AppStatus.canceled), att: null);
    case 'AUTOCANCEL':
      return (app: _app('auto', workDate: _future, status: AppStatus.autoCanceled), att: null);
    default: // UNKNOWN — 목록에 없는 상태(:455–460)
      return (app: _app('unk', workDate: _future, status: AppStatus.expired), att: null);
  }
}

/// 상태 → (칩 글, 진한 글/아이콘, 옅은 면, 대비 ≥4.5 단언) — 후보 mk_cand S2–S16 과 같은 표. info 짝 3갈래는 4.03(판정 요청)이라 대비를 기록만 한다.
const _chips = <String, (String, Color, Color, bool)>{
  'PLAN': ('확정', AppColors.successDark, AppColors.successBg, true),
  'READY': ('확정', AppColors.successDark, AppColors.successBg, true),
  'NOREC': ('출근 기록 없음', AppColors.warningDark, AppColors.warningBg, true),
  'WORKING': ('근무 중', AppColors.tealDark, AppColors.tealBg, true),
  'SETTLING': ('정산 중', AppColors.purple, AppColors.purpleBg, true),
  'CALC': ('정산 대기', AppColors.warningDark, AppColors.warningBg, true),
  'PAID': ('정산 완료', AppColors.infoDark, AppColors.infoBg, false),
  'SENT': ('송금 완료', AppColors.infoDark, AppColors.infoBg, false),
  'NOSHOW': ('노쇼', AppColors.errorDark, AppColors.errorBg, true),
  'ABSENT': ('결근', AppColors.warningDark, AppColors.warningBg, true),
  'PENDING': ('대기', AppColors.warningDark, AppColors.warningBg, true),
  'CONTRACT': ('계약 진행 중', AppColors.infoDark, AppColors.infoBg, false),
  'REJECTED': ('거절', AppColors.errorDark, AppColors.errorBg, true),
  'CANCELED': ('취소', AppColors.textSecondary, AppColors.grey100, true),
  'AUTOCANCEL': ('자동 취소', AppColors.textSecondary, AppColors.grey100, true),
  'UNKNOWN': ('알 수 없음', AppColors.textSecondary, AppColors.grey100, true),
};

final String _wBrand = _hex(AppColors.brand);
final String _wText1 = _hex(AppColors.textPrimary);
final String _wText2 = _hex(AppColors.textSecondary);
final String _wGrey100 = _hex(AppColors.grey100);
final String _wGrey500 = _hex(AppColors.grey500);
final String _wGrey600 = _hex(AppColors.grey600);
final String _wGrey700 = _hex(AppColors.grey700);
const String _wUserFace = 'ffe3f2fd';
const String _wUserIcon = 'ff1565c0';
const String _wCardLine = 'ffe8e9ed';

// ── 측정(위젯 값만 · rect 0) — 출력 줄은 sub 마다 하나 ──

typedef _ChipObs = ({int n, String face, String icon, String fg, double cr});

/// 상태 칩 — 글 [lab] 의 가장 가까운 Container(칩 상자) 면 · 그 안 아이콘 · 글 색 · 대비(면을 카드 바탕에 얹어서).
_ChipObs _chipLine(WidgetTester t, String tok, Finder cardF, String lab, Color cardFace) {
  final f = find.descendant(of: cardF, matching: find.text(lab), skipOffstage: true);
  final n = f.evaluate().length;
  var face = '-';
  var icon = '-';
  var fg = '-';
  var cr = 0.0;
  var cr45 = false;
  if (n == 1) {
    final box = find.ancestor(of: f, matching: find.byType(Container)).first;
    final fc = _faceOf(t, box);
    final gc = _fgOf(t, f);
    face = _hex(fc);
    icon = _h(_oneIcon(t, box));
    fg = _hex(gc);
    cr = _contrast(gc, Color.alphaBlend(fc, cardFace));
    cr45 = cr >= 4.5;
  }
  _out('D545 $tok att chip n=$n lab=${_enc(lab)} face=$face icon=$icon fg=$fg cr=${cr.toStringAsFixed(2)} cr45=$cr45');
  return (n: n, face: face, icon: icon, fg: fg, cr: cr);
}

typedef _WiconObs = ({int n, String src, String face, String icon});

/// 업무명 줄의 앞 칸 — 업무 저장색 칸(WorkTypeIcon) 또는 아이콘 없음 칸의 면 · 아이콘 색.
_WiconObs _wiconLine(WidgetTester t, String tok, Finder cardF, bool user) {
  final f = find.descendant(of: cardF, matching: find.text(_wt), skipOffstage: true);
  final n = f.evaluate().length;
  final src = user ? 'user' : 'box';
  var face = '-';
  var icon = '-';
  if (n == 1) {
    final row = find.ancestor(of: f, matching: find.byType(Row)).first;
    final box = find.descendant(of: row, matching: find.byType(Container), skipOffstage: true).first;
    face = _hex(_faceOf(t, box));
    icon = _h(_oneIcon(t, box));
  }
  _out('D545 $tok att wicon n=$n src=$src face=$face icon=$icon');
  return (n: n, src: src, face: face, icon: icon);
}

typedef _BandObs = ({int n, String face, String icon, String tfg, String dfg, bool cr});

/// 고정근무 띠 — 띠 상자 면 · 별 · '고정근무' 글 · 요일/기간 글 색 · 대비.
_BandObs _bandLine(WidgetTester t, String tok, Finder cardF, Color cardFace) {
  final f = find.descendant(of: cardF, matching: find.text('고정근무'), skipOffstage: true);
  final n = f.evaluate().length;
  var face = '-';
  var icon = '-';
  var tfg = '-';
  var dfg = '-';
  var cr = false;
  if (n == 1) {
    final box = find.ancestor(of: f, matching: find.byType(Container)).first;
    final fc = _faceOf(t, box);
    final tc = _fgOf(t, f);
    final others = find.descendant(of: box, matching: find.byType(Text), skipOffstage: true).evaluate().map((e) => e.widget as Text).where((w) => w.data != '고정근무').toList();
    final dc = others.length == 1 ? (others.first.style?.color ?? Colors.black) : null;
    final star = find.descendant(of: box, matching: find.byIcon(Icons.star), skipOffstage: true);
    face = _hex(fc);
    icon = star.evaluate().length == 1 ? _h(t.widget<Icon>(star).color) : '-';
    tfg = _hex(tc);
    dfg = _h(dc);
    final bg = Color.alphaBlend(fc, cardFace);
    cr = dc != null && _contrast(tc, bg) >= 4.5 && _contrast(dc, bg) >= 4.5;
  }
  _out('D545 $tok att band n=$n face=$face icon=$icon tfg=$tfg dfg=$dfg cr45=$cr');
  return (n: n, face: face, icon: icon, tfg: tfg, dfg: dfg, cr: cr);
}

/// 급여 명세서 아이콘 버튼(급여 확정 · 송금 때만) — 버튼 색. 누르지 않는다.
({int n, String c}) _slipLine(WidgetTester t, String tok, Finder cardF) {
  final f = find.descendant(of: cardF, matching: find.byType(IconButton), skipOffstage: true);
  final n = f.evaluate().length;
  final c = n == 1 ? _h(t.widget<IconButton>(f).color) : '-';
  _out('D545 $tok att slip n=$n c=$c');
  return (n: n, c: c);
}

typedef _KeepObs = ({String biz, String bizic, String wt, String clock, String time, String wage, String card, String cbd});

/// 그대로인 요소 — 사업장명 · 사업장 아이콘 · 업무명 · 시계 아이콘 · 예정시간 · 급여 · 카드 면 · 카드 선.
_KeepObs _keepLine(WidgetTester t, String tok, Finder cardF) {
  String textColor(Finder f) => f.evaluate().length == 1 ? _hex(_fgOf(t, f)) : '-';
  String iconColor(IconData d) {
    final f = find.descendant(of: cardF, matching: find.byIcon(d), skipOffstage: true);
    return f.evaluate().length == 1 ? _h(t.widget<Icon>(f).color) : '-';
  }

  final biz = textColor(find.descendant(of: cardF, matching: find.text(_biz), skipOffstage: true));
  final wt = textColor(find.descendant(of: cardF, matching: find.text(_wt), skipOffstage: true));
  final wrap = find.descendant(of: cardF, matching: find.byType(Wrap), skipOffstage: true);
  var time = '-';
  var wage = '-';
  if (wrap.evaluate().length == 1) {
    final ts = find.descendant(of: wrap, matching: find.byType(Text), skipOffstage: true).evaluate().map((e) => e.widget as Text).toList();
    if (ts.length == 2) {
      time = _h(ts[0].style?.color);
      wage = _h(ts[1].style?.color);
    }
  }
  final outer = t.widget<Container>(find.descendant(of: cardF, matching: find.byType(Container), skipOffstage: true).first).decoration;
  final card = outer is BoxDecoration ? _h(outer.color) : '-';
  final bd = outer is BoxDecoration ? outer.border : null;
  final cbd = bd is Border ? _hex(bd.top.color) : '-';
  final o = (biz: biz, bizic: iconColor(Icons.business), wt: wt, clock: iconColor(Icons.access_time), time: time, wage: wage, card: card, cbd: cbd);
  _out('D545 $tok att keep biz=${o.biz} bizic=${o.bizic} wt=${o.wt} clock=${o.clock} time=${o.time} wage=${o.wage} card=${o.card} cbd=${o.cbd}');
  return o;
}

typedef _V = ({String id, double w, double h, double s});
const _views = <_V>[(id: 'W', w: 390.0, h: 844.0, s: 1.0), (id: 'B', w: 320.0, h: 640.0, s: 2.0)];
const _cases = <({String id, int shots})>[
  (id: 'PLAN', shots: 1), (id: 'READY', shots: 1), (id: 'NOREC', shots: 1), (id: 'WORKING', shots: 1), (id: 'SETTLING', shots: 1), (id: 'CALC', shots: 1),
  (id: 'PAID', shots: 1), (id: 'SENT', shots: 1), (id: 'NOSHOW', shots: 1), (id: 'ABSENT', shots: 1), (id: 'PENDING', shots: 1), (id: 'CONTRACT', shots: 1),
  (id: 'REJECTED', shots: 1), (id: 'CANCELED', shots: 1), (id: 'AUTOCANCEL', shots: 1), (id: 'UNKNOWN', shots: 1),
];

final bool _before = Platform.environment['DU_BEFORE_OBSERVE'] == '545';
final Map<String, String> _env = Platform.environment;
final bool _optIn =
    (_env['DU1_VQ_PHASE'] == 'before' && _env['DU1_VQ_RUN'] == 'du545-tb' && _env['DU_BEFORE_OBSERVE'] == '545') ||
        (_env['DU1_VQ_PHASE'] == 'after' && _env['DU1_VQ_RUN'] == 'du545-ta' && _env['DU_BEFORE_OBSERVE'] == null);

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
    _out('R545 setup init unexpected=$nUnexp http=$nHttp un64=${_enc(wire.unexpected.join('|'))}');
    final initOk = nUnexp == 0 && nHttp == 0;
    if (!initOk) _halt = 'setUpAll 초기화 안전 대역';
    expect(initOk, isTrue, reason: 'setUpAll 초기화 중 예상 밖 채널 0 · HTTP 0 — [${wire.unexpected.join(' | ')}]');
  });

  for (final v in _views) {
    for (final c in _cases) {
      testWidgets('S913SC-${v.id}-${c.id} 지원자 근무 일정 카드 색 1차 — 상태 칩 StatusBadge 짝 · 업무 칸 · 고정근무 띠 중립 · 명세서 brand', (t) async {
        final tok = 'S913SC-${v.id}-${c.id}';
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
        _out('D545 $tok begin mode=$mode phase=${Platform.environment['DU1_VQ_PHASE'] ?? '(unset)'} env=$_envLine manifest=$_manifest');
        final seen = _Seen();
        void need(String k, bool ok, [String why = '']) => expect(ok, isTrue, reason: '$tok $k $why');
        final checks = <(String, bool, String)>[];
        void chk(String k, bool ok, [String why = '']) => checks.add((k, ok, why));

        final fx = _fixOf(c.id);
        final want = _chips[c.id]!;
        Object? failure;
        StackTrace? failureSt;
        var shots = 0;
        try {
          FlutterError.onError = seen.add;
          final key = GlobalKey();
          await t.pumpWidget(RepaintBoundary(
            key: key,
            child: ChangeNotifierProvider<UserProvider>(
              create: (_) => _P(),
              child: MaterialApp(
                debugShowCheckedModeBanner: false,
                theme: RoleTheme.workerTheme,
                locale: const Locale('ko', 'KR'),
                supportedLocales: const [Locale('ko', 'KR'), Locale('en', 'US')],
                localizationsDelegates: const [
                  GlobalMaterialLocalizations.delegate,
                  GlobalWidgetsLocalizations.delegate,
                  GlobalCupertinoLocalizations.delegate,
                ],
                builder: (ctx, child) => MediaQuery(data: MediaQuery.of(ctx).copyWith(textScaler: TextScaler.linear(v.s)), child: child!),
                // 일정 화면 목록과 같은 바깥 여백(my_schedule_screen.dart:1615–1621 SliverPadding — 좌우 spacing 16 · 위아래 4).
                home: Scaffold(
                  body: Builder(
                    builder: (ctx) => SingleChildScrollView(
                      padding: EdgeInsets.fromLTRB(ResponsiveHelper.spacing(ctx, 16), ResponsiveHelper.spacing(ctx, 4), ResponsiveHelper.spacing(ctx, 16),
                          ResponsiveHelper.spacing(ctx, 4)),
                      child: ScheduleCard(application: fx.app, attendance: fx.att),
                    ),
                  ),
                ),
              ),
            ),
          ));
          for (var i = 0; i < 10; i++) {
            await t.pump(const Duration(milliseconds: 50));
          }
          final cardF = find.byType(ScheduleCard);
          final nCard = cardF.evaluate().length;
          need('카드 1', nCard == 1, '개수 $nCard');

          // 그려진 글 집합(숫자는 # · 보이지 않는 낱말 묶음 문자 제거). 기록용: TB · TA 의 set 을 손으로 대조한다(문구 변경 0).
          final words = <String>{};
          for (final e in find.descendant(of: cardF, matching: find.byType(Text), skipOffstage: true).evaluate()) {
            final d = (e.widget as Text).data;
            if (d != null && d.isNotEmpty) words.add(visibleText(d).replaceAll(RegExp(r'\d+'), '#'));
          }
          final wordList = words.toList()..sort();
          _out('D545 $tok att txt n=${wordList.length} set=${_enc(wordList.join('|'))}');

          // 카드 바탕(theme.cardColor) — 칩 · 띠 대비의 바탕.
          final outer = t.widget<Container>(find.descendant(of: cardF, matching: find.byType(Container), skipOffstage: true).first).decoration;
          final cardFace = outer is BoxDecoration ? (outer.color ?? Colors.white) : Colors.white;

          final co = _chipLine(t, tok, cardF, want.$1, cardFace);
          final wo = _wiconLine(t, tok, cardF, fx.app.workTypeIcon != null);
          final bo = _bandLine(t, tok, cardF, cardFace);
          final so = _slipLine(t, tok, cardF);
          final ko = _keepLine(t, tok, cardF);
          final wantBand = c.id == 'READY' ? 1 : 0;
          final wantSlip = c.id == 'PAID' || c.id == 'SENT' ? 1 : 0;
          need('상태 칩 글 1(분기 그대로)', co.n == 1, '${want.$1} n ${co.n}');
          need('업무명 1', wo.n == 1, 'n ${wo.n}');
          need('고정근무 띠 수(장기만)', bo.n == wantBand, 'n ${bo.n} want $wantBand');
          need('급여 명세서 버튼 수(확정 · 송금만)', so.n == wantSlip, 'n ${so.n} want $wantSlip');
          // 그대로인 요소 — 두 모드 같은 값(후보는 이 줄들을 바꾸지 않는다).
          chk('그대로 = 사업장명 grey700 · 사업장 아이콘 grey600 · 업무명 grey700 · 시계 grey500 · 예정시간 textPrimary · 급여 brand · 카드 선 E8E9ED',
              ko.biz == _wGrey700 && ko.bizic == _wGrey600 && ko.wt == _wGrey700 && ko.clock == _wGrey500 && ko.time == _wText1 && ko.wage == _wBrand && ko.cbd == _wCardLine,
              '${ko.biz}/${ko.bizic}/${ko.wt}/${ko.clock}/${ko.time}/${ko.wage}/${ko.cbd}');
          if (wo.src == 'user') {
            chk('그대로 = 업무 저장색 칸(E-USERCOLOR) 면 #E3F2FD · 아이콘 #1565C0', wo.face == _wUserFace && wo.icon == _wUserIcon, '${wo.face}/${wo.icon}');
          }
          if (!_before) {
            chk('strict 상태 칩 = StatusBadge 짝(옅은 면 ${_hex(want.$3)} · 진한 글/아이콘 ${_hex(want.$2)})',
                co.face == _hex(want.$3) && co.fg == _hex(want.$2) && co.icon == _hex(want.$2), '${co.face}/${co.fg}/${co.icon}');
            if (want.$4) chk('strict 상태 칩 대비 ≥4.5', co.cr >= 4.5, co.cr.toStringAsFixed(2));
            if (wo.src == 'box') chk('strict 업무 아이콘 없음 칸 = grey100 면 · grey600 아이콘', wo.face == _wGrey100 && wo.icon == _wGrey600, '${wo.face}/${wo.icon}');
            if (bo.n == 1) {
              chk('strict 고정근무 띠 = grey100 면 · grey600 별 · textPrimary 제목 · textSecondary 상세 · 대비',
                  bo.face == _wGrey100 && bo.icon == _wGrey600 && bo.tfg == _wText1 && bo.dfg == _wText2 && bo.cr, '${bo.face}/${bo.icon}/${bo.tfg}/${bo.dfg}/${bo.cr}');
            }
            if (so.n == 1) chk('strict 급여 명세서 버튼 = brand(행동)', so.c == _wBrand, so.c);
          }
          final shotId = '1${c.id.toLowerCase()}';
          _out('D545 $tok shot $shotId ovf=${seen.overflows.length}');
          await vqCapture(t, key, '${tok}_$shotId', conditions: {
            'viewport': '${v.w.toInt()}x${v.h.toInt()}', 'textScaler': v.s, 'run': vqRun, 'manifest': _manifest, 'mode': mode,
            'fixture': c.id, 'state': 'card-${c.id.toLowerCase()}',
          });
          shots++;
        } catch (e, st) {
          failure = e;
          failureSt = st;
        } finally {
          FlutterError.onError = prevOnError;
        }

        // 성공 · 실패 공통 정리 — 화면을 내리고(UserProvider dispose) 남은 timer 가 끝날 시간을 준다.
        var cleanupErr = '';
        try {
          await t.pumpWidget(const SizedBox.shrink());
          await t.pump(const Duration(milliseconds: 500));
        } catch (e, st) {
          cleanupErr = e.toString();
          if (failure == null) {
            failure = e;
            failureSt = st;
          }
        }

        // 집계 — 예상 밖 플랫폼 채널(서버 · 저장소 · 인증 포함) · HTTP.
        final nUnexp = wire.unexpected.length;
        final nHttp = net.tries.length;
        _out('D545 $tok att wire unexpected=$nUnexp http=$nHttp');

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
        _out('R545 $tok raw ovf64=${_enc(ovfRaw)} fw64=${_enc(fwRaw)} un64=${_enc(wire.unexpected.join(' | '))} '
            'cleanup64=${_enc(cleanupErr)} fail64=${_enc(failure?.toString() ?? '')}');
        _out('D545 $tok att fw n=$nFw');
        _out('D545 $tok done state=${c.id} mode=$mode captures=$shots overflows=$nOvf exc=${exc != null}');

        final f0 = failure;
        if (f0 != null) {
          _halt ??= '$tok ${f0.toString().split('\n').first}';
          Error.throwWithStackTrace(f0, failureSt ?? StackTrace.current);
        }
        chk('예상 밖 채널 0 · HTTP 0', nUnexp == 0 && nHttp == 0, 'unexpected $nUnexp http $nHttp');
        if (!_before && v.id == 'W') chk('strict W 화면 전체 넘침 0', nOvf == 0, ovfRaw);
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
