// lib/screens/business_admin/unclosed_action_queue_screen.dart
// ADMIN REDESIGN — PHASE 2B
// 마감 필요 Action Queue — business×workDate 미마감 항목 전체 목록
//
// 설계 원칙:
//   - canonical unit: business × workDate
//   - close 판정: callableGetUnclosedActionQueue (= srvHomeUnclosed 동일 로직)
//   - 기존 AttendanceStatusDialog 재사용 — 새 처리 로직 생성 금지
//   - oldest first 정렬 (서버 수행)
//   - error state ≠ empty state (available:false 시 별도 표시)
//
// KNOWN LIMITATIONS:
//   - V1: 전체 fetch (페이지네이션 미구현, 서버 cap 500건)
//   - 처리 후 전체 reload (개별 row 갱신 미구현)
//   - open-ended 장기 근로자는 CF와 동일하게 미집계
//     (Home LEGACY count와 미미한 차이 가능, PHASE 3에서 해소 예정)

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../providers/user_provider.dart';
import '../../services/unclosed_action_queue_service.dart';
import '../../theme/app_colors.dart';
import '../../utils/loading_state_mixin.dart';
import '../../utils/navigation_helper.dart';
import '../../utils/responsive_helper.dart';
import '../../widgets/common/app_empty_state.dart';
import '../../widgets/common/app_page_scaffold.dart';
import '../../widgets/common/loading_widget.dart';
import '../../widgets/common/notification_badge.dart';
import '../common/notification_screen.dart';
import 'dialogs/attendance_status_dialog.dart';

// ─── 날짜 포맷 ────────────────────────────────────────────────────────────────

final _dateFmt = DateFormat('M월 d일 EEEE', 'ko_KR');

int _daysAgo(DateTime workDate) {
  final now = DateTime.now();
  final todayMidnight = DateTime(now.year, now.month, now.day);
  final dateMidnight  = DateTime(workDate.year, workDate.month, workDate.day);
  return todayMidnight.difference(dateMidnight).inDays;
}

String _urgencyLabel(int daysAgo) {
  if (daysAgo <= 1) return '어제';
  return 'D+$daysAgo';
}

// ─── 화면 ─────────────────────────────────────────────────────────────────────

class UnclosedActionQueueScreen extends StatefulWidget {
  const UnclosedActionQueueScreen({super.key});

  static Route<bool> route() => MaterialPageRoute<bool>(
        builder: (_) => const UnclosedActionQueueScreen(),
      );

  @override
  State<UnclosedActionQueueScreen> createState() =>
      _UnclosedActionQueueScreenState();
}

class _UnclosedActionQueueScreenState
    extends State<UnclosedActionQueueScreen>
    with LoadingStateMixin {
  final _svc = UnclosedActionQueueService.instance;

  List<UnclosedQueueItem> _items    = [];
  bool _isAvailable                 = true;
  bool _hasChanges                  = false;

  // [CROSS-DOMAIN-R5.1F.1] 진입 시점 한 번이 아니라, 머무는 동안에도 본다.
  UserProvider? _userProvider;
  bool _accessRevoked               = false;
  // [CROSS-DOMAIN-R5.1F.5] 확인하지 못한 상태 — 거부와 다른 말이다.
  bool _accessUnverified            = false;

  // ─── 로드 ──────────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // [AUDIT.2-M003] screen-level guard — canManageWage 없는 직접 진입 방어
      final up = context.read<UserProvider>();
      // [CROSS-DOMAIN-R5.1F.5] 확인된 거부일 때만 되돌린다. 확인하지 못한
      //   상태에서 pop하면 ERROR를 DENIED로 말하는 것이다 — 화면은 열어 두고
      //   아래 listener가 "확인하지 못했습니다"로 표시한다.
      final entry = up.checkCurrentBusiness((p) => p.canManageWage);
      if (entry == PermissionCheck.denied) {
        Navigator.of(context).pop();
        return;
      }
      _accessUnverified = entry != PermissionCheck.allowed;
      // [CROSS-DOMAIN-R5.1F.1] 진입 후 회수/부여도 화면에 닿아야 한다.
      _userProvider = up;
      up.addListener(_onPermissionChanged);
      // 확인되지 않은 상태에서는 조회하지 않는다 — 권한이 확인되면
      // listener가 그때 _load()를 부른다.
      if (!_accessUnverified) _load();
    });
  }

  /// [CROSS-DOMAIN-R5.1F.1] entry guard와 같은 predicate로 회수·부여를 본다.
  void _onPermissionChanged() {
    if (!mounted) return;
    final up = _userProvider;
    if (up == null) return;
    // [CROSS-DOMAIN-R5.1F.5] 네 상태로 본다.
    //   unknown(하이드레이션 전)과 error(전송 실패)는 거부가 아니므로
    //   잠금 화면으로 바꾸지 않는다 — 대신 확인 실패라고 말한다.
    final check = up.checkCurrentBusiness((p) => p.canManageWage);
    final unverified = check == PermissionCheck.error ||
        check == PermissionCheck.unknown;
    final wasUnverified = _accessUnverified;
    if (wasUnverified != unverified) {
      setState(() => _accessUnverified = unverified);
    }
    if (unverified) return;

    final allowed = check == PermissionCheck.allowed;
    if (allowed == _accessRevoked) {
      setState(() => _accessRevoked = !allowed);
      if (allowed) _load();
      return;
    }
    // 상태 bool은 그대로지만, 확인하지 못한 상태에서 막 벗어났다면
    // 그동안 하지 못한 조회를 지금 한다.
    if (wasUnverified && allowed) _load();
  }

  @override
  void dispose() {
    _userProvider?.removeListener(_onPermissionChanged);
    super.dispose();
  }

  Future<void> _load() async {
    await runWithLoading(() async {
      final result = await _svc.fetchQueue();
      if (!mounted) return;
      setState(() {
        _isAvailable = result.available;
        _items       = result.rows;
      });
    });
  }

  // ─── 마감 처리 진입 ────────────────────────────────────────────────────────

  Future<void> _openAttendance(UnclosedQueueItem item) async {
    // AttendanceStatusDialog 기존 canonical 화면 재사용
    // CloseManagementDialog와 동일한 call signature
    final changed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AttendanceStatusDialog(
        date:              item.workDate,
        businessIds:       [item.businessId],
        initialBusinessId: item.businessId,
      ),
    );
    if (changed == true && mounted) {
      _hasChanges = true;
      // 처리 후 전체 reload — 완전 마감 row는 사라지고, 부분 마감 row는 갱신됨
      await _load();
    }
  }

  // ─── 빌드 ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        // _hasChanges bool result를 caller에게 전달
        if (!didPop) Navigator.pop(context, _hasChanges);
      },
      child: AppPageScaffold(
        title: '마감 필요',
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, size: 22),
            color: AppColors.textSecondary,
            onPressed: (isLoading || _accessRevoked) ? null : _load,
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
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const NotificationScreen()),
              ),
              tooltip: '알림',
            ),
          ),
        ],
        body: _accessUnverified
            // [CROSS-DOMAIN-R5.1F.5] 확인 실패 — "권한 없음"이 아니다.
            ? AppEmptyState(
                icon: Icons.sync_problem_outlined,
                title: '권한 정보를 확인하지 못했습니다',
                subtitle: '잠시 후 다시 시도해주세요.',
                action: TextButton(
                  onPressed: () => unawaited(
                      _userProvider?.refreshSubAdminAccessState() ??
                          Future.value()),
                  child: const Text('다시 확인'),
                ),
              )
            : _accessRevoked
            // [CROSS-DOMAIN-R5.1F.1] 권한 회수 — "마감 필요 0건"이 아니다.
            ? const AppEmptyState(
                icon: Icons.lock_outline,
                title: '접근 권한이 없습니다',
                subtitle: '급여 관리 권한이 있는 관리자에게 문의하세요.',
              )
            : isLoading
                ? const LoadingWidget()
                : _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (!_isAvailable) return _buildErrorState();
    if (_items.isEmpty) return _buildEmptyState();
    return Column(
      children: [
        _buildTopSummary(),
        const Divider(height: 1, thickness: 1, color: AppColors.borderLight),
        Expanded(
          child: ListView.builder(
            // AppPageScaffold는 body에 하단 SafeArea를 적용하지 않는다.
            // gesture navigation 기기에서 마지막 row가 시스템 바에 가리지 않도록 보정.
            padding: EdgeInsets.only(
              bottom: MediaQuery.paddingOf(context).bottom,
            ),
            itemCount: _items.length,
            itemBuilder: (_, i) => _buildRow(_items[i]),
          ),
        ),
      ],
    );
  }

  // ─── 상단 요약 ─────────────────────────────────────────────────────────────

  Widget _buildTopSummary() {
    final total = _items.length;
    final oldestDays = total > 0 ? _daysAgo(_items.first.workDate) : 0;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '마감 필요 $total건',
            style: ResponsiveHelper.bodyStyle(
              context,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ).copyWith(fontSize: 17),
          ),
          if (total > 0) ...[
            const SizedBox(height: 2),
            Text(
              '가장 오래된 미처리 ${_urgencyLabel(oldestDays)}',
              style: ResponsiveHelper.bodyStyle(
                context,
                color: AppColors.textTertiary,
              ).copyWith(fontSize: 13),
            ),
          ],
        ],
      ),
    );
  }

  // ─── 각 row ────────────────────────────────────────────────────────────────

  Widget _buildRow(UnclosedQueueItem item) {
    final daysAgo = _daysAgo(item.workDate);
    final urgency = _urgencyLabel(daysAgo);
    final dateLabel = _dateFmt.format(item.workDate);

    return InkWell(
      onTap: () => _openAttendance(item),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: const BoxDecoration(
          color: AppColors.surface,
          border: Border(
            bottom: BorderSide(color: AppColors.borderLight, width: 1),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // ─ 정보 영역 ─────────────────────────────────────────────────
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 날짜 + D+N
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          dateLabel,
                          style: ResponsiveHelper.bodyStyle(
                            context,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary,
                          ).copyWith(fontSize: 14),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        urgency,
                        style: ResponsiveHelper.bodyStyle(
                          context,
                          color: AppColors.textSecondary,
                        ).copyWith(fontSize: 12),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  // 사업장명
                  Text(
                    item.businessName,
                    style: ResponsiveHelper.bodyStyle(
                      context,
                      color: AppColors.textSecondary,
                    ).copyWith(fontSize: 13),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),
                  // 확정/완료/남음
                  Text(
                    '확정 ${item.totalConfirmed}명 · 완료 ${item.closedCount}명 · ${item.remainingCount}명 남음',
                    style: ResponsiveHelper.bodyStyle(
                      context,
                      color: AppColors.textTertiary,
                    ).copyWith(fontSize: 12),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.chevron_right, size: 20, color: AppColors.textHint),
          ],
        ),
      ),
    );
  }

  // ─── 상태 화면들 ────────────────────────────────────────────────────────────

  Widget _buildEmptyState() {
    return const AppEmptyState(
      icon: Icons.check_circle_outline,
      title: '마감할 근무일이 없어요',
    );
  }

  // available:false — 0건처럼 보이면 안 됨 (별도 semantics 유지)
  Widget _buildErrorState() {
    return AppEmptyState(
      icon: Icons.error_outline,
      iconColor: AppColors.error,
      title: '마감 정보를 불러오지 못했어요',
      action: OutlinedButton(
        onPressed: isLoading ? null : _load,
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.brand,
          side: const BorderSide(color: AppColors.brand),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
        child: const Text('다시 시도'),
      ),
    );
  }
}
