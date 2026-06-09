import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../widgets/dialogs/styled_dialog.dart';
import '../common/settings_screen.dart';
import 'business_list_screen.dart';

/// TO 등록 전 요구사항(사업장/이메일/사업자등록증) 체크 후 안내 다이얼로그 표시.
///
/// 모든 조건 충족 시 true 반환.
/// 미충족 항목이 있으면 다이얼로그를 띄우고 false 반환.
/// [hasApprovedBusiness] 승인된 사업장이 있는지 — 사업장 목록에서 진입 시 true 고정.
Future<bool> checkTOPrerequisites(
  BuildContext context, {
  required bool hasApprovedBusiness,
  required bool isEmailVerified,
  required bool hasLicense,
}) async {
  final missing = <String>[];
  if (!hasApprovedBusiness) missing.add('사업장 등록');
  if (!isEmailVerified) missing.add('이메일 인증');
  if (!hasLicense) missing.add('사업자등록증 등록');
  if (missing.isEmpty) return true;

  final needsBusiness = !hasApprovedBusiness;
  final buttonText = needsBusiness ? '사업장 등록하러 가기' : '설정으로 이동';

  final proceed = await showDialog<bool>(
    context: context,
    builder: (ctx) => StyledDialog(
      title: '공고 등록 불가',
      subtitle: '다음 항목을 먼저 완료해주세요',
      icon: Icons.block_outlined,
      headerColor: AppColors.error,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ...missing.map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: StyledDialogInfoCard.error(item),
            ),
          ),
          const SizedBox(height: 4),
          StyledDialogInfoCard.info(
            needsBusiness
                ? '사업장을 먼저 등록한 후 공고를 작성해주세요.'
                : '설정 화면에서 완료 후 다시 시도해주세요.',
          ),
        ],
      ),
      actions: [
        StyledDialogButton.cancel(
          onPressed: () => Navigator.pop(ctx, false),
        ),
        StyledDialogButton.primary(
          text: buttonText,
          onPressed: () => Navigator.pop(ctx, true),
        ),
      ],
    ),
  );

  if (proceed == true && context.mounted) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => needsBusiness
            ? const BusinessListScreen()
            : const SettingsScreen(),
      ),
    );
  }
  return false;
}
