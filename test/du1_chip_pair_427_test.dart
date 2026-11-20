// [DU427 · 소급 셀 · 표시만] 근태 칩 · 배지 바탕 = 앱 기준 상태 짝 Bg 토큰(StatusBadge 와 같은 짝) · S028 목록 글자 줄바꿈 경계.
//   before = 현재 A(목록 7767bf63 · 월 상세 c9104a57 · CountChip 101d46bb) / strict = 수리 r1 후보(목록 e970256c · 월 상세 324bce86 · CountChip 2cd62e62).
//   [수리 r1] run1 후보(목록 1e7bbbbb)의 칩 글자 keepWords 는 뺐다 — 칩 줄바꿈 잔여는 뷰별 정확 기대로 고정한다(아래 '칩 줄바꿈 뷰별 정확').
//   기본 skip — lkit 단계 env 정확 조합(TB before/du427-tb/DU_BEFORE_OBSERVE=427 · TA after/du427-ta/없음)일 때만 돈다.
//   장면: 뷰 W 390x844@1.0 · B 320x640@2.0 × LIST(5행) · EMPTY · MONTH = 공개 6. 탭 · 정정 · 조회 흐름은 하지 않는다(표시만).
//   줄 판정(DU424 _breaks 와 같은 식): 문단마다 글자 선택 상자 top 으로 실제 줄을 묶는다.
//     ok = 줄이 바뀌는 모든 곳에서 앞 글자가 공백 · ZWSP(또는 새 줄 첫 글자가 공백) / lead = 둘째 줄부터 '·' 로 시작하는 줄 수.
//   문단 높이: 배정 높이 ≥ 같은 폭 필요 높이(getMaxIntrinsicHeight) − 0.5 · didExceedMaxLines 0. 조상 clip · 실제 잉크 · 기기 낭독은 계측 밖.
//   B before 는 알려진 결함(범위 · 머리줄 '·' 시작, 칩 · 시각 낱말 중간 끊김)을 이 판정기가 잡는지 음성 기대로 단언한다.
// ignore_for_file: depend_on_referenced_packages
import 'dart:convert';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';

import 'package:ALfit/models/core/attendance_model.dart';
import 'package:ALfit/models/core/business_member_model.dart';
import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/providers/notification_provider.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/screens/business_admin/admin_month_detail_screen.dart';
import 'package:ALfit/screens/business_admin/stats_attendance_list_screen.dart';
import 'package:ALfit/services/admin_stats_service.dart';
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

/// stats_to_attendance_link_test :39–61 과 같은 관리자 대역(권한 모두 허용)
class _Provider extends UserProvider {
  @override
  UserModel? get currentUser => UserModel(uid: 'admin1', username: 'admin1', name: '김관리', email: 'a@alfit.local',
      role: UserRole.BUSINESS_ADMIN, managedBusinessIds: const ['biz1']);
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

DateTime _kst(int d) => DateTime.utc(2026, 10, d).subtract(const Duration(hours: 9));
AttendanceModel _att(String id, String uid, int day, String status, {String wage = 'pending', DateTime? inAt}) => AttendanceModel(
    id: id, applicationId: 'app_$id', userId: uid, businessId: 'biz1', businessName: '평택 센터', workDate: _kst(day),
    workType: '분류', status: status, wageStatus: wage, checkInAt: inAt, createdAt: DateTime.utc(2026, 10, 1));

final _rows = <AttendanceModel>[
  _att('a1', 'abs', 5, AttendanceModel.statusAbsent),
  _att('u1', 'unk', 6, AttendanceModel.statusUnconfirmed),
  _att('m1', 'miss', 7, AttendanceModel.statusMissedCheckout, inAt: _kst(7).add(const Duration(hours: 9))),
  _att('l1', 'late', 8, AttendanceModel.statusLate, inAt: _kst(8).add(const Duration(hours: 9, minutes: 12))),
  _att('p1', 'ok', 9, AttendanceModel.statusPresent, wage: AttendanceModel.wageConfirmed, inAt: _kst(9).add(const Duration(hours: 9))),
];
const _info = {
  'abs': UserInfo(name: '합성 결근', personNo: 'P-501'),
  'unk': UserInfo(name: '합성 확인필요', personNo: 'P-502'),
  'miss': UserInfo(name: '합성 퇴근미확인', personNo: 'P-503'),
  'late': UserInfo(name: '합성 지각', personNo: 'P-504'),
  'ok': UserInfo(name: '합성 정상', personNo: 'P-505'),
};
const _scope = '2026년 10월 · 평택 센터 · 전체';
const _empty = '조건에 맞는 근무가 없어요';

class _FakeStats extends AdminStatsService {
  @override
  Future<List<BusinessOption>> getBusinessOptions(List<String> ids) async => const [BusinessOption(id: 'biz1', name: '평택 센터')];
  @override
  Future<MonthDetailData> getMonthDetail({required List<String> businessIds, String? filterBusinessId, required int year, required int month}) async =>
      AdminStatsService.buildMonthDetail(year: 2026, month: 10, attendance: _rows, infoMap: _info);
  @override
  Future<StatsAttendanceSnapshot?> getAttendanceSnapshot({required List<String> businessIds, String? filterBusinessId, required int year, int? month}) async =>
      StatsAttendanceSnapshot(records: _rows, userInfo: _info);
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

final bool _before = Platform.environment['DU_BEFORE_OBSERVE'] == '427';
final Map<String, String> _env = Platform.environment;
final bool _optIn =
    (_env['DU1_VQ_PHASE'] == 'before' && _env['DU1_VQ_RUN'] == 'du427-tb' && _env['DU_BEFORE_OBSERVE'] == '427') ||
        (_env['DU1_VQ_PHASE'] == 'after' && _env['DU1_VQ_RUN'] == 'du427-ta' && _env['DU_BEFORE_OBSERVE'] == null);
var _anyFail = false;
final String _manifest = Platform.environment['DUL_MANIFEST'] ?? '(unset)';
const _envKeys = ['DU_BEFORE_OBSERVE', 'DU1_VQ_PHASE', 'DU1_VQ_OUT', 'DU1_VQ_RUN', 'DU1_VQ_DATE', 'DU397_DIAG', 'DU397_MANIFEST', 'DU400_MANIFEST',
  'DU401_MANIFEST', 'DU398_MANIFEST', 'DU406_MANIFEST', 'DU407_MANIFEST', 'DU296_PHASE', 'DUL_MANIFEST'];
final String _envLine = [for (final k in _envKeys) '$k:${Platform.environment[k] ?? '(unset)'}'].join(',');

void _out(String s) {
  // ignore: avoid_print
  print(s);
}

String _plainOf(Widget w) => w is RichText ? TextLayout.plain(w.text.toPlainText(includeSemanticsLabels: false)) : '';

const _tokens = <String, Color>{
  'warningDark': AppColors.warningDark, 'textSecondary': AppColors.textSecondary, 'purple': AppColors.purple,
  'errorDark': AppColors.errorDark, 'successDark': AppColors.successDark,
  'warningBg': AppColors.warningBg, 'grey200': AppColors.grey200, 'purpleBg': AppColors.purpleBg, 'errorBg': AppColors.errorBg,
  'successBg': AppColors.successBg, 'grey100': AppColors.grey100,
};
String _tok(Color? c) {
  if (c == null) return 'null';
  for (final e in _tokens.entries) {
    if (e.value.toARGB32() == c.toARGB32()) return e.key;
  }
  return 'x${c.toARGB32().toRadixString(16)}';
}

/// 바탕 이름 — 글자색의 12% 와 같으면 'tint12', 아니면 토큰 이름.
String _bgTok(Color? bg, Color? fg) {
  if (bg != null && fg != null && bg.toARGB32() == fg.withValues(alpha: 0.12).toARGB32()) return 'tint12';
  return _tok(bg);
}

/// 문단의 실제 줄(DU424 :199–242 와 같은 식) — 글자마다 선택 상자를 구해 같은 top(±0.5)끼리 묶는다.
final String _zwsp = String.fromCharCode(0x200B);
({List<String> lines, bool ok, int lead}) _breaks(RenderParagraph rp) {
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
  if (tops.isEmpty) return (lines: const <String>[], ok: true, lead: 0);
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
  final lines = [for (final b in buf) TextLayout.plain(b.toString()).trim()];
  var lead = 0;
  for (var j = 1; j < lines.length; j++) {
    if (lines[j].startsWith('·')) lead++;
  }
  return (lines: lines, ok: ok, lead: lead);
}

/// 배정 높이가 같은 폭의 필요 높이를 담는가(문단 자체 잘림 0) · maxLines 초과 0.
bool _paraOk(RenderParagraph rp) => !rp.didExceedMaxLines && rp.size.height + 0.5 >= rp.getMaxIntrinsicHeight(rp.size.width);

String _w(List<String> lines) => lines.map((x) => x.replaceAll(' ', '_')).join('|');

void main() {
  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
  });

  const views = [(id: 'W', w: 390.0, h: 844.0, s: 1.0), (id: 'B', w: 320.0, h: 640.0, s: 2.0)];
  const states = [
    (key: 'LIST', title: '근태 통계 목록 5행 — 칩 글자 · 바탕 짝 · 범위 · 머리줄 · 칩 · 시각 줄바꿈 경계'),
    (key: 'EMPTY', title: '근태 통계 목록 0행 — 범위 · 빈 안내 줄바꿈 경계'),
    (key: 'MONTH', title: '월 상세 직원 배지 — 글자 · 바탕 짝'),
  ];
  for (final v in views) {
    for (final st in states) {
      testWidgets('S028CP-${v.id}-${st.key} ${st.title}', (t) async {
        if (_anyFail) fail('앞 사례 실패 — 이 사례 본문 실행 0 · 캡처 0');
        try {
          final tok = 'S028CP-${v.id}-${st.key}';
          final mode = _before ? 'before' : 'strict';
          _out('D427 $tok begin mode=$mode phase=${Platform.environment['DU1_VQ_PHASE'] ?? '(unset)'} env=$_envLine manifest=$_manifest');
          await t.runAsync(_loadFonts);
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
          final isMonth = st.key == 'MONTH';
          final list = st.key == 'LIST' ? _rows : const <AttendanceModel>[];
          await t.pumpWidget(MultiProvider(
            providers: [
              ChangeNotifierProvider<UserProvider>(create: (_) => _Provider()),
              ChangeNotifierProvider<NotificationProvider>(create: (_) => NotificationProvider()),
            ],
            child: RepaintBoundary(
              key: key,
              child: MaterialApp(
                debugShowCheckedModeBanner: false,
                theme: RoleTheme.businessAdminTheme,
                builder: (ctx, child) => MediaQuery(data: MediaQuery.of(ctx).copyWith(textScaler: TextScaler.linear(v.s)), child: child!),
                home: isMonth
                    ? AdminMonthDetailScreen(
                        businessIds: const ['biz1'], filterBusinessId: null, year: 2026, month: 10,
                        businesses: const [BusinessOption(id: 'biz1', name: '평택 센터')], service: _FakeStats(),
                        debugOpenAttendance: (_) async => false)
                    : StatsAttendanceListScreen(
                        title: '근태 내역', scopeLabel: _scope, load: () async => null, matches: (_) => true,
                        initial: StatsAttendanceSnapshot(records: list, userInfo: _info)),
              ),
            ),
          ));
          for (var i = 0; i < 20; i++) {
            await t.pump(const Duration(milliseconds: 100));
          }
          // 본문 세로 Scrollable 중 가장 큰 것(DU421 :368–372 와 같은 고름)
          final all = find.byType(Scrollable);
          final vs = [for (var i = 0; i < all.evaluate().length; i++) all.at(i)]
              .where((f) => t.state<ScrollableState>(f).position.axis == Axis.vertical)
              .toList()
            ..sort((a, b) => t.getRect(b).height.compareTo(t.getRect(a).height));
          must('세로 Scrollable 있음', vs.isNotEmpty);
          final scrollable = vs.first;
          // 대상은 skipOffstage:false 로 찾고, 매번 맨 위로 되돌린 뒤 아래로 굴려 닿는다(순서 · 캐시 범위에 기대지 않는다).
          Future<Finder> reach(Finder f) async {
            t.state<ScrollableState>(scrollable).position.jumpTo(0);
            await t.pump();
            await t.scrollUntilVisible(f, 80, scrollable: scrollable);
            await t.pump();
            return f;
          }

          var shots = 0;
          Future<void> shot(String sub, String state) async {
            _out('D427 $tok shot $sub ovf=${overflows.length}');
            await vqCapture(t, key, '${tok}_$sub', conditions: {
              'viewport': '${v.w.toInt()}x${v.h.toInt()}', 'textScaler': v.s, 'run': vqRun, 'manifest': _manifest, 'mode': mode, 'fixture': st.key,
              'state': state,
            });
            shots++;
          }

          Finder richIn(Finder host, bool Function(String p) p) =>
              find.descendant(of: host, matching: find.byWidgetPredicate((w) => w is RichText && p(_plainOf(w)), skipOffstage: false), skipOffstage: false);
          Finder chipsIn(Finder host) => find.descendant(
              of: host,
              matching: find.byWidgetPredicate(
                  (w) => w is Container && w.decoration is BoxDecoration && (w.decoration! as BoxDecoration).borderRadius == BorderRadius.circular(4),
                  skipOffstage: false),
              skipOffstage: false);
          // 칩 Container 하나 → (글자색, 바탕, 글자 문단)
          ({String fg, String bg, RenderParagraph rp}) chipAt(Element el) {
            final c = el.widget as Container;
            final rf = find.descendant(of: find.byElementPredicate((e) => identical(e, el)), matching: find.byType(RichText), skipOffstage: false).first;
            final fg = (t.widget(rf) as RichText).text.style?.color;
            return (fg: _tok(fg), bg: _bgTok((c.decoration! as BoxDecoration).color, fg), rp: t.renderObject(rf) as RenderParagraph);
          }

          var paraOk = true;
          var paraN = 0;
          ({List<String> lines, bool ok, int lead}) judge(RenderParagraph rp) {
            paraN++;
            paraOk = paraOk && _paraOk(rp);
            return _breaks(rp);
          }

          if (st.key == 'LIST') {
            await shot('1main', 'list-top');
            final sc = judge(t.renderObject(richIn(find.byType(StatsAttendanceListScreen), (p) => p == _scope).first) as RenderParagraph);
            final fg = <String, String>{}, bg = <String, String>{};
            var headOk = true, chipOk = true, timesOk = true;
            var headLead = 0, timesLead = 0;
            var a1Head = '', u1Chip = '', a1Times = '';
            for (final (id, name) in const [('a1', 'abs'), ('u1', 'unk'), ('m1', 'miss'), ('l1', 'late'), ('p1', 'ok')]) {
              final row = await reach(find.byKey(ValueKey('att-row-$id'), skipOffstage: false));
              final els = chipsIn(row).evaluate().toList();
              must('$id 칩 있음', els.isNotEmpty);
              final c0 = chipAt(els.first);
              fg[name] = c0.fg;
              bg[name] = c0.bg;
              final cb = judge(c0.rp);
              chipOk = chipOk && cb.ok;
              if (id == 'u1') u1Chip = _w(cb.lines);
              if (id == 'p1') {
                must('p1 급여 칩 있음(칩 2)', els.length == 2, '칩 ${els.length}개');
                final c1 = chipAt(els.last);
                fg['paid'] = c1.fg;
                bg['paid'] = c1.bg;
                chipOk = chipOk && judge(c1.rp).ok;
              }
              final hf = richIn(row, (p) => p.endsWith(' · 분류'));
              must('$id 머리줄 1', hf.evaluate().length == 1);
              final hb = judge(t.renderObject(hf) as RenderParagraph);
              headOk = headOk && hb.ok;
              headLead += hb.lead;
              if (id == 'a1') a1Head = _w(hb.lines);
              final tf = richIn(row, (p) => p.startsWith('출퇴근 ') || p.startsWith('출근 '));
              must('$id 시각 줄 1', tf.evaluate().length == 1);
              final tb = judge(t.renderObject(tf) as RenderParagraph);
              timesOk = timesOk && tb.ok;
              timesLead += tb.lead;
              if (id == 'a1') a1Times = _w(tb.lines);
            }
            await reach(find.byKey(const ValueKey('att-row-p1'), skipOffstage: false));
            await shot('2low', 'list-bottom');
            _out('D427 $tok att chipfg late=${fg['late']} miss=${fg['miss']} unk=${fg['unk']} abs=${fg['abs']} ok=${fg['ok']} paid=${fg['paid']}');
            _out('D427 $tok att chipbg late=${bg['late']} miss=${bg['miss']} unk=${bg['unk']} abs=${bg['abs']} ok=${bg['ok']} paid=${bg['paid']}');
            _out('D427 $tok att wrap scopeOk=${sc.ok} scopeLead=${sc.lead} headOk=$headOk headLead=$headLead chipOk=$chipOk timesOk=$timesOk timesLead=$timesLead');
            _out('D427 $tok att para n=$paraN ok=$paraOk');
            _out('D427 $tok att lines scope=${_w(sc.lines)} a1head=$a1Head u1chip=$u1Chip a1times=$a1Times');
            if (_before) {
              if (v.id == 'B') {
                // 음성 기대 — 알려진 결함(DU425 · DU426 B 합성)을 이 판정기가 잡는다.
                must('before B 범위 · 머리줄 · 줄 시작', sc.lead >= 1 && headLead >= 1, '${sc.lead} $headLead');
                must('before B 칩 · 시각 낱말 중간 끊김', !chipOk && !timesOk, '$chipOk $timesOk');
              }
            } else {
              must('strict 칩 글자', fg['late'] == 'warningDark' && fg['miss'] == 'textSecondary' && fg['unk'] == 'purple' &&
                  fg['abs'] == 'errorDark' && fg['ok'] == 'successDark' && fg['paid'] == 'textSecondary', '$fg');
              must('strict 칩 바탕 Bg 짝', bg['late'] == 'warningBg' && bg['miss'] == 'grey200' && bg['unk'] == 'purpleBg' &&
                  bg['abs'] == 'errorBg' && bg['ok'] == 'successBg' && bg['paid'] == 'grey200', '$bg');
              must('strict 줄바꿈 경계(범위 · 머리줄 · 시각)', sc.ok && sc.lead == 0 && headOk && headLead == 0 && timesOk && timesLead == 0,
                  '${sc.ok} ${sc.lead} $headOk $headLead $timesOk $timesLead');
              must('strict 문단 높이', paraOk, '$paraN');
            }
            // [수리 r1] 칩 글자는 이번 후보에서 바꾸지 않는다(기존 시험 추종본을 공용 kit 로 적용할 수 없어 범위에서 뺐다).
            //   그래서 칩 줄바꿈은 두 모드 같은 정확 기대다 — W 는 끊김 0, B 는 알려진 잔여('근태 확인 필 / 요')를 판정기가 계속 잡는다.
            must('칩 줄바꿈 뷰별 정확(W 0 · B 잔여)', v.id == 'W' ? chipOk : !chipOk, '$chipOk $u1Chip');
          } else if (st.key == 'EMPTY') {
            await shot('1main', 'empty');
            final sc = judge(t.renderObject(richIn(find.byType(StatsAttendanceListScreen), (p) => p == _scope).first) as RenderParagraph);
            final ef = richIn(find.byType(StatsAttendanceListScreen), (p) => p == _empty);
            must('빈 안내 1', ef.evaluate().length == 1);
            final eb = judge(t.renderObject(ef) as RenderParagraph);
            final align = (t.widget(ef) as RichText).textAlign.name;
            _out('D427 $tok att wrap scopeOk=${sc.ok} scopeLead=${sc.lead} emptyOk=${eb.ok} align=$align');
            _out('D427 $tok att para n=$paraN ok=$paraOk');
            _out('D427 $tok att lines scope=${_w(sc.lines)} empty=${_w(eb.lines)}');
            if (!_before) {
              must('strict 범위 · 빈 안내 경계 · 가운데', sc.ok && sc.lead == 0 && eb.ok && align == 'center', '${sc.ok} ${sc.lead} ${eb.ok} $align');
              must('strict 문단 높이', paraOk, '$paraN');
            }
          } else {
            Finder badge(String uid, String b) => find.byKey(ValueKey('worker-badge-$uid-$b'), skipOffstage: false);
            await reach(badge('late', 'late'));
            await shot('1badge', 'worker-badges');
            final fg = <String, String>{}, bg = <String, String>{};
            for (final (uid, b, name) in const [('late', 'late', 'late'), ('miss', 'missedCheckout', 'miss'), ('unk', 'unconfirmed', 'unk'),
              ('abs', 'absent', 'abs')]) {
              final f = await reach(badge(uid, b));
              must('$name 배지 정확 1', f.evaluate().length == 1);
              final els = chipsIn(f).evaluate().toList();
              must('$name 배지 바탕 상자 1', els.length == 1, '상자 ${els.length}개');
              final c = chipAt(els.single);
              fg[name] = c.fg;
              bg[name] = c.bg;
              judge(c.rp);
            }
            _out('D427 $tok att badgefg late=${fg['late']} miss=${fg['miss']} unk=${fg['unk']} abs=${fg['abs']}');
            _out('D427 $tok att badgebg late=${bg['late']} miss=${bg['miss']} unk=${bg['unk']} abs=${bg['abs']}');
            _out('D427 $tok att para n=$paraN ok=$paraOk');
            if (!_before) {
              must('strict 배지 글자', fg['late'] == 'warningDark' && fg['miss'] == 'textSecondary' && fg['unk'] == 'purple' && fg['abs'] == 'errorDark',
                  '$fg');
              must('strict 배지 바탕 Bg 짝', bg['late'] == 'warningBg' && bg['miss'] == 'grey200' && bg['unk'] == 'purpleBg' && bg['abs'] == 'errorBg',
                  '$bg');
              must('strict 문단 높이', paraOk, '$paraN');
            }
          }
          if (!_before) must('strict 넘침 0', overflows.isEmpty, overflows.join(' | '));
          must('미처리 framework 예외 0', fwErrors.isEmpty, '$fwErrors');
          final exc = t.takeException();
          _out('D427 $tok done state=${st.key} mode=$mode captures=$shots overflows=${overflows.length} exc=${exc != null} ovfRaw=${overflows.isEmpty ? '-' : base64Url.encode(utf8.encode(overflows.join('\n'))).replaceAll('=', '')}');
          must('끝 예외 0', exc == null, '$exc');
        } catch (e) {
          _anyFail = true;
          rethrow;
        }
      }, skip: !_optIn);
    }
  }
}
