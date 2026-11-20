// lib/screens/user/user_settings_screen.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';

import 'package:cloud_functions/cloud_functions.dart';
import '../../models/core/legal_terms_model.dart';
import '../../models/core/user_model.dart';
import '../../providers/user_provider.dart';
import '../../services/auth_service.dart';
import '../../services/fcm_service.dart';
import '../../services/legal_terms_service.dart';
import '../../theme/app_colors.dart';
import '../../utils/dialog_helper.dart';
import '../../utils/text_layout.dart';
import '../../utils/toast_helper.dart';
import '../../widgets/dialogs/styled_dialog.dart';
import '../../widgets/common/terms_read_only_screen.dart';
import '../common/help_screen.dart';
import '../common/tour_screen.dart';

/// 사용자 전용 설정 화면
///
/// MY 탭 하단 "설정" 메뉴에서 진입.
/// 앱 환경·도움말·약관·계정 관리 항목만 포함.
/// 프로필 정보·근무 통계·배지 등은 MY 탭에서 직접 관리.
class UserSettingsScreen extends StatefulWidget {
  const UserSettingsScreen({super.key});

  @override
  State<UserSettingsScreen> createState() => _UserSettingsScreenState();
}

class _UserSettingsScreenState extends State<UserSettingsScreen> {
  // ── 알림 ────────────────────────────────────────────────────────
  bool _isPushEnabled = false;
  bool _isLoading = true;
  bool _isNotifPrefsLoading = false;
  bool _isNotifExpanded = false;
  Map<String, bool> _notifPrefs = Map.of(UserModel.defaultNotifPrefs);

  // ── 앱 정보 ──────────────────────────────────────────────────────
  String _appVersion = '';

  @override
  void initState() {
    super.initState();
    _loadNotificationStatus();
    _loadAppVersion();
  }

  // ── 초기화 ──────────────────────────────────────────────────────

  Future<void> _loadAppVersion() async {
    final info = await PackageInfo.fromPlatform();
    if (mounted) setState(() => _appVersion = info.version);
  }

  Future<void> _loadNotificationStatus() async {
    final userId = context.read<UserProvider>().currentUser?.uid;
    if (userId == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    final permStatus = await Permission.notification.status;
    final systemGranted = permStatus.isGranted;

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
          _notifPrefs = {...UserModel.defaultNotifPrefs, ...savedPrefs};
        }
        _isLoading = false;
      });
    }
  }

  Future<void> _togglePushNotification(bool value) async {
    if (_isLoading) return;
    setState(() => _isLoading = true);

    try {
      final userProvider = context.read<UserProvider>();
      final userId = userProvider.currentUser?.uid;
      if (userId == null) return;

      final isAdminForFcm =
          userProvider.isSubAdmin ? userProvider.isAdminMode : userProvider.isAdmin;
      if (value) {
        final permStatus = await Permission.notification.status;
        if (permStatus.isDenied) await Permission.notification.request();
        final granted = await Permission.notification.isGranted;
        if (!mounted) return;
        if (!granted) {
          ToastHelper.showWarning('기기 설정에서 알림 권한을 허용해주세요');
          await openAppSettings();
          return;
        }
        await FCMService().initialize(userId, isAdmin: isAdminForFcm);
        if (!mounted) return;
        ToastHelper.showSuccess('푸시 알림이 활성화되었습니다');
      } else {
        // [.69] 서버 반영이 확인돼야 '꺼짐'(settings_screen 과 같은 계약).
        final removed = await FCMService().clearToken(networkTimeout: const Duration(seconds: 8));
        if (!mounted) return;
        if (!removed) {
          await FCMService().initialize(userId, isAdmin: isAdminForFcm);
          if (!mounted) return;
          ToastHelper.showError('푸시 알림을 끄지 못했습니다. 서버에 반영되지 않아 알림이 계속 올 수 있어요. 연결을 확인한 뒤 다시 시도해 주세요.');
          return;
        }
        ToastHelper.showSuccess('푸시 알림이 비활성화되었습니다');
      }
      setState(() => _isPushEnabled = value);
    } catch (_) {
      if (mounted) ToastHelper.showError('알림 설정 변경에 실패했습니다');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

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
    } catch (_) {
      if (mounted) {
        setState(() => _notifPrefs = {..._notifPrefs, key: !value});
        ToastHelper.showError('설정 저장에 실패했습니다');
      }
    } finally {
      if (mounted) setState(() => _isNotifPrefsLoading = false);
    }
  }

  // ── 약관 뷰어 ──────────────────────────────────────────────────

  Future<void> _showTermsInApp(
      BuildContext ctx, String termId, String fallbackTitle) async {
    LegalTermsItem? item;
    try {
      final terms = await LegalTermsService().fetchEffectiveTerms();
      item = terms.items.where((t) => t.id == termId).firstOrNull;
    } catch (_) {
      item = null;
    }
    if (!mounted) return;
    // ignore: use_build_context_synchronously
    await Navigator.of(ctx).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        // [DU263] 공용 약관 화면(두 설정 화면의 같은 사본을 합침). 못 읽으면 본문 대신 실패 상태를 보인다
        //   — 이전에는 실패 문장을 약관 본문처럼 그렸다.
        builder: (_) => TermsReadOnlyScreen(
          title: item?.title ?? fallbackTitle,
          content: item?.content ?? '',
          version: item?.version,
          loadFailed: item == null,
        ),
      ),
    );
  }

  // ── 계정 ────────────────────────────────────────────────────────

  Future<void> _handleLogout() async {
    final confirmed = await DialogHelper.showLogoutConfirm(context);
    if (!mounted || !confirmed) return;
    await context.read<UserProvider>().signOut();
  }

  Future<void> _handleDeleteAccount() async {
    // [F-15-1(A) 수정] 중복 탭 방지 — _togglePushNotification과 동일 패턴
    // guard + try/finally로 진행 중 재진입 완전 차단
    if (_isLoading) return;
    setState(() => _isLoading = true);
    try {
      final confirmed = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => StyledDialog(
          title: '회원탈퇴',
          subtitle: '이 작업은 되돌릴 수 없습니다',
          icon: Icons.person_remove_outlined,
          headerColor: AppColors.error,
          content: StyledDialogInfoCard.error(
            '탈퇴하면 모든 데이터가 영구 삭제되며 복구할 수 없습니다.\n계속하려면 비밀번호를 입력해주세요.',
          ),
          actions: [
            StyledDialogButton.cancel(
              onPressed: () => Navigator.pop(ctx, false),
            ),
            StyledDialogButton.danger(
              text: '계속',
              onPressed: () => Navigator.pop(ctx, true),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;

      // 비밀번호 확인 다이얼로그
      // [FC-01 OWNERSHIP FIX] _WithdrawPasswordDialog(StatefulWidget)이 controller를
      // 직접 소유하고 State.dispose()에서 해제한다.
      // Dialog lifecycle ↔ controller lifecycle 완전 일치:
      //   State 생성 → _ctrl 생성 → 사용 → Navigator.pop → route 종료 → State.dispose() → _ctrl.dispose()
      // 부모 메서드가 controller를 소유하면 showDialog 완료 직후 dispose하게 되고,
      // Dialog 종료 애니메이션 중 DFSA deactivate()가 dispose된 controller에 접근해 크래시 발생.
      // ignore: use_build_context_synchronously
      final password = await showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => const _WithdrawPasswordDialog(),
      );
      if (password == null || password.isEmpty || !mounted) return;

      try {
        // [F-15-1(B) FIX] SubAdmin 탈퇴 차단 — settings_screen.dart와 동일 방어 적용
        // SubAdmin은 사업장에서 직책 해제 후 탈퇴해야 함
        final blockerResult = await FirebaseFunctions.instanceFor(region: 'asia-northeast3')
            .httpsCallable('callableGetWithdrawBlockers',
                options: HttpsCallableOptions(timeout: const Duration(seconds: 25)))
            .call<Map<String, dynamic>>({});
        if (!mounted) return;

        final hardBlocks = (blockerResult.data['hardBlocks'] as List<dynamic>? ?? [])
            .cast<Map<String, dynamic>>();
        // [NEW-QA-02 FIX] 서버가 반환하는 모든 hardBlock 처리 — SUBADMIN_MEMBERSHIP만 체크하던 버그 수정.
        // 탈퇴 가능 여부의 최종 진실 소스는 서버(callableDeleteAccountFinal)이며,
        // 클라이언트는 서버 결과 전체를 그대로 사용자에게 안내한다.
        if (hardBlocks.isNotEmpty) {
          final first = hardBlocks.first;
          final type = first['type'] as String? ?? '';
          final count = first['count'] as int? ?? 0;
          ToastHelper.showError(_hardBlockMessage(type, count));
          return;
        }

        final err = await AuthService().deleteAccountWithPassword(password);
        if (!mounted) return;
        if (err != null) {
          ToastHelper.showError(err);
        } else {
          await context.read<UserProvider>().signOut();
        }
      } catch (e) {
        if (mounted) ToastHelper.showError('탈퇴 처리 중 오류가 발생했습니다');
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ── hardBlock 안내 메시지 ─────────────────────────────────────────
  // [NEW-QA-02] 서버 callableGetWithdrawBlockers 반환 type별 사용자 안내
  String _hardBlockMessage(String type, int count) {
    switch (type) {
      case 'SUBADMIN_MEMBERSHIP':
        return '서브관리자로 등록된 사업장($count곳)에서 직책 해제 후 탈퇴해주세요.';
      case 'UNSIGNED_CONTRACT':
        return '미서명 계약서($count건)를 먼저 서명해주세요.';
      default:
        return '탈퇴 전 처리해야 할 항목($count건)이 있습니다. 해결 후 다시 시도해주세요.';
    }
  }

  // ── 빌드 ────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text(
          '설정',
          style: TextStyle(
            fontWeight: FontWeight.w800,
            letterSpacing: -0.3,
            color: AppColors.textPrimary,
          ),
        ),
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        // 뒤로가기 버튼: 파란 Material 기본색 아닌 어두운 텍스트 색
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: AppColors.borderLight),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 12),
        children: [
          // ── 알림 ────────────────────────────────────────────────
          _SectionHeader(label: '알림'),
          _buildNotificationCard(),
          const SizedBox(height: 8),

          // ── 앱 정보 ─────────────────────────────────────────────
          _SectionHeader(label: '앱 정보'),
          _buildInfoGroup([
            _InfoRow(
              icon: Icons.phone_android,
              label: '앱 버전',
              trailing: Text(
                _appVersion.isEmpty ? '...' : _appVersion,
                style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          ]),
          const SizedBox(height: 8),

          // ── 도움말 ───────────────────────────────────────────────
          _SectionHeader(label: '도움말'),
          _buildMenuGroup([
            _MenuRow(
              icon: Icons.help_outline,
              label: '도움말 (Q&A)',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const HelpScreen()),
              ),
            ),
            _MenuRow(
              icon: Icons.tour_outlined,
              label: '가이드 다시 보기',
              // [R7-ONBOARDING.1] 같은 메뉴 이름이 두 화면을 열고 있었다.
              //
              //   관리자 경로(공용 설정)는 기능 투어를, 이 경로는 가입 때 본
              //   소개(OnboardingScreen)를 열었다. 같은 사용자가 계약 서명
              //   화면을 거쳐 공용 설정에 닿으면 두 가지를 다 만났다.
              //
              //   '가이드' 는 기능 사용법이다. 제품 소개는 가입 때 한 번
              //   보는 것이고 다시 보기의 대상이 아니다 — 두 경로를 기능
              //   가이드 하나로 모은다.
              onTap: () async {
                final role =
                    context.read<UserProvider>().currentUser?.role.name ?? 'USER';
                await pushTourScreen(context, role: role);
              },
            ),
          ]),
          const SizedBox(height: 8),

          // ── 법적 고지 ─────────────────────────────────────────────
          _SectionHeader(label: '법적 고지'),
          _buildMenuGroup([
            _MenuRow(
              icon: Icons.article_outlined,
              label: '서비스 이용약관',
              onTap: () =>
                  _showTermsInApp(context, 'service_terms', '서비스 이용약관'),
            ),
            _MenuRow(
              icon: Icons.privacy_tip_outlined,
              label: '개인정보 처리방침',
              onTap: () =>
                  _showTermsInApp(context, 'privacy_policy', '개인정보 처리방침'),
            ),
            _MenuRow(
              icon: Icons.location_on_outlined,
              label: '위치정보 이용 동의',
              onTap: () =>
                  _showTermsInApp(context, 'location_terms', '위치정보 이용 동의'),
            ),
          ]),
          const SizedBox(height: 8),

          // ── 계정 ─────────────────────────────────────────────────
          _SectionHeader(label: '계정'),
          _buildMenuGroup([
            // [DU247] 로그아웃은 다시 로그인하면 되는 계정 동작이다 — 위험색 없이 다른 메뉴와 같은 중립 행
            //   (관리자 설정 S045 의 중립 버튼과 같은 뜻). 확인은 로그아웃 확인 대화가 맡는다(사용자 11-10 "중립으로 진행").
            _MenuRow(
              icon: Icons.logout,
              label: '로그아웃',
              onTap: _handleLogout,
            ),
          ]),
          const SizedBox(height: 8),
          // 회원탈퇴 — 파괴적 작업이므로 눈에 덜 띄게 표시
          // [DU245] 덜 띄게 = 중립 보조색·작은 밑줄 글자·맨 아래 자리. 글자는 읽혀야 한다(이전 grey400, 바탕 위 1.75).
          //   위험색(빨강)은 탈퇴를 오히려 강조하므로 쓰지 않는다(사용자 11-10). 관리자 설정(S045)과 같다.
          Center(
            child: TextButton(
              onPressed: _handleDeleteAccount,
              child: const Text(
                '회원탈퇴',
                style: TextStyle(
                  fontSize: 13,
                  color: AppColors.textSecondary,
                  decoration: TextDecoration.underline,
                  decorationColor: AppColors.textSecondary,
                ),
              ),
            ),
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  // ── 알림 카드 ──────────────────────────────────────────────────

  Widget _buildNotificationCard() {
    // [DU244] 다른 묶음과 같은 카드(_group). 행 아이콘도 메뉴 행과 같은 중립 상자다 — 켜짐/꺼짐은 스위치가 말한다.
    final theme = Theme.of(context);
    return _group(
      Column(
        children: [
          // 마스터 토글
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
            child: Row(
              children: [
                const _IconBox(icon: Icons.notifications_outlined),
                const SizedBox(width: 12),
                const Expanded(child: _RowLabel('푸시 알림')),
                if (_isLoading)
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  Switch(
                    value: _isPushEnabled,
                    onChanged: _togglePushNotification,
                    activeThumbColor: theme.primaryColor, // [DU244] 대표색(S045 와 같음)
                  ),
              ],
            ),
          ),
          // 상세 설정 확장 (활성화됐을 때만)
          if (_isPushEnabled) ...[
            const Divider(height: 1, thickness: 1, color: AppColors.grey100, indent: 64),
            InkWell(
              onTap: () => setState(() => _isNotifExpanded = !_isNotifExpanded),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    const _IconBox(icon: Icons.tune),
                    const SizedBox(width: 12),
                    const Expanded(child: _RowLabel('알림 세부 설정')),
                    Icon(
                      _isNotifExpanded
                          ? Icons.keyboard_arrow_up
                          : Icons.keyboard_arrow_down,
                      size: 18,
                      color: AppColors.textSecondary,
                    ),
                  ],
                ),
              ),
            ),
            if (_isNotifExpanded) _buildNotifCategories(),
          ],
          // 시스템 알림 설정 링크
          const Divider(height: 1, thickness: 1, color: AppColors.grey100, indent: 64),
          InkWell(
            onTap: () async => openAppSettings(),
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  _IconBox(icon: Icons.settings_applications_outlined),
                  SizedBox(width: 12),
                  Expanded(child: _RowLabel('시스템 알림 설정')),
                  Icon(Icons.open_in_new,
                      size: 14, color: AppColors.textSecondary),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNotifCategories() {
    final categories = [
      (key: UserModel.notifWorkReminder, label: '근무 알림'),
      (key: UserModel.notifApplicationUpdate, label: '지원 현황 알림'),  // 확정·취소는 항상 수신
      (key: UserModel.notifReviewAlert, label: '리뷰 알림'),
      (key: UserModel.notifContractAlert, label: '계약서 알림'),
      (key: UserModel.notifWageAlert, label: '급여 알림'),
      (key: UserModel.notifToMatchAlert, label: '새 일자리 알림'),
    ];

    return Container(
      color: AppColors.grey50,
      child: Column(
        children: categories.map((c) {
          // [DU244] 위 행 글자 시작(64)과 맞춘다.
          return Padding(
            padding: const EdgeInsets.fromLTRB(64, 0, 8, 0),
            child: Row(
              children: [
                Expanded(
                  // [DU244 v2] 큰 글자에서 줄이 바뀌면 낱말 단위로만(음절 끊김 금지). 읽기 도구에는 원문.
                  child: Text(
                    TextLayout.keepWords(c.label),
                    semanticsLabel: c.label,
                    style: const TextStyle(
                        fontSize: 13, color: AppColors.textSecondary),
                  ),
                ),
                // [DU244] 스위치 터치 48(shrinkWrap 제거). 저장 중 표시도 같은 높이 상자에 둬 행이 줄었다 늘지 않는다.
                _isNotifPrefsLoading
                    ? const SizedBox(
                        width: 60,
                        height: 48,
                        child: Center(
                          child: SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 1.5),
                          ),
                        ),
                      )
                    : Switch(
                        value: _notifPrefs[c.key] ?? true,
                        onChanged: (v) => _toggleNotifPref(c.key, v),
                        activeThumbColor: Theme.of(context).primaryColor, // [DU244] 대표색
                      ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  // ── 공통 레이아웃 helpers ─────────────────────────────────────────

  /// [DU244] 묶음 카드 — 관리자 홈(S010)·슈퍼관리자 홈(S062)과 같은 흰 면·반경 16·grey200 선.
  ///   Material 이라 안쪽 InkWell 의 눌림 표시가 카드 위에 보이고(이전 흰 Container 는 가렸다), 모서리에서 잘린다.
  Widget _group(Widget child) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Material(
        color: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppColors.grey200),
        ),
        clipBehavior: Clip.antiAlias,
        child: child,
      ),
    );
  }

  Widget _buildMenuGroup(List<_MenuRow> items) {
    return _group(
      Column(
        children: [
          for (var i = 0; i < items.length; i++) ...[
            items[i],
            if (i < items.length - 1)
              const Divider(height: 1, thickness: 1, color: AppColors.grey100, indent: 64),
          ],
        ],
      ),
    );
  }

  Widget _buildInfoGroup(List<_InfoRow> items) {
    return _group(
      Column(
        children: [
          for (var i = 0; i < items.length; i++) ...[
            items[i],
            if (i < items.length - 1)
              const Divider(height: 1, thickness: 1, color: AppColors.grey100, indent: 64),
          ],
        ],
      ),
    );
  }
}

// ── Private 위젯 ─────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String label;
  const _SectionHeader({required this.label});

  @override
  Widget build(BuildContext context) {
    // [DU244] 관리자 홈(S010)·관리자 설정(S045)과 같은 16 bold 본문색. 원문 그대로(짧은 낱말, 기존 시험·접근성이 원문으로 찾는다).
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.bold,
          color: AppColors.textPrimary,
        ),
      ),
    );
  }
}

class _MenuRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _MenuRow({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // [DU244] 아이콘은 중립 상자(S010·S045 와 같음) — 색으로 종류를 말하지 않는다. 눌림 표시는 묶음 카드가 자른다.
    //   [DU247] 진입 메뉴에는 위험색을 쓰지 않는다(위험색은 확인 대화 같은 확정 순간에만) — 위험 행 경로를 지웠다.
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        child: Row(
          children: [
            _IconBox(icon: icon),
            const SizedBox(width: 12),
            Expanded(child: _RowLabel(label)),
            const Icon(Icons.chevron_right,
                size: 18, color: AppColors.grey400), // [DU244] S010·S062 와 같음
          ],
        ),
      ),
    );
  }
}

/// [DU244 v2] 행 제목 — 14 w600. 큰 글자에서 줄이 바뀌면 낱말 단위로만 바꾼다(음절 끊김 금지). 읽기 도구에는 원문.
class _RowLabel extends StatelessWidget {
  final String text;

  const _RowLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      TextLayout.keepWords(text),
      semanticsLabel: text,
      style: const TextStyle(
          fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
    );
  }
}

/// [DU244] 행 아이콘 상자 — 관리자 홈(S010)·관리자 설정(S045)과 같은 36·반경 10·grey100 바탕·grey600 아이콘.
///   [DU247] 위험색 상자는 없앴다(진입 메뉴는 중립).
class _IconBox extends StatelessWidget {
  final IconData icon;

  const _IconBox({required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: AppColors.grey100,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(icon, color: AppColors.grey600, size: 18),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final Widget? trailing;

  const _InfoRow({
    required this.icon,
    required this.label,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      child: Row(
        children: [
          _IconBox(icon: icon), // [DU244] 메뉴 행과 같은 중립 상자
          const SizedBox(width: 12),
          Expanded(child: _RowLabel(label)),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

// [DU263] 약관 읽기 전용 화면은 공용 TermsReadOnlyScreen(lib/widgets/common/terms_read_only_screen.dart)으로 옮겼다.

// ══════════════════════════════════════════════════════════════════════
// [FC-01 OWNERSHIP FIX] 비밀번호 확인 다이얼로그 — 독립 StatefulWidget
// ══════════════════════════════════════════════════════════════════════

/// 회원탈퇴 시 현재 비밀번호를 입력받는 다이얼로그.
///
/// ## Controller Ownership Rule
/// `_ctrl`(TextEditingController)을 이 StatefulWidget의 State가 직접 소유하고
/// `State.dispose()`에서 해제한다.
///
/// 부모 메서드에서 controller를 생성한 뒤 `showDialog` 완료 직후 dispose하면
/// Dialog 종료 애니메이션 진행 중에 `DFSA.deactivate() → unfocus()` 마이크로태스크가
/// dispose된 controller에 접근하여 `TextEditingController was used after being disposed`
/// 크래시가 발생한다.
///
/// ## 결과 반환
/// 취소·hardware back → `null`, 탈퇴 확인 → 입력된 비밀번호 `String`.
class _WithdrawPasswordDialog extends StatefulWidget {
  const _WithdrawPasswordDialog();

  @override
  State<_WithdrawPasswordDialog> createState() => _WithdrawPasswordDialogState();
}

class _WithdrawPasswordDialogState extends State<_WithdrawPasswordDialog> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StyledDialog(
      title: '비밀번호 확인',
      subtitle: '탈퇴를 진행하려면 현재 비밀번호를 입력하세요',
      icon: Icons.lock_outline,
      headerColor: AppColors.error,
      content: StyledDialogTextField(
        controller: _ctrl,
        labelText: '현재 비밀번호',
        obscureText: true,
        autofocus: true,
        prefixIcon: Icons.lock_outline,
      ),
      actions: [
        StyledDialogButton.cancel(
          onPressed: () => Navigator.pop(context),
        ),
        StyledDialogButton.danger(
          text: '탈퇴',
          onPressed: () => Navigator.pop(context, _ctrl.text),
        ),
      ],
    );
  }
}
