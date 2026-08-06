import 'package:flutter/material.dart';

/// 전역 Navigator Key — FCM 알림 이동, PortOne 본인인증 WebView 등에서 사용
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

/// 전역 ScaffoldMessenger Key — 어디서든 SnackBar 표시용
final GlobalKey<ScaffoldMessengerState> scaffoldMessengerKey =
    GlobalKey<ScaffoldMessengerState>();

// 로그아웃 후 로그인 화면으로 이동하는 콜백 — main.dart에서 등록
// goHome()이 AuthWrapper를 스택에서 제거한 경우에도 안전하게 동작하도록
// AuthWrapper를 새로 push하는 방식 사용 (popUntil 대신)
VoidCallback? _loginRedirectCallback;

/// main.dart에서 호출 — AuthWrapper를 push하는 로직을 주입
void setLoginRedirectCallback(VoidCallback callback) {
  _loginRedirectCallback = callback;
}

/// signOut() 완료 후 호출 — 스택 상태와 무관하게 로그인 화면으로 이동
void redirectToLogin() {
  _loginRedirectCallback?.call();
}
