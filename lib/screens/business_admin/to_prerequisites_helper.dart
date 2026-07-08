import 'package:flutter/material.dart';

import '../../models/core/business_model.dart';
import '../../theme/app_colors.dart';
import '../../widgets/dialogs/styled_dialog.dart';
import '../common/settings_screen.dart';
import 'business_list_screen.dart';
import 'work_type_management_screen.dart';

/// TO 등록 전 요구사항(사업장/업무종류/사업주날인/사업자등록증) 체크 후 안내 다이얼로그 표시.
///
/// 모든 조건 충족 시 true 반환.
/// 미충족 항목이 있으면 다이얼로그를 띄우고 false 반환.
/// [hasApprovedBusiness] 승인된 사업장이 있는지 — 사업장 목록에서 진입 시 true 고정.
/// [hasWorkTypes] 해당 사업장에 등록된 업무 종류가 있는지.
/// [hasSeal] 사업주 날인(서명/도장)이 등록되어 있는지.
/// [approvedBusiness] 업무관리로 이동할 때 사용할 사업장 정보 (없으면 설정으로 이동).
Future<bool> checkTOPrerequisites(
  BuildContext context, {
  required bool hasApprovedBusiness,
  required bool hasWorkTypes,
  required bool hasSeal,
  required bool hasLicense,
  BusinessModel? approvedBusiness,
}) async {
  final missing = <String>[];
  if (!hasApprovedBusiness) missing.add('사업장 등록');
  if (!hasWorkTypes) missing.add('업무 종류 등록');
  if (!hasSeal) missing.add('사업주 날인 등록');
  if (!hasLicense) missing.add('사업자등록증 등록');
  if (missing.isEmpty) return true;

  final needsBusiness = !hasApprovedBusiness;
  final needsWorkTypes = !needsBusiness && !hasWorkTypes;

  final buttonText = needsBusiness
      ? '사업장 등록하러 가기'
      : needsWorkTypes
          ? '업무관리로 이동'
          : '설정으로 이동';

  final infoText = needsBusiness
      ? '사업장을 먼저 등록한 후 공고를 작성해주세요.'
      : needsWorkTypes
          ? '업무 종류를 먼저 등록해주세요.'
          : '설정 화면에서 완료 후 다시 시도해주세요.';

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
          StyledDialogInfoCard.info(infoText),
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
    if (needsBusiness) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const BusinessListScreen()),
      );
    } else if (needsWorkTypes && approvedBusiness != null) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => WorkTypeManagementScreen(
            businessId: approvedBusiness.id,
            businessName: approvedBusiness.name,
          ),
        ),
      );
    } else {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const SettingsScreen()),
      );
    }
  }
  return false;
}
