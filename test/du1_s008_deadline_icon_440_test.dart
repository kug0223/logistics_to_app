// [DU440 · 자체 판정 셀 · 표시만] S008 리뷰 관리 미작성 — 마감 아이콘(schedule · alarm)을 마감 글 첫 줄 가운데에 둔다(FirstLineIcon · 크기 불변).
//   F110 후보 '마감 아이콘 식별성 보조'(감사110). DU432 r2 시험(b8d3dbe2)의 host · fixture · '미작성' 진입을 그대로 쓰고 측정만 바꿨다.
//   before = 현재 A(화면 182d1e78) / strict = 후보(33ec98c3). 값은 즉시 지역 값으로. 기본 skip — TB before/du440-tb/DU_BEFORE_OBSERVE=440 · TA after/du440-ta/없음.
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

final bool _before = Platform.environment['DU_BEFORE_OBSERVE'] == '440';
final Map<String, String> _env = Platform.environment;
final bool _optIn =
    (_env['DU1_VQ_PHASE'] == 'before' && _env['DU1_VQ_RUN'] == 'du440-tb' && _env['DU_BEFORE_OBSERVE'] == '440') ||
        (_env['DU1_VQ_PHASE'] == 'after' && _env['DU1_VQ_RUN'] == 'du440-ta' && _env['DU_BEFORE_OBSERVE'] == null);
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

String _f2(double v) => v.toStringAsFixed(2);

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
  });

  const views = [(id: 'W', w: 390.0, h: 844.0, s: 1.0), (id: 'B', w: 320.0, h: 640.0, s: 2.0)];
  for (final v in views) {
    testWidgets('S008DI-${v.id}-PENDING 리뷰 관리 미작성 — 마감 아이콘 첫 줄 정렬 · 크기 불변', (t) async {
      if (_anyFail) fail('앞 사례 실패 — 이 사례 본문 실행 0 · 캡처 0');
      try {
        final tok = 'S008DI-${v.id}-PENDING';
        final mode = _before ? 'before' : 'strict';
        _out('D440 $tok begin mode=$mode phase=${Platform.environment['DU1_VQ_PHASE'] ?? '(unset)'} env=$_envLine manifest=$_manifest');
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
        _out('D440 $tok att neg emptyOk=$negEmpty clipOk=$negClip maxCaught=$negMax');
        must('판정기 음성 3종', !negEmpty && !negClip && negMax, '빈 $negEmpty 잘림 $negClip 줄수밖 $negMax');

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
          _out('D440 $tok shot $sub ovf=${overflows.length}');
          await vqCapture(t, key, '${tok}_$sub', conditions: {
            'viewport': '${v.w.toInt()}x${v.h.toInt()}', 'textScaler': v.s, 'run': vqRun, 'manifest': _manifest, 'mode': mode, 'fixture': 'PENDING',
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
        await shot('1top', 'deadline-icons');

        // ── [DU440] 마감 아이콘 — 크기 · 첫 줄 정렬 · 색(값은 즉시) ──
        String iconLine(IconData icon, String key) {
          final iF = find.byIcon(icon, skipOffstage: false);
          if (iF.evaluate().length != 1) return '$key=n${iF.evaluate().length}';
          final ir = t.getRect(iF);
          final size = (t.widget(iF) as Icon).size ?? -1;
          final color = (t.widget(iF) as Icon).color;
          // 같은 줄 묶음의 마감 글(아이콘 오른쪽 · 가장 가까운 '마감 yyyy.MM.dd' 문단)
          final dl = rich((p) => RegExp(r'^마감 \d{4}\.\d{2}\.\d{2}$').hasMatch(p)).evaluate().toList();
          Element? best;
          var bestD = double.infinity;
          for (final e in dl) {
            final r = t.getRect(find.byElementPredicate((x) => identical(x, e), skipOffstage: false));
            final d = (r.left - ir.right).abs() + (r.top - ir.top).abs();
            if (r.left >= ir.right - 0.5 && d < bestD) {
              bestD = d;
              best = e;
            }
          }
          if (best == null) return '$key=nolabel';
          final rp = best.renderObject! as RenderParagraph;
          final tr = t.getRect(find.byElementPredicate((x) => identical(x, best), skipOffstage: false));
          final b0 = rp.getBoxesForSelection(const TextSelection(baseOffset: 0, extentOffset: 1)).first;
          final firstMid = tr.top + (b0.top + b0.bottom) / 2;
          final j = _judge(rp);
          final dFirst = ir.center.dy - firstMid;
          final fontPx = rp.textScaler.scale((rp.text.style?.fontSize) ?? 12);
          return '$key size=${_f2(size)} font=${_f2(fontPx)} dFirst=${_f2(dFirst)} lines=${j.lines.length} color=${color?.toARGB32().toRadixString(16)}';
        }

        final soon = iconLine(Icons.alarm, 'soon');
        final normal = iconLine(Icons.schedule, 'normal');
        double num(String line, String k) => double.tryParse(RegExp('$k=(-?[0-9.]+)').firstMatch(line)?.group(1) ?? '') ?? double.nan;
        _out('D440 $tok att icon soonSize=${_f2(num(soon, 'size'))} soonFont=${_f2(num(soon, 'font'))} soonD=${_f2(num(soon, 'dFirst'))} '
            'soonLines=${num(soon, 'lines').toInt()} normalSize=${_f2(num(normal, 'size'))} normalD=${_f2(num(normal, 'dFirst'))} '
            'normalLines=${num(normal, 'lines').toInt()}');
        _out('D440 $tok att raw soon=${soon.replaceAll(' ', '_').replaceAll('=', ':')} normal=${normal.replaceAll(' ', '_').replaceAll('=', ':')}');

        final soonSize = num(soon, 'size');
        final soonD = num(soon, 'dFirst');
        final normalSize = num(normal, 'size');
        final normalD = num(normal, 'dFirst');
        must('마감 아이콘 둘 측정', !soonSize.isNaN && !normalSize.isNaN, '$soon | $normal');
        // 크기는 바꾸지 않는다(DU361 규칙) — 두 모드 모두 iconSize(12) = W 10.8(0.9) · B 10.2(0.85).
        final want = v.id == 'B' ? 10.2 : 10.8;
        must('아이콘 크기 불변', (soonSize - want).abs() <= 0.05 && (normalSize - want).abs() <= 0.05,
            '${_f2(soonSize)} ${_f2(normalSize)} 기대 ${_f2(want)}');
        if (_before) {
          if (v.id == 'B') {
            // 음성 기대 — base 는 Row 기본(가운데)이라 마감 글이 두 줄이면 아이콘이 첫 줄 가운데에서 벗어난다.
            must('before B 첫 줄 벗어남 검출', soonD.abs() > 4 || normalD.abs() > 4, '${_f2(soonD)} ${_f2(normalD)}');
          }
        } else {
          must('strict 아이콘 = 첫 줄 가운데(±2)', soonD.abs() <= 2 && normalD.abs() <= 2, '${_f2(soonD)} ${_f2(normalD)}');
          must('strict 넘침 0', overflows.isEmpty, overflows.join(' | '));
        }

        // 임박 카드(두 번째 카드 · B 에서 첫 화면 밖)를 보이게 해 한 장 더 — 측정은 위에서 끝났다.
        await t.ensureVisible(find.byIcon(Icons.alarm, skipOffstage: false));
        for (var i = 0; i < 10; i++) {
          await t.pump(const Duration(milliseconds: 50));
        }
        await shot('2soon', 'deadline-soon');
        must('미처리 framework 예외 0', fwErrors.isEmpty, '오류 $fwErrors');
        final exc = t.takeException();
        _out('D440 $tok done state=PENDING mode=$mode captures=$shots overflows=${overflows.length} exc=${exc != null} ovfRaw=${overflows.isEmpty ? '-' : base64Url.encode(utf8.encode(overflows.join('\n'))).replaceAll('=', '')}');
        must('끝 예외 0', exc == null, '예외 $exc');
      } catch (e) {
        _anyFail = true;
        rethrow;
      }
    }, skip: !_optIn);
  }
}
