// [DU428 · 소급 셀 · 표시만] S028 근태 목록 조판 — 날짜 · 요일 단위(F106-1), 시각 줄(F106-1), 칩 '필 / 요'(F106-2), 계측 보완(F106-3).
//   before = 현재 A(목록 e970256c) / strict = 후보(목록 8ed98126).
//   후보: 머리줄 날짜(요일 포함 · NBSP) · 업무명 따로 항목('·' 생략) / 좁거나 큰 글자면 '근태 확인 ›' 을 본문 아래로 / 시각 조각 joinParts.
//   기본 skip — lkit 단계 env 정확 조합(TB before/du428-tb/DU_BEFORE_OBSERVE=428 · TA after/du428-ta/없음)일 때만 돈다.
//   장면: 뷰 W 390x844@1.0 · B 320x640@2.0 × LIST(5행) = 공개 2. 탭 · 정정 · 조회 흐름은 하지 않는다(표시만).
//   판정(F106-3): 문단마다 글자 선택 상자 top 으로 줄을 묶는다. 보이는 글자(공백 · 제어문자 아님)에 상자가 없으면 visMissing 으로 세고,
//     상자가 하나도 없으면 ok=false. 줄 경계는 앞 글자가 공백 · ZWSP(또는 새 줄 첫 글자가 공백)일 때만 ok. 제어문자 제거 전문 = semanticsLabel,
//     런타임 의미 라벨(getSemantics)에 원문이 있고 제어문자가 없다. 배정 높이 ≥ 필요 높이 − 0.5 · maxLines 초과 0. 조상 clip · 잉크 · 낭독은 계측 밖.
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
import 'package:ALfit/screens/business_admin/stats_attendance_list_screen.dart';
import 'package:ALfit/services/admin_stats_service.dart';
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

// DU427 시험 · 진단과 같은 5행
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
const _ids = ['a1', 'u1', 'm1', 'l1', 'p1'];

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

final bool _before = Platform.environment['DU_BEFORE_OBSERVE'] == '428';
final Map<String, String> _env = Platform.environment;
final bool _optIn =
    (_env['DU1_VQ_PHASE'] == 'before' && _env['DU1_VQ_RUN'] == 'du428-tb' && _env['DU_BEFORE_OBSERVE'] == '428') ||
        (_env['DU1_VQ_PHASE'] == 'after' && _env['DU1_VQ_RUN'] == 'du428-ta' && _env['DU_BEFORE_OBSERVE'] == null);
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

final String _zwsp = String.fromCharCode(0x200B);
final String _wj = String.fromCharCode(0x2060);
final String _nbsp = String.fromCharCode(0x00A0);

/// 보이는 글자인가(공백 · 줄바꿈 없는 공백 · 제어문자 아님).
bool _visible(String ch) => ch.trim().isNotEmpty && ch != _zwsp && ch != _wj && ch != _nbsp;

/// 문단의 실제 줄(DU427 _breaks 보완) — 보이는 글자의 상자 누락(visMissing)과 상자 0(ok=false)을 잡는다.
({List<String> lines, bool ok, int lead, int visMissing}) _breaks(RenderParagraph rp) {
  final s = rp.text.toPlainText(includeSemanticsLabels: false);
  final tops = <double>[];
  final lineOf = List<int>.filled(s.length, -1);
  var visMissing = 0;
  for (var i = 0; i < s.length; i++) {
    final boxes = rp.getBoxesForSelection(TextSelection(baseOffset: i, extentOffset: i + 1));
    if (boxes.isEmpty) {
      if (_visible(s[i])) visMissing++;
      continue;
    }
    final top = boxes.first.top;
    var k = tops.indexWhere((x) => (x - top).abs() < 0.5);
    if (k < 0) {
      tops.add(top);
      k = tops.length - 1;
    }
    lineOf[i] = k;
  }
  if (tops.isEmpty) return (lines: const <String>[], ok: false, lead: 0, visMissing: visMissing);
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
  return (lines: lines, ok: ok && visMissing == 0, lead: lead, visMissing: visMissing);
}

bool _paraOk(RenderParagraph rp) => !rp.didExceedMaxLines && rp.size.height + 0.5 >= rp.getMaxIntrinsicHeight(rp.size.width);

String _w(List<String> lines) => lines.map((x) => x.replaceAll(' ', '_')).join('|');

bool _overlap(Rect a, Rect b) => a.intersect(b).width > 0.5 && a.intersect(b).height > 0.5;

void main() {
  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
  });

  const views = [(id: 'W', w: 390.0, h: 844.0, s: 1.0), (id: 'B', w: 320.0, h: 640.0, s: 2.0)];
  for (final v in views) {
    testWidgets('S028TS-${v.id}-LIST 근태 통계 목록 5행 — 날짜 · 요일 단위 · 업무명 · 칩 · 시각 줄과 행동 배치', (t) async {
      if (_anyFail) fail('앞 사례 실패 — 이 사례 본문 실행 0 · 캡처 0');
      try {
        final tok = 'S028TS-${v.id}-LIST';
        final mode = _before ? 'before' : 'strict';
        _out('D428 $tok begin mode=$mode phase=${Platform.environment['DU1_VQ_PHASE'] ?? '(unset)'} env=$_envLine manifest=$_manifest');
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
              home: StatsAttendanceListScreen(
                  title: '근태 내역', scopeLabel: '2026년 10월 · 평택 센터 · 전체', load: () async => null, matches: (_) => true,
                  initial: StatsAttendanceSnapshot(records: _rows, userInfo: _info)),
            ),
          ),
        ));
        for (var i = 0; i < 20; i++) {
          await t.pump(const Duration(milliseconds: 100));
        }
        final all = find.byType(Scrollable);
        final vs = [for (var i = 0; i < all.evaluate().length; i++) all.at(i)]
            .where((f) => t.state<ScrollableState>(f).position.axis == Axis.vertical)
            .toList()
          ..sort((a, b) => t.getRect(b).height.compareTo(t.getRect(a).height));
        must('세로 Scrollable 있음', vs.isNotEmpty);
        final scrollable = vs.first;
        Future<Finder> reach(Finder f) async {
          t.state<ScrollableState>(scrollable).position.jumpTo(0);
          await t.pump();
          await t.scrollUntilVisible(f, 80, scrollable: scrollable);
          await t.pump();
          return f;
        }

        var shots = 0;
        Future<void> shot(String sub, String state) async {
          _out('D428 $tok shot $sub ovf=${overflows.length}');
          await vqCapture(t, key, '${tok}_$sub', conditions: {
            'viewport': '${v.w.toInt()}x${v.h.toInt()}', 'textScaler': v.s, 'run': vqRun, 'manifest': _manifest, 'mode': mode, 'fixture': 'LIST',
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

        var paraN = 0;
        var paraAll = true;
        var visAll = true;
        var textAll = true;
        var semAll = true;
        // 문단 하나 판정: 줄 · 보이는 글자 · 높이 · 전문(제어문자 제거) = semanticsLabel · 런타임 의미 라벨.
        ({List<String> lines, bool ok, int lead, int visMissing}) judge(Finder rf) {
          paraN++;
          final rp = t.renderObject(rf) as RenderParagraph;
          paraAll = paraAll && _paraOk(rp);
          final b = _breaks(rp);
          visAll = visAll && b.visMissing == 0;
          final textF = find.ancestor(of: rf, matching: find.byType(Text, skipOffstage: false)).first;
          final label = (t.widget(textF) as Text).semanticsLabel;
          final plain = TextLayout.plain(rp.text.toPlainText(includeSemanticsLabels: false));
          if (label != null) {
            textAll = textAll && plain == label;
            final node = t.getSemantics(rf).label;
            semAll = semAll && node.contains(label) && !node.contains(_wj) && !node.contains(_zwsp);
          }
          return b;
        }

        await shot('1main', 'list-top');
        var stackedN = 0;
        var inCardAll = true;
        var overlapAny = false;
        var dateAll = true;
        var workSepN = 0;
        var chipAll = true;
        var chipMaxLines = 0;
        var timesAll = true;
        var timesBreakAfterDot = true;
        var a1Date = '', u1Chip = '', l1Times = '';
        final timesLines = <String, int>{};
        var chipN = 0;
        for (final id in _ids) {
          final row = await reach(find.byKey(ValueKey('att-row-$id'), skipOffstage: false));
          final card = t.getRect(row);
          // 날짜(before: 머리줄 전체)
          final df = richIn(row, (p) => p.startsWith('10/'));
          must('$id 날짜 문단 1', df.evaluate().length == 1, '${df.evaluate().length}개');
          final db = judge(df);
          final intact = db.lines.any((l) => l.contains('10/') && l.contains('('));
          dateAll = dateAll && intact && db.ok && db.lead == 0;
          if (id == 'a1') a1Date = _w(db.lines);
          // 업무명 따로 항목
          final wf = richIn(row, (p) => p == '분류');
          final wn = wf.evaluate().length;
          if (wn == 1) {
            workSepN++;
            final wb = judge(wf);
            dateAll = dateAll && wb.ok && wb.lines.length == 1;
          }
          // 칩
          final els = chipsIn(row).evaluate().toList();
          must('$id 칩 있음', els.isNotEmpty);
          for (final el in els) {
            chipN++;
            final rf = find.descendant(of: find.byElementPredicate((e) => identical(e, el)), matching: find.byType(RichText, skipOffstage: false),
                skipOffstage: false);
            must('$id 칩 글자 문단 1', rf.evaluate().length == 1);
            final cb = judge(rf);
            chipAll = chipAll && cb.ok;
            if (cb.lines.length > chipMaxLines) chipMaxLines = cb.lines.length;
            if (id == 'u1') u1Chip = _w(cb.lines);
          }
          // 시각
          final tf = richIn(row, (p) => p.startsWith('출퇴근 ') || p.startsWith('출근 '));
          must('$id 시각 문단 1', tf.evaluate().length == 1);
          final tb = judge(tf);
          timesAll = timesAll && tb.ok && tb.lead == 0;
          timesLines[id] = tb.lines.length;
          if (tb.lines.length > 1 && !tb.lines.first.endsWith('·')) timesBreakAfterDot = false;
          if (id == 'l1') l1Times = _w(tb.lines);
          // 행동 '근태 확인 ›' — 카드 안 · 본문과 겹침 0 · 쌓기(본문 아래) 여부
          final af = richIn(row, (p) => p == '근태 확인 ›');
          must('$id 행동 1', af.evaluate().length == 1);
          final ar = t.getRect(af);
          inCardAll = inCardAll && ar.left >= card.left - 0.5 && ar.right <= card.right + 0.5 && ar.top >= card.top - 0.5 && ar.bottom <= card.bottom + 0.5;
          final contents = <Rect>[t.getRect(df), t.getRect(tf), if (wn == 1) t.getRect(wf)];
          for (final el in els) {
            contents.add(t.getRect(find.byElementPredicate((e) => identical(e, el))));
          }
          if (contents.any((r) => _overlap(r, ar))) overlapAny = true;
          if (ar.top >= t.getRect(tf).bottom - 0.5) stackedN++;
        }
        await reach(find.byKey(const ValueKey('att-row-p1'), skipOffstage: false));
        await shot('2low', 'list-bottom');
        final tl = _ids.map((id) => timesLines[id]).join('|');
        _out('D428 $tok att layout stacked=$stackedN inCard=$inCardAll overlap=$overlapAny');
        _out('D428 $tok att wrap date=$dateAll workSep=$workSepN chip=$chipAll chipMax=$chipMaxLines times=$timesAll timesAfterDot=$timesBreakAfterDot');
        _out('D428 $tok att timesn v=$tl');
        _out('D428 $tok att check n=$paraN chips=$chipN para=$paraAll vis=$visAll text=$textAll sem=$semAll');
        _out('D428 $tok att lines a1date=$a1Date u1chip=$u1Chip l1times=$l1Times');
        must('방문 5행 · 칩 6', chipN == 6, '$chipN');
        must('문단 높이 · 보이는 글자 · 전문 · 의미 라벨', paraAll && visAll && textAll && semAll, '$paraAll $visAll $textAll $semAll');
        must('행동 카드 안 · 겹침 0', inCardAll && !overlapAny, '$inCardAll $overlapAny');
        if (_before) {
          must('before 나란히(쌓기 0) · 업무명 따로 0', stackedN == 0 && workSepN == 0, '$stackedN $workSepN');
          if (v.id == 'B') {
            // 음성 기대 — 알려진 결함(DU427 B 합성)을 이 판정기가 잡는다.
            must('before B 날짜 · 요일 분리 검출', !dateAll, a1Date);
            must('before B 칩 낱말 중간 끊김 검출', !chipAll, u1Chip);
            must('before B l1 시각 3줄 검출', timesLines['l1'] == 3, l1Times);
          }
        } else {
          must('strict 업무명 따로 5 · 날짜 단위 · 칩 · 시각 경계', workSepN == 5 && dateAll && chipAll && chipMaxLines == 1 && timesAll && timesBreakAfterDot,
              '$workSepN $dateAll $chipAll $chipMaxLines $timesAll $timesBreakAfterDot');
          if (v.id == 'W') {
            must('strict W 나란히 · 시각 한 줄', stackedN == 0 && timesLines.values.every((n) => n == 1), '$stackedN $tl');
          } else {
            must('strict B 쌓기 5 · 시각 ≤ 2줄(출퇴근 기록 없음 1줄)', stackedN == 5 && timesLines['a1'] == 1 && timesLines['u1'] == 1 &&
                timesLines.values.every((n) => n <= 2), '$stackedN $tl');
          }
          must('strict 넘침 0', overflows.isEmpty, overflows.join(' | '));
        }
        must('미처리 framework 예외 0', fwErrors.isEmpty, '$fwErrors');
        final exc = t.takeException();
        _out('D428 $tok done state=LIST mode=$mode captures=$shots overflows=${overflows.length} exc=${exc != null} ovfRaw=${overflows.isEmpty ? '-' : base64Url.encode(utf8.encode(overflows.join('\n'))).replaceAll('=', '')}');
        must('끝 예외 0', exc == null, '$exc');
      } catch (e) {
        _anyFail = true;
        rethrow;
      }
    }, skip: !_optIn);
  }
}
