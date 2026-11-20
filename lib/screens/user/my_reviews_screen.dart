import 'package:flutter/material.dart';
import 'my_reviews_reads.dart';
import 'package:provider/provider.dart';

import '../../models/core/monthly_review_model.dart';
import '../../providers/user_provider.dart';
import '../../services/monthly_review_service.dart';
import '../../theme/app_colors.dart';
import '../../utils/text_layout.dart';
import '../../utils/responsive_helper.dart';
import '../../utils/toast_helper.dart';
import '../../widgets/common/app_empty_state.dart';
import '../../widgets/common/app_page_actions.dart';
import '../../widgets/common/app_page_scaffold.dart';
import '../../widgets/user/pending_contract_bar.dart';
import '../../widgets/common/loading_widget.dart';
import '../../widgets/common/review_card.dart';

class MyReviewsScreen extends StatefulWidget {
  const MyReviewsScreen({super.key, this.reads});

  /// [R7-P2-4 P24-R] 목록을 만드는 읽기 경계. production 은 null.
  final MyReviewsReads? reads;

  @override
  State<MyReviewsScreen> createState() => _MyReviewsScreenState();
}

class _MyReviewsScreenState extends State<MyReviewsScreen> {
  final MonthlyReviewService _reviewService = MonthlyReviewService();
  late final MyReviewsReads _reads =
      widget.reads ?? MyReviewsReads.of(_reviewService);

  List<MonthlyReviewModel> _reviews = [];
  double _avgRating = 0.0;
  bool _isLoading = false; // 초기값 false — postFrameCallback 첫 호출 시 재진입 방어에 걸리지 않도록
  String? _loadError;

  String? _cursor;
  bool _hasMore = false;
  bool _isLoadingMore = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _loadReviews();
    });
  }

  Future<void> _loadReviews() async {
    if (!mounted) return;
    if (_isLoading) return; // pull-to-refresh 재진입 방어
    final uid = context.read<UserProvider>().currentUser?.uid;
    if (uid == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }
    setState(() { _isLoading = true; _loadError = null; _cursor = null; _hasMore = false; });
    try {
      final page = await _reads.reviewsForUserPaged(
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
    if (!mounted) return; // dispose 직후 스크롤 이벤트 재진입 방지
    setState(() => _isLoadingMore = true);
    try {
      final page = await _reads.reviewsForUserPaged(
        targetUserId: uid,
        startAfterId: _cursor,
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
    // [R7-P3-4] 알림(flat)에서 들어오는데 이 화면만 파란 헤더였다.
    //   우상단 새로고침·홈·알림과 미서명 계약 바를 그대로 옮긴다.
    return AppPageScaffold(
      title: '내 근무 평가',
      actions: appPageActions(context, onRefresh: _loadReviews),
      bottomNavigationBar: const PendingContractBar(useSafeArea: true),
      body: SafeArea(
        top: false,
        left: false,
        right: false,
        child: _isLoading
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
                      // 하단 홈버튼·네비게이션 바 높이 보장
                      // [BUG-PAD FIX] GradientScaffold 내부 SafeArea(top:false)가 paddingOf.bottom을
                      // 이미 소비하므로 viewPaddingOf(물리값) 사용 시 이중 패딩 발생 → paddingOf로 통일
                      // (SafeArea 내부에서 paddingOf.bottom = 0, 시각적으로 중복 제거됨)
                      SliverToBoxAdapter(
                        child: SizedBox(
                          height: MediaQuery.paddingOf(context).bottom,
                        ),
                      ),
                    ],
                  ),
                ),
      ),
    );
  }

  Widget _buildSummaryHeader(BuildContext context) {
    final avgRating = _avgRating;

    // [DU252] 대표색 띠 + 반투명 카드 → 흰 요약 카드(S010·S082·S070 과 같은 흰 면·반경 16·grey200).
    //   이 화면만 파란 덩어리가 남아 있었다 — 다른 하위 화면처럼 흰 헤더 아래 흰 카드로 둔다.
    return Container(
      margin: EdgeInsets.fromLTRB(
        ResponsiveHelper.spacing(context, 16),
        ResponsiveHelper.spacing(context, 16),
        ResponsiveHelper.spacing(context, 16),
        ResponsiveHelper.spacing(context, 12),
      ),
      padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 20)),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.grey200),
      ),
        // [R7-P2-4 P24-R] 세 칸이 flex 없이 한 줄 고정이라 320dp·배율 2.0 에서
        //   172px 넘쳤다 — 평가 수·평균·별점은 이 화면의 요약 수치라 지우지
        //   않는다. 각 칸에 flex 를 주고 값은 한 줄로 줄인다.
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            Expanded(
                child: _buildStat(context, '총 평가', '${_reviews.length}건')),
            _buildDivider(),
            Expanded(
              child: _buildStat(context, '평균 별점',
                  avgRating == 0 ? '-' : avgRating.toStringAsFixed(1)),
            ),
            _buildDivider(),
            Expanded(
              child: _buildStat(
                context,
                '별점',
                avgRating == 0
                    ? '-'
                    : '★' * avgRating.round() + '☆' * (5 - avgRating.round()),
                valueColor: AppColors.warningDark, // [DU252] 별은 진한 호박색(흰 위 ≥4.5)
                valueFontSize: 15, // [DU252 v2] 별 다섯 개가 보통 폭 한 칸에 한 줄로(이전 19.5 — 두 줄로 갈라졌다)
              ),
            ),
          ],
        ),
    );
  }

  // [DU252] 흰 카드 위 수치는 본문색, 라벨은 보조색. 큰 글자에서 말줄임으로 값이 사라지지 않게 줄을 바꾼다
  //   (이전 maxLines 1 + 말줄임 — B320 에서 별점이 '★…' 로 잘렸다).
  Widget _buildStat(BuildContext context, String label, String value,
      {Color valueColor = AppColors.textPrimary, double? valueFontSize}) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(value,
            textAlign: TextAlign.center,
            style: ResponsiveHelper.subtitleStyle(context).copyWith(
              color: valueColor,
              fontWeight: FontWeight.bold,
              fontSize: valueFontSize ?? ResponsiveHelper.subtitleStyle(context).fontSize! * 1.15,
            )),
        SizedBox(height: ResponsiveHelper.spacing(context, 4)),
        Text(TextLayout.keepWords(label),
            semanticsLabel: label,
            textAlign: TextAlign.center,
            style: ResponsiveHelper.tinyStyle(context,
                color: AppColors.textSecondary)),
      ],
    );
  }

  Widget _buildDivider() => Container(
        height: 32,
        width: 1,
        color: AppColors.grey200, // [DU252]
      );
}

