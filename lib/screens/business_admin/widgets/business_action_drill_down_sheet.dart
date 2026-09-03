// lib/screens/business_admin/widgets/business_action_drill_down_sheet.dart
// ADMIN REDESIGN — PHASE 2C
// 공통 사업장 Action Drill-Down 바텀시트
//
// 사용 방법:
//   final bizId = await BusinessActionDrillDownSheet.show(
//     context,
//     title: '계약 미발송',
//     totalCount: 12,
//     items: [BizDrillDownItem(...)],
//   );
//   if (bizId == null || !mounted) return;
//   // bizId 로 해당 사업장 화면 진입
//
// 설계 원칙:
//   - DialogHelper.showSheet() 사용 (useSafeArea:true, 모서리 radius 20 보장)
//   - 사업장 수 제한 없음 — scrollable
//   - 0건 사업장은 표시하지 않음 (caller 책임)
//   - orange/green gradient Dialog 사용 금지 — white-base

import 'package:flutter/material.dart';

import '../../../theme/app_colors.dart';
import '../../../utils/dialog_helper.dart';
import '../../../utils/responsive_helper.dart';

// ─── 데이터 모델 ──────────────────────────────────────────────────────────────

class BizDrillDownItem {
  final String businessId;
  final String businessName;
  final int count;
  final int? secondaryCount;     // e.g. missingDueDateCount
  final String? secondaryLabel;  // e.g. '지급일 확인 필요'

  const BizDrillDownItem({
    required this.businessId,
    required this.businessName,
    required this.count,
    this.secondaryCount,
    this.secondaryLabel,
  });
}

// ─── 바텀시트 ─────────────────────────────────────────────────────────────────

class BusinessActionDrillDownSheet extends StatelessWidget {
  final String title;
  final int totalCount;
  final List<BizDrillDownItem> items;

  const BusinessActionDrillDownSheet._({
    required this.title,
    required this.totalCount,
    required this.items,
  });

  /// 사업장 선택 후 businessId 반환. 취소 / 닫기 시 null.
  static Future<String?> show(
    BuildContext context, {
    required String title,
    required int totalCount,
    required List<BizDrillDownItem> items,
  }) {
    return DialogHelper.showSheet<String>(
      context,
      isScrollControlled: true,
      builder: (_) => BusinessActionDrillDownSheet._(
        title:      title,
        totalCount: totalCount,
        items:      items,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: _initialSize(items.length),
      minChildSize: 0.3,
      maxChildSize: 0.85,
      expand: false,
      builder: (ctx, scrollController) => Column(
        children: [
          // 핸들
          _buildHandle(),
          // 헤더
          _buildHeader(context),
          const Divider(height: 1, thickness: 1, color: AppColors.borderLight),
          // 사업장 목록
          Expanded(
            child: ListView.separated(
              controller: scrollController,
              itemCount: items.length,
              separatorBuilder: (_, __) =>
                  const Divider(height: 1, thickness: 1, color: AppColors.borderLight),
              itemBuilder: (_, i) => _buildRow(context, items[i]),
            ),
          ),
        ],
      ),
    );
  }

  // ─── 초기 시트 높이 (사업장 수에 따라 조정) ────────────────────────────────

  double _initialSize(int count) {
    if (count <= 2) return 0.40;
    if (count <= 4) return 0.55;
    return 0.70;
  }

  // ─── 핸들 ──────────────────────────────────────────────────────────────────

  Widget _buildHandle() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Container(
        width: 40,
        height: 4,
        decoration: BoxDecoration(
          color: AppColors.grey300,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }

  // ─── 헤더 ──────────────────────────────────────────────────────────────────

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: ResponsiveHelper.titleStyle(
              context, color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            '총 $totalCount건 · ${items.length}개 사업장',
            style: ResponsiveHelper.bodyStyle(
              context, color: AppColors.textTertiary,
            ).copyWith(fontSize: 13),
          ),
        ],
      ),
    );
  }

  // ─── 각 사업장 row ─────────────────────────────────────────────────────────

  Widget _buildRow(BuildContext context, BizDrillDownItem item) {
    return InkWell(
      onTap: () => Navigator.pop(context, item.businessId),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            // 정보 영역
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.businessName,
                    style: ResponsiveHelper.bodyStyle(
                      context,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ).copyWith(fontSize: 15),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Text(
                        '${item.count}건',
                        style: ResponsiveHelper.bodyStyle(
                          context,
                          color: AppColors.brand,
                          fontWeight: FontWeight.w600,
                        ).copyWith(fontSize: 13),
                      ),
                      // secondary: 예) 지급일 확인 필요 2건
                      if (item.secondaryCount != null &&
                          item.secondaryCount! > 0 &&
                          item.secondaryLabel != null) ...[
                        const SizedBox(width: 8),
                        Text(
                          '${item.secondaryLabel} ${item.secondaryCount}건',
                          style: ResponsiveHelper.bodyStyle(
                            context,
                            color: AppColors.textTertiary,
                          ).copyWith(fontSize: 12),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.chevron_right, size: 20, color: AppColors.textHint),
          ],
        ),
      ),
    );
  }
}
