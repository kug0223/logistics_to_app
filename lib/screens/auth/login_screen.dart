import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

// Providers
import '../../providers/user_provider.dart';

// Utils
import '../../utils/responsive_helper.dart';
import '../../utils/toast_helper.dart';

// Widgets
import '../../widgets/common/loading_widget.dart';
import '../../widgets/alfit_splash_logo_widget.dart';
import '../../widgets/dialogs/styled_dialog.dart';

// Services
import '../../services/auth_service.dart';

// Screens
import 'register_screen.dart';

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

  /// 🔍 아이디 찾기 다이얼로그
  Future<void> _showFindUsernameDialog() async {
    final nameController = TextEditingController();
    final phoneController = TextEditingController();

    final result = await showDialog<String?>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => StyledDialog(
          title: '아이디 찾기',
          subtitle: '가입 시 입력한 정보를 입력해주세요',
          icon: Icons.person_search,
          headerColor: Theme.of(context).primaryColor,
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 이름 입력
              StyledDialogTextField(
                controller: nameController,
                labelText: '이름',
                hintText: '홍길동',
                prefixIcon: Icons.person,
              ),

              SizedBox(height: ResponsiveHelper.spacing(context, 16)),

              // 전화번호 입력
              StyledDialogTextField(
                controller: phoneController,
                labelText: '전화번호',
                hintText: '01012345678',
                prefixIcon: Icons.phone,
                keyboardType: TextInputType.phone,
                maxLength: 11,
              ),
            ],
          ),
          actions: [
            StyledDialogButton.cancel(
              onPressed: () => Navigator.pop(context),
            ),
            StyledDialogButton.primary(
              text: '찾기',
              onPressed: () async {
                if (nameController.text.isEmpty) {
                  ToastHelper.showWarning('이름을 입력해주세요');
                  return;
                }
                if (phoneController.text.isEmpty) {
                  ToastHelper.showWarning('전화번호를 입력해주세요');
                  return;
                }

                final authService = AuthService();
                final username = await authService.findUsername(
                  name: nameController.text,
                  phone: phoneController.text,
                );

                if (username != null) {
                  final maskedUsername = username.length > 4
                      ? '${username.substring(0, 4)}${'*' * (username.length - 4)}'
                      : username;
                  Navigator.pop(context, maskedUsername);
                }
              },
            ),
          ],
        ),
      ),
    );

    nameController.dispose();
    phoneController.dispose();

    // 결과 표시
    if (result != null && mounted) {
      await showDialog(
        context: context,
        builder: (context) => StyledDialog(
          title: '아이디 찾기 완료',
          subtitle: null,
          icon: Icons.check_circle,
          headerColor: Colors.green[600],
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 20)),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    Text(
                      '회원님의 아이디는',
                      style: ResponsiveHelper.bodyStyle(context),
                    ),
                    SizedBox(height: ResponsiveHelper.spacing(context, 8)),
                    Text(
                      result,
                      style: ResponsiveHelper.titleStyle(context).copyWith(
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).primaryColor,
                      ),
                    ),
                    SizedBox(height: ResponsiveHelper.spacing(context, 4)),
                    Text(
                      '입니다',
                      style: ResponsiveHelper.bodyStyle(context),
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            StyledDialogButton.primary(
              text: '확인',
              onPressed: () => Navigator.pop(context),
            ),
          ],
        ),
      );
    }
  }

  /// 🔒 비밀번호 찾기 다이얼로그
  Future<void> _showFindPasswordDialog() async {
    final usernameController = TextEditingController();
    final emailController = TextEditingController();
    final codeController = TextEditingController();
    bool isEmailSent = false;
    String? verificationCode;

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => StyledDialog(
          title: '비밀번호 찾기',
          subtitle: '이메일 인증 후 비밀번호를 재설정할 수 있습니다',
          icon: Icons.lock_reset,
          headerColor: Theme.of(context).primaryColor,
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 아이디 입력
              StyledDialogTextField(
                controller: usernameController,
                labelText: '아이디',
                hintText: 'your_username',
                prefixIcon: Icons.account_circle,
              ),

              SizedBox(height: ResponsiveHelper.spacing(context, 16)),

              // 이메일 입력
              StyledDialogTextField(
                controller: emailController,
                labelText: '이메일',
                hintText: 'your@email.com',
                prefixIcon: Icons.email,
                keyboardType: TextInputType.emailAddress,
                suffixIcon: isEmailSent
                    ? null
                    : TextButton(
                        onPressed: () async {
                          if (usernameController.text.isEmpty) {
                            ToastHelper.showWarning('아이디를 입력해주세요');
                            return;
                          }
                          if (emailController.text.isEmpty ||
                              !emailController.text.contains('@')) {
                            ToastHelper.showWarning('올바른 이메일을 입력해주세요');
                            return;
                          }

                          // TODO: 실제 이메일 발송 구현
                          setState(() {
                            isEmailSent = true;
                            verificationCode = '123456'; // 개발용
                          });

                          ToastHelper.showSuccess(
                              '인증번호가 발송되었습니다\n(개발용: 123456)');
                        },
                        child: Text(
                          '인증',
                          style: ResponsiveHelper.smallStyle(context).copyWith(
                            color: Theme.of(context).primaryColor,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
              ),

              // 인증번호 입력
              if (isEmailSent) ...[
                SizedBox(height: ResponsiveHelper.spacing(context, 16)),
                StyledDialogTextField(
                  controller: codeController,
                  labelText: '인증번호',
                  hintText: '6자리 숫자',
                  prefixIcon: Icons.password,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                ),
              ],
            ],
          ),
          actions: [
            StyledDialogButton.cancel(
              onPressed: () => Navigator.pop(context, false),
            ),
            if (isEmailSent)
              StyledDialogButton.primary(
                text: '확인',
                onPressed: () {
                  if (codeController.text != verificationCode) {
                    ToastHelper.showError('인증번호가 일치하지 않습니다');
                    return;
                  }
                  Navigator.pop(context, true);
                },
              ),
          ],
        ),
      ),
    );

    usernameController.dispose();
    emailController.dispose();
    codeController.dispose();

    // 인증 성공 시 비밀번호 재설정 안내
    if (result == true && mounted) {
      await showDialog(
        context: context,
        builder: (context) => StyledDialog(
          title: '이메일 인증 완료',
          subtitle: null,
          icon: Icons.mark_email_read,
          headerColor: Colors.green[600],
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '이메일로 비밀번호 재설정 링크가 발송되었습니다.',
                style: ResponsiveHelper.bodyStyle(context),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: ResponsiveHelper.spacing(context, 12)),
              Text(
                '이메일을 확인하여 비밀번호를 재설정해주세요.',
                style: ResponsiveHelper.smallStyle(context, color: Colors.grey[600]),
                textAlign: TextAlign.center,
              ),
            ],
          ),
          actions: [
            StyledDialogButton.primary(
              text: '확인',
              onPressed: () => Navigator.pop(context),
            ),
          ],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: Consumer<UserProvider>(
          builder: (context, userProvider, _) {
            return LoadingOverlay(
              isLoading: userProvider.isLoading,
              message: '로그인 중...',
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      theme.primaryColor.withOpacity(0.05),
                      theme.primaryColor.withOpacity(0.1),
                    ],
                  ),
                ),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final availableHeight = constraints.maxHeight;
                    final content = _buildContent(context, theme, userProvider);
                    
                    const minContentHeight = 580.0;
                    
                    if (availableHeight >= minContentHeight) {
                      return Center(
                        child: SingleChildScrollView(
                          physics: const NeverScrollableScrollPhysics(),
                          child: content,
                        ),
                      );
                    }
                    
                    return SingleChildScrollView(
                      physics: const ClampingScrollPhysics(),
                      child: content,
                    );
                  },
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context, ThemeData theme, UserProvider userProvider) {
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 24),
        vertical: ResponsiveHelper.spacing(context, 20),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 로고 (이미 "나에게 딱 맞는 알바, 알핏!" 포함)
          ALfitSplashLogo(
            isDark: false,
            width: MediaQuery.of(context).size.width * 0.5,
          ),
          
          SizedBox(height: ResponsiveHelper.spacing(context, 8)),
          
          // 서브타이틀
          Text(
            '반갑습니다!',
            textAlign: TextAlign.center,
            style: ResponsiveHelper.bodyStyle(
              context,
              color: Colors.grey[600],
            ).copyWith(
              fontWeight: FontWeight.w500,
            ),
          ),
          
          SizedBox(height: ResponsiveHelper.spacing(context, 24)),

          // 로그인 카드
          Container(
            padding: ResponsiveHelper.cardPadding(context),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.08),
                  blurRadius: 20,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ✨ 아이디 입력 (포커스 이동)
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
                      if (value == null || value.isEmpty) {
                        return '아이디를 입력해주세요';
                      }
                      return null;
                    },
                  ),
                  
                  SizedBox(height: ResponsiveHelper.spacing(context, 12)),

                  // ✨ 비밀번호 입력 (포커스 이동)
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
                        color: Colors.grey[600],
                        size: ResponsiveHelper.iconSize(context, 20),
                      ),
                      onPressed: () {
                        setState(() {
                          _obscurePassword = !_obscurePassword;
                        });
                      },
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return '비밀번호를 입력해주세요';
                      }
                      if (value.length < 6) {
                        return '비밀번호는 6자 이상이어야 합니다';
                      }
                      return null;
                    },
                  ),
                  
                  SizedBox(height: ResponsiveHelper.spacing(context, 20)),

                  // 로그인 버튼
                  ElevatedButton(
                    onPressed: userProvider.isLoading ? null : _handleLogin,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: theme.primaryColor,
                      foregroundColor: Colors.white,
                      padding: EdgeInsets.symmetric(
                        vertical: ResponsiveHelper.spacing(context, 14),
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 2,
                    ),
                    child: Text(
                      '로그인',
                      style: ResponsiveHelper.bodyStyle(context).copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          
          SizedBox(height: ResponsiveHelper.spacing(context, 12)),

          // ✨ 아이디/비밀번호 찾기
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              TextButton(
                onPressed: _showFindUsernameDialog,
                style: TextButton.styleFrom(
                  foregroundColor: Colors.grey[700],
                  padding: EdgeInsets.symmetric(
                    horizontal: ResponsiveHelper.spacing(context, 8),
                    vertical: ResponsiveHelper.spacing(context, 4),
                  ),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(
                  '아이디 찾기',
                  style: ResponsiveHelper.smallStyle(context, color: Colors.grey[700]),
                ),
              ),
              
              Container(
                height: ResponsiveHelper.spacing(context, 12),
                width: 1,
                color: Colors.grey[400],
                margin: EdgeInsets.symmetric(
                  horizontal: ResponsiveHelper.spacing(context, 8),
                ),
              ),
              
              TextButton(
                onPressed: _showFindPasswordDialog,
                style: TextButton.styleFrom(
                  foregroundColor: Colors.grey[700],
                  padding: EdgeInsets.symmetric(
                    horizontal: ResponsiveHelper.spacing(context, 8),
                    vertical: ResponsiveHelper.spacing(context, 4),
                  ),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(
                  '비밀번호 찾기',
                  style: ResponsiveHelper.smallStyle(context, color: Colors.grey[700]),
                ),
              ),
            ],
          ),
          
          SizedBox(height: ResponsiveHelper.spacing(context, 16)),

          // 회원가입 버튼
          OutlinedButton(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const RegisterScreen(),
                ),
              );
            },
            style: OutlinedButton.styleFrom(
              foregroundColor: theme.primaryColor,
              side: BorderSide(
                color: theme.primaryColor,
                width: 1.5,
              ),
              padding: EdgeInsets.symmetric(
                vertical: ResponsiveHelper.spacing(context, 12),
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              backgroundColor: Colors.white,
            ),
            child: Text(
              '회원가입',
              style: ResponsiveHelper.bodyStyle(context).copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          
          SizedBox(height: ResponsiveHelper.spacing(context, 16)),
          
          // 안내 문구
          Container(
            padding: EdgeInsets.symmetric(
              horizontal: ResponsiveHelper.spacing(context, 12),
              vertical: ResponsiveHelper.spacing(context, 10),
            ),
            decoration: BoxDecoration(
              color: theme.primaryColor.withOpacity(0.08),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.info_outline,
                  color: theme.primaryColor,
                  size: ResponsiveHelper.iconSize(context, 16),
                ),
                SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                Expanded(
                  child: Text(
                    '처음 이용하시나요? 회원가입을 진행해주세요.',
                    style: ResponsiveHelper.smallStyle(
                      context,
                      color: Colors.grey[700],
                    ),
                  ),
                ),
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
        hintStyle: ResponsiveHelper.smallStyle(context, color: Colors.grey[400]),
        prefixIcon: Icon(
          icon,
          color: theme.primaryColor,
          size: ResponsiveHelper.iconSize(context, 22),
        ),
        suffixIcon: suffixIcon,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey[300]!),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey[300]!),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: theme.primaryColor,
            width: 2,
          ),
        ),
        filled: true,
        fillColor: Colors.grey[50],
        contentPadding: EdgeInsets.symmetric(
          horizontal: ResponsiveHelper.spacing(context, 14),
          vertical: ResponsiveHelper.spacing(context, 14),
        ),
        isDense: true,
      ),
      validator: validator,
    );
  }
}