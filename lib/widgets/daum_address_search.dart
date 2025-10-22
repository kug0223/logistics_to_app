import 'package:flutter/material.dart';
import 'dart:convert';

// Web 전용 import (조건부 import)
import 'dart:html' as html;
import 'dart:ui_web' as ui_web;

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

/// 다음 주소 검색 서비스
class DaumAddressService {
  /// 주소 검색 다이얼로그 열기
  static Future<AddressResult?> searchAddress(BuildContext context) async {
    return showDialog<AddressResult>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _AddressSearchDialog(),
    );
  }
}

class _AddressSearchDialog extends StatefulWidget {
  @override
  State<_AddressSearchDialog> createState() => _AddressSearchDialogState();
}

class _AddressSearchDialogState extends State<_AddressSearchDialog> {
  final String _viewId = 'daum-address-${DateTime.now().millisecondsSinceEpoch}';
  bool _isProcessing = false;
  bool _isRegistered = false;

  @override
  void initState() {
    super.initState();
    _registerView();
  }

  void _registerView() {
    // HTML iframe 생성
    final iframe = html.IFrameElement()
      ..style.width = '100%'
      ..style.height = '100%'
      ..style.border = 'none'
      ..srcdoc = _getHtmlContent();

    // platformViewRegistry 등록
    ui_web.platformViewRegistry.registerViewFactory(
      _viewId,
      (int viewId) => iframe,
    );

    setState(() => _isRegistered = true);

    // ✅ 메시지 리스너 - postMessage 이벤트
    html.window.onMessage.listen((event) async {
      if (_isProcessing) return;
      
      final data = event.data;
      if (data is Map && data['type'] == 'complete') {
        _handleAddressComplete(data);
      }
    });

    // ✅ CustomEvent 리스너 추가 (대체 방법)
    html.window.addEventListener('daumAddressComplete', (event) async {
      if (_isProcessing) return;
      
      if (event is html.CustomEvent) {
        final data = event.detail;
        if (data is Map && data['type'] == 'complete') {
          _handleAddressComplete(data);
        }
      }
    });
  }

  /// 주소 선택 완료 처리
  Future<void> _handleAddressComplete(Map data) async {
    setState(() => _isProcessing = true);
    
    print('📍 주소 선택: ${data['address']}');
    
    // REST API로 좌표 변환
    double? latitude;
    double? longitude;
    
    try {
      final coords = await _geocodeAddress(data['address']);
      latitude = coords['latitude'];
      longitude = coords['longitude'];
      print('✅ 좌표: $latitude, $longitude');
    } catch (e) {
      print('⚠️ 좌표 변환 실패: $e');
    }
    
    if (mounted) {
      final result = AddressResult(
        fullAddress: data['address'] ?? '',
        roadAddress: data['roadAddress'] ?? '',
        jibunAddress: data['jibunAddress'] ?? '',
        zonecode: data['zonecode'] ?? '',
        latitude: latitude,
        longitude: longitude,
      );
      
      Navigator.pop(context, result);
    }
  }

  /// REST API로 주소 → 좌표 변환 (Kakao REST API 사용)
  Future<Map<String, double?>> _geocodeAddress(String address) async {
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

  String _getHtmlContent() {
    return '''
<!DOCTYPE html>
<html>
<head>
  <meta charset="UTF-8">
  <style>
    * { margin: 0; padding: 0; }
    body { font-family: 'Malgun Gothic', sans-serif; }
    #wrap { width: 100%; height: 100%; }
  </style>
</head>
<body>
  <div id="wrap"></div>
  <script src="//t1.daumcdn.net/mapjsapi/bundle/postcode/prod/postcode.v2.js"></script>
  <script>
    new daum.Postcode({
      oncomplete: function(data) {
        const address = data.userSelectedType === 'R' ? data.roadAddress : data.jibunAddress;
        
        const messageData = {
          type: 'complete',
          address: address,
          roadAddress: data.roadAddress || '',
          jibunAddress: data.jibunAddress || '',
          zonecode: data.zonecode || ''
        };
        
        // ✅ 방법 1: postMessage 시도
        try {
          if (window.parent && window.parent !== window) {
            window.parent.postMessage(messageData, '*');
            console.log('✅ postMessage 성공');
          }
        } catch (e) {
          console.warn('⚠️ postMessage 실패:', e);
        }
        
        // ✅ 방법 2: CustomEvent 사용 (대체 방법)
        try {
          const customEvent = new CustomEvent('daumAddressComplete', {
            detail: messageData,
            bubbles: true
          });
          window.dispatchEvent(customEvent);
          console.log('✅ CustomEvent 발송 성공');
        } catch (e) {
          console.error('❌ CustomEvent 실패:', e);
        }
      },
      width: '100%',
      height: '100%'
    }).embed(document.getElementById('wrap'));
  </script>
</body>
</html>
    ''';
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Container(
        width: 600,
        height: 600,
        child: Column(
          children: [
            // 헤더
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.blue.shade700,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(4),
                  topRight: Radius.circular(4),
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.search, color: Colors.white),
                  const SizedBox(width: 8),
                  const Text(
                    '주소 검색',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  if (_isProcessing)
                    const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  else
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white),
                      onPressed: () => Navigator.pop(context),
                    ),
                ],
              ),
            ),
            // 주소 검색 iframe
            Expanded(
              child: _isRegistered
                  ? HtmlElementView(viewType: _viewId)
                  : const Center(child: CircularProgressIndicator()),
            ),
          ],
        ),
      ),
    );
  }
}