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

import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/core/application_model.dart';
import '../../providers/user_provider.dart';
import '../../models/core/business_model.dart';
import '../../models/core/user_model.dart';
import '../../services/firestore_service.dart';
import '../../services/support_review_queue_service.dart';
import '../../theme/app_colors.dart';
import '../../utils/dialog_helper.dart';
import '../../utils/format_helper.dart';
import '../../utils/loading_state_mixin.dart';
import '../../utils/navigation_helper.dart';
import '../../utils/responsive_helper.dart';
import '../../utils/toast_helper.dart';
import '../../widgets/common/app_empty_state.dart';
import '../../widgets/common/app_page_scaffold.dart';
import '../../widgets/common/loading_widget.dart';
import '../../widgets/common/notification_badge.dart';
import '../../widgets/dialogs/worker_detail_dialog.dart';
import '../common/notification_screen.dart';

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

enum SupportReviewFilter { all, overdue, today, upcoming }

extension SupportReviewFilterLabel on SupportReviewFilter {
  String get label {
    switch (this) {
      case SupportReviewFilter.all:      return '전체';
      case SupportReviewFilter.overdue:  return '기한 지남';
      case SupportReviewFilter.today:    return '오늘';
      case SupportReviewFilter.upcoming: return '예정';
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

// [R1.2] workDate는 '사업장이 운영되는 날짜'(Asia/Seoul calendar date)다.
//   Firestore Timestamp를 parseTimestamp가 .toLocal()로 풀기 때문에 DateTime의
//   year/month/day는 기기 timezone을 따른다. intl DateFormat은 그 local 값을
//   그대로 찍으므로 UTC 기기에서 KST 자정(= 전날 15:00 UTC)이 하루 전으로 보인다.
//   날짜 표기·그룹 키는 전부 FormatHelper의 KST 변환을 거친다.

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
    this.initialFilter = SupportReviewFilter.all,
  });

  final List<String> businessIds;
  final List<BusinessModel> businesses;

  /// [AH-V2-04C] 진입 시 선택될 필터.
  ///
  /// Home이 '긴급 N건'을 강조해 보여준 뒤 들어오면 그 집합으로 바로 착지한다.
  /// 생략하면 기존대로 전체. 다른 진입 경로의 동작은 바뀌지 않는다.
  final SupportReviewFilter initialFilter;

  static Route<bool> route({
    required List<String> businessIds,
    required List<BusinessModel> businesses,
    SupportReviewFilter initialFilter = SupportReviewFilter.all,
  }) =>
      MaterialPageRoute<bool>(
        builder: (_) => SupportReviewQueueScreen(
          businessIds: businessIds,
          businesses: businesses,
          initialFilter: initialFilter,
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
  // [R1.2] null = 지원자 정보 조회 실패(UNKNOWN). 빈 Map = 조회 성공·대상 없음.
  //   둘을 합치면 '누구인지 모른다'가 '이력이 없다'로 둔갑한다.
  Map<String, UserModel>? _users = const {};
  late SupportReviewFilter _filter;
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
    // [AH-V2-04C] 호출부가 지정한 필터로 시작. 로드 후 자동 전환은 하지 않는다 —
    //   '기한 지남'으로 들어왔는데 그 사이 다 처리됐다면 해당 필터의 빈 상태를
    //   보여주는 것이 맞다. 몰래 전체로 되돌리면 무엇을 보고 있는지 알 수 없다.
    _filter = widget.initialFilter;
    _load();
  }

  Future<void> _load() async {
    // [CR-01 FIX] 로드 시작 시 에러 플래그 초기화 (동기 컨텍스트 — mounted 보장)
    setState(() => _hasLoadError = false);
    // [CROSS-DOMAIN-R5.1F.2] 이 화면은 배정 사업장 전체를 한 번에 보여주므로
    //   사업장마다 listener를 달지 않는다. 대신 목록을 다시 읽는 이 길목에서
    //   권한도 같은 주기로 다시 읽는다(in-flight는 하나로 합쳐진다).
    //   폴링이 아니라 사용자가 만든 결정적 refresh다.
    unawaited(context.read<UserProvider>().refreshSubAdminAccessState());
    await runWithLoading(() async {
      try {
        final apps = await _queueSvc.loadPendingApplications(widget.businessIds);
        final users = apps.isNotEmpty && widget.businessIds.isNotEmpty
            ? await _queueSvc.loadUsers(apps, widget.businessIds.first)
            : const <String, UserModel>{};

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
          _users        = const {};
        });
      }
    });
  }

  // ─── 우선순위 분류 ─────────────────────────────────────────────────────────

  /// [AH-V2-04C.1] KST 날짜 경계로 분류 — 서버 Home 요약과 같은 기준.
  ///
  /// 기기 local 자정을 쓰면 KST가 아닌 기기에서 서버와 하루가 어긋나
  /// Home '긴급 N건'과 이 화면의 '기한 지남' 개수가 달라진다.
  /// FormatHelper.toKstDate는 device timezone 무관한 KST 날짜 비교 키다.
  ///
  /// overdue / today / upcoming은 이 한 classifier를 공유하므로
  /// 셋의 날짜 경계가 서로 모순되지 않는다.
  _Priority _priorityOf(ApplicationModel app) {
    final today    = FormatHelper.toKstDate(DateTime.now());
    final dateOnly = FormatHelper.toKstDate(app.workDate);

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
        case SupportReviewFilter.all:      return true;
        case SupportReviewFilter.overdue:  return p == _Priority.overdue;
        case SupportReviewFilter.today:    return p == _Priority.today;
        case SupportReviewFilter.upcoming: return p == _Priority.upcoming;
      }
    }).toList();

    // 2. QueueItem 변환
    final items = filtered.map((app) {
      BusinessModel? biz;
      try { biz = widget.businesses.firstWhere((b) => b.id == app.businessId); } catch (_) {}
      return _QueueItem(
        app:      app,
        user:     _users?[app.uid],
        business: biz,
        priority: _priorityOf(app),
      );
    }).toList();

    // 3. 날짜별 그룹화
    final groupMap = <String, List<_QueueItem>>{};
    for (final item in items) {
      // [R1.2] KST calendar date 키 — _priorityOf(toKstDate)와 같은 경계를 쓴다.
      final key = FormatHelper.formatDateISO(item.app.workDate);
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
      if (group.priority != lastPriority && _filter == SupportReviewFilter.all) {
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

  /// [CROSS-DOMAIN-R5.1F.2] 이 큐는 여러 사업장의 지원서를 한 화면에 모은다.
  ///
  /// [APPROVE-AUTH-01 C2]는 selected-A 기준 `can()` 게이트가 B 행을 잘못
  /// 막는다는 이유로 클라이언트 게이트를 **없앴다**. 그러면 권한 없는 사업장의
  /// 승인/거절 CTA가 그대로 남고, 누르면 서버 403으로만 끝난다.
  /// 답은 "게이트 없음"이 아니라 **행의 사업장 기준 게이트**다 — 서버가 보는
  /// 단위(`callableApproveApplicationForReview`의 target business)와 같다.
  ///
  /// 하이드레이션 전(UNKNOWN)에는 fail-closed로 두고, `_load()`가 부르는
  /// access refresh가 채우면 다시 그려진다 — 폴링이 아니라 결정적 refresh다.
  bool _canActOn(ApplicationModel app) =>
      context.read<UserProvider>().canForBusiness(
            app.businessId,
            (p) => p.canManageTo,
          );

  Future<void> _approveApp(ApplicationModel app, String? userName) async {
    // [CROSS-DOMAIN-R5.1F.2] 서버와 같은 단위로 먼저 막는다.
    if (!_canActOn(app)) {
      ToastHelper.showWarning('이 사업장의 공고 관리 권한이 없습니다.');
      return;
    }
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
    // [CROSS-DOMAIN-R5.1F.2] 승인과 같은 권한·같은 단위다.
    if (!_canActOn(app)) {
      ToastHelper.showWarning('이 사업장의 공고 관리 권한이 없습니다.');
      return;
    }
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
    // [CROSS-DOMAIN-R5.1F.2] 행마다 사업장이 다르므로 판정은 _canActOn이 하고,
    //   여기서는 권한이 바뀌면 다시 그려지도록 구독만 건다.
    context.watch<UserProvider>();
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.pop(context, _hasChanges);
      },
      child: AppPageScaffold(
        title: '지원 검토',
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, size: 22),
            color: AppColors.textSecondary,
            onPressed: isLoading ? null : _load,
            tooltip: '새로고침',
          ),
          IconButton(
            icon: const Icon(Icons.home_outlined),
            color: AppColors.textSecondary,
            onPressed: () => NavigationHelper.goHome(context),
            tooltip: '홈',
          ),
          NotificationBadge(
            child: IconButton(
              icon: const Icon(Icons.notifications_outlined),
              color: AppColors.textSecondary,
              onPressed: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const NotificationScreen())),
              tooltip: '알림',
            ),
          ),
        ],
        body: isLoading
            ? const LoadingWidget()
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
                      // AppPageScaffold는 body에 하단 SafeArea를 적용하지 않는다.
                      // gesture navigation 기기에서 마지막 row가 시스템 바에 가리지 않도록 보정.
                      padding: EdgeInsets.only(
                        bottom: MediaQuery.paddingOf(context).bottom,
                      ),
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
        children: SupportReviewFilter.values.map((f) {
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
    final dateLabel     = FormatHelper.formatDateKorean(group.date);
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
    // [R1.2] 상세는 지원자 문서를 읽은 경우에만 연다. 조회 실패 상태에서
    //   빈 프로필을 여는 것은 '이력 없음'을 보여주는 것과 같다.
    final canOpenDetail = user != null;

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
              child: InkWell(
                onTap: canOpenDetail ? () => _openApplicantDetail(item) : null,
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
                        if (canOpenDetail) ...[
                          const SizedBox(width: 2),
                          const Icon(Icons.chevron_right,
                              size: 16, color: AppColors.textTertiary),
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
                        '${FormatHelper.formatDateCompact(app.workDate)} ~ ${FormatHelper.formatDateCompact(app.workEndDate!)}',
                        style: ResponsiveHelper.bodyStyle(
                          context,
                          color: AppColors.textTertiary,
                        ).copyWith(fontSize: 12),
                      ),
                    ],
                    // [R1.2] 판단 근거 요약 — 이미 로드한 UserModel만 쓴다(추가 read 0).
                    _buildApplicantSummary(user),
                  ],
                ),
              ),
            ),
            // ─ 액션 버튼 ──────────────────────────────────────────────────
            const SizedBox(width: 8),
            // [CROSS-DOMAIN-R5.1F.2] 이 행의 사업장에 권한이 없으면 CTA 대신
            //   이유를 보여준다 — 누를 수 없는 버튼을 남기지 않는다.
            if (!_canActOn(app))
              Text(
                '권한 없음',
                style: ResponsiveHelper.bodyStyle(
                  context,
                  color: AppColors.textTertiary,
                ).copyWith(fontSize: 12),
              )
            else
              _ActionButtons(
                onReject: _isActing ? null : () => _rejectApp(app, user?.displayName ?? user?.name),
                onApprove: _isActing ? null : () => _approveApp(app, user?.displayName ?? user?.name),
              ),
          ],
        ),
      ),
    );
  }

  /// [R1.2] 지원자 판단 요약 한 줄.
  ///
  /// 규칙: **확인된 사실만 쓴다.**
  ///   - 조회 실패(user == null) → '0건'이 아니라 조회 실패라고 말한다.
  ///   - 노쇼·지각은 0일 때 행을 만들지 않는다. UserModel의 0은 '사건이 없다'와
  ///     '필드가 아직 채워지지 않았다'를 구분하지 못하므로 `노쇼 0회`는 거짓 단언이다.
  ///     양수만 표시하면 어느 쪽이든 거짓말이 되지 않는다.
  Widget _buildApplicantSummary(UserModel? user) {
    if (user == null) {
      return Padding(
        padding: const EdgeInsets.only(top: 3),
        child: Text(
          '지원자 정보를 불러오지 못했어요',
          style: ResponsiveHelper.bodyStyle(
            context,
            color: AppColors.errorDark,
          ).copyWith(fontSize: 12),
        ),
      );
    }

    final chips = <Widget>[];
    if (user.isBlacklisted) {
      chips.add(_SummaryChip('이용 제한', AppColors.error));
    }
    if (user.recentNoShowCount > 0) {
      chips.add(_SummaryChip('노쇼 ${user.recentNoShowCount}회', AppColors.error));
    }
    if (user.recentLateCount > 0) {
      chips.add(_SummaryChip('지각 ${user.recentLateCount}회', AppColors.warningDark));
    }
    if (user.totalWorkDays > 0) {
      chips.add(_SummaryChip('근무 ${user.totalWorkDays}일', AppColors.textSecondary));
    }
    if (user.reviewCount > 0 && user.averageRating > 0) {
      chips.add(_SummaryChip(
          '평점 ${user.averageRating.toStringAsFixed(1)}', AppColors.textSecondary));
    }
    if (chips.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Wrap(spacing: 6, runSpacing: 4, children: chips),
    );
  }

  /// [R1.2] 지원자 상세 — 기존 WorkerDetailDialog 재사용.
  ///
  /// 이번 지원 context(application·businessId)를 그대로 넘겨 목록에서 보던
  /// 근무를 상세에서도 유지한다.
  ///
  /// `showApprovalButtons: false` — 이 화면의 '승인'은 계약서 발송 대기
  /// (contractPending)로 보내지만 WorkerDetailDialog의 '승인'은 곧바로
  /// confirmed로 확정한다. 같은 화면에서 서로 다른 두 승인을 노출하지 않는다.
  /// 확정 mutation 계약은 R2에서 정리한다.
  ///
  /// `isConfirmed: false` — 계좌·통장사본·신분증·계약 섹션은 확정자 전용이라
  /// 검토 단계에서는 렌더되지 않는다.
  Future<void> _openApplicantDetail(_QueueItem item) async {
    final user = item.user;
    if (user == null) return;
    await WorkerDetailDialog.show(
      context: context,
      user: user,
      application: item.app,
      businessId: item.app.businessId,
      isConfirmed: false,
      showApprovalButtons: false,
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
    return const AppEmptyState(
      icon: Icons.check_circle_outline,
      title: '검토할 지원이 없어요',
    );
  }

  Widget _buildEmptyStateFiltered() {
    return AppEmptyState(
      icon: Icons.filter_list_off,
      title: '해당 조건의 지원이 없어요',
      action: TextButton(
        onPressed: () => setState(() => _filter = SupportReviewFilter.all),
        child: const Text('전체 보기'),
      ),
    );
  }

  // [CR-01 FIX] ERROR state — permission-denied/network 등 실패 시 표시
  Widget _buildErrorState() {
    return AppEmptyState(
      icon: Icons.error_outline,
      iconColor: AppColors.error,
      title: '지원 내역을 불러오지 못했어요',
      subtitle: '잠시 후 다시 시도해 주세요.',
      action: TextButton(
        onPressed: _load,
        child: const Text('다시 시도'),
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

/// [R1.2] 지원자 요약 칩 — 값이 있을 때만 만들어진다.
class _SummaryChip extends StatelessWidget {
  const _SummaryChip(this.label, this.color);

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.grey100,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        // 12px 하한 — 운영 정보라 더 작게 두지 않는다 (TYPO-50)
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color),
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
          fontSize: 12,
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
