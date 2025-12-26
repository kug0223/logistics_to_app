// lib/widgets/dialogs/monthly_review_dialog.dart

import 'package:flutter/material.dart';
import '../../utils/responsive_helper.dart';
import '../../theme/app_colors.dart';
import '../../models/core/monthly_review_model.dart';
import '../../models/settings/trust_settings_model.dart';
import '../../services/monthly_review_service.dart';
import '../../utils/toast_helper.dart';
import 'styled_dialog.dart';

/// 월별 리뷰 작성 다이얼로그 (관리자 → 지원자)
/// 
/// 정책:
/// - 월 1회만 작성 가능
/// - 작성 후 수정 불가
/// - 3일 후 공개
class MonthlyReviewDialog extends StatefulWidget {
  /// 작성자 (관리자) UID
  final String reviewerId;
  
  /// 작성자 이름
  final String reviewerName;
  
  /// 사업장 ID
  final String businessId;
  
  /// 사업장 이름
  final String businessName;
  
  /// 리뷰 대상 사용자 UID
  final String targetUserId;
  
  /// 리뷰 대상 사용자 이름
  final String targetUserName;
  
  /// 리뷰 대상 년도
  final int reviewYear;
  
  /// 리뷰 대상 월
  final int reviewMonth;
  
  /// 해당 월 근무 일수
  final int workDaysInMonth;
  
  /// 해당 월 정상 출근 일수
  final int normalAttendanceDays;
  
  /// 해당 월 지각 횟수
  final int lateDays;

  const MonthlyReviewDialog({
    super.key,
    required this.reviewerId,
    required this.reviewerName,
    required this.businessId,
    required this.businessName,
    required this.targetUserId,
    required this.targetUserName,
    required this.reviewYear,
    required this.reviewMonth,
    required this.workDaysInMonth,
    this.normalAttendanceDays = 0,
    this.lateDays = 0,
  });

  @override
  State<MonthlyReviewDialog> createState() => _MonthlyReviewDialogState();
}

class _MonthlyReviewDialogState extends State<MonthlyReviewDialog> {
  final _commentController = TextEditingController();
  final _reviewService = MonthlyReviewService();
  
  // 상태
  int _rating = 4;
  bool? _wouldRehire;
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
      print('❌ 태그 로드 실패: $e');
    }
    setState(() => _isLoading = false);
  }

  Future<void> _submitReview() async {
    // 유효성 검사
    if (_wouldRehire == null) {
      ToastHelper.showWarning('재고용 의사를 선택해주세요.');
      return;
    }
    
    setState(() => _isSubmitting = true);
    
    final result = await _reviewService.createReviewForUser(
      reviewerId: widget.reviewerId,
      reviewerName: widget.reviewerName,
      businessId: widget.businessId,
      businessName: widget.businessName,
      targetUserId: widget.targetUserId,
      targetUserName: widget.targetUserName,
      reviewYear: widget.reviewYear,
      reviewMonth: widget.reviewMonth,
      workDaysInMonth: widget.workDaysInMonth,
      normalAttendanceDays: widget.normalAttendanceDays,
      lateDays: widget.lateDays,
      rating: _rating,
      wouldRehire: _wouldRehire!,
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
                '리뷰가 작성되었습니다.\n3일 후 ${widget.targetUserName}님에게 공개됩니다.',
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
                          // 근태 요약
                          _buildAttendanceSummary(context),
                          SizedBox(height: ResponsiveHelper.spacing(context, 24)),
                          
                          // 평점
                          _buildRatingSection(context),
                          SizedBox(height: ResponsiveHelper.spacing(context, 24)),
                          
                          // 재고용 의사
                          _buildRehireSection(context, theme),
                          SizedBox(height: ResponsiveHelper.spacing(context, 24)),
                          
                          // 긍정 태그
                          _buildTagSection(
                            context,
                            title: '좋았던 점',
                            icon: Icons.thumb_up_outlined,
                            iconColor: AppColors.success,
                            tags: _tags.positiveTags,
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
                            tags: _tags.improvementTags,
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
            theme.primaryColor.withOpacity(0.8),
          ],
        ),
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(24),
          topRight: Radius.circular(24),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 12)),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(
              Icons.rate_review,
              color: Colors.white,
              size: ResponsiveHelper.iconSize(context, 28),
            ),
          ),
          SizedBox(width: ResponsiveHelper.spacing(context, 16)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${widget.reviewMonth}월 리뷰 작성',
                  style: ResponsiveHelper.titleStyle(context).copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: ResponsiveHelper.spacing(context, 4)),
                Text(
                  widget.targetUserName,
                  style: ResponsiveHelper.smallStyle(context, color: Colors.white70),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: Icon(
              Icons.close,
              color: Colors.white,
              size: ResponsiveHelper.iconSize(context, 24),
            ),
          ),
        ],
      ),
    );
  }

  /// 근태 요약
  Widget _buildAttendanceSummary(BuildContext context) {
    final absenceDays = widget.workDaysInMonth - widget.normalAttendanceDays - widget.lateDays;
    
    return Container(
      padding: ResponsiveHelper.cardPadding(context),
      decoration: BoxDecoration(
        color: AppColors.grey50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.grey200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.analytics_outlined,
                size: ResponsiveHelper.iconSize(context, 20),
                color: AppColors.grey600,
              ),
              SizedBox(width: ResponsiveHelper.spacing(context, 8)),
              Text(
                '${widget.reviewMonth}월 근태 요약',
                style: ResponsiveHelper.subtitleStyle(context).copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 12)),
          Row(
            children: [
              _buildStatItem(context, '근무일', '${widget.workDaysInMonth}일', AppColors.info),
              _buildStatItem(context, '정상 출근', '${widget.normalAttendanceDays}일', AppColors.success),
              _buildStatItem(context, '지각', '${widget.lateDays}회', 
                  widget.lateDays > 0 ? AppColors.warning : AppColors.grey400),
              if (absenceDays > 0)
                _buildStatItem(context, '결근', '${absenceDays}일', AppColors.error),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(BuildContext context, String label, String value, Color color) {
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: ResponsiveHelper.subtitleStyle(context).copyWith(
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 4)),
          Text(
            label,
            style: ResponsiveHelper.smallStyle(context, color: AppColors.grey500),
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
        Text(
          '종합 평가',
          style: ResponsiveHelper.subtitleStyle(context).copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        SizedBox(height: ResponsiveHelper.spacing(context, 12)),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(5, (index) {
            final starIndex = index + 1;
            return GestureDetector(
              onTap: () => setState(() => _rating = starIndex),
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: ResponsiveHelper.spacing(context, 4),
                ),
                child: Icon(
                  starIndex <= _rating ? Icons.star : Icons.star_border,
                  size: ResponsiveHelper.iconSize(context, 40),
                  color: Colors.amber,
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
      case 4: return '좋았어요 👍';
      case 3: return '보통이에요';
      case 2: return '아쉬웠어요';
      case 1: return '많이 부족해요';
      default: return '';
    }
  }

  /// 재고용 의사 섹션
  Widget _buildRehireSection(BuildContext context, ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              '재고용 의사',
              style: ResponsiveHelper.subtitleStyle(context).copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(width: ResponsiveHelper.spacing(context, 8)),
            Container(
              padding: EdgeInsets.symmetric(
                horizontal: ResponsiveHelper.spacing(context, 8),
                vertical: ResponsiveHelper.spacing(context, 2),
              ),
              decoration: BoxDecoration(
                color: AppColors.warningBg,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                '관리자 전용',
                style: ResponsiveHelper.tinyStyle(context, color: AppColors.warningDark),
              ),
            ),
          ],
        ),
        SizedBox(height: ResponsiveHelper.spacing(context, 4)),
        Text(
          '이 정보는 다른 관리자에게만 공개됩니다.',
          style: ResponsiveHelper.smallStyle(context, color: AppColors.grey500),
        ),
        SizedBox(height: ResponsiveHelper.spacing(context, 12)),
        Row(
          children: [
            Expanded(
              child: _buildRehireOption(
                context,
                theme,
                label: '예, 다시 함께하고 싶어요',
                icon: Icons.thumb_up,
                isSelected: _wouldRehire == true,
                color: AppColors.success,
                onTap: () => setState(() => _wouldRehire = true),
              ),
            ),
            SizedBox(width: ResponsiveHelper.spacing(context, 12)),
            Expanded(
              child: _buildRehireOption(
                context,
                theme,
                label: '아니요',
                icon: Icons.thumb_down,
                isSelected: _wouldRehire == false,
                color: AppColors.error,
                onTap: () => setState(() => _wouldRehire = false),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildRehireOption(
    BuildContext context,
    ThemeData theme, {
    required String label,
    required IconData icon,
    required bool isSelected,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: ResponsiveHelper.cardPadding(context),
        decoration: BoxDecoration(
          color: isSelected ? color.withOpacity(0.1) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? color : AppColors.grey300,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Column(
          children: [
            Icon(
              icon,
              size: ResponsiveHelper.iconSize(context, 28),
              color: isSelected ? color : AppColors.grey400,
            ),
            SizedBox(height: ResponsiveHelper.spacing(context, 8)),
            Text(
              label,
              style: ResponsiveHelper.smallStyle(
                context,
                color: isSelected ? color : AppColors.grey600,
              ),
              textAlign: TextAlign.center,
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
            Icon(
              icon,
              size: ResponsiveHelper.iconSize(context, 20),
              color: iconColor,
            ),
            SizedBox(width: ResponsiveHelper.spacing(context, 8)),
            Text(
              title,
              style: ResponsiveHelper.subtitleStyle(context).copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(width: ResponsiveHelper.spacing(context, 8)),
            Text(
              '(복수 선택 가능)',
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
                  color: isSelected ? iconColor.withOpacity(0.1) : Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isSelected ? iconColor : AppColors.grey300,
                  ),
                ),
                child: Text(
                  tag,
                  style: ResponsiveHelper.smallStyle(
                    context,
                    color: isSelected ? iconColor : AppColors.grey600,
                  ).copyWith(
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

  /// 상세 코멘트 섹션
  Widget _buildCommentSection(BuildContext context, ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              Icons.edit_note,
              size: ResponsiveHelper.iconSize(context, 20),
              color: AppColors.grey600,
            ),
            SizedBox(width: ResponsiveHelper.spacing(context, 8)),
            Text(
              '상세 코멘트',
              style: ResponsiveHelper.subtitleStyle(context).copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(width: ResponsiveHelper.spacing(context, 8)),
            Container(
              padding: EdgeInsets.symmetric(
                horizontal: ResponsiveHelper.spacing(context, 8),
                vertical: ResponsiveHelper.spacing(context, 2),
              ),
              decoration: BoxDecoration(
                color: AppColors.warningBg,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                '관리자 전용',
                style: ResponsiveHelper.tinyStyle(context, color: AppColors.warningDark),
              ),
            ),
          ],
        ),
        SizedBox(height: ResponsiveHelper.spacing(context, 4)),
        Text(
          '이 내용은 다른 관리자에게만 공개됩니다. (선택)',
          style: ResponsiveHelper.smallStyle(context, color: AppColors.grey500),
        ),
        SizedBox(height: ResponsiveHelper.spacing(context, 12)),
        TextField(
          controller: _commentController,
          maxLines: 3,
          maxLength: 500,
          style: ResponsiveHelper.bodyStyle(context),
          decoration: InputDecoration(
            hintText: '채용 시 참고할 내용을 작성해주세요.',
            hintStyle: ResponsiveHelper.smallStyle(context, color: AppColors.grey400),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: AppColors.grey300),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: AppColors.grey300),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: theme.primaryColor, width: 2),
            ),
            filled: true,
            fillColor: Colors.white,
            contentPadding: ResponsiveHelper.cardPadding(context),
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
        border: Border.all(color: AppColors.info.withOpacity(0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.info_outline,
            size: ResponsiveHelper.iconSize(context, 20),
            color: AppColors.infoDark,
          ),
          SizedBox(width: ResponsiveHelper.spacing(context, 12)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '작성 후 수정이 불가합니다.',
                  style: ResponsiveHelper.smallStyle(context, color: AppColors.infoDark).copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: ResponsiveHelper.spacing(context, 4)),
                Text(
                  '신중하게 작성해주세요. 작성 후 3일 뒤 ${widget.targetUserName}님에게 점수와 태그가 공개됩니다.',
                  style: ResponsiveHelper.smallStyle(context, color: AppColors.infoDark),
                ),
              ],
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
        color: Colors.white,
        border: Border(
          top: BorderSide(color: AppColors.grey200),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: _isSubmitting ? null : () => Navigator.pop(context),
              style: OutlinedButton.styleFrom(
                padding: EdgeInsets.symmetric(
                  vertical: ResponsiveHelper.spacing(context, 16),
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                side: BorderSide(color: AppColors.grey300),
              ),
              child: Text(
                '취소',
                style: ResponsiveHelper.bodyStyle(context, color: AppColors.grey600),
              ),
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
                  vertical: ResponsiveHelper.spacing(context, 16),
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 0,
              ),
              child: _isSubmitting
                  ? SizedBox(
                      height: ResponsiveHelper.iconSize(context, 20),
                      width: ResponsiveHelper.iconSize(context, 20),
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Text(
                      '리뷰 작성',
                      style: ResponsiveHelper.bodyStyle(context, color: Colors.white).copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 리뷰 작성 다이얼로그 표시 헬퍼
Future<bool?> showMonthlyReviewDialog(
  BuildContext context, {
  required String reviewerId,
  required String reviewerName,
  required String businessId,
  required String businessName,
  required String targetUserId,
  required String targetUserName,
  required int reviewYear,
  required int reviewMonth,
  required int workDaysInMonth,
  int normalAttendanceDays = 0,
  int lateDays = 0,
}) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (context) => MonthlyReviewDialog(
      reviewerId: reviewerId,
      reviewerName: reviewerName,
      businessId: businessId,
      businessName: businessName,
      targetUserId: targetUserId,
      targetUserName: targetUserName,
      reviewYear: reviewYear,
      reviewMonth: reviewMonth,
      workDaysInMonth: workDaysInMonth,
      normalAttendanceDays: normalAttendanceDays,
      lateDays: lateDays,
    ),
  );
}