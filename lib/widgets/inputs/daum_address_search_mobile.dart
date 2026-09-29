// ============================================
// daum_address_search_mobile.dart (Android/iOS) - 완전 리팩토링
// ✨ StyledDialog + ResponsiveHelper + Theme 색상 + WebView 스케일 조정
// ============================================
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'dart:convert';

// Models
import 'daum_address_search.dart';

// Utils
import '../../utils/responsive_helper.dart';

// Widgets
import '../dialogs/styled_dialog.dart';
import '../../theme/app_colors.dart';

/// Mobile 플랫폼 구현체 - WebView로 다음 주소 API 연동
class DaumAddressSearchImpl {
  static Future<AddressResult?> searchAddress(BuildContext context) async {
    return _showDaumPostcodeDialog(context);
  }

  /// ✨ StyledDialog 기반 주소 검색 다이얼로그
  static Future<AddressResult?> _showDaumPostcodeDialog(BuildContext context) async {
    final theme = Theme.of(context);
    AddressResult? result;

    return showDialog<AddressResult>(
      context: context,
      builder: (context) => StyledDialog(
        title: '주소 검색',
        subtitle: '우편번호 또는 도로명 주소를 검색하세요',
        icon: Icons.location_on,
        headerColor: theme.primaryColor,
        showCloseButton: true,
        content: SizedBox(
          height: ResponsiveHelper.dialogHeight(context),
          // [R7-P4.3A] 좌표 조회를 여기서 하지 않는다.
          //
          //   예전에는 주소를 고른 **직후** 이 콜백 안에서 Kakao 좌표 조회를
          //   `await` 하고, 그게 끝나야 다이얼로그를 닫았다. 그래서 주소를
          //   고른 사용자는 우편번호 WebView 를 보면서 최대 10초(타임아웃)
          //   동안 아무 표시 없이 멈춘 화면을 봤다. 실패해도 조용히 좌표만
          //   비어 있는 채로 닫혔다.
          //
          //   주소 선택과 좌표 확인은 **다른 일**이다. 여기서는 주소만 주고
          //   바로 닫는다. 좌표는 폼이 자기 화면에서 상태를 보여 주며 받는다
          //   (`_resolveCoordinates`). 재시도도 거기서 한다.
          child: _DaumPostcodeWebView(
            onAddressSelected: (selectedResult) {
              result = selectedResult;
              if (context.mounted) Navigator.pop(context, result);
            },
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
            if (mounted) setState(() => _isLoading = false);
          },
        ),
      )
      ..loadHtmlString(_getPostcodeHTML(), baseUrl: 'https://localhost');
  }

  /// 주소 데이터 처리
  void _handleAddressData(String jsonString) {
    try {
      final data = jsonDecode(jsonString);

      String clip(String key, {int max = 200}) {
        final v = data[key]?.toString() ?? '';
        return v.length > max ? v.substring(0, max) : v;
      }

      final result = AddressResult(
        fullAddress: clip('address'),
        roadAddress: clip('roadAddress').isNotEmpty ? clip('roadAddress') : clip('address'),
        jibunAddress: clip('jibunAddress'),
        zonecode: clip('zonecode', max: 10),
        latitude: null, // Geocoding으로 채움
        longitude: null,
        sigungu: clip('sigungu', max: 50).isEmpty ? null : clip('sigungu', max: 50),
        bname: clip('bname', max: 50).isEmpty ? null : clip('bname', max: 50),
      );

      widget.onAddressSelected(result);
    } catch (e) {
      if (kDebugMode) debugPrint('❌ 주소 데이터 파싱 실패: $e');
    }
  }

  /// ✨ 개선된 다음 우편번호 서비스 HTML
  /// - JavaScript 강제 조작으로 모든 텍스트 크기 완벽 제어
  /// - MutationObserver로 동적 생성 요소까지 감지
  String _getPostcodeHTML() {
    return '''
<!DOCTYPE html>
<html>
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=0.9, maximum-scale=1.0, user-scalable=yes">
    <title>다음 주소 검색</title>
    <style>
        * { 
            margin: 0; 
            padding: 0; 
            box-sizing: border-box;
        }
        body { 
            width: 100%; 
            height: 100vh;
            overflow: hidden;
        }
        #container { 
            width: 100%; 
            height: 100%;
        }
    </style>
    <script src="https://t1.daumcdn.net/mapjsapi/bundle/postcode/prod/postcode.v2.js"></script>
</head>
<body>
    <div id="container"></div>
    <script>
        // ✨ 폰트 크기 강제 조정 함수
        function adjustFontSize(element) {
            // 이미 처리된 요소는 스킵
            if (element.dataset && element.dataset.fontAdjusted === 'true') {
                return;
            }
            
            // 현재 폰트 크기 가져오기
            const computedStyle = window.getComputedStyle(element);
            const currentSize = parseFloat(computedStyle.fontSize);
            
            // 폰트 크기가 있는 경우만 조정
            if (currentSize && currentSize > 0) {
                // 12px 이상인 경우 80%로 축소
                if (currentSize >= 12) {
                    const newSize = Math.max(11, currentSize * 0.80);
                    element.style.fontSize = newSize + 'px';
                    element.style.setProperty('font-size', newSize + 'px', 'important');
                }
                
                // line-height도 조정
                element.style.lineHeight = '1.4';
                element.style.setProperty('line-height', '1.4', 'important');
            }
            
            // 패딩도 조정 (입력창, 버튼 등)
            if (element.tagName === 'INPUT') {
                element.style.padding = '8px';
                element.style.setProperty('padding', '8px', 'important');
            } else if (element.tagName === 'BUTTON') {
                element.style.padding = '6px 12px';
                element.style.setProperty('padding', '6px 12px', 'important');
            }
            
            // 처리 완료 표시
            element.dataset.fontAdjusted = 'true';
        }
        
        // ✨ 모든 요소에 폰트 크기 조정 적용
        function adjustAllElements(root) {
            const allElements = root.querySelectorAll('*');
            allElements.forEach(el => adjustFontSize(el));
            
            // root 자체도 조정
            if (root !== document.body) {
                adjustFontSize(root);
            }
        }
        
        // ✨ MutationObserver로 동적 생성 요소 감지
        const observer = new MutationObserver((mutations) => {
            mutations.forEach((mutation) => {
                // 새로 추가된 노드들
                mutation.addedNodes.forEach((node) => {
                    if (node.nodeType === 1) { // Element 노드만
                        adjustFontSize(node);
                        adjustAllElements(node);
                    }
                });
            });
        });
        
        // 다음 우편번호 서비스 실행
        new daum.Postcode({
            oncomplete: function(data) {
                const result = {
                    address: data.address,
                    roadAddress: data.roadAddress || data.address,
                    jibunAddress: data.jibunAddress || '',
                    zonecode: data.zonecode,
                    sigungu: data.sigungu || '',
                    bname: data.bname || ''
                };
                
                handleAddress.postMessage(JSON.stringify(result));
            },
            width: '100%',
            height: '100%',
            autoMapping: true,
            shorthand: false
        }).embed(document.getElementById('container'));
        
        // ✨ 초기 로드 후 모든 요소 조정
        setTimeout(() => {
            adjustAllElements(document.body);
            
            // MutationObserver 시작 (이후 동적 생성 요소 감지)
            observer.observe(document.getElementById('container'), {
                childList: true,
                subtree: true
            });
        }, 100);
        
        // ✨ 추가 안전장치: 1초 후 한 번 더 조정
        setTimeout(() => {
            adjustAllElements(document.body);
        }, 1000);
    </script>
</body>
</html>
    ''';
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: Container(
        clipBehavior: Clip.hardEdge,
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(12)),
        child: Stack(
          children: [
            WebViewWidget(controller: _controller),
          
          // 로딩 오버레이
          if (_isLoading)
            Container(
              color: Colors.white,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(
                      color: Theme.of(context).primaryColor,
                    ),
                    SizedBox(height: ResponsiveHelper.spacing(context, 16)),
                    Text(
                      '주소 검색 로딩 중...',
                      style: ResponsiveHelper.bodyStyle(
                        context,
                        color: AppColors.grey600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
        ),
      ),
    );
  }
}
