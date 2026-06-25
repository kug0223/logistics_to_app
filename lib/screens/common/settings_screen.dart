import 'dart:convert';

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:package_info_plus/package_info_plus.dart';

// Models
import '../../models/core/user_model.dart';
import '../../models/core/to_model.dart';

// Providers
import '../../providers/user_provider.dart';
import '../../providers/theme_provider.dart';

// Utils
import '../../utils/responsive_helper.dart';
import '../../utils/navigation_helper.dart';

// Widgets
import '../../widgets/common/common_widgets.dart';
import '../../widgets/contract/signature_pad_widget.dart';
import '../../widgets/dialogs/restart_program_dialog.dart';
import '../../widgets/dialogs/trust_score_info_dialog.dart';

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
import '../super_admin/all_businesses_screen.dart';
import '../super_admin/all_users_screen.dart';
import '../super_admin/legal_terms_management_screen.dart';

// Tour
import '../../utils/tour_helper.dart';
import 'tour_screen.dart';

// Services
import '../../services/auth_service.dart';
import '../../services/firestore_service.dart';
import '../../services/pass_verification_service.dart';
import '../../utils/encryption_helper.dart';
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
  String _appVersion = '';
  String? _businessSealBase64;
  String _sealType = 'stamp';
  String? _resolvedBusinessId;
  bool _isSealLoading = true;

  @override
  void initState() {
    super.initState();
    _loadNotificationStatus();
    _loadAppVersion();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadBusinessSeal());
  }

  Future<void> _loadBusinessSeal() async {
    final user = context.read<UserProvider>().currentUser;

    // BUSINESS_ADMIN이 아니면 즉시 로딩 해제
    if (user == null || user.role != UserRole.BUSINESS_ADMIN) {
      if (mounted) setState(() => _isSealLoading = false);
      return;
    }

    // 날인 + 사업장 ID 즉시 표시 (비동기 쿼리 전, 블로킹 없음)
    if (!mounted) return;
    setState(() {
      _businessSealBase64 = user.sealBase64;
      _sealType = user.sealType;
      _resolvedBusinessId = user.businessId; // 모델에서 즉시 세팅
      _isSealLoading = false;
    });

    // user.businessId가 없을 때만 Firestore 조회 (내비게이션용, UI 블로킹 없음)
    if (_resolvedBusinessId == null) {
      try {
        final snap = await FirebaseFirestore.instance
            .collection('businesses')
            .where('adminIds', arrayContains: user.uid)
            .limit(1)
            .get();
        if (snap.docs.isNotEmpty && mounted) {
          setState(() => _resolvedBusinessId = snap.docs.first.id);
        }
      } catch (e) {
        debugPrint('⚠️ adminIds로 사업장 조회 실패: $e');
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
      setState(() => _isLoading = false);
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
    setState(() => _isLoading = true);

    try {
      final userProvider = context.read<UserProvider>();
      final userId = userProvider.currentUser?.uid;

      if (userId == null) {
        if (mounted) setState(() => _isLoading = false);
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
          if (mounted) setState(() => _isLoading = false);
          return;
        }
        await FCMService().initialize(userId, isAdmin: userProvider.isAdmin);
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
      debugPrint('❌ 알림 설정 변경 실패: $e');
      if (mounted) ToastHelper.showError('알림 설정 변경에 실패했습니다');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final userProvider = context.watch<UserProvider>();
    final user = userProvider.currentUser;
    final theme = Theme.of(context);

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
              onTap: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const ProfileEditScreen())),
            ),
          ]),
          if (user?.role == UserRole.USER) ...[
            SizedBox(height: ResponsiveHelper.spacing(context, 8)),
            _buildMenuGroup(context, [
              _SettingsItem(
                icon: Icons.verified_user_outlined,
                iconColor: AppColors.infoDark,
                title: '본인인증 (PASS)',
                subtitle: (user?.isPassVerified ?? false) ? '완료' : '미완료',
                onTap: () => _handlePassAuth(user!),
              ),
              _SettingsItem(
                icon: Icons.folder_special_outlined,
                iconColor: AppColors.successDark,
                title: '내 서류 관리',
                onTap: () => NavigationHelper.push<bool>(context,
                    destination: const DocumentManagementScreen()),
              ),
              _SettingsItem(
                icon: Icons.star_rounded,
                iconColor: AppColors.warning,
                title: '내 평가 확인',
                onTap: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const MyReviewsScreen())),
              ),
            ]),
            SizedBox(height: ResponsiveHelper.spacing(context, 8)),
            _buildSignatureCard(context, user),
          ],

          SizedBox(height: ResponsiveHelper.spacing(context, 20)),

          // ── 사업장 설정 (관리자) ─────────────────────────────
          if (user?.role == UserRole.BUSINESS_ADMIN) ...[
            _buildSectionHeader(context, '사업장 설정', Icons.business_outlined),
            SizedBox(height: ResponsiveHelper.spacing(context, 8)),
            _buildMenuGroup(context, [
              _SettingsItem(
                icon: Icons.description_outlined,
                iconColor: AppColors.successDark,
                title: '내 서류 관리',
                onTap: () => NavigationHelper.push<bool>(context,
                    destination: const DocumentManagementScreen()),
              ),
            ]),
            SizedBox(height: ResponsiveHelper.spacing(context, 8)),
            _buildSealCard(context, user),
            SizedBox(height: ResponsiveHelper.spacing(context, 8)),
            _buildMenuGroup(context, [
              _SettingsItem(
                icon: Icons.business_outlined,
                iconColor: AppColors.purpleDark,
                title: '사업장 정보',
                onTap: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const BusinessListScreen())),
              ),
              _SettingsItem(
                icon: Icons.work_outline,
                iconColor: AppColors.warningDark,
                title: '업무 유형 관리',
                onTap: () async {
                  final nav = Navigator.of(context);
                  final biz = await BusinessPickerHelper.pick(context);
                  if (biz == null || !mounted) return;
                  nav.push(MaterialPageRoute(
                      builder: (_) => WorkTypeManagementScreen(
                          businessId: biz.id, businessName: biz.name)));
                },
              ),
              _SettingsItem(
                icon: Icons.article_outlined,
                iconColor: AppColors.infoDark,
                title: '근로계약서 관리',
                onTap: () {
                  final businessId = user?.businessId ?? _resolvedBusinessId;
                  if (businessId == null) {
                    ToastHelper.showWarning('사업장 정보를 먼저 등록해주세요');
                    return;
                  }
                  debugPrint('📋 [settings/contractTemplate] businessId=$businessId');
                  Navigator.push(context, MaterialPageRoute(
                      builder: (_) => ContractTemplateListScreen(businessId: businessId)));
                },
              ),
              if (!(user?.isSubAdmin ?? false))
                _SettingsItem(
                  icon: Icons.group_outlined,
                  iconColor: theme.primaryColor,
                  title: '멤버 관리',
                  onTap: () async {
                    final nav = Navigator.of(context);
                    final biz = await BusinessPickerHelper.pick(context);
                    if (biz == null || !mounted) return;
                    nav.push(MaterialPageRoute(
                        builder: (_) => MemberManagementScreen(
                            businessId: biz.id, businessName: biz.name)));
                  },
                ),
              _SettingsItem(
                icon: Icons.rate_review_outlined,
                iconColor: AppColors.warningDark,
                title: '리뷰 관리',
                onTap: () async {
                  final nav = Navigator.of(context);
                  final biz = await BusinessPickerHelper.pick(context);
                  if (biz == null || !mounted) return;
                  nav.push(MaterialPageRoute(
                      builder: (_) => AdminReviewListScreen(businessId: biz.id)));
                },
              ),
            ]),
            SizedBox(height: ResponsiveHelper.spacing(context, 20)),
          ],

          // ── 관리자 메뉴 (슈퍼) ──────────────────────────────
          if (user?.role == UserRole.SUPER_ADMIN) ...[
            _buildSectionHeader(context, '관리자 메뉴', Icons.admin_panel_settings_outlined),
            SizedBox(height: ResponsiveHelper.spacing(context, 8)),
            _buildMenuGroup(context, [
              _SettingsItem(
                icon: Icons.people_outline,
                iconColor: AppColors.errorDark,
                title: '전체 사용자 관리',
                onTap: () => NavigationHelper.push(context, destination: const AllUsersScreen()),
              ),
              _SettingsItem(
                icon: Icons.business_center_outlined,
                iconColor: AppColors.purpleDark,
                title: '전체 사업장 관리',
                onTap: () => NavigationHelper.push(context, destination: const AllBusinessesScreen()),
              ),
              _SettingsItem(
                icon: Icons.gavel_outlined,
                iconColor: AppColors.infoDark,
                title: '약관 관리',
                onTap: () => Navigator.push(context, MaterialPageRoute(
                    builder: (_) => const LegalTermsManagementScreen())),
              ),
            ]),
            SizedBox(height: ResponsiveHelper.spacing(context, 20)),
            _buildSectionHeader(context, '개발자 도구', Icons.developer_mode_outlined),
            SizedBox(height: ResponsiveHelper.spacing(context, 8)),
            _buildMenuGroup(context, [
              _SettingsItem(
                icon: Icons.sync,
                iconColor: AppColors.warningDark,
                title: 'Application 마이그레이션',
                onTap: () => _runApplicationMigration(context),
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
            _buildNotifPrefsCard(context),
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
                final role = context.read<UserProvider>().currentUser?.role.name ?? 'USER';
                await TourHelper.resetAll();
                if (!mounted) return;
                // ignore: use_build_context_synchronously
                await pushTourScreen(context, role: role);
              },
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
  }
  
  

  /// ✨ 세련된 프로필 카드
  /// 파란 헤더 — 가로 compact 프로필 (공간 최소화)
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
              Container(
                width: ResponsiveHelper.spacing(context, 52),
                height: ResponsiveHelper.spacing(context, 52),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.person,
                  size: ResponsiveHelper.iconSize(context, 30),
                  color: Colors.white,
                ),
              ),
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

          // ── 지원자 신뢰도 + 통계 (한 줄 compact)
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
                  // 신뢰도
                  Text(user.trustGradeEmoji,
                      style: ResponsiveHelper.bodyStyle(context)),
                  SizedBox(width: ResponsiveHelper.spacing(context, 4)),
                  Text(
                    '신뢰도 ${user.trustScore}점',
                    style: ResponsiveHelper.smallStyle(context,
                        color: Colors.white, fontWeight: FontWeight.w600),
                  ),
                  SizedBox(width: ResponsiveHelper.spacing(context, 4)),
                  Container(
                    padding: EdgeInsets.symmetric(
                        horizontal: ResponsiveHelper.spacing(context, 6),
                        vertical: 1),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(user.trustGrade,
                        style: ResponsiveHelper.tinyStyle(context,
                            color: Colors.white,
                            fontWeight: FontWeight.w600)),
                  ),
                  GestureDetector(
                    onTap: () => TrustScoreInfoDialog.show(context),
                    child: Padding(
                      padding: EdgeInsets.only(
                          left: ResponsiveHelper.spacing(context, 4)),
                      child: Icon(Icons.help_outline,
                          size: ResponsiveHelper.iconSize(context, 14),
                          color: Colors.white.withValues(alpha: 0.7)),
                    ),
                  ),
                  const Spacer(),
                  // 통계 4개 inline
                  _miniStat(context, '근무', '${user.totalWorkDays}일'),
                  _miniStat(context, '평점',
                      user.averageRating.toStringAsFixed(1)),
                  _miniStat(context, '지각', '${user.lateCount}회'),
                  _miniStat(context, '노쇼', '${user.noShowCount}회'),
                ],
              ),
            ),

            // 재시작 프로그램 (신뢰도 50 미만만, 작게)
            if (user.trustScore < 50) ...[
              SizedBox(height: ResponsiveHelper.spacing(context, 8)),
              GestureDetector(
                onTap: () => _showRestartProgramDialog(context, user),
                child: Container(
                  width: double.infinity,
                  padding: EdgeInsets.symmetric(
                      vertical: ResponsiveHelper.spacing(context, 8)),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: Colors.white.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.refresh,
                          size: ResponsiveHelper.iconSize(context, 14),
                          color: Colors.white),
                      SizedBox(width: ResponsiveHelper.spacing(context, 6)),
                      Text('재시작 프로그램 신청',
                          style: ResponsiveHelper.tinyStyle(context,
                              color: Colors.white,
                              fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
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

 /// 🆕 재시작 프로그램 다이얼로그 표시
  Future<void> _showRestartProgramDialog(BuildContext context, UserModel user) async {
    await showRestartProgramDialog(
      context,
      userId: user.uid,
      currentScore: user.trustScore,
      noShowCount: user.noShowCount,
      lateCount: user.lateCount,
      onSuccess: () {
        // 사용자 정보 새로고침
        context.read<UserProvider>().refreshUserData();
      },
    );
    
    // refreshUserData() 호출 후 UserProvider가 notifyListeners() → 자동 rebuild
    // (context.watch 사용 화면이므로 별도 setState 불필요)
  }


  // ── PASS 본인인증 ─────────────────────────────────────────────────

  // [TODO-DANAL] kDebugMode 블록은 다날 연동 후 제거
  Future<void> _handlePassAuth(UserModel user) async {
    PassAuthResult? result;

    if (kDebugMode) {
      result = await _showPassMockDialog();
    } else {
      result = await PassVerificationService.authenticate(purpose: 'reauth');
    }

    if (!mounted || result == null) return;

    try {
      await FirestoreService().updateUserDocument(user.uid, {
        'ci': EncryptionHelper.encrypt(result.passToken),
        'passVerifiedAt': Timestamp.fromDate(DateTime.now()),
      });
      if (!mounted) return;
      await context.read<UserProvider>().refreshCurrentUser();
      if (!mounted) return;
      ToastHelper.showSuccess('본인인증이 완료되었습니다.');
    } catch (e) {
      if (!mounted) return;
      ToastHelper.showError('본인인증 처리에 실패했습니다. 다시 시도해주세요.');
    }
  }

  // [TODO-DANAL] 다날 연동 후 이 메서드 전체 삭제
  Future<PassAuthResult?> _showPassMockDialog() async {
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: AppColors.infoBg,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.developer_mode, color: AppColors.info, size: 18),
            ),
            const SizedBox(width: 10),
            Text('[개발] PASS 인증', style: ResponsiveHelper.subtitleStyle(ctx)),
          ],
        ),
        content: Text(
          '테스트 방식을 선택하세요.',
          style: ResponsiveHelper.bodyStyle(ctx, color: AppColors.grey600),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        actions: [
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(ctx),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.grey600,
                    side: const BorderSide(color: AppColors.grey300),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: const Text('취소'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(ctx, 'random'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.info,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: const Text('랜덤 생성'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
    if (!mounted || choice == null) return null;
    return PassVerificationService.authenticate(purpose: 'reauth');
  }

  Widget _buildSectionHeader(BuildContext context, String title, IconData icon) {
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
                            color: AppColors.grey500)),
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
            if (!isLast)
              const Divider(height: 1, indent: 52, thickness: 0.5),
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
                color: iconColor,
                size: ResponsiveHelper.iconSize(context, 18)),
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

  Widget _buildNotifPrefsCard(BuildContext context) {
    final theme = Theme.of(context);
    final role = context.read<UserProvider>().currentUser?.role;
    final isAdmin = role == UserRole.BUSINESS_ADMIN || role == UserRole.SUPER_ADMIN;

    // 역할에 맞는 알림 항목만 표시
    // 근무 리마인더·지원 결과는 근무자 전용, 나머지는 공통
    final items = isAdmin
        ? [
            (UserModel.notifReviewAlert,   '리뷰 요청 알림',  Icons.rate_review_outlined),
            (UserModel.notifContractAlert, '계약 알림',       Icons.description_outlined),
            (UserModel.notifWageAlert,     '임금 확정 알림',  Icons.payments_outlined),
          ]
        : [
            (UserModel.notifWorkReminder,      '근무 리마인더',   Icons.schedule_outlined),
            (UserModel.notifApplicationUpdate, '지원 결과 알림',  Icons.check_circle_outline),
            (UserModel.notifReviewAlert,       '리뷰 요청 알림',  Icons.rate_review_outlined),
            (UserModel.notifContractAlert,     '계약 알림',       Icons.description_outlined),
            (UserModel.notifWageAlert,         '임금 확정 알림',  Icons.payments_outlined),
          ];
    return Container(
      decoration: CommonWidgets.compactCardDecoration(),
      child: Column(
        children: items.asMap().entries.map((entry) {
          final i = entry.key;
          final (key, label, icon) = entry.value;
          final enabled = _notifPrefs[key] ?? true;
          return Column(
            children: [
              Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: ResponsiveHelper.spacing(context, 16),
                  vertical: ResponsiveHelper.spacing(context, 10),
                ),
                child: Row(children: [
                  Icon(icon,
                      size: ResponsiveHelper.iconSize(context, 18),
                      color: enabled ? theme.primaryColor : AppColors.grey400),
                  SizedBox(width: ResponsiveHelper.spacing(context, 12)),
                  Expanded(
                    child: Text(label,
                        style: ResponsiveHelper.bodyStyle(context).copyWith(
                          color: enabled ? null : AppColors.grey400,
                        )),
                  ),
                  Switch(
                    value: enabled,
                    onChanged: _isNotifPrefsLoading
                        ? null
                        : (v) => _toggleNotifPref(key, v),
                    activeThumbColor: theme.primaryColor,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ]),
              ),
              if (i < items.length - 1)
                const Divider(height: 1, indent: 46, color: AppColors.grey100),
            ],
          );
        }).toList(),
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
                    color: AppColors.error,
                    size: ResponsiveHelper.iconSize(context, 18)),
                SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                Text('로그아웃',
                    style: ResponsiveHelper.bodyStyle(context).copyWith(
                        color: AppColors.error, fontWeight: FontWeight.w600)),
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
      onPressed: () => _showDeleteAccountSheet(context, userProvider),
      child: Text(
        '회원탈퇴',
        style: ResponsiveHelper.smallStyle(context,
            color: AppColors.grey400).copyWith(
          decoration: TextDecoration.underline,
          decorationColor: AppColors.grey400,
        ),
      ),
    );
  }

  Future<void> _showDeleteAccountSheet(
      BuildContext context, UserProvider userProvider) async {
    final passwordCtrl = TextEditingController();
    bool obscure = true;
    bool isLoading = false;
    String? errorMsg;

    await showModalBottomSheet(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModal) {
          Future<void> doDelete() async {
            final pw = passwordCtrl.text.trim();
            if (pw.isEmpty) {
              setModal(() => errorMsg = '비밀번호를 입력해주세요');
              return;
            }

            // BUSINESS_ADMIN: 활성 TO/계약 사전 확인
            final currentUser = userProvider.currentUser;
            final currentBusinessId = currentUser?.businessId;
            if (currentUser?.isBusinessAdmin == true &&
                currentBusinessId != null) {
              setModal(() { isLoading = true; errorMsg = null; });
              final activeToSnap = await FirebaseFirestore.instance
                  .collection('tos')
                  .where('businessId', isEqualTo: currentBusinessId)
                  .where('status', whereIn: [
                    TOStatus.active, TOStatus.full, TOStatus.scheduled
                  ])
                  .limit(1)
                  .get();
              setModal(() => isLoading = false);
              if (!ctx.mounted) return;

              if (activeToSnap.docs.isNotEmpty) {
                final proceed = await showDialog<bool>(
                  context: ctx,
                  builder: (dCtx) => AlertDialog(
                    title: const Text('활성 공고 있음'),
                    content: const Text(
                      '현재 활성 공고가 있습니다.\n탈퇴하면 공고·계약·근무자 데이터가 모두 삭제됩니다.\n계속하시겠습니까?',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(dCtx, false),
                        child: const Text('취소'),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(dCtx, true),
                        style: TextButton.styleFrom(foregroundColor: AppColors.error),
                        child: const Text('탈퇴 진행'),
                      ),
                    ],
                  ),
                );
                if (proceed != true || !ctx.mounted) return;
              }
            }

            setModal(() {
              isLoading = true;
              errorMsg = null;
            });

            final authService = AuthService();
            final err = await authService.deleteAccountWithPassword(pw);

            if (!ctx.mounted) return;

            if (err != null) {
              setModal(() {
                isLoading = false;
                errorMsg = err;
              });
            } else {
              Navigator.pop(ctx);
              if (context.mounted) context.read<ThemeProvider>().reset();
              // signOut()은 notifyListeners()로 라우팅 처리 — setState/context 미사용
              // 따라서 이후 mounted 체크 불필요 (의도된 설계)
              await userProvider.signOut();
            }
          }

          return Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            padding: EdgeInsets.fromLTRB(
              24, 16, 24,
              MediaQuery.of(ctx).viewInsets.bottom + 24,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 핸들 바
                  Center(
                    child: Container(
                      width: 40, height: 4,
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
                    style: ResponsiveHelper.titleStyle(ctx).copyWith(
                        fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '탈퇴 후 계정 복구는 불가능합니다',
                    style: ResponsiveHelper.smallStyle(ctx,
                        color: AppColors.grey500),
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
                          style: ResponsiveHelper.smallStyle(ctx,
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
                                    style: ResponsiveHelper.tinyStyle(ctx,
                                        color: AppColors.errorDeep)),
                                Expanded(
                                  child: Text(text,
                                      style: ResponsiveHelper.tinyStyle(ctx,
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
                    style: ResponsiveHelper.bodyStyle(ctx).copyWith(
                        fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: passwordCtrl,
                    obscureText: obscure,
                    decoration: InputDecoration(
                      hintText: '현재 비밀번호 입력',
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12)),
                      errorText: errorMsg,
                      suffixIcon: IconButton(
                        icon: Icon(
                          obscure ? Icons.visibility_off : Icons.visibility,
                          size: 20,
                        ),
                        onPressed: () => setModal(() => obscure = !obscure),
                      ),
                    ),
                    onSubmitted: (_) => doDelete(),
                  ),
                  const SizedBox(height: 20),

                  // 버튼
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: isLoading ? null : () => Navigator.pop(ctx),
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
                          onPressed: isLoading ? null : doDelete,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.error,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                          child: isLoading
                              ? const SizedBox(
                                  width: 18, height: 18,
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
        },
      ),
    );
    passwordCtrl.dispose();
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

    DialogHelper.showLoading(context, message: '마이그레이션 진행 중...\n잠시만 기다려주세요.');

    try {
      // 마이그레이션 실행
      final result = await FirestoreService().migrateApplicationWorkDetailIds();
      
      // 로딩 닫기
      if (context.mounted) Navigator.pop(context);

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
    } catch (e) {
      // 로딩 닫기
      if (context.mounted) Navigator.pop(context);
      if (context.mounted) ToastHelper.showError('마이그레이션 오류: $e');
    }
  }

  // ── 서명 등록 카드 ────────────────────────────────────────────

  Widget _buildSignatureCard(BuildContext context, UserModel? user) {
    final theme = Theme.of(context);
    final signatureBase64 = user?.signatureBase64;
    final hasSignature = signatureBase64 != null && signatureBase64.isNotEmpty;

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
                      hasSignature ? '등록됨 · 계약서 서명 시 자동 사용' : '미등록 · 계약서 서명에 사용됩니다',
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
                    base64Decode(signatureBase64),
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
      final b64 = base64Encode(bytes);
      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .update({'signatureBase64': b64});
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
      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .update({'signatureBase64': null});
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
            width: 20, height: 20,
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
                          style: ResponsiveHelper.bodyStyle(context)
                              .copyWith(fontWeight: FontWeight.w600, color: AppColors.grey500)),
                      SizedBox(height: ResponsiveHelper.spacing(context, 2)),
                      Text('사업장 등록 후 설정 가능합니다',
                          style: ResponsiveHelper.tinyStyle(context, color: AppColors.grey400)),
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

    final hasSeal = _businessSealBase64 != null && _businessSealBase64!.isNotEmpty;
    final isStamp = _sealType == 'stamp';

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
                    Text('사업주 날인',
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
                    base64Decode(_businessSealBase64!),
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
      final b64 = base64Encode(bytes);
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .update({'sealBase64': b64, 'sealType': 'stamp'});
      await userProvider.refreshUserData();
      if (mounted) {
        setState(() {
          _businessSealBase64 = b64;
          _sealType = 'stamp';
        });
        ToastHelper.showSuccess('도장이 등록되었습니다');
      }
    } catch (e) {
      if (mounted) ToastHelper.showError('도장 등록에 실패했습니다');
    }
  }

  Future<void> _registerBusinessSignature(BuildContext context, UserModel? user) async {
    if (user == null) return;

    final userProvider = context.read<UserProvider>();
    final bytes = await showSignaturePad(context, title: '사업주 서명');
    if (bytes == null || !mounted) return;

    try {
      final b64 = base64Encode(bytes);
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .update({'sealBase64': b64, 'sealType': 'signature'});
      await userProvider.refreshUserData();
      if (mounted) {
        setState(() {
          _businessSealBase64 = b64;
          _sealType = 'signature';
        });
        ToastHelper.showSuccess('서명이 등록되었습니다');
      }
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
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .update({'sealBase64': null, 'sealType': 'stamp'});
      await userProvider.refreshUserData();
      if (mounted) {
        setState(() {
          _businessSealBase64 = null;
          _sealType = 'stamp';
        });
        ToastHelper.showSuccess('날인이 삭제되었습니다');
      }
    } catch (e) {
      if (mounted) ToastHelper.showError('날인 삭제에 실패했습니다');
    }
  }
}

// ── 설정 메뉴 그룹용 데이터 클래스 ─────────────────────────────────
class _SettingsItem {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;

  const _SettingsItem({
    required this.icon,
    required this.iconColor,
    required this.title,
    this.subtitle,
    required this.onTap,
  });
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
                  fontWeight:
                      selected ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
