// [PERF-L12 · 같은 뿌리 = L30 PZ-2] 완료된 static Future 를 다른 zone(FakeAsync 시험 등)에서 기다리면 멈춘다.
//   완료된 `_Future` 에 붙는 리스너는 **그 Future 가 만들어진 zone** 의 microtask 로 돈다 — 다른 zone 이 그
//   microtask 를 돌리지 않으면(FakeAsync) await 가 영영 안 끝난다. `AppCheckReady` 는 완료 결과를 값(bool)으로
//   보관하고, 진행 중 future 만 들고 있다가 완료 시 비운다 → 완료 뒤 호출은 호출자 zone 의 새 Future.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:ALfit/services/app_check_ready.dart';

void main() {
  var calls = 0;

  test('ACZ-1 첫 zone(실제 이벤트 루프)에서 토큰 받기 완료', () async {
    AppCheckReady.debugReset();
    await AppCheckReady.start(() {
      calls++;
      return Future<Object?>.value('t');
    });
    expect(AppCheckReady.settled, isTrue);
  });

  testWidgets('ACZ-2 다음 시험(다른 FakeAsync zone)에서 다시 start · wait 해도 멈추지 않고 토큰 요청은 여전히 1번', (t) async {
    await AppCheckReady.start(() {
      calls++;
      return Future<Object?>.value('t2');
    });
    await AppCheckReady.wait();
    expect(calls, 1, reason: '"Too many attempts" 방어 — 완료 뒤 start 는 다시 요청하지 않는다');
    expect(AppCheckReady.settled, isTrue);
  }, timeout: const Timeout(Duration(seconds: 20)));

  test('ACZ-3 진행 중에는 같은 future 에 합류 · 완료 시 비움(진행 중 future 를 영구 보관하지 않음)', () async {
    AppCheckReady.debugReset();
    final token = Completer<Object?>();
    var n = 0;
    final a = AppCheckReady.start(() {
      n++;
      return token.future;
    });
    final b = AppCheckReady.start(() {
      n++;
      return token.future;
    });
    expect(identical(a, b), isTrue);
    expect(n, 1);
    token.complete('t');
    await a;
    final c = AppCheckReady.start(() {
      n++;
      return token.future;
    });
    expect(identical(a, c), isFalse, reason: '완료된 future 를 다시 돌려주면 다른 zone 에서 멈춘다');
    await c;
    expect(n, 1);
    AppCheckReady.debugReset();
  });
}
