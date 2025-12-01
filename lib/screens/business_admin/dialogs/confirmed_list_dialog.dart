// lib/screens/business_admin/dialogs/confirmed_list_dialog.dart
// PART 1: 메인 클래스, import, 목록 UI

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../models/core/work_detail_model.dart';
import '../../../models/core/application_model.dart';
import '../../../models/core/user_model.dart';
import '../../../models/core/review_model.dart';
import '../../../models/core/id_card_access_request_model.dart';
import '../../../providers/user_provider.dart';
import '../../../services/firestore_service.dart';
import '../../../utils/format_helper.dart';
import '../../../utils/responsive_helper.dart';
import '../../../utils/toast_helper.dart';
import '../../../widgets/work_type_icon.dart';
import '../../../widgets/dialogs/styled_dialog.dart';
import '../../../models/ui/admin_to_list_ui_models.dart';
import '../../../theme/app_colors.dart';

class ConfirmedListDialog {
  final BuildContext context;
  final TOItem toItem;
  final FirestoreService firestoreService;

  ConfirmedListDialog({
    required this.context,
    required this.toItem,
    required this.firestoreService,
  });

  void show() {
    showDialog(
      context: context,
      builder: (context) => _ConfirmedListDialogWidget(
        toItem: toItem,
        firestoreService: firestoreService,
      ),
    );
  }
}

class _ConfirmedListDialogWidget extends StatefulWidget {
  final TOItem toItem;
  final FirestoreService firestoreService;

  const _ConfirmedListDialogWidget({
    required this.toItem,
    required this.firestoreService,
  });

  @override
  State<_ConfirmedListDialogWidget> createState() =>
      _ConfirmedListDialogWidgetState();
}

class _ConfirmedListDialogWidgetState
    extends State<_ConfirmedListDialogWidget> {
  bool _isLoading = true;
  Map<String, List<Map<String, dynamic>>> _confirmedByWork = {};
  String? _error;
  int _totalConfirmed = 0;
  Map<String, String> _idCardStatusMap = {}; // userId -> 상태 (none, pending, approved)

  @override
  void initState() {
    super.initState();
    _loadConfirmedApplicants();
  }

  Future<void> _loadConfirmedApplicants() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final userProvider = context.read<UserProvider>();
      final currentUserId = userProvider.currentUser?.uid ?? '';

      final applications = await widget.firestoreService.getApplicationsByTO(
        widget.toItem.to.businessId,
        widget.toItem.to.title,
        widget.toItem.to.date,
      );

      final confirmed =
          applications.where((app) => app.status == 'CONFIRMED').toList();

      final futures = confirmed.map((app) async {
        final user = await widget.firestoreService.getUser(app.uid);
        return {
          'application': app,
          'user': user,
          'workType': app.selectedWorkType,
        };
      }).toList();

      final results = await Future.wait(futures);

      final Map<String, List<Map<String, dynamic>>> groupedByWork = {};

      for (var result in results) {
        if (result['user'] != null) {
          final workType = result['workType'] as String;
          groupedByWork.putIfAbsent(workType, () => []);
          groupedByWork[workType]!.add(result);
        }
      }

      // ✅ 신분증 요청 상태 일괄 조회
      final userIds = results
          .where((r) => r['user'] != null)
          .map((r) => (r['user'] as UserModel).uid)
          .toList();
      
      final idCardStatusMap = await _loadIdCardStatusBatch(currentUserId, userIds);

      setState(() {
        _confirmedByWork = groupedByWork;
        _totalConfirmed = confirmed.length;
        _idCardStatusMap = idCardStatusMap;
        _isLoading = false;
      });
    } catch (e) {
      print('❌ 확정 명단 로드 실패: $e');
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  /// 신분증 요청 상태 일괄 조회
  Future<Map<String, String>> _loadIdCardStatusBatch(String requesterId, List<String> targetUserIds) async {
    final Map<String, String> statusMap = {};
    
    try {
      for (final userId in targetUserIds) {
        final access = await widget.firestoreService.checkIdCardAccess(
          requesterId: requesterId,
          targetUserId: userId,
        );
        
        if (access == null) {
          statusMap[userId] = 'none'; // 미요청
        } else if (access.status == IdCardAccessStatus.pending) {
          statusMap[userId] = 'pending'; // 요청중
        } else if (access.isValidAccess) {
          statusMap[userId] = 'approved'; // 승인됨
        } else {
          statusMap[userId] = 'none'; // 만료/거절 → 재요청 가능
        }
      }
    } catch (e) {
      print('⚠️ 신분증 상태 조회 실패: $e');
    }
    
    return statusMap;
  }

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('MM/dd (E)', 'ko_KR');

    return StyledDialog(
      title: '확정 명단',
      subtitle:
          '${dateFormat.format(widget.toItem.to.date)} · ${widget.toItem.to.title}',
      icon: Icons.check_circle,
      headerColor: AppColors.success,
      maxHeightRatio: 0.85,
      content: _buildContent(),
      actions: [
        StyledDialogButton.cancel(
          text: '닫기',
          onPressed: () => Navigator.pop(context),
        ),
      ],
    );
  }

  Widget _buildContent() {
    if (_isLoading) {
      return SizedBox(
        height: ResponsiveHelper.spacing(context, 200),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(AppColors.success),
              ),
              SizedBox(height: ResponsiveHelper.spacing(context, 16)),
              Text(
                '확정 명단 불러오는 중...',
                style: ResponsiveHelper.bodyStyle(context, color: AppColors.grey600),
              ),
            ],
          ),
        ),
      );
    }

    if (_error != null) {
      return SizedBox(
        height: ResponsiveHelper.spacing(context, 200),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, size: ResponsiveHelper.iconSize(context, 48), color: AppColors.error),
              SizedBox(height: ResponsiveHelper.spacing(context, 12)),
              Text('데이터를 불러올 수 없습니다', style: ResponsiveHelper.bodyStyle(context)),
            ],
          ),
        ),
      );
    }

    if (_confirmedByWork.isEmpty) {
      return SizedBox(
        height: ResponsiveHelper.spacing(context, 200),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.people_outline, size: ResponsiveHelper.iconSize(context, 48), color: AppColors.grey400),
              SizedBox(height: ResponsiveHelper.spacing(context, 12)),
              Text('확정된 근무자가 없습니다', style: ResponsiveHelper.bodyStyle(context, color: AppColors.grey600)),
            ],
          ),
        ),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildTotalStats(),
        SizedBox(height: ResponsiveHelper.spacing(context, 16)),
        ..._confirmedByWork.entries.map((entry) {
          final workType = entry.key;
          final workers = entry.value;
          final workDetail = widget.toItem.workDetails.firstWhere(
            (w) => w.workType == workType,
            orElse: () => widget.toItem.workDetails.first,
          );
          return _buildWorkSection(workType, workers, workDetail);
        }),
      ],
    );
  }

  Widget _buildTotalStats() {
    return Container(
      padding: ResponsiveHelper.cardPadding(context),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.success.withOpacity(0.1), AppColors.success.withOpacity(0.05)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.success.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Container(
            padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 12)),
            decoration: BoxDecoration(color: AppColors.success, borderRadius: BorderRadius.circular(12)),
            child: Icon(Icons.people, color: Colors.white, size: ResponsiveHelper.iconSize(context, 24)),
          ),
          SizedBox(width: ResponsiveHelper.spacing(context, 12)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('총 확정 인원', style: ResponsiveHelper.smallStyle(context, color: AppColors.grey600)),
                Text('$_totalConfirmed명', style: ResponsiveHelper.titleStyle(context).copyWith(fontWeight: FontWeight.bold, color: AppColors.success)),
              ],
            ),
          ),
          Container(
            padding: EdgeInsets.symmetric(horizontal: ResponsiveHelper.spacing(context, 12), vertical: ResponsiveHelper.spacing(context, 6)),
            decoration: BoxDecoration(color: AppColors.success, borderRadius: BorderRadius.circular(20)),
            child: Text('${_confirmedByWork.length}개 업무', style: ResponsiveHelper.smallStyle(context, color: Colors.white).copyWith(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildWorkSection(String workType, List<Map<String, dynamic>> workers, WorkDetailModel workDetail) {
    return Container(
      margin: EdgeInsets.only(bottom: ResponsiveHelper.spacing(context, 16)),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(
        children: [
          Container(
            padding: ResponsiveHelper.cardPadding(context),
            decoration: BoxDecoration(
              color: AppColors.grey50,
              borderRadius: const BorderRadius.only(topLeft: Radius.circular(16), topRight: Radius.circular(16)),
            ),
            child: Row(
              children: [
                WorkTypeIcon.buildWithBackground(iconString: workDetail.workTypeIcon, backgroundColor: workDetail.workTypeBackgroundColor, size: ResponsiveHelper.iconSize(context, 32)),
                SizedBox(width: ResponsiveHelper.spacing(context, 12)),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(workType, style: ResponsiveHelper.subtitleStyle(context).copyWith(fontWeight: FontWeight.bold)),
                      Text('${workDetail.startTime} ~ ${workDetail.endTime}', style: ResponsiveHelper.smallStyle(context, color: AppColors.grey600)),
                    ],
                  ),
                ),
                Container(
                  padding: EdgeInsets.symmetric(horizontal: ResponsiveHelper.spacing(context, 10), vertical: ResponsiveHelper.spacing(context, 4)),
                  decoration: BoxDecoration(color: AppColors.success.withOpacity(0.15), borderRadius: BorderRadius.circular(12)),
                  child: Text('${workers.length}명', style: ResponsiveHelper.bodyStyle(context, color: AppColors.success).copyWith(fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),
          ...(() {
            final sortedWorkers = List<Map<String, dynamic>>.from(workers);
            sortedWorkers.sort((a, b) {
              final userA = a['user'] as UserModel;
              final userB = b['user'] as UserModel;
              
              // 1. 성별 정렬 (남성 먼저)
              final genderOrder = {'남성': 0, '여성': 1};
              final genderA = genderOrder[userA.gender] ?? 2;
              final genderB = genderOrder[userB.gender] ?? 2;
              
              if (genderA != genderB) {
                return genderA.compareTo(genderB);
              }
              
              // 2. 나이순 정렬 (어린순)
              final ageA = userA.age ?? 999;
              final ageB = userB.age ?? 999;
              return ageA.compareTo(ageB);
            });
            
            return sortedWorkers.asMap().entries.map((entry) {
              final index = entry.key;
              final worker = entry.value;
            final user = worker['user'] as UserModel;
            final application = worker['application'] as ApplicationModel;
            final isLast = index == workers.length - 1;
            final idCardStatus = _idCardStatusMap[user.uid] ?? 'none';

            return Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => _showWorkerDetailDialog(context, user, application, workDetail),
                borderRadius: isLast ? const BorderRadius.only(bottomLeft: Radius.circular(16), bottomRight: Radius.circular(16)) : null,
                child: Container(
                  padding: ResponsiveHelper.cardPadding(context),
                  decoration: BoxDecoration(border: isLast ? null : Border(bottom: BorderSide(color: AppColors.border))),
                  child: Row(
                    children: [
                      // ✅ 순번 숫자로 변경
                      CircleAvatar(
                        radius: ResponsiveHelper.spacing(context, 20),
                        backgroundColor: AppColors.info.withOpacity(0.1),
                        child: Text(
                          '${index + 1}',
                          style: ResponsiveHelper.subtitleStyle(context).copyWith(
                            fontWeight: FontWeight.bold,
                            color: AppColors.info,
                          ),
                        ),
                      ),
                      SizedBox(width: ResponsiveHelper.spacing(context, 12)),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // ✅ 이름 + 성별 · 나이
                            Row(
                              children: [
                                Text(user.name, style: ResponsiveHelper.bodyStyle(context).copyWith(fontWeight: FontWeight.w600)),
                                SizedBox(width: ResponsiveHelper.spacing(context, 6)),
                                Text(
                                  '${user.gender ?? ''}${user.age != null ? ' · ${user.age}세' : ''}',
                                  style: ResponsiveHelper.smallStyle(context, color: AppColors.grey500),
                                ),
                                const Spacer(),
                                Icon(Icons.chevron_right, size: ResponsiveHelper.iconSize(context, 16), color: AppColors.grey400),
                              ],
                            ),
                            SizedBox(height: ResponsiveHelper.spacing(context, 4)),
                            // ✅ 신뢰도 + 평점 + 신분증 상태
                            Row(
                              children: [
                                _buildTrustBadge(user),
                                SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                                if (user.averageRating > 0) ...[
                                  Icon(Icons.star, size: ResponsiveHelper.iconSize(context, 12), color: Colors.amber),
                                  SizedBox(width: ResponsiveHelper.spacing(context, 2)),
                                  Text(user.averageRating.toStringAsFixed(1), style: ResponsiveHelper.smallStyle(context, color: AppColors.grey600)),
                                  SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                                ],
                                _buildIdCardStatusBadge(idCardStatus),
                              ],
                            ),
                          ],
                        ),
                      ),
                      if (user.phone != null)
                        IconButton(
                          onPressed: () => _makePhoneCall(user.phone!),
                          icon: Icon(Icons.phone, color: AppColors.info, size: ResponsiveHelper.iconSize(context, 20)),
                          tooltip: '전화 걸기',
                        ),
                    ],
                  ),
                ),
              ),
            );
          });
          })(),
        ],
      ),
    );
  }
  

  Widget _buildTrustBadge(UserModel user) {
    final trustScore = _calculateTrustScore(user);
    Color badgeColor;
    if (trustScore >= 80) {
      badgeColor = AppColors.success;
    } else if (trustScore >= 60) {
      badgeColor = AppColors.info;
    } else if (trustScore >= 40) {
      badgeColor = AppColors.warning;
    } else {
      badgeColor = AppColors.error;
    }
    return Container(
      padding: EdgeInsets.symmetric(horizontal: ResponsiveHelper.spacing(context, 6), vertical: ResponsiveHelper.spacing(context, 2)),
      decoration: BoxDecoration(color: badgeColor.withOpacity(0.15), borderRadius: BorderRadius.circular(8)),
      child: Text('신뢰 $trustScore', style: ResponsiveHelper.tinyStyle(context, color: badgeColor).copyWith(fontWeight: FontWeight.bold)),
    );
  }
  

  int _calculateTrustScore(UserModel user) {
    int score = 60;
    score += (user.averageRating * 4).toInt();
    score += (user.totalWorkDays / 10).clamp(0, 15).toInt();
    score -= user.noShowCount * 5;
    score -= user.lateCount * 2;
    return score.clamp(0, 100);
  }

  Future<void> _makePhoneCall(String phoneNumber) async {
    final uri = Uri.parse('tel:$phoneNumber');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      ToastHelper.showError('전화를 걸 수 없습니다');
    }
  }
  /// 신분증 상태 배지
  Widget _buildIdCardStatusBadge(String status) {
    IconData icon;
    String label;
    Color color;
    
    switch (status) {
      case 'approved':
        icon = Icons.verified;
        label = '신분증';
        color = AppColors.success;
        break;
      case 'pending':
        icon = Icons.hourglass_top;
        label = '요청중';
        color = AppColors.warning;
        break;
      case 'none':
      default:
        icon = Icons.lock_outline;
        label = '미요청';
        color = AppColors.grey400;
        break;
    }
    
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 6),
        vertical: ResponsiveHelper.spacing(context, 2),
      ),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: ResponsiveHelper.iconSize(context, 10), color: color),
          SizedBox(width: ResponsiveHelper.spacing(context, 3)),
          Text(
            label,
            style: ResponsiveHelper.tinyStyle(context, color: color).copyWith(fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  void _showWorkerDetailDialog(BuildContext context, UserModel user, ApplicationModel application, WorkDetailModel workDetail) {
    showDialog(
      context: context,
      builder: (dialogContext) => _WorkerDetailDialog(
        user: user,
        application: application,
        workDetail: workDetail,
        businessId: widget.toItem.to.businessId,
        firestoreService: widget.firestoreService,
      ),
    );
  }
}

// PART 2: _WorkerDetailDialog 클래스
// 이 내용을 PART 1 아래에 붙여넣기 하세요

class _WorkerDetailDialog extends StatefulWidget {
  final UserModel user;
  final ApplicationModel application;
  final WorkDetailModel workDetail;
  final String businessId;
  final FirestoreService firestoreService;

  const _WorkerDetailDialog({
    required this.user,
    required this.application,
    required this.workDetail,
    required this.businessId,
    required this.firestoreService,
  });

  @override
  State<_WorkerDetailDialog> createState() => _WorkerDetailDialogState();
}

class _WorkerDetailDialogState extends State<_WorkerDetailDialog> {
  bool _isLoadingHistory = true;
  bool _isLoadingIdCardAccess = true;
  Map<String, dynamic>? _businessHistory;
  IdCardAccessRequestModel? _idCardAccess;
  List<ReviewModel> _reviews = [];

  @override
  void initState() {
    super.initState();
    _loadBusinessHistory();
    _checkIdCardAccess();
  }

  Future<void> _loadBusinessHistory() async {
    try {
      final history = await widget.firestoreService.getBusinessWorkHistory(
        userId: widget.user.uid,
        businessId: widget.businessId,
      );
      if (mounted) {
        setState(() {
          _businessHistory = history;
          _reviews = (history['reviews'] as List<ReviewModel>?) ?? [];
          _isLoadingHistory = false;
        });
      }
    } catch (e) {
      print('❌ 사업장 이력 로드 실패: $e');
      if (mounted) setState(() => _isLoadingHistory = false);
    }
  }

  Future<void> _checkIdCardAccess() async {
    try {
      final userProvider = context.read<UserProvider>();
      final currentUser = userProvider.currentUser;
      if (currentUser == null) {
        setState(() => _isLoadingIdCardAccess = false);
        return;
      }
      final access = await widget.firestoreService.checkIdCardAccess(
        requesterId: currentUser.uid,
        targetUserId: widget.user.uid,
      );
      if (mounted) {
        setState(() {
          _idCardAccess = access;
          _isLoadingIdCardAccess = false;
        });
      }
    } catch (e) {
      print('❌ 신분증 열람 권한 확인 실패: $e');
      if (mounted) setState(() => _isLoadingIdCardAccess = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final trustScore = _calculateTrustScore(widget.user);
    return StyledDialog(
      title: '근무자 상세정보',
      subtitle: widget.user.name,
      icon: Icons.person,
      headerColor: AppColors.info,
      maxHeightRatio: 0.9,
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildBasicInfoSection(trustScore),
            SizedBox(height: ResponsiveHelper.spacing(context, 16)),
            _buildStatsRow(),
            SizedBox(height: ResponsiveHelper.spacing(context, 16)),
            _buildBusinessHistorySection(),
            SizedBox(height: ResponsiveHelper.spacing(context, 16)),
            if (_reviews.isNotEmpty) ...[
              _buildReviewsSection(),
              SizedBox(height: ResponsiveHelper.spacing(context, 16)),
            ],
            _buildPaymentInfoSection(),
            SizedBox(height: ResponsiveHelper.spacing(context, 16)),
            _buildIdCardSection(),
          ],
        ),
      ),
      actions: [
        if (widget.user.phone != null)
          StyledDialogButton.primary(
            text: '전화 걸기',
            
            backgroundColor: AppColors.success,
            onPressed: () => _makePhoneCall(widget.user.phone!),
          ),
        StyledDialogButton.cancel(text: '닫기', onPressed: () => Navigator.pop(context)),
      ],
    );
  }

  Widget _buildBasicInfoSection(int trustScore) {
    final user = widget.user;
    Color trustColor;
    if (trustScore >= 80) {
      trustColor = AppColors.success;
    } else if (trustScore >= 60) {
      trustColor = AppColors.info;
    } else if (trustScore >= 40) {
      trustColor = AppColors.warning;
    } else {
      trustColor = AppColors.error;
    }

    return Container(
      padding: ResponsiveHelper.cardPadding(context),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: ResponsiveHelper.spacing(context, 28),
                backgroundColor: AppColors.grey100,
                backgroundImage: user.profileImageUrl != null ? NetworkImage(user.profileImageUrl!) : null,
                child: user.profileImageUrl == null
                    ? Text(user.name.isNotEmpty ? user.name[0] : '?', style: ResponsiveHelper.titleStyle(context).copyWith(fontWeight: FontWeight.bold, color: AppColors.grey600))
                    : null,
              ),
              SizedBox(width: ResponsiveHelper.spacing(context, 16)),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(user.name, style: ResponsiveHelper.titleStyle(context).copyWith(fontWeight: FontWeight.bold)),
                    SizedBox(height: ResponsiveHelper.spacing(context, 4)),
                    Text('${user.gender ?? ''} ${user.age != null ? '· ${user.age}세' : ''}', style: ResponsiveHelper.bodyStyle(context, color: AppColors.grey600)),
                  ],
                ),
              ),
              Container(
                padding: EdgeInsets.symmetric(horizontal: ResponsiveHelper.spacing(context, 12), vertical: ResponsiveHelper.spacing(context, 8)),
                decoration: BoxDecoration(
                  color: trustColor.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: trustColor.withOpacity(0.3)),
                ),
                child: Column(
                  children: [
                    Text('신뢰도', style: ResponsiveHelper.tinyStyle(context, color: trustColor)),
                    Text('$trustScore점', style: ResponsiveHelper.subtitleStyle(context).copyWith(fontWeight: FontWeight.bold, color: trustColor)),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 12)),
          Divider(color: AppColors.border),
          SizedBox(height: ResponsiveHelper.spacing(context, 12)),
          Row(
            children: [
              Icon(Icons.phone, size: ResponsiveHelper.iconSize(context, 16), color: AppColors.grey500),
              SizedBox(width: ResponsiveHelper.spacing(context, 8)),
              Text(FormatHelper.formatPhone(user.phone ?? '-'), style: ResponsiveHelper.bodyStyle(context)),
            ],
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 8)),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.location_on, size: ResponsiveHelper.iconSize(context, 16), color: AppColors.grey500),
              SizedBox(width: ResponsiveHelper.spacing(context, 8)),
              Expanded(
                child: Text(
                  user.address != null ? '${user.address}${user.detailAddress != null ? ' ${user.detailAddress}' : ''}' : '-',
                  style: ResponsiveHelper.bodyStyle(context),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatsRow() {
    final user = widget.user;
    return Container(
      padding: ResponsiveHelper.cardPadding(context),
      decoration: BoxDecoration(color: AppColors.grey50, borderRadius: BorderRadius.circular(12)),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildStatItem(icon: Icons.calendar_today, label: '총 근무', value: '${user.totalWorkDays}일', color: AppColors.info),
          _buildStatDivider(),
          _buildStatItem(icon: Icons.star, label: '평균 평점', value: user.averageRating.toStringAsFixed(1), color: Colors.amber),
          _buildStatDivider(),
          _buildStatItem(icon: Icons.cancel, label: '무단결근', value: '${user.noShowCount}회', color: user.noShowCount > 0 ? AppColors.error : AppColors.grey500),
          _buildStatDivider(),
          _buildStatItem(icon: Icons.schedule, label: '지각', value: '${user.lateCount}회', color: user.lateCount > 0 ? AppColors.warning : AppColors.grey500),
        ],
      ),
    );
  }

  Widget _buildStatItem({required IconData icon, required String label, required String value, required Color color}) {
    return Column(
      children: [
        Icon(icon, size: ResponsiveHelper.iconSize(context, 18), color: color),
        SizedBox(height: ResponsiveHelper.spacing(context, 4)),
        Text(value, style: ResponsiveHelper.bodyStyle(context).copyWith(fontWeight: FontWeight.bold, color: color)),
        Text(label, style: ResponsiveHelper.tinyStyle(context, color: AppColors.grey500)),
      ],
    );
  }

  Widget _buildStatDivider() {
    return Container(height: ResponsiveHelper.spacing(context, 40), width: 1, color: AppColors.border);
  }

  Widget _buildBusinessHistorySection() {
    return _buildSection(
      title: '우리 사업장 이력',
      icon: Icons.business,
      child: _isLoadingHistory
          ? _buildLoadingIndicator()
          : _businessHistory == null || _businessHistory!['workCount'] == 0
              ? _buildEmptyMessage('이 사업장에서 근무한 이력이 없습니다')
              : Column(
                  children: [
                    _buildHistoryRow('근무 횟수', '${_businessHistory!['workCount']}회', Icons.repeat, AppColors.info),
                    if (_businessHistory!['lastWorkDate'] != null)
                      _buildHistoryRow('최근 근무', '${DateFormat('MM/dd').format(_businessHistory!['lastWorkDate'])} (${_businessHistory!['lastWorkType']})', Icons.history, AppColors.grey600),
                    if (_businessHistory!['averageRating'] != null)
                      _buildHistoryRow('평균 평점', '${(_businessHistory!['averageRating'] as double).toStringAsFixed(1)}점', Icons.star, Colors.amber),
                  ],
                ),
    );
  }

  Widget _buildHistoryRow(String label, String value, IconData icon, Color color) {
    return Padding(
      padding: EdgeInsets.only(bottom: ResponsiveHelper.spacing(context, 8)),
      child: Row(
        children: [
          Icon(icon, size: ResponsiveHelper.iconSize(context, 16), color: color),
          SizedBox(width: ResponsiveHelper.spacing(context, 8)),
          Text(label, style: ResponsiveHelper.bodyStyle(context, color: AppColors.grey600)),
          const Spacer(),
          Text(value, style: ResponsiveHelper.bodyStyle(context).copyWith(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _buildReviewsSection() {
    return _buildSection(
      title: '최근 리뷰',
      icon: Icons.rate_review,
      child: Column(
        children: _reviews.take(3).map((review) {
          return Container(
            margin: EdgeInsets.only(bottom: ResponsiveHelper.spacing(context, 8)),
            padding: ResponsiveHelper.cardPadding(context),
            decoration: BoxDecoration(color: AppColors.grey50, borderRadius: BorderRadius.circular(8)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    ...List.generate(5, (i) => Icon(i < review.rating ? Icons.star : Icons.star_border, size: ResponsiveHelper.iconSize(context, 14), color: Colors.amber)),
                    const Spacer(),
                    Text(DateFormat('MM/dd').format(review.workDate), style: ResponsiveHelper.tinyStyle(context, color: AppColors.grey500)),
                  ],
                ),
                if (review.comment != null && review.comment!.isNotEmpty) ...[
                  SizedBox(height: ResponsiveHelper.spacing(context, 4)),
                  Text(review.comment!, style: ResponsiveHelper.smallStyle(context), maxLines: 2, overflow: TextOverflow.ellipsis),
                ],
                SizedBox(height: ResponsiveHelper.spacing(context, 4)),
                Text('${review.businessName} · ${review.workType}', style: ResponsiveHelper.tinyStyle(context, color: AppColors.grey500)),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildPaymentInfoSection() {
    final user = widget.user;
    return _buildSection(
      title: '급여 정보',
      icon: Icons.account_balance,
      child: Column(
        children: [
          _buildInfoRow('은행', user.bankName ?? '-'),
          _buildInfoRow('계좌번호', user.accountNumber ?? '-'),
          _buildInfoRow('예금주', user.accountHolder ?? '-'),
        ],
      ),
    );
  }

// PART 3: 신분증 열람 섹션 및 헬퍼 메서드
// 이 내용을 PART 2 아래에 붙여넣기 하세요 (_WorkerDetailDialogState 클래스 내부)

  Widget _buildIdCardSection() {
    return _buildSection(
      title: '신분증',
      icon: Icons.badge,
      child: _isLoadingIdCardAccess ? _buildLoadingIndicator() : _buildIdCardContent(),
    );
  }

  Widget _buildIdCardContent() {
    // ✅ 승인된 상태
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
                      Text('열람 승인됨', style: ResponsiveHelper.bodyStyle(context).copyWith(fontWeight: FontWeight.bold, color: AppColors.successDark)),
                      Text('${_idCardAccess!.remainingDays}일 후 만료', style: ResponsiveHelper.smallStyle(context, color: AppColors.success)),
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
    
    // ✅ 요청중 상태
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
          crossAxisAlignment: CrossAxisAlignment.center,
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

    // ✅ 미요청 상태 (기존)
    return Container(
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
          Text('신분증 열람 권한이 없습니다', style: ResponsiveHelper.bodyStyle(context, color: AppColors.grey600)),
          SizedBox(height: ResponsiveHelper.spacing(context, 4)),
          Text('열람 요청 시 근무자의 승인이 필요합니다', style: ResponsiveHelper.smallStyle(context, color: AppColors.grey500), textAlign: TextAlign.center),
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
                // 안내 문구
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

  Future<void> _sendIdCardAccessRequest(BuildContext dialogContext, IdCardAccessReason reason, String customReason) async {
    Navigator.pop(dialogContext);
    try {
      final userProvider = context.read<UserProvider>();
      final currentUser = userProvider.currentUser;
      if (currentUser == null) {
        ToastHelper.showError('로그인이 필요합니다');
        return;
      }
      final business = await widget.firestoreService.getBusinessById(widget.businessId);
      await widget.firestoreService.createIdCardAccessRequest(
        requesterId: currentUser.uid,
        requesterName: currentUser.name,
        requesterBusinessId: widget.businessId,
        requesterBusinessName: business?.name ?? '',
        targetUserId: widget.user.uid,
        targetUserName: widget.user.name,
        reason: reason,
        customReason: reason == IdCardAccessReason.other ? customReason : null,
        applicationId: widget.application.id,
      );
      
      // ✅ 요청 성공 후 상태 업데이트
      ToastHelper.showSuccess('열람 요청을 보냈습니다');
      setState(() {
        _idCardAccess = IdCardAccessRequestModel(
          id: '',
          requesterId: currentUser.uid,
          requesterName: currentUser.name,
          requesterBusinessId: widget.businessId,
          requesterBusinessName: business?.name ?? '',
          targetUserId: widget.user.uid,
          targetUserName: widget.user.name,
          reason: reason,
          customReason: reason == IdCardAccessReason.other ? customReason : null,
          status: IdCardAccessStatus.pending,
          requestedAt: DateTime.now(),
          applicationId: widget.application.id,
        );
      });
      
    } catch (e) {
      print('❌ 신분증 열람 요청 실패: $e');
      ToastHelper.showError('요청 실패');
    }
  }

  Widget _buildSection({required String title, required IconData icon, required Widget child}) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: EdgeInsets.symmetric(horizontal: ResponsiveHelper.spacing(context, 16), vertical: ResponsiveHelper.spacing(context, 12)),
            decoration: BoxDecoration(
              color: AppColors.grey50,
              borderRadius: const BorderRadius.only(topLeft: Radius.circular(12), topRight: Radius.circular(12)),
            ),
            child: Row(
              children: [
                Icon(icon, size: ResponsiveHelper.iconSize(context, 18), color: theme.primaryColor),
                SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                Text(title, style: ResponsiveHelper.bodyStyle(context).copyWith(fontWeight: FontWeight.bold, color: theme.primaryColor)),
              ],
            ),
          ),
          Padding(padding: ResponsiveHelper.cardPadding(context), child: child),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: EdgeInsets.only(bottom: ResponsiveHelper.spacing(context, 8)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: ResponsiveHelper.spacing(context, 80), child: Text(label, style: ResponsiveHelper.smallStyle(context, color: AppColors.grey600))),
          Expanded(child: Text(value, style: ResponsiveHelper.bodyStyle(context))),
        ],
      ),
    );
  }

  Widget _buildLoadingIndicator() {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 16)),
        child: SizedBox(width: ResponsiveHelper.spacing(context, 24), height: ResponsiveHelper.spacing(context, 24), child: const CircularProgressIndicator(strokeWidth: 2)),
      ),
    );
  }

  Widget _buildEmptyMessage(String message) {
    return Padding(
      padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 8)),
      child: Text(message, style: ResponsiveHelper.bodyStyle(context, color: AppColors.grey500), textAlign: TextAlign.center),
    );
  }

  int _calculateTrustScore(UserModel user) {
    int score = 60;
    score += (user.averageRating * 4).toInt();
    score += (user.totalWorkDays / 10).clamp(0, 15).toInt();
    score -= user.noShowCount * 5;
    score -= user.lateCount * 2;
    return score.clamp(0, 100);
  }

  Future<void> _makePhoneCall(String phoneNumber) async {
    final uri = Uri.parse('tel:$phoneNumber');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      ToastHelper.showError('전화를 걸 수 없습니다');
    }
  }
}