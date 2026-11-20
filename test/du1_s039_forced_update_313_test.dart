// ignore_for_file: depend_on_referenced_packages
// [DU313] S039 ForcedUpdateScreen — 버전 게이트 차단 화면 4상태 렌더 관측(11-15 자체검토 셀).
//   상태: 업데이트 필요(스토어 주소 있음) · 업데이트 필요(주소 없음) · 확인 실패(unknown) · 확인 실패에서 '다시 확인' 진행 중.
//   진입은 실제 SplashScreen → pushReplacement 경로(app_version_gate_test VG-4x 가 이미 보증)를 다시 돌지 않고
//   화면을 직접 띄운다. 스토어 열기(url_launcher)는 누르지 않는다. 진행 중 상태는 끝나지 않는 onRetry 로 만든다.
//   단언(전후 공통): 넘침 0 · 주요/보조 버튼 화면 안 · hit · 높이 ≥ 48 · 진행 중 버튼 비활성 · 뒤로 가기 차단.
//   [DU313 r3] 소급 2 결정 — 현재 제품 정답 단언(낱말 줄바꿈 · 결과 안내 · 다시 확인 라벨 · 52 · 재확인 결과 전달)은 기본 실행에서 건다.
//   VQ(DU1_VQ_PHASE)는 PNG 저장에만 쓴다. 알려진 옛 결함만 명시 env DU_BEFORE_OBSERVE=313r3 에서 단언 대신 'KNOWN NG' 로 기록한다.
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ALfit/screens/common/forced_update_screen.dart';
import 'package:ALfit/services/app_version_service.dart';
import 'package:ALfit/theme/role_theme.dart';

import 'support/du1_vq_capture.dart';
import 'support/visible_text.dart';

const kUpd = VersionGateResult(
  status: VersionGateStatus.updateRequired,
  source: VersionPolicySource.remote,
  fromCache: false,
  currentVersion: '1.3.0',
  minVersion: '1.4.0',
  updateUrl: 'https://store.example/app',
);
const kUpdNoUrl = VersionGateResult(
  status: VersionGateStatus.updateRequired,
  source: VersionPolicySource.remote,
  fromCache: false,
  currentVersion: '1.3.0',
  minVersion: '1.4.0',
);
const kUnknown = VersionGateResult(
  status: VersionGateStatus.unknown,
  source: VersionPolicySource.localDefault,
  fromCache: true,
  currentVersion: '',
  minVersion: '',
);

const kSupported = VersionGateResult(
  status: VersionGateStatus.supported,
  source: VersionPolicySource.remote,
  fromCache: false,
  currentVersion: '1.4.0',
  minVersion: '1.4.0',
);

/// [DU313 r3] 알려진 옛 결함 관측 모드 — 명시 env 일 때만. 기본(일반 실행)은 모든 단언을 건다.
final bool _beforeObs = Platform.environment['DU_BEFORE_OBSERVE'] == '313r3';

/// sidecar 에 남길 onRetry 모드 설명(소급 2 정정 — 실제 callback 과 같게).
const _modeDesc = {
  'pending': '끝나지 않는 Future(진행 중 관측)',
  'blocked': '즉시 같은 판정을 돌려줌(여전히 막힘)',
  'to_upd': '즉시 updateRequired(스토어 URL 있음)를 돌려줌',
  'to_unknown': '즉시 unknown 을 돌려줌',
  'pass': 'Splash 처럼 pushAndRemoveUntil 로 대체 + supported 를 돌려줌',
};

/// 문단의 줄 목록과 음절 끊김 위치 — 실제 문단의 글자별 상자(getBoxesForSelection) top 으로 줄을 가른다.
///   앞 줄 마지막 글자와 다음 줄 첫 글자 사이(양끝 포함)에 공백 · 줄바꿈이 하나도 없으면 낱말 중간 끊김이다.
///   상자가 없는 글자(WORD JOINER 등 폭 0)는 건너뛴다.
({List<String> lines, List<String> breaks}) _lines(RenderParagraph rp) {
  final plain = rp.text.toPlainText();
  final lines = <StringBuffer>[];
  final breaks = <String>[];
  final ws = RegExp(r'[\s ]');
  double? lastTop;
  var lastIdx = -1;
  for (var i = 0; i < plain.length; i++) {
    final bx = rp.getBoxesForSelection(TextSelection(baseOffset: i, extentOffset: i + 1));
    if (bx.isEmpty) continue;
    final top = bx.first.top;
    if (lastTop == null || top > lastTop + 1) {
      if (lastTop != null && !ws.hasMatch(plain.substring(lastIdx, i + 1))) {
        breaks.add('${visibleText(lines.last.toString())}|${visibleText(plain.substring(i, (i + 3).clamp(0, plain.length)))}');
      }
      lines.add(StringBuffer());
      lastTop = top;
    }
    lines.last.write(plain[i]);
    lastIdx = i;
  }
  return (lines: [for (final b in lines) visibleText(b.toString())], breaks: breaks);
}

void main() {
  for (final c in const [(id: 'S039-A', w: 392.0, h: 844.0, s: 1.0), (id: 'S039-B', w: 320.0, h: 640.0, s: 2.0)]) {
    testWidgets('${c.id} 강제 업데이트 ${c.w.toInt()}×${c.h.toInt()}@${c.s} — 업데이트 · 주소 없음 · 확인 실패 · 진행 중', (t) async {
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
      try {
      t.view.physicalSize = Size(c.w, c.h);
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.reset);
      final key = GlobalKey();
      void out(String l) {
        // ignore: avoid_print
        print(l);
      }

      final pending = Completer<VersionGateResult>();
      var retries = 0;
      var curMode = 'pending';
      final nav = GlobalKey<NavigatorState>();
      // [DU313 r2] onRetry 모드 — pending: 끝나지 않음(진행 중 관측) · blocked: 곧 끝나고 여전히 막힘 ·
      //   pass: Splash 와 같이 pushAndRemoveUntil 로 화면을 대체(통과).
      Future<void> pump(VersionGateResult r, String tag, {String mode = 'pending'}) async {
        curMode = mode;
        await t.pumpWidget(RepaintBoundary(
          key: key,
          child: MaterialApp(
            navigatorKey: nav,
            debugShowCheckedModeBanner: false,
            theme: RoleTheme.workerTheme,
            builder: (ctx, child) =>
                MediaQuery(data: MediaQuery.of(ctx).copyWith(textScaler: TextScaler.linear(c.s)), child: child!),
            home: ForcedUpdateScreen(
              key: ValueKey(tag),
              result: r,
              onRetry: () {
                retries++;
                if (mode == 'blocked') return Future<VersionGateResult>.value(r);
                if (mode == 'to_upd') return Future<VersionGateResult>.value(kUpd);
                if (mode == 'to_unknown') return Future<VersionGateResult>.value(kUnknown);
                if (mode == 'pass') {
                  nav.currentState!.pushAndRemoveUntil(
                      MaterialPageRoute(builder: (_) => const Scaffold(body: Text('통과 뒤 화면'))), (route) => false);
                  return Future<VersionGateResult>.value(kSupported);
                }
                return pending.future;
              },
            ),
          ),
        ));
        for (var i = 0; i < 6; i++) {
          await t.pump(const Duration(milliseconds: 50));
        }
      }

      Map<String, Object?> cond(String state) => {
            'entry': 'ForcedUpdateScreen 직접(SplashScreen 경로는 app_version_gate_test VG-40~47)',
            'theme': 'RoleTheme.workerTheme', 'viewport': '${c.w.toInt()}x${c.h.toInt()}', 'dpr': 1.0, 'textScaler': c.s,
            'fonts': 'vqLoadFonts: NotoSansKR Regular+Bold · Roboto=NotoSansKR · MaterialIcons(SDK)',
            'onRetry': _modeDesc[curMode], 'beforeObserve': _beforeObs, 'store': '누르지 않음', 'state': state};

      bool hits(Finder f) {
        final hit = HitTestResult();
        WidgetsBinding.instance.hitTestInView(hit, t.getRect(f).center, t.view.viewId);
        return hit.path.any((e) => e.target == t.renderObject(f));
      }

      bool inScreen(Rect r) => r.top >= -0.5 && r.bottom <= c.h + 0.5 && r.left >= -0.5 && r.right <= c.w + 0.5;

      // [DU313 r3] 알려진 옛 결함 — 기본은 단언, DU_BEFORE_OBSERVE=313r3 일 때만 기록
      void known(bool ok, String what) {
        out('KNOWN ${ok ? 'ok' : 'NG'} $what beforeObs=$_beforeObs');
        if (!_beforeObs) expect(ok, isTrue, reason: what);
      }

      String texts(String tag) {
        final buf = StringBuffer();
        final paras = find.descendant(of: find.byType(ForcedUpdateScreen), matching: find.byType(RichText));
        for (final e in paras.evaluate()) {
          final rp = e.renderObject! as RenderParagraph;
          final l = _lines(rp);
          final r = t.getRect(find.byElementPredicate((x) => identical(x, e)));
          buf.writeln('$tag text "${visibleText(rp.text.toPlainText())}" rect=$r lines=${l.lines.length} ${l.lines} '
              'syllableBreaks=${l.breaks} color=${rp.text.style?.color} size=${rp.text.style?.fontSize} w=${rp.text.style?.fontWeight}');
          expect(l.breaks, isEmpty, reason: '$tag 낱말 중간 줄바꿈: "${visibleText(rp.text.toPlainText())}"');
        }
        return buf.toString().trimRight();
      }

      Finder primary() => find.descendant(of: find.byType(ForcedUpdateScreen), matching: find.byType(ElevatedButton));
      Finder secondary() => find.descendant(of: find.byType(ForcedUpdateScreen), matching: find.byType(TextButton));
      Finder icon() => find.descendant(of: find.byType(ForcedUpdateScreen), matching: find.byType(Icon));

      void check(String tag, {required bool hasSecondary, required bool busy}) {
        expect(overflows, isEmpty, reason: '$tag 넘침');
        final scaffold = t.widget<Scaffold>(find.descendant(of: find.byType(ForcedUpdateScreen), matching: find.byType(Scaffold)));
        final pop = t.widget<PopScope>(find.descendant(of: find.byType(ForcedUpdateScreen), matching: find.byType(PopScope)));
        expect(pop.canPop, isFalse, reason: '$tag 뒤로 가기 우회 금지');
        expect(primary(), findsOneWidget);
        final pr = t.getRect(primary());
        final pb = t.widget<ElevatedButton>(primary());
        final pl = find.descendant(of: primary(), matching: find.byType(Text));
        out('$tag bg=${scaffold.backgroundColor} icon=${t.getRect(icon())} '
            'iconColor=${t.widget<Icon>(icon()).color} iconSize=${t.widget<Icon>(icon()).size}');
        out('$tag primary rect=$pr h=${pr.height.toStringAsFixed(1)} label="${visibleText(t.widget<Text>(pl).data ?? '')}" '
            'enabled=${pb.onPressed != null} hit=${hits(primary())} inScreen=${inScreen(pr)} '
            'bg=${pb.style?.backgroundColor?.resolve({})} fg=${pb.style?.foregroundColor?.resolve({})}');
        expect(inScreen(pr), isTrue, reason: '$tag 주요 버튼 화면 안');
        expect(pr.height, greaterThanOrEqualTo(48 - 1e-6), reason: '$tag 주요 버튼 높이(48, 부동소수 오차 1e-6)');
        known(pr.height >= 52 - 1e-6, '$tag 주요 버튼 시각 최소 52(실측 ${pr.height.toStringAsFixed(1)})');
        expect(hits(primary()), isTrue, reason: '$tag 주요 버튼 hit');
        expect(pb.onPressed == null, busy, reason: '$tag 진행 중에만 비활성');
        if (hasSecondary) {
          expect(secondary(), findsOneWidget);
          final sr = t.getRect(secondary());
          final sb = t.widget<TextButton>(secondary());
          out('$tag secondary rect=$sr h=${sr.height.toStringAsFixed(1)} enabled=${sb.onPressed != null} hit=${hits(secondary())} '
              'inScreen=${inScreen(sr)} gap=${(sr.top - pr.bottom).toStringAsFixed(1)}');
          expect(inScreen(sr), isTrue, reason: '$tag 보조 버튼 화면 안');
          expect(sr.height, greaterThanOrEqualTo(48 - 1e-6), reason: '$tag 보조 버튼 높이(48, 부동소수 오차 1e-6)');
          expect(hits(secondary()), isTrue, reason: '$tag 보조 버튼 hit');
          expect(sb.onPressed == null, busy);
        } else {
          expect(secondary(), findsNothing, reason: '$tag 보조 버튼 없음');
        }
        final top = t.getRect(icon()).top;
        final bottom = hasSecondary ? t.getRect(secondary()).bottom : pr.bottom;
        out('$tag block top=${top.toStringAsFixed(1)} bottom=${bottom.toStringAsFixed(1)} '
            'above=${top.toStringAsFixed(1)} below=${(c.h - bottom).toStringAsFixed(1)}');
        out(texts(tag));
      }

      // ① 업데이트 필요 — 스토어 주소 있음(주요 '업데이트하기' + 보조 '업데이트를 마쳤어요')
      await pump(kUpd, 'upd');
      check('${c.id}_1_upd', hasSecondary: true, busy: false);
      expect(findVisibleText('앱 업데이트가 필요합니다'), findsOneWidget);
      expect(findVisibleText('업데이트하기'), findsOneWidget);
      await vqCapture(t, key, '${c.id}_1_upd', conditions: cond('업데이트 필요 · 스토어 주소 있음'));

      // ② 업데이트 필요 — 주소 없음(주요가 '다시 확인' · 직접 검색 안내)
      await pump(kUpdNoUrl, 'nourl');
      check('${c.id}_2_nourl', hasSecondary: false, busy: false);
      expect(findVisibleText('다시 확인'), findsOneWidget);
      expect(findVisibleTextContaining('직접 검색'), findsOneWidget);
      await vqCapture(t, key, '${c.id}_2_nourl', conditions: cond('업데이트 필요 · 스토어 주소 없음'));

      // ③ 확인 실패(unknown) — '다시 확인'
      await pump(kUnknown, 'unknown');
      check('${c.id}_3_unknown', hasSecondary: false, busy: false);
      expect(findVisibleText('앱 버전을 확인하지 못했습니다'), findsOneWidget);
      expect(findVisibleText('앱 업데이트가 필요합니다'), findsNothing, reason: '네트워크 오류를 업데이트 필요로 말하지 않는다');
      await vqCapture(t, key, '${c.id}_3_unknown', conditions: cond('확인 실패(unknown)'));

      // ④ 확인 실패 → '다시 확인' 진행 중
      await t.tap(primary());
      for (var i = 0; i < 4; i++) {
        await t.pump(const Duration(milliseconds: 50));
      }
      expect(retries, 1);
      check('${c.id}_4_busy', hasSecondary: false, busy: true);
      expect(findVisibleText('잠시만 기다려 주세요'), findsOneWidget);
      await vqCapture(t, key, '${c.id}_4_busy', conditions: cond('확인 실패 → 다시 확인 진행 중'));
      // 다시 누를 수 없다(중복 호출 0)
      await t.tap(primary(), warnIfMissed: false);
      await t.pump(const Duration(milliseconds: 50));
      expect(retries, 1, reason: '진행 중 중복 호출 0');
      // [DU313 r2] ⑤ 업데이트 필요 → 보조 버튼으로 다시 확인 → 여전히 막힘 / ⑥ 확인 실패 → 다시 확인 → 여전히 막힘
      //   r2 after 단계에서만 결과 안내 단언(r2 before = r1 적용본은 안내가 없다 — 기록만).
      // [DU313 r3] 업데이트 필요 안내 새 문구(소급 2 권고). 옛 문구는 '아직 최신 버전이 아니에요. …'.
      const updNote = '아직 업데이트가 필요해요. 업데이트한 뒤 앱을 다시 열어 주세요.';
      const unkNote = '아직 버전을 확인하지 못했어요. 잠시 후 다시 시도해 주세요.';
      Future<void> settle([int n = 8]) async {
        for (var i = 0; i < n; i++) {
          await t.pump(const Duration(milliseconds: 50));
        }
      }

      // [DU313 r2b] 결과 안내가 스크롤 영역 안에 끝까지 보이는가(잘려 보이지 않는가)
      void noteVisible(String tag, String note) {
        final f = findVisibleText(note);
        if (f.evaluate().isEmpty) return;
        final vp = t.getRect(find.descendant(of: find.byType(ForcedUpdateScreen), matching: find.byType(Scrollable)).first);
        final nr = t.getRect(f);
        final ok = nr.top >= vp.top - 0.5 && nr.bottom <= vp.bottom + 0.5;
        out('$tag noteRect=$nr viewport=$vp fullyVisible=$ok');
        expect(ok, isTrue, reason: '$tag 결과 안내가 스크롤 영역에 잘려 보인다');
      }

      await pump(kUpd, 'upd_blocked', mode: 'blocked');
      final secLabel = visibleText(t.widget<Text>(find.descendant(of: secondary(), matching: find.byType(Text))).data ?? '');
      await t.tap(secondary());
      await settle();
      expect(retries, 2);
      check('${c.id}_5_upd_recheck', hasSecondary: true, busy: false);
      noteVisible('${c.id}_5_upd_recheck', updNote);
      out('${c.id}_5_upd_recheck secondaryLabel="$secLabel" note=${findVisibleText(updNote).evaluate().isNotEmpty}');
      expect(secLabel, '다시 확인', reason: '보조 버튼은 완료 선언이 아니라 다시 확인');
      known(findVisibleText(updNote).evaluate().length == 1, '⑤ 여전히 업데이트 필요 — 새 안내 문구');
      await vqCapture(t, key, '${c.id}_5_upd_recheck', conditions: cond('업데이트 필요 → 보조 버튼 다시 확인 → 여전히 막힘'));

      await pump(kUnknown, 'unknown_blocked', mode: 'blocked');
      await t.tap(primary());
      await settle();
      expect(retries, 3);
      check('${c.id}_6_unknown_recheck', hasSecondary: false, busy: false);
      noteVisible('${c.id}_6_unknown_recheck', unkNote);
      out('${c.id}_6_unknown_recheck note=${findVisibleText(unkNote).evaluate().isNotEmpty}');
      expect(findVisibleText(unkNote), findsOneWidget, reason: '여전히 확인 실패면 결과를 말한다');
      await vqCapture(t, key, '${c.id}_6_unknown_recheck', conditions: cond('확인 실패 → 다시 확인 → 여전히 실패'));

      // [DU313 r3] ⑧ 확인 실패 → 다시 확인 → 새 판정 updateRequired(URL 있음): 화면이 업데이트 필요로 바뀐다
      await pump(kUnknown, 'unknown_to_upd', mode: 'to_upd');
      await t.tap(primary());
      await settle();
      expect(retries, 4);
      final toUpd = findVisibleText('앱 업데이트가 필요합니다').evaluate().isNotEmpty &&
          findVisibleText('업데이트하기').evaluate().isNotEmpty &&
          secondary().evaluate().length == 1 &&
          findVisibleText(updNote).evaluate().length == 1;
      out('${c.id}_8_unknown_to_upd propagated=$toUpd');
      known(toUpd, '⑧ 새 판정 updateRequired 로 제목 · 스토어 CTA · 보조 다시 확인 · 안내가 바뀐다');
      check('${c.id}_8_unknown_to_upd', hasSecondary: toUpd, busy: false);
      noteVisible('${c.id}_8_unknown_to_upd', toUpd ? updNote : unkNote);
      await vqCapture(t, key, '${c.id}_8_unknown_to_upd', conditions: cond('확인 실패 → 다시 확인 → 새 판정 업데이트 필요'));

      // [DU313 r3] ⑨ 업데이트 필요(URL) → 보조 다시 확인 → 새 판정 unknown: 화면이 확인 실패로 바뀐다
      await pump(kUpd, 'upd_to_unknown', mode: 'to_unknown');
      await t.tap(secondary());
      await settle();
      expect(retries, 5);
      final toUnk = findVisibleText('앱 버전을 확인하지 못했습니다').evaluate().isNotEmpty &&
          secondary().evaluate().isEmpty &&
          findVisibleText('다시 확인').evaluate().length == 1 &&
          findVisibleText(unkNote).evaluate().length == 1;
      out('${c.id}_9_upd_to_unknown propagated=$toUnk');
      known(toUnk, '⑨ 새 판정 unknown 으로 제목 · 다시 확인 CTA · 확인 실패 안내가 바뀐다');
      check('${c.id}_9_upd_to_unknown', hasSecondary: !toUnk, busy: false);
      await vqCapture(t, key, '${c.id}_9_upd_to_unknown', conditions: cond('업데이트 필요 → 다시 확인 → 새 판정 확인 실패'));

      // ⑦ 다시 확인 통과 — 화면이 대체되고 결과 안내 setState 가 죽은 화면을 건드리지 않는다
      await pump(kUnknown, 'unknown_pass', mode: 'pass');
      await t.tap(primary());
      await settle(12);
      expect(retries, 6);
      expect(find.byType(ForcedUpdateScreen), findsNothing, reason: '통과하면 차단 화면이 대체된다');
      expect(find.text('통과 뒤 화면'), findsOneWidget);
      expect(t.takeException(), isNull);
      out('${c.id}_7_pass replaced=true');
      out('${c.id} retries=$retries beforeObs=$_beforeObs phase=$vqPhase');
      await t.pumpWidget(const SizedBox.shrink());
      } finally {
        // 단언 실패 때도 오류 처리기를 먼저 되돌린다 — 안 그러면 binding 단언 뒤 10분 시간 초과까지 멈춘다(DU314 TB 실측).
        FlutterError.onError = prev;
      }
    });
  }
}
