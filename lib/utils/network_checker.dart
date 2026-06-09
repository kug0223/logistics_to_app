import 'package:connectivity_plus/connectivity_plus.dart';

/// 서비스 레이어에서 네트워크 상태 확인용 싱글톤
///
/// NetworkProvider가 Flutter Widget 트리에 속해 서비스에서 직접 사용 불가.
/// NetworkProvider._init에서 상태 변경 시 이 클래스도 동기화한다.
class NetworkChecker {
  NetworkChecker._();
  static final NetworkChecker instance = NetworkChecker._();

  bool _isOnline = true;

  bool get isOnline => _isOnline;

  /// NetworkProvider에서 상태 변경 시 호출
  void update(bool isOnline) => _isOnline = isOnline;

  /// Firebase 작업 전 네트워크 체크 — 오프라인이면 예외 발생
  void assertOnline([String? message]) {
    if (!_isOnline) {
      throw NetworkOfflineException(
        message ?? '인터넷 연결을 확인해주세요.',
      );
    }
  }

  /// 실시간 검사 (connectivity_plus 직접 호출)
  static Future<bool> checkNow() async {
    final results = await Connectivity().checkConnectivity();
    return results.any((r) =>
        r == ConnectivityResult.mobile ||
        r == ConnectivityResult.wifi ||
        r == ConnectivityResult.ethernet);
  }
}

class NetworkOfflineException implements Exception {
  final String message;
  const NetworkOfflineException(this.message);
  @override
  String toString() => message;
}
