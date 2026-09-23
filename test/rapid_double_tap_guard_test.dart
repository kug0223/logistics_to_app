// [R7-P1-CORR] 빠른 연속 탭 — 같은 모달 1개 / 같은 mutation 1회.
//
// 이 테스트가 지키는 사실은 하나다: `showDialog`가 route를 동기로 push해도
// 그 route의 ModalBarrier는 **다음 프레임**에야 화면을 덮는다. 그 한 프레임
// 동안 두 번째 탭은 여전히 아래 버튼에 닿는다. 그래서 시간이 아니라 상태로
// 막아야 한다.
//
// 01 그룹은 그 메커니즘을 실제 Flutter gesture/Navigator 파이프라인에서
// 재현한다 — 가드 없는 버전이 정말로 2개를 띄우는지 **먼저** 확인한 뒤,
// 가드를 건 버전이 1개로 수렴하는지 본다. 깨지는 것을 보지 않고 고쳤다고
// 말하지 않기 위해서다.
//
// 03 그룹은 실제 호출부가 이 계약을 쓰고 있는지 소스에서 확인한다.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ALfit/utils/action_guard.dart';

// ── 소스 계약 검사 helper ────────────────────────────────────────────────
String _src(String path) => File(path).readAsStringSync();

/// `//` 주석 줄을 지운다 — 주석에 적힌 문구가 계약을 만족시키지 못하게 한다.
String _codeOf(String src) => src
    .split('\n')
    .where((l) => !l.trimLeft().startsWith('//'))
    .join('\n');

/// [sig]로 시작하는 선언의 본문. 파라미터 괄호를 **먼저** 닫고 나서 본문
/// 중괄호를 찾는다 — Dart named parameter `({...})`가 본문처럼 보이기 때문이다.
String _bodyOf(String src, String sig) {
  final start = src.indexOf(sig);
  if (start < 0) throw StateError('$sig 를 찾지 못함');
  var i = start + sig.length;
  var paren = 0;
  var sawParen = false;
  for (; i < src.length; i++) {
    final c = src[i];
    if (c == '(') {
      paren++;
      sawParen = true;
    } else if (c == ')') {
      paren--;
      if (sawParen && paren == 0) {
        i++;
        break;
      }
    } else if (c == '{' && !sawParen) {
      break;
    }
  }
  final brace = src.indexOf('{', i);
  if (brace < 0) throw StateError('$sig 본문을 찾지 못함');
  var depth = 0;
  for (var j = brace; j < src.length; j++) {
    if (src[j] == '{') depth++;
    if (src[j] == '}') {
      depth--;
      if (depth == 0) return src.substring(brace, j + 1);
    }
  }
  throw StateError('$sig 본문이 닫히지 않음');
}

// ── 재현용 위젯 ──────────────────────────────────────────────────────────
//
// 실제 화면의 구조를 그대로 옮긴 최소 재현이다:
//   버튼 탭 → (가드) → await 확인 다이얼로그 → 확인 → mutation
//
// mutation은 세지기만 하는 가짜다. 여기서 확인하는 것은 서버가 아니라
// **클라이언트가 서버를 몇 번 부르려 했는가**다.
class _TapProbe extends StatefulWidget {
  final bool guarded;
  final void Function() onMutate;
  final String entityId;

  const _TapProbe({
    super.key,
    required this.guarded,
    required this.onMutate,
    this.entityId = 'app1',
  });

  @override
  State<_TapProbe> createState() => _TapProbeState();
}

class _TapProbeState extends State<_TapProbe> {
  bool _isProcessing = false;

  /// 테스트가 직접 부른다 — 아래 `_doubleFire` 주석 참조.
  Future<void> fire() => _handle();

  Future<void> _handle() {
    if (!widget.guarded) return _inner();
    return ActionGuard.runVoid(
      ActionGuard.keyOf('probe', [widget.entityId]),
      _inner,
    );
  }

  /// 고치기 전의 모양 그대로다 — 체크와 설정 사이에 await가 있다.
  Future<void> _inner() async {
    if (_isProcessing) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        content: const Text('정말요?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('확인'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _isProcessing = true);
    try {
      widget.onMutate();
    } finally {
      // 실제 화면도 finally에서 되돌린다 — 한 번 처리했다고 영구히 잠기지 않는다.
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ElevatedButton(
        onPressed: _handle,
        child: const Text('실행'),
      ),
    );
  }
}

/// [_TapProbe]는 반드시 Navigator **아래**에 있어야 한다.
///
/// 처음 이 테스트는 `_TapProbe`가 스스로 MaterialApp을 만들게 했고, 그래서
/// `showDialog(context: context)`가 받은 State.context는 MaterialApp보다
/// **위**였다 — Navigator를 찾지 못해 다이얼로그가 하나도 열리지 않았다.
/// 재현 테스트가 "0개"를 보고 통과해 버리면 아무것도 지키지 못한다.
Widget _host(Widget child) => MaterialApp(home: Scaffold(body: child));

/// 같은 프레임 안에서 onTap이 두 번 발화한 상황을 만든다.
///
/// ── 왜 `tester.tap()`을 두 번 부르지 않는가 ───────────────────────────────
///
/// 시도했고, 재현되지 않았다. `tester.tap()`을 연속 두 번 부르든, 프레임을
/// 넘기지 않고 PointerDown/Up 네 개를 binding에 직접 밀어 넣든, onPressed는
/// **한 번만** 발화했다(측정함: CALLS=1, DIALOGS=1). `flutter_test`의 이벤트
/// 처리가 두 pointer 시퀀스 사이에 프레임을 끼워 넣고, 그 프레임에서 올라온
/// ModalBarrier가 두 번째 탭을 받아 버린다.
///
/// 즉 **이 하네스는 실기기의 same-frame double tap을 만들 수 없다.** 그러니
/// 재현되지 않았다는 이유로 문제가 없다고 말하면 안 된다 — 문제는 실사용에서
/// 관찰됐고, 재현하지 못한 것은 도구다.
///
/// 그래서 한 단계 안쪽에서 재현한다. 같은 프레임의 두 탭이 하는 일은 정확히
/// "프레임 사이에 핸들러가 두 번 불린다"이고, 아래가 바로 그것이다. 가드가
/// 막아야 하는 지점도 정확히 거기다 — 핸들러 진입이다.
///
/// 대신 포기한 것이 있다: 이 테스트는 gesture/hit-test 층은 검증하지 않는다.
/// 그 층의 확인은 실기기 몫으로 남는다.
Future<void> _doubleFire(WidgetTester tester, GlobalKey<_TapProbeState> key) {
  final s = key.currentState!;
  // await 없이 연달아 부른다 — 사이에 프레임도 microtask drain도 없다.
  final a = s.fire();
  final b = s.fire();
  return Future.wait([a, b]);
}

void main() {
  setUp(ActionGuard.resetForTest);

  // ══════════════════════════════════════════════════════════════
  // 01. 재현 — 가드 없는 구조는 실제로 두 개를 띄운다
  // ══════════════════════════════════════════════════════════════
  group('01. rapid double-tap 재현', () {
    testWidgets('01-a 가드가 없으면 같은 다이얼로그가 2개 쌓이고 mutation도 2번 간다',
        (tester) async {
      var mutations = 0;
      final key = GlobalKey<_TapProbeState>();
      await tester.pumpWidget(_host(_TapProbe(
          key: key, guarded: false, onMutate: () => mutations++)));

      final done = _doubleFire(tester, key);
      await tester.pump();

      // 두 개가 쌓였다는 것이 이 CORRECTION의 출발점이다.
      expect(find.text('정말요?'), findsNWidgets(2),
          reason: '가드 없는 구조에서 모달이 2개 쌓이지 않으면 이 테스트의 전제가 무너진다');

      // 위 다이얼로그 확인 → mutation 1
      await tester.tap(find.text('확인').last);
      await tester.pumpAndSettle();
      // 아래 다이얼로그가 아직 남아 있다 — 여기서 또 누를 수 있다는 것이 문제다.
      expect(find.text('정말요?'), findsOneWidget);
      await tester.tap(find.text('확인'));
      await tester.pumpAndSettle();
      await done;

      expect(mutations, 2,
          reason: 'await 뒤 재확인이 없으면 두 번째 확인도 그대로 mutation에 닿는다');
    });

    testWidgets('01-b 가드를 걸면 모달은 1개, mutation은 1회', (tester) async {
      var mutations = 0;
      final key = GlobalKey<_TapProbeState>();
      await tester.pumpWidget(_host(_TapProbe(
          key: key, guarded: true, onMutate: () => mutations++)));

      final done = _doubleFire(tester, key);
      await tester.pump();

      expect(find.text('정말요?'), findsOneWidget);

      await tester.tap(find.text('확인'));
      await tester.pumpAndSettle();
      await done;

      expect(find.text('정말요?'), findsNothing);
      expect(mutations, 1);
    });

    testWidgets('01-c 첫 흐름이 끝나면 다시 열 수 있다 — 영구 잠금이 아니다',
        (tester) async {
      var mutations = 0;
      final key = GlobalKey<_TapProbeState>();
      await tester.pumpWidget(_host(_TapProbe(
          key: key, guarded: true, onMutate: () => mutations++)));

      final done = _doubleFire(tester, key);
      await tester.pump();
      await tester.tap(find.text('확인'));
      await tester.pumpAndSettle();
      await done;
      expect(mutations, 1);
      expect(ActionGuard.inFlightCount, 0, reason: 'key가 풀려야 한다');

      // 사용자가 다시 누른다 — 이번엔 진짜 탭으로.
      await tester.tap(find.text('실행'));
      await tester.pumpAndSettle();
      expect(find.text('정말요?'), findsOneWidget,
          reason: '두 번째 사용자 행동은 정상적으로 열려야 한다');
    });
  });

  // ══════════════════════════════════════════════════════════════
  // 02. ActionGuard 계약
  // ══════════════════════════════════════════════════════════════
  group('02. ActionGuard 계약', () {
    test('02-a busy 표시는 첫 await 이전에 동기로 선다', () {
      // run을 await하지 않고 곧바로 물어본다 — 같은 프레임의 두 번째 탭과 같은 상황.
      final f = ActionGuard.runVoid('k', () async {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      });
      expect(ActionGuard.isBusy('k'), true);
      return f.then((_) => expect(ActionGuard.isBusy('k'), false));
    });

    test('02-b 진행 중이면 body를 아예 실행하지 않는다', () async {
      var runs = 0;
      final a = ActionGuard.runVoid('k', () async {
        runs++;
        await Future<void>.delayed(const Duration(milliseconds: 10));
      });
      final b = ActionGuard.runVoid('k', () async {
        runs++;
      });
      await Future.wait([a, b]);
      expect(runs, 1);
    });

    test('02-c 다른 대상은 서로 막지 않는다', () async {
      var runs = 0;
      await Future.wait([
        ActionGuard.runVoid(ActionGuard.keyOf('invite', ['to1', 'slot9']),
            () async {
          runs++;
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }),
        ActionGuard.runVoid(ActionGuard.keyOf('invite', ['to1', 'slot10']),
            () async {
          runs++;
        }),
      ]);
      expect(runs, 2, reason: '전역 잠금이 아니다');
    });

    test('02-d 중첩 확인 흐름은 살아 있다 — 행동 이름이 다르면 통과한다', () async {
      var inner = 0;
      await ActionGuard.runVoid(ActionGuard.keyOf('offer', ['app7']), () async {
        await ActionGuard.runVoid(
            ActionGuard.keyOf('offer-confirm', ['app7']), () async {
          inner++;
        });
      });
      expect(inner, 1);
    });

    test('02-e body가 던져도 key는 풀린다', () async {
      await expectLater(
        ActionGuard.runVoid('k', () async => throw StateError('boom')),
        throwsStateError,
      );
      expect(ActionGuard.isBusy('k'), false);
      expect(ActionGuard.inFlightCount, 0);
    });

    test('02-f 빈 식별자가 서로 다른 대상을 같은 key로 만들지 않는다', () {
      // `['a', null]`과 `[null, 'a']`가 같은 문자열이 되면 안 된다.
      expect(ActionGuard.keyOf('x', ['a', null]),
          isNot(ActionGuard.keyOf('x', [null, 'a'])));
      expect(ActionGuard.keyOf('x', ['a', '']), ActionGuard.keyOf('x', ['a', null]));
    });

    test('02-g 중복 탭은 조용히 무시된다 — 토스트를 띄우지 않는다', () async {
      // 반환값으로 "이미 처리 중"을 구분할 수단을 만들지 않았다는 계약.
      // 사용자는 두 번 눌렀다고 생각하지 않고, 첫 탭의 결과를 이미 보고 있다.
      final held = ActionGuard.run<String>('k', () async {
        await Future<void>.delayed(const Duration(milliseconds: 10));
        return 'done';
      });
      final dup = await ActionGuard.run<String>('k', () async => 'second');
      expect(dup, isNull);
      expect(await held, 'done');
    });
  });

  // ══════════════════════════════════════════════════════════════
  // 03. 실제 호출부가 이 계약을 쓰는가
  // ══════════════════════════════════════════════════════════════
  group('03. R7-P1 CTA 적용', () {
    const cardPath = 'lib/widgets/admin/cards/admin_to_group_card.dart';
    const dayPath = 'lib/screens/business_admin/dialogs/day_applicants_dialog.dart';
    const workPath =
        'lib/screens/business_admin/dialogs/work_applicants_dialog.dart';

    test('03-a 공고 카드의 modal CTA가 single-flight로 감싸였다', () {
      final src = _codeOf(_src(cardPath));
      for (final sig in [
        'Future<void> _openApplicants(',
        'Future<void> _showInviteWorkerDialog(',
        'Future<void> _showSentInvitesSheet(',
      ]) {
        expect(src.contains(sig), true, reason: sig);
        final idx = src.indexOf(sig);
        // 진입점은 ActionGuard로 넘기고 본체는 `...Inner`가 갖는다.
        expect(src.substring(idx, idx + 400).contains('ActionGuard.'), true,
            reason: '$sig 가 가드를 거치지 않는다');
      }
      expect(src.contains('_openApplicantsInner('), true);
      expect(src.contains('_showInviteWorkerDialogInner('), true);
    });

    test('03-b 초대 시트는 모집 단위 단위로 잠근다 — 공고 전체가 아니다', () {
      for (final p in [dayPath, workPath]) {
        final src = _codeOf(_src(p));
        expect(src.contains("ActionGuard.keyOf('inviteMethod'"), true,
            reason: p);
        // key에 slotId가 들어가야 다른 날짜/업무가 서로 막히지 않는다.
        final idx = src.indexOf("ActionGuard.keyOf('inviteMethod'");
        expect(src.substring(idx, idx + 120).contains('slotId'), true,
            reason: '$p — key가 모집 단위를 구분하지 않는다');
      }
    });

    test('03-c mutation 경로는 await 뒤에 _isProcessing을 다시 본다', () {
      // 체크와 설정 사이에 await가 있으면 그 체크는 낡은 값이다.
      final cases = <String, List<String>>{
        dayPath: ['Future<void> _releaseNoshowSeatInner('],
        workPath: [
          'Future<void> _showAlternativeWorkOfferSheetInner(',
          'Future<void> _showConfirmedReassignmentSheetInner(',
        ],
      };
      cases.forEach((path, sigs) {
        final src = _src(path);
        for (final sig in sigs) {
          final body = _codeOf(_bodyOf(src, sig));
          final setIdx = body.indexOf('_isProcessing = true');
          expect(setIdx, greaterThan(-1), reason: sig);
          final before = body.substring(0, setIdx);
          // 설정 **직전**에 재확인이 있어야 한다.
          final lastCheck = before.lastIndexOf('if (_isProcessing) return');
          expect(lastCheck, greaterThan(-1), reason: '$sig 재확인 없음');
          expect(before.substring(lastCheck).contains('await '), false,
              reason: '$sig — 재확인과 설정 사이에 또 await가 있다');
        }
      });
    });

    test('03-d 중복 탭 방어를 시간(debounce)으로 하지 않았다', () {
      final guard = _codeOf(_src('lib/utils/action_guard.dart'));
      expect(guard.contains('Duration(milliseconds:'), false,
          reason: '모달이 떠 있는 동안 내내 닫혀 있어야 한다 — 고정 시간창이 아니다');
      expect(guard.contains('Timer('), false);
    });

    test('03-e 전역 잠금을 만들지 않았다', () {
      final guard = _codeOf(_src('lib/utils/action_guard.dart'));
      // 단일 bool 전역 플래그였다면 정상적인 중첩 확인 흐름까지 막혔을 것이다.
      expect(guard.contains('static bool _busy'), false);
      expect(guard.contains('Map<String,'), true);
    });
  });
}
