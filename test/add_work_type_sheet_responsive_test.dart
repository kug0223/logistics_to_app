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
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _helper() =>
    File('lib/utils/dialog_helper.dart').readAsStringSync();
String _sheet() =>
    File('lib/widgets/pickers/add_work_type_sheet.dart').readAsStringSync();

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

    test('WT-SHEET-05 아이콘 검색 예시가 실제 쓰임에 가깝다', () {
      final s = _sheet();
      expect(s.contains('예: 배달, 청소, 요리, 운동'), isFalse);
      expect(s.contains('예: 포장, 상하차, 홀서빙, 청소'), isTrue);
    });
  });
}
