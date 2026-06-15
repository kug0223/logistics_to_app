// lib/screens/super_admin/review_tags_settings_screen.dart

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../utils/responsive_helper.dart';
import '../../utils/toast_helper.dart';
import '../../utils/dialog_helper.dart';
import '../../theme/app_colors.dart';
import '../../widgets/dialogs/styled_dialog.dart';
import '../../widgets/common/gradient_scaffold.dart';
import '../../widgets/common/loading_widget.dart';
import '../../widgets/common/app_tab_label.dart';

/// 리뷰 태그 관리 화면
class ReviewTagsSettingsScreen extends StatefulWidget {
  const ReviewTagsSettingsScreen({super.key});

  @override
  State<ReviewTagsSettingsScreen> createState() => _ReviewTagsSettingsScreenState();
}

class _ReviewTagsSettingsScreenState extends State<ReviewTagsSettingsScreen> 
    with SingleTickerProviderStateMixin {
  final _firestore = FirebaseFirestore.instance;
  late TabController _tabController;
  
  bool _isLoading = true;
  
  // 태그 목록
  List<String> _positiveTags = [];
  List<String> _improvementTags = [];
  List<String> _businessPositiveTags = [];
  List<String> _businessImprovementTags = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadTags();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadTags() async {
    try {
      final doc = await _firestore.collection('settings').doc('review_tags').get();
      
      if (doc.exists) {
        final data = doc.data()!;
        _positiveTags = List<String>.from(data['positiveTags'] ?? []);
        _improvementTags = List<String>.from(data['improvementTags'] ?? []);
        _businessPositiveTags = List<String>.from(data['businessPositiveTags'] ?? []);
        _businessImprovementTags = List<String>.from(data['businessImprovementTags'] ?? []);
      } else {
        // 기본값 설정
        _setDefaultTags();
        await _saveTags();
      }
    } catch (e) {
      debugPrint('❌ 태그 로드 실패: $e');
      _setDefaultTags();
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _setDefaultTags() {
    _positiveTags = ['시간 준수', '성실함', '작업 속도', '소통 원활', '꼼꼼함', '체력 좋음', '협조적', '빠른 습득'];
    _improvementTags = ['지각/조퇴', '무단 이탈', '작업 미숙', '소통 부족', '태도 불량', '집중력'];
    _businessPositiveTags = ['급여 정확', '친절한 관리자', '시설 청결', '업무 설명 명확', '휴게시간 준수', '교통 편리'];
    _businessImprovementTags = ['업무 과중', '소통 부족', '시설 불편', '대기 시간 김', '안전 문제'];
  }

  Future<void> _saveTags() async {
    try {
      await _firestore.collection('settings').doc('review_tags').set({
        'positiveTags': _positiveTags,
        'improvementTags': _improvementTags,
        'businessPositiveTags': _businessPositiveTags,
        'businessImprovementTags': _businessImprovementTags,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      
      if (mounted) ToastHelper.showSuccess('태그가 저장되었습니다');
    } catch (e) {
      debugPrint('❌ 태그 저장 실패: $e');
      if (mounted) ToastHelper.showError('저장에 실패했습니다');
    }
  }

  Future<void> _addTag(String type) async {
    final controller = TextEditingController();
    try {
      final result = await showDialog<String>(
        context: context,
        builder: (context) => _TagInputDialog(
          title: '태그 추가',
          controller: controller,
        ),
      );

      if (result != null && result.isNotEmpty) {
        if (!mounted) return;
        setState(() {
          switch (type) {
            case 'positive':
              if (!_positiveTags.contains(result)) _positiveTags.add(result);
              break;
            case 'improvement':
              if (!_improvementTags.contains(result)) _improvementTags.add(result);
              break;
            case 'businessPositive':
              if (!_businessPositiveTags.contains(result)) _businessPositiveTags.add(result);
              break;
            case 'businessImprovement':
              if (!_businessImprovementTags.contains(result)) _businessImprovementTags.add(result);
              break;
          }
        });
        await _saveTags();
      }
    } finally {
      controller.dispose();
    }
  }

  Future<void> _removeTag(String type, String tag) async {
    final confirmed = await DialogHelper.showConfirm(
      context,
      title: '태그 삭제',
      message: '"$tag" 태그를 삭제하시겠습니까?',
      confirmText: '삭제',
    );
    
    if (!confirmed || !mounted) return;

    setState(() {
      switch (type) {
        case 'positive':
          _positiveTags.remove(tag);
          break;
        case 'improvement':
          _improvementTags.remove(tag);
          break;
        case 'businessPositive':
          _businessPositiveTags.remove(tag);
          break;
        case 'businessImprovement':
          _businessImprovementTags.remove(tag);
          break;
      }
    });
    await _saveTags();
  }

  @override
  Widget build(BuildContext context) {
    return GradientScaffold(
      title: '리뷰 태그 관리',
      headerBottom: TabBar(
        controller: _tabController,
        indicatorColor: Colors.white,
        indicatorWeight: 2.5,
        labelColor: Colors.white,
        unselectedLabelColor: Colors.white.withValues(alpha: 0.6),
        dividerColor: Colors.transparent,
        tabs: const [
          Tab(child: AppTabLabel(label: '지원자 평가')),
          Tab(child: AppTabLabel(label: '사업장 평가')),
        ],
      ),
      body: _isLoading
          ? const LoadingWidget()
          : TabBarView(
              controller: _tabController,
              children: [
                // 지원자 평가 태그
                _buildTagsTab(
                  context,
                  positiveTags: _positiveTags,
                  positiveType: 'positive',
                  positiveTitle: '긍정 태그',
                  positiveSubtitle: '관리자가 지원자에게 부여하는 긍정적 평가',
                  improvementTags: _improvementTags,
                  improvementType: 'improvement',
                  improvementTitle: '개선 태그',
                  improvementSubtitle: '관리자가 지원자에게 부여하는 개선점',
                ),
                // 사업장 평가 태그
                _buildTagsTab(
                  context,
                  positiveTags: _businessPositiveTags,
                  positiveType: 'businessPositive',
                  positiveTitle: '긍정 태그',
                  positiveSubtitle: '지원자가 사업장에 부여하는 긍정적 평가',
                  improvementTags: _businessImprovementTags,
                  improvementType: 'businessImprovement',
                  improvementTitle: '개선 태그',
                  improvementSubtitle: '지원자가 사업장에 부여하는 개선점',
                ),
              ],
            ),
    );
  }

  Widget _buildTagsTab(
    BuildContext context, {
    required List<String> positiveTags,
    required String positiveType,
    required String positiveTitle,
    required String positiveSubtitle,
    required List<String> improvementTags,
    required String improvementType,
    required String improvementTitle,
    required String improvementSubtitle,
  }) {
    return SingleChildScrollView(
      padding: ResponsiveHelper.cardPadding(context),
      child: Column(
        children: [
          // 긍정 태그 섹션
          _buildTagSection(
            context,
            title: positiveTitle,
            subtitle: positiveSubtitle,
            tags: positiveTags,
            type: positiveType,
            color: AppColors.success,
            icon: Icons.thumb_up_outlined,
          ),
          
          SizedBox(height: ResponsiveHelper.spacing(context, 20)),
          
          // 개선 태그 섹션
          _buildTagSection(
            context,
            title: improvementTitle,
            subtitle: improvementSubtitle,
            tags: improvementTags,
            type: improvementType,
            color: AppColors.warning,
            icon: Icons.build_outlined,
          ),
          
          SizedBox(height: ResponsiveHelper.spacing(context, 20)),
        ],
      ),
    );
  }

  Widget _buildTagSection(
    BuildContext context, {
    required String title,
    required String subtitle,
    required List<String> tags,
    required String type,
    required Color color,
    required IconData icon,
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
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '$title (${tags.length}개)',
                        style: ResponsiveHelper.subtitleStyle(context).copyWith(
                          fontWeight: FontWeight.bold,
                          color: color,
                        ),
                      ),
                      Text(
                        subtitle,
                        style: ResponsiveHelper.smallStyle(context, color: AppColors.grey600),
                      ),
                    ],
                  ),
                ),
                // 추가 버튼
                IconButton(
                  onPressed: () => _addTag(type),
                  icon: Icon(
                    Icons.add_circle_outline,
                    color: color,
                    size: ResponsiveHelper.iconSize(context, 24),
                  ),
                  tooltip: '태그 추가',
                ),
              ],
            ),
          ),
          
          // 태그 목록
          Padding(
            padding: ResponsiveHelper.cardPadding(context),
            child: tags.isEmpty
                ? Center(
                    child: Padding(
                      padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 20)),
                      child: Text(
                        '등록된 태그가 없습니다',
                        style: ResponsiveHelper.bodyStyle(context, color: AppColors.grey400),
                      ),
                    ),
                  )
                : Wrap(
                    spacing: ResponsiveHelper.spacing(context, 8),
                    runSpacing: ResponsiveHelper.spacing(context, 8),
                    children: tags.map((tag) => _buildTagChip(
                      context,
                      tag: tag,
                      type: type,
                      color: color,
                    )).toList(),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildTagChip(
    BuildContext context, {
    required String tag,
    required String type,
    required Color color,
  }) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 12),
        vertical: ResponsiveHelper.spacing(context, 8),
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            tag,
            style: ResponsiveHelper.bodyStyle(context).copyWith(
              color: color,
              fontWeight: FontWeight.w500,
            ),
          ),
          SizedBox(width: ResponsiveHelper.spacing(context, 6)),
          Semantics(
            button: true,
            label: '태그 $tag 삭제',
            child: GestureDetector(
              onTap: () => _removeTag(type, tag),
              child: Icon(
                Icons.close,
                size: ResponsiveHelper.iconSize(context, 16),
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 태그 입력 다이얼로그
class _TagInputDialog extends StatelessWidget {
  final String title;
  final TextEditingController controller;

  const _TagInputDialog({
    required this.title,
    required this.controller,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return StyledDialog(
      title: title,
      icon: Icons.label_outline,
      headerColor: theme.primaryColor,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          StyledDialogTextField(
            controller: controller,
            labelText: '태그 이름',
            hintText: '예: 성실함',
            prefixIcon: Icons.tag,
          ),
        ],
      ),
      actions: [
        StyledDialogButton.cancel(
          onPressed: () => Navigator.pop(context),
        ),
        StyledDialogButton.primary(
          text: '추가',
          onPressed: () {
            final text = controller.text.trim();
            if (text.isEmpty) {
              ToastHelper.showError('태그 이름을 입력하세요');
              return;
            }
            Navigator.pop(context, text);
          },
        ),
      ],
    );
  }
}