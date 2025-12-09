// lib/screens/business_admin/dialogs/work_applicants_dialog.dart
// 업무별 지원자 관리 다이얼로그 - 개선된 버전

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../../models/core/application_model.dart';
import '../../../models/core/work_detail_model.dart';
import '../../../models/core/user_model.dart';
import '../../../services/firestore_service.dart';
import '../../../providers/user_provider.dart';
import '../../../utils/toast_helper.dart';
import '../../../utils/responsive_helper.dart';
import '../../../utils/dialog_helper.dart';
import '../../../widgets/work_type_icon.dart';
import '../../../widgets/dialogs/worker_detail_dialog.dart';
import '../../../models/ui/admin_to_list_ui_models.dart';
import '../../../theme/app_colors.dart';
import '../../../utils/id_card_helper.dart';
import 'fixed_worker_management_dialog.dart';
import '../../../widgets/common/loading_button.dart';

/// 업무별 지원자 관리 다이얼로그 - 개선된 버전
class WorkApplicantsDialog extends StatefulWidget {
  final WorkDetailModel work;
  final TOItem toItem;
  final VoidCallback onChanged;

  const WorkApplicantsDialog({
    super.key,
    required this.work,
    required this.toItem,
    required this.onChanged,
  });

  @override
  State<WorkApplicantsDialog> createState() => _WorkApplicantsDialogState();
}

class _WorkApplicantsDialogState extends State<WorkApplicantsDialog> {
  final FirestoreService _firestoreService = FirestoreService();
  
  List<Map<String, dynamic>> _applicants = [];
  bool _isLoading = true;
  
  final Set<String> _selectedIds = {};
  bool _selectAll = false;
  
  // 신분증 상태 맵
  Map<String, String> _idCardStatusMap = {};
  // ⭐ 변경 여부 추적
  bool _hasChanges = false;
  // ✅ 로딩 상태
  bool _isProcessing = false;
  // 신분증 일괄 요청 모드
  bool _isIdCardSelectMode = false;
  final Set<String> _selectedIdCardUserIds = {};

  @override
  void initState() {
    super.initState();
    _loadApplicants();
  }

  /// 지원자 + 사용자 정보 + 신분증 상태 로드
  Future<void> _loadApplicants() async {
    setState(() => _isLoading = true);

    try {
      final userProvider = context.read<UserProvider>();
      final currentUserId = userProvider.currentUser?.uid ?? '';

      final apps = await _firestoreService.getApplicationsByTO(
        widget.toItem.to.businessId,
        widget.toItem.to.title,
        widget.toItem.to.date,
      );

      final filtered = apps.where((app) {
        // ✅ workDetailId로 매칭 (없으면 workType + 시간으로 폴백)
        if (app.workDetailId != null && app.workDetailId!.isNotEmpty) {
          return app.workDetailId == widget.work.id;
        }
        // 기존 데이터 호환
        return app.selectedWorkType == widget.work.workType &&
               app.startTime == widget.work.startTime &&
               app.endTime == widget.work.endTime;
      }).toList();

      // 병렬로 사용자 정보 조회
      final futures = filtered.map((app) async {
        final user = await _firestoreService.getUser(app.uid);
        return {
          'application': app,
          'user': user,
        };
      }).toList();

      final applicantsWithUserInfo = await Future.wait(futures);
      
      // 성별 → 나이순 정렬
      applicantsWithUserInfo.sort((a, b) {
        final userA = a['user'] as UserModel?;
        final userB = b['user'] as UserModel?;
        
        if (userA == null || userB == null) return 0;
        
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

      // 신분증 상태 일괄 조회 (확정자만)
      final confirmedUserIds = applicantsWithUserInfo
          .where((item) {
            final app = item['application'] as ApplicationModel;
            return item['user'] != null && app.status == 'CONFIRMED';
          })
          .map((item) => (item['user'] as UserModel).uid)
          .toList();
      
      final idCardStatusMap = await IdCardHelper.loadStatusBatch(
        firestoreService: _firestoreService,
        requesterId: currentUserId,
        targetUserIds: confirmedUserIds,
      );

      setState(() {
        _applicants = applicantsWithUserInfo;
        _idCardStatusMap = idCardStatusMap;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }


  /// 전체 선택/해제
  void _toggleSelectAll(bool? value) {
    final pendingApps = _applicants
        .where((item) => (item['application'] as ApplicationModel).status == 'PENDING')
        .map((item) => (item['application'] as ApplicationModel).id)
        .toList();

    setState(() {
      _selectAll = value ?? false;
      if (_selectAll) {
        _selectedIds.addAll(pendingApps);
      } else {
        _selectedIds.clear();
      }
    });
  }

  /// 개별 선택
  void _toggleSelection(String appId) {
    setState(() {
      if (_selectedIds.contains(appId)) {
        _selectedIds.remove(appId);
      } else {
        _selectedIds.add(appId);
      }
      
      final pendingCount = _applicants
          .where((item) => (item['application'] as ApplicationModel).status == 'PENDING')
          .length;
      _selectAll = _selectedIds.length == pendingCount && pendingCount > 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    // 상태별 분류
    final pending = _applicants.where((item) => 
      (item['application'] as ApplicationModel).status == 'PENDING').toList();
    final confirmed = _applicants.where((item) => 
      (item['application'] as ApplicationModel).status == 'CONFIRMED').toList();

      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop) {
            Navigator.pop(context, _hasChanges);
          }
        },
        child: Dialog(
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
            _buildHeader(context, theme),
            
            // 통계 바
            _buildStatsBar(context, pending.length, confirmed.length),
            
            // 전체 선택 (대기중인 경우만)
            if (pending.isNotEmpty)
              _buildSelectAllRow(context, pending.length),
            
            // 지원자 목록
            Flexible(
              child: _isLoading
                  ? Center(child: CircularProgressIndicator())
                  // ✅ pending과 confirmed 둘 다 비어있으면 빈 상태 표시
                  : (pending.isEmpty && confirmed.isEmpty)
                      ? _buildEmptyState(context)
                      : _buildApplicantList(context, pending, confirmed),
            ),
            
            // 하단 액션 바
            _buildBottomBar(context),
          ],
        ),
      ),
        ),
    );
  }

  /// 헤더
  Widget _buildHeader(BuildContext context, ThemeData theme) {
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
      child: Row(
        children: [
          // 업무 아이콘
          WorkTypeIcon.buildWithBackground(
            iconString: widget.work.workTypeIcon ?? 'work',
            backgroundColor: widget.work.workTypeBackgroundColor,
            size: ResponsiveHelper.iconSize(context, 24),
            containerSize: ResponsiveHelper.spacing(context, 44),
          ),
          SizedBox(width: ResponsiveHelper.spacing(context, 12)),
          
          // 제목
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${widget.work.workType} - 지원자 관리',
                  style: ResponsiveHelper.subtitleStyle(context).copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: ResponsiveHelper.spacing(context, 2)),
                Text(
                  '${widget.work.startTime}~${widget.work.endTime} | ${widget.work.formattedWage}',
                  style: ResponsiveHelper.smallStyle(context, color: Colors.white70),
                ),
              ],
            ),
          ),
          
          // 닫기 버튼
          IconButton(
            onPressed: () => Navigator.pop(context, _hasChanges),  // ✅ 변경 여부 반환
            icon: Icon(Icons.close, color: Colors.white),
            padding: EdgeInsets.zero,
            constraints: BoxConstraints(),
          ),
        ],
      ),
    );
  }

  /// 통계 바
  Widget _buildStatsBar(BuildContext context, int pendingCount, int confirmedCount) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 16),
        vertical: ResponsiveHelper.spacing(context, 12),
      ),
      decoration: BoxDecoration(
        color: AppColors.grey50,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          _buildStatItem(context, '대기', pendingCount, AppColors.warning),
          SizedBox(width: ResponsiveHelper.spacing(context, 24)),
          _buildStatItem(context, '확정', confirmedCount, AppColors.success),
          const Spacer(),
          Text(
            '필요: ${widget.work.requiredCount}명',
            style: ResponsiveHelper.smallStyle(context, color: AppColors.grey600),
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(BuildContext context, String label, int count, Color color) {
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        SizedBox(width: ResponsiveHelper.spacing(context, 6)),
        Text(
          '$label: ',
          style: ResponsiveHelper.smallStyle(context, color: AppColors.grey600),
        ),
        Text(
          '$count명',
          style: ResponsiveHelper.bodyStyle(context).copyWith(
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }

  /// 전체 선택 행
  Widget _buildSelectAllRow(BuildContext context, int pendingCount) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 16),
        vertical: ResponsiveHelper.spacing(context, 8),
      ),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 24,
            height: 24,
            child: Checkbox(
              value: _selectAll,
              onChanged: _toggleSelectAll,
              activeColor: Theme.of(context).primaryColor,
            ),
          ),
          SizedBox(width: ResponsiveHelper.spacing(context, 8)),
          Text(
            '전체 선택',
            style: ResponsiveHelper.bodyStyle(context),
          ),
          const Spacer(),
          if (_selectedIds.isNotEmpty)
            Container(
              padding: EdgeInsets.symmetric(
                horizontal: ResponsiveHelper.spacing(context, 8),
                vertical: ResponsiveHelper.spacing(context, 4),
              ),
              decoration: BoxDecoration(
                color: Theme.of(context).primaryColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '${_selectedIds.length}명 선택',
                style: ResponsiveHelper.smallStyle(context, color: Theme.of(context).primaryColor),
              ),
            ),
        ],
      ),
    );
  }

  /// 빈 상태
  Widget _buildEmptyState(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
        minHeight: ResponsiveHelper.spacing(context, 200),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.people_outline, size: 64, color: AppColors.grey300),
            SizedBox(height: ResponsiveHelper.spacing(context, 16)),
            Text(
              '지원자가 없습니다',
              style: ResponsiveHelper.bodyStyle(context, color: AppColors.grey500),
            ),
        ],
      ),
      ),
    );
  }

  /// 지원자 목록
  Widget _buildApplicantList(BuildContext context, List<Map<String, dynamic>> pending, List<Map<String, dynamic>> confirmed) {
    return SingleChildScrollView(
      padding: ResponsiveHelper.cardPadding(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 대기 중 섹션
          if (pending.isNotEmpty) ...[
            _buildSectionHeader(context, '대기 중', pending.length, AppColors.warning),
            SizedBox(height: ResponsiveHelper.spacing(context, 8)),
            ...pending.asMap().entries.map((entry) {
              final index = entry.key;
              final item = entry.value;
              return _buildApplicantCard(context, item, index + 1, isPending: true);
            }),
            SizedBox(height: ResponsiveHelper.spacing(context, 16)),
          ],
          
          // 확정 섹션
          if (confirmed.isNotEmpty) ...[
            _buildConfirmedSectionHeader(context, confirmed.length),
            SizedBox(height: ResponsiveHelper.spacing(context, 8)),
            ...confirmed.asMap().entries.map((entry) {
              final index = entry.key;
              final item = entry.value;
              return _buildApplicantCard(context, item, index + 1, isPending: false);
            }),
          ],
        ],
      ),
    );
  }
  /// 확정 섹션 헤더 (신분증 요청 버튼 포함)
  Widget _buildConfirmedSectionHeader(BuildContext context, int confirmedCount) {
    // 미요청자 수 계산
    final requestableCount = _applicants.where((item) {
      final app = item['application'] as ApplicationModel;
      final user = item['user'] as UserModel?;
      if (app.status != 'CONFIRMED' || user == null) return false;
      final status = _idCardStatusMap[user.uid] ?? 'none';
      return status == 'none';
    }).length;

    return Row(
      children: [
        // 좌측: 섹션 타이틀
        Container(
          width: 4,
          height: 20,
          decoration: BoxDecoration(
            color: AppColors.success,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        SizedBox(width: ResponsiveHelper.spacing(context, 8)),
        Text(
          '확정 ($confirmedCount명)',
          style: ResponsiveHelper.subtitleStyle(context).copyWith(
            fontWeight: FontWeight.bold,
            color: AppColors.success,
          ),
        ),
        
        const Spacer(),
        
        // 우측: 신분증 요청 버튼들
        if (requestableCount > 0) ...[
          // 선택 모드일 때: 요청하기 버튼
          if (_isIdCardSelectMode && _selectedIdCardUserIds.isNotEmpty) ...[
            _buildIdCardRequestButton(context),
            SizedBox(width: ResponsiveHelper.spacing(context, 8)),
          ],
          
          // 신분증 요청 토글 버튼
          _buildIdCardSelectModeButton(context, requestableCount),
        ],
      ],
    );
  }

  /// 신분증 선택 모드 토글 버튼
  Widget _buildIdCardSelectModeButton(BuildContext context, int requestableCount) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          setState(() {
            _isIdCardSelectMode = !_isIdCardSelectMode;
            if (!_isIdCardSelectMode) {
              _selectedIdCardUserIds.clear();
            } else {
              // 선택 모드 진입 시 미요청자 전체 선택
              _selectAllRequestableUsers();
            }
          });
        },
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: ResponsiveHelper.spacing(context, 10),
            vertical: ResponsiveHelper.spacing(context, 6),
          ),
          decoration: BoxDecoration(
            color: _isIdCardSelectMode ? AppColors.info : AppColors.infoBg,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.info),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _isIdCardSelectMode ? Icons.close : Icons.badge,
                size: ResponsiveHelper.iconSize(context, 14),
                color: _isIdCardSelectMode ? Colors.white : AppColors.info,
              ),
              SizedBox(width: ResponsiveHelper.spacing(context, 4)),
              Text(
                _isIdCardSelectMode ? '취소' : '신분증 요청',
                style: ResponsiveHelper.smallStyle(
                  context,
                  color: _isIdCardSelectMode ? Colors.white : AppColors.info,
                ).copyWith(fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 요청하기 버튼
  Widget _buildIdCardRequestButton(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _batchRequestIdCard(),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: ResponsiveHelper.spacing(context, 10),
            vertical: ResponsiveHelper.spacing(context, 6),
          ),
          decoration: BoxDecoration(
            color: AppColors.success,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.send,
                size: ResponsiveHelper.iconSize(context, 14),
                color: Colors.white,
              ),
              SizedBox(width: ResponsiveHelper.spacing(context, 4)),
              Text(
                '요청하기 (${_selectedIdCardUserIds.length})',
                style: ResponsiveHelper.smallStyle(context, color: Colors.white).copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 미요청자 전체 선택
  void _selectAllRequestableUsers() {
    _selectedIdCardUserIds.clear();
    for (final item in _applicants) {
      final app = item['application'] as ApplicationModel;
      final user = item['user'] as UserModel?;
      if (app.status != 'CONFIRMED' || user == null) continue;
      
      final status = _idCardStatusMap[user.uid] ?? 'none';
      if (status == 'none') {
        _selectedIdCardUserIds.add(user.uid);
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
    for (final item in _applicants) {
      final app = item['application'] as ApplicationModel;
      final user = item['user'] as UserModel?;
      if (user == null || !_selectedIdCardUserIds.contains(user.uid)) continue;
      
      targets.add({
        'uid': user.uid,
        'name': user.name,
        'applicationId': app.id,
      });
    }

    final businessId = widget.toItem.to.businessId;
    final business = await _firestoreService.getBusinessById(businessId);

    final successCount = await IdCardHelper.showBatchRequestDialog(
      context: context,
      firestoreService: _firestoreService,
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
      _hasChanges = true;
      
      // 상태 맵 업데이트 (요청 성공한 사용자들)
      setState(() {
        for (final uid in _selectedIdCardUserIds) {
          _idCardStatusMap[uid] = 'pending';
        }
        _isIdCardSelectMode = false;
        _selectedIdCardUserIds.clear();
      });
    }
  }

  /// 섹션 헤더
  Widget _buildSectionHeader(BuildContext context, String title, int count, Color color) {
    return Row(
      children: [
        Container(
          width: 4,
          height: 20,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        SizedBox(width: ResponsiveHelper.spacing(context, 8)),
        Text(
          '$title ($count명)',
          style: ResponsiveHelper.subtitleStyle(context).copyWith(
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }

  /// 지원자 카드 (개선된 버전)
  Widget _buildApplicantCard(BuildContext context, Map<String, dynamic> item, int index, {required bool isPending}) {
    final app = item['application'] as ApplicationModel;
    final user = item['user'] as UserModel?;
    final idCardStatus = _idCardStatusMap[user?.uid ?? ''] ?? 'none';
    final isSelected = _selectedIds.contains(app.id);
    
    // 신뢰도 점수 계산
    final trustScore = _calculateTrustScore(user);

    return Container(
      margin: EdgeInsets.only(bottom: ResponsiveHelper.spacing(context, 8)),
      decoration: BoxDecoration(
        color: isSelected ? Theme.of(context).primaryColor.withOpacity(0.05) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isSelected ? Theme.of(context).primaryColor : AppColors.border,
          width: isSelected ? 2 : 1,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: isPending ? () => _toggleSelection(app.id) : null,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: ResponsiveHelper.cardPadding(context),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // ✅ 체크박스 영역 (레이아웃 안정화)
                if (isPending) ...[
                  // 대기중: 항상 체크박스 표시
                  SizedBox(
                    width: 24,
                    height: 24,
                    child: Checkbox(
                      value: isSelected,
                      onChanged: (_) => _toggleSelection(app.id),
                      activeColor: Theme.of(context).primaryColor,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                  SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                ] else ...[
                  // 확정: 신분증 모드에 따라 애니메이션
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: _isIdCardSelectMode ? 32 : 0,
                    child: _isIdCardSelectMode
                        ? (idCardStatus == 'none'
                            ? SizedBox(
                                width: 24,
                                height: 24,
                                child: Checkbox(
                                  value: _selectedIdCardUserIds.contains(user?.uid ?? ''),
                                  onChanged: (_) => _toggleIdCardSelection(user?.uid ?? ''),
                                  activeColor: AppColors.info,
                                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                  visualDensity: VisualDensity.compact,
                                ),
                              )
                            : const SizedBox(width: 24))  // 이미 요청된 사용자는 빈 공간
                        : const SizedBox.shrink(),
                  ),
                ],
                
                // 순번
                CircleAvatar(
                  radius: ResponsiveHelper.spacing(context, 16),
                  backgroundColor: isPending 
                      ? AppColors.warning.withOpacity(0.15)
                      : AppColors.success.withOpacity(0.15),
                  child: Text(
                    '$index',
                    style: ResponsiveHelper.bodyStyle(context).copyWith(
                      fontWeight: FontWeight.bold,
                      color: isPending ? AppColors.warningDark : AppColors.successDark,
                    ),
                  ),
                ),
                SizedBox(width: ResponsiveHelper.spacing(context, 12)),
                
                // 정보
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 1줄: 이름 + 성별·나이
                      Row(
                        children: [
                          Text(
                            user?.name ?? '이름 없음',
                            style: ResponsiveHelper.bodyStyle(context).copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          SizedBox(width: ResponsiveHelper.spacing(context, 6)),
                          Expanded(
                            child: Text(
                              '${user?.gender ?? ''}${user?.age != null ? ' · ${user!.age}세' : ''}',
                              style: ResponsiveHelper.smallStyle(context, color: AppColors.grey500),
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: ResponsiveHelper.spacing(context, 4)),
                      
                      // 2줄: 연락처
                      Row(
                        children: [
                          Icon(
                            Icons.phone,
                            size: ResponsiveHelper.iconSize(context, 12),
                            color: AppColors.grey400,
                          ),
                          SizedBox(width: ResponsiveHelper.spacing(context, 4)),
                          Text(
                            user?.phone ?? '-',
                            style: ResponsiveHelper.smallStyle(context, color: AppColors.grey600),
                          ),
                        ],
                      ),
                      SizedBox(height: ResponsiveHelper.spacing(context, 4)),
                      
                      // 3줄: 지원시간 + 신분증 배지 (확정자만)
                      Row(
                        children: [
                          Icon(
                            Icons.access_time,
                            size: ResponsiveHelper.iconSize(context, 12),
                            color: AppColors.grey400,
                          ),
                          SizedBox(width: ResponsiveHelper.spacing(context, 4)),
                          Text(
                            _formatAppliedTime(app.appliedAt),
                            style: ResponsiveHelper.smallStyle(context, color: AppColors.grey500),
                          ),
                          // ✅ 확정자의 신분증 배지를 지원시간 옆으로 이동
                          if (!isPending) ...[
                            SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                            IdCardHelper.buildStatusBadge(context, idCardStatus),
                          ],
                        ],
                      ),
                      SizedBox(height: ResponsiveHelper.spacing(context, 6)),
                      
                      // 4줄: 신뢰도 + 평점
                      Row(
                        children: [
                          _buildTrustBadge(context, trustScore),
                          SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                          if (user != null && user.averageRating > 0) ...[
                            Icon(
                              Icons.star,
                              size: ResponsiveHelper.iconSize(context, 12),
                              color: Colors.amber,
                            ),
                            SizedBox(width: ResponsiveHelper.spacing(context, 2)),
                            Text(
                              user.averageRating.toStringAsFixed(1),
                              style: ResponsiveHelper.smallStyle(context, color: AppColors.grey600),
                            ),
                            SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                          ],
                        ],
                      ),
                      
                      // 자기소개 (있는 경우)
                      if (app.applicationMessage?.isNotEmpty == true) ...[
                        SizedBox(height: ResponsiveHelper.spacing(context, 6)),
                        Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: ResponsiveHelper.spacing(context, 8),
                            vertical: ResponsiveHelper.spacing(context, 4),
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.grey50,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            app.applicationMessage!,
                            style: ResponsiveHelper.smallStyle(context, color: AppColors.grey600),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                      
                      // 장기 근무 정보 (있는 경우) - ✅ TO도 장기인지 확인
                      if (widget.toItem.to.isLongTerm && app.isLongTermApplication && app.workPeriodDisplay.isNotEmpty) ...[
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
                                '장기: ${app.workPeriodDisplay}',
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
                _buildMoreMenuButton(context, item, isPending),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 신뢰도 점수 계산
  int _calculateTrustScore(UserModel? user) {
    if (user == null) return 60;
    
    int score = 60;
    score += ((user.averageRating) * 4).round();
    score += (user.totalWorkDays / 10).clamp(0, 15).round();
    score -= (user.noShowCount ?? 0) * 5;
    score -= (user.lateCount ?? 0) * 2;
    
    return score.clamp(0, 100);
  }

  /// 신뢰도 배지
  Widget _buildTrustBadge(BuildContext context, int score) {
    Color color;
    if (score >= 80) {
      color = AppColors.success;
    } else if (score >= 60) {
      color = AppColors.info;
    } else if (score >= 40) {
      color = AppColors.warning;
    } else {
      color = AppColors.error;
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
          Icon(
            Icons.shield,
            size: ResponsiveHelper.iconSize(context, 10),
            color: color,
          ),
          SizedBox(width: ResponsiveHelper.spacing(context, 3)),
          Text(
            '신뢰 $score',
            style: ResponsiveHelper.tinyStyle(context, color: color).copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  /// 지원 시간 포맷
  String _formatAppliedTime(DateTime appliedAt) {
    final now = DateTime.now();
    final diff = now.difference(appliedAt);
    
    if (diff.inMinutes < 60) {
      return '${diff.inMinutes}분 전';
    } else if (diff.inHours < 24) {
      return '${diff.inHours}시간 전';
    } else if (diff.inDays < 7) {
      return '${diff.inDays}일 전';
    } else {
      return DateFormat('MM/dd HH:mm').format(appliedAt);
    }
  }
  /// 더보기 메뉴 버튼
  Widget _buildMoreMenuButton(BuildContext context, Map<String, dynamic> item, bool isPending) {
    final app = item['application'] as ApplicationModel;
    final user = item['user'] as UserModel?;
    final isConfirmed = app.status == 'CONFIRMED';
    // ✅ TO 자체가 장기인지 확인 (Application 기준 X)
    final isLongTerm = widget.toItem.to.isLongTerm;

    return SizedBox(
      width: ResponsiveHelper.spacing(context, 32),
      height: ResponsiveHelper.spacing(context, 32),
      child: PopupMenuButton<String>(
        icon: Icon(
          Icons.more_vert,
          size: ResponsiveHelper.iconSize(context, 20),
          color: AppColors.grey600,
        ),
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      onSelected: (value) => _handleMenuAction(value, item),
      itemBuilder: (context) => [
        // 상세보기 (공통)
        PopupMenuItem<String>(
          value: 'detail',
          child: Row(
            children: [
              Icon(Icons.person_outline, size: ResponsiveHelper.iconSize(context, 18), color: AppColors.grey700),
              SizedBox(width: ResponsiveHelper.spacing(context, 12)),
              Text('상세보기', style: ResponsiveHelper.bodyStyle(context)),
            ],
          ),
        ),
        
        // 파트변경 (공통)
        PopupMenuItem<String>(
          value: 'change_part',
          child: Row(
            children: [
              Icon(Icons.swap_horiz, size: ResponsiveHelper.iconSize(context, 18), color: AppColors.info),
              SizedBox(width: ResponsiveHelper.spacing(context, 12)),
              Text('파트변경', style: ResponsiveHelper.bodyStyle(context)),
            ],
          ),
        ),
        
        // 대기중일 때: 승인/거절
        if (isPending) ...[
          const PopupMenuDivider(),
          PopupMenuItem<String>(
            value: 'approve',
            child: Row(
              children: [
                Icon(Icons.check_circle_outline, size: ResponsiveHelper.iconSize(context, 18), color: AppColors.success),
                SizedBox(width: ResponsiveHelper.spacing(context, 12)),
                Text('승인', style: ResponsiveHelper.bodyStyle(context, color: AppColors.success)),
              ],
            ),
          ),
          PopupMenuItem<String>(
            value: 'reject',
            child: Row(
              children: [
                Icon(Icons.cancel_outlined, size: ResponsiveHelper.iconSize(context, 18), color: AppColors.error),
                SizedBox(width: ResponsiveHelper.spacing(context, 12)),
                Text('거절', style: ResponsiveHelper.bodyStyle(context, color: AppColors.error)),
              ],
            ),
          ),
        ],
        
        // 확정자일 때
        if (isConfirmed) ...[
          const PopupMenuDivider(),
          if (isLongTerm) ...[
            // 장기: 근무 시작 전이면 확정취소도 가능
            if (!_hasWorkStarted()) ...[
              PopupMenuItem<String>(
                value: 'cancel_confirmation',
                child: Row(
                  children: [
                    Icon(Icons.cancel_outlined, size: ResponsiveHelper.iconSize(context, 18), color: AppColors.error),
                    SizedBox(width: ResponsiveHelper.spacing(context, 12)),
                    Text('확정취소', style: ResponsiveHelper.bodyStyle(context, color: AppColors.error)),
                  ],
                ),
              ),
            ],
            // 장기: 고정근무 관리 (항상)
            PopupMenuItem<String>(
              value: 'fixed_worker_management',
              child: Row(
                children: [
                  Icon(Icons.settings, size: ResponsiveHelper.iconSize(context, 18), color: AppColors.longTermDark),
                  SizedBox(width: ResponsiveHelper.spacing(context, 12)),
                  Text('고정근무 관리', style: ResponsiveHelper.bodyStyle(context, color: AppColors.longTermDark)),
                ],
              ),
            ),
          ] else ...[
            // 단기: 확정취소
            PopupMenuItem<String>(
              value: 'cancel_confirmation',
              child: Row(
                children: [
                  Icon(Icons.cancel_outlined, size: ResponsiveHelper.iconSize(context, 18), color: AppColors.error),
                  SizedBox(width: ResponsiveHelper.spacing(context, 12)),
                  Text('확정취소', style: ResponsiveHelper.bodyStyle(context, color: AppColors.error)),
                ],
              ),
            ),
          ],
        ],
      ],
      ),
    );
  }

  /// 메뉴 액션 처리
  Future<void> _handleMenuAction(String action, Map<String, dynamic> item) async {
    switch (action) {
      case 'detail':
        _showApplicantDetail(item);
        break;
      case 'change_part':
        _showChangeWorkPartDialog(item);
        break;
      case 'approve':
        _approveApplication(item);
        break;
      case 'reject':
        _rejectApplication(item);
        break;
      case 'cancel_confirmation':
        _cancelConfirmation(item);
        break;
      case 'fixed_worker_management':
        _openFixedWorkerManagement();
        break;
    }
  }

  /// 파트변경 다이얼로그
  Future<void> _showChangeWorkPartDialog(Map<String, dynamic> item) async {
    final app = item['application'] as ApplicationModel;
    final user = item['user'] as UserModel?;
    final workDetails = widget.toItem.workDetails;
    
    // 현재 파트 제외한 다른 파트 목록
    final otherWorkDetails = workDetails.where((w) => w.workType != widget.work.workType).toList();
    
    if (otherWorkDetails.isEmpty) {
      ToastHelper.showWarning('변경 가능한 다른 파트가 없습니다');
      return;
    }

    final selectedWorkType = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.swap_horiz, color: Theme.of(context).primaryColor),
            SizedBox(width: ResponsiveHelper.spacing(context, 8)),
            Text('파트변경', style: ResponsiveHelper.titleStyle(context)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${user?.name ?? '지원자'}님의 파트를 변경합니다.',
              style: ResponsiveHelper.bodyStyle(context, color: AppColors.grey600),
            ),
            SizedBox(height: ResponsiveHelper.spacing(context, 8)),
            Container(
              padding: EdgeInsets.symmetric(
                horizontal: ResponsiveHelper.spacing(context, 12),
                vertical: ResponsiveHelper.spacing(context, 8),
              ),
              decoration: BoxDecoration(
                color: AppColors.grey100,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Text('현재: ', style: ResponsiveHelper.bodyStyle(context, color: AppColors.grey600)),
                  Text(
                    widget.work.workType,
                    style: ResponsiveHelper.bodyStyle(context).copyWith(fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
            SizedBox(height: ResponsiveHelper.spacing(context, 16)),
            Text(
              '변경할 파트 선택',
              style: ResponsiveHelper.subtitleStyle(context).copyWith(fontWeight: FontWeight.bold),
            ),
            SizedBox(height: ResponsiveHelper.spacing(context, 8)),
            ...otherWorkDetails.map((work) => Padding(
              padding: EdgeInsets.only(bottom: ResponsiveHelper.spacing(context, 8)),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => Navigator.pop(context, work.workType),
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: ResponsiveHelper.cardPadding(context),
                    decoration: BoxDecoration(
                      border: Border.all(color: AppColors.border),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        WorkTypeIcon.buildWithBackground(
                          iconString: work.workTypeIcon,
                          backgroundColor: work.workTypeBackgroundColor,
                          size: ResponsiveHelper.iconSize(context, 20),
                          containerSize: ResponsiveHelper.spacing(context, 36),
                        ),
                        SizedBox(width: ResponsiveHelper.spacing(context, 12)),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                work.workType,
                                style: ResponsiveHelper.bodyStyle(context).copyWith(fontWeight: FontWeight.w600),
                              ),
                              Text(
                                '${work.startTime}~${work.endTime} | ${work.formattedWage}',
                                style: ResponsiveHelper.smallStyle(context, color: AppColors.grey600),
                              ),
                            ],
                          ),
                        ),
                        Icon(Icons.arrow_forward_ios, size: ResponsiveHelper.iconSize(context, 14), color: AppColors.grey400),
                      ],
                    ),
                  ),
                ),
              ),
            )),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('취소', style: TextStyle(color: AppColors.grey600)),
          ),
        ],
      ),
    );

    if (selectedWorkType == null) return;

    // 파트 변경 처리
    try {
      final userProvider = context.read<UserProvider>();
      final adminUID = userProvider.currentUser?.uid ?? '';
      final selectedWork = otherWorkDetails.firstWhere((w) => w.workType == selectedWorkType);

      await _firestoreService.changeApplicationWorkType(
        applicationId: app.id,
        newWorkType: selectedWorkType,
        newWage: selectedWork.wage,
        adminUID: adminUID,
      );
      ToastHelper.showSuccess('${user?.name ?? '지원자'}님의 파트가 $selectedWorkType(으)로 변경되었습니다');
      await _loadApplicants();
      _updateLocalStats();
    } catch (e) {
      ToastHelper.showError('파트 변경에 실패했습니다');
    }
  }

  /// 개별 승인
  Future<void> _approveApplication(Map<String, dynamic> item) async {
    final app = item['application'] as ApplicationModel;
    final user = item['user'] as UserModel?;

    final confirm = await DialogHelper.showConfirm(
      context,
      title: '지원 승인',
      message: '${user?.name ?? '지원자'}님을 승인하시겠습니까?',
      confirmText: '승인',
    );

    if (confirm != true) return;

    try {
      final userProvider = context.read<UserProvider>();
      final adminUID = userProvider.currentUser?.uid;

      await _firestoreService.updateApplicationStatus(
        applicationId: app.id,
        status: 'CONFIRMED',
        confirmedBy: adminUID,
      );

      ToastHelper.showSuccess('${user?.name ?? '지원자'}님이 승인되었습니다');
      await _loadApplicants();
      _updateLocalStats();
    } catch (e) {
      ToastHelper.showError('승인 처리 중 오류가 발생했습니다');
    }
  }

  /// 개별 거절
  Future<void> _rejectApplication(Map<String, dynamic> item) async {
    final app = item['application'] as ApplicationModel;
    final user = item['user'] as UserModel?;

    final reason = await DialogHelper.showRejectReasonPicker(
      context,
      title: '지원 거절',
      message: '${user?.name ?? '지원자'}님을 거절합니다.\n거절 사유를 선택해주세요.',
    );

    if (reason == null) return;

    try {
      final userProvider = context.read<UserProvider>();
      final adminUID = userProvider.currentUser?.uid;

      await _firestoreService.updateApplicationStatus(
        applicationId: app.id,
        status: 'REJECTED',
        rejectedBy: adminUID,
        message: reason,
      );

      ToastHelper.showSuccess('${user?.name ?? '지원자'}님이 거절되었습니다');
      await _loadApplicants();
      _updateLocalStats();
    } catch (e) {
      ToastHelper.showError('거절 처리 중 오류가 발생했습니다');
    }
  }

  /// 확정취소 (단기)
  Future<void> _cancelConfirmation(Map<String, dynamic> item) async {
    final app = item['application'] as ApplicationModel;
    final user = item['user'] as UserModel?;

    final reason = await DialogHelper.showRejectReasonPicker(
      context,
      title: '확정 취소',
      message: '${user?.name ?? '근무자'}님의 확정을 취소합니다.\n취소 사유를 선택해주세요.',
    );

    if (reason == null) return;

    try {
      final userProvider = context.read<UserProvider>();
      final adminUID = userProvider.currentUser?.uid;

      await _firestoreService.updateApplicationStatus(
        applicationId: app.id,
        status: 'REJECTED',
        rejectedBy: adminUID,
        message: reason,
      );

      ToastHelper.showSuccess('${user?.name ?? '근무자'}님의 확정이 취소되었습니다');
      await _loadApplicants();
      _updateLocalStats();
    } catch (e) {
      ToastHelper.showError('확정 취소 중 오류가 발생했습니다');
    }
  }

  /// 고정근무 관리 다이얼로그 열기 (장기)
  void _openFixedWorkerManagement() {
    Navigator.pop(context); // 현재 다이얼로그 닫기
    
    showDialog(
      context: context,
      builder: (context) => FixedWorkerManagementDialog(
        businessId: widget.toItem.to.businessId,
        onChanged: () {
          widget.onChanged();
        },
      ),
    );
  }

  /// 지원자 상세 보기 - 공통 위젯 사용
  void _showApplicantDetail(Map<String, dynamic> item) async{
    final app = item['application'] as ApplicationModel;
    final user = item['user'] as UserModel?;
    
    if (user == null) {
      ToastHelper.showError('사용자 정보를 불러올 수 없습니다');
      return;
    }

    final isPending = app.status == 'PENDING';
    final isConfirmed = app.status == 'CONFIRMED';

    final changed = await WorkerDetailDialog.show(
      context: context,
      user: user,
      application: app,
      toItem: widget.toItem,
      businessId: widget.toItem.to.businessId,
      isConfirmed: isConfirmed,
      showApprovalButtons: isPending,
      onStatusChanged: () async {
        await _loadApplicants();
        _updateLocalStats();
      },
    );
    

    
    // 신분증 상태만 업데이트 (전체 새로고침 X)
    if (changed != false) {
      final userProvider = context.read<UserProvider>();
      final currentUserId = userProvider.currentUser?.uid ?? '';
      
      final newStatus = await IdCardHelper.loadStatusBatch(
        firestoreService: _firestoreService,
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

  /// 하단 액션 바
  Widget _buildBottomBar(BuildContext context) {
    final hasSelection = _selectedIds.isNotEmpty;
    
    return Container(
      padding: ResponsiveHelper.cardPadding(context),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AppColors.border)),
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(20),
          bottomRight: Radius.circular(20),
        ),
      ),
      child: Row(
        children: [
          // 선택 수
          Text(
            '선택: ${_selectedIds.length}명',
            style: ResponsiveHelper.bodyStyle(context, color: AppColors.grey600),
          ),
          const Spacer(),
          
          // 거절 버튼
          LoadingButton.outlined(
            text: '거절',
            icon: Icons.close,
            borderColor: AppColors.error,
            foregroundColor: AppColors.error,
            disabled: !hasSelection,
            onPressed: () async => await _batchReject(),
          ),
          SizedBox(width: ResponsiveHelper.spacing(context, 8)),
          
          // 승인 버튼
          LoadingButton.success(
            text: '승인',
            icon: Icons.check,
            disabled: !hasSelection,
            onPressed: () async => await _batchApprove(),
          ),
        ],
      ),
    );
  }

  /// 일괄 승인
  Future<void> _batchApprove() async {
    if (_selectedIds.isEmpty || _isProcessing) return;

    // 인원 체크
    final stats = widget.toItem.workDetailStats?[widget.work.workType];
    final confirmed = stats?['confirmed'] ?? 0;
    final remaining = widget.work.requiredCount - confirmed;

    if (_selectedIds.length > remaining) {
      ToastHelper.showWarning('필요 인원(${widget.work.requiredCount}명)을 초과합니다. 현재 $confirmed명 확정, $remaining명 추가 가능');
      return;
    }

    final confirm = await DialogHelper.showConfirm(
      context,
      title: '일괄 승인',
      message: '선택한 ${_selectedIds.length}명을 승인하시겠습니까?',
      confirmText: '승인',
    );

    if (confirm != true) return;

    setState(() => _isProcessing = true);

    try {
      final userProvider = context.read<UserProvider>();
      final adminUID = userProvider.currentUser?.uid;
      
      for (final appId in _selectedIds) {
        await _firestoreService.updateApplicationStatus(
          applicationId: appId,
          status: 'CONFIRMED',
          confirmedBy: adminUID,
        );
      }

      ToastHelper.showSuccess('${_selectedIds.length}명이 승인되었습니다');
      _selectedIds.clear();
      await _loadApplicants();
      await _updateLocalStats();
    } catch (e) {
      ToastHelper.showError('승인 처리 중 오류가 발생했습니다');
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  /// 일괄 거절
  Future<void> _batchReject() async {
    if (_selectedIds.isEmpty || _isProcessing) return;

    final reason = await DialogHelper.showRejectReasonPicker(
      context,
      title: '일괄 거절',
      message: '선택한 ${_selectedIds.length}명을 거절합니다.\n거절 사유를 선택해주세요.',
    );

    if (reason == null) return;

    setState(() => _isProcessing = true);

    try {
      final userProvider = context.read<UserProvider>();
      final adminUID = userProvider.currentUser?.uid;
      
      for (final appId in _selectedIds) {
        await _firestoreService.updateApplicationStatus(
          applicationId: appId,
          status: 'REJECTED',
          rejectedBy: adminUID,
          message: reason,
        );
      }

      ToastHelper.showSuccess('${_selectedIds.length}명이 거절되었습니다');
      _selectedIds.clear();
      await _loadApplicants();
      await _updateLocalStats();
    } catch (e) {
      ToastHelper.showError('거절 처리 중 오류가 발생했습니다');
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }
  /// 로컬 통계 갱신 (부모 toItem의 workDetailStats 업데이트)
  /// ✅ 자동취소로 인해 다른 업무의 통계도 변경될 수 있으므로 전체 업무 통계 갱신
  Future<void> _updateLocalStats() async {
    _hasChanges = true;  // ⭐ 변경 표시
    
    try {
      // ✅ 전체 업무의 지원서를 서버에서 다시 가져오기
      final allApplications = await _firestoreService.getApplicationsByTOId(
        widget.toItem.to.id,
      );
      
      // 업무별 통계 계산
      final Map<String, Map<String, int>> newStats = {};
      
      for (final work in widget.toItem.workDetails) {
        int pending = 0;
        int confirmed = 0;
        
        for (final app in allApplications) {
          if (app.selectedWorkType == work.workType &&
              app.startTime == work.startTime &&
              app.endTime == work.endTime) {
            if (app.status == 'PENDING') pending++;
            if (app.status == 'CONFIRMED') confirmed++;
          }
        }
        
        newStats[work.id] = {
          'pending': pending,
          'confirmed': confirmed,
        };
      }
      
      widget.toItem.workDetailStats = newStats;
      
    } catch (e) {
      // 실패 시 현재 업무만 업데이트
      int pending = 0;
      int confirmed = 0;
      
      for (var item in _applicants) {
        final app = item['application'] as ApplicationModel;
        if (app.status == 'PENDING') pending++;
        if (app.status == 'CONFIRMED') confirmed++;
      }
      
      widget.toItem.workDetailStats ??= {};
      widget.toItem.workDetailStats![widget.work.id] = {
        'pending': pending,
        'confirmed': confirmed,
      };
    }
  }
  /// 근무가 이미 시작됐는지 확인
  bool _hasWorkStarted() {
    final today = DateTime.now();
    final workStartDate = widget.toItem.to.date;
    return !workStartDate.isAfter(today);  // 시작일 <= 오늘
  }
}
