import 'dart:ui' show SemanticsAction;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ALfit/models/core/business_model.dart';
import 'package:ALfit/utils/attendance_policy_disclosure.dart';
import 'package:ALfit/widgets/common/attendance_rule_guide_view.dart';

/// [ATTENDANCE-RULE-GUIDE.29-A1] 화면 읽기가 받는 이름은 **원문**이다 — 표시용 줄바꿈 문자(WORD JOINER 등)가 없다.
///   사례는 '예: 17:41 출근 → 인정 시작 18:05' 한 문장으로 읽힌다(입력·결과 조각을 따로 읽지 않는다).
void main() {
  final g = attendanceRuleGuide(const AttendanceRules(), startHHmm: '17:35', endHHmm: '18:35');

  Future<void> pump(WidgetTester t, {bool collapsible = false}) async {
    t.view.physicalSize = const Size(320, 2400);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: AttendanceRuleGuideView(guide: g, collapsibleExamples: collapsible),
        ),
      ),
    ));
    await t.pump();
  }

  testWidgets('ARGS-1 기준 설명·근무시간 semantics 이름은 원문, 숨은 문자 없음', (t) async {
    final h = t.ensureSemantics();
    await pump(t);
    for (final p in g.sections.expand((s) => s.items).expand((i) => i.points)) {
      expect(find.bySemanticsLabel(p), findsOneWidget, reason: '원문 이름이 없다: $p');
    }
    expect(find.bySemanticsLabel(RegExp('[⁠​]')), findsNothing);
    expect(find.bySemanticsLabel(RegExp('17:35–18:35')), findsOneWidget);
    h.dispose();
  });

  testWidgets('ARGS-2 사례는 한 문장으로 읽힌다', (t) async {
    final h = t.ensureSemantics();
    await pump(t);
    for (final e in g.sections.expand((s) => s.items).expand((i) => i.examples)) {
      expect(find.bySemanticsLabel('예: ${attendanceRuleExampleText(e)}'), findsOneWidget);
    }
    h.dispose();
  });

  testWidgets('ARGS-3 접힌 사례는 버튼으로 펼친다 — 펼치기 전에는 사례가 읽히지 않는다', (t) async {
    final h = t.ensureSemantics();
    await pump(t, collapsible: true);
    expect(find.bySemanticsLabel(RegExp('^예: ')), findsNothing);
    final toggle = find.widgetWithText(TextButton, '시간 예시 보기');
    expect(t.getSemantics(toggle).getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
    await t.tap(toggle);
    await t.pump();
    expect(find.bySemanticsLabel(RegExp('^예: ')), findsWidgets);
    expect(find.text('시간 예시 접기'), findsOneWidget);
    h.dispose();
  });
}
