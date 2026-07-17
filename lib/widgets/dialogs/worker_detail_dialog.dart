// lib/widgets/dialogs/worker_detail_dialog.dart
// 공통 근무자/지원자 상세 다이얼로그
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../models/core/application_model.dart';
import '../../models/core/user_model.dart';
import '../../models/core/id_card_access_request_model.dart';
import '../../models/ui/admin_to_list_ui_models.dart';
import '../../models/core/employment_contract_model.dart';
import '../../models/core/work_detail_data.dart';
import '../../screens/contract/contract_sign_screen.dart';
import '../../services/contract_service.dart';
import 'contract_template_selector_dialog.dart';
import '../../services/firestore_service.dart';
import '../../providers/user_provider.dart';
import '../../utils/toast_helper.dart';
import '../../utils/responsive_helper.dart';
import '../../utils/format_helper.dart';
import '../../utils/dialog_helper.dart';
import '../../theme/app_colors.dart';
import '../../utils/id_card_helper.dart';
import '../../screens/business_admin/dialogs/fixed_worker_management_dialog.dart';
import '../../utils/image_helper.dart';
import '../../utils/encryption_helper.dart';
import 'monthly_review_dialog.dart';
import 'styled_dialog.dart';
import '../../models/core/monthly_review_model.dart';
import '../../models/core/review_request_model.dart';
import '../../services/monthly_review_service.dart';
import '../../widgets/common/loading_widget.dart';

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
  final String? attendanceStatus;  // ✅ 추가: 출퇴근/급여 상태

  const WorkerDetailDialog({
    super.key,
    required this.user,
    this.application,
    this.toItem,
    this.businessId,
    this.isConfirmed = false,
    this.showApprovalButtons = false,
    this.onStatusChanged,
    this.attendanceStatus,  // ✅ 추가
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
    String? attendanceStatus,  // ✅ 추가
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
        attendanceStatus: attendanceStatus,  // ✅ 추가
      ),
    );
  }

  @override
  State<WorkerDetailDialog> createState() => _WorkerDetailDialogState();
}

class _WorkerDetailDialogState extends State<WorkerDetailDialog> {
  final FirestoreService _firestoreService = FirestoreService();
  bool _isLoading = true;
  bool _hasChanges = false;  // ⭐ 변경사항 추적 플래그 추가
  bool _showResidentNumber = false;
  
  // 추가 데이터
  Map<String, dynamic>? _businessHistory;
  String? _workTime;  // 🔥 근무 시간 (장기용)
  List<MonthlyReviewModel> _recentReviews = [];
  IdCardAccessRequestModel? _idCardAccess;
  // 다이얼로그가 열린 상태에서 신분증 열람 권한이 만료/철회되어도 UI에 반영되지 않는 문제.
  // 60초마다 Firestore 재조회로 만료(시간 경과)·철회(상태 변경) 모두 감지한다.
  Timer? _accessRefreshTimer;
  // ID-1 보안: 직접 URL 대신 CF 발급 1시간 만료 Signed URL 캐시
  String? _idCardSignedUrl;
  bool _idCardSignedUrlLoading = false;
  bool _hasAttendance = false;  // ✅ 출퇴근 기록 여부 (장기 확정자용)
  bool? _hasWrittenReview;     // 리뷰 작성 여부 (null=미확인)
  EmploymentContractModel? _contract;

  @override
  void initState() {
    super.initState();
    // addPostFrameCallback으로 첫 프레임 이후 로드
    // Firestore 캐시 히트 시 _loadAdditionalData()가 첫 프레임 전에 완료되어
    // _isLoading=false 상태로 빈 프로필이 1~2프레임 노출되는 플래시 방지
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _loadAdditionalData();
    });
  }

  Future<void> _loadAdditionalData() async {

    try {
      final userProvider = context.read<UserProvider>();
      final currentUserId = userProvider.currentUser?.uid ?? '';
      final businessId = widget.businessId ?? widget.toItem?.to.businessId;
      final app = widget.application;

      final results = await Future.wait([
        // 0: 우리 사업장 이력
        businessId != null
            ? _firestoreService.getBusinessWorkHistory(
                businessId: businessId, userId: widget.user.uid)
            : Future.value(null),

        // 1: 최근 리뷰 (monthly_reviews 컬렉션) — CF 경유 (callableGetReviewsForUser)
        MonthlyReviewService().getPublishedReviewsForUser(targetUserId: widget.user.uid, limit: 5),

        // 2: 신분증 열람 권한 (확정자만)
        widget.isConfirmed
            ? _firestoreService.checkIdCardAccess(
                requesterId: currentUserId, targetUserId: widget.user.uid)
            : Future.value(null),

        // 3: 장기 출퇴근 기록 여부
        (app != null &&
                widget.isConfirmed &&
                (app.isLongTermApplication ||
                    widget.toItem?.to.isLongTerm == true))
            ? _firestoreService.hasAttendanceRecord(app.id, businessId: app.businessId)
            : Future.value(false),

        // 4: 근무 시간 (toItem 없을 때)
        (app != null && widget.toItem == null)
            ? _fetchWorkTime(app)
            : Future.value(null),

        // 5: 리뷰 작성 여부 (확정자 + businessId 있을 때)
        (widget.isConfirmed && app != null && widget.businessId != null)
            ? _checkReviewWritten(app)
            : Future.value(null),

        // 6: 계약서 (확정자 + application 있을 때) — 관리자 컨텍스트이므로 businessId 전달
        (widget.isConfirmed && app != null)
            ? ContractService().getByApplication(app.id, businessId: app.businessId)
            : Future.value(null),
      ]);

      _businessHistory = results[0] as Map<String, dynamic>?;
      _recentReviews = (results[1] as List).cast<MonthlyReviewModel>();
      _idCardAccess = results[2] as IdCardAccessRequestModel?;
      _hasAttendance = (results[3] as bool?) ?? false;
      _workTime = results[4] as String?;
      _hasWrittenReview = results[5] as bool?;
      _contract = results[6] as EmploymentContractModel?;

      if (_idCardAccess?.isValidAccess == true) {
        _startAccessRefreshTimer();
        _loadIdCardSignedUrl();
      }

      if (mounted) setState(() => _isLoading = false);
    } catch (e) {
      debugPrint('❌ 추가 데이터 로드 실패: $e');
      if (mounted) {
        setState(() => _isLoading = false);
        ToastHelper.showError('데이터를 불러오는데 실패했습니다.');
      }
    }
  }

  Future<void> _loadIdCardSignedUrl() async {
    if (!mounted) return;
    setState(() => _idCardSignedUrlLoading = true);
    final url = await _firestoreService.getIdCardSignedUrl(widget.user.uid);
    if (!mounted) return;
    setState(() {
      _idCardSignedUrl = url;
      _idCardSignedUrlLoading = false;
    });
  }

  void _startAccessRefreshTimer() {
    _accessRefreshTimer?.cancel();
    _accessRefreshTimer = Timer.periodic(const Duration(seconds: 60), (_) async {
      if (!mounted) return;
      final currentUserId = context.read<UserProvider>().currentUser?.uid ?? '';
      final updated = await _firestoreService.checkIdCardAccess(
        requesterId: currentUserId,
        targetUserId: widget.user.uid,
      );
      if (!mounted) return;
      setState(() => _idCardAccess = updated);
      if (updated?.isValidAccess != true) _accessRefreshTimer?.cancel();
    });
  }

  @override
  void dispose() {
    _accessRefreshTimer?.cancel();
    super.dispose();
  }

  Future<String?> _fetchWorkTime(ApplicationModel app) async {
    if (app.startTime.isNotEmpty && app.endTime.isNotEmpty) {
      return '${app.startTime} ~ ${app.endTime}';
    }
    final to = await _firestoreService.getTOByApplication(app);
    if (to == null) return null;
    final workDetails = await _firestoreService.getWorkDetails(to.id);
    final matched = workDetails
        .where((w) => w.workType == app.selectedWorkType)
        .firstOrNull;
    if (matched == null) return null;
    return '${matched.startTime} ~ ${matched.endTime}';
  }

  Future<bool> _checkReviewWritten(ApplicationModel app) async {
    final now = DateTime.now();
    int reviewYear;
    int reviewMonth;
    if (app.isLongTermApplication) {
      if (now.month == 1) {
        reviewYear = now.year - 1;
        reviewMonth = 12;
      } else {
        reviewYear = now.year;
        reviewMonth = now.day < 5 ? now.month - 1 : now.month;
      }
    } else {
      reviewYear = app.workDate.year;
      reviewMonth = app.workDate.month;
    }
    final reviewKey = MonthlyReviewModel.generateKeyForUser(
      businessId: widget.businessId!,
      targetUserId: widget.user.uid,
      year: reviewYear,
      month: reviewMonth,
    );
    final existing = await MonthlyReviewService().getReviewById(reviewKey);
    return existing != null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final trustScore = widget.user.trustScore;
    final isPending = widget.application?.status == AppStatus.pending;

   return Dialog(
      backgroundColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
      ),
      insetPadding: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 16),
        vertical: AppDialogSize.insetV,
      ),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * AppDialogSize.maxHeightRatio,
        ),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.15),
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
                  ? const LoadingWidget()
                  : SingleChildScrollView(
                      padding: ResponsiveHelper.cardPadding(context),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildBasicInfo(context),
                          SizedBox(height: ResponsiveHelper.spacing(context, 20)),
                          if (widget.isConfirmed) ...[
                            _buildPaymentInfo(context),
                            SizedBox(height: ResponsiveHelper.spacing(context, 20)),
                            _buildContractStatusSection(context),
                            SizedBox(height: ResponsiveHelper.spacing(context, 20)),
                            _buildIdCardSection(context),
                            SizedBox(height: ResponsiveHelper.spacing(context, 20)),
                            _buildWorkStats(context),
                            SizedBox(height: ResponsiveHelper.spacing(context, 20)),
                            _buildBusinessHistory(context),
                            SizedBox(height: ResponsiveHelper.spacing(context, 20)),
                            _buildRecentReviews(context),
                            SizedBox(height: ResponsiveHelper.spacing(context, 20)),
                            _buildSelfIntro(context),
                          ] else ...[
                            _buildWorkStats(context),
                            SizedBox(height: ResponsiveHelper.spacing(context, 20)),
                            _buildBusinessHistory(context),
                            SizedBox(height: ResponsiveHelper.spacing(context, 20)),
                            _buildSelfIntro(context),
                            SizedBox(height: ResponsiveHelper.spacing(context, 20)),
                            _buildRecentReviews(context),
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
          colors: [theme.primaryColor, theme.primaryColor.withValues(alpha: 0.8)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(ResponsiveHelper.spacing(context, 20)),
          topRight: Radius.circular(ResponsiveHelper.spacing(context, 20)),
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
                backgroundImage: widget.user.profileImageUrl != null
                    ? CachedNetworkImageProvider(widget.user.profileImageUrl!)
                    : null,
                child: widget.user.profileImageUrl == null
                    ? Text(
                        widget.user.name.isNotEmpty ? widget.user.name[0] : '?',
                        style: ResponsiveHelper.titleStyle(context).copyWith(
                          fontWeight: FontWeight.bold,
                          color: theme.primaryColor,
                        ),
                      )
                    : null,
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
                      style: ResponsiveHelper.bodyStyle(context, color: Colors.white.withValues(alpha: 0.7)),
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
                  color: trustScore >= 80
                      ? AppColors.success.withValues(alpha: 0.25)
                      : trustScore >= 60
                          ? AppColors.amber.withValues(alpha: 0.25)
                          : AppColors.error.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    Text(
                      '$trustScore',
                      style: ResponsiveHelper.titleStyle(context).copyWith(
                        color: trustScore >= 80
                            ? AppColors.success
                            : trustScore >= 60
                                ? AppColors.amber
                                : AppColors.error,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      '신뢰도',
                      style: ResponsiveHelper.tinyStyle(context, color: Colors.white.withValues(alpha: 0.7)),
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
              color: Colors.white.withValues(alpha: 0.15),
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
                    color: Colors.white.withValues(alpha: 0.2),
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
      case AppStatus.pending:
        return AppColors.warning;
      case AppStatus.confirmed:
        return AppColors.success;
      case AppStatus.rejected:
        return AppColors.error;
      default:
        return AppColors.grey500;
    }
  }

  // H-8: 주민번호 복사 시 감사 로그 기록 (개인정보보호법 접근 기록)
  // [SEC-LOG-COPY] 로그 실패 시 false 반환 → 호출자가 복사 차단
  Future<bool> _logResidentNumberCopy() async {
    try {
      final viewerId = context.read<UserProvider>().currentUser?.uid;
      if (viewerId == null) return false;
      // [SEC-84] bizId 폴백: widget 파라미터가 모두 null일 경우 UserProvider에서 보완
      //   isAdminOf('')==false → 로그 미기록 silently fail 방지
      final userProv = context.read<UserProvider>();
      final managedIds = userProv.currentUser?.managedBusinessIds;
      final bizId = widget.businessId ??
          widget.toItem?.to.businessId ??
          userProv.effectiveBusinessId ??
          (managedIds != null && managedIds.isNotEmpty ? managedIds.first : '');
      await FirebaseFirestore.instance.collection('id_card_copy_logs').add({
        'viewerId': viewerId,
        'targetUserId': widget.user.uid,
        'businessId': bizId,
        'copiedAt': FieldValue.serverTimestamp(),
        'action': 'resident_number_copy',
      });
      return true;
    } catch (e) {
      debugPrint('⚠️ [H-8] 주민번호 복사 감사 로그 기록 실패: $e');
      if (mounted) ToastHelper.showError('감사 로그 기록 실패로 복사가 중단되었습니다.');
      return false;
    }
  }

  String _formatResidentNumber(String raw) {
    final cleaned = raw.replaceAll('-', '');
    if (cleaned.length >= 13) {
      return '${cleaned.substring(0, 6)}-${cleaned.substring(6)}';
    }
    return raw;
  }

  String _getStatusLabel(String status) {
    switch (status) {
      case AppStatus.pending:
        return '대기중';
      case AppStatus.confirmed:
        return '확정';
      case AppStatus.rejected:
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
            widget.isConfirmed && app.confirmedAt != null
                ? _buildInfoRow(context, '확정일', DateFormat('yyyy.MM.dd HH:mm').format(app.confirmedAt!))
                : _buildInfoRow(context, '지원일', DateFormat('yyyy.MM.dd HH:mm').format(app.appliedAt)),
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
            // ✅ 희망 시작일 강조 표시
            if (app.desiredStartDate != null)
              _buildInfoRow(
                context, 
                '희망 시작일', 
                '${app.desiredStartDate!.month}/${app.desiredStartDate!.day} (${_getWeekdayName(app.desiredStartDate!)})',
                highlight: true,
              ),
        ],
        ],
      ),
      
    );
  }
  String _getWeekdayName(DateTime date) => FormatHelper.weekday(date);

  /// 근무 통계
  Widget _buildWorkStats(BuildContext context) {
    final user = widget.user;
    return _buildSection(
      context,
      title: '근무 통계',
      icon: Icons.bar_chart,
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _buildStatCard(
                  context,
                  icon: Icons.work_history_outlined,
                  label: '총 근무',
                  value: '${user.totalWorkDays}일',
                  color: AppColors.info,
                ),
              ),
              SizedBox(width: ResponsiveHelper.spacing(context, 8)),
              Expanded(
                child: _buildStatCard(
                  context,
                  icon: Icons.star_rounded,
                  label: '평균 평점',
                  value: user.averageRating > 0
                      ? user.averageRating.toStringAsFixed(1)
                      : '-',
                  color: AppColors.amberMedium,
                ),
              ),
            ],
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 8)),
          Row(
            children: [
              Expanded(
                child: _buildStatCard(
                  context,
                  icon: Icons.cancel_outlined,
                  label: '무단결근',
                  value: '${user.noShowCount}회',
                  color: user.noShowCount > 0 ? AppColors.error : AppColors.grey400,
                  bgColor: user.noShowCount > 0 ? AppColors.errorBg : AppColors.grey100,
                ),
              ),
              SizedBox(width: ResponsiveHelper.spacing(context, 8)),
              Expanded(
                child: _buildStatCard(
                  context,
                  icon: Icons.schedule_outlined,
                  label: '지각',
                  value: '${user.lateCount}회',
                  color: user.lateCount > 0 ? AppColors.warning : AppColors.grey400,
                  bgColor: user.lateCount > 0 ? AppColors.warningBg : AppColors.grey100,
                ),
              ),
            ],
          ),
          if (user.reviewCount > 0) ...[
            SizedBox(height: ResponsiveHelper.spacing(context, 8)),
            _buildRehireRateBadge(context, user.rehireRate, user.reviewCount),
          ],
        ],
      ),
    );
  }

  Widget _buildRehireRateBadge(BuildContext context, double rate, int reviewCount) {
    final pct = (rate * 100).round();
    final Color color;
    final Color bgColor;
    final IconData icon;
    if (rate >= 0.7) {
      color = AppColors.successDark;
      bgColor = AppColors.successBg;
      icon = Icons.thumb_up_rounded;
    } else if (rate >= 0.4) {
      color = AppColors.warningDark;
      bgColor = AppColors.warningBg;
      icon = Icons.thumbs_up_down_rounded;
    } else {
      color = AppColors.errorDark;
      bgColor = AppColors.errorBg;
      icon = Icons.thumb_down_rounded;
    }

    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 14),
        vertical: ResponsiveHelper.spacing(context, 10),
      ),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(icon, size: ResponsiveHelper.iconSize(context, 16), color: color),
          SizedBox(width: ResponsiveHelper.spacing(context, 8)),
          Text(
            '재고용 추천률',
            style: ResponsiveHelper.smallStyle(context, color: color),
          ),
          const Spacer(),
          Text(
            '$pct%',
            style: ResponsiveHelper.subtitleStyle(context).copyWith(
              color: color,
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(width: ResponsiveHelper.spacing(context, 4)),
          Text(
            '(전체 $reviewCount건)',
            style: ResponsiveHelper.tinyStyle(context, color: color),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String value,
    required Color color,
    Color? bgColor,
  }) {
    final bg = bgColor ?? color.withValues(alpha: 0.1);
    return Container(
      padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 12)),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Icon(icon, size: ResponsiveHelper.iconSize(context, 20), color: color),
          SizedBox(height: ResponsiveHelper.spacing(context, 6)),
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
            textAlign: TextAlign.center,
          ),
        ],
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
                  _buildInfoRow(context, '평균 평점', '${(_businessHistory!['avgRating'] as num).toDouble().toStringAsFixed(1)}점'),
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

  Widget _buildReviewItem(BuildContext context, MonthlyReviewModel review) {
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
                  color: AppColors.amber,
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
            '${review.businessName} · ${review.reviewYear}년 ${review.reviewMonth}월',
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

  /// 근로계약서 섹션 (확정자만)
  Widget _buildContractStatusSection(BuildContext context) {
    return _buildSection(
      context,
      title: '근로계약서',
      icon: Icons.description_outlined,
      child: _buildContractContent(context),
    );
  }

  Widget _buildContractContent(BuildContext context) {
    final contract = _contract;

    if (contract == null) {
      final canCreate = widget.isConfirmed &&
          widget.application != null &&
          (widget.toItem != null ||
              widget.application!.toId?.isNotEmpty == true);
      return Column(
        children: [
          Container(
            padding: ResponsiveHelper.cardPadding(context),
            decoration: BoxDecoration(
              color: AppColors.grey50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline, color: AppColors.grey400, size: ResponsiveHelper.iconSize(context, 16)),
                SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                Text(
                  '계약서가 없습니다',
                  style: ResponsiveHelper.smallStyle(context, color: AppColors.grey500),
                ),
              ],
            ),
          ),
          if (canCreate) ...[
            SizedBox(height: ResponsiveHelper.spacing(context, 8)),
            SizedBox(
              width: double.infinity,
              child: _buildDialogButton(
                label: '계약서 작성하기',
                icon: Icons.draw_outlined,
                bgColor: Theme.of(context).primaryColor.withValues(alpha: 0.08),
                textColor: Theme.of(context).primaryColor,
                onTap: _createContractAndSign,
              ),
            ),
          ],
        ],
      );
    }

    if (contract.status == ContractStatus.pendingEmployer) {
      return SizedBox(
        width: double.infinity,
        child: _buildDialogButton(
          label: '계약서 서명하기 (사업주)',
          icon: Icons.draw,
          bgColor: Theme.of(context).primaryColor.withValues(alpha: 0.08),
          textColor: Theme.of(context).primaryColor,
          onTap: () => _openExistingContractSign(contract),
        ),
      );
    }

    if (contract.status == ContractStatus.pendingWorker) {
      return Container(
        padding: ResponsiveHelper.cardPadding(context),
        decoration: BoxDecoration(
          color: AppColors.warningBg,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.warning.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            Icon(Icons.hourglass_top, color: AppColors.warning, size: ResponsiveHelper.iconSize(context, 20)),
            SizedBox(width: ResponsiveHelper.spacing(context, 8)),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '근무자 서명 대기 중',
                    style: ResponsiveHelper.bodyStyle(context).copyWith(
                      fontWeight: FontWeight.bold,
                      color: AppColors.warningDark,
                    ),
                  ),
                  Text(
                    '근무자에게 서명 요청 알림이 발송되었습니다',
                    style: ResponsiveHelper.smallStyle(context, color: AppColors.warning),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    if (contract.status == ContractStatus.completed) {
      return Container(
        padding: ResponsiveHelper.cardPadding(context),
        decoration: BoxDecoration(
          color: AppColors.successBg,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.success.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            Icon(Icons.verified, color: AppColors.success, size: ResponsiveHelper.iconSize(context, 20)),
            SizedBox(width: ResponsiveHelper.spacing(context, 8)),
            Text(
              '계약서 서명 완료',
              style: ResponsiveHelper.bodyStyle(context).copyWith(
                fontWeight: FontWeight.bold,
                color: AppColors.successDark,
              ),
            ),
          ],
        ),
      );
    }

    // voided
    return Container(
      padding: ResponsiveHelper.cardPadding(context),
      decoration: BoxDecoration(
        color: AppColors.grey100,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.grey300),
      ),
      child: Row(
        children: [
          Icon(Icons.cancel_outlined, color: AppColors.grey500, size: ResponsiveHelper.iconSize(context, 20)),
          SizedBox(width: ResponsiveHelper.spacing(context, 8)),
          Text(
            '계약 무효 처리됨',
            style: ResponsiveHelper.bodyStyle(context, color: AppColors.grey500),
          ),
        ],
      ),
    );
  }

  Future<void> _openExistingContractSign(EmploymentContractModel contract) async {
    var c = contract;

    // 조항 없는 구 계약서 → 서명 전에 템플릿 선택 유도
    if (c.articles.isEmpty) {
      final businessId = widget.businessId ?? widget.toItem?.to.businessId;
      if (businessId != null && mounted) {
        final articles = await ContractTemplateSelectorDialog.show(
          context,
          businessId: businessId,
        );
        if (articles == null || !mounted) return; // 취소 → 중단
        if (articles.isNotEmpty) {
          await ContractService().updateArticles(
            contractId: c.id,
            articles: articles,
          );
          if (!mounted) return;
          c = c.copyWith(articles: articles);
        }
      }
    }

    if (!mounted) return;
    final nav = Navigator.of(context, rootNavigator: true);
    Navigator.pop(context, _hasChanges);
    widget.onStatusChanged?.call();
    await nav.push(MaterialPageRoute(
      builder: (_) => ContractSignScreen(contract: c, role: 'employer'),
    ));
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
              border: Border.all(color: AppColors.success.withValues(alpha: 0.3)),
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
                        '${_idCardAccess!.remainingDays ?? 0}일 후 만료',
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
            _idCardSignedUrlLoading
                ? Container(
                    height: ResponsiveHelper.spacing(context, 150),
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: AppColors.grey100,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Center(child: LoadingWidget()),
                  )
                : _idCardSignedUrl != null
                    ? GestureDetector(
                        onTap: () => ImageHelper.showFullScreenViewer(
                          context,
                          imageUrl: _idCardSignedUrl,
                          title: '신분증',
                        ),
                        child: Stack(
                          children: [
                            Container(
                              height: ResponsiveHelper.spacing(context, 150),
                              width: double.infinity,
                              decoration: BoxDecoration(
                                color: AppColors.grey100,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: CachedNetworkImage(
                                  imageUrl: _idCardSignedUrl!,
                                  fit: BoxFit.contain,
                                  placeholder: (context, url) => const LoadingWidget(),
                                  errorWidget: (context, url, error) => Center(
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.image_not_supported, color: AppColors.grey400),
                                        const SizedBox(height: 4),
                                        TextButton(
                                          onPressed: _loadIdCardSignedUrl,
                                          child: const Text('다시 시도'),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            Positioned(
                              right: 8,
                              bottom: 8,
                              child: Container(
                                padding: const EdgeInsets.all(4),
                                decoration: BoxDecoration(
                                  color: Colors.black54,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Icon(
                                  Icons.zoom_in,
                                  color: Colors.white,
                                  size: 18,
                                ),
                              ),
                            ),
                          ],
                        ),
                      )
                    : Container(
                        height: ResponsiveHelper.spacing(context, 150),
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: AppColors.grey100,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.image_not_supported, color: AppColors.grey400),
                              const SizedBox(height: 8),
                              TextButton(
                                onPressed: _loadIdCardSignedUrl,
                                child: const Text('이미지 로드'),
                              ),
                            ],
                          ),
                        ),
                      ),
          // 주민번호 텍스트 표시 — 이미지만으로 확인이 어려운 경우 보조
          if (widget.user.residentNumber != null) ...[
            SizedBox(height: ResponsiveHelper.spacing(context, 10)),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.grey50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.grey200),
              ),
              child: Row(
                children: [
                  Icon(Icons.badge_outlined, color: AppColors.grey500, size: ResponsiveHelper.iconSize(context, 18)),
                  SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '주민등록번호',
                          style: ResponsiveHelper.smallStyle(context, color: AppColors.grey500),
                        ),
                        Text(
                          _showResidentNumber
                              ? _formatResidentNumber(widget.user.residentNumber!)
                              : EncryptionHelper.maskResidentNumber(widget.user.residentNumber),
                          style: ResponsiveHelper.bodyStyle(context).copyWith(
                            fontWeight: FontWeight.w600,
                            letterSpacing: 1.0,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(
                      _showResidentNumber ? Icons.visibility_off : Icons.visibility,
                      color: AppColors.grey500,
                      size: ResponsiveHelper.iconSize(context, 20),
                    ),
                    tooltip: _showResidentNumber ? '번호 숨기기' : '전체 보기',
                    onPressed: () => setState(() => _showResidentNumber = !_showResidentNumber),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                  SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                  IconButton(
                    icon: Icon(Icons.copy, color: AppColors.info, size: ResponsiveHelper.iconSize(context, 20)),
                    tooltip: '번호 복사',
                    onPressed: () async {
                      final logged = await _logResidentNumberCopy();
                      if (!logged || !mounted) return;
                      await Clipboard.setData(ClipboardData(text: widget.user.residentNumber!.replaceAll('-', '')));
                      if (!mounted) return;
                      ToastHelper.showSuccess('주민번호가 복사되었습니다.');
                    },
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            ),
          ],
        ],
      );
    }
    
    // 만료/거절 상태 — 재요청 가능
    final access = _idCardAccess;
    if (access != null &&
        (access.status == IdCardAccessStatus.expired ||
         (access.status == IdCardAccessStatus.approved && access.isExpired) ||
         access.status == IdCardAccessStatus.rejected)) {
      final isExpiredState = access.status != IdCardAccessStatus.rejected;
      return Container(
        width: double.infinity,
        padding: ResponsiveHelper.cardPadding(context),
        decoration: BoxDecoration(
          color: isExpiredState ? AppColors.warningBg : AppColors.errorBg,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: (isExpiredState ? AppColors.warning : AppColors.error).withValues(alpha: 0.3),
          ),
        ),
        child: Column(
          children: [
            Icon(
              isExpiredState ? Icons.timer_off : Icons.block,
              size: ResponsiveHelper.iconSize(context, 32),
              color: isExpiredState ? AppColors.warningDark : AppColors.errorDark,
            ),
            SizedBox(height: ResponsiveHelper.spacing(context, 8)),
            Text(
              isExpiredState ? '열람 권한이 만료됐습니다' : '열람 요청이 거절됐습니다',
              style: ResponsiveHelper.bodyStyle(context).copyWith(
                fontWeight: FontWeight.bold,
                color: isExpiredState ? AppColors.warningDark : AppColors.errorDark,
              ),
            ),
            if (!isExpiredState && access.rejectionReason != null) ...[
              SizedBox(height: ResponsiveHelper.spacing(context, 4)),
              Text(
                access.rejectionReason!,
                style: ResponsiveHelper.smallStyle(context, color: AppColors.errorDark),
                textAlign: TextAlign.center,
              ),
            ],
            SizedBox(height: ResponsiveHelper.spacing(context, 12)),
            SizedBox(
              width: double.infinity,
              child: _buildDialogButton(
                label: '다시 요청하기',
                icon: Icons.refresh,
                bgColor: AppColors.infoBg,
                textColor: AppColors.infoDark,
                onTap: () => _showIdCardAccessRequestDialog(),
              ),
            ),
          ],
        ),
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
          border: Border.all(color: AppColors.warning.withValues(alpha: 0.3)),
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
            child: _buildDialogButton(
              label: '열람 요청',
              icon: Icons.send_outlined,
              bgColor: AppColors.infoBg,
              textColor: AppColors.infoDark,
              onTap: () => _showIdCardAccessRequestDialog(),
            ),
          ),
        ],
      ),
    );
  }

  /// 공통 섹션 빌더
  Widget _buildSection(BuildContext context, {required String title, required IconData icon, required Widget child}) {
    final primary = Theme.of(context).primaryColor;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: ResponsiveHelper.spacing(context, 3),
              height: ResponsiveHelper.spacing(context, 16),
              decoration: BoxDecoration(
                color: primary,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            SizedBox(width: ResponsiveHelper.spacing(context, 8)),
            Icon(icon, size: ResponsiveHelper.iconSize(context, 15), color: primary.withValues(alpha: 0.8)),
            SizedBox(width: ResponsiveHelper.spacing(context, 6)),
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

  Widget _buildInfoRow(BuildContext context, String label, String value, {bool highlight = false}) {
    final theme = Theme.of(context);
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
              style: ResponsiveHelper.bodyStyle(
                context, 
                color: highlight ? theme.primaryColor : null,
              ).copyWith(
                fontWeight: highlight ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 하단 버튼
  Widget _buildDialogButton({
    required String label,
    required IconData icon,
    required Color bgColor,
    required Color textColor,
    required VoidCallback onTap,
    double verticalPadding = 12,
  }) {
    return Material(
      color: bgColor,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: verticalPadding, horizontal: 4),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 15, color: textColor),
                const SizedBox(width: 5),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: textColor,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBottomButtons(BuildContext context, bool isPending) {
    final isConfirmed = AppStatus.confirmedStatuses.contains(widget.application?.status);
    final isLongTerm = widget.toItem?.to.isLongTerm ??
                       widget.application?.isLongTermApplication ??
                       false;
    final primary = Theme.of(context).primaryColor;

    return Container(
      padding: ResponsiveHelper.cardPadding(context),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          // 닫기 버튼 (항상)
          Expanded(
            child: _buildDialogButton(
              label: '닫기',
              icon: Icons.close,
              bgColor: AppColors.grey100,
              textColor: AppColors.grey600,
              onTap: () => Navigator.pop(context, _hasChanges),
            ),
          ),

          // 승인/거절 버튼 (대기중이고 showApprovalButtons가 true일 때만)
          // 블랙리스트 근무자는 승인 버튼 숨김 (지원 후 블랙리스트 등록된 경우 방어)
          if (isPending && widget.showApprovalButtons && widget.application != null &&
              !widget.user.isBlacklisted) ...[
            SizedBox(width: ResponsiveHelper.spacing(context, 8)),
            Expanded(
              child: _buildDialogButton(
                label: '거절',
                icon: Icons.cancel_outlined,
                bgColor: AppColors.errorBg,
                textColor: AppColors.error,
                onTap: () => _updateStatus(AppStatus.rejected),
              ),
            ),
            SizedBox(width: ResponsiveHelper.spacing(context, 8)),
            Expanded(
              child: _buildDialogButton(
                label: '승인',
                icon: Icons.check_circle_outline,
                bgColor: AppColors.successBg,
                textColor: AppColors.successDark,
                onTap: () => _updateStatus(AppStatus.confirmed),
              ),
            ),
          ] else if (isPending && widget.showApprovalButtons && widget.application != null &&
              widget.user.isBlacklisted) ...[
            // 블랙리스트 경고 배너 (거절만 허용)
            SizedBox(width: ResponsiveHelper.spacing(context, 8)),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: EdgeInsets.symmetric(
                        horizontal: ResponsiveHelper.spacing(context, 8),
                        vertical: ResponsiveHelper.spacing(context, 4)),
                    decoration: BoxDecoration(
                      color: AppColors.errorBg,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.block, color: AppColors.error, size: 14),
                        SizedBox(width: ResponsiveHelper.spacing(context, 4)),
                        Text('이용 제한 근무자',
                            style: ResponsiveHelper.smallStyle(context,
                                color: AppColors.error, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                  SizedBox(height: ResponsiveHelper.spacing(context, 4)),
                  _buildDialogButton(
                    label: '거절',
                    icon: Icons.cancel_outlined,
                    bgColor: AppColors.errorBg,
                    textColor: AppColors.error,
                    onTap: () => _updateStatus(AppStatus.rejected),
                  ),
                ],
              ),
            ),
          ],

          // 리뷰 버튼 (확정자 + businessId 있을 때)
          if (isConfirmed && widget.application != null && widget.businessId != null) ...[
            SizedBox(width: ResponsiveHelper.spacing(context, 8)),
            Expanded(
              child: _buildDialogButton(
                label: _hasWrittenReview == true ? '리뷰 확인' : '리뷰 작성',
                icon: _hasWrittenReview == true
                    ? Icons.rate_review
                    : Icons.rate_review_outlined,
                bgColor: _hasWrittenReview == true
                    ? AppColors.successBg
                    : primary.withValues(alpha: 0.08),
                textColor: _hasWrittenReview == true
                    ? AppColors.successDark
                    : primary,
                onTap: _openReviewDialog,
              ),
            ),
          ],

          // 확정자 액션 버튼
          if (isConfirmed && widget.application != null) ...[
            SizedBox(width: ResponsiveHelper.spacing(context, 8)),

            // 장기 + 로딩 중
            if (_isLoading && isLongTerm) ...[
              Expanded(
                child: Container(
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppColors.grey100,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Center(
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.grey400),
                    ),
                  ),
                ),
              ),
            // 장기 + 출퇴근 있음: 고정근무 관리
            ] else if (isLongTerm && _hasAttendance) ...[
              Expanded(
                child: _buildDialogButton(
                  label: '고정근무 관리',
                  icon: Icons.settings_outlined,
                  bgColor: AppColors.longTermDark,
                  textColor: Colors.white,
                  onTap: _openFixedWorkerManagement,
                ),
              ),
            // 장기 + 출퇴근 없음 OR 단기: 확정취소
            ] else ...[
              Expanded(
                child: Builder(
                  builder: (context) {
                    final canCancel = widget.attendanceStatus == null ||
                                      widget.attendanceStatus == 'pending';
                    return _buildDialogButton(
                      label: '확정취소',
                      icon: Icons.cancel_outlined,
                      bgColor: canCancel ? AppColors.errorBg : AppColors.grey100,
                      textColor: canCancel ? AppColors.error : AppColors.grey400,
                      onTap: () {
                        if (canCancel) {
                          _cancelConfirmation();
                        } else {
                          ToastHelper.showWarning('확정취소는 미출근 상태일 때만 가능합니다');
                        }
                      },
                    );
                  },
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
      if (mounted) ToastHelper.showInfo('전화: $phone');
    }
  }

  /// 상태 업데이트
  Future<void> _updateStatus(String newStatus) async {
    if (widget.application == null || _isLoading) return;

    final actionText = newStatus == AppStatus.confirmed ? '승인' : '거절';
    final adminUID = context.read<UserProvider>().currentUser?.uid;
    String? rejectReason;

    if (newStatus == AppStatus.confirmed) {
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

      if (confirm != true || !mounted) return;
    } else {
      // 거절 - 사유 선택
      rejectReason = await DialogHelper.showRejectReasonPicker(
        context,
        title: '지원자 거절',
        targetName: widget.user.name,
      );

      if (rejectReason == null) return;
    }

    if (!mounted || _isLoading) return;
    setState(() => _isLoading = true);
    try {
      await _firestoreService.updateApplicationStatus(
        applicationId: widget.application!.id,
        status: newStatus,
        confirmedBy: newStatus == AppStatus.confirmed ? adminUID : null,
        rejectedBy: newStatus == AppStatus.rejected ? adminUID : null,
        message: rejectReason,
      );

      if (mounted) {
        if (newStatus == AppStatus.confirmed) {
          await _createContractAndSign();
        } else {
          Navigator.pop(context);
          ToastHelper.showSuccess('$actionText 처리되었습니다');
          widget.onStatusChanged?.call();
        }
      }
    } catch (e) {
      debugPrint('❌ 상태 업데이트 실패: $e');
      if (mounted) {
        setState(() => _isLoading = false);
        ToastHelper.showError('$actionText 처리 중 오류가 발생했습니다');
      }
    }
  }

  Future<void> _createContractAndSign() async {
    final app = widget.application!;
    final businessId = widget.businessId ?? widget.toItem?.to.businessId;

    if (businessId == null) {
      final callback = widget.onStatusChanged; // pop 전에 캡처
      Navigator.pop(context);
      ToastHelper.showSuccess('승인 처리되었습니다');
      callback?.call();
      return;
    }

    // 템플릿 선택 먼저 — 취소하면 계약 생성 중단
    if (!mounted) return;
    final articles = await ContractTemplateSelectorDialog.show(
      context,
      businessId: businessId,
    );
    if (articles == null || !mounted) return;

    setState(() => _isLoading = true);

    try {
    // 해당 지원서에 맞는 WorkDetailData 찾기
    // toItem이 없을 때는 app.toId로 Firestore에서 직접 조회
    List<WorkDetailData> workDetails;
    if (widget.toItem != null) {
      workDetails = widget.toItem!.workDetails;
      if (workDetails.isEmpty) {
        workDetails = await _firestoreService.getWorkDetails(widget.toItem!.to.id);
      }
    } else {
      final toId = app.toId ?? '';
      workDetails = toId.isNotEmpty
          ? await _firestoreService.getWorkDetails(toId)
          : [];
    }

    if (!mounted) return;

    if (workDetails.isEmpty) {
      setState(() => _isLoading = false);
      ToastHelper.showError('업무 정보를 불러올 수 없습니다');
      return;
    }

    WorkDetailData workDetail;
    if (app.workDetailId?.isNotEmpty == true) {
      workDetail = workDetails.firstWhere(
        (w) => w.id == app.workDetailId || w.legacyId == app.workDetailId,
        orElse: () => workDetails.firstWhere(
          (w) => w.workType == app.selectedWorkType,
          orElse: () => workDetails.first,
        ),
      );
    } else {
      workDetail = workDetails.firstWhere(
        (w) => w.workType == app.selectedWorkType,
        orElse: () => workDetails.first,
      );
    }

      final business = await _firestoreService.getBusinessById(businessId);
      if (!mounted) return;

      if (business == null) {
        final callback = widget.onStatusChanged; // pop 전에 캡처
        Navigator.pop(context);
        ToastHelper.showSuccess('승인 처리되었습니다');
        callback?.call();
        return;
      }

      // [BUG-수정 M-1] updateApplicationStatus 완료 후 Firestore에는 computedWorkEndDate가
      // 저장되지만 로컬 app 객체는 구버전이라 workEndDate가 null일 수 있음.
      // 서버에서 최신 데이터를 재조회해 contractEnd 공백 발급 버그를 방지.
      final freshAppDoc = await FirebaseFirestore.instance
          .collection('applications')
          .doc(app.id)
          .get(const GetOptions(source: Source.server));
      // 승인 처리 직후 문서가 삭제된 경쟁 상태 방어 (catch(e)로 에러 토스트 처리됨)
      if (!freshAppDoc.exists) throw Exception('지원서를 찾을 수 없습니다');
      // [CRASH-GUARD] tryFromMap — 손상된 Firestore 문서에서 크래시 방지
      final freshApp = ApplicationModel.tryFromMap(freshAppDoc.data()!, freshAppDoc.id);
      if (freshApp == null) throw Exception('지원서 데이터가 손상되었습니다');

      // findOrCreateContract: 기존 번들 계약서가 있으면 슬롯 추가,
      // 없으면 신규 생성. 중복 방지 + 단기 번들링 처리.
      final contract = await ContractService().findOrCreateContract(
        application: freshApp,
        business: business,
        worker: widget.user,
        workDetail: workDetail,
        articles: articles,
      );

      if (!mounted) return;

      // 항상 서명 화면으로 이동 — 사업주가 계약서 내용 확인 후 직접 날인
      final nav = Navigator.of(context, rootNavigator: true);
      final callback = widget.onStatusChanged; // pop 전에 캡처
      Navigator.pop(context);
      callback?.call();
      await nav.push(MaterialPageRoute(
        builder: (_) => ContractSignScreen(contract: contract, role: 'employer'),
      ));
    } catch (e) {
      debugPrint('❌ 계약서 생성 실패: $e');
      if (mounted) {
        final callback = widget.onStatusChanged; // pop 전에 캡처
        Navigator.pop(context);
        ToastHelper.showSuccess('승인 처리되었습니다');
        callback?.call();
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
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

    if (!mounted) return;

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
  
  /// 확정 취소 (CONFIRMED / CONTRACT_PENDING 모두 처리)
  Future<void> _cancelConfirmation() async {
    if (widget.application == null) return;
    if (_isLoading) return; // 중복 실행 방어
    // [BUG-FIX 2026-07-16] _isLoading 설정 누락 — _showCancelReasonPicker() await 중 재진입 가능
    setState(() => _isLoading = true);

    final adminUID = context.read<UserProvider>().currentUser?.uid;

    final cancelReason = await _showCancelReasonPicker();
    if (cancelReason == null || !mounted) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    try {
      final success = await _firestoreService.cancelConfirmedApplication(
        widget.application!.id,
        applyNoShowPenalty: false,
        canceledBy: adminUID,
        cancelReason: cancelReason,
      );

      if (mounted && success) {
        Navigator.pop(context, true);
        ToastHelper.showSuccess('확정이 취소되었습니다');
        widget.onStatusChanged?.call();
      }
    } catch (e) {
      debugPrint('❌ 확정 취소 실패: $e');
      if (mounted) {
        ToastHelper.showError('확정 취소 중 오류가 발생했습니다');
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// 확정취소 사유 선택 다이얼로그
  Future<String?> _showCancelReasonPicker() async {
    String? selectedReason;
    final customReasonController = TextEditingController();
    // ignore: unawaited_futures — result awaited below; controller disposed after

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
            insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
            child: Container(
              width: double.maxFinite,
              constraints: const BoxConstraints(maxWidth: 400),
              child: SingleChildScrollView(
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
                                style: ResponsiveHelper.smallStyle(context, color: Colors.white.withValues(alpha: 0.7)),
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
            ),
          );
        },
      ),
    );
    customReasonController.dispose();
    return result;
  }

  /// 🆕 리뷰 작성 다이얼로그 열기
  Future<void> _openReviewDialog() async {
    final app = widget.application;
    if (app == null || widget.businessId == null) return;

    final reviewer = context.read<UserProvider>().currentUser;
    if (reviewer == null) return;

    final now = DateTime.now();
    final workDays = _businessHistory?['totalDays'] ?? 1;

    // 리뷰 기준 월: 단기는 실제 근무일, 장기는 직전 완료 달
    int reviewYear;
    int reviewMonth;
    if (app.isLongTermApplication) {
      // 장기: 당월 5일 이전이면 전달, 이후면 이번달
      if (now.month == 1) {
        reviewYear = now.year - 1;
        reviewMonth = 12;
      } else {
        reviewYear = now.year;
        reviewMonth = now.day < 5 ? now.month - 1 : now.month;
      }
    } else {
      reviewYear = app.workDate.year;
      reviewMonth = app.workDate.month;
    }

    final requestKey = ReviewRequestModel.generateKey(
      businessId: widget.businessId!,
      workerId: widget.user.uid,
      year: reviewYear,
      month: reviewMonth,
    );
    final reviewRequest =
        await MonthlyReviewService().getReviewRequest(requestKey);

    // review_request가 있으면 해당 년/월로 보정 (CF 기준이 정확)
    if (reviewRequest != null) {
      reviewYear = reviewRequest.reviewYear;
      reviewMonth = reviewRequest.reviewMonth;
    }

    if (!mounted) return;

    // 기작성 리뷰 확인: monthly_reviews 직접 조회 (review_requests.adminStatus 갱신 여부 무관)
    final reviewKey = MonthlyReviewModel.generateKeyForUser(
      businessId: widget.businessId!,
      targetUserId: widget.user.uid,
      year: reviewYear,
      month: reviewMonth,
    );
    final existingReview =
        await MonthlyReviewService().getReviewById(reviewKey);
    if (!mounted) return;

    if (existingReview != null) {
      await showMonthlyReviewViewDialog(context, review: existingReview);
      return;
    }

    final result = await showMonthlyReviewDialog(
      context,
      reviewerId: reviewer.uid,
      reviewerName: reviewer.name,
      businessId: widget.businessId!,
      businessName: widget.toItem?.to.businessName ?? '',
      targetUserId: widget.user.uid,
      targetUserName: widget.user.name,
      reviewYear: reviewYear,
      reviewMonth: reviewMonth,
      workDaysInMonth: workDays,
      normalAttendanceDays: workDays,
      lateDays: 0,
      requestId: reviewRequest?.id,
    );

    if (result == true && mounted) {
      setState(() {
        _hasChanges = true;
        _hasWrittenReview = true;
      });
      widget.onStatusChanged?.call();
    }
  }

  /// 고정근무 관리 다이얼로그 열기
  void _openFixedWorkerManagement() {
    final businessId = widget.businessId ?? widget.application?.businessId;
    
    if (businessId == null) {
      ToastHelper.showError('사업장 정보를 찾을 수 없습니다');
      return;
    }

    // 루트 Navigator context를 팝 이전에 캡처 (pop 이후 context는 unmount됨)
    final rootNav = Navigator.of(context, rootNavigator: true);
    final onStatusChanged = widget.onStatusChanged;
    Navigator.pop(context);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      showDialog(
        context: rootNav.context,
        builder: (context) => FixedWorkerManagementDialog(
          businessIds: [businessId],
          initialBusinessId: businessId,
          onChanged: () {
            onStatusChanged?.call();
          },
        ),
      );
    });
  }
}