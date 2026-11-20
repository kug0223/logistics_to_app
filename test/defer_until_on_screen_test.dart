// [.20 PERCEIVED-PERFORMANCE] DeferUntilOnScreen — 화면 근처에 오기 전에는 child 를 만들지 않는다.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ALfit/widgets/common/defer_until_on_screen.dart';

Widget _page({required double above}) => MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: Column(
            children: [
              SizedBox(height: above),
              const SizedBox(
                height: 180,
                child: DeferUntilOnScreen(
                  placeholder: Text('PLACEHOLDER'),
                  child: Text('HEAVY'),
                ),
              ),
              const SizedBox(height: 400),
            ],
          ),
        ),
      ),
    );

/// 위쪽 영역이 진입 뒤에 채워지는 화면(공고 상세처럼) — [grown] 이 되면 위가 3000 으로 늘어난다.
class _Growing extends StatefulWidget {
  const _Growing();
  @override
  State<_Growing> createState() => _GrowingState();
}

class _GrowingState extends State<_Growing> {
  bool grown = false;
  @override
  void initState() {
    super.initState();
    Future<void>.delayed(const Duration(milliseconds: 300), () {
      if (mounted) setState(() => grown = true);
    });
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: Column(children: [
              SizedBox(height: grown ? 3000 : 50),
              const SizedBox(
                height: 180,
                child: DeferUntilOnScreen(placeholder: Text('PLACEHOLDER'), child: Text('HEAVY')),
              ),
            ]),
          ),
        ),
      );
}

void main() {
  testWidgets('DU-1 화면 아래 멀리 있으면 진입 때 child 를 만들지 않는다', (t) async {
    await t.pumpWidget(_page(above: 3000));
    await t.pump(const Duration(seconds: 2));
    expect(find.text('PLACEHOLDER'), findsOneWidget);
    expect(find.text('HEAVY'), findsNothing);
  });

  testWidgets('DU-2 스크롤로 다가오면 child 로 바뀐다(한 번 만든 뒤 유지)', (t) async {
    await t.pumpWidget(_page(above: 3000));
    await t.pump();
    await t.drag(find.byType(SingleChildScrollView), const Offset(0, -2600));
    await t.pump();
    expect(find.text('HEAVY'), findsOneWidget);
    await t.drag(find.byType(SingleChildScrollView), const Offset(0, 2600));
    await t.pump();
    // 되돌아가도 다시 placeholder 로 바꾸지 않는다(스크롤 밖이라 화면엔 없을 수 있음 → skipOffstage false 로 확인)
    expect(find.text('HEAVY', skipOffstage: false), findsOneWidget);
    expect(find.text('PLACEHOLDER', skipOffstage: false), findsNothing);
  });

  testWidgets('DU-3 처음부터 화면 안이면 자리 잡은 뒤(settle) child', (t) async {
    await t.pumpWidget(_page(above: 100));
    await t.pump();
    expect(find.text('HEAVY'), findsNothing, reason: '진입 직후 첫 프레임에서는 판정하지 않는다');
    await t.pump(const Duration(milliseconds: 1300));
    expect(find.text('HEAVY'), findsOneWidget);
  });

  testWidgets('DU-4 진입 직후 잠깐 화면 안이었다가 위쪽이 채워져 밀려나면 만들지 않는다(기기 실측 회귀)', (t) async {
    await t.pumpWidget(const _Growing());
    await t.pump();
    await t.pump(const Duration(milliseconds: 400)); // 위쪽 영역이 채워짐
    await t.pump(const Duration(seconds: 2)); // settle 지남
    expect(find.text('HEAVY', skipOffstage: false), findsNothing);
    expect(find.text('PLACEHOLDER', skipOffstage: false), findsOneWidget);
  });

  testWidgets('DU-5 dispose 뒤 타이머·스크롤 리스너가 남지 않는다(예외 없음)', (t) async {
    await t.pumpWidget(_page(above: 3000));
    await t.pump();
    await t.pumpWidget(const MaterialApp(home: SizedBox()));
    await t.pump(const Duration(seconds: 2));
    expect(t.takeException(), isNull);
  });
}
