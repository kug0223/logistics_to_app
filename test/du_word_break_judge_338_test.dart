// [DU338] 공용 낱말 안 줄바꿈 판정기(support/du_word_break.dart) 작은 사례 — 소급 감사 6 §4 '판정기 사례 확인'.
//   들어가는 낱말 · 넘는 낱말(여러 줄 연속 분절) · 개행 · 표시 제어 문자(WJ · NBSP · ZWSP) · 낱말 단위 조판 뒤.
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ALfit/utils/text_layout.dart';

import 'support/du1_vq_capture.dart';
import 'support/du_word_break.dart';

Future<List<WordBreak>> _judge(WidgetTester t, String text, double width) async {
  await t.pumpWidget(MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: ThemeData(fontFamily: 'NotoSansKR'),
    home: Scaffold(
      body: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(width: width, child: Text(text, style: const TextStyle(fontSize: 20))),
      ),
    ),
  ));
  await t.pump();
  final rp = t.renderObject<RenderParagraph>(find.byType(RichText).first);
  return wordBreaks(rp);
}

void main() {
  testWidgets('판정기 사례 — 들어가는 낱말 · 넘는 낱말 · 개행 · 표시 제어 문자', (t) async {
    await t.runAsync(vqLoadFonts);
    // 한 글자 약 20px. 폭 100 ≈ 5글자.
    // ① 들어가는 낱말이 음절로 갈림 → avoidable(그냥 Text 는 한글 음절 사이에서 줄을 바꾼다)
    final a = await _judge(t, '가나 다라마바사', 100);
    // ignore: avoid_print
    print('① $a');
    expect(a.where((b) => !b.forced), isNotEmpty, reason: '들어가는 낱말 음절 끊김은 avoidable');
    // ② 같은 글을 keepWords 로 → 낱말 안 끊김 0
    final b = await _judge(t, TextLayout.keepWords('가나 다라마바사'), 100);
    // ignore: avoid_print
    print('② $b');
    expect(b, isEmpty, reason: 'keepWords 뒤 들어가는 낱말은 끊기지 않는다');
    // ③ 문단보다 넓은 낱말(12글자) keepWords → 여러 줄 연속 분절이 모두 forced, avoidable 0
    final c = await _judge(t, TextLayout.keepWords('가 나다라마바사아자차카타파하'), 100);
    // ignore: avoid_print
    print('③ $c');
    expect(c.where((x) => !x.forced), isEmpty, reason: '넘는 낱말 안 분절은 forced');
    expect(c.where((x) => x.forced).length, greaterThanOrEqualTo(2), reason: '공백 없는 연속 분절도 센다');
    // ④ 개행 — 개행 자체는 끊김이 아니다
    final d = await _judge(t, '가나\n다라', 300);
    // ignore: avoid_print
    print('④ $d');
    expect(d, isEmpty);
    // ⑤ ZWSP 자리(TextLayout.identity 가 긴 이름 가운데에 넣는 줄바꿈 자리)에서 바뀐 줄은 끊김이 아니다
    final e = await _judge(t, TextLayout.identity('가나다라마바사아자차'), 120);
    // ignore: avoid_print
    print('⑤ $e');
    expect(e.where((x) => !x.forced), isEmpty, reason: 'ZWSP 경계는 낱말 경계');
    // ⑥ NBSP 로 붙인 구분점(phrases) — 구분점 앞에서 바뀌지 않는다
    final f = await _judge(t, TextLayout.phrases('가나다 · 라마바사'), 110);
    // ignore: avoid_print
    print('⑥ $f');
    expect(f.where((x) => !x.forced), isEmpty);
  });
}
