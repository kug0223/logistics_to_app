import 'package:flutter/material.dart';
import 'dart:async';

/// 화면 이동 + 데이터 갱신 통합 헬퍼
/// 
/// 사용법:
/// ```dart
/// NavigationHelper.push(
///   context,
///   destination: SomeScreen(),
///   onReturn: (result) {
///     if (result == true) _loadData();
///   },
/// );
/// ```
class NavigationHelper {
  
  /// 기본 push + 결과 처리
  /// 
  /// [destination]: 이동할 화면
  /// [onReturn]: 돌아왔을 때 콜백 (result 전달)
  /// [onChanged]: result == true일 때만 호출되는 간편 콜백
  static Future<T?> push<T>(
    BuildContext context, {
    required Widget destination,
    FutureOr<void> Function(T? result)? onReturn,
    VoidCallback? onChanged,
  }) async {
    final result = await Navigator.push<T>(
      context,
      MaterialPageRoute(builder: (context) => destination),
    );
    
    // 콜백 처리
    if (onReturn != null) {
      onReturn(result);
    }
    
    // result == true일 때만 onChanged 호출
    if (onChanged != null && result == true) {
      onChanged();
    }
    
    return result;
  }

  /// pushReplacement + 결과 처리
  static Future<T?> pushReplacement<T, TO>(
    BuildContext context, {
    required Widget destination,
    TO? result,
  }) async {
    return Navigator.pushReplacement<T, TO>(
      context,
      MaterialPageRoute(builder: (context) => destination),
      result: result,
    );
  }

  /// pushAndRemoveUntil (로그인 화면 등)
  static Future<T?> pushAndRemoveAll<T>(
    BuildContext context, {
    required Widget destination,
  }) async {
    return Navigator.pushAndRemoveUntil<T>(
      context,
      MaterialPageRoute(builder: (context) => destination),
      (route) => false,
    );
  }

  /// pop with result
  /// 
  /// [changed]: 데이터 변경 여부 (true면 이전 화면에서 갱신)
  static void pop(BuildContext context, {bool changed = false}) {
    Navigator.pop(context, changed);
  }

  /// 변경 있음으로 pop (편의 메서드)
  static void popWithChange(BuildContext context) {
    Navigator.pop(context, true);
  }

  /// 변경 없음으로 pop (편의 메서드)  
  static void popWithoutChange(BuildContext context) {
    Navigator.pop(context, false);
  }
}