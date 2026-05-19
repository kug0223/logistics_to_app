import 'package:flutter/material.dart';
import 'toast_helper.dart';

/// 로딩 상태 + try/catch/finally 보일러플레이트를 제거하는 mixin.
///
/// 사용법:
/// ```dart
/// class _MyState extends State<My> with LoadingStateMixin {
///   @override
///   void initState() {
///     super.initState();
///     _load();
///   }
///
///   Future<void> _load() => runWithLoading(() async {
///     final data = await _service.getData();
///     if (mounted) setState(() => _data = data);
///   }, errorTag: '_load');
/// }
/// ```
/// build 에서는 `_isLoading` 대신 `isLoading`을 사용합니다.
mixin LoadingStateMixin<T extends StatefulWidget> on State<T> {
  bool isLoading = true;

  void setLoading(bool val) {
    if (mounted) setState(() => isLoading = val);
  }

  /// [work]를 실행하는 동안 [isLoading]을 true로 유지합니다.
  /// 예외 발생 시 [errorTag] 로그를 남기고, [errorMessage]가 있으면 토스트를 표시합니다.
  Future<void> runWithLoading(
    Future<void> Function() work, {
    String? errorTag,
    String? errorMessage,
  }) async {
    setLoading(true);
    try {
      await work();
    } catch (e) {
      debugPrint('❌ ${errorTag ?? runtimeType}: $e');
      if (errorMessage != null && mounted) {
        ToastHelper.showError(errorMessage);
      }
    } finally {
      setLoading(false);
    }
  }
}
