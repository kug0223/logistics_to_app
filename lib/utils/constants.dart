/// 앱 전역 상수 정의
class Constants {
  // 색상
  static const int primaryColor = 0xFF2563EB; // Blue
  static const int secondaryColor = 0xFF10B981; // Green
  static const int errorColor = 0xFFEF4444; // Red
  static const int warningColor = 0xFFF59E0B; // Orange

  // 물류센터 목록
  static const List<Map<String, String>> centers = [
    {
      'id': 'CENTER_A',
      'name': '송파 물류센터',
      'address': '서울시 송파구 올림픽로 300',
    },
    {
      'id': 'CENTER_B',
      'name': '강남 물류센터',
      'address': '서울시 강남구 테헤란로 500',
    },
    {
      'id': 'CENTER_C',
      'name': '서초 물류센터',
      'address': '서울시 서초구 강남대로 400',
    },
  ];

  // 지원 상태 코드
  static const String statusPending = 'PENDING'; // 대기
  static const String statusConfirmed = 'CONFIRMED'; // 확정
  static const String statusRejected = 'REJECTED'; // 거절
  static const String statusCanceled = 'CANCELED'; // 취소

  // 업무 유형
  static const List<String> workTypes = [
    '피킹',
    '패킹',
    '분류',
    '배송',
    '하역',
    '검수',
  ];

  // Firebase Collections
  static const String collectionUsers = 'users';
  static const String collectionTOs = 'tos';
  static const String collectionApplications = 'applications';

  // GPS 설정
  static const double gpsAccuracyThreshold = 100.0; // 미터
  static const Duration locationTimeout = Duration(seconds: 30);

  // 페이지네이션
  static const int pageSize = 20;

  // 에러 메시지
  static const String errorNetwork = '네트워크 연결을 확인해주세요.';
  static const String errorUnknown = '알 수 없는 오류가 발생했습니다.';
  static const String errorPermission = '권한이 없습니다.';
}

/// 앱 상수 (main.dart에서 사용하기 위한 별칭)
class AppConstants {
  static const int primaryColor = Constants.primaryColor;
}