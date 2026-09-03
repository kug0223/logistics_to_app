// lib/widgets/dialogs/business_review_dialog.dart

import 'package:flutter/material.dart';
import '../../utils/responsive_helper.dart';
import '../../theme/app_colors.dart';
import '../../models/settings/trust_settings_model.dart';
import '../../services/monthly_review_service.dart';
import '../../utils/toast_helper.dart';
import 'styled_dialog.dart';
import 'review_dialog_shell.dart';

/// 지원자 → 사업장 리뷰 작성 다이얼로그
/// 
/// 정책:
/// - 월 1회만 작성 가능
/// - 작성 후 수정 불가
/// - 즉시공개(상대방 작성 시) or 14일 후 자동 공개
/// - 익명 작성
class BusinessReviewDialog extends StatefulWidget {
  /// 작성자 (지원자) UID
  final String reviewerId;
  
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

  /// review_requests 문서 ID (양방향 공개 연동)
  final String? requestId;

  /// 미리 로드된 태그 목록 (showBusinessReviewDialog에서 주입)
  final ReviewTagsModel preloadedTags;

  const BusinessReviewDialog({
    super.key,
    required this.reviewerId,
    required this.businessId,
    required this.businessName,
    required this.reviewYear,
    required this.reviewMonth,
    required this.workDaysInMonth,
    this.requestId,
    required this.preloadedTags,
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
  bool _isSubmitting = false;

  // 태그 목록 (showBusinessReviewDialog에서 미리 로드 후 주입)
  late ReviewTagsModel _tags;

  @override
  void initState() {
    super.initState();
    _tags = widget.preloadedTags;
  }

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _submitReview() async {
    // 유효성 검사
    if (_wouldWorkAgain == null) {
      ToastHelper.showWarning('다시 근무할 의향을 선택해주세요.');
      return;
    }
    
    setState(() => _isSubmitting = true);

    try {
      final result = await _reviewService.createReviewForBusiness(
        reviewerId: widget.reviewerId,
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
        requestId: widget.requestId,
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
                  size: ResponsiveHelper.iconSize(resultContext, 48),
                  color: AppColors.info,
                ),
                SizedBox(height: ResponsiveHelper.spacing(resultContext, 16)),
                Text(
                  '리뷰가 작성되었습니다.\n관리자도 리뷰를 작성하면 즉시 공개됩니다.\n(미작성 시 14일 후 자동 공개)',
                  style: ResponsiveHelper.bodyStyle(resultContext),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
            actions: [
              StyledDialogButton.primary(
                text: '확인',
                onPressed: () {
                  // [FC-10 FIX] 중첩 다이얼로그 확인 — pop 전 unfocus (_commentController 보호)
                  FocusManager.instance.primaryFocus?.unfocus();
                  Navigator.pop(resultContext);
                  Navigator.pop(context, true);
                },
              ),
            ],
          ),
        );
      } else {
        if (mounted) ToastHelper.showError(result.error ?? '리뷰 작성에 실패했습니다.');
      }
    } catch (e) {
      debugPrint('❌ 리뷰 제출 실패: $e');
      if (mounted) ToastHelper.showError('리뷰 작성에 실패했습니다.');
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ReviewDialogShell(
      header: _buildHeader(context, theme),
      body: [
        _buildBusinessInfo(context),
        SizedBox(height: ResponsiveHelper.spacing(context, 24)),
        _buildRatingSection(context),
        SizedBox(height: ResponsiveHelper.spacing(context, 24)),
        _buildWorkAgainSection(context, theme),
        SizedBox(height: ResponsiveHelper.spacing(context, 24)),
        _buildTagSection(
          context,
          title: '좋았던 점',
          icon: Icons.thumb_up_outlined,
          iconColor: AppColors.success,
          tags: _tags.businessPositiveTags,
          selectedTags: _selectedPositiveTags,
          onChanged: (tags) => setState(() => _selectedPositiveTags = tags),
        ),
        SizedBox(height: ResponsiveHelper.spacing(context, 24)),
        _buildTagSection(
          context,
          title: '아쉬운 점',
          icon: Icons.lightbulb_outline,
          iconColor: AppColors.warning,
          tags: _tags.businessImprovementTags,
          selectedTags: _selectedImprovementTags,
          onChanged: (tags) => setState(() => _selectedImprovementTags = tags),
        ),
        SizedBox(height: ResponsiveHelper.spacing(context, 24)),
        _buildCommentSection(context, theme),
        SizedBox(height: ResponsiveHelper.spacing(context, 16)),
        _buildNotice(context),
      ],
      actions: _buildActions(context, theme),
    );
  }

  /// 헤더 — flat AppModalHeader (ALfit Modal Grammar)
  Widget _buildHeader(BuildContext context, ThemeData theme) {
    return AppModalHeader(
      title: '사업장 리뷰 작성',
      subtitle: '${widget.reviewYear}년 ${widget.reviewMonth}월',
      onClose: () {
        FocusManager.instance.primaryFocus?.unfocus();
        Navigator.pop(context);
      },
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
              color: AppColors.amber,
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
            final starValue = index + 1;
            return Semantics(
              label: '$starValue점',
              button: true,
              selected: _rating == starValue,
              child: GestureDetector(
                onTap: () => setState(() => _rating = starValue),
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: ResponsiveHelper.spacing(context, 4),
                  ),
                  child: Icon(
                    index < _rating ? Icons.star : Icons.star_border,
                    color: AppColors.amber,
                    size: ResponsiveHelper.iconSize(context, 40),
                  ),
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
            Expanded(
              child: Text(
                '다시 근무하고 싶으신가요?',
                style: ResponsiveHelper.subtitleStyle(context).copyWith(
                  fontWeight: FontWeight.bold,
                ),
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
            Expanded(
              child: Text(
                title,
                style: ResponsiveHelper.subtitleStyle(context).copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            Text(
              '복수 선택',
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
            Expanded(
              child: Text(
                '상세 후기',
                style: ResponsiveHelper.subtitleStyle(context).copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            Text(
              '선택',
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
              '리뷰는 익명으로 작성됩니다. 관리자도 리뷰를 작성하면 즉시 공개되며, 미작성 시 14일 후 자동 공개됩니다.\n작성 후에는 수정할 수 없습니다.',
              style: ResponsiveHelper.smallStyle(context, color: AppColors.info),
            ),
          ),
        ],
      ),
    );
  }

  /// 버튼 — ReviewDialogShell scroll 내부에 위치 (keyboard-safe)
  Widget _buildActions(BuildContext context, ThemeData theme) {
    return Row(
      children: [
        Expanded(
          child: StyledDialogButton.cancel(
            onPressed: _isSubmitting ? null : () {
              FocusManager.instance.primaryFocus?.unfocus();
              Navigator.pop(context);
            },
          ),
        ),
        SizedBox(width: ResponsiveHelper.spacing(context, 12)),
        Expanded(
          flex: 2,
          child: StyledDialogButton.primary(
            text: '리뷰 작성',
            onPressed: _isSubmitting ? null : _submitReview,
            isLoading: _isSubmitting,
          ),
        ),
      ],
    );
  }
}

/// 사업장 리뷰 다이얼로그 표시 헬퍼
Future<bool?> showBusinessReviewDialog(
  BuildContext context, {
  required String reviewerId,
  required String businessId,
  required String businessName,
  required int reviewYear,
  required int reviewMonth,
  required int workDaysInMonth,
  String? requestId,
}) async {
  // 다이얼로그 열기 전 태그 미리 로드 — 빈 폼 플래시 방지
  ReviewTagsModel tags;
  try {
    tags = await MonthlyReviewService().getReviewTags();
  } catch (_) {
    tags = ReviewTagsModel.defaults();
  }
  if (!context.mounted) return null;

  return showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (context) => BusinessReviewDialog(
      reviewerId: reviewerId,
      businessId: businessId,
      businessName: businessName,
      reviewYear: reviewYear,
      reviewMonth: reviewMonth,
      workDaysInMonth: workDaysInMonth,
      requestId: requestId,
      preloadedTags: tags,
    ),
  );
}