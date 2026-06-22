// lib/screens/super_admin/badge_settings_screen.dart

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../utils/responsive_helper.dart';
import '../../utils/toast_helper.dart';
import '../../utils/dialog_helper.dart';
import '../../theme/app_colors.dart';
import '../../models/settings/trust_settings_model.dart';
import '../../widgets/dialogs/styled_dialog.dart';
import '../../widgets/app_select_field.dart';
import '../../widgets/common/gradient_scaffold.dart';
import '../../widgets/common/loading_widget.dart';
import '../../utils/loading_state_mixin.dart';

/// 배지 관리 화면
class BadgeSettingsScreen extends StatefulWidget {
  const BadgeSettingsScreen({super.key});

  @override
  State<BadgeSettingsScreen> createState() => _BadgeSettingsScreenState();
}

class _BadgeSettingsScreenState extends State<BadgeSettingsScreen>
    with LoadingStateMixin {
  final _firestore = FirebaseFirestore.instance;
  List<BadgeModel> _badges = [];

  @override
  void initState() {
    super.initState();
    _loadBadges();
  }

  Future<void> _loadBadges() async {
    setLoading(true);
    try {
      final snapshot = await _firestore
          .collection('badges')
          .orderBy('order')
          .get();
      
      if (snapshot.docs.isEmpty) {
        // 기본 배지 생성
        _badges = BadgeModel.defaultBadges();
        final batch = _firestore.batch();
        for (final badge in _badges) {
          batch.set(_firestore.collection('badges').doc(badge.id), badge.toMap());
        }
        await batch.commit();
      } else {
        _badges = snapshot.docs
            .map((doc) => BadgeModel.fromMap(doc.data(), doc.id))
            .toList();
      }
    } catch (e) {
      debugPrint('❌ 배지 로드 실패: $e');
      _badges = BadgeModel.defaultBadges();
    } finally {
      if (mounted) setLoading(false);
    }
  }

  Future<void> _toggleBadgeActive(BadgeModel badge) async {
    try {
      await _firestore.collection('badges').doc(badge.id).update({
        'isActive': !badge.isActive,
      });

      if (!mounted) return;
      setState(() {
        final index = _badges.indexWhere((b) => b.id == badge.id);
        if (index != -1) {
          _badges[index] = BadgeModel(
            id: badge.id,
            name: badge.name,
            icon: badge.icon,
            type: badge.type,
            conditionType: badge.conditionType,
            conditionValue: badge.conditionValue,
            workType: badge.workType,
            isActive: !badge.isActive,
            order: badge.order,
            createdAt: badge.createdAt,
            minWorkDaysRequired: badge.minWorkDaysRequired,
            maxNoShowAllowed: badge.maxNoShowAllowed,
            minRatingRequired: badge.minRatingRequired,
            benefit: badge.benefit,
          );
        }
      });
      
      if (mounted) ToastHelper.showSuccess(badge.isActive ? '배지가 비활성화되었습니다' : '배지가 활성화되었습니다');
    } catch (e) {
      if (mounted) ToastHelper.showError('변경에 실패했습니다');
    }
  }

  Future<void> _editBadge(BadgeModel badge) async {
    final result = await showDialog<BadgeModel>(
      context: context,
      builder: (context) => _BadgeEditDialog(badge: badge),
    );
    
    if (result != null) {
      if (!mounted) return;
      try {
        await _firestore.collection('badges').doc(result.id).update(result.toMap());
        await _loadBadges();
        if (mounted) ToastHelper.showSuccess('배지가 수정되었습니다');
      } catch (e) {
        if (mounted) ToastHelper.showError('수정에 실패했습니다');
      }
    }
  }

  Future<void> _addBadge() async {
    final result = await showDialog<BadgeModel>(
      context: context,
      builder: (context) => const _BadgeEditDialog(),
    );

    if (result != null) {
      if (!mounted) return;
      try {
        final newId = _firestore.collection('badges').doc().id;
        final newBadge = BadgeModel(
          id: newId,
          name: result.name,
          icon: result.icon,
          type: result.type,
          conditionType: result.conditionType,
          conditionValue: result.conditionValue,
          workType: result.workType,
          isActive: true,
          order: _badges.length + 1,
          createdAt: DateTime.now(),
        );

        await _firestore.collection('badges').doc(newId).set(newBadge.toMap());
        await _loadBadges();
        if (mounted) ToastHelper.showSuccess('배지가 추가되었습니다');
      } catch (e) {
        if (mounted) ToastHelper.showError('추가에 실패했습니다');
      }
    }
  }

  Future<void> _deleteBadge(BadgeModel badge) async {
    final confirmed = await DialogHelper.showDangerConfirm(
      context,
      title: '배지 삭제',
      message: '"${badge.name}" 배지를 삭제하시겠습니까?\n이미 획득한 사용자에게는 영향이 없습니다.',
      confirmText: '삭제',
    );

    if (!confirmed || !mounted) return;

    try {
      await _firestore.collection('badges').doc(badge.id).delete();
      await _loadBadges();
      if (mounted) ToastHelper.showSuccess('배지가 삭제되었습니다');
    } catch (e) {
      if (mounted) ToastHelper.showError('삭제에 실패했습니다');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    // 타입별 그룹화
    final trustBadges = _badges.where((b) => b.type == BadgeType.trustScore).toList();
    final attendanceBadges = _badges.where((b) => b.type == BadgeType.attendance).toList();
    final specialtyBadges = _badges.where((b) => b.type == BadgeType.specialty).toList();
    final experienceBadges = _badges.where((b) => b.type == BadgeType.experience).toList();
    
    return GradientScaffold(
      title: '배지 관리',
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addBadge,
        backgroundColor: theme.primaryColor,
        icon: const Icon(Icons.add),
        label: const Text('배지 추가'),
      ),
      body: isLoading
          ? const LoadingWidget()
          : ListView(
              padding: ResponsiveHelper.cardPadding(context),
              children: [
                // 안내 카드
                Container(
                  padding: ResponsiveHelper.cardPadding(context),
                  decoration: BoxDecoration(
                    color: AppColors.infoBg,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.emoji_events,
                        size: ResponsiveHelper.iconSize(context, 32),
                        color: AppColors.amber,
                      ),
                      SizedBox(width: ResponsiveHelper.spacing(context, 12)),
                      Expanded(
                        child: Text(
                          '배지를 관리하고 조건을 설정하세요.\n비활성화된 배지는 새로 획득할 수 없습니다.',
                          style: ResponsiveHelper.bodyStyle(context).copyWith(
                            color: AppColors.infoDark,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                
                SizedBox(height: ResponsiveHelper.spacing(context, 24)),
                
                // 신뢰도 배지
                if (trustBadges.isNotEmpty)
                  _buildBadgeSection(
                    context,
                    title: '신뢰도 배지',
                    icon: Icons.verified,
                    color: AppColors.amber,
                    badges: trustBadges,
                  ),
                
                SizedBox(height: ResponsiveHelper.spacing(context, 16)),
                
                // 근태 배지
                if (attendanceBadges.isNotEmpty)
                  _buildBadgeSection(
                    context,
                    title: '근태 배지',
                    icon: Icons.access_time,
                    color: AppColors.success,
                    badges: attendanceBadges,
                  ),
                
                SizedBox(height: ResponsiveHelper.spacing(context, 16)),
                
                // 전문 배지
                if (specialtyBadges.isNotEmpty)
                  _buildBadgeSection(
                    context,
                    title: '전문 배지',
                    icon: Icons.workspace_premium,
                    color: AppColors.info,
                    badges: specialtyBadges,
                  ),

                SizedBox(height: ResponsiveHelper.spacing(context, 16)),

                // 경력 배지
                if (experienceBadges.isNotEmpty)
                  _buildBadgeSection(
                    context,
                    title: '경력 배지',
                    icon: Icons.military_tech,
                    color: AppColors.amber,
                    badges: experienceBadges,
                  ),

                SizedBox(height: ResponsiveHelper.spacing(context, 80)), // FAB 공간
              ],
            ),
    );
  }

  Widget _buildBadgeSection(
    BuildContext context, {
    required String title,
    required IconData icon,
    required Color color,
    required List<BadgeModel> badges,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 헤더
          Container(
            padding: ResponsiveHelper.cardPadding(context),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
              ),
            ),
            child: Row(
              children: [
                Icon(icon, size: ResponsiveHelper.iconSize(context, 20), color: color),
                SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                Text(
                  '$title (${badges.length}개)',
                  style: ResponsiveHelper.subtitleStyle(context).copyWith(
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
              ],
            ),
          ),
          
          // 배지 목록
          ...badges.asMap().entries.map((entry) {
            final index = entry.key;
            final badge = entry.value;
            final isLast = index == badges.length - 1;
            
            return Column(
              children: [
                _buildBadgeTile(context, badge),
                if (!isLast) const Divider(height: 1),
              ],
            );
          }),
        ],
      ),
    );
  }

  Widget _buildBadgeTile(BuildContext context, BadgeModel badge) {
    return ListTile(
      contentPadding: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 16),
        vertical: ResponsiveHelper.spacing(context, 8),
      ),
      leading: Container(
        width: ResponsiveHelper.spacing(context, 48),
        height: ResponsiveHelper.spacing(context, 48),
        decoration: BoxDecoration(
          color: badge.isActive 
              ? AppColors.amber.withValues(alpha: 0.15) 
              : AppColors.grey200,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Center(
          child: Text(
            badge.icon,
            style: ResponsiveHelper.titleStyle(context),
          ),
        ),
      ),
      title: Row(
        children: [
          Text(
            badge.name,
            style: ResponsiveHelper.bodyStyle(context).copyWith(
              fontWeight: FontWeight.w600,
              color: badge.isActive ? null : AppColors.grey400,
            ),
          ),
          if (!badge.isActive) ...[
            SizedBox(width: ResponsiveHelper.spacing(context, 8)),
            Container(
              padding: EdgeInsets.symmetric(
                horizontal: ResponsiveHelper.spacing(context, 6),
                vertical: ResponsiveHelper.spacing(context, 2),
              ),
              decoration: BoxDecoration(
                color: AppColors.grey200,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                '비활성',
                style: ResponsiveHelper.smallStyle(context, color: AppColors.grey500),
              ),
            ),
          ],
        ],
      ),
      subtitle: Text(
        _getConditionText(badge),
        style: ResponsiveHelper.smallStyle(context, color: AppColors.grey500),
      ),
      trailing: PopupMenuButton<String>(
        onSelected: (value) {
          switch (value) {
            case 'edit':
              _editBadge(badge);
              break;
            case 'toggle':
              _toggleBadgeActive(badge);
              break;
            case 'delete':
              _deleteBadge(badge);
              break;
          }
        },
        itemBuilder: (context) => [
          const PopupMenuItem(value: 'edit', child: Text('수정')),
          PopupMenuItem(
            value: 'toggle',
            child: Text(badge.isActive ? '비활성화' : '활성화'),
          ),
          PopupMenuItem(
            value: 'delete',
            child: Text('삭제', style: ResponsiveHelper.bodyStyle(context, color: AppColors.error)),
          ),
        ],
      ),
    );
  }

  String _getConditionText(BadgeModel badge) {
    // 주 조건 텍스트
    final primary = switch (badge.conditionType) {
      BadgeConditionType.minScore     => '신뢰도 ${badge.conditionValue}점 이상',
      BadgeConditionType.workDays     => badge.workType != null
          ? '${badge.workType} ${badge.conditionValue}일 이상'
          : '총 근무 ${badge.conditionValue}일 이상',
      BadgeConditionType.consecutive  => '${badge.conditionValue}회 연속 무지각',
      BadgeConditionType.monthlyPerfect => '월간 100% 출근 ${badge.conditionValue}개월',
    };

    // 복합 조건 추가 텍스트
    final extras = <String>[
      if (badge.minWorkDaysRequired != null)
        '근무 ${badge.minWorkDaysRequired}일 이상',
      if (badge.maxNoShowAllowed != null)
        badge.maxNoShowAllowed == 0 ? '노쇼 없음' : '노쇼 ${badge.maxNoShowAllowed}회 이하',
      if (badge.minRatingRequired != null)
        '평점 ${badge.minRatingRequired!.toStringAsFixed(1)}점 이상',
    ];

    if (extras.isEmpty) return primary;
    return '$primary\n+ ${extras.join(' · ')}';
  }
}

/// 배지 편집 다이얼로그
class _BadgeEditDialog extends StatefulWidget {
  final BadgeModel? badge;

  const _BadgeEditDialog({this.badge});

  @override
  State<_BadgeEditDialog> createState() => _BadgeEditDialogState();
}

class _BadgeEditDialogState extends State<_BadgeEditDialog> {
  final _nameController = TextEditingController();
  final _iconController = TextEditingController();
  final _valueController = TextEditingController();
  final _workTypeController = TextEditingController();
  final _benefitController = TextEditingController();

  BadgeType _selectedType = BadgeType.trustScore;
  BadgeConditionType _selectedCondition = BadgeConditionType.minScore;

  @override
  void initState() {
    super.initState();
    if (widget.badge != null) {
      _nameController.text = widget.badge!.name;
      _iconController.text = widget.badge!.icon;
      _valueController.text = widget.badge!.conditionValue.toString();
      _workTypeController.text = widget.badge!.workType ?? '';
      _benefitController.text = widget.badge!.benefit ?? '';
      _selectedType = widget.badge!.type;
      _selectedCondition = widget.badge!.conditionType;
    } else {
      _iconController.text = '🏅';
      _valueController.text = '50';
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _iconController.dispose();
    _valueController.dispose();
    _workTypeController.dispose();
    _benefitController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.badge != null;
    
    return StyledDialog(
      title: isEdit ? '배지 수정' : '새 배지 추가',
      icon: Icons.emoji_events,
      headerColor: AppColors.amber,
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 이름
            StyledDialogTextField(
              controller: _nameController,
              labelText: '배지 이름',
              hintText: '예: 골드',
              prefixIcon: Icons.badge,
            ),
            
            SizedBox(height: ResponsiveHelper.spacing(context, 16)),
            
            // 아이콘
            StyledDialogTextField(
              controller: _iconController,
              labelText: '아이콘 (이모지)',
              hintText: '예: 🥇',
              prefixIcon: Icons.emoji_emotions,
            ),
            
            SizedBox(height: ResponsiveHelper.spacing(context, 16)),
            
            // 배지 타입
            Text(
              '배지 유형',
              style: ResponsiveHelper.bodyStyle(context).copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            SizedBox(height: ResponsiveHelper.spacing(context, 8)),
            AppSelectField<BadgeType>(
              value: _selectedType,
              hintText: '배지 유형 선택',
              sheetTitle: '배지 유형',
              items: BadgeType.values,
              labelOf: _getBadgeTypeName,
              prefixIcon: Icons.category,
              onChanged: (value) {
                if (value == null) return;
                setState(() {
                  _selectedType = value;
                  if (value == BadgeType.trustScore) {
                    _selectedCondition = BadgeConditionType.minScore;
                  } else if (value == BadgeType.attendance) {
                    _selectedCondition = BadgeConditionType.consecutive;
                  } else {
                    _selectedCondition = BadgeConditionType.workDays;
                  }
                });
              },
            ),
            
            SizedBox(height: ResponsiveHelper.spacing(context, 16)),
            
            // 조건 타입
            Text(
              '획득 조건',
              style: ResponsiveHelper.bodyStyle(context).copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            SizedBox(height: ResponsiveHelper.spacing(context, 8)),
            AppSelectField<BadgeConditionType>(
              value: _selectedCondition,
              hintText: '획득 조건 선택',
              sheetTitle: '획득 조건',
              items: BadgeConditionType.values,
              labelOf: _getConditionTypeName,
              prefixIcon: Icons.flag,
              onChanged: (value) {
                if (value != null) setState(() => _selectedCondition = value);
              },
            ),
            
            SizedBox(height: ResponsiveHelper.spacing(context, 16)),
            
            // 조건 값
            StyledDialogTextField(
              controller: _valueController,
              labelText: '조건 값',
              hintText: '예: 90',
              prefixIcon: Icons.numbers,
              keyboardType: TextInputType.number,
            ),
            
            // 업무 유형 (전문 배지일 때만)
            if (_selectedType == BadgeType.specialty) ...[
              SizedBox(height: ResponsiveHelper.spacing(context, 16)),
              StyledDialogTextField(
                controller: _workTypeController,
                labelText: '업무 유형 (선택)',
                hintText: '예: 피킹',
                prefixIcon: Icons.work,
              ),
            ],

            // 혜택 설명
            SizedBox(height: ResponsiveHelper.spacing(context, 16)),
            StyledDialogTextField(
              controller: _benefitController,
              labelText: '혜택 설명',
              hintText: '예: 골드 강조 표시 · 자동확정 공고 지원 가능',
              prefixIcon: Icons.card_giftcard,
            ),
          ],
        ),
      ),
      actions: [
        StyledDialogButton.cancel(
          onPressed: () => Navigator.pop(context),
        ),
        StyledDialogButton.primary(
          text: isEdit ? '수정' : '추가',
          onPressed: () {
            if (_nameController.text.isEmpty) {
              ToastHelper.showError('배지 이름을 입력하세요');
              return;
            }
            final parsedValue = int.tryParse(_valueController.text) ?? 0;
            if (parsedValue <= 0) {
              ToastHelper.showError('조건 값은 1 이상의 숫자여야 합니다');
              return;
            }

            final result = BadgeModel(
              id: widget.badge?.id ?? '',
              name: _nameController.text.trim(),
              icon: _iconController.text.trim(),
              type: _selectedType,
              conditionType: _selectedCondition,
              conditionValue: parsedValue,
              workType: _workTypeController.text.isEmpty
                  ? null
                  : _workTypeController.text.trim(),
              isActive: widget.badge?.isActive ?? true,
              order: widget.badge?.order ?? 0,
              createdAt: widget.badge?.createdAt ?? DateTime.now(),
              benefit: _benefitController.text.trim().isEmpty
                  ? null
                  : _benefitController.text.trim(),
            );
            
            Navigator.pop(context, result);
          },
        ),
      ],
    );
  }

  String _getBadgeTypeName(BadgeType type) {
    switch (type) {
      case BadgeType.trustScore:
        return '신뢰도 배지';
      case BadgeType.attendance:
        return '근태 배지';
      case BadgeType.experience:
        return '경험 배지';
      case BadgeType.specialty:
        return '전문 배지';
    }
  }

  String _getConditionTypeName(BadgeConditionType type) {
    switch (type) {
      case BadgeConditionType.minScore:
        return '최소 점수';
      case BadgeConditionType.workDays:
        return '근무 일수';
      case BadgeConditionType.consecutive:
        return '연속 무지각';
      case BadgeConditionType.monthlyPerfect:
        return '월간 완벽 출근';
    }
  }
}