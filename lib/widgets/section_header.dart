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
    // [R7-P2-1 P21-H] 액션 폭 상한은 **행 자신의 폭**에서 나온다.
    //   Row 안쪽에서 LayoutBuilder 를 쓰면 비-flex 자식이라 제약이 무한대로
    //   들어와 상한이 걸리지 않는다 — 바깥에서 한 번 잰다.
    return LayoutBuilder(builder: (context, c) {
      final double? actionMax = c.maxWidth.isFinite ? c.maxWidth * 0.6 : null;
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
                      Text(title, style: AppTextStyles.sectionTitle()),
                      SizedBox(height: 2 * s),
                      Text(subtitle!, style: AppTextStyles.sectionSubtitle()),
                    ],
                  )
                : Text(title, style: AppTextStyles.sectionTitle()),
          ),
          // 우측 액션
          if (actionText != null && onAction != null) ...[
            SizedBox(width: 8 * s),
            // [R7-P2-1 P21-H] 액션에 상한이 없어서, 긴 액션(`2026년 9월 ›`)이
            //   좁은 화면·큰 배율에서 행을 넘쳤다(320dp·2.0 에서 31px).
            //   액션은 **목적지를 말하는 문구**라 줄이면 어디로 가는지 잃는다.
            //   그래서 자르지 않고, 폭의 60% 를 넘을 때만 줄바꿈하게 한다 —
            //   들어가는 평소에는 상한이 걸리지 않아 기존 배치와 같다.
            ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: actionMax ?? double.infinity,
              ),
              child: GestureDetector(
                onTap: onAction,
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  // 터치 영역 확장 (최소 44×44 확보)
                  padding:
                      EdgeInsets.symmetric(vertical: 8 * s, horizontal: 4 * s),
                  child: Text(
                    actionText!,
                    style: AppTextStyles.sectionAction(),
                  ),
                ),
              ),
            ),
          ],
        ],
      );
    });
  }
}
