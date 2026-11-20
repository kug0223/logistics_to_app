// [DU1 R8] 탭 shell 의 시스템 뒤로가 탭 안 화면의 PopScope 를 따르는지.
//   기기(D3)에서 프로필 관리: AppBar 뒤로 → 확인 창, 시스템 뒤로 → 확인 없이 나감.
//   원인: shell 이 탭 Navigator 에 pop() 을 직접 불렀다(PopScope 무시). maybePop() 으로 바꾼다.
//   (1) 두 shell 소스 계약 (2) 같은 구조(루트 PopScope + 탭 Navigator + 안쪽 PopScope)에서
//   실제 시스템 뒤로(handlePopRoute)로 pop 과 maybePop 의 차이를 확인한다. 실제 shell 렌더는 기기 증거가 맡는다.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

String _code(String p) => File(p)
    .readAsLinesSync()
    .where((l) => !l.trimLeft().startsWith('//'))
    .join('\n');

class _Shell extends StatelessWidget {
  const _Shell({required this.navKey, required this.useMaybePop});
  final GlobalKey<NavigatorState> navKey;
  final bool useMaybePop;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (navKey.currentState?.canPop() == true) {
          useMaybePop ? navKey.currentState!.maybePop() : navKey.currentState!.pop();
        }
      },
      child: Navigator(
        key: navKey,
        onGenerateRoute: (s) => MaterialPageRoute(
          settings: s,
          builder: (ctx) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => Navigator.of(ctx).push(MaterialPageRoute(builder: (_) => const _Guarded())),
                child: const Text('열기'),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Guarded extends StatefulWidget {
  const _Guarded();
  @override
  State<_Guarded> createState() => _GuardedState();
}

class _GuardedState extends State<_Guarded> {
  bool asked = false;
  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) setState(() => asked = true);
      },
      child: Scaffold(body: Text(asked ? '확인 창' : '편집 중')),
    );
  }
}

Future<void> _open(WidgetTester tester, bool useMaybePop) async {
  await tester.pumpWidget(MaterialApp(home: _Shell(navKey: GlobalKey<NavigatorState>(), useMaybePop: useMaybePop)));
  await tester.tap(find.text('열기'));
  await tester.pumpAndSettle();
  expect(find.text('편집 중'), findsOneWidget);
  await tester.binding.handlePopRoute(); // 실제 시스템 뒤로
  await tester.pumpAndSettle();
}

void main() {
  test('[R8] 두 shell 은 탭 Navigator 에 maybePop 을 쓴다(pop 직접 호출 없음)', () {
    for (final p in const [
      'lib/screens/user/user_root_screen.dart',
      'lib/screens/business_admin/business_admin_shell.dart',
    ]) {
      final src = _code(p);
      expect(src.contains('navKey.currentState!.maybePop();'), isTrue, reason: p);
      expect(src.contains('navKey.currentState!.pop();'), isFalse, reason: p);
    }
  });

  testWidgets('[R8] 결함 재현 — pop() 은 안쪽 PopScope 를 건너뛰고 화면을 닫는다', (tester) async {
    await _open(tester, false);
    expect(find.text('편집 중'), findsNothing);
    expect(find.text('확인 창'), findsNothing);
    expect(find.text('열기'), findsOneWidget);
  });

  testWidgets('[R8] maybePop() 은 안쪽 PopScope 를 따른다 — 닫지 않고 확인을 연다', (tester) async {
    await _open(tester, true);
    expect(find.text('확인 창'), findsOneWidget);
    expect(find.text('열기'), findsNothing);
  });
}
