import 'dart:convert';
import 'dart:typed_data';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:package_info_plus/package_info_plus.dart';

// Models
import '../../models/core/user_model.dart';

// Providers
import '../../providers/user_provider.dart';
import '../../providers/theme_provider.dart';

// Utils
import '../../utils/responsive_helper.dart';
import '../../utils/navigation_helper.dart';

// Widgets
import '../../widgets/common/common_widgets.dart';
import '../../widgets/contract/signature_pad_widget.dart';
// restart_program_dialog, trust_score_info_dialog: [5A.2A] 신뢰도 UI 제거
import '../../widgets/common/badge_display_widget.dart';

// Screens
import '../business_admin/contract_template_list_screen.dart';
import '../business_admin/member_management_screen.dart';
import '../business_admin/admin_review_list_screen.dart';
import '../business_admin/work_type_management_screen.dart';
import 'document_management_screen.dart';
import 'help_screen.dart';
import '../user/my_reviews_screen.dart';
import 'profile_edit_screen.dart';
import '../business_admin/business_list_screen.dart';
import '../business_admin/admin_contract_management_screen.dart';
import '../business_admin/payroll/payroll_payment_dashboard_screen.dart';
import '../business_admin/business_admin_home_screen.dart';
import '../user/my_applications_screen.dart';
import '../user/subadmin_leave_screen.dart';
import '../super_admin/all_businesses_screen.dart';
import '../super_admin/all_users_screen.dart';
import '../super_admin/legal_terms_management_screen.dart';
import '../../services/legal_terms_service.dart';
import '../../models/core/legal_terms_model.dart';
import '../super_admin/help_faq_management_screen.dart';

// Tour
import '../../utils/tour_helper.dart';
import 'tour_screen.dart';

// Services
import '../../services/auth_service.dart';
import '../../services/firestore_service.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../services/fcm_service.dart';

// Utils
import '../../utils/toast_helper.dart';
import '../../utils/image_helper.dart';
import '../../utils/dialog_helper.dart';
import '../../utils/business_picker_helper.dart';
import '../../theme/app_colors.dart';
import '../../widgets/common/gradient_scaffold.dart';

/// ✨ 통합 설정 화면 (역할별 메뉴 자동 표시)
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _isPushEnabled = true;
  bool _isLoading = true;
  Map<String, bool> _notifPrefs = Map.of(UserModel.defaultNotifPrefs);
  bool _isNotifPrefsLoading = false;
  bool _isNotifExpanded = false;
  String _appVersion = '';
  String? _businessSealBase64;
  String _sealType = 'stamp';
  String? _resolvedBusinessId;
  bool _isSealLoading = true;
  // [PERF] base64 디코딩 캐시 — build마다 재디코딩 방지
  Uint8List? _cachedSignatureBytes;
  String? _cachedSignatureBase64;
  Uint8List? _cachedSealBytes;
  String? _cachedSealBase64;

  @override
  void initState() {
    super.initState();
    _loadNotificationStatus();
    _loadAppVersion();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadBusinessSeal());
  }

  Future<void> _loadBusinessSeal() async {
    final user = context.read<UserProvider>().currentUser;

    // BUSINESS_ADMIN·SUB_ADMIN 외에는 즉시 로딩 해제
    if (user == null || (!user.isBusinessAdmin && !user.isSubAdmin)) {
      if (mounted) setState(() => _isSealLoading = false);
      return;
    }

    // 날인 + 사업장 ID 즉시 표시 (비동기 쿼리 전, 블로킹 없음)
    if (!mounted) return;
    setState(() {
      _businessSealBase64 = user.sealBase64;
      _sealType = user.sealType;
      _resolvedBusinessId = context.read<UserProvider>().effectiveBusinessId;
      // BUSINESS_ADMIN: null → 아래 CF 조회 분기로 진입 / SUB_ADMIN: effectiveBusinessId(선택 사업장)
      _isSealLoading = false;
    });

    // effectiveBusinessId가 null(BUSINESS_ADMIN 멀티사업장)이면 CF로 사업장 조회 (UI 블로킹 없음)
    if (_resolvedBusinessId == null) {
      try {
        final callable =
            FirebaseFunctions.instanceFor(region: 'asia-northeast3')
                .httpsCallable('callableGetMyBusiness');
        final response = await callable.call<Map<String, dynamic>>({});
        final list = (response.data['businesses'] as List?) ?? [];
        if (list.isNotEmpty && mounted) {
          final first = Map<String, dynamic>.from(list.first as Map);
          setState(() => _resolvedBusinessId = first['id'] as String?);
        }
      } catch (e) {
        if (kDebugMode) debugPrint('⚠️ 사업장 조회 실패: $e');
      }
    }
  }

  Future<void> _loadAppVersion() async {
    final info = await PackageInfo.fromPlatform();
    if (mounted) setState(() => _appVersion = info.version);
  }

  /// 알림 상태 로드
  Future<void> _loadNotificationStatus() async {
    final userProvider = context.read<UserProvider>();
    final userId = userProvider.currentUser?.uid;

    if (userId != null) {
      // 시스템 권한 + Firestore fcmToken 둘 다 확인
      final permissionStatus = await Permission.notification.status;
      final systemGranted = permissionStatus.isGranted;

      bool hasFcmToken = false;
      Map<String, bool>? savedPrefs;
      if (systemGranted) {
        final doc = await FirebaseFirestore.instance
            .collection('users')
            .doc(userId)
            .get();
        hasFcmToken = doc.data()?['fcmToken'] != null;
        final raw = doc.data()?['notifPrefs'];
        if (raw is Map) {
          savedPrefs = Map<String, bool>.from(
            raw.map((k, v) => MapEntry(k.toString(), v == true)),
          );
        }
      }

      if (mounted) {
        setState(() {
          _isPushEnabled = systemGranted && hasFcmToken;
          if (savedPrefs != null) {
            _notifPrefs = {
              ...UserModel.defaultNotifPrefs,
              ...savedPrefs,
            };
          }
          _isLoading = false;
        });
      }
    } else {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// 개별 알림 카테고리 토글
  Future<void> _toggleNotifPref(String key, bool value) async {
    final userId = context.read<UserProvider>().currentUser?.uid;
    if (userId == null) return;
    setState(() {
      _notifPrefs = {..._notifPrefs, key: value};
      _isNotifPrefsLoading = true;
    });
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .update({'notifPrefs': _notifPrefs});
    } catch (e) {
      // 실패 시 롤백
      if (mounted) {
        setState(() => _notifPrefs = {..._notifPrefs, key: !value});
        ToastHelper.showError('설정 저장에 실패했습니다');
      }
    } finally {
      if (mounted) setState(() => _isNotifPrefsLoading = false);
    }
  }

  /// 푸시 알림 토글
  Future<void> _togglePushNotification(bool value) async {
    if (_isLoading) return; // 중복 실행 방어
    setState(() => _isLoading = true);

    try {
      final userProvider = context.read<UserProvider>();
      final userId = userProvider.currentUser?.uid;

      if (userId == null) {
        return;
      }

      if (value) {
        // 알림 켜기 → 시스템 권한 먼저 확인
        final permissionStatus = await Permission.notification.status;
        if (permissionStatus.isDenied) {
          await Permission.notification.request();
        }
        final granted = await Permission.notification.isGranted;
        if (!mounted) return;
        if (!granted) {
          ToastHelper.showWarning('기기 설정에서 알림 권한을 허용해주세요');
          await openAppSettings();
          return;
        }
        // SubAdmin은 현재 모드(isAdminMode) 기준, 그 외는 isAdmin 그대로
        final isAdminForFcm = userProvider.isSubAdmin
            ? userProvider.isAdminMode
            : userProvider.isAdmin;
        await FCMService().initialize(userId, isAdmin: isAdminForFcm);
        if (!mounted) return;
        ToastHelper.showSuccess('푸시 알림이 활성화되었습니다');
      } else {
        // 알림 끄기 → FCM 토큰 삭제
        await FCMService().clearToken();
        if (!mounted) return;
        ToastHelper.showSuccess('푸시 알림이 비활성화되었습니다');
      }

      setState(() => _isPushEnabled = value);
    } catch (e) {
      if (kDebugMode) debugPrint('❌ 알림 설정 변경 실패: $e');
      if (mounted) ToastHelper.showError('알림 설정 변경에 실패했습니다');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Selector<UserProvider, ({UserModel? user, bool isAdminMode})>(
      selector: (_, p) => (user: p.currentUser, isAdminMode: p.isAdminMode),
      builder: (context, data, _) {
        final user = data.user;
        final userProvider = context.read<UserProvider>();
        final theme = Theme.of(context);
        final isSubAdminInAdminMode =
            (user?.isSubAdmin ?? false) && data.isAdminMode;
        final isSubAdminInUserMode =
            (user?.isSubAdmin ?? false) && !data.isAdminMode;
        final showUserItems =
            user?.role == UserRole.USER || isSubAdminInUserMode;
        final showAdminSection =
            user?.role == UserRole.BUSINESS_ADMIN || isSubAdminInAdminMode;

        return GradientScaffold(
          title: '설정',
          headerContent: _buildHeaderProfile(context, userProvider),
          body: ListView(
            padding: ResponsiveHelper.listPadding(context),
            children: [
              SizedBox(height: ResponsiveHelper.spacing(context, 8)),

              // UX-04: 설정 화면에 필수/선택 항목 구분 없음
              // 근로자 기준 공고 지원 필수 항목: PASS 본인인증, 신분증, 통장사본, 계좌 등록
              // 현재는 '내 서류 관리' 안에 모두 섞여 있어 신규 사용자가 무엇을 먼저 해야 하는지 파악 어려움
              // 개선 방향: 미완료 필수 항목에 빨간 뱃지 표시, 또는 상단에 "완료 N/4" 진행 바 추가
              // ── 내 정보 ──────────────────────────────────────────
              _buildSectionHeader(context, '내 정보', Icons.person_outline),
              SizedBox(height: ResponsiveHelper.spacing(context, 8)),
              _buildMenuGroup(context, [
                _SettingsItem(
                  icon: Icons.edit_outlined,
                  iconColor: theme.primaryColor,
                  title: '프로필 수정',
                  onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const ProfileEditScreen())),
                ),
              ]),
              if (showUserItems) ...[
                SizedBox(height: ResponsiveHelper.spacing(context, 8)),
                _buildMenuGroup(context, [
                  _buildDocumentMenuItem(context, user),
                  _SettingsItem(
                    icon: Icons.star_rounded,
                    iconColor: AppColors.warning,
                    title: '내 평가 확인',
                    onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const MyReviewsScreen())),
                  ),
                ]),
                SizedBox(height: ResponsiveHelper.spacing(context, 8)),
                _buildSignatureCard(context, user),
              ],

              // ── 서브관리자 관리 ─────────────────────────────────
              if (user?.isSubAdmin == true) ...[
                SizedBox(height: ResponsiveHelper.spacing(context, 20)),
                _buildSectionHeader(
                    context, '서브관리자 관리', Icons.admin_panel_settings_outlined),
                SizedBox(height: ResponsiveHelper.spacing(context, 8)),
                _buildMenuGroup(context, [
                  // [PD-01] 관리자 모드 중일 때: 지원자 모드 복귀 CTA
                  if (isSubAdminInAdminMode)
                    _SettingsItem(
                      icon: Icons.person_outline,
                      iconColor: AppColors.infoDark,
                      title: '지원자 모드로 전환',
                      onTap: () => userProvider.toggleAdminMode(),
                      // toggleAdminMode() → notifyListeners() → AuthWrapper 반응형 라우팅 → UserRootScreen
                    ),
                  _SettingsItem(
                    icon: Icons.logout_outlined,
                    iconColor: AppColors.error,
                    title: '서브관리자 탈퇴',
                    subtitle: '${user!.subAdminBusinessIds.length}개 사업장',
                    subtitleColor: AppColors.grey500,
                    onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const SubadminLeaveScreen())),
                  ),
                ]),
              ],

              SizedBox(height: ResponsiveHelper.spacing(context, 20)),

              // ── 사업장 설정 (관리자) ─────────────────────────────
              if (showAdminSection) ...[
                _buildSectionHeader(context, '사업장 설정', Icons.business_outlined),
                SizedBox(height: ResponsiveHelper.spacing(context, 8)),
                // [5D.2A] BUSINESS_ADMIN: 사업장 서류 관리 → BusinessListScreen
                // canonical 경로: businesses/{bizId}.businessLicenseImageUrl
                // DocumentManagementScreen은 legacy users/{uid} 경로만 업데이트 — BUSINESS_ADMIN primary UX 부적합
                if (user?.isBusinessAdmin == true) ...[
                  _buildMenuGroup(context, [
                    _SettingsItem(
                      icon: Icons.description_outlined,
                      iconColor: AppColors.successDark,
                      title: '사업장 서류 관리',
                      onTap: () => NavigationHelper.push<void>(context,
                          destination: const BusinessListScreen()),
                    ),
                  ]),
                  SizedBox(height: ResponsiveHelper.spacing(context, 8)),
                ],
                // 날인 카드: BUSINESS_ADMIN 항상 / SubAdmin은 계약서 관리 권한 있을 때만
                if (user?.isBusinessAdmin == true ||
                    userProvider.can((p) => p.canManageContract)) ...[
                  _buildSealCard(context, user),
                  SizedBox(height: ResponsiveHelper.spacing(context, 8)),
                ],
                _buildMenuGroup(context, [
                  _SettingsItem(
                    icon: Icons.business_outlined,
                    iconColor: AppColors.purpleDark,
                    title: '사업장 정보',
                    onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const BusinessListScreen())),
                  ),
                  user?.isBusinessAdmin == true ||
                          userProvider.can((p) => p.canManageTo)
                      ? _SettingsItem(
                          icon: Icons.work_outline,
                          iconColor: AppColors.warningDark,
                          title: '업무 유형 관리',
                          onTap: () async {
                            final nav = Navigator.of(context);
                            final biz =
                                await BusinessPickerHelper.pick(context);
                            if (biz == null || !mounted) return;
                            nav.push(MaterialPageRoute(
                                builder: (_) => WorkTypeManagementScreen(
                                    businessId: biz.id,
                                    businessName: biz.name)));
                          },
                        )
                      : null,
                  user?.isBusinessAdmin == true ||
                          userProvider.can((p) => p.canManageContract)
                      ? _SettingsItem(
                          icon: Icons.article_outlined,
                          iconColor: AppColors.infoDark,
                          title: '근로계약서 관리',
                          onTap: () async {
                            final nav = Navigator.of(context);
                            final biz =
                                await BusinessPickerHelper.pick(context);
                            if (biz == null || !mounted) return;
                            if (kDebugMode) {
                              debugPrint(
                                  '📋 [settings/contractTemplate] businessId=${biz.id}');
                            }
                            nav.push(MaterialPageRoute(
                                builder: (_) => ContractTemplateListScreen(
                                    businessId: biz.id)));
                          },
                        )
                      : null,
                  user?.isBusinessAdmin == true
                      ? _SettingsItem(
                          icon: Icons.group_outlined,
                          iconColor: theme.primaryColor,
                          title: '팀원 관리',
                          onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) =>
                                      const MemberManagementScreen())),
                        )
                      : null,
                  user?.isBusinessAdmin == true ||
                          userProvider.can((p) => p.canManageWorkers)
                      ? _SettingsItem(
                          icon: Icons.rate_review_outlined,
                          iconColor: AppColors.warningDark,
                          title: '리뷰 관리',
                          onTap: () async {
                            final nav = Navigator.of(context);
                            final biz =
                                await BusinessPickerHelper.pick(context);
                            if (biz == null || !mounted) return;
                            nav.push(MaterialPageRoute(
                                builder: (_) =>
                                    AdminReviewListScreen(businessId: biz.id)));
                          },
                        )
                      : null,
                ]),
                SizedBox(height: ResponsiveHelper.spacing(context, 20)),
              ],

              // ── 관리자 메뉴 (슈퍼) ──────────────────────────────
              if (user?.role == UserRole.SUPER_ADMIN) ...[
                _buildSectionHeader(
                    context, '관리자 메뉴', Icons.admin_panel_settings_outlined),
                SizedBox(height: ResponsiveHelper.spacing(context, 8)),
                _buildMenuGroup(context, [
                  _SettingsItem(
                    icon: Icons.people_outline,
                    iconColor: AppColors.errorDark,
                    title: '전체 사용자 관리',
                    onTap: () => NavigationHelper.push(context,
                        destination: const AllUsersScreen()),
                  ),
                  _SettingsItem(
                    icon: Icons.business_center_outlined,
                    iconColor: AppColors.purpleDark,
                    title: '전체 사업장 관리',
                    onTap: () => NavigationHelper.push(context,
                        destination: const AllBusinessesScreen()),
                  ),
                  _SettingsItem(
                    icon: Icons.gavel_outlined,
                    iconColor: AppColors.infoDark,
                    title: '약관 관리',
                    onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) =>
                                const LegalTermsManagementScreen())),
                  ),
                  _SettingsItem(
                    icon: Icons.help_outline_rounded,
                    iconColor: AppColors.successDark,
                    title: '도움말 FAQ 관리',
                    onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const HelpFaqManagementScreen())),
                  ),
                ]),
                SizedBox(height: ResponsiveHelper.spacing(context, 20)),
                _buildSectionHeader(
                    context, '개발자 도구', Icons.developer_mode_outlined),
                SizedBox(height: ResponsiveHelper.spacing(context, 8)),
                _buildMenuGroup(context, [
                  _SettingsItem(
                    icon: Icons.sync,
                    iconColor: AppColors.warningDark,
                    title: 'Application 마이그레이션',
                    onTap: () => _runApplicationMigration(context),
                  ),
                  _SettingsItem(
                    icon: Icons.access_time_filled,
                    iconColor: AppColors.info,
                    title: '총 근무시간 마이그레이션',
                    subtitle: 'totalWorkHours 0 오류 복구',
                    onTap: () => _runWorkHoursMigration(context),
                  ),
                ]),
                SizedBox(height: ResponsiveHelper.spacing(context, 20)),
              ],

              // ── 알림 ─────────────────────────────────────────────
              _buildSectionHeader(context, '알림', Icons.notifications_outlined),
              SizedBox(height: ResponsiveHelper.spacing(context, 8)),
              _buildNotificationToggleCard(context),
              if (_isPushEnabled) ...[
                SizedBox(height: ResponsiveHelper.spacing(context, 8)),
                _buildNotifExpandTile(context,
                    isEffectiveAdmin:
                        showAdminSection || user?.role == UserRole.SUPER_ADMIN),
              ],
              SizedBox(height: ResponsiveHelper.spacing(context, 4)),
              _buildMenuGroup(context, [
                _SettingsItem(
                  icon: Icons.settings_applications_outlined,
                  iconColor: AppColors.grey600,
                  title: '시스템 알림 설정',
                  onTap: () async => openAppSettings(),
                ),
              ]),
              SizedBox(height: ResponsiveHelper.spacing(context, 20)),

              // ── 앱 정보 ──────────────────────────────────────────
              _buildSectionHeader(context, '앱 정보', Icons.info_outline),
              SizedBox(height: ResponsiveHelper.spacing(context, 8)),
              _buildInfoCard(context, items: [
                {
                  'icon': Icons.phone_android,
                  'title': '앱 버전',
                  'value': _appVersion.isEmpty ? '...' : _appVersion,
                },
              ]),
              SizedBox(height: ResponsiveHelper.spacing(context, 20)),

              // ── 도움말 ───────────────────────────────────────────
              _buildSectionHeader(context, '도움말', Icons.help_outline),
              SizedBox(height: ResponsiveHelper.spacing(context, 8)),
              _buildMenuGroup(context, [
                _SettingsItem(
                  icon: Icons.help_outline,
                  iconColor: AppColors.infoDark,
                  title: '도움말 (Q&A)',
                  onTap: () => Navigator.push(context,
                      MaterialPageRoute(builder: (_) => const HelpScreen())),
                ),
                _SettingsItem(
                  icon: Icons.tour_outlined,
                  iconColor: AppColors.purpleDark,
                  title: '가이드 다시 보기',
                  onTap: () async {
                    final role =
                        context.read<UserProvider>().currentUser?.role.name ??
                            'USER';
                    await TourHelper.resetAll();
                    if (!mounted) return;
                    // ignore: use_build_context_synchronously
                    await pushTourScreen(context, role: role);
                  },
                ),
              ]),
              SizedBox(height: ResponsiveHelper.spacing(context, 20)),

              // ── 법적 고지 ─────────────────────────────────────────
              // [LEGAL-FIX 2026-08-10] 사용자가 약관을 언제든 열람할 수 있도록 추가
              // 개인정보보호법 제35조(열람 요구권) + Google Play 정책 요구사항
              _buildSectionHeader(context, '법적 고지', Icons.policy_outlined),
              SizedBox(height: ResponsiveHelper.spacing(context, 8)),
              _buildMenuGroup(context, [
                _SettingsItem(
                  icon: Icons.article_outlined,
                  iconColor: AppColors.grey600,
                  title: '서비스 이용약관',
                  onTap: () =>
                      _showTermsInApp(context, 'service_terms', '서비스 이용약관'),
                ),
                _SettingsItem(
                  icon: Icons.privacy_tip_outlined,
                  iconColor: AppColors.infoDark,
                  title: '개인정보 처리방침',
                  onTap: () =>
                      _showTermsInApp(context, 'privacy_policy', '개인정보 처리방침'),
                ),
                _SettingsItem(
                  icon: Icons.location_on_outlined,
                  iconColor: AppColors.successDark,
                  title: '위치정보 이용 동의',
                  onTap: () =>
                      _showTermsInApp(context, 'location_terms', '위치정보 이용 동의'),
                ),
              ]),
              SizedBox(height: ResponsiveHelper.spacing(context, 24)),

              // ── 로그아웃 / 회원탈퇴 ─────────────────────────────
              _buildLogoutButton(context, userProvider),
              SizedBox(height: ResponsiveHelper.spacing(context, 8)),
              _buildDeleteAccountButton(context, userProvider),
              SizedBox(height: ResponsiveHelper.spacing(context, 24)),
            ],
          ),
        );
      },
    );
  }

  /// ✨ 세련된 프로필 카드
  /// 파란 헤더 — 가로 compact 프로필 (공간 최소화)
  Widget _buildSettingsAvatar(BuildContext context, UserModel? user) {
    final size = ResponsiveHelper.spacing(context, 52);
    final photoUrl = user?.profileImageUrl;
    final hasPhoto = photoUrl != null && photoUrl.isNotEmpty;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.2),
        shape: BoxShape.circle,
      ),
      child: ClipOval(
        child: hasPhoto
            ? CachedNetworkImage(
                imageUrl: photoUrl,
                fit: BoxFit.cover,
                placeholder: (_, __) => Icon(
                  Icons.person,
                  size: ResponsiveHelper.iconSize(context, 30),
                  color: Colors.white,
                ),
                errorWidget: (_, __, ___) => Icon(
                  Icons.person,
                  size: ResponsiveHelper.iconSize(context, 30),
                  color: Colors.white,
                ),
              )
            : Icon(
                Icons.person,
                size: ResponsiveHelper.iconSize(context, 30),
                color: Colors.white,
              ),
      ),
    );
  }

  Widget _buildHeaderProfile(BuildContext context, UserProvider userProvider) {
    final user = userProvider.currentUser;
    final isUser = user?.role == UserRole.USER;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        ResponsiveHelper.spacing(context, 16),
        ResponsiveHelper.spacing(context, 4),
        ResponsiveHelper.spacing(context, 16),
        ResponsiveHelper.spacing(context, 16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── 아바타(좌) + 이름/역할(우) 가로 배치
          Row(
            children: [
              // 작은 아바타
              _buildSettingsAvatar(context, user),
              SizedBox(width: ResponsiveHelper.spacing(context, 14)),
              // 이름 + 아이디 + 역할
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      user?.name ?? '사용자',
                      style: ResponsiveHelper.subtitleStyle(context).copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '@${user?.username ?? 'username'}',
                      style: ResponsiveHelper.tinyStyle(context,
                          color: Colors.white.withValues(alpha: 0.8)),
                    ),
                    const SizedBox(height: 6),
                    // 역할 배지 (작게)
                    Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: ResponsiveHelper.spacing(context, 8),
                        vertical: ResponsiveHelper.spacing(context, 3),
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: Colors.white.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            user?.role == UserRole.SUPER_ADMIN
                                ? Icons.verified_user
                                : user?.role == UserRole.BUSINESS_ADMIN
                                    ? Icons.admin_panel_settings
                                    : Icons.person,
                            size: ResponsiveHelper.iconSize(context, 12),
                            color: Colors.white,
                          ),
                          SizedBox(width: ResponsiveHelper.spacing(context, 4)),
                          Text(
                            CommonWidgets.getRoleName(
                                user?.roleString ?? 'USER'),
                            style: ResponsiveHelper.tinyStyle(context,
                                color: Colors.white,
                                fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          // ── 지원자 근무 통계 (한 줄 compact) — [5A.2A] 신뢰도 점수/등급/재시작 제거
          if (isUser && user != null) ...[
            SizedBox(height: ResponsiveHelper.spacing(context, 12)),
            Container(
              padding: EdgeInsets.symmetric(
                horizontal: ResponsiveHelper.spacing(context, 12),
                vertical: ResponsiveHelper.spacing(context, 8),
              ),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  // 통계 4개 inline
                  _miniStat(context, '근무', '${user.totalWorkDays}일'),
                  _miniStat(
                      context, '평점', user.averageRating.toStringAsFixed(1)),
                  _miniStat(context, '지각(90일)', '${user.recentLateCount}회'),
                  _miniStat(context, '노쇼(90일)', '${user.recentNoShowCount}회'),
                ],
              ),
            ),

            // 배지 영역 (보유 배지 있을 때만 표시)
            if (user.badges.isNotEmpty) ...[
              SizedBox(height: ResponsiveHelper.spacing(context, 12)),
              BadgeDisplayWidget(
                badgeIds: user.badges,
                compact: true,
                maxDisplay: 8,
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _miniStat(BuildContext context, String label, String value) {
    return Padding(
      padding: EdgeInsets.only(left: ResponsiveHelper.spacing(context, 8)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(value,
              style: ResponsiveHelper.tinyStyle(context,
                  color: Colors.white, fontWeight: FontWeight.bold)),
          Text(label,
              style: ResponsiveHelper.tinyStyle(context,
                  color: Colors.white.withValues(alpha: 0.7))),
        ],
      ),
    );
  }

  // [5A.2A] _showRestartProgramDialog 제거 — 재시작 프로그램 폐기

  Widget _buildSectionHeader(
      BuildContext context, String title, IconData icon) {
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

  /// [PERF] 내 서류 관리 메뉴 아이템 — subtitle·subtitleColor 중복 계산 방지
  _SettingsItem _buildDocumentMenuItem(BuildContext context, UserModel? user) {
    final idDone = user?.hasIdDocument ?? false;
    final accDone = (user?.bankName?.isNotEmpty ?? false) &&
        (user?.accountNumber?.isNotEmpty ?? false);
    final bookDone = user?.hasBankbookDocument ?? false;
    final done = [idDone, accDone, bookDone].where((v) => v).length;
    return _SettingsItem(
      icon: Icons.folder_special_outlined,
      iconColor: AppColors.successDark,
      title: '내 서류 관리',
      subtitle: done == 3
          ? '신분증 · 계좌 · 통장사본 모두 완료'
          : done == 0
              ? '신분증 · 계좌 · 통장사본 미등록'
              : '서류 $done/3 완료',
      subtitleColor: done == 3
          ? AppColors.success
          : done == 0
              ? AppColors.error
              : AppColors.warning,
      onTap: () => NavigationHelper.push<bool>(context,
          destination: const DocumentManagementScreen()),
    );
  }

  /// 여러 메뉴 항목을 하나의 카드로 묶는 그룹 위젯
  Widget _buildMenuGroup(BuildContext context, List<_SettingsItem?> items) {
    final valid = items.whereType<_SettingsItem>().toList();
    if (valid.isEmpty) return const SizedBox.shrink();
    return Container(
      decoration: CommonWidgets.compactCardDecoration(),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Column(
          children: [
            for (int i = 0; i < valid.length; i++) ...[
              _buildMenuRow(context, valid[i]),
              if (i < valid.length - 1)
                const Divider(height: 1, indent: 52, thickness: 0.5),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildMenuRow(BuildContext context, _SettingsItem item) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: item.onTap,
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
                color: item.iconColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(item.icon,
                  color: item.iconColor,
                  size: ResponsiveHelper.iconSize(context, 18)),
            ),
            SizedBox(width: ResponsiveHelper.spacing(context, 12)),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.title,
                      style: ResponsiveHelper.bodyStyle(context)
                          .copyWith(fontWeight: FontWeight.w600)),
                  if (item.subtitle != null)
                    Text(item.subtitle!,
                        style: ResponsiveHelper.smallStyle(context,
                            color: item.subtitleColor ?? AppColors.grey500)),
                ],
              ),
            ),
            Icon(Icons.chevron_right,
                size: ResponsiveHelper.iconSize(context, 18),
                color: AppColors.grey400),
          ]),
        ),
      ),
    );
  }

  /// ✨ 세련된 정보 카드
  Widget _buildInfoCard(
    BuildContext context, {
    required List<Map<String, dynamic>> items,
  }) {
    final theme = Theme.of(context);
    return Container(
      decoration: CommonWidgets.compactCardDecoration(),
      child: Column(
        children: List.generate(items.length, (index) {
          final item = items[index];
          final isLast = index == items.length - 1;
          return Column(children: [
            Padding(
              padding: EdgeInsets.symmetric(
                horizontal: ResponsiveHelper.spacing(context, 16),
                vertical: ResponsiveHelper.spacing(context, 12),
              ),
              child: Row(children: [
                Container(
                  width: ResponsiveHelper.spacing(context, 34),
                  height: ResponsiveHelper.spacing(context, 34),
                  decoration: BoxDecoration(
                    color: theme.primaryColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    item['icon'] as IconData,
                    color: theme.primaryColor,
                    size: ResponsiveHelper.iconSize(context, 18),
                  ),
                ),
                SizedBox(width: ResponsiveHelper.spacing(context, 12)),
                Expanded(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(item['title'] as String,
                          style: ResponsiveHelper.bodyStyle(context)
                              .copyWith(fontWeight: FontWeight.w600)),
                      Text(item['value'] as String,
                          style: ResponsiveHelper.bodyStyle(context,
                              color: AppColors.grey500)),
                    ],
                  ),
                ),
              ]),
            ),
            if (!isLast) const Divider(height: 1, indent: 52, thickness: 0.5),
          ]);
        }),
      ),
    );
  }

  Widget _buildNotificationToggleCard(BuildContext context) {
    final theme = Theme.of(context);
    const iconColor = AppColors.amber;
    return Container(
      decoration: CommonWidgets.compactCardDecoration(),
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
              color: iconColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(Icons.notifications_active,
                color: iconColor, size: ResponsiveHelper.iconSize(context, 18)),
          ),
          SizedBox(width: ResponsiveHelper.spacing(context, 12)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('푸시 알림',
                    style: ResponsiveHelper.bodyStyle(context)
                        .copyWith(fontWeight: FontWeight.w600)),
                Text(
                  _isPushEnabled ? '알림을 받고 있습니다' : '알림이 꺼져 있습니다',
                  style: ResponsiveHelper.tinyStyle(context,
                      color: AppColors.grey500),
                ),
              ],
            ),
          ),
          _isLoading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : Switch(
                  value: _isPushEnabled,
                  onChanged: _togglePushNotification,
                  activeThumbColor: theme.primaryColor,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
        ]),
      ),
    );
  }

  Widget _buildNotifExpandTile(BuildContext context,
      {bool isEffectiveAdmin = false}) {
    final theme = Theme.of(context);
    final items = isEffectiveAdmin
        ? [
            (
              UserModel.notifReviewAlert,
              '리뷰 요청 알림',
              Icons.rate_review_outlined
            ),
            (UserModel.notifContractAlert, '계약 알림', Icons.description_outlined),
            (UserModel.notifWageAlert, '임금 확정 알림', Icons.payments_outlined),
          ]
        : [
            (UserModel.notifWorkReminder, '근무 리마인더', Icons.schedule_outlined),
            (
              UserModel.notifApplicationUpdate,
              '지원 결과 알림',  // 거절·취소·일정변경 (확정·취소는 항상 수신)
              Icons.check_circle_outline
            ),
            (
              UserModel.notifReviewAlert,
              '리뷰 요청 알림',
              Icons.rate_review_outlined
            ),
            (UserModel.notifContractAlert, '계약 알림', Icons.description_outlined),
            (UserModel.notifWageAlert, '임금 확정 알림', Icons.payments_outlined),
            (
              UserModel.notifToMatchAlert,
              '새 일자리 알림',
              Icons.work_outline
            ),
          ];
    final enabledCount =
        items.where((item) => _notifPrefs[item.$1] ?? true).length;

    return Container(
      decoration: CommonWidgets.compactCardDecoration(),
      child: Column(
        children: [
          // 헤더 — 탭으로 펼치기/접기
          InkWell(
            onTap: () => setState(() => _isNotifExpanded = !_isNotifExpanded),
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: ResponsiveHelper.spacing(context, 16),
                vertical: ResponsiveHelper.spacing(context, 12),
              ),
              child: Row(children: [
                Icon(Icons.tune_outlined,
                    size: ResponsiveHelper.iconSize(context, 18),
                    color: AppColors.grey500),
                SizedBox(width: ResponsiveHelper.spacing(context, 12)),
                Expanded(
                  child: Text('알림 세부 설정',
                      style: ResponsiveHelper.bodyStyle(context)),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: theme.primaryColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text('$enabledCount/${items.length}',
                      style: ResponsiveHelper.tinyStyle(context,
                              color: theme.primaryColor)
                          .copyWith(fontWeight: FontWeight.w600)),
                ),
                SizedBox(width: ResponsiveHelper.spacing(context, 6)),
                AnimatedRotation(
                  turns: _isNotifExpanded ? 0.5 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: Icon(Icons.keyboard_arrow_down,
                      size: ResponsiveHelper.iconSize(context, 22),
                      color: AppColors.grey400),
                ),
              ]),
            ),
          ),
          // 펼쳐지는 개별 항목
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeInOut,
            child: _isNotifExpanded
                ? Column(
                    children: [
                      const Divider(height: 1, color: AppColors.grey100),
                      ...items.asMap().entries.map((entry) {
                        final i = entry.key;
                        final (key, label, icon) = entry.value;
                        final enabled = _notifPrefs[key] ?? true;
                        return Column(
                          children: [
                            Padding(
                              padding: EdgeInsets.symmetric(
                                horizontal:
                                    ResponsiveHelper.spacing(context, 16),
                                vertical: ResponsiveHelper.spacing(context, 10),
                              ),
                              child: Row(children: [
                                Icon(icon,
                                    size:
                                        ResponsiveHelper.iconSize(context, 18),
                                    color: enabled
                                        ? theme.primaryColor
                                        : AppColors.grey400),
                                SizedBox(
                                    width:
                                        ResponsiveHelper.spacing(context, 12)),
                                Expanded(
                                  child: Text(label,
                                      style: ResponsiveHelper.bodyStyle(context)
                                          .copyWith(
                                              color: enabled
                                                  ? null
                                                  : AppColors.grey400)),
                                ),
                                Switch(
                                  value: enabled,
                                  onChanged: _isNotifPrefsLoading
                                      ? null
                                      : (v) => _toggleNotifPref(key, v),
                                  activeThumbColor: theme.primaryColor,
                                  materialTapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                ),
                              ]),
                            ),
                            if (i < items.length - 1)
                              const Divider(
                                  height: 1,
                                  indent: 46,
                                  color: AppColors.grey100),
                          ],
                        );
                      }),
                    ],
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  // ── 약관 앱 내 뷰어 ─────────────────────────────────────────────
  // [LEGAL-FIX 2026-08-10] 개인정보보호법 제35조 열람 요구권 + Google Play 정책 대응
  // Firestore에서 해당 termId 항목을 로드 후 전체화면으로 표시
  Future<void> _showTermsInApp(
      BuildContext ctx, String termId, String fallbackTitle) async {
    LegalTermsItem? item;
    try {
      final terms = await LegalTermsService().getTerms();
      item = terms.items.where((t) => t.id == termId).firstOrNull;
    } catch (_) {
      item = null;
    }
    if (!mounted) return;
    // ignore: use_build_context_synchronously
    final nav = Navigator.of(ctx);
    await nav.push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _TermsReadOnlyScreen(
          title: item?.title ?? fallbackTitle,
          content: item?.content ?? '약관을 불러오지 못했습니다. 잠시 후 다시 시도해주세요.',
          version: item?.version,
        ),
      ),
    );
  }

  Widget _buildLogoutButton(BuildContext context, UserProvider userProvider) {
    return Container(
      width: double.infinity,
      decoration: CommonWidgets.compactCardDecoration(),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () async {
            final themeProvider = context.read<ThemeProvider>();
            final confirmed = await DialogHelper.showLogoutConfirm(context);
            // async gap 이후 mounted 체크 (CLAUDE.md 비동기 안전성 규칙)
            if (!mounted) return;
            if (confirmed) {
              themeProvider.reset();
              await userProvider.signOut();
            }
          },
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: ResponsiveHelper.spacing(context, 16),
              vertical: ResponsiveHelper.spacing(context, 13),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.logout,
                    color: AppColors.textSecondary,
                    size: ResponsiveHelper.iconSize(context, 18)),
                SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                Text('로그아웃',
                    style: ResponsiveHelper.bodyStyle(context).copyWith(
                        color: AppColors.textSecondary, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ),
      ),
    );
  }
  // ━━━ 회원탈퇴 ━━━

  Widget _buildDeleteAccountButton(
      BuildContext context, UserProvider userProvider) {
    return TextButton(
      onPressed: () => _showWithdrawalChecklist(context, userProvider),
      child: Text(
        '회원탈퇴',
        style: ResponsiveHelper.smallStyle(context, color: AppColors.error)
            .copyWith(
          decoration: TextDecoration.underline,
          decorationColor: AppColors.error,
        ),
      ),
    );
  }

  // ━━━ 탈퇴 전 체크리스트 ━━━
  // callableGetWithdrawBlockers CF로 BLOCK/WARNING 조건 확인 후 비밀번호 시트로 이동
  Future<void> _showWithdrawalChecklist(
      BuildContext context, UserProvider userProvider) async {
    String? navTarget; // 네비게이션 목적지 (null = 이동 없음)

    final shouldProceed = await DialogHelper.showSheet<bool>(
      context,
      isScrollControlled: true,
      builder: (outerCtx) {
        // StatefulBuilder 외부에 선언 → 한 번만 초기화
        bool isLoading = true;
        List<Map<String, dynamic>> hardBlocks = [];
        List<Map<String, dynamic>> warnings = [];
        String? cfError;
        bool cfStarted = false; // CF 중복 호출 방지

        return StatefulBuilder(builder: (ctx, setSheet) {
          // CF 최초 1회만 호출
          if (!cfStarted) {
            cfStarted = true;
            Future.microtask(() async {
              try {
                final callable =
                    FirebaseFunctions.instanceFor(region: 'asia-northeast3')
                        .httpsCallable('callableGetWithdrawBlockers',
                            options: HttpsCallableOptions(
                                timeout: const Duration(seconds: 20)));
                final result = await callable.call<Map<String, dynamic>>({});
                if (!ctx.mounted) return;
                setSheet(() {
                  isLoading = false;
                  hardBlocks = List<Map<String, dynamic>>.from(
                      (result.data['hardBlocks'] as List? ?? [])
                          .map((e) => Map<String, dynamic>.from(e as Map)));
                  warnings = List<Map<String, dynamic>>.from(
                      (result.data['warnings'] as List? ?? [])
                          .map((e) => Map<String, dynamic>.from(e as Map)));
                });
              } catch (_) {
                if (!ctx.mounted) return;
                setSheet(() {
                  isLoading = false;
                  cfError = '확인 중 오류가 발생했습니다. 다시 시도해 주세요.';
                });
              }
            });
          }

          // ── 로컬 헬퍼 ──────────────────────────────────────────────────
          Widget blockRow({
            required Color color,
            required Color bgColor,
            required IconData icon,
            required String label,
            required String? navKey,
          }) {
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: bgColor,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: color.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  Icon(icon, size: 16, color: color),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(label,
                        style: ResponsiveHelper.tinyStyle(ctx, color: color)
                            .copyWith(height: 1.4)),
                  ),
                  if (navKey != null)
                    TextButton(
                      onPressed: () {
                        navTarget = navKey;
                        Navigator.pop(ctx, null);
                      },
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        foregroundColor: color,
                      ),
                      child:
                          const Text('확인하기 →', style: TextStyle(fontSize: 11)),
                    ),
                ],
              ),
            );
          }

          String blockLabel(Map<String, dynamic> b) {
            final n = (b['count'] as num?)?.toInt() ?? 0;
            return switch (b['type'] as String? ?? '') {
              'UNPAID_WAGES' => '미확정/미이체 급여 $n건',
              'INTERIM_PENDING' => '중간정산 승인 대기 $n건',
              'CONFIRMED_WORKERS' => '확정 근무자 $n명이 있는 진행 중 공고',
              'UNSIGNED_CONTRACT' => '미서명 계약서 $n건',
              'SUBADMIN_MEMBERSHIP' => '서브관리자로 등록된 사업장 $n곳 — 탈퇴 전 해제 필요',
              'ACTIVE_CONTRACTS' => '고정계약 근로자 $n명 — 탈퇴 전 계약 종료 필요',
              final t => t,
            };
          }

          String warnLabel(Map<String, dynamic> w) {
            final n = (w['count'] as num?)?.toInt() ?? 0;
            return switch (w['type'] as String? ?? '') {
              'PENDING_APPLICANTS' => '대기 중 지원자 $n명 — 탈퇴 시 자동 취소',
              'ACTIVE_TOS' => '활성 공고 $n개 — 탈퇴 시 자동 마감',
              'PENDING_WAGES' => '미확정/미이체 급여 $n건 — 탈퇴 전 관리자 확인 권장',
              'CONFIRMED_WORK' => '진행 중 장기 근무 $n건 — 탈퇴 전 관리자에게 퇴사 신청 권장',
              final t => t,
            };
          }

          String? blockNavKey(Map<String, dynamic> b) =>
              switch (b['type'] as String? ?? '') {
                'UNPAID_WAGES' => 'payroll_unpaid',
                'INTERIM_PENDING' => 'payroll_interim',
                'CONFIRMED_WORKERS' => 'to_management',
                'UNSIGNED_CONTRACT' => 'my_applications',
                'SUBADMIN_MEMBERSHIP' => 'subadmin_leave',
                'ACTIVE_CONTRACTS' => 'contract_management',
                _ => null,
              };

          String? warnNavKey(Map<String, dynamic> w) =>
              switch (w['type'] as String? ?? '') {
                'PENDING_APPLICANTS' || 'ACTIVE_TOS' => 'to_management',
                _ => 'my_applications',
              };
          // ───────────────────────────────────────────────────────────────

          return Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 28),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 핸들
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: AppColors.grey300,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text('탈퇴 전 확인',
                      style: ResponsiveHelper.titleStyle(ctx)
                          .copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text('처리 필요 항목을 먼저 완료해 주세요',
                      style: ResponsiveHelper.smallStyle(ctx,
                          color: AppColors.grey500)),
                  const SizedBox(height: 20),

                  if (isLoading)
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.symmetric(vertical: 32),
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  else if (cfError != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Text(cfError!,
                          style: ResponsiveHelper.smallStyle(ctx,
                              color: AppColors.error)),
                    )
                  else ...[
                    if (hardBlocks.isNotEmpty) ...[
                      Text('처리 필요 항목',
                          style: ResponsiveHelper.smallStyle(ctx,
                              color: AppColors.errorDeep,
                              fontWeight: FontWeight.w600)),
                      const SizedBox(height: 8),
                      for (final b in hardBlocks)
                        blockRow(
                          color: AppColors.error,
                          bgColor: AppColors.errorBg,
                          icon: Icons.block_rounded,
                          label: blockLabel(b),
                          navKey: blockNavKey(b),
                        ),
                      const SizedBox(height: 12),
                    ],
                    if (warnings.isNotEmpty) ...[
                      Text('확인 권장 사항',
                          style: ResponsiveHelper.smallStyle(ctx,
                              color: const Color(0xFFB45309),
                              fontWeight: FontWeight.w600)),
                      const SizedBox(height: 8),
                      for (final w in warnings)
                        blockRow(
                          color: const Color(0xFFB45309),
                          bgColor: const Color(0xFFFFFBEB),
                          icon: Icons.warning_amber_rounded,
                          label: warnLabel(w),
                          navKey: warnNavKey(w),
                        ),
                      const SizedBox(height: 12),
                    ],
                    if (hardBlocks.isEmpty && warnings.isEmpty)
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF0FDF4),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFBBF7D0)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.check_circle_outline,
                                size: 18, color: Color(0xFF16A34A)),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text('탈퇴 가능한 상태입니다.',
                                  style: ResponsiveHelper.smallStyle(ctx,
                                      color: const Color(0xFF166534))),
                            ),
                          ],
                        ),
                      ),
                  ],

                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(ctx, null),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                          child: const Text('닫기'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: (hardBlocks.isEmpty &&
                                  !isLoading &&
                                  cfError == null)
                              ? () => Navigator.pop(ctx, true)
                              : null,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.error,
                            disabledBackgroundColor: AppColors.grey300,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                          child: Text('탈퇴 진행',
                              style: ResponsiveHelper.bodyStyle(ctx).copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600)),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        });
      },
    );

    if (!context.mounted) return;

    // 항목 네비게이션 처리 (탈퇴 flow는 종료)
    if (navTarget != null) {
      switch (navTarget) {
        case 'payroll_unpaid':
          // 미이체 탭(0) — 사업장 선택 후 당월 급여 지급현황으로 이동
          final bizUnpaid = await BusinessPickerHelper.pick(context);
          if (bizUnpaid == null || !context.mounted) return;
          final nowUnpaid = DateTime.now();
          await Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => PayrollPaymentDashboardScreen(
                        businessId: bizUnpaid.id,
                        businessName: bizUnpaid.name,
                        year: nowUnpaid.year,
                        month: nowUnpaid.month,
                        initialTab: 0,
                        showAllOutstanding: true, // [5C.2-S21] Home 드릴다운과 동일 전체기간 뷰
                      )));
        case 'payroll_interim':
          // 중간정산 탭(3) — 사업장 선택 후 당월 급여 지급현황으로 이동
          final bizInterim = await BusinessPickerHelper.pick(context);
          if (bizInterim == null || !context.mounted) return;
          final nowInterim = DateTime.now();
          await Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => PayrollPaymentDashboardScreen(
                        businessId: bizInterim.id,
                        businessName: bizInterim.name,
                        year: nowInterim.year,
                        month: nowInterim.month,
                        initialTab: 3,
                        showPendingSettlementOnly: true, // [5C.2-S21] Home 드릴다운과 동일 PENDING 필터
                      )));
        case 'to_management':
          await Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => const BusinessAdminHomeScreen()));
        case 'my_applications':
          await Navigator.push(context,
              MaterialPageRoute(builder: (_) => const MyApplicationsScreen()));
        case 'subadmin_leave':
          await Navigator.push(context,
              MaterialPageRoute(builder: (_) => const SubadminLeaveScreen()));
        case 'contract_management':
          // 고정계약 근로자 계약 관리 — 사업장 선택 후 계약 관리 화면으로 이동
          final bizContract = await BusinessPickerHelper.pick(context);
          if (bizContract == null || !context.mounted) return;
          await Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => AdminContractManagementScreen(
                        businessId: bizContract.id,
                        businessName: bizContract.name,
                      )));
      }
      return;
    }

    // 탈퇴 진행 → 비밀번호 확인 시트
    if (shouldProceed == true && context.mounted) {
      await _showDeleteAccountSheet(context, userProvider);
    }
  }

  Future<void> _showDeleteAccountSheet(
      BuildContext context, UserProvider userProvider) async {
    // [FC-SET-01 OWNERSHIP FIX] _DeleteAccountSheet(StatefulWidget)이 passwordCtrl을
    // 직접 소유하고 State.dispose()에서 해제한다.
    // ThemeProvider.reset() + signOut()은 sheet 종료 후 부모에서 처리.
    final deleted = await DialogHelper.showSheet<bool>(
      context,
      isScrollControlled: true,
      builder: (ctx) => _DeleteAccountSheet(userProvider: userProvider),
    );
    if (deleted == true) {
      if (context.mounted) context.read<ThemeProvider>().reset();
      // signOut()은 notifyListeners()로 라우팅 처리 — 이후 mounted 체크 불필요 (의도된 설계)
      await userProvider.signOut();
    }
  }

  /// 🔄 Application 마이그레이션 실행
  Future<void> _runApplicationMigration(BuildContext context) async {
    // 확인 다이얼로그
    final confirmed = await DialogHelper.showConfirm(
      context,
      title: 'Application 마이그레이션',
      message: '기존 지원서에 누락된 workDetailId, toId, groupId를 채웁니다.\n\n'
          '⚠️ 데이터가 많으면 시간이 걸릴 수 있습니다.\n'
          '계속하시겠습니까?',
      confirmText: '실행',
      cancelText: '취소',
      icon: Icons.sync,
      iconColor: AppColors.warningDark,
    );

    if (confirmed != true || !context.mounted) return;
    final rootNav = Navigator.of(context, rootNavigator: true);

    DialogHelper.showLoading(context, message: '마이그레이션 진행 중...\n잠시만 기다려주세요.');

    Map<String, dynamic>? result;
    try {
      result = await FirestoreService().migrateApplicationWorkDetailIds();
    } catch (e) {
      if (context.mounted) ToastHelper.showError('마이그레이션 오류: $e');
    } finally {
      if (rootNav.mounted && rootNav.canPop()) rootNav.pop();
    }

    if (result == null) return;

    // 결과 표시
    final migrated = result['migrated'] ?? 0;
    final skipped = result['skipped'] ?? 0;
    final failed = result['failed'] ?? 0;

    if (context.mounted) {
      if (failed == -1) {
        ToastHelper.showError('마이그레이션 실패');
      } else {
        await DialogHelper.showInfo(
          context,
          title: '마이그레이션 완료',
          message: '✅ 마이그레이션: $migrated개\n'
              '⏭️ 스킵 (이미 있음): $skipped개\n'
              '❌ 실패: $failed개',
        );
      }
    }
  }

  /// 🔄 총 근무시간(totalWorkHours) 마이그레이션 실행
  ///
  /// 원인: callableCalculateAndConfirmWage가 attendance.workHours(최상위 필드)를 쓰지 않아
  ///   onAttendanceWageStatusChanged 트리거에서 0이 누적된 사용자 복구.
  Future<void> _runWorkHoursMigration(BuildContext context) async {
    final confirmed = await DialogHelper.showConfirm(
      context,
      title: '총 근무시간 마이그레이션',
      message: '확정된 근태 기록을 기반으로 모든 사용자의\n'
          '총 근무시간(totalWorkHours)을 재계산합니다.\n\n'
          '⚠️ 기존 값을 덮어씁니다.\n'
          '계속하시겠습니까?',
      confirmText: '실행',
      cancelText: '취소',
      icon: Icons.access_time_filled,
      iconColor: AppColors.info,
    );

    if (confirmed != true || !context.mounted) return;
    final rootNav = Navigator.of(context, rootNavigator: true);

    DialogHelper.showLoading(context, message: '근무시간 재계산 중...\n잠시만 기다려주세요.');

    int? updatedUsers;
    int? scannedAttendances;
    try {
      final callable = FirebaseFunctions.instanceFor(region: 'asia-northeast3')
          .httpsCallable('callableMigrateUserWorkHours');
      final result = await callable.call<Map<String, dynamic>>();
      updatedUsers = result.data['updatedUsers'] ?? 0;
      scannedAttendances = result.data['scannedAttendances'] ?? 0;
    } catch (e) {
      if (context.mounted) ToastHelper.showError('마이그레이션 오류: $e');
    } finally {
      if (rootNav.mounted && rootNav.canPop()) rootNav.pop();
    }

    if (updatedUsers == null) return;

    if (context.mounted) {
      await DialogHelper.showInfo(
        context,
        title: '마이그레이션 완료',
        message: '✅ 업데이트된 사용자: $updatedUsers명\n'
            '📋 처리된 근태 기록: $scannedAttendances건',
      );
    }
  }

  // ── 서명 등록 카드 ────────────────────────────────────────────

  Widget _buildSignatureCard(BuildContext context, UserModel? user) {
    final theme = Theme.of(context);
    final signatureBase64 = user?.signatureBase64;
    final hasSignature = signatureBase64 != null && signatureBase64.isNotEmpty;

    // [PERF-FIX] base64 변경 시에만 재디코딩 — build마다 decode 방지
    if (hasSignature && signatureBase64 != _cachedSignatureBase64) {
      _cachedSignatureBase64 = signatureBase64;
      _cachedSignatureBytes = base64Decode(signatureBase64);
    } else if (!hasSignature) {
      _cachedSignatureBase64 = null;
      _cachedSignatureBytes = null;
    }

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
            Row(children: [
              Container(
                width: ResponsiveHelper.spacing(context, 34),
                height: ResponsiveHelper.spacing(context, 34),
                decoration: BoxDecoration(
                  color: theme.primaryColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.draw_outlined,
                    color: theme.primaryColor,
                    size: ResponsiveHelper.iconSize(context, 18)),
              ),
              SizedBox(width: ResponsiveHelper.spacing(context, 12)),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('내 서명',
                        style: ResponsiveHelper.bodyStyle(context)
                            .copyWith(fontWeight: FontWeight.w600)),
                    Text(
                      hasSignature
                          ? '등록됨 · 계약서 서명 시 자동 사용'
                          : '미등록 · 계약서 서명에 사용됩니다',
                      style: ResponsiveHelper.tinyStyle(context,
                          color: AppColors.grey500),
                    ),
                  ],
                ),
              ),
            ]),
            if (hasSignature) ...[
              SizedBox(height: ResponsiveHelper.spacing(context, 10)),
              Container(
                width: double.infinity,
                height: 58,
                decoration: BoxDecoration(
                  border: Border.all(color: AppColors.grey200),
                  borderRadius: BorderRadius.circular(8),
                  color: AppColors.grey50,
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.memory(
                    _cachedSignatureBytes!,
                    fit: BoxFit.contain,
                  ),
                ),
              ),
            ],
            SizedBox(height: ResponsiveHelper.spacing(context, 10)),
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _registerSignature(context),
                  icon: const Icon(Icons.edit_outlined, size: 14),
                  label: Text(hasSignature ? '변경' : '등록',
                      style: ResponsiveHelper.smallStyle(context)),
                  style: OutlinedButton.styleFrom(
                    padding: EdgeInsets.symmetric(
                        vertical: ResponsiveHelper.spacing(context, 8)),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ),
              if (hasSignature) ...[
                SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _deleteSignature(context),
                    icon: const Icon(Icons.delete_outline,
                        size: 14, color: AppColors.error),
                    label: Text('삭제',
                        style: ResponsiveHelper.smallStyle(context,
                            color: AppColors.error)),
                    style: OutlinedButton.styleFrom(
                      padding: EdgeInsets.symmetric(
                          vertical: ResponsiveHelper.spacing(context, 8)),
                      side: const BorderSide(color: AppColors.error),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ),
              ],
            ]),
          ],
        ),
      ),
    );
  }

  Future<void> _registerSignature(BuildContext context) async {
    final userProvider = context.read<UserProvider>();
    final uid = userProvider.currentUser?.uid;
    final bytes = await showSignaturePad(context, title: '내 서명 등록');
    if (bytes == null || !mounted) return;
    if (uid == null) return;

    try {
      // [SEC-SS01] 서명 이미지 크기 제한 — Firestore 문서 1MB 한계 방어
      if (bytes.length > 500000) {
        if (mounted) ToastHelper.showError('서명 이미지가 너무 큽니다. 더 작게 그려주세요.');
        return;
      }
      final b64 = base64Encode(bytes);
      await FirebaseFunctions.instanceFor(region: 'asia-northeast3')
          .httpsCallable('callableSaveUserSignature')
          .call({'signatureBase64': b64});
      await userProvider.refreshUserData();
      if (mounted) ToastHelper.showSuccess('서명이 등록되었습니다');
    } catch (e) {
      if (mounted) ToastHelper.showError('서명 등록에 실패했습니다');
    }
  }

  Future<void> _deleteSignature(BuildContext context) async {
    final userProvider = context.read<UserProvider>();
    final uid = userProvider.currentUser?.uid;
    final confirm = await DialogHelper.showConfirm(
      context,
      title: '서명 삭제',
      message: '등록된 서명을 삭제하시겠습니까?',
      confirmText: '삭제',
      confirmColor: AppColors.error,
    );
    if (confirm != true || !mounted) return;
    if (uid == null) return;

    try {
      await FirebaseFunctions.instanceFor(region: 'asia-northeast3')
          .httpsCallable('callableSaveUserSignature')
          .call({'signatureBase64': null});
      await userProvider.refreshUserData();
      if (mounted) ToastHelper.showSuccess('서명이 삭제되었습니다');
    } catch (e) {
      if (mounted) ToastHelper.showError('서명 삭제에 실패했습니다');
    }
  }

  // ── 사업자 날인 등록 카드 (도장 이미지 / 직접 서명 선택) ────────────────

  Widget _buildSealCard(BuildContext context, UserModel? user) {
    // 사업장 조회 중
    if (_isSealLoading) {
      return Container(
        decoration: CommonWidgets.compactCardDecoration(),
        padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 20)),
        child: Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Theme.of(context).primaryColor,
            ),
          ),
        ),
      );
    }

    // 사업장 미등록 — 먼저 사업장 등록 안내
    if (_resolvedBusinessId == null) {
      return Container(
        decoration: CommonWidgets.compactCardDecoration(),
        padding: EdgeInsets.symmetric(
          horizontal: ResponsiveHelper.spacing(context, 16),
          vertical: ResponsiveHelper.spacing(context, 14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: ResponsiveHelper.spacing(context, 34),
                  height: ResponsiveHelper.spacing(context, 34),
                  decoration: BoxDecoration(
                    color: AppColors.grey200,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(Icons.verified_outlined,
                      color: AppColors.grey400,
                      size: ResponsiveHelper.iconSize(context, 18)),
                ),
                SizedBox(width: ResponsiveHelper.spacing(context, 12)),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('사업주 날인',
                          style: ResponsiveHelper.bodyStyle(context).copyWith(
                              fontWeight: FontWeight.w600,
                              color: AppColors.grey500)),
                      SizedBox(height: ResponsiveHelper.spacing(context, 2)),
                      Text('사업장 등록 후 설정 가능합니다',
                          style: ResponsiveHelper.tinyStyle(context,
                              color: AppColors.grey400)),
                    ],
                  ),
                ),
              ],
            ),
            SizedBox(height: ResponsiveHelper.spacing(context, 10)),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () async {
                  await NavigationHelper.push<void>(
                    context,
                    destination: const BusinessListScreen(),
                  );
                  if (!mounted) return;
                  // 사업장 등록 후 돌아오면 날인 정보 새로고침
                  setState(() => _isSealLoading = true);
                  await _loadBusinessSeal();
                },
                icon: Icon(Icons.add_business_outlined,
                    size: ResponsiveHelper.iconSize(context, 14)),
                label: Text('사업장 등록하기',
                    style: ResponsiveHelper.smallStyle(context,
                        color: Theme.of(context).primaryColor,
                        fontWeight: FontWeight.w600)),
                style: OutlinedButton.styleFrom(
                  padding: EdgeInsets.symmetric(
                      vertical: ResponsiveHelper.spacing(context, 8)),
                  side: BorderSide(color: Theme.of(context).primaryColor),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ),
          ],
        ),
      );
    }

    final hasSeal =
        _businessSealBase64 != null && _businessSealBase64!.isNotEmpty;
    final isStamp = _sealType == 'stamp';

    // [PERF-FIX] base64 변경 시에만 재디코딩 — build마다 decode 방지
    if (hasSeal && _businessSealBase64 != _cachedSealBase64) {
      _cachedSealBase64 = _businessSealBase64;
      _cachedSealBytes = base64Decode(_businessSealBase64!);
    } else if (!hasSeal) {
      _cachedSealBase64 = null;
      _cachedSealBytes = null;
    }

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
            // 헤더
            Row(children: [
              Container(
                width: ResponsiveHelper.spacing(context, 34),
                height: ResponsiveHelper.spacing(context, 34),
                decoration: BoxDecoration(
                  color: AppColors.warningDark.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.verified_outlined,
                    color: AppColors.warningDark,
                    size: ResponsiveHelper.iconSize(context, 18)),
              ),
              SizedBox(width: ResponsiveHelper.spacing(context, 12)),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('인감/서명',
                        style: ResponsiveHelper.bodyStyle(context)
                            .copyWith(fontWeight: FontWeight.w600)),
                    Text(
                      hasSeal
                          ? '등록됨 · 계약서 서명 시 자동 사용'
                          : '미등록 · 계약서 사업주란에 사용됩니다',
                      style: ResponsiveHelper.tinyStyle(context,
                          color: AppColors.grey500),
                    ),
                  ],
                ),
              ),
            ]),

            SizedBox(height: ResponsiveHelper.spacing(context, 12)),

            // 도장/서명 방식 선택 탭
            Container(
              decoration: BoxDecoration(
                color: AppColors.grey100,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(children: [
                _SealTypeTab(
                  label: '도장 이미지',
                  icon: Icons.image_outlined,
                  selected: isStamp,
                  onTap: () {
                    if (!isStamp) setState(() => _sealType = 'stamp');
                  },
                ),
                _SealTypeTab(
                  label: '직접 서명',
                  icon: Icons.draw_outlined,
                  selected: !isStamp,
                  onTap: () {
                    if (isStamp) setState(() => _sealType = 'signature');
                  },
                ),
              ]),
            ),

            // 등록된 이미지 미리보기
            if (hasSeal) ...[
              SizedBox(height: ResponsiveHelper.spacing(context, 10)),
              Container(
                width: double.infinity,
                height: 70,
                decoration: BoxDecoration(
                  border: Border.all(color: AppColors.grey200),
                  borderRadius: BorderRadius.circular(8),
                  color: AppColors.grey50,
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.memory(
                    _cachedSealBytes!,
                    fit: BoxFit.contain,
                  ),
                ),
              ),
            ],

            SizedBox(height: ResponsiveHelper.spacing(context, 10)),

            // 등록/변경/삭제 버튼
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: isStamp
                      ? () => _registerSeal(context, user)
                      : () => _registerBusinessSignature(context, user),
                  icon: Icon(
                    isStamp ? Icons.upload_outlined : Icons.draw_outlined,
                    size: 14,
                  ),
                  label: Text(hasSeal ? '변경' : '등록',
                      style: ResponsiveHelper.smallStyle(context)),
                  style: OutlinedButton.styleFrom(
                    padding: EdgeInsets.symmetric(
                        vertical: ResponsiveHelper.spacing(context, 8)),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ),
              if (hasSeal) ...[
                SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _deleteSeal(context, user),
                    icon: const Icon(Icons.delete_outline,
                        size: 14, color: AppColors.error),
                    label: Text('삭제',
                        style: ResponsiveHelper.smallStyle(context,
                            color: AppColors.error)),
                    style: OutlinedButton.styleFrom(
                      padding: EdgeInsets.symmetric(
                          vertical: ResponsiveHelper.spacing(context, 8)),
                      side: const BorderSide(color: AppColors.error),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ),
              ],
            ]),
          ],
        ),
      ),
    );
  }

  Future<void> _callSaveSeal(String? b64, String sealType) async {
    await FirebaseFunctions.instanceFor(region: 'asia-northeast3')
        .httpsCallable('callableSaveSeal')
        .call({'sealBase64': b64, 'sealType': sealType});
  }

  Future<void> _registerSeal(BuildContext context, UserModel? user) async {
    if (user == null) return;

    final userProvider = context.read<UserProvider>();
    final source = await ImageHelper.showImageSourceBottomSheet(context);
    if (source == null || !mounted) return;

    final picked = await ImagePicker().pickImage(
      source: source,
      imageQuality: 80,
      maxWidth: 600,
    );
    if (picked == null || !mounted) return;

    try {
      final bytes = await picked.readAsBytes();
      if (bytes.length > 500000) {
        if (mounted) ToastHelper.showError('이미지가 너무 큽니다. 더 작은 이미지를 선택해 주세요.');
        return;
      }
      final b64 = base64Encode(bytes);
      await _callSaveSeal(b64, 'stamp');
      await userProvider.refreshUserData();
      if (!mounted) return;
      setState(() {
        _businessSealBase64 = b64;
        _sealType = 'stamp';
      });
      ToastHelper.showSuccess('도장이 등록되었습니다');
    } catch (e) {
      if (mounted) ToastHelper.showError('도장 등록에 실패했습니다');
    }
  }

  Future<void> _registerBusinessSignature(
      BuildContext context, UserModel? user) async {
    if (user == null) return;

    final userProvider = context.read<UserProvider>();
    final bytes = await showSignaturePad(context, title: '사업주 서명');
    if (bytes == null || !mounted) return;

    try {
      if (bytes.length > 500000) {
        if (mounted) ToastHelper.showError('서명 이미지가 너무 큽니다. 더 작게 그려주세요.');
        return;
      }
      final b64 = base64Encode(bytes);
      await _callSaveSeal(b64, 'signature');
      await userProvider.refreshUserData();
      if (!mounted) return;
      setState(() {
        _businessSealBase64 = b64;
        _sealType = 'signature';
      });
      ToastHelper.showSuccess('서명이 등록되었습니다');
    } catch (e) {
      if (mounted) ToastHelper.showError('서명 등록에 실패했습니다');
    }
  }

  Future<void> _deleteSeal(BuildContext context, UserModel? user) async {
    if (user == null) return;

    final userProvider = context.read<UserProvider>();
    final confirm = await DialogHelper.showConfirm(
      context,
      title: '날인 삭제',
      message: '등록된 날인을 삭제하시겠습니까?',
      confirmText: '삭제',
      confirmColor: AppColors.error,
    );
    if (confirm != true || !mounted) return;

    try {
      await _callSaveSeal(null, 'stamp');
      await userProvider.refreshUserData();
      if (!mounted) return;
      setState(() {
        _businessSealBase64 = null;
        _sealType = 'stamp';
      });
      ToastHelper.showSuccess('날인이 삭제되었습니다');
    } catch (e) {
      if (mounted) ToastHelper.showError('날인 삭제에 실패했습니다');
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// FC-SET-01 OWNERSHIP FIX: _DeleteAccountSheet
// passwordCtrl을 BottomSheet State가 직접 소유하고 dispose().
// ThemeProvider.reset() + signOut()은 sheet 종료 후 부모(_showDeleteAccountSheet)가 처리.
// ─────────────────────────────────────────────────────────────────────────────

class _DeleteAccountSheet extends StatefulWidget {
  final UserProvider userProvider;
  const _DeleteAccountSheet({required this.userProvider});

  @override
  State<_DeleteAccountSheet> createState() => _DeleteAccountSheetState();
}

class _DeleteAccountSheetState extends State<_DeleteAccountSheet> {
  final _passwordCtrl = TextEditingController();
  bool _obscure = true;
  bool _isLoading = false;
  String? _errorMsg;

  @override
  void dispose() {
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _doDelete() async {
    FocusManager.instance.primaryFocus?.unfocus();
    final pw = _passwordCtrl.text.trim();
    if (pw.isEmpty) {
      setState(() => _errorMsg = '비밀번호를 입력해주세요');
      return;
    }

    if (!mounted) return;
    final confirmed = await DialogHelper.showDangerConfirm(
      context,
      title: '정말 탈퇴하시겠습니까?',
      message: '탈퇴 후 계정 및 모든 데이터가 삭제되며 복구할 수 없습니다.',
      confirmText: '탈퇴하기',
    );
    if (confirmed != true || !mounted) return;

    setState(() {
      _isLoading = true;
      _errorMsg = null;
    });

    final authService = AuthService();
    final err = await authService.deleteAccountWithPassword(pw);

    if (!mounted) return;

    if (err != null) {
      setState(() {
        _isLoading = false;
        _errorMsg = err;
      });
    } else {
      // 탈퇴 성공 → sheet 닫기 (true 반환)
      // ThemeProvider.reset() + signOut()은 부모(_showDeleteAccountSheet)가 처리
      Navigator.pop(context, true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(
        24,
        16,
        24,
        MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 핸들 바
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.grey300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),

            // 제목
            Text(
              '회원탈퇴',
              style: ResponsiveHelper.titleStyle(context)
                  .copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(
              '탈퇴 후 계정 복구는 불가능합니다',
              style: ResponsiveHelper.smallStyle(context, color: AppColors.grey500),
            ),
            const SizedBox(height: 16),

            // 통합 안내 박스
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.errorBg,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.errorLight),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '탈퇴 시 아래 사항을 확인해주세요',
                    style: ResponsiveHelper.smallStyle(context,
                        color: AppColors.errorDeep,
                        fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 10),
                  for (final text in <String>[
                    '프로필 및 개인정보 즉시 삭제',
                    '업로드한 서류 삭제 (신분증, 통장사본 등)',
                    '진행 중인 지원·공고 자동 취소',
                    '탈퇴 후 30일간 재가입 제한',
                  ])
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('• ',
                              style: ResponsiveHelper.tinyStyle(context,
                                  color: AppColors.errorDeep)),
                          Expanded(
                            child: Text(text,
                                style: ResponsiveHelper.tinyStyle(context,
                                        color: AppColors.errorDeep)
                                    .copyWith(height: 1.4)),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // 비밀번호 입력
            Text(
              '비밀번호 확인',
              style: ResponsiveHelper.bodyStyle(context)
                  .copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _passwordCtrl,
              obscureText: _obscure,
              decoration: InputDecoration(
                hintText: '현재 비밀번호 입력',
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12)),
                errorText: _errorMsg,
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscure ? Icons.visibility_off : Icons.visibility,
                    size: 20,
                  ),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
              onSubmitted: (_) => _doDelete(),
            ),
            const SizedBox(height: 20),

            // 버튼
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _isLoading ? null : () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('취소'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _doDelete,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.error,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : Text(
                            '탈퇴하기',
                            style: ResponsiveHelper.bodyStyle(context).copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w600),
                          ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

// ── 설정 메뉴 그룹용 데이터 클래스 ─────────────────────────────────
class _SettingsItem {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String? subtitle;
  final Color? subtitleColor;
  final VoidCallback onTap;

  const _SettingsItem({
    required this.icon,
    required this.iconColor,
    required this.title,
    this.subtitle,
    this.subtitleColor,
    required this.onTap,
  });
}

// ── 약관 읽기 전용 뷰어 ──────────────────────────────────────────────
// [LEGAL-FIX 2026-08-10] 개인정보보호법 제35조 열람 요구권 대응
// 동의 버튼 없이 읽기만 가능 (register_screen의 _TermsViewerScreen과 달리)
class _TermsReadOnlyScreen extends StatelessWidget {
  final String title;
  final String content;
  final String? version;

  const _TermsReadOnlyScreen({
    required this.title,
    required this.content,
    this.version,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close),
          color: AppColors.grey700,
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          title,
          style: ResponsiveHelper.bodyStyle(context,
              color: AppColors.grey900, fontWeight: FontWeight.w600),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            if (version != null)
              Container(
                width: double.infinity,
                color: AppColors.grey100,
                padding: EdgeInsets.symmetric(
                  horizontal: ResponsiveHelper.spacing(context, 16),
                  vertical: ResponsiveHelper.spacing(context, 8),
                ),
                child: Text(
                  '버전 $version',
                  style: ResponsiveHelper.smallStyle(context,
                      color: AppColors.grey500),
                ),
              ),
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 20)),
                child: SelectableText(
                  content,
                  style: ResponsiveHelper.bodyStyle(context,
                      color: AppColors.grey800),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── 날인 방식 선택 탭 버튼 ──────────────────────────────────────────
class _SealTypeTab extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _SealTypeTab({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          margin: const EdgeInsets.all(3),
          padding: EdgeInsets.symmetric(
            vertical: ResponsiveHelper.spacing(context, 8),
          ),
          decoration: BoxDecoration(
            color: selected ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.06),
                      blurRadius: 4,
                      offset: const Offset(0, 1),
                    )
                  ]
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: ResponsiveHelper.iconSize(context, 14),
                color: selected ? AppColors.warningDark : AppColors.grey500,
              ),
              SizedBox(width: ResponsiveHelper.spacing(context, 4)),
              Text(
                label,
                style: ResponsiveHelper.smallStyle(
                  context,
                  color: selected ? AppColors.warningDark : AppColors.grey500,
                ).copyWith(
                  fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
