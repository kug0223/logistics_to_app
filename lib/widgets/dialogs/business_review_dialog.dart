// lib/widgets/dialogs/business_review_dialog.dart

import 'package:flutter/material.dart';
import '../../utils/responsive_helper.dart';
import '../../theme/app_colors.dart';
import '../../models/settings/trust_settings_model.dart';
import '../../services/monthly_review_service.dart';
import '../../utils/toast_helper.dart';
import 'styled_dialog.dart';

/// 지원자 → 사업장 리뷰 작성 다이얼로그
/// 
/// 정책:
/// - 월 1회만 작성 가능
/// - 작성 후 수정 불가
/// - 3일 후 공개
/// - 익명 작성
class BusinessReviewDialog extends StatefulWidget {
  /// 작성자 (지원자) UID
  final String reviewerId;
  
  /// 작성자 이름 (저장 시 익명 처리)
  final String reviewerName;
  
  /// 사업장 ID
  final String businessId;
  
  /// 사업장 이름
  final String businessName;
  
  /// 리뷰 대상 년도
  final int reviewYear;
  
  /// 리뷰 대상 월
  final int reviewMonth;
  
  /// 해당 월 근무 일수
  final int workDaysInMonth;

  const BusinessReviewDialog({
    super.key,
    required this.reviewerId,
    required this.reviewerName,
    required this.businessId,
    required this.businessName,
    required this.reviewYear,
    required this.reviewMonth,
    required this.workDaysInMonth,
  });

  @override
  State<BusinessReviewDialog> createState() => _BusinessReviewDialogState();
}

class _BusinessReviewDialogState extends State<BusinessReviewDialog> {
  final _commentController = TextEditingController();
  final _reviewService = MonthlyReviewService();
  
  // 상태
  int _rating = 4;
  bool? _wouldWorkAgain;
  List<String> _selectedPositiveTags = [];
  List<String> _selectedImprovementTags = [];
  bool _isLoading = false;
  bool _isSubmitting = false;
  
  // 태그 목록
  ReviewTagsModel _tags = ReviewTagsModel.defaults();

  @override
  void initState() {
    super.initState();
    _loadTags();
  }

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _loadTags() async {
    setState(() => _isLoading = true);
    try {
      _tags = await _reviewService.getReviewTags();
    } catch (e) {
      debugPrint('❌ 태그 로드 실패: $e');
    }
    setState(() => _isLoading = false);
  }

  Future<void> _submitReview() async {
    // 유효성 검사
    if (_wouldWorkAgain == null) {
      ToastHelper.showWarning('다시 근무할 의향을 선택해주세요.');
      return;
    }
    
    setState(() => _isSubmitting = true);
    
    final result = await _reviewService.createReviewForBusiness(
      reviewerId: widget.reviewerId,
      reviewerName: widget.reviewerName,
      businessId: widget.businessId,
      businessName: widget.businessName,
      reviewYear: widget.reviewYear,
      reviewMonth: widget.reviewMonth,
      workDaysInMonth: widget.workDaysInMonth,
      rating: _rating,
      wouldWorkAgain: _wouldWorkAgain!,
      positiveTags: _selectedPositiveTags,
      improvementTags: _selectedImprovementTags,
      comment: _commentController.text.trim().isEmpty 
          ? null 
          : _commentController.text.trim(),
    );
    
    if (!mounted) return;
    
    if (result.reviewId != null) {
      // 성공 다이얼로그
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (resultContext) => StyledDialog(
          title: '리뷰 작성 완료',
          subtitle: null,
          icon: Icons.check_circle,
          headerColor: AppColors.success,
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.schedule,
                size: ResponsiveHelper.iconSize(context, 48),
                color: AppColors.info,
              ),
              SizedBox(height: ResponsiveHelper.spacing(context, 16)),
              Text(
                '리뷰가 작성되었습니다.\n3일 후 익명으로 공개됩니다.',
                style: ResponsiveHelper.bodyStyle(context),
                textAlign: TextAlign.center,
              ),
            ],
          ),
          actions: [
            StyledDialogButton.primary(
              text: '확인',
              onPressed: () {
                Navigator.pop(resultContext);
                Navigator.pop(context, true);
              },
            ),
          ],
        ),
      );
    } else {
      setState(() => _isSubmitting = false);
      ToastHelper.showError(result.error ?? '리뷰 작성에 실패했습니다.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    // 🆕 첫 리뷰 작성 툴팁은 관리자 리뷰에서만 표시 (지원자 리뷰는 별도)
    
    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
      ),
      child: Container(
        constraints: BoxConstraints(
          maxWidth: 500,
          maxHeight: MediaQuery.of(context).size.height * 0.9,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 헤더
            _buildHeader(context, theme),
            
            // 내용
            Flexible(
              child: _isLoading
                  ? Center(
                      child: Padding(
                        padding: ResponsiveHelper.cardPadding(context),
                        child: CircularProgressIndicator(),
                      ),
                    )
                  : SingleChildScrollView(
                      padding: ResponsiveHelper.cardPadding(context),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // 사업장 정보
                          _buildBusinessInfo(context),
                          SizedBox(height: ResponsiveHelper.spacing(context, 24)),
                          
                          // 평점
                          _buildRatingSection(context),
                          SizedBox(height: ResponsiveHelper.spacing(context, 24)),
                          
                          // 재근무 의사
                          _buildWorkAgainSection(context, theme),
                          SizedBox(height: ResponsiveHelper.spacing(context, 24)),
                          
                          // 긍정 태그
                          _buildTagSection(
                            context,
                            title: '좋았던 점',
                            icon: Icons.thumb_up_outlined,
                            iconColor: AppColors.success,
                            tags: _tags.businessPositiveTags,
                            selectedTags: _selectedPositiveTags,
                            onChanged: (tags) {
                              setState(() => _selectedPositiveTags = tags);
                            },
                          ),
                          SizedBox(height: ResponsiveHelper.spacing(context, 24)),
                          
                          // 개선 태그
                          _buildTagSection(
                            context,
                            title: '아쉬운 점',
                            icon: Icons.lightbulb_outline,
                            iconColor: AppColors.warning,
                            tags: _tags.businessImprovementTags,
                            selectedTags: _selectedImprovementTags,
                            onChanged: (tags) {
                              setState(() => _selectedImprovementTags = tags);
                            },
                          ),
                          SizedBox(height: ResponsiveHelper.spacing(context, 24)),
                          
                          // 상세 코멘트
                          _buildCommentSection(context, theme),
                          SizedBox(height: ResponsiveHelper.spacing(context, 16)),
                          
                          // 안내 문구
                          _buildNotice(context),
                        ],
                      ),
                    ),
            ),
            
            // 버튼
            _buildActions(context, theme),
          ],
        ),
      ),
    );
  }

  /// 헤더
  Widget _buildHeader(BuildContext context, ThemeData theme) {
    return Container(
      padding: ResponsiveHelper.cardPadding(context),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            theme.primaryColor,
            theme.primaryColor.withValues(alpha: 0.8),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(24),
          topRight: Radius.circular(24),
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(
                Icons.rate_review,
                color: Colors.white,
                size: ResponsiveHelper.iconSize(context, 28),
              ),
              SizedBox(width: ResponsiveHelper.spacing(context, 12)),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '사업장 리뷰 작성',
                      style: ResponsiveHelper.subtitleStyle(context).copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      '${widget.reviewYear}년 ${widget.reviewMonth}월',
                      style: ResponsiveHelper.smallStyle(context).copyWith(
                        color: Colors.white.withValues(alpha: 0.9),
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: Icon(Icons.close, color: Colors.white),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 사업장 정보
  Widget _buildBusinessInfo(BuildContext context) {
    return Container(
      padding: ResponsiveHelper.cardPadding(context),
      decoration: BoxDecoration(
        color: AppColors.grey50,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(
            Icons.business,
            color: AppColors.grey600,
            size: ResponsiveHelper.iconSize(context, 24),
          ),
          SizedBox(width: ResponsiveHelper.spacing(context, 12)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.businessName,
                  style: ResponsiveHelper.subtitleStyle(context).copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  '${widget.workDaysInMonth}일 근무',
                  style: ResponsiveHelper.smallStyle(context, color: AppColors.grey600),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 평점 섹션
  Widget _buildRatingSection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              Icons.star,
              color: Colors.amber,
              size: ResponsiveHelper.iconSize(context, 20),
            ),
            SizedBox(width: ResponsiveHelper.spacing(context, 8)),
            Text(
              '전체 평점',
              style: ResponsiveHelper.subtitleStyle(context).copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        SizedBox(height: ResponsiveHelper.spacing(context, 12)),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(5, (index) {
            return GestureDetector(
              onTap: () => setState(() => _rating = index + 1),
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: ResponsiveHelper.spacing(context, 4),
                ),
                child: Icon(
                  index < _rating ? Icons.star : Icons.star_border,
                  color: Colors.amber,
                  size: ResponsiveHelper.iconSize(context, 40),
                ),
              ),
            );
          }),
        ),
        SizedBox(height: ResponsiveHelper.spacing(context, 8)),
        Center(
          child: Text(
            _getRatingText(_rating),
            style: ResponsiveHelper.bodyStyle(context, color: AppColors.grey600),
          ),
        ),
      ],
    );
  }

  String _getRatingText(int rating) {
    switch (rating) {
      case 5: return '최고예요! ⭐';
      case 4: return '좋아요 👍';
      case 3: return '보통이에요';
      case 2: return '아쉬워요';
      case 1: return '별로예요';
      default: return '';
    }
  }

  /// 재근무 의사
  Widget _buildWorkAgainSection(BuildContext context, ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              Icons.replay,
              color: theme.primaryColor,
              size: ResponsiveHelper.iconSize(context, 20),
            ),
            SizedBox(width: ResponsiveHelper.spacing(context, 8)),
            Text(
              '다시 근무하고 싶으신가요?',
              style: ResponsiveHelper.subtitleStyle(context).copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              ' *',
              style: ResponsiveHelper.subtitleStyle(context).copyWith(
                color: AppColors.error,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        SizedBox(height: ResponsiveHelper.spacing(context, 12)),
        Row(
          children: [
            Expanded(
              child: _buildChoiceButton(
                context,
                label: '네, 좋아요',
                icon: Icons.thumb_up,
                isSelected: _wouldWorkAgain == true,
                color: AppColors.success,
                onTap: () => setState(() => _wouldWorkAgain = true),
              ),
            ),
            SizedBox(width: ResponsiveHelper.spacing(context, 12)),
            Expanded(
              child: _buildChoiceButton(
                context,
                label: '아니요',
                icon: Icons.thumb_down,
                isSelected: _wouldWorkAgain == false,
                color: AppColors.error,
                onTap: () => setState(() => _wouldWorkAgain = false),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildChoiceButton(
    BuildContext context, {
    required String label,
    required IconData icon,
    required bool isSelected,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(
          vertical: ResponsiveHelper.spacing(context, 12),
        ),
        decoration: BoxDecoration(
          color: isSelected ? color.withValues(alpha: 0.1) : AppColors.grey50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? color : AppColors.grey200,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              color: isSelected ? color : AppColors.grey500,
              size: ResponsiveHelper.iconSize(context, 20),
            ),
            SizedBox(width: ResponsiveHelper.spacing(context, 8)),
            Text(
              label,
              style: ResponsiveHelper.bodyStyle(context).copyWith(
                color: isSelected ? color : AppColors.grey600,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 태그 섹션
  Widget _buildTagSection(
    BuildContext context, {
    required String title,
    required IconData icon,
    required Color iconColor,
    required List<String> tags,
    required List<String> selectedTags,
    required ValueChanged<List<String>> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: iconColor, size: ResponsiveHelper.iconSize(context, 20)),
            SizedBox(width: ResponsiveHelper.spacing(context, 8)),
            Text(
              title,
              style: ResponsiveHelper.subtitleStyle(context).copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              ' (복수 선택)',
              style: ResponsiveHelper.smallStyle(context, color: AppColors.grey500),
            ),
          ],
        ),
        SizedBox(height: ResponsiveHelper.spacing(context, 12)),
        Wrap(
          spacing: ResponsiveHelper.spacing(context, 8),
          runSpacing: ResponsiveHelper.spacing(context, 8),
          children: tags.map((tag) {
            final isSelected = selectedTags.contains(tag);
            return GestureDetector(
              onTap: () {
                final newTags = List<String>.from(selectedTags);
                if (isSelected) {
                  newTags.remove(tag);
                } else {
                  newTags.add(tag);
                }
                onChanged(newTags);
              },
              child: Container(
                padding: EdgeInsets.symmetric(
                  horizontal: ResponsiveHelper.spacing(context, 12),
                  vertical: ResponsiveHelper.spacing(context, 8),
                ),
                decoration: BoxDecoration(
                  color: isSelected ? iconColor.withValues(alpha: 0.1) : AppColors.grey50,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isSelected ? iconColor : AppColors.grey200,
                  ),
                ),
                child: Text(
                  tag,
                  style: ResponsiveHelper.smallStyle(context).copyWith(
                    color: isSelected ? iconColor : AppColors.grey600,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  /// 코멘트 섹션
  Widget _buildCommentSection(BuildContext context, ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              Icons.edit_note,
              color: theme.primaryColor,
              size: ResponsiveHelper.iconSize(context, 20),
            ),
            SizedBox(width: ResponsiveHelper.spacing(context, 8)),
            Text(
              '상세 후기',
              style: ResponsiveHelper.subtitleStyle(context).copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              ' (선택)',
              style: ResponsiveHelper.smallStyle(context, color: AppColors.grey500),
            ),
          ],
        ),
        SizedBox(height: ResponsiveHelper.spacing(context, 12)),
        TextField(
          controller: _commentController,
          maxLines: 3,
          maxLength: 200,
          decoration: InputDecoration(
            hintText: '근무하면서 느낀 점을 자유롭게 작성해주세요.',
            hintStyle: ResponsiveHelper.bodyStyle(context, color: AppColors.grey400),
            filled: true,
            fillColor: AppColors.grey50,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: AppColors.grey200),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: theme.primaryColor),
            ),
          ),
        ),
      ],
    );
  }

  /// 안내 문구
  Widget _buildNotice(BuildContext context) {
    return Container(
      padding: ResponsiveHelper.cardPadding(context),
      decoration: BoxDecoration(
        color: AppColors.infoBg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.info_outline,
            color: AppColors.info,
            size: ResponsiveHelper.iconSize(context, 18),
          ),
          SizedBox(width: ResponsiveHelper.spacing(context, 8)),
          Expanded(
            child: Text(
              '리뷰는 익명으로 작성되며, 3일 후 공개됩니다.\n작성 후에는 수정할 수 없습니다.',
              style: ResponsiveHelper.smallStyle(context, color: AppColors.info),
            ),
          ),
        ],
      ),
    );
  }

  /// 버튼
  Widget _buildActions(BuildContext context, ThemeData theme) {
    return Container(
      padding: ResponsiveHelper.cardPadding(context),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.grey200)),
      ),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: () => Navigator.pop(context),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.grey600,
                side: BorderSide(color: AppColors.grey300),
                padding: EdgeInsets.symmetric(
                  vertical: ResponsiveHelper.spacing(context, 14),
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text('취소'),
            ),
          ),
          SizedBox(width: ResponsiveHelper.spacing(context, 12)),
          Expanded(
            flex: 2,
            child: ElevatedButton(
              onPressed: _isSubmitting ? null : _submitReview,
              style: ElevatedButton.styleFrom(
                backgroundColor: theme.primaryColor,
                foregroundColor: Colors.white,
                padding: EdgeInsets.symmetric(
                  vertical: ResponsiveHelper.spacing(context, 14),
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: _isSubmitting
                  ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Text('리뷰 작성'),
            ),
          ),
        ],
      ),
    );
  }
}

/// 사업장 리뷰 다이얼로그 표시 헬퍼
Future<bool?> showBusinessReviewDialog(
  BuildContext context, {
  required String reviewerId,
  required String reviewerName,
  required String businessId,
  required String businessName,
  required int reviewYear,
  required int reviewMonth,
  required int workDaysInMonth,
}) {
  return showDialog<bool>(
    context: context,
    builder: (context) => BusinessReviewDialog(
      reviewerId: reviewerId,
      reviewerName: reviewerName,
      businessId: businessId,
      businessName: businessName,
      reviewYear: reviewYear,
      reviewMonth: reviewMonth,
      workDaysInMonth: workDaysInMonth,
    ),
  );
}