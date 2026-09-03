import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_auth/firebase_auth.dart' show FirebaseAuth, FirebaseAuthException;
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
import '../../widgets/auth/terms_viewer_screen.dart';
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
  finalSetup,   // 4: 지역(USER) + 약관 동의 — 내국인 가입과 동일 구조
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

  /// [B.1] Recoverable 오류 재시도 지원 — 업로드 완료된 Storage 경로 기억.
  /// finalizeForeignIdentity가 recoverable 오류로 실패해도 계정이 유지되므로
  /// 재시도 시 이미 업로드된 이미지를 재사용할 수 있다.
  /// 새 이미지가 선택되면 null로 리셋.
  String? _uploadedStoragePath;

  // ── Step 3: OCR 확인 ─────────────────────────────────────────
  ForeignIdOcrResult? _ocrResult;
  final _legalNameCtrl      = TextEditingController();
  final _rawForeignIdCtrl   = TextEditingController(); // 13자리 평문
  final _visaTypeCtrl       = TextEditingController(); // 필수
  // _stayExpiryCtrl 제거됨 — 가입 필수정보 최소화 정책 (Data Minimization)
  final _koreanNameCtrl     = TextEditingController();
  final _ocrFormKey = GlobalKey<FormState>();

  // ── finalSetup: 약관 동의 ────────────────────────────────────
  LegalTerms? _legalTerms;
  bool _termsLoading = false;
  final _consentMap = <String, bool>{};
  final _viewedTermIds = <String>{}; // 열람한 약관 ID — '보기 *' ↔ '다시보기' 표시 구분

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
      final code = e is FirebaseAuthException ? e.code : e.runtimeType.toString();
      debugPrint('❌ [_sendCode] 에러: $e');
      setState(() {
        _codeSending = false;
        _phoneError = '발송 실패 ($code)';  // TODO: 진단 후 원래 메시지로 복원
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
      // stayExpiryDate — 가입 필수정보 최소화 정책으로 수집 안 함
      _koreanNameCtrl.clear();
      _imagePath = null;          // 재업로드 없음
      _uploadedStoragePath = null; // [B.1] 기존 Storage 경로가 있어도 이 흐름에서는 무관
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
      // stayExpiryDate — 가입 필수정보 최소화 정책으로 수집 안 함
      _koreanNameCtrl.clear();
      _imagePath = picked.path;
      _uploadedStoragePath = null; // [B.1] 새 이미지 선택 → 이전 업로드 경로 무효화

      setState(() => _ocrRunning = false);
      _goTo(_Step.ocrConfirm);
    } catch (e) {
      debugPrint('❌ [ForeignReg] OCR 실패: $e');
      if (!mounted) return;
      // OCR 예외 → 모든 필드 수동 입력 허용
      _ocrResult = const ForeignIdOcrResult(
        legalNameFailed: true, foreignIdFailed: true, visaTypeFailed: true,
      );
      _legalNameCtrl.clear();
      _rawForeignIdCtrl.clear();
      _visaTypeCtrl.clear();
      _imagePath = picked.path;
      _uploadedStoragePath = null; // [B.1] 새 이미지 선택 → 이전 업로드 경로 무효화

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
      ToastHelper.showWarning('영문 이름을 입력해주세요');
      return false;
    }
    if (_visaTypeCtrl.text.trim().isEmpty) {
      ToastHelper.showWarning('체류자격을 입력해주세요');
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
    final imagePath = _imagePath;

    // [DEBUG] 진입점 추적
    final dbgCurrentUid = FirebaseAuth.instance.currentUser?.uid;
    final dbgMaskedId = rawId.length >= 8 ? '${rawId.substring(0, 8)}*****' : '(len=${rawId.length})';
    debugPrint('🔷 [ForeignReg] _processRegistration 시작 | isResume=${widget.isResume} | existingAuth=${dbgCurrentUid ?? "null"} | maskedId=$dbgMaskedId | legalName=$legalName | imagePath=${imagePath != null}');

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
      _goTo(_Step.finalSetup);
      return;
    }
    // [SAFETY] RESUME 전용 — FRESH 신규 가입은 _commitFreshRegistration() 에서 처리
  }

  // ============================================================
  // finalSetup 유효성 검사 (지역 + 약관)
  // ============================================================

  bool _validateFinalSetup() {
    if (widget.role == UserRole.USER && _homeRegion == null) {
      ToastHelper.showWarning('주로 일할 지역을 선택해주세요');
      return false;
    }
    final required = _legalTerms?.activeItems.where((t) => t.isRequired).toList() ?? [];
    final allAgreed = required.every((t) => _consentMap[t.id] == true);
    if (!allAgreed) {
      ToastHelper.showWarning('필수 약관에 모두 동의해주세요');
      return false;
    }
    return true;
  }

  bool get _isFinalSetupComplete {
    if (widget.role == UserRole.USER && _homeRegion == null) return false;
    final required = _legalTerms?.activeItems.where((t) => t.isRequired).toList() ?? [];
    return required.every((t) => _consentMap[t.id] == true);
  }

  // ================================================================
  // FRESH 신규 가입 최종 커밋 — finalSetup '가입 완료' 버튼에서 실행
  //   signUp → Storage → finalizeForeignIdentity → markIdCard
  //   → koreanName → region → termsConsent → active
  // ================================================================
  Future<void> _commitFreshRegistration() async {
    if (_isBusy) return;
    setState(() => _isBusy = true);

    // Draft 값 먼저 읽기 (async gap 이전)
    final rawId = _rawForeignIdCtrl.text.trim().replaceAll(RegExp(r'\D'), '');
    final legalName = _legalNameCtrl.text.trim();
    final visaType = _visaTypeCtrl.text.trim();
    final imagePath = _imagePath;
    final koreanName = _koreanNameCtrl.text.trim();
    final phone = _phoneCtrl.text.trim();
    final role = widget.role;

    final dbgMaskedId = rawId.length >= 8 ? '${rawId.substring(0, 8)}*****' : '(len=${rawId.length})';
    debugPrint('🔷 [ForeignReg] _commitFreshRegistration 시작 | maskedId=$dbgMaskedId');

    // ──────────────────────────────────────────────────────────────
    // [B.2] RETRY GUARD: 이전 시도에서 Auth/Firestore pending 이 남아있는지 확인
    // ──────────────────────────────────────────────────────────────
    final existingSession = FirebaseAuth.instance.currentUser;
    bool proceedFresh = true;

    if (existingSession != null) {
      final retryUid = existingSession.uid;
      bool isValidPendingRetry = false;
      String? retryActualStatus;
      bool retryDocExists = false;
      try {
        final userDoc = await FirebaseFirestore.instance
            .collection('users').doc(retryUid).get();
        final status = userDoc.data()?['accountStatus'] as String?;
        retryActualStatus = status;
        retryDocExists = userDoc.exists;
        isValidPendingRetry = userDoc.exists && status == 'registration_pending';
      } catch (fsErr) {
        debugPrint('❌ [ForeignReg commit] Firestore 상태 조회 실패: $fsErr');
      }

      debugPrint('🔍 [ForeignReg commit] 기존 세션 | uid=$retryUid | docExists=$retryDocExists | status=$retryActualStatus');

      if (!isValidPendingRetry) {
        if (!retryDocExists) {
          // Orphan Auth → signOut 후 신규 진행
          debugPrint('⚠️ [ForeignReg commit] Orphan Auth 감지 → signOut + 신규 가입');
          try { await FirebaseAuth.instance.signOut(); } catch (_) {}
          proceedFresh = true;
        } else {
          if (!mounted) return;
          setState(() => _isBusy = false);
          if (retryActualStatus == 'active') {
            ToastHelper.showError('이미 가입된 계정이 확인되었습니다. 로그인 화면에서 다시 시도해 주세요.');
          } else {
            ToastHelper.showError('현재 상태에서는 가입을 진행할 수 없습니다. 앱을 재시작해 주세요.');
          }
          return;
        }
      } else {
        // 유효한 pending retry → finalize 재시도 (signUp 건너뜀)
        proceedFresh = false;
        if (_uploadedStoragePath == null && imagePath != null) {
          try {
            final ts = DateTime.now().millisecondsSinceEpoch;
            final retryPath = 'users/$retryUid/idCard_$ts.jpg';
            await FirebaseStorage.instance.ref(retryPath).putFile(File(imagePath));
            _uploadedStoragePath = retryPath;
          } catch (e) {
            debugPrint('⚠️ [ForeignReg commit retry] 이미지 업로드 실패: $e');
          }
        }
        final finalizeErr = await AuthService().finalizeForeignIdentity(
          rawId,
          legalName: legalName.isNotEmpty ? legalName : null,
          visaType: visaType.isNotEmpty ? visaType : null,
        );
        if (!mounted) return;
        if (finalizeErr != null) {
          setState(() => _isBusy = false);
          ToastHelper.showError(finalizeErr);
          return;
        }
        if (_uploadedStoragePath != null) {
          try {
            await FirebaseFunctions.instanceFor(region: 'asia-northeast3')
                .httpsCallable('callableMarkIdCardVerified',
                    options: HttpsCallableOptions(timeout: const Duration(seconds: 15)))
                .call({'storagePath': _uploadedStoragePath});
          } catch (e) {
            debugPrint('⚠️ [ForeignReg commit retry] markIdCardVerified 실패: $e');
          }
        }
        if (imagePath != null) {
          try { await File(imagePath).delete(); } catch (_) {}
        }
        // proceedFresh == false → fall through to region + terms
      }
    }

    if (proceedFresh) {
      if (!mounted) return;

      // ── 사전 중복 체크 ──────────────────────────────────────────
      try {
        final exists = await AuthService().precheckForeignIdentity(rawId, role);
        if (!mounted) return;
        if (exists) {
          setState(() => _isBusy = false);
          ToastHelper.showError('이미 동일 역할로 가입된 외국인등록번호입니다.');
          return;
        }
      } catch (_) { /* 사전 체크 실패 무시 — finalize에서 재확인 */ }

      // ── 계정 생성 ─────────────────────────────────────────────
      if (!mounted) return;
      final userProvider = context.read<UserProvider>();
      final effectiveName = koreanName.isNotEmpty ? koreanName : legalName;
      final sentinelId = '${rawId.substring(0, 6)}-${rawId[6]}${'*' * 6}';

      debugPrint('🔷 [ForeignReg commit] signUp() | sentinelId=$sentinelId');
      final success = await userProvider.signUp(
        username: _usernameCtrl.text.trim(),
        password: _passwordCtrl.text,
        name: effectiveName,
        phone: phone,
        role: role,
        gender: null,
        birthDate: null,
        residentNumber: null,
        foreignIdNumber: sentinelId,
        accountStatus: 'registration_pending',
        authPhone: phone,
        phoneVerificationLevel: 'otp_verified',
        homeRegion: null,
      );
      if (!mounted) return;
      if (!success) {
        setState(() => _isBusy = false);
        final err = userProvider.error ?? '';
        final userMsg = err.contains('permission-denied') || err.contains('PERMISSION_DENIED')
            ? '정보를 저장하지 못했습니다. 잠시 후 다시 시도해주세요.'
            : (err.isNotEmpty ? err : '계정 생성에 실패했습니다.');
        ToastHelper.showError(userMsg);
        return;
      }

      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) {
        setState(() => _isBusy = false);
        ToastHelper.showError('계정 정보를 확인할 수 없습니다. 다시 시도해주세요.');
        return;
      }

      // ── 이미지 업로드 ────────────────────────────────────────
      String? uploadedPath;
      if (imagePath != null) {
        try {
          final ts = DateTime.now().millisecondsSinceEpoch;
          final storagePath = 'users/$uid/idCard_$ts.jpg';
          await FirebaseStorage.instance.ref(storagePath).putFile(File(imagePath));
          uploadedPath = storagePath;
          _uploadedStoragePath = storagePath;
        } catch (e) {
          debugPrint('⚠️ [ForeignReg commit] 이미지 업로드 실패 (계속): $e');
        }
      }

      // ── finalizeForeignIdentity ──────────────────────────────
      final finalizeErr = await AuthService().finalizeForeignIdentity(
        rawId,
        legalName: legalName.isNotEmpty ? legalName : null,
        visaType: visaType.isNotEmpty ? visaType : null,
      );
      if (!mounted) return;
      if (finalizeErr != null) {
        setState(() => _isBusy = false);
        ToastHelper.showError(finalizeErr);
        return;
      }

      // ── callableMarkIdCardVerified ───────────────────────────
      if (uploadedPath != null) {
        try {
          await FirebaseFunctions.instanceFor(region: 'asia-northeast3')
              .httpsCallable('callableMarkIdCardVerified',
                  options: HttpsCallableOptions(timeout: const Duration(seconds: 15)))
              .call({'storagePath': uploadedPath});
        } catch (e) {
          debugPrint('⚠️ [ForeignReg commit] markIdCardVerified 실패: $e');
        }
      }

      // ── 임시 파일 정리 ────────────────────────────────────────
      if (imagePath != null) {
        try { await File(imagePath).delete(); } catch (_) {}
      }

      // ── koreanName 저장 ───────────────────────────────────────
      if (koreanName.isNotEmpty) {
        try {
          await FirebaseFirestore.instance
              .collection('users').doc(uid).update({'koreanName': koreanName});
        } catch (e) {
          debugPrint('⚠️ [ForeignReg commit] koreanName 저장 실패 (치명적 아님): $e');
        }
      }
    }

    // ── region + terms → active (fresh + retry 공통) ─────────────
    await _finalizeRegistration();
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

    // homeRegion 업데이트 (USER 전용) — hard-fail: 실패 시 terms CF 호출 금지
    // _validateFinalSetup()에서 homeRegion != null 보장됨 (USER만 진입)
    if (widget.role == UserRole.USER) {
      try {
        await FirestoreService().updateUserDocument(uid, {'homeRegion': _homeRegion!.toMap()});
      } catch (e) {
        debugPrint('❌ [ForeignReg] homeRegion 저장 실패: $e');
        if (!mounted) return;
        setState(() => _isBusy = false);
        ToastHelper.showError('지역 정보를 저장하지 못했습니다.\n잠시 후 다시 시도해주세요.');
        return; // callableRecordTermsConsent 호출 금지 — registration_pending 유지
      }
    }

    // callableRecordTermsConsent → 5가지 조건 충족 시 CF가 active로 전환 (USER: homeRegion 포함)
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
        if (_validateOcrConfirm()) {
          if (widget.isResume) {
            await _processRegistration(); // RESUME: finalize → finalSetup
          } else {
            _goTo(_Step.finalSetup); // FRESH: 서버 호출 없이 이동
          }
        }
      case _Step.finalSetup:
        if (_validateFinalSetup()) {
          if (widget.isResume) {
            await _finalizeRegistration(); // RESUME: region + terms → active
          } else {
            await _commitFreshRegistration(); // FRESH: 전체 커밋 → active
          }
        }
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
        backgroundColor: Colors.white,
        body: SafeArea(
          bottom: false,
          child: Column(children: [
            // 커스텀 헤더 (내국인 회원가입과 동일한 UI Shell)
            _buildHeader(),
            // 내용
            Expanded(
              child: SingleChildScrollView(
                controller: _scrollCtrl,
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
                child: _buildCurrentStep(theme),
              ),
            ),
          ]),
        ),
        bottomNavigationBar: SafeArea(
          top: false,
          child: _buildBottomButtons(theme),
        ),
      ),
    );
  }

  // 현재 스텝에 따른 헤더 부제목
  String get _stepSubtitle => switch (_step) {
    _Step.basicInfo    => '기본 정보 입력',
    _Step.phone        => '휴대폰 인증',
    _Step.documentScan => '외국인등록증 스캔',
    _Step.ocrConfirm   => '정보 확인',
    _Step.finalSetup   => widget.role == UserRole.USER ? '일자리 시작 설정' : '서비스 이용 동의',
  };

  // 내국인 회원가입과 동일한 커스텀 헤더
  Widget _buildHeader() {
    final int total;
    final int current;
    if (widget.isResume) {
      // [RESUME MODE] documentScan(0) → ocrConfirm(1) → finalSetup(2) [3단계, 두 역할 동일]
      total = 3;
      current = (_step.index - _Step.documentScan.index).clamp(0, total - 1);
    } else {
      // [FRESH] basicInfo(0)→phone(1)→documentScan(2)→ocrConfirm(3)→finalSetup(4) [5단계]
      total = _Step.values.length; // 5
      current = _step.index;
    }

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
          GestureDetector(
            onTap: _handleBack,
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
                  _stepSubtitle,
                  style: ResponsiveHelper.smallStyle(context,
                      color: AppColors.textSecondary),
                ),
                SizedBox(height: ResponsiveHelper.spacing(context, 12)),
                // 진행 세그먼트 (내국인 회원가입과 동일한 스타일)
                Row(
                  children: List.generate(total * 2 - 1, (i) {
                    if (i.isOdd) {
                      return SizedBox(width: ResponsiveHelper.spacing(context, 5));
                    }
                    return _buildProgressSegment(i ~/ 2 <= current);
                  }),
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
          color: active ? Theme.of(context).primaryColor : AppColors.grey200,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }

  Widget _buildCurrentStep(ThemeData theme) {
    return switch (_step) {
      _Step.basicInfo    => _buildBasicInfo(theme),
      _Step.phone        => _buildPhone(theme),
      _Step.documentScan => _buildDocumentScan(theme),
      _Step.ocrConfirm   => _buildOcrConfirm(theme),
      _Step.finalSetup   => _buildFinalSetup(theme),
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
    final isLast = _step == _Step.finalSetup;
    final isDocScan = _step == _Step.documentScan;
    final isDisabled = isLast && !_isFinalSetupComplete;

    if (isDocScan) {
      // 문서 스캔 단계는 하단 버튼 없음 (직접 촬영/선택 버튼으로 진행)
      return const SizedBox.shrink();
    }

    return Padding(
      padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 16)),
      child: SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: isDisabled ? null : _onNext,
          style: ElevatedButton.styleFrom(
            backgroundColor: theme.primaryColor,
            disabledBackgroundColor: AppColors.grey200,
            foregroundColor: Colors.white,
            disabledForegroundColor: AppColors.grey400,
            padding: EdgeInsets.symmetric(vertical: ResponsiveHelper.spacing(context, 14)),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            elevation: 0,
          ),
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

        // 영문 이름 (외국인등록증 기재)
        _buildOcrField(
          controller: _legalNameCtrl,
          label: '영문 이름 (외국인등록증 기재)',
          hint: '예: NGUYEN VAN AN',
          failed: _ocrResult?.legalNameFailed ?? true,
          validator: (v) => (v == null || v.trim().isEmpty) ? '영문 이름을 입력해주세요' : null,
        ),
        // [Phase A.4] OCR 이름 정확도 불확실 시 확인 안내
        if (_ocrResult != null && _ocrResult!.shouldPromptNameVerification) ...[
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.info_outline, size: 14, color: Colors.orange),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    '카드에 적힌 영문 이름과 동일한지 확인해주세요',
                    style: const TextStyle(fontSize: 12, color: Colors.orange),
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 14),

        // 한글 이름 (선택) — 영문 이름 바로 아래 배치
        _buildOcrField(
          controller: _koreanNameCtrl,
          label: '한글 이름',
          hint: '한글 이름을 입력해주세요',
          failed: false,
          isOptional: true,
        ),
        const SizedBox(height: 4),
        Text(
          '없으면 입력하지 않으셔도 됩니다',
          style: ResponsiveHelper.tinyStyle(context, color: AppColors.grey400),
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

        // 체류자격 (필수)
        _buildOcrField(
          controller: _visaTypeCtrl,
          label: '체류자격',
          hint: '예: F-4',
          failed: false,
          isOptional: false,
          validator: (v) {
            if (v == null || v.trim().isEmpty) return '체류자격을 입력해주세요';
            return null;
          },
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

  // ============================================================
  // finalSetup: 지역(USER) + 약관 동의 — 내국인 가입과 동일 구조
  // ============================================================

  Widget _buildFinalSetup(ThemeData theme) {
    final title = widget.role == UserRole.USER ? '일자리 시작 설정' : '서비스 이용 동의';
    final subtitle = widget.role == UserRole.USER
        ? '지역과 약관을 설정하면 가입이 완료됩니다'
        : '서비스 이용을 위해 약관에 동의해주세요';

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _buildStepHeader(title, subtitle),
      const SizedBox(height: 24),

      // 지역 선택 (USER 전용)
      if (widget.role == UserRole.USER) ...[
        Text('주로 일할 지역',
            style: ResponsiveHelper.smallStyle(context,
                color: AppColors.grey600, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        if (_homeRegion != null)
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.successBg,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(children: [
              const Icon(Icons.location_on, color: AppColors.success),
              const SizedBox(width: 10),
              Expanded(
                child: Text(_homeRegion!.toString(),
                    style: const TextStyle(fontWeight: FontWeight.w600)),
              ),
              TextButton(onPressed: _selectRegion, child: const Text('변경')),
            ]),
          )
        else
          GestureDetector(
            onTap: _selectRegion,
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.grey200),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(children: [
                Icon(Icons.map_outlined, color: AppColors.grey400),
                const SizedBox(width: 10),
                Expanded(
                  child: Text('지역을 선택해주세요',
                      style: ResponsiveHelper.bodyStyle(context,
                          color: AppColors.grey400)),
                ),
                Icon(Icons.chevron_right, color: AppColors.grey400),
              ]),
            ),
          ),
        Text('가입 후 MY에서 언제든 변경할 수 있어요.',
            style: ResponsiveHelper.tinyStyle(context, color: AppColors.grey400)),
        const SizedBox(height: 24),
      ],

      // 약관 동의 섹션
      if (_termsLoading)
        const Center(child: CircularProgressIndicator())
      else if (_legalTerms == null)
        Text('약관 정보를 불러올 수 없습니다.',
            style: ResponsiveHelper.bodyStyle(context, color: AppColors.grey500))
      else
        _buildConsentSection(),
    ]);
  }

  /// 내국인 가입의 _buildConsentSection()과 동일한 로직
  Widget _buildConsentSection() {
    final items = _legalTerms!.activeItems;
    final allAgreed = items.isNotEmpty && items.every((t) => _consentMap[t.id] == true);

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // 전체 동의 버튼
      GestureDetector(
        onTap: () async {
          final alreadyAll = items.every((t) => _consentMap[t.id] == true);
          if (!alreadyAll) {
            // 아직 동의 안 한 항목에 순차적으로 약관 뷰어 열기
            final unagreed = items.where((t) => _consentMap[t.id] != true).toList();
            for (final item in unagreed) {
              await _showTermsDetail(item);
              if (!mounted) return;
            }
          } else {
            setState(() {
              for (final key in _consentMap.keys) { _consentMap[key] = false; }
            });
          }
        },
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.grey50,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(children: [
            Checkbox(
              value: allAgreed ? true : (items.any((t) => _consentMap[t.id] == true) ? null : false),
              tristate: true,
              onChanged: (v) {
                if (v == true) {
                  // 전체 동의: 각 항목 뷰어 순차 오픈
                  final unagreed = items.where((t) => _consentMap[t.id] != true).toList();
                  if (unagreed.isEmpty) return;
                  Future.microtask(() async {
                    for (final item in unagreed) {
                      await _showTermsDetail(item);
                      if (!mounted) return;
                    }
                  });
                } else {
                  setState(() {
                    for (final key in _consentMap.keys) { _consentMap[key] = false; }
                    _viewedTermIds.clear();
                  });
                }
              },
            ),
            const Expanded(child: Text('전체 동의', style: TextStyle(fontWeight: FontWeight.w600))),
          ]),
        ),
      ),
      const Divider(height: 20),

      for (final item in items)
        _buildConsentRow(item),
    ]);
  }

  Widget _buildConsentRow(LegalTermsItem item) {
    final theme = Theme.of(context);
    final viewed = _viewedTermIds.contains(item.id);
    final agreed = _consentMap[item.id] == true;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Checkbox(
        value: agreed,
        onChanged: (v) {
          if (v == true && !viewed) {
            // 약관을 보지 않고 체크 → 뷰어 오픈 후 동의
            _showTermsDetail(item);
          } else {
            setState(() => _consentMap[item.id] = v ?? false);
          }
        },
      ),
      title: Text(
        '${item.isRequired ? '[필수] ' : '[선택] '}${item.title}',
        style: ResponsiveHelper.bodyStyle(context),
      ),
      trailing: item.content.isNotEmpty
          ? TextButton(
              onPressed: () => _showTermsDetail(item),
              child: Text(
                viewed ? '다시보기' : '보기 *',
                style: TextStyle(
                  color: viewed ? AppColors.grey400 : theme.primaryColor,
                  fontWeight: viewed ? FontWeight.normal : FontWeight.bold,
                ),
              ),
            )
          : null,
    );
  }

  Future<void> _showTermsDetail(LegalTermsItem item) async {
    _viewedTermIds.add(item.id);
    if (mounted) setState(() {});
    final agreed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => TermsViewerScreen(item: item),
      ),
    );
    if (agreed == true && mounted) {
      setState(() => _consentMap[item.id] = true);
    }
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
      Text(
        title,
        style: ResponsiveHelper.bodyStyle(context).copyWith(
          fontSize: 20,
          fontWeight: FontWeight.bold,
          color: AppColors.textPrimary,
        ),
      ),
      const SizedBox(height: 6),
      Text(
        subtitle,
        style: ResponsiveHelper.smallStyle(context, color: AppColors.textSecondary),
      ),
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
