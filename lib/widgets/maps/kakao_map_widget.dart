import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../../utils/responsive_helper.dart';

/// 🗺️ 카카오맵 위젯
/// - WebView로 카카오맵 표시
/// - 마커로 위치 표시
/// - 반응형 높이 지원
class KakaoMapWidget extends StatefulWidget {
  final double latitude;
  final double longitude;
  final String placeName;
  final double? height; // null이면 자동 높이 (반응형)
  final bool showControls; // 확대/축소 버튼 표시 여부

  const KakaoMapWidget({
    super.key,
    required this.latitude,
    required this.longitude,
    required this.placeName,
    this.height,
    this.showControls = true,
  });

  @override
  State<KakaoMapWidget> createState() => _KakaoMapWidgetState();
}

class _KakaoMapWidgetState extends State<KakaoMapWidget> {
  late final WebViewController _controller;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _initializeWebView();
  }

  void _initializeWebView() {
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.white)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (String url) {
            print('🗺️ 지도 로딩 시작: $url');
          },
          onPageFinished: (String url) {
            print('✅ 지도 로딩 완료: $url');
            setState(() => _isLoading = false);
          },
          onWebResourceError: (WebResourceError error) {
            print('❌ 지도 로딩 에러: ${error.description}');
            setState(() => _isLoading = false);
          },
        ),
      )
      ..loadHtmlString(_buildMapHtml());
  }

  /// 🗺️ 카카오맵 HTML 생성
  String _buildMapHtml() {
    return '''
<!DOCTYPE html>
<html>
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
    <style>
        * { margin: 0; padding: 0; }
        html, body { width: 100%; height: 100%; overflow: hidden; }
        #map { width: 100%; height: 100%; }
    </style>
</head>
<body>
    <div id="map"></div>
    <script type="text/javascript" src="https://dapi.kakao.com/v2/maps/sdk.js?appkey=b11bc20a0e0981b6214e611198f4d237"></script>
    <script>
        // ✅ SDK 로드 완료 대기!
        window.onload = function() {
            if (typeof kakao === 'undefined') {
                console.error('카카오맵 SDK 로드 실패');
                return;
            }
            
            var container = document.getElementById('map');
            var options = {
                center: new kakao.maps.LatLng(${widget.latitude}, ${widget.longitude}),
                level: 3
            };

            var map = new kakao.maps.Map(container, options);
            
            // 지도 확대/축소 컨트롤
            ${widget.showControls ? '''
            var zoomControl = new kakao.maps.ZoomControl();
            map.addControl(zoomControl, kakao.maps.ControlPosition.RIGHT);
            ''' : ''}
            
            // 마커 생성
            var markerPosition = new kakao.maps.LatLng(${widget.latitude}, ${widget.longitude});
            var marker = new kakao.maps.Marker({
                position: markerPosition,
                map: map
            });

            // 인포윈도우 (장소명 표시)
            var infowindow = new kakao.maps.InfoWindow({
                content: '<div style="padding:8px 12px;font-size:14px;font-weight:bold;background:white;border-radius:8px;box-shadow:0 2px 8px rgba(0,0,0,0.1);">${widget.placeName}</div>',
                removable: false
            });
            infowindow.open(map, marker);
            
            // 모바일 터치 최적화
            if (window.innerWidth < 600) {
                map.setDraggable(true);
                map.setZoomable(true);
            }
            
            console.log('✅ 카카오맵 초기화 완료');
        };
    </script>
</body>
</html>
    ''';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    // 반응형 높이 계산
    final mapHeight = widget.height ?? ResponsiveHelper.spacing(context, 300);
    
    return Container(
      height: mapHeight,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: theme.dividerColor,
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Stack(
          children: [
            // 지도 WebView
            WebViewWidget(controller: _controller),
            
            // 로딩 인디케이터 (개선)
            if (_isLoading)
              Container(
                color: Colors.white,
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      CircularProgressIndicator(
                        valueColor: AlwaysStoppedAnimation<Color>(
                          theme.primaryColor,
                        ),
                      ),
                      SizedBox(height: ResponsiveHelper.spacing(context, 12)),
                      Text(
                        '지도를 불러오는 중...',
                        style: ResponsiveHelper.bodyStyle(context).copyWith(
                          color: theme.textTheme.bodySmall?.color,
                        ),
                      ),
                      SizedBox(height: ResponsiveHelper.spacing(context, 8)),
                      Text(
                        '시뮬레이터에서는 시간이 걸릴 수 있습니다',
                        style: ResponsiveHelper.smallStyle(context).copyWith(
                          color: theme.textTheme.bodySmall?.color?.withOpacity(0.7),
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
            
            // 🆕 지도 대체 UI (실제 기기 권장)
            Positioned(
              bottom: ResponsiveHelper.spacing(context, 8),
              left: ResponsiveHelper.spacing(context, 8),
              child: Container(
                padding: EdgeInsets.symmetric(
                  horizontal: ResponsiveHelper.spacing(context, 8),
                  vertical: ResponsiveHelper.spacing(context, 4),
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.9),
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 4,
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.info_outline,
                      size: ResponsiveHelper.iconSize(context, 14),
                      color: theme.primaryColor,
                    ),
                    SizedBox(width: ResponsiveHelper.spacing(context, 4)),
                    Text(
                      '실제 기기에서 더 빠릅니다',
                      style: ResponsiveHelper.tinyStyle(context).copyWith(
                        color: theme.textTheme.bodySmall?.color,
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