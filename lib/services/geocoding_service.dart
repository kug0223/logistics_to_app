// lib/services/geocoding_service.dart

import 'package:flutter/foundation.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;

class GeocodingService {
  static const String _kakaoRestApiKey =
      String.fromEnvironment('KAKAO_REST_API_KEY');
  
  /// 주소로 GPS 좌표 조회 (Kakao Local API)
  static Future<Map<String, double>?> getCoordinatesFromAddress(String address) async {
    if (address.trim().isEmpty) return null;
    if (kDebugMode) {
      debugPrint('🔍 [Geocoding] ▶ 호출됨');
      debugPrint('   키 상태: ${_kakaoRestApiKey.isEmpty ? "❌ 비어있음 (dart-define 미적용)" : "✅ 설정됨 (${_kakaoRestApiKey.substring(0, _kakaoRestApiKey.length.clamp(0, 6))}...)"}');
      debugPrint('   주소: $address');
    }
    if (_kakaoRestApiKey.isEmpty) {
      if (kDebugMode) debugPrint('⚠️ [Geocoding] KAKAO_REST_API_KEY 미설정 — --dart-define=KAKAO_REST_API_KEY=xxx 필요');
      return null;
    }
    try {
      if (kDebugMode) {
        debugPrint('🗺️ [Geocoding] 주소 → GPS 변환 시작...');
        debugPrint('   주소: $address');
      }
      final encodedAddress = Uri.encodeComponent(address);
      final url = Uri.parse(
        'https://dapi.kakao.com/v2/local/search/address.json?query=$encodedAddress'
      );
      
      final response = await http.get(
        url,
        headers: {
          'Authorization': 'KakaoAK $_kakaoRestApiKey',
        },
      ).timeout(const Duration(seconds: 10));
      
      if (kDebugMode) debugPrint('📡 [Geocoding] HTTP 응답 코드: ${response.statusCode}');
      if (response.statusCode != 200 && kDebugMode) {
        debugPrint('   응답 바디: ${response.body}');
      }
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (kDebugMode) debugPrint('   documents 개수: ${(data['documents'] as List?)?.length ?? 0}');
        if (data['documents'] != null && data['documents'].isNotEmpty) {
          final doc = data['documents'][0];

          // 도로명 주소 우선, 없으면 지번 주소
          final addressData = doc['road_address'] ?? doc['address'];

          if (addressData != null) {
            final latStr = addressData['y'] as String?;
            final lngStr = addressData['x'] as String?;
            if (latStr == null || lngStr == null) {
              if (kDebugMode) debugPrint('❌ [Geocoding] 좌표 필드 누락');
              return null;
            }
            final latitude = double.tryParse(latStr);
            final longitude = double.tryParse(lngStr);
            if (latitude == null || longitude == null) return null;

            if (kDebugMode) {
              debugPrint('✅ [Geocoding] 좌표 변환 성공!');
              debugPrint('   위도: $latitude, 경도: $longitude');
            }
            return {
              'latitude': latitude,
              'longitude': longitude,
            };
          }
        }

        if (kDebugMode) debugPrint('❌ [Geocoding] 주소에 대한 좌표를 찾을 수 없습니다.');
        return null;
      } else if (response.statusCode == 401) {
        if (kDebugMode) debugPrint('❌ [Geocoding] API 키 인증 실패 (401)');
        return null;
      } else {
        if (kDebugMode) debugPrint('❌ [Geocoding] API 호출 실패: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      if (kDebugMode) debugPrint('❌ [Geocoding] 에러 발생: $e');
      return null;
    }
  }
  
  /// 여러 주소를 한 번에 변환
  static Future<List<Map<String, double>?>> getCoordinatesFromAddresses(
    List<String> addresses,
  ) async {
    final results = <Map<String, double>?>[];
    
    for (final address in addresses) {
      final coords = await getCoordinatesFromAddress(address);
      results.add(coords);
      
      // API 요청 제한을 고려한 딜레이
      await Future.delayed(const Duration(milliseconds: 100));
    }
    
    return results;
  }
}