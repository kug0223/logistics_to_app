// ignore_for_file: depend_on_referenced_packages
// [DU1 C0 S004] 기본가입 지원자 약관 단계(2단계) — 약관 읽기 상태별 실제 위젯 LOCAL 렌더.
//   seam: RegisterScreen.termsLoaderForTest(약관 읽기 교체) · initialUserTermsStepForTest(약관 단계에서 화면만 연다).
//   본인인증·가입 writer·서버 동의 기록은 부르지 않는다(가입 완료 버튼을 누르지 않는다).
//   TS-1 로딩 중 · TS-2 실패 → 문구·'다시 시도' → 다시 시도로 정상 · TS-3 불완전(필수 0) · TS-4 정상 목록·전체 동의
//   각 상태를 320×640@2.0 에서 스크롤로 도달, 넘침 0.
import 'dart:async';

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

LegalTermsItem _item(String id, String title, bool required_) => LegalTermsItem(
      id: id, title: title, content: '$title 본문입니다.\n' * 3, isRequired: required_,
      version: 'b', revisionId: '${id}__b', order: 1);

EffectiveLegalTerms _terms(List<LegalTermsItem> items) =>
    EffectiveLegalTerms(serverNow: DateTime.utc(2026, 11, 1), upcoming: const [], items: items);

// [DU1 구현154] scale · boundaryKey 는 TS-4-N / B 캡처용 선택 인자다. 기본(2.0 · null)은 TS-1~3 의 기존 렌더와 같다.
Future<void> _pump(WidgetTester t, Future<EffectiveLegalTerms> Function() loader,
    {double scale = 2.0, GlobalKey? boundaryKey}) async {
  t.view.physicalSize = const Size(320, 640);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  final app = MaterialApp(
    debugShowCheckedModeBanner: boundaryKey == null,
    theme: RoleTheme.workerTheme,
    builder: (ctx, child) => MediaQuery(
        data: boundaryKey == null
            ? MediaQuery.of(ctx).copyWith(textScaler: TextScaler.linear(scale))
            : MediaQuery.of(ctx).copyWith(
                textScaler: TextScaler.linear(scale),
                padding: EdgeInsets.zero,
                viewPadding: EdgeInsets.zero,
                viewInsets: EdgeInsets.zero),
        child: child!),
    home: RegisterScreen(termsLoaderForTest: loader, initialUserTermsStepForTest: true),
  );
  await t.pumpWidget(ChangeNotifierProvider<UserProvider>(
    create: (_) => UserProvider(),
    child: boundaryKey == null ? app : RepaintBoundary(key: boundaryKey, child: app),
  ));
  for (var i = 0; i < 8; i++) {
    await t.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _scrollTo(WidgetTester t, Finder f) async {
  await t.scrollUntilVisible(f, 150, scrollable: find.byType(Scrollable).first, maxScrolls: 60);
  await t.pump(const Duration(milliseconds: 50));
  final r = t.getRect(f);
  expect(r.left >= 0 && r.right <= 320, isTrue, reason: '가로 화면 안 $r');
}

void main() {
  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
  });

  testWidgets('TS-1 로딩 중 — 약관 단계에 진행 표시', (t) async {
    final c = Completer<EffectiveLegalTerms>();
    await _pump(t, () => c.future);
    expect(findVisibleText('일자리 시작 설정'), findsOneWidget, reason: '지원자 약관 단계');
    final spinner = find.byType(CircularProgressIndicator);
    await _scrollTo(t, spinner.last);
    expect(spinner, findsWidgets);
    c.complete(_terms([_item('service_terms', '서비스 이용약관', true)]));
    await t.pump(const Duration(milliseconds: 100));
    await t.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('TS-2 실패 → 문구·다시 시도 → 다시 시도로 정상', (t) async {
    var calls = 0;
    await _pump(t, () async {
      calls++;
      if (calls == 1) throw Exception('network');
      return _terms([_item('service_terms', '서비스 이용약관', true), _item('marketing', '마케팅 수신', false)]);
    });
    final msg = findVisibleTextContaining('약관을 불러오지 못했어요');
    await _scrollTo(t, msg);
    expect(msg, findsOneWidget);
    expect(findVisibleTextContaining('전체 동의'), findsNothing, reason: '못 읽었으면 동의 체크를 그리지 않는다');
    final retry = find.widgetWithText(TextButton, '다시 시도').evaluate().isNotEmpty
        ? find.widgetWithText(TextButton, '다시 시도')
        : find.ancestor(of: findVisibleText('다시 시도'), matching: find.byWidgetPredicate((w) => w is ButtonStyleButton)).first;
    await _scrollTo(t, retry);
    await t.tap(retry);
    for (var i = 0; i < 8; i++) {
      await t.pump(const Duration(milliseconds: 50));
    }
    expect(calls, 2);
    final all = findVisibleTextContaining('전체 동의');
    await _scrollTo(t, all);
    expect(all, findsOneWidget);
    expect(findVisibleTextContaining('서비스 이용약관'), findsWidgets);
    expect(t.takeException(), isNull);
  });

  testWidgets('TS-3 불완전(필수 항목 0) — 불완전 문구, 동의 체크 없음', (t) async {
    await _pump(t, () async => _terms([_item('marketing', '마케팅 수신', false)]));
    final msg = findVisibleTextContaining('약관 정보가 완전하지 않습니다');
    await _scrollTo(t, msg);
    expect(msg, findsOneWidget);
    expect(findVisibleTextContaining('전체 동의'), findsNothing);
    expect(t.takeException(), isNull);
  });

  // [DU1 구현154 · 후속154 §2] TS-4 를 N(320×640@1) · B(320×640@2) 로 나눠, 세 항목의 배지를 제목 행과 연결해 찾고
  //   유한 도달(scrollUntilVisible 최대 60) → 50ms×최대20 3표본 안정 → hold 1 → 배지 완전 표시 확인 뒤 항목마다 1장 캡처한다.
  //   보기 · 체크 · 전체 동의 · 다음 · 가입 버튼은 누르지 않는다(순수 렌더 · 스크롤). 기존 seam · 자료 그대로.
  for (final c in const [(id: 'TS-4-N', s: 1.0), (id: 'TS-4-B', s: 2.0)]) {
    testWidgets('${c.id} 정상 — 필수·선택 항목과 전체 동의 320×640@${c.s}', (t) async {
      SharedPreferences.setMockInitialValues({});
      await t.runAsync(vqLoadFonts);
      final key = GlobalKey();
      await _pump(t, () async => _terms([
            _item('service_terms', '서비스 이용약관', true),
            _item('privacy', '개인정보 수집·이용 동의(아주 긴 제목 예시)', true),
            _item('marketing', '마케팅 수신', false),
          ]), scale: c.s, boundaryKey: key);
      void out(String l) {
        // ignore: avoid_print
        print(l);
      }
      final mq = MediaQuery.of(t.element(find.byType(RegisterScreen)));
      out('${c.id} screenMQ textScaler=${mq.textScaler} padding=${mq.padding} viewPadding=${mq.viewPadding} viewInsets=${mq.viewInsets} · physical ${t.view.padding.top},${t.view.padding.bottom},${t.view.viewInsets.bottom}');
      final all = findVisibleTextContaining('전체 동의');
      await _scrollTo(t, all);
      final sc = find.byType(Scrollable).first;
      final pos0 = t.state<ScrollableState>(sc).position;
      String raw(Rect r) => 'LTRB(${r.left}, ${r.top}, ${r.right}, ${r.bottom})';
      double spread(List<List<double>> w) {
        var s = 0.0;
        for (var k = 0; k < w[0].length; k++) {
          var hi = w[0][k];
          var lo = w[0][k];
          for (final v in w) {
            if (v[k] > hi) hi = v[k];
            if (v[k] < lo) lo = v[k];
          }
          if (hi - lo > s) s = hi - lo;
        }
        return s;
      }
      var n = 0;
      for (final it in const [
        (id: 'service_terms', title: '서비스 이용약관', req: true),
        (id: 'privacy', title: '개인정보 수집·이용 동의(아주 긴 제목 예시)', req: true),
        (id: 'marketing', title: '마케팅 수신', req: false),
      ]) {
        n++;
        final label = findVisibleText(it.title);
        await t.scrollUntilVisible(label, 150, scrollable: sc, maxScrolls: 60);
        expect(label, findsOneWidget, reason: '${it.id} 제목 Text 하나');
        // [DU1 구현159 · 후속159 §3] 제목의 가장 가까운 Row 는 이제 선택 영역 안쪽 Row 다. 제목 · 체크 · 배지와 별도 보기 TextButton 을
        //   함께 품는 조상 Row 만 남겨 정확히 1개임을 단언하고 그것을 외곽 Row 로 쓴다(.first 안쪽 Row · 임의 .last 금지).
        final rowAnc = find.ancestor(of: label, matching: find.byType(Row)).evaluate().toList();
        final rowEls = rowAnc.where((e) {
          final f = find.byElementPredicate((x) => identical(x, e));
          return find.descendant(of: f, matching: find.byType(TextButton)).evaluate().length == 1 &&
              find.descendant(of: f, matching: find.byIcon(Icons.check_circle_outline)).evaluate().length == 1 &&
              find.descendant(of: f, matching: find.text(it.req ? '필수' : '선택')).evaluate().length == 1;
        }).toList();
        expect(rowEls.length, 1, reason: '${it.id} 외곽 Row(제목·체크·배지·보기) 하나');
        final row = find.byElementPredicate((x) => identical(x, rowEls.single));
        out('${c.id} ${it.id} rowLink rowAncestors=${rowAnc.length} outerIndex=${rowAnc.indexOf(rowEls.single)} (0=가장 가까운)');
        final badgeText = find.descendant(of: row, matching: find.text(it.req ? '필수' : '선택'));
        expect(badgeText, findsOneWidget, reason: '${it.id} 행 안 배지 하나');
        final badgeBox = find.ancestor(of: badgeText, matching: find.byType(Container)).first;
        List<double> nums() {
          final p = t.state<ScrollableState>(sc).position;
          final rs = <Rect>[t.getRect(badgeBox), t.getRect(badgeText), t.getRect(label), t.getRect(row), t.getRect(sc)];
          return <double>[
            p.pixels, p.minScrollExtent, p.maxScrollExtent, p.viewportDimension, p.extentBefore, p.extentAfter,
            for (final r in rs) ...<double>[r.left, r.top, r.right, r.bottom],
          ];
        }
        bool flags() {
          final p = t.state<ScrollableState>(sc).position;
          return identical(p, pos0) && p.hasContentDimensions && !p.outOfRange && !p.isScrollingNotifier.value;
        }
        final samples = <List<double>>[];
        final oks = <bool>[];
        var stableAt = 0;
        for (var i = 1; i <= 20; i++) {
          await t.pump(const Duration(milliseconds: 50));
          final v = nums();
          samples.add(v);
          oks.add(flags() && v.every((x) => x.isFinite));
          if (samples.length >= 3 &&
              oks.sublist(oks.length - 3).every((f) => f) &&
              spread(samples.sublist(samples.length - 3)) <= 0.1) {
            stableAt = i;
            break;
          }
        }
        expect(stableAt, greaterThan(0), reason: '${it.id} 50ms×20 안에 안정 창 없음');
        await t.pump(const Duration(milliseconds: 50));
        final held = nums();
        expect(flags() && held.every((x) => x.isFinite) && spread([samples.last, held]) <= 0.1, isTrue, reason: '${it.id} hold 실패');
        final bb = t.getRect(badgeBox);
        final vp = t.getRect(sc);
        expect(bb.top >= vp.top - 0.5 && bb.bottom <= vp.bottom + 0.5 && bb.left >= 0 && bb.right <= 320, isTrue,
            reason: '${it.id} 배지 완전 표시 $bb / $vp');
        final para = t.renderObject<RenderParagraph>(find.descendant(of: label, matching: find.byType(RichText), matchRoot: true).first) /* [DU365] 제목 KeepWordsText(Semantics 로 감싼 RichText) 추종 */;
        final len = para.text.toPlainText().length;
        final lines = para.getBoxesForSelection(TextSelection(baseOffset: 0, extentOffset: len)).map((b) => b.top.round()).toSet().length;
        final pp = t.state<ScrollableState>(sc).position;
        out('${c.id} ${it.id} samples=${samples.length} stableWindow=#${stableAt - 2}~#$stableAt pixels=${pp.pixels} min=${pp.minScrollExtent} max=${pp.maxScrollExtent} '
            'viewportDimension=${pp.viewportDimension} extentBefore=${pp.extentBefore} extentAfter=${pp.extentAfter} outOfRange=${pp.outOfRange} isScrolling=${pp.isScrollingNotifier.value} '
            'badgeBox=${raw(bb)} badgeText=${raw(t.getRect(badgeText))} label=${raw(t.getRect(label))} labelLines=$lines row=${raw(t.getRect(row))} viewport=${raw(vp)}');
        // [DU1 구현159 · 후속159 §3] 단일 선택 대상 교정 확인(구현158 관측 블록 보완) — tap 0 · performAction 0 · 포인터 이벤트 dispatch 0 · 콜백 직접 호출 0.
        //   state 는 fixture 초기값(무탭 경로) 기재이지 측정이 아니다. 렌더 근거는 outline 아이콘과 semantics checked 값이다.
        String idn(Object o) => '${o.runtimeType}#${identityHashCode(o).toRadixString(16)}';
        String esc(String s) => s.replaceAll('\n', r'\n');
        final checkIcon = find.descendant(of: row, matching: find.byIcon(Icons.check_circle_outline));
        expect(checkIcon, findsOneWidget, reason: '${it.id} 체크 아이콘 하나');
        final selInk = find.ancestor(of: checkIcon, matching: find.byType(InkWell)).first;
        final titleInk = find.ancestor(of: label, matching: find.byType(InkWell)).first;
        final badgeInk = find.ancestor(of: badgeText, matching: find.byType(InkWell)).first;
        final viewBtn = find.descendant(of: row, matching: find.byType(TextButton));
        expect(viewBtn, findsOneWidget, reason: '${it.id} 보기 버튼 하나');
        final viewInk = find.descendant(of: viewBtn, matching: find.byType(InkWell));
        expect(viewInk, findsOneWidget, reason: '${it.id} 보기 InkWell 하나');
        final selEl = t.element(selInk);
        expect(identical(selEl, t.element(titleInk)) && identical(selEl, t.element(badgeInk)), isTrue, reason: '${it.id} 체크·배지·제목 = 같은 InkWell Element');
        expect(identical(selEl, t.element(viewInk)), isFalse, reason: '${it.id} 보기는 다른 InkWell');
        expect(find.descendant(of: selInk, matching: find.byType(TextButton)), findsNothing, reason: '${it.id} 보기는 선택 영역 밖 형제');
        final selLs = find.descendant(of: selInk, matching: find.byType(Listener));
        final titleLs = find.descendant(of: titleInk, matching: find.byType(Listener));
        final viewLs = find.descendant(of: viewBtn, matching: find.byType(Listener));
        final lsN = [selLs.evaluate().length, titleLs.evaluate().length, viewLs.evaluate().length];
        expect(lsN, [1, 1, 1], reason: '${it.id} Listener 각 1');
        final selRO = t.renderObject(selLs.first);
        final titleRO = t.renderObject(titleLs.first);
        final viewRO = t.renderObject(viewLs.first);
        expect(identical(selRO, titleRO) && !identical(selRO, viewRO), isTrue, reason: '${it.id} 같은 RenderPointerListener · 보기는 다른 객체');
        final sR = t.getRect(selInk);
        final iR = t.getRect(checkIcon);
        final bR = t.getRect(badgeBox);
        final lR = t.getRect(label);
        final vR = t.getRect(viewBtn);
        out('${c.id} ${it.id} probe vqEnabled=$vqEnabled state=fixture 초기값(무탭 · 기재, 측정 아님) icon=check_circle_outline listeners sel=${lsN[0]} title=${lsN[1]} view=${lsN[2]} '
            'sameInk(check,badge,title)=true viewInkSame=false selRO=${idn(selRO)} viewRO=${idn(viewRO)}');
        out('${c.id} ${it.id} probe rect(전역 logical · view 좌상단) sel=${raw(sR)} icon=${raw(iR)} badgeBox=${raw(bR)} label=${raw(lR)} view=${raw(vR)} row=${raw(t.getRect(row))} viewport=${raw(t.getRect(sc))} '
            'selSize=${sR.width}x${sR.height} viewSize=${vR.width}x${vR.height} selRight-viewLeft=${sR.right - vR.left}');
        expect(sR.width >= 48 && sR.height >= 48 && vR.width >= 48 && vR.height >= 48, isTrue, reason: '${it.id} 선택 영역 · 보기 최소 48 $sR / $vR');
        final cc = sR.center;
        final vc = vR.center;
        final pts = <(String, Offset, bool, bool)>[
          ('center', cc, true, false),
          ('left+0.5', Offset(sR.left + 0.5, cc.dy), true, false), ('left-0.5', Offset(sR.left - 0.5, cc.dy), false, false),
          ('right-0.5', Offset(sR.right - 0.5, cc.dy), true, false), ('right+0.5', Offset(sR.right + 0.5, cc.dy), false, true),
          ('top+0.5', Offset(cc.dx, sR.top + 0.5), true, false), ('top-0.5', Offset(cc.dx, sR.top - 0.5), false, false),
          ('bottom-0.5', Offset(cc.dx, sR.bottom - 0.5), true, false), ('bottom+0.5', Offset(cc.dx, sR.bottom + 0.5), false, false),
          ('c-23.5x', Offset(cc.dx - 23.5, cc.dy), true, false), ('c+23.5x', Offset(cc.dx + 23.5, cc.dy), true, false),
          ('c-23.5y', Offset(cc.dx, cc.dy - 23.5), true, false), ('c+23.5y', Offset(cc.dx, cc.dy + 23.5), true, false),
          ('icon', iR.center, true, false), ('badge', bR.center, true, false),
          ('gap8', Offset((iR.right + bR.left) / 2, iR.center.dy), true, false),
          ('gap6', Offset((bR.right + lR.left) / 2, bR.center.dy), true, false),
          ('title', lR.center, true, false), ('view', vc, false, true),
          ('shared-0.5', Offset(sR.right - 0.5, vc.dy), true, false), ('shared+0.5', Offset(sR.right + 0.5, vc.dy), false, true),
        ];
        var c48 = 0;
        for (final s in pts) {
          final hr = t.hitTestOnBinding(s.$2);
          bool has(RenderObject ro) => hr.path.any((e) => identical(e.target, ro));
          String tf(RenderObject ro) {
            final es = hr.path.where((e) => identical(e.target, ro));
            return es.isEmpty ? '-' : '${es.first.transform?.storage.toList()}';
          }
          final sel = has(selRO);
          final view = has(viewRO);
          out('${c.id} ${it.id} probe hit ${s.$1} at=(${s.$2.dx}, ${s.$2.dy}) sel=$sel title=${has(titleRO)} view=$view expect=${s.$3}/${s.$4} pathLen=${hr.path.length} selT=${tf(selRO)} viewT=${tf(viewRO)}');
          out('    path ${hr.path.map((e) => idn(e.target)).join(' > ')}');
          expect(sel == s.$3 && view == s.$4, isTrue, reason: '${it.id} hit ${s.$1} sel=$sel view=$view');
          if (s.$1.startsWith('c-23.5') || s.$1.startsWith('c+23.5')) c48 += sel ? 1 : 0;
        }
        expect(c48, 4, reason: '${it.id} 중심 48 표본 4/4');
        final sem = <String, SemanticsNode>{
          for (final e in <(String, Finder)>[('check', checkIcon), ('badge', badgeText), ('title', label), ('sel', selInk), ('view', viewBtn)])
            e.$1: t.getSemantics(e.$2),
        };
        final m = sem['sel']!;
        final v = sem['view']!;
        out('${c.id} ${it.id} probe sem ids check=${sem['check']!.id} badge=${sem['badge']!.id} title=${sem['title']!.id} sel=${m.id} view=${v.id}');
        expect(sem['check']!.id == m.id && sem['badge']!.id == m.id && sem['title']!.id == m.id && v.id != m.id, isTrue, reason: '${it.id} 병합 노드 하나 · 보기 별도');
        final md = m.getSemanticsData();
        final vd = v.getSemanticsData();
        final badge = it.req ? '필수' : '선택';
        int cnt(String s, String p) => p.allMatches(s).length;
        final nameOk = RegExp('^$badge[\n ]+${RegExp.escape(it.title)}\$').hasMatch(md.label) &&
            cnt(md.label, badge) == 1 && cnt(md.label, it.title) == 1 && !md.label.contains('보기') && !md.label.contains('*');
        String acts(SemanticsData d) => SemanticsAction.values.where(d.hasAction).map((a) => a.name).join(',');
        Rect inTo(SemanticsNode n, SemanticsNode? top) {
          var mx = Matrix4.identity();
          for (SemanticsNode? k = n; k != null && !identical(k, top); k = k.parent) {
            if (k.transform != null) mx = k.transform!.multiplied(mx);
          }
          return MatrixUtils.transformRect(mx, n.rect);
        }
        out('${c.id} ${it.id} probe sem merged label="${esc(md.label)}" nameOk=$nameOk hasCheckedState=${md.flagsCollection.hasCheckedState} isChecked=${md.flagsCollection.isChecked} '
            'actions=${acts(md)} flags=${md.flagsCollection.toStrings()} mergeAll=${m.mergeAllDescendantsIntoThisNode} children=${m.childrenCount} rect=${m.rect} global=${inTo(m, null)} sel=${raw(sR)}');
        out('${c.id} ${it.id} probe sem view label="${esc(vd.label)}" actions=${acts(vd)} flags=${vd.flagsCollection.toStrings()} mergeAll=${v.mergeAllDescendantsIntoThisNode} children=${v.childrenCount} rect=${v.rect} global=${inTo(v, null)} view=${raw(vR)}');
        expect(nameOk, isTrue, reason: '${it.id} 병합 이름 ${esc(md.label)}');
        expect(md.flagsCollection.hasCheckedState && !md.flagsCollection.isChecked && md.hasAction(SemanticsAction.tap), isTrue, reason: '${it.id} checked 의미 · tap');
        final par = m.parent!;
        final rowP = inTo(m, par).expandToInclude(inTo(v, par));
        final taps = <String>[];
        void walk(SemanticsNode p) {
          p.visitChildren((k) {
            if (k.getSemanticsData().hasAction(SemanticsAction.tap) && rowP.inflate(0.5).contains(inTo(k, par).center)) taps.add('${k.id}');
            walk(k);
            return true;
          });
        }
        walk(par);
        out('${c.id} ${it.id} probe sem rowTaps parent=${par.id} viewParent=${v.parent?.id} rowInParent=$rowP taps=$taps');
        expect(taps.length == 2 && taps.toSet().containsAll(['${m.id}', '${v.id}']), isTrue, reason: '${it.id} 행 독립 tap 대상 = 병합 1 + 보기 1 $taps');
        for (SemanticsNode? k = m; k != null; k = k.parent) {
          final d = k.getSemanticsData();
          out('    chain id=${k.id} rect=${k.rect} transform=${k.transform?.storage.toList()} flags=${d.flagsCollection.toStrings()} actions=${acts(d)} label="${esc(d.label)}"');
        }
        out(m.toStringDeep().split('\n').map((l) => '    | $l').join('\n'));
        out(v.toStringDeep().split('\n').map((l) => '    V| $l').join('\n'));
        if (n == 1) out(par.toStringDeep().split('\n').map((l) => '    P| $l').join('\n'));
        await vqCapture(t, key, '${c.id}_${n}_${it.id}', conditions: {
          'screen': 'RegisterScreen (production) · termsLoaderForTest · initialUserTermsStepForTest',
          'role': 'USER 약관 단계(2)', 'theme': 'RoleTheme.workerTheme',
          'viewport': '320x640', 'dpr': 1.0, 'textScaler': c.s,
          'mq': 'padding=${mq.padding} viewPadding=${mq.viewPadding} viewInsets=${mq.viewInsets}', 'keyboard': '닫힘(inset 0)',
          'fonts': 'vqLoadFonts: NotoSansKR Regular+Bold · Roboto=NotoSansKR · MaterialIcons(SDK) · FlutterTest 미등록',
          'data': '약관 3: service_terms 필수 · privacy 필수(긴 제목) · marketing 선택 · version b · serverNow 2026-11-01Z',
          'prefs': 'setMockInitialValues({})', 'clock': '미주입',
          'state': '${it.id} 행 도달 · 정착 확인 후 캡처', 'badge': it.req ? '필수' : '선택'});
        final after = nums();
        expect(flags() && after.every((x) => x.isFinite) && spread([held, after]) <= 0.1, isTrue, reason: '${it.id} 캡처 전후 유지 실패');
      }
      expect(t.takeException(), isNull);
    });
  }

  // [DU1 구현160 · 후속160] TS-5-N / B — 긴 privacy(필수) 한 항목의 실제 동작. 명시 tap 6 / 배율:
  //   ① unread 배지 tapAt → viewer ② 헤더 X(null) ③ gap8 tapAt → true ④ 제목 tapAt → false ⑤ 별도 다시보기 → viewer ⑥ 동의하고 닫기 → true.
  //   복귀 4상태(②③④⑥ 뒤)마다 정착 · 의미 · 이웃 확인 뒤 PNG 1장. performAction · callback 직접 호출 · Navigator 직접 pop 0.
  //   viewer CTA 가 비활성일 때만 viewer Scrollable jumpTo(끝) 1회(포인터 이벤트 아님). register 도달은 기존 scrollUntilVisible(drag) + ensureVisible.
  for (final c in const [(id: 'TS-5-N', s: 1.0), (id: 'TS-5-B', s: 2.0)]) {
    testWidgets('${c.id} 동작 — privacy 배지→viewer→X→gap8 true→제목 false→다시보기→동의 true 320×640@${c.s}', (t) async {
      SharedPreferences.setMockInitialValues({});
      await t.runAsync(vqLoadFonts);
      final key = GlobalKey();
      const items = [
        (id: 'service_terms', title: '서비스 이용약관', req: true),
        (id: 'privacy', title: '개인정보 수집·이용 동의(아주 긴 제목 예시)', req: true),
        (id: 'marketing', title: '마케팅 수신', req: false),
      ];
      final tt = items[1].title;
      await _pump(t, () async => _terms([for (final i in items) _item(i.id, i.title, i.req)]), scale: c.s, boundaryKey: key);
      void out(String l) {
        // ignore: avoid_print
        print(l);
      }
      String raw(Rect r) => 'LTRB(${r.left}, ${r.top}, ${r.right}, ${r.bottom})';
      String idn(Object o) => '${o.runtimeType}#${identityHashCode(o).toRadixString(16)}';
      String esc(String s) => s.replaceAll('\n', r'\n');
      double spread(List<List<double>> w) {
        var s = 0.0;
        for (var k = 0; k < w[0].length; k++) {
          var hi = w[0][k];
          var lo = w[0][k];
          for (final v in w) {
            if (v[k] > hi) hi = v[k];
            if (v[k] < lo) lo = v[k];
          }
          if (hi - lo > s) s = hi - lo;
        }
        return s;
      }
      final mq = MediaQuery.of(t.element(find.byType(RegisterScreen)));
      out('${c.id} screenMQ textScaler=${mq.textScaler} padding=${mq.padding} viewPadding=${mq.viewPadding} viewInsets=${mq.viewInsets}');
      await _scrollTo(t, findVisibleTextContaining('전체 동의'));
      final sc = find.byType(Scrollable).first;
      final pos0 = t.state<ScrollableState>(sc).position;
      final viewer = find.byType(TermsViewerScreen);
      final checkIco = find.byWidgetPredicate((w) => w is Icon && (w.icon == Icons.check_circle || w.icon == Icons.check_circle_outline));
      Finder rowOf(String title, bool req) {
        final els = find.ancestor(of: findVisibleText(title), matching: find.byType(Row)).evaluate().where((e) {
          final f = find.byElementPredicate((x) => identical(x, e));
          int cnt(Finder m) => find.descendant(of: f, matching: m).evaluate().length;
          return cnt(findVisibleText(title)) == 1 && cnt(find.byType(TextButton)) == 1 && cnt(checkIco) == 1 && cnt(find.text(req ? '필수' : '선택')) == 1;
        }).toList();
        expect(els.length, 1, reason: '$title 외곽 Row(제목·체크·배지·보기) 하나');
        return find.byElementPredicate((x) => identical(x, els.single));
      }
      ({String icon, String view, String sem}) rowState(String title, bool req) {
        final row = rowOf(title, req);
        final ico = t.widget<Icon>(find.descendant(of: row, matching: checkIco));
        final vb = find.descendant(of: row, matching: find.byType(TextButton));
        final vt = visibleText(t.widget<Text>(find.descendant(of: vb, matching: find.byType(Text))).data ?? '');
        final node = t.getSemantics(find.descendant(of: row, matching: checkIco));
        final d = node.getSemanticsData();
        final own = d.label.contains(title);
        final sem = !own ? '행노드아님#${node.id}' : (d.flagsCollection.hasCheckedState ? '${d.flagsCollection.isChecked}' : 'none');
        return (icon: ico.icon == Icons.check_circle ? 'filled' : 'outline', view: vt, sem: sem);
      }
      void neighbors(String tag) {
        for (final i in [items[0], items[2]]) {
          final s = rowState(i.title, i.req);
          out('$tag neighbor ${i.id} icon=${s.icon} view=${s.view} semChecked=${s.sem}');
          expect(s.icon == 'outline' && s.view == '보기' && (s.sem == 'false' || s.sem.startsWith('행노드아님')), isTrue, reason: '$tag 이웃 ${i.id} 불변 $s');
        }
      }
      Future<void> waitFor(String tag, bool Function() done) async {
        var i = 0;
        var idle = false;
        while (i < 60) {
          await t.pump(const Duration(milliseconds: 50));
          i++;
          if (done() && !t.binding.hasScheduledFrame) {
            idle = true;
            break;
          }
        }
        out('$tag wait pumps=$i done=${done()} idle=$idle viewer=${viewer.evaluate().length}');
        expect(done(), isTrue, reason: '$tag 대기 조건');
      }
      // 상태마다: 제목 유한 도달 + ensureVisible → TS-4 와 같은 26성분 3표본 안정 · hold · 완전 표시. viewer 위에서는 부르지 않는다.
      Future<(List<double> Function(), bool Function(), List<double>)> settle(String tag) async {
        expect(viewer, findsNothing, reason: '$tag viewer 없음에서만 측정');
        final label = findVisibleText(tt);
        await t.scrollUntilVisible(label, 150, scrollable: sc, maxScrolls: 60);
        expect(label, findsOneWidget, reason: '$tag 제목 Text 하나');
        await t.ensureVisible(rowOf(tt, true));
        final row = rowOf(tt, true);
        final badgeText = find.descendant(of: row, matching: find.text('필수'));
        expect(badgeText, findsOneWidget, reason: '$tag 배지 하나');
        final badgeBox = find.ancestor(of: badgeText, matching: find.byType(Container)).first;
        final vb = find.descendant(of: row, matching: find.byType(TextButton));
        List<double> nums() {
          final p = t.state<ScrollableState>(sc).position;
          final rs = <Rect>[t.getRect(badgeBox), t.getRect(badgeText), t.getRect(label), t.getRect(row), t.getRect(sc)];
          return <double>[
            p.pixels, p.minScrollExtent, p.maxScrollExtent, p.viewportDimension, p.extentBefore, p.extentAfter,
            for (final r in rs) ...<double>[r.left, r.top, r.right, r.bottom],
          ];
        }
        bool flags() {
          final p = t.state<ScrollableState>(sc).position;
          return identical(p, pos0) && p.hasContentDimensions && !p.outOfRange && !p.isScrollingNotifier.value;
        }
        final samples = <List<double>>[];
        final oks = <bool>[];
        var stableAt = 0;
        for (var i = 1; i <= 20; i++) {
          await t.pump(const Duration(milliseconds: 50));
          final v = nums();
          samples.add(v);
          oks.add(flags() && v.every((x) => x.isFinite));
          if (samples.length >= 3 && oks.sublist(oks.length - 3).every((f) => f) && spread(samples.sublist(samples.length - 3)) <= 0.1) {
            stableAt = i;
            break;
          }
        }
        expect(stableAt, greaterThan(0), reason: '$tag 50ms×20 안에 안정 창 없음');
        await t.pump(const Duration(milliseconds: 50));
        final held = nums();
        expect(flags() && held.every((x) => x.isFinite) && spread([samples.last, held]) <= 0.1, isTrue, reason: '$tag hold 실패');
        final vp = t.getRect(sc);
        bool inside(Rect r) => r.top >= vp.top - 0.5 && r.bottom <= vp.bottom + 0.5 && r.left >= 0 && r.right <= 320;
        expect(inside(t.getRect(badgeBox)) && inside(t.getRect(label)) && inside(t.getRect(vb)), isTrue, reason: '$tag 배지 · 제목 · 보기 완전 표시');
        final para = t.renderObject<RenderParagraph>(find.descendant(of: label, matching: find.byType(RichText), matchRoot: true).first) /* [DU365] 제목 KeepWordsText(Semantics 로 감싼 RichText) 추종 */;
        final lines = para.getBoxesForSelection(TextSelection(baseOffset: 0, extentOffset: para.text.toPlainText().length)).map((b) => b.top.round()).toSet().length;
        final pp = t.state<ScrollableState>(sc).position;
        out('$tag samples=${samples.length} stableWindow=#${stableAt - 2}~#$stableAt pixels=${pp.pixels} min=${pp.minScrollExtent} max=${pp.maxScrollExtent} '
            'viewportDimension=${pp.viewportDimension} extentBefore=${pp.extentBefore} extentAfter=${pp.extentAfter} outOfRange=${pp.outOfRange} isScrolling=${pp.isScrollingNotifier.value} '
            'badgeBox=${raw(t.getRect(badgeBox))} badgeText=${raw(t.getRect(badgeText))} label=${raw(t.getRect(label))} labelLines=$lines row=${raw(t.getRect(row))} view=${raw(t.getRect(vb))} viewport=${raw(vp)}');
        return (nums, flags, held);
      }
      String acts(SemanticsData d) => SemanticsAction.values.where(d.hasAction).map((a) => a.name).join(',');
      Rect inTo(SemanticsNode n, SemanticsNode? top) {
        var mx = Matrix4.identity();
        for (SemanticsNode? k = n; k != null && !identical(k, top); k = k.parent) {
          if (k.transform != null) mx = k.transform!.multiplied(mx);
        }
        return MatrixUtils.transformRect(mx, n.rect);
      }
      const tol = 0.01;
      bool near(Rect a, Rect b) =>
          (a.left - b.left).abs() <= tol && (a.top - b.top).abs() <= tol && (a.right - b.right).abs() <= tol && (a.bottom - b.bottom).abs() <= tol;
      // 대상 행의 대상 연결 · 최소 48 · 의미(같은 id · 이름 · checked 기대값 · tap) · raw rect · chain · 행 action · 이웃.
      void inspect(String tag, bool exp, String expView) {
        final row = rowOf(tt, true);
        final ico = find.descendant(of: row, matching: checkIco);
        final label = findVisibleText(tt);
        final badgeText = find.descendant(of: row, matching: find.text('필수'));
        final selInk = find.ancestor(of: ico, matching: find.byType(InkWell)).first;
        final viewBtn = find.descendant(of: row, matching: find.byType(TextButton));
        final selEl = t.element(selInk);
        expect(identical(selEl, t.element(find.ancestor(of: label, matching: find.byType(InkWell)).first)) &&
            identical(selEl, t.element(find.ancestor(of: badgeText, matching: find.byType(InkWell)).first)), isTrue, reason: '$tag 같은 InkWell');
        expect(find.descendant(of: selInk, matching: find.byType(TextButton)), findsNothing, reason: '$tag 보기는 선택 영역 밖');
        final sR = t.getRect(selInk);
        final vR = t.getRect(viewBtn);
        final icon = t.widget<Icon>(ico).icon == Icons.check_circle ? 'filled' : 'outline';
        final vt = visibleText(t.widget<Text>(find.descendant(of: viewBtn, matching: find.byType(Text))).data ?? '');
        out('$tag target icon=$icon view=$vt sel=${raw(sR)} viewBtn=${raw(vR)} row=${raw(t.getRect(row))} selSize=${sR.width}x${sR.height} viewSize=${vR.width}x${vR.height} selRight-viewLeft=${sR.right - vR.left}');
        expect(sR.width >= 48 && sR.height >= 48 && vR.width >= 48 && vR.height >= 48, isTrue, reason: '$tag 최소 48');
        expect(icon == (exp ? 'filled' : 'outline') && vt == expView, isTrue, reason: '$tag 렌더 상태 icon=$icon view=$vt');
        final sem = <String, SemanticsNode>{
          for (final e in <(String, Finder)>[('check', ico), ('badge', badgeText), ('title', label), ('sel', selInk), ('view', viewBtn)])
            e.$1: t.getSemantics(e.$2),
        };
        final m = sem['sel']!;
        final v = sem['view']!;
        final md = m.getSemanticsData();
        final vd = v.getSemanticsData();
        int cnt(String s, String p) => p.allMatches(s).length;
        final nameOk = RegExp('^필수[\n ]+${RegExp.escape(tt)}\$').hasMatch(md.label) &&
            cnt(md.label, '필수') == 1 && cnt(md.label, tt) == 1 && !md.label.contains('보기') && !md.label.contains('*');
        final mg = inTo(m, null);
        final vg = inTo(v, null);
        out('$tag sem ids check=${sem['check']!.id} badge=${sem['badge']!.id} title=${sem['title']!.id} sel=${m.id} view=${v.id} parent=${m.parent?.id} viewParent=${v.parent?.id}');
        out('$tag sem merged label="${esc(md.label)}" nameOk=$nameOk hasCheckedState=${md.flagsCollection.hasCheckedState} isChecked=${md.flagsCollection.isChecked} actions=${acts(md)} '
            'flags=${md.flagsCollection.toStrings()} local=${raw(m.rect)} transform=${m.transform?.storage.toList()} global=${raw(mg)} widgetSel=${raw(sR)} near=${near(mg, sR)}');
        out('$tag sem view label="${esc(vd.label)}" actions=${acts(vd)} flags=${vd.flagsCollection.toStrings()} local=${raw(v.rect)} transform=${v.transform?.storage.toList()} '
            'global=${raw(vg)} widgetView=${raw(vR)} near=${near(vg, vR)}');
        expect(sem['check']!.id == m.id && sem['badge']!.id == m.id && sem['title']!.id == m.id && v.id != m.id, isTrue, reason: '$tag 병합 1 · 보기 별도');
        expect(nameOk, isTrue, reason: '$tag 병합 이름 ${esc(md.label)}');
        expect(md.flagsCollection.hasCheckedState && md.flagsCollection.isChecked == exp && md.hasAction(SemanticsAction.tap), isTrue, reason: '$tag checked=$exp · tap');
        expect(vd.label == expView && vd.hasAction(SemanticsAction.tap), isTrue, reason: '$tag 보기 label ${esc(vd.label)}');
        expect(near(mg, sR) && near(vg, vR), isTrue, reason: '$tag semantics global ≈ 위젯 rect(≤$tol)');
        final par = m.parent!;
        expect(identical(v.parent, par), isTrue, reason: '$tag 병합 · 보기 같은 부모');
        final rowP = inTo(m, par).expandToInclude(inTo(v, par));
        final centerTaps = <String>[];
        final overlap = <String>[];
        void walk(SemanticsNode p, int depth) {
          p.visitChildren((k) {
            final d = k.getSemanticsData();
            final r = inTo(k, par);
            if (d.hasAction(SemanticsAction.tap) && rowP.inflate(0.5).contains(r.center)) centerTaps.add('${k.id}');
            if (d.actions != 0 && rowP.deflate(0.5).overlaps(r)) overlap.add('${k.id}:${acts(d)}');
            out('    $tag S| ${'  ' * depth}id=${k.id} local=${raw(k.rect)} inParent=${raw(r)} global=${raw(inTo(k, null))} flags=${d.flagsCollection.toStrings()} actions=${acts(d)} label="${esc(d.label)}"');
            walk(k, depth + 1);
            return true;
          });
        }
        walk(par, 0);
        out('$tag sem rowTaps parent=${par.id} rowInParent=${raw(rowP)} centerTaps=$centerTaps overlapActions=$overlap');
        expect(centerTaps.length == 2 && centerTaps.toSet().containsAll(['${m.id}', '${v.id}']), isTrue, reason: '$tag 행 tap(중심) = 병합 + 보기 $centerTaps');
        expect(overlap.length == 2 && overlap.every((s) => s.startsWith('${m.id}:') || s.startsWith('${v.id}:')), isTrue, reason: '$tag 행과 겹치는 action 노드 $overlap');
        for (final e in <(String, SemanticsNode)>[('merged', m), ('view', v)]) {
          for (SemanticsNode? k = e.$2; k != null; k = k.parent) {
            final d = k.getSemanticsData();
            out('    $tag chain ${e.$1} id=${k.id} local=${raw(k.rect)} transform=${k.transform?.storage.toList()} global=${raw(inTo(k, null))} flags=${d.flagsCollection.toStrings()} actions=${acts(d)}');
          }
        }
        out(par.toStringDeep().split('\n').map((l) => '    $tag P| $l').join('\n'));
        neighbors(tag);
      }
      ({RenderObject sel, RenderObject view, Rect icon, Rect badge, Rect title, Finder viewBtn}) targets() {
        final row = rowOf(tt, true);
        final ico = find.descendant(of: row, matching: checkIco);
        final selInk = find.ancestor(of: ico, matching: find.byType(InkWell)).first;
        final viewBtn = find.descendant(of: row, matching: find.byType(TextButton));
        final selLs = find.descendant(of: selInk, matching: find.byType(Listener));
        final viewLs = find.descendant(of: viewBtn, matching: find.byType(Listener));
        expect([selLs.evaluate().length, viewLs.evaluate().length], [1, 1], reason: 'Listener 각 1');
        final badgeBox = find.ancestor(of: find.descendant(of: row, matching: find.text('필수')), matching: find.byType(Container)).first;
        return (sel: t.renderObject(selLs.first), view: t.renderObject(viewLs.first), icon: t.getRect(ico), badge: t.getRect(badgeBox),
            title: t.getRect(findVisibleText(tt)), viewBtn: viewBtn);
      }
      var taps = 0;
      Future<void> tapLogged(String tag, Offset p, RenderObject want, RenderObject? not, String pre, Future<void> Function() act) async {
        final hr = t.hitTestOnBinding(p);
        final has = hr.path.any((e) => identical(e.target, want));
        final bad = not != null && hr.path.any((e) => identical(e.target, not));
        out('$tag pre at=(${p.dx}, ${p.dy}) viewer=${viewer.evaluate().length} $pre want=${idn(want)} inPath=$has notInPath=${!bad} pathLen=${hr.path.length}');
        out('    $tag path ${hr.path.map((e) => idn(e.target)).join(' > ')}');
        expect(has && !bad, isTrue, reason: '$tag 탭 전 hit 경로');
        await act();
        taps++;
        out('$tag tap#$taps 실행');
      }
      String regPre() {
        final s = rowState(tt, true);
        return 'target icon=${s.icon} view=${s.view} semChecked=${s.sem}';
      }
      Future<void> peek(String tag) async {
        await t.pump();
        final s = rowState(tt, true);
        out('$tag 1프레임 뒤(전환 중) target icon=${s.icon} view=${s.view} semChecked=${s.sem} viewer=${viewer.evaluate().length}');
        expect(s.icon, 'outline', reason: '$tag 탭이 동의값을 바로 쓰지 않는다');
      }
      void viewerIs(String tag) {
        expect(viewer, findsOneWidget, reason: '$tag viewer 1');
        final cta = find.descendant(of: viewer, matching: find.byType(ElevatedButton));
        out('$tag viewer item=${t.widget<TermsViewerScreen>(viewer).item.id} title=${find.descendant(of: viewer, matching: findVisibleText(tt)).evaluate().length} '
            'ctaEnabled=${t.widget<ElevatedButton>(cta).onPressed != null} rect=${raw(t.getRect(viewer))}');
        expect(t.widget<TermsViewerScreen>(viewer).item.id, 'privacy', reason: '$tag privacy viewer');
      }
      var k = 0;
      Future<void> shot(String tag, String name, String state, (List<double> Function(), bool Function(), List<double>) st) async {
        k++;
        await vqCapture(t, key, '${c.id}_${k}_$name', conditions: {
          'screen': 'RegisterScreen (production) · termsLoaderForTest · initialUserTermsStepForTest',
          'role': 'USER 약관 단계(2)', 'theme': 'RoleTheme.workerTheme', 'viewport': '320x640', 'dpr': 1.0, 'textScaler': c.s,
          'mq': 'padding=${mq.padding} viewPadding=${mq.viewPadding} viewInsets=${mq.viewInsets}', 'keyboard': '닫힘(inset 0)',
          'fonts': 'vqLoadFonts: NotoSansKR Regular+Bold · Roboto=NotoSansKR · MaterialIcons(SDK) · FlutterTest 미등록',
          'data': '약관 3: service_terms 필수 · privacy 필수(긴 제목) · marketing 선택 · version b · serverNow 2026-11-01Z',
          'prefs': 'setMockInitialValues({})', 'clock': '미주입', 'state': state, 'taps': '$taps'});
        final after = st.$1();
        expect(st.$2() && after.every((x) => x.isFinite) && spread([st.$3, after]) <= 0.1, isTrue, reason: '$tag 캡처 전후 유지 실패');
        out('$tag shot ${c.id}_${k}_$name vqEnabled=$vqEnabled taps=$taps');
      }
      // ── S0 초기(unread · 캡처 없음)
      await settle('${c.id} S0');
      inspect('${c.id} S0', false, '보기');
      // ① unread 배지 중심 tapAt → 즉시 동의 0 · privacy viewer
      var tg = targets();
      await tapLogged('${c.id} T1 badge', tg.badge.center, tg.sel, tg.view, regPre(), () => t.tapAt(tg.badge.center));
      await peek('${c.id} T1');
      await waitFor('${c.id} T1 viewer', () => viewer.evaluate().length == 1);
      viewerIs('${c.id} T1');
      // ② viewer 헤더 X → null 복귀
      final x = find.descendant(of: viewer, matching: find.byType(IconButton));
      expect(x, findsOneWidget, reason: 'viewer 헤더 X 하나');
      await tapLogged('${c.id} T2 X', t.getCenter(x), t.renderObject(find.descendant(of: x, matching: find.byType(Listener)).first), null,
          'register 측정 안 함(viewer 위)', () => t.tap(x));
      await waitFor('${c.id} T2 pop', () => viewer.evaluate().isEmpty);
      var st = await settle('${c.id} S1');
      inspect('${c.id} S1', false, '다시보기');
      await shot('${c.id} S1', 'after_x_null', 'viewer 헤더 X(null) 복귀 — 대상 false · 다시보기 · 이웃 false', st);
      // ③ 아이콘과 배지 사이 gap8 tapAt → true(viewer 없음)
      tg = targets();
      final g8 = Offset((tg.icon.right + tg.badge.left) / 2, tg.icon.center.dy);
      await tapLogged('${c.id} T3 gap8', g8, tg.sel, tg.view, regPre(), () => t.tapAt(g8));
      await waitFor('${c.id} T3', () => viewer.evaluate().isEmpty);
      st = await settle('${c.id} S2');
      inspect('${c.id} S2', true, '다시보기');
      await shot('${c.id} S2', 'gap8_true', '열람 뒤 gap8 tapAt — 대상 true · 이웃 false', st);
      // ④ 제목 내부 대표점(rect 중심) tapAt → false
      tg = targets();
      final tc = tg.title.center;
      await tapLogged('${c.id} T4 title', tc, tg.sel, tg.view, regPre(), () => t.tapAt(tc));
      await waitFor('${c.id} T4', () => viewer.evaluate().isEmpty);
      st = await settle('${c.id} S3');
      inspect('${c.id} S3', false, '다시보기');
      await shot('${c.id} S3', 'title_false', '제목 tapAt — 대상 false · 이웃 false', st);
      // ⑤ 별도 다시보기 TextButton → privacy viewer(즉시 동의 0)
      tg = targets();
      final vb = tg.viewBtn;
      await tapLogged('${c.id} T5 view', t.getCenter(vb), tg.view, tg.sel, regPre(), () => t.tap(vb));
      await peek('${c.id} T5');
      await waitFor('${c.id} T5 viewer', () => viewer.evaluate().length == 1);
      viewerIs('${c.id} T5');
      // ⑥ CTA 활성 확인(필요하면 viewer jumpTo 끝 1회) → 동의하고 닫기
      final cta = find.descendant(of: viewer, matching: find.byType(ElevatedButton));
      final vs = find.descendant(of: viewer, matching: find.byType(Scrollable)).first;
      final vpos = t.state<ScrollableState>(vs).position;
      var en = t.widget<ElevatedButton>(cta).onPressed != null;
      out('${c.id} T6 viewer scroll pixels=${vpos.pixels} max=${vpos.maxScrollExtent} ctaEnabled=$en');
      if (!en) {
        vpos.jumpTo(vpos.maxScrollExtent);
        await waitFor('${c.id} T6 jumpTo 끝', () => t.widget<ElevatedButton>(cta).onPressed != null);
        en = t.widget<ElevatedButton>(cta).onPressed != null;
        out('${c.id} T6 viewer jumpTo 끝 1회 pixels=${vpos.pixels} max=${vpos.maxScrollExtent} ctaEnabled=$en');
      }
      expect(en, isTrue, reason: 'T6 CTA 활성');
      expect(visibleText(t.widget<Text>(find.descendant(of: cta, matching: find.byType(Text))).data ?? ''), '동의하고 닫기');
      await tapLogged('${c.id} T6 agree', t.getCenter(cta), t.renderObject(find.descendant(of: cta, matching: find.byType(Listener)).first), null,
          'register 측정 안 함(viewer 위)', () => t.tap(cta));
      await waitFor('${c.id} T6 pop', () => viewer.evaluate().isEmpty);
      st = await settle('${c.id} S4');
      inspect('${c.id} S4', true, '다시보기');
      await shot('${c.id} S4', 'viewer_agree_true', '다시보기 viewer 동의하고 닫기(true) 복귀 — 대상 true · 이웃 false', st);
      out('${c.id} done taps=$taps shots=$k');
      expect(taps, 6, reason: '명시 tap 6');
      expect(t.takeException(), isNull);
    });
  }

  // [DU1 구현161 · 후속161] TS-6-N / B — 활성 다시보기 글색 · 밑줄(grey400 → textSecondary) after 관측. 명시 tap 2 / 배율:
  //   ① unread privacy 배지 tapAt → viewer ② viewer 헤더 X → null 복귀(= 구현160 S1 상태) → 정착 · 단언 · PNG 1장.
  //   기준 기하는 구현160 TS-5 S1 raw(≤ 0.01). TS-5 국소 함수의 사본이며 waitFor 는 조건 · idle 을 둘 다 마지막에 단언한다.
  for (final c in const [
    (id: 'TS-6-N', s: 1.0, px: 40.10000000000002, ln: 2,
        row: [17.0, 431.29999999999995, 303.0, 479.29999999999995], sel: [17.0, 431.29999999999995, 251.64002532958983, 479.29999999999995],
        view: [251.64002532958983, 431.29999999999995, 303.0, 479.29999999999995], badge: [39.099999999999994, 445.79999999999995, 70.17998657226562, 464.79999999999995],
        title: [75.27998657226561, 436.29999999999995, 251.64002532958983, 474.29999999999995], vp: [0.0, 125.9, 320.0, 560.8]),
    (id: 'TS-6-B', s: 2.0, px: 624.2, ln: 6,
        row: [17.0, 242.5, 303.0, 464.5], sel: [17.0, 242.5, 207.47999114990233, 464.5],
        view: [207.47999114990233, 329.5, 303.0, 377.5], badge: [39.099999999999994, 335.5, 92.26000366210937, 371.5],
        title: [97.36000366210936, 242.5, 207.47999114990233, 464.5], vp: [0.0, 170.90000000000003, 320.0, 546.0]),
  ]) {
    testWidgets('${c.id} 다시보기 색 — privacy 배지→viewer→X(null) 복귀 320×640@${c.s}', (t) async {
      SharedPreferences.setMockInitialValues({});
      await t.runAsync(vqLoadFonts);
      final key = GlobalKey();
      const items = [
        (id: 'service_terms', title: '서비스 이용약관', req: true),
        (id: 'privacy', title: '개인정보 수집·이용 동의(아주 긴 제목 예시)', req: true),
        (id: 'marketing', title: '마케팅 수신', req: false),
      ];
      final tt = items[1].title;
      await _pump(t, () async => _terms([for (final i in items) _item(i.id, i.title, i.req)]), scale: c.s, boundaryKey: key);
      void out(String l) {
        // ignore: avoid_print
        print(l);
      }
      String raw(Rect r) => 'LTRB(${r.left}, ${r.top}, ${r.right}, ${r.bottom})';
      String idn(Object o) => '${o.runtimeType}#${identityHashCode(o).toRadixString(16)}';
      String esc(String s) => s.replaceAll('\n', r'\n');
      String hex(Color? x) => x == null ? 'null' : '#${x.toARGB32().toRadixString(16).padLeft(8, '0')}';
      double spread(List<List<double>> w) {
        var s = 0.0;
        for (var k = 0; k < w[0].length; k++) {
          var hi = w[0][k];
          var lo = w[0][k];
          for (final v in w) {
            if (v[k] > hi) hi = v[k];
            if (v[k] < lo) lo = v[k];
          }
          if (hi - lo > s) s = hi - lo;
        }
        return s;
      }
      final mq = MediaQuery.of(t.element(find.byType(RegisterScreen)));
      final primary = Theme.of(t.element(find.byType(RegisterScreen))).primaryColor;
      const textSecondary = Color(0xFF60646F); // = AppColors.textSecondary(app_colors.dart:263) — AppColors import 를 더하지 않는다
      out('${c.id} screenMQ textScaler=${mq.textScaler} padding=${mq.padding} viewPadding=${mq.viewPadding} viewInsets=${mq.viewInsets} primary=${hex(primary)}');
      await _scrollTo(t, findVisibleTextContaining('전체 동의'));
      final sc = find.byType(Scrollable).first;
      final pos0 = t.state<ScrollableState>(sc).position;
      final viewer = find.byType(TermsViewerScreen);
      final checkIco = find.byWidgetPredicate((w) => w is Icon && (w.icon == Icons.check_circle || w.icon == Icons.check_circle_outline));
      Finder rowOf(String title, bool req) {
        final els = find.ancestor(of: findVisibleText(title), matching: find.byType(Row)).evaluate().where((e) {
          final f = find.byElementPredicate((x) => identical(x, e));
          int cnt(Finder m) => find.descendant(of: f, matching: m).evaluate().length;
          return cnt(findVisibleText(title)) == 1 && cnt(find.byType(TextButton)) == 1 && cnt(checkIco) == 1 && cnt(find.text(req ? '필수' : '선택')) == 1;
        }).toList();
        expect(els.length, 1, reason: '$title 외곽 Row(제목·체크·배지·보기) 하나');
        return find.byElementPredicate((x) => identical(x, els.single));
      }
      // 행 상태: 아이콘 모양 · 보기 글 · 보기 글색 / 밑줄색(Text.style) · semantics checked(그 행 병합 노드일 때)
      ({String icon, String view, Color? color, Color? deco, TextDecoration? dec, String sem}) rowState(String title, bool req) {
        final row = rowOf(title, req);
        final ico = t.widget<Icon>(find.descendant(of: row, matching: checkIco));
        final vb = find.descendant(of: row, matching: find.byType(TextButton));
        final vtx = t.widget<Text>(find.descendant(of: vb, matching: find.byType(Text)));
        final node = t.getSemantics(find.descendant(of: row, matching: checkIco));
        final d = node.getSemanticsData();
        final own = d.label.contains(title);
        final sem = !own ? '행노드아님#${node.id}' : (d.flagsCollection.hasCheckedState ? '${d.flagsCollection.isChecked}' : 'none');
        return (icon: ico.icon == Icons.check_circle ? 'filled' : 'outline', view: visibleText(vtx.data ?? ''), color: vtx.style?.color,
            deco: vtx.style?.decorationColor, dec: vtx.style?.decoration, sem: sem);
      }
      void neighbors(String tag) {
        for (final i in [items[0], items[2]]) {
          final s = rowState(i.title, i.req);
          out('$tag neighbor ${i.id} icon=${s.icon} view=${s.view} color=${hex(s.color)} deco=${hex(s.deco)} dec=${s.dec} semChecked=${s.sem}');
          expect(s.icon == 'outline' && s.view == '보기' && s.color == primary && s.deco == primary && s.dec == TextDecoration.underline &&
              (s.sem == 'false' || s.sem.startsWith('행노드아님')), isTrue, reason: '$tag 이웃 ${i.id} 불변 $s');
        }
      }
      Future<void> waitFor(String tag, bool Function() done) async {
        var i = 0;
        var idle = false;
        while (i < 60) {
          await t.pump(const Duration(milliseconds: 50));
          i++;
          if (done() && !t.binding.hasScheduledFrame) {
            idle = true;
            break;
          }
        }
        out('$tag wait pumps=$i done=${done()} idle=$idle scheduled=${t.binding.hasScheduledFrame} viewer=${viewer.evaluate().length}');
        expect(done() && idle && !t.binding.hasScheduledFrame, isTrue, reason: '$tag 대기 조건 · idle');
      }
      bool near4(Rect r, List<double> e) =>
          (r.left - e[0]).abs() <= 0.01 && (r.top - e[1]).abs() <= 0.01 && (r.right - e[2]).abs() <= 0.01 && (r.bottom - e[3]).abs() <= 0.01;
      // 도달 · 정착(TS-5 와 같은 26성분 규약) — viewer 위에서는 부르지 않는다. 기준 기하 비교는 S1 에서만.
      Future<(List<double> Function(), bool Function(), List<double>)> settle(String tag, {bool compare = false}) async {
        expect(viewer, findsNothing, reason: '$tag viewer 없음에서만 측정');
        final label = findVisibleText(tt);
        await t.scrollUntilVisible(label, 150, scrollable: sc, maxScrolls: 60);
        expect(label, findsOneWidget, reason: '$tag 제목 Text 하나');
        await t.ensureVisible(rowOf(tt, true));
        final row = rowOf(tt, true);
        final badgeText = find.descendant(of: row, matching: find.text('필수'));
        expect(badgeText, findsOneWidget, reason: '$tag 배지 하나');
        final badgeBox = find.ancestor(of: badgeText, matching: find.byType(Container)).first;
        final vb = find.descendant(of: row, matching: find.byType(TextButton));
        final selInk = find.ancestor(of: find.descendant(of: row, matching: checkIco), matching: find.byType(InkWell)).first;
        List<double> nums() {
          final p = t.state<ScrollableState>(sc).position;
          final rs = <Rect>[t.getRect(badgeBox), t.getRect(badgeText), t.getRect(label), t.getRect(row), t.getRect(sc)];
          return <double>[
            p.pixels, p.minScrollExtent, p.maxScrollExtent, p.viewportDimension, p.extentBefore, p.extentAfter,
            for (final r in rs) ...<double>[r.left, r.top, r.right, r.bottom],
          ];
        }
        bool flags() {
          final p = t.state<ScrollableState>(sc).position;
          return identical(p, pos0) && p.hasContentDimensions && !p.outOfRange && !p.isScrollingNotifier.value;
        }
        final samples = <List<double>>[];
        final oks = <bool>[];
        var stableAt = 0;
        for (var i = 1; i <= 20; i++) {
          await t.pump(const Duration(milliseconds: 50));
          final v = nums();
          samples.add(v);
          oks.add(flags() && v.every((x) => x.isFinite));
          if (samples.length >= 3 && oks.sublist(oks.length - 3).every((f) => f) && spread(samples.sublist(samples.length - 3)) <= 0.1) {
            stableAt = i;
            break;
          }
        }
        expect(stableAt, greaterThan(0), reason: '$tag 50ms×20 안에 안정 창 없음');
        await t.pump(const Duration(milliseconds: 50));
        final held = nums();
        expect(flags() && held.every((x) => x.isFinite) && spread([samples.last, held]) <= 0.1, isTrue, reason: '$tag hold 실패');
        final vp = t.getRect(sc);
        bool inside(Rect r) => r.top >= vp.top - 0.5 && r.bottom <= vp.bottom + 0.5 && r.left >= 0 && r.right <= 320;
        expect(inside(t.getRect(badgeBox)) && inside(t.getRect(label)) && inside(t.getRect(vb)), isTrue, reason: '$tag 배지 · 제목 · 보기 완전 표시');
        final para = t.renderObject<RenderParagraph>(find.descendant(of: label, matching: find.byType(RichText), matchRoot: true).first) /* [DU365] 제목 KeepWordsText(Semantics 로 감싼 RichText) 추종 */;
        final lines = para.getBoxesForSelection(TextSelection(baseOffset: 0, extentOffset: para.text.toPlainText().length)).map((b) => b.top.round()).toSet().length;
        final pp = t.state<ScrollableState>(sc).position;
        out('$tag samples=${samples.length} stableWindow=#${stableAt - 2}~#$stableAt pixels=${pp.pixels} min=${pp.minScrollExtent} max=${pp.maxScrollExtent} '
            'viewportDimension=${pp.viewportDimension} extentBefore=${pp.extentBefore} extentAfter=${pp.extentAfter} outOfRange=${pp.outOfRange} isScrolling=${pp.isScrollingNotifier.value} '
            'badgeBox=${raw(t.getRect(badgeBox))} badgeText=${raw(t.getRect(badgeText))} label=${raw(t.getRect(label))} labelLines=$lines row=${raw(t.getRect(row))} '
            'sel=${raw(t.getRect(selInk))} view=${raw(t.getRect(vb))} viewport=${raw(vp)}');
        if (compare) {
          final ok = (pp.pixels - c.px).abs() <= 0.01 && lines == c.ln && near4(t.getRect(row), c.row) && near4(t.getRect(selInk), c.sel) &&
              near4(t.getRect(vb), c.view) && near4(t.getRect(badgeBox), c.badge) && near4(t.getRect(label), c.title) && near4(vp, c.vp);
          out('$tag 구현160 S1 기하 대조(≤0.01) ok=$ok');
          expect(ok, isTrue, reason: '$tag 구현160 S1 기하와 같아야 한다');
        }
        return (nums, flags, held);
      }
      String acts(SemanticsData d) => SemanticsAction.values.where(d.hasAction).map((a) => a.name).join(',');
      Rect inTo(SemanticsNode n, SemanticsNode? top) {
        var mx = Matrix4.identity();
        for (SemanticsNode? k = n; k != null && !identical(k, top); k = k.parent) {
          if (k.transform != null) mx = k.transform!.multiplied(mx);
        }
        return MatrixUtils.transformRect(mx, n.rect);
      }
      bool near(Rect a, Rect b) =>
          (a.left - b.left).abs() <= 0.01 && (a.top - b.top).abs() <= 0.01 && (a.right - b.right).abs() <= 0.01 && (a.bottom - b.bottom).abs() <= 0.01;
      // S1: 다시보기 글색 · 밑줄 · 활성 · 렌더 상태 · 의미(같은 id · 이름 · checked false · tap · 별도 보기) · raw rect · chain · 이웃.
      void inspect(String tag) {
        final row = rowOf(tt, true);
        final ico = find.descendant(of: row, matching: checkIco);
        final label = findVisibleText(tt);
        final badgeText = find.descendant(of: row, matching: find.text('필수'));
        final selInk = find.ancestor(of: ico, matching: find.byType(InkWell)).first;
        final viewBtn = find.descendant(of: row, matching: find.byType(TextButton));
        expect(identical(t.element(selInk), t.element(find.ancestor(of: label, matching: find.byType(InkWell)).first)) &&
            identical(t.element(selInk), t.element(find.ancestor(of: badgeText, matching: find.byType(InkWell)).first)), isTrue, reason: '$tag 같은 InkWell');
        expect(find.descendant(of: selInk, matching: find.byType(TextButton)), findsNothing, reason: '$tag 보기는 선택 영역 밖');
        final s = rowState(tt, true);
        final vtx = t.widget<Text>(find.descendant(of: viewBtn, matching: find.byType(Text)));
        final enabled = t.widget<TextButton>(viewBtn).onPressed != null;
        final sR = t.getRect(selInk);
        final vR = t.getRect(viewBtn);
        out('$tag target icon=${s.icon} view=${s.view} enabled=$enabled color=${hex(s.color)} deco=${hex(s.deco)} dec=${s.dec} weight=${vtx.style?.fontWeight} '
            'sel=${raw(sR)} viewBtn=${raw(vR)} selSize=${sR.width}x${sR.height} viewSize=${vR.width}x${vR.height}');
        expect(s.icon == 'outline' && s.view == '다시보기' && enabled && s.color == textSecondary && s.deco == textSecondary &&
            s.dec == TextDecoration.underline && vtx.style?.fontWeight == FontWeight.normal, isTrue, reason: '$tag 다시보기 textSecondary · 밑줄 · 활성');
        expect(sR.width >= 48 && sR.height >= 48 && vR.width >= 48 && vR.height >= 48, isTrue, reason: '$tag 최소 48');
        final sem = <String, SemanticsNode>{
          for (final e in <(String, Finder)>[('check', ico), ('badge', badgeText), ('title', label), ('sel', selInk), ('view', viewBtn)])
            e.$1: t.getSemantics(e.$2),
        };
        final m = sem['sel']!;
        final v = sem['view']!;
        final md = m.getSemanticsData();
        final vd = v.getSemanticsData();
        int cnt(String x, String p) => p.allMatches(x).length;
        final nameOk = RegExp('^필수[\n ]+${RegExp.escape(tt)}\$').hasMatch(md.label) &&
            cnt(md.label, '필수') == 1 && cnt(md.label, tt) == 1 && !md.label.contains('보기') && !md.label.contains('*');
        final mg = inTo(m, null);
        final vg = inTo(v, null);
        out('$tag sem ids check=${sem['check']!.id} badge=${sem['badge']!.id} title=${sem['title']!.id} sel=${m.id} view=${v.id} parent=${m.parent?.id} viewParent=${v.parent?.id}');
        out('$tag sem merged label="${esc(md.label)}" nameOk=$nameOk hasCheckedState=${md.flagsCollection.hasCheckedState} isChecked=${md.flagsCollection.isChecked} actions=${acts(md)} '
            'local=${raw(m.rect)} transform=${m.transform?.storage.toList()} global=${raw(mg)} widgetSel=${raw(sR)} near=${near(mg, sR)}');
        out('$tag sem view label="${esc(vd.label)}" actions=${acts(vd)} flags=${vd.flagsCollection.toStrings()} local=${raw(v.rect)} transform=${v.transform?.storage.toList()} '
            'global=${raw(vg)} widgetView=${raw(vR)} near=${near(vg, vR)}');
        expect(sem['check']!.id == m.id && sem['badge']!.id == m.id && sem['title']!.id == m.id && v.id != m.id && identical(v.parent, m.parent), isTrue, reason: '$tag 병합 1 · 보기 별도');
        expect(nameOk && md.flagsCollection.hasCheckedState && !md.flagsCollection.isChecked && md.hasAction(SemanticsAction.tap), isTrue, reason: '$tag 이름 · checked false · tap');
        expect(vd.label == '다시보기' && vd.hasAction(SemanticsAction.tap) && near(mg, sR) && near(vg, vR), isTrue, reason: '$tag 보기 label · tap · global ≈ 위젯');
        final par = m.parent!;
        final rowP = inTo(m, par).expandToInclude(inTo(v, par));
        final centerTaps = <String>[];
        final overlap = <String>[];
        par.visitChildren((k) {
          final d = k.getSemanticsData();
          final r = inTo(k, par);
          if (d.hasAction(SemanticsAction.tap) && rowP.inflate(0.5).contains(r.center)) centerTaps.add('${k.id}');
          if (d.actions != 0 && rowP.deflate(0.5).overlaps(r)) overlap.add('${k.id}:${acts(d)}');
          return true;
        });
        out('$tag sem rowTaps parent=${par.id} rowInParent=${raw(rowP)} centerTaps=$centerTaps overlapActions=$overlap');
        expect(centerTaps.length == 2 && centerTaps.toSet().containsAll(['${m.id}', '${v.id}']) && overlap.length == 2, isTrue, reason: '$tag 행 tap = 병합 + 보기');
        for (final e in <(String, SemanticsNode)>[('merged', m), ('view', v)]) {
          for (SemanticsNode? k = e.$2; k != null; k = k.parent) {
            out('    $tag chain ${e.$1} id=${k.id} local=${raw(k.rect)} transform=${k.transform?.storage.toList()} global=${raw(inTo(k, null))} actions=${acts(k.getSemanticsData())}');
          }
        }
        neighbors(tag);
      }
      var taps = 0;
      Future<void> tapLogged(String tag, Offset p, RenderObject want, RenderObject? not, String pre, Future<void> Function() act) async {
        final hr = t.hitTestOnBinding(p);
        final has = hr.path.any((e) => identical(e.target, want));
        final bad = not != null && hr.path.any((e) => identical(e.target, not));
        out('$tag pre at=(${p.dx}, ${p.dy}) viewer=${viewer.evaluate().length} $pre want=${idn(want)} inPath=$has notInPath=${!bad} pathLen=${hr.path.length}');
        out('    $tag path ${hr.path.map((e) => idn(e.target)).join(' > ')}');
        expect(has && !bad, isTrue, reason: '$tag 탭 전 hit 경로');
        await act();
        taps++;
        out('$tag tap#$taps 실행');
      }
      // ── S0 초기(unread · 캡처 없음): 도달 · 렌더 outline · 보기 * · 주색 · 이웃 false
      await settle('${c.id} S0');
      final s0 = rowState(tt, true);
      out('${c.id} S0 target icon=${s0.icon} view=${s0.view} color=${hex(s0.color)} deco=${hex(s0.deco)} semChecked=${s0.sem}');
      expect(s0.icon == 'outline' && s0.view == '보기' && s0.color == primary && s0.sem == 'false', isTrue, reason: 'S0 unread 상태');
      neighbors('${c.id} S0');
      // ① unread privacy 배지 중심 tapAt → privacy viewer
      final row1 = rowOf(tt, true);
      final selInk1 = find.ancestor(of: find.descendant(of: row1, matching: checkIco), matching: find.byType(InkWell)).first;
      final vb1 = find.descendant(of: row1, matching: find.byType(TextButton));
      final selLs = find.descendant(of: selInk1, matching: find.byType(Listener));
      final viewLs = find.descendant(of: vb1, matching: find.byType(Listener));
      expect([selLs.evaluate().length, viewLs.evaluate().length], [1, 1], reason: 'Listener 각 1');
      final bc = t.getRect(find.ancestor(of: find.descendant(of: row1, matching: find.text('필수')), matching: find.byType(Container)).first).center;
      await tapLogged('${c.id} T1 badge', bc, t.renderObject(selLs.first), t.renderObject(viewLs.first), 'target icon=${s0.icon} semChecked=${s0.sem}', () => t.tapAt(bc));
      await waitFor('${c.id} T1 viewer', () => viewer.evaluate().length == 1);
      expect(t.widget<TermsViewerScreen>(viewer).item.id, 'privacy', reason: 'T1 privacy viewer');
      out('${c.id} T1 viewer item=${t.widget<TermsViewerScreen>(viewer).item.id} rect=${raw(t.getRect(viewer))}');
      // ② viewer 헤더 X → null 복귀
      final x = find.descendant(of: viewer, matching: find.byType(IconButton));
      expect(x, findsOneWidget, reason: 'viewer 헤더 X 하나');
      await tapLogged('${c.id} T2 X', t.getCenter(x), t.renderObject(find.descendant(of: x, matching: find.byType(Listener)).first), null,
          'register 측정 안 함(viewer 위)', () => t.tap(x));
      await waitFor('${c.id} T2 pop', () => viewer.evaluate().isEmpty);
      // ── S1: 구현160 S1 과 같은 상태 · 기하 → 단언 → 캡처
      final st = await settle('${c.id} S1', compare: true);
      inspect('${c.id} S1');
      final pp = t.state<ScrollableState>(sc).position;
      await vqCapture(t, key, '${c.id}_review_color', conditions: {
        'screen': 'RegisterScreen (production) · termsLoaderForTest · initialUserTermsStepForTest',
        'role': 'USER 약관 단계(2)', 'theme': 'RoleTheme.workerTheme', 'viewport': '320x640', 'dpr': 1.0, 'textScaler': c.s,
        'mq': 'padding=${mq.padding} viewPadding=${mq.viewPadding} viewInsets=${mq.viewInsets}', 'keyboard': '닫힘(inset 0)',
        'fonts': 'vqLoadFonts: NotoSansKR Regular+Bold · Roboto=NotoSansKR · MaterialIcons(SDK) · FlutterTest 미등록',
        'data': '약관 3: service_terms 필수 · privacy 필수(긴 제목) · marketing 선택 · version b · serverNow 2026-11-01Z',
        'prefs': 'setMockInitialValues({})', 'clock': '미주입',
        'state': 'viewer 헤더 X(null) 복귀 — 대상 false · 다시보기 textSecondary · 이웃 false', 'taps': '$taps',
        'source': 'G 38852e1b(예상 after) · 다시보기 글색 / 밑줄 textSecondary', 'scroll': '${pp.pixels}',
        'before': 'du160 TS-5-${c.id.substring(5)}_1_after_x_null'});
      final after = st.$1();
      expect(st.$2() && after.every((x) => x.isFinite) && spread([st.$3, after]) <= 0.1, isTrue, reason: 'S1 캡처 전후 유지 실패');
      out('${c.id} shot ${c.id}_review_color vqEnabled=$vqEnabled taps=$taps');
      expect(taps, 2, reason: '명시 tap 2');
      expect(t.takeException(), isNull);
    });
  }

  // [DU1 구현165 · 후속165] TS-7 / TS-8 — S004 묶음 A1(미열람 보기 * → 보기) · C1(가입 후 안내 grey400 → textSecondary) · E1(전체 동의 미체크 grey400 → textTertiary).
  //   TS-7-N / B(before · after 공통): `_scrollTo(전체 동의)` 뒤 안내 위 16dp 여백 jumpTo 1회로 안내 Text 와 전체 동의 아이콘을 함께 완전 표시 · 정착 · 단계별 색 단언 · PNG 1.
  //   TS-8-N / B-1 / 2 / 3(after 전용): TS-4 와 같은 도달(전체 동의 → 항목 순서대로 scrollUntilVisible) · k 번째 unread 행 단언 · PNG 1.
  //   tap 0 · performAction 0 · callback 직접 호출 0. 공유 실패 latch(첫 실패 뒤 다음 사례는 첫 줄에서 실패) · pump / scroll 뒤와 캡처 직전 takeException null.
  var latch165 = false;
  // [DU393] 기본 회귀(phase 없음)는 현재 after 기대를 검사한다. 캡처는 명시 phase(+vqEnabled) 옵트인 — 그때만 phase 접미사로 before/after 를 가른다.
  final capture165 = vqEnabled;
  final after165 = !capture165 || (vqPhase ?? '').endsWith('-after');
  // [DU393] 공유 latch 는 캡처 묶음에서만 앞 사례를 막는다 — 기본 회귀에서는 시험마다 초기화(독립).
  void latchStart165() {
    if (!capture165) latch165 = false;
    expect(latch165, isFalse, reason: '앞 사례 실패 — 진행하지 않는다');
  }
  const items165 = [
    (id: 'service_terms', title: '서비스 이용약관', req: true),
    (id: 'privacy', title: '개인정보 수집·이용 동의(아주 긴 제목 예시)', req: true),
    (id: 'marketing', title: '마케팅 수신', req: false),
  ];
  String raw165(Rect r) => 'LTRB(${r.left}, ${r.top}, ${r.right}, ${r.bottom})';
  String hex165(Color? x) => x == null ? 'null' : '#${x.toARGB32().toRadixString(16).padLeft(8, '0')}';
  void out165(String l) {
    // ignore: avoid_print
    print(l);
  }
  void pend165(WidgetTester t, String tag) {
    final e = t.takeException();
    if (e != null) latch165 = true;
    expect(e, isNull, reason: '$tag pending exception');
    expect(latch165, isFalse, reason: '$tag latch');
  }
  double spread165(List<List<double>> w) {
    var s = 0.0;
    for (var k = 0; k < w[0].length; k++) {
      var hi = w[0][k];
      var lo = w[0][k];
      for (final v in w) {
        if (v[k] > hi) hi = v[k];
        if (v[k] < lo) lo = v[k];
      }
      if (hi - lo > s) s = hi - lo;
    }
    return s;
  }
  final ico165 = find.byWidgetPredicate((w) => w is Icon && (w.icon == Icons.check_circle || w.icon == Icons.check_circle_outline));
  Finder rowOf165(String title, bool req) {
    final els = find.ancestor(of: findVisibleText(title), matching: find.byType(Row)).evaluate().where((e) {
      final f = find.byElementPredicate((x) => identical(x, e));
      int cnt(Finder m) => find.descendant(of: f, matching: m).evaluate().length;
      return cnt(findVisibleText(title)) == 1 && cnt(find.byType(TextButton)) == 1 && cnt(ico165) == 1 && cnt(find.text(req ? '필수' : '선택')) == 1;
    }).toList();
    expect(els.length, 1, reason: '$title 외곽 Row(제목 · 체크 · 배지 · 보기) 하나');
    return find.byElementPredicate((x) => identical(x, els.single));
  }
  // 정착: 50ms × 최대 20 · 연속 3표본 spread ≤ 0.1 · 유한 · 동일 ScrollPosition · hasContentDimensions · !outOfRange · !isScrolling, 예약 프레임 대기(≤ 20), hold 1, 끝에 !hasScheduledFrame. 표본 raw 출력.
  Future<(List<double> Function(), List<double>)> settle165(WidgetTester t, String tag, Finder sc, ScrollPosition pos0, List<Finder> fs) async {
    List<double> nums() {
      final p = t.state<ScrollableState>(sc).position;
      final v = <double>[p.pixels, p.minScrollExtent, p.maxScrollExtent, p.viewportDimension, p.extentBefore, p.extentAfter];
      for (final f in fs) {
        final r = t.getRect(f);
        v.addAll([r.left, r.top, r.right, r.bottom]);
      }
      return v;
    }
    bool flags() {
      final p = t.state<ScrollableState>(sc).position;
      return identical(p, pos0) && p.hasContentDimensions && !p.outOfRange && !p.isScrollingNotifier.value;
    }
    final samples = <List<double>>[];
    final oks = <bool>[];
    var stableAt = 0;
    for (var i = 1; i <= 20; i++) {
      await t.pump(const Duration(milliseconds: 50));
      pend165(t, '$tag 정착 pump $i');
      final v = nums();
      samples.add(v);
      oks.add(flags() && v.every((x) => x.isFinite));
      if (samples.length >= 3 && oks.sublist(oks.length - 3).every((f) => f) && spread165(samples.sublist(samples.length - 3)) <= 0.1) {
        stableAt = i;
        break;
      }
    }
    expect(stableAt, greaterThan(0), reason: '$tag 50ms×20 안에 안정 창 없음');
    // 안정 창 뒤 예약 프레임(overscroll 등 시각 애니메이션)이 끝날 때까지 50ms × 최대 20 대기 — 횟수 기록, 끝에 단언.
    var idleWait = 0;
    while (t.binding.hasScheduledFrame && idleWait < 20) {
      await t.pump(const Duration(milliseconds: 50));
      pend165(t, '$tag idle pump ${idleWait + 1}');
      idleWait++;
    }
    await t.pump(const Duration(milliseconds: 50));
    pend165(t, '$tag hold pump');
    final held = nums();
    expect(flags() && held.every((x) => x.isFinite) && spread165([samples.last, held]) <= 0.1, isTrue, reason: '$tag hold 실패');
    expect(t.binding.hasScheduledFrame, isFalse, reason: '$tag 예약 프레임 남음');
    out165('$tag settle samples=${samples.length} stableWindow=#${stableAt - 2}~#$stableAt idleWait=$idleWait raw=${samples.map((s) => s.join(',')).join(' | ')} held=${held.join(',')}');
    return (nums, held);
  }
  for (final c in const [(id: 'TS-7-N', s: 1.0), (id: 'TS-7-B', s: 2.0)]) {
    testWidgets('${c.id} 가입 후 안내 · 전체 동의 아이콘 색 320×640@${c.s}', (t) async {
      latchStart165();
      try {
        SharedPreferences.setMockInitialValues({});
        await t.runAsync(vqLoadFonts);
        final key = GlobalKey();
        await _pump(t, () async => _terms([for (final i in items165) _item(i.id, i.title, i.req)]), scale: c.s, boundaryKey: key);
        pend165(t, '${c.id} pump');
        final phase = vqPhase ?? '';
        // [DU393] 단계 이름 단언은 캡처 옵트인에서만(기본 회귀 = after)
        if (capture165) expect(phase.endsWith('-before') || phase.endsWith('-after'), isTrue, reason: '단계 이름 $phase');
        final isAfter = after165;
        final mq = MediaQuery.of(t.element(find.byType(RegisterScreen)));
        final allText = findVisibleTextContaining('전체 동의');
        await _scrollTo(t, allText);
        pend165(t, '${c.id} _scrollTo');
        final sc = find.byType(Scrollable).first;
        final pos0 = t.state<ScrollableState>(sc).position;
        final note = findVisibleText('가입 후 MY에서 언제든 변경할 수 있어요.');
        expect(note, findsOneWidget, reason: '가입 후 안내 Text 하나');
        final allInk = find.ancestor(of: allText, matching: find.byType(InkWell)).first;
        final allIcon = find.descendant(of: allInk, matching: find.byType(Icon));
        expect(allIcon, findsOneWidget, reason: '전체 동의 아이콘 하나');
        // 안내 위 16dp 여백 jumpTo 1회(포인터 아님) — 레이아웃 좌표로 목표를 정하므로 앞 경로와 무관하다.
        final vp0 = t.getRect(sc);
        final nr0 = t.getRect(note);
        final target = (pos0.pixels + (nr0.top - vp0.top) - 16).clamp(pos0.minScrollExtent, pos0.maxScrollExtent).toDouble();
        out165('${c.id} reach phase=$phase prePixels=${pos0.pixels} preMax=${pos0.maxScrollExtent} noteTop=${nr0.top} vpTop=${vp0.top} target=$target');
        pos0.jumpTo(target);
        await t.pump();
        pend165(t, '${c.id} jumpTo');
        final st = await settle165(t, '${c.id} S', sc, pos0, [note, allIcon, allInk, sc]);
        final vp = t.getRect(sc);
        final nR = t.getRect(note);
        final iR = t.getRect(allIcon);
        final aR = t.getRect(allInk);
        bool inside(Rect r) => r.top >= vp.top && r.bottom <= vp.bottom && r.left >= 0 && r.right <= 320;
        expect(inside(nR.inflate(1)) && inside(iR.inflate(1)), isTrue, reason: '${c.id} 안내 · 아이콘 ± 1dp 완전 표시 $nR $iR / $vp');
        final noteW = t.widget<Text>(note);
        final iconW = t.widget<Icon>(allIcon);
        final para = t.renderObject<RenderParagraph>(note);
        final lines = para.getBoxesForSelection(TextSelection(baseOffset: 0, extentOffset: para.text.toPlainText().length)).map((b) => b.top.round()).toSet().length;
        final p = t.state<ScrollableState>(sc).position;
        out165('${c.id} S phase=$phase pixels=${p.pixels} min=${p.minScrollExtent} max=${p.maxScrollExtent} viewportDimension=${p.viewportDimension} extentBefore=${p.extentBefore} '
            'extentAfter=${p.extentAfter} note=${raw165(nR)} noteLines=$lines noteColor=${hex165(noteW.style?.color)} noteSize=${noteW.style?.fontSize} icon=${raw165(iR)} '
            'iconColor=${hex165(iconW.color)} iconSize=${iconW.size} allInk=${raw165(aR)} viewport=${raw165(vp)}');
        for (final it in items165) {
          final row = rowOf165(it.title, it.req);
          final vb = find.descendant(of: row, matching: find.byType(TextButton));
          final vt = t.widget<Text>(find.descendant(of: vb, matching: find.byType(Text)));
          out165('${c.id} S row ${it.id} row=${raw165(t.getRect(row))} view=${raw165(t.getRect(vb))} viewText=${visibleText(vt.data ?? '')}');
        }
        expect(iconW.icon, Icons.check_circle_outline, reason: '${c.id} 전체 동의 미체크');
        expect(noteW.style?.color, isAfter ? const Color(0xFF60646F) : const Color(0xFFBDBDBD), reason: '${c.id} 안내 글색');
        expect(iconW.color, isAfter ? const Color(0xFF686C77) : const Color(0xFFBDBDBD), reason: '${c.id} 전체 동의 아이콘 색');
        final sem = t.getSemantics(allInk).getSemanticsData();
        out165('${c.id} S allSem label="${sem.label.replaceAll('\n', r'\n')}" actions=${SemanticsAction.values.where(sem.hasAction).map((a) => a.name).join(',')} flags=${sem.flagsCollection.toStrings()}');
        pend165(t, '${c.id} 캡처 직전');
        await vqCapture(t, key, '${c.id}_guidance_allcheck', conditions: {
          'screen': 'RegisterScreen (production) · termsLoaderForTest · initialUserTermsStepForTest', 'role': 'USER 약관 단계(2)',
          'theme': 'RoleTheme.workerTheme', 'viewport': '320x640', 'dpr': 1.0, 'textScaler': c.s,
          'mq': 'padding=${mq.padding} viewPadding=${mq.viewPadding} viewInsets=${mq.viewInsets}', 'keyboard': '닫힘(inset 0)',
          'fonts': 'vqLoadFonts: NotoSansKR Regular+Bold · Roboto=NotoSansKR · MaterialIcons(SDK) · FlutterTest 미등록',
          'data': '약관 3: service_terms 필수 · privacy 필수(긴 제목) · marketing 선택 · version b · serverNow 2026-11-01Z',
          'prefs': 'setMockInitialValues({})', 'clock': '미주입', 'phase': phase, 'scroll': '${p.pixels}',
          'state': '초기 unread · 전체 동의 미체크 · 가입 후 안내와 전체 동의 아이콘 함께 표시', 'taps': '0'});
        final after = st.$1();
        expect(after.every((x) => x.isFinite) && spread165([st.$2, after]) <= 0.1, isTrue, reason: '${c.id} 캡처 전후 유지');
        pend165(t, '${c.id} 캡처 뒤');
        out165('${c.id} shot ${c.id}_guidance_allcheck vqEnabled=$vqEnabled');
      } catch (e) {
        latch165 = true;
        rethrow;
      }
    });
  }
  for (final c in const [(id: 'TS-8-N', s: 1.0), (id: 'TS-8-B', s: 2.0)]) {
    for (var k = 1; k <= 3; k++) {
      testWidgets('${c.id}-$k unread 행 보기 문구 320×640@${c.s}', (t) async {
        latchStart165();
        final tag = '${c.id}-$k';
        try {
          expect(after165, isTrue, reason: '$tag 는 after 전용');
          SharedPreferences.setMockInitialValues({});
          await t.runAsync(vqLoadFonts);
          final key = GlobalKey();
          await _pump(t, () async => _terms([for (final i in items165) _item(i.id, i.title, i.req)]), scale: c.s, boundaryKey: key);
          pend165(t, '$tag pump');
          final mq = MediaQuery.of(t.element(find.byType(RegisterScreen)));
          final primary = Theme.of(t.element(find.byType(RegisterScreen))).primaryColor;
          await _scrollTo(t, findVisibleTextContaining('전체 동의'));
          pend165(t, '$tag _scrollTo');
          final sc = find.byType(Scrollable).first;
          final pos0 = t.state<ScrollableState>(sc).position;
          // TS-4 와 같은 도달: 1 … k 항목을 순서대로 scrollUntilVisible(150, 최대 60) · 정착(TS-4 와 같은 26성분).
          late (List<double> Function(), List<double>) st;
          for (var i = 0; i < k; i++) {
            final it = items165[i];
            final label = findVisibleText(it.title);
            await t.scrollUntilVisible(label, 150, scrollable: sc, maxScrolls: 60);
            pend165(t, '$tag scroll ${it.id}');
            expect(label, findsOneWidget, reason: '$tag ${it.id} 제목 Text 하나');
            final row = rowOf165(it.title, it.req);
            final badgeText = find.descendant(of: row, matching: find.text(it.req ? '필수' : '선택'));
            expect(badgeText, findsOneWidget, reason: '$tag ${it.id} 배지 하나');
            final badgeBox = find.ancestor(of: badgeText, matching: find.byType(Container)).first;
            st = await settle165(t, '$tag reach ${it.id}', sc, pos0, [badgeBox, badgeText, label, row, sc]);
          }
          final it = items165[k - 1];
          final label = findVisibleText(it.title);
          final row = rowOf165(it.title, it.req);
          final badgeText = find.descendant(of: row, matching: find.text(it.req ? '필수' : '선택'));
          final badgeBox = find.ancestor(of: badgeText, matching: find.byType(Container)).first;
          final ico = find.descendant(of: row, matching: ico165);
          final selInk = find.ancestor(of: ico, matching: find.byType(InkWell)).first;
          final viewBtn = find.descendant(of: row, matching: find.byType(TextButton));
          final vtx = t.widget<Text>(find.descendant(of: viewBtn, matching: find.byType(Text)));
          final vp = t.getRect(sc);
          final lR = t.getRect(label);
          final bR = t.getRect(badgeBox);
          final sR = t.getRect(selInk);
          final vR = t.getRect(viewBtn);
          bool inside(Rect r) => r.top >= vp.top - 0.5 && r.bottom <= vp.bottom + 0.5 && r.left >= 0 && r.right <= 320;
          final para = t.renderObject<RenderParagraph>(find.descendant(of: label, matching: find.byType(RichText), matchRoot: true).first) /* [DU365] 제목 KeepWordsText(Semantics 로 감싼 RichText) 추종 */;
          final lines = para.getBoxesForSelection(TextSelection(baseOffset: 0, extentOffset: para.text.toPlainText().length)).map((b) => b.top.round()).toSet().length;
          final p = t.state<ScrollableState>(sc).position;
          out165('$tag S ${it.id} pixels=${p.pixels} min=${p.minScrollExtent} max=${p.maxScrollExtent} viewportDimension=${p.viewportDimension} extentBefore=${p.extentBefore} '
              'extentAfter=${p.extentAfter} label=${raw165(lR)} labelLines=$lines badgeBox=${raw165(bR)} sel=${raw165(sR)} view=${raw165(vR)} row=${raw165(t.getRect(row))} '
              'viewport=${raw165(vp)} viewText=${visibleText(vtx.data ?? '')} color=${hex165(vtx.style?.color)} deco=${hex165(vtx.style?.decorationColor)} '
              'dec=${vtx.style?.decoration} weight=${vtx.style?.fontWeight} icon=${t.widget<Icon>(ico).icon == Icons.check_circle ? 'filled' : 'outline'}');
          for (final o in items165) {
            final r2 = rowOf165(o.title, o.req);
            final v2 = find.descendant(of: r2, matching: find.byType(TextButton));
            final t2 = t.widget<Text>(find.descendant(of: v2, matching: find.byType(Text)));
            out165('$tag S row ${o.id} row=${raw165(t.getRect(r2))} view=${raw165(t.getRect(v2))} viewText=${visibleText(t2.data ?? '')}');
          }
          expect(inside(lR) && inside(bR) && inside(vR), isTrue, reason: '$tag 제목 · 배지 · 보기 완전 표시');
          expect(sR.width >= 48 && sR.height >= 48 && vR.width >= 48 && vR.height >= 48 && (sR.right - vR.left).abs() <= 0.01, isTrue,
              reason: '$tag 선택 / 보기 최소 48 · 분리 $sR $vR');
          expect(visibleText(vtx.data ?? '') == '보기' && vtx.style?.color == primary && vtx.style?.decorationColor == primary &&
              vtx.style?.decoration == TextDecoration.underline && vtx.style?.fontWeight == FontWeight.w600, isTrue, reason: '$tag 미열람 보기 · 주색 · w600 · 밑줄');
          expect(t.widget<Icon>(ico).icon, Icons.check_circle_outline, reason: '$tag 미체크');
          // 의미: 체크 · 배지 · 제목 · 선택 영역은 같은 병합 노드, 보기는 별도 노드(label 보기) · checked false · tap.
          final sem = <String, SemanticsNode>{
            for (final e in <(String, Finder)>[('check', ico), ('badge', badgeText), ('title', label), ('sel', selInk), ('view', viewBtn)])
              e.$1: t.getSemantics(e.$2),
          };
          final m = sem['sel']!;
          final v = sem['view']!;
          final md = m.getSemanticsData();
          final vd = v.getSemanticsData();
          final badge = it.req ? '필수' : '선택';
          int cnt(String x, String q) => q.allMatches(x).length;
          final nameOk = RegExp('^$badge[\n ]+${RegExp.escape(it.title)}\$').hasMatch(md.label) && cnt(md.label, badge) == 1 &&
              cnt(md.label, it.title) == 1 && !md.label.contains('보기') && !md.label.contains('*');
          String acts(SemanticsData d) => SemanticsAction.values.where(d.hasAction).map((a) => a.name).join(',');
          out165('$tag S sem ids check=${sem['check']!.id} badge=${sem['badge']!.id} title=${sem['title']!.id} sel=${m.id} view=${v.id} '
              'merged="${md.label.replaceAll('\n', r'\n')}" nameOk=$nameOk hasCheckedState=${md.flagsCollection.hasCheckedState} isChecked=${md.flagsCollection.isChecked} '
              'actions=${acts(md)} view="${vd.label}" viewActions=${acts(vd)} viewFlags=${vd.flagsCollection.toStrings()}');
          expect(sem['check']!.id == m.id && sem['badge']!.id == m.id && sem['title']!.id == m.id && v.id != m.id, isTrue, reason: '$tag 병합 1 · 보기 별도');
          expect(nameOk && md.flagsCollection.hasCheckedState && !md.flagsCollection.isChecked && md.hasAction(SemanticsAction.tap), isTrue,
              reason: '$tag 이름 · checked false · tap');
          expect(vd.label == '보기' && vd.hasAction(SemanticsAction.tap), isTrue, reason: '$tag 보기 label · tap');
          // hit 분리(이벤트 dispatch 없음): 선택 중심 → 선택 Listener 만, 보기 중심 → 보기 Listener 만.
          final selRO = t.renderObject(find.descendant(of: selInk, matching: find.byType(Listener)).first);
          final viewRO = t.renderObject(find.descendant(of: viewBtn, matching: find.byType(Listener)).first);
          bool has(Offset o, RenderObject ro) => t.hitTestOnBinding(o).path.any((e) => identical(e.target, ro));
          final hs = [has(sR.center, selRO), has(sR.center, viewRO), has(vR.center, viewRO), has(vR.center, selRO)];
          out165('$tag S hit selCenter sel=${hs[0]} view=${hs[1]} · viewCenter view=${hs[2]} sel=${hs[3]}');
          expect(hs, [true, false, true, false], reason: '$tag hit 분리');
          pend165(t, '$tag 캡처 직전');
          await vqCapture(t, key, '${tag}_unread', conditions: {
            'screen': 'RegisterScreen (production) · termsLoaderForTest · initialUserTermsStepForTest', 'role': 'USER 약관 단계(2)',
            'theme': 'RoleTheme.workerTheme', 'viewport': '320x640', 'dpr': 1.0, 'textScaler': c.s,
            'mq': 'padding=${mq.padding} viewPadding=${mq.viewPadding} viewInsets=${mq.viewInsets}', 'keyboard': '닫힘(inset 0)',
            'fonts': 'vqLoadFonts: NotoSansKR Regular+Bold · Roboto=NotoSansKR · MaterialIcons(SDK) · FlutterTest 미등록',
            'data': '약관 3: service_terms 필수 · privacy 필수(긴 제목) · marketing 선택 · version b · serverNow 2026-11-01Z',
            'prefs': 'setMockInitialValues({})', 'clock': '미주입', 'phase': vqPhase ?? '', 'scroll': '${p.pixels}',
            'state': '${it.id} 행 도달(TS-4 순서) · unread · 미체크', 'before': 'du159 TS-4-${c.id.substring(5)}_${k}_${it.id}', 'taps': '0'});
          final after = st.$1();
          expect(after.every((x) => x.isFinite) && spread165([st.$2, after]) <= 0.1, isTrue, reason: '$tag 캡처 전후 유지');
          pend165(t, '$tag 캡처 뒤');
          out165('$tag shot ${tag}_unread vqEnabled=$vqEnabled');
        } catch (e) {
          latch165 = true;
          rethrow;
        }
      });
    }
  }
}
