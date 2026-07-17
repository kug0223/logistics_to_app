import 'dart:io';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/user_provider.dart';
import '../../models/core/user_model.dart';
import '../../utils/responsive_helper.dart';
import '../../widgets/common/common_widgets.dart';
import '../../utils/document_upload_helper.dart';
import '../../services/firestore_service.dart';
import '../../utils/toast_helper.dart';
import '../../utils/dialog_helper.dart';
import '../../utils/format_helper.dart';
import '../../widgets/dialogs/styled_dialog.dart';
import 'package:intl/intl.dart';
import '../../services/storage_service.dart';
import '../../utils/navigation_helper.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_select_field.dart';
import '../../widgets/common/gradient_scaffold.dart';
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

    if (user == null) {
      return GradientScaffold(
        title: '내 서류 관리',
        body: const Center(child: Text('사용자 정보를 불러올 수 없습니다')),
      );
    }

    return GradientScaffold(
      title: '내 서류 관리',
      onBack: () => NavigationHelper.pop(context, changed: _hasChanges),
      onRefresh: _loadUserDocuments,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 📢 안내 카드
        _buildInfoBanner(
          message: '본인 명의의 서류만 등록 가능합니다.\n'
              '신분증과 통장의 이름이 일치해야 합니다.',
          icon: Icons.info_outline,
          color: AppColors.infoDark,
        ),

        SizedBox(height: ResponsiveHelper.spacing(context, 20)),

        // 📄 신분증 섹션
        _buildSectionHeader('신분증', Icons.badge),

        SizedBox(height: ResponsiveHelper.spacing(context, 8)),

        _buildIdCardSection(user),

        SizedBox(height: ResponsiveHelper.spacing(context, 20)),

        // 💳 통장 정보 섹션
        _buildSectionHeader('통장 정보', Icons.account_balance_wallet),

        SizedBox(height: ResponsiveHelper.spacing(context, 8)),

        _buildBankInfoSection(user),
      ],
    );
  }

  /// 신분증 업로드
  Future<void> _uploadIdCard() async {
    if (_isLoading) return;
    final userProvider = context.read<UserProvider>();
    final user = userProvider.currentUser;
    if (user == null) return;

    setState(() => _isLoading = true); // 피커 전에 설정 — 피커 도중 이중 탭 방지

    String? newIdCardUrl; // [M-19] CF 실패 시 Storage orphan 방지
    try {
      // 주민번호 앞 7자리 조합
      String? residentNumber;
      if (user.residentNumber != null && user.residentNumber!.length >= 8) {
        residentNumber = user.residentNumber!.substring(0, 8); // "990101-1"
      }

      final imagePath = await DocumentUploadHelper.pickAndVerifyIdCard(
        context,
        user.name,
        expectedResidentNumber: residentNumber,
      );

      if (imagePath == null || !mounted) return; // finally가 _isLoading 초기화

      final oldUrl = user.idCardImageUrl;

      // 1. 새 이미지 먼저 업로드 — 예외 여부와 무관하게 임시 파일 삭제 보장
      final storagePath = 'users/${user.uid}/idCard_${DateTime.now().millisecondsSinceEpoch}.jpg';
      String? downloadUrl;
      try {
        downloadUrl = await _storageService.uploadImage(imagePath, storagePath);
      } finally {
        // TMP-01: pickAndVerifyIdCard가 반환한 임시 압축 파일.
        try { await File(imagePath).delete(); } catch (_) {}
      }

      if (downloadUrl == null) {
        if (mounted) ToastHelper.showError('이미지 업로드에 실패했습니다');
        return;
      }

      // 2. CF로 isIdVerified/idCardVerifiedAt 설정 — Admin SDK 경유로 직접 쓰기 차단 준수
      newIdCardUrl = downloadUrl; // CF 호출 전 추적 시작
      await FirebaseFunctions.instanceFor(region: 'asia-northeast3')
          .httpsCallable('callableMarkIdCardVerified')
          .call({'imageUrl': downloadUrl});
      newIdCardUrl = null; // CF 성공 — Storage 정리 불필요

      // 3. 기존 이미지 삭제 (best-effort — CF callableDeleteIdCard가 새 URL 기준 처리)
      if (oldUrl != null && oldUrl != downloadUrl) {
        try {
          await _storageService.deleteImageByUrl(oldUrl);
        } catch (e) {
          debugPrint('⚠️ 기존 신분증 삭제 실패 (무시): $e');
        }
      }

      // UserProvider 갱신
      await userProvider.refreshCurrentUser();
      if (!mounted) return;

      ToastHelper.showSuccess('신분증이 등록되었습니다');
      _hasChanges = true;
    } catch (e) {
      // [M-19] CF 실패 시 업로드된 신분증 파일 Storage orphan 방지
      if (newIdCardUrl != null) {
        try { await _storageService.deleteImageByUrl(newIdCardUrl); } catch (_) {}
      }
      if (mounted) ToastHelper.showError('신분증 등록에 실패했습니다');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// 통장 정보 저장
  Future<void> _saveBankInfo() async {
    if (_selectedBank == null || _accountNumberController.text.trim().isEmpty) {
      ToastHelper.showWarning('은행과 계좌번호를 입력해주세요');
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
          'bankName': _selectedBank,
          'accountNumber': _accountNumberController.text.trim(),
          'accountHolder': user.name,
        },
      );

      await userProvider.refreshCurrentUser();
      if (!mounted) return;

      ToastHelper.showSuccess('통장 정보가 저장되었습니다');
      _hasChanges = true;  // ✅ 추가
    } catch (e) {
      // Firestore 업데이트 중 화면 pop 시 unmounted 가능 → mounted 체크 필수
      if (mounted) ToastHelper.showError('통장 정보 저장에 실패했습니다');
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
      message: '등록된 신분증을 삭제하시겠습니까?',
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
      title: '통장 정보 삭제',
      message: '등록된 통장 정보를 삭제하시겠습니까?',
      confirmText: '삭제',
    );

    if (!confirmed || !mounted) return;

    final userProvider = context.read<UserProvider>();
    final user = userProvider.currentUser;

    if (user == null) return;

    setState(() => _isLoading = true);

    try {
      // [BUG-수정] CLAUDE.md 규칙: Firestore 먼저 삭제 후 Storage 삭제
      // 1. Storage URL 미리 수집
      final oldBankbookUrl = user.bankbookImageUrl;

      // 2. Firestore 먼저 업데이트 (실패 시 Storage는 건드리지 않음)
      await _firestoreService.updateUserDocument(
        user.uid,
        {
          'bankName': null,
          'accountNumber': null,
          'accountHolder': null,
          'bankbookImageUrl': null,
        },
      );

      // 3. Firestore 성공 후 Storage 삭제
      if (oldBankbookUrl != null) {
        try {
          await _storageService.deleteImageByUrl(oldBankbookUrl);
        } catch (e) {
          debugPrint('⚠️ 통장사본 Storage 삭제 실패 (무시): $e');
        }
      }

      await userProvider.refreshCurrentUser();
      if (!mounted) return;

      setState(() {
        _selectedBank = null;
        _accountNumberController.clear();
      });

      ToastHelper.showSuccess('통장 정보가 삭제되었습니다');
      _hasChanges = true;  // ✅ 추가
    } catch (e) {
      debugPrint('❌ 통장 정보 삭제 실패: $e');
      if (mounted) ToastHelper.showError('통장 정보 삭제에 실패했습니다');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// 📄 신분증 섹션
  Widget _buildIdCardSection(UserModel user) {
    final hasIdCard = user.idCardImageUrl != null;

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
            if (hasIdCard) ...[
              // 등록된 신분증 정보 — compact single-line row
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
                      '신분증 등록 완료',
                      style: ResponsiveHelper.bodyStyle(context).copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (user.idCardVerifiedAt != null)
                    Text(
                      DateFormat('yyyy.MM.dd').format(user.idCardVerifiedAt!),
                      style: ResponsiveHelper.tinyStyle(context,
                          color: AppColors.grey500),
                    ),
                ],
              ),

              SizedBox(height: ResponsiveHelper.spacing(context, 12)),

              // 버튼들
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _isLoading ? null : _uploadIdCard,
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
                      onPressed: _isLoading ? null : _deleteIdCard,
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
              // 신분증 미등록 — compact inline empty state
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
                      Icons.badge_outlined,
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
                            '주민등록증 또는 운전면허증 앞면',
                            style: ResponsiveHelper.tinyStyle(context,
                                color: AppColors.grey400),
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
                text: '신분증 업로드',
                onPressed: _isLoading ? null : _uploadIdCard,
                icon: Icons.camera_alt,
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// 💳 통장 정보 섹션
  Widget _buildBankInfoSection(UserModel user) {
    final hasBankInfo = user.bankName != null && user.accountNumber != null;

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
            if (hasBankInfo) ...[
              // 등록된 통장 정보 — horizontal info rows
              _buildInfoRow(
                icon: Icons.account_balance,
                label: '은행',
                value: user.bankName!,
              ),
              const Divider(height: 20, thickness: 0.5),
              _buildInfoRow(
                icon: Icons.credit_card,
                label: '계좌번호',
                value: EncryptionHelper.maskAccountNumber(user.accountNumber),
              ),
              const Divider(height: 20, thickness: 0.5),
              _buildInfoRow(
                icon: Icons.person,
                label: '예금주',
                value: user.accountHolder ?? user.name,
              ),

              SizedBox(height: ResponsiveHelper.spacing(context, 12)),

              // 통장사본 표시
              if (user.bankbookImageUrl != null) ...[
                Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: ResponsiveHelper.spacing(context, 12),
                    vertical: ResponsiveHelper.spacing(context, 10),
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.success.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: AppColors.success.withValues(alpha: 0.2)),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.check_circle,
                        color: AppColors.successDark,
                        size: ResponsiveHelper.iconSize(context, 16),
                      ),
                      SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                      Text(
                        '통장사본 등록 완료',
                        style: ResponsiveHelper.smallStyle(context).copyWith(
                          color: AppColors.successDeep,
                        ),
                      ),
                    ],
                  ),
                ),
              ] else ...[
                Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: ResponsiveHelper.spacing(context, 12),
                    vertical: ResponsiveHelper.spacing(context, 10),
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.warning.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: AppColors.warning.withValues(alpha: 0.2)),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.warning_amber,
                        color: AppColors.warningDark,
                        size: ResponsiveHelper.iconSize(context, 16),
                      ),
                      SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                      Expanded(
                        child: Text(
                          '통장사본 미등록',
                          style: ResponsiveHelper.smallStyle(context).copyWith(
                            color: AppColors.warningDarkest,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: _isLoading ? null : _uploadBankbookImage,
                        child: const Text('업로드'),
                      ),
                    ],
                  ),
                ),
              ],

              SizedBox(height: ResponsiveHelper.spacing(context, 12)),

              // 버튼들
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        setState(() {
                          _selectedBank = user.bankName;
                          _accountNumberController.text = user.accountNumber ?? '';
                        });
                        _showBankEditDialog();
                      },
                      icon: const Icon(Icons.edit, size: 14),
                      label: Text('수정',
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
                      onPressed: _isLoading ? null : _deleteBankInfo,
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
              // 통장 정보 미등록 — compact inline empty state
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
                      Icons.account_balance_wallet_outlined,
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
                            '급여 수령을 위한 통장 정보',
                            style: ResponsiveHelper.tinyStyle(context,
                                color: AppColors.grey400),
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
                text: '통장 정보 등록',
                onPressed: _showBankEditDialog,
                icon: Icons.add,
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// 정보 행 위젯 — horizontal label + value
  Widget _buildInfoRow({
    required IconData icon,
    required String label,
    required String value,
  }) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Container(
          width: ResponsiveHelper.spacing(context, 34),
          height: ResponsiveHelper.spacing(context, 34),
          decoration: BoxDecoration(
            color: theme.primaryColor.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            icon,
            size: ResponsiveHelper.iconSize(context, 18),
            color: theme.primaryColor,
          ),
        ),
        SizedBox(width: ResponsiveHelper.spacing(context, 12)),
        Text(
          label,
          style: ResponsiveHelper.bodyStyle(context).copyWith(
            color: AppColors.grey600,
          ),
        ),
        const Spacer(),
        Text(
          value,
          style: ResponsiveHelper.bodyStyle(context).copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  /// 통장 정보 수정 다이얼로그
  Future<void> _showBankEditDialog() async {
    String? localBank = _selectedBank;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => StyledDialog(
          title: '통장 정보 입력',
          subtitle: '급여 수령에 사용할 계좌 정보를 입력하세요',
          icon: Icons.account_balance_wallet,
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppSelectField<String>(
                value: localBank,
                hintText: '은행을 선택하세요',
                sheetTitle: '은행 선택',
                items: const [
                  'KB국민은행', '신한은행', 'NH농협은행', '우리은행', '하나은행',
                  'IBK기업은행', 'SC제일은행', '씨티은행', '카카오뱅크', '토스뱅크',
                  'KEB하나은행', '경남은행', '광주은행', '대구은행', '부산은행',
                  '전북은행', '제주은행', '케이뱅크', '새마을금고', '신협',
                  '저축은행', '우체국',
                ],
                labelOf: (b) => b,
                prefixIcon: Icons.account_balance,
                onChanged: (value) => setDialogState(() => localBank = value),
              ),
              SizedBox(height: ResponsiveHelper.spacing(ctx, 16)),
              CommonWidgets.textField(
                context: ctx,
                controller: _accountNumberController,
                label: '계좌번호',
                hint: '- 없이 숫자만 입력',
                icon: Icons.credit_card,
                keyboardType: TextInputType.number,
              ),
            ],
          ),
          actions: [
            StyledDialogButton.cancel(onPressed: () => Navigator.pop(ctx)),
            StyledDialogButton.primary(
              text: '저장',
              onPressed: () {
                setState(() => _selectedBank = localBank);
                Navigator.pop(ctx);
                _saveBankInfo();
              },
            ),
          ],
        ),
      ),
    );
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
      final imagePath = await DocumentUploadHelper.pickAndVerifyBankbook(
        context,
        user.name,
        expectedAccountNumber: (user.accountNumber?.isEmpty ?? true) ? null : user.accountNumber,
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

      await _firestoreService.updateUserDocument(
        user.uid,
        {
          'bankbookImageUrl': newUrl,
        },
      );
      newUrl = null; // Firestore 저장 성공 → 정리 불필요

      // 2. 업로드·저장 성공 후 기존 이미지 삭제 (best-effort)
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
