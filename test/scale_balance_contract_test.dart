// [SCALE-BALANCE.34] 확대(글자 배율) 상태의 시각 균형 — 기기 관찰(392·2.0)에서 나온 결함이 돌아오지 않게.
//   SB-1 RichText 는 사용자 글자 배율을 스스로 받지 않는다 → lib 의 모든 RichText 는 textScaler 를 넘긴다
//   SB-2 공통 달력 칸 높이 — 배율 1.0 은 기본 그대로, 2.0 은 글자가 커진 만큼 늘어난다(날짜 숫자 겹침·잘림 방지)
//   SB-3 약관 할 일 카드 — 큰 글자에서 설명을 접되 카드 안 '설명 보기' 로 화면에서 펼친다(.34-A1). 펼치기는 동의 화면 이동과 별개
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'support/visible_text.dart';
import 'package:ALfit/models/core/legal_readiness.dart';
import 'package:ALfit/widgets/calendar/app_calendar.dart';
import 'package:ALfit/widgets/common/legal_task_card.dart';

Future<void> _loadFont() async {
  final loader = FontLoader('NotoSansKR');
  for (final f in const ['Regular', 'Bold']) {
    loader.addFont(rootBundle
        .load('assets/fonts/NotoSansKR-$f.ttf')
        .then((b) => ByteData.sublistView(b.buffer.asUint8List())));
  }
  await loader.load();
}

void main() {
  setUpAll(() async {
    await _loadFont();
    await initializeDateFormatting('ko_KR');
  });

  test('SB-1 lib 의 RichText 는 모두 textScaler 를 넘긴다', () {
    final misses = <String>[];
    for (final e in Directory('lib').listSync(recursive: true)) {
      if (e is! File || !e.path.endsWith('.dart')) continue;
      final src = e.readAsStringSync();
      for (final m in RegExp(r'RichText\(').allMatches(src)) {
        final head = src.substring(m.start, (m.start + 260).clamp(0, src.length));
        if (!head.contains('textScaler:')) misses.add('${e.path}:${'\n'.allMatches(src.substring(0, m.start)).length + 1}');
      }
    }
    expect(misses, isEmpty, reason: 'RichText 는 MediaQuery 배율을 자동으로 쓰지 않는다 — Text.rich 를 쓰거나 textScaler 를 넘긴다');
  });

  for (final scale in const [1.0, 2.0]) {
    testWidgets('SB-2 달력 칸 높이 · 배율 $scale', (t) async {
      late double row, dow;
      await t.pumpWidget(MaterialApp(
        builder: (ctx, c) => MediaQuery(
            data: MediaQuery.of(ctx).copyWith(textScaler: TextScaler.linear(scale)), child: c!),
        home: Builder(builder: (ctx) {
          row = AppCalendar.scaledHeight(ctx, 40);
          dow = AppCalendar.scaledHeight(ctx, 28, fontSize: 13);
          return const SizedBox();
        }),
      ));
      if (scale == 1.0) {
        expect(row, 40);
        expect(dow, 28);
      } else {
        // 15pt 숫자가 30pt 가 되면 줄 높이(×1.3)만큼 칸이 늘어난다 — 숫자 줄끼리 겹치지 않는다.
        expect(row, closeTo(40 + 15 * 1.3, 0.01));
        expect(row, greaterThanOrEqualTo(30 * 1.3));
        expect(dow, closeTo(28 + 13 * 1.3, 0.01));
      }
    });
  }

  for (final (width, scale, showsBody) in const [(392.0, 1.0, true), (392.0, 2.0, false), (320.0, 1.3, false)]) {
    testWidgets('SB-3 약관 카드 ${width.toInt()}·$scale — 설명 ${showsBody ? '보임' : '숨김(읽기에는 전달)'}', (t) async {
      t.view.physicalSize = Size(width, 800);
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.reset);
      final h = t.ensureSemantics();
      await t.pumpWidget(MaterialApp(
        theme: ThemeData(fontFamily: 'NotoSansKR'),
        builder: (ctx, c) => MediaQuery(
            data: MediaQuery.of(ctx).copyWith(textScaler: TextScaler.linear(scale)), child: c!),
        home: Scaffold(
          body: LegalTaskCard(loadReadiness: () async => const LegalReadiness(status: LegalReadinessStatus.legacyConsentUnknown)),
        ),
      ));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      String shown() => t.widgetList<Text>(find.byType(Text)).map((w) => visibleText(w.data ?? '')).join('|');
      expect(shown().contains('이전 동의 기록으로는'), showsBody);
      if (!showsBody) {
        // 화면 읽기 없이도 — 카드 안에서 설명을 펼친다.
        expect(findVisibleText('설명 보기'), findsOneWidget);
        await t.tap(findVisibleText('설명 보기'));
        await t.pumpAndSettle();
        expect(shown().contains('이전 동의 기록으로는'), isTrue, reason: '펼친 설명이 화면에 보인다');
        expect(find.byType(Scaffold), findsOneWidget, reason: '설명 펼치기는 동의 화면으로 이동하지 않는다');
        await t.tap(findVisibleText('설명 접기'));
        await t.pumpAndSettle();
        expect(shown().contains('이전 동의 기록으로는'), isFalse);
      } else {
        expect(findVisibleText('설명 보기'), findsNothing, reason: '기본 크기는 예전처럼 설명을 그대로 보인다');
      }
      h.dispose();
    });
  }

  testWidgets('SB-4 공통 달력 2.0 — 날짜 선택 표시가 맞고, 다음 달로 넘겨도 넘침 없음', (t) async {
    t.view.physicalSize = const Size(392, 1400);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(
      theme: ThemeData(fontFamily: 'NotoSansKR'),
      builder: (ctx, c) => MediaQuery(data: MediaQuery.of(ctx).copyWith(textScaler: const TextScaler.linear(2.0)), child: c!),
      home: const Scaffold(body: _CalHost()),
    ));
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
    final host = t.state<_CalHostState>(find.byType(_CalHost));
    await t.tap(find.text('20').first);
    await t.pumpAndSettle();
    expect(host.selected?.day, 20, reason: '누른 날짜가 선택된다');
    // 다음 달 — 왼쪽으로 넘긴다.
    await t.fling(find.byType(AppCalendar), const Offset(-300, 0), 1000);
    await t.pumpAndSettle();
    expect(t.takeException(), isNull, reason: '달 이동 후 칸이 겹치거나 넘치지 않는다');
    expect(host.pages, greaterThanOrEqualTo(1));
    expect(host.focused.month, 11);
    // 칸 높이가 글자 높이를 담는다 — 날짜 숫자 문단이 자기 칸 안에 있다.
    final cell = t.getRect(find.text('20').first);
    expect(cell.height, lessThanOrEqualTo(AppCalendar.scaledHeight(t.element(find.byType(AppCalendar)), 40)));
  });
}

// ── .34-A1 대표 회귀 ─────────────────────────────────────────────
//   SB-4 공통 달력(2.0) — 날짜를 누르면 선택이 그 날짜로 바뀌고 표시가 따라간다, 다음 달로 넘겨도 넘침 없음
//   SB-5 로그인(키보드 열림) — 입력칸·로그인 버튼에 스크롤로 닿고, 빈 칸 오류 안내가 생겨도 넘치지 않는다
class _CalHost extends StatefulWidget {
  const _CalHost();
  @override
  State<_CalHost> createState() => _CalHostState();
}

class _CalHostState extends State<_CalHost> {
  DateTime focused = DateTime(2026, 10, 15);
  DateTime? selected;
  int pages = 0;
  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        child: AppCalendar(
          focusedDay: focused,
          selectedDay: selected,
          onDaySelected: (sel, foc) => setState(() { selected = sel; focused = foc; }),
          onPageChanged: (foc) => setState(() { focused = foc; pages++; }),
          eventLoader: (_) => const [],
        ),
      );
}
