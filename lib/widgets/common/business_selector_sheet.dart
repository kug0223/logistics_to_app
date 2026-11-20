// lib/widgets/common/business_selector_sheet.dart
//
// 공유 사업장 선택 바텀시트 — SUB_ADMIN 멀티 사업장 전환 전용
//
// 사용 패턴:
//   final selected = await DialogHelper.showSheet<String>(
//     context,
//     builder: (ctx) => BusinessSelectorSheet(
//       businessIds: bizIds,
//       businessNames: up.subAdminBusinessNames,
//       selectedBusinessId: up.effectiveBusinessId,
//     ),
//   );

import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../utils/responsive_helper.dart';
import '../../utils/text_layout.dart';

class BusinessSelectorSheet extends StatelessWidget {
  final List<String> businessIds;
  final Map<String, String> businessNames;
  // 현재 선택된 사업장 — 체크 아이콘 표시용
  final String? selectedBusinessId;

  const BusinessSelectorSheet({
    super.key,
    required this.businessIds,
    required this.businessNames,
    this.selectedBusinessId,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(
            ResponsiveHelper.spacing(context, 20),
            ResponsiveHelper.spacing(context, 20),
            ResponsiveHelper.spacing(context, 20),
            ResponsiveHelper.spacing(context, 8),
          ),
          child: Text(
            '사업장 선택',
            style: ResponsiveHelper.subtitleStyle(context)
                .copyWith(fontWeight: FontWeight.bold),
          ),
        ),
        // [DU297 BS1] 사업장 목록만 스크롤한다(제목 고정).
        //   이전: 스크롤 없음 — B320 2.0 사업장 5개에서 아래 168px 넘침, 마지막 사업장에 닿지 못했다.
        Flexible(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ...businessIds.map((id) {
                  final name = businessNames[id] ?? id;
                  final isSelected = id == selectedBusinessId;
                  return ListTile(
                    leading: SizedBox(
                      width: 20,
                      child: isSelected
                          ? Icon(Icons.check_rounded,
                              color: theme.primaryColor, size: 20)
                          : null,
                    ),
                    // [DU297 BS2] 사업장 이름은 낱말 단위(identity), 읽기 이름 원문
                    title: Text(
                      TextLayout.identity(name),
                      semanticsLabel: name,
                      style: ResponsiveHelper.bodyStyle(context).copyWith(
                        color: isSelected
                            ? theme.primaryColor
                            : AppColors.textPrimary,
                        fontWeight:
                            isSelected ? FontWeight.w600 : FontWeight.normal,
                      ),
                    ),
                    onTap: () => Navigator.pop(context, id),
                  );
                }),
                SizedBox(height: ResponsiveHelper.spacing(context, 8)),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
