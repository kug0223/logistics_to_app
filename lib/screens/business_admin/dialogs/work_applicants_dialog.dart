// lib/screens/business_admin/dialogs/work_applicants_dialog.dart
// 업무별 지원자 관리 다이얼로그 - 개선된 버전

import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../../models/core/application_model.dart';
import '../../../models/core/business_model.dart';
import '../../../models/core/employment_contract_model.dart';
import '../../../models/core/work_detail_model.dart';
import '../../../models/core/user_model.dart';
import '../../../services/contract_service.dart';
import '../../../services/firestore_service.dart';
import '../../../providers/user_provider.dart';
import '../../../utils/loading_state_mixin.dart';
import '../../../utils/toast_helper.dart';
import '../../../utils/responsive_helper.dart';
import '../../../utils/dialog_helper.dart';
import '../../../widgets/work_type_icon.dart';
import '../../../widgets/dialogs/worker_detail_dialog.dart';
import '../../../widgets/dialogs/contract_template_selector_dialog.dart';
import '../../../models/ui/admin_to_list_ui_models.dart';
import '../../../theme/app_colors.dart';
import '../../../widgets/common/app_checkbox.dart';
import '../../../widgets/dialogs/styled_dialog.dart';
import '../../../utils/id_card_helper.dart';
import 'fixed_worker_management_dialog.dart';
import '../../../utils/format_helper.dart';
import '../../../utils/trust_score_helper.dart';
import '../../../models/core/monthly_review_model.dart';
import '../../../services/monthly_review_service.dart';
import '../../../screens/contract/contract_sign_screen.dart' show ContractTemplateWidget;
import '../../../widgets/common/loading_widget.dart';

/// 다이얼로그 결과
class WorkApplicantsDialogResult {
  final bool hasChanges;
  final Set<String> affectedTOIds;  // 충돌로 영향받은 다른 TO ID
  
  const WorkApplicantsDialogResult({
    this.hasChanges = false,
    this.affectedTOIds = const <String>{},
  });
}

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

class _WorkApplicantsDialogState extends State<WorkApplicantsDialog>
    with LoadingStateMixin {
  final FirestoreService _firestoreService = FirestoreService();

  List<Map<String, dynamic>> _applicants = [];
  // 통계 계산용 전체 앱 목록 (_loadApplicants에서 캐시, _updateLocalStats에서 재사용)
  List<ApplicationModel> _allApplications = [];

  final Set<String> _selectedIds = {};
  final Set<String> _starredIds = <String>{};
  bool _selectAll = false;
  bool _isBatchMode = false;
  
  // 신분증 상태 맵
  Map<String, String> _idCardStatusMap = {};
  // ⭐ 변경 여부 추적
  bool _hasChanges = false;
  // ✅ 로딩 상태
  bool _isProcessing = false;
  // 신분증 일괄 요청 모드
  bool _isIdCardSelectMode = false;
  final Set<String> _selectedIdCardUserIds = {};
  // ✅ 장기공고 출퇴근 기록 맵 (applicationId -> hasAttendance)
  final Map<String, bool> _hasAttendanceMap = {};
  // 🔥 충돌로 취소된 다른 TO ID 목록
  final Set<String> _affectedOtherTOIds = {};
  // 리뷰 작성 여부 (uid → true=작성완료)
  final Map<String, bool> _reviewWrittenMap = {};

  @override
  void initState() {
    super.initState();
    _loadApplicants();
  }

  /// 지원자 + 사용자 정보 + 신분증 상태 로드
  Future<void> _loadApplicants() => runWithLoading(() async {
      final userProvider = context.read<UserProvider>();
      final currentUserId = userProvider.currentUser?.uid ?? '';

      // 슬롯 기반 TO는 해당 슬롯 지원자만, 아니면 전체 TO 지원자 조회 (대기+확정만)
      final List<ApplicationModel> apps;
      if (widget.toItem.slot != null) {
        apps = await _firestoreService.getApplicationsBySlotId(
          widget.toItem.to.id,
          widget.toItem.slot!.id,
          businessId: widget.toItem.to.businessId,
          statuses: const ['PENDING', 'CONTRACT_PENDING', 'CONFIRMED'],
        );
      } else {
        apps = await _firestoreService.getApplicationsByTOId(
          widget.toItem.to.id,
          businessId: widget.toItem.to.businessId,
          statuses: const ['PENDING', 'CONTRACT_PENDING', 'CONFIRMED'],
        );
      }

      final filtered = apps.where((app) {
        final wdId = app.workDetailId;
        if (wdId != null && wdId.isNotEmpty) {
          // 신규 compositeId 매칭
          if (wdId == widget.work.id) return true;
          // 레거시: workDetailId = workType만 저장된 경우 → 시간으로 추가 확인
          if (wdId == widget.work.workType) {
            return app.startTime == widget.work.startTime &&
                   app.endTime == widget.work.endTime;
          }
          return false;
        }
        // workDetailId 없는 구 데이터 호환
        return app.selectedWorkType == widget.work.workType &&
               app.startTime == widget.work.startTime &&
               app.endTime == widget.work.endTime;
      }).toList();

      // ✅ 1. 중복 제거된 UID 목록 추출
      final uniqueUids = filtered.map((app) => app.uid).toSet().toList();

      // ✅ 2. 사용자 정보 일괄 조회 (캐시 포함)
      final userMap = await _firestoreService.getUsersBatch(uniqueUids);
      
      // ✅ 3. 결과 매핑 (추가 조회 없음)
      final applicantsWithUserInfo = filtered.map((app) {
        return {
          'application': app,
          'user': userMap[app.uid],
        };
      }).toList();
      
      // 성명순 정렬
      applicantsWithUserInfo.sort((a, b) {
        final userA = a['user'] as UserModel?;
        final userB = b['user'] as UserModel?;
        if (userA == null || userB == null) return 0;
        return userA.name.compareTo(userB.name);
      });

      // 신분증 상태 일괄 조회 (확정자만)
      final confirmedUserIds = applicantsWithUserInfo
          .where((item) {
            final app = item['application'] as ApplicationModel;
            return item['user'] != null &&
                (app.status == AppStatus.confirmed || app.status == AppStatus.contractPending);
          })
          .map((item) => (item['user'] as UserModel).uid)
          .toList();
      
      final idCardStatusMap = await IdCardHelper.loadStatusBatch(
        firestoreService: _firestoreService,
        requesterId: currentUserId,
        targetUserIds: confirmedUserIds,
      );

      // 리뷰 작성 여부 일괄 확인 (슬롯 날짜가 있는 확정자만)
      final slotDate = widget.toItem.slot?.date;
      if (slotDate != null && confirmedUserIds.isNotEmpty) {
        final businessId = widget.toItem.to.businessId;
        final reviewFutures = confirmedUserIds.map((uid) async {
          final key = MonthlyReviewModel.generateKeyForUser(
            businessId: businessId,
            targetUserId: uid,
            year: slotDate.year,
            month: slotDate.month,
          );
          final exists = await MonthlyReviewService().getReviewById(key);
          return MapEntry(uid, exists != null);
        });
        final reviewEntries = await Future.wait(reviewFutures);
        _reviewWrittenMap.addAll(Map.fromEntries(reviewEntries));
      }

      // ✅ 장기공고인 경우 확정자들의 출퇴근 기록 병렬 확인
      if (widget.toItem.to.isLongTerm) {
        final confirmedApps = applicantsWithUserInfo
            .where((item) {
              final s = (item['application'] as ApplicationModel).status;
              return AppStatus.confirmedStatuses.contains(s);
            })
            .map((item) => item['application'] as ApplicationModel)
            .toList();
        
        if (confirmedApps.isNotEmpty) {
          final attendanceFutures = confirmedApps.map((app) async {
            final hasRecord = await _firestoreService.hasAttendanceRecord(app.id);
            return MapEntry(app.id, hasRecord);
          });
          final attendanceEntries = await Future.wait(attendanceFutures);
          _hasAttendanceMap.addAll(Map.fromEntries(attendanceEntries));
        }
      }

      setState(() {
        _applicants = applicantsWithUserInfo;
        _idCardStatusMap = idCardStatusMap;
        _allApplications = apps; // 통계 계산용 캐시
      });
  }, errorTag: '지원자 목록 로드');


  /// 전체 선택/해제
  void _toggleSelectAll(bool? value) {
    final pendingApps = _applicants
        .where((item) => (item['application'] as ApplicationModel).status == AppStatus.pending)
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
          .where((item) => (item['application'] as ApplicationModel).status == AppStatus.pending)
          .length;
      _selectAll = _selectedIds.length == pendingCount && pendingCount > 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // 상태별 분류
    final pending = _applicants.where((item) =>
      (item['application'] as ApplicationModel).status == AppStatus.pending).toList();
    final confirmed = _applicants.where((item) {
      final s = (item['application'] as ApplicationModel).status;
      return AppStatus.confirmedStatuses.contains(s);
    }).toList();

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          Navigator.pop(context, WorkApplicantsDialogResult(
            hasChanges: _hasChanges,
            affectedTOIds: _affectedOtherTOIds,
          ));
        }
      },
      child: Dialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(ResponsiveHelper.spacing(context, 24)),
        ),
        child: Container(
          constraints: BoxConstraints(
            maxWidth: 500,
            maxHeight: MediaQuery.sizeOf(context).height * 0.88,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.max,
            children: [
              _buildHeader(context, theme),
              _buildStatsBar(context, pending.length, confirmed.length),
              if (pending.isNotEmpty)
                _buildSelectAllRow(context, pending.length),
              Expanded(
                child: isLoading
                    ? const LoadingWidget()
                    : (pending.isEmpty && confirmed.isEmpty)
                        ? _buildEmptyState(context)
                        : _buildApplicantList(context, pending, confirmed),
              ),
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
          colors: [theme.primaryColor, theme.primaryColor.withValues(alpha: 0.8)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(ResponsiveHelper.spacing(context, 24)),
          topRight: Radius.circular(ResponsiveHelper.spacing(context, 24)),
        ),
      ),
      child: Row(
        children: [
          // 업무 아이콘
          WorkTypeIcon.buildWithBackground(
            iconString: widget.work.workTypeIcon,
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
                  '${FormatHelper.formatDate(widget.toItem.slot?.date ?? widget.toItem.to.date)} · ${widget.work.startTime}~${widget.work.endTime} | ${widget.work.formattedWage}',
                  style: ResponsiveHelper.smallStyle(context, color: Colors.white70),
                ),
              ],
            ),
          ),
          
          // 닫기 버튼
          IconButton(
            onPressed: () => Navigator.pop(context, WorkApplicantsDialogResult(
              hasChanges: _hasChanges,
              affectedTOIds: _affectedOtherTOIds,
            )),
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
          width: ResponsiveHelper.spacing(context, 8),
          height: ResponsiveHelper.spacing(context, 8),
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
          if (_isBatchMode) ...[
            AppCheckbox(
              value: _selectAll,
              onTap: () => _toggleSelectAll(!_selectAll),
            ),
            SizedBox(width: ResponsiveHelper.spacing(context, 8)),
            Text('전체 선택', style: ResponsiveHelper.bodyStyle(context)),
            if (_selectedIds.isNotEmpty) ...[
              SizedBox(width: ResponsiveHelper.spacing(context, 8)),
              Container(
                padding: EdgeInsets.symmetric(
                  horizontal: ResponsiveHelper.spacing(context, 8),
                  vertical: ResponsiveHelper.spacing(context, 3),
                ),
                decoration: BoxDecoration(
                  color: Theme.of(context).primaryColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(ResponsiveHelper.spacing(context, 10)),
                ),
                child: Text(
                  '${_selectedIds.length}명',
                  style: ResponsiveHelper.smallStyle(context, color: Theme.of(context).primaryColor),
                ),
              ),
            ],
          ],
          const Spacer(),
          // 일괄선택 토글 버튼
          Material(
            color: _isBatchMode
                ? Theme.of(context).primaryColor.withValues(alpha: 0.1)
                : AppColors.grey100,
            borderRadius: BorderRadius.circular(ResponsiveHelper.spacing(context, 8)),
            child: InkWell(
              onTap: () => setState(() {
                _isBatchMode = !_isBatchMode;
                if (!_isBatchMode) {
                  _selectedIds.clear();
                  _selectAll = false;
                }
              }),
              borderRadius: BorderRadius.circular(ResponsiveHelper.spacing(context, 8)),
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: ResponsiveHelper.spacing(context, 10),
                  vertical: ResponsiveHelper.spacing(context, 6),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _isBatchMode ? Icons.close : Icons.checklist,
                      size: ResponsiveHelper.iconSize(context, 14),
                      color: _isBatchMode
                          ? Theme.of(context).primaryColor
                          : AppColors.grey600,
                    ),
                    SizedBox(width: ResponsiveHelper.spacing(context, 4)),
                    Text(
                      _isBatchMode ? '취소' : '일괄선택',
                      style: ResponsiveHelper.smallStyle(
                        context,
                        color: _isBatchMode
                            ? Theme.of(context).primaryColor
                            : AppColors.grey600,
                      ).copyWith(fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 빈 상태
  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.people_outline, size: ResponsiveHelper.iconSize(context, 64), color: AppColors.grey300),
          SizedBox(height: ResponsiveHelper.spacing(context, 16)),
          Text(
            '지원자가 없습니다',
            style: ResponsiveHelper.bodyStyle(context, color: AppColors.grey500),
          ),
        ],
      ),
    );
  }

  /// 지원자 목록
  List<Map<String, dynamic>> _sortedPending(List<Map<String, dynamic>> pending) {
    final sorted = List<Map<String, dynamic>>.from(pending);
    sorted.sort((a, b) {
      final aId = (a['application'] as ApplicationModel).id;
      final bId = (b['application'] as ApplicationModel).id;
      final aStarred = _starredIds.contains(aId) ? 0 : 1;
      final bStarred = _starredIds.contains(bId) ? 0 : 1;
      return aStarred.compareTo(bStarred);
    });
    return sorted;
  }

  Widget _buildApplicantList(BuildContext context, List<Map<String, dynamic>> pending, List<Map<String, dynamic>> confirmed) {
    return SingleChildScrollView(
      padding: ResponsiveHelper.cardPadding(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 대기 중 섹션 (별 표시 항목 상단 고정)
            if (pending.isNotEmpty) ...[
              _buildSectionHeader(context, '대기 중', pending.length, AppColors.warning),
              SizedBox(height: ResponsiveHelper.spacing(context, 8)),
              ..._sortedPending(pending).asMap().entries.map((entry) =>
                  _buildApplicantCard(context, entry.value, entry.key + 1, isPending: true)),
              SizedBox(height: ResponsiveHelper.spacing(context, 16)),
            ],

            // 확정 섹션
            if (confirmed.isNotEmpty) ...[
              _buildSectionHeader(context, '확정', confirmed.length, AppColors.success),
              Builder(builder: (context) {
                final requestableCount = _applicants.where((item) {
                  final app = item['application'] as ApplicationModel;
                  final user = item['user'] as UserModel?;
                  if ((app.status != AppStatus.confirmed && app.status != AppStatus.contractPending) || user == null) return false;
                  return IdCardHelper.isRequestable(_idCardStatusMap[user.uid] ?? 'none');
                }).length;
                if (requestableCount == 0) return const SizedBox.shrink();
                return _buildIdCardRequestSection(context, requestableCount);
              }),
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
  /// 신분증 일괄 요청 섹션 (confirmed_list_dialog와 동일한 패턴)
  Widget _buildIdCardRequestSection(BuildContext context, int requestableCount) {
    return Container(
      margin: EdgeInsets.only(top: ResponsiveHelper.spacing(context, 8)),
      padding: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 16),
        vertical: ResponsiveHelper.spacing(context, 10),
      ),
      decoration: BoxDecoration(
        color: _isIdCardSelectMode ? AppColors.infoBg : Colors.white,
        borderRadius: BorderRadius.circular(ResponsiveHelper.spacing(context, 12)),
        border: Border.all(color: _isIdCardSelectMode ? AppColors.info : AppColors.border),
      ),
      child: Row(
        children: [
          Icon(Icons.badge, size: ResponsiveHelper.iconSize(context, 18), color: AppColors.info),
          SizedBox(width: ResponsiveHelper.spacing(context, 8)),
          Expanded(
            child: Text(
              _isIdCardSelectMode
                  ? '${_selectedIdCardUserIds.length}명 선택됨'
                  : '미요청 $requestableCount명',
              style: ResponsiveHelper.bodyStyle(context, color: AppColors.infoDark),
            ),
          ),
          if (_isIdCardSelectMode && _selectedIdCardUserIds.isNotEmpty) ...[
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => _batchRequestIdCard(),
                borderRadius: BorderRadius.circular(ResponsiveHelper.spacing(context, 8)),
                child: Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: ResponsiveHelper.spacing(context, 12),
                    vertical: ResponsiveHelper.spacing(context, 6),
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.success,
                    borderRadius: BorderRadius.circular(ResponsiveHelper.spacing(context, 8)),
                  ),
                  child: Text(
                    '요청하기',
                    style: ResponsiveHelper.smallStyle(context, color: Colors.white)
                        .copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ),
            SizedBox(width: ResponsiveHelper.spacing(context, 8)),
          ],
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
              borderRadius: BorderRadius.circular(ResponsiveHelper.spacing(context, 8)),
              child: Container(
                padding: EdgeInsets.symmetric(
                  horizontal: ResponsiveHelper.spacing(context, 12),
                  vertical: ResponsiveHelper.spacing(context, 6),
                ),
                decoration: BoxDecoration(
                  color: _isIdCardSelectMode ? AppColors.grey100 : AppColors.info,
                  borderRadius: BorderRadius.circular(ResponsiveHelper.spacing(context, 8)),
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

  /// 미요청자 전체 선택
  void _selectAllRequestableUsers() {
    _selectedIdCardUserIds.clear();
    for (final item in _applicants) {
      final app = item['application'] as ApplicationModel;
      final user = item['user'] as UserModel?;
      if ((app.status != AppStatus.confirmed && app.status != AppStatus.contractPending) || user == null) continue;

      final status = _idCardStatusMap[user.uid] ?? 'none';
      if (IdCardHelper.isRequestable(status)) {
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

    if (!mounted) return;
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
          width: ResponsiveHelper.spacing(context, 4),
          height: ResponsiveHelper.spacing(context, 20),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(ResponsiveHelper.spacing(context, 2)),
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

  /// 지원자 카드
  Widget _buildApplicantCard(BuildContext context, Map<String, dynamic> item, int index, {required bool isPending}) {
    final app = item['application'] as ApplicationModel;
    final user = item['user'] as UserModel?;
    final idCardStatus = _idCardStatusMap[user?.uid ?? ''] ?? 'none';
    final isSelected = _selectedIds.contains(app.id);
    final isStarred = isPending && _starredIds.contains(app.id);
    final trustScore = TrustScoreHelper.calculate(user);

    Color cardBg = Colors.white;
    Color cardBorder = AppColors.border;
    if (isSelected) {
      cardBg = Theme.of(context).primaryColor.withValues(alpha: 0.05);
      cardBorder = Theme.of(context).primaryColor;
    } else if (isStarred) {
      cardBg = AppColors.amber.withValues(alpha: 0.1); // amber[50] equivalent
      cardBorder = AppColors.amberLight;
    }

    return Container(
      margin: EdgeInsets.only(bottom: ResponsiveHelper.spacing(context, 8)),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(ResponsiveHelper.spacing(context, 12)),
        border: Border.all(color: cardBorder),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: isPending
              ? (_isBatchMode
                  ? () => _toggleSelection(app.id)
                  : () => _showApplicantDetail(item))
              : () => _showApplicantDetail(item),
          borderRadius: BorderRadius.circular(ResponsiveHelper.spacing(context, 12)),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: ResponsiveHelper.spacing(context, 12),
              vertical: ResponsiveHelper.spacing(context, 10),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 신분증 선택모드 (확정자 전용)
                if (!isPending) ...[
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: _isIdCardSelectMode ? ResponsiveHelper.spacing(context, 28) : 0,
                    clipBehavior: Clip.hardEdge,
                    decoration: const BoxDecoration(),
                    child: _isIdCardSelectMode
                        ? Padding(
                            padding: EdgeInsets.only(right: ResponsiveHelper.spacing(context, 8)),
                            child: IdCardHelper.isRequestable(idCardStatus)
                                ? AppCheckbox(
                                    value: _selectedIdCardUserIds.contains(user?.uid ?? ''),
                                    onTap: () => _toggleIdCardSelection(user?.uid ?? ''),
                                    activeColor: AppColors.info,
                                    size: ResponsiveHelper.iconSize(context, 20),
                                  )
                                : AppCheckbox(
                                    value: true,
                                    enabled: false,
                                    size: ResponsiveHelper.iconSize(context, 20),
                                  ),
                          )
                        : const SizedBox.shrink(),
                  ),
                ],

                // 정보 영역 (전체 너비 사용)
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 1줄: 순번 + 이름 + 성별·나이 | 배지/별
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(
                            child: Row(
                              children: [
                                // 일괄선택 모드 선택 아이콘 (슬라이드인)
                                if (isPending) ...[
                                  AnimatedContainer(
                                    duration: const Duration(milliseconds: 200),
                                    width: _isBatchMode ? ResponsiveHelper.spacing(context, 26) : 0,
                                    clipBehavior: Clip.hardEdge,
                                    decoration: const BoxDecoration(),
                                    child: _isBatchMode
                                        ? Padding(
                                            padding: EdgeInsets.only(right: ResponsiveHelper.spacing(context, 6)),
                                            child: AppCheckbox(
                                              value: isSelected,
                                              size: ResponsiveHelper.iconSize(context, 20),
                                            ),
                                          )
                                        : null,
                                  ),
                                ],
                                Text(
                                  '$index.',
                                  style: ResponsiveHelper.smallStyle(context, color: AppColors.grey400)
                                      .copyWith(fontWeight: FontWeight.w700),
                                ),
                                SizedBox(width: ResponsiveHelper.spacing(context, 5)),
                                Flexible(
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Flexible(
                                        child: Text(
                                          user?.name ?? '이름 없음',
                                          style: ResponsiveHelper.bodyStyle(context).copyWith(fontWeight: FontWeight.w700),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      if (user?.gender != null || user?.age != null) ...[
                                        SizedBox(width: ResponsiveHelper.spacing(context, 4)),
                                        Flexible(
                                          child: Text(
                                            '(${user?.gender ?? ''}${user?.age != null ? ' · ${user!.age}세' : ''})',
                                            style: ResponsiveHelper.smallStyle(context, color: AppColors.grey500),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                          if (isPending)
                            GestureDetector(
                              onTap: () => setState(() {
                                if (_starredIds.contains(app.id)) {
                                  _starredIds.remove(app.id);
                                } else {
                                  _starredIds.add(app.id);
                                }
                              }),
                              behavior: HitTestBehavior.opaque,
                              child: Padding(
                                padding: EdgeInsets.only(
                                  left: ResponsiveHelper.spacing(context, 14),
                                  top: ResponsiveHelper.spacing(context, 10),
                                  bottom: ResponsiveHelper.spacing(context, 10),
                                ),
                                child: Icon(
                                  isStarred ? Icons.star_rounded : Icons.star_border_rounded,
                                  size: ResponsiveHelper.iconSize(context, 18),
                                  color: isStarred ? AppColors.amber : AppColors.grey300,
                                ),
                              ),
                            )
                          else
                            _buildReviewBadge(context, user?.uid),
                        ],
                      ),
                      SizedBox(height: ResponsiveHelper.spacing(context, 5)),

                      // 2줄: 전화번호 · 지원시간
                      Row(
                        children: [
                          Icon(Icons.phone, size: ResponsiveHelper.iconSize(context, 12), color: AppColors.grey400),
                          SizedBox(width: ResponsiveHelper.spacing(context, 4)),
                          Text(
                            user?.phone != null ? FormatHelper.formatPhone(user!.phone!) : '-',
                            style: ResponsiveHelper.smallStyle(context, color: AppColors.grey600),
                          ),
                          SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                          Text('·', style: ResponsiveHelper.smallStyle(context, color: AppColors.grey300)),
                          SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                          Icon(Icons.access_time, size: ResponsiveHelper.iconSize(context, 12), color: AppColors.grey400),
                          SizedBox(width: ResponsiveHelper.spacing(context, 4)),
                          Text(
                            _formatAppliedTime(app.appliedAt),
                            style: ResponsiveHelper.smallStyle(context, color: AppColors.grey500),
                          ),
                        ],
                      ),
                      SizedBox(height: ResponsiveHelper.spacing(context, 4)),

                      // 3줄: 신뢰도 + 평점 + 신분증(확정자)
                      Row(
                        children: [
                          _buildTrustBadge(context, trustScore),
                          if (user != null && user.averageRating > 0) ...[
                            SizedBox(width: ResponsiveHelper.spacing(context, 6)),
                            Icon(Icons.star, size: ResponsiveHelper.iconSize(context, 12), color: AppColors.amber),
                            SizedBox(width: ResponsiveHelper.spacing(context, 2)),
                            Text(
                              user.averageRating.toStringAsFixed(1),
                              style: ResponsiveHelper.smallStyle(context, color: AppColors.grey600),
                            ),
                          ],
                          if (!isPending) ...[
                            SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                            IdCardHelper.buildStatusBadge(context, idCardStatus),
                          ],
                        ],
                      ),

                      // 자기소개
                      if (app.applicationMessage?.isNotEmpty == true) ...[
                        SizedBox(height: ResponsiveHelper.spacing(context, 6)),
                        Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: ResponsiveHelper.spacing(context, 8),
                            vertical: ResponsiveHelper.spacing(context, 4),
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.grey50,
                            borderRadius: BorderRadius.circular(ResponsiveHelper.spacing(context, 6)),
                          ),
                          child: Text(
                            app.applicationMessage!,
                            style: ResponsiveHelper.smallStyle(context, color: AppColors.grey600),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],

                      // 장기 근무 정보
                      if (widget.toItem.to.isLongTerm && app.isLongTermApplication && app.workPeriodDisplay.isNotEmpty) ...[
                        SizedBox(height: ResponsiveHelper.spacing(context, 5)),
                        Row(
                          children: [
                            Icon(
                              Icons.date_range,
                              size: ResponsiveHelper.iconSize(context, 12),
                              color: app.desiredStartDate != null ? Theme.of(context).primaryColor : AppColors.grey500,
                            ),
                            SizedBox(width: ResponsiveHelper.spacing(context, 4)),
                            Flexible(
                              child: Text(
                                app.desiredStartDate != null
                                    ? '희망: ${app.desiredStartDate!.month}/${app.desiredStartDate!.day}~ (${app.workEndDate!.month}/${app.workEndDate!.day}까지)'
                                    : '장기: ${app.workPeriodDisplay}',
                                style: ResponsiveHelper.smallStyle(
                                  context,
                                  color: app.desiredStartDate != null ? Theme.of(context).primaryColor : AppColors.grey600,
                                ).copyWith(
                                  fontWeight: app.desiredStartDate != null ? FontWeight.w600 : FontWeight.normal,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ],

                      // 확정자 액션 버튼 (파트변경 / 확정취소 or 고정근무 관리) — 일괄선택 모드에서는 숨김
                      if (!isPending && !_isBatchMode) ...[
                        SizedBox(height: ResponsiveHelper.spacing(context, 8)),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            _buildActionButton(
                              context,
                              label: '파트변경',
                              icon: Icons.swap_horiz,
                              bgColor: AppColors.infoBg,
                              textColor: AppColors.info,
                              onTap: () => _showChangeWorkPartDialog(item),
                            ),
                            SizedBox(width: ResponsiveHelper.spacing(context, 12)),
                            if (widget.toItem.to.isLongTerm && (_hasAttendanceMap[app.id] ?? false))
                              _buildActionButton(
                                context,
                                label: '고정근무 관리',
                                icon: Icons.settings,
                                bgColor: AppColors.longTermBg,
                                textColor: AppColors.longTermDark,
                                onTap: _openFixedWorkerManagement,
                              )
                            else
                              _buildActionButton(
                                context,
                                label: '확정취소',
                                icon: Icons.cancel_outlined,
                                bgColor: AppColors.errorBg,
                                textColor: AppColors.error,
                                onTap: () => _cancelConfirmation(item),
                              ),
                          ],
                        ),
                      ],

                      // 대기 중 액션 버튼 (파트변경 / 거절 / 승인) — 일괄선택 모드에서는 숨김
                      if (isPending && !_isBatchMode) ...[
                        SizedBox(height: ResponsiveHelper.spacing(context, 8)),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            _buildActionButton(
                              context,
                              label: '파트변경',
                              icon: Icons.swap_horiz,
                              bgColor: AppColors.infoBg,
                              textColor: AppColors.info,
                              onTap: () => _showChangeWorkPartDialog(item),
                            ),
                            SizedBox(width: ResponsiveHelper.spacing(context, 12)),
                            _buildActionButton(
                              context,
                              label: '거절',
                              icon: Icons.close,
                              bgColor: AppColors.errorBg,
                              textColor: AppColors.error,
                              onTap: () => _rejectApplication(item),
                            ),
                            SizedBox(width: ResponsiveHelper.spacing(context, 12)),
                            _buildActionButton(
                              context,
                              label: '승인',
                              icon: Icons.check,
                              bgColor: AppColors.successBg,
                              textColor: AppColors.successDark,
                              onTap: () => _approveApplication(item),
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
      ),
    );
  }

  Widget _buildActionButton(
    BuildContext context, {
    required String label,
    required IconData icon,
    required Color bgColor,
    required Color textColor,
    required VoidCallback onTap,
  }) {
    return Material(
      color: bgColor,
      borderRadius: BorderRadius.circular(ResponsiveHelper.spacing(context, 8)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(ResponsiveHelper.spacing(context, 8)),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: ResponsiveHelper.spacing(context, 14),
            vertical: ResponsiveHelper.spacing(context, 6),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: ResponsiveHelper.iconSize(context, 13), color: textColor),
              SizedBox(width: ResponsiveHelper.spacing(context, 4)),
              Text(
                label,
                style: ResponsiveHelper.smallStyle(context, color: textColor)
                    .copyWith(fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      ),
    );
  }

/// 리뷰 작성 여부 배지
  Widget _buildReviewBadge(BuildContext context, String? uid) {
    if (uid == null || !_reviewWrittenMap.containsKey(uid)) {
      return const SizedBox.shrink();
    }
    final written = _reviewWrittenMap[uid]!;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 5),
        vertical: ResponsiveHelper.spacing(context, 2),
      ),
      decoration: BoxDecoration(
        color: written ? AppColors.successBg : AppColors.warningBg,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            written ? Icons.rate_review : Icons.rate_review_outlined,
            size: ResponsiveHelper.iconSize(context, 10),
            color: written ? AppColors.successDark : AppColors.warningDark,
          ),
          SizedBox(width: ResponsiveHelper.spacing(context, 2)),
          Text(
            written ? '리뷰완료' : '리뷰미작성',
            style: ResponsiveHelper.tinyStyle(
              context,
              color: written ? AppColors.successDark : AppColors.warningDark,
            ),
          ),
        ],
      ),
    );
  }

/// 신뢰도 배지 (높음/보통/주의 3단계)
  Widget _buildTrustBadge(BuildContext context, int score) {
    // 80+: 초록, 40~79: 회색, 40 미만: 빨강
    final Color color;
    final Color bgColor;
    final bool isLow = score < 40;
    
    if (score >= 70) {
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
        borderRadius: BorderRadius.circular(ResponsiveHelper.spacing(context, 8)),
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
            '신뢰$score',
            style: ResponsiveHelper.tinyStyle(context, color: color).copyWith(
              fontWeight: FontWeight.w600,
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
  /// 파트변경 다이얼로그
  Future<void> _showChangeWorkPartDialog(Map<String, dynamic> item) async {
    final app = item['application'] as ApplicationModel;
    final user = item['user'] as UserModel?;
    final workDetails = widget.toItem.workDetails;
    
    // 현재 파트 제외한 다른 파트 목록 (id 기반 비교 — workType 이름 중복 방지)
    final otherWorkDetails = workDetails.where((w) => w.id != widget.work.id).toList();
    
    if (otherWorkDetails.isEmpty) {
      ToastHelper.showWarning('변경 가능한 다른 파트가 없습니다');
      return;
    }

    final selectedWorkId = await showDialog<String>(
      context: context,
      builder: (context) => StyledDialog(
        title: '파트변경',
        icon: Icons.swap_horiz,
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
                borderRadius: BorderRadius.circular(ResponsiveHelper.spacing(context, 8)),
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
                  onTap: () async {
                    final confirmed = await DialogHelper.showConfirm(
                      context,
                      title: '파트 변경',
                      message: '${user?.name ?? '지원자'}님을\n${widget.work.workType} → ${work.workType}(으)로\n변경하시겠습니까?',
                      confirmText: '변경',
                    );
                    if (confirmed == true && context.mounted) {
                      Navigator.pop(context, work.id);
                    }
                  },
                  borderRadius: BorderRadius.circular(ResponsiveHelper.spacing(context, 12)),
                  child: Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: ResponsiveHelper.spacing(context, 12),
                      vertical: ResponsiveHelper.spacing(context, 10),
                    ),
                    decoration: BoxDecoration(
                      border: Border.all(color: AppColors.border),
                      borderRadius: BorderRadius.circular(ResponsiveHelper.spacing(context, 12)),
                    ),
                    child: Row(
                      children: [
                        WorkTypeIcon.buildWithBackground(
                          iconString: work.workTypeIcon,
                          backgroundColor: work.workTypeBackgroundColor,
                          size: ResponsiveHelper.iconSize(context, 18),
                          containerSize: ResponsiveHelper.spacing(context, 32),
                        ),
                        SizedBox(width: ResponsiveHelper.spacing(context, 10)),
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
                        Icon(Icons.arrow_forward_ios, size: ResponsiveHelper.iconSize(context, 12), color: AppColors.grey300),
                      ],
                    ),
                  ),
                ),
              ),
            )),
          ],
        ),
        actions: [
          StyledDialogButton.cancel(
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );

    if (selectedWorkId == null || !mounted) return;

    // 파트 변경 처리
    try {
      final userProvider = context.read<UserProvider>();
      final adminUID = userProvider.currentUser?.uid ?? '';
      final selectedWork = otherWorkDetails.firstWhere((w) => w.id == selectedWorkId);

      await _firestoreService.changeApplicationWorkType(
        applicationId: app.id,
        newWorkType: selectedWork.workType,
        newWage: selectedWork.wage,
        adminUID: adminUID,
        newWorkDetailId: selectedWork.id,
      );
      ToastHelper.showSuccess('${user?.name ?? '지원자'}님의 파트가 ${selectedWork.workType}(으)로 변경되었습니다');
      await _loadApplicants();
      if (!mounted) return;
      _updateLocalStats();
    } catch (e) {
      ToastHelper.showError('파트 변경에 실패했습니다');
    }
  }

  /// 개별 승인
  Future<void> _approveApplication(Map<String, dynamic> item) async {
    if (_isProcessing) return;
    final app = item['application'] as ApplicationModel;
    final user = item['user'] as UserModel?;
    final userProvider = context.read<UserProvider>();

    // 인원 체크 (일괄 승인과 동일 기준)
    final stats = widget.toItem.workDetailStats?[widget.work.id];
    final confirmedCount = stats?['confirmed'] ?? 0;
    final remaining = widget.work.requiredCount - confirmedCount;
    if (remaining <= 0) {
      ToastHelper.showWarning(
        '필요 인원(${widget.work.requiredCount}명)이 이미 충족되었습니다.',
      );
      return;
    }

    final confirm = await DialogHelper.showConfirm(
      context,
      title: '지원 승인',
      message: '${user?.name ?? '지원자'}님을 승인하시겠습니까?',
      confirmText: '승인',
    );

    if (confirm != true || !mounted) return;

    try {
      final adminUID = userProvider.currentUser?.uid;

      final affectedTOIds = await _firestoreService.updateApplicationStatus(
        applicationId: app.id,
        status: AppStatus.confirmed,
        confirmedBy: adminUID,
      );
      
      // 🔥 충돌로 취소된 TO ID 수집
      if (affectedTOIds.isNotEmpty) {
        _affectedOtherTOIds.addAll(affectedTOIds);
        debugPrint('⚠️ 충돌로 ${affectedTOIds.length}개 TO 영향: $affectedTOIds');
      }

      ToastHelper.showSuccess('${user?.name ?? '지원자'}님이 승인되었습니다');
      await _loadApplicants();
      if (!mounted) return;
      _updateLocalStats();
    } catch (e) {
      ToastHelper.showError('승인 처리 중 오류가 발생했습니다');
    }
  }

  /// 개별 거절
  Future<void> _rejectApplication(Map<String, dynamic> item) async {
    if (_isProcessing) return;
    final app = item['application'] as ApplicationModel;
    final user = item['user'] as UserModel?;
    final userProvider = context.read<UserProvider>();

    final reason = await DialogHelper.showRejectReasonPicker(
      context,
      title: '지원 거절',
      message: '${user?.name ?? '지원자'}님을 거절합니다.\n거절 사유를 선택해주세요.',
    );

    if (reason == null || !mounted) return;

    try {
      final adminUID = userProvider.currentUser?.uid;

      await _firestoreService.updateApplicationStatus(
        applicationId: app.id,
        status: AppStatus.rejected,
        rejectedBy: adminUID,
        message: reason,
      );

      ToastHelper.showSuccess('${user?.name ?? '지원자'}님이 거절되었습니다');
      await _loadApplicants();
      if (!mounted) return;
      _updateLocalStats();
    } catch (e) {
      ToastHelper.showError('거절 처리 중 오류가 발생했습니다');
    }
  }

  /// 확정취소 (단기)
  Future<void> _cancelConfirmation(Map<String, dynamic> item) async {
    if (_isProcessing) return;
    final app = item['application'] as ApplicationModel;
    final user = item['user'] as UserModel?;
    final userProvider = context.read<UserProvider>();

    final reason = await DialogHelper.showRejectReasonPicker(
      context,
      title: '확정 취소',
      message: '${user?.name ?? '근무자'}님의 확정을 취소합니다.\n취소 사유를 선택해주세요.',
    );

    if (reason == null || !mounted) return;

    try {
      final adminUID = userProvider.currentUser?.uid;

      await _firestoreService.cancelConfirmedApplication(
        app.id,
        canceledBy: adminUID,
        cancelReason: reason,
      );

      ToastHelper.showSuccess('${user?.name ?? '근무자'}님의 확정이 취소되었습니다');
      await _loadApplicants();
      if (!mounted) return;
      await _updateLocalStats();
    } catch (e) {
      ToastHelper.showError('확정 취소 중 오류가 발생했습니다');
    }
  }

  /// 고정근무 관리 다이얼로그 열기 (장기)
  void _openFixedWorkerManagement() {
    final businessId = widget.toItem.to.businessId;
    final onChanged = widget.onChanged;
    // 루트 Navigator는 이 다이얼로그가 pop된 후에도 유효
    final rootNav = Navigator.of(context, rootNavigator: true);
    Navigator.of(context).pop();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      showDialog(
        context: rootNav.context,
        builder: (_) => FixedWorkerManagementDialog(
          businessIds: [businessId],
          initialBusinessId: businessId,
          onChanged: onChanged,
        ),
      );
    });
  }

  /// 지원자 상세 보기 - 공통 위젯 사용
  void _showApplicantDetail(Map<String, dynamic> item) async{
    final app = item['application'] as ApplicationModel;
    final user = item['user'] as UserModel?;
    
    if (user == null) {
      ToastHelper.showError('사용자 정보를 불러올 수 없습니다');
      return;
    }

    final isPending = app.status == AppStatus.pending;
    final isConfirmed = app.status == AppStatus.confirmed ||
        app.status == AppStatus.contractPending;

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
    if (changed == true && mounted) {
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
    final bottomRadius = BorderRadius.only(
      bottomLeft: Radius.circular(ResponsiveHelper.spacing(context, 24)),
      bottomRight: Radius.circular(ResponsiveHelper.spacing(context, 24)),
    );

    if (!_isBatchMode) {
      return Container(
        padding: ResponsiveHelper.cardPadding(context),
        decoration: BoxDecoration(
          color: AppColors.grey50,
          border: Border(top: BorderSide(color: AppColors.border)),
          borderRadius: bottomRadius,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              onPressed: () => Navigator.pop(context, WorkApplicantsDialogResult(
                hasChanges: _hasChanges,
                affectedTOIds: _affectedOtherTOIds,
              )),
              child: Text('닫기', style: ResponsiveHelper.bodyStyle(context, color: AppColors.grey600)),
            ),
          ],
        ),
      );
    }

    final hasSelection = _selectedIds.isNotEmpty;
    return Container(
      padding: ResponsiveHelper.cardPadding(context),
      decoration: BoxDecoration(
        color: AppColors.grey50,
        border: Border(top: BorderSide(color: AppColors.border)),
        borderRadius: bottomRadius,
      ),
      child: Row(
        children: [
          Text(
            '선택: ${_selectedIds.length}명',
            style: ResponsiveHelper.bodyStyle(context, color: AppColors.grey600),
          ),
          const Spacer(),
          _buildBottomBarButton(
            context,
            label: '거절',
            icon: Icons.close,
            bgColor: hasSelection ? AppColors.errorBg : AppColors.grey100,
            textColor: hasSelection ? AppColors.error : AppColors.grey400,
            onTap: hasSelection ? () => _batchReject() : null,
          ),
          SizedBox(width: ResponsiveHelper.spacing(context, 8)),
          _buildBottomBarButton(
            context,
            label: '승인',
            icon: Icons.check,
            bgColor: hasSelection ? AppColors.successBg : AppColors.grey100,
            textColor: hasSelection ? AppColors.successDark : AppColors.grey400,
            onTap: hasSelection ? () => _batchApprove() : null,
          ),
        ],
      ),
    );
  }

  Widget _buildBottomBarButton(
    BuildContext context, {
    required String label,
    required IconData icon,
    required Color bgColor,
    required Color textColor,
    required VoidCallback? onTap,
  }) {
    return Material(
      color: bgColor,
      borderRadius: BorderRadius.circular(ResponsiveHelper.spacing(context, 10)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(ResponsiveHelper.spacing(context, 10)),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: ResponsiveHelper.spacing(context, 18),
            vertical: ResponsiveHelper.spacing(context, 8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: ResponsiveHelper.iconSize(context, 15), color: textColor),
              SizedBox(width: ResponsiveHelper.spacing(context, 5)),
              Text(
                label,
                style: ResponsiveHelper.bodyStyle(context, color: textColor)
                    .copyWith(fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 일괄 승인 (계약서 생성 + 인감 날인 + 근무자 발송)
  Future<void> _batchApprove() async {
    if (_selectedIds.isEmpty || _isProcessing) return;

    // 인원 체크
    final stats = widget.toItem.workDetailStats?[widget.work.id];
    final confirmedCount = stats?['confirmed'] ?? 0;
    final remaining = widget.work.requiredCount - confirmedCount;

    if (_selectedIds.length > remaining) {
      ToastHelper.showWarning('필요 인원(${widget.work.requiredCount}명)을 초과합니다. 현재 $confirmedCount명 확정, $remaining명 추가 가능');
      return;
    }

    // 1. 계약서 템플릿 선택
    final businessId = widget.toItem.to.businessId;
    final articles = await ContractTemplateSelectorDialog.show(context, businessId: businessId);
    if (articles == null || !mounted) return;

    // 2. 사업장 정보 + 인감 로드
    setState(() => _isProcessing = true);
    late BusinessModel business;
    late String sealBase64;

    try {
      final b = await _firestoreService.getBusinessById(businessId);
      if (b == null) {
        ToastHelper.showError('사업장 정보를 불러올 수 없습니다');
        return;
      }
      business = b;
      final businessDoc = await FirebaseFirestore.instance
          .collection('businesses')
          .doc(businessId)
          .get();
      final seal = businessDoc.data()?['sealBase64'] as String?;
      if (seal == null || seal.isEmpty) {
        ToastHelper.showError('일괄 계약 발송에는 사업장 인감이 필요합니다.\n설정 > 사업장 설정에서 인감을 먼저 등록해주세요.');
        return;
      }
      sealBase64 = seal;
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }

    if (!mounted) return;

    // 3. 첫 번째 선택 지원자로 미리보기 계약서 생성
    final firstItem = _applicants.firstWhere(
      (item) => _selectedIds.contains((item['application'] as ApplicationModel).id),
      orElse: () => <String, dynamic>{},
    );
    if (firstItem.isEmpty) return;

    final firstApp = firstItem['application'] as ApplicationModel;
    final firstUser = firstItem['user'] as UserModel?;
    if (firstUser == null) {
      ToastHelper.showError('지원자 정보를 불러올 수 없습니다');
      return;
    }

    setState(() => _isProcessing = true);
    late EmploymentContractModel previewContract;
    try {
      // buildPreviewContract: 번들 탐색 없이 항상 isNewUnsaved=true 반환 → Firestore 미저장
      previewContract = await ContractService().buildPreviewContract(
        application: firstApp,
        business: business,
        worker: firstUser,
        workDetail: widget.work,
        articles: articles,
      );
    } catch (e) {
      ToastHelper.showError('계약서 미리보기 생성에 실패했습니다');
      return;
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }

    if (!mounted) return;

    // 4. 미리보기 다이얼로그
    final confirmed = await _showBatchContractPreview(
      contract: previewContract,
      sealBase64: sealBase64,
      count: _selectedIds.length,
    );
    if (confirmed != true || !mounted) return;

    // 5. 일괄 처리
    setState(() => _isProcessing = true);
    try {
      final userProvider = context.read<UserProvider>();
      final adminUID = userProvider.currentUser?.uid;
      final sealBytes = base64Decode(sealBase64);

      int successCount = 0;

      for (final appId in _selectedIds.toList()) {
        final item = _applicants.firstWhere(
          (i) => (i['application'] as ApplicationModel).id == appId,
          orElse: () => <String, dynamic>{},
        );
        if (item.isEmpty) continue;

        final app = item['application'] as ApplicationModel;
        final user = item['user'] as UserModel?;
        if (user == null) continue;

        try {
          // confirmed 호출 → _confirmWithConflictCheck 내부에서 CONTRACT_PENDING 설정 + 충돌 체크
          final affectedTOIds = await _firestoreService.updateApplicationStatus(
            applicationId: appId,
            status: AppStatus.confirmed,
            confirmedBy: adminUID,
          );
          if (affectedTOIds.isNotEmpty) {
            _affectedOtherTOIds.addAll(affectedTOIds);
          }

          // 계약서 생성 + 인감 날인 → 근무자 발송
          final contract = await ContractService().findOrCreateContract(
            application: app,
            business: business,
            worker: user,
            workDetail: widget.work,
            articles: articles,
          );
          await ContractService().saveEmployerSignature(
            contract: contract,
            signatureBytes: sealBytes,
          );
          successCount++;
        } catch (itemErr) {
          debugPrint('❌ [$appId] 계약서 처리 실패 — 상태 롤백: $itemErr');
          try {
            await _firestoreService.updateApplicationStatus(
              applicationId: appId,
              status: AppStatus.pending,
              confirmedBy: adminUID,
            );
          } catch (rollbackErr) {
            debugPrint('⚠️ 롤백 실패 ($appId): $rollbackErr');
          }
        }
      }

      if (successCount < _selectedIds.length) {
        ToastHelper.showWarning(
            '$successCount/${_selectedIds.length}명 계약서 발송 완료. 실패한 지원자는 다시 시도해주세요.');
      } else {
        ToastHelper.showSuccess('${_selectedIds.length}명에게 계약서가 발송되었습니다');
      }
      _selectedIds.clear();
      await _loadApplicants();
      await _updateLocalStats();

      for (var toId in _affectedOtherTOIds) {
        _firestoreService.clearCache(toId: toId);
      }
    } catch (e) {
      ToastHelper.showError('처리 중 오류가 발생했습니다');
      debugPrint('❌ 일괄 계약 발송 실패: $e');
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  /// 일괄 계약서 미리보기 다이얼로그
  Future<bool?> _showBatchContractPreview({
    required EmploymentContractModel contract,
    required String sealBase64,
    required int count,
  }) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 32),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Column(
          children: [
            // 헤더
            Container(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 16),
              decoration: BoxDecoration(
                color: Theme.of(ctx).primaryColor,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.description_outlined, color: Colors.white, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '근로계약서 미리보기',
                      style: ResponsiveHelper.subtitleStyle(ctx).copyWith(color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    icon: const Icon(Icons.close, color: Colors.white, size: 20),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            ),
            // 안내 배너
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              color: AppColors.info.withValues(alpha: 0.08),
              child: Text(
                '아래 조건으로 선택된 $count명에게 계약서가 발송됩니다.\n이름·생년월일 등 개인정보는 각 근무자별로 적용됩니다.',
                style: ResponsiveHelper.smallStyle(ctx, color: AppColors.info),
                textAlign: TextAlign.center,
              ),
            ),
            // 계약서 본문
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: ContractTemplateWidget(
                  snapshot: contract.snapshot,
                  contractDate: contract.createdAt,
                  slots: contract.slots,
                  articles: contract.articles,
                  employerSealBase64: sealBase64,
                ),
              ),
            ),
            // 하단 버튼
            Container(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 8,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('취소'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: Text('$count명에게 발송'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 일괄 거절
  Future<void> _batchReject() async {
    if (_selectedIds.isEmpty || _isProcessing) return;

    final userProvider = context.read<UserProvider>();
    final reason = await DialogHelper.showRejectReasonPicker(
      context,
      title: '일괄 거절',
      message: '선택한 ${_selectedIds.length}명을 거절합니다.\n거절 사유를 선택해주세요.',
    );

    if (reason == null || !mounted) return;

    setState(() => _isProcessing = true);

    try {
      final adminUID = userProvider.currentUser?.uid;
      // 순회 중 컬렉션 변경을 방지하기 위해 복사본으로 순회
      final idsToReject = List<String>.from(_selectedIds);

      for (final appId in idsToReject) {
        await _firestoreService.updateApplicationStatus(
          applicationId: appId,
          status: AppStatus.rejected,
          rejectedBy: adminUID,
          message: reason,
        );
      }

      ToastHelper.showSuccess('${idsToReject.length}명이 거절되었습니다');
      _selectedIds.clear();
      await _loadApplicants();
      await _updateLocalStats();
    } catch (e) {
      ToastHelper.showError('거절 처리 중 오류가 발생했습니다');
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }
  /// 로컬 통계 갱신 (toItem의 workDetailStats + slot 단위 카운트 업데이트)
  /// _loadApplicants 직후 캐시된 _allApplications를 재사용해 이중 fetch 방지
  Future<void> _updateLocalStats() async {
    _hasChanges = true;

    try {
      final applications = _allApplications;

      final Map<String, Map<String, int>> newStats = {};
      int totalPending = 0;
      int totalConfirmed = 0;

      for (final work in widget.toItem.workDetails) {
        int pending = 0;
        int confirmed = 0;

        for (final app in applications) {
          // workDetailId 우선 매칭, 없으면 workType+시간 폴백 (구 데이터 호환)
          final bool matches;
          final wdId = app.workDetailId;
          if (wdId != null && wdId.isNotEmpty) {
            if (wdId == work.id) {
              matches = true;
            } else if (wdId == work.workType) {
              // 레거시: workDetailId = workType만 → 시간으로 추가 확인
              matches = app.startTime == work.startTime &&
                  app.endTime == work.endTime;
            } else {
              matches = false;
            }
          } else {
            matches = app.selectedWorkType == work.workType &&
                app.startTime == work.startTime &&
                app.endTime == work.endTime;
          }
          if (matches) {
            if (app.status == AppStatus.pending) pending++;
            if (app.status == AppStatus.confirmed || app.status == AppStatus.contractPending) confirmed++;
          }
        }

        newStats[work.id] = {'pending': pending, 'confirmed': confirmed};
        totalPending += pending;
        totalConfirmed += confirmed;
      }

      widget.toItem.workDetailStats = newStats;
      // 슬롯 헤더 숫자도 즉시 갱신
      widget.toItem.updateOuterStats(confirmed: totalConfirmed, pending: totalPending);

    } catch (e) {
      // 실패 시 현재 다이얼로그 목록 기준으로 현재 업무만 업데이트
      int pending = 0;
      int confirmed = 0;

      for (final item in _applicants) {
        final app = item['application'] as ApplicationModel;
        if (app.status == AppStatus.pending) pending++;
        if (app.status == AppStatus.confirmed || app.status == AppStatus.contractPending) confirmed++;
      }

      widget.toItem.workDetailStats ??= {};
      widget.toItem.workDetailStats![widget.work.id] = {
        'pending': pending,
        'confirmed': confirmed,
      };
    }
  }
}
