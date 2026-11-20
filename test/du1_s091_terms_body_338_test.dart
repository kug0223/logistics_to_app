// ignore_for_file: depend_on_referenced_packages
// [DU338] S091 약관 전문 보기(TermsViewerScreen) 본문 낱말 조판 — 소급 5 채택 · 소급 6 인계 'S091 본문은 S048 과 같은 보존 규칙'.
//   자료: du1_c0_terms_viewer_test 와 같은 QA 긴 약관(첫 문장 · 제1~8조 · ①② · 일반 단락 · 끝 문장).
//   W 392x844 1.0 / B 320x640 2.0. 공용 판정기(support/du_word_break.dart, 독립 한 줄 폭)로 본문 줄 전수의
//   피할 수 있는 끊김 / 강제 끊김을 센다. 보존: 줄 수 · 순서 · 원문(보이는 글자 = 낭독 이름 = 원문 줄) · 조문 강조 ·
//   읽기 완료 전 CTA 잠김 → 끝 도달 → 활성 → 탭 → true 반환.
//   단언(기본): 예외 0 · 넘침 0 · 줄 수/순서 · 읽기 완료 흐름 · 피할 수 있는 끊김 0 · 원문 동일성.
//   DU_BEFORE_OBSERVE=338 이면 끊김 · 원문 동일성(낭독 이름)은 KNOWN 으로 기록만 한다.
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'package:ALfit/models/core/legal_terms_model.dart';
import 'package:ALfit/theme/role_theme.dart';
import 'package:ALfit/widgets/auth/terms_viewer_screen.dart';

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

final bool _beforeObs = Platform.environment['DU_BEFORE_OBSERVE'] == '338';

const kFirst = '[QA-첫문장] 이 약관은 ALfit 이 제공하는 근무 매칭 서비스의 이용 조건과 절차를 정합니다.';
const kLast = '[QA-끝문장] 본 약관은 2026년 11월 1일부터 시행하며, 이전 약관은 이 날부터 효력을 잃습니다.';
String longContent() {
  final b = StringBuffer('$kFirst\n');
  for (var n = 1; n <= 8; n++) {
    b.writeln('제$n조 (QA 조문 $n — 이용 조건과 책임의 범위)');
    b.writeln('① 회원은 서비스를 이용할 때 관계 법령과 이 약관의 내용을 지켜야 하며, 회사가 안내하는 이용 방법을 따라야 합니다.');
    b.writeln('② 회사는 서비스 화면에 표시한 근무 일정·장소·임금 정보를 사업장이 등록한 내용 그대로 보여 주며, 그 내용의 변경은 사업장의 책임입니다.');
    b.writeln('일반 단락: 근무 확정 이후의 취소·변경은 별도로 정한 절차에 따르고, 근태 기록은 사업장의 처리 기준에 따라 계산됩니다.');
  }
  b.write(kLast);
  return b.toString();
}

void main() {
  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
  });

  for (final c in const [(id: 'S091-W', w: 392.0, h: 844.0, s: 1.0), (id: 'S091-B', w: 320.0, h: 640.0, s: 2.0)]) {
    testWidgets('${c.id} 약관 전문 본문 ${c.w.toInt()}x${c.h.toInt()}@${c.s}', (t) async {
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
            {'state': state, 'viewport': '${c.w.toInt()}x${c.h.toInt()}', 'textScaler': c.s, 'data': 'QA 긴 약관(du1_c0_terms_viewer 와 같음)'};
        final content = longContent();
        final item = LegalTermsItem(id: 'service_terms', title: '[QA] 서비스 이용약관 (위치기반 근무 매칭 및 급여 정산 이용 조건 포함)',
            content: content, isRequired: true, version: '2026-11-01', revisionId: 'service_terms__2026-11-01', order: 1);
        Object? result = 'unset';
        await t.pumpWidget(RepaintBoundary(
          key: key,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: RoleTheme.workerTheme,
            builder: (ctx, child) =>
                MediaQuery(data: MediaQuery.of(ctx).copyWith(textScaler: TextScaler.linear(c.s)), child: child!),
            home: Builder(
              builder: (ctx) => Scaffold(
                body: Center(
                  child: TextButton(
                    onPressed: () async {
                      result = await Navigator.push<bool>(ctx, MaterialPageRoute(builder: (_) => TermsViewerScreen(item: item)));
                    },
                    child: const Text('열기'),
                  ),
                ),
              ),
            ),
          ),
        ));
        await t.tap(find.text('열기'));
        for (var i = 0; i < 10; i++) {
          await t.pump(const Duration(milliseconds: 50));
        }
        expect(find.byType(TermsViewerScreen), findsOneWidget);
        final vScroll = find.descendant(of: find.byType(TermsViewerScreen), matching: find.byType(Scrollable)).first;
        final pos = t.state<ScrollableState>(vScroll).position;
        final cta = find.descendant(of: find.byType(TermsViewerScreen), matching: find.byType(ElevatedButton)).first;

        // 본문 줄 Text — 스크롤 본문 안의 Text 중 원문 줄과 보이는 글자가 같은 것(제목 · 버전 제외)
        final lines = content.split('\n');
        final bodyTexts = find.descendant(of: vScroll, matching: find.byType(Text)).evaluate().map((e) => e.widget as Text).toList();
        final shown = bodyTexts.map((w) => visibleText(w.data ?? '')).toList();
        // 줄 수 · 순서: 원문 줄이 본문 Text 목록에 같은 순서로 모두 있다
        var k = 0;
        for (final s in shown) {
          if (k < lines.length && s == lines[k]) k++;
        }
        out('${c.id} 원문 줄=${lines.length} 순서대로 찾음=$k 본문 Text=${bodyTexts.length}');
        expect(k, lines.length, reason: '${c.id} 원문 줄이 같은 순서로 모두 보인다(줄 수 · 순서 보존)');
        // 원문 동일성: 줄마다 보이는 글자 = 원문, 낭독 이름 = 원문(낭독 이름이 없으면 data 자체가 원문이어야 한다)
        var semOk = 0;
        for (final w in bodyTexts) {
          final v = visibleText(w.data ?? '');
          if (!lines.contains(v)) continue;
          if ((w.semanticsLabel ?? w.data) == v) semOk++;
        }
        out('${c.id} 원문 동일성(보이는 글자=낭독 이름=원문) $semOk/${lines.length}');
        // 조문 강조: 제N조 · ①② 줄은 w600
        final art = bodyTexts.firstWhere((w) => visibleText(w.data ?? '').startsWith('제1조'));
        out('${c.id} 조문 제목 굵기=${art.style?.fontWeight}');
        expect(art.style?.fontWeight, FontWeight.w600);

        // 판정: 스크롤 본문 안 문단 전수(지연 생성 아님 — Column)
        var avoid = 0;
        final forced = <WordBreak>[];
        final avoidList = <WordBreak>[];
        for (final e in find.descendant(of: vScroll, matching: find.byType(RichText)).evaluate()) {
          final rp = e.renderObject! as RenderParagraph;
          for (final b in wordBreaks(rp)) {
            if (b.forced) {
              forced.add(b);
            } else {
              avoid++;
              avoidList.add(b);
            }
          }
        }
        out('${c.id} avoidable=$avoid ${avoidList.take(12).toList()}');
        out('${c.id} forced=${forced.length} ${forced.take(6).toList()}');

        // 읽기 완료 흐름: 처음엔 CTA 잠김
        expect(t.widget<ElevatedButton>(cta).onPressed, isNull, reason: '${c.id} 끝까지 읽기 전 동의 잠김');
        await vqCapture(t, key, '${c.id}_1_top', conditions: cond('처음 · 동의 잠김'));
        pos.jumpTo(pos.maxScrollExtent * 0.45);
        await t.pump(const Duration(milliseconds: 50));
        await vqCapture(t, key, '${c.id}_2_mid', conditions: cond('본문 45%'));
        expect(t.widget<ElevatedButton>(cta).onPressed, isNull, reason: '${c.id} 중간에서는 여전히 잠김');
        pos.jumpTo(pos.maxScrollExtent);
        for (var i = 0; i < 4; i++) {
          await t.pump(const Duration(milliseconds: 50));
        }
        expect(findVisibleText(kLast), findsOneWidget);
        expect(t.widget<ElevatedButton>(cta).onPressed, isNotNull, reason: '${c.id} 끝 도달 뒤 동의 가능');
        await vqCapture(t, key, '${c.id}_3_end', conditions: cond('끝 도달 · 동의 활성'));
        await t.tap(cta);
        for (var i = 0; i < 10; i++) {
          await t.pump(const Duration(milliseconds: 50));
        }
        expect(result, isTrue, reason: '${c.id} 동의하고 닫기 → true');
        expect(t.takeException(), isNull);
        out('${c.id} summary overflows=${overflows.length} avoidable=$avoid forced=${forced.length} semOk=$semOk/${lines.length} beforeObs=$_beforeObs');
        out('KNOWN ${avoid == 0 ? 'ok' : 'NG'} ${c.id} 피할 수 있는 끊김 0(실측 $avoid)');
        out('KNOWN ${semOk == lines.length ? 'ok' : 'NG'} ${c.id} 원문 동일성 ${lines.length}(실측 $semOk)');
        expect(overflows, isEmpty, reason: '${c.id} 넘침');
        if (!_beforeObs) {
          expect(avoid, 0, reason: '${c.id} 피할 수 있는 끊김');
          expect(semOk, lines.length, reason: '${c.id} 원문 동일성');
        }
        await t.pumpWidget(const SizedBox.shrink());
      } finally {
        FlutterError.onError = prev;
      }
    });
  }
}
