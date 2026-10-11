// [R8-INTEGRATED §G] 같은 앱의 다이얼로그가 입구에 따라 다른 폭으로 뜬다.
//
// 이 앱의 모달은 두 셸로 그려진다.
//   · `DialogHelper._buildDialog` — showAlert/showConfirm/showError 등이 쓴다
//   · `StyledDialog` 위젯 — 화면·위젯 30여 곳이 직접 쓴다
// 머리·버튼·색은 같은 값을 쓰고 있다(radius 24, 아이콘 44×44, 제목 #111827).
// **좌우 여백만 다르다** — 32 vs 16. 그래서 같은 폰에서 두 다이얼로그의
// 폭이 다르다. 소스만 보면 "둘 다 표준 셸"로 읽히므로 실제로 재서 못박는다.
//
// 이 셀은 어느 쪽이 옳다고 말하지 않는다. **지금 값이 얼마나 벌어져 있는지**를
// 기록해, 한쪽으로 모을 때 무엇이 바뀌는지 알고 바꾸게 한다.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ALfit/utils/dialog_helper.dart';
import 'package:ALfit/widgets/dialogs/styled_dialog.dart';

/// 화면에 떠 있는 `Dialog` 의 실제 가로 폭.
/// 눈에 보이는 카드의 폭. `Dialog` 엘리먼트 자체는 화면 전체를 차지한다
/// (`AnimatedPadding` 이 여백을 안쪽에서 준다) — 그래서 흰 카드를 그리는
/// `Material` 을 재야 실제 폭이 나온다.
double _dialogWidth(WidgetTester t) {
  final card = find
      .descendant(of: find.byType(Dialog), matching: find.byType(Material))
      .first;
  return t.getRect(card).width;
}

var _hostSeq = 0;

/// 호스트를 **새로** 세운다.
///
/// `pumpWidget` 에 구조가 같은 트리를 주면 Flutter 는 엘리먼트를 재사용하고
/// Navigator 도 그대로 남는다 — 그래서 앞 셀에서 띄운 다이얼로그가 계속
/// 떠 있었다(`Dialog` 가 두 개로 잡혔다). 매번 다른 key 를 줘서 끊는다.
Future<void> _pumpHost(WidgetTester t, Size size,
    {required void Function(BuildContext) open}) async {
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);

  late BuildContext ctx;
  await t.pumpWidget(MaterialApp(
    key: ValueKey('host${_hostSeq++}'),
    home: Builder(builder: (c) {
      ctx = c;
      return const Scaffold(body: SizedBox.expand());
    }),
  ));
  open(ctx);
  await t.pumpAndSettle();
  expect(find.byType(Dialog), findsOneWidget,
      reason: '다이얼로그가 하나만 떠 있어야 한다');
}

void main() {
  const widths = [320.0, 360.0, 411.0];

  group('DLG-01 두 셸의 폭 — 실측', () {
    for (final w in widths) {
      testWidgets('화면 폭 ${w.toStringAsFixed(0)}dp', (t) async {
        await _pumpHost(t, Size(w, 800), open: (c) {
          DialogHelper.showAlert(c, title: '안내', message: '한 줄 메시지입니다.');
        });
        final helperW = _dialogWidth(t);

        await _pumpHost(t, Size(w, 800), open: (c) {
          showDialog(
            context: c,
            builder: (_) => const StyledDialog(
              title: '안내',
              icon: Icons.info_outline,
              content: Text('한 줄 메시지입니다.'),
            ),
          );
        });
        final styledW = _dialogWidth(t);

        // DialogHelper: insetPadding 좌우 32 → 화면폭 - 64 (단 maxWidth 380)
        expect(helperW, w - 64,
            reason: 'DialogHelper 셸의 폭이 바뀌었다 (insetPadding 32)');
        // StyledDialog: insetPadding 좌우 16 → 화면폭 - 32, maxWidth 없음
        expect(styledW, w - 32,
            reason: 'StyledDialog 셸의 폭이 바뀌었다 (insetPadding 16)');
        // 지금 벌어진 간격 — 한쪽으로 모으면 이 값이 0 이 된다.
        expect(styledW - helperW, 32.0,
            reason: '두 셸의 폭 차이가 바뀌었다 — 통합했다면 이 셀을 고쳐라');
        expect(t.takeException(), isNull);
      });
    }
  });

  testWidgets('DLG-02 넓은 화면에서는 DialogHelper 가 380 에서 멈춘다', (t) async {
    // maxWidth 380 은 DialogHelper 쪽에만 있다. 태블릿 폭에서 두 셸의
    // 차이가 32 가 아니라 훨씬 커진다 — 같은 앱의 모달로 보이지 않는다.
    await _pumpHost(t, const Size(800, 900), open: (c) {
      DialogHelper.showAlert(c, title: '안내', message: '한 줄');
    });
    expect(_dialogWidth(t), 380.0);

    await _pumpHost(t, const Size(800, 900), open: (c) {
      showDialog(
        context: c,
        builder: (_) => const StyledDialog(
          title: '안내',
          icon: Icons.info_outline,
          content: Text('한 줄'),
        ),
      );
    });
    expect(_dialogWidth(t), 768.0, reason: '800 - 32');
    expect(t.takeException(), isNull);
  });

  testWidgets('DLG-03 공유하는 값은 실제로 같다 — 폭만 다르다', (t) async {
    // 모서리·아이콘 상자·제목색은 두 셸이 같은 값을 쓴다. 그래서 이 결함은
    // "두 디자인 체계"가 아니라 **한 체계의 여백 불일치**다. 범위를 좁혀
    // 둬야 통합이 전면 재작성으로 번지지 않는다.
    for (final build in <void Function(BuildContext)>[
      (c) => DialogHelper.showAlert(c, title: '안내', message: 'x'),
      (c) => showDialog(
            context: c,
            builder: (_) => const StyledDialog(
              title: '안내',
              icon: Icons.info_outline,
              content: Text('x'),
            ),
          ),
    ]) {
      await _pumpHost(t, const Size(360, 800), open: build);

      final shape = t.widget<Dialog>(find.byType(Dialog)).shape;
      expect(
          shape,
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          reason: '모서리 반경');

      // 아이콘 상자 44×44 — 두 셸 공통.
      final box = find.byWidgetPredicate((widget) =>
          widget is Container &&
          widget.constraints?.maxWidth == 44 &&
          widget.constraints?.maxHeight == 44);
      expect(box, findsOneWidget, reason: '아이콘 상자 44×44');

      final title = t.widget<Text>(find.text('안내'));
      expect(title.style?.color, const Color(0xFF111827), reason: '제목 색');
      expect(t.takeException(), isNull);
    }
  });
}
