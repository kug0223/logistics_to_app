// [R7-P4.4E.5] 새 업무유형 추가 시트 — 소스 계약.
//
//   실기기 증거: 키보드 ON 에서 `BOTTOM OVERFLOWED BY 2.0 PIXELS`.
//
//   **세로 넘침은 이번에 원인을 확정하지 못했다.** 세운 가설 두 개가 모두
//   측정으로 반증됐다(아래). 그래서 그 축은 테스트로 고정하지 않는다 —
//   돌려보지 않은 것을 통과로 적지 않는 것과 같은 이유로, **확인하지 못한
//   것을 고쳤다고 적지 않는다.** 재현 레시피는 Ledger 에 남겼다.
//
//   여기 남긴 것은 측정으로 뒷받침되는 두 가지다:
//     ① 바닥 여백 값을 두 곳이 **짐작하지 않고 한 곳에서 본다**
//     ② 색 preset 이 좁은 화면에서 줄바꿈한다(고정폭 Row 였다)
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:ALfit/widgets/pickers/add_work_type_sheet.dart';

String _helper() =>
    File('lib/utils/dialog_helper.dart').readAsStringSync();
String _sheet() =>
    File('lib/widgets/pickers/add_work_type_sheet.dart').readAsStringSync();


/// 시트를 띄운 상태로 pump 한다. [insetBottom] 이 키보드 높이다.
///
///   §4 재현 기준: **키보드 OFF 에서 넘침 0** 이어야 이 하네스를 믿을 수
///   있다. E5 에서는 OFF 에서도 깨져 충실도를 확립하지 못했고, 그래서
///   그때는 이 표를 쓰지 않았다.
Future<void> _openSheet(
  WidgetTester tester, {
  required Size size,
  double textScale = 1.0,
  double insetBottom = 0,
  double viewPaddingBottom = 6, // 실기기와 같은 조건(8dp 미만)
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  late BuildContext ctx;
  await tester.pumpWidget(
    MaterialApp(
      builder: (c, child) => MediaQuery(
        data: MediaQuery.of(c).copyWith(
          textScaler: TextScaler.linear(textScale),
          viewInsets: EdgeInsets.only(bottom: insetBottom),
          viewPadding: EdgeInsets.only(bottom: viewPaddingBottom),
          padding:
              EdgeInsets.only(bottom: insetBottom > 0 ? 0 : viewPaddingBottom),
        ),
        child: child!,
      ),
      home: Builder(builder: (c) {
        ctx = c;
        return const Scaffold(body: SizedBox.expand());
      }),
    ),
  );

  unawaited(AddWorkTypeSheet.show(ctx));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  group('[R7-P4.4E.5] 바닥 여백은 한 곳에서 온다', () {
    test('WT-SHEET-00 시트가 바깥이 넣은 값을 짐작하지 않는다', () {
      final h = _helper();
      expect(
          h.contains('static double sheetBottomInset(BuildContext context) =>'),
          isTrue,
          reason: '값이 한 곳에 있어야 두 곳이 어긋나지 않는다');
      expect(h.contains('final safeBottom = sheetBottomInset(ctx);'), isTrue,
          reason: 'helper 자신도 그 값을 쓴다');

      final s = _sheet();
      expect(s.contains('DialogHelper.sheetBottomInset(context)'), isTrue,
          reason: '예전에는 viewPadding.bottom 을 뺐는데 바깥은 max(8, vp) 를 '
              '넣고 있었다 — 홈 인디케이터가 8dp 보다 얇은 기기에서 어긋난다');
    });

    test('WT-SHEET-01 숫자를 깎아 숨기지 않았다', () {
      final s = _sheet();
      // `height - 2` / `padding - 2` 류의 눈가림이 없다.
      expect(RegExp(r'-\s*2(?:\.0)?\s*[,)]').hasMatch(s), isFalse);
    });
  });

  group('[R7-P4.4E.5] 색 preset 은 좁은 화면에서 줄바꿈한다', () {
    test('WT-SHEET-02 고정폭 Row 가 아니다', () {
      final s = _sheet();
      final i = s.indexOf('Widget _colorRow(');
      expect(i, greaterThan(-1));
      final body = s.substring(i, i + 1200);
      expect(body.contains('Wrap('), isTrue,
          reason: '320dp 가용폭 ~280 인데 swatch 8개가 288 이다 — Row 로는 넘친다');
      expect(body.contains('mainAxisAlignment: MainAxisAlignment.spaceBetween'),
          isFalse,
          reason: 'spaceBetween 은 남는 공간을 나눌 뿐 모자란 공간을 만들지 못한다');
    });

    test('WT-SHEET-03 preset 개수를 줄여 해결하지 않았다', () {
      // 색을 빼면 downstream(공고·일정·근태 카드)의 구분 수단이 줄어든다.
      final palette =
          File('lib/theme/app_colors.dart').readAsStringSync();
      final i = palette.indexOf('static const List<Color> workTypePalette');
      final block = palette.substring(i, i + 300);
      expect(RegExp(r'workType\w+').allMatches(block).length,
          greaterThanOrEqualTo(8),
          reason: '8색 preset 을 유지한다');
    });
  });

  group('[R7-P4.4E.5] 시각 정리', () {
    test('WT-SHEET-04 미리보기 글로우를 낮췄다', () {
      final s = _sheet();
      expect(s.contains('alpha: 0.4'), isFalse,
          reason: '강한 컬러 글로우가 입력란을 CTA 처럼 보이게 했다');
      expect(s.contains('_bgColor.withValues(alpha: 0.18)'), isTrue);
    });

    test('WT-SHEET-05 검색 예시는 **사전이 찾아 주는 말**이다', () {
      final s = _sheet();
      expect(s.contains('예: 배달, 청소, 요리, 운동'), isFalse,
          reason: '이 제품에서 관리자가 만드는 업무와 거리가 있다');

      // 예시로 적은 말이 실제로 매칭되는지 사전에서 확인한다.
      //   E5 에서 '상하차' 를 넣었는데 매칭이 0건이었다 — 찾으라고 적어 둔
      //   말이 안 찾아지면 검색이 고장난 것처럼 보인다.
      final hint = RegExp(r"hintText: '예: ([^']+)'").firstMatch(s);
      expect(hint, isNotNull, reason: '검색 예시 문구를 찾지 못했다');
      final terms = hint!.group(1)!.split(',').map((t) => t.trim());

      final dict = File('lib/widgets/pickers/icon_picker_dialog.dart')
          .readAsStringSync();
      for (final t in terms) {
        expect(dict.contains("'$t'"), isTrue,
            reason: '"$t" 는 아이콘 사전에 없다 — 검색해도 0건이다');
      }
    });
  });

  group('[R7-P4.4E.5.1] 반응형 — 넘침 0', () {
    // §4 재현 기준: 키보드 OFF 에서 0 이어야 하네스를 믿을 수 있다.
    //   E5 에서는 OFF 에서도 깨져 하네스 충실도를 확립하지 못했다.
    //   원인(고정 높이 상자)을 없애자 OFF 가 0 이 됐고, 그래서 이 표가
    //   비로소 의미를 갖는다.
    for (final w in const [320.0, 360.0, 411.0]) {
      testWidgets('WT-UX-0${w == 320.0 ? 1 : (w == 360.0 ? 5 : 6)} '
          '${w.toInt()}dp 키보드 OFF/ON', (tester) async {
        await _openSheet(tester, size: Size(w, 740));
        expect(tester.takeException(), isNull, reason: '${w.toInt()}dp OFF');

        await _openSheet(tester, size: Size(w, 740), insetBottom: 320);
        expect(tester.takeException(), isNull, reason: '${w.toInt()}dp ON');
      });
    }

    testWidgets('WT-UX-04 320dp × 배율 2.0 × 키보드 ON', (tester) async {
      await _openSheet(tester,
          size: const Size(320, 740), textScale: 2.0, insetBottom: 320);
      expect(tester.takeException(), isNull);
    });

    testWidgets('WT-UX-04b 320dp × 배율 1.3 · 411dp × 배율 2.0', (tester) async {
      await _openSheet(tester,
          size: const Size(320, 740), textScale: 1.3, insetBottom: 320);
      expect(tester.takeException(), isNull, reason: '320 × 1.3');

      await _openSheet(tester,
          size: const Size(411, 740), textScale: 2.0, insetBottom: 320);
      expect(tester.takeException(), isNull, reason: '411 × 2.0');
    });
  });

  group('[R7-P4.4E.5.1] 키보드 ON 에서 저장까지 닿는다', () {
    testWidgets('WT-UX-03 320dp 키보드 ON — 스크롤로 저장 버튼에 닿는다',
        (tester) async {
      await _openSheet(tester, size: const Size(320, 740), insetBottom: 320);
      // 모든 것이 한 화면에 보일 필요는 없다 — 스크롤로 닿으면 된다(§19).
      final scroll = find.byType(SingleChildScrollView);
      expect(scroll, findsWidgets);
      await tester.drag(scroll.first, const Offset(0, -600));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.text('추가'), findsOneWidget, reason: '저장 CTA 에 닿아야 한다');
    });

    testWidgets('WT-UX-11 빈 이름으로는 저장할 수 없다', (tester) async {
      await _openSheet(tester, size: const Size(360, 740));
      final scroll = find.byType(SingleChildScrollView);
      await tester.drag(scroll.first, const Offset(0, -600));
      await tester.pump();
      final btn = tester.widget<ElevatedButton>(
          find.ancestor(of: find.text('추가'), matching: find.byType(ElevatedButton)));
      expect(btn.onPressed, isNull, reason: '이름이 비면 저장이 열리지 않는다');
    });
  });

  group('[R7-P4.4E.5.1] 고정 높이 상자를 없앴다', () {
    test('WT-UX-15 아이콘 줄은 내용이 높이를 정한다', () {
      final s = _sheet();
      final i = s.indexOf("Widget _iconRow(");
      final body = s.substring(i, i + 2600);
      expect(body.contains('height: ResponsiveHelper.spacing(context, 80)'),
          isFalse,
          reason: '상자는 폭에 따라 줄고 칩은 고정이라 좁은 화면에서 넘쳤다');
      expect(body.contains('SingleChildScrollView('), isTrue);
      expect(body.contains('scrollDirection: Axis.horizontal'), isTrue);
    });

    test('WT-UX-16 제목과 라벨이 공간을 양보한다', () {
      final s = _sheet();
      // 줄바꿈 모양이 아니라 **성질**을 본다 — 제목이 줄 수 있어야 한다.
      final i = s.indexOf("_isEdit ? '업무유형 수정' : '새 업무유형 추가'");
      expect(i, greaterThan(-1));
      final around = s.substring(i - 400, i + 300);
      expect(around.contains('Expanded('), isTrue,
          reason: '제목이 줄지 못해 배율 2.0 에서 96px 넘쳤다');
      expect(around.contains('maxLines: 2'), isTrue,
          reason: '큰 배율에서는 잘라내기 전에 줄바꿈한다');
      expect(s.contains("Expanded(child: _label('아이콘')),"), isTrue);
      // Spacer 로 되돌아가지 않는다.
      expect(s.contains('const Spacer(),'), isFalse);
    });
  });
}
