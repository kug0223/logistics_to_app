// lib/screens/business_admin/dialogs/fixed_worker_management_dialog.dart
// 고정근무자 관리 다이얼로그 - 리뉴얼 버전
// 
// 기능:
// - 고정근무자 목록 조회
// - 근무자 상세 정보 (WorkerDetailDialog 연동)
// - 추가 근무 요청
// - 미출근 요청
// - 계약해지 요청 (NEW)

import 'dart:math' show min;
import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../../models/core/application_model.dart';
import '../../../models/core/notification_model.dart';
import '../../../models/core/schedule_change_request_model.dart';
import '../../../models/core/user_model.dart';
import '../../../models/core/work_detail_data.dart';
import '../../../services/contract_service.dart';
import '../../../services/firestore_service.dart';
import '../../../providers/user_provider.dart';
import '../../../utils/toast_helper.dart';
import '../../../utils/responsive_helper.dart';
import '../../../utils/format_helper.dart';
import '../../../utils/dialog_helper.dart';
import '../../../utils/loading_state_mixin.dart';
import '../../../widgets/common/loading_widget.dart';
import '../../../widgets/dialogs/contract_template_selector_dialog.dart';
import '../../../widgets/dialogs/worker_detail_dialog.dart';
import '../../../theme/app_colors.dart';
import '../../../widgets/work_type_icon.dart';
import '../../../widgets/dialogs/styled_dialog.dart';
import '../../../widgets/pickers/date_picker_bottom_sheet.dart';
import '../../../widgets/app_select_field.dart';
import '../../../widgets/common/app_search_bar.dart';
import '../../contract/contract_sign_screen.dart';

/// 근무자의 특정 날짜 근무 상태
enum _WorkerDayStatus {
  normalWork,        // 정상 출근 예정 (정규 요일, 예외 없음)
  leaveApproved,     // 휴무 승인됨
  leavePending,      // 휴무/미출근 대기중
  extraWorkApproved, // 추가근무 승인됨 (비정규 요일)
  extraWorkPending,  // 추가근무 대기중
  notWorkingDay,     // 해당일 근무 없음 (정규 아님 + 예외도 없음)
  notInPeriod,       // 계약 기간 외
}

/// 고정근무자 관리 다이얼로그
class FixedWorkerManagementDialog extends StatefulWidget {
  final List<String>? businessIds;  // 여러 사업장 (캘린더에서 호출 시)
  final String? initialBusinessId;  // 초기 선택 사업장
  final VoidCallback onChanged;
  final DateTime? focusDate;        // 날짜 모드 (캘린더에서 날짜 선택 후 열 때)
  // [B-3] 특정 근무자 uid → 로드 후 해당 근무자로 자동 검색 포커스
  final String? initialWorkerUid;

  const FixedWorkerManagementDialog({
    super.key,
    this.businessIds,
    this.initialBusinessId,
    required this.onChanged,
    this.focusDate,
    this.initialWorkerUid,
  });

  @override
  State<FixedWorkerManagementDialog> createState() => _FixedWorkerManagementDialogState();
}

class _FixedWorkerManagementDialogState extends State<FixedWorkerManagementDialog>
    with LoadingStateMixin {
  final FirestoreService _firestoreService = FirestoreService();

  // 고정근무자 목록 (사용자 정보 포함)
  List<_FixedWorkerItem> _fixedWorkers = [];
  
  // 사업장 선택
  String? _selectedBusinessId;
  Map<String, String> _businessNameMap = {};
  List<String> _businessIds = [];
  bool _showBusinessSelector = false;

  // 날짜 모드 (focusDate != null 일 때)
  List<ScheduleChangeRequestModel> _pendingRequestsForDate = [];
  bool get _isDateMode => widget.focusDate != null;

  // 승인/거절 중복 클릭 방지
  bool _isProcessing = false;

  // 검색
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  List<_FixedWorkerItem> get _filteredFixedWorkers {
    if (_searchQuery.isEmpty) return _fixedWorkers;
    final q = _searchQuery.toLowerCase();
    return _fixedWorkers.where((item) {
      final name = (item.user?.name ?? '').toLowerCase();
      return name.contains(q);
    }).toList();
  }

  List<_FixedWorkerItem> get _expiringWorkers => _fixedWorkers.where((item) =>
    _isExpiringWithinDays(item.application, 15) &&
    item.application.renewalDecision == null
  ).toList();

  @override
  void initState() {
    super.initState();
    _initBusinessData();
    _searchController.addListener(() {
      setState(() => _searchQuery = _searchController.text.trim());
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// 사업장 데이터 초기화
  Future<void> _initBusinessData() async {
    if (widget.businessIds != null && widget.businessIds!.isNotEmpty) {
      // 여러 사업장 모드 (캘린더에서 호출)
      _businessIds = widget.businessIds!;
      _selectedBusinessId = widget.initialBusinessId ?? _businessIds.first;
      // 저장된 마지막 선택 사업장 반영 (드롭다운이 있는 경우만)
      if (_businessIds.length > 1) {
        final prefs = await SharedPreferences.getInstance();
        final saved = prefs.getString('alfit_last_business_id');
        if (saved != null && _businessIds.contains(saved)) {
          _selectedBusinessId = saved;
        }
      }
      _showBusinessSelector = true;
      await _loadBusinessNames();
    } else if (widget.initialBusinessId != null) {
      // 단일 사업장 모드 (기존 호출) — 드롭다운 없음, 저장값 무시
      _businessIds = [widget.initialBusinessId!];
      _selectedBusinessId = widget.initialBusinessId;
      _showBusinessSelector = false;
      await _loadBusinessNames();
    }

    _loadFixedWorkers();
  }

  /// 사업장명 조회
  Future<void> _loadBusinessNames() async {
    try {
      final nameMap = await _firestoreService.getBusinessNames(_businessIds);
      if (mounted) {
        setState(() {
          _businessNameMap = nameMap;
        });
      }
    } catch (e) {
      debugPrint('❌ 사업장명 조회 실패: $e');
    }
  }

  /// 고정근무자 로드
  Future<void> _loadFixedWorkers() => runWithLoading(() async {
    if (_selectedBusinessId == null) return;

    final allApps = await _firestoreService.getApplicationsByBusinessId(_selectedBusinessId!);

      // 기본 필터: 장기 확정자 중 퇴사/해지 완료 제외
      final allFiltered = allApps.where((app) {
        if (!(app.status == AppStatus.confirmed || app.status == AppStatus.contractPending)) return false;
        if (!app.isLongTermApplication) return false;
        if (app.isTerminationApproved) return false;
        if (app.resignStatus == AppStatus.approved || app.resignStatus == AppStatus.autoApproved) return false;

        // EXTEND(연장된 구 계약):
        // - 일반 목록: 항상 제외 (신규 계약이 대체)
        // - 날짜 모드: focusDate가 구 계약 기간 내이면 포함
        if (app.renewalDecision == AppStatus.renewalExtend) {
          if (!_isDateMode) return false;
          final focus = widget.focusDate!;
          final start = app.desiredStartDate ?? app.workDate;
          final end = app.actualResignDate ?? app.workEndDate;
          final focusOnly = DateTime(focus.year, focus.month, focus.day);
          final startOnly = DateTime(start.year, start.month, start.day);
          if (focusOnly.isBefore(startOnly)) return false;
          if (end != null) {
            final endOnly = DateTime(end.year, end.month, end.day);
            if (focusOnly.isAfter(endOnly)) return false;
          }
          return true;
        }
        return true;
      }).toList();

      // 날짜 모드: 구 계약(EXTEND)이 오늘을 커버하는 uid는 신규 계약 숨김 (중복 방지)
      final Set<String> uidsWithActiveLegacy = _isDateMode
          ? allFiltered
              .where((app) => app.renewalDecision == AppStatus.renewalExtend)
              .map((app) => app.uid)
              .toSet()
          : {};

      final filtered = allFiltered.where((app) {
        if (uidsWithActiveLegacy.contains(app.uid) &&
            app.renewalDecision != AppStatus.renewalExtend) {
          return false;
        }
        return true;
      }).toList();

      // ✅ 1. 업무유형 정보 한 번만 조회 (중복 제거!)
      final businessWorkTypes = await _firestoreService.getBusinessWorkTypes(_selectedBusinessId!);
      final workTypeMap = { for (var w in businessWorkTypes) w.name: w };
      
      // ✅ 2. 중복 제거된 UID 목록
      final uniqueUids = filtered.map((app) => app.uid).toSet().toList();

      // ✅ 3. 사용자 정보 일괄 조회 (캐시 포함)
      final userMap = await _firestoreService.getUsersBatch(uniqueUids, businessId: _selectedBusinessId!);
      
      // ✅ 4. 결과 매핑 (추가 조회 없음)
      final results = filtered.map((app) {
        final matched = workTypeMap[app.selectedWorkType];
        
        return _FixedWorkerItem(
          application: app, 
          user: userMap[app.uid],
          workTypeIcon: matched?.icon,
          workTypeColor: matched?.color,
          workTypeBackgroundColor: matched?.backgroundColor,
        );
      }).toList();

      // 최신 확정순 정렬 (confirmedAt null-safe)
      results.sort((a, b) => (b.application.confirmedAt ?? b.application.appliedAt)
          .compareTo(a.application.confirmedAt ?? a.application.appliedAt));

      // 날짜 모드: 해당 날짜의 대기 요청 로드
      if (_isDateMode && _selectedBusinessId != null) {
        _pendingRequestsForDate =
            await _firestoreService.getScheduleChangeRequestsForDate(
          date: widget.focusDate!,
          businessIds: [_selectedBusinessId!],
        );
      }

      if (!mounted) return;
      setState(() {
        _fixedWorkers = results;
      });

      // [B-3] 특정 근무자 uid가 지정된 경우 해당 근무자 이름으로 자동 검색
      // uid 매칭 실패 시(목록에 없는 경우) 검색창을 채우지 않음 — 엉뚱한 사람 포커스 방지
      if (widget.initialWorkerUid != null && results.isNotEmpty && mounted) {
        final matches = results.where(
          (item) => item.application.uid == widget.initialWorkerUid,
        ).toList();
        if (matches.isNotEmpty) {
          final name = matches.first.user?.name ?? '';
          if (name.isNotEmpty) {
            _searchController.text = name;
            // TextEditingController.text setter는 addListener 콜백을 트리거하지 않음.
            //           _filteredFixedWorkers가 _searchQuery를 기준으로 필터링하므로 setState로 동기화 필수.
            setState(() => _searchQuery = name);
          }
        }
      }
  }, errorTag: '고정근무자 로드', errorMessage: '고정근무자 목록을 불러올 수 없습니다');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      insetPadding: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 16),
        vertical: AppDialogSize.insetV,
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * AppDialogSize.maxHeightRatio,
        ),
        child: Column(
          children: [
            // 헤더
            _buildHeader(context, theme),

            // 날짜 모드 서브헤더
            if (_isDateMode) _buildDateModeSubHeader(context),

            // 통계 바
            _buildStatsBar(context),

            // 계약 만료 임박 경고 배너
            if (!_isDateMode && !isLoading && _expiringWorkers.isNotEmpty)
              _buildExpiringWarningBanner(context),

            // 검색바
            Padding(
              padding: EdgeInsets.fromLTRB(
                ResponsiveHelper.spacing(context, 16),
                ResponsiveHelper.spacing(context, 8),
                ResponsiveHelper.spacing(context, 16),
                0,
              ),
              child: AppSearchBar(
                controller: _searchController,
                hintText: '이름으로 검색...',
                padding: EdgeInsets.zero,
              ),
            ),

            // 목록
            Expanded(
              child: isLoading
                  ? const LoadingWidget(message: '고정근무자 로딩 중...')
                  : _fixedWorkers.isEmpty
                      ? _buildEmptyState(context)
                      : _buildWorkerList(context),
            ),

            // 하단 버튼
            _buildBottomBar(context),
          ],
        ),
      ),
    );
  }

  /// 헤더
  Widget _buildHeader(BuildContext context, ThemeData theme) {
    return Container(
      padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 16)),
      decoration: BoxDecoration(
        color: AppColors.longTermDark,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(ResponsiveHelper.spacing(context, 20)),
          topRight: Radius.circular(ResponsiveHelper.spacing(context, 20)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 제목 행
          Row(
            children: [
              Container(
                padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 10)),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.manage_accounts,
                  color: Colors.white,
                  size: ResponsiveHelper.iconSize(context, 24),
                ),
              ),
              SizedBox(width: ResponsiveHelper.spacing(context, 12)),
              Expanded(
                child: Text(
                  '고정근무자 관리',
                  style: ResponsiveHelper.subtitleStyle(context).copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              // 닫기 버튼
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close, color: Colors.white),
              ),
            ],
          ),
          
          // 사업장 드롭다운 (여러 사업장일 때만 표시)
          if (_showBusinessSelector) ...[
            SizedBox(height: ResponsiveHelper.spacing(context, 12)),
            _buildBusinessDropdown(context),
          ],
        ],
      ),
    );
  }

  /// 사업장 선택 드롭다운
  Widget _buildBusinessDropdown(BuildContext context) {
    return AppSelectField<String>(
      value: _selectedBusinessId,
      hintText: '사업장을 선택하세요',
      sheetTitle: '사업장 선택',
      items: _businessIds,
      labelOf: (id) => _businessNameMap[id] ?? id,
      prefixIcon: Icons.business,
      onChanged: (value) {
        if (value != null && value != _selectedBusinessId) {
          setState(() => _selectedBusinessId = value);
          SharedPreferences.getInstance().then(
            (prefs) => prefs.setString('alfit_last_business_id', value),
          );
          _loadFixedWorkers();
        }
      },
    );
  }

  // ============================================================
  // 📅 날짜 모드 전용 위젯 & 헬퍼
  // ============================================================

  /// 날짜 모드 서브헤더 (날짜 + 통계 통합)
  Widget _buildDateModeSubHeader(BuildContext context) {
    final date = widget.focusDate!;
    final isWeekend = date.weekday == DateTime.saturday || date.weekday == DateTime.sunday;

    // 통계 계산
    int normalCount = 0, leaveCount = 0, extraCount = 0, pendingCount = 0;
    for (final w in _fixedWorkers) {
      switch (_getWorkerDayStatus(w.application)) {
        case _WorkerDayStatus.normalWork:        normalCount++;
        case _WorkerDayStatus.leaveApproved:     leaveCount++;
        case _WorkerDayStatus.leavePending:      pendingCount++;
        case _WorkerDayStatus.extraWorkApproved: extraCount++;
        case _WorkerDayStatus.extraWorkPending:  pendingCount++;
        case _WorkerDayStatus.notWorkingDay:
        case _WorkerDayStatus.notInPeriod:       break;
      }
    }

    final hasStats = (normalCount + leaveCount + extraCount + pendingCount) > 0;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 16),
        vertical: ResponsiveHelper.spacing(context, 10),
      ),
      decoration: BoxDecoration(
        color: AppColors.tealBg,
        border: Border(bottom: BorderSide(color: AppColors.teal.withValues(alpha: 0.2))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 날짜 행
          Row(
            children: [
              Icon(Icons.event, size: ResponsiveHelper.iconSize(context, 15), color: AppColors.tealDark),
              SizedBox(width: ResponsiveHelper.spacing(context, 6)),
              Text(
                '${date.month}월 ${date.day}일(${FormatHelper.weekday(date)}) 근무 현황',
                style: ResponsiveHelper.smallStyle(context).copyWith(
                  fontWeight: FontWeight.bold,
                  color: isWeekend ? AppColors.errorDark : AppColors.tealDark,
                ),
              ),
              const Spacer(),
              if (_pendingRequestsForDate.isNotEmpty)
                Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: ResponsiveHelper.spacing(context, 8),
                    vertical: ResponsiveHelper.spacing(context, 3),
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.warning,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '대기 ${_pendingRequestsForDate.length}건',
                    style: ResponsiveHelper.tinyStyle(context, color: Colors.white)
                        .copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
            ],
          ),
          // 통계 행 (근무자 로드 완료 후만 표시)
          if (!isLoading && hasStats) ...[
            SizedBox(height: ResponsiveHelper.spacing(context, 8)),
            Wrap(
              spacing: ResponsiveHelper.spacing(context, 6),
              runSpacing: 4,
              children: [
                if (normalCount > 0) _buildInlineStatChip(context, '출근예정', normalCount, AppColors.success),
                if (leaveCount > 0)  _buildInlineStatChip(context, '휴무', leaveCount, AppColors.warning),
                if (extraCount > 0)  _buildInlineStatChip(context, '추가근무', extraCount, AppColors.teal),
                if (pendingCount > 0) _buildInlineStatChip(context, '대기', pendingCount, AppColors.grey500),
              ],
            ),
          ],
        ],
      ),
    );
  }

  /// 서브헤더 내 소형 통계 칩
  Widget _buildInlineStatChip(BuildContext context, String label, int count, Color color) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 8),
        vertical: ResponsiveHelper.spacing(context, 3),
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: ResponsiveHelper.tinyStyle(context, color: color)
                .copyWith(fontWeight: FontWeight.w600),
          ),
          SizedBox(width: ResponsiveHelper.spacing(context, 4)),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '$count',
              style: ResponsiveHelper.tinyStyle(context, color: Colors.white)
                  .copyWith(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  /// 특정 근무자의 해당 날짜 상태 계산
  _WorkerDayStatus _getWorkerDayStatus(ApplicationModel app) {
    final date = widget.focusDate!;
    final today = DateTime(date.year, date.month, date.day);

    // 계약 기간 확인
    final startDate = app.desiredStartDate ?? app.workDate;
    final endDate = app.actualResignDate ?? app.workEndDate;
    final start = DateTime(startDate.year, startDate.month, startDate.day);
    if (today.isBefore(start)) return _WorkerDayStatus.notInPeriod;
    if (endDate != null) {
      final end = DateTime(endDate.year, endDate.month, endDate.day);
      if (today.isAfter(end)) return _WorkerDayStatus.notInPeriod;
    }

    // 정규 요일 확인
    final isRegularDay = app.workDays?.contains(FormatHelper.weekday(date)) ?? false;

    // 승인된 휴무 확인
    final isOnLeave = app.isLeaveDateOn(date);
    // 승인된 추가근무 확인
    final hasExtraWork = app.isExtraWorkDateOn(date);

    // 해당 날짜 대기 요청
    final pending = _pendingRequestsForDate
        .where((r) => r.applicationId == app.id)
        .firstOrNull;

    if (isRegularDay) {
      if (isOnLeave) return _WorkerDayStatus.leaveApproved;
      if (pending != null && (pending.isLeaveRequest || pending.isNoWorkRequest)) {
        return _WorkerDayStatus.leavePending;
      }
      return _WorkerDayStatus.normalWork;
    } else {
      if (hasExtraWork) return _WorkerDayStatus.extraWorkApproved;
      if (pending != null && pending.isExtraWorkRequest) {
        return _WorkerDayStatus.extraWorkPending;
      }
      return _WorkerDayStatus.notWorkingDay;
    }
  }

  /// 날짜 모드 상태 배지
  Widget _buildDayStatusBadge(BuildContext context, _WorkerDayStatus status) {
    late Color bg;
    late Color fg;
    late IconData icon;
    late String label;

    switch (status) {
      case _WorkerDayStatus.normalWork:
        bg = AppColors.successBg; fg = AppColors.successDark;
        icon = Icons.check_circle_outline; label = '출근 예정';
      case _WorkerDayStatus.leaveApproved:
        bg = AppColors.warningBg; fg = AppColors.warningDark;
        icon = Icons.beach_access_outlined; label = '휴무 승인';
      case _WorkerDayStatus.leavePending:
        bg = AppColors.warningBg; fg = AppColors.warningDark;
        icon = Icons.hourglass_top_outlined; label = '휴무 대기';
      case _WorkerDayStatus.extraWorkApproved:
        bg = AppColors.tealBg; fg = AppColors.tealDark;
        icon = Icons.add_circle_outline; label = '추가근무';
      case _WorkerDayStatus.extraWorkPending:
        bg = AppColors.tealBg; fg = AppColors.tealDark;
        icon = Icons.hourglass_top_outlined; label = '추가 대기';
      case _WorkerDayStatus.notWorkingDay:
        bg = AppColors.grey100; fg = AppColors.grey500;
        icon = Icons.remove_circle_outline; label = '비근무일';
      case _WorkerDayStatus.notInPeriod:
        bg = AppColors.grey100; fg = AppColors.grey400;
        icon = Icons.event_busy_outlined; label = '기간 외';
    }

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 8),
        vertical: ResponsiveHelper.spacing(context, 4),
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: fg.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: fg),
          SizedBox(width: ResponsiveHelper.spacing(context, 4)),
          Text(label,
              style: ResponsiveHelper.tinyStyle(context, color: fg)
                  .copyWith(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  /// 대기 요청 인라인 승인/거절 버튼
  Widget _buildPendingActions(BuildContext context, ApplicationModel app) {
    final userProvider = Provider.of<UserProvider>(context, listen: false);
    final uid = userProvider.currentUser?.uid;
    if (uid == null) return const SizedBox.shrink();
    final approverUid = uid;

    final pending = _pendingRequestsForDate
        .where((r) => r.applicationId == app.id)
        .firstOrNull;
    if (pending == null) return const SizedBox.shrink();

    return Padding(
      padding: EdgeInsets.only(top: ResponsiveHelper.spacing(context, 8)),
      child: Row(
        children: [
          if (pending.reason != null && pending.reason!.isNotEmpty) ...[
            Icon(Icons.chat_bubble_outline,
                size: 12, color: AppColors.grey500),
            SizedBox(width: ResponsiveHelper.spacing(context, 4)),
            Expanded(
              child: Text(
                pending.reason!,
                style: ResponsiveHelper.tinyStyle(context, color: AppColors.grey600),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ] else
            const Spacer(),
          SizedBox(width: ResponsiveHelper.spacing(context, 8)),
          _buildMiniButton(
            context,
            label: '거절',
            color: AppColors.error,
            onTap: isLoading || _isProcessing ? null : () => _rejectPendingRequest(pending, approverUid),
          ),
          SizedBox(width: ResponsiveHelper.spacing(context, 6)),
          _buildMiniButton(
            context,
            label: '승인',
            color: AppColors.teal,
            filled: true,
            onTap: isLoading || _isProcessing ? null : () => _approvePendingRequest(pending, approverUid),
          ),
        ],
      ),
    );
  }

  Widget _buildMiniButton(
    BuildContext context, {
    required String label,
    required Color color,
    bool filled = false,
    required VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: ResponsiveHelper.spacing(context, 12),
          vertical: ResponsiveHelper.spacing(context, 5),
        ),
        decoration: BoxDecoration(
          color: filled ? color : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color),
        ),
        child: Text(
          label,
          style: ResponsiveHelper.tinyStyle(
            context,
            color: filled ? Colors.white : color,
          ).copyWith(fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  /// 대기 요청 승인 처리
  Future<void> _approvePendingRequest(
      ScheduleChangeRequestModel request, String approverUid) async {
    if (_isProcessing) return;
    setState(() => _isProcessing = true);
    try {
      final ok = await _firestoreService.approveScheduleChangeRequest(
        requestId: request.id,
        approverUid: approverUid,
      );
      if (ok && mounted) {
        ToastHelper.showSuccess('요청을 승인했습니다');
        widget.onChanged();
        _loadFixedWorkers();
      } else if (mounted) {
        ToastHelper.showError('승인 처리에 실패했습니다');
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  /// 대기 요청 거절 처리
  Future<void> _rejectPendingRequest(
      ScheduleChangeRequestModel request, String approverUid) async {
    if (_isProcessing) return;
    setState(() => _isProcessing = true);
    try {
      final ok = await _firestoreService.rejectScheduleChangeRequest(
        requestId: request.id,
        rejectorUid: approverUid,
      );
      if (ok && mounted) {
        ToastHelper.showSuccess('요청을 거절했습니다');
        widget.onChanged();
        _loadFixedWorkers();
      } else if (mounted) {
        ToastHelper.showError('거절 처리에 실패했습니다');
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  // ============================================================
  // 📊 통계 바
  // ============================================================

  /// 통계 바
  Widget _buildStatsBar(BuildContext context) {
    if (_isDateMode) return const SizedBox.shrink();

    final activeCount = _fixedWorkers.where((w) => w.application.resignStatus == null).length;
    final pendingResignCount = _fixedWorkers.where((w) => w.application.resignStatus == AppStatus.pending).length;
    final terminationPendingCount = _fixedWorkers.where((w) => w.application.terminationStatus == AppStatus.pending).length;

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
          _buildStatChip(context, '전체', _fixedWorkers.length, AppColors.longTermDark),
          SizedBox(width: ResponsiveHelper.spacing(context, 8)),
          _buildStatChip(context, '정상', activeCount, AppColors.success),
          if (pendingResignCount > 0) ...[
            SizedBox(width: ResponsiveHelper.spacing(context, 8)),
            _buildStatChip(context, '퇴사대기', pendingResignCount, AppColors.warning),
          ],
          if (terminationPendingCount > 0) ...[
            SizedBox(width: ResponsiveHelper.spacing(context, 8)),
            _buildStatChip(context, '해지대기', terminationPendingCount, AppColors.error),
          ],
        ],
      ),
    );
  }

  Widget _buildStatChip(BuildContext context, String label, int count, Color color) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 12),
        vertical: ResponsiveHelper.spacing(context, 6),
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: ResponsiveHelper.smallStyle(context, color: color),
          ),
          SizedBox(width: ResponsiveHelper.spacing(context, 6)),
          Container(
            padding: EdgeInsets.symmetric(
              horizontal: ResponsiveHelper.spacing(context, 6),
              vertical: ResponsiveHelper.spacing(context, 2),
            ),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '$count',
              style: ResponsiveHelper.tinyStyle(context, color: Colors.white).copyWith(
                fontWeight: FontWeight.bold,
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
          Icon(
            Icons.people_outline,
            size: ResponsiveHelper.iconSize(context, 64),
            color: AppColors.grey400,
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 16)),
          Text(
            '고정근무자가 없습니다',
            style: ResponsiveHelper.subtitleStyle(context, color: AppColors.grey600),
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 8)),
          Text(
            '장기 공고에서 지원자를 확정하면\n이곳에 표시됩니다',
            textAlign: TextAlign.center,
            style: ResponsiveHelper.bodyStyle(context, color: AppColors.grey500),
          ),
        ],
      ),
    );
  }

  /// 근무자 목록
  Widget _buildWorkerList(BuildContext context) {
    final workers = _filteredFixedWorkers;

    if (workers.isEmpty) {
      return Center(
        child: Padding(
          padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 32)),
          child: Text(
            _searchQuery.isEmpty ? '고정근무자가 없습니다' : '"$_searchQuery" 검색 결과가 없습니다',
            style: ResponsiveHelper.bodyStyle(context, color: AppColors.grey500),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    if (!_isDateMode) {
      return ListView.separated(
        padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 16)),
        itemCount: workers.length,
        separatorBuilder: (_, __) => SizedBox(height: ResponsiveHelper.spacing(context, 12)),
        itemBuilder: (context, index) => _buildWorkerCard(workers[index]),
      );
    }

    // 날짜 모드: 해당날 관련자 / 비관련자 분리
    final active = workers.where((w) {
      final s = _getWorkerDayStatus(w.application);
      return s != _WorkerDayStatus.notWorkingDay && s != _WorkerDayStatus.notInPeriod;
    }).toList();
    final inactive = workers.where((w) {
      final s = _getWorkerDayStatus(w.application);
      return s == _WorkerDayStatus.notWorkingDay || s == _WorkerDayStatus.notInPeriod;
    }).toList();

    return ListView(
      padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 16)),
      children: [
        if (active.isEmpty)
          Padding(
            padding: EdgeInsets.symmetric(vertical: ResponsiveHelper.spacing(context, 24)),
            child: Center(
              child: Text('이 날 근무 예정인 계약직이 없습니다',
                  style: ResponsiveHelper.bodyStyle(context, color: AppColors.grey500)),
            ),
          ),
        ...active.map((w) => Padding(
              padding: EdgeInsets.only(bottom: ResponsiveHelper.spacing(context, 12)),
              child: _buildWorkerCard(w),
            )),
        if (inactive.isNotEmpty) ...[
          Padding(
            padding: EdgeInsets.symmetric(vertical: ResponsiveHelper.spacing(context, 8)),
            child: Row(children: [
              const Expanded(child: Divider()),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: ResponsiveHelper.spacing(context, 8)),
                child: Text('오늘 비근무 (${inactive.length}명)',
                    style: ResponsiveHelper.tinyStyle(context, color: AppColors.grey400)),
              ),
              const Expanded(child: Divider()),
            ]),
          ),
          ...inactive.map((w) => Padding(
                padding: EdgeInsets.only(bottom: ResponsiveHelper.spacing(context, 10)),
                child: Opacity(opacity: 0.5, child: _buildWorkerCard(w)),
              )),
        ],
      ],
    );
  }

  /// 근무자 카드
  Widget _buildWorkerCard(_FixedWorkerItem item) {
    final app = item.application;
    final user = item.user;
    final name = user?.name ?? '이름 없음';

    final hasResignRequest = app.resignStatus == AppStatus.pending;
    final hasTerminationRequest = app.terminationStatus == AppStatus.pending;

    // 날짜 모드 상태
    final dayStatus = _isDateMode ? _getWorkerDayStatus(app) : null;
    final hasPendingRequest = dayStatus == _WorkerDayStatus.leavePending ||
        dayStatus == _WorkerDayStatus.extraWorkPending;

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      elevation: 2,
      shadowColor: Colors.black.withValues(alpha: 0.08),
      child: InkWell(
        onTap: () => _showWorkerActions(item),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 16)),
          child: Column(
            children: [
              // 해지/퇴사 요청 중 배너 (날짜 모드 포함 항상 표시)
              if (hasResignRequest || hasTerminationRequest)
                _buildStatusBanner(app, hasResignRequest, hasTerminationRequest),

              // 계약서 서명 대기 배너 (연장 후 근무자 미서명)
              if (app.status == AppStatus.contractPending)
                _buildContractPendingBanner(context),

              // 계약 만료 임박 배너 (D-15 이내, 미결정) — 리스트 모드에서만 (버튼 포함)
              if (!_isDateMode && _isExpiringWithinDays(app, 15) && app.renewalDecision == null)
                _buildRenewalBanner(context, app, item.user),

              // 계약 갱신 결정 완료 배너 (날짜 모드 포함 항상 표시)
              if (app.renewalDecision != null)
                _buildRenewalDecisionBanner(context, app),

              // 기본 정보
              Row(
                children: [
                  // 정보
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              name,
                              style: ResponsiveHelper.bodyStyle(context).copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            if (user?.gender != null) ...[
                              SizedBox(width: ResponsiveHelper.spacing(context, 6)),
                              Text(
                                '${user?.gender ?? ''}${user?.age != null ? ' · ${user?.age}세' : ''}',
                                style: ResponsiveHelper.smallStyle(context, color: AppColors.grey500),
                              ),
                            ],
                          ],
                        ),
                        SizedBox(height: ResponsiveHelper.spacing(context, 4)),
                        // 업무 정보
                        Row(
                          children: [
                            // 업무 아이콘
                            if (item.workTypeIcon != null)
                              WorkTypeIcon.buildWithBackground(
                                iconString: item.workTypeIcon!,
                                iconColor: item.workTypeColor,
                                backgroundColor: item.workTypeBackgroundColor,
                                size: 12,
                                containerSize: 20,
                              )
                            else
                              Icon(
                                Icons.work_outline,
                                size: ResponsiveHelper.iconSize(context, 14),
                                color: AppColors.grey500,
                              ),
                            SizedBox(width: ResponsiveHelper.spacing(context, 4)),
                            Text(
                              app.selectedWorkType,
                              style: ResponsiveHelper.smallStyle(context, color: AppColors.grey600),
                            ),
                          ],
                        ),
                        SizedBox(height: ResponsiveHelper.spacing(context, 4)),
                        // 요일 (별도 Row)
                        Row(
                          children: [
                            Icon(
                              Icons.calendar_today_outlined,
                              size: ResponsiveHelper.iconSize(context, 12),
                              color: AppColors.grey400,
                            ),
                            SizedBox(width: ResponsiveHelper.spacing(context, 4)),
                            Flexible(
                              child: Text(
                                _formatWorkDays(app.workDays),
                                style: ResponsiveHelper.smallStyle(context, color: AppColors.grey500),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: ResponsiveHelper.spacing(context, 2)),
                        // 시작일: 희망시작일 우선, 종료일: 퇴사일 우선
                        Builder(builder: (_) {
                          final effectiveStartDate = app.desiredStartDate ?? app.workDate;
                          final effectiveEndDate = app.actualResignDate ?? app.workEndDate;
                          int? daysLeft;
                          if (effectiveEndDate != null &&
                              !app.isTerminationApproved) {
                            final todayOnly = DateTime.now();
                            final today = DateTime(todayOnly.year, todayOnly.month, todayOnly.day);
                            final end = DateTime(effectiveEndDate.year, effectiveEndDate.month, effectiveEndDate.day);
                            final diff = end.difference(today).inDays;
                            if (diff >= 0) daysLeft = diff;
                          }
                          return Row(
                            children: [
                              Text(
                                '${DateFormat('M/d').format(effectiveStartDate)} ~ ${effectiveEndDate != null ? DateFormat('M/d').format(effectiveEndDate) : '미정'}',
                                style: ResponsiveHelper.tinyStyle(context, color: AppColors.grey500),
                              ),
                              if (daysLeft != null) ...[
                                SizedBox(width: ResponsiveHelper.spacing(context, 5)),
                                _buildDDayChip(context, daysLeft),
                              ],
                            ],
                          );
                        }),
                      ],
                    ),
                  ),

                  // 날짜 모드: 상태 배지 / 일반 모드: 더보기 아이콘
                  if (dayStatus != null)
                    _buildDayStatusBadge(context, dayStatus)
                  else
                    Icon(
                      Icons.chevron_right,
                      color: AppColors.grey400,
                      size: ResponsiveHelper.iconSize(context, 24),
                    ),
                ],
              ),

              // 날짜 모드: 대기 요청 인라인 승인/거절
              if (hasPendingRequest) _buildPendingActions(context, app),
            ],
          ),
        ),
      ),
    );
  }

  /// 상태 배너
  Widget _buildStatusBanner(ApplicationModel app, bool hasResignRequest, bool hasTerminationRequest) {
    Color bgColor;
    Color textColor;
    IconData icon;
    String statusText;

    if (hasTerminationRequest) {
      bgColor = AppColors.errorBg;
      textColor = AppColors.errorDark;
      icon = Icons.cancel_outlined;
      final requestedAt = app.terminationRequestedAt;
      final daysLeft = requestedAt != null
          ? 3 - DateTime.now().difference(requestedAt).inDays
          : 0;
      statusText = '계약해지 요청중 (${daysLeft > 0 ? '$daysLeft일 후 자동 해지' : '오늘 자동 해지'})';
    } else {
      bgColor = AppColors.warningBg;
      textColor = AppColors.warningDark;
      icon = Icons.exit_to_app;
      final requestedAt = app.resignRequestedAt;
      final daysLeft = requestedAt != null
          ? 3 - DateTime.now().difference(requestedAt).inDays
          : 0;
      statusText = '퇴사 요청중 (${daysLeft > 0 ? '$daysLeft일 후 자동 승인' : '오늘 자동 승인'})';
    }

    return Container(
      margin: EdgeInsets.only(bottom: ResponsiveHelper.spacing(context, 12)),
      padding: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 12),
        vertical: ResponsiveHelper.spacing(context, 8),
      ),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(icon, size: ResponsiveHelper.iconSize(context, 16), color: textColor),
          SizedBox(width: ResponsiveHelper.spacing(context, 8)),
          Expanded(
            child: Text(
              statusText,
              style: ResponsiveHelper.smallStyle(context, color: textColor).copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 계약 만료 임박 경고 배너
  Widget _buildExpiringWarningBanner(BuildContext context) {
    final count = _expiringWorkers.length;
    return Container(
      margin: EdgeInsets.fromLTRB(
        ResponsiveHelper.spacing(context, 16),
        ResponsiveHelper.spacing(context, 8),
        ResponsiveHelper.spacing(context, 16),
        0,
      ),
      padding: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 14),
        vertical: ResponsiveHelper.spacing(context, 10),
      ),
      decoration: BoxDecoration(
        color: AppColors.warningBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(
            Icons.event_busy,
            color: AppColors.warningDark,
            size: ResponsiveHelper.iconSize(context, 18),
          ),
          SizedBox(width: ResponsiveHelper.spacing(context, 8)),
          Expanded(
            child: Text(
              '계약 만료 임박 $count명 (D-15 이내)',
              style: ResponsiveHelper.smallStyle(context, color: AppColors.warningDark)
                  .copyWith(fontWeight: FontWeight.w600),
            ),
          ),
          SizedBox(width: ResponsiveHelper.spacing(context, 8)),
          TextButton(
            onPressed: isLoading ? null : _batchExtendExpiringWorkers,
            style: TextButton.styleFrom(
              foregroundColor: AppColors.warningDark,
              padding: EdgeInsets.symmetric(
                horizontal: ResponsiveHelper.spacing(context, 12),
                vertical: ResponsiveHelper.spacing(context, 6),
              ),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(
              '일괄 연장',
              style: ResponsiveHelper.smallStyle(context, color: AppColors.warningDark)
                  .copyWith(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  /// 단일 연장 실행 (setLoading 미포함 — 일괄 처리에서 호출)
  Future<bool> _executeExtend(ApplicationModel app) async {
    if (app.workEndDate == null) return false;
    try {
      final originalStart = app.desiredStartDate ?? app.workDate;
      final contractMonths = (app.workEndDate!.year - originalStart.year) * 12
          + (app.workEndDate!.month - originalStart.month);
      final renewalMonths = contractMonths > 0 ? contractMonths : 1;
      final newStart = app.workEndDate!.add(const Duration(days: 1));
      final rawEndYear = app.workEndDate!.year + ((app.workEndDate!.month + renewalMonths - 1) ~/ 12);
      final rawEndMonth = (app.workEndDate!.month + renewalMonths - 1) % 12 + 1;
      final lastDayOfMonth = DateTime(rawEndYear, rawEndMonth + 1, 0).day;
      final newEnd = DateTime(rawEndYear, rawEndMonth, app.workEndDate!.day.clamp(1, lastDayOfMonth));

      final newApp = await _firestoreService.createRenewedApplication(
        original: app,
        newStartDate: newStart,
        newEndDate: newEnd,
      );
      await _firestoreService.createNotification(
        NotificationModel.createContractRenewed(
          userId: app.uid,
          businessName: app.businessName,
          businessId: app.businessId,
          newEndDate: newEnd,
          applicationId: newApp.id,
        ),
      );
      return true;
    } catch (e) {
      debugPrint('❌ 계약 연장 실패 (${app.uid}): $e');
      return false;
    }
  }

  /// 만료 임박자 일괄 연장
  Future<void> _batchExtendExpiringWorkers() async {
    final expiring = _expiringWorkers;
    if (expiring.isEmpty) return;

    final confirm = await DialogHelper.showConfirm(
      context,
      title: '계약 일괄 연장',
      message: '${expiring.length}명의 계약을 동일 기간으로 일괄 연장합니다.\n\n'
          '각 근무자에게 연장 알림이 발송됩니다.\n'
          '(계약서는 각 근무자 카드에서 개별 작성 가능)',
      confirmText: '일괄 연장',
      confirmColor: AppColors.success,
      icon: Icons.autorenew,
      iconColor: AppColors.success,
    );
    if (confirm != true || !mounted) return;

    setLoading(true);
    int successCount = 0;
    try {
      const batchSize = 5;
      for (var i = 0; i < expiring.length; i += batchSize) {
        final batch = expiring.sublist(i, min(i + batchSize, expiring.length));
        final results = await Future.wait(batch.map((item) => _executeExtend(item.application)));
        successCount += results.where((r) => r).length;
      }
    } finally {
      setLoading(false);
    }
    if (!mounted) return;
    if (successCount == expiring.length) {
      ToastHelper.showSuccess('$successCount명 계약 연장 완료');
    } else {
      ToastHelper.showError(
        '${expiring.length - successCount}명 연장 실패 ($successCount명 성공)',
      );
    }
    _loadFixedWorkers();
    widget.onChanged();
  }

  bool _isExpiringWithinDays(ApplicationModel app, int days) {
    if (!app.isLongTermApplication) return false;
    if (app.isTerminationApproved) return false;
    final endDate = app.actualResignDate ?? app.workEndDate;
    if (endDate == null) return false;
    final today = DateTime.now();
    final todayOnly = DateTime(today.year, today.month, today.day);
    final endOnly = DateTime(endDate.year, endDate.month, endDate.day);
    final diff = endOnly.difference(todayOnly).inDays;
    return diff >= 0 && diff <= days;
  }

  Widget _buildRenewalBanner(BuildContext context, ApplicationModel app, UserModel? user) {
    final endDate = app.workEndDate!;
    final today = DateTime.now();
    final todayOnly = DateTime(today.year, today.month, today.day);
    final endOnly = DateTime(endDate.year, endDate.month, endDate.day);
    final daysLeft = endOnly.difference(todayOnly).inDays;

    return Container(
      margin: EdgeInsets.only(bottom: ResponsiveHelper.spacing(context, 10)),
      padding: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 12),
        vertical: ResponsiveHelper.spacing(context, 10),
      ),
      decoration: BoxDecoration(
        color: AppColors.warningBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.event_note, size: ResponsiveHelper.iconSize(context, 14), color: AppColors.warningDark),
              SizedBox(width: ResponsiveHelper.spacing(context, 6)),
              Text(
                '계약 만료 D-$daysLeft (${endDate.month}/${endDate.day})',
                style: ResponsiveHelper.smallStyle(context, color: AppColors.warningDark)
                    .copyWith(fontWeight: FontWeight.w600),
              ),
            ],
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 8)),
          Row(
            children: [
              Expanded(
                child: _actionButton(
                  context,
                  label: '연장',
                  icon: Icons.autorenew,
                  bgColor: AppColors.successBg,
                  textColor: AppColors.successDark,
                  onTap: () => _showRenewalDecisionDialog(app, user, extend: true),
                ),
              ),
              SizedBox(width: ResponsiveHelper.spacing(context, 8)),
              Expanded(
                child: _actionButton(
                  context,
                  label: '종료',
                  icon: Icons.stop_circle_outlined,
                  bgColor: AppColors.errorBg,
                  textColor: AppColors.error,
                  onTap: () => _showRenewalDecisionDialog(app, user, extend: false),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 계약 갱신 결정 완료 배너 (연장됨 / 종료 예정)
  Widget _buildRenewalDecisionBanner(BuildContext context, ApplicationModel app) {
    final isExtend = app.renewalDecision == AppStatus.renewalExtend;
    final color = isExtend ? AppColors.success : AppColors.error;
    final bgColor = isExtend ? AppColors.successBg : AppColors.errorBg;
    final icon = isExtend ? Icons.autorenew : Icons.stop_circle_outlined;

    // 연장됨: 다음 계약 기간 계산 (processRenewal과 동일 공식)
    String label;
    if (isExtend && app.workEndDate != null) {
      final originalStart = app.desiredStartDate ?? app.workDate;
      final contractMonths = (app.workEndDate!.year - originalStart.year) * 12
          + (app.workEndDate!.month - originalStart.month);
      final renewalMonths = contractMonths > 0 ? contractMonths : 1;
      final newStart = app.workEndDate!.add(const Duration(days: 1));
      final rawEndYear = app.workEndDate!.year + ((app.workEndDate!.month + renewalMonths - 1) ~/ 12);
      final rawEndMonth = (app.workEndDate!.month + renewalMonths - 1) % 12 + 1;
      final lastDay = DateTime(rawEndYear, rawEndMonth + 1, 0).day;
      final newEnd = DateTime(rawEndYear, rawEndMonth, app.workEndDate!.day.clamp(1, lastDay));
      label = '다음 계약 ${newStart.month}/${newStart.day} ~ ${newEnd.month}/${newEnd.day}';
    } else {
      label = isExtend ? '다음 계약 연장됨' : '계약 종료 예정';
    }

    return Container(
      margin: EdgeInsets.only(bottom: ResponsiveHelper.spacing(context, 8)),
      padding: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 10),
        vertical: ResponsiveHelper.spacing(context, 6),
      ),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: ResponsiveHelper.iconSize(context, 13), color: color),
          SizedBox(width: ResponsiveHelper.spacing(context, 5)),
          Text(
            label,
            style: ResponsiveHelper.tinyStyle(context, color: color)
                .copyWith(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  /// 계약서 서명 대기 배너 (연장 후 근무자 미서명)
  Widget _buildContractPendingBanner(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: EdgeInsets.only(bottom: ResponsiveHelper.spacing(context, 8)),
      padding: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 10),
        vertical: ResponsiveHelper.spacing(context, 7),
      ),
      decoration: BoxDecoration(
        color: AppColors.infoBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.info.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Icon(Icons.draw_outlined, size: ResponsiveHelper.iconSize(context, 14), color: AppColors.infoDark),
          SizedBox(width: ResponsiveHelper.spacing(context, 6)),
          Text(
            '계약서 서명 대기 중',
            style: ResponsiveHelper.smallStyle(context, color: AppColors.infoDark)
                .copyWith(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  /// 남은 계약일수 D-day 배지
  Widget _buildDDayChip(BuildContext context, int daysLeft) {
    final Color color;
    if (daysLeft <= 7) {
      color = AppColors.error;
    } else if (daysLeft <= 15) {
      color = AppColors.warning;
    } else if (daysLeft <= 30) {
      color = AppColors.info;
    } else {
      color = AppColors.grey400;
    }
    final label = daysLeft == 0 ? 'D-Day' : 'D-$daysLeft';

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 5),
        vertical: 1,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(
        label,
        style: ResponsiveHelper.tinyStyle(context, color: color)
            .copyWith(fontWeight: FontWeight.w700),
      ),
    );
  }

  Widget _actionButton(
    BuildContext context, {
    required String label,
    required IconData icon,
    required Color bgColor,
    required Color textColor,
    required VoidCallback onTap,
  }) {
    return Material(
      color: bgColor,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: ResponsiveHelper.spacing(context, 8)),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: ResponsiveHelper.iconSize(context, 14), color: textColor),
              SizedBox(width: ResponsiveHelper.spacing(context, 4)),
              Text(label, style: ResponsiveHelper.smallStyle(context, color: textColor)
                  .copyWith(fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showRenewalDecisionDialog(
    ApplicationModel app,
    UserModel? user, {
    required bool extend,
  }) async {
    if (app.workEndDate == null) return;
    if (extend) {
      // 기존 계약 기간과 동일한 개월수로 종료일 자동 계산
      final originalStart = app.desiredStartDate ?? app.workDate;
      final contractMonths = (app.workEndDate!.year - originalStart.year) * 12
          + (app.workEndDate!.month - originalStart.month);
      final renewalMonths = contractMonths > 0 ? contractMonths : 1;
      final newStart = app.workEndDate!.add(const Duration(days: 1));
      final rawEndYear = app.workEndDate!.year + ((app.workEndDate!.month + renewalMonths - 1) ~/ 12);
      final rawEndMonth = (app.workEndDate!.month + renewalMonths - 1) % 12 + 1;
      final lastDayOfMonth = DateTime(rawEndYear, rawEndMonth + 1, 0).day;
      final newEnd = DateTime(
        rawEndYear,
        rawEndMonth,
        app.workEndDate!.day.clamp(1, lastDayOfMonth),
      );

      final confirm = await DialogHelper.showConfirm(
        context,
        title: '계약 연장',
        message: '${user?.name ?? ''}님의 계약을 $renewalMonths개월 연장합니다.\n\n'
            '새 계약 기간: ${newStart.month}/${newStart.day} ~ ${newEnd.month}/${newEnd.day}\n\n'
            '연장 후 근로계약서 작성 화면이 열립니다.',
        confirmText: '연장 및 계약서 작성',
        confirmColor: AppColors.success,
        icon: Icons.autorenew,
        iconColor: AppColors.success,
      );
      if (confirm != true || !mounted) return;

      final newApp = await _processRenewal(app, user, newEndDate: newEnd);
      if (newApp != null && mounted) {
        await _createContractForRenewal(newApp, user);
      }
    } else {
      // 종료: 확인 후 처리
      final confirm = await DialogHelper.showConfirm(
        context,
        title: '계약 종료',
        message: '${user?.name ?? ''}님의 계약을 ${app.workEndDate!.month}/${app.workEndDate!.day}에 종료하시겠습니까?\n근무자에게 종료 통보 알림이 발송됩니다.',
        confirmText: '종료',
        confirmColor: AppColors.error,
        icon: Icons.stop_circle_outlined,
        iconColor: AppColors.error,
      );
      if (confirm != true || !mounted) return;

      await _processTermination(app, user);
    }
  }

  Future<ApplicationModel?> _processRenewal(ApplicationModel app, UserModel? user, {required DateTime newEndDate}) async {
    if (!mounted || isLoading) return null;
    setLoading(true);
    try {
      // 1. 신규 계약 생성 + 원본 renewalDecision=EXTEND 표시 (배치로 원자 처리)
      // createRenewedApplication 내부에서 원본 문서 업데이트까지 배치로 처리하므로
      // 여기서 별도로 updateApplicationFields(renewalDecision)를 호출하면 안 됨.
      final newStart = app.workEndDate!.add(const Duration(days: 1));
      final newApp = await _firestoreService.createRenewedApplication(
        original: app,
        newStartDate: newStart,
        newEndDate: newEndDate,
      );

      // 2. 근무자에게 연장 알림
      await _firestoreService.createNotification(
        NotificationModel.createContractRenewed(
          userId: app.uid,
          businessName: app.businessName,
          businessId: app.businessId,
          newEndDate: newEndDate,
          applicationId: newApp.id,
        ),
      );

      if (mounted) {
        _loadFixedWorkers();
        widget.onChanged();
      }
      return newApp;
    } catch (e) {
      debugPrint('❌ 계약 연장 실패: $e');
      if (mounted) ToastHelper.showError('계약 연장에 실패했습니다');
      return null;
    } finally {
      setLoading(false);
    }
  }

  /// 연장된 신규 Application에 대해 근로계약서 작성 후 발송
  Future<void> _createContractForRenewal(ApplicationModel newApp, UserModel? user) async {
    if (user == null || !mounted) return;
    final businessId = newApp.businessId;
    if (businessId.isEmpty) {
      ToastHelper.showSuccess('계약이 연장되었습니다');
      return;
    }

    // 템플릿 선택
    final articles = await ContractTemplateSelectorDialog.show(context, businessId: businessId);
    if (articles == null || !mounted) {
      ToastHelper.showSuccess('계약이 연장되었습니다 (계약서는 나중에 작성할 수 있습니다)');
      return;
    }

    setLoading(true);
    try {
      // 업무 상세 로드 (WorkDetailData는 workType으로 매칭)
      final workDetails = newApp.toId?.isNotEmpty == true
          ? await _firestoreService.getWorkDetails(newApp.toId!)
          : <WorkDetailData>[];
      if (!mounted) return;

      if (workDetails.isEmpty) {
        ToastHelper.showError('업무 정보를 불러올 수 없습니다');
        return;
      }

      // 1592행 isEmpty 조기 반환으로 여기 도달 시 workDetails는 비어있지 않음 — .first 안전
      final workDetail = workDetails.firstWhere(
        (w) => w.workType == newApp.selectedWorkType,
        orElse: () => workDetails.first,
      );

      final business = await _firestoreService.getBusinessById(businessId);
      if (!mounted) return;
      if (business == null) {
        ToastHelper.showSuccess('계약이 연장되었습니다');
        return;
      }

      final contract = await ContractService().findOrCreateContract(
        application: newApp,
        business: business,
        worker: user,
        workDetail: workDetail,
        articles: articles,
      );
      if (!mounted) return;

      // 연장 계약서는 항상 서명 화면으로 이동 — 사업주가 내용 확인 후 서명
      if (!mounted) return;
      final nav = Navigator.of(context, rootNavigator: true);
      await nav.push(MaterialPageRoute(
        builder: (_) => ContractSignScreen(contract: contract, role: 'employer'),
      ));
      if (mounted) ToastHelper.showSuccess('계약이 연장되었습니다');
    } catch (e) {
      debugPrint('❌ 연장 계약서 생성 실패: $e');
      if (mounted) ToastHelper.showError('계약서 작성에 실패했습니다. 상세 정보에서 다시 시도하세요');
    } finally {
      setLoading(false);
    }
  }

  Future<void> _processTermination(ApplicationModel app, UserModel? user) async {
    if (!mounted || isLoading) return;
    // async gap 이전에 미리 추출 — BuildContext across async gaps 오류 방지
    final adminUID = context.read<UserProvider>().currentUser?.uid;
    setLoading(true);
    try {
      // 1. renewalDecision = 'TERMINATE'
      await _firestoreService.updateApplicationFields(
        app.id,
        {'renewalDecision': AppStatus.renewalTerminate},
      );

      // 2. 근무자에게 종료 통보 알림
      await _firestoreService.createNotification(
        NotificationModel.createContractTerminating(
          userId: app.uid,
          businessName: app.businessName,
          businessId: app.businessId,
          endDate: app.workEndDate!,
          applicationId: app.id,
        ),
      );

      // [BUG-수정 M-2] workEndDate가 오늘이거나 이미 지난 경우 즉시 CANCELED로 전환.
      // 미래 종료일인 경우 Cloud Functions D-0 처리에 위임(현재 설계 유지).
      // cancelConfirmedApplication 내부에서 _decrementTOConfirmed도 함께 처리됨.
      final endDate = app.workEndDate;
      if (endDate != null) {
        final today = DateTime.now();
        final endDateOnly = DateTime(endDate.year, endDate.month, endDate.day);
        final todayOnly = DateTime(today.year, today.month, today.day);
        if (!endDateOnly.isAfter(todayOnly)) {
          // 이미 만료됐거나 오늘이 종료일인 경우 — 즉시 CANCELED 처리
          // [C-H4-FIX] 반환값 체크 — false 반환 시(이미 취소됨·찾을 수 없음) 후속 처리 스킵
          final canceled = await _firestoreService.cancelConfirmedApplication(
            app.id,
            canceledBy: adminUID,
            cancelReason: '계약 종료 (만료일 도달)',
          );
          if (canceled) {
            // [CRITICAL-005 수정] 만료일 당일 즉시 처리 시 terminationCompletionNotifiedAt 설정
            // Flutter에서 이미 "계약 종료 통보" 알림을 발송했으므로, Functions D-0 처리에서
            // 이 필드가 없으면 "계약 종료 완료" 알림을 이중 발송하는 버그 방지
            await _firestoreService.updateApplicationFields(
              app.id,
              {'terminationCompletionNotifiedAt': Timestamp.now()},
            );
          }
        }
        // 미래 종료일이면 Cloud Functions가 D-0에 자동 처리 — 별도 조치 불필요
      }

      if (mounted) {
        ToastHelper.showSuccess('계약 종료가 통보되었습니다');
        _loadFixedWorkers();
        widget.onChanged();
      }
    } catch (e) {
      debugPrint('❌ 계약 종료 처리 실패: $e');
      if (mounted) ToastHelper.showError('계약 종료 처리에 실패했습니다');
    } finally {
      setLoading(false);
    }
  }

  /// 하단 버튼
  Widget _buildBottomBar(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 16)),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AppColors.border)),
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(20),
          bottomRight: Radius.circular(20),
        ),
      ),
      child: SizedBox(
        width: double.infinity,
        child: OutlinedButton(
          onPressed: () => Navigator.pop(context),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.grey600,
            side: BorderSide(color: AppColors.grey300),
            padding: EdgeInsets.symmetric(vertical: ResponsiveHelper.spacing(context, 14)),
          ),
          child: const Text('닫기'),
        ),
      ),
    );
  }

  /// 근무 요일 포맷
  String _formatWorkDays(List<String>? workDays) {
    if (workDays == null || workDays.isEmpty) return '매일';
    if (workDays.length == 7) return '매일';
    return workDays.join(', ');
  }

  // ============================================================
  // 📋 액션 메서드
  // ============================================================

  /// 근무자 액션 선택 바텀시트
  void _showWorkerActions(_FixedWorkerItem item) {
    final app = item.application;
    final user = item.user;
    final name = user?.name ?? '이름 없음';

    showModalBottomSheet(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 12),
                Container(
                  width: 40, height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.grey300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Flexible(
                  child: SingleChildScrollView(
                    child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      ResponsiveHelper.spacing(context, 16),
                      ResponsiveHelper.spacing(context, 12),
                      ResponsiveHelper.spacing(context, 16),
                      ResponsiveHelper.spacing(context, 16),
                    ),
                    child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 헤더
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            style: ResponsiveHelper.subtitleStyle(context).copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            '${app.selectedWorkType} · ${_formatWorkDays(app.workDays)}',
                            style: ResponsiveHelper.smallStyle(context, color: AppColors.grey600),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                SizedBox(height: ResponsiveHelper.spacing(context, 20)),
                Divider(height: 1, color: AppColors.border),
                SizedBox(height: ResponsiveHelper.spacing(context, 8)),

                // 메뉴 항목들
                _buildActionItem(
                  context,
                  icon: Icons.person_outline,
                  title: '상세 정보 보기',
                  subtitle: '근무자의 상세 정보 확인',
                  color: AppColors.info,
                  onTap: () {
                    Navigator.pop(context);
                    WidgetsBinding.instance.addPostFrameCallback((_) => _showWorkerDetail(item));
                  },
                ),

                _buildActionItem(
                  context,
                  icon: Icons.add_circle_outline,
                  title: '추가 근무 요청',
                  subtitle: '휴무일에 추가 근무 요청',
                  color: AppColors.success,
                  onTap: () {
                    Navigator.pop(context);
                    WidgetsBinding.instance.addPostFrameCallback((_) => _showExtraWorkRequestDialog(app));
                  },
                ),

                _buildActionItem(
                  context,
                  icon: Icons.remove_circle_outline,
                  title: '미출근 요청',
                  subtitle: '특정 날짜 근무 제외 요청',
                  color: AppColors.warning,
                  onTap: () {
                    Navigator.pop(context);
                    WidgetsBinding.instance.addPostFrameCallback((_) => _showNoWorkRequestDialog(app));
                  },
                ),

                // 계약해지 요청 (퇴사 요청이 없을 때만)
                if (app.resignStatus != AppStatus.pending && app.terminationStatus != AppStatus.pending)
                  _buildActionItem(
                    context,
                    icon: Icons.cancel_outlined,
                    title: '계약해지 요청',
                    subtitle: '고정 근무 계약 해지 요청',
                    color: AppColors.error,
                    onTap: () {
                      Navigator.pop(context);
                      WidgetsBinding.instance.addPostFrameCallback((_) => _showTerminationRequestDialog(item));
                    },
                  ),

                // 해지 요청 취소 (요청 중일 때만)
                if (app.terminationStatus == AppStatus.pending)
                  _buildActionItem(
                    context,
                    icon: Icons.undo,
                    title: '해지 요청 취소',
                    subtitle: '계약해지 요청 철회',
                    color: AppColors.grey600,
                    onTap: () {
                      Navigator.pop(context);
                      WidgetsBinding.instance.addPostFrameCallback((_) => _cancelTerminationRequest(app));
                    },
                  ),

                // 계약 연장 (종료일 있고 갱신 미결정일 때)
                if (app.workEndDate != null &&
                    app.renewalDecision == null &&
                    !app.isTerminationApproved)
                  _buildActionItem(
                    context,
                    icon: Icons.autorenew,
                    title: '계약 연장',
                    subtitle: '계약 기간을 연장합니다',
                    color: AppColors.success,
                    onTap: () {
                      Navigator.pop(context);
                      WidgetsBinding.instance.addPostFrameCallback((_) => _showRenewalDecisionDialog(app, user, extend: true));
                    },
                  ),

                // 계약 종료 통보 (종료일 있고 갱신 미결정일 때)
                if (app.workEndDate != null &&
                    app.renewalDecision == null &&
                    !app.isTerminationApproved)
                  _buildActionItem(
                    context,
                    icon: Icons.stop_circle_outlined,
                    title: '계약 종료 통보',
                    subtitle: '만료일에 계약을 종료합니다',
                    color: AppColors.error,
                    onTap: () {
                      Navigator.pop(context);
                      WidgetsBinding.instance.addPostFrameCallback((_) => _showRenewalDecisionDialog(app, user, extend: false));
                    },
                  ),

                SizedBox(height: ResponsiveHelper.spacing(context, 8)),
              ],
            ),         // 내부 Column 끝
            ),         // Padding 끝
          ),           // SingleChildScrollView 끝
          ),           // Flexible 끝
          ],           // 외부 Column children 끝
        ),             // 외부 Column 끝
      ),               // SafeArea 끝
      );               // Container 끝
      },
    );
  }

  /// 액션 아이템 빌더
  Widget _buildActionItem(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: ResponsiveHelper.spacing(context, 8),
            vertical: ResponsiveHelper.spacing(context, 12),
          ),
          child: Row(
            children: [
              Container(
                padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 10)),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: ResponsiveHelper.iconSize(context, 22)),
              ),
              SizedBox(width: ResponsiveHelper.spacing(context, 14)),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: ResponsiveHelper.bodyStyle(context).copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: ResponsiveHelper.smallStyle(context, color: AppColors.grey500),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
                color: AppColors.grey400,
                size: ResponsiveHelper.iconSize(context, 20),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 근무자 상세 정보 (WorkerDetailDialog 활용)
  void _showWorkerDetail(_FixedWorkerItem item) {
    if (item.user == null) {
      ToastHelper.showError('사용자 정보를 불러올 수 없습니다');
      return;
    }

    // 위 null 가드로 item.user! 안전
    WorkerDetailDialog.show(
      context: context,
      user: item.user!,
      application: item.application,
      businessId: _selectedBusinessId!,
      isConfirmed: true,
      showApprovalButtons: false,
      onStatusChanged: () {
        widget.onChanged();
        _loadFixedWorkers();
      },
    );
  }

  /// 추가 근무 요청 다이얼로그
  Future<void> _showExtraWorkRequestDialog(ApplicationModel app) async {
    // 🔥 실제 근무 기간 계산 (희망시작일/퇴사일 우선)
    final effectiveStartDate = app.desiredStartDate ?? app.workDate;
    final effectiveEndDate = app.actualResignDate ?? app.workEndDate;
    
    if (effectiveEndDate == null) {
      ToastHelper.showError('근무 종료일 정보가 없습니다');
      return;
    }
    
    // 선택 가능한 첫 날짜 찾기
    DateTime? findFirstSelectableDate() {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final workStart = DateTime(effectiveStartDate.year, effectiveStartDate.month, effectiveStartDate.day);
      final workEnd = DateTime(effectiveEndDate.year, effectiveEndDate.month, effectiveEndDate.day);

      DateTime checkDate = now.isAfter(workStart) ? today : workStart;

      while (!checkDate.isAfter(workEnd)) {
        bool isOriginalWorkDay = false;
        if (app.workDays != null && app.workDays!.isNotEmpty) {
          isOriginalWorkDay = app.workDays!.contains(FormatHelper.weekday(checkDate));
        } else {
          isOriginalWorkDay = true;
        }

        if (!isOriginalWorkDay) {
          final alreadyExtra = app.extraWorkDates?.any((d) =>
              d.year == checkDate.year && d.month == checkDate.month && d.day == checkDate.day) ?? false;
          if (!alreadyExtra) return checkDate;
        } else if (app.leaveDates != null) {
          final isLeaveDay = app.leaveDates!.any((d) =>
              d.year == checkDate.year && d.month == checkDate.month && d.day == checkDate.day);
          if (isLeaveDay) return checkDate;
        }

        checkDate = checkDate.add(const Duration(days: 1));
      }

      return null;
    }

    final initialDate = findFirstSelectableDate();

    if (initialDate == null) {
      ToastHelper.showWarning('추가 근무 요청 가능한 날짜가 없습니다');
      return;
    }

    final selectedDate = await DatePickerBottomSheet.show(
      context: context,
      initialDate: initialDate,
      title: '추가 근무 날짜 선택',
      minDate: DateTime.now(),
      maxDate: effectiveEndDate,
      enabledDayPredicate: (date) {
        final workStart = DateTime(effectiveStartDate.year, effectiveStartDate.month, effectiveStartDate.day);
        final workEnd = DateTime(effectiveEndDate.year, effectiveEndDate.month, effectiveEndDate.day);
        if (date.isBefore(workStart) || date.isAfter(workEnd)) return false;

        bool isOriginalWorkDay = false;
        if (app.workDays != null && app.workDays!.isNotEmpty) {
          isOriginalWorkDay = app.workDays!.contains(FormatHelper.weekday(date));
        } else {
          isOriginalWorkDay = true;
        }

        if (isOriginalWorkDay) {
          return app.leaveDates?.any((d) =>
              d.year == date.year && d.month == date.month && d.day == date.day) ?? false;
        }

        if (app.extraWorkDates != null) {
          final alreadyExtra = app.extraWorkDates!.any((d) =>
              d.year == date.year && d.month == date.month && d.day == date.day);
          if (alreadyExtra) return false;
        }

        return true;
      },
    );

    if (selectedDate == null || !mounted) return;

    final reasonController = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StyledDialog(
        title: '추가 근무 요청',
        icon: Icons.add_circle_outline,
        headerColor: AppColors.success,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            StyledDialogInfoCard.success(
              FormatHelper.formatDateLong(selectedDate),
            ),
            SizedBox(height: ResponsiveHelper.spacing(context, 16)),
            Text(
              '요청 사유 (선택)',
              style: ResponsiveHelper.bodyStyle(context).copyWith(fontWeight: FontWeight.bold),
            ),
            SizedBox(height: ResponsiveHelper.spacing(context, 8)),
            TextField(
              controller: reasonController,
              decoration: InputDecoration(
                hintText: '추가 근무 요청 사유를 입력하세요',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
              maxLines: 2,
            ),
          ],
        ),
        actions: [
          StyledDialogButton.cancel(
            onPressed: () => Navigator.pop(context, false),
          ),
          StyledDialogButton.primary(
            text: '요청',
            onPressed: () => Navigator.pop(context, true),
          ),
        ],
      ),
    );

    final reason = reasonController.text.trim();
    reasonController.dispose();

    if (confirmed != true || !mounted) return;

    await _submitExtraWorkRequest(app, selectedDate, reason);
  }

  /// 추가 근무 요청 제출
  Future<void> _submitExtraWorkRequest(ApplicationModel app, DateTime date, String reason) async {
    final userProvider = context.read<UserProvider>();
    final adminUid = userProvider.currentUser?.uid;

    if (adminUid == null) {
      ToastHelper.showError('관리자 정보를 찾을 수 없습니다');
      return;
    }

    final worker = await _firestoreService.getUser(app.uid);
    if (!mounted) return;
    final workerName = worker?.name ?? '이름 없음';

    final request = ScheduleChangeRequestModel(
      id: '',
      businessId: _selectedBusinessId!,
      applicationId: app.id,
      applicantUid: app.uid,
      applicantName: workerName,
      targetDate: DateTime(date.year, date.month, date.day),
      requestType: RequestType.EXTRA_WORK,
      requestedBy: RequesterType.ADMIN,
      requestedByUid: adminUid,
      requestedAt: DateTime.now(),
      reason: reason.isEmpty ? null : reason,
      wageAmount: app.wage,
    );

    final requestId = await _firestoreService.createScheduleChangeRequest(request);

    if (!mounted) return;
    if (requestId != null) {
      ToastHelper.showSuccess('추가 근무 요청이 전송되었습니다');
      widget.onChanged();
      _loadFixedWorkers();
    } else {
      ToastHelper.showError('추가 근무 요청 실패');
    }
  }

  /// 미출근 요청 다이얼로그
  Future<void> _showNoWorkRequestDialog(ApplicationModel app) async {
    // 🔥 실제 근무 기간 계산 (희망시작일/퇴사일 우선)
    final effectiveStartDate = app.desiredStartDate ?? app.workDate;
    final effectiveEndDate = app.actualResignDate ?? app.workEndDate;
    
    if (effectiveEndDate == null) {
      ToastHelper.showError('근무 종료일 정보가 없습니다');
      return;
    }
    
    // 선택 가능한 첫 날짜 찾기
    DateTime? findFirstSelectableDate() {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final workStart = DateTime(effectiveStartDate.year, effectiveStartDate.month, effectiveStartDate.day);
      final workEnd = DateTime(effectiveEndDate.year, effectiveEndDate.month, effectiveEndDate.day);

      DateTime checkDate = now.isAfter(workStart) ? today : workStart;

      while (!checkDate.isAfter(workEnd)) {
        bool isWorkDay = false;
        if (app.workDays != null && app.workDays!.isNotEmpty) {
          isWorkDay = app.workDays!.contains(FormatHelper.weekday(checkDate));
        } else {
          isWorkDay = true;
        }

        if (isWorkDay) {
          final isLeaveDay = app.leaveDates?.any((d) =>
              d.year == checkDate.year && d.month == checkDate.month && d.day == checkDate.day) ?? false;
          if (!isLeaveDay) return checkDate;
        }

        checkDate = checkDate.add(const Duration(days: 1));
      }

      return null;
    }

    final initialDate = findFirstSelectableDate();

    if (initialDate == null) {
      ToastHelper.showWarning('미출근 요청 가능한 날짜가 없습니다');
      return;
    }

    final selectedDate = await DatePickerBottomSheet.show(
      context: context,
      initialDate: initialDate,
      title: '미출근 날짜 선택',
      minDate: DateTime.now(),
      maxDate: effectiveEndDate,
      enabledDayPredicate: (date) {
        final workStart = DateTime(effectiveStartDate.year, effectiveStartDate.month, effectiveStartDate.day);
        final workEnd = DateTime(effectiveEndDate.year, effectiveEndDate.month, effectiveEndDate.day);
        if (date.isBefore(workStart) || date.isAfter(workEnd)) return false;

        bool isWorkDay = false;
        if (app.workDays != null && app.workDays!.isNotEmpty) {
          isWorkDay = app.workDays!.contains(FormatHelper.weekday(date));
        } else {
          isWorkDay = true;
        }

        if (!isWorkDay) return false;

        return !(app.leaveDates?.any((d) =>
            d.year == date.year && d.month == date.month && d.day == date.day) ?? false);
      },
    );

    if (selectedDate == null || !mounted) return;

    final reasonController = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StyledDialog(
        title: '미출근 요청',
        icon: Icons.remove_circle_outline,
        headerColor: AppColors.warning,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            StyledDialogInfoCard.warning(
              FormatHelper.formatDateLong(selectedDate),
            ),
            SizedBox(height: ResponsiveHelper.spacing(context, 16)),
            Text(
              '요청 사유',
              style: ResponsiveHelper.bodyStyle(context).copyWith(fontWeight: FontWeight.bold),
            ),
            SizedBox(height: ResponsiveHelper.spacing(context, 8)),
            TextField(
              controller: reasonController,
              decoration: InputDecoration(
                hintText: '미출근 요청 사유를 입력하세요',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
              maxLines: 2,
            ),
          ],
        ),
        actions: [
          StyledDialogButton.cancel(
            onPressed: () => Navigator.pop(context, false),
          ),
          StyledDialogButton.primary(
            text: '요청',
            onPressed: () => Navigator.pop(context, true),
          ),
        ],
      ),
    );

    final noWorkReason = reasonController.text.trim();
    reasonController.dispose();

    if (confirmed != true || !mounted) return;

    await _submitNoWorkRequest(app, selectedDate, noWorkReason);
  }

  /// 미출근 요청 제출
  Future<void> _submitNoWorkRequest(ApplicationModel app, DateTime date, String reason) async {
    final userProvider = context.read<UserProvider>();
    final adminUid = userProvider.currentUser?.uid;

    if (adminUid == null) {
      ToastHelper.showError('관리자 정보를 찾을 수 없습니다');
      return;
    }

    final worker = await _firestoreService.getUser(app.uid);
    if (!mounted) return;
    final workerName = worker?.name ?? '이름 없음';

    final request = ScheduleChangeRequestModel(
      id: '',
      businessId: _selectedBusinessId!,
      applicationId: app.id,
      applicantUid: app.uid,
      applicantName: workerName,
      targetDate: DateTime(date.year, date.month, date.day),
      requestType: RequestType.NO_WORK,
      requestedBy: RequesterType.ADMIN,
      requestedByUid: adminUid,
      requestedAt: DateTime.now(),
      reason: reason.isEmpty ? null : reason,
      wageAmount: app.wage,
    );

    final requestId = await _firestoreService.createScheduleChangeRequest(request);

    if (!mounted) return;
    if (requestId != null) {
      ToastHelper.showSuccess('미출근 요청이 전송되었습니다');
      widget.onChanged();
      _loadFixedWorkers();
    } else {
      ToastHelper.showError('미출근 요청 실패');
    }
  }

  // ============================================================
  // 🔥 계약해지 요청 (NEW)
  // ============================================================

  /// 계약해지 요청 다이얼로그
  Future<void> _showTerminationRequestDialog(_FixedWorkerItem item) async {
    final app = item.application;
    final user = item.user;
    final name = user?.name ?? '이름 없음';

    String? selectedReason;
    final customReasonController = TextEditingController();

    final reasons = [
      '업무 능력 부족',
      '근태 불량 (지각/결근)',
      '업무 태도 불량',
      '인력 구조 조정',
      '계약 조건 불일치',
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
                                '계약해지 요청',
                                style: ResponsiveHelper.subtitleStyle(context).copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                '$name님',
                                style: ResponsiveHelper.smallStyle(context, color: Colors.white.withValues(alpha: 0.7)),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: Icon(Icons.close, color: Colors.white, size: ResponsiveHelper.iconSize(context, 24)),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ],
                    ),
                  ),

                  // 안내
                  Container(
                    margin: EdgeInsets.all(ResponsiveHelper.spacing(context, 16)),
                    padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 12)),
                    decoration: BoxDecoration(
                      color: AppColors.infoBg,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.info_outline, size: ResponsiveHelper.iconSize(context, 20), color: AppColors.infoDark),
                        SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                        Expanded(
                          child: Text(
                            '근무자가 3일 이내 승인/거절하지 않으면\n자동으로 계약이 해지됩니다.',
                            style: ResponsiveHelper.smallStyle(context, color: AppColors.infoDark),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // 사유 선택
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: ResponsiveHelper.spacing(context, 16)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '해지 사유를 선택해주세요',
                          style: ResponsiveHelper.bodyStyle(context).copyWith(fontWeight: FontWeight.w600),
                        ),
                        SizedBox(height: ResponsiveHelper.spacing(context, 12)),

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
                                color: selectedReason == reason ? AppColors.errorBg : AppColors.grey100,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: selectedReason == reason ? AppColors.error : AppColors.grey300,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    selectedReason == reason
                                        ? Icons.radio_button_checked
                                        : Icons.radio_button_off,
                                    color: selectedReason == reason ? AppColors.error : AppColors.grey400,
                                    size: ResponsiveHelper.iconSize(context, 20),
                                  ),
                                  SizedBox(width: ResponsiveHelper.spacing(context, 12)),
                                  Text(reason, style: ResponsiveHelper.bodyStyle(context)),
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
                              hintText: '상세 사유를 입력하세요',
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
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

                  SizedBox(height: ResponsiveHelper.spacing(context, 8)),

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
                              padding: EdgeInsets.symmetric(vertical: ResponsiveHelper.spacing(context, 12)),
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
                              padding: EdgeInsets.symmetric(vertical: ResponsiveHelper.spacing(context, 12)),
                            ),
                            child: const Text('해지 요청'),
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

    customReasonController.dispose();

    if (result == null || !mounted) return;

    await _submitTerminationRequest(app, result);
  }

  /// 계약해지 요청 제출
  Future<void> _submitTerminationRequest(ApplicationModel app, String reason) async {
    final userProvider = context.read<UserProvider>();
    final adminUid = userProvider.currentUser?.uid;

    if (adminUid == null) {
      ToastHelper.showError('관리자 정보를 찾을 수 없습니다');
      return;
    }

    try {
      final success = await _firestoreService.requestTermination(
        applicationId: app.id,
        reason: reason,
        requestedByUid: adminUid,
      );

      if (success && mounted) {
        ToastHelper.showSuccess('계약해지 요청이 전송되었습니다');
        widget.onChanged();
        _loadFixedWorkers();
      } else if (mounted) {
        ToastHelper.showError('계약해지 요청에 실패했습니다');
      }
    } catch (e) {
      debugPrint('❌ 계약해지 요청 실패: $e');
      if (mounted) {
        ToastHelper.showError('계약해지 요청 중 오류가 발생했습니다');
      }
    }
  }

  /// 해지 요청 취소
  Future<void> _cancelTerminationRequest(ApplicationModel app) async {
    final confirmed = await DialogHelper.showConfirm(
      context,
      title: '해지 요청 취소',
      message: '계약해지 요청을 취소하시겠습니까?',
      confirmText: '취소하기',
      confirmColor: AppColors.warning,
    );

    if (confirmed != true || !mounted) return;

    try {
      final success = await _firestoreService.cancelTerminationRequest(app.id);

      if (success && mounted) {
        ToastHelper.showSuccess('해지 요청이 취소되었습니다');
        widget.onChanged();
        _loadFixedWorkers();
      } else if (mounted) {
        ToastHelper.showError('해지 요청 취소에 실패했습니다');
      }
    } catch (e) {
      debugPrint('❌ 해지 요청 취소 실패: $e');
      if (mounted) {
        ToastHelper.showError('해지 요청 취소 중 오류가 발생했습니다');
      }
    }
  }
}

class _FixedWorkerItem {
  final ApplicationModel application;
  final UserModel? user;
  final String? workTypeIcon;
  final String? workTypeColor;
  final String? workTypeBackgroundColor;  // 🔥 추가

  _FixedWorkerItem({
    required this.application,
    this.user,
    this.workTypeIcon,
    this.workTypeColor,
    this.workTypeBackgroundColor,  // 🔥 추가
  });
}