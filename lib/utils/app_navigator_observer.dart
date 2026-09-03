// lib/utils/app_navigator_observer.dart
//
// Root navigator top route observer — FCM dedupe 전용
//
// [역할]
//   MaterialApp root Navigator의 현재 top route를 추적한다.
//   tab nested Navigator는 추적하지 않음 (MaterialApp navigatorObservers 등록 시
//   root navigator 이벤트만 수신됨).
//
// [사용처]
//   FCMService._pushFcmScreen():
//     실제 root top route name == 'fcm:$destinationKey' 일 때만 push skip.
//
// [주의]
//   static instance 방식이므로 앱 수명 전체에서 단 하나만 존재.
//   MaterialApp.navigatorObservers에 instance를 직접 전달해야 한다.

import 'package:flutter/material.dart';

/// Root Navigator top route tracker (singleton)
class AppNavigatorObserver extends NavigatorObserver {
  static final AppNavigatorObserver instance = AppNavigatorObserver._();
  AppNavigatorObserver._();

  Route<dynamic>? _currentRoute;

  /// 현재 root navigator top route (null = stack 비어 있음)
  Route<dynamic>? get currentRoute => _currentRoute;

  /// 현재 root navigator top route의 settings.name
  /// FCM route: 'fcm:[destinationKey]' 형식
  /// 일반 route: null (anonymous MaterialPageRoute)
  String? get currentRouteName => _currentRoute?.settings.name;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _currentRoute = route;
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _currentRoute = previousRoute;
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    if (_currentRoute == oldRoute) {
      _currentRoute = newRoute;
    }
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (_currentRoute == route) {
      _currentRoute = previousRoute;
    }
  }
}
