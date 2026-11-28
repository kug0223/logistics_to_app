import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

/// 기기 무결성 검증 서비스
/// - 기기 시간 변조 감지 (서버 시각과 비교)
class DeviceIntegrityService {
  static const _maxAllowedDiffMs = 5 * 60 * 1000; // 5분

  final _fn = FirebaseFunctions.instanceFor(region: 'asia-northeast3');

  /// [PERF-L38 · 판정291 B1] [isDeviceTimeValid] 와 같은 허용차(5분) 판정 — 서버 시각 표본을 다시 쓸 때 쓴다.
  static bool withinAllowedDiff(int serverMs, int deviceMs) =>
      (serverMs - deviceMs).abs() <= _maxAllowedDiffMs;

  /// [PERF-L38 · 판정291 B1] 서버 시각 **표본**만 받는다(판정은 하지 않는다).
  ///   확인하지 못하면(네트워크·형식 오류) null — 호출자는 이것을 '정상' 근거로 쓰지 않는다.
  ///   [isDeviceTimeValid] 의 '확인 불가 = 허용' 정책은 그 함수 안에만 있다(여기서 넓히지 않는다).
  Future<int?> fetchServerTimeMs() async {
    try {
      final result = await _fn
          .httpsCallable('getServerTime', options: HttpsCallableOptions(timeout: const Duration(seconds: 10)))
          .call({});
      final rawMs = result.data['serverTimeMs'];
      if (rawMs == null || rawMs is! num) return null;
      return rawMs.toInt();
    } catch (e) {
      debugPrint('⚠️ 서버 시각 표본 실패: $e');
      return null;
    }
  }

  /// 기기 시각과 서버 시각을 비교하여 변조 여부 반환
  ///
  /// 반환값:
  ///   `true`  — 시각 정상 (차이 5분 이내)
  ///   `false` — 변조 의심 또는 확인 불가
  Future<bool> isDeviceTimeValid() async {
    try {
      final result = await _fn
          .httpsCallable('getServerTime', options: HttpsCallableOptions(timeout: const Duration(seconds: 10)))
          .call({});
      final rawMs = result.data['serverTimeMs'];
      if (rawMs == null || rawMs is! num) {
        debugPrint('⚠️ 서버 응답 형식 오류: serverTimeMs=$rawMs');
        return false;
      }
      final serverMs = rawMs.toInt();
      final deviceMs = DateTime.now().millisecondsSinceEpoch;
      final diffMs = (serverMs - deviceMs).abs();

      debugPrint('🕐 기기-서버 시각 차이: ${diffMs ~/ 1000}초');

      if (diffMs > _maxAllowedDiffMs) {
        debugPrint('⚠️ 기기 시간 변조 의심: 차이 ${diffMs ~/ 60000}분');
        return false;
      }
      return true;
    } catch (e) {
      // 네트워크 오류 등 확인 불가 시 — 차단하지 않고 허용
      debugPrint('⚠️ 서버 시각 확인 실패 (네트워크): $e');
      return true;
    }
  }
}
