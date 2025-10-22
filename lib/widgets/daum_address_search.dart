// ============================================
// daum_address_search.dart (메인 파일)
// ============================================
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

// ✅ 플랫폼별 조건부 import
import 'daum_address_search_web.dart' if (dart.library.io) 'daum_address_search_mobile.dart';

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

/// 다음 주소 검색 서비스 (플랫폼 자동 선택)
class DaumAddressService {
  static Future<AddressResult?> searchAddress(BuildContext context) async {
    // ✅ 플랫폼에 따라 자동으로 구현체 선택
    return DaumAddressSearchImpl.searchAddress(context);
  }
}