// [R7-PREDEVICE-STABILIZATION.1] 근로자가 보는 **방향 문구**가 실제로 읽힌다.
//
// ── 왜 필요한가 ─────────────────────────────────────────────────────
//   이 Phase 는 근로자 고지 네 줄에 방향과 구체 사례를 더했다
//   ("30분 단위" → "30분 단위로 올려서 차감 (6분 늦으면 30분)" — 사례의
//   도착 분은 유예를 1분 넘긴 시점이고, `.1A` 가 계산에서 가져오게 했다).
//   문장이 길어졌으므로 **좁은 화면·큰 배율에서 잘리거나 넘치면** 고지한
//   것이 아니다 — 글자 수가 늘어난 변경은 렌더로 확인해야 끝난다.
//
//   `attendancePolicyLines` 를 쓰는 면은 여섯이다(공고 상세 · 계약 PDF ·
//   계약 서명 · 내 지원 · 수락 시트 · 지원 확인). 그중 **수락 시트**는
//   근로자가 확정 전에 반드시 읽는 면이고 provider 없이 띄울 수 있어
//   여기서 실제로 그린다. 나머지 면의 렌더는 이 Phase 에서 확인하지
//   못했다 — 보고서에 NOT TESTED 로 남긴다.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ALfit/models/core/application_model.dart';
import 'package:ALfit/models/core/business_model.dart';
import 'package:ALfit/utils/attendance_policy_disclosure.dart';
import 'package:ALfit/widgets/dialogs/application_policy_acknowledge_sheet.dart';

final _workDate = DateTime(2026, 10, 15);

/// 고지 snapshot 을 가진 확정 지원. snapshot 이 없으면 시트가 바로 닫힌다.
ApplicationModel _app({AttendanceRules? snapshot}) => ApplicationModel(
      id: 'app1',
      businessId: 'b1',
      businessName: '중앙물류센터',
      toTitle: '냉장 분류',
      workDate: _workDate,
      startTime: '09:00',
      endTime: '18:00',
      uid: 'u1',
      selectedWorkType: '분류',
      wage: 12000,
      status: 'CONFIRMED',
      appliedAt: _workDate,
      attendancePolicySnapshot:
          snapshot ?? AttendanceRules.defaults().copyWith(
                earlyWindow: 30,
                earlyArrivalUnit: 30,
                lateGrace: 5,
                lateUnit: 30,
                lateWindow: 30,
                overtimeUnit: 30,
                earlyLeaveUnit: 30,
              ),
    );

/// 시트를 띄운다. [size] · [textScale] 이 측정 축이다.
Future<void> _openSheet(
  WidgetTester tester, {
  Size size = const Size(360, 800),
  double textScale = 1.0,
  ApplicationModel? application,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  late BuildContext ctx;
  await tester.pumpWidget(
    MaterialApp(
      builder: (c, child) => MediaQuery(
        data: MediaQuery.of(c)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Builder(builder: (c) {
        ctx = c;
        return const Scaffold(body: SizedBox.expand());
      }),
    ),
  );

  unawaited(ApplicationPolicyAcknowledgeSheet.show(
    ctx,
    application: application ?? _app(),
    workerName: '김근로',
  ));
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// 화면에 실제로 그려진 모든 Text 를 한 문자열로 모은다.
String _visibleText(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text))
    .map((t) => t.data ?? t.textSpan?.toPlainText() ?? '')
    .join('\n');

void main() {
  group('PD-DIR 수락 시트가 방향을 보여준다', () {
    testWidgets('PD-DIR-01 360dp 배율 1.0 — 네 방향 문구가 모두 보인다',
        (tester) async {
      await _openSheet(tester);
      expect(tester.takeException(), isNull);

      final shown = _visibleText(tester);
      // 공용 formatter 가 만든 일곱 줄이 그대로 화면에 있다.
      for (final l in attendancePolicyLines(_app().attendancePolicySnapshot!)) {
        expect(shown.contains(l.value), isTrue,
            reason: '"${l.label}" 줄이 화면에 없다: ${l.value}');
      }
      // 방향을 말하는 표현이 실제로 읽힌다.
      expect(shown.contains('올려서 차감'), isTrue);
      expect(shown.contains('남는 시간은 인정되지 않아요'), isTrue);
      // 유예 5분 · 단위 30분 → 첫 지각 사례는 6분이다.
      expect(shown.contains('6분 늦으면 30분'), isTrue, reason: shown);
      expect(shown.contains('1분 일찍 가도 30분'), isTrue);
    });

    for (final w in const [320.0, 360.0]) {
      for (final scale in const [1.0, 1.3, 2.0]) {
        testWidgets('PD-DIR ${w.toInt()}dp × 배율 $scale — 넘침 0',
            (tester) async {
          await _openSheet(tester, size: Size(w, 800), textScale: scale);
          expect(tester.takeException(), isNull,
              reason: '${w.toInt()}dp × $scale 에서 고지가 넘친다');
        });
      }
    }

    testWidgets('PD-DIR-08 배율 2.0 에서도 방향 문구가 잘리지 않는다',
        (tester) async {
      // 스크롤로 닿으면 된다 — 한 화면에 다 보일 필요는 없다. 다만
      //   말줄임·클립으로 **사라지면** 고지가 아니다.
      await _openSheet(tester,
          size: const Size(320, 800), textScale: 2.0);
      expect(tester.takeException(), isNull);

      final shown = _visibleText(tester);
      expect(shown.contains('…'), isFalse,
          reason: '고지 문구가 말줄임으로 잘렸다');
      for (final t in const ['올려서 차감', '남는 시간은 인정되지 않아요']) {
        expect(shown.contains(t), isTrue,
            reason: '배율 2.0 에서 "$t" 가 사라졌다');
      }
    });

    testWidgets('PD-DIR-09 단위를 바꾸면 화면의 사례 숫자도 바뀐다',
        (tester) async {
      // 사례의 두 숫자(도착 분·차감 분)가 박혀 있으면 다른 사업장에 거짓이
      //   된다. 유예 5분 · 단위 10분이면 "6분 늦으면 10분" 이어야 한다.
      await _openSheet(tester,
          application: _app(
              snapshot: AttendanceRules.defaults().copyWith(
            earlyWindow: 30,
            earlyArrivalUnit: 10,
            lateGrace: 5,
            lateUnit: 10,
            lateWindow: 30,
            overtimeUnit: 10,
            earlyLeaveUnit: 10,
          )));
      expect(tester.takeException(), isNull);

      final shown = _visibleText(tester);
      expect(shown.contains('6분 늦으면 10분'), isTrue, reason: shown);
      expect(shown.contains('1분 일찍 가도 10분'), isTrue);
      expect(shown.contains('6분 늦으면 30분'), isFalse,
          reason: '30 이 하드코딩돼 있다');
    });
  });
}
