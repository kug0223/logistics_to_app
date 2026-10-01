// [R7-P4.4E.6A] 공고 등록 업무 카드의 가로 넘침.
//
// E6 에서 root cause 를 코드로 확정했다: 업무명 아래 메타데이터 Row 에
// `Expanded`/`Flexible`/`Spacer` 가 하나도 없어 줄어들 수 있는 자식이 없었다.
// `'(실근무 N시간 M분)'` 이 붙는 순간 Row 는 자식 고유 폭의 합을 그대로
// 요구하고, 360dp 기기에서 3.9px 넘쳤다.
//
// 이 테스트가 고정하는 계약:
//   1. 넘침 0 — 320/360/411dp × 배율 1.0/1.3/2.0 아홉 칸 전부.
//   2. **업무명·시작~종료 시각·실근무 시간이 전부 화면에 남는다.**
//      시간은 ALfit 의 핵심 사실이므로 공간이 부족하다고 ellipsis 로
//      감추지 않는다. 좁아지면 줄을 바꿔서라도 전체를 보여준다.
//   3. 수정·삭제 버튼이 계속 눌릴 수 있다.
//
// 넘침만 0 이면 통과하는 테스트는 만들지 않는다 — 내용을 지워도 넘침은
// 0 이 되기 때문이다. 세 가지를 같이 본다.
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ALfit/screens/business_admin/to_management/widgets/to_work_detail_card.dart';

/// 실제 화면에서 카드가 받는 가로 제약을 흉내낸다 — 화면 좌우 거터 16.
const double kGutter = 16;

/// 가장 불리한 대표 문자열.
/// 시간은 5+3+5 = 13자 고정, 실근무는 '(실근무 11시간 30분)' 이 최장 계열.
const String kWorkType = '물류 상하차 보조';
const String kStart = '09:00';
const String kEnd = '18:00';

Future<void> _pumpCard(
  WidgetTester tester, {
  required double width,
  required double textScale,
  required double height,
}) async {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(textScale),
          ),
          child: Scaffold(
            body: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: kGutter),
                child: TOWorkDetailCard(
                  workType: kWorkType,
                  workTypeIcon: 'local_shipping',
                  workTypeColor: '#2E7D32',
                  wage: 12000,
                  requiredCount: 3,
                  startTime: kStart,
                  endTime: kEnd,
                  breakMinutes: 60,
                  onEdit: () {},
                  onDelete: () {},
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

/// 화면 밖으로 나간 픽셀이 없는지 본다. `takeException` 은 RenderFlex 넘침을
/// 잡지만, 넘침 없이도 부모 밖으로 나갈 수 있으므로 경계도 같이 본다.
void _expectWithinViewport(WidgetTester tester, Finder finder, String label) {
  final viewport = tester.getSize(find.byType(MaterialApp)).width;
  for (final e in finder.evaluate()) {
    final box = e.renderObject as RenderBox;
    final topLeft = box.localToGlobal(Offset.zero);
    expect(
      topLeft.dx,
      greaterThanOrEqualTo(-0.5),
      reason: '$label 이 왼쪽으로 벗어났다',
    );
    expect(
      topLeft.dx + box.size.width,
      lessThanOrEqualTo(viewport + 0.5),
      reason: '$label 이 오른쪽으로 벗어났다 '
          '(right=${topLeft.dx + box.size.width}, viewport=$viewport)',
    );
  }
}

void main() {
  const widths = <double>[320, 360, 411];
  const scales = <double>[1.0, 1.3, 2.0];

  for (final w in widths) {
    for (final s in scales) {
      testWidgets('업무 카드 ${w.toInt()}dp 배율 $s — 넘침 0 + 정보 전부 보임',
          (tester) async {
        // 배율이 커지면 카드가 길어진다 — 세로는 스크롤이 받으므로 넉넉히 준다.
        await _pumpCard(tester, width: w, textScale: s, height: 2400);

        expect(
          tester.takeException(),
          isNull,
          reason: '${w.toInt()}dp 배율 $s 에서 넘쳤다',
        );

        // 업무명 — 임의로 자르지 않는다.
        final workTypeText = find.text(kWorkType);
        expect(workTypeText, findsOneWidget,
            reason: '업무명이 통째로 사라졌다');
        _expectWithinViewport(tester, workTypeText, '업무명');

        // 시작~종료 시각 — 전체가 남아야 한다.
        final timeText = find.text('$kStart ~ $kEnd');
        expect(timeText, findsOneWidget,
            reason: '시작~종료 시각이 통째로 사라졌다');
        _expectWithinViewport(tester, timeText, '시작~종료 시각');

        // 실근무 — breakMinutes 60 이므로 표시되어야 한다.
        final netText = find.textContaining('실근무');
        expect(netText, findsOneWidget,
            reason: '실근무 표기가 사라졌다 — 공간 부족으로 숨기지 않는다');
        _expectWithinViewport(tester, netText, '실근무');

        // 수정·삭제 버튼이 계속 눌릴 수 있어야 한다.
        for (final icon in [Icons.edit_outlined, Icons.delete_outline]) {
          final btn = find.byIcon(icon);
          expect(btn, findsOneWidget, reason: '$icon 버튼이 사라졌다');
          _expectWithinViewport(tester, btn, '$icon 버튼');
          final size = tester.getSize(btn);
          expect(size.width, greaterThan(0));
          expect(size.height, greaterThan(0));
        }
      });
    }
  }

  testWidgets('시간 텍스트는 ellipsis 로 잘리지 않는다', (tester) async {
    // 가장 좁고 가장 큰 배율 — 여기서도 overflow 처리는 ellipsis 가 아니어야 한다.
    await _pumpCard(tester, width: 320, textScale: 2.0, height: 2400);
    tester.takeException();

    final timeWidget = tester.widget<Text>(find.text('$kStart ~ $kEnd'));
    expect(
      timeWidget.overflow,
      isNot(TextOverflow.ellipsis),
      reason: '시간은 핵심 사실이므로 ellipsis 로 감추지 않는다',
    );

    final netWidget =
        tester.widget<Text>(find.textContaining('실근무'));
    expect(
      netWidget.overflow,
      isNot(TextOverflow.ellipsis),
      reason: '실근무도 ellipsis 로 감추지 않는다',
    );
  });
}
