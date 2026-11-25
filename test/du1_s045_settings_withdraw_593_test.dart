// ignore_for_file: depend_on_referenced_packages
// [DU593b · 결정 미이행 장부 파일 단위 · 설정 탈퇴 흐름 S045] 판정 원문 이행 —
//   장부 031 retro128 :60(탈퇴 체크리스트 반복 행 면 · 구역 제목 중립 · 실제 상태는 작은 표시 + 명시 문구 · 대표 안내 1개만 E-NOTICE) ·
//   장부 032 retro130 :76 (b)(1단계 정상 '탈퇴 가능' 넓은 초록 면 → 중립 면/본문 + 작은 체크) ·
//   장부 033 retro130 :76 (b)(2단계 비밀번호 시트 넓은 빨강 면 → 중립 면/본문 + 작은 경고 아이콘 · 분명한 주의 제목 · 네 항목 전문 보존).
//   before = 지금 A(settings_screen f29abf51 = DU531 채택판) 기록 · strict = 후보.
//   하네스 = DU529 suite(8b870960 · 정규 DONE 5/5) 설정 화면 대역 그대로(지원자 · 알림 권한 거부 · 앱 버전 · Functions callableGetWithdrawBlockers 만 대역 응답 ·
//     _FakeApp/_FakeCore · _png · _P · 설정 목록 scrollUntilVisible) + DU590b suite(28fc47fb · 정규 DONE 5/5) 측정 블록
//     (DU571 r2 _fullShown max 판 · _midBreaks · _area · _hitWithin · _lineCount · _seeText · _btnLine · DU309 색 · DU575 _paintOf · A8 _fills · _rtOne).
//   누르는 것: '회원탈퇴' 링크 → MIX '닫기' / OK '탈퇴 진행' → 비밀번호 시트 '취소'. '확인하기 →' · '탈퇴하기' 는 누르지 않는다(이동 · 최종 확인창 · 탈퇴 서비스 0).
//   입력 0 · 끌기 = 설정 목록 scrollUntilVisible 만 · 쓰기 0. 기본 skip — TB before/du593bf-tb/DU_BEFORE_OBSERVE=593 · TA after/du593bf-ta/없음.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui show BoxHeightStyle;

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

Future<void> _loadFonts() async {
  Future<ByteData> b(String p) => File(p).readAsBytes().then((x) => ByteData.view(x.buffer));
  for (final fam in const ['NotoSansKR', 'Roboto']) {
    await (FontLoader(fam)
          ..addFont(b('assets/fonts/NotoSansKR-Regular.ttf'))
          ..addFont(b('assets/fonts/NotoSansKR-Bold.ttf')))
        .load();
  }
  await (FontLoader('FlutterTest')..addFont(b('assets/fonts/NotoSansKR-Regular.ttf'))).load();
  await (FontLoader('MaterialIcons')
        ..addFont(b('C:/Users/kug02/flutter/bin/cache/artifacts/material_fonts/materialicons-regular.otf')))
      .load();
}

void _out(String s) {
  // ignore: avoid_print
  print(s);
}

String _enc(String s) => s.isEmpty ? '-' : base64Url.encode(utf8.encode(s)).replaceAll('=', '');

/// 시각 오류 수집 — 넘침은 원문 + 위치, 그 밖 framework 오류는 원문.
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

bool _inside(Rect a, Rect b) => a.left >= b.left - 0.5 && a.top >= b.top - 0.5 && a.right <= b.right + 0.5 && a.bottom <= b.bottom + 0.5;

final String _wj = String.fromCharCode(0x2060);
final String _zw = String.fromCharCode(0x200B);

bool _gap(String ch) => ch == ' ' || ch == '\n' || ch == '\t' || ch == _zw;

/// 그려진 글(표시 제어 문자 포함) 기준 — 낱말(공백 · 개행 · ZWSP 사이) 안에서 줄이 바뀐 횟수. NBSP · WORD JOINER 로 묶은 덩어리는 한 낱말이다.
int _midBreaks(RenderParagraph rp) {
  final s = rp.text.toPlainText(includeSemanticsLabels: false);
  var n = 0;
  double? lastTop;
  var lastIdx = -1;
  for (var i = 0; i < s.length; i++) {
    final ch = s[i];
    if (ch == '\n') {
      lastTop = null;
      lastIdx = i;
      continue;
    }
    if (ch == _wj || ch == _zw) continue;
    final bx = rp.getBoxesForSelection(TextSelection(baseOffset: i, extentOffset: i + 1));
    if (bx.isEmpty) continue;
    final top = bx.first.top;
    final half = (bx.first.bottom - bx.first.top) / 2;
    final wrapped = lastTop != null && top > lastTop + half;
    if (wrapped) {
      var gap = _gap(ch) || (lastIdx >= 0 && _gap(s[lastIdx]));
      for (var k = lastIdx + 1; k < i; k++) {
        if (_gap(s[k])) gap = true;
      }
      if (!gap) n++;
    }
    if (lastTop == null || wrapped) lastTop = top;
    lastIdx = i;
  }
  return n;
}

/// 글 전문이 그려졌는가 — 마지막 글자까지 자리(box)가 문단 크기 안에 있다(말줄임으로 잘린 글자는 자리가 없다).
bool _fullShown(RenderParagraph rp, Size size) {
  final s = rp.text.toPlainText(includeSemanticsLabels: false);
  for (var i = s.length - 1; i >= 0; i--) {
    final ch = s[i];
    if (ch == _wj || _gap(ch)) continue;
    // [DU571 r2 · 판정167 시험 STOP 수리 · 판정159/161/162 방식] 세로는 줄 배치(max 상자) · 가로는 tight right(종전) · 공차 0.5 그대로.
    //   tight 세로는 run 글꼴 높이라 줄 높이 1.3 < 글꼴 원래 1.448em 이면 줄 상자 밖으로 나온다(DU559 nmraw: h+1.258). 잉크/clip 증명 아님.
    final sel = TextSelection(baseOffset: i, extentOffset: i + 1);
    final tight = rp.getBoxesForSelection(sel);
    final mx = rp.getBoxesForSelection(sel, boxHeightStyle: ui.BoxHeightStyle.max);
    return tight.isNotEmpty && mx.isNotEmpty && mx.first.bottom <= size.height + 0.5 && tight.first.right <= size.width + 0.5;
  }
  return false;
}

/// [f] 가 실제로 보일 수 있는 칸 — 화면 ∩ 조상 스크롤 칸 전부.
Rect _area(Finder f, Rect screen) {
  var a = screen;
  for (final e in find.ancestor(of: f, matching: find.byType(Scrollable)).evaluate()) {
    final ro = e.renderObject;
    if (ro is RenderBox && ro.hasSize) a = a.intersect(ro.localToGlobal(Offset.zero) & ro.size);
  }
  return a;
}

/// [pos] 를 눌렀을 때 맞는 대상 중에 [f] 의 위젯(자손 포함)이 만든 render object 가 있는가.
bool _hitWithin(WidgetTester t, Finder f, Offset pos) {
  final own = <Object>{};
  void walk(Element e) {
    final ro = e.renderObject;
    if (ro != null) own.add(ro);
    e.visitChildren(walk);
  }

  walk(f.evaluate().first);
  return t.hitTestOnBinding(pos).path.any((x) => own.contains(x.target));
}

/// 그려진 문단의 줄 수 — 글자 자리(box)의 서로 다른 top 개수.
int _lineCount(RenderParagraph rp) {
  final n = rp.text.toPlainText(includeSemanticsLabels: false).length;
  final tops = <int>{};
  for (final b in rp.getBoxesForSelection(TextSelection(baseOffset: 0, extentOffset: n))) {
    tops.add(b.top.round());
  }
  return tops.length;
}

typedef _V = ({String id, double w, double h, double s});

const _views = <_V>[(id: 'W', w: 390.0, h: 844.0, s: 1.0), (id: 'B', w: 320.0, h: 640.0, s: 2.0), (id: 'N', w: 320.0, h: 640.0, s: 1.0)];

/// 사례 — MIX(체크리스트 · 처리 필요 2 + 확인 권장 1 — 반복 행 · 구역 제목 · 이동 글 · 장부 031) ·
///   OK(체크리스트 정상 '탈퇴 가능' 안내 — 장부 032 → '탈퇴 진행' → 비밀번호 시트 안내 — 장부 033).
const _cases = <({String id, int shots})>[(id: 'MIX', shots: 1), (id: 'OK', shots: 2)];

/// 글 원문(대상 소스와 같다 — mkcell 이 원문 대조). 행 글 = blockLabel/warnLabel 이 대역 count 로 만드는 글.
const _linkText = '회원탈퇴';
const _sec1 = '처리 필요 항목';
const _sec2 = '확인 권장 사항';
const _row1 = '미서명 계약서 1건';
const _row2 = '받지 못한 급여 2건 — 관리자에게 이체 요청 후 탈퇴 가능';
const _row3 = '진행 중 장기 근무 1건 — 탈퇴 전 관리자에게 퇴사 신청 권장';
const _goLink = '확인하기 →';
const _closeText = '닫기';
const _okText = '탈퇴 가능한 상태입니다.';
const _goText = '탈퇴 진행';
const _pwTitle = '탈퇴 시 아래 사항을 확인해주세요';
const _pwItems = <String>['프로필 및 개인정보 즉시 삭제', '업로드한 서류 삭제 (신분증, 통장사본 등)', '진행 중인 지원·공고 자동 취소', '탈퇴 후 30일간 재가입 제한'];
const _pwGo = '탈퇴하기';
const _cancelText = '취소';

final bool _before = Platform.environment['DU_BEFORE_OBSERVE'] == '593';
final Map<String, String> _env = Platform.environment;
final bool _optIn =
    (_env['DU1_VQ_PHASE'] == 'before' && _env['DU1_VQ_RUN'] == 'du593bf-tb' && _env['DU_BEFORE_OBSERVE'] == '593') ||
        (_env['DU1_VQ_PHASE'] == 'after' && _env['DU1_VQ_RUN'] == 'du593bf-ta' && _env['DU_BEFORE_OBSERVE'] == null);

/// 첫 실패 뒤 사례는 본문에 들어가지 않는다(진입 0 · 캡처 0).
String? _halt;
final String _manifest = Platform.environment['DUL_MANIFEST'] ?? '(unset)';
const _envKeys = ['DU_BEFORE_OBSERVE', 'DU1_VQ_PHASE', 'DU1_VQ_OUT', 'DU1_VQ_RUN', 'DU1_VQ_DATE', 'DU397_DIAG', 'DU397_MANIFEST', 'DU400_MANIFEST',
  'DU401_MANIFEST', 'DU398_MANIFEST', 'DU406_MANIFEST', 'DU407_MANIFEST', 'DU296_PHASE', 'DUL_MANIFEST'];
final String _envLine = [for (final k in _envKeys) '$k:${Platform.environment[k] ?? '(unset)'}'].join(',');

void main() {
  // 플랫폼 응답 — [DU529 와 같다] 알림 권한 = 거부(0 → 사용자 문서 조회 없음) · 앱 버전 = 대역 값.
  //   누른 뒤 부르는 것: '회원탈퇴' → Functions callableGetWithdrawBlockers 하나(사례별 hardBlocks · warnings 대역). 비밀번호 시트는 열릴 때 호출 0.
  //   그 밖 Functions 이름은 오류 응답 + 기록(이동 · 탈퇴 서비스 경로를 타지 않았다는 증거).
  const permChannel = MethodChannel('flutter.baseflow.com/permissions/methods');
  const fnChannel = 'dev.flutter.pigeon.cloud_functions_platform_interface.CloudFunctionsHostApi.call';
  final permCalls = <String>[];
  final fnCalls = <String>[];
  var fnBlocks = <Object?>[];
  var fnWarns = <Object?>[];
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    PackageInfo.setMockInitialValues(
        appName: 'ALfit', packageName: 'com.alfit.app', version: '1.0.0', buildNumber: '1', buildSignature: '');
    permCalls.clear();
    fnCalls.clear();
    fnBlocks = <Object?>[];
    fnWarns = <Object?>[];
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
        return codec.encodeMessage(<Object?>['not-found', 'du593b-blocked', null]);
      }
      return codec.encodeMessage(<Object?>[
        <String, Object?>{'hardBlocks': fnBlocks, 'warnings': fnWarns},
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
    await _loadFonts();
  });

  for (final v in _views) {
    for (final c in _cases) {
      testWidgets('S593BF-${v.id}-${c.id} 설정 탈퇴 흐름 장부 031 · 032 · 033 — 체크리스트 반복 행 · 정상 안내 · 비밀번호 시트 안내 중립 면 + 작은 상태 표시', (t) async {
        final tok = 'S593BF-${v.id}-${c.id}';
        if (_halt != null) fail('$tok 진입 0 — 앞 실패: $_halt');
        final prevOnError = FlutterError.onError;
        addTearDown(() => FlutterError.onError = prevOnError);
        t.view.physicalSize = Size(v.w, v.h);
        t.view.devicePixelRatio = 1.0;
        addTearDown(t.view.reset);
        final screen = Offset.zero & Size(v.w, v.h);
        final mode = _before ? 'before' : 'strict';
        _out('D593 $tok begin mode=$mode phase=${Platform.environment['DU1_VQ_PHASE'] ?? '(unset)'} env=$_envLine manifest=$_manifest');
        final isW = v.id == 'W';
        // MIX = 처리 필요 2(이동 있는 미서명 계약 · 이동 없는 받지 못한 급여) + 확인 권장 1(이동 있는 진행 중 장기 근무) — 지원자 본인 사유. OK = 0 · 0.
        if (c.id == 'MIX') {
          fnBlocks = <Object?>[
            <String, Object?>{'type': 'UNSIGNED_CONTRACT', 'count': 1},
            <String, Object?>{'type': 'PENDING_WAGES', 'count': 2},
          ];
          fnWarns = <Object?>[
            <String, Object?>{'type': 'CONFIRMED_WORK', 'count': 1},
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
                theme: RoleTheme.workerTheme,
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
          final scr = find.byType(SettingsScreen);
          final nScreen = scr.evaluate().length;
          _out('D593 $tok att scr n=$nScreen');
          need('설정 화면 1', nScreen == 1, '개수 $nScreen');

          Future<void> shot(String id, String state) async {
            _out('D593 $tok shot $id ovf=${seen.overflows.length}');
            await vqCapture(t, key, '${tok}_$id', conditions: {
              'viewport': '${v.w.toInt()}x${v.h.toInt()}', 'textScaler': v.s, 'run': vqRun, 'manifest': _manifest, 'mode': mode,
              'fixture': c.id, 'state': state,
            });
            shots++;
          }

          // ① '회원탈퇴' 링크 — 설정 목록은 보이는 부분만 짓는다(DU529 와 같이 대상이 나올 때까지 실제로 끈다) → 누름 → 체크리스트 시트.
          final listF = find.descendant(of: scr, matching: find.byType(Scrollable), skipOffstage: true).first;
          Finder label(String s) => find.byWidgetPredicate((w) => w is Text && TextLayout.plain(w.data ?? '') == s, skipOffstage: true);
          final linkF = label(_linkText);
          await t.scrollUntilVisible(linkF, 120, scrollable: listF, maxScrolls: 80, duration: const Duration(milliseconds: 50));
          await settle(6);
          final nLink = linkF.evaluate().length;
          need('회원탈퇴 링크 1', nLink == 1, '개수 $nLink');
          await t.ensureVisible(linkF);
          await settle(4);
          await t.tap(linkF);
          await settle();
          final sheetF = find.byType(BottomSheet, skipOffstage: true);
          final nSheet = sheetF.evaluate().length;
          _out('D593 $tok att sheet n=$nSheet');
          need('체크리스트 시트 1', nSheet == 1, '개수 $nSheet');

          if (c.id == 'MIX') {
            // ② 구역 제목 2(장부 031 · C6) — 글 색 · 실제 바탕 · 대비.
            final s1 = _paintOf(t, sheetF, _sec1);
            _out('D593 $tok att sec1 n=${s1.n} fill=${s1.fill} fg=${s1.fg} cr=${s1.cr} ok45=${_ok45(s1.cr)}');
            final s2 = _paintOf(t, sheetF, _sec2);
            _out('D593 $tok att sec2 n=${s2.n} fill=${s2.fill} fg=${s2.fg} cr=${s2.cr} ok45=${_ok45(s2.cr)}');
            need('구역 제목 1 · 1', s1.n == 1 && s2.n == 1, 'n ${s1.n} · ${s2.n}');
            // ③ 반복 행 3(장부 031) — 행 글을 넣고(_seeText = ensureVisible) 같은 글의 상자 면 · 선 · 작은 아이콘 · 글 색 · 대비, 같은 Row 의 이동 글.
            final r1 = await _rowStep(t, sheetF, _row1, screen);
            _out('D593 $tok att row1 n=${r1.b.n} face=${r1.b.face} edge=${r1.b.edge} icon=${r1.b.icon} fg=${r1.b.fg} cr=${r1.b.cr} ok45=${r1.b.ok45}');
            _out('D593 $tok att see1 n=${r1.s.n} full=${r1.s.full} brk=${r1.s.brk} lines=${r1.s.lines} vis=${r1.s.vis}');
            _out('D593 $tok att link1 n=${r1.l.n} fg=${r1.l.fg} cr=${r1.l.cr} ok45=${r1.l.ok45} m48=${r1.l.m48} vis=${r1.l.vis} hit=${r1.l.hit}');
            final r2 = await _rowStep(t, sheetF, _row2, screen);
            _out('D593 $tok att row2 n=${r2.b.n} face=${r2.b.face} edge=${r2.b.edge} icon=${r2.b.icon} fg=${r2.b.fg} cr=${r2.b.cr} ok45=${r2.b.ok45}');
            _out('D593 $tok att see2 n=${r2.s.n} full=${r2.s.full} brk=${r2.s.brk} lines=${r2.s.lines} vis=${r2.s.vis}');
            _out('D593 $tok att link2 n=${r2.l.n} fg=${r2.l.fg} cr=${r2.l.cr} ok45=${r2.l.ok45} m48=${r2.l.m48} vis=${r2.l.vis} hit=${r2.l.hit}');
            final r3 = await _rowStep(t, sheetF, _row3, screen);
            _out('D593 $tok att row3 n=${r3.b.n} face=${r3.b.face} edge=${r3.b.edge} icon=${r3.b.icon} fg=${r3.b.fg} cr=${r3.b.cr} ok45=${r3.b.ok45}');
            _out('D593 $tok att see3 n=${r3.s.n} full=${r3.s.full} brk=${r3.s.brk} lines=${r3.s.lines} vis=${r3.s.vis}');
            _out('D593 $tok att link3 n=${r3.l.n} fg=${r3.l.fg} cr=${r3.l.cr} ok45=${r3.l.ok45} m48=${r3.l.m48} vis=${r3.l.vis} hit=${r3.l.hit}');
            need('행 글 1 · 1 · 1', r1.b.n == 1 && r2.b.n == 1 && r3.b.n == 1, 'n ${r1.b.n} · ${r2.b.n} · ${r3.b.n}');
            raw = 'sec ${s1.fg}/${s2.fg} rows ${r1.b.face}/${r1.b.edge}/${r1.b.fg} ${r2.b.face}/${r2.b.fg} ${r3.b.face}/${r3.b.fg} links ${r1.l.fg}/${r3.l.fg}';
            final cf = _fills(t);
            _out('D593 $tok att cfills n=${cf.n} brand=${cf.brand} err=${cf.err} none=${cf.none} other=${cf.other} list=${cf.list}');
            await shot('1mix', 'withdraw-checklist-blocked-warned');
            // ④ 닫기 — 체크리스트 '닫기'(이동 0 · 비밀번호 시트 0).
            final closeF = label(_closeText);
            final nClose = closeF.evaluate().length;
            need('닫기 1', nClose == 1, '개수 $nClose');
            await t.ensureVisible(closeF);
            await settle(4);
            await t.tap(closeF);
            await settle();
          } else {
            // ② 정상 '탈퇴 가능' 안내(장부 032) — 글을 넣고 같은 글의 상자 면 · 선 · 작은 체크 · 글 색 · 대비.
            final os = await _seeText(t, sheetF, (s) => s == _okText, screen);
            final ob = _boxOf(sheetF, _okText);
            _out('D593 $tok att okbox n=${ob.n} face=${ob.face} edge=${ob.edge} icon=${ob.icon} fg=${ob.fg} cr=${ob.cr} ok45=${ob.ok45}');
            _out('D593 $tok att oksee n=${os.n} full=${os.full} brk=${os.brk} lines=${os.lines} vis=${os.vis}');
            need('정상 안내 글 1', ob.n == 1 && os.n == 1, 'n ${ob.n} · ${os.n}');
            final of1 = _fills(t);
            _out('D593 $tok att ofills n=${of1.n} brand=${of1.brand} err=${of1.err} none=${of1.none} other=${of1.other} list=${of1.list}');
            await shot('1ok', 'withdraw-checklist-clear');
            // ③ '탈퇴 진행' → 비밀번호 시트(시트를 닫고 다음 시트를 열 뿐 — 확인창 · 탈퇴 서비스 0).
            final goF = label(_goText);
            final nGo = goF.evaluate().length;
            need('탈퇴 진행 1', nGo == 1, '개수 $nGo');
            await t.ensureVisible(goF);
            await settle(4);
            await t.tap(goF);
            await settle();
            final nSheet2 = sheetF.evaluate().length;
            _out('D593 $tok att sheet2 n=$nSheet2');
            need('비밀번호 시트 1', nSheet2 == 1, '개수 $nSheet2');
            // ④ 비밀번호 시트 안내(장부 033) — 주의 제목(상자 면 · 선 · 작은 경고 아이콘 · 글 색 · 대비 · 전문) · 네 항목(전문 · 끊김 · 보임 · 글/점 색 · 대비).
            final ps = await _seeText(t, sheetF, (s) => s == _pwTitle, screen);
            final pb = _boxOf(sheetF, _pwTitle);
            _out('D593 $tok att pwbox n=${pb.n} face=${pb.face} edge=${pb.edge} icon=${pb.icon} fg=${pb.fg} cr=${pb.cr} ok45=${pb.ok45}');
            _out('D593 $tok att pwsee n=${ps.n} full=${ps.full} brk=${ps.brk} lines=${ps.lines} vis=${ps.vis}');
            need('주의 제목 1', pb.n == 1 && ps.n == 1, 'n ${pb.n} · ${ps.n}');
            final pi = await _itemsStep(t, sheetF, screen);
            _out('D593 $tok att pwitem n=${pi.n} full=${pi.full} brk=${pi.brk} lines=${pi.lines} vis=${pi.vis} fg=${pi.fg} dot=${pi.dot} cr=${pi.cr} ok45=${pi.ok45}');
            need('네 항목 각 1', pi.n == _pwItems.length, 'n ${pi.n}');
            // ⑤ 시트 '탈퇴하기'(다음 확인창을 여는 단추 · DU529 중립 그대로) — 글을 넣고 단추 받는 자리 · 보임 · hit(누르지 않는다).
            await _seeText(t, sheetF, (s) => s == _pwGo, screen);
            final pg = _btnLine(t, sheetF, (s) => s == _pwGo, screen);
            _out('D593 $tok att pwgo n=${pg.n} dis=${pg.dis} m48=${pg.m48} vis=${pg.vis} hit=${pg.hit}');
            raw = 'ok ${ob.face}/${ob.edge}/${ob.icon}/${ob.fg} pw ${pb.face}/${pb.edge}/${pb.icon}/${pb.fg} items ${pi.fg}/${pi.dot}/${pi.cr}';
            final pf = _fills(t);
            _out('D593 $tok att pwfills n=${pf.n} brand=${pf.brand} err=${pf.err} none=${pf.none} other=${pf.other} list=${pf.list}');
            await shot('2pw', 'withdraw-password-sheet');
            // ⑥ 닫기 — 비밀번호 시트 '취소'(최종 확인창 0 · 탈퇴 서비스 0).
            final cancelF = label(_cancelText);
            final nCancel = cancelF.evaluate().length;
            need('시트 취소 1', nCancel == 1, '개수 $nCancel');
            await t.ensureVisible(cancelF);
            await settle(4);
            await t.tap(cancelF);
            await settle();
          }
          final nLeft = sheetF.evaluate().length;
          _out('D593 $tok att close n=$nLeft');
          need('시트 닫힘', nLeft == 0, '남은 $nLeft');
          // 화면 전체 채움 단추(A8 기록) — 시트를 닫은 뒤 설정 화면.
          final fl = _fills(t);
          _out('D593 $tok att fills n=${fl.n} brand=${fl.brand} err=${fl.err} none=${fl.none} other=${fl.other} list=${fl.list}');
          raw = '$raw fills ${fl.list}';
        } catch (e, st) {
          failure = e;
          failureSt = st;
        } finally {
          FlutterError.onError = prevOnError;
        }

        // ⑦ 성공 · 실패 공통 정리 — 화면을 내리고 남은 timer 가 끝날 시간을 준다.
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
        // ⑧ 서비스 호출 기록 — 탈퇴 흐름은 조회 1건뿐이어야 한다(이동 · 최종 확인 · 탈퇴 서비스 · 그 밖 Functions 0).
        final fnSnap = fnCalls.join('+');
        final nFn = fnCalls.where((x) => x == 'callableGetWithdrawBlockers').length;
        final nOther = fnCalls.length - nFn;
        _out('D593 $tok att wire fn=$nFn other=$nOther perm=${permCalls.length}');
        final exc = t.takeException();
        if (exc != null && failure == null) {
          failure = exc;
          failureSt = StackTrace.current;
        }
        final nOvf = seen.overflows.length;
        final nFw = seen.other.length;
        final ovfRaw = seen.overflows.take(8).join('\n----\n');
        final fwRaw = seen.other.take(4).map((m) => m.length > 400 ? m.substring(0, 400) : m).join('\n----\n');
        _out('R593 $tok raw m64=${_enc(raw)} ovf64=${_enc(ovfRaw)} fw64=${_enc(fwRaw)} cleanup64=${_enc(cleanupErr)} '
            'fail64=${_enc(failure?.toString() ?? '')} perm64=${_enc(permCalls.join(','))} fn64=${_enc(fnSnap)}');
        _out('D593 $tok att fw n=$nFw');
        _out('D593 $tok done state=${c.id} mode=$mode captures=$shots overflows=$nOvf exc=${exc != null}');

        final f0 = failure;
        if (f0 != null) {
          _halt ??= '$tok ${f0.toString().split('\n').first}';
          Error.throwWithStackTrace(f0, failureSt ?? StackTrace.current);
        }
        chk('Functions 호출 = callableGetWithdrawBlockers 1건뿐(이동 · 최종 확인 · 탈퇴 서비스 0)', fnSnap == 'callableGetWithdrawBlockers', fnSnap);
        // B(320 · 2.0) · N(320 · 1.0) 의 넘침 · framework 오류는 기록만(DU529 B · DU590b 와 같이 TB/TA 손 대조) — W strict 는 0.
        if (!_before && isW) chk('strict W 화면 전체 넘침 0', nOvf == 0, ovfRaw);
        if (!_before && isW) chk('strict W 미처리 framework 예외 0', nFw == 0, fwRaw);
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

// 측정 도우미(DU571 r2 바이트 그대로 · DU590b 와 같이 main 뒤에 둔다 — preflight 'renderObject 재사용' 줄 훑기 거짓 양성 회피).

typedef _SeeObs = ({int n, bool name, bool full, int brk, int lines, bool vis});

/// [DU571] 바뀐 글 하나 — 그린 글(표시 제어 문자 제외)이 [match] 에 맞는 RichText 가 정확히 하나일 때 **그 RichText 를** ensureVisible 로 넣고,
///   같은 요소로 읽는 이름(가장 가까운 Semantics 조상 label = 그 글 원문) · 전문 · 낱말 안 끊김(강제 포함) · 줄 수 · 화면 ∩ 스크롤 칸 안을 잰다
///   (DU570 의 같은 이름 도우미와 같은 잣대 · 찾는 조건만 함수 · await 뒤에는 Element 를 직접 읽지 않고 같은 finder 로 다시 잡는다).
Future<_SeeObs> _seeText(WidgetTester t, Finder host, bool Function(String s) match, Rect screen) async {
  final es = find
      .descendant(of: host, matching: find.byType(RichText), skipOffstage: false)
      .evaluate()
      .where((e) => match(TextLayout.plain((e.widget as RichText).text.toPlainText(includeSemanticsLabels: false))))
      .toList();
  if (es.length != 1) return (n: es.length, name: false, full: false, brk: 0, lines: 0, vis: false);
  final el = es.first;
  final want = TextLayout.plain((el.widget as RichText).text.toPlainText(includeSemanticsLabels: false));
  final tf = find.byElementPredicate((x) => identical(x, el), skipOffstage: false);
  await t.ensureVisible(tf);
  for (var m = 0; m < 4; m++) {
    await t.pump(const Duration(milliseconds: 50));
  }
  final rp = t.renderObject<RenderParagraph>(tf);
  final sem = find.ancestor(of: tf, matching: find.byType(Semantics, skipOffstage: false)).evaluate();
  final label = sem.isEmpty ? null : (sem.first.widget as Semantics).properties.label;
  return (
    n: 1,
    name: label == want,
    full: _fullShown(rp, rp.size),
    brk: _midBreaks(rp),
    lines: _lineCount(rp),
    vis: _inside(t.getRect(tf), _area(tf, screen)),
  );
}

typedef _BtnObs = ({int n, bool dis, bool m48, bool vis, bool hit});

/// [DU571] 그 글이 든 버튼 — 그린 글이 [match] 에 맞고 ButtonStyleButton 조상이 있는 RichText 가 정확히 하나일 때 **그 버튼 한 요소로**
///   비활성(onPressed null · 행동 불변) · 받는 자리(48 기록) · 화면 ∩ 스크롤 칸 안 · 중심 hit 를 잰다(ensureVisible 0 · 누르지 않는다).
_BtnObs _btnLine(WidgetTester t, Finder host, bool Function(String s) match, Rect screen) {
  final btn = find.byWidgetPredicate((w) => w is ButtonStyleButton, skipOffstage: false);
  final es = find
      .descendant(of: host, matching: find.byType(RichText), skipOffstage: false)
      .evaluate()
      .where((e) => match(TextLayout.plain((e.widget as RichText).text.toPlainText(includeSemanticsLabels: false))))
      .where((e) {
        final ef = find.byElementPredicate((x) => identical(x, e), skipOffstage: false);
        return find.ancestor(of: ef, matching: btn).evaluate().isNotEmpty;
      })
      .toList();
  if (es.length != 1) return (n: es.length, dis: false, m48: false, vis: false, hit: false);
  final el = es.first;
  final tf = find.byElementPredicate((x) => identical(x, el), skipOffstage: false);
  final bf = find.ancestor(of: tf, matching: btn).first;
  final r = t.getRect(bf);
  return (
    n: 1,
    dis: (t.widget(bf) as ButtonStyleButton).onPressed == null,
    m48: r.width >= 48 - 0.01 && r.height >= 48 - 0.01,
    vis: _inside(r, _area(bf, screen)),
    hit: _hitWithin(t, bf, r.center),
  );
}

// [DU575] 색 도우미 — DU309 시험(du1_confirm_color_split_309_test :84–95 · :162–183)과 같은 식(bgOf 는 main 안 지역 함수를 최상위 _bgOf 로만 옮김).

double _lum(Color c) {
  double ch(double v) => v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * ch(c.r) + 0.7152 * ch(c.g) + 0.0722 * ch(c.b);
}

double _contrast(Color a, Color b) {
  final x = _lum(a);
  final y = _lum(b);
  return (math.max(x, y) + 0.05) / (math.min(x, y) + 0.05);
}

String _hex(Color c) => '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

Color _bgOf(Element e) {
  final layers = <Color>[];
  e.visitAncestorElements((a) {
    final w = a.widget;
    Color? c;
    if (w is ColoredBox) {
      c = w.color;
    } else if (w is DecoratedBox && w.decoration is BoxDecoration) {
      c = (w.decoration as BoxDecoration).color;
    } else if (w is Material && w.type != MaterialType.transparency) {
      c = w.color ?? Theme.of(a).canvasColor;
    }
    if (c == null || c.a == 0) return true;
    layers.add(c);
    return c.a < 1.0;
  });
  var out = layers.isEmpty ? Colors.white : layers.last;
  for (final c in layers.reversed.skip(1)) {
    out = Color.alphaBlend(c, out);
  }
  return out;
}

/// [DU575] 주 행동 칠 — 그 글(RichText)의 글자색 · 그 글 뒤 실제 바탕(_bgOf = 버튼 Material) · 대비 · brand 여부 · 흰 글 여부 · 머리 아이콘 색(맨 위 Icon).
typedef _PaintObs = ({int n, String fill, String fg, String cr, bool brand, bool white, String icon});

_PaintObs _paintOf(WidgetTester t, Finder host, String go) {
  final es = find
      .descendant(of: host, matching: find.byType(RichText), skipOffstage: false)
      .evaluate()
      .where((e) => TextLayout.plain((e.widget as RichText).text.toPlainText(includeSemanticsLabels: false)) == go)
      .toList();
  final icons = find.descendant(of: host, matching: find.byType(Icon), skipOffstage: false).evaluate().toList()
    ..sort((x, y) => t.getRect(find.byElementPredicate((q) => identical(q, x), skipOffstage: false)).top
        .compareTo(t.getRect(find.byElementPredicate((q) => identical(q, y), skipOffstage: false)).top));
  final Color? ic = icons.isEmpty ? null : (icons.first.widget as Icon).color;
  final icon = ic == null ? '-' : _hex(ic);
  if (es.length != 1) return (n: es.length, fill: '-', fg: '-', cr: '0.00', brand: false, white: false, icon: icon);
  final el = es.first;
  final Color? fg = (el.widget as RichText).text.style?.color;
  final bg = _bgOf(el);
  return (
    n: 1,
    fill: _hex(bg),
    fg: fg == null ? '-' : _hex(fg),
    cr: fg == null ? '0.00' : _contrast(fg, bg).toStringAsFixed(2),
    brand: bg.toARGB32() == AppColors.brand.toARGB32(),
    white: fg != null && fg.toARGB32() == Colors.white.toARGB32(),
    icon: icon,
  );
}

/// [DU575 · 점검표 A8] 화면에 그려진(onstage) ButtonStyleButton 전부의 채움 — 단추 자신의 Material 색(투명 · 없음 = none) · 글 = 첫 RichText(Icon 글리프 제외).
///   기록만(브랜드 밖 채움은 보고서 색 조화 표 '후보'). 카드 행 단추(_inviteActionButton = GestureDetector + Container)는 여기 들지 않는다 — README A8 표.
typedef _FillObs = ({int n, int brand, int err, int none, int other, String list});

_FillObs _fills(WidgetTester t) {
  final rows = <String>[];
  var b = 0, er = 0, no = 0, ot = 0;
  for (final e in find.byWidgetPredicate((w) => w is ButtonStyleButton).evaluate()) {
    final bf = find.byElementPredicate((x) => identical(x, e));
    final mats = find.descendant(of: bf, matching: find.byType(Material), skipOffstage: false).evaluate().toList();
    final Color? fc = mats.isEmpty ? null : (mats.first.widget as Material).color;
    final texts = find
        .descendant(of: bf, matching: find.byType(RichText), skipOffstage: false)
        .evaluate()
        .where((r) => find.ancestor(of: find.byElementPredicate((x) => identical(x, r), skipOffstage: false), matching: find.byType(Icon)).evaluate().isEmpty)
        .toList();
    final lab = texts.isEmpty ? '-' : TextLayout.plain((texts.first.widget as RichText).text.toPlainText(includeSemanticsLabels: false));
    if (fc == null || fc.a == 0) {
      no++;
      rows.add('$lab:none');
    } else {
      if (fc.toARGB32() == AppColors.brand.toARGB32()) {
        b++;
      } else if (fc.toARGB32() == AppColors.errorDark.toARGB32()) {
        er++;
      } else {
        ot++;
      }
      rows.add('$lab:${_hex(fc)}');
    }
  }
  return (n: rows.length, brand: b, err: er, none: no, other: ot, list: _enc(rows.join('|')));
}

/// 그린 글(표시 제어 문자 제외)이 [match] 에 맞는 RichText 하나의 Finder — 정확히 하나가 아니면 null(아이콘 글리프는 한글 조건에 맞지 않는다).
Finder? _rtOne(Finder host, bool Function(String s) match) {
  final es = find
      .descendant(of: host, matching: find.byType(RichText), skipOffstage: false)
      .evaluate()
      .where((e) => match(TextLayout.plain((e.widget as RichText).text.toPlainText(includeSemanticsLabels: false))))
      .toList();
  if (es.length != 1) return null;
  final el = es.first;
  return find.byElementPredicate((x) => identical(x, el), skipOffstage: false);
}

// ───────────── [DU593b] 새 측정 — 위 재사용 도우미(_seeText · _btnLine · _rtOne · _bgOf · _contrast · _hex)만 부른다 ─────────────

bool _ok45(String cr) => (double.tryParse(cr) ?? 0) >= 4.5;

String _argb(Color c) => '#${c.toARGB32().toRadixString(16).padLeft(8, '0').toUpperCase()}';

typedef _BoxObs = ({int n, String face, String edge, String icon, String fg, String cr, bool ok45});

/// [DU593b] 글 하나(그린 글 = [want])가 놓인 테두리 상자 — 가장 가까운 BoxDecoration(border 있음) 조상의 면 · 선(#AARRGGBB · 알파 포함),
///   그 상자 안에서 글에 가장 가까운 Row 의 첫 아이콘 색(상자 안 Row 가 없으면 '-'), 글 색 · 실제 바탕(_bgOf) 대비. 기록만(누르지 않는다).
_BoxObs _boxOf(Finder host, String want) {
  final f = _rtOne(host, (s) => s == want);
  if (f == null) return (n: 0, face: '-', edge: '-', icon: '-', fg: '-', cr: '0.00', ok45: false);
  final el = f.evaluate().first;
  BoxDecoration? deco;
  Element? row;
  el.visitAncestorElements((a) {
    final w = a.widget;
    if (w is DecoratedBox) {
      final dd = w.decoration;
      if (dd is BoxDecoration && dd.border != null) {
        deco = dd;
        return false;
      }
    }
    if (row == null && w is Row) row = a;
    return true;
  });
  final d = deco;
  final r = row;
  final Color? fc = d?.color;
  final bd = d?.border;
  var icon = '-';
  if (r != null) {
    final ics = find
        .descendant(of: find.byElementPredicate((x) => identical(x, r), skipOffstage: false), matching: find.byType(Icon), skipOffstage: false)
        .evaluate()
        .toList();
    final Color? ic = ics.isEmpty ? null : (ics.first.widget as Icon).color;
    if (ic != null) icon = _hex(ic);
  }
  final Color? fg = (el.widget as RichText).text.style?.color;
  final cr = fg == null ? 0.0 : _contrast(fg, _bgOf(el));
  return (
    n: 1,
    face: fc == null ? '-' : _argb(fc),
    edge: bd is Border ? _argb(bd.top.color) : '-',
    icon: icon,
    fg: fg == null ? '-' : _hex(fg),
    cr: cr.toStringAsFixed(2),
    ok45: cr >= 4.5,
  );
}

typedef _LinkObs = ({int n, String fg, String cr, bool ok45, bool m48, bool vis, bool hit});

/// [DU593b] 행 글 [want] 과 같은 Row 안의 이동 단추('확인하기 →') — 그 단추 글을 ensureVisible(_seeText)로 넣은 뒤 같은 Row 를 다시 잡아
///   글 색 · 실제 바탕 대비 · 단추 한 요소의 받는 자리 48 · 보임 · 중심 hit(_btnLine). 단추가 없으면 n 0(나머지 '-' · false). 누르지 않는다.
Future<_LinkObs> _linkOf(WidgetTester t, Finder sheet, String want, Rect screen) async {
  const none = (n: 0, fg: '-', cr: '0.00', ok45: false, m48: false, vis: false, hit: false);
  Finder? rowOf() {
    final f = _rtOne(sheet, (s) => s == want);
    if (f == null) return null;
    final rs = find.ancestor(of: f, matching: find.byType(Row)).evaluate().toList();
    if (rs.isEmpty) return null;
    final re = rs.first;
    return find.byElementPredicate((x) => identical(x, re), skipOffstage: false);
  }

  final r0 = rowOf();
  if (r0 == null || _rtOne(r0, (s) => s == _goLink) == null) return none;
  await _seeText(t, r0, (s) => s == _goLink, screen);
  final r1 = rowOf();
  if (r1 == null) return none;
  final lf = _rtOne(r1, (s) => s == _goLink);
  if (lf == null) return none;
  final bl = _btnLine(t, r1, (s) => s == _goLink, screen);
  final el = lf.evaluate().first;
  final Color? fg = (el.widget as RichText).text.style?.color;
  final cr = fg == null ? 0.0 : _contrast(fg, _bgOf(el));
  return (n: bl.n, fg: fg == null ? '-' : _hex(fg), cr: cr.toStringAsFixed(2), ok45: cr >= 4.5, m48: bl.m48, vis: bl.vis, hit: bl.hit);
}

typedef _RowObs = ({_BoxObs b, _SeeObs s, _LinkObs l});

/// [DU593b · 장부 031] 체크리스트 반복 행 하나 — 행 글 ensureVisible + 전문 · 끊김 · 줄 · 보임(_seeText) → 같은 글의 상자(_boxOf) → 같은 Row 의 이동 단추(_linkOf).
Future<_RowObs> _rowStep(WidgetTester t, Finder sheet, String want, Rect screen) async {
  final s = await _seeText(t, sheet, (x) => x == want, screen);
  final b = _boxOf(sheet, want);
  final l = await _linkOf(t, sheet, want, screen);
  return (b: b, s: s, l: l);
}

typedef _ItemObs = ({int n, bool full, int brk, int lines, bool vis, String fg, String dot, String cr, bool ok45});

/// [DU593b · 장부 033] 비밀번호 시트 네 항목 — 항목마다 ensureVisible + 전문 · 끊김 · 줄 · 보임(_seeText) · 글 색 · 실제 바탕 대비(가장 낮은 값) ·
///   앞 점('•') 글 색(첫 점). 네 항목이 각각 정확히 하나일 때만 n 에 센다 — full · vis 는 네 항목 모두 참일 때 참.
Future<_ItemObs> _itemsStep(WidgetTester t, Finder sheet, Rect screen) async {
  var n = 0;
  var brk = 0;
  var lines = 0;
  var full = true;
  var vis = true;
  var minCr = 99.0;
  final fgs = <String>{};
  for (final it in _pwItems) {
    final s = await _seeText(t, sheet, (x) => x == it, screen);
    if (s.n != 1) continue;
    n++;
    full = full && s.full;
    vis = vis && s.vis;
    brk += s.brk;
    lines += s.lines;
    final f = _rtOne(sheet, (x) => x == it);
    if (f == null) continue;
    final el = f.evaluate().first;
    final Color? fg = (el.widget as RichText).text.style?.color;
    if (fg == null) {
      fgs.add('-');
      continue;
    }
    fgs.add(_hex(fg));
    final cr = _contrast(fg, _bgOf(el));
    if (cr < minCr) minCr = cr;
  }
  final dots = find
      .descendant(
          of: sheet,
          matching: find.byWidgetPredicate((w) => w is RichText && w.text.toPlainText(includeSemanticsLabels: false).trim() == '•'),
          skipOffstage: false)
      .evaluate()
      .toList();
  final Color? dc = dots.isEmpty ? null : (dots.first.widget as RichText).text.style?.color;
  final all = n == _pwItems.length;
  return (
    n: n,
    full: full && all,
    brk: brk,
    lines: lines,
    vis: vis && all,
    fg: fgs.isEmpty ? '-' : (fgs.length == 1 ? fgs.first : 'mixed'),
    dot: dc == null ? '-' : _hex(dc),
    cr: (n == 0 ? 0.0 : minCr).toStringAsFixed(2),
    ok45: n > 0 && minCr >= 4.5,
  );
}
