// ============================================
// daum_address_search_web.dart (Web 전용)
// ============================================
import 'package:flutter/material.dart';
import 'dart:convert';
import 'dart:html' as html;
import 'dart:js' as js;
import 'dart:async';

import 'daum_address_search.dart';

/// Web 플랫폼 구현체
class DaumAddressSearchImpl {
  static Future<AddressResult?> searchAddress(BuildContext context) async {
    return _openDaumPopup();
  }
  
  static Future<AddressResult?> _openDaumPopup() async {
    final completer = Completer<AddressResult?>();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    
    // 전역 콜백 등록
    js.context['daumAddressCallback$timestamp'] = js.allowInterop((
      String address,
      String roadAddress,
      String jibunAddress,
      String zonecode,
    ) async {
      try {
        print('📍 주소 선택: $address');
        
        // 좌표 변환
        double? latitude;
        double? longitude;
        
        try {
          final coords = await _geocodeAddress(address);
          latitude = coords['latitude'];
          longitude = coords['longitude'];
          print('✅ 좌표: $latitude, $longitude');
        } catch (e) {
          print('⚠️ 좌표 변환 실패: $e');
        }
        
        final result = AddressResult(
          fullAddress: address,
          roadAddress: roadAddress,
          jibunAddress: jibunAddress,
          zonecode: zonecode,
          latitude: latitude,
          longitude: longitude,
        );
        
        completer.complete(result);
      } catch (e) {
        print('❌ 주소 처리 오류: $e');
        completer.complete(null);
      } finally {
        js.context['daumAddressCallback$timestamp'] = null;
      }
    });
    
    // ⭐ Daum 공식 팝업 URL 사용
    final popupUrl = 'https://postcode.map.daum.net/guide?callback=opener.daumAddressCallback$timestamp';
    
    // 팝업 열기
    final popup = html.window.open(
      popupUrl,
      'daumAddressPopup',
      'width=570,height=420,scrollbars=yes',
    );
    
    if (popup == null) {
      print('❌ 팝업이 차단되었습니다');
      js.context['daumAddressCallback$timestamp'] = null;
      return null;
    }
    
    print('✅ Daum 주소 검색 팝업 열림');
    
    // 팝업이 닫힐 때까지 대기
    Timer.periodic(const Duration(milliseconds: 500), (timer) {
      try {
        if (popup.closed == true) {
          timer.cancel();
          if (!completer.isCompleted) {
            print('⚠️ 주소 선택 없이 팝업 닫힘');
            completer.complete(null);
            js.context['daumAddressCallback$timestamp'] = null;
          }
        }
      } catch (e) {
        timer.cancel();
        if (!completer.isCompleted) {
          completer.complete(null);
          js.context['daumAddressCallback$timestamp'] = null;
        }
      }
    });
    
    return completer.future;
  }
  
  static Future<Map<String, double?>> _geocodeAddress(String address) async {
    try {
      const kakaoApiKey = '3605b3b94d2ecc9123d063e510b02d8f';
      
      final encodedAddress = Uri.encodeComponent(address);
      final url = 'https://dapi.kakao.com/v2/local/search/address.json?query=$encodedAddress';
      
      final response = await html.HttpRequest.request(
        url,
        method: 'GET',
        requestHeaders: {
          'Authorization': 'KakaoAK $kakaoApiKey',
        },
      );
      
      final data = jsonDecode(response.responseText!);
      
      if (data['documents'] != null && data['documents'].isNotEmpty) {
        final doc = data['documents'][0];
        return {
          'latitude': double.tryParse(doc['y']?.toString() ?? '0'),
          'longitude': double.tryParse(doc['x']?.toString() ?? '0'),
        };
      }
      
      return {'latitude': null, 'longitude': null};
    } catch (e) {
      print('❌ Geocoding 오류: $e');
      return {'latitude': null, 'longitude': null};
    }
  }
}