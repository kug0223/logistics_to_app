// lib/widgets/section_header.dart
//
// ALfit 홈 섹션 헤더 공통 위젯
//
// 사용법:
//   SectionHeader(
//     s: s,
//     title: '8월 12일 일자리',
//     actionText: '3개 모두보기 ›',
//     onAction: () => ...,
//   )
//
//   SectionHeader(
//     s: s,
//     title: '지원 현황',
//     subtitle: '오산시 주변',       // 선택적 부제목
//     actionText: '전체보기 ›',
//     onAction: () => ...,
//   )
//
//   SectionHeader(s: s, title: '나의 ALfit') // 액션 없음

import 'package:flutter/material.dart';

import '../theme/app_text_styles.dart';

class SectionHeader extends StatelessWidget {
  final String title;

  /// 제목 아래에 표시할 부제목 (예: 지역명)
  final String? subtitle;

  /// 우측 액션 텍스트 (예: "3개 모두보기 ›", "전체보기 ›")
  final String? actionText;

  /// 액션 탭 콜백
  final VoidCallback? onAction;

  /// ResponsiveHelper scale factor (기본 1.0)
  final double s;

  const SectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.actionText,
    this.onAction,
    this.s = 1.0,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // 제목 + 선택적 부제목
        Expanded(
          child: subtitle != null
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(title, style: AppTextStyles.sectionTitle(s: s)),
                    SizedBox(height: 2 * s),
                    Text(subtitle!, style: AppTextStyles.sectionSubtitle(s: s)),
                  ],
                )
              : Text(title, style: AppTextStyles.sectionTitle(s: s)),
        ),
        // 우측 액션
        if (actionText != null && onAction != null) ...[
          SizedBox(width: 8 * s),
          GestureDetector(
            onTap: onAction,
            behavior: HitTestBehavior.opaque,
            child: Padding(
              // 터치 영역 확장 (최소 44×44 확보)
              padding: EdgeInsets.symmetric(
                  vertical: 8 * s, horizontal: 4 * s),
              child: Text(
                actionText!,
                style: AppTextStyles.sectionAction(s: s),
              ),
            ),
          ),
        ],
      ],
    );
  }
}
