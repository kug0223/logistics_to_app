// lib/services/geocoding_service.dart

import 'package:flutter/foundation.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;

/// [R7-P4.3A] 주소 → 좌표 변환이 **왜** 실패했는지.
///
///   예전에는 이 서비스가 여섯 가지 다른 사건을 전부 `null` 하나로 돌려줬다:
///   키 미설정 · 401 · 그 밖의 HTTP 오류 · 타임아웃/네트워크 · 검색 결과 0건 ·
///   응답에 좌표 필드 없음. 그리고 그 이유를 적는 `debugPrint` 는 전부
///   `kDebugMode` 안에 있어서, **릴리스 기기에서는 아무 흔적도 남지 않았다.**
///
///   호출부는 `null` 만 받으니 화면에 쓸 말이 하나뿐이었고, 사용자는 다시
///   시도해야 하는지 주소를 바꿔야 하는지 알 수 없었다. 원인별로 다음 행동이
///   다르므로 원인을 그대로 올려 보낸다.
enum GeocodeStatus {
  /// 좌표를 찾았다.
  resolved,

  /// 조회는 성공했는데 그 주소로 등록된 좌표가 없다(검색 결과 0건).
  /// 다시 눌러도 결과는 같다 — 주소를 바꿔야 한다.
  notFound,

  /// 키가 거부됐다(401). 사용자가 할 수 있는 일이 없다.
  unauthorized,

  /// 네트워크·타임아웃·그 밖의 서버 응답. **다시 시도하면 될 수 있다.**
  unavailable,

  /// 빌드에 `KAKAO_REST_API_KEY` 가 들어 있지 않다(`--dart-define` 누락).
  /// 기기에서 다시 눌러도 영원히 안 된다 — 빌드 문제다.
  notConfigured,
}

class GeocodeResult {
  const GeocodeResult(this.status, {this.latitude, this.longitude});

  final GeocodeStatus status;
  final double? latitude;
  final double? longitude;

  bool get isResolved => status == GeocodeStatus.resolved;

  /// 같은 입력으로 다시 시도하는 것이 의미 있는 실패인가.
  bool get isRetryable => status == GeocodeStatus.unavailable;
}

class GeocodingService {
  static const String _kakaoRestApiKey =
      String.fromEnvironment('KAKAO_REST_API_KEY');

  /// 빌드에 키가 들어 있는지. 화면이 "다시 시도" 를 권할지 말지 정하는 데 쓴다.
  static bool get isConfigured => _kakaoRestApiKey.isNotEmpty;

  /// 주소로 좌표 조회 (Kakao Local API).
  ///
  /// 실패를 `null` 로 뭉개지 않는다 — [GeocodeResult.status] 를 본다.
  static Future<GeocodeResult> resolveAddress(String address) async {
    if (address.trim().isEmpty) {
      return const GeocodeResult(GeocodeStatus.notFound);
    }
    if (_kakaoRestApiKey.isEmpty) {
      // [R7-P4.3A] 이 분기는 릴리스에서도 남아야 한다 — 기기에서 "주소를
      //   찾지 못했어요" 로 보이면 주소를 계속 바꿔 보게 되는데, 실제로는
      //   빌드에 키가 없는 것이라 무엇을 해도 안 된다.
      debugPrint('⚠️ [Geocoding] KAKAO_REST_API_KEY 미설정 — 빌드에 dart-define 누락');
      return const GeocodeResult(GeocodeStatus.notConfigured);
    }
    try {
      final url = Uri.parse(
        'https://dapi.kakao.com/v2/local/search/address.json'
        '?query=${Uri.encodeComponent(address)}',
      );

      final response = await http.get(
        url,
        headers: {'Authorization': 'KakaoAK $_kakaoRestApiKey'},
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 401 || response.statusCode == 403) {
        // 키 값 자체는 로그에 남기지 않는다.
        debugPrint('❌ [Geocoding] 키 거부 (${response.statusCode})');
        return const GeocodeResult(GeocodeStatus.unauthorized);
      }
      if (response.statusCode != 200) {
        debugPrint('❌ [Geocoding] 응답 ${response.statusCode}');
        return const GeocodeResult(GeocodeStatus.unavailable);
      }

      final data = json.decode(response.body);
      final documents = data['documents'] as List?;
      if (documents == null || documents.isEmpty) {
        return const GeocodeResult(GeocodeStatus.notFound);
      }

      // 도로명 주소 우선, 없으면 지번 주소
      final addressData = documents[0]['road_address'] ?? documents[0]['address'];
      if (addressData == null) {
        return const GeocodeResult(GeocodeStatus.notFound);
      }

      final latitude = double.tryParse(addressData['y']?.toString() ?? '');
      final longitude = double.tryParse(addressData['x']?.toString() ?? '');
      if (latitude == null || longitude == null) {
        debugPrint('❌ [Geocoding] 응답에 좌표 필드 없음');
        return const GeocodeResult(GeocodeStatus.notFound);
      }

      if (kDebugMode) {
        debugPrint('✅ [Geocoding] $latitude, $longitude');
      }
      return GeocodeResult(
        GeocodeStatus.resolved,
        latitude: latitude,
        longitude: longitude,
      );
    } catch (e) {
      // 타임아웃·네트워크·파싱 — 다시 시도할 수 있는 실패로 본다.
      debugPrint('❌ [Geocoding] 실패: $e');
      return const GeocodeResult(GeocodeStatus.unavailable);
    }
  }
}
