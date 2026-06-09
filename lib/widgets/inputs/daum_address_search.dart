// ============================================
// daum_address_search.dart (메인 진입점)
// ✨ 다음 주소 검색 API 연동 (모바일 전용)
// ============================================
import 'package:flutter/material.dart';
import 'daum_address_search_mobile.dart';

/// 다음 주소 검색 결과
class AddressResult {
  final String fullAddress;     // 전체 주소
  final String roadAddress;     // 도로명 주소
  final String jibunAddress;    // 지번 주소
  final String zonecode;        // 우편번호
  final double? latitude;       // GPS 위도 (Geocoding)
  final double? longitude;      // GPS 경도 (Geocoding)
  final String? sigungu;        // 시/군/구 (예: 강남구, 수원시)
  final String? bname;          // 법정읍면동 (예: 역삼동, 세교동)

  AddressResult({
    required this.fullAddress,
    required this.roadAddress,
    required this.jibunAddress,
    required this.zonecode,
    this.latitude,
    this.longitude,
    this.sigungu,
    this.bname,
  });
}

/// 다음 주소 검색 서비스 (모바일 전용)
/// 
/// 사용 예시:
/// ```dart
/// final result = await DaumAddressService.searchAddress(context);
/// if (result != null) {
///   debugPrint('주소: ${result.fullAddress}');
///   debugPrint('위도: ${result.latitude}, 경도: ${result.longitude}');
/// }
/// ```
class DaumAddressService {
  /// 주소 검색 다이얼로그 표시
  /// 
  /// - StyledDialog 기반 통일된 디자인
  /// - 자동 GPS 좌표 획득 (Geocoding)
  /// - 반응형 레이아웃 지원
  static Future<AddressResult?> searchAddress(BuildContext context) async {
    return DaumAddressSearchImpl.searchAddress(context);
  }
}