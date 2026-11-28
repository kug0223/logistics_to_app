// lib/widgets/common/id_document_kind_sheet.dart
//
// [ALFIT-AUTH-KAKAO-ONBOARDING.1 · 판정278 §4 · R2-1] 국적 미확정(가입 직후 서류 전) 사용자의 첫 신분 서류 입구.
//
//   기존 서류 등록은 `user.isForeign`(false = 내국인 1~4 규칙)으로 바로 들어갔다. 새 계정은 서류 전이라
//   그 값이 '모름' 인데 false 로 읽히면 외국인등록증의 정상 번호(5~8)가 걸러진다. 그래서 **사용자가 서류
//   종류를 먼저 고른다** — 고른 종류가 정해진 뒤의 번호 규칙 · OCR · 대조는 기존 그대로다.
//   이 선택은 등록할 서류 종류일 뿐 국적 · 진위 · 취업자격 판정이 아니다.

import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../utils/dialog_helper.dart';
import '../../utils/responsive_helper.dart';
import '../../utils/text_layout.dart';
import '../auth/role_choice_card.dart';

/// 'resident'(주민등록증·운전면허증) | 'foreign_registration'(외국인등록증) | null(닫음)
Future<String?> showIdDocumentKindSheet(BuildContext context) => DialogHelper.showSheet<String>(
      context,
      isScrollControlled: true,
      builder: (_) => const IdDocumentKindSheet(),
    );

class IdDocumentKindSheet extends StatelessWidget {
  const IdDocumentKindSheet({super.key});

  /// server_api_1 §6 `documentKind` 값과 같다.
  static const String resident = 'resident_id';
  static const String foreignRegistration = 'foreign_registration';

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        ResponsiveHelper.spacing(context, 20),
        ResponsiveHelper.spacing(context, 20),
        ResponsiveHelper.spacing(context, 20),
        ResponsiveHelper.spacing(context, 24),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            TextLayout.keepWords('어떤 신분증을 등록할까요?'),
            semanticsLabel: '어떤 신분증을 등록할까요?',
            style: ResponsiveHelper.subtitleStyle(context,
                color: AppColors.textPrimary, fontWeight: FontWeight.w700),
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 6)),
          Text(
            TextLayout.keepWords('가지고 있는 신분증을 골라 주세요. 고른 서류에 맞춰 사진을 확인해요.'),
            semanticsLabel: '가지고 있는 신분증을 골라 주세요. 고른 서류에 맞춰 사진을 확인해요.',
            style: ResponsiveHelper.smallStyle(context, color: AppColors.textSecondary),
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 16)),
          RoleChoiceCard(
            icon: Icons.badge_outlined,
            title: '주민등록증 · 운전면허증',
            description: '한국 주민등록번호가 있는 신분증',
            selected: false,
            onTap: () => Navigator.of(context).pop(resident),
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 10)),
          RoleChoiceCard(
            icon: Icons.public,
            title: '외국인등록증',
            description: '외국인등록번호가 있는 등록증',
            selected: false,
            onTap: () => Navigator.of(context).pop(foreignRegistration),
          ),
        ],
      ),
    );
  }
}
