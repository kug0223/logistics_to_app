import 'dart:async' show unawaited;
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
import '../../services/tax_identity_service.dart';
import '../../services/phone_verification_service.dart';
import '../../utils/responsive_helper.dart';
import '../../utils/document_upload_helper.dart';
import '../../utils/format_helper.dart';
import '../../utils/identity_identifier.dart';
import '../../utils/terms_submit_guard.dart';
import '../../utils/text_layout.dart';
import '../../utils/toast_helper.dart';
import '../../utils/dialog_helper.dart';
import '../../widgets/common/common_widgets.dart';
import '../../widgets/common/first_line_icon.dart';
import '../../widgets/common/keep_words_text.dart';
import '../../widgets/inputs/home_region_picker_sheet.dart';
import '../../widgets/auth/terms_viewer_screen.dart';
import '../../theme/app_colors.dart';
import '../../utils/picker_cache_scope.dart';

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
/// [FULL13-REEVAL.3] 위젯 시험용 주입 지점 — 사진 선택·OCR·Storage·callable 대신 합성 함수.
///   운영 코드는 설정하지 않는다(null 이면 실제 구현).
@visibleForTesting
class ForeignRegisterHooks {
  /// 새 사진 선택 + OCR. result 가 null 이면 "사진은 골랐고 OCR 이 예외로 끝남"이다.
  static Future<({String path, ForeignIdOcrResult? result})> Function()? pickAndOcr;
  /// [CASE C] 기존 사진 다운로드 + OCR.
  static Future<ForeignIdOcrResult> Function(String storagePath)? reuseOcr;
  static String? Function()? currentUid;
  static Future<void> Function(String localPath, String storagePath)? upload;
  static Future<Map<String, dynamic>?> Function(String uid)? readUser;
  static Future<String?> Function(String rawId, String legalName, String koreanName,
      String visaType, Map<String, dynamic>? documentEvidence)? finalize;
  static Future<void> Function(Map<String, dynamic> payload)? mark;
  static bool Function()? collectionEnabled;
  /// [DU354] 휴대폰 인증 서비스(SMS 발송 · 확인). null 이면 실제 PhoneVerificationService.
  static PhoneVerificationService Function()? phoneService;

  static void reset() {
    pickAndOcr = null;
    reuseOcr = null;
    currentUid = null;
    upload = null;
    readUser = null;
    finalize = null;
    mark = null;
    collectionEnabled = null;
    phoneService = null;
  }
}

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
  final PhoneVerificationService _phoneSvc =
      ForeignRegisterHooks.phoneService?.call() ?? PhoneVerificationService();
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
  // [DU378] 인증 없이 '다음'을 눌렀다 — 번호/인증번호 묶음 아래 지속 안내(편집 · 새 발송 · 성공 · 재인증 · 단계 이동 때 지움)
  bool _phoneGateShown = false;
  final _phoneGateKey = GlobalKey();
  bool _codeSending = false;
  bool _codeVerifying = false;
  /// [DU358] 지금 발송 · 확인 흐름이 묶인 번호(정규화 숫자, 발송 시작 때 정함)와 인증에 성공한 번호.
  ///   칸 값이 묶인 번호와 달라지면 그 흐름은 이 번호와 무관하다 — 보낸 상태 · 확인 결과를 쓰지 않는다.
  String? _boundPhone;
  String? _verifiedPhone;
  /// [DU358] 발송 · 확인 요청 세대. await 뒤 세대가 바뀌었으면(번호 편집 · 재발송 · 재인증) 결과를 버린다.
  int _phoneReqGen = 0;
  /// [DU363] 인증번호 확인 진행 플래그(_codeVerifying)의 소유 토큰 — 최신 확인만 플래그를 내린다.
  ///   구세대 확인이 늦게 끝나며 새 확인의 진행 · 중복 잠금을 풀던 경로(이전 확인 → 재발송 → 새 확인 → 이전 완료)를 막는다.
  int _verifyToken = 0;
  static String _normPhone(String s) => s.replaceAll(RegExp(r'\D'), '');
  String? _phoneError;
  /// [DU354] 인증번호 확인 오류는 인증번호 칸 아래에 붙인다(번호 칸 아래면 번호가 틀린 것처럼 읽힌다).
  String? _codeError;
  /// [DU354] 발송 뒤 인증번호 칸으로 포커스를 옮긴다 — autofocus 는 번호 칸이 포커스를 쥐고 있으면 듣지 않는다.
  final FocusNode _codeFocus = FocusNode();

  // ── Step 2: 문서 스캔 ─────────────────────────────────────────
  String? _imagePath; // 로컬 임시 파일 경로 (OCR 후 업로드까지 유지)
  // [SIM-PICKER-CACHE] _imagePath 를 만든 선택의 picker cache 산출물(UUID 사본·scaled_).
  //   업로드까지 그 경로를 그대로 쓰므로 **재선택·기존 이미지 재사용·화면 종료** 때만 놓는다.
  PickerCacheScope? _imagePickScope;
  bool _ocrRunning = false;
  /// [DU355] 이전에 올린 등록증을 지금 불러오는 중인가(처리 중 문구용 — 위젯 값이 아니라 실제 작업으로 정한다).
  bool _reuseRunning = false;
  /// [DU355] CASE C 재사용이 실패해 스캔 화면에 남았는가(안내용). 새 사진을 고르면(_ocrAttempted) 안내는 사라진다.
  bool _reuseFailed = false;

  /// [CASE C] 기존 Storage idCard를 재사용 중 — 재업로드 / markIdCardVerified 불필요
  bool _usingExistingIdCard = false;

  /// [B.1] Recoverable 오류 재시도 지원 — 업로드 완료된 Storage 경로 기억.
  /// finalizeForeignIdentity가 recoverable 오류로 실패해도 계정이 유지되므로
  /// 재시도 시 이미 업로드된 이미지를 재사용할 수 있다.
  /// 새 이미지가 선택되면 null로 리셋.
  String? _uploadedStoragePath;
  /// [DOC-LATE-DELETE.7 · D] 마지막 제출이 서버에서 거절된 이유. 다시 시도하거나 입력을 고치면 지운다.
  String? _submitError;

  // ── Step 3: OCR 확인 ─────────────────────────────────────────
  ForeignIdOcrResult? _ocrResult;

  /// [FULL13-REEVAL.2] 지금 사진에 대해 OCR 을 돌렸는가 / 예외로 끝났는가.
  ///   번호 OCR 값은 `_ocrResult.foreignIdRaw` 에만 둔다 — 입력 칸에 넣지 않는다.
  bool _ocrAttempted = false;
  bool _ocrThrew = false;

  /// [FULL13-REEVAL.2] 업로드 판정 근거. 예전에는 OCR 값이 곧 입력값이라
  ///   (INV-3) 무판정만 보냈다. 이제 번호는 직접 입력이므로 같은 사진의 OCR
  ///   번호를 후보로 보내 서버가 입력 번호와 대조한다. 수집이 꺼져 있으면
  ///   예전처럼 무판정만 보낸다.
  ///   [FULL13-REEVAL.3] 이름도 직접 입력이므로 입력 이름 ↔ 같은 사진의 OCR 이름
  ///   비교 결과를 함께 보낸다(서버는 이름·번호가 모두 MATCHED 일 때만 MATCHED).
  Map<String, dynamic> _markSelfCheck() => DocumentPickResult.foreignSignupSelfCheck(
        collectionEnabled: _collectionEnabled,
        ocrAttempted: _ocrAttempted,
        ocrThrew: _ocrThrew,
        ocrForeignIdRaw: _ocrResult?.foreignIdRaw,
        nameOutcome: _ocrThrew
            ? DocFieldOutcome.unassessed
            : ForeignIdOcrService.compareTypedLegalName(
                _legalNameCtrl.text, _ocrResult),
      );

  bool get _collectionEnabled =>
      ForeignRegisterHooks.collectionEnabled?.call() ??
      TaxIdentityService.collectionEnabledLocally;

  String? get _currentUid => ForeignRegisterHooks.currentUid != null
      ? ForeignRegisterHooks.currentUid!()
      : FirebaseAuth.instance.currentUser?.uid;

  /// [FULL13-REEVAL.3] [CASE C] 업로드 없이 기존 사진을 쓰는 복구 — 그 사진의 현재 버전에
  ///   묶은 근거를 가입 확정과 함께 보낸다. 수집 OFF·OCR 예외·버전 모름이면 보내지 않는다.
  Map<String, dynamic>? _existingPhotoEvidence(int? currentIdDocumentVersion) {
    if (!_usingExistingIdCard || !_collectionEnabled || !_ocrAttempted || _ocrThrew) {
      return null;
    }
    if (currentIdDocumentVersion == null || currentIdDocumentVersion <= 0) return null;
    final raw = (_ocrResult?.foreignIdRaw ?? '').replaceAll(RegExp(r'\D'), '');
    return {
      'idDocumentVersion': currentIdDocumentVersion,
      'name': ForeignIdOcrService.compareTypedLegalName(_legalNameCtrl.text, _ocrResult).wire,
      'identifierCandidates': raw.length == 13 ? [raw] : const <String>[],
    };
  }

  Future<void> _callMark(Map<String, dynamic> payload) {
    final hook = ForeignRegisterHooks.mark;
    if (hook != null) return hook(payload);
    return FirebaseFunctions.instanceFor(region: 'asia-northeast3')
        .httpsCallable('callableMarkIdCardVerified',
            options: HttpsCallableOptions(timeout: const Duration(seconds: 15)))
        .call(payload);
  }

  Future<String?> _callFinalize(String rawId, String legalName, String koreanName,
      String visaType, {Map<String, dynamic>? documentEvidence}) {
    final hook = ForeignRegisterHooks.finalize;
    if (hook != null) {
      return hook(rawId, legalName, koreanName, visaType, documentEvidence);
    }
    return AuthService().finalizeForeignIdentity(
      rawId,
      legalName: legalName.isNotEmpty ? legalName : null,
      koreanName: koreanName.isNotEmpty ? koreanName : null,
      visaType: visaType.isNotEmpty ? visaType : null,
      documentEvidence: documentEvidence,
    );
  }
  final _legalNameCtrl      = TextEditingController();
  final _rawForeignIdCtrl   = TextEditingController(); // 13자리 평문
  final _visaTypeCtrl       = TextEditingController(); // 필수
  // _stayExpiryCtrl 제거됨 — 가입 필수정보 최소화 정책 (Data Minimization)
  final _koreanNameCtrl     = TextEditingController();
  final _ocrFormKey = GlobalKey<FormState>();

  // ── finalSetup: 약관 동의 ────────────────────────────────────
  // [R7-PAYROLL-POLICY.5B] 서버가 판정한 시행 중 약관.
  EffectiveLegalTerms? _legalTerms;
  bool _termsLoading = false;

  /// 조회 실패 사유. null 이 아니면 동의할 수 없다(ERROR ≠ EMPTY).
  String? _termsError;
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
        _reuseRunning = true;
        _tryReuseExistingIdCard(widget.existingIdCardPath!);
      }
    }
  }

  /// 들고 있던 선택의 picker 산출물을 놓는다 — 그 경로를 더 쓰지 않을 때만 부른다.
  void _releaseHeldPick() {
    final s = _imagePickScope;
    _imagePickScope = null;
    if (s != null) unawaited(s.release());
  }

  /// 새 선택을 _imagePath 로 채택한다. 이전 선택의 산출물은 이제 아무도 쓰지 않는다.
  void _adoptPickedImage(String path, PickerCacheScope scope) {
    _releaseHeldPick();
    _imagePickScope = scope;
    _imagePath = path;
  }

  @override
  void dispose() {
    _releaseHeldPick();
    _scrollCtrl.dispose();
    _usernameCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmCtrl.dispose();
    _phoneCtrl.dispose();
    _codeCtrl.dispose();
    _codeFocus.dispose();
    _legalNameCtrl.dispose();
    _rawForeignIdCtrl.dispose();
    _visaTypeCtrl.dispose();
    _koreanNameCtrl.dispose();
    super.dispose();
  }

  /// [R7-PAYROLL-POLICY.5B] 서버가 **지금 시행 중**이라고 답한 약관만 쓴다.
  ///
  /// 실패하면 기본값으로 대체하지 않는다 — 발행되지 않은 글을 현재 약관처럼
  /// 보여 주고 동의를 받으면, 그 동의는 사용자가 본 글을 가리키지 않는다.
  Future<void> _loadTerms({bool resetChoices = false}) async {
    setState(() {
      _termsLoading = true;
      _termsError = null;
      // [DU359] 시행본이 바뀌었다(reset) — 고른 것과 열람 표시를 조회를 기다리기 **전에** 지운다.
      //   성공 분기에서만 지우면 재조회가 실패/필수 0 일 때 reset 의도가 사라지고, 뒤의 일반 재시도 성공에서
      //   같은 ID 새 버전에 이전 열람 표시가 남아 새 글을 열지 않고 체크할 수 있었다(소급 11 P1).
      if (resetChoices) {
        _consentMap.clear();
        _viewedTermIds.clear();
      }
    });
    try {
      final terms = await _legalTermsService.fetchEffectiveTerms();
      if (!mounted) return;
      if (!terms.hasRequiredItems) {
        setState(() {
          _legalTerms = null;
          _termsLoading = false;
          _termsError = '약관 정보가 완전하지 않습니다.\n잠시 후 다시 시도해 주세요.';
        });
        return;
      }
      setState(() {
        _legalTerms = terms;
        // [DU359] reset 의 동의 · 열람 지움은 조회 전으로 옮겼다(위). 여기서는 새 항목을 미동의로 둔다.
        for (final item in terms.activeItems) {
          _consentMap[item.id] = false;
        }
        _termsLoading = false;
      });
    } catch (e) {
      debugPrint('⚠️ [ForeignReg] 시행 중 약관 조회 실패: $e');
      if (!mounted) return;
      setState(() {
        _legalTerms = null;
        _termsLoading = false;
        _termsError = '약관을 불러오지 못했어요.\n네트워크를 확인하고 다시 시도해 주세요.';
      });
    }
  }

  // ============================================================
  // 탐색 헬퍼
  // ============================================================

  void _goTo(_Step step) {
    setState(() {
      _step = step;
      _phoneGateShown = false; // [DU378]
    });
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
    final gen = ++_phoneReqGen; // [DU358] 이 발송의 세대 — 진행 중이던 확인 결과는 버린다
    final bound = _normPhone(phone);
    _verifyToken++; // [DU363] 진행 중이던 확인은 더 이상 플래그 소유자가 아니다
    setState(() { _codeSending = true; _phoneError = null; _boundPhone = bound; _codeVerifying = false; _phoneGateShown = false; });
    try {
      await _phoneSvc.sendCode(phone);
      if (!mounted) return;
      if (gen != _phoneReqGen || _normPhone(_phoneCtrl.text) != bound) {
        // [DU358] 발송 중 번호가 바뀌었다 — 이 발송은 지금 번호와 무관하다(보낸 상태를 켜지 않는다)
        setState(() => _codeSending = false);
        return;
      }
      setState(() { _codeSent = true; _codeSending = false; _codeCtrl.clear(); _codeError = null; });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _codeSent && !_phoneVerified) _codeFocus.requestFocus();
      });
      ToastHelper.showSuccess('인증번호가 발송되었습니다');
    } catch (e) {
      if (!mounted) return;
      if (gen != _phoneReqGen) {
        setState(() => _codeSending = false); // [DU358] 이미 무효가 된 발송의 실패 — 지금 번호 칸에 오류를 붙이지 않는다
        return;
      }
      final code = e is FirebaseAuthException ? e.code : e.runtimeType.toString();
      debugPrint('❌ [_sendCode] 에러($code): $e');
      // [DU354] 진단 코드는 로그에만 남기고, 화면에는 내국인 가입(register_screen)과 같은 안내를 보인다.
      setState(() {
        _codeSending = false;
        _phoneError = switch (code) {
          'too-many-requests'    => '잠시 후 다시 시도해주세요',
          'invalid-phone-number' => '올바른 휴대폰 번호를 입력해주세요',
          'quota-exceeded'       => '인증번호 발송 횟수를 초과했습니다. 잠시 후 다시 시도해주세요',
          _                      => '발송에 실패했습니다. 다시 시도해주세요',
        };
      });
    }
  }

  Future<void> _verifyCode() async {
    if (_codeVerifying) return;
    final code = _codeCtrl.text.trim();
    if (code.length != 6) return;
    // [DU358] 보낸 번호와 지금 칸 값이 같을 때만 확인한다(다르면 보낸 상태가 이미 무효다)
    final bound = _boundPhone;
    if (!_codeSent || bound == null || _normPhone(_phoneCtrl.text) != bound) return;
    final gen = _phoneReqGen;
    final my = ++_verifyToken; // [DU363] 이 확인이 진행 플래그의 소유자다
    setState(() { _codeVerifying = true; _codeError = null; });
    try {
      final result = await _phoneSvc.verifyCode(_phoneCtrl.text.trim(), code);
      if (!mounted) return;
      if (my != _verifyToken) return; // [DU363] 더 새 확인 · 무효화가 소유권을 가져갔다 — 플래그를 건드리지 않는다
      if (gen != _phoneReqGen || _normPhone(_phoneCtrl.text) != bound) {
        // [DU358] 확인 중 번호 편집 · 재발송 · 재인증이 있었다 — 늦게 온 결과를 쓰지 않는다
        setState(() => _codeVerifying = false);
        return;
      }
      if (result.valid) {
        setState(() { _phoneVerified = true; _verifiedPhone = bound; _codeVerifying = false; _codeError = null; _phoneGateShown = false; });
        ToastHelper.showSuccess('휴대폰 인증이 완료되었습니다');
      } else {
        final msg = switch (result.reason) {
          'expired' => '인증번호가 만료됐습니다. 재발송해주세요',
          'too_many_attempts' => '시도 횟수를 초과했습니다. 재발송해주세요',
          // [DU367] 확인 기준이 없다(보낸 번호와 다름 · 재발송으로 대체됨) — 숫자를 잘못 넣은 것(wrong_code)과 구별한다
          'no_code' => '인증번호를 다시 발송한 뒤 확인해주세요',
          _ => '인증번호가 일치하지 않습니다',
        };
        setState(() { _codeVerifying = false; _codeError = msg; });
        ToastHelper.showError(msg);
      }
    } catch (_) {
      if (!mounted) return;
      if (my != _verifyToken) return; // [DU363] 소유자가 아니면 플래그를 건드리지 않는다
      if (gen != _phoneReqGen) {
        setState(() => _codeVerifying = false);
        return;
      }
      setState(() { _codeVerifying = false; _codeError = '확인에 실패했습니다. 다시 시도해주세요'; });
    }
  }

  /// [DU358] 번호 칸 편집 — 지금 흐름이 묶인 번호와 달라지면 보낸 상태 · 확인 진행 · 인증번호 · 오류를 무효화한다.
  ///   발송 진행 중이면 발송 버튼은 그 응답이 올 때까지 막혀 있다(응답은 세대가 달라 버려진다).
  void _onPhoneEdited() {
    final now = _normPhone(_phoneCtrl.text);
    setState(() {
      _phoneError = null;
      _phoneGateShown = false; // [DU378]
      if (_boundPhone != null && now != _boundPhone) {
        _phoneReqGen++;
        _verifyToken++; // [DU363]
        _boundPhone = null;
        _codeSent = false;
        _codeVerifying = false;
        _codeCtrl.clear();
        _codeError = null;
      }
    });
  }

  /// [DU358] 인증에 성공한 번호와 지금 칸 값이 같은가(신규 가입 경로).
  bool get _phoneBindingOk =>
      _phoneVerified && _verifiedPhone != null && _verifiedPhone == _normPhone(_phoneCtrl.text);

  bool _validatePhone() {
    if (!_phoneBindingOk) {
      // [DU378] 토스트 → 번호/인증번호 묶음 아래 지속 안내(같은 문구). 안내 끝이 보이게 스크롤하면 바로 위 행동도 함께 보인다.
      setState(() => _phoneGateShown = true);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final ctx = _phoneGateKey.currentContext;
        if (!mounted || ctx == null) return;
        Scrollable.ensureVisible(ctx,
            duration: const Duration(milliseconds: 200),
            alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd);
      });
      return false;
    }
    return true;
  }

  /// [DU378] 휴대폰 인증 사전조건 안내 — 예전 경고 토스트와 같은 문구, OCR 일부 인식 실패 안내와 같은 경고 면.
  ///   나타날 때 낭독(liveRegion). 아이콘은 첫 줄 가운데, 글은 낱말 사이에서만 줄바꿈.
  Widget _phoneGateNotice() {
    const style = TextStyle(fontSize: 13);
    return Semantics(
      liveRegion: true,
      child: Container(
        key: _phoneGateKey,
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.warningBg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.warningLight),
        ),
        child: const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          FirstLineIcon(Icons.warning_amber, size: 18, color: AppColors.warningDark, textStyle: style),
          SizedBox(width: 8),
          Expanded(child: KeepWordsText('휴대폰 번호 인증을 완료해주세요', style: style)),
        ]),
      ),
    );
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
      final ForeignIdOcrResult result;
      final reuseHook = ForeignRegisterHooks.reuseOcr;
      if (reuseHook != null) {
        result = await reuseHook(storagePath);
      } else {
        // ① Storage에서 bytes 다운로드 (max 10MB)
        final bytes = await FirebaseStorage.instance
            .ref(storagePath)
            .getData(10 * 1024 * 1024);

        if (bytes == null || !mounted) {
          if (mounted) setState(() { _ocrRunning = false; _reuseRunning = false; _reuseFailed = true; });
          return;
        }

        // ② 임시 파일 저장 (OCR용 — 업로드 재사용 안 함)
        final dir = await getTemporaryDirectory();
        final ts = DateTime.now().millisecondsSinceEpoch;
        final tempFile = File('${dir.path}/idCard_resume_$ts.jpg');
        await tempFile.writeAsBytes(bytes);
        tempFilePath = tempFile.path;

        // ③ OCR 실행
        result = await ForeignIdOcrService.recognizeFromPath(tempFile.path);
      }

      if (!mounted) return;

      // ④ OCR 결과로 폼 초기화 (실패 필드는 '직접 입력 필요' 표시)
      _ocrResult = result;
      _ocrAttempted = true;
      _ocrThrew = false;
      // [FULL13-REEVAL.3] 영문 이름도 직접 입력 — OCR 이름은 비교 근거로만 쓴다.
      _legalNameCtrl.clear();
      // [FULL13-REEVAL.2] 번호는 직접 입력받는다 — OCR 값을 칸에 넣으면
      //   같은 사진과의 대조가 자기 대조가 된다.
      _rawForeignIdCtrl.clear();
      _visaTypeCtrl.text = result.visaType ?? '';
      // stayExpiryDate — 가입 필수정보 최소화 정책으로 수집 안 함
      _koreanNameCtrl.clear();
      _releaseHeldPick();         // 이전에 고른 사진은 더 쓰지 않는다
      _imagePath = null;          // 재업로드 없음
      _uploadedStoragePath = null; // [B.1] 기존 Storage 경로가 있어도 이 흐름에서는 무관
      _usingExistingIdCard = true;

      setState(() {
        _ocrRunning = false;
        _reuseRunning = false;
        _step = _Step.ocrConfirm;
      });

      debugPrint('✅ [ForeignReg CASE C] 기존 idCard 재사용 성공 → ocrConfirm');
    } catch (e) {
      debugPrint('⚠️ [ForeignReg CASE C] 기존 idCard 재사용 실패 → documentScan 유지: $e');
      if (mounted) setState(() { _ocrRunning = false; _reuseRunning = false; _reuseFailed = true; });
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
    final pickHook = ForeignRegisterHooks.pickAndOcr;
    if (pickHook != null) {
      // [FULL13-REEVAL.3] 시험 경로 — 실제 경로와 같은 상태 전이(번호·이름 칸은 비움).
      setState(() => _ocrRunning = true);
      final r = await pickHook();
      if (!mounted) return;
      _imagePath = r.path;
      _ocrAttempted = true;
      _ocrThrew = r.result == null;
      _ocrResult = r.result ?? const ForeignIdOcrResult(
        legalNameFailed: true, foreignIdFailed: true, visaTypeFailed: true,
      );
      _legalNameCtrl.clear();
      _rawForeignIdCtrl.clear();
      _visaTypeCtrl.text = _ocrResult?.visaType ?? '';
      _koreanNameCtrl.clear();
      _uploadedStoragePath = null;
      _submitError = null;
      setState(() => _ocrRunning = false);
      _goTo(_Step.ocrConfirm);
      return;
    }
    final picker = ImagePicker();
    final scope = await PickerCacheScope.begin();
    final picked = await picker.pickImage(source: source, imageQuality: 90, maxWidth: 2000);
    await scope.capture(picked?.path);
    if (picked == null || !mounted) {
      await scope.release();
      return;
    }

    setState(() { _ocrRunning = true; });

    try {
      final result = await ForeignIdOcrService.recognizeFromPath(picked.path);
      if (!mounted) {
        await scope.release(); // 채택되지 않은 선택
        return;
      }

      // OCR 결과로 확인 폼 초기화
      _ocrResult = result;
      _ocrAttempted = true;
      _ocrThrew = false;
      // [FULL13-REEVAL.3] 영문 이름도 직접 입력 — OCR 이름은 비교 근거로만 쓴다.
      _legalNameCtrl.clear();
      // [FULL13-REEVAL.2] 번호는 직접 입력받는다(OCR 값은 대조 근거로만 쓴다).
      _rawForeignIdCtrl.clear();
      _visaTypeCtrl.text = result.visaType ?? '';
      // stayExpiryDate — 가입 필수정보 최소화 정책으로 수집 안 함
      _koreanNameCtrl.clear();
      _adoptPickedImage(picked.path, scope);
      _uploadedStoragePath = null; // [B.1] 새 이미지 선택 → 이전 업로드 경로 무효화 · 이전 거절 사유도 지운다
      _submitError = null;

      setState(() => _ocrRunning = false);
      _goTo(_Step.ocrConfirm);
    } catch (e) {
      debugPrint('❌ [ForeignReg] OCR 실패: $e');
      if (!mounted) {
        await scope.release(); // 채택되지 않은 선택
        return;
      }
      // OCR 예외 → 모든 필드 수동 입력 허용
      _ocrResult = const ForeignIdOcrResult(
        legalNameFailed: true, foreignIdFailed: true, visaTypeFailed: true,
      );
      _ocrAttempted = true;
      _ocrThrew = true;
      _legalNameCtrl.clear();
      _rawForeignIdCtrl.clear();
      _visaTypeCtrl.clear();
      _adoptPickedImage(picked.path, scope);
      _uploadedStoragePath = null; // [B.1] 새 이미지 선택 → 이전 업로드 경로 무효화 · 이전 거절 사유도 지운다
      _submitError = null;

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
    setState(() {
      _isBusy = true;
      _submitError = null; // [DOC-LATE-DELETE.7 · D] 새 시도 — 이전 거절 사유를 지운다
    });

    final rawId = _rawForeignIdCtrl.text.trim().replaceAll(RegExp(r'\D'), '');
    final legalName = _legalNameCtrl.text.trim();
    // [R8-P3B.3B] 한국식 이름은 finalizeForeignIdentity(CF)로 넘겨 저장한다.
    //   users 문서 직접 update는 [PII-B4-R1.4.3] denylist에 막혀 항상 실패했다.
    final koreanName = _koreanNameCtrl.text.trim();
    final visaType = _visaTypeCtrl.text.trim();
    final imagePath = _imagePath;

    // [PII-B4-R1.3A] 진입점 추적 — 식별정보를 로그 문자열로 구성하지 않는다.
    //
    //   이전에는 등록번호 앞 8자리와 실명이 같은 줄에 있었다. 13자리 중
    //   마지막은 체크섬이므로 8자리를 주면 남는 것은 4자리뿐이고, 실명이
    //   옆에 붙어 있으면 그 4자리는 사실상 지켜지지 않는다.
    //
    //   debugPrint는 릴리스 빌드에서 제거되지 않는다. 그래서 kDebugMode로
    //   감싸는 것으로 끝내지 않고 **값 자체를 만들지 않는다**. (§3·§4)
    final dbgCurrentUid = _currentUid;
    debugPrint('🔷 [ForeignReg] _processRegistration 시작 | isResume=${widget.isResume} | existingAuth=${dbgCurrentUid ?? "null"} | idLen=${rawId.length} | hasLegalName=${legalName.isNotEmpty} | imagePath=${imagePath != null}');

    // ================================================================
    // [RESUME MODE] 기존 uid 유지 — 새 Auth 계정 생성 금지
    // ================================================================
    if (widget.isResume) {
      final uid = _currentUid;
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
      // [DOC-LATE-DELETE.7 · D] 같은 사진으로 다시 시도하면 이미 올린 객체를 다시 쓴다
      //   (신규 가입 흐름의 재시도 계약과 같다). 예전에는 가입 확정이 거절될 때마다
      //   새로 올려 쓰지 않는 사진이 쌓였다. 새 사진을 고르면 _pickAndOcr 가 지운다.
      if (!_usingExistingIdCard && imagePath != null && _uploadedStoragePath != null) {
        uploadedPath = _uploadedStoragePath;
      } else if (!_usingExistingIdCard && imagePath != null) {
        try {
          final ts = DateTime.now().millisecondsSinceEpoch;
          final storagePath = 'users/$uid/idCard_$ts.jpg';
          final uploadHook = ForeignRegisterHooks.upload;
          if (uploadHook != null) {
            await uploadHook(imagePath, storagePath);
          } else {
            final ref = FirebaseStorage.instance.ref(storagePath);
            await ref.putFile(File(imagePath), _idCardUploadMetadata(imagePath));
          }
          uploadedPath = storagePath;
          _uploadedStoragePath = storagePath;
        } catch (e) {
          debugPrint('⚠️ [ForeignReg resume] 이미지 업로드 실패: $e');
        }
      }

      // ── ② Firestore에서 fingerprint 존재 여부 확인 ───────────────
      //    fingerprint가 없으면 finalizeForeignIdentity 호출
      //    fingerprint가 있으면 이미 완료 — skip (idempotent 보장)
      bool hasFingerprint = false;
      // [R8-P3B.3B] 같은 읽기에서 koreanName도 같이 본다 — 추가 왕복 없음.
      //   fingerprint가 이미 있으면 신원은 확정된 것이라 finalize를 건너뛰었는데,
      //   그러면 사용자가 이번에 입력한 한국식 이름이 어디에도 저장되지 않는다.
      //   (예전에는 그 자리를 users 직접 update가 메우려 했고, 그건 항상 실패했다.)
      //   저장할 이름이 실제로 달라졌을 때만 finalize를 부른다.
      String? storedKoreanName;
      // [FULL13-REEVAL.3] CASE C 근거를 현재 문서 버전에 묶기 위해 같은 읽기에서 본다.
      int? storedIdDocumentVersion;
      try {
        final readHook = ForeignRegisterHooks.readUser;
        final data = readHook != null
            ? await readHook(uid)
            : (await FirebaseFirestore.instance.collection('users').doc(uid).get()).data();
        hasFingerprint = data?['foreignIdentityFingerprint'] != null;
        storedKoreanName = data?['koreanName'] as String?;
        storedIdDocumentVersion = (data?['idDocumentVersion'] as num?)?.toInt();
      } catch (e) {
        debugPrint('⚠️ [ForeignReg resume] Firestore 읽기 실패 — finalize 시도: $e');
        // 읽기 실패 시 finalize 호출로 폴백 (CF 내부에서 중복 방지)
      }

      if (!mounted) return;

      final koreanNameNeedsSave =
          koreanName.isNotEmpty && koreanName != storedKoreanName;

      if (!hasFingerprint || koreanNameNeedsSave) {
        final finalizeErr = await _callFinalize(
          rawId, legalName, koreanName, visaType,
          // [FULL13-REEVAL.3] CASE C(업로드 없음)일 때만 — 새 사진은 아래 업로드 판정이 본다.
          documentEvidence: _existingPhotoEvidence(storedIdDocumentVersion),
        );
        if (!mounted) return;
        if (finalizeErr != null) {
          setState(() {
            _isBusy = false;
            _submitError = finalizeErr;
          });
          ToastHelper.showError(finalizeErr);
          return;
        }
      }

      // ── ③ callableMarkIdCardVerified (이미 있으면 CF가 갱신) ──────
      if (uploadedPath != null) {
        try {
          await _callMark({
            'storagePath': uploadedPath,
            // [FULL13-REEVAL.2] 번호는 직접 입력, OCR 번호는 후보로만(_markSelfCheck).
            'selfCheck': _markSelfCheck(),
          });
        } catch (e) {
          debugPrint('⚠️ [ForeignReg resume] markIdCardVerified 실패 (재시도 가능): $e');
        }
      }

      // 임시 파일 정리 ([CASE C] _usingExistingIdCard 시 임시파일 없음 — _tryReuseExistingIdCard에서 정리 완료)
      if (!_usingExistingIdCard && imagePath != null) {
        try { await File(imagePath).delete(); } catch (_) {}
      }

      // [R8-P3B.3B] koreanName 직접 write 제거.
      //   여기 있던 users 문서 update는 [PII-B4-R1.4.3] denylist('koreanName')에
      //   막혀 **한 번도 성공한 적이 없다**. try/catch가 "치명적 아님"으로 삼켜서
      //   실패가 드러나지 않았고, 고치려던 버그(재개 가입에서 한국식 이름 누락)는
      //   그대로 남아 있었다. 게다가 매번 실패하는 왕복이 한 번 더 붙었다.
      //   이제 위 finalizeForeignIdentity(CF)가 저장한다 — 왕복은 1회 줄었다.

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

  /// [DU356] 마지막 단계 진행을 막을 이유(지역 · 약관 준비 · 필수 동의), 통과면 null — 진행 · '가입 완료' 활성 · writer 직전이 모두 이것 하나를 본다.
  ///   예전 판정은 `_legalTerms?.… ?? []` 로 시작해 약관 로딩 · 실패 · 필수 0 일 때 빈 목록 every = true 가 되어
  ///   '가입 완료' 가 켜지고 진행이 통과했다(내국인 C0-TERMS-SUBMIT-GUARD 와 같은 결함, 소급 9 채택 범위).
  String? _finalSetupBlockReason() {
    if (widget.role == UserRole.USER && _homeRegion == null) return '주로 일할 지역을 선택해주세요';
    return termsSubmitBlockReason(
        loading: _termsLoading, error: _termsError, terms: _legalTerms, consent: _consentMap);
  }

  bool _validateFinalSetup() {
    final reason = _finalSetupBlockReason();
    if (reason != null) {
      ToastHelper.showWarning(reason);
      return false;
    }
    return true;
  }

  bool get _isFinalSetupComplete => _finalSetupBlockReason() == null;

  // ================================================================
  // FRESH 신규 가입 최종 커밋 — finalSetup '가입 완료' 버튼에서 실행
  //   signUp → Storage → finalizeForeignIdentity → markIdCard
  //   → koreanName → region → termsConsent → active
  // ================================================================
  Future<void> _commitFreshRegistration() async {
    if (_isBusy) return;
    // [DU356] writer 직전에도 같은 판정 — 진행 버튼 밖 경로로 들어와도 약관 준비 · 필수 동의 없이 가입을 시작하지 않는다.
    if (!_validateFinalSetup()) return;
    // [DU358] 저장할 번호(authPhone · otp_verified)가 인증에 성공한 번호와 같을 때만 가입을 시작한다.
    if (!_phoneBindingOk) {
      ToastHelper.showWarning('휴대폰 번호 인증을 다시 완료해주세요');
      return;
    }
    setState(() {
      _isBusy = true;
      _submitError = null; // [DOC-LATE-DELETE.7 · D] 새 시도 — 이전 거절 사유를 지운다
    });

    // Draft 값 먼저 읽기 (async gap 이전)
    final rawId = _rawForeignIdCtrl.text.trim().replaceAll(RegExp(r'\D'), '');
    final legalName = _legalNameCtrl.text.trim();
    final visaType = _visaTypeCtrl.text.trim();
    final imagePath = _imagePath;
    final koreanName = _koreanNameCtrl.text.trim();
    final phone = _phoneCtrl.text.trim();
    final role = widget.role;

    // [PII-B4-R1.3A] 등록번호 앞 8자리 제거 — 길이만 남긴다. (§3)
    debugPrint('🔷 [ForeignReg] _commitFreshRegistration 시작 | idLen=${rawId.length}');

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
            await FirebaseStorage.instance.ref(retryPath).putFile(File(imagePath), _idCardUploadMetadata(imagePath));
            _uploadedStoragePath = retryPath;
          } catch (e) {
            debugPrint('⚠️ [ForeignReg commit retry] 이미지 업로드 실패: $e');
          }
        }
        final finalizeErr = await AuthService().finalizeForeignIdentity(
          rawId,
          legalName: legalName.isNotEmpty ? legalName : null,
          koreanName: koreanName.isNotEmpty ? koreanName : null,
          visaType: visaType.isNotEmpty ? visaType : null,
        );
        if (!mounted) return;
        if (finalizeErr != null) {
          setState(() {
            _isBusy = false;
            _submitError = finalizeErr;
          });
          ToastHelper.showError(finalizeErr);
          return;
        }
        if (_uploadedStoragePath != null) {
          try {
            await FirebaseFunctions.instanceFor(region: 'asia-northeast3')
                .httpsCallable('callableMarkIdCardVerified',
                    options: HttpsCallableOptions(timeout: const Duration(seconds: 15)))
                .call({
                  'storagePath': _uploadedStoragePath,
                  // [FULL13-REEVAL.2] 위와 같다(_markSelfCheck).
                  'selfCheck': _markSelfCheck(),
                });
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

      // [PII-B4-R1.3A] sentinelId는 등록번호 앞 7자리에서 파생된 값이다.
      //   Firestore에 저장되는 값이라 해도 로그로 흘릴 이유는 없다. (§3)
      debugPrint('🔷 [ForeignReg commit] signUp() 호출');
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
          await FirebaseStorage.instance.ref(storagePath).putFile(File(imagePath), _idCardUploadMetadata(imagePath));
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
        koreanName: koreanName.isNotEmpty ? koreanName : null,
        visaType: visaType.isNotEmpty ? visaType : null,
      );
      if (!mounted) return;
      if (finalizeErr != null) {
        setState(() {
          _isBusy = false;
          _submitError = finalizeErr;
        });
        ToastHelper.showError(finalizeErr);
        return;
      }

      // ── callableMarkIdCardVerified ───────────────────────────
      if (uploadedPath != null) {
        try {
          await FirebaseFunctions.instanceFor(region: 'asia-northeast3')
              .httpsCallable('callableMarkIdCardVerified',
                  options: HttpsCallableOptions(timeout: const Duration(seconds: 15)))
              .call({
                'storagePath': uploadedPath,
                // [FULL13-REEVAL.2] 예전(INV-3)에는 OCR 값이 곧 입력값이라 무판정만
                //   보냈다. 이제 번호는 직접 입력이므로 같은 사진의 OCR 번호를
                //   후보로 보낸다. 수집 OFF 면 여전히 무판정이다.
                'selfCheck': _markSelfCheck(),
              });
        } catch (e) {
          debugPrint('⚠️ [ForeignReg commit] markIdCardVerified 실패: $e');
        }
      }

      // ── 임시 파일 정리 ────────────────────────────────────────
      if (imagePath != null) {
        try { await File(imagePath).delete(); } catch (_) {}
      }

      // [R8-P3B.3B] koreanName 직접 write 제거 — 위 finalizeForeignIdentity(CF)가 저장한다.
      //   여기 있던 update는 denylist에 막혀 항상 실패했고, 실패 왕복만 한 번 더 붙었다.
    }

    // ── region + terms → active (fresh + retry 공통) ─────────────
    // [DOC-LATE-DELETE.7 · D] _finalizeRegistration 은 진행 중이면 바로 돌아간다. 여기까지 _isBusy 가
    //   true 로 남아 있어 약관 동의·활성화가 한 번도 실행되지 않고 "처리 중"에 멈췄다(기기 실측).
    if (!mounted) return;
    setState(() => _isBusy = false);
    await _finalizeRegistration();
  }


  // ============================================================
  // Step 5 (USER) 또는 최종: recordTermsConsent → active
  // ============================================================

  /// [DOC-LATE-DELETE.7 · D] 신분증 사진 업로드 형식을 명시한다. 메타데이터 없이 putFile 하면 Android SDK 가
  ///   file:// 에서 형식을 못 찾아 형식 없는 업로드가 되고, Storage 규칙(isImageType)이 거절한다(에뮬레이터 실측).
  ///   문서 관리 화면(StorageService)은 이미 형식을 지정한다 — 같은 방식으로 맞춘다.
  SettableMetadata _idCardUploadMetadata(String localPath) => SettableMetadata(contentType: switch (localPath.split('.').last.toLowerCase()) {
        'png' => 'image/png',
        'webp' => 'image/webp',
        'heic' || 'heif' => 'image/heic',
        _ => 'image/jpeg',
      });

  Future<void> _finalizeRegistration() async {
    if (_isBusy) return;
    // [DU356] writer(지역 저장 · 동의 기록) 직전에도 같은 판정.
    if (!_validateFinalSetup()) return;
    setState(() => _isBusy = true);

    // [DU359 seam] 위 _processRegistration 과 같은 uid 출처(시험 주입 없으면 FirebaseAuth.currentUser — 운영 동작 같음)
    final uid = _currentUid;
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
      } catch (e) {
        // [R7-PAYROLL-POLICY.5B] 약관이 바뀐 것은 네트워크 오류가 아니다.
        //   같은 payload 로 재시도하면 영원히 실패한다. 새 글을 보여 주고
        //   고른 것을 지우고 다시 고르게 한다 — 자동 승격하지 않는다.
        if (LegalTermsService.isTermsVersionStale(e)) {
          debugPrint('⚠️ [ForeignReg] 동의 제출 중 약관 시행본이 바뀌었다');
          if (!mounted) return;
          await _loadTerms(resetChoices: true);
          if (!mounted) return;
          setState(() => _isBusy = false);
          ToastHelper.showWarning(
              '약관이 변경되었습니다.\n변경된 내용을 확인하고 다시 동의해 주세요.');
          return;
        }
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
        bottomNavigationBar: _phoneStepToastAvoid(SafeArea(
          top: false,
          child: _buildBottomButtons(theme),
        )),
      ),
    );
  }

  // [DU370] 휴대폰 단계에서 토스트가 하단 '다음'을 덮었다 — 그 단계의 고정 '다음' 영역만 회피 영역으로 등록한다
  //   (DU1 구현57 F56-1 공용 부품, 소급 14 §2-4 좁은 후속). 다른 단계 · 공용 토스트 위치 규칙은 그대로다.
  Widget _phoneStepToastAvoid(Widget bar) => _step == _Step.phone ? ToastAvoidArea(child: bar) : bar;

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
          // [DU1 구현47 S001] 실측 뒤로 터치 32.3×32.3(320·2.0) — 기준 48. 아이콘 크기는 그대로, 누르는 영역만 최소 48×48
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _handleBack,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
              child: Padding(
                padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 8)),
                child: Icon(
                  Icons.arrow_back,
                  color: AppColors.textPrimary,
                  size: ResponsiveHelper.iconSize(context, 22),
                ),
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
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        // [DOC-LATE-DELETE.7 · D] 서버가 거절한 이유를 토스트로만 흘려보내지 않는다 —
        //   같은 단계에 남아 다시 시도하거나 새 사진을 고를 때까지 보인다.
        if (_submitError != null)
          Container(
            key: const ValueKey('foreign-submit-error'),
            width: double.infinity,
            margin: EdgeInsets.only(bottom: ResponsiveHelper.spacing(context, 10)),
            padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 12)),
            decoration: BoxDecoration(
              color: AppColors.errorBg,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.errorLight),
            ),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Icon(Icons.error_outline, color: AppColors.errorDark, size: 18),
              const SizedBox(width: 8),
              Expanded(child: Text(_submitError!,
                  style: ResponsiveHelper.bodyStyle(context).copyWith(color: AppColors.errorDark))),
            ]),
          ),
        SizedBox(
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
      ]),
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
          child: _buildPhoneVerifiedBody(),
        ),
      ] else ...[
        _buildLabel('휴대폰 번호', Icons.phone_outlined),
        _buildFieldWithAction(
          hint: '010-0000-0000',
          actionLabels: const ['인증번호 받기', '재발송'],
          field: TextField(
            controller: _phoneCtrl,
            keyboardType: TextInputType.phone,
            decoration: InputDecoration(
              hintText: '010-0000-0000',
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              error: _fieldError(_phoneError),
            ),
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            onChanged: (_) => _onPhoneEdited(),
          ),
          action: ElevatedButton(
            onPressed: _codeSending ? null : _sendCode,
            style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14)),
            child: _codeSending
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : Text(_codeSent ? '재발송' : '인증번호 받기'),
          ),
        ),

        if (_codeSent) ...[
          const SizedBox(height: 12),
          _buildFieldWithAction(
            hint: '인증번호 6자리',
            actionLabels: const ['확인'],
            field: TextField(
              controller: _codeCtrl,
              focusNode: _codeFocus,
              keyboardType: TextInputType.number,
              maxLength: 6,
              autofocus: true,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              onChanged: (v) {
                if (_codeError != null) setState(() => _codeError = null);
                if (v.length == 6) _verifyCode();
              },
              decoration: InputDecoration(
                hintText: '인증번호 6자리',
                counterText: '',
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                error: _fieldError(_codeError),
              ),
            ),
            action: ElevatedButton(
              onPressed: _codeVerifying ? null : _verifyCode,
              style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14)),
              child: _codeVerifying
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('확인'),
            ),
          ),
        ],
        // [DU378] 인증 없이 '다음' → 묶음 바로 아래 지속 안내(발송 전 '인증번호 받기' · 발송 뒤 '확인'과 함께 보인다)
        if (_phoneGateShown) ...[
          const SizedBox(height: 12),
          _phoneGateNotice(),
        ],
      ],
    ]);
  }

  /// [DU354 r2] 칸 오류 안내 — 낱말 단위 줄바꿈(B 에서 '입|력해주세요' 음절 끊김), 읽기는 원문.
  ///   모양은 M3 기본 오류 글과 같다(bodySmall · colorScheme.error, 앱 테마에 errorStyle 덮어쓰기 없음). 줄 수 제한 없음.
  Widget? _fieldError(String? msg) {
    if (msg == null) return null;
    final theme = Theme.of(context);
    return Text(
      TextLayout.keepWords(msg),
      semanticsLabel: msg,
      style: (theme.textTheme.bodySmall ?? const TextStyle()).copyWith(color: theme.colorScheme.error),
    );
  }

  /// [DU354] 입력 칸 + 옆 버튼. 칸이 예시 글(hint)을 다 보이지 못할 만큼 좁으면(큰 글자 · 좁은 화면)
  ///   버튼을 칸 아래 전체 폭으로 내린다 — 칸이 몇 글자만 보이고 오류 안내가 사라지던 문제(320 · 2.0).
  ///   잴 때 글자 배율 · 버튼 글자 스타일(테마) · 칸 글자 스타일 · 안쪽 여백(12×2)을 쓴다.
  Widget _buildFieldWithAction({
    required String hint,
    required List<String> actionLabels,
    required Widget field,
    required Widget action,
  }) {
    return LayoutBuilder(builder: (context, cons) {
      final theme = Theme.of(context);
      final scaler = MediaQuery.textScalerOf(context);
      final dir = Directionality.of(context);
      final base = DefaultTextStyle.of(context).style;
      double widthOf(String text, TextStyle style) {
        final tp = TextPainter(
          text: TextSpan(text: text, style: style),
          textDirection: dir,
          textScaler: scaler,
          maxLines: 1,
        )..layout();
        final w = tp.width;
        tp.dispose();
        return w;
      }

      final actionStyle = base.merge(theme.elevatedButtonTheme.style?.textStyle?.resolve(const <WidgetState>{}));
      final fieldStyle = base.merge(theme.textTheme.bodyLarge);
      var labelW = 0.0;
      for (final l in actionLabels) {
        final w = widthOf(l, actionStyle);
        if (w > labelW) labelW = w;
      }
      final actionW = (labelW + 32) < 64 ? 64.0 : labelW + 32; // 좌우 16 · 테마 최소 폭 64
      final fieldMinW = widthOf(hint, fieldStyle) + 24 + 4; // 안쪽 여백 12×2 + 테두리
      if (cons.maxWidth - 8 - actionW >= fieldMinW) {
        return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: field),
          const SizedBox(width: 8),
          action,
        ]);
      }
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        field,
        const SizedBox(height: 8),
        action,
      ]);
    });
  }

  /// [DU354] 인증 완료 카드 — 번호는 표시 형식(010-1234-5678, 저장값은 그대로)으로 보이고,
  ///   번호가 '재인증' 옆 한 줄에 다 들어가지 않으면 '재인증' 을 아래 오른쪽으로 내린다(숫자 중간 줄바꿈 방지).
  Widget _buildPhoneVerifiedBody() {
    final shown = FormatHelper.formatPhone(_phoneCtrl.text);
    final reauth = TextButton(
      // [DU358] 재인증 — 진행 중 결과도 버리고 묶인 번호 · 인증 번호를 지운다
      onPressed: () => setState(() {
        _phoneReqGen++;
        _verifyToken++; // [DU363]
        _phoneVerified = false;
        _verifiedPhone = null;
        _boundPhone = null;
        _codeSent = false;
        _codeVerifying = false;
        _codeCtrl.clear();
        _codeError = null;
        _phoneGateShown = false; // [DU378]
      }),
      child: const Text('재인증'),
    );
    final numberStyle = ResponsiveHelper.bodyStyle(context);
    return LayoutBuilder(builder: (context, cons) {
      final theme = Theme.of(context);
      final scaler = MediaQuery.textScalerOf(context);
      final dir = Directionality.of(context);
      final base = DefaultTextStyle.of(context).style;
      double widthOf(String text, TextStyle style) {
        final tp = TextPainter(
          text: TextSpan(text: text, style: style),
          textDirection: dir,
          textScaler: scaler,
          maxLines: 1,
        )..layout();
        final w = tp.width;
        tp.dispose();
        return w;
      }

      final reauthStyle = base.merge(theme.textButtonTheme.style?.textStyle?.resolve(const <WidgetState>{}) ??
          theme.textTheme.labelLarge);
      final reauthW = (widthOf('재인증', reauthStyle) + 24) < 64 ? 64.0 : widthOf('재인증', reauthStyle) + 24;
      final numberW = widthOf(shown, base.merge(numberStyle));
      final info = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('인증 완료', style: ResponsiveHelper.smallStyle(context, color: AppColors.successDark, fontWeight: FontWeight.w600)),
        Text(shown, semanticsLabel: shown, style: numberStyle),
      ]);
      const icon = Icon(Icons.check_circle, color: AppColors.success);
      final iconW = IconTheme.of(context).size ?? 24;
      if (cons.maxWidth - iconW - 10 - reauthW >= numberW) {
        return Row(children: [icon, const SizedBox(width: 10), Expanded(child: info), reauth]);
      }
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [icon, const SizedBox(width: 10), Expanded(child: info)]),
        Align(alignment: Alignment.centerRight, child: reauth),
      ]);
    });
  }

  String get _ocrRunningMsg =>
      _reuseRunning ? '이전에 등록한 외국인등록증을 불러오는 중...' : '이미지 인식 중...';

  static const String _kReuseFailed =
      '이전에 올린 외국인등록증을 불러오지 못했습니다. 다시 촬영하거나 갤러리에서 선택해주세요.';

  // [DU349] OCR 목적 안내 — 문구 그대로. 화면용은 낱말 단위 + '·' 뒤 줄바꿈(긴 괄호 낱말이 음절로 갈리지 않게).
  static const String _kOcrPurposeRaw = 'OCR로 성명·번호·체류자격 등 정보를 자동으로 인식합니다. '
      '인식된 내용은 다음 화면에서 직접 확인하고 수정할 수 있습니다.';
  static final String _kOcrPurpose =
      TextLayout.keepWords(_kOcrPurposeRaw).replaceAll('·\u2060', '·\u200B');

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
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Row(children: [
            Icon(Icons.info_outline, size: 15, color: AppColors.grey600),
            SizedBox(width: 6),
            Text('입력 보조 수단', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.grey700)),
          ]),
          const SizedBox(height: 6),
          // [DU349] 본문 grey600(안내 면 위 4.28) → textSecondary, 낱말 단위 · '·' 뒤 줄바꿈 허용(문구 그대로)
          Text(
            _kOcrPurpose,
            semanticsLabel: _kOcrPurposeRaw,
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
        ]),
      ),
      const SizedBox(height: 24),

      if (_ocrRunning) ...[
        Center(child: Column(children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          // [CASE C] 기존 idCard 재사용 시도 중 vs. 신규 OCR 실행 중 구분
          // [DU355] 위젯 값이 아니라 지금 하는 작업으로 고른다(재사용 실패 뒤 새 사진 인식에 '이전…' 이 보이던 문제), 낱말 줄바꿈 · 가운데
          Text(TextLayout.keepWords(_ocrRunningMsg), semanticsLabel: _ocrRunningMsg, textAlign: TextAlign.center),
        ])),
      ] else ...[
        // [DU355] CASE C 재사용 실패 — 말없이 돌아오지 않고 다시 고르게 안내한다(새 사진을 고르면 사라진다).
        if (_reuseFailed && !_ocrAttempted) ...[
          Container(
            key: const ValueKey('foreign-reuse-failed'),
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.infoBg,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              // [DU361] 첫 줄 가운데(크기 그대로)
              FirstLineIcon(Icons.info_outline, size: 16, color: AppColors.infoDeep,
                  textStyle: ResponsiveHelper.smallStyle(context, color: AppColors.infoDeep)),
              const SizedBox(width: 8),
              Expanded(child: Text(
                TextLayout.keepWords(_kReuseFailed),
                semanticsLabel: _kReuseFailed,
                style: ResponsiveHelper.smallStyle(context, color: AppColors.infoDeep),
              )),
            ]),
          ),
          const SizedBox(height: 16),
        ],
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
          // [DU1 구현47 S001] 320·2.0 '갤러리에서 선/택' 끊김 — 단어 단위(문구 그대로)
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(TextLayout.keepWords(label), style: TextStyle(
              fontWeight: FontWeight.w600,
              color: isPrimary ? Colors.white : AppColors.grey800,
            )),
            const SizedBox(height: 2),
            // [DU349] 보조 설명 grey500(2.57) → textSecondary, chevron grey400 → grey600
            // [DU355] 주 버튼 위 보조 설명 white70(brand 위 실제 3.60) → 흰색(5.58). 위계는 글자 크기 · 굵기로 남긴다(소급 10)
            Text(TextLayout.keepWords(sublabel), semanticsLabel: sublabel, style: TextStyle(
              fontSize: 12,
              color: isPrimary ? Colors.white : AppColors.textSecondary,
            )),
          ])),
          Icon(Icons.chevron_right, color: isPrimary ? Colors.white70 : AppColors.grey600),
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
        Text('촬영 팁', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: AppColors.textSecondary)), // [DU349] grey600(grey50 위 4.41)
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
            // [DU355] Colors.orange.* → warning 토큰(면 warningBg · 테두리 warningLight · 아이콘 warningDark)
            decoration: BoxDecoration(
              color: AppColors.warningBg,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.warningLight),
            ),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Icon(Icons.warning_amber, color: AppColors.warningDark, size: 18),
              const SizedBox(width: 8),
              Expanded(child: Text(
                TextLayout.keepWords('일부 정보를 인식하지 못했습니다. 해당 항목을 직접 입력해주세요.'), // [DU1 구현47] '인식하/지' 끊김
                style: const TextStyle(fontSize: 13),
              )),
            ]),
          ),

        const SizedBox(height: 4),

        // 영문 이름 (외국인등록증 기재)
        _buildOcrField(
          controller: _legalNameCtrl,
          // [FULL13-REEVAL.3] 직접 입력 칸 — OCR 이름은 대조 근거로만 쓴다.
          label: '영문 이름 (등록증 기재대로 직접 입력)',
          hint: '예: NGUYEN AN', // [DU360] '예: NGUYEN VAN AN' 은 320 · 2.0 칸(248)에서 말줄임 — 짧은 예(Codex 후보)
          failed: false,
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
                // [DU355] 주황 Colors.orange(흰 바탕 2.16) → warningDark. 글은 그대로(W · B 끊김 없음 — r3 에서 낱말 조판 철회)
                const Icon(Icons.info_outline, size: 14, color: AppColors.warningDark),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    '카드에 적힌 영문 이름과 동일한지 확인해주세요',
                    style: const TextStyle(fontSize: 12, color: AppColors.warningDark),
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
          hint: '선택 입력', // [DU360] 레이블 '(선택)' · 아래 안내와 같은 뜻, B 말줄임 해소
          failed: false,
          isOptional: true,
        ),
        const SizedBox(height: 4),
        // [DU350] grey400(1.88) → textTertiary, 낱말 단위
        Text(
          TextLayout.keepWords('없으면 입력하지 않으셔도 됩니다'),
          semanticsLabel: '없으면 입력하지 않으셔도 됩니다',
          style: ResponsiveHelper.tinyStyle(context, color: AppColors.textTertiary),
        ),
        const SizedBox(height: 14),

        // 외국인등록번호 — 13자리 입력, 표시는 마스킹 없음 (입력 중)
        _buildOcrField(
          controller: _rawForeignIdCtrl,
          // [FULL13-REEVAL.2] 직접 입력 칸 — OCR 인식 여부와 무관하게 비어 있다.
          label: '외국인등록번호 (13자리 숫자 직접 입력)',
          hint: '숫자 13자리', // [DU360] 레이블 '(13자리 숫자 직접 입력)'과 같은 뜻. 예시 번호(279px)는 B 칸(248)에서 다시 잘려 고르지 않음
          failed: false,
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
      // [DU1 구현47 S001] 320·2.0 에서 긴 레이블('영문 이름 (등록증 기재대로 직접 입력)')+배지 Row 가 오른쪽으로 넘쳤다 —
      //   Wrap 으로 좁으면 배지·(선택)이 다음 줄로 내려가고 레이블은 단어 단위 줄바꿈(문구·배지 그대로).
      Wrap(crossAxisAlignment: WrapCrossAlignment.center, runSpacing: 4, children: [
        Text(TextLayout.keepWords(label), style: ResponsiveHelper.smallStyle(context, color: AppColors.grey600, fontWeight: FontWeight.w600)),
        if (failed) ...[
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.orange.shade100,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text('직접 입력 필요', style: TextStyle(fontSize: 12, color: Colors.orange.shade800)),
          ),
        ],
        if (isOptional) ...[
          const SizedBox(width: 6),
          Text('(선택)', style: ResponsiveHelper.tinyStyle(context, color: AppColors.textTertiary)), // [DU350] grey400 → textTertiary
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
              // [DU356] 미선택 글 grey400 → textTertiary, 아이콘 grey400 → grey600(읽기색 기준)
              child: Row(children: [
                const Icon(Icons.map_outlined, color: AppColors.grey600),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(TextLayout.keepWords('지역을 선택해주세요'),
                      semanticsLabel: '지역을 선택해주세요',
                      style: ResponsiveHelper.bodyStyle(context,
                          color: AppColors.textTertiary)),
                ),
                const Icon(Icons.chevron_right, color: AppColors.grey600),
              ]),
            ),
          ),
        // [DU356] grey400 → textSecondary(내국인 가입 S004 와 같은 색), 낱말 줄바꿈
        Text(TextLayout.keepWords('가입 후 MY에서 언제든 변경할 수 있어요.'),
            semanticsLabel: '가입 후 MY에서 언제든 변경할 수 있어요.',
            style: ResponsiveHelper.tinyStyle(context, color: AppColors.textSecondary)),
        const SizedBox(height: 24),
      ],

      // 약관 동의 섹션
      if (_termsLoading)
        const Center(child: CircularProgressIndicator())
      // [R7-PAYROLL-POLICY.5B] 못 읽었으면 못 읽었다고 말하고 다시 시도할
      //   길을 준다. 체크박스를 그리지 않으므로 동의가 불가능하고, 지금까지
      //   입력한 가입 정보는 그대로 남는다.
      else if (_legalTerms == null)
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // [DU356] 실패 글 grey500 → textSecondary, 아이콘 grey500 → grey600
            const Icon(Icons.cloud_off_outlined, size: 18, color: AppColors.grey600),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                  TextLayout.keepWords(_termsError ?? '약관 정보를 불러올 수 없습니다.'),
                  semanticsLabel: _termsError ?? '약관 정보를 불러올 수 없습니다.',
                  style: ResponsiveHelper.bodyStyle(context,
                      color: AppColors.textSecondary)),
            ),
          ]),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => _loadTerms(),
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('다시 시도'),
          ),
        ])
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
      // [DU356] 항목 제목 낱말 줄바꿈('수|신' · '동|의'), 낭독은 원문
      title: Text(
        TextLayout.keepWords('${item.isRequired ? '[필수] ' : '[선택] '}${item.title}'),
        semanticsLabel: '${item.isRequired ? '[필수] ' : '[선택] '}${item.title}',
        style: ResponsiveHelper.bodyStyle(context),
      ),
      trailing: item.content.isNotEmpty
          ? TextButton(
              onPressed: () => _showTermsDetail(item),
              child: Text(
                viewed ? '다시보기' : '보기 *',
                style: TextStyle(
                  color: viewed ? AppColors.textSecondary : theme.primaryColor, // [DU356] '다시보기' grey400 → textSecondary
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
      // [DU349] 단계 머리 제목 · 안내 낱말 단위(320 · 2.0 '스 / 캔' · '촬영하거 / 나'), 원문은 낭독용
      Text(
        TextLayout.keepWords(title),
        semanticsLabel: title,
        style: ResponsiveHelper.bodyStyle(context).copyWith(
          fontSize: 20,
          fontWeight: FontWeight.bold,
          color: AppColors.textPrimary,
        ),
      ),
      const SizedBox(height: 6),
      Text(
        TextLayout.keepWords(subtitle),
        semanticsLabel: subtitle,
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

const TextStyle _kTipStyle = TextStyle(fontSize: 12, color: AppColors.textSecondary);

class _TipRow extends StatelessWidget {
  final IconData icon;
  final String text;
  const _TipRow({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      // [DU361] 여러 줄 팁(B)에서 아이콘이 글 덩어리 가운데에 놓였다 — 위 정렬 + 첫 줄 가운데(크기 · 색 그대로)
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        FirstLineIcon(icon, size: 14, color: AppColors.grey600, textStyle: _kTipStyle), // [DU349] grey500 → grey600
        const SizedBox(width: 6),
        // [DU1 구현47 S001] 320·2.0 에서 팁 글이 줄지 않아 오른쪽으로 125~173px 넘쳤다 — 남은 폭에서 단어 단위 줄바꿈(문구 그대로)
        // [DU349] 글자 grey600(grey50 위 4.41) → textSecondary
        Expanded(child: Text(TextLayout.keepWords(text), semanticsLabel: text, style: _kTipStyle)),
      ]),
    );
  }
}
