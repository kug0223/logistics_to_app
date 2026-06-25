import 'package:flutter/material.dart';

import '../../models/core/user_model.dart';
import '../../theme/app_colors.dart';
import '../../widgets/dialogs/styled_dialog.dart';
import '../common/document_management_screen.dart';
import '../common/settings_screen.dart';

/// 지원 전 필수 서류·인증 체크 후 안내 다이얼로그 표시.
///
/// 모든 조건 충족 시 true 반환.
/// 미충족 항목이 있으면 다이얼로그를 표시하고 false 반환.
/// [isFlexType] 단기(flex) 공고 여부 — 신분증 인증 필수 여부 결정.
Future<bool> checkApplyPrerequisites(
  BuildContext context, {
  required UserModel user,
  required bool isFlexType,
}) async {
  final missing = <String>[];

  // 1. 본인인증 (PASS) — 이메일 인증 없음
  final passVerified =
      user.ci != null && user.ci!.isNotEmpty && user.passVerifiedAt != null;
  if (!passVerified) missing.add('본인인증(PASS)');

  // 2. 신분증 등록
  if (user.idCardImageUrl == null || user.idCardImageUrl!.isEmpty) {
    missing.add('신분증 등록');
  }

  // 3. 신분증 인증 — 단기(flex) 공고만 필수
  if (isFlexType && !user.isIdVerified) {
    missing.add('신분증 인증');
  }

  // 4. 계좌 정보
  if (user.bankName == null || user.bankName!.isEmpty ||
      user.accountNumber == null || user.accountNumber!.isEmpty) {
    missing.add('계좌 정보 등록');
  }

  // 5. 통장사본
  if (user.bankbookImageUrl == null || user.bankbookImageUrl!.isEmpty) {
    missing.add('통장사본 등록');
  }

  if (missing.isEmpty) return true;

  // PASS 미완료 → 설정(본인인증), 나머지 → 서류 관리 화면으로 이동
  final needsPassAuth = !passVerified;

  final proceed = await showDialog<bool>(
    context: context,
    builder: (ctx) => StyledDialog(
      title: '지원 불가',
      subtitle: '다음 항목을 먼저 완료해주세요',
      icon: Icons.assignment_late_outlined,
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
            needsPassAuth
                ? '설정 > 본인인증에서 PASS 인증 후 다시 시도해주세요.'
                : '설정 > 내 서류 관리에서 완료 후 다시 시도해주세요.',
          ),
        ],
      ),
      actions: [
        StyledDialogButton.cancel(
          onPressed: () => Navigator.pop(ctx, false),
        ),
        StyledDialogButton.primary(
          text: needsPassAuth ? '본인인증 하러 가기' : '서류 관리로 이동',
          onPressed: () => Navigator.pop(ctx, true),
        ),
      ],
    ),
  );

  if (proceed == true && context.mounted) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => needsPassAuth
            ? const SettingsScreen()
            : const DocumentManagementScreen(),
      ),
    );
  }
  return false;
}
