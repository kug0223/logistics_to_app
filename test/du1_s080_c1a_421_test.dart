// [r3 · 판정81/인계81 · A 계약] 수리 r1 cb06f020 보존. 바뀐 것: 'stat geo' 의 selIn 을 새 계약으로 —
//   selInX(선택 상자 가로 ⊂ 자기 문단 · 자기 칸 각 ±0.5) · selCardY(세로 ⊂ 카드 ±0.5) · selIn = 둘의 AND(두 모드 must) ·
//   selOverY(문단 · 칸 세로 최대 초과 · num2 관측) · selOverAt(그 최대치의 문단ID:기준, 없으면 -) · 빈 수집/비유한 rect 실패 · 진단 원좌표 3자리.
//   그 밖(fixture · 뷰 · 배율 · 기대 · 공차 · 다른 must · 캡처 · sidecar 7키 · 핸들 finally 해제)은 cb06f020 그대로다.
// [r2 · 판정78/인계78] r1 d28c2933 보존. 바뀐 것: F78-2 tok 접두 C1A421 → S080CA(lcell ^S\d{3}[A-Z]{1,2}$) · 상태 키 H35L/H35 → REACKL/REACK(^[A-Z]+$) ·
//   F78-3 sidecar conditions 에서 clockUtc 제거(lpost 정확 7키 — 고정 시계는 아래 _clock 소스 · 보고에 보존) ·
//   F78-5 'stat geo' clip → maxOver(didExceedMaxLines 만) 이름 정정 + selIn(실제 글자 선택 상자 ⊂ 문단 rect ⊂ 칸, 반올림 전 좌표 ±0.5) 추가.
//   fixture · 뷰 · 다른 기대 · 공차는 그대로다.
// [S080 C1-a · DU421 후보 · 감사77 인계 §2] 지원자 홈 '내 지원 현황' 3칸 요약 라벨('검토 중' · '확정' · '계약 대기')의 줄바꿈 · 낱말 경계 · 원문 낭독 라벨.
//   records 후보 파일이다 — 승인 전에는 AlFit test/ 에 두지 않는다(analyze 0 · 정적 미검증. 승인 실행의 ANALYZE1 이 첫 검사).
//   하네스: UserHomeScreen(reads:, clock:) — du1_vq_capture_test(023d56d9)의 VQ-01c · H35-B2/H36-B2 · H35-A 와 같은 앱 목록 · 약관 · 날짜(DU1_VQ_DATE=2026-11-08 의
//     _today · _clock = 그날 KST 10:00)를 이 파일 안에 옮겼다(공용 관측 시험은 바꾸지 않는다). 렌더 트리 = 그 시험 _capture 와 같은
//     MultiProvider → RepaintBoundary → MaterialApp(workerTheme · builder TextScaler) · UserTabScope 없음. 글꼴 = 그 시험 _loadFonts 와 같은 4 등록(FlutterTest 별칭 포함).
//     차이 1: _Worker.passVerifiedAt = 고정 2026-10-01(DU420 과 같음 · vq 는 실행 시각−30일). 두 쪽 모두 null 아님.
//   장면: 뷰 W 390x844@1.0 · B 320x640@2.0 × 상태 NEWL(VQ-01c 앱 · 약관 현재) · REACKL(H35-B2/H36-B2 앱 · 재동의 · 긴 이름) · REACK(H35-A 앱 · 재동의) = 공개 6.
//     목표 4 → 장면: VQ-01c = B-NEWL · H35-B2 · H36-B2 = B-REACKL(두 시험은 같은 앱 · 약관 · 뷰 — 통계 카드 라벨 관측에 한해 한 장면, 두 CTA 동작 동등성 아님) · H35-A = W-REACK.
//     나머지 W-NEWL · W-REACKL · B-REACK 는 W/B 짝 대조용(목표 아님).
//   관측(통계 카드를 Scrollable.ensureVisible(alignment 0.5) 한 같은 프레임): 'stat geo' 카드 · 본문 표시 영역 · 세 칸(Column) · 값 · 라벨 rect, 포함 ·
//     표시 · maxOver(maxLines 초과만) · [r3] selInX · selCardY · selIn · selOverY · selOverAt(선택 상자 기하 — 잉크 · 조상 clip 인증 아님, PNG 직접 대조와 함께) · 넘침 /
//     'stat text' 라벨 글자별 선택 상자를 같은 top(±0.5)끼리 묶은 실제 줄(TextLayout.plain · 앞뒤 공백 제거) — 줄 수 · 줄 문자열 · 줄별 좌우 끝(전역 x, 공백 · U+2060 제외) · 낱말 경계 /
//     'stat sem' Row 범위 의미 노드: 원문 라벨 정확 일치 수 · U+2060 포함 수 · 라벨 Text 의 semanticsLabel · textAlign · 표시 문자열 종류 /
//     'stat style' 라벨 · 값 문단의 실제 크기 · 굵기 · 색(정확) · 값 자간(정확 -0.50) · 라벨 자간(테마에서 물려받음 — 관측) · 값 글자.
//   모드: DU_BEFORE_OBSERVE=421 이면 before(현행 홈 ee1f3f31 — 위젯 계약 = 원 Text · 나머지 관측만), 아니면 strict(후보 141bf0a6 — 위젯 계약 · 낱말 경계 · 의미 1 · 뷰별 줄 단언).
//   낭독: 의미 트리 라벨 검사일 뿐 실제 스크린리더 낭독 인증이 아니다.
//   출력 줄: lkit 선언형 계약 'D421 <tok> <kind> [<sub>] k=v …' — 값 공백 0(줄 문자열 공백 → '_' · 줄 구분 '|' · 목록 ',').
// ignore_for_file: depend_on_referenced_packages
import 'dart:convert';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ALfit/models/core/application_model.dart';
import 'package:ALfit/models/core/business_model.dart';
import 'package:ALfit/models/core/legal_readiness.dart';
import 'package:ALfit/models/core/renewal_proposal_model.dart';
import 'package:ALfit/models/core/slot_model.dart';
import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/models/core/user_region.dart';
import 'package:ALfit/providers/notification_provider.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/screens/user/user_home_reads.dart';
import 'package:ALfit/screens/user/user_home_screen.dart';
import 'package:ALfit/services/payroll_correction_service.dart';
import 'package:ALfit/theme/app_colors.dart';
import 'package:ALfit/theme/role_theme.dart';
import 'package:ALfit/utils/format_helper.dart';
import 'package:ALfit/utils/text_layout.dart';

import 'support/checkin_contract_fixture.dart';
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

/// 지원자 provider 대역(DU420 시험 :95–111 과 같은 게터)
class _Worker extends UserProvider {
  @override
  UserModel? get currentUser => UserModel(
      uid: 'u1', username: 'u1', name: '김근로', email: 'u1@alfit.local', role: UserRole.USER,
      homeRegion: const UserRegion(province: '서울특별시', city: '강남구', district: '역삼동'),
      accountStatus: 'active', passVerifiedAt: DateTime.utc(2026, 10, 1), totalWorkDays: 3);
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

// 고정: vq _clock(DU1_VQ_DATE=2026-11-08 → 그날 KST 10:00 = 01:00Z) · _today = toKstDate(…) = DateTime.utc(2026,11,8)
//   [r2 F78-3] 이 시각은 sidecar 키로 쓰지 않는다(lpost 정확 7키) — 근거는 이 소스와 보고서다.
final DateTime _clock = DateTime.utc(2026, 11, 8, 1);
final DateTime _today = FormatHelper.toKstDate(_clock);
DateTime _day(int o) => _today.add(Duration(days: o));

// vq _short(:237–244) 의 today 없는 경로
ApplicationModel _short(String id, int dayOffset, {DateTime? confirmedAt, String type = '피킹', String start = '09:00', String end = '18:00'}) =>
    ApplicationModel(
      id: id, toId: 'to_$id', uid: 'u1', businessId: 'biz1', businessName: '강남 물류센터', toTitle: '단기 공고',
      status: AppStatus.confirmed, selectedWorkType: type, startTime: start, endTime: end, wage: 12000, wageType: 'hourly',
      workDate: _day(dayOffset), confirmedAt: confirmedAt, appliedAt: _day(-3));

// vq VQ-01c longApp(:2272–2275) · h35Apps(long: true) 첫 항목(:2381–2386, id 만 new1) 과 같은 값
ApplicationModel _longNew(String id) => ApplicationModel(
    id: id, toId: 'to_$id', uid: 'u1', businessId: 'biz1', businessName: '[QA] 아주 긴 이름의 강남 물류센터 평택 2공장',
    toTitle: '단기 공고', status: AppStatus.confirmed, selectedWorkType: '냉장 피킹·검수 보조', startTime: '09:00', endTime: '18:00',
    wage: 12000, wageType: 'hourly', workDate: _day(3), confirmedAt: _clock.subtract(const Duration(hours: 2)), appliedAt: _day(-3));

// vq h35Apps(:2379–2389) 의 today · clock 없는 경로
List<ApplicationModel> _h35Apps({bool long = false}) => [
      long ? _longNew('new1') : _short('new1', 3, confirmedAt: _clock.subtract(const Duration(hours: 2))),
      _short('next2', 5, type: '상하차', start: '13:00', end: '22:00'),
    ];
const _h35Legal = LegalReadiness(status: LegalReadinessStatus.reconsentRequired, reconsentRequired: ['service_terms']); // vq :2390
const _cur = LegalReadiness(status: LegalReadinessStatus.current); // vq _reads 기본값

// vq _reads(:325–342) 와 같은 경계
UserHomeReads _reads(List<ApplicationModel> apps, {LegalReadiness legal = _cur}) {
  Future<List<ApplicationModel>>? last;
  return UserHomeReads(
    slotsForTO: (_) async => const <SlotModel>[],
    myContracts: (_) async => completedContractsFor(await (last ?? Future.value(const <ApplicationModel>[]))),
    myApplications: (_) => last = Future.value(apps),
    myMonthlyAttendances: ({required String userId, required int year, required int month}) async => const [],
    publishedTOs: () async => const [],
    pendingIdCardRequests: (_) async => const [],
    myRenewalProposals: () async => const <RenewalProposalModel>[],
    businessById: (_) async => BusinessModel(
        id: 'biz1', name: '강남 물류센터', ownerId: 'a1', businessNumber: '000-00-00000', address: '서울특별시 강남구 테헤란로 1',
        category: '물류', subCategory: '창고', isApproved: true, createdAt: _day(-200)),
    invalidatePublishedTOsCache: () {},
    documentCorrections: () async => DocumentCorrectionSurface.empty,
    legalReadiness: () async => legal,
  );
}

// vq _loadFonts(:491–511) 와 같은 4 등록 — 공용 vqLoadFonts 에는 FlutterTest 별칭이 없어 쓰지 않는다
Future<void> _loadFonts() async {
  Future<ByteData> b(String p) => File(p).readAsBytes().then((x) => ByteData.view(x.buffer));
  for (final fam in const ['NotoSansKR', 'Roboto']) {
    final l = FontLoader(fam)
      ..addFont(b('assets/fonts/NotoSansKR-Regular.ttf'))
      ..addFont(b('assets/fonts/NotoSansKR-Bold.ttf'));
    await l.load();
  }
  final testDefault = FontLoader('FlutterTest')..addFont(b('assets/fonts/NotoSansKR-Regular.ttf'));
  await testDefault.load();
  final icons = FontLoader('MaterialIcons')..addFont(b('C:/Users/kug02/flutter/bin/cache/artifacts/material_fonts/materialicons-regular.otf'));
  await icons.load();
}

final bool _before = Platform.environment['DU_BEFORE_OBSERVE'] == '421';
var _anyFail = false; // 같은 파일 앞 사례 실패 뒤 본문 · 캡처 0(F64-2 와 같은 2층)
final String _manifest = Platform.environment['DUL_MANIFEST'] ?? '(unset)';
const _envKeys = ['DU_BEFORE_OBSERVE', 'DU1_VQ_PHASE', 'DU1_VQ_OUT', 'DU1_VQ_RUN', 'DU1_VQ_DATE', 'DU397_DIAG', 'DU397_MANIFEST', 'DU400_MANIFEST',
  'DU401_MANIFEST', 'DU398_MANIFEST', 'DU406_MANIFEST', 'DU407_MANIFEST', 'DU296_PHASE', 'DUL_MANIFEST'];
final String _envLine = [for (final k in _envKeys) '$k:${Platform.environment[k] ?? '(unset)'}'].join(',');
const _labels = ['검토 중', '확정', '계약 대기'];
const _wj = '\u2060';

void _out(String s) {
  // ignore: avoid_print
  print(s);
}

String _f1(double v) => v.toStringAsFixed(1);
String _rect(Rect r) => '${_f1(r.left)},${_f1(r.top)},${_f1(r.right)},${_f1(r.bottom)}';
String _b64(List<String> xs) => xs.isEmpty ? '-' : base64Url.encode(utf8.encode(xs.join('\n'))).replaceAll('=', '');
String _plainOf(Widget w) => w is RichText ? TextLayout.plain(w.text.toPlainText(includeSemanticsLabels: false)) : '';
Finder _el(Element e) => find.byElementPredicate((x) => identical(x, e), skipOffstage: false);
Rect _rectOf(Element e) {
  final ro = e.renderObject! as RenderBox;
  return MatrixUtils.transformRect(ro.getTransformTo(null), Offset.zero & ro.size);
}

// [r3] 진단용 원좌표(소수 3자리) · 유한 rect 판정
String _r3(Rect r) => [r.left, r.top, r.right, r.bottom].map((v) => v.toStringAsFixed(3)).join(',');
bool _finite(Rect r) => r.left.isFinite && r.top.isFinite && r.right.isFinite && r.bottom.isFinite && r.right >= r.left && r.bottom >= r.top;

bool _inside(Rect outer, Rect r) =>
    r.left >= outer.left - 0.5 && r.top >= outer.top - 0.5 && r.right <= outer.right + 0.5 && r.bottom <= outer.bottom + 0.5;

Element? _nearest(Element e, bool Function(Widget w) p) {
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

List<Element> _richIn(Element root, bool Function(String plain) p) {
  final out = <Element>[];
  void walk(Element x) {
    if (x.widget is RichText && p(_plainOf(x.widget))) out.add(x);
    x.visitChildren(walk);
  }

  root.visitChildren(walk);
  return out;
}

String _code(Color? c) {
  if (c == null) return '-';
  if (c == AppColors.textTertiary) return 'textTertiary';
  if (c == AppColors.textPrimary) return 'textPrimary';
  if (c == AppColors.successDark) return 'successDark';
  if (c == AppColors.warningDark) return 'warningDark';
  return 'other';
}

// 실제 문단 스타일(DefaultTextStyle 병합 뒤) 크기/굵기/색 — 굵기 표기는 DU420 :669 와 같은 replaceAll
String _style(RenderParagraph rp) {
  final st = rp.text.style;
  final fw = st?.fontWeight == null ? '-' : st!.fontWeight.toString().replaceAll('FontWeight.', '');
  return '${st?.fontSize == null ? '-' : _f1(st!.fontSize!)}/$fw/${_code(st?.color)}';
}

// 자간 — 값은 statNumber 가 직접 -0.5, 라벨은 statLabel 이 지정하지 않아 테마 기본 글자 스타일에서 물려받는다(관측)
String _ls(RenderParagraph rp) {
  final v = rp.text.style?.letterSpacing;
  return v == null ? '-' : v.toStringAsFixed(2);
}

/// 라벨 문단의 실제 줄: 글자(UTF-16 한 단위)마다 선택 상자를 구해 같은 top(±0.5)끼리 묶는다.
///   text = 줄마다 TextLayout.plain · 앞뒤 공백 제거 / ext = 줄마다 공백 · U+2060 을 뺀 글자 상자의 전역 좌우 끝 'l~r'.
({List<String> text, List<String> ext}) _lines(RenderParagraph rp) {
  final s = rp.text.toPlainText(includeSemanticsLabels: false);
  final tops = <double>[];
  final buf = <StringBuffer>[];
  final lo = <double>[];
  final hi = <double>[];
  for (var i = 0; i < s.length; i++) {
    final boxes = rp.getBoxesForSelection(TextSelection(baseOffset: i, extentOffset: i + 1));
    if (boxes.isEmpty) continue;
    final b = boxes.first;
    var k = tops.indexWhere((x) => (x - b.top).abs() < 0.5);
    if (k < 0) {
      tops.add(b.top);
      buf.add(StringBuffer());
      lo.add(double.infinity);
      hi.add(double.negativeInfinity);
      k = tops.length - 1;
    }
    buf[k].write(s[i]);
    if (s[i] != ' ' && s[i] != _wj && s[i] != '\u00A0') {
      final gl = rp.localToGlobal(Offset(b.left, b.top)).dx;
      final gr = rp.localToGlobal(Offset(b.right, b.top)).dx;
      if (gl < lo[k]) lo[k] = gl;
      if (gr > hi[k]) hi[k] = gr;
    }
  }
  final order = List<int>.generate(tops.length, (i) => i)..sort((a, b) => tops[a].compareTo(tops[b]));
  final text = <String>[];
  final ext = <String>[];
  for (final i in order) {
    final t = TextLayout.plain(buf[i].toString()).trim();
    if (t.isEmpty) continue;
    text.add(t);
    ext.add(lo[i].isFinite ? '${_f1(lo[i])}~${_f1(hi[i])}' : '-');
  }
  return (text: text, ext: ext);
}

String _w(List<String> lines) => lines.map((x) => x.replaceAll(' ', '_')).join('|');

/// [r2 F78-5] 문단의 글자(공백 · U+2060 · NBSP 제외)마다 선택 상자를 전역 좌표(반올림 전)로 — 조판 잘림 관측용. 잉크 · 조상 clip 은 아니다.
List<Rect> _selBoxes(RenderParagraph rp) {
  final s = rp.text.toPlainText(includeSemanticsLabels: false);
  final out = <Rect>[];
  for (var i = 0; i < s.length; i++) {
    if (s[i] == ' ' || s[i] == _wj || s[i] == '\u00A0') continue;
    for (final b in rp.getBoxesForSelection(TextSelection(baseOffset: i, extentOffset: i + 1))) {
      out.add(Rect.fromPoints(rp.localToGlobal(Offset(b.left, b.top)), rp.localToGlobal(Offset(b.right, b.bottom))));
    }
  }
  return out;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({
        'onboarding_completed_u1': true,
        'tour_completed_user_home': true,
      }));
  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
    await initializeDateFormatting('ko_KR');
  });

  const views = [(id: 'W', w: 390.0, h: 844.0, s: 1.0), (id: 'B', w: 320.0, h: 640.0, s: 2.0)];
  final states = [
    (key: 'NEWL', title: '지원 현황 3칸 라벨 — VQ-01c 앱(새 확정 긴 이름 1건 · 약관 현재)', apps: [_longNew('newL')], legal: _cur),
    (key: 'REACKL', title: '지원 현황 3칸 라벨 — H35-B2/H36-B2 앱(새 확정 긴 이름 + 다가오는 확정 · 약관 재동의)', apps: _h35Apps(long: true), legal: _h35Legal),
    (key: 'REACK', title: '지원 현황 3칸 라벨 — H35-A 앱(새 확정 + 다가오는 확정 · 약관 재동의)', apps: _h35Apps(), legal: _h35Legal),
  ];
  for (final v in views) {
    for (final st in states) {
      testWidgets('S080CA-${v.id}-${st.key} ${st.title}', (t) async {
        if (_anyFail) fail('앞 사례 실패 — 이 사례 본문 실행 0 · 캡처 0');
        SemanticsHandle? sem; // [repair r1] 해제는 아래 finally — 시험 끝 검증 전(tearDown 은 늦다 · run1 TB 원실패)
        try {
          final tok = 'S080CA-${v.id}-${st.key}';
          final mode = _before ? 'before' : 'strict';
          _out('D421 $tok begin mode=$mode phase=${Platform.environment['DU1_VQ_PHASE'] ?? '(unset)'} env=$_envLine manifest=$_manifest');
          await t.runAsync(_loadFonts);
          sem = t.ensureSemantics();
          final overflows = <String>[];
          final fwErrors = <String>[];
          final prev = FlutterError.onError;
          FlutterError.onError = (d) {
            final m = d.exceptionAsString();
            if (m.contains('overflowed')) {
              overflows.add(m.split('\n').first);
            } else {
              fwErrors.add(m.split('\n').first);
              prev?.call(d);
            }
          };
          addTearDown(() => FlutterError.onError = prev);
          t.view.physicalSize = Size(v.w, v.h);
          t.view.devicePixelRatio = 1.0;
          addTearDown(t.view.reset);
          void must(String k, bool ok, [String why = '']) => expect(ok, isTrue, reason: '$tok $k $why');
          final key = GlobalKey();
          await t.pumpWidget(MultiProvider(
            providers: [
              ChangeNotifierProvider<UserProvider>.value(value: _Worker()),
              ChangeNotifierProvider<NotificationProvider>(create: (_) => NotificationProvider()),
            ],
            child: RepaintBoundary(
              key: key,
              child: MaterialApp(
                  debugShowCheckedModeBanner: false,
                  theme: RoleTheme.workerTheme,
                  builder: (ctx, child) => MediaQuery(data: MediaQuery.of(ctx).copyWith(textScaler: TextScaler.linear(v.s)), child: child!),
                  home: UserHomeScreen(reads: _reads(st.apps, legal: st.legal), clock: () => _clock)),
            ),
          ));
          for (var i = 0; i < 25; i++) {
            await t.pump(const Duration(milliseconds: 100));
          }

          // 통계 Row = 세 라벨을 각 정확 1개씩 품은 Row. '확정' 은 최근 지원 배지에도 있어 '검토 중' 후보의 가장 가까운 Row 를 세 라벨로 거른다.
          final seeds = find.byWidgetPredicate((w) => w is RichText && _plainOf(w) == _labels[0], skipOffstage: false).evaluate().toList();
          final rows = <Element>{
            for (final e in seeds)
              if (_nearest(e, (w) => w is Row) case final r?) r,
          }.where((r) => _labels.every((l) => _richIn(r, (p) => p == l).length == 1)).toList();
          must('세 라벨 Row 정확 1', rows.length == 1, 'seeds=${seeds.length} rows=${rows.length}');
          final row = rows.single;
          final card = _nearest(row, (w) => w is Container && w.decoration != null)!;
          // 카드 전체를 본문 표시 영역 가운데로(Row 위 가장자리 정렬은 카드 위 안쪽 여백 12·s 를 표시 영역 밖으로 민다)
          await Scrollable.ensureVisible(card, alignment: 0.5);
          for (var i = 0; i < 5; i++) {
            await t.pump(const Duration(milliseconds: 100));
          }
          // 본문 표시 영역 = 가장 큰 세로 Scrollable(vq _heroReach 와 같은 고름) ∩ 화면
          final all = find.byType(Scrollable);
          final vs = [for (var i = 0; i < all.evaluate().length; i++) all.at(i)]
              .where((f) => t.state<ScrollableState>(f).position.axis == Axis.vertical)
              .toList()
            ..sort((a, b) => t.getRect(b).height.compareTo(t.getRect(a).height));
          must('세로 Scrollable 있음', vs.isNotEmpty);
          final vp = t.getRect(vs.first).intersect(Offset.zero & Size(v.w, v.h));
          final cardR = _rectOf(card);
          final cells = <Rect>[];
          final vals = <Rect>[];
          final labs = <Rect>[];
          final lines = <({List<String> text, List<String> ext})>[];
          final lStyle = <String>[];
          final vStyle = <String>[];
          final lLs = <String>[];
          final vLs = <String>[];
          final vText = <String>[];
          final sl = <String>[];
          final ta = <String>[];
          final keep = <String>[];
          var inCell = true;
          var maxOver = false; // [r2 F78-5] didExceedMaxLines 만 — 조판 잘림 전체가 아니다
          // [r3 · 판정81 A 계약] 선택 상자 b(라벨 3 + 값 3, 비공백 글자) — 반올림 전 전역 logical px.
          //   selInX: 모든 b 의 left/right 를 자기 문단 p · 자기 칸 c 와 각각 직접 ±0.5 · selCardY: 모든 b 의 top/bottom ⊂ 카드 k ±0.5 ·
          //   selIn = selInX && selCardY · selOverY = max_b max(0, p.top−b.top, b.bottom−p.bottom, c.top−b.top, b.bottom−c.bottom)(관측 · 성공 조건 아님) ·
          //   빈 수집 · 비유한 rect 는 실패. r2 의 selIn(X/Y 모두 ⊂ 문단 · 칸)과 다른 계약이다.
          final xBad = <String>[];
          final yBad = <String>[];
          var selOverY = 0.0;
          var selOverAt = '-';
          for (var i = 0; i < 3; i++) {
            final le = _richIn(row, (p) => p == _labels[i]).single;
            final col = _nearest(le, (w) => w is Column)!;
            final valueEls = _richIn(col, (p) => p != _labels[i]);
            must('칸 "${_labels[i]}" 값 문단 정확 1', valueEls.length == 1, '${valueEls.length}');
            final cR = _rectOf(col);
            final vR = _rectOf(valueEls.single);
            final lR = _rectOf(le);
            final lp = le.renderObject! as RenderParagraph;
            final vpara = valueEls.single.renderObject! as RenderParagraph;
            cells.add(cR);
            vals.add(vR);
            labs.add(lR);
            lines.add(_lines(lp));
            lStyle.add(_style(lp));
            vStyle.add(_style(vpara));
            lLs.add(_ls(lp));
            vLs.add(_ls(vpara));
            vText.add(_plainOf(valueEls.single.widget));
            inCell = inCell && _inside(cR, vR) && _inside(cR, lR) && _inside(cardR, cR);
            maxOver = maxOver || lp.didExceedMaxLines || vpara.didExceedMaxLines;
            for (final (nm, pr, para) in [('l', lR, lp), ('v', vR, vpara)]) {
              final id = '$nm${i + 1}';
              final bx = _selBoxes(para);
              if (bx.isEmpty) {
                xBad.add('$id:empty');
                yBad.add('$id:empty');
              }
              if (!_finite(pr) || !_finite(cR) || !_finite(cardR)) {
                xBad.add('$id:ref-invalid');
                yBad.add('$id:ref-invalid');
                continue;
              }
              for (final b in bx) {
                if (!_finite(b)) {
                  xBad.add('$id:box-invalid');
                  yBad.add('$id:box-invalid');
                  continue;
                }
                final raw = _r3(b);
                if (b.left < pr.left - 0.5) xBad.add('$id:x:p.left:$raw/${_r3(pr)}');
                if (b.right > pr.right + 0.5) xBad.add('$id:x:p.right:$raw/${_r3(pr)}');
                if (b.left < cR.left - 0.5) xBad.add('$id:x:c.left:$raw/${_r3(cR)}');
                if (b.right > cR.right + 0.5) xBad.add('$id:x:c.right:$raw/${_r3(cR)}');
                if (b.top < cardR.top - 0.5) yBad.add('$id:y:k.top:$raw/${_r3(cardR)}');
                if (b.bottom > cardR.bottom + 0.5) yBad.add('$id:y:k.bottom:$raw/${_r3(cardR)}');
                for (final (ref, dv) in [
                  ('p.top', pr.top - b.top),
                  ('p.bottom', b.bottom - pr.bottom),
                  ('c.top', cR.top - b.top),
                  ('c.bottom', b.bottom - cR.bottom),
                ]) {
                  if (dv > selOverY) {
                    selOverY = dv;
                    selOverAt = '$id:$ref';
                  }
                }
              }
            }
            final tw = _nearest(le, (w) => w is Text)!.widget as Text;
            sl.add(tw.semanticsLabel == null ? 'null' : (tw.semanticsLabel == _labels[i] ? 'orig' : 'other'));
            ta.add(tw.textAlign == null ? 'null' : tw.textAlign!.name);
            final d = tw.data ?? '';
            keep.add(d == _labels[i] ? 'raw' : (TextLayout.plain(d) == _labels[i] && d.contains(_wj) ? 'wj' : 'other'));
          }
          final selInX = xBad.isEmpty;
          final selCardY = yBad.isEmpty;
          final selIn = selInX && selCardY; // [r3] 새 계약의 selIn — r2 selIn 과 혼용하지 않는다
          // 의미: Row 범위 노드 — 원문 정확 일치 수 · U+2060 포함 수(DU398 :324–327 과 같은 bySemanticsLabel 방식)
          final semN = [
            for (final l in _labels) find.descendant(of: _el(row), matching: find.bySemanticsLabel(l)).evaluate().length,
          ];
          final semWJ = find.descendant(of: _el(row), matching: find.bySemanticsLabel(RegExp(_wj))).evaluate().length;
          final wordOk = [for (var i = 0; i < 3; i++) lines[i].text.join(' ') == _labels[i]].every((x) => x);
          final vis = _inside(vp, cardR);
          _out('D421 $tok stat geo card=${_rect(cardR)} vp=${_rect(vp)} c1=${_rect(cells[0])} c2=${_rect(cells[1])} c3=${_rect(cells[2])} '
              'v1=${_rect(vals[0])} v2=${_rect(vals[1])} v3=${_rect(vals[2])} l1=${_rect(labs[0])} l2=${_rect(labs[1])} l3=${_rect(labs[2])} '
              'inCell=$inCell vis=$vis maxOver=$maxOver selInX=$selInX selCardY=$selCardY selIn=$selIn '
              'selOverY=${selOverY.toStringAsFixed(2)} selOverAt=$selOverAt ovf=${overflows.length}');
          _out('D421 $tok stat text n1=${lines[0].text.length} n2=${lines[1].text.length} n3=${lines[2].text.length} '
              'w1=${_w(lines[0].text)} w2=${_w(lines[1].text)} w3=${_w(lines[2].text)} '
              'e1=${lines[0].ext.join(';')} e2=${lines[1].ext.join(';')} e3=${lines[2].ext.join(';')} wordOk=$wordOk');
          _out('D421 $tok stat sem s1=${semN[0]} s2=${semN[1]} s3=${semN[2]} wj=$semWJ sl=${sl.join(',')} ta=${ta.join(',')} keep=${keep.join(',')}');
          _out('D421 $tok stat style lf=${lStyle.join(',')} lls=${lLs.join(',')} vf=${vStyle.join(',')} vls=${vLs.join(',')} vt=${vText.join(',')}');
          // 공통(두 모드): 칸 · 카드 포함 · 표시 영역 안 · maxLines 초과 0 · [r3] 선택 상자 가로 ⊂ 문단 · 칸 / 세로 ⊂ 카드 · 의미 U+2060 0 · 넘침 0 · 글꼴/크기/색 보존
          must('값 · 라벨 ⊂ 칸 ⊂ 카드(±0.5)', inCell);
          must('카드 ⊂ 본문 표시 영역', vis, '${_rect(cardR)} / ${_rect(vp)}');
          must('maxLines 초과 0', !maxOver);
          must('selOverY 유한 · 0 이상(관측)', selOverY.isFinite && selOverY >= 0, '$selOverY');
          must('selInX 선택 상자 가로 ⊂ 자기 문단 · 자기 칸(각 ±0.5)', selInX, '${xBad.length} ${xBad.take(4).join(' ')}');
          must('selCardY 선택 상자 세로 ⊂ 카드(±0.5)', selCardY, '${yBad.length} ${yBad.take(4).join(' ')}');
          must('selIn = selInX && selCardY', selIn);
          must('의미 U+2060 노드 0', semWJ == 0, '$semWJ');
          must('넘침 0', overflows.isEmpty, overflows.join(' | '));
          must('라벨 문단 12/w500/textTertiary', lStyle.every((x) => x == '12.0/w500/textTertiary'), lStyle.join(','));
          must('값 문단 20/w800/상태색', vStyle.join(',') == '20.0/w800/textPrimary,20.0/w800/successDark,20.0/w800/warningDark', vStyle.join(','));
          must('값 자간 -0.50', vLs.every((x) => x == '-0.50'), vLs.join(','));
          if (_before) {
            // before: 실행 중인 홈이 원 Text(label, style:) 인지 — 위젯 계약만 단언, 줄 · 의미 수는 관측
            must('before 원 Text 계약', sl.every((x) => x == 'null') && ta.every((x) => x == 'null') && keep.every((x) => x == 'raw'),
                '${sl.join(',')} ${ta.join(',')} ${keep.join(',')}');
          } else {
            must('strict 후보 Text 계약(semanticsLabel 원문 · center · 낱말 묶기)',
                sl.every((x) => x == 'orig') && ta.every((x) => x == 'center') && keep.every((x) => x == 'wj'),
                '${sl.join(',')} ${ta.join(',')} ${keep.join(',')}');
            must('세 라벨 낱말 경계(줄을 공백으로 이으면 원문)', wordOk, '${lines.map((l) => _w(l.text)).toList()}');
            must('원문 의미 노드 각 정확 1', semN.every((n) => n == 1), '$semN');
            if (v.id == 'B') {
              must('B 계약 대기 = 두 줄 계약|대기', _w(lines[2].text) == '계약|대기', _w(lines[2].text));
              must('B 검토 중 · 확정 = 한 줄', lines[0].text.length == 1 && lines[1].text.length == 1, '${_w(lines[0].text)} ${_w(lines[1].text)}');
            } else {
              must('W 세 라벨 한 줄', lines.every((l) => l.text.length == 1), '${lines.map((l) => _w(l.text)).toList()}');
            }
          }
          must('shot 직전 미처리 framework 예외 0', fwErrors.isEmpty, '$fwErrors');
          _out('D421 $tok shot 1stat ovf=${overflows.length}');
          await vqCapture(t, key, '${tok}_1stat', conditions: {
            'viewport': '${v.w.toInt()}x${v.h.toInt()}', 'textScaler': v.s, 'run': vqRun, 'manifest': _manifest, 'mode': mode, 'fixture': st.key,
            'state': 'stat-row-visible',
          });
          final exc = t.takeException();
          _out('D421 $tok done state=${st.key} mode=$mode captures=1 overflows=${overflows.length} exc=${exc != null} ovfRaw=${_b64(overflows)}');
          must('끝 예외 0', exc == null, '$exc');
        } catch (e) {
          _anyFail = true;
          rethrow;
        } finally {
          sem?.dispose(); // [repair r1] _verifySemanticsHandlesWereDisposed 전에 해제
        }
      });
    }
  }
}
