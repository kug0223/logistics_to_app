// [CP02] 두 셸 공용 하단 탭 — 표시부만(라우팅·권한·순서·방문·Navigator 는 셸이 소유).
//
// 정본: records/reports/DU_concept_precise_spec_audit_2026-11-11.md §7.
// 입력은 셋뿐이다: 보이는 탭 항목(기존 아이콘 쌍·라벨), 현재 '보이는' 위치, 탭(보이는 위치) 콜백.
//   관리자 셸의 visible → actual 대응은 셸이 `onTap: (i) => switchToTab(visibleIndices[i])` 로 계속 소유한다.
// SDK BottomNavigationBar 는 라벨 글자 배율을 1.0 으로 묶는다(bottom_navigation_bar.dart:763–766).
//   이 위젯은 실제 TextScaler 를 그대로 받고, 라벨이 길면 줄바꿈해 높이를 늘린다(고정 높이·말줄임·축소 없음).
// [CP02 C1] 비선택 아이콘·라벨 = textPrimary(시안 실측 진한 중립), 칸 안 수평 여백 6(큰 글자에서 이웃 라벨 분리),
//   라벨 줄은 공백에서만 바뀐다(표시값만 TextLayout.keepWords 의 U+2060, 의미 이름·items 원문은 그대로).
// [CP02 C2] 탭 내용은 위쪽 정렬 — 라벨 줄 수가 달라도 아이콘이 한 줄에 놓인다(가장 높은 탭이 행 높이를 정한다).
import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../utils/text_layout.dart';

class AppBottomTabBar extends StatelessWidget {
  const AppBottomTabBar({
    super.key,
    required this.items,
    required this.currentIndex,
    required this.onTap,
  });

  /// 보이는 탭만, 보이는 순서대로. `icon`(비선택)·`activeIcon`(선택)·`label` 을 쓴다.
  final List<BottomNavigationBarItem> items;

  /// 보이는 목록 안의 현재 위치.
  final int currentIndex;

  /// 보이는 목록 안의 위치로 부른다.
  final ValueChanged<int> onTap;

  static const double minContentHeight = 56;
  static const double iconSize = 24;

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    return Material(
      color: AppColors.surface,
      elevation: 0,
      child: DecoratedBox(
        // 위 경계선 1 physical px
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: AppColors.conceptTabLine, width: 1 / dpr)),
        ),
        // 선은 자기 높이(1/DPR)를 가진다 — 높이 = 선 + 내용 + 아래 inset.
        child: Padding(
          padding: EdgeInsets.only(top: 1 / dpr),
          // 아래 시스템 영역(inset)은 여기서 한 번만 비운다.
          child: SafeArea(
            top: false,
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < items.length; i++)
                    Expanded(child: _tab(context, i)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _tab(BuildContext context, int i) {
    final item = items[i];
    final selected = i == currentIndex;
    final label = item.label ?? '';
    // 탭마다 의미 노드 1개 — 이름은 라벨 1개(아이콘 의미 제외), 선택 1개.
    return Semantics(
      container: true,
      button: true,
      selected: selected,
      child: InkWell(
        onTap: () => onTap(i),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: minContentHeight, minWidth: 48),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 6),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.start,
              children: [
                IconTheme(
                  data: IconThemeData(
                    size: iconSize,
                    color: selected ? AppColors.brand : AppColors.textPrimary,
                  ),
                  child: ExcludeSemantics(child: selected ? item.activeIcon : item.icon),
                ),
                const SizedBox(height: 4),
                Text(
                  TextLayout.keepWords(label),
                  semanticsLabel: label,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.2,
                    letterSpacing: 0,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    color: selected ? AppColors.brandDark : AppColors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
