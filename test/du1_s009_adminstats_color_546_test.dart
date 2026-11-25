// ignore_for_file: depend_on_referenced_packages
// [DU546 · 색만] 관리자 통계 화면(AdminStatsScreen · DU-S009/S028 계열) 색 예산 1차 — 통계 숫자 중립(노쇼율 양수만 errorDark · 확인 필요 purple 그대로) ·
//   재고용률 값/별점 amber → 중립 · 전년 대비 칩 · 지각/결근 배지 = StatusBadge 짝 · 근태 조회 실패 띠 = 흰 면/grey200 선 + errorDark 글 · 데이터 없음 띠 글/아이콘.
//   차트 계열색(업무별 인건비 · 신뢰점수 등급) · 막대 · 범례 · 낡은 숫자 띠 · DU329/DU333/DU425 가 정한 곳은 그대로(두 모드 같은 값으로 기록).
//   before = 현재 A(admin_stats_screen 9d627669) 기록 전용 · strict = 후보(97de4551).
//   하네스 = admin_stats_content_render_test.dart 의 대역(가짜 Firebase 코어 · _AdminProvider · _FakeStats extends AdminStatsService ·
//     MultiProvider(UserProvider · NotificationProvider) · businessAdminTheme) + DU545 의 Fake AuthService(UserProvider 가 FirebaseAuth 를 만들지 않게) +
//     DU541 r2 의 플랫폼 메시지 전수 관찰(기반 채널만 원래 경로 · CF/Firestore/그 밖은 기록 후 응답 null) · HTTP 클라이언트 생성 허용/요청 차단.
//   상태 5: NORMAL(정상 집계 · 전년 대비 · 지각/결근 · 업무별 · 신뢰점수 · 12개월 막대 · 이달 강조) · ZERO(0건) · UNCONF(미확인 근태) ·
//     ATTFAIL(근태만 조회 실패) · FAIL(통계 전체 조회 실패 — 머리 연도/사업장 유지 · 통계 칸 0 · 다시 시도).
//   누르는 것 0 · 끌기 0 — 목록은 ScrollPosition.jumpTo 로만 내려 가며 지어진 위젯 값을 읽는다(막대 touchCallback 0 · 다른 화면 이동 0). rect 0.
//   기본 skip — TB before/du546-tb/DU_BEFORE_OBSERVE=546 · TA after/du546-ta/없음.
import 'dart:convert';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';

import 'package:ALfit/models/core/business_member_model.dart';
import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/providers/notification_provider.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/screens/business_admin/admin_stats_screen.dart';
import 'package:ALfit/services/admin_stats_service.dart';
import 'package:ALfit/services/auth_service.dart';
import 'package:ALfit/theme/app_colors.dart';
import 'package:ALfit/theme/role_theme.dart';

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

/// 인증 대역 — 화면은 인증을 읽지 않는다(UserProvider 생성자가 기본 AuthService 로 FirebaseAuth 를 만들지 않게 할 뿐 · DU545 와 같다).
class _NoAuth extends Fake implements AuthService {}

/// admin_stats_content_render_test.dart:59 의 _AdminProvider 와 같은 override(BUSINESS_ADMIN · 사업장 2 · 급여 권한 허용) — 생성자만 Fake AuthService.
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

/// 주입 reader — admin_stats_content_render_test.dart:167 의 _FakeStats 와 같은 방식(실제 클래스를 상속해 읽기만 대체). [annual] null = 연간 조회 실패.
class _FakeStats extends AdminStatsService {
  _FakeStats(this.annual);
  final AnnualStatsData? annual;
  int annualCalls = 0;
  int optionCalls = 0;

  @override
  Future<List<BusinessOption>> getBusinessOptions(List<String> ids) async {
    optionCalls++;
    return const [BusinessOption(id: 'biz1', name: _bizA), BusinessOption(id: 'biz2', name: '평택 센터')];
  }

  @override
  Future<AnnualStatsData> getAnnualStats({required List<String> businessIds, String? filterBusinessId, required int year}) {
    annualCalls++;
    final a = annual;
    if (a == null) return Future<AnnualStatsData>.error(StateError('du546 stats down'));
    return Future<AnnualStatsData>.value(a);
  }
}

/// 원래 경로로 보내는 Flutter 기반 채널과 이유(DU541 · DU545 와 같은 표).
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

/// 모든 플랫폼 메시지 관찰 — 기반 채널은 원래 경로, CF · Firestore · 그 밖은 이름을 기록하고 응답 null(이 화면은 주입 reader 만 읽는다 — 0 이어야 한다).
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

/// 외부 HTTP 차단(DU541 r2) — 클라이언트 객체 생성은 허용하고 센다(hcl), 실제 요청(모든 HttpClient 멤버 호출)은 [tries] 에 기록하고 실패시킨다.
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
    throw const SocketException('DU546 관측 — 외부 HTTP 차단');
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

/// 값이 모두 같으면 그 값, 비었거나 다르면 '-'.
String _one(Iterable<String> xs) {
  final s = xs.toSet();
  return s.length == 1 ? s.first : '-';
}

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

// ── 찾기(지어진 위젯 전부 · 화면 밖 캐시 포함 — 색은 위젯 값이라 위치와 무관) ──

/// 이 파일의 private 위젯(_StatCell · _DeltaBadge · _ExBadge)을 이름으로 — 시험에서 타입을 직접 쓸 수 없다.
bool _isA(Widget w, String typeName) => w.runtimeType.toString() == typeName;

// [주의] flutter_test 3.35 의 descendant/ancestor 는 안쪽 matching finder 를 그 자신의 skipOffstage 로 따로 평가해 교집합을 낸다
//   (finders.dart _DescendantFinderMixin.findInCandidates · _AncestorFinderMixin.findInCandidates) — 바깥만 false 면 캐시 칸 위젯이 빠진다.
//   그래서 안쪽 finder 도 모두 skipOffstage: false 다.
Finder _kind(Finder root, String typeName) => find.descendant(
    of: root, matching: find.byWidgetPredicate((w) => _isA(w, typeName), skipOffstage: false), skipOffstage: false);

/// 보이는 글자가 정확히 [s] 인 Text(낱말 묶음 문자 제거 · visible_text.dart 와 같은 식).
Finder _vis(Finder root, String s) => find.descendant(
    of: root, matching: find.byWidgetPredicate((w) => w is Text && visibleText(w.data ?? '') == s, skipOffstage: false), skipOffstage: false);

Finder _visHas(Finder root, String part) => find.descendant(
    of: root,
    matching: find.byWidgetPredicate((w) => w is Text && visibleText(w.data ?? '').contains(part), skipOffstage: false),
    skipOffstage: false);

Color _fgOf(WidgetTester t, Finder f) => t.widget<Text>(f.first).style?.color ?? Colors.black;

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

typedef _CellObs = ({String label, String lab, String val, String sub, double cr, List<_DeltaObs> deltas});

/// 통계 칸 하나(_StatCell) — 라벨 · 값 · 보조 줄 글 색 · 대비(흰 카드) · 그 칸의 전년 대비 칩.
_CellObs? _cellOf(WidgetTester t, Finder cell) {
  final ts = _ownTexts(cell);
  if (ts.length < 2) return null;
  final labC = ts[0].style?.color ?? Colors.black;
  final valC = ts[1].style?.color ?? Colors.black;
  final subC = ts.length > 2 ? (ts[2].style?.color ?? Colors.black) : null;
  var cr = _contrast(labC, Colors.white);
  final cv = _contrast(valC, Colors.white);
  if (cv < cr) cr = cv;
  if (subC != null && _contrast(subC, Colors.white) < cr) cr = _contrast(subC, Colors.white);
  return (label: visibleText(ts[0].data ?? ''), lab: _hex(labC), val: _hex(valC), sub: _h(subC), cr: cr, deltas: _deltasIn(t, cell));
}

typedef _BadgeObs = ({String face, String fg, double cr});
typedef _BandObs = ({String face, String bd, String icon, String fg, double cr});
typedef _SerObs = ({String fg, String bar});

/// 계열 한 줄(업무별 인건비 · 신뢰점수 등급) — 이름 글 [name] 의 가장 가까운 Column 안 [pick] 글 색 · 막대(LinearProgressIndicator) 색.
_SerObs? _serOf(WidgetTester t, Finder root, String name, bool Function(String s) pick) {
  final nf = _vis(root, name);
  if (nf.evaluate().length != 1) return null;
  final col = find.ancestor(of: nf, matching: find.byType(Column, skipOffstage: false)).first;
  final others = find.descendant(of: col, matching: find.byType(Text, skipOffstage: false), skipOffstage: false).evaluate().map((e) => e.widget as Text).where((w) => pick(w.data ?? '')).toList();
  final bars = find.descendant(of: col, matching: find.byType(LinearProgressIndicator, skipOffstage: false), skipOffstage: false);
  if (others.length != 1 || bars.evaluate().length != 1) return null;
  return (fg: _h(others.first.style?.color), bar: _h(t.widget<LinearProgressIndicator>(bars).valueColor?.value));
}

// ── 고정값 — admin_stats_content_render_test.dart:108 의 _annual 틀(현행 schema · 단위 원/건/명) ──

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
const _kpiLabels = ['급여 확정 근무', '출근율', '노쇼율', '재고용률'];

AnnualStatsData? _dataOf(String id) {
  switch (id) {
    case 'NORMAL': // 정상 집계 — 전년 대비 4(총 인건비 · 급여 확정 근무 오름 · 출근율 내림 · 노쇼율 오름=줄어듦) · 지각/결근 2명 · 업무 3 · 등급 5
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
    case 'ZERO': // 정상 응답 · 그해 근태 0건 · 리뷰 없음
      return AnnualStatsData(
        year: _y, totalWage: 0, totalWorkCount: 0, totalWorkerCount: 0, prevYearTotalWage: 0, prevYearTotalWorkCount: 0,
        attendanceRecordCount: 0, attendanceRate: 0, prevYearAttendanceRate: 0, rehireRate: 0, avgRating: 0,
        noShowCount: 0, noShowRate: 0, prevYearNoShowRate: 0, wageByWorkType: const {}, monthlyTrends: _trends(false),
        exceptions: const [], exceptionMonth: _m,
      );
    case 'UNCONF': // 상태를 확인할 수 없는 근태 2건 — 출근율 · 노쇼율 '확인 필요' + '미확인 2건 ›'(DU425 purple)
      return AnnualStatsData(
        year: _y, totalWage: 6420000, totalWorkCount: 31, totalWorkerCount: 9, prevYearTotalWage: 0, prevYearTotalWorkCount: 0,
        attendanceRecordCount: 40, unconfirmedAttendanceCount: 2, attendanceRate: 90.0, prevYearAttendanceRate: 0, rehireRate: 60.0, avgRating: 4.2,
        noShowCount: 1, noShowRate: 2.5, prevYearNoShowRate: 0, wageByWorkType: const {}, monthlyTrends: _trends(true),
        exceptions: const [], exceptionMonth: _m, reviewStatsState: ReviewStatsState.available,
      );
    case 'ATTFAIL': // 근태 조회 실패(부분 · limitReached) — 확인 불가 · 조회 실패 띠 · 리뷰도 실패
      return AnnualStatsData(
        year: _y, totalWage: 0, totalWorkCount: 0, totalWorkerCount: 0, prevYearTotalWage: 0, prevYearTotalWorkCount: 0,
        attendanceRate: 0, prevYearAttendanceRate: 0, rehireRate: 0, avgRating: 0, noShowCount: 0, noShowRate: 0, prevYearNoShowRate: 0,
        wageByWorkType: const {}, monthlyTrends: _trends(false), exceptions: const [], exceptionMonth: _m,
        reviewStatsState: ReviewStatsState.unavailable,
        attendanceStatsState: AttendanceStatsState.unavailable, prevAttendanceStatsState: AttendanceStatsState.unavailable,
      );
    default: // FAIL — 연간 조회 자체가 실패(통계를 불러오지 못했습니다 · 다시 시도)
      return null;
  }
}

final String _wT1 = _hex(AppColors.textPrimary);
final String _wT2 = _hex(AppColors.textSecondary);
final String _wT3 = _hex(AppColors.textTertiary);
final String _wG900 = _hex(AppColors.grey900);
final String _wG600 = _hex(AppColors.grey600);
final String _wPurple = _hex(AppColors.purple);
final String _wErrD = _hex(AppColors.errorDark);

/// strict 통계 칸 기대 [v1 출근율 · v2 노쇼율 · v3 재고용률 · s3 별점] — lines_du546.py KPI 와 같은 표(후보 C7–C10 · DU329 · DU425 그대로인 값).
Map<String, List<String>> _kpiStrict() => {
      'NORMAL': [_wT1, _wErrD, _wT1, _wG600],
      'ZERO': [_wT1, _wT3, _wT3, '-'],
      'UNCONF': [_wPurple, _wPurple, _wT1, _wG600],
      'ATTFAIL': [_wT3, _wT3, _wT3, '-'],
      'FAIL': ['-', '-', '-', '-'],
    };

/// 상태별 개수 기대 [통계 칸 · 전년 대비 · 오름 · 내림 · 배지 · 지각 · 결근 · 실패 띠 · 데이터 없음 띠 · 업무 · 등급 · 실패 본문] — 두 모드 같다(표시 조건 그대로).
const _counts = <String, List<int>>{
  'NORMAL': [4, 4, 3, 1, 3, 2, 1, 0, 0, 3, 5, 0],
  'ZERO': [4, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0],
  'UNCONF': [4, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
  'ATTFAIL': [4, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0],
  'FAIL': [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1],
};

typedef _V = ({String id, double w, double h, double s});
const _views = <_V>[(id: 'W', w: 390.0, h: 844.0, s: 1.0), (id: 'B', w: 320.0, h: 640.0, s: 2.0)];
const _cases = <({String id, int shots})>[
  (id: 'NORMAL', shots: 2), (id: 'ZERO', shots: 1), (id: 'UNCONF', shots: 1), (id: 'ATTFAIL', shots: 1), (id: 'FAIL', shots: 1),
];

final bool _before = Platform.environment['DU_BEFORE_OBSERVE'] == '546';
final Map<String, String> _env = Platform.environment;
final bool _optIn =
    (_env['DU1_VQ_PHASE'] == 'before' && _env['DU1_VQ_RUN'] == 'du546-tb' && _env['DU_BEFORE_OBSERVE'] == '546') ||
        (_env['DU1_VQ_PHASE'] == 'after' && _env['DU1_VQ_RUN'] == 'du546-ta' && _env['DU_BEFORE_OBSERVE'] == null);

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
      FirebasePlatform.instance = _FakeCore();
      await Firebase.initializeApp();
      await _loadFonts();
    } finally {
      m.allMessagesHandler = prevAll;
      HttpOverrides.global = prevHttp;
    }
    final nUnexp = wire.unexpected.length + wire.cf.length + wire.fs.length;
    final nHttp = net.tries.length;
    _out('R546 setup init unexpected=$nUnexp http=$nHttp un64=${_enc([...wire.unexpected, ...wire.cf, ...wire.fs].join('|'))}');
    final initOk = nUnexp == 0 && nHttp == 0;
    if (!initOk) _halt = 'setUpAll 초기화 안전 대역';
    expect(initOk, isTrue, reason: 'setUpAll 초기화 중 예상 밖 채널 0 · HTTP 0 — [${wire.unexpected.join(' | ')}]');
  });

  for (final v in _views) {
    for (final c in _cases) {
      testWidgets('S914AS-${v.id}-${c.id} 관리자 통계 색 1차 — 통계 숫자 중립 · 전년 대비/지각·결근 칩 StatusBadge 짝 · 조회 실패 띠 중립 · 재고용률 amber 0', (t) async {
        final tok = 'S914AS-${v.id}-${c.id}';
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
        _out('D546 $tok begin mode=$mode phase=${Platform.environment['DU1_VQ_PHASE'] ?? '(unset)'} env=$_envLine manifest=$_manifest');
        final seen = _Seen();
        void need(String k, bool ok, [String why = '']) => expect(ok, isTrue, reason: '$tok $k $why');
        final checks = <(String, bool, String)>[];
        void chk(String k, bool ok, [String why = '']) => checks.add((k, ok, why));

        final svc = _FakeStats(_dataOf(c.id));
        final want = _counts[c.id]!;
        Object? failure;
        StackTrace? failureSt;
        var shots = 0;
        try {
          FlutterError.onError = seen.add;
          final key = GlobalKey();
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
                home: AdminStatsScreen(businessIds: const ['biz1', 'biz2'], service: svc),
              ),
            ),
          ));
          for (var i = 0; i < 20; i++) {
            await t.pump(const Duration(milliseconds: 100));
          }
          final scr = find.byType(AdminStatsScreen);
          final nScr = scr.evaluate().length;
          need('화면 1', nScr == 1, '개수 $nScr');

          Future<void> shot(String id, String state) async {
            _out('D546 $tok shot $id ovf=${seen.overflows.length}');
            await vqCapture(t, key, '${tok}_$id', conditions: {
              'viewport': '${v.w.toInt()}x${v.h.toInt()}', 'textScaler': v.s, 'run': vqRun, 'manifest': _manifest, 'mode': mode,
              'fixture': c.id, 'state': state,
            });
            shots++;
          }

          // ① 첫 화면(맨 위) 캡처.
          await shot('1${c.id == 'NORMAL' ? 'top' : c.id.toLowerCase()}', 'stats-${c.id.toLowerCase()}-top');

          // ② 맨 위부터 끝까지 jumpTo 로 내려 가며 지어진 위젯 값을 처음 본 때 한 번씩 모은다(누름 · 끌기 0).
          final words = <String>{};
          final cells = <String, _CellObs>{};
          final heroDeltas = <_DeltaObs>[];
          final badges = <String, _BadgeObs>{};
          final keep = <String, String>{};
          final wt = <String, _SerObs>{};
          final tr = <String, _SerObs>{};
          _BandObs? eb;
          _BandObs? nd;
          var heroSeen = false;
          var secSeen = false;
          var failN = 0;
          var failT = '-';
          var failS = '-';
          var retryN = 0;

          void collect() {
            for (final e in find.descendant(of: scr, matching: find.byType(Text, skipOffstage: false), skipOffstage: false).evaluate()) {
              final d = (e.widget as Text).data;
              if (d != null && d.isNotEmpty) words.add(visibleText(d).replaceAll(RegExp(r'\d+'), '#'));
            }
            // 머리(연도 · 사업장 선택) — 목록 밖.
            for (final (k, s) in [('ytxt', '$_y년'), ('bizt', '전체 사업장')]) {
              final f = _vis(scr, s);
              if (!keep.containsKey(k) && f.evaluate().length == 1) keep[k] = _hex(_fgOf(t, f));
            }
            final bz = _vis(scr, '전체 사업장');
            if (!keep.containsKey('bizf') && bz.evaluate().length == 1) {
              keep['bizf'] = _hex(_faceOf(t, find.ancestor(of: bz, matching: find.byType(Container, skipOffstage: false)).first));
            }
            // 총 인건비(라벨 · 범위 · 큰 값 · 전년 대비 칩).
            final hl = _vis(scr, '총 인건비');
            if (!heroSeen && hl.evaluate().length == 1) {
              heroSeen = true;
              final hero = find.ancestor(of: hl, matching: find.byType(Column, skipOffstage: false)).first;
              final hts = _ownTexts(hero);
              keep['hlab'] = _hex(_fgOf(t, hl));
              final hr = _vis(scr, '$_y년 전체');
              keep['hrng'] = hr.evaluate().length == 1 ? _hex(_fgOf(t, hr)) : '-';
              keep['hval'] = hts.length == 3 ? _h(hts.last.style?.color) : '-';
              heroDeltas.addAll(_deltasIn(t, hero));
            }
            // 통계 칸 4.
            final cf = _kind(scr, '_StatCell');
            final nC = cf.evaluate().length;
            for (var i = 0; i < nC; i++) {
              final o = _cellOf(t, cf.at(i));
              if (o != null) cells.putIfAbsent(o.label, () => o);
            }
            // 근태 조회 실패 띠 · 데이터 없음 띠.
            final ebF = _vis(scr, '출근 데이터를 불러올 수 없습니다');
            if (eb == null && ebF.evaluate().length == 1) {
              final box = find.ancestor(of: ebF, matching: find.byType(Container, skipOffstage: false)).first;
              final faceC = _faceOf(t, box);
              final fgC = _fgOf(t, ebF);
              eb = (face: _hex(faceC), bd: _edgeOf(t, box), icon: _iconIn(t, box), fg: _hex(fgC),
                  cr: _contrast(fgC, Color.alphaBlend(faceC, AppColors.background)));
            }
            final ndF = _visHas(scr, '근태 데이터가 없습니다');
            if (nd == null && ndF.evaluate().length == 1) {
              final box = find.ancestor(of: ndF, matching: find.byType(Container, skipOffstage: false)).first;
              final faceC = _faceOf(t, box);
              final fgC = _fgOf(t, ndF);
              nd = (face: _hex(faceC), bd: _edgeOf(t, box), icon: _iconIn(t, box), fg: _hex(fgC),
                  cr: _contrast(fgC, Color.alphaBlend(faceC, AppColors.background)));
            }
            // 지각 · 결근 구역 머리 · 배지.
            final stF = _visHas(scr, '지각·결근 내역');
            if (!secSeen && stF.evaluate().length == 1) {
              secSeen = true;
              final sec = find.ancestor(of: stF, matching: find.byType(Container, skipOffstage: false)).first;
              keep['stl'] = _hex(_fgOf(t, stF));
              final sd = _vis(scr, '지각 2회 이상 또는 결근·노쇼가 있는 근로자');
              keep['sds'] = sd.evaluate().length == 1 ? _hex(_fgOf(t, sd)) : '-';
              final si = find.descendant(of: sec, matching: find.byIcon(Icons.event_note_outlined, skipOffstage: false), skipOffstage: false);
              keep['sic'] = si.evaluate().length == 1 ? _h(t.widget<Icon>(si).color) : '-';
              final ch = find.descendant(of: sec, matching: find.byIcon(Icons.chevron_right, skipOffstage: false), skipOffstage: false);
              keep['chv'] = _one(ch.evaluate().map((e) => _h((e.widget as Icon).color)));
            }
            final bf = _kind(scr, '_ExBadge');
            final nB = bf.evaluate().length;
            for (var i = 0; i < nB; i++) {
              final b = bf.at(i);
              final tx = find.descendant(of: b, matching: find.byType(Text, skipOffstage: false), skipOffstage: false);
              if (tx.evaluate().length != 1) continue;
              final lab = visibleText(t.widget<Text>(tx).data ?? '');
              final faceC = _faceOf(t, find.descendant(of: b, matching: find.byType(Container, skipOffstage: false), skipOffstage: false).first);
              final fgC = _fgOf(t, tx);
              badges.putIfAbsent(lab, () => (face: _hex(faceC), fg: _hex(fgC), cr: _contrast(fgC, Color.alphaBlend(faceC, Colors.white))));
            }
            // 업무별 인건비 · 신뢰점수(계열색 — 그대로 기록).
            for (final n in _wtNames) {
              if (!wt.containsKey(n)) {
                final o = _serOf(t, scr, n, (s) => s != n);
                if (o != null) wt[n] = o;
              }
            }
            for (final g in _grades) {
              if (!tr.containsKey(g)) {
                final o = _serOf(t, scr, g, (s) => s.contains('명 ('));
                if (o != null) tr[g] = o;
              }
            }
            // 차트 범례 점 · 막대 안내 · 차트 안내 · 하위 행 제목.
            final lg = _vis(scr, '이달');
            if (!keep.containsKey('leg') && lg.evaluate().length == 1) {
              final row = find.ancestor(of: lg, matching: find.byType(Row, skipOffstage: false)).first;
              keep['leg'] = _hex(_faceOf(t, find.descendant(of: row, matching: find.byType(Container, skipOffstage: false), skipOffstage: false).first));
            }
            for (final (k, s) in [('hint', '막대를 탭하면 해당 월 상세 보기'), ('cmsg', '조회 실패'), ('cmsg', '데이터 없음'), ('sub', '전체 근태 (건)')]) {
              final f = _vis(scr, s);
              if (!keep.containsKey(k) && f.evaluate().length == 1) keep[k] = _hex(_fgOf(t, f));
            }
            // 통계 전체 조회 실패 본문(DU333).
            final ft = _vis(scr, '통계를 불러오지 못했습니다');
            if (failN == 0 && ft.evaluate().length == 1) {
              failN = 1;
              failT = _hex(_fgOf(t, ft));
              final fs = _vis(scr, '네트워크 상태를 확인 후 당겨서 새로고침하세요');
              failS = fs.evaluate().length == 1 ? _hex(_fgOf(t, fs)) : '-';
              retryN = _vis(scr, '다시 시도').evaluate().length;
            }
          }

          ScrollPosition? pos() {
            final sf = find.descendant(of: scr, matching: find.byType(Scrollable, skipOffstage: false), skipOffstage: false);
            return sf.evaluate().isEmpty ? null : t.state<ScrollableState>(sf.first).position;
          }

          collect();
          var steps = 0;
          for (var i = 0; i < 80; i++) {
            final p = pos();
            if (p == null || p.pixels >= p.maxScrollExtent - 0.5) break;
            final nx = p.pixels + 160 > p.maxScrollExtent ? p.maxScrollExtent : p.pixels + 160;
            p.jumpTo(nx);
            await t.pump(const Duration(milliseconds: 16));
            steps++;
            collect();
          }

          // ③ 출력(sub 마다 한 줄 · 값은 모은 변수에서만).
          final wordList = words.toList()..sort();
          _out('D546 $tok att txt n=${wordList.length} set=${_enc(wordList.join('|'))}');

          final nKpi = cells.length;
          final kc = [for (final l in _kpiLabels) cells[l]];
          final kv = [for (final o in kc) o?.val ?? '-'];
          final ks = [for (final o in kc) o?.sub ?? '-'];
          final kLab = _one(cells.values.map((o) => o.lab));
          final kCr = nKpi > 0 && cells.values.every((o) => o.cr >= 4.5);
          _out('D546 $tok att kpi n=$nKpi lab=$kLab v0=${kv[0]} v1=${kv[1]} v2=${kv[2]} v3=${kv[3]} s1=${ks[1]} s2=${ks[2]} s3=${ks[3]} cr45=$kCr');

          final allD = [...heroDeltas, for (final o in cells.values) ...o.deltas];
          final ups = allD.where((x) => x.up).toList();
          final dns = allD.where((x) => !x.up).toList();
          final pFace = _one(ups.map((x) => x.face));
          final pFg = _one(ups.map((x) => x.fg));
          final pIcon = _one(ups.map((x) => x.icon));
          final nFace = _one(dns.map((x) => x.face));
          final nFg = _one(dns.map((x) => x.fg));
          final nIcon = _one(dns.map((x) => x.icon));
          final dCr = allD.isNotEmpty && allD.every((x) => x.cr >= 4.5);
          _out('D546 $tok att delta n=${allD.length} up=${ups.length} dn=${dns.length} pface=$pFace pfg=$pFg picon=$pIcon nface=$nFace nfg=$nFg nicon=$nIcon cr45=$dCr');

          final lateB = [for (final e in badges.entries) if (e.key.startsWith('지각')) e.value];
          final absB = [for (final e in badges.entries) if (e.key.startsWith('결근')) e.value];
          final lFace = _one(lateB.map((x) => x.face));
          final lFg = _one(lateB.map((x) => x.fg));
          final aFace = _one(absB.map((x) => x.face));
          final aFg = _one(absB.map((x) => x.fg));
          final bCr = badges.isNotEmpty && badges.values.every((x) => x.cr >= 4.5);
          final sIc = keep['sic'] ?? '-';
          final sTl = keep['stl'] ?? '-';
          final sDs = keep['sds'] ?? '-';
          final sChv = keep['chv'] ?? '-';
          _out('D546 $tok att exrow n=${badges.length} late=${lateB.length} abs=${absB.length} lface=$lFace lfg=$lFg aface=$aFace afg=$aFg '
              'sic=$sIc stl=$sTl sds=$sDs chv=$sChv cr45=$bCr');

          final ebv = eb;
          final ebN = ebv == null ? 0 : 1;
          final ebCr = ebv != null && ebv.cr >= 4.5;
          _out('D546 $tok att errband n=$ebN face=${ebv?.face ?? '-'} bd=${ebv?.bd ?? '-'} icon=${ebv?.icon ?? '-'} fg=${ebv?.fg ?? '-'} cr45=$ebCr');

          final ndv = nd;
          final ndN = ndv == null ? 0 : 1;
          final ndCr = ndv != null && ndv.cr >= 4.5;
          _out('D546 $tok att nodata n=$ndN face=${ndv?.face ?? '-'} icon=${ndv?.icon ?? '-'} fg=${ndv?.fg ?? '-'} cr45=$ndCr');

          String joined(Map<String, _SerObs> m, List<String> order, bool bar) =>
              m.isEmpty ? '-' : [for (final k in order) if (m[k] != null) (bar ? m[k]!.bar : m[k]!.fg)].join('.');
          final wtC = joined(wt, _wtNames, false);
          final wtB = joined(wt, _wtNames, true);
          final trC = joined(tr, _grades, false);
          final trB = joined(tr, _grades, true);
          _out('D546 $tok att series wtn=${wt.length} wt=$wtC wtb=$wtB trn=${tr.length} tr=$trC trb=$trB');

          final kYtxt = keep['ytxt'] ?? '-';
          final kBizt = keep['bizt'] ?? '-';
          final kBizf = keep['bizf'] ?? '-';
          final kHlab = keep['hlab'] ?? '-';
          final kHrng = keep['hrng'] ?? '-';
          final kHval = keep['hval'] ?? '-';
          final kLeg = keep['leg'] ?? '-';
          final kHint = keep['hint'] ?? '-';
          final kCmsg = keep['cmsg'] ?? '-';
          final kSub = keep['sub'] ?? '-';
          _out('D546 $tok att keep ytxt=$kYtxt bizt=$kBizt bizf=$kBizf hlab=$kHlab hrng=$kHrng hval=$kHval leg=$kLeg hint=$kHint cmsg=$kCmsg sub=$kSub');

          final hdr = kYtxt == '-' ? 0 : 1;
          _out('D546 $tok att fail n=$failN tfg=$failT sfg=$failS rn=$retryN kpi=$nKpi hdr=$hdr');
          _out('R546 $tok sweep steps=$steps words=${wordList.length}');

          // ④ 개수(두 모드 같다 — 표시 조건 그대로).
          final got = [nKpi, allD.length, ups.length, dns.length, badges.length, lateB.length, absB.length, ebN, ndN, wt.length, tr.length, failN];
          need('개수 표(통계 칸 · 전년 대비 · 배지 · 띠 · 계열 · 실패 본문) = 상태 기대', got.join(',') == want.join(','), 'got ${got.join(',')} want ${want.join(',')}');
          chk('머리 연도 textPrimary · 사업장 선택 grey100 면/textPrimary 글(그대로 · 실패에도 머리 유지)',
              kYtxt == _wT1 && kBizt == _wT1 && kBizf == _hex(AppColors.grey100) && hdr == 1, '$kYtxt/$kBizt/$kBizf/$hdr');
          if (nKpi > 0) chk('지표 라벨 textTertiary(DU329 그대로)', kLab == _wT3, kLab);
          if (nKpi > 0) chk('급여 확정 근무 값 grey900/확인 불가 textTertiary(DU329 그대로)', kv[0] == (c.id == 'ATTFAIL' ? _wT3 : _wG900), kv[0]);
          if (!_before) {
            final ws = _kpiStrict()[c.id]!;
            chk('strict 통계 숫자 — 출근율 · 재고용률 중립 · 노쇼율 양수 errorDark · 확인 필요 purple · 없음/확인 불가 textTertiary · 별점 grey600',
                kv[1] == ws[0] && kv[2] == ws[1] && kv[3] == ws[2] && ks[3] == ws[3], '${kv.join('/')} ${ks.join('/')} want ${ws.join('/')}');
            if (nKpi > 0) chk('strict 통계 칸 글 대비 ≥4.5', kCr, 'cr45 $kCr');
            if (allD.isNotEmpty) {
              chk('strict 전년 대비 칩 = successBg/successDark(오름) · errorBg/errorDark(내림) · 대비 ≥4.5',
                  pFace == _hex(AppColors.successBg) && pFg == _hex(AppColors.successDark) && pIcon == _hex(AppColors.successDark) &&
                      nFace == _hex(AppColors.errorBg) && nFg == _wErrD && nIcon == _wErrD && dCr,
                  '$pFace/$pFg/$pIcon $nFace/$nFg/$nIcon $dCr');
            }
            if (badges.isNotEmpty) {
              chk('strict 지각 warningBg/warningDark · 결근 errorBg/errorDark · 대비 ≥4.5',
                  lFace == _hex(AppColors.warningBg) && lFg == _hex(AppColors.warningDark) && aFace == _hex(AppColors.errorBg) && aFg == _wErrD && bCr,
                  '$lFace/$lFg $aFace/$aFg $bCr');
            }
            if (ebv != null) {
              chk('strict 조회 실패 띠 = 흰 면 · grey200 선 · errorDark 글 · error 아이콘 · 대비 ≥4.5',
                  ebv.face == _hex(AppColors.surface) && ebv.bd == _hex(AppColors.grey200) && ebv.fg == _wErrD && ebv.icon == _hex(AppColors.error) && ebCr,
                  '${ebv.face}/${ebv.bd}/${ebv.fg}/${ebv.icon} $ebCr');
            }
            if (ndv != null) {
              chk('strict 데이터 없음 띠 = grey100 면 · grey600 아이콘 · textSecondary 글 · 대비 ≥4.5',
                  ndv.face == _hex(AppColors.grey100) && ndv.icon == _wG600 && ndv.fg == _wT2 && ndCr, '${ndv.face}/${ndv.icon}/${ndv.fg} $ndCr');
            }
          }

          // ⑤ (NORMAL) 끝까지 내린 화면 캡처 — 업무별 인건비 · 차트 · 신뢰점수.
          if (c.id == 'NORMAL') await shot('2low', 'stats-normal-bottom');
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
        final nAnn = svc.annualCalls;
        final nOpt = svc.optionCalls;
        _out('D546 $tok att wire cf=$nCf fs=$nFs unexpected=$nUnexp http=$nHttp hcl=$nHcl ann=$nAnn opt=$nOpt');

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
        final unText = [...wire.unexpected, ...wire.cf.map((x) => 'cf $x'), ...wire.fs.map((x) => 'fs $x'), ...net.tries].join(' | ');
        _out('R546 $tok raw ovf64=${_enc(ovfRaw)} fw64=${_enc(fwRaw)} un64=${_enc(unText)} cleanup64=${_enc(cleanupErr)} '
            'fail64=${_enc(failure?.toString() ?? '')}');
        _out('D546 $tok att fw n=$nFw');
        _out('D546 $tok done state=${c.id} mode=$mode captures=$shots overflows=$nOvf exc=${exc != null}');

        final f0 = failure;
        if (f0 != null) {
          _halt ??= '$tok ${f0.toString().split('\n').first}';
          Error.throwWithStackTrace(f0, failureSt ?? StackTrace.current);
        }
        chk('예상 밖 채널 · CF · Firestore 0 · HTTP 요청 0 · 주입 reader 연간 1 · 사업장 1', nCf == 0 && nFs == 0 && nUnexp == 0 && nHttp == 0 && nAnn == 1 && nOpt == 1,
            '$unText ann $nAnn opt $nOpt');
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
