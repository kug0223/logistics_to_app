// [DU432 · 소급 셀 · 표시만] S008 리뷰 관리 검색 안내 — hint 모드 세로 여백 · 정렬 국소 보완(후속112 §3–4).
//   DU431 r1 시험(11baae24)을 바탕으로 했다. 칸 · 안내 네 변 차이, 입력 · 지운 뒤 기하, 목록 높이를 수치로 출력하고 strict 단언을 더했다.
//   before = 복원 A(화면 ce1e2b7b · AppSearchBar b7d6b0fc) / strict = 후보(화면 182d1e78 · AppSearchBar 79d2e9b5).
//   후보: hintMaxLines 를 줄 때만 다음을 한다. 기본 null 경로는 그대로다.
//     - 안내를 keepWords 로 두 줄까지 · 기본 안내와 같은 글꼴 · 줄 높이.
//     - 세로 contentPadding spacing(10).
//     - maintainHintSize false.
//   준비 렌더 진단(diag · 1회) 통과: B 빈 칸 107 · 위/아래 10.87/6.13 · 입력 중 65 · 글자 ↔ 아이콘 중심 0, W 는 base 와 같다.
//   host · fixture 는 DU430 · DU431 시험과 같다(목록 2 callable · 보통/임박/만료).
//   기본 skip — TB before/du432-tb/DU_BEFORE_OBSERVE=432 · TA after/du432-ta/없음.
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
import 'package:ALfit/widgets/common/app_search_bar.dart';

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

final bool _before = Platform.environment['DU_BEFORE_OBSERVE'] == '432';
final Map<String, String> _env = Platform.environment;
final bool _optIn =
    (_env['DU1_VQ_PHASE'] == 'before' && _env['DU1_VQ_RUN'] == 'du432-tb' && _env['DU_BEFORE_OBSERVE'] == '432') ||
        (_env['DU1_VQ_PHASE'] == 'after' && _env['DU1_VQ_RUN'] == 'du432-ta' && _env['DU_BEFORE_OBSERVE'] == null);
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

String _f2(double v) => v.toStringAsFixed(2);

/// 안내 불투명도 — 없으면 0(hint 모드 maintainHintSize false 는 입력 중 안내를 트리에서 뺀다). FadeTransition(AnimatedSwitcher)도 곱한다.
double _opacityOf(WidgetTester t, Finder f) {
  final els = f.evaluate().toList();
  if (els.isEmpty) return 0.0;
  var op = 1.0;
  els.single.visitAncestorElements((e) {
    final w = e.widget;
    if (w is Opacity) op *= w.opacity;
    if (w is AnimatedOpacity) op *= w.opacity;
    if (w is FadeTransition) op *= w.opacity.value;
    return true;
  });
  return op;
}

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
  });

  const hint = '근무자 이름으로 검색';
  const views = [(id: 'W', w: 390.0, h: 844.0, s: 1.0), (id: 'B', w: 320.0, h: 640.0, s: 2.0)];
  for (final v in views) {
    testWidgets('S008SH-${v.id}-SEARCH 리뷰 관리 검색 안내 — 두 줄 안내 세로 여백 · 입력 정렬 · 원문 의미 · 기본 경로 불변', (t) async {
      if (_anyFail) fail('앞 사례 실패 — 이 사례 본문 실행 0 · 캡처 0');
      try {
        final tok = 'S008SH-${v.id}-SEARCH';
        final mode = _before ? 'before' : 'strict';
        _out('D432 $tok begin mode=$mode phase=${Platform.environment['DU1_VQ_PHASE'] ?? '(unset)'} env=$_envLine manifest=$_manifest');
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
        Finder rich(bool Function(String p) p) => find.byWidgetPredicate((w) => w is RichText && p(_plainOf(w)), skipOffstage: false);

        // ── 판정기 음성 확인 3종(DU430 과 같다) ──
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
        _out('D432 $tok att neg emptyOk=$negEmpty clipOk=$negClip maxCaught=$negMax');
        must('판정기 음성 3종', !negEmpty && !negClip && negMax, '빈 $negEmpty 잘림 $negClip 줄수밖 $negMax');

        // ── 기본 경로(hintMaxLines 없음) — 다른 소비처와 같은 경로. before/after 같아야 한다 ──
        final dc = TextEditingController();
        addTearDown(dc.dispose);
        await t.pumpWidget(MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: RoleTheme.businessAdminTheme,
          builder: (ctx, child) => MediaQuery(data: MediaQuery.of(ctx).copyWith(textScaler: TextScaler.linear(v.s)), child: child!),
          home: Scaffold(body: Column(children: [AppSearchBar(controller: dc, hintText: hint)])),
        ));
        await t.pump();
        final dh = rich((p) => p == hint);
        must('기본 안내 문단 1', dh.evaluate().length == 1, '${dh.evaluate().length}개');
        final drp = t.renderObject(dh) as RenderParagraph;
        _out('D432 $tok att default maxLines=${drp.maxLines ?? 0} overflow=${drp.overflow.name} exceeded=${drp.didExceedMaxLines} '
            'fieldH=${_f(t.getRect(find.byType(TextField)).height)}');

        // ── S008 화면 ──
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
        var shots = 0;
        Future<void> shot(String sub, String state) async {
          _out('D432 $tok shot $sub ovf=${overflows.length}');
          await vqCapture(t, key, '${tok}_$sub', conditions: {
            'viewport': '${v.w.toInt()}x${v.h.toInt()}', 'textScaler': v.s, 'run': vqRun, 'manifest': _manifest, 'mode': mode, 'fixture': 'SEARCH',
            'state': state,
          });
          shots++;
        }

        // 미작성 탭(목록이 있는 탭)으로
        final tabBar = find.byType(TabBar);
        final pendTab = find.descendant(of: tabBar, matching: rich((p) => p == '미작성'), skipOffstage: false);
        await t.ensureVisible(pendTab);
        await t.pump();
        await t.tap(pendTab);
        for (var i = 0; i < 20; i++) {
          await t.pump(const Duration(milliseconds: 50));
        }
        await shot('1top', 'search-empty');

        final tf = find.byType(TextField);
        must('검색 입력 1', tf.evaluate().length == 1);
        final hf = find.descendant(of: tf, matching: rich((p) => p == hint), skipOffstage: false);
        must('안내 문단 1(보이는 글자 = 원문)', hf.evaluate().length == 1, '${hf.evaluate().length}개');
        final rp = t.renderObject(hf) as RenderParagraph;
        final j = _judge(rp);
        // [초안 r1 · DU432 TA STOP] rp 는 입력 중 트리에서 빠져 dispose 될 수 있다 — 단언에 쓸 값은 여기서 바로 남긴다.
        final rpExceeded = rp.didExceedMaxLines;
        final rpParaOk = _paraOk(rp);
        final rpNeed = _need(rp);
        final rpGot = rp.size.height;
        final textF = find.ancestor(of: hf, matching: find.byType(Text, skipOffstage: false)).first;
        final label = (t.widget(textF) as Text).semanticsLabel;
        // 안내는 의미 노드의 label · hint · value 어디에든 들어갈 수 있다 — 셋을 합쳐 원문 포함 · 제어문자 0 을 본다.
        final sn = t.getSemantics(hf);
        final node = '${sn.label}|${sn.hint}|${sn.value}';
        final semOk = node.contains(hint) && !node.contains(_wj) && !node.contains(_zwsp);
        final fieldR = t.getRect(tf);
        final hintR = t.getRect(hf);
        final barF = find.ancestor(of: tf, matching: find.byType(Container, skipOffstage: false)).first;
        final barR = t.getRect(barF);
        final tabR = t.getRect(tabBar);
        final chipF = rich((p) => p == '전체');
        final chipR = t.getRect(chipF.first);
        final inField = hintR.left >= fieldR.left - 0.5 && hintR.right <= fieldR.right + 0.5 && hintR.top >= fieldR.top - 0.5 && hintR.bottom <= fieldR.bottom + 0.5;
        final overlapTab = barR.top < tabR.bottom - 0.5;
        final overlapChip = chipR.top < barR.bottom - 0.5;
        _out('D432 $tok att hint lines=${j.lines.length} ok=${j.ok} exceeded=${rp.didExceedMaxLines} maxLines=${rp.maxLines ?? 0} overflow=${rp.overflow.name} '
            'labelSet=${label != null} labelOk=${label == hint} sem=$semOk text=${_w(j.lines)}');
        _out('D432 $tok att geom need=${_f(_need(rp))} got=${_f(rp.size.height)} w=${_f(rp.size.width)} max=${_f(rp.constraints.maxWidth)} '
            'starts=${j.starts.join('/')} rects=${j.rects.map(_rect).join('/')}');
        _out('D432 $tok att layout fieldH=${_f(fieldR.height)} barH=${_f(barR.height)} inField=$inField overlapTab=$overlapTab overlapChip=$overlapChip');
        // [DU432] 칸 · 안내 네 변 차이(음수 = 밖으로 벗어난 양) · 막대 아래 세로 목록 높이(없으면 -1).
        final gl = hintR.left - fieldR.left, gr = fieldR.right - hintR.right, gt = hintR.top - fieldR.top, gb = fieldR.bottom - hintR.bottom;
        final listRs = find
            .byWidgetPredicate((w) => w is Scrollable && (w.axisDirection == AxisDirection.down || w.axisDirection == AxisDirection.up))
            .evaluate()
            .map((e) => t.getRect(find.byElementPredicate((x) => identical(x, e))))
            .where((r) => r.top >= barR.bottom - 0.5)
            .toList();
        final listH = listRs.isEmpty ? -1.0 : listRs.first.height;
        _out('D432 $tok att gap l=${_f2(gl)} r=${_f2(gr)} t=${_f2(gt)} b=${_f2(gb)} fieldH=${_f2(fieldR.height)} hintH=${_f2(hintR.height)} '
            'listN=${listRs.length} listH=${_f2(listH)}');

        // ── 입력 → 거르기 → 지우기(안내 가림 · 복귀 · 목록) ──
        int cardsShown() => ['합성 보통', '합성 임박', '합성 만료'].where((n) => rich((p) => p == n).evaluate().isNotEmpty).length;
        final before3 = cardsShown();
        await t.enterText(tf, '보통');
        for (var i = 0; i < 10; i++) {
          await t.pump(const Duration(milliseconds: 100));
        }
        final hintTyped = _opacityOf(t, find.descendant(of: tf, matching: rich((p) => p == hint), skipOffstage: false));
        final filtered = cardsShown();
        // [DU432] 입력 중 — 칸 높이 · 입력 글자 상자 중심과 검색 아이콘 중심 차 · 안내 문단 수(hint 모드는 0, 기본은 1 · 불투명도 0).
        final typedFieldR = t.getRect(tf);
        final edR = t.getRect(find.descendant(of: tf, matching: find.byType(EditableText, skipOffstage: false), skipOffstage: false));
        final iconR = t.getRect(find.descendant(of: tf, matching: find.byIcon(Icons.search, skipOffstage: false), skipOffstage: false));
        final dCenter = edR.center.dy - iconR.center.dy;
        final typedHintN = find.descendant(of: tf, matching: rich((p) => p == hint), skipOffstage: false).evaluate().length;
        _out('D432 $tok att typed fieldH=${_f2(typedFieldR.height)} dCenter=${_f2(dCenter)} hintN=$typedHintN');
        await shot('2typed', 'search-typed');
        final clearF = find.descendant(of: tf, matching: find.byIcon(Icons.clear, skipOffstage: false), skipOffstage: false);
        must('지우기 버튼 1', clearF.evaluate().length == 1, '${clearF.evaluate().length}개');
        await t.tap(clearF);
        for (var i = 0; i < 10; i++) {
          await t.pump(const Duration(milliseconds: 100));
        }
        final hintBack = _opacityOf(t, find.descendant(of: tf, matching: rich((p) => p == hint), skipOffstage: false));
        final restored = cardsShown();
        // [DU432] 지운 뒤 — 빈 안내와 같은 칸 높이 · 위아래 여유인지.
        final clearedHf = find.descendant(of: tf, matching: rich((p) => p == hint), skipOffstage: false);
        final clearedN = clearedHf.evaluate().length;
        final clearedFieldR = t.getRect(tf);
        final clearedHintR = clearedN == 1 ? t.getRect(clearedHf) : Rect.zero;
        final ct = clearedHintR.top - clearedFieldR.top, cb = clearedFieldR.bottom - clearedHintR.bottom;
        _out('D432 $tok att cleared fieldH=${_f2(clearedFieldR.height)} t=${_f2(ct)} b=${_f2(cb)} hintN=$clearedN');
        _out('D432 $tok att input before=$before3 typedHint=${hintTyped.toStringAsFixed(2)} filtered=$filtered clearedHint=${hintBack.toStringAsFixed(2)} restored=$restored');

        must('작성 경로 호출 0', !_calls.contains('callableGetUsersBatch') && !_calls.contains('callableGetAdminAttendances'), '호출 $_calls');
        must('입력 → 거르기 → 지우기 경로 보존', before3 >= 2 && hintTyped < 0.01 && filtered == 1 && hintBack > 0.99 && restored == before3,
            '처음 $before3 · 입력 뒤 안내 $hintTyped · 거름 $filtered · 지운 뒤 안내 $hintBack · 복귀 $restored');
        // [수리 r1] 문단 높이(_paraOk = didExceedMaxLines 아님 포함)는 before B 의 알려진 말줄임과 모순이라 strict 전용으로 옮겼다(DU431 TB STOP).
        must('안내 안 · 막대 비겹침', inField && !overlapTab && !overlapChip, '$inField $overlapTab $overlapChip');
        if (_before) {
          if (v.id == 'B') {
            // 음성 기대 — 알려진 B 결함(감사110 후보: '근무자 이름…' 말줄임)을 판정기가 잡는다.
            must('before B 안내 말줄임 검출', rpExceeded && j.lines.length == 1, 'exceeded $rpExceeded 줄 ${j.lines.length}');
          }
        } else {
          must('strict 안내 원문 라벨 · 의미 노드 · 말줄임 0 · 낱말 경계', label == hint && semOk && !rpExceeded && j.ok && j.visMissing == 0,
              '라벨 $label 넘침 $rpExceeded 경계 ${j.ok}');
          must('strict 줄 수(W 1 · B 2)', j.lines.length == (v.id == 'W' ? 1 : 2), _w(j.lines));
          must('strict 안내 문단 높이(필요 ≤ 배정 · 줄 수 초과 0)', rpParaOk, 'need ${_f(rpNeed)} got ${_f(rpGot)}');
          must('strict 넘침 0', overflows.isEmpty, overflows.join(' | '));
          // [DU432] 후보 기하 — 준비 진단과 같은 기준(pre/diag_criteria.md C1 · C4 · C5 · C3).
          must('strict 안내 위 · 아래 여유 ≥ 4', gt >= 4 && gb >= 4, '위 ${_f2(gt)} 아래 ${_f2(gb)}');
          must('strict 입력 글자 ↔ 아이콘 중심 |Δ| ≤ 1', dCenter.abs() <= 1.0, _f2(dCenter));
          must('strict 입력 중 칸 ≤ 빈 칸', typedFieldR.height <= fieldR.height + 0.01, '${_f2(typedFieldR.height)} ${_f2(fieldR.height)}');
          must('strict 지운 뒤 = 빈 안내(±0.5)', clearedN == 1 && (ct - gt).abs() <= 0.5 && (cb - gb).abs() <= 0.5 && (clearedFieldR.height - fieldR.height).abs() <= 0.5,
              '$clearedN ${_f2(ct)} ${_f2(cb)} ${_f2(clearedFieldR.height)}');
          if (v.id == 'W') {
            must('strict W 칸 48(빈 · 입력 · 지운 뒤)', [fieldR, typedFieldR, clearedFieldR].every((r) => (r.height - 48).abs() <= 0.01),
                '${_f2(fieldR.height)} ${_f2(typedFieldR.height)} ${_f2(clearedFieldR.height)}');
          }
        }
        must('미처리 framework 예외 0', fwErrors.isEmpty, '오류 $fwErrors');
        final exc = t.takeException();
        _out('D432 $tok done state=SEARCH mode=$mode captures=$shots overflows=${overflows.length} exc=${exc != null} ovfRaw=${overflows.isEmpty ? '-' : base64Url.encode(utf8.encode(overflows.join('\n'))).replaceAll('=', '')}');
        must('끝 예외 0', exc == null, '예외 $exc');
      } catch (e) {
        _anyFail = true;
        rethrow;
      }
    }, skip: !_optIn);
  }
}
