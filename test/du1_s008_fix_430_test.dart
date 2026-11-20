// [DU430 · 소급 셀 · 표시만] S008 리뷰 관리 '미작성' 탭 교정 — F108-1 마감 '·' 첫머리 · F108-2 탭 '미작성' 잘림(후속108).
//   before = 현재 A(DU429 후보 1e7a5c91) / strict = 후보(ce1e2b7b). 마감 판정 · 버튼 · 콜백 · 문구 원문 · 데이터 그대로.
//   host: DU429 시험과 같은 cloud_functions 채널 대역(목록 2 callable) · 보통(+10일) · 임박(+2일) · 만료(−2일) 요청 3장.
//   fixture 시각은 실행 시점 DateTime.now() 기준 상대일이다 — 캡처 env DU1_VQ_DATE 는 이 시계가 아니다.
//   기대는 fixture 에서 독립으로 만든다(이름 · 기간 '연년 월월' · 마감 '마감 yyyy.MM.dd' · '임박!' · '기한 만료' · 탭 원문 · 배지 수).
//   판정: 줄(선택 상자 top) · 보이는 글자 상자 누락 · 필요/배정 높이 · 각 줄 원문 offset 과 사각형(수치 출력) · 의미 라벨(필수 존재 + 런타임 노드 포함)
//     · 카드 안 이름/기간/마감/임박/버튼 비겹침 · 탭 한 줄 · 화면 안 · 선택. 판정기 음성 확인 3종(빈 문단 · 고정 높이 잘림 · maxLines 밖 글자)을 먼저 돈다.
//   기본 skip — TB before/du430-tb/DU_BEFORE_OBSERVE=430 · TA after/du430-ta/없음.
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
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/providers/notification_provider.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/screens/business_admin/admin_review_list_screen.dart';
import 'package:ALfit/theme/role_theme.dart';
import 'package:ALfit/utils/navigation_key.dart';
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

class _AdminP extends UserProvider {
  @override
  UserModel? get currentUser => UserModel(uid: 'OWNER', username: 'owner', name: '관리자', email: 'owner@test.local', role: UserRole.BUSINESS_ADMIN);
  @override
  String? get effectiveBusinessId => 'BIZ';
}

const _channel = 'dev.flutter.pigeon.cloud_functions_platform_interface.CloudFunctionsHostApi.call';
final _now = DateTime.now();
Map<String, Object?> _ts(DateTime d) => <String, Object?>{'_seconds': d.millisecondsSinceEpoch ~/ 1000, '_nanoseconds': 0};

// 독립 fixture 표 — (키, 이름, 마감까지)
const _fix = [('normal', '합성 보통', 10), ('soon', '합성 임박', 2), ('expired', '합성 만료', -2)];
String _two(int n) => n.toString().padLeft(2, '0');
String _dot(DateTime d) => '${d.year}.${_two(d.month)}.${_two(d.day)}';
DateTime _deadline(int days) => DateTime.fromMillisecondsSinceEpoch((_now.add(Duration(days: days)).millisecondsSinceEpoch ~/ 1000) * 1000);
final String _period = '${_now.year}년 ${_now.month}월';
String _dlExpected(String k, int days) => k == 'expired' ? '기한 만료' : '마감 ${_dot(_deadline(days))}';

Map<String, Object?> _req(String id, String name, int days) => <String, Object?>{
      'id': id, 'requestKey': 'BIZ_${id}_${_now.year}_${_now.month}', 'businessId': 'BIZ', 'businessName': 'QA 사업장',
      'workerId': 'W$id', 'workerName': name, 'reviewYear': _now.year, 'reviewMonth': _now.month,
      'deadline': _ts(_now.add(Duration(days: days))), 'adminStatus': 'pending', 'workerStatus': 'pending', 'isPublished': false,
      'createdAt': _ts(_now.subtract(const Duration(days: 1))),
    };

final _calls = <String>[];
Future<ByteData?> _handle(ByteData? message) async {
  final args = (const StandardMessageCodec().decodeMessage(message) as List).first as Map;
  final name = args['functionName'] as String;
  _calls.add(name);
  ByteData? ok(Map<String, Object?> body) => const StandardMessageCodec().encodeMessage(<Object?>[body]);
  switch (name) {
    case 'callableGetMonthlyReviewsByBiz':
      return ok({'reviews': <Object?>[]});
    case 'callableGetReviewRequestsByBiz':
      return ok({'reviewRequests': <Object?>[for (final (i, f) in _fix.indexed) _req('R${i + 1}', f.$2, f.$3)]});
    default:
      return const StandardMessageCodec().encodeMessage(<Object?>['not-found', 'mock not-found', <String, Object?>{'code': 'not-found'}]);
  }
}

void _stubAuthChannels(WidgetTester t) {
  const base = 'dev.flutter.pigeon.firebase_auth_platform_interface.FirebaseAuthHostApi';
  for (final m in ['registerIdTokenListener', 'registerAuthStateListener']) {
    t.binding.defaultBinaryMessenger.setMockMessageHandler('$base.$m', (_) async => const StandardMessageCodec().encodeMessage(<Object?>['test/auth-events']));
  }
  t.binding.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('test/auth-events'), (_) async => null);
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

final bool _before = Platform.environment['DU_BEFORE_OBSERVE'] == '430';
final Map<String, String> _env = Platform.environment;
final bool _optIn =
    (_env['DU1_VQ_PHASE'] == 'before' && _env['DU1_VQ_RUN'] == 'du430-tb' && _env['DU_BEFORE_OBSERVE'] == '430') ||
        (_env['DU1_VQ_PHASE'] == 'after' && _env['DU1_VQ_RUN'] == 'du430-ta' && _env['DU_BEFORE_OBSERVE'] == null);
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
String _f(double v) => v.toStringAsFixed(1);
String _rect(Rect r) => '${_f(r.left)},${_f(r.top)},${_f(r.width)}x${_f(r.height)}';

final String _zwsp = String.fromCharCode(0x200B);
final String _wj = String.fromCharCode(0x2060);
final String _nbsp = String.fromCharCode(0x00A0);
bool _visible(String ch) => ch.trim().isNotEmpty && ch != _zwsp && ch != _wj && ch != _nbsp;

/// 문단 판정 — 줄 · 각 줄 시작 원문 offset · 줄 사각형 · 보이는 글자 상자 누락 · 첫머리 '·' 수 · 경계 ok.
({List<String> lines, List<int> starts, List<Rect> rects, bool ok, int lead, int visMissing}) _judge(RenderParagraph rp) {
  final s = rp.text.toPlainText(includeSemanticsLabels: false);
  final tops = <double>[];
  final lineOf = List<int>.filled(s.length, -1);
  final boxesOf = <int, List<TextBox>>{};
  var visMissing = 0;
  for (var i = 0; i < s.length; i++) {
    final boxes = rp.getBoxesForSelection(TextSelection(baseOffset: i, extentOffset: i + 1));
    if (boxes.isEmpty || boxes.every((b) => (b.right - b.left).abs() < 0.01 && _visible(s[i]))) {
      if (_visible(s[i])) visMissing++;
      if (boxes.isEmpty) continue;
    }
    var k = tops.indexWhere((x) => (x - boxes.first.top).abs() < 0.5);
    if (k < 0) {
      tops.add(boxes.first.top);
      k = tops.length - 1;
    }
    lineOf[i] = k;
    boxesOf[i] = boxes;
  }
  if (tops.isEmpty) return (lines: const <String>[], starts: const <int>[], rects: const <Rect>[], ok: false, lead: 0, visMissing: visMissing);
  final order = List<int>.generate(tops.length, (i) => i)..sort((a, b) => tops[a].compareTo(tops[b]));
  final rank = List<int>.filled(tops.length, 0);
  for (var r = 0; r < order.length; r++) {
    rank[order[r]] = r;
  }
  final buf = List<StringBuffer>.generate(tops.length, (_) => StringBuffer());
  final starts = List<int>.filled(tops.length, -1);
  final rects = List<Rect?>.filled(tops.length, null);
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
      if (starts[ln] < 0) starts[ln] = i;
      for (final bx in boxesOf[i]!) {
        final r = Rect.fromLTRB(bx.left, bx.top, bx.right, bx.bottom);
        rects[ln] = rects[ln] == null ? r : rects[ln]!.expandToInclude(r);
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
  return (lines: lines, starts: starts, rects: [for (final r in rects) r ?? Rect.zero], ok: ok && visMissing == 0, lead: lead, visMissing: visMissing);
}

double _need(RenderParagraph rp) => rp.getMaxIntrinsicHeight(rp.size.width);
bool _paraOk(RenderParagraph rp) => !rp.didExceedMaxLines && rp.size.height + 0.5 >= _need(rp);
String _w(List<String> lines) => lines.map((x) => x.replaceAll(' ', '_')).join('|');
bool _overlap(Rect a, Rect b) => a.intersect(b).width > 0.5 && a.intersect(b).height > 0.5;

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
  });

  const views = [(id: 'W', w: 390.0, h: 844.0, s: 1.0), (id: 'B', w: 320.0, h: 640.0, s: 2.0)];
  for (final v in views) {
    testWidgets('S008FX-${v.id}-PENDING 리뷰 관리 미작성 탭 — 마감 · 임박 따로 항목 · 탭 원문 한 줄 · 줄 수치 · 의미 라벨', (t) async {
      if (_anyFail) fail('앞 사례 실패 — 이 사례 본문 실행 0 · 캡처 0');
      try {
        final tok = 'S008FX-${v.id}-PENDING';
        final mode = _before ? 'before' : 'strict';
        _out('D430 $tok begin mode=$mode phase=${Platform.environment['DU1_VQ_PHASE'] ?? '(unset)'} env=$_envLine manifest=$_manifest');
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

        // ── 판정기 음성 확인 3종(제품 화면 밖 작은 트리) ──
        await t.pumpWidget(Directionality(
          textDirection: TextDirection.ltr,
          child: Column(children: [
            const Text('', key: ValueKey('neg-empty')),
            const SizedBox(height: 8, child: Text('높이가 모자라 잘리는 두 줄 이상의 문장 하나 둘 셋 넷 다섯', key: ValueKey('neg-clip'))),
            const SizedBox(width: 60, child: Text('한 줄 밖 글자가 남는 문장 하나 둘 셋', key: ValueKey('neg-max'), maxLines: 1, overflow: TextOverflow.clip)),
          ]),
        ));
        RenderParagraph negRp(String k) => t.renderObject(find.descendant(of: find.byKey(ValueKey(k)), matching: find.byType(RichText), matchRoot: true)) as RenderParagraph;
        final negEmpty = _judge(negRp('neg-empty')).ok;
        final negClip = _paraOk(negRp('neg-clip'));
        final negMaxRp = negRp('neg-max');
        final negMax = _judge(negMaxRp).visMissing > 0 || negMaxRp.didExceedMaxLines;
        _out('D430 $tok att neg emptyOk=$negEmpty clipOk=$negClip maxCaught=$negMax');
        must('판정기 음성: 빈 문단 ok=false · 고정 높이 잘림 paraOk=false · maxLines 밖 글자 검출', !negEmpty && !negClip && negMax,
            '빈 $negEmpty 잘림 $negClip 줄수밖 $negMax');

        _stubAuthChannels(t);
        _calls.clear();
        t.binding.defaultBinaryMessenger.setMockMessageHandler(_channel, _handle);
        addTearDown(() => t.binding.defaultBinaryMessenger.setMockMessageHandler(_channel, null));
        final key = GlobalKey();
        await t.pumpWidget(MultiProvider(
          providers: [
            ChangeNotifierProvider<UserProvider>(create: (_) => _AdminP()),
            ChangeNotifierProvider<NotificationProvider>(create: (_) => NotificationProvider()),
          ],
          child: RepaintBoundary(
            key: key,
            child: MaterialApp(
              navigatorKey: navigatorKey,
              debugShowCheckedModeBanner: false,
              theme: RoleTheme.businessAdminTheme,
              builder: (ctx, child) => MediaQuery(data: MediaQuery.of(ctx).copyWith(textScaler: TextScaler.linear(v.s)), child: child!),
              home: const AdminReviewListScreen(businessId: 'BIZ'),
            ),
          ),
        ));
        for (var r = 0; r < 4; r++) {
          await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
          for (var i = 0; i < 5; i++) {
            await t.pump(const Duration(milliseconds: 50));
          }
        }
        Finder rich(bool Function(String p) p) => find.byWidgetPredicate((w) => w is RichText && p(_plainOf(w)), skipOffstage: false);
        final tabBar = find.byType(TabBar);
        must('탭 막대 1', tabBar.evaluate().length == 1);
        final scrollableTabs = (t.widget(tabBar) as TabBar).isScrollable;

        // ── 탭: 원문 · 배지 · 한 줄 · 닿은 뒤 화면 안 ──
        final tabTexts = <String>[], tabLines = <String>[], tabBadges = <String>[], tabIn = <String>[];
        for (final (label, badge) in const [('작성', '0'), ('받음', '0'), ('미작성', '3')]) {
          final lf = find.descendant(of: tabBar, matching: rich((p) => p == label), skipOffstage: false);
          must('탭 글자 $label 1', lf.evaluate().length == 1, '${lf.evaluate().length}개');
          await t.ensureVisible(lf);
          await t.pump();
          final tabF = find.ancestor(of: lf, matching: find.byType(Tab, skipOffstage: false)).first;
          final bf = find.descendant(of: tabF, matching: rich((p) => p == badge), skipOffstage: false);
          must('탭 $label 배지 $badge 1', bf.evaluate().length == 1, '${bf.evaluate().length}개');
          final rp = t.renderObject(lf) as RenderParagraph;
          final lr = t.getRect(lf);
          final tr = t.getRect(tabF);
          tabTexts.add(label);
          tabLines.add(_judge(rp).lines.length.toString());
          tabBadges.add(badge);
          final inside = lr.left >= -0.5 && lr.right <= v.w + 0.5 && lr.bottom <= tr.bottom + 0.5 && rp.size.height + 0.5 >= _need(rp);
          tabIn.add(inside.toString());
        }
        final pendTab = find.descendant(of: tabBar, matching: rich((p) => p == '미작성'), skipOffstage: false);
        await t.ensureVisible(pendTab);
        await t.pump();
        await t.tap(pendTab);
        for (var i = 0; i < 20; i++) {
          await t.pump(const Duration(milliseconds: 50));
        }
        final selected = (t.widget(tabBar) as TabBar).controller!.index;
        _out('D430 $tok att tabs scrollable=$scrollableTabs text=${tabTexts.join('|')} lines=${tabLines.join('|')} badge=${tabBadges.join('|')} in=${tabIn.join('|')} selected=$selected');

        final all = find.byType(Scrollable);
        final vs = [for (var i = 0; i < all.evaluate().length; i++) all.at(i)]
            .where((f) => t.state<ScrollableState>(f).position.axis == Axis.vertical && t.getRect(f).left >= -0.5 && t.getRect(f).left < v.w - 1)
            .toList()
          ..sort((a, b) => t.getRect(b).height.compareTo(t.getRect(a).height));
        must('세로 Scrollable 있음', vs.isNotEmpty);
        final scrollable = vs.first;
        Future<void> reach(Finder f) async {
          t.state<ScrollableState>(scrollable).position.jumpTo(0);
          await t.pump();
          await t.scrollUntilVisible(f, 80, scrollable: scrollable);
          await t.pump();
        }

        var shots = 0;
        Future<void> shot(String sub, String state) async {
          _out('D430 $tok shot $sub ovf=${overflows.length}');
          await vqCapture(t, key, '${tok}_$sub', conditions: {
            'viewport': '${v.w.toInt()}x${v.h.toInt()}', 'textScaler': v.s, 'run': vqRun, 'manifest': _manifest, 'mode': mode, 'fixture': 'PENDING',
            'state': state,
          });
          shots++;
        }

        await shot('1top', 'pending-top');
        var paraAll = true, visAll = true, wrapAll = true, semAll = true, textAll = true, labelAll = true, overlapAny = false;
        var judged = 0;
        // 문단 하나: 판정 + 독립 원문 대조(expected) + 라벨 필수 여부.
        ({List<String> lines, List<int> starts, List<Rect> rects, bool ok, int lead, int visMissing}) check(Finder rf, String expected, bool needLabel) {
          judged++;
          final rp = t.renderObject(rf) as RenderParagraph;
          paraAll = paraAll && _paraOk(rp);
          final j = _judge(rp);
          visAll = visAll && j.visMissing == 0;
          wrapAll = wrapAll && j.ok;
          final plain = TextLayout.plain(rp.text.toPlainText(includeSemanticsLabels: false));
          textAll = textAll && plain == expected;
          final textF = find.ancestor(of: rf, matching: find.byType(Text, skipOffstage: false)).first;
          final label = (t.widget(textF) as Text).semanticsLabel;
          if (needLabel) labelAll = labelAll && label == expected;
          if (label != null) {
            final node = t.getSemantics(rf).label;
            semAll = semAll && node.contains(label) && !node.contains(_wj) && !node.contains(_zwsp);
          }
          return j;
        }

        final rows = <String>[];
        final geom = <String>[];
        var soonLead = 0;
        var soonSep = 0;
        var soonDl = '';
        for (final (k, name, days) in _fix) {
          final nameF = rich((p) => p == name);
          await reach(nameF);
          must('$k 이름 1', nameF.evaluate().length == 1);
          final cardF = find.ancestor(
              of: nameF,
              matching: find.byWidgetPredicate(
                  (w) => w is Container && w.decoration is BoxDecoration && (w.decoration! as BoxDecoration).borderRadius == BorderRadius.circular(16),
                  skipOffstage: false)).first;
          final dlExp = _dlExpected(k, days);
          final periodF = find.descendant(of: cardF, matching: rich((p) => p == _period), skipOffstage: false);
          // before 의 임박 마감은 '마감 날짜 · 임박!' 한 문단이다 — 시작 일치로 찾는다.
          final dlF = find.descendant(of: cardF, matching: rich((p) => p == dlExp || p.startsWith('$dlExp ')), skipOffstage: false);
          final soonF = find.descendant(of: cardF, matching: rich((p) => p == '임박!'), skipOffstage: false);
          must('$k 기간 · 마감 문단 각 1', periodF.evaluate().length == 1 && dlF.evaluate().length == 1,
              '기간 ${periodF.evaluate().length} 마감 ${dlF.evaluate().length}');
          final nj = check(nameF, name, true);
          check(periodF, _period, true);
          final dlPlain = _plainOf(t.widget(dlF));
          final dj = check(dlF, dlPlain, true);
          // 독립 원문: after 는 마감 글이 정확히 dlExp, before 의 임박은 dlExp + ' · 임박!'.
          final dlTextOk = _before && k == 'soon' ? dlPlain == '$dlExp · 임박!' : dlPlain == dlExp;
          textAll = textAll && dlTextOk;
          final soonN = soonF.evaluate().length;
          final rects = <Rect>[t.getRect(nameF), t.getRect(periodF), t.getRect(dlF)];
          if (soonN == 1) {
            check(soonF, '임박!', false);
            rects.add(t.getRect(soonF));
          }
          final btnF = find.descendant(of: cardF, matching: find.byWidgetPredicate((w) => w is ElevatedButton, skipOffstage: false), skipOffstage: false);
          final btnN = btnF.evaluate().length;
          if (btnN == 1) rects.add(t.getRect(btnF));
          for (var i = 0; i < rects.length; i++) {
            for (var j = i + 1; j < rects.length; j++) {
              if (_overlap(rects[i], rects[j])) overlapAny = true;
            }
          }
          final rpDl = t.renderObject(dlF) as RenderParagraph;
          if (k == 'soon') {
            soonLead = dj.lead;
            soonSep = soonN;
            soonDl = _w(dj.lines);
          }
          final dateIntact = k == 'expired' || dj.lines.any((l) => l.contains(_dot(_deadline(days))));
          rows.add('$k=dl:${_w(dj.lines)};lead:${dj.lead};date:$dateIntact;soon:$soonN;btn:$btnN;name:${nj.lines.length}');
          geom.add('$k=need:${_f(_need(rpDl))};got:${_f(rpDl.size.height)};w:${_f(rpDl.size.width)};max:${_f(rpDl.constraints.maxWidth)};'
              'ml:${rpDl.maxLines ?? 0};ov:${rpDl.overflow.name};starts:${dj.starts.join('/')};rects:${dj.rects.map(_rect).join('/')}');
        }
        await reach(rich((p) => p == '합성 만료'));
        await shot('2expired', 'pending-expired');
        _out('D430 $tok att cards ${rows.join(' ')}');
        _out('D430 $tok att geom ${geom.join(' ')}');
        _out('D430 $tok att check n=$judged para=$paraAll vis=$visAll wrap=$wrapAll text=$textAll label=$labelAll sem=$semAll overlap=$overlapAny');
        _out('D430 $tok att soon lead=$soonLead sep=$soonSep dl=$soonDl');
        must('작성 경로 호출 0', !_calls.contains('callableGetUsersBatch') && !_calls.contains('callableGetAdminAttendances'), '호출 $_calls');
        must('문단 높이 · 보이는 글자 · 원문 · 라벨 · 의미 노드 · 카드 안 비겹침', paraAll && visAll && textAll && labelAll && semAll && !overlapAny,
            '$paraAll $visAll $textAll $labelAll $semAll $overlapAny');
        if (_before) {
          if (v.id == 'B') {
            // 음성 기대 — 알려진 B 결함(감사108 F108-1 · F108-2)을 판정기가 잡는다.
            must('before B 임박 마감 줄 첫머리 점 검출', soonLead >= 1, soonDl);
            must('before B 탭 미작성 두 줄 검출', tabLines[2] != '1', tabLines.join('|'));
          }
        } else {
          must('strict 탭 원문 한 줄 · 닿은 뒤 화면 안 · 미작성 선택', tabLines.every((x) => x == '1') && tabIn.every((x) => x == 'true') && selected == 2,
              '${tabLines.join('|')} ${tabIn.join('|')} 선택 $selected');
          must('strict 탭 가로 스크롤 W 아님 · B 예', scrollableTabs == (v.id == 'B'), '스크롤 $scrollableTabs');
          must('strict 임박 따로 항목 · 첫머리 점 0 · 날짜 단위 · 경계', soonSep == 1 && soonLead == 0 && wrapAll && rows.every((r) => r.contains(';date:true;')),
              rows.join(' '));
          must('strict 넘침 0', overflows.isEmpty, overflows.join(' | '));
        }
        must('미처리 framework 예외 0', fwErrors.isEmpty, '오류 $fwErrors');
        final exc = t.takeException();
        _out('D430 $tok done state=PENDING mode=$mode captures=$shots overflows=${overflows.length} exc=${exc != null} ovfRaw=${overflows.isEmpty ? '-' : base64Url.encode(utf8.encode(overflows.join('\n'))).replaceAll('=', '')}');
        must('끝 예외 0', exc == null, '예외 $exc');
      } catch (e) {
        _anyFail = true;
        rethrow;
      }
    }, skip: !_optIn);
  }
}
