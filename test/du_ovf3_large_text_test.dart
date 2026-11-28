// [OVF3 · 판정273/274 잔여] OCR/신분증 창 넘침(F275-OVF-OCR · F275-OVF-IDCARD) + F273-RRCF-WRAP 낱말 줄바꿈 회귀 — 6 조건 · strict runner · 캡처 0. (r3: F274-CCDP-WRAP 은 시험 환경에서 재현 안 돼 제외 · OPEN)
//   하니스 = v1g/ovf1/test_cand_r4(1dad34bc0c8e1688) 의 줄 그대로 + 보기 크기 인자화(W 390×844). 대역 = 제품 기존 훅(RegistrationRecoveryReads) · 열기만(쓰기 단추 누르기 0) · 새 제품 코드 0.
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'package:ALfit/screens/auth/registration_recovery_reads.dart';
import 'package:ALfit/screens/auth/registration_recovery_screen.dart';
import 'package:ALfit/services/firestore_service.dart';
import 'package:ALfit/theme/role_theme.dart';
import 'package:ALfit/utils/id_card_helper.dart';
import 'package:ALfit/widgets/dialogs/ocr_verification_dialog.dart';
import 'support/visible_text.dart'; // [impl_21] TextLayout 문구는 보이는 글자로 찾는다

// ── 글꼴(상대 경로) ──
Future<void> _loadFonts() async {
  Future<ByteData> b(String p) => File(p).readAsBytes().then((x) => ByteData.view(x.buffer));
  for (final fam in const ['NotoSansKR', 'Roboto', 'FlutterTest']) {
    await (FontLoader(fam)
          ..addFont(b('assets/fonts/NotoSansKR-Regular.ttf'))
          ..addFont(b('assets/fonts/NotoSansKR-Bold.ttf')))
        .load();
  }
}

// ── Firebase 코어 대역(pilot_invite_fence_sheet_message_test.dart 와 같은 꼴) ──
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

// ── 안전 대역 ──
class _NoHttp extends HttpOverrides {
  final tries = <String>[];
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    tries.add('createHttpClient');
    throw StateError('OVF1 시험은 HTTP 0');
  }
}

/// 근무 가능 인력 0 명 대역 — 후보 조회 호출 수를 센다 · 초대 호출 = 즉시 실패(쓰기 0).
// [ovf3] _ZeroWorkers · fixture(ovf1 전용)는 옮기지 않음

// ── strict runner ──
// [ovf3] 보기 크기 인자화(r3: W 사례 제외 — B/N 만 · r4 와 같은 320×640).
typedef _View = ({String id, double scale, double w, double h});
const _vB = (id: 'B', scale: 2.0, w: 320.0, h: 640.0);
const _vN = (id: 'N', scale: 1.0, w: 320.0, h: 640.0);
var _screen = const Size(320, 640); // [ovf3] _strict 가 보기마다 바꿈

class _Ctx {
  _Ctx(this.t);
  final WidgetTester t;
  BuildContext? host;
  final errors = <FlutterErrorDetails>[];
  final unexpected = <String>[];
  late _NoHttp net;

  Rect get screen => Offset.zero & _screen;

  Future<void> frames([int n = 10]) async {
    for (var i = 0; i < n; i++) {
      await t.pump(const Duration(milliseconds: 50));
    }
  }

  /// 대상 1 · 사각형 전부 화면 안 · 중심 hit 가 대상(또는 그 자손)에 닿음. 감싼 Scrollable 이 있으면 먼저 그쪽으로 끌어온다(구현 형식 단언 0).
  Future<void> visible(Finder f, String what, {bool hit = true}) async {
    expect(f, findsOneWidget, reason: '$what 1 개');
    final sc = find.ancestor(of: f, matching: find.byType(Scrollable));
    if (sc.evaluate().isNotEmpty) {
      await t.scrollUntilVisible(f, 80, scrollable: sc.first, maxScrolls: 60);
      await frames(4);
    }
    final rc = t.getRect(f);
    final inside = rc.left >= -0.5 && rc.top >= -0.5 && rc.right <= _screen.width + 0.5 && rc.bottom <= _screen.height + 0.5;
    expect(inside, isTrue, reason: '$what 화면 안 보임 · rect $rc');
    if (hit) expect(f.hitTestable(), findsOneWidget, reason: '$what 중심 hit(가림 0) · rect $rc');
  }

  Future<void> tap(Finder f, String what) async {
    await visible(f, what);
    await t.tap(f);
    await frames(10);
  }
}

Future<void> _strict(WidgetTester t, _View v, Future<void> Function(_Ctx c) body) async {
  final c = _Ctx(t);
  final m = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final prevAll = m.allMessagesHandler;
  final prevHttp = HttpOverrides.current;
  final prevOnError = FlutterError.onError;
  c.net = _NoHttp();
  m.allMessagesHandler = (channel, handler, message) {
    if (channel.startsWith('flutter/')) return handler == null ? null : handler(message);
    c.unexpected.add(channel);
    return null;
  };
  HttpOverrides.global = c.net;
  _screen = Size(v.w, v.h); // [ovf3]
  t.view.physicalSize = _screen;
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  try {
    FlutterError.onError = c.errors.add;
    await t.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: RoleTheme.businessAdminTheme,
      locale: const Locale('ko', 'KR'),
      supportedLocales: const [Locale('ko', 'KR'), Locale('en', 'US')],
      localizationsDelegates: const [GlobalMaterialLocalizations.delegate, GlobalWidgetsLocalizations.delegate, GlobalCupertinoLocalizations.delegate],
      builder: (ctx, child) => MediaQuery(data: MediaQuery.of(ctx).copyWith(textScaler: TextScaler.linear(v.scale)), child: child!),
      home: Scaffold(body: Builder(builder: (bc) {
        c.host = bc;
        return const SizedBox.expand();
      })),
    ));
    await body(c);
    await t.pumpWidget(const SizedBox.shrink());
    await c.frames(10);
  } finally {
    FlutterError.onError = prevOnError;
    m.allMessagesHandler = prevAll;
    HttpOverrides.global = prevHttp;
  }
  // [r3] 위젯 해제 뒤 FlutterErrorDetails.toString() 은 조상 탐색으로 assert — 예외 문자열만 사용
  final ovf = c.errors.where((e) => e.exceptionAsString().contains('overflowed')).toList();
  // [r4] matcher 의 불일치 설명도 FlutterErrorDetails.toString() 을 부름 → 문자열 목록으로 단언
  final ovfText = ovf.map((e) => e.exceptionAsString().split('\n').first).toList();
  final errText = c.errors.map((e) => e.exceptionAsString().split('\n').first).toList();
  expect(ovfText, isEmpty, reason: 'RenderFlex 넘침 0');
  expect(errText, isEmpty, reason: 'FlutterError 0');
  expect(c.unexpected, isEmpty, reason: '플랫폼 채널(CF·Firestore·Auth 포함) 0 — ${c.unexpected.join(' | ')}');
  expect(c.net.tries, isEmpty, reason: 'HTTP 0');
  expect(t.takeException(), isNull);
}

// ── fixture(갤러리 suite r4 와 같은 값) ──
const _ocrInfo = '예금주: 홍길동\n계좌번호: 1234567890\n은행: 국민은행';
const _ocrErr = '이미지를 읽지 못했어요';
const _idrOne = [
  {'uid': 'w1', 'name': '김근로'},
];
const _idrThree = [
  {'uid': 'w1', 'name': '김근로'},
  {'uid': 'w2', 'name': '이근로'},
  {'uid': 'w3', 'name': '박근로'},
];

/// TextLayout 의 낱말 결합자(U+2060)·끊음 자리(U+200B)·NBSP 를 정리한 글이 [s] 와 같은 Text(ovf2 와 같은 꼴 + NBSP).
Finder _plain(String s) => find.byWidgetPredicate(
    (w) => w is Text && (w.data ?? '').replaceAll('⁠', '').replaceAll('​', '').replaceAll(' ', ' ') == s,
    description: 'plain "$s"');

/// 실제 줄 조각 — RenderParagraph 의 줄 경계(du1_c1_create_date_range_test lineSegs 와 같은 방법) · 표시 제어 문자 정리.
List<String> _lines(WidgetTester t, Finder f) {
  // [r2] Text 위젯의 바깥 렌더는 RenderSemanticsAnnotations 일 수 있다 → 안쪽 RichText 의 RenderParagraph 를 찾는다
  final rp = t.renderObject<RenderParagraph>(find.descendant(of: f, matching: find.byType(RichText), matchRoot: true).first);
  final plain = rp.text.toPlainText(includeSemanticsLabels: false);
  final tp = TextPainter(text: rp.text, textDirection: TextDirection.ltr, textScaler: rp.textScaler)..layout(maxWidth: rp.size.width);
  final out = <String>[];
  var s0 = 0;
  for (final lm in tp.computeLineMetrics()) {
    final e = tp.getLineBoundary(tp.getPositionForOffset(Offset(tp.width, lm.baseline - lm.ascent + lm.height / 2))).end;
    out.add(plain.substring(s0, e).replaceAll('⁠', '').replaceAll('​', '').replaceAll(' ', ' '));
    s0 = e;
  }
  tp.dispose();
  return out;
}

// ── 장면 ──
/// B-OCRS — 통장사본 OCR 일치 창 · '등록하기' 보임·hit → 탭 → true · 닫힘.
Future<void> _ocrs(_Ctx c) async {
  Object? result = 'unset';
  OcrVerificationDialog.showSuccess(context: c.host!, documentType: '통장사본', extractedInfo: _ocrInfo, confidence: 0.92).then((v) => result = v);
  await c.frames(12);
  final dlg = find.byType(AlertDialog);
  expect(dlg, findsOneWidget, reason: 'OCR 일치 창 열림');
  await c.tap(find.descendant(of: dlg, matching: find.text('등록하기')), '등록하기');
  expect(dlg, findsNothing, reason: '등록하기 → 창 닫힘');
  expect(result, true, reason: '결과 true');
}

/// B/N-OCRE — 신분증 인식 실패 창(allowContinue) · 단추 3 보임·hit → '취소' 탭 → false · 닫힘.
Future<void> _ocre(_Ctx c) async {
  Object? result = 'unset';
  OcrVerificationDialog.showError(context: c.host!, documentType: '신분증', errorMessage: _ocrErr, allowContinue: true).then((v) => result = v);
  await c.frames(12);
  final dlg = find.byType(AlertDialog);
  expect(dlg, findsOneWidget, reason: '인식 실패 창 열림');
  await c.visible(find.descendant(of: dlg, matching: find.text('인식 실패')), '제목', hit: false);
  for (final b in const ['그대로 등록', '다시 시도', '취소']) {
    await c.visible(find.descendant(of: dlg, matching: find.text(b)), '단추 $b');
  }
  await c.tap(find.descendant(of: dlg, matching: findVisibleText('취소')), '취소');
  expect(dlg, findsNothing, reason: '취소 → 창 닫힘');
  expect(result, false, reason: '결과 false');
}

/// B-IDRA/IDRM — 신분증 열람 요청 창(1 · 3 명) · 사유 3 보임·hit → '소득세 신고' 선택 → '요청 보내기' 보임·hit(누르기 0 — 쓰기) → '취소' → 닫힘.
Future<void> _idr(_Ctx c, String arg) async {
  var done = false;
  IdCardHelper.showBatchRequestDialog(
      context: c.host!,
      firestoreService: FirestoreService(),
      requester: const {'uid': 'owner-700', 'name': 'QA 사장'},
      business: const {'id': 'biz-700', 'name': '강남 물류센터'},
      targets: arg == '1' ? _idrOne : _idrThree).then((_) => done = true);
  await c.frames(12);
  final dlg = find.byType(Dialog);
  expect(dlg, findsOneWidget, reason: '열람 요청 창 열림');
  for (final s in const ['소득세 신고', '근로계약서 작성', '4대보험 신고']) {
    await c.visible(find.descendant(of: dlg, matching: find.text(s)), '사유 $s');
  }
  await c.tap(find.descendant(of: dlg, matching: find.text('소득세 신고')), '소득세 신고 선택');
  await c.visible(find.descendant(of: dlg, matching: find.text('요청 보내기')), "'요청 보내기'");
  await c.tap(find.descendant(of: dlg, matching: findVisibleText('취소')), '취소');
  expect(dlg, findsNothing, reason: '취소 → 창 닫힘');
  expect(done, isTrue);
}

/// B-RRCF — 가입 복구 외국인 단계 단추 글이 낱말 단위로만 줄바꿈(음절 중간 0) · 보임·hit(누르기 0).
Future<void> _rrcfWrap(_Ctx c) async {
  Navigator.of(c.host!).push(MaterialPageRoute<void>(
      builder: (_) => RegistrationRecoveryScreen(
          reads: RegistrationRecoveryReads(
              currentUid: () => 'owner-700',
              userDoc: (_) async => <String, dynamic>{'role': 'USER'},
              terms: () async => throw StateError('OVF3 시험 대역 — 약관 읽기 0'),
              recordConsent: (_) async {}))));
  await c.frames(12);
  const label = '외국인 가입 이어서 완료';
  final f = _plain(label);
  await c.visible(f, '단추 $label');
  final lines = _lines(c.t, f);
  const words = ['외국인', '가입', '이어서', '완료'];
  final bad = [for (final l in lines) ...l.trim().split(' ').where((w) => w.isNotEmpty && !words.contains(w))];
  expect(bad, isEmpty, reason: '줄 조각 $lines — 모든 조각이 온전한 낱말(음절 중간 줄바꿈 0)');
}


void main() {
  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
    await _loadFonts();
  });
  testWidgets('OVF3-B-OCRS OCR 일치 창(320×640 · 글자 2.0) — 넘침 0 · 등록하기 보임·hit · true', (t) async {
    await _strict(t, _vB, _ocrs);
  });
  testWidgets('OVF3-B-OCRE OCR 인식 실패 창(320×640 · 글자 2.0) — 넘침 0 · 단추 3 보임·hit · 취소 false', (t) async {
    await _strict(t, _vB, _ocre);
  });
  testWidgets('OVF3-N-OCRE OCR 인식 실패 창(320×640 · 글자 1.0) — 넘침 0 · 단추 3 보임·hit · 취소 false', (t) async {
    await _strict(t, _vN, _ocre);
  });
  testWidgets('OVF3-B-IDRA 신분증 열람 요청 1 명(320×640 · 글자 2.0) — 넘침 0 · 사유 3 · 요청 보내기 보임·hit · 취소', (t) async {
    await _strict(t, _vB, (c) => _idr(c, '1'));
  });
  testWidgets('OVF3-B-IDRM 신분증 열람 요청 3 명(320×640 · 글자 2.0) — 넘침 0 · 사유 3 · 요청 보내기 보임·hit · 취소', (t) async {
    await _strict(t, _vB, (c) => _idr(c, '3'));
  });
  testWidgets('OVF3-B-RRCF 가입 복구 단추 글 낱말 줄바꿈(320×640 · 글자 2.0) — 넘침 0 · 음절 중간 줄바꿈 0', (t) async {
    await _strict(t, _vB, _rrcfWrap);
  });
}
