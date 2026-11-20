import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

/// [E1-CANARY] 초대 발송 **성공 응답을 받은 직후** 한 번만 응답 유실을 흉내 낸다.
///
///   목적: DEV 카나리아에서 "서버는 저장했는데 앱은 응답을 확인하지 못했다"를
///   만들어, 앱의 저장 확인·재발송 차단·상위 갱신을 실제 원장과 대조한다.
///
///   이것은 **실제 네트워크 응답 유실이 아니다.** 서버 호출은 정상 완료되고,
///   앱이 그 결과를 버리고 시간 초과 오류를 받은 것처럼 행동할 뿐이다.
///
///   켜지는 조건 — 셋 다 참일 때만:
///     1) 디버그 빌드(`kDebugMode`). 릴리스·프로필 빌드에서는 상수 false 라
///        이 분기가 컴파일 단계에서 제거된다.
///     2) 빌드 시 `--dart-define=E1_DROP_INVITE_RESPONSE=true`. 기본값 false.
///        `config/dev/dart_defines.json` 등 저장소의 빌드 설정에는 이 키가 없다.
///     3) 이 프로세스에서 아직 한 번도 주입하지 않았다(첫 성공 1회만).
///
///   운영 빌드에서 켜질 수 없도록 런타임 설정(Remote Config 등)으로 열지 않는다.
class E1DebugFault {
  E1DebugFault._();

  /// 빌드 시 정의 — 컴파일 상수.
  static const bool defined = bool.fromEnvironment('E1_DROP_INVITE_RESPONSE');

  static bool _consumed = false;

  /// 테스트 전용 — 정의 대신 강제로 켠다(디버그 빌드 조건은 그대로 본다).
  @visibleForTesting
  static bool debugForce = false;

  @visibleForTesting
  static void debugReset() {
    _consumed = false;
    debugForce = false;
  }

  /// 이 프로세스에서 주입이 이미 일어났는가.
  static bool get consumed => _consumed;

  /// 지금 켜져 있는가.
  static bool get armed => kDebugMode && (defined || debugForce) && !_consumed;

  /// 초대 callable 이 **성공한 뒤** 부른다. 켜져 있으면 한 번만 던진다.
  static void afterInviteCommitted() {
    if (!armed) return;
    _consumed = true;
    debugPrint('[E1-FAULT] 초대 성공 응답을 버리고 deadline-exceeded 를 주입했다(1회)');
    throw FirebaseFunctionsException(
      code: 'deadline-exceeded',
      message: '[E1-FAULT] 디버그 응답 유실 주입',
    );
  }
}
