import 'package:flutter/material.dart';

/// 전역 Navigator Key — FCM 알림 이동, PortOne 본인인증 WebView 등에서 사용
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

/// 전역 ScaffoldMessenger Key — 어디서든 SnackBar 표시용
final GlobalKey<ScaffoldMessengerState> scaffoldMessengerKey =
    GlobalKey<ScaffoldMessengerState>();
