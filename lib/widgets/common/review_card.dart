// lib/widgets/common/review_card.dart
//
// 관리자·근로자 양쪽에서 사용하는 공통 리뷰 카드.
// perspective 파라미터로 역할별 표시 차이를 제어한다.

import 'package:flutter/material.dart';

import '../../models/core/monthly_review_model.dart';
import '../../theme/app_colors.dart';
import '../../utils/format_helper.dart';
import '../../utils/responsive_helper.dart';

enum ReviewCardPerspective {
  workerReceived, // 근로자가 자신이 받은 평가를 보는 화면
  adminWritten,   // 관리자가 작성한 평가를 보는 화면 (작성 탭)
  adminReceived,  // 관리자가 근로자에게 받은 평가를 보는 화면 (받은 탭)
}

class ReviewCard extends StatelessWidget {
  final MonthlyReviewModel review;
  final ReviewCardPerspective perspective;

  /// adminReceived 전용 — 답변 버튼 누를 때 호출
  final VoidCallback? onReply;

  /// adminWritten/adminReceived 전용 — 미공개 상태 툴팁 텍스트
  final String? deadlineSubtext;

  const ReviewCard({
    super.key,
    required this.review,
    required this.perspective,
    this.onReply,
    this.deadlineSubtext,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.only(bottom: ResponsiveHelper.spacing(context, 10)),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 14)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(context),
            SizedBox(height: ResponsiveHelper.spacing(context, 10)),
            // 근로자가 보는 화면에서 미공개 리뷰는 내용 블라인드
            // — 별점·태그를 미리 보면 상호 블라인드 공정성이 깨짐
            if (perspective == ReviewCardPerspective.workerReceived &&
                !review.isPublished)
              _buildPendingPlaceholder(context)
            else ...[
              _buildRating(context),
              _buildWorkStats(context),
              _buildTags(context),
              _buildComment(context),
              _buildResponseSection(context),
            ],
          ],
        ),
      ),
    );
  }

  // ─── 헤더 ────────────────────────────────────────────────────────

  Widget _buildHeader(BuildContext context) {
    if (perspective == ReviewCardPerspective.workerReceived) {
      return _buildWorkerHeader(context);
    }
    return _buildAdminHeader(context);
  }

  Widget _buildWorkerHeader(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            review.businessName,
            style: ResponsiveHelper.subtitleStyle(context)
                .copyWith(fontWeight: FontWeight.bold),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (!review.isPublished) ...[
          SizedBox(width: ResponsiveHelper.spacing(context, 6)),
          _buildPendingBadge(context),
        ],
        SizedBox(width: ResponsiveHelper.spacing(context, 6)),
        Text(
          review.periodText,
          style: ResponsiveHelper.smallStyle(context, color: AppColors.grey500),
        ),
      ],
    );
  }

  Widget _buildAdminHeader(BuildContext context) {
    final titleText = perspective == ReviewCardPerspective.adminWritten
        ? (review.targetUserName ?? '지원자')
        : review.reviewerName;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      titleText,
                      style: ResponsiveHelper.bodyStyle(context)
                          .copyWith(fontWeight: FontWeight.bold),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  ),
                  if (perspective == ReviewCardPerspective.adminWritten &&
                      (review.targetUserAge != null ||
                          review.targetUserGender != null)) ...[
                    SizedBox(width: ResponsiveHelper.spacing(context, 4)),
                    Text(
                      '(${[
                        if (review.targetUserAge != null)
                          '${review.targetUserAge}세',
                        if (review.targetUserGender != null)
                          review.targetUserGender!,
                      ].join(', ')})',
                      style: ResponsiveHelper.smallStyle(
                          context, color: AppColors.grey500),
                    ),
                  ],
                ],
              ),
              SizedBox(height: ResponsiveHelper.spacing(context, 2)),
              Text(
                '${review.businessName} · ${review.periodText}',
                style: ResponsiveHelper.smallStyle(
                    context, color: AppColors.grey500),
              ),
            ],
          ),
        ),
        SizedBox(width: ResponsiveHelper.spacing(context, 8)),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildStatusBadge(context),
            SizedBox(height: ResponsiveHelper.spacing(context, 3)),
            Text(
              FormatHelper.formatDateDot(review.createdAt),
              style: ResponsiveHelper.tinyStyle(
                  context, color: AppColors.grey400),
            ),
          ],
        ),
      ],
    );
  }

  // ─── 배지 ────────────────────────────────────────────────────────

  Widget _buildPendingBadge(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 6),
        vertical: ResponsiveHelper.spacing(context, 2),
      ),
      decoration: BoxDecoration(
        color: AppColors.grey100,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        '검토 중',
        style: ResponsiveHelper.tinyStyle(context, color: AppColors.grey500),
      ),
    );
  }

  Widget _buildPendingPlaceholder(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        vertical: ResponsiveHelper.spacing(context, 14),
        horizontal: ResponsiveHelper.spacing(context, 12),
      ),
      decoration: BoxDecoration(
        color: AppColors.grey50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.grey200),
      ),
      child: Column(
        children: [
          Icon(Icons.lock_outline,
              size: ResponsiveHelper.iconSize(context, 22),
              color: AppColors.grey400),
          SizedBox(height: ResponsiveHelper.spacing(context, 6)),
          Text(
            '관리자가 평가를 작성했습니다',
            style: ResponsiveHelper.bodyStyle(context)
                .copyWith(fontWeight: FontWeight.w600, color: AppColors.grey700),
            textAlign: TextAlign.center,
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 4)),
          Text(
            '내 리뷰를 작성하면 서로의 평가가 공개됩니다',
            style: ResponsiveHelper.smallStyle(context, color: AppColors.grey500),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBadge(BuildContext context) {
    final color = review.isPublished ? AppColors.success : AppColors.warning;
    final badge = Container(
      padding: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 9),
        vertical: ResponsiveHelper.spacing(context, 4),
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        review.publishStatusText,
        style: ResponsiveHelper.tinyStyle(context).copyWith(
          color: color,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
    if (review.isPublished || deadlineSubtext == null) return badge;
    return Tooltip(message: deadlineSubtext!, child: badge);
  }

  Widget _buildRehireBadge(BuildContext context) {
    final rehire = review.wouldRehire ?? false;
    final color = rehire ? AppColors.success : AppColors.error;
    final label = perspective == ReviewCardPerspective.adminReceived
        ? (rehire ? '재근무' : '비희망')
        : (rehire ? '재고용' : '비고용');

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 7),
        vertical: ResponsiveHelper.spacing(context, 2),
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            rehire ? Icons.thumb_up_rounded : Icons.thumb_down_rounded,
            size: ResponsiveHelper.iconSize(context, 11),
            color: color,
          ),
          SizedBox(width: ResponsiveHelper.spacing(context, 3)),
          Text(
            label,
            style: ResponsiveHelper.tinyStyle(context).copyWith(
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  // ─── 평점 ────────────────────────────────────────────────────────

  Widget _buildRating(BuildContext context) {
    return Row(
      children: [
        ...List.generate(
          5,
          (i) => Icon(
            i < review.rating
                ? Icons.star_rounded
                : Icons.star_border_rounded,
            size: ResponsiveHelper.iconSize(context, 18),
            color: AppColors.amber,
          ),
        ),
        SizedBox(width: ResponsiveHelper.spacing(context, 5)),
        Text(
          review.ratingText,
          style: ResponsiveHelper.smallStyle(context).copyWith(
            fontWeight: FontWeight.w600,
            color: AppColors.grey700,
          ),
        ),
        if (review.wouldRehire != null) ...[
          SizedBox(width: ResponsiveHelper.spacing(context, 8)),
          _buildRehireBadge(context),
        ],
      ],
    );
  }

  // ─── 근무 통계 ────────────────────────────────────────────────────

  Widget _buildWorkStats(BuildContext context) {
    final hasDays = review.workDaysInMonth > 0;
    final hasLate = review.lateDays > 0;
    if (!hasDays && !hasLate) return const SizedBox.shrink();

    return Padding(
      padding: EdgeInsets.only(top: ResponsiveHelper.spacing(context, 8)),
      child: Row(
        children: [
          Icon(Icons.work_outline,
              size: ResponsiveHelper.iconSize(context, 12),
              color: AppColors.grey400),
          SizedBox(width: ResponsiveHelper.spacing(context, 3)),
          if (hasDays)
            Text(
              '근무 ${review.workDaysInMonth}일',
              style: ResponsiveHelper.tinyStyle(
                  context, color: AppColors.grey500),
            ),
          if (hasLate)
            Text(
              '${hasDays ? ' · ' : ''}지각 ${review.lateDays}회',
              style: ResponsiveHelper.tinyStyle(
                  context, color: AppColors.warning),
            ),
        ],
      ),
    );
  }

  // ─── 태그 ────────────────────────────────────────────────────────

  Widget _buildTags(BuildContext context) {
    if (review.positiveTags.isEmpty && review.improvementTags.isEmpty) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: EdgeInsets.only(top: ResponsiveHelper.spacing(context, 8)),
      child: Wrap(
        spacing: ResponsiveHelper.spacing(context, 5),
        runSpacing: ResponsiveHelper.spacing(context, 5),
        children: [
          ...review.positiveTags
              .map((t) => _buildTag(context, t, isPositive: true)),
          ...review.improvementTags
              .map((t) => _buildTag(context, t, isPositive: false)),
        ],
      ),
    );
  }

  Widget _buildTag(BuildContext context, String label,
      {required bool isPositive}) {
    final color = isPositive ? AppColors.success : AppColors.warning;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 8),
        vertical: ResponsiveHelper.spacing(context, 4),
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(label,
          style: ResponsiveHelper.tinyStyle(context).copyWith(color: color)),
    );
  }

  // ─── 코멘트 ────────────────────────────────────────────────────────

  Widget _buildComment(BuildContext context) {
    if (perspective == ReviewCardPerspective.workerReceived) {
      return const SizedBox.shrink();
    }
    if (review.comment == null || review.comment!.isEmpty) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: EdgeInsets.only(top: ResponsiveHelper.spacing(context, 8)),
      child: Text(
        '"${review.comment!}"',
        style: ResponsiveHelper.smallStyle(context, color: AppColors.grey600),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  // ─── 사업장 답변 ────────────────────────────────────────────────────

  Widget _buildResponseSection(BuildContext context) {
    final hasResponse = review.businessResponse != null &&
        review.businessResponse!.isNotEmpty;

    if (hasResponse) {
      return Padding(
        padding: EdgeInsets.only(top: ResponsiveHelper.spacing(context, 6)),
        child: Container(
          width: double.infinity,
          padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 8)),
          decoration: BoxDecoration(
            color: AppColors.info.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: AppColors.info.withValues(alpha: 0.2)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.store,
                      size: ResponsiveHelper.iconSize(context, 11),
                      color: AppColors.info),
                  SizedBox(width: ResponsiveHelper.spacing(context, 3)),
                  Text(
                    '사업장 답변',
                    style: ResponsiveHelper.tinyStyle(context).copyWith(
                        color: AppColors.info, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              SizedBox(height: ResponsiveHelper.spacing(context, 3)),
              Text(
                review.businessResponse!,
                style: ResponsiveHelper.smallStyle(
                    context, color: AppColors.grey700),
              ),
            ],
          ),
        ),
      );
    }

    // 관리자가 받은 리뷰 → 답변하기 버튼
    if (perspective == ReviewCardPerspective.adminReceived) {
      return Padding(
        padding: EdgeInsets.only(top: ResponsiveHelper.spacing(context, 4)),
        child: Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: onReply,
            icon: Icon(Icons.reply,
                size: ResponsiveHelper.iconSize(context, 14)),
            label: Text('답변하기',
                style: ResponsiveHelper.smallStyle(context)),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.info,
              padding: EdgeInsets.symmetric(
                horizontal: ResponsiveHelper.spacing(context, 8),
                vertical: ResponsiveHelper.spacing(context, 4),
              ),
            ),
          ),
        ),
      );
    }

    return const SizedBox.shrink();
  }
}
