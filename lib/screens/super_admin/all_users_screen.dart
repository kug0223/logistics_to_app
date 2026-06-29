import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import '../../models/core/user_model.dart';
import '../../providers/user_provider.dart';
import '../../theme/app_colors.dart';
import '../../utils/responsive_helper.dart';
import '../../utils/toast_helper.dart';
import '../../utils/dialog_helper.dart';
import '../../utils/format_helper.dart';
import '../../widgets/common/app_empty_state.dart';
import '../../widgets/common/gradient_scaffold.dart';
import '../../widgets/common/loading_widget.dart';
import '../../utils/loading_state_mixin.dart';
import '../../services/badge_service.dart';

/// 모든 사용자 조회·관리 화면 (최고관리자 전용)
class AllUsersScreen extends StatefulWidget {
  const AllUsersScreen({super.key});

  @override
  State<AllUsersScreen> createState() => _AllUsersScreenState();
}

class _AllUsersScreenState extends State<AllUsersScreen>
    with LoadingStateMixin {
  final _firestore = FirebaseFirestore.instance;

  List<UserModel> _users = [];
  String _roleFilter = 'ALL';
  String _searchQuery = '';
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
      setState(() => _searchQuery = _searchController.text.trim().toLowerCase());
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
    try {
      final snap = await _firestore
          .collection('users')
          .orderBy('createdAt', descending: true)
          .limit(500)
          .get();

      if (!mounted) return;
      setState(() {
        _users = snap.docs
            .map((d) => UserModel.fromMap(d.data(), d.id))
            .toList();
      });
      setLoading(false);
    } catch (e) {
      if (!mounted) return;
      ToastHelper.showError('사용자 목록 불러오기 실패: $e');
      setLoading(false);
    }
  }

  List<UserModel> get _filtered {
    var list = _roleFilter == 'ALL'
        ? _users
        : _users.where((u) => u.role.name == _roleFilter).toList();

    if (_searchQuery.isNotEmpty) {
      list = list.where((u) {
        final name = u.name.toLowerCase();
        final username = u.username.toLowerCase();
        final phone = u.phone?.toLowerCase() ?? '';
        return name.contains(_searchQuery) ||
            username.contains(_searchQuery) ||
            phone.contains(_searchQuery);
      }).toList();
    }
    return list;
  }

  // ── 관리 액션 ───────────────────────────────────────────────────

  Future<void> _toggleBlacklist(UserModel user) async {
    if (user.isBlacklisted) {
      final confirmed = await DialogHelper.showDangerConfirm(
        context,
        title: '블랙리스트 해제',
        message: '${user.name}님의 블랙리스트를 해제하시겠습니까?\n해제 후 로그인이 가능해집니다.',
        confirmText: '해제',
      );
      if (!confirmed || !mounted) return;

      try {
        await _firestore.collection('users').doc(user.uid).update({
          'isBlacklisted': false,
          'blacklistReason': FieldValue.delete(),
        });
        if (!mounted) return;
        ToastHelper.showSuccess('블랙리스트가 해제되었습니다');
        await _loadAllUsers();
      } catch (e) {
        if (mounted) ToastHelper.showError('처리 실패: $e');
      }
    } else {
      // 등록: 사유 입력
      final reason = await _showReasonDialog(
        title: '블랙리스트 등록',
        hint: '예: 반복 노쇼, 사기 피해 신고, 이용 약관 위반 등',
        confirmLabel: '등록',
        confirmColor: AppColors.error,
      );
      if (reason == null || !mounted) return;

      try {
        await _firestore.collection('users').doc(user.uid).update({
          'isBlacklisted': true,
          'blacklistReason': reason,
        });
        if (!mounted) return;
        ToastHelper.showSuccess('블랙리스트에 등록되었습니다');
        await _loadAllUsers();
      } catch (e) {
        if (mounted) ToastHelper.showError('처리 실패: $e');
      }
    }
  }

  Future<void> _clearRestriction(UserModel user) async {
    final restrictedUntil = user.restrictedUntil;
    if (restrictedUntil == null) return;

    final isPermanent = restrictedUntil.year >= 9999;
    final restrictionText = isPermanent
        ? '영구 이용 제한 중'
        : '${FormatHelper.formatDateISO(restrictedUntil)}까지 제한 중';

    final confirmed = await DialogHelper.showDangerConfirm(
      context,
      title: '제재 해제',
      message: '${user.name}님의 제재를 해제하시겠습니까?\n현재: $restrictionText\n해제 후 즉시 이용 가능해집니다.',
      confirmText: '해제',
    );
    if (!confirmed || !mounted) return;

    try {
      await _firestore.collection('users').doc(user.uid).update({
        'restrictedUntil': FieldValue.delete(),
        'noShowCount': 0,
      });
      if (!mounted) return;
      ToastHelper.showSuccess('제재가 해제되었습니다');
      await _loadAllUsers();
    } catch (e) {
      if (mounted) ToastHelper.showError('처리 실패: $e');
    }
  }

  Future<void> _adjustTrustScore(UserModel user) async {
    final controller = TextEditingController(
      text: user.trustScore.toString(),
    );
    final result = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('신뢰도 점수 조정 — ${user.name}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '현재 점수: ${user.trustScore}점\n0~100 범위로 입력하세요.',
              style: ResponsiveHelper.bodyStyle(ctx, color: AppColors.grey600),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: '신뢰도 점수',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                suffixText: '점',
              ),
              autofocus: true,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('취소'),
          ),
          ElevatedButton(
            onPressed: () {
              final v = int.tryParse(controller.text.trim());
              if (v == null || v < 0 || v > 100) {
                ToastHelper.showError('0~100 사이의 숫자를 입력하세요');
                return;
              }
              Navigator.pop(ctx, v);
            },
            child: const Text('저장'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (result == null || !mounted) return;

    try {
      await _firestore.collection('users').doc(user.uid).update({
        'trustScore': result,
      });
      // 신뢰도 수동 조정 직후 배지 재계산 — minScore 조건 충족 시 즉시 배지 부여.
      // fire-and-forget: 배지 계산 실패가 UI 플로우를 막지 않도록 await 없이 실행.
      BadgeService().evaluateAndUpdateBadgesForUser(user.uid)
          .catchError((e) { debugPrint('⚠️ 배지 재계산 실패 (무시): $e'); return <String>[]; });
      if (!mounted) return;
      ToastHelper.showSuccess('신뢰도가 $result점으로 조정되었습니다');
      await _loadAllUsers();
    } catch (e) {
      if (mounted) ToastHelper.showError('처리 실패: $e');
    }
  }

  Future<String?> _showReasonDialog({
    required String title,
    required String hint,
    required String confirmLabel,
    required Color confirmColor,
  }) async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          maxLines: 3,
          decoration: InputDecoration(
            hintText: hint,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            contentPadding: const EdgeInsets.all(12),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('취소'),
          ),
          ElevatedButton(
            onPressed: () {
              if (controller.text.trim().isEmpty) {
                ToastHelper.showError('사유를 입력하세요');
                return;
              }
              Navigator.pop(ctx, controller.text.trim());
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: confirmColor,
              foregroundColor: Colors.white,
            ),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
    controller.dispose();
    return result;
  }

  // ── 사용자 상세 바텀시트 ────────────────────────────────────────

  void _showUserDetailSheet(UserModel user) {
    showModalBottomSheet(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
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
        onAdjustTrustScore: () {
          Navigator.pop(ctx);
          _adjustTrustScore(user);
        },
      ),
    );
  }

  // ── UI ─────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return GradientScaffold(
      title: '전체 사용자 관리 (${_users.length}명)',
      onRefresh: _loadAllUsers,
      body: Column(
        children: [
          _buildSearchBar(),
          _buildRoleFilter(),
          Expanded(
            child: isLoading
                ? const LoadingWidget(message: '사용자 목록을 불러오는 중...')
                : _filtered.isEmpty
                    ? _buildEmptyState()
                    : _buildUserList(),
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
                onSelected: (_) => setState(() => _roleFilter = e.key),
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
    return const AppEmptyState(
      icon: Icons.people_outline,
      title: '해당하는 사용자가 없습니다',
    );
  }

  Widget _buildUserList() {
    final list = _filtered;
    return RefreshIndicator(
      onRefresh: _loadAllUsers,
      child: ListView.builder(
        padding: ResponsiveHelper.cardPadding(context),
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
                    if (user.phone != null)
                      Text(
                        user.phone!,
                        style: ResponsiveHelper.smallStyle(
                          context,
                          color: Theme.of(context).textTheme.bodyMedium?.color,
                        ),
                      ),
                    // 상태 칩 행
                    Row(
                      children: [
                        Text(
                          '신뢰도 ${user.trustScore}점 · ${user.totalWorkDays}일 근무',
                          style: ResponsiveHelper.tinyStyle(
                            context,
                            color: Theme.of(context).textTheme.bodySmall?.color,
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
  final VoidCallback onAdjustTrustScore;

  const _UserDetailSheet({
    required this.user,
    required this.onToggleBlacklist,
    required this.onClearRestriction,
    required this.onAdjustTrustScore,
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
                _infoRow(context, Icons.phone_outlined, '연락처', user.phone ?? '-'),
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

                SizedBox(height: ResponsiveHelper.spacing(context, 8)),
                _actionButton(
                  context,
                  icon: Icons.tune,
                  label: '신뢰도 점수 수동 조정',
                  color: Theme.of(context).primaryColor,
                  onTap: onAdjustTrustScore,
                  outlined: true,
                ),

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
      ('신뢰도', '${user.trustScore}점', AppColors.amber),
      ('총 근무', '${user.totalWorkDays}일', AppColors.success),
      ('노쇼', '${user.noShowCount}회', user.noShowCount > 0 ? AppColors.error : AppColors.grey400),
      ('지각', '${user.lateCount}회', user.lateCount > 3 ? AppColors.warning : AppColors.grey400),
      ('평점', user.averageRating > 0 ? '${user.averageRating.toStringAsFixed(1)}점' : '-', AppColors.purple),
      ('리뷰', '${user.reviewCount}건', AppColors.info),
    ];

    return GridView.count(
      crossAxisCount: 3,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: ResponsiveHelper.spacing(context, 8),
      crossAxisSpacing: ResponsiveHelper.spacing(context, 8),
      childAspectRatio: 2.2,
      children: items.map((item) {
        final (label, value, color) = item;
        return Container(
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                value,
                style: ResponsiveHelper.bodyStyle(context).copyWith(
                  color: color,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                label,
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
