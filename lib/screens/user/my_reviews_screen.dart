import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/core/monthly_review_model.dart';
import '../../providers/user_provider.dart';
import '../../services/monthly_review_service.dart';
import '../../utils/responsive_helper.dart';
import '../../utils/toast_helper.dart';
import '../../widgets/common/app_empty_state.dart';
import '../../widgets/common/gradient_scaffold.dart';
import '../../widgets/common/loading_widget.dart';
import '../../widgets/common/review_card.dart';

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
      final page = await _reviewService.getAllReviewsForUserPaged(
        targetUserId: uid,
      );
      // 평균 점수는 공개된 리뷰(isPublished=true)만으로 계산 — 미공개는 확정 전 상태
      // 이 화면의 avgRating은 Firestore user.averageRating(전체 리뷰 기준)과 다를 수 있음
      // 두 값의 의미가 다른 것은 의도된 설계 — 이 화면은 본인이 볼 수 있는 공개 리뷰만 대상
      final published = page.records.where((r) => r.isPublished).toList();
      final avg = published.isEmpty
          ? 0.0
          : published.map((r) => r.rating).reduce((a, b) => a + b) / published.length;
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
      final page = await _reviewService.getAllReviewsForUserPaged(
        targetUserId: uid,
        startAfter: _cursor,
      );
      if (!mounted) return;
      final allReviews = [..._reviews, ...page.records];
      final published = allReviews.where((r) => r.isPublished).toList();
      final avg = published.isEmpty
          ? 0.0
          : published.map((r) => r.rating).reduce((a, b) => a + b) / published.length;
      setState(() {
        _reviews = allReviews;
        _avgRating = avg;
        _cursor = page.cursor;
        _hasMore = page.hasMore;
      });
    } catch (e) {
      debugPrint('⚠️ [MyReviewsScreen] loadMore 실패: $e');
      if (mounted) ToastHelper.showError('리뷰를 더 불러오지 못했습니다');
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
                              (ctx, i) => ReviewCard(
                                review: _reviews[i],
                                perspective: ReviewCardPerspective.workerReceived,
                              ),
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

