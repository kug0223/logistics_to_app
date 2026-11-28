import 'dart:io';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/user_provider.dart';
import '../../models/core/user_model.dart';
import '../../utils/responsive_helper.dart';
import '../../widgets/common/common_widgets.dart';
import '../../widgets/common/loading_widget.dart';
import '../../widgets/common/privacy_inline_notice.dart';
import '../../utils/document_upload_helper.dart';
import '../../utils/action_guard.dart';
import '../../utils/identity_identifier.dart';
import '../../services/firestore_service.dart';
import '../../utils/toast_helper.dart';
import '../../utils/dialog_helper.dart';
import '../../utils/format_helper.dart';
import '../../utils/text_layout.dart';
import '../../widgets/dialogs/styled_dialog.dart';
import '../../services/storage_service.dart';
import '../../services/tax_identity_service.dart';
import '../../services/foreign_id_ocr_service.dart';
import '../../utils/image_helper.dart';
import '../../utils/ocr_verification_helper.dart';
import '../../utils/navigation_helper.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_select_field.dart';
import '../../widgets/common/id_document_kind_sheet.dart';
import 'foreign_id_document_screen.dart';
import '../../utils/encryption_helper.dart';

/// 📄 내 서류 관리 화면 (역할별 분기)
/// - 지원자(USER): 신분증 + 통장 정보
/// - 관리자(BUSINESS_ADMIN): 사업자등록증
class DocumentManagementScreen extends StatefulWidget {
  const DocumentManagementScreen({super.key});

  @override
  State<DocumentManagementScreen> createState() => _DocumentManagementScreenState();
}

class _DocumentManagementScreenState extends State<DocumentManagementScreen> {
  final FirestoreService _firestoreService = FirestoreService();
  final StorageService _storageService = StorageService();

  // 사업자 정보 입력 컨트롤러 (관리자용)
  final TextEditingController _businessNumberController = TextEditingController();
  final TextEditingController _businessNameController = TextEditingController();
  final TextEditingController _ceoNameController = TextEditingController();

  // 통장 정보 입력 컨트롤러 (지원자용)
  final TextEditingController _accountNumberController = TextEditingController();
  String? _selectedBank;

  bool _isLoading = false;
  /// [.20 PERCEIVED-PERFORMANCE] 업로드 중 지금 무엇을 하는지. 사진 확인(압축·글자 읽기)은 도우미 창이
  ///   단계를 보여 주지만, 그 창이 닫힌 뒤 전송·등록 동안은 빈 화면에 스피너만 있어
  ///   어디까지 됐는지 알 수 없었다. null 이면 문구 없음.
  String? _loadingMessage;
  void _stage(String message) {
    if (mounted) setState(() => _loadingMessage = message);
  }

  /// [PERF-L42 · 판정291 §4] 전송 진행률 — 같은 백분율이면 다시 그리지 않는다.
  int _lastUploadPct = -1;
  void _uploadProgress(double fraction) {
    final pct = (fraction * 100).clamp(0, 100).round();
    if (pct == _lastUploadPct) return;
    _lastUploadPct = pct;
    _stage('사진을 올리고 있어요 · $pct%');
  }
  /// [I9 · impl_16 배정 → impl_17] 확인·선택 창(첫 await) **전에** 같은 화면의 같은 잠금 묶음을 잠근다 —
  ///   창이 뜨기 전(다음 프레임) 연타의 두 번째 진입이 창·mutation 을 한 번 더 내지 않게. 본문 함수 이름·내용은 그대로다
  ///   (서류 계약 시험이 본문을 이름으로 잘라 본다). `_isLoading` 은 진행 표시로 그대로 쓴다.
  String get _docActionKey => ActionGuard.ownerKey('documentManagement._isLoading', this);
  Future<void> _deleteBusinessLicenseTap() => ActionGuard.runVoid(_docActionKey, () => _deleteBusinessLicense());
  Future<void> _uploadIdCardTap() => ActionGuard.runVoid(_docActionKey, () => _uploadIdCard());
  Future<void> _deleteIdCardTap() => ActionGuard.runVoid(_docActionKey, () => _deleteIdCard());
  Future<void> _deleteBankInfoTap() => ActionGuard.runVoid(_docActionKey, () => _deleteBankInfo());
  bool _hasChanges = false;

  /// [PII-B4-R1.4] 세무정보 등록 상태 — 번호는 담기지 않는다.
  ///   null = 아직 조회 전. `loadFailed` = 조회 실패(미등록과 다르다).
  TaxIdentityStatus? _taxStatus;

  @override
  void initState() {
    super.initState();
    _loadUserDocuments();
    _loadTaxIdentity();
  }

  /// 세무정보 상태 조회. 실패해도 화면 전체를 막지 않는다.
  Future<void> _loadTaxIdentity() async {
    final s = await TaxIdentityService.loadStatus();
    if (!mounted) return;
    setState(() => _taxStatus = s);
  }

  @override
  void dispose() {
    _accountNumberController.dispose();
    _businessNumberController.dispose();
    _businessNameController.dispose();
    _ceoNameController.dispose();
    super.dispose();
  }

  /// 사용자 서류 정보 로드
  Future<void> _loadUserDocuments() async {
    final userProvider = context.read<UserProvider>();
    final user = userProvider.currentUser;
    if (user != null) {
      setState(() {
        _selectedBank = user.bankName;
        _accountNumberController.text = user.accountNumber ?? '';
        // 관리자용 필드
      _businessNumberController.text = user.businessNumber != null
          ? FormatHelper.formatBusinessNumber(user.businessNumber!)
          : '';
      _businessNameController.text = user.businessName ?? '';
      _ceoNameController.text = user.ceoName ?? user.name; // ✅ 저장된 값 우선, 없으면 본인 이름
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // select로 currentUser 변경 시에만 rebuild (UserProvider의 다른 상태 변경 무시)
    final user = context.select<UserProvider, UserModel?>((p) => p.currentUser);

    // 흰색 AppBar + 뒤로가기만 — 홈 디자인 언어 그대로 유지
    // 홈/알림/새로고침 버튼 제거: 2차 Task 화면이므로 불필요
    // Bottom Navigation 제거: 지원 준비 작업 플로우 집중, 뒤로가기로 복귀
    final appBar = AppBar(
      backgroundColor: AppColors.surface,
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20,
            color: AppColors.textPrimary),
        onPressed: () => NavigationHelper.pop(context, changed: _hasChanges),
        tooltip: '뒤로',
      ),
      title: const Text(
        '내 서류 관리',
        style: TextStyle(
          color: AppColors.textPrimary,
          fontSize: 20,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.3,
        ),
      ),
      titleSpacing: 0,
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(0.5),
        child: Container(height: 0.5, color: AppColors.borderLight),
      ),
    );

    if (user == null) {
      return Scaffold(
        backgroundColor: AppColors.background,
        appBar: appBar,
        body: const Center(child: Text('사용자 정보를 불러올 수 없습니다')),
      );
    }

    return Scaffold(
      // [DU627b · 판정207 D-SCREEN-BG] 화면 바탕 = 앱 화면 바탕 background(#F6F7FA · AppPageScaffold 기본과 같다) — 예전 grey50 은 같은 역할의 다른 거의-흰.
      backgroundColor: AppColors.background,
      appBar: appBar,
      body: _isLoading
          ? LoadingWidget(message: _loadingMessage)
          : ListView(
              padding: ResponsiveHelper.listPadding(context),
              children: [
                // ✅ 역할별 분기
                if (user.role == UserRole.BUSINESS_ADMIN) ...[
                  // 🏢 관리자: 사업자등록증
                  _buildAdminDocuments(user),
                ] else ...[
                  // 👤 지원자: 신분증 + 통장
                  _buildUserDocuments(user),
                ],
              ],
            ),
    );
  }

  // ============================================================
  // 🏢 관리자용: 사업자등록증 섹션
  // ============================================================

  Widget _buildAdminDocuments(UserModel user) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 📢 안내 카드
        _buildInfoBanner(
          message: '사업자등록증이 승인되어야 \n'
                   '사업장 등록이 가능합니다.\n'
                   '아래 정보와 사업자등록증이 일치해야 합니다.',
          icon: Icons.warning_amber,
          color: AppColors.warningDark,
        ),

        SizedBox(height: ResponsiveHelper.spacing(context, 20)),

        // 📝 사업자 정보 입력 섹션
        _buildSectionHeader('사업자 정보'),

        SizedBox(height: ResponsiveHelper.spacing(context, 8)),

        _buildBusinessInfoSection(user),

        SizedBox(height: ResponsiveHelper.spacing(context, 20)),

        // 📋 사업자등록증 섹션
        _buildSectionHeader('사업자등록증'),

        SizedBox(height: ResponsiveHelper.spacing(context, 8)),

        _buildBusinessLicenseSection(user),
      ],
    );
  }

  /// 📝 사업자 정보 입력 섹션
  Widget _buildBusinessInfoSection(UserModel user) {
    final theme = Theme.of(context);
    final hasSaved = user.businessNumber != null && user.businessName != null;

    InputDecoration fieldDeco(String label, IconData icon) => InputDecoration(
          labelText: label,
          isDense: true,
          contentPadding: EdgeInsets.symmetric(
            horizontal: ResponsiveHelper.spacing(context, 12),
            vertical: ResponsiveHelper.spacing(context, 12),
          ),
          prefixIcon: Icon(icon,
              size: ResponsiveHelper.iconSize(context, 18),
              color: theme.primaryColor),
          counter: const SizedBox.shrink(),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: AppColors.grey300),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: theme.primaryColor, width: 1.5),
          ),
        );

    return Container(
      decoration: CommonWidgets.compactCardDecoration(),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: ResponsiveHelper.spacing(context, 16),
          vertical: ResponsiveHelper.spacing(context, 14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 사업자등록번호
            TextFormField(
              controller: _businessNumberController,
              keyboardType: TextInputType.number,
              maxLength: 12,
              inputFormatters: [BusinessNumberFormatter()],
              style: ResponsiveHelper.bodyStyle(context),
              decoration: fieldDeco('사업자등록번호', Icons.badge_outlined),
            ),
            SizedBox(height: ResponsiveHelper.spacing(context, 10)),

            // 상호명
            TextField(
              controller: _businessNameController,
              style: ResponsiveHelper.bodyStyle(context),
              decoration: fieldDeco('상호명', Icons.storefront_outlined),
            ),
            SizedBox(height: ResponsiveHelper.spacing(context, 10)),

            // 대표자명 + 내 이름 가져오기
            Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
              Expanded(
                child: TextField(
                  controller: _ceoNameController,
                  style: ResponsiveHelper.bodyStyle(context),
                  decoration: fieldDeco('대표자명', Icons.person_outline),
                ),
              ),
              TextButton(
                onPressed: () =>
                    setState(() => _ceoNameController.text = user.name),
                style: TextButton.styleFrom(
                    padding: EdgeInsets.symmetric(
                        horizontal: ResponsiveHelper.spacing(context, 8))),
                child: Text('내 이름',
                    style: ResponsiveHelper.tinyStyle(context,
                        color: theme.primaryColor,
                        fontWeight: FontWeight.w600)),
              ),
            ]),

            SizedBox(height: ResponsiveHelper.spacing(context, 14)),

            // 저장/수정 버튼 — compact outline 스타일
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _isLoading ? null : _saveBusinessInfo,
                icon: Icon(hasSaved ? Icons.edit_outlined : Icons.save_outlined,
                    size: 16),
                label: Text(hasSaved ? '사업자 정보 수정' : '사업자 정보 저장',
                    style: ResponsiveHelper.bodyStyle(context,
                        color: theme.primaryColor,
                        fontWeight: FontWeight.w600)),
                style: OutlinedButton.styleFrom(
                  padding: EdgeInsets.symmetric(
                      vertical: ResponsiveHelper.spacing(context, 10)),
                  side: BorderSide(color: theme.primaryColor),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 사업자 정보 저장
  Future<void> _saveBusinessInfo() async {
    final cleanNumber = _businessNumberController.text.replaceAll('-', '');

    if (cleanNumber.length != 10) {
      ToastHelper.showWarning('사업자번호 10자리를 입력해주세요');
      return;
    }

    if (_businessNameController.text.trim().isEmpty) {
      ToastHelper.showWarning('상호명을 입력해주세요');
      return;
    }

    if (_ceoNameController.text.trim().isEmpty) {
      ToastHelper.showWarning('대표자명을 입력해주세요');
      return;
    }

    final userProvider = context.read<UserProvider>();
    final user = userProvider.currentUser;

    if (user == null) return;

    setState(() => _isLoading = true);

    try {
      await _firestoreService.updateUserDocument(
        user.uid,
        {
          'businessNumber': cleanNumber,
          'businessName': _businessNameController.text.trim(),
          'ceoName': _ceoNameController.text.trim(), // ✅ 추가!
        },
      );

      await userProvider.refreshCurrentUser();
      if (!mounted) return;

      _hasChanges = true;
      ToastHelper.showSuccess('사업자 정보가 저장되었습니다');
    } catch (e) {
      if (mounted) ToastHelper.showError('저장에 실패했습니다');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// 📋 사업자등록증 섹션
  Widget _buildBusinessLicenseSection(UserModel user) {
    // [R8-P5.1] path 우선 — 신규 등록은 경로만 기록한다(영구 URL 미생성).
    //   레거시 사용자는 URL 만 갖고 있으므로 둘 다 본다.
    final hasLicense = user.businessLicenseImagePath != null ||
        user.businessLicenseImageUrl != null;
    final cleanNumber = _businessNumberController.text.replaceAll('-', '');
    final hasBusinessInfo = cleanNumber.length == 10 &&
        _businessNameController.text.trim().isNotEmpty;

    return Container(
      decoration: CommonWidgets.compactCardDecoration(),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: ResponsiveHelper.spacing(context, 16),
          vertical: ResponsiveHelper.spacing(context, 12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (hasLicense) ...[
              // 등록된 사업자등록증 정보 — compact single-line row
              Row(
                children: [
                  Container(
                    width: ResponsiveHelper.spacing(context, 34),
                    height: ResponsiveHelper.spacing(context, 34),
                    decoration: BoxDecoration(
                      color: AppColors.success.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.check_circle,
                      color: AppColors.successDark,
                      size: ResponsiveHelper.iconSize(context, 18),
                    ),
                  ),
                  SizedBox(width: ResponsiveHelper.spacing(context, 12)),
                  Expanded(
                    child: Text(
                      '사업자등록증 등록 완료',
                      style: ResponsiveHelper.bodyStyle(context).copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),

              SizedBox(height: ResponsiveHelper.spacing(context, 12)),

              // 버튼들
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _isLoading ? null : () {
                        if (hasBusinessInfo) {
                          _uploadBusinessLicense();
                        } else {
                          ToastHelper.showWarning('사업자 정보를 먼저 저장해주세요');
                        }
                      },
                      icon: const Icon(Icons.refresh, size: 14),
                      label: Text('재업로드',
                          style: ResponsiveHelper.smallStyle(context, color: AppColors.brand)),
                      style: OutlinedButton.styleFrom(
                        // [DU627b · 판정207 §4] 재업로드 = 행동 brand(글 · 아이콘 · 선 한 짝 — '사업자 정보 수정' 외곽 단추와 같다 · 예전 글 grey600 · 선 infoDark 두 색).
                        foregroundColor: AppColors.brand,
                        side: const BorderSide(color: AppColors.brand),
                        padding: EdgeInsets.symmetric(
                            vertical: ResponsiveHelper.spacing(context, 8)),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  ),
                  SizedBox(width: ResponsiveHelper.spacing(context, 12)),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _isLoading ? null : _deleteBusinessLicenseTap,
                      icon: const Icon(Icons.delete, size: 14),
                      label: Text('삭제',
                          style: ResponsiveHelper.smallStyle(context)),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.textSecondary,
                        side: const BorderSide(color: AppColors.border),
                        padding: EdgeInsets.symmetric(
                            vertical: ResponsiveHelper.spacing(context, 8)),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  ),
                ],
              ),
            ] else ...[
              // 사업자등록증 미등록 — compact inline empty state
              Container(
                padding: EdgeInsets.symmetric(
                  horizontal: ResponsiveHelper.spacing(context, 16),
                  vertical: ResponsiveHelper.spacing(context, 14),
                ),
                decoration: BoxDecoration(
                  color: AppColors.grey50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.grey200),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.description_outlined,
                      size: 20,
                      color: AppColors.grey400,
                    ),
                    SizedBox(width: ResponsiveHelper.spacing(context, 10)),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // [DU485] grey500(grey50 위 약 2.6) → textSecondary(USER 경로 '미등록'과 같다 · DU1 구현89).
                          Text(
                            '미등록',
                            style: ResponsiveHelper.smallStyle(context,
                                color: AppColors.textSecondary,
                                fontWeight: FontWeight.w600),
                          ),
                          // [DU486] 큰 글자에서 '업 / 로드해주세요'처럼 음절 사이에서 끊겼다 — 낱말 사이에서만 줄을 바꾼다. 읽기 도구에는 원문.
                          Text(
                            TextLayout.keepWords(hasBusinessInfo
                                ? '위 정보와 일치하는 사업자등록증을 업로드해주세요'
                                : '먼저 사업자 정보를 입력하고 저장해주세요'),
                            semanticsLabel: hasBusinessInfo
                                ? '위 정보와 일치하는 사업자등록증을 업로드해주세요'
                                : '먼저 사업자 정보를 입력하고 저장해주세요',
                            // [DU485] 안내 grey400(grey50 위 약 1.8) → textTertiary. 사업자 정보 미저장 분기(warningDark)는 그대로다.
                            style: ResponsiveHelper.tinyStyle(context,
                                color: hasBusinessInfo
                                    ? AppColors.textTertiary
                                    : AppColors.warningDark),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              SizedBox(height: ResponsiveHelper.spacing(context, 12)),

              CommonWidgets.primaryButton(
                context: context,
                text: '사업자등록증 업로드',
                onPressed: _isLoading ? null : () {
                  if (hasBusinessInfo) {
                    _uploadBusinessLicense();
                  } else {
                    ToastHelper.showWarning('사업자 정보를 먼저 저장해주세요');
                  }
                },
                icon: Icons.camera_alt,
              ),

              if (!hasBusinessInfo)
                Padding(
                  padding: EdgeInsets.only(top: ResponsiveHelper.spacing(context, 8)),
                  child: Text(
                    '* 사업자 정보를 먼저 저장해주세요',
                    style: ResponsiveHelper.smallStyle(context).copyWith(
                      color: AppColors.warningDark,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  /// 사업자등록증 업로드
  Future<void> _uploadBusinessLicense() async {
    if (_isLoading) return;
    final userProvider = context.read<UserProvider>();
    final user = userProvider.currentUser;
    if (user == null) return;

    setState(() => _isLoading = true); // 피커 전에 설정 — 피커 도중 이중 탭 방지

    // [R8-P5.1] orphan 추적을 URL 이 아니라 Storage 경로로 한다 —
    //   업로드가 더 이상 download URL 을 만들지 않으므로 지울 대상도 경로다.
    String? newLicensePath;
    try {
      // 입력한 정보로 OCR 검증
      final imagePath = await DocumentUploadHelper.pickAndVerifyBusinessLicense(
        context,
        businessNumber: _businessNumberController.text.trim(),
        ceoName: _ceoNameController.text.trim(),
        onCeoNameExtracted: (name) {
          if (mounted) setState(() => _ceoNameController.text = name);
        },
      );

      if (imagePath == null || !mounted) return; // finally가 _isLoading 초기화

      final oldUrl = user.businessLicenseImageUrl;
      final oldPath = user.businessLicenseImagePath;

      // 1. 새 이미지 먼저 업로드 — 예외 여부와 무관하게 임시 파일 삭제 보장
      //
      // [R8-P5.1] uploadImage → uploadImageNoUrl.
      //   이 값은 표시용이 아니다 — checkBusinessLicense를 거쳐 사업장 자동승인과
      //   공고 등록 선행조건을 연다. 그런데 클라이언트가 users 문서에 직접 쓰고 있었고,
      //   업로드는 영구 토큰 URL까지 만들었다. 신분증·통장사본과 같은 규칙으로 맞춘다.
      _stage('사진을 올리고 있어요');
      final storagePath = 'users/${user.uid}/businessLicense_${DateTime.now().millisecondsSinceEpoch}.jpg';
      bool uploadOk = false;
      try {
        uploadOk = await _storageService.uploadImageNoUrl(imagePath, storagePath);
      } finally {
        // TMP-01: pickAndVerifyBusinessLicense가 반환한 임시 압축 파일.
        try { await File(imagePath).delete(); } catch (_) {}
      }

      if (!uploadOk) {
        if (mounted) ToastHelper.showError('이미지 업로드에 실패했습니다');
        return;
      }

      // 2. CF로 등록 — 경로 소유권·존재 확인 후 서버가 기록한다.
      //    클라이언트 직접 write는 Rules denylist로 막혀 있다.
      _stage('등록하고 있어요');
      newLicensePath = storagePath; // CF 호출 전 Storage orphan 추적
      await FirebaseFunctions.instanceFor(region: 'asia-northeast3')
          .httpsCallable('callableRegisterBusinessLicense')
          .call({'storagePath': storagePath});
      newLicensePath = null; // CF 성공 — Storage 정리 불필요

      // 3. 업로드·저장 성공 후 기존 이미지 삭제 (best-effort)
      //    path 우선, 레거시 사용자만 URL 폴백 — 신분증·통장사본과 같은 순서.
      if (oldPath != null) {
        try {
          await _storageService.deleteImage(oldPath);
        } catch (e) {
          debugPrint('⚠️ 기존 사업자등록증 삭제 실패 (무시): $e');
        }
      } else if (oldUrl != null) {
        try {
          await _storageService.deleteImageByUrl(oldUrl);
        } catch (e) {
          debugPrint('⚠️ 기존 사업자등록증 URL 삭제 실패 (무시): $e');
        }
      }

      // UserProvider 갱신
      await userProvider.refreshCurrentUser();
      if (!mounted) return;

      ToastHelper.showSuccess('사업자등록증이 등록되었습니다');
      _hasChanges = true;
    } catch (e) {
      // [R8-P5.1] CF 실패 시 업로드된 파일 Storage orphan 방지 (경로 기반)
      if (newLicensePath != null) {
        try { await _storageService.deleteImage(newLicensePath); } catch (_) {}
      }
      if (mounted) ToastHelper.showError('사업자등록증 등록에 실패했습니다');
    } finally {
      if (mounted) setState(() { _isLoading = false; _loadingMessage = null; });
    }
  }

  /// 사업자등록증 삭제
  Future<void> _deleteBusinessLicense() async {
    if (_isLoading) return;
    final confirmed = await DialogHelper.showDangerConfirm(
      context,
      title: '사업자등록증 삭제',
      message: '등록된 사업자등록증을 삭제하시겠습니까?',
      confirmText: '삭제',
    );

    if (!confirmed || !mounted) return;

    final userProvider = context.read<UserProvider>();
    final user = userProvider.currentUser;


    if (user == null) return;

    setState(() => _isLoading = true);

    try {
      // Firestore 먼저 업데이트 → 성공 후 Storage 삭제 (순서 역전 방지)
      final oldUrl = user.businessLicenseImageUrl;
      await _firestoreService.updateUserDocument(
        user.uid,
        {
          'businessLicenseImageUrl': null,
        },
      );

      if (oldUrl != null) {
        try {
          await _storageService.deleteImageByUrl(oldUrl);
        } catch (e) {
          debugPrint('⚠️ 사업자등록증 Storage 삭제 실패 (무시): $e');
        }
      }

      await userProvider.refreshCurrentUser();
      if (!mounted) return;

      ToastHelper.showSuccess('사업자등록증이 삭제되었습니다');
      _hasChanges = true;  // ✅ 추가
    } catch (e) {
      debugPrint('❌ 사업자등록증 삭제 실패: $e');
      if (mounted) ToastHelper.showError('사업자등록증 삭제에 실패했습니다');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ============================================================
  // 👤 지원자용: 신분증 + 통장 섹션 (기존 코드)
  // ============================================================

  Widget _buildUserDocuments(UserModel user) {
    // [BUG-ID-01] 신규 flow는 idCardImagePath만 저장 → idCardImageUrl 없어도 등록 상태 표시
    final hasId = user.idCardImagePath != null || user.idCardImageUrl != null;
    // [PRODUCT-POLICY 2026-08-21] 급여정보 준비 완료 = 계좌 + 통장사본 제출 + mismatch 아님
    //   null / 미등록     → 미완료 (숫자 배지)
    //   'review_required' → 지원자 기준 준비 완료 (초록 체크) — background 관리자 검토 중
    //   'verified'        → 준비 완료 + 관리자 검토 완료 (초록 체크)
    //   'mismatch'        → 재등록 필요 (빨강 배지) — 관리자가 명시적 문제 발견
    //
    // review_required를 "승인 대기"로 표시하지 않는다.
    // 지원 준비 완료 기준 = callableApplyToTO mismatch gate와 동일 논리.
    // [PII-DOC-R1.5.3] bankVerificationStatus == 'mismatch' 분기를 뺐다.
    //   이 값을 쓰는 곳이 서버에 하나도 없다(남은 것은 FieldValue.delete뿐).
    //   아무도 만들지 않는 상태로 빨간 배지를 띄우면, 사용자는 해결할 수
    //   없는 할 일을 받게 된다.
    // Canonical 기준: UserModel.hasWageDocumentsReady와 동일
    // (hasBankAccount && hasBankbookDocument)
    final isPayoutDocsReady = user.hasWageDocumentsReady;
    // 미사용 변수 방지: 이 함수에서 isBankVerified/isBankReviewRequired는
    // _buildBankInfoSection 내부에서 별도 계산하므로 여기서 선언하지 않는다.

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // [DU1 구현121 S038 V6] 급여계좌 안내 띠는 ② 급여정보 준비 안(급여 계좌 카드 바로 위)으로 옮겼다 —
        //   화면 첫 안내가 ① 신원 확인보다 먼저 ② 의 내용(본인 명의 급여계좌·예금주명)을 말했다(구현121 ko 관측). 문구·색·조건은 그대로다.
        // ① 신원 확인 섹션
        _buildReadinessSectionLabel(
          step: 1,
          title: '신원 확인',
          description: '지원자 본인 확인을 위해 필요해요',
          isComplete: hasId,
        ),

        SizedBox(height: ResponsiveHelper.spacing(context, 10)),

        _buildIdCardSection(user),

        // [PII-B4-R1.4 §28] 신분증 바로 아래 — 같은 "신원 확인" 단계다.
        //   수집이 켜져 있을 때만 보인다(§14). 꺼져 있으면 서버도 등록을
        //   받지 않으므로 등록할 수 없는 항목을 띄우지 않는다.
        if (_showsTaxIdentity) ...[
          SizedBox(height: ResponsiveHelper.spacing(context, 10)),
          _buildTaxIdentitySection(user),
        ],

        SizedBox(height: ResponsiveHelper.spacing(context, 18)),

        // ② 급여정보 준비 섹션
        // [PRODUCT-POLICY] isComplete = 제출 완료
        _buildReadinessSectionLabel(
          step: 2,
          title: '급여정보 준비',
          description: '근무 후 급여 지급을 위해 필요해요',
          isComplete: isPayoutDocsReady,
        ),

        SizedBox(height: ResponsiveHelper.spacing(context, 10)),

        // 📢 안내 카드 — 급여 계좌 등록 안내(구현121: 화면 맨 위에서 이 자리로)
        _buildInfoBanner(
          message: '본인 명의의 급여계좌를 등록해주세요.\n'
              '통장에 표시된 예금주명을 정확히 확인해주세요.',
          icon: Icons.info_outline,
          // [DU1 구현89 S038] 배너 글자가 infoDark 라 옅은 면 위 3.97:1(PNG) — 이 호출만 brandDark(공용 배너 helper 무변경).
          color: AppColors.brandDark,
        ),

        SizedBox(height: ResponsiveHelper.spacing(context, 10)),

        _buildBankInfoSection(user),
      ],
    );
  }

  /// 지원 준비 단계 라벨 — "① 신원 확인 / ② 급여정보 준비"
  ///
  /// 스텝 배지 상태:
  ///   [isComplete] = true                         → 초록 ✓
  ///   [isError]    = true (mismatch)              → 빨강 ⚠
  ///   [isPending]  = true (review_required)       → 앰버 ⏳
  ///   그 외                                        → 파란 숫자 (미완료)
  ///
  /// 상태 우선순위: isComplete > isError > isPending > 미완료
  Widget _buildReadinessSectionLabel({
    required int step,
    required String title,
    required String description,
    required bool isComplete,
    bool isPending = false,   // bankVerificationStatus == 'review_required'
    bool isError   = false,   // bankVerificationStatus == 'mismatch'
  }) {
    final theme = Theme.of(context);

    // 배지 색상
    final Color badgeColor = isComplete
        ? AppColors.success
        : isError
            ? AppColors.errorDark   // 빨강 — mismatch
            : isPending
                ? AppColors.warningDark // 앰버 — review_required
                : theme.primaryColor;   // 파랑 — 미완료

    // 배지 아이콘/텍스트
    final Widget badgeChild = isComplete
        ? const Icon(Icons.check_rounded, color: Colors.white, size: 13)
        : isError
            ? const Icon(Icons.priority_high_rounded, color: Colors.white, size: 13)
            : isPending
                ? const Icon(Icons.hourglass_empty_rounded,
                    color: Colors.white, size: 12)
                : Text(
                    '$step',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      height: 1.0,
                    ),
                  );

    // [DU1 구현122 S038 V3] 번호 배지를 제목 줄과 한 Row 로 묶는다 — 예전 Row(center)는 배지를 제목+설명 묶음의 세로 가운데에 두어,
    //   설명이 두 줄이 되면(320dp·글자 2.0) 번호가 제목이 아니라 설명 첫 줄 옆에 놓였다. 설명은 예전과 같은 x·같은 폭(배지 24 + 간격 뒤)이다.
    // [DU1 구현123 S038 V7] 원 지름 = 숫자 글자(12 × 글자 배율) + 위아래 3, 최소 24 — 배율 1 에서는 예전 24 그대로다.
    //   예전 고정 24 는 글자 2.0 에서 숫자(24)가 원 가장자리까지 닿아 아래 테두리가 끊겨 보였다(구현123 관측).
    //   숫자 배율은 줄이지 않고 원을 필요한 만큼만 키운다(키운 글자를 되돌려 줄이지 않는다).
    final badgeSize = (MediaQuery.textScalerOf(context).scale(12) + 6).clamp(24.0, double.infinity);
    final gap = ResponsiveHelper.spacing(context, 10);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // 스텝 배지
            Container(
              width: badgeSize,
              height: badgeSize,
              decoration: BoxDecoration(
                color: badgeColor,
                shape: BoxShape.circle,
              ),
              child: Center(child: badgeChild),
            ),
            SizedBox(width: gap),
            // 제목
            Expanded(
              child: Text(
                title,
                style: ResponsiveHelper.bodyStyle(context).copyWith(
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            // 완료 배지 제거 — 왼쪽 배지가 이미 상태를 표현함
          ],
        ),
        // 설명 — 제목 글 열에 맞춘다
        Padding(
          padding: EdgeInsets.only(left: badgeSize + gap),
          child: Text(
            description,
            // [DU1 구현89 S038] grey500 2.57:1(PNG) — 읽기 설명이라 textSecondary.
            style: ResponsiveHelper.tinyStyle(context,
                color: AppColors.textSecondary),
          ),
        ),
      ],
    );
  }

  /// 신분증 대조용 기대 식별번호 앞 7자리.
  ///
  /// [PII-DOC-R1.2] 계산 규칙은 `identity_identifier.dart` 한 곳에만 있다.
  ///   여기 있던 구현은 국적 개념이 없어 외국인에게 내국인 코드(1~4)를 찍었고,
  ///   등록증의 5~8과 항상 불일치했다. 같은 변환을 화면마다 복사하지 않는다.
  String? _buildExpectedResidentNumber(UserModel user) =>
      expectedIdentifierForUser(user).prefix;

  /// 신분증 업로드
  Future<void> _uploadIdCard() async {
    if (_isLoading) return;
    final userProvider = context.read<UserProvider>();
    var user = userProvider.currentUser;
    if (user == null) return;

    // [ALFIT-AUTH-KAKAO-ONBOARDING.1 · 판정278 §4 R2-1] 국적 미확정(새 계정 · 서류 전)은 서류 종류를 먼저 고른다.
    //   'unknown' 을 내국인(isForeign=false)으로 흘리지 않는다. 고른 뒤의 번호 규칙 · OCR · 대조는 기존 그대로다.
    String? documentKind;
    if (user.isNationalityUnconfirmed) {
      final kind = await showIdDocumentKindSheet(context);
      if (!mounted || kind == null) return;
      if (kind == IdDocumentKindSheet.foreignRegistration) {
        // 외국인등록증은 번호 · 이름을 먼저 서버에 등록한다(callableRegisterForeignIdDocument) —
        //   서버가 nationalityStatus='foreign' 을 쓴 뒤에 사진을 올린다(5~8 규칙).
        final ok = await Navigator.of(context).push<bool>(MaterialPageRoute(
          builder: (_) => const ForeignIdDocumentScreen(),
        ));
        if (!mounted || ok != true) return;
        user = userProvider.currentUser;
        if (user == null) return;
        if (user.isNationalityUnconfirmed) {
          ToastHelper.showError('등록 정보를 다시 불러온 뒤 시도해 주세요');
          return;
        }
      } else {
        documentKind = IdDocumentKindSheet.resident;
      }
    }

    setState(() => _isLoading = true); // 피커 전에 설정 — 피커 도중 이중 탭 방지
    // [PERF-L42] 사진을 고른 뒤 압축하는 동안(글자 확인 창이 뜨기 전) 빈 스피너만 있었다 — 단계를 말한다.
    _stage('사진을 준비하고 있어요');

    String? newIdCardPath; // [M-19] CF 실패 시 Storage orphan 방지 (path 기반)
    try {
      // 주민번호 앞자리 계산: birthDate + gender (내국인 residentNumber는 저장 안 됨)
      final residentNumber = _buildExpectedResidentNumber(user);

      final picked = await DocumentUploadHelper.pickAndVerifyIdCard(
        context,
        user.name,
        expectedResidentNumber: residentNumber,
        // [R7-P4.4E.10A.1] 신원번호 구조 판정에 쓴다 — 성별·세기 코드가
        //   내국인 1~4, 외국인 5~8 로 다르다. 같은 범위로 보면 한쪽에서
        //   정상 번호를 "구조 불만족" 으로 버린다.
        isForeign: user.isForeign,
      );

      if (picked == null || !mounted) return; // finally가 _isLoading 초기화
      final imagePath = picked.path;

      // [R7-P4.4E.10A.1 / E10-D] 제출 시작을 서버에 알리고 순번을 받는다.
      //
      //   서버는 도착 순서만 알았다. A→B 로 올렸는데 A 의 호출이 나중에
      //   완료되면 A 가 더 높은 버전을 받아 **옛 문서가 현재 truth** 가 됐다.
      //   클라이언트 시계를 권위로 쓰지 않고 **서버가 세는 순번**만 쓴다.
      //
      // [R7-P4.4E.10A.2 / §2] 순번을 못 받으면 **여기서 멈춘다.**
      //   예전에는 "순번 없이 진행" 했는데, 그건 가드를 우회하는 길이었다 —
      //   순번 없는 finalize 가 그대로 현재 truth 가 됐다. 서버도 이제
      //   protocol 이 켜진 사용자의 순번 없는 finalize 를 받지 않으므로,
      //   그대로 진행하면 업로드만 하고 등록은 실패하는 더 나쁜 결과가 된다.
      //   재시도 가능한 오류로 말하고 끝낸다.
      _stage('사진을 올리고 있어요');
      final int attemptSeq;
      try {
        final begin = await FirebaseFunctions.instanceFor(
                region: 'asia-northeast3')
            .httpsCallable('callableBeginIdDocumentSubmission')
            .call<Map<String, dynamic>>();
        final seq = (begin.data['attemptSeq'] as num?)?.toInt();
        if (seq == null || seq <= 0) {
          throw StateError('attemptSeq 없음');
        }
        attemptSeq = seq;
      } catch (e) {
        debugPrint('⚠️ 제출 순번 발급 실패: $e');
        if (mounted) {
          ToastHelper.showError('잠시 후 다시 시도해주세요');
        }
        return; // finalize 까지 진행하지 않는다
      }

      // 1. 새 이미지 먼저 업로드 — 예외 여부와 무관하게 임시 파일 삭제 보장
      final storagePath = 'users/${user.uid}/idCard_${DateTime.now().millisecondsSinceEpoch}.jpg';
      bool uploadOk = false;
      try {
        // [BUG-ID-01] uploadImageNoUrl — getDownloadURL() 미호출로 permanent URL 생성 방지
        //   [PERF-L42] 보낸 비율을 단계 문구로 보인다.
        _lastUploadPct = -1;
        uploadOk = await _storageService.uploadImageNoUrl(imagePath, storagePath,
            onProgress: _uploadProgress);
      } finally {
        // TMP-01: pickAndVerifyIdCard가 반환한 임시 압축 파일.
        try { await File(imagePath).delete(); } catch (_) {}
      }

      if (!uploadOk) {
        if (mounted) ToastHelper.showError('이미지 업로드에 실패했습니다');
        return;
      }

      // 2. CF로 신분증 등록 — 경로 소유권 검증 후 isIdVerified=true 설정
      //    [BUG-ID-01] storagePath 직접 전달 — URL 파싱 불필요, permanent URL 생성 0건
      //    [PRODUCT-POLICY] callableMarkIdCardVerified가 경로 검증 완료 후 isIdVerified=true를 설정한다.
      //    [DOCUMENT-VERIFICATION-INTEGRITY-R0] 기기 확인 **근거**를 함께 보낸다.
      //      판정이 아니다 — 서버가 이 근거로 문서 상태를 정한다.
      _stage('등록하고 있어요');
      newIdCardPath = storagePath; // CF 호출 전 Storage orphan 추적
      await FirebaseFunctions.instanceFor(region: 'asia-northeast3')
          .httpsCallable('callableMarkIdCardVerified')
          .call({
        'storagePath': storagePath,
        'selfCheck': picked.selfCheck,
        'attemptSeq': attemptSeq,
        // [ALFIT-AUTH-KAKAO-ONBOARDING.1 · §5] 국적 미확정 사용자가 고른 서류 종류 — 서버가 후보 종류(1~4/5~8)와
        //   nationalityStatus(domestic · id_document_declared) 판정에 쓴다. 옛 계정은 보내지 않는다(기존 판정 그대로).
        if (documentKind != null) 'documentKind': documentKind,
      });
      newIdCardPath = null; // CF 성공 — Storage 정리 불필요

      // 3. 기존 이미지는 서버가 지운다.
      //    [DOC-LATE-DELETE.7] callableMarkIdCardVerified 가 교체 커밋에서 옛 경로를 정리 대기로
      //    올리고 지운다. 신분증 객체는 Storage 규칙상 클라이언트가 지우지 못한다 — 승인 뒤 늦게
      //    끝나는 클라이언트 삭제가 현재 사진을 지우는 경쟁을 닫기 위해서다.

      // UserProvider 갱신
      await userProvider.refreshCurrentUser();
      if (!mounted) return;

      ToastHelper.showSuccess('신분증이 등록되었습니다');
      _hasChanges = true;
    } catch (e) {
      // [M-19] CF 실패 시 업로드된 신분증 파일 Storage orphan 방지.
      //   [DOC-LATE-DELETE.7] 서버에 정리를 맡긴다 — 응답만 늦고 실제로는 등록된 경우(현재 사진)면
      //   서버가 지우지 않는다. 등록 처리가 아직 진행 중이면 정리가 먼저 그 경로를 막는다.
      if (newIdCardPath != null) {
        try {
          await FirebaseFunctions.instanceFor(region: 'asia-northeast3')
              .httpsCallable('callableDiscardIdCardUpload')
              .call({'storagePath': newIdCardPath});
        } catch (e) {
          debugPrint('⚠️ 업로드 정리 요청 실패 (무시): $e');
        }
      }
      if (mounted) {
        // [서버296 · impl_60] 0바이트(빈) 신분증 파일은 서버가 `ID_CARD_EMPTY` 로 거절한다 — 다시 올리면 되는 일이니
        //   일반 실패가 아니라 무엇을 하면 되는지 말한다.
        final emptyFile = e is FirebaseFunctionsException &&
            e.details is Map &&
            (e.details as Map)['code'] == 'ID_CARD_EMPTY';
        ToastHelper.showError(emptyFile
            ? '신분증 사진 파일이 비어 있어요. 다시 찍거나 골라 주세요.'
            : '신분증 등록에 실패했습니다');
      }
    } finally {
      if (mounted) setState(() { _isLoading = false; _loadingMessage = null; });
    }
  }

  /// 통장 정보 저장
  /// [BATCH-1B Policy 5] callableUpdateBankAccount CF 경유 — 계좌 변경 시 bankVerificationStatus 자동 초기화
  /// 기존 updateUserDocument() 직접 쓰기(plain text accountNumber)에서 CF 경유로 전환
  /// [V3 FOREIGN HOLDER] accountHolder: 외국인이면 사용자가 입력한 예금주명, 내국인이면 null (CF가 name으로 자동)
  Future<void> _saveBankInfo({String? accountHolder}) async {
    if (_selectedBank == null || _accountNumberController.text.trim().isEmpty) {
      ToastHelper.showWarning('은행과 계좌번호를 입력해주세요');
      return;
    }

    final userProvider = context.read<UserProvider>();
    if (userProvider.currentUser == null) return;

    setState(() => _isLoading = true);

    try {
      // [BATCH-1B] CF callableUpdateBankAccount — 계좌 변경 + bankVerificationStatus 리셋 원자적 처리
      //   accountNumber: EncryptionHelper.encrypt()로 AES 암호화 후 전달
      //   (CF에는 ENCRYPT_KEY 없으므로 클라이언트에서 암호화해서 보내야 함)
      final encryptedAccount = EncryptionHelper.encrypt(_accountNumberController.text.trim())
          ?? _accountNumberController.text.trim(); // ENCRYPT_KEY 미설정 시 plain text 폴백
      final payload = <String, dynamic>{
        'bankName': _selectedBank,
        'accountNumber': encryptedAccount,
      };
      // [V3 FOREIGN HOLDER] 외국인만 accountHolder 포함 — CF가 isForeign 분기로 처리
      if (accountHolder != null && accountHolder.isNotEmpty) {
        payload['accountHolder'] = accountHolder;
      }
      await FirebaseFunctions.instanceFor(region: 'asia-northeast3')
          .httpsCallable('callableUpdateBankAccount')
          .call(payload);

      await userProvider.refreshCurrentUser();
      if (!mounted) return;

      ToastHelper.showSuccess('급여정보가 저장되었습니다');
      _hasChanges = true;
    } catch (e, stack) {
      // Crashlytics에 non-fatal 기록 — 릴리스 빌드에서도 Firebase Console에서 확인 가능
      final code = e is FirebaseFunctionsException ? e.code : null;
      FirebaseCrashlytics.instance.recordError(
        e, stack,
        reason: 'callableUpdateBankAccount 실패 (code=$code)',
        fatal: false,
      );
      if (mounted) {
        // FirebaseFunctionsException의 code로 원인별 안내 분기
        final msg = switch (code) {
          'unauthenticated' => '인증에 실패했습니다. 앱을 재시작 후 다시 시도해 주세요.',
          'permission-denied' => '권한이 없습니다. 지원자 계정으로 로그인 후 이용해 주세요.',
          'failed-precondition' => '계정 정보가 완전하지 않습니다. 이름을 먼저 등록해 주세요.',
          _ => '급여정보 저장에 실패했습니다',
        };
        ToastHelper.showError(msg);
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// 신분증 삭제
  Future<void> _deleteIdCard() async {
    if (_isLoading) return;
    final confirmed = await DialogHelper.showDangerConfirm(
      context,
      title: '신분증 삭제',
      message: '삭제하면 다시 등록해야 합니다.\n등록된 신분증을 삭제하시겠습니까?',
      confirmText: '삭제',
    );

    if (!confirmed || !mounted) return;

    final userProvider = context.read<UserProvider>();
    final user = userProvider.currentUser;

    if (user == null) return;

    setState(() => _isLoading = true);

    try {
      // [HIGH-01] CF callableDeleteIdCard — Firestore 먼저 업데이트 + Storage best-effort 삭제 CF 내부 처리
      await FirebaseFunctions.instanceFor(region: 'asia-northeast3')
          .httpsCallable('callableDeleteIdCard')
          .call({});

      await userProvider.refreshCurrentUser();
      if (!mounted) return;

      ToastHelper.showSuccess('신분증이 삭제되었습니다');
      _hasChanges = true;
    } catch (e) {
      debugPrint('❌ 신분증 삭제 실패: $e');
      if (mounted) ToastHelper.showError('신분증 삭제에 실패했습니다');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// 통장 정보 삭제
  Future<void> _deleteBankInfo() async {
    if (_isLoading) return;
    final confirmed = await DialogHelper.showDangerConfirm(
      context,
      title: '급여 계좌 삭제',
      message: '삭제하면 다시 등록해야 합니다.\n등록된 급여 계좌 정보를 삭제하시겠습니까?',
      confirmText: '삭제',
    );

    if (!confirmed || !mounted) return;

    final userProvider = context.read<UserProvider>();
    final user = userProvider.currentUser;

    if (user == null) return;

    setState(() => _isLoading = true);

    try {
      // CF callableDeleteBankInfo — Firestore 먼저 업데이트(Admin SDK) + Storage best-effort 삭제
      // isBankbookVerified/bankbookVerifiedAt 초기화도 CF 내부에서 처리
      await FirebaseFunctions.instanceFor(region: 'asia-northeast3')
          .httpsCallable('callableDeleteBankInfo')
          .call({});

      await userProvider.refreshCurrentUser();
      if (!mounted) return;

      setState(() {
        _selectedBank = null;
        _accountNumberController.clear();
      });

      ToastHelper.showSuccess('급여정보가 삭제되었습니다');
      _hasChanges = true;
    } catch (e) {
      debugPrint('❌ 급여정보 삭제 실패: $e');
      if (mounted) ToastHelper.showError('급여정보 삭제에 실패했습니다');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ── [DOCUMENT-VERIFICATION-INTEGRITY-R0] 문서 상태 표시 ─────────────────
  //
  //   금지: 업로드됨을 '확인 완료'처럼 보이게 하는 문구.
  //   '확인 완료'는 사람이 확인한 상태(MANUAL_APPROVED) 하나뿐이다.

  ({String label, Color color, IconData icon}) _idCardStatus(UserModel user) =>
      _docStatus(user.idCardDocumentState);

  ({String label, Color color, IconData icon}) _bankbookStatus(UserModel user) =>
      _docStatus(user.bankbookDocumentState);

  // [DU627b · 판정207 §4] 상태 칩 글/아이콘 = 실제 상태 의미색의 읽히는 짝(success/error/warning → *Dark · 13/w600 글 4.5 이상) — 세무 칩과 같은 짝. '제출 완료' infoDark(정보 상태)는 그대로.
  ({String label, Color color, IconData icon}) _docStatus(String? state) {
    switch (state) {
      case 'MANUAL_APPROVED':
        return (
          label: '확인 완료',
          // [R7-P1-7 P17-D] 같은 함수의 다른 분기는 error/warning/infoDark 를 쓰는데
          //   이 한 줄만 raw 초록이었다 — 앱의 success 초록과 달라 '완료'가 두 색이 된다.
          color: AppColors.successDark,
          icon: Icons.check_circle_rounded
        );
      case 'MANUAL_REJECTED':
      case 'REUPLOAD_REQUIRED':
        return (
          label: '다시 등록 필요',
          color: AppColors.errorDark,
          icon: Icons.error_outline
        );
      case 'SELF_CHECK_OVERRIDDEN':
      case 'MANUAL_REVIEW_REQUIRED':
        return (
          label: '관리자 확인 중',
          color: AppColors.warningDark,
          icon: Icons.hourglass_top
        );
      case 'SELF_CHECK_PASSED':
        return (
          label: '제출 완료',
          color: AppColors.textSecondary,
          icon: Icons.task_alt
        );
      default:
        // 상태가 없는 기존 제출물. 통과로 읽지 않는다 — 제출됐다고만 말한다.
        return (
          label: '제출 완료',
          color: AppColors.textSecondary,
          icon: Icons.task_alt
        );
    }
  }

  /// [DU1 후속110 S038] 완전 미등록의 상태 표시 — 세무(_taxStatusChip 미등록)와 같은 중립 아이콘·색·문구.
  static const ({String label, Color color, IconData icon}) _unregisteredStatus =
      (label: '미등록', color: AppColors.textSecondary, icon: Icons.remove_circle_outline);

  Widget _docStatusChip(
      BuildContext context, ({String label, Color color, IconData icon}) s) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(s.icon, color: s.color, size: 18),
      SizedBox(width: ResponsiveHelper.spacing(context, 4)),
      Text(s.label,
          style: ResponsiveHelper.smallStyle(context,
              color: s.color, fontWeight: FontWeight.w600)),
    ]);
  }

  // ══════════════════════════════════════════════════════════════
  // [PII-B4-R1.4] 세무정보
  //
  //   등록된 번호는 **다시 보여주지 않는다**(§27). 서버가 응답에 싣지
  //   않으므로 앱이 알 수도 없다. 화면이 말하는 것은 "등록됐는가"와
  //   "지금 신분증과 어긋난 것이 확인됐는가" 둘뿐이다.
  // ══════════════════════════════════════════════════════════════

  /// 이 화면에 세무정보 항목을 띄울 것인가.
  ///
  ///   서버 응답을 우선한다 — Remote Config는 화면용 스위치이고,
  ///   실제로 등록을 받는지 아는 쪽은 서버다. 이미 등록된 사람에게는
  ///   플래그와 무관하게 상태를 보여준다(감추면 사라진 것처럼 보인다).
  bool get _showsTaxIdentity {
    final s = _taxStatus;
    if (s == null) return false;
    if (s.registered) return true;
    return s.collectionEnabled || TaxIdentityService.collectionEnabledLocally;
  }

  /// [PII-B4-R1.4.1 §12] 외국인인데 세무 레코드가 없다 — 수집이 꺼져 있던
  ///   때 가입한 계정이다. 이때만 한 번 등록할 길을 연다. 정상 가입자는
  ///   이미 등록돼 있으므로 이 상태가 되지 않는다.
  bool get _needsForeignTaxRecovery =>
      _taxStatus?.foreignRecoveryAvailable == true;

  ({String label, Color color, IconData icon}) _taxStatusChip() {
    final s = _taxStatus;
    if (s == null || s.loadFailed) {
      return (label: '확인 불가', color: AppColors.textSecondary, icon: Icons.help_outline); // [DU1 구현89] grey500 2.68 → textSecondary
    }
    if (!s.registered) {
      return (label: '미등록', color: AppColors.textSecondary, icon: Icons.remove_circle_outline); // [DU1 구현89] grey500 2.68 → textSecondary
    }
    if (s.blocksApply) {
      // [DU1 구현141 ⑤] 상태 글 13 / w600 · 아이콘이 이 색을 쓴다 — errorFaded 는 흰 카드 위 3.49(작은 글 4.5 미만, 구현134 관측).
      return (label: '정보 확인 필요', color: AppColors.errorDark, icon: Icons.error_outline);
    }
    return (label: '등록 완료', color: AppColors.successDark, icon: Icons.check_circle);
  }

  Widget _buildTaxIdentitySection(UserModel user) {
    final s = _taxStatus;
    final registered = s?.registered == true;
    // [§3·§65] 외국인은 가입 시 등록된다 — 여기서 번호를 다시 묻지 않는다.
    final isForeign = user.isForeign;
    final chip = _taxStatusChip();

    return Container(
      padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 16)),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.grey200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(Icons.receipt_long_outlined,
                  size: 22,
                  color: registered ? AppColors.textSecondary : AppColors.grey400),
              SizedBox(width: ResponsiveHelper.spacing(context, 12)),
              // [DU1 구현137 ②] 제목 · 부제 묶음과 상태 칩을 Wrap 으로(C128-3 과 같은 원칙) — 한 줄에 들어가면 칩이 예전처럼 오른쪽,
              //   모자라면(좁은 폭 · 큰 글자) 칩이 아래 줄로 가서 제목 '세무정보' · 부제가 음절로 끊기지 않는다(구현134 B 관측: 세 / 무 / 정 / 보).
              Expanded(
                child: Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  runSpacing: ResponsiveHelper.spacing(context, 6),
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('세무정보',
                            style: ResponsiveHelper.bodyStyle(context)
                                .copyWith(fontWeight: FontWeight.w600)),
                        Text(
                          isForeign
                              ? (_needsForeignTaxRecovery
                                  ? '가입 시 확인한 외국인등록번호를 등록해주세요'
                                  : '가입 시 등록됨 — 외국인등록번호')
                              : '소득신고에 쓰이는 주민등록번호',
                          style: ResponsiveHelper.tinyStyle(context,
                              color: isForeign && registered
                                  ? AppColors.successDark
                                  // [DU1 구현89 S038] 부제 grey500 2.68:1(PNG) → textSecondary
                                  : AppColors.textSecondary),
                        ),
                      ],
                    ),
                    _docStatusChip(context, chip),
                  ],
                ),
              ),
            ],
          ),

          // 불일치는 근로자가 할 일이 있다는 뜻이다 — 무엇을 할지 말한다.
          if (s?.blocksApply == true) ...[
            SizedBox(height: ResponsiveHelper.spacing(context, 10)),
            Container(
              width: double.infinity,
              padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 10)),
              decoration: BoxDecoration(
                color: AppColors.errorFaded.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '등록한 세무정보와 신분증 정보가 달라 보입니다.\n'
                '세무정보를 수정하거나 신분증을 다시 등록해주세요.',
                // [DU1 구현136 V6] 글색만 errorDark — errorFaded 는 자기 8% 면(실측 #FEF1F1) 위 3.17(작은 글 4.5 미만, 구현134 관측). 면은 그대로.
                style: ResponsiveHelper.tinyStyle(context,
                    color: AppColors.errorDark),
              ),
            ),
          ],

          Padding(
            padding: EdgeInsets.symmetric(
                vertical: ResponsiveHelper.spacing(context, 12)),
            child: const Divider(
                height: 1, thickness: 0.5, color: AppColors.grey200),
          ),

          // [§28] 외국인은 수정 CTA 없음 — 변경은 신원 재확인이 함께 가야 한다.
          //   [R1.4.1 §12] 단 하나의 예외: 수집이 꺼져 있던 때 가입해
          //   세무 레코드가 없는 계정은 여기서 한 번 등록할 수 있다.
          // [ALFIT-AUTH-KAKAO-ONBOARDING.1 · §5] 국적 미확정이면 국내 번호 등록으로 보내지 않는다 — 서버도 거절한다.
          if (user.isNationalityUnconfirmed)
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                TextLayout.keepWords('신분증 또는 외국인등록증을 먼저 등록하면 세무정보를 등록할 수 있어요.'),
                semanticsLabel: '신분증 또는 외국인등록증을 먼저 등록하면 세무정보를 등록할 수 있어요.',
                style: ResponsiveHelper.smallStyle(context, color: AppColors.textSecondary),
              ),
            )
          else if (isForeign && _needsForeignTaxRecovery)
            _flatPrimaryButton(
              text: '세무정보 등록하기',
              onPressed: _isLoading ? null : () => _openTaxIdentitySheet(user),
            )
          else if (isForeign)
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                registered
                    ? '가입 시 등록되어 추가 입력이 필요하지 않습니다.'
                    : '가입 정보를 확인할 수 없습니다. 고객센터로 문의해주세요.',
                style: ResponsiveHelper.smallStyle(context,
                    color: AppColors.grey600),
              ),
            )
          else if (registered)
            // [DU1 구현135 ①] Row+Spacer 는 좁은 폭·큰 글자에서 오른쪽 안내가 화면 밖으로 넘쳤다(구현134 B 320×640@2.0 관측).
            //   Wrap(spaceBetween): 한 줄에 들어가면 예전처럼 양끝, 아니면 안내가 다음 줄로 내려가 전문 줄바꿈. 문구·동작·색 무변경.
            SizedBox(
              width: double.infinity,
              child: Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: ResponsiveHelper.spacing(context, 12),
                runSpacing: ResponsiveHelper.spacing(context, 6),
                children: [
                  TextButton(
                    onPressed: _isLoading ? null : () => _openTaxIdentitySheet(user),
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      // [DU1 구현139 ③] 글자 버튼도 터치 최소 48×48(C128-1 과 같은 값, 구현137 관측: N 24.1×19 · B 48×37).
                      //   글 폭이 48 보다 좁아(N 24.1) 가운데로 밀리지 않게 왼쪽 정렬 — 글 위치 · 색 · 크기는 그대로.
                      minimumSize: const Size(48, 48),
                      alignment: Alignment.centerLeft,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      foregroundColor: AppColors.grey600,
                    ),
                    child: Text('수정',
                        style: ResponsiveHelper.smallStyle(context,
                            color: AppColors.grey600,
                            fontWeight: FontWeight.w500)),
                  ),
                  // 등록된 번호를 되돌려 보여주는 경로는 두지 않는다(§27).
                  // [DU1 구현140 ④] 부가 설명 글색 textTertiary — grey400 은 흰 카드 위 1.88(작은 글 4.5 미만, 구현134 관측).
                  Text('등록된 번호는 표시되지 않습니다',
                      style: ResponsiveHelper.tinyStyle(context,
                          color: AppColors.textTertiary)),
                ],
              ),
            )
          else
            _flatPrimaryButton(
              text: '세무정보 등록하기',
              onPressed: _isLoading ? null : () => _openTaxIdentitySheet(user),
              // [DU1 구현121 S038 V10] 같은 '입력해서 등록' 행동인 급여정보 등록하기와 같은 + — 세 등록 버튼 중 이것만 아이콘이 없었다.
              icon: Icons.add,
            ),
        ],
      ),
    );
  }

  /// 세무정보 입력 — 등록/수정 공용.
  Future<void> _openTaxIdentitySheet(UserModel user) async {
    FocusScope.of(context).unfocus(); // 키보드 포커스 crash 방지
    final registered = _taxStatus?.registered == true;
    final saved = await DialogHelper.showSheet<bool>(
      context,
      isScrollControlled: true,
      builder: (_) => _TaxIdentitySheet(
        user: user,
        isUpdate: registered,
        isForeignRecovery: _needsForeignTaxRecovery,
      ),
    );
    if (saved == true) {
      _hasChanges = true;
      await _loadTaxIdentity();
    }
  }

  /// 📄 신원 확인 카드 — 단층 구조 (Nested Card 금지)
  /// 아이템 행 + 구분선 + CTA 버튼으로만 구성
  ///
  /// [V3 FOREIGN-DOCUMENT-FIRST]
  ///   외국인 isIdVerified=true: 가입 중 등록된 외국인등록증과 연결됨
  ///   → 재업로드를 요구하지 않음. 이미지 갱신은 허용 (카드 갱신 등).
  Widget _buildIdCardSection(UserModel user) {
    // [BUG-ID-01] 신규 flow는 idCardImagePath만 저장 → idCardImageUrl 없어도 등록 상태 표시
    final hasIdCard = user.idCardImagePath != null || user.idCardImageUrl != null;
    // [V3 FOREIGN-DOCUMENT-FIRST] 외국인 여부 & 가입 시 등록 완료 여부
    final isForeignRegistered = user.isForeign && user.isIdVerified;

    return Container(
      padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 16)),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.grey200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Column(
        children: [
          // ── 아이템 행 ──────────────────────────────────────────────
          Row(
            children: [
              Icon(
                Icons.badge_outlined,
                size: 22,
                // [DU627b · 판정207 §4] 항목 식별 아이콘 = 장식 → 중립 textSecondary(등록됨) / grey400(미등록) — 행의 강조는 오른쪽 상태 칩 하나.
                // 예전 infoDark 는 같은 카드의 brand 단추 · 상태 칩 옆 두 번째 파랑이었다(세무 · 급여 계좌 아이콘도 같은 값).
                color: hasIdCard ? AppColors.textSecondary : AppColors.grey400,
              ),
              SizedBox(width: ResponsiveHelper.spacing(context, 12)),
              // [DU1 구현137 ②] 세무 머리와 같은 Wrap — B 320×2.0 에서 칩 옆 부제가 '주민등록 / 증 또는 운 / 전면허증' 으로 끊겼다(구현136 관측).
              Expanded(
                child: Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  runSpacing: ResponsiveHelper.spacing(context, 6),
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isForeignRegistered ? '외국인등록증' : '신분증',
                          style: ResponsiveHelper.bodyStyle(context)
                              .copyWith(fontWeight: FontWeight.w600),
                        ),
                        Text(
                          isForeignRegistered
                              ? '가입 시 등록됨 — 갱신 시 재업로드 가능'
                              : '주민등록증 또는 운전면허증',
                          style: ResponsiveHelper.tinyStyle(context,
                              color: isForeignRegistered ? AppColors.successDark : AppColors.textSecondary), // [DU1 구현89] 2.68 → textSecondary
                        ),
                      ],
                    ),
                    // [DOCUMENT-VERIFICATION-INTEGRITY-R0] 상태를 그대로 말한다.
                    //
                    //   예전에는 파일이 있기만 하면 '✓ 등록완료'였다. 인식이
                    //   실패했든, 이름이 달랐든, 사용자가 경고를 넘겼든 화면은
                    //   똑같이 초록 체크를 보여줬다 — 그것이 제보된 현상이다.
                    //   '확인 완료'는 사람이 확인한 경우에만 쓴다.
                    if (hasIdCard)
                      _docStatusChip(context, _idCardStatus(user))
                    else
                      // [DU1 후속110 S038] 세무 미등록과 같은 중립 표시(⊖ 미등록) — 이 상태 행에는 탭 동작이 없는데
                      //   chevron 이 '눌러서 이동'처럼 보였다. 등록은 아래 '신분증 등록하기' 버튼이 맡는다.
                      _docStatusChip(context, _unregisteredStatus),
                  ],
                ),
              ),
            ],
          ),

          // ── 구분선 ─────────────────────────────────────────────────
          Padding(
            padding: EdgeInsets.symmetric(
                vertical: ResponsiveHelper.spacing(context, 12)),
            child: const Divider(
                height: 1, thickness: 0.5, color: AppColors.grey200),
          ),

          // [RELEASE-CORRECTION-PRIVACY-INLINE-DISCLOSURE]
          //   올리기 전에 무엇에 쓰이고 누가 언제 열 수 있는지 먼저 말한다.
          //   방침 링크를 눌러야만 알 수 있는 상태로 두지 않는다.
          const PrivacyInlineNotice(
            disclosure: PrivacyDisclosure.idDocument,
            icon: Icons.badge_outlined,
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 12)),

          // ── CTA 버튼 ───────────────────────────────────────────────
          if (hasIdCard)
            // 완료: 경량 텍스트 링크 행 — "다시 등록하기"는 사진 재촬영/재업로드 의미 명확화
            Row(
              children: [
                TextButton(
                  onPressed: _isLoading ? null : _uploadIdCardTap,
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    // [DU1 구현129 C128-1] 글자 링크도 터치 최소 48×48(구현128 관측: 높이 N 19 / B 37). 글자·색·배치는 그대로.
                    minimumSize: const Size(48, 48),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    foregroundColor: AppColors.grey600,
                  ),
                  child: Text('다시 등록하기',
                      style: ResponsiveHelper.smallStyle(context,
                          color: AppColors.grey600,
                          fontWeight: FontWeight.w500)),
                ),
                const Spacer(),
                TextButton(
                  onPressed: _isLoading ? null : _deleteIdCardTap,
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    // [DU1 구현129 C128-1] 글자 링크도 터치 최소 48×48(구현128 관측: 높이 N 19 / B 37). 글자·색·배치는 그대로.
                    minimumSize: const Size(48, 48),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    // [DU1 구현131 C128-2] 인라인 삭제는 글자 링크(채움 없음)라 낮은 강조이고, 색은 작은 글 대비를 넘는 errorDark —
                    //   예전 errorFaded(#EF5350)는 흰 카드 위 3.49:1(작은 글 4.5 미만, 구현128 관측). 확인 dialog 의 강한 red 는 그대로다.
                    foregroundColor: AppColors.errorDark,
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.delete_outline, size: 13),
                    const SizedBox(width: 3),
                    Text('삭제',
                        style: ResponsiveHelper.smallStyle(context,
                            color: AppColors.errorDark,
                            fontWeight: FontWeight.w500)),
                  ]),
                ),
              ],
            )
          else if (user.isNationalityUnconfirmed)
            // [ALFIT-AUTH-KAKAO-ONBOARDING.1] 국적 미확정(새 계정) — 두 서류를 같은 틀로 받는다는 것을 말한다.
            _flatPrimaryButton(
              text: '신분증 · 외국인등록증 등록하기',
              onPressed: _isLoading ? null : _uploadIdCardTap,
              icon: Icons.camera_alt,
            )
          else
            // 미등록: 신분증 등록하기 flat primary
            _flatPrimaryButton(
              text: '신분증 등록하기',
              onPressed: _isLoading ? null : _uploadIdCardTap,
              icon: Icons.camera_alt,
            ),
        ],
      ),
    );
  }

  /// 💳 급여정보 준비 카드 — 단층 구조 (Nested Card 금지)
  /// 완료 조건: 계좌정보(은행+계좌번호) + 통장사본 모두 있어야 등록완료
  ///
  /// 6-상태 분기 (verificationStatus 우선, 없으면 문서 존재 여부로 판단):
  ///   B+ (등록 완료): hasBankAccount && hasBankbookDocument
  ///   B (계좌만)   : hasBankAccount && !hasBankbookDocument
  ///   A (미등록)   : !hasBankAccount
  ///
  /// [PII-DOC-R1.5.5] bankVerificationStatus 기반 3분기('확인 완료' /
  ///   '제출 완료' / '확인 필요')를 제거했다. 그 필드에는 값을 쓰는 서버
  ///   코드가 하나도 없다(남은 것은 legacy 정리용 delete뿐). 아무도 만들지
  ///   않는 값으로 "확인 완료"라고 말하면 하지 않은 확인을 했다고 하는 것이고,
  ///   "확인 필요"라고 말하면 해결할 수 없는 할 일을 주는 것이다.
  ///   남는 것은 사실뿐이다 — 등록됐는가.
  ///   지급 가능 여부의 canonical 판정은 R1.6 Payroll Readiness가 맡는다.
  Widget _buildBankInfoSection(UserModel user) {
    // [V3 FOREIGN HOLDER] user.hasBankAccount getter 사용 — accountHolder 포함
    final hasBankAccount = user.hasBankAccount;
    final hasBankbook = user.hasBankbookDocument;

    // ── 우측 상태 뱃지 ────────────────────────────────────────────
    final Widget statusBadge;
    if (hasBankAccount && hasBankbook) {
      // B+: 계좌 + 통장사본 제출 완료.
      //   [DOCUMENT-VERIFICATION-INTEGRITY-R0] 여기가 '등록완료' 초록 체크였다.
      //   제출은 확인이 아니다 — 서버가 기록한 상태를 그대로 말한다.
      statusBadge = _docStatusChip(context, _bankbookStatus(user));
    } else if (hasBankAccount) {
      // B: 계좌만 있고 통장사본 없음 — '미등록' 표시 금지 (BANKBOOK-UX-01 수정)
      statusBadge = Text('계좌 등록됨',
          style: ResponsiveHelper.smallStyle(context,
              color: AppColors.textSecondary, fontWeight: FontWeight.w500));
    } else {
      // A: 완전 미등록
      // [DU1 후속110 S038] 세무·신분증 미등록과 같은 중립 표시 — chevron 은 탭 동작 없는 상태 행에 '이동'을 암시했다.
      statusBadge = _docStatusChip(context, _unregisteredStatus);
    }

    // ── 부제 텍스트 ────────────────────────────────────────────────
    // accountNumber는 AES-CBC 암호화 저장 → 복호화 불가 → 전체 노출 금지
    // bankName은 평문 저장 → 표시 가능
    final String subText;
    if (hasBankAccount && hasBankbook) {
      // B+: V3 완료 — 은행명만 표시 (통장사본 포함 등록 완료)
      subText = user.bankName ?? '급여 계좌 등록됨';
    } else if (hasBankAccount) {
      // B: 계좌만 — 통장사본 미제출
      subText = '${user.bankName!} · 통장사본 등록 필요';
    } else {
      subText = '은행 · 계좌 · 예금주 · 통장사본';
    }

    // [DU1 구현130 C128-3] 제목 · 은행명 묶음 — 아래 머리 Row 에서 상태에 따라 Wrap / Expanded 로 쓴다(위젯 구성은 예전 Column 그대로).
    final Widget titleBlock = Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('급여 계좌',
                        style: ResponsiveHelper.bodyStyle(context)
                            .copyWith(fontWeight: FontWeight.w600)),
                    Text(subText,
                        // [DU1 구현89 S038] 2.68:1 → textSecondary
                        style: ResponsiveHelper.tinyStyle(context,
                            color: AppColors.textSecondary)),
                  ],
                );

    return Container(
      padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 16)),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.grey200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Column(
        children: [
          // ── 아이템 행 ──────────────────────────────────────────────
          Row(
            children: [
              Icon(
                Icons.account_balance_wallet_outlined,
                size: 22,
                // 계좌가 등록되면 아이콘 색상 활성화 (통장사본 여부 무관)
                color: hasBankAccount ? AppColors.textSecondary : AppColors.grey400,
              ),
              SizedBox(width: ResponsiveHelper.spacing(context, 12)),
              // [DU1 구현130 C128-3] 제출 완료에서는 묶음과 상태 칩을 Wrap 으로 — 한 줄에 들어가면 칩이 예전처럼 오른쪽,
              //   모자라면(좁은 폭 · 큰 글자) 칩이 묶음 아래 줄로 가서 제목 '급여 계좌' 가 음절로 끊기지 않는다
              //   (구현128 관측: B 320×2.0 에서 '급여 계 / 좌'). 계좌만 · 미등록은 예전 Row 배치 그대로.
              // [DU1 구현137 ②] 미등록도 Wrap(B 관측: 부제 '통장 / 사본') — 계좌만(통장사본 없음)은 fixture 가 없어 예전 Row 그대로.
              if (!(hasBankAccount && !hasBankbook))
                Expanded(
                  child: Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    runSpacing: ResponsiveHelper.spacing(context, 6),
                    children: [titleBlock, statusBadge],
                  ),
                )
              else ...[
                Expanded(child: titleBlock),
                // 상태 뱃지 (우측)
                statusBadge,
              ],
            ],
          ),

          // ── 구분선 ─────────────────────────────────────────────────
          Padding(
            padding: EdgeInsets.symmetric(
                vertical: ResponsiveHelper.spacing(context, 12)),
            child: const Divider(
                height: 1, thickness: 0.5, color: AppColors.grey200),
          ),

          // ── CTA ────────────────────────────────────────────────────
          // [PII-DOC-R1.5.5] isVerified / isMismatch / isReviewRequired
          //   세 분기를 제거했다. 모두 bankVerificationStatus 값에 걸려
          //   있었고 그 값을 만드는 서버 코드가 없어 도달 불가였다.
          //   isVerified 분기의 CTA는 아래 등록 완료 분기와 동일했다.
          if (hasBankAccount && hasBankbook)
            // 등록 완료 — 계좌 변경 / 전체 삭제 경량 행
            Row(
              children: [
                TextButton(
                  onPressed: _isLoading ? null : _showBankEditDialog,
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    // [DU1 구현129 C128-1] 글자 링크도 터치 최소 48×48(구현128 관측: 높이 N 19 / B 37). 글자·색·배치는 그대로.
                    minimumSize: const Size(48, 48),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    foregroundColor: AppColors.grey600,
                  ),
                  child: Text('계좌 변경하기',
                      style: ResponsiveHelper.smallStyle(context,
                          color: AppColors.grey600,
                          fontWeight: FontWeight.w500)),
                ),
                const Spacer(),
                TextButton(
                  onPressed: _isLoading ? null : _deleteBankInfoTap,
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    // [DU1 구현129 C128-1] 글자 링크도 터치 최소 48×48(구현128 관측: 높이 N 19 / B 37). 글자·색·배치는 그대로.
                    minimumSize: const Size(48, 48),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    // [DU1 구현131 C128-2] 신분증 삭제와 같은 errorDark(작은 글 대비).
                    foregroundColor: AppColors.errorDark,
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.delete_outline, size: 13),
                    const SizedBox(width: 3),
                    Text('삭제',
                        style: ResponsiveHelper.smallStyle(context,
                            color: AppColors.errorDark,
                            fontWeight: FontWeight.w500)),
                  ]),
                ),
              ],
            )
          else if (hasBankAccount && !hasBankbook)
            // B: 계좌만 — 통장사본 등록 유도
            _flatPrimaryButton(
              text: '통장사본 등록하기',
              onPressed: _isLoading ? null : _uploadBankbookImage,
              icon: Icons.camera_alt,
            )
          else
            // A: 완전 미등록
            _flatPrimaryButton(
              text: '급여정보 등록하기',
              onPressed: _showBankEditDialog,
              icon: Icons.add,
            ),
        ],
      ),
    );
  }

  /// 급여정보 수정 다이얼로그
  Future<void> _showBankEditDialog() async {
    // [FC-DOC-02 OWNERSHIP FIX] _BankEditDialog(StatefulWidget)이 customBankCtrl을
    // 직접 소유하고 State.dispose()에서 해제한다. _accountNumberController는
    // Dialog가 초기값을 받아 로컬 컨트롤러로 관리하고, 결과를 _BankEditResult로 반환.

    // [V3 FOREIGN HOLDER] isForeign + 기존 accountHolder 전달
    final user = context.read<UserProvider>().currentUser;
    // [ALFIT-AUTH-KAKAO-ONBOARDING.1 · server_api_1 §6] 국적 미확정이면 예금주 기준(이름 출처)을 정할 수 없다 —
    //   서버도 NATIONALITY_UNCONFIRMED 로 거절한다. 입력을 받기 전에 서류 먼저라고 말한다.
    if (user != null && user.isNationalityUnconfirmed) {
      ToastHelper.showInfo('신분증 또는 외국인등록증을 먼저 등록해 주세요');
      return;
    }
    final isForeign = user?.isForeign ?? false;
    final initialAccountHolder = user?.accountHolder;

    final result = await showDialog<_BankEditResult>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _BankEditDialog(
        initialBank: _selectedBank,
        initialAccountNumber: _accountNumberController.text,
        isForeign: isForeign,
        initialAccountHolder: initialAccountHolder,
      ),
    );

    if (result == null || !mounted) return;

    final previousBank = _selectedBank; // [BUG-ROLLBACK] 실패 시 롤백용 이전 은행명 보존
    setState(() {
      _selectedBank = result.bankName;
      _accountNumberController.text = result.accountNumber; // _saveBankInfo()가 읽는 컨트롤러 동기화
    });
    try {
      // [BUG-ROLLBACK FIX] CLAUDE.md '낙관적 업데이트 실패 시 롤백 필수' 준수
      // [V3 FOREIGN HOLDER] 외국인이면 result.accountHolder를 CF로 전달
      await _saveBankInfo(accountHolder: result.accountHolder);
    } catch (_) {
      if (mounted) setState(() => _selectedBank = previousBank);
    }
  }

  /// 통장사본 업로드
  /// [AUD-5 ②-3] callable 실패가 '서버가 기록하지 않았음' 이 확정인 오류인가(입력·권한·상태 거절 등).
  ///   시간 초과 · 연결 끊김 · 내부 오류 · 알 수 없음 · 취소는 결과를 모른다 — false.
  static bool _bankbookMarkDefinitelyFailed(Object e) =>
      e is FirebaseFunctionsException &&
      const {
        'invalid-argument',
        'failed-precondition',
        'permission-denied',
        'not-found',
        'unauthenticated',
        'already-exists',
        'resource-exhausted',
        'out-of-range',
        'unimplemented',
      }.contains(e.code);

  Future<void> _uploadBankbookImage() async {
    if (_isLoading) return;
    final userProvider = context.read<UserProvider>();
    final user = userProvider.currentUser;
    if (user == null) return;

    setState(() => _isLoading = true); // 피커 전에 설정 — 피커 도중 이중 탭 방지
    _stage('사진을 준비하고 있어요'); // [PERF-L42] 압축 구간 단계 문구

    // [R8-P5] orphan 추적을 URL 이 아니라 Storage 경로로 한다 —
    //   업로드가 더 이상 download URL 을 만들지 않으므로 지울 대상도 경로다.
    String? newBankbookPath;
    try {
      // [V3 FOREIGN HOLDER] 외국인: user.name 기반 예금주 비교 skip (legalName 불일치 오탐)
      // 내국인: user.name 기반 SOFT 이름 검증 유지
      final picked = await DocumentUploadHelper.pickAndVerifyBankbook(
        context,
        user.isForeign ? null : user.name,
        expectedAccountNumber: (user.accountNumber?.isEmpty ?? true) ? null : user.accountNumber,
        // expectedBankName 미사용: 스크린샷 내 은행명 표기가 다양해 오탐 가능성 높음
      );

      if (picked == null || !mounted) return; // finally가 _isLoading 초기화
      final imagePath = picked.path;

      // [R7-P4.4E.11B §16] 이전 경로를 여기서 캡처하지 않는다 — 서버가
      //   검증해서 돌려주는 `previousBankbookPath` 만 삭제 대상이다.

      // 1. 새 이미지 먼저 업로드 — 예외 여부와 무관하게 임시 파일 삭제 보장
      //
      // [R8-P5] uploadImage → uploadImageNoUrl.
      //   uploadImage 는 업로드 뒤 getDownloadURL() 을 한 번 더 부른다.
      //   DEV 실측 warm 약 250ms 짜리 왕복인데, 그렇게 얻은 URL 로 하는 일이 없다:
      //     · 통장사본 열람은 callableGetBankbookSignedUrl(1시간 Signed URL) 전용이고
      //       ([V3] worker_detail_dialog — bankbookImageUrl 직접 노출 금지)
      //     · callableGetUsersBatch 는 응답에서 이 필드를 지워서 보낸다
      //   그러면서도 **영구 토큰이 박힌 다운로드 URL** 이 PII 문서에 대해 만들어져
      //   Firestore 에 저장되고 있었다. 신분증은 [BUG-ID-01] 로 이미 이 경로를 막았다 —
      //   통장사본만 남아 있었다.
      _stage('사진을 올리고 있어요');
      final storagePath = 'users/${user.uid}/bankbook_${DateTime.now().millisecondsSinceEpoch}.jpg';
      bool uploadOk = false;
      try {
        _lastUploadPct = -1; // [PERF-L42] 보낸 비율을 단계 문구로
        uploadOk = await _storageService.uploadImageNoUrl(imagePath, storagePath,
            onProgress: _uploadProgress);
      } finally {
        // TMP-01: pickAndVerifyBankbook이 반환한 임시 압축 파일.
        try { await File(imagePath).delete(); } catch (_) {}
      }

      if (!uploadOk) {
        if (mounted) ToastHelper.showError('이미지 업로드에 실패했습니다');
        return;
      }

      // 2. CF로 통장사본 canonical state 기록 — Admin SDK 경유로 직접 쓰기 차단 준수
      //    [DOCUMENT-VERIFICATION-INTEGRITY-R0] storagePath 직통 + 기기 확인 근거.
      //    [R8-P5] imageUrl 미전달 — 서버가 canonical 로 쓰는 값은 storagePath 하나다.
      _stage('등록하고 있어요');
      newBankbookPath = storagePath; // CF 호출 전 Storage orphan 추적
      final markResult = await FirebaseFunctions.instanceFor(region: 'asia-northeast3')
          .httpsCallable('callableMarkBankbookVerified')
          .call({
        'storagePath': storagePath,
        'selfCheck': picked.selfCheck,
      });
      newBankbookPath = null; // CF 성공 — Storage 정리 불필요

      // 3. 기존 이미지 삭제 (best-effort)
      //
      // [R7-P4.4E.11B §16·§17] 예전엔 **클라이언트가 자기 로컬 모델의**
      //   `bankbookImagePath`/`bankbookImageUrl` 을 그대로 믿고 지웠다.
      //   그 값이 (패치 전에 심어진) 신분증 경로라면 신분증 object 가
      //   삭제됐다 — 통장사본 교체가 다른 서류를 파괴하는 경로였다.
      //
      //   이제 서버가 트랜잭션에서 읽은 값을 통장사본 술어로 검증해
      //   `previousBankbookPath` 로 돌려준다. 그 값만 지운다.
      //   경로 문법을 클라이언트에 복제하지 않는다.
      final prev = (markResult.data is Map)
          ? (markResult.data as Map)['previousBankbookPath'] as String?
          : null;
      // [PERF-L42] 서버(callableMarkBankbookVerified)가 같은 거래에서 옛 경로를 정리 목록에 올리고
      //   응답 전에 지운다(functions/src/index.ts — arrayUnion(safePrevPath) · await srvDrainBankbookCleanup).
      //   그래서 평소에는 클라이언트가 같은 파일을 한 번 더 지우지 않는다. 서버가 아직 못 지웠다고 알릴 때만
      //   (`cleanupPending == true`) 예전처럼 한 번 지운다 — 지워도 지우지 않아도 안전하다(서버가 다시 시도한다).
      final cleanupPending = (markResult.data is Map) &&
          (markResult.data as Map)['cleanupPending'] == true;
      if (cleanupPending && prev != null && prev.isNotEmpty) {
        try {
          await _storageService.deleteImage(prev);
        } catch (e) {
          debugPrint('⚠️ 기존 통장사본 삭제 실패 (무시): $e');
        }
      }

      await userProvider.refreshCurrentUser();
      if (!mounted) return;

      _hasChanges = true;
      ToastHelper.showSuccess('통장사본이 등록되었습니다');
    } catch (e) {
      // [R8-P5] CF 실패 시 업로드된 통장사본 Storage orphan 방지 (경로 기반 — 신분증과 동일)
      // [AUD-5 ②-3] 단, **서버가 기록하지 않았다고 확정된 실패**일 때만 지운다. 시간 초과 · 연결 끊김처럼 결과를 모르는
      //   실패에서 지우면, 서버가 이미 현재 통장사본으로 등록한 파일을 앱이 지워 users 는 '등록' 인데 파일이 없게 됐다.
      //   결과를 모르면 지우지 않고 users 문서를 다시 읽어 실제로 등록됐는지 확인한다(등록됐으면 성공으로 맞춘다).
      var committed = false;
      if (newBankbookPath != null) {
        if (_bankbookMarkDefinitelyFailed(e)) {
          try { await _storageService.deleteImage(newBankbookPath); } catch (_) {}
        } else {
          try {
            await userProvider.refreshCurrentUser();
            committed = userProvider.currentUser?.bankbookImagePath == newBankbookPath;
          } catch (_) {}
        }
      }
      if (committed) {
        _hasChanges = true;
        if (mounted) ToastHelper.showSuccess('통장사본이 등록되었습니다');
      } else if (mounted) {
        ToastHelper.showError('통장사본 등록에 실패했습니다');
      }
    } finally {
      if (mounted) setState(() { _isLoading = false; _loadingMessage = null; });
    }
  }

  // ============================================================
  // 공통 UI 헬퍼 위젯
  // ============================================================

  /// 플랫 기본 버튼 — Gradient 없음, ALfit Blue 단색
  Widget _flatPrimaryButton({
    required String text,
    required VoidCallback? onPressed,
    IconData? icon,
  }) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          // [DU1 구현89 S038] 옛 #1565C0 이 같은 화면 단계 원(브랜드 #3859E8)·앱 주 행동색과 달랐다 — 브랜드 토큰(흰 글자 5.58:1).
          backgroundColor: AppColors.brand,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: EdgeInsets.symmetric(
              vertical: ResponsiveHelper.spacing(context, 10)),  // 14→10: 카드 시각 무게 경감
          // [DU1 구현89 S038] 실측 48 — 공통 기준 주 버튼 최소 52(여백은 그대로, 최소값만).
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12)),
          disabledBackgroundColor: AppColors.grey200,
          disabledForegroundColor: AppColors.grey500,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 18),
              SizedBox(width: ResponsiveHelper.spacing(context, 6)),
            ],
            // [R7-P2-1 후속 H6-D] 320dp·글자 2.0 에서 '신분증 등록하기' 가
            //   Row 를 0.3px~30px 넘겼다(측정). 아이콘과 함께 놓이는 라벨은
            //   남는 폭 안에서 줄어들게 한다 — 버튼이 잘려 나가지 않는다.
            Flexible(
              child: Text(text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: ResponsiveHelper.bodyStyle(context,
                      color: Colors.white, fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      ),
    );
  }

  /// 섹션 헤더 (settings_screen.dart 동일 스타일)
  ///   [DU485] 설정 화면은 DU241 에서 16 bold 본문색 · 아이콘 없음으로 바뀌었는데 여기는 옛 양식(grey500 작은 글자 + 아이콘 · grey50 위 약 2.6)이었다.
  ///   설정의 `_buildSectionHeader` 와 같은 정의로 맞춘다. 원문 그대로(짧은 두세 낱말).
  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: EdgeInsets.only(left: ResponsiveHelper.spacing(context, 4)),
      child: Text(
        title,
        style: const TextStyle(
            fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
      ),
    );
  }

  /// 안내 배너 (CommonWidgets.infoCard 대체)
  Widget _buildInfoBanner({
    required String message,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 14),
        vertical: ResponsiveHelper.spacing(context, 10),
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: color),
          SizedBox(width: ResponsiveHelper.spacing(context, 8)),
          Expanded(
            child: Text(
              message,
              style: ResponsiveHelper.tinyStyle(context, color: color),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// FC-DOC-02 OWNERSHIP FIX: _BankEditDialog
// customBankCtrl + accountNumberCtrl을 Dialog State가 직접 소유하고 dispose().
// ─────────────────────────────────────────────────────────────────────────────

class _BankEditResult {
  final String bankName;
  final String accountNumber;
  // [V3 FOREIGN HOLDER] 외국인만 사용 — 내국인은 null (CF가 users.name으로 자동 설정)
  final String? accountHolder;
  const _BankEditResult({
    required this.bankName,
    required this.accountNumber,
    this.accountHolder,
  });
}

class _BankEditDialog extends StatefulWidget {
  final String? initialBank;
  final String initialAccountNumber;
  // [V3 FOREIGN HOLDER] 외국인만 사용 — 내국인은 false
  final bool isForeign;
  final String? initialAccountHolder;

  const _BankEditDialog({
    this.initialBank,
    required this.initialAccountNumber,
    this.isForeign = false,
    this.initialAccountHolder,
  });

  @override
  State<_BankEditDialog> createState() => _BankEditDialogState();
}

class _BankEditDialogState extends State<_BankEditDialog> {
  late String? _localBank;
  final _customBankCtrl = TextEditingController();
  late final TextEditingController _accountNumberCtrl;
  // [V3 FOREIGN HOLDER] 외국인용 예금주명 컨트롤러
  late final TextEditingController _accountHolderCtrl;

  @override
  void initState() {
    super.initState();
    _localBank = widget.initialBank;
    _accountNumberCtrl = TextEditingController(text: widget.initialAccountNumber);
    _accountHolderCtrl = TextEditingController(text: widget.initialAccountHolder ?? '');
  }

  @override
  void dispose() {
    _customBankCtrl.dispose();
    _accountNumberCtrl.dispose();
    _accountHolderCtrl.dispose();
    super.dispose();
  }

  String get _effectiveBankName => _localBank == '기타 (직접 입력)'
      ? _customBankCtrl.text.trim()
      : (_localBank ?? '');

  bool get _isSaveEnabled {
    final baseOk = _effectiveBankName.isNotEmpty &&
        _accountNumberCtrl.text.trim().isNotEmpty;
    if (!widget.isForeign) return baseOk;
    // 외국인: 예금주명 필수
    return baseOk && _accountHolderCtrl.text.trim().isNotEmpty;
  }

  @override
  Widget build(BuildContext context) {
    return StyledDialog(
      title: '급여정보 입력',
      subtitle: '급여 수령에 사용할 계좌 정보를 입력하세요',
      icon: Icons.account_balance_wallet,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppSelectField<String>(
            value: _localBank,
            hintText: '은행 / 증권사를 선택하세요',
            sheetTitle: '금융기관 선택',
            searchHint: '은행명을 검색해주세요',
            labelOf: (b) => b,
            prefixIcon: Icons.account_balance,
            // Dialog 안에서 바텀시트를 열 때 루트 Navigator 사용 — Focus/Overlay 중첩 크래시 방지
            useRootNavigator: true,
            groups: const [
              AppSelectGroup(
                header: '주요 은행',
                items: ['KB국민은행', '신한은행', 'NH농협은행', '우리은행', '하나은행', 'IBK기업은행'],
              ),
              AppSelectGroup(
                header: '인터넷 은행',
                items: ['카카오뱅크', '토스뱅크', '케이뱅크'],
              ),
              AppSelectGroup(
                header: '기타 금융기관',
                items: [
                  'SC제일은행', '씨티은행', 'KDB산업은행', '수협은행',
                  '경남은행', '광주은행', '대구은행', '부산은행', '전북은행', '제주은행',
                  '새마을금고', '신협', '저축은행', '우체국',
                  '미래에셋증권', '삼성증권', 'NH투자증권', 'KB증권', '한국투자증권',
                  '키움증권', '신한투자증권', '대신증권', '메리츠증권', '하나증권',
                  '교보증권', '현대차증권', '유안타증권',
                  '기타 (직접 입력)',
                ],
              ),
            ],
            onChanged: (value) => setState(() {
              _localBank = value;
              if (value != '기타 (직접 입력)') _customBankCtrl.clear();
            }),
          ),
          // '기타' 선택 시 직접 입력 필드 표시
          if (_localBank == '기타 (직접 입력)') ...[
            SizedBox(height: ResponsiveHelper.spacing(context, 12)),
            CommonWidgets.textField(
              context: context,
              controller: _customBankCtrl,
              label: '금융기관명 직접 입력',
              hint: '예: OO저축은행, OO캐피탈',
              icon: Icons.edit_outlined,
              onChanged: (_) => setState(() {}),
            ),
          ],
          SizedBox(height: ResponsiveHelper.spacing(context, 16)),
          CommonWidgets.textField(
            context: context,
            controller: _accountNumberCtrl,
            label: '계좌번호',
            hint: '- 없이 숫자만 입력',
            icon: Icons.credit_card,
            keyboardType: TextInputType.number,
            onChanged: (_) => setState(() {}),
          ),
          // [V3 FOREIGN HOLDER] 외국인만 예금주명 입력 필드 표시
          // 내국인은 CF가 users.name으로 자동 설정
          if (widget.isForeign) ...[
            SizedBox(height: ResponsiveHelper.spacing(context, 16)),
            CommonWidgets.textField(
              context: context,
              controller: _accountHolderCtrl,
              label: '예금주명',
              hint: '통장에 표시된 예금주명을 입력해주세요',
              icon: Icons.person_outline,
              onChanged: (_) => setState(() {}),
            ),
          ],
        ],
      ),
      actions: [
        StyledDialogButton.cancel(
          onPressed: () => Navigator.pop(context),
        ),
        StyledDialogButton.primary(
          text: '저장',
          // 은행 선택 + 계좌번호 미입력 시 null → 자동 disabled (grey)
          // 외국인: 예금주명도 필수 (_isSaveEnabled에서 검증)
          onPressed: _isSaveEnabled
              ? () => Navigator.pop(
                    context,
                    _BankEditResult(
                      bankName: _effectiveBankName,
                      accountNumber: _accountNumberCtrl.text.trim(),
                      // 외국인만 accountHolder 전달 — 내국인은 null (CF가 name으로 자동)
                      accountHolder: widget.isForeign
                          ? _accountHolderCtrl.text.trim()
                          : null,
                    ),
                  )
              : null,
        ),
      ],
    );
  }
}

// ══════════════════════════════════════════════════════════════
// [PII-B4-R1.4] 세무정보 입력 시트
//
//   여기가 전체번호를 손에 쥐는 **유일한 순간**이다. 그래서 신분증
//   대조도 여기서 한다 — 등록이 끝나면 앱은 그 번호를 다시 알 수 없다.
//
//   제출 후에는 컨트롤러를 비우고 시트를 닫는다(§29).
// ══════════════════════════════════════════════════════════════
/// [FULL13-REEVAL.2] 위젯 시험용 주입 지점 — Storage·ML Kit·callable 대신 합성 함수를 넣는다.
///   운영 코드는 이 값을 설정하지 않는다(null 이면 실제 구현).
@visibleForTesting
class TaxIdentitySheetHooks {
  static Future<File?> Function(String storagePath)? download;
  static Future<Map<String, dynamic>> Function(
      String imagePath, String expectedName, String expected, bool isForeign)? ocr;
  static Future<String?> Function(String kind, String value,
      DocFieldOutcome match, TaxIdDocumentEvidence? evidence)? submit;
  static Future<ForeignIdOcrResult> Function(String imagePath)? foreignOcr;

  static void reset() {
    download = null;
    ocr = null;
    submit = null;
    foreignOcr = null;
  }
}

/// [FULL13-REEVAL.2] 위젯 시험에서 시트를 직접 띄운다.
@visibleForTesting
Widget debugTaxIdentitySheet({
  required UserModel user,
  bool isUpdate = false,
  bool isForeignRecovery = false,
}) =>
    _TaxIdentitySheet(
        user: user, isUpdate: isUpdate, isForeignRecovery: isForeignRecovery);

class _TaxIdentitySheet extends StatefulWidget {
  const _TaxIdentitySheet({
    required this.user,
    required this.isUpdate,
    this.isForeignRecovery = false,
  });

  final UserModel user;
  final bool isUpdate;

  /// [R1.4.1] 수집이 꺼져 있을 때 가입한 외국인의 1회 복구인가.
  ///   서버가 입력값을 가입 때 만든 신원 지문과 대조한다(번호 확인).
  ///   [FULL13-REEVAL.2] 그와 별개로, 올라간 등록증이 있으면 그 사진을 다시
  ///   읽어 문서 대조 근거를 보낸다(대조 버튼·안내 문구는 붙이지 않는다).
  ///   이름은 독립 근거가 없어 UNASSESSED 로 보낸다.
  final bool isForeignRecovery;

  @override
  State<_TaxIdentitySheet> createState() => _TaxIdentitySheetState();
}

class _TaxIdentitySheetState extends State<_TaxIdentitySheet> {
  final _frontCtrl = TextEditingController();
  final _backCtrl = TextEditingController();
  final _backFocus = FocusNode();

  /// [FULL13-REEVAL.3] 외국인 복구에서만 — 등록증 기재대로 직접 입력하는 영문 이름.
  ///   비교에만 쓰고 저장하지 않는다.
  final _legalNameCtrl = TextEditingController();

  bool _busy = false;
  String? _error;

  /// 신분증 대조 결과 — 하지 않았으면 UNASSESSED다.
  ///
  ///   이 값은 **등록 가부를 정하지 않는다**. 서버가 형식·본인인증 정보·
  ///   검증부호로 판단하고, 이건 "확인이 필요한가"를 말할 뿐이다(§20).
  DocFieldOutcome _match = DocFieldOutcome.unassessed;
  bool _checking = false;

  /// [FULL13-REEVAL] 현재 업로드 신분증을 다시 읽은 근거 — 서버가 판정한다.
  ///   입력이 바뀌면 버린다(그 값에 대한 근거가 아니다).
  TaxIdDocumentEvidence? _evidence;

  bool get _hasUploadedIdCard =>
      (widget.user.idCardImagePath?.isNotEmpty ?? false) &&
      (widget.user.idDocumentVersion ?? 0) > 0;

  /// 본인 Storage 경로의 현재 신분증을 임시 파일로 받는다(호출자가 삭제).
  ///   쓰기 도중 실패하면 반쯤 쓴 파일을 여기서 지운다.
  Future<File?> _downloadUploadedIdCard() async {
    final path = widget.user.idCardImagePath!;
    final hook = TaxIdentitySheetHooks.download;
    if (hook != null) return hook(path);
    final bytes =
        await FirebaseStorage.instance.ref(path).getData(10 * 1024 * 1024);
    if (bytes == null) return null;
    final dir = await getTemporaryDirectory();
    final file = File(
        '${dir.path}/tax_idcheck_${DateTime.now().millisecondsSinceEpoch}.jpg');
    try {
      await file.writeAsBytes(bytes, flush: true);
    } catch (_) {
      try {
        await file.delete();
      } catch (_) {/* 없으면 무시 */}
      rethrow;
    }
    return file;
  }

  Future<Map<String, dynamic>> _ocr(String imagePath) async {
    if (widget.isForeignRecovery) {
      // [FULL13-REEVAL.3] 외국인 복구: 가입 때와 같은 등록증 OCR 로 읽고,
      //   이번에 직접 입력한 영문 이름과 비교한다(저장된 legalName 은 OCR 로 채워졌을
      //   수 있어 기준으로 쓰지 않는다). 번호는 후보로만 — 판정은 서버가 한다.
      final fHook = TaxIdentitySheetHooks.foreignOcr;
      final r = fHook != null
          ? await fHook(imagePath)
          : await ForeignIdOcrService.recognizeFromPath(imagePath);
      final raw = (r.foreignIdRaw ?? '').replaceAll(RegExp(r'\D'), '');
      return {
        'identifierOutcome': raw.length == 13
            ? (raw == _entered ? DocFieldOutcome.matched : DocFieldOutcome.mismatch)
            : DocFieldOutcome.unreadable,
        'nameOutcome':
            ForeignIdOcrService.compareTypedLegalName(_legalNameCtrl.text, r),
        'identifierCandidates': raw.length == 13 ? <String>[raw] : const <String>[],
      };
    }
    final name = widget.user.name;
    final hook = TaxIdentitySheetHooks.ocr;
    if (hook != null) return hook(imagePath, name, _entered, false);
    return OcrVerificationHelper.verifyIdCardName(
      imagePath,
      name,
      expectedResidentNumber: _entered,
    );
  }

  @override
  void dispose() {
    _frontCtrl.dispose();
    _backCtrl.dispose();
    _backFocus.dispose();
    _legalNameCtrl.dispose();
    super.dispose();
  }

  String get _entered =>
      '${_frontCtrl.text.trim()}${_backCtrl.text.trim()}'
          .replaceAll(RegExp(r'\D'), '');

  bool get _canSubmit => _entered.length == 13 && !_busy;

  /// 신분증 사진과 대조. 선택 사항이며, 실패해도 등록을 막지 않는다.
  ///
  ///   [FULL13-REEVAL] 신분증이 이미 올라가 있으면 **그 사진**을 다시 읽는다 —
  ///   새로 찍은 사진은 서버의 현재 문서가 아니다. 그 근거([_evidence])를
  ///   등록과 함께 보내면 서버가 입력 13자리와 대조해 자동 대조를 다시 적는다.
  Future<void> _compareWithIdCard() async {
    if (_entered.length != 13) return;
    setState(() => _checking = true);
    File? image;
    try {
      final uploaded = _hasUploadedIdCard;
      image = uploaded
          ? await _downloadUploadedIdCard()
          : await ImageHelper.pickAndCompressImage(
              context,
              type: ImageType.document,
              useBottomSheet: true,
            );
      if (image == null || !mounted) return;
      final result = await _ocr(image.path).timeout(
          const Duration(seconds: 30),
          onTimeout: () => <String, dynamic>{});
      if (!mounted) return;
      // 시간 초과·인식 오류는 "못 읽었다"가 아니라 "판정 안 함"이다 — 근거를 보내지 않는다.
      final assessed = result.containsKey('identifierOutcome');
      setState(() {
        _match = result['identifierOutcome'] as DocFieldOutcome? ??
            DocFieldOutcome.unassessed;
        _evidence = (uploaded && assessed)
            ? TaxIdDocumentEvidence(
                idDocumentVersion: widget.user.idDocumentVersion!,
                name: result['nameOutcome'] as DocFieldOutcome? ??
                    DocFieldOutcome.unassessed,
                identifierCandidates:
                    (result['identifierCandidates'] as List<String>?) ??
                        const <String>[],
              )
            : null;
      });
    } catch (e) {
      // 대조 실패는 불일치가 아니다 — 모르는 상태로 둔다(§16·§37).
      //   [FULL13-REEVAL.2] 다운로드·OCR 실패면 근거도 보내지 않는다.
      if (mounted) {
        setState(() {
          _match = DocFieldOutcome.unassessed;
          _evidence = null;
        });
      }
    } finally {
      // 대조용 임시 파일은 업로드하지 않는다 — 여기서 끝난다.
      try {
        await image?.delete();
      } catch (_) {/* 이미 지워졌으면 무시 */}
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _submit() async {
    if (!_canSubmit) return;
    FocusScope.of(context).unfocus();
    // [FULL13-REEVAL] 올라간 신분증이 있는데 아직 대조하지 않았으면 먼저 한다 —
    //   정상 신청자가 버튼을 몰라서 수동 확인으로 떨어지지 않게. 실패해도 등록은 계속한다.
    //   [FULL13-REEVAL.2] 외국인 복구도 같다 — 지금 등록증 사진을 다시 읽는다.
    if (_hasUploadedIdCard && _evidence == null) {
      await _compareWithIdCard();
      if (!mounted) return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final value = _entered;
    final evidence = _evidence;
    final kind = widget.isForeignRecovery
        ? 'recoverForeign'
        : (widget.isUpdate ? 'update' : 'register');
    final hook = TaxIdentitySheetHooks.submit;
    final err = hook != null
        ? await hook(kind, value, _match, evidence)
        : widget.isForeignRecovery
            ? await TaxIdentityService.recoverForeign(value,
                documentEvidence: evidence)
            : widget.isUpdate
                ? await TaxIdentityService.update(value,
                    documentMatch: _match, documentEvidence: evidence)
                : await TaxIdentityService.register(value,
                    documentMatch: _match, documentEvidence: evidence);
    if (!mounted) return;
    if (err != null) {
      setState(() {
        _busy = false;
        _error = err;
      });
      return;
    }
    // [§29] 제출 즉시 입력값을 지운다 — 뒤로 가도 남아 있지 않게.
    _frontCtrl.clear();
    _backCtrl.clear();
    _evidence = null;
    if (!mounted) return;
    Navigator.pop(context, true);
  }

  ({String text, Color color})? get _matchHint => switch (_match) {
        DocFieldOutcome.matched =>
          (text: '신분증의 번호와 같습니다', color: AppColors.successDark),
        // [DU281 TX3] errorFaded(#EF5350 3.49) → errorDark, grey600 → 보조색
        DocFieldOutcome.mismatch => (
            text: '신분증의 번호와 다릅니다. 입력값을 확인해주세요',
            color: AppColors.errorDark
          ),
        DocFieldOutcome.unreadable => (
            text: '신분증에서 번호를 읽지 못했습니다. 등록은 계속할 수 있어요',
            color: AppColors.textSecondary
          ),
        DocFieldOutcome.unassessed => null,
      };

  @override
  Widget build(BuildContext context) {
    final hint = _matchHint;
    // [DU281 TX7] 320·2.0 에서 내용이 아래로 305px(키보드가 뜨면 585px) 넘쳐 입력칸·'등록하기'에 닿지 못했다 —
    //   내용을 스크롤 안에 둔다(키보드 높이만큼 아래 여백은 그대로).
    return SingleChildScrollView(
      child: Padding(
      padding: EdgeInsets.only(
        left: ResponsiveHelper.spacing(context, 20),
        right: ResponsiveHelper.spacing(context, 20),
        top: ResponsiveHelper.spacing(context, 20),
        bottom: MediaQuery.of(context).viewInsets.bottom +
            ResponsiveHelper.spacing(context, 20),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // [DU281 TX1] 기본 grey700 15 → 시트 제목(subtitle bold 본문색, O057 과 같다). 낱말 단위.
          Text(TextLayout.keepWords(widget.isUpdate ? '세무정보 수정' : '세무정보 등록'),
              semanticsLabel: widget.isUpdate ? '세무정보 수정' : '세무정보 등록',
              style: ResponsiveHelper.subtitleStyle(context)
                  .copyWith(fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
          SizedBox(height: ResponsiveHelper.spacing(context, 6)),
          // [DU281 r1] 낱말 단위(B320 '쓰이/는'·'다/시')
          Text(
            TextLayout.keepWords(widget.isForeignRecovery
                ? '가입할 때 확인한 외국인등록번호를 한 번 더 입력해주세요.\n'
                    '가입 정보와 같은 번호일 때만 등록됩니다.'
                : '소득신고·원천징수에 쓰이는 주민등록번호입니다.\n'
                    '등록한 번호는 화면에 다시 표시되지 않습니다.'),
            // [DU281 TX2] grey600(4.61) → 보조색
            style:
                ResponsiveHelper.smallStyle(context, color: AppColors.textSecondary),
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 12)),
          // [RELEASE-CORRECTION-PRIVACY-INLINE-DISCLOSURE]
          //   번호를 입력받기 **전에** 민감정보라는 점과, 사업장 관리자가
          //   어떤 조건에서 열 수 있는지를 말한다. 동의 게이트가 아니라 고지다.
          const PrivacyInlineNotice(
            disclosure: PrivacyDisclosure.taxIdentity,
            icon: Icons.lock_outline,
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 16)),
          // [DU282 DF1] 큰 글자: 두 칸을 나란히 두면 '앞 6자리' 값이 칸보다 넓어 앞이 잘려 보였다
          //   (320·2.0 칸 89.1 < 글자 109.6, '00101'). 위아래로 둔다 — 입력 순서·포커스 이동·가림은 같다.
          //   기본 배율은 기존 가로 배치 그대로(DU274·DU276 과 같은 큰 글자 전환 기준).
          if (MediaQuery.textScalerOf(context).scale(10) >= 13)
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _digitField(_frontCtrl, 6, '앞 6자리',
                    autofocus: true,
                    onFilled: () => _backFocus.requestFocus()),
                SizedBox(height: ResponsiveHelper.spacing(context, 12)),
                _digitField(_backCtrl, 7, '뒤 7자리',
                    focusNode: _backFocus, obscure: true),
              ],
            )
          else
          Row(
            children: [
              Expanded(
                flex: 6,
                child: _digitField(_frontCtrl, 6, '앞 6자리',
                    autofocus: true,
                    onFilled: () => _backFocus.requestFocus()),
              ),
              Padding(
                padding: EdgeInsets.symmetric(
                    horizontal: ResponsiveHelper.spacing(context, 8)),
                child: const Text('-'),
              ),
              Expanded(
                flex: 7,
                child: _digitField(_backCtrl, 7, '뒤 7자리',
                    focusNode: _backFocus, obscure: true),
              ),
            ],
          ),
          // [FULL13-REEVAL.3] 외국인 복구 — 영문 이름을 등록증 기재대로 한 번 입력한다.
          //   지금 올라간 등록증의 이름과 비교하는 데만 쓰고 저장하지 않는다.
          if (widget.isForeignRecovery) ...[
            SizedBox(height: ResponsiveHelper.spacing(context, 12)),
            TextField(
              controller: _legalNameCtrl,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                labelText: '영문 이름 (등록증 기재대로)',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (_) => setState(() => _evidence = null),
            ),
          ],
          if (hint != null) ...[
            SizedBox(height: ResponsiveHelper.spacing(context, 10)),
            // [DU281 r2] 낱말 단위(B320 '다릅니/다'). 읽기 이름은 원문.
            Text(TextLayout.keepWords(hint.text),
                semanticsLabel: hint.text,
                style: ResponsiveHelper.smallStyle(context, color: hint.color)), // [DU281 TX3] tiny → small
          ],
          if (_error != null) ...[
            SizedBox(height: ResponsiveHelper.spacing(context, 10)),
            Text(TextLayout.keepWords(_error!),
                semanticsLabel: _error,
                // [DU281 TX4] tiny errorFaded(3.49) → small errorDark · [r2] 낱말 단위
                style: ResponsiveHelper.smallStyle(context,
                    color: AppColors.errorDark)),
          ],
          SizedBox(height: ResponsiveHelper.spacing(context, 14)),
          // 대조는 선택이다. 건너뛰어도 등록은 된다 — 확인은 나중에
          // 관리자가 신분증 원본과 직접 한다(§37).
          //
          // [R1.4.1] 외국인 복구에는 붙이지 않는다. 서버가 가입 때 만든
          //   신원 지문과 직접 대조하므로 OCR보다 확실하다.
          if (!widget.isForeignRecovery) TextButton.icon(
            onPressed: (_entered.length == 13 && !_checking && !_busy)
                ? _compareWithIdCard
                : null,
            icon: _checking
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.badge_outlined, size: 16),
            label: Text(_checking ? '확인 중…' : '신분증 사진으로 확인 (선택)'),
            // [DU281 TX5] padding 0(터치 48 미만)·글자색 직접 지정(누를 수 없을 때도 같은 색) →
            //   대표색 글자 버튼 48, 스타일은 textStyle 로(비활성은 테마 비활성색)
            style: TextButton.styleFrom(
              foregroundColor: AppColors.brand,
              minimumSize: const Size(48, 48),
              padding: EdgeInsets.symmetric(horizontal: ResponsiveHelper.spacing(context, 4)),
              textStyle: ResponsiveHelper.smallStyle(context, fontWeight: FontWeight.w600),
            ),
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 14)),
          SafeArea(
            top: false,
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _canSubmit ? _submit : null,
                // [DU281 TX6] 대표색 52, 비활성 grey200 위 보조색(DU280 과 같다)
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.brand,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: AppColors.grey200,
                  disabledForegroundColor: AppColors.textSecondary,
                  elevation: 0,
                  minimumSize: const Size.fromHeight(52),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: _busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : Text(widget.isUpdate ? '수정하기' : '등록하기'),
              ),
            ),
          ),
        ],
      ),
      ),
    );
  }

  Widget _digitField(
    TextEditingController ctrl,
    int len,
    String label, {
    bool autofocus = false,
    bool obscure = false,
    FocusNode? focusNode,
    VoidCallback? onFilled,
  }) =>
      TextField(
        controller: ctrl,
        focusNode: focusNode,
        autofocus: autofocus,
        obscureText: obscure,
        keyboardType: TextInputType.number,
        maxLength: len,
        // [§29] 복사·붙여넣기 메뉴를 열지 않는다.
        enableInteractiveSelection: false,
        decoration: InputDecoration(
          labelText: label,
          counterText: '',
          border: const OutlineInputBorder(),
          isDense: true,
        ),
        onChanged: (v) {
          // 입력이 바뀌면 이전 대조 결과는 더 이상 이 값에 대한 것이 아니다.
          setState(() {
            _match = DocFieldOutcome.unassessed;
            _evidence = null;
          });
          if (v.length == len) onFilled?.call();
        },
      );
}
