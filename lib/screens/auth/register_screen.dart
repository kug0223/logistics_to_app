import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/user_model.dart';
import '../../providers/user_provider.dart';
import '../../widgets/custom_button.dart';
import '../../widgets/loading_widget.dart';
import '../admin/business_registration_screen.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({Key? key}) : super(key: key);

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  int _currentStep = 0;
  
  // Step 1: 기본 정보
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
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
            const SizedBox(width: 12),
            const Text('사업장 등록'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '사업장 관리자는 사업장 정보가 필요합니다.',
              style: TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '지금 등록하기',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.blue[900],
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '• TO를 바로 생성할 수 있습니다\n• 지원자를 바로 관리할 수 있습니다',
                    style: TextStyle(fontSize: 13, color: Colors.grey[700]),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '나중에 등록하기',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.grey[900],
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '• 로그인 후 홈 화면에서 등록 가능\n• TO 생성은 사업장 등록 후 가능',
                    style: TextStyle(fontSize: 13, color: Colors.grey[700]),
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
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
            child: const Text(
              '지금 등록하기',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
          OutlinedButton(
            onPressed: () {
              Navigator.pop(context);
              _registerUser();
            },
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
            child: const Text(
              '나중에 등록하기',
              style: TextStyle(fontSize: 16),
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
                    padding: const EdgeInsets.only(top: 24.0),
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
                                padding: const EdgeInsets.symmetric(vertical: 16),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                              child: const Text('이전'),
                            ),
                          ),
                          const SizedBox(width: 12),
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
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const SizedBox(height: 16),
                          
                          // 안내 문구
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.blue[50],
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.info_outline, color: Colors.blue[700]),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    '기본 정보를 입력해주세요',
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: Colors.blue[700],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 24),

                          // 이름 입력
                          TextFormField(
                            controller: _nameController,
                            decoration: InputDecoration(
                              labelText: '이름',
                              hintText: '홍길동',
                              prefixIcon: const Icon(Icons.person_outline),
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
                              if (value.length < 2) {
                                return '이름은 2자 이상이어야 합니다';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 16),

                          // 이메일 입력
                          TextFormField(
                            controller: _emailController,
                            keyboardType: TextInputType.emailAddress,
                            decoration: InputDecoration(
                              labelText: '이메일',
                              hintText: 'example@email.com',
                              prefixIcon: const Icon(Icons.email_outlined),
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
                                return '유효한 이메일을 입력해주세요';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 16),

                          // 비밀번호 입력
                          TextFormField(
                            controller: _passwordController,
                            obscureText: _obscurePassword,
                            decoration: InputDecoration(
                              labelText: '비밀번호',
                              hintText: '6자 이상 입력',
                              prefixIcon: const Icon(Icons.lock_outline),
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
                          const SizedBox(height: 16),

                          // 비밀번호 확인
                          TextFormField(
                            controller: _confirmPasswordController,
                            obscureText: _obscureConfirmPassword,
                            decoration: InputDecoration(
                              labelText: '비밀번호 확인',
                              hintText: '비밀번호 재입력',
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
                          const SizedBox(height: 16),
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
                        const SizedBox(height: 16),
                        
                        // 안내 문구
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.amber[50],
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.help_outline, color: Colors.amber[700]),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  '어떻게 이용하시나요?',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.amber[900],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),

                        // 일반 지원자 카드
                        _buildRoleCard(
                          role: UserRole.USER,
                          icon: Icons.person,
                          title: '일반 지원자',
                          description: 'TO에 지원하고 싶어요',
                          features: [
                            'TO 지원하기',
                            '내 지원 내역 확인',
                            '출퇴근 체크',
                          ],
                          color: Colors.blue,
                        ),
                        
                        const SizedBox(height: 16),

                        // 사업장 관리자 카드
                        _buildRoleCard(
                          role: UserRole.BUSINESS_ADMIN,
                          icon: Icons.business,
                          title: '사업장 관리자',
                          description: 'TO를 등록하고 싶어요',
                          features: [
                            'TO 생성 및 관리',
                            '지원자 승인/거절',
                            '사업장 정보 관리',
                          ],
                          color: Colors.green,
                        ),
                        
                        const SizedBox(height: 24),

                        // 약관 동의 안내
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.grey[100],
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '회원가입 시 개인정보 처리방침 및\n서비스 이용약관에 동의하게 됩니다.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 12,
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
          },
        ),
      ),
    );
  }

  // 역할 선택 카드 위젯
  Widget _buildRoleCard({
    required UserRole role,
    required IconData icon,
    required String title,
    required String description,
    required List<String> features,
    required Color color,
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
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: isSelected ? color.withOpacity(0.1) : Colors.white,
          border: Border.all(
            color: isSelected ? color : Colors.grey[300]!,
            width: isSelected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(12),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: color.withOpacity(0.2),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                // 아이콘
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isSelected ? color : color.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    icon,
                    color: isSelected ? Colors.white : color,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 16),
                
                // 제목과 설명
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: isSelected ? color : Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        description,
                        style: TextStyle(
                          fontSize: 14,
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
                    size: 28,
                  )
                else
                  Icon(
                    Icons.radio_button_unchecked,
                    color: Colors.grey[400],
                    size: 28,
                  ),
              ],
            ),
            
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 12),
            
            // 기능 목록
            ...features.map((feature) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Icon(
                    Icons.check,
                    size: 16,
                    color: isSelected ? color : Colors.grey[600],
                  ),
                  const SizedBox(width: 8),
                  Text(
                    feature,
                    style: TextStyle(
                      fontSize: 14,
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