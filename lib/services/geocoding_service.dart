// lib/services/geocoding_service.dart

import 'package:flutter/foundation.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;

class GeocodingService {
  static const String _kakaoRestApiKey =
      String.fromEnvironment('KAKAO_REST_API_KEY');
  
  /// 주소로 GPS 좌표 조회 (Kakao Local API)
  static Future<Map<String, double>?> getCoordinatesFromAddress(String address) async {
    if (_kakaoRestApiKey.isEmpty) {
      debugPrint('⚠️ [Geocoding] KAKAO_REST_API_KEY 미설정 — --dart-define=KAKAO_REST_API_KEY=xxx 필요');
      return null;
    }
    try {
      debugPrint('🗺️ [Geocoding] 주소 → GPS 변환 시작...');
      debugPrint('   주소: $address');
      
      final encodedAddress = Uri.encodeComponent(address);
      final url = Uri.parse(
        'https://dapi.kakao.com/v2/local/search/address.json?query=$encodedAddress'
      );
      
      final response = await http.get(
        url,
        headers: {
          'Authorization': 'KakaoAK $_kakaoRestApiKey',
        },
      );
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        
        if (data['documents'] != null && data['documents'].isNotEmpty) {
          final doc = data['documents'][0];
          
          // 도로명 주소 우선, 없으면 지번 주소
          final addressData = doc['road_address'] ?? doc['address'];
          
          if (addressData != null) {
            final latitude = double.parse(addressData['y']);
            final longitude = double.parse(addressData['x']);
            
            debugPrint('✅ [Geocoding] 좌표 변환 성공!');
            debugPrint('   위도: $latitude');
            debugPrint('   경도: $longitude');
            
            return {
              'latitude': latitude,
              'longitude': longitude,
            };
          }
        }
        
        debugPrint('❌ [Geocoding] 주소에 대한 좌표를 찾을 수 없습니다.');
        return null;
      } else if (response.statusCode == 401) {
        debugPrint('❌ [Geocoding] API 키 인증 실패 (401)');
        debugPrint('   Kakao REST API 키를 확인하세요!');
        return null;
      } else {
        debugPrint('❌ [Geocoding] API 호출 실패: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      debugPrint('❌ [Geocoding] 에러 발생: $e');
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