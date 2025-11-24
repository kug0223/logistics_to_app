// lib/screens/common/profile_edit_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:intl/intl.dart';

// Providers
import '../../providers/user_provider.dart';

// Models
import '../../models/core/user_model.dart';

// Services
import '../../services/firestore_service.dart';
import '../../services/auth_service.dart';

// Utils
import '../../utils/responsive_helper.dart';
import '../../utils/toast_helper.dart';

// Widgets
import '../../widgets/common/common_widgets.dart';
import '../../widgets/inputs/daum_address_search.dart';
import '../../widgets/dialogs/styled_dialog.dart';  // ⭐ 추가

/// ✨ 프로필 수정 화면
class ProfileEditScreen extends StatefulWidget {
  const ProfileEditScreen({super.key});

  @override
  State<ProfileEditScreen> createState() => _ProfileEditScreenState();
}

class _ProfileEditScreenState extends State<ProfileEditScreen> {
  final _formKey = GlobalKey<FormState>();
  final _firestoreService = FirestoreService();
  final _authService = AuthService();

  // 컨트롤러
  late TextEditingController _emailController;
  late TextEditingController _phoneController;
  late TextEditingController _addressController;
  late TextEditingController _detailAddressController;
  final _emailCodeController = TextEditingController();

  // 상태
  bool _isLoading = false;
  bool _hasChanges = false;

  // 이메일 인증 상태
  String? _originalEmail;
  bool _isEmailChanged = false;
  bool _isEmailSent = false;
  bool _isEmailVerified = false;
  String? _verificationCode;

  @override
  void initState() {
    super.initState();
    _initControllers();
  }

  void _initControllers() {
    final user = context.read<UserProvider>().currentUser;

    _emailController = TextEditingController(text: user?.userEmail ?? '');
    _phoneController = TextEditingController(text: user?.phone ?? '');
    _addressController = TextEditingController(text: user?.address ?? '');
    _detailAddressController = TextEditingController(text: user?.detailAddress ?? '');

    _originalEmail = user?.userEmail;

    // 변경 감지 리스너
    _emailController.addListener(_checkChanges);
    _phoneController.addListener(_checkChanges);
    _addressController.addListener(_checkChanges);
    _detailAddressController.addListener(_checkChanges);
  }

  void _checkChanges() {
    final user = context.read<UserProvider>().currentUser;
    if (user == null) return;

    final emailChanged = _emailController.text != (user.userEmail ?? '');
    final phoneChanged = _phoneController.text != (user.phone ?? '');
    final addressChanged = _addressController.text != (user.address ?? '');
    final detailChanged = _detailAddressController.text != (user.detailAddress ?? '');

    setState(() {
      _hasChanges = emailChanged || phoneChanged || addressChanged || detailChanged;
      _isEmailChanged = emailChanged;

      // 이메일이 변경되면 인증 초기화
      if (emailChanged && _emailController.text != _originalEmail) {
        _isEmailSent = false;
        _isEmailVerified = false;
      }
    });
  }

  @override
  void dispose() {
    _emailController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    _detailAddressController.dispose();
    _emailCodeController.dispose();
    super.dispose();
  }

  /// 이메일 인증 코드 발송
  Future<void> _sendEmailVerification() async {
    final email = _emailController.text.trim();

    if (email.isEmpty || !email.contains('@')) {
      ToastHelper.showWarning('올바른 이메일을 입력해주세요');
      return;
    }

    setState(() => _isEmailSent = true);

    // TODO: 실제 이메일 발송 구현
    _verificationCode = '123456';

    ToastHelper.showSuccess('인증번호가 $email로 발송되었습니다\n(개발용: 123456)');
  }

  /// 이메일 인증 코드 확인
  void _verifyEmailCode() {
    if (_emailCodeController.text == _verificationCode) {
      setState(() => _isEmailVerified = true);
      ToastHelper.showSuccess('이메일 인증이 완료되었습니다');
    } else {
      ToastHelper.showError('인증번호가 일치하지 않습니다');
    }
  }

  /// 주소 검색
  Future<void> _searchAddress() async {
    if (kIsWeb) {
      ToastHelper.showWarning('웹에서는 주소 검색을 사용할 수 없습니다');
      return;
    }

    final result = await DaumAddressService.searchAddress(context);

    if (result != null && mounted) {
      setState(() {
        _addressController.text = result.fullAddress;
      });
      ToastHelper.showSuccess('주소가 입력되었습니다');
    }
  }

  /// 비밀번호 변경 다이얼로그
  Future<void> _showPasswordChangeDialog() async {
    final currentPasswordController = TextEditingController();
    final newPasswordController = TextEditingController();
    final confirmPasswordController = TextEditingController();
    bool obscureCurrent = true;
    bool obscureNew = true;
    bool obscureConfirm = true;
    int passwordStrength = 0;

    // 비밀번호 강도 체크
    void checkPasswordStrength(String password) {
      if (password.isEmpty) {
        passwordStrength = 0;
        return;
      }
      int strength = 0;
      if (password.length >= 8) strength++;
      if (RegExp(r'[a-zA-Z]').hasMatch(password) && RegExp(r'[0-9]').hasMatch(password)) strength++;
      if (RegExp(r'[!@#$%^&*(),.?":{}|<>]').hasMatch(password)) strength++;
      passwordStrength = strength;
    }

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final theme = Theme.of(context);

          return StyledDialog(
            title: '비밀번호 변경',
            subtitle: '보안을 위해 안전한 비밀번호를 사용하세요',
            icon: Icons.lock_outline,
            content: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // 현재 비밀번호
                StyledDialogTextField(
                  controller: currentPasswordController,
                  labelText: '현재 비밀번호',
                  hintText: '현재 사용 중인 비밀번호',
                  prefixIcon: Icons.lock,
                  obscureText: obscureCurrent,
                  suffixIcon: IconButton(
                    icon: Icon(
                      obscureCurrent ? Icons.visibility_off : Icons.visibility,
                      color: Colors.grey[600],
                      size: ResponsiveHelper.iconSize(context, 22),
                    ),
                    onPressed: () => setDialogState(() => obscureCurrent = !obscureCurrent),
                  ),
                ),

                SizedBox(height: ResponsiveHelper.spacing(context, 24)),

                // 새 비밀번호
                StyledDialogTextField(
                  controller: newPasswordController,
                  labelText: '새 비밀번호',
                  hintText: '영문, 숫자, 특수문자 포함 8자 이상',
                  prefixIcon: Icons.lock_open,
                  obscureText: obscureNew,
                  onChanged: (value) {
                    setDialogState(() => checkPasswordStrength(value));
                  },
                  suffixIcon: IconButton(
                    icon: Icon(
                      obscureNew ? Icons.visibility_off : Icons.visibility,
                      color: Colors.grey[600],
                      size: ResponsiveHelper.iconSize(context, 22),
                    ),
                    onPressed: () => setDialogState(() => obscureNew = !obscureNew),
                  ),
                ),

                // 비밀번호 강도 표시
                if (newPasswordController.text.isNotEmpty) ...[
                  SizedBox(height: ResponsiveHelper.spacing(context, 12)),
                  PasswordStrengthIndicator(strength: passwordStrength),
                ],

                SizedBox(height: ResponsiveHelper.spacing(context, 24)),

                // 새 비밀번호 확인
                StyledDialogTextField(
                  controller: confirmPasswordController,
                  labelText: '새 비밀번호 확인',
                  hintText: '새 비밀번호를 다시 입력하세요',
                  prefixIcon: Icons.check_circle_outline,
                  obscureText: obscureConfirm,
                  suffixIcon: IconButton(
                    icon: Icon(
                      obscureConfirm ? Icons.visibility_off : Icons.visibility,
                      color: Colors.grey[600],
                      size: ResponsiveHelper.iconSize(context, 22),
                    ),
                    onPressed: () => setDialogState(() => obscureConfirm = !obscureConfirm),
                  ),
                ),

                SizedBox(height: ResponsiveHelper.spacing(context, 24)),

                // 안내 카드
                StyledDialogInfoCard.info(
                  '안전한 비밀번호는 영문, 숫자, 특수문자를 조합하여 8자 이상으로 만들어주세요.',
                ),
              ],
            ),
            actions: [
              StyledDialogButton.cancel(
                onPressed: () => Navigator.pop(context, false),
              ),
              StyledDialogButton.primary(
                text: '변경하기',
                onPressed: () {
                  // 검증
                  if (currentPasswordController.text.isEmpty) {
                    ToastHelper.showWarning('현재 비밀번호를 입력해주세요');
                    return;
                  }
                  if (newPasswordController.text.length < 8) {
                    ToastHelper.showWarning('새 비밀번호는 8자 이상이어야 합니다');
                    return;
                  }
                  if (!RegExp(r'[a-zA-Z]').hasMatch(newPasswordController.text)) {
                    ToastHelper.showWarning('영문을 포함해야 합니다');
                    return;
                  }
                  if (!RegExp(r'[0-9]').hasMatch(newPasswordController.text)) {
                    ToastHelper.showWarning('숫자를 포함해야 합니다');
                    return;
                  }
                  if (!RegExp(r'[!@#$%^&*(),.?":{}|<>]').hasMatch(newPasswordController.text)) {
                    ToastHelper.showWarning('특수문자를 포함해야 합니다');
                    return;
                  }
                  if (newPasswordController.text != confirmPasswordController.text) {
                    ToastHelper.showWarning('새 비밀번호가 일치하지 않습니다');
                    return;
                  }

                  Navigator.pop(context, true);
                },
              ),
            ],
          );
        },
      ),
    );

    if (result == true) {
      // TODO: 실제 비밀번호 변경 로직 구현
      ToastHelper.showSuccess('비밀번호가 변경되었습니다');
    }

    currentPasswordController.dispose();
    newPasswordController.dispose();
    confirmPasswordController.dispose();
  }

  /// 저장
  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;

    // 이메일이 변경되었는데 인증 안 했으면
    if (_isEmailChanged && !_isEmailVerified) {
      ToastHelper.showWarning('변경된 이메일 인증을 완료해주세요');
      return;
    }

    final user = context.read<UserProvider>().currentUser;
    if (user == null) return;

    setState(() => _isLoading = true);

    try {
      final updates = <String, dynamic>{};

      // 변경된 필드만 업데이트
      if (_emailController.text.trim() != (user.userEmail ?? '')) {
        updates['userEmail'] = _emailController.text.trim();
      }
      if (_phoneController.text.trim() != (user.phone ?? '')) {
        updates['phone'] = _phoneController.text.trim();
      }
      if (_addressController.text.trim() != (user.address ?? '')) {
        updates['address'] = _addressController.text.trim();
      }
      if (_detailAddressController.text.trim() != (user.detailAddress ?? '')) {
        updates['detailAddress'] = _detailAddressController.text.trim();
      }

      if (updates.isNotEmpty) {
        await _firestoreService.updateUserDocument(user.uid, updates);
        await context.read<UserProvider>().refreshCurrentUser();

        // 원본 이메일 업데이트
        _originalEmail = _emailController.text.trim();

        ToastHelper.showSuccess('프로필이 수정되었습니다');

        setState(() {
          _hasChanges = false;
          _isEmailChanged = false;
          _isEmailSent = false;
          _isEmailVerified = false;
        });
      }
    } catch (e) {
      ToastHelper.showError('프로필 수정에 실패했습니다');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final user = context.watch<UserProvider>().currentUser;

    if (user == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text('프로필 수정'),
        actions: [
          if (_hasChanges)
            TextButton(
              onPressed: _isLoading ? null : _saveProfile,
              child: _isLoading
                  ? SizedBox(
                      width: ResponsiveHelper.iconSize(context, 20),
                      height: ResponsiveHelper.iconSize(context, 20),
                      child: const CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Text(
                      '저장',
                      style: ResponsiveHelper.bodyStyle(context).copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
            ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: ResponsiveHelper.cardPadding(context),
          children: [
            // 프로필 헤더
            _buildProfileHeader(user),

            SizedBox(height: ResponsiveHelper.spacing(context, 24)),

            // 읽기 전용 정보 섹션
            _buildSectionHeader('기본 정보', Icons.person_outline),
            SizedBox(height: ResponsiveHelper.spacing(context, 12)),
            _buildReadOnlySection(user),

            SizedBox(height: ResponsiveHelper.spacing(context, 24)),

            // 수정 가능 정보 섹션
            _buildSectionHeader('연락처 정보', Icons.contact_phone_outlined),
            SizedBox(height: ResponsiveHelper.spacing(context, 12)),
            _buildEditableSection(user),

            SizedBox(height: ResponsiveHelper.spacing(context, 24)),

            // 주소 섹션
            _buildSectionHeader('주소 정보', Icons.location_on_outlined),
            SizedBox(height: ResponsiveHelper.spacing(context, 12)),
            _buildAddressSection(),

            SizedBox(height: ResponsiveHelper.spacing(context, 24)),

            // 보안 섹션
            _buildSectionHeader('보안', Icons.security_outlined),
            SizedBox(height: ResponsiveHelper.spacing(context, 12)),
            _buildSecuritySection(),

            SizedBox(height: ResponsiveHelper.spacing(context, 32)),
          ],
        ),
      ),
    );
  }

  /// 프로필 헤더
  Widget _buildProfileHeader(UserModel user) {
    final theme = Theme.of(context);
    // ⭐ ThemeProvider에서 역할별 색상 자동으로 가져옴
    final roleColor = theme.primaryColor;

    return Container(
      padding: ResponsiveHelper.cardPadding(context),
      decoration: CommonWidgets.gradientCardDecoration(color: roleColor),
      child: Row(
        children: [
          // 아바타
          Container(
            padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 16)),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.person,
              size: ResponsiveHelper.iconSize(context, 40),
              color: Colors.white,
            ),
          ),

          SizedBox(width: ResponsiveHelper.spacing(context, 16)),

          // 정보
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  user.name,
                  style: ResponsiveHelper.titleStyle(context).copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: ResponsiveHelper.spacing(context, 4)),
                Text(
                  '@${user.username}',
                  style: ResponsiveHelper.bodyStyle(context).copyWith(
                    color: Colors.white.withOpacity(0.9),
                  ),
                ),
                SizedBox(height: ResponsiveHelper.spacing(context, 8)),
                Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: ResponsiveHelper.spacing(context, 12),
                    vertical: ResponsiveHelper.spacing(context, 4),
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    CommonWidgets.getRoleName(user.roleString),  // ⭐ 수정
                    style: ResponsiveHelper.smallStyle(context).copyWith(
                      color: roleColor,
                      fontWeight: FontWeight.bold,
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

  /// 섹션 헤더
  Widget _buildSectionHeader(String title, IconData icon) {
    final theme = Theme.of(context);

    return Row(
      children: [
        Container(
          padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 8)),
          decoration: BoxDecoration(
            color: theme.primaryColor.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            icon,
            size: ResponsiveHelper.iconSize(context, 20),
            color: theme.primaryColor,
          ),
        ),
        SizedBox(width: ResponsiveHelper.spacing(context, 12)),
        Text(
          title,
          style: ResponsiveHelper.subtitleStyle(context).copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  /// 읽기 전용 정보 섹션
  Widget _buildReadOnlySection(UserModel user) {
    return Container(
      padding: ResponsiveHelper.cardPadding(context),
      decoration: CommonWidgets.cardDecoration(),
      child: Column(
        children: [
          _buildInfoRow(
            icon: Icons.person_outline,
            label: '이름',
            value: user.name,
          ),
          _buildDivider(),
          _buildInfoRow(
            icon: Icons.badge_outlined,
            label: '아이디',
            value: user.username,
          ),
          if (user.birthDate != null) ...[
            _buildDivider(),
            _buildInfoRow(
              icon: Icons.cake_outlined,
              label: '생년월일',
              value: DateFormat('yyyy.MM.dd').format(user.birthDate!),
            ),
          ],
          if (user.gender != null) ...[
            _buildDivider(),
            _buildInfoRow(
              icon: user.gender == '남성' ? Icons.male : Icons.female,
              label: '성별',
              value: user.gender!,
            ),
          ],
        ],
      ),
    );
  }

  /// 수정 가능 정보 섹션
  Widget _buildEditableSection(UserModel user) {
    final theme = Theme.of(context);

    return Container(
      padding: ResponsiveHelper.cardPadding(context),
      decoration: CommonWidgets.cardDecoration(),
      child: Column(
        children: [
          // 이메일
          CommonWidgets.textField(
            context: context,
            controller: _emailController,
            label: '이메일',
            hint: 'your@email.com',
            icon: Icons.email_outlined,
            keyboardType: TextInputType.emailAddress,
            suffixIcon: _isEmailChanged
                ? (_isEmailVerified
                    ? Icon(
                        Icons.check_circle,
                        color: Colors.green[600],
                        size: ResponsiveHelper.iconSize(context, 24),
                      )
                    : TextButton(
                        onPressed: _sendEmailVerification,
                        child: Text(
                          _isEmailSent ? '재발송' : '인증',
                          style: ResponsiveHelper.smallStyle(context).copyWith(
                            color: theme.primaryColor,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ))
                : null,
            validator: (value) {
              if (value == null || value.isEmpty) return '이메일을 입력해주세요';
              if (!value.contains('@')) return '올바른 이메일 형식이 아닙니다';
              return null;
            },
          ),

          // 이메일 인증 코드 입력
          if (_isEmailChanged && _isEmailSent && !_isEmailVerified) ...[
            SizedBox(height: ResponsiveHelper.spacing(context, 16)),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _emailCodeController,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(6),
                    ],
                    decoration: InputDecoration(
                      labelText: '인증번호 6자리',
                      hintText: '123456',
                      prefixIcon: Icon(Icons.pin, color: theme.primaryColor),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
                SizedBox(width: ResponsiveHelper.spacing(context, 12)),
                ElevatedButton(
                  onPressed: _verifyEmailCode,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: theme.primaryColor,
                    padding: EdgeInsets.symmetric(
                      horizontal: ResponsiveHelper.spacing(context, 20),
                      vertical: ResponsiveHelper.spacing(context, 16),
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text('확인', style: TextStyle(color: Colors.white)),
                ),
              ],
            ),
          ],

          SizedBox(height: ResponsiveHelper.spacing(context, 16)),

          // 전화번호
          CommonWidgets.textField(
            context: context,
            controller: _phoneController,
            label: '전화번호',
            hint: '01012345678',
            icon: Icons.phone_outlined,
            keyboardType: TextInputType.phone,
            validator: (value) {
              if (value == null || value.isEmpty) return '전화번호를 입력해주세요';
              if (value.length < 10) return '올바른 전화번호를 입력해주세요';
              return null;
            },
          ),
        ],
      ),
    );
  }

  /// 주소 섹션
  Widget _buildAddressSection() {
    return Container(
      padding: ResponsiveHelper.cardPadding(context),
      decoration: CommonWidgets.cardDecoration(),
      child: Column(
        children: [
          // 주소
          if (kIsWeb)
            CommonWidgets.textField(
              context: context,
              controller: _addressController,
              label: '주소',
              hint: '주소를 직접 입력해주세요',
              icon: Icons.location_on_outlined,
            )
          else
            CommonWidgets.textField(
              context: context,
              controller: _addressController,
              label: '주소',
              hint: '주소 검색 버튼을 눌러주세요',
              icon: Icons.location_on_outlined,
              readOnly: true,
              onTap: _searchAddress,
              suffixIcon: IconButton(
                onPressed: _searchAddress,
                icon: Icon(
                  Icons.search,
                  color: Theme.of(context).primaryColor,
                ),
              ),
            ),

          SizedBox(height: ResponsiveHelper.spacing(context, 16)),

          // 상세주소
          CommonWidgets.textField(
            context: context,
            controller: _detailAddressController,
            label: '상세주소',
            hint: '동/호수 입력',
            icon: Icons.home_outlined,
          ),
        ],
      ),
    );
  }

  /// 보안 섹션
  Widget _buildSecuritySection() {
    final theme = Theme.of(context);

    return Container(
      decoration: CommonWidgets.cardDecoration(),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _showPasswordChangeDialog,
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: ResponsiveHelper.cardPadding(context),
            child: Row(
              children: [
                Container(
                  padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 12)),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.lock_outline,
                    color: Colors.orange[700],
                    size: ResponsiveHelper.iconSize(context, 24),
                  ),
                ),
                SizedBox(width: ResponsiveHelper.spacing(context, 16)),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '비밀번호 변경',
                        style: ResponsiveHelper.bodyStyle(context).copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      SizedBox(height: ResponsiveHelper.spacing(context, 4)),
                      Text(
                        '계정 보안을 위해 주기적으로 변경하세요',
                        style: ResponsiveHelper.smallStyle(context).copyWith(
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right,
                  color: Colors.grey[400],
                  size: ResponsiveHelper.iconSize(context, 24),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 정보 행
  Widget _buildInfoRow({
    required IconData icon,
    required String label,
    required String value,
  }) {
    final theme = Theme.of(context);

    return Padding(
      padding: EdgeInsets.symmetric(
        vertical: ResponsiveHelper.spacing(context, 12),
      ),
      child: Row(
        children: [
          Icon(
            icon,
            size: ResponsiveHelper.iconSize(context, 20),
            color: theme.primaryColor.withOpacity(0.7),
          ),
          SizedBox(width: ResponsiveHelper.spacing(context, 12)),
          Text(
            label,
            style: ResponsiveHelper.bodyStyle(context).copyWith(
              color: Colors.grey[600],
            ),
          ),
          const Spacer(),
          Text(
            value,
            style: ResponsiveHelper.bodyStyle(context).copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  /// 구분선
  Widget _buildDivider() {
    return Divider(
      height: 1,
      color: Colors.grey[200],
    );
  }
}