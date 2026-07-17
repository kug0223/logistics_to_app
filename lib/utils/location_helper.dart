import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:math' show cos, sqrt, asin;

/// GPS 위치 및 권한 관리 헬퍼

/// GPS 권한/서비스 상태 — 호출부에서 상황별 메시지 분기에 사용
enum LocationCheckResult {
  ok,
  serviceDisabled,  // 시스템 GPS(위치 서비스) Off
  permissionDenied, // 앱 권한 거부
  permissionDeniedForever, // 영구 거부
  error,
}

class LocationHelper {
  /// GPS 권한 확인 및 요청 (결과 상세 반환)
  static Future<LocationCheckResult> checkAndRequestPermissionDetailed() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return LocationCheckResult.serviceDisabled;

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          return LocationCheckResult.permissionDenied;
        }
      }
      if (permission == LocationPermission.deniedForever) {
        return LocationCheckResult.permissionDeniedForever;
      }
      return LocationCheckResult.ok;
    } catch (_) {
      return LocationCheckResult.error;
    }
  }

  /// GPS 권한 확인 및 요청 (하위 호환 — bool 반환)
  static Future<bool> checkAndRequestPermission() async {
    try {
      // 1. 위치 서비스 활성화 확인
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (kDebugMode) debugPrint('⚠️ 위치 서비스가 비활성화되어 있습니다.');
        return false;
      }

      // 2. 권한 상태 확인
      LocationPermission permission = await Geolocator.checkPermission();

      // 3. 권한이 거부된 경우 요청
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          if (kDebugMode) debugPrint('❌ 위치 권한이 거부되었습니다.');
          return false;
        }
      }

      // 4. 영구 거부된 경우 — 앱 설정으로 유도
      if (permission == LocationPermission.deniedForever) {
        if (kDebugMode) debugPrint('❌ 위치 권한이 영구적으로 거부되었습니다. 앱 설정에서 허용 필요.');
        return false; // 호출부에서 openAppSettings() 제공 필요
      }

      if (kDebugMode) debugPrint('✅ 위치 권한 확인 완료');
      return true;
    } catch (e) {
      if (kDebugMode) debugPrint('❌ 위치 권한 확인 실패: $e');
      return false;
    }
  }

  /// 현재 위치 가져오기
  static Future<Position?> getCurrentPosition() async {
    try {
      // 권한 확인
      final hasPermission = await checkAndRequestPermission();
      if (!hasPermission) {
        return null;
      }

      // 현재 위치 가져오기
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );

      // 가짜 GPS 앱(Mock Location) 감지 — 위치 스푸핑 차단
      if (position.isMocked) {
        if (kDebugMode) debugPrint('⚠️ Mock GPS 감지됨 — 위치 위조 시도');
        return null;
      }
      if (kDebugMode) debugPrint('✅ 현재 위치: ${position.latitude}, ${position.longitude}');
      return position;
    } catch (e) {
      if (kDebugMode) debugPrint('❌ 위치 가져오기 실패: $e');
      return null;
    }
  }

  /// 두 지점 간 거리 계산 (미터)
  static double calculateDistance({
    required double lat1,
    required double lon1,
    required double lat2,
    required double lon2,
  }) {
    const p = 0.017453292519943295; // Math.PI / 180
    final a = 0.5 -
        cos((lat2 - lat1) * p) / 2 +
        cos(lat1 * p) * cos(lat2 * p) * (1 - cos((lon2 - lon1) * p)) / 2;

    final distance = 12742000 * asin(sqrt(a)); // 2 * R; R = 6371 km
    return distance; // 미터 단위
  }

  /// 사업장 반경 내에 있는지 확인
  static bool isWithinRadius({
    required double currentLat,
    required double currentLon,
    required double businessLat,
    required double businessLon,
    double radiusInMeters = 100.0,
  }) {
    final distance = calculateDistance(
      lat1: currentLat,
      lon1: currentLon,
      lat2: businessLat,
      lon2: businessLon,
    );

    if (kDebugMode) debugPrint('📍 사업장과의 거리: ${distance.toStringAsFixed(1)}m (기준: ${radiusInMeters}m)');
    return distance <= radiusInMeters;
  }

  /// 앱 설정 열기
  static Future<void> openAppSettings() async {
    await Geolocator.openAppSettings();
  }

  /// 위치 설정 열기
  static Future<void> openLocationSettings() async {
    await Geolocator.openLocationSettings();
  }

  /// 거리를 읽기 쉬운 형태로 변환
  static String formatDistance(double meters) {
    if (meters < 1000) {
      return '${meters.toStringAsFixed(0)}m';
    } else {
      return '${(meters / 1000).toStringAsFixed(1)}km';
    }
  }

  /// 위치 정확도 체크
  static Future<bool> isAccuracyGood() async {
    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );

      // Mock GPS 앱(위치 스푸핑) 차단 — getCurrentPosition과 동일 방어 적용
      if (position.isMocked) {
        if (kDebugMode) debugPrint('⚠️ isAccuracyGood: Mock GPS 감지됨');
        return false;
      }

      // 정확도가 50m 이하면 양호
      final isGood = position.accuracy <= 50;
      if (kDebugMode) debugPrint('📍 위치 정확도: ${position.accuracy.toStringAsFixed(1)}m ${isGood ? "✅" : "⚠️"}');

      return isGood;
    } catch (e) {
      if (kDebugMode) debugPrint('❌ 정확도 체크 실패: $e');
      return false;
    }
  }

  /// 권한 상태 메시지
  static String getPermissionMessage(LocationPermission permission) {
    switch (permission) {
      case LocationPermission.denied:
        return '위치 권한이 거부되었습니다.\n출퇴근 체크를 위해 위치 권한이 필요합니다.';
      case LocationPermission.deniedForever:
        return '위치 권한이 영구적으로 거부되었습니다.\n설정에서 권한을 허용해주세요.';
      case LocationPermission.whileInUse:
      case LocationPermission.always:
        return '위치 권한이 허용되었습니다.';
      default:
        return '위치 권한 상태를 확인할 수 없습니다.';
    }
  }

  /// 실시간 위치 스트림 (선택적)
  static Stream<Position> getPositionStream() {
    return Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10, // 10m 이동 시 업데이트
      ),
    );
  }
}
