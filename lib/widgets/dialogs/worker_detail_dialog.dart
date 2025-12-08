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
import '../../utils/id_card_helper.dart';
import 'styled_dialog.dart';
import '../../screens/business_admin/dialogs/fixed_worker_management_dialog.dart';
import '../common/loading_button.dart';

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
  static Future<bool?> show({
    required BuildContext context,
    required UserModel user,
    ApplicationModel? application,
    TOItem? toItem,
    String? businessId,
    bool isConfirmed = false,
    bool showApprovalButtons = false,
    VoidCallback? onStatusChanged,
  }) {
    return showDialog<bool>(
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
  bool _hasChanges = false;  // ⭐ 변경사항 추적 플래그 추가
  
  // 추가 데이터
  Map<String, dynamic>? _businessHistory;
  String? _workTime;  // 🔥 근무 시간 (장기용)
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
      
      // 최근 리뷰 (항상 로드)
      futures.add(_firestoreService.getUserReviews(widget.user.uid, limit: 5));
      
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
      
      // 결과 할당 (setState 밖에서)
      _businessHistory = results[0] as Map<String, dynamic>?;
      _recentReviews = results[1] as List<ReviewModel>;
      _idCardAccess = results[2] as IdCardAccessRequestModel?;
      
      // 🔥 근무 시간 조회 (장기 지원자용 - toItem 없을 때)
      final app = widget.application;
      if (app != null && widget.toItem == null) {
        if (app.startTime.isNotEmpty && app.endTime.isNotEmpty) {
          _workTime = '${app.startTime} ~ ${app.endTime}';
        } else {
          // TO 조회 후 workDetails에서 시간 가져오기
          final to = await _firestoreService.getTOByApplication(app);
          if (to != null) {
            final workDetails = await _firestoreService.getWorkDetails(to.id);
            final matched = workDetails.where((w) => w.workType == app.selectedWorkType).firstOrNull;
            if (matched != null) {
              _workTime = '${matched.startTime} ~ ${matched.endTime}';
            }
          }
        }
      }
      
      // 모든 작업 완료 후 UI 업데이트
      if (mounted) {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      print('❌ 추가 데이터 로드 실패: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
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
                          
                          // 최근 리뷰 (항상 표시)
                          SizedBox(height: ResponsiveHelper.spacing(context, 20)),
                          _buildRecentReviews(context),
                          
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
          // 근무 시간 표시
          if (app != null) ...[
            Builder(builder: (context) {
              if (widget.toItem != null) {
                final workDetail = widget.toItem!.workDetails.where(
                  (w) => w.workType == app.selectedWorkType,
                ).firstOrNull;
                if (workDetail != null) {
                  return _buildInfoRow(context, '근무 시간', '${workDetail.startTime} ~ ${workDetail.endTime}');
                }
              }
              if (_workTime != null) {
                return _buildInfoRow(context, '근무 시간', _workTime!);
              }
              return const SizedBox.shrink();
            }),
          ],
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
      child: _recentReviews.isEmpty
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
                    '아직 등록된 리뷰가 없습니다',
                    style: ResponsiveHelper.smallStyle(context, color: AppColors.grey500),
                  ),
                ],
              ),
            )
          : Column(
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
    final isConfirmed = widget.application?.status == 'CONFIRMED';
    final isLongTerm = widget.application?.workEndDate != null;

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
              onPressed: () => Navigator.pop(context, _hasChanges),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.grey600,
                side: BorderSide(color: AppColors.grey300),
                padding: EdgeInsets.symmetric(vertical: ResponsiveHelper.spacing(context, 12)),
              ),
              child: const Text('닫기'),
            ),
          ),
          
          // 승인/거절 버튼 (대기중이고 showApprovalButtons가 true일 때만)
          if (isPending && widget.showApprovalButtons && widget.application != null) ...[
            SizedBox(width: ResponsiveHelper.spacing(context, 8)),
            
            // 거절 버튼
            Expanded(
              child: LoadingButton.outlined(
                text: '거절',
                borderColor: AppColors.error,
                foregroundColor: AppColors.error,
                onPressed: () async => await _updateStatus('REJECTED'),
              ),
            ),
            SizedBox(width: ResponsiveHelper.spacing(context, 8)),
            
            // 승인 버튼
            Expanded(
              child: LoadingButton.success(
                text: '승인',
                onPressed: () async => await _updateStatus('CONFIRMED'),
              ),
            ),
          ],

          // 확정자 액션 버튼
          if (isConfirmed && widget.application != null) ...[
            SizedBox(width: ResponsiveHelper.spacing(context, 8)),
            
            if (isLongTerm) ...[
              // 장기 확정자: 고정근무 관리 버튼
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _openFixedWorkerManagement,
                  icon: Icon(
                    Icons.settings,
                    size: ResponsiveHelper.iconSize(context, 18),
                  ),
                  label: const Text('고정근무 관리'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.longTermDark,
                    foregroundColor: Colors.white,
                    padding: EdgeInsets.symmetric(vertical: ResponsiveHelper.spacing(context, 12)),
                  ),
                ),
              ),
            ] else ...[
              // 단기 확정자: 확정취소 버튼
              Expanded(
                child: LoadingButton.outlined(
                  text: '확정취소',
                  icon: Icons.cancel_outlined,
                  borderColor: AppColors.error,
                  foregroundColor: AppColors.error,
                  onPressed: () async => await _cancelConfirmation(),
                ),
              ),
            ],
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
  Future<void> _showIdCardAccessRequestDialog() async {
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

    final successCount = await IdCardHelper.showBatchRequestDialog(
      context: context,
      firestoreService: _firestoreService,
      requester: {
        'uid': currentUser.uid,
        'name': currentUser.name,
      },
      business: {
        'id': businessId ?? '',
        'name': business?.name ?? '',
      },
      targets: [
        {
          'uid': widget.user.uid,
          'name': widget.user.name,
          'applicationId': widget.application?.id ?? '',
        },
      ],
    );

    if (successCount > 0 && mounted) {
      setState(() {
        _hasChanges = true;
        _idCardAccess = IdCardAccessRequestModel(
          id: '',
          requesterId: currentUser.uid,
          requesterName: currentUser.name,
          requesterBusinessId: businessId ?? '',
          requesterBusinessName: business?.name ?? '',
          targetUserId: widget.user.uid,
          targetUserName: widget.user.name,
          reason: IdCardAccessReason.other,  // 실제 선택값은 Helper에서 처리
          status: IdCardAccessStatus.pending,
          requestedAt: DateTime.now(),
        );
      });
    }
  }
  
  /// 단기 확정 취소
  Future<void> _cancelConfirmation() async {
    if (widget.application == null) return;

    // 취소 사유 선택
    final cancelReason = await _showCancelReasonPicker();
    if (cancelReason == null) return;

    try {
      final userProvider = context.read<UserProvider>();
      final adminUID = userProvider.currentUser?.uid;

      await _firestoreService.updateApplicationStatus(
        applicationId: widget.application!.id,
        status: 'CANCELED',
        rejectedBy: adminUID,
        message: cancelReason,
      );

      if (mounted) {
        Navigator.pop(context, true);
        ToastHelper.showSuccess('확정이 취소되었습니다');
        widget.onStatusChanged?.call();
      }
    } catch (e) {
      print('❌ 확정 취소 실패: $e');
      if (mounted) {
        ToastHelper.showError('확정 취소 중 오류가 발생했습니다');
      }
    }
  }

  /// 확정취소 사유 선택 다이얼로그
  Future<String?> _showCancelReasonPicker() async {
    final theme = Theme.of(context);
    String? selectedReason;
    final customReasonController = TextEditingController();

    final reasons = [
      '일정 변경',
      '인원 조정',
      '업무 취소',
      '근무자 요청',
      '기타',
    ];

    final result = await showDialog<String>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return Dialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Container(
              width: double.maxFinite,
              constraints: const BoxConstraints(maxWidth: 400),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 헤더
                  Container(
                    padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 16)),
                    decoration: BoxDecoration(
                      color: AppColors.error,
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(16),
                        topRight: Radius.circular(16),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.cancel_outlined,
                          color: Colors.white,
                          size: ResponsiveHelper.iconSize(context, 24),
                        ),
                        SizedBox(width: ResponsiveHelper.spacing(context, 12)),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '확정 취소',
                                style: ResponsiveHelper.subtitleStyle(context).copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                '${widget.user.name}님',
                                style: ResponsiveHelper.smallStyle(context, color: Colors.white70),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: Icon(
                            Icons.close,
                            color: Colors.white,
                            size: ResponsiveHelper.iconSize(context, 24),
                          ),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ],
                    ),
                  ),

                  // 사유 선택
                  Padding(
                    padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 16)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '취소 사유를 선택해주세요',
                          style: ResponsiveHelper.bodyStyle(context).copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        SizedBox(height: ResponsiveHelper.spacing(context, 12)),

                        // 사유 목록
                        ...reasons.map((reason) => Padding(
                          padding: EdgeInsets.only(bottom: ResponsiveHelper.spacing(context, 8)),
                          child: InkWell(
                            onTap: () => setDialogState(() => selectedReason = reason),
                            borderRadius: BorderRadius.circular(8),
                            child: Container(
                              padding: EdgeInsets.symmetric(
                                horizontal: ResponsiveHelper.spacing(context, 12),
                                vertical: ResponsiveHelper.spacing(context, 12),
                              ),
                              decoration: BoxDecoration(
                                color: selectedReason == reason
                                    ? AppColors.errorBg
                                    : AppColors.grey100,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: selectedReason == reason
                                      ? AppColors.error
                                      : AppColors.grey300,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    selectedReason == reason
                                        ? Icons.radio_button_checked
                                        : Icons.radio_button_off,
                                    color: selectedReason == reason
                                        ? AppColors.error
                                        : AppColors.grey400,
                                    size: ResponsiveHelper.iconSize(context, 20),
                                  ),
                                  SizedBox(width: ResponsiveHelper.spacing(context, 12)),
                                  Text(
                                    reason,
                                    style: ResponsiveHelper.bodyStyle(context),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        )),

                        // 기타 사유 입력
                        if (selectedReason == '기타') ...[
                          SizedBox(height: ResponsiveHelper.spacing(context, 8)),
                          TextField(
                            controller: customReasonController,
                            decoration: InputDecoration(
                              hintText: '취소 사유를 입력하세요',
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                              contentPadding: EdgeInsets.symmetric(
                                horizontal: ResponsiveHelper.spacing(context, 12),
                                vertical: ResponsiveHelper.spacing(context, 12),
                              ),
                            ),
                            style: ResponsiveHelper.bodyStyle(context),
                            maxLines: 2,
                          ),
                        ],
                      ],
                    ),
                  ),

                  // 하단 버튼
                  Container(
                    padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 16)),
                    decoration: BoxDecoration(
                      border: Border(top: BorderSide(color: AppColors.border)),
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
                                vertical: ResponsiveHelper.spacing(context, 12),
                              ),
                            ),
                            child: const Text('취소'),
                          ),
                        ),
                        SizedBox(width: ResponsiveHelper.spacing(context, 12)),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: selectedReason != null
                                ? () {
                                    final reason = selectedReason == '기타' &&
                                            customReasonController.text.trim().isNotEmpty
                                        ? customReasonController.text.trim()
                                        : selectedReason;
                                    Navigator.pop(context, reason);
                                  }
                                : null,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.error,
                              foregroundColor: Colors.white,
                              padding: EdgeInsets.symmetric(
                                vertical: ResponsiveHelper.spacing(context, 12),
                              ),
                            ),
                            child: const Text('확정 취소'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
    return result;
  }

  /// 고정근무 관리 다이얼로그 열기
  void _openFixedWorkerManagement() {
    final businessId = widget.businessId ?? widget.application?.businessId;
    
    if (businessId == null) {
      ToastHelper.showError('사업장 정보를 찾을 수 없습니다');
      return;
    }

    // 현재 다이얼로그 닫기
    Navigator.pop(context);

    // 고정근무 관리 다이얼로그 열기
    showDialog(
      context: context,
      builder: (context) => FixedWorkerManagementDialog(
        businessId: businessId,
        onChanged: () {
          widget.onStatusChanged?.call();
        },
      ),
    );
  }
}