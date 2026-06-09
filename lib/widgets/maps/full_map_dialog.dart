import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../models/core/business_model.dart';
import '../../utils/responsive_helper.dart';
import '../../utils/toast_helper.dart';
import 'kakao_map_widget.dart';
import 'package:flutter/services.dart';

/// 🗺️ 전체화면 지도 다이얼로그
/// - 큰 화면에서 상세 지도 보기
/// - 사업장 정보 카드 오버레이
/// - 길찾기 버튼
class FullMapDialog extends StatelessWidget {
  final BusinessModel business;

  const FullMapDialog({
    super.key,
    required this.business,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: EdgeInsets.zero,
      child: Container(
        width: MediaQuery.sizeOf(context).width,
        height: MediaQuery.sizeOf(context).height,
        color: Colors.white,
        child: Stack(
          children: [
            // 전체 화면 지도
            Positioned.fill(
              child: business.latitude != null && business.longitude != null
                  ? KakaoMapWidget(
                      latitude: business.latitude!,
                      longitude: business.longitude!,
                      placeName: business.name,
                      showControls: true,
                    )
                  : const Center(child: Text('위치 정보를 불러올 수 없습니다')),
            ),
            
            // 상단: 닫기 버튼
            Positioned(
              top: MediaQuery.of(context).padding.top + ResponsiveHelper.spacing(context, 8),
              right: ResponsiveHelper.spacing(context, 16),
              child: _buildCloseButton(context, theme),
            ),
            
            // 하단: 사업장 정보 카드
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: _buildBottomCard(context, theme),
            ),
          ],
        ),
      ),
    );
  }

  /// 닫기 버튼
  Widget _buildCloseButton(BuildContext context, ThemeData theme) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: IconButton(
        onPressed: () => Navigator.pop(context),
        icon: Icon(
          Icons.close,
          color: theme.primaryColor,
          size: ResponsiveHelper.iconSize(context, 24),
        ),
        tooltip: '닫기',
      ),
    );
  }

  /// 하단 사업장 정보 카드
  Widget _buildBottomCard(BuildContext context, ThemeData theme) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(24),
          topRight: Radius.circular(24),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 20,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: ResponsiveHelper.cardPadding(context),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 드래그 핸들
              Center(
                child: Container(
                  width: ResponsiveHelper.spacing(context, 40),
                  height: ResponsiveHelper.spacing(context, 4),
                  decoration: BoxDecoration(
                    color: theme.dividerColor,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              
              SizedBox(height: ResponsiveHelper.spacing(context, 16)),
              
              // 사업장명
              Text(
                business.name,
                style: ResponsiveHelper.subtitleStyle(context).copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              
              SizedBox(height: ResponsiveHelper.spacing(context, 8)),
              
              // 주소 + 상세주소 + 복사 버튼
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.location_on,
                    size: ResponsiveHelper.iconSize(context, 18),
                    color: theme.primaryColor,
                  ),
                  SizedBox(width: ResponsiveHelper.spacing(context, 6)),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 기본 주소
                        Text(
                          business.address,
                          style: ResponsiveHelper.bodyStyle(context).copyWith(
                            color: theme.textTheme.bodySmall?.color,
                          ),
                        ),
                        // 상세주소 (있을 경우)
                        if (business.detailAddress != null && 
                            business.detailAddress!.isNotEmpty) ...[
                          SizedBox(height: ResponsiveHelper.spacing(context, 2)),
                          Text(
                            business.detailAddress!,
                            style: ResponsiveHelper.bodyStyle(context).copyWith(
                              color: theme.textTheme.bodySmall?.color,
                            ),
                          ),
                        ],
                        // 📋 주소 복사 버튼
                        SizedBox(height: ResponsiveHelper.spacing(context, 6)),
                        InkWell(
                          onTap: () {
                            // 주소 + 상세주소 함께 복사
                            String fullAddress = business.address;
                            if (business.detailAddress != null && 
                                business.detailAddress!.isNotEmpty) {
                              fullAddress += ' ${business.detailAddress}';
                            }
                            Clipboard.setData(ClipboardData(text: fullAddress));
                            ToastHelper.showSuccess('주소가 복사되었습니다');
                          },
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.content_copy,
                                size: ResponsiveHelper.iconSize(context, 14),
                                color: theme.primaryColor,
                              ),
                              SizedBox(width: ResponsiveHelper.spacing(context, 4)),
                              Text(
                                '주소 복사',
                                style: ResponsiveHelper.smallStyle(context).copyWith(
                                  color: theme.primaryColor,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              
              // 교통 정보
              if (business.nearestStation != null) ...[
                SizedBox(height: ResponsiveHelper.spacing(context, 6)),
                Row(
                  children: [
                    Icon(
                      Icons.subway,
                      size: ResponsiveHelper.iconSize(context, 18),
                      color: AppColors.info,
                    ),
                    SizedBox(width: ResponsiveHelper.spacing(context, 6)),
                    Text(
                      '${business.nearestStation}${business.walkingMinutes != null ? " 도보 ${business.walkingMinutes}분" : ""}',
                      style: ResponsiveHelper.bodyStyle(context).copyWith(
                        color: theme.textTheme.bodySmall?.color,
                      ),
                    ),
                  ],
                ),
              ],
              
              SizedBox(height: ResponsiveHelper.spacing(context, 16)),
              
              // 길찾기 버튼만
              SizedBox(
                width: double.infinity,
                child: _buildActionButton(
                  context: context,
                  theme: theme,
                  icon: Icons.directions,
                  label: '길찾기',
                  color: theme.primaryColor,
                  onPressed: () => _openDirections(context),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 액션 버튼
  Widget _buildActionButton({
    required BuildContext context,
    required ThemeData theme,
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onPressed,
  }) {
    return ElevatedButton.icon(
      onPressed: onPressed,
      icon: Icon(
        icon,
        size: ResponsiveHelper.iconSize(context, 20),
      ),
      label: Text(
        label,
        style: ResponsiveHelper.bodyStyle(context).copyWith(
          color: Colors.white,
          fontWeight: FontWeight.bold,
        ),
      ),
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        padding: EdgeInsets.symmetric(
          vertical: ResponsiveHelper.spacing(context, 14),
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        elevation: 0,
      ),
    );
  }

  /// 길찾기
  void _openDirections(BuildContext context) async {
    final lat = business.latitude;
    final lng = business.longitude;
    if (lat == null || lng == null) {
      ToastHelper.showError('위치 정보가 없습니다');
      return;
    }
    final uri = Uri.parse(
      'https://map.kakao.com/link/to/${business.name},$lat,$lng',
    );

    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      ToastHelper.showError('길찾기를 열 수 없습니다');
    }
  }
}