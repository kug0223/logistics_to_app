// lib/screens/auth/signup/signup_identity_step.dart
//
// [ALFIT-AUTH-KAKAO-ONBOARDING.1 · §2.3 · §4.3] 휴대폰 본인확인(KG이니시스 통합인증 · PortOne V1).
//   네 상태를 다르게 말한다: 취소(중립) · 실패(주의) · 서버 확인 중(진행) · 마침(성공).
//   창이 돌아온 것만으로 마쳤다고 하지 않는다 — 서버(verifyPassAuth)가 확인해야 '마쳤어요'.
//   표현: '본인확인' — '인증 완료/검증 완료/진위/취업자격' 같은 말은 쓰지 않는다.

import 'package:flutter/material.dart';

import '../../../services/auth/signup_api.dart';
import '../../../theme/app_colors.dart';
import '../../../utils/responsive_helper.dart';
import '../../../utils/text_layout.dart';
import '../../../widgets/common/common_widgets.dart';
import 'signup_flow_controller.dart';
import 'signup_flow_screen.dart';

class SignupIdentityStep extends StatelessWidget {
  const SignupIdentityStep({super.key, required this.controller});

  final SignupFlowController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final roleLabel = SignupCopy.roleLabel(c.session.role ?? c.selectedRole);
    final children = <Widget>[
      _roleRow(context, roleLabel),
      SizedBox(height: ResponsiveHelper.spacing(context, 16)),
    ];
    switch (c.kgPhase) {
      case KgPhase.idle:
        children.add(const SignupNote(
          tone: SignupNoteTone.neutral,
          // [app_impl_9 · 인증 문구 2026-11-26] 수단은 휴대폰 문자 인증이 아니라 간편인증(인증서 앱) — 수단을 단정하지 않는다.
          text: '간편인증으로 본인 명의를 확인해요. 확인한 정보로 계정을 만들어요.',
        ));
        break;
      case KgPhase.inWindow:
        children.add(const SignupNote(
          tone: SignupNoteTone.progress,
          text: '본인확인 창에서 진행해 주세요.',
        ));
        break;
      case KgPhase.canceled:
        children.add(const SignupNote(
          tone: SignupNoteTone.neutral,
          title: '본인확인을 취소했어요',
          text: '준비되면 다시 시도할 수 있어요. 지금까지 고른 내용은 그대로 있어요.',
        ));
        break;
      case KgPhase.failed:
        children.add(SignupNote(
          tone: SignupNoteTone.caution,
          title: '본인확인을 마치지 못했어요',
          text: c.message ?? '잠시 후 다시 시도해 주세요.',
        ));
        break;
      case KgPhase.verifying:
        children.add(const SignupNote(
          tone: SignupNoteTone.progress,
          title: '확인 결과를 받고 있어요',
          text: '잠시만 기다려 주세요. 창을 닫지 마세요.',
        ));
        break;
      case KgPhase.verified:
        children.add(const SignupNote(
          tone: SignupNoteTone.success,
          title: '본인확인을 마쳤어요',
          text: '아래 정보로 가입해요. 가입을 마치면 바로 시작할 수 있어요.',
        ));
        final v = c.verification;
        if (v != null && (v.name != null || v.birthDate != null || v.phoneMasked != null)) {
          children.addAll([
            SizedBox(height: ResponsiveHelper.spacing(context, 12)),
            _resultCard(context, v),
          ]);
        }
        if (v?.roleLikelyTaken == true) {
          children.addAll([
            SizedBox(height: ResponsiveHelper.spacing(context, 12)),
            const SignupNote(
              tone: SignupNoteTone.neutral,
              text: '같은 정보로 가입한 계정이 있을 수 있어요. 가입을 마칠 때 한 번 더 확인해요.',
            ),
          ]);
        }
        if (c.message != null) {
          children.addAll([
            SizedBox(height: ResponsiveHelper.spacing(context, 12)),
            SignupNote(tone: SignupNoteTone.caution, text: c.message!),
          ]);
        }
        break;
    }
    return SignupStepScaffold(
      title: '본인확인',
      description: '안전한 근무 약속을 위해 가입할 때 한 번 본인확인을 해요.',
      children: children,
    );
  }

  Widget _roleRow(BuildContext context, String roleLabel) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 14),
        vertical: ResponsiveHelper.spacing(context, 12),
      ),
      decoration: CommonWidgets.compactCardDecoration(),
      child: Row(
        children: [
          const Icon(Icons.badge_outlined, size: 20, color: AppColors.textSecondary),
          SizedBox(width: ResponsiveHelper.spacing(context, 10)),
          Expanded(
            child: Text(
              TextLayout.keepWords('가입할 계정 · $roleLabel'),
              semanticsLabel: '가입할 계정 $roleLabel',
              style: ResponsiveHelper.bodyStyle(context, color: AppColors.textPrimary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _resultCard(BuildContext context, PassSignupVerification v) {
    Widget row(String k, String? val) => val == null
        ? const SizedBox.shrink()
        : Padding(
            padding: EdgeInsets.symmetric(vertical: ResponsiveHelper.spacing(context, 4)),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: ResponsiveHelper.spacing(context, 76),
                  child: Text(k,
                      style: ResponsiveHelper.smallStyle(context, color: AppColors.textSecondary)),
                ),
                Expanded(
                  child: Text(
                    val,
                    style: ResponsiveHelper.bodyStyle(context, color: AppColors.textPrimary),
                  ),
                ),
              ],
            ),
          );
    return Container(
      padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 14)),
      decoration: CommonWidgets.compactCardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          row('이름', v.name),
          row('생년월일', _birth(v.birthDate)),
          row('휴대폰', v.phoneMasked),
        ],
      ),
    );
  }

  static String? _birth(String? yyyymmdd) {
    if (yyyymmdd == null || yyyymmdd.length < 8) return yyyymmdd;
    return '${yyyymmdd.substring(0, 4)}년 ${int.tryParse(yyyymmdd.substring(4, 6)) ?? ''}월 '
        '${int.tryParse(yyyymmdd.substring(6, 8)) ?? ''}일';
  }
}
