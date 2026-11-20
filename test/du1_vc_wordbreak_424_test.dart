// [DU424 · 소급 셀(사용자 11-17) · 표시만] V-c 지원자 홈 '내 지원 현황' 3칸 숫자 윗선 + 시작·복구 버튼/지역명 낱말 줄바꿈.
//   before = 현재 A(홈 141bf0a6 · main cea5554f) / strict = 후보(홈 Row 위 정렬 · main keepWords/identity 3곳).
//   기본 skip — lkit 단계 env 정확 조합(TB before/du424-tb/DU_BEFORE_OBSERVE=424 · TA after/du424-ta/없음)일 때만 돈다.
//   HOMESTAT: DU421 시험(e161ac85)의 REACKL 앱 · 약관 재동의 · 고정 시계(2026-11-08 KST 10:00) · 같은 렌더 트리.
//     통계 카드를 가운데로 보이게 한 같은 프레임에서 세 숫자 문단 top · 두 구분선 rect · 라벨 줄(C1-a 낱말 경계 보존)을 잰다.
//   ROUTEERR · UNSELECTED · SELECTED: DU422 시험(17542fe3)과 같은 AuthWrapper host · _FakeCore · debugPrint 단일 주입(ROUTEERR).
//     버튼 라벨 · 지역명 문단의 실제 줄(글자 선택 상자 top 묶음)을 구하고, 줄바꿈이 공백 · U+200B(identity 가운데)에서만 일어났는지 본다.
//   출력 줄: 'D424 <tok> <kind> [<sub>] k=v …' — 값 공백 0(공백 → '_' · 줄 구분 '|').
// ignore_for_file: depend_on_referenced_packages
import 'dart:convert';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ALfit/main.dart' show AuthWrapper;
import 'package:ALfit/models/core/application_model.dart';
import 'package:ALfit/models/core/business_model.dart';
import 'package:ALfit/models/core/legal_readiness.dart';
import 'package:ALfit/models/core/renewal_proposal_model.dart';
import 'package:ALfit/models/core/slot_model.dart';
import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/models/core/user_region.dart';
import 'package:ALfit/providers/notification_provider.dart';
import 'package:ALfit/providers/theme_provider.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/screens/user/user_home_reads.dart';
import 'package:ALfit/screens/user/user_home_screen.dart';
import 'package:ALfit/services/payroll_correction_service.dart';
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

/// 홈 지원자 대역(DU421 :78–94 와 같은 게터)
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

/// AuthWrapper 대역(DU422 :66–84 와 같음) — 로그아웃은 즉시 완료.
class _Prov extends UserProvider {
  int signOutCalls = 0;
  @override
  Future<void> signOut() {
    signOutCalls++;
    return Future<void>.value();
  }
}

// DU421 :96–141 과 같은 고정값 · 앱 목록 · 읽기 경계
final DateTime _clock = DateTime.utc(2026, 11, 8, 1);
final DateTime _today = FormatHelper.toKstDate(_clock);
DateTime _day(int o) => _today.add(Duration(days: o));
ApplicationModel _short(String id, int dayOffset, {DateTime? confirmedAt, String type = '피킹', String start = '09:00', String end = '18:00'}) =>
    ApplicationModel(
      id: id, toId: 'to_$id', uid: 'u1', businessId: 'biz1', businessName: '강남 물류센터', toTitle: '단기 공고',
      status: AppStatus.confirmed, selectedWorkType: type, startTime: start, endTime: end, wage: 12000, wageType: 'hourly',
      workDate: _day(dayOffset), confirmedAt: confirmedAt, appliedAt: _day(-3));
ApplicationModel _longNew(String id) => ApplicationModel(
    id: id, toId: 'to_$id', uid: 'u1', businessId: 'biz1', businessName: '[QA] 아주 긴 이름의 강남 물류센터 평택 2공장',
    toTitle: '단기 공고', status: AppStatus.confirmed, selectedWorkType: '냉장 피킹·검수 보조', startTime: '09:00', endTime: '18:00',
    wage: 12000, wageType: 'hourly', workDate: _day(3), confirmedAt: _clock.subtract(const Duration(hours: 2)), appliedAt: _day(-3));
List<ApplicationModel> _reackl() => [_longNew('new1'), _short('next2', 5, type: '상하차', start: '13:00', end: '22:00')];
const _h35Legal = LegalReadiness(status: LegalReadinessStatus.reconsentRequired, reconsentRequired: ['service_terms']);
UserHomeReads _reads(List<ApplicationModel> apps) {
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
    legalReadiness: () async => _h35Legal,
  );
}

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

final bool _before = Platform.environment['DU_BEFORE_OBSERVE'] == '424';
final Map<String, String> _env = Platform.environment;
final bool _optIn =
    (_env['DU1_VQ_PHASE'] == 'before' && _env['DU1_VQ_RUN'] == 'du424-tb' && _env['DU_BEFORE_OBSERVE'] == '424') ||
        (_env['DU1_VQ_PHASE'] == 'after' && _env['DU1_VQ_RUN'] == 'du424-ta' && _env['DU_BEFORE_OBSERVE'] == null);
var _anyFail = false;
final String _manifest = Platform.environment['DUL_MANIFEST'] ?? '(unset)';
const _envKeys = ['DU_BEFORE_OBSERVE', 'DU1_VQ_PHASE', 'DU1_VQ_OUT', 'DU1_VQ_RUN', 'DU1_VQ_DATE', 'DU397_DIAG', 'DU397_MANIFEST', 'DU400_MANIFEST',
  'DU401_MANIFEST', 'DU398_MANIFEST', 'DU406_MANIFEST', 'DU407_MANIFEST', 'DU296_PHASE', 'DUL_MANIFEST'];
final String _envLine = [for (final k in _envKeys) '$k:${Platform.environment[k] ?? '(unset)'}'].join(',');

const _labels = ['검토 중', '확정', '계약 대기'];
const _marker = '🔄 USER homeRegion 없음 → 복구 화면 (강제)';
const _injectMsg = 'DU424_INJECT 역할 분기 시험 주입 예외';
const _routeCta = '로그아웃하고 다시 시도';
const _regionTitle = '주로 일할 지역을 알려주세요';
const _hint = '지역 선택하기';
const _save = '저장하고 시작하기';
const _sejong = '세종특별자치시';

void _out(String s) {
  // ignore: avoid_print
  print(s);
}

String _f1(double v) => v.toStringAsFixed(1);
String _rect(Rect r) => '${_f1(r.left)},${_f1(r.top)},${_f1(r.right)},${_f1(r.bottom)}';
String _plainOf(Widget w) => w is RichText ? TextLayout.plain(w.text.toPlainText(includeSemanticsLabels: false)) : '';
Finder _rich(String plain) => find.byWidgetPredicate((w) => w is RichText && _plainOf(w) == plain);
Rect _rectOfEl(Element e) {
  final ro = e.renderObject! as RenderBox;
  return MatrixUtils.transformRect(ro.getTransformTo(null), Offset.zero & ro.size);
}

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

/// 문단의 실제 줄 — 글자(UTF-16 한 단위)마다 선택 상자를 구해 같은 top(±0.5)끼리 묶고 위에서부터 번호를 매긴다.
///   상자가 없는 글자(WORD JOINER · ZERO WIDTH SPACE 등)는 앞 글자의 줄에 붙인다.
///   ok = 줄이 바뀌는 모든 지점(새 줄 첫 상자 글자 i)에서 s[i-1] 이 공백 · ZERO WIDTH SPACE 이거나 s[i] 가 공백이다
///   (낱말 경계 · identity 가운데에서만 줄바꿈 — 줄 끝 공백이 어느 줄 상자로 잡히든 같은 판정).
final String _zwsp = String.fromCharCode(0x200B);
({List<String> lines, bool ok}) _breaks(RenderParagraph rp) {
  final s = rp.text.toPlainText(includeSemanticsLabels: false);
  final tops = <double>[];
  final lineOf = List<int>.filled(s.length, -1);
  for (var i = 0; i < s.length; i++) {
    final boxes = rp.getBoxesForSelection(TextSelection(baseOffset: i, extentOffset: i + 1));
    if (boxes.isEmpty) continue;
    final top = boxes.first.top;
    var k = tops.indexWhere((x) => (x - top).abs() < 0.5);
    if (k < 0) {
      tops.add(top);
      k = tops.length - 1;
    }
    lineOf[i] = k;
  }
  if (tops.isEmpty) return (lines: const <String>[], ok: true);
  final order = List<int>.generate(tops.length, (i) => i)..sort((a, b) => tops[a].compareTo(tops[b]));
  final rank = List<int>.filled(tops.length, 0);
  for (var r = 0; r < order.length; r++) {
    rank[order[r]] = r;
  }
  final buf = List<StringBuffer>.generate(tops.length, (_) => StringBuffer());
  var ok = true;
  var prevLine = -1;
  var curLine = 0;
  for (var i = 0; i < s.length; i++) {
    if (lineOf[i] >= 0) {
      final ln = rank[lineOf[i]];
      if (prevLine >= 0 && ln != prevLine) {
        final b = i > 0 ? s[i - 1] : '';
        if (!(b == ' ' || b == _zwsp || s[i] == ' ')) ok = false;
      }
      prevLine = ln;
      curLine = ln;
    }
    buf[curLine].write(s[i]);
  }
  return (lines: [for (final b in buf) TextLayout.plain(b.toString()).trim()], ok: ok);
}

String _w(List<String> lines) => lines.map((x) => x.replaceAll(' ', '_')).join('|');

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
  const states = [
    (key: 'HOMESTAT', title: '지원자 홈 내 지원 현황 3칸 — REACKL 앱(긴 이름 · 약관 재동의) · 숫자 윗선 · 구분선 · 라벨 줄'),
    (key: 'ROUTEERR', title: '역할 분기 catch — 로그아웃 버튼 라벨 줄바꿈'),
    (key: 'UNSELECTED', title: '지역 설정 복구 미선택 — 저장 버튼 라벨 줄바꿈'),
    (key: 'SELECTED', title: '지역 설정 복구 세종특별자치시 선택 — 지역명 · 저장 버튼 라벨 줄바꿈'),
  ];
  for (final v in views) {
    for (final st in states) {
      testWidgets('S424VW-${v.id}-${st.key} ${st.title}', (t) async {
        if (_anyFail) fail('앞 사례 실패 — 이 사례 본문 실행 0 · 캡처 0');
        SemanticsHandle? sem;
        final origPrint = debugPrint;
        try {
          final tok = 'S424VW-${v.id}-${st.key}';
          final mode = _before ? 'before' : 'strict';
          _out('D424 $tok begin mode=$mode phase=${Platform.environment['DU1_VQ_PHASE'] ?? '(unset)'} env=$_envLine manifest=$_manifest');
          await t.runAsync(_loadFonts);
          sem = t.ensureSemantics();
          var markerSeen = 0, injected = 0;
          debugPrint = (String? m, {int? wrapWidth}) {
            origPrint(m, wrapWidth: wrapWidth);
            if (m == _marker) {
              markerSeen++;
              if (st.key == 'ROUTEERR' && injected == 0) {
                injected = 1;
                throw StateError(_injectMsg);
              }
            }
          };
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
          Widget app(Widget home, List<ChangeNotifierProvider> providers) => MultiProvider(
                providers: providers,
                child: RepaintBoundary(
                  key: key,
                  child: MaterialApp(
                      debugShowCheckedModeBanner: false,
                      theme: RoleTheme.workerTheme,
                      builder: (ctx, child) => MediaQuery(data: MediaQuery.of(ctx).copyWith(textScaler: TextScaler.linear(v.s)), child: child!),
                      home: home),
                ),
              );
          var capture = '1main';
          if (st.key == 'HOMESTAT') {
            // ── V-c ───────────────────────────────────────────
            capture = '1stat';
            await t.pumpWidget(app(UserHomeScreen(reads: _reads(_reackl()), clock: () => _clock), [
              ChangeNotifierProvider<UserProvider>.value(value: _Worker()),
              ChangeNotifierProvider<NotificationProvider>(create: (_) => NotificationProvider()),
            ]));
            for (var i = 0; i < 25; i++) {
              await t.pump(const Duration(milliseconds: 100));
            }
            final seeds = find.byWidgetPredicate((w) => w is RichText && _plainOf(w) == _labels[0], skipOffstage: false).evaluate().toList();
            final rows = <Element>{
              for (final e in seeds)
                if (_nearest(e, (w) => w is Row) case final r?) r,
            }.where((r) => _labels.every((l) => _richIn(r, (p) => p == l).length == 1)).toList();
            must('세 라벨 Row 정확 1', rows.length == 1, '${rows.length}');
            final row = rows.single;
            final card = _nearest(row, (w) => w is Container && w.decoration != null)!;
            await Scrollable.ensureVisible(card, alignment: 0.5);
            for (var i = 0; i < 5; i++) {
              await t.pump(const Duration(milliseconds: 100));
            }
            final cardR = _rectOfEl(card);
            final tops = <double>[];
            var inCell = true;
            var labOk = true;
            final labLines = <String>[];
            for (var i = 0; i < 3; i++) {
              final le = _richIn(row, (p) => p == _labels[i]).single;
              final col = _nearest(le, (w) => w is Column)!;
              final valueEls = _richIn(col, (p) => p != _labels[i]);
              must('칸 "${_labels[i]}" 값 문단 정확 1', valueEls.length == 1, '${valueEls.length}');
              final cR = _rectOfEl(col);
              final vR = _rectOfEl(valueEls.single);
              final lR = _rectOfEl(le);
              tops.add(vR.top);
              inCell = inCell && _inside(cR, vR) && _inside(cR, lR) && _inside(cardR, cR);
              final br = _breaks(le.renderObject! as RenderParagraph);
              labOk = labOk && br.ok;
              labLines.add(_w(br.lines));
            }
            final divs = <Element>[];
            void walk(Element x) {
              final w = x.widget;
              if (w is Container && w.constraints?.maxWidth == 1.0) divs.add(x);
              x.visitChildren(walk);
            }

            row.visitChildren(walk);
            must('구분선 정확 2', divs.length == 2, '${divs.length}');
            final d1 = _rectOfEl(divs[0]), d2 = _rectOfEl(divs[1]);
            final spread = tops.reduce((a, b) => a > b ? a : b) - tops.reduce((a, b) => a < b ? a : b);
            final same = spread <= 0.5;
            _out('D424 $tok stat top v=${tops.map(_f1).join(',')} spread=${_f1(spread)} same=$same d1=${_rect(d1)} d2=${_rect(d2)} card=${_rect(cardR)} inCell=$inCell');
            _out('D424 $tok stat lab l3=${labLines[2]} ok=$labOk');
            must('숫자 · 라벨 칸 안 · 카드 안', inCell);
            must('C1-a 라벨 낱말 경계 보존', labOk, labLines.join(' / '));
            if (!_before) must('strict 세 숫자 윗선 같음(±0.5)', same, tops.map(_f1).join(','));
          } else {
            // ── 시작·복구 줄바꿈 ─────────────────────────────────
            final prov = _Prov()..debugSetCurrentUser(UserModel(
                uid: 'u1', username: 'u1', name: '김근로', email: 'u1@alfit.local', role: UserRole.USER,
                accountStatus: 'active', passVerifiedAt: DateTime.utc(2026, 10, 1)));
            final theme = ThemeProvider()..setRole('USER');
            await t.pumpWidget(app(const AuthWrapper(), [
              ChangeNotifierProvider<UserProvider>.value(value: prov),
              ChangeNotifierProvider<ThemeProvider>.value(value: theme),
            ]));
            final isRoute = st.key == 'ROUTEERR';
            for (var i = 0; i < 30; i++) {
              await t.pump(const Duration(milliseconds: 16));
              if ((isRoute ? _rich(_routeCta) : _rich(_regionTitle)).evaluate().isNotEmpty) break;
            }
            must('대상 화면 도달', (isRoute ? _rich(_routeCta) : _rich(_regionTitle)).evaluate().length == 1);
            if (isRoute) {
              _out('D424 $tok route inj injected=$injected marker=$markerSeen catch=${_rich(_routeCta).evaluate().length == 1}');
              must('주입 1 · 표지 1 · catch', injected == 1 && markerSeen == 1);
              final btn = find.ancestor(of: _rich(_routeCta), matching: find.byType(ElevatedButton));
              await t.ensureVisible(btn);
              await t.pump();
              final br = _breaks(t.renderObject(_rich(_routeCta)) as RenderParagraph);
              _out('D424 $tok wb cta lines=${_w(br.lines)} ok=${br.ok}');
              if (!_before) must('strict 버튼 라벨 낱말 경계', br.ok, _w(br.lines));
            } else {
              if (st.key == 'SELECTED') {
                await t.ensureVisible(_rich(_hint));
                await t.pump();
                await t.tap(_rich(_hint));
                await t.pumpAndSettle();
                final item = _rich(_sejong);
                await t.scrollUntilVisible(item, 120, scrollable: find.byType(Scrollable).last);
                await t.pumpAndSettle();
                must('시트 세종특별자치시 항목 1', item.evaluate().length == 1);
                await t.tap(item);
                await t.pumpAndSettle();
                must('선택 반영', _rich('$_sejong $_sejong').evaluate().length == 1);
              }
              _out('D424 $tok region nav region=true catch=${_rich(_routeCta).evaluate().isNotEmpty} injected=$injected');
              must('주입 0 · catch 아님', injected == 0 && _rich(_routeCta).evaluate().isEmpty);
              final saveF = find.ancestor(of: _rich(_save), matching: find.byType(ElevatedButton));
              await t.ensureVisible(saveF);
              await t.pump();
              final sb = _breaks(t.renderObject(_rich(_save)) as RenderParagraph);
              _out('D424 $tok wb save lines=${_w(sb.lines)} ok=${sb.ok}');
              if (!_before) must('strict 저장 라벨 낱말 경계', sb.ok, _w(sb.lines));
              if (st.key == 'SELECTED') {
                final rf = _rich('$_sejong $_sejong');
                await t.ensureVisible(rf);
                await t.pump();
                final rb = _breaks(t.renderObject(rf) as RenderParagraph);
                _out('D424 $tok wb region lines=${_w(rb.lines)} ok=${rb.ok}');
                if (!_before) must('strict 지역명 낱말 · 가운데 경계', rb.ok, _w(rb.lines));
              }
            }
          }
          if (!_before) must('strict 넘침 0', overflows.isEmpty, overflows.join(' | '));
          must('shot 직전 미처리 framework 예외 0', fwErrors.isEmpty, '$fwErrors');
          _out('D424 $tok shot $capture ovf=${overflows.length}');
          await vqCapture(t, key, '${tok}_$capture', conditions: {
            'viewport': '${v.w.toInt()}x${v.h.toInt()}', 'textScaler': v.s, 'run': vqRun, 'manifest': _manifest, 'mode': mode, 'fixture': st.key,
            'state': st.key == 'HOMESTAT' ? 'stat-row-visible' : 'label-visible',
          });
          final exc = t.takeException();
          _out('D424 $tok done state=${st.key} mode=$mode captures=1 overflows=${overflows.length} exc=${exc != null} ovfRaw=${overflows.isEmpty ? '-' : base64Url.encode(utf8.encode(overflows.join('\n'))).replaceAll('=', '')}');
          must('끝 예외 0', exc == null, '$exc');
        } catch (e) {
          _anyFail = true;
          rethrow;
        } finally {
          debugPrint = origPrint;
          sem?.dispose();
        }
      }, skip: !_optIn);
    }
  }
}
