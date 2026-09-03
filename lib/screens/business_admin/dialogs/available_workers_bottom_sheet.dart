// Phase 8.1B — 근무 가능 인력 BottomSheet
// DayApplicantsDialog에서 부족한 work group에서 열린다.
// DialogHelper.showSheet()를 통해 표시.
import 'package:flutter/material.dart';

import '../../../models/core/available_worker_model.dart';
import '../../../services/available_workers_service.dart';
import '../../../theme/app_colors.dart';
import '../../../utils/format_helper.dart';
import '../../../utils/responsive_helper.dart';
import '../../../utils/toast_helper.dart';

class AvailableWorkersBottomSheet extends StatefulWidget {
  final String toId;
  final String slotId;
  final String? workDetailId;
  final String businessId;
  final DateTime date;
  final String workType;
  final String startTime;
  final String endTime;
  final int requiredCount;
  final int confirmedCount;

  const AvailableWorkersBottomSheet({
    super.key,
    required this.toId,
    required this.slotId,
    this.workDetailId,
    required this.businessId,
    required this.date,
    required this.workType,
    required this.startTime,
    required this.endTime,
    required this.requiredCount,
    required this.confirmedCount,
  });

  @override
  State<AvailableWorkersBottomSheet> createState() =>
      _AvailableWorkersBottomSheetState();
}

class _AvailableWorkersBottomSheetState
    extends State<AvailableWorkersBottomSheet> {
  final _svc = AvailableWorkersService();

  List<AvailableWorkerModel> _candidates = [];
  bool _isLoading = true;
  bool _isLoadingMore = false;
  String? _error;
  bool _hasMore = false;
  String? _nextCursor;

  // uid → 초대 진행/완료 상태
  final Set<String> _invitedUids = {};
  final Map<String, bool> _invitingUids = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool loadMore = false}) async {
    if (!loadMore) {
      setState(() {
        _isLoading = true;
        _error = null;
      });
    } else {
      setState(() => _isLoadingMore = true);
    }
    try {
      final result = await _svc.getAvailableWorkers(
        toId: widget.toId,
        slotId: widget.slotId,
        workDetailId: widget.workDetailId,
        cursor: loadMore ? _nextCursor : null,
      );
      if (!mounted) return;
      setState(() {
        if (loadMore) {
          _candidates.addAll(result.candidates);
        } else {
          _candidates = result.candidates;
        }
        _hasMore = result.hasMore;
        _nextCursor = result.nextCursor;
        _isLoading = false;
        _isLoadingMore = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = _parseError(e);
        _isLoading = false;
        _isLoadingMore = false;
      });
    }
  }

  String _parseError(Object e) {
    final s = e.toString().toLowerCase();
    if (s.contains('not-found')) return '공고 또는 슬롯 정보를 찾을 수 없습니다.';
    if (s.contains('permission-denied')) return '조회 권한이 없습니다.';
    if (s.contains('failed-precondition')) {
      return '사업장 위치 정보가 설정되지 않았습니다.\n사업장 설정에서 도시를 입력해주세요.';
    }
    return '인력 조회에 실패했습니다. 다시 시도해주세요.';
  }

  Future<void> _invite(AvailableWorkerModel worker) async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('근무 제안'),
        content: Text(
          '${worker.maskedName}님에게\n'
          '${FormatHelper.formatDate(widget.date)} '
          '${widget.workType} (${widget.startTime}~${widget.endTime})\n'
          '근무 제안을 보내시겠습니까?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('제안 보내기'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _invitingUids[worker.uid] = true);
    try {
      await _svc.inviteWorker(
        toId: widget.toId,
        businessId: widget.businessId,
        targetUid: worker.uid,
        workDate: widget.date,
        slotId: widget.slotId,
        // [Phase 8.1B.4] workType+시간 3중 매칭으로 정확한 WorkDetail 식별 (wage 오파생 방지)
        selectedWorkType: widget.workType,
        workDetailStartTime: widget.startTime,
        workDetailEndTime: widget.endTime,
      );
      if (!mounted) return;
      setState(() {
        _invitedUids.add(worker.uid);
        _invitingUids.remove(worker.uid);
      });
      ToastHelper.showSuccess('근무 제안을 보냈습니다.');
    } catch (e) {
      if (!mounted) return;
      setState(() => _invitingUids.remove(worker.uid));
      final s = e.toString().toLowerCase();
      String msg = '제안 전송에 실패했습니다. 다시 시도해주세요.';
      if (s.contains('full') || s.contains('정원')) {
        msg = '정원이 초과되어 제안을 보낼 수 없습니다.';
      } else if (s.contains('already') || s.contains('이미')) {
        msg = '이미 지원하거나 초대된 근로자입니다.';
      } else if (s.contains('permission')) {
        msg = '초대 권한이 없습니다.';
      }
      ToastHelper.showError(msg);
    }
  }

  @override
  Widget build(BuildContext context) {
    final shortage = widget.requiredCount - widget.confirmedCount;
    final shortageLabel = shortage <= 0 ? '0' : '$shortage';

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.75,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── 드래그 핸들 ──────────────────────────────────────────────────
          Center(
            child: Container(
              margin: const EdgeInsets.symmetric(vertical: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.grey300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // ── 헤더 ─────────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '근무 가능 인력',
                  style: ResponsiveHelper.subtitleStyle(context)
                      .copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text(
                  '${FormatHelper.formatDate(widget.date)}  '
                  '${widget.workType}  '
                  '${widget.startTime}~${widget.endTime}',
                  style: ResponsiveHelper.smallStyle(
                      context, color: AppColors.textSecondary),
                ),
                const SizedBox(height: 2),
                Text(
                  '정원 ${widget.requiredCount}명 · 확정 ${widget.confirmedCount}명 · 부족 $shortageLabel명',
                  style: ResponsiveHelper.smallStyle(
                      context, color: AppColors.warning),
                ),
              ],
            ),
          ),

          const Divider(height: 1),

          // ── 본문 ─────────────────────────────────────────────────────────
          Flexible(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Padding(
        padding: EdgeInsets.all(40),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: AppColors.error, size: 40),
            const SizedBox(height: 12),
            Text(
              _error!,
              style: ResponsiveHelper.bodyStyle(context),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: _load,
              child: const Text('다시 시도'),
            ),
          ],
        ),
      );
    }

    if (_candidates.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.person_search_outlined,
                size: 48, color: AppColors.grey400),
            const SizedBox(height: 12),
            Text(
              '이 날 가능일을 등록한 인력이 없습니다',
              style: ResponsiveHelper.bodyStyle(
                  context, color: AppColors.grey500),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      shrinkWrap: true,
      physics: const BouncingScrollPhysics(),
      itemCount: _candidates.length + (_hasMore ? 1 : 0),
      itemBuilder: (ctx, i) {
        if (i == _candidates.length) {
          return Padding(
            padding: const EdgeInsets.all(16),
            child: _isLoadingMore
                ? const Center(
                    child: SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : OutlinedButton(
                    onPressed: () => _load(loadMore: true),
                    child: const Text('더 불러오기'),
                  ),
          );
        }
        return _buildCandidateRow(_candidates[i]);
      },
    );
  }

  Widget _buildCandidateRow(AvailableWorkerModel worker) {
    final isInviting = _invitingUids[worker.uid] == true;
    final isInvited = _invitedUids.contains(worker.uid);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          // ── 이름 + 지역 ──────────────────────────────────────────────
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  worker.maskedName,
                  style: ResponsiveHelper.bodyStyle(context)
                      .copyWith(fontWeight: FontWeight.w600),
                ),
                if (worker.district != null && worker.district!.isNotEmpty)
                  Text(
                    worker.locationLabel,
                    style: ResponsiveHelper.smallStyle(
                        context, color: AppColors.grey500),
                  )
                else if (worker.city.isNotEmpty)
                  Text(
                    worker.city,
                    style: ResponsiveHelper.smallStyle(
                        context, color: AppColors.grey500),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),

          // ── 버튼 ─────────────────────────────────────────────────────
          if (isInvited)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: AppColors.grey100,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '제안 보냄',
                style: ResponsiveHelper.smallStyle(
                    context, color: AppColors.grey500),
              ),
            )
          else if (isInviting)
            const SizedBox(
              width: 64,
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else
            OutlinedButton(
              onPressed: () => _invite(worker),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.info,
                side: const BorderSide(color: AppColors.info),
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(
                '근무 제안',
                style: ResponsiveHelper.smallStyle(
                    context, color: AppColors.info),
              ),
            ),
        ],
      ),
    );
  }
}
