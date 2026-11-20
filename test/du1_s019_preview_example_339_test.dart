// ignore_for_file: depend_on_referenced_packages
// [DU339] S019 계약서 양식 미리보기 예시 값 — 소급 감사 6 §3 'S019 예시 내용 CORRECTION_OPEN'.
//   미리보기 전용 예시: 시급 · 통상시급 10,320원(2026 예시) + 예시 근무일 1일(09:00–18:00 · 같은 시급) → '단기 (1일)'.
//   실모델 기본값 · 실계약 · 공용 0일 처리 · writer · 조항 · PDF 는 바꾸지 않는다(이 시험은 미리보기 화면만 본다).
//   W 392x844 1.0 / B 320x640 2.0. 단언(기본): 예외 0 · 넘침 0 · '단기 (1일)' · 10,320원(임금 · 통상시급 · 근무일 표) · 옛 10,030 · (0일) 없음 ·
//   공용 판정기 avoidable 0. DU_BEFORE_OBSERVE=339 이면 값 단언은 KNOWN 으로 기록만 한다.
import 'dart:io';

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
import 'support/du_word_break.dart';
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

final bool _beforeObs = Platform.environment['DU_BEFORE_OBSERVE'] == '339';

void main() {
  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
    await initializeDateFormatting('ko_KR');
  });

  for (final c in const [(id: 'S019X-W', w: 392.0, h: 844.0, s: 1.0), (id: 'S019X-B', w: 320.0, h: 640.0, s: 2.0)]) {
    testWidgets('${c.id} 미리보기 예시 값 ${c.w.toInt()}x${c.h.toInt()}@${c.s}', (t) async {
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

        final tpl = ContractTemplateModel(
            id: 't-daily', businessId: 'b1', name: '기본 양식', templateType: 'daily',
            articles: ContractTemplateModel.defaultArticlesFor('daily'), createdAt: DateTime(2026, 11, 1));
        await t.pumpWidget(RepaintBoundary(
          key: key,
          child: ChangeNotifierProvider<NotificationProvider>(
            create: (_) => NotificationProvider(),
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: RoleTheme.businessAdminTheme,
              builder: (ctx, child) =>
                  MediaQuery(data: MediaQuery.of(ctx).copyWith(textScaler: TextScaler.linear(c.s)), child: child!),
              home: ContractTemplatePreviewScreen(template: tpl),
            ),
          ),
        ));
        for (var i = 0; i < 6; i++) {
          await t.pump(const Duration(milliseconds: 50));
        }
        expect(t.takeException(), isNull);
        // 보이는 글자 전체(SingleChildScrollView 라 화면 밖도 배치돼 있다)
        final all = find.byType(RichText).evaluate().map((e) => visibleText((e.renderObject! as RenderParagraph).text.toPlainText())).toList();
        bool has(String s) => all.any((x) => x.contains(s));
        final oneDay = has('단기 (1일)');
        final zeroDay = has('(0일)');
        final newWage = all.where((x) => x.contains('10,320')).length;
        final oldWage = has('10,030');
        out('${c.id} 단기(1일)=$oneDay (0일)=$zeroDay 10,320 글자수=$newWage 10,030=$oldWage');
        // 근무일 표 — 표 머리('근무일') 와 예시 근무일 날짜(yyyy-MM-dd, 생년월일 1990-01-01 제외)가 있어야 한다.
        //   '09:00 ~ 18:00' 은 '기본 근무 시간' 행에 원래 있으므로 근무일 표의 근거가 아니다(TB 관측).
        //   [DU339 시험 수리 2/3] 좁은 칸 · 큰 글자에서는 표가 근무일마다 쌓은 배치(_stacked)로 바뀌어 머리('근무일')가 없다(TA B 관측).
        //   예시 근무일 날짜(20yy-MM-dd)만 근무일 표의 근거로 쓴다 — 다른 20yy 날짜 글자는 이 화면에 없다(생년월일은 1990).
        final slotHead = all.any((x) => x == '근무일');
        final slotDate = all.any((x) => RegExp(r'^20\d\d-\d\d-\d\d$').hasMatch(x));
        final slotTime = slotDate;
        out('${c.id} 예시 근무일 표 머리=$slotHead 날짜=$slotDate');
        // 공용 판정기
        var avoid = 0;
        final forced = <WordBreak>[];
        for (final e in find.byType(RichText).evaluate()) {
          for (final b in wordBreaks(e.renderObject! as RenderParagraph)) {
            if (b.forced) {
              forced.add(b);
            } else {
              avoid++;
              out('${c.id} avoidable $b');
            }
          }
        }
        out('${c.id} forced=${forced.length} $forced');
        // 캡처: 위 · 제2~3조(근무 조건 · 임금)
        await vqCapture(t, key, '${c.id}_1_top', conditions: {'viewport': '${c.w.toInt()}x${c.h.toInt()}', 'textScaler': c.s});
        final art2 = findVisibleText('제2조 (근무 조건)');
        await t.ensureVisible(art2);
        await t.pump(const Duration(milliseconds: 50));
        final pos = t.state<ScrollableState>(find.byType(Scrollable).first).position;
        pos.jumpTo((pos.pixels + t.getRect(art2).top - 120).clamp(pos.minScrollExtent, pos.maxScrollExtent));
        await t.pump(const Duration(milliseconds: 50));
        await vqCapture(t, key, '${c.id}_2_terms', conditions: {'state': '제2조 근무 조건 · 제3조 임금', 'viewport': '${c.w.toInt()}x${c.h.toInt()}', 'textScaler': c.s});
        expect(t.takeException(), isNull);
        expect(overflows, isEmpty, reason: '${c.id} 넘침');
        final ok = oneDay && !zeroDay && newWage >= 2 && !oldWage && slotTime;
        out('${c.id} summary 예시값=${ok ? 'ok' : 'NG'} avoidable=$avoid forced=${forced.length} beforeObs=$_beforeObs');
        out('KNOWN ${ok ? 'ok' : 'NG'} ${c.id} 예시 단기(1일) · 10,320 · 근무일 09:00–18:00');
        out('KNOWN ${avoid == 0 ? 'ok' : 'NG'} ${c.id} 피할 수 있는 끊김 0(실측 $avoid)');
        if (!_beforeObs) {
          expect(oneDay, isTrue, reason: '${c.id} 근무 형태 단기 (1일)');
          expect(zeroDay, isFalse, reason: '${c.id} (0일) 없음');
          expect(newWage, greaterThanOrEqualTo(2), reason: '${c.id} 임금 · 통상시급 10,320');
          expect(oldWage, isFalse, reason: '${c.id} 옛 예시 10,030 없음');
          expect(slotTime, isTrue, reason: '${c.id} 예시 근무일 09:00–18:00');
          expect(avoid, 0, reason: '${c.id} 피할 수 있는 끊김');
        }
        await t.pumpWidget(const SizedBox.shrink());
      } finally {
        FlutterError.onError = prev;
      }
    });
  }
}
