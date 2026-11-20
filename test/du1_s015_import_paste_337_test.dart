// ignore_for_file: depend_on_referenced_packages
// [DU337] S015 기존 계약서로 시작(ContractImportPasteScreen) + 조항 분리 실패 시트(O094) 렌더 관측.
//   W 392x844 1.0 / B 320x640 2.0. ① 빈 화면(나누기 비활성) ② 나눌 수 없는 글 입력 ③ 나누기 → 실패 시트 · 시트 끝.
//   글자마다 **가장 가까운 불투명 바탕**(Container/DecoratedBox 색 · Material 색 · 채운 버튼 면, 반투명은 흰색 위 합성)과
//   대비를 잰다. 피할 수 있는 음절 끊김(DU335 판정식, 문단 폭보다 넓은 낱말은 강제로 따로)과 넘침도 센다.
//   단언(기본): 예외 0 · 넘침 0 · 끊김 0 · 대비 미달 0. DU_BEFORE_OBSERVE=337 이면 끊김 · 대비는 KNOWN 으로 기록만 한다.
import 'dart:io';
import 'dart:math' as math;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';

import 'package:ALfit/providers/notification_provider.dart';
import 'package:ALfit/screens/business_admin/contract_import_paste_screen.dart';
import 'package:ALfit/theme/role_theme.dart';

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

final bool _beforeObs = Platform.environment['DU_BEFORE_OBSERVE'] == '337';
const String _unparsable = '근로조건은 다음과 같다. 급여는 월말에 지급한다.';

double _lum(Color c) {
  double ch(double v) => v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * ch(c.r) + 0.7152 * ch(c.g) + 0.0722 * ch(c.b);
}

double _contrast(Color a, Color b) {
  final x = _lum(a), y = _lum(b);
  return (math.max(x, y) + 0.05) / (math.min(x, y) + 0.05);
}

Color _overWhite(Color c) => Color.alphaBlend(c, Colors.white);

/// 글자 뒤의 가장 가까운 바탕색. 못 찾으면 흰색.
Color _bgOf(Element e) {
  Color? found;
  e.visitAncestorElements((a) {
    final w = a.widget;
    Color? c;
    if (w is ButtonStyleButton) {
      final disabled = !w.enabled;
      c = w.style?.backgroundColor?.resolve(disabled ? {WidgetState.disabled} : <WidgetState>{});
      if (c == null && w is ElevatedButton) c = Theme.of(a).colorScheme.primary;
      if (c == null) return true; // 글자 버튼 · 테두리 버튼은 바탕이 투명 — 더 위로
    } else if (w is Container && w.decoration is BoxDecoration) {
      c = (w.decoration! as BoxDecoration).color;
    } else if (w is Container && w.color != null) {
      c = w.color;
    } else if (w is DecoratedBox && w.decoration is BoxDecoration) {
      c = (w.decoration as BoxDecoration).color;
    } else if (w is Material && w.type != MaterialType.transparency) {
      c = w.color ?? Theme.of(a).colorScheme.surface;
    } else if (w is ColoredBox) {
      c = w.color;
    }
    if (c == null || c.a == 0) return true;
    found = _overWhite(c);
    return false;
  });
  return found ?? Colors.white;
}

List<String> _avoidable(RenderParagraph rp, [List<String>? forced]) {
  final plain = rp.text.toPlainText();
  final ws = RegExp(r'[\s ]');
  bool isWs(String ch) => ch == '\n' || ws.hasMatch(ch);
  double wordWidth(int i) {
    var s = i, e = i;
    while (s > 0 && !isWs(plain[s - 1])) {
      s--;
    }
    while (e < plain.length && !isWs(plain[e])) {
      e++;
    }
    return rp
        .getBoxesForSelection(TextSelection(baseOffset: s, extentOffset: e))
        .fold<double>(0, (a, b) => a + (b.right - b.left));
  }

  final out = <String>[];
  double? lastTop;
  var lastIdx = -1;
  var line = StringBuffer();
  for (var i = 0; i < plain.length; i++) {
    if (plain[i] == '\n') {
      lastTop = null;
      line = StringBuffer();
      lastIdx = i;
      continue;
    }
    final bx = rp.getBoxesForSelection(TextSelection(baseOffset: i, extentOffset: i + 1));
    if (bx.isEmpty) continue;
    final top = bx.first.top;
    if (lastTop == null || top > lastTop + 1) {
      if (lastTop != null && !ws.hasMatch(plain.substring(lastIdx, i + 1)) && ws.hasMatch(line.toString().trim())) {
        if (wordWidth(i) > rp.size.width + 0.5) {
          forced?.add('${visibleText(line.toString())}|${plain[i]}');
        } else {
          out.add('${visibleText(line.toString())}|${plain[i]}');
        }
      }
      line = StringBuffer();
      lastTop = top;
    }
    line.write(plain[i]);
    lastIdx = i;
  }
  return out;
}

void main() {
  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
    await initializeDateFormatting('ko_KR');
  });

  for (final c in const [(id: 'S015-W', w: 392.0, h: 844.0, s: 1.0), (id: 'S015-B', w: 320.0, h: 640.0, s: 2.0)]) {
    testWidgets('${c.id} 기존 계약서로 시작 · 실패 시트 ${c.w.toInt()}x${c.h.toInt()}@${c.s}', (t) async {
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

        Map<String, Object?> cond(String state) =>
            {'state': state, 'viewport': '${c.w.toInt()}x${c.h.toInt()}', 'textScaler': c.s};

        await t.pumpWidget(RepaintBoundary(
          key: key,
          child: ChangeNotifierProvider<NotificationProvider>(
            create: (_) => NotificationProvider(),
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: RoleTheme.businessAdminTheme,
              builder: (ctx, child) =>
                  MediaQuery(data: MediaQuery.of(ctx).copyWith(textScaler: TextScaler.linear(c.s)), child: child!),
              home: const ContractImportPasteScreen(businessId: 'b1', templateType: 'daily'),
            ),
          ),
        ));
        for (var i = 0; i < 6; i++) {
          await t.pump(const Duration(milliseconds: 50));
        }
        expect(t.takeException(), isNull);
        var avoid = 0, low = 0;
        final forced = <String>[];
        final seen = <String>{};
        void dump(String tag) {
          for (final e in find.byType(RichText).evaluate()) {
            final rp = e.renderObject! as RenderParagraph;
            final s = visibleText(rp.text.toPlainText());
            if (s.length < 2) continue;
            final r = t.getRect(find.byElementPredicate((x) => identical(x, e)));
            if (r.bottom < 0 || r.top > c.h || r.width == 0) continue;
            final col = rp.text.style?.color;
            final bg = _bgOf(e);
            final k = '$s@${bg.toARGB32()}@${col?.toARGB32()}';
            if (seen.contains(k)) continue;
            seen.add(k);
            final av = _avoidable(rp, forced);
            final cst = col == null ? 99.0 : _contrast(_overWhite(col), bg);
            avoid += av.length;
            if (cst < 4.5) low++;
            if (av.isNotEmpty || cst < 4.5) {
              final head = s.length > 26 ? '${s.substring(0, 26)}…' : s;
              out('$tag "$head" avoidable=$av color=0x${col?.toARGB32().toRadixString(16)} bg=0x${bg.toARGB32().toRadixString(16)} contrast=${cst.toStringAsFixed(2)} size=${rp.text.style?.fontSize}');
            }
          }
        }

        // [DU343] 붙여넣기 칸 자동 완성 — 의도적으로 끈다(autofillHints null → AutofillConfiguration.disabled).
        //   기본 [] 는 켜진 상태라, hint 위젯(DU337)으로 hintText 가 비면 autofill 설정의 원문 힌트도 null 이 됐다(소급 7 §1).
        final tf = t.widget<TextField>(find.byType(TextField).first);
        final afOff = tf.autofillHints == null;
        // ignore: avoid_print
        print('KNOWN ${afOff ? 'ok' : 'NG'} ${c.id} 붙여넣기 칸 autofill 의도적 제외(autofillHints=${tf.autofillHints}) beforeObs=$_beforeObs');
        if (!_beforeObs && Platform.environment['DU_BEFORE_OBSERVE'] != '343') {
          expect(afOff, isTrue, reason: '${c.id} 붙여넣기 칸 autofill 의도적 제외');
        }
        // ① 빈 화면 — 나누기 비활성
        dump('${c.id}_empty');
        await vqCapture(t, key, '${c.id}_1_empty', conditions: cond('빈 입력 · 나누기 비활성'));

        // ② 나눌 수 없는 글 입력(사용자처럼 입력창까지 내려서)
        await t.dragUntilVisible(find.byType(TextField), find.byType(ListView).first, const Offset(0, -120));
        await t.pump(const Duration(milliseconds: 50));
        await t.enterText(find.byType(TextField).first, _unparsable);
        for (var i = 0; i < 4; i++) {
          await t.pump(const Duration(milliseconds: 50));
        }
        dump('${c.id}_typed');
        await vqCapture(t, key, '${c.id}_2_typed', conditions: cond('나눌 수 없는 글 입력 · 나누기 활성'));

        // ③ 나누기 → 실패 시트
        FocusManager.instance.primaryFocus?.unfocus();
        await t.pump(const Duration(milliseconds: 50));
        await t.tap(find.byType(ElevatedButton).first);
        for (var i = 0; i < 12; i++) {
          await t.pump(const Duration(milliseconds: 50));
        }
        expect(t.takeException(), isNull);
        expect(findVisibleText('자동으로 조항을 나누지 못했습니다.'), findsOneWidget, reason: '${c.id} 실패 시트');
        dump('${c.id}_sheet');
        await vqCapture(t, key, '${c.id}_3_sheet', conditions: cond('조항 분리 실패 시트 처음'));
        final sheetScroll = find.descendant(of: find.byType(BottomSheet), matching: find.byType(Scrollable));
        if (sheetScroll.evaluate().isNotEmpty) {
          final sp = t.state<ScrollableState>(sheetScroll.first).position;
          sp.jumpTo(sp.maxScrollExtent);
          await t.pump(const Duration(milliseconds: 50));
          dump('${c.id}_sheetEnd');
          await vqCapture(t, key, '${c.id}_4_sheet_end', conditions: cond('조항 분리 실패 시트 끝'));
        }
        expect(t.takeException(), isNull);
        out('${c.id} summary overflows=${overflows.length} $overflows avoidable=$avoid forced=${forced.length} $forced lowContrastTexts=$low beforeObs=$_beforeObs');
        out('KNOWN ${avoid == 0 ? 'ok' : 'NG'} ${c.id} 피할 수 있는 끊김 0(실측 $avoid)');
        out('KNOWN ${low == 0 ? 'ok' : 'NG'} ${c.id} 바탕 대비 미달 0(실측 $low)');
        expect(overflows, isEmpty, reason: '${c.id} 넘침');
        if (!_beforeObs) {
          expect(avoid, 0, reason: '${c.id} 피할 수 있는 끊김');
          expect(low, 0, reason: '${c.id} 바탕 대비 4.5 미만 글자');
        }
        await t.pumpWidget(const SizedBox.shrink());
      } finally {
        FlutterError.onError = prev;
      }
    });
  }
}
