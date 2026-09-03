// lib/widgets/user/cards/job_image_placeholder.dart

import 'package:flutter/material.dart';
import '../../../theme/app_colors.dart';
import '../../work_type_icon.dart';

/// 사업장 대표 이미지가 없을 때 표시하는 ALfit 전용 Placeholder
///
/// 실제 사업장 사진이 없거나 로딩 실패 시 회색 빈 박스 대신 사용.
/// 업무 유형 아이콘 + 연한 브랜드 배경으로 empty-state임을 명확히 표현.
///
/// 이미지 fallback 우선순위:
///   1. 사업장/공고 대표 이미지 (CachedNetworkImage)
///   2. 업무 유형 이미지 (현재 미사용)
///   3. JobImagePlaceholder (본 위젯)
///
/// 다른 사업장의 실제 사진을 fallback으로 절대 사용하지 않는다.
class JobImagePlaceholder extends StatelessWidget {
  /// `to.workDetails.firstOrNull?.workTypeIcon` 등에서 전달
  final String? workTypeIcon;

  /// null이면 부모 위젯이 크기를 결정 (Expanded, AspectRatio 등)
  final double? width;
  final double? height;

  const JobImagePlaceholder({
    super.key,
    this.workTypeIcon,
    this.width,
    this.height,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      // 연한 ALfit 브랜드 블루 배경 — 실제 사진이 아님을 명확히 구분
      color: const Color(0xFFEEF4FD),
      child: Center(
        child: _buildIcon(),
      ),
    );
  }

  Widget _buildIcon() {
    final icon = workTypeIcon;
    if (icon != null && icon.isNotEmpty) {
      return Opacity(
        opacity: 0.4,
        child: WorkTypeIcon.buildFromString(
          icon,
          color: AppColors.infoDark,
          size: 28,
        ),
      );
    }
    return Icon(
      Icons.work_outline,
      color: AppColors.infoDark.withValues(alpha: 0.3),
      size: 26,
    );
  }
}
