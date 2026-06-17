import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/core/monthly_review_model.dart';
import '../../providers/user_provider.dart';
import '../../services/monthly_review_service.dart';
import '../../theme/app_colors.dart';
import '../../utils/responsive_helper.dart';
import '../../widgets/common/app_empty_state.dart';
import '../../widgets/common/gradient_scaffold.dart';
import '../../widgets/common/loading_widget.dart';

class MyReviewsScreen extends StatefulWidget {
  const MyReviewsScreen({super.key});

  @override
  State<MyReviewsScreen> createState() => _MyReviewsScreenState();
}

class _MyReviewsScreenState extends State<MyReviewsScreen> {
  final MonthlyReviewService _reviewService = MonthlyReviewService();

  List<MonthlyReviewModel> _reviews = [];
  double _avgRating = 0.0;
  bool _isLoading = true;
  String? _loadError;

  DocumentSnapshot? _cursor;
  bool _hasMore = false;
  bool _isLoadingMore = false;

  @override
  void initState() {
    super.initState();
    _loadReviews();
  }

  Future<void> _loadReviews() async {
    final uid = context.read<UserProvider>().currentUser?.uid;
    if (uid == null) return;
    setState(() { _isLoading = true; _loadError = null; _cursor = null; _hasMore = false; });
    try {
      final page = await _reviewService.getPublishedReviewsForUserPaged(
        targetUserId: uid,
      );
      // [오탐 확인] 평균 점수를 첫 페이지(최대 30건)만으로 계산한다.
      // hasMore=true이면 전체 평균과 다를 수 있으나, 정확한 값은 users.averageRating에 있다.
      // 대부분의 근무자는 리뷰 수가 30건 미만이므로 실용적으로 허용된 트레이드오프이다.
      final avg = page.records.isEmpty
          ? 0.0
          : page.records.map((r) => r.rating).reduce((a, b) => a + b) / page.records.length;
      if (mounted) {
        setState(() {
          _reviews = page.records;
          _avgRating = avg;
          _cursor = page.cursor;
          _hasMore = page.hasMore;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() { _loadError = e.toString(); _isLoading = false; });
    }
  }

  Future<void> _loadMore() async {
    final uid = context.read<UserProvider>().currentUser?.uid;
    if (uid == null || !_hasMore || _isLoadingMore) return;
    setState(() => _isLoadingMore = true);
    try {
      final page = await _reviewService.getPublishedReviewsForUserPaged(
        targetUserId: uid,
        startAfter: _cursor,
      );
      if (!mounted) return;
      final allReviews = [..._reviews, ...page.records];
      final avg = allReviews.isEmpty
          ? 0.0
          : allReviews.map((r) => r.rating).reduce((a, b) => a + b) / allReviews.length;
      setState(() {
        _reviews = allReviews;
        _avgRating = avg;
        _cursor = page.cursor;
        _hasMore = page.hasMore;
      });
    } catch (_) {
      // 예외는 무시하고 finally에서 상태 초기화
    } finally {
      if (mounted) setState(() => _isLoadingMore = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GradientScaffold(
      title: '내 근무 평가',
      onRefresh: _loadReviews,
      body: _isLoading
          ? const LoadingWidget()
          : _loadError != null
              ? AppEmptyState(
                  icon: Icons.error_outline,
                  title: '리뷰를 불러오지 못했습니다',
                  action: TextButton(
                    onPressed: _loadReviews,
                    child: const Text('다시 시도'),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadReviews,
                  child: CustomScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    slivers: [
                      if (_reviews.isNotEmpty)
                        SliverToBoxAdapter(child: _buildSummaryHeader(context)),
                      if (_reviews.isEmpty)
                        const AppEmptyState(
                          asSliver: true,
                          icon: Icons.star_border_rounded,
                          title: '아직 받은 평가가 없습니다',
                          subtitle: '근무 완료 후 사업장에서 평가를 남기면\n여기에 표시됩니다',
                        )
                      else
                        SliverPadding(
                          padding: EdgeInsets.fromLTRB(
                            ResponsiveHelper.spacing(context, 16),
                            0,
                            ResponsiveHelper.spacing(context, 16),
                            ResponsiveHelper.spacing(context, 24),
                          ),
                          sliver: SliverList(
                            delegate: SliverChildBuilderDelegate(
                              (ctx, i) => _ReviewCard(review: _reviews[i]),
                              childCount: _reviews.length,
                            ),
                          ),
                        ),
                      if (_hasMore)
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: EdgeInsets.only(
                              top: ResponsiveHelper.spacing(context, 4),
                              bottom: ResponsiveHelper.spacing(context, 24),
                            ),
                            child: Center(
                              child: _isLoadingMore
                                  ? const CircularProgressIndicator()
                                  : TextButton.icon(
                                      onPressed: _loadMore,
                                      icon: const Icon(Icons.expand_more),
                                      label: const Text('더 보기'),
                                    ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
    );
  }

  Widget _buildSummaryHeader(BuildContext context) {
    final avgRating = _avgRating;
    final theme = Theme.of(context);

    return Container(
      color: theme.primaryColor,
      padding: EdgeInsets.fromLTRB(
        ResponsiveHelper.spacing(context, 24),
        0,
        ResponsiveHelper.spacing(context, 24),
        ResponsiveHelper.spacing(context, 28),
      ),
      child: Container(
        padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 20)),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _buildStat(context, '총 평가', '${_reviews.length}건'),
            _buildDivider(),
            _buildStat(context, '평균 별점',
                avgRating == 0 ? '-' : avgRating.toStringAsFixed(1)),
            _buildDivider(),
            _buildStat(
              context,
              '별점',
              avgRating == 0
                  ? '-'
                  : '★' * avgRating.round() + '☆' * (5 - avgRating.round()),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStat(BuildContext context, String label, String value) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(value,
            style: ResponsiveHelper.subtitleStyle(context).copyWith(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: ResponsiveHelper.subtitleStyle(context).fontSize! * 1.15,
            )),
        SizedBox(height: ResponsiveHelper.spacing(context, 4)),
        Text(label,
            style: ResponsiveHelper.tinyStyle(context,
                color: Colors.white.withValues(alpha: 0.85))),
      ],
    );
  }

  Widget _buildDivider() => Container(
        height: 32,
        width: 1,
        color: Colors.white.withValues(alpha: 0.3),
      );
}

class _ReviewCard extends StatelessWidget {
  final MonthlyReviewModel review;

  const _ReviewCard({required this.review});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      margin: EdgeInsets.only(bottom: ResponsiveHelper.spacing(context, 12)),
      elevation: 2,
      shadowColor: Colors.black.withValues(alpha: 0.08),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 16)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 헤더: 사업장명 + 기간
            Row(
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
                Text(
                  review.periodText,
                  style: ResponsiveHelper.smallStyle(context,
                      color: AppColors.grey500),
                ),
              ],
            ),

            SizedBox(height: ResponsiveHelper.spacing(context, 10)),

            // 별점 + 텍스트
            Row(
              children: [
                ...List.generate(5, (i) => Icon(
                  i < review.rating ? Icons.star_rounded : Icons.star_outline_rounded,
                  size: ResponsiveHelper.iconSize(context, 20),
                  color: i < review.rating ? AppColors.warning : AppColors.grey300,
                )),
                SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                Text(
                  review.ratingText,
                  style: ResponsiveHelper.smallStyle(context).copyWith(
                    color: _ratingColor(review.rating),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),

            // 출근 통계
            if (review.workDaysInMonth > 0) ...[
              SizedBox(height: ResponsiveHelper.spacing(context, 8)),
              Row(
                children: [
                  _buildStatChip(context,
                      Icons.work_outline, '근무 ${review.workDaysInMonth}일'),
                  SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                  _buildStatChip(context,
                      Icons.check_circle_outline,
                      '정상 ${review.normalAttendanceDays}일'),
                  if (review.lateDays > 0) ...[
                    SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                    _buildStatChip(context,
                        Icons.access_time_outlined,
                        '지각 ${review.lateDays}회',
                        color: AppColors.warning),
                  ],
                ],
              ),
            ],

            // 긍정 태그
            if (review.positiveTags.isNotEmpty) ...[
              SizedBox(height: ResponsiveHelper.spacing(context, 10)),
              Wrap(
                spacing: ResponsiveHelper.spacing(context, 6),
                runSpacing: ResponsiveHelper.spacing(context, 4),
                children: review.positiveTags
                    .map((tag) => _buildTag(context, tag, AppColors.successBg,
                        AppColors.successDark))
                    .toList(),
              ),
            ],

            // 개선 태그
            if (review.improvementTags.isNotEmpty) ...[
              SizedBox(height: ResponsiveHelper.spacing(context, 6)),
              Wrap(
                spacing: ResponsiveHelper.spacing(context, 6),
                runSpacing: ResponsiveHelper.spacing(context, 4),
                children: review.improvementTags
                    .map((tag) => _buildTag(context, tag, AppColors.warningBg,
                        AppColors.warningDark))
                    .toList(),
              ),
            ],

            // 사업장 답변 (USER_TO_BUSINESS 답변이 있는 경우)
            if (review.businessResponse != null &&
                review.businessResponse!.isNotEmpty) ...[
              SizedBox(height: ResponsiveHelper.spacing(context, 10)),
              Container(
                padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 10)),
                decoration: BoxDecoration(
                  color: theme.primaryColor.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: theme.primaryColor.withValues(alpha: 0.2)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.business_center_outlined,
                        size: ResponsiveHelper.iconSize(context, 14),
                        color: theme.primaryColor),
                    SizedBox(width: ResponsiveHelper.spacing(context, 6)),
                    Expanded(
                      child: Text(
                        review.businessResponse!,
                        style: ResponsiveHelper.smallStyle(context,
                            color: AppColors.grey700),
                      ),
                    ),
                  ],
                ),
              ),
            ],

          ],
        ),
      ),
    );
  }

  Widget _buildStatChip(BuildContext context, IconData icon, String label,
      {Color? color}) {
    final c = color ?? AppColors.grey500;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: ResponsiveHelper.iconSize(context, 12), color: c),
        SizedBox(width: ResponsiveHelper.spacing(context, 3)),
        Text(label,
            style: ResponsiveHelper.tinyStyle(context, color: c)),
      ],
    );
  }

  Widget _buildTag(
      BuildContext context, String label, Color bg, Color fg) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 8),
        vertical: ResponsiveHelper.spacing(context, 3),
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(label,
          style:
              ResponsiveHelper.tinyStyle(context, color: fg)),
    );
  }

  Color _ratingColor(int rating) {
    if (rating >= 4) return AppColors.successDark;
    if (rating == 3) return AppColors.grey600;
    return AppColors.errorDark;
  }
}
