// ============================================
// daum_address_search_mobile.dart (Android/iOS) - GPS 좌표 추가
// ============================================
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'dart:convert';
import 'daum_address_search.dart';
import '../../services/geocoding_service.dart';  // ⭐ 추가

/// Mobile 플랫폼 구현체 - WebView로 다음 주소 API 연동
class DaumAddressSearchImpl {
  static Future<AddressResult?> searchAddress(BuildContext context) async {
    return _showDaumPostcodeWebView(context);
  }

  /// 다음 우편번호 서비스 WebView
  static Future<AddressResult?> _showDaumPostcodeWebView(BuildContext context) async {
    AddressResult? result;
    
    return showDialog<AddressResult>(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        child: Container(
          height: MediaQuery.of(context).size.height * 0.8,
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              // 헤더
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.location_on,
                      color: Colors.blue.shade700,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    '주소 검색',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // WebView
              Expanded(
                child: _DaumPostcodeWebView(
                  onAddressSelected: (selectedResult) async {
                    // ⭐ GPS 좌표 자동 획득
                    final coords = await GeocodingService.getCoordinatesFromAddress(
                      selectedResult.fullAddress,
                    );
                    
                    // GPS 좌표 추가
                    result = AddressResult(
                      fullAddress: selectedResult.fullAddress,
                      roadAddress: selectedResult.roadAddress,
                      jibunAddress: selectedResult.jibunAddress,
                      zonecode: selectedResult.zonecode,
                      latitude: coords?['latitude'],   // ⭐ GPS 좌표
                      longitude: coords?['longitude'], // ⭐ GPS 좌표
                    );
                    
                    Navigator.pop(context, result);
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 다음 우편번호 서비스 WebView 위젯
class _DaumPostcodeWebView extends StatefulWidget {
  final Function(AddressResult) onAddressSelected;

  const _DaumPostcodeWebView({
    required this.onAddressSelected,
  });

  @override
  State<_DaumPostcodeWebView> createState() => _DaumPostcodeWebViewState();
}

class _DaumPostcodeWebViewState extends State<_DaumPostcodeWebView> {
  late final WebViewController _controller;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _initWebView();
  }

  void _initWebView() {
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.white)
      ..addJavaScriptChannel(
        'handleAddress',
        onMessageReceived: (JavaScriptMessage message) {
          _handleAddressData(message.message);
        },
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (String url) {
            setState(() => _isLoading = false);
          },
        ),
      )
      ..loadHtmlString(_getPostcodeHTML(), baseUrl: 'https://localhost');
  }

  /// 주소 데이터 처리
  void _handleAddressData(String jsonString) {
    try {
      final data = jsonDecode(jsonString);
      
      final result = AddressResult(
        fullAddress: data['address'] ?? '',
        roadAddress: data['roadAddress'] ?? data['address'] ?? '',
        jibunAddress: data['jibunAddress'] ?? '',
        zonecode: data['zonecode'] ?? '',
        latitude: null,  // 나중에 Geocoding으로 채움
        longitude: null,
      );
      
      widget.onAddressSelected(result);
    } catch (e) {
      print('❌ 주소 데이터 파싱 실패: $e');
    }
  }

  /// 다음 우편번호 서비스 HTML
  String _getPostcodeHTML() {
    return '''
<!DOCTYPE html>
<html>
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>다음 주소 검색</title>
    <style>
        * { margin: 0; padding: 0; }
        body { width: 100%; height: 100vh; }
        #container { width: 100%; height: 100%; }
    </style>
    <script src="https://t1.daumcdn.net/mapjsapi/bundle/postcode/prod/postcode.v2.js"></script>
</head>
<body>
    <div id="container"></div>
    <script>
        // 다음 우편번호 서비스 실행
        new daum.Postcode({
            oncomplete: function(data) {
                // 선택한 주소 데이터를 Flutter로 전달
                const result = {
                    address: data.address,
                    roadAddress: data.roadAddress || data.address,
                    jibunAddress: data.jibunAddress || '',
                    zonecode: data.zonecode
                };
                
                // Flutter로 메시지 전송
                handleAddress.postMessage(JSON.stringify(result));
            },
            width: '100%',
            height: '100%'
        }).embed(document.getElementById('container'));
    </script>
</body>
</html>
    ''';
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        WebViewWidget(controller: _controller),
        if (_isLoading)
          Container(
            color: Colors.white,
            child: const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('주소 검색 로딩 중...'),
                ],
              ),
            ),
          ),
      ],
    );
  }
}