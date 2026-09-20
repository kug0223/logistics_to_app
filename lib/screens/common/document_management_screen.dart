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
import '../../utils/identity_identifier.dart';
import '../../services/firestore_service.dart';
import '../../utils/toast_helper.dart';
import '../../utils/dialog_helper.dart';
import '../../utils/format_helper.dart';
import '../../widgets/dialogs/styled_dialog.dart';
import '../../services/storage_service.dart';
import '../../services/tax_identity_service.dart';
import '../../utils/image_helper.dart';
import '../../utils/ocr_verification_helper.dart';
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
    final user = userProvider.currentUser;
    if (user == null) return;

    setState(() => _isLoading = true); // 피커 전에 설정 — 피커 도중 이중 탭 방지

    String? newIdCardPath; // [M-19] CF 실패 시 Storage orphan 방지 (path 기반)
    try {
      // 주민번호 앞자리 계산: birthDate + gender (내국인 residentNumber는 저장 안 됨)
      final residentNumber = _buildExpectedResidentNumber(user);

      final picked = await DocumentUploadHelper.pickAndVerifyIdCard(
        context,
        user.name,
        expectedResidentNumber: residentNumber,
      );

      if (picked == null || !mounted) return; // finally가 _isLoading 초기화
      final imagePath = picked.path;

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
      //    [DOCUMENT-VERIFICATION-INTEGRITY-R0] 기기 확인 **근거**를 함께 보낸다.
      //      판정이 아니다 — 서버가 이 근거로 문서 상태를 정한다.
      newIdCardPath = storagePath; // CF 호출 전 Storage orphan 추적
      await FirebaseFunctions.instanceFor(region: 'asia-northeast3')
          .httpsCallable('callableMarkIdCardVerified')
          .call({'storagePath': storagePath, 'selfCheck': picked.selfCheck});
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

  // ── [DOCUMENT-VERIFICATION-INTEGRITY-R0] 문서 상태 표시 ─────────────────
  //
  //   금지: 업로드됨을 '확인 완료'처럼 보이게 하는 문구.
  //   '확인 완료'는 사람이 확인한 상태(MANUAL_APPROVED) 하나뿐이다.

  ({String label, Color color, IconData icon}) _idCardStatus(UserModel user) =>
      _docStatus(user.idCardDocumentState);

  ({String label, Color color, IconData icon}) _bankbookStatus(UserModel user) =>
      _docStatus(user.bankbookDocumentState);

  ({String label, Color color, IconData icon}) _docStatus(String? state) {
    switch (state) {
      case 'MANUAL_APPROVED':
        return (
          label: '확인 완료',
          color: const Color(0xFF22C55E),
          icon: Icons.check_circle_rounded
        );
      case 'MANUAL_REJECTED':
      case 'REUPLOAD_REQUIRED':
        return (
          label: '다시 등록 필요',
          color: AppColors.error,
          icon: Icons.error_outline
        );
      case 'SELF_CHECK_OVERRIDDEN':
      case 'MANUAL_REVIEW_REQUIRED':
        return (
          label: '관리자 확인 중',
          color: AppColors.warning,
          icon: Icons.hourglass_top
        );
      case 'SELF_CHECK_PASSED':
        return (
          label: '제출 완료',
          color: AppColors.infoDark,
          icon: Icons.task_alt
        );
      default:
        // 상태가 없는 기존 제출물. 통과로 읽지 않는다 — 제출됐다고만 말한다.
        return (
          label: '제출 완료',
          color: AppColors.infoDark,
          icon: Icons.task_alt
        );
    }
  }

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

  ({String label, Color color, IconData icon}) _taxStatusChip() {
    final s = _taxStatus;
    if (s == null || s.loadFailed) {
      return (label: '확인 불가', color: AppColors.grey500, icon: Icons.help_outline);
    }
    if (!s.registered) {
      return (label: '미등록', color: AppColors.grey500, icon: Icons.remove_circle_outline);
    }
    if (s.blocksApply) {
      return (label: '정보 확인 필요', color: AppColors.errorFaded, icon: Icons.error_outline);
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
                  color: registered ? AppColors.infoDark : AppColors.grey400),
              SizedBox(width: ResponsiveHelper.spacing(context, 12)),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('세무정보',
                        style: ResponsiveHelper.bodyStyle(context)
                            .copyWith(fontWeight: FontWeight.w600)),
                    Text(
                      isForeign
                          ? '가입 시 등록됨 — 외국인등록번호'
                          : '소득신고에 쓰이는 주민등록번호',
                      style: ResponsiveHelper.tinyStyle(context,
                          color: isForeign && registered
                              ? AppColors.successDark
                              : AppColors.grey500),
                    ),
                  ],
                ),
              ),
              _docStatusChip(context, chip),
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
                style: ResponsiveHelper.tinyStyle(context,
                    color: AppColors.errorFaded),
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
          if (isForeign)
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
            Row(
              children: [
                TextButton(
                  onPressed: _isLoading ? null : () => _openTaxIdentitySheet(user),
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    foregroundColor: AppColors.grey600,
                  ),
                  child: Text('수정',
                      style: ResponsiveHelper.smallStyle(context,
                          color: AppColors.grey600,
                          fontWeight: FontWeight.w500)),
                ),
                const Spacer(),
                // 등록된 번호를 되돌려 보여주는 경로는 두지 않는다(§27).
                Text('등록된 번호는 표시되지 않습니다',
                    style: ResponsiveHelper.tinyStyle(context,
                        color: AppColors.grey400)),
              ],
            )
          else
            _flatPrimaryButton(
              text: '세무정보 등록하기',
              onPressed: _isLoading ? null : () => _openTaxIdentitySheet(user),
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
      builder: (_) => _TaxIdentitySheet(user: user, isUpdate: registered),
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
              // [DOCUMENT-VERIFICATION-INTEGRITY-R0] 상태를 그대로 말한다.
              //
              //   예전에는 파일이 있기만 하면 '✓ 등록완료'였다. 인식이
              //   실패했든, 이름이 달랐든, 사용자가 경고를 넘겼든 화면은
              //   똑같이 초록 체크를 보여줬다 — 그것이 제보된 현상이다.
              //   '확인 완료'는 사람이 확인한 경우에만 쓴다.
              if (hasIdCard)
                _docStatusChip(context, _idCardStatus(user))
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
    if (hasBankAccount && hasBankbook) {
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
                            color: AppColors.grey500)),
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
      final picked = await DocumentUploadHelper.pickAndVerifyBankbook(
        context,
        user.isForeign ? null : user.name,
        expectedAccountNumber: (user.accountNumber?.isEmpty ?? true) ? null : user.accountNumber,
        // expectedBankName 미사용: 스크린샷 내 은행명 표기가 다양해 오탐 가능성 높음
      );

      if (picked == null || !mounted) return; // finally가 _isLoading 초기화
      final imagePath = picked.path;

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
      //    [DOCUMENT-VERIFICATION-INTEGRITY-R0] storagePath 직통 + 기기 확인 근거.
      await FirebaseFunctions.instanceFor(region: 'asia-northeast3')
          .httpsCallable('callableMarkBankbookVerified')
          .call({
        'imageUrl': newUrl,
        'storagePath': storagePath,
        'selfCheck': picked.selfCheck,
      });
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

// ══════════════════════════════════════════════════════════════
// [PII-B4-R1.4] 세무정보 입력 시트
//
//   여기가 전체번호를 손에 쥐는 **유일한 순간**이다. 그래서 신분증
//   대조도 여기서 한다 — 등록이 끝나면 앱은 그 번호를 다시 알 수 없다.
//
//   제출 후에는 컨트롤러를 비우고 시트를 닫는다(§29).
// ══════════════════════════════════════════════════════════════
class _TaxIdentitySheet extends StatefulWidget {
  const _TaxIdentitySheet({required this.user, required this.isUpdate});

  final UserModel user;
  final bool isUpdate;

  @override
  State<_TaxIdentitySheet> createState() => _TaxIdentitySheetState();
}

class _TaxIdentitySheetState extends State<_TaxIdentitySheet> {
  final _frontCtrl = TextEditingController();
  final _backCtrl = TextEditingController();
  final _backFocus = FocusNode();

  bool _busy = false;
  String? _error;

  /// 신분증 대조 결과 — 하지 않았으면 UNASSESSED다.
  ///
  ///   이 값은 **등록 가부를 정하지 않는다**. 서버가 형식·본인인증 정보·
  ///   검증부호로 판단하고, 이건 "확인이 필요한가"를 말할 뿐이다(§20).
  DocFieldOutcome _match = DocFieldOutcome.unassessed;
  bool _checking = false;

  @override
  void dispose() {
    _frontCtrl.dispose();
    _backCtrl.dispose();
    _backFocus.dispose();
    super.dispose();
  }

  String get _entered =>
      '${_frontCtrl.text.trim()}${_backCtrl.text.trim()}'
          .replaceAll(RegExp(r'\D'), '');

  bool get _canSubmit => _entered.length == 13 && !_busy;

  /// 신분증 사진과 대조. 선택 사항이며, 실패해도 등록을 막지 않는다.
  Future<void> _compareWithIdCard() async {
    if (_entered.length != 13) return;
    setState(() => _checking = true);
    File? image;
    try {
      image = await ImageHelper.pickAndCompressImage(
        context,
        type: ImageType.document,
        useBottomSheet: true,
      );
      if (image == null || !mounted) return;
      final result = await OcrVerificationHelper.verifyIdCardName(
        image.path,
        widget.user.name,
        expectedResidentNumber: _entered,
      ).timeout(const Duration(seconds: 30),
          onTimeout: () => <String, dynamic>{});
      if (!mounted) return;
      setState(() => _match =
          result['identifierOutcome'] as DocFieldOutcome? ??
              DocFieldOutcome.unassessed);
    } catch (e) {
      // 대조 실패는 불일치가 아니다 — 모르는 상태로 둔다(§16·§37).
      if (mounted) setState(() => _match = DocFieldOutcome.unassessed);
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
    setState(() {
      _busy = true;
      _error = null;
    });
    final value = _entered;
    final err = widget.isUpdate
        ? await TaxIdentityService.update(value, documentMatch: _match)
        : await TaxIdentityService.register(value, documentMatch: _match);
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
    if (!mounted) return;
    Navigator.pop(context, true);
  }

  ({String text, Color color})? get _matchHint => switch (_match) {
        DocFieldOutcome.matched =>
          (text: '신분증의 번호와 같습니다', color: AppColors.successDark),
        DocFieldOutcome.mismatch => (
            text: '신분증의 번호와 다릅니다. 입력값을 확인해주세요',
            color: AppColors.errorFaded
          ),
        DocFieldOutcome.unreadable => (
            text: '신분증에서 번호를 읽지 못했습니다. 등록은 계속할 수 있어요',
            color: AppColors.grey600
          ),
        DocFieldOutcome.unassessed => null,
      };

  @override
  Widget build(BuildContext context) {
    final hint = _matchHint;
    return Padding(
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
          Text(widget.isUpdate ? '세무정보 수정' : '세무정보 등록',
              style: ResponsiveHelper.bodyStyle(context)
                  .copyWith(fontWeight: FontWeight.w700)),
          SizedBox(height: ResponsiveHelper.spacing(context, 6)),
          Text(
            '소득신고·원천징수에 쓰이는 주민등록번호입니다.\n'
            '등록한 번호는 화면에 다시 표시되지 않습니다.',
            style:
                ResponsiveHelper.smallStyle(context, color: AppColors.grey600),
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 16)),
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
          if (hint != null) ...[
            SizedBox(height: ResponsiveHelper.spacing(context, 10)),
            Text(hint.text,
                style: ResponsiveHelper.tinyStyle(context, color: hint.color)),
          ],
          if (_error != null) ...[
            SizedBox(height: ResponsiveHelper.spacing(context, 10)),
            Text(_error!,
                style: ResponsiveHelper.tinyStyle(context,
                    color: AppColors.errorFaded)),
          ],
          SizedBox(height: ResponsiveHelper.spacing(context, 14)),
          // 대조는 선택이다. 건너뛰어도 등록은 된다 — 확인은 나중에
          // 관리자가 신분증 원본과 직접 한다(§37).
          TextButton.icon(
            onPressed: (_entered.length == 13 && !_checking && !_busy)
                ? _compareWithIdCard
                : null,
            icon: _checking
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.badge_outlined, size: 16),
            label: Text(_checking ? '확인 중…' : '신분증 사진으로 확인 (선택)',
                style: ResponsiveHelper.smallStyle(context,
                    color: AppColors.infoDark)),
            style: TextButton.styleFrom(padding: EdgeInsets.zero),
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 14)),
          SafeArea(
            top: false,
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _canSubmit ? _submit : null,
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
          setState(() => _match = DocFieldOutcome.unassessed);
          if (v.length == len) onFilled?.call();
        },
      );
}
