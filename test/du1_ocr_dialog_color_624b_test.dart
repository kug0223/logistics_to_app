// [DU624b · 판정207 §4 역할별 색 · 표시만] OCR 확인창 3종(lib/widgets/dialogs/ocr_verification_dialog.dart) 색 토큰 4줄 —
//   '등록하기' · '계속 진행' 주 행동 채움 의미색(successMedium · warningMedium) → brand · '그대로 등록' 보조 행동 글 warningDark → brand ·
//   '입력 정보' 값 글 infoDark → textPrimary(일반 자료 글 = 중립). 머리 의미 아이콘 · '인식 정보' warningDark · '오류:' errorDark · 결과 상자 면은 그대로.
//   관측: 실제 창 함수 3개(showSuccess · showWarning · showError)를 실제 호출(document_upload_helper.dart :533 · :591 · :244)과 같은 인자 꼴로 부른다.
//     호출 화면(서류 등록 · 카메라/OCR)은 이 하네스에서 열 수 없어 시험 호스트(RoleTheme.workerTheme · 빈 Scaffold)로 부른다(부모 화면 미관측).
//   재는 것: 셸 면(T0-a 전제 — 흰 · tint 투명) · 덮개 · 제목/본문 전문 · 글 대비(글 뒤 실제 바탕) · 단추 도달 · 칠(주 행동 · 머리 아이콘) · 글색 · 반환값 · 넘침.
//   before = 지금 A(ocr 467f78a9) 기록 · strict = 후보(cand/ aa30f958 · mkcell 이 SHA 대조). T0-a(role_theme 9cc10962) 적용 뒤 gN 판만 실행한다(README §8).
//   하네스 = DU622b suite(47d89ce0) 블록 재사용(그 안 DU618b 811d8f93 블록은 g3 TB 9/9 성공 계보 · prep/mk_suite.py 가 줄 범위 바이트 단언) + 새 부분(prep/suite_parts/p2 · p3).
//   누르는 것: OSUC '등록하기'(반환 true · 호스트만 받는다) / OWARN '다시 촬영'(false) / OERR '취소'(false) — 도달 실패 시 NavigatorState.pop(같은 값).
//     '계속 진행' · '그대로 등록' · '다시 시도'는 누르지 않는다.
//   기본 skip — TB before/du624boc-tb/DU_BEFORE_OBSERVE=624 · TA after/du624boc-ta/없음.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui show BoxHeightStyle;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ALfit/theme/app_colors.dart';
import 'package:ALfit/theme/role_theme.dart';
import 'package:ALfit/utils/text_layout.dart';
import 'package:ALfit/widgets/dialogs/ocr_verification_dialog.dart';

import 'support/du1_vq_capture.dart';

/// CF Pigeon 채널 — RG 시험(offer_workdetail_roster · noshow_contract_dialog_gate)과 같은 'unavailable' 응답을 주고 센다.
const _cfChannel = 'dev.flutter.pigeon.cloud_functions_platform_interface.CloudFunctionsHostApi.call';

/// [DU526 과 같다] FirebaseAuth 를 처음 읽을 때 등록하는 두 리스너 채널과 그 이벤트 채널.
const _authBase = 'dev.flutter.pigeon.firebase_auth_platform_interface.FirebaseAuthHostApi.';
const _authFake = 'du560.fake.auth.';
const _authListeners = ['registerIdTokenListener', 'registerAuthStateListener'];

/// 원래 경로로 보내는 Flutter 기반 채널과 이유.
const _frameworkAllow = <String, String>{
  'flutter/assets': 'AssetBundle(아이콘 글꼴 · 이미지 매니페스트) 읽기',
  'flutter/platform': 'MaterialApp Title · SystemSound/Haptic(InkWell 탭 피드백)',
  'flutter/navigation': '루트 Navigator 경로 보고',
  'flutter/mousecursor': 'MouseRegion 커서 갱신(시험 포인터)',
  'flutter/restoration': 'RootRestorationScope 상태 복원 조회',
  'flutter/keyboard': 'HardwareKeyboard 상태 동기화',
  'flutter/accessibility': '의미 트리/알림 전달',
};

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

/// [a] 가 [b] **안**에 있는가(0.5px 허용).
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
    // [DU560 repair 3 proposed / decision168] Vertical max selection box; horizontal tight right; tolerance unchanged.
    // This measures selection-box placement, not ink bounds or ancestor clipping.
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

/// [DU624b] 사례 — OSUC = OCR 일치 창(showSuccess) · OWARN = 정보 불일치 창(showWarning) · OERR = 인식 실패 창(showError) — 각 1장.
const _cases = <({String id, int shots})>[(id: 'OSUC', shots: 1), (id: 'OWARN', shots: 1), (id: 'OERR', shots: 1)];

final bool _before = Platform.environment['DU_BEFORE_OBSERVE'] == '624';

/// [DU624b] 글 = 제품 원문(ocr_verification_dialog.dart — mkcell 이 소스 대조). 인자 꼴 = 실제 호출(document_upload_helper.dart :533 통장사본 일치 ·
///   :591 통장사본 계좌번호 불일치(사유 글 꼴 :554–:556 · :575) · :244 신분증 인식 실패(allowContinue true)). 이름 · 번호는 fixture 값.
const _sTitle = '입력 정보와 일치해요';
const _sDesc = '등록한 급여계좌 정보와 통장사본을 비교했어요.';
const _sInfo = '예금주: 홍길동\n계좌번호: 1234567890\n은행: 국민은행';
const _sGo = '등록하기';
const _wTitle = '정보 불일치';
const _wHead = '통장사본의 정보가 입력하신 정보와 일치하지 않습니다';
const _wExp = '홍길동\n1234567890\n국민은행';
const _wExt = '홍길동\n1234567899';
const _wReason = '• 입력한 계좌번호와 통장사본의 계좌번호가 일치하지 않습니다\n  입력: 1234567890\n  인식: 1234567899\n\n사진이 선명하게 보이도록 다시 촬영해주세요';
const _wLast = '• 나중에 설정에서 다시 업로드할 수 있습니다\n• 정확한 정보 입력을 위해 다시 촬영을 권장합니다';
const _wLab = '입력 정보';
const _wRetake = '다시 촬영';
const _wGo = '계속 진행';
const _oTitle = '인식 실패';
const _oBody = '신분증를 인식할 수 없습니다';
const _oErr = '이미지를 읽지 못했어요';
const _oLast = '오류: 이미지를 읽지 못했어요';
const _oCancel = '취소';
const _oKeep = '그대로 등록';
const _oRetry = '다시 시도';

final Map<String, String> _env = Platform.environment;
final bool _optIn =
    (_env['DU1_VQ_PHASE'] == 'before' && _env['DU1_VQ_RUN'] == 'du624boc-tb' && _env['DU_BEFORE_OBSERVE'] == '624') ||
        (_env['DU1_VQ_PHASE'] == 'after' && _env['DU1_VQ_RUN'] == 'du624boc-ta' && _env['DU_BEFORE_OBSERVE'] == null);

/// 첫 실패 뒤 사례는 본문에 들어가지 않는다(진입 0 · 캡처 0).
String? _halt;
final String _manifest = Platform.environment['DUL_MANIFEST'] ?? '(unset)';
const _envKeys = ['DU_BEFORE_OBSERVE', 'DU1_VQ_PHASE', 'DU1_VQ_OUT', 'DU1_VQ_RUN', 'DU1_VQ_DATE', 'DU397_DIAG', 'DU397_MANIFEST', 'DU400_MANIFEST',
  'DU401_MANIFEST', 'DU398_MANIFEST', 'DU406_MANIFEST', 'DU407_MANIFEST', 'DU296_PHASE', 'DUL_MANIFEST'];
final String _envLine = [for (final k in _envKeys) '$k:${Platform.environment[k] ?? '(unset)'}'].join(',');

/// 모든 플랫폼 메시지 관찰 — 허용 Flutter 기반 채널은 원래 경로(센다) · Auth 정확 허용은 setUpAll 모의로(센다) ·
///   CF · 그 밖(Firestore · 저장소 · 허용 밖 flutter/*)은 이름을 기록하고 막는다(응답 null) · **막는 순간 tripped**(후속 UI 조작 중단).
class _DWire {
  final unexpected = <String>[];
  final cf = <String>[];
  final framework = <String, int>{};
  final auth = <String>[];
  var tripped = false;

  Future<ByteData?>? route(TestDefaultBinaryMessenger m, String channel, MessageHandler? handler, ByteData? message) {
    if (channel == _cfChannel) {
      cf.add(channel);
      tripped = true;
      return null;
    }
    for (final name in _authListeners) {
      if (channel == '$_authBase$name') {
        auth.add('register:$name');
        return handler?.call(message);
      }
      if (channel == '$_authFake$name') {
        String method;
        try {
          method = const StandardMethodCodec().decodeMethodCall(message).method;
        } catch (_) {
          method = '?';
        }
        if (method == 'listen' || method == 'cancel') {
          auth.add('$method:$name');
          return handler?.call(message);
        }
        unexpected.add('$channel#$method');
        tripped = true;
        return null;
      }
    }
    if (_frameworkAllow.containsKey(channel)) {
      framework.update(channel, (x) => x + 1, ifAbsent: () => 1);
      return handler != null ? handler(message) : m.delegate.send(channel, message);
    }
    unexpected.add(channel);
    tripped = true;
    return null;
  }
}

/// [F120-3] 외부 HTTP 차단 — 만들려는 시도를 기록하고 실패시킨다(끝에 0 단언).
class _DNoHttp extends HttpOverrides {
  _DNoHttp(this.wire);
  final _DWire wire;
  final tries = <String>[];

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    tries.add('createHttpClient');
    wire.tripped = true;
    throw const SocketException('NCB-12O 관측 — 외부 HTTP 차단');
  }
}

/// 시각 오류 수집 — 넘침은 원문 전체 + 위치 두 줄, 그 밖 framework 오류도 원문 전체(DU516 r1 과 같다).
class _DSeen {
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
      overflows.add('${m.split('\n').first} @ $loc\n$m');
    } else {
      other.add(m);
    }
  }
}

// [DU584b] 아래 측정 도우미는 바이트 그대로 옮겼다 — DU562 r2(b4029f2a) :930–945 · :947–971 · :991–1013(ensureVisible 대상 = 잰 대상) · DU560 r3(0c33ce67) :885–898(확인창 글) · DU575(5cd431b1) :766–802 · :842–869 · :871–903(색 · 칠 · 화면 채움 단추).

Finder _txt(Finder scope, String want, {bool onstage = true}) => find.descendant(
    of: scope,
    matching: find.byWidgetPredicate((w) => w is Text && TextLayout.plain(w.data ?? w.textSpan?.toPlainText() ?? '') == want),
    skipOffstage: onstage);

/// [DU581 r3 _bringBuilt 와 같은 대비 · 판정167 교훈] [want] 글이 [host] 안에 아직 안 지어졌을 때만 그 host 의 세로 Scrollable 을 끌어 짓는다
///   (누르기 아님 · 찾는 식 = _txt 와 같은 정규화 · 단언 없음 — 개수 판정은 뒤 _textLine/_btnReach 출력과 cell 선언). 지어져 있으면 아무것도 하지 않는다.
Future<void> _bringBuilt(WidgetTester t, Finder host, String? want) async {
  final tf = find.descendant(
      of: host, matching: find.byWidgetPredicate((w) => w is Text && TextLayout.plain(w.data ?? w.textSpan?.toPlainText() ?? '') == want), skipOffstage: false);
  if (tf.evaluate().isNotEmpty) return;
  final sc = find.descendant(
      of: host, matching: find.byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.down), skipOffstage: false);
  await t.scrollUntilVisible(tf, 120, scrollable: sc.first, maxScrolls: 40);
  await t.pump(const Duration(milliseconds: 50));
}

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

typedef _DlgObs = ({int n, bool full, int brk, int lines, bool vis});

/// [UXW-1a] 확인창 안 글 하나 — 그린 글(표시 제어 문자 제외)이 [want] 인 RichText 가 정확히 하나일 때 전문 · 낱말 안 끊김 · 줄 수 · 화면 안(잰 즉시 값).
_DlgObs _dlgText(WidgetTester t, Finder host, String want, Rect screen) {
  final es = find
      .descendant(of: host, matching: find.byType(RichText), skipOffstage: false)
      .evaluate()
      .where((e) => TextLayout.plain((e.widget as RichText).text.toPlainText(includeSemanticsLabels: false)) == want)
      .toList();
  if (es.length != 1) return (n: es.length, full: false, brk: 0, lines: 0, vis: false);
  final rp = es.first.renderObject as RenderParagraph;
  final r = t.getRect(find.byElementPredicate((x) => identical(x, es.first), skipOffstage: false));
  return (n: 1, full: _fullShown(rp, rp.size), brk: _midBreaks(rp), lines: _lineCount(rp), vis: _inside(r, screen));
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

/// [DU584b] 확인창 호스트 — 그린 글(표시 제어 문자 제외)이 [want] 인 RichText 를 품은 Dialog 만 고른다(뒤에 깔린 날짜별 창 · 근태 창과 섞지 않는다).
///   부를 때 한 번 고정한다 — 연 뒤 · 닫은 뒤 각각 새로 부른다.
Finder _dlgWith(String want) {
  final ds = find.byType(Dialog, skipOffstage: false).evaluate().where((d) => find
      .descendant(of: find.byElementPredicate((x) => identical(x, d), skipOffstage: false), matching: find.byType(RichText), skipOffstage: false)
      .evaluate()
      .any((e) => TextLayout.plain((e.widget as RichText).text.toPlainText(includeSemanticsLabels: false)) == want)).toList();
  return find.byElementPredicate((x) => ds.contains(x), skipOffstage: false);
}

Finder _fe(Element e) => find.byElementPredicate((x) => identical(x, e), skipOffstage: false);

String _argb(Color c) => c.toARGB32().toRadixString(16).padLeft(8, '0').toUpperCase();

typedef _SurfObs = ({int n, String col, String tint, bool white, bool tint0, bool m3});

/// [DU622b] 셸 면 — [host](Dialog 또는 BottomSheet 하나)의 첫 Material(셸이 그리는 면)이 실제로 받은 color · surfaceTintColor(SDK 해석 뒤 값).
///   white = 흰색 · tint0 = tint 가 투명(null 은 false) · m3 = [m3want](그 자리 테마의 M3 기본 container 톤 — before 기대)와 같다(없으면 false).
_SurfObs _surfOf(Finder host, Color? m3want) {
  final hs = host.evaluate().toList();
  if (hs.length != 1) return (n: hs.length, col: '-', tint: '-', white: false, tint0: false, m3: false);
  final ms = find.descendant(of: _fe(hs.first), matching: find.byType(Material), skipOffstage: false).evaluate().toList();
  if (ms.isEmpty) return (n: 0, col: '-', tint: '-', white: false, tint0: false, m3: false);
  final m = ms.first.widget as Material;
  final c = m.color;
  final tc = m.surfaceTintColor;
  return (
    n: 1,
    col: c == null ? 'null' : _argb(c),
    tint: tc == null ? 'null' : _argb(tc),
    white: c != null && c.toARGB32() == Colors.white.toARGB32(),
    tint0: tc != null && tc.a == 0,
    m3: c != null && m3want != null && c.toARGB32() == m3want.toARGB32(),
  );
}

typedef _BarObs = ({int n, String top, String list});

/// [DU622b] 덮개 — 지어진 ModalBarrier 중 색이 있는 것(경로 순서) · 맨 위(마지막) 색 · 목록(기록만 · 이 셀은 덮개를 바꾸지 않는다 — 판정207 §4 D-BARRIER).
_BarObs _barOf() {
  final cs = <String>[];
  for (final e in find.byType(ModalBarrier, skipOffstage: false).evaluate()) {
    final c = (e.widget as ModalBarrier).color;
    if (c != null && c.a > 0) cs.add(_argb(c));
  }
  return (n: cs.length, top: cs.isEmpty ? '-' : cs.last, list: _enc(cs.join('|')));
}

typedef _CrObs = ({int n, String fg, String bg, String cr, bool ok45});

/// [DU622b] 글 대비 — [host] 안 그린 글(표시 제어 문자 제외)이 [want] 인 RichText 하나의 글자색 · 그 글 뒤 실제 바탕(_bgOf — 셸 Material 포함) · 대비.
_CrObs _crOf(Finder host, String want) {
  final es = find
      .descendant(of: host, matching: find.byType(RichText), skipOffstage: false)
      .evaluate()
      .where((e) => TextLayout.plain((e.widget as RichText).text.toPlainText(includeSemanticsLabels: false)) == want)
      .toList();
  if (es.length != 1) return (n: es.length, fg: '-', bg: '-', cr: '0.00', ok45: false);
  final fg = (es.first.widget as RichText).text.style?.color;
  final bg = _bgOf(es.first);
  final cr = fg == null ? 0.0 : _contrast(Color.alphaBlend(fg, bg), bg);
  return (n: 1, fg: fg == null ? '-' : _hex(fg), bg: _hex(bg), cr: cr.toStringAsFixed(2), ok45: cr >= 4.5);
}

// ───────────── [DU624b] 새로 쓴 부분 — 사례 문맥 · 공통 틀 · 셸 면 기대 · 사례 본문 3 · main ─────────────

/// [DU624b] 사례 하나의 실행 문맥 — DU622b _Run(47d89ce0 :749–:785) 과 같은 꼴 · 출력 접두 D624.
class _Run {
  _Run(this.t, this.v, this.c, this.tok, this.key, this.mode, this.seen, this.wire, this.net);
  final WidgetTester t;
  final _V v;
  final ({String id, int shots}) c;
  final String tok;
  final GlobalKey key;
  final String mode;
  final _DSeen seen;
  final _DWire wire;
  final _DNoHttp net;
  final checks = <(String, bool, String)>[];
  BuildContext? ctx;
  var shots = 0;

  Rect get screen => Offset.zero & Size(v.w, v.h);

  void need(String k, bool ok, [String why = '']) => expect(ok, isTrue, reason: '$tok $k $why');
  void chk(String k, bool ok, [String why = '']) => checks.add((k, ok, why));
  void safe(String step) => need('안전 대역($step) — 예상 밖 채널 · CF · HTTP 0', !wire.tripped && net.tries.isEmpty,
      'cf ${wire.cf.length} 예상 밖 [${wire.unexpected.join(' | ')}] http ${net.tries.length}');

  Future<void> frames(int n) async {
    for (var i = 0; i < n; i++) {
      await t.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> shot(String id, String state) async {
    _out('D624 $tok shot $id ovf=${seen.overflows.length}');
    await vqCapture(t, key, '${tok}_$id', conditions: {
      'viewport': '${v.w.toInt()}x${v.h.toInt()}', 'textScaler': v.s, 'run': vqRun, 'manifest': _manifest, 'mode': mode,
      'fixture': c.id, 'state': state,
    });
    shots++;
  }
}

/// [DU624b] 사례 공통 틀 — DU622b _oCase(47d89ce0 :790–:906)의 guard(모든 초기화보다 먼저) · 성공/실패 공통 정리 · 집계 그대로.
///   바뀐 것: 출력 접두 D624/R624 · 화면 = 빈 Scaffold 호스트 하나(RoleTheme.workerTheme · BuildContext 를 r.ctx 로) · Provider 0(창 함수가 읽지 않는다).
///   넘침: 이 셀은 배치를 바꾸지 않는다 → 두 모드 기록(TB = TA 같은 수인지 보고서 대조 · 판정207 §3 :58 '기존 overflow 각각 확인').
Future<void> _oCase(WidgetTester t, _V v, ({String id, int shots}) c, String tok, Future<String> Function(_Run r) body) async {
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final wire = _DWire();
  final net = _DNoHttp(wire);
  final prevAll = messenger.allMessagesHandler;
  final prevHttp = HttpOverrides.current;
  final prevOnError = FlutterError.onError;
  messenger.allMessagesHandler = (channel, handler, message) => wire.route(messenger, channel, handler, message);
  HttpOverrides.global = net;
  addTearDown(() {
    messenger.allMessagesHandler = prevAll;
    HttpOverrides.global = prevHttp;
    FlutterError.onError = prevOnError;
  });
  t.view.physicalSize = Size(v.w, v.h);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  final mode = _before ? 'before' : 'strict';
  _out('D624 $tok begin mode=$mode phase=${Platform.environment['DU1_VQ_PHASE'] ?? '(unset)'} env=$_envLine manifest=$_manifest');
  final seen = _DSeen();
  final key = GlobalKey();
  final r = _Run(t, v, c, tok, key, mode, seen, wire, net);
  Object? failure;
  StackTrace? failureSt;
  var raw = '';
  try {
    FlutterError.onError = seen.add;
    await t.pumpWidget(RepaintBoundary(
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
        builder: (ctx, child) => MediaQuery(data: MediaQuery.of(ctx).copyWith(textScaler: TextScaler.linear(v.s)), child: child!),
        home: Scaffold(body: Builder(builder: (bc) {
          r.ctx = bc;
          return const SizedBox.expand();
        })),
      ),
    ));
    raw = await body(r);
  } catch (e, st) {
    failure = e;
    failureSt = st;
  } finally {
    FlutterError.onError = prevOnError;
  }

  // 성공 · 실패 공통 정리 — DU622b _oCase 와 같다.
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

  final nUnexp = wire.unexpected.length;
  final nCf = wire.cf.length;
  final nHttp = net.tries.length;
  final tripped = wire.tripped;
  final unText = wire.unexpected.join(' | ');
  _out('D624 $tok att wire cf=$nCf unexpected=$nUnexp http=$nHttp');

  messenger.allMessagesHandler = prevAll;
  HttpOverrides.global = prevHttp;
  final exc = t.takeException();
  if (exc != null && failure == null) {
    failure = exc;
    failureSt = StackTrace.current;
  }
  final nOvf = seen.overflows.length;
  final nFw = seen.other.length;
  final ovfRaw = seen.overflows.join('\n----\n');
  final fwRaw = seen.other.join('\n----\n');
  _out('R624 $tok raw m64=${_enc(raw)} ovf64=${_enc(ovfRaw)} fw64=${_enc(fwRaw)} un64=${_enc(unText)} cleanup64=${_enc(cleanupErr)} '
      'fail64=${_enc(failure?.toString() ?? '')}');
  _out('D624 $tok att fw n=$nFw');
  _out('D624 $tok done state=${c.id} mode=$mode captures=${r.shots} overflows=$nOvf exc=${exc != null}');

  final f0 = failure;
  if (f0 != null) {
    _halt ??= '$tok ${f0.toString().split('\n').first}';
    Error.throwWithStackTrace(f0, failureSt ?? StackTrace.current);
  }
  final checks = r.checks;
  void chk(String k, bool ok, [String why = '']) => checks.add((k, ok, why));
  if (!_before) chk('strict 미처리 framework 예외 0', nFw == 0, fwRaw);
  chk('캡처 수 = 선언', r.shots == c.shots, 'shots ${r.shots} want ${c.shots}');
  chk('시험 전체 CF 0 · 예상 밖 채널 0 · HTTP 0(해제 · 대기 뒤)', nCf == 0 && nUnexp == 0 && nHttp == 0 && !tripped,
      'cf $nCf 예상 밖 [$unText] http $nHttp tripped $tripped');
  final bad = checks.where((x) => !x.$2).toList();
  if (bad.isNotEmpty) _halt ??= '$tok ${bad.first.$1}';
  for (final x in checks) {
    expect(x.$2, isTrue, reason: '$tok ${x.$1} ${x.$3}');
  }
}

/// [DU624b] 셸 면 기대 — 이 셀은 T0-a(role_theme 9cc10962 · DialogThemeData white/transparent) 적용 뒤 판(gN)에서만 돈다:
///   바탕 미지정 AlertDialog = 흰 · tint 투명 · M3 기본 container 톤 아님(두 모드 같다 — 이 셀은 창 면을 바꾸지 않는다).
void _surfChk(_Run r, String k, _SurfObs s) =>
    r.chk('$k 바탕 미지정 = 흰 · tint 투명(T0-a 전제 · 두 모드)', s.n == 1 && s.white && s.tint0 && !s.m3, '${s.col} ${s.tint}');

/// [DU624b] 창 닫기 — [label] 단추가 도달(보임 · 중심 hit)이면 그 InkWell 을 누르고, 아니면 루트 NavigatorState.pop([value]) 로 닫는다(누른 방법 반환).
Future<String> _closeBy(WidgetTester t, Finder host, String label, _BO reach, bool? value) async {
  if (reach.n == 1 && reach.vis && reach.hit) {
    await t.tap(find.ancestor(of: _txt(host, label, onstage: false), matching: find.byType(InkWell)).first);
    return 'tap';
  }
  t.state<NavigatorState>(find.byType(Navigator)).pop(value);
  return 'pop';
}

/// [DU624b · OSUC] OCR 일치 창 — showSuccess(통장사본 · 실제 호출 document_upload_helper.dart:533 과 같은 인자 꼴).
///   셸 면 · 덮개 · 제목/설명 전문 · 대비 · '등록하기' 도달 · 칠(주 행동 채움 · 머리 아이콘) · 1success → '등록하기' → 반환 true.
///   기준: 주 행동(진행) = brand 채움 + 흰 글(판정207 §4) · 머리 아이콘 = 실제 일치 결과 의미색 successDark 유지.
Future<String> _sucBody(_Run r) async {
  final t = r.t;
  final tok = r.tok;
  final screen = r.screen;
  final ctx = r.ctx;
  r.need('호스트 BuildContext', ctx != null);
  if (ctx == null) return 'no-ctx';
  final fut = OcrVerificationDialog.showSuccess(context: ctx, documentType: '통장사본', extractedInfo: _sInfo, confidence: 0.92);
  await r.frames(10);
  r.safe('OCR 일치 창 열림');
  final od = _dlgWith(_sTitle);
  final nOpen = od.evaluate().length;
  _out('D624 $tok att open n=$nOpen');
  r.need('OCR 일치 창 1', nOpen == 1, '개수 $nOpen');
  final ds = _surfOf(od, RoleTheme.workerTheme.colorScheme.surfaceContainerHigh);
  _out('D624 $tok att dsurf n=${ds.n} col=${ds.col} tint=${ds.tint} white=${ds.white} tint0=${ds.tint0} m3=${ds.m3}');
  _surfChk(r, 'OCR 일치 창(AlertDialog)', ds);
  final bar = _barOf();
  _out('D624 $tok att bar n=${bar.n} top=${bar.top} list=${bar.list}');
  final ot = _dlgText(t, od, _sTitle, screen);
  _out('D624 $tok att otitle n=${ot.n} full=${ot.full} brk=${ot.brk} lines=${ot.lines} vis=${ot.vis}');
  final ob = _dlgText(t, od, _sDesc, screen);
  _out('D624 $tok att obody n=${ob.n} full=${ob.full} brk=${ob.brk} lines=${ob.lines} vis=${ob.vis}');
  final tc = _crOf(od, _sTitle);
  _out('D624 $tok att otcr n=${tc.n} fg=${tc.fg} bg=${tc.bg} cr=${tc.cr} ok45=${tc.ok45}');
  final bc = _crOf(od, _sDesc);
  _out('D624 $tok att obcr n=${bc.n} fg=${bc.fg} bg=${bc.bg} cr=${bc.cr} ok45=${bc.ok45}');
  final go = await _btnReach(t, od, _sGo, screen);
  _out('D624 $tok att go n=${go.n} vis=${go.vis} hit=${go.hit} m48=${go.m48}');
  final gp = _paintOf(t, od, _sGo);
  _out('D624 $tok att gopaint n=${gp.n} fill=${gp.fill} fg=${gp.fg} cr=${gp.cr} brand=${gp.brand} white=${gp.white} icon=${gp.icon}');
  final fo = _fills(t);
  _out('D624 $tok att fills n=${fo.n} brand=${fo.brand} err=${fo.err} none=${fo.none} other=${fo.other} list=${fo.list}');
  await r.shot('1success', 'ocr-success');
  r.safe('OCR 일치 창 캡처');
  final how = await _closeBy(t, od, _sGo, go, true);
  await r.frames(10);
  final nLeft = _dlgWith(_sTitle).evaluate().length;
  final ret = await fut;
  _out('D624 $tok att close n=$nLeft how=$how ret=$ret');
  r.need('OCR 일치 창 닫힘', nLeft == 0, '남은 $nLeft');
  r.safe('OCR 일치 창 닫힘');
  final gcr = double.tryParse(gp.cr) ?? 0;
  final headOk = gp.icon == _hex(AppColors.successDark);
  final oldFill = gp.fill == _hex(AppColors.successMedium);
  r.chk('머리 의미 아이콘 successDark 유지(두 모드)', headOk, gp.icon);
  if (_before) {
    r.chk('before 주 행동 채움 = successMedium(지금 A :139)', gp.n == 1 && oldFill && !gp.brand, '${gp.fill} ${gp.cr}');
  } else {
    r.chk('strict 주 행동 채움 brand · 흰 글 대비 ≥ 4.5', gp.n == 1 && gp.brand && gp.white && gcr >= 4.5, '${gp.fill} ${gp.cr}');
  }
  r.chk('제목 · 설명 대비 ≥ 4.5(두 모드 · 글 변경 0)', tc.ok45 && bc.ok45, '${tc.cr} ${bc.cr}');
  r.chk('등록하기 반환 true', ret == true, '반환 $ret');
  return 'dsurf $ds bar $bar title $ot body $ob tcr $tc bcr $bc go $go gopaint $gp fills $fo close $nLeft/$how/$ret';
}

/// [DU624b · OWARN] 정보 불일치 창 — showWarning(통장사본 계좌번호 불일치 · 실제 호출 document_upload_helper.dart:591 과 같은 인자 꼴).
///   셸 면 · 덮개 · 제목/첫 줄/끝 안내 전문 · 대비 · '입력 정보' 값 글색(incr) · '인식 정보' 값 글색(excr) · '입력 정보' 라벨(labcr 기록) · '다시 촬영' 글색(rtcr) ·
///   두 단추 도달 · '계속 진행' 칠 · 1warning → '다시 촬영' → 반환 false.
///   기준: 주 행동(진행 · 손실 아님) = brand 채움 · 일반 자료 글 = 중립(textPrimary) · 불일치 값 = 주의 의미색 warningDark 유지 · 머리 = 실제 주의 warningDark 유지.
Future<String> _warnBody(_Run r) async {
  final t = r.t;
  final tok = r.tok;
  final screen = r.screen;
  final ctx = r.ctx;
  r.need('호스트 BuildContext', ctx != null);
  if (ctx == null) return 'no-ctx';
  final fut = OcrVerificationDialog.showWarning(context: ctx, documentType: '통장사본', expectedInfo: _wExp, extractedInfo: _wExt, reason: _wReason);
  await r.frames(10);
  r.safe('정보 불일치 창 열림');
  final od = _dlgWith(_wTitle);
  final nOpen = od.evaluate().length;
  _out('D624 $tok att open n=$nOpen');
  r.need('정보 불일치 창 1', nOpen == 1, '개수 $nOpen');
  final ds = _surfOf(od, RoleTheme.workerTheme.colorScheme.surfaceContainerHigh);
  _out('D624 $tok att dsurf n=${ds.n} col=${ds.col} tint=${ds.tint} white=${ds.white} tint0=${ds.tint0} m3=${ds.m3}');
  _surfChk(r, '정보 불일치 창(AlertDialog)', ds);
  final bar = _barOf();
  _out('D624 $tok att bar n=${bar.n} top=${bar.top} list=${bar.list}');
  final ot = _dlgText(t, od, _wTitle, screen);
  _out('D624 $tok att otitle n=${ot.n} full=${ot.full} brk=${ot.brk} lines=${ot.lines} vis=${ot.vis}');
  final ob = _dlgText(t, od, _wHead, screen);
  _out('D624 $tok att obody n=${ob.n} full=${ob.full} brk=${ob.brk} lines=${ob.lines} vis=${ob.vis}');
  final ol = _dlgText(t, od, _wLast, screen);
  _out('D624 $tok att olast n=${ol.n} full=${ol.full} brk=${ol.brk} lines=${ol.lines} vis=${ol.vis}');
  final tc = _crOf(od, _wTitle);
  _out('D624 $tok att otcr n=${tc.n} fg=${tc.fg} bg=${tc.bg} cr=${tc.cr} ok45=${tc.ok45}');
  final bc = _crOf(od, _wHead);
  _out('D624 $tok att obcr n=${bc.n} fg=${bc.fg} bg=${bc.bg} cr=${bc.cr} ok45=${bc.ok45}');
  final ic = _crOf(od, _wExp);
  _out('D624 $tok att incr n=${ic.n} fg=${ic.fg} bg=${ic.bg} cr=${ic.cr} ok45=${ic.ok45}');
  final ec = _crOf(od, _wExt);
  _out('D624 $tok att excr n=${ec.n} fg=${ec.fg} bg=${ec.bg} cr=${ec.cr} ok45=${ec.ok45}');
  final lc = _crOf(od, _wLab);
  _out('D624 $tok att labcr n=${lc.n} fg=${lc.fg} bg=${lc.bg} cr=${lc.cr} ok45=${lc.ok45}');
  final rc = _crOf(od, _wRetake);
  _out('D624 $tok att rtcr n=${rc.n} fg=${rc.fg} bg=${rc.bg} cr=${rc.cr} ok45=${rc.ok45}');
  final no = await _btnReach(t, od, _wRetake, screen);
  _out('D624 $tok att no n=${no.n} vis=${no.vis} hit=${no.hit} m48=${no.m48}');
  final go = await _btnReach(t, od, _wGo, screen);
  _out('D624 $tok att go n=${go.n} vis=${go.vis} hit=${go.hit} m48=${go.m48}');
  final gp = _paintOf(t, od, _wGo);
  _out('D624 $tok att gopaint n=${gp.n} fill=${gp.fill} fg=${gp.fg} cr=${gp.cr} brand=${gp.brand} white=${gp.white} icon=${gp.icon}');
  final fo = _fills(t);
  _out('D624 $tok att fills n=${fo.n} brand=${fo.brand} err=${fo.err} none=${fo.none} other=${fo.other} list=${fo.list}');
  await r.shot('1warning', 'ocr-mismatch');
  r.safe('정보 불일치 창 캡처');
  final how = await _closeBy(t, od, _wRetake, no, false);
  await r.frames(10);
  final nLeft = _dlgWith(_wTitle).evaluate().length;
  final ret = await fut;
  _out('D624 $tok att close n=$nLeft how=$how ret=$ret');
  r.need('정보 불일치 창 닫힘', nLeft == 0, '남은 $nLeft');
  r.safe('정보 불일치 창 닫힘');
  final gcr = double.tryParse(gp.cr) ?? 0;
  final headOk = gp.icon == _hex(AppColors.warningDark);
  final oldFill = gp.fill == _hex(AppColors.warningMedium);
  final oldIn = ic.fg == _hex(AppColors.infoDark);
  final newIn = ic.fg == _hex(AppColors.textPrimary);
  final exOk = ec.fg == _hex(AppColors.warningDark);
  final rtOk = rc.fg == _hex(AppColors.brand);
  r.chk('머리 의미 아이콘 warningDark 유지(두 모드)', headOk, gp.icon);
  r.chk("'인식 정보' 값 글 warningDark 유지(두 모드 · 불일치 의미)", ec.n == 1 && exOk, ec.fg);
  r.chk("'다시 촬영' 보조 행동 글 brand 유지(두 모드 · primaryColor)", rc.n == 1 && rtOk && rc.ok45, '${rc.fg} ${rc.cr}');
  if (_before) {
    r.chk('before 주 행동 채움 = warningMedium(지금 A :277)', gp.n == 1 && oldFill && !gp.brand, '${gp.fill} ${gp.cr}');
    r.chk("before '입력 정보' 값 글 = infoDark(지금 A :223)", ic.n == 1 && oldIn, ic.fg);
  } else {
    r.chk('strict 주 행동 채움 brand · 흰 글 대비 ≥ 4.5', gp.n == 1 && gp.brand && gp.white && gcr >= 4.5, '${gp.fill} ${gp.cr}');
    r.chk("strict '입력 정보' 값 글 = textPrimary · 대비 ≥ 4.5", ic.n == 1 && newIn && ic.ok45, '${ic.fg} ${ic.cr}');
  }
  r.chk('제목 · 첫 줄 대비 ≥ 4.5(두 모드 · 글 변경 0)', tc.ok45 && bc.ok45, '${tc.cr} ${bc.cr}');
  r.chk('다시 촬영 반환 false', ret == false, '반환 $ret');
  return 'dsurf $ds bar $bar title $ot body $ob last $ol tcr $tc bcr $bc incr $ic excr $ec labcr $lc rtcr $rc no $no go $go gopaint $gp fills $fo '
      'close $nLeft/$how/$ret';
}

/// [DU624b · OERR] 인식 실패 창 — showError(신분증 · allowContinue true · 실제 호출 document_upload_helper.dart:244 과 같은 인자 꼴 · DU622b OCRE 흐름).
///   셸 면 · 덮개 · 제목/본문/'오류:' 줄 전문 · 대비 · '그대로 등록' 글색(keepcr) · '취소' 글색(nocr 기록) · 세 단추 도달 · '다시 시도' 칠 · 1error → '취소' → 반환 false.
///   기준: 보조 행동(진행) 글 = brand · 취소 = 중립 · 주 행동 '다시 시도' = brand 채움(primaryColor) · '오류:' 상세 = 실제 오류 errorDark 유지 · 머리 = errorDark 유지.
Future<String> _errBody(_Run r) async {
  final t = r.t;
  final tok = r.tok;
  final screen = r.screen;
  final ctx = r.ctx;
  r.need('호스트 BuildContext', ctx != null);
  if (ctx == null) return 'no-ctx';
  final fut = OcrVerificationDialog.showError(context: ctx, documentType: '신분증', errorMessage: _oErr, allowContinue: true);
  await r.frames(10);
  r.safe('인식 실패 창 열림');
  final od = _dlgWith(_oTitle);
  final nOpen = od.evaluate().length;
  _out('D624 $tok att open n=$nOpen');
  r.need('인식 실패 창 1', nOpen == 1, '개수 $nOpen');
  final ds = _surfOf(od, RoleTheme.workerTheme.colorScheme.surfaceContainerHigh);
  _out('D624 $tok att dsurf n=${ds.n} col=${ds.col} tint=${ds.tint} white=${ds.white} tint0=${ds.tint0} m3=${ds.m3}');
  _surfChk(r, '인식 실패 창(AlertDialog)', ds);
  final bar = _barOf();
  _out('D624 $tok att bar n=${bar.n} top=${bar.top} list=${bar.list}');
  final ot = _dlgText(t, od, _oTitle, screen);
  _out('D624 $tok att otitle n=${ot.n} full=${ot.full} brk=${ot.brk} lines=${ot.lines} vis=${ot.vis}');
  final ob = _dlgText(t, od, _oBody, screen);
  _out('D624 $tok att obody n=${ob.n} full=${ob.full} brk=${ob.brk} lines=${ob.lines} vis=${ob.vis}');
  final ol = _dlgText(t, od, _oLast, screen);
  _out('D624 $tok att olast n=${ol.n} full=${ol.full} brk=${ol.brk} lines=${ol.lines} vis=${ol.vis}');
  final tc = _crOf(od, _oTitle);
  _out('D624 $tok att otcr n=${tc.n} fg=${tc.fg} bg=${tc.bg} cr=${tc.cr} ok45=${tc.ok45}');
  final bc = _crOf(od, _oBody);
  _out('D624 $tok att obcr n=${bc.n} fg=${bc.fg} bg=${bc.bg} cr=${bc.cr} ok45=${bc.ok45}');
  final lc = _crOf(od, _oLast);
  _out('D624 $tok att olcr n=${lc.n} fg=${lc.fg} bg=${lc.bg} cr=${lc.cr} ok45=${lc.ok45}');
  final kc = _crOf(od, _oKeep);
  _out('D624 $tok att keepcr n=${kc.n} fg=${kc.fg} bg=${kc.bg} cr=${kc.cr} ok45=${kc.ok45}');
  final nc = _crOf(od, _oCancel);
  _out('D624 $tok att nocr n=${nc.n} fg=${nc.fg} bg=${nc.bg} cr=${nc.cr} ok45=${nc.ok45}');
  final no = await _btnReach(t, od, _oCancel, screen);
  _out('D624 $tok att no n=${no.n} vis=${no.vis} hit=${no.hit} m48=${no.m48}');
  final kp = await _btnReach(t, od, _oKeep, screen);
  _out('D624 $tok att keep n=${kp.n} vis=${kp.vis} hit=${kp.hit} m48=${kp.m48}');
  final rt = await _btnReach(t, od, _oRetry, screen);
  _out('D624 $tok att retry n=${rt.n} vis=${rt.vis} hit=${rt.hit} m48=${rt.m48}');
  final rp = _paintOf(t, od, _oRetry);
  _out('D624 $tok att repaint n=${rp.n} fill=${rp.fill} fg=${rp.fg} cr=${rp.cr} brand=${rp.brand} white=${rp.white} icon=${rp.icon}');
  final fo = _fills(t);
  _out('D624 $tok att fills n=${fo.n} brand=${fo.brand} err=${fo.err} none=${fo.none} other=${fo.other} list=${fo.list}');
  await r.shot('1error', 'ocr-error');
  r.safe('인식 실패 창 캡처');
  final how = await _closeBy(t, od, _oCancel, no, false);
  await r.frames(10);
  final nLeft = _dlgWith(_oTitle).evaluate().length;
  final ret = await fut;
  _out('D624 $tok att close n=$nLeft how=$how ret=$ret');
  r.need('인식 실패 창 닫힘', nLeft == 0, '남은 $nLeft');
  r.safe('인식 실패 창 닫힘');
  final rcr = double.tryParse(rp.cr) ?? 0;
  final headOk = rp.icon == _hex(AppColors.errorDark);
  final errOk = lc.fg == _hex(AppColors.errorDark);
  final oldKeep = kc.fg == _hex(AppColors.warningDark);
  final newKeep = kc.fg == _hex(AppColors.brand);
  r.chk('머리 의미 아이콘 errorDark 유지(두 모드)', headOk, rp.icon);
  r.chk("'오류:' 상세 글 errorDark 유지 · 대비 ≥ 4.5(두 모드)", lc.n == 1 && errOk && lc.ok45, '${lc.fg} ${lc.cr}');
  r.chk("주 행동 '다시 시도' brand 채움 · 흰 글 대비 ≥ 4.5(두 모드 · primaryColor)", rp.n == 1 && rp.brand && rp.white && rcr >= 4.5, '${rp.fill} ${rp.cr}');
  if (_before) {
    r.chk("before '그대로 등록' 글 = warningDark(지금 A :410)", kc.n == 1 && oldKeep, kc.fg);
  } else {
    r.chk("strict '그대로 등록' 글 = brand · 대비 ≥ 4.5", kc.n == 1 && newKeep && kc.ok45, '${kc.fg} ${kc.cr}');
  }
  r.chk('제목 · 본문 대비 ≥ 4.5(두 모드 · 글 변경 0)', tc.ok45 && bc.ok45, '${tc.cr} ${bc.cr}');
  r.chk('취소 반환 false', ret == false, '반환 $ret');
  return 'dsurf $ds bar $bar title $ot body $ob last $ol tcr $tc bcr $bc lcr $lc keepcr $kc nocr $nc no $no keep $kp retry $rt repaint $rp fills $fo '
      'close $nLeft/$how/$ret';
}

void main() {
  setUpAll(() async {
    await _loadFonts();
  });
  for (final v in _views) {
    for (final c in _cases) {
      testWidgets('S624OC-${v.id}-${c.id} OCR 확인창 색 역할(판정207 §4)', (t) async {
        final tok = 'S624OC-${v.id}-${c.id}';
        if (_halt != null) fail('$tok 진입 0 — 앞 실패: $_halt');
        await _oCase(t, v, c, tok, switch (c.id) { 'OSUC' => _sucBody, 'OWARN' => _warnBody, _ => _errBody });
      }, skip: !_optIn);
    }
  }
}
