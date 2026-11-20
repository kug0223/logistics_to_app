// ignore_for_file: depend_on_referenced_packages
// [DU335] S019 계약서 양식 미리보기(ContractTemplatePreviewScreen) 렌더 관측 — 시스템 기본 조항(단기 · 기간제) 양식.
//   W 392x844 1.0 / B 320x640 2.0, 위 · 가운데 · 끝 캡처. 문단별 피할 수 있는 음절 끊김과 흰 바탕 대비 < 4.5 글자를 기록한다.
//   단언(기본): 넘침 0 · 예외 0 · 피할 수 있는 끊김 0 · 대비 미달 0. DU_BEFORE_OBSERVE=335 이면 끊김 · 대비는 KNOWN 으로 기록만 한다.
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

import 'package:ALfit/models/core/contract_template_model.dart';
import 'package:ALfit/providers/notification_provider.dart';
import 'package:ALfit/screens/business_admin/contract_template_preview_screen.dart';
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

final bool _beforeObs = Platform.environment['DU_BEFORE_OBSERVE'] == '335';

double _lum(Color c) {
  double ch(double v) => v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * ch(c.r) + 0.7152 * ch(c.g) + 0.0722 * ch(c.b);
}

double _contrast(Color a, Color b) {
  final x = _lum(a), y = _lum(b);
  return (math.max(x, y) + 0.05) / (math.min(x, y) + 0.05);
}

/// 줄이 바뀐 자리 앞뒤가 모두 공백이 아니고(낱말 안), 그 줄에 공백이 있었다면(낱말 경계에서 바꿀 수 있었다면) 피할 수 있는 끊김이다.
///   [DU335 시험 수리 1/3] 단, 그 낱말 자체가 문단 폭보다 넓으면('기간제및단시간근로자보호법,') 어디서든 낱말 안에서 끊길 수밖에 없다 —
///   피할 수 없는 강제 끊김으로 [forced] 에 따로 기록한다(글자 축소 · 문구 변경 없이는 없앨 수 없다).
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

ContractTemplateModel _tpl(String type) => ContractTemplateModel(
    id: 't-$type', businessId: 'b1', name: '기본 양식', templateType: type,
    articles: ContractTemplateModel.defaultArticlesFor(type), createdAt: DateTime(2026, 11, 1));

void main() {
  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
    await initializeDateFormatting('ko_KR');
  });

  for (final c in const [
    (id: 'S019-W', w: 392.0, h: 844.0, s: 1.0, type: 'daily'),
    (id: 'S019-B', w: 320.0, h: 640.0, s: 2.0, type: 'daily'),
    (id: 'S019-PB', w: 320.0, h: 640.0, s: 2.0, type: 'period'),
  ]) {
    testWidgets('${c.id} 계약서 양식 미리보기 ${c.type} ${c.w.toInt()}x${c.h.toInt()}@${c.s}', (t) async {
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

        await t.pumpWidget(RepaintBoundary(
          key: key,
          child: ChangeNotifierProvider<NotificationProvider>(
            create: (_) => NotificationProvider(),
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: RoleTheme.businessAdminTheme,
              builder: (ctx, child) =>
                  MediaQuery(data: MediaQuery.of(ctx).copyWith(textScaler: TextScaler.linear(c.s)), child: child!),
              home: ContractTemplatePreviewScreen(template: _tpl(c.type)),
            ),
          ),
        ));
        for (var i = 0; i < 6; i++) {
          await t.pump(const Duration(milliseconds: 50));
        }
        expect(t.takeException(), isNull);
        expect(overflows, isEmpty, reason: '${c.id} 넘침');
        // 본문은 SingleChildScrollView 라 화면 밖 문단도 배치돼 있다 — 한 번에 전수 기록한다.
        var avoid = 0, low = 0, paras = 0;
        final forced = <String>[];
        final seen = <String>{};
        for (final e in find.byType(RichText).evaluate()) {
          final rp = e.renderObject! as RenderParagraph;
          final s = visibleText(rp.text.toPlainText());
          if (s.length < 2 || seen.contains(s)) continue;
          seen.add(s);
          paras++;
          final av = _avoidable(rp, forced);
          final col = rp.text.style?.color;
          final cst = col == null ? 99.0 : _contrast(col, Colors.white);
          if (av.isNotEmpty) avoid += av.length;
          if (cst < 4.5) low++;
          if (av.isNotEmpty || cst < 4.5) {
            final head = s.length > 24 ? '${s.substring(0, 24)}…' : s;
            out('${c.id} "$head" avoidable=$av color=$col contrastOnWhite=${cst.toStringAsFixed(2)} size=${rp.text.style?.fontSize}');
          }
        }
        // [DU335] 원문 동일성(보완기록 5 본문 조판 조건) — 조항마다 제목 · 본문의 화면 글자(표시 제어 문자 제외)와
        //   낭독 이름(semanticsLabel)이 모두 원문과 같다. 줄바꿈 · 번호 · 구두점 · 순서가 그대로라는 뜻이다.
        var same = 0;
        for (final a in _tpl(c.type).articles) {
          for (final s in [a.title, a.content]) {
            final f = find.byWidgetPredicate((w) => w is Text && w.semanticsLabel == s && visibleText(w.data ?? '') == s);
            expect(f, findsOneWidget, reason: '${c.id} 원문 동일성: ${s.length > 16 ? s.substring(0, 16) : s}');
            same++;
          }
        }
        out('${c.id} 원문 동일성 조항 제목 · 본문 $same개 일치');
        await vqCapture(t, key, '${c.id}_1_top', conditions: {'template': c.type, 'viewport': '${c.w.toInt()}x${c.h.toInt()}', 'textScaler': c.s});
        final sc = find.byType(Scrollable).first;
        final pos = t.state<ScrollableState>(sc).position;
        pos.jumpTo(pos.maxScrollExtent * 0.45);
        await t.pump(const Duration(milliseconds: 50));
        await vqCapture(t, key, '${c.id}_2_mid', conditions: {'template': c.type, 'scroll': '45%', 'viewport': '${c.w.toInt()}x${c.h.toInt()}', 'textScaler': c.s});
        pos.jumpTo(pos.maxScrollExtent);
        await t.pump(const Duration(milliseconds: 50));
        await vqCapture(t, key, '${c.id}_3_end', conditions: {'template': c.type, 'scroll': 'end', 'viewport': '${c.w.toInt()}x${c.h.toInt()}', 'textScaler': c.s});
        expect(overflows, isEmpty, reason: '${c.id} 넘침(스크롤 뒤)');
        out('${c.id} summary paragraphs=$paras avoidable=$avoid forced=${forced.length} $forced lowContrastTexts=$low beforeObs=$_beforeObs');
        out('KNOWN ${avoid == 0 ? 'ok' : 'NG'} ${c.id} 피할 수 있는 끊김 0(실측 $avoid)');
        out('KNOWN ${low == 0 ? 'ok' : 'NG'} ${c.id} 흰 바탕 대비 미달 0(실측 $low)');
        if (!_beforeObs) {
          expect(avoid, 0, reason: '${c.id} 피할 수 있는 끊김');
          expect(low, 0, reason: '${c.id} 흰 바탕 대비 4.5 미만 글자');
        }
        await t.pumpWidget(const SizedBox.shrink());
      } finally {
        FlutterError.onError = prev;
      }
    });
  }
}
