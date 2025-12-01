// lib/widgets/dialogs/worker_detail_dialog.dart
// 공통 근무자/지원자 상세 다이얼로그

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../models/core/application_model.dart';
import '../../models/core/user_model.dart';
import '../../models/core/id_card_access_request_model.dart';
import '../../models/core/review_model.dart';
import '../../models/ui/admin_to_list_ui_models.dart';
import '../../services/firestore_service.dart';
import '../../providers/user_provider.dart';
import '../../utils/toast_helper.dart';
import '../../utils/format_helper.dart';
import '../../utils/responsive_helper.dart';
import '../../utils/dialog_helper.dart';
import '../../theme/app_colors.dart';
import 'styled_dialog.dart';

/// 공통 근무자/지원자 상세 다이얼로그
/// 
/// [isConfirmed] - 확정자 여부 (true: 확정명단에서 호출, false: 지원자 관리에서 호출)
/// [application] - 지원서 정보 (대기중일 때 승인/거절용)
/// [showApprovalButtons] - 승인/거절 버튼 표시 여부
class WorkerDetailDialog extends StatefulWidget {
  final UserModel user;
  final ApplicationModel? application;
  final TOItem? toItem;
  final String? businessId;
  final bool isConfirmed;
  final bool showApprovalButtons;
  final VoidCallback? onStatusChanged;

  const WorkerDetailDialog({
    super.key,
    required this.user,
    this.application,
    this.toItem,
    this.businessId,
    this.isConfirmed = false,
    this.showApprovalButtons = false,
    this.onStatusChanged,
  });

  /// 다이얼로그 표시 헬퍼
  static Future<void> show({
    required BuildContext context,
    required UserModel user,
    ApplicationModel? application,
    TOItem? toItem,
    String? businessId,
    bool isConfirmed = false,
    bool showApprovalButtons = false,
    VoidCallback? onStatusChanged,
  }) {
    return showDialog(
      context: context,
      builder: (context) => WorkerDetailDialog(
        user: user,
        application: application,
        toItem: toItem,
        businessId: businessId,
        isConfirmed: isConfirmed,
        showApprovalButtons: showApprovalButtons,
        onStatusChanged: onStatusChanged,
      ),
    );
  }

  @override
  State<WorkerDetailDialog> createState() => _WorkerDetailDialogState();
}

class _WorkerDetailDialogState extends State<WorkerDetailDialog> {
  final FirestoreService _firestoreService = FirestoreService();
  bool _isLoading = false;
  
  // 추가 데이터
  Map<String, dynamic>? _businessHistory;
  List<ReviewModel> _recentReviews = [];
  IdCardAccessRequestModel? _idCardAccess;

  @override
  void initState() {
    super.initState();
    _loadAdditionalData();
  }

  Future<void> _loadAdditionalData() async {
    setState(() => _isLoading = true);
    
    try {
      final userProvider = context.read<UserProvider>();
      final currentUserId = userProvider.currentUser?.uid ?? '';
      final businessId = widget.businessId ?? widget.toItem?.to.businessId;
      
      // 병렬로 데이터 로드
      final futures = <Future>[];
      
      // 우리 사업장 이력 (businessId가 있을 때만)
      if (businessId != null) {
        futures.add(_firestoreService.getBusinessWorkHistory(
          businessId: businessId,
          userId: widget.user.uid,
        ));
      } else {
        futures.add(Future.value(null));
      }
      
      // 최근 리뷰 (확정자일 때만)
      if (widget.isConfirmed) {
        futures.add(_firestoreService.getUserReviews(widget.user.uid, limit: 3));
      } else {
        futures.add(Future.value(<ReviewModel>[]));
      }
      
      // 신분증 열람 권한 (확정자일 때만)
      if (widget.isConfirmed) {
        futures.add(_firestoreService.checkIdCardAccess(
          requesterId: currentUserId,
          targetUserId: widget.user.uid,
        ));
      } else {
        futures.add(Future.value(null));
      }
      
      final results = await Future.wait(futures);
      
      setState(() {
        _businessHistory = results[0] as Map<String, dynamic>?;
        _recentReviews = results[1] as List<ReviewModel>;
        _idCardAccess = results[2] as IdCardAccessRequestModel?;
        _isLoading = false;
      });
    } catch (e) {
      print('❌ 추가 데이터 로드 실패: $e');
      setState(() => _isLoading = false);
    }
  }

  /// 신뢰도 점수 계산
  int _calculateTrustScore(UserModel user) {
    int score = 60; // 기본 점수
    score += ((user.averageRating) * 4).round(); // 평점 반영 (최대 20점)
    score += (user.totalWorkDays / 10).clamp(0, 15).round(); // 근무일 반영 (최대 15점)
    score -= (user.noShowCount ?? 0) * 5; // 무단결근 감점
    score -= (user.lateCount ?? 0) * 2; // 지각 감점
    return score.clamp(0, 100);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final trustScore = _calculateTrustScore(widget.user);
    final isPending = widget.application?.status == 'PENDING';

   return Dialog(
      backgroundColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
      ),
      child: Container(
        constraints: BoxConstraints(
          maxWidth: 500,
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.15),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 헤더
            _buildHeader(context, theme, trustScore),
            
            // 내용
            Flexible(
              child: _isLoading
                  ? Center(
                      child: Padding(
                        padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 40)),
                        child: CircularProgressIndicator(),
                      ),
                    )
                  : SingleChildScrollView(
                      padding: ResponsiveHelper.cardPadding(context),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // 기본 정보
                          _buildBasicInfo(context),
                          SizedBox(height: ResponsiveHelper.spacing(context, 20)),
                          
                          // 근무 통계
                          _buildWorkStats(context),
                          SizedBox(height: ResponsiveHelper.spacing(context, 20)),
                          
                          // 우리 사업장 이력
                          _buildBusinessHistory(context),
                          SizedBox(height: ResponsiveHelper.spacing(context, 20)),
                          
                          // 자기소개
                          _buildSelfIntro(context),
                          
                          // 최근 리뷰 (확정자만)
                          if (widget.isConfirmed && _recentReviews.isNotEmpty) ...[
                            SizedBox(height: ResponsiveHelper.spacing(context, 20)),
                            _buildRecentReviews(context),
                          ],
                          
                          // 급여 정보 (확정자만)
                          if (widget.isConfirmed) ...[
                            SizedBox(height: ResponsiveHelper.spacing(context, 20)),
                            _buildPaymentInfo(context),
                          ],
                          
                          // 신분증 섹션 (확정자만)
                          if (widget.isConfirmed) ...[
                            SizedBox(height: ResponsiveHelper.spacing(context, 20)),
                            _buildIdCardSection(context),
                          ],
                        ],
                      ),
                    ),
            ),
            
            // 하단 버튼
            _buildBottomButtons(context, isPending),
          ],
        ),
      ),
    );
  }

  /// 헤더 (프로필 + 전화 버튼)
  Widget _buildHeader(BuildContext context, ThemeData theme, int trustScore) {
    return Container(
      padding: ResponsiveHelper.cardPadding(context),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [theme.primaryColor, theme.primaryColor.withOpacity(0.8)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              // 프로필 이미지
              CircleAvatar(
                radius: ResponsiveHelper.spacing(context, 28),
                backgroundColor: Colors.white,
                child: Text(
                  widget.user.name.isNotEmpty ? widget.user.name[0] : '?',
                  style: ResponsiveHelper.titleStyle(context).copyWith(
                    fontWeight: FontWeight.bold,
                    color: theme.primaryColor,
                  ),
                ),
              ),
              SizedBox(width: ResponsiveHelper.spacing(context, 12)),
              
              // 이름 + 정보
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            widget.user.name,
                            style: ResponsiveHelper.titleStyle(context).copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                        // 상태 배지
                        if (widget.application != null)
                          Container(
                            padding: EdgeInsets.symmetric(
                              horizontal: ResponsiveHelper.spacing(context, 8),
                              vertical: ResponsiveHelper.spacing(context, 2),
                            ),
                            decoration: BoxDecoration(
                              color: _getStatusColor(widget.application!.status),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              _getStatusLabel(widget.application!.status),
                              style: ResponsiveHelper.tinyStyle(context, color: Colors.white).copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                      ],
                    ),
                    SizedBox(height: ResponsiveHelper.spacing(context, 4)),
                    Text(
                      '${widget.user.gender ?? ''} · ${widget.user.age ?? '-'}세',
                      style: ResponsiveHelper.bodyStyle(context, color: Colors.white70),
                    ),
                  ],
                ),
              ),
              
              // 신뢰도 점수 (우측 상단)
              Container(
                padding: EdgeInsets.symmetric(
                  horizontal: ResponsiveHelper.spacing(context, 10),
                  vertical: ResponsiveHelper.spacing(context, 6),
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    Text(
                      '$trustScore',
                      style: ResponsiveHelper.titleStyle(context).copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      '신뢰도',
                      style: ResponsiveHelper.tinyStyle(context, color: Colors.white70),
                    ),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 12)),
          
          // 연락처 + 전화 버튼
          Container(
            padding: EdgeInsets.symmetric(
              horizontal: ResponsiveHelper.spacing(context, 12),
              vertical: ResponsiveHelper.spacing(context, 8),
            ),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.phone, size: ResponsiveHelper.iconSize(context, 16), color: Colors.white),
                SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                Text(
                  widget.user.phone ?? '-',
                  style: ResponsiveHelper.bodyStyle(context, color: Colors.white),
                ),
                if (widget.user.phone != null && widget.user.phone!.isNotEmpty) ...[
                  SizedBox(width: ResponsiveHelper.spacing(context, 12)),
                  Material(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(20),
                    child: InkWell(
                      onTap: () => _makePhoneCall(widget.user.phone),
                      borderRadius: BorderRadius.circular(20),
                      child: Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: ResponsiveHelper.spacing(context, 12),
                          vertical: ResponsiveHelper.spacing(context, 4),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.call,
                              size: ResponsiveHelper.iconSize(context, 14),
                              color: Colors.white,
                            ),
                            SizedBox(width: ResponsiveHelper.spacing(context, 4)),
                            Text(
                              '전화',
                              style: ResponsiveHelper.smallStyle(context, color: Colors.white),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'PENDING':
        return AppColors.warning;
      case 'CONFIRMED':
        return AppColors.success;
      case 'REJECTED':
        return AppColors.error;
      default:
        return AppColors.grey500;
    }
  }

  String _getStatusLabel(String status) {
    switch (status) {
      case 'PENDING':
        return '대기중';
      case 'CONFIRMED':
        return '확정';
      case 'REJECTED':
        return '거절';
      default:
        return status;
    }
  }

  /// 기본 정보
  Widget _buildBasicInfo(BuildContext context) {
    final app = widget.application;
    
    return _buildSection(
      context,
      title: '기본 정보',
      icon: Icons.person_outline,
      child: Column(
        children: [
          if (widget.user.address != null)
            _buildInfoRow(context, '주소', 
              '${widget.user.address}${widget.user.detailAddress != null ? ' ${widget.user.detailAddress}' : ''}'),
          if (app != null)
            _buildInfoRow(context, '지원일', DateFormat('yyyy.MM.dd HH:mm').format(app.appliedAt)),
          if (app != null)
            _buildInfoRow(context, '지원 업무', app.selectedWorkType),
          if (app != null && app.isLongTermApplication) ...[
            _buildInfoRow(context, '근무 기간', app.workPeriodDisplay),
            if (app.workDaysDisplay != null)
              _buildInfoRow(context, '근무 요일', app.workDaysDisplay!),
          ],
        ],
      ),
    );
  }

  /// 근무 통계
  Widget _buildWorkStats(BuildContext context) {
    return _buildSection(
      context,
      title: '근무 통계',
      icon: Icons.bar_chart,
      child: Row(
        children: [
          _buildStatCard(context, '총 근무', '${widget.user.totalWorkDays}일', AppColors.info),
          SizedBox(width: ResponsiveHelper.spacing(context, 8)),
          _buildStatCard(context, '평균 평점', widget.user.averageRating > 0 ? widget.user.averageRating.toStringAsFixed(1) : '-', Colors.amber),
          SizedBox(width: ResponsiveHelper.spacing(context, 8)),
          _buildStatCard(context, '무단결근', '${widget.user.noShowCount ?? 0}회', AppColors.error),
          SizedBox(width: ResponsiveHelper.spacing(context, 8)),
          _buildStatCard(context, '지각', '${widget.user.lateCount ?? 0}회', AppColors.warning),
        ],
      ),
    );
  }

  Widget _buildStatCard(BuildContext context, String label, String value, Color color) {
    return Expanded(
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: ResponsiveHelper.spacing(context, 8),
          vertical: ResponsiveHelper.spacing(context, 10),
        ),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: ResponsiveHelper.subtitleStyle(context).copyWith(
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            SizedBox(height: ResponsiveHelper.spacing(context, 2)),
            Text(
              label,
              style: ResponsiveHelper.tinyStyle(context, color: AppColors.grey600),
            ),
          ],
        ),
      ),
    );
  }

  /// 우리 사업장 이력
  Widget _buildBusinessHistory(BuildContext context) {
    return _buildSection(
      context,
      title: '우리 사업장 이력',
      icon: Icons.business,
      child: _businessHistory == null || (_businessHistory!['workCount'] ?? 0) == 0
          ? Container(
              padding: ResponsiveHelper.cardPadding(context),
              decoration: BoxDecoration(
                color: AppColors.grey50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: AppColors.grey400, size: ResponsiveHelper.iconSize(context, 16)),
                  SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                  Text(
                    '이 사업장에서 근무한 이력이 없습니다',
                    style: ResponsiveHelper.smallStyle(context, color: AppColors.grey500),
                  ),
                ],
              ),
            )
          : Column(
              children: [
                _buildInfoRow(context, '근무 횟수', '${_businessHistory!['workCount']}회'),
                _buildInfoRow(context, '최근 근무', _businessHistory!['lastWork'] ?? '-'),
                if (_businessHistory!['avgRating'] != null && _businessHistory!['avgRating'] > 0)
                  _buildInfoRow(context, '평균 평점', '${(_businessHistory!['avgRating'] as double).toStringAsFixed(1)}점'),
              ],
            ),
    );
  }

  /// 자기소개
  Widget _buildSelfIntro(BuildContext context) {
    // 지원서 메시지 또는 사용자 bio
    final message = widget.application?.applicationMessage ?? widget.user.bio;
    
    if (message == null || message.isEmpty) {
      return SizedBox.shrink();
    }
    
    return _buildSection(
      context,
      title: '자기소개',
      icon: Icons.chat_bubble_outline,
      child: Container(
        width: double.infinity,
        padding: ResponsiveHelper.cardPadding(context),
        decoration: BoxDecoration(
          color: AppColors.grey50,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          message,
          style: ResponsiveHelper.bodyStyle(context),
        ),
      ),
    );
  }

  /// 최근 리뷰
  Widget _buildRecentReviews(BuildContext context) {
    return _buildSection(
      context,
      title: '최근 리뷰',
      icon: Icons.rate_review,
      child: Column(
        children: _recentReviews.map((review) => _buildReviewItem(context, review)).toList(),
      ),
    );
  }

  Widget _buildReviewItem(BuildContext context, ReviewModel review) {
    return Container(
      margin: EdgeInsets.only(bottom: ResponsiveHelper.spacing(context, 8)),
      padding: ResponsiveHelper.cardPadding(context),
      decoration: BoxDecoration(
        color: AppColors.grey50,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // 별점
              Row(
                children: List.generate(5, (index) => Icon(
                  index < review.rating ? Icons.star : Icons.star_border,
                  size: ResponsiveHelper.iconSize(context, 14),
                  color: Colors.amber,
                )),
              ),
              const Spacer(),
              Text(
                DateFormat('yy.MM.dd').format(review.createdAt),
                style: ResponsiveHelper.tinyStyle(context, color: AppColors.grey500),
              ),
            ],
          ),
          if (review.comment?.isNotEmpty == true) ...[
            SizedBox(height: ResponsiveHelper.spacing(context, 6)),
            Text(
              review.comment!,
              style: ResponsiveHelper.smallStyle(context),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          SizedBox(height: ResponsiveHelper.spacing(context, 4)),
          Text(
            '${review.businessName} · ${review.workType}',
            style: ResponsiveHelper.tinyStyle(context, color: AppColors.grey500),
          ),
        ],
      ),
    );
  }

  /// 급여 정보 (확정자만)
  Widget _buildPaymentInfo(BuildContext context) {
    return _buildSection(
      context,
      title: '급여 정보',
      icon: Icons.account_balance,
      child: Column(
        children: [
          _buildInfoRow(context, '은행', widget.user.bankName ?? '-'),
          _buildInfoRow(context, '계좌번호', widget.user.accountNumber ?? '-'),
          _buildInfoRow(context, '예금주', widget.user.accountHolder ?? widget.user.name),
        ],
      ),
    );
  }

  /// 신분증 섹션 (확정자만)
  Widget _buildIdCardSection(BuildContext context) {
    return _buildSection(
      context,
      title: '신분증',
      icon: Icons.badge,
      child: _buildIdCardContent(context),
    );
  }

  Widget _buildIdCardContent(BuildContext context) {
    // 승인된 상태
    if (_idCardAccess != null && _idCardAccess!.isValidAccess) {
      return Column(
        children: [
          Container(
            padding: ResponsiveHelper.cardPadding(context),
            decoration: BoxDecoration(
              color: AppColors.successBg,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.success.withOpacity(0.3)),
            ),
            child: Row(
              children: [
                Icon(Icons.verified, color: AppColors.success, size: ResponsiveHelper.iconSize(context, 20)),
                SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '열람 승인됨',
                        style: ResponsiveHelper.bodyStyle(context).copyWith(
                          fontWeight: FontWeight.bold,
                          color: AppColors.successDark,
                        ),
                      ),
                      Text(
                        '${_idCardAccess!.remainingDays}일 후 만료',
                        style: ResponsiveHelper.smallStyle(context, color: AppColors.success),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 12)),
          if (widget.user.idCardImageUrl != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.network(
                widget.user.idCardImageUrl!,
                height: ResponsiveHelper.spacing(context, 150),
                width: double.infinity,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  height: ResponsiveHelper.spacing(context, 150),
                  color: AppColors.grey100,
                  child: Center(child: Icon(Icons.image_not_supported, color: AppColors.grey400)),
                ),
              ),
            ),
        ],
      );
    }
    
    // 요청중 상태
    if (_idCardAccess != null && _idCardAccess!.isPending) {
      return Container(
        width: double.infinity,
        padding: ResponsiveHelper.cardPadding(context),
        decoration: BoxDecoration(
          color: AppColors.warningBg,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.warning.withOpacity(0.3)),
        ),
        child: Column(
          children: [
            Icon(Icons.hourglass_top, size: ResponsiveHelper.iconSize(context, 32), color: AppColors.warning),
            SizedBox(height: ResponsiveHelper.spacing(context, 8)),
            Text(
              '열람 요청중',
              style: ResponsiveHelper.bodyStyle(context).copyWith(
                fontWeight: FontWeight.bold,
                color: AppColors.warningDark,
              ),
            ),
            SizedBox(height: ResponsiveHelper.spacing(context, 4)),
            Text(
              '근무자의 승인을 기다리고 있습니다',
              style: ResponsiveHelper.smallStyle(context, color: AppColors.warning),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: ResponsiveHelper.spacing(context, 8)),
            Text(
              '요청일: ${DateFormat('MM/dd HH:mm').format(_idCardAccess!.requestedAt)}',
              style: ResponsiveHelper.tinyStyle(context, color: AppColors.grey500),
            ),
          ],
        ),
      );
    }

    // 미요청 상태
    return Container(
      width: double.infinity,
      padding: ResponsiveHelper.cardPadding(context),
      decoration: BoxDecoration(
        color: AppColors.grey50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          Icon(Icons.lock, size: ResponsiveHelper.iconSize(context, 32), color: AppColors.grey400),
          SizedBox(height: ResponsiveHelper.spacing(context, 8)),
          Text(
            '신분증 열람 권한이 없습니다',
            style: ResponsiveHelper.bodyStyle(context, color: AppColors.grey600),
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 4)),
          Text(
            '열람 요청 시 근무자의 승인이 필요합니다',
            style: ResponsiveHelper.smallStyle(context, color: AppColors.grey500),
            textAlign: TextAlign.center,
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 12)),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => _showIdCardAccessRequestDialog(),
              icon: Icon(Icons.send, size: ResponsiveHelper.iconSize(context, 16)),
              label: const Text('열람 요청'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.info,
                foregroundColor: Colors.white,
                padding: EdgeInsets.symmetric(vertical: ResponsiveHelper.spacing(context, 12)),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 공통 섹션 빌더
  Widget _buildSection(BuildContext context, {required String title, required IconData icon, required Widget child}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: ResponsiveHelper.iconSize(context, 18), color: AppColors.grey600),
            SizedBox(width: ResponsiveHelper.spacing(context, 8)),
            Text(
              title,
              style: ResponsiveHelper.subtitleStyle(context).copyWith(fontWeight: FontWeight.bold),
            ),
          ],
        ),
        SizedBox(height: ResponsiveHelper.spacing(context, 12)),
        child,
      ],
    );
  }

  Widget _buildInfoRow(BuildContext context, String label, String value) {
    return Padding(
      padding: EdgeInsets.only(bottom: ResponsiveHelper.spacing(context, 8)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: ResponsiveHelper.spacing(context, 80),
            child: Text(
              label,
              style: ResponsiveHelper.bodyStyle(context, color: AppColors.grey500),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: ResponsiveHelper.bodyStyle(context),
            ),
          ),
        ],
      ),
    );
  }

  /// 하단 버튼
  Widget _buildBottomButtons(BuildContext context, bool isPending) {
    return Container(
      padding: ResponsiveHelper.cardPadding(context),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          // 닫기 버튼 (항상)
          Expanded(
            child: OutlinedButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('닫기'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.grey600,
                side: BorderSide(color: AppColors.grey300),
                padding: EdgeInsets.symmetric(vertical: ResponsiveHelper.spacing(context, 12)),
              ),
            ),
          ),
          
          // 승인/거절 버튼 (대기중이고 showApprovalButtons가 true일 때만)
          if (isPending && widget.showApprovalButtons && widget.application != null) ...[
            SizedBox(width: ResponsiveHelper.spacing(context, 8)),
            
            // 거절 버튼
            Expanded(
              child: OutlinedButton(
                onPressed: () => _updateStatus('REJECTED'),
                child: const Text('거절'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.error,
                  side: BorderSide(color: AppColors.error),
                  padding: EdgeInsets.symmetric(vertical: ResponsiveHelper.spacing(context, 12)),
                ),
              ),
            ),
            SizedBox(width: ResponsiveHelper.spacing(context, 8)),
            
            // 승인 버튼
            Expanded(
              child: ElevatedButton(
                onPressed: () => _updateStatus('CONFIRMED'),
                child: const Text('승인'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.success,
                  foregroundColor: Colors.white,
                  padding: EdgeInsets.symmetric(vertical: ResponsiveHelper.spacing(context, 12)),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// 전화 걸기
  Future<void> _makePhoneCall(String? phone) async {
    if (phone == null || phone.isEmpty) {
      ToastHelper.showWarning('전화번호가 없습니다');
      return;
    }
    
    final uri = Uri.parse('tel:$phone');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      ToastHelper.showInfo('전화: $phone');
    }
  }

  /// 상태 업데이트
  Future<void> _updateStatus(String newStatus) async {
    if (widget.application == null) return;
    
    final actionText = newStatus == 'CONFIRMED' ? '승인' : '거절';
    String? rejectReason;
    
    if (newStatus == 'CONFIRMED') {
      // 승인
      final confirm = await DialogHelper.showConfirm(
        context,
        title: '지원자 승인',
        message: '${widget.user.name}님을 승인하시겠습니까?',
        confirmText: '승인',
        confirmColor: AppColors.success,
        icon: Icons.check_circle,
        iconColor: AppColors.success,
      );
      
      if (confirm != true) return;
    } else {
      // 거절 - 사유 선택
      rejectReason = await DialogHelper.showRejectReasonPicker(
        context,
        title: '지원자 거절',
        targetName: widget.user.name,
      );
      
      if (rejectReason == null) return;
    }

    try {
      final userProvider = context.read<UserProvider>();
      final adminUID = userProvider.currentUser?.uid;
      
      await _firestoreService.updateApplicationStatus(
        applicationId: widget.application!.id,
        status: newStatus,
        confirmedBy: newStatus == 'CONFIRMED' ? adminUID : null,
        rejectedBy: newStatus == 'REJECTED' ? adminUID : null,
        message: rejectReason,
      );

      if (mounted) {
        Navigator.pop(context);
        ToastHelper.showSuccess('$actionText 처리되었습니다');
        widget.onStatusChanged?.call();
      }
    } catch (e) {
      print('❌ 상태 업데이트 실패: $e');
      if (mounted) {
        ToastHelper.showError('$actionText 처리 중 오류가 발생했습니다');
      }
    }
  }

  /// 신분증 열람 요청 다이얼로그
  void _showIdCardAccessRequestDialog() {
    IdCardAccessReason? selectedReason;
    final customReasonController = TextEditingController();

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          return StyledDialog(
            title: '신분증 열람 요청',
            subtitle: '${widget.user.name}님에게 요청',
            icon: Icons.badge,
            headerColor: AppColors.info,
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '신분증 열람 사유를 선택해주세요.',
                  style: ResponsiveHelper.bodyStyle(context, color: AppColors.grey600),
                ),
                SizedBox(height: ResponsiveHelper.spacing(context, 16)),
                
                // 사유 선택 카드들
                ...IdCardAccessRequestModel.reasonOptions.map((option) {
                  final reason = option['value'] as IdCardAccessReason;
                  final label = option['label'] as String;
                  final isSelected = selectedReason == reason;
                  
                  return Padding(
                    padding: EdgeInsets.only(bottom: ResponsiveHelper.spacing(context, 8)),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () => setDialogState(() => selectedReason = reason),
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: ResponsiveHelper.spacing(context, 16),
                            vertical: ResponsiveHelper.spacing(context, 12),
                          ),
                          decoration: BoxDecoration(
                            color: isSelected ? AppColors.info.withOpacity(0.1) : Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isSelected ? AppColors.info : AppColors.border,
                              width: isSelected ? 2 : 1,
                            ),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: ResponsiveHelper.spacing(context, 24),
                                height: ResponsiveHelper.spacing(context, 24),
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: isSelected ? AppColors.info : Colors.white,
                                  border: Border.all(
                                    color: isSelected ? AppColors.info : AppColors.grey400,
                                    width: 2,
                                  ),
                                ),
                                child: isSelected
                                    ? Icon(Icons.check, size: ResponsiveHelper.iconSize(context, 16), color: Colors.white)
                                    : null,
                              ),
                              SizedBox(width: ResponsiveHelper.spacing(context, 12)),
                              Expanded(
                                child: Text(
                                  label,
                                  style: ResponsiveHelper.bodyStyle(context).copyWith(
                                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                                    color: isSelected ? AppColors.info : AppColors.grey700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                }),
                
                // 기타 사유 입력
                if (selectedReason == IdCardAccessReason.other) ...[
                  SizedBox(height: ResponsiveHelper.spacing(context, 8)),
                  TextField(
                    controller: customReasonController,
                    decoration: InputDecoration(
                      hintText: '사유를 입력해주세요',
                      hintStyle: ResponsiveHelper.bodyStyle(context, color: AppColors.grey400),
                      filled: true,
                      fillColor: AppColors.grey50,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: AppColors.border),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: AppColors.border),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: AppColors.info, width: 2),
                      ),
                      contentPadding: EdgeInsets.all(ResponsiveHelper.spacing(context, 16)),
                    ),
                    maxLines: 2,
                  ),
                ],
                
                SizedBox(height: ResponsiveHelper.spacing(context, 16)),
                
                // 안내 카드
                Container(
                  padding: ResponsiveHelper.cardPadding(context),
                  decoration: BoxDecoration(
                    color: AppColors.infoBg,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.info.withOpacity(0.3)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline, size: ResponsiveHelper.iconSize(context, 20), color: AppColors.info),
                      SizedBox(width: ResponsiveHelper.spacing(context, 12)),
                      Expanded(
                        child: Text(
                          '승인 시 7일간 신분증을 열람할 수 있습니다.',
                          style: ResponsiveHelper.smallStyle(context, color: AppColors.infoDark),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            actions: [
              StyledDialogButton.cancel(onPressed: () => Navigator.pop(dialogContext)),
              StyledDialogButton.primary(
                text: '요청 보내기',
                backgroundColor: AppColors.info,
                onPressed: selectedReason != null
                    ? () => _sendIdCardAccessRequest(dialogContext, selectedReason!, customReasonController.text)
                    : () {},
              ),
            ],
          );
        },
      ),
    );
  }

  /// 신분증 열람 요청 전송
  Future<void> _sendIdCardAccessRequest(BuildContext dialogContext, IdCardAccessReason reason, String customReason) async {
    Navigator.pop(dialogContext);
    
    try {
      final userProvider = context.read<UserProvider>();
      final currentUser = userProvider.currentUser;
      if (currentUser == null) {
        ToastHelper.showError('로그인이 필요합니다');
        return;
      }
      
      final businessId = widget.businessId ?? widget.toItem?.to.businessId;
      final business = businessId != null 
          ? await _firestoreService.getBusinessById(businessId)
          : null;
      
      await _firestoreService.createIdCardAccessRequest(
        requesterId: currentUser.uid,
        requesterName: currentUser.name,
        requesterBusinessId: businessId ?? '',
        requesterBusinessName: business?.name ?? '',
        targetUserId: widget.user.uid,
        targetUserName: widget.user.name,
        reason: reason,
        customReason: reason == IdCardAccessReason.other ? customReason : null,
        applicationId: widget.application?.id,
      );
      
      ToastHelper.showSuccess('열람 요청을 보냈습니다');
      
      setState(() {
        _idCardAccess = IdCardAccessRequestModel(
          id: '',
          requesterId: currentUser.uid,
          requesterName: currentUser.name,
          requesterBusinessId: businessId ?? '',
          requesterBusinessName: business?.name ?? '',
          targetUserId: widget.user.uid,
          targetUserName: widget.user.name,
          reason: reason,
          customReason: reason == IdCardAccessReason.other ? customReason : null,
          status: IdCardAccessStatus.pending,
          requestedAt: DateTime.now(),
          applicationId: widget.application?.id,
        );
      });
    } catch (e) {
      print('❌ 신분증 열람 요청 실패: $e');
      ToastHelper.showError('요청 실패');
    }
  }
}