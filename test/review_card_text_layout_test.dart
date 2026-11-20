import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter_test/flutter_test.dart';

import 'package:ALfit/models/core/monthly_review_model.dart';
import 'package:ALfit/widgets/common/review_card.dart';

import 'support/visible_text.dart';

/// [TEXT-LAYOUT-CONSUMER.29] 리뷰 관리 카드(관리자 관점) — 기기 320dp·1.3 / 392dp·2.0 에서
///   이름 말줄임, '2026 / 년 10월' 갈림, 댓글 두 줄 잘림(카드에 상세 화면이 없어 나머지를 볼 수 없었다).
const _long = '남궁아리아나크리스티나합성근로자';
const _comment = '긴 댓글 확인용 합성 문장입니다. 한 달 동안 성실하게 근무했고 마감 정리까지 꼼꼼했습니다.';

MonthlyReviewModel _review() => MonthlyReviewModel.tryFromMap({
      'reviewKey': 'k1',
      'reviewType': 'ADMIN_TO_USER',
      'reviewerName': '합성 관리자',
      'businessId': 'b1',
      'businessName': '[합성] E7 사업장',
      'targetUserId': 'u1',
      'targetUserName': _long,
      'targetUserGender': '여성',
      'targetUserAge': 31,
      'reviewYear': 2026,
      'reviewMonth': 10,
      'workDaysInMonth': 12,
      'normalAttendanceDays': 11,
      'lateDays': 1,
      'rating': 4,
      'wouldRehire': true,
      'positiveTags': ['성실해요'],
      'improvementTags': <String>[],
      'comment': _comment,
      'isPublished': true,
      'createdAt': Timestamp.fromDate(DateTime(2026, 10, 29)),
    }, 'r1')!;

Future<void> _pump(WidgetTester t, double width, double scale) async {
  t.view.physicalSize = Size(width, 1600);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(
    builder: (ctx, c) => MediaQuery(
        data: MediaQuery.of(ctx).copyWith(textScaler: TextScaler.linear(scale)), child: c!),
    home: Scaffold(
      body: SingleChildScrollView(
        child: ReviewCard(review: _review(), perspective: ReviewCardPerspective.adminWritten),
      ),
    ),
  ));
  await t.pump();
}

void main() {
  for (final c in [(320.0, 1.3), (392.0, 2.0)]) {
    testWidgets('RC-1 ${c.$1.toInt()}dp × ${c.$2} — 이름 전체·(나이, 성별) 한 덩어리, 넘침 0', (t) async {
      await _pump(t, c.$1, c.$2);
      expect(t.takeException(), isNull);
      final name = findVisibleTextContaining(_long);
      expect(name, findsOneWidget);
      final w = t.widget<Text>(name);
      expect(w.overflow, isNot(TextOverflow.ellipsis));
      expect(w.maxLines, isNull);
      // '(31세, 여성)' 은 한 줄 안에서 갈리지 않는다(NBSP 로 묶음).
      expect(visibleText(w.textSpan!.toPlainText()), contains('(31세, 여성)'));
    });

    // 머리말 전체는 한 줄에 안 들어가고 기간('2026년 10월')은 들어가는 폭 — 시험 글꼴이 기기보다 넓어 411dp·1.0 으로 본다.
    testWidgets('RC-2 (${c.$1.toInt()}dp × ${c.$2} 묶음) 411dp × 1.0 — 사업장 · 기간은 구분점 뒤에서만, 기간 한 줄', (t) async {
      await _pump(t, 411, 1.0);
      final head = findVisibleText('[합성] E7 사업장 · 2026년 10월');
      expect(head, findsOneWidget);
      // 줄이 바뀌어도 '2026년 10월' 은 한 덩어리 — 그 글자 범위가 한 줄에 있다('2026 / 년 10월' 방지).
      final p = t.renderObject<RenderParagraph>(
          find.descendant(of: head, matching: find.byType(RichText), matchRoot: true).first);
      final plain = p.text.toPlainText();
      final from = plain.indexOf('2');
      final to = plain.lastIndexOf('월') + 1;
      final tops = p
          .getBoxesForSelection(TextSelection(baseOffset: from, extentOffset: to))
          .map((b) => b.top.round())
          .toSet();
      expect(tops.length, 1, reason: '기간이 줄을 나눠 갖는다');
    });

    testWidgets('RC-3 ${c.$1.toInt()}dp × ${c.$2} — 댓글은 전부 보인다(상세 화면이 없다)', (t) async {
      await _pump(t, c.$1, c.$2);
      final f = find.text('"$_comment"');
      expect(f, findsOneWidget);
      final w = t.widget<Text>(f);
      expect(w.maxLines, isNull);
      expect(w.overflow, isNot(TextOverflow.ellipsis));
    });
  }
}
