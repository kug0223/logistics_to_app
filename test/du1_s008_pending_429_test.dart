// [DU429 · 소급 셀 · 표시만] S008 리뷰 관리 '미작성' 탭 — 탭 · 구분 · 요청 카드 글자 대비, 만료 카드 Opacity 제거, 임박 버튼 브랜드, 마감 글 줄바꿈.
//   before = 현재 A(8ce225fa) / strict = 후보(1e7a5c91). 데이터 · 마감 판정 · 콜백 · 문구 그대로.
//   host: admin_review_nested_response_test 의 cloud_functions 채널 대역과 같은 꼴(목록 2 callable 만 · 작성 경로 호출 0).
//   기본 skip — lkit 단계 env 정확 조합(TB before/du429-tb/DU_BEFORE_OBSERVE=429 · TA after/du429-ta/없음)일 때만 돈다.
//   장면: 뷰 W 390x844@1.0 · B 320x640@2.0 × PENDING(보통 · 임박 · 만료 3장) = 공개 2.
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
import 'package:ALfit/theme/app_colors.dart';
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

Map<String, Object?> _req(String id, String name, Duration toDeadline) => <String, Object?>{
      'id': id,
      'requestKey': 'BIZ_${id}_${_now.year}_${_now.month}',
      'businessId': 'BIZ',
      'businessName': 'QA 사업장',
      'workerId': 'W$id',
      'workerName': name,
      'reviewYear': _now.year,
      'reviewMonth': _now.month,
      'deadline': _ts(_now.add(toDeadline)),
      'adminStatus': 'pending',
      'workerStatus': 'pending',
      'isPublished': false,
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
      return ok({
        'reviewRequests': <Object?>[
          _req('R1', '합성 보통', const Duration(days: 10)),
          _req('R2', '합성 임박', const Duration(days: 2)),
          _req('R3', '합성 만료', const Duration(days: -2)),
        ],
      });
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

final bool _before = Platform.environment['DU_BEFORE_OBSERVE'] == '429';
final Map<String, String> _env = Platform.environment;
final bool _optIn =
    (_env['DU1_VQ_PHASE'] == 'before' && _env['DU1_VQ_RUN'] == 'du429-tb' && _env['DU_BEFORE_OBSERVE'] == '429') ||
        (_env['DU1_VQ_PHASE'] == 'after' && _env['DU1_VQ_RUN'] == 'du429-ta' && _env['DU_BEFORE_OBSERVE'] == null);
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
  'grey400': AppColors.grey400, 'grey500': AppColors.grey500, 'textSecondary': AppColors.textSecondary, 'textTertiary': AppColors.textTertiary,
  'error': AppColors.error, 'errorDark': AppColors.errorDark, 'brand': AppColors.brand,
};
String _tok(Color? c) {
  if (c == null) return 'null';
  for (final e in _tokens.entries) {
    if (e.value.toARGB32() == c.toARGB32()) return e.key;
  }
  return 'x${c.toARGB32().toRadixString(16)}';
}

final String _zwsp = String.fromCharCode(0x200B);
final String _wj = String.fromCharCode(0x2060);
final String _nbsp = String.fromCharCode(0x00A0);
bool _visible(String ch) => ch.trim().isNotEmpty && ch != _zwsp && ch != _wj && ch != _nbsp;

/// 문단의 실제 줄(DU428 _breaks 와 같은 식) — 보이는 글자 상자 누락 · 상자 0 이면 ok=false.
({List<String> lines, bool ok, int visMissing}) _breaks(RenderParagraph rp) {
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
    var k = tops.indexWhere((x) => (x - boxes.first.top).abs() < 0.5);
    if (k < 0) {
      tops.add(boxes.first.top);
      k = tops.length - 1;
    }
    lineOf[i] = k;
  }
  if (tops.isEmpty) return (lines: const <String>[], ok: false, visMissing: visMissing);
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
  return (lines: [for (final b in buf) TextLayout.plain(b.toString()).trim()], ok: ok && visMissing == 0, visMissing: visMissing);
}

bool _paraOk(RenderParagraph rp) => !rp.didExceedMaxLines && rp.size.height + 0.5 >= rp.getMaxIntrinsicHeight(rp.size.width);
String _w(List<String> lines) => lines.map((x) => x.replaceAll(' ', '_')).join('|');

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
  });

  const views = [(id: 'W', w: 390.0, h: 844.0, s: 1.0), (id: 'B', w: 320.0, h: 640.0, s: 2.0)];
  for (final v in views) {
    testWidgets('S008RP-${v.id}-PENDING 리뷰 관리 미작성 탭 — 보통 · 임박 · 만료 카드 글자 대비 · 만료 흐림 · 임박 버튼 · 마감 줄바꿈', (t) async {
      if (_anyFail) fail('앞 사례 실패 — 이 사례 본문 실행 0 · 캡처 0');
      try {
        final tok = 'S008RP-${v.id}-PENDING';
        final mode = _before ? 'before' : 'strict';
        _out('D429 $tok begin mode=$mode phase=${Platform.environment['DU1_VQ_PHASE'] ?? '(unset)'} env=$_envLine manifest=$_manifest');
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
        _stubAuthChannels(t);
        _calls.clear();
        t.binding.defaultBinaryMessenger.setMockMessageHandler(_channel, _handle);
        addTearDown(() => t.binding.defaultBinaryMessenger.setMockMessageHandler(_channel, null));
        void must(String k, bool ok, [String why = '']) => expect(ok, isTrue, reason: '$tok $k $why');
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
        final pendTab = find.descendant(of: tabBar, matching: rich((p) => p == '미작성'), skipOffstage: false);
        must('미작성 탭 글자 1', pendTab.evaluate().length == 1, '${pendTab.evaluate().length}개');
        await t.tap(pendTab);
        for (var i = 0; i < 20; i++) {
          await t.pump(const Duration(milliseconds: 50));
        }
        final unselF = find.descendant(of: tabBar, matching: rich((p) => p == '받음'), skipOffstage: false);
        must('받음 탭 글자 1', unselF.evaluate().length == 1);
        final tabUnsel = _tok((t.widget(unselF) as RichText).text.style?.color);

        // 미작성 탭 본문(가장 큰 세로 Scrollable)
        final all = find.byType(Scrollable);
        final vs = [for (var i = 0; i < all.evaluate().length; i++) all.at(i)]
            .where((f) => t.state<ScrollableState>(f).position.axis == Axis.vertical && t.getRect(f).width > 0 && t.getRect(f).left >= -0.5 &&
                t.getRect(f).left < v.w - 1)
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
          _out('D429 $tok shot $sub ovf=${overflows.length}');
          await vqCapture(t, key, '${tok}_$sub', conditions: {
            'viewport': '${v.w.toInt()}x${v.h.toInt()}', 'textScaler': v.s, 'run': vqRun, 'manifest': _manifest, 'mode': mode, 'fixture': 'PENDING',
            'state': state,
          });
          shots++;
        }

        await shot('1top', 'pending-top');
        var paraAll = true, visAll = true, wrapAll = true, semAll = true;
        var paraN = 0;
        void judge(Finder rf) {
          paraN++;
          final rp = t.renderObject(rf) as RenderParagraph;
          paraAll = paraAll && _paraOk(rp);
          final b = _breaks(rp);
          visAll = visAll && b.visMissing == 0;
          wrapAll = wrapAll && b.ok;
          final textF = find.ancestor(of: rf, matching: find.byType(Text, skipOffstage: false)).first;
          final label = (t.widget(textF) as Text).semanticsLabel;
          if (label != null) {
            final node = t.getSemantics(rf).label;
            semAll = semAll && node.contains(label) && !node.contains(_wj) && !node.contains(_zwsp);
          }
        }

        final cards = <String, Map<String, String>>{};
        var deadlineLines = '';
        for (final (k, name) in const [('normal', '합성 보통'), ('soon', '합성 임박'), ('expired', '합성 만료')]) {
          final nameF = rich((p) => p == name);
          await reach(nameF);
          must('$k 이름 1', nameF.evaluate().length == 1);
          final cardF = find.ancestor(
              of: nameF,
              matching: find.byWidgetPredicate(
                  (w) => w is Container && w.decoration is BoxDecoration && (w.decoration! as BoxDecoration).borderRadius == BorderRadius.circular(16),
                  skipOffstage: false)).first;
          var op = 1.0;
          nameF.evaluate().single.visitAncestorElements((e) {
            final w = e.widget;
            if (w is Opacity) op *= w.opacity;
            return true;
          });
          final periodF = find.descendant(of: cardF, matching: rich((p) => p == '${_now.year}년 ${_now.month}월'), skipOffstage: false);
          final dlF = find.descendant(of: cardF, matching: rich((p) => p.startsWith('마감 ') || p == '기한 만료'), skipOffstage: false);
          must('$k 기간 · 마감 글 각 1', periodF.evaluate().length == 1 && dlF.evaluate().length == 1);
          final iconF = find.descendant(of: cardF, matching: find.byWidgetPredicate((w) => w is Icon && w.size != null && w.color != null, skipOffstage: false),
              skipOffstage: false);
          final icons = iconF.evaluate().map((e) => e.widget as Icon).where((i) => i.icon == Icons.alarm || i.icon == Icons.schedule || i.icon == Icons.event_busy).toList();
          must('$k 마감 아이콘 1', icons.length == 1, '${icons.length}개');
          final btnF = find.descendant(of: cardF, matching: find.byWidgetPredicate((w) => w is ElevatedButton, skipOffstage: false), skipOffstage: false);
          var btn = 'none';
          if (btnF.evaluate().isNotEmpty) {
            final st = (t.widget(btnF.first) as ElevatedButton).style;
            btn = _tok(st?.backgroundColor?.resolve(<WidgetState>{}));
            judge(find.descendant(of: btnF.first, matching: find.byType(RichText, skipOffstage: false), skipOffstage: false).first);
          }
          judge(nameF);
          judge(periodF);
          judge(dlF);
          final rpDl = t.renderObject(dlF) as RenderParagraph;
          if (k == 'soon') deadlineLines = _w(_breaks(rpDl).lines);
          cards[k] = {
            'name': _tok((t.widget(nameF) as RichText).text.style?.color),
            'period': _tok((t.widget(periodF) as RichText).text.style?.color),
            'dl': _tok((t.widget(dlF) as RichText).text.style?.color),
            'icon': _tok(icons.single.color),
            'btn': btn,
            'op': op.toStringAsFixed(2),
          };
        }
        final divF = rich((p) => p == '기한 만료');
        // '기한 만료' 는 구분 글자와 만료 카드 마감 글 두 곳이다 — 구분 글자는 카드 밖(조상에 반경 16 카드 없음).
        final divEls = divF.evaluate().where((e) {
          var inCard = false;
          e.visitAncestorElements((a) {
            final w = a.widget;
            if (w is Container && w.decoration is BoxDecoration && (w.decoration! as BoxDecoration).borderRadius == BorderRadius.circular(16)) {
              inCard = true;
              return false;
            }
            return true;
          });
          return !inCard;
        }).toList();
        must('기한 만료 구분 글자 1', divEls.length == 1, '${divEls.length}개');
        final div = _tok((divEls.single.widget as RichText).text.style?.color);
        await reach(rich((p) => p == '합성 만료'));
        await shot('2expired', 'pending-expired');
        String c(String k, String f) => cards[k]![f]!;
        _out('D429 $tok att tab unsel=$tabUnsel div=$div');
        _out('D429 $tok att normal name=${c('normal', 'name')} period=${c('normal', 'period')} dl=${c('normal', 'dl')} icon=${c('normal', 'icon')} btn=${c('normal', 'btn')} op=${c('normal', 'op')}');
        _out('D429 $tok att soon name=${c('soon', 'name')} period=${c('soon', 'period')} dl=${c('soon', 'dl')} icon=${c('soon', 'icon')} btn=${c('soon', 'btn')} op=${c('soon', 'op')}');
        _out('D429 $tok att expired name=${c('expired', 'name')} period=${c('expired', 'period')} dl=${c('expired', 'dl')} icon=${c('expired', 'icon')} btn=${c('expired', 'btn')} op=${c('expired', 'op')}');
        _out('D429 $tok att check n=$paraN para=$paraAll vis=$visAll wrap=$wrapAll sem=$semAll calls=${_calls.toSet().length}');
        _out('D429 $tok att lines soondl=$deadlineLines');
        must('작성 경로 호출 0(사용자 · 근태 조회 없음)', !_calls.contains('callableGetUsersBatch') && !_calls.contains('callableGetAdminAttendances'), '$_calls');
        must('문단 높이 · 보이는 글자 · 의미 라벨', paraAll && visAll && semAll, '$paraAll $visAll $semAll');
        if (!_before) {
          must('strict 탭 · 구분', tabUnsel == 'textSecondary' && div == 'textTertiary', '$tabUnsel $div');
          must('strict 보통', c('normal', 'period') == 'textSecondary' && c('normal', 'dl') == 'textSecondary' && c('normal', 'icon') == 'textSecondary' &&
              c('normal', 'btn') == 'brand' && c('normal', 'op') == '1.00', '카드 ${cards['normal']}');
          must('strict 임박', c('soon', 'period') == 'textSecondary' && c('soon', 'dl') == 'errorDark' && c('soon', 'icon') == 'error' &&
              c('soon', 'btn') == 'brand' && c('soon', 'op') == '1.00', '카드 ${cards['soon']}');
          must('strict 만료', c('expired', 'name') == 'textTertiary' && c('expired', 'period') == 'textSecondary' && c('expired', 'dl') == 'textTertiary' &&
              c('expired', 'icon') == 'textTertiary' && c('expired', 'btn') == 'none' && c('expired', 'op') == '1.00', '카드 ${cards['expired']}');
          must('strict 줄바꿈 경계', wrapAll, deadlineLines);
          must('strict 넘침 0', overflows.isEmpty, overflows.join(' | '));
        }
        must('미처리 framework 예외 0', fwErrors.isEmpty, '$fwErrors');
        final exc = t.takeException();
        _out('D429 $tok done state=PENDING mode=$mode captures=$shots overflows=${overflows.length} exc=${exc != null} ovfRaw=${overflows.isEmpty ? '-' : base64Url.encode(utf8.encode(overflows.join('\n'))).replaceAll('=', '')}');
        must('끝 예외 0', exc == null, '$exc');
      } catch (e) {
        _anyFail = true;
        rethrow;
      }
    }, skip: !_optIn);
  }
}
