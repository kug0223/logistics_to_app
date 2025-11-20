import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter/services.dart';
import '../../models/core/user_model.dart';
import '../../providers/user_provider.dart';
import '../../widgets/common/loading_widget.dart';
import '../../utils/responsive_helper.dart';
import '../../services/auth_service.dart';
import '../business_admin/business_registration_screen.dart';

/// 개선된 회원가입 화면 - 주민번호 기반 + 이메일 인증 + 서류 업로드
class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  int _currentStep = 0;
  // State 변수 추가
  int _passwordStrength = 0; // 0: 약함, 1: 보통, 2: 강함
  
  // Step 1: 기본 정보
  final _usernameController = TextEditingController();
  bool _isCheckingUsername = false;
  bool _isUsernameAvailable = false;
  String? _usernameError;
  String _currentUsername = '';
  String _currentEmail = '';
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _residentNumber1Controller = TextEditingController(); // 앞 6자리
  final _residentNumber2Controller = TextEditingController(); // 뒷 1자리
  final _emailController = TextEditingController();
  final _emailCodeController = TextEditingController(); // 이메일 인증 코드
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  
  // 이메일 인증 상태
  bool _isEmailSent = false;
  bool _isEmailVerified = false;
  String? _verificationCode; // 실제로는 서버에서 생성/확인
  
  // 주민번호로 파싱된 정보
  DateTime? _parsedBirthDate;
  String? _parsedGender;
  String? _residentNumberError;

  // Step 2: 역할 선택
  UserRole? _selectedRole;
  
  // Step 3: 추가 정보 (선택)
  String? _idCardImagePath;
  String? _bankbookImagePath;

  @override
  void dispose() {
    _usernameController.dispose();
    _nameController.dispose();
    _residentNumber1Controller.dispose();
    _residentNumber2Controller.dispose();
    _emailController.dispose();
    _emailCodeController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  /// 주민번호로 생년월일과 성별 파싱
  void _parseResidentNumber() {
    final rn1 = _residentNumber1Controller.text;
    final rn2 = _residentNumber2Controller.text;
    
    if (rn1.length == 6 && rn2.length >= 1) {
      try {
        int year = int.parse(rn1.substring(0, 2));
        int month = int.parse(rn1.substring(2, 4));
        int day = int.parse(rn1.substring(4, 6));
        int genderCode = int.parse(rn2[0]);
        
        // 1차: 성별 코드 유효성 체크
        if (genderCode < 1 || genderCode > 4) {
          setState(() {
            _parsedBirthDate = null;
            _parsedGender = null;
            _residentNumberError = '뒷자리는 1~4만 가능합니다';  // ⭐
          });
          return;
        }
        
        // 2차: 연도와 성별 코드 매칭 검증
        if (genderCode == 1 || genderCode == 2) {
          // 1, 2 = 1900년대생
          year += 1900;
        } else if (genderCode == 3 || genderCode == 4) {
          // 3, 4 = 2000년대생
          final currentYear = DateTime.now().year;
          final twoDigitCurrentYear = currentYear % 100;
          
          if (year > twoDigitCurrentYear) {
            setState(() {
              _parsedBirthDate = null;
              _parsedGender = null;
              _residentNumberError = '2000년대생은 00~${twoDigitCurrentYear.toString().padLeft(2, '0')}년생만 가능합니다';  // ⭐
            });
            return;
          }
          year += 2000;
        }
        
        // ⭐ 추가: 1900년대생인데 3,4 사용한 경우
        if ((genderCode == 3 || genderCode == 4) && year < 2000) {
          setState(() {
            _parsedBirthDate = null;
            _parsedGender = null;
            _residentNumberError = '${year}년생은 뒷자리 1 또는 2를 사용해야 합니다';
          });
          return;
        }
        
        // ⭐ 추가: 2000년대생인데 1,2 사용한 경우
        if ((genderCode == 1 || genderCode == 2) && year >= 2000) {
          setState(() {
            _parsedBirthDate = null;
            _parsedGender = null;
            _residentNumberError = '${year}년생은 뒷자리 3 또는 4를 사용해야 합니다';
          });
          return;
        }
        
        // 3차: 날짜 유효성 체크
        try {
          _parsedBirthDate = DateTime(year, month, day);
        } catch (e) {
          setState(() {
            _parsedBirthDate = null;
            _parsedGender = null;
            _residentNumberError = '존재하지 않는 날짜입니다 ($year년 $month월 $day일)';  // ⭐
          });
          return;
        }
        
        // ⭐ 성공!
        _parsedGender = (genderCode == 1 || genderCode == 3) ? '남성' : '여성';
        setState(() {
          _residentNumberError = null;  // ⭐ 에러 초기화
        });
        
        print('✅ 주민번호 파싱 성공: $_parsedBirthDate, $_parsedGender');
      } catch (e) {
        print('❌ 주민번호 파싱 실패: $e');
        setState(() {
          _parsedBirthDate = null;
          _parsedGender = null;
          _residentNumberError = '올바른 주민번호를 입력해주세요';  // ⭐
        });
      }
    } else {
      // ⭐ 입력 불완전
      setState(() {
        _parsedBirthDate = null;
        _parsedGender = null;
        _residentNumberError = null;  // 입력 중에는 에러 안 보임
      });
    }
  }

  /// 이메일 인증 코드 발송 (시뮬레이션)
  Future<void> _sendEmailVerification() async {
    if (_emailController.text.isEmpty || !_emailController.text.contains('@')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('올바른 이메일을 입력해주세요')),
      );
      return;
    }
    
    setState(() => _isEmailSent = true);
    
    // TODO: 실제로는 서버에서 이메일 발송
    // 개발 단계에서는 고정 코드 사용
    _verificationCode = '123456';
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('인증번호가 ${_emailController.text}로 발송되었습니다\n(개발용: 123456)'),
        duration: const Duration(seconds: 5),
      ),
    );
  }

  /// 이메일 인증 코드 확인
  void _verifyEmailCode() {
    if (_emailCodeController.text == _verificationCode) {
      setState(() => _isEmailVerified = true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('이메일 인증이 완료되었습니다'),
          backgroundColor: Colors.green,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('인증번호가 일치하지 않습니다'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // Step 검증
  bool _validateStep1() {
    if (!(_formKey.currentState?.validate() ?? false)) return false;
    
    _parseResidentNumber();
    if (_parsedBirthDate == null || _parsedGender == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('올바른 주민번호를 입력해주세요')),
      );
      return false;
    }
    
    if (!_isEmailVerified) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('이메일 인증을 완료해주세요')),
      );
      return false;
    }
    
    return true;
  }

  bool _validateStep2() {
    if (_selectedRole == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('이용 방법을 선택해주세요'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
      return false;
    }
    return true;
  }

  // 다음/이전 단계
  void _onStepContinue() {
    if (_currentStep == 0) {
      if (_validateStep1()) {
        setState(() => _currentStep = 1);
      }
    } else if (_currentStep == 1) {
      if (_validateStep2()) {
        setState(() => _currentStep = 2);
      }
    } else if (_currentStep == 2) {
      // Step 3: 추가 정보는 선택사항
      _handleRoleSelection();
    }
  }

  void _onStepCancel() {
    if (_currentStep > 0) {
      setState(() => _currentStep -= 1);
    } else {
      Navigator.pop(context);
    }
  }

  // 역할 선택 후 처리
  Future<void> _handleRoleSelection() async {
    if (_selectedRole == UserRole.USER) {
      await _registerUser();
    } else if (_selectedRole == UserRole.BUSINESS_ADMIN) {
      _showBusinessRegistrationDialog();
    }
  }

  // 사업장 등록 선택 다이얼로그
  void _showBusinessRegistrationDialog() {
    final theme = Theme.of(context);
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        title: Row(
          children: [
            Icon(Icons.business, color: theme.primaryColor),
            SizedBox(width: ResponsiveHelper.spacing(context, 12)),
            Text('사업장 등록', style: ResponsiveHelper.titleStyle(context)),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('사업장 정보를 지금 등록하시겠습니까?', style: ResponsiveHelper.bodyStyle(context)),
              SizedBox(height: ResponsiveHelper.spacing(context, 20)),
              Container(
                padding: ResponsiveHelper.cardPadding(context),
                decoration: BoxDecoration(
                  color: theme.primaryColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: theme.primaryColor.withOpacity(0.3)),
                ),
                child: Text(
                  '지금 등록하시면 TO를 바로 생성하고 지원자를 관리할 수 있습니다.',
                  style: ResponsiveHelper.smallStyle(context),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _registerUser();
            },
            child: Text('나중에', style: ResponsiveHelper.bodyStyle(context)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _registerUserAndGoToBusinessRegistration();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: theme.primaryColor,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: Text(
              '지금 등록',
              style: ResponsiveHelper.bodyStyle(context).copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _registerUser() async {
    final userProvider = context.read<UserProvider>();
    
    final success = await userProvider.signUp(
      username: _usernameController.text.trim(),  // ⭐ 추가됨
      userEmail: _emailController.text.trim(),    // ⭐ email → userEmail
      password: _passwordController.text,
      name: _nameController.text.trim(),
      phone: _phoneController.text.trim(),
      role: _selectedRole!,
      gender: _parsedGender,
      birthDate: _parsedBirthDate,
      residentNumber: '${_residentNumber1Controller.text}-${_residentNumber2Controller.text}******',
      idCardImageUrl: _idCardImagePath,
    );

    if (success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('회원가입이 완료되었습니다! 로그인해주세요.'),
          backgroundColor: Colors.green[600],
        ),
      );
      Navigator.pop(context);
    }
  }
  
  // 비밀번호 강도 체크 함수
  void _checkPasswordStrength(String password) {
    // ⭐ 비어있으면 0으로 초기화
    if (password.isEmpty) {
      setState(() => _passwordStrength = 0);
      return;
    }
    int strength = 0;
    
    if (password.length >= 8) strength++;
    if (RegExp(r'[a-zA-Z]').hasMatch(password) && RegExp(r'[0-9]').hasMatch(password)) strength++;
    if (RegExp(r'[!@#$%^&*(),.?":{}|<>]').hasMatch(password)) strength++;
    
    setState(() => _passwordStrength = strength);
  }
  // 비밀번호 검증강화
  String? _validatePassword(String? value) {
    if (value == null || value.isEmpty) {
      return '비밀번호를 입력해주세요';
    }
    
    if (value.length < 8) {
      return '비밀번호는 8자 이상이어야 합니다';
    }
    
    // 영문 포함 체크
    if (!RegExp(r'[a-zA-Z]').hasMatch(value)) {
      return '영문을 포함해야 합니다';
    }
    
    // 숫자 포함 체크
    if (!RegExp(r'[0-9]').hasMatch(value)) {
      return '숫자를 포함해야 합니다';
    }
    
    // 특수문자 포함 체크 (선택사항 - 더 강력한 보안)
    if (!RegExp(r'[!@#$%^&*(),.?":{}|<>]').hasMatch(value)) {
      return '특수문자를 포함해야 합니다';
    }
    
    return null;
  }

  // 사업장 관리자: 회원가입 후 사업장 등록 화면으로
  Future<void> _registerUserAndGoToBusinessRegistration() async {
    final userProvider = context.read<UserProvider>();
    
    final success = await userProvider.signUp(
      username: _usernameController.text.trim(),
      userEmail: _emailController.text.trim(),
      password: _passwordController.text,
      name: _nameController.text.trim(),
      phone: _phoneController.text.trim(),
      role: UserRole.BUSINESS_ADMIN,
      gender: _parsedGender,
      birthDate: _parsedBirthDate,
      residentNumber: '${_residentNumber1Controller.text}-${_residentNumber2Controller.text}******',
    );

    if (success && mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => const BusinessRegistrationScreen(isFromSignUp: true),
        ),
      );
    }
  }
  Future<void> _checkUsername() async {
    final username = _usernameController.text.trim();
    
    if (username.length < 4) {
      setState(() {
        _isUsernameAvailable = false;
        _usernameError = '4자 이상 입력하세요';
      });
      return;
    }
    
    setState(() => _isCheckingUsername = true);
    
    final authService = AuthService();
    final exists = await authService.checkUsernameExists(username);
    
    setState(() {
      _isCheckingUsername = false;
      _isUsernameAvailable = !exists;
      _usernameError = exists ? '이미 사용중인 아이디입니다' : null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Scaffold(
      body: Consumer<UserProvider>(
        builder: (context, userProvider, _) {
          return LoadingOverlay(
            isLoading: userProvider.isLoading,
            message: '회원가입 중...',
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
              child: SafeArea(
                child: Column(
                  children: [
                    _buildHeader(),
                    _buildProgressBar(),
                    SizedBox(height: ResponsiveHelper.spacing(context, 24)),
                    Expanded(
                      child: SingleChildScrollView(
                        padding: EdgeInsets.symmetric(
                          horizontal: ResponsiveHelper.spacing(context, 24),
                        ),
                        child: _buildCurrentStep(),
                      ),
                    ),
                    _buildBottomButton(),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  /// 헤더
  Widget _buildHeader() {
    final theme = Theme.of(context);
    
    return Padding(
      padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 16)),
      child: Row(
        children: [
          Material(
            color: Colors.white.withOpacity(0.3),
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              onTap: _onStepCancel,
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 8)),
                child: Icon(
                  Icons.arrow_back,
                  color: theme.primaryColor,
                  size: ResponsiveHelper.iconSize(context, 24),
                ),
              ),
            ),
          ),
          SizedBox(width: ResponsiveHelper.spacing(context, 16)),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '회원가입',
                style: ResponsiveHelper.titleStyle(context).copyWith(
                  fontWeight: FontWeight.bold,
                  fontSize: ResponsiveHelper.titleStyle(context).fontSize! * 1.3,
                ),
              ),
              SizedBox(height: ResponsiveHelper.spacing(context, 4)),
              Text(
                _currentStep == 0
                    ? '기본 정보 입력'
                    : _currentStep == 1
                        ? '이용 방법 선택'
                        : '추가 정보 (선택)',
                style: ResponsiveHelper.smallStyle(
                  context,
                  color: Colors.grey[600],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 진행 표시기
  Widget _buildProgressBar() {
    final theme = Theme.of(context);
    
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 40),
      ),
      child: Row(
        children: [
          Expanded(
            child: Container(
              height: ResponsiveHelper.spacing(context, 4),
              decoration: BoxDecoration(
                color: theme.primaryColor,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          SizedBox(width: ResponsiveHelper.spacing(context, 8)),
          Expanded(
            child: Container(
              height: ResponsiveHelper.spacing(context, 4),
              decoration: BoxDecoration(
                color: _currentStep >= 1 ? theme.primaryColor : Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          SizedBox(width: ResponsiveHelper.spacing(context, 8)),
          Expanded(
            child: Container(
              height: ResponsiveHelper.spacing(context, 4),
              decoration: BoxDecoration(
                color: _currentStep >= 2 ? theme.primaryColor : Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 현재 단계 컨텐츠
  Widget _buildCurrentStep() {
    switch (_currentStep) {
      case 0:
        return _buildStep1BasicInfo();
      case 1:
        return _buildStep2RoleSelection();
      case 2:
        // 역할에 따라 다른 화면 표시
        if (_selectedRole == UserRole.USER) {
          return _buildStep3UserDocuments();      // 지원자용
        } else if (_selectedRole == UserRole.BUSINESS_ADMIN) {
          return _buildStep3BusinessDocuments();  // 사업자용
        }
        return Container();
      default:
        return Container();
    }
  }

  /// Step 1: 기본 정보 + 주민번호 + 이메일 인증
  Widget _buildStep1BasicInfo() {
    return Container(
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
          children: [
            // 이름
            _buildTextField(
              controller: _nameController,
              label: '이름',
              hint: '홍길동',
              icon: Icons.person_outline,
              validator: (value) {
                if (value == null || value.isEmpty) return '이름을 입력해주세요';
                return null;
              },
            ),
            
            SizedBox(height: ResponsiveHelper.spacing(context, 16)),
            
            // 아이디
            _buildTextField(
              controller: _usernameController,
              label: '아이디',
              hint: '영문소문자, 숫자 (4-20자)',
              icon: Icons.account_circle_outlined,
              suffixIcon: _currentUsername.isEmpty
                  ? null
                  : _isCheckingUsername
                      ? SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : _isUsernameAvailable
                          ? Icon(
                              Icons.check_circle,
                              color: Colors.green,
                              size: ResponsiveHelper.iconSize(context, 24),
                            )
                          : TextButton(
                              onPressed: () {
                                final username = _usernameController.text.trim();
                                if (username.length >= 4 && RegExp(r'^[a-z0-9_]+$').hasMatch(username)) {
                                  _checkUsername();
                                } else {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('아이디를 올바르게 입력해주세요\n(영문 소문자, 숫자, _ / 4자 이상)'),
                                      duration: Duration(seconds: 2),
                                    ),
                                  );
                                }
                              },
                              child: Text(
                                '중복확인',
                                style: ResponsiveHelper.smallStyle(
                                  context,
                                  color: Theme.of(context).primaryColor,
                                ),
                              ),
                            ),
              validator: (value) {
                if (value == null || value.isEmpty) return '아이디를 입력해주세요';
                if (value.length < 4) return '4자 이상 입력해주세요';
                if (!RegExp(r'^[a-z0-9_]+$').hasMatch(value)) {
                  return '영문 소문자, 숫자, _만 사용 가능';
                }
                if (!_isUsernameAvailable) return '중복 확인을 해주세요';
                return null;
              },
              onChanged: (value) {
                setState(() {
                  _currentUsername = value;
                  _isUsernameAvailable = false;
                  _usernameError = null;
                });
              },
            ),
            SizedBox(height: ResponsiveHelper.spacing(context, 16)),
            
            // 주민번호
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: TextFormField(
                    controller: _residentNumber1Controller,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(6),
                    ],
                    style: ResponsiveHelper.bodyStyle(context),
                    decoration: InputDecoration(
                      hintText: '990101',
                      hintStyle: TextStyle(color: Colors.grey[400]),
                      prefixIcon: Icon(
                        Icons.credit_card,
                        color: Theme.of(context).primaryColor,
                        size: ResponsiveHelper.iconSize(context, 24),
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      filled: true,
                      fillColor: Colors.grey[50],
                    ),
                    validator: (value) {
                      if (value == null || value.length != 6) {
                        return '6자리';
                      }
                      return null;
                    },
                    onChanged: (value) {
                      if (value.length != 6) {
                        setState(() {
                          _parsedBirthDate = null;
                          _parsedGender = null;
                        });
                      } else {
                        _parseResidentNumber();
                      }
                    },
                  ),
                ),
                Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: ResponsiveHelper.spacing(context, 8),
                  ),
                  child: Text('-', style: ResponsiveHelper.titleStyle(context)),
                ),
                Expanded(
                  flex: 2,
                  child: TextFormField(
                    controller: _residentNumber2Controller,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(1),
                    ],
                    style: ResponsiveHelper.bodyStyle(context),
                    decoration: InputDecoration(
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      filled: true,
                      fillColor: Colors.grey[50],
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) return '필수';
                      
                      // ⭐ validator에서는 간단하게만
                      final genderCode = int.tryParse(value);
                      if (genderCode == null || genderCode < 1 || genderCode > 4) {
                        return null; // ⭐ 여기서는 에러 안 냄 (밑에서 표시)
                      }
                      
                      return null;
                    },
                    onChanged: (value) {
                      if (value.isEmpty) {
                        setState(() {
                          _parsedBirthDate = null;
                          _parsedGender = null;
                        });
                      } else {
                        _parseResidentNumber();
                      }
                    },
                  ),
                ),
                Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: ResponsiveHelper.spacing(context, 8),
                  ),
                  child: Text('●●●●●●', style: ResponsiveHelper.bodyStyle(context)),
                ),
              ],
            ),

            // 파싱 결과 표시 (성공 또는 오류)
            if (_residentNumber1Controller.text.length == 6 && 
                _residentNumber2Controller.text.isNotEmpty)
              Padding(
                padding: EdgeInsets.only(
                  top: ResponsiveHelper.spacing(context, 8),
                ),
                child: Container(
                  padding: ResponsiveHelper.cardPadding(context).copyWith(
                    top: ResponsiveHelper.spacing(context, 8),
                    bottom: ResponsiveHelper.spacing(context, 8),
                  ),
                  decoration: BoxDecoration(
                    color: _parsedBirthDate != null && _parsedGender != null
                        ? Colors.green[50]
                        : Colors.red[50],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _parsedBirthDate != null && _parsedGender != null
                            ? Icons.check_circle
                            : Icons.error_outline,
                        color: _parsedBirthDate != null && _parsedGender != null
                            ? Colors.green[700]
                            : Colors.red[700],
                        size: ResponsiveHelper.iconSize(context, 18),
                      ),
                      SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                      Expanded(
                        child: Text(
                          _parsedBirthDate != null && _parsedGender != null
                              ? '생년월일: ${_parsedBirthDate!.year}.${_parsedBirthDate!.month}.${_parsedBirthDate!.day} / 성별: $_parsedGender'
                              : _residentNumberError ?? '올바른 주민번호를 입력해주세요',  // ⭐ 변경!
                          style: ResponsiveHelper.smallStyle(
                            context,
                            color: _parsedBirthDate != null && _parsedGender != null
                                ? Colors.green[900]
                                : Colors.red[900],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            
            SizedBox(height: ResponsiveHelper.spacing(context, 16)),
            
            // 이메일
            _buildTextField(
              controller: _emailController,
              label: '이메일',
              hint: 'your@email.com',
              icon: Icons.email_outlined,
              keyboardType: TextInputType.emailAddress,
              suffixIcon: _currentEmail.isEmpty  // ⭐ 변경!
                  ? null
                  : !_isEmailVerified
                      ? TextButton(
                          onPressed: _sendEmailVerification,
                          child: Text(
                            _isEmailSent ? '재발송' : '인증',
                            style: ResponsiveHelper.smallStyle(
                              context,
                              color: Theme.of(context).primaryColor,
                            ),
                          ),
                        )
                      : Icon(
                          Icons.check_circle,
                          color: Colors.green[600],
                          size: ResponsiveHelper.iconSize(context, 24),
                        ),
              validator: (value) {
                if (value == null || value.isEmpty) return '이메일을 입력해주세요';
                if (!value.contains('@')) return '올바른 이메일 형식이 아닙니다';
                if (!_isEmailVerified) return '이메일 인증을 완료해주세요';
                return null;
              },
              onChanged: (value) {
                // ⭐ 이메일이 변경되면 상태 업데이트 + 인증 초기화
                setState(() {
                  _currentEmail = value;  // ⭐ 추가!
                  _isEmailSent = false;
                  _isEmailVerified = false;
                });
              },
            ),
            
            // 이메일 인증 코드 입력
            if (_isEmailSent && !_isEmailVerified) ...[
              SizedBox(height: ResponsiveHelper.spacing(context, 16)),
              _buildTextField(
                controller: _emailCodeController,
                label: '인증번호',
                hint: '6자리 숫자',
                icon: Icons.password,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(6),
                ],
                suffixIcon: TextButton(
                  onPressed: _verifyEmailCode,
                  child: Text(
                    '확인',
                    style: ResponsiveHelper.smallStyle(
                      context,
                      color: Theme.of(context).primaryColor,
                    ),
                  ),
                ),
              ),
            ],
            
            SizedBox(height: ResponsiveHelper.spacing(context, 16)),
            
            // 전화번호
            _buildTextField(
              controller: _phoneController,
              label: '전화번호',
              hint: '01012345678',
              icon: Icons.phone_outlined,
              keyboardType: TextInputType.phone,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(11),
              ],
              validator: (value) {
                if (value == null || value.isEmpty) return '전화번호를 입력해주세요';
                if (value.length < 10) return '올바른 전화번호를 입력해주세요';
                return null;
              },
            ),
            
            SizedBox(height: ResponsiveHelper.spacing(context, 16)),
            
            // 비밀번호
            _buildTextField(
              controller: _passwordController,
              label: '비밀번호',
              hint: '영문+숫자+특수문자 8자 이상',  // ⭐ 힌트 변경
              icon: Icons.lock_outline,
              obscureText: _obscurePassword,
              suffixIcon: IconButton(
                icon: Icon(
                  _obscurePassword ? Icons.visibility_off : Icons.visibility,
                  color: Colors.grey[600],
                  size: ResponsiveHelper.iconSize(context, 22),
                ),
                onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
              ),
              validator: _validatePassword,  // ⭐ 새 함수 사용
              onChanged: (value) {
                _checkPasswordStrength(value);  // ⭐ 강도 체크
              },
            ),
            // 비밀번호 강도 표시 (TextField 아래에 추가)
            if (_passwordStrength > 0) ...[
              SizedBox(height: ResponsiveHelper.spacing(context, 8)),
              Row(
                children: [
                  Expanded(
                    child: LinearProgressIndicator(
                      value: _passwordStrength / 3,
                      backgroundColor: Colors.grey[300],
                      color: _passwordStrength == 0
                          ? Colors.red
                          : _passwordStrength == 1
                              ? Colors.orange
                              : _passwordStrength == 2
                                  ? Colors.yellow
                                  : Colors.green,
                      minHeight: 4,
                    ),
                  ),
                  SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                  Text(
                    _passwordStrength == 0
                        ? '약함'
                        : _passwordStrength == 1
                            ? '보통'
                            : _passwordStrength == 2
                                ? '강함'
                                : '매우 강함',
                    style: ResponsiveHelper.smallStyle(
                      context,
                      color: _passwordStrength == 0
                          ? Colors.red
                          : _passwordStrength == 1
                              ? Colors.orange
                              : _passwordStrength == 2
                                  ? Colors.yellow[700]
                                  : Colors.green,
                    ),
                  ),
                ],
              ),
            ],

            SizedBox(height: ResponsiveHelper.spacing(context, 16)),

            // 비밀번호 확인
            _buildTextField(
              controller: _confirmPasswordController,
              label: '비밀번호 확인',
              hint: '비밀번호를 다시 입력',
              icon: Icons.lock_outline,
              obscureText: _obscureConfirmPassword,
              suffixIcon: IconButton(
                icon: Icon(
                  _obscureConfirmPassword ? Icons.visibility_off : Icons.visibility,
                  color: Colors.grey[600],
                  size: ResponsiveHelper.iconSize(context, 22),
                ),
                onPressed: () => setState(() => _obscureConfirmPassword = !_obscureConfirmPassword),
              ),
              validator: (value) {
                if (value == null || value.isEmpty) return '비밀번호를 다시 입력해주세요';
                if (value != _passwordController.text) return '비밀번호가 일치하지 않습니다';
                return null;
              },
            ),
          ],
        ),
      ),
    );
  }

  /// Step 2: 역할 선택 (기존과 동일)
  Widget _buildStep2RoleSelection() {
    // 이전 코드 그대로 사용
    return Column(
      children: [
        Container(
          padding: ResponsiveHelper.cardPadding(context),
          decoration: BoxDecoration(
            color: Colors.blue[50],
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Icon(
                Icons.help_outline,
                color: Colors.blue[700],
                size: ResponsiveHelper.iconSize(context, 24),
              ),
              SizedBox(width: ResponsiveHelper.spacing(context, 12)),
              Expanded(
                child: Text(
                  '어떻게 이용하시나요?',
                  style: ResponsiveHelper.bodyStyle(
                    context,
                    color: Colors.blue[900],
                  ),
                ),
              ),
            ],
          ),
        ),
        SizedBox(height: ResponsiveHelper.spacing(context, 24)),
        _buildRoleCard(
          role: UserRole.USER,
          icon: Icons.person,
          title: '지원자로 이용',
          description: 'TO에 지원하고 일정을 관리합니다',
          color: Colors.green[600]!,
          features: ['TO 검색 및 지원', '나의 일정 관리', '지원 내역 확인'],
        ),
        SizedBox(height: ResponsiveHelper.spacing(context, 16)),
        _buildRoleCard(
          role: UserRole.BUSINESS_ADMIN,
          icon: Icons.business_center,
          title: '사업장 관리자로 이용',
          description: 'TO를 생성하고 지원자를 관리합니다',
          color: Colors.blue[600]!,
          features: ['TO 생성 및 관리', '지원자 승인/거절', '인력 현황 파악'],
        ),
      ],
    );
  }

  /// Step 3-A: 지원자 추가 정보 (신분증, 통장사본)
  Widget _buildStep3UserDocuments() {
    final theme = Theme.of(context);
    
    return Column(
      children: [
        // 안내 문구
        Container(
          padding: ResponsiveHelper.cardPadding(context),
          decoration: BoxDecoration(
            color: Colors.green[50],
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.green[200]!),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Icon(
                    Icons.person_outline,
                    color: Colors.green[700],
                    size: ResponsiveHelper.iconSize(context, 28),
                  ),
                  SizedBox(width: ResponsiveHelper.spacing(context, 12)),
                  Expanded(
                    child: Text(
                      '지원자 필수 서류',
                      style: ResponsiveHelper.subtitleStyle(context).copyWith(
                        color: Colors.green[900],
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              SizedBox(height: ResponsiveHelper.spacing(context, 12)),
              Text(
                '• 소득신고 및 급여 지급을 위해 필요한 정보입니다.\n'
                '• TO 지원 및 근무 확정 시 필수로 제출해야 합니다.\n'
                '• 지금 등록하시면 TO 지원이 더 빠르게 진행됩니다.',
                style: ResponsiveHelper.smallStyle(
                  context,
                  color: Colors.grey[700],
                ),
              ),
            ],
          ),
        ),
        
        SizedBox(height: ResponsiveHelper.spacing(context, 24)),
        
        // 신분증 업로드
        _buildDocumentUploadCard(
          title: '신분증 앞면',
          description: '주민등록증 또는 운전면허증 앞면을 촬영해주세요',
          icon: Icons.badge_outlined,
          imagePath: _idCardImagePath,
          color: Colors.blue[600]!,
          onTap: () {
            // TODO: 이미지 선택 구현
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('신분증 업로드 기능 구현 예정')),
            );
          },
        ),
        
        SizedBox(height: ResponsiveHelper.spacing(context, 16)),
        
        // 통장사본 업로드
        _buildDocumentUploadCard(
          title: '통장 사본',
          description: '급여를 받을 통장의 사본을 촬영해주세요\n(은행명, 계좌번호, 예금주명이 보이도록)',
          icon: Icons.account_balance_outlined,
          imagePath: _bankbookImagePath,
          color: Colors.green[600]!,
          onTap: () {
            // TODO: 이미지 선택 구현
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('통장 사본 업로드 기능 구현 예정')),
            );
          },
        ),
        
        SizedBox(height: ResponsiveHelper.spacing(context, 24)),
        
        // 나중에 하기 안내
        Container(
          padding: ResponsiveHelper.cardPadding(context),
          decoration: BoxDecoration(
            color: Colors.grey[100],
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Icon(
                Icons.info_outline,
                color: Colors.grey[600],
                size: ResponsiveHelper.iconSize(context, 20),
              ),
              SizedBox(width: ResponsiveHelper.spacing(context, 12)),
              Expanded(
                child: Text(
                  '지금 등록하지 않으셔도 됩니다.\n프로필에서 언제든지 추가하실 수 있습니다.',
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
    );
  }

  /// Step 3-B: 사업장 관리자 추가 정보 (사업자등록증)
  Widget _buildStep3BusinessDocuments() {
    final theme = Theme.of(context);
    
    return Column(
      children: [
        // 안내 문구
        Container(
          padding: ResponsiveHelper.cardPadding(context),
          decoration: BoxDecoration(
            color: Colors.blue[50],
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.blue[200]!),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Icon(
                    Icons.business_center,
                    color: Colors.blue[700],
                    size: ResponsiveHelper.iconSize(context, 28),
                  ),
                  SizedBox(width: ResponsiveHelper.spacing(context, 12)),
                  Expanded(
                    child: Text(
                      '사업장 관리자 서류',
                      style: ResponsiveHelper.subtitleStyle(context).copyWith(
                        color: Colors.blue[900],
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              SizedBox(height: ResponsiveHelper.spacing(context, 12)),
              Text(
                '• 사업장 정보 확인을 위해 필요한 서류입니다.\n'
                '• TO 생성 및 지원자 관리를 위해 필수입니다.\n'
                '• 지금 등록하시면 바로 사업장을 운영할 수 있습니다.',
                style: ResponsiveHelper.smallStyle(
                  context,
                  color: Colors.grey[700],
                ),
              ),
            ],
          ),
        ),
        
        SizedBox(height: ResponsiveHelper.spacing(context, 24)),
        
        // 사업자등록증 업로드
        _buildDocumentUploadCard(
          title: '사업자등록증',
          description: '사업자등록증을 촬영하거나 파일을 선택해주세요\n(사업자번호, 상호명, 대표자명이 보이도록)',
          icon: Icons.business,
          imagePath: _idCardImagePath, // TODO: _businessLicenseImagePath로 변경
          color: Colors.blue[600]!,
          onTap: () {
            // TODO: 이미지 선택 구현
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('사업자등록증 업로드 기능 구현 예정')),
            );
          },
        ),
        
        SizedBox(height: ResponsiveHelper.spacing(context, 24)),
        
        // 추가 정보 안내
        Container(
          padding: ResponsiveHelper.cardPadding(context),
          decoration: BoxDecoration(
            color: Colors.amber[50],
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.amber[200]!),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.lightbulb_outline,
                    color: Colors.amber[700],
                    size: ResponsiveHelper.iconSize(context, 20),
                  ),
                  SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                  Text(
                    '다음 단계',
                    style: ResponsiveHelper.subtitleStyle(context).copyWith(
                      color: Colors.amber[900],
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              SizedBox(height: ResponsiveHelper.spacing(context, 8)),
              Text(
                '회원가입 완료 후 사업장 상세 정보를 입력하실 수 있습니다:\n'
                '• 사업장 주소 및 연락처\n'
                '• 업종 및 상세 업무 내용\n'
                '• 근무 조건 및 급여 정보',
                style: ResponsiveHelper.smallStyle(
                  context,
                  color: Colors.grey[700],
                ),
              ),
            ],
          ),
        ),
        
        SizedBox(height: ResponsiveHelper.spacing(context, 16)),
        
        // 나중에 하기 안내
        Container(
          padding: ResponsiveHelper.cardPadding(context),
          decoration: BoxDecoration(
            color: Colors.grey[100],
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Icon(
                Icons.info_outline,
                color: Colors.grey[600],
                size: ResponsiveHelper.iconSize(context, 20),
              ),
              SizedBox(width: ResponsiveHelper.spacing(context, 12)),
              Expanded(
                child: Text(
                  '지금 등록하지 않으셔도 됩니다.\n로그인 후 사업장 등록 화면에서 입력하실 수 있습니다.',
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
    );
  }

  /// 서류 업로드 카드
  Widget _buildDocumentUploadCard({
    required String title,
    required String description,
    required IconData icon,
    String? imagePath,
    required Color color,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    final isUploaded = imagePath != null;
    
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: ResponsiveHelper.cardPadding(context),
        decoration: BoxDecoration(
          color: isUploaded ? color.withOpacity(0.1) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isUploaded ? color : Colors.grey[300]!,
            width: isUploaded ? 2 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 12)),
              decoration: BoxDecoration(
                color: isUploaded ? color : color.withOpacity(0.2),
                shape: BoxShape.circle,
              ),
              child: Icon(
                isUploaded ? Icons.check : icon,
                color: isUploaded ? Colors.white : color,
                size: ResponsiveHelper.iconSize(context, 32),
              ),
            ),
            SizedBox(width: ResponsiveHelper.spacing(context, 16)),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: ResponsiveHelper.subtitleStyle(context).copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: ResponsiveHelper.spacing(context, 4)),
                  Text(
                    description,
                    style: ResponsiveHelper.smallStyle(
                      context,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.camera_alt,
              color: color,
              size: ResponsiveHelper.iconSize(context, 24),
            ),
          ],
        ),
      ),
    );
  }

  /// 텍스트 필드 빌더
  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
    bool obscureText = false,
    bool enabled = true,
    Widget? suffixIcon,
    String? Function(String?)? validator,
    void Function(String)? onChanged,
  }) {
    final theme = Theme.of(context);
    
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      obscureText: obscureText,
      enabled: enabled,
      style: ResponsiveHelper.bodyStyle(context),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        hintStyle: ResponsiveHelper.smallStyle(
          context,
          color: Colors.grey[400],
        ),
        prefixIcon: Icon(
          icon,
          color: theme.primaryColor,
          size: ResponsiveHelper.iconSize(context, 24),
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
          borderSide: BorderSide(color: theme.primaryColor, width: 2),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey[200]!),
        ),
        filled: true,
        fillColor: enabled ? Colors.grey[50] : Colors.grey[100],
        contentPadding: EdgeInsets.symmetric(
          horizontal: ResponsiveHelper.spacing(context, 16),
          vertical: ResponsiveHelper.spacing(context, 18),
        ),
      ),
      validator: validator,
      onChanged: onChanged,
    );
  }

  /// 역할 선택 카드
  Widget _buildRoleCard({
    required UserRole role,
    required IconData icon,
    required String title,
    required String description,
    required Color color,
    required List<String> features,
  }) {
    final isSelected = _selectedRole == role;
    
    return InkWell(
      onTap: () => setState(() => _selectedRole = role),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: ResponsiveHelper.cardPadding(context),
        decoration: BoxDecoration(
          color: isSelected ? color.withOpacity(0.1) : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? color : Colors.grey[300]!,
            width: isSelected ? 2 : 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: color.withOpacity(0.2),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
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
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: ResponsiveHelper.subtitleStyle(context).copyWith(
                          color: isSelected ? color : Colors.black87,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: ResponsiveHelper.spacing(context, 4)),
                      Text(
                        description,
                        style: ResponsiveHelper.smallStyle(
                          context,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  isSelected ? Icons.check_circle : Icons.radio_button_unchecked,
                  color: isSelected ? color : Colors.grey[400],
                  size: ResponsiveHelper.iconSize(context, 28),
                ),
              ],
            ),
            SizedBox(height: ResponsiveHelper.spacing(context, 16)),
            Divider(color: Colors.grey[300]),
            SizedBox(height: ResponsiveHelper.spacing(context, 12)),
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

  /// 하단 버튼
  Widget _buildBottomButton() {
    final theme = Theme.of(context);
    final userProvider = context.watch<UserProvider>();
    
    return Padding(
      padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 20)),
      child: ElevatedButton(
        onPressed: userProvider.isLoading ? null : _onStepContinue,
        style: ElevatedButton.styleFrom(
          backgroundColor: theme.primaryColor,
          foregroundColor: Colors.white,
          padding: EdgeInsets.symmetric(
            vertical: ResponsiveHelper.spacing(context, 18),
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          elevation: 2,
        ),
        child: Text(
          _currentStep == 0
              ? '다음'
              : _currentStep == 1
                  ? '다음'
                  : '완료',
          style: ResponsiveHelper.bodyStyle(context).copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}