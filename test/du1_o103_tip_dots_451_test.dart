// ignore_for_file: depend_on_referenced_packages
// [DU451 · 자체 판정 셀 · 표시만] DU-O103 첫 사용 안내 창 — 팁 점을 옆 글 첫 줄 가운데에(공용 FirstLineIcon · 크기 그대로).
//   before = 현재 A(tooltip_service 28b023a8 · DU433 r2 후보) / strict = 후보(4c409d11). harness 는 DU433 r2 시험(d75a3312)과 같고 측정만 바꿨다.
//   r1: TB STOP(창 닫기 단계 누락 · 점 사각형에 여백 포함) 두 가지만 고쳤다.
//   실제 진입 경로(TooltipContents.showFirstReview · showFirstApplication)로 연다. 값은 닿은 즉시 지역 값으로 남긴다.
//   기본 skip — TB before/du451-tb/DU_BEFORE_OBSERVE=451 · TA after/du451-ta/없음.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ALfit/services/tooltip_service.dart';
import 'package:ALfit/theme/app_colors.dart';
import 'package:ALfit/theme/role_theme.dart';
import 'package:ALfit/utils/text_layout.dart';

import 'support/du1_vq_capture.dart';
import 'support/visible_text.dart'; // [impl_21] TextLayout 문구는 보이는 글자로 찾는다

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

final bool _before = Platform.environment['DU_BEFORE_OBSERVE'] == '451';
final Map<String, String> _env = Platform.environment;
final bool _optIn =
    (_env['DU1_VQ_PHASE'] == 'before' && _env['DU1_VQ_RUN'] == 'du451-tb' && _env['DU_BEFORE_OBSERVE'] == '451') ||
        (_env['DU1_VQ_PHASE'] == 'after' && _env['DU1_VQ_RUN'] == 'du451-ta' && _env['DU_BEFORE_OBSERVE'] == null);
var _anyFail = false;
final String _manifest = Platform.environment['DUL_MANIFEST'] ?? '(unset)';
const _envKeys = ['DU_BEFORE_OBSERVE', 'DU1_VQ_PHASE', 'DU1_VQ_OUT', 'DU1_VQ_RUN', 'DU1_VQ_DATE', 'DU397_DIAG', 'DU397_MANIFEST', 'DU400_MANIFEST',
  'DU401_MANIFEST', 'DU398_MANIFEST', 'DU406_MANIFEST', 'DU407_MANIFEST', 'DU296_PHASE', 'DUL_MANIFEST'];
final String _envLine = [for (final k in _envKeys) '$k:${Platform.environment[k] ?? '(unset)'}'].join(',');

void _out(String s) {
  // ignore: avoid_print
  print(s);
}

String _f2(double v) => v.toStringAsFixed(2);
String _plainOf(Widget w) => w is RichText ? TextLayout.plain(w.text.toPlainText(includeSemanticsLabels: false)) : '';

/// 줄 나눔(DU432 진단 · DU433 진단과 같은 방식) — 줄 글자 · 낱말 경계 ok(명시 줄바꿈 '\n' 은 경계로 본다).

/// 글자 뒤 채움색 — 가장 가까운 불투명 Material · Container/DecoratedBox 의 BoxDecoration 색.

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  const views = [(id: 'W', w: 390.0, h: 844.0, s: 1.0), (id: 'B', w: 320.0, h: 640.0, s: 2.0)];
  const states = [
    (key: 'REVIEW', title: '첫 리뷰 작성이시네요!', icon: Icons.rate_review, tileBg: AppColors.warningBg, tileFg: AppColors.warningDark,
        tip: '평점과 태그는 지원자가 볼 수 있어요.', caption: '첫 리뷰 안내 창(amber · 팁 3) — 머리 · 확인 버튼 · 팁 묶음'),
    (key: 'APPLY', title: '첫 지원이시네요!', icon: Icons.assignment_turned_in, tileBg: AppColors.brandSurface, tileFg: AppColors.brand,
        tip: '불참이 예상되면 미리 연락해주세요.', caption: '첫 지원 안내 창(브랜드 · 팁 2) — 머리 · 확인 버튼 · 팁 묶음'),
  ];
  for (final v in views) {
    for (final st in states) {
      testWidgets('S103TD-${v.id}-${st.key} ${st.caption} — 팁 점 첫 줄 가운데', (t) async {
        if (_anyFail) fail('앞 사례 실패 — 이 사례 본문 실행 0 · 캡처 0');
        try {
          final tok = 'S103TD-${v.id}-${st.key}';
          final mode = _before ? 'before' : 'strict';
          _out('D451 $tok begin mode=$mode phase=${Platform.environment['DU1_VQ_PHASE'] ?? '(unset)'} env=$_envLine manifest=$_manifest');
          await t.runAsync(_loadFonts);
          final overflows = <String>[];
          final fwErrors = <String>[];
          final prev = FlutterError.onError;
          FlutterError.onError = (d) {
            final m = d.exceptionAsString();
            if (m.contains('overflowed')) {
              // 넘침 출처(error-causing widget 다음 두 줄)를 함께 남긴다(DU446 · 447 교훈).
              final full = d.toString();
              final k = full.indexOf('The relevant error-causing widget was');
              final loc = k < 0 ? '' : full.substring(k).split('\n').skip(1).where((l) => l.trim().isNotEmpty).take(2).map((l) => l.trim()).join(' ');
              overflows.add('${m.split('\n').first} @ $loc');
            } else {
              fwErrors.add(m.split('\n').first);
              prev?.call(d);
            }
          };
          addTearDown(() => FlutterError.onError = prev);
          t.view.physicalSize = Size(v.w, v.h);
          t.view.devicePixelRatio = 1.0;
          addTearDown(t.view.reset);
          SharedPreferences.setMockInitialValues(<String, Object>{});
          void must(String k, bool ok, [String why = '']) => expect(ok, isTrue, reason: '$tok $k $why');

          final key = GlobalKey();
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
                      onPressed: () {
                        if (st.key == 'REVIEW') {
                          TooltipContents.showFirstReview(ctx);
                        } else {
                          TooltipContents.showFirstApplication(ctx);
                        }
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
          for (var i = 0; i < 10; i++) {
            await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
            await t.pump(const Duration(milliseconds: 100));
          }
          var shots = 0;
          Future<void> shot(String sub, String state) async {
            _out('D451 $tok shot $sub ovf=${overflows.length}');
            await vqCapture(t, key, '${tok}_$sub', conditions: {
              'viewport': '${v.w.toInt()}x${v.h.toInt()}', 'textScaler': v.s, 'run': vqRun, 'manifest': _manifest, 'mode': mode, 'fixture': st.key,
              'state': state,
            });
            shots++;
          }

          final dlg = find.byType(Dialog);
          must('창 1', dlg.evaluate().length == 1, '${dlg.evaluate().length}개');
          Finder inD(Finder f) => find.descendant(of: dlg, matching: f, skipOffstage: false);
          final titleF = inD(find.byWidgetPredicate((w) => w is RichText && _plainOf(w) == st.title, skipOffstage: false));
          final iconF = inD(find.byIcon(st.icon, skipOffstage: false));
          must('제목 · 아이콘 1', titleF.evaluate().length == 1 && iconF.evaluate().length == 1,
              '${titleF.evaluate().length} ${iconF.evaluate().length}');
          await shot('1open', 'dialog-open');

          // ── 팁 점 — 점 중심과 옆 글 첫 줄 가운데 차(값은 즉시) ──
          //   before: BoxShape.circle Container(5×5) · after: 공용 FirstLineIcon 안 Icons.circle. 점이 든 Row 의 글(RichText 1)과 짝짓는다.
          final dotEls = <Element>[
            ...inD(find.byWidgetPredicate((w) => w is Container && w.decoration is BoxDecoration && (w.decoration! as BoxDecoration).shape == BoxShape.circle,
                    skipOffstage: false))
                .evaluate(),
            ...inD(find.byIcon(Icons.circle, skipOffstage: false)).evaluate(),
          ];
          var maxAbsD = 0.0;
          var paired = 0;
          var dotSize = 0.0;
          Element? lastText;
          for (final d in dotEls) {
            Element? row;
            d.visitAncestorElements((a) {
              if (a.widget is Row) {
                row = a;
                return false;
              }
              return true;
            });
            final r = row;
            if (r == null) continue;
            final texts = find
                .descendant(of: find.byElementPredicate((x) => identical(x, r), skipOffstage: false), matching: find.byType(RichText, skipOffstage: false),
                    skipOffstage: false)
                .evaluate()
                // [r2 · r1 TA STOP] Icon 도 안에서 RichText(글리프)로 그린다 — 후보의 점(FirstLineIcon 안 Icons.circle) 글리프는 뺀다(DU454 와 같은 처리 · preflight v26).
                .where((e) {
                  var inIcon = false;
                  e.visitAncestorElements((a) {
                    if (a.widget is Icon) {
                      inIcon = true;
                      return false;
                    }
                    return !identical(a, r);
                  });
                  return !inIcon && _plainOf(e.widget).trim().isNotEmpty;
                })
                .toList();
            if (texts.length != 1) continue;
            final te = texts.single;
            final rp = te.renderObject! as RenderParagraph;
            final tr = t.getRect(find.byElementPredicate((x) => identical(x, te), skipOffstage: false));
            final b0 = rp.getBoxesForSelection(const TextSelection(baseOffset: 0, extentOffset: 1)).first;
            // 점 자체 — Container 는 margin 까지 잡히므로 안의 DecoratedBox 로 잰다(Icon 은 그대로).
            final dotBox = d.widget is Container
                ? find.descendant(of: find.byElementPredicate((x) => identical(x, d), skipOffstage: false),
                        matching: find.byType(DecoratedBox, skipOffstage: false), skipOffstage: false)
                    .first
                : find.byElementPredicate((x) => identical(x, d), skipOffstage: false);
            final dr = t.getRect(dotBox);
            final dd = dr.center.dy - (tr.top + (b0.top + b0.bottom) / 2);
            if (dd.abs() > maxAbsD) maxAbsD = dd.abs();
            dotSize = dr.width;
            paired++;
            lastText = te;
          }
          final want = st.key == 'REVIEW' ? 3 : 2;
          _out('D451 $tok att dots n=${dotEls.length} paired=$paired want=$want maxAbsD=${_f2(maxAbsD)} size=${_f2(dotSize)}');

          // 마지막 팁이 보이게 굴려 한 장 더 — 측정은 위에서 끝났다.
          final lt = lastText;
          if (lt != null) {
            await t.ensureVisible(find.byElementPredicate((x) => identical(x, lt), skipOffstage: false));
            for (var i = 0; i < 5; i++) {
              await t.pump(const Duration(milliseconds: 60));
            }
          }
          await shot('2tips', 'tips-visible');

          // 창 닫기 — 열린 창의 표시 키(TooltipService._pendingKeys)가 다음 사례 창을 막지 않게(DU433 시험과 같은 단계).
          final okF = inD(findVisibleText('확인', skipOffstage: false));
          must('확인 1', okF.evaluate().length == 1, '개수 ${okF.evaluate().length}');
          await t.ensureVisible(okF);
          await t.pump(const Duration(milliseconds: 300));
          await t.tap(okF);
          for (var i = 0; i < 5; i++) {
            await t.pump(const Duration(milliseconds: 100));
          }
          must('확인 → 창 닫힘', find.byType(Dialog).evaluate().isEmpty, '창 ${find.byType(Dialog).evaluate().length}');
          must('팁 점 · 글 짝 개수', dotEls.length == want && paired == want, '점 ${dotEls.length} 짝 $paired 기대 $want');
          if (_before) {
            // 음성 기대 — base 점은 위 여백 2 · 5×5 고정이라 첫 줄 가운데보다 위(W ≈ 5 · B ≈ 14 · DU433 r2 합성).
            must('before 점 첫 줄 벗어남 검출', maxAbsD > 3, _f2(maxAbsD));
          } else {
            must('strict 점 = 첫 줄 가운데(±1.5)', maxAbsD <= 1.5, _f2(maxAbsD));
            must('strict 넘침 0', overflows.isEmpty, overflows.join(' | '));
          }
          must('미처리 framework 예외 0', fwErrors.isEmpty, '오류 $fwErrors');
          final exc = t.takeException();
          _out('D451 $tok done state=${st.key} mode=$mode captures=$shots overflows=${overflows.length} exc=${exc != null} ovfRaw=${overflows.isEmpty ? '-' : base64Url.encode(utf8.encode(overflows.join('\n'))).replaceAll('=', '')}');
          must('끝 예외 0', exc == null, '예외 $exc');
        } catch (e) {
          _anyFail = true;
          rethrow;
        }
      }, skip: !_optIn);
    }
  }
}
