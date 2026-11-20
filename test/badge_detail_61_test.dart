// [.61] 근로자 배지 상세 — 구현되지 않은 혜택·근거 없는 '인증' 문구를 보이지 않는다.
//   기본 배지 혜택 문구는 관리자 목록 표시·자동확정 우선 배정·매칭 추천·'공식 인증' 을 약속하지만 그 소비자가 없다.
import 'support/visible_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ALfit/models/settings/trust_settings_model.dart';
import 'package:ALfit/widgets/common/badge_display_widget.dart';

void main() {
  testWidgets('[B61-f] 배지 상세에 혜택 목록(약속)이 없다 — 이름·조건은 그대로', (tester) async {
    final b = BadgeModel.defaultBadges().firstWhere((x) => x.id == 'badge_first_step');
    expect(b.benefit, contains('인증'), reason: '기본 문구가 실제로 인증을 말한다(전제)');
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: Builder(builder: (ctx) => TextButton(
        onPressed: () => showDialog(context: ctx, builder: (_) => BadgeDetailDialog(badge: b)), child: const Text('열기'))))));
    await tester.tap(find.text('열기'));
    await tester.pumpAndSettle();
    expect(findVisibleTextContaining(b.name), findsWidgets);
    expect(findVisibleText('배지 혜택'), findsNothing);
    expect(findVisibleTextContaining('공식 인증'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
