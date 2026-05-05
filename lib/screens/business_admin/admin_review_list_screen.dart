// lib/screens/business_admin/admin_review_list_screen.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

// Utils
import '../../utils/responsive_helper.dart';
import '../../theme/app_colors.dart';

// Providers
import '../../providers/user_provider.dart';

// Models
import '../../models/core/monthly_review_model.dart';

// Services
import '../../services/monthly_review_service.dart';

/// 관리자용 리뷰 목록 화면
/// 
/// 기능:
/// - 내가 작성한 리뷰 (지원자 평가)
/// - 사업장이 받은 리뷰 (지원자 → 사업장)
/// - 월별 필터링
class AdminReviewListScreen extends StatefulWidget {
  final String? businessId;
  
  const AdminReviewListScreen({
    super.key,
    this.businessId,
  });

  @override
  State<AdminReviewListScreen> createState() => _AdminReviewListScreenState();
}

class _AdminReviewListScreenState extends State<AdminReviewListScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _reviewService = MonthlyReviewService();
  
  // 상태
  bool _isLoading = true;
  List<MonthlyReviewModel> _writtenReviews = [];  // 내가 작성한 리뷰
  List<MonthlyReviewModel> _receivedReviews = []; // 사업장이 받은 리뷰
  
  // 필터
  final int _selectedYear = DateTime.now().year;
  int _selectedMonth = 0; // 0 = 전체

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadReviews();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadReviews() async {
    setState(() => _isLoading = true);
    
    final userProvider = context.read<UserProvider>();
    final user = userProvider.currentUser;
    final businessId = widget.businessId ?? user?.businessId;
    
    if (businessId == null) {
      setState(() => _isLoading = false);
      return;
    }
    
    try {
      // 1. 내가 작성한 리뷰 (관리자 → 지원자)
      _writtenReviews = await _reviewService.getReviewsByBusiness(
        businessId: businessId,
        limit: 100,
      );
      
      // 2. 사업장이 받은 리뷰 (지원자 → 사업장)
      _receivedReviews = await _reviewService.getReviewsForBusiness(
        businessId: businessId,
        limit: 100,
      );
      
      // 월별 필터 적용
      if (_selectedMonth > 0) {
        _writtenReviews = _writtenReviews.where((r) => 
          r.reviewYear == _selectedYear && r.reviewMonth == _selectedMonth
        ).toList();
        
        _receivedReviews = _receivedReviews.where((r) => 
          r.reviewYear == _selectedYear && r.reviewMonth == _selectedMonth
        ).toList();
      }
    } catch (e) {
      debugPrint('❌ 리뷰 로드 실패: $e');
    }
    
    setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Scaffold(
      backgroundColor: AppColors.grey50,
      appBar: AppBar(
        title: Text(
          '리뷰 관리',
          style: ResponsiveHelper.subtitleStyle(context).copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: theme.primaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          indicatorWeight: 3,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white.withValues(alpha: 0.6),
          tabs: [
            Tab(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.edit_note, size: ResponsiveHelper.iconSize(context, 18)),
                  SizedBox(width: ResponsiveHelper.spacing(context, 6)),
                  Text('작성한 리뷰 (${_writtenReviews.length})'),
                ],
              ),
            ),
            Tab(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.inbox, size: ResponsiveHelper.iconSize(context, 18)),
                  SizedBox(width: ResponsiveHelper.spacing(context, 6)),
                  Text('받은 리뷰 (${_receivedReviews.length})'),
                ],
              ),
            ),
          ],
        ),
        actions: [
          // 월 필터
          PopupMenuButton<int>(
            icon: Icon(Icons.filter_list, color: Colors.white),
            tooltip: '월 필터',
            onSelected: (month) {
              setState(() => _selectedMonth = month);
              _loadReviews();
            },
            itemBuilder: (context) => [
              PopupMenuItem(value: 0, child: Text('전체')),
              ...List.generate(12, (i) => PopupMenuItem(
                value: i + 1,
                child: Text('${i + 1}월'),
              )),
            ],
          ),
        ],
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                // 탭 1: 작성한 리뷰
                _buildReviewList(_writtenReviews, isWritten: true),
                
                // 탭 2: 받은 리뷰
                _buildReviewList(_receivedReviews, isWritten: false),
              ],
            ),
    );
  }

  Widget _buildReviewList(List<MonthlyReviewModel> reviews, {required bool isWritten}) {
    if (reviews.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isWritten ? Icons.edit_off : Icons.inbox_outlined,
              size: ResponsiveHelper.iconSize(context, 64),
              color: AppColors.grey300,
            ),
            SizedBox(height: ResponsiveHelper.spacing(context, 16)),
            Text(
              isWritten ? '작성한 리뷰가 없습니다' : '받은 리뷰가 없습니다',
              style: ResponsiveHelper.bodyStyle(context, color: AppColors.grey500),
            ),
          ],
        ),
      );
    }
    
    return RefreshIndicator(
      onRefresh: _loadReviews,
      child: ListView.builder(
        padding: ResponsiveHelper.cardPadding(context),
        itemCount: reviews.length,
        itemBuilder: (context, index) {
          final review = reviews[index];
          return _buildReviewCard(context, review, isWritten: isWritten);
        },
      ),
    );
  }

  Widget _buildReviewCard(BuildContext context, MonthlyReviewModel review, {required bool isWritten}) {
    final theme = Theme.of(context);
    
    return Container(
      margin: EdgeInsets.only(bottom: ResponsiveHelper.spacing(context, 12)),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: Offset(0, 2),
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
              color: review.isPublished 
                  ? theme.primaryColor.withValues(alpha: 0.05)
                  : AppColors.warning.withValues(alpha: 0.1),
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
              ),
            ),
            child: Row(
              children: [
                // 대상 정보
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            isWritten ? Icons.person : Icons.store,
                            size: ResponsiveHelper.iconSize(context, 16),
                            color: theme.primaryColor,
                          ),
                          SizedBox(width: ResponsiveHelper.spacing(context, 6)),
                          Text(
                            isWritten 
                                ? (review.targetUserName ?? '지원자')
                                : review.reviewerName,
                            style: ResponsiveHelper.bodyStyle(context).copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: ResponsiveHelper.spacing(context, 4)),
                      Text(
                        '${review.reviewYear}년 ${review.reviewMonth}월',
                        style: ResponsiveHelper.smallStyle(context, color: AppColors.grey500),
                      ),
                    ],
                  ),
                ),
                
                // 공개 상태 배지
                Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: ResponsiveHelper.spacing(context, 10),
                    vertical: ResponsiveHelper.spacing(context, 4),
                  ),
                  decoration: BoxDecoration(
                    color: review.isPublished 
                        ? AppColors.success.withValues(alpha: 0.15)
                        : AppColors.warning.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    review.isPublished ? '공개됨' : '대기중',
                    style: ResponsiveHelper.tinyStyle(context).copyWith(
                      color: review.isPublished ? AppColors.success : AppColors.warning,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
          
          // 본문
          Padding(
            padding: ResponsiveHelper.cardPadding(context),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 평점
                Row(
                  children: [
                    ...List.generate(5, (i) => Icon(
                      i < review.rating ? Icons.star : Icons.star_border,
                      size: ResponsiveHelper.iconSize(context, 20),
                      color: Colors.amber,
                    )),
                    SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                    Text(
                      '${review.rating}.0',
                      style: ResponsiveHelper.bodyStyle(context).copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    
                    // 재고용/재근무 의사
                    if (review.wouldRehire != null) ...[
                      SizedBox(width: ResponsiveHelper.spacing(context, 16)),
                      Icon(
                        review.wouldRehire! ? Icons.thumb_up : Icons.thumb_down,
                        size: ResponsiveHelper.iconSize(context, 16),
                        color: review.wouldRehire! ? AppColors.success : AppColors.error,
                      ),
                      SizedBox(width: ResponsiveHelper.spacing(context, 4)),
                      Text(
                        isWritten 
                            ? (review.wouldRehire! ? '재고용 희망' : '재고용 비희망')
                            : (review.wouldRehire! ? '재근무 희망' : '재근무 비희망'),
                        style: ResponsiveHelper.smallStyle(context, color: AppColors.grey600),
                      ),
                    ],
                  ],
                ),
                
                // 태그
                if (review.positiveTags.isNotEmpty || review.improvementTags.isNotEmpty) ...[
                  SizedBox(height: ResponsiveHelper.spacing(context, 12)),
                  Wrap(
                    spacing: ResponsiveHelper.spacing(context, 6),
                    runSpacing: ResponsiveHelper.spacing(context, 6),
                    children: [
                      ...review.positiveTags.map((tag) => _buildTag(context, tag, isPositive: true)),
                      ...review.improvementTags.map((tag) => _buildTag(context, tag, isPositive: false)),
                    ],
                  ),
                ],
                
                // 코멘트
                if (review.comment != null && review.comment!.isNotEmpty) ...[
                  SizedBox(height: ResponsiveHelper.spacing(context, 12)),
                  Container(
                    padding: ResponsiveHelper.cardPadding(context),
                    decoration: BoxDecoration(
                      color: AppColors.grey50,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      review.comment!,
                      style: ResponsiveHelper.smallStyle(context, color: AppColors.grey700),
                    ),
                  ),
                ],
                
                // 근무 정보
                SizedBox(height: ResponsiveHelper.spacing(context, 12)),
                Row(
                  children: [
                    Icon(
                      Icons.work_outline,
                      size: ResponsiveHelper.iconSize(context, 14),
                      color: AppColors.grey400,
                    ),
                    SizedBox(width: ResponsiveHelper.spacing(context, 4)),
                    Text(
                      '근무 ${review.workDaysInMonth}일',
                      style: ResponsiveHelper.tinyStyle(context, color: AppColors.grey500),
                    ),
                    if (review.normalAttendanceDays > 0) ...[
                      Text(
                        ' · 정상 ${review.normalAttendanceDays}일',
                        style: ResponsiveHelper.tinyStyle(context, color: AppColors.grey500),
                      ),
                    ],
                    if (review.lateDays > 0) ...[
                      Text(
                        ' · 지각 ${review.lateDays}회',
                        style: ResponsiveHelper.tinyStyle(context, color: AppColors.warning),
                      ),
                    ],
                    Spacer(),
                    Text(
                      _formatDate(review.createdAt),
                      style: ResponsiveHelper.tinyStyle(context, color: AppColors.grey400),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTag(BuildContext context, String tag, {required bool isPositive}) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 8),
        vertical: ResponsiveHelper.spacing(context, 4),
      ),
      decoration: BoxDecoration(
        color: isPositive 
            ? AppColors.success.withValues(alpha: 0.1)
            : AppColors.warning.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        tag,
        style: ResponsiveHelper.tinyStyle(context).copyWith(
          color: isPositive ? AppColors.success : AppColors.warning,
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.month}/${date.day}';
  }
}