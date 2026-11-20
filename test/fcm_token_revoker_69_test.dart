// [.69 FCM-DEVICE-REVOKE] 기기 토큰 폐기 순서 — 로그아웃이 오프라인으로 끝나지 못해도 다음 계정에 같은 토큰이 붙지 않는가,
//   늦게 끝난 이전 폐기가 다음 계정의 새 토큰을 지우지 않는가(새 등록은 그 완료를 기다린다).
//   서버 쪽(배포 sender 가 고르는 토큰)은 c69/a69.js 가 에뮬레이터에서 따로 확인한다. 실제 FCM 은 실행하지 않는다.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:ALfit/services/fcm_token_revoker.dart';

class _Device {
  bool pending = false;
  int deletes = 0;
  final List<Completer<void>> calls = [];
  DeviceTokenRevoker revoker() => DeviceTokenRevoker(
        deleteToken: () {
          deletes++;
          final c = Completer<void>();
          calls.add(c);
          return c.future;
        },
        readPending: () async => pending,
        writePending: (v) async => pending = v,
      );
}

void main() {
  test('[F69-a] 온라인 로그아웃 — 폐기 완료, 표식 없음', () async {
    final d = _Device();
    final r = d.revoker();
    final f = r.revoke(timeout: const Duration(seconds: 1));
    await Future<void>.delayed(Duration.zero);
    d.calls.single.complete();
    expect(await f, isTrue);
    expect(d.pending, isFalse);
  });

  test('[F69-b] 오프라인 로그아웃 — 상한에서 돌아오고 표식이 남는다(로그아웃은 기다리지 않는다)', () async {
    final d = _Device();
    final r = d.revoker();
    expect(await r.revoke(timeout: const Duration(milliseconds: 30)), isFalse);
    expect(d.pending, isTrue);
    expect(r.isInFlight, isTrue, reason: '폐기는 계속 돈다(Future.timeout 은 원래 작업을 취소하지 않는다)');
  });

  test('[F69-c] 다음 로그인은 진행 중인 이전 폐기가 끝나야 등록한다 — 폐기는 한 번만, 늦은 폐기가 새 토큰을 지우지 않음', () async {
    final d = _Device();
    final r = d.revoker();
    await r.revoke(timeout: const Duration(milliseconds: 20)); // A 로그아웃 — 오프라인
    // B 로그인: 아직 끝나지 않았다 → 등록하지 않는다
    expect(await r.settle(timeout: const Duration(milliseconds: 20)), isFalse);
    expect(d.deletes, 1, reason: '두 번째 폐기를 새로 시작하지 않는다(새 토큰을 지울 수 있다)');
    // 네트워크 회복 — 이전 폐기가 끝난다. 그 다음에야 새 토큰을 받는다.
    final later = r.settle(timeout: const Duration(seconds: 1));
    d.calls.single.complete();
    expect(await later, isTrue);
    expect(d.pending, isFalse);
    expect(d.deletes, 1);
  });

  test('[F69-d] 앱이 꺼졌다 켜짐 — 표식만 남은 폐기를 다시 하고, 실패하면 표식 유지·등록 안 함', () async {
    final d = _Device()..pending = true;
    final r = DeviceTokenRevoker(
      deleteToken: () async => throw Exception('offline'),
      readPending: () async => d.pending,
      writePending: (v) async => d.pending = v,
    );
    expect(await r.settle(timeout: const Duration(seconds: 1)), isFalse);
    expect(d.pending, isTrue);
  });

  test('[F69-e] 남은 폐기가 없으면 바로 등록(폐기 호출 없음)', () async {
    final d = _Device();
    expect(await d.revoker().settle(timeout: const Duration(seconds: 1)), isTrue);
    expect(d.deletes, 0);
  });
}
