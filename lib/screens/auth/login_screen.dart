import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
import 'registration_recovery_screen.dart'; // [C안 F-01-3] 가입 미완료 복구 화면
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
  bool _saveId = false;

  final _authService = AuthService();
  // [NEW-04] _auth, _fn은 _PasswordResetSheet 내부에서 직접 생성 (LoginScreen에서 제거)

  final _usernameFocus = FocusNode();
  final _passwordFocus = FocusNode();

  // 바텀시트용 FocusNode + TextEditingController — 화면 lifecycle에서 관리
  // dismiss 애니메이션(300ms)이 끝나기 전에 dispose되면 TextField crash 발생하므로
  // addPostFrameCallback 대신 State.dispose()에서 일괄 정리
  final _findUsernameNameFocus = FocusNode();
  final _findUsernamePhoneFocus = FocusNode();
  final _findUsernameNameController = TextEditingController();
  final _findUsernamePhoneController = TextEditingController();

  // [NEW-04] 비밀번호 찾기 controller/focus는 _PasswordResetSheet가 자체 소유.
  // LoginScreen State에서 제거하여 lifecycle 불일치(disposed controller 참조) 원천 차단.

  @override
  void initState() {
    super.initState();
    _loadSavedId();
  }

  Future<void> _loadSavedId() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('saved_username') ?? '';
    // async gap 동안 사용자가 이미 타이핑했으면 덮어쓰지 않음
    if (saved.isNotEmpty && mounted && _usernameController.text.isEmpty) {
      setState(() {
        _usernameController.text = saved;
        _saveId = true;
      });
    }
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _usernameFocus.dispose();
    _passwordFocus.dispose();
    _findUsernameNameFocus.dispose();
    _findUsernamePhoneFocus.dispose();
    _findUsernameNameController.dispose();
    _findUsernamePhoneController.dispose();
    // [NEW-04] 비밀번호찾기 controller/focus는 _PasswordResetSheet.dispose()가 처리
    super.dispose();
  }

  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();

    // 아이디 저장/삭제
    final prefs = await SharedPreferences.getInstance();
    if (_saveId) {
      await prefs.setString('saved_username', _usernameController.text.trim());
    } else {
      await prefs.remove('saved_username');
    }
    if (!mounted) return;

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
      // [C안 F-01-3] 외국인 가입 미완료 계정 → 복구 화면으로 라우팅
      if (userProvider.hasIncompleteRegistration) {
        Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => const RegistrationRecoveryScreen(),
        ));
        return;
      }
      final err = userProvider.error;
      ToastHelper.showError(
        (err != null && err.isNotEmpty) ? err : '아이디 또는 비밀번호가 올바르지 않습니다.',
      );
    }
  }

  Future<void> _showFindUsernameDialog() async {
    // 이전 호출에서 남은 내용 초기화
    _findUsernameNameController.clear();
    _findUsernamePhoneController.clear();
    // [AUTH-FIX §4] 복수 계정 지원: null=미검색, []=없음, non-empty=발견
    List<Map<String, String>>? foundAccounts;
    bool isSearching = false;

    // [AUTH-FIX §5] 앞 2자리만 노출, 나머지 마스킹 (e.g. ab*****)
    String maskUsername(String u) =>
        u.length > 2 ? '${u.substring(0, 2)}${'*' * (u.length - 2)}' : u;

    String roleLabel(String role) {
      switch (role) {
        case 'BUSINESS_ADMIN': return '사업장 관리자';
        case 'USER': return '지원자';
        default: return role;
      }
    }

    await DialogHelper.showSheet(
        context,
        isScrollControlled: true,
        builder: (sheetContext) => StatefulBuilder(
            builder: (ctx, setSheetState) {
              Future<void> search() async {
                if (_findUsernameNameController.text.isEmpty) {
                  ToastHelper.showWarning('이름을 입력해주세요');
                  _findUsernameNameFocus.requestFocus();
                  return;
                }
                if (_findUsernamePhoneController.text.isEmpty) {
                  ToastHelper.showWarning('전화번호를 입력해주세요');
                  _findUsernamePhoneFocus.requestFocus();
                  return;
                }
                setSheetState(() => isSearching = true);
                final result = await _authService.findUsername(
                  name: _findUsernameNameController.text,
                  phone: _findUsernamePhoneController.text,
                );
                if (!ctx.mounted) return;
                setSheetState(() {
                  isSearching = false;
                  foundAccounts = result;
                });
              }

              return Padding(
                padding: EdgeInsets.only(bottom: MediaQuery.of(sheetContext).viewInsets.bottom),
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
                            decoration: BoxDecoration(color: AppColors.grey300, borderRadius: BorderRadius.circular(2)),
                          ),
                        ),
                        if (foundAccounts == null) ...[
                          Text('아이디 찾기',
                              style: ResponsiveHelper.titleStyle(ctx).copyWith(fontWeight: FontWeight.w700, color: AppColors.grey900)),
                          const SizedBox(height: 6),
                          Text('가입 시 입력한 이름과 전화번호를 입력해주세요',
                              style: ResponsiveHelper.bodyStyle(ctx).copyWith(color: AppColors.grey500)),
                          const SizedBox(height: 24),
                          _buildSheetTextField(
                            context: ctx,
                            controller: _findUsernameNameController,
                            focusNode: _findUsernameNameFocus,
                            label: '이름', hint: '홍길동', icon: Icons.person_outline,
                            onSubmitted: (_) => _findUsernamePhoneFocus.requestFocus(),
                          ),
                          const SizedBox(height: 12),
                          _buildSheetTextField(
                            context: ctx,
                            controller: _findUsernamePhoneController,
                            focusNode: _findUsernamePhoneFocus,
                            label: '전화번호', hint: '01012345678', icon: Icons.phone_outlined,
                            keyboardType: TextInputType.phone, maxLength: 11,
                            onSubmitted: (_) => search(),
                          ),
                          const SizedBox(height: 24),
                          ElevatedButton(
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
                                : Text('아이디 찾기', style: ResponsiveHelper.subtitleStyle(ctx, color: Colors.white).copyWith(fontWeight: FontWeight.w600)),
                          ),
                        ] else if (foundAccounts!.isEmpty) ...[
                          const SizedBox(height: 8),
                          Icon(Icons.search_off_rounded, size: 60, color: AppColors.grey300),
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
                            onPressed: () => setSheetState(() => foundAccounts = null),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              side: BorderSide(color: Theme.of(ctx).primaryColor),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                            ),
                            child: Text('다시 찾기',
                                style: ResponsiveHelper.subtitleStyle(ctx).copyWith(fontWeight: FontWeight.w600, color: Theme.of(ctx).primaryColor)),
                          ),
                        ] else ...[
                          // [AUTH-FIX §4] 복수 계정 결과 표시
                          const SizedBox(height: 8),
                          Icon(Icons.check_circle_rounded, size: 60, color: Theme.of(ctx).primaryColor),
                          const SizedBox(height: 16),
                          Text(
                            foundAccounts!.length == 1 ? '아이디를 찾았어요' : '${foundAccounts!.length}개의 계정을 찾았어요',
                            textAlign: TextAlign.center,
                            style: ResponsiveHelper.subtitleStyle(ctx).copyWith(fontWeight: FontWeight.w700, color: AppColors.grey900),
                          ),
                          const SizedBox(height: 20),
                          ...foundAccounts!.map((account) {
                            final username = account['username'] ?? '';
                            final role = account['role'] ?? '';
                            return Container(
                              margin: const EdgeInsets.only(bottom: 10),
                              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
                              decoration: BoxDecoration(
                                color: Theme.of(ctx).primaryColor.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      maskUsername(username),
                                      style: ResponsiveHelper.subtitleStyle(ctx).copyWith(
                                        fontWeight: FontWeight.w800,
                                        color: Theme.of(ctx).primaryColor,
                                        letterSpacing: 1.5,
                                      ),
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: Theme.of(ctx).primaryColor.withValues(alpha: 0.12),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      roleLabel(role),
                                      style: ResponsiveHelper.smallStyle(ctx).copyWith(
                                        color: Theme.of(ctx).primaryColor,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }),
                          const SizedBox(height: 14),
                          ElevatedButton(
                            onPressed: () {
                              FocusScope.of(ctx).unfocus();
                              Navigator.pop(sheetContext);
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Theme.of(ctx).primaryColor,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                              elevation: 0,
                            ),
                            child: Text('확인', style: ResponsiveHelper.subtitleStyle(ctx, color: Colors.white).copyWith(fontWeight: FontWeight.w600)),
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
  }

  /// [NEW-04] 비밀번호 찾기 바텀시트 — controller/focus 소유권을 _PasswordResetSheet에 위임.
  /// LoginScreen이 AuthWrapper에 의해 dispose되어도 시트의 controller는 영향받지 않는다.
  Future<void> _showFindPasswordDialog() async {
    await DialogHelper.showSheet(
      context,
      isScrollControlled: true,
      builder: (sheetContext) => const _PasswordResetSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    // sizeOf / paddingOf 는 키보드 상태와 무관 — 키보드 애니메이션 중 리빌드 없음
    final size = MediaQuery.sizeOf(context);
    final sysPadding = MediaQuery.paddingOf(context);

    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: Builder(
        builder: (ctx) {
          final isLoading = ctx.select<UserProvider, bool>((p) => p.isLoading);
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
                  colors: [
                    Theme.of(ctx).primaryColor,
                    Theme.of(ctx).colorScheme.secondary,
                  ],
                ),
              ),
              child: Stack(
                children: [
                  // 빛번짐 — 상단 우측 (스플래시 동일)
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
                  // 빛번짐 — 하단 좌측
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
                  // 콘텐츠 — LayoutBuilder 없음
                  // size.height 기반 고정 패딩 → 키보드 프레임마다 재계산 없음 → 부드러운 전환
                  Positioned.fill(
                    child: SingleChildScrollView(
                      physics: const ClampingScrollPhysics(),
                      padding: EdgeInsets.only(
                        top: sysPadding.top + size.height * 0.12,
                        bottom: math.max(24.0, sysPadding.bottom + 16),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // 로고 — 좌측 정렬, 아이콘 없음
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 28),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  'ALfit',
                                  style: TextStyle(
                                    fontSize: ResponsiveHelper.titleStyle(ctx).fontSize! * 2.4,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white,
                                    letterSpacing: 2,
                                    height: 1,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  '나에게 딱 맞는 알바 매칭',
                                  style: ResponsiveHelper.bodyStyle(ctx).copyWith(
                                    color: Colors.white.withValues(alpha: 0.75),
                                    letterSpacing: 0.2,
                                  ),
                                ),
                              ],
                            ),
                          ),

                          SizedBox(height: size.height * 0.04),

                          // 로그인 카드
                          Container(
                            margin: const EdgeInsets.symmetric(horizontal: 20),
                            padding: const EdgeInsets.fromLTRB(24, 32, 24, 32),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(24),
                              boxShadow: const [
                                BoxShadow(
                                  color: Color(0x2E000000),
                                  blurRadius: 32,
                                  offset: Offset(0, 10),
                                ),
                              ],
                            ),
                            child: _buildForm(ctx, isLoading),
                          ),
                        ],
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

          const SizedBox(height: 16),

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

          const SizedBox(height: 14),

          // 아이디 저장 체크박스 + 아이디/비밀번호 찾기
          Row(
            children: [
              SizedBox(
                width: 20,
                height: 20,
                child: Checkbox(
                  value: _saveId,
                  onChanged: (v) => setState(() => _saveId = v ?? false),
                  activeColor: theme.primaryColor,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                ),
              ),
              const SizedBox(width: 6),
              GestureDetector(
                onTap: () => setState(() => _saveId = !_saveId),
                child: Text(
                  '아이디 저장',
                  style: ResponsiveHelper.smallStyle(context, color: AppColors.grey600),
                ),
              ),
              const Spacer(),
              TextButton(
                onPressed: _showFindUsernameDialog,
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.grey600,
                  minimumSize: Size.zero,
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text('아이디 찾기', style: ResponsiveHelper.smallStyle(context)),
              ),
              Container(
                width: 1, height: 10,
                color: AppColors.grey300,
                margin: const EdgeInsets.symmetric(horizontal: 2),
              ),
              TextButton(
                onPressed: _showFindPasswordDialog,
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.grey600,
                  minimumSize: Size.zero,
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
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
              backgroundColor: theme.primaryColor,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              elevation: 0,
            ),
            child: Text(
              '로그인',
              style: ResponsiveHelper.subtitleStyle(context, color: Colors.white)
                  .copyWith(fontWeight: FontWeight.w600),
            ),
          ),

          const SizedBox(height: 20),

          const Divider(color: AppColors.grey200, height: 1),

          const SizedBox(height: 14),

          // 회원가입 링크 — 카드 안
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '계정이 없으신가요?',
                style: ResponsiveHelper.smallStyle(context, color: AppColors.grey500),
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
                  style: ResponsiveHelper.smallStyle(context).copyWith(
                    fontWeight: FontWeight.w700,
                    color: theme.primaryColor,
                  ),
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

// ── [NEW-04] 비밀번호 재설정 바텀시트 ──────────────────────────────────────────
//
// 분리 이유:
//   비밀번호 재설정 흐름은 signInWithCustomToken → updatePassword → signOut 순으로
//   임시 Firebase Auth 세션을 사용한다.
//   이 사이에 authStateChanges 이벤트가 발생하면 AuthWrapper가 LoginScreen을 dispose할 수 있고,
//   LoginScreen.State가 소유한 controller를 바텀시트가 계속 참조하면 disposed controller 오류가 발생한다.
//
// 해결:
//   controller/focusNode를 이 위젯의 State가 직접 소유하고 initState/dispose에서 관리한다.
//   LoginScreen이 먼저 dispose되어도 이 시트의 controller는 영향을 받지 않는다.
//   바텀시트가 닫힐 때 State.dispose()가 호출되어 controller도 함께 정리된다.

class _PasswordResetSheet extends StatefulWidget {
  const _PasswordResetSheet();

  @override
  State<_PasswordResetSheet> createState() => _PasswordResetSheetState();
}

class _PasswordResetSheetState extends State<_PasswordResetSheet> {
  // [NEW-04] controller/focus 자체 소유 — LoginScreen lifecycle과 완전 독립
  final _usernameController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _usernameFocus = FocusNode();
  final _newPasswordFocus = FocusNode();
  final _confirmPasswordFocus = FocusNode();

  // Firebase 인스턴스 — 시트 자체에서 직접 참조 (LoginScreen 의존 제거)
  final _auth = FirebaseAuth.instance;
  final _fn = FirebaseFunctions.instanceFor(region: 'asia-northeast3');
  final _authService = AuthService();

  // 0: 아이디 + 인증, 1: 새 비밀번호 입력, 2: 완료
  int _step = 0;
  bool _isAuthenticating = false;
  bool _isChanging = false;
  bool _obscureNew = true;
  bool _obscureConfirm = true;
  String? _customToken;

  // [AUTH-FIX §2] 외국인 OTP 플로우
  bool _isForeign = false;
  bool _otpSent = false;
  bool _isSendingOtp = false;
  bool _isVerifyingOtp = false;
  String? _maskedPhone;
  final _otpCodeController = TextEditingController();
  final _otpCodeFocus = FocusNode();

  @override
  void dispose() {
    _usernameController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    _usernameFocus.dispose();
    _newPasswordFocus.dispose();
    _confirmPasswordFocus.dispose();
    // [AUTH-FIX §2] 외국인 OTP 플로우 리소스 정리
    _otpCodeController.dispose();
    _otpCodeFocus.dispose();
    super.dispose();
  }

  // ── 외국인 OTP 인증 ────────────────────────────────────────────────────────

  // [AUTH-FIX §2] 1단계: username → recovery phone으로 OTP 발송
  Future<void> _doOtpSend() async {
    if (_usernameController.text.trim().isEmpty) {
      ToastHelper.showWarning('아이디를 입력해주세요');
      _usernameFocus.requestFocus();
      return;
    }
    setState(() => _isSendingOtp = true);
    try {
      final maskedPhone = await _authService.sendOtpForPasswordReset(
        _usernameController.text.trim(),
      );
      if (!mounted) return;
      if (maskedPhone == null || maskedPhone.isEmpty) {
        ToastHelper.showError('입력한 정보를 확인할 수 없어요.');
        setState(() => _isSendingOtp = false);
        return;
      }
      setState(() {
        _isSendingOtp = false;
        _otpSent = true;
        _maskedPhone = maskedPhone;
      });
      Future.delayed(const Duration(milliseconds: 300), () {
        if (mounted) _otpCodeFocus.requestFocus();
      });
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      setState(() => _isSendingOtp = false);
      ToastHelper.showError(e.message ?? '입력한 정보를 확인할 수 없어요.');
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSendingOtp = false);
      ToastHelper.showError('오류가 발생했습니다. 다시 시도해주세요');
    }
  }

  // [AUTH-FIX §2] 2단계: OTP 검증 → Custom Token 발급 → step 1로 전환
  Future<void> _doOtpVerify() async {
    final code = _otpCodeController.text.trim();
    if (code.length < 6) {
      ToastHelper.showWarning('인증번호 6자리를 입력해주세요');
      _otpCodeFocus.requestFocus();
      return;
    }
    setState(() => _isVerifyingOtp = true);
    try {
      final customToken = await _authService.resetPasswordWithOtp(
        username: _usernameController.text.trim(),
        code: code,
      );
      if (!mounted) return;
      if (customToken == null || customToken.isEmpty) {
        ToastHelper.showError('인증번호가 올바르지 않습니다');
        setState(() => _isVerifyingOtp = false);
        return;
      }
      _customToken = customToken;
      setState(() { _isVerifyingOtp = false; _step = 1; });
      Future.delayed(const Duration(milliseconds: 300), () {
        if (mounted) _newPasswordFocus.requestFocus();
      });
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      setState(() => _isVerifyingOtp = false);
      ToastHelper.showError(e.message ?? '인증번호가 올바르지 않습니다');
    } catch (e) {
      if (!mounted) return;
      setState(() => _isVerifyingOtp = false);
      ToastHelper.showError('오류가 발생했습니다. 다시 시도해주세요');
    }
  }

  // ── PASS 인증 ──────────────────────────────────────────────────────────────

  Future<void> _doPassAuth() async {
    if (_usernameController.text.trim().isEmpty) {
      ToastHelper.showWarning('아이디를 입력해주세요');
      _usernameFocus.requestFocus();
      return;
    }
    setState(() => _isAuthenticating = true);
    try {
      final passResult = await PassVerificationService.authenticate(
        purpose: 'resetPassword',
      );
      if (!mounted) return;
      if (passResult == null) {
        setState(() => _isAuthenticating = false);
        return; // 사용자 취소
      }

      final result = await _fn
          .httpsCallable(
            'resetPasswordWithPass',
            options: HttpsCallableOptions(timeout: const Duration(seconds: 15)),
          )
          .call({
        'passToken': passResult.passToken,
        'username': _usernameController.text.trim(),
      });
      if (!mounted) return;
      _customToken = result.data['customToken'] as String?;
      setState(() { _isAuthenticating = false; _step = 1; });
      Future.delayed(const Duration(milliseconds: 300), () {
        if (mounted) _newPasswordFocus.requestFocus();
      });
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      setState(() => _isAuthenticating = false);
      ToastHelper.showError(e.message ?? '본인인증에 실패했습니다');
    } catch (e) {
      if (!mounted) return;
      setState(() => _isAuthenticating = false);
      ToastHelper.showError('오류가 발생했습니다. 다시 시도해주세요');
    }
  }

  // ── 비밀번호 변경 ──────────────────────────────────────────────────────────

  Future<void> _resetPassword() async {
    final pw = _newPasswordController.text;
    final pwRegex = RegExp(r'^(?=.*[a-zA-Z])(?=.*\d)(?=.*[!@#$%^&*(),.?":{}|<>]).{8,}$');
    if (!pwRegex.hasMatch(pw)) {
      ToastHelper.showWarning('비밀번호는 8자 이상이며\n영문·숫자·특수문자를 포함해야 합니다');
      _newPasswordFocus.requestFocus();
      return;
    }
    if (pw != _confirmPasswordController.text) {
      ToastHelper.showWarning('비밀번호가 일치하지 않습니다');
      _confirmPasswordFocus.requestFocus();
      return;
    }
    if (_customToken == null) {
      ToastHelper.showError('인증 세션이 만료되었습니다. 다시 본인인증을 진행해주세요');
      setState(() => _step = 0);
      return;
    }
    setState(() => _isChanging = true);
    // [NEW-QA-05 FIX] Provider 참조를 첫 번째 await 이전에 캡처.
    // unmount 이후에도 Auth state cleanup이 반드시 실행되어야 하므로
    // context.read()를 await 이후에 호출하면 안 됨.
    // 원칙: "인증 state cleanup은 mounted와 무관하게 실행. UI 조작만 mounted 확인."
    final userProvider = context.read<UserProvider>();
    try {
      // [NEW-04] 임시 Custom Token 세션으로 재로그인 → 비밀번호 변경 → 즉시 로그아웃.
      // signInWithCustomToken 이후 authStateChanges 이벤트가 발생해 AuthWrapper가
      // LoginScreen을 dispose할 수 있지만, 이 시트의 controller는 이 State가 소유하므로
      // disposed controller 오류가 발생하지 않는다.
      final cred = await _auth.signInWithCustomToken(_customToken!);
      await cred.user!.updatePassword(pw);
      // [AUTH-FIX BUG-AUTH-09] 비밀번호 변경 후 기존 모든 세션 서버 측 revoke (best-effort)
      try {
        await _fn.httpsCallable('revokeUserSession',
            options: HttpsCallableOptions(timeout: const Duration(seconds: 10))).call({});
      } catch (e) {
        debugPrint('⚠️ [PasswordReset] revokeUserSession 실패: $e');
      }
      // mounted 무관하게 cleanup — Sheet가 닫혀도 ghost session 방지 보장
      userProvider.invalidatePendingUserLoads();
      await _auth.signOut(); // 임시 세션 즉시 종료 → 새 비밀번호로 재로그인 유도
      if (!mounted) return;
      setState(() { _isChanging = false; _step = 2; });
    } catch (e) {
      // cleanup 먼저 (mounted 무관) → UI 업데이트는 mounted 확인 후
      userProvider.invalidatePendingUserLoads();
      await _auth.signOut(); // 임시 세션 정리 — 미정리 시 의도치 않은 로그인 전환
      if (mounted) {
        setState(() => _isChanging = false);
        ToastHelper.showError('비밀번호 변경에 실패했습니다. 다시 시도해주세요');
      }
    }
  }

  // ── 빌드 ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(24, 0, 24, 40 + MediaQuery.of(context).padding.bottom),
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
              if (_step == 2) ...[
                const SizedBox(height: 8),
                Icon(Icons.check_circle_rounded, size: 60, color: Theme.of(context).primaryColor),
                const SizedBox(height: 16),
                Text('비밀번호가 변경되었어요',
                    textAlign: TextAlign.center,
                    style: ResponsiveHelper.subtitleStyle(context).copyWith(fontWeight: FontWeight.w700, color: AppColors.grey900)),
                const SizedBox(height: 8),
                Text('새 비밀번호로 로그인해주세요',
                    textAlign: TextAlign.center,
                    style: ResponsiveHelper.bodyStyle(context).copyWith(color: AppColors.grey500)),
                const SizedBox(height: 28),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).primaryColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    elevation: 0,
                  ),
                  child: Text('로그인하러 가기', style: ResponsiveHelper.subtitleStyle(context).copyWith(fontWeight: FontWeight.w600)),
                ),
                const SizedBox(height: 8),

              // ── 새 비밀번호 입력 ──
              ] else if (_step == 1) ...[
                Text('비밀번호 재설정',
                    style: ResponsiveHelper.titleStyle(context).copyWith(fontWeight: FontWeight.w700, color: AppColors.grey900)),
                const SizedBox(height: 6),
                Text('새로 사용할 비밀번호를 입력해주세요',
                    style: ResponsiveHelper.bodyStyle(context).copyWith(color: AppColors.grey500)),
                const SizedBox(height: 24),
                _buildTextField(
                  controller: _newPasswordController,
                  focusNode: _newPasswordFocus,
                  label: '새 비밀번호',
                  hint: '8자 이상, 영문·숫자·특수문자 포함',
                  icon: Icons.lock_outline,
                  obscureText: _obscureNew,
                  suffixWidget: Semantics(
                    button: true,
                    label: _obscureNew ? '비밀번호 표시' : '비밀번호 숨김',
                    child: GestureDetector(
                      onTap: () => setState(() => _obscureNew = !_obscureNew),
                      child: Icon(_obscureNew ? Icons.visibility_off : Icons.visibility,
                          color: AppColors.grey400, size: 20),
                    ),
                  ),
                  onSubmitted: (_) => _confirmPasswordFocus.requestFocus(),
                ),
                const SizedBox(height: 12),
                _buildTextField(
                  controller: _confirmPasswordController,
                  focusNode: _confirmPasswordFocus,
                  label: '비밀번호 확인',
                  hint: '비밀번호를 다시 입력해주세요',
                  icon: Icons.lock_outline,
                  obscureText: _obscureConfirm,
                  suffixWidget: Semantics(
                    button: true,
                    label: _obscureConfirm ? '비밀번호 표시' : '비밀번호 숨김',
                    child: GestureDetector(
                      onTap: () => setState(() => _obscureConfirm = !_obscureConfirm),
                      child: Icon(_obscureConfirm ? Icons.visibility_off : Icons.visibility,
                          color: AppColors.grey400, size: 20),
                    ),
                  ),
                  onSubmitted: (_) => _resetPassword(),
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: _isChanging ? null : _resetPassword,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).primaryColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    elevation: 0,
                  ),
                  child: _isChanging
                      ? const SizedBox(width: 20, height: 20,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : Text('비밀번호 변경', style: ResponsiveHelper.subtitleStyle(context, color: Colors.white).copyWith(fontWeight: FontWeight.w600)),
                ),

              // ── 아이디 입력 + 인증 (내국인: PASS / 외국인: OTP) ──
              ] else ...[
                Text('비밀번호 찾기',
                    style: ResponsiveHelper.titleStyle(context).copyWith(fontWeight: FontWeight.w700, color: AppColors.grey900)),
                const SizedBox(height: 6),
                Text(
                  _isForeign
                      ? '아이디 입력 후 등록된 연락처로 인증번호를 받습니다'
                      : '아이디 입력 후 본인인증을 진행해주세요.',
                  style: ResponsiveHelper.bodyStyle(context).copyWith(color: AppColors.grey500),
                ),
                const SizedBox(height: 16),
                // [AUTH-FIX §2] 내국인/외국인 토글
                Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () => setState(() {
                          _isForeign = false;
                          _otpSent = false;
                          _otpCodeController.clear();
                          _maskedPhone = null;
                        }),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          decoration: BoxDecoration(
                            color: !_isForeign
                                ? Theme.of(context).primaryColor
                                : AppColors.grey100,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '내국인',
                            textAlign: TextAlign.center,
                            style: ResponsiveHelper.bodyStyle(context).copyWith(
                              fontWeight: FontWeight.w600,
                              color: !_isForeign ? Colors.white : AppColors.grey500,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: GestureDetector(
                        onTap: () => setState(() {
                          _isForeign = true;
                          _otpSent = false;
                          _otpCodeController.clear();
                          _maskedPhone = null;
                        }),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          decoration: BoxDecoration(
                            color: _isForeign
                                ? Theme.of(context).primaryColor
                                : AppColors.grey100,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '외국인',
                            textAlign: TextAlign.center,
                            style: ResponsiveHelper.bodyStyle(context).copyWith(
                              fontWeight: FontWeight.w600,
                              color: _isForeign ? Colors.white : AppColors.grey500,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _buildTextField(
                  controller: _usernameController,
                  focusNode: _usernameFocus,
                  label: '아이디',
                  hint: 'your_username',
                  icon: Icons.account_circle_outlined,
                  onSubmitted: (_) => _isForeign ? _doOtpSend() : _doPassAuth(),
                ),
                const SizedBox(height: 16),
                if (!_isForeign) ...[
                  // 내국인: PASS 본인인증
                  PassAuthButton(
                    onPressed: _doPassAuth,
                    isLoading: _isAuthenticating,
                  ),
                ] else if (!_otpSent) ...[
                  // 외국인 1단계: OTP 발송 요청
                  ElevatedButton(
                    onPressed: _isSendingOtp ? null : _doOtpSend,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).primaryColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      elevation: 0,
                    ),
                    child: _isSendingOtp
                        ? const SizedBox(width: 20, height: 20,
                            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : Text('인증번호 받기', style: ResponsiveHelper.subtitleStyle(context, color: Colors.white).copyWith(fontWeight: FontWeight.w600)),
                  ),
                ] else ...[
                  // 외국인 2단계: OTP 입력 + 검증
                  Text(
                    '$_maskedPhone 으로 인증번호를 발송했습니다',
                    textAlign: TextAlign.center,
                    style: ResponsiveHelper.smallStyle(context).copyWith(color: AppColors.grey500),
                  ),
                  const SizedBox(height: 12),
                  _buildTextField(
                    controller: _otpCodeController,
                    focusNode: _otpCodeFocus,
                    label: '인증번호',
                    hint: '6자리 숫자 입력',
                    icon: Icons.sms_outlined,
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    onSubmitted: (_) => _doOtpVerify(),
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton(
                    onPressed: _isVerifyingOtp ? null : _doOtpVerify,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).primaryColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      elevation: 0,
                    ),
                    child: _isVerifyingOtp
                        ? const SizedBox(width: 20, height: 20,
                            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : Text('인증 확인', style: ResponsiveHelper.subtitleStyle(context, color: Colors.white).copyWith(fontWeight: FontWeight.w600)),
                  ),
                  const SizedBox(height: 10),
                  Center(
                    child: TextButton(
                      onPressed: _isSendingOtp ? null : () => setState(() {
                        _otpSent = false;
                        _otpCodeController.clear();
                        _maskedPhone = null;
                      }),
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.zero,
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: Text(
                        '인증번호 다시 받기',
                        style: ResponsiveHelper.bodyStyle(context).copyWith(
                          color: Theme.of(context).primaryColor,
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }

  // ── 텍스트 필드 헬퍼 (시트 자체 소유 — LoginScreen helper 의존 제거) ────────

  Widget _buildTextField({
    required TextEditingController controller,
    required FocusNode focusNode,
    required String label,
    required String hint,
    required IconData icon,
    bool obscureText = false,
    Widget? suffixWidget,
    TextInputType? keyboardType,
    int? maxLength,
    Function(String)? onSubmitted,
  }) {
    return TextField(
      controller: controller,
      focusNode: focusNode,
      obscureText: obscureText,
      keyboardType: keyboardType,
      maxLength: maxLength,
      onSubmitted: onSubmitted,
      style: ResponsiveHelper.bodyStyle(context),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        hintStyle: ResponsiveHelper.smallStyle(context, color: AppColors.grey400),
        prefixIcon: Icon(icon, color: Theme.of(context).primaryColor, size: 20),
        suffixIcon: suffixWidget != null
            ? Padding(padding: const EdgeInsets.only(right: 12), child: suffixWidget)
            : null,
        suffixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: AppColors.grey300)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: AppColors.grey300)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Theme.of(context).primaryColor, width: 2)),
        filled: true,
        fillColor: AppColors.grey50,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        isDense: true,
        counterText: maxLength != null ? '' : null, // 글자수 카운터 숨김
      ),
    );
  }
}