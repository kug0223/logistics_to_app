// lib/screens/business_admin/dialogs/confirmed_list_dialog.dart
// PART 1: 메인 클래스, import, 목록 UI

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../models/core/work_detail_model.dart';
import '../../../models/core/application_model.dart';
import '../../../models/core/user_model.dart';
import '../../../providers/user_provider.dart';
import '../../../services/firestore_service.dart';
import '../../../utils/format_helper.dart';
import '../../../utils/responsive_helper.dart';
import '../../../utils/toast_helper.dart';
import '../../../widgets/work_type_icon.dart';
import '../../../widgets/dialogs/styled_dialog.dart';
import '../../../widgets/dialogs/worker_detail_dialog.dart';
import '../../../models/ui/admin_to_list_ui_models.dart';
import '../../../theme/app_colors.dart';
import '../../../utils/id_card_helper.dart';

class ConfirmedListDialog {
  final BuildContext context;
  final TOItem toItem;
  final FirestoreService firestoreService;
  final VoidCallback? onChanged;  // ⭐ 추가

  ConfirmedListDialog({
    required this.context,
    required this.toItem,
    required this.firestoreService,
    this.onChanged,  // ⭐ 추가
  });

  void show() {
    showDialog(
      context: context,
      builder: (context) => _ConfirmedListDialogWidget(
        toItem: toItem,
        firestoreService: firestoreService,
        onChanged: onChanged,  // ⭐ 추가
      ),
    );
  }
}

class _ConfirmedListDialogWidget extends StatefulWidget {
  final TOItem toItem;
  final FirestoreService firestoreService;
  final VoidCallback? onChanged;  // ⭐ 추가

  const _ConfirmedListDialogWidget({
    required this.toItem,
    required this.firestoreService,
    this.onChanged,  // ⭐ 추가
  });

  @override
  State<_ConfirmedListDialogWidget> createState() =>
      _ConfirmedListDialogWidgetState();
}

class _ConfirmedListDialogWidgetState
    extends State<_ConfirmedListDialogWidget> {
  bool _isLoading = true;
  bool _hasChanges = false;  // ⭐ 추가
  Map<String, List<Map<String, dynamic>>> _confirmedByWork = {};
  Map<String, String> _idCardStatusMap = {};
  String? _error;
  int _totalConfirmed = 0;

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

      // 각 업무별로 성별→나이순 정렬
      for (var workers in groupedByWork.values) {
        workers.sort((a, b) {
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
      }

      // 신분증 상태 일괄 조회
      final userProvider = context.read<UserProvider>();
      final currentUserId = userProvider.currentUser?.uid ?? '';
      
      final confirmedUserIds = results
          .where((item) => item['user'] != null)
          .map((item) => (item['user'] as UserModel).uid)
          .toList();
      
      final idCardStatusMap = await IdCardHelper.loadStatusBatch(
        firestoreService: widget.firestoreService,
        requesterId: currentUserId,
        targetUserIds: confirmedUserIds,
      );

      setState(() {
        _confirmedByWork = groupedByWork;
        _idCardStatusMap = idCardStatusMap;
        _totalConfirmed = confirmed.length;
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
          onPressed: () {
            if (_hasChanges) {
              widget.onChanged?.call();  // ⭐ 변경사항 전달
            }
            Navigator.pop(context);
          },
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
          ...workers.asMap().entries.map((entry) {
            final index = entry.key;
            final worker = entry.value;
            final user = worker['user'] as UserModel;
            final application = worker['application'] as ApplicationModel;
            final isLast = index == workers.length - 1;

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
                      // 순번
                      CircleAvatar(
                        radius: ResponsiveHelper.spacing(context, 16),
                        backgroundColor: AppColors.success.withOpacity(0.15),
                        child: Text(
                          '${index + 1}',
                          style: ResponsiveHelper.bodyStyle(context).copyWith(
                            fontWeight: FontWeight.bold,
                            color: AppColors.successDark,
                          ),
                        ),
                      ),
                      SizedBox(width: ResponsiveHelper.spacing(context, 12)),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // 1줄: 이름 + 성별·나이 + 화살표
                            Row(
                              children: [
                                Text(user.name, style: ResponsiveHelper.bodyStyle(context).copyWith(fontWeight: FontWeight.w600)),
                                SizedBox(width: ResponsiveHelper.spacing(context, 6)),
                                Text(
                                  '${user.gender ?? ''}${user.age != null ? ' · ${user.age}세' : ''}',
                                  style: ResponsiveHelper.smallStyle(context, color: AppColors.grey600),
                                ),
                                SizedBox(width: ResponsiveHelper.spacing(context, 4)),
                                Icon(Icons.chevron_right, size: ResponsiveHelper.iconSize(context, 16), color: AppColors.grey400),
                              ],
                            ),
                            SizedBox(height: ResponsiveHelper.spacing(context, 4)),
                            // 2줄: 신뢰도 + 신분증 + 평점
                            Row(
                              children: [
                                _buildTrustBadge(user),
                                SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                                IdCardHelper.buildStatusBadge(context, _idCardStatusMap[user.uid] ?? 'none'),
                                SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                                if (user.averageRating > 0) ...[
                                  Icon(Icons.star, size: ResponsiveHelper.iconSize(context, 12), color: Colors.amber),
                                  SizedBox(width: ResponsiveHelper.spacing(context, 2)),
                                  Text(user.averageRating.toStringAsFixed(1), style: ResponsiveHelper.smallStyle(context, color: AppColors.grey600)),
                                ],
                              ],
                            ),
                            // 3줄: 장기 근무 정보 (있는 경우)
                            if (application.isLongTermApplication && application.workPeriodDisplay.isNotEmpty) ...[
                              SizedBox(height: ResponsiveHelper.spacing(context, 6)),
                              Container(
                                padding: EdgeInsets.symmetric(
                                  horizontal: ResponsiveHelper.spacing(context, 8),
                                  vertical: ResponsiveHelper.spacing(context, 4),
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.purple.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.event_note,
                                      size: ResponsiveHelper.iconSize(context, 12),
                                      color: Colors.purple,
                                    ),
                                    SizedBox(width: ResponsiveHelper.spacing(context, 4)),
                                    Text(
                                      '장기: ${application.workPeriodDisplay}',
                                      style: ResponsiveHelper.tinyStyle(context, color: Colors.purple).copyWith(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),  
                    ],
                  ),
                ),
              ),
            );
          }),
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

  Future<void> _showWorkerDetailDialog(BuildContext context, UserModel user, ApplicationModel application, WorkDetailModel workDetail) async {
    final changed = await WorkerDetailDialog.show(
      context: context,
      user: user,
      application: application,
      toItem: widget.toItem,
      businessId: widget.toItem.to.businessId,
      isConfirmed: true,
      showApprovalButtons: false,
      onStatusChanged: () {
        _hasChanges = true;
      },
    );
    
    // ⭐ 신분증 상태만 로컬 업데이트 (전체 새로고침 X)
    if (changed != false) {
      _hasChanges = true;
      
      final userProvider = context.read<UserProvider>();
      final currentUserId = userProvider.currentUser?.uid ?? '';
      
      final newStatus = await IdCardHelper.loadStatusBatch(
        firestoreService: widget.firestoreService,
        requesterId: currentUserId,
        targetUserIds: [user.uid],
      );
      
      if (mounted) {
        setState(() {
          _idCardStatusMap.addAll(newStatus);
        });
      }
    }
  }
}