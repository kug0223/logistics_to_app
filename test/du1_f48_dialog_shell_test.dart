// [DU1 구현49 · 감사49 §3·§4 F48-1] 공용 확인창(DialogHelper._buildDialog/showConfirm/showAlert) 가독성 — 대조 셀.
//   주 대표는 test/du1_c1_edit_discard_test.dart(공고 수정 미저장 경고 320·2.0)를 그대로 재사용한다.
//   여기서는 ① 같은 짧은 확인 문구 360×780·1.0 배치·두 반환값 ② 긴 본문 320×760·2.0 본문 끝 실제 스크롤 도달·취소 false
//   ③ 1버튼 showAlert 320×640·2.0 을 관측한다. 서버·writer 없음(순수 UI helper).
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ALfit/theme/app_colors.dart';
import 'package:ALfit/theme/role_theme.dart';
import 'package:ALfit/utils/dialog_helper.dart';

import 'support/du1_vq_capture.dart';
import 'support/visible_text.dart';

const _longMessage = '이 작업은 되돌릴 수 없습니다. 확정된 근무와 연결된 급여 기록, 근태 기록, '
    '계약서 보관본이 함께 정리되며 근로자에게 알림이 발송됩니다. '
    '정리 이후에는 같은 조건으로 다시 만들 수 없고, 필요한 경우 새 공고를 '
    '등록해 처음부터 다시 진행해야 합니다. 계속하시겠습니까?';

Future<void> _settle(WidgetTester t, [int n = 8]) async {
  for (var i = 0; i < n; i++) {
    await t.pump(const Duration(milliseconds: 50));
  }
}

void _out(String l) {
  // ignore: avoid_print
  print(l);
}

void main() {
  Future<({BuildContext ctx, GlobalKey key, List<String> overflows, FlutterExceptionHandler? prev})> host(
      WidgetTester t, double w, double h, double s) async {
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
    t.view.physicalSize = Size(w, h);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    final key = GlobalKey();
    late BuildContext ctx;
    await t.pumpWidget(RepaintBoundary(
      key: key,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: RoleTheme.businessAdminTheme,
        builder: (c, child) => MediaQuery(data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(s)), child: child!),
        home: Builder(builder: (c) {
          ctx = c;
          return const Scaffold(body: SizedBox.expand());
        }),
      ),
    ));
    await t.pump();
    return (ctx: ctx, key: key, overflows: overflows, prev: prev);
  }

  Map<String, Object?> cond(String id, double w, double h, double s, String state) => {
        'entry': 'LOCAL host → DialogHelper 직접 호출(공용 셸 대조 셀)', 'theme': 'RoleTheme.businessAdminTheme',
        'viewport': '${w.toInt()}x${h.toInt()}', 'dpr': 1.0, 'textScaler': s, 'mq': 'padding/viewPadding/viewInsets 0', 'keyboard': '없음',
        'fonts': 'vqLoadFonts: NotoSansKR Regular+Bold · Roboto=NotoSansKR · MaterialIcons(SDK)', 'prefs': '없음', 'clock': '미주입',
        'cell': id, 'state': state};

  String rect(WidgetTester t, Finder f) {
    final r = t.getRect(f);
    final hit = HitTestResult();
    WidgetsBinding.instance.hitTestInView(hit, r.center, t.view.viewId);
    return '$r(${r.width.toStringAsFixed(1)}×${r.height.toStringAsFixed(1)}) hit=${hit.path.any((e) => e.target == t.renderObject(f))}';
  }

  Finder btn(String label) => find.ancestor(of: findVisibleText(label), matching: find.byType(InkWell)).first;

  void lines(WidgetTester t, String label, Finder f) {
    final rp = t.renderObject<RenderParagraph>(find.descendant(of: f, matching: find.byType(RichText)).first);
    final lm = rp.getBoxesForSelection(TextSelection(baseOffset: 0, extentOffset: rp.text.toPlainText().length));
    final tops = lm.map((b) => b.top.round()).toSet().length;
    _out('  $label 줄수=$tops 표시="${rp.text.toPlainText().replaceAll('⁠', '')}" joiner=${rp.text.toPlainText().contains('⁠')}');
  }

  testWidgets('F48-S 짧은 확인 360×780@1.0 — 배치·나가기 true·계속 수정 false', (t) async {
    final h = await host(t, 360, 780, 1.0);
    for (final (tap, expectV) in const [('나가기', true), ('계속 수정', false)]) {
      bool? r;
      DialogHelper.showConfirm(h.ctx, title: '변경사항 취소', message: '저장하지 않은 변경사항이 있습니다.\n나가시겠습니까?',
              confirmText: '나가기', cancelText: '계속 수정', icon: Icons.exit_to_app_outlined)
          .then((v) => r = v);
      await _settle(t);
      _out('F48-S 제목 ${rect(t, findVisibleText('변경사항 취소'))} 계속수정 ${rect(t, btn('계속 수정'))} 나가기 ${rect(t, btn('나가기'))}');
      lines(t, '제목', findVisibleText('변경사항 취소'));
      lines(t, '계속 수정', btn('계속 수정'));
      if (tap == '나가기') await vqCapture(t, h.key, 'F48-S_confirm', conditions: cond('F48-S', 360, 780, 1.0, '짧은 확인창'));
      await t.tap(btn(tap));
      await _settle(t);
      expect(r, expectV, reason: '$tap 반환');
      _out('F48-S $tap → $r');
    }
    FlutterError.onError = h.prev;
    expect(h.overflows, isEmpty, reason: h.overflows.join(' | '));
  });

  testWidgets('F48-C 같은 짧은 확인 320×640@2.0 — 줄 끊김 위치·두 행동(주 대표와 같은 문구)', (t) async {
    final h = await host(t, 320, 640, 2.0);
    bool? r;
    DialogHelper.showConfirm(h.ctx, title: '변경사항 취소', message: '저장하지 않은 변경사항이 있습니다.\n나가시겠습니까?',
            confirmText: '나가기', cancelText: '계속 수정', icon: Icons.exit_to_app_outlined)
        .then((v) => r = v);
    await _settle(t);
    _out('F48-C 제목 ${rect(t, findVisibleText('변경사항 취소'))} 계속수정 ${rect(t, btn('계속 수정'))} 나가기 ${rect(t, btn('나가기'))}');
    for (final (label, f) in [
      ('제목', findVisibleText('변경사항 취소')),
      ('본문', findVisibleText('저장하지 않은 변경사항이 있습니다.\n나가시겠습니까?')),
      ('계속 수정', btn('계속 수정')),
      ('나가기', btn('나가기')),
    ]) {
      final rp = t.renderObject<RenderParagraph>(find.descendant(of: f, matching: find.byType(RichText)).first.evaluate().isEmpty
          ? f
          : find.descendant(of: f, matching: find.byType(RichText)).first);
      final plain = rp.text.toPlainText();
      final segs = <String>[];
      var start = 0;
      final tp = TextPainter(text: rp.text, textDirection: TextDirection.ltr, textScaler: rp.textScaler, textAlign: rp.textAlign)
        ..layout(maxWidth: rp.size.width);
      for (final lm in tp.computeLineMetrics()) {
        final pos = tp.getPositionForOffset(Offset(tp.width, lm.baseline - lm.ascent + lm.height / 2));
        final end = tp.getLineBoundary(pos).end;
        segs.add(plain.substring(start, end).replaceAll('⁠', ''));
        start = end;
      }
      _out('  $label 줄=${segs.length} [${segs.join(' / ')}]');
    }
    await vqCapture(t, h.key, 'F48-C_confirm', conditions: cond('F48-C', 320, 640, 2.0, '짧은 확인창 큰 글자'));
    await t.tap(btn('계속 수정'));
    await _settle(t);
    expect(r, isFalse);
    FlutterError.onError = h.prev;
    expect(h.overflows, isEmpty, reason: h.overflows.join(' | '));
  });

  testWidgets('F48-L 긴 본문 320×760@2.0 — 본문 끝 스크롤 도달·두 행동 도달·취소 false', (t) async {
    final h = await host(t, 320, 760, 2.0);
    bool? r;
    DialogHelper.showConfirm(h.ctx, title: '사업장 삭제', message: _longMessage, confirmText: '삭제', icon: Icons.delete_outline, iconColor: AppColors.error)
        .then((v) => r = v);
    await _settle(t);
    final dialog = find.byType(Dialog);
    final scroll = find.descendant(of: dialog, matching: find.byType(Scrollable)).first;
    _out('F48-L dialog ${t.getRect(dialog)} 본문viewport ${t.getRect(scroll)} 삭제 ${rect(t, btn('삭제'))} 취소 ${rect(t, btn('취소'))}');
    lines(t, '제목', findVisibleText('사업장 삭제'));
    await vqCapture(t, h.key, 'F48-L_1_top', conditions: cond('F48-L', 320, 760, 2.0, '긴 본문 처음'));
    final pos = t.state<ScrollableState>(scroll).position;
    _out('F48-L max=${pos.maxScrollExtent.toStringAsFixed(1)}');
    for (var i = 0; i < 30 && pos.pixels < pos.maxScrollExtent - 0.5; i++) {
      await t.drag(scroll, const Offset(0, -120));
      await _settle(t, 2);
    }
    final body = find.descendant(of: scroll, matching: find.byType(RichText)).last;
    final rp = t.renderObject<RenderParagraph>(body);
    final txt = rp.text.toPlainText();
    final endBox = rp.getBoxesForSelection(TextSelection(baseOffset: txt.length - 1, extentOffset: txt.length)).last;
    final endGlobal = rp.localToGlobal(Offset(endBox.left, endBox.bottom));
    final vp = t.getRect(scroll);
    _out('F48-L 끝 pixels=${pos.pixels.toStringAsFixed(1)}/${pos.maxScrollExtent.toStringAsFixed(1)} 마지막글자 bottom=${endGlobal.dy.toStringAsFixed(1)} viewport bottom=${vp.bottom.toStringAsFixed(1)} 보임=${endGlobal.dy <= vp.bottom + 0.5}');
    expect(endGlobal.dy <= vp.bottom + 0.5, isTrue, reason: '본문 끝까지 스크롤 도달');
    await vqCapture(t, h.key, 'F48-L_2_end', conditions: cond('F48-L', 320, 760, 2.0, '긴 본문 끝'));
    _out('F48-L 끝에서 삭제 ${rect(t, btn('삭제'))} 취소 ${rect(t, btn('취소'))}');
    await t.tap(btn('취소'));
    await _settle(t);
    expect(r, isFalse);
    FlutterError.onError = h.prev;
    expect(h.overflows, isEmpty, reason: h.overflows.join(' | '));
  });

  testWidgets('F48-A 1버튼 showAlert 320×640@2.0 — 확인 도달·닫힘', (t) async {
    final h = await host(t, 320, 640, 2.0);
    var closed = false;
    DialogHelper.showAlert(h.ctx, title: '사업주 날인 미등록', message: '계약서 발송을 위해 사업주 날인이 필요합니다.').then((_) => closed = true);
    await _settle(t);
    _out('F48-A 제목 ${rect(t, findVisibleText('사업주 날인 미등록'))} 확인 ${rect(t, btn('확인'))}');
    lines(t, '제목', findVisibleText('사업주 날인 미등록'));
    await vqCapture(t, h.key, 'F48-A_alert', conditions: cond('F48-A', 320, 640, 2.0, '1버튼 알림'));
    await t.tap(btn('확인'));
    await _settle(t);
    expect(closed, isTrue);
    FlutterError.onError = h.prev;
    expect(h.overflows, isEmpty, reason: h.overflows.join(' | '));
  });
}
