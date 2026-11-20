// ignore_for_file: depend_on_referenced_packages
// [DU529 · 표시만] 설정 화면(lib/screens/common/settings_screen.dart) 색 예산 2차 — 감사128 L3 · L2.
//   L3: 탈퇴 흐름 첫째(체크리스트 '탈퇴 진행') · 둘째(비밀번호 '탈퇴하기') 버튼의 빨강 채움을 중립 외곽선으로. 셋째 최종 확인창의 빨강 채움은 그대로.
//   L2: 날인 방식 선택 탭의 선택 아이콘 · 글자 warningDark → brand.
//   before = 현재 A(settings_screen e8de662a) 기록 · strict = 후보. 상태 WD(탈퇴 3단계 · 막힘 없음) · BLK(첫째 시트 · 처리 필요 항목 → 버튼 비활성) ·
//   SEAL(사업장 관리자 날인 방식 탭) × W/B. 하네스 · 채널 대역 · 줄 형식 = DU525 r2 시험(du1_s045_settings_color_525_test.dart).
//   누르는 것: '회원탈퇴' 링크 → '탈퇴 진행' → (비밀번호 입력) '탈퇴하기'(시트) → 확인창 '취소' → 시트 '취소'. **확인창의 '탈퇴하기'는 누르지 않는다**
//   (탈퇴 서비스 호출 0). Functions 는 callableGetWithdrawBlockers 만 대역 응답하고 그 밖 이름은 오류 응답 + 기록한다.
//   기본 skip — TB before/du529-tb/DU_BEFORE_OBSERVE=529 · TA after/du529-ta/없음.
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

/// 역할 대역 — SEAL = 사업장 관리자(날인 등록 카드) · WD/BLK = 지원자(회원탈퇴 흐름).
class _P extends UserProvider {
  _P(this.scene);

  final String scene;

  @override
  UserModel? get currentUser => UserModel(
        uid: 'u1',
        username: 'u1',
        name: 'QA 관리자',
        email: 'u1@alfit.local',
        role: scene == 'SEAL' ? UserRole.BUSINESS_ADMIN : UserRole.USER,
        managedBusinessIds: scene == 'SEAL' ? const ['biz1'] : const [],
        sealBase64: scene == 'SEAL' ? _png : null,
        sealType: 'stamp',
        signatureBase64: scene == 'SEAL' ? null : _png,
      );

  @override
  bool get isAdminMode => false;

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

/// 빨강 계열 채움인가 — 토큰 이름에 기대지 않고 색 값으로 본다(error F44336 · errorDark B42318 모두 참).
bool _isRed(Color? c) => c != null && c.a > 0.5 && c.r > c.g + 0.25 && c.r > c.b + 0.25;

double _lum(Color c) {
  double ch(double v) => v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * ch(c.r) + 0.7152 * ch(c.g) + 0.0722 * ch(c.b);
}

double _contrast(Color a, Color b) {
  final x = _lum(a);
  final y = _lum(b);
  return (math.max(x, y) + 0.05) / (math.min(x, y) + 0.05);
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

/// 버튼 한 개의 측정값(측정 시점에 값으로 잡는다 — 뒤에 UI 를 다시 읽지 않는다).
typedef _B = ({Color? fill, Color? fg, Color? side, bool on, double ratio, Rect rect, bool inView});

typedef _V = ({String id, double w, double h, double s});
const _views = <_V>[(id: 'W', w: 390.0, h: 844.0, s: 1.0), (id: 'B', w: 320.0, h: 640.0, s: 2.0)];
const _cases = <({String id, int shots})>[(id: 'WD', shots: 3), (id: 'BLK', shots: 1), (id: 'SEAL', shots: 1)];

final bool _before = Platform.environment['DU_BEFORE_OBSERVE'] == '529';
final Map<String, String> _env = Platform.environment;
final bool _optIn =
    (_env['DU1_VQ_PHASE'] == 'before' && _env['DU1_VQ_RUN'] == 'du529-tb' && _env['DU_BEFORE_OBSERVE'] == '529') ||
        (_env['DU1_VQ_PHASE'] == 'after' && _env['DU1_VQ_RUN'] == 'du529-ta' && _env['DU_BEFORE_OBSERVE'] == null);
String? _halt;
final String _manifest = Platform.environment['DUL_MANIFEST'] ?? '(unset)';
const _envKeys = ['DU_BEFORE_OBSERVE', 'DU1_VQ_PHASE', 'DU1_VQ_OUT', 'DU1_VQ_RUN', 'DU1_VQ_DATE', 'DU397_DIAG', 'DU397_MANIFEST', 'DU400_MANIFEST',
  'DU401_MANIFEST', 'DU398_MANIFEST', 'DU406_MANIFEST', 'DU407_MANIFEST', 'DU296_PHASE', 'DUL_MANIFEST'];
final String _envLine = [for (final k in _envKeys) '$k:${Platform.environment[k] ?? '(unset)'}'].join(',');

void main() {
  // 플랫폼 응답 — 알림 권한 = 거부(0 → 사용자 문서 조회 없음 · settings_screen :195–201) · 앱 버전 = 대역 값(DU525 r2 와 같다).
  //   누른 뒤 부르는 것: '회원탈퇴' → Functions callableGetWithdrawBlockers(:1538–1543) 하나. 둘째 시트 · 최종 확인창은 열릴 때 호출 0
  //   (AuthService.deleteAccountWithPassword 는 확인창 '탈퇴하기' 승인 뒤 :2788–2789 — 이 시험은 그 버튼을 누르지 않는다).
  const permChannel = MethodChannel('flutter.baseflow.com/permissions/methods');
  const fnChannel = 'dev.flutter.pigeon.cloud_functions_platform_interface.CloudFunctionsHostApi.call';
  final permCalls = <String>[];
  final fnCalls = <String>[];
  var fnBlocks = <Object?>[];
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    PackageInfo.setMockInitialValues(
        appName: 'ALfit', packageName: 'com.alfit.app', version: '1.0.0', buildNumber: '1', buildSignature: '');
    permCalls.clear();
    fnCalls.clear();
    fnBlocks = <Object?>[];
    final m = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    m.setMockMethodCallHandler(permChannel, (call) async {
      permCalls.add(call.method);
      return 0;
    });
    m.setMockMessageHandler(fnChannel, (msg) async {
      const codec = StandardMessageCodec();
      final args = (codec.decodeMessage(msg) as List).first as Map;
      final name = args['functionName'].toString();
      fnCalls.add(name);
      if (name != 'callableGetWithdrawBlockers') {
        return codec.encodeMessage(<Object?>['not-found', 'du529-blocked', null]);
      }
      return codec.encodeMessage(<Object?>[
        <String, Object?>{'hardBlocks': fnBlocks, 'warnings': <Object?>[]},
      ]);
    });
  });
  tearDown(() {
    final m = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    m.setMockMethodCallHandler(permChannel, null);
    m.setMockMessageHandler(fnChannel, null);
  });
  setUpAll(() async {
    await initializeDateFormatting('ko');
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
  });

  for (final v in _views) {
    for (final c in _cases) {
      testWidgets('S045SD-${v.id}-${c.id} 설정 색 예산 2차 — 탈퇴 중간 단계 버튼 중립 · 날인 방식 선택색 brand', (t) async {
        final tok = 'S045SD-${v.id}-${c.id}';
        if (_halt != null) fail('$tok 진입 0 — 앞 실패: $_halt');
        await t.runAsync(vqLoadFonts);
        final prevOnError = FlutterError.onError;
        addTearDown(() => FlutterError.onError = prevOnError);
        t.view.physicalSize = Size(v.w, v.h);
        t.view.devicePixelRatio = 1.0;
        addTearDown(t.view.reset);
        final mode = _before ? 'before' : 'strict';
        _out('D529 $tok begin mode=$mode phase=${Platform.environment['DU1_VQ_PHASE'] ?? '(unset)'} env=$_envLine manifest=$_manifest');
        // BLK = 근로자 본인이 직접 풀 수 없는 막힘 1건(이동 버튼 없는 유형 — blockNavKey null).
        if (c.id == 'BLK') {
          fnBlocks = <Object?>[
            <String, Object?>{'type': 'PENDING_WAGES', 'count': 1},
          ];
        }
        final seen = _Seen();
        void need(String k, bool ok, [String why = '']) => expect(ok, isTrue, reason: '$tok $k $why');
        final checks = <(String, bool, String)>[];
        void chk(String k, bool ok, [String why = '']) => checks.add((k, ok, why));
        Object? failure;
        StackTrace? failureSt;
        var shots = 0;
        var raw = '';
        var fnSnap = '';
        try {
          FlutterError.onError = seen.add;
          final key = GlobalKey();
          await t.pumpWidget(MultiProvider(
            providers: [
              ChangeNotifierProvider<UserProvider>.value(value: _P(c.id)),
              ChangeNotifierProvider<NotificationProvider>(create: (_) => NotificationProvider()),
            ],
            child: RepaintBoundary(
              key: key,
              child: MaterialApp(
                debugShowCheckedModeBanner: false,
                theme: c.id == 'SEAL' ? RoleTheme.businessAdminTheme : RoleTheme.workerTheme,
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
          Future<void> settle([int n = 12]) async {
            for (var i = 0; i < n; i++) {
              await t.pump(const Duration(milliseconds: 80));
            }
          }

          await settle(20);
          final nScreen = find.byType(SettingsScreen).evaluate().length;
          need('설정 화면 1', nScreen == 1, '개수 $nScreen');
          Future<void> shot(String id, String state) async {
            _out('D529 $tok shot $id ovf=${seen.overflows.length}');
            await vqCapture(t, key, '${tok}_$id', conditions: {
              'viewport': '${v.w.toInt()}x${v.h.toInt()}', 'textScaler': v.s, 'run': vqRun, 'manifest': _manifest, 'mode': mode,
              'fixture': c.id, 'state': state,
            });
            shots++;
          }

          final listF = find.descendant(of: find.byType(SettingsScreen), matching: find.byType(Scrollable), skipOffstage: true).first;
          // 목록은 보이는 부분만 짓는다 — 대상이 나올 때까지 실제로 끈다.
          Future<void> bring(Finder f) async {
            await t.scrollUntilVisible(f, 120, scrollable: listF, maxScrolls: 80, duration: const Duration(milliseconds: 50));
            await settle(6);
          }

          Finder label(String s) => find.byWidgetPredicate((w) => w is Text && TextLayout.plain(w.data ?? '') == s, skipOffstage: true);
          Color? inkOf(Finder textF) =>
              t.renderObject<RenderParagraph>(find.descendant(of: textF, matching: find.byType(RichText), skipOffstage: true).first).text.style?.color;

          // 시트 안 버튼 — 가장 가까운 스크롤 칸 안으로 끌어온 뒤(화면 밖 rect 를 재지 않는다) 값으로 잡는다.
          Future<_B> button(Finder textF) async {
            await t.ensureVisible(textF);
            await settle(4);
            final btnF = find.ancestor(of: textF, matching: find.byWidgetPredicate((w) => w is ButtonStyleButton)).first;
            final btn = t.widget<ButtonStyleButton>(btnF);
            final on = btn.onPressed != null;
            final st = on ? <WidgetState>{} : <WidgetState>{WidgetState.disabled};
            final fill = btn.style?.backgroundColor?.resolve(st);
            final side = btn.style?.side?.resolve(st)?.color;
            final fg = inkOf(textF);
            final rect = t.getRect(btnF);
            final vp = t.getRect(find.ancestor(of: btnF, matching: find.byType(Scrollable)).first);
            final vis = vp.intersect(rect);
            final inView = vis.width >= rect.width - 0.5 && vis.height >= rect.height - 0.5;
            final ratio = fg == null ? 0.0 : _contrast(fg, fill ?? Colors.white);
            return (fill: fill, fg: fg, side: side, on: on, ratio: ratio, rect: rect, inView: inView);
          }

          // 루트(시트 · 확인창) 안에서 누를 수 있는 자리의 문구 집합(정렬 · '|' 로 이음).
          String labelsIn(Finder root, bool Function(Widget w) isAction) {
            final out = <String>[];
            for (final e in find.descendant(of: root, matching: find.byType(Text), skipOffstage: true).evaluate()) {
              var hit = false;
              e.visitAncestorElements((a) {
                if (isAction(a.widget)) {
                  hit = true;
                  return false;
                }
                return true;
              });
              if (hit) out.add(TextLayout.plain((e.widget as Text).data ?? ''));
            }
            out.sort();
            return out.join('|');
          }

          if (c.id == 'SEAL') {
            // ── 날인 방식 선택 탭(L2) — 선택 = '도장 이미지'(sealType stamp) · 비선택 = '직접 서명'
            final selF = label('도장 이미지');
            await bring(selF);
            final offF = label('직접 서명');
            final nSel = selF.evaluate().length;
            final nOff = offF.evaluate().length;
            need('날인 방식 탭 글 1 · 1', nSel == 1 && nOff == 1, '개수 $nSel · $nOff');
            final selIcoF = find.descendant(of: find.ancestor(of: selF, matching: find.byType(Row)).first, matching: find.byType(Icon), skipOffstage: true);
            final offIcoF = find.descendant(of: find.ancestor(of: offF, matching: find.byType(Row)).first, matching: find.byType(Icon), skipOffstage: true);
            final nSelIco = selIcoF.evaluate().length;
            final nOffIco = offIcoF.evaluate().length;
            need('탭 아이콘 1 · 1', nSelIco == 1 && nOffIco == 1, '개수 $nSelIco · $nOffIco');
            final selIcon = t.widget<Icon>(selIcoF).color;
            final offIcon = t.widget<Icon>(offIcoF).color;
            final selText = inkOf(selF);
            final offText = inkOf(offF);
            final selDec = t.widget<AnimatedContainer>(find.ancestor(of: selF, matching: find.byType(AnimatedContainer)).first).decoration;
            final selFace = selDec is BoxDecoration ? selDec.color : null;
            final tabRect = t.getRect(find.ancestor(of: selF, matching: find.byType(GestureDetector)).first);
            final ratio = selText == null ? 0.0 : _contrast(selText, selFace ?? Colors.white);
            raw = 'tab sel icon ${_hex(selIcon)} text ${_hex(selText)} face ${_hex(selFace)} off icon ${_hex(offIcon)} text ${_hex(offText)} '
                'ratio ${ratio.toStringAsFixed(2)} rect $tabRect';
            _out('D529 $tok att tab selicon=${_hex(selIcon)} seltext=${_hex(selText)} selface=${_hex(selFace)} officon=${_hex(offIcon)} '
                'offtext=${_hex(offText)} ratio=${ratio.toStringAsFixed(2)} h=${tabRect.height.toStringAsFixed(1)}');
            if (!_before) {
              chk('strict 날인 방식 선택 탭 — 선택 아이콘 · 글자 brand · 대비 ≥4.5',
                  selIcon == AppColors.brand && selText == AppColors.brand && ratio >= 4.5, raw);
              chk('strict 날인 방식 탭 — 선택 면 흰색 · 비선택 아이콘 grey500 · 글자 textSecondary 보존',
                  selFace == Colors.white && offIcon == AppColors.grey500 && offText == AppColors.textSecondary, raw);
            }
            await shot('1tab', 'seal-type-tab');
          } else {
            // ── 탈퇴 흐름(L3) ① 첫째 시트(탈퇴 전 확인)
            final linkF = label('회원탈퇴');
            await bring(linkF);
            final nLink = linkF.evaluate().length;
            need('회원탈퇴 링크 1', nLink == 1, '개수 $nLink');
            await t.tap(linkF);
            await settle();
            final sheetF = find.byType(BottomSheet, skipOffstage: true);
            final goF = label('탈퇴 진행');
            final nSheet1 = sheetF.evaluate().length;
            final nGo = goF.evaluate().length;
            need('첫째 시트 1 · 탈퇴 진행 1', nSheet1 == 1 && nGo == 1, '개수 $nSheet1 · $nGo');
            final b1 = await button(goF);
            final btns1 = labelsIn(sheetF, (w) => w is ButtonStyleButton);
            final wantOn = c.id == 'WD';
            raw = 's1 fill ${_hex(b1.fill)} text ${_hex(b1.fg)} side ${_hex(b1.side)} on ${b1.on} ratio ${b1.ratio.toStringAsFixed(2)} '
                'rect ${b1.rect} inView ${b1.inView} btns $btns1';
            _out('D529 $tok att s1 fill=${_hex(b1.fill)} text=${_hex(b1.fg)} side=${_hex(b1.side)} on=${b1.on} '
                'ratio=${b1.ratio.toStringAsFixed(2)} h=${b1.rect.height.toStringAsFixed(1)} btns=${_enc(btns1)}');
            need('첫째 시트 버튼이 스크롤 칸 안 · 활성 = 기대', b1.inView && b1.on == wantOn, raw);
            if (!_before) {
              if (wantOn) {
                chk('strict 첫째 시트 탈퇴 진행 — 빨강 채움 0 · 글 textSecondary · 테두리 grey300 · 대비 ≥4.5',
                    b1.fill == null && !_isRed(b1.fill) && b1.fg == AppColors.textSecondary && b1.side == AppColors.grey300 && b1.ratio >= 4.5, raw);
              } else {
                // 비활성 대비는 기록만(ratio).
                chk('strict 첫째 시트 탈퇴 진행(비활성) — 빨강 채움 0 · 글 textDisabled · 테두리 grey300',
                    b1.fill == null && !_isRed(b1.fill) && b1.fg == AppColors.textDisabled && b1.side == AppColors.grey300, raw);
              }
            }
            chk('첫째 시트 버튼 문구 집합 = 닫기 · 탈퇴 진행', btns1 == '닫기|탈퇴 진행', btns1);

            if (c.id == 'BLK') {
              await shot('1blk', 'withdraw-checklist-blocked');
              final closeF = label('닫기');
              final nClose = closeF.evaluate().length;
              need('닫기 1', nClose == 1, '개수 $nClose');
              await t.tap(closeF);
              await settle();
            } else {
              await shot('1chk', 'withdraw-checklist-clear');
              // ② 둘째 시트(비밀번호 확인) — '탈퇴 진행' 은 시트를 닫고 비밀번호 시트를 열 뿐이다(:1801 · :1903–1905).
              await t.tap(goF);
              await settle();
              final outF = label('탈퇴하기');
              final nSheet2 = sheetF.evaluate().length;
              final nOut = outF.evaluate().length;
              need('둘째 시트 1 · 탈퇴하기 1', nSheet2 == 1 && nOut == 1, '개수 $nSheet2 · $nOut');
              final b2 = await button(outF);
              final btns2 = labelsIn(sheetF, (w) => w is ButtonStyleButton);
              raw = '$raw | s2 fill ${_hex(b2.fill)} text ${_hex(b2.fg)} side ${_hex(b2.side)} on ${b2.on} ratio ${b2.ratio.toStringAsFixed(2)} '
                  'rect ${b2.rect} inView ${b2.inView} btns $btns2';
              _out('D529 $tok att s2 fill=${_hex(b2.fill)} text=${_hex(b2.fg)} side=${_hex(b2.side)} on=${b2.on} '
                  'ratio=${b2.ratio.toStringAsFixed(2)} h=${b2.rect.height.toStringAsFixed(1)} btns=${_enc(btns2)}');
              need('둘째 시트 버튼이 스크롤 칸 안 · 활성', b2.inView && b2.on, raw);
              if (!_before) {
                chk('strict 둘째 시트 탈퇴하기 — 빨강 채움 0 · 글 textSecondary · 테두리 grey300 · 대비 ≥4.5',
                    b2.fill == null && !_isRed(b2.fill) && b2.fg == AppColors.textSecondary && b2.side == AppColors.grey300 && b2.ratio >= 4.5, raw);
              }
              chk('둘째 시트 버튼 문구 집합 = 취소 · 탈퇴하기', btns2 == '취소|탈퇴하기', btns2);
              await shot('2pw', 'withdraw-password-sheet');

              // ③ 최종 확인창 — 비밀번호 칸을 채워야 열린다(:2768–2772). 확인창의 '탈퇴하기'는 누르지 않는다.
              final fieldF = find.descendant(of: sheetF, matching: find.byType(TextField), skipOffstage: true);
              final nField = fieldF.evaluate().length;
              need('비밀번호 칸 1', nField == 1, '개수 $nField');
              await t.enterText(fieldF, 'du529-not-a-password');
              await settle(4);
              await t.ensureVisible(outF);
              await settle(4);
              await t.tap(outF);
              await settle();
              final dlgF = find.byType(Dialog, skipOffstage: true);
              final okF = find.descendant(of: dlgF, matching: label('탈퇴하기'), skipOffstage: true);
              final noF = find.descendant(of: dlgF, matching: label('취소'), skipOffstage: true);
              final nDlg = dlgF.evaluate().length;
              final nOk = okF.evaluate().length;
              final nNo = noF.evaluate().length;
              need('최종 확인창 1 · 탈퇴하기 1 · 취소 1', nDlg == 1 && nOk == 1 && nNo == 1, '개수 $nDlg · $nOk · $nNo');
              final okMatF = find.ancestor(of: okF, matching: find.byType(Material)).first;
              final okFill = t.widget<Material>(okMatF).color;
              final okText = inkOf(okF);
              final okRect = t.getRect(okMatF);
              final okRatio = okText == null || okFill == null ? 0.0 : _contrast(okText, okFill);
              final okRed = _isRed(okFill);
              final acts = labelsIn(dlgF, (w) => w is InkWell);
              raw = '$raw | s3 fill ${_hex(okFill)} text ${_hex(okText)} red $okRed ratio ${okRatio.toStringAsFixed(2)} rect $okRect acts $acts';
              _out('D529 $tok att s3 fill=${_hex(okFill)} text=${_hex(okText)} red=$okRed ratio=${okRatio.toStringAsFixed(2)} '
                  'h=${okRect.height.toStringAsFixed(1)} acts=${_enc(acts)}');
              if (!_before) {
                chk('strict 최종 확인창 탈퇴하기 — 빨강 채움 유지(errorDark) · 흰 글 · 대비 ≥4.5',
                    okRed && okFill == AppColors.errorDark && okText == Colors.white && okRatio >= 4.5, raw);
              }
              chk('최종 확인창 행동 문구 집합 = 취소 · 탈퇴하기', acts == '취소|탈퇴하기', acts);
              await shot('3final', 'withdraw-final-confirm');
              // 닫기 — 확인창 '취소'(탈퇴 실행 0) → 시트 '취소'.
              await t.tap(noF);
              await settle();
              final nDlgAfter = dlgF.evaluate().length;
              need('확인창 닫힘', nDlgAfter == 0, '개수 $nDlgAfter');
              final cancelF = label('취소');
              final nCancel = cancelF.evaluate().length;
              need('시트 취소 1', nCancel == 1, '개수 $nCancel');
              await t.ensureVisible(cancelF);
              await settle(4);
              await t.tap(cancelF);
              await settle();
            }
            final nSheetEnd = sheetF.evaluate().length;
            need('시트 닫힘', nSheetEnd == 0, '개수 $nSheetEnd');
          }
          // 서비스 호출 기록 — 탈퇴 흐름은 조회 1건뿐이어야 한다(탈퇴 실행 · 그 밖 Functions 0).
          fnSnap = fnCalls.join('+');
          _out('D529 $tok att fn calls=${fnSnap.isEmpty ? '-' : fnSnap} n=${fnCalls.length}');
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
        _out('R529 $tok raw m64=${_enc(raw)} ovf64=${_enc(ovfRaw)} fw64=${_enc(fwRaw)} cleanup64=${_enc(cleanupErr)} '
            'fail64=${_enc(failure?.toString() ?? '')} perm64=${_enc(permCalls.join(','))} fn64=${_enc(fnSnap)}');
        _out('D529 $tok done state=${c.id} mode=$mode captures=$shots overflows=$nOvf exc=${exc != null}');

        final f0 = failure;
        if (f0 != null) {
          _halt ??= '$tok ${f0.toString().split('\n').first}';
          Error.throwWithStackTrace(f0, failureSt ?? StackTrace.current);
        }
        // 넘침 — W 는 strict 0. B 는 기존 넘침이 있을 수 있어 기록만(shot · done 줄의 ovf/overflows 를 TB 와 대조한다).
        if (!_before && v.id == 'W') chk('strict W 넘침 0', nOvf == 0, ovfRaw);
        // 탈퇴 실행 경로를 타지 않았다는 증거 — 두 모드 모두.
        if (c.id != 'SEAL') chk('Functions 호출 = callableGetWithdrawBlockers 1건뿐', fnSnap == 'callableGetWithdrawBlockers', fnSnap);
        // 응답 없는 플랫폼 채널이 남아 있으면 두 모드 모두 멈춘다(DU525 r1 원인의 재발 방지).
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
