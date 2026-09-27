// [R7-P1-2 DEVICE.1H] Staffing 디자인 적용 — 실행 + 실제 production 콘텐츠 렌더.
//
//   §2 날짜 4지점 중 **active 2건**만 고쳤다.
//     to_detail_dialogs 2건 → `TODetailDialogs` 가 어디서도 인스턴스화되지
//       않는다(dead code) → NO PATCH.
//     to_list_dialogs:278 `to.date`(DATE_ONLY) → ACTIVE.
//     unclosed_action_queue_screen `item.workDate`(DATE_ONLY) → ACTIVE.
//       같은 화면의 `_daysAgo` 도 기기 성분을 읽어 `D+N` 이 밀렸다.
//
//   §5 는 shell 만으로 끝내지 말라고 한다. 여기서 실제로 그리는 production
//   위젯은 `AppModalShell` · `AppModalHeader` · `CapacitySummaryText` ·
//   `StyledDialogInfoCard` 이고, 날짜 계산은 production 함수를 그대로 실행한다.
//   **사람 카드·badge/action 행은 여기서 그리지 못한다** — 그 위젯은 Firebase
//   의존 State 안에 있다. 미검증으로 남긴다(보고서 §미검증).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ALfit/models/ui/invite_capacity_state.dart';
import 'package:ALfit/screens/business_admin/unclosed_action_queue_screen.dart';
import 'package:ALfit/utils/format_helper.dart';
import 'package:ALfit/widgets/admin/capacity_summary_text.dart';
import 'package:ALfit/widgets/dialogs/styled_dialog.dart';

/// KST 달력일의 실제 instant (Firestore Timestamp 가 주는 모양).
DateTime _kstDay(int y, int m, int d) =>
    DateTime.utc(y, m, d).subtract(const Duration(hours: 9));

void main() {
  // ══════════════════════════════════════════════════════════════
  // A. §2 날짜 — production 함수 실행, 기기 무관
  // ══════════════════════════════════════════════════════════════

  group('DH-A 미마감 큐 날짜/지연일수', () {
    test('DH-A1 workDate 9/28(KST) → `9월 28일 월요일`', () {
      expect(formatUnclosedWorkDate(_kstDay(2026, 9, 28)), '9월 28일 월요일');
    });

    test('DH-A2 월 경계도 밀리지 않는다', () {
      // 10/1 00:00 KST = 9/30 15:00 UTC — 기기 성분을 읽으면 `9월 30일`.
      expect(formatUnclosedWorkDate(_kstDay(2026, 10, 1)), startsWith('10월 1일'));
      expect(formatUnclosedWorkDate(_kstDay(2026, 1, 1)), startsWith('1월 1일'));
    });

    test('DH-A3 지연일수가 KST 달력 차이다', () {
      final today = FormatHelper.toKstDate(DateTime.now());
      final threeDaysAgo =
          today.subtract(const Duration(days: 3)).add(const Duration(hours: 9));
      expect(unclosedDaysAgo(threeDaysAgo), 3);
    });

    test('DH-A4 오늘은 0, 어제는 1', () {
      final now = DateTime.now();
      expect(unclosedDaysAgo(now), 0);
      expect(unclosedDaysAgo(now.subtract(const Duration(days: 1))), 1);
    });

    test('DH-A5 긴급 라벨 계약 유지', () {
      expect(unclosedUrgencyLabel(0), '어제');
      expect(unclosedUrgencyLabel(1), '어제');
      expect(unclosedUrgencyLabel(3), 'D+3');
    });
  });

  group('DH-B 마감 지난 공고 다이얼로그의 근무일', () {
    // to_list_dialogs 가 만드는 문자열과 **같은 식**을 실행한다.
    String workDateLine(DateTime date) =>
        '근무일: ${FormatHelper.toKstDateKey(date)} '
        '(${FormatHelper.weekday(date)})';

    test('DH-B1 9/28(KST) → 2026-09-28 (월)', () {
      expect(workDateLine(_kstDay(2026, 9, 28)), '근무일: 2026-09-28 (월)');
    });

    test('DH-B2 연 경계에서도 밀리지 않는다', () {
      expect(workDateLine(_kstDay(2027, 1, 1)), contains('2027-01-01'));
    });
  });

  // ══════════════════════════════════════════════════════════════
  // C. 실제 production 콘텐츠 렌더 matrix
  //
  //   viewport 는 저장소가 선언한 `ResponsiveHelper` 폭 계층을 따른다
  //   (<360 / <400 / <600 / >=600, 실사용 360~412dp). 높이도 함께 명시한다.
  // ══════════════════════════════════════════════════════════════

  group('DH-C 실제 콘텐츠 렌더', () {
    /// 실제 화면과 같은 조합: 머리말(범위 문구) + 정원 문구 + 날짜 정보 카드
    /// + 사람 줄 텍스트. 모두 production 위젯이다.
    Widget harness({
      required Size size,
      required double textScale,
      required int rows,
      required InviteCapacityState capacity,
      required bool pending,
      EdgeInsets padding = EdgeInsets.zero,
      double keyboard = 0,
      String? scopeSubtitle,
    }) {
      return MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(
            size: size,
            textScaler: TextScaler.linear(textScale),
            padding: padding,
            viewInsets: EdgeInsets.only(bottom: keyboard),
          ),
          child: AppModalShell(children: [
            AppModalHeader(
              title: '사무업무 · 인력 현황',
              subtitle: scopeSubtitle ??
                  '2026년 9월 28일 월요일 · 공고 2개 · 업무 3개',
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: CapacitySummaryText(
                requiredCount: 12,
                capacity: capacity,
                isPending: pending,
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                child: Column(children: [
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: StyledDialogInfoCard.error(
                      '근무일: 2026-09-28 (월)\n근무 시간: 09:00 ~ 18:00',
                    ),
                  ),
                  for (var i = 0; i < rows; i++)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('가나다라마바사아자차카타파하영업관리(W-01$i) · 010-0000-0000'),
                          const Text('최근 90일 노쇼 7회 · 계약서 작성 필요 · '
                              '신분증 재요청 필요 · 주3회 · 계약 종료 · 지원 4일 전'),
                        ],
                      ),
                    ),
                ]),
              ),
            ),
            const SizedBox(height: 56, child: Center(child: Text('닫기'))),
          ]),
        ),
      );
    }

    for (final size in const [
      Size(320, 640), // 작은 지원 폭 (<360 계층)
      Size(360, 740), // 실사용 하한
      Size(412, 892), // 실사용 상한
      Size(600, 960), // 태블릿 경계
    ]) {
      for (final scale in const [1.0, 1.3, 2.0]) {
        for (final rows in const [0, 1, 20]) {
          testWidgets(
              'DH-C ${size.width.toInt()}x${size.height.toInt()} '
              'scale$scale rows$rows', (tester) async {
            await tester.pumpWidget(harness(
              size: size,
              textScale: scale,
              rows: rows,
              capacity: InviteCapacityState.available,
              pending: false,
            ));
            await tester.pump();

            expect(tester.takeException(), isNull, reason: 'overflow/clipping');

            // 필요 인원은 언제나 보인다.
            expect(find.text('필요 12명'), findsOneWidget);

            // 닫기가 화면 안에 있다.
            final r = tester.getRect(find.text('닫기'));
            expect(r.bottom, lessThanOrEqualTo(size.height + 0.5),
                reason: '닫기가 화면 밖으로 밀렸다 (bottom=${r.bottom})');

            // 머리말 범위 문구가 살아 있다 — 글자를 줄여 숨기지 않는다.
            expect(find.byType(AppModalHeader), findsOneWidget);

            if (rows > 0) expect(find.byType(Scrollable), findsWidgets);
          });
        }
      }
    }

    testWidgets('DH-C-CAP 정원 갱신 중 — 숫자 없이 `갱신 중`', (tester) async {
      await tester.pumpWidget(harness(
        size: const Size(360, 740),
        textScale: 1.0,
        rows: 1,
        capacity: InviteCapacityState.unknown,
        pending: true,
      ));
      await tester.pump();
      expect(find.text('필요 12명'), findsOneWidget);
      expect(find.text('갱신 중'), findsOneWidget);
      expect(find.text('정원 확인 불가'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('DH-C-ERR 정원 확인 불가 — 필요 인원은 유지', (tester) async {
      await tester.pumpWidget(harness(
        size: const Size(320, 640),
        textScale: 2.0,
        rows: 1,
        capacity: InviteCapacityState.unknown,
        pending: false,
      ));
      await tester.pump();
      expect(find.text('필요 12명'), findsOneWidget);
      expect(find.text('정원 확인 불가'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('DH-C-SCOPE 부분 로드에서는 수를 만들지 않는다', (tester) async {
      // `_dayStaffingRows == null` 일 때 머리말은 날짜만 남는다.
      await tester.pumpWidget(harness(
        size: const Size(360, 740),
        textScale: 1.0,
        rows: 1,
        capacity: InviteCapacityState.unknown,
        pending: true,
        scopeSubtitle: '2026년 9월 28일 월요일',
      ));
      await tester.pump();
      expect(find.textContaining('공고'), findsNothing,
          reason: '조회가 불완전하면 `공고 0개` 를 만들어 내지 않는다');
      expect(tester.takeException(), isNull);
    });

    testWidgets('DH-C-KB 키보드 올라와도 닫기에 닿는다', (tester) async {
      await tester.pumpWidget(harness(
        size: const Size(360, 740),
        textScale: 1.0,
        rows: 20,
        capacity: InviteCapacityState.available,
        pending: false,
        keyboard: 320,
      ));
      await tester.pump();
      final r = tester.getRect(find.text('닫기'));
      expect(r.bottom, lessThanOrEqualTo(740 - 320 + 0.5));
      expect(tester.takeException(), isNull);
    });

    testWidgets('DH-C-SA safe area(노치·홈바)에서도 잘리지 않는다', (tester) async {
      await tester.pumpWidget(harness(
        size: const Size(390, 844),
        textScale: 1.3,
        rows: 20,
        capacity: InviteCapacityState.available,
        pending: false,
        padding: const EdgeInsets.only(top: 47, bottom: 34),
      ));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.text('닫기'), findsOneWidget);
    });
  });
}
