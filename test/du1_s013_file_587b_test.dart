// ignore_for_file: depend_on_referenced_packages
// [DU587b · 장부 097 · 103 · 104(business_form_screen.dart 파일 단위) · 판정119 :78 · 판정114 :64 · :101] DU-S013 사업장 등록/수정 폼 —
//   2단계 '사업자등록증 (필수/잠금/선택)' 섹션 제목 · 3단계 '사업장 사진 (최대 5장)' 섹션 제목 · 3단계 비콘 감도 눈금 세 칸(가운데 −70 = 값 칩 기준).
//   before = 지금 A(business_form_screen b5db2309 = DU456 r4 후보) 기록 · strict = 후보(prep/mk_cand.py).
//   하네스 = 블록 재사용(prep/mk_test.py 가 원본 바이트 대조 · 정규화 목록 그대로):
//     DU445 시험(57480d64 · S013 수정 3단계 근태 위치 · DONE) — 가짜 Firebase(storageBucket) · _AdminProvider · _out.
//     DU586b 시험(ec2b868b · 준비 PASS — 그 안의 DU585b · DU578 · DU575 · DU560 r3 블록) — _NoHttp · _enc/_inside/_Seen · _spansOf/_sig ·
//       max 판 _fullShown/_midBreaks/_textObs · _area · _lineCount · 보기 W/B/N · opt-in · _txt/_bringBuilt · _hex · _fills · _semOf/_TO/_textLine ·
//       _lum/_contrast · _bgOf · _RoleObs/_roleOf.
//   새로 쓴 것: 이 머리 · 사업장 대역(DU445 _business 원문 + 승인 여부) · 채널 관찰(_Wire — S013 판) · 사례 3(REG 신규 · LOCK 승인 수정 · OPT 미승인 수정) ·
//     칸 표(_groupsOf) · 읽는 이름(_readName) · 괄호 덩어리(_unitKept) · 주 행동 채움(_navFill) · 단계(_atStep · _goNext · _tapText) · 출력 줄(sub 마다 리터럴).
//   누르는 것 = 단계 이동만(신규 업종 '회사' · 세부 '물류센터' · '다음') · 저장 0 · 입력 0 · 끌기 0 · 업무 writer 0(CF · Firestore 채널 0 단언).
//   기본 skip — TB before/du587bfile-tb/DU_BEFORE_OBSERVE=587 · TA after/du587bfile-ta/없음.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui show BoxHeightStyle;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ALfit/models/core/business_model.dart';
import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/providers/notification_provider.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/screens/business_admin/business_form_screen.dart';
import 'package:ALfit/theme/app_colors.dart';
import 'package:ALfit/theme/role_theme.dart';
import 'package:ALfit/utils/beacon_helper.dart';
import 'package:ALfit/utils/text_layout.dart';

import 'support/du1_vq_capture.dart';

class _FakeApp extends Fake with MockPlatformInterfaceMixin implements FirebaseAppPlatform {
  @override
  String get name => defaultFirebaseAppName;
  // storageBucket 필수 — 폼이 StorageService() 를 필드로 든다(기존 시험 주석).
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

class _AdminProvider extends UserProvider {
  @override
  UserModel? get currentUser => UserModel(
        uid: 'admin1', username: 'admin1', name: '김사장', email: 'admin1@alfit.local', role: UserRole.BUSINESS_ADMIN,
        managedBusinessIds: const ['biz1'],
      );
  @override
  bool get isBusinessAdmin => true;
  @override
  bool get isSubAdmin => false;
}

/// [DU587b] 사업장 — DU445 `_business()`(business_form_responsive_render_test 와 같은 좌표 있는 사업장) 원문 + 승인 여부만 사례로 가른다.
///   LOCK = 승인(2단계 제목 '(잠금)') · OPT = 미승인('(선택)'). 출근 방식 'both'(GPS · 비콘 카드 둘 다 그려짐 — DU445 와 같다) ·
///   비콘 감도 = 모델 기본 −75(값 칩 '보통 (3~8m)' — 눈금 세 글과 겹치지 않는다).
BusinessModel _business({required bool approved}) => BusinessModel(
      id: 'biz1', name: '중앙물류센터 수도권 1센터', ownerId: 'admin1', companyName: '주식회사 중앙물류', ownerName: '김사장',
      businessNumber: '0000000000', address: '경기도 화성시 동탄순환대로 1길 23', detailAddress: '3층 물류동 A구역',
      category: '물류', subCategory: '창고', phone: '031-000-0000', latitude: 37.2, longitude: 127.07, city: '화성시', district: '동탄면',
      isApproved: approved, createdAt: DateTime(2026, 1, 1),
      attendanceType: 'both', beaconUUID: 'E2C56DB5-DFFB-48D2-B060-D0F5A71096E0',
    );

/// [DU587b] 플랫폼 메시지 관찰(S013 폼 판) — CF · Firestore 채널은 이름을 적고 막는다(응답 null · tripped — 업무 읽기/쓰기 0 단언).
///   그 밖(Storage 인스턴스 · Flutter 기반 · 플러그인)은 **원래 경로로 넘기고** 이름만 센다 — 기존 S013 시험(DU445 · DU480 · BF-R)은 채널 대역 없이
///   같은 화면을 그렸다(그 동작 그대로 · 막아서 생기는 다른 실패 0). Storage 는 따로 센다(저장은 누르지 않는다 · 기록만).
class _Wire {
  final cf = <String>[];
  final fs = <String>[];
  final st = <String>[];
  final other = <String, int>{};
  var tripped = false;

  Future<ByteData?>? route(TestDefaultBinaryMessenger m, String channel, MessageHandler? handler, ByteData? message) {
    if (channel.contains('cloud_functions') || channel.contains('firebase_functions')) {
      cf.add(channel);
      tripped = true;
      return null;
    }
    if (channel.contains('firestore')) {
      fs.add(channel);
      tripped = true;
      return null;
    }
    if (channel.contains('firebase_storage')) {
      st.add(channel);
    } else {
      other.update(channel, (x) => x + 1, ifAbsent: () => 1);
    }
    return handler != null ? handler(message) : m.delegate.send(channel, message);
  }
}

/// [F120-3] 외부 HTTP 차단 — 만들려는 시도를 기록하고 실패시킨다(끝에 0 단언).
class _NoHttp extends HttpOverrides {
  _NoHttp(this.wire);
  final _Wire wire;
  final tries = <String>[];

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    tries.add('createHttpClient');
    wire.tripped = true;
    throw const SocketException('DU587b 관측 — 외부 HTTP 차단');
  }
}

void _out(String s) {
  // ignore: avoid_print
  print(s);
}

String _enc(String s) => s.isEmpty ? '-' : base64Url.encode(utf8.encode(s)).replaceAll('=', '');
/// [a] 가 [b] **안**에 있는가(겹침이 아니라 포함 · 0.5px 허용 — DU508 r3 와 같다).
bool _inside(Rect a, Rect b) => a.left >= b.left - 0.5 && a.top >= b.top - 0.5 && a.right <= b.right + 0.5 && a.bottom <= b.bottom + 0.5;

/// 시각 오류 수집 — 넘침은 원문 전체 + 위치 두 줄, 그 밖 framework 오류도 원문 전체(DU516 r1 과 같다).
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
      overflows.add('${m.split('\n').first} @ $loc\n$m');
    } else {
      other.add(m);
    }
  }
}

/// 글 조각별 실제 스타일 — 조상 스타일부터 차례로 merge(Text = 기본 글 스타일과 합친 하나 · Text.rich = 조각마다). 빈 조각은 뺀다.
List<(String, TextStyle)> _spansOf(RenderParagraph rp) {
  final out = <(String, TextStyle)>[];
  void walk(InlineSpan s, TextStyle eff) {
    final e = s.style == null ? eff : eff.merge(s.style);
    if (s is TextSpan) {
      final tx = s.text;
      if (tx != null && tx.isNotEmpty) out.add((tx, e));
      for (final ch in s.children ?? const <InlineSpan>[]) {
        walk(ch, e);
      }
    }
  }
  walk(rp.text, const TextStyle());
  return out;
}

/// 스타일 서명 '크기/줄 높이/굵기/자간/색' — 크기 · 자간 소수 1 · 줄 높이 소수 2 · 굵기 값 · ARGB 8자리(없으면 n).
String _sig(TextStyle s) {
  String n(double? x, int d) => x == null ? 'n' : x.toStringAsFixed(d);
  final c = s.color;
  return [
    n(s.fontSize, 1),
    n(s.height, 2),
    s.fontWeight == null ? 'n' : s.fontWeight!.value.toString(),
    n(s.letterSpacing, 1),
    c == null ? 'n' : c.toARGB32().toRadixString(16).padLeft(8, '0'),
  ].join('/');
}

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
const _cases = <({String id, int shots})>[(id: 'REG', shots: 1), (id: 'LOCK', shots: 3), (id: 'OPT', shots: 1)];

/// [kind] title(섹션 제목 — 괄호 덩어리 u1) · tick(비콘 눈금 — 같은 자리 rssi 의 helper 글과 같은가 hp) ·
/// [want] 보이는 글(TextLayout.plain) · [say] 읽는 이름 원문 · [rssi] 눈금 자리(제목은 0 — hp 를 내지 않는다).
typedef _Tg = ({String sub, String kind, String want, String say, int rssi});
typedef _Grp = ({String shot, String state, int step, List<_Tg> tgs});

/// 가운데 눈금 — base(before) '보통(~5m)' · 후보(strict) '가까움(1~3m)'. 보이는 글은 제품 식 그대로 첫 '(' 앞 공백(label.replaceFirst('(', ' (')) ·
///   읽는 이름 = semanticsLabel(label 원문 · 공백 없음).
const _midOld = '보통 (~5m)';
const _midOldSay = '보통(~5m)';
const _midNew = '가까움 (1~3m)';
const _midNewSay = '가까움(1~3m)';

/// [DU587b] 사례별 칸 묶음 — [step] = 폼 단계 번호(0 업종 · 1 기본 정보 · 2 상세 정보). 묶음 끝에 화면 채움(A8) → 캡처.
List<_Grp> _groupsOf(String id) => switch (id) {
      'REG' => const [
          (shot: '1lic', state: 'step2-license-required', step: 1, tgs: [
            (sub: 'lt', kind: 'title', want: '사업자등록증 (필수)', say: '사업자등록증 (필수)', rssi: 0),
          ]),
        ],
      'LOCK' => const [
          (shot: '1lic', state: 'step2-license-locked', step: 1, tgs: [
            (sub: 'lt', kind: 'title', want: '사업자등록증 (잠금)', say: '사업자등록증 (잠금)', rssi: 0),
          ]),
          (shot: '2photo', state: 'step3-photo-title', step: 2, tgs: [
            (sub: 'pt', kind: 'title', want: '사업장 사진 (최대 5장)', say: '사업장 사진 (최대 5장)', rssi: 0),
          ]),
          (shot: '3beacon', state: 'step3-beacon-ticks', step: 2, tgs: [
            (sub: 't1', kind: 'tick', want: '멀리 (~10m)', say: '멀리(~10m)', rssi: -90),
            (sub: 't2', kind: 'tick', want: '_mid', say: '_midSay', rssi: -70),
            (sub: 't3', kind: 'tick', want: '가까이 (~1m)', say: '가까이(~1m)', rssi: -50),
          ]),
        ],
      _ => const [
          (shot: '1lic', state: 'step2-license-optional', step: 1, tgs: [
            (sub: 'lt', kind: 'title', want: '사업자등록증 (선택)', say: '사업자등록증 (선택)', rssi: 0),
          ]),
        ],
    };

/// 이 모드의 보이는 글 · 읽는 이름(가운데 눈금만 모드마다 다르다).
String _wantOf(_Tg x) => x.want == '_mid' ? (_before ? _midOld : _midNew) : x.want;
String _sayOf(_Tg x) => x.say == '_midSay' ? (_before ? _midOldSay : _midNewSay) : x.say;

final bool _before = Platform.environment['DU_BEFORE_OBSERVE'] == '587';
final Map<String, String> _env = Platform.environment;
final bool _optIn =
    (_env['DU1_VQ_PHASE'] == 'before' && _env['DU1_VQ_RUN'] == 'du587bfile-tb' && _env['DU_BEFORE_OBSERVE'] == '587') ||
        (_env['DU1_VQ_PHASE'] == 'after' && _env['DU1_VQ_RUN'] == 'du587bfile-ta' && _env['DU_BEFORE_OBSERVE'] == null);
/// 첫 실패 뒤 사례는 본문에 들어가지 않는다(진입 0 · 캡처 0).
String? _halt;
final String _manifest = Platform.environment['DUL_MANIFEST'] ?? '(unset)';
const _envKeys = ['DU_BEFORE_OBSERVE', 'DU1_VQ_PHASE', 'DU1_VQ_OUT', 'DU1_VQ_RUN', 'DU1_VQ_DATE', 'DU397_DIAG', 'DU397_MANIFEST', 'DU400_MANIFEST',
  'DU401_MANIFEST', 'DU398_MANIFEST', 'DU406_MANIFEST', 'DU407_MANIFEST', 'DU296_PHASE', 'DUL_MANIFEST'];
final String _envLine = [for (final k in _envKeys) '$k:${Platform.environment[k] ?? '(unset)'}'].join(',');

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
  });

  for (final v in _views) {
    for (final c in _cases) {
      testWidgets('S587BF-${v.id}-${c.id} 사업장 폼 섹션 제목 조판 · 비콘 눈금 기준(장부 097 · 103 · 104) — 전문 · 음절 끊김 · 괄호 덩어리 · 읽는 이름 · 눈금 = helper · 넘침', (t) async {
        final tok = 'S587BF-${v.id}-${c.id}';
        if (_halt != null) fail('$tok 진입 0 — 앞 실패: $_halt');

        // guard 를 이 사례의 어떤 초기화보다 먼저 건다(글꼴 · provider · 폼 생성 전 · DU586b 순서). 이전 값은 모두 잡아 둔다.
        final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        final wire = _Wire();
        final net = _NoHttp(wire);
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
        await t.runAsync(vqLoadFonts);
        t.view.physicalSize = Size(v.w, v.h);
        t.view.devicePixelRatio = 1.0;
        addTearDown(t.view.reset);
        final screen = Offset.zero & Size(v.w, v.h);
        final mode = _before ? 'before' : 'strict';
        _out('D587 $tok begin mode=$mode phase=${Platform.environment['DU1_VQ_PHASE'] ?? '(unset)'} env=$_envLine manifest=$_manifest');
        final seen = _Seen();
        void need(String k, bool ok, [String why = '']) => expect(ok, isTrue, reason: '$tok $k $why');
        final checks = <(String, bool, String)>[];
        void chk(String k, bool ok, [String why = '']) => checks.add((k, ok, why));
        Future<void> settle([int n = 12]) async {
          for (var i = 0; i < n; i++) {
            await t.pump(const Duration(milliseconds: 100));
          }
        }

        Object? failure;
        StackTrace? failureSt;
        var shots = 0;
        var raw = '';
        try {
          FlutterError.onError = seen.add;
          final key = GlobalKey();
          await t.pumpWidget(RepaintBoundary(
            key: key,
            child: MultiProvider(
              providers: [
                ChangeNotifierProvider<UserProvider>(create: (_) => _AdminProvider()),
                ChangeNotifierProvider<NotificationProvider>(create: (_) => NotificationProvider()),
              ],
              child: MaterialApp(
                debugShowCheckedModeBanner: false,
                theme: RoleTheme.businessAdminTheme,
                builder: (ctx, child) => MediaQuery(data: MediaQuery.of(ctx).copyWith(textScaler: TextScaler.linear(v.s)), child: child!),
                home: c.id == 'REG' ? const BusinessFormScreen() : BusinessFormScreen(business: _business(approved: c.id == 'LOCK')),
              ),
            ),
          ));
          await settle();
          final form = find.byType(BusinessFormScreen);
          final nForm = form.evaluate().length;
          need('폼 1', nForm == 1, 'n $nForm');

          Future<void> shot(String id, String state) async {
            _out('D587 $tok shot $id ovf=${seen.overflows.length}');
            await vqCapture(t, key, '${tok}_$id', conditions: {
              'viewport': '${v.w.toInt()}x${v.h.toInt()}', 'textScaler': v.s, 'run': vqRun, 'manifest': _manifest, 'mode': mode,
              'fixture': c.id, 'state': state,
            });
            shots++;
          }

          // ① 신규 등록은 1단계에서 업종 · 세부 업종을 고른다(_validateStep1 · DU480 경로 — 펼침 '회사' → '물류센터').
          if (c.id == 'REG') {
            for (final s in const ['회사', '물류센터']) {
              final n = await _tapText(t, s);
              need('1단계 글 $s 하나 · 누름', n == 1, 'n $n');
              await settle();
            }
          }
          // ② 칸 묶음마다 — 그 단계로 '다음' 을 실제로 눌러 가고(_goNext · 저장 0) · 대상 글이 안 지어졌으면 짓고(_bringBuilt · 점검표 A4) ·
          //   같은 Text 를 ensureVisible 로 넣고 잰다(_textLine · A1) · 그 Text 의 실제 글자색 · 바탕 · 대비(_roleOf) · 읽는 이름(_readName) ·
          //   괄호 덩어리 한 줄(_unitKept) · 눈금 = 같은 자리 rssi 의 helper 글(hp). 묶음 끝에 화면 채움(A8 — _fills · _navFill) → 캡처.
          final rawRows = <String>[];
          final groups = _groupsOf(c.id);
          var step = 0;
          for (var gi = 0; gi < groups.length; gi++) {
            final g = groups[gi];
            while (step < g.step) {
              final moved = await _goNext(t);
              need('단계 ${step + 1} → ${step + 2} 다음 누름', moved, 'step $step');
              await settle();
              step++;
            }
            final at = _atStep(form, step);
            need('단계 도달 $step', at, g.state);
            for (final x in g.tgs) {
              final want = _wantOf(x);
              await _bringBuilt(t, form, want);
              final tf = _txt(form, want, onstage: false);
              final o = await _textLine(t, tf, want, screen);
              final r = o.n == 1 ? _roleOf(tf, '-') : _roleNone;
              final rn = o.n == 1 && _readName(t, tf) == _sayOf(x);
              final u1 = o.n == 1 &&
                  x.kind == 'title' &&
                  _unitKept(t.renderObject<RenderParagraph>(find.descendant(of: tf, matching: find.byType(RichText), skipOffstage: true).first));
              final hp = want == BeaconHelper.proximityLabel(x.rssi);
              if (x.kind == 'title') {
                _ttOut(tok, x.sub, o, r, rn, u1);
              } else {
                _tkOut(tok, x.sub, o, r, rn, hp);
              }
              rawRows.add('${x.sub} "$want" n${o.n} ${r.sig} ${r.fg}/${r.bg} ${r.cr} rn $rn u1 $u1 hp $hp');
              chk('대상 글 하나 ${x.sub}', o.n == 1 && o.shown, want);
              if (!_before) {
                chk('strict ${x.sub} 전문 · 음절 끊김 0 · 말줄임 0 · 보임', o.full && o.brk == 0 && o.ell0 && o.vis,
                    '$want full ${o.full} brk ${o.brk} ell0 ${o.ell0} vis ${o.vis}');
                chk('strict ${x.sub} 읽는 이름 = 원문', rn, '$want say ${_sayOf(x)}');
                chk('strict ${x.sub} 대비 4.5 이상', r.ok45, '$want ${r.fg} on ${r.bg} ${r.cr}');
                if (x.kind == 'title') chk('strict ${x.sub} 괄호 덩어리 한 줄', u1, want);
                if (x.sub == 't2') chk('strict t2 가운데 눈금 = 값 칩 같은 자리 기준(BeaconHelper.proximityLabel)', hp, '$want rssi ${x.rssi}');
              }
            }
            final fl = _fills(t);
            _fillsOut(tok, gi + 1, fl);
            final pb = _navFill(form, step);
            _pbOut(tok, gi + 1, pb);
            await shot(g.shot, g.state);
          }
          raw = 'rows ${rawRows.join(' | ')}';
        } catch (e, st) {
          failure = e;
          failureSt = st;
        } finally {
          FlutterError.onError = prevOnError;
        }

        // ③ 성공 · 실패 공통 정리 — 폼을 내리고 남은 timer · 지연 응답이 끝날 시간을 준다. guard 는 아직 걸려 있다.
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

        // ④ 최종 안전 집계 — 해제 · 대기 뒤 guard 아래에서 센다(값 측정과 분리).
        final nCf = wire.cf.length;
        final nFs = wire.fs.length;
        final nSt = wire.st.length;
        final nHttp = net.tries.length;
        final nOther = wire.other.values.fold<int>(0, (a, b) => a + b);
        final tripped = wire.tripped;
        final chText = [...wire.cf, ...wire.fs, ...wire.st, for (final e in wire.other.entries) '${e.key} x${e.value}'].join(' | ');
        _out('D587 $tok att wire cf=$nCf fs=$nFs st=$nSt http=$nHttp other=$nOther');

        messenger.allMessagesHandler = prevAll;
        HttpOverrides.global = prevHttp;
        final exc = t.takeException();
        if (exc != null && failure == null) {
          failure = exc;
          failureSt = StackTrace.current;
        }
        final nOvf = seen.overflows.length;
        final nFw = seen.other.length;
        final ovfRaw = seen.overflows.take(8).join('\n----\n');
        final fwRaw = seen.other.take(4).map((m) => m.length > 400 ? m.substring(0, 400) : m).join('\n----\n');
        _out('R587 $tok raw m64=${_enc(raw)} ovf64=${_enc(ovfRaw)} fw64=${_enc(fwRaw)} ch64=${_enc(chText)} cleanup64=${_enc(cleanupErr)} '
            'fail64=${_enc(failure?.toString() ?? '')}');
        _out('D587 $tok att fw n=$nFw');
        _out('D587 $tok done state=${c.id} mode=$mode captures=$shots overflows=$nOvf exc=${exc != null}');

        final f0 = failure;
        if (f0 != null) {
          _halt ??= '$tok ${f0.toString().split('\n').first}';
          Error.throwWithStackTrace(f0, failureSt ?? StackTrace.current);
        }
        // 넘침: strict 0(큰 글자에서 줄 증가는 허용 · 넘침 · 숨김은 허용하지 않는다) · before 는 기록(앞 S013 셀 실측 0 — README §5).
        if (!_before) chk('화면 전체 넘침 0(strict)', nOvf == 0, ovfRaw);
        chk('미처리 framework 예외 0', nFw == 0, fwRaw);
        chk('캡처 수 = 선언', shots == c.shots, 'shots $shots want ${c.shots}');
        chk('시험 전체 CF 0 · Firestore 0 · HTTP 0(해제 · 대기 뒤 · 업무 writer 불실행)', nCf == 0 && nFs == 0 && nHttp == 0 && !tripped,
            'cf $nCf fs $nFs http $nHttp tripped $tripped [$chText]');
        final bad = checks.where((x) => !x.$2).toList();
        if (bad.isNotEmpty) _halt ??= '$tok ${bad.first.$1}';
        for (final x in checks) {
          expect(x.$2, isTrue, reason: '$tok ${x.$1} ${x.$3}');
        }
      }, skip: !_optIn);
    }
  }
}

// 측정 도우미(DU586b 와 같이 main 뒤).

/// 그려진 글(묶음 문자를 뺀 것) · 위젯 글이 [want] 인 Text(Text.rich 포함) — DU523 의 찾기 술어와 같다.
///   [onstage] true = 화면에 그려지는 것만(머리 — O003 은 좁은 창 판정용 머리 사본을 Offstage 로 한 번 더 짓는다 · work_applicants_dialog:2038).
///   false = 지어진 것 전부(본문 — O002 본문은 지연 생성 목록 CustomScrollView/SliverList · ListView.separated · day_applicants_dialog:1457/:1476 —
///   B 에서 머리가 커지면 첫 묶음이 칸 밖(캐시 안)에 지어져 onstage 개수 0 이 될 수 있다 · DU573/DU581 TB STOP 교훈).
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

String _hex(Color c) => '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

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

/// 읽는 이름 — Text.semanticsLabel(있으면) · 없으면 span 의 읽는 이름을 포함한 평문 · 그다음 data.
String _semOf(Text w) => w.semanticsLabel ?? w.textSpan?.toPlainText() ?? w.data ?? '';

typedef _TO = ({int n, bool shown, bool sem, bool full, bool ell0, int brk, int lines, bool vis});

/// 글 하나 — [tf] 를 ensureVisible 로 화면 안에 넣고 **같은 [tf]** 를 잰다(점검표 A1 · 판정169a §5).
///   shown · full · ell0 · brk = DU560 r3 _textObs(max 판 _fullShown 그대로) · lines = _lineCount · vis = 화면 ∩ 조상 스크롤 칸 안 · n ≠ 1 이면 재지 않는다.
Future<_TO> _textLine(WidgetTester t, Finder tf, String want, Rect screen) async {
  final n = tf.evaluate().length;
  _TextObs o = (shown: false, name: false, full: false, ell0: false, brk: 0, size: Size.zero);
  var sem = false;
  var lines = 0;
  var vis = false;
  if (n == 1) {
    await t.ensureVisible(tf);
    for (var m = 0; m < 4; m++) {
      await t.pump(const Duration(milliseconds: 50));
    }
    o = _textObs(t, tf, want);
    sem = _semOf(t.widget<Text>(tf)) == want;
    lines = _lineCount(t.renderObject<RenderParagraph>(find.descendant(of: tf, matching: find.byType(RichText), skipOffstage: true).first));
    vis = _inside(t.getRect(tf), _area(tf, screen));
  }
  return (n: n, shown: o.shown, sem: sem, full: o.full, ell0: o.ell0, brk: o.brk, lines: lines, vis: vis);
}

double _lum(Color c) {
  double ch(double v) => v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * ch(c.r) + 0.7152 * ch(c.g) + 0.0722 * ch(c.b);
}

double _contrast(Color a, Color b) {
  final x = _lum(a);
  final y = _lum(b);
  return (math.max(x, y) + 0.05) / (math.min(x, y) + 0.05);
}

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

/// [DU578] 잰 글의 역할 — 그 Text 안 RichText 하나의 실제 글 조각 스타일 서명(DU555 _spansOf · _sig · 여러 조각이면 정렬 '|') ·
///   그린 글자색 · 글 뒤 실제 바탕(_bgOf) · 대비 · 결정값과 같은가. [tf] = _textLine 이 ensureVisible 로 넣고 잰 **같은 Text**(점검표 A1).
typedef _RoleObs = ({String sig, String fg, String bg, String cr, bool ok45, bool role});

const _RoleObs _roleNone = (sig: '-', fg: '-', bg: '-', cr: '0.00', ok45: false, role: false);

_RoleObs _roleOf(Finder tf, String want) {
  final rs = find.descendant(of: tf, matching: find.byType(RichText), skipOffstage: false).evaluate().toList();
  if (rs.length != 1) return _roleNone;
  final rp = rs.first.renderObject;
  if (rp is! RenderParagraph) return _roleNone;
  final sigs = <String>{};
  for (final (_, st) in _spansOf(rp)) {
    sigs.add(_sig(st));
  }
  final sig = sigs.isEmpty ? '-' : (sigs.toList()..sort()).join('|');
  final Color? fg = (rs.first.widget as RichText).text.style?.color;
  final bg = _bgOf(rs.first);
  final cr = fg == null ? 0.0 : _contrast(fg, bg);
  return (sig: sig, fg: fg == null ? '-' : _hex(fg), bg: _hex(bg), cr: cr.toStringAsFixed(2), ok45: cr >= 4.5, role: sig == want);
}

/// [DU587b] 읽는 이름 — 가장 가까운 읽기 덮개(Semantics excludeSemantics: true)가 있으면 그 label · 없으면 그 Text 의 읽는 이름(_semOf).
///   후보는 두 제목을 Semantics(label: 원문, excludeSemantics: true) 로 감싼다(Text 는 낱말 묶음 표시 문자를 품는다) — 화면 읽기가 듣는 이름을 잰다.
String _readName(WidgetTester t, Finder tf) {
  String? cover;
  tf.evaluate().first.visitAncestorElements((a) {
    final w = a.widget;
    if (w is Semantics && w.excludeSemantics) {
      cover = w.properties.label ?? '';
      return false;
    }
    return true;
  });
  return cover ?? _semOf(t.widget<Text>(tf));
}

/// [DU587b] 괄호 덩어리('(최대 5장)' · '(잠금)')가 한 줄에 그려졌는가 — 여는 괄호부터 닫는 괄호까지 글자 자리(box) top 이 같다
///   (반 글자 높이 허용 · WORD JOINER 건너뜀). 괄호가 없으면 false.
bool _unitKept(RenderParagraph rp) {
  final s = rp.text.toPlainText(includeSemanticsLabels: false);
  final i0 = s.indexOf('(');
  final i1 = i0 < 0 ? -1 : s.indexOf(')', i0);
  if (i1 < 0) return false;
  double? top;
  for (var k = i0; k <= i1; k++) {
    if (s[k] == _wj) continue;
    final bx = rp.getBoxesForSelection(TextSelection(baseOffset: k, extentOffset: k + 1));
    if (bx.isEmpty) continue;
    final b = bx.first;
    final t0 = top ??= b.top;
    if ((b.top - t0).abs() > (b.bottom - b.top) / 2) return false;
  }
  return top != null;
}

/// [DU587b · 점검표 A8] 단계 아래 주 행동('다음' · 마지막 단계 '저장하기' — CommonWidgets.primaryButton = Container 채움 + InkWell · ButtonStyleButton 아님 →
///   _fills 에 안 든다)의 채움 — 그 글 뒤 실제 바탕(_bgOf = 단추 Container 의 BoxDecoration 색). 누르기 0 · 기록만.
typedef _NavObs = ({int n, String fill, bool brand});

_NavObs _navFill(Finder form, int step) {
  final es = _txt(form, step == 2 ? '저장하기' : '다음', onstage: false).evaluate().toList();
  if (es.length != 1) return (n: es.length, fill: '-', brand: false);
  final c = _bgOf(es.first);
  return (n: es.length, fill: _hex(c), brand: c.toARGB32() == AppColors.brand.toARGB32());
}

/// [DU587b] 지금 단계 — 1(기본 정보) = '이전' · '다음' 둘 다 있다 · 2(상세 정보 · 마지막) = '저장하기' 가 있다(_buildNavigationButtons).
bool _atStep(Finder form, int step) => switch (step) {
      1 => _txt(form, '이전', onstage: false).evaluate().isNotEmpty && _txt(form, '다음', onstage: false).evaluate().isNotEmpty,
      2 => _txt(form, '저장하기', onstage: false).evaluate().isNotEmpty,
      _ => false,
    };

/// [DU587b · DU445/BF-R goNext 와 같은 동작] '다음' 을 화면에 넣고 실제로 누른다(단계 이동 · 저장 아님). 못 찾으면 false.
Future<bool> _goNext(WidgetTester t) async {
  final next = find.text('다음');
  if (next.evaluate().isEmpty) return false;
  await t.ensureVisible(next.first);
  await t.pump();
  await t.tap(next.first, warnIfMissed: false);
  return true;
}

/// [DU587b · DU480 tapText 와 같은 동작] 신규 1단계 업종 글 [s] 를 화면에 넣고 누른다 — 찾은 개수를 돌려준다(1 이 아니면 누르지 않는다).
Future<int> _tapText(WidgetTester t, String s) async {
  final f = find.text(s);
  final n = f.evaluate().length;
  if (n != 1) return n;
  await t.ensureVisible(f);
  await t.pump();
  await t.tap(f, warnIfMissed: false);
  return n;
}

/// [DU587b] 섹션 제목 출력 한 줄 — sub 마다 리터럴 줄(preflight 2-5 가 'att <sub>' 키를 정적 대조 · lgate 가 같은 줄을 판정). 키 순서 = prep/lines_du587b.py TITLE_KEYS.
void _ttOut(String tok, String sub, _TO o, _RoleObs r, bool rn, bool u1) {
  switch (sub) {
    case 'lt':
      _out('D587 $tok att lt n=${o.n} shown=${o.shown} sem=${o.sem} full=${o.full} ell0=${o.ell0} brk=${o.brk} lines=${o.lines} vis=${o.vis} sig=${r.sig} fg=${r.fg} bg=${r.bg} cr=${r.cr} ok45=${r.ok45} rn=$rn u1=$u1');
    case 'pt':
      _out('D587 $tok att pt n=${o.n} shown=${o.shown} sem=${o.sem} full=${o.full} ell0=${o.ell0} brk=${o.brk} lines=${o.lines} vis=${o.vis} sig=${r.sig} fg=${r.fg} bg=${r.bg} cr=${r.cr} ok45=${r.ok45} rn=$rn u1=$u1');
    default:
      throw StateError('DU587b 제목 sub 선언 밖 $sub');
  }
}

/// [DU587b] 비콘 눈금 출력 한 줄 — 키 순서 = TICK_KEYS.
void _tkOut(String tok, String sub, _TO o, _RoleObs r, bool rn, bool hp) {
  switch (sub) {
    case 't1':
      _out('D587 $tok att t1 n=${o.n} shown=${o.shown} sem=${o.sem} full=${o.full} ell0=${o.ell0} brk=${o.brk} lines=${o.lines} vis=${o.vis} sig=${r.sig} fg=${r.fg} bg=${r.bg} cr=${r.cr} ok45=${r.ok45} rn=$rn hp=$hp');
    case 't2':
      _out('D587 $tok att t2 n=${o.n} shown=${o.shown} sem=${o.sem} full=${o.full} ell0=${o.ell0} brk=${o.brk} lines=${o.lines} vis=${o.vis} sig=${r.sig} fg=${r.fg} bg=${r.bg} cr=${r.cr} ok45=${r.ok45} rn=$rn hp=$hp');
    case 't3':
      _out('D587 $tok att t3 n=${o.n} shown=${o.shown} sem=${o.sem} full=${o.full} ell0=${o.ell0} brk=${o.brk} lines=${o.lines} vis=${o.vis} sig=${r.sig} fg=${r.fg} bg=${r.bg} cr=${r.cr} ok45=${r.ok45} rn=$rn hp=$hp');
    default:
      throw StateError('DU587b 눈금 sub 선언 밖 $sub');
  }
}

/// [DU587b · 점검표 A8] 캡처 직전 화면 채움 단추 기록 한 줄 — 묶음 번호마다 리터럴 줄(키 순서 = FILL_KEYS).
void _fillsOut(String tok, int i, _FillObs fl) {
  switch (i) {
    case 1:
      _out('D587 $tok att fills1 n=${fl.n} brand=${fl.brand} err=${fl.err} none=${fl.none} other=${fl.other} list=${fl.list}');
    case 2:
      _out('D587 $tok att fills2 n=${fl.n} brand=${fl.brand} err=${fl.err} none=${fl.none} other=${fl.other} list=${fl.list}');
    case 3:
      _out('D587 $tok att fills3 n=${fl.n} brand=${fl.brand} err=${fl.err} none=${fl.none} other=${fl.other} list=${fl.list}');
    default:
      throw StateError('DU587b 채움 기록 번호 선언 밖 $i');
  }
}

/// [DU587b · 점검표 A8] 단계 아래 주 행동 채움 기록 한 줄 — 묶음 번호마다 리터럴 줄(키 순서 = NAV_KEYS).
void _pbOut(String tok, int i, _NavObs p) {
  switch (i) {
    case 1:
      _out('D587 $tok att pb1 n=${p.n} fill=${p.fill} brand=${p.brand}');
    case 2:
      _out('D587 $tok att pb2 n=${p.n} fill=${p.fill} brand=${p.brand}');
    case 3:
      _out('D587 $tok att pb3 n=${p.n} fill=${p.fill} brand=${p.brand}');
    default:
      throw StateError('DU587b 주 행동 기록 번호 선언 밖 $i');
  }
}
