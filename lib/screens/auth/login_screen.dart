import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/user_provider.dart';
import '../../widgets/common/loading_widget.dart';
import '../../widgets/ALfit_splash_logo_widget.dart';
import '../../utils/responsive_helper.dart';
import 'register_screen.dart';

/// ALfit 로그인 화면 - LayoutBuilder로 화면 크기별 최적화
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

  @override
  void dispose() {
    _usernameController.dispose(); 
    _passwordController.dispose();
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
                // ✅ LayoutBuilder로 화면 크기 감지
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final availableHeight = constraints.maxHeight;
                    final content = _buildContent(context, theme, userProvider);
                    
                    // 컨텐츠 최소 높이 (대략적인 계산)
                    const minContentHeight = 580.0;
                    
                    // ✅ 화면이 충분하면 중앙 배치 (스크롤 없음)
                    if (availableHeight >= minContentHeight) {
                      return Center(
                        child: SingleChildScrollView(
                          physics: const NeverScrollableScrollPhysics(),
                          child: content,
                        ),
                      );
                    }
                    
                    // ✅ 화면이 작으면 스크롤 허용
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

  /// 로그인 컨텐츠 (분리)
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
          // 로고
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
                  // 아이디 입력
                  _buildTextField(
                    context: context,
                    theme: theme,
                    controller: _usernameController,
                    label: '아이디',
                    hint: 'your_username',
                    icon: Icons.account_circle_outlined,
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return '아이디를 입력해주세요';
                      }
                      return null;
                    },
                  ),
                  
                  SizedBox(height: ResponsiveHelper.spacing(context, 12)),

                  // 비밀번호 입력
                  _buildTextField(
                    context: context,
                    theme: theme,
                    controller: _passwordController,
                    label: '비밀번호',
                    hint: '6자 이상 입력',
                    icon: Icons.lock_outline,
                    obscureText: _obscurePassword,
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

          // 아이디/비밀번호 찾기
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              TextButton(
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('아이디 찾기 기능 준비 중입니다')),
                  );
                },
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
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('비밀번호 찾기 기능 준비 중입니다')),
                  );
                },
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

  /// 공통 텍스트 필드 빌더
  Widget _buildTextField({
    required BuildContext context,
    required ThemeData theme,
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    bool obscureText = false,
    Widget? suffixIcon,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: obscureText,
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