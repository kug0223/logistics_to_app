// [BTN-FG-01] 채워진 버튼의 글자색이 `foregroundColor` 를 따르는가.
//
// ── 무엇이 잘못됐었나 ──────────────────────────────────────────────
//   약관 상세(`terms_viewer_screen.dart`)의 `동의하고 닫기` 버튼은
//   `foregroundColor: Colors.white` 를 주고도 **회색 글자**로 찍혔다.
//   자식 위젯이 `Text(style: ResponsiveHelper.bodyStyle(context, ...))` 였고,
//   그 helper 는 `color` 를 안 넘기면 `AppColors.grey700` 을 **항상** 채운다.
//   위젯 자신의 style 은 DefaultTextStyle 을 이기므로 버튼의 전경색이 졌다.
//
//   Flutter 는 `ButtonStyle.textStyle` 의 색은
//   `textStyle.copyWith(color: resolvedForegroundColor)` 로 덮는다
//   (`button_style_button.dart`). 그래서 같은 스타일이라도
//   **버튼 style 에 주면 안전하고, 자식 Text 에 주면 새어 나온다.**
//   비활성 색(`disabledForegroundColor`)도 같은 규칙을 탄다 —
//   그래서 "흰색 하드코딩" 이 아니라 스타일 위치를 옮기는 것이 옳은 수정이다.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ALfit/theme/app_colors.dart';
import 'package:ALfit/utils/responsive_helper.dart';

/// 버튼 안에서 실제로 그려진 글자색.
Color? _renderedTextColor(WidgetTester tester, String label) {
  final el = tester.element(find.text(label));
  final defaultStyle = DefaultTextStyle.of(el).style;
  final widget = el.widget as Text;
  final own = widget.style;
  if (own == null) return defaultStyle.color;
  return own.inherit ? defaultStyle.merge(own).color : own.color;
}

Future<void> _pump(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(MaterialApp(
    theme: ThemeData(primaryColor: const Color(0xFF1565C0)),
    home: Scaffold(body: Center(child: child)),
  ));
  await tester.pump();
}

void main() {
  group('BTN-FG-01 반례 — 자식 Text 에 색 있는 스타일을 주면 샌다', () {
    testWidgets('수정 전 형태: foregroundColor 가 무시된다', (tester) async {
      // 고친 코드가 아니라 **예전 형태**를 그대로 재현한다.
      await _pump(
        tester,
        Builder(builder: (ctx) {
          return ElevatedButton(
            onPressed: () {},
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1565C0),
              foregroundColor: Colors.white,
            ),
            child: Text(
              '동의하고 닫기',
              style: ResponsiveHelper.bodyStyle(
                ctx,
                fontWeight: FontWeight.w600,
              ),
            ),
          );
        }),
      );

      expect(_renderedTextColor(tester, '동의하고 닫기'), AppColors.grey700,
          reason: '흰색이 아니라 helper 기본 회색이 찍힌다 — 이것이 신고된 증상');
      expect(_renderedTextColor(tester, '동의하고 닫기'), isNot(Colors.white));
    });
  });

  group('BTN-FG-01 정상 — 버튼 style 에 주면 전경색이 이긴다', () {
    testWidgets('활성: 흰색으로 찍힌다', (tester) async {
      await _pump(
        tester,
        Builder(builder: (ctx) {
          return ElevatedButton(
            onPressed: () {},
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1565C0),
              foregroundColor: Colors.white,
              disabledForegroundColor: AppColors.grey400,
              textStyle: ResponsiveHelper.bodyStyle(
                ctx,
                fontWeight: FontWeight.w600,
              ),
            ),
            child: const Text('동의하고 닫기'),
          );
        }),
      );

      expect(_renderedTextColor(tester, '동의하고 닫기'), Colors.white);
    });

    testWidgets('비활성: 흰색이 아니라 비활성 색을 따른다', (tester) async {
      // 여기가 "흰색 하드코딩" 이 틀린 수정인 이유다 —
      // 하드코딩하면 회색 배경 위에 흰 글자가 남는다.
      await _pump(
        tester,
        Builder(builder: (ctx) {
          return ElevatedButton(
            onPressed: null, // 비활성
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1565C0),
              disabledBackgroundColor: AppColors.grey200,
              foregroundColor: Colors.white,
              disabledForegroundColor: AppColors.grey400,
              textStyle: ResponsiveHelper.bodyStyle(
                ctx,
                fontWeight: FontWeight.w600,
              ),
            ),
            child: const Text('내용을 끝까지 확인해주세요'),
          );
        }),
      );

      expect(_renderedTextColor(tester, '내용을 끝까지 확인해주세요'),
          AppColors.grey400);
      expect(_renderedTextColor(tester, '내용을 끝까지 확인해주세요'),
          isNot(Colors.white),
          reason: '비활성 배경(grey200) 위에 흰 글자가 남으면 안 읽힌다');
    });

    testWidgets('글자 크기·굵기는 그대로 유지된다', (tester) async {
      await _pump(
        tester,
        Builder(builder: (ctx) {
          return ElevatedButton(
            onPressed: () {},
            style: ElevatedButton.styleFrom(
              foregroundColor: Colors.white,
              textStyle: ResponsiveHelper.bodyStyle(
                ctx,
                fontWeight: FontWeight.w600,
              ),
            ),
            child: const Text('동의하고 닫기'),
          );
        }),
      );
      final el = tester.element(find.text('동의하고 닫기'));
      final s = DefaultTextStyle.of(el).style;
      expect(s.fontSize, 15, reason: 'bodyStyle 의 크기');
      expect(s.fontWeight, FontWeight.w600);
    });
  });

  group('BTN-FG-01 소스 — 같은 실수가 다시 들어오지 않게 한다', () {
    test('약관 상세와 로그인 완료 버튼은 스타일을 버튼 style 에 준다', () {
      for (final path in const [
        'lib/widgets/auth/terms_viewer_screen.dart',
        'lib/screens/auth/login_screen.dart',
      ]) {
        final src = _read(path);
        expect(src.contains('[BTN-FG-01]'), isTrue,
            reason: '$path 에 수정 근거 주석이 남아 있어야 한다');
      }

      // 약관 상세: 자식 Text 에 style 인자가 없어야 한다.
      final terms = _read('lib/widgets/auth/terms_viewer_screen.dart');
      final i = terms.indexOf("_reachedBottom ? '동의하고 닫기'");
      expect(i, greaterThan(-1));
      // 그 Text 호출 안(닫는 괄호까지)에 style: 이 없어야 한다.
      final tail = terms.substring(i, i + 160);
      expect(tail.contains('style:'), isFalse,
          reason: '글자색은 버튼 style 이 정한다');
    });
  });
}

String _read(String p) {
  final f = File(p);
  expect(f.existsSync(), isTrue, reason: '$p 를 찾지 못함');
  return f.readAsStringSync().replaceAll('\r\n', '\n');
}
