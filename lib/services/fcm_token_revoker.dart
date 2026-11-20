// [.69 FCM-DEVICE-REVOKE] 이 기기의 FCM 토큰 폐기 — 계정 경계.
//
//   FCM 토큰은 계정이 아니라 기기(앱 설치)의 것이다. 로그아웃 때 이전 계정 문서에서 토큰을 지우는 쓰기가
//   오프라인으로 끝나지 못하면, 그 쓰기는 이전 계정의 대기열에 묶여 로그아웃 뒤에는 나가지 않는다(기기 확인 .69).
//   그 뒤 같은 기기로 다른 계정이 로그인하면 같은 토큰이 두 계정 문서에 남고, 서버는 이전 계정 알림을
//   이 기기로 보낸다(배포 sender 선택 확인 .69). 알림 블록이 있는 메시지는 OS 가 바로 띄운다.
//
//   그래서 로그아웃 때 기기 토큰 자체를 폐기한다(deleteToken). 폐기된 토큰은 FCM 이 거절하고, 배포 sender 의
//   기존 만료 토큰 정리가 이전 계정 문서에서 지운다. 상한 안에 끝내지 못하면 '폐기 대기' 표식을 남기고,
//   다음 로그인은 폐기를 끝낸 뒤에만 새 토큰을 등록한다 — 같은 토큰이 다음 계정에 붙지 않는다.
//   대기 중인 폐기는 하나만 돈다(늦게 끝난 이전 폐기가 다음 계정의 새 토큰을 지우지 않게, 새 등록은 그 완료를 기다린다).
library;

class DeviceTokenRevoker {
  DeviceTokenRevoker({
    required this.deleteToken,
    required this.readPending,
    required this.writePending,
  });

  /// 기기 토큰 폐기(FirebaseMessaging.deleteToken).
  final Future<void> Function() deleteToken;

  /// '폐기 대기' 표식(SharedPreferences) — 앱이 꺼져도 남는다.
  final Future<bool> Function() readPending;
  final Future<void> Function(bool) writePending;

  Future<void>? _inFlight;

  /// 지금 폐기가 진행 중인가(시험·진단용).
  bool get isInFlight => _inFlight != null;

  Future<void> _run() {
    return _inFlight ??= () async {
      try {
        await deleteToken();
        await writePending(false);
      } finally {
        _inFlight = null;
      }
    }();
  }

  /// 로그아웃 — 표식을 먼저 남기고 폐기한다. [timeout] 안에 끝났으면 true.
  /// 끝나지 않아도 폐기는 계속 돌고, 표식은 남아 다음 로그인·앱 시작이 이어 받는다.
  Future<bool> revoke({required Duration timeout}) async {
    await writePending(true);
    try {
      await _run().timeout(timeout);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 새 토큰을 등록해도 되는가 — 진행 중이거나 남은 폐기를 먼저 끝낸다. 끝내지 못하면 false(등록하지 않는다).
  Future<bool> settle({required Duration timeout}) async {
    if (_inFlight == null && !await readPending()) return true;
    try {
      await _run().timeout(timeout);
      return true;
    } catch (_) {
      return false;
    }
  }
}
