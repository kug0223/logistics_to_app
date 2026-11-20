// [DEVICE-MISMATCH-FIX] 탭 라벨은 잘리지 않는다.
//
// DEVICE 관찰(Pixel 5, 원본 APK 1.0.21): 급여 지급 현황 탭이 `미… 2 / 이체현황 /
//   변… 0 / 중… 0`, 당일명단 탭이 `확인… 1 / 정상 1 / 확인… 0 / 처리… 0` 이었다.
//
// root cause: AppTabLabel 이 라벨과 배지를 **둘 다 같은 flex** 로 감쌌다. Row 는
//   남는 폭을 flex 비율로 나눠 주고, 배지가 다 쓰지 않은 몫은 라벨에게 돌아가지
//   않는다 → 탭 폭이 충분해도 라벨은 절반까지만 받고 한 줄 말줄임으로 잘렸다.
//
// 측정 자: 번들 NotoSansKR(기기 한글 폰트에 가장 가까운 자). 기본 테스트 폰트는
//   한글을 약 30% 넓게 재므로 쓰지 않는다.
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ALfit/widgets/common/app_tab_label.dart';

const _font = 'NotoSansKR';
const _pixel5Width = 1080 / 2.625; // 411.43dp

Future<void> _loadFont() async {
  final loader = FontLoader(_font);
  for (final f in const ['Regular', 'Bold']) {
    loader.addFont(rootBundle
        .load('assets/fonts/NotoSansKR-$f.ttf')
        .then((b) => ByteData.sublistView(b.buffer.asUint8List())));
  }
  await loader.load();
}

typedef _Spec = ({String label, int? count});

/// 실제 화면과 같은 TabBar 설정(라벨 패딩·라벨 스타일)으로 그린다.
Future<void> _pumpTabs(
  WidgetTester t, {
  required List<_Spec> tabs,
  required double width,
  required double labelPadding,
  required FontWeight weight,
  double textScale = 1.0,
  Widget Function(_Spec s)? labelBuilder,
}) async {
  t.view.physicalSize = Size(_pixel5Width, 800);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(
    theme: ThemeData(fontFamily: _font),
    home: MediaQuery(
      data: MediaQueryData(
        size: const Size(_pixel5Width, 800),
        textScaler: TextScaler.linear(textScale),
      ),
      child: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: width,
            child: DefaultTabController(
              length: tabs.length,
              child: TabBar(
                isScrollable: false,
                labelPadding: EdgeInsets.symmetric(horizontal: labelPadding),
                labelStyle: TextStyle(fontSize: 13, fontWeight: weight),
                unselectedLabelStyle: const TextStyle(fontSize: 13),
                tabs: [
                  for (final s in tabs)
                    Tab(
                        child: labelBuilder?.call(s) ??
                            AppTabLabel(label: s.label, count: s.count)),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  ));
  await t.pump();
}

/// 라벨 문단이 **전부** 그려졌는가(말줄임 없음)와 줄 수.
({bool truncated, int lines}) _measure(WidgetTester t, String label) {
  final rp = t.renderObject<RenderParagraph>(find.text(label));
  final boxes = rp.getBoxesForSelection(
      TextSelection(baseOffset: 0, extentOffset: label.length));
  final tops = boxes.map((b) => b.top.roundToDouble()).toSet();
  return (truncated: rp.didExceedMaxLines, lines: tops.length);
}

const _payroll = <_Spec>[
  (label: '미이체', count: 2),
  (label: '이체현황', count: null),
  (label: '변경요청', count: 0),
  (label: '중간정산', count: 0),
];
const _roster = <_Spec>[
  (label: '확인필요', count: 1),
  (label: '정상', count: 1),
  (label: '확인완료', count: 0),
  (label: '처리완료', count: 0),
];

/// 고치기 전 구조 — 라벨·배지 둘 다 같은 flex, 라벨 한 줄 말줄임.
Widget _legacy(_Spec s) => Row(mainAxisSize: MainAxisSize.min, children: [
      Flexible(
          child: Text(s.label, maxLines: 1, overflow: TextOverflow.ellipsis)),
      const SizedBox(width: 3),
      Flexible(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 2),
          child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text('${s.count ?? 0}',
                  style: const TextStyle(fontSize: 12))),
        ),
      ),
    ]);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(_loadFont);

  // 당일명단 시트: 화면 폭 − listPadding 좌우 16.
  const rosterWidth = _pixel5Width - 32;

  group('재현 — 고치기 전 구조는 같은 폭에서 라벨을 자른다', () {
    testWidgets('TL-0a 급여 탭(라벨 패딩 14) — 배지 있는 탭이 말줄임', (t) async {
      await _pumpTabs(t,
          tabs: _payroll,
          width: _pixel5Width,
          labelPadding: 14,
          weight: FontWeight.w600,
          labelBuilder: (s) => s.count == null ? Text(s.label) : _legacy(s));
      final cut = [
        for (final s in _payroll)
          if (s.count != null && _measure(t, s.label).truncated) s.label
      ];
      expect(cut, isNotEmpty, reason: '옛 구조가 잘리지 않으면 재현이 아니다');
    });

    testWidgets('TL-0b 당일명단 탭(라벨 패딩 0) — 4글자 라벨이 말줄임', (t) async {
      await _pumpTabs(t,
          tabs: _roster,
          width: rosterWidth,
          labelPadding: 0,
          weight: FontWeight.bold,
          labelBuilder: _legacy);
      final cut = [
        for (final s in _roster)
          if (_measure(t, s.label).truncated) s.label
      ];
      expect(cut, isNotEmpty, reason: '옛 구조가 잘리지 않으면 재현이 아니다');
    });
  });

  group('수정 — 라벨 전체가 보인다', () {
    for (final scale in const [1.0, 1.3]) {
      testWidgets('TL-1 급여 탭 · 배율 $scale — 말줄임 0, 넘침 0', (t) async {
        await _pumpTabs(t,
            tabs: _payroll,
            width: _pixel5Width,
            labelPadding: 14,
            weight: FontWeight.w600,
            textScale: scale);
        expect(t.takeException(), isNull);
        for (final s in _payroll) {
          final m = _measure(t, s.label);
          expect(m.truncated, isFalse, reason: '${s.label} 이 잘렸다');
          if (scale == 1.0) {
            expect(m.lines, 1, reason: '${s.label} 은 기본 배율에서 한 줄이어야 한다');
          }
        }
      });

      testWidgets('TL-2 당일명단 탭 · 배율 $scale — 말줄임 0, 넘침 0', (t) async {
        await _pumpTabs(t,
            tabs: _roster,
            width: rosterWidth,
            labelPadding: 0,
            weight: FontWeight.bold,
            textScale: scale);
        expect(t.takeException(), isNull);
        for (final s in _roster) {
          final m = _measure(t, s.label);
          expect(m.truncated, isFalse, reason: '${s.label} 이 잘렸다');
          if (scale == 1.0) {
            expect(m.lines, 1, reason: '${s.label} 은 기본 배율에서 한 줄이어야 한다');
          }
        }
      });
    }

    testWidgets('TL-3 숫자 배지는 그대로 보인다', (t) async {
      await _pumpTabs(t,
          tabs: _payroll,
          width: _pixel5Width,
          labelPadding: 14,
          weight: FontWeight.w600);
      expect(find.text('2'), findsOneWidget);
      expect(find.text('0'), findsNWidgets(2));
    });
  });
}
