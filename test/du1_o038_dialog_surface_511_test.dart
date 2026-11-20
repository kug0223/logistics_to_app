// [DU511 r3 · NDB-2 · DU-O001 판정 O038 범위 · 표시만] DU-O038 아이콘 선택 창 바탕 — 지정 없음(M3 기본 연보라) → 흰 면(AppColors.surface) 한 줄.
//   before = 현재 A(icon_picker_dialog 2afa43dc · DU438c 채택) / strict = 후보(05784582). 시험은 438c 하네스 그대로(분류 칩 잘림 · 48 ·
//   마지막 칩/격자 마지막 아이콘 실제 스크롤 · 선택됨 전문 · 하단 비겹침 · 선택 완료 반환) + 창 면 · 검색칸 · 선택 칩 색.
//   두 모드 모두 기존 계약을 단언하고, 차이는 창 면만. 환경 입력: SDK MaterialIcons 글꼴(경로 · SHA 는 prep/env_inputs.txt).
//   tok 접두 'S938OS'. 기본 skip — TB before/du511-tb/DU_BEFORE_OBSERVE=511 · TA after/du511-ta/없음.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ALfit/theme/app_colors.dart';
import 'package:ALfit/theme/role_theme.dart';
import 'package:ALfit/utils/text_layout.dart';
import 'package:ALfit/widgets/pickers/icon_picker_dialog.dart';

import 'support/du1_vq_capture.dart';

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

final bool _before = Platform.environment['DU_BEFORE_OBSERVE'] == '511';
final Map<String, String> _env = Platform.environment;
final bool _optIn =
    (_env['DU1_VQ_PHASE'] == 'before' && _env['DU1_VQ_RUN'] == 'du511-tb' && _env['DU_BEFORE_OBSERVE'] == '511') ||
        (_env['DU1_VQ_PHASE'] == 'after' && _env['DU1_VQ_RUN'] == 'du511-ta' && _env['DU_BEFORE_OBSERVE'] == null);
var _anyFail = false;
final String _manifest = Platform.environment['DUL_MANIFEST'] ?? '(unset)';
const _envKeys = ['DU_BEFORE_OBSERVE', 'DU1_VQ_PHASE', 'DU1_VQ_OUT', 'DU1_VQ_RUN', 'DU1_VQ_DATE', 'DU397_DIAG', 'DU397_MANIFEST', 'DU400_MANIFEST',
  'DU401_MANIFEST', 'DU398_MANIFEST', 'DU406_MANIFEST', 'DU407_MANIFEST', 'DU296_PHASE', 'DUL_MANIFEST'];
final String _envLine = [for (final k in _envKeys) '$k:${Platform.environment[k] ?? '(unset)'}'].join(',');

void _out(String s) {
  // ignore: avoid_print
  print(s);
}

String _plainOf(Widget w) => w is RichText ? TextLayout.plain(w.text.toPlainText(includeSemanticsLabels: false)) : '';
String _f1(double v) => v.toStringAsFixed(1);

const _cats = ['전체', '물류/배송', '음식/음료', '청소/관리', '도구/작업', '사무/문서', '시간/일정', '사람/팀', '상태/액션', '건물/장소', '교통/이동',
  '금융/결제', '농업/자연', '서비스/뷰티', '스포츠/이벤트'];

void main() {
  setUpAll(() async {});
  const views = [(id: 'W', w: 390.0, h: 844.0, s: 1.0), (id: 'B', w: 320.0, h: 640.0, s: 2.0)];
  for (final v in views) {
    testWidgets('S938OS-${v.id}-SURF 아이콘 선택 창 바탕 — 흰 면 · 분류 칩 · 격자 · 반환 계약 유지', (t) async {
      if (_anyFail) fail('앞 사례 실패 — 이 사례 본문 실행 0 · 캡처 0');
      try {
        final tok = 'S938OS-${v.id}-SURF';
        final mode = _before ? 'before' : 'strict';
        _out('D511 $tok begin mode=$mode phase=${Platform.environment['DU1_VQ_PHASE'] ?? '(unset)'} env=$_envLine manifest=$_manifest');
        await t.runAsync(_loadFonts);
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

        final key = GlobalKey();
        IconItem? picked;
        var returned = false;
        await t.pumpWidget(RepaintBoundary(
          key: key,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: RoleTheme.businessAdminTheme,
            builder: (ctx, child) => MediaQuery(data: MediaQuery.of(ctx).copyWith(textScaler: TextScaler.linear(v.s)), child: child!),
            home: Scaffold(
              body: Builder(
                builder: (ctx) => Center(
                  child: TextButton(
                    onPressed: () async {
                      picked = await IconPickerDialog.show(context: ctx);
                      returned = true;
                    },
                    child: const Text('열기'),
                  ),
                ),
              ),
            ),
          ),
        ));
        await t.pump();
        await t.tap(find.text('열기'));
        for (var i = 0; i < 8; i++) {
          await t.pump(const Duration(milliseconds: 100));
        }
        var shots = 0;
        Future<void> shot(String sub, String state) async {
          _out('D511 $tok shot $sub ovf=${overflows.length}');
          await vqCapture(t, key, '${tok}_$sub', conditions: {
            'viewport': '${v.w.toInt()}x${v.h.toInt()}', 'textScaler': v.s, 'run': vqRun, 'manifest': _manifest, 'mode': mode, 'fixture': 'SURF',
            'state': state,
          });
          shots++;
        }

        final dlg = find.byType(Dialog);
        must('창 1', dlg.evaluate().length == 1, '창 ${dlg.evaluate().length}');
        Finder inD(Finder f) => find.descendant(of: dlg, matching: f, skipOffstage: false);
        Finder rtD(bool Function(String p) p) => inD(find.byWidgetPredicate((w) => w is RichText && p(_plainOf(w)), skipOffstage: false));
        Element? nearest(Element e, bool Function(Widget w) test) {
          Element? hit;
          e.visitAncestorElements((a) {
            if (test(a.widget)) {
              hit = a;
              return false;
            }
            return true;
          });
          return hit;
        }

        // ── 분류 칩 줄(가로 Scrollable) ──
        final anchor = rtD((p) => p == '물류/배송');
        must('분류 칩 물류/배송 1', anchor.evaluate().length == 1, '개수 ${anchor.evaluate().length}');
        final rowScEl = nearest(anchor.evaluate().first, (w) => w is Scrollable && w.axisDirection == AxisDirection.right);
        must('분류 칩 가로 스크롤 1', rowScEl != null, '없음');
        final rowSc = find.byElementPredicate((x) => identical(x, rowScEl));
        final rowBox = rowScEl!.renderObject! as RenderBox;
        final rowH = rowBox.size.height;
        // 칩마다(그려진 것만) 글자 잘림 · 필요 높이(글자 줄 상자 + 칩 위아래 여백 + 테두리) · 누르는 자리.
        var built = 0, clip = 0;
        var need = 0.0, recv = double.infinity;
        for (final c in _cats) {
          final f = find.descendant(of: rowSc, matching: find.byWidgetPredicate((w) => w is RichText && _plainOf(w) == c, skipOffstage: false), skipOffstage: false);
          if (f.evaluate().length != 1) continue;
          built++;
          final rp = f.evaluate().first.renderObject! as RenderParagraph;
          final want = rp.getMaxIntrinsicHeight(double.infinity);
          if (rp.size.height + 0.5 < want) clip++;
          final box = nearest(f.evaluate().first, (w) => w is AnimatedContainer);
          final pad = box == null ? 0.0 : ((box.widget as AnimatedContainer).padding?.resolve(TextDirection.ltr).vertical ?? 0.0);
          need = math.max(need, want + pad + 3.0);
          final g = nearest(f.evaluate().first, (w) => w is GestureDetector);
          final gro = g?.renderObject;
          if (gro is RenderBox && gro.hasSize) recv = math.min(recv, gro.size.height);
        }
        if (recv == double.infinity) recv = 0;
        _out('D511 $tok att chips n=$built clip=$clip rowH=${_f1(rowH)} need=${_f1(need)} recv=${_f1(recv)}');
        // [r3] 창 면(Dialog 첫 Material) · 검색칸 채움 · 선택된 분류 칩 '전체' 면 — 측정 시점 값으로 잡는다(v34).
        String ctok(Color? c) => c == null
            ? 'none'
            : c.toARGB32() == AppColors.surface.toARGB32()
                ? 'white'
                : c.toARGB32() == AppColors.grey100.toARGB32()
                    ? 'grey100'
                    : c.toARGB32() == AppColors.brand.toARGB32()
                        ? 'brand'
                        : 'x${c.toARGB32().toRadixString(16).padLeft(8, '0')}';
        final shellC = t.widget<Material>(find.descendant(of: dlg, matching: find.byType(Material), skipOffstage: false).first).color;
        final tfEls = find.descendant(of: dlg, matching: find.byType(TextField), skipOffstage: false).evaluate().toList();
        final searchC = tfEls.length == 1 ? (tfEls.first.widget as TextField).decoration?.fillColor : null;
        final selT = find.descendant(of: rowSc, matching: find.byWidgetPredicate((w) => w is RichText && _plainOf(w) == '전체', skipOffstage: false), skipOffstage: false).evaluate().toList();
        final selBox = selT.length == 1 ? nearest(selT.first, (w) => w is AnimatedContainer) : null;
        final selC = selBox == null ? null : ((selBox.widget as AnimatedContainer).decoration as BoxDecoration?)?.color;
        final shellT = ctok(shellC), searchT = ctok(searchC), chipT = ctok(selC);
        _out('D511 $tok att surf shell=$shellT search=$searchT chip=$chipT');
        await shot('1open', 'category-row-open');

        // ── 마지막 분류 칩 — 실제 가로 스크롤 → 중심 hit → 탭 → 선택(흰 글자) ──
        final lastF = find.descendant(of: rowSc, matching: find.byWidgetPredicate((w) => w is RichText && _plainOf(w) == _cats.last, skipOffstage: false), skipOffstage: false);
        var lastReach = false, lastSel = false;
        try {
          await t.scrollUntilVisible(lastF, 80, scrollable: rowSc, maxScrolls: 60);
        } catch (_) {}
        await t.pump(const Duration(milliseconds: 100));
        if (lastF.evaluate().length == 1) {
          final g = nearest(lastF.evaluate().first, (w) => w is GestureDetector);
          final gro = g?.renderObject;
          if (gro is RenderBox && gro.hasSize) {
            final c = gro.localToGlobal(gro.size.center(Offset.zero));
            lastReach = (Offset.zero & Size(v.w, v.h)).contains(c) && t.hitTestOnBinding(c).path.any((h) => identical(h.target, gro));
            if (lastReach) {
              await t.tapAt(c);
              for (var i = 0; i < 4; i++) {
                await t.pump(const Duration(milliseconds: 100));
              }
              final now = find.descendant(of: rowSc, matching: find.byWidgetPredicate((w) => w is RichText && _plainOf(w) == _cats.last, skipOffstage: false), skipOffstage: false);
              lastSel = now.evaluate().length == 1 && (t.widget(now) as RichText).text.style?.color == Colors.white;
            }
          }
        }
        _out('D511 $tok att last reach=$lastReach sel=$lastSel');

        // ── 그 분류 격자의 마지막 아이콘 — 실제 스크롤 → 탭 → '… 선택됨' 전문 ──
        final gridScEl = find.descendant(of: dlg, matching: find.byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.down), skipOffstage: false)
            .evaluate()
            .where((e) => find.descendant(of: find.byElementPredicate((x) => identical(x, e)), matching: find.byType(GridView), skipOffstage: false).evaluate().isEmpty &&
                nearest(e, (w) => w is GridView) != null)
            .toList();
        final sportIcons = IconPickerDialog.getAllIcons().where((i) => i.category == _cats.last).toList();
        var gridReach = false, chosen = false, chosenFull = false;
        var chosenLabel = '-';
        if (gridScEl.length == 1 && sportIcons.isNotEmpty) {
          final gsc = find.byElementPredicate((x) => identical(x, gridScEl.first));
          final lastIcon = sportIcons.last;
          final iconF = find.descendant(of: gsc, matching: find.byIcon(lastIcon.icon, skipOffstage: false), skipOffstage: false);
          try {
            await t.scrollUntilVisible(iconF, 120, scrollable: gsc, maxScrolls: 60);
          } catch (_) {}
          await t.pump(const Duration(milliseconds: 100));
          if (iconF.evaluate().isNotEmpty) {
            final ib = iconF.evaluate().first.renderObject! as RenderBox;
            final c = ib.localToGlobal(ib.size.center(Offset.zero));
            gridReach = (Offset.zero & Size(v.w, v.h)).contains(c) && t.hitTestOnBinding(c).path.isNotEmpty;
            if (gridReach) {
              await t.tapAt(c);
              for (var i = 0; i < 4; i++) {
                await t.pump(const Duration(milliseconds: 100));
              }
              chosenLabel = lastIcon.label;
              final chF = rtD((p) => p == '${lastIcon.label} 선택됨');
              chosen = chF.evaluate().length == 1;
              if (chosen) {
                final rp = chF.evaluate().first.renderObject! as RenderParagraph;
                chosenFull = !rp.didExceedMaxLines && rp.size.height + 0.5 >= rp.getMaxIntrinsicHeight(rp.size.width);
              }
            }
          }
        }
        _out('D511 $tok att grid reach=$gridReach chosen=$chosen full=$chosenFull');
        // ── 하단('선택 완료')과 격자 비겹침 ──
        final okF = rtD((p) => p == '선택 완료');
        var gap = -999.0;
        if (okF.evaluate().length == 1 && gridScEl.length == 1) {
          final gb = gridScEl.first.renderObject! as RenderBox;
          final gridBottom = gb.localToGlobal(Offset(0, gb.size.height)).dy;
          final ob = nearest(okF.evaluate().first, (w) => w is InkWell || w is GestureDetector || w is ButtonStyleButton)?.renderObject;
          if (ob is RenderBox && ob.hasSize) gap = ob.localToGlobal(Offset.zero).dy - gridBottom;
        }
        _out('D511 $tok att footer gap=${_f1(gap)}');
        await shot('2last', 'last-category-last-icon');
        // ── '선택 완료' → 닫힘 · 반환값 = 고른 아이콘 ──
        var closed = false, retOk = false;
        if (okF.evaluate().length == 1) {
          await t.ensureVisible(okF.first);
          await t.pump(const Duration(milliseconds: 100));
          await t.tap(okF.first, warnIfMissed: false);
          for (var i = 0; i < 8; i++) {
            await t.pump(const Duration(milliseconds: 100));
          }
          closed = find.byType(Dialog).evaluate().isEmpty;
          retOk = returned && picked?.label == chosenLabel;
        }
        _out('D511 $tok att ret closed=$closed ok=$retOk');
        FlutterError.onError = prev;
        // 기존 계약(438c 채택) — 두 모드 공통.
        must('계약 분류 칩 잘림 0 · 줄 높이 ≥ 필요 높이 · 누르는 자리 ≥ 48', clip == 0 && rowH + 0.5 >= need && recv >= 48 - 0.01, 'clip $clip rowH ${_f1(rowH)} need ${_f1(need)} recv ${_f1(recv)}');
        must('계약 마지막 분류 칩 도달 · 선택', lastReach && lastSel, '$lastReach $lastSel');
        must('계약 격자 마지막 아이콘 도달 · 선택됨 전문', gridReach && chosen && chosenFull, '$gridReach $chosen $chosenFull');
        must('계약 하단 · 격자 비겹침', gap >= -0.5, _f1(gap));
        must('계약 선택 완료 → 닫힘 · 반환값', closed && retOk, '$closed $retOk');
        must('계약 검색칸 grey100 · 선택 칩 brand', searchT == 'grey100' && chipT == 'brand', '$searchT $chipT');
        if (_before) {
          // 음성 기대(코드 확정 · base 바탕 미지정 → M3 기본 면 · r2 TB 관측 xffe9e7ef) — 흰 면 아님.
          must('before 창 면 흰색 아님', shellT != 'white', shellT);
        } else {
          must('strict 창 면 흰색', shellT == 'white', shellT);
          must('strict 넘침 0', overflows.isEmpty, overflows.join(' | '));
        }
        must('미처리 framework 예외 0', fwErrors.isEmpty, '오류 $fwErrors');
        final exc = t.takeException();
        _out('D511 $tok done state=SURF mode=$mode captures=$shots overflows=${overflows.length} exc=${exc != null} ovfRaw=${overflows.isEmpty ? '-' : base64Url.encode(utf8.encode(overflows.join('\n'))).replaceAll('=', '')}');
        must('끝 예외 0', exc == null, '예외 $exc');
      } catch (e) {
        _anyFail = true;
        rethrow;
      }
    }, skip: !_optIn);
  }
}
