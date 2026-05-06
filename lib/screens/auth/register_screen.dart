import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter/services.dart';
import 'package:cloud_functions/cloud_functions.dart';
import '../../models/core/user_model.dart';
import '../../providers/user_provider.dart';
import '../../widgets/common/loading_widget.dart';
import '../../utils/responsive_helper.dart';
import '../../services/auth_service.dart';
import '../../services/storage_service.dart';
import '../../widgets/inputs/daum_address_search.dart';
import '../../utils/document_upload_helper.dart';
import '../../utils/toast_helper.dart';
import '../business_admin/business_form_screen.dart';

import 'package:flutter/foundation.dart' show kIsWeb;
import '../../theme/app_colors.dart';

/// 개선된 회원가입 화면 - 자동 스크롤 + 여백 최적화 + Storage 업로드
class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  // ✅ Storage 서비스 추가
  final StorageService _storageService = StorageService();
  
  final TextEditingController _accountNumberController = TextEditingController();
  String? _selectedBank;

  int _currentStep = 0;
  AutovalidateMode _autovalidateMode = AutovalidateMode.disabled;
  
  // ✅ 중복 제출 방지 플래그 추가
  bool _isSubmitting = false;
  
  // 스크롤 컨트롤러
  final ScrollController _scrollController = ScrollController();
  
  // Step 1: 기본 정보
  final _usernameController = TextEditingController();
  bool _isCheckingUsername = false;
  bool _isUsernameAvailable = false;
  String? _usernameError;
  String _currentUsername = '';
  String _currentEmail = '';
  Timer? _usernameDebounce;
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _residentNumber1Controller = TextEditingController();
  final _residentNumber2Controller = TextEditingController();
  final _emailController = TextEditingController();
  final _emailCodeController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  
  // 이메일 인증 상태
  bool _isEmailSent = false;
  bool _isEmailVerified = false;
  bool _isEmailSending = false;
  bool _isEmailVerifying = false;

  // 이메일 분리 입력
  final _emailLocalController = TextEditingController();
  final _emailDomainController = TextEditingController();
  String? _selectedEmailDomain = 'naver.com';

  // 법적 동의
  bool _agreedToAll = false;
  bool _agreedToTerms = false;
  bool _agreedToPrivacy = false;
  bool _agreedToMarketing = false;

  // 주소 정보
  final _addressController = TextEditingController();
  final _detailAddressController = TextEditingController();
  
  // 주민번호 파싱 정보
  DateTime? _parsedBirthDate;
  String? _parsedGender;
  String? _residentNumberError;

  // Step 2: 역할 선택
  UserRole? _selectedRole;

  // Step 3: 사업장 관리자 추가 정보
  final _businessNumberController = TextEditingController();
  final _businessNameController = TextEditingController();
  final _ceoNameController = TextEditingController();
  String? _businessLicenseImagePath;
  
  // Step 3: 추가 정보 (선택)
  String? _idCardImagePath;
  String? _bankbookImagePath;
  
  // FocusNode 선언
  final _nameFocus = FocusNode();
  final _usernameFocus = FocusNode();
  final _residentNumber1Focus = FocusNode();
  final _residentNumber2Focus = FocusNode();
  final _emailFocus = FocusNode();
  final _emailCodeFocus = FocusNode();
  final _phoneFocus = FocusNode();
  final _addressFocus = FocusNode();
  final _detailAddressFocus = FocusNode();
  final _passwordFocus = FocusNode();
  final _confirmPasswordFocus = FocusNode();

  // Step 3: 사업장 관리자 포커스
  final _businessNameFocus = FocusNode();
  final _ceoNameFocus = FocusNode();
  final _accountNumberFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _nameFocus.requestFocus();
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _usernameController.dispose();
    _nameController.dispose();
    _residentNumber1Controller.dispose();
    _residentNumber2Controller.dispose();
    _emailController.dispose();
    _emailLocalController.dispose();
    _emailDomainController.dispose();
    _emailCodeController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    _detailAddressController.dispose();
    _accountNumberController.dispose();
    
    _usernameDebounce?.cancel();
    _nameFocus.dispose();
    _usernameFocus.dispose();
    _residentNumber1Focus.dispose();
    _residentNumber2Focus.dispose();
    _emailFocus.dispose();
    _emailCodeFocus.dispose();
    _phoneFocus.dispose();
    _addressFocus.dispose();
    _detailAddressFocus.dispose();
    _passwordFocus.dispose();
    _confirmPasswordFocus.dispose();
    _businessNameFocus.dispose();
    _ceoNameFocus.dispose();
    _accountNumberFocus.dispose();
    super.dispose();
  }
  // ============================================================
  // 🔧 핵심 함수들
  // ============================================================

  /// 주민번호로 생년월일과 성별 파싱
  void _parseResidentNumber() {
    final rn1 = _residentNumber1Controller.text;
    final rn2 = _residentNumber2Controller.text;
    
    if (rn1.length == 6 && rn2.isNotEmpty) {
      try {
        int year = int.parse(rn1.substring(0, 2));
        int month = int.parse(rn1.substring(2, 4));
        int day = int.parse(rn1.substring(4, 6));
        int genderCode = int.parse(rn2[0]);
        
        if (genderCode < 1 || genderCode > 4) {
          setState(() {
            _parsedBirthDate = null;
            _parsedGender = null;
            _residentNumberError = '뒷자리는 1~4만 가능합니다';
          });
          return;
        }
        
        if (genderCode == 1 || genderCode == 2) {
          year += 1900;
        } else if (genderCode == 3 || genderCode == 4) {
          final currentYear = DateTime.now().year;
          final twoDigitCurrentYear = currentYear % 100;
          
          if (year > twoDigitCurrentYear) {
            setState(() {
              _parsedBirthDate = null;
              _parsedGender = null;
              _residentNumberError = '2000년대생은 00~${twoDigitCurrentYear.toString().padLeft(2, '0')}년생만 가능합니다';
            });
            return;
          }
          year += 2000;
        }
        
        if ((genderCode == 3 || genderCode == 4) && year < 2000) {
          setState(() {
            _parsedBirthDate = null;
            _parsedGender = null;
            _residentNumberError = '$year년생은 뒷자리 1 또는 2를 사용해야 합니다';
          });
          return;
        }
        
        if ((genderCode == 1 || genderCode == 2) && year >= 2000) {
          setState(() {
            _parsedBirthDate = null;
            _parsedGender = null;
            _residentNumberError = '$year년생은 뒷자리 3 또는 4를 사용해야 합니다';
          });
          return;
        }
        
        try {
          _parsedBirthDate = DateTime(year, month, day);
        } catch (e) {
          setState(() {
            _parsedBirthDate = null;
            _parsedGender = null;
            _residentNumberError = '존재하지 않는 날짜입니다 ($year년 $month월 $day일)';
          });
          return;
        }
        
        _parsedGender = (genderCode == 1 || genderCode == 3) ? '남성' : '여성';
        setState(() {
          _residentNumberError = null;
        });
        
        debugPrint('✅ 주민번호 파싱 성공: $_parsedBirthDate, $_parsedGender');
      } catch (e) {
        debugPrint('❌ 주민번호 파싱 실패: $e');
        setState(() {
          _parsedBirthDate = null;
          _parsedGender = null;
          _residentNumberError = '올바른 주민번호를 입력해주세요';
        });
      }
    } else {
      setState(() {
        _parsedBirthDate = null;
        _parsedGender = null;
        _residentNumberError = null;
      });
    }
  }

  /// 이메일 인증 코드 발송 (Cloud Function)
  Future<void> _sendEmailVerification() async {
    final email = _emailController.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      ToastHelper.showWarning('올바른 이메일을 입력해주세요');
      return;
    }

    setState(() => _isEmailSending = true);

    try {
      final callable = FirebaseFunctions.instanceFor(region: 'asia-northeast3')
          .httpsCallable('sendEmailVerificationCode');
      await callable.call({'email': email});

      setState(() => _isEmailSent = true);
      ToastHelper.showSuccess('인증번호가 $email로 발송되었습니다 (5분 유효)');

      Future.delayed(const Duration(milliseconds: 300), () {
        if (mounted) _emailCodeFocus.requestFocus();
      });
    } on FirebaseFunctionsException catch (e) {
      ToastHelper.showError(e.message ?? '발송에 실패했습니다. 다시 시도해주세요');
    } catch (e) {
      ToastHelper.showError('발송에 실패했습니다. 다시 시도해주세요');
    } finally {
      if (mounted) setState(() => _isEmailSending = false);
    }
  }

  /// 이메일 인증 코드 검증 (Cloud Function)
  Future<void> _verifyEmailCode() async {
    final email = _emailController.text.trim();
    final code = _emailCodeController.text.trim();

    if (code.length != 6) {
      ToastHelper.showWarning('6자리 인증번호를 입력해주세요');
      return;
    }

    setState(() => _isEmailVerifying = true);

    try {
      final callable = FirebaseFunctions.instanceFor(region: 'asia-northeast3')
          .httpsCallable('verifyEmailCode');
      final result = await callable.call({'email': email, 'code': code});

      final data = result.data as Map<String, dynamic>;
      if (data['valid'] == true) {
        setState(() => _isEmailVerified = true);
        ToastHelper.showSuccess('이메일 인증이 완료되었습니다');
        Future.delayed(const Duration(milliseconds: 300), () {
          if (mounted) _phoneFocus.requestFocus();
        });
      } else {
        final reason = data['reason'] as String? ?? '';
        final msg = switch (reason) {
          'expired' => '인증번호가 만료되었습니다. 재발송해주세요',
          'wrong_code' => '인증번호가 일치하지 않습니다',
          'too_many_attempts' => '시도 횟수를 초과했습니다. 재발송해주세요',
          _ => '인증에 실패했습니다',
        };
        ToastHelper.showError(msg);
      }
    } catch (e) {
      ToastHelper.showError('인증 확인에 실패했습니다. 다시 시도해주세요');
    } finally {
      if (mounted) setState(() => _isEmailVerifying = false);
    }
  }

  /// ✅ 주소 검색 (포커스 추가)
  Future<void> _searchAddress() async {
    final result = await DaumAddressService.searchAddress(context);
    
    if (result != null && mounted) {
      setState(() {
        _addressController.text = result.fullAddress;
      });
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('주소가 입력되었습니다'),
          backgroundColor: AppColors.successMedium,
          duration: Duration(seconds: 2),
        ),
      );
      
      // ✅ 상세주소 필드로 포커스 이동
      Future.delayed(const Duration(milliseconds: 300), () {
        if (mounted) {
          _detailAddressFocus.requestFocus();
        }
      });
    }
  }

  // Step 검증
  bool _validateStep1() {
    if (!(_formKey.currentState?.validate() ?? false)) return false;

    _parseResidentNumber();
    if (_parsedBirthDate == null || _parsedGender == null) {
      ToastHelper.showWarning('올바른 주민번호를 입력해주세요');
      return false;
    }

    if (!_isEmailVerified) {
      ToastHelper.showWarning('이메일 인증을 완료해주세요');
      return false;
    }

    if (!_agreedToTerms || !_agreedToPrivacy) {
      ToastHelper.showWarning('필수 약관에 동의해주세요');
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
        _scrollToTop();
      } else {
        setState(() {
          _autovalidateMode = AutovalidateMode.onUserInteraction;
        });
      }
    } else if (_currentStep == 1) {
      if (_validateStep2()) {
        setState(() => _currentStep = 2);
        _scrollToTop();
      }
    } else if (_currentStep == 2) {
      _handleRoleSelection();
    }
  }

  void _onStepCancel() {
    if (_currentStep > 0) {
      setState(() => _currentStep -= 1);
      _scrollToTop();
    } else {
      Navigator.pop(context);
    }
  }
  
  /// 스크롤 맨 위로
  void _scrollToTop() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
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
  // ============================================================
  // 📝 회원가입 로직 (Storage 업로드 포함)
  // ============================================================

  // 사업장 등록 선택 다이얼로그
  void _showBusinessRegistrationDialog() {
    final theme = Theme.of(context);
    
    // 사업자등록증 미등록 시 경고
    if (_businessLicenseImagePath == null) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Row(
            children: [
              Icon(Icons.warning_amber, color: AppColors.warningDark),
              SizedBox(width: ResponsiveHelper.spacing(context, 8)),
              Text('사업자등록증 미등록', style: ResponsiveHelper.titleStyle(context)),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 12)),
                  decoration: BoxDecoration(
                    color: AppColors.warningBg,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.warningLight),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '⚠️ 사업자등록증이 등록되지 않았습니다.',
                        style: ResponsiveHelper.bodyStyle(context).copyWith(
                          fontWeight: FontWeight.bold,
                          color: AppColors.warningDarkest,
                        ),
                      ),
                      SizedBox(height: ResponsiveHelper.spacing(context, 8)),
                      Text(
                        '• 사업자등록증 미등록 시 사업장 등록이 불가합니다.\n'
                        '• 설정 > 내 서류 관리에서 등록할 수 있습니다.',
                        style: ResponsiveHelper.smallStyle(context).copyWith(
                          color: AppColors.warningDeep,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
              },
              child: Text('돌아가기', style: ResponsiveHelper.bodyStyle(context)),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                _registerUser();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.warningDark,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: Text(
                '나중에 등록',
                style: ResponsiveHelper.bodyStyle(context).copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      );
      return;
    }
    
    // 사업자등록증 등록 완료 시 기존 다이얼로그
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
            SizedBox(width: ResponsiveHelper.spacing(context, 8)),
            Text('사업장 등록', style: ResponsiveHelper.titleStyle(context)),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('사업장 정보를 지금 등록하시겠습니까?', style: ResponsiveHelper.bodyStyle(context)),
              SizedBox(height: ResponsiveHelper.spacing(context, 16)),
              Container(
                padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 12)),
                decoration: BoxDecoration(
                  color: theme.primaryColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: theme.primaryColor.withValues(alpha: 0.3)),
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

  /// ✅ 회원가입 (Storage 업로드 추가 + 중복 제출 방지)
  Future<void> _registerUser() async {
    // ✅ 중복 제출 방지
    if (_isSubmitting) return;
    setState(() => _isSubmitting = true);
    
    final userProvider = context.read<UserProvider>();
    
    try {
      // ✅ 이미지 업로드 (있는 경우에만)
      String? idCardImageUrl;
      String? bankbookImageUrl;
      String? businessLicenseImageUrl;
      
      // 임시 UID 생성 (실제 가입 전 업로드용)
      final tempId = DateTime.now().millisecondsSinceEpoch.toString();
      
      // 신분증 업로드
      if (_idCardImagePath != null && !kIsWeb) {
        ToastHelper.showInfo('신분증 업로드 중...');
        final storagePath = 'users/temp_$tempId/idCard_$tempId.jpg';
        idCardImageUrl = await _storageService.uploadImage(_idCardImagePath!, storagePath);
        if (idCardImageUrl == null) {
          debugPrint('⚠️ 신분증 업로드 실패 - 계속 진행');
        }
      }
      
      // 통장사본 업로드
      if (_bankbookImagePath != null && !kIsWeb) {
        ToastHelper.showInfo('통장사본 업로드 중...');
        final storagePath = 'users/temp_$tempId/bankbook_$tempId.jpg';
        bankbookImageUrl = await _storageService.uploadImage(_bankbookImagePath!, storagePath);
        if (bankbookImageUrl == null) {
          debugPrint('⚠️ 통장사본 업로드 실패 - 계속 진행');
        }
      }
      
      // 사업자등록증 업로드 (BUSINESS_ADMIN인 경우)
      if (_businessLicenseImagePath != null && _selectedRole == UserRole.BUSINESS_ADMIN && !kIsWeb) {
        ToastHelper.showInfo('사업자등록증 업로드 중...');
        final storagePath = 'users/temp_$tempId/businessLicense_$tempId.jpg';
        businessLicenseImageUrl = await _storageService.uploadImage(_businessLicenseImagePath!, storagePath);
        if (businessLicenseImageUrl == null) {
          debugPrint('⚠️ 사업자등록증 업로드 실패 - 계속 진행');
        }
      }
      
      // ✅ 회원가입 실행 (URL 전달)
      final success = await userProvider.signUp(
        username: _usernameController.text.trim(),
        userEmail: _emailController.text.trim(),
        password: _passwordController.text,
        name: _nameController.text.trim(),
        phone: _phoneController.text.trim(),
        role: _selectedRole!,
        gender: _parsedGender,
        birthDate: _parsedBirthDate,
        residentNumber: '${_residentNumber1Controller.text}-${_residentNumber2Controller.text}******',
        address: _addressController.text.trim(),
        detailAddress: _detailAddressController.text.trim(),
        // ✅ Storage URL 전달 (로컬 경로 대신)
        idCardImageUrl: idCardImageUrl,
        bankbookImageUrl: bankbookImageUrl,
        businessLicenseImageUrl: businessLicenseImageUrl,
        // ✅ 통장 정보 추가
        bankName: _selectedBank,
        accountNumber: _accountNumberController.text.trim().isEmpty 
            ? null 
            : _accountNumberController.text.trim(),
        // 사업자 정보 (BUSINESS_ADMIN인 경우)
        businessNumber: _selectedRole == UserRole.BUSINESS_ADMIN 
            ? _businessNumberController.text.replaceAll('-', '') 
            : null,
        businessName: _selectedRole == UserRole.BUSINESS_ADMIN 
            ? _businessNameController.text.trim() 
            : null,
      );

      if (success && mounted) {
        final loginSuccess = await userProvider.signIn(
          _usernameController.text.trim(),
          _passwordController.text,
        );
        if (!mounted) return;
        if (loginSuccess) {
          ToastHelper.showSuccess('가입을 환영합니다!');
          Navigator.of(context).popUntil((route) => route.isFirst);
        } else {
          ToastHelper.showSuccess('회원가입이 완료되었습니다. 로그인해주세요.');
          Navigator.pop(context);
        }
      }
    } catch (e) {
      debugPrint('❌ 회원가입 실패: $e');
      ToastHelper.showError('회원가입에 실패했습니다');
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }
  
// 비밀번호 검증강화
  String? _validatePassword(String? value) {
    if (value == null || value.isEmpty) {
      return '비밀번호를 입력해주세요';
    }
    
    if (value.length < 8) {
      return '비밀번호는 8자 이상이어야 합니다';
    }
    
    if (!RegExp(r'[a-zA-Z]').hasMatch(value)) {
      return '영문을 포함해야 합니다';
    }
    
    if (!RegExp(r'[0-9]').hasMatch(value)) {
      return '숫자를 포함해야 합니다';
    }
    
    if (!RegExp(r'[!@#$%^&*(),.?":{}|<>]').hasMatch(value)) {
      return '특수문자를 포함해야 합니다';
    }
    
    return null;
  }

  /// ✅ 사업장 관리자: 회원가입 후 사업장 등록 화면으로 (Storage 업로드 추가)
  Future<void> _registerUserAndGoToBusinessRegistration() async {
    // ✅ 중복 제출 방지
    if (_isSubmitting) return;
    setState(() => _isSubmitting = true);
    
    final userProvider = context.read<UserProvider>();
    
    try {
      // ✅ 사업자등록증 업로드
      String? businessLicenseImageUrl;
      final tempId = DateTime.now().millisecondsSinceEpoch.toString();
      
      if (_businessLicenseImagePath != null && !kIsWeb) {
        ToastHelper.showInfo('사업자등록증 업로드 중...');
        final storagePath = 'users/temp_$tempId/businessLicense_$tempId.jpg';
        businessLicenseImageUrl = await _storageService.uploadImage(_businessLicenseImagePath!, storagePath);
      }
      
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
        address: _addressController.text.trim(),
        detailAddress: _detailAddressController.text.trim(),
        businessNumber: _businessNumberController.text.replaceAll('-', ''),
        businessName: _businessNameController.text.trim(),
        businessLicenseImageUrl: businessLicenseImageUrl,
      );

      if (success && mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => const BusinessFormScreen(isFromSignUp: true),
          ),
        );
      }
    } catch (e) {
      debugPrint('❌ 회원가입 실패: $e');
      ToastHelper.showError('회원가입에 실패했습니다');
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
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
  void _syncEmail() {
    final local = _emailLocalController.text.trim();
    final domain = _selectedEmailDomain == null
        ? _emailDomainController.text.trim()
        : _selectedEmailDomain!;
    final full = (local.isEmpty || domain.isEmpty) ? '' : '$local@$domain';
    _emailController.text = full;
    setState(() {
      _currentEmail = full;
      _isEmailSent = false;
      _isEmailVerified = false;
    });
  }

  // ============================================================
  // 🎨 Build 메서드 + 이미지 업로드
  // ============================================================

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: Consumer<UserProvider>(
        builder: (context, userProvider, _) {
          return LoadingOverlay(
            // ✅ 중복 제출 상태도 로딩에 포함
            isLoading: userProvider.isLoading || _isSubmitting,
            message: _isSubmitting ? '서류 업로드 중...' : '회원가입 중...',
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    theme.primaryColor.withValues(alpha: 0.05),
                    theme.primaryColor.withValues(alpha: 0.1),
                  ],
                ),
              ),
              child: SafeArea(
                child: Column(
                  children: [
                    _buildHeader(),
                    _buildProgressBar(),
                    SizedBox(height: ResponsiveHelper.spacing(context, 16)),
                    Expanded(
                      child: SingleChildScrollView(
                        controller: _scrollController,
                        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                        padding: EdgeInsets.symmetric(
                          horizontal: ResponsiveHelper.spacing(context, 20),
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


  /// 사업자등록증 이미지 선택
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

  /// 신분증 이미지 선택
  Future<void> _pickIdCardImage() async {
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

  /// 통장사본 이미지 선택
  Future<void> _pickBankbookImage() async {
    final imagePath = await DocumentUploadHelper.pickAndVerifyBankbook(
      context,
      _nameController.text.trim(),
      expectedAccountNumber: _accountNumberController.text.trim().isEmpty 
          ? null 
          : _accountNumberController.text.trim(),
      expectedBankName: _selectedBank,
    );
    
    if (imagePath != null) {
      setState(() => _bankbookImagePath = imagePath);
    }
  }
  // ============================================================
  // 🔧 헤더, 진행바, 단계 컨텐츠
  // ============================================================

  /// 헤더
  Widget _buildHeader() {
    final theme = Theme.of(context);
    
    return Padding(
      padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 12)),
      child: Row(
        children: [
          Material(
            color: Colors.white.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(10),
            child: InkWell(
              onTap: _onStepCancel,
              borderRadius: BorderRadius.circular(10),
              child: Padding(
                padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 8)),
                child: Icon(
                  Icons.arrow_back,
                  color: theme.primaryColor,
                  size: ResponsiveHelper.iconSize(context, 22),
                ),
              ),
            ),
          ),
          SizedBox(width: ResponsiveHelper.spacing(context, 12)),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '회원가입',
                style: ResponsiveHelper.titleStyle(context).copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              SizedBox(height: ResponsiveHelper.spacing(context, 2)),
              Text(
                _currentStep == 0
                    ? '기본 정보 입력'
                    : _currentStep == 1
                        ? '이용 방법 선택'
                        : '추가 정보 (선택)',
                style: ResponsiveHelper.smallStyle(
                  context,
                  color: AppColors.grey600,
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
        horizontal: ResponsiveHelper.spacing(context, 32),
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
          SizedBox(width: ResponsiveHelper.spacing(context, 6)),
          Expanded(
            child: Container(
              height: ResponsiveHelper.spacing(context, 4),
              decoration: BoxDecoration(
                color: _currentStep >= 1 ? theme.primaryColor : AppColors.grey300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          SizedBox(width: ResponsiveHelper.spacing(context, 6)),
          Expanded(
            child: Container(
              height: ResponsiveHelper.spacing(context, 4),
              decoration: BoxDecoration(
                color: _currentStep >= 2 ? theme.primaryColor : AppColors.grey300,
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
        if (_selectedRole == UserRole.USER) {
          return _buildStep3UserDocuments();
        } else if (_selectedRole == UserRole.BUSINESS_ADMIN) {
          return _buildStep3BusinessDocuments();
        }
        return Container();
      default:
        return Container();
    }
  }
  // ============================================================
  // 📝 Step 1: 기본 정보 입력
  // ============================================================

  Widget _buildStep1BasicInfo() {
    return Container(
      padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 12)),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 16,
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
              focusNode: _nameFocus,
              textInputAction: TextInputAction.next,
              onFieldSubmitted: (_) => _usernameFocus.requestFocus(),
              validator: (value) {
                if (value == null || value.isEmpty) return '이름을 입력해주세요';
                return null;
              },
            ),
            
            SizedBox(height: ResponsiveHelper.spacing(context, 12)),
            
            // 아이디
            _buildTextField(
              controller: _usernameController,
              label: '아이디',
              hint: '영문소문자, 숫자 (4-20자)',
              icon: Icons.account_circle_outlined,
              focusNode: _usernameFocus,
              textInputAction: TextInputAction.next,
              onFieldSubmitted: (_) => _residentNumber1Focus.requestFocus(),
              suffixIcon: _currentUsername.isEmpty
                  ? null
                  : _isCheckingUsername
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: Padding(
                            padding: EdgeInsets.all(12),
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      : _isUsernameAvailable
                          ? Icon(
                              Icons.check_circle,
                              color: Colors.green,
                              size: ResponsiveHelper.iconSize(context, 22),
                            )
                          : _usernameError != null
                              ? Icon(
                                  Icons.cancel,
                                  color: AppColors.error,
                                  size: ResponsiveHelper.iconSize(context, 22),
                                )
                              : null,
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
                _usernameDebounce?.cancel();
                if (value.trim().length >= 4 &&
                    RegExp(r'^[a-z0-9_]+$').hasMatch(value.trim())) {
                  _usernameDebounce = Timer(
                    const Duration(milliseconds: 600),
                    _checkUsername,
                  );
                }
              },
            ),
            
            SizedBox(height: ResponsiveHelper.spacing(context, 12)),
            
            // 주민번호
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: TextFormField(
                    controller: _residentNumber1Controller,
                    focusNode: _residentNumber1Focus,
                    keyboardType: TextInputType.number,
                    textInputAction: TextInputAction.next,
                    onFieldSubmitted: (_) => _residentNumber2Focus.requestFocus(),
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(6),
                    ],
                    style: ResponsiveHelper.bodyStyle(context),
                    decoration: InputDecoration(
                      hintText: '990101',
                      hintStyle: TextStyle(color: AppColors.grey400),
                      prefixIcon: Icon(
                        Icons.credit_card,
                        color: Theme.of(context).primaryColor,
                        size: ResponsiveHelper.iconSize(context, 22),
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      filled: true,
                      fillColor: AppColors.grey50,
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: ResponsiveHelper.spacing(context, 12),
                        vertical: ResponsiveHelper.spacing(context, 12),
                      ),
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
                        _residentNumber2Focus.requestFocus();
                      }
                    },
                  ),
                ),
                Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: ResponsiveHelper.spacing(context, 6),
                  ),
                  child: Text('-', style: ResponsiveHelper.titleStyle(context)),
                ),
                Expanded(
                  flex: 2,
                  child: TextFormField(
                    controller: _residentNumber2Controller,
                    focusNode: _residentNumber2Focus,
                    keyboardType: TextInputType.number,
                    textInputAction: TextInputAction.next,
                    onFieldSubmitted: (_) => _emailFocus.requestFocus(),
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(1),
                    ],
                    style: ResponsiveHelper.bodyStyle(context),
                    decoration: InputDecoration(
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      filled: true,
                      fillColor: AppColors.grey50,
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: ResponsiveHelper.spacing(context, 12),
                        vertical: ResponsiveHelper.spacing(context, 12),
                      ),
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) return '필수';
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
                        _emailFocus.requestFocus();
                      }
                    },
                  ),
                ),
                Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: ResponsiveHelper.spacing(context, 6),
                  ),
                  child: Text('●●●●●●', style: ResponsiveHelper.smallStyle(context)),
                ),
              ],
            ),

            // 파싱 결과 표시
            if (_residentNumber1Controller.text.length == 6 && 
                _residentNumber2Controller.text.isNotEmpty)
              Padding(
                padding: EdgeInsets.only(
                  top: ResponsiveHelper.spacing(context, 6),
                ),
                child: Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: ResponsiveHelper.spacing(context, 10),
                    vertical: ResponsiveHelper.spacing(context, 6),
                  ),
                  decoration: BoxDecoration(
                    color: _parsedBirthDate != null && _parsedGender != null
                        ? AppColors.successBg
                        : AppColors.errorBg,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _parsedBirthDate != null && _parsedGender != null
                            ? Icons.check_circle
                            : Icons.error_outline,
                        color: _parsedBirthDate != null && _parsedGender != null
                            ? AppColors.successDark
                            : AppColors.errorDark,
                        size: ResponsiveHelper.iconSize(context, 16),
                      ),
                      SizedBox(width: ResponsiveHelper.spacing(context, 6)),
                      Expanded(
                        child: Text(
                          _parsedBirthDate != null && _parsedGender != null
                              ? '${_parsedBirthDate!.year}.${_parsedBirthDate!.month}.${_parsedBirthDate!.day} / $_parsedGender'
                              : _residentNumberError ?? '올바른 주민번호를 입력해주세요',
                          style: ResponsiveHelper.smallStyle(
                            context,
                            color: _parsedBirthDate != null && _parsedGender != null
                                ? AppColors.successDeep
                                : AppColors.errorDeep,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            
            SizedBox(height: ResponsiveHelper.spacing(context, 12)),

            // 이메일: [아이디] @ [도메인▼]
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 로컬 파트
                Expanded(
                  flex: 5,
                  child: TextFormField(
                    controller: _emailLocalController,
                    focusNode: _emailFocus,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    style: ResponsiveHelper.bodyStyle(context),
                    decoration: InputDecoration(
                      labelText: '이메일 아이디',
                      hintText: 'example',
                      hintStyle: TextStyle(color: AppColors.grey400),
                      prefixIcon: Icon(
                        Icons.email_outlined,
                        color: Theme.of(context).primaryColor,
                        size: ResponsiveHelper.iconSize(context, 22),
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    onChanged: (_) => _syncEmail(),
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? '이메일 아이디를 입력해주세요' : null,
                  ),
                ),

                // @ 구분자
                Padding(
                  padding: EdgeInsets.only(
                    top: ResponsiveHelper.spacing(context, 16),
                    left: ResponsiveHelper.spacing(context, 6),
                    right: ResponsiveHelper.spacing(context, 6),
                  ),
                  child: Text(
                    '@',
                    style: ResponsiveHelper.bodyStyle(context).copyWith(
                      fontWeight: FontWeight.w600,
                      color: AppColors.grey700,
                    ),
                  ),
                ),

                // 도메인 파트
                Expanded(
                  flex: 5,
                  child: _selectedEmailDomain == null
                      // 직접 입력 모드
                      ? TextFormField(
                          controller: _emailDomainController,
                          keyboardType: TextInputType.url,
                          textInputAction: TextInputAction.next,
                          style: ResponsiveHelper.bodyStyle(context),
                          decoration: InputDecoration(
                            labelText: '직접 입력',
                            hintText: 'example.com',
                            hintStyle: TextStyle(color: AppColors.grey400),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            suffixIcon: TextButton(
                              onPressed: () => setState(
                                  () => _selectedEmailDomain = 'naver.com'),
                              child: const Text('목록',
                                  style: TextStyle(fontSize: 11)),
                            ),
                          ),
                          onChanged: (_) => _syncEmail(),
                          validator: (v) => (v == null || v.trim().isEmpty)
                              ? '도메인을 입력해주세요'
                              : null,
                        )
                      // 드롭다운 모드
                      : DropdownButtonFormField<String>(
                          initialValue: _selectedEmailDomain,
                          isExpanded: true,
                          decoration: InputDecoration(
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 14),
                          ),
                          items: [
                            for (final d in [
                              'naver.com',
                              'gmail.com',
                              'kakao.com',
                              'daum.net',
                              'hanmail.net',
                            ])
                              DropdownMenuItem(
                                value: d,
                                child: Text(d,
                                    style: const TextStyle(fontSize: 14)),
                              ),
                            const DropdownMenuItem(
                              value: '__direct__',
                              child: Text('직접 입력',
                                  style: TextStyle(fontSize: 14)),
                            ),
                          ],
                          onChanged: (v) {
                            if (v == '__direct__') {
                              setState(() {
                                _selectedEmailDomain = null;
                                _emailDomainController.clear();
                              });
                              _syncEmail();
                            } else {
                              setState(() => _selectedEmailDomain = v);
                              _syncEmail();
                            }
                          },
                        ),
                ),
              ],
            ),

            // 이메일 인증 버튼
            if (_currentEmail.isNotEmpty) ...[
              SizedBox(height: ResponsiveHelper.spacing(context, 6)),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (_isEmailVerified)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.check_circle,
                            color: AppColors.successMedium,
                            size: ResponsiveHelper.iconSize(context, 18)),
                        const SizedBox(width: 4),
                        Text('인증 완료',
                            style: ResponsiveHelper.smallStyle(context,
                                color: AppColors.successDark)),
                      ],
                    )
                  else if (_isEmailSending)
                    const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2))
                  else
                    TextButton.icon(
                      onPressed: _sendEmailVerification,
                      icon: Icon(Icons.send,
                          size: 14,
                          color: Theme.of(context).primaryColor),
                      label: Text(
                        _isEmailSent ? '재발송' : '인증번호 받기',
                        style: ResponsiveHelper.smallStyle(context,
                            color: Theme.of(context).primaryColor),
                      ),
                    ),
                ],
              ),
            ],

            // 이메일 인증 코드 입력
            if (_isEmailSent && !_isEmailVerified) ...[
              SizedBox(height: ResponsiveHelper.spacing(context, 12)),
              _buildTextField(
                controller: _emailCodeController,
                label: '인증번호',
                hint: '6자리 숫자',
                icon: Icons.password,
                keyboardType: TextInputType.number,
                focusNode: _emailCodeFocus,
                textInputAction: TextInputAction.done,
                onFieldSubmitted: (_) => _verifyEmailCode(),
                onChanged: (value) {
                  if (value.length == 6 && !_isEmailVerifying) {
                    _verifyEmailCode();
                  }
                },
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(6),
                ],
                suffixIcon: _isEmailVerifying
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : TextButton(
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
            
            SizedBox(height: ResponsiveHelper.spacing(context, 12)),
            
            // 전화번호
            _buildTextField(
              controller: _phoneController,
              label: '전화번호',
              hint: '01012345678',
              icon: Icons.phone_outlined,
              keyboardType: TextInputType.phone,
              focusNode: _phoneFocus,
              textInputAction: TextInputAction.next,
              onFieldSubmitted: (_) => kIsWeb ? _addressFocus.requestFocus() : _detailAddressFocus.requestFocus(),
              onChanged: (value) {
                if (value.length == 11) {
                  Future.delayed(const Duration(milliseconds: 100), () {
                    if (mounted) {
                      kIsWeb
                          ? _addressFocus.requestFocus()
                          : _detailAddressFocus.requestFocus();
                    }
                  });
                }
              },
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
            
            SizedBox(height: ResponsiveHelper.spacing(context, 12)),

            // 주소
            if (kIsWeb) ...[
              _buildTextField(
                controller: _addressController,
                label: '주소',
                hint: '주소를 직접 입력해주세요 (임시)',
                icon: Icons.location_on_outlined,
                focusNode: _addressFocus,
                textInputAction: TextInputAction.next,
                onFieldSubmitted: (_) => _detailAddressFocus.requestFocus(),
                validator: (value) {
                  if (value == null || value.isEmpty) return '주소를 입력해주세요';
                  return null;
                },
              ),
            ] else ...[
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
                    size: ResponsiveHelper.iconSize(context, 22),
                  ),
                  onPressed: _searchAddress,
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) return '주소를 입력해주세요';
                  return null;
                },
              ),
            ],

            SizedBox(height: ResponsiveHelper.spacing(context, 12)),

            // 상세 주소
            _buildTextField(
              controller: _detailAddressController,
              label: '상세 주소',
              hint: '동/호수 등 상세 주소',
              icon: Icons.home_outlined,
              focusNode: _detailAddressFocus,
              textInputAction: TextInputAction.next,
              onFieldSubmitted: (_) => _passwordFocus.requestFocus(),
              validator: (value) => null,
            ),

            SizedBox(height: ResponsiveHelper.spacing(context, 12)),
            
            // 비밀번호
            _buildTextField(
              controller: _passwordController,
              label: '비밀번호',
              hint: '영문+숫자+특수문자 8자 이상',
              icon: Icons.lock_outline,
              obscureText: _obscurePassword,
              focusNode: _passwordFocus,
              textInputAction: TextInputAction.next,
              onFieldSubmitted: (_) => _confirmPasswordFocus.requestFocus(),
              suffixIcon: IconButton(
                icon: Icon(
                  _obscurePassword ? Icons.visibility_off : Icons.visibility,
                  color: AppColors.grey600,
                  size: ResponsiveHelper.iconSize(context, 20),
                ),
                onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
              ),
              validator: _validatePassword,
              onChanged: (_) => setState(() {}),
            ),

            // 비밀번호 조건 체크리스트
            if (_passwordController.text.isNotEmpty) ...[
              SizedBox(height: ResponsiveHelper.spacing(context, 8)),
              _buildPasswordChecklist(),
            ],

            SizedBox(height: ResponsiveHelper.spacing(context, 12)),

            // 비밀번호 확인
            _buildTextField(
              controller: _confirmPasswordController,
              label: '비밀번호 확인',
              hint: '비밀번호를 다시 입력',
              icon: Icons.lock_outline,
              obscureText: _obscureConfirmPassword,
              focusNode: _confirmPasswordFocus,
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) => FocusScope.of(context).unfocus(),
              suffixIcon: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_confirmPasswordController.text.isNotEmpty)
                    Icon(
                      _confirmPasswordController.text == _passwordController.text
                          ? Icons.check_circle
                          : Icons.cancel,
                      color: _confirmPasswordController.text == _passwordController.text
                          ? AppColors.success
                          : AppColors.error,
                      size: ResponsiveHelper.iconSize(context, 20),
                    ),
                  IconButton(
                    icon: Icon(
                      _obscureConfirmPassword ? Icons.visibility_off : Icons.visibility,
                      color: AppColors.grey600,
                      size: ResponsiveHelper.iconSize(context, 20),
                    ),
                    onPressed: () => setState(() => _obscureConfirmPassword = !_obscureConfirmPassword),
                  ),
                ],
              ),
              validator: (value) {
                if (value == null || value.isEmpty) return '비밀번호를 다시 입력해주세요';
                if (value != _passwordController.text) return '비밀번호가 일치하지 않습니다';
                return null;
              },
              onChanged: (_) => setState(() {}),
            ),
            
            SizedBox(height: ResponsiveHelper.spacing(context, 16)),

            // 법적 동의
            _buildConsentSection(),

            SizedBox(height: ResponsiveHelper.spacing(context, 8)),
          ],
        ),
      ),
    );
  }

  Widget _buildPasswordChecklist() {
    final pw = _passwordController.text;
    final checks = [
      (RegExp(r'.{8,}').hasMatch(pw), '8자 이상'),
      (RegExp(r'[a-zA-Z]').hasMatch(pw), '영문 포함'),
      (RegExp(r'[0-9]').hasMatch(pw), '숫자 포함'),
      (RegExp(r'[!@#\$%^&*(),.?":{}|<>]').hasMatch(pw), '특수문자 포함'),
    ];
    final passed = checks.where((c) => c.$1).length;

    // 강도 색상
    final strengthColor = passed <= 1
        ? AppColors.error
        : passed == 2
            ? AppColors.warning
            : passed == 3
                ? AppColors.yellowDark
                : AppColors.success;
    final strengthLabel = passed <= 1
        ? '약함'
        : passed == 2
            ? '보통'
            : passed == 3
                ? '강함'
                : '매우 강함';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 강도 바
        Row(
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: passed / 4,
                  backgroundColor: AppColors.grey200,
                  valueColor: AlwaysStoppedAnimation(strengthColor),
                  minHeight: 5,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              strengthLabel,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: strengthColor,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        // 조건 2열 고정 그리드
        Row(
          children: [
            _buildCheckItem(checks[0]),
            const SizedBox(width: 12),
            _buildCheckItem(checks[1]),
          ],
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            _buildCheckItem(checks[2]),
            const SizedBox(width: 12),
            _buildCheckItem(checks[3]),
          ],
        ),
      ],
    );
  }

  Widget _buildCheckItem((bool, String) check) {
    final (passed, label) = check;
    return Expanded(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            passed ? Icons.check_circle : Icons.radio_button_unchecked,
            size: 13,
            color: passed ? AppColors.success : AppColors.grey400,
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: passed ? AppColors.successDark : AppColors.grey500,
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // ✅ 법적 동의 섹션
  // ============================================================

  Widget _buildConsentSection() {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(),
        SizedBox(height: ResponsiveHelper.spacing(context, 4)),

        // 전체 동의
        InkWell(
          onTap: () {
            setState(() {
              _agreedToAll = !_agreedToAll;
              _agreedToTerms = _agreedToAll;
              _agreedToPrivacy = _agreedToAll;
              _agreedToMarketing = _agreedToAll;
            });
          },
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: EdgeInsets.symmetric(
              horizontal: ResponsiveHelper.spacing(context, 4),
              vertical: ResponsiveHelper.spacing(context, 8),
            ),
            child: Row(
              children: [
                Icon(
                  _agreedToAll
                      ? Icons.check_circle
                      : Icons.check_circle_outline,
                  color: _agreedToAll ? theme.primaryColor : AppColors.grey400,
                  size: ResponsiveHelper.iconSize(context, 22),
                ),
                SizedBox(width: ResponsiveHelper.spacing(context, 10)),
                Text(
                  '전체 동의',
                  style: ResponsiveHelper.bodyStyle(context).copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ),

        const Divider(height: 1),
        SizedBox(height: ResponsiveHelper.spacing(context, 4)),

        // [필수] 이용약관
        _buildConsentRow(
          label: '[필수] 서비스 이용약관',
          agreed: _agreedToTerms,
          onChanged: (v) {
            setState(() {
              _agreedToTerms = v;
              _agreedToAll =
                  _agreedToTerms && _agreedToPrivacy && _agreedToMarketing;
            });
          },
          onViewTap: () => _showTermsDialog(),
        ),

        // [필수] 개인정보처리방침
        _buildConsentRow(
          label: '[필수] 개인정보 처리방침',
          agreed: _agreedToPrivacy,
          onChanged: (v) {
            setState(() {
              _agreedToPrivacy = v;
              _agreedToAll =
                  _agreedToTerms && _agreedToPrivacy && _agreedToMarketing;
            });
          },
          onViewTap: () => _showPrivacyDialog(),
        ),

        // [선택] 마케팅
        _buildConsentRow(
          label: '[선택] 마케팅 정보 수신 동의',
          agreed: _agreedToMarketing,
          onChanged: (v) {
            setState(() {
              _agreedToMarketing = v;
              _agreedToAll =
                  _agreedToTerms && _agreedToPrivacy && _agreedToMarketing;
            });
          },
        ),
      ],
    );
  }

  Widget _buildConsentRow({
    required String label,
    required bool agreed,
    required void Function(bool) onChanged,
    VoidCallback? onViewTap,
  }) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.symmetric(
        vertical: ResponsiveHelper.spacing(context, 2),
      ),
      child: Row(
        children: [
          InkWell(
            onTap: () => onChanged(!agreed),
            borderRadius: BorderRadius.circular(4),
            child: Icon(
              agreed ? Icons.check_circle : Icons.check_circle_outline,
              color: agreed ? theme.primaryColor : AppColors.grey400,
              size: ResponsiveHelper.iconSize(context, 20),
            ),
          ),
          SizedBox(width: ResponsiveHelper.spacing(context, 8)),
          Expanded(
            child: InkWell(
              onTap: () => onChanged(!agreed),
              child: Text(
                label,
                style: ResponsiveHelper.smallStyle(
                  context,
                  color: AppColors.grey700,
                ),
              ),
            ),
          ),
          if (onViewTap != null)
            TextButton(
              onPressed: onViewTap,
              style: TextButton.styleFrom(
                padding: EdgeInsets.symmetric(
                  horizontal: ResponsiveHelper.spacing(context, 4),
                ),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(
                '보기',
                style: ResponsiveHelper.tinyStyle(
                  context,
                  color: AppColors.grey500,
                ).copyWith(decoration: TextDecoration.underline),
              ),
            ),
        ],
      ),
    );
  }

  void _showTermsDialog() {
    showDialog(
      context: context,
      builder: (context) => _buildLegalDialog(
        title: '서비스 이용약관',
        content: '''제1조 (목적)
본 약관은 AlFit(이하 "회사")이 제공하는 인력 매칭 플랫폼 서비스(이하 "서비스")의 이용에 관한 기본적인 사항을 규정합니다.

제2조 (정의)
① "회원"이란 본 약관에 동의하고 서비스에 가입한 자를 말합니다.
② "지원자"란 사업장에 근무를 지원하는 회원을 말합니다.
③ "사업장 관리자"란 근무 공고를 등록하고 지원자를 관리하는 회원을 말합니다.

제3조 (서비스 내용)
회사는 사업장과 구직자를 연결하는 인력 매칭 중개 플랫폼을 운영합니다. 실제 근로계약은 사업장과 지원자 간에 체결되며, 회사는 중개자로서의 역할을 합니다.

제4조 (이용계약)
① 회원이 되려는 자는 본 약관에 동의하고 가입 신청을 완료하여야 합니다.
② 만 14세 미만은 서비스에 가입할 수 없습니다.

제5조 (회원의 의무)
① 회원은 정확한 정보를 제공해야 하며, 변경 시 즉시 수정해야 합니다.
② 타인의 정보를 도용하거나 허위 정보를 입력해서는 안 됩니다.
③ 서비스를 통해 알게 된 타 회원의 개인정보를 무단 수집·이용해서는 안 됩니다.
④ 서비스의 안정적인 운영을 방해하는 행위를 해서는 안 됩니다.

제6조 (서비스 이용)
① 서비스는 원칙적으로 연중무휴 24시간 제공합니다.
② 시스템 점검 등의 사유로 일시 중단될 수 있으며, 사전에 공지합니다.

제7조 (책임 제한)
① 회사는 중개 플랫폼으로서 사업장과 지원자 간 근로관계에서 발생하는 분쟁에 대해 직접적인 책임을 지지 않습니다.
② 천재지변, 불가항력으로 인한 서비스 중단에 대해 책임지지 않습니다.

제8조 (준거법 및 분쟁해결)
본 약관은 대한민국 법률에 따라 해석되며, 분쟁 발생 시 관할 법원은 회사 소재지 관할 법원으로 합니다.''',
      ),
    );
  }

  void _showPrivacyDialog() {
    showDialog(
      context: context,
      builder: (context) => _buildLegalDialog(
        title: '개인정보 처리방침',
        content: '''AlFit은 개인정보보호법 제30조에 따라 이용자의 개인정보를 보호하고 관련 고충을 신속하게 처리하기 위해 다음과 같이 개인정보 처리방침을 수립·공개합니다.

1. 수집하는 개인정보 항목
• 필수: 이름, 생년월일, 성별, 이메일, 비밀번호, 전화번호, 주소
• 선택: 신분증 사진, 통장사본, 계좌번호
• 사업장 관리자 추가: 사업자등록번호, 사업장명, 대표자명, 사업자등록증

2. 개인정보 수집 및 이용 목적
• 회원 식별 및 서비스 제공
• 급여 지급을 위한 계좌 정보 처리
• 근로계약 체결 및 인력 매칭
• 서비스 이용 현황 파악 및 부정 이용 방지
• 고객 상담 및 민원 처리

3. 개인정보 보유 및 이용 기간
• 회원 탈퇴 시 즉시 삭제
• 단, 관련 법령에 따라 아래 기간 동안 보존
  - 계약 또는 청약철회 기록: 5년 (전자상거래법)
  - 소비자 불만·분쟁처리 기록: 3년 (전자상거래법)

4. 개인정보 제3자 제공
지원자의 이름, 연락처, 지원 이력을 해당 사업장 관리자에게 제공합니다.
(공고 지원 시 이에 동의한 것으로 간주합니다)

5. 개인정보 처리 위탁
현재 개인정보 처리를 외부에 위탁하는 업체는 없습니다.

6. 정보 주체의 권리
회원은 언제든지 개인정보 열람, 정정, 삭제, 처리 정지를 요구할 수 있습니다.
앱 내 고객센터 또는 이메일로 요청하시면 지체 없이 조치합니다.

7. 개인정보 보호책임자
개인정보 관련 문의는 서비스 내 문의하기를 통해 접수해주세요.''',
      ),
    );
  }

  Widget _buildLegalDialog({
    required String title,
    required String content,
  }) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(
        title,
        style: ResponsiveHelper.subtitleStyle(context).copyWith(
          fontWeight: FontWeight.bold,
        ),
      ),
      content: SizedBox(
        width: double.maxFinite,
        height: 400,
        child: SingleChildScrollView(
          child: Text(
            content,
            style: ResponsiveHelper.smallStyle(
              context,
              color: AppColors.grey700,
            ).copyWith(height: 1.6),
          ),
        ),
      ),
      actions: [
        ElevatedButton(
          onPressed: () => Navigator.pop(context),
          style: ElevatedButton.styleFrom(
            backgroundColor: Theme.of(context).primaryColor,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          child: Text(
            '확인',
            style: ResponsiveHelper.bodyStyle(context)
                .copyWith(color: Colors.white),
          ),
        ),
      ],
    );
  }

  // ============================================================
  // 📝 Step 2: 역할 선택
  // ============================================================

  Widget _buildStep2RoleSelection() {
    return Column(
      children: [
        Container(
          padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 12)),
          decoration: BoxDecoration(
            color: AppColors.infoBg,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Icon(
                Icons.help_outline,
                color: AppColors.infoDark,
                size: ResponsiveHelper.iconSize(context, 22),
              ),
              SizedBox(width: ResponsiveHelper.spacing(context, 10)),
              Expanded(
                child: Text(
                  '어떻게 이용하시나요?',
                  style: ResponsiveHelper.bodyStyle(
                    context,
                    color: AppColors.infoDeep,
                  ),
                ),
              ),
            ],
          ),
        ),
        SizedBox(height: ResponsiveHelper.spacing(context, 20)),
        _buildRoleCard(
          role: UserRole.USER,
          icon: Icons.person,
          title: '지원자로 이용',
          description: '공고에 지원하고 일정을 관리합니다',
          color: AppColors.successMedium,
          features: ['공고 검색 및 지원', '나의 근무일정 관리', '지원 내역 확인'],
        ),
        SizedBox(height: ResponsiveHelper.spacing(context, 12)),
        _buildRoleCard(
          role: UserRole.BUSINESS_ADMIN,
          icon: Icons.business_center,
          title: '사업장 관리자로 이용',
          description: '공고를 생성하고 지원자를 관리합니다',
          color: AppColors.infoMedium,
          features: ['공고 생성 및 관리', '지원자 승인/거절', '인력 현황 파악'],
        ),
      ],
    );
  }
  // ============================================================
  // 📝 Step 3-A: 지원자 추가 정보
  // ============================================================

  Widget _buildStep3UserDocuments() {
    return Column(
      children: [
        // 안내 카드
        Container(
          padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 12)),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [AppColors.infoBg, AppColors.infoExtraLight],
            ),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.infoLight, width: 1.5),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Container(
                    padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 10)),
                    decoration: BoxDecoration(
                      color: AppColors.infoMedium,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.info_outline,
                      color: Colors.white,
                      size: ResponsiveHelper.iconSize(context, 24),
                    ),
                  ),
                  SizedBox(width: ResponsiveHelper.spacing(context, 12)),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '서류 제출 안내',
                          style: ResponsiveHelper.subtitleStyle(context).copyWith(
                            fontWeight: FontWeight.bold,
                            color: AppColors.infoDeep,
                          ),
                        ),
                        Text(
                          '본인 명의 서류만 인증 가능합니다',
                          style: ResponsiveHelper.smallStyle(
                            context,
                            color: AppColors.infoDark,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              SizedBox(height: ResponsiveHelper.spacing(context, 12)),
              Container(
                padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 10)),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildNoticeItem('✓ 신분증과 통장의 이름이 일치해야 합니다', AppColors.infoDeep),
                    SizedBox(height: ResponsiveHelper.spacing(context, 4)),
                    _buildNoticeItem('✓ 선명한 사진을 촬영해주세요', AppColors.infoDeep),
                  ],
                ),
              ),
            ],
          ),
        ),
        
        SizedBox(height: ResponsiveHelper.spacing(context, 16)),
        
        // 신분증 업로드
        _buildIdCardUploadCard(),
        
        SizedBox(height: ResponsiveHelper.spacing(context, 16)),
        
        // 통장 정보 카드
        _buildBankInfoCard(),
        
        SizedBox(height: ResponsiveHelper.spacing(context, 16)),
        
        // 나중에 하기 안내
        Container(
          padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 10)),
          decoration: BoxDecoration(
            color: AppColors.grey100,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Icon(
                Icons.info_outline,
                color: AppColors.grey600,
                size: ResponsiveHelper.iconSize(context, 18),
              ),
              SizedBox(width: ResponsiveHelper.spacing(context, 10)),
              Expanded(
                child: Text(
                  '지금 등록하지 않아도 설정에서 추가할 수 있습니다.',
                  style: ResponsiveHelper.smallStyle(
                    context,
                    color: AppColors.grey700,
                  ),
                ),
              ),
            ],
          ),
        ),
        
        SizedBox(height: ResponsiveHelper.spacing(context, 16)),
      ],
    );
  }

  // 안내 항목 빌더
  Widget _buildNoticeItem(String text, Color color) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(
            text,
            style: ResponsiveHelper.smallStyle(context, color: color),
          ),
        ),
      ],
    );
  }

  // 신분증 업로드 카드
  Widget _buildIdCardUploadCard() {
    return Container(
      padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 12)),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.grey300),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
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
                size: ResponsiveHelper.iconSize(context, 22),
              ),
              SizedBox(width: ResponsiveHelper.spacing(context, 10)),
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
                  color: AppColors.successMedium,
                  size: ResponsiveHelper.iconSize(context, 22),
                ),
            ],
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 12)),
          InkWell(
            onTap: _pickIdCardImage,
            borderRadius: BorderRadius.circular(10),
            child: Container(
              height: ResponsiveHelper.spacing(context, 100),
              decoration: BoxDecoration(
                color: AppColors.grey100,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: _idCardImagePath != null 
                      ? AppColors.successSoft 
                      : AppColors.grey300,
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
                      size: ResponsiveHelper.iconSize(context, 40),
                      color: _idCardImagePath != null 
                          ? AppColors.successMedium 
                          : AppColors.grey400,
                    ),
                    SizedBox(height: ResponsiveHelper.spacing(context, 6)),
                    Text(
                      _idCardImagePath != null 
                          ? '업로드 완료 (재촬영하려면 터치)'
                          : '신분증 사진 업로드',
                      style: ResponsiveHelper.smallStyle(
                        context,
                        color: _idCardImagePath != null 
                            ? AppColors.successDark 
                            : AppColors.grey600,
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

  // 통장 정보 카드
  Widget _buildBankInfoCard() {
    return Container(
      padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 12)),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.grey300),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
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
                Icons.account_balance_wallet,
                color: Theme.of(context).primaryColor,
                size: ResponsiveHelper.iconSize(context, 22),
              ),
              SizedBox(width: ResponsiveHelper.spacing(context, 10)),
              Text(
                '급여 통장 정보',
                style: ResponsiveHelper.bodyStyle(context).copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 12)),
          
          // 은행 선택
          DropdownButtonFormField<String>(
            initialValue: _selectedBank,
            decoration: InputDecoration(
              labelText: '은행',
              prefixIcon: Icon(Icons.account_balance, size: ResponsiveHelper.iconSize(context, 20)),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              isDense: true,
              contentPadding: EdgeInsets.symmetric(
                horizontal: ResponsiveHelper.spacing(context, 12),
                vertical: ResponsiveHelper.spacing(context, 12),
              ),
            ),
            items: [
              'KB국민은행', '신한은행', 'NH농협은행', '우리은행', '하나은행',
              'IBK기업은행', '카카오뱅크', '토스뱅크', '새마을금고', '우체국',
            ].map((bank) => DropdownMenuItem(
              value: bank,
              child: Text(bank, style: ResponsiveHelper.bodyStyle(context)),
            )).toList(),
            onChanged: (value) {
              setState(() => _selectedBank = value);
              Future.delayed(const Duration(milliseconds: 200), () {
                if (mounted) _accountNumberFocus.requestFocus();
              });
            },
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 12)),
          
          // 계좌번호 입력
          TextFormField(
            controller: _accountNumberController,
            focusNode: _accountNumberFocus,
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.done,
            onFieldSubmitted: (_) => FocusScope.of(context).unfocus(),
            style: ResponsiveHelper.bodyStyle(context),
            decoration: InputDecoration(
              labelText: '계좌번호',
              hintText: '- 없이 숫자만 입력',
              prefixIcon: Icon(Icons.credit_card, size: ResponsiveHelper.iconSize(context, 20)),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              isDense: true,
              contentPadding: EdgeInsets.symmetric(
                horizontal: ResponsiveHelper.spacing(context, 12),
                vertical: ResponsiveHelper.spacing(context, 12),
              ),
            ),
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 10)),
          
          // 예금주 안내
          Container(
            padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 10)),
            decoration: BoxDecoration(
              color: Colors.green.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.info_outline,
                  color: AppColors.successDark,
                  size: ResponsiveHelper.iconSize(context, 16),
                ),
                SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                Expanded(
                  child: Text(
                    '예금주: ${_nameController.text.isEmpty ? "(이름 입력 필요)" : _nameController.text}',
                    style: ResponsiveHelper.smallStyle(
                      context,
                      color: AppColors.successDeep,
                    ),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 12)),
          
          // 통장사본 업로드
          InkWell(
            onTap: _pickBankbookImage,
            borderRadius: BorderRadius.circular(10),
            child: Container(
              height: ResponsiveHelper.spacing(context, 100),
              decoration: BoxDecoration(
                color: AppColors.grey100,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: _bankbookImagePath != null 
                      ? AppColors.successSoft 
                      : AppColors.grey300,
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
                      size: ResponsiveHelper.iconSize(context, 40),
                      color: _bankbookImagePath != null 
                          ? AppColors.successMedium 
                          : AppColors.grey400,
                    ),
                    SizedBox(height: ResponsiveHelper.spacing(context, 6)),
                    Text(
                      _bankbookImagePath != null 
                          ? '통장사본 업로드 완료'
                          : '통장사본 사진 업로드',
                      style: ResponsiveHelper.smallStyle(
                        context,
                        color: _bankbookImagePath != null 
                            ? AppColors.successDark 
                            : AppColors.grey600,
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
  // ============================================================
  // 📝 Step 3-B: 사업장 관리자 추가 정보
  // ============================================================

  Widget _buildStep3BusinessDocuments() {
    final theme = Theme.of(context);
    
    return Column(
      children: [
        // 안내 헤더
        Container(
          padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 12)),
          decoration: BoxDecoration(
            color: theme.primaryColor.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: theme.primaryColor.withValues(alpha: 0.3),
            ),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Icon(
                    Icons.business_center,
                    color: theme.primaryColor,
                    size: ResponsiveHelper.iconSize(context, 24),
                  ),
                  SizedBox(width: ResponsiveHelper.spacing(context, 10)),
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
              SizedBox(height: ResponsiveHelper.spacing(context, 8)),
              Text(
                '• 모든 항목은 선택사항입니다.\n• 지금 입력하시면 사업장 등록이 더 빠릅니다.',
                style: ResponsiveHelper.smallStyle(
                  context,
                  color: theme.textTheme.bodySmall?.color,
                ),
              ),
            ],
          ),
        ),
        
        SizedBox(height: ResponsiveHelper.spacing(context, 16)),
        
        // 입력 카드 섹션
        Container(
          padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 12)),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildBusinessNumberField(),
              SizedBox(height: ResponsiveHelper.spacing(context, 12)),
              _buildTextField(
                controller: _businessNameController,
                label: '상호명',
                hint: '예: 홍길동 물류센터',
                icon: Icons.store_outlined,
                focusNode: _businessNameFocus,
                textInputAction: TextInputAction.next,
                onFieldSubmitted: (_) => _ceoNameFocus.requestFocus(),
                validator: (value) {
                  if (value != null && value.isNotEmpty && value.length < 2) {
                    return '2자 이상 입력해주세요';
                  }
                  return null;
                },
              ),
              SizedBox(height: ResponsiveHelper.spacing(context, 12)),
              _buildCEONameField(),
            ],
          ),
        ),
        
        SizedBox(height: ResponsiveHelper.spacing(context, 16)),
        
        // 서류 업로드 섹션
        Text(
          '사업자등록증',
          style: ResponsiveHelper.subtitleStyle(context).copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        SizedBox(height: ResponsiveHelper.spacing(context, 10)),
        
        _buildDocumentUploadCard(
          title: '사업자등록증',
          description: '사업자등록증을 촬영해주세요',
          icon: Icons.business,
          imagePath: _businessLicenseImagePath,
          color: theme.primaryColor,
          onTap: _pickBusinessLicenseImage,
        ),
        
        SizedBox(height: ResponsiveHelper.spacing(context, 16)),
        
        // 나중에 하기 안내
        Container(
          padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 10)),
          decoration: BoxDecoration(
            color: AppColors.grey100,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Icon(
                Icons.info_outline,
                color: AppColors.grey600,
                size: ResponsiveHelper.iconSize(context, 18),
              ),
              SizedBox(width: ResponsiveHelper.spacing(context, 10)),
              Expanded(
                child: Text(
                  '지금 등록하지 않아도 설정에서 추가할 수 있습니다.',
                  style: ResponsiveHelper.smallStyle(
                    context,
                    color: AppColors.grey700,
                  ),
                ),
              ),
            ],
          ),
        ),
        
        SizedBox(height: ResponsiveHelper.spacing(context, 16)),
      ],
    );
  }

  /// 사업자등록번호 입력 필드
  Widget _buildBusinessNumberField() {
    final theme = Theme.of(context);
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextFormField(
          controller: _businessNumberController,
          keyboardType: TextInputType.number,
          textInputAction: TextInputAction.next,
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
              color: AppColors.grey400,
            ),
            prefixIcon: Icon(
              Icons.badge_outlined,
              color: theme.primaryColor,
              size: ResponsiveHelper.iconSize(context, 22),
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: AppColors.grey300),
            ),
            filled: true,
            fillColor: AppColors.grey50,
            isDense: true,
            contentPadding: EdgeInsets.symmetric(
              horizontal: ResponsiveHelper.spacing(context, 12),
              vertical: ResponsiveHelper.spacing(context, 12),
            ),
          ),
          onChanged: (value) {
            setState(() {});
            if (value.length == 10) {
              _businessNameFocus.requestFocus();
            }
          },
          onFieldSubmitted: (_) => _businessNameFocus.requestFocus(),
          validator: (value) {
            if (value != null && value.isNotEmpty && value.length != 10) {
              return '10자리를 입력해주세요';
            }
            return null;
          },
        ),
        
        if (_businessNumberController.text.length == 10)
          Padding(
            padding: EdgeInsets.only(
              top: ResponsiveHelper.spacing(context, 6),
              left: ResponsiveHelper.spacing(context, 12),
            ),
            child: Text(
              '형식: ${_formatBusinessNumber(_businessNumberController.text)}',
              style: ResponsiveHelper.tinyStyle(
                context,
                color: AppColors.successDark,
              ),
            ),
          ),
      ],
    );
  }

  /// 대표자명 필드
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
                focusNode: _ceoNameFocus,
                textInputAction: TextInputAction.done,
                onFieldSubmitted: (_) => FocusScope.of(context).unfocus(),
                style: ResponsiveHelper.bodyStyle(context),
                decoration: InputDecoration(
                  labelText: '대표자명',
                  hintText: '예: 홍길동',
                  hintStyle: ResponsiveHelper.smallStyle(
                    context,
                    color: AppColors.grey400,
                  ),
                  prefixIcon: Icon(
                    Icons.person_outline,
                    color: theme.primaryColor,
                    size: ResponsiveHelper.iconSize(context, 22),
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: AppColors.grey300),
                  ),
                  filled: true,
                  fillColor: AppColors.grey50,
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: ResponsiveHelper.spacing(context, 12),
                    vertical: ResponsiveHelper.spacing(context, 12),
                  ),
                ),
                validator: (value) {
                  if (value != null && value.isNotEmpty && value.length < 2) {
                    return '2자 이상 입력해주세요';
                  }
                  return null;
                },
              ),
            ),
            SizedBox(width: ResponsiveHelper.spacing(context, 6)),
            TextButton(
              onPressed: () {
                setState(() {
                  _ceoNameController.text = _nameController.text;
                });
              },
              child: Text(
                '이름\n가져오기',
                textAlign: TextAlign.center,
                style: ResponsiveHelper.tinyStyle(
                  context,
                  color: theme.primaryColor,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// 사업자등록번호 포맷팅
  String _formatBusinessNumber(String value) {
    final digits = value.replaceAll(RegExp(r'\D'), '');
    if (digits.length != 10) return value;
    
    return '${digits.substring(0, 3)}-${digits.substring(3, 5)}-${digits.substring(5, 10)}';
  }
  // ============================================================
  // 🔧 공통 위젯들
  // ============================================================

  /// 서류 업로드 카드
  Widget _buildDocumentUploadCard({
    required String title,
    required String description,
    required IconData icon,
    String? imagePath,
    required Color color,
    required VoidCallback onTap,
  }) {
    final isUploaded = imagePath != null;
    
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 12)),
        decoration: BoxDecoration(
          color: isUploaded ? color.withValues(alpha: 0.1) : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isUploaded ? color : AppColors.grey300,
            width: isUploaded ? 2 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 10)),
              decoration: BoxDecoration(
                color: isUploaded ? color : color.withValues(alpha: 0.2),
                shape: BoxShape.circle,
              ),
              child: Icon(
                isUploaded ? Icons.check : icon,
                color: isUploaded ? Colors.white : color,
                size: ResponsiveHelper.iconSize(context, 28),
              ),
            ),
            SizedBox(width: ResponsiveHelper.spacing(context, 12)),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: ResponsiveHelper.bodyStyle(context).copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: ResponsiveHelper.spacing(context, 2)),
                  Text(
                    description,
                    style: ResponsiveHelper.smallStyle(
                      context,
                      color: AppColors.grey600,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.camera_alt,
              color: color,
              size: ResponsiveHelper.iconSize(context, 22),
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
    bool readOnly = false,
    VoidCallback? onTap,
    Widget? suffixIcon,
    String? Function(String?)? validator,
    void Function(String)? onChanged,
    TextInputAction? textInputAction,
    void Function(String)? onFieldSubmitted,
    FocusNode? focusNode,
  }) {
    final theme = Theme.of(context);
    
    return TextFormField(
      controller: controller,
      focusNode: focusNode,  
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      obscureText: obscureText,
      enabled: enabled,
      readOnly: readOnly,
      onTap: onTap,
      textInputAction: textInputAction,
      onFieldSubmitted: onFieldSubmitted,
      style: ResponsiveHelper.bodyStyle(context),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        hintStyle: ResponsiveHelper.smallStyle(
          context,
          color: AppColors.grey400,
        ),
        prefixIcon: Icon(
          icon,
          color: theme.primaryColor,
          size: ResponsiveHelper.iconSize(context, 22),
        ),
        suffixIcon: suffixIcon,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: AppColors.grey300),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: AppColors.grey300),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: theme.primaryColor, width: 2),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: AppColors.grey200),
        ),
        filled: true,
        fillColor: enabled ? AppColors.grey50 : AppColors.grey100,
        isDense: true,
        contentPadding: EdgeInsets.symmetric(
          horizontal: ResponsiveHelper.spacing(context, 12),
          vertical: ResponsiveHelper.spacing(context, 12),
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
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 12)),
        decoration: BoxDecoration(
          color: isSelected ? color.withValues(alpha: 0.1) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? color : AppColors.grey300,
            width: isSelected ? 2 : 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: color.withValues(alpha: 0.2),
                    blurRadius: 10,
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
                  padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 10)),
                  decoration: BoxDecoration(
                    color: isSelected ? color : AppColors.grey200,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    icon,
                    color: isSelected ? Colors.white : color,
                    size: ResponsiveHelper.iconSize(context, 24),
                  ),
                ),
                SizedBox(width: ResponsiveHelper.spacing(context, 12)),
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
                      SizedBox(height: ResponsiveHelper.spacing(context, 2)),
                      Text(
                        description,
                        style: ResponsiveHelper.smallStyle(
                          context,
                          color: AppColors.grey600,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  isSelected ? Icons.check_circle : Icons.radio_button_unchecked,
                  color: isSelected ? color : AppColors.grey400,
                  size: ResponsiveHelper.iconSize(context, 24),
                ),
              ],
            ),
            SizedBox(height: ResponsiveHelper.spacing(context, 10)),
            Divider(color: AppColors.grey300, height: 1),
            SizedBox(height: ResponsiveHelper.spacing(context, 8)),
            ...features.map((feature) => Padding(
              padding: EdgeInsets.only(
                bottom: ResponsiveHelper.spacing(context, 4),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.check,
                    size: ResponsiveHelper.iconSize(context, 14),
                    color: isSelected ? color : AppColors.grey600,
                  ),
                  SizedBox(width: ResponsiveHelper.spacing(context, 6)),
                  Text(
                    feature,
                    style: ResponsiveHelper.smallStyle(
                      context,
                      color: isSelected ? Colors.black87 : AppColors.grey700,
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
      padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 16)),
      child: ElevatedButton(
        // ✅ 중복 제출 방지
        onPressed: (userProvider.isLoading || _isSubmitting) ? null : _onStepContinue,
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