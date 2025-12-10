// lib/screens/business_admin/dialogs/confirmed_list_dialog.dart

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../models/core/work_detail_model.dart';
import '../../../models/core/application_model.dart';
import '../../../models/core/user_model.dart';
import '../../../providers/user_provider.dart';
import '../../../services/firestore_service.dart';
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
  final VoidCallback? onChanged;
  final VoidCallback? onLocalStatsChanged;  // ⭐ 추가

  ConfirmedListDialog({
    required this.context,
    required this.toItem,
    required this.firestoreService,
    this.onChanged,
    this.onLocalStatsChanged,  // ⭐ 추가
  });

  void show() {
    showDialog(
      context: context,
      builder: (context) => _ConfirmedListDialogWidget(
        toItem: toItem,
        firestoreService: firestoreService,
        onChanged: onChanged,
        onLocalStatsChanged: onLocalStatsChanged,  // ⭐ 추가
      ),
    );
  }
}

class _ConfirmedListDialogWidget extends StatefulWidget {
  final TOItem toItem;
  final FirestoreService firestoreService;
  final VoidCallback? onChanged;
  final VoidCallback? onLocalStatsChanged;  // ⭐ 추가

  const _ConfirmedListDialogWidget({
    required this.toItem,
    required this.firestoreService,
    this.onChanged,
    this.onLocalStatsChanged,  // ⭐ 추가
  });

  @override
  State<_ConfirmedListDialogWidget> createState() =>
      _ConfirmedListDialogWidgetState();
}

class _ConfirmedListDialogWidgetState
    extends State<_ConfirmedListDialogWidget> {
  bool _isLoading = true;
  bool _hasChanges = false;
  Map<String, List<Map<String, dynamic>>> _confirmedByWork = {};
  Map<String, String> _idCardStatusMap = {};
  String? _error;
  int _totalConfirmed = 0;

  // 신분증 일괄 요청 모드
  bool _isIdCardSelectMode = false;
  final Set<String> _selectedIdCardUserIds = {};

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

      // ✅ 1. 중복 제거된 UID 목록
      final uniqueUids = confirmed.map((app) => app.uid).toSet().toList();
      
      // ✅ 2. 사용자 정보 한 번만 조회 (병렬)
      final userFutures = uniqueUids.map((uid) async {
        final user = await widget.firestoreService.getUser(uid);
        return MapEntry(uid, user);
      });
      final userEntries = await Future.wait(userFutures);
      final userMap = Map.fromEntries(userEntries);
      
      // ✅ 3. 결과 매핑 (추가 조회 없음)
      final results = confirmed.map((app) {
        return {
          'application': app,
          'user': userMap[app.uid],
          'workType': app.selectedWorkType,
        };
      }).toList();
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
          
          final genderOrder = {'남성': 0, '여성': 1};
          final genderA = genderOrder[userA.gender] ?? 2;
          final genderB = genderOrder[userB.gender] ?? 2;
          
          if (genderA != genderB) {
            return genderA.compareTo(genderB);
          }
          
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
      debugPrint('❌ 확정 명단 로드 실패: $e');
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('MM/dd (E)', 'ko_KR');

    // ⭐ PopScope 추가: 외부 탭으로 닫아도 변경 여부 반환
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          // ⭐ 변경사항 있으면 로컬 콜백 호출
          if (_hasChanges) {
            widget.onLocalStatsChanged?.call();
          }
          Navigator.pop(context, _hasChanges);
        }
      },
      child: StyledDialog(
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
              // ⭐ 변경사항 있으면 로컬 콜백 호출
              if (_hasChanges) {
                widget.onLocalStatsChanged?.call();
              }
              Navigator.pop(context, _hasChanges);
            },
          ),
        ],
      ),
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

    // 전체 미요청자 수 계산
    final totalRequestableCount = _idCardStatusMap.entries
        .where((e) => e.value == 'none')
        .length;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildTotalStats(),
        // 신분증 일괄 요청 영역
        if (totalRequestableCount > 0)
          _buildIdCardRequestSection(totalRequestableCount),
        SizedBox(height: ResponsiveHelper.spacing(context, 16)),
        ..._confirmedByWork.entries.map((entry) {
          final groupKey = entry.key;
          final workers = entry.value;
          
          // ✅ workDetailId로 먼저 찾고, 없으면 workType으로 폴백
          final workDetail = widget.toItem.workDetails.firstWhere(
            (w) => w.id == groupKey,
            orElse: () => widget.toItem.workDetails.firstWhere(
              (w) => w.workType == groupKey,
              orElse: () => widget.toItem.workDetails.first,
            ),
          );
          return _buildWorkSection(workDetail.workType, workers, workDetail);
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

  /// 신분증 일괄 요청 섹션
  Widget _buildIdCardRequestSection(int requestableCount) {
    return Container(
      margin: EdgeInsets.only(top: ResponsiveHelper.spacing(context, 12)),
      padding: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 16),
        vertical: ResponsiveHelper.spacing(context, 10),
      ),
      decoration: BoxDecoration(
        color: _isIdCardSelectMode ? AppColors.infoBg : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _isIdCardSelectMode ? AppColors.info : AppColors.border),
      ),
      child: Row(
        children: [
          Icon(
            Icons.badge,
            size: ResponsiveHelper.iconSize(context, 18),
            color: AppColors.info,
          ),
          SizedBox(width: ResponsiveHelper.spacing(context, 8)),
          Expanded(
            child: Text(
              _isIdCardSelectMode 
                  ? '${_selectedIdCardUserIds.length}명 선택됨'
                  : '미요청 $requestableCount명',
              style: ResponsiveHelper.bodyStyle(context, color: AppColors.infoDark),
            ),
          ),
          // 요청하기 버튼 (선택 모드 + 선택된 항목 있을 때)
          if (_isIdCardSelectMode && _selectedIdCardUserIds.isNotEmpty) ...[
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => _batchRequestIdCard(),
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: ResponsiveHelper.spacing(context, 12),
                    vertical: ResponsiveHelper.spacing(context, 6),
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.success,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '요청하기',
                    style: ResponsiveHelper.smallStyle(context, color: Colors.white).copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
            SizedBox(width: ResponsiveHelper.spacing(context, 8)),
          ],
          // 신분증 요청 / 취소 버튼
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () {
                setState(() {
                  _isIdCardSelectMode = !_isIdCardSelectMode;
                  if (!_isIdCardSelectMode) {
                    _selectedIdCardUserIds.clear();
                  } else {
                    _selectAllRequestableUsers();
                  }
                });
              },
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: EdgeInsets.symmetric(
                  horizontal: ResponsiveHelper.spacing(context, 12),
                  vertical: ResponsiveHelper.spacing(context, 6),
                ),
                decoration: BoxDecoration(
                  color: _isIdCardSelectMode ? AppColors.grey100 : AppColors.info,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _isIdCardSelectMode ? '취소' : '신분증 요청',
                  style: ResponsiveHelper.smallStyle(
                    context, 
                    color: _isIdCardSelectMode ? AppColors.grey700 : Colors.white,
                  ).copyWith(fontWeight: FontWeight.w600),
                ),
              ),
            ),
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
          // 헤더
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
          // 워커 목록
          ...workers.asMap().entries.map((entry) {
            final index = entry.key;
            final worker = entry.value;
            final user = worker['user'] as UserModel;
            final application = worker['application'] as ApplicationModel;
            final isLast = index == workers.length - 1;
            final idCardStatus = _idCardStatusMap[user.uid] ?? 'none';
            final isIdCardSelected = _selectedIdCardUserIds.contains(user.uid);

            return Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: _isIdCardSelectMode && idCardStatus == 'none'
                    ? () => _toggleIdCardSelection(user.uid)
                    : () => _showWorkerDetailDialog(context, user, application, workDetail),
                borderRadius: isLast ? const BorderRadius.only(bottomLeft: Radius.circular(16), bottomRight: Radius.circular(16)) : null,
                child: Container(
                  padding: ResponsiveHelper.cardPadding(context),
                  decoration: BoxDecoration(
                    color: isIdCardSelected ? AppColors.infoBg : Colors.transparent,
                    border: isLast ? null : Border(bottom: BorderSide(color: AppColors.border)),
                  ),
                  child: Row(
                    children: [
                      // ✅ 체크박스 영역 (애니메이션)
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        width: _isIdCardSelectMode ? 32 : 0,
                        child: _isIdCardSelectMode
                            ? (idCardStatus == 'none'
                                ? SizedBox(
                                    width: 24,
                                    height: 24,
                                    child: Checkbox(
                                      value: isIdCardSelected,
                                      onChanged: (_) => _toggleIdCardSelection(user.uid),
                                      activeColor: AppColors.info,
                                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                      visualDensity: VisualDensity.compact,
                                    ),
                                  )
                                : const SizedBox(width: 24))  // 이미 요청된 사용자는 빈 공간
                            : const SizedBox.shrink(),
                      ),
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
                                  user.gender != null || user.age != null
                                      ? '(${user.gender ?? ''}${user.age != null ? ' · ${user.age}세' : ''})'
                                      : '',
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
                                if (user.averageRating > 0) ...[
                                  Icon(Icons.star, size: ResponsiveHelper.iconSize(context, 12), color: Colors.amber),
                                  SizedBox(width: ResponsiveHelper.spacing(context, 2)),
                                  Text(user.averageRating.toStringAsFixed(1), style: ResponsiveHelper.smallStyle(context, color: AppColors.grey600)),
                                ],
                                SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                                IdCardHelper.buildStatusBadge(context, idCardStatus),
                              ],
                            ),
                            // 3줄: 장기 근무 정보 (있는 경우) - 희망 시작일만 강조
                            if (widget.toItem.to.isLongTerm && application.isLongTermApplication && application.workPeriodDisplay.isNotEmpty) ...[
                              SizedBox(height: ResponsiveHelper.spacing(context, 6)),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.date_range,
                                    size: ResponsiveHelper.iconSize(context, 12),
                                    color: application.desiredStartDate != null 
                                        ? Theme.of(context).primaryColor 
                                        : AppColors.grey500,
                                  ),
                                  SizedBox(width: ResponsiveHelper.spacing(context, 4)),
                                  Text(
                                    application.desiredStartDate != null
                                        ? '희망: ${application.desiredStartDate!.month}/${application.desiredStartDate!.day}~ (${application.workEndDate!.month}/${application.workEndDate!.day}까지)'
                                        : '장기: ${application.workPeriodDisplay}',
                                    style: ResponsiveHelper.smallStyle(
                                      context, 
                                      color: application.desiredStartDate != null 
                                          ? Theme.of(context).primaryColor 
                                          : AppColors.grey600,
                                    ).copyWith(
                                      fontWeight: application.desiredStartDate != null ? FontWeight.w600 : FontWeight.normal,
                                    ),
                                  ),
                                ],
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
    
    // 70+: 파랑, 40~69: 회색, 40 미만: 빨강
    final Color color;
    final Color bgColor;
    final bool isLow = trustScore < 40;
    
    if (trustScore >= 70) {
      color = AppColors.info;
      bgColor = AppColors.infoBg;
    } else if (isLow) {
      color = AppColors.error;
      bgColor = AppColors.errorBg;
    } else {
      color = AppColors.grey600;
      bgColor = AppColors.grey100;
    }
    
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 6), 
        vertical: ResponsiveHelper.spacing(context, 2),
      ),
      decoration: BoxDecoration(
        color: bgColor, 
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isLow ? Icons.shield : Icons.shield_outlined,
            size: ResponsiveHelper.iconSize(context, 10),
            color: color,
          ),
          SizedBox(width: ResponsiveHelper.spacing(context, 3)),
          Text(
            '신뢰$trustScore', 
            style: ResponsiveHelper.tinyStyle(context, color: color).copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
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

  /// ⭐ 수정: 로컬 통계 업데이트 패턴 적용
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
    
    if (changed == true && mounted) {
      _hasChanges = true;
      
      final workType = application.selectedWorkType;
      
      setState(() {
        // 1. 목록에서 해당 워커 제거
        _confirmedByWork[workType]?.removeWhere(
          (item) => (item['user'] as UserModel).uid == user.uid
        );
        
        // 2. 해당 업무에 워커가 없으면 업무 자체 제거
        if (_confirmedByWork[workType]?.isEmpty ?? false) {
          _confirmedByWork.remove(workType);
        }
        
        // 3. 총 인원 감소
        _totalConfirmed--;
        
        // 4. 신분증 맵에서 제거
        _idCardStatusMap.remove(user.uid);
        _selectedIdCardUserIds.remove(user.uid);
        
        // 5. 부모 toItem.workDetailStats 업데이트
        widget.toItem.workDetailStats ??= {};
        // ✅ workDetailId로 조회 (application에서 가져옴)
        final workDetailId = application.workDetailId;
        if (workDetailId != null) {
          final stats = widget.toItem.workDetailStats![workDetailId];
          if (stats != null) {
            stats['confirmed'] = ((stats['confirmed'] ?? 1)) - 1;
          }
        }
      });
    } else {
      // 신분증 상태만 변경된 경우 (확정 취소 아님)
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

  /// 미요청자 전체 선택
  void _selectAllRequestableUsers() {
    _selectedIdCardUserIds.clear();
    for (var entry in _confirmedByWork.entries) {
      for (var worker in entry.value) {
        final user = worker['user'] as UserModel?;
        if (user == null) continue;
        final status = _idCardStatusMap[user.uid] ?? 'none';
        if (status == 'none') {
          _selectedIdCardUserIds.add(user.uid);
        }
      }
    }
  }

  /// 신분증 선택 토글
  void _toggleIdCardSelection(String uid) {
    setState(() {
      if (_selectedIdCardUserIds.contains(uid)) {
        _selectedIdCardUserIds.remove(uid);
      } else {
        _selectedIdCardUserIds.add(uid);
      }
    });
  }

  /// 일괄 신분증 요청
  Future<void> _batchRequestIdCard() async {
    if (_selectedIdCardUserIds.isEmpty) return;

    final userProvider = context.read<UserProvider>();
    final currentUser = userProvider.currentUser;
    if (currentUser == null) {
      ToastHelper.showError('로그인이 필요합니다');
      return;
    }

    // 선택된 사용자 정보 수집
    final targets = <Map<String, String>>[];
    for (var entry in _confirmedByWork.entries) {
      for (var worker in entry.value) {
        final user = worker['user'] as UserModel?;
        final app = worker['application'] as ApplicationModel?;
        if (user == null || !_selectedIdCardUserIds.contains(user.uid)) continue;
        
        targets.add({
          'uid': user.uid,
          'name': user.name,
          'applicationId': app?.id ?? '',
        });
      }
    }

    final businessId = widget.toItem.to.businessId;
    final business = await widget.firestoreService.getBusinessById(businessId);

    final successCount = await IdCardHelper.showBatchRequestDialog(
      context: context,
      firestoreService: widget.firestoreService,
      requester: {
        'uid': currentUser.uid,
        'name': currentUser.name,
      },
      business: {
        'id': businessId,
        'name': business?.name ?? '',
      },
      targets: targets,
    );

    if (successCount > 0) {
      setState(() {
        for (final uid in _selectedIdCardUserIds) {
          _idCardStatusMap[uid] = 'pending';
        }
        _isIdCardSelectMode = false;
        _selectedIdCardUserIds.clear();
      });
    }
  }
}