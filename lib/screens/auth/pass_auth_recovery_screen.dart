import 'package:flutter/material.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:provider/provider.dart';

import '../../providers/user_provider.dart';
import '../../services/pass_verification_service.dart';
import '../../theme/app_colors.dart';
import '../../utils/responsive_helper.dart';
import '../../utils/toast_helper.dart';
import '../../widgets/auth/pass_auth_button.dart';
import '../../widgets/auth/pass_result_display.dart';

/// 본인인증 복구 화면
///
/// needsPassAuthRecovery == true인 USER에게 홈 배너 → 진입.
/// 기존 PassVerificationService.authenticate()를 재사용해
/// PASS 인증을 완료한 뒤 finalizePassReauth CF로 passVerifiedAt 저장.
/// 성공 시 UserProvider.refreshCurrentUser() → pop.
class PassAuthRecoveryScreen extends StatefulWidget {
  const PassAuthRecoveryScreen({super.key});

  @override
  State<PassAuthRecoveryScreen> createState() => _PassAuthRecoveryScreenState();
}

class _PassAuthRecoveryScreenState extends State<PassAuthRecoveryScreen> {
  PassAuthResult? _authResult;
  bool _isPassLoading = false;
  bool _isFinalizing = false;

  Future<void> _handlePassAuth() async {
    if (_isPassLoading) return;
    setState(() => _isPassLoading = true);
    try {
      final result = await PassVerificationService.authenticate(
        purpose: 'reauth',
      );
      if (!mounted) return;
      if (result != null) {
        setState(() => _authResult = result);
      } else {
        // 취소 또는 실패 — 이전 결과 초기화
        setState(() => _authResult = null);
      }
    } catch (e) {
      debugPrint('[PassAuthRecovery] authenticate 예외: $e');
      if (mounted) ToastHelper.showError('본인인증 중 오류가 발생했습니다');
    } finally {
      if (mounted) setState(() => _isPassLoading = false);
    }
  }

  Future<void> _handleFinalize() async {
    final result = _authResult;
    if (result == null || _isFinalizing) return;

    // async gap 전 context 의존 객체 미리 획득
    final userProvider = context.read<UserProvider>();
    final nav = Navigator.of(context);

    setState(() => _isFinalizing = true);
    try {
      await PassVerificationService.finalizePassReauth(result.passToken);
      // 인증 완료 — 사용자 정보 갱신 후 화면 복귀
      await userProvider.refreshCurrentUser();
      if (!mounted) return;
      ToastHelper.showSuccess('본인인증이 완료되었습니다');
      nav.pop();
    } on FirebaseFunctionsException catch (e) {
      debugPrint('[PassAuthRecovery] finalizePassReauth CF 오류: ${e.code} ${e.message}');
      if (!mounted) return;
      final msg = switch (e.code) {
        'not-found' => '인증 세션이 만료되었습니다. 본인인증을 다시 진행해주세요.',
        'deadline-exceeded' => '인증 토큰이 만료되었습니다. 본인인증을 다시 진행해주세요.',
        'permission-denied' => '본인 계정의 CI 정보와 일치하지 않습니다.',
        _ => '인증 완료 처리 중 오류가 발생했습니다. 다시 시도해주세요.',
      };
      ToastHelper.showError(msg);
      // 세션 만료 시 이전 결과 초기화 → 재인증 유도
      if (e.code == 'not-found' || e.code == 'deadline-exceeded') {
        setState(() => _authResult = null);
      }
    } catch (e) {
      debugPrint('[PassAuthRecovery] finalizePassReauth 예외: $e');
      if (mounted) ToastHelper.showError('인증 완료 처리 중 오류가 발생했습니다');
    } finally {
      if (mounted) setState(() => _isFinalizing = false);
    }
  }

  double _sp(BuildContext context, double sz) =>
      ResponsiveHelper.spacing(context, sz);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('본인인증'),
        elevation: 0,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.symmetric(
              horizontal: _sp(context, 24), vertical: _sp(context, 32)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 안내 아이콘
              Center(
                child: Container(
                  width: _sp(context, 80),
                  height: _sp(context, 80),
                  decoration: BoxDecoration(
                    color: AppColors.warning.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.verified_user_outlined,
                    size: _sp(context, 40),
                    color: AppColors.warning,
                  ),
                ),
              ),

              SizedBox(height: _sp(context, 24)),

              // 제목
              Text(
                '휴대폰 본인인증이 필요합니다',
                style: ResponsiveHelper.titleStyle(context,
                    fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),

              SizedBox(height: _sp(context, 12)),

              // 설명
              Text(
                '공고 지원 및 서비스 이용을 위해\n휴대폰 본인인증을 완료해주세요.\n\n인증 후 별도 가입 없이 기존 계정이 유지됩니다.',
                style: ResponsiveHelper.bodyStyle(context)
                    .copyWith(color: AppColors.grey600),
                textAlign: TextAlign.center,
              ),

              SizedBox(height: _sp(context, 40)),

              // PASS 인증 버튼
              PassAuthButton(
                onPressed: _handlePassAuth,
                isLoading: _isPassLoading,
                isCompleted: _authResult != null,
              ),

              // 인증 결과 표시
              if (_authResult != null) ...[
                SizedBox(height: _sp(context, 16)),
                PassResultDisplay(result: _authResult!),

                SizedBox(height: _sp(context, 24)),

                // 완료 버튼
                FilledButton(
                  onPressed: _isFinalizing ? null : _handleFinalize,
                  style: FilledButton.styleFrom(
                    backgroundColor: theme.primaryColor,
                    padding: EdgeInsets.symmetric(vertical: _sp(context, 16)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: _isFinalizing
                      ? SizedBox(
                          width: _sp(context, 20),
                          height: _sp(context, 20),
                          child: const CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : Text(
                          '인증 완료',
                          style: ResponsiveHelper.bodyStyle(context).copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                ),
              ],

              SizedBox(height: _sp(context, 16)),

              // 취소/나중에 버튼 (사용자가 원할 경우 나갈 수 있음)
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(
                  '나중에 하기',
                  style: ResponsiveHelper.bodyStyle(context)
                      .copyWith(color: AppColors.grey600),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
