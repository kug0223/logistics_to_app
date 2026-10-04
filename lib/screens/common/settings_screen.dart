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
import '../business_admin/admin_stats_screen.dart';
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
import '../../services/business_posting_readiness.dart';
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
import '../../widgets/common/app_page_actions.dart';
import '../../widgets/user/pending_contract_bar.dart';
import '../../widgets/common/app_page_scaffold.dart';

/// 설정 화면 진입 시 바로 보여줄 항목.
///
/// [FP-07] 다른 화면의 CTA가 "설정으로 이동"만 하면 사용자가 긴 목록에서
/// 항목을 직접 찾아야 한다. 지금은 인감/서명 하나만 필요하므로
/// navigation framework를 만들지 않고 최소 진입점만 둔다.
enum SettingsTarget { seal }

/// ✨ 통합 설정 화면 (역할별 메뉴 자동 표시)
class SettingsScreen extends StatefulWidget {
  /// 지정하면 해당 섹션이 보이도록 스크롤한다. null이면 기존대로 최상단.
  final SettingsTarget? initialTarget;

  const SettingsScreen({super.key, this.initialTarget});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  /// [FP-07] initialTarget 스크롤용 — 지정되지 않으면 쓰이지 않는다.
  final _scrollCtrl = ScrollController();
  final _sealKey = GlobalKey();
  bool _isPushEnabled = true;
  bool _isLoading = true;
  Map<String, bool> _notifPrefs = Map.of(UserModel.defaultNotifPrefs);
  bool _isNotifPrefsLoading = false;
  bool _isNotifExpanded = false;
  String _appVersion = '';
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
    // [FP-07] 지정된 섹션으로 이동 — ListView(children:)이라 전 항목이
    //   빌드되므로 ensureVisible이 동작한다. 실패해도 최상단일 뿐이다.
    if (widget.initialTarget != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToTarget());
    }
  }

  void _scrollToTarget() {
    if (!mounted) return;
    final ctx = switch (widget.initialTarget) {
      SettingsTarget.seal => _sealKey.currentContext,
      null => null,
    };
    if (ctx == null) return;
    Scrollable.ensureVisible(
      ctx,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOut,
      alignment: 0.1,
    );
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
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

        // [R7-P1-6 P16-M] 관리자 역할만 D0 의 flat admin shell 로 바꾼다.
        //
        //   이 화면은 **역할이 공유한다**. USER·SubAdmin(사용자 모드)도 들어와
        //   '설정' 으로 본다(`showUserItems`). 이전 감사 메모는 "USER 진입 경로가
        //   없다"고 적었는데 현행 HEAD 에서는 사실이 아니다 —
        //   `contract_sign_screen`·`job_posting_screen`·`notification_screen` 이
        //   여는 경로가 있고 SubAdmin 은 모드 전환으로 이 화면을 양쪽에서 쓴다.
        //   그래서 shell 을 통째로 바꾸면 **지원자 공통 레이아웃까지** 바뀐다.
        //   지원자 쪽은 P2 소유이므로 건드리지 않는다.
        //
        //   프로필 블록은 그라디언트 헤더 위에 흰 글자로 그려져 있다. flat 배경
        //   (grey100)에 그대로 내리면 보이지 않으므로, 관리자 경로에서는 같은
        //   블록을 **brand 색 카드**(radius 16)에 담아 대비를 유지한다 —
        //   내용·문구·정보량은 그대로다.
        final useAdminShell =
            showAdminSection || user?.role == UserRole.SUPER_ADMIN;
        final listBody = ListView(
            controller: _scrollCtrl,
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

              // ── [사업장 관리] ─────────────────────────────────────
              // BUSINESS_ADMIN 또는 SUB_ADMIN(관리자 모드)에게 표시.
              // 권한별 개별 항목은 nullable로 처리해 _buildMenuGroup에서 자동 필터.
              if (showAdminSection) ...[
                _buildSectionHeader(
                    context, '사업장 관리', Icons.business_outlined),
                SizedBox(height: ResponsiveHelper.spacing(context, 8)),
                // [5D.2A] BUSINESS_ADMIN: 사업장 서류 관리 → BusinessListScreen
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
                // 날인 카드: BUSINESS_ADMIN 항상 / SubAdmin은 canManageContract일 때만
                if (user?.isBusinessAdmin == true ||
                    !userProvider.checkCurrentBusiness((p) => p.canManageContract).hidesAffordance) ...[
                  KeyedSubtree(key: _sealKey, child: _buildSealCard(context, user)),
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
                          !userProvider.checkCurrentBusiness((p) => p.canManageTo).hidesAffordance
                      ? _SettingsItem(
                          icon: Icons.work_outline,
                          iconColor: AppColors.warningDark,
                          title: '업무 관리',
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
                ]),
                SizedBox(height: ResponsiveHelper.spacing(context, 20)),
              ],

              // ── [계약] ────────────────────────────────────────────
              // BUSINESS_ADMIN 또는 canManageContract SUB_ADMIN에게 표시.
              if (showAdminSection &&
                  (user?.isBusinessAdmin == true ||
                      !userProvider.checkCurrentBusiness((p) => p.canManageContract).hidesAffordance)) ...[
                _buildSectionHeader(
                    context, '계약', Icons.description_outlined),
                SizedBox(height: ResponsiveHelper.spacing(context, 8)),
                _buildMenuGroup(context, [
                  _SettingsItem(
                    icon: Icons.folder_open_outlined,
                    iconColor: AppColors.infoDark,
                    title: '계약 관리',
                    onTap: () async {
                      final nav = Navigator.of(context);
                      final biz = await BusinessPickerHelper.pick(context);
                      if (biz == null || !mounted) return;
                      nav.push(MaterialPageRoute(
                          builder: (_) => AdminContractManagementScreen(
                              businessId: biz.id,
                              businessName: biz.name)));
                    },
                  ),
                  _SettingsItem(
                    icon: Icons.article_outlined,
                    iconColor: AppColors.infoDark,
                    title: '계약서 템플릿',
                    onTap: () async {
                      final nav = Navigator.of(context);
                      final biz = await BusinessPickerHelper.pick(context);
                      if (biz == null || !mounted) return;
                      if (kDebugMode) {
                        debugPrint(
                            '📋 [settings/contractTemplate] businessId=${biz.id}');
                      }
                      nav.push(MaterialPageRoute(
                          builder: (_) =>
                              ContractTemplateListScreen(businessId: biz.id)));
                    },
                  ),
                ]),
                SizedBox(height: ResponsiveHelper.spacing(context, 20)),
              ],

              // ── [분석] ────────────────────────────────────────────
              // BUSINESS_ADMIN 또는 canManageWage·canManageWorkers SUB_ADMIN에게 표시.
              if (showAdminSection &&
                  (user?.isBusinessAdmin == true ||
                      !userProvider.checkCurrentBusiness((p) => p.canManageWage).hidesAffordance ||
                      !userProvider.checkCurrentBusiness((p) => p.canManageWorkers).hidesAffordance)) ...[
                _buildSectionHeader(context, '분석', Icons.bar_chart_outlined),
                SizedBox(height: ResponsiveHelper.spacing(context, 8)),
                _buildMenuGroup(context, [
                  user?.isBusinessAdmin == true ||
                          !userProvider.checkCurrentBusiness((p) => p.canManageWage).hidesAffordance
                      ? _SettingsItem(
                          icon: Icons.insights_outlined,
                          iconColor: AppColors.purpleDark,
                          title: '통계',
                          onTap: () async {
                            final nav = Navigator.of(context);
                            final biz =
                                await BusinessPickerHelper.pick(context);
                            if (biz == null || !mounted) return;
                            nav.push(MaterialPageRoute(
                                builder: (_) =>
                                    AdminStatsScreen(businessIds: [biz.id])));
                          },
                        )
                      : null,
                  user?.isBusinessAdmin == true ||
                          !userProvider.checkCurrentBusiness((p) => p.canManageWorkers).hidesAffordance
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
        );

        // [R7-P3-4] 지원자 경로도 flat shell 로 맞춘다.
        //
        //   P1-6 에서 관리자 경로만 바꾸고 지원자 쪽은 P2 소유라 남겨 뒀다.
        //   그 사이 MY 탭·홈·일정·일자리가 모두 flat 이 되어, 이 화면만
        //   파란 헤더로 열리고 있었다. 프로필 블록의 대비 문제는 관리자 경로가
        //   이미 푼 방식(brand 색 카드)을 **그대로** 쓴다 — 내용·문구 동일.
        //
        //   지원자 경로에만 있던 기능은 잃지 않는다:
        //   우상단 홈·알림(배지 포함)과 미서명 계약 바. 새로고침은 원래 없었다.
        //   관리자 경로에는 이 셋을 **더하지 않는다** — 없던 것을 만들지 않는다.
        return AppPageScaffold(
          title: useAdminShell
              ? (showAdminSection ? '관리' : '설정')
              : '설정',
          actions: useAdminShell ? const [] : appPageActions(context),
          bottomNavigationBar: useAdminShell
              ? null
              : const PendingContractBar(useSafeArea: true),
          body: Column(
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(
                  ResponsiveHelper.spacing(context, 16),
                  ResponsiveHelper.spacing(context, 12),
                  ResponsiveHelper.spacing(context, 16),
                  0,
                ),
                // [P4.2B-ID-01] 관리자 경로만 tonal 로 내렸다.
                //
                //   이 블록에는 InkWell 도 onTap 도 없다 — 프로필 편집도,
                //   역할 전환도, 사업장 전환도 아니다. 순수한 이름표다.
                //   그런데 관리 탭에서 가장 진한 면(primary 100%)을 그것이
                //   차지하고, 실제로 누를 수 있는 모든 메뉴 행은 흰 바탕에
                //   회색 아이콘이었다. **만질 수 없는 것이 가장 강했다.**
                //
                //   [R7-P4.2B VR-03] 세 안을 360dp 에서 직접 그려 재 봤다.
                //     x1.0  A=103  B/C=88 / x1.3  A=118  B/C=123
                //   높이는 근거가 아니다(큰 글꼴에서 역전). 근거는 면적의
                //   강도다. B(흰 면)는 아래 메뉴 행과 구별이 사라져 이름표가
                //   또 하나의 누를 수 있는 행처럼 읽혔다. C 는 brand 를
                //   유지하면서 강도만 내린다.
                //
                //   지원자 경로는 그대로 둔다 — 그쪽 블록은 이름표가 아니라
                //   근무·평점·지각·노쇼를 담은 정보 면이라 성격이 다르다.
                child: Container(
                  decoration: BoxDecoration(
                    color: useAdminShell
                        ? theme.primaryColor.withValues(alpha: 0.06)
                        : theme.primaryColor,
                    borderRadius: BorderRadius.circular(16),
                    border: useAdminShell
                        ? Border.all(
                            color: theme.primaryColor.withValues(alpha: 0.16))
                        : null,
                  ),
                  child: _buildHeaderProfile(context, userProvider,
                      tonal: useAdminShell),
                ),
              ),
              Expanded(child: listBody),
            ],
          ),
        );
      },
    );
  }

  /// ✨ 세련된 프로필 카드
  /// 파란 헤더 — 가로 compact 프로필 (공간 최소화)
  Widget _buildSettingsAvatar(BuildContext context, UserModel? user,
      {bool tonal = false}) {
    // [P4.2B-ID-01] tonal 면 위에서는 흰 아이콘이 보이지 않는다.
    //   아바타 크기도 함께 내린다 — 이름표가 첫 화면을 덜 차지한다.
    final fg = tonal ? Theme.of(context).primaryColor : Colors.white;
    final size = ResponsiveHelper.spacing(context, tonal ? 44 : 52);
    final photoUrl = user?.profileImageUrl;
    final hasPhoto = photoUrl != null && photoUrl.isNotEmpty;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: tonal
            ? Theme.of(context).primaryColor.withValues(alpha: 0.10)
            : Colors.white.withValues(alpha: 0.2),
        shape: BoxShape.circle,
      ),
      child: ClipOval(
        child: hasPhoto
            ? CachedNetworkImage(
                imageUrl: photoUrl,
                fit: BoxFit.cover,
                placeholder: (_, __) => Icon(
                  Icons.person,
                  size: ResponsiveHelper.iconSize(context, tonal ? 24 : 30),
                  color: fg,
                ),
                errorWidget: (_, __, ___) => Icon(
                  Icons.person,
                  size: ResponsiveHelper.iconSize(context, tonal ? 24 : 30),
                  color: fg,
                ),
              )
            : Icon(
                Icons.person,
                size: ResponsiveHelper.iconSize(context, tonal ? 24 : 30),
                color: fg,
              ),
      ),
    );
  }

  Widget _buildHeaderProfile(BuildContext context, UserProvider userProvider,
      {bool tonal = false}) {
    final user = userProvider.currentUser;
    final isUser = user?.role == UserRole.USER;
    // [P4.2B-ID-01] tonal 면에서는 흰 글자가 전부 사라진다. 색만 바꾸고
    //   구성(아바타 · 이름 · @아이디 · 역할 배지)과 문구는 그대로 둔다.
    final theme = Theme.of(context);
    final nameColor = tonal ? AppColors.textPrimary : Colors.white;
    final subColor =
        tonal ? AppColors.grey500 : Colors.white.withValues(alpha: 0.8);
    final badgeFg = tonal ? theme.primaryColor : Colors.white;
    final badgeBg = tonal
        ? theme.primaryColor.withValues(alpha: 0.10)
        : Colors.white.withValues(alpha: 0.2);

    return Padding(
      padding: EdgeInsets.fromLTRB(
        ResponsiveHelper.spacing(context, tonal ? 14 : 16),
        ResponsiveHelper.spacing(context, tonal ? 14 : 4),
        ResponsiveHelper.spacing(context, tonal ? 14 : 16),
        ResponsiveHelper.spacing(context, tonal ? 14 : 16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── 아바타(좌) + 이름/역할(우) 가로 배치
          Row(
            children: [
              // 작은 아바타
              _buildSettingsAvatar(context, user, tonal: tonal),
              SizedBox(width: ResponsiveHelper.spacing(context, tonal ? 12 : 14)),
              // 이름 + 아이디 + 역할
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      user?.name ?? '사용자',
                      style: ResponsiveHelper.subtitleStyle(context).copyWith(
                        color: nameColor,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '@${user?.username ?? 'username'}',
                      style:
                          ResponsiveHelper.tinyStyle(context, color: subColor),
                    ),
                    const SizedBox(height: 6),
                    // 역할 배지 (작게)
                    Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: ResponsiveHelper.spacing(context, 8),
                        vertical: ResponsiveHelper.spacing(context, 3),
                      ),
                      decoration: BoxDecoration(
                        color: badgeBg,
                        borderRadius: BorderRadius.circular(12),
                        border: tonal
                            ? null
                            : Border.all(
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
                            color: badgeFg,
                          ),
                          SizedBox(width: ResponsiveHelper.spacing(context, 4)),
                          Text(
                            CommonWidgets.getRoleName(
                                user?.roleString ?? 'USER'),
                            style: ResponsiveHelper.tinyStyle(context,
                                color: badgeFg,
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
                          const Text('확인하기 →', style: TextStyle(fontSize: 12)),
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
              // [R7-P4.4E.11C.0C.0a.6] 승인된 돈인데 끝낼 사람이 남지 않는 경우다.
              //   "승인 대기"(INTERIM_PENDING)와 다른 사실이므로 문구를 섞지 않는다.
              'INTERIM_SETTLEMENT_UNPROCESSED' =>
                '승인된 중간정산 $n건 미이체 — 탈퇴 후 처리할 관리자가 없습니다',
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
                // 같은 화면(중간정산 탭)이지만 PENDING 필터를 끈 경로다 —
                //   막힌 이유가 APPROVED 미이체이므로 그 행이 보여야 한다.
                'INTERIM_SETTLEMENT_UNPROCESSED' => 'payroll_interim_approved',
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
                      // [R7-P1-6 P16-M] 상태색은 AppColors 계약 안에서만 쓴다 —
                      //   바로 위 hardBlocks 는 이미 error/errorBg 를 쓰고 있었다.
                      Text('확인 권장 사항',
                          style: ResponsiveHelper.smallStyle(ctx,
                              color: AppColors.warningDark,
                              fontWeight: FontWeight.w600)),
                      const SizedBox(height: 8),
                      for (final w in warnings)
                        blockRow(
                          color: AppColors.warningDark,
                          bgColor: AppColors.warningBg,
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
                          color: AppColors.successBg,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.successLight),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.check_circle_outline,
                                size: 18, color: AppColors.success),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text('탈퇴 가능한 상태입니다.',
                                  style: ResponsiveHelper.smallStyle(ctx,
                                      color: AppColors.successDark)),
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
        case 'payroll_interim_approved':
          // 중간정산 탭(3) — 사업장 선택 후 당월 급여 지급현황으로 이동
          //
          // [R7-P4.4E.11C.0C.0a.6 §18] 두 blocker 가 가리키는 **행이 다르다.**
          //   `INTERIM_PENDING` 은 승인 대기(PENDING)로 보내고,
          //   `INTERIM_SETTLEMENT_UNPROCESSED` 는 이미 승인된(APPROVED)
          //   미이체 행으로 보내야 한다. PENDING 필터를 그대로 쓰면 후자는
          //   "처리 대기 중인 중간정산이 없습니다" 가 떠서, 막힌 이유를
          //   말해 놓고 그 일을 할 화면이 비어 있게 된다.
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
                        // [5C.2-S21] Home 드릴다운과 동일 PENDING 필터 —
                        //   승인 미이체 경로에서는 끈다(PENDING+APPROVED 전체).
                        showPendingSettlementOnly:
                            navTarget != 'payroll_interim_approved',
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


  /// [R7-P4.4E.3A] 고용주 날인 **상태만** 보여주는 카드 (SubAdmin).
  ///
  ///   등록·변경·삭제 CTA 를 주지 않는다. 등록할 수 있는 사람은 사업장
  ///   owner 뿐이고, 여기서 저장하면 호출자 **본인** 날인이 기록돼
  ///   계약서 사업주란과는 무관한 값이 생긴다(P4.4C §9 — SubAdmin 에게
  ///   인감을 등록하라고 하지 않는다).
  ///
  ///   상태는 Home 이 쓰는 준비 판정과 **같은 것**을 읽는다. 못 읽은 것을
  ///   '미등록' 으로 접지 않는다 — 실제로는 등록돼 있는데 사업장 관리자에게
  ///   헛된 요청을 하게 만든다.
  Widget _buildEmployerSealStatusCard(BuildContext context) {
    return ValueListenableBuilder<FirstPostingReadinessSnapshot>(
      valueListenable: FirstPostingReadinessStore.current,
      builder: (ctx, snap, _) {
        final r = snap.isResolved ? snap.value : null;

        late final String title;
        late final String body;
        late final IconData icon;
        late final Color tone;

        if (snap.status == FirstPostingReadinessStatus.failed) {
          icon = Icons.cloud_off_rounded;
          tone = AppColors.grey500;
          title = '사업주 날인';
          body = '상태를 확인하지 못했어요';
        } else if (r == null) {
          icon = Icons.hourglass_empty_rounded;
          tone = AppColors.grey400;
          title = '사업주 날인';
          body = '확인 중이에요';
        } else if (r.sealReady) {
          icon = Icons.verified_rounded;
          tone = AppColors.success;
          title = '사업주 날인';
          body = '등록됨 · 계약서 사업주란에 사용됩니다';
        } else if (r.sealUnknown) {
          icon = Icons.help_outline_rounded;
          tone = AppColors.grey500;
          title = '사업주 날인';
          body = '상태를 확인할 수 없어요\n사업장 관리자에게 확인하세요';
        } else {
          icon = Icons.error_outline_rounded;
          tone = AppColors.warningDark;
          title = '사업주 날인';
          body = '미등록 · 사업장 관리자에게 등록을 요청하세요';
        }

        return Container(
          decoration: CommonWidgets.compactCardDecoration(),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: ResponsiveHelper.spacing(context, 16),
              vertical: ResponsiveHelper.spacing(context, 12),
            ),
            child: Row(
              children: [
                Container(
                  width: ResponsiveHelper.spacing(context, 34),
                  height: ResponsiveHelper.spacing(context, 34),
                  decoration: BoxDecoration(
                    color: tone.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon,
                      color: tone,
                      size: ResponsiveHelper.iconSize(context, 18)),
                ),
                SizedBox(width: ResponsiveHelper.spacing(context, 12)),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: ResponsiveHelper.bodyStyle(context)
                              .copyWith(fontWeight: FontWeight.w600)),
                      Text(
                        body,
                        style: ResponsiveHelper.tinyStyle(context,
                            color: AppColors.grey500),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

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

    // [R7-P4.4E.3] 값을 **복사해 들고 있지 않는다.**
    //
    //   예전에는 `_loadBusinessSeal()` 이 initState 에서 한 번 읽어 둔
    //   `_businessSealBase64` 를 그렸다. 관리 탭 root 는 IndexedStack 안에서
    //   계속 살아 있고 재진입 시 다시 읽는 곳이 없다. 그래서 Home 의 준비
    //   카드에서 인감을 등록하면(그쪽은 **다른 인스턴스**다) Home 은 완료로
    //   바뀌는데 관리 탭은 계속 '미등록' 이었다 — 같은 값을 두고 두 화면이
    //   다른 말을 한 것이다.
    //
    //   바로 옆 서명 카드는 처음부터 `user.signatureBase64` 를 build 때
    //   읽고 있었다. 인감도 같은 규칙으로 맞춘다. 저장 경로가 이미
    //   `refreshUserData()` 를 부르므로 provider 가 알리면 여기까지 닿는다.
    // [R7-P4.4E.3A] 계약서 사업주란에 들어가는 것은 **사업장 owner 의 날인**
    //   이다(P4.4C). 호출자 자신의 날인이 아니다.
    //
    //   여기는 `users/{callerUid}.sealBase64` 를 그리는 자리라, 호출자가
    //   owner 인 동안만 맞는 말이었다. SubAdmin 에게는 본인 날인을 고용주
    //   날인인 것처럼 보여 줬고 — 개인 날인이 있으면 '등록됨' 이라고 했다.
    //   그 날인은 계약 writer 가 쓰지 않으므로 준비되지 않았는데 되었다고
    //   말한 셈이다. 등록 버튼도 눌러 봐야 그 칸을 채우지 못한다.
    //
    //   owner 날인을 직접 읽을 수는 없다 — `users/{uid}` get 은 본인과
    //   SUPER_ADMIN 만이다(firestore.rules). 그래서 Home 이 이미 쓰고 있는
    //   준비 판정을 **같이** 본다. 새 조회도, 새 listener 도 만들지 않는다.
    if (user?.isSubAdmin == true) {
      return _buildEmployerSealStatusCard(context);
    }

    final sealBase64 = user?.sealBase64;
    final hasSeal = sealBase64 != null && sealBase64.isNotEmpty;
    final isStamp = (user?.sealType ?? _sealType) == 'stamp';

    // [PERF-FIX] base64 변경 시에만 재디코딩 — build마다 decode 방지
    if (hasSeal && sealBase64 != _cachedSealBase64) {
      _cachedSealBase64 = sealBase64;
      _cachedSealBytes = base64Decode(sealBase64);
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
        _sealType = 'stamp';
      });
      ToastHelper.showSuccess('도장이 등록되었습니다');
    } catch (e) {
      // [P4.4B-SEAL-01] 예전에는 원인을 하나로 뭉개고 로그도 남기지 않았다.
      //   권한 거부·네트워크·서버 거절이 같은 문장이라, 관리자는 다시 눌러야
      //   하는지 다른 이미지를 골라야 하는지 알 수 없었다.
      debugPrint('❌ 도장 등록 실패: $e');
      if (mounted) ToastHelper.showError(_sealErrorMessage(e));
    }
  }

  /// [P4.4B-SEAL-01] 인감/서명 저장 실패 — 원인별로 다음 행동이 다르다.
  String _sealErrorMessage(Object e) {
    if (e is FirebaseFunctionsException) {
      return switch (e.code) {
        'unauthenticated' => '로그인이 만료됐어요\n다시 로그인한 뒤 등록해주세요',
        'permission-denied' => '이 계정에는 날인을 등록할 권한이 없어요',
        // 서버가 크기·형식을 거절한 경우 — 다시 눌러도 같다.
        'invalid-argument' => '이미지를 등록할 수 없어요\n더 작고 선명한 이미지로 다시 시도해주세요',
        'unavailable' || 'deadline-exceeded' =>
          '네트워크가 불안정해요\n잠시 후 다시 시도해주세요',
        _ => '등록하지 못했어요\n잠시 후 다시 시도해주세요',
      };
    }
    return '등록하지 못했어요\n잠시 후 다시 시도해주세요';
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
        _sealType = 'signature';
      });
      ToastHelper.showSuccess('서명이 등록되었습니다');
    } catch (e) {
      // [P4.4B-SEAL-01] 사업주 서명도 도장과 같은 저장 경로(callableSaveSeal)다.
      debugPrint('❌ 사업주 서명 등록 실패: $e');
      if (mounted) ToastHelper.showError(_sealErrorMessage(e));
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
      // 화면 값은 provider 에서 다시 읽는다 — 여기서 따로 들고 있지 않는다.
      setState(() => _sealType = 'stamp');
      ToastHelper.showSuccess('날인이 삭제되었습니다');
    } catch (e) {
      // [P4.4B-SEAL-01] 삭제 실패를 조용히 넘기면 화면은 지워진 것처럼 보이고
      //   서버에는 남는다 — 다음 계약에 옛 날인이 찍힌다.
      debugPrint('❌ 날인 삭제 실패: $e');
      if (mounted) ToastHelper.showError(_sealErrorMessage(e));
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
