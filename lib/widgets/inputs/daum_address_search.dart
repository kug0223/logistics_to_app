// ============================================
// daum_address_search.dart (메인 파일)
// ============================================
import 'package:flutter/material.dart';
import 'daum_address_search_mobile.dart';

/// 다음 주소 검색 결과
class AddressResult {
  final String fullAddress;
  final String roadAddress;
  final String jibunAddress;
  final String zonecode;
  final double? latitude;
  final double? longitude;

  AddressResult({
    required this.fullAddress,
    required this.roadAddress,
    required this.jibunAddress,
    required this.zonecode,
    this.latitude,
    this.longitude,
  });
}

/// 다음 주소 검색 서비스 (모바일 전용)
class DaumAddressService {
  static Future<AddressResult?> searchAddress(BuildContext context) async {
    // 모바일 구현체 직접 호출
    return DaumAddressSearchImpl.searchAddress(context);
  }
}