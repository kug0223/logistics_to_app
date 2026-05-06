import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

// Providers
import '../../providers/user_provider.dart';

// Utils
import 'package:cloud_functions/cloud_functions.dart';
import '../../utils/responsive_helper.dart';
import '../../utils/toast_helper.dart';

// Widgets
import '../../widgets/common/loading_widget.dart';

// Services
import '../../services/auth_service.dart';

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

  // ✨ FocusNode 추가
  final _usernameFocus = FocusNode();
  final _passwordFocus = FocusNode();

  @override
  void dispose() {
    _usernameController.dispose(); 
    _passwordController.dispose();
    _usernameFocus.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) return;

    final userProvider = context.read<UserProvider>();
    final success = await userProvider.signIn(
      _usernameController.text.trim(),
      _passwordController.text,
    );

    if (!success && mounted) {
      // 에러 처리는 AuthService에서 Toast로 표시됨
    }
  }

  Future<void> _showFindUsernameDialog() async {
    final nameController = TextEditingController();
    final phoneController = TextEditingController();
    final nameFocus = FocusNode();
    final phoneFocus = FocusNode();

    String? foundUsername;
    bool isSearching = false;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => StatefulBuilder(
        builder: (_, setSheetState) {
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
            final result = await AuthService().findUsername(
              name: nameController.text,
              phone: phoneController.text,
            );
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
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 40),
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
                    const Text('아이디 찾기',
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: Color(0xFF1A1A1A))),
                    const SizedBox(height: 6),
                    Text('가입 시 입력한 이름과 전화번호를 입력해주세요',
                        style: TextStyle(fontSize: 14, color: AppColors.grey500)),
                    const SizedBox(height: 24),
                    _buildSheetTextField(
                      controller: nameController,
                      focusNode: nameFocus,
                      label: '이름',
                      hint: '홍길동',
                      icon: Icons.person_outline,
                      onSubmitted: (_) => phoneFocus.requestFocus(),
                    ),
                    const SizedBox(height: 12),
                    _buildSheetTextField(
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
                    ElevatedButton(
                      onPressed: isSearching ? null : search,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1565C0),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        elevation: 0,
                      ),
                      child: isSearching
                          ? const SizedBox(width: 20, height: 20,
                              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                          : const Text('찾기', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                    ),

                  ] else if (foundUsername!.isEmpty) ...[
                    const SizedBox(height: 8),
                    const Icon(Icons.search_off_rounded, size: 60, color: Color(0xFFCCCCCC)),
                    const SizedBox(height: 16),
                    const Text('일치하는 계정을 찾을 수 없어요',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Color(0xFF1A1A1A))),
                    const SizedBox(height: 8),
                    Text('입력하신 정보를 다시 확인해주세요',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 14, color: AppColors.grey500)),
                    const SizedBox(height: 28),
                    OutlinedButton(
                      onPressed: () => setSheetState(() => foundUsername = null),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        side: const BorderSide(color: Color(0xFF1565C0)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      child: const Text('다시 찾기',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Color(0xFF1565C0))),
                    ),
                    const SizedBox(height: 8),

                  ] else ...[
                    const SizedBox(height: 8),
                    const Icon(Icons.check_circle_rounded, size: 60, color: Color(0xFF1565C0)),
                    const SizedBox(height: 16),
                    const Text('아이디를 찾았어요',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Color(0xFF1A1A1A))),
                    const SizedBox(height: 20),
                    Container(
                      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 24),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE3F2FD),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Text(
                        foundUsername!.length > 4
                            ? '${foundUsername!.substring(0, 4)}${'*' * (foundUsername!.length - 4)}'
                            : foundUsername!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF1565C0),
                          letterSpacing: 2,
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton(
                      onPressed: () => Navigator.pop(sheetContext),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1565C0),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        elevation: 0,
                      ),
                      child: const Text('확인', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                    ),
                    const SizedBox(height: 8),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );

    nameController.dispose();
    phoneController.dispose();
    nameFocus.dispose();
    phoneFocus.dispose();
  }

  Future<void> _showFindPasswordDialog() async {
    final usernameController = TextEditingController();
    final emailController = TextEditingController();
    final codeController = TextEditingController();
    final newPasswordController = TextEditingController();
    final confirmPasswordController = TextEditingController();
    final usernameFocus = FocusNode();
    final emailFocus = FocusNode();
    final codeFocus = FocusNode();
    final newPasswordFocus = FocusNode();
    final confirmPasswordFocus = FocusNode();

    // 0: 아이디+이메일 입력, 1: 인증코드+새비밀번호 입력, 2: 완료
    int step = 0;
    bool isSending = false;
    bool isChanging = false;
    bool obscureNew = true;
    bool obscureConfirm = true;

    final fn = FirebaseFunctions.instanceFor(region: 'asia-northeast3');

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => StatefulBuilder(
        builder: (_, setSheetState) {
          Future<void> sendCode() async {
            if (usernameController.text.isEmpty) {
              ToastHelper.showWarning('아이디를 입력해주세요');
              usernameFocus.requestFocus();
              return;
            }
            if (emailController.text.isEmpty || !emailController.text.contains('@')) {
              ToastHelper.showWarning('올바른 이메일을 입력해주세요');
              emailFocus.requestFocus();
              return;
            }
            setSheetState(() => isSending = true);
            try {
              await fn.httpsCallable('sendPasswordResetCode').call({
                'username': usernameController.text.trim(),
                'email': emailController.text.trim(),
              });
              setSheetState(() { isSending = false; step = 1; });
              ToastHelper.showSuccess('인증번호가 이메일로 발송되었습니다 (5분 유효)');
              Future.delayed(const Duration(milliseconds: 300), () => codeFocus.requestFocus());
            } on FirebaseFunctionsException catch (e) {
              setSheetState(() => isSending = false);
              ToastHelper.showError(e.message ?? '인증번호 발송에 실패했습니다');
            } catch (_) {
              setSheetState(() => isSending = false);
              ToastHelper.showError('오류가 발생했습니다. 다시 시도해주세요');
            }
          }

          Future<void> resetPassword() async {
            if (codeController.text.length != 6) {
              ToastHelper.showWarning('6자리 인증번호를 입력해주세요');
              codeFocus.requestFocus();
              return;
            }
            if (newPasswordController.text.length < 6) {
              ToastHelper.showWarning('비밀번호는 6자 이상이어야 합니다');
              newPasswordFocus.requestFocus();
              return;
            }
            if (newPasswordController.text != confirmPasswordController.text) {
              ToastHelper.showWarning('비밀번호가 일치하지 않습니다');
              confirmPasswordFocus.requestFocus();
              return;
            }
            setSheetState(() => isChanging = true);
            try {
              await fn.httpsCallable('resetPasswordWithCode').call({
                'username': usernameController.text.trim(),
                'code': codeController.text.trim(),
                'newPassword': newPasswordController.text,
              });
              setSheetState(() { isChanging = false; step = 2; });
            } on FirebaseFunctionsException catch (e) {
              setSheetState(() => isChanging = false);
              ToastHelper.showError(e.message ?? '비밀번호 변경에 실패했습니다');
            } catch (_) {
              setSheetState(() => isChanging = false);
              ToastHelper.showError('오류가 발생했습니다. 다시 시도해주세요');
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
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 40),
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
                    const Icon(Icons.check_circle_rounded, size: 60, color: Color(0xFF1565C0)),
                    const SizedBox(height: 16),
                    const Text('비밀번호가 변경되었어요',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Color(0xFF1A1A1A))),
                    const SizedBox(height: 8),
                    Text('새 비밀번호로 로그인해주세요',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 14, color: AppColors.grey500)),
                    const SizedBox(height: 28),
                    ElevatedButton(
                      onPressed: () => Navigator.pop(sheetContext),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1565C0),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        elevation: 0,
                      ),
                      child: const Text('로그인하러 가기', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                    ),
                    const SizedBox(height: 8),

                  // ── 인증코드 + 새 비밀번호 입력 ──
                  ] else if (step == 1) ...[
                    const Text('비밀번호 재설정',
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: Color(0xFF1A1A1A))),
                    const SizedBox(height: 6),
                    Text('이메일로 발송된 인증번호와 새 비밀번호를 입력해주세요',
                        style: TextStyle(fontSize: 14, color: AppColors.grey500)),
                    const SizedBox(height: 24),
                    _buildSheetTextField(
                      controller: codeController,
                      focusNode: codeFocus,
                      label: '인증번호',
                      hint: '6자리 숫자',
                      icon: Icons.mail_outline,
                      keyboardType: TextInputType.number,
                      maxLength: 6,
                      onSubmitted: (_) => newPasswordFocus.requestFocus(),
                    ),
                    const SizedBox(height: 12),
                    _buildSheetTextField(
                      controller: newPasswordController,
                      focusNode: newPasswordFocus,
                      label: '새 비밀번호',
                      hint: '6자 이상',
                      icon: Icons.lock_outline,
                      obscureText: obscureNew,
                      suffixWidget: GestureDetector(
                        onTap: () => setSheetState(() => obscureNew = !obscureNew),
                        child: Icon(obscureNew ? Icons.visibility_off : Icons.visibility,
                            color: AppColors.grey400, size: 20),
                      ),
                      onSubmitted: (_) => confirmPasswordFocus.requestFocus(),
                    ),
                    const SizedBox(height: 12),
                    _buildSheetTextField(
                      controller: confirmPasswordController,
                      focusNode: confirmPasswordFocus,
                      label: '비밀번호 확인',
                      hint: '비밀번호를 다시 입력해주세요',
                      icon: Icons.lock_outline,
                      obscureText: obscureConfirm,
                      suffixWidget: GestureDetector(
                        onTap: () => setSheetState(() => obscureConfirm = !obscureConfirm),
                        child: Icon(obscureConfirm ? Icons.visibility_off : Icons.visibility,
                            color: AppColors.grey400, size: 20),
                      ),
                      onSubmitted: (_) => resetPassword(),
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton(
                      onPressed: isChanging ? null : resetPassword,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1565C0),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        elevation: 0,
                      ),
                      child: isChanging
                          ? const SizedBox(width: 20, height: 20,
                              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                          : const Text('비밀번호 변경', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                    ),

                  // ── 아이디 + 이메일 입력 ──
                  ] else ...[
                    const Text('비밀번호 찾기',
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: Color(0xFF1A1A1A))),
                    const SizedBox(height: 6),
                    Text('가입 시 등록한 아이디와 이메일을 입력해주세요',
                        style: TextStyle(fontSize: 14, color: AppColors.grey500)),
                    const SizedBox(height: 24),
                    _buildSheetTextField(
                      controller: usernameController,
                      focusNode: usernameFocus,
                      label: '아이디',
                      hint: 'your_username',
                      icon: Icons.account_circle_outlined,
                      onSubmitted: (_) => emailFocus.requestFocus(),
                    ),
                    const SizedBox(height: 12),
                    _buildSheetTextField(
                      controller: emailController,
                      focusNode: emailFocus,
                      label: '이메일',
                      hint: 'your@email.com',
                      icon: Icons.email_outlined,
                      keyboardType: TextInputType.emailAddress,
                      onSubmitted: (_) => sendCode(),
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton(
                      onPressed: isSending ? null : sendCode,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1565C0),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        elevation: 0,
                      ),
                      child: isSending
                          ? const SizedBox(width: 20, height: 20,
                              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                          : const Text('인증번호 발송', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );

    usernameController.dispose();
    emailController.dispose();
    codeController.dispose();
    newPasswordController.dispose();
    confirmPasswordController.dispose();
    usernameFocus.dispose();
    emailFocus.dispose();
    codeFocus.dispose();
    newPasswordFocus.dispose();
    confirmPasswordFocus.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: Consumer<UserProvider>(
        builder: (context, userProvider, _) {
          return LoadingOverlay(
            isLoading: userProvider.isLoading,
            message: '로그인 중...',
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xFF1565C0), Color(0xFF1E88E5)],
                ),
              ),
              child: SafeArea(
                bottom: false,
                child: Column(
                  children: [
                    // 상단 로고 영역
                    SizedBox(
                      height: MediaQuery.of(context).size.height * 0.27,
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text(
                              'ALfit',
                              style: TextStyle(
                                fontSize: 44,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                                letterSpacing: 1.5,
                                height: 1,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '나에게 딱 맞는 알바 매칭',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w400,
                                color: Colors.white.withValues(alpha: 0.75),
                                letterSpacing: 0.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    // 하단 흰색 폼 영역
                    Expanded(
                      child: Container(
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.vertical(
                            top: Radius.circular(32),
                          ),
                        ),
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.fromLTRB(28, 32, 28, 40),
                          child: _buildForm(context, userProvider),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildForm(BuildContext context, UserProvider userProvider) {
    final theme = Theme.of(context);

    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            '로그인',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: Color(0xFF1A1A1A),
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
            hint: 'your_username',
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
            hint: '6자 이상 입력',
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
              if (value.length < 6) return '비밀번호는 6자 이상이어야 합니다';
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
                child: const Text('아이디 찾기', style: TextStyle(fontSize: 13)),
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
                child: const Text('비밀번호 찾기', style: TextStyle(fontSize: 13)),
              ),
            ],
          ),

          const SizedBox(height: 24),

          // 로그인 버튼
          ElevatedButton(
            onPressed: userProvider.isLoading ? null : _handleLogin,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1565C0),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              elevation: 0,
            ),
            child: const Text(
              '로그인',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
          ),

          const SizedBox(height: 40),

          // 회원가입 링크
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '계정이 없으신가요?',
                style: TextStyle(fontSize: 14, color: AppColors.grey500),
              ),
              TextButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const RegisterScreen()),
                ),
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFF1565C0),
                  minimumSize: Size.zero,
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text(
                  '회원가입',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
              ),
            ],
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
      style: const TextStyle(fontSize: 15),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        hintStyle: TextStyle(color: AppColors.grey400, fontSize: 14),
        prefixIcon: Icon(icon, color: const Color(0xFF1565C0), size: 20),
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
          borderSide: const BorderSide(color: Color(0xFF1565C0), width: 2),
        ),
        filled: true,
        fillColor: enabled ? AppColors.grey50 : AppColors.grey100,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        isDense: true,
      ),
    );
  }
}