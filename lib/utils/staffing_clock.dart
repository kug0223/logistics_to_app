import 'package:flutter/foundation.dart';

/// [E1-FIXTURE-CLOCK] 관리자 인력 화면(공고 카드·업무 상세·업무별 지원자 창)이 "지금"을 읽는 한 곳.
///
///   이 화면들의 마감·정원·관계 판정은 모두 현재 시각을 본다. 에뮬레이터에서 캡처한 고정 근무일
///   픽스처는 그 날이 지나면 같은 화면을 "마감"으로 그려 초대 입구가 사라진다 — 제품이 아니라
///   테스트를 돌린 날짜가 바뀐 것이다. 테스트가 캡처 시각을 고정할 수 있게 이 한 곳만 연다.
///
///   production 은 [debugOverride] 가 null 이라 `DateTime.now()` 그대로다.
abstract final class StaffingClock {
  @visibleForTesting
  static DateTime Function()? debugOverride;

  static DateTime now() => debugOverride?.call() ?? DateTime.now();
}
