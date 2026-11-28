// lib/screens/auth/signup/signup_consent_step.dart
//
// [ALFIT-AUTH-KAKAO-ONBOARDING.1 · §2.2 Consent · C277-01] 필수 동의 — 서버 시행본 그대로.
//   그리기는 공용 LegalConsentList(본문 열람 → 체크 · 열람 ≠ 동의). 판정은 공용 termsSubmitBlockReason.
//   '전체 동의' 는 기존 가입 화면과 같다 — 아직 동의하지 않은 항목의 본문을 차례로 열고, 뷰어에서
//   '동의하고 닫기' 를 누른 항목만 체크한다(열람 ≠ 동의 · 거절한 항목은 그대로 둔다).

import 'package:flutter/material.dart';

import '../../../theme/app_colors.dart';
import '../../../utils/responsive_helper.dart';
import '../../../utils/text_layout.dart';
import '../../../widgets/auth/legal_consent_list.dart';
import '../../../widgets/auth/terms_viewer_screen.dart';
import 'signup_flow_controller.dart';
import 'signup_flow_screen.dart';

class SignupConsentStep extends StatelessWidget {
  const SignupConsentStep({super.key, required this.controller});

  final SignupFlowController controller;

  Future<void> _agreeAllWithViewing(BuildContext context) async {
    final c = controller;
    for (final item in c.unagreedItems) {
      final agreed = await Navigator.push<bool>(
        context,
        MaterialPageRoute(builder: (_) => TermsViewerScreen(item: item)),
      );
      if (!context.mounted) return;
      c.markViewed(item.id);
      if (agreed == true) c.setChoice(item.id, true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final terms = c.terms;
    final children = <Widget>[];
    if (c.termsLoading) {
      children.add(const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: CircularProgressIndicator()),
      ));
    } else if (c.termsError != null || terms == null) {
      children.addAll([
        SignupNote(tone: SignupNoteTone.caution, text: c.termsError ?? '약관을 불러오지 못했어요.'),
        SizedBox(height: ResponsiveHelper.spacing(context, 8)),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: c.loadTerms,
            style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
            child: const Text('다시 불러오기'),
          ),
        ),
      ]);
    } else {
      final items = terms.activeItems;
      final allOn = items.isNotEmpty && items.every((i) => c.choices[i.id] == true);
      children.addAll([
        Container(
          decoration: BoxDecoration(
            color: allOn ? AppColors.brandSurface : AppColors.grey50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: allOn ? AppColors.brand : AppColors.borderLight),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: c.busy ? null : (allOn ? c.clearAll : () => _agreeAllWithViewing(context)),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 56),
              child: Row(
                children: [
                  Checkbox(
                    value: allOn,
                    onChanged: c.busy
                        ? null
                        : (v) => (v ?? false) ? _agreeAllWithViewing(context) : c.clearAll(),
                  ),
                  Expanded(
                    child: Text(
                      TextLayout.keepWords('약관 전체 동의'),
                      semanticsLabel: '약관 전체 동의',
                      style: ResponsiveHelper.bodyStyle(context,
                          color: AppColors.textPrimary, fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        SizedBox(height: ResponsiveHelper.spacing(context, 8)),
        LegalConsentList(
          items: items,
          stored: const {},
          choices: c.choices,
          viewed: c.viewed,
          enabled: !c.busy,
          onChanged: c.setChoice,
          onViewed: c.markViewed,
        ),
      ]);
      if (terms.upcoming.isNotEmpty) {
        children.addAll([
          SizedBox(height: ResponsiveHelper.spacing(context, 8)),
          const SignupNote(
            tone: SignupNoteTone.neutral,
            text: '곧 바뀌는 약관이 있어요. 시행일이 되면 다시 안내해 드려요.',
          ),
        ]);
      }
    }
    if (c.message != null) {
      children.addAll([
        SizedBox(height: ResponsiveHelper.spacing(context, 12)),
        SignupNote(tone: SignupNoteTone.caution, text: c.message!),
      ]);
    }
    return SignupStepScaffold(
      title: '서비스 이용 약관에 동의해 주세요',
      description: '필수 약관에 동의해야 가입할 수 있어요. 선택 약관은 동의하지 않아도 돼요.',
      children: children,
    );
  }
}
