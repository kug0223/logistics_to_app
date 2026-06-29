// lib/screens/common/profile_edit_screen.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:intl/intl.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cached_network_image/cached_network_image.dart' show CachedNetworkImageProvider;

// Providers
import '../../providers/user_provider.dart';

// Models
import '../../models/core/user_model.dart';

// Services
import '../../services/firestore_service.dart';
import '../../services/auth_service.dart';

// Utils
import '../../utils/responsive_helper.dart';
import '../../utils/toast_helper.dart';

// Widgets
import '../../widgets/common/common_widgets.dart';
import '../../widgets/inputs/daum_address_search.dart';
import '../../widgets/dialogs/styled_dialog.dart';
import '../../theme/app_colors.dart';
import '../../widgets/common/gradient_scaffold.dart';

/// 프로필 수정 화면
class ProfileEditScreen extends StatefulWidget {
  const ProfileEditScreen({super.key});

  @override
  State<ProfileEditScreen> createState() => _ProfileEditScreenState();
}

class _ProfileEditScreenState extends State<ProfileEditScreen> {
  final _formKey = GlobalKey<FormState>();
  final _firestoreService = FirestoreService();
  final _authService = AuthService();

  late TextEditingController _phoneController;
  late TextEditingController _addressController;
  late TextEditingController _detailAddressController;

  bool _isLoading = false;
  bool _hasChanges = false;
  bool _isUploadingPhoto = false;

  @override
  void initState() {
    super.initState();
    _initControllers();
  }

  void _initControllers() {
    final user = context.read<UserProvider>().currentUser;
    _phoneController = TextEditingController(text: user?.phone ?? '');
    _addressController = TextEditingController(text: user?.address ?? '');
    _detailAddressController = TextEditingController(text: user?.detailAddress ?? '');

    _phoneController.addListener(_checkChanges);
    _addressController.addListener(_checkChanges);
    _detailAddressController.addListener(_checkChanges);
  }

  void _checkChanges() {
    final user = context.read<UserProvider>().currentUser;
    if (user == null) return;
    setState(() {
      _hasChanges =
          _addressController.text != (user.address ?? '') ||
          _detailAddressController.text != (user.detailAddress ?? '');
    });
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _addressController.dispose();
    _detailAddressController.dispose();
    super.dispose();
  }

  // ── 프로필 사진 ──────────────────────────────────────────────

  Future<void> _showPhotoPicker() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      // useSafeArea: true 사용 중이므로 내부 SafeArea 제거 (D-L-1)
      builder: (ctx) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36, height: 4, margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                  color: AppColors.grey300,
                  borderRadius: BorderRadius.circular(2)),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('앨범에서 선택'),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined),
              title: const Text('카메라로 촬영'),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
          ],
        ),
      ),
    );
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
    final ref = FirebaseStorage.instance
        .ref('users/${user.uid}/profile/photo.jpg');
    String? uploadedUrl;
    try {
      final bytes = await picked.readAsBytes();
      final task = await ref.putData(
          bytes, SettableMetadata(contentType: 'image/jpeg'));
      uploadedUrl = await task.ref.getDownloadURL();

      // Firestore 저장 실패 시 Storage 파일 정리 후 에러 전파
      await _firestoreService.updateUserDocument(
          user.uid, {'profileImageUrl': uploadedUrl});
      if (!mounted) return;
      await context.read<UserProvider>().refreshCurrentUser();
      if (mounted) ToastHelper.showSuccess('프로필 사진이 변경되었습니다');
    } catch (e) {
      // Storage 업로드는 됐지만 Firestore 저장 실패 → orphan 방지
      if (uploadedUrl != null) {
        try { await ref.delete(); } catch (_) {}
      }
      if (mounted) ToastHelper.showError('사진 업로드에 실패했습니다');
    } finally {
      if (mounted) setState(() => _isUploadingPhoto = false);
    }
  }

  // ── 주소 검색 ─────────────────────────────────────────────────

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

  // ── 비밀번호 변경 ─────────────────────────────────────────────

  Future<void> _showPasswordChangeDialog() async {
    final currentPw = TextEditingController();
    final newPw = TextEditingController();
    final confirmPw = TextEditingController();
    bool hideCurrent = true, hideNew = true, hideConfirm = true;
    int strength = 0;
    bool isChanging = false;

    void calcStrength(String pw) {
      int s = 0;
      if (pw.length >= 8) s++;
      if (RegExp(r'[a-zA-Z]').hasMatch(pw) && RegExp(r'[0-9]').hasMatch(pw)) s++;
      if (RegExp(r'[!@#$%^&*(),.?":{}|<>]').hasMatch(pw)) s++;
      strength = s;
    }

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDs) => StyledDialog(
          title: '비밀번호 변경',
          subtitle: '보안을 위해 안전한 비밀번호를 사용하세요',
          icon: Icons.lock_outline,
          content: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              StyledDialogTextField(
                controller: currentPw,
                labelText: '현재 비밀번호',
                hintText: '현재 사용 중인 비밀번호',
                prefixIcon: Icons.lock,
                obscureText: hideCurrent,
                suffixIcon: IconButton(
                  icon: Icon(hideCurrent ? Icons.visibility_off : Icons.visibility,
                      color: AppColors.grey600, size: 22),
                  onPressed: () => setDs(() => hideCurrent = !hideCurrent),
                ),
              ),
              SizedBox(height: ResponsiveHelper.spacing(ctx, 20)),
              StyledDialogTextField(
                controller: newPw,
                labelText: '새 비밀번호',
                hintText: '영문, 숫자, 특수문자 포함 8자 이상',
                prefixIcon: Icons.lock_open,
                obscureText: hideNew,
                onChanged: (v) => setDs(() => calcStrength(v)),
                suffixIcon: IconButton(
                  icon: Icon(hideNew ? Icons.visibility_off : Icons.visibility,
                      color: AppColors.grey600, size: 22),
                  onPressed: () => setDs(() => hideNew = !hideNew),
                ),
              ),
              if (newPw.text.isNotEmpty) ...[
                SizedBox(height: ResponsiveHelper.spacing(ctx, 10)),
                PasswordStrengthIndicator(strength: strength),
              ],
              SizedBox(height: ResponsiveHelper.spacing(ctx, 20)),
              StyledDialogTextField(
                controller: confirmPw,
                labelText: '새 비밀번호 확인',
                hintText: '새 비밀번호를 다시 입력하세요',
                prefixIcon: Icons.check_circle_outline,
                obscureText: hideConfirm,
                suffixIcon: IconButton(
                  icon: Icon(hideConfirm ? Icons.visibility_off : Icons.visibility,
                      color: AppColors.grey600, size: 22),
                  onPressed: () => setDs(() => hideConfirm = !hideConfirm),
                ),
              ),
              SizedBox(height: ResponsiveHelper.spacing(ctx, 20)),
              StyledDialogInfoCard.info(
                  '영문, 숫자, 특수문자를 조합하여 8자 이상으로 만들어주세요.'),
            ],
          ),
          actions: [
            StyledDialogButton.cancel(
                onPressed: () { if (!isChanging) Navigator.pop(ctx, false); }),
            StyledDialogButton.primary(
              text: isChanging ? '변경 중...' : '변경하기',
              onPressed: () async {
                if (isChanging) return;
                if (currentPw.text.isEmpty) {
                  ToastHelper.showWarning('현재 비밀번호를 입력해주세요'); return;
                }
                if (newPw.text.length < 8) {
                  ToastHelper.showWarning('새 비밀번호는 8자 이상이어야 합니다'); return;
                }
                if (!RegExp(r'[a-zA-Z]').hasMatch(newPw.text)) {
                  ToastHelper.showWarning('영문을 포함해야 합니다'); return;
                }
                if (!RegExp(r'[0-9]').hasMatch(newPw.text)) {
                  ToastHelper.showWarning('숫자를 포함해야 합니다'); return;
                }
                if (!RegExp(r'[!@#$%^&*(),.?":{}|<>]').hasMatch(newPw.text)) {
                  ToastHelper.showWarning('특수문자를 포함해야 합니다'); return;
                }
                if (newPw.text != confirmPw.text) {
                  ToastHelper.showWarning('새 비밀번호가 일치하지 않습니다'); return;
                }
                setDs(() => isChanging = true);
                final success = await _authService.changePassword(
                    currentPassword: currentPw.text,
                    newPassword: newPw.text);
                if (success && ctx.mounted) {
                  setDs(() => isChanging = false);
                  await showDialog(
                    context: ctx,
                    barrierDismissible: false,
                    builder: (rc) => StyledDialog(
                      title: '비밀번호 변경 완료',
                      subtitle: null,
                      icon: Icons.check_circle,
                      headerColor: AppColors.successMedium,
                      content: Text('비밀번호가 성공적으로 변경되었습니다.',
                          style: ResponsiveHelper.bodyStyle(rc),
                          textAlign: TextAlign.center),
                      actions: [
                        StyledDialogButton.primary(
                          text: '확인',
                          onPressed: () {
                            Navigator.pop(rc);
                            Navigator.pop(ctx, true);
                          },
                        ),
                      ],
                    ),
                  );
                } else if (ctx.mounted) {
                  setDs(() => isChanging = false);
                }
              },
            ),
          ],
        ),
      ),
    );

    currentPw.dispose();
    newPw.dispose();
    confirmPw.dispose();

    if (result == true && mounted) {
      ToastHelper.showSuccess('비밀번호가 변경되었습니다');
    }
  }

  // ── 저장 ─────────────────────────────────────────────────────

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

      if (updates.isNotEmpty) {
        await _firestoreService.updateUserDocument(user.uid, updates);
        if (!mounted) return;
        await context.read<UserProvider>().refreshCurrentUser();
        if (!mounted) return;
        ToastHelper.showSuccess('프로필이 수정되었습니다');
        setState(() {
          _hasChanges = false;
        });
      }
    } catch (e) {
      if (mounted) ToastHelper.showError('프로필 수정에 실패했습니다');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ── Build ─────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final user = context.select<UserProvider, UserModel?>((p) => p.currentUser);
    if (user == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    return GradientScaffold(
      title: '프로필 수정',
      actions: [
        if (_hasChanges)
          TextButton(
            onPressed: _isLoading ? null : _saveProfile,
            child: _isLoading
                ? const SizedBox(
                    width: 18, height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : Text('저장',
                    style: ResponsiveHelper.bodyStyle(context)
                        .copyWith(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
      ],
      body: Form(
        key: _formKey,
        child: ListView(
          padding: ResponsiveHelper.listPadding(context),
          children: [
            SizedBox(height: ResponsiveHelper.spacing(context, 8)),

            // ── 프로필 사진 ─────────────────────────────────────
            _buildAvatarSection(user),

            SizedBox(height: ResponsiveHelper.spacing(context, 24)),

            // ── 기본 정보 ───────────────────────────────────────
            _buildSectionLabel('기본 정보', Icons.person_outline),
            SizedBox(height: ResponsiveHelper.spacing(context, 8)),
            _buildReadOnlyCard(user),

            SizedBox(height: ResponsiveHelper.spacing(context, 20)),

            // ── 연락처 ──────────────────────────────────────────
            _buildSectionLabel('연락처', Icons.contact_phone_outlined),
            SizedBox(height: ResponsiveHelper.spacing(context, 8)),
            _buildContactCard(user),

            SizedBox(height: ResponsiveHelper.spacing(context, 20)),

            // ── 주소 ────────────────────────────────────────────
            _buildSectionLabel('주소', Icons.location_on_outlined),
            SizedBox(height: ResponsiveHelper.spacing(context, 8)),
            _buildAddressCard(),

            SizedBox(height: ResponsiveHelper.spacing(context, 20)),

            // ── 보안 ────────────────────────────────────────────
            _buildSectionLabel('보안', Icons.security_outlined),
            SizedBox(height: ResponsiveHelper.spacing(context, 8)),
            _buildSecurityCard(),

            SizedBox(height: ResponsiveHelper.spacing(context, 32)),
          ],
        ),
      ),
    );
  }

  // ── 위젯 빌더 ─────────────────────────────────────────────────

  Widget _buildAvatarSection(UserModel user) {
    final theme = Theme.of(context);
    final hasPhoto = (user.profileImageUrl?.isNotEmpty ?? false);
    final avatarSize = ResponsiveHelper.spacing(context, 60);
    final badgeSize = ResponsiveHelper.spacing(context, 22);

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 16),
        vertical: ResponsiveHelper.spacing(context, 14),
      ),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Row(children: [
        // 아바타
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
                  image: hasPhoto
                      ? DecorationImage(
                          image: CachedNetworkImageProvider(user.profileImageUrl!),
                          fit: BoxFit.cover)
                      : null,
                ),
                child: _isUploadingPhoto
                    ? Center(
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: theme.primaryColor))
                    : !hasPhoto
                        ? Center(
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
                          )
                        : null,
              ),
              Positioned(
                bottom: 0, right: 0,
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
        SizedBox(width: ResponsiveHelper.spacing(context, 14)),
        // 이름/아이디
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
        // 사진 변경 텍스트 힌트
        GestureDetector(
          onTap: _showPhotoPicker,
          child: Text('사진 변경',
              style: ResponsiveHelper.tinyStyle(context,
                  color: theme.primaryColor, fontWeight: FontWeight.w600)),
        ),
      ]),
    );
  }

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

  Widget _buildCard({required Widget child}) {
    return Container(
      decoration: CommonWidgets.compactCardDecoration(
          color: Theme.of(context).colorScheme.surface),
      child: child,
    );
  }

  Widget _buildReadOnlyCard(UserModel user) {
    final rows = <_InfoRow>[
      _InfoRow(Icons.person_outline, '이름', user.name),
      _InfoRow(Icons.badge_outlined, '아이디', user.username),
      if (user.birthDate != null)
        _InfoRow(Icons.cake_outlined, '생년월일',
            DateFormat('yyyy.MM.dd').format(user.birthDate!)),
      if (user.gender != null)
        _InfoRow(
            user.gender == '남성' ? Icons.male : Icons.female,
            '성별',
            user.gender!),
    ];

    return _buildCard(
      child: Column(
        children: [
          for (int i = 0; i < rows.length; i++) ...[
            _buildInfoRow(rows[i]),
            if (i < rows.length - 1)
              const Divider(height: 1, indent: 52, thickness: 0.5),
          ],
        ],
      ),
    );
  }

  Widget _buildInfoRow(_InfoRow row) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 16),
        vertical: ResponsiveHelper.spacing(context, 12),
      ),
      child: Row(children: [
        Container(
          width: ResponsiveHelper.spacing(context, 34),
          height: ResponsiveHelper.spacing(context, 34),
          decoration: BoxDecoration(
            color: theme.primaryColor.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(row.icon,
              size: ResponsiveHelper.iconSize(context, 16),
              color: theme.primaryColor.withValues(alpha: 0.7)),
        ),
        SizedBox(width: ResponsiveHelper.spacing(context, 12)),
        Text(row.label,
            style: ResponsiveHelper.bodyStyle(context,
                color: AppColors.grey600)),
        const Spacer(),
        Text(row.value,
            style: ResponsiveHelper.bodyStyle(context)
                .copyWith(fontWeight: FontWeight.w600)),
      ]),
    );
  }

  Widget _buildContactCard(UserModel user) {
    return _buildCard(
      child: Padding(
        padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 16)),
        child: Column(children: [
          CommonWidgets.textField(
            context: context,
            controller: _phoneController,
            label: '전화번호',
            hint: '01012345678',
            icon: Icons.phone_outlined,
            keyboardType: TextInputType.phone,
            readOnly: true,
          ),
        ]),
      ),
    );
  }

  Widget _buildAddressCard() {
    return _buildCard(
      child: Padding(
        padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 16)),
        child: Column(children: [
          if (kIsWeb)
            CommonWidgets.textField(
              context: context,
              controller: _addressController,
              label: '주소',
              hint: '주소를 직접 입력해주세요',
              icon: Icons.location_on_outlined,
            )
          else
            CommonWidgets.textField(
              context: context,
              controller: _addressController,
              label: '주소',
              hint: '주소 검색 버튼을 눌러주세요',
              icon: Icons.location_on_outlined,
              readOnly: true,
              onTap: _searchAddress,
              suffixIcon: IconButton(
                onPressed: _searchAddress,
                icon: Icon(Icons.search,
                    color: Theme.of(context).primaryColor),
              ),
            ),
          SizedBox(height: ResponsiveHelper.spacing(context, 12)),
          CommonWidgets.textField(
            context: context,
            controller: _detailAddressController,
            label: '상세주소',
            hint: '동/호수 입력',
            icon: Icons.home_outlined,
          ),
        ]),
      ),
    );
  }

  Widget _buildSecurityCard() {
    return _buildCard(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _showPasswordChangeDialog,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: ResponsiveHelper.spacing(context, 16),
              vertical: ResponsiveHelper.spacing(context, 12),
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

class _InfoRow {
  final IconData icon;
  final String label;
  final String value;
  const _InfoRow(this.icon, this.label, this.value);
}
