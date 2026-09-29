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
  // [R7-P4.3A] 이 두 값은 **주소 검색이 채우지 않는다.**
  //   다음 우편번호 API 는 좌표를 주지 않는다 — 별도 geocoding 이 필요하고,
  //   그것은 이제 호출부(사업장 등록 폼)가 자기 화면에서 상태를 보여 주며
  //   한다. 여기서 기다렸다 닫으면 실패를 말할 자리가 없다.
  //   항상 null 이지만 필드는 남긴다 — 수기 입력 경로가 이 모양을 쓴다.
  final double? latitude;
  final double? longitude;
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
///   // 좌표가 필요하면 GeocodingService.resolveAddress 를 따로 부른다.
/// }
/// ```
class DaumAddressService {
  /// 주소 검색 다이얼로그 표시
  ///
  /// - StyledDialog 기반 통일된 디자인
  /// - **좌표는 주지 않는다** — [GeocodingService.resolveAddress] 를 쓴다
  /// - 반응형 레이아웃 지원
  static Future<AddressResult?> searchAddress(BuildContext context) async {
    return DaumAddressSearchImpl.searchAddress(context);
  }
}