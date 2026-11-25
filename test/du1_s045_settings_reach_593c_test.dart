// ignore_for_file: depend_on_referenced_packages
// [DU593c · 판정175 §2 :21 F175-WITHDRAW-READ-TAP · 같은 파일 표시 셀 · 설정 탈퇴 흐름 S045] —
//   탈퇴 전 확인 시트 · 비밀번호 확인 시트의 **전체 문장 실제 연속 도달**(문단마다 _seeText 로 넣고 같은 문단을 끝까지 실제로 끌어 _sweep) ·
//   각 이동 '확인하기 →' 받는 자리 48 / 화면 ∩ 조상 스크롤 칸 / 중심 hit(_btnReach — ensureVisible 대상 = 잰 InkWell) · 끝 단추(닫기 · 탈퇴 진행 · 취소 · 탈퇴하기) 도달.
//   같은 판정 잔여: MIX 행 낱말 끊김 · B 이동 vis/m48 · 정상 안내 작은 체크 대비 2.78 → 후보(낱말 줄바꿈 + 원문 이름 · 받는 자리 48 · 좁은 폭 배치 · successDark).
//   before = 지금 A(settings_screen 4453f993 = DU593b 채택판) 기록 · strict = 후보.
//   하네스 = DU593b suite(bc2642a3 · g1 정규 DONE 5/5) 설정 화면 대역 · 측정 블록 그대로 + DU588c suite(2bcd2e41 · 정규 DONE 5/5) _lineRects · _bringBuilt · _txt ·
//     _btnReach · _sweep 그대로(블록 바이트 = prep/mk_suite.py 단언).
//   누르는 것: '회원탈퇴' 링크 → MIX '닫기' / OK '탈퇴 진행' → 비밀번호 시트 '취소'. '확인하기 →' · '탈퇴하기' 는 누르지 않는다(이동 · 최종 확인창 · 탈퇴 서비스 0).
//   끌기 = 설정 목록 scrollUntilVisible + _sweep 의 실제 끌기(시트 본문 scroll owner)만 · 입력 0 · 쓰기 0. 기본 skip — TB before/du593cr-tb/DU_BEFORE_OBSERVE=593 · TA after/du593cr-ta/없음.
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

/// [동의 g6 du1 · 판정174 §6 기존 du1 증명 그대로] 아래 _sweep 이 쓴다.
/// [g5] 문단의 줄 상자(문단 좌표) — 보이는 글자마다 max 상자(줄 배치 세로 · tight 가로)를 같은 줄끼리 합친다(공백 · 낱말 묶음 문자 제외).
List<Rect> _lineRects(RenderParagraph rp) {
  final s = rp.text.toPlainText(includeSemanticsLabels: false);
  final out = <Rect>[];
  for (var i = 0; i < s.length; i++) {
    final ch = s[i];
    if (ch == _wj || _gap(ch)) continue;
    for (final b in rp.getBoxesForSelection(TextSelection(baseOffset: i, extentOffset: i + 1), boxHeightStyle: ui.BoxHeightStyle.max)) {
      final r = b.toRect();
      final k = out.indexWhere((x) => (x.top - r.top).abs() <= 0.5);
      if (k < 0) {
        out.add(r);
      } else {
        out[k] = out[k].expandToInclude(r);
      }
    }
  }
  out.sort((a, b) => a.top.compareTo(b.top));
  return out;
}

typedef _V = ({String id, double w, double h, double s});

const _views = <_V>[(id: 'W', w: 390.0, h: 844.0, s: 1.0), (id: 'B', w: 320.0, h: 640.0, s: 2.0), (id: 'N', w: 320.0, h: 640.0, s: 1.0)];

/// 사례 — MIX(처리 필요 2 + 확인 권장 1 — 체크리스트 글 7 · 이동 2 · 끝 단추 2) · OK(정상 안내 → '탈퇴 진행' → 비밀번호 시트 — 글 3 + 8 · 끝 단추 4).
const _cases = <({String id, int shots})>[(id: 'MIX', shots: 2), (id: 'OK', shots: 3)];

/// 글 원문(대상 소스와 같다 — mkcell 이 원문 대조). 행 글 = blockLabel/warnLabel 이 대역 count 로 만드는 글.
const _linkText = '회원탈퇴';
const _title1 = '탈퇴 전 확인';
const _sub1 = '처리 필요 항목을 먼저 완료해 주세요';
const _sec1 = '처리 필요 항목';
const _sec2 = '확인 권장 사항';
const _row1 = '미서명 계약서 1건';
const _row2 = '받지 못한 급여 2건 — 관리자에게 이체 요청 후 탈퇴 가능';
const _row3 = '진행 중 장기 근무 1건 — 탈퇴 전 관리자에게 퇴사 신청 권장';
const _goLink = '확인하기 →';
const _closeText = '닫기';
const _okText = '탈퇴 가능한 상태입니다.';
const _goText = '탈퇴 진행';
const _title2 = '회원탈퇴';
const _sub2 = '탈퇴 후 계정 복구는 불가능합니다';
const _pwTitle = '탈퇴 시 아래 사항을 확인해주세요';
const _pwItems = <String>['프로필 및 개인정보 즉시 삭제', '업로드한 서류 삭제 (신분증, 통장사본 등)', '진행 중인 지원·공고 자동 취소', '탈퇴 후 30일간 재가입 제한'];
const _pwLabel = '비밀번호 확인';
const _hint = '현재 비밀번호 입력';
const _pwGo = '탈퇴하기';
const _cancelText = '취소';

/// [DU593c] 시트 글 — kw = 이 셀이 낱말 줄바꿈(TextLayout.keepWords) + 읽는 이름 원문(semanticsLabel)을 넣은 글('rd') · 그 밖 제목 글('rx').
typedef _Para = ({String id, String text, bool kw});

const _mixParas = <_Para>[
  (id: 'title', text: _title1, kw: false),
  (id: 'sub1', text: _sub1, kw: true),
  (id: 'sec1', text: _sec1, kw: false),
  (id: 'row1', text: _row1, kw: true),
  (id: 'row2', text: _row2, kw: true),
  (id: 'sec2', text: _sec2, kw: false),
  (id: 'row3', text: _row3, kw: true),
];
const _mixRows = <({String id, String text})>[(id: 'row1', text: _row1), (id: 'row2', text: _row2), (id: 'row3', text: _row3)];
const _okParas = <_Para>[(id: 'title', text: _title1, kw: false), (id: 'sub1', text: _sub1, kw: true), (id: 'ok', text: _okText, kw: true)];
final _pwParas = <_Para>[
  (id: 'title2', text: _title2, kw: false),
  (id: 'sub2', text: _sub2, kw: true),
  (id: 'pwt', text: _pwTitle, kw: true),
  for (var i = 0; i < _pwItems.length; i++) (id: 'item${i + 1}', text: _pwItems[i], kw: true),
  (id: 'pwl', text: _pwLabel, kw: false),
];

final bool _before = Platform.environment['DU_BEFORE_OBSERVE'] == '593';
final Map<String, String> _env = Platform.environment;
final bool _optIn =
    (_env['DU1_VQ_PHASE'] == 'before' && _env['DU1_VQ_RUN'] == 'du593cr-tb' && _env['DU_BEFORE_OBSERVE'] == '593') ||
        (_env['DU1_VQ_PHASE'] == 'after' && _env['DU1_VQ_RUN'] == 'du593cr-ta' && _env['DU_BEFORE_OBSERVE'] == null);

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
      testWidgets('S593CR-${v.id}-${c.id} 설정 탈퇴 흐름 F175 — 두 시트 전체 문장 연속 도달 · 이동 받는 자리 48 · 끝 단추 도달 · 낱말 줄바꿈 · 작은 체크 대비', (t) async {
        final tok = 'S593CR-${v.id}-${c.id}';
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

          // [DU593c] 화면 단추 채움(A8 기록) + 캡처 — 캡처마다 한 번.
          Future<void> cap(String id, String state) async {
            final f = _fills(t);
            _out('D593 $tok att fl id=$id n=${f.n} brand=${f.brand} err=${f.err} none=${f.none} other=${f.other} list=${f.list}');
            raw += 'fl $id ${f.list} ';
            await shot(id, state);
          }

          if (c.id == 'MIX') {
            // ② 체크리스트 글 7(제목 · 부제 · 구역 제목 2 · 행 3) — 하나씩 넣고(_seeText) 같은 문단을 끝까지 실제로 끌어 모든 줄 연속 도달(_sweep) 기록.
            for (final p in _mixParas) {
              raw += await _readOne(t, sheetF, tok, p, screen, need);
            }
            // ③ 행마다 이동 '확인하기 →' — 그 행 상자 안 InkWell 한 요소를 넣고 같은 요소의 받는 자리 48 · 칸 안 · 중심 hit · 글 아래 배치(stk). 이동 없는 행은 n 0.
            for (final r in _mixRows) {
              final card = _cardOf(sheetF, r.text);
              if (card == null || _rtOne(card, (s) => s == _goLink) == null) {
                _out('D593 $tok att lk0 id=${r.id} n=0');
                raw += 'lk0 ${r.id} ';
                continue;
              }
              final k = await _btnReach(t, card, _goLink, screen);
              final stk = _below(t, card, r.text);
              _out('D593 $tok att lk id=${r.id} n=${k.n} m48=${k.m48} vis=${k.vis} hit=${k.hit} stk=$stk');
              need('이동 ${r.id} 1', k.n == 1, '개수 ${k.n}');
              raw += 'lk ${r.id} $k $stk ';
            }
            // 캡처 1 — 첫 행 글을 칸 위에 두고(이동 받는 자리 · 좁은 폭 배치가 함께 보이게) 찍는다(측정 아님).
            final r1f = _rtOne(sheetF, (s) => s == _row1);
            if (r1f != null) {
              await t.ensureVisible(r1f);
              await settle(4);
            }
            await cap('1mix', 'withdraw-checklist-rows-links');
            // ④ 끝 단추 — '닫기'(활성) · '탈퇴 진행'(처리 필요 항목 → 비활성) 받는 자리 · 칸 안 · hit(누르지 않는다 — 닫기는 ⑤).
            raw += await _ctaOne(t, sheetF, tok, 'close', _closeText, screen, need);
            raw += await _ctaOne(t, sheetF, tok, 'go', _goText, screen, need);
            await cap('2end', 'withdraw-checklist-end');
            // ⑤ 닫기 — 체크리스트 '닫기'(이동 0 · 비밀번호 시트 0).
            final closeF = label(_closeText);
            final nClose = closeF.evaluate().length;
            need('닫기 1', nClose == 1, '개수 $nClose');
            await t.ensureVisible(closeF);
            await settle(4);
            await t.tap(closeF);
            await settle();
          } else {
            // ② 체크리스트 글 3(제목 · 부제 · 정상 안내) — 넣기 · 연속 도달.
            for (final p in _okParas) {
              raw += await _readOne(t, sheetF, tok, p, screen, need);
            }
            // ③ 정상 안내 작은 체크(J3) — 아이콘 색 · 그 아이콘 뒤 실제 바탕과의 대비(비문자 3:1).
            final ob = _boxOf(sheetF, _okText);
            final icr = _icr(sheetF, _okText);
            _out('D593 $tok att okbox n=${ob.n} icon=${ob.icon} icr=${icr.toStringAsFixed(2)} ok3=${icr >= 3}');
            need('정상 안내 상자 1', ob.n == 1, '개수 ${ob.n}');
            raw += 'okbox ${ob.icon} ${icr.toStringAsFixed(2)} ';
            await cap('1ok', 'withdraw-checklist-clear');
            // ④ 체크리스트 끝 단추 — '닫기' · '탈퇴 진행'(활성) 받는 자리 · 칸 안 · hit.
            raw += await _ctaOne(t, sheetF, tok, 'close', _closeText, screen, need);
            raw += await _ctaOne(t, sheetF, tok, 'go', _goText, screen, need);
            // ⑤ '탈퇴 진행' → 비밀번호 시트(시트를 닫고 다음 시트를 열 뿐 — 확인창 · 탈퇴 서비스 0).
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
            await cap('2pw', 'withdraw-password-sheet-top');
            // ⑥ 비밀번호 시트 글 8(제목 · 부제 · 주의 제목 · 네 항목 · 비밀번호 확인) — 넣기 · 연속 도달. 입력 칸 힌트는 기록만(말줄임 잔여 후보 · 이 셀 변경 0).
            for (final p in _pwParas) {
              raw += await _readOne(t, sheetF, tok, p, screen, need);
            }
            final hs = await _seeText(t, sheetF, (s) => s == _hint, screen);
            _out('D593 $tok att hint n=${hs.n} full=${hs.full} brk=${hs.brk} lines=${hs.lines} vis=${hs.vis}');
            raw += 'hint $hs ';
            // ⑦ 비밀번호 시트 끝 단추 — '취소' · '탈퇴하기'(최종 확인창을 여는 단추 · 누르지 않는다).
            raw += await _ctaOne(t, sheetF, tok, 'cancel', _cancelText, screen, need);
            raw += await _ctaOne(t, sheetF, tok, 'final', _pwGo, screen, need);
            await cap('3end', 'withdraw-password-sheet-end');
            // ⑧ 닫기 — 비밀번호 시트 '취소'(최종 확인창 0 · 탈퇴 서비스 0).
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

// 측정 도우미(DU593b · DU588c 블록 바이트 그대로 · main 뒤에 둔다 — preflight 'renderObject 재사용' 줄 훑기 거짓 양성 회피).

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

/// [DU514 과 같다] 그린 글(표시 제어 문자 제외).
String _plainOf(Widget w) => w is RichText ? TextLayout.plain(w.text.toPlainText(includeSemanticsLabels: false)) : '';

/// [DU581 r2 · 판정167 시험 STOP 수리] 지연 생성 목록(사용자 목록 · 상세 시트 ListView) 안의 글이 아직 안 만들어졌을 때만
///   그 host 의 세로 목록을 끌어 만든다(누르기 아님 · 찾는 식 = _seeText 와 같은 _plainOf · 단언 없음 — 개수 판정은 _seeText 뒤 need).
Future<void> _bringBuilt(WidgetTester t, Finder host, String? want) async {
  final tf = find.descendant(
      of: host, matching: find.byWidgetPredicate((w) => w is RichText && _plainOf(w) == want), skipOffstage: false);
  if (tf.evaluate().isNotEmpty) return;
  final sc = find.descendant(
      of: host, matching: find.byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.down), skipOffstage: false);
  await t.scrollUntilVisible(tf, 120, scrollable: sc.first, maxScrolls: 40);
  await t.pump(const Duration(milliseconds: 50));
}

/// [DU562 r2 · DONE 5/5 그대로] Text 찾기(그린 글 = 표시 제어 문자를 뺀 원문) — _btnReach 가 쓴다.
Finder _txt(Finder scope, String want, {bool onstage = true}) => find.descendant(
    of: scope,
    matching: find.byWidgetPredicate((w) => w is Text && TextLayout.plain(w.data ?? w.textSpan?.toPlainText() ?? '') == want),
    skipOffstage: onstage);

/// [DU562 r2 · DONE 5/5 그대로] 아래 _btnReach 는 DU581 _bringBuilt(같은 이름 · 같은 인자 String?) 와 함께 쓴다(지어져 있으면 아무것도 하지 않는다).
typedef _BO = ({int n, bool vis, bool hit, bool m48});

/// 글자 버튼(누르지 않는다) — 글 [label] 의 InkWell 조상을 ensureVisible 로 화면 안에 넣고 **같은 InkWell** 을 잰다(DU560 r3 _btnLine 과 같은 대상).
Future<_BO> _btnReach(WidgetTester t, Finder scope, String label, Rect screen) async {
  await _bringBuilt(t, scope, label);
  final tf = _txt(scope, label, onstage: false);
  final n = tf.evaluate().length;
  var vis = false;
  var hit = false;
  var m48 = false;
  if (n == 1) {
    final ink = find.ancestor(of: tf, matching: find.byType(InkWell)).first;
    await t.ensureVisible(ink);
    for (var m = 0; m < 4; m++) {
      await t.pump(const Duration(milliseconds: 50));
    }
    final r = t.getRect(ink);
    m48 = r.width >= 48 - 0.01 && r.height >= 48 - 0.01;
    vis = _inside(r, _area(ink, screen));
    hit = _hitWithin(t, ink, r.center);
  }
  return (n: n, vis: vis, hit: hit, m48: m48);
}

/// [DU588c · 판정174 §2 :22 F174-S052-DIALOG-REACH · 관측 = 기록만(단언 0)] 창 본문 문단 RichText [tf] 하나 — 말단 · 모든 줄 연속 도달.
///   동의 g6 du1(:218–:287 · 판정174 §6 '기존 du1 의 모든 줄 도달 + 문단 좌표 가시 구간 연속성 증명')의 read()(줄마다 온전히 보인 프레임 · 문단 ≤ 칸이면
///   문단 전체 한 프레임 · 가시 구간 [vTop, vBot] 모으기 · 구멍 셈)와 걸음(stepPx · 터치 슬롭 24 · 놓기 전 멈춤)을 옮기고, 가로 잘림은 단언 대신 센다(hcut).
///   끌기 방향만 반대 — _seeText 의 ensureVisible 로 문단 윗끝이 칸 윗끝에 온 자리에서 같은 본문 scroll owner 를 실제 끌어(손가락 위 = 내용 위) 끝(max)까지 보낸다.
///   손가락 시작점 = 문단 ∩ 칸 가운데(사유 창 입력칸 위에서 끌지 않는다). 칸에 다 들어가면(max 0) 끌지 않고 한 프레임만 읽는다.
typedef _SwObs = ({int n, int lines, int seen, bool top, bool last, bool whole, bool need, bool cont, int hcut, bool fit, bool end, bool moved});

Future<_SwObs> _sweep(WidgetTester t, Finder tf, Rect screen) async {
  final n = tf.evaluate().length;
  if (n != 1) return (n: n, lines: 0, seen: 0, top: false, last: false, whole: false, need: false, cont: false, hcut: 0, fit: false, end: false, moved: false);
  final swRp = t.renderObject<RenderParagraph>(tf);
  final lines = _lineRects(swRp);
  final h = swRp.size.height;
  final sc = find.ancestor(of: tf, matching: find.byType(Scrollable)).first;
  final pos = t.state<ScrollableState>(sc).position;
  final p0 = pos.pixels;
  final fit = pos.maxScrollExtent <= 0.5;
  final a0 = _area(tf, screen);
  final needWhole = h <= a0.height + 0.5;
  final stepPx = needWhole ? ((a0.height - h) / 2).clamp(1.0, 8.0).toDouble() : 8.0;
  final seen = List<bool>.filled(lines.length, false);
  final spans = <(double, double)>[];
  var wholeSeen = false;
  var topSeen = false;
  var hcut = 0;
  void read() {
    final a = _area(tf, screen);
    if (a.isEmpty) return;
    final o = swRp.localToGlobal(Offset.zero);
    final vTop = (a.top - o.dy).clamp(0.0, h).toDouble();
    final vBot = (a.bottom - o.dy).clamp(0.0, h).toDouble();
    if (vBot > vTop) {
      spans.add((vTop, vBot));
      if (vTop <= 0.5) topSeen = true;
    }
    for (var i = 0; i < lines.length; i++) {
      final g = lines[i].shift(o);
      if (!(g.left >= a.left - 0.5 && g.right <= a.right + 0.5)) hcut++;
      if (g.top >= a.top - 0.5 && g.bottom <= a.bottom + 0.5) seen[i] = true;
    }
    if (_inside(o & swRp.size, a)) wholeSeen = true;
  }

  read();
  if (!fit) {
    final start = t.getRect(tf).intersect(a0).center;
    final drag = await t.startGesture(start);
    await drag.moveBy(const Offset(0, -24)); // 끌기 인식(터치 슬롭 넘김)
    await t.pump(const Duration(milliseconds: 16));
    read();
    var moves = 0;
    while (moves < 600 && pos.pixels < pos.maxScrollExtent - 0.5) {
      await drag.moveBy(Offset(0, -stepPx));
      await t.pump(const Duration(milliseconds: 16));
      moves++;
      read();
    }
    await t.pump(const Duration(milliseconds: 150)); // 놓기 전 멈춤 — 튕김 없이 놓는다
    await drag.up();
    for (var i = 0; i < 6; i++) {
      await t.pump(const Duration(milliseconds: 50));
    }
    read();
  }
  spans.sort((x, y) => x.$1.compareTo(y.$1));
  var covered = 0.0;
  var hole = -1.0;
  for (final s in spans) {
    if (s.$1 > covered + 0.5) {
      hole = covered;
      break;
    }
    if (s.$2 > covered) covered = s.$2;
  }
  return (
    n: 1,
    lines: lines.length,
    seen: seen.where((x) => x).length,
    top: topSeen,
    last: seen.isNotEmpty && seen.last,
    whole: wholeSeen,
    need: needWhole,
    cont: hole < 0 && covered >= h - 0.5,
    hcut: hcut,
    fit: fit,
    end: pos.pixels >= pos.maxScrollExtent - 0.5,
    moved: (pos.pixels - p0).abs() > 0.5,
  );
}

// ───────────── [DU593c] 새 측정 — 위 재사용 도우미(_seeText · _sweep · _btnReach · _btnLine · _rtOne · _txt · _bgOf · _contrast)만 부른다 ─────────────

/// [DU593c · 판정175 §2 :21 F175-WITHDRAW-READ-TAP] 시트 글 하나 — _seeText(그 RichText 를 넣고 이름 · 전문 · 낱말 안 끊김 · 줄 · 칸 안) 뒤 같은 RichText 를
///   _sweep(같은 scroll owner 를 끝까지 실제로 끌며 모든 줄 · 문단 좌표 연속 · 가로 잘림 · 끝 도달)으로 잰다. 낱말 줄바꿈을 넣은 글(kw)은 'rd', 제목 글은 'rx'.
///   글이 정확히 하나가 아니면 needFn 으로 멈춘다.
Future<String> _readOne(WidgetTester t, Finder host, String tok, _Para p, Rect screen, void Function(String k, bool ok, [String why]) needFn) async {
  final s = await _seeText(t, host, (x) => x == p.text, screen);
  if (p.kw) {
    _out('D593 $tok att rd id=${p.id} n=${s.n} name=${s.name} full=${s.full} brk=${s.brk} lines=${s.lines} vis=${s.vis}');
  } else {
    _out('D593 $tok att rx id=${p.id} n=${s.n} name=${s.name} full=${s.full} brk=${s.brk} lines=${s.lines} vis=${s.vis}');
  }
  needFn('글 ${p.id} 1', s.n == 1, '개수 ${s.n}');
  final r = await _sweep(t, _rtOne(host, (x) => x == p.text) ?? find.byElementPredicate((e) => false), screen);
  _out('D593 $tok att rch id=${p.id} n=${r.n} lines=${r.lines} seen=${r.seen} top=${r.top} last=${r.last} whole=${r.whole} need=${r.need} cont=${r.cont} hcut=${r.hcut} fit=${r.fit} end=${r.end} moved=${r.moved}');
  needFn('연속 도달 문단 ${p.id} 1', r.n == 1, '개수 ${r.n}');
  return '${p.id} $s $r ';
}

/// [DU593c · F175 끝 단추 도달] 시트 끝 단추 하나 — _btnReach(그 글의 InkWell 을 넣고 같은 InkWell 의 받는 자리 48 · 칸 안 · 중심 hit) + _btnLine(비활성 여부만). 누르지 않는다.
Future<String> _ctaOne(WidgetTester t, Finder host, String tok, String id, String text, Rect screen, void Function(String k, bool ok, [String why]) needFn) async {
  final k = await _btnReach(t, host, text, screen);
  final b = _btnLine(t, host, (s) => s == text, screen);
  _out('D593 $tok att cta id=$id n=${k.n} dis=${b.dis} m48=${k.m48} vis=${k.vis} hit=${k.hit}');
  needFn('끝 단추 $id 1', k.n == 1 && b.n == 1, '개수 ${k.n} · ${b.n}');
  return 'cta $id $k $b ';
}

/// [DU593c] 행 글 [want] 이 놓인 반복 행 상자(가장 가까운 테두리 있는 DecoratedBox) — 이동 글 · 받는 자리를 그 행 안에서만 찾는다(두 이동 글 구분).
Finder? _cardOf(Finder host, String want) {
  final f = _rtOne(host, (s) => s == want);
  if (f == null) return null;
  Element? box;
  f.evaluate().first.visitAncestorElements((a) {
    final w = a.widget;
    if (w is DecoratedBox && w.decoration is BoxDecoration && (w.decoration as BoxDecoration).border != null) {
      box = a;
      return false;
    }
    return true;
  });
  final b = box;
  if (b == null) return null;
  return find.byElementPredicate((x) => identical(x, b), skipOffstage: false);
}

/// [DU593c] 이동 받는 자리(InkWell)가 행 글 아래 줄에 있는가(좁은 폭 배치) — 글 상자 아래끝 ≤ InkWell 윗끝(공차 0.5). 기록만.
bool _below(WidgetTester t, Finder card, String want) {
  final tf = _rtOne(card, (s) => s == want);
  final ink = find.ancestor(of: _txt(card, _goLink, onstage: false), matching: find.byType(InkWell));
  if (tf == null || ink.evaluate().isEmpty) return false;
  return t.getRect(ink.first).top >= t.getRect(tf).bottom - 0.5;
}

/// [DU593c · J3] 글 [want] 과 같은 Row 의 첫 아이콘 색 ↔ 그 아이콘 뒤 실제 바탕(_bgOf) 대비(비문자 3:1 대조 · 아이콘 없으면 0).
double _icr(Finder host, String want) {
  final f = _rtOne(host, (s) => s == want);
  if (f == null) return 0.0;
  final rows = find.ancestor(of: f, matching: find.byType(Row)).evaluate().toList();
  if (rows.isEmpty) return 0.0;
  final row = rows.first;
  final ics = find
      .descendant(of: find.byElementPredicate((x) => identical(x, row), skipOffstage: false), matching: find.byType(Icon), skipOffstage: false)
      .evaluate()
      .toList();
  if (ics.isEmpty) return 0.0;
  final Color? ic = (ics.first.widget as Icon).color;
  return ic == null ? 0.0 : _contrast(ic, _bgOf(ics.first));
}
