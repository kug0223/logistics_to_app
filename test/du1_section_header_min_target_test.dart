// [DU1 구현99 C99-2] SectionHeader 우측 액션 receiver — 기본값(minActionTarget null)은 예전과 같고,
//   opt-in(48)일 때만 바깥 receiver 가 48×48 이상이 된다. 14개 화면 60곳 소비처의 기본 배치를 바꾸지 않았다는 근거.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ALfit/widgets/section_header.dart';

Future<Rect> _actionRect(WidgetTester t, {double? minTarget}) async {
  t.view.physicalSize = const Size(390, 300);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(
    home: Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: SectionHeader(title: '지원 현황', actionText: '전체보기 ›', onAction: () {}, minActionTarget: minTarget),
      ),
    ),
  ));
  await t.pump();
  final recv = find.ancestor(of: find.text('전체보기 ›'), matching: find.byType(GestureDetector)).first;
  return t.getRect(recv);
}

void main() {
  testWidgets('SH-MT-1 기본값은 예전 receiver(세로 패딩 8*s)와 같다', (t) async {
    final r = await _actionRect(t);
    // 예전 구조: Padding(vertical 8, horizontal 4) + Text — 높이 = 글자 줄 + 16, 너비 = 글자 폭 + 8
    final txt = t.getRect(find.text('전체보기 ›'));
    // ignore: avoid_print
    print('SH-MT-1 기본 receiver $r · 글자 $txt');
    expect(r.height, closeTo(txt.height + 16, 0.01), reason: '기본 높이 = 글자 + 위아래 8');
    expect(r.width, closeTo(txt.width + 8, 0.01), reason: '기본 너비 = 글자 + 좌우 4');
  });

  testWidgets('SH-MT-2 opt-in 48 이면 바깥 receiver 48×48 이상·글자는 가운데', (t) async {
    final r = await _actionRect(t, minTarget: 48);
    final txt = t.getRect(find.text('전체보기 ›'));
    // ignore: avoid_print
    print('SH-MT-2 opt-in receiver $r · 글자 $txt');
    expect(r.height, greaterThanOrEqualTo(48 - 0.01));
    expect(r.width, greaterThanOrEqualTo(48 - 0.01));
    expect((txt.center.dy - r.center.dy).abs(), lessThan(0.5), reason: '글자 세로 가운데');
  });
}
