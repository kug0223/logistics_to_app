// ignore_for_file: depend_on_referenced_packages
// [DU579 · 장부 BL-06(+BL-20 일부) · 색 · 배치] 관리자 통계(DU-S009) — 판정141 PP-ADMINSTATS-COLOR R1–R4 이행 + F141-ADMINSTATS-B-LAYOUT 넘침 3곳.
//   R1 정정 전 띠 세 소비처(연간 · 월 상세 · 근태 내역) = 흰 면 + grey200 선 + warningDark 글 · R2 업무별 금액 글 textPrimary ·
//   R3 신뢰점수 인원수 글 textPrimary · R4 전년 대비 금액 · 건수 칩 중립(grey200 면 · textSecondary 화살표/글) — 비율(출근율 · 노쇼율) 칩은 의미색 그대로.
//   BL-20(일부): 신뢰점수 머리 Wrap(160px) · 데이터 없음 띠(104px) · 조회 실패 띠(127px). 월별 건수 12칸(62px)은 뗐다(README '판단 필요') →
//     B NORMAL 은 그 한 자리(admin_stats_screen 월별 Row 줄) 넘침만 허용한다.
//   before = 지금 A(admin_stats 97de4551 · 월 상세 324bce86 · 내역 8ed98126) 기록 · strict = 후보(cand/ · mkcell 이 SHA 대조).
//   하네스 = du1_s009_adminstats_color_546_test(e1b75087) 대역(가짜 Firebase · _AdminProvider · _FakeStats · 채널/HTTP 관찰 · 글꼴 · 칩 읽기) +
//     stats_to_attendance_link_test SA-8 · SA-11c 흐름(내역 열기 → 근태 화면 대신 시험 대역 true → 다시 읽기 실패 → 뒤로) +
//     측정 블록 = DU562 시험(du1_o002_o003_uxw2_naming_562_test :157–254 · :930–971 — max 판 _fullShown · _textObs · _area · _textLine · _bringBuilt) ·
//     DU575 시험 _fills(A8).
//   누르는 것: STALE '출근율'(미확인 칸) · MSTALE '근태 확인 필요' 칸 · 내역 행(근태 화면 대신 시험 대역 → true · CF 0 · 쓰기 0) · 뒤로 = Navigator.pop(DU560 과 같다).
//   기본 skip — TB before/du579as-tb/DU_BEFORE_OBSERVE=579 · TA after/du579as-ta/없음.
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui show BoxHeightStyle;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';

import 'package:ALfit/models/core/attendance_model.dart';
import 'package:ALfit/models/core/business_member_model.dart';
import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/providers/notification_provider.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/screens/business_admin/admin_month_detail_screen.dart';
import 'package:ALfit/screens/business_admin/admin_stats_screen.dart';
import 'package:ALfit/screens/business_admin/stats_attendance_list_screen.dart';
import 'package:ALfit/services/admin_stats_service.dart';
import 'package:ALfit/services/auth_service.dart';
import 'package:ALfit/theme/app_colors.dart';
import 'package:ALfit/theme/role_theme.dart';
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

/// 인증 대역 — 화면은 인증을 읽지 않는다(UserProvider 생성자가 기본 AuthService 로 FirebaseAuth 를 만들지 않게 할 뿐 · DU546 과 같다).
class _NoAuth extends Fake implements AuthService {}

/// DU546 과 같은 override(BUSINESS_ADMIN · 사업장 2 · 급여 · 근태 권한 허용) — 생성자만 Fake AuthService.
class _AdminProvider extends UserProvider {
  _AdminProvider() : super(authService: _NoAuth());
  @override
  UserModel? get currentUser => UserModel(
        uid: 'admin1',
        username: 'admin1',
        name: '김관리',
        email: 'a@alfit.local',
        role: UserRole.BUSINESS_ADMIN,
        managedBusinessIds: const ['biz1', 'biz2'],
      );
  @override
  bool get isBusinessAdmin => true;
  @override
  bool get isSubAdmin => false;
  @override
  PermissionCheck checkCurrentBusiness(bool Function(MemberPermissions p) check) => PermissionCheck.allowed;
  @override
  PermissionCheck checkForBusiness(String businessId, bool Function(MemberPermissions p) check) => PermissionCheck.allowed;
  @override
  bool can(bool Function(MemberPermissions p) check) => true;
}

const _bizA = '강남 물류센터';

/// 근태 원본 2건(stats_to_attendance_link_test _att 와 같은 꼴 · 2026-10 고정) — 확인 필요 1(u1) · 정상 1(p1).
DateTime _kst(int d) => DateTime.utc(2026, 10, d).subtract(const Duration(hours: 9));

AttendanceModel _att(String id, String uid, int day, String status) => AttendanceModel(
      id: id,
      applicationId: 'app_$id',
      userId: uid,
      businessId: 'biz1',
      businessName: _bizA,
      workDate: _kst(day),
      workType: '분류',
      status: status,
      wageStatus: 'pending',
      createdAt: DateTime.utc(2026, 10, 1),
    );

final _rows = <AttendanceModel>[
  _att('u1', 'unk', 8, AttendanceModel.statusUnconfirmed),
  _att('p1', 'okw', 9, AttendanceModel.statusPresent),
];

const _info = {
  'unk': UserInfo(name: '합성 상태없음', personNo: 'P-204'),
  'okw': UserInfo(name: '합성 정상', personNo: 'P-207'),
};

/// 주입 reader — DU546 _FakeStats(실제 클래스를 상속해 읽기만 대체) + 월 상세 · 내역 읽기(SA 시험 꼴). [annual] null = 연간 조회 실패.
///   흐름 중 바꾸는 값: annual(뒤로 가기 전 근태 조회 실패 응답) · snapFail(내역 다시 읽기 실패) · monthFail(월 상세 다시 읽기 실패).
class _FakeStats extends AdminStatsService {
  _FakeStats(this.annual);
  AnnualStatsData? annual;
  bool snapFail = false;
  bool monthFail = false;
  int annualCalls = 0;
  int optionCalls = 0;
  int monthCalls = 0;
  int snapCalls = 0;

  @override
  Future<List<BusinessOption>> getBusinessOptions(List<String> ids) async {
    optionCalls++;
    return const [BusinessOption(id: 'biz1', name: _bizA)];
  }

  @override
  Future<AnnualStatsData> getAnnualStats({required List<String> businessIds, String? filterBusinessId, required int year}) {
    annualCalls++;
    final a = annual;
    if (a == null) return Future<AnnualStatsData>.error(StateError('du579 stats down'));
    return Future<AnnualStatsData>.value(a);
  }

  @override
  Future<MonthDetailData> getMonthDetail({required List<String> businessIds, String? filterBusinessId, required int year, required int month}) {
    monthCalls++;
    if (monthFail) return Future<MonthDetailData>.error(StateError('du579 month down'));
    return Future<MonthDetailData>.value(AdminStatsService.buildMonthDetail(year: 2026, month: 10, attendance: _rows, infoMap: _info));
  }

  @override
  Future<StatsAttendanceSnapshot?> getAttendanceSnapshot({required List<String> businessIds, String? filterBusinessId, required int year, int? month}) async {
    snapCalls++;
    if (snapFail) return null;
    return StatsAttendanceSnapshot(records: _rows, userInfo: _info);
  }
}

/// 원래 경로로 보내는 Flutter 기반 채널과 이유(DU546 과 같은 표).
const _frameworkAllow = <String, String>{
  'flutter/assets': 'AssetBundle(아이콘 글꼴 · 이미지 매니페스트) 읽기',
  'flutter/platform': 'MaterialApp Title · SystemChrome(AppBar 상태바 스타일) · SystemSound/Haptic',
  'flutter/navigation': '루트 Navigator 경로 보고',
  'flutter/mousecursor': 'MouseRegion 커서 갱신(시험 포인터)',
  'flutter/restoration': 'RootRestorationScope 상태 복원 조회',
  'flutter/keyboard': 'HardwareKeyboard 상태 동기화',
  'flutter/accessibility': '의미 트리/알림 전달',
};

const _cfChannel = 'dev.flutter.pigeon.cloud_functions_platform_interface.CloudFunctionsHostApi.call';
const _fsBase = 'dev.flutter.pigeon.cloud_firestore_platform_interface.FirebaseFirestoreHostApi';

/// 모든 플랫폼 메시지 관찰 — 기반 채널은 원래 경로, CF · Firestore · 그 밖은 이름을 기록하고 응답 null(이 화면들은 주입 reader 만 읽는다 — 0 이어야 한다).
class _Wire {
  final cf = <String>[];
  final fs = <String>[];
  final unexpected = <String>[];

  Future<ByteData?>? route(TestDefaultBinaryMessenger m, String channel, MessageHandler? handler, ByteData? message) {
    if (_frameworkAllow.containsKey(channel)) {
      return handler != null ? handler(message) : m.delegate.send(channel, message);
    }
    if (channel == _cfChannel) {
      cf.add(channel);
    } else if (channel.startsWith('$_fsBase.')) {
      fs.add(channel.substring(_fsBase.length + 1));
    } else {
      unexpected.add(channel);
    }
    return null;
  }
}

/// 외부 HTTP 차단(DU546) — 클라이언트 객체 생성은 허용하고 센다(hcl), 실제 요청(모든 HttpClient 멤버 호출)은 [tries] 에 기록하고 실패시킨다.
class _NoHttp extends HttpOverrides {
  final tries = <String>[];
  var clients = 0;

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    clients++;
    return _BlockedHttpClient(tries);
  }
}

/// 요청을 하나도 보내지 않는 HttpClient — 어떤 멤버든 부르면 기록하고 SocketException.
class _BlockedHttpClient implements HttpClient {
  _BlockedHttpClient(this.tries);
  final List<String> tries;

  @override
  dynamic noSuchMethod(Invocation invocation) {
    tries.add('HttpClient ${invocation.memberName}');
    throw const SocketException('DU579 관측 — 외부 HTTP 차단');
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

// ── DU562 측정 블록(:157–254 · :930–971 바이트 그대로) ──

/// [a] 가 [b] **안**에 있는가(0.5px 허용).
bool _inside(Rect a, Rect b) => a.left >= b.left - 0.5 && a.top >= b.top - 0.5 && a.right <= b.right + 0.5 && a.bottom <= b.bottom + 0.5;

final String _wj = String.fromCharCode(0x2060);
final String _zw = String.fromCharCode(0x200B);

bool _gap(String ch) => ch == ' ' || ch == '\n' || ch == '\t' || ch == _zw;

/// 그려진 글(표시 제어 문자 포함) 기준 — 낱말(공백 · 개행 · ZWSP 사이) 안에서 줄이 바뀐 횟수. NBSP · WORD JOINER 로 묶은 덩어리는 한 낱말이다.
int _midBreaks(RenderParagraph rp) {
  final s = rp.text.toPlainText(includeSemanticsLabels: false);
  var n = 0;
  double? lastTop;
  var lastIdx = -1;
  for (var i = 0; i < s.length; i++) {
    final ch = s[i];
    if (ch == '\n') {
      lastTop = null;
      lastIdx = i;
      continue;
    }
    if (ch == _wj || ch == _zw) continue;
    final bx = rp.getBoxesForSelection(TextSelection(baseOffset: i, extentOffset: i + 1));
    if (bx.isEmpty) continue;
    final top = bx.first.top;
    final half = (bx.first.bottom - bx.first.top) / 2;
    final wrapped = lastTop != null && top > lastTop + half;
    if (wrapped) {
      var gap = _gap(ch) || (lastIdx >= 0 && _gap(s[lastIdx]));
      for (var k = lastIdx + 1; k < i; k++) {
        if (_gap(s[k])) gap = true;
      }
      if (!gap) n++;
    }
    if (lastTop == null || wrapped) lastTop = top;
    lastIdx = i;
  }
  return n;
}

/// 글 전문이 그려졌는가 — 마지막 글자까지 자리(box)가 문단 크기 안에 있다(말줄임으로 잘린 글자는 자리가 없다).
bool _fullShown(RenderParagraph rp, Size size) {
  final s = rp.text.toPlainText(includeSemanticsLabels: false);
  for (var i = s.length - 1; i >= 0; i--) {
    final ch = s[i];
    if (ch == _wj || _gap(ch)) continue;
    // [DU560 repair 3 proposed / decision168] Vertical max selection box; horizontal tight right; tolerance unchanged.
    // This measures selection-box placement, not ink bounds or ancestor clipping.
    final sel = TextSelection(baseOffset: i, extentOffset: i + 1);
    final tight = rp.getBoxesForSelection(sel);
    final mx = rp.getBoxesForSelection(sel, boxHeightStyle: ui.BoxHeightStyle.max);
    return tight.isNotEmpty && mx.isNotEmpty && mx.first.bottom <= size.height + 0.5 && tight.first.right <= size.width + 0.5;
  }
  return false;
}

typedef _TextObs = ({bool shown, bool name, bool full, bool ell0, int brk, Size size});

/// Text 하나의 관측값(잰 즉시 값으로 굳힌다) — 그려진 글(표시 제어 문자를 뺀 것) · 읽는 이름이 각각 [want] 원문과 같은가 · 전문 · 말줄임 설정 · 낱말 안 끊김 수.
_TextObs _textObs(WidgetTester t, Finder textF, String want) {
  final rp = t.renderObject<RenderParagraph>(find.descendant(of: textF, matching: find.byType(RichText), skipOffstage: true).first);
  final size = rp.size;
  final shown = TextLayout.plain(rp.text.toPlainText(includeSemanticsLabels: false));
  final name = rp.text.toPlainText();
  return (shown: shown == want, name: name == want, full: _fullShown(rp, size), ell0: rp.overflow != TextOverflow.ellipsis, brk: _midBreaks(rp), size: size);
}

/// [f] 가 실제로 보일 수 있는 칸 — 화면 ∩ 조상 스크롤 칸 전부.
Rect _area(Finder f, Rect screen) {
  var a = screen;
  for (final e in find.ancestor(of: f, matching: find.byType(Scrollable)).evaluate()) {
    final ro = e.renderObject;
    if (ro is RenderBox && ro.hasSize) a = a.intersect(ro.localToGlobal(Offset.zero) & ro.size);
  }
  return a;
}

/// 그려진 문단의 줄 수 — 글자 자리(box)의 서로 다른 top 개수.
int _lineCount(RenderParagraph rp) {
  final n = rp.text.toPlainText(includeSemanticsLabels: false).length;
  final tops = <int>{};
  for (final b in rp.getBoxesForSelection(TextSelection(baseOffset: 0, extentOffset: n))) {
    tops.add(b.top.round());
  }
  return tops.length;
}

Finder _txt(Finder scope, String want, {bool onstage = true}) => find.descendant(
    of: scope,
    matching: find.byWidgetPredicate((w) => w is Text && TextLayout.plain(w.data ?? w.textSpan?.toPlainText() ?? '') == want),
    skipOffstage: onstage);

/// [DU581 r3 _bringBuilt 와 같은 대비 · 판정167 교훈] [want] 글이 [host] 안에 아직 안 지어졌을 때만 그 host 의 세로 Scrollable 을 끌어 짓는다
///   (누르기 아님 · 찾는 식 = _txt 와 같은 정규화 · 단언 없음 — 개수 판정은 뒤 _textLine/_btnReach 출력과 cell 선언). 지어져 있으면 아무것도 하지 않는다.
Future<void> _bringBuilt(WidgetTester t, Finder host, String? want) async {
  final tf = find.descendant(
      of: host, matching: find.byWidgetPredicate((w) => w is Text && TextLayout.plain(w.data ?? w.textSpan?.toPlainText() ?? '') == want), skipOffstage: false);
  if (tf.evaluate().isNotEmpty) return;
  final sc = find.descendant(
      of: host, matching: find.byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.down), skipOffstage: false);
  await t.scrollUntilVisible(tf, 120, scrollable: sc.first, maxScrolls: 40);
  await t.pump(const Duration(milliseconds: 50));
}

/// 읽는 이름 — Text.semanticsLabel(있으면) · 없으면 span 의 읽는 이름을 포함한 평문 · 그다음 data.
String _semOf(Text w) => w.semanticsLabel ?? w.textSpan?.toPlainText() ?? w.data ?? '';

typedef _TO = ({int n, bool shown, bool sem, bool full, bool ell0, int brk, int lines, bool vis});

/// 글 하나 — [tf] 를 ensureVisible 로 화면 안에 넣고 **같은 [tf]** 를 잰다(점검표 A1 · 판정169a §5).
///   shown · full · ell0 · brk = DU560 r3 _textObs(max 판 _fullShown 그대로) · lines = _lineCount · vis = 화면 ∩ 조상 스크롤 칸 안 · n ≠ 1 이면 재지 않는다.
Future<_TO> _textLine(WidgetTester t, Finder tf, String want, Rect screen) async {
  final n = tf.evaluate().length;
  _TextObs o = (shown: false, name: false, full: false, ell0: false, brk: 0, size: Size.zero);
  var sem = false;
  var lines = 0;
  var vis = false;
  if (n == 1) {
    await t.ensureVisible(tf);
    for (var m = 0; m < 4; m++) {
      await t.pump(const Duration(milliseconds: 50));
    }
    o = _textObs(t, tf, want);
    sem = _semOf(t.widget<Text>(tf)) == want;
    lines = _lineCount(t.renderObject<RenderParagraph>(find.descendant(of: tf, matching: find.byType(RichText), skipOffstage: true).first));
    vis = _inside(t.getRect(tf), _area(tf, screen));
  }
  return (n: n, shown: o.shown, sem: sem, full: o.full, ell0: o.ell0, brk: o.brk, lines: lines, vis: vis);
}

// ── DU546 칩 · 띠 읽기(바이트 그대로) ──

/// 이 파일의 private 위젯(_StatCell · _DeltaBadge)을 이름으로 — 시험에서 타입을 직접 쓸 수 없다.
bool _isA(Widget w, String typeName) => w.runtimeType.toString() == typeName;

// [주의] flutter_test 3.35 의 descendant/ancestor 는 안쪽 matching finder 를 그 자신의 skipOffstage 로 따로 평가해 교집합을 낸다
//   (finders.dart _DescendantFinderMixin.findInCandidates · _AncestorFinderMixin.findInCandidates) — 바깥만 false 면 캐시 칸 위젯이 빠진다.
//   그래서 안쪽 finder 도 모두 skipOffstage: false 다.
Finder _kind(Finder root, String typeName) => find.descendant(
    of: root, matching: find.byWidgetPredicate((w) => _isA(w, typeName), skipOffstage: false), skipOffstage: false);

/// Container 하나의 면 색(BoxDecoration.color · 없으면 Container.color · 그것도 없으면 투명).
Color _faceOf(WidgetTester t, Finder box) {
  final c = t.widget<Container>(box);
  final d = c.decoration;
  return d is BoxDecoration ? (d.color ?? Colors.transparent) : (c.color ?? Colors.transparent);
}

/// Container 하나의 테두리 색(Border 윗변) — 없으면 '-'.
String _edgeOf(WidgetTester t, Finder box) {
  final d = t.widget<Container>(box).decoration;
  final b = d is BoxDecoration ? d.border : null;
  return b is Border ? _hex(b.top.color) : '-';
}

/// [box] 안 Icon 이 정확히 하나면 그 색, 아니면 '-'.
String _iconIn(WidgetTester t, Finder box) {
  final f = find.descendant(of: box, matching: find.byType(Icon, skipOffstage: false), skipOffstage: false);
  if (f.evaluate().length != 1) return '-';
  return _h(t.widget<Icon>(f).color);
}

/// [box] 안의 Text 중 전년 대비 칩(_DeltaBadge) 안이 아닌 것 — 나무 순서.
List<Text> _ownTexts(Finder box) {
  final under = find
      .descendant(of: _kind(box, '_DeltaBadge'), matching: find.byType(Text, skipOffstage: false), skipOffstage: false)
      .evaluate()
      .toSet();
  return [
    for (final e in find.descendant(of: box, matching: find.byType(Text, skipOffstage: false), skipOffstage: false).evaluate())
      if (!under.contains(e)) e.widget as Text,
  ];
}

typedef _DeltaObs = ({bool up, String face, String fg, String icon, double cr});

/// [box] 안 전년 대비 칩 — 오름/내림(화살표) · 면 · 글 · 화살표 색 · 대비(면을 흰 카드에 얹어서).
List<_DeltaObs> _deltasIn(WidgetTester t, Finder box) {
  final df = _kind(box, '_DeltaBadge');
  final n = df.evaluate().length;
  final res = <_DeltaObs>[];
  for (var i = 0; i < n; i++) {
    final d = df.at(i);
    final ic = find.descendant(of: d, matching: find.byType(Icon, skipOffstage: false), skipOffstage: false);
    final tx = find.descendant(of: d, matching: find.byType(Text, skipOffstage: false), skipOffstage: false);
    if (ic.evaluate().length != 1 || tx.evaluate().length != 1) continue;
    final faceC = _faceOf(t, find.descendant(of: d, matching: find.byType(Container, skipOffstage: false), skipOffstage: false).first);
    final icon = t.widget<Icon>(ic);
    final fgC = t.widget<Text>(tx).style?.color ?? Colors.black;
    res.add((up: icon.icon == Icons.arrow_upward, face: _hex(faceC), fg: _hex(fgC), icon: _h(icon.color), cr: _contrast(fgC, Color.alphaBlend(faceC, Colors.white))));
  }
  return res;
}

// ── DU575 _fills(점검표 A8 · 바이트 그대로 — _hex · _enc 는 이 파일의 같은 이름) ──

/// [DU575 · 점검표 A8] 화면에 그려진(onstage) ButtonStyleButton 전부의 채움 — 단추 자신의 Material 색(투명 · 없음 = none) · 글 = 첫 RichText(Icon 글리프 제외).
///   기록만(브랜드 밖 채움은 보고서 색 조화 표 '후보'). 카드 행 단추(_inviteActionButton = GestureDetector + Container)는 여기 들지 않는다 — README A8 표.
typedef _FillObs = ({int n, int brand, int err, int none, int other, String list});

_FillObs _fills(WidgetTester t) {
  final rows = <String>[];
  var b = 0, er = 0, no = 0, ot = 0;
  for (final e in find.byWidgetPredicate((w) => w is ButtonStyleButton).evaluate()) {
    final bf = find.byElementPredicate((x) => identical(x, e));
    final mats = find.descendant(of: bf, matching: find.byType(Material), skipOffstage: false).evaluate().toList();
    final Color? fc = mats.isEmpty ? null : (mats.first.widget as Material).color;
    final texts = find
        .descendant(of: bf, matching: find.byType(RichText), skipOffstage: false)
        .evaluate()
        .where((r) => find.ancestor(of: find.byElementPredicate((x) => identical(x, r), skipOffstage: false), matching: find.byType(Icon)).evaluate().isEmpty)
        .toList();
    final lab = texts.isEmpty ? '-' : TextLayout.plain((texts.first.widget as RichText).text.toPlainText(includeSemanticsLabels: false));
    if (fc == null || fc.a == 0) {
      no++;
      rows.add('$lab:none');
    } else {
      if (fc.toARGB32() == AppColors.brand.toARGB32()) {
        b++;
      } else if (fc.toARGB32() == AppColors.errorDark.toARGB32()) {
        er++;
      } else {
        ot++;
      }
      rows.add('$lab:${_hex(fc)}');
    }
  }
  return (n: rows.length, brand: b, err: er, none: no, other: ot, list: _enc(rows.join('|')));
}

// ── DU579 새 부분: 칩 짝 이름 · 계열 행 · 띠 ──

/// 칩 짝 이름 — neutral(StatusBadge.neutral 면 grey200 + textSecondary) · success · error(StatusBadge 짝) · 그 밖 other.
String _pairOf(_DeltaObs? d) {
  if (d == null) return '-';
  for (final (name, face, ink) in [
    ('neutral', AppColors.grey200, AppColors.textSecondary),
    ('success', AppColors.successBg, AppColors.successDark),
    ('error', AppColors.errorBg, AppColors.errorDark),
  ]) {
    if (d.face == _hex(face) && d.fg == _hex(ink) && d.icon == _hex(ink)) return name;
  }
  return 'other';
}

typedef _SerObs = ({String fg, String bar, bool full, int brk, int lbrk, double cr});

/// 계열 한 줄(업무별 인건비 · 신뢰점수 등급) — 이름 글 [name] 을 짓고(_bringBuilt) 그 줄(가장 가까운 Column)의 [pick] 글 하나를
///   ensureVisible 로 넣은 뒤 **같은 글**의 색 · 전문 · 낱말 안 끊김 · 대비(흰 카드)와 막대 색 · 이름 글 끊김을 잰다(점검표 A1 · A4).
Future<_SerObs?> _serOf(WidgetTester t, Finder root, String name, bool Function(String s) pick) async {
  await _bringBuilt(t, root, name);
  final nf = _txt(root, name, onstage: false);
  if (nf.evaluate().length != 1) return null;
  final col = find.ancestor(of: nf, matching: find.byType(Column, skipOffstage: false)).first;
  final tfs = find.descendant(
      of: col, matching: find.byWidgetPredicate((w) => w is Text && pick(TextLayout.plain(w.data ?? '')), skipOffstage: false), skipOffstage: false);
  final bars = find.descendant(of: col, matching: find.byType(LinearProgressIndicator, skipOffstage: false), skipOffstage: false);
  if (tfs.evaluate().length != 1 || bars.evaluate().length != 1) return null;
  await t.ensureVisible(tfs);
  for (var m = 0; m < 4; m++) {
    await t.pump(const Duration(milliseconds: 50));
  }
  final w = t.widget<Text>(tfs);
  final fgC = w.style?.color ?? Colors.black;
  final o = _textObs(t, tfs, TextLayout.plain(w.data ?? ''));
  final lo = _textObs(t, nf, name);
  return (fg: _hex(fgC), bar: _h(t.widget<LinearProgressIndicator>(bars).valueColor?.value), full: o.full, brk: o.brk, lbrk: lo.brk, cr: _contrast(fgC, Colors.white));
}

typedef _BandObs = ({int n, String face, String bd, String icon, String fg, String cr, bool ok45, bool full, int brk, int lines, bool vis, bool sem, bool inb});

/// 띠 하나(정정 전 · 조회 실패 · 데이터 없음) — 글 [want] 를 짓고 _textLine(ensureVisible = 잰 대상)으로 잰 뒤, 그 글의 가장 가까운 Container(띠)의
///   면 · 선 · 아이콘 · 글 색 · 대비(면을 화면 바탕에 얹어서) · 글이 띠 안 · 띠가 화면 폭 안(inb)을 읽는다.
Future<_BandObs> _band(WidgetTester t, Finder scope, String want, Rect screen) async {
  await _bringBuilt(t, scope, want);
  final tf = _txt(scope, want, onstage: false);
  final o = await _textLine(t, tf, want, screen);
  if (o.n != 1) {
    return (n: o.n, face: '-', bd: '-', icon: '-', fg: '-', cr: '0.00', ok45: false, full: false, brk: 0, lines: 1, vis: false, sem: false, inb: false);
  }
  final box = find.ancestor(of: tf, matching: find.byType(Container)).first;
  final faceC = _faceOf(t, box);
  final fgC = t.widget<Text>(tf).style?.color ?? Colors.black;
  final cr = _contrast(fgC, Color.alphaBlend(faceC, AppColors.background));
  final br = t.getRect(box);
  final inb = _inside(t.getRect(tf), br) && br.left >= screen.left - 0.5 && br.right <= screen.right + 0.5;
  return (
    n: 1,
    face: _hex(faceC),
    bd: _edgeOf(t, box),
    icon: _iconIn(t, box),
    fg: _hex(fgC),
    cr: cr.toStringAsFixed(2),
    ok45: cr >= 4.5,
    full: o.full,
    brk: o.brk,
    lines: o.lines,
    vis: o.vis,
    sem: o.sem,
    inb: inb,
  );
}

// ── 고정값 — DU546 _dataOf 틀(현행 schema · 단위 원/건/명) ──

final int _y = DateTime.now().year;
final int _m = DateTime.now().month;

/// 12개월 막대(이달 = 실행 달 · 이달/기타 강조). [withWage] 거짓이면 0 원(차트 '데이터 없음').
List<MonthlyTrend> _trends(bool withWage) => [
      for (var i = 1; i <= 12; i++)
        MonthlyTrend(year: _y, month: i, workCount: withWage ? 80 + i : 0, totalWage: withWage ? 8000000 + i * 250000 : 0, workerCount: withWage ? 10 + i : 0),
    ];

/// 업무 3(금액 서로 다름 · 내림차순 = 홀서빙 → 주방 보조 → 배송 분류) · 신뢰점수 5명(등급 5개 하나씩).
const _wtNames = ['홀서빙', '주방 보조', '배송 분류'];
const _grades = ['최우수', '우수', '보통', '주의', '경고'];
const _trTitle = '근로자 신뢰점수 분포';
const _trAvg = '평균 59점 · 5명';
const _staleAnnual = '최신 집계를 불러오지 못했어요. 아래 숫자는 정정 전 기준이에요.';
const _staleList = '최신 내역을 불러오지 못했어요. 아래 목록은 정정 전 기준이에요.';

AnnualStatsData? _dataOf(String id, {bool unavailable = false}) {
  switch (id) {
    case 'NORMAL': // DU546 과 같다 — 전년 대비 4(총 인건비 · 급여 확정 근무 오름 · 출근율 내림 · 노쇼율 오름=줄어듦) · 지각/결근 2명 · 업무 3 · 등급 5
      return AnnualStatsData(
        year: _y, totalWage: 128400000, totalWorkCount: 1472, totalWorkerCount: 63, prevYearTotalWage: 98000000, prevYearTotalWorkCount: 1200,
        attendanceRecordCount: 1500, attendanceRate: 94.0, prevYearAttendanceRate: 95.0, rehireRate: 72.5, avgRating: 4.6,
        noShowCount: 18, noShowRate: 1.2, prevYearNoShowRate: 2.0,
        wageByWorkType: const {'홀서빙': 52000000, '주방 보조': 41000000, '배송 분류': 3500000},
        monthlyTrends: _trends(true),
        exceptions: const [
          WorkerException(userId: 'w1', userName: '김지각', businessName: _bizA, lateCount: 2, absentCount: 1),
          WorkerException(userId: 'w2', userName: '이늦음', businessName: _bizA, lateCount: 3, absentCount: 0),
        ],
        exceptionMonth: _m,
        workerTrustScores: const {'w1': 95, 'w2': 80, 'w3': 60, 'w4': 40, 'w5': 20},
        reviewStatsState: ReviewStatsState.available,
      );
    case 'ZERO': // DU546 과 같다 — 정상 응답 · 그해 근태 0건 · 리뷰 없음
      return AnnualStatsData(
        year: _y, totalWage: 0, totalWorkCount: 0, totalWorkerCount: 0, prevYearTotalWage: 0, prevYearTotalWorkCount: 0,
        attendanceRecordCount: 0, attendanceRate: 0, prevYearAttendanceRate: 0, rehireRate: 0, avgRating: 0,
        noShowCount: 0, noShowRate: 0, prevYearNoShowRate: 0, wageByWorkType: const {}, monthlyTrends: _trends(false),
        exceptions: const [], exceptionMonth: _m,
      );
    case 'ATTFAIL': // DU546 과 같다 — 근태 조회 실패(부분 · limitReached) — 확인 불가 · 조회 실패 띠 · 리뷰도 실패
      return AnnualStatsData(
        year: _y, totalWage: 0, totalWorkCount: 0, totalWorkerCount: 0, prevYearTotalWage: 0, prevYearTotalWorkCount: 0,
        attendanceRate: 0, prevYearAttendanceRate: 0, rehireRate: 0, avgRating: 0, noShowCount: 0, noShowRate: 0, prevYearNoShowRate: 0,
        wageByWorkType: const {}, monthlyTrends: _trends(false), exceptions: const [], exceptionMonth: _m,
        reviewStatsState: ReviewStatsState.unavailable,
        attendanceStatsState: AttendanceStatsState.unavailable, prevAttendanceStatsState: AttendanceStatsState.unavailable,
      );
    case 'STALE': // SA 시험 꼴 — 확인 필요 1(미확인 칸 → 내역) · 월 막대 1칸 · 전년 0(칩 0). [unavailable] = 정정 뒤 다시 읽기가 근태를 못 읽은 응답
      return AnnualStatsData(
        year: _y, totalWage: 80000, totalWorkCount: 1, totalWorkerCount: 2, prevYearTotalWage: 0, prevYearTotalWorkCount: 0,
        attendanceRecordCount: 2, unconfirmedAttendanceCount: 1, attendanceRate: 50, prevYearAttendanceRate: 0, rehireRate: 0, avgRating: 0,
        noShowCount: 0, noShowRate: 0, prevYearNoShowRate: 0, wageByWorkType: const {},
        monthlyTrends: [MonthlyTrend(year: _y, month: _m, workCount: 2, totalWage: 80000, workerCount: 2)],
        exceptions: const [], exceptionMonth: _m,
        attendanceStatsState: unavailable ? AttendanceStatsState.unavailable : AttendanceStatsState.available,
      );
    default: // MSTALE — 연간 화면을 그리지 않는다(월 상세가 첫 화면)
      return null;
  }
}

typedef _V = ({String id, double w, double h, double s});
const _views = <_V>[(id: 'W', w: 390.0, h: 844.0, s: 1.0), (id: 'B', w: 320.0, h: 640.0, s: 2.0), (id: 'N', w: 320.0, h: 640.0, s: 1.0)];
typedef _C = ({String id, int shots});
const _cases = <_C>[(id: 'NORMAL', shots: 3), (id: 'ZERO', shots: 1), (id: 'ATTFAIL', shots: 1), (id: 'STALE', shots: 2), (id: 'MSTALE', shots: 1)];

final bool _before = Platform.environment['DU_BEFORE_OBSERVE'] == '579';
final Map<String, String> _env = Platform.environment;
final bool _optIn =
    (_env['DU1_VQ_PHASE'] == 'before' && _env['DU1_VQ_RUN'] == 'du579as-tb' && _env['DU_BEFORE_OBSERVE'] == '579') ||
        (_env['DU1_VQ_PHASE'] == 'after' && _env['DU1_VQ_RUN'] == 'du579as-ta' && _env['DU_BEFORE_OBSERVE'] == null);

/// 월별 건수 12칸 Row 가 만들어진 줄(넘침 위치) — base 1031(DU546 TA B :117 원문) · 후보 1043(prep/mk_cand.py 가 계산 · 단언). 이 셀은 이 Row 를 바꾸지 않는다.
final int _monLine = _before ? 1031 : 1043;

/// 첫 실패 뒤 사례는 본문에 들어가지 않는다(진입 0 · 캡처 0).
String? _halt;
final String _manifest = Platform.environment['DUL_MANIFEST'] ?? '(unset)';
const _envKeys = ['DU_BEFORE_OBSERVE', 'DU1_VQ_PHASE', 'DU1_VQ_OUT', 'DU1_VQ_RUN', 'DU1_VQ_DATE', 'DU397_DIAG', 'DU397_MANIFEST', 'DU400_MANIFEST',
  'DU401_MANIFEST', 'DU398_MANIFEST', 'DU406_MANIFEST', 'DU407_MANIFEST', 'DU296_PHASE', 'DUL_MANIFEST'];
final String _envLine = [for (final k in _envKeys) '$k:${Platform.environment[k] ?? '(unset)'}'].join(',');

final String _wSurface = _hex(AppColors.surface);
final String _wG200 = _hex(AppColors.grey200);
final String _wT1 = _hex(AppColors.textPrimary);
final String _wWarnD = _hex(AppColors.warningDark);

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
      FirebasePlatform.instance = _FakeCore();
      await Firebase.initializeApp();
      await _loadFonts();
    } finally {
      m.allMessagesHandler = prevAll;
      HttpOverrides.global = prevHttp;
    }
    final nUnexp = wire.unexpected.length + wire.cf.length + wire.fs.length;
    final nHttp = net.tries.length;
    _out('R579 setup init unexpected=$nUnexp http=$nHttp un64=${_enc([...wire.unexpected, ...wire.cf, ...wire.fs].join('|'))}');
    final initOk = nUnexp == 0 && nHttp == 0;
    if (!initOk) _halt = 'setUpAll 초기화 안전 대역';
    expect(initOk, isTrue, reason: 'setUpAll 초기화 중 예상 밖 채널 0 · HTTP 0 — [${wire.unexpected.join(' | ')}]');
  });

  for (final v in _views) {
    for (final c in _cases) {
      testWidgets('S579AS-${v.id}-${c.id} 관리자 통계 색 R1–R4 · 넘침 F141', (t) async {
        final tok = 'S579AS-${v.id}-${c.id}';
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
        _out('D579 $tok begin mode=$mode phase=${Platform.environment['DU1_VQ_PHASE'] ?? '(unset)'} env=$_envLine manifest=$_manifest');
        final seen = _Seen();
        void need(String k, bool ok, [String why = '']) => expect(ok, isTrue, reason: '$tok $k $why');
        final checks = <(String, bool, String)>[];
        void chk(String k, bool ok, [String why = '']) => checks.add((k, ok, why));

        final svc = _FakeStats(_dataOf(c.id));
        final screen = Rect.fromLTWH(0, 0, v.w, v.h);
        Object? failure;
        StackTrace? failureSt;
        var shots = 0;
        try {
          FlutterError.onError = seen.add;
          final key = GlobalKey();
          final Widget home = c.id == 'MSTALE'
              ? AdminMonthDetailScreen(
                  businessIds: const ['biz1'],
                  filterBusinessId: null,
                  year: 2026,
                  month: 10,
                  businesses: const [BusinessOption(id: 'biz1', name: _bizA)],
                  service: svc,
                  debugOpenAttendance: (r) async => true,
                )
              : AdminStatsScreen(businessIds: const ['biz1', 'biz2'], service: svc, debugOpenAttendance: (r) async => true);
          await t.pumpWidget(RepaintBoundary(
            key: key,
            child: MultiProvider(
              providers: [
                ChangeNotifierProvider<UserProvider>(create: (_) => _AdminProvider()),
                ChangeNotifierProvider<NotificationProvider>(create: (_) => NotificationProvider()),
              ],
              child: MaterialApp(
                debugShowCheckedModeBanner: false,
                theme: RoleTheme.businessAdminTheme,
                locale: const Locale('ko', 'KR'),
                supportedLocales: const [Locale('ko', 'KR'), Locale('en', 'US')],
                localizationsDelegates: const [
                  GlobalMaterialLocalizations.delegate,
                  GlobalWidgetsLocalizations.delegate,
                  GlobalCupertinoLocalizations.delegate,
                ],
                builder: (ctx, child) => MediaQuery(data: MediaQuery.of(ctx).copyWith(textScaler: TextScaler.linear(v.s)), child: child!),
                home: home,
              ),
            ),
          ));
          for (var i = 0; i < 20; i++) {
            await t.pump(const Duration(milliseconds: 100));
          }

          Future<void> shot(String id, String state) async {
            _out('D579 $tok shot $id ovf=${seen.overflows.length}');
            await vqCapture(t, key, '${tok}_$id', conditions: {
              'viewport': '${v.w.toInt()}x${v.h.toInt()}', 'textScaler': v.s, 'run': vqRun, 'manifest': _manifest, 'mode': mode,
              'fixture': c.id, 'state': state,
            });
            shots++;
            final f = _fills(t);
            _out('D579 $tok att fills n=${f.n} brand=${f.brand} err=${f.err} none=${f.none} other=${f.other} list=${f.list}');
          }

          Future<void> settle() async {
            for (var i = 0; i < 20; i++) {
              await t.pump(const Duration(milliseconds: 100));
            }
          }

          // 정정 전 띠는 목록 첫 칸이다 — 앞 단계 ensureVisible 로 내려간 목록을 맨 위로 되돌린다(DU546 과 같은 jumpTo · 끌기 0).
          Future<void> toTop(Finder host) async {
            final sf = find.descendant(
                of: host, matching: find.byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.down), skipOffstage: false);
            if (sf.evaluate().isNotEmpty) t.state<ScrollableState>(sf.first).position.jumpTo(0);
            await t.pump(const Duration(milliseconds: 50));
          }

          if (c.id == 'NORMAL') {
            final scr = find.byType(AdminStatsScreen);
            need('연간 화면 1', scr.evaluate().length == 1);
            await shot('1top', 'stats-normal-top');
            // ① R4 전년 대비 칩 4 — 총 인건비(금액) · 급여 확정 근무(건수) · 출근율 · 노쇼율(비율). 위젯 값(위치 무관).
            final hl = _txt(scr, '총 인건비', onstage: false);
            need('총 인건비 1', hl.evaluate().length == 1);
            final dW = _deltasIn(t, find.ancestor(of: hl, matching: find.byType(Column, skipOffstage: false)).first);
            final byLabel = <String, List<_DeltaObs>>{};
            final cf = _kind(scr, '_StatCell');
            final nCell = cf.evaluate().length;
            for (var i = 0; i < nCell; i++) {
              final ts = _ownTexts(cf.at(i));
              if (ts.isNotEmpty) byLabel[TextLayout.plain(ts.first.data ?? '')] = _deltasIn(t, cf.at(i));
            }
            final dC = byLabel['급여 확정 근무'] ?? const <_DeltaObs>[];
            final dR = byLabel['출근율'] ?? const <_DeltaObs>[];
            final dN = byLabel['노쇼율'] ?? const <_DeltaObs>[];
            final w0 = dW.length == 1 ? dW.first : null;
            final c0 = dC.length == 1 ? dC.first : null;
            final r0 = dR.length == 1 ? dR.first : null;
            final n0 = dN.length == 1 ? dN.first : null;
            final pW = _pairOf(w0);
            final pC = _pairOf(c0);
            final pR = _pairOf(r0);
            final pN = _pairOf(n0);
            _out('D579 $tok att dwage n=${dW.length} up=${w0?.up ?? false} pair=$pW face=${w0?.face ?? '-'} fg=${w0?.fg ?? '-'} '
                'cr=${(w0?.cr ?? 0).toStringAsFixed(2)} ok45=${w0 != null && w0.cr >= 4.5}');
            _out('D579 $tok att dcount n=${dC.length} up=${c0?.up ?? false} pair=$pC face=${c0?.face ?? '-'} fg=${c0?.fg ?? '-'} '
                'cr=${(c0?.cr ?? 0).toStringAsFixed(2)} ok45=${c0 != null && c0.cr >= 4.5}');
            _out('D579 $tok att drate n=${dR.length} up=${r0?.up ?? false} pair=$pR face=${r0?.face ?? '-'} fg=${r0?.fg ?? '-'} '
                'cr=${(r0?.cr ?? 0).toStringAsFixed(2)} ok45=${r0 != null && r0.cr >= 4.5}');
            _out('D579 $tok att dns n=${dN.length} up=${n0?.up ?? false} pair=$pN face=${n0?.face ?? '-'} fg=${n0?.fg ?? '-'} '
                'cr=${(n0?.cr ?? 0).toStringAsFixed(2)} ok45=${n0 != null && n0.cr >= 4.5}');
            need('전년 대비 칩 = 총 인건비 1 · 급여 확정 근무 1 · 출근율 1 · 노쇼율 1', dW.length == 1 && dC.length == 1 && dR.length == 1 && dN.length == 1,
                '${dW.length}/${dC.length}/${dR.length}/${dN.length} 칸 $nCell');
            if (!_before) {
              chk('strict R4 금액 · 건수 칩 = 중립 짝(grey200 · textSecondary) · 비율 칩 = 의미색 짝 그대로(출근율 내림 error · 노쇼율 오름 success)',
                  pW == 'neutral' && pC == 'neutral' && pR == 'error' && pN == 'success', '$pW/$pC/$pR/$pN');
            }
            // ② R2 업무별 인건비 — 금액 글 · 막대(계열색 그대로).
            final wt = <_SerObs>[];
            for (final n in _wtNames) {
              final o = await _serOf(t, scr, n, (s) => s != n);
              if (o != null) wt.add(o);
            }
            final wtBars = wt.isEmpty ? '-' : wt.map((o) => o.bar).join('.');
            final wtKeep = wtBars == [AppColors.info, AppColors.success, AppColors.warning].map(_hex).join('.');
            final wtPrim = wt.isNotEmpty && wt.every((o) => o.fg == _wT1);
            final wtFull = wt.isNotEmpty && wt.every((o) => o.full);
            final wtBrk = wt.fold<int>(0, (a, o) => a + o.brk);
            final wtCr = wt.isEmpty ? 0.0 : wt.map((o) => o.cr).reduce((a, b) => a < b ? a : b);
            _out('D579 $tok att wage n=${wt.length} prim=$wtPrim bars=$wtBars barkeep=$wtKeep full=$wtFull brk=$wtBrk '
                'cr=${wtCr.toStringAsFixed(2)} ok45=${wtCr >= 4.5}');
            if (!_before) chk('strict R2 금액 글 textPrimary · 막대 계열 그대로 · 전문 · 끊김 0', wtPrim && wtKeep && wtFull && wtBrk == 0, '$wtBars $wtFull $wtBrk');
            await _bringBuilt(t, scr, '업무별 인건비');
            await t.ensureVisible(_txt(scr, '업무별 인건비', onstage: false));
            await t.pump(const Duration(milliseconds: 50));
            await shot('2wage', 'stats-normal-wage');
            // ③ BL-20 신뢰점수 머리(제목 · 평균) — 전문 · 끊김 · 카드 안.
            await _bringBuilt(t, scr, _trTitle);
            final tt = _txt(scr, _trTitle, onstage: false);
            final tl = await _textLine(t, tt, _trTitle, screen);
            await _bringBuilt(t, scr, _trAvg);
            final at = _txt(scr, _trAvg, onstage: false);
            final al = await _textLine(t, at, _trAvg, screen);
            var hIn = false;
            if (tl.n == 1 && al.n == 1) {
              final card = t.getRect(find.ancestor(of: tt, matching: find.byType(Container)).first);
              hIn = _inside(t.getRect(tt), card) && _inside(t.getRect(at), card);
            }
            _out('D579 $tok att thead n=${tl.n} full=${tl.full} brk=${tl.brk} lines=${tl.lines} vis=${tl.vis} sem=${tl.sem} '
                'an=${al.n} afull=${al.full} abrk=${al.brk} inb=$hIn');
            if (!_before) chk('strict F141 신뢰점수 머리 — 제목 · 평균 전문 · 낱말 안 끊김 0 · 카드 안', tl.full && tl.brk == 0 && al.full && al.brk == 0 && hIn, '${tl.brk}/${al.brk} $hIn');
            // ④ R3 신뢰점수 등급 — 인원수 글 · 막대(등급색 그대로) · 등급 이름 끊김(기록).
            final tr = <_SerObs>[];
            for (final g in _grades) {
              final o = await _serOf(t, scr, g, (s) => s.contains('명 ('));
              if (o != null) tr.add(o);
            }
            final trBars = tr.isEmpty ? '-' : tr.map((o) => o.bar).join('.');
            final trKeep = trBars == [AppColors.success, AppColors.info, AppColors.warning, AppColors.error, AppColors.grey500].map(_hex).join('.');
            final trPrim = tr.isNotEmpty && tr.every((o) => o.fg == _wT1);
            final trFull = tr.isNotEmpty && tr.every((o) => o.full);
            final trBrk = tr.fold<int>(0, (a, o) => a + o.brk);
            final trLbrk = tr.fold<int>(0, (a, o) => a + o.lbrk);
            final trCr = tr.isEmpty ? 0.0 : tr.map((o) => o.cr).reduce((a, b) => a < b ? a : b);
            _out('D579 $tok att trust n=${tr.length} prim=$trPrim bars=$trBars barkeep=$trKeep full=$trFull brk=$trBrk lbrk=$trLbrk '
                'cr=${trCr.toStringAsFixed(2)} ok45=${trCr >= 4.5}');
            if (!_before) chk('strict R3 인원수 글 textPrimary · 등급 막대 그대로 · 전문 · 끊김 0', trPrim && trKeep && trFull && trBrk == 0, '$trBars $trFull $trBrk');
            await t.ensureVisible(tt);
            await t.pump(const Duration(milliseconds: 50));
            await shot('3trust', 'stats-normal-trust');
          }

          if (c.id == 'ZERO' || c.id == 'ATTFAIL') {
            final scr = find.byType(AdminStatsScreen);
            need('연간 화면 1', scr.evaluate().length == 1);
            final zero = c.id == 'ZERO';
            final b = await _band(t, scr, zero ? '$_y년 근태 데이터가 없습니다' : '출근 데이터를 불러올 수 없습니다', screen);
            // 색은 이 셀이 바꾸지 않는다 — DU546 이 정한 값 그대로인지(keep).
            final keep = zero
                ? b.face == _hex(AppColors.grey100) && b.bd == '-' && b.icon == _hex(AppColors.grey600) && b.fg == _hex(AppColors.textSecondary)
                : b.face == _wSurface && b.bd == _wG200 && b.icon == _hex(AppColors.error) && b.fg == _hex(AppColors.errorDark);
            _out('D579 $tok att band n=${b.n} face=${b.face} bd=${b.bd} icon=${b.icon} fg=${b.fg} cr=${b.cr} ok45=${b.ok45} full=${b.full} '
                'brk=${b.brk} lines=${b.lines} vis=${b.vis} sem=${b.sem} inb=${b.inb} keep=$keep');
            need('띠 1', b.n == 1);
            if (!_before) chk('strict F141 띠 — 글 띠 안 · 띠 화면 폭 안 · 전문 · 낱말 안 끊김 0 · 색 그대로', b.inb && b.full && b.brk == 0 && keep, '${b.inb} ${b.brk} $keep');
            await shot(zero ? '1zero' : '1attfail', zero ? 'stats-zero-band' : 'stats-attfail-band');
          }

          if (c.id == 'STALE') {
            final scr = find.byType(AdminStatsScreen);
            need('연간 화면 1', scr.evaluate().length == 1);
            await _bringBuilt(t, scr, '출근율');
            final cell = find.byKey(const ValueKey('annual-unconfirmed-att'), skipOffstage: false);
            need('미확인 칸 1', cell.evaluate().length == 1);
            await t.ensureVisible(cell);
            await t.pump(const Duration(milliseconds: 50));
            await t.tap(cell);
            await settle();
            final lst = find.byType(StatsAttendanceListScreen);
            final navList = lst.evaluate().length;
            need('내역 화면 1', navList == 1);
            svc.snapFail = true;
            final row = find.byKey(const ValueKey('att-row-u1'), skipOffstage: false);
            if (row.evaluate().isEmpty) {
              await t.scrollUntilVisible(row, 120,
                  scrollable: find.descendant(of: lst, matching: find.byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.down), skipOffstage: false).first,
                  maxScrolls: 40);
            }
            need('내역 행 1', row.evaluate().length == 1);
            await t.ensureVisible(row);
            await t.pump(const Duration(milliseconds: 50));
            await t.tap(row);
            await settle();
            await toTop(lst);
            final lb = await _band(t, lst, _staleList, screen);
            _out('D579 $tok att lstale n=${lb.n} face=${lb.face} bd=${lb.bd} icon=${lb.icon} fg=${lb.fg} cr=${lb.cr} ok45=${lb.ok45} full=${lb.full} '
                'brk=${lb.brk} lines=${lb.lines} vis=${lb.vis} sem=${lb.sem} inb=${lb.inb}');
            need('내역 정정 전 띠 1', lb.n == 1);
            await shot('1list', 'list-stale');
            svc.annual = _dataOf('STALE', unavailable: true);
            Navigator.of(t.element(lst)).pop();
            await settle();
            final navBack = find.byType(StatsAttendanceListScreen, skipOffstage: false).evaluate().length;
            await toTop(scr);
            final ab = await _band(t, scr, _staleAnnual, screen);
            _out('D579 $tok att astale n=${ab.n} face=${ab.face} bd=${ab.bd} icon=${ab.icon} fg=${ab.fg} cr=${ab.cr} ok45=${ab.ok45} full=${ab.full} '
                'brk=${ab.brk} lines=${ab.lines} vis=${ab.vis} sem=${ab.sem} inb=${ab.inb}');
            _out('D579 $tok att nav lst=$navList back=$navBack');
            need('연간 정정 전 띠 1 · 내역 닫힘', ab.n == 1 && navBack == 0, 'back $navBack');
            if (!_before) {
              chk('strict R1 내역 · 연간 정정 전 띠 = 흰 면 · grey200 선 · warningDark 글 · 대비 ≥4.5 · 전문 · 띠 안',
                  lb.face == _wSurface && lb.bd == _wG200 && lb.fg == _wWarnD && lb.ok45 && lb.full && lb.inb &&
                      ab.face == _wSurface && ab.bd == _wG200 && ab.fg == _wWarnD && ab.ok45 && ab.full && ab.inb,
                  '${lb.face}/${lb.bd}/${lb.fg}/${lb.cr} ${ab.face}/${ab.bd}/${ab.fg}/${ab.cr}');
            }
            await shot('2annual', 'annual-stale');
          }

          if (c.id == 'MSTALE') {
            final mds = find.byType(AdminMonthDetailScreen);
            need('월 상세 화면 1', mds.evaluate().length == 1);
            await _bringBuilt(t, mds, '근태 현황');
            final stat = find.byKey(const ValueKey('att-stat-unconfirmed'), skipOffstage: false);
            need('근태 확인 필요 칸 1', stat.evaluate().length == 1);
            await t.ensureVisible(stat);
            await t.pump(const Duration(milliseconds: 50));
            await t.tap(stat);
            await settle();
            final lst = find.byType(StatsAttendanceListScreen);
            final navList = lst.evaluate().length;
            need('내역 화면 1', navList == 1);
            final row = find.byKey(const ValueKey('att-row-u1'), skipOffstage: false);
            if (row.evaluate().isEmpty) {
              await t.scrollUntilVisible(row, 120,
                  scrollable: find.descendant(of: lst, matching: find.byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.down), skipOffstage: false).first,
                  maxScrolls: 40);
            }
            need('내역 행 1', row.evaluate().length == 1);
            await t.ensureVisible(row);
            await t.pump(const Duration(milliseconds: 50));
            await t.tap(row);
            await settle();
            svc.monthFail = true;
            Navigator.of(t.element(lst)).pop();
            await settle();
            final navBack = find.byType(StatsAttendanceListScreen, skipOffstage: false).evaluate().length;
            await toTop(mds);
            final mb = await _band(t, mds, _staleAnnual, screen);
            _out('D579 $tok att mstale n=${mb.n} face=${mb.face} bd=${mb.bd} icon=${mb.icon} fg=${mb.fg} cr=${mb.cr} ok45=${mb.ok45} full=${mb.full} '
                'brk=${mb.brk} lines=${mb.lines} vis=${mb.vis} sem=${mb.sem} inb=${mb.inb}');
            _out('D579 $tok att nav lst=$navList back=$navBack');
            need('월 상세 정정 전 띠 1 · 내역 닫힘', mb.n == 1 && navBack == 0, 'back $navBack');
            if (!_before) {
              chk('strict R1 월 상세 정정 전 띠 = 흰 면 · grey200 선 · warningDark 글 · 대비 ≥4.5 · 전문 · 띠 안',
                  mb.face == _wSurface && mb.bd == _wG200 && mb.fg == _wWarnD && mb.ok45 && mb.full && mb.inb, '${mb.face}/${mb.bd}/${mb.fg}/${mb.cr}');
            }
            await shot('1month', 'month-stale');
          }
        } catch (e, st) {
          failure = e;
          failureSt = st;
        } finally {
          FlutterError.onError = prevOnError;
        }

        // 성공 · 실패 공통 정리 — 화면을 내리고(UserProvider · NotificationProvider dispose) 남은 timer 가 끝날 시간을 준다.
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

        // 집계 — 예상 밖 플랫폼 채널(CF · Firestore 포함) · HTTP · 주입 reader 호출 수.
        final nCf = wire.cf.length;
        final nFs = wire.fs.length;
        final nUnexp = wire.unexpected.length;
        final nHttp = net.tries.length;
        final nHcl = net.clients;
        _out('D579 $tok att wire cf=$nCf fs=$nFs unexpected=$nUnexp http=$nHttp hcl=$nHcl ann=${svc.annualCalls} opt=${svc.optionCalls} '
            'mdc=${svc.monthCalls} snp=${svc.snapCalls}');

        messenger.allMessagesHandler = prevAll;
        HttpOverrides.global = prevHttp;
        final exc = t.takeException();
        if (exc != null && failure == null) {
          failure = exc;
          failureSt = StackTrace.current;
        }
        final nOvf = seen.overflows.length;
        final nMon = seen.overflows.where((o) => o.contains('admin_stats_screen.dart:$_monLine:')).length;
        // B NORMAL 은 뗀 월별 건수 Row 한 자리 넘침만 허용(그 밖 0) · 그 밖 보기/상태는 화면 전체 넘침 0.
        final ovfOk = v.id == 'B' && c.id == 'NORMAL' ? nOvf == nMon : nOvf == 0;
        final nFw = seen.other.length;
        final ovfRaw = seen.overflows.take(8).join('\n----\n');
        final fwRaw = seen.other.take(4).map((m) => m.length > 400 ? m.substring(0, 400) : m).join('\n----\n');
        final unText = [...wire.unexpected, ...wire.cf.map((x) => 'cf $x'), ...wire.fs.map((x) => 'fs $x'), ...net.tries].join(' | ');
        _out('R579 $tok raw ovf64=${_enc(ovfRaw)} fw64=${_enc(fwRaw)} un64=${_enc(unText)} cleanup64=${_enc(cleanupErr)} '
            'fail64=${_enc(failure?.toString() ?? '')}');
        _out('D579 $tok att ovf n=$nOvf mon=$nMon ok=$ovfOk');
        _out('D579 $tok att fw n=$nFw');
        _out('D579 $tok done state=${c.id} mode=$mode captures=$shots overflows=$nOvf exc=${exc != null}');

        final f0 = failure;
        if (f0 != null) {
          _halt ??= '$tok ${f0.toString().split('\n').first}';
          Error.throwWithStackTrace(f0, failureSt ?? StackTrace.current);
        }
        chk('예상 밖 채널 · CF · Firestore 0 · HTTP 요청 0', nCf == 0 && nFs == 0 && nUnexp == 0 && nHttp == 0, unText);
        if (!_before) chk('strict 넘침 — B NORMAL 은 월별 건수 Row 만 · 그 밖 0', ovfOk, ovfRaw);
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
