// ignore_for_file: depend_on_referenced_packages
// [DU1 후속43] C0 S091 TermsViewerScreen · S004 개별 '보기→복귀' — 실제 RegisterScreen 약관 단계에서 개별 보기 버튼을 눌러 진입한다.
//   seam: RegisterScreen.termsLoaderForTest(QA 약관 표시 자료) · initialUserTermsStepForTest(약관 단계만 연다 — 인증·가입 writer 없음).
//   가입 진행/완료·서버 동의 writer 는 누르지 않는다(spy 없음 — 미진입은 정적 확인). viewed/consent 는 화면 표시(보기*/다시보기·체크 아이콘)로 관찰.
//   글꼴 vqLoadFonts · boundary = MaterialApp 바깥(root overlay·fullscreen route 포함) · DU1_VQ_OUT 직접 출력.
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ALfit/models/core/legal_terms_model.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/screens/auth/register_screen.dart';
import 'package:ALfit/theme/role_theme.dart';
import 'package:ALfit/widgets/auth/terms_viewer_screen.dart';

import 'support/du1_vq_capture.dart';
import 'support/visible_text.dart';

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

// ── QA 표시 자료(before 전 고정) — 실제 약관 정책/서버 문서가 아니다 ──
const kLongId = 'service_terms';
const kLongTitle = '[QA] 서비스 이용약관 (위치기반 근무 매칭 및 급여 정산 이용 조건 포함)';
const kLongVersion = '2026-11-01';
const kFirst = '[QA-첫문장] 이 약관은 ALfit 이 제공하는 근무 매칭 서비스의 이용 조건과 절차를 정합니다.';
const kLast = '[QA-끝문장] 본 약관은 2026년 11월 1일부터 시행하며, 이전 약관은 이 날부터 효력을 잃습니다.';
String longContent() {
  final b = StringBuffer('$kFirst\n');
  for (var n = 1; n <= 8; n++) {
    b.writeln('제$n조 (QA 조문 $n — 이용 조건과 책임의 범위)');
    b.writeln('① 회원은 서비스를 이용할 때 관계 법령과 이 약관의 내용을 지켜야 하며, 회사가 안내하는 이용 방법을 따라야 합니다.');
    b.writeln('② 회사는 서비스 화면에 표시한 근무 일정·장소·임금 정보를 사업장이 등록한 내용 그대로 보여 주며, 그 내용의 변경은 사업장의 책임입니다.');
    b.writeln('일반 단락: 근무 확정 이후의 취소·변경은 별도로 정한 절차에 따르고, 근태 기록은 사업장의 처리 기준에 따라 계산됩니다.');
  }
  b.write(kLast);
  return b.toString();
}

final kItems = [
  LegalTermsItem(id: kLongId, title: kLongTitle, content: longContent(), isRequired: true, version: kLongVersion,
      revisionId: '${kLongId}__$kLongVersion', order: 1),
  const LegalTermsItem(id: 'privacy', title: '개인정보 수집·이용 동의', content: '개인정보 수집·이용 동의 본문입니다.\n개인정보 수집·이용 동의 본문입니다.',
      isRequired: true, version: 'b', revisionId: 'privacy__b', order: 2),
  const LegalTermsItem(id: 'marketing', title: '마케팅 수신', content: '마케팅 수신 본문입니다.', isRequired: false, version: 'b',
      revisionId: 'marketing__b', order: 3),
];
EffectiveLegalTerms kTerms() => EffectiveLegalTerms(serverNow: DateTime.utc(2026, 11, 1), upcoming: const [], items: kItems);

Future<void> _settle(WidgetTester t, [int n = 8]) async {
  for (var i = 0; i < n; i++) {
    await t.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
  });

  for (final c in const [(id: 'C0-TV-A', w: 392.0, h: 844.0, s: 1.0), (id: 'C0-TV-B', w: 320.0, h: 640.0, s: 2.0)]) {
    testWidgets('${c.id} 약관 ${c.w.toInt()}×${c.h.toInt()}@${c.s} — 개별 보기→viewer→null 닫기→다시보기→끝→동의 true 복귀', (t) async {
      await t.runAsync(vqLoadFonts);
      final overflows = <String>[];
      final prev = FlutterError.onError;
      FlutterError.onError = (d) {
        final m = d.exceptionAsString();
        if (m.contains('overflowed')) {
          overflows.add(m.split('\n').first);
        } else {
          prev?.call(d);
        }
      };
      addTearDown(() => FlutterError.onError = prev);
      final size = Size(c.w, c.h);
      t.view.physicalSize = size;
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.reset);
      final key = GlobalKey();
      await t.pumpWidget(ChangeNotifierProvider<UserProvider>(
        create: (_) => UserProvider(),
        child: RepaintBoundary(
          key: key,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: RoleTheme.workerTheme,
            builder: (ctx, child) => MediaQuery(data: MediaQuery.of(ctx).copyWith(textScaler: TextScaler.linear(c.s)), child: child!),
            home: RegisterScreen(termsLoaderForTest: () async => kTerms(), initialUserTermsStepForTest: true),
          ),
        ),
      ));
      await _settle(t);
      final log = <String>[];
      void out(String l) {
        log.add(l);
        // ignore: avoid_print
        print(l);
      }
      final mq = MediaQuery.of(t.element(find.byType(RegisterScreen)));
      out('${c.id} screenMQ padding=${mq.padding} viewPadding=${mq.viewPadding} viewInsets=${mq.viewInsets} · physical ${t.view.padding.top},${t.view.padding.bottom},${t.view.viewInsets.bottom}');
      Map<String, Object?> cond(String state) => {
            'entry': 'RegisterScreen(termsLoaderForTest, initialUserTermsStepForTest) → 개별 보기 TextButton → TermsViewerScreen(fullscreenDialog)',
            'theme': 'RoleTheme.workerTheme', 'viewport': '${c.w.toInt()}x${c.h.toInt()}', 'dpr': 1.0, 'textScaler': c.s,
            'mq': 'padding=${mq.padding} viewPadding=${mq.viewPadding} viewInsets=${mq.viewInsets}',
            'fonts': 'vqLoadFonts: NotoSansKR Regular+Bold · Roboto=NotoSansKR · MaterialIcons(SDK) · FlutterTest 미등록',
            'data': 'kItems: $kLongId "$kLongTitle" v$kLongVersion 필수(긴 본문 제1~8조) · privacy 필수(짧음) · marketing 선택(짧음)',
            'prefs': 'setMockInitialValues({})', 'clock': '미주입(serverNow 2026-11-01 고정 자료)', 'state': state};
      bool hits(Finder f, Offset p) {
        final hit = HitTestResult();
        WidgetsBinding.instance.hitTestInView(hit, p, t.view.viewId);
        return hit.path.any((e) => e.target == t.renderObject(f));
      }
      String rr(Finder f) {
        final r = t.getRect(f);
        final inScreen = r.top >= 0 && r.bottom <= c.h && r.left >= 0 && r.right <= c.w;
        return '$r(${r.width.toStringAsFixed(1)}×${r.height.toStringAsFixed(1)}) hit=${hits(f, r.center)} inScreen=$inScreen';
      }
      // 등록 화면의 약관 행 — label Text 의 조상 Row 중 '보기'/'다시보기' TextButton 을 함께 가진 가장 가까운 Row
      // [DU1 구현160 · 후속160] 구현159 뒤 제목의 가장 가까운 Row 는 선택 영역 안쪽 Row 다 — 정확 제목 · TextButton · 체크(outline/filled)
      //   · 배지를 각 1개 함께 품는 조상 Row 를 정확히 1개로 단언해 외곽 Row 로 쓴다(보기 버튼 연결 유지).
      Finder termRow(String title) {
        final els = find.ancestor(of: findVisibleText(title), matching: find.byWidgetPredicate((w) => w is Row)).evaluate().where((e) {
          final f = find.byElementPredicate((x) => identical(x, e));
          int cnt(Finder m) => find.descendant(of: f, matching: m).evaluate().length;
          return cnt(findVisibleText(title)) == 1 && cnt(find.byType(TextButton)) == 1 &&
              cnt(find.byWidgetPredicate((w) => w is Icon && (w.icon == Icons.check_circle || w.icon == Icons.check_circle_outline))) == 1 &&
              cnt(find.byWidgetPredicate((w) => w is Text && (w.data == '필수' || w.data == '선택'))) == 1;
        }).toList();
        expect(els.length, 1, reason: '$title 외곽 Row(제목·체크·배지·보기) 하나');
        return find.byElementPredicate((x) => identical(x, els.single));
      }
      Finder viewBtn(String title) => find.descendant(of: termRow(title), matching: find.byType(TextButton));
      bool agreedOf(String title) =>
          find.descendant(of: termRow(title), matching: find.byIcon(Icons.check_circle)).evaluate().isNotEmpty;
      String viewLabel(String title) => visibleText(t.widget<Text>(find.descendant(of: viewBtn(title), matching: find.byType(Text))).data ?? '');
      final regScroll = find.descendant(of: find.byType(RegisterScreen), matching: find.byType(Scrollable)).first;
      Future<void> showRow(String title) async {
        await t.scrollUntilVisible(viewBtn(title), 120, scrollable: regScroll, maxScrolls: 80);
        await _settle(t, 2);
      }
      String states() => [for (final i in kItems) '${i.id}:${agreedOf(i.title) ? '동의' : '미동의'}/${viewLabel(i.title)}'].join(' ');

      // ① 개별 보기 — 대상 행 label 과 보기 버튼
      await showRow(kLongTitle);
      final regPos = t.state<ScrollableState>(regScroll).position;
      out('reg row label=${t.getRect(findVisibleText(kLongTitle))} viewBtn=${rr(viewBtn(kLongTitle))} offset=${regPos.pixels.toStringAsFixed(1)} states=${states()}');
      out('reg checkbox(InkWell) ${rr(find.ancestor(of: find.descendant(of: termRow(kLongTitle), matching: find.byIcon(Icons.check_circle_outline)), matching: find.byType(InkWell)).first)}');
      await vqCapture(t, key, '${c.id}_1_register_row', conditions: cond('가입 약관 단계 — 대상 행·보기 버튼'));
      final before = {for (final i in kItems) i.id: agreedOf(i.title)};
      await t.tap(viewBtn(kLongTitle));
      await _settle(t, 10);

      // ② 초기 viewer
      Finder vScroll() => find.descendant(of: find.byType(TermsViewerScreen), matching: find.byType(Scrollable)).first;
      ScrollPosition vPos() => t.state<ScrollableState>(vScroll()).position;
      Finder cta() => find.descendant(of: find.byType(TermsViewerScreen), matching: find.byType(ElevatedButton)).first;
      Finder closeX() => find.descendant(of: find.byType(TermsViewerScreen), matching: find.byType(IconButton)).first;
      Finder secondary() => find.descendant(of: find.byType(TermsViewerScreen), matching: find.byType(TextButton)).first;
      final titleText = find.descendant(of: find.byType(TermsViewerScreen), matching: findVisibleText(kLongTitle));
      String viewerState(String tag) {
        final tw = titleText.evaluate().isEmpty ? null : t.widget<Text>(titleText.first);
        final rp = titleText.evaluate().isEmpty ? null : t.renderObject<RenderParagraph>(titleText.first);
        return '$tag viewer title=${titleText.evaluate().isEmpty ? '없음' : t.getRect(titleText.first)} maxLines=${tw?.maxLines} '
            'titleClipped=${rp?.didExceedMaxLines} version=${findVisibleText('v$kLongVersion').evaluate().isNotEmpty} '
            'hint=${findVisibleText('끝까지 읽으면 동의할 수 있습니다').evaluate().isNotEmpty} cta=${rr(cta())} ctaEnabled=${t.widget<ElevatedButton>(cta()).onPressed != null} '
            'ctaLabel=${visibleText(t.widget<Text>(find.descendant(of: cta(), matching: find.byType(Text))).data ?? '')} '
            'close=${rr(closeX())} secondary=${rr(secondary())} bodyViewport=${t.getRect(vScroll())} offset=${vPos().pixels.toStringAsFixed(1)}/${vPos().maxScrollExtent.toStringAsFixed(1)}';
      }
      expect(find.byType(TermsViewerScreen), findsOneWidget, reason: '개별 보기 → fullscreen viewer');
      final first = findVisibleText(kFirst);
      out(viewerState('② 초기'));
      out('② first sentence=${t.getRect(first)} inBody=${t.getRect(first).top >= t.getRect(vScroll()).top - 0.5 && t.getRect(first).bottom <= t.getRect(vScroll()).bottom + 0.5}');
      expect(t.widget<ElevatedButton>(cta()).onPressed, isNull, reason: '긴 문서 초기 CTA 비활성');
      await vqCapture(t, key, '${c.id}_2_viewer_initial', conditions: cond('viewer 초기(안내·비활성 CTA·제목/version·첫 문장)'));

      // ③ null 닫기 — A: 헤더 X, B: 보조 '동의하지 않고 닫기'
      await t.tap(c.id.endsWith('A') ? closeX() : secondary());
      await _settle(t, 10);
      expect(find.byType(TermsViewerScreen), findsNothing);
      await showRow(kLongTitle);
      final after3 = {for (final i in kItems) i.id: agreedOf(i.title)};
      out('③ null 닫기(${c.id.endsWith('A') ? '헤더 X' : '보조 버튼'}) 복귀 states=${states()} consent변화=${after3.toString() != before.toString()}');
      expect(after3, before, reason: 'null 닫기는 동의를 바꾸지 않는다');
      // [r2] 표시 갱신 판정은 맨 끝에서 — 실패해도 이후 상태(다시 열기·끝·동의 복귀)의 증거를 남긴다
      final labelAfterNull = viewLabel(kLongTitle);
      out('③ 복귀 보기 버튼 글자="$labelAfterNull" (기대: 다시보기)');
      await vqCapture(t, key, '${c.id}_3_back_after_null', conditions: cond('null 닫기 복귀 — 다시보기·동의 불변'));

      // ④ 다시보기 → 새 viewer(CTA 비활성) → 끝 접근(활성) → 마지막 문장 끝 정렬
      await t.tap(viewBtn(kLongTitle));
      await _settle(t, 10);
      out(viewerState('④ 재진입'));
      expect(t.widget<ElevatedButton>(cta()).onPressed, isNull, reason: '새 viewer 의 _reachedBottom 은 새 상태');
      final vpBefore = t.getRect(vScroll());
      vPos().jumpTo(vPos().maxScrollExtent - 60); // 끝 80px 안으로 — 활성 임계
      await _settle(t, 4);
      final vpAfter = t.getRect(vScroll());
      out('④ 끝 접근 bodyViewport before=$vpBefore after=$vpAfter hintGone=${findVisibleText('끝까지 읽으면 동의할 수 있습니다').evaluate().isEmpty} ctaEnabled=${t.widget<ElevatedButton>(cta()).onPressed != null} offset=${vPos().pixels.toStringAsFixed(1)}/${vPos().maxScrollExtent.toStringAsFixed(1)}');
      expect(t.widget<ElevatedButton>(cta()).onPressed, isNotNull, reason: '끝 접근 → 활성');
      final last = findVisibleText(kLast);
      var lr = t.getRect(last);
      final vp4 = t.getRect(vScroll());
      vPos().jumpTo((vPos().pixels + (lr.bottom - (vp4.bottom - 4))).clamp(vPos().minScrollExtent, vPos().maxScrollExtent));
      await _settle(t, 3);
      lr = t.getRect(last);
      final vp4b = t.getRect(vScroll());
      out('④ 마지막 문장 끝 last=$lr bodyViewport=$vp4b 끝보임=${lr.bottom <= vp4b.bottom + 0.5 && lr.top >= vp4b.top - 0.5} offset=${vPos().pixels.toStringAsFixed(1)}/${vPos().maxScrollExtent.toStringAsFixed(1)} cta=${rr(cta())}');
      await vqCapture(t, key, '${c.id}_4_viewer_end', conditions: cond('다시보기 viewer 끝 — 마지막 문장·활성 CTA'));

      // ⑤ 동의하고 닫기 → 대상만 true
      await t.tap(cta());
      await _settle(t, 10);
      expect(find.byType(TermsViewerScreen), findsNothing);
      await showRow(kLongTitle);
      out('⑤ true 복귀 states=${states()}');
      expect(agreedOf(kLongTitle), isTrue);
      for (final i in kItems.skip(1)) {
        expect(agreedOf(i.title), before[i.id], reason: '${i.id} 동의는 그대로');
      }
      await vqCapture(t, key, '${c.id}_5_back_agreed', conditions: cond('동의하고 닫기 복귀 — 대상만 동의'));

      // ⑥ (A 셀만) 이미 동의한 항목을 다시 열고 null 닫기 → 동의 유지
      if (c.id.endsWith('A')) {
        await t.tap(viewBtn(kLongTitle));
        await _settle(t, 10);
        await t.tap(closeX());
        await _settle(t, 10);
        await showRow(kLongTitle);
        out('⑥ 동의 뒤 재열람·null 닫기 states=${states()}');
        expect(agreedOf(kLongTitle), isTrue, reason: 'null 닫기는 기존 동의를 해제하지 않는다');
      }
      FlutterError.onError = prev;
      out('overflows(${overflows.length})=${overflows.join(' | ')}');
      expect(labelAfterNull, '다시보기', reason: 'null 닫기 복귀 — 열람 기록(_viewedTermIds)이 보기 버튼 글자에 반영돼야 한다');
      expect(overflows, isEmpty, reason: overflows.join(' | '));
      expect(t.takeException(), isNull);
    });
  }

  // ── [DU1 후속44 §1] C0-TV-B-READ — 같은 B 조건·자료, 실제 개별 보기로 진입해 **중간 읽기 위치**만 순차 관찰한다.
  //   ① 고유 첫 문장 전문 ② 제1조 제목 ③ ①항 ④ ②항 ⑤ 일반 단락. 각 위치에서 본문 viewport·pixels·maxScrollExtent·대상 rect·PNG.
  //   끝/동의 경로는 반복하지 않는다. 마지막에 헤더 X 로 닫는다(null — 동의 writer 아님). 가입 진행·서버 writer 미진입.
  testWidgets('C0-TV-B-READ 약관 320×640@2.0 — 첫 문장 전문·제1조 제목/①/②/일반 단락 읽기 위치', (t) async {
    await t.runAsync(vqLoadFonts);
    final overflows = <String>[];
    final prev = FlutterError.onError;
    FlutterError.onError = (d) {
      final m = d.exceptionAsString();
      if (m.contains('overflowed')) {
        overflows.add(m.split('\n').first);
      } else {
        prev?.call(d);
      }
    };
    addTearDown(() => FlutterError.onError = prev);
    const size = Size(320, 640);
    t.view.physicalSize = size;
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    final key = GlobalKey();
    await t.pumpWidget(ChangeNotifierProvider<UserProvider>(
      create: (_) => UserProvider(),
      child: RepaintBoundary(
        key: key,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: RoleTheme.workerTheme,
          builder: (ctx, child) => MediaQuery(data: MediaQuery.of(ctx).copyWith(textScaler: const TextScaler.linear(2.0)), child: child!),
          home: RegisterScreen(termsLoaderForTest: () async => kTerms(), initialUserTermsStepForTest: true),
        ),
      ),
    ));
    await _settle(t);
    void out(String l) {
      // ignore: avoid_print
      print(l);
    }
    final mq = MediaQuery.of(t.element(find.byType(RegisterScreen)));
    out('C0-TV-B-READ screenMQ padding=${mq.padding} viewPadding=${mq.viewPadding} viewInsets=${mq.viewInsets} · physical ${t.view.padding.top},${t.view.padding.bottom},${t.view.viewInsets.bottom}');
    // [DU1 구현160 · 후속160] 구현159 뒤 제목의 가장 가까운 Row 는 선택 영역 안쪽 Row 다 — 정확 제목 · TextButton · 체크(outline/filled)
    //   · 배지를 각 1개 함께 품는 조상 Row 를 정확히 1개로 단언해 외곽 Row 로 쓴다(보기 버튼 연결 유지).
    Finder termRow(String title) {
      final els = find.ancestor(of: findVisibleText(title), matching: find.byWidgetPredicate((w) => w is Row)).evaluate().where((e) {
        final f = find.byElementPredicate((x) => identical(x, e));
        int cnt(Finder m) => find.descendant(of: f, matching: m).evaluate().length;
        return cnt(findVisibleText(title)) == 1 && cnt(find.byType(TextButton)) == 1 &&
            cnt(find.byWidgetPredicate((w) => w is Icon && (w.icon == Icons.check_circle || w.icon == Icons.check_circle_outline))) == 1 &&
            cnt(find.byWidgetPredicate((w) => w is Text && (w.data == '필수' || w.data == '선택'))) == 1;
      }).toList();
      expect(els.length, 1, reason: '$title 외곽 Row(제목·체크·배지·보기) 하나');
      return find.byElementPredicate((x) => identical(x, els.single));
    }
    Finder viewBtn(String title) => find.descendant(of: termRow(title), matching: find.byType(TextButton));
    final regScroll = find.descendant(of: find.byType(RegisterScreen), matching: find.byType(Scrollable)).first;
    await t.scrollUntilVisible(viewBtn(kLongTitle), 120, scrollable: regScroll, maxScrolls: 80);
    await _settle(t, 2);
    await t.tap(viewBtn(kLongTitle));
    await _settle(t, 10);
    expect(find.byType(TermsViewerScreen), findsOneWidget, reason: '실제 개별 보기 → viewer');
    final vScroll = find.descendant(of: find.byType(TermsViewerScreen), matching: find.byType(Scrollable)).first;
    final pos = t.state<ScrollableState>(vScroll).position;
    final header = find.descendant(of: find.byType(TermsViewerScreen), matching: find.byType(IconButton)).first;
    final cta = find.descendant(of: find.byType(TermsViewerScreen), matching: find.byType(ElevatedButton)).first;
    Map<String, Object?> cond(String state) => {
          'entry': 'RegisterScreen 약관 단계 → 대상 행 개별 보기 TextButton → TermsViewerScreen', 'theme': 'RoleTheme.workerTheme',
          'viewport': '320x640', 'dpr': 1.0, 'textScaler': 2.0, 'mq': 'padding=${mq.padding} viewPadding=${mq.viewPadding} viewInsets=${mq.viewInsets}',
          'fonts': 'vqLoadFonts: NotoSansKR Regular+Bold · Roboto=NotoSansKR · MaterialIcons(SDK) · FlutterTest 미등록',
          'data': 'kItems(구현43 과 같음) — $kLongId v$kLongVersion', 'prefs': 'setMockInitialValues({})', 'clock': '미주입(serverNow 2026-11-01 자료)',
          'state': state};
    // 대상 rect 전체를 본문 표시 영역 안(top+4)으로 — 표시 영역보다 크면 시작 정렬 뒤 끝 정렬을 따로 한다
    Future<void> read(String tag, Finder f) async {
      await t.ensureVisible(f);
      await _settle(t, 2);
      var vp = t.getRect(vScroll);
      var r = t.getRect(f);
      pos.jumpTo((pos.pixels + (r.top - (vp.top + 4))).clamp(pos.minScrollExtent, pos.maxScrollExtent));
      await _settle(t, 3);
      vp = t.getRect(vScroll);
      r = t.getRect(f);
      final whole = r.top >= vp.top - 0.5 && r.bottom <= vp.bottom + 0.5;
      final hr = t.getRect(header), cr = t.getRect(cta);
      out('$tag rect=$r bodyViewport=$vp pixels=${pos.pixels.toStringAsFixed(1)}/${pos.maxScrollExtent.toStringAsFixed(1)} 전체보임=$whole '
          'header(닫기)=$hr ctaTop=${cr.top.toStringAsFixed(1)} 본문∩CTA=${r.bottom > cr.top && r.top < cr.top} 본문∩머리=${r.top < vp.top - 0.5}');
      await vqCapture(t, key, 'C0-TV-B-READ_${tag.split(' ').first}', conditions: cond('$tag pixels=${pos.pixels.toStringAsFixed(1)} rect=$r'));
      if (!whole) {
        pos.jumpTo((pos.pixels + (r.bottom - (vp.bottom - 4))).clamp(pos.minScrollExtent, pos.maxScrollExtent));
        await _settle(t, 3);
        final r2 = t.getRect(f);
        out('$tag (끝 정렬) rect=$r2 pixels=${pos.pixels.toStringAsFixed(1)} 끝보임=${r2.bottom <= t.getRect(vScroll).bottom + 0.5}');
        await vqCapture(t, key, 'C0-TV-B-READ_${tag.split(' ').first}b_end', conditions: cond('$tag 끝 정렬 pixels=${pos.pixels.toStringAsFixed(1)} rect=$r2'));
      }
      expect(whole || t.getRect(f).bottom <= t.getRect(vScroll).bottom + 0.5, isTrue, reason: '$tag 처음·끝을 읽을 수 있다');
    }
    final article1 = findVisibleTextContaining('제1조 (QA 조문 1');
    await read('①첫문장 고유 첫 문장', findVisibleText(kFirst));
    await read('②제1조 제목', article1);
    await read('③①항 제1조 ①', findVisibleTextContaining('① 회원은 서비스를 이용할 때').first);
    await read('④②항 제1조 ②', findVisibleTextContaining('② 회사는 서비스 화면에 표시한').first);
    await read('⑤일반단락 제1조 일반 단락', findVisibleTextContaining('일반 단락: 근무 확정 이후의').first);
    // 위계: 조문 제목은 굵게(w600)·①② 와 일반 단락은 보통 — 실제 그려진 스타일
    String wOf(Finder f) => '${t.widget<Text>(f).style?.fontWeight}';
    out('위계 제1조=${wOf(article1.first)} ①=${wOf(findVisibleTextContaining('① 회원은 서비스를 이용할 때').first)} 일반=${wOf(findVisibleTextContaining('일반 단락: 근무 확정 이후의').first)}');
    await t.tap(header);
    await _settle(t, 10);
    expect(find.byType(TermsViewerScreen), findsNothing, reason: '헤더 X 닫기(null)');
    FlutterError.onError = prev;
    out('overflows(${overflows.length})=${overflows.join(' | ')}');
    expect(overflows, isEmpty, reason: overflows.join(' | '));
    expect(t.takeException(), isNull);
  });

  // ── [DU1 구현45 · 감사45 §4 다음 대표] C0 S004 전체 동의 — 실제 순차 viewer.
  //   1회: 전체 동의 탭 → (미동의 항목 순서대로) 긴 약관 끝까지 → 동의 / privacy → '동의하지 않고 닫기'(null) / marketing → 동의
  //        → 부모: 거절한 항목만 미동의, 전체 동의 미체크.
  //   2회: 전체 동의 탭 → 미동의(privacy) 하나만 열림 → 동의 → 전부 동의·전체 동의 체크.  3회: 전체 동의 탭 → 전부 해제.
  //   viewer 를 home 에 두지 않는다. 가입 진행·서버 동의 writer 미진입(정적 확인). 상태는 화면 표시(체크 아이콘·보기 글자)로 관찰.
  for (final c in const [(id: 'C0-AA-A', w: 392.0, h: 844.0, s: 1.0), (id: 'C0-AA-B', w: 320.0, h: 640.0, s: 2.0)]) {
    testWidgets('${c.id} 전체 동의 ${c.w.toInt()}×${c.h.toInt()}@${c.s} — 순차 viewer true/null/true → 부모 반영 → 재탭 → 해제', (t) async {
      await t.runAsync(vqLoadFonts);
      final overflows = <String>[];
      final prev = FlutterError.onError;
      FlutterError.onError = (d) {
        final m = d.exceptionAsString();
        if (m.contains('overflowed')) {
          overflows.add(m.split('\n').first);
        } else {
          prev?.call(d);
        }
      };
      addTearDown(() => FlutterError.onError = prev);
      final size = Size(c.w, c.h);
      t.view.physicalSize = size;
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.reset);
      final key = GlobalKey();
      await t.pumpWidget(ChangeNotifierProvider<UserProvider>(
        create: (_) => UserProvider(),
        child: RepaintBoundary(
          key: key,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: RoleTheme.workerTheme,
            builder: (ctx, child) => MediaQuery(data: MediaQuery.of(ctx).copyWith(textScaler: TextScaler.linear(c.s)), child: child!),
            home: RegisterScreen(termsLoaderForTest: () async => kTerms(), initialUserTermsStepForTest: true),
          ),
        ),
      ));
      await _settle(t);
      void out(String l) {
        // ignore: avoid_print
        print(l);
      }
      final mq = MediaQuery.of(t.element(find.byType(RegisterScreen)));
      out('${c.id} screenMQ padding=${mq.padding} viewPadding=${mq.viewPadding} viewInsets=${mq.viewInsets} · physical ${t.view.padding.top},${t.view.padding.bottom},${t.view.viewInsets.bottom}');
      Map<String, Object?> cond(String state) => {
            'entry': 'RegisterScreen 약관 단계 → 전체 동의 InkWell → TermsViewerScreen 순차', 'theme': 'RoleTheme.workerTheme',
            'viewport': '${c.w.toInt()}x${c.h.toInt()}', 'dpr': 1.0, 'textScaler': c.s,
            'mq': 'padding=${mq.padding} viewPadding=${mq.viewPadding} viewInsets=${mq.viewInsets}',
            'fonts': 'vqLoadFonts: NotoSansKR Regular+Bold · Roboto=NotoSansKR · MaterialIcons(SDK) · FlutterTest 미등록',
            'data': 'kItems(구현43 과 같음): service_terms 필수 긴 본문 · privacy 필수 짧음 · marketing 선택 짧음',
            'prefs': 'setMockInitialValues({})', 'clock': '미주입(serverNow 2026-11-01 자료)', 'state': state};
      bool hits(Finder f, Offset p) {
        final hit = HitTestResult();
        WidgetsBinding.instance.hitTestInView(hit, p, t.view.viewId);
        return hit.path.any((e) => e.target == t.renderObject(f));
      }
      String rr(Finder f) {
        final r = t.getRect(f);
        return '$r(${r.width.toStringAsFixed(1)}×${r.height.toStringAsFixed(1)}) hit=${hits(f, r.center)} inScreen=${r.top >= 0 && r.bottom <= c.h && r.left >= 0 && r.right <= c.w}';
      }
      Finder termRow(String title) => find.ancestor(of: findVisibleText(title), matching: find.byWidgetPredicate((w) => w is Row)).first;
      bool agreedOf(String title) => find.descendant(of: termRow(title), matching: find.byIcon(Icons.check_circle)).evaluate().isNotEmpty;
      final allText = findVisibleText('전체 동의');
      final allTap = find.ancestor(of: allText, matching: find.byType(InkWell)).first;
      bool allChecked() => find.descendant(of: allTap, matching: find.byIcon(Icons.check_circle)).evaluate().isNotEmpty;
      final regScroll = find.descendant(of: find.byType(RegisterScreen), matching: find.byType(Scrollable)).first;
      String states() => '전체=${allChecked() ? '체크' : '미체크'} ${[for (final i in kItems) '${i.id}:${agreedOf(i.title) ? '동의' : '미동의'}'].join(' ')}';
      Future<void> showAll() async {
        await t.scrollUntilVisible(allTap, 120, scrollable: regScroll, maxScrolls: 80);
        await _settle(t, 2);
      }
      Finder vScroll() => find.descendant(of: find.byType(TermsViewerScreen), matching: find.byType(Scrollable)).first;
      Finder cta() => find.descendant(of: find.byType(TermsViewerScreen), matching: find.byType(ElevatedButton)).first;
      Finder secondary() => find.descendant(of: find.byType(TermsViewerScreen), matching: find.byType(TextButton)).first;
      bool ctaOn() => t.widget<ElevatedButton>(cta()).onPressed != null;
      String viewerTitle() => visibleText(t.widget<TermsViewerScreen>(find.byType(TermsViewerScreen)).item.title);

      await showAll();
      out('① 전체 동의 target=${rr(allTap)} states=${states()}');
      await vqCapture(t, key, '${c.id}_1_all_before', conditions: cond('전체 동의 전'));
      // ── 1회 전체 동의
      await t.tap(allText);
      await _settle(t, 10);
      // viewer 1: 긴 약관 → 끝 → 동의
      expect(find.byType(TermsViewerScreen), findsOneWidget);
      out('② viewer#1 title="${viewerTitle()}" ctaEnabled=${ctaOn()} cta=${rr(cta())}');
      expect(viewerTitle(), kLongTitle, reason: '미동의 첫 항목 = service_terms');
      await vqCapture(t, key, '${c.id}_2_seq1_initial', conditions: cond('순차 #1 초기(비활성)'));
      final p1 = t.state<ScrollableState>(vScroll()).position;
      p1.jumpTo(p1.maxScrollExtent);
      await _settle(t, 4);
      out('② viewer#1 끝 pixels=${p1.pixels.toStringAsFixed(1)}/${p1.maxScrollExtent.toStringAsFixed(1)} ctaEnabled=${ctaOn()} 마지막문장=${t.getRect(findVisibleText(kLast))} viewport=${t.getRect(vScroll())}');
      expect(ctaOn(), isTrue);
      await t.tap(cta());
      await _settle(t, 10);
      // viewer 2: privacy(짧음 — 처음부터 활성) → null
      expect(find.byType(TermsViewerScreen), findsOneWidget, reason: '다음 미동의 항목 viewer');
      out('③ viewer#2 title="${viewerTitle()}" ctaEnabled=${ctaOn()}(짧은 문서 maxScrollExtent<50 → 처음부터 활성) cta=${rr(cta())} secondary=${rr(secondary())}');
      expect(viewerTitle(), '개인정보 수집·이용 동의');
      await vqCapture(t, key, '${c.id}_3_seq2_short', conditions: cond('순차 #2 짧은 약관(처음부터 활성)'));
      await t.tap(secondary());
      await _settle(t, 10);
      // viewer 3: marketing → 동의
      expect(find.byType(TermsViewerScreen), findsOneWidget);
      out('④ viewer#3 title="${viewerTitle()}" ctaEnabled=${ctaOn()}');
      expect(viewerTitle(), '마케팅 수신');
      await t.tap(cta());
      await _settle(t, 10);
      expect(find.byType(TermsViewerScreen), findsNothing);
      await showAll();
      out('⑤ 1회 결과 states=${states()}');
      expect(agreedOf(kLongTitle), isTrue);
      expect(agreedOf('개인정보 수집·이용 동의'), isFalse, reason: 'null 닫은 항목만 미동의');
      expect(agreedOf('마케팅 수신'), isTrue);
      expect(allChecked(), isFalse);
      await vqCapture(t, key, '${c.id}_4_after_first', conditions: cond('1회 전체 동의 뒤 — privacy 만 미동의'));
      // ── 2회: 미동의 privacy 하나만
      await t.tap(allText);
      await _settle(t, 10);
      out('⑥ 2회 viewer title="${viewerTitle()}"');
      expect(viewerTitle(), '개인정보 수집·이용 동의', reason: '이미 동의한 항목은 다시 열지 않는다');
      await t.tap(cta());
      await _settle(t, 10);
      expect(find.byType(TermsViewerScreen), findsNothing, reason: '열 항목이 하나뿐');
      await showAll();
      out('⑦ 2회 결과 states=${states()}');
      expect(allChecked(), isTrue);
      for (final i in kItems) {
        expect(agreedOf(i.title), isTrue, reason: i.id);
      }
      await vqCapture(t, key, '${c.id}_5_all_agreed', conditions: cond('2회 뒤 전부 동의'));
      // ── 3회: 해제(viewer 없음)
      await t.tap(allText);
      await _settle(t, 6);
      expect(find.byType(TermsViewerScreen), findsNothing);
      out('⑧ 3회(해제) states=${states()}');
      for (final i in kItems) {
        expect(agreedOf(i.title), isFalse, reason: '${i.id} 해제');
      }
      FlutterError.onError = prev;
      out('overflows(${overflows.length})=${overflows.join(' | ')}');
      expect(overflows, isEmpty, reason: overflows.join(' | '));
      expect(t.takeException(), isNull);
    });
  }
}
