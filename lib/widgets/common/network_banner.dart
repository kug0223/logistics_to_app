import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/network_provider.dart';
import '../../theme/app_colors.dart';
import '../../utils/responsive_helper.dart';

/// 네트워크 상태를 앱 상단에 배너로 표시하는 래퍼 위젯
class NetworkBanner extends StatefulWidget {
  final Widget child;
  const NetworkBanner({super.key, required this.child});

  @override
  State<NetworkBanner> createState() => _NetworkBannerState();
}

class _NetworkBannerState extends State<NetworkBanner>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _heightAnim;
  bool? _prevOnline; // null = 초기 상태 (배너 미표시)

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _heightAnim = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<NetworkProvider>(
      builder: (context, network, child) {
        final isOnline = network.isOnline;

        // 초기 오프라인 상태 또는 상태 변경 시 애니메이션
        if (_prevOnline != isOnline) {
          if (!isOnline) {
            _controller.forward();
          } else if (_prevOnline != null) {
            // 재연결 시(초기 온라인 제외) 잠깐 초록 배너 보여주고 닫기
            _controller.forward().then((_) async {
              await Future.delayed(const Duration(seconds: 2));
              if (mounted) _controller.reverse();
            });
          }
        }
        _prevOnline = isOnline;

        return Column(
          children: [
            SizeTransition(
              sizeFactor: _heightAnim,
              child: _NetworkBar(isOnline: isOnline),
            ),
            Expanded(child: widget.child),
          ],
        );
      },
    );
  }
}

class _NetworkBar extends StatelessWidget {
  final bool isOnline;
  const _NetworkBar({required this.isOnline});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: isOnline ? AppColors.successMedium : AppColors.errorMedium,
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            isOnline ? Icons.wifi : Icons.wifi_off,
            color: Colors.white,
            size: 16,
          ),
          const SizedBox(width: 6),
          Text(
            isOnline ? '인터넷 연결이 복구되었습니다' : '인터넷 연결이 없습니다',
            style: ResponsiveHelper.smallStyle(context, color: Colors.white).copyWith(fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }
}
