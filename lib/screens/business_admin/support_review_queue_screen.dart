// lib/screens/business_admin/support_review_queue_screen.dart
// ADMIN REDESIGN — PHASE 2A
// 지원 검토 Queue — 전체 기간 PENDING 지원서 탐색 + 승인/거절
//
// 설계 원칙:
//   - 새 승인 로직 없음: FirestoreService.updateApplicationStatus 재사용
//   - businessIds는 caller(Home)가 서버 인증 기반으로 전달
//   - 날짜 제한 없이 전체 PENDING 표시 (monthly calendar 대체)
//   - single primary scroll — nested scroll 없음
//
// KNOWN LIMITATIONS:
//   - V1: 클라이언트 측 용량(requiredCount) 검증 없음 (기존 DayApplicantsDialog 동일)
//   - V1: 전체 fetch (페이지네이션 미구현)

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../models/core/application_model.dart';
import '../../models/core/business_model.dart';
import '../../models/core/user_model.dart';
import '../../services/firestore_service.dart';
import '../../services/support_review_queue_service.dart';
import '../../theme/app_colors.dart';
import '../../utils/dialog_helper.dart';
import '../../utils/loading_state_mixin.dart';
import '../../utils/responsive_helper.dart';
import '../../utils/toast_helper.dart';

// ─── 우선순위 분류 ────────────────────────────────────────────────────────────

enum _Priority { overdue, today, upcoming }

extension _PriorityLabel on _Priority {
  String get label {
    switch (this) {
      case _Priority.overdue:  return '기한 지남';
      case _Priority.today:    return '오늘';
      case _Priority.upcoming: return '예정';
    }
  }

  Color get color {
    switch (this) {
      case _Priority.overdue:  return AppColors.error;
      case _Priority.today:    return AppColors.brand;
      case _Priority.upcoming: return AppColors.textSecondary;
    }
  }

  Color get bgColor {
    switch (this) {
      case _Priority.overdue:  return AppColors.errorBg;
      case _Priority.today:    return AppColors.infoBg;
      case _Priority.upcoming: return AppColors.grey100;
    }
  }
}

// ─── 필터 ─────────────────────────────────────────────────────────────────────

enum _Filter { all, overdue, today, upcoming }

extension _FilterLabel on _Filter {
  String get label {
    switch (this) {
      case _Filter.all:      return '전체';
      case _Filter.overdue:  return '기한 지남';
      case _Filter.today:    return '오늘';
      case _Filter.upcoming: return '예정';
    }
  }
}

// ─── 내부 데이터 구조 ────────────────────────────────────────────────────────

class _QueueItem {
  final ApplicationModel app;
  final UserModel? user;
  final BusinessModel? business;  // null: businesses 목록에 없는 사업장
  final _Priority priority;

  const _QueueItem({
    required this.app,
    required this.user,
    required this.business,
    required this.priority,
  });
}

class _DateGroup {
  final String dateKey;    // 'yyyy-MM-dd'
  final DateTime date;
  final _Priority priority;
  final List<_QueueItem> items;
  bool expanded;

  _DateGroup({
    required this.dateKey,
    required this.date,
    required this.priority,
    required this.items,
    this.expanded = false,
  });

  int get count => items.length;
  Set<String> get businessIds =>
      items.map((i) => i.business?.id ?? i.app.businessId).toSet();
}

// ─── 화면 진입 ListView item 타입 (단순 sealed class 역할) ───────────────────

abstract class _ListItem {}

class _PrioritySectionHeader extends _ListItem {
  final _Priority priority;
  final int count;
  _PrioritySectionHeader(this.priority, this.count);
}

class _DateGroupHeader extends _ListItem {
  final _DateGroup group;
  _DateGroupHeader(this.group);
}

class _AppRow extends _ListItem {
  final _QueueItem item;
  _AppRow(this.item);
}

// ─── 포맷 헬퍼 ───────────────────────────────────────────────────────────────

final _dateHeaderFmt = DateFormat('M월 d일 EEEE', 'ko_KR');
final _dateLabelFmt  = DateFormat('M/d(E)', 'ko_KR');

String _fmtWorkTime(ApplicationModel app) {
  final start = app.startTime;
  final end   = app.endTime;
  if (start.isEmpty || end.isEmpty) return '';
  return '$start–$end';
}

// ─── 화면 ─────────────────────────────────────────────────────────────────────

class SupportReviewQueueScreen extends StatefulWidget {
  const SupportReviewQueueScreen({
    super.key,
    required this.businessIds,
    required this.businesses,
  });

  final List<String> businessIds;
  final List<BusinessModel> businesses;

  static Route<bool> route({
    required List<String> businessIds,
    required List<BusinessModel> businesses,
  }) =>
      MaterialPageRoute<bool>(
        builder: (_) => SupportReviewQueueScreen(
          businessIds: businessIds,
          businesses: businesses,
        ),
      );

  @override
  State<SupportReviewQueueScreen> createState() =>
      _SupportReviewQueueScreenState();
}

class _SupportReviewQueueScreenState extends State<SupportReviewQueueScreen>
    with LoadingStateMixin {
  final _queueSvc  = SupportReviewQueueService.instance;
  final _svc       = FirestoreService();

  List<ApplicationModel> _apps  = [];
  Map<String, UserModel> _users = {};
  _Filter _filter               = _Filter.all;
  bool _hasChanges              = false;
  bool _isActing                = false;  // 승인/거절 중 중복 방지
  // [CR-01 FIX] ERROR != EMPTY 분리 — CF callable 실패 시 에러 상태
  bool _hasLoadError            = false;

  // 날짜 그룹 확장 상태
  final Set<String> _expandedKeys = {};

  // ─── 로드 ──────────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    // [CR-01 FIX] 로드 시작 시 에러 플래그 초기화 (동기 컨텍스트 — mounted 보장)
    setState(() => _hasLoadError = false);
    await runWithLoading(() async {
      try {
        final apps = await _queueSvc.loadPendingApplications(widget.businessIds);
        final users = apps.isNotEmpty && widget.businessIds.isNotEmpty
            ? await _queueSvc.loadUsers(apps, widget.businessIds.first)
            : <String, UserModel>{};

        if (!mounted) return;
        setState(() {
          _apps        = apps;
          _users       = users;
          _hasLoadError = false;
          _expandedKeys.clear();
        });
      } catch (e) {
        debugPrint('[SupportReviewQueue] 로드 실패: $e');
        if (!mounted) return;
        // stale 이전 데이터를 ERROR 뒤에 정상 데이터처럼 노출하지 않도록 클리어
        setState(() {
          _hasLoadError = true;
          _apps         = [];
          _users        = {};
        });
      }
    });
  }

  // ─── 우선순위 분류 ─────────────────────────────────────────────────────────

  _Priority _priorityOf(ApplicationModel app) {
    final now      = DateTime.now();
    final today    = DateTime(now.year, now.month, now.day);
    final appDate  = app.workDate;
    final dateOnly = DateTime(appDate.year, appDate.month, appDate.day);

    if (dateOnly.isBefore(today))              return _Priority.overdue;
    if (dateOnly.isAtSameMomentAs(today))      return _Priority.today;
    return _Priority.upcoming;
  }

  // ─── 그룹 계산 ─────────────────────────────────────────────────────────────

  List<_DateGroup> _buildGroups() {
    // 1. 필터 적용
    final filtered = _apps.where((app) {
      final p = _priorityOf(app);
      switch (_filter) {
        case _Filter.all:      return true;
        case _Filter.overdue:  return p == _Priority.overdue;
        case _Filter.today:    return p == _Priority.today;
        case _Filter.upcoming: return p == _Priority.upcoming;
      }
    }).toList();

    // 2. QueueItem 변환
    final items = filtered.map((app) {
      BusinessModel? biz;
      try { biz = widget.businesses.firstWhere((b) => b.id == app.businessId); } catch (_) {}
      return _QueueItem(
        app:      app,
        user:     _users[app.uid],
        business: biz,
        priority: _priorityOf(app),
      );
    }).toList();

    // 3. 날짜별 그룹화
    final groupMap = <String, List<_QueueItem>>{};
    for (final item in items) {
      final key = DateFormat('yyyy-MM-dd').format(item.app.workDate);
      groupMap.putIfAbsent(key, () => []).add(item);
    }

    return groupMap.entries.map((e) {
      final dateKey = e.key;
      final groupItems = e.value;
      return _DateGroup(
        dateKey:  dateKey,
        date:     groupItems.first.app.workDate,
        priority: groupItems.first.priority,
        items:    groupItems,
        expanded: _expandedKeys.contains(dateKey),
      );
    }).toList()
      ..sort((a, b) => a.date.compareTo(b.date));
  }

  // ─── 통계 계산 ──────────────────────────────────────────────────────────────

  int get _totalCount    => _apps.length;
  int get _overdueCount  => _apps.where((a) => _priorityOf(a) == _Priority.overdue).length;
  int get _todayCount    => _apps.where((a) => _priorityOf(a) == _Priority.today).length;

  // ─── 플랫 ListView 아이템 목록 ──────────────────────────────────────────────

  List<_ListItem> _buildListItems(List<_DateGroup> groups) {
    final items = <_ListItem>[];
    _Priority? lastPriority;

    for (final group in groups) {
      // priority 구분선 헤더
      if (group.priority != lastPriority && _filter == _Filter.all) {
        final priorityCount = groups
            .where((g) => g.priority == group.priority)
            .fold(0, (sum, g) => sum + g.count);
        items.add(_PrioritySectionHeader(group.priority, priorityCount));
        lastPriority = group.priority;
      }

      // 날짜 그룹 헤더
      items.add(_DateGroupHeader(group));

      // 확장 시 앱 행
      if (group.expanded) {
        for (final item in group.items) {
          items.add(_AppRow(item));
        }
      }
    }

    return items;
  }

  // ─── 액션 ──────────────────────────────────────────────────────────────────

  Future<void> _approveApp(ApplicationModel app, String? userName) async {
    // [APPROVE-AUTH-01 C2] 클라이언트 selected-A canManageTo 게이트 제거.
    // 서버(callableApproveApplicationForReview)가 target business 권한을 재검증한다.
    if (_isActing) return;

    final adminUID = FirebaseAuth.instance.currentUser?.uid;
    if (adminUID == null) return;

    final displayName = userName ?? '이 지원자';
    final confirmed = await DialogHelper.showCustom<bool>(
      context,
      title: '승인 확인',
      content: Text(
        '$displayName${_getJobContext(app)} 지원을 승인하시겠습니까?\n계약서 발송 대기 상태로 전환됩니다.',
        style: ResponsiveHelper.bodyStyle(context),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('취소'),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: AppColors.brand),
          onPressed: () => Navigator.pop(context, true),
          child: const Text('승인', style: TextStyle(color: Colors.white)),
        ),
      ],
    );
    if (confirmed != true) return;
    if (!mounted) return;

    setState(() => _isActing = true);
    try {
      await _svc.updateApplicationStatus(
        applicationId: app.id,
        status: AppStatus.contractPending,
        confirmedBy: adminUID,
      );
      if (!mounted) return;
      setState(() {
        _apps.removeWhere((a) => a.id == app.id);
        _hasChanges = true;
        _isActing = false;
      });
      ToastHelper.showSuccess('승인 완료 — 계약서 발송 대기 상태로 전환되었습니다.');
    } catch (e) {
      if (!mounted) return;
      setState(() => _isActing = false);
      ToastHelper.showError('승인 중 오류가 발생했습니다. 다시 시도해주세요.');
    }
  }

  Future<void> _rejectApp(ApplicationModel app, String? userName) async {
    // [APPROVE-AUTH-01 C2] 클라이언트 selected-A canManageTo 게이트 제거.
    // 서버(callableRejectApplication)가 target business 권한을 재검증한다.
    if (_isActing) return;

    final adminUID = FirebaseAuth.instance.currentUser?.uid;
    if (adminUID == null) return;

    final reason = await DialogHelper.showRejectReasonPicker(
      context,
      title: '거절 사유',
      targetName: userName,
    );
    if (reason == null) return;
    if (!mounted) return;

    setState(() => _isActing = true);
    try {
      await _svc.updateApplicationStatus(
        applicationId: app.id,
        status: AppStatus.rejected,
        rejectedBy: adminUID,
        message: reason,
      );
      if (!mounted) return;
      setState(() {
        _apps.removeWhere((a) => a.id == app.id);
        _hasChanges = true;
        _isActing = false;
      });
      ToastHelper.showSuccess('거절 처리 완료');
    } catch (e) {
      if (!mounted) return;
      setState(() => _isActing = false);
      ToastHelper.showError('거절 중 오류가 발생했습니다. 다시 시도해주세요.');
    }
  }

  String _getJobContext(ApplicationModel app) {
    final type = app.isLongTermApplication ? ' (장기)' : '';
    final wt   = app.selectedWorkType.isNotEmpty ? ' · ${app.selectedWorkType}' : '';
    return '$wt$type';
  }

  // ─── 날짜 그룹 토글 ────────────────────────────────────────────────────────

  void _toggleDateGroup(String key) {
    setState(() {
      if (_expandedKeys.contains(key)) {
        _expandedKeys.remove(key);
      } else {
        _expandedKeys.add(key);
      }
    });
  }

  // ─── 빌드 ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.pop(context, _hasChanges);
      },
      child: Scaffold(
        backgroundColor: AppColors.surface,
        appBar: AppBar(
          backgroundColor: AppColors.surface,
          foregroundColor: AppColors.brand,
          elevation: 0,
          scrolledUnderElevation: 1,
          surfaceTintColor: Colors.transparent,
          title: Text(
            '지원 검토',
            style: ResponsiveHelper.titleStyle(context, color: AppColors.textPrimary),
          ),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new, size: 20),
            onPressed: () => Navigator.pop(context, _hasChanges),
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh, size: 22),
              onPressed: isLoading ? null : _load,
              tooltip: '새로고침',
            ),
          ],
        ),
        body: isLoading
            ? const Center(child: CircularProgressIndicator())
            : _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    // [CR-01 FIX] ERROR state: 빈 화면 대신 명확한 에러 UI
    if (_hasLoadError) return _buildErrorState();

    final groups   = _buildGroups();
    final listItems = _buildListItems(groups);

    return Column(
      children: [
        // ── 상단 통계 요약 ────────────────────────────────────────────────
        _buildTopStats(),
        // ── 필터 칩 ────────────────────────────────────────────────────────
        _buildFilterChips(),
        const Divider(height: 1, thickness: 1, color: AppColors.borderLight),
        // ── 리스트 ──────────────────────────────────────────────────────────
        Expanded(
          child: _apps.isEmpty
              ? _buildEmptyState()
              : groups.isEmpty
                  ? _buildEmptyStateFiltered()
                  : ListView.builder(
                      itemCount: listItems.length,
                      itemBuilder: (ctx, i) => _buildListItem(listItems[i]),
                    ),
        ),
      ],
    );
  }

  // ─── 상단 통계 ─────────────────────────────────────────────────────────────

  Widget _buildTopStats() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      '전체 $_totalCount건',
                      style: ResponsiveHelper.bodyStyle(
                        context,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ).copyWith(fontSize: 17),
                    ),
                    if (widget.businesses.length > 1) ...[
                      const SizedBox(width: 8),
                      Text(
                        '${widget.businesses.length}개 사업장',
                        style: ResponsiveHelper.bodyStyle(
                          context,
                          color: AppColors.textTertiary,
                        ).copyWith(fontSize: 13),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          if (_overdueCount > 0)
            _StatBadge(label: '기한지남', count: _overdueCount, color: AppColors.error),
          if (_overdueCount > 0 && _todayCount > 0) const SizedBox(width: 6),
          if (_todayCount > 0)
            _StatBadge(label: '오늘', count: _todayCount, color: AppColors.brand),
        ],
      ),
    );
  }

  // ─── 필터 칩 ───────────────────────────────────────────────────────────────

  Widget _buildFilterChips() {
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        children: _Filter.values.map((f) {
          final selected = _filter == f;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilterChip(
              label: Text(
                f.label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  color: selected ? AppColors.brand : AppColors.textSecondary,
                ),
              ),
              selected: selected,
              onSelected: (_) => setState(() {
                _filter = f;
                _expandedKeys.clear();
              }),
              backgroundColor: AppColors.grey100,
              selectedColor: AppColors.infoBg,
              checkmarkColor: AppColors.brand,
              side: selected
                  ? const BorderSide(color: AppColors.brand, width: 1.2)
                  : const BorderSide(color: AppColors.border),
              padding: const EdgeInsets.symmetric(horizontal: 4),
              visualDensity: VisualDensity.compact,
            ),
          );
        }).toList(),
      ),
    );
  }

  // ─── ListView 아이템 렌더 ──────────────────────────────────────────────────

  Widget _buildListItem(_ListItem item) {
    if (item is _PrioritySectionHeader)  return _buildPrioritySectionHeader(item);
    if (item is _DateGroupHeader)         return _buildDateGroupHeader(item.group);
    if (item is _AppRow)                  return _buildAppRow(item.item);
    return const SizedBox.shrink();
  }

  // ─── 우선순위 섹션 헤더 ────────────────────────────────────────────────────

  Widget _buildPrioritySectionHeader(_PrioritySectionHeader header) {
    return Container(
      color: header.priority.bgColor,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 14,
            decoration: BoxDecoration(
              color: header.priority.color,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            header.priority.label,
            style: ResponsiveHelper.bodyStyle(
              context,
              fontWeight: FontWeight.w600,
              color: header.priority.color,
            ).copyWith(fontSize: 13),
          ),
          const SizedBox(width: 4),
          Text(
            '${header.count}건',
            style: ResponsiveHelper.bodyStyle(
              context,
              color: header.priority.color,
            ).copyWith(fontSize: 13),
          ),
        ],
      ),
    );
  }

  // ─── 날짜 그룹 헤더 ────────────────────────────────────────────────────────

  Widget _buildDateGroupHeader(_DateGroup group) {
    final dateLabel     = _dateHeaderFmt.format(group.date);
    final bizCount      = group.businessIds.length;
    final isExpanded    = _expandedKeys.contains(group.dateKey);

    return InkWell(
      onTap: () => _toggleDateGroup(group.dateKey),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          border: Border(
            bottom: BorderSide(
              color: isExpanded ? AppColors.brand.withValues(alpha: 0.12) : AppColors.borderLight,
              width: 1,
            ),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    dateLabel,
                    style: ResponsiveHelper.bodyStyle(
                      context,
                      fontWeight: FontWeight.w600,
                      color: isExpanded ? AppColors.brand : AppColors.textPrimary,
                    ).copyWith(fontSize: 14),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${group.count}건 · $bizCount개 사업장',
                    style: ResponsiveHelper.bodyStyle(
                      context,
                      color: AppColors.textTertiary,
                    ).copyWith(fontSize: 12),
                  ),
                ],
              ),
            ),
            Icon(
              isExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
              size: 20,
              color: isExpanded ? AppColors.brand : AppColors.textTertiary,
            ),
          ],
        ),
      ),
    );
  }

  // ─── 지원자 행 ─────────────────────────────────────────────────────────────

  Widget _buildAppRow(_QueueItem item) {
    final app      = item.app;
    final user     = item.user;
    final biz      = item.business;
    final userName = user?.displayName ?? user?.name ?? '지원자';
    final workTime = _fmtWorkTime(app);
    final isLong   = app.isLongTermApplication;

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(
          bottom: BorderSide(color: AppColors.borderLight, width: 1),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 10, 12, 10),
        child: Row(
          children: [
            // ─ 정보 영역 ──────────────────────────────────────────────────
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          userName,
                          style: ResponsiveHelper.bodyStyle(
                            context,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary,
                          ).copyWith(fontSize: 14),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (isLong) ...[
                        const SizedBox(width: 6),
                        _TypeBadge('장기', AppColors.infoMedium),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _buildContextLine(app, biz, workTime),
                    style: ResponsiveHelper.bodyStyle(
                      context,
                      color: AppColors.textSecondary,
                    ).copyWith(fontSize: 12),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                  if (isLong && app.workEndDate != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      '${_dateLabelFmt.format(app.workDate)} ~ ${_dateLabelFmt.format(app.workEndDate!)}',
                      style: ResponsiveHelper.bodyStyle(
                        context,
                        color: AppColors.textTertiary,
                      ).copyWith(fontSize: 11),
                    ),
                  ],
                ],
              ),
            ),
            // ─ 액션 버튼 ──────────────────────────────────────────────────
            const SizedBox(width: 8),
            _ActionButtons(
              onReject: _isActing ? null : () => _rejectApp(app, user?.displayName ?? user?.name),
              onApprove: _isActing ? null : () => _approveApp(app, user?.displayName ?? user?.name),
            ),
          ],
        ),
      ),
    );
  }

  String _buildContextLine(ApplicationModel app, BusinessModel? biz, String time) {
    final parts = <String>[];
    if (biz != null && biz.name.isNotEmpty) parts.add(biz.name);
    if (app.selectedWorkType.isNotEmpty) parts.add(app.selectedWorkType);
    if (time.isNotEmpty) parts.add(time);
    return parts.join(' · ');
  }

  // ─── Empty / Error 상태 ─────────────────────────────────────────────────────

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.check_circle_outline, size: 56, color: AppColors.textHint),
          const SizedBox(height: 12),
          Text(
            '검토할 지원이 없어요',
            style: ResponsiveHelper.bodyStyle(
              context,
              color: AppColors.textTertiary,
              fontWeight: FontWeight.w500,
            ).copyWith(fontSize: 15),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyStateFiltered() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.filter_list_off, size: 48, color: AppColors.textHint),
          const SizedBox(height: 12),
          Text(
            '해당 조건의 지원이 없어요',
            style: ResponsiveHelper.bodyStyle(
              context,
              color: AppColors.textTertiary,
            ).copyWith(fontSize: 15),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => setState(() => _filter = _Filter.all),
            child: const Text('전체 보기'),
          ),
        ],
      ),
    );
  }

  // [CR-01 FIX] ERROR state — permission-denied/network 등 실패 시 표시
  Widget _buildErrorState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, size: 56, color: AppColors.errorLight),
          const SizedBox(height: 12),
          Text(
            '지원 내역을 불러오지 못했어요',
            style: ResponsiveHelper.bodyStyle(
              context,
              fontWeight: FontWeight.w500,
              color: AppColors.textPrimary,
            ).copyWith(fontSize: 15),
          ),
          const SizedBox(height: 4),
          Text(
            '잠시 후 다시 시도해 주세요.',
            style: ResponsiveHelper.bodyStyle(
              context,
              color: AppColors.textTertiary,
            ).copyWith(fontSize: 13),
          ),
          const SizedBox(height: 16),
          TextButton(
            onPressed: _load,
            child: const Text('다시 시도'),
          ),
        ],
      ),
    );
  }
}

// ─── 서브 위젯 ─────────────────────────────────────────────────────────────────

class _StatBadge extends StatelessWidget {
  const _StatBadge({
    required this.label,
    required this.count,
    required this.color,
  });

  final String label;
  final int count;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        '$label $count',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}

class _TypeBadge extends StatelessWidget {
  const _TypeBadge(this.label, this.color);

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}

class _ActionButtons extends StatelessWidget {
  const _ActionButtons({
    required this.onReject,
    required this.onApprove,
  });

  final VoidCallback? onReject;
  final VoidCallback? onApprove;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 거절
        OutlinedButton(
          onPressed: onReject,
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.error,
            side: const BorderSide(color: AppColors.errorLight, width: 1),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            minimumSize: const Size(0, 32),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
            textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
          ),
          child: const Text('거절'),
        ),
        const SizedBox(width: 6),
        // 승인
        ElevatedButton(
          onPressed: onApprove,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.brand,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            minimumSize: const Size(0, 32),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
            elevation: 0,
            textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
          child: const Text('승인'),
        ),
      ],
    );
  }
}
