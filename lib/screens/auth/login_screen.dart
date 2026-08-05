import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

// Providers
import '../../providers/user_provider.dart';
import '../../services/analytics_service.dart';

// Utils
import 'package:cloud_functions/cloud_functions.dart';
import '../../utils/dialog_helper.dart';
import '../../utils/responsive_helper.dart';
import '../../utils/toast_helper.dart';

// Widgets
import '../../widgets/common/loading_widget.dart';

// Services
import 'package:firebase_auth/firebase_auth.dart';
import '../../services/auth_service.dart';
import '../../services/pass_verification_service.dart';

// Widgets
import '../../widgets/auth/pass_auth_button.dart';

// Screens
import 'register_screen.dart';
import '../../theme/app_colors.dart';

/// ALfit 로그인 화면 - 포커스 이동 + 아이디/비밀번호 찾기
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;

  final _authService = AuthService();
  final _auth = FirebaseAuth.instance;
  final _fn = FirebaseFunctions.instanceFor(region: 'asia-northeast3');

  final _usernameFocus = FocusNode();
  final _passwordFocus = FocusNode();

  // 아이디찾기/비밀번호찾기 바텀시트용 FocusNode — 화면 lifecycle에서 관리하여
  // addPostFrameCallback dispose가 위젯 deactivate보다 먼저 실행되는 타이밍 크래시 방지
  final _findUsernameNameFocus = FocusNode();
  final _findUsernamePhoneFocus = FocusNode();
  final _findPasswordUsernameFocus = FocusNode();
  final _findPasswordNewPasswordFocus = FocusNode();
  final _findPasswordConfirmPasswordFocus = FocusNode();

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _usernameFocus.dispose();
    _passwordFocus.dispose();
    _findUsernameNameFocus.dispose();
    _findUsernamePhoneFocus.dispose();
    _findPasswordUsernameFocus.dispose();
    _findPasswordNewPasswordFocus.dispose();
    _findPasswordConfirmPasswordFocus.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus(); // 키보드 닫기 → toast가 키보드 뒤에 숨지 않도록

    final userProvider = context.read<UserProvider>();
    if (userProvider.isLoading) return;
    final success = await userProvider.signIn(
      _usernameController.text.trim(),
      _passwordController.text,
    );

    if (!mounted) return;
    if (success) {
      AnalyticsService.logLogin(userProvider.currentUser?.role.name ?? 'UNKNOWN');
    } else {
      // signIn 실패 시 provider의 _error를 toast로 표시
      final err = userProvider.error;
      ToastHelper.showError(
        (err != null && err.isNotEmpty) ? err : '아이디 또는 비밀번호가 올바르지 않습니다.',
      );
    }
  }

  Future<void> _showFindUsernameDialog() async {
    final nameController = TextEditingController();
    final phoneController = TextEditingController();
    final nameFocus = _findUsernameNameFocus;
    final phoneFocus = _findUsernamePhoneFocus;

    String? foundUsername;
    bool isSearching = false;

    try {
    await DialogHelper.showSheet(
      context,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          Future<void> search() async {
            if (nameController.text.isEmpty) {
              ToastHelper.showWarning('이름을 입력해주세요');
              nameFocus.requestFocus();
              return;
            }
            if (phoneController.text.isEmpty) {
              ToastHelper.showWarning('전화번호를 입력해주세요');
              phoneFocus.requestFocus();
              return;
            }
            setSheetState(() => isSearching = true);
            final result = await _authService.findUsername(
              name: nameController.text,
              phone: phoneController.text,
            );
            if (!ctx.mounted) return;
            setSheetState(() {
              isSearching = false;
              foundUsername = result ?? '';
            });
          }

          return Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
            ),
            child: Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
              ),
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(24, 0, 24, 40 + MediaQuery.of(ctx).padding.bottom),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Container(
                        margin: const EdgeInsets.only(top: 12, bottom: 24),
                        width: 40, height: 4,
                        decoration: BoxDecoration(
                          color: AppColors.grey300,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),

                  if (foundUsername == null) ...[
                    Text('아이디 찾기',
                        style: ResponsiveHelper.titleStyle(ctx).copyWith(fontWeight: FontWeight.w700, color: AppColors.grey900)),
                    const SizedBox(height: 6),
                    Text('가입 시 입력한 이름과 전화번호를 입력해주세요',
                        style: ResponsiveHelper.bodyStyle(ctx).copyWith(color: AppColors.grey500)),
                    const SizedBox(height: 24),
                    _buildSheetTextField(
                      context: ctx,
                      controller: nameController,
                      focusNode: nameFocus,
                      label: '이름',
                      hint: '홍길동',
                      icon: Icons.person_outline,
                      onSubmitted: (_) => phoneFocus.requestFocus(),
                    ),
                    const SizedBox(height: 12),
                    _buildSheetTextField(
                      context: ctx,
                      controller: phoneController,
                      focusNode: phoneFocus,
                      label: '전화번호',
                      hint: '01012345678',
                      icon: Icons.phone_outlined,
                      keyboardType: TextInputType.phone,
                      maxLength: 11,
                      onSubmitted: (_) => search(),
                    ),
                    const SizedBox(height: 24),
                    Semantics(
                      enabled: !isSearching,
                      hint: isSearching ? '검색 중입니다' : null,
                      child: ElevatedButton(
                      onPressed: isSearching ? null : search,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Theme.of(ctx).primaryColor,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        elevation: 0,
                      ),
                      child: isSearching
                          ? const SizedBox(width: 20, height: 20,
                              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                          : Text('찾기', style: ResponsiveHelper.subtitleStyle(ctx).copyWith(fontWeight: FontWeight.w600)),
                      ),
                    ), // Semantics

                  ] else if (foundUsername!.isEmpty) ...[
                    const SizedBox(height: 8),
                    Icon(Icons.search_off_rounded, size: ResponsiveHelper.iconSize(context, 60), color: AppColors.grey300),
                    const SizedBox(height: 16),
                    Text('일치하는 계정을 찾을 수 없어요',
                        textAlign: TextAlign.center,
                        style: ResponsiveHelper.subtitleStyle(ctx).copyWith(fontWeight: FontWeight.w700, color: AppColors.grey900)),
                    const SizedBox(height: 8),
                    Text('입력하신 정보를 다시 확인해주세요',
                        textAlign: TextAlign.center,
                        style: ResponsiveHelper.bodyStyle(ctx).copyWith(color: AppColors.grey500)),
                    const SizedBox(height: 28),
                    OutlinedButton(
                      onPressed: () => setSheetState(() => foundUsername = null),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        side: BorderSide(color: Theme.of(ctx).primaryColor),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      child: Text('다시 찾기',
                          style: ResponsiveHelper.subtitleStyle(ctx).copyWith(fontWeight: FontWeight.w600, color: Theme.of(ctx).primaryColor)),
                    ),
                    const SizedBox(height: 8),

                  ] else ...[
                    const SizedBox(height: 8),
                    Icon(Icons.check_circle_rounded, size: 60, color: Theme.of(ctx).primaryColor),
                    const SizedBox(height: 16),
                    Text('아이디를 찾았어요',
                        textAlign: TextAlign.center,
                        style: ResponsiveHelper.subtitleStyle(ctx).copyWith(fontWeight: FontWeight.w700, color: AppColors.grey900)),
                    const SizedBox(height: 20),
                    Container(
                      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 24),
                      decoration: BoxDecoration(
                        color: Theme.of(ctx).primaryColor.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Text(
                        foundUsername!.length > 4
                            ? '${foundUsername!.substring(0, 4)}${'*' * (foundUsername!.length - 4)}'
                            : foundUsername!,
                        textAlign: TextAlign.center,
                        style: ResponsiveHelper.titleStyle(ctx).copyWith(
                          fontWeight: FontWeight.w800,
                          color: Theme.of(ctx).primaryColor,
                          letterSpacing: 2,
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton(
                      onPressed: () => Navigator.pop(sheetContext),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Theme.of(ctx).primaryColor,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        elevation: 0,
                      ),
                      child: Text('확인', style: ResponsiveHelper.subtitleStyle(ctx).copyWith(fontWeight: FontWeight.w600)),
                    ),
                    const SizedBox(height: 8),
                  ],
                ],
                ),
              ),
            ),
          );
        },
      ),
    );
    } finally {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        nameController.dispose();
        phoneController.dispose();
        // FocusNode는 _LoginScreenState.dispose()에서 해제 — 여기서 dispose 금지
      });
    }
  }

  Future<void> _showFindPasswordDialog() async {
    final usernameController = TextEditingController();
    final newPasswordController = TextEditingController();
    final confirmPasswordController = TextEditingController();
    final usernameFocus = _findPasswordUsernameFocus;
    final newPasswordFocus = _findPasswordNewPasswordFocus;
    final confirmPasswordFocus = _findPasswordConfirmPasswordFocus;

    // 0: 아이디 + PASS 인증, 1: 새 비밀번호 입력, 2: 완료
    int step = 0;
    bool isAuthenticating = false;
    bool isChanging = false;
    bool obscureNew = true;
    bool obscureConfirm = true;
    String? customToken;

    // _showFindUsernameDialog와 동일하게 try-finally로 dispose 보장
    try {
    await DialogHelper.showSheet(
      context,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          // PASS 인증 → CF resetPasswordWithPass → customToken 확보 → step 1
          //
          // [운영 전제] 내국인 가입 시 register_screen의 finalizeRegistration()이
          //   passToken → ciHash 를 Firestore 에 저장해야 CI 매칭이 성공한다.
          //
          Future<void> doPassAuth() async {
            if (usernameController.text.trim().isEmpty) {
              ToastHelper.showWarning('아이디를 입력해주세요');
              usernameFocus.requestFocus();
              return;
            }
            setSheetState(() => isAuthenticating = true);
            try {
              final passResult = await PassVerificationService.authenticate(
                purpose: 'resetPassword',
              );
              if (!ctx.mounted) return;
              if (passResult == null) {
                setSheetState(() => isAuthenticating = false);
                return; // 사용자가 인증 취소
              }

              final result = await _fn
                  .httpsCallable(
                    'resetPasswordWithPass',
                    options: HttpsCallableOptions(timeout: const Duration(seconds: 15)),
                  )
                  .call({
                'passToken': passResult.passToken,
                'username': usernameController.text.trim(),
              });
              if (!ctx.mounted) return;
              customToken = result.data['customToken'] as String?;
              setSheetState(() { isAuthenticating = false; step = 1; });
              Future.delayed(const Duration(milliseconds: 300), () {
                if (ctx.mounted) newPasswordFocus.requestFocus();
              });
            } on FirebaseFunctionsException catch (e) {
              if (!ctx.mounted) return;
              setSheetState(() => isAuthenticating = false);
              ToastHelper.showError(e.message ?? '본인인증에 실패했습니다');
            } catch (e) {
              if (!ctx.mounted) return;
              setSheetState(() => isAuthenticating = false);
              ToastHelper.showError('오류가 발생했습니다. 다시 시도해주세요');
            }
          }

          // Custom Token으로 재로그인 → 비밀번호 변경
          Future<void> resetPassword() async {
            final pw = newPasswordController.text;
            final pwRegex = RegExp(r'^(?=.*[a-zA-Z])(?=.*\d)(?=.*[!@#$%^&*(),.?":{}|<>]).{8,}$');
            if (!pwRegex.hasMatch(pw)) {
              ToastHelper.showWarning('비밀번호는 8자 이상이며\n영문·숫자·특수문자를 포함해야 합니다');
              newPasswordFocus.requestFocus();
              return;
            }
            if (pw != confirmPasswordController.text) {
              ToastHelper.showWarning('비밀번호가 일치하지 않습니다');
              confirmPasswordFocus.requestFocus();
              return;
            }
            // customToken은 doPassAuth() 성공 시 설정된다.
            // null이면 사용자가 step 0으로 돌아가 재인증해야 한다.
            if (customToken == null) {
              ToastHelper.showError('인증 세션이 만료되었습니다. 다시 본인인증을 진행해주세요');
              setSheetState(() => step = 0);
              return;
            }
            setSheetState(() => isChanging = true);
            try {
              // Custom Token으로 Firebase 재로그인 → 비밀번호 변경
              final cred = await _auth.signInWithCustomToken(customToken!);
              await cred.user!.updatePassword(pw);
              await _auth.signOut(); // 변경 완료 후 로그아웃 → 새 비밀번호로 재로그인 유도
              if (!ctx.mounted) return;
              setSheetState(() { isChanging = false; step = 2; });
            } catch (e) {
              // 에러 표시를 먼저 — signOut()이 AuthWrapper 전환을 유발해 ctx가
              // unmount된 이후 setSheetState를 호출하면 에러가 날 수 있음.
              if (ctx.mounted) {
                setSheetState(() => isChanging = false);
                ToastHelper.showError('비밀번호 변경에 실패했습니다. 다시 시도해주세요');
              }
              // signInWithCustomToken 세션 정리 — 미정리 시 의도치 않은 로그인 전환.
              await _auth.signOut();
            }
          }

          return Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
            ),
            child: Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
              ),
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(24, 0, 24, 40 + MediaQuery.of(ctx).padding.bottom),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Container(
                        margin: const EdgeInsets.only(top: 12, bottom: 24),
                        width: 40, height: 4,
                        decoration: BoxDecoration(
                          color: AppColors.grey300,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),

                  // ── 완료 화면 ──
                  if (step == 2) ...[
                    const SizedBox(height: 8),
                    Icon(Icons.check_circle_rounded, size: 60, color: Theme.of(ctx).primaryColor),
                    const SizedBox(height: 16),
                    Text('비밀번호가 변경되었어요',
                        textAlign: TextAlign.center,
                        style: ResponsiveHelper.subtitleStyle(ctx).copyWith(fontWeight: FontWeight.w700, color: AppColors.grey900)),
                    const SizedBox(height: 8),
                    Text('새 비밀번호로 로그인해주세요',
                        textAlign: TextAlign.center,
                        style: ResponsiveHelper.bodyStyle(ctx).copyWith(color: AppColors.grey500)),
                    const SizedBox(height: 28),
                    ElevatedButton(
                      onPressed: () => Navigator.pop(sheetContext),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Theme.of(ctx).primaryColor,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        elevation: 0,
                      ),
                      child: Text('로그인하러 가기', style: ResponsiveHelper.subtitleStyle(ctx).copyWith(fontWeight: FontWeight.w600)),
                    ),
                    const SizedBox(height: 8),

                  // ── 새 비밀번호 입력 ──
                  ] else if (step == 1) ...[
                    Text('비밀번호 재설정',
                        style: ResponsiveHelper.titleStyle(ctx).copyWith(fontWeight: FontWeight.w700, color: AppColors.grey900)),
                    const SizedBox(height: 6),
                    Text('새로 사용할 비밀번호를 입력해주세요',
                        style: ResponsiveHelper.bodyStyle(ctx).copyWith(color: AppColors.grey500)),
                    const SizedBox(height: 24),
                    _buildSheetTextField(
                      context: ctx,
                      controller: newPasswordController,
                      focusNode: newPasswordFocus,
                      label: '새 비밀번호',
                      hint: '8자 이상, 영문·숫자·특수문자 포함',
                      icon: Icons.lock_outline,
                      obscureText: obscureNew,
                      suffixWidget: Semantics(
                        button: true,
                        label: obscureNew ? '비밀번호 표시' : '비밀번호 숨김',
                        child: GestureDetector(
                          onTap: () => setSheetState(() => obscureNew = !obscureNew),
                          child: Icon(obscureNew ? Icons.visibility_off : Icons.visibility,
                              color: AppColors.grey400, size: 20),
                        ),
                      ),
                      onSubmitted: (_) => confirmPasswordFocus.requestFocus(),
                    ),
                    const SizedBox(height: 12),
                    _buildSheetTextField(
                      context: ctx,
                      controller: confirmPasswordController,
                      focusNode: confirmPasswordFocus,
                      label: '비밀번호 확인',
                      hint: '비밀번호를 다시 입력해주세요',
                      icon: Icons.lock_outline,
                      obscureText: obscureConfirm,
                      suffixWidget: Semantics(
                        button: true,
                        label: obscureConfirm ? '비밀번호 표시' : '비밀번호 숨김',
                        child: GestureDetector(
                          onTap: () => setSheetState(() => obscureConfirm = !obscureConfirm),
                          child: Icon(obscureConfirm ? Icons.visibility_off : Icons.visibility,
                              color: AppColors.grey400, size: 20),
                        ),
                      ),
                      onSubmitted: (_) => resetPassword(),
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton(
                      onPressed: isChanging ? null : resetPassword,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Theme.of(ctx).primaryColor,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        elevation: 0,
                      ),
                      child: isChanging
                          ? const SizedBox(width: 20, height: 20,
                              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                          : Text('비밀번호 변경', style: ResponsiveHelper.subtitleStyle(ctx).copyWith(fontWeight: FontWeight.w600)),
                    ),

                  // ── 아이디 입력 + PASS 인증 ──
                  ] else ...[
                    Text('비밀번호 찾기',
                        style: ResponsiveHelper.titleStyle(ctx).copyWith(fontWeight: FontWeight.w700, color: AppColors.grey900)),
                    const SizedBox(height: 6),
                    Text('아이디 입력 후 PASS 본인인증으로 신원을 확인합니다',
                        style: ResponsiveHelper.bodyStyle(ctx).copyWith(color: AppColors.grey500)),
                    const SizedBox(height: 24),
                    _buildSheetTextField(
                      context: ctx,
                      controller: usernameController,
                      focusNode: usernameFocus,
                      label: '아이디',
                      hint: 'your_username',
                      icon: Icons.account_circle_outlined,
                      onSubmitted: (_) => doPassAuth(),
                    ),
                    const SizedBox(height: 16),
                    PassAuthButton(
                      onPressed: doPassAuth,
                      isLoading: isAuthenticating,
                    ),
                    const SizedBox(height: 14),
                    // 외국인 사용자 안내 — ciHash 미등록으로 비밀번호 찾기 불가
                    Center(
                      child: Wrap(
                        alignment: WrapAlignment.center,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            '외국인 사용자이신가요? ',
                            style: ResponsiveHelper.bodyStyle(ctx)
                                .copyWith(color: AppColors.grey500),
                          ),
                          TextButton(
                            onPressed: () => ToastHelper.showInfo(
                              '고객센터(alfit@alfit.co.kr)로 문의해 주세요',
                            ),
                            style: TextButton.styleFrom(
                              padding: EdgeInsets.zero,
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            child: Text(
                              '고객센터 문의',
                              style: ResponsiveHelper.bodyStyle(ctx).copyWith(
                                color: Theme.of(ctx).primaryColor,
                                decoration: TextDecoration.underline,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
                ),
              ),
            ),
          );
        },
      ),
    );
    } finally {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        usernameController.dispose();
        newPasswordController.dispose();
        confirmPasswordController.dispose();
        // FocusNode는 _LoginScreenState.dispose()에서 해제 — 여기서 dispose 금지
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: Builder(
        builder: (context) {
          final isLoading = context.select<UserProvider, bool>((p) => p.isLoading);
          final size = MediaQuery.sizeOf(context);
          final bottomPadding = MediaQuery.of(context).padding.bottom;
          return LoadingOverlay(
            isLoading: isLoading,
            message: '로그인 중...',
            child: Container(
              width: double.infinity,
              height: double.infinity,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Theme.of(context).primaryColor, Theme.of(context).colorScheme.secondary],
                ),
              ),
              child: Stack(
                children: [
                  // 스플래시와 동일한 빛번짐 — 상단 우측
                  Positioned(
                    top: -size.height * 0.12,
                    right: -size.width * 0.15,
                    child: Container(
                      width: size.width * 0.75,
                      height: size.width * 0.75,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withValues(alpha: 0.07),
                      ),
                    ),
                  ),
                  // 하단 좌측
                  Positioned(
                    bottom: -size.height * 0.08,
                    left: -size.width * 0.2,
                    child: Container(
                      width: size.width * 0.65,
                      height: size.width * 0.65,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withValues(alpha: 0.05),
                      ),
                    ),
                  ),
                  // 메인 콘텐츠
                  Positioned.fill(
                    child: SafeArea(
                      bottom: false,
                      child: SingleChildScrollView(
                  physics: const ClampingScrollPhysics(),
                  child: Column(
                    children: [
                      SizedBox(height: math.max(40.0, size.height * 0.07)),

                      // 로고 영역
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ClipOval(
                            child: Image.asset(
                              'assets/icons/app_icon.png',
                              width: 60,
                              height: 60,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'ALfit',
                            style: TextStyle(
                              fontSize: ResponsiveHelper.titleStyle(context).fontSize! * 2.2,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                              letterSpacing: 1.5,
                              height: 1,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '나에게 딱 맞는 알바 매칭',
                            style: ResponsiveHelper.bodyStyle(context).copyWith(
                              color: Colors.white.withValues(alpha: 0.75),
                              letterSpacing: 0.3,
                            ),
                          ),
                        ],
                      ),

                      SizedBox(height: math.max(28.0, size.height * 0.05)),

                      // 로그인 카드 (floating)
                      Container(
                        margin: const EdgeInsets.symmetric(horizontal: 20),
                        padding: const EdgeInsets.fromLTRB(24, 28, 24, 28),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(24),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.18),
                              blurRadius: 32,
                              offset: const Offset(0, 10),
                            ),
                          ],
                        ),
                        child: _buildForm(context, isLoading),
                      ),

                      const SizedBox(height: 24),

                      // 회원가입 링크 (카드 밖, 파란 배경)
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            '계정이 없으신가요?',
                            style: ResponsiveHelper.bodyStyle(context).copyWith(
                              color: Colors.white.withValues(alpha: 0.8),
                            ),
                          ),
                          TextButton(
                            onPressed: () => Navigator.push(
                              context,
                              MaterialPageRoute(builder: (_) => const RegisterScreen()),
                            ),
                            style: TextButton.styleFrom(
                              minimumSize: Size.zero,
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            child: Text(
                              '회원가입',
                              style: ResponsiveHelper.bodyStyle(context).copyWith(
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                                decoration: TextDecoration.underline,
                                decorationColor: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ),

                      SizedBox(height: math.max(24.0, bottomPadding + 16)),
                    ],
                  ),
                ),
              ),
            ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildForm(BuildContext context, bool isLoading) {
    final theme = Theme.of(context);

    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '로그인',
            style: ResponsiveHelper.titleStyle(context).copyWith(
              fontWeight: FontWeight.w700,
              color: AppColors.grey900,
              height: 1,
            ),
          ),

          const SizedBox(height: 28),

          _buildTextField(
            context: context,
            theme: theme,
            controller: _usernameController,
            focusNode: _usernameFocus,
            label: '아이디',
            hint: '아이디를 입력하세요',
            icon: Icons.account_circle_outlined,
            textInputAction: TextInputAction.next,
            onFieldSubmitted: (_) => _passwordFocus.requestFocus(),
            validator: (value) {
              if (value == null || value.isEmpty) return '아이디를 입력해주세요';
              return null;
            },
          ),

          const SizedBox(height: 14),

          _buildTextField(
            context: context,
            theme: theme,
            controller: _passwordController,
            focusNode: _passwordFocus,
            label: '비밀번호',
            hint: '비밀번호를 입력하세요',
            icon: Icons.lock_outline,
            obscureText: _obscurePassword,
            textInputAction: TextInputAction.done,
            onFieldSubmitted: (_) => _handleLogin(),
            suffixIcon: IconButton(
              icon: Icon(
                _obscurePassword ? Icons.visibility_off : Icons.visibility,
                color: AppColors.grey400,
                size: 20,
              ),
              onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
            ),
            validator: (value) {
              if (value == null || value.isEmpty) return '비밀번호를 입력해주세요';
              if (value.length < 8) return '비밀번호는 8자 이상이어야 합니다';
              return null;
            },
          ),

          const SizedBox(height: 10),

          // 아이디/비밀번호 찾기
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              TextButton(
                onPressed: _showFindUsernameDialog,
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.grey500,
                  minimumSize: Size.zero,
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text('아이디 찾기', style: ResponsiveHelper.smallStyle(context)),
              ),
              Container(width: 1, height: 12, color: AppColors.grey300,
                  margin: const EdgeInsets.symmetric(horizontal: 4)),
              TextButton(
                onPressed: _showFindPasswordDialog,
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.grey500,
                  minimumSize: Size.zero,
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text('비밀번호 찾기', style: ResponsiveHelper.smallStyle(context)),
              ),
            ],
          ),

          const SizedBox(height: 24),

          // 로그인 버튼
          ElevatedButton(
            onPressed: isLoading ? null : _handleLogin,
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).primaryColor,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              elevation: 0,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '로그인',
                  style: ResponsiveHelper.subtitleStyle(context, color: Colors.white).copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(width: 8),
                const Icon(Icons.arrow_forward_rounded, size: 18, color: Colors.white),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// ✨ 텍스트 필드 빌더 (포커스 이동 지원)
  Widget _buildTextField({
    required BuildContext context,
    required ThemeData theme,
    required TextEditingController controller,
    required FocusNode focusNode,
    required String label,
    required String hint,
    required IconData icon,
    bool obscureText = false,
    TextInputAction? textInputAction,
    Function(String)? onFieldSubmitted,
    Widget? suffixIcon,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      focusNode: focusNode,
      obscureText: obscureText,
      textInputAction: textInputAction,
      onFieldSubmitted: onFieldSubmitted,
      style: ResponsiveHelper.bodyStyle(context),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        hintStyle: ResponsiveHelper.smallStyle(context, color: AppColors.grey400),
        prefixIcon: Icon(
          icon,
          color: theme.primaryColor,
          size: ResponsiveHelper.iconSize(context, 22),
        ),
        suffixIcon: suffixIcon,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: AppColors.grey300),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: AppColors.grey300),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: theme.primaryColor,
            width: 2,
          ),
        ),
        filled: true,
        fillColor: AppColors.grey50,
        contentPadding: EdgeInsets.symmetric(
          horizontal: ResponsiveHelper.spacing(context, 14),
          vertical: ResponsiveHelper.spacing(context, 14),
        ),
        isDense: true,
      ),
      validator: validator,
    );
  }

  Widget _buildSheetTextField({
    required BuildContext context,
    required TextEditingController controller,
    required FocusNode focusNode,
    required String label,
    required String hint,
    required IconData icon,
    TextInputType? keyboardType,
    int? maxLength,
    bool enabled = true,
    bool obscureText = false,
    Widget? suffixWidget,
    Function(String)? onSubmitted,
  }) {
    return TextField(
      controller: controller,
      focusNode: focusNode,
      keyboardType: keyboardType,
      maxLength: maxLength,
      enabled: enabled,
      obscureText: obscureText,
      onSubmitted: onSubmitted,
      style: ResponsiveHelper.bodyStyle(context),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        hintStyle: ResponsiveHelper.smallStyle(context, color: AppColors.grey400),
        prefixIcon: Icon(icon, color: Theme.of(context).primaryColor, size: 20),
        suffixIcon: suffixWidget != null
            ? Padding(
                padding: const EdgeInsets.only(right: 12),
                child: suffixWidget,
              )
            : null,
        suffixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
        counterText: '',
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: AppColors.grey300),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: AppColors.grey300),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: AppColors.grey200),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Theme.of(context).primaryColor, width: 2),
        ),
        filled: true,
        fillColor: enabled ? AppColors.grey50 : AppColors.grey100,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        isDense: true,
      ),
    );
  }
}