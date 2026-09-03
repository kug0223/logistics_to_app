import 'dart:io';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/user_provider.dart';
import '../../models/core/user_model.dart';
import '../../utils/responsive_helper.dart';
import '../../widgets/common/common_widgets.dart';
import '../../widgets/common/loading_widget.dart';
import '../../utils/document_upload_helper.dart';
import '../../services/firestore_service.dart';
import '../../utils/toast_helper.dart';
import '../../utils/dialog_helper.dart';
import '../../utils/format_helper.dart';
import '../../widgets/dialogs/styled_dialog.dart';
import '../../services/storage_service.dart';
import '../../utils/navigation_helper.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_select_field.dart';
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
  bool _hasChanges = false;

  @override
  void initState() {
    super.initState();
    _loadUserDocuments();
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
      backgroundColor: Colors.white,
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20,
            color: Color(0xFF1F2937)),
        onPressed: () => NavigationHelper.pop(context, changed: _hasChanges),
        tooltip: '뒤로',
      ),
      title: const Text(
        '내 서류 관리',
        style: TextStyle(
          color: Color(0xFF111827),
          fontSize: 20,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.3,
        ),
      ),
      titleSpacing: 0,
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(0.5),
        child: Container(height: 0.5, color: const Color(0xFFE5E7EB)),
      ),
    );

    if (user == null) {
      return Scaffold(
        backgroundColor: AppColors.grey50,
        appBar: appBar,
        body: const Center(child: Text('사용자 정보를 불러올 수 없습니다')),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.grey50,
      appBar: appBar,
      body: _isLoading
          ? const LoadingWidget()
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
        _buildSectionHeader('사업자 정보', Icons.business),

        SizedBox(height: ResponsiveHelper.spacing(context, 8)),

        _buildBusinessInfoSection(user),

        SizedBox(height: ResponsiveHelper.spacing(context, 20)),

        // 📋 사업자등록증 섹션
        _buildSectionHeader('사업자등록증', Icons.description),

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
    final hasLicense = user.businessLicenseImageUrl != null;
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
                          style: ResponsiveHelper.smallStyle(context)),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.infoDark,
                        side: const BorderSide(color: AppColors.infoDark),
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
                      onPressed: _isLoading ? null : _deleteBusinessLicense,
                      icon: const Icon(Icons.delete, size: 14),
                      label: Text('삭제',
                          style: ResponsiveHelper.smallStyle(context)),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.error,
                        side: const BorderSide(color: AppColors.error),
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
                          Text(
                            '미등록',
                            style: ResponsiveHelper.smallStyle(context,
                                color: AppColors.grey500,
                                fontWeight: FontWeight.w600),
                          ),
                          Text(
                            hasBusinessInfo
                                ? '위 정보와 일치하는 사업자등록증을 업로드해주세요'
                                : '먼저 사업자 정보를 입력하고 저장해주세요',
                            style: ResponsiveHelper.tinyStyle(context,
                                color: hasBusinessInfo
                                    ? AppColors.grey400
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

    String? newUrl; // catch에서 orphan 정리를 위해 try 밖에서 선언
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

      // 1. 새 이미지 먼저 업로드 — 예외 여부와 무관하게 임시 파일 삭제 보장
      final storagePath = 'users/${user.uid}/businessLicense_${DateTime.now().millisecondsSinceEpoch}.jpg';
      try {
        newUrl = await _storageService.uploadImage(imagePath, storagePath);
      } finally {
        // TMP-01: pickAndVerifyBusinessLicense가 반환한 임시 압축 파일.
        try { await File(imagePath).delete(); } catch (_) {}
      }

      if (newUrl == null) {
        if (mounted) ToastHelper.showError('이미지 업로드에 실패했습니다');
        return;
      }

      // 2. Firestore에 새 URL 저장
      await _firestoreService.updateUserDocument(
        user.uid,
        {
          'businessLicenseImageUrl': newUrl,
        },
      );
      newUrl = null; // Firestore 저장 성공 → 정리 불필요

      // 3. 업로드·저장 성공 후 기존 이미지 삭제 (best-effort)
      if (oldUrl != null) {
        try {
          await _storageService.deleteImageByUrl(oldUrl);
        } catch (e) {
          debugPrint('⚠️ 기존 사업자등록증 삭제 실패 (무시): $e');
        }
      }

      // UserProvider 갱신
      await userProvider.refreshCurrentUser();
      if (!mounted) return;

      ToastHelper.showSuccess('사업자등록증이 등록되었습니다');
      _hasChanges = true;
    } catch (e) {
      // Firestore 저장 실패 시 이미 업로드된 파일 정리 (고아 파일 방지)
      if (newUrl != null) {
        try {
          await _storageService.deleteImageByUrl(newUrl);
        } catch (_) {}
      }
      if (mounted) ToastHelper.showError('사업자등록증 등록에 실패했습니다');
    } finally {
      if (mounted) setState(() => _isLoading = false);
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
    final bankStatus     = user.bankVerificationStatus;
    final isBankMismatch = bankStatus == 'mismatch';
    // Canonical 기준: UserModel.hasWageDocumentsReady와 동일
    // (hasBankAccount && hasBankbookDocument && !mismatch)
    final isBankReadyForApply = user.hasWageDocumentsReady;
    // 미사용 변수 방지: 이 함수에서 isBankVerified/isBankReviewRequired는
    // _buildBankInfoSection 내부에서 별도 계산하므로 여기서 선언하지 않는다.

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 📢 안내 카드
        _buildInfoBanner(
          message: '본인 명의의 급여계좌를 등록해주세요.\n'
              '통장에 표시된 예금주명을 정확히 확인해주세요.',
          icon: Icons.info_outline,
          color: AppColors.infoDark,
        ),

        SizedBox(height: ResponsiveHelper.spacing(context, 24)),

        // ① 신원 확인 섹션
        _buildReadinessSectionLabel(
          step: 1,
          title: '신원 확인',
          description: '지원자 본인 확인을 위해 필요해요',
          isComplete: hasId,
        ),

        SizedBox(height: ResponsiveHelper.spacing(context, 10)),

        _buildIdCardSection(user),

        SizedBox(height: ResponsiveHelper.spacing(context, 18)),

        // ② 급여정보 준비 섹션
        // [PRODUCT-POLICY] isComplete = 제출 완료 (review_required 포함), mismatch = isError
        // isPending 미전달: review_required는 지원자 기준 완료 → 앰버 ⏳ 대신 초록 ✓
        _buildReadinessSectionLabel(
          step: 2,
          title: '급여정보 준비',
          description: '근무 후 급여 지급을 위해 필요해요',
          isComplete: isBankReadyForApply,
          isError: isBankMismatch,
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
            ? const Color(0xFFEF4444)   // 빨강 — mismatch
            : isPending
                ? const Color(0xFFF59E0B) // 앰버 — review_required
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

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // 스텝 배지
        Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: badgeColor,
            shape: BoxShape.circle,
          ),
          child: Center(child: badgeChild),
        ),
        SizedBox(width: ResponsiveHelper.spacing(context, 10)),
        // 제목 + 설명
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: ResponsiveHelper.bodyStyle(context).copyWith(
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              Text(
                description,
                style: ResponsiveHelper.tinyStyle(context,
                    color: AppColors.grey500),
              ),
            ],
          ),
        ),
        // 완료 배지 제거 — 왼쪽 배지가 이미 상태를 표현함
      ],
    );
  }

  /// 신분증/통장 검증용 주민번호 앞자리 계산
  /// 반환 형식: "YYMMDD-G" (예: 1990년 1월 1일 남성 → "900101-1")
  /// 내국인은 residentNumber가 저장되지 않으므로 birthDate + gender로 재계산.
  /// 성별 코드: 2000년 이전 남성=1, 여성=2 / 2000년 이후 남성=3, 여성=4
  String? _buildExpectedResidentNumber(UserModel user) {
    if (user.birthDate == null || user.gender == null) return null;
    final birth = user.birthDate!;
    final yy = (birth.year % 100).toString().padLeft(2, '0');
    final mm = birth.month.toString().padLeft(2, '0');
    final dd = birth.day.toString().padLeft(2, '0');
    final front = '$yy$mm$dd';
    final isMale = user.gender == '남성';
    final genderCode = birth.year >= 2000 ? (isMale ? 3 : 4) : (isMale ? 1 : 2);
    return '$front-$genderCode';
  }

  /// 신분증 업로드
  Future<void> _uploadIdCard() async {
    if (_isLoading) return;
    final userProvider = context.read<UserProvider>();
    final user = userProvider.currentUser;
    if (user == null) return;

    setState(() => _isLoading = true); // 피커 전에 설정 — 피커 도중 이중 탭 방지

    String? newIdCardPath; // [M-19] CF 실패 시 Storage orphan 방지 (path 기반)
    try {
      // 주민번호 앞자리 계산: birthDate + gender (내국인 residentNumber는 저장 안 됨)
      final residentNumber = _buildExpectedResidentNumber(user);

      final imagePath = await DocumentUploadHelper.pickAndVerifyIdCard(
        context,
        user.name,
        expectedResidentNumber: residentNumber,
      );

      if (imagePath == null || !mounted) return; // finally가 _isLoading 초기화

      final oldUrl = user.idCardImageUrl;
      final oldPath = user.idCardImagePath;

      // 1. 새 이미지 먼저 업로드 — 예외 여부와 무관하게 임시 파일 삭제 보장
      final storagePath = 'users/${user.uid}/idCard_${DateTime.now().millisecondsSinceEpoch}.jpg';
      bool uploadOk = false;
      try {
        // [BUG-ID-01] uploadImageNoUrl — getDownloadURL() 미호출로 permanent URL 생성 방지
        uploadOk = await _storageService.uploadImageNoUrl(imagePath, storagePath);
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
      newIdCardPath = storagePath; // CF 호출 전 Storage orphan 추적
      await FirebaseFunctions.instanceFor(region: 'asia-northeast3')
          .httpsCallable('callableMarkIdCardVerified')
          .call({'storagePath': storagePath});
      newIdCardPath = null; // CF 성공 — Storage 정리 불필요

      // 3. 기존 이미지 삭제 (best-effort)
      //    path 기반 우선, 없으면 URL fallback
      if (oldPath != null) {
        try {
          await _storageService.deleteImage(oldPath);
        } catch (e) {
          debugPrint('⚠️ 기존 신분증 삭제 실패 (무시): $e');
        }
      } else if (oldUrl != null) {
        try {
          await _storageService.deleteImageByUrl(oldUrl);
        } catch (e) {
          debugPrint('⚠️ 기존 신분증 URL 삭제 실패 (무시): $e');
        }
      }

      // UserProvider 갱신
      await userProvider.refreshCurrentUser();
      if (!mounted) return;

      ToastHelper.showSuccess('신분증이 등록되었습니다');
      _hasChanges = true;
    } catch (e) {
      // [M-19] CF 실패 시 업로드된 신분증 파일 Storage orphan 방지 (path 기반 삭제)
      if (newIdCardPath != null) {
        try { await _storageService.deleteImage(newIdCardPath); } catch (_) {}
      }
      if (mounted) ToastHelper.showError('신분증 등록에 실패했습니다');
    } finally {
      if (mounted) setState(() => _isLoading = false);
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
                // 완료 시 green → infoDark: 아이콘은 항목 식별 역할이므로 중립 파랑.
                // semantic green은 우측 ✓ 등록완료 영역에서만 사용.
                color: hasIdCard ? AppColors.infoDark : AppColors.grey400,
              ),
              SizedBox(width: ResponsiveHelper.spacing(context, 12)),
              Expanded(
                child: Column(
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
                          color: isForeignRegistered ? AppColors.successDark : AppColors.grey500),
                    ),
                  ],
                ),
              ),
              // 미등록 > / ✓ 등록완료
              if (hasIdCard)
                Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.check_circle_rounded,
                      color: Color(0xFF22C55E), size: 18),
                  SizedBox(width: ResponsiveHelper.spacing(context, 4)),
                  Text('등록완료',
                      style: ResponsiveHelper.smallStyle(context,
                          color: const Color(0xFF22C55E),
                          fontWeight: FontWeight.w600)),
                ])
              else
                Row(mainAxisSize: MainAxisSize.min, children: [
                  Text('미등록',
                      style: ResponsiveHelper.smallStyle(context,
                          color: const Color(0xFF9CA3AF))),
                  const Icon(Icons.chevron_right,
                      color: Color(0xFF9CA3AF), size: 16),
                ]),
            ],
          ),

          // ── 구분선 ─────────────────────────────────────────────────
          Padding(
            padding: EdgeInsets.symmetric(
                vertical: ResponsiveHelper.spacing(context, 12)),
            child: const Divider(
                height: 1, thickness: 0.5, color: AppColors.grey200),
          ),

          // ── CTA 버튼 ───────────────────────────────────────────────
          if (hasIdCard)
            // 완료: 경량 텍스트 링크 행 — "다시 등록하기"는 사진 재촬영/재업로드 의미 명확화
            Row(
              children: [
                TextButton(
                  onPressed: _isLoading ? null : _uploadIdCard,
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    minimumSize: Size.zero,
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
                  onPressed: _isLoading ? null : _deleteIdCard,
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    // errorFaded: 인라인 삭제는 낮은 강조 — confirm dialog에서 강한 red 사용
                    foregroundColor: AppColors.errorFaded,
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.delete_outline, size: 13),
                    const SizedBox(width: 3),
                    Text('삭제',
                        style: ResponsiveHelper.smallStyle(context,
                            color: AppColors.errorFaded,
                            fontWeight: FontWeight.w500)),
                  ]),
                ),
              ],
            )
          else
            // 미등록: 신분증 등록하기 flat primary
            _flatPrimaryButton(
              text: '신분증 등록하기',
              onPressed: _isLoading ? null : _uploadIdCard,
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
  ///   E (확인 필요): bankVerificationStatus == 'mismatch' — 재등록 필요
  ///   D (확인 완료): bankVerificationStatus == 'verified'
  ///   C (제출 완료): bankVerificationStatus == 'review_required'
  ///              [PRODUCT-POLICY] "확인 중" 아님. 정상 제출 완료 상태. 지원 가능.
  ///   B+ (V3 완료): hasBankAccount && hasBankbookDocument && verificationStatus==null
  ///              [V3] bankVerificationStatus 폐기 후 신규 등록 계좌의 완료 상태
  ///   B (계좌만)  : hasBankAccount && !hasBankbookDocument
  ///   A (미등록)  : !hasBankAccount
  ///
  /// ⚠️ 홈 '지원 준비 0/2 1/2 2/2' 완료 카운터 기준:
  ///    UserModel.hasWageDocumentsReady (hasBankAccount && hasBankbook && !mismatch)
  ///    → B+ / C / D 모두 준비 완료로 카운트됨
  Widget _buildBankInfoSection(UserModel user) {
    // [V3 FOREIGN HOLDER] user.hasBankAccount getter 사용 — accountHolder 포함
    final hasBankAccount = user.hasBankAccount;
    final hasBankbook = user.hasBankbookDocument;
    // bankVerificationStatus: null | 'review_required' | 'verified' | 'mismatch'
    // CF Admin SDK가 제어하는 신뢰 필드 — 클라이언트 직접 쓰기 금지 (Firestore Rules RC 적용)
    final verificationStatus = user.bankVerificationStatus;

    // ── 상태 분기 ─────────────────────────────────────────────────
    // [V3] bankVerificationStatus 폐기 → null도 완료 상태일 수 있음 (B+ 상태).
    // 레거시 계정 호환성을 위해 기존 status 값도 처리.
    final bool isVerified       = verificationStatus == 'verified';
    final bool isReviewRequired = verificationStatus == 'review_required';
    final bool isMismatch       = verificationStatus == 'mismatch';

    // ── 우측 상태 뱃지 ────────────────────────────────────────────
    final Widget statusBadge;
    if (isVerified) {
      // D: 확인 완료
      statusBadge = Row(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.check_circle_rounded,
            color: Color(0xFF22C55E), size: 18),
        SizedBox(width: ResponsiveHelper.spacing(context, 4)),
        Text('확인 완료',
            style: ResponsiveHelper.smallStyle(context,
                color: const Color(0xFF22C55E), fontWeight: FontWeight.w600)),
      ]);
    } else if (isReviewRequired) {
      // C: 제출 완료 — [PRODUCT-POLICY] review_required = 정상 제출 상태 → 지원 가능
      // "확인 중"(amber ⏳)으로 표시하면 섹션 헤더 초록 ✓와 시각적 충돌 발생
      statusBadge = Row(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.check_circle_rounded,
            color: Color(0xFF3B82F6), size: 18),
        SizedBox(width: ResponsiveHelper.spacing(context, 4)),
        Text('제출 완료',
            style: ResponsiveHelper.smallStyle(context,
                color: const Color(0xFF3B82F6), fontWeight: FontWeight.w600)),
      ]);
    } else if (isMismatch) {
      // E: 확인 필요 (error)
      statusBadge = Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.error_outline_rounded,
            color: AppColors.errorFaded, size: 16),
        SizedBox(width: ResponsiveHelper.spacing(context, 4)),
        Text('확인 필요',
            style: ResponsiveHelper.smallStyle(context,
                color: AppColors.errorFaded, fontWeight: FontWeight.w600)),
      ]);
    } else if (hasBankAccount && hasBankbook) {
      // B+: V3 완료 상태 — verificationStatus 미설정이지만 계좌+통장사본 등록 완료
      statusBadge = Row(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.check_circle_rounded,
            color: Color(0xFF22C55E), size: 18),
        SizedBox(width: ResponsiveHelper.spacing(context, 4)),
        Text('등록완료',
            style: ResponsiveHelper.smallStyle(context,
                color: const Color(0xFF22C55E),
                fontWeight: FontWeight.w600)),
      ]);
    } else if (hasBankAccount) {
      // B: 계좌만 있고 통장사본 없음 — '미등록' 표시 금지 (BANKBOOK-UX-01 수정)
      statusBadge = Text('계좌 등록됨',
          style: ResponsiveHelper.smallStyle(context,
              color: AppColors.infoDark, fontWeight: FontWeight.w500));
    } else {
      // A: 완전 미등록
      statusBadge = Row(mainAxisSize: MainAxisSize.min, children: [
        Text('미등록',
            style: ResponsiveHelper.smallStyle(context,
                color: const Color(0xFF9CA3AF))),
        const Icon(Icons.chevron_right, color: Color(0xFF9CA3AF), size: 16),
      ]);
    }

    // ── 부제 텍스트 ────────────────────────────────────────────────
    // accountNumber는 AES-CBC 암호화 저장 → 복호화 불가 → 전체 노출 금지
    // bankName은 평문 저장 → 표시 가능
    final String subText;
    if (isMismatch) {
      subText = '계좌정보를 확인하고 다시 제출해주세요';
    } else if (isReviewRequired) {
      // [PRODUCT-POLICY] "확인하고 있어요" → 기다려야 하는 인상 제거
      // verified와 동일하게 은행명 표시 (준비 완료 상태)
      subText = user.bankName ?? '급여 계좌 등록됨';
    } else if (isVerified) {
      subText = user.bankName ?? '급여 계좌';
    } else if (hasBankAccount && hasBankbook) {
      // B+: V3 완료 — 은행명만 표시 (통장사본 포함 등록 완료)
      subText = user.bankName ?? '급여 계좌 등록됨';
    } else if (hasBankAccount) {
      // B: 계좌만 — 통장사본 미제출
      subText = '${user.bankName!} · 통장사본 등록 필요';
    } else {
      subText = '은행 · 계좌 · 예금주 · 통장사본';
    }

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
                color: hasBankAccount ? AppColors.infoDark : AppColors.grey400,
              ),
              SizedBox(width: ResponsiveHelper.spacing(context, 12)),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('급여 계좌',
                        style: ResponsiveHelper.bodyStyle(context)
                            .copyWith(fontWeight: FontWeight.w600)),
                    Text(subText,
                        style: ResponsiveHelper.tinyStyle(context,
                            color: isMismatch
                                ? AppColors.errorFaded
                                : AppColors.grey500)),
                  ],
                ),
              ),
              // 상태 뱃지 (우측)
              statusBadge,
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
          if (isVerified)
            // D: 확인 완료 — 수정 / 삭제
            Row(
              children: [
                TextButton(
                  onPressed: _isLoading ? null : _showBankEditDialog,
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    foregroundColor: AppColors.grey600,
                  ),
                  child: Text('수정하기',
                      style: ResponsiveHelper.smallStyle(context,
                          color: AppColors.grey600,
                          fontWeight: FontWeight.w500)),
                ),
                const Spacer(),
                TextButton(
                  onPressed: _isLoading ? null : _deleteBankInfo,
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    foregroundColor: AppColors.errorFaded,
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.delete_outline, size: 13),
                    const SizedBox(width: 3),
                    Text('삭제',
                        style: ResponsiveHelper.smallStyle(context,
                            color: AppColors.errorFaded,
                            fontWeight: FontWeight.w500)),
                  ]),
                ),
              ],
            )
          else if (isMismatch)
            // E: 확인 필요 — 계좌정보 수정 유도
            _flatPrimaryButton(
              text: '계좌정보 수정하기',
              onPressed: _isLoading ? null : _showBankEditDialog,
              icon: Icons.edit_outlined,
            )
          else if (isReviewRequired)
            // C: 제출 완료 — [PRODUCT-POLICY] 안내 없이 선택적 재제출/계좌 수정 옵션만 제공
            // "검토 후 확인 여부를 안내해 드릴게요" 같이 기다리는 인상을 주는 텍스트 제거
            //   재제출: callableMarkBankbookVerified 재호출 → 새 이미지로 review_required 유지 (안전)
            //   계좌 수정: callableUpdateBankAccount → 계좌 변경 + 상태 초기화 (안전)
            Row(
              children: [
                TextButton(
                  onPressed: _isLoading ? null : _uploadBankbookImage,
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    foregroundColor: AppColors.grey600,
                  ),
                  child: Text('통장사본 다시 제출',
                      style: ResponsiveHelper.smallStyle(context,
                          color: AppColors.grey600,
                          fontWeight: FontWeight.w500)),
                ),
                const Spacer(),
                TextButton(
                  onPressed: _isLoading ? null : _showBankEditDialog,
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    foregroundColor: AppColors.grey600,
                  ),
                  child: Text('계좌 수정',
                      style: ResponsiveHelper.smallStyle(context,
                          color: AppColors.grey600,
                          fontWeight: FontWeight.w500)),
                ),
              ],
            )
          else if (hasBankAccount && hasBankbook)
            // B+: V3 완료 상태 — 계좌 변경 / 전체 삭제 경량 행 (큰 CTA 제거)
            Row(
              children: [
                TextButton(
                  onPressed: _isLoading ? null : _showBankEditDialog,
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    minimumSize: Size.zero,
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
                  onPressed: _isLoading ? null : _deleteBankInfo,
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    foregroundColor: AppColors.errorFaded,
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.delete_outline, size: 13),
                    const SizedBox(width: 3),
                    Text('삭제',
                        style: ResponsiveHelper.smallStyle(context,
                            color: AppColors.errorFaded,
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
  Future<void> _uploadBankbookImage() async {
    if (_isLoading) return;
    final userProvider = context.read<UserProvider>();
    final user = userProvider.currentUser;
    if (user == null) return;

    setState(() => _isLoading = true); // 피커 전에 설정 — 피커 도중 이중 탭 방지

    String? newUrl; // catch에서 orphan 정리를 위해 try 밖에서 선언
    try {
      // [V3 FOREIGN HOLDER] 외국인: user.name 기반 예금주 비교 skip (legalName 불일치 오탐)
      // 내국인: user.name 기반 SOFT 이름 검증 유지
      final imagePath = await DocumentUploadHelper.pickAndVerifyBankbook(
        context,
        user.isForeign ? null : user.name,
        expectedAccountNumber: (user.accountNumber?.isEmpty ?? true) ? null : user.accountNumber,
        // expectedBankName 미사용: 스크린샷 내 은행명 표기가 다양해 오탐 가능성 높음
      );

      if (imagePath == null || !mounted) return; // finally가 _isLoading 초기화

      final oldUrl = user.bankbookImageUrl;

      // 1. 새 이미지 먼저 업로드 — 예외 여부와 무관하게 임시 파일 삭제 보장
      final storagePath = 'users/${user.uid}/bankbook_${DateTime.now().millisecondsSinceEpoch}.jpg';
      try {
        newUrl = await _storageService.uploadImage(imagePath, storagePath);
      } finally {
        // TMP-01: pickAndVerifyBankbook이 반환한 임시 압축 파일.
        try { await File(imagePath).delete(); } catch (_) {}
      }

      if (newUrl == null) {
        if (mounted) ToastHelper.showError('이미지 업로드에 실패했습니다');
        return;
      }

      // 2. CF로 isBankbookVerified/bankbookVerifiedAt 설정 — Admin SDK 경유로 직접 쓰기 차단 준수
      await FirebaseFunctions.instanceFor(region: 'asia-northeast3')
          .httpsCallable('callableMarkBankbookVerified')
          .call({'imageUrl': newUrl});
      newUrl = null; // CF 성공 — Storage 정리 불필요

      // 3. 기존 이미지 삭제 (best-effort)
      if (oldUrl != null) {
        try {
          await _storageService.deleteImageByUrl(oldUrl);
        } catch (e) {
          debugPrint('⚠️ 기존 통장사본 삭제 실패 (무시): $e');
        }
      }

      await userProvider.refreshCurrentUser();
      if (!mounted) return;

      _hasChanges = true;
      ToastHelper.showSuccess('통장사본이 등록되었습니다');
    } catch (e) {
      // Firestore 저장 실패 시 이미 업로드된 파일 정리 (고아 파일 방지)
      if (newUrl != null) {
        try {
          await _storageService.deleteImageByUrl(newUrl);
        } catch (_) {}
      }
      if (mounted) ToastHelper.showError('통장사본 등록에 실패했습니다');
    } finally {
      if (mounted) setState(() => _isLoading = false);
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
          backgroundColor: AppColors.workTypeBlue,   // #1565C0 flat
          foregroundColor: Colors.white,
          elevation: 0,
          padding: EdgeInsets.symmetric(
              vertical: ResponsiveHelper.spacing(context, 10)),  // 14→10: 카드 시각 무게 경감
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
            Text(text,
                style: ResponsiveHelper.bodyStyle(context,
                    color: Colors.white, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }

  /// 섹션 헤더 (settings_screen.dart 동일 스타일)
  Widget _buildSectionHeader(String title, IconData icon) {
    return Padding(
      padding: EdgeInsets.only(left: ResponsiveHelper.spacing(context, 4)),
      child: Row(
        children: [
          Icon(icon,
              size: ResponsiveHelper.iconSize(context, 14),
              color: AppColors.grey500),
          SizedBox(width: ResponsiveHelper.spacing(context, 6)),
          Text(
            title,
            style: ResponsiveHelper.smallStyle(context,
                color: AppColors.grey500, fontWeight: FontWeight.w600),
          ),
        ],
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
