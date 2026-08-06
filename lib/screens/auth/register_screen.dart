import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter/services.dart';
import '../../models/core/user_model.dart';
import '../../providers/user_provider.dart';
import '../../widgets/common/loading_widget.dart';
import '../../utils/responsive_helper.dart';
import '../../services/auth_service.dart';
import '../../services/storage_service.dart';
import '../../services/analytics_service.dart';
import '../../services/firestore_service.dart';
import '../../services/legal_terms_service.dart';
import '../../services/phone_verification_service.dart';
import '../../services/pass_verification_service.dart';
import '../../models/core/legal_terms_model.dart';
import '../../widgets/inputs/daum_address_search.dart';
import '../../utils/document_upload_helper.dart';
import '../../utils/toast_helper.dart';
import '../business_admin/business_form_screen.dart';
import '../../widgets/auth/pass_auth_button.dart';
import '../../widgets/auth/pass_result_display.dart';

import 'package:firebase_auth/firebase_auth.dart' show FirebaseAuthException;
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../../theme/app_colors.dart';
import '../../widgets/app_select_field.dart';
import '../../widgets/common/common_widgets.dart';
import '../../utils/dialog_helper.dart';

/// 개선된 회원가입 화면 - 자동 스크롤 + 여백 최적화 + Storage 업로드
class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  static final _pwLengthRe  = RegExp(r'.{8,}');
  static final _pwLetterRe  = RegExp(r'[a-zA-Z]');
  static final _pwDigitRe   = RegExp(r'[0-9]');
  static final _pwSpecialRe = RegExp(r'[!@#$%^&*(),.?":{}|<>]');
  static final _usernameRe  = RegExp(r'^[a-z0-9_]+$');
  static final _korNameRe   = RegExp(r'^[가-힣a-zA-Z\s]+$');
  static final _nonDigitRe  = RegExp(r'\D');

  final StorageService _storageService = StorageService();
  final FirestoreService _firestoreService = FirestoreService();
  final LegalTermsService _legalTermsService = LegalTermsService();
  final PhoneVerificationService _phoneSvc = PhoneVerificationService();

  final TextEditingController _accountNumberController = TextEditingController();
  String? _selectedBank;

  int _currentStep = 0;
  AutovalidateMode _autovalidateMode = AutovalidateMode.disabled;
  
  bool _isSubmitting = false;
  
  // 스크롤 컨트롤러
  final ScrollController _scrollController = ScrollController();
  
  // Step 1: 기본 정보
  final _usernameController = TextEditingController();
  // 아이디 중복 확인 상태 — ValueNotifier로 분리해 타이핑마다 전체 폼 rebuild 방지
  final _usernameStatus = ValueNotifier<_UsernameStatus>(const _UsernameStatus());
  Timer? _usernameDebounce;
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _residentNumber1Controller = TextEditingController();
  final _residentNumber2Controller = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  
  // 전화번호 SMS 인증
  final _phoneCodeController = TextEditingController();
  final _phoneVerifyStatus = ValueNotifier<_PhoneVerifyStatus>(const _PhoneVerifyStatus());
  String _lastSentPhone = ''; // 발송한 번호 추적 (번호 변경 시 재인증)

  // 법적 동의 — Firestore 약관 기반 동적 관리
  LegalTerms? _legalTerms;
  bool _isTermsLoading = false;
  // itemId → 동의 여부 (ValueNotifier로 동의 섹션만 재빌드)
  final _consentNotifier = ValueNotifier<Map<String, bool>>({});
  Map<String, bool> get _consentMap => _consentNotifier.value;
  // 열람 완료된 약관 ID 목록 — 열람 없이 체크 방지
  final _viewedTermIds = <String>{};

  // 주소 정보
  final _addressController = TextEditingController();
  final _detailAddressController = TextEditingController();
  
  // 주민번호 파싱 정보 — ValueNotifier로 분리해 타이핑마다 전체 폼 rebuild 방지
  final _residentResult = ValueNotifier<_ResidentResult>(const _ResidentResult());

  // 내국인/외국인 분기
  bool _isKorean = true;
  PassAuthResult? _passAuthResult;
  bool _isPassLoading = false;

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
    Future.delayed(const Duration(milliseconds: 400), () {
      if (mounted) _nameFocus.requestFocus();
    });
    _loadTerms();
    // 사업자등록번호 입력 시 업로드 카드 활성화 반영
    _businessNumberController.addListener(() { if (mounted) setState(() {}); });
  }

  Future<void> _loadTerms() async {
    setState(() => _isTermsLoading = true);
    try {
      final terms = await _legalTermsService.getTerms();
      if (!mounted) return;
      final map = <String, bool>{};
      for (final item in terms.activeItems) {
        map[item.id] = false;
      }
      _consentNotifier.value = {..._consentNotifier.value, ...map};
      setState(() { _legalTerms = terms; _isTermsLoading = false; });
    } catch (e) {
      debugPrint('⚠️ 약관 로드 실패, 기본값 사용: $e');
      final defaults = LegalTerms.defaultTerms();
      if (!mounted) return;
      final map = <String, bool>{};
      for (final item in defaults.activeItems) {
        map[item.id] = false;
      }
      _consentNotifier.value = {..._consentNotifier.value, ...map};
      setState(() { _legalTerms = defaults; _isTermsLoading = false; });
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _usernameController.dispose();
    _usernameStatus.dispose();
    _residentResult.dispose();
    _consentNotifier.dispose();
    _phoneCodeController.dispose();
    _phoneVerifyStatus.dispose();
    _nameController.dispose();
    _residentNumber1Controller.dispose();
    _residentNumber2Controller.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    _detailAddressController.dispose();
    _accountNumberController.dispose();
    _businessNumberController.dispose();
    _businessNameController.dispose();
    _ceoNameController.dispose();

    _usernameDebounce?.cancel();
    _nameFocus.dispose();
    _usernameFocus.dispose();
    _residentNumber1Focus.dispose();
    _residentNumber2Focus.dispose();
    _phoneFocus.dispose();
    _addressFocus.dispose();
    _detailAddressFocus.dispose();
    _passwordFocus.dispose();
    _confirmPasswordFocus.dispose();
    _businessNameFocus.dispose();
    _ceoNameFocus.dispose();
    _accountNumberFocus.dispose();
    // TMP-MEDIUM: 이미지 선택 후 이탈 시 압축 임시 파일 정리
    for (final path in [_idCardImagePath, _bankbookImagePath, _businessLicenseImagePath]) {
      if (path != null) {
        try { File(path).deleteSync(); } catch (_) {}
      }
    }
    super.dispose();
  }
  // ============================================================
  // 🔧 핵심 함수들
  // ============================================================

/// 주민번호/외국인등록번호로 생년월일과 성별 파싱 — setState 없이 notifier만 업데이트
  void _parseResidentNumber() {
    final rn1 = _residentNumber1Controller.text;
    final rn2 = _residentNumber2Controller.text;

    if (rn1.length != 6 || rn2.isEmpty) {
      _residentResult.value = const _ResidentResult();
      return;
    }

    try {
      int year = int.parse(rn1.substring(0, 2));
      final int month = int.parse(rn1.substring(2, 4));
      final int day = int.parse(rn1.substring(4, 6));
      final int genderCode = int.parse(rn2[0]);

      // 외국인등록번호: 5~8 / 주민등록번호: 1~4
      final isForeign = !_isKorean;
      final minCode = isForeign ? 5 : 1;
      final maxCode = isForeign ? 8 : 4;

      if (genderCode < minCode || genderCode > maxCode) {
        _residentResult.value = _ResidentResult(error: '뒷자리는 $minCode~$maxCode만 가능합니다');
        return;
      }

      // 외국인등록번호는 코드 범위를 -4 이동해 주민번호 로직 재사용
      final effectiveCode = isForeign ? genderCode - 4 : genderCode;

      if (effectiveCode == 1 || effectiveCode == 2) {
        year += 1900;
      } else {
        final currentYear = DateTime.now().year;
        final twoDigitCurrentYear = currentYear % 100;
        if (year > twoDigitCurrentYear) {
          _residentResult.value = _ResidentResult(
            error: '2000년대생은 00~${twoDigitCurrentYear.toString().padLeft(2, '0')}년생만 가능합니다',
          );
          return;
        }
        year += 2000;
      }

      if ((effectiveCode == 3 || effectiveCode == 4) && year < 2000) {
        final expected = isForeign ? '7 또는 8' : '3 또는 4';
        _residentResult.value = _ResidentResult(error: '$year년생은 뒷자리 $expected를 사용해야 합니다');
        return;
      }

      if ((effectiveCode == 1 || effectiveCode == 2) && year >= 2000) {
        final expected = isForeign ? '7 또는 8' : '3 또는 4';
        _residentResult.value = _ResidentResult(error: '$year년생은 뒷자리 $expected를 사용해야 합니다');
        return;
      }

      DateTime birthDate;
      try {
        birthDate = DateTime(year, month, day);
      } catch (_) {
        _residentResult.value = _ResidentResult(error: '존재하지 않는 날짜입니다 ($year년 $month월 $day일)');
        return;
      }

      // 만 19세 이상 검사 (CF verifyPassAuth와 동일 기준)
      final today = DateTime.now();
      int age = today.year - birthDate.year;
      if (today.month < birthDate.month ||
          (today.month == birthDate.month && today.day < birthDate.day)) {
        age--;
      }
      if (age < 19) {
        _residentResult.value = const _ResidentResult(error: '만 19세 이상만 가입 가능합니다');
        return;
      }

      // 뒷자리 첫 자리(성별코드)만 입력받으므로 체크섬 검증 불가 — 서버 측 검증으로 대체 예정

      final gender = (effectiveCode == 1 || effectiveCode == 3) ? '남성' : '여성';
      _residentResult.value = _ResidentResult(birthDate: birthDate, gender: gender);
      debugPrint('✅ ${isForeign ? "외국인등록번호" : "주민번호"} 파싱 성공');
    } catch (_) {
      debugPrint('❌ 번호 파싱 실패');
      _residentResult.value = const _ResidentResult(error: '올바른 번호를 입력해주세요');
    }
  }

  Future<void> _searchAddress() async {
    final result = await DaumAddressService.searchAddress(context);
    
    if (result != null && mounted) {
      setState(() {
        _addressController.text = result.fullAddress;
      });
      
      ToastHelper.showSuccess('주소가 입력되었습니다');
      
      // 상세주소 필드로 포커스 이동
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

    if (_isKorean) {
      // 내국인: PASS 인증 완료 여부 확인
      if (_passAuthResult == null) {
        ToastHelper.showWarning('PASS 본인인증을 완료해주세요');
        return false;
      }
    } else {
      // 외국인: 외국인등록번호 검증
      _parseResidentNumber();
      final rr = _residentResult.value;
      if (rr.birthDate == null || rr.gender == null) {
        ToastHelper.showWarning('올바른 외국인등록번호를 입력해주세요');
        return false;
      }

      // 전화번호 SMS 인증 확인
      if (!_phoneVerifyStatus.value.isVerified) {
        ToastHelper.showWarning('휴대폰 번호 인증을 완료해주세요');
        return false;
      }
    }

    // 필수 동의 항목 체크
    final requiredItems = _legalTerms?.activeItems
        .where((t) => t.isRequired)
        .toList() ?? [];
    final allRequiredAgreed = requiredItems.every(
        (t) => _consentMap[t.id] == true);
    if (!allRequiredAgreed) {
      ToastHelper.showWarning('필수 약관에 모두 동의해주세요');
      return false;
    }

    return true;
  }

  bool _validateStep2() {
    if (_selectedRole == null) {
      ToastHelper.showWarning('이용 방법을 선택해주세요');
      return false;
    }
    return true;
  }

  bool _isStepTransitioning = false; // 더블탭 Step 건너뜀 방지

  Future<void> _onStepContinue() async {
    if (_isStepTransitioning) return;
    setState(() => _isStepTransitioning = true);

    try {
      // 단계 내부 번호(_currentStep)와 UI 표시 레이블이 다름:
      //   Step 0 → 화면: "이용 방법 선택" (_buildStep2RoleSelection)
      //   Step 1 → 화면: "기본 정보 입력"  (_buildStep1BasicInfo)
      //   Step 2 → 화면: "추가 정보"       (_buildStep3 Documents)
      // 역할 선택을 맨 앞에 배치해 맞춤형 폼 안내가 가능하도록 순서를 의도적으로 역전함.
      if (_currentStep == 0) {
        if (_validateStep2()) {
          setState(() => _currentStep = 1);
          _scrollToTop();
        }
      } else if (_currentStep == 1) {
        if (_validateStep1()) {
          setState(() => _currentStep = 2);
          _scrollToTop();
        } else {
          setState(() {
            _autovalidateMode = AutovalidateMode.onUserInteraction;
          });
        }
      } else if (_currentStep == 2) {
        // await로 호출해 _handleRoleSelection이 완료될 때까지 _isStepTransitioning을 유지.
        // 이로써 300ms 지연 없이도 처리 완료 전 재진입이 차단된다.
        await _handleRoleSelection();
      }
    } finally {
      await Future.delayed(const Duration(milliseconds: 300));
      if (mounted) setState(() => _isStepTransitioning = false);
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
    if (_selectedRole == null) return;
    if (_isSubmitting) return; // _isStepTransitioning 해제(300ms) 후 연타 방지

    // Step 3 사업장 관리자: 입력한 경우에만 형식 검사 (선택사항)
    // [DESIGN] 동일 사업자등록번호로 복수 관리자 계정 허용 — 중복 체크 미수행 의도적 설계.
    //          예: 같은 사업장에 대표와 부관리자가 각자 BUSINESS_ADMIN으로 가입 가능.
    if (_selectedRole == UserRole.BUSINESS_ADMIN) {
      final bizNum = _businessNumberController.text.replaceAll('-', '');
      if (bizNum.isNotEmpty) {
        if (bizNum.length != 10) {
          ToastHelper.showWarning('사업자등록번호 10자리를 확인해주세요');
          return;
        }
        if (!_isValidBusinessNumber(bizNum)) {
          ToastHelper.showWarning('유효하지 않은 사업자등록번호입니다. 다시 확인해주세요.');
          return;
        }
      }
    }

    if (_selectedRole == UserRole.USER) {
      final missingDocs = <String>[];
      if (_idCardImagePath == null) missingDocs.add('신분증');
      if (_bankbookImagePath == null) missingDocs.add('통장사본');

      if (missingDocs.isNotEmpty) {
        final confirmed = await DialogHelper.showConfirm(
          context,
          title: '서류 미등록',
          message: '${missingDocs.join(', ')} 미등록 시 단기 공고 지원이 불가합니다.\n설정 > 내 서류 관리에서 나중에 등록할 수 있어요.',
          confirmText: '나중에 등록',
          cancelText: '돌아가기',
          confirmColor: AppColors.warningDark,
          icon: Icons.warning_amber_outlined,
          iconColor: AppColors.warningDark,
        );
        if (!mounted) return;
        if (!confirmed) return;
      }
      await _registerUser();
    } else if (_selectedRole == UserRole.BUSINESS_ADMIN) {
      await _showBusinessRegistrationDialog();
    }
  }
  // ============================================================
  // 📝 회원가입 로직 (Storage 업로드 포함)
  // ============================================================

  // 사업장 등록 선택 다이얼로그
  Future<void> _showBusinessRegistrationDialog() async {
    // 사업자등록증 미등록 시 경고
    if (_businessLicenseImagePath == null) {
      if (!mounted) return;
      final proceed = await DialogHelper.showConfirm(
        context,
        title: '사업자등록증 미등록',
        message: '미등록 시 사업장 등록이 불가합니다.\n설정 > 내 서류 관리에서 나중에 등록할 수 있어요.',
        confirmText: '나중에 등록',
        cancelText: '돌아가기',
        confirmColor: AppColors.warningDark,
        icon: Icons.warning_amber_outlined,
        iconColor: AppColors.warningDark,
      );
      if (!mounted) return;
      if (proceed) await _registerUser();
      return;
    }

    // 사업자등록증 등록 완료 — 사업장 등록 여부 선택
    if (!mounted) return;
    final registerNow = await DialogHelper.showConfirm(
      context,
      title: '사업장 등록',
      message: '사업장 정보를 지금 등록하시겠습니까?\n\n지금 등록하면 TO를 바로 생성하고 지원자를 관리할 수 있습니다.',
      confirmText: '지금 등록',
      cancelText: '나중에',
      icon: Icons.business_outlined,
      iconColor: Theme.of(context).primaryColor,
    );
    if (!mounted) return;
    if (registerNow) {
      _registerUserAndGoToBusinessRegistration();
    } else {
      await _registerUser();
    }
  }

  /// 회원가입: 계정 먼저 생성 → UID로 올바른 경로에 업로드 (temp 고아 파일 방지)
  Future<void> _registerUser() async {
    if (_isSubmitting) return;
    setState(() => _isSubmitting = true);

    final userProvider = context.read<UserProvider>();

    try {
      final rr = _residentResult.value;

      // 외국인: 등록번호 중복 체크 (내국인은 CF verifyPassAuth의 ciHash+role 중복 체크로 대체)
      if (!_isKorean) {
        final foreignId = '${_residentNumber1Controller.text}-X${_residentNumber2Controller.text}*****';
        final exists = await AuthService().checkForeignIdExists(foreignId, _selectedRole!);
        if (!mounted) return;
        if (exists) {
          ToastHelper.showError('이미 동일 역할로 가입된 외국인등록번호입니다.');
          setState(() => _isSubmitting = false);
          return;
        }
      }

      // Step 1: 이미지 URL 없이 계정 생성 → UID 확보
      final success = await userProvider.signUp(
        username: _usernameController.text.trim(),
        password: _passwordController.text,
        name: _isKorean ? _passAuthResult!.name : _nameController.text.trim(),
        phone: _isKorean ? _passAuthResult!.phone : _phoneController.text.trim(),
        role: _selectedRole!,
        gender: _isKorean ? _passAuthResult!.gender : rr.gender,
        birthDate: _isKorean ? _passAuthResult!.birthDate : rr.birthDate,
        // 내국인: 주민번호 직접 저장 안 함.
        // [TODO-DANAL] 다날 계약 후 verifyPassAuth CF에서 받은 passToken을 경유해
        //   users/{uid}.ciHash 저장 필요. ciHash가 없으면 비밀번호 찾기 CI 매칭 실패.
        residentNumber: _isKorean ? null : '${_residentNumber1Controller.text}-X******',
        foreignIdNumber: _isKorean ? null : '${_residentNumber1Controller.text}-X${_residentNumber2Controller.text}*****',
        // 내국인: PASS 인증 완료이므로 즉시 active. 외국인: 슈퍼관리자 승인 전까지 pending.
        accountStatus: _isKorean ? 'active' : 'pending',
        address: _addressController.text.trim(),
        detailAddress: _detailAddressController.text.trim(),
        bankName: _selectedBank,
        accountNumber: _accountNumberController.text.trim().isEmpty
            ? null : _accountNumberController.text.trim(),
        businessNumber: _selectedRole == UserRole.BUSINESS_ADMIN &&
            _businessNumberController.text.replaceAll('-', '').isNotEmpty
            ? _businessNumberController.text.replaceAll('-', '') : null,
        businessName: _selectedRole == UserRole.BUSINESS_ADMIN &&
            _businessNameController.text.trim().isNotEmpty
            ? _businessNameController.text.trim() : null,
        ceoName: _selectedRole == UserRole.BUSINESS_ADMIN &&
            _ceoNameController.text.trim().isNotEmpty
            ? _ceoNameController.text.trim() : null,
      );

      if (!success) {
        if (mounted) {
          final err = userProvider.error;
          ToastHelper.showError((err != null && err.isNotEmpty) ? err : '회원가입에 실패했습니다.');
        }
        return;
      }
      if (!mounted) return;

      // Step 2: 동의 일시·버전 CF로 저장 (법적 타임스탬프 서버 발급)
      final uid = userProvider.currentUser?.uid;
      if (uid != null && _legalTerms != null) {
        final consentRecord = <String, dynamic>{};
        for (final item in _legalTerms!.activeItems) {
          // [D1] agreedAt/termsConsentAt은 서버에서 설정 — 클라이언트는 agreed+version만 전달
          consentRecord[item.id] = {
            'agreed': _consentMap[item.id] ?? false,
            'version': item.version,
          };
        }
        try {
          await FirebaseFunctions.instanceFor(region: 'asia-northeast3')
              .httpsCallable('callableRecordTermsConsent',
                  options: HttpsCallableOptions(timeout: const Duration(seconds: 10)))
              .call({'consentRecord': consentRecord});
        } catch (_) {
          // 동의 기록 저장 실패는 가입을 막지 않음 (best-effort)
          debugPrint('⚠️ 동의 기록 저장 실패');
        }
      }

      if (!mounted) return;

      // Step 3: UID 확보 후 올바른 경로에 파일 업로드 (병렬)
      if (uid == null) {
        debugPrint('⚠️ uid null — 업로드 스킵');
      }
      if (uid != null && !kIsWeb) {
        final uploads = <String, Future<String?>>{};
        if (_idCardImagePath != null) {
          uploads['idCardImageUrl'] = _storageService.uploadImage(
              _idCardImagePath!, 'users/$uid/idCard_${DateTime.now().millisecondsSinceEpoch}.jpg');
        }
        if (_bankbookImagePath != null) {
          uploads['bankbookImageUrl'] = _storageService.uploadImage(
              _bankbookImagePath!, 'users/$uid/bankbook_${DateTime.now().millisecondsSinceEpoch}.jpg');
        }
        if (_businessLicenseImagePath != null && _selectedRole == UserRole.BUSINESS_ADMIN) {
          uploads['businessLicenseImageUrl'] = _storageService.uploadImage(
              _businessLicenseImagePath!, 'users/$uid/businessLicense_${DateTime.now().millisecondsSinceEpoch}.jpg');
        }

        if (uploads.isNotEmpty) {
          ToastHelper.showInfo('서류 업로드 중...');
          final uploadRefs = uploads.keys.toList();
          final results = await Future.wait(uploads.values);
          final updates = <String, dynamic>{};
          final uploadedUrls = <String>[];
          for (int i = 0; i < uploadRefs.length; i++) {
            if (results[i] != null) {
              updates[uploadRefs[i]] = results[i];
              uploadedUrls.add(results[i]!);
            }
          }
          // TMP-01: 업로드된 임시 압축 파일 삭제 (성공/실패 무관)
          for (final path in [_idCardImagePath, _bankbookImagePath, _businessLicenseImagePath]) {
            if (path != null) {
              try {
                final f = File(path);
                if (await f.exists()) await f.delete();
              // 임시파일 삭제 실패 무시 — OS가 앱 종료 시 정리함, 기능에 영향 없음
              } catch (_) {}
            }
          }
          if (updates.isNotEmpty && mounted) {
            try {
              await _firestoreService.updateUserDocument(uid, updates);
              // onAuthStateChanged가 Auth 계정 생성 시점에 발화 → 서류 URL 없는 상태로 캐싱됨
              // updateUserDocument 완료 후 Provider를 갱신해야 내 서류 관리에서 재업로드 요구 안 함
              if (mounted) {
                try { await context.read<UserProvider>().refreshCurrentUser(); } catch (_) {}
              }
            } catch (_) {
              // Firestore 업데이트 실패 시 Storage 업로드 파일 정리 (orphan 방지)
              for (final url in uploadedUrls) {
                try { await _storageService.deleteImageByUrl(url); } catch (_) {}
              }
              if (mounted) ToastHelper.showWarning('서류 업로드에 실패했습니다. 설정 > 내 서류 관리에서 다시 시도해주세요.');
            }
          }
        }
      }

      if (!mounted) return;

      // [AUTH-H3] 가입 완료 후 passToken 즉시 소비 (15분 재사용 차단)
      // 별도 try-catch: 이 단계 실패는 계정 생성 자체와 무관.
      // 실패해도 계정은 정상 생성됐으므로 재가입 루프를 유발하는 오탐 방지.
      if (_isKorean && _passAuthResult != null) {
        try {
          await PassVerificationService.finalizeRegistration(_passAuthResult!.passToken);
        } catch (e) {
          debugPrint('⚠️ finalizeRegistration 실패 (ciHash 미연동): $e');
          // ciHash 연동 실패 — 계정 자체는 생성 완료, 슈퍼관리자 수동 처리 필요
        }
      }

      if (!mounted) return;

      AnalyticsService.logSignUp(_selectedRole?.name ?? 'USER');
      ToastHelper.showSuccess('가입을 환영합니다!');
      Navigator.of(context).popUntil((route) => route.isFirst);
    } catch (e) {
      debugPrint('❌ 회원가입 실패: $e');
      final errStr = e.toString();
      if (_isKorean &&
          (errStr.contains('deadline-exceeded') ||
              errStr.contains('token-expired') ||
              errStr.contains('passToken'))) {
        if (mounted) setState(() => _passAuthResult = null);
        if (mounted) ToastHelper.showError('PASS 인증 세션이 만료되었습니다.\n화면 상단의 PASS 인증을 다시 진행해주세요.');
      } else {
        if (mounted) ToastHelper.showError('회원가입에 실패했습니다');
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
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
    
    if (!_pwLetterRe.hasMatch(value)) {
      return '영문을 포함해야 합니다';
    }

    if (!_pwDigitRe.hasMatch(value)) {
      return '숫자를 포함해야 합니다';
    }

    if (!_pwSpecialRe.hasMatch(value)) {
      return '특수문자를 포함해야 합니다';
    }
    
    return null;
  }

  /// 사업장 관리자 회원가입: 계정 먼저 생성 → UID로 올바른 경로에 업로드
  Future<void> _registerUserAndGoToBusinessRegistration() async {
    if (_isSubmitting) return;
    setState(() => _isSubmitting = true);

    final userProvider = context.read<UserProvider>();

    try {
      final rr = _residentResult.value;

      // 외국인: 등록번호 중복 체크 (내국인은 CF verifyPassAuth의 ciHash+role 중복 체크로 대체)
      if (!_isKorean) {
        final foreignId = '${_residentNumber1Controller.text}-X${_residentNumber2Controller.text}*****';
        final exists = await AuthService().checkForeignIdExists(foreignId, UserRole.BUSINESS_ADMIN);
        if (!mounted) return;
        if (exists) {
          ToastHelper.showError('이미 동일 역할로 가입된 외국인등록번호입니다.');
          setState(() => _isSubmitting = false);
          return;
        }
      }

      // Step 1: 이미지 URL 없이 계정 생성 → UID 확보
      final success = await userProvider.signUp(
        username: _usernameController.text.trim(),
        password: _passwordController.text,
        name: _isKorean ? _passAuthResult!.name : _nameController.text.trim(),
        phone: _isKorean ? _passAuthResult!.phone : _phoneController.text.trim(),
        role: UserRole.BUSINESS_ADMIN,
        gender: _isKorean ? _passAuthResult!.gender : rr.gender,
        birthDate: _isKorean ? _passAuthResult!.birthDate : rr.birthDate,
        // [TODO-DANAL] _registerUser()와 동일한 ciHash 미저장 이슈 — PASS 계약 후 함께 처리
        residentNumber: _isKorean ? null : '${_residentNumber1Controller.text}-X******',
        foreignIdNumber: _isKorean ? null : '${_residentNumber1Controller.text}-X${_residentNumber2Controller.text}*****',
        accountStatus: _isKorean ? 'active' : 'pending',
        address: _addressController.text.trim(),
        detailAddress: _detailAddressController.text.trim(),
        bankName: _selectedBank,
        accountNumber: _accountNumberController.text.trim().isEmpty
            ? null : _accountNumberController.text.trim(),
        businessNumber: _businessNumberController.text.replaceAll('-', '').isNotEmpty
            ? _businessNumberController.text.replaceAll('-', '') : null,
        businessName: _businessNameController.text.trim().isNotEmpty
            ? _businessNameController.text.trim() : null,
        ceoName: _ceoNameController.text.trim().isNotEmpty
            ? _ceoNameController.text.trim() : null,
      );

      if (!success) {
        if (mounted) {
          final err = userProvider.error;
          ToastHelper.showError((err != null && err.isNotEmpty) ? err : '회원가입에 실패했습니다.');
        }
        return;
      }
      if (!mounted) return;

      // Step 2: 동의 일시·버전 CF로 저장 (법적 타임스탬프 서버 발급)
      final uid = userProvider.currentUser?.uid;
      if (uid != null && _legalTerms != null) {
        final consentRecord = <String, dynamic>{};
        for (final item in _legalTerms!.activeItems) {
          // [D1] agreedAt/termsConsentAt은 서버에서 설정 — 클라이언트는 agreed+version만 전달
          consentRecord[item.id] = {
            'agreed': _consentMap[item.id] ?? false,
            'version': item.version,
          };
        }
        try {
          await FirebaseFunctions.instanceFor(region: 'asia-northeast3')
              .httpsCallable('callableRecordTermsConsent',
                  options: HttpsCallableOptions(timeout: const Duration(seconds: 10)))
              .call({'consentRecord': consentRecord});
        } catch (_) {
          // 동의 기록 저장 실패는 가입을 막지 않음 (best-effort)
          debugPrint('⚠️ 동의 기록 저장 실패');
        }
      }

      if (!mounted) return;

      // Step 3: UID로 올바른 경로에 업로드 (병렬)
      if (uid != null && !kIsWeb) {
        final uploads = <String, Future<String?>>{};
        if (_idCardImagePath != null) {
          uploads['idCardImageUrl'] = _storageService.uploadImage(
              _idCardImagePath!, 'users/$uid/idCard_${DateTime.now().millisecondsSinceEpoch}.jpg');
        }
        if (_bankbookImagePath != null) {
          uploads['bankbookImageUrl'] = _storageService.uploadImage(
              _bankbookImagePath!, 'users/$uid/bankbook_${DateTime.now().millisecondsSinceEpoch}.jpg');
        }
        if (_businessLicenseImagePath != null) {
          uploads['businessLicenseImageUrl'] = _storageService.uploadImage(
              _businessLicenseImagePath!,
              'users/$uid/businessLicense_${DateTime.now().millisecondsSinceEpoch}.jpg');
        }

        if (uploads.isNotEmpty) {
          ToastHelper.showInfo('서류 업로드 중...');
          final uploadRefs2 = uploads.keys.toList();
          final results = await Future.wait(uploads.values);
          final fileUpdates = <String, dynamic>{};
          final uploadedUrls2 = <String>[];
          for (int i = 0; i < uploadRefs2.length; i++) {
            if (results[i] != null) {
              fileUpdates[uploadRefs2[i]] = results[i];
              uploadedUrls2.add(results[i]!);
            }
          }
          // TMP-01: 업로드된 임시 압축 파일 삭제 (성공/실패 무관)
          for (final path in [_idCardImagePath, _bankbookImagePath, _businessLicenseImagePath]) {
            if (path != null) {
              try {
                final f = File(path);
                if (await f.exists()) await f.delete();
              // 임시파일 삭제 실패 무시 — OS가 앱 종료 시 정리함, 기능에 영향 없음
              } catch (_) {}
            }
          }
          if (fileUpdates.isNotEmpty && mounted) {
            try {
              await _firestoreService.updateUserDocument(uid, fileUpdates);
              // onAuthStateChanged가 Auth 계정 생성 시점에 발화 → 서류 URL 없는 상태로 캐싱됨
              // updateUserDocument 완료 후 Provider를 갱신해야 내 서류 관리에서 재업로드 요구 안 함
              if (mounted) {
                try { await context.read<UserProvider>().refreshCurrentUser(); } catch (_) {}
              }
            } catch (_) {
              for (final url in uploadedUrls2) {
                try { await _storageService.deleteImageByUrl(url); } catch (_) {}
              }
              if (mounted) ToastHelper.showWarning('서류 업로드에 실패했습니다. 설정 > 내 서류 관리에서 다시 시도해주세요.');
            }
          }
        }
      }

      if (!mounted) return;

      // [AUTH-H3] 가입 완료 후 passToken 즉시 소비 (15분 재사용 차단)
      // 별도 try-catch: 이 단계 실패는 계정 생성 자체와 무관.
      if (_isKorean && _passAuthResult != null) {
        try {
          await PassVerificationService.finalizeRegistration(_passAuthResult!.passToken);
        } catch (e) {
          debugPrint('⚠️ finalizeRegistration 실패 (ciHash 미연동): $e');
        }
      }

      if (!mounted) return;

      AnalyticsService.logSignUp('BUSINESS_ADMIN');
      ToastHelper.showSuccess('가입을 환영합니다!');
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => const BusinessFormScreen(isFromSignUp: true),
        ),
      );
    } catch (e) {
      debugPrint('❌ 회원가입 실패: $e');
      if (mounted) ToastHelper.showError('회원가입에 실패했습니다');
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _checkUsername() async {
    final username = _usernameController.text.trim();
    if (username.length < 4) {
      _usernameStatus.value = const _UsernameStatus(error: '4자 이상 입력하세요');
      return;
    }
    _usernameStatus.value = const _UsernameStatus(isChecking: true, hasText: true);
    final authService = AuthService();
    final exists = await authService.checkUsernameExists(username);
    if (!mounted) return;
    _usernameStatus.value = _UsernameStatus(
      hasText: true,
      isAvailable: !exists,
      error: exists ? '이미 사용중인 아이디입니다' : null,
    );
  }
  // ── SMS 인증 ────────────────────────────────────────────────────

  Future<void> _sendPhoneCode() async {
    if (_phoneVerifyStatus.value.isSending) return; // 이중 탭 방지 — SMS 이중 발송 차단
    final phone = _phoneController.text.trim();
    _phoneVerifyStatus.value = const _PhoneVerifyStatus(isSending: true);
    try {
      await _phoneSvc.sendCode(phone);
      if (!mounted) return;
      _lastSentPhone = phone;
      _phoneCodeController.clear();
      _phoneVerifyStatus.value = const _PhoneVerifyStatus(isSent: true);
      ToastHelper.showSuccess('인증번호가 발송되었습니다');
    } on FirebaseAuthException catch (e) {
      final String msg = switch (e.code) {
        'too-many-requests'    => '잠시 후 다시 시도해주세요',
        'invalid-phone-number' => '올바른 휴대폰 번호를 입력해주세요',
        'quota-exceeded'       => '인증번호 발송 횟수를 초과했습니다. 잠시 후 다시 시도해주세요',
        _                      => '발송에 실패했습니다. 다시 시도해주세요',
      };
      if (!mounted) return; // dispose 후 ValueNotifier 접근 방지
      _phoneVerifyStatus.value = _PhoneVerifyStatus(error: msg);
      ToastHelper.showError(msg);
    } on Exception {
      if (!mounted) return;
      _phoneVerifyStatus.value = const _PhoneVerifyStatus(error: '발송에 실패했습니다. 다시 시도해주세요');
      ToastHelper.showError('발송에 실패했습니다. 다시 시도해주세요');
    }
  }

  Future<void> _verifyPhoneCode() async {
    final code = _phoneCodeController.text.trim();
    if (code.length != 6) return;
    if (_phoneVerifyStatus.value.isVerifying) return; // 이중 탭 방지
    _phoneVerifyStatus.value = const _PhoneVerifyStatus(
        isSent: true, isVerifying: true);
    try {
      final result = await _phoneSvc.verifyCode(_phoneController.text.trim(), code);
      if (result.valid) {
        // 역할이 이미 선택된 상태이므로 role+phone 중복 가입 체크
        if (_selectedRole != null) {
          final isDuplicate = await AuthService().checkDuplicateRegistration(
            phone: _phoneController.text.trim(),
            role: _selectedRole!,
          );
          if (!mounted) return;
          if (isDuplicate == null) {
            // 중복 체크 CF 오류 — null 폴스루로 중복 계정 통과 방지
            _phoneVerifyStatus.value = const _PhoneVerifyStatus(isSent: true);
            ToastHelper.showWarning('중복 확인 중 오류가 발생했습니다. 잠시 후 다시 시도해주세요.');
            return;
          }
          if (isDuplicate == true) {
            final roleLabel = _selectedRole == UserRole.USER ? '지원자' : '사업장 관리자';
            _phoneVerifyStatus.value = _PhoneVerifyStatus(
              isSent: true,
              error: '$roleLabel 계정에 이미 등록된 번호입니다. 로그인해주세요.',
            );
            ToastHelper.showError('$roleLabel 계정에 이미 등록된 번호입니다.');
            return;
          }
        }
        if (!mounted) return;
        _phoneVerifyStatus.value = const _PhoneVerifyStatus(isVerified: true);
        ToastHelper.showSuccess('휴대폰 인증이 완료되었습니다');
      } else {
        final msg = switch (result.reason) {
          'expired'           => '인증번호가 만료됐습니다. 재발송해주세요',
          'too_many_attempts' => '시도 횟수를 초과했습니다. 재발송해주세요',
          _                   => '인증번호가 일치하지 않습니다',
        };
        if (!mounted) return; // dispose 후 ValueNotifier 접근 방지
        _phoneVerifyStatus.value = _PhoneVerifyStatus(isSent: true, error: msg);
        ToastHelper.showError(msg);
      }
    } on Exception {
      if (!mounted) return;
      _phoneVerifyStatus.value = const _PhoneVerifyStatus(
          isSent: true, error: '확인에 실패했습니다');
    }
  }

  // ── SMS 인증 UI 헬퍼 ────────────────────────────────────────────

  Widget _buildPhoneVerifiedBadge(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(top: ResponsiveHelper.spacing(context, 8)),
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: ResponsiveHelper.spacing(context, 14),
          vertical: ResponsiveHelper.spacing(context, 10),
        ),
        decoration: BoxDecoration(
          color: AppColors.successBg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.successLight),
        ),
        child: Row(children: [
          Icon(Icons.check_circle,
              color: AppColors.successDark,
              size: ResponsiveHelper.iconSize(context, 18)),
          SizedBox(width: ResponsiveHelper.spacing(context, 8)),
          Text('휴대폰 인증 완료',
              style: ResponsiveHelper.smallStyle(context,
                  color: AppColors.successDark, fontWeight: FontWeight.w600)),
          const Spacer(),
          TextButton(
            onPressed: () =>
                _phoneVerifyStatus.value = const _PhoneVerifyStatus(),
            style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap),
            child: Text('재인증',
                style: ResponsiveHelper.tinyStyle(context,
                    color: AppColors.grey400)),
          ),
        ]),
      ),
    );
  }

  Widget _buildPhoneCodeInput(
      BuildContext context, ThemeData theme, _PhoneVerifyStatus status) {
    return Padding(
      padding: EdgeInsets.only(top: ResponsiveHelper.spacing(context, 10)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: TextField(
              controller: _phoneCodeController,
              keyboardType: TextInputType.number,
              maxLength: 6,
              autofocus: true,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              onChanged: (v) {
                if (v.length == 6 && !status.isVerifying) _verifyPhoneCode();
              },
              style: ResponsiveHelper.bodyStyle(context),
              decoration: InputDecoration(
                hintText: '인증번호 6자리',
                hintStyle: ResponsiveHelper.smallStyle(context,
                    color: AppColors.grey400),
                counterText: '',
                isDense: true,
                contentPadding: EdgeInsets.symmetric(
                    horizontal: ResponsiveHelper.spacing(context, 12),
                    vertical: ResponsiveHelper.spacing(context, 12)),
                filled: true,
                fillColor: AppColors.grey50,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: AppColors.grey300)),
                enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: AppColors.grey300)),
                focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide:
                        BorderSide(color: theme.primaryColor, width: 1.5)),
              ),
            ),
          ),
          SizedBox(width: ResponsiveHelper.spacing(context, 8)),
          ElevatedButton(
            onPressed: status.isVerifying ? null : _verifyPhoneCode,
            style: ElevatedButton.styleFrom(
              backgroundColor: theme.primaryColor,
              elevation: 0,
              padding: EdgeInsets.symmetric(
                  horizontal: ResponsiveHelper.spacing(context, 16),
                  vertical: ResponsiveHelper.spacing(context, 13)),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            child: status.isVerifying
                ? const SizedBox(
                    width: 18, height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : Text('확인',
                    style: ResponsiveHelper.bodyStyle(context,
                        color: Colors.white)),
          ),
        ]),
        if (status.error != null) ...[
          SizedBox(height: ResponsiveHelper.spacing(context, 6)),
          Text(status.error!,
              style: ResponsiveHelper.tinyStyle(context,
                  color: AppColors.error)),
        ],
        SizedBox(height: ResponsiveHelper.spacing(context, 4)),
        TextButton(
          onPressed: status.isSending ? null : _sendPhoneCode,
          style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap),
          child: Text('인증번호 재발송',
              style: ResponsiveHelper.tinyStyle(context,
                  color: theme.primaryColor)),
        ),
      ]),
    );
  }

  /// PortOne(포트원) PASS 본인인증 실행
  ///
  /// 흐름:
  ///   PassVerificationService.authenticate()
  ///     → iamport_flutter WebView (KG이니시스 통합인증 V1)
  ///     → 사용자 PASS 인증 완료
  ///     → CF verifyPassAuth(imp_uid) 호출
  ///     → PassAuthResult { name, gender, birthDate, phone, passToken } 반환
  ///
  /// passToken 은 15분 유효. 가입 제출 시 CF finalizeRegistration() 에 전달하여
  /// ciHash 를 Firestore 에 저장하고 토큰을 소진한다.
  ///
  Future<void> _handlePassAuth() async {
    if (_isPassLoading) return;
    setState(() => _isPassLoading = true);
    try {
      final result = await PassVerificationService.authenticate(
        purpose: 'register',
        role: _selectedRole?.name ?? 'USER',
      );
      if (!mounted) return;
      if (result != null) {
        setState(() {
          _passAuthResult = result;
          _nameController.text = result.name;
          _phoneController.text = result.phone;
        });
      }
    } catch (e) {
      if (!mounted) return;
      ToastHelper.showError('본인인증에 실패했습니다. 다시 시도해주세요.');
    } finally {
      if (mounted) setState(() => _isPassLoading = false);
    }
  }

  // ============================================================
  // 🎨 Build 메서드 + 이미지 업로드
  // ============================================================

  @override
  Widget build(BuildContext context) {
    // select로 isLoading만 구독 — UserProvider의 다른 변경 시 전체 폼 rebuild 방지
    final isProviderLoading = context.select<UserProvider, bool>((p) => p.isLoading);
    return PopScope(
      // 제출 중이거나 중간 단계면 pop 차단 — onPopInvokedWithResult에서 처리
      canPop: !_isSubmitting && _currentStep == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_isSubmitting) {
          ToastHelper.showWarning('처리 중입니다. 잠시만 기다려주세요.');
          return;
        }
        // 시스템 뒤로가기를 단계 이전으로 처리 (_currentStep > 0 보장)
        _onStepCancel();
      },
      child: Scaffold(
        resizeToAvoidBottomInset: true,
        body: LoadingOverlay(
            isLoading: isProviderLoading || _isSubmitting,
            message: _isSubmitting ? '서류 업로드 중...' : '회원가입 중...',
            child: Container(
              width: double.infinity,
              height: double.infinity,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Theme.of(context).primaryColor,
                    Theme.of(context).colorScheme.secondary,
                  ],
                ),
              ),
              child: SafeArea(
                bottom: false,
                child: Column(
                  children: [
                    _buildHeader(),
                    Expanded(
                      child: Container(
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.vertical(
                            top: Radius.circular(32),
                          ),
                        ),
                        child: SingleChildScrollView(
                          controller: _scrollController,
                          keyboardDismissBehavior:
                              ScrollViewKeyboardDismissBehavior.onDrag,
                          padding: EdgeInsets.fromLTRB(
                            ResponsiveHelper.spacing(context, 20),
                            ResponsiveHelper.spacing(context, 24),
                            ResponsiveHelper.spacing(context, 20),
                            0,
                          ),
                          child: Column(
                            children: [
                              _buildCurrentStep(),
                              _buildBottomButton(),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),  // Scaffold
    );      // PopScope
  }


  /// 사업자등록증 이미지 선택
  Future<void> _pickBusinessLicenseImage() async {
    final bizNum = _businessNumberController.text.replaceAll('-', '');
    if (bizNum.length != 10) {
      ToastHelper.showWarning('사업자등록번호를 먼저 입력해주세요');
      return;
    }
    final imagePath = await DocumentUploadHelper.pickAndVerifyBusinessLicense(
      context,
      businessNumber: _businessNumberController.text.trim(),
      ceoName: _ceoNameController.text.trim().isEmpty
          ? null
          : _ceoNameController.text.trim(),
    );
    if (imagePath != null && mounted) {
      setState(() => _businessLicenseImagePath = imagePath);
    }
  }

  /// 신분증 이미지 선택
  Future<void> _pickIdCardImage() async {
    // 여권은 OCR 번호 비교 없이 이미지만 업로드
    String? residentNumber;
    if (!_isKorean &&
        _residentNumber1Controller.text.isNotEmpty &&
        _residentNumber2Controller.text.isNotEmpty) {
      residentNumber = '${_residentNumber1Controller.text}-${_residentNumber2Controller.text[0]}';
    }

    final imagePath = await DocumentUploadHelper.pickAndVerifyIdCard(
      context,
      _nameController.text.trim(),
      expectedResidentNumber: residentNumber,
    );
    
    if (imagePath != null && mounted) {
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

    if (imagePath != null && mounted) {
      setState(() => _bankbookImagePath = imagePath);
    }
  }
  // ============================================================
  // 🔧 헤더, 진행바, 단계 컨텐츠
  // ============================================================

  /// 헤더 (블루 배경 + 진행바 통합)
  Widget _buildHeader() {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        ResponsiveHelper.spacing(context, 20),
        ResponsiveHelper.spacing(context, 8),
        ResponsiveHelper.spacing(context, 20),
        ResponsiveHelper.spacing(context, 14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 뒤로가기 버튼
          GestureDetector(
            onTap: _onStepCancel,
            child: Container(
              padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 6)),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                Icons.arrow_back,
                color: Colors.white,
                size: ResponsiveHelper.iconSize(context, 20),
              ),
            ),
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 10)),
          // 타이틀
          Text(
            '회원가입',
            style: ResponsiveHelper.titleStyle(context).copyWith(
              fontWeight: FontWeight.w800,
              color: Colors.white,
              letterSpacing: 0.5,
            ),
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 2)),
          Text(
            _currentStep == 0
                ? '이용 방법 선택'
                : _currentStep == 1
                    ? '기본 정보 입력'
                    : '추가 정보 (선택)',
            style: ResponsiveHelper.bodyStyle(context).copyWith(
              color: Colors.white.withValues(alpha: 0.75),
            ),
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 12)),
          // 진행 표시기
          Row(
            children: [
              _buildProgressSegment(true),
              SizedBox(width: ResponsiveHelper.spacing(context, 6)),
              _buildProgressSegment(_currentStep >= 1),
              SizedBox(width: ResponsiveHelper.spacing(context, 6)),
              _buildProgressSegment(_currentStep >= 2),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildProgressSegment(bool active) {
    return Expanded(
      child: Container(
        height: 3,
        decoration: BoxDecoration(
          color: active
              ? Colors.white
              : Colors.white.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }

  /// 현재 단계 컨텐츠
  Widget _buildCurrentStep() {
    switch (_currentStep) {
      case 0:
        return _buildStep2RoleSelection();
      case 1:
        return _buildStep1BasicInfo();
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

  Widget _buildSectionLabel(String title, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Row(children: [
        Icon(icon, size: 13, color: AppColors.grey500),
        const SizedBox(width: 5),
        Text(title, style: ResponsiveHelper.smallStyle(context, color: AppColors.grey500, fontWeight: FontWeight.w600)),
      ]),
    );
  }

  Widget _buildNationalityToggle() {
    return Row(
      children: [
        for (final entry in const [
          (true, '내국인', Icons.person),
          (false, '외국인', Icons.public),
        ])
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(right: 6),
              child: GestureDetector(
                onTap: () => setState(() {
                  _isKorean = entry.$1;
                  _passAuthResult = null;
                  _nameController.clear();
                  _residentResult.value = const _ResidentResult();
                  _residentNumber1Controller.clear();
                  _residentNumber2Controller.clear();
                  _phoneController.clear();
                  _phoneVerifyStatus.value = const _PhoneVerifyStatus();
                }),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: _isKorean == entry.$1
                        ? Theme.of(context).primaryColor
                        : AppColors.grey100,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: _isKorean == entry.$1
                          ? Theme.of(context).primaryColor
                          : AppColors.grey300,
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        entry.$3,
                        size: 16,
                        color: _isKorean == entry.$1
                            ? Colors.white
                            : AppColors.grey500,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        entry.$2,
                        style: ResponsiveHelper.smallStyle(
                          context,
                          color: _isKorean == entry.$1
                              ? Colors.white
                              : AppColors.grey600,
                          fontWeight: _isKorean == entry.$1
                              ? FontWeight.w600
                              : FontWeight.normal,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildStep1BasicInfo() {
    return Form(
      key: _formKey,
      autovalidateMode: _autovalidateMode,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── 내국인/외국인 선택 ──
          _buildNationalityToggle(),

          const SizedBox(height: 20),

          // ── 기본 정보 카드 (이름 + 아이디 + 주민번호/PASS) ──
          _buildSectionLabel('기본 정보', Icons.person_outline),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: CommonWidgets.compactCardDecoration(),
            child: Column(
              children: [
                // 아이디 — ValueListenableBuilder로 아이디 필드만 재빌드
                ValueListenableBuilder<_UsernameStatus>(
                  valueListenable: _usernameStatus,
                  builder: (context, status, _) => CommonWidgets.textField(
                    context: context,
                    controller: _usernameController,
                    label: '아이디',
                    hint: '영문소문자, 숫자 (4-20자)',
                    icon: Icons.account_circle_outlined,
                    focusNode: _usernameFocus,
                    textInputAction: TextInputAction.next,
                    onFieldSubmitted: (_) => _residentNumber1Focus.requestFocus(),
                    suffixIcon: !status.hasText
                        ? null
                        : status.isChecking
                            ? const SizedBox(
                                width: 20, height: 20,
                                child: Padding(
                                  padding: EdgeInsets.all(12),
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                ),
                              )
                            : status.isAvailable
                                ? Icon(Icons.check_circle,
                                    color: AppColors.success,
                                    size: ResponsiveHelper.iconSize(context, 22))
                                : status.error != null
                                    ? Icon(Icons.cancel,
                                        color: AppColors.error,
                                        size: ResponsiveHelper.iconSize(context, 22))
                                    : null,
                    validator: (value) {
                      if (value == null || value.isEmpty) return '아이디를 입력해주세요';
                      if (value.length < 4) return '4자 이상 입력해주세요';
                      if (!_usernameRe.hasMatch(value)) {
                        return '영문 소문자, 숫자, _만 사용 가능';
                      }
                      if (!status.isAvailable) return '중복 확인을 해주세요';
                      return null;
                    },
                    onChanged: (value) {
                      // setState 없이 notifier만 업데이트 → 아이디 필드만 재빌드
                      _usernameStatus.value = _UsernameStatus(hasText: value.isNotEmpty);
                      _usernameDebounce?.cancel();
                      if (value.trim().length >= 4 &&
                          _usernameRe.hasMatch(value.trim())) {
                        _usernameDebounce = Timer(
                          const Duration(milliseconds: 600),
                          _checkUsername,
                        );
                      }
                    },
                  ),
                ),

                const SizedBox(height: 10),

                // 내국인: PASS 인증 버튼 → 완료 시 결과 표시 (이름/성별/생년월일/전화번호)
                if (_isKorean) ...[
                  PassAuthButton(
                    onPressed: _handlePassAuth,
                    isLoading: _isPassLoading,
                    isCompleted: _passAuthResult != null,
                  ),
                  if (_passAuthResult != null) ...[
                    const SizedBox(height: 12),
                    PassResultDisplay(result: _passAuthResult!),
                  ],
                ],

                // 외국인: 이름 직접 입력 (내국인은 PASS 인증에서 자동 입력)
                if (!_isKorean) ...[
                  const SizedBox(height: 10),
                  CommonWidgets.textField(
                    context: context,
                    controller: _nameController,
                    label: '이름',
                    hint: '홍길동',
                    icon: Icons.person_outline,
                    focusNode: _nameFocus,
                    textInputAction: TextInputAction.next,
                    onFieldSubmitted: (_) => _residentNumber1Focus.requestFocus(),
                    inputFormatters: [LengthLimitingTextInputFormatter(50)],
                    validator: (value) {
                      if (!_isKorean) {
                        if (value == null || value.trim().isEmpty) return '이름을 입력해주세요';
                        if (value.trim().length < 2) return '이름은 2글자 이상 입력해주세요';
                        if (value.trim().length > 50) return '이름은 50자 이하로 입력해주세요';
                        if (!_korNameRe.hasMatch(value.trim())) {
                          return '이름은 한글 또는 영문만 입력해주세요';
                        }
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 10),
                ],

                // 외국인: 외국인등록번호 입력 (앞 6자리 - 뒷 1자리)
                if (!_isKorean) ...[
                  Row(
                    children: [
                      Icon(Icons.credit_card,
                          color: Theme.of(context).primaryColor,
                          size: ResponsiveHelper.iconSize(context, 16)),
                      const SizedBox(width: 6),
                      Text('외국인등록번호',
                          style: ResponsiveHelper.smallStyle(context,
                              color: AppColors.grey600,
                              fontWeight: FontWeight.w600)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 5,
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
                            hintText: '앞 6자리 (990101)',
                            hintStyle: ResponsiveHelper.smallStyle(context, color: AppColors.grey400),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                            filled: true, fillColor: AppColors.grey50, isDense: true,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                          ),
                          validator: (v) => (!_isKorean && (v == null || v.length != 6)) ? '6자리 입력' : null,
                          onChanged: (v) {
                            if (v.length == 6) {
                              _parseResidentNumber();
                              _residentNumber2Focus.requestFocus();
                            } else {
                              _residentResult.value = const _ResidentResult();
                            }
                          },
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        child: Text('-', style: ResponsiveHelper.titleStyle(context)),
                      ),
                      Expanded(
                        flex: 2,
                        child: TextFormField(
                          controller: _residentNumber2Controller,
                          focusNode: _residentNumber2Focus,
                          keyboardType: TextInputType.number,
                          textInputAction: TextInputAction.next,
                          onFieldSubmitted: (_) => _phoneFocus.requestFocus(),
                          inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(1)],
                          style: ResponsiveHelper.bodyStyle(context),
                          decoration: InputDecoration(
                            hintText: '5~8',
                            hintStyle: ResponsiveHelper.smallStyle(context, color: AppColors.grey400),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                            filled: true, fillColor: AppColors.grey50, isDense: true,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                          ),
                          validator: (v) => (!_isKorean && (v == null || v.isEmpty)) ? '필수' : null,
                          onChanged: (v) {
                            if (v.isNotEmpty) {
                              _parseResidentNumber();
                            } else {
                              _residentResult.value = const _ResidentResult();
                            }
                          },
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(left: 6, top: 12),
                        child: Text('●●●●●●',
                            style: ResponsiveHelper.smallStyle(context,
                                color: AppColors.grey500)),
                      ),
                    ],
                  ),
                  ValueListenableBuilder<_ResidentResult>(
                    valueListenable: _residentResult,
                    builder: (context, rr, _) {
                      final rn1 = _residentNumber1Controller.text;
                      final rn2 = _residentNumber2Controller.text;
                      if (rn1.length != 6 || rn2.isEmpty) return const SizedBox.shrink();
                      final ok = rr.birthDate != null && rr.gender != null;
                      return Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: ok ? AppColors.successBg : AppColors.errorBg,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(children: [
                            Icon(
                              ok ? Icons.check_circle : Icons.error_outline,
                              color: ok ? AppColors.successDark : AppColors.errorDark,
                              size: ResponsiveHelper.iconSize(context, 16),
                            ),
                            const SizedBox(width: 6),
                            Expanded(child: Text(
                              ok
                                  ? '${rr.birthDate!.year}.${rr.birthDate!.month}.${rr.birthDate!.day} / ${rr.gender}'
                                  : rr.error ?? '올바른 번호를 입력해주세요',
                              style: ResponsiveHelper.smallStyle(context,
                                  color: ok ? AppColors.successDeep : AppColors.errorDeep),
                            )),
                          ]),
                        ),
                      );
                    },
                  ),
                ],
              ],
            ),
          ),

          const SizedBox(height: 20),

          // ── 연락처 카드 ──
          _buildSectionLabel('연락처', Icons.contact_phone_outlined),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: CommonWidgets.compactCardDecoration(),
            child: Column(
              children: [
                // 내국인: PASS에서 받아온 전화번호 (읽기 전용)
                if (_isKorean)
                  CommonWidgets.textField(
                    context: context,
                    controller: _phoneController,
                    label: '전화번호',
                    hint: 'PASS 인증 후 자동 입력',
                    icon: Icons.phone_outlined,
                    readOnly: true,
                  ),

                // 외국인: 전화번호 직접 입력 + SMS OTP
                if (!_isKorean) ...[
                  CommonWidgets.textField(
                    context: context,
                    controller: _phoneController,
                    label: '전화번호',
                    hint: '01012345678',
                    icon: Icons.phone_outlined,
                    keyboardType: TextInputType.phone,
                    focusNode: _phoneFocus,
                    textInputAction: TextInputAction.next,
                    onChanged: (value) {
                      // [M-01-FIX] isVerified 상태에서도 번호 변경 시 재인증 초기화
                      // 이전: isSent만 체크 → 인증 완료 후 번호 교체해도 isVerified가 유지됨
                      if (value != _lastSentPhone &&
                          (_phoneVerifyStatus.value.isSent || _phoneVerifyStatus.value.isVerified)) {
                        _phoneVerifyStatus.value = const _PhoneVerifyStatus();
                      }
                      if (value.length == 11) {
                        Future.delayed(const Duration(milliseconds: 100), () {
                          if (mounted) kIsWeb ? _addressFocus.requestFocus() : _detailAddressFocus.requestFocus();
                        });
                      }
                    },
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(11),
                    ],
                    validator: (value) {
                      if (!_isKorean && (value == null || value.isEmpty)) return '전화번호를 입력해주세요';
                      if (!_isKorean && value!.length < 10) return '올바른 전화번호를 입력해주세요';
                      return null;
                    },
                  ),
                  ListenableBuilder(
                    listenable: Listenable.merge([_phoneVerifyStatus, _phoneController]),
                    builder: (context, _) {
                      final status = _phoneVerifyStatus.value;
                      final phone = _phoneController.text.trim();
                      final theme = Theme.of(context);

                      if (status.isVerified) return _buildPhoneVerifiedBadge(context);
                      if (status.isSent) return _buildPhoneCodeInput(context, theme, status);
                      if (phone.length >= 10) {
                        return Padding(
                          padding: EdgeInsets.only(top: ResponsiveHelper.spacing(context, 8)),
                          child: SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: status.isSending ? null : _sendPhoneCode,
                              icon: status.isSending
                                  ? SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: theme.primaryColor))
                                  : const Icon(Icons.sms_outlined, size: 16),
                              label: Text(
                                status.isSending ? '발송 중...' : '휴대폰 인증하기',
                                style: ResponsiveHelper.smallStyle(context, color: theme.primaryColor, fontWeight: FontWeight.w600),
                              ),
                              style: OutlinedButton.styleFrom(
                                padding: EdgeInsets.symmetric(vertical: ResponsiveHelper.spacing(context, 10)),
                                side: BorderSide(color: theme.primaryColor),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                            ),
                          ),
                        );
                      }
                      return const SizedBox.shrink();
                    },
                  ),
                ],
              ],
            ),
          ),

          const SizedBox(height: 20),

          // ── 주소 카드 ──
          _buildSectionLabel('주소', Icons.location_on_outlined),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: CommonWidgets.compactCardDecoration(),
            child: Column(
              children: [
                if (kIsWeb) ...[
                  CommonWidgets.textField(
                    context: context,
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
                  CommonWidgets.textField(
                    context: context,
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
                const SizedBox(height: 10),
                CommonWidgets.textField(
                  context: context,
                  controller: _detailAddressController,
                  label: '상세 주소',
                  hint: '동/호수 등 상세 주소',
                  icon: Icons.home_outlined,
                  focusNode: _detailAddressFocus,
                  textInputAction: TextInputAction.next,
                  onFieldSubmitted: (_) => _passwordFocus.requestFocus(),
                  validator: (value) => null,
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // ── 비밀번호 카드 ──
          _buildSectionLabel('비밀번호', Icons.lock_outline),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: CommonWidgets.compactCardDecoration(),
            child: Column(
              children: [
                // 비밀번호 — ValueListenableBuilder로 해당 위젯만 재빌드
                ValueListenableBuilder<TextEditingValue>(
                  valueListenable: _passwordController,
                  builder: (context, pwValue, _) => Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CommonWidgets.textField(
                        context: context,
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
                      ),
                      if (pwValue.text.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        _buildPasswordChecklist(),
                      ],
                    ],
                  ),
                ),

                const SizedBox(height: 10),

                // 비밀번호 확인 — ValueListenableBuilder로 아이콘만 재빌드
                ValueListenableBuilder<TextEditingValue>(
                  valueListenable: _confirmPasswordController,
                  builder: (context, confirmValue, _) => CommonWidgets.textField(
                    context: context,
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
                        if (confirmValue.text.isNotEmpty)
                          Icon(
                            confirmValue.text == _passwordController.text
                                ? Icons.check_circle
                                : Icons.cancel,
                            color: confirmValue.text == _passwordController.text
                                ? AppColors.success
                                : AppColors.error,
                            size: ResponsiveHelper.iconSize(context, 20),
                          ),
                        IconButton(
                          icon: Icon(
                            _obscureConfirmPassword
                                ? Icons.visibility_off
                                : Icons.visibility,
                            color: AppColors.grey600,
                            size: ResponsiveHelper.iconSize(context, 20),
                          ),
                          onPressed: () =>
                              setState(() => _obscureConfirmPassword = !_obscureConfirmPassword),
                        ),
                      ],
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) return '비밀번호를 다시 입력해주세요';
                      if (value != _passwordController.text) return '비밀번호가 일치하지 않습니다';
                      return null;
                    },
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // ── 약관 동의 (flat, divider 기반) ──
          // ValueListenableBuilder로 동의 섹션만 재빌드 — 체크 시 전체 폼 rebuild 방지
          ValueListenableBuilder<Map<String, bool>>(
            valueListenable: _consentNotifier,
            builder: (context, _, __) => _buildConsentSection(),
          ),

          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _buildPasswordChecklist() {
    final pw = _passwordController.text;
    final checks = [
      (_pwLengthRe.hasMatch(pw),  '8자 이상'),
      (_pwLetterRe.hasMatch(pw),  '영문 포함'),
      (_pwDigitRe.hasMatch(pw),   '숫자 포함'),
      (_pwSpecialRe.hasMatch(pw), '특수문자 포함'),
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
              child: LinearProgressIndicator(
                value: passed / 4,
                backgroundColor: AppColors.grey200,
                borderRadius: BorderRadius.circular(4),
                valueColor: AlwaysStoppedAnimation(strengthColor),
                minHeight: 5,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              strengthLabel,
              style: ResponsiveHelper.smallStyle(context, color: strengthColor).copyWith(
                fontWeight: FontWeight.w600,
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
            style: ResponsiveHelper.smallStyle(
              context,
              color: passed ? AppColors.successDark : AppColors.grey500,
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // ── 법적 동의 섹션 — Firestore 약관 동적 로드 ─────────────
  // ============================================================

  bool get _agreedToAll {
    if (_legalTerms == null) return false;
    return _legalTerms!.activeItems.every((t) => _consentMap[t.id] == true);
  }

  Widget _buildConsentSection() {
    final theme = Theme.of(context);

    if (_isTermsLoading) {
      return Padding(
        padding: EdgeInsets.symmetric(
            vertical: ResponsiveHelper.spacing(context, 16)),
        child: Center(
          child: SizedBox(
            width: 20, height: 20,
            child: CircularProgressIndicator(
                strokeWidth: 2, color: theme.primaryColor),
          ),
        ),
      );
    }

    final items = _legalTerms?.activeItems ?? [];
    final agreedToAll = _agreedToAll;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(),
        SizedBox(height: ResponsiveHelper.spacing(context, 4)),

        // 전체 동의 — 미열람 항목이 있으면 순차 열람 후 전체 동의
        InkWell(
          onTap: () async {
            final newVal = !agreedToAll;
            if (newVal) {
              // 현재 미동의 항목 전부 뷰어 표시 (열람 이력 무관)
              final unagreed = items
                  .where((t) => _consentMap[t.id] != true)
                  .toList();
              final refusedIds = <String>{};
              for (final item in unagreed) {
                if (!mounted) return;
                await _showTermsDetail(item);
                if (_consentNotifier.value[item.id] != true) {
                  refusedIds.add(item.id);
                }
              }
              if (!mounted) return;
              // 거절하지 않은 항목만 true로 설정
              final updated = Map<String, bool>.from(_consentNotifier.value);
              for (final t in items) {
                if (!refusedIds.contains(t.id)) updated[t.id] = true;
              }
              _consentNotifier.value = updated;
            } else {
              if (!mounted) return;
              final updated = Map<String, bool>.from(_consentNotifier.value);
              for (final t in items) { updated[t.id] = false; }
              _consentNotifier.value = updated;
            }
          },
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: ResponsiveHelper.spacing(context, 4),
              vertical: ResponsiveHelper.spacing(context, 8),
            ),
            child: Row(children: [
              Icon(
                agreedToAll ? Icons.check_circle : Icons.check_circle_outline,
                color: agreedToAll ? theme.primaryColor : AppColors.grey400,
                size: ResponsiveHelper.iconSize(context, 18),
              ),
              SizedBox(width: ResponsiveHelper.spacing(context, 8)),
              Text('전체 동의',
                  style: ResponsiveHelper.bodyStyle(context)
                      .copyWith(fontWeight: FontWeight.bold)),
              SizedBox(width: ResponsiveHelper.spacing(context, 6)),
              Text('(필수 및 선택 포함)',
                  style: ResponsiveHelper.tinyStyle(context,
                      color: AppColors.grey400)),
            ]),
          ),
        ),

        const Divider(height: 1),
        SizedBox(height: ResponsiveHelper.spacing(context, 4)),

        // 동의 항목 목록 (Firestore에서 로드)
        for (final item in items)
          _buildConsentRow(
            label: item.title,
            isRequired: item.isRequired,
            agreed: _consentMap[item.id] ?? false,
            viewed: _viewedTermIds.contains(item.id),
            onChanged: (v) {
              // 열람하지 않은 항목 체크 시도 → 자동으로 뷰어 열기
              if (v && !_viewedTermIds.contains(item.id)) {
                _showTermsDetail(item);
                return;
              }
              _consentNotifier.value = {
                ..._consentNotifier.value,
                item.id: v,
              };
            },
            onViewTap: () => _showTermsDetail(item),
          ),
      ],
    );
  }

  Widget _buildConsentRow({
    required String label,
    required bool isRequired,
    required bool agreed,
    required void Function(bool) onChanged,
    bool viewed = false, // 열람 여부 — 미열람 시 체크박스 시각적 힌트
    VoidCallback? onViewTap,
  }) {
    final theme = Theme.of(context);
    // 미열람 상태의 체크박스 색상: 회색 (열람 유도)
    final checkColor = agreed
        ? theme.primaryColor
        : viewed
            ? AppColors.grey400
            : AppColors.grey300;

    return Padding(
      padding: EdgeInsets.symmetric(
          vertical: ResponsiveHelper.spacing(context, 2)),
      child: Row(children: [
        InkWell(
          onTap: () => onChanged(!agreed),
          borderRadius: BorderRadius.circular(4),
          child: Icon(
            agreed ? Icons.check_circle : Icons.check_circle_outline,
            color: checkColor,
            size: ResponsiveHelper.iconSize(context, 18),
          ),
        ),
        SizedBox(width: ResponsiveHelper.spacing(context, 8)),
        // 필수/선택 배지
        Container(
          padding: EdgeInsets.symmetric(
              horizontal: ResponsiveHelper.spacing(context, 5), vertical: 1),
          decoration: BoxDecoration(
            color: isRequired ? AppColors.errorBg : AppColors.grey100,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            isRequired ? '필수' : '선택',
            style: ResponsiveHelper.tinyStyle(context,
                color: isRequired ? AppColors.error : AppColors.grey500,
                fontWeight: FontWeight.w600),
          ),
        ),
        SizedBox(width: ResponsiveHelper.spacing(context, 6)),
        Expanded(
          child: InkWell(
            onTap: () => onChanged(!agreed),
            child: Text(label,
                style: ResponsiveHelper.smallStyle(context,
                    color: AppColors.grey700)),
          ),
        ),
        if (onViewTap != null)
          TextButton(
            onPressed: onViewTap,
            style: TextButton.styleFrom(
              padding: EdgeInsets.symmetric(
                  horizontal: ResponsiveHelper.spacing(context, 4)),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            // 미열람이면 '보기' 강조, 열람 완료면 일반 스타일
            child: Text(
              viewed ? '다시보기' : '보기 *',
              style: ResponsiveHelper.tinyStyle(context,
                  color: viewed
                      ? AppColors.grey400
                      : theme.primaryColor,
                  fontWeight: viewed ? FontWeight.normal : FontWeight.w600)
                  .copyWith(
                    decoration: TextDecoration.underline,
                    decorationColor: viewed
                        ? AppColors.grey400
                        : theme.primaryColor,
                  ),
            ),
          ),
      ]),
    );
  }

  /// 약관 전체 화면 뷰어 (카카오/네이버 스타일)
  /// - '동의하고 닫기' 버튼으로 체크박스 자동 체크
  /// - '닫기'는 체크 없이 종료
  Future<void> _showTermsDetail(LegalTermsItem item) async {
    // 뷰어를 열었다는 것 자체를 "열람 완료"로 기록
    _viewedTermIds.add(item.id);

    final agreed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _TermsViewerScreen(item: item),
      ),
    );
    if (agreed == true && mounted) {
      _consentNotifier.value = {..._consentNotifier.value, item.id: true};
    }
    // 뷰어에서 동의하지 않고 닫아도 열람 기록은 유지 (재열람 없이 체크 허용)
  }

  // ============================================================
  // 📝 Step 2: 역할 선택
  // ============================================================

  Widget _buildStep2RoleSelection() {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: AppColors.infoBg,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Icon(
                Icons.help_outline,
                color: AppColors.infoDark,
                size: 18,
              ),
              const SizedBox(width: 8),
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
        SizedBox(height: ResponsiveHelper.spacing(context, 16)),
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
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: AppColors.infoBg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.infoLight),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: AppColors.infoMedium,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.info_outline,
                      color: Colors.white,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '서류 제출 안내',
                          style: ResponsiveHelper.bodyStyle(context).copyWith(
                            fontWeight: FontWeight.w700,
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
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildNoticeItem('✓ 신분증과 통장의 이름이 일치해야 합니다', AppColors.infoDeep),
                    const SizedBox(height: 2),
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
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: CommonWidgets.compactCardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: Theme.of(context).primaryColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.badge,
                  color: Theme.of(context).primaryColor,
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                '신분증 앞면',
                style: ResponsiveHelper.bodyStyle(context).copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              if (_idCardImagePath != null)
                Icon(
                  Icons.check_circle,
                  color: AppColors.successMedium,
                  size: 18,
                ),
            ],
          ),
          const SizedBox(height: 10),
          InkWell(
            onTap: _pickIdCardImage,
            borderRadius: BorderRadius.circular(10),
            child: Container(
              height: 80,
              decoration: BoxDecoration(
                color: AppColors.grey100,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: _idCardImagePath != null
                      ? AppColors.successSoft
                      : AppColors.grey300,
                  width: 1.5,
                ),
              ),
              child: Center(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      _idCardImagePath != null
                          ? Icons.check_circle_outline
                          : Icons.add_photo_alternate,
                      size: 20,
                      color: _idCardImagePath != null
                          ? AppColors.successMedium
                          : AppColors.grey400,
                    ),
                    const SizedBox(width: 8),
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
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: CommonWidgets.compactCardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: Theme.of(context).primaryColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.account_balance_wallet,
                  color: Theme.of(context).primaryColor,
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                '급여 통장 정보',
                style: ResponsiveHelper.bodyStyle(context).copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          
          // 은행 선택
          AppSelectField<String>(
            value: _selectedBank,
            hintText: '은행을 선택하세요',
            sheetTitle: '은행 선택',
            items: const [
              'KB국민은행', '신한은행', 'NH농협은행', '우리은행', '하나은행',
              'IBK기업은행', '카카오뱅크', '토스뱅크', '새마을금고', '우체국',
            ],
            labelOf: (b) => b,
            prefixIcon: Icons.account_balance,
            onChanged: (value) {
              setState(() => _selectedBank = value);
              Future.delayed(const Duration(milliseconds: 200), () {
                if (mounted) _accountNumberFocus.requestFocus();
              });
            },
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 12)),
          
          // 계좌번호 입력
          CommonWidgets.textField(
            context: context,
            controller: _accountNumberController,
            label: '계좌번호',
            hint: '- 없이 숫자만 입력',
            icon: Icons.credit_card_outlined,
            keyboardType: TextInputType.number,
            focusNode: _accountNumberFocus,
            textInputAction: TextInputAction.done,
            onFieldSubmitted: (_) => FocusScope.of(context).unfocus(),
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(20),
            ],
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 10)),
          
          // 예금주 안내
          Container(
            padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 10)),
            decoration: BoxDecoration(
              color: AppColors.success.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.success.withValues(alpha: 0.3)),
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
              height: 80,
              decoration: BoxDecoration(
                color: AppColors.grey100,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: _bankbookImagePath != null
                      ? AppColors.successSoft
                      : AppColors.grey300,
                  width: 1.5,
                ),
              ),
              child: Center(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      _bankbookImagePath != null
                          ? Icons.check_circle_outline
                          : Icons.add_photo_alternate,
                      size: 20,
                      color: _bankbookImagePath != null
                          ? AppColors.successMedium
                          : AppColors.grey400,
                    ),
                    const SizedBox(width: 8),
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
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: theme.primaryColor.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: theme.primaryColor.withValues(alpha: 0.25),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: theme.primaryColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.business_center,
                  color: theme.primaryColor,
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '사업장 관리자 정보',
                      style: ResponsiveHelper.bodyStyle(context).copyWith(
                        color: theme.primaryColor,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
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
            ],
          ),
        ),
        
        SizedBox(height: ResponsiveHelper.spacing(context, 16)),
        
        // 입력 카드 섹션
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: CommonWidgets.compactCardDecoration(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildBusinessNumberField(),
              SizedBox(height: ResponsiveHelper.spacing(context, 12)),
              CommonWidgets.textField(
                context: context,
                controller: _businessNameController,
                label: '상호명',
                hint: '예: 홍길동 물류센터',
                icon: Icons.store_outlined,
                focusNode: _businessNameFocus,
                textInputAction: TextInputAction.next,
                onFieldSubmitted: (_) => _ceoNameFocus.requestFocus(),
                inputFormatters: [LengthLimitingTextInputFormatter(100)],
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
        _buildSectionLabel('사업자등록증', Icons.business_outlined),

        Builder(builder: (context) {
          final bizReady = _businessNumberController.text.replaceAll('-', '').length == 10;
          return _buildDocumentUploadCard(
            title: '사업자등록증',
            description: bizReady
                ? '사업자등록증을 촬영해주세요'
                : '사업자등록번호를 먼저 입력해주세요',
            icon: Icons.business,
            imagePath: _businessLicenseImagePath,
            color: bizReady ? theme.primaryColor : AppColors.grey400,
            onTap: _pickBusinessLicenseImage,
          );
        }),
        
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CommonWidgets.textField(
          context: context,
          controller: _businessNumberController,
          label: '사업자등록번호',
          hint: '0000000000',
          icon: Icons.badge_outlined,
          keyboardType: TextInputType.number,
          textInputAction: TextInputAction.next,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(10),
          ],
          onChanged: (value) {
            if (value.length == 10) _businessNameFocus.requestFocus();
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: CommonWidgets.textField(
                context: context,
                controller: _ceoNameController,
                label: '대표자명',
                hint: '예: 홍길동',
                icon: Icons.person_outline,
                focusNode: _ceoNameFocus,
                textInputAction: TextInputAction.done,
                onFieldSubmitted: (_) => FocusScope.of(context).unfocus(),
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
                  color: Theme.of(context).primaryColor,
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
    final digits = value.replaceAll(_nonDigitRe, '');
    if (digits.length != 10) return value;
    return '${digits.substring(0, 3)}-${digits.substring(3, 5)}-${digits.substring(5, 10)}';
  }

  /// 국세청 사업자등록번호 체크섬 검증
  /// 가중치 [1,3,7,1,3,7,1,3,5] 적용 후 검증 자릿수 비교
  bool _isValidBusinessNumber(String num) {
    if (num.length != 10) return false;
    final d = num.split('').map(int.parse).toList();
    const w = [1, 3, 7, 1, 3, 7, 1, 3, 5];
    int sum = 0;
    for (int i = 0; i < 9; i++) { sum += d[i] * w[i]; }
    sum += (d[8] * 5) ~/ 10;
    final checkDigit = (10 - (sum % 10)) % 10;
    return checkDigit == d[9];
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
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isUploaded ? color.withValues(alpha: 0.08) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isUploaded ? color : AppColors.grey300,
            width: isUploaded ? 2 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 4,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: isUploaded ? color : color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                isUploaded ? Icons.check : icon,
                color: isUploaded ? Colors.white : color,
                size: 18,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: ResponsiveHelper.bodyStyle(context).copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    isUploaded ? '완료 · 탭하여 다시 등록' : description,
                    style: ResponsiveHelper.smallStyle(
                      context,
                      color: isUploaded ? color : AppColors.grey600,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              isUploaded ? Icons.refresh : Icons.camera_alt,
              color: color,
              size: 18,
            ),
          ],
        ),
      ),
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
      onTap: () => setState(() {
        if (_selectedRole == role) return;
        _selectedRole = role;
        // 역할 변경 시 인증 상태 초기화 — 이전 역할 기준 인증 결과가 재사용되는 것 방지
        _passAuthResult = null;
        _phoneVerifyStatus.value = const _PhoneVerifyStatus();
        _phoneController.clear();
      }),
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? color.withValues(alpha: 0.08) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? color : AppColors.grey300,
            width: isSelected ? 2 : 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: color.withValues(alpha: 0.15),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ]
              : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  ),
                ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: isSelected ? color : color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    icon,
                    color: isSelected ? Colors.white : color,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: ResponsiveHelper.bodyStyle(context).copyWith(
                          color: isSelected ? color : AppColors.grey800,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 1),
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
                  size: 20,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Divider(color: AppColors.grey200, height: 1),
            const SizedBox(height: 6),
            ...features.map((feature) => Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Row(
                children: [
                  Icon(
                    Icons.check,
                    size: 12,
                    color: isSelected ? color : AppColors.grey500,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    feature,
                    style: ResponsiveHelper.smallStyle(
                      context,
                      color: isSelected ? AppColors.grey800 : AppColors.grey700,
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
    // isLoading은 LoadingOverlay가 처리 — 여기서는 _isSubmitting만 체크
    return SafeArea(
      top: false,
      child: Padding(
      padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 16)),
      child: ElevatedButton(
        onPressed: _isSubmitting ? null : _onStepContinue,
        style: ElevatedButton.styleFrom(
          backgroundColor: theme.primaryColor,
          foregroundColor: Colors.white,
          padding: EdgeInsets.symmetric(
            vertical: ResponsiveHelper.spacing(context, 14),
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          elevation: 0,
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
      ),  // Padding
    );   // SafeArea
  }
}

/// 주민번호 파싱 결과 — ValueNotifier에 담겨 결과 표시 위젯만 재빌드
class _ResidentResult {
  final DateTime? birthDate;
  final String? gender;
  final String? error;

  const _ResidentResult({
    this.birthDate,
    this.gender,
    this.error,
  });
}

// ── 전화번호 SMS 인증 상태 ─────────────────────────────────────────
class _PhoneVerifyStatus {
  final bool isSending;   // 발송 중
  final bool isSent;      // 발송 완료 (코드 입력 창 표시)
  final bool isVerifying; // 검증 중
  final bool isVerified;  // 인증 완료
  final String? error;

  const _PhoneVerifyStatus({
    this.isSending = false,
    this.isSent = false,
    this.isVerifying = false,
    this.isVerified = false,
    this.error,
  });
}

/// 아이디 중복 확인 상태 — ValueNotifier에 담겨 해당 필드만 재빌드
class _UsernameStatus {
  final bool hasText;
  final bool isChecking;
  final bool isAvailable;
  final String? error;

  const _UsernameStatus({
    this.hasText = false,
    this.isChecking = false,
    this.isAvailable = false,
    this.error,
  });
}

// ── 약관 전체 화면 뷰어 ────────────────────────────────────────────
//
// 카카오·네이버 스타일:
// - 전체 내용 스크롤
// - 하단 '동의하고 닫기' → true 반환 (체크박스 자동 체크)
// - '닫기' → null 반환 (체크 없이 종료)

class _TermsViewerScreen extends StatefulWidget {
  final LegalTermsItem item;
  const _TermsViewerScreen({required this.item});

  @override
  State<_TermsViewerScreen> createState() => _TermsViewerScreenState();
}

class _TermsViewerScreenState extends State<_TermsViewerScreen> {
  final _scrollCtrl = ScrollController();
  bool _reachedBottom = false;

  @override
  void initState() {
    super.initState();
    _scrollCtrl.addListener(_onScroll);
    // 내용이 짧으면 처음부터 동의 가능
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients &&
          _scrollCtrl.position.maxScrollExtent < 50) {
        setState(() => _reachedBottom = true);
      }
    });
  }

  void _onScroll() {
    if (_reachedBottom) return;
    final pos = _scrollCtrl.position;
    if (pos.pixels >= pos.maxScrollExtent - 80) {
      setState(() => _reachedBottom = true);
    }
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: theme.primaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.item.title,
                style: ResponsiveHelper.bodyStyle(context,
                    color: Colors.white)
                    .copyWith(fontWeight: FontWeight.bold)),
            Text('v${widget.item.version}',
                style: ResponsiveHelper.tinyStyle(context,
                    color: Colors.white.withValues(alpha: 0.75))),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('닫기',
                style: ResponsiveHelper.smallStyle(context,
                    color: Colors.white.withValues(alpha: 0.85))),
          ),
        ],
      ),
      body: Column(
        children: [
          // 스크롤 진행 안내
          if (!_reachedBottom)
            Container(
              width: double.infinity,
              color: AppColors.grey50,
              padding: EdgeInsets.symmetric(
                horizontal: ResponsiveHelper.spacing(context, 16),
                vertical: ResponsiveHelper.spacing(context, 8),
              ),
              child: Row(children: [
                Icon(Icons.keyboard_arrow_down,
                    size: 16, color: AppColors.grey400),
                SizedBox(width: 4),
                Text('끝까지 스크롤하면 동의할 수 있습니다',
                    style: ResponsiveHelper.tinyStyle(context,
                        color: AppColors.grey500)),
              ]),
            ),

          // 약관 내용
          Expanded(
            child: SingleChildScrollView(
              controller: _scrollCtrl,
              padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 20)),
              child: Text(
                widget.item.content,
                style: ResponsiveHelper.smallStyle(context,
                    color: AppColors.grey700)
                    .copyWith(height: 1.7),
              ),
            ),
          ),

          // 하단 동의 버튼
          SafeArea(
            top: false,
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                ResponsiveHelper.spacing(context, 16),
                ResponsiveHelper.spacing(context, 8),
                ResponsiveHelper.spacing(context, 16),
                ResponsiveHelper.spacing(context, 12),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 동의하기 (메인 CTA)
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _reachedBottom
                          ? () => Navigator.pop(context, true)
                          : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: theme.primaryColor,
                        disabledBackgroundColor: AppColors.grey200,
                        padding: EdgeInsets.symmetric(
                            vertical: ResponsiveHelper.spacing(context, 14)),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        elevation: 0,
                      ),
                      child: Text(
                        _reachedBottom ? '동의하고 닫기' : '내용을 끝까지 확인해주세요',
                        style: ResponsiveHelper.bodyStyle(context).copyWith(
                          color: _reachedBottom ? Colors.white : AppColors.grey400,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  // 동의 없이 닫기
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text('동의하지 않고 닫기',
                        style: ResponsiveHelper.smallStyle(context,
                            color: AppColors.grey400)),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

