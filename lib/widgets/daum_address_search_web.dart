// ============================================
// daum_address_search_web.dart (Web 전용)
// ============================================
import 'package:flutter/material.dart';
import 'dart:convert';
import 'dart:html' as html;
import 'dart:ui_web' as ui_web;
import 'dart:js' as js;

import 'daum_address_search.dart';

/// Web 플랫폼 구현체
class DaumAddressSearchImpl {
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

  @override
  void initState() {
    super.initState();
    _registerView();
  }

  void _registerView() {
    // JavaScript 콜백 등록
    js.context['flutterAddressCallback'] = js.allowInterop((String addressJson) {
      if (_isProcessing) return;
      setState(() => _isProcessing = true);
      _handleAddressComplete(addressJson);
    });

    // iframe 생성
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
  }

  Future<void> _handleAddressComplete(String addressJson) async {
    try {
      final data = jsonDecode(addressJson);
      final address = data['address'] ?? '';

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
      
      if (mounted) {
        final result = AddressResult(
          fullAddress: address,
          roadAddress: data['roadAddress'] ?? '',
          jibunAddress: data['jibunAddress'] ?? '',
          zonecode: data['zonecode'] ?? '',
          latitude: latitude,
          longitude: longitude,
        );
        
        Navigator.pop(context, result);
      }
    } catch (e) {
      print('❌ 주소 처리 오류: $e');
      setState(() => _isProcessing = false);
    }
  }

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
    #wrap { width: 100%; height: 100vh; }
  </style>
</head>
<body>
  <div id="wrap"></div>
  <script src="//t1.daumcdn.net/mapjsapi/bundle/postcode/prod/postcode.v2.js"></script>
  <script>
    window.addEventListener('load', function() {
      new daum.Postcode({
        oncomplete: function(data) {
          const address = data.userSelectedType === 'R' ? data.roadAddress : data.jibunAddress;
          
          const result = {
            address: address,
            roadAddress: data.roadAddress || '',
            jibunAddress: data.jibunAddress || '',
            zonecode: data.zonecode || ''
          };
          
          console.log('✅ 주소 선택됨:', result);
          
          if (window.parent && window.parent.flutterAddressCallback) {
            try {
              window.parent.flutterAddressCallback(JSON.stringify(result));
            } catch (e) {
              console.error('❌ 콜백 호출 실패:', e);
            }
          }
        },
        width: '100%',
        height: '100%'
      }).embed(document.getElementById('wrap'));
    });
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
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.blue[700],
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
            Expanded(
              child: HtmlElementView(viewType: _viewId),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    js.context['flutterAddressCallback'] = null;
    super.dispose();
  }
}