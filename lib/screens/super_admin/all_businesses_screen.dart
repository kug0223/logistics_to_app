import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../theme/app_colors.dart';
import '../../providers/user_provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/core/business_model.dart';
import '../../widgets/common/loading_widget.dart';
import '../../widgets/common/styled_container.dart';
import '../../utils/toast_helper.dart';
import '../../utils/dialog_helper.dart';
import '../../utils/responsive_helper.dart';
import '../../utils/format_helper.dart';
import '../../widgets/common/app_empty_state.dart';
import '../../widgets/common/gradient_scaffold.dart';
import '../../utils/loading_state_mixin.dart';

/// ✅ 모든 사업장 조회·관리 화면 (최고관리자 전용)
class AllBusinessesScreen extends StatefulWidget {
  const AllBusinessesScreen({super.key});

  @override
  State<AllBusinessesScreen> createState() => _AllBusinessesScreenState();
}

class _AllBusinessesScreenState extends State<AllBusinessesScreen>
    with LoadingStateMixin {
  final _firestore = FirebaseFirestore.instance;

  List<_BusinessWithOwner> _businesses = [];
  String _statusFilter = 'ALL'; // 'ALL' | 'ACTIVE' | 'DEACTIVATED'
  bool _isProcessing = false;

  static const _statusLabels = {
    'ALL': '전체',
    'ACTIVE': '활성',
    'DEACTIVATED': '비활성',
  };

  @override
  void initState() {
    super.initState();
    // 방어 심층화: AuthWrapper 분기 외 2차 역할 확인
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!context.read<UserProvider>().isSuperAdmin) {
        Navigator.pop(context);
        return;
      }
      _loadAllBusinesses();
    });
  }

  Future<void> _loadAllBusinesses() async {
    setLoading(true);
    try {
      final businessSnapshot = await _firestore
          .collection('businesses')
          .orderBy('createdAt', descending: true)
          .limit(300)
          .get();

      final businesses = businessSnapshot.docs.map((doc) {
        try { return BusinessModel.fromMap(doc.data(), doc.id); } catch (_) { return null; }
      }).whereType<BusinessModel>().toList();

      // 소유자 일괄 조회: whereIn 30개 청크 배치 → 최대 10회 read (기존 300회 → 97% 절감)
      final ownerIds = businesses.map((b) => b.ownerId).toSet().toList();
      final ownerMap = <String, ({String name, String email})>{};

      for (var i = 0; i < ownerIds.length; i += 30) {
        final chunk = ownerIds.sublist(i, i + 30 < ownerIds.length ? i + 30 : ownerIds.length);
        try {
          final snap = await _firestore
              .collection('users')
              .where(FieldPath.documentId, whereIn: chunk)
              .get();
          for (final doc in snap.docs) {
            final data = doc.data();
            ownerMap[doc.id] = (
              name: data['name'] as String? ?? '알 수 없음',
              email: data['email'] as String? ?? '',
            );
          }
        } catch (_) {}
      }

      final ownerInfos = businesses
          .map((b) => ownerMap[b.ownerId] ?? (name: '알 수 없음', email: ''))
          .toList();

      final result = List.generate(businesses.length, (i) {
        return _BusinessWithOwner(
          business: businesses[i],
          ownerName: ownerInfos[i].name,
          ownerEmail: ownerInfos[i].email,
          adminCount: businesses[i].adminIds.length,
        );
      });

      if (!mounted) return;
      setState(() => _businesses = result);
      setLoading(false);
    } catch (e) {
      if (!mounted) return;
      ToastHelper.showError('사업장 목록을 불러오는데 실패했습니다: $e');
      setLoading(false);
    }
  }

  List<_BusinessWithOwner> get _filtered {
    return switch (_statusFilter) {
      'ACTIVE' => _businesses.where((b) => !b.business.isDeactivated).toList(),
      'DEACTIVATED' => _businesses.where((b) => b.business.isDeactivated).toList(),
      _ => _businesses,
    };
  }

  // ── 관리 액션 ──────────────────────────────────────────────────

  Future<void> _deactivateBusiness(_BusinessWithOwner item) async {
    if (_isProcessing) return;
    final confirmed = await DialogHelper.showDangerConfirm(
      context,
      title: '사업장 비활성화',
      message: '「${item.business.name}」을 비활성화하시겠습니까?\n'
          '비활성화 후 이 사업장의 공고는 지원자에게 노출되지 않습니다.\n'
          '활성 TO는 수동으로 마감 처리해 주세요.',
      confirmText: '비활성화',
    );
    if (!confirmed || !mounted) return;
    setState(() => _isProcessing = true);

    try {
      await _firestore.collection('businesses').doc(item.business.id).update({
        'deactivatedAt': FieldValue.serverTimestamp(),
      });
      if (!mounted) return;
      ToastHelper.showSuccess('사업장이 비활성화되었습니다');
      await _loadAllBusinesses();
    } catch (e) {
      if (mounted) ToastHelper.showError('처리 실패: $e');
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _reactivateBusiness(_BusinessWithOwner item) async {
    if (_isProcessing) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('사업장 재활성화'),
        content: Text('「${item.business.name}」을 재활성화하시겠습니까?\n'
            '재활성화 후 다시 공고를 등록할 수 있습니다.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.success),
            child: const Text('재활성화', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _isProcessing = true);

    try {
      await _firestore.collection('businesses').doc(item.business.id).update({
        'deactivatedAt': FieldValue.delete(),
      });
      if (!mounted) return;
      ToastHelper.showSuccess('사업장이 재활성화되었습니다');
      await _loadAllBusinesses();
    } catch (e) {
      if (mounted) ToastHelper.showError('처리 실패: $e');
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  // ── UI ────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final activeCount = _businesses.where((b) => !b.business.isDeactivated).length;
    final deactivatedCount = _businesses.where((b) => b.business.isDeactivated).length;

    return GradientScaffold(
      title: '전체 사업장 관리',
      onRefresh: _loadAllBusinesses,
      body: isLoading
          ? const LoadingWidget(message: '사업장 목록을 불러오는 중...')
          : _businesses.isEmpty
              ? _buildEmptyState()
              : Column(
                  children: [
                    _buildFilterBar(activeCount, deactivatedCount),
                    Expanded(child: _buildBusinessList()),
                  ],
                ),
    );
  }

  Widget _buildFilterBar(int activeCount, int deactivatedCount) {
    final counts = {'ALL': _businesses.length, 'ACTIVE': activeCount, 'DEACTIVATED': deactivatedCount};
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 16),
        vertical: ResponsiveHelper.spacing(context, 8),
      ),
      color: Theme.of(context).colorScheme.surface,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: _statusLabels.entries.map((e) {
            final active = _statusFilter == e.key;
            return Padding(
              padding: EdgeInsets.only(right: ResponsiveHelper.spacing(context, 8)),
              child: FilterChip(
                label: Text('${e.value} (${counts[e.key]})'),
                selected: active,
                onSelected: (_) => setState(() => _statusFilter = e.key),
                selectedColor: Theme.of(context).primaryColor.withValues(alpha: 0.15),
                checkmarkColor: Theme.of(context).primaryColor,
                labelStyle: ResponsiveHelper.smallStyle(
                  context,
                  color: active ? Theme.of(context).primaryColor : null,
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
      icon: Icons.business_outlined,
      title: '등록된 사업장이 없습니다',
    );
  }

  Widget _buildBusinessList() {
    final list = _filtered;
    if (list.isEmpty) {
      return AppEmptyState(
        icon: Icons.business_outlined,
        title: _statusFilter == 'DEACTIVATED' ? '비활성화된 사업장이 없습니다' : '활성 사업장이 없습니다',
      );
    }
    return RefreshIndicator(
      onRefresh: _loadAllBusinesses,
      child: ListView.builder(
        padding: ResponsiveHelper.cardPadding(context),
        itemCount: list.length,
        itemBuilder: (context, index) => _buildBusinessCard(list[index]),
      ),
    );
  }

  Widget _buildBusinessCard(_BusinessWithOwner item) {
    final business = item.business;
    final isDeactivated = business.isDeactivated;

    return Card(
      margin: EdgeInsets.only(bottom: ResponsiveHelper.spacing(context, 16)),
      elevation: isDeactivated ? 0 : 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: isDeactivated
            ? BorderSide(color: AppColors.grey300, width: 1)
            : BorderSide.none,
      ),
      child: Padding(
        padding: ResponsiveHelper.cardPadding(context),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 사업장명 + 상태 + 액션 메뉴
            Row(
              children: [
                Expanded(
                  child: Text(
                    business.name,
                    style: ResponsiveHelper.titleStyle(context).copyWith(
                      color: isDeactivated ? AppColors.grey400 : null,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                // 상태 배지
                if (isDeactivated)
                  StyledBadge(
                    label: '비활성',
                    backgroundColor: AppColors.grey200,
                    textColor: AppColors.grey500,
                    fontSize: ResponsiveHelper.tinyStyle(context).fontSize!,
                  )
                else
                  StyledBadge(
                    label: '활성',
                    backgroundColor: AppColors.success.withValues(alpha: 0.1),
                    textColor: AppColors.success,
                    fontSize: ResponsiveHelper.tinyStyle(context).fontSize!,
                  ),
                SizedBox(width: ResponsiveHelper.spacing(context, 4)),
                // 관리 메뉴
                PopupMenuButton<String>(
                  icon: Icon(
                    Icons.more_vert,
                    size: ResponsiveHelper.iconSize(context, 20),
                    color: AppColors.grey500,
                  ),
                  onSelected: (value) {
                    if (value == 'deactivate') _deactivateBusiness(item);
                    if (value == 'reactivate') _reactivateBusiness(item);
                  },
                  itemBuilder: (ctx) => [
                    if (!isDeactivated)
                      const PopupMenuItem(
                        value: 'deactivate',
                        child: Row(
                          children: [
                            Icon(Icons.pause_circle_outline, color: AppColors.warning),
                            SizedBox(width: 8),
                            Text('비활성화'),
                          ],
                        ),
                      ),
                    if (isDeactivated)
                      const PopupMenuItem(
                        value: 'reactivate',
                        child: Row(
                          children: [
                            Icon(Icons.play_circle_outline, color: AppColors.success),
                            SizedBox(width: 8),
                            Text('재활성화'),
                          ],
                        ),
                      ),
                  ],
                ),
              ],
            ),

            // 비활성화 날짜 표시
            if (isDeactivated && business.deactivatedAt != null) ...[
              SizedBox(height: ResponsiveHelper.spacing(context, 4)),
              Text(
                '비활성화: ${FormatHelper.formatDateISO(business.deactivatedAt!)}',
                style: ResponsiveHelper.tinyStyle(context, color: AppColors.grey400),
              ),
            ],

            Divider(height: ResponsiveHelper.spacing(context, 24)),

            _buildInfoRow(
              icon: Icons.person,
              label: '관리자',
              value: '${item.ownerName}${item.ownerEmail.isNotEmpty ? " (${item.ownerEmail})" : ""}${item.adminCount > 1 ? " 외 ${item.adminCount - 1}명" : ""}',
              color: AppColors.purple,
            ),
            SizedBox(height: ResponsiveHelper.spacing(context, 12)),
            _buildInfoRow(
              icon: Icons.numbers,
              label: '사업자번호',
              value: business.formattedBusinessNumber,
              color: Theme.of(context).primaryColor,
            ),
            SizedBox(height: ResponsiveHelper.spacing(context, 12)),
            _buildInfoRow(
              icon: Icons.category,
              label: '업종',
              value: '${business.category} / ${business.subCategory}',
              color: AppColors.success,
            ),
            SizedBox(height: ResponsiveHelper.spacing(context, 12)),
            _buildInfoRow(
              icon: Icons.location_on,
              label: '주소',
              value: business.address,
              color: AppColors.error,
            ),
            if (business.phone != null) ...[
              SizedBox(height: ResponsiveHelper.spacing(context, 12)),
              _buildInfoRow(
                icon: Icons.phone,
                label: '연락처',
                value: business.phone!,
                color: AppColors.warning,
              ),
            ],
            SizedBox(height: ResponsiveHelper.spacing(context, 12)),
            Text(
              '등록일: ${FormatHelper.formatDateISO(business.createdAt)}',
              style: ResponsiveHelper.tinyStyle(
                context,
                color: Theme.of(context).textTheme.bodySmall?.color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: ResponsiveHelper.iconSize(context, 18), color: color),
        SizedBox(width: ResponsiveHelper.spacing(context, 8)),
        Expanded(
          child: RichText(
            text: TextSpan(
              style: ResponsiveHelper.bodyStyle(
                context,
                color: Theme.of(context).textTheme.bodyMedium?.color,
              ),
              children: [
                TextSpan(
                  text: '$label: ',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                TextSpan(text: value),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _BusinessWithOwner {
  final BusinessModel business;
  final String ownerName;
  final String ownerEmail;
  final int adminCount;

  _BusinessWithOwner({
    required this.business,
    required this.ownerName,
    required this.ownerEmail,
    required this.adminCount,
  });
}
