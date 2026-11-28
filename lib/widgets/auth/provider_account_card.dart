// lib/widgets/auth/provider_account_card.dart
//
// [ALFIT-AUTH-KAKAO-ONBOARDING.1 · §2.7 · §4.3] 카카오로 만든 계정의 '보안' 칸.
//
//   카카오 계정에는 비밀번호가 없다 — 비밀번호 변경 칸 대신 연결된 로그인 수단을 보인다.
//   '다른 역할 추가' 는 같은 사람이 반대 역할 계정을 하나 더 만드는 길이다(역할별 최대 1 · 새 본인확인).
//   서버(callableSignupSessionStartAddRole)가 세션을 열고 역할을 고정한다 → 가입 마법사(동의부터).
//   완료되면 새 UID 로 옮긴다(기존 로그아웃 경로로 이전 UID 정리 뒤 로그인 · UID 전환 격리).

import 'package:flutter/material.dart';

import '../../models/core/user_model.dart';
import '../../screens/auth/signup/signup_flow_screen.dart';
import '../../services/auth/signup_api.dart';
import '../../theme/app_colors.dart';
import '../../utils/responsive_helper.dart';
import '../../utils/text_layout.dart';
import '../../widgets/common/common_widgets.dart';

class ProviderAccountCard extends StatefulWidget {
  const ProviderAccountCard({super.key, required this.user, this.api});

  final UserModel user;
  final SignupApi? api;

  @override
  State<ProviderAccountCard> createState() => _ProviderAccountCardState();
}

class _ProviderAccountCardState extends State<ProviderAccountCard> {
  bool _busy = false;
  String? _message;

  String get _otherRole => widget.user.isBusinessAdmin ? 'USER' : 'BUSINESS_ADMIN';

  Future<void> _addRole() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    final api = widget.api ?? FirebaseSignupApi();
    try {
      final session = await api.startAddRole(role: _otherRole);
      if (!mounted) return;
      await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => SignupFlowScreen(session: session, api: api),
      ));
    } on SignupApiException catch (e) {
      if (mounted) setState(() => _message = e.userMessage);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final otherLabel = _otherRole == 'USER' ? '근무자 계정 추가' : '사업주 계정 추가';
    return Container(
      decoration: CommonWidgets.compactCardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _row(
            icon: Icons.chat_bubble_outline,
            title: '카카오로 로그인해요',
            subtitle: '이 계정은 비밀번호 없이 카카오로 로그인해요',
          ),
          const Divider(height: 1, color: AppColors.borderLight),
          InkWell(
            onTap: _busy ? null : _addRole,
            child: _row(
              icon: Icons.person_add_alt_1_outlined,
              title: otherLabel,
              subtitle: '같은 카카오로 다른 역할 계정을 하나 더 만들어요. 본인확인을 한 번 더 해요.',
              trailing: _busy
                  ? const SizedBox(
                      width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : Icon(Icons.chevron_right,
                      size: ResponsiveHelper.iconSize(context, 18), color: AppColors.grey600),
            ),
          ),
          if (_message != null)
            Padding(
              padding: EdgeInsets.fromLTRB(
                ResponsiveHelper.spacing(context, 16),
                0,
                ResponsiveHelper.spacing(context, 16),
                ResponsiveHelper.spacing(context, 12),
              ),
              child: Text(
                TextLayout.keepWords(_message!),
                semanticsLabel: _message,
                style: ResponsiveHelper.smallStyle(context, color: AppColors.warningInk),
              ),
            ),
        ],
      ),
    );
  }

  Widget _row({
    required IconData icon,
    required String title,
    required String subtitle,
    Widget? trailing,
  }) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 56),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: ResponsiveHelper.spacing(context, 16),
          vertical: ResponsiveHelper.spacing(context, 14),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: ResponsiveHelper.spacing(context, 34),
              height: ResponsiveHelper.spacing(context, 34),
              decoration: BoxDecoration(
                color: AppColors.brandSurface,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: AppColors.brand, size: ResponsiveHelper.iconSize(context, 18)),
            ),
            SizedBox(width: ResponsiveHelper.spacing(context, 12)),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    TextLayout.keepWords(title),
                    semanticsLabel: title,
                    style: ResponsiveHelper.bodyStyle(context, fontWeight: FontWeight.w600),
                  ),
                  SizedBox(height: ResponsiveHelper.spacing(context, 2)),
                  Text(
                    TextLayout.keepWords(subtitle),
                    semanticsLabel: subtitle,
                    style: ResponsiveHelper.smallStyle(context, color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
            if (trailing != null) ...[
              SizedBox(width: ResponsiveHelper.spacing(context, 8)),
              trailing,
            ],
          ],
        ),
      ),
    );
  }
}
