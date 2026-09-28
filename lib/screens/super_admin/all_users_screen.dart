import 'package:flutter/material.dart';
// [R7-P1-7 P17-A] GradientScaffold → AppPageScaffold(D0 flat admin shell).
//   이 화면의 Colors.white 는 전부 **본문**이다(버튼 전경색·전체화면 이미지 뷰어
//   오버레이) — 헤더에 의존하는 색이 없어 위젯 이름만 바뀐다. 가로 스크롤 표의
//   열·행동·현재 선택 접근성은 좁은 폭 렌더로 따로 확인한다.
import 'package:cloud_functions/cloud_functions.dart';
import 'package:provider/provider.dart';
import 'all_users_reads.dart';
import '../../models/core/user_model.dart';
import '../../providers/user_provider.dart';
import '../../theme/app_colors.dart';
import '../../utils/responsive_helper.dart';
import '../../utils/toast_helper.dart';
import '../../utils/dialog_helper.dart';
import '../../utils/format_helper.dart';
import '../../widgets/common/app_empty_state.dart';
import '../../widgets/common/app_page_scaffold.dart';
import '../../widgets/common/loading_widget.dart';
import '../../utils/loading_state_mixin.dart';
// badge_service, flutter/services: [5A.2A] trustScore 관련 제거로 불필요
import '../../widgets/dialogs/styled_dialog.dart';

/// 모든 사용자 조회·관리 화면 (최고관리자 전용)
class AllUsersScreen extends StatefulWidget {
  const AllUsersScreen({super.key, this.reads});

  /// [R7-P3-2 P32-X1] 목록을 만드는 읽기 경계. production 은 null.
  final AllUsersReads? reads;

  @override
  State<AllUsersScreen> createState() => _AllUsersScreenState();
}

class _AllUsersScreenState extends State<AllUsersScreen>
    with LoadingStateMixin {
  late final AllUsersReads _reads = widget.reads ?? AllUsersReads.of();
  List<UserModel> _users = [];
  Object? _loadError;
  String _roleFilter = 'ALL';
  String _searchQuery = '';
  List<UserModel> _cachedFiltered = []; // 필터 결과 캐시 — build()마다 재계산 방지
  bool _isProcessing = false;
  final _searchController = TextEditingController();

  static const _roleLabels = {
    'ALL': '전체',
    'USER': '지원자',
    'BUSINESS_ADMIN': '관리자',
    'SUPER_ADMIN': '슈퍼관리자',
  };

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text.trim().toLowerCase();
        _rebuildFilter();
      });
    });
    // 방어 심층화: AuthWrapper 분기 외 2차 역할 확인 (context는 postFrameCallback에서만 안전하게 접근)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!context.read<UserProvider>().isSuperAdmin) {
        Navigator.pop(context);
        return;
      }
      _loadAllUsers();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadAllUsers() async {
    setLoading(true);
    if (mounted) setState(() => _loadError = null);
    try {
      final rawList = await _reads.allUsersRaw();

      if (!mounted) return;
      final users = rawList.whereType<Map>().map((data) {
        try {
          final d = Map<String, dynamic>.from(data);
          final uid = d['uid'] as String? ?? '';
          return UserModel.fromMap(d, uid);
        } catch (_) { return null; }
      }).whereType<UserModel>().toList();
      setState(() { _users = users; _rebuildFilter(); });
      setLoading(false);
    } catch (e) {
      if (!mounted) return;
      // [R7-P3-2 P32-X1] 조회 실패를 **대상 없음**으로 말하지 않는다.
      //   토스트는 사라지고 화면에는 `해당하는 사용자가 없습니다` 만 남았다 —
      //   문의 대상이 정말 없는 것과 못 읽은 것은 다른 사실이다.
      ToastHelper.showError('사용자 목록 불러오기 실패: $e');
      setState(() => _loadError = e);
      setLoading(false);
    }
  }

  /// _users / _roleFilter / _searchQuery 변경 시 호출 — build()마다 재계산하지 않음
  void _rebuildFilter() {
    var list = _roleFilter == 'ALL'
        ? _users
        : _users.where((u) => u.role.name == _roleFilter).toList();

    if (_searchQuery.isNotEmpty) {
      list = list.where((u) {
        final name = u.name.toLowerCase();
        final username = u.username.toLowerCase();
        final phone = u.effectivePhone?.toLowerCase() ?? '';
        return name.contains(_searchQuery) ||
            username.contains(_searchQuery) ||
            phone.contains(_searchQuery);
      }).toList();
    }
    _cachedFiltered = list;
  }

  // ── 관리 액션 ───────────────────────────────────────────────────

  /// [R7-P3-3 P33-X1] 쓰기 직전 **대상을 다시 말한다**.
  ///
  ///   상세 시트는 확인창을 띄우기 전에 `Navigator.pop` 으로 닫힌다. 그래서
  ///   시트 안에만 있던 `@아이디` 가 정작 실행 직전에는 사라져 있었고,
  ///   이름이 같은 계정이면 확인창 문구가 **글자 하나 다르지 않았다**.
  ///   목록 행에 긴 식별자를 강제하지 않고, 되돌릴 수 없는 순간에만 붙인다.
  ///   연락처·신분번호는 더하지 않는다 — 이미 상세에 있는 정보만 옮긴다.
  String _targetLine(UserModel u) {
    final role = switch (u.role) {
      UserRole.SUPER_ADMIN => '슈퍼관리자',
      UserRole.BUSINESS_ADMIN => '사업장관리자',
      UserRole.USER => '지원자',
    };
    final biz = u.businessName;
    return '${u.name} · @${u.username} · $role'
        '${biz != null && biz.isNotEmpty ? ' · $biz' : ''}';
  }

  Future<void> _toggleBlacklist(UserModel user) async {
    if (_isProcessing) return;
    if (user.isBlacklisted) {
      final confirmed = await DialogHelper.showDangerConfirm(
        context,
        title: '블랙리스트 해제',
        message: '${_targetLine(user)}\n\n이 계정의 블랙리스트를 해제하시겠습니까?\n해제 후 로그인이 가능해집니다.',
        confirmText: '해제',
      );
      if (!confirmed || !mounted) return;
      setState(() => _isProcessing = true);

      try {
        await FirebaseFunctions.instanceFor(region: 'asia-northeast3')
            .httpsCallable('callableUnblacklistUser')
            .call({'targetUid': user.uid});
        if (!mounted) return;
        ToastHelper.showSuccess('블랙리스트가 해제되었습니다');
        await _loadAllUsers();
      } catch (e) {
        if (mounted) ToastHelper.showError('처리 실패: $e');
      } finally {
        if (mounted) setState(() => _isProcessing = false);
      }
    } else {
      // 등록: 사유 입력
      final reason = await _showReasonDialog(
        subject: _targetLine(user),
        title: '블랙리스트 등록',
        hint: '예: 반복 노쇼, 사기 피해 신고, 이용 약관 위반 등',
        confirmLabel: '등록',
        confirmColor: AppColors.error,
      );
      if (reason == null || !mounted) return;
      setState(() => _isProcessing = true);

      try {
        await FirebaseFunctions.instanceFor(region: 'asia-northeast3')
            .httpsCallable('callableBlacklistUser')
            .call({'targetUid': user.uid, 'blacklistReason': reason});
        if (!mounted) return;
        ToastHelper.showSuccess('블랙리스트에 등록되었습니다');
        await _loadAllUsers();
      } catch (e) {
        if (mounted) ToastHelper.showError('처리 실패: $e');
      } finally {
        if (mounted) setState(() => _isProcessing = false);
      }
    }
  }

  Future<void> _clearRestriction(UserModel user) async {
    if (_isProcessing) return;
    final restrictedUntil = user.restrictedUntil;
    if (restrictedUntil == null) return;

    final isPermanent = restrictedUntil.year >= 9999;
    final restrictionText = isPermanent
        ? '영구 이용 제한 중'
        : '${FormatHelper.formatDateISO(restrictedUntil)}까지 제한 중';

    final confirmed = await DialogHelper.showDangerConfirm(
      context,
      title: '제재 해제',
      message: '${_targetLine(user)}\n\n이 계정의 제재를 해제하시겠습니까?\n현재: $restrictionText\n해제 후 즉시 이용 가능해집니다.',
      confirmText: '해제',
    );
    if (!confirmed || !mounted) return;
    setState(() => _isProcessing = true);

    try {
      await FirebaseFunctions.instanceFor(region: 'asia-northeast3')
          .httpsCallable('callableResetPenalty')
          .call({'targetUid': user.uid});
      if (!mounted) return;
      ToastHelper.showSuccess('제재가 해제되었습니다');
      await _loadAllUsers();
    } catch (e) {
      if (mounted) ToastHelper.showError('처리 실패: $e');
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  // [5A.2A] _adjustTrustScore 제거 — callableAdjustTrustScore 폐기

  Future<String?> _showReasonDialog({
    required String subject,
    required String title,
    required String hint,
    required String confirmLabel,
    required Color confirmColor,
  }) {
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _ReasonDialog(
        subject: subject,
        title: title,
        hint: hint,
        confirmLabel: confirmLabel,
        confirmColor: confirmColor,
      ),
    );
  }

  // ── 사용자 상세 바텀시트 ────────────────────────────────────────

  void _showUserDetailSheet(UserModel user) {
    // DraggableScrollableSheet는 backgroundColor: transparent 필수 →
    // CLAUDE.md 허용 예외: showModalBottomSheet 직접 호출
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _UserDetailSheet(
        user: user,
        onToggleBlacklist: () {
          Navigator.pop(ctx);
          _toggleBlacklist(user);
        },
        onClearRestriction: () {
          Navigator.pop(ctx);
          _clearRestriction(user);
        },
        // [5A.2A] onAdjustTrustScore 제거
      ),
    );
  }

  // ── UI ─────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return AppPageScaffold(
      title: '전체 사용자 관리 (${_users.length}명)',
      // [R7-P1-7 P17-A] 헤더 새로고침 → flat shell 의 actions (행동 동일).
      actions: [
        IconButton(
          icon: const Icon(Icons.refresh_rounded),
          color: AppColors.textSecondary,
          tooltip: '새로고침',
          onPressed: _loadAllUsers,
        ),
      ],
      body: Column(
        children: [
          _buildSearchBar(),
          _buildRoleFilter(),
          Expanded(
            child: Builder(builder: (context) {
              if (isLoading) return const LoadingWidget(message: '사용자 목록을 불러오는 중...');
              final filtered = _cachedFiltered;
              return filtered.isEmpty ? _buildEmptyState() : _buildUserList(filtered);
            }),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        ResponsiveHelper.spacing(context, 16),
        ResponsiveHelper.spacing(context, 8),
        ResponsiveHelper.spacing(context, 16),
        0,
      ),
      child: TextField(
        controller: _searchController,
        decoration: InputDecoration(
          hintText: '이름 · 아이디 · 연락처 검색',
          prefixIcon: const Icon(Icons.search),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () => _searchController.clear(),
                )
              : null,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          contentPadding: EdgeInsets.symmetric(
            vertical: ResponsiveHelper.spacing(context, 10),
          ),
        ),
      ),
    );
  }

  Widget _buildRoleFilter() {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 16),
        vertical: ResponsiveHelper.spacing(context, 8),
      ),
      color: Theme.of(context).colorScheme.surface,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: _roleLabels.entries.map((e) {
            final active = _roleFilter == e.key;
            final count = e.key == 'ALL'
                ? _users.length
                : _users.where((u) => u.role.name == e.key).length;
            return Padding(
              padding: EdgeInsets.only(right: ResponsiveHelper.spacing(context, 8)),
              child: FilterChip(
                label: Text('${e.value} ($count)'),
                selected: active,
                onSelected: (_) => setState(() { _roleFilter = e.key; _rebuildFilter(); }),
                selectedColor: AppColors.errorDark.withValues(alpha: 0.15),
                checkmarkColor: AppColors.errorDark,
                labelStyle: ResponsiveHelper.smallStyle(
                  context,
                  color: active ? AppColors.errorDark : null,
                ).copyWith(fontWeight: active ? FontWeight.bold : null),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    // [R7-P3-2 P32-X1] 못 읽은 것은 없는 것이 아니다.
    if (_loadError != null) {
      return AppEmptyState(
        icon: Icons.error_outline,
        title: '사용자 목록을 불러오지 못했습니다',
        subtitle: '해당하는 사용자가 없다는 뜻이 아닙니다.',
        action: TextButton(
          onPressed: _loadAllUsers,
          child: const Text('다시 시도'),
        ),
      );
    }
    return const AppEmptyState(
      icon: Icons.people_outline,
      title: '해당하는 사용자가 없습니다',
    );
  }

  Widget _buildUserList(List<UserModel> list) {
    return RefreshIndicator(
      onRefresh: _loadAllUsers,
      child: ListView.builder(
        padding: ResponsiveHelper.listPadding(context),
        itemCount: list.length,
        itemBuilder: (context, i) => _buildUserCard(list[i]),
      ),
    );
  }

  Widget _buildUserCard(UserModel user) {
    final roleColor = switch (user.role) {
      UserRole.SUPER_ADMIN => AppColors.error,
      UserRole.BUSINESS_ADMIN => AppColors.purple,
      UserRole.USER => AppColors.success,
    };
    final roleLabel = switch (user.role) {
      UserRole.SUPER_ADMIN => '슈퍼관리자',
      UserRole.BUSINESS_ADMIN => '사업장관리자',
      UserRole.USER => '지원자',
    };

    return Card(
      margin: EdgeInsets.only(bottom: ResponsiveHelper.spacing(context, 10)),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 1,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _showUserDetailSheet(user),
        child: Padding(
          padding: ResponsiveHelper.cardPadding(context),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: user.isBlacklisted
                    ? AppColors.error.withValues(alpha: 0.12)
                    : roleColor.withValues(alpha: 0.12),
                child: Icon(
                  user.isBlacklisted ? Icons.block : Icons.person,
                  color: user.isBlacklisted ? AppColors.error : roleColor,
                ),
              ),
              SizedBox(width: ResponsiveHelper.spacing(context, 12)),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            user.name,
                            style: ResponsiveHelper.bodyStyle(context)
                                .copyWith(fontWeight: FontWeight.bold),
                          ),
                        ),
                        Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: ResponsiveHelper.spacing(context, 8),
                            vertical: ResponsiveHelper.spacing(context, 3),
                          ),
                          decoration: BoxDecoration(
                            color: roleColor.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: roleColor),
                          ),
                          child: Text(
                            roleLabel,
                            style: ResponsiveHelper.tinyStyle(context, color: roleColor)
                                .copyWith(fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: ResponsiveHelper.spacing(context, 4)),
                    if (user.effectivePhone != null)
                      Text(
                        user.effectivePhone!,
                        style: ResponsiveHelper.smallStyle(
                          context,
                          color: Theme.of(context).textTheme.bodyMedium?.color,
                        ),
                      ),
                    // 상태 칩 행
                    Row(
                      children: [
                        // 신뢰도 텍스트: Flexible 필수 — 칩 3개 동시 표시 시 360dp overflow 방지
                        Flexible(
                          child: Text(
                            '${user.totalWorkDays}일 근무',
                            style: ResponsiveHelper.tinyStyle(
                              context,
                              color: Theme.of(context).textTheme.bodySmall?.color,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (user.isBlacklisted) ...[
                          SizedBox(width: ResponsiveHelper.spacing(context, 6)),
                          _miniChip('블랙리스트', AppColors.error),
                        ],
                        if (user.isRestricted) ...[
                          SizedBox(width: ResponsiveHelper.spacing(context, 6)),
                          _miniChip('제재중', AppColors.warning),
                        ],
                        if (user.isPending) ...[
                          SizedBox(width: ResponsiveHelper.spacing(context, 6)),
                          _miniChip('승인대기', AppColors.info),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
                color: AppColors.grey400,
                size: ResponsiveHelper.iconSize(context, 18),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _miniChip(String label, Color color) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 6),
        vertical: ResponsiveHelper.spacing(context, 1),
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: ResponsiveHelper.tinyStyle(context, color: color)
            .copyWith(fontWeight: FontWeight.bold),
      ),
    );
  }
}

// ── 사용자 상세 바텀시트 ─────────────────────────────────────────

class _UserDetailSheet extends StatelessWidget {
  final UserModel user;
  final VoidCallback onToggleBlacklist;
  final VoidCallback onClearRestriction;

  const _UserDetailSheet({
    required this.user,
    required this.onToggleBlacklist,
    required this.onClearRestriction,
  });

  @override
  Widget build(BuildContext context) {
    final roleColor = switch (user.role) {
      UserRole.SUPER_ADMIN => AppColors.error,
      UserRole.BUSINESS_ADMIN => AppColors.purple,
      UserRole.USER => AppColors.success,
    };
    final roleLabel = switch (user.role) {
      UserRole.SUPER_ADMIN => '슈퍼관리자',
      UserRole.BUSINESS_ADMIN => '사업장관리자',
      UserRole.USER => '지원자',
    };

    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (ctx, controller) => Column(
        children: [
          // 핸들
          Center(
            child: Container(
              margin: EdgeInsets.symmetric(
                vertical: ResponsiveHelper.spacing(context, 12),
              ),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.grey300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          // 헤더
          Padding(
            padding: EdgeInsets.symmetric(
              horizontal: ResponsiveHelper.spacing(context, 20),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: ResponsiveHelper.spacing(context, 22),
                  backgroundColor: roleColor.withValues(alpha: 0.12),
                  child: Icon(Icons.person, color: roleColor, size: ResponsiveHelper.iconSize(context, 24)),
                ),
                SizedBox(width: ResponsiveHelper.spacing(context, 12)),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        user.name,
                        style: ResponsiveHelper.titleStyle(context)
                            .copyWith(fontWeight: FontWeight.bold),
                      ),
                      Text(
                        '@${user.username} · $roleLabel',
                        style: ResponsiveHelper.smallStyle(context, color: AppColors.grey500),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: ResponsiveHelper.spacing(context, 10),
                    vertical: ResponsiveHelper.spacing(context, 4),
                  ),
                  decoration: BoxDecoration(
                    color: roleColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: roleColor.withValues(alpha: 0.4)),
                  ),
                  child: Text(
                    roleLabel,
                    style: ResponsiveHelper.smallStyle(context, color: roleColor)
                        .copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),
          Divider(height: ResponsiveHelper.spacing(context, 24)),
          Expanded(
            child: ListView(
              controller: controller,
              padding: EdgeInsets.symmetric(
                horizontal: ResponsiveHelper.spacing(context, 20),
              ),
              children: [
                // 기본 정보
                _sectionTitle(context, '기본 정보'),
                _infoRow(context, Icons.phone_outlined, '연락처', user.effectivePhone ?? '-'),
                _infoRow(context, Icons.cake_outlined, '생년월일',
                  user.birthDate != null ? FormatHelper.formatDateISO(user.birthDate!) : '-'),
                _infoRow(context, Icons.person_outline, '성별', user.gender ?? '-'),
                if (user.businessName != null)
                  _infoRow(context, Icons.business_outlined, '사업체명', user.businessName!),
                _infoRow(context, Icons.calendar_today_outlined, '가입일',
                  user.createdAt != null ? FormatHelper.formatDateISO(user.createdAt!) : '-'),

                SizedBox(height: ResponsiveHelper.spacing(context, 16)),

                // 신뢰도 & 근무 통계
                _sectionTitle(context, '신뢰도 & 근무'),
                _statsGrid(context),

                SizedBox(height: ResponsiveHelper.spacing(context, 16)),

                // 현재 상태
                _sectionTitle(context, '계정 상태'),
                if (user.isBlacklisted)
                  _statusCard(
                    context,
                    icon: Icons.block,
                    color: AppColors.error,
                    label: '블랙리스트',
                    description: user.blacklistReason ?? '사유 없음',
                  ),
                if (user.isRestricted)
                  _statusCard(
                    context,
                    icon: Icons.timer_off_outlined,
                    color: AppColors.warning,
                    label: '이용 제한 중',
                    description: user.restrictedUntil!.year >= 9999
                        ? '영구 제한'
                        : '~${FormatHelper.formatDateISO(user.restrictedUntil!)}',
                  ),
                if (user.isPending)
                  _statusCard(
                    context,
                    icon: Icons.hourglass_top_outlined,
                    color: AppColors.info,
                    label: '가입 승인 대기',
                    description: '슈퍼관리자 승인 필요 (외국인 계정)',
                  ),
                if (!user.isBlacklisted && !user.isRestricted && !user.isPending)
                  _statusCard(
                    context,
                    icon: Icons.check_circle_outline,
                    color: AppColors.success,
                    label: '정상',
                    description: '이용 제한 없음',
                  ),

                SizedBox(height: ResponsiveHelper.spacing(context, 20)),

                // 관리 액션
                _sectionTitle(context, '관리 액션'),
                SizedBox(height: ResponsiveHelper.spacing(context, 8)),

                // SUPER_ADMIN 계정에 블랙리스트 버튼 노출 금지 — 자기 자신 또는 동급 계정 차단 방지
                if (user.role != UserRole.SUPER_ADMIN)
                  _actionButton(
                    context,
                    icon: user.isBlacklisted ? Icons.lock_open : Icons.block,
                    label: user.isBlacklisted ? '블랙리스트 해제' : '블랙리스트 등록',
                    color: AppColors.error,
                    onTap: onToggleBlacklist,
                    outlined: user.isBlacklisted,
                  ),

                if (user.isRestricted) ...[
                  SizedBox(height: ResponsiveHelper.spacing(context, 8)),
                  _actionButton(
                    context,
                    icon: Icons.timer_off_outlined,
                    label: '제재 해제 (노쇼 카운트 초기화)',
                    color: AppColors.warning,
                    onTap: onClearRestriction,
                    outlined: true,
                  ),
                ],

                SizedBox(height: ResponsiveHelper.spacing(context, 24)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(BuildContext context, String title) {
    return Padding(
      padding: EdgeInsets.only(bottom: ResponsiveHelper.spacing(context, 8)),
      child: Text(
        title,
        style: ResponsiveHelper.subtitleStyle(context).copyWith(
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _infoRow(BuildContext context, IconData icon, String label, String value) {
    return Padding(
      padding: EdgeInsets.only(bottom: ResponsiveHelper.spacing(context, 8)),
      child: Row(
        children: [
          Icon(icon, size: ResponsiveHelper.iconSize(context, 16), color: AppColors.grey400),
          SizedBox(width: ResponsiveHelper.spacing(context, 8)),
          SizedBox(
            width: ResponsiveHelper.spacing(context, 64),
            child: Text(
              label,
              style: ResponsiveHelper.smallStyle(context, color: AppColors.grey500),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: ResponsiveHelper.smallStyle(
                context,
                color: Theme.of(context).textTheme.bodyMedium?.color,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _statsGrid(BuildContext context) {
    final items = [
      ('총 근무', '${user.totalWorkDays}일', AppColors.success),
      ('노쇼', '${user.noShowCount}회', user.noShowCount > 0 ? AppColors.error : AppColors.grey400),
      ('지각(90일)', '${user.recentLateCount}회', user.recentLateCount > 3 ? AppColors.warning : AppColors.grey400),
      ('평점', user.averageRating > 0 ? '${user.averageRating.toStringAsFixed(1)}점' : '-', AppColors.purple),
      ('리뷰', '${user.reviewCount}건', AppColors.info),
    ];

    // [R7-P3-3 P33-X1] 타일 비율이 2.2 로 고정이라 글자 배율을 키우면 값·라벨
    //   두 줄이 타일보다 커졌다 — 320dp · 배율 2.0 에서 아래로 70~104px 넘쳤다.
    //   이 시트는 조치 대상을 확인하는 자리라 수치를 지우지 않는다. 대신
    //   글자가 커진 만큼 타일을 낮춘다.
    final textScale = MediaQuery.textScalerOf(context).scale(1.0);
    final ratio = (2.2 / (textScale <= 0 ? 1.0 : textScale)).clamp(1.0, 2.2);

    return GridView.count(
      crossAxisCount: 3,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: ResponsiveHelper.spacing(context, 8),
      crossAxisSpacing: ResponsiveHelper.spacing(context, 8),
      childAspectRatio: ratio,
      children: items.map((item) {
        final (label, value, color) = item;
        return Container(
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: ResponsiveHelper.bodyStyle(context).copyWith(
                  color: color,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: ResponsiveHelper.tinyStyle(context, color: AppColors.grey500),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _statusCard(
    BuildContext context, {
    required IconData icon,
    required Color color,
    required String label,
    required String description,
  }) {
    return Container(
      margin: EdgeInsets.only(bottom: ResponsiveHelper.spacing(context, 8)),
      padding: ResponsiveHelper.cardPadding(context),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: ResponsiveHelper.iconSize(context, 20)),
          SizedBox(width: ResponsiveHelper.spacing(context, 10)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: ResponsiveHelper.bodyStyle(context).copyWith(
                    color: color,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  description,
                  style: ResponsiveHelper.smallStyle(context, color: AppColors.grey600),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionButton(
    BuildContext context, {
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
    bool outlined = false,
  }) {
    return SizedBox(
      width: double.infinity,
      child: outlined
          ? OutlinedButton.icon(
              onPressed: onTap,
              icon: Icon(icon, size: ResponsiveHelper.iconSize(context, 18)),
              label: Text(label),
              style: OutlinedButton.styleFrom(
                foregroundColor: color,
                side: BorderSide(color: color),
                padding: EdgeInsets.symmetric(
                  vertical: ResponsiveHelper.spacing(context, 12),
                ),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            )
          : ElevatedButton.icon(
              onPressed: onTap,
              icon: Icon(icon, size: ResponsiveHelper.iconSize(context, 18)),
              label: Text(label),
              style: ElevatedButton.styleFrom(
                backgroundColor: color,
                foregroundColor: Colors.white,
                padding: EdgeInsets.symmetric(
                  vertical: ResponsiveHelper.spacing(context, 12),
                ),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                elevation: 0,
              ),
            ),
    );
  }
}

// [5A.2A] _TrustScoreDialog 제거 — 신뢰도 점수 시스템 폐기

// ── 사유 입력 다이얼로그 (블랙리스트/제재) ──────────────────────────────
class _ReasonDialog extends StatefulWidget {
  /// [R7-P3-3 P33-X1] 되돌리기 어려운 쓰기의 **대상**. 제목만으로는
  ///   누구에게 하는 일인지 알 수 없었다.
  final String subject;
  final String title;
  final String hint;
  final String confirmLabel;
  final Color confirmColor;

  const _ReasonDialog({
    required this.subject,
    required this.title,
    required this.hint,
    required this.confirmLabel,
    required this.confirmColor,
  });

  @override
  State<_ReasonDialog> createState() => _ReasonDialogState();
}

class _ReasonDialogState extends State<_ReasonDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StyledDialog(
      title: widget.title,
      icon: Icons.edit_note_outlined,
      headerColor: widget.confirmColor,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // [R7-P3-3 P33-X1] 대상 먼저 — 이름이 같은 계정이 있어도 여기서 갈린다.
          Text(
            widget.subject,
            style: ResponsiveHelper.smallStyle(context,
                    color: AppColors.grey700)
                .copyWith(fontWeight: FontWeight.bold),
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 10)),
          StyledDialogTextField(
            controller: _controller,
            labelText: '사유',
            hintText: widget.hint,
            prefixIcon: Icons.notes_outlined,
            maxLines: 3,
            maxLength: 500,
            autofocus: true,
          ),
        ],
      ),
      actions: [
        // [FC-06 FIX] autofocus: true — cancel도 unfocus 필수
        StyledDialogButton.cancel(onPressed: () {
          FocusManager.instance.primaryFocus?.unfocus();
          Navigator.pop(context);
        }),
        StyledDialogButton(
          text: widget.confirmLabel,
          onPressed: () {
            if (_controller.text.trim().isEmpty) {
              ToastHelper.showError('사유를 입력하세요');
              return;
            }
            // [FC-06 FIX] confirm도 unfocus 후 pop
            FocusManager.instance.primaryFocus?.unfocus();
            Navigator.pop(context, _controller.text.trim());
          },
          backgroundColor: widget.confirmColor,
          foregroundColor: Colors.white,
        ),
      ],
    );
  }
}
