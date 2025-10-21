import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import '../utils/toast_helper.dart';

class LocationService {
  // 위치 권한 요청
  Future<bool> requestLocationPermission() async {
    try {
      PermissionStatus status = await Permission.location.request();
      
      if (status.isGranted) {
        return true;
      } else if (status.isDenied) {
        ToastHelper.showError('위치 권한이 거부되었습니다.');
        return false;
      } else if (status.isPermanentlyDenied) {
        ToastHelper.showError('설정에서 위치 권한을 허용해주세요.');
        await openAppSettings();
        return false;
      }
      return false;
    } catch (e) {
      print('위치 권한 요청 실패: $e');
      return false;
    }
  }

  // 현재 위치 가져오기
  Future<Position?> getCurrentLocation() async {
    try {
      bool hasPermission = await requestLocationPermission();
      if (!hasPermission) return null;

      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        ToastHelper.showError('위치 서비스가 비활성화되어 있습니다.');
        return null;
      }

      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      return position;
    } catch (e) {
      print('위치 가져오기 실패: $e');
      ToastHelper.showError('위치를 가져올 수 없습니다.');
      return null;
    }
  }

  // 두 좌표 간 거리 계산 (미터 단위)
  double calculateDistance(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    return Geolocator.distanceBetween(lat1, lon1, lat2, lon2);
  }

  // 특정 위치 범위 내에 있는지 확인
  Future<bool> isWithinRange({
    required double targetLat,
    required double targetLon,
    required double rangeInMeters,
  }) async {
    Position? currentPosition = await getCurrentLocation();
    if (currentPosition == null) return false;

    double distance = calculateDistance(
      currentPosition.latitude,
      currentPosition.longitude,
      targetLat,
      targetLon,
    );

    return distance <= rangeInMeters;
  }
}