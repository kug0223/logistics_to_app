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

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../providers/user_provider.dart';
import '../../services/unclosed_action_queue_service.dart';
import '../../theme/app_colors.dart';
import '../../utils/loading_state_mixin.dart';
import '../../utils/responsive_helper.dart';
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

  // ─── 로드 ──────────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // [AUDIT.2-M003] screen-level guard — canManageWage 없는 직접 진입 방어
      final up = context.read<UserProvider>();
      if (!up.can((p) => p.canManageWage)) {
        Navigator.of(context).pop();
        return;
      }
      _load();
    });
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
            '마감 필요',
            style: ResponsiveHelper.titleStyle(
              context, color: AppColors.textPrimary,
            ),
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
    if (!_isAvailable) return _buildErrorState();
    if (_items.isEmpty) return _buildEmptyState();
    return Column(
      children: [
        _buildTopSummary(),
        const Divider(height: 1, thickness: 1, color: AppColors.borderLight),
        Expanded(
          child: ListView.builder(
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
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.check_circle_outline, size: 56, color: AppColors.textHint),
          const SizedBox(height: 12),
          Text(
            '마감할 근무일이 없어요',
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

  // available:false — 0건처럼 보이면 안 됨
  Widget _buildErrorState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, size: 56, color: AppColors.error),
          const SizedBox(height: 12),
          Text(
            '마감 정보를 불러오지 못했어요',
            style: ResponsiveHelper.bodyStyle(
              context,
              color: AppColors.textTertiary,
              fontWeight: FontWeight.w500,
            ).copyWith(fontSize: 15),
          ),
          const SizedBox(height: 16),
          OutlinedButton(
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
        ],
      ),
    );
  }
}
