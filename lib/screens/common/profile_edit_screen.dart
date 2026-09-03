// lib/screens/common/profile_edit_screen.dart

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:intl/intl.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';

// Providers
import '../../providers/user_provider.dart';

// Models
import '../../models/core/user_model.dart';

// Services
import '../../services/firestore_service.dart';
import '../../services/auth_service.dart';
import '../../services/pass_verification_service.dart';

// Utils
import '../../utils/image_helper.dart';
import '../../utils/responsive_helper.dart';
import '../../utils/toast_helper.dart';

// Widgets
import '../../models/core/user_region.dart';
import '../../widgets/inputs/daum_address_search.dart';
import '../../widgets/inputs/home_region_picker_sheet.dart';
import '../../widgets/dialogs/styled_dialog.dart';
import '../../theme/app_colors.dart';
import '../../widgets/common/loading_widget.dart';

/// 프로필 관리 화면 (MY 2Depth)
///
/// ## 정보 구조
/// - [읽기 전용] 본인 정보: 이름·아이디·생년월일·성별·전화번호 (본인인증 기반, 임의 변경 불가)
/// - [편집 가능] 주소·상세주소
/// - [별도 기능] 프로필 사진 (즉시 저장), 비밀번호 변경 (Dialog)
///
/// ## 저장 방식
/// 주소 변경 → 하단 "변경사항 저장" CTA 활성화 → 탭하면 Firestore 저장
class ProfileEditScreen extends StatefulWidget {
  const ProfileEditScreen({super.key});

  @override
  State<ProfileEditScreen> createState() => _ProfileEditScreenState();
}

class _ProfileEditScreenState extends State<ProfileEditScreen> {
  final _formKey = GlobalKey<FormState>();
  final _firestoreService = FirestoreService();

  late TextEditingController _addressController;
  late TextEditingController _detailAddressController;

  bool _isLoading = false;
  bool _hasChanges = false;
  bool _isUploadingPhoto = false;
  bool _isReVerifying = false;

  // 주로 일할 지역 — null이면 미수정, 값이 있으면 사용자가 새로 선택한 지역
  UserRegion? _pendingHomeRegion;

  @override
  void initState() {
    super.initState();
    _initControllers();
  }

  void _initControllers() {
    final user = context.read<UserProvider>().currentUser;
    _addressController = TextEditingController(text: user?.address ?? '');
    _detailAddressController =
        TextEditingController(text: user?.detailAddress ?? '');

    _addressController.addListener(_checkChanges);
    _detailAddressController.addListener(_checkChanges);
  }

  void _checkChanges() {
    final user = context.read<UserProvider>().currentUser;
    if (user == null) return;
    setState(() {
      _hasChanges =
          _addressController.text != (user.address ?? '') ||
          _detailAddressController.text != (user.detailAddress ?? '') ||
          (_pendingHomeRegion != null && _pendingHomeRegion != user.homeRegion);
    });
  }

  @override
  void dispose() {
    _addressController.dispose();
    _detailAddressController.dispose();
    super.dispose();
  }

  // ── 본인 재인증 ──────────────────────────────────────────────────

  /// PASS 재인증 — 동일 CI 검증 후 이름·전화번호·성별·생년월일·passVerifiedAt 갱신
  ///
  /// 흐름:
  ///   확인 다이얼로그 → PassVerificationService.authenticate(purpose: 'reauth')
  ///   → CF finalizePassReauth(passToken) → UserProvider 갱신 → 성공 토스트
  Future<void> _handlePassReVerify(UserModel user) async {
    // 확인 다이얼로그
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('본인 재인증'),
        content: const Text(
          '현재 계정에 등록된 분의 인증 정보로만 재인증이 가능합니다.\n재인증을 진행할까요?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('재인증하기'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _isReVerifying = true);
    try {
      final result = await PassVerificationService.authenticate(
        purpose: 'reauth',
        role: user.role.name,
      );
      if (!mounted) return;
      if (result == null) return; // 사용자 취소

      await PassVerificationService.finalizePassReauth(result.passToken);
      if (!mounted) return;
      await context.read<UserProvider>().refreshCurrentUser();
      if (!mounted) return;
      ToastHelper.showSuccess('본인인증 정보가 업데이트되었습니다');
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      if (e.code == 'permission-denied') {
        ToastHelper.showError('현재 계정의 본인인증 정보와 다릅니다');
      } else if (e.code == 'deadline-exceeded') {
        ToastHelper.showError('인증 세션이 만료되었습니다. 다시 시도해주세요');
      } else {
        ToastHelper.showError('재인증에 실패했습니다. 다시 시도해주세요');
      }
    } catch (e) {
      if (!mounted) return;
      ToastHelper.showError('재인증에 실패했습니다. 다시 시도해주세요');
    } finally {
      if (mounted) setState(() => _isReVerifying = false);
    }
  }

  // ── 프로필 사진 ──────────────────────────────────────────────────

  Future<void> _showPhotoPicker() async {
    // 공통 Image Picker BottomSheet 사용 — 개별 구현 금지
    final source = await ImageHelper.showImageSourceBottomSheet(context);
    if (source == null || !mounted) return;
    await _uploadPhoto(source);
  }

  Future<void> _uploadPhoto(ImageSource source) async {
    final user = context.read<UserProvider>().currentUser;
    if (user == null) return;

    final picked = await ImagePicker().pickImage(
      source: source,
      imageQuality: 75,
      maxWidth: 600,
      maxHeight: 600,
    );
    if (picked == null || !mounted) return;

    setState(() => _isUploadingPhoto = true);
    final ref =
        FirebaseStorage.instance.ref('users/${user.uid}/profile/photo.jpg');
    String? uploadedUrl;
    try {
      final bytes = await picked.readAsBytes();
      final task =
          await ref.putData(bytes, SettableMetadata(contentType: 'image/jpeg'));
      uploadedUrl = await task.ref.getDownloadURL();

      // Firestore 실패 시 Storage orphan 방지 → Firestore 먼저
      await _firestoreService
          .updateUserDocument(user.uid, {'profileImageUrl': uploadedUrl});
      if (!mounted) return;
      await context.read<UserProvider>().refreshCurrentUser();
      if (mounted) ToastHelper.showSuccess('프로필 사진이 변경되었습니다');
    } catch (e) {
      if (uploadedUrl != null) {
        try {
          await ref.delete();
        } catch (_) {}
      }
      if (mounted) ToastHelper.showError('사진 업로드에 실패했습니다');
    } finally {
      if (mounted) setState(() => _isUploadingPhoto = false);
    }
  }

  // ── 주소 검색 ────────────────────────────────────────────────────

  Future<void> _searchAddress() async {
    if (kIsWeb) {
      ToastHelper.showWarning('웹에서는 주소 검색을 사용할 수 없습니다');
      return;
    }
    final result = await DaumAddressService.searchAddress(context);
    if (result != null && mounted) {
      setState(() => _addressController.text = result.fullAddress);
    }
  }

  // ── 주로 일할 지역 선택 ─────────────────────────────────────────────

  Future<void> _pickHomeRegion() async {
    final user = context.read<UserProvider>().currentUser;
    final result = await HomeRegionPickerSheet.show(
      context: context,
      selectedRegion: _pendingHomeRegion ?? user?.homeRegion,
    );
    if (result != null && mounted) {
      setState(() => _pendingHomeRegion = result);
      _checkChanges();
    }
  }

  // ── 비밀번호 변경 ─────────────────────────────────────────────────

  Future<void> _showPasswordChangeDialog() async {
    // [FC-02 OWNERSHIP FIX] _PasswordChangeDialog(StatefulWidget)이 controller 3개를
    // 직접 소유하고 State.dispose()에서 해제한다.
    // Dialog lifecycle ↔ controller lifecycle 완전 일치.
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const _PasswordChangeDialog(),
    );
    if (result == true && mounted) {
      ToastHelper.showSuccess('비밀번호가 변경되었습니다');
    }
  }

  // ── 저장 ─────────────────────────────────────────────────────────

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;
    final user = context.read<UserProvider>().currentUser;
    if (user == null) return;

    setState(() => _isLoading = true);
    try {
      final updates = <String, dynamic>{};
      if (_addressController.text.trim() != (user.address ?? '')) {
        updates['address'] = _addressController.text.trim();
      }
      if (_detailAddressController.text.trim() != (user.detailAddress ?? '')) {
        updates['detailAddress'] = _detailAddressController.text.trim();
      }
      if (_pendingHomeRegion != null && _pendingHomeRegion != user.homeRegion) {
        updates['homeRegion'] = _pendingHomeRegion!.toMap();
      }

      if (updates.isNotEmpty) {
        await _firestoreService.updateUserDocument(user.uid, updates);
        if (!mounted) return;
        await context.read<UserProvider>().refreshCurrentUser();
        if (!mounted) return;
        ToastHelper.showSuccess('변경사항이 저장되었습니다');
        setState(() {
          _hasChanges = false;
          _pendingHomeRegion = null;
        });
      }
    } catch (e) {
      if (mounted) ToastHelper.showError('저장에 실패했습니다');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ── Build ─────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final user =
        context.select<UserProvider, UserModel?>((p) => p.currentUser);
    if (user == null) return const Scaffold(body: LoadingWidget());

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text(
          '프로필 관리',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
            letterSpacing: -0.3,
          ),
        ),
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: AppColors.borderLight),
        ),
      ),
      // 변경사항이 있을 때만 하단 저장 CTA 활성화 — SafeArea(top:false)로 홈버튼 영역 처리
      bottomNavigationBar: _hasChanges
          ? SafeArea(
              top: false,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border(
                      top: BorderSide(color: AppColors.borderLight)),
                ),
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _saveProfile,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: theme.primaryColor,
                    disabledBackgroundColor: AppColors.grey200,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    elevation: 0,
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Text(
                          '변경사항 저장',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                ),
              ),
            )
          : null,
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 40),
          children: [
            // ── 프로필 헤더 ──────────────────────────────────────────
            _buildProfileHeader(user),
            const SizedBox(height: 28),

            // ── 본인 정보 (본인인증 기반, 변경 불가) ─────────────────
            _buildVerifiedSectionLabel(),
            const SizedBox(height: 8),
            _buildPersonalInfoCard(user),
            // 잠금 안내 + 재인증 링크 (내국인 PASS 인증 계정에만 표시)
            _buildLockedNote(user: user),
            const SizedBox(height: 20),

            // ── 주소 (편집 가능 — Input UI로 명확히 구분) ───────────
            _buildSectionLabel('주소', Icons.location_on_outlined),
            const SizedBox(height: 8),
            _buildSimpleCard(
              child: Column(
                children: [
                  if (kIsWeb)
                    _buildField(
                      controller: _addressController,
                      label: '주소',
                      hint: '주소를 직접 입력해주세요',
                    )
                  else
                    _buildField(
                      controller: _addressController,
                      label: '주소',
                      hint: '주소 검색 버튼을 눌러주세요',
                      readOnly: true,
                      onTap: _searchAddress,
                      suffixIcon: IconButton(
                        onPressed: _searchAddress,
                        icon: Icon(Icons.search,
                            color: theme.primaryColor, size: 20),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    ),
                  const SizedBox(height: 12),
                  _buildField(
                    controller: _detailAddressController,
                    label: '상세주소',
                    hint: '동/호수 입력',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // ── 주로 일할 지역 (USER 전용, 편집 가능) ────────────────
            _buildSectionLabel('주로 일할 지역', Icons.location_on_outlined),
            const SizedBox(height: 8),
            _buildHomeRegionCard(user),
            const SizedBox(height: 20),

            // ── 보안 ────────────────────────────────────────────────
            _buildSectionLabel('보안', Icons.security_outlined),
            const SizedBox(height: 8),
            _buildSecurityCard(),
          ],
        ),
      ),
    );
  }

  // ── 위젯 빌더 ──────────────────────────────────────────────────────

  /// 프로필 헤더: Card 없이 avatar + 이름/@ID + 사진 변경
  Widget _buildProfileHeader(UserModel user) {
    final theme = Theme.of(context);
    final hasPhoto = (user.profileImageUrl?.isNotEmpty ?? false);
    final avatarSize = ResponsiveHelper.spacing(context, 60);
    final badgeSize = ResponsiveHelper.spacing(context, 22);

    return Row(
      children: [
        // 아바타 + 카메라 뱃지
        GestureDetector(
          onTap: _showPhotoPicker,
          child: Stack(
            children: [
              Container(
                width: avatarSize,
                height: avatarSize,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: theme.primaryColor.withValues(alpha: 0.12),
                  border: Border.all(
                      color: theme.primaryColor.withValues(alpha: 0.25),
                      width: 1.5),
                ),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (hasPhoto)
                      ClipOval(
                        child: CachedNetworkImage(
                          imageUrl: user.profileImageUrl!,
                          width: avatarSize,
                          height: avatarSize,
                          fit: BoxFit.cover,
                          placeholder: (_, __) => const SizedBox.shrink(),
                          errorWidget: (_, __, ___) => Center(
                            child: Text(
                              user.name.isNotEmpty
                                  ? user.name[0].toUpperCase()
                                  : '?',
                              style: TextStyle(
                                fontSize: avatarSize * 0.4,
                                fontWeight: FontWeight.bold,
                                color: theme.primaryColor,
                              ),
                            ),
                          ),
                        ),
                      ),
                    if (_isUploadingPhoto)
                      Center(
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: theme.primaryColor))
                    else if (!hasPhoto)
                      Center(
                        child: Text(
                          user.name.isNotEmpty
                              ? user.name[0].toUpperCase()
                              : '?',
                          style: TextStyle(
                            fontSize: avatarSize * 0.4,
                            fontWeight: FontWeight.bold,
                            color: theme.primaryColor,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Positioned(
                bottom: 0,
                right: 0,
                child: Container(
                  width: badgeSize,
                  height: badgeSize,
                  decoration: BoxDecoration(
                    color: theme.primaryColor,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 1.5),
                  ),
                  child: Icon(Icons.camera_alt_outlined,
                      size: badgeSize * 0.5, color: Colors.white),
                ),
              ),
            ],
          ),
        ),
        SizedBox(width: ResponsiveHelper.spacing(context, 16)),
        // 이름 / @ID
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(user.name,
                  style: ResponsiveHelper.subtitleStyle(context)
                      .copyWith(fontWeight: FontWeight.bold)),
              SizedBox(height: ResponsiveHelper.spacing(context, 2)),
              Text('@${user.username}',
                  style: ResponsiveHelper.smallStyle(context,
                      color: AppColors.grey500)),
            ],
          ),
        ),
        // 사진 변경 텍스트
        GestureDetector(
          onTap: _showPhotoPicker,
          child: Text(
            '사진 변경',
            style: ResponsiveHelper.tinyStyle(context,
                color: Theme.of(context).primaryColor,
                fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }

  /// 본인 정보 섹션 레이블 — 우측에 "✓ 본인인증 완료" 뱃지 포함
  Widget _buildVerifiedSectionLabel() {
    return Padding(
      padding: EdgeInsets.only(left: ResponsiveHelper.spacing(context, 4)),
      child: Row(children: [
        Icon(Icons.person_outline,
            size: ResponsiveHelper.iconSize(context, 14),
            color: AppColors.grey500),
        SizedBox(width: ResponsiveHelper.spacing(context, 6)),
        Text('본인 정보',
            style: ResponsiveHelper.smallStyle(context,
                color: AppColors.grey500, fontWeight: FontWeight.w600)),
        const Spacer(),
        // 본인인증 완료 상태 뱃지 — 왜 잠겨 있는지 바로 인지 가능
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: AppColors.successBg,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.verified_outlined,
                  size: 11, color: AppColors.successDark),
              const SizedBox(width: 3),
              Text(
                '본인인증 완료',
                style: ResponsiveHelper.tinyStyle(context,
                    color: AppColors.successDark, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      ]),
    );
  }

  /// 일반 섹션 레이블 (아이콘 + 텍스트)
  Widget _buildSectionLabel(String title, IconData icon) {
    return Padding(
      padding: EdgeInsets.only(left: ResponsiveHelper.spacing(context, 4)),
      child: Row(children: [
        Icon(icon,
            size: ResponsiveHelper.iconSize(context, 14),
            color: AppColors.grey500),
        SizedBox(width: ResponsiveHelper.spacing(context, 6)),
        Text(title,
            style: ResponsiveHelper.smallStyle(context,
                color: AppColors.grey500, fontWeight: FontWeight.w600)),
      ]),
    );
  }

  /// 본인 정보 카드 — TextField 없음, key-value Row만 사용
  ///
  /// 이름/아이디/생년월일/성별/전화번호 모두 읽기 전용 정보로 표시.
  /// 입력창처럼 보이면 사용자가 탭해보게 되므로 일관되게 텍스트 Row로 표현.
  Widget _buildPersonalInfoCard(UserModel user) {
    final rows = <_InfoRow>[
      _InfoRow('이름', user.name),
      _InfoRow('아이디', user.username),
      if (user.birthDate != null)
        _InfoRow('생년월일', DateFormat('yyyy.MM.dd').format(user.birthDate!)),
      if (user.gender != null) _InfoRow('성별', user.gender!),
      if (user.effectivePhone != null && user.effectivePhone!.isNotEmpty)
        _InfoRow('전화번호', user.effectivePhone!),
    ];

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.borderLight),
      ),
      child: Column(
        children: [
          for (int i = 0; i < rows.length; i++) ...[
            Padding(
              padding: EdgeInsets.symmetric(
                horizontal: ResponsiveHelper.spacing(context, 16),
                vertical: ResponsiveHelper.spacing(context, 13),
              ),
              child: Row(children: [
                // 고정 폭 라벨 컬럼 — "생년월일"(4자) 기준으로 설정해 모든 행의 값이 수직 정렬됨
                SizedBox(
                  width: ResponsiveHelper.spacing(context, 76),
                  child: Text(
                    rows[i].label,
                    style: ResponsiveHelper.bodyStyle(context,
                        color: AppColors.grey600),
                  ),
                ),
                Expanded(
                  child: Text(
                    rows[i].value,
                    style: ResponsiveHelper.bodyStyle(context)
                        .copyWith(fontWeight: FontWeight.w500),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                    textAlign: TextAlign.end,
                  ),
                ),
              ]),
            ),
            if (i < rows.length - 1)
              const Divider(height: 1, indent: 16, thickness: 0.5),
          ],
        ],
      ),
    );
  }

  /// 본인인증 잠금 안내 + 재인증 링크 — 카드 아래 1회만 표시
  ///
  /// [user.passVerifiedAt] 가 있는 내국인 계정(PASS 인증 완료)에만 재인증 링크 노출.
  /// 외국인 계정은 passVerifiedAt == null → 재인증 링크 숨김.
  Widget _buildLockedNote({required UserModel user}) {
    final canReauth = user.passVerifiedAt != null;
    return Padding(
      padding: EdgeInsets.only(
        top: ResponsiveHelper.spacing(context, 8),
        left: ResponsiveHelper.spacing(context, 4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.lock_outline, size: 12, color: AppColors.grey400),
              SizedBox(width: ResponsiveHelper.spacing(context, 5)),
              Expanded(
                child: Text(
                  '본인인증 정보는 직접 변경할 수 없습니다.',
                  style: ResponsiveHelper.tinyStyle(context,
                      color: AppColors.grey400),
                ),
              ),
            ],
          ),
          if (canReauth) ...[
            SizedBox(height: ResponsiveHelper.spacing(context, 6)),
            GestureDetector(
              onTap: _isReVerifying ? null : () => _handlePassReVerify(user),
              child: Padding(
                padding: EdgeInsets.only(
                    left: ResponsiveHelper.spacing(context, 17)),
                child: _isReVerifying
                    ? Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 11,
                            height: 11,
                            child: CircularProgressIndicator(
                              strokeWidth: 1.5,
                              color: Theme.of(context).primaryColor,
                            ),
                          ),
                          SizedBox(width: ResponsiveHelper.spacing(context, 5)),
                          Text(
                            '재인증 진행 중...',
                            style: ResponsiveHelper.tinyStyle(context,
                                color: AppColors.grey500),
                          ),
                        ],
                      )
                    : Text(
                        '정보가 잘못됐나요?  재인증하기 >',
                        style: ResponsiveHelper.tinyStyle(context,
                            color: Theme.of(context).primaryColor),
                      ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// 흰 카드 래퍼 (패딩 포함)
  Widget _buildSimpleCard({required Widget child}) {
    return Container(
      padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 16)),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.borderLight),
      ),
      child: child,
    );
  }

  /// 주로 일할 지역 카드 — 탭하면 HomeRegionPickerSheet 호출
  Widget _buildHomeRegionCard(UserModel user) {
    final theme = Theme.of(context);
    // 미저장 변경이 있으면 pending값, 없으면 현재 저장된 값
    final displayRegion = _pendingHomeRegion ?? user.homeRegion;
    final hasRegion = displayRegion != null;
    final label = hasRegion
        ? '${displayRegion.province ?? ''} ${displayRegion.city}'.trim()
        : '선택 안 됨';

    return GestureDetector(
      onTap: _pickHomeRegion,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: ResponsiveHelper.spacing(context, 16),
          vertical: ResponsiveHelper.spacing(context, 14),
        ),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.borderLight),
        ),
        child: Row(
          children: [
            Icon(
              Icons.map_outlined,
              size: ResponsiveHelper.iconSize(context, 20),
              color: hasRegion ? theme.primaryColor : AppColors.grey400,
            ),
            SizedBox(width: ResponsiveHelper.spacing(context, 12)),
            Expanded(
              child: Text(
                label,
                style: ResponsiveHelper.bodyStyle(context).copyWith(
                  color: hasRegion ? AppColors.textPrimary : AppColors.grey400,
                  fontWeight: hasRegion ? FontWeight.w500 : FontWeight.normal,
                ),
              ),
            ),
            Icon(
              Icons.chevron_right,
              size: ResponsiveHelper.iconSize(context, 20),
              color: AppColors.grey400,
            ),
          ],
        ),
      ),
    );
  }

  /// 라벨 외부 배치 + neutral background TextFormField
  ///
  /// 주소·상세주소 전용 — 입력 가능한 영역임을 시각적으로 구분.
  /// 읽기 전용 정보(본인 정보, 전화번호)에는 사용하지 않는다.
  Widget _buildField({
    required TextEditingController controller,
    required String label,
    String? hint,
    bool readOnly = false,
    TextInputType? keyboardType,
    Widget? suffixIcon,
    VoidCallback? onTap,
  }) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: ResponsiveHelper.smallStyle(context,
              color: AppColors.grey600, fontWeight: FontWeight.w500),
        ),
        SizedBox(height: ResponsiveHelper.spacing(context, 6)),
        TextFormField(
          controller: controller,
          readOnly: readOnly,
          keyboardType: keyboardType,
          onTap: onTap,
          style: ResponsiveHelper.bodyStyle(context),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle:
                ResponsiveHelper.bodyStyle(context, color: AppColors.grey400),
            filled: true,
            fillColor: readOnly ? AppColors.grey50 : Colors.white,
            contentPadding: EdgeInsets.symmetric(
              horizontal: ResponsiveHelper.spacing(context, 14),
              vertical: ResponsiveHelper.spacing(context, 12),
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppColors.grey200),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppColors.grey200),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: theme.primaryColor, width: 1.5),
            ),
            disabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppColors.grey200),
            ),
            suffixIcon: suffixIcon,
          ),
        ),
      ],
    );
  }

  /// 보안 카드 (비밀번호 변경 row)
  Widget _buildSecurityCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.borderLight),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _showPasswordChangeDialog,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: ResponsiveHelper.spacing(context, 16),
              vertical: ResponsiveHelper.spacing(context, 14),
            ),
            child: Row(children: [
              Container(
                width: ResponsiveHelper.spacing(context, 34),
                height: ResponsiveHelper.spacing(context, 34),
                decoration: BoxDecoration(
                  color: AppColors.warningDark.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.lock_outline,
                    color: AppColors.warningDark,
                    size: ResponsiveHelper.iconSize(context, 18)),
              ),
              SizedBox(width: ResponsiveHelper.spacing(context, 12)),
              Expanded(
                child: Text('비밀번호 변경',
                    style: ResponsiveHelper.bodyStyle(context)
                        .copyWith(fontWeight: FontWeight.w600)),
              ),
              Icon(Icons.chevron_right,
                  size: ResponsiveHelper.iconSize(context, 18),
                  color: AppColors.grey400),
            ]),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// FC-02 OWNERSHIP FIX: _PasswordChangeDialog
// TextEditingController 3개를 Dialog State가 직접 소유하고 dispose().
// 부모 메서드는 showDialog<bool> 결과만 수신.
// ─────────────────────────────────────────────────────────────────────────────

class _PasswordChangeDialog extends StatefulWidget {
  const _PasswordChangeDialog();

  @override
  State<_PasswordChangeDialog> createState() => _PasswordChangeDialogState();
}

class _PasswordChangeDialogState extends State<_PasswordChangeDialog> {
  final _currentPw = TextEditingController();
  final _newPw = TextEditingController();
  final _confirmPw = TextEditingController();
  final _authService = AuthService();

  bool _hideCurrent = true;
  bool _hideNew = true;
  bool _hideConfirm = true;
  int _strength = 0;
  bool _isChanging = false;

  static final _pwLetterRe = RegExp(r'[a-zA-Z]');
  static final _pwDigitRe = RegExp(r'[0-9]');
  static final _pwSpecialRe = RegExp(r'[!@#$%^&*(),.?":{}|<>]');

  @override
  void dispose() {
    _currentPw.dispose();
    _newPw.dispose();
    _confirmPw.dispose();
    super.dispose();
  }

  void _calcStrength(String pw) {
    int s = 0;
    if (pw.length >= 8) s++;
    if (_pwLetterRe.hasMatch(pw) && _pwDigitRe.hasMatch(pw)) s++;
    if (_pwSpecialRe.hasMatch(pw)) s++;
    setState(() => _strength = s);
  }

  Future<void> _onSubmit() async {
    if (_isChanging) return;

    // 유효성 검사
    if (_currentPw.text.isEmpty) {
      ToastHelper.showWarning('현재 비밀번호를 입력해주세요');
      return;
    }
    if (_newPw.text.length < 8) {
      ToastHelper.showWarning('새 비밀번호는 8자 이상이어야 합니다');
      return;
    }
    if (!_pwLetterRe.hasMatch(_newPw.text)) {
      ToastHelper.showWarning('영문을 포함해야 합니다');
      return;
    }
    if (!_pwDigitRe.hasMatch(_newPw.text)) {
      ToastHelper.showWarning('숫자를 포함해야 합니다');
      return;
    }
    if (!_pwSpecialRe.hasMatch(_newPw.text)) {
      ToastHelper.showWarning('특수문자를 포함해야 합니다');
      return;
    }
    if (_newPw.text != _confirmPw.text) {
      ToastHelper.showWarning('새 비밀번호가 일치하지 않습니다');
      return;
    }

    setState(() => _isChanging = true);
    final success = await _authService.changePassword(
      currentPassword: _currentPw.text,
      newPassword: _newPw.text,
    );

    if (!mounted) return; // async gap 이후 mounted 체크

    if (success) {
      setState(() => _isChanging = false);
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (rc) => StyledDialog(
          title: '비밀번호 변경 완료',
          subtitle: null,
          icon: Icons.check_circle,
          headerColor: AppColors.successMedium,
          content: Text(
            '비밀번호가 성공적으로 변경되었습니다.',
            style: ResponsiveHelper.bodyStyle(rc),
            textAlign: TextAlign.center,
          ),
          actions: [
            StyledDialogButton.primary(
              text: '확인',
              onPressed: () {
                Navigator.pop(rc);            // 중첩 dialog 닫기 → _onSubmit await 해제
                Navigator.pop(context, true); // 메인 dialog 닫기 (result: true)
              },
            ),
          ],
        ),
      );
      // 이 지점 이후 코드 없음 —
      // Navigator.pop(context, true)로 메인 dialog 종료가 시작되었으므로
      // setState 등을 호출하지 않아도 된다.
    } else {
      // mounted는 위에서 이미 확인 → 추가 async gap 없이 동기 실행
      setState(() => _isChanging = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return StyledDialog(
      title: '비밀번호 변경',
      subtitle: '보안을 위해 안전한 비밀번호를 사용하세요',
      icon: Icons.lock_outline,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // 현재 비밀번호
          StyledDialogTextField(
            controller: _currentPw,
            labelText: '현재 비밀번호',
            hintText: '현재 사용 중인 비밀번호',
            obscureText: _hideCurrent,
            suffixIcon: IconButton(
              icon: Icon(
                _hideCurrent ? Icons.visibility_off : Icons.visibility,
                color: AppColors.grey600,
                size: 22,
              ),
              onPressed: () => setState(() => _hideCurrent = !_hideCurrent),
            ),
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 20)),

          // 새 비밀번호 + 강도 표시기
          StyledDialogTextField(
            controller: _newPw,
            labelText: '새 비밀번호',
            hintText: '영문, 숫자, 특수문자 포함 8자 이상',
            obscureText: _hideNew,
            onChanged: _calcStrength,
            suffixIcon: IconButton(
              icon: Icon(
                _hideNew ? Icons.visibility_off : Icons.visibility,
                color: AppColors.grey600,
                size: 22,
              ),
              onPressed: () => setState(() => _hideNew = !_hideNew),
            ),
          ),
          if (_newPw.text.isNotEmpty) ...[
            SizedBox(height: ResponsiveHelper.spacing(context, 10)),
            PasswordStrengthIndicator(strength: _strength),
          ],
          SizedBox(height: ResponsiveHelper.spacing(context, 20)),

          // 새 비밀번호 확인
          StyledDialogTextField(
            controller: _confirmPw,
            labelText: '새 비밀번호 확인',
            hintText: '새 비밀번호를 다시 입력하세요',
            obscureText: _hideConfirm,
            suffixIcon: IconButton(
              icon: Icon(
                _hideConfirm ? Icons.visibility_off : Icons.visibility,
                color: AppColors.grey600,
                size: 22,
              ),
              onPressed: () => setState(() => _hideConfirm = !_hideConfirm),
            ),
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 16)),

          // 비밀번호 규칙 힌트
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.info_outline, size: 13, color: AppColors.grey400),
              SizedBox(width: ResponsiveHelper.spacing(context, 6)),
              Expanded(
                child: Text(
                  '영문, 숫자, 특수문자를 조합하여 8자 이상 입력해주세요.',
                  style: ResponsiveHelper.smallStyle(context,
                      color: AppColors.grey500),
                ),
              ),
            ],
          ),
        ],
      ),
      actions: [
        StyledDialogButton.cancel(
          onPressed: () {
            if (!_isChanging) Navigator.pop(context, false);
          },
        ),
        StyledDialogButton.primary(
          text: _isChanging ? '변경 중...' : '변경하기',
          onPressed: _onSubmit,
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _InfoRow {
  final String label;
  final String value;
  const _InfoRow(this.label, this.value);
}
