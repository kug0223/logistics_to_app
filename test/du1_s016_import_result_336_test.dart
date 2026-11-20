// ignore_for_file: depend_on_referenced_packages
// [DU336] S016 계약서 가져온 내용 확인(ContractImportResultScreen) 렌더 관측 — 실제 파서(ArticleParser.parse) 결과로 띄운다.
//   자료: 제1~3조(자동 작성 범위) · 제4조 연장수당(겹침 경고) · 제5조 긴 비밀유지 · 제6조 연락처(개인정보).
//   W 392x844 1.0 / B 320x640 2.0. 처음(위 · 끝) + 긴 조항 '전문 보기' 펼침 뒤. 넘침 · 피할 수 있는 음절 끊김 ·
//   흰 바탕 대비 < 4.5 글자 · '전문 보기/접기' 터치 높이를 기록한다.
//   단언(기본): 예외 0 · 넘침 0 · 끊김 0 · 대비 미달 0 · 펼침 컨트롤 48 · 펼침이 포함 여부를 바꾸지 않음.
//   DU_BEFORE_OBSERVE=336 이면 넘침 · 끊김 · 대비 · 48 은 KNOWN 으로 기록만 한다.
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
import 'package:ALfit/screens/business_admin/contract_import_result_screen.dart';
import 'package:ALfit/theme/role_theme.dart';
import 'package:ALfit/utils/contract_article_parser.dart';

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

final bool _beforeObs = Platform.environment['DU_BEFORE_OBSERVE'] == '336';

const _pasted = '''
표준 근로계약서

제1조 (근로계약 당사자)
사업주와 근로자는 다음과 같이 근로계약을 체결한다.

제2조 (근무 조건)
근무 장소는 사업장 소재지로 하며, 업무는 분류 및 포장 작업으로 한다.

제3조 (임금)
시급은 최저임금 이상으로 하며 매월 25일 근로자 명의 계좌로 지급한다.

제4조 (연장·야간근로 수당)
1일 8시간을 초과하는 근로에 대하여는 통상임금의 100분의 50 이상을 가산하여 지급한다. 야간근로(22시부터 익일 06시까지)에 대하여도 동일하게 가산하며, 연장·야간·휴일근로가 중복되는 경우 각각의 가산수당을 합산하여 지급한다.

제5조 (비밀 유지)
근로자는 재직 중은 물론 퇴직 후에도 업무상 알게 된 사업장의 영업비밀과 고객 정보를 외부에 누설하거나 부정하게 사용하여서는 아니 된다. 이를 위반하여 사업장에 손해를 끼친 경우 관계 법령에 따라 책임을 진다.

제6조 (비상 연락)
근무 중 사고가 발생하면 현장 책임자 김관리(010-1234-5678)에게 즉시 알린다.
''';

double _lum(Color c) {
  double ch(double v) => v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * ch(c.r) + 0.7152 * ch(c.g) + 0.0722 * ch(c.b);
}

double _contrast(Color a, Color b) {
  final x = _lum(a), y = _lum(b);
  return (math.max(x, y) + 0.05) / (math.min(x, y) + 0.05);
}

/// 피할 수 있는 끊김: 줄이 바뀐 자리가 낱말 안이고 그 줄에 공백이 있었다. 낱말 자체가 문단 폭보다 넓으면 강제 끊김으로 따로 센다(DU335 판정식).
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

  for (final c in const [(id: 'S016-W', w: 392.0, h: 844.0, s: 1.0), (id: 'S016-B', w: 320.0, h: 640.0, s: 2.0)]) {
    testWidgets('${c.id} 가져온 내용 확인 ${c.w.toInt()}x${c.h.toInt()}@${c.s}', (t) async {
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

        final result = ArticleParser.parse(_pasted);
        out('${c.id} parse total=${result.totalCount} system=${result.systemRangeCount} dup=${result.likelyDuplicateCount} pii=${result.hasAnyPii} '
            'articles=${result.articles.map((a) => '${a.articleNumber}:${a.included ? 'in' : 'out'}:${a.warnings.map((w) => w.name).join('+')}').join(', ')}');
        final includedBefore = result.articles.map((a) => a.included).toList();

        await t.pumpWidget(RepaintBoundary(
          key: key,
          child: ChangeNotifierProvider<NotificationProvider>(
            create: (_) => NotificationProvider(),
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: RoleTheme.businessAdminTheme,
              builder: (ctx, child) =>
                  MediaQuery(data: MediaQuery.of(ctx).copyWith(textScaler: TextScaler.linear(c.s)), child: child!),
              home: ContractImportResultScreen(businessId: 'b1', templateType: 'daily', parseResult: result),
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
            if (s.length < 2 || seen.contains(s)) continue;
            final self = find.byElementPredicate((x) => identical(x, e));
            final r = t.getRect(self);
            if (r.bottom < 0 || r.top > c.h) continue;
            seen.add(s);
            final av = _avoidable(rp, forced);
            final col = rp.text.style?.color;
            // [DU336 시험 수리 1/3] 채운 버튼(ElevatedButton) 안 글자는 흰 바탕이 아니라 버튼 면 위다 — 그 면과 잰다.
            final filled = find.ancestor(of: self, matching: find.byWidgetPredicate((w) => w is ElevatedButton));
            Color bg = Colors.white;
            if (filled.evaluate().isNotEmpty) {
              final st = t.widget<ElevatedButton>(filled.first).style;
              bg = st?.backgroundColor?.resolve(<WidgetState>{}) ?? Theme.of(e).colorScheme.primary;
            }
            final cst = col == null ? 99.0 : _contrast(col, bg);
            avoid += av.length;
            if (cst < 4.5) low++;
            if (av.isNotEmpty || cst < 4.5) {
              final head = s.length > 26 ? '${s.substring(0, 26)}…' : s;
              out('$tag "$head" avoidable=$av color=$col contrastOnWhite=${cst.toStringAsFixed(2)} size=${rp.text.style?.fontSize}');
            }
          }
        }

        dump('${c.id}_top');
        await vqCapture(t, key, '${c.id}_1_top', conditions: {'state': '처음(파서 기본 포함)', 'viewport': '${c.w.toInt()}x${c.h.toInt()}', 'textScaler': c.s});

        // [DU336 시험 수리 1/3] 목록은 지연 생성(ListView)이라 한 번에 다 보이지 않는다 — 반 화면씩 끝까지 내리며 전수 기록한 뒤 맨 위로.
        final sc = find.byType(Scrollable).first;
        final pos = t.state<ScrollableState>(sc).position;
        while (pos.pixels < pos.maxScrollExtent - 0.5) {
          pos.jumpTo(math.min(pos.pixels + c.h * 0.5, pos.maxScrollExtent));
          await t.pump(const Duration(milliseconds: 50));
          dump('${c.id}_walk');
        }
        expect(overflows.where((o) => o.contains('overflowed')).length, overflows.length);
        pos.jumpTo(0);
        await t.pump(const Duration(milliseconds: 50));

        // 긴 조항 '전문 보기' — 터치 높이 · hit · 펼침이 포함 여부를 바꾸지 않음
        final more = findVisibleText('전문 보기');
        var minH = 999.0;
        // [DU336 시험 수리 2/3] `.first` finder 는 일치가 없으면 바로 No element 를 던진다(TB_dbg) — 생길 때까지 내린 뒤 첫 것을 화면 안으로.
        for (var k = 0; k < 60 && more.evaluate().isEmpty; k++) {
          await t.drag(sc, const Offset(0, -120));
          await t.pump(const Duration(milliseconds: 50));
        }
        final found = more.evaluate().isNotEmpty;
        if (found) {
          await t.ensureVisible(more.first);
          await t.pump(const Duration(milliseconds: 50));
        }
        out('${c.id} 전문보기 찾음=$found 개수=${more.evaluate().length}');
        if (found) {
          for (var i = 0; i < 4; i++) {
            await t.pump(const Duration(milliseconds: 50));
          }
          final recv = find.ancestor(of: more.first, matching: find.byType(GestureDetector)).first;
          final rr = t.getRect(recv);
          minH = rr.height;
          final hit = HitTestResult();
          WidgetsBinding.instance.hitTestInView(hit, Offset(rr.left + 4, rr.center.dy), t.view.viewId);
          out('${c.id} 전문보기 receiver=$rr h=${rr.height.toStringAsFixed(1)} hitPath=${hit.path.length}');
          await t.tap(more.first);
          for (var i = 0; i < 6; i++) {
            await t.pump(const Duration(milliseconds: 50));
          }
          expect(t.takeException(), isNull);
          expect(result.articles.map((a) => a.included).toList(), includedBefore, reason: '${c.id} 펼침은 포함 여부를 바꾸지 않는다');
          dump('${c.id}_expanded');
          await vqCapture(t, key, '${c.id}_2_expanded', conditions: {'state': '긴 조항 전문 보기 펼침', 'viewport': '${c.w.toInt()}x${c.h.toInt()}', 'textScaler': c.s});
        }
        await t.drag(sc, Offset(0, -c.h * 4));
        for (var i = 0; i < 6; i++) {
          await t.pump(const Duration(milliseconds: 50));
        }
        dump('${c.id}_end');
        await vqCapture(t, key, '${c.id}_3_end', conditions: {'state': '끝', 'viewport': '${c.w.toInt()}x${c.h.toInt()}', 'textScaler': c.s});
        expect(t.takeException(), isNull);
        out('${c.id} summary overflows=${overflows.length} $overflows avoidable=$avoid forced=${forced.length} $forced lowContrastTexts=$low expandMinH=${minH.toStringAsFixed(1)} beforeObs=$_beforeObs');
        out('KNOWN ${overflows.isEmpty ? 'ok' : 'NG'} ${c.id} 넘침 0(실측 ${overflows.length})');
        out('KNOWN ${avoid == 0 ? 'ok' : 'NG'} ${c.id} 피할 수 있는 끊김 0(실측 $avoid)');
        out('KNOWN ${low == 0 ? 'ok' : 'NG'} ${c.id} 흰 바탕 대비 미달 0(실측 $low)');
        out('KNOWN ${minH >= 48 - 1e-6 ? 'ok' : 'NG'} ${c.id} 전문 보기 터치 48(실측 ${minH.toStringAsFixed(1)})');
        if (!_beforeObs) {
          expect(overflows, isEmpty, reason: '${c.id} 넘침');
          expect(avoid, 0, reason: '${c.id} 피할 수 있는 끊김');
          expect(low, 0, reason: '${c.id} 흰 바탕 대비 4.5 미만 글자');
          expect(minH, greaterThanOrEqualTo(48 - 1e-6), reason: '${c.id} 전문 보기 터치 높이');
        }
        await t.pumpWidget(const SizedBox.shrink());
      } finally {
        FlutterError.onError = prev;
      }
    });
  }
}
