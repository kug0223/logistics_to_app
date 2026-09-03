import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter/services.dart';
import '../../models/core/user_model.dart';
import '../../providers/user_provider.dart';
import '../../widgets/common/loading_widget.dart';
import '../../utils/responsive_helper.dart';
import '../../services/auth_service.dart';
import '../../services/analytics_service.dart';
import '../../services/legal_terms_service.dart';
import '../../services/phone_verification_service.dart';
import '../../services/pass_verification_service.dart';
import '../../models/core/legal_terms_model.dart';
import '../../models/core/user_region.dart';
import '../../widgets/inputs/home_region_picker_sheet.dart';
import '../../utils/toast_helper.dart';
import '../../widgets/auth/pass_auth_button.dart';
import '../../widgets/auth/pass_result_display.dart';
import '../../widgets/auth/terms_viewer_screen.dart';

import 'package:firebase_auth/firebase_auth.dart' show FirebaseAuth, FirebaseAuthException;
import 'package:cloud_functions/cloud_functions.dart';
import '../../theme/app_colors.dart';
import '../../widgets/common/common_widgets.dart';
import 'foreign_register_screen.dart';

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

  final LegalTermsService _legalTermsService = LegalTermsService();
  final PhoneVerificationService _phoneSvc = PhoneVerificationService();

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

  // 주로 일할 지역 (USER 가입 시 필수, BUSINESS_ADMIN은 null)
  UserRegion? _selectedHomeRegion;

  // 주민번호 파싱 정보 — ValueNotifier로 분리해 타이핑마다 전체 폼 rebuild 방지
  final _residentResult = ValueNotifier<_ResidentResult>(const _ResidentResult());

  // 내국인/외국인 분기
  bool _isKorean = true;
  PassAuthResult? _passAuthResult;
  bool _isPassLoading = false;

  // Step 0: 역할 선택
  UserRole? _selectedRole;

  // FocusNode 선언
  final _nameFocus = FocusNode();
  final _usernameFocus = FocusNode();
  final _residentNumber1Focus = FocusNode();
  final _residentNumber2Focus = FocusNode();
  final _phoneFocus = FocusNode();
  final _passwordFocus = FocusNode();
  final _confirmPasswordFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(milliseconds: 400), () {
      if (mounted) _nameFocus.requestFocus();
    });
    _loadTerms();
    // 사업자등록번호 의존 UI는 ValueListenableBuilder로 격리 — 전체 rebuild 불필요
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

    _usernameDebounce?.cancel();
    _nameFocus.dispose();
    _usernameFocus.dispose();
    _residentNumber1Focus.dispose();
    _residentNumber2Focus.dispose();
    _phoneFocus.dispose();
    _passwordFocus.dispose();
    _confirmPasswordFocus.dispose();
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

  // ── 주로 일할 지역 선택 ──────────────────────────────────────────

  Future<void> _pickHomeRegion() async {
    final result = await HomeRegionPickerSheet.show(
      context: context,
      selectedRegion: _selectedHomeRegion,
    );
    if (result != null && mounted) {
      setState(() => _selectedHomeRegion = result);
    }
  }

  // Step 검증
  /// STEP 2: 기본 정보 (공통) + ADMIN은 약관 포함
  bool _validateStep1() {
    if (!(_formKey.currentState?.validate() ?? false)) return false;

    if (_isKorean) {
      // 내국인: 본인인증 완료 여부 확인
      if (_passAuthResult == null) {
        ToastHelper.showWarning('본인인증을 완료해주세요');
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

    // BUSINESS_ADMIN: 약관 동의 여기서 검증 (ADMIN은 STEP 3 없음)
    if (_selectedRole == UserRole.BUSINESS_ADMIN) {
      final requiredItems = _legalTerms?.activeItems
          .where((t) => t.isRequired)
          .toList() ?? [];
      final allRequiredAgreed = requiredItems.every(
          (t) => _consentMap[t.id] == true);
      if (!allRequiredAgreed) {
        ToastHelper.showWarning('필수 약관에 모두 동의해주세요');
        return false;
      }
    }

    return true;
  }

  /// STEP 3 (USER 전용): 주로 일할 지역 + 약관 동의
  bool _validateStep3User() {
    if (_selectedHomeRegion == null) {
      ToastHelper.showWarning('주로 일할 지역을 선택해주세요');
      return false;
    }

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
      // 단계 내부 번호(_currentStep)와 UI 표시 레이블:
      //   Step 0 → "이용 방법 선택" (_buildStep2RoleSelection)
      //   Step 1 → "기본 정보 입력"  (_buildStep1BasicInfo)
      //             - USER  → Step 2 (일자리 시작 설정)
      //             - ADMIN → 바로 가입 완료 (STEP 3 없음)
      //   Step 2 → "일자리 시작 설정" (_buildStep3UserStart) — USER 전용
      if (_currentStep == 0) {
        if (_validateStep2()) {
          setState(() => _currentStep = 1);
          _scrollToTop();
        }
      } else if (_currentStep == 1) {
        // [V3 FOREIGN-DOCUMENT-FIRST] 외국인은 전용 마법사로 라우팅
        if (!_isKorean) {
          if (_selectedRole == null) {
            ToastHelper.showWarning('이용 방법을 먼저 선택해주세요');
            return;
          }
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ForeignRegisterScreen(role: _selectedRole!),
            ),
          );
          return;
        }
        if (_validateStep1()) {
          if (_selectedRole == UserRole.BUSINESS_ADMIN) {
            // ADMIN: STEP 3 없음 — 바로 가입 처리
            await _doRegister();
          } else {
            // USER: STEP 3 (주로 일할 지역 + 약관)으로 이동
            setState(() => _currentStep = 2);
            _scrollToTop();
          }
        } else {
          setState(() {
            _autovalidateMode = AutovalidateMode.onUserInteraction;
          });
        }
      } else if (_currentStep == 2) {
        // USER 전용 — 지역 + 약관 검증 후 가입
        if (_validateStep3User()) {
          await _doRegister();
        }
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

  // ============================================================
  // 📝 회원가입 로직
  // ============================================================

  /// 공통 가입 처리 — USER·ADMIN 모두 이 메서드 사용
  /// - USER: homeRegion = _selectedHomeRegion (STEP 3에서 선택)
  /// - ADMIN: homeRegion = null (STEP 3 없음)
  Future<void> _doRegister() async {
    if (_isSubmitting) return;
    setState(() => _isSubmitting = true);

    final userProvider = context.read<UserProvider>();
    final role = _selectedRole!;

    try {
      final rr = _residentResult.value;

      // [FOREIGN-IDENTITY-01] 외국인: HMAC 기반 사전 중복 체크 (UX용, atomic 체크는 finalize에서)
      // rawForeignId = 앞6자리 + 뒤7자리 (하이픈 없음, 평문 — HTTPS로 CF 전달)
      if (!_isKorean) {
        final rawForeignId = '${_residentNumber1Controller.text}${_residentNumber2Controller.text}';
        final exists = await AuthService().precheckForeignIdentity(rawForeignId, role);
        if (!mounted) return;
        if (exists) {
          ToastHelper.showError('이미 동일 역할로 가입된 외국인등록번호입니다.');
          setState(() => _isSubmitting = false);
          return;
        }
      }

      // 계정 생성 → UID 확보
      final success = await userProvider.signUp(
        username: _usernameController.text.trim(),
        password: _passwordController.text,
        name: _isKorean ? _passAuthResult!.name : _nameController.text.trim(),
        phone: _isKorean ? _passAuthResult!.phone : _phoneController.text.trim(),
        role: role,
        gender: _isKorean ? _passAuthResult!.gender : rr.gender,
        birthDate: _isKorean ? _passAuthResult!.birthDate : rr.birthDate,
        // [TODO-DANAL] 다날 계약 후 verifyPassAuth CF에서 받은 passToken을 경유해
        //   users/{uid}.ciHash 저장 필요. ciHash가 없으면 비밀번호 찾기 CI 매칭 실패.
        // [FOREIGN-IDENTITY-03] 외국인 residentNumber/foreignIdNumber:
        //   foreignIdNumber = SEC-102 규칙 통과용 sentinel (뒷첫자리+마스킹).
        //   실제 고유성 식별은 callableFinalizeForeignIdentity가 HMAC fingerprint로 처리.
        //   전체 외국인등록번호는 plaintext로 CF에만 전달 — Firestore에 직접 저장 안 함.
        residentNumber: null,
        foreignIdNumber: _isKorean ? null : '${_residentNumber1Controller.text}-${_residentNumber2Controller.text.substring(0, 1)}${('*' * 6)}',
        // [V3] _doRegister는 내국인 전용 경로 — 외국인은 ForeignRegisterScreen에서 처리
        accountStatus: 'active',
        // 전화번호 시스템: 내국인은 PASS 인증 전화번호 → identity_verified
        authPhone: _isKorean ? _passAuthResult!.phone : _phoneController.text.trim(),
        phoneVerificationLevel: _isKorean ? 'identity_verified' : 'otp_verified',
        // USER만 homeRegion 설정 (STEP 3에서 선택), ADMIN은 null
        homeRegion: role == UserRole.USER ? _selectedHomeRegion : null,
      );

      if (!success) {
        if (mounted) {
          final err = userProvider.error;
          ToastHelper.showError((err != null && err.isNotEmpty) ? err : '회원가입에 실패했습니다.');
        }
        return;
      }
      if (!mounted) return;

      // [FOREIGN-IDENTITY-03] 외국인: identity 확정 — HMAC fingerprint 생성 + atomic 중복 차단
      // signUp() 직후, 약관 동의 기록 전에 수행 (already-exists 시 계정 롤백 + 조기 반환)
      if (!_isKorean) {
        final rawForeignId = '${_residentNumber1Controller.text}${_residentNumber2Controller.text}';
        final finalizeErr = await AuthService().finalizeForeignIdentity(rawForeignId);
        if (!mounted) return;
        if (finalizeErr != null) {
          // already-exists: finalizeForeignIdentity 내부에서 Auth+Firestore 롤백 완료
          ToastHelper.showError(finalizeErr);
          setState(() => _isSubmitting = false);
          return;
        }
      }

      // [NATIVE-IDENTITY-03] 내국인: identity 확정 + passToken 소비 (FAIL-CLOSE)
      // 약관 동의 기록 전 수행 — 실패 시 rollback으로 users 문서 삭제 → consent 자동 정리
      // already-exists: finalizeNativeIdentity 내부에서 Auth+Firestore 롤백 완료
      if (_isKorean && _passAuthResult != null) {
        final finalizeErr = await AuthService().finalizeNativeIdentity(_passAuthResult!.passToken);
        if (!mounted) return;
        if (finalizeErr != null) {
          ToastHelper.showError(finalizeErr);
          setState(() => _isSubmitting = false);
          return;
        }
      }

      // 동의 일시·버전 CF로 저장 (법적 타임스탬프 서버 발급)
      // [C안 F-01-3] pending 계정은 userProvider._currentUser가 null →
      //   Firebase Auth UID 직접 참조 (userProvider.currentUser?.uid는 null 반환)
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid != null && _legalTerms != null) {
        final consentRecord = <String, dynamic>{};
        for (final item in _legalTerms!.activeItems) {
          // [D1] agreedAt/termsConsentAt은 서버에서 설정 — 클라이언트는 agreed+version만 전달
          consentRecord[item.id] = {
            'agreed': _consentMap[item.id] ?? false,
            'version': item.version,
          };
        }
        if (!_isKorean) {
          // [C안] 외국인(pending) 계정은 약관 기록 필수 — 성공 전까지 재시도 다이얼로그
          bool recorded = false;
          while (!recorded) {
            try {
              await FirebaseFunctions.instanceFor(region: 'asia-northeast3')
                  .httpsCallable('callableRecordTermsConsent',
                      options: HttpsCallableOptions(timeout: const Duration(seconds: 10)))
                  .call({'consentRecord': consentRecord});
              recorded = true;
            } catch (_) {
              debugPrint('⚠️ 동의 기록 저장 실패');
              if (!mounted) return;
              final retry = await _showTermsConsentRetryDialog();
              if (!retry) {
                if (mounted) {
                  ToastHelper.showWarning(
                      '약관 동의 기록에 실패했습니다.\n다시 로그인하여 재시도해주세요.');
                }
                return;
              }
            }
          }
        } else {
          // 한국인(active): 약관 기록 실패 허용 (PASS 인증으로 법적 동의 보완)
          try {
            await FirebaseFunctions.instanceFor(region: 'asia-northeast3')
                .httpsCallable('callableRecordTermsConsent',
                    options: HttpsCallableOptions(timeout: const Duration(seconds: 10)))
                .call({'consentRecord': consentRecord});
          } catch (_) {
            debugPrint('⚠️ 동의 기록 저장 실패 (한국인 — 무시)');
          }
        }
      }

      if (!mounted) return;

      // [NATIVE-IDENTITY-03] passVerifiedAt/ciHash는 finalizeNativeIdentity(CF) 완료 후 기록됨.
      // signUp() 내부 _loadUserData()는 finalizeNativeIdentity 이전 실행 → 캐시 갱신 필요.
      if (_isKorean && _passAuthResult != null && mounted) {
        await context.read<UserProvider>().refreshUserData();
      }

      if (!mounted) return;

      AnalyticsService.logSignUp(role.name);
      ToastHelper.showSuccess('가입을 환영합니다!');
      // AuthWrapper가 역할에 맞는 HOME으로 자동 라우팅
      Navigator.of(context).popUntil((route) => route.isFirst);
    } catch (e) {
      debugPrint('❌ 회원가입 실패: $e');
      final errStr = e.toString();
      if (_isKorean &&
          (errStr.contains('deadline-exceeded') ||
              errStr.contains('token-expired') ||
              errStr.contains('passToken'))) {
        if (mounted) setState(() => _passAuthResult = null);
        if (mounted) ToastHelper.showError('본인인증 세션이 만료되었습니다.\n화면 상단의 본인인증을 다시 진행해주세요.');
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
      padding: EdgeInsets.only(top: ResponsiveHelper.spacing(context, 6)),
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: ResponsiveHelper.spacing(context, 10),
          vertical: ResponsiveHelper.spacing(context, 6),
        ),
        decoration: BoxDecoration(
          color: AppColors.successBg,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(children: [
          Icon(Icons.check_circle_outline,
              color: AppColors.successDark,
              size: ResponsiveHelper.iconSize(context, 14)),
          SizedBox(width: ResponsiveHelper.spacing(context, 6)),
          Text('인증 완료',
              style: ResponsiveHelper.smallStyle(context,
                  color: AppColors.successDark, fontWeight: FontWeight.w600)),
          const Spacer(),
          TextButton(
            onPressed: () =>
                _phoneVerifyStatus.value = const _PhoneVerifyStatus(),
            style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
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
  ///     → 사용자 본인인증 완료 (KG이니시스)
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
      } else {
        // 취소 또는 실패 — 이전 인증 결과 초기화 (재시도 시 구 결과 잔류 방지)
        if (_passAuthResult != null) {
          setState(() => _passAuthResult = null);
        }
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
        backgroundColor: Colors.white,
        resizeToAvoidBottomInset: true,
        body: LoadingOverlay(
          isLoading: isProviderLoading || _isSubmitting,
          message: '회원가입 중...',
          child: SafeArea(
            bottom: false,
            child: Column(
              children: [
                _buildHeader(),
                Expanded(
                  child: SingleChildScrollView(
                    controller: _scrollController,
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    padding: EdgeInsets.fromLTRB(
                      ResponsiveHelper.spacing(context, 20),
                      ResponsiveHelper.spacing(context, 16),
                      ResponsiveHelper.spacing(context, 20),
                      ResponsiveHelper.spacing(context, 24),
                    ),
                    child: _buildCurrentStep(),
                  ),
                ),
              ],
            ),
          ),
        ),
        bottomNavigationBar: _buildBottomButton(),
      ),  // Scaffold
    );      // PopScope
  }


  // ============================================================
  // 🔧 헤더, 진행바, 단계 컨텐츠
  // ============================================================

  /// 헤더 — white surface 기반 (REG-2 리디자인)
  /// 기존 파란 그라디언트 헤더를 제거하고 앱 전체 white surface 기준에 맞춤
  Widget _buildHeader() {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        ResponsiveHelper.spacing(context, 4),
        ResponsiveHelper.spacing(context, 6),
        ResponsiveHelper.spacing(context, 20),
        ResponsiveHelper.spacing(context, 12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 뒤로가기 버튼 — 다크 아이콘 (white surface 기준)
          GestureDetector(
            onTap: _onStepCancel,
            child: Padding(
              padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 8)),
              child: Icon(
                Icons.arrow_back,
                color: AppColors.textPrimary,
                size: ResponsiveHelper.iconSize(context, 22),
              ),
            ),
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 2)),
          Padding(
            padding: EdgeInsets.symmetric(
                horizontal: ResponsiveHelper.spacing(context, 8)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '회원가입',
                  style: ResponsiveHelper.titleStyle(context).copyWith(
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                    letterSpacing: 0.2,
                  ),
                ),
                SizedBox(height: ResponsiveHelper.spacing(context, 2)),
                Text(
                  _currentStep == 0
                      ? '이용 방법 선택'
                      : _currentStep == 1
                          ? '기본 정보 입력'
                          : '일자리 시작 설정',
                  style: ResponsiveHelper.smallStyle(context,
                      color: AppColors.textSecondary),
                ),
                SizedBox(height: ResponsiveHelper.spacing(context, 12)),
                // 진행 표시기 — ADMIN: 2단계, USER: 3단계
                if (_selectedRole == UserRole.BUSINESS_ADMIN)
                  Row(
                    children: [
                      _buildProgressSegment(true),
                      SizedBox(width: ResponsiveHelper.spacing(context, 5)),
                      _buildProgressSegment(_currentStep >= 1),
                    ],
                  )
                else
                  Row(
                    children: [
                      _buildProgressSegment(true),
                      SizedBox(width: ResponsiveHelper.spacing(context, 5)),
                      _buildProgressSegment(_currentStep >= 1),
                      SizedBox(width: ResponsiveHelper.spacing(context, 5)),
                      _buildProgressSegment(_currentStep >= 2),
                    ],
                  ),
              ],
            ),
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
              ? Theme.of(context).primaryColor
              : AppColors.grey200,
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
        // USER 전용: 주로 일할 지역 + 약관 (ADMIN은 step 2에 도달하지 않음)
        return _buildStep3UserStart();
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

          // [V3 FOREIGN-DOCUMENT-FIRST] 외국인: Document-First 전용 안내 카드
          if (!_isKorean) ...[
            _buildForeignDocumentCard(),
          ] else ...[

          // ── 기본 정보 카드 (이름 + 아이디 + 주민번호/PASS) ── (내국인 전용)
          _buildSectionLabel('기본 정보', Icons.person_outline),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: CommonWidgets.compactCardDecoration(borderOnly: true),
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
                      if (value.length > 20) return '아이디는 20자 이하로 입력해주세요';
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

                // 내국인: 본인인증 버튼 → 완료 시 결과 표시 (이름/성별/생년월일/전화번호)
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

              ],
            ),
          ),

          const SizedBox(height: 20),

          // ── 연락처 카드 ──
          _buildSectionLabel('연락처', Icons.contact_phone_outlined),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: CommonWidgets.compactCardDecoration(borderOnly: true),
            child: Column(
              children: [
                // 내국인: PASS에서 받아온 전화번호 (읽기 전용)
                if (_isKorean)
                  CommonWidgets.textField(
                    context: context,
                    controller: _phoneController,
                    label: '전화번호',
                    hint: '본인인증 후 자동 입력',
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
                          if (mounted) _passwordFocus.requestFocus();
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

          // ── 비밀번호 카드 ──
          _buildSectionLabel('비밀번호', Icons.lock_outline),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: CommonWidgets.compactCardDecoration(borderOnly: true),
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

          // ── 약관 동의 — ADMIN 전용 (USER는 STEP 3에서 처리) ──
          if (_selectedRole == UserRole.BUSINESS_ADMIN) ...[
            ValueListenableBuilder<Map<String, bool>>(
              valueListenable: _consentNotifier,
              builder: (context, _, __) => _buildConsentSection(),
            ),
            const SizedBox(height: 8),
          ],

          ], // else (!_isKorean 분기 종료)
        ],
      ),
    );
  }

  /// [V3 FOREIGN-DOCUMENT-FIRST] 외국인 전용 가입 안내 카드
  Widget _buildForeignDocumentCard() {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 안내 카드
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                theme.colorScheme.primary.withValues(alpha: 0.08),
                theme.colorScheme.primary.withValues(alpha: 0.02),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: theme.colorScheme.primary.withValues(alpha: 0.25)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.credit_card, color: theme.colorScheme.primary, size: 22),
                ),
                const SizedBox(width: 10),
                Text(
                  '외국인등록증으로 간편 가입',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ]),
              const SizedBox(height: 14),
              _buildForeignStep(icon: Icons.camera_alt_outlined, text: '외국인등록증을 촬영하거나 이미지를 선택'),
              const SizedBox(height: 6),
              _buildForeignStep(icon: Icons.auto_fix_high, text: 'OCR로 성명·번호·체류자격 자동 인식'),
              const SizedBox(height: 6),
              _buildForeignStep(icon: Icons.edit_note, text: '인식된 내용을 직접 확인하고 수정'),
              const SizedBox(height: 6),
              _buildForeignStep(icon: Icons.check_circle_outline, text: '약관 동의 후 즉시 이용 가능'),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.grey50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Icon(Icons.info_outline, size: 14, color: AppColors.grey500),
                  const SizedBox(width: 6),
                  Expanded(child: Text(
                    'OCR은 입력 보조 수단입니다. 신분증 진위 확인이나 취업 자격 인증과 무관합니다.',
                    style: ResponsiveHelper.tinyStyle(context, color: AppColors.grey600),
                  )),
                ]),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        // 가입 시작 버튼
        SizedBox(
          width: double.infinity,
          height: 50,
          child: ElevatedButton.icon(
            onPressed: _selectedRole == null ? null : () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ForeignRegisterScreen(role: _selectedRole!),
                ),
              );
            },
            icon: const Icon(Icons.arrow_forward),
            label: const Text('외국인 가입 시작', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            style: ElevatedButton.styleFrom(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
        if (_selectedRole == null) ...[
          const SizedBox(height: 10),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            const Icon(Icons.arrow_upward, size: 14, color: AppColors.grey500),
            const SizedBox(width: 4),
            Text('이전 화면에서 이용 방법을 먼저 선택해주세요',
                style: ResponsiveHelper.tinyStyle(context, color: AppColors.grey500)),
          ]),
        ],
      ],
    );
  }

  Widget _buildForeignStep({required IconData icon, required String text}) {
    return Row(children: [
      Icon(icon, size: 15, color: AppColors.grey500),
      const SizedBox(width: 8),
      Flexible(child: Text(text, style: ResponsiveHelper.smallStyle(context, color: AppColors.grey700))),
    ]);
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

  /// [C안 F-01-3] 약관 동의 기록 실패 시 재시도 다이얼로그
  /// returns true = 재시도, false = 포기
  Future<bool> _showTermsConsentRetryDialog() async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false, // 반드시 선택 필요 (CLAUDE.md: showDialog는 barrierDismissible:false 필수)
      builder: (ctx) => AlertDialog(
        title: const Text('약관 동의 기록 실패'),
        content: const Text(
          '서버와 통신 중 오류가 발생했습니다.\n'
          '약관 동의 기록은 가입 완료에 필수입니다.\n\n'
          '다시 시도하시겠습니까?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('포기'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('다시 시도'),
          ),
        ],
      ),
    );
    return result ?? false;
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
        builder: (_) => TermsViewerScreen(item: item),
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
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Progress bar 아래 ~ 질문 위: 의도적 여백 — 상하 visual balance 확보
        SizedBox(height: ResponsiveHelper.spacing(context, 20)),
        Text(
          '어떻게 이용하시나요?',
          style: ResponsiveHelper.titleStyle(context).copyWith(
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimary,
            letterSpacing: 0.1,
          ),
        ),
        SizedBox(height: ResponsiveHelper.spacing(context, 6)),
        Text(
          '이용 방법에 따라 필요한 정보만 받을게요.',
          style: ResponsiveHelper.bodyStyle(context, color: AppColors.textSecondary),
        ),
        SizedBox(height: ResponsiveHelper.spacing(context, 28)),
        _buildRoleCard(
          role: UserRole.USER,
          icon: Icons.person_outline,
          title: '지원자로 이용',
          description: '원하는 날짜의 일자리에 지원하고 일정을 관리해요.',
        ),
        // 두 카드는 하나의 질문에 대한 답변 — 독립 메뉴가 아니므로 간격 축소
        SizedBox(height: ResponsiveHelper.spacing(context, 7)),
        _buildRoleCard(
          role: UserRole.BUSINESS_ADMIN,
          icon: Icons.business_center_outlined,
          title: '사업장 관리자로 이용',
          description: '공고를 등록하고 지원자를 관리해요.',
        ),
      ],
    );
  }
  // ============================================================
  // 📝 Step 3 (USER 전용): 일자리 시작 설정
  // ============================================================

  /// USER STEP 3: 주로 일할 지역(필수) + 약관 동의
  /// ADMIN은 이 단계에 도달하지 않음 (STEP 2에서 바로 가입 처리)
  /// USER STEP 3: 주로 일할 지역(필수) + 약관 동의
  /// [REG-3] 배너 제거 → STEP 1/2와 동일한 단순·직관적 디자인 언어 적용
  /// ADMIN은 이 단계에 도달하지 않음 (STEP 2에서 바로 가입 처리)
  Widget _buildStep3UserStart() {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── 페이지 카피 — STEP 1/2와 동일한 구조 ──
        SizedBox(height: ResponsiveHelper.spacing(context, 20)),
        Text(
          '어디에서 일하고 싶으세요?',
          style: ResponsiveHelper.titleStyle(context).copyWith(
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimary,
            letterSpacing: 0.1,
          ),
        ),
        SizedBox(height: ResponsiveHelper.spacing(context, 6)),
        Text(
          '선택한 지역의 일자리를 먼저 보여드려요.',
          style: ResponsiveHelper.bodyStyle(context, color: AppColors.textSecondary),
        ),
        SizedBox(height: ResponsiveHelper.spacing(context, 28)),

        // ── 주로 일할 지역 (필수) ──
        _buildSectionLabel('주로 일할 지역', Icons.location_on_outlined),
        GestureDetector(
          onTap: _pickHomeRegion,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            decoration: CommonWidgets.compactCardDecoration(borderOnly: true),
            child: Row(
              children: [
                Icon(
                  Icons.map_outlined,
                  size: ResponsiveHelper.iconSize(context, 20),
                  color: _selectedHomeRegion != null ? theme.primaryColor : AppColors.grey400,
                ),
                SizedBox(width: ResponsiveHelper.spacing(context, 12)),
                Expanded(
                  child: Text(
                    _selectedHomeRegion != null
                        ? '${_selectedHomeRegion!.province ?? ''} ${_selectedHomeRegion!.city}'.trim()
                        : '지역을 선택해주세요',
                    style: ResponsiveHelper.bodyStyle(
                      context,
                      color: _selectedHomeRegion != null
                          ? AppColors.textPrimary
                          : AppColors.grey400,
                    ),
                  ),
                ),
                Icon(Icons.chevron_right,
                    size: ResponsiveHelper.iconSize(context, 20),
                    color: AppColors.grey400),
              ],
            ),
          ),
        ),
        Padding(
          padding: EdgeInsets.only(
            top: ResponsiveHelper.spacing(context, 6),
            left: ResponsiveHelper.spacing(context, 4),
          ),
          child: Text(
            '가입 후 MY에서 언제든 변경할 수 있어요.',
            style: ResponsiveHelper.tinyStyle(context, color: AppColors.grey400),
          ),
        ),

        const SizedBox(height: 24),

        // ── 약관 동의 ──
        ValueListenableBuilder<Map<String, bool>>(
          valueListenable: _consentNotifier,
          builder: (context, _, __) => _buildConsentSection(),
        ),

        const SizedBox(height: 8),
      ],
    );
  }


  /// 역할 선택 카드 (REG-2 리디자인 v2)
  /// - 태그·체크리스트 완전 제거: 아이콘 + 제목 + 설명 1줄
  /// - 선택 색상: 앱 primary #1565C0 통일 (per-role 색상 없음)
  /// - white surface, neutral border, 과도한 shadow 없음
  Widget _buildRoleCard({
    required UserRole role,
    required IconData icon,
    required String title,
    required String description,
  }) {
    final isSelected = _selectedRole == role;
    final primary = Theme.of(context).primaryColor; // #1565C0

    return InkWell(
      onTap: () => setState(() {
        if (_selectedRole == role) return;
        _selectedRole = role;
        // 역할 변경 시 인증 상태 초기화 — 이전 역할 기준 인증 결과가 재사용되는 것 방지
        _passAuthResult = null;
        _phoneVerifyStatus.value = const _PhoneVerifyStatus();
        _phoneController.clear();
      }),
      borderRadius: BorderRadius.circular(14),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        padding: EdgeInsets.symmetric(
          horizontal: ResponsiveHelper.spacing(context, 16),
          vertical: ResponsiveHelper.spacing(context, 14),
        ),
        decoration: BoxDecoration(
          color: isSelected ? primary.withValues(alpha: 0.08) : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected ? primary : AppColors.grey300,
            width: isSelected ? 2.0 : 1.0,
          ),
        ),
        child: Row(
          children: [
            // 아이콘
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: isSelected
                    ? primary.withValues(alpha: 0.10)
                    : AppColors.grey100,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                icon,
                color: isSelected ? primary : AppColors.grey600,
                size: 22,
              ),
            ),
            SizedBox(width: ResponsiveHelper.spacing(context, 14)),
            // 제목 + 설명
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: ResponsiveHelper.bodyStyle(context).copyWith(
                      color: isSelected ? primary : AppColors.textPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  SizedBox(height: ResponsiveHelper.spacing(context, 3)),
                  Text(
                    description,
                    style: ResponsiveHelper.smallStyle(
                      context,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            // 선택 상태에만 check icon 표시 — 미선택 시 아이콘 없음, 텍스트 영역 자연 확장
            if (isSelected) ...[
              SizedBox(width: ResponsiveHelper.spacing(context, 10)),
              Icon(
                Icons.check_rounded,
                color: primary,
                size: 20,
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// 하단 버튼
  Widget _buildBottomButton() {
    final theme = Theme.of(context);
    // Step 0: 역할 미선택 → 시각적 비활성화 (_validateStep2 toast 대신 버튼 자체 disable)
    // Step 1: 항상 활성 (내부 검증은 _onStepContinue → _validateStep1 처리)
    // Step 2 (USER 전용): 지역 미선택 → 비활성화 (필수 항목이므로 선택 전 진행 불가)
    final isDisabled = _isSubmitting ||
        (_currentStep == 0 && _selectedRole == null) ||
        (_currentStep == 2 && _selectedHomeRegion == null);
    return SafeArea(
      top: false,
      child: Padding(
      padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 16)),
      child: ElevatedButton(
        onPressed: isDisabled ? null : _onStepContinue,
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
                  ? (_selectedRole == UserRole.BUSINESS_ADMIN ? '완료' : '다음')
                  : '가입 완료',
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

// _TermsViewerScreen → lib/widgets/auth/terms_viewer_screen.dart (TermsViewerScreen)으로 추출됨

