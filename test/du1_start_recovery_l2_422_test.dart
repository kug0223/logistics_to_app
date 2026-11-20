// [p3 · 후속101 F101-1] p2(fd6a2ac9) 대비 바뀐 것은 기본 skip 하나다 — 공용 lkit 단계 env 로만 켠다(새 키 0 · 공용 runner 변경 0).
//   TB: DU1_VQ_PHASE=before · DU1_VQ_RUN=du422-tb · DU_BEFORE_OBSERVE=422 / TA: DU1_VQ_PHASE=after · DU1_VQ_RUN=du422-ta · DU_BEFORE_OBSERVE 없음.
//   그 밖의 호출(일반 flutter test · 다른 run 값 · RG)은 8개 모두 skip — 본문 · 주입 · 캡처 0. 나머지 원문은 p2 그대로다.
// [DU422 · 시작·복구 L2 · 후속100 §2] S094(AuthWrapper 역할 분기 catch) · S085(_HomeRegionRecoveryScreen) 표시 교정의 before/strict 관측.
//   records 후보 파일이다 — 승인 전에는 AlFit test/ 에 두지 않는다(analyze 0 · 정적 미검증. 승인 실행의 ANALYZE1 이 첫 검사).
//   같은 파일이 B0(main.dart 386ee7f8)와 B2(cea5554f) 양쪽에서 컴파일되도록 공개 AuthWrapper 하나만 main.dart 에서 가져온다(새 제품 seam 0).
//   host: MultiProvider(UserProvider 대역 · ThemeProvider 'USER' 미리 고정) → RepaintBoundary → MaterialApp(RoleTheme.workerTheme ·
//     builder TextScaler) · home: AuthWrapper — 실제 분기(:403–430 try · :417–420 homeRegion null).
//     Firebase 는 DU421 시험(e161ac85 :61–75 · :294–297)과 같은 _FakeCore 초기화(기존 mock) — 대역 UserProvider() 기본 생성의
//     AuthService 필드 초기화가 FirebaseAuth/Firestore.instance 를 읽기 때문. 제품 Firebase · 실데이터 · 네트워크 0.
//     prefs: onboarding_completed_u1 = true(온보딩 분기 통과). 사용자: USER · uid u1 · homeRegion null(debugSetCurrentUser).
//   S094 유도(제품 seam 0): debugPrint 를 시험에서 감싸 원 콜백에 모두 전달하고, try 안의 정확 로그
//     '🔄 USER homeRegion 없음 → 복구 화면 (강제)' 를 전달한 직후 고정 marker 예외를 정확 1회 던진다(던지기 전 latch).
//     로그 호출에 합성 예외를 주입한 실제 catch/renderer 경로이며, 자연 발생 예외 재현 · 운영 원인 확인이 아니다.
//     복구는 finally(시험 끝 불변식 검사 전) — tearDown 은 늦다(DU421 repair r1 과 같은 이유).
//   S085: 같은 host 의 실제 복구 화면. 지역 선택은 실제 HomeRegionPickerSheet 에서 '세종특별자치시'(한 번에 완료 · 가장 긴 표시
//     '세종특별자치시 세종특별자치시'). 로그아웃은 대역 signOut — UNSELECTED 는 실패(Future.error), SIGNINGOUT 은 끝나지 않는 Future.
//     저장(_save)은 누르지 않는다 — FirestoreService() 인라인 생성이라 저장 중 · 저장 실패는 이 접근으로 유도하지 않는다(관측 0 · 한계).
//     토스트는 navigatorKey 미부착이라 표시되지 않는다(ToastHelper :61–62 null 반환) — 토스트 관측 0.
//   장면: 뷰 W 390x844@1.0 · B 320x640@2.0 × 상태 ROUTEERR · UNSELECTED · SELECTED · SIGNINGOUT = 공개 8 · 각 캡처 1(1main).
//   모드: DU_BEFORE_OBSERVE=422 이면 before(B0 — 값은 관측 · 소스로 확정된 것만 정확), 아니면 strict(B2 — 계약 단언).
//   낭독: 의미 트리 flag/action 검사일 뿐 실제 스크린리더 낭독 인증이 아니다.
//   출력 줄: lkit 선언형 계약 'D422 <tok> <kind> [<sub>] k=v …' — 값 공백 0(공백 → '_' · 줄 구분 '|').
// ignore_for_file: depend_on_referenced_packages
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ALfit/main.dart' show AuthWrapper;
import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/providers/theme_provider.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/theme/app_colors.dart';
import 'package:ALfit/theme/role_theme.dart';
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

enum _Out { ok, fail, pending }

/// 대역 provider — 사용자는 debugSetCurrentUser 로 넣는다(isLoggedIn = 필드 기준). signOut 만 바꾼다(호출 수 계수).
class _Prov extends UserProvider {
  _Prov(this.out);
  final _Out out;
  int signOutCalls = 0;
  final Completer<void> _never = Completer<void>();
  @override
  Future<void> signOut() {
    signOutCalls++;
    switch (out) {
      case _Out.ok:
        return Future<void>.value();
      case _Out.fail:
        return Future<void>.error(StateError('DU422 대역 로그아웃 실패'));
      case _Out.pending:
        return _never.future;
    }
  }
}

UserModel _user() => UserModel(
    uid: 'u1', username: 'u1', name: '김근로', email: 'u1@alfit.local', role: UserRole.USER,
    accountStatus: 'active', passVerifiedAt: DateTime.utc(2026, 10, 1));

// vq _loadFonts(:491–511) 와 같은 4 등록(DU421 :144–156 과 같음)
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

final bool _before = Platform.environment['DU_BEFORE_OBSERVE'] == '422';
// [p3 · F101-1] 명시 opt-in — 승인 TB/TA 의 단계 env 정확 조합일 때만 본문을 돌린다.
final Map<String, String> _env = Platform.environment;
final bool _optIn =
    (_env['DU1_VQ_PHASE'] == 'before' && _env['DU1_VQ_RUN'] == 'du422-tb' && _env['DU_BEFORE_OBSERVE'] == '422') ||
        (_env['DU1_VQ_PHASE'] == 'after' && _env['DU1_VQ_RUN'] == 'du422-ta' && _env['DU_BEFORE_OBSERVE'] == null);
var _anyFail = false; // 같은 파일 앞 사례 실패 뒤 본문 · 캡처 0
final String _manifest = Platform.environment['DUL_MANIFEST'] ?? '(unset)';
const _envKeys = ['DU_BEFORE_OBSERVE', 'DU1_VQ_PHASE', 'DU1_VQ_OUT', 'DU1_VQ_RUN', 'DU1_VQ_DATE', 'DU397_DIAG', 'DU397_MANIFEST', 'DU400_MANIFEST',
  'DU401_MANIFEST', 'DU398_MANIFEST', 'DU406_MANIFEST', 'DU407_MANIFEST', 'DU296_PHASE', 'DUL_MANIFEST'];
final String _envLine = [for (final k in _envKeys) '$k:${Platform.environment[k] ?? '(unset)'}'].join(',');

const _marker = '🔄 USER homeRegion 없음 → 복구 화면 (강제)'; // main.dart :418(B0) — B2 같은 줄
const _injectMsg = 'DU422_INJECT 역할 분기 시험 주입 예외';
const _catchLog = '❌ 화면 전환 중 에러 발생!'; // main.dart :431
const _routeCta = '로그아웃하고 다시 시도';
const _routeOld = '화면을 불러오는 중 오류가 발생했습니다';
const _routeNew = '화면을 불러오지 못했어요';
const _routeBody = '일시적인 문제일 수 있어요.\n로그아웃한 뒤 다시 로그인해 주세요.';
const _regionTitle = '주로 일할 지역을 알려주세요';
const _hint = '지역 선택하기';
const _save = '저장하고 시작하기';
const _sejong = '세종특별자치시';

void _out(String s) {
  // ignore: avoid_print
  print(s);
}

String _f1(double v) => v.toStringAsFixed(1);
String _rect(Rect r) => '${_f1(r.left)},${_f1(r.top)},${_f1(r.right)},${_f1(r.bottom)}';
String _b64(List<String> xs) => xs.isEmpty ? '-' : base64Url.encode(utf8.encode(xs.join('\n'))).replaceAll('=', '');
String _w(String s) => s.replaceAll('\n', '|').replaceAll(' ', '_');
String _plainOf(Widget w) => w is RichText ? TextLayout.plain(w.text.toPlainText(includeSemanticsLabels: false)) : '';
Finder _rich(String plain) => find.byWidgetPredicate((w) => w is RichText && _plainOf(w) == plain);
Finder _richHas(String part) => find.byWidgetPredicate((w) => w is RichText && _plainOf(w).contains(part));
Rect _rectOf(WidgetTester t, Finder f) {
  final ro = t.renderObject(f) as RenderBox;
  return MatrixUtils.transformRect(ro.getTransformTo(null), Offset.zero & ro.size);
}

bool _inside(Rect outer, Rect r) =>
    r.left >= outer.left - 0.5 && r.top >= outer.top - 0.5 && r.right <= outer.right + 0.5 && r.bottom <= outer.bottom + 0.5;

const _tokens = <String, Color>{
  'grey50': AppColors.grey50, 'background': AppColors.background, 'grey400': AppColors.grey400, 'textSecondary': AppColors.textSecondary,
  'textTertiary': AppColors.textTertiary, 'textPrimary': AppColors.textPrimary, 'error': AppColors.error, 'errorDark': AppColors.errorDark,
};
String _tok(Color? c) {
  if (c == null) return 'null';
  for (final e in _tokens.entries) {
    if (e.value.toARGB32() == c.toARGB32()) return e.key;
  }
  return 'x${c.toARGB32().toRadixString(16)}';
}

Color? _richColor(WidgetTester t, Finder f) => (t.widget(f) as RichText).text.style?.color;

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({'onboarding_completed_u1': true}));
  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
  });

  const views = [(id: 'W', w: 390.0, h: 844.0, s: 1.0), (id: 'B', w: 320.0, h: 640.0, s: 2.0)];
  const states = [
    (key: 'ROUTEERR', title: '역할 분기 catch — try 안 정확 로그 1회 주입 · 실패 안내 · 로그아웃 CTA', out: _Out.ok),
    (key: 'UNSELECTED', title: '지역 설정 복구 — 첫 진입(미선택) · 로그아웃 실패 뒤 다시 누를 수 있음', out: _Out.fail),
    (key: 'SELECTED', title: '지역 설정 복구 — 실제 시트에서 세종특별자치시 선택(가장 긴 표시)', out: _Out.ok),
    (key: 'SIGNINGOUT', title: '지역 설정 복구 — 미선택에서 로그아웃 진행 중(끝나지 않는 대역)', out: _Out.pending),
  ];
  for (final v in views) {
    for (final st in states) {
      testWidgets('S094SR-${v.id}-${st.key} ${st.title}', (t) async {
        if (_anyFail) fail('앞 사례 실패 — 이 사례 본문 실행 0 · 캡처 0');
        SemanticsHandle? sem;
        final origPrint = debugPrint;
        try {
          final tok = 'S094SR-${v.id}-${st.key}';
          final mode = _before ? 'before' : 'strict';
          _out('D422 $tok begin mode=$mode phase=${Platform.environment['DU1_VQ_PHASE'] ?? '(unset)'} env=$_envLine manifest=$_manifest');
          await t.runAsync(_loadFonts);
          sem = t.ensureSemantics();
          // debugPrint 감시 — 모든 줄을 원 콜백에 전달. ROUTEERR 만 _marker 전달 직후 1회 던진다(던지기 전 latch).
          var markerSeen = 0, injected = 0, catchLogSeen = 0, errLogSeen = 0;
          debugPrint = (String? m, {int? wrapWidth}) {
            origPrint(m, wrapWidth: wrapWidth);
            if (m == _catchLog) catchLogSeen++;
            if (m == '에러: Bad state: $_injectMsg') errLogSeen++;
            if (m == _marker) {
              markerSeen++;
              if (st.key == 'ROUTEERR' && injected == 0) {
                injected = 1;
                throw StateError(_injectMsg);
              }
            }
          };
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
          final vp = Offset.zero & Size(v.w, v.h);
          final prov = _Prov(st.out)..debugSetCurrentUser(_user());
          final theme = ThemeProvider()..setRole('USER'); // 미리 고정 — AuthWrapper 의 setRole('USER') 는 같은 값이라 알림 0
          final key = GlobalKey();
          await t.pumpWidget(MultiProvider(
            providers: [
              ChangeNotifierProvider<UserProvider>.value(value: prov),
              ChangeNotifierProvider<ThemeProvider>.value(value: theme),
            ],
            child: RepaintBoundary(
              key: key,
              child: MaterialApp(
                  debugShowCheckedModeBanner: false,
                  theme: RoleTheme.workerTheme,
                  builder: (ctx, child) => MediaQuery(data: MediaQuery.of(ctx).copyWith(textScaler: TextScaler.linear(v.s)), child: child!),
                  home: const AuthWrapper()),
            ),
          ));
          final isRoute = st.key == 'ROUTEERR';
          for (var i = 0; i < 30; i++) {
            await t.pump(const Duration(milliseconds: 16));
            if ((isRoute ? _rich(_routeCta) : _rich(_regionTitle)).evaluate().isNotEmpty) break;
          }
          must('대상 화면 도달', (isRoute ? _rich(_routeCta) : _rich(_regionTitle)).evaluate().length == 1);

          if (isRoute) {
            // ── S094 ──────────────────────────────────────────────
            final catchOn = _rich(_routeCta).evaluate().length == 1;
            final regionOn = _rich(_regionTitle).evaluate().isNotEmpty;
            final raw = _richHas('DU422_INJECT').evaluate().isNotEmpty;
            _out('D422 $tok route inj injected=$injected marker=$markerSeen log=$catchLogSeen errLog=$errLogSeen catch=$catchOn region=$regionOn raw=$raw');
            must('주입 정확 1 · 표지 로그 1 · catch 로그 각 1', injected == 1 && markerSeen == 1 && catchLogSeen == 1 && errLogSeen == 1,
                '$injected/$markerSeen/$catchLogSeen/$errLogSeen');
            must('catch 화면 · 복구 화면 아님', catchOn && !regionOn);
            final oldT = _rich(_routeOld).evaluate().isNotEmpty;
            final newT = _rich(_routeNew).evaluate().isNotEmpty;
            final bodyT = _rich(_routeBody).evaluate().isNotEmpty;
            _out('D422 $tok route text old=$oldT new=$newT body=$bodyT');
            final btnF = find.ancestor(of: _rich(_routeCta), matching: find.byType(ElevatedButton));
            await t.ensureVisible(btnF);
            await t.pump();
            final btn = _rectOf(t, btnF);
            final bMin = btn.height >= 52 - 0.01;
            final bVis = _inside(vp, btn);
            _out('D422 $tok route geo btn=${_rect(btn)} btnH=${_f1(btn.height)} min=$bMin vis=$bVis ovf=${overflows.length}');
            final icon = t.widget<Icon>(find.byIcon(Icons.error_outline));
            _out('D422 $tok route look icon=${_tok(icon.color)}');
            if (!_before) {
              must('strict 원문 없음 · 새 제목 · 안내', !raw && !oldT && newT && bodyT, '$raw $oldT $newT $bodyT');
              must('strict 주 버튼 ≥ 52 · 화면 안', bMin && bVis, _rect(btn));
              must('strict 아이콘 errorDark', _tok(icon.color) == 'errorDark');
              must('strict 넘침 0', overflows.isEmpty, overflows.join(' | '));
            }
            must('shot 직전 미처리 framework 예외 0', fwErrors.isEmpty, '$fwErrors');
            must('shot 직전 catch 유지 · 주입 1', _rich(_routeCta).evaluate().length == 1 && injected == 1 && markerSeen == 1);
            _out('D422 $tok shot 1main ovf=${overflows.length}');
            await vqCapture(t, key, '${tok}_1main', conditions: {
              'viewport': '${v.w.toInt()}x${v.h.toInt()}', 'textScaler': v.s, 'run': vqRun, 'manifest': _manifest, 'mode': mode, 'fixture': st.key,
              'state': 'route-error-catch',
            });
            await t.tap(btnF);
            await t.pump(const Duration(milliseconds: 300));
            final still = _rich(_routeCta).evaluate().length == 1;
            final regionAfter = _rich(_regionTitle).evaluate().isNotEmpty;
            _out('D422 $tok route act calls=${prov.signOutCalls} catch=$still region=$regionAfter');
            must('CTA → 대역 signOut 정확 1 · catch 유지', prov.signOutCalls == 1 && still && !regionAfter, '${prov.signOutCalls}');
          } else {
            // ── S085 ──────────────────────────────────────────────
            final catchOn = _rich(_routeCta).evaluate().isNotEmpty;
            _out('D422 $tok region nav marker=$markerSeen region=true catch=$catchOn');
            must('주입 0 · catch 아님', injected == 0 && !catchOn && markerSeen >= 1, '$injected $catchOn $markerSeen');
            Finder tapF() => find.ancestor(
                of: _rich(st.key == 'SELECTED' ? '$_sejong $_sejong' : _hint),
                matching: find.byWidgetPredicate((w) => (w is GestureDetector && w.onTap != null) || (w is InkWell && w.onTap != null))).first;
            if (st.key == 'SELECTED') {
              await t.ensureVisible(_rich(_hint));
              await t.pump();
              await t.tap(_rich(_hint));
              await t.pumpAndSettle();
              // 시트 목록은 ListView.builder(지연 생성) — 아직 안 만든 항목도 찾도록 시트 목록(마지막 Scrollable)을 굴린다.
              final item = _rich(_sejong);
              await t.scrollUntilVisible(item, 120, scrollable: find.byType(Scrollable).last);
              await t.pumpAndSettle();
              must('시트 세종특별자치시 항목 1', item.evaluate().length == 1);
              await t.tap(item);
              await t.pumpAndSettle();
              must('선택 반영', _rich('$_sejong $_sejong').evaluate().length == 1);
            }
            final saveF = find.ancestor(of: _rich(_save), matching: find.byType(ElevatedButton));
            final outF = find.byType(TextButton);
            must('저장 1 · 로그아웃 1', saveF.evaluate().length == 1 && outF.evaluate().length == 1);
            bool enabledOf(Finder f) => (t.widget(f) as ButtonStyleButton).enabled;
            if (st.key == 'SIGNINGOUT') {
              await t.ensureVisible(outF);
              await t.pump();
              await t.tap(outF);
              await t.pump(const Duration(milliseconds: 100));
              final spin = find.descendant(of: outF, matching: find.byType(CircularProgressIndicator)).evaluate().isNotEmpty;
              _out('D422 $tok region act calls=${prov.signOutCalls} spin=$spin outOn=${enabledOf(outF)} saveOn=${enabledOf(saveF)} cardTap=${tapF().evaluate().isNotEmpty}');
              must('진행 중 · 로그아웃 비활성 · 미선택 저장 비활성', prov.signOutCalls == 1 && spin && !enabledOf(outF) && !enabledOf(saveF));
            }
            await t.ensureVisible(outF);
            await t.pump();
            final card = _rectOf(t, tapF());
            final save = _rectOf(t, saveF);
            final out = _rectOf(t, outF);
            final label = _rectOf(t, _rich(_save));
            final cMin = card.height >= 48 - 0.01, sMin = save.height >= 52 - 0.01, oMin = out.height >= 48 - 0.01;
            final lIn = _inside(save, label), vis = _inside(vp, out);
            _out('D422 $tok region geo card=${_rect(card)} cardH=${_f1(card.height)} save=${_rect(save)} saveH=${_f1(save.height)} '
                'out=${_rect(out)} outH=${_f1(out.height)} cardMin=$cMin saveMin=$sMin outMin=$oMin labelIn=$lIn vis=$vis ovf=${overflows.length}');
            if (st.key != 'SIGNINGOUT') {
              final bg = t.widget<Scaffold>(find.ancestor(of: _rich(_regionTitle), matching: find.byType(Scaffold)).first).backgroundColor;
              final textF = _rich(st.key == 'SELECTED' ? '$_sejong $_sejong' : _hint);
              final chev = t.widget<Icon>(find.descendant(of: tapF(), matching: find.byIcon(Icons.chevron_right)));
              final ink = find.ancestor(of: textF, matching: find.byType(InkWell)).evaluate().length;
              final sd = t.getSemantics(textF).getSemanticsData();
              _out('D422 $tok region look bg=${_tok(bg)} hint=${_tok(_richColor(t, textF))} chev=${_tok(chev.color)} ink=$ink '
                  'button=${sd.flagsCollection.isButton} tap=${sd.hasAction(SemanticsAction.tap)}');
              if (!_before) {
                must('strict 바탕 · 안내 · 화살표 토큰', _tok(bg) == 'background' && _tok(chev.color) == 'textTertiary' &&
                    _tok(_richColor(t, textF)) == (st.key == 'SELECTED' ? 'textPrimary' : 'textSecondary'));
                must('strict 카드 InkWell 1 · 버튼 의미 · 탭', ink == 1 && sd.flagsCollection.isButton && sd.hasAction(SemanticsAction.tap));
              }
              final sel = st.key == 'SELECTED' ? ' sel=${_w('$_sejong $_sejong')}' : '';
              _out('D422 $tok region state$sel saveOn=${enabledOf(saveF)} outOn=${enabledOf(outF)} cardTap=${tapF().evaluate().isNotEmpty}');
            }
            if (!_before) {
              must('strict 카드 ≥ 48 · 저장 ≥ 52 · 로그아웃 ≥ 48 · 라벨 안 · 로그아웃 화면 안', cMin && sMin && oMin && lIn && vis,
                  '${_rect(card)} ${_rect(save)} ${_rect(out)} ${_rect(label)}');
              must('strict 넘침 0', overflows.isEmpty, overflows.join(' | '));
            }
            must('shot 직전 미처리 framework 예외 0', fwErrors.isEmpty, '$fwErrors');
            must('shot 직전 주입 0', injected == 0);
            _out('D422 $tok shot 1main ovf=${overflows.length}');
            await vqCapture(t, key, '${tok}_1main', conditions: {
              'viewport': '${v.w.toInt()}x${v.h.toInt()}', 'textScaler': v.s, 'run': vqRun, 'manifest': _manifest, 'mode': mode, 'fixture': st.key,
              'state': 'region-recovery',
            });
            if (st.key == 'UNSELECTED') {
              await t.tap(outF);
              await t.pump(const Duration(milliseconds: 100));
              _out('D422 $tok region act calls=${prov.signOutCalls} outOn=${enabledOf(outF)} saveOn=${enabledOf(saveF)}');
              must('로그아웃 실패 뒤 다시 누를 수 있음 · 저장 비활성 유지', prov.signOutCalls == 1 && enabledOf(outF) && !enabledOf(saveF));
            }
          }
          final exc = t.takeException();
          _out('D422 $tok done state=${st.key} mode=$mode captures=1 overflows=${overflows.length} exc=${exc != null} ovfRaw=${_b64(overflows)}');
          must('끝 예외 0', exc == null, '$exc');
        } catch (e) {
          _anyFail = true;
          rethrow;
        } finally {
          debugPrint = origPrint; // 시험 끝 불변식 검사 전 복구
          sem?.dispose();
        }
      }, skip: !_optIn); // [p3 · F101-1] 기본 skip
    }
  }
}
