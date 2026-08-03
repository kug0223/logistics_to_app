// lib/screens/business_admin/dialogs/work_applicants_dialog.dart
// 업무별 지원자 관리 다이얼로그 - 개선된 버전

import 'dart:convert';
import 'dart:math' show min;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
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
import '../../common/settings_screen.dart';
import '../../../models/ui/admin_to_list_ui_models.dart';
import '../../../theme/app_colors.dart';
import '../../../widgets/common/app_checkbox.dart';
import '../../../widgets/dialogs/styled_dialog.dart';
import '../../../utils/id_card_helper.dart';
import 'fixed_worker_management_dialog.dart';
import '../../../utils/format_helper.dart';
import '../../../utils/trust_score_helper.dart';
import '../../../utils/week_helper.dart';
import '../../../models/core/attendance_model.dart';
import '../../../models/core/monthly_review_model.dart';
import '../../../services/monthly_review_service.dart';
import '../../../screens/contract/contract_sign_screen.dart' show ContractTemplateWidget;
import '../../../widgets/common/app_empty_state.dart';
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
  final WorkDetailModel? work;  // null = 전체 업무 그룹 모드
  final TOItem toItem;
  final VoidCallback onChanged;
  /// 알림 딥링크에서 특정 지원자를 바로 강조 표시할 때 전달. null이면 일반 목록 표시.
  final String? initialApplicationId;
  /// 알림 딥링크에서 slot이 없을 때 헤더에 표시할 날짜. slot?.date가 우선한다.
  final DateTime? initialDate;

  const WorkApplicantsDialog({
    super.key,
    this.work,
    required this.toItem,
    required this.onChanged,
    this.initialApplicationId,
    this.initialDate,
  });

  @override
  State<WorkApplicantsDialog> createState() => _WorkApplicantsDialogState();
}

class _WorkApplicantsDialogState extends State<WorkApplicantsDialog>
    with LoadingStateMixin {
  final FirestoreService _firestoreService = FirestoreService();

  List<Map<String, dynamic>> _applicants = [];
  List<Map<String, dynamic>> _pending = [];
  List<Map<String, dynamic>> _confirmed = [];
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
  // 🔥 충돌로 취소된 다른 TO ID 목록
  final Set<String> _affectedOtherTOIds = {};
  // 리뷰 작성 여부 (uid → true=작성완료)
  final Map<String, bool> _reviewWrittenMap = {};
  // 이번 주 근무 횟수 (uid → 근무 횟수)
  final Map<String, int> _weeklyWorkCountMap = {};
  // 계약서 상태 (applicationId → status string, null=미작성)
  Map<String, String?> _contractStatusMap = {};
  // 계약서 일괄작성 처리 중 플래그
  bool _isContractBatchProcessing = false;
  // [BUG-CANCEL-01] 확정취소 버튼 가드 — 근무 이력 있는 확정자 노출 방지
  // key = userId, value = 슬롯 날짜(or 주간)에 checkIn/급여확정 기록 존재 여부
  Map<String, bool> _hasWorkedMap = {};

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
      // [BUGFIX] whereIn + equality 복합쿼리 시 Firestore 보안 규칙
      //   request.query.filters.businessId가 null 반환 → PERMISSION_DENIED.
      //   statuses 파라미터 제거 후 클라이언트 필터링으로 전환.
      final List<ApplicationModel> apps;
      if (widget.toItem.slot != null) {
        apps = await _firestoreService.getApplicationsBySlotId(
          widget.toItem.to.id,
          widget.toItem.slot!.id,
          businessId: widget.toItem.to.businessId,
        );
      } else {
        apps = await _firestoreService.getApplicationsByTOId(
          widget.toItem.to.id,
          businessId: widget.toItem.to.businessId,
        );
      }

      const activeStatuses = {'PENDING', 'CONTRACT_PENDING', 'CONFIRMED'};
      final filtered = apps.where((app) {
        if (!activeStatuses.contains(app.status)) return false;
        if (widget.work != null) {
          final wdId = app.workDetailId;
          if (wdId != null && wdId.isNotEmpty) {
            // 신규 compositeId 매칭
            if (wdId == widget.work!.id) return true;
            // 레거시: workDetailId = workType만 저장된 경우 → 시간으로 추가 확인
            if (wdId == widget.work!.workType) {
              return app.startTime == widget.work!.startTime &&
                     app.endTime == widget.work!.endTime;
            }
            return false;
          }
          // workDetailId 없는 구 데이터 호환
          return app.selectedWorkType == widget.work!.workType &&
                 app.startTime == widget.work!.startTime &&
                 app.endTime == widget.work!.endTime;
        }
        return true; // 그룹 모드: 업무 필터 없음 (activeStatuses만 체크)
      }).toList();

      // ✅ 1. 중복 제거된 UID/ID 목록 추출
      final uniqueUids = filtered.map((app) => app.uid).toSet().toList();
      final allAppIds = filtered.map((app) => app.id).toList();

      // 날짜 범위 (weeklyMap Future 생성에 필요)
      final slotDate = widget.toItem.slot?.date;
      final refDate = slotDate ?? DateTime.now();
      final ws = WeekHelper.weekStart(refDate);
      final we = WeekHelper.weekEnd(refDate);

      // ✅ 2. 독립 조회 4개 동시 시작 (서로 의존성 없음)
      // hasWorkedMap은 슬롯 날짜 있을 때만 의미 있지만, 미리 시작해두면 크리티컬 패스에서 제외됨
      final userMapFuture = _firestoreService.getUsersBatch(uniqueUids, businessId: widget.toItem.to.businessId);
      final weeklyMapFuture = _firestoreService.getWeeklyAttendanceByBusiness(
        businessId: widget.toItem.to.businessId, weekStart: ws, weekEnd: we);
      final contractMapFuture = ContractService().getContractStatusBatch(
        allAppIds, businessId: widget.toItem.to.businessId);
      final hasWorkedFuture = slotDate != null
          ? _firestoreService.loadHasWorkedMap(
              businessId: widget.toItem.to.businessId, date: slotDate)
          : Future.value(<String, bool>{});

      final userMap = await userMapFuture;
      
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
        _reviewWrittenMap
          ..clear()
          ..addAll(Map.fromEntries(reviewEntries));
      }

      // 이번 주 근무 횟수 — 위에서 동시에 시작한 weeklyMapFuture 결과 수집
      Map<String, List<dynamic>> weeklyMap;
      try {
        weeklyMap = await weeklyMapFuture;
      } catch (e) {
        debugPrint('⚠️ 주간 근무 횟수 조회 실패 (배지 미표시): $e');
        weeklyMap = {};
      }
      // 모든 지원자 uid를 0으로 초기화 → 기록 없는 지원자도 "주0회" 배지 표시
      final weeklyCountMap = <String, int>{
        for (final uid in uniqueUids) uid: 0,
      };
      for (final entry in weeklyMap.entries) {
        // "근무한 날" 기준: 실제 출근 기록(checkIn)이 있고 결근·노쇼가 아닌 날
        // present + late + early_leave 모두 포함 (조퇴도 출근한 날)
        weeklyCountMap[entry.key] = entry.value
            .where((a) =>
                a.checkIn != null &&
                a.status != AttendanceModel.statusAbsent &&
                a.status != AttendanceModel.statusNoShow)
            .length;
      }

      // isStarred 필드에서 관심표시 복원
      final starredFromFirestore = filtered
          .where((app) => app.isStarred)
          .map((app) => app.id)
          .toSet();

      // 계약서 상태 — 위에서 동시에 시작한 contractMapFuture 결과 수집
      final contractMap = await contractMapFuture;

      // [BUG-CANCEL-01] 확정취소 버튼 가드 — 근무 이력 맵 구성
      // 슬롯 기반: hasWorkedFuture (위에서 동시 시작) 결과 수집
      // 비슬롯: 이미 로드된 weeklyMap 에서 app.workDate 매칭으로 근무 여부 파악
      final Map<String, bool> hasWorkedMap;
      if (slotDate != null && confirmedUserIds.isNotEmpty) {
        hasWorkedMap = await hasWorkedFuture;
      } else {
        hasWorkedMap = {};
        final confirmedShortTermApps = filtered.where((app) =>
            (app.status == AppStatus.confirmed ||
                app.status == AppStatus.contractPending) &&
            !app.isLongTermApplication);
        for (final app in confirmedShortTermApps) {
          final appDay = DateTime(
              app.workDate.year, app.workDate.month, app.workDate.day);
          final userAtts = (weeklyMap[app.uid] ?? []).whereType<AttendanceModel>().toList();
          for (final att in userAtts) {
            final attDay = DateTime(
                att.workDate.year, att.workDate.month, att.workDate.day);
            if (attDay == appDay) {
              if ((att.checkIn != null &&
                      att.status != AttendanceModel.statusAbsent &&
                      att.status != AttendanceModel.statusNoShow) ||
                  att.isWageConfirmed ||
                  att.isWageTransferred) {
                hasWorkedMap[app.uid] = true;
              }
              break;
            }
          }
        }
      }

      // 알림 딥링크로 진입 시 해당 지원자를 목록 맨 앞으로 이동
      if (widget.initialApplicationId != null) {
        final idx = applicantsWithUserInfo.indexWhere(
          (item) => (item['application'] as ApplicationModel).id == widget.initialApplicationId,
        );
        if (idx > 0) {
          final highlighted = applicantsWithUserInfo.removeAt(idx);
          applicantsWithUserInfo.insert(0, highlighted);
        }
      }

      if (!mounted) return;
      setState(() {
        _applicants = applicantsWithUserInfo;
        _groupApplicants();
        _idCardStatusMap = idCardStatusMap;
        _allApplications = apps; // 통계 계산용 캐시
        _starredIds
          ..clear()
          ..addAll(starredFromFirestore);
        _weeklyWorkCountMap
          ..clear()
          ..addAll(weeklyCountMap);
        _contractStatusMap = contractMap;
        _hasWorkedMap = hasWorkedMap; // [BUG-CANCEL-01]
      });
  }, errorTag: '지원자 목록 로드');

  void _groupApplicants() {
    _pending = _applicants.where((item) =>
        (item['application'] as ApplicationModel).status == AppStatus.pending).toList();
    _confirmed = _applicants.where((item) {
      final s = (item['application'] as ApplicationModel).status;
      return AppStatus.confirmedStatuses.contains(s);
    }).toList();
  }

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

    final pending = _pending;
    final confirmed = _confirmed;

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
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
        insetPadding: EdgeInsets.symmetric(
          horizontal: ResponsiveHelper.spacing(context, 16),
          vertical: AppDialogSize.insetV,
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * AppDialogSize.maxHeightRatio,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.max,
            children: [
              _buildHeader(context, theme),
              _buildStatsBar(context, pending.length, confirmed.length),
              if (pending.isNotEmpty && widget.work != null)
                _buildSelectAllRow(context, pending.length),
              Expanded(
                child: isLoading
                    ? const LoadingWidget()
                    : (pending.isEmpty && confirmed.isEmpty)
                        ? _buildEmptyState()
                        : widget.work == null
                            ? _buildGroupedApplicantList(context)
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
          // 업무 아이콘 (그룹 모드: 공통 아이콘, 단일 모드: 업무 아이콘)
          if (widget.work != null)
            WorkTypeIcon.buildWithBackground(
              iconString: widget.work!.workTypeIcon,
              backgroundColor: widget.work!.workTypeBackgroundColor,
              size: ResponsiveHelper.iconSize(context, 24),
              containerSize: ResponsiveHelper.spacing(context, 44),
            )
          else
            Container(
              width: ResponsiveHelper.spacing(context, 44),
              height: ResponsiveHelper.spacing(context, 44),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(ResponsiveHelper.spacing(context, 12)),
              ),
              child: Icon(Icons.people, color: Colors.white, size: ResponsiveHelper.iconSize(context, 24)),
            ),
          SizedBox(width: ResponsiveHelper.spacing(context, 12)),

          // 제목
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.work != null
                      ? '${widget.work!.workType} - 지원자 관리'
                      : '${widget.toItem.to.title} - 지원자 관리',
                  style: ResponsiveHelper.subtitleStyle(context).copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: ResponsiveHelper.spacing(context, 2)),
                Text(
                  widget.work != null
                      ? '${FormatHelper.formatDate(widget.toItem.slot?.date ?? widget.initialDate ?? widget.toItem.to.date)} · ${widget.work!.startTime}~${widget.work!.endTime} | ${widget.work!.formattedWage}'
                      : '${FormatHelper.formatDate(widget.toItem.slot?.date ?? widget.initialDate ?? widget.toItem.to.date)} · 업무 ${widget.toItem.workDetails.length}종',
                  style: ResponsiveHelper.smallStyle(context, color: Colors.white.withValues(alpha: 0.7)),
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
          if (widget.work != null)
            Text(
              '필요: ${widget.work!.requiredCount}명',
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
                } else {
                  // 다른 모드와 상호 배제
                  _isIdCardSelectMode = false;
                  _selectedIdCardUserIds.clear();
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
  Widget _buildEmptyState() {
    return const AppEmptyState(
      icon: Icons.people_outline,
      title: '지원자가 없습니다',
    );
  }

  /// 지원자 목록: 별표시 먼저 → 주간 근무 적은 순 → 이름순
  List<Map<String, dynamic>> _sortedPending(List<Map<String, dynamic>> pending) {
    final sorted = List<Map<String, dynamic>>.from(pending);
    sorted.sort((a, b) {
      final aApp = a['application'] as ApplicationModel;
      final bApp = b['application'] as ApplicationModel;
      final aUser = a['user'] as UserModel?;
      final bUser = b['user'] as UserModel?;

      final aStarred = _starredIds.contains(aApp.id) ? 0 : 1;
      final bStarred = _starredIds.contains(bApp.id) ? 0 : 1;
      if (aStarred != bStarred) return aStarred.compareTo(bStarred);

      final aCount = _weeklyWorkCountMap[aUser?.uid ?? ''] ?? 0;
      final bCount = _weeklyWorkCountMap[bUser?.uid ?? ''] ?? 0;
      if (aCount != bCount) return aCount.compareTo(bCount);

      return (aUser?.name ?? '').compareTo(bUser?.name ?? '');
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
              Builder(builder: (context) {
                final noContractCount = confirmed.where((item) {
                  final app = item['application'] as ApplicationModel;
                  final status = _contractStatusMap[app.id];
                  return status == null || status.isEmpty || status == 'voided';
                }).length;
                if (noContractCount == 0) return const SizedBox.shrink();
                return _buildContractBatchSection(context, noContractCount);
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

  /// 그룹 모드: 업무별 섹션으로 나눈 지원자 목록
  Widget _buildGroupedApplicantList(BuildContext context) {
    final works = widget.toItem.workDetails;
    if (works.isEmpty) return _buildEmptyState();

    return SingleChildScrollView(
      padding: ResponsiveHelper.cardPadding(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final work in works) ..._buildWorkSection(context, work),
        ],
      ),
    );
  }

  /// 업무 섹션 (헤더 + 대기 카드 + 확정 카드)
  List<Widget> _buildWorkSection(BuildContext context, WorkDetailModel work) {
    final workApplicants = _applicants.where((item) {
      final app = item['application'] as ApplicationModel;
      return _appMatchesWork(app, work);
    }).toList();

    if (workApplicants.isEmpty) return [];

    final pending = workApplicants.where((item) =>
        (item['application'] as ApplicationModel).status == AppStatus.pending).toList();
    final confirmed = workApplicants.where((item) {
      final s = (item['application'] as ApplicationModel).status;
      return AppStatus.confirmedStatuses.contains(s);
    }).toList();

    return [
      // 업무 섹션 헤더
      Container(
        margin: EdgeInsets.only(
          bottom: ResponsiveHelper.spacing(context, 8),
          top: ResponsiveHelper.spacing(context, 12),
        ),
        padding: EdgeInsets.symmetric(
          horizontal: ResponsiveHelper.spacing(context, 12),
          vertical: ResponsiveHelper.spacing(context, 8),
        ),
        decoration: BoxDecoration(
          color: AppColors.grey50,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            WorkTypeIcon.buildWithBackground(
              iconString: work.workTypeIcon,
              backgroundColor: work.workTypeBackgroundColor,
              size: ResponsiveHelper.iconSize(context, 16),
              containerSize: ResponsiveHelper.spacing(context, 32),
            ),
            SizedBox(width: ResponsiveHelper.spacing(context, 8)),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    work.workType,
                    style: ResponsiveHelper.bodyStyle(context, color: AppColors.grey800)
                        .copyWith(fontWeight: FontWeight.bold),
                  ),
                  Text(
                    '${work.startTime}~${work.endTime}  ${work.formattedWage}',
                    style: ResponsiveHelper.smallStyle(context, color: AppColors.grey500),
                  ),
                ],
              ),
            ),
            if (pending.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.warningBg,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '대기 ${pending.length}',
                  style: ResponsiveHelper.tinyStyle(context, color: AppColors.warningDark),
                ),
              ),
            if (pending.isNotEmpty && confirmed.isNotEmpty)
              SizedBox(width: ResponsiveHelper.spacing(context, 4)),
            if (confirmed.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.successBg,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '확정 ${confirmed.length}',
                  style: ResponsiveHelper.tinyStyle(context, color: AppColors.successDark),
                ),
              ),
          ],
        ),
      ),
      // 대기 섹션
      if (pending.isNotEmpty) ...[
        SizedBox(height: ResponsiveHelper.spacing(context, 4)),
        ..._sortedPending(pending).asMap().entries.map((entry) =>
            _buildApplicantCard(context, entry.value, entry.key + 1, isPending: true, workOverride: work)),
        SizedBox(height: ResponsiveHelper.spacing(context, 8)),
      ],
      // 확정 섹션
      if (confirmed.isNotEmpty) ...[
        ...confirmed.asMap().entries.map((entry) =>
            _buildApplicantCard(context, entry.value, entry.key + 1, isPending: false, workOverride: work)),
        SizedBox(height: ResponsiveHelper.spacing(context, 16)),
      ],
    ];
  }

  /// 매칭 헬퍼: app이 특정 work에 속하는지 확인
  bool _appMatchesWork(ApplicationModel app, WorkDetailModel work) {
    final wdId = app.workDetailId;
    if (wdId != null && wdId.isNotEmpty) {
      if (wdId == work.id) return true;
      if (wdId == work.workType) {
        return app.startTime == work.startTime && app.endTime == work.endTime;
      }
      return false;
    }
    return app.selectedWorkType == work.workType &&
        app.startTime == work.startTime &&
        app.endTime == work.endTime;
  }

  /// app에 대응하는 WorkDetailModel 반환 (그룹 모드용)
  WorkDetailModel? _getWorkForApp(ApplicationModel app) {
    for (final w in widget.toItem.workDetails) {
      if (_appMatchesWork(app, w)) return w;
    }
    return widget.work;
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
                    // 다른 모드와 상호 배제
                    _isBatchMode = false;
                    _selectedIds.clear();
                    _selectAll = false;
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

  /// 계약서 일괄작성 섹션 (확정자 중 계약 미작성자)
  Widget _buildContractBatchSection(BuildContext context, int noContractCount) {
    return Container(
      margin: EdgeInsets.only(
        top: ResponsiveHelper.spacing(context, 4),
        bottom: ResponsiveHelper.spacing(context, 4),
      ),
      padding: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 16),
        vertical: ResponsiveHelper.spacing(context, 10),
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Icon(
            Icons.description_outlined,
            size: ResponsiveHelper.iconSize(context, 18),
            color: AppColors.success,
          ),
          SizedBox(width: ResponsiveHelper.spacing(context, 8)),
          Expanded(
            child: Text(
              '계약서 미작성 $noContractCount명',
              style: ResponsiveHelper.bodyStyle(context, color: AppColors.successDark),
            ),
          ),
          if (_isContractBatchProcessing)
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            InkWell(
              onTap: _batchCreateContractsForConfirmed,
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
                  '계약서 일괄작성',
                  style: ResponsiveHelper.smallStyle(context, color: Colors.white)
                      .copyWith(fontWeight: FontWeight.w600),
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
    if (_isProcessing) return; // 이중 탭 방지 — 중복 요청 전송 차단
    if (_selectedIdCardUserIds.isEmpty) return;
    setState(() => _isProcessing = true);
    try {
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

    if (!mounted) return;
    if (successCount > 0) {
      _hasChanges = true;

      // 상태 맵 업데이트 (요청 성공한 사용자들)
      setState(() {
        for (final uid in _selectedIdCardUserIds) {
          _idCardStatusMap[uid] = 'pending';
        }
        _isIdCardSelectMode = false;
        _selectedIdCardUserIds.clear();
        _isProcessing = false;
      });
    }
    } catch (e) {
      debugPrint('❌ [_batchRequestIdCard] 신분증 요청 실패: $e');
      if (mounted) ToastHelper.showError('신분증 요청 중 오류가 발생했습니다');
    } finally {
      if (mounted && _isProcessing) setState(() => _isProcessing = false);
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
  Widget _buildApplicantCard(BuildContext context, Map<String, dynamic> item, int index, {required bool isPending, WorkDetailModel? workOverride}) {
    final app = item['application'] as ApplicationModel;
    // ignore: unused_local_variable — 향후 확장용 (계약서 로직은 별도 메서드에서 _getWorkForApp 사용)
    final effectiveWork = workOverride ?? widget.work ?? _getWorkForApp(app);
    final user = item['user'] as UserModel?;
    final idCardStatus = _idCardStatusMap[user?.uid ?? ''] ?? 'none';
    // null = 로딩 전 / int = 로딩 완료 (0포함) → Wrap 조건부 포함으로 간격 오염 방지
    final weeklyCount = _weeklyWorkCountMap[user?.uid ?? ''];
    final isSelected = _selectedIds.contains(app.id);
    final isStarred = isPending && _starredIds.contains(app.id);
    final trustScore = TrustScoreHelper.calculate(user);

    final isNotificationTarget = widget.initialApplicationId != null && app.id == widget.initialApplicationId;

    Color cardBg = Colors.white;
    Color cardBorder = AppColors.border;
    if (isNotificationTarget) {
      // 알림 딥링크로 진입한 지원자 — 파란 강조 (isSelected보다 우선)
      cardBg = Theme.of(context).primaryColor.withValues(alpha: 0.08);
      cardBorder = Theme.of(context).primaryColor;
    } else if (isSelected) {
      cardBg = Theme.of(context).primaryColor.withValues(alpha: 0.05);
      cardBorder = Theme.of(context).primaryColor;
    } else if (isStarred) {
      cardBg = AppColors.amber.withValues(alpha: 0.1); // amber[50] equivalent
      cardBorder = AppColors.amberLight;
    } else if (!isPending) {
      cardBg = AppColors.successBg.withValues(alpha: 0.35);
    }

    return Container(
      margin: EdgeInsets.only(bottom: ResponsiveHelper.spacing(context, 4)),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(ResponsiveHelper.spacing(context, 10)),
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
          borderRadius: BorderRadius.circular(ResponsiveHelper.spacing(context, 10)),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: ResponsiveHelper.spacing(context, 10),
              vertical: ResponsiveHelper.spacing(context, 8),
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
                                          user?.name ?? app.applicantName ?? '이름 없음',
                                          style: ResponsiveHelper.bodyStyle(context).copyWith(fontWeight: FontWeight.w700),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      if (user?.gender != null || user?.age != null) ...[
                                        SizedBox(width: ResponsiveHelper.spacing(context, 4)),
                                        Flexible(
                                          child: Text(
                                            '(${user?.gender ?? ''}${user?.age != null ? ' · ${user?.age}세' : ''})',
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
                          Text(
                            _formatAppliedTime(app.appliedAt),
                            style: ResponsiveHelper.tinyStyle(context, color: AppColors.grey400),
                          ),
                          if (isPending) ...[
                            SizedBox(width: ResponsiveHelper.spacing(context, 4)),
                            GestureDetector(
                              onTap: () async {
                                final nowStarred = !_starredIds.contains(app.id);
                                // Optimistic update — 즉시 반영해 이중 탭 시 방향 뒤집힘 방지
                                setState(() {
                                  if (nowStarred) {
                                    _starredIds.add(app.id);
                                  } else {
                                    _starredIds.remove(app.id);
                                  }
                                });
                                try {
                                  await _firestoreService.updateApplicationFields(
                                    app.id,
                                    {'isStarred': nowStarred},
                                  );
                                } catch (e) {
                                  // 실패 시 UI 롤백
                                  if (mounted) {
                                    setState(() {
                                      if (nowStarred) {
                                        _starredIds.remove(app.id);
                                      } else {
                                        _starredIds.add(app.id);
                                      }
                                    });
                                    ToastHelper.showError('별 표시 저장에 실패했습니다');
                                  }
                                }
                              },
                              behavior: HitTestBehavior.opaque,
                              child: Padding(
                                padding: EdgeInsets.only(
                                  left: ResponsiveHelper.spacing(context, 6),
                                  top: ResponsiveHelper.spacing(context, 10),
                                  bottom: ResponsiveHelper.spacing(context, 10),
                                ),
                                child: Icon(
                                  isStarred ? Icons.star_rounded : Icons.star_border_rounded,
                                  size: ResponsiveHelper.iconSize(context, 18),
                                  color: isStarred ? AppColors.amber : AppColors.grey300,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      SizedBox(height: ResponsiveHelper.spacing(context, 5)),

                      // 2줄: 신뢰도 · 전화 · 주간횟수 · 평점
                      Wrap(
                        spacing: ResponsiveHelper.spacing(context, 5),
                        runSpacing: ResponsiveHelper.spacing(context, 3),
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          if (user?.phone != null && (user?.phone ?? '').isNotEmpty)
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.phone, size: ResponsiveHelper.iconSize(context, 11), color: AppColors.grey400),
                                SizedBox(width: ResponsiveHelper.spacing(context, 4)),
                                Text(
                                  FormatHelper.formatPhone(user?.phone ?? ''),
                                  style: ResponsiveHelper.smallStyle(context, color: AppColors.grey600),
                                ),
                              ],
                            ),
                          _buildTrustBadge(context, trustScore),
                          if (weeklyCount != null)
                            _buildWeeklyCountBadge(context, weeklyCount),
                          if (user != null && user.averageRating > 0)
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.star, size: ResponsiveHelper.iconSize(context, 12), color: AppColors.amber),
                                SizedBox(width: ResponsiveHelper.spacing(context, 2)),
                                Text(
                                  user.averageRating.toStringAsFixed(1),
                                  style: ResponsiveHelper.smallStyle(context, color: AppColors.grey600),
                                ),
                              ],
                            ),
                        ],
                      ),

                      // 3줄: 배지 (리뷰·계약·신분증) — 확정자 전용
                      if (!isPending) ...[
                        SizedBox(height: ResponsiveHelper.spacing(context, 3)),
                        Wrap(
                          spacing: ResponsiveHelper.spacing(context, 4),
                          runSpacing: ResponsiveHelper.spacing(context, 3),
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            _buildReviewBadge(context, user?.uid),
                            _buildContractBadge(context, app.id),
                            IdCardHelper.buildStatusBadge(context, idCardStatus),
                          ],
                        ),
                      ],

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
                                    ? '희망: ${app.desiredStartDate!.month}/${app.desiredStartDate!.day}~'
                                        '${app.workEndDate != null ? " (${app.workEndDate!.month}/${app.workEndDate!.day}까지)" : ""}'
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

                      // 확정자 액션 버튼 (파트변경 / 계약서 작성 / 확정취소 or 고정근무 관리)
                      if (!isPending && !_isBatchMode) ...[
                        SizedBox(height: ResponsiveHelper.spacing(context, 8)),
                        SizedBox(
                          width: double.infinity,
                          child: Wrap(
                          alignment: WrapAlignment.end,
                          spacing: ResponsiveHelper.spacing(context, 8),
                          runSpacing: ResponsiveHelper.spacing(context, 6),
                          children: [
                            if (widget.toItem.workDetails.length > 1)
                              _buildActionButton(
                                context,
                                label: '파트변경',
                                icon: Icons.swap_horiz,
                                bgColor: AppColors.infoBg,
                                textColor: AppColors.info,
                                onTap: () => _showChangeWorkPartDialog(item),
                              ),
                            // 계약 미작성 시 개별 작성 버튼
                            if (_contractStatusMap[app.id] == null ||
                                (_contractStatusMap[app.id]?.isEmpty ?? true) ||
                                _contractStatusMap[app.id] == 'voided')
                              _buildActionButton(
                                context,
                                label: '계약서 작성',
                                icon: Icons.description_outlined,
                                bgColor: AppColors.success,
                                textColor: Colors.white,
                                filled: true,
                                onTap: () => _createContractForConfirmedUser(item),
                              ),
                            // [B-2] 장기근무자는 첫 출근 전에도 고정근무 관리 가능
                            if (widget.toItem.to.isLongTerm)
                              _buildActionButton(
                                context,
                                label: '고정근무 관리',
                                icon: Icons.settings,
                                bgColor: AppColors.longTermBg,
                                textColor: AppColors.longTermDark,
                                // [B-3] item 전달 → 해당 근무자 uid로 자동 포커스
                                onTap: () => _openFixedWorkerManagement(item),
                              )
                            // [BUG-CANCEL-01] 근무 이력 있는 단기 확정자 취소 버튼 숨김
                            else if (_canCancelConfirmation(app))
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
                        ),
                      ],

                      // 대기 중 액션 버튼 (파트변경 / 거절 / 승인) — 마감/인원충족 TO에서는 숨김
                      if (isPending && !_isBatchMode && !widget.toItem.to.isClosed) ...[
                        SizedBox(height: ResponsiveHelper.spacing(context, 8)),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            if (widget.toItem.workDetails.length > 1) ...[
                              _buildActionButton(
                                context,
                                label: '파트변경',
                                icon: Icons.swap_horiz,
                                bgColor: AppColors.infoBg,
                                textColor: AppColors.info,
                                onTap: () => _showChangeWorkPartDialog(item),
                              ),
                              SizedBox(width: ResponsiveHelper.spacing(context, 12)),
                            ],
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
                              bgColor: AppColors.success,
                              textColor: Colors.white,
                              filled: true,
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
    bool filled = false,
  }) {
    final effectiveBg = filled ? bgColor : Colors.transparent;
    final effectiveText = filled ? Colors.white : textColor;
    return Material(
      color: effectiveBg,
      borderRadius: BorderRadius.circular(ResponsiveHelper.spacing(context, 8)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(ResponsiveHelper.spacing(context, 8)),
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: ResponsiveHelper.spacing(context, 14),
            vertical: ResponsiveHelper.spacing(context, 6),
          ),
          decoration: filled
              ? null
              : BoxDecoration(
                  border: Border.all(color: textColor.withValues(alpha: 0.6)),
                  borderRadius: BorderRadius.circular(ResponsiveHelper.spacing(context, 8)),
                ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: ResponsiveHelper.iconSize(context, 13), color: effectiveText),
              SizedBox(width: ResponsiveHelper.spacing(context, 4)),
              Text(
                label,
                style: ResponsiveHelper.smallStyle(context, color: effectiveText)
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

/// 계약서 상태 배지 (확정자 전용)
  Widget _buildContractBadge(BuildContext context, String appId) {
    final status = _contractStatusMap[appId];
    final String label;
    final Color color;
    final Color bgColor;
    if (status == null || status.isEmpty) {
      label = '계약미작성';
      color = AppColors.error;
      bgColor = AppColors.errorBg;
    } else {
      switch (status) {
        case 'pending_employer':
          label = '관리자서명';
          color = AppColors.warningDark;
          bgColor = AppColors.warningBg;
        case 'pending_worker':
          label = '서명대기';
          color = AppColors.warningDark;
          bgColor = AppColors.warningBg;
        case 'completed':
          label = '계약완료';
          color = AppColors.successDark;
          bgColor = AppColors.successBg;
        case 'voided':
          label = '무효';
          color = AppColors.error;
          bgColor = AppColors.errorBg;
        default:
          label = '계약중';
          color = AppColors.grey600;
          bgColor = AppColors.grey100;
      }
    }
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 5),
        vertical: 1,
      ),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        label,
        style: ResponsiveHelper.tinyStyle(context, color: color)
            .copyWith(fontWeight: FontWeight.bold),
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

  /// 이번 주 근무 횟수 배지
  /// null = 데이터 미로드, 0 = 이번 주 미근무
  /// 색상: 0회=회색(여유), 1~2회=초록, 3~4회=파랑, 5+회=주황(다른 지원자 기회 고려)
  Widget _buildWeeklyCountBadge(BuildContext context, int? count) {
    if (count == null) return const SizedBox.shrink();

    final Color color;
    final Color bgColor;
    final IconData icon;

    if (count == 0) {
      color = AppColors.grey500;
      bgColor = AppColors.grey100;
      icon = Icons.calendar_today_outlined;
    } else if (count <= 2) {
      color = AppColors.successDark;
      bgColor = AppColors.successBg;
      icon = Icons.calendar_today;
    } else if (count <= 4) {
      color = AppColors.infoDark;
      bgColor = AppColors.infoBg;
      icon = Icons.calendar_today;
    } else {
      color = AppColors.warningDark;
      bgColor = AppColors.warningBg;
      icon = Icons.calendar_today;
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
          Icon(icon, size: ResponsiveHelper.iconSize(context, 10), color: color),
          SizedBox(width: ResponsiveHelper.spacing(context, 3)),
          Text(
            '주$count회',
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

    if (diff.isNegative || diff.inMinutes < 1) {
      return '방금 전';
    }
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
    if (_isProcessing) return;
    final app = item['application'] as ApplicationModel;
    final user = item['user'] as UserModel?;
    final workDetails = widget.toItem.workDetails;

    // 현재 파트 제외한 다른 파트 목록 (id 기반 비교 — workType 이름 중복 방지)
    final currentWork = _getWorkForApp(app) ?? widget.work;
    final otherWorkDetails = workDetails.where((w) => w.id != (currentWork?.id ?? '')).toList();

    if (otherWorkDetails.isEmpty) {
      ToastHelper.showWarning('변경 가능한 다른 파트가 없습니다');
      return;
    }
    setState(() => _isProcessing = true);

    // [C-1] 파트변경 전 급여 상태 확인 — confirmed: 완전 차단 / calculated: 경고 후 선택
    // [H-CF-1] callableGetWageStatusCount CF 경유 — assertBizAdmin 서버 교차검증
    final int confirmedCount;
    final int calculatedCount;
    try {
      final wageCountResult = await FirebaseFunctions.instanceFor(region: 'asia-northeast3')
          .httpsCallable('callableGetWageStatusCount')
          .call({'applicationId': app.id, 'businessId': app.businessId});
      final resultMap = wageCountResult.data as Map;
      confirmedCount   = resultMap['confirmedCount']   as int? ?? 0;
      calculatedCount  = resultMap['calculatedCount']  as int? ?? 0;
    } catch (e) {
      debugPrint('❌ 급여 상태 확인 실패: $e');
      if (mounted) {
        setState(() => _isProcessing = false);
        ToastHelper.showError('급여 상태 확인 중 오류가 발생했습니다. 다시 시도해주세요.');
      }
      return;
    }
    if (!mounted) return;

    // confirmed(마감 완료) 기록 있으면 파트변경 완전 차단
    if (confirmedCount > 0) {
      setState(() => _isProcessing = false);
      await DialogHelper.showError(
        context,
        title: '파트변경 불가',
        message: '마감 처리된 급여가 $confirmedCount건 있습니다.\n먼저 마감을 취소한 후 다시 시도해주세요.',
      );
      return;
    }

    // calculated(계산 완료, 미마감) 기록 있으면 경고 후 선택
    if (calculatedCount > 0) {
      final proceed = await DialogHelper.showConfirm(
        context,
        title: '임금 계산 초기화 안내',
        message: '계산된 급여 $calculatedCount건이 있습니다.\n파트변경 시 해당 급여가 초기화되어 재계산이 필요합니다.\n계속하시겠습니까?',
        confirmText: '계속',
        cancelText: '취소',
      );
      if (proceed != true || !mounted) {
        if (mounted) setState(() => _isProcessing = false);
        return;
      }
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
                    currentWork?.workType ?? '',
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
                      message: '${user?.name ?? '지원자'}님을\n${currentWork?.workType ?? ''} → ${work.workType}(으)로\n변경하시겠습니까?',
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

    if (selectedWorkId == null || !mounted) {
      if (mounted) setState(() => _isProcessing = false);
      return;
    }

    // 파트 변경 처리
    try {
      final userProvider = context.read<UserProvider>();
      final adminUID = userProvider.currentUser?.uid ?? 'UNKNOWN';
      final selectedWork = otherWorkDetails.firstWhere(
        (w) => w.id == selectedWorkId,
        orElse: () => throw StateError('선택한 파트를 찾을 수 없습니다'),
      );

      await _firestoreService.changeApplicationWorkType(
        applicationId: app.id,
        newWorkType: selectedWork.workType,
        newWage: selectedWork.wage,
        adminUID: adminUID,
        newWorkDetailId: selectedWork.id,
        newWageType: selectedWork.wageType,
        newWorkTypeIcon: selectedWork.workTypeIcon,
        newWorkTypeColor: selectedWork.workTypeColor,
        newWorkTypeBackgroundColor: selectedWork.workTypeBackgroundColor,
      );
      final resetMsg = calculatedCount > 0
          ? '\n계산된 급여 $calculatedCount건이 초기화되었습니다.'
          : '';
      if (!mounted) return;
      ToastHelper.showSuccess('${user?.name ?? '지원자'}님의 파트가 ${selectedWork.workType}(으)로 변경되었습니다$resetMsg');
      await _loadApplicants();
      if (!mounted) return;
      await _updateLocalStats();
    } catch (e) {
      if (mounted) ToastHelper.showError('파트 변경에 실패했습니다');
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  /// 개별 승인
  Future<void> _approveApplication(Map<String, dynamic> item) async {
    if (_isProcessing) return;
    final app = item['application'] as ApplicationModel;
    final user = item['user'] as UserModel?;
    final userProvider = context.read<UserProvider>();

    // 인원 체크 (일괄 승인과 동일 기준)
    final effectiveWork = _getWorkForApp(app) ?? widget.work;
    final stats = (effectiveWork != null)
        ? (widget.toItem.workDetailStats?[effectiveWork.id])
        : null;
    final confirmedCount = (stats?['confirmed'] as int?) ?? 0;
    final remaining = (effectiveWork != null)
        ? effectiveWork.requiredCount - confirmedCount
        : 0;
    if (effectiveWork != null && remaining <= 0) {
      ToastHelper.showWarning(
        '필요 인원(${effectiveWork.requiredCount}명)이 이미 충족되었습니다.',
      );
      return;
    }

    setState(() => _isProcessing = true);
    try {
      final confirm = await DialogHelper.showConfirm(
        context,
        title: '지원 승인',
        message: '${user?.name ?? '지원자'}님을 승인하시겠습니까?',
        confirmText: '승인',
      );

      if (confirm != true || !mounted) return;

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

      if (!mounted) return;
      ToastHelper.showSuccess('${user?.name ?? '지원자'}님이 승인되었습니다');
      await _loadApplicants();
      if (!mounted) return;
      await _updateLocalStats();
    } catch (e) {
      if (mounted) ToastHelper.showError('승인 처리 중 오류가 발생했습니다');
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  /// 개별 거절
  Future<void> _rejectApplication(Map<String, dynamic> item) async {
    if (_isProcessing) return;
    final app = item['application'] as ApplicationModel;
    final user = item['user'] as UserModel?;
    final userProvider = context.read<UserProvider>();

    setState(() => _isProcessing = true);
    try {
      final reason = await DialogHelper.showRejectReasonPicker(
        context,
        title: '지원 거절',
        message: '${user?.name ?? '지원자'}님을 거절합니다.\n거절 사유를 선택해주세요.',
      );

      if (reason == null || !mounted) return;

      final adminUID = userProvider.currentUser?.uid;

      await _firestoreService.updateApplicationStatus(
        applicationId: app.id,
        status: AppStatus.rejected,
        rejectedBy: adminUID,
        message: reason,
      );

      if (!mounted) return;
      ToastHelper.showSuccess('${user?.name ?? '지원자'}님이 거절되었습니다');
      await _loadApplicants();
      if (!mounted) return;
      await _updateLocalStats();
    } catch (e) {
      if (mounted) ToastHelper.showError('거절 처리 중 오류가 발생했습니다');
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  /// [BUG-CANCEL-01] 확정취소 가능 여부
  /// 단기 근무자 전용 — 장기는 이미 UI에서 '고정근무 관리' 버튼으로 분기됨
  bool _canCancelConfirmation(ApplicationModel app) {
    return _hasWorkedMap[app.uid] != true;
  }

  /// 확정취소 (단기)
  Future<void> _cancelConfirmation(Map<String, dynamic> item) async {
    if (_isProcessing) return;
    setState(() => _isProcessing = true);  // 사유 선택 다이얼로그 중 재진입 방지
    final app = item['application'] as ApplicationModel;
    final user = item['user'] as UserModel?;
    final userProvider = context.read<UserProvider>();

    final reason = await DialogHelper.showRejectReasonPicker(
      context,
      title: '확정 취소',
      message: '${user?.name ?? '근무자'}님의 확정을 취소합니다.\n취소 사유를 선택해주세요.',
    );

    // [역전패턴 수정] 원래 "if (reason == null || !mounted)"였으나 !mounted 시에도 setState 호출되는 버그.
    // reason==null(사용자 취소)이면 로딩 해제 후 리턴, unmount면 setState 생략하고 리턴.
    if (reason == null) {
      if (mounted) setState(() => _isProcessing = false);
      return;
    }
    if (!mounted) return;
    try {
      final adminUID = userProvider.currentUser?.uid;

      await _firestoreService.cancelConfirmedApplication(
        app.id,
        canceledBy: adminUID,
        cancelReason: reason,
      );

      if (!mounted) return;
      ToastHelper.showSuccess('${user?.name ?? '근무자'}님의 확정이 취소되었습니다');
      await _loadApplicants();
      if (!mounted) return;
      await _updateLocalStats();
    } catch (e) {
      if (mounted) ToastHelper.showError('확정 취소 중 오류가 발생했습니다');
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  /// 고정근무 관리 다이얼로그 열기 (장기)
  // [B-3] item 파라미터 추가 → 해당 근무자 uid 전달로 자동 포커스
  void _openFixedWorkerManagement(Map<String, dynamic> item) {
    if (_isProcessing) return;
    setState(() => _isProcessing = true);
    final app = item['application'] as ApplicationModel;
    final businessId = widget.toItem.to.businessId;
    final onChanged = widget.onChanged;
    // 루트 Navigator는 이 다이얼로그가 pop된 후에도 유효
    final rootNav = Navigator.of(context, rootNavigator: true);
    Navigator.of(context).pop(WorkApplicantsDialogResult(
      hasChanges: _hasChanges,
      affectedTOIds: _affectedOtherTOIds,
    ));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      showDialog(
        context: rootNav.context,
        barrierDismissible: false,
        builder: (_) => FixedWorkerManagementDialog(
          businessIds: [businessId],
          initialBusinessId: businessId,
          onChanged: onChanged,
          initialWorkerUid: app.uid,
        ),
      );
    });
  }

  /// 지원자 상세 보기 - 공통 위젯 사용
  Future<void> _showApplicantDetail(Map<String, dynamic> item) async{
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
        if (!mounted) return;
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

    // 인원 체크 (일괄 승인은 단일 업무 모드에서만 실행됨)
    if (widget.work != null) {
      final stats = widget.toItem.workDetailStats?[widget.work!.id];
      final confirmedCount = stats?['confirmed'] ?? 0;
      final remaining = widget.work!.requiredCount - confirmedCount;

      if (_selectedIds.length > remaining) {
        ToastHelper.showWarning('필요 인원(${widget.work!.requiredCount}명)을 초과합니다. 현재 $confirmedCount명 확정, $remaining명 추가 가능');
        return;
      }
    }

    // 첫 번째 await 전에 가드 설정 — 템플릿 선택 다이얼로그가 열려 있는 동안 중복 탭 차단
    setState(() => _isProcessing = true);

    // 1. 계약서 템플릿 선택
    final businessId = widget.toItem.to.businessId;
    final articles = await ContractTemplateSelectorDialog.show(context, businessId: businessId);
    if (articles == null) {
      if (mounted) setState(() => _isProcessing = false);
      return;
    }
    if (!mounted) return;

    // 2. 사업장 정보 + 인감 로드
    final currentUserSeal = context.read<UserProvider>().currentUser?.sealBase64;
    final currentUserSealType = context.read<UserProvider>().currentUser?.sealType ?? 'stamp';
    late BusinessModel business;
    late String sealBase64;
    String sealType = 'stamp';
    bool continueToProcess = false;

    try {
      final b = await _firestoreService.getBusinessById(businessId);
      if (b == null) {
        if (mounted) ToastHelper.showError('사업장 정보를 불러올 수 없습니다');
        return;
      }
      business = b;
      // 날인은 users/{uid}에서 전역 로드 (설정에서 등록한 날인 사용)
      if (currentUserSeal == null || currentUserSeal.isEmpty) {
        if (!mounted) return;
        final goToSettings = await DialogHelper.showConfirm(
          context,
          title: '사업주 날인 미등록',
          message: '일괄 계약 발송에는 사업주 날인이 필요합니다.\n설정 > 사업주 날인에서 도장 또는 서명을 먼저 등록해주세요.',
          confirmText: '설정으로 이동',
          cancelText: '취소',
        );
        if (!mounted) return;
        if (goToSettings) {
          Navigator.of(context, rootNavigator: true).push(
            MaterialPageRoute(builder: (_) => const SettingsScreen()),
          );
        }
        return;
      }
      sealBase64 = currentUserSeal;
      sealType = currentUserSealType;
      continueToProcess = true;
    } catch (e) {
      debugPrint('❌ [_batchApprove] 사업장 정보 조회 실패: $e');
      if (mounted) ToastHelper.showError('사업장 정보를 불러오는 중 오류가 발생했습니다');
    } finally {
      // 실제 일괄 처리로 이어지는 경우 _isProcessing을 유지, 아니면 복원
      if (!continueToProcess && mounted) setState(() => _isProcessing = false);
    }

    if (!mounted) return;

    // 3. 첫 번째 선택 지원자로 미리보기 계약서 생성
    final firstItem = _applicants.firstWhere(
      (item) => _selectedIds.contains((item['application'] as ApplicationModel).id),
      orElse: () => <String, dynamic>{},
    );
    if (firstItem.isEmpty) {
      if (mounted) setState(() => _isProcessing = false);
      return;
    }

    final firstApp = firstItem['application'] as ApplicationModel;
    final firstUser = firstItem['user'] as UserModel?;
    if (firstUser == null) {
      ToastHelper.showError('지원자 정보를 불러올 수 없습니다');
      if (mounted) setState(() => _isProcessing = false);
      return;
    }
    final firstWorkDetail = widget.work ?? _getWorkForApp(firstApp);
    if (firstWorkDetail == null) {
      ToastHelper.showError('업무 정보를 찾을 수 없습니다');
      if (mounted) setState(() => _isProcessing = false);
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
        workDetail: firstWorkDetail,
        articles: articles,
      );
    } catch (e) {
      if (mounted) ToastHelper.showError('계약서 미리보기 생성에 실패했습니다');
      return;
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }

    if (!mounted) return;

    // 4. 미리보기 다이얼로그
    final confirmed = await _showBatchContractPreview(
      contract: previewContract,
      sealBase64: sealBase64,
      sealType: sealType,
      count: _selectedIds.length,
    );
    if (confirmed != true || !mounted) return;

    // 5. 일괄 처리
    setState(() => _isProcessing = true);
    try {
      final userProvider = context.read<UserProvider>();
      final adminUID = userProvider.currentUser?.uid;
      final sealBytes = base64Decode(sealBase64);

      // 처리 대상 목록 수집
      final toProcess = <Map<String, dynamic>>[];
      for (final appId in _selectedIds.toList()) {
        final item = _applicants.firstWhere(
          (i) => (i['application'] as ApplicationModel).id == appId,
          orElse: () => <String, dynamic>{},
        );
        if (item.isNotEmpty && item['user'] != null) toProcess.add(item);
      }

      // 단건 처리 함수 (성공 여부 반환)
      Future<bool> processOne(Map<String, dynamic> item) async {
        final app = item['application'] as ApplicationModel;
        final user = item['user'] as UserModel;
        final appId = app.id;
        final appWorkDetail = widget.work ?? _getWorkForApp(app);
        if (appWorkDetail == null) return false;
        try {
          final affectedTOIds = await _firestoreService.updateApplicationStatus(
            applicationId: appId,
            status: AppStatus.confirmed,
            confirmedBy: adminUID,
          );
          if (affectedTOIds.isNotEmpty) {
            _affectedOtherTOIds.addAll(affectedTOIds);
          }
          // [BUG-수정 M-1] updateApplicationStatus 완료 후 Firestore에는 computedWorkEndDate가
          // 저장되지만 로컬 app 객체는 구버전이라 workEndDate가 null일 수 있음.
          // 서버에서 최신 데이터를 재조회해 contractEnd 공백 발급 버그를 방지.
          final freshAppDoc = await FirebaseFirestore.instance
              .collection('applications')
              .doc(appId)
              .get(const GetOptions(source: Source.server));
          // 승인 처리 직후 문서가 삭제된 경쟁 상태 방어 (catch(itemErr)로 롤백됨)
          if (!freshAppDoc.exists) throw Exception('지원서를 찾을 수 없습니다');
          // [BUG-H1-P2 수정 2026-07-15] fromMap → tryFromFirestore: 파싱 실패 시 크래시 대신 명시적 예외
          final freshApp = ApplicationModel.tryFromFirestore(freshAppDoc) ??
              (throw Exception('승인 후 지원서 파싱 실패'));
          final contract = await ContractService().findOrCreateContract(
            application: freshApp,
            business: business,
            worker: user,
            workDetail: appWorkDetail,
            articles: articles,
          );
          await ContractService().saveEmployerSignature(
            contract: contract,
            signatureBytes: sealBytes,
          );
          return true;
        } catch (itemErr) {
          debugPrint('❌ [$appId] 계약서 처리 실패 — 상태 롤백: $itemErr');
          try {
            await _firestoreService.updateApplicationStatus(
              applicationId: appId,
              status: AppStatus.pending,
            );
          } catch (rollbackErr) {
            debugPrint('⚠️ 롤백 실패 ($appId): $rollbackErr');
          }
          return false;
        }
      }

      // 5개씩 배치 병렬 처리 (Firebase rate limit 고려)
      const batchSize = 5;
      int successCount = 0;
      for (var i = 0; i < toProcess.length; i += batchSize) {
        final batch = toProcess.sublist(i, min(i + batchSize, toProcess.length));
        final results = await Future.wait(batch.map(processOne));
        successCount += results.where((r) => r).length;
      }
      if (!mounted) return;

      if (successCount < _selectedIds.length) {
        ToastHelper.showWarning(
            '$successCount/${_selectedIds.length}명 계약서 발송 완료. 실패한 지원자는 다시 시도해주세요.');
      } else {
        ToastHelper.showSuccess('${_selectedIds.length}명에게 계약서가 발송되었습니다');
      }
      _selectedIds.clear();
      if (mounted) setState(() { _isBatchMode = false; _selectAll = false; });
      await _loadApplicants();
      await _updateLocalStats();
      if (!mounted) return;

      for (var toId in _affectedOtherTOIds) {
        _firestoreService.clearCache(toId: toId);
      }
    } catch (e) {
      if (mounted) ToastHelper.showError('처리 중 오류가 발생했습니다');
      debugPrint('❌ 일괄 계약 발송 실패: $e');
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  /// 일괄 계약서 미리보기 다이얼로그
  Future<bool?> _showBatchContractPreview({
    required EmploymentContractModel contract,
    required String sealBase64,
    String sealType = 'stamp',
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
                  employerSignatureUrl: contract.employerSignatureUrl,
                  employerSealBase64: sealBase64,
                  employerSealType: sealType,
                  workerSignatureUrl: contract.workerSignatureUrl,
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

  /// 확정자 계약서 일괄작성 (이미 확정된 상태 → 상태 변경 없이 계약서만 생성)
  Future<void> _batchCreateContractsForConfirmed() async {
    if (_isContractBatchProcessing) return;
    setState(() => _isContractBatchProcessing = true);
    final businessId = widget.toItem.to.businessId;

    // 1. 템플릿 선택
    final articles = await ContractTemplateSelectorDialog.show(context, businessId: businessId);
    if (articles == null || !mounted) {
      if (mounted) setState(() => _isContractBatchProcessing = false);
      return;
    }

    // 2. 인감 확인
    final currentUser = context.read<UserProvider>().currentUser;
    final sealBase64 = currentUser?.sealBase64 ?? '';
    final sealType = currentUser?.sealType ?? 'stamp';
    if (sealBase64.isEmpty) {
      if (!mounted) {
        return;
      }
      final goSettings = await DialogHelper.showConfirm(
        context,
        title: '사업주 날인 미등록',
        message: '일괄 계약 발송에는 사업주 날인이 필요합니다.\n설정 > 사업주 날인에서 도장 또는 서명을 먼저 등록해주세요.',
        confirmText: '설정으로 이동',
        cancelText: '취소',
      );
      if (!mounted) {
        return;
      }
      if (goSettings) {
        Navigator.of(context, rootNavigator: true)
            .push(MaterialPageRoute(builder: (_) => const SettingsScreen()));
      }
      setState(() => _isContractBatchProcessing = false);
      return;
    }

    // 3. 사업장 정보 로드
    late BusinessModel business;
    try {
      final b = await _firestoreService.getBusinessById(businessId);
      if (b == null) {
        if (mounted) ToastHelper.showError('사업장 정보를 불러올 수 없습니다');
        return;
      }
      business = b;
    } catch (e) {
      debugPrint('❌ [_batchCreateContractsForConfirmed] 사업장 정보 조회 실패: $e');
      if (mounted) ToastHelper.showError('사업장 정보를 불러오는 중 오류가 발생했습니다');
      return;
    } finally {
      if (mounted) setState(() => _isContractBatchProcessing = false);
    }
    if (!mounted) return;

    // 4. 계약 미작성 확정자 수집
    final toProcess = _applicants.where((item) {
      final app = item['application'] as ApplicationModel;
      if (!AppStatus.confirmedStatuses.contains(app.status)) return false;
      final status = _contractStatusMap[app.id];
      return status == null || status.isEmpty || status == 'voided';
    }).toList();
    if (toProcess.isEmpty) return;

    // 5. 첫 번째 대상으로 미리보기 생성
    final firstApp = toProcess.first['application'] as ApplicationModel;
    final firstUser = toProcess.first['user'] as UserModel?;
    if (firstUser == null) {
      ToastHelper.showError('지원자 정보를 불러올 수 없습니다');
      return;
    }
    final firstWorkDetail = widget.work ?? _getWorkForApp(firstApp);
    if (firstWorkDetail == null) {
      ToastHelper.showError('업무 정보를 찾을 수 없습니다');
      return;
    }

    setState(() => _isContractBatchProcessing = true);
    late EmploymentContractModel previewContract;
    try {
      previewContract = await ContractService().buildPreviewContract(
        application: firstApp,
        business: business,
        worker: firstUser,
        workDetail: firstWorkDetail,
        articles: articles,
      );
    } catch (e) {
      if (mounted) ToastHelper.showError('계약서 미리보기 생성에 실패했습니다');
      return;
    } finally {
      if (mounted) setState(() => _isContractBatchProcessing = false);
    }
    if (!mounted) return;

    // 6. 미리보기 다이얼로그
    final confirmed = await _showBatchContractPreview(
      contract: previewContract,
      sealBase64: sealBase64,
      sealType: sealType,
      count: toProcess.length,
    );
    if (confirmed != true || !mounted) return;

    // 7. 일괄 계약서 생성 + 날인
    setState(() => _isContractBatchProcessing = true);
    final sealBytes = base64Decode(sealBase64);
    try {
      Future<bool> processOne(Map<String, dynamic> item) async {
        final app = item['application'] as ApplicationModel;
        final user = item['user'] as UserModel?;
        if (user == null) return false;
        final appWorkDetail = widget.work ?? _getWorkForApp(app);
        if (appWorkDetail == null) return false;
        try {
          final contract = await ContractService().findOrCreateContract(
            application: app,
            business: business,
            worker: user,
            workDetail: appWorkDetail,
            articles: articles,
          );
          await ContractService().saveEmployerSignature(
            contract: contract,
            signatureBytes: sealBytes,
          );
          return true;
        } catch (e) {
          debugPrint('❌ [${app.id}] 계약서 발송 실패: $e');
          return false;
        }
      }

      const batchSize = 5;
      int successCount = 0;
      final List<Map<String, dynamic>> successItems = [];
      for (var i = 0; i < toProcess.length; i += batchSize) {
        final batch = toProcess.sublist(i, min(i + batchSize, toProcess.length));
        final results = await Future.wait(batch.map(processOne));
        if (!mounted) return;
        for (var j = 0; j < batch.length; j++) {
          if (results[j]) {
            successCount++;
            successItems.add(batch[j]);
          }
        }
      }

      if (!mounted) return;
      if (successCount < toProcess.length) {
        ToastHelper.showWarning(
            '$successCount/${toProcess.length}명 계약서 발송 완료. 실패한 항목은 다시 시도해주세요.');
      } else {
        ToastHelper.showSuccess('${toProcess.length}명에게 계약서가 발송되었습니다');
      }
      if (successCount > 0) {
        _hasChanges = true;
        setState(() {
          for (final item in successItems) {
            final app = item['application'] as ApplicationModel;
            _contractStatusMap[app.id] = 'pending_worker';
          }
        });
      }
    } catch (e) {
      if (mounted) ToastHelper.showError('처리 중 오류가 발생했습니다');
      debugPrint('❌ 계약서 일괄 발송 실패: $e');
    } finally {
      if (mounted) setState(() => _isContractBatchProcessing = false);
    }
  }

  /// 개별 계약서 작성 (확정자 단건)
  Future<void> _createContractForConfirmedUser(Map<String, dynamic> item) async {
    if (_isProcessing) return;
    setState(() => _isProcessing = true);
    final app = item['application'] as ApplicationModel;
    final user = item['user'] as UserModel?;
    if (user == null) {
      if (mounted) setState(() => _isProcessing = false);
      return;
    }
    final businessId = widget.toItem.to.businessId;

    // 1. 템플릿 선택
    final articles = await ContractTemplateSelectorDialog.show(context, businessId: businessId);
    if (articles == null || !mounted) {
      if (mounted) setState(() => _isProcessing = false);
      return;
    }

    // 2. 인감 확인
    final currentUser = context.read<UserProvider>().currentUser;
    final sealBase64 = currentUser?.sealBase64 ?? '';
    final sealType = currentUser?.sealType ?? 'stamp';
    if (sealBase64.isEmpty) {
      if (!mounted) {
        return;
      }
      final goSettings = await DialogHelper.showConfirm(
        context,
        title: '사업주 날인 미등록',
        message: '계약 발송에는 사업주 날인이 필요합니다.\n설정 > 사업주 날인에서 도장 또는 서명을 먼저 등록해주세요.',
        confirmText: '설정으로 이동',
        cancelText: '취소',
      );
      if (!mounted) {
        return;
      }
      if (goSettings) {
        Navigator.of(context, rootNavigator: true)
            .push(MaterialPageRoute(builder: (_) => const SettingsScreen()));
      }
      setState(() => _isProcessing = false);
      return;
    }

    // 3. 사업장 정보 로드 + 미리보기 생성
    final resolvedWork = widget.work ?? _getWorkForApp(app);
    if (resolvedWork == null) {
      ToastHelper.showError('업무 정보를 찾을 수 없습니다');
      if (mounted) setState(() => _isProcessing = false);
      return;
    }
    late EmploymentContractModel previewContract;
    try {
      final b = await _firestoreService.getBusinessById(businessId);
      if (b == null) {
        if (mounted) ToastHelper.showError('사업장 정보를 불러올 수 없습니다');
        return;
      }
      previewContract = await ContractService().buildPreviewContract(
        application: app,
        business: b,
        worker: user,
        workDetail: resolvedWork,
        articles: articles,
      );
    } catch (e) {
      if (mounted) ToastHelper.showError('계약서 미리보기 생성에 실패했습니다');
      return;
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
    if (!mounted) return;

    // 4. 미리보기
    final ok = await _showBatchContractPreview(
      contract: previewContract,
      sealBase64: sealBase64,
      sealType: sealType,
      count: 1,
    );
    if (ok != true || !mounted) return;

    // 5. 계약서 생성 + 날인
    setState(() => _isProcessing = true);
    try {
      final b = await _firestoreService.getBusinessById(businessId);
      if (b == null) {
        if (mounted) ToastHelper.showError('사업장 정보를 불러올 수 없습니다');
        return;
      }
      final sealBytes = base64Decode(sealBase64);
      final contract = await ContractService().findOrCreateContract(
        application: app,
        business: b,
        worker: user,
        workDetail: resolvedWork,
        articles: articles,
      );
      await ContractService().saveEmployerSignature(
        contract: contract,
        signatureBytes: sealBytes,
      );
      if (!mounted) return;
      ToastHelper.showSuccess('계약서가 발송되었습니다');
      _hasChanges = true;
      setState(() => _contractStatusMap[app.id] = 'pending_worker');
    } catch (e) {
      if (mounted) ToastHelper.showError('계약서 발송 실패: $e');
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  /// 일괄 거절
  Future<void> _batchReject() async {
    if (_selectedIds.isEmpty || _isProcessing) return;
    setState(() => _isProcessing = true);

    final userProvider = context.read<UserProvider>();
    final reason = await DialogHelper.showRejectReasonPicker(
      context,
      title: '일괄 거절',
      message: '선택한 ${_selectedIds.length}명을 거절합니다.\n거절 사유를 선택해주세요.',
    );

    if (reason == null || !mounted) {
      if (mounted) setState(() => _isProcessing = false);
      return;
    }

    try {
      final adminUID = userProvider.currentUser?.uid;
      // 순회 중 컬렉션 변경을 방지하기 위해 복사본으로 순회
      final idsToReject = List<String>.from(_selectedIds);

      // 병렬 거절 처리 — 개별 try-catch로 성공/실패 카운팅
      final rejectResults = await Future.wait(idsToReject.map((appId) async {
        try {
          await _firestoreService.updateApplicationStatus(
            applicationId: appId,
            status: AppStatus.rejected,
            rejectedBy: adminUID,
            message: reason,
          );
          return true;
        } catch (e) {
          debugPrint('❌ [_batchReject] 거절 실패 [$appId]: $e');
          return false;
        }
      }));
      final successCount = rejectResults.where((r) => r).length;
      final failCount = rejectResults.where((r) => !r).length;

      if (!mounted) return;
      if (successCount > 0) {
        final msg = failCount > 0
            ? '$successCount명 거절 완료 ($failCount명 실패)'
            : '$successCount명이 거절되었습니다';
        ToastHelper.showSuccess(msg);
        _selectedIds.clear();
        await _loadApplicants();
        if (!mounted) return;
        await _updateLocalStats();
      } else {
        ToastHelper.showError('거절 처리 중 오류가 발생했습니다');
      }
    } catch (e) {
      if (mounted) ToastHelper.showError('거절 처리 중 오류가 발생했습니다');
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
      // [BUG-FIX] _applicants(필터된 Map 목록) → _allApplications(원본 ApplicationModel 목록) 사용
      // _applicants는 현재 업무(widget.work)로 필터된 결과라 전체 통계가 정확하지 않음
      int pending = 0;
      int confirmed = 0;

      for (final app in _allApplications) {
        if (app.status == AppStatus.pending) pending++;
        if (app.status == AppStatus.confirmed || app.status == AppStatus.contractPending) confirmed++;
      }

      widget.toItem.workDetailStats ??= {};
      if (widget.work != null) {
        widget.toItem.workDetailStats![widget.work!.id] = {
          'pending': pending,
          'confirmed': confirmed,
        };
      }
    }
  }
}
