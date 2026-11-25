// ignore_for_file: depend_on_referenced_packages
// [DU600b · 파일 셀 · 표시만] DU-S030 공고 등록(lib/screens/business_admin/to_management/create_to_screen.dart) 결정 미이행 —
//   장부 089 · 판정114 §6 :103 S030 불러오기 시트: ① 빈 목록 전체가 보일 본문 칸 · 독립 스크롤 우선 · 아래 안내 띠 자연 높이
//     (시트 높이 0.72 고정 → 글자 배율만큼 · 최대 1.0) ② 안내의 가운뎃점 덩어리를 의미구로(낱말 사이 · '·' 뒤에서만 줄바꿈 · 문구 그대로).
//   장부 146 · 판정126 §4 :51 사업장 선택칸 — '실제 잘림을 개별 관측한 뒤' wrapLabel opt-in: 이 셀은 **관측만**(att bz · 두 모드 같은 코드 · 기록만).
//   before = 지금 A(create_to_screen 603a502c = DU488 후보) 기록 · strict = 후보(cand/ · mkcell 이 SHA 대조).
//   하네스 = 블록 재사용(prep/mk_test.py 가 원본 fullSHA · 블록 sha12 · 경계 줄 단언): DU595b suite(7e30c11e · 판정177 §5 수용) —
//     가짜 Firebase · 글꼴 · max 판 _fullShown · _textObs · _area · _lineCount · 보기 W/B/N · _halt · env 줄 · _DSeen · _txt · _semOf ·
//     색 도우미 · _fills · _inkOf / DU581 r3 suite(3f4a404a · DONE 5/5) — _hitWithin / DU488 suite(fafffa51 · DONE 5/5 · 같은 시트) — 사업장 관리자 대역.
//   새로 쓴 것: 이 머리 · 사례 1(SHEET) · 글 상수 · 읽기 경계(DU488 대역 꼴 · 사업장 이름만 긴 이름) · 그린 그대로 재기 _drawn · 사례 본문 _caseOf · main.
//   누르는 것 = 시작 단추 'host'(DU488 과 같다) · 앱 바 '불러오기' 글 중심(tapAt · 잰 hit 와 같은 점)뿐 — 저장 · 게시 · 불러오기 항목 선택 0 · 쓰기 0.
//   기본 skip — TB before/du600bct-tb/DU_BEFORE_OBSERVE=600 · TA after/du600bct-ta/없음.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui show BoxHeightStyle;

import 'package:cloud_firestore_platform_interface/cloud_firestore_platform_interface.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ALfit/models/core/business_member_model.dart';
import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/providers/notification_provider.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/screens/business_admin/to_management/create_to_screen.dart';
import 'package:ALfit/theme/app_colors.dart';
import 'package:ALfit/theme/role_theme.dart';
import 'package:ALfit/utils/navigation_key.dart';
import 'package:ALfit/utils/text_layout.dart';
import 'package:ALfit/widgets/app_select_field.dart';

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

typedef _TextObs = ({bool shown, bool name, bool full, bool ell0, int brk, Size size});

/// Text 하나의 관측값(잰 즉시 값으로 굳힌다) — 그려진 글(표시 제어 문자를 뺀 것) · 읽는 이름이 각각 [want] 원문과 같은가 · 전문 · 말줄임 설정 · 낱말 안 끊김 수.
_TextObs _textObs(WidgetTester t, Finder textF, String want) {
  final rp = t.renderObject<RenderParagraph>(find.descendant(of: textF, matching: find.byType(RichText), skipOffstage: true).first);
  final size = rp.size;
  final shown = TextLayout.plain(rp.text.toPlainText(includeSemanticsLabels: false));
  final name = rp.text.toPlainText();
  return (shown: shown == want, name: name == want, full: _fullShown(rp, size), ell0: rp.overflow != TextOverflow.ellipsis, brk: _midBreaks(rp), size: size);
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

/// [DU600b] 사례 — SHEET = 공고 등록 폼 첫 화면(사업장 선택칸 관측 · 1form) → 앱 바 '불러오기' → 이전 공고 0 인 불러오기 시트(2sheet).
const _cases = <({String id, int shots})>[(id: 'SHEET', shots: 2)];

/// [DU600b] 이 셀이 보는 글 — mkcell 이 base/후보 원문과 대조한다(두 모드 같은 글).
const _kNote = '공고 제목·관리용 카드명·공통 안내·근무유형·요일·업무 설정을 불러옵니다. 날짜와 공개 설정은 포함되지 않습니다.';
const _kTitle = '기존 공고 불러오기';
const _kEmpty = '등록된 공고가 없습니다';
const _kLoadBtn = '불러오기';

/// [DU600b · 장부 146 관측] 사업장 이름 — 실제 잘림을 보려는 긴 이름(대역 값 · 두 모드 같음 · README §0).
const _kBizName = 'QA 평택 제2 물류센터 포장동';

final bool _before = Platform.environment['DU_BEFORE_OBSERVE'] == '600';
final Map<String, String> _env = Platform.environment;
final bool _optIn =
    (_env['DU1_VQ_PHASE'] == 'before' && _env['DU1_VQ_RUN'] == 'du600bct-tb' && _env['DU_BEFORE_OBSERVE'] == '600') ||
        (_env['DU1_VQ_PHASE'] == 'after' && _env['DU1_VQ_RUN'] == 'du600bct-ta' && _env['DU_BEFORE_OBSERVE'] == null);

/// 첫 실패 뒤 사례는 본문에 들어가지 않는다(진입 0 · 캡처 0).
String? _halt;
final String _manifest = Platform.environment['DUL_MANIFEST'] ?? '(unset)';
const _envKeys = ['DU_BEFORE_OBSERVE', 'DU1_VQ_PHASE', 'DU1_VQ_OUT', 'DU1_VQ_RUN', 'DU1_VQ_DATE', 'DU397_DIAG', 'DU397_MANIFEST', 'DU400_MANIFEST',
  'DU401_MANIFEST', 'DU398_MANIFEST', 'DU406_MANIFEST', 'DU407_MANIFEST', 'DU296_PHASE', 'DUL_MANIFEST'];
final String _envLine = [for (final k in _envKeys) '$k:${Platform.environment[k] ?? '(unset)'}'].join(',');

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

// [DU600b] 아래 측정 도우미는 DU595b suite(7e30c11e · 판정177 §5 수용)에서 바이트 그대로 옮겼다 — :229–232(_txt) · :246–247(_semOf) ·
//   :272–355(_lum · _contrast · _hex · _bgOf · _FillObs · _fills · _InkObs · _inkOf). 이 셀은 지연 목록 · ensureVisible 측정을 쓰지 않아 _bringBuilt · _TO · _textLine 은 옮기지 않았다.

Finder _txt(Finder scope, String want, {bool onstage = true}) => find.descendant(
    of: scope,
    matching: find.byWidgetPredicate((w) => w is Text && TextLayout.plain(w.data ?? w.textSpan?.toPlainText() ?? '') == want),
    skipOffstage: onstage);

/// 읽는 이름 — Text.semanticsLabel(있으면) · 없으면 span 의 읽는 이름을 포함한 평문 · 그다음 data.
String _semOf(Text w) => w.semanticsLabel ?? w.textSpan?.toPlainText() ?? w.data ?? '';

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

/// [DU592b] 칩 · 배지 글의 칠 — [tf](_textLine 이 ensureVisible 하고 잰 **같은 Finder** · 점검표 A1) 안 글(RichText)의 글자색 ·
///   그 글 뒤 실제 바탕(_bgOf — 면이 반투명이면 아래 면과 섞는다) · 대비. 잰 즉시 값으로 굳힌다(뒤에 UI 를 다시 읽지 않는다).
typedef _InkObs = ({int n, String fg, String bg, String cr, bool ok45});

_InkObs _inkOf(Finder tf) {
  final es = find.descendant(of: tf, matching: find.byType(RichText), skipOffstage: false).evaluate().toList();
  if (es.length != 1) return (n: es.length, fg: '-', bg: '-', cr: '0.00', ok45: false);
  final Color? fg = (es.first.widget as RichText).text.style?.color;
  final bg = _bgOf(es.first);
  final cr = fg == null ? 0.0 : _contrast(fg, bg);
  return (n: 1, fg: fg == null ? '-' : _hex(fg), bg: _hex(bg), cr: cr.toStringAsFixed(2), ok45: cr >= 4.5);
}

// [DU600b] 누르는 자리 hit — DU581 r3 suite(3f4a404a · run DONE 5/5 19:35:21)의 :193–204 바이트 그대로(_hitWithin).

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

// [DU600b] 사업장 관리자 대역 — DU488 suite(fafffa51 · run DONE 5/5 06:36 · 같은 시트)의 :49–67 바이트 그대로(kBiz · kOwner · _Owner).

const kBiz = 'biz-local-c50';
const kOwner = 'owner-local-c50';

/// du1_c1_create_discard_test 와 같은 사업장 관리자 대역.
class _Owner extends UserProvider {
  @override
  UserModel? get currentUser => UserModel(uid: kOwner, username: 'owner', name: 'QA 사장', email: 'o@test.local',
      role: UserRole.BUSINESS_ADMIN, businessId: kBiz, managedBusinessIds: const [kBiz], createdAt: DateTime(2026, 1, 1));
  @override
  bool get isBusinessAdmin => true;
  @override
  bool get isSubAdmin => false;
  @override
  bool get isAdminMode => true;
  @override
  bool get permissionsLoaded => true;
  @override
  bool canForBusiness(String businessId, bool Function(MemberPermissions p) check) => true;
}

// ───────────── [DU600b] 새로 쓴 부분 — 읽기 경계 · 그린 그대로 재기 · 사례 본문 ─────────────

/// [DU600b] 읽기 경계 — DU488 suite(fafffa51) main 안 stubChannels(:171–226)와 같은 대역: 사업장 · 사장(날인) 문서 get · 업무 유형/계약 템플릿 query ·
///   '불러오기' 목록 CF(callableGetTOsByBiz) = 빈 목록 · 그 밖 Firestore 쓰기/읽기 · Functions 는 오류로 막는다. 바꾼 것: 최상위 함수로 옮김 ·
///   사업장 이름 = _kBizName(장부 146 관측) · 막음 표지 'du600b-blocked'.
void _stub() {
  const base = 'dev.flutter.pigeon.cloud_firestore_platform_interface.FirebaseFirestoreHostApi';
  final meta = PigeonSnapshotMetadata(hasPendingWrites: false, isFromCache: false);
  final m = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const codec = FirebaseFirestoreHostApi.codec;
  m.setMockMessageHandler('$base.documentReferenceGet', (msg) async {
    final args = codec.decodeMessage(msg) as List;
    final path = (args[1] as DocumentReferenceRequest).path;
    Map<String?, Object?>? data;
    if (path == 'businesses/$kBiz') {
      data = {
        'name': _kBizName, 'businessNumber': '000-00-00000', 'category': '물류', 'subCategory': '포장', 'address': '서울시 QA구 1',
        'ownerId': kOwner, 'adminIds': [kOwner], 'isApproved': true, 'createdAt': Timestamp.fromDate(DateTime(2026, 10, 1)),
        'businessLicenseImageUrl': 'https://example.invalid/qa-license.png',
      };
    } else if (path == 'users/$kOwner') {
      data = {'role': 'BUSINESS_ADMIN', 'name': 'QA 사장', 'sealBase64': 'LOCAL-QA-SEAL'};
    } else {
      return codec.encodeMessage(<Object?>['du600b-blocked', 'get 차단: $path', null]);
    }
    return codec.encodeMessage(<Object?>[PigeonDocumentSnapshot(path: path, data: data, metadata: meta)]);
  });
  m.setMockMessageHandler('$base.queryGet', (msg) async {
    final raw = String.fromCharCodes(msg!.buffer.asUint8List(msg.offsetInBytes, msg.lengthInBytes));
    final List<PigeonDocumentSnapshot> docs;
    if (raw.contains('businesses/$kBiz/workTypes')) {
      docs = [
        PigeonDocumentSnapshot(path: 'businesses/$kBiz/workTypes/wt-c50', data: <String?, Object?>{
          'businessId': kBiz, 'name': '포장', 'icon': 'box', 'color': '#3859E8', 'backgroundColor': '#EEF2FF',
          'displayOrder': 0, 'isActive': true, 'createdAt': Timestamp.fromDate(DateTime(2026, 10, 1)),
        }, metadata: meta),
      ];
    } else if (raw.contains('businesses/$kBiz/contract_templates')) {
      docs = [
        PigeonDocumentSnapshot(path: 'businesses/$kBiz/contract_templates/tpl-c50', data: <String?, Object?>{
          'businessId': kBiz, 'name': '단기 근무 기본', 'templateType': 'daily', 'articles': const [],
          'createdAt': Timestamp.fromDate(DateTime(2026, 10, 2)),
        }, metadata: meta),
      ];
    } else {
      return codec.encodeMessage(<Object?>['du600b-blocked', 'query 차단', null]);
    }
    return codec.encodeMessage(<Object?>[PigeonQuerySnapshot(documents: docs, documentChanges: const [], metadata: meta)]);
  });
  for (final op in const ['documentReferenceSet', 'documentReferenceUpdate', 'documentReferenceDelete', 'writeBatchCommit',
    'transactionCreate', 'aggregateQuery', 'querySnapshot', 'documentReferenceSnapshot']) {
    m.setMockMessageHandler('$base.$op', (msg) async => codec.encodeMessage(<Object?>['du600b-blocked', '$op 차단', null]));
  }
  m.setMockMessageHandler('dev.flutter.pigeon.cloud_functions_platform_interface.CloudFunctionsHostApi.call', (msg) async {
    const c = StandardMessageCodec();
    final args = (c.decodeMessage(msg) as List).first as Map;
    if (args['functionName'] == 'callableGetTOsByBiz') {
      return c.encodeMessage(<Object?>[<String, Object?>{'tos': <Object?>[]}]);
    }
    return c.encodeMessage(<Object?>['du600b-blocked', 'functions 차단', null]);
  });
}

typedef _DrawnObs = ({int n, bool shown, bool sem, bool full, bool ell0, int brk, int lines, bool vis, Rect r});

/// [DU600b] 글 하나 — **그려진 그대로** 잰다(ensureVisible 0 · 시트 본문이 아래 안내 띠 앞에서 잘린 상태를 숨기지 않는다 — DU597b _tabObs 와 같은 원칙 · A1).
///   shown · full · ell0 · brk = _textObs(max 판 _fullShown 그대로) · lines = _lineCount · vis = 화면 ∩ 조상 스크롤 칸 안 · n ≠ 1 이면 재지 않는다. 잰 즉시 값으로 굳힌다.
_DrawnObs _drawn(WidgetTester t, Finder tf, String want, Rect screen) {
  final n = tf.evaluate().length;
  if (n != 1) {
    return (n: n, shown: false, sem: false, full: false, ell0: false, brk: 0, lines: 0, vis: false, r: Rect.zero);
  }
  final o = _textObs(t, tf, want);
  final r = t.getRect(tf);
  return (
    n: n,
    shown: o.shown,
    sem: _semOf(t.widget<Text>(tf)) == want,
    full: o.full,
    ell0: o.ell0,
    brk: o.brk,
    lines: _lineCount(t.renderObject<RenderParagraph>(find.descendant(of: tf, matching: find.byType(RichText), skipOffstage: true).first)),
    vis: _inside(r, _area(tf, screen)),
    r: r,
  );
}

/// [DU600b] 사례 — 공고 등록 폼을 열고(시작 단추 'host') ① 사업장 선택칸 이름 관측(장부 146 · 기록만) · 채움 단추(A8) · 1form
///   ② 앱 바 '불러오기' 글 중심을 눌러(잰 hit 와 같은 점) 이전 공고 0 인 시트 → 시트 높이 · 제목 · 빈 목록(아이콘 · 글 · 본문 칸) · 아래 안내 · 채움 단추 · 2sheet.
Future<void> _caseOf(WidgetTester t, _V v, ({String id, int shots}) c, String tok) async {
  final prevOnError = FlutterError.onError;
  addTearDown(() => FlutterError.onError = prevOnError);
  t.view.physicalSize = Size(v.w, v.h);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  final mode = _before ? 'before' : 'strict';
  _out('D600 $tok begin mode=$mode phase=${Platform.environment['DU1_VQ_PHASE'] ?? '(unset)'} env=$_envLine manifest=$_manifest');
  final seen = _DSeen();
  final checks = <(String, bool, String)>[];
  void chk(String k, bool ok, [String why = '']) => checks.add((k, ok, why));
  Object? failure;
  StackTrace? failureSt;
  var shots = 0;
  var raw = '';
  // 모은 단언 재료 — 측정 즉시 값(뒤에 UI 를 다시 읽지 않는다).
  var okBefore = false;
  var okStrict = false;
  try {
    FlutterError.onError = seen.add;
    _stub();
    final key = GlobalKey();
    await t.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<UserProvider>(create: (_) => _Owner()),
        ChangeNotifierProvider<NotificationProvider>(create: (_) => NotificationProvider()),
      ],
      child: RepaintBoundary(
        key: key,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          navigatorKey: navigatorKey,
          theme: RoleTheme.businessAdminTheme,
          builder: (ctx, child) => MediaQuery(data: MediaQuery.of(ctx).copyWith(textScaler: TextScaler.linear(v.s)), child: child!),
          home: Builder(builder: (ctx) => Scaffold(body: Center(child: TextButton(
              onPressed: () => Navigator.of(ctx).push(MaterialPageRoute<void>(builder: (_) => const AdminCreateTOScreen(initialBusinessId: kBiz))),
              child: const Text('host'))))),
        ),
      ),
    ));
    Future<void> settle(int n) async {
      for (var i = 0; i < n; i++) {
        await t.pump(const Duration(milliseconds: 50));
      }
    }

    await t.pump();
    await t.tap(find.text('host'));
    await settle(16);
    final host = find.byType(AdminCreateTOScreen);
    final nHost = host.evaluate().length;
    if (nHost != 1) throw StateError('공고 등록 화면 $nHost');
    Future<void> shot(String id, String state) async {
      _out('D600 $tok shot $id ovf=${seen.overflows.length}');
      await vqCapture(t, key, '${tok}_$id', conditions: {
        'viewport': '${v.w.toInt()}x${v.h.toInt()}', 'textScaler': v.s, 'run': vqRun, 'manifest': _manifest, 'mode': mode,
        'fixture': c.id, 'state': state,
      });
      shots++;
    }

    final screen = Offset.zero & Size(v.w, v.h);
    // ① 폼 첫 화면 — 사업장 선택칸 이름(장부 146 · 실제 잘림 관측만 · 이 후보는 선택칸을 바꾸지 않는다) · 채움 단추(A8 · 기록만).
    final fieldF = find.byWidgetPredicate((w) => w is AppSelectField);
    final bz = _drawn(t, _txt(fieldF, _kBizName, onstage: false), _kBizName, screen);
    _out('D600 $tok att bz n=${bz.n} full=${bz.full} ell0=${bz.ell0} lines=${bz.lines} vis=${bz.vis}');
    final f0 = _fills(t);
    _out('D600 $tok att f0 n=${f0.n} brand=${f0.brand} err=${f0.err} none=${f0.none} other=${f0.other} list=${f0.list}');
    await shot('1form', 'form-top');
    // ② 앱 바 '불러오기' 글 중심을 누른다 — 그 점이 그 단추(ButtonStyleButton)에 맞지 않으면 누르지 않는다(시트 0 → 아래에서 멈춤).
    final loadF = _txt(find.byType(AppBar), _kLoadBtn, onstage: false);
    final nLoad = loadF.evaluate().length;
    if (nLoad != 1) throw StateError('불러오기 $nLoad');
    final lp = t.getRect(loadF).center;
    final loadBtn = find.ancestor(of: loadF, matching: find.byWidgetPredicate((w) => w is ButtonStyleButton)).first;
    if (!_hitWithin(t, loadBtn, lp)) throw StateError('불러오기 중심 hit 거짓');
    await t.tapAt(lp);
    await settle(20);
    final sheetF = find.byType(BottomSheet);
    final nSheet = sheetF.evaluate().length;
    if (nSheet != 1) throw StateError('시트 $nSheet');
    // 시트 높이 — 지금 A: 화면 × 0.72 + 아래 여백 8(DialogHelper.sheetBottomInset) · 후보: 글자 배율만큼(B 는 시트가 허용하는 최대).
    final sr = t.getRect(sheetF);
    final grow = sr.height > 0.72 * v.h + 8 + 0.5;
    _out('D600 $tok att sh h=${sr.height.toStringAsFixed(1)} r=${(sr.height / v.h).toStringAsFixed(2)} top=${sr.top.toStringAsFixed(1)} grow=$grow');
    final tt = _drawn(t, _txt(sheetF, _kTitle, onstage: false), _kTitle, screen);
    _out('D600 $tok att tt n=${tt.n} shown=${tt.shown} sem=${tt.sem} full=${tt.full} brk=${tt.brk} lines=${tt.lines} vis=${tt.vis}');
    // 빈 목록 — 아이콘 · 글을 그린 그대로(본문 스크롤 칸 ∩ 화면 안인가) · 본문 칸 높이 · 둘이 차지하는 높이.
    final emF = _txt(sheetF, _kEmpty, onstage: false);
    final em = _drawn(t, emF, _kEmpty, screen);
    final icF = find.descendant(of: sheetF, matching: find.byIcon(Icons.inbox_outlined), skipOffstage: false);
    final nIc = icF.evaluate().length;
    final ir = nIc == 1 ? t.getRect(icF) : Rect.zero;
    final iv = nIc == 1 && _inside(ir, _area(icF, screen));
    final bodyF = find.ancestor(of: emF, matching: find.byType(Scrollable));
    final hasBody = em.n == 1 && bodyF.evaluate().isNotEmpty;
    final bh = hasBody ? t.getSize(bodyF.first).height : 0.0;
    final need = em.n == 1 && nIc == 1 ? em.r.bottom - ir.top : 0.0;
    final nEm = em.n == 1 && nIc == 1 ? 1 : 0;
    _out('D600 $tok att em n=$nEm iv=$iv tv=${em.vis} tlines=${em.lines} tbrk=${em.brk} bh=${bh.toStringAsFixed(1)} need=${need.toStringAsFixed(1)}');
    // 아래 안내 — 글(그린 그대로) · 칠/대비(_inkOf 같은 Finder) · 띠 높이 · 본문과 따로 스크롤(안내 조상 Scrollable 0 · 빈 목록은 조상 Scrollable 있음).
    final ntF = _txt(sheetF, _kNote, onstage: false);
    final nt = _drawn(t, ntF, _kNote, screen);
    final io = _inkOf(ntF);
    final footF = find.ancestor(of: ntF, matching: find.byWidgetPredicate((w) => w is Container && w.color == AppColors.grey100));
    final fh = nt.n == 1 && footF.evaluate().isNotEmpty ? t.getSize(footF.first).height : 0.0;
    final ind = nt.n == 1 && find.ancestor(of: ntF, matching: find.byType(Scrollable)).evaluate().isEmpty && hasBody;
    _out('D600 $tok att nt n=${nt.n} shown=${nt.shown} sem=${nt.sem} full=${nt.full} brk=${nt.brk} lines=${nt.lines} vis=${nt.vis} ind=$ind fg=${io.fg} c45=${io.ok45} fh=${fh.toStringAsFixed(1)}');
    final fs = _fills(t);
    _out('D600 $tok att fs n=${fs.n} brand=${fs.brand} err=${fs.err} none=${fs.none} other=${fs.other} list=${fs.list}');
    await shot('2sheet', 'load-sheet-empty');
    final allIn = iv && em.vis;
    final same = bz.n == 1 && tt.n == 1 && tt.shown && tt.sem && tt.full && tt.brk == 0 && tt.vis && nEm == 1 &&
        nt.n == 1 && nt.shown && nt.sem && nt.full && nt.vis && ind && io.fg == _hex(AppColors.textSecondary) && io.ok45;
    okBefore = same && !grow && (v.id == 'B' ? (!allIn && nt.brk >= 1) : allIn);
    okStrict = same && grow == (v.id == 'B') && allIn && nt.brk == 0;
    raw = 'bz $bz f0 $f0 sh ${sr.height} ${sr.top} $grow tt $tt em $em ic $nIc $ir $iv bh $bh need $need nt $nt io $io fh $fh ind $ind fs $fs';
  } catch (e, st) {
    failure = e;
    failureSt = st;
  } finally {
    FlutterError.onError = prevOnError;
  }

  // ③ 성공 · 실패 공통 정리 — 화면을 내리고 남은 timer · 지연 응답이 끝날 시간을 준다.
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
  _out('R600 $tok raw m64=${_enc(raw)} ovf64=${_enc(ovfRaw)} fw64=${_enc(fwRaw)} cleanup64=${_enc(cleanupErr)} fail64=${_enc(failure?.toString() ?? '')}');
  _out('D600 $tok att fw n=$nFw');
  _out('D600 $tok done state=${c.id} mode=$mode captures=$shots overflows=$nOvf exc=${exc != null}');

  final f1 = failure;
  if (f1 != null) {
    _halt ??= '$tok ${f1.toString().split('\n').first}';
    Error.throwWithStackTrace(f1, failureSt ?? StackTrace.current);
  }
  if (_before) {
    chk('before 대상 = 지금 A(시트 높이 화면 × 0.72 + 8 · 제목 전문 · 낱말 경계 · 아래 안내 전문 · 칠 textSecondary ≥ 4.5 · 본문과 따로 스크롤 / '
        'B: 빈 목록 아이콘 · 글이 본문 칸 밖으로 잘림 · 안내 낱말 안 끊김 ≥ 1 / W · N: 빈 목록 본문 칸 안)', okBefore, raw);
  } else {
    chk('strict 대상 = 후보(W · N 시트 높이 그대로 · B 시트가 커짐 · 빈 목록 아이콘 · 글 본문 칸 안 · 아래 안내 전문 · 낱말 안 끊김 0 · '
        '칠 textSecondary ≥ 4.5 · 본문과 따로 스크롤 · 제목 전문 · 낱말 경계)', okStrict, raw);
    chk('strict 미처리 framework 예외 0', nFw == 0, fwRaw);
    chk('strict 넘침 0', nOvf == 0, ovfRaw);
  }
  chk('캡처 수 = 선언', shots == c.shots, 'shots $shots want ${c.shots}');
  final bad = checks.where((x) => !x.$2).toList();
  if (bad.isNotEmpty) _halt ??= '$tok ${bad.first.$1}';
  for (final x in checks) {
    expect(x.$2, isTrue, reason: '$tok ${x.$1} ${x.$3}');
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
    await _loadFonts();
  });
  for (final v in _views) {
    for (final c in _cases) {
      testWidgets('S600CT-${v.id}-${c.id} 공고 등록 불러오기 시트 — 빈 목록 본문 칸 · 안내 의미구 줄바꿈', (t) async {
        final tok = 'S600CT-${v.id}-${c.id}';
        if (_halt != null) fail('$tok 진입 0 — 앞 실패: $_halt');
        await _caseOf(t, v, c, tok);
      }, skip: !_optIn);
    }
  }
}
