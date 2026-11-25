// lib/screens/super_admin/badge_settings_screen.dart
// [R7-P1-6 P16-A] GradientScaffold(지원자 공통 레이아웃) → AppPageScaffold
//   (D0 관리자 표준 flat shell). 이 화면은 headerContent 를 쓰지 않고 헤더에
//   TabBar 도 없으며 가로 스크롤 표도 없다 — 그래서 위젯 이름만 바뀐다.
//   본문의 흰 카드는 flat 배경(grey100) 위에서 그대로 카드로 읽힌다.

import 'dart:math' show max;
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import '../../utils/responsive_helper.dart';
import '../../providers/user_provider.dart';
import '../../utils/text_layout.dart';
import '../../utils/toast_helper.dart';
import '../../widgets/common/app_empty_state.dart';
import '../../utils/dialog_helper.dart';
import '../../theme/app_colors.dart';
import '../../models/settings/trust_settings_model.dart';
import '../../widgets/dialogs/styled_dialog.dart';
import '../../widgets/app_select_field.dart';
import '../../widgets/common/app_page_scaffold.dart';
import '../../widgets/common/loading_widget.dart';
import '../../utils/loading_state_mixin.dart';

/// 배지 관리 화면
class BadgeSettingsScreen extends StatefulWidget {
  const BadgeSettingsScreen({super.key, this.load});

  /// [.61] 시험용 읽기 경계 — null 이면 Firestore `badges`(빈 컬렉션이면 기본 배지 생성 포함, 기존 동작).
  final Future<List<BadgeModel>> Function()? load;

  @override
  State<BadgeSettingsScreen> createState() => _BadgeSettingsScreenState();
}

class _BadgeSettingsScreenState extends State<BadgeSettingsScreen>
    with LoadingStateMixin {
  final _firestore = FirebaseFirestore.instance;
  List<BadgeModel> _badges = [];
  List<BadgeModel> _trustBadges = [];
  List<BadgeModel> _attendanceBadges = [];
  List<BadgeModel> _specialtyBadges = [];
  List<BadgeModel> _experienceBadges = [];
  bool _isAdding = false;
  bool _isToggling = false;
  /// [.61] 배지 정의를 읽지 못했다 — 기본 배지를 현재 설정처럼 보이거나 그 위에서 수정·삭제하지 않는다.
  Object? _loadError;

  /// [.61] 기본 배지 ID — 삭제해도 화면을 다시 열면 '누락 기본 배지 동기화' 가 되살린다(LOCAL 재현).
  ///   그래서 삭제를 열지 않고 비활성화로 안내한다.
  static final Set<String> _defaultIds = BadgeModel.defaultBadges().map((b) => b.id).toSet();

  void _groupBadges() {
    _trustBadges      = _badges.where((b) => b.type == BadgeType.trustScore).toList();
    _attendanceBadges = _badges.where((b) => b.type == BadgeType.attendance).toList();
    _specialtyBadges  = _badges.where((b) => b.type == BadgeType.specialty).toList();
    _experienceBadges = _badges.where((b) => b.type == BadgeType.experience).toList();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!context.read<UserProvider>().isSuperAdmin) {
        Navigator.pop(context);
        return;
      }
      _loadBadges();
    });
  }

  Future<void> _loadBadges() async {
    setLoading(true);
    if (mounted) setState(() => _loadError = null);
    try {
      if (widget.load != null) {
        _badges = await widget.load!();
        _groupBadges();
        return;
      }
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
        _badges = snapshot.docs.map((doc) {
          try { return BadgeModel.fromMap(doc.data(), doc.id); } catch (_) { return null; }
        }).whereType<BadgeModel>().toList();

        // 기본 배지 중 파싱 성공한 항목에 없는 ID만 추가 (손상 문서는 기존 ID 보유 상태로 방치하지 않음)
        final existingIds = _badges.map((b) => b.id).toSet();
        final missing = BadgeModel.defaultBadges()
            .where((b) => !existingIds.contains(b.id))
            .toList();
        if (missing.isNotEmpty) {
          final batch = _firestore.batch();
          for (final badge in missing) {
            batch.set(_firestore.collection('badges').doc(badge.id), badge.toMap());
          }
          await batch.commit();
          _badges = [..._badges, ...missing]..sort((a, b) => a.order.compareTo(b.order));
          debugPrint('✅ 누락 기본 배지 ${missing.length}개 동기화: ${missing.map((b) => b.id).join(', ')}');
        }
      }
      _groupBadges();
    } catch (e) {
      debugPrint('❌ 배지 로드 실패: $e');
      // [.61] 예전에는 기본 배지를 현재 설정처럼 보였다(그 위에서 수정·삭제 가능). 못 읽은 것은 못 읽었다고 말한다.
      _badges = [];
      _groupBadges();
      if (mounted) setState(() => _loadError = e);
    } finally {
      if (mounted) setLoading(false);
    }
  }

  Future<void> _toggleBadgeActive(BadgeModel badge) async {
    if (_isToggling) return;
    setState(() => _isToggling = true);
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
        // _groupBadges 필수: 미호출 시 그룹 리스트가 갱신되지 않아 토글 결과 화면 미반영
        _groupBadges();
      });

      if (mounted) ToastHelper.showSuccess(badge.isActive ? '배지가 비활성화되었습니다' : '배지가 활성화되었습니다');
    } catch (e) {
      if (mounted) ToastHelper.showError('변경에 실패했습니다');
    } finally {
      if (mounted) setState(() => _isToggling = false);
    }
  }

  Future<void> _editBadge(BadgeModel badge) async {
    final result = await showDialog<BadgeModel>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _BadgeEditDialog(badge: badge),
    );
    
    if (result != null) {
      if (!mounted) return;
      try {
        await _firestore.collection('badges').doc(result.id).update(result.toMap());
        if (!mounted) return;
        // _loadBadges() 전체 재로드 대신 로컬 리스트만 갱신 (네트워크 절감)
        setState(() {
          final idx = _badges.indexWhere((b) => b.id == result.id);
          if (idx >= 0) _badges[idx] = result;
          _groupBadges();
        });
        if (mounted) ToastHelper.showSuccess('배지가 수정되었습니다');
      } catch (e) {
        if (mounted) ToastHelper.showError('수정에 실패했습니다');
      }
    }
  }

  Future<void> _addBadge() async {
    if (_isAdding || isLoading) return;
    setState(() => _isAdding = true);
    try {
      final result = await showDialog<BadgeModel>(
        context: context,
        barrierDismissible: false,
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
            // _badges.length+1은 삭제 후 재추가 시 중복 order 발생
            // 예: [1,3] 남은 상태에서 length+1=3 → 기존 배지와 order 충돌
            order: _badges.map((b) => b.order).fold(0, max) + 1,
            createdAt: DateTime.now(),
          );

          await _firestore.collection('badges').doc(newId).set(newBadge.toMap());
          await _loadBadges();
          if (mounted) ToastHelper.showSuccess('배지가 추가되었습니다');
        } catch (e) {
          if (mounted) ToastHelper.showError('추가에 실패했습니다');
        }
      }
    } catch (e) {
      debugPrint('❌ 배지 추가 실패: $e');
      if (mounted) ToastHelper.showError('오류가 발생했습니다');
    } finally {
      if (mounted) setState(() => _isAdding = false);
    }
  }

  Future<void> _deleteBadge(BadgeModel badge) async {
    final confirmed = await DialogHelper.showDangerConfirm(
      context,
      title: '배지 삭제',
      // [.61] 예전 문구 '이미 획득한 사용자에게는 영향이 없습니다' 는 사실이 아니었다 — 근로자 화면은 배지 정의를
      //   찾아 그리므로 정의를 지우면 이미 받은 사람의 화면에서도 사라진다(받은 기록 ID 는 남는다).
      message: TextLayout.keepWords('"${badge.name}" 배지를 삭제하시겠습니까?\n'
          '이미 받은 사람의 화면에서도 이 배지가 더 이상 보이지 않습니다(받은 기록은 남습니다). 되돌릴 수 없습니다.'),
      confirmText: '삭제',
    );

    if (!confirmed || !mounted) return;

    try {
      await _firestore.collection('badges').doc(badge.id).delete();
      if (!mounted) return;
      await _loadBadges();
      if (mounted) ToastHelper.showSuccess('배지가 삭제되었습니다');
    } catch (e) {
      if (mounted) ToastHelper.showError('삭제에 실패했습니다');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    final trustBadges = _trustBadges;
    final attendanceBadges = _attendanceBadges;
    final specialtyBadges = _specialtyBadges;
    final experienceBadges = _experienceBadges;
    
    return AppPageScaffold(
      title: '배지 관리',
      // [DU503 · 감사48 (가)] 떠 있는 '배지 추가' 버튼(FAB)을 두지 않는다 — 목록 머리의 글자 행동으로 옮겼다(아래 ListView).
      body: isLoading
          ? const LoadingWidget()
          : _loadError != null
              ? AppEmptyState(
                  icon: Icons.cloud_off_outlined,
                  title: '배지 정보를 불러오지 못했습니다',
                  subtitle: '현재 설정을 모르는 상태라 수정·추가·삭제를 막았습니다.',
                  action: TextButton(onPressed: _loadBadges, child: const Text('다시 시도')),
                )
              : ListView(
              padding: ResponsiveHelper.listPadding(context),
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
                          // [.61] 이 화면은 배지 **정의** 를 관리한다. 사람에게 직접 주거나 회수하는 기능은 없다(앱·서버 확인).
                          TextLayout.keepWords('배지 정의와 조건을 관리합니다.\n'
                              '비활성화한 배지는 새로 받을 수 없고, 이미 받은 사람에게는 그대로 보입니다.\n'
                              '특정 사람에게 배지를 직접 주거나 회수하는 기능은 없습니다.'),
                          // [DU503] infoDark/infoBg 4.03(미달) → infoDeep(DU496 · 약관 관리 안내 띠와 같다).
                          style: ResponsiveHelper.bodyStyle(context).copyWith(
                            color: AppColors.infoDeep,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                
                SizedBox(height: ResponsiveHelper.spacing(context, 16)),
                // [DU503 · 감사48 (가)] 배지 목록 머리 오른쪽 '+ 배지 추가' 글자 행동(S024 '+ 멤버 초대' 와 같은 TextButton 계열 · receiver 48).
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: _isAdding ? null : _addBadge,
                    icon: Icon(Icons.add, size: ResponsiveHelper.iconSize(context, 16)),
                    label: Text('배지 추가',
                        style: ResponsiveHelper.smallStyle(context,
                            color: theme.primaryColor, fontWeight: FontWeight.w600)),
                    style: TextButton.styleFrom(
                      foregroundColor: theme.primaryColor,
                      minimumSize: const Size(48, 48),
                      padding: EdgeInsets.symmetric(
                        horizontal: ResponsiveHelper.spacing(context, 10),
                        vertical: ResponsiveHelper.spacing(context, 4),
                      ),
                    ),
                  ),
                ),
                SizedBox(height: ResponsiveHelper.spacing(context, 8)),
                
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
        color: AppColors.surface,
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
                // [.61] 큰 글자(392·2.0)에서 이 줄이 33px 넘쳤다 — 줄을 바꿀 수 있게 하고 낱말로 묶는다.
                Flexible(
                  child: Text(
                    TextLayout.keepWords('$title (${badges.length}개)'),
                    // [DU490] 제목 글자가 구역 색(amber · success · info)이라 같은 색 10% 면 위 약 1.4–2.9 였다 —
                    //   앱 섹션 제목 규칙(본문색 bold · DU241)으로 바꾼다. 구역 색은 아이콘 · 머리 면이 그대로 말한다.
                    style: ResponsiveHelper.subtitleStyle(context).copyWith(
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
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
      // [DU501] Row(Flexible 이름 + 칩)는 B(320@2.0)에서 이름 칸이 한 글자 폭이 되어 세로로 쌓였다 → Wrap.
      //   이름은 자기 폭을 쓰고 낱말 단위로 줄을 바꾼다([.61] · 말줄임 없음). 칩은 자리가 없으면 다음 줄로 간다.
      title: Wrap(
        spacing: ResponsiveHelper.spacing(context, 8),
        runSpacing: ResponsiveHelper.spacing(context, 4),
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            TextLayout.keepWords(badge.name),
            semanticsLabel: badge.name,
            style: ResponsiveHelper.bodyStyle(context).copyWith(
              fontWeight: FontWeight.w600,
              // [DU489] 비활성 이름 grey400(1.88) → textTertiary(5.25) — 상태는 '비활성' 칩이 말한다.
              color: badge.isActive ? null : AppColors.textTertiary,
            ),
          ),
          if (!badge.isActive)
            Container(
              padding: EdgeInsets.symmetric(
                horizontal: ResponsiveHelper.spacing(context, 6),
                vertical: ResponsiveHelper.spacing(context, 2),
              ),
              // [DU489] grey500/grey200(2.31) → 중립 칩 짝 textSecondary/grey100(5.43 · DU468 과 같다).
              decoration: BoxDecoration(
                color: AppColors.grey100,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                '비활성',
                style: ResponsiveHelper.smallStyle(context, color: AppColors.textSecondary),
              ),
            ),
        ],
      ),
      // [DU489] 조건 설명 grey500(흰 위 2.68) → textSecondary(5.92).
      subtitle: Text(
        // [DU501] B 에서 '이/상' 처럼 음절에서 끊겼다 — 낱말 조판(줄바꿈 문자는 그대로).
        TextLayout.keepWords(_getConditionText(badge)),
        style: ResponsiveHelper.smallStyle(context, color: AppColors.textSecondary),
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
          // [.61] 기본 배지는 삭제가 되살아난다 — 삭제를 열지 않고 이유를 보인다.
          if (_defaultIds.contains(badge.id))
            PopupMenuItem(
              enabled: false,
              value: 'delete-default',
              child: Text(TextLayout.keepWords('기본 배지는 삭제 대신 비활성화를 쓰세요'),
                  style: ResponsiveHelper.smallStyle(context, color: AppColors.grey500)),
            )
          else
          PopupMenuItem(
            value: 'delete',
            child: Text('삭제', style: ResponsiveHelper.bodyStyle(context, color: AppColors.errorDark)),
          ),
        ],
      ),
    );
  }

  String _getConditionText(BadgeModel badge) {
    // 주 조건 텍스트
    final primary = switch (badge.conditionType) {
      BadgeConditionType.minScore          => '신뢰도 ${badge.conditionValue}점 이상',
      BadgeConditionType.workDays          => '총 근무 ${badge.conditionValue}일 이상',
      BadgeConditionType.consecutive       => '${badge.conditionValue}회 연속 무지각',
      BadgeConditionType.monthlyPerfect    => '월간 100% 출근',
      BadgeConditionType.nightShiftCount   => '야간(22시 이후) 출근 ${badge.conditionValue}회',
      BadgeConditionType.earlyBirdCount    => '새벽(6시 이전) 출근 ${badge.conditionValue}회',
      BadgeConditionType.weekendCount      => '주말·공휴일 근무 ${badge.conditionValue}회',
      BadgeConditionType.sameBusinessRehire => '같은 사업장 ${badge.conditionValue}회 재고용',
      BadgeConditionType.uniqueBusinesses  => '${badge.conditionValue}개 이상 사업장 경험',
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
              enabled: !isEdit,
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
              enabled: !isEdit,
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
              enabled: !isEdit,
            ),
            // [.61] 근로자 화면 문구는 이름이 아니라 조건으로 만든다('10번의 근무를 완료했어요').
            //   받은 뒤 조건을 바꾸면 이미 받은 사람의 화면이 하지 않은 근무를 말했다(10회 → '30번의 근무를 완료했어요').
            if (isEdit) ...[
              SizedBox(height: ResponsiveHelper.spacing(context, 4)),
              Text(
                TextLayout.keepWords('유형과 조건은 바꿀 수 없습니다. 이미 받은 사람의 화면에 조건이 그대로 표시되기 때문입니다. 다른 조건이 필요하면 새 배지를 추가하세요.'),
                style: ResponsiveHelper.smallStyle(context, color: AppColors.grey500),
              ),
            ],

            // 업무 유형 (전문 배지일 때만)
            if (_selectedType == BadgeType.specialty) ...[
              SizedBox(height: ResponsiveHelper.spacing(context, 16)),
              StyledDialogTextField(
                controller: _workTypeController,
                labelText: '업무 유형 (선택)',
                hintText: '예: 피킹',
                prefixIcon: Icons.work,
                enabled: !isEdit,
              ),
            ],

            // 혜택 설명
            SizedBox(height: ResponsiveHelper.spacing(context, 16)),
            // [.61] 예시가 구현되지 않은 혜택(자동확정 공고 지원)을 권했다. 혜택 문구는 지금 근로자에게 보이지 않는다.
            StyledDialogTextField(
              controller: _benefitController,
              labelText: '혜택 설명',
              hintText: '실제로 제공되는 혜택만 적으세요',
              prefixIcon: Icons.card_giftcard,
            ),
            SizedBox(height: ResponsiveHelper.spacing(context, 4)),
            Text(
              TextLayout.keepWords('혜택 설명은 현재 근로자 화면에 표시되지 않습니다(배지에 연결된 혜택 기능이 없음).'),
              style: ResponsiveHelper.smallStyle(context, color: AppColors.grey500),
            ),
          ],
        ),
      ),
      actions: [
        StyledDialogButton.cancel(
          onPressed: () {
            FocusManager.instance.primaryFocus?.unfocus();
            Navigator.pop(context);
          },
        ),
        StyledDialogButton.primary(
          text: isEdit ? '수정' : '추가',
          onPressed: () {
            if (_nameController.text.isEmpty) {
              ToastHelper.showError('배지 이름을 입력하세요');
              return;
            }
            if (_iconController.text.trim().isEmpty) {
              ToastHelper.showError('아이콘을 입력하세요');
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

            FocusManager.instance.primaryFocus?.unfocus();
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
      case BadgeConditionType.nightShiftCount:
        return '야간 출근 횟수';
      case BadgeConditionType.earlyBirdCount:
        return '새벽 출근 횟수';
      case BadgeConditionType.weekendCount:
        return '주말 근무 횟수';
      case BadgeConditionType.sameBusinessRehire:
        return '동일 사업장 재고용';
      case BadgeConditionType.uniqueBusinesses:
        return '다양한 사업장 수';
    }
  }
}