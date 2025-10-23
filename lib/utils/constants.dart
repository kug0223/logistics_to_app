/// 앱 전역 상수 정의
class Constants {
  // 색상
  static const int primaryColor = 0xFF2563EB; // Blue
  static const int secondaryColor = 0xFF10B981; // Green
  static const int errorColor = 0xFFEF4444; // Red
  static const int warningColor = 0xFFF59E0B; // Orange

  // ❌ 물류센터 목록 (deprecated) - 삭제!
  // static const List<Map<String, String>> centers = [ ... ];

  // 지원 상태 코드
  static const String statusPending = 'PENDING';
  static const String statusConfirmed = 'CONFIRMED';
  static const String statusRejected = 'REJECTED';
  static const String statusCanceled = 'CANCELED';

  // ✅ 업무 유형 (아이콘 포함)
  static const List<Map<String, String>> workTypes = [
    {'name': '피킹', 'icon': '📦'},
    {'name': '패킹', 'icon': '📦'},
    {'name': '배송', 'icon': '🚚'},
    {'name': '분류', 'icon': '🏷️'},
    {'name': '하역', 'icon': '🏋️'},
    {'name': '검수', 'icon': '✅'},
  ];

  // ✅ 업무 유형 이름만 (기존 코드 호환용)
  static final List<String> workTypeNames = workTypes
      .map((type) => type['name']!)
      .toList();

  // 업종 카테고리
  static const Map<String, List<String>> jobCategories = {
    '회사': [
      '일반 회사',
      '제조, 생산, 건설',
      '물류센터'
    ],
    '매장': [
      '카페 (카페, 음료, 베이커리)',
      '외식업 (음식, 외식업)',
      '판매-서비스 (편의점, 유통, 호텔 등)',
      '매장관리 (PC방, 스터디카페 등)',
    ],
    '기타': [
      '교육, 의료, 기관',
      '기타',
    ],
  };

  static const List<String> categoryList = ['회사', '알바 매장', '기타'];

  // Firebase Collections
  static const String collectionUsers = 'users';
  static const String collectionTOs = 'tos';
  static const String collectionApplications = 'applications';
  // ❌ collectionCenters 삭제
  static const String collectionBusinesses = 'businesses';

  // GPS 설정
  static const double gpsAccuracyThreshold = 100.0;
  static const Duration locationTimeout = Duration(seconds: 30);

  // 페이지네이션
  static const int pageSize = 20;

  // 에러 메시지
  static const String errorNetwork = '네트워크 연결을 확인해주세요.';
  static const String errorUnknown = '알 수 없는 오류가 발생했습니다.';
  static const String errorPermission = '권한이 없습니다.';
}

/// 앱 상수 (간편 접근용)
class AppConstants {
  static const int primaryColor = Constants.primaryColor;
  
  // ❌ centers 삭제!
  // static const List<Map<String, String>> centers = Constants.centers;
  
  // ✅ 업무 유형
  static const List<Map<String, String>> workTypes = Constants.workTypes;
  static final List<String> workTypeNames = Constants.workTypeNames;
  
  // ✅ 업종 카테고리
  static const Map<String, List<String>> jobCategories = Constants.jobCategories;
  static const List<String> categoryList = Constants.categoryList;
}