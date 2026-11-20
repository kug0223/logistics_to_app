import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../providers/user_provider.dart';
import '../../providers/theme_provider.dart';
import '../../services/fcm_service.dart';
import 'all_businesses_screen.dart';
import 'all_users_screen.dart';
import '../../utils/dialog_helper.dart';
import '../../utils/responsive_helper.dart';
import '../common/settings_screen.dart';
import '../common/notification_screen.dart';
import 'system_settings_screen.dart';
import '../../theme/app_colors.dart';
import '../../utils/toast_helper.dart';
import '../../widgets/common/notification_badge.dart';
import '../../utils/text_layout.dart';
import '../../utils/format_helper.dart';

/// [DU240] 메뉴 행 한 줄 — 제목·설명·목적지. soon 이면 '준비 중' 표시(누르면 안내 toast).
typedef _MenuItem = ({IconData icon, String title, String subtitle, VoidCallback onTap, bool soon});

/// 최고관리자(SUPER_ADMIN) 홈 화면
///
/// [DU240] 시안·관리자 홈(S010)과 같은 시각 체계로 옮겼다.
///   파란 그라데이션 hero·둥근 회색 본문·작은 회색 섹션 라벨·떨어진 색 아이콘 타일 대신,
///   흰 머리(로고·이름·역할 배지·알림/로그아웃) → 화면 바탕 위 굵은 섹션 제목 → 흰 묶음 카드
///   (중립 아이콘 상자 + 제목/설명 + chevron, 행 사이 구분선)로 읽는다.
///   읽는 값(회원·사업장 count)·로딩 '-'·실패 '확인 못함'·목적지 5곳·로그아웃·FCM 소비·당겨서 새로고침은 그대로다.
class AdminHomeScreen extends StatefulWidget {
  const AdminHomeScreen({super.key});

  @override
  State<AdminHomeScreen> createState() => _AdminHomeScreenState();
}

class _AdminHomeScreenState extends State<AdminHomeScreen>
    with WidgetsBindingObserver {
  bool _isLoading = true;
  _SuperAdminStats? _stats;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadStats();
    // [Phase 9D] cold-start pending payload 소비
    WidgetsBinding.instance.addPostFrameCallback((_) {
      FCMService().consumePendingColdStartPayload();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 앱이 백그라운드에서 복귀할 때 통계 갱신
    if (state == AppLifecycleState.resumed) {
      _loadStats();
    }
  }

  Future<void> _loadStats() async {
    setState(() => _isLoading = true);
    try {
      final results = await Future.wait([
        FirebaseFirestore.instance.collection('users').count().get(),
        FirebaseFirestore.instance.collection('businesses').count().get(),
      ]);
      if (!mounted) return;
      setState(() {
        _stats = _SuperAdminStats(
          totalUsers: results[0].count ?? 0,
          totalBusinesses: results[1].count ?? 0,
        );
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('❌ 슈퍼관리자 통계 로드 실패: $e');
      if (!mounted) return;
      // [SA-AUDIT.49] 읽지 못한 것을 0명·0개로 말하지 않는다.
      setState(() {
        _stats = null;
        _isLoading = false;
      });
    }
  }

  /// [DU240] 묶음 카드 바탕 — 관리자 홈(S010 `_groupSurface`)과 같은 값: surface · radius 16 · grey200 1px · 그림자 없음.
  static final BoxDecoration _groupSurface = BoxDecoration(
    color: AppColors.surface,
    borderRadius: BorderRadius.circular(16),
    border: Border.all(color: AppColors.grey200, width: 1),
  );

  @override
  Widget build(BuildContext context) {
    return Selector<UserProvider, String?>(
      // [PERF] 이름 1개만 구독 — 다른 UserProvider 변경 시 rebuild 방지
      selector: (_, p) => p.currentUser?.name,
      builder: (context, userName, _) {
        final s = ResponsiveHelper.getScale(context);
        return Scaffold(
          backgroundColor: AppColors.background,
          body: SafeArea(
            bottom: false,
            child: RefreshIndicator(
              onRefresh: _loadStats,
              // [DU240] 머리도 본문과 함께 스크롤한다 — 큰 글자에서 고정 머리가 화면을 차지하지 않는다.
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.only(
                    bottom: ResponsiveHelper.listPadding(context, extra: 8 * s).bottom),
                children: [
                  _buildHeader(context, s, userName),
                  SizedBox(height: 20 * s),
                  _sectionHeader(s, '플랫폼 현황'),
                  SizedBox(height: 8 * s),
                  _buildStatsRow(context, s),
                  SizedBox(height: 24 * s),
                  _sectionHeader(s, '관리'),
                  SizedBox(height: 8 * s),
                  _group(context, s, [
                    (
                      icon: Icons.business_center_outlined,
                      title: '모든 사업장',
                      subtitle: '전체 사업장 현황 및 관리',
                      soon: false,
                      onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const AllBusinessesScreen()),
                          ),
                    ),
                    (
                      icon: Icons.people_outline,
                      title: '사용자 관리',
                      subtitle: '회원 목록 조회 및 정보 관리',
                      soon: false,
                      onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const AllUsersScreen()),
                          ),
                    ),
                  ]),
                  SizedBox(height: 24 * s),
                  _sectionHeader(s, '시스템'),
                  SizedBox(height: 8 * s),
                  _group(context, s, [
                    (
                      icon: Icons.admin_panel_settings_outlined,
                      title: '시스템 설정',
                      subtitle: '신뢰도 규칙·배지·임금·공고 설정 관리',
                      soon: false,
                      onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const SystemSettingsScreen()),
                          ),
                    ),
                  ]),
                  SizedBox(height: 24 * s),
                  _sectionHeader(s, '개인'),
                  SizedBox(height: 8 * s),
                  _group(context, s, [
                    (
                      icon: Icons.settings_outlined,
                      title: '설정',
                      subtitle: '개인 설정 및 테마',
                      soon: false,
                      onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const SettingsScreen()),
                          ),
                    ),
                  ]),
                  SizedBox(height: 24 * s),
                  _sectionHeader(s, '준비 중'),
                  SizedBox(height: 8 * s),
                  _group(context, s, [
                    (
                      icon: Icons.dashboard_outlined,
                      title: '공고 모니터링',
                      subtitle: '전체 공고 현황 분석',
                      soon: true,
                      onTap: () => ToastHelper.showInfo('공고 모니터링 기능은 준비 중입니다'),
                    ),
                    (
                      icon: Icons.analytics_outlined,
                      title: '전체 통계',
                      subtitle: '플랫폼 전체 통계 분석',
                      soon: true,
                      onTap: () => ToastHelper.showInfo('통계 기능은 준비 중입니다'),
                    ),
                  ]),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // ────────────────────────────────────────────────────────────
  //  헤더 — 흰 머리(관리자 홈 S010 과 같은 로고·버튼)
  // ────────────────────────────────────────────────────────────

  Widget _buildHeader(BuildContext context, double s, String? userName) {
    final name = '${userName ?? '관리자'}님';
    return Container(
      color: AppColors.surface,
      padding: EdgeInsets.fromLTRB(20 * s, 8 * s, 16 * s, 16 * s),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32 * s,
                height: 32 * s,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [AppColors.infoDark, AppColors.info],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                clipBehavior: Clip.hardEdge,
                child: Image.asset('assets/icons/app_icon_foreground.png',
                    width: 32 * s, height: 32 * s, fit: BoxFit.cover),
              ),
              SizedBox(width: 8 * s),
              Expanded(
                child: Text('ALfit',
                    style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        color: AppColors.infoDark,
                        letterSpacing: -0.6)),
              ),
              // 알림 벨
              // [.66] 화면 읽기에 이름·버튼 역할이 없었다('읽지 않은 알림 N건' 값만) — 배지 값은 그대로 두고 이름을 준다.
              NotificationBadge(
                child: _headerBtn(
                  s,
                  Icons.notifications_outlined,
                  label: '알림',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const NotificationScreen()),
                  ),
                ),
              ),
              SizedBox(width: 6 * s),
              // 로그아웃 — [.66] 화면 읽기에 이름이 없었다(노드 자체가 비어 있음).
              _headerBtn(
                s,
                Icons.logout,
                label: '로그아웃',
                onTap: () async {
                  final confirmed = await DialogHelper.showLogoutConfirm(context);
                  if (confirmed && context.mounted) {
                    // signOut 먼저: 실패 시 ThemeProvider.reset() 호출 방지
                    await context.read<UserProvider>().signOut();
                    if (context.mounted) {
                      context.read<ThemeProvider>().reset();
                    }
                  }
                },
              ),
            ],
          ),
          SizedBox(height: 12 * s),
          // 이름 + 역할 배지 — 긴 이름은 낱말 단위로 줄을 바꾼다(말줄임 없음). 좁으면 배지가 다음 줄로 간다.
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8 * s,
            runSpacing: 6 * s,
            children: [
              Text(
                TextLayout.keepWords(name),
                semanticsLabel: name,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                  letterSpacing: -0.3,
                ),
              ),
              _roleBadge(context, s),
            ],
          ),
        ],
      ),
    );
  }

  /// [DU240] 머리 버튼 — S010 `_headerBtn` 과 같은 회색 사각, 누르는 영역은 48×48 이상(아이콘 크기는 그대로).
  Widget _headerBtn(double s, IconData icon,
      {required String label, required VoidCallback onTap}) {
    return Semantics(
      button: true,
      label: label,
      child: Material(
        color: AppColors.grey100,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            child: Center(
              widthFactor: 1,
              heightFactor: 1,
              child: Padding(
                padding: EdgeInsets.all(8 * s),
                child: Icon(icon, color: AppColors.textSecondary, size: 22 * s),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// [DU240] 역할 배지 — S010 `_adminBadge` 와 같은 모양('관리자' → '최고관리자').
  Widget _roleBadge(BuildContext context, double s) {
    final color = Theme.of(context).primaryColor;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 10 * s, vertical: 4 * s),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.25), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.admin_panel_settings_outlined, color: color, size: 12 * s),
          SizedBox(width: 4 * s),
          Text('최고관리자',
              style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  // ────────────────────────────────────────────────────────────
  //  섹션 제목 · 통계 · 묶음 카드
  // ────────────────────────────────────────────────────────────

  Widget _sectionHeader(double s, String title) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 20 * s),
      child: Text(
        TextLayout.keepWords(title),
        semanticsLabel: title,
        style: TextStyle(
            fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
      ),
    );
  }

  Widget _buildStatsRow(BuildContext context, double s) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 16 * s),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: _statCard(
                s,
                label: '전체 회원',
                value: _isLoading ? '-' : (_stats == null ? '확인 못함' : '${FormatHelper.formatNumber(_stats!.totalUsers)}명'),
                icon: Icons.people_outline,
              ),
            ),
            SizedBox(width: 8 * s),
            Expanded(
              child: _statCard(
                s,
                label: '전체 사업장',
                value: _isLoading ? '-' : (_stats == null ? '확인 못함' : '${FormatHelper.formatNumber(_stats!.totalBusinesses)}개'),
                icon: Icons.business_outlined,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// [DU240] 통계 값 — 숫자로 시작하면 TextLayout.amount(쉼표 뒤에서만 줄바꿈), 그 밖('확인 못함'·'-')은 낱말 단위.
  static String _statText(String v) =>
      v.isNotEmpty && '0123456789'.contains(v[0]) ? TextLayout.amount(v) : TextLayout.keepWords(v);

  Widget _statCard(
    double s, {
    required String label,
    required String value,
    required IconData icon,
  }) {
    // 아는 값만 굵은 본문색 — 로딩 '-'·실패 '확인 못함'은 보조색으로 0 이나 값처럼 보이지 않게 한다.
    final known = !_isLoading && _stats != null;
    return Container(
      decoration: _groupSurface,
      padding: EdgeInsets.fromLTRB(14 * s, 12 * s, 14 * s, 12 * s),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(icon, size: 16 * s, color: AppColors.grey600),
              SizedBox(width: 6 * s),
              Flexible(
                child: Text(
                  TextLayout.keepWords(label),
                  semanticsLabel: label,
                  style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                ),
              ),
            ],
          ),
          SizedBox(height: 6 * s),
          Text(
            _statText(value),
            semanticsLabel: value,
            style: TextStyle(
              fontSize: known ? 20 : 15,
              fontWeight: known ? FontWeight.w800 : FontWeight.w600,
              color: known ? AppColors.textPrimary : AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  /// [DU240] 묶음 카드 — 관리자 홈 '처리할 일'과 같은 흰 카드 하나에 행을 구분선으로 잇는다.
  Widget _group(BuildContext context, double s, List<_MenuItem> items) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 16 * s),
      child: Material(
        color: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppColors.grey200),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            for (var i = 0; i < items.length; i++)
              _menuRow(context, s, items[i], isLast: i == items.length - 1),
          ],
        ),
      ),
    );
  }

  /// [DU240] 메뉴 설명 — 낱말 안에서는 끊지 않고, 가운뎃점(·) 뒤에서는 줄을 바꿀 수 있다
  ///   ('신뢰도 규칙·배지·임금·공고'가 한 줄보다 길 때 글자 중간이 아니라 '·' 뒤에서 바뀐다).
  ///   화면 전용 문자는 TextLayout.plain 이 지우므로 semanticsLabel 은 원문 그대로다.
  static String _menuText(String s) =>
      s.split('·').map(TextLayout.keepWords).join('·${String.fromCharCode(0x200B)}');

  /// [DU240] 메뉴 행 — S010 처리할 일 행과 같은 중립 아이콘 상자(grey100·radius 10·36) + 제목 15 w600 + 설명 12.
  ///   준비 중이면 chevron 대신 '준비 중' 표시를 두고, 누르면 지금처럼 안내 toast 를 띄운다.
  Widget _menuRow(BuildContext context, double s, _MenuItem it, {required bool isLast}) {
    return Column(
      children: [
        InkWell(
          onTap: it.onTap,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 16 * s, vertical: 13 * s),
            child: Row(
              children: [
                Container(
                  width: 36 * s,
                  height: 36 * s,
                  decoration: BoxDecoration(
                    color: AppColors.grey100,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(it.icon,
                      size: 18 * s, color: it.soon ? AppColors.grey400 : AppColors.grey600),
                ),
                SizedBox(width: 12 * s),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        TextLayout.keepWords(it.title),
                        semanticsLabel: it.title,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: it.soon ? AppColors.textSecondary : AppColors.textPrimary,
                        ),
                      ),
                      SizedBox(height: 2 * s),
                      Text(
                        _menuText(it.subtitle),
                        semanticsLabel: it.subtitle,
                        style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                ),
                SizedBox(width: 8 * s),
                if (it.soon)
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 8 * s, vertical: 3 * s),
                    decoration: BoxDecoration(
                      color: AppColors.grey100,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text('준비 중',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textSecondary)),
                  )
                else
                  Icon(Icons.chevron_right, size: 18 * s, color: AppColors.grey400),
              ],
            ),
          ),
        ),
        if (!isLast)
          Padding(
            padding: EdgeInsets.only(left: 64 * s),
            child: const Divider(height: 1, thickness: 1, color: AppColors.grey100),
          ),
      ],
    );
  }
}

// ──────────────────────────────────────────────────────────────
//  데이터 모델
// ──────────────────────────────────────────────────────────────

class _SuperAdminStats {
  final int totalUsers;
  final int totalBusinesses;

  const _SuperAdminStats({
    required this.totalUsers,
    required this.totalBusinesses,
  });
}
