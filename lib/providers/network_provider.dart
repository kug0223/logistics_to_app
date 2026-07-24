import 'dart:async';
import 'package:flutter/material.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../utils/network_checker.dart';

class NetworkProvider extends ChangeNotifier {
  bool _isOnline = true;
  bool _disposed = false;
  StreamSubscription<List<ConnectivityResult>>? _subscription;
  final _connectivity = Connectivity(); // 동일 인스턴스 재사용

  bool get isOnline => _isOnline;

  NetworkProvider() {
    _init();
  }

  Future<void> _init() async {
    // 앱 시작 시 현재 상태 확인
    final results = await _connectivity.checkConnectivity();
    final initialOnline = _hasConnection(results);
    // 기본값(true)과 실제 상태가 다를 경우에만 갱신 + 알림
    // (오프라인으로 시작하면 NetworkBanner가 즉시 표시되어야 함)
    if (initialOnline != _isOnline) {
      _isOnline = initialOnline;
      NetworkChecker.instance.update(_isOnline);
      if (!_disposed) notifyListeners();
    } else {
      NetworkChecker.instance.update(_isOnline); // 서비스 레이어와 동기화
    }

    // 이후 변화 감지 — dispose 이후 구독 방지
    if (_disposed) return;
    _subscription = _connectivity.onConnectivityChanged.listen(
      (List<ConnectivityResult> results) {
        final online = _hasConnection(results);
        if (online != _isOnline) {
          _isOnline = online;
          NetworkChecker.instance.update(online);
          if (!_disposed) notifyListeners();
        }
      },
      onError: (e) => debugPrint('⚠️ Connectivity 스트림 에러: $e'),
    );
  }

  bool _hasConnection(List<ConnectivityResult> results) {
    return results.any((r) =>
        r == ConnectivityResult.mobile ||
        r == ConnectivityResult.wifi ||
        r == ConnectivityResult.ethernet);
  }

  @override
  void dispose() {
    _disposed = true;
    _subscription?.cancel();
    super.dispose();
  }
}
