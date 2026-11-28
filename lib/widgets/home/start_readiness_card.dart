// lib/widgets/home/start_readiness_card.dart
//
// [ALFIT-AUTH-KAKAO-ONBOARDING.1 · 대표 결정 2026-11-25] 홈 상단 「시작 준비」 카드 — 가입은 간편하게, 필요한 것은
//   홈에서 단계별로. 항목마다 완료 표시 · 누르면 해당 화면 · **전부 끝나면 카드 자체가 없다**(호출자가 숨김 판단).
//   판정은 하지 않는다 — 호출자가 기존 getter/실제 데이터로 `done` 을 넘긴다(새 판정 로직 0).
//   공통 표면(CommonWidgets.compactCardDecoration) · AppColors · ResponsiveHelper · 낱말 단위 줄바꿈 · 각 줄 최소 56.

import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../utils/responsive_helper.dart';
import '../../utils/text_layout.dart';
import '../common/common_widgets.dart';

class StartReadinessItem {
  const StartReadinessItem({
    required this.icon,
    required this.title,
    this.subtitle,
    required this.done,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final bool done;
  final VoidCallback? onTap;
}

class StartReadinessCard extends StatelessWidget {
  const StartReadinessCard({super.key, required this.items, this.title = '시작 준비'});

  final String title;
  final List<StartReadinessItem> items;

  /// 모두 끝났는가 — 호출자가 카드를 숨길 때 쓴다.
  static bool allDone(List<StartReadinessItem> items) => items.every((i) => i.done);

  @override
  Widget build(BuildContext context) {
    final left = items.where((i) => !i.done).length;
    final remain = '$left개 남았어요';
    return Semantics(
      container: true,
      label: '$title, $remain',
      child: Container(
        decoration: CommonWidgets.compactCardDecoration(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(
                ResponsiveHelper.spacing(context, 14),
                ResponsiveHelper.spacing(context, 12),
                ResponsiveHelper.spacing(context, 14),
                ResponsiveHelper.spacing(context, 8),
              ),
              child: Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: ResponsiveHelper.spacing(context, 8),
                runSpacing: ResponsiveHelper.spacing(context, 2),
                children: [
                  Text(
                    TextLayout.keepWords(title),
                    semanticsLabel: title,
                    style: ResponsiveHelper.bodyStyle(context,
                        color: AppColors.textPrimary, fontWeight: FontWeight.w700),
                  ),
                  Text(
                    TextLayout.keepWords(remain),
                    semanticsLabel: remain,
                    style: ResponsiveHelper.smallStyle(context,
                        color: AppColors.brand, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
            for (final (i, item) in items.indexed) ...[
              if (i > 0) const Divider(height: 1, thickness: 0.5, color: AppColors.borderLight),
              _Row(item: item),
            ],
          ],
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.item});
  final StartReadinessItem item;

  @override
  Widget build(BuildContext context) {
    final done = item.done;
    // [판정284 C284-02] 부모가 자식 의미를 덮으므로(excludeSemantics) 같은 콜백을 부모 접근성 tap action 에도 연결한다 —
    //   화면 읽기 사용자가 행을 두 번 탭해도 일반 터치와 같은 목적지로 간다.
    return Semantics(
      button: item.onTap != null,
      label: '${item.title}${done ? ', 완료' : ''}',
      excludeSemantics: true,
      onTap: item.onTap,
      child: InkWell(
        onTap: item.onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: ResponsiveHelper.spacing(context, 14),
              vertical: ResponsiveHelper.spacing(context, 10),
            ),
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: done ? AppColors.successBg : AppColors.brandSurface,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(done ? Icons.check_rounded : item.icon,
                      size: 18, color: done ? AppColors.successDark : AppColors.brand),
                ),
                SizedBox(width: ResponsiveHelper.spacing(context, 12)),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        TextLayout.keepWords(item.title),
                        style: ResponsiveHelper.bodyStyle(context,
                            color: done ? AppColors.textSecondary : AppColors.textPrimary,
                            fontWeight: done ? FontWeight.w500 : FontWeight.w600),
                      ),
                      if (item.subtitle != null && !done) ...[
                        SizedBox(height: ResponsiveHelper.spacing(context, 2)),
                        Text(
                          TextLayout.keepWords(item.subtitle!),
                          style: ResponsiveHelper.smallStyle(context, color: AppColors.textSecondary),
                        ),
                      ],
                    ],
                  ),
                ),
                SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                if (done)
                  Text('완료',
                      style: ResponsiveHelper.smallStyle(context,
                          color: AppColors.successDark, fontWeight: FontWeight.w600))
                else
                  // [대표 결정 2026-11-26 조화] 관리자 홈 「처리할 일」 행 꺾쇠와 같은 값(conceptChevron · 18).
                  const Icon(Icons.chevron_right, size: 18, color: AppColors.conceptChevron),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
