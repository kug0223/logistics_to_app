import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter/services.dart';
import '../../models/core/user_model.dart';
import '../../providers/user_provider.dart';
import '../../widgets/buttons/custom_button.dart';
import '../../widgets/common/loading_widget.dart';
import '../../utils/responsive_helper.dart';  // ⭐ 추가
import '../business_admin/business_registration_screen.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  int _currentStep = 0;
  
  // Step 1: 기본 정보
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;

  // Step 2: 역할 선택
  UserRole? _selectedRole;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  // Step 1 검증
  bool _validateStep1() {
    return _formKey.currentState?.validate() ?? false;
  }

  // Step 2 검증
  bool _validateStep2() {
    if (_selectedRole == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('이용 방법을 선택해주세요'),
          backgroundColor: Colors.orange,
        ),
      );
      return false;
    }
    return true;
  }

  // 다음 단계로
  void _onStepContinue() {
    if (_currentStep == 0) {
      if (_validateStep1()) {
        setState(() => _currentStep = 1);
      }
    } else if (_currentStep == 1) {
      if (_validateStep2()) {
        _handleRoleSelection();
      }
    }
  }

  // 이전 단계로
  void _onStepCancel() {
    if (_currentStep > 0) {
      setState(() => _currentStep -= 1);
    }
  }

  // 역할 선택 후 처리
  Future<void> _handleRoleSelection() async {
    if (_selectedRole == UserRole.USER) {
      // ✅ 일반 사용자: 바로 회원가입 진행
      await _registerUser();
    } else if (_selectedRole == UserRole.BUSINESS_ADMIN) {
      // ✅ 사업장 관리자: 사업장 등록 선택 다이얼로그 표시
      _showBusinessRegistrationDialog();
    }
  }

  // 사업장 등록 선택 다이얼로그
  void _showBusinessRegistrationDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.business, color: Colors.blue[700]),
            SizedBox(width: ResponsiveHelper.spacing(context, 12)),
            const Text('사업장 등록'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '사업장 관리자는 사업장 정보가 필요합니다.',
              style: ResponsiveHelper.subtitleStyle(context),
            ),
            SizedBox(height: ResponsiveHelper.spacing(context, 12)),
            Container(
              padding: ResponsiveHelper.cardPadding(context),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '지금 등록하기',
                    style: ResponsiveHelper.bodyStyle(
                      context,
                      color: Colors.blue[900],
                    ).copyWith(fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: ResponsiveHelper.spacing(context, 4)),
                  Text(
                    '• TO를 바로 생성할 수 있습니다\n• 지원자를 바로 관리할 수 있습니다',
                    style: ResponsiveHelper.smallStyle(
                      context,
                      color: Colors.grey[700],
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: ResponsiveHelper.spacing(context, 8)),
            Container(
              padding: ResponsiveHelper.cardPadding(context),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '나중에 등록하기',
                    style: ResponsiveHelper.bodyStyle(
                      context,
                      color: Colors.grey[900],
                    ).copyWith(fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: ResponsiveHelper.spacing(context, 4)),
                  Text(
                    '• 로그인 후 홈 화면에서 등록 가능\n• TO 생성은 사업장 등록 후 가능',
                    style: ResponsiveHelper.smallStyle(
                      context,
                      color: Colors.grey[700],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _registerUserAndGoToBusinessRegistration();
            },
            style: TextButton.styleFrom(
              padding: EdgeInsets.symmetric(
                horizontal: ResponsiveHelper.spacing(context, 24),
                vertical: ResponsiveHelper.spacing(context, 12),
              ),
            ),
            child: Text(
              '지금 등록하기',
              style: ResponsiveHelper.subtitleStyle(
                context,
              ).copyWith(fontWeight: FontWeight.bold),
            ),
          ),
          OutlinedButton(
            onPressed: () {
              Navigator.pop(context);
              _registerUser();
            },
            style: OutlinedButton.styleFrom(
              padding: EdgeInsets.symmetric(
                horizontal: ResponsiveHelper.spacing(context, 24),
                vertical: ResponsiveHelper.spacing(context, 12),
              ),
            ),
            child: Text(
              '나중에 등록하기',
              style: ResponsiveHelper.subtitleStyle(context),
            ),
          ),
        ],
      ),
    );
  }

  // ✅ 일반 사용자 회원가입 (바로 Firebase 저장)
  Future<void> _registerUser() async {
    final userProvider = context.read<UserProvider>();
    
    final success = await userProvider.signUp(
      email: _emailController.text.trim(),
      password: _passwordController.text,
      name: _nameController.text.trim(),
      phone: _phoneController.text.trim(),
      role: _selectedRole!,
    );

    if (success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('회원가입이 완료되었습니다! 로그인해주세요.'),
          backgroundColor: Colors.green,
        ),
      );
      Navigator.pop(context); // 로그인 화면으로
    }
  }

  // ✅ 사업장 관리자: 회원가입 후 사업장 등록 화면으로
  Future<void> _registerUserAndGoToBusinessRegistration() async {
    final userProvider = context.read<UserProvider>();
    
    final success = await userProvider.signUp(
      email: _emailController.text.trim(),
      password: _passwordController.text,
      name: _nameController.text.trim(),
      phone: _phoneController.text.trim(),
      role: UserRole.BUSINESS_ADMIN,
    );

    if (success && mounted) {
      // 사업장 등록 화면으로 이동
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => BusinessRegistrationScreen(
            isFromSignUp: true, // ✅ 회원가입에서 온 것 표시
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('회원가입'),
        elevation: 0,
      ),
      body: SafeArea(
        child: Consumer<UserProvider>(
          builder: (context, userProvider, _) {
            return LoadingOverlay(
              isLoading: userProvider.isLoading,
              message: '회원가입 중...',
              child: Stepper(
                currentStep: _currentStep,
                onStepContinue: _onStepContinue,
                onStepCancel: _onStepCancel,
                controlsBuilder: (context, details) {
                  return Padding(
                    padding: EdgeInsets.only(
                      top: ResponsiveHelper.spacing(context, 24),
                    ),
                    child: Row(
                      children: [
                        if (_currentStep == 0)
                          Expanded(
                            child: CustomButton(
                              text: '다음',
                              onPressed: details.onStepContinue,
                              isLoading: false,
                            ),
                          )
                        else ...[
                          Expanded(
                            child: OutlinedButton(
                              onPressed: details.onStepCancel,
                              style: OutlinedButton.styleFrom(
                                padding: EdgeInsets.symmetric(
                                  vertical: ResponsiveHelper.spacing(context, 16),
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                              child: const Text('이전'),
                            ),
                          ),
                          SizedBox(width: ResponsiveHelper.spacing(context, 12)),
                          Expanded(
                            child: CustomButton(
                              text: '선택하기',
                              onPressed: details.onStepContinue,
                              isLoading: userProvider.isLoading,
                            ),
                          ),
                        ],
                      ],
                    ),
                  );
                },
                steps: [
                  // Step 1: 기본 정보 입력
                  Step(
                    title: const Text('기본 정보'),
                    subtitle: const Text('이름, 이메일, 비밀번호'),
                    isActive: _currentStep >= 0,
                    state: _currentStep > 0 ? StepState.complete : StepState.indexed,
                    content: Form(
                      key: _formKey,
                      child: Column(
                        children: [
                          SizedBox(height: ResponsiveHelper.spacing(context, 16)),
                          
                          // 이름
                          TextFormField(
                            controller: _nameController,
                            decoration: InputDecoration(
                              labelText: '이름',
                              prefixIcon: const Icon(Icons.person),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                              filled: true,
                              fillColor: Colors.grey[50],
                            ),
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return '이름을 입력해주세요';
                              }
                              return null;
                            },
                          ),
                          SizedBox(height: ResponsiveHelper.spacing(context, 16)),
                          
                          // 이메일
                          TextFormField(
                            controller: _emailController,
                            keyboardType: TextInputType.emailAddress,
                            decoration: InputDecoration(
                              labelText: '이메일',
                              prefixIcon: const Icon(Icons.email),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                              filled: true,
                              fillColor: Colors.grey[50],
                            ),
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return '이메일을 입력해주세요';
                              }
                              if (!value.contains('@')) {
                                return '올바른 이메일 형식이 아닙니다';
                              }
                              return null;
                            },
                          ),
                          SizedBox(height: ResponsiveHelper.spacing(context, 16)),
                          
                          // 전화번호
                          TextFormField(
                            controller: _phoneController,
                            keyboardType: TextInputType.phone,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                              LengthLimitingTextInputFormatter(11),
                            ],
                            decoration: InputDecoration(
                              labelText: '전화번호',
                              hintText: '01012345678',
                              prefixIcon: const Icon(Icons.phone),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                              filled: true,
                              fillColor: Colors.grey[50],
                            ),
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return '전화번호를 입력해주세요';
                              }
                              if (value.length < 10) {
                                return '올바른 전화번호를 입력해주세요';
                              }
                              return null;
                            },
                          ),
                          SizedBox(height: ResponsiveHelper.spacing(context, 16)),
                          
                          // 비밀번호
                          TextFormField(
                            controller: _passwordController,
                            obscureText: _obscurePassword,
                            decoration: InputDecoration(
                              labelText: '비밀번호',
                              hintText: '6자 이상',
                              prefixIcon: const Icon(Icons.lock),
                              suffixIcon: IconButton(
                                icon: Icon(
                                  _obscurePassword
                                      ? Icons.visibility_off
                                      : Icons.visibility,
                                ),
                                onPressed: () {
                                  setState(() {
                                    _obscurePassword = !_obscurePassword;
                                  });
                                },
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                              filled: true,
                              fillColor: Colors.grey[50],
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
                          SizedBox(height: ResponsiveHelper.spacing(context, 16)),
                          
                          // 비밀번호 확인
                          TextFormField(
                            controller: _confirmPasswordController,
                            obscureText: _obscureConfirmPassword,
                            decoration: InputDecoration(
                              labelText: '비밀번호 확인',
                              prefixIcon: const Icon(Icons.lock_outline),
                              suffixIcon: IconButton(
                                icon: Icon(
                                  _obscureConfirmPassword
                                      ? Icons.visibility_off
                                      : Icons.visibility,
                                ),
                                onPressed: () {
                                  setState(() {
                                    _obscureConfirmPassword = !_obscureConfirmPassword;
                                  });
                                },
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                              filled: true,
                              fillColor: Colors.grey[50],
                            ),
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return '비밀번호를 다시 입력해주세요';
                              }
                              if (value != _passwordController.text) {
                                return '비밀번호가 일치하지 않습니다';
                              }
                              return null;
                            },
                          ),
                          SizedBox(height: ResponsiveHelper.spacing(context, 16)),
                        ],
                      ),
                    ),
                  ),

                  // Step 2: 역할 선택
                  Step(
                    title: const Text('이용 방법'),
                    subtitle: const Text('지원자 또는 사업장 관리자'),
                    isActive: _currentStep >= 1,
                    state: _currentStep > 1 ? StepState.complete : StepState.indexed,
                    content: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(height: ResponsiveHelper.spacing(context, 16)),
                        
                        // 안내 문구
                        Container(
                          padding: ResponsiveHelper.cardPadding(context),
                          decoration: BoxDecoration(
                            color: Colors.amber[50],
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.help_outline, color: Colors.amber[700]),
                              SizedBox(width: ResponsiveHelper.spacing(context, 12)),
                              Expanded(
                                child: Text(
                                  '어떻게 이용하시나요?',
                                  style: ResponsiveHelper.bodyStyle(
                                    context,
                                    color: Colors.amber[900],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        SizedBox(height: ResponsiveHelper.spacing(context, 24)),
                        
                        // 지원자 선택
                        _buildRoleCard(
                          context: context,
                          role: UserRole.USER,
                          icon: Icons.person,
                          title: '지원자로 이용',
                          description: 'TO에 지원하고 일정을 관리합니다',
                          color: Colors.green,
                          features: [
                            'TO 검색 및 지원',
                            '나의 일정 관리',
                            '지원 내역 확인',
                          ],
                        ),
                        SizedBox(height: ResponsiveHelper.spacing(context, 16)),
                        
                        // 사업장 관리자 선택
                        _buildRoleCard(
                          context: context,
                          role: UserRole.BUSINESS_ADMIN,
                          icon: Icons.business_center,
                          title: '사업장 관리자로 이용',
                          description: 'TO를 생성하고 지원자를 관리합니다',
                          color: Colors.blue,
                          features: [
                            'TO 생성 및 관리',
                            '지원자 승인/거절',
                            '인력 현황 파악',
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  /// 역할 선택 카드
  Widget _buildRoleCard({
    required BuildContext context,
    required UserRole role,
    required IconData icon,
    required String title,
    required String description,
    required Color color,
    required List<String> features,
  }) {
    final isSelected = _selectedRole == role;
    
    return InkWell(
      onTap: () {
        setState(() {
          _selectedRole = role;
        });
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: ResponsiveHelper.cardPadding(context),
        decoration: BoxDecoration(
          color: isSelected ? color.withOpacity(0.1) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? color : Colors.grey[300]!,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 아이콘과 제목
            Row(
              children: [
                // 아이콘
                Container(
                  padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 12)),
                  decoration: BoxDecoration(
                    color: isSelected ? color : Colors.grey[200],
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    icon,
                    color: isSelected ? Colors.white : color,
                    size: ResponsiveHelper.iconSize(context, 28),
                  ),
                ),
                SizedBox(width: ResponsiveHelper.spacing(context, 16)),
                
                // 제목과 설명
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: ResponsiveHelper.subtitleStyle(
                          context,
                          color: isSelected ? color : Colors.black87,
                        ),
                      ),
                      SizedBox(height: ResponsiveHelper.spacing(context, 4)),
                      Text(
                        description,
                        style: ResponsiveHelper.bodyStyle(
                          context,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
                
                // 선택 표시
                if (isSelected)
                  Icon(
                    Icons.check_circle,
                    color: color,
                    size: ResponsiveHelper.iconSize(context, 28),
                  )
                else
                  Icon(
                    Icons.radio_button_unchecked,
                    color: Colors.grey[400],
                    size: ResponsiveHelper.iconSize(context, 28),
                  ),
              ],
            ),
            
            SizedBox(height: ResponsiveHelper.spacing(context, 16)),
            const Divider(),
            SizedBox(height: ResponsiveHelper.spacing(context, 12)),
            
            // 기능 목록
            ...features.map((feature) => Padding(
              padding: EdgeInsets.only(
                bottom: ResponsiveHelper.spacing(context, 8),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.check,
                    size: ResponsiveHelper.iconSize(context, 16),
                    color: isSelected ? color : Colors.grey[600],
                  ),
                  SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                  Text(
                    feature,
                    style: ResponsiveHelper.bodyStyle(
                      context,
                      color: isSelected ? Colors.black87 : Colors.grey[700],
                    ),
                  ),
                ],
              ),
            )),
          ],
        ),
      ),
    );
  }
}