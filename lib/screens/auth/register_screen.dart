import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import '../../models/core/user_model.dart';
import '../../providers/user_provider.dart';
import '../../widgets/common/loading_widget.dart';
import '../../utils/responsive_helper.dart';
import '../../services/auth_service.dart';
import '../business_admin/business_registration_screen.dart';
import '../../widgets/inputs/daum_address_search.dart';
import '../../utils/ocr_verification_helper.dart';
import '../../widgets/dialogs/ocr_verification_dialog.dart';
import '../../utils/document_upload_helper.dart';


import 'package:flutter/foundation.dart' show kIsWeb;

/// 개선된 회원가입 화면 - 주민번호 기반 + 이메일 인증 + 서류 업로드
class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final TextEditingController _accountNumberController = TextEditingController();
  String? _selectedBank;

  int _currentStep = 0;
  // State 변수 추가
  int _passwordStrength = 0; // 0: 약함, 1: 보통, 2: 강함
  AutovalidateMode _autovalidateMode = AutovalidateMode.disabled;
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

  // ⭐ 주소 정보 추가 (여기!)
  final _addressController = TextEditingController();
  final _detailAddressController = TextEditingController();
  
  // 주민번호로 파싱된 정보
  DateTime? _parsedBirthDate;
  String? _parsedGender;
  String? _residentNumberError;

  // Step 2: 역할 선택
  UserRole? _selectedRole;

  // ⭐ Step 3: 사업장 관리자 추가 정보
  final _businessNumberController = TextEditingController();
  final _businessNameController = TextEditingController();
  final _ceoNameController = TextEditingController();
  String? _businessLicenseImagePath;
  
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
    _addressController.dispose();        // ⭐ 추가
    _detailAddressController.dispose();  // ⭐ 추가
    _accountNumberController.dispose();
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
  /// 주소 검색
  Future<void> _searchAddress() async {
    final result = await DaumAddressService.searchAddress(context);
    
    if (result != null) {
      setState(() {
        _addressController.text = result.fullAddress;
      });
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('주소가 입력되었습니다'),
          backgroundColor: Colors.green[600],
          duration: Duration(seconds: 2),
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
      } else {
        // ⭐ 검증 실패 시 실시간 검증 활성화
        setState(() {
          _autovalidateMode = AutovalidateMode.onUserInteraction;
        });
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
      address: _addressController.text.trim(),                    // ⭐ 추가
      detailAddress: _detailAddressController.text.trim(),        // ⭐ 추가
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
      address: _addressController.text.trim(),                    // ⭐ 추가
      detailAddress: _detailAddressController.text.trim(),        // ⭐ 추가
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
  // ============================================================
  // 📸 이미지 업로드 - 카메라/갤러리 선택 (개선 버전)
  // ============================================================

  /// 🎯 이미지 소스 선택 다이얼로그 (모바일만)
  Future<ImageSource?> _showImageSourceDialog() async {
    return await showDialog<ImageSource>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        title: Row(
          children: [
            Icon(
              Icons.add_photo_alternate,
              color: Theme.of(context).primaryColor,
            ),
            SizedBox(width: ResponsiveHelper.spacing(context, 12)),
            Text(
              '이미지 선택',
              style: ResponsiveHelper.subtitleStyle(context),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 📷 카메라
            ListTile(
              leading: Container(
                padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 8)),
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.camera_alt,
                  color: Colors.blue[700],
                  size: ResponsiveHelper.iconSize(context, 24),
                ),
              ),
              title: Text(
                '카메라로 촬영',
                style: ResponsiveHelper.bodyStyle(context),
              ),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            SizedBox(height: ResponsiveHelper.spacing(context, 8)),
            // 🖼️ 갤러리
            ListTile(
              leading: Container(
                padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 8)),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.photo_library,
                  color: Colors.green[700],
                  size: ResponsiveHelper.iconSize(context, 24),
                ),
              ),
              title: Text(
                '갤러리에서 선택',
                style: ResponsiveHelper.bodyStyle(context),
              ),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('취소'),
          ),
        ],
      ),
    );
  }

  /// 📸 사업자등록증 이미지 선택 (간소화 버전)
  Future<void> _pickBusinessLicenseImage() async {
    final imagePath = await DocumentUploadHelper.pickAndVerifyBusinessLicense(
      context,
      businessNumber: _businessNumberController.text.trim().isEmpty 
          ? null 
          : _businessNumberController.text.trim(),
      ceoName: _ceoNameController.text.trim().isEmpty 
          ? null 
          : _ceoNameController.text.trim(),
    );
    
    if (imagePath != null) {
      setState(() => _businessLicenseImagePath = imagePath);
    }
  }

  /// 📸 신분증 이미지 선택 (주민번호 검증 포함)
  Future<void> _pickIdCardImage() async {
    // 주민번호 앞 7자리 조합 (예: "990101-1")
    String? residentNumber;
    if (_residentNumber1Controller.text.isNotEmpty && 
        _residentNumber2Controller.text.isNotEmpty) {
      residentNumber = '${_residentNumber1Controller.text}-${_residentNumber2Controller.text[0]}';
    }
    
    final imagePath = await DocumentUploadHelper.pickAndVerifyIdCard(
      context,
      _nameController.text.trim(),
      expectedResidentNumber: residentNumber,
    );
    
    if (imagePath != null) {
      setState(() => _idCardImagePath = imagePath);
    }
  }
  /// 📸 통장사본 이미지 선택
  Future<void> _pickBankbookImage() async {
    final imagePath = await DocumentUploadHelper.pickAndVerifyBankbook(
      context,
      _nameController.text.trim(),
    );
    
    if (imagePath != null) {
      setState(() => _bankbookImagePath = imagePath);
    }
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
        autovalidateMode: _autovalidateMode,
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

            // ⭐ 주소 (웹: 수동입력 / 모바일: 다음 API)
            if (kIsWeb) ...[
              // 🌐 웹 환경: 수동 입력
              _buildTextField(
                controller: _addressController,
                label: '주소',
                hint: '주소를 직접 입력해주세요 (임시)',
                icon: Icons.location_on_outlined,
                validator: (value) {
                  if (value == null || value.isEmpty) return '주소를 입력해주세요';
                  return null;
                },
              ),
            ] else ...[
              // 📱 모바일 환경: 다음 주소 검색
              _buildTextField(
                controller: _addressController,
                label: '주소',
                hint: '주소 검색 버튼을 눌러주세요',
                icon: Icons.location_on_outlined,
                readOnly: true,
                onTap: _searchAddress,
                suffixIcon: IconButton(
                  icon: Icon(
                    Icons.search,
                    color: Theme.of(context).primaryColor,
                    size: ResponsiveHelper.iconSize(context, 24),
                  ),
                  onPressed: _searchAddress,
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) return '주소를 입력해주세요';
                  return null;
                },
              ),
            ],

            SizedBox(height: ResponsiveHelper.spacing(context, 16)),

            // ⭐ 상세 주소
            _buildTextField(
              controller: _detailAddressController,
              label: '상세 주소',
              hint: '동/호수 등 상세 주소',
              icon: Icons.home_outlined,
              validator: (value) {
                // 상세주소는 선택사항
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
          description: '공고에 지원하고 일정을 관리합니다',
          color: Colors.green[600]!,
          features: ['공고 검색 및 지원', '나의 근무일정 관리', '지원 내역 확인'],
        ),
        SizedBox(height: ResponsiveHelper.spacing(context, 16)),
        _buildRoleCard(
          role: UserRole.BUSINESS_ADMIN,
          icon: Icons.business_center,
          title: '사업장 관리자로 이용',
          description: '공고를 생성하고 지원자를 관리합니다',
          color: Colors.blue[600]!,
          features: ['공고 생성 및 관리', '지원자 승인/거절', '인력 현황 파악'],
        ),
      ],
    );
  }

  /// Step 3-A: 지원자 추가 정보 (통장 정보 추가 버전)
  Widget _buildStep3UserDocuments() {
    final theme = Theme.of(context);
    
    return SingleChildScrollView(
      child: Column(
        children: [
          // 📢 상단 안내 카드
          Container(
            padding: ResponsiveHelper.cardPadding(context),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.blue[50]!, Colors.blue[100]!],
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.blue[200]!, width: 2),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Container(
                      padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 12)),
                      decoration: BoxDecoration(
                        color: Colors.blue[600],
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.info_outline,
                        color: Colors.white,
                        size: ResponsiveHelper.iconSize(context, 28),
                      ),
                    ),
                    SizedBox(width: ResponsiveHelper.spacing(context, 16)),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '서류 제출 안내',
                            style: ResponsiveHelper.subtitleStyle(context).copyWith(
                              fontWeight: FontWeight.bold,
                              color: Colors.blue[900],
                            ),
                          ),
                          SizedBox(height: ResponsiveHelper.spacing(context, 4)),
                          Text(
                            '본인 명의 서류만 인증 가능합니다',
                            style: ResponsiveHelper.smallStyle(
                              context,
                              color: Colors.blue[700],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                SizedBox(height: ResponsiveHelper.spacing(context, 16)),
                Container(
                  padding: ResponsiveHelper.cardPadding(context),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildNoticeItem(
                        '✓ 신분증과 통장의 이름이 일치해야 합니다',
                        Colors.blue[900]!,
                      ),
                      SizedBox(height: ResponsiveHelper.spacing(context, 8)),
                      _buildNoticeItem(
                        '✓ 신분증 주민번호가 입력한 정보와 일치해야 합니다',
                        Colors.blue[900]!,
                      ),
                      SizedBox(height: ResponsiveHelper.spacing(context, 8)),
                      _buildNoticeItem(
                        '✓ 통장사본의 예금주가 본인 이름과 일치해야 합니다',
                        Colors.blue[900]!,
                      ),
                      SizedBox(height: ResponsiveHelper.spacing(context, 12)),
                      Divider(),
                      SizedBox(height: ResponsiveHelper.spacing(context, 8)),
                      Row(
                        children: [
                          Icon(
                            Icons.camera_alt,
                            size: ResponsiveHelper.iconSize(context, 18),
                            color: Colors.orange[700],
                          ),
                          SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                          Expanded(
                            child: Text(
                              '선명한 사진을 촬영해주세요 (흐림/반사 주의)',
                              style: ResponsiveHelper.smallStyle(
                                context,
                                color: Colors.orange[900],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          
          SizedBox(height: ResponsiveHelper.spacing(context, 24)),
          
          // 📸 신분증 업로드
          _buildIdCardUploadCard(),
          
          SizedBox(height: ResponsiveHelper.spacing(context, 24)),
          
          // 💳 통장 정보 카드 (NEW!)
          _buildBankInfoCard(),
          
          SizedBox(height: ResponsiveHelper.spacing(context, 24)),
          
          // ✨ 나중에 하기 안내
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
                    '지금 등록하지 않으셔도 됩니다.\n설정 > 내 정보에서 언제든지 추가하실 수 있습니다.',
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

  // ⭐ 안내 항목 빌더 (새로 추가)
  Widget _buildNoticeItem(String text, Color color) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.only(top: 2),
          child: Icon(
            Icons.check_circle,
            size: ResponsiveHelper.iconSize(context, 16),
            color: color,
          ),
        ),
        SizedBox(width: ResponsiveHelper.spacing(context, 8)),
        Expanded(
          child: Text(
            text,
            style: ResponsiveHelper.smallStyle(context, color: color),
          ),
        ),
      ],
    );
  }

  // ⭐ 신분증 업로드 카드 (새로 추가)
  Widget _buildIdCardUploadCard() {
    return Container(
      padding: ResponsiveHelper.cardPadding(context),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey[300]!),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.badge,
                color: Theme.of(context).primaryColor,
                size: ResponsiveHelper.iconSize(context, 24),
              ),
              SizedBox(width: ResponsiveHelper.spacing(context, 12)),
              Text(
                '신분증 앞면',
                style: ResponsiveHelper.bodyStyle(context).copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              Spacer(),
              if (_idCardImagePath != null)
                Icon(
                  Icons.check_circle,
                  color: Colors.green[600],
                  size: ResponsiveHelper.iconSize(context, 24),
                ),
            ],
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 16)),
          InkWell(
            onTap: _pickIdCardImage,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              height: ResponsiveHelper.spacing(context, 120),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _idCardImagePath != null 
                      ? Colors.green[300]! 
                      : Colors.grey[300]!,
                  width: 2,
                ),
              ),
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      _idCardImagePath != null 
                          ? Icons.check_circle_outline 
                          : Icons.add_photo_alternate,
                      size: ResponsiveHelper.iconSize(context, 48),
                      color: _idCardImagePath != null 
                          ? Colors.green[600] 
                          : Colors.grey[400],
                    ),
                    SizedBox(height: ResponsiveHelper.spacing(context, 8)),
                    Text(
                      _idCardImagePath != null 
                          ? '신분증 업로드 완료 (재촬영하려면 터치)'
                          : '신분증 사진 업로드',
                      style: ResponsiveHelper.smallStyle(
                        context,
                        color: _idCardImagePath != null 
                            ? Colors.green[700] 
                            : Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ⭐ 통장 정보 카드 (NEW!)
  Widget _buildBankInfoCard() {
    return Container(
      padding: ResponsiveHelper.cardPadding(context),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey[300]!),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 제목
          Row(
            children: [
              Icon(
                Icons.account_balance_wallet,
                color: Theme.of(context).primaryColor,
                size: ResponsiveHelper.iconSize(context, 24),
              ),
              SizedBox(width: ResponsiveHelper.spacing(context, 12)),
              Text(
                '급여 통장 정보',
                style: ResponsiveHelper.bodyStyle(context).copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 16)),
          
          // 🏦 은행 선택
          DropdownButtonFormField<String>(
            value: _selectedBank,
            decoration: InputDecoration(
              labelText: '은행',
              prefixIcon: Icon(Icons.account_balance),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.grey[300]!),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: Theme.of(context).primaryColor,
                  width: 2,
                ),
              ),
            ),
            items: [
              'KB국민은행',
              '신한은행',
              'NH농협은행',
              '우리은행',
              '하나은행',
              'IBK기업은행',
              'SC제일은행',
              '씨티은행',
              '카카오뱅크',
              '토스뱅크',
              'KEB하나은행',
              '경남은행',
              '광주은행',
              '대구은행',
              '부산은행',
              '전북은행',
              '제주은행',
              '케이뱅크',
              '새마을금고',
              '신협',
              '저축은행',
              '우체국',
            ].map((bank) => DropdownMenuItem(
              value: bank,
              child: Text(bank),
            )).toList(),
            onChanged: (value) {
              setState(() => _selectedBank = value);
            },
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 16)),
          
          // 💳 계좌번호 입력
          TextFormField(
            controller: _accountNumberController,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: '계좌번호',
              hintText: '- 없이 숫자만 입력',
              prefixIcon: Icon(Icons.credit_card),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.grey[300]!),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: Theme.of(context).primaryColor,
                  width: 2,
                ),
              ),
            ),
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 12)),
          
          // 💡 예금주 안내
          Container(
            padding: ResponsiveHelper.cardPadding(context).copyWith(
              top: ResponsiveHelper.spacing(context, 12),
              bottom: ResponsiveHelper.spacing(context, 12),
            ),
            decoration: BoxDecoration(
              color: Colors.green.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.green.withOpacity(0.3)),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.info_outline,
                  color: Colors.green[700],
                  size: ResponsiveHelper.iconSize(context, 18),
                ),
                SizedBox(width: ResponsiveHelper.spacing(context, 12)),
                Expanded(
                  child: Text(
                    '예금주: ${_nameController.text.isEmpty ? "(이름 입력 필요)" : _nameController.text}',
                    style: ResponsiveHelper.smallStyle(
                      context,
                      color: Colors.green[900],
                    ),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 16)),
          
          // 📸 통장사본 업로드
          InkWell(
            onTap: _pickBankbookImage,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              height: ResponsiveHelper.spacing(context, 120),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _bankbookImagePath != null 
                      ? Colors.green[300]! 
                      : Colors.grey[300]!,
                  width: 2,
                ),
              ),
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      _bankbookImagePath != null 
                          ? Icons.check_circle_outline 
                          : Icons.add_photo_alternate,
                      size: ResponsiveHelper.iconSize(context, 48),
                      color: _bankbookImagePath != null 
                          ? Colors.green[600] 
                          : Colors.grey[400],
                    ),
                    SizedBox(height: ResponsiveHelper.spacing(context, 8)),
                    Text(
                      _bankbookImagePath != null 
                          ? '통장사본 업로드 완료'
                          : '통장사본 사진 업로드',
                      style: ResponsiveHelper.smallStyle(
                        context,
                        color: _bankbookImagePath != null 
                            ? Colors.green[700] 
                            : Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Step 3-B: 사업장 관리자 추가 정보 (완전 개선 버전)
  Widget _buildStep3BusinessDocuments() {
    final theme = Theme.of(context);
    
    return SingleChildScrollView(
      child: Column(
        children: [
          // ✨ 안내 헤더
          Container(
            padding: ResponsiveHelper.cardPadding(context),
            decoration: BoxDecoration(
              color: theme.primaryColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: theme.primaryColor.withOpacity(0.3),
              ),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.business_center,
                      color: theme.primaryColor,
                      size: ResponsiveHelper.iconSize(context, 28),
                    ),
                    SizedBox(width: ResponsiveHelper.spacing(context, 12)),
                    Expanded(
                      child: Text(
                        '사업장 관리자 정보',
                        style: ResponsiveHelper.subtitleStyle(context).copyWith(
                          color: theme.primaryColor,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: ResponsiveHelper.spacing(context, 12)),
                Text(
                  '• TO 생성 및 지원자 관리를 위한 정보입니다.\n'
                  '• 지금 입력하시면 사업장 등록이 더 빠릅니다.\n'
                  '• 모든 항목은 선택사항입니다.',
                  style: ResponsiveHelper.smallStyle(
                    context,
                    color: theme.textTheme.bodySmall?.color,
                  ),
                ),
              ],
            ),
          ),
          
          SizedBox(height: ResponsiveHelper.spacing(context, 24)),
          
          // ✨ 입력 카드 섹션
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 📝 사업자등록번호
                _buildBusinessNumberField(),
                
                SizedBox(height: ResponsiveHelper.spacing(context, 16)),
                
                // 📝 상호명
                _buildTextField(
                  controller: _businessNameController,
                  label: '상호명',
                  hint: '예: 홍길동 물류센터',
                  icon: Icons.store_outlined,
                  validator: (value) {
                    // 선택사항이지만 입력했다면 최소 2자
                    if (value != null && value.isNotEmpty && value.length < 2) {
                      return '2자 이상 입력해주세요';
                    }
                    return null;
                  },
                ),
                
                SizedBox(height: ResponsiveHelper.spacing(context, 16)),
                
                // 📝 대표자명 (기본값: 회원가입 이름)
                _buildCEONameField(),
              ],
            ),
          ),
          
          SizedBox(height: ResponsiveHelper.spacing(context, 24)),
          
          // ✨ 서류 업로드 섹션
          Text(
            '사업자등록증',
            style: ResponsiveHelper.subtitleStyle(context).copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 12)),
          
          _buildDocumentUploadCard(
            title: '사업자등록증',
            description: '사업자등록증을 촬영하거나 파일을 선택해주세요\n(사업자번호, 상호명, 대표자명이 보이도록)',
            icon: Icons.business,
            imagePath: _businessLicenseImagePath,
            color: theme.primaryColor,
            onTap: _pickBusinessLicenseImage,
          ),
          
          SizedBox(height: ResponsiveHelper.spacing(context, 24)),
          
          // ✨ 나중에 하기 안내
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
                    '지금 등록하지 않으셔도 됩니다.\n설정 > 내 정보에서 언제든지 추가하실 수 있습니다.',
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

  /// 📝 사업자등록번호 입력 필드 (자동 포맷)
  Widget _buildBusinessNumberField() {
    final theme = Theme.of(context);
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextFormField(
          controller: _businessNumberController,
          keyboardType: TextInputType.number,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(10),
          ],
          style: ResponsiveHelper.bodyStyle(context),
          decoration: InputDecoration(
            labelText: '사업자등록번호',
            hintText: '0000000000',
            hintStyle: ResponsiveHelper.smallStyle(
              context,
              color: Colors.grey[400],
            ),
            prefixIcon: Icon(
              Icons.badge_outlined,
              color: theme.primaryColor,
              size: ResponsiveHelper.iconSize(context, 24),
            ),
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
            filled: true,
            fillColor: Colors.grey[50],
            contentPadding: EdgeInsets.symmetric(
              horizontal: ResponsiveHelper.spacing(context, 16),
              vertical: ResponsiveHelper.spacing(context, 18),
            ),
          ),
          validator: (value) {
            // 선택사항이지만 입력했다면 10자리
            if (value != null && value.isNotEmpty && value.length != 10) {
              return '10자리를 입력해주세요';
            }
            return null;
          },
          onChanged: (value) {
            // 실시간 포맷 표시는 하지 않음 (입력 방해)
            // 대신 저장할 때 포맷팅
          },
        ),
        
        // 포맷 미리보기
        if (_businessNumberController.text.length == 10)
          Padding(
            padding: EdgeInsets.only(
              top: ResponsiveHelper.spacing(context, 8),
              left: ResponsiveHelper.spacing(context, 16),
            ),
            child: Text(
              '형식: ${_formatBusinessNumber(_businessNumberController.text)}',
              style: ResponsiveHelper.tinyStyle(
                context,
                color: Colors.green[700],
              ),
            ),
          ),
      ],
    );
  }

  /// 📝 대표자명 필드 (기본값: 회원가입 이름)
  Widget _buildCEONameField() {
    final theme = Theme.of(context);
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: TextFormField(
                controller: _ceoNameController,
                style: ResponsiveHelper.bodyStyle(context),
                decoration: InputDecoration(
                  labelText: '대표자명',
                  hintText: '예: 홍길동',
                  hintStyle: ResponsiveHelper.smallStyle(
                    context,
                    color: Colors.grey[400],
                  ),
                  prefixIcon: Icon(
                    Icons.person_outline,
                    color: theme.primaryColor,
                    size: ResponsiveHelper.iconSize(context, 24),
                  ),
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
                  filled: true,
                  fillColor: Colors.grey[50],
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: ResponsiveHelper.spacing(context, 16),
                    vertical: ResponsiveHelper.spacing(context, 18),
                  ),
                ),
                validator: (value) {
                  // 선택사항이지만 입력했다면 최소 2자
                  if (value != null && value.isNotEmpty && value.length < 2) {
                    return '2자 이상 입력해주세요';
                  }
                  return null;
                },
              ),
            ),
            SizedBox(width: ResponsiveHelper.spacing(context, 8)),
            TextButton.icon(
              onPressed: () {
                setState(() {
                  _ceoNameController.text = _nameController.text;
                });
              },
              icon: Icon(
                Icons.sync,
                size: ResponsiveHelper.iconSize(context, 18),
              ),
              label: Text(
                '이름 가져오기',
                style: ResponsiveHelper.smallStyle(context),
              ),
            ),
          ],
        ),
        Padding(
          padding: EdgeInsets.only(
            top: ResponsiveHelper.spacing(context, 8),
            left: ResponsiveHelper.spacing(context, 16),
          ),
          child: Text(
            '💡 회원가입 시 입력한 이름을 자동으로 가져올 수 있습니다',
            style: ResponsiveHelper.tinyStyle(
              context,
              color: Colors.grey[600],
            ),
          ),
        ),
      ],
    );
  }

  /// 🔧 사업자등록번호 포맷팅 (000-00-00000)
  String _formatBusinessNumber(String value) {
    final digits = value.replaceAll(RegExp(r'\D'), '');
    if (digits.length != 10) return value;
    
    return '${digits.substring(0, 3)}-${digits.substring(3, 5)}-${digits.substring(5, 10)}';
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
    bool readOnly = false,        // ⭐ 추가
    VoidCallback? onTap,          // ⭐ 추가
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
      readOnly: readOnly,           // ⭐ 추가
      onTap: onTap,   
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