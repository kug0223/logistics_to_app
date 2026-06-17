import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/core/user_model.dart';
import '../../widgets/common/loading_widget.dart';
import '../../utils/toast_helper.dart';
import '../../utils/responsive_helper.dart';
import '../../widgets/common/app_empty_state.dart';
import '../../widgets/common/gradient_scaffold.dart';
import '../../utils/loading_state_mixin.dart';

/// 모든 사용자 조회 화면 (최고관리자 전용)
class AllUsersScreen extends StatefulWidget {
  const AllUsersScreen({super.key});

  @override
  State<AllUsersScreen> createState() => _AllUsersScreenState();
}

class _AllUsersScreenState extends State<AllUsersScreen>
    with LoadingStateMixin {
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
    _loadAllUsers();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadAllUsers() async {
    setLoading(true);
    try {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .orderBy('createdAt', descending: true)
          .limit(500) // OOM 방지
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
        return name.contains(_searchQuery) ||
            username.contains(_searchQuery);
      }).toList();
    }
    return list;
  }

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
          hintText: '이름 · 이메일 · 아이디 검색',
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
            return Padding(
              padding: EdgeInsets.only(right: ResponsiveHelper.spacing(context, 8)),
              child: FilterChip(
                label: Text(e.value),
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
      margin: EdgeInsets.only(bottom: ResponsiveHelper.spacing(context, 12)),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 1,
      child: Padding(
        padding: ResponsiveHelper.cardPadding(context),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: roleColor.withValues(alpha: 0.12),
              child: Icon(Icons.person, color: roleColor),
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
                    Text(user.phone!,
                        style: ResponsiveHelper.smallStyle(context,
                            color: Theme.of(context).textTheme.bodyMedium?.color)),
                  if (user.isBlacklisted)
                    Row(
                      children: [
                        Icon(Icons.block, size: ResponsiveHelper.iconSize(context, 14), color: AppColors.error),
                        SizedBox(width: 4),
                        Text('블랙리스트',
                            style: ResponsiveHelper.tinyStyle(context,
                                color: AppColors.error)),
                      ],
                    ),
                  Text(
                    '신뢰도: ${user.storedTrustScore ?? 100}점  근무: ${user.totalWorkDays}일',
                    style: ResponsiveHelper.tinyStyle(context,
                        color: Theme.of(context).textTheme.bodySmall?.color),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
