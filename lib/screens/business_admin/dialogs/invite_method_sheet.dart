// [Phase 8.1B.3] 인력 초대 방식 선택 시트
//
// DayApplicantsDialog가 부족한 work-group에서 [인력 초대] 탭 시 표시.
// 두 가지 초대 방식을 제공하며 사용자 선택 결과(String)를 Navigator.pop으로 반환:
//   'availability' → AvailableWorkersBottomSheet
//   'direct'       → InviteWorkerDialog (contextual mode)
// 실제 시트/다이얼로그 열기는 호출부(DayApplicantsDialog)에서 처리.
import 'package:flutter/material.dart';

import '../../../theme/app_colors.dart';
import '../../../utils/format_helper.dart';
import '../../../utils/responsive_helper.dart';

class InviteMethodSheet extends StatelessWidget {
  final String workType;
  final DateTime date;
  final String startTime;
  final String endTime;
  final int shortage;

  const InviteMethodSheet({
    super.key,
    required this.workType,
    required this.date,
    required this.startTime,
    required this.endTime,
    required this.shortage,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = ResponsiveHelper.getScale(context);

    final dateStr = FormatHelper.formatDateShort(date);
    final contextLabel =
        '$workType · $dateStr · $startTime~$endTime · $shortage명 부족';

    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(16 * s, 8 * s, 16 * s, 20 * s),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 드래그 핸들
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: EdgeInsets.only(bottom: 16 * s),
                decoration: BoxDecoration(
                  color: AppColors.grey300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            // 헤더
            Text(
              '인력 초대',
              style: ResponsiveHelper.subtitleStyle(context)
                  .copyWith(fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 4 * s),
            Text(
              contextLabel,
              style: ResponsiveHelper.smallStyle(context,
                  color: AppColors.grey500),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            SizedBox(height: 20 * s),
            // SECTION 1: 근무 가능 인력
            _buildMethodTile(
              context,
              s,
              icon: Icons.person_search_outlined,
              color: AppColors.info,
              title: '근무 가능 인력',
              subtitle:
                  '가능일을 등록한 인력 중 이 업무에 맞는 사람을 찾아요.',
              result: 'availability',
            ),
            SizedBox(height: 10 * s),
            // SECTION 2: 직접 초대
            _buildMethodTile(
              context,
              s,
              icon: Icons.person_add_outlined,
              color: theme.primaryColor,
              title: '직접 초대',
              subtitle:
                  '전화번호를 알고 있는 근로자에게 직접 근무를 제안해요.',
              result: 'direct',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMethodTile(
    BuildContext context,
    double s, {
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required String result,
  }) {
    return InkWell(
      onTap: () => Navigator.pop<String>(context, result),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: EdgeInsets.all(14 * s),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Row(
          children: [
            Container(
              width: 40 * s,
              height: 40 * s,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              alignment: Alignment.center,
              child: Icon(
                icon,
                size: ResponsiveHelper.iconSize(context, 20),
                color: color,
              ),
            ),
            SizedBox(width: 12 * s),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: ResponsiveHelper.bodyStyle(context).copyWith(
                      fontWeight: FontWeight.w600,
                      color: color,
                    ),
                  ),
                  SizedBox(height: 2 * s),
                  Text(
                    subtitle,
                    style: ResponsiveHelper.smallStyle(context,
                        color: AppColors.grey600),
                  ),
                ],
              ),
            ),
            SizedBox(width: 8 * s),
            Icon(
              Icons.chevron_right,
              size: ResponsiveHelper.iconSize(context, 18),
              color: color.withValues(alpha: 0.6),
            ),
          ],
        ),
      ),
    );
  }
}
