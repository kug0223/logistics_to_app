// lib/config/kakao_config.dart
//
// [ALFIT-AUTH-KAKAO-ONBOARDING.1] 카카오 Android **네이티브 앱 키** — 앱 실행 파일에 들어가는 공개 성격의 값이다
//   (REST/JavaScript/Admin 키 아님 · 비밀값 아님). 대표 제공 2026-11-25.
//
//   같은 값이 두 곳에만 있다:
//     1) 여기(Dart SDK 초기화 — KakaoAuthService.install)
//     2) android/app/src/main/res/values/kakao_config.xml 의 kakao_scheme("kakao" + 키 · 리다이렉트 수신)
//   바꿀 때는 두 곳을 함께 바꾼다(시험 AKA-S4 가 일치 여부만 확인한다 — 값은 출력하지 않는다).
//   빌드 때 dart-define KAKAO_NATIVE_APP_KEY 를 주면 그 값이 우선한다.

const String kKakaoNativeAppKey = '80bb150bba02cd243ead3c8d4a04b18a';
