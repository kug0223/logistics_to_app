import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_auth/firebase_auth.dart' show FirebaseAuth;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_storage/firebase_storage.dart';

import '../../models/core/user_model.dart';
import '../../models/core/legal_terms_model.dart';
import '../../models/core/user_region.dart';
import '../../providers/user_provider.dart';
import '../../services/auth_service.dart';
import '../../services/firestore_service.dart';
import '../../services/foreign_id_ocr_service.dart';
import '../../services/legal_terms_service.dart';
import '../../services/phone_verification_service.dart';
import '../../utils/responsive_helper.dart';
import '../../utils/toast_helper.dart';
import '../../utils/dialog_helper.dart';
import '../../widgets/common/common_widgets.dart';
import '../../widgets/inputs/home_region_picker_sheet.dart';
import '../../theme/app_colors.dart';

/// V3 외국인 Document-First 회원가입 마법사
///
/// [PRODUCT-POLICY]
///   OCR = 입력 보조수단. "외국인등록증 진위확인/취업자격 인증"이 아님.
///   OCR 실패 시 수동 입력으로 대체 — 가입 차단 없음.
///   legalName / koreanName / accountHolder 는 완전 독립된 개념.
///   rawForeignId 13자리 평문은 Firestore 영구 저장 금지.
///
/// [RESUME MODE] isResume: true
///   RegistrationRecoveryScreen에서 registration_pending 계정 복구 시 진입.
///   - 새 Auth 계정 생성 금지 — FirebaseAuth.currentUser.uid 그대로 사용
///   - users/{uid} 문서 초기화 금지 — userProvider.signUp() 호출 안 함
///   - documentScan 단계부터 시작 (basicInfo/phone 건너뜀)
///   - _processRegistration() 내에서 fingerprint 여부를 Firestore로 확인 후
///     미완료 단계(finalizeForeignIdentity / markIdCardVerified)만 선택적으로 실행
class ForeignRegisterScreen extends StatefulWidget {
  final UserRole role;

  /// true = RegistrationRecoveryScreen에서 진입 (registration_pending 복구)
  /// false = 신규 가입 (기본값)
  final bool isResume;

  /// [CASE C] fingerprint 없음 + 기존 idCard 있음 → Storage 파일 재사용 시도
  /// - 경로가 있으면: Storage 다운로드 → OCR 재실행 → ocrConfirm 단계로 바로 이동
  /// - 경로가 없거나 다운로드 실패 시: documentScan 단계에서 재촬영 요청
  /// - null이면 CASE B/D (idCard 없음) → documentScan에서 신규 촬영/선택
  final String? existingIdCardPath;

  const ForeignRegisterScreen({
    super.key,
    required this.role,
    this.isResume = false,
    this.existingIdCardPath,
  });

  @override
  State<ForeignRegisterScreen> createState() => _ForeignRegisterScreenState();
}

/// 마법사 단계
enum _Step {
  basicInfo,    // 0: 아이디·비밀번호
  phone,        // 1: 휴대폰 OTP 인증
  documentScan, // 2: 외국인등록증 촬영/선택 → OCR
  ocrConfirm,   // 3: OCR 결과 확인·수정
  terms,        // 4: 약관 동의
  homeRegion,   // 5: 주로 일할 지역 (USER 전용)
}

class _ForeignRegisterScreenState extends State<ForeignRegisterScreen> {
  static final _usernameRe = RegExp(r'^[a-z0-9_]+$');
  static final _foreignId13Re = RegExp(r'^\d{13}$');

  final LegalTermsService _legalTermsService = LegalTermsService();
  final PhoneVerificationService _phoneSvc = PhoneVerificationService();
  final ScrollController _scrollCtrl = ScrollController();

  _Step _step = _Step.basicInfo;
  bool _isBusy = false;

  // ── Step 0: 기본 정보 ──────────────────────────────────────────
  final _formKey = GlobalKey<FormState>();
  final _usernameCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmCtrl  = TextEditingController();
  bool _obscurePass = true;
  bool _obscureConfirm = true;
  bool _usernameAvailable = false;
  bool _usernameChecking = false;

  // ── Step 1: 휴대폰 인증 ───────────────────────────────────────
  final _phoneCtrl = TextEditingController();
  final _codeCtrl  = TextEditingController();
  bool _codeSent = false;
  bool _phoneVerified = false;
  bool _codeSending = false;
  bool _codeVerifying = false;
  String? _phoneError;

  // ── Step 2: 문서 스캔 ─────────────────────────────────────────
  String? _imagePath; // 로컬 임시 파일 경로 (OCR 후 업로드까지 유지)
  bool _ocrRunning = false;

  /// [CASE C] 기존 Storage idCard를 재사용 중 — 재업로드 / markIdCardVerified 불필요
  bool _usingExistingIdCard = false;

  // ── Step 3: OCR 확인 ─────────────────────────────────────────
  ForeignIdOcrResult? _ocrResult;
  final _legalNameCtrl      = TextEditingController();
  final _rawForeignIdCtrl   = TextEditingController(); // 13자리 평문
  final _visaTypeCtrl       = TextEditingController();
  final _stayExpiryCtrl     = TextEditingController(); // YYYY-MM-DD
  final _koreanNameCtrl     = TextEditingController();
  final _ocrFormKey = GlobalKey<FormState>();

  // ── Step 4: 약관 동의 ─────────────────────────────────────────
  LegalTerms? _legalTerms;
  bool _termsLoading = false;
  final _consentMap = <String, bool>{};
  final _viewedIds  = <String>{};

  // ── Step 5: 주로 일할 지역 ────────────────────────────────────
  UserRegion? _homeRegion;

  @override
  void initState() {
    super.initState();
    _loadTerms();
    // [RESUME MODE] basicInfo / phone 건너뜀 — documentScan부터 시작
    if (widget.isResume) {
      _step = _Step.documentScan;
      _phoneVerified = true; // 이미 가입 시 검증된 번호

      // [CASE C] 기존 idCard 재사용 시도 — Storage 다운로드 → OCR → ocrConfirm 이동
      // existingIdCardPath가 있으면 먼저 재사용 시도, 실패 시 documentScan 유지
      if (widget.existingIdCardPath != null) {
        _ocrRunning = true; // documentScan 로딩 표시
        _tryReuseExistingIdCard(widget.existingIdCardPath!);
      }
    }
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    _usernameCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmCtrl.dispose();
    _phoneCtrl.dispose();
    _codeCtrl.dispose();
    _legalNameCtrl.dispose();
    _rawForeignIdCtrl.dispose();
    _visaTypeCtrl.dispose();
    _stayExpiryCtrl.dispose();
    _koreanNameCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadTerms() async {
    setState(() => _termsLoading = true);
    try {
      final terms = await _legalTermsService.getTerms();
      if (!mounted) return;
      setState(() {
        _legalTerms = terms;
        for (final item in terms.activeItems) {
          _consentMap[item.id] = false;
        }
        _termsLoading = false;
      });
    } catch (e) {
      debugPrint('⚠️ [ForeignReg] 약관 로드 실패, 기본값 사용: $e');
      if (!mounted) return;
      final defaults = LegalTerms.defaultTerms();
      setState(() {
        _legalTerms = defaults;
        for (final item in defaults.activeItems) {
          _consentMap[item.id] = false;
        }
        _termsLoading = false;
      });
    }
  }

  // ============================================================
  // 탐색 헬퍼
  // ============================================================

  void _goTo(_Step step) {
    setState(() => _step = step);
    Future.microtask(() {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(0, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
      }
    });
  }

  void _handleBack() {
    // [RESUME MODE] documentScan이 첫 단계 → pop으로 RecoveryScreen 복귀
    if (widget.isResume && _step == _Step.documentScan) {
      Navigator.pop(context);
      return;
    }
    if (_step.index > 0) {
      _goTo(_Step.values[_step.index - 1]);
    } else {
      Navigator.pop(context);
    }
  }

  // ============================================================
  // Step 0: 기본 정보 유효성
  // ============================================================

  Future<void> _checkUsername() async {
    final username = _usernameCtrl.text.trim();
    if (username.length < 4) return;
    setState(() { _usernameChecking = true; _usernameAvailable = false; });
    final exists = await AuthService().checkUsernameExists(username);
    if (!mounted) return;
    setState(() {
      _usernameChecking = false;
      _usernameAvailable = !exists;
    });
    if (exists) ToastHelper.showError('이미 사용중인 아이디입니다');
  }

  bool _validateBasicInfo() {
    if (!(_formKey.currentState?.validate() ?? false)) return false;
    if (!_usernameAvailable) {
      ToastHelper.showWarning('아이디 중복 확인을 해주세요');
      return false;
    }
    return true;
  }

  // ============================================================
  // Step 1: 휴대폰 인증
  // ============================================================

  Future<void> _sendCode() async {
    if (_codeSending) return;
    final phone = _phoneCtrl.text.trim();
    if (phone.length < 10) {
      setState(() => _phoneError = '올바른 휴대폰 번호를 입력해주세요');
      return;
    }
    setState(() { _codeSending = true; _phoneError = null; });
    try {
      await _phoneSvc.sendCode(phone);
      if (!mounted) return;
      setState(() { _codeSent = true; _codeSending = false; _codeCtrl.clear(); });
      ToastHelper.showSuccess('인증번호가 발송되었습니다');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _codeSending = false;
        _phoneError = '발송에 실패했습니다. 다시 시도해주세요';
      });
    }
  }

  Future<void> _verifyCode() async {
    if (_codeVerifying) return;
    final code = _codeCtrl.text.trim();
    if (code.length != 6) return;
    setState(() { _codeVerifying = true; _phoneError = null; });
    try {
      final result = await _phoneSvc.verifyCode(_phoneCtrl.text.trim(), code);
      if (!mounted) return;
      if (result.valid) {
        setState(() { _phoneVerified = true; _codeVerifying = false; });
        ToastHelper.showSuccess('휴대폰 인증이 완료되었습니다');
      } else {
        final msg = switch (result.reason) {
          'expired' => '인증번호가 만료됐습니다. 재발송해주세요',
          'too_many_attempts' => '시도 횟수를 초과했습니다. 재발송해주세요',
          _ => '인증번호가 일치하지 않습니다',
        };
        setState(() { _codeVerifying = false; _phoneError = msg; });
        ToastHelper.showError(msg);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() { _codeVerifying = false; _phoneError = '확인에 실패했습니다. 다시 시도해주세요'; });
    }
  }

  bool _validatePhone() {
    if (!_phoneVerified) {
      ToastHelper.showWarning('휴대폰 번호 인증을 완료해주세요');
      return false;
    }
    return true;
  }

  // ============================================================
  // [CASE C] 기존 Storage idCard 재사용 — Storage 다운로드 → OCR → ocrConfirm
  // ============================================================

  /// [CASE C] fingerprint 없음 + 기존 idCard 있음 복구 시 호출.
  /// Storage 파일이 실제 존재하고 OCR이 성공하면 ocrConfirm 단계로 이동.
  /// 실패 시 documentScan 유지 — 사용자가 직접 재촬영.
  Future<void> _tryReuseExistingIdCard(String storagePath) async {
    String? tempFilePath;
    try {
      // ① Storage에서 bytes 다운로드 (max 10MB)
      final bytes = await FirebaseStorage.instance
          .ref(storagePath)
          .getData(10 * 1024 * 1024);

      if (bytes == null || !mounted) {
        if (mounted) setState(() => _ocrRunning = false);
        return;
      }

      // ② 임시 파일 저장 (OCR용 — 업로드 재사용 안 함)
      final dir = await getTemporaryDirectory();
      final ts = DateTime.now().millisecondsSinceEpoch;
      final tempFile = File('${dir.path}/idCard_resume_$ts.jpg');
      await tempFile.writeAsBytes(bytes);
      tempFilePath = tempFile.path;

      // ③ OCR 실행
      final result = await ForeignIdOcrService.recognizeFromPath(tempFile.path);

      if (!mounted) return;

      // ④ OCR 결과로 폼 초기화 (실패 필드는 '직접 입력 필요' 표시)
      _ocrResult = result;
      _legalNameCtrl.text = result.legalName ?? '';
      _rawForeignIdCtrl.text = result.foreignIdRaw ?? '';
      _visaTypeCtrl.text = result.visaType ?? '';
      _stayExpiryCtrl.text = result.stayExpiryDate ?? '';
      _koreanNameCtrl.clear();
      _imagePath = null;          // 재업로드 없음
      _usingExistingIdCard = true;

      setState(() {
        _ocrRunning = false;
        _step = _Step.ocrConfirm;
      });

      debugPrint('✅ [ForeignReg CASE C] 기존 idCard 재사용 성공 → ocrConfirm');
    } catch (e) {
      debugPrint('⚠️ [ForeignReg CASE C] 기존 idCard 재사용 실패 → documentScan 유지: $e');
      if (mounted) setState(() => _ocrRunning = false);
      // documentScan 단계 유지 — 사용자가 직접 재촬영
    } finally {
      // 임시 파일 정리 (OCR 전용, 업로드하지 않음)
      if (tempFilePath != null) {
        try { await File(tempFilePath).delete(); } catch (_) {}
      }
    }
  }

  // ============================================================
  // Step 2: 문서 스캔 + OCR
  // ============================================================

  Future<void> _pickAndOcr(ImageSource source) async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: source, imageQuality: 90, maxWidth: 2000);
    if (picked == null || !mounted) return;

    setState(() { _ocrRunning = true; });

    try {
      final result = await ForeignIdOcrService.recognizeFromPath(picked.path);
      if (!mounted) return;

      // OCR 결과로 확인 폼 초기화
      _ocrResult = result;
      _legalNameCtrl.text = result.legalName ?? '';
      _rawForeignIdCtrl.text = result.foreignIdRaw ?? '';
      _visaTypeCtrl.text = result.visaType ?? '';
      _stayExpiryCtrl.text = result.stayExpiryDate ?? '';
      _koreanNameCtrl.clear();
      _imagePath = picked.path;

      setState(() => _ocrRunning = false);
      _goTo(_Step.ocrConfirm);
    } catch (e) {
      debugPrint('❌ [ForeignReg] OCR 실패: $e');
      if (!mounted) return;
      // OCR 예외 → 모든 필드 수동 입력 허용
      _ocrResult = const ForeignIdOcrResult(
        legalNameFailed: true, foreignIdFailed: true, visaTypeFailed: true, stayExpiryFailed: true,
      );
      _legalNameCtrl.clear();
      _rawForeignIdCtrl.clear();
      _visaTypeCtrl.clear();
      _stayExpiryCtrl.clear();
      _imagePath = picked.path;

      setState(() { _ocrRunning = false; });
      _goTo(_Step.ocrConfirm);
    }
  }

  // ============================================================
  // Step 3: OCR 확인 유효성
  // ============================================================

  bool _validateOcrConfirm() {
    if (!(_ocrFormKey.currentState?.validate() ?? false)) return false;
    // rawForeignId 13자리 숫자 필수
    final id = _rawForeignIdCtrl.text.trim().replaceAll(RegExp(r'\D'), '');
    if (!_foreignId13Re.hasMatch(id)) {
      ToastHelper.showWarning('외국인등록번호 13자리를 확인해주세요');
      return false;
    }
    // 외국인 뒷자리 첫 번째 자리: 5~8
    final genderDigit = int.tryParse(id[6]);
    if (genderDigit == null || genderDigit < 5 || genderDigit > 8) {
      ToastHelper.showWarning('외국인등록번호 뒷자리 첫 번째 숫자가 올바르지 않습니다 (5~8)');
      return false;
    }
    if (_legalNameCtrl.text.trim().isEmpty) {
      ToastHelper.showWarning('성명을 입력해주세요');
      return false;
    }
    return true;
  }

  // ============================================================
  // Step 3 → Step 4: 계정 생성 + 업로드 + finalize + markId
  // ============================================================

  Future<void> _processRegistration() async {
    if (_isBusy) return;
    setState(() => _isBusy = true);

    final rawId = _rawForeignIdCtrl.text.trim().replaceAll(RegExp(r'\D'), '');
    final legalName = _legalNameCtrl.text.trim();
    final visaType = _visaTypeCtrl.text.trim();
    final stayExpiry = _stayExpiryCtrl.text.trim();
    final imagePath = _imagePath;

    // ================================================================
    // [RESUME MODE] 기존 uid 유지 — 새 Auth 계정 생성 금지
    // ================================================================
    if (widget.isResume) {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) {
        setState(() => _isBusy = false);
        ToastHelper.showError('세션이 만료되었습니다. 다시 로그인해주세요.');
        return;
      }

      // ── ① 외국인등록증 이미지 업로드 ─────────────────────────────
      // [CASE C] _usingExistingIdCard == true → 기존 Storage 파일 재사용
      //   isIdVerified = true 이미 설정됨 → 업로드·markIdCardVerified 불필요
      // [CASE B/D] _usingExistingIdCard == false → 새 이미지 업로드
      String? uploadedPath;
      if (!_usingExistingIdCard && imagePath != null) {
        try {
          final ts = DateTime.now().millisecondsSinceEpoch;
          final storagePath = 'users/$uid/idCard_$ts.jpg';
          final ref = FirebaseStorage.instance.ref(storagePath);
          await ref.putFile(File(imagePath));
          uploadedPath = storagePath;
        } catch (e) {
          debugPrint('⚠️ [ForeignReg resume] 이미지 업로드 실패: $e');
        }
      }

      // ── ② Firestore에서 fingerprint 존재 여부 확인 ───────────────
      //    fingerprint가 없으면 finalizeForeignIdentity 호출
      //    fingerprint가 있으면 이미 완료 — skip (idempotent 보장)
      bool hasFingerprint = false;
      try {
        final docSnap = await FirebaseFirestore.instance
            .collection('users').doc(uid).get();
        hasFingerprint = docSnap.data()?['foreignIdentityFingerprint'] != null;
      } catch (e) {
        debugPrint('⚠️ [ForeignReg resume] Firestore 읽기 실패 — finalize 시도: $e');
        // 읽기 실패 시 finalize 호출로 폴백 (CF 내부에서 중복 방지)
      }

      if (!mounted) return;

      if (!hasFingerprint) {
        final finalizeErr = await AuthService().finalizeForeignIdentity(
          rawId,
          legalName: legalName.isNotEmpty ? legalName : null,
          visaType: visaType.isNotEmpty ? visaType : null,
          stayExpiryDate: stayExpiry.isNotEmpty ? stayExpiry : null,
        );
        if (!mounted) return;
        if (finalizeErr != null) {
          setState(() => _isBusy = false);
          ToastHelper.showError(finalizeErr);
          return;
        }
      }

      // ── ③ callableMarkIdCardVerified (이미 있으면 CF가 갱신) ──────
      if (uploadedPath != null) {
        try {
          await FirebaseFunctions.instanceFor(region: 'asia-northeast3')
              .httpsCallable('callableMarkIdCardVerified',
                  options: HttpsCallableOptions(timeout: const Duration(seconds: 15)))
              .call({'storagePath': uploadedPath});
        } catch (e) {
          debugPrint('⚠️ [ForeignReg resume] markIdCardVerified 실패 (재시도 가능): $e');
        }
      }

      // 임시 파일 정리 ([CASE C] _usingExistingIdCard 시 임시파일 없음 — _tryReuseExistingIdCard에서 정리 완료)
      if (!_usingExistingIdCard && imagePath != null) {
        try { await File(imagePath).delete(); } catch (_) {}
      }

      // [V3 BUG-FIX] koreanName 저장 — isResume 흐름에서 signUp()을 호출하지 않으므로
      //   koreanName이 Firestore에 기록되지 않는 누락 버그 수정.
      //   displayName getter(koreanName ?? legalName ?? name)가 올바르게 동작하려면 필수.
      final koreanNameResume = _koreanNameCtrl.text.trim();
      if (koreanNameResume.isNotEmpty) {
        try {
          await FirebaseFirestore.instance
              .collection('users').doc(uid).update({'koreanName': koreanNameResume});
        } catch (e) {
          debugPrint('⚠️ [ForeignReg resume] koreanName 저장 실패 (치명적 아님): $e');
        }
      }

      if (!mounted) return;
      setState(() => _isBusy = false);
      _goTo(_Step.terms);
      return;
    }

    // ================================================================
    // [신규 가입 흐름] — isResume == false
    // ================================================================

    final userProvider = context.read<UserProvider>();
    final role = widget.role;
    final koreanName = _koreanNameCtrl.text.trim();
    final phone = _phoneCtrl.text.trim();

    // ── 사전 중복 체크 (UX용, atomic 체크는 finalize에서) ──────────
    try {
      final exists = await AuthService().precheckForeignIdentity(rawId, role);
      if (!mounted) return;
      if (exists) {
        setState(() => _isBusy = false);
        ToastHelper.showError('이미 동일 역할로 가입된 외국인등록번호입니다.');
        return;
      }
    } catch (_) { /* 사전 체크 실패 무시 — finalize에서 재확인 */ }

    // ── 계정 생성 ─────────────────────────────────────────────────
    final effectiveName = koreanName.isNotEmpty ? koreanName : legalName;
    final sentinelId = '${rawId.substring(0, 6)}-${rawId[6]}${'*' * 6}';

    final success = await userProvider.signUp(
      username: _usernameCtrl.text.trim(),
      password: _passwordCtrl.text,
      name: effectiveName,
      phone: phone,
      role: role,
      gender: null,       // V3: 서버가 rawForeignId에서 계산
      birthDate: null,    // V3: 서버가 rawForeignId에서 계산
      residentNumber: null,
      foreignIdNumber: sentinelId,
      accountStatus: 'registration_pending',
      authPhone: phone,
      phoneVerificationLevel: 'otp_verified',
      homeRegion: null,   // 나중에 recordTermsConsent 전에 설정
    );
    if (!mounted) return;
    if (!success) {
      setState(() => _isBusy = false);
      final err = userProvider.error;
      ToastHelper.showError((err != null && err.isNotEmpty) ? err : '계정 생성에 실패했습니다.');
      return;
    }

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      setState(() => _isBusy = false);
      ToastHelper.showError('계정 정보를 확인할 수 없습니다. 다시 시도해주세요.');
      return;
    }

    // ── 외국인등록증 이미지 업로드 ────────────────────────────────
    String? uploadedPath;
    if (imagePath != null) {
      try {
        final ts = DateTime.now().millisecondsSinceEpoch;
        final storagePath = 'users/$uid/idCard_$ts.jpg';
        final ref = FirebaseStorage.instance.ref(storagePath);
        await ref.putFile(File(imagePath));
        uploadedPath = storagePath;
      } catch (e) {
        debugPrint('⚠️ [ForeignReg] 이미지 업로드 실패 (계속): $e');
      }
    }

    // ── finalizeForeignIdentity ───────────────────────────────────
    final finalizeErr = await AuthService().finalizeForeignIdentity(
      rawId,
      legalName: legalName.isNotEmpty ? legalName : null,
      visaType: visaType.isNotEmpty ? visaType : null,
      stayExpiryDate: stayExpiry.isNotEmpty ? stayExpiry : null,
    );
    if (!mounted) return;
    if (finalizeErr != null) {
      setState(() => _isBusy = false);
      ToastHelper.showError(finalizeErr);
      return;
    }

    // ── callableMarkIdCardVerified ────────────────────────────────
    if (uploadedPath != null) {
      try {
        await FirebaseFunctions.instanceFor(region: 'asia-northeast3')
            .httpsCallable('callableMarkIdCardVerified',
                options: HttpsCallableOptions(timeout: const Duration(seconds: 15)))
            .call({'storagePath': uploadedPath});
      } catch (e) {
        debugPrint('⚠️ [ForeignReg] markIdCardVerified 실패 (resume로 재시도 가능): $e');
      }
    }

    // 임시 파일 정리
    if (imagePath != null) {
      try { await File(imagePath).delete(); } catch (_) {}
    }

    if (!mounted) return;
    setState(() => _isBusy = false);
    _goTo(_Step.terms);
  }

  // ============================================================
  // Step 4: 약관 동의 유효성
  // ============================================================

  bool _validateTerms() {
    final required = _legalTerms?.activeItems.where((t) => t.isRequired).toList() ?? [];
    final allAgreed = required.every((t) => _consentMap[t.id] == true);
    if (!allAgreed) {
      ToastHelper.showWarning('필수 약관에 모두 동의해주세요');
      return false;
    }
    return true;
  }

  // ============================================================
  // Step 5 (USER) 또는 최종: recordTermsConsent → active
  // ============================================================

  Future<void> _finalizeRegistration() async {
    if (_isBusy) return;
    setState(() => _isBusy = true);

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      setState(() => _isBusy = false);
      ToastHelper.showError('세션이 만료되었습니다. 다시 로그인해주세요.');
      return;
    }

    // homeRegion 업데이트 (USER 전용) — main.dart와 동일한 직접 Firestore 쓰기 패턴
    if (widget.role == UserRole.USER && _homeRegion != null) {
      try {
        await FirestoreService().updateUserDocument(uid, {'homeRegion': _homeRegion!.toMap()});
      } catch (e) {
        debugPrint('⚠️ [ForeignReg] homeRegion 업데이트 실패 (계속): $e');
      }
    }

    // callableRecordTermsConsent → 4가지 조건 충족 시 CF가 active로 전환
    final consentRecord = <String, dynamic>{};
    for (final item in (_legalTerms?.activeItems ?? [])) {
      consentRecord[item.id] = {
        'agreed': _consentMap[item.id] ?? false,
        'version': item.version,
      };
    }

    bool recorded = false;
    while (!recorded) {
      try {
        await FirebaseFunctions.instanceFor(region: 'asia-northeast3')
            .httpsCallable('callableRecordTermsConsent',
                options: HttpsCallableOptions(timeout: const Duration(seconds: 10)))
            .call({'consentRecord': consentRecord});
        recorded = true;
      } catch (_) {
        if (!mounted) return;
        final retry = await _showTermsRetryDialog();
        if (!retry) {
          ToastHelper.showWarning('약관 동의 기록에 실패했습니다.\n다시 로그인하여 재시도해주세요.');
          setState(() => _isBusy = false);
          return;
        }
      }
    }

    if (!mounted) return;
    await context.read<UserProvider>().refreshUserData();
    if (!mounted) return;

    setState(() => _isBusy = false);
    ToastHelper.showSuccess('가입을 환영합니다!');
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  Future<bool> _showTermsRetryDialog() async {
    final result = await DialogHelper.showSheet<bool>(
      context,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.cloud_off, size: 40, color: AppColors.grey400),
          const SizedBox(height: 16),
          const Text('서버 연결 실패', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 8),
          const Text('약관 동의 기록에 실패했습니다.\n인터넷 연결 후 재시도해주세요.', textAlign: TextAlign.center),
          const SizedBox(height: 24),
          Row(children: [
            Expanded(child: OutlinedButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('취소'),
            )),
            const SizedBox(width: 12),
            Expanded(child: ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('재시도'),
            )),
          ]),
        ]),
      ),
    );
    return result ?? false;
  }

  // ============================================================
  // 다음 버튼 로직
  // ============================================================

  Future<void> _onNext() async {
    switch (_step) {
      case _Step.basicInfo:
        if (_validateBasicInfo()) _goTo(_Step.phone);
      case _Step.phone:
        if (_validatePhone()) _goTo(_Step.documentScan);
      case _Step.documentScan:
        ToastHelper.showWarning('외국인등록증 사진을 먼저 촬영해주세요');
      case _Step.ocrConfirm:
        if (_validateOcrConfirm()) await _processRegistration();
      case _Step.terms:
        if (!_validateTerms()) return;
        if (widget.role == UserRole.USER) {
          _goTo(_Step.homeRegion);
        } else {
          await _finalizeRegistration();
        }
      case _Step.homeRegion:
        if (_homeRegion == null) {
          ToastHelper.showWarning('주로 일할 지역을 선택해주세요');
          return;
        }
        await _finalizeRegistration();
    }
  }

  // ============================================================
  // Build
  // ============================================================

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PopScope(
      // [RESUME MODE] documentScan이 첫 단계 / [신규] basicInfo가 첫 단계
      canPop: widget.isResume
          ? _step == _Step.documentScan
          : _step == _Step.basicInfo,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _handleBack();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.isResume ? '가입 이어서 완료' : '외국인 회원가입'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: _handleBack,
          ),
        ),
        body: Column(children: [
          // 진행 표시줄
          _buildProgressBar(),
          // 내용
          Expanded(
            child: SingleChildScrollView(
              controller: _scrollCtrl,
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
              child: _buildCurrentStep(theme),
            ),
          ),
        ]),
        bottomNavigationBar: SafeArea(
          top: false,
          child: _buildBottomButtons(theme),
        ),
      ),
    );
  }

  Widget _buildProgressBar() {
    final double progress;
    if (widget.isResume) {
      // [RESUME MODE] documentScan(0) → ocrConfirm(1) → terms(2) → [homeRegion(3)]
      final resumeTotal = widget.role == UserRole.USER ? 4 : 3;
      final resumeCurrent = (_step.index - _Step.documentScan.index).clamp(0, resumeTotal);
      progress = (resumeCurrent + 1) / resumeTotal;
    } else {
      final total = widget.role == UserRole.USER ? _Step.values.length : _Step.values.length - 1;
      progress = (_step.index + 1) / total;
    }
    return LinearProgressIndicator(
      value: progress,
      backgroundColor: AppColors.grey100,
      minHeight: 4,
    );
  }

  Widget _buildCurrentStep(ThemeData theme) {
    return switch (_step) {
      _Step.basicInfo    => _buildBasicInfo(theme),
      _Step.phone        => _buildPhone(theme),
      _Step.documentScan => _buildDocumentScan(theme),
      _Step.ocrConfirm   => _buildOcrConfirm(theme),
      _Step.terms        => _buildTerms(theme),
      _Step.homeRegion   => _buildHomeRegion(theme),
    };
  }

  Widget _buildBottomButtons(ThemeData theme) {
    if (_isBusy) {
      return Container(
        padding: const EdgeInsets.all(16),
        child: const Column(mainAxisSize: MainAxisSize.min, children: [
          LinearProgressIndicator(),
          SizedBox(height: 8),
          Text('처리 중...', style: TextStyle(color: AppColors.grey500)),
        ]),
      );
    }
    final isLast = _step == _Step.homeRegion ||
        (_step == _Step.terms && widget.role == UserRole.BUSINESS_ADMIN);
    final isDocScan = _step == _Step.documentScan;

    if (isDocScan) {
      // 문서 스캔 단계는 하단 버튼 없음 (직접 촬영/선택 버튼으로 진행)
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: SizedBox(
        width: double.infinity,
        height: 48,
        child: ElevatedButton(
          onPressed: _onNext,
          child: Text(isLast ? '가입 완료' : '다음'),
        ),
      ),
    );
  }

  // ============================================================
  // Step 화면 구성
  // ============================================================

  Widget _buildBasicInfo(ThemeData theme) {
    return Form(
      key: _formKey,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _buildStepHeader('기본 정보 입력', '아이디와 비밀번호를 설정해주세요'),
        const SizedBox(height: 24),

        // 아이디
        _buildLabel('아이디', Icons.account_circle_outlined),
        CommonWidgets.textField(
          context: context,
          controller: _usernameCtrl,
          label: '아이디',
          hint: '영문소문자·숫자·_ (4~20자)',
          icon: Icons.account_circle_outlined,
          textInputAction: TextInputAction.next,
          onChanged: (_) => setState(() { _usernameAvailable = false; }),
          suffixIcon: _usernameChecking
              ? const SizedBox(width: 20, height: 20, child: Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator(strokeWidth: 2)))
              : _usernameAvailable
                  ? const Icon(Icons.check_circle, color: AppColors.success)
                  : null,
          validator: (v) {
            if (v == null || v.isEmpty) return '아이디를 입력해주세요';
            if (v.length < 4) return '4자 이상 입력해주세요';
            if (v.length > 20) return '20자 이하로 입력해주세요';
            if (!_usernameRe.hasMatch(v)) return '영문 소문자, 숫자, _만 사용 가능';
            if (!_usernameAvailable) return '중복 확인을 해주세요';
            return null;
          },
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            onPressed: _checkUsername,
            child: const Text('아이디 중복 확인'),
          ),
        ),
        const SizedBox(height: 16),

        // 비밀번호
        _buildLabel('비밀번호', Icons.lock_outline),
        CommonWidgets.textField(
          context: context,
          controller: _passwordCtrl,
          label: '비밀번호',
          hint: '영문+숫자+특수문자 8자 이상',
          icon: Icons.lock_outline,
          obscureText: _obscurePass,
          textInputAction: TextInputAction.next,
          suffixIcon: IconButton(
            icon: Icon(_obscurePass ? Icons.visibility_off : Icons.visibility),
            onPressed: () => setState(() => _obscurePass = !_obscurePass),
          ),
          validator: (v) {
            if (v == null || v.isEmpty) return '비밀번호를 입력해주세요';
            if (v.length < 8) return '8자 이상이어야 합니다';
            if (!RegExp(r'[a-zA-Z]').hasMatch(v)) return '영문을 포함해야 합니다';
            if (!RegExp(r'[0-9]').hasMatch(v)) return '숫자를 포함해야 합니다';
            if (!RegExp(r'[!@#$%^&*(),.?":{}|<>]').hasMatch(v)) return '특수문자를 포함해야 합니다';
            return null;
          },
        ),
        const SizedBox(height: 12),

        CommonWidgets.textField(
          context: context,
          controller: _confirmCtrl,
          label: '비밀번호 확인',
          hint: '비밀번호를 다시 입력해주세요',
          icon: Icons.lock_outline,
          obscureText: _obscureConfirm,
          suffixIcon: IconButton(
            icon: Icon(_obscureConfirm ? Icons.visibility_off : Icons.visibility),
            onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm),
          ),
          validator: (v) {
            if (v != _passwordCtrl.text) return '비밀번호가 일치하지 않습니다';
            return null;
          },
        ),
      ]),
    );
  }

  Widget _buildPhone(ThemeData theme) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _buildStepHeader('휴대폰 인증', '본인 명의 휴대폰 번호로 인증해주세요'),
      const SizedBox(height: 24),

      if (_phoneVerified) ...[
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.successBg,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(children: [
            const Icon(Icons.check_circle, color: AppColors.success),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('인증 완료', style: ResponsiveHelper.smallStyle(context, color: AppColors.successDark, fontWeight: FontWeight.w600)),
              Text(_phoneCtrl.text, style: ResponsiveHelper.bodyStyle(context)),
            ])),
            TextButton(
              onPressed: () => setState(() { _phoneVerified = false; _codeSent = false; _codeCtrl.clear(); }),
              child: const Text('재인증'),
            ),
          ]),
        ),
      ] else ...[
        _buildLabel('휴대폰 번호', Icons.phone_outlined),
        Row(children: [
          Expanded(
            child: TextField(
              controller: _phoneCtrl,
              keyboardType: TextInputType.phone,
              decoration: InputDecoration(
                hintText: '010-0000-0000',
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                errorText: _phoneError,
              ),
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              onChanged: (_) => setState(() => _phoneError = null),
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton(
            onPressed: _codeSending ? null : _sendCode,
            style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14)),
            child: _codeSending
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : Text(_codeSent ? '재발송' : '인증번호 받기'),
          ),
        ]),

        if (_codeSent) ...[
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: TextField(
                controller: _codeCtrl,
                keyboardType: TextInputType.number,
                maxLength: 6,
                autofocus: true,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                onChanged: (v) { if (v.length == 6) _verifyCode(); },
                decoration: InputDecoration(
                  hintText: '인증번호 6자리',
                  counterText: '',
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton(
              onPressed: _codeVerifying ? null : _verifyCode,
              style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14)),
              child: _codeVerifying
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('확인'),
            ),
          ]),
        ],
      ],
    ]);
  }

  Widget _buildDocumentScan(ThemeData theme) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _buildStepHeader('외국인등록증 스캔', '외국인등록증을 촬영하거나 갤러리에서 선택해주세요'),
      const SizedBox(height: 8),

      // OCR 목적 안내
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: theme.colorScheme.primary.withValues(alpha: 0.3)),
        ),
        child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.info_outline, size: 15, color: AppColors.grey600),
            SizedBox(width: 6),
            Text('입력 보조 수단', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.grey700)),
          ]),
          SizedBox(height: 6),
          Text(
            'OCR로 성명·번호·체류자격 등 정보를 자동으로 인식합니다. '
            '인식된 내용은 다음 화면에서 직접 확인하고 수정할 수 있습니다.',
            style: TextStyle(fontSize: 12, color: AppColors.grey600),
          ),
        ]),
      ),
      const SizedBox(height: 24),

      if (_ocrRunning) ...[
        Center(child: Column(children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          // [CASE C] 기존 idCard 재사용 시도 중 vs. 신규 OCR 실행 중 구분
          Text(
            widget.isResume && widget.existingIdCardPath != null
                ? '이전에 등록한 외국인등록증을 불러오는 중...'
                : '이미지 인식 중...',
          ),
        ])),
      ] else ...[
        // 촬영 버튼
        _buildScanOption(
          icon: Icons.camera_alt_outlined,
          label: '카메라로 촬영',
          sublabel: '선명하게 촬영하면 인식률이 높아집니다',
          onTap: () => _pickAndOcr(ImageSource.camera),
          isPrimary: true,
        ),
        const SizedBox(height: 12),
        _buildScanOption(
          icon: Icons.photo_library_outlined,
          label: '갤러리에서 선택',
          sublabel: '저장된 외국인등록증 사진을 선택하세요',
          onTap: () => _pickAndOcr(ImageSource.gallery),
        ),
        const SizedBox(height: 24),

        // 촬영 팁
        _buildTipCard(),
      ],
    ]);
  }

  Widget _buildScanOption({
    required IconData icon,
    required String label,
    required String sublabel,
    required VoidCallback onTap,
    bool isPrimary = false,
  }) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: isPrimary ? theme.colorScheme.primary : AppColors.grey50,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isPrimary ? theme.colorScheme.primary : AppColors.grey200,
          ),
        ),
        child: Row(children: [
          Icon(icon, color: isPrimary ? Colors.white : AppColors.grey600, size: 28),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: TextStyle(
              fontWeight: FontWeight.w600,
              color: isPrimary ? Colors.white : AppColors.grey800,
            )),
            const SizedBox(height: 2),
            Text(sublabel, style: TextStyle(
              fontSize: 12,
              color: isPrimary ? Colors.white70 : AppColors.grey500,
            )),
          ])),
          Icon(Icons.chevron_right, color: isPrimary ? Colors.white70 : AppColors.grey400),
        ]),
      ),
    );
  }

  Widget _buildTipCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.grey50,
        borderRadius: BorderRadius.circular(10),
      ),
      child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('촬영 팁', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: AppColors.grey600)),
        SizedBox(height: 8),
        _TipRow(icon: Icons.light_mode_outlined, text: '밝은 곳에서 촬영하세요'),
        _TipRow(icon: Icons.straighten, text: '카드가 화면 안에 가득 차도록 찍으세요'),
        _TipRow(icon: Icons.flip, text: '앞면(사진·정보가 있는 면)을 찍어주세요'),
        _TipRow(icon: Icons.block_outlined, text: '빛 반사나 그림자가 없도록 해주세요'),
      ]),
    );
  }

  Widget _buildOcrConfirm(ThemeData theme) {
    final hadFailures = _ocrResult?.legalNameFailed == true
        || _ocrResult?.foreignIdFailed == true
        || _ocrResult?.visaTypeFailed == true;

    return Form(
      key: _ocrFormKey,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _buildStepHeader('정보 확인', '인식된 정보를 확인하고 수정해주세요'),
        const SizedBox(height: 8),

        if (hadFailures)
          Container(
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: Colors.orange.shade50,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.orange.shade200),
            ),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.warning_amber, color: Colors.orange.shade700, size: 18),
              const SizedBox(width: 8),
              const Expanded(child: Text(
                '일부 정보를 인식하지 못했습니다. 해당 항목을 직접 입력해주세요.',
                style: TextStyle(fontSize: 13),
              )),
            ]),
          ),

        const SizedBox(height: 4),

        // 성명 (외국인등록증 기재)
        _buildOcrField(
          controller: _legalNameCtrl,
          label: '성명 (외국인등록증 기재)',
          hint: '예: NGUYEN VAN AN',
          failed: _ocrResult?.legalNameFailed ?? true,
          validator: (v) => (v == null || v.trim().isEmpty) ? '성명을 입력해주세요' : null,
        ),
        const SizedBox(height: 14),

        // 외국인등록번호 — 13자리 입력, 표시는 마스킹 없음 (입력 중)
        _buildOcrField(
          controller: _rawForeignIdCtrl,
          label: '외국인등록번호 (13자리 숫자)',
          hint: '예: 0010205XXXXXXX',
          failed: _ocrResult?.foreignIdFailed ?? true,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(13)],
          validator: (v) {
            if (v == null || v.isEmpty) return '외국인등록번호를 입력해주세요';
            final cleaned = v.replaceAll(RegExp(r'\D'), '');
            if (!_foreignId13Re.hasMatch(cleaned)) return '13자리 숫자를 입력해주세요';
            final g = int.tryParse(cleaned[6]);
            if (g == null || g < 5 || g > 8) return '뒷자리 첫 번째 숫자가 올바르지 않습니다 (5~8)';
            return null;
          },
        ),
        const SizedBox(height: 14),

        // 체류자격
        _buildOcrField(
          controller: _visaTypeCtrl,
          label: '체류자격 (선택)',
          hint: '예: E-9, F-4, H-2',
          failed: false,
          isOptional: true,
        ),
        const SizedBox(height: 14),

        // 체류기간만료일
        _buildOcrField(
          controller: _stayExpiryCtrl,
          label: '체류기간만료일 (선택)',
          hint: 'YYYY-MM-DD',
          failed: false,
          isOptional: true,
        ),
        const SizedBox(height: 14),

        // 앱 표시용 이름 (선택)
        _buildLabel('앱 표시 이름 (선택)', Icons.badge_outlined),
        CommonWidgets.textField(
          context: context,
          controller: _koreanNameCtrl,
          label: '앱 표시 이름',
          hint: '한국어 이름이 있다면 입력해주세요 (예: 응우옌 반 안)',
          icon: Icons.badge_outlined,
        ),
        const SizedBox(height: 4),
        Text(
          '앱 내 표시에만 사용됩니다. 급여 계좌와 계약서에는 외국인등록증 성명이 우선 사용됩니다.',
          style: ResponsiveHelper.tinyStyle(context, color: AppColors.grey500),
        ),
        const SizedBox(height: 20),
      ]),
    );
  }

  Widget _buildOcrField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required bool failed,
    bool isOptional = false,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
    String? Function(String?)? validator,
  }) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Text(label, style: ResponsiveHelper.smallStyle(context, color: AppColors.grey600, fontWeight: FontWeight.w600)),
        if (failed) ...[
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.orange.shade100,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text('직접 입력 필요', style: TextStyle(fontSize: 10, color: Colors.orange.shade800)),
          ),
        ],
        if (isOptional) ...[
          const SizedBox(width: 6),
          Text('(선택)', style: ResponsiveHelper.tinyStyle(context, color: AppColors.grey400)),
        ],
      ]),
      const SizedBox(height: 6),
      TextFormField(
        controller: controller,
        keyboardType: keyboardType,
        inputFormatters: inputFormatters,
        validator: validator,
        decoration: InputDecoration(
          hintText: hint,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          filled: true,
          fillColor: failed ? Colors.orange.shade50 : AppColors.grey50,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: failed ? Colors.orange.shade300 : AppColors.grey300),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: failed ? Colors.orange.shade300 : AppColors.grey200),
          ),
        ),
      ),
    ]);
  }

  Widget _buildTerms(ThemeData theme) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _buildStepHeader('서비스 이용 동의', '서비스 이용을 위해 약관에 동의해주세요'),
      const SizedBox(height: 20),

      if (_termsLoading) ...[
        const Center(child: CircularProgressIndicator()),
      ] else if (_legalTerms == null) ...[
        const Text('약관 정보를 불러올 수 없습니다.'),
      ] else ...[
        // 전체 동의 버튼
        GestureDetector(
          onTap: () {
            final allChecked = _consentMap.values.every((v) => v);
            setState(() {
              for (final key in _consentMap.keys) {
                _consentMap[key] = !allChecked;
              }
            });
          },
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.grey50,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(children: [
              Checkbox(
                value: _consentMap.isNotEmpty && _consentMap.values.every((v) => v),
                tristate: true,
                onChanged: (v) => setState(() {
                  for (final key in _consentMap.keys) { _consentMap[key] = v ?? false; }
                }),
              ),
              const Expanded(child: Text('전체 동의', style: TextStyle(fontWeight: FontWeight.w600))),
            ]),
          ),
        ),
        const Divider(height: 20),

        for (final item in _legalTerms!.activeItems) ...[
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Checkbox(
              value: _consentMap[item.id] ?? false,
              onChanged: (v) => setState(() => _consentMap[item.id] = v ?? false),
            ),
            title: Text(
              '${item.isRequired ? '[필수] ' : '[선택] '}${item.title}',
              style: ResponsiveHelper.bodyStyle(context),
            ),
            trailing: item.content.isNotEmpty
                ? TextButton(
                    onPressed: () async {
                      _viewedIds.add(item.id);
                      // 약관 내용 바텀시트 표시
                      await DialogHelper.showSheet(
                        context,
                        isScrollControlled: true,
                        builder: (ctx) => DraggableScrollableSheet(
                          initialChildSize: 0.7,
                          maxChildSize: 0.95,
                          minChildSize: 0.4,
                          expand: false,
                          builder: (_, scrollCtrl) => Padding(
                            padding: const EdgeInsets.all(20),
                            child: SingleChildScrollView(
                              controller: scrollCtrl,
                              child: Column(children: [
                                Text(item.title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                                const SizedBox(height: 16),
                                Text(item.content),
                              ]),
                            ),
                          ),
                        ),
                      );
                    },
                    child: const Text('보기'),
                  )
                : null,
          ),
        ],
      ],
    ]);
  }

  Widget _buildHomeRegion(ThemeData theme) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _buildStepHeader('주로 일할 지역', '가까운 일자리를 먼저 보여드릴게요'),
      const SizedBox(height: 20),

      if (_homeRegion != null)
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.successBg,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(children: [
            const Icon(Icons.location_on, color: AppColors.success),
            const SizedBox(width: 10),
            Expanded(child: Text(_homeRegion!.toString(), style: const TextStyle(fontWeight: FontWeight.w600))),
            TextButton(
              onPressed: _selectRegion,
              child: const Text('변경'),
            ),
          ]),
        )
      else
        OutlinedButton.icon(
          onPressed: _selectRegion,
          icon: const Icon(Icons.location_on_outlined),
          label: const Text('지역 선택하기'),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(double.infinity, 48),
          ),
        ),
    ]);
  }

  Future<void> _selectRegion() async {
    final region = await DialogHelper.showSheet<UserRegion>(
      context,
      isScrollControlled: true,
      builder: (ctx) => const HomeRegionPickerSheet(),
    );
    if (region != null && mounted) {
      setState(() => _homeRegion = region);
    }
  }

  // ============================================================
  // 공통 위젯 헬퍼
  // ============================================================

  Widget _buildStepHeader(String title, String subtitle) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
      const SizedBox(height: 6),
      Text(subtitle, style: const TextStyle(color: AppColors.grey500, fontSize: 14)),
    ]);
  }

  Widget _buildLabel(String text, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(children: [
        Icon(icon, size: 13, color: AppColors.grey500),
        const SizedBox(width: 4),
        Text(text, style: ResponsiveHelper.smallStyle(context, color: AppColors.grey600, fontWeight: FontWeight.w600)),
      ]),
    );
  }
}

// ──────────────────────────────────────────────────────────────
// 보조 위젯
// ──────────────────────────────────────────────────────────────

class _TipRow extends StatelessWidget {
  final IconData icon;
  final String text;
  const _TipRow({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(children: [
        Icon(icon, size: 14, color: AppColors.grey500),
        const SizedBox(width: 6),
        Text(text, style: const TextStyle(fontSize: 12, color: AppColors.grey600)),
      ]),
    );
  }
}
