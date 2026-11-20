// ignore_for_file: depend_on_referenced_packages
// [DU325] S034 업무 유형 삭제 두 확인창 — seam(showWorkTypeActivePostingsDialog · showWorkTypeDeleteConfirmDialog) 직접 호출 렌더 관측.
//   소급 3 인계 §4: 스타일을 바꾸지 않은 seam 으로 before, 별도 스타일 후보로 after. 실제 S034 메뉴 → 조회 → 연속 창 → writer 통합 증거는 아니다.
//   단언(기본): 넘침 0 · 버튼 화면 안 · hit · 반환(취소 false · 계속/삭제 true) · 바깥 탭으로 닫히지 않음(barrierDismissible:false).
//   스타일 단언(피할 수 있는 음절 끊김 0 · '계속'은 위험색 아님 · 버튼 높이 ≥ 48)은 기본 실행에서 걸고,
//   DU_BEFORE_OBSERVE=325 일 때만 KNOWN 으로 기록한다(옛 스타일 관측).
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ALfit/screens/business_admin/work_type_management_screen.dart';
import 'package:ALfit/theme/app_colors.dart';
import 'package:ALfit/theme/role_theme.dart';

import 'support/du1_vq_capture.dart';
import 'support/visible_text.dart';

final bool _beforeObs = Platform.environment['DU_BEFORE_OBSERVE'] == '325';
const kLongName = '야간 분류 · 상하차 보조(냉동 창고 B동 출고)';

({List<String> lines, List<String> avoidable}) _lines(RenderParagraph rp) {
  final plain = rp.text.toPlainText();
  final lines = <StringBuffer>[];
  final avoidable = <String>[];
  final ws = RegExp(r'[\s ]');
  double? lastTop;
  var lastIdx = -1;
  for (var i = 0; i < plain.length; i++) {
    final bx = rp.getBoxesForSelection(TextSelection(baseOffset: i, extentOffset: i + 1));
    if (bx.isEmpty) continue;
    final top = bx.first.top;
    if (lastTop == null || top > lastTop + 1) {
      if (lastTop != null && !ws.hasMatch(plain.substring(lastIdx, i + 1)) && ws.hasMatch(lines.last.toString().trim())) {
        avoidable.add('${visibleText(lines.last.toString())}|${visibleText(plain.substring(i, (i + 3).clamp(0, plain.length)))}');
      }
      lines.add(StringBuffer());
      lastTop = top;
    }
    lines.last.write(plain[i]);
    lastIdx = i;
  }
  return (lines: [for (final b in lines) visibleText(b.toString())], avoidable: avoidable);
}

bool _isRedish(Color? c) {
  if (c == null) return false;
  return c.r > 0.6 && c.g < 0.35 && c.b < 0.35;
}

void main() {
  for (final c in const [(id: 'S034-W', w: 360.0, h: 780.0, s: 1.0), (id: 'S034-B', w: 320.0, h: 640.0, s: 2.0)]) {
    testWidgets('${c.id} 업무 유형 삭제 두 창 ${c.w.toInt()}×${c.h.toInt()}@${c.s}', (t) async {
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

        void known(bool ok, String what) {
          out('KNOWN ${ok ? 'ok' : 'NG'} $what beforeObs=$_beforeObs');
          if (!_beforeObs) expect(ok, isTrue, reason: what);
        }

        late BuildContext host;
        await t.pumpWidget(RepaintBoundary(
          key: key,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: RoleTheme.businessAdminTheme,
            builder: (ctx, child) =>
                MediaQuery(data: MediaQuery.of(ctx).copyWith(textScaler: TextScaler.linear(c.s)), child: child!),
            home: Builder(builder: (ctx) {
              host = ctx;
              return const Scaffold(body: Center(child: Text('host')));
            }),
          ),
        ));
        Future<void> settle([int n = 10]) async {
          for (var i = 0; i < n; i++) {
            await t.pump(const Duration(milliseconds: 50));
          }
        }

        bool hits(Finder f) {
          final hit = HitTestResult();
          WidgetsBinding.instance.hitTestInView(hit, t.getRect(f).center, t.view.viewId);
          return hit.path.any((e) => e.target == t.renderObject(f));
        }

        bool inScreen(Rect x) => x.top >= -0.5 && x.bottom <= c.h + 0.5 && x.left >= -0.5 && x.right <= c.w + 0.5;
        Finder btn(String label) => find
            .ancestor(
                of: find.descendant(of: find.byType(Dialog), matching: findVisibleText(label)),
                matching: find.byWidgetPredicate((w) => w is InkWell || w is ButtonStyleButton))
            .first;
        Color? labelColor(String label) {
          final rp = t.renderObject<RenderParagraph>(
              find.descendant(of: find.descendant(of: find.byType(Dialog), matching: findVisibleText(label)), matching: find.byType(RichText)));
          return rp.text.style?.color;
        }

        void dump(String tag) {
          for (final e in find.descendant(of: find.byType(Dialog), matching: find.byType(RichText)).evaluate()) {
            final rp = e.renderObject! as RenderParagraph;
            final s = visibleText(rp.text.toPlainText());
            if (s.length < 2) continue;
            final l = _lines(rp);
            out('$tag text "$s" rect=${t.getRect(find.byElementPredicate((x) => identical(x, e)))} lines=${l.lines} '
                'avoidable=${l.avoidable} color=${rp.text.style?.color} size=${rp.text.style?.fontSize}');
            known(l.avoidable.isEmpty, '$tag 피할 수 있는 음절 끊김 0: "$s"');
          }
        }

        void checkBtn(String tag, String label) {
          final f = btn(label);
          final r = t.getRect(f);
          out('$tag button "$label" rect=$r h=${r.height.toStringAsFixed(1)} hit=${hits(f)} inScreen=${inScreen(r)} '
              'labelColor=${labelColor(label)} type=${t.widget(f).runtimeType}');
          // before(옛 2단계 창)은 320·2.0 에서 버튼이 화면 아래로 벗어났다(TB 실측 643 > 640) — 옛 결함 관측 대상
          known(inScreen(r), '$tag $label 화면 안(실측 $r)');
          expect(hits(f), isTrue, reason: '$tag $label hit');
          known(r.height >= 48 - 1e-6, '$tag $label 높이 ≥ 48(실측 ${r.height.toStringAsFixed(1)})');
        }

        Future<bool?> openA() => showWorkTypeActivePostingsDialog(host, affectedCount: 3);
        Future<bool?> openB() => showWorkTypeDeleteConfirmDialog(host, workTypeName: kLongName);

        // ① 1단계 — 진행 중 공고 있음(3개)
        var fut = openA();
        await settle();
        expect(find.byType(Dialog), findsOneWidget);
        expect(overflows, isEmpty, reason: '${c.id} ① 넘침');
        dump('${c.id}_1_active');
        checkBtn('${c.id}_1_active', '취소');
        checkBtn('${c.id}_1_active', '계속');
        known(!_isRedish(labelColor('계속')) && !_isRedish(t.widget<Material>(find.ancestor(of: btn('계속'), matching: find.byType(Material)).first).color),
            '${c.id} ① 계속은 위험색 아님(다음 확인으로 가는 일반 진행)');
        await vqCapture(t, key, '${c.id}_1_active', conditions: {'state': '진행 중 공고 3개 — 1단계', 'viewport': '${c.w.toInt()}x${c.h.toInt()}', 'textScaler': c.s, 'beforeObserve': _beforeObs});
        await t.tapAt(const Offset(4, 4));
        await settle();
        expect(find.byType(Dialog), findsOneWidget, reason: '${c.id} ① 바깥 탭으로 닫히지 않는다');
        await t.tap(btn('취소'));
        await settle();
        expect(await fut, isFalse, reason: '① 취소 = false');
        fut = openA();
        await settle();
        await t.tap(btn('계속'));
        await settle();
        expect(await fut, isTrue, reason: '① 계속 = true');

        // ② 2단계 — 최종 삭제 확인(긴 이름)
        fut = openB();
        await settle();
        expect(find.byType(Dialog), findsOneWidget);
        expect(overflows, isEmpty, reason: '${c.id} ② 넘침');
        expect(find.descendant(of: find.byType(Dialog), matching: findVisibleText(kLongName)), findsOneWidget, reason: '긴 이름 전문');
        dump('${c.id}_2_delete');
        checkBtn('${c.id}_2_delete', '취소');
        checkBtn('${c.id}_2_delete', '삭제');
        await vqCapture(t, key, '${c.id}_2_delete', conditions: {'state': '최종 삭제 확인 — 긴 이름', 'viewport': '${c.w.toInt()}x${c.h.toInt()}', 'textScaler': c.s, 'beforeObserve': _beforeObs});
        await t.tapAt(const Offset(4, 4));
        await settle();
        expect(find.byType(Dialog), findsOneWidget, reason: '${c.id} ② 바깥 탭으로 닫히지 않는다');
        await t.tap(btn('취소'));
        await settle();
        expect(await fut, isFalse, reason: '② 취소 = false');
        fut = openB();
        await settle();
        await t.tap(btn('삭제'));
        await settle();
        expect(await fut, isTrue, reason: '② 삭제 = true');
        out('${c.id} done beforeObs=$_beforeObs phase=$vqPhase deleteLabelColor=${AppColors.errorDark}');
        await t.pumpWidget(const SizedBox.shrink());
      } finally {
        FlutterError.onError = prev;
      }
    });
  }
}
