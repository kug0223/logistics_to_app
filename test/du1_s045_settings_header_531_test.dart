// ignore_for_file: depend_on_referenced_packages
// [DU531 · 표시만] 설정 화면(lib/screens/common/settings_screen.dart) 머리 카드 — 감사128 V2.
//   지원자 경로의 진한 brand 면 · 흰 글 · 반투명 통계 칸을 관리자와 같은 옅은 brand 면 · 진한 글 · 흰 통계 칸으로. 역할 칩은 두 경로 모두 같은 중립.
//   before = 현재 A(settings_screen 8a958cb5) 기록 · strict = 후보. 상태 USER(지원자) · SUB(서브관리자 · 지원자 모드) ·
//   SUBADM(서브관리자 · 관리자 모드) · BA(사업장 관리자) × W/B. 하네스 · 채널 대역 · 줄 형식 = DU525 r2 / DU529 시험.
//   누르는 것 0 · 끄는 것 0(머리는 첫 화면에 있다). 통계 값은 대역 사용자(근무 12일 · 평점 4.5 · 지각 1회 · 노쇼 0회).
//   기본 skip — TB before/du531-tb/DU_BEFORE_OBSERVE=531 · TA after/du531-ta/없음.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ALfit/models/core/business_member_model.dart';
import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/providers/notification_provider.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/screens/common/settings_screen.dart';
import 'package:ALfit/theme/app_colors.dart';
import 'package:ALfit/theme/role_theme.dart';
import 'package:ALfit/utils/text_layout.dart';

import 'support/du1_vq_capture.dart';

/// 1×1 PNG(유효) — settings_broken_image_fallback_test.dart 와 같은 값.
const _png = 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAC'
    'hwGA60e6kgAAAABJRU5ErkJggg==';

class _FakeApp extends Fake with MockPlatformInterfaceMixin implements FirebaseAppPlatform {
  @override
  String get name => defaultFirebaseAppName;
  @override
  FirebaseOptions get options =>
      const FirebaseOptions(apiKey: 'k', appId: 'a', messagingSenderId: 's', projectId: 'p', storageBucket: 'p.appspot.com');
}

class _FakeCore extends FirebasePlatform with MockPlatformInterfaceMixin {
  @override
  FirebaseAppPlatform app([String name = defaultFirebaseAppName]) => _FakeApp();
  @override
  Future<FirebaseAppPlatform> initializeApp({String? name, FirebaseOptions? options}) async => _FakeApp();
  @override
  List<FirebaseAppPlatform> get apps => [_FakeApp()];
}

/// 역할 대역 — BA = 사업장 관리자 · USER = 지원자 · SUB = 서브관리자(지원자 모드) · SUBADM = 서브관리자(관리자 모드).
class _P extends UserProvider {
  _P(this.scene, this.who);

  final String scene;
  final String who;

  @override
  UserModel? get currentUser => UserModel(
        uid: 'u1',
        username: 'u1',
        name: who,
        email: 'u1@alfit.local',
        role: scene == 'BA' ? UserRole.BUSINESS_ADMIN : UserRole.USER,
        managedBusinessIds: scene == 'BA' ? const ['biz1'] : const [],
        subAdminBusinessIds: scene.startsWith('SUB') ? const ['biz1'] : const [],
        sealBase64: scene == 'BA' ? _png : null,
        sealType: 'stamp',
        signatureBase64: scene == 'BA' ? null : _png,
        totalWorkDays: 12,
        averageRating: 4.5,
        recentLateCount: 1,
        recentNoShowCount: 0,
      );

  @override
  bool get isAdminMode => scene == 'SUBADM';

  @override
  String? get effectiveBusinessId => 'biz1';

  @override
  PermissionCheck checkCurrentBusiness(bool Function(MemberPermissions p) check) => PermissionCheck.allowed;

  @override
  bool can(bool Function(MemberPermissions p) check) => true;
}

void _out(String s) {
  // ignore: avoid_print
  print(s);
}

String _enc(String s) => s.isEmpty ? '-' : base64Url.encode(utf8.encode(s)).replaceAll('=', '');
String _hex(Color? c) => c == null ? 'none' : (c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase();
String _hex8(Color? c) => c == null ? 'none' : c.toARGB32().toRadixString(16).padLeft(8, '0').toUpperCase();
String _rc(Rect r) =>
    '${r.left.toStringAsFixed(1)},${r.top.toStringAsFixed(1)},${r.width.toStringAsFixed(1)},${r.height.toStringAsFixed(1)}';

double _lum(Color c) {
  double ch(double v) => v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * ch(c.r) + 0.7152 * ch(c.g) + 0.0722 * ch(c.b);
}

double _contrast(Color a, Color b) {
  final x = _lum(a);
  final y = _lum(b);
  return (math.max(x, y) + 0.05) / (math.min(x, y) + 0.05);
}

/// BoxDecoration 의 모서리 반경(네 귀가 같은 BorderRadius 일 때 왼쪽 위 값) — 아니면 null.
double? _radiusOf(Decoration? d) {
  if (d is! BoxDecoration) return null;
  final r = d.borderRadius;
  return r is BorderRadius ? r.topLeft.x : null;
}

Color? _faceOf(Decoration? d) => d is BoxDecoration ? d.color : null;

/// 이 요소가 놓인 실제 바탕색 — 조상의 칠(DecoratedBox · ColoredBox · 불투명 Material)을 안쪽부터 모아, 처음 만난 불투명 색 위에 차례로 겹친다.
///   Container 는 세지 않는다(안에서 DecoratedBox/ColoredBox 를 만들어 두 번 세게 된다). 투명(알파 0) · 투명 Material 은 건너뛴다.
Color _surfaceOf(Element e) {
  final layers = <Color>[];
  Color base = Colors.white;
  e.visitAncestorElements((a) {
    final w = a.widget;
    Color? c;
    if (w is ColoredBox) {
      c = w.color;
    } else if (w is DecoratedBox) {
      c = _faceOf(w.decoration);
    } else if (w is Material && w.type != MaterialType.transparency) {
      c = w.color;
    }
    if (c != null && c.a > 0) {
      if (c.a >= 1) {
        base = c;
        return false;
      }
      layers.add(c);
    }
    return true;
  });
  var out = base;
  for (final l in layers.reversed) {
    out = Color.alphaBlend(l, out);
  }
  return out;
}

/// 글자 요소 하나의 (글자색 · 놓인 바탕 · 대비) — 반투명 글자는 바탕에 겹친 뒤 잰다.
({Color? fg, Color bg, double ratio}) _ink(Element richText) {
  final fg = (richText.renderObject! as RenderParagraph).text.style?.color;
  final bg = _surfaceOf(richText);
  final ratio = fg == null ? 0.0 : _contrast(Color.alphaBlend(fg, bg), bg);
  return (fg: fg, bg: bg, ratio: ratio);
}

/// 시각 오류 수집 — 넘침은 원문 + 위치, 그 밖 framework 오류도 원문.
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

typedef _V = ({String id, double w, double h, double s});
const _views = <_V>[(id: 'W', w: 390.0, h: 844.0, s: 1.0), (id: 'B', w: 320.0, h: 640.0, s: 2.0)];
const _cases = <({String id, int shots})>[(id: 'USER', shots: 1), (id: 'SUB', shots: 1), (id: 'SUBADM', shots: 1), (id: 'BA', shots: 1)];
const _who = <String, String>{'USER': '김지원', 'SUB': '박서브관리자긴이름테스트', 'SUBADM': '박서브관리자긴이름테스트', 'BA': 'QA 관리자'};
const _statWords = '12일|근무|4.5|평점|1회|지각(90일)|0회|노쇼(90일)';

final bool _before = Platform.environment['DU_BEFORE_OBSERVE'] == '531';
final Map<String, String> _env = Platform.environment;
final bool _optIn =
    (_env['DU1_VQ_PHASE'] == 'before' && _env['DU1_VQ_RUN'] == 'du531-tb' && _env['DU_BEFORE_OBSERVE'] == '531') ||
        (_env['DU1_VQ_PHASE'] == 'after' && _env['DU1_VQ_RUN'] == 'du531-ta' && _env['DU_BEFORE_OBSERVE'] == null);
String? _halt;
final String _manifest = Platform.environment['DUL_MANIFEST'] ?? '(unset)';
const _envKeys = ['DU_BEFORE_OBSERVE', 'DU1_VQ_PHASE', 'DU1_VQ_OUT', 'DU1_VQ_RUN', 'DU1_VQ_DATE', 'DU397_DIAG', 'DU397_MANIFEST', 'DU400_MANIFEST',
  'DU401_MANIFEST', 'DU398_MANIFEST', 'DU406_MANIFEST', 'DU407_MANIFEST', 'DU296_PHASE', 'DUL_MANIFEST'];
final String _envLine = [for (final k in _envKeys) '$k:${Platform.environment[k] ?? '(unset)'}'].join(',');

void main() {
  // 플랫폼 응답 — 알림 권한 = 거부(0 → 사용자 문서 조회 없음) · 앱 버전 = 대역 값(DU525 r2 와 같다). 이 시험은 누르지 않는다.
  const permChannel = MethodChannel('flutter.baseflow.com/permissions/methods');
  final permCalls = <String>[];
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    PackageInfo.setMockInitialValues(
        appName: 'ALfit', packageName: 'com.alfit.app', version: '1.0.0', buildNumber: '1', buildSignature: '');
    permCalls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(permChannel, (call) async {
      permCalls.add(call.method);
      return 0;
    });
  });
  tearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(permChannel, null));
  setUpAll(() async {
    await initializeDateFormatting('ko');
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
  });

  for (final v in _views) {
    for (final c in _cases) {
      testWidgets('S045SH-${v.id}-${c.id} 설정 머리 카드 — 지원자도 옅은 brand 면 · 역할 칩 중립 · 통계 칸 흰 면', (t) async {
        final tok = 'S045SH-${v.id}-${c.id}';
        if (_halt != null) fail('$tok 진입 0 — 앞 실패: $_halt');
        await t.runAsync(vqLoadFonts);
        final prevOnError = FlutterError.onError;
        addTearDown(() => FlutterError.onError = prevOnError);
        t.view.physicalSize = Size(v.w, v.h);
        t.view.devicePixelRatio = 1.0;
        addTearDown(t.view.reset);
        final mode = _before ? 'before' : 'strict';
        _out('D531 $tok begin mode=$mode phase=${Platform.environment['DU1_VQ_PHASE'] ?? '(unset)'} env=$_envLine manifest=$_manifest');
        final who = _who[c.id] ?? '';
        final isBa = c.id == 'BA';
        final seen = _Seen();
        void need(String k, bool ok, [String why = '']) => expect(ok, isTrue, reason: '$tok $k $why');
        final checks = <(String, bool, String)>[];
        void chk(String k, bool ok, [String why = '']) => checks.add((k, ok, why));
        Object? failure;
        StackTrace? failureSt;
        var shots = 0;
        var raw = '';
        try {
          FlutterError.onError = seen.add;
          final key = GlobalKey();
          await t.pumpWidget(MultiProvider(
            providers: [
              ChangeNotifierProvider<UserProvider>.value(value: _P(c.id, who)),
              ChangeNotifierProvider<NotificationProvider>(create: (_) => NotificationProvider()),
            ],
            child: RepaintBoundary(
              key: key,
              child: MaterialApp(
                debugShowCheckedModeBanner: false,
                theme: c.id == 'BA' || c.id == 'SUBADM' ? RoleTheme.businessAdminTheme : RoleTheme.workerTheme,
                locale: const Locale('ko', 'KR'),
                supportedLocales: const [Locale('ko', 'KR'), Locale('en', 'US')],
                localizationsDelegates: const [
                  GlobalMaterialLocalizations.delegate,
                  GlobalWidgetsLocalizations.delegate,
                  GlobalCupertinoLocalizations.delegate,
                ],
                builder: (ctx, child) =>
                    MediaQuery(data: MediaQuery.of(ctx).copyWith(textScaler: TextScaler.linear(v.s)), child: child!),
                home: const SettingsScreen(),
              ),
            ),
          ));
          for (var i = 0; i < 20; i++) {
            await t.pump(const Duration(milliseconds: 80));
          }
          final nScreen = find.byType(SettingsScreen).evaluate().length;
          need('설정 화면 1', nScreen == 1, '개수 $nScreen');
          Future<void> shot(String id, String state) async {
            _out('D531 $tok shot $id ovf=${seen.overflows.length}');
            await vqCapture(t, key, '${tok}_$id', conditions: {
              'viewport': '${v.w.toInt()}x${v.h.toInt()}', 'textScaler': v.s, 'run': vqRun, 'manifest': _manifest, 'mode': mode,
              'fixture': c.id, 'state': state,
            });
            shots++;
          }

          Finder label(String s) => find.byWidgetPredicate((w) => w is Text && TextLayout.plain(w.data ?? '') == s, skipOffstage: true);
          // 카드 안에서 글 하나의 RichText 요소(Text → RichText 첫째).
          Element richOf(Finder textF) => find.descendant(of: textF, matching: find.byType(RichText), skipOffstage: true).evaluate().first;

          // ── 머리 카드(모서리 16 Container — 이름 글의 가장 가까운 조상)
          final nameF = label(who);
          final nName = nameF.evaluate().length;
          need('이름 글 1', nName == 1, '개수 $nName');
          final cardsF = find.ancestor(of: nameF, matching: find.byWidgetPredicate((w) => w is Container && _radiusOf(w.decoration) == 16));
          final nCards = cardsF.evaluate().length;
          need('머리 카드(모서리 16) ≥1', nCards >= 1, '개수 $nCards');
          final cardF = cardsF.first;
          final cardEl = cardF.evaluate().first;
          final cardDec = t.widget<Container>(cardF).decoration;
          final rawFace = _faceOf(cardDec);
          final cardBorder = cardDec is BoxDecoration ? cardDec.border : null;
          final edge = cardBorder is Border ? cardBorder.top.color : null;
          final under = _surfaceOf(cardEl);
          final face = rawFace == null ? under : Color.alphaBlend(rawFace, under);
          final primary = Theme.of(cardEl).primaryColor;
          final wantFace = primary.withValues(alpha: 0.06);
          final wantEdge = primary.withValues(alpha: 0.16);
          final cardRect = t.getRect(cardF);
          // 카드 안 모든 글(아이콘 글리프 제외) — 글자색 · 놓인 바탕 · 대비
          var nText = 0;
          var minRatio = 99.0;
          var worst = '';
          for (final e in find.descendant(of: cardF, matching: find.byType(RichText), skipOffstage: true).evaluate()) {
            var inIcon = false;
            e.visitAncestorElements((a) {
              if (a.widget is Icon) {
                inIcon = true;
                return false;
              }
              return a != cardEl;
            });
            if (inIcon) continue;
            final k = _ink(e);
            nText++;
            if (k.ratio < minRatio) {
              minRatio = k.ratio;
              worst = '${(e.renderObject! as RenderParagraph).text.toPlainText()} fg ${_hex8(k.fg)} bg ${_hex(k.bg)}';
            }
          }
          final nameInk = _ink(richOf(nameF));
          final subF = find.descendant(of: cardF, matching: label('@u1'), skipOffstage: true);
          final nSub = subF.evaluate().length;
          need('@아이디 글 1', nSub == 1, '개수 $nSub');
          final subInk = _ink(richOf(subF));
          final wantN = isBa ? 3 : 11;
          raw = 'head face ${_hex(face)} raw ${_hex8(rawFace)} edge ${_hex8(edge)} under ${_hex(under)} n $nText min ${minRatio.toStringAsFixed(2)} '
              'worst [$worst] name ${_hex8(nameInk.fg)} sub ${_hex8(subInk.fg)} card $cardRect';
          _out('D531 $tok att head face=${_hex(face)} raw=${_hex8(rawFace)} edge=${_hex8(edge)} n=$nText minratio=${minRatio.toStringAsFixed(2)} '
              'name=${_hex(nameInk.fg)} sub=${_hex(subInk.fg)} card=${_rc(cardRect)}');
          chk('머리 글 수 = 기대', nText == wantN, 'n $nText want $wantN');
          if (!_before) {
            chk('strict 머리 면 = 옅은 brand(주색 6%) · 테두리 주색 16% — 네 상태 같은 토큰',
                rawFace?.toARGB32() == wantFace.toARGB32() && edge?.toARGB32() == wantEdge.toARGB32(), raw);
            chk('strict 이름 textPrimary · @아이디 textSecondary', nameInk.fg == AppColors.textPrimary && subInk.fg == AppColors.textSecondary, raw);
            chk('strict 머리 안 모든 글 대비 ≥4.5', minRatio >= 4.5, raw);
          }

          // ── 아바타(사진 없음 → 사람 아이콘) — 아이콘색 · 원 면 · 크기
          final avaF = find.descendant(of: cardF, matching: find.byIcon(Icons.person), skipOffstage: true);
          final nAva = avaF.evaluate().length;
          // BA 는 칩 아이콘이 admin_panel_settings 라 사람 아이콘 1 · 지원자 계열은 아바타 + 칩(W 칩 있음) = 1 또는 2. 첫째가 아바타다.
          need('사람 아이콘 ≥1', nAva >= 1, '개수 $nAva');
          final avaIcon = t.widget<Icon>(avaF.first).color;
          final avaBoxF = find.ancestor(of: avaF.first, matching: find.byType(Container)).first;
          final avaDisc = _faceOf(t.widget<Container>(avaBoxF).decoration);
          final avaRect = t.getRect(avaBoxF);
          raw = '$raw | ava icon ${_hex8(avaIcon)} disc ${_hex8(avaDisc)} rect $avaRect';
          _out('D531 $tok att ava icon=${_hex(avaIcon)} disc=${_hex8(avaDisc)} size=${avaRect.width.toStringAsFixed(1)}');
          if (!_before) {
            chk('strict 아바타 — 아이콘 주색 · 원 면 주색 10%',
                avaIcon?.toARGB32() == primary.toARGB32() && avaDisc?.toARGB32() == primary.withValues(alpha: 0.10).toARGB32(), raw);
          }

          // ── 역할 칩(역할명 글) — 글자색 · 놓인 바탕 · 대비. 큰 글자(B)에서는 칩 면 없이 글자만 둔다(기존 규칙).
          final roleName = isBa ? '사업장 관리자' : '지원자';
          final roleF = find.descendant(of: cardF, matching: label(roleName), skipOffstage: true);
          final nRole = roleF.evaluate().length;
          need('역할명 글 1', nRole == 1, '개수 $nRole');
          final roleInk = _ink(richOf(roleF));
          final chipBoxes = find.ancestor(of: roleF, matching: find.byWidgetPredicate((w) => w is Container && _radiusOf(w.decoration) == 12));
          final boxed = chipBoxes.evaluate().isNotEmpty;
          final chipRect = boxed ? t.getRect(chipBoxes.first) : t.getRect(roleF);
          raw = '$raw | chip fg ${_hex8(roleInk.fg)} bg ${_hex(roleInk.bg)} ratio ${roleInk.ratio.toStringAsFixed(2)} boxed $boxed rect $chipRect';
          _out('D531 $tok att chip fg=${_hex(roleInk.fg)} bg=${_hex(roleInk.bg)} ratio=${roleInk.ratio.toStringAsFixed(2)} boxed=$boxed '
              'h=${chipRect.height.toStringAsFixed(1)}');
          if (!_before) {
            chk('strict 역할 칩 — 글 textSecondary(중립) · 칩이 있으면 흰 면 · 대비 ≥4.5',
                roleInk.fg == AppColors.textSecondary && (!boxed || roleInk.bg.toARGB32() == Colors.white.toARGB32()) && roleInk.ratio >= 4.5, raw);
          }

          // ── 지원자 통계 칸(BA 는 없다) — 칸 면 · 값/이름 글자색 · 대비 · 글 집합(순서 포함)
          final workF = find.descendant(of: cardF, matching: label('근무'), skipOffstage: true);
          final nWork = workF.evaluate().length;
          need('통계 이름 글(근무) = 기대', nWork == (isBa ? 0 : 1), '개수 $nWork');
          if (!isBa) {
            final wrapF = find.ancestor(of: workF, matching: find.byType(Wrap)).first;
            final boxF = find.ancestor(of: wrapF, matching: find.byWidgetPredicate((w) => w is Container && _radiusOf(w.decoration) == 10));
            final nBox = boxF.evaluate().length;
            need('통계 칸(모서리 10) ≥1', nBox >= 1, '개수 $nBox');
            final boxRaw = _faceOf(t.widget<Container>(boxF.first).decoration);
            final boxRect = t.getRect(boxF.first);
            final words = <String>[];
            var statMin = 99.0;
            for (final e in find.descendant(of: wrapF, matching: find.byType(Text), skipOffstage: true).evaluate()) {
              words.add(TextLayout.plain((e.widget as Text).data ?? ''));
            }
            for (final e in find.descendant(of: wrapF, matching: find.byType(RichText), skipOffstage: true).evaluate()) {
              final k = _ink(e);
              if (k.ratio < statMin) statMin = k.ratio;
            }
            final wordsJoined = words.join('|');
            final valF = find.descendant(of: wrapF, matching: label('12일'), skipOffstage: true);
            final nVal = valF.evaluate().length;
            need('통계 값 글(12일) 1', nVal == 1, '개수 $nVal');
            final valInk = _ink(richOf(valF));
            final labInk = _ink(richOf(workF));
            raw = '$raw | stat box ${_hex8(boxRaw)} val ${_hex8(valInk.fg)} lab ${_hex8(labInk.fg)} on ${_hex(valInk.bg)} min ${statMin.toStringAsFixed(2)} '
                'rect $boxRect words $wordsJoined';
            _out('D531 $tok att stat box=${_hex8(boxRaw)} val=${_hex(valInk.fg)} lab=${_hex(labInk.fg)} minratio=${statMin.toStringAsFixed(2)} '
                'h=${boxRect.height.toStringAsFixed(1)} words=${_enc(wordsJoined)}');
            chk('통계 글 집합 · 순서 = 근무 · 평점 · 지각 · 노쇼(값 → 이름)', wordsJoined == _statWords, wordsJoined);
            if (!_before) {
              chk('strict 통계 칸 — 흰 면 · 값 textPrimary · 이름 textSecondary · 대비 ≥4.5',
                  boxRaw?.toARGB32() == Colors.white.toARGB32() && valInk.fg == AppColors.textPrimary && labInk.fg == AppColors.textSecondary &&
                      statMin >= 4.5, raw);
            }
          }
          await shot('1head', 'header-card');
        } catch (e, st) {
          failure = e;
          failureSt = st;
        } finally {
          FlutterError.onError = prevOnError;
        }

        // 공통 정리 — 화면을 내리고 남은 timer 가 끝날 시간을 준다.
        var cleanupErr = '';
        try {
          await t.pumpWidget(const SizedBox.shrink());
          for (var i = 0; i < 6; i++) {
            await t.pump(const Duration(seconds: 1));
          }
        } catch (e, st) {
          cleanupErr = e.toString();
          if (failure == null) {
            failure = e;
            failureSt = st;
          }
        }
        final exc = t.takeException();
        if (exc != null && failure == null) {
          failure = exc;
          failureSt = StackTrace.current;
        }
        final nOvf = seen.overflows.length;
        final nFw = seen.other.length;
        final ovfRaw = seen.overflows.join('\n----\n');
        final fwRaw = seen.other.join('\n----\n');
        _out('R531 $tok raw m64=${_enc(raw)} ovf64=${_enc(ovfRaw)} fw64=${_enc(fwRaw)} cleanup64=${_enc(cleanupErr)} '
            'fail64=${_enc(failure?.toString() ?? '')} perm64=${_enc(permCalls.join(','))}');
        _out('D531 $tok done state=${c.id} mode=$mode captures=$shots overflows=$nOvf exc=${exc != null}');

        final f0 = failure;
        if (f0 != null) {
          _halt ??= '$tok ${f0.toString().split('\n').first}';
          Error.throwWithStackTrace(f0, failureSt ?? StackTrace.current);
        }
        // 넘침 — W 는 strict 0. B 는 기존 넘침이 있을 수 있어 기록만(shot · done 줄의 ovf/overflows 를 TB 와 대조한다).
        if (!_before && v.id == 'W') chk('strict W 넘침 0', nOvf == 0, ovfRaw);
        chk('미처리 framework 예외 0', nFw == 0, fwRaw);
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
