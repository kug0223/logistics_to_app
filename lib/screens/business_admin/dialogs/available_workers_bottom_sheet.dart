// Phase 8.1B / R7.2A — 근무 가능 인력 BottomSheet
// R7.2A 추가: weeklyBusinessCount 표시, FULL_POOL filter/sort, poolComplete parity
// DayApplicantsDialog에서 부족한 work group에서 열린다.
// DialogHelper.showSheet()를 통해 표시.
import 'package:flutter/material.dart';

import '../../../models/core/available_worker_model.dart';
import '../../../services/available_workers_service.dart';
import '../../../theme/app_colors.dart';
import '../../../utils/dialog_helper.dart';
import '../../../utils/format_helper.dart';
import '../../../utils/responsive_helper.dart';
import '../../../utils/toast_helper.dart';

// ── 필터/정렬 Enum ────────────────────────────────────────────────────────────

enum _WeeklyRange { all, zero, oneToTwo, threePlus }

enum _SortMode { recommended, weeklyAsc, weeklyDesc }

// ── Main Widget ───────────────────────────────────────────────────────────────

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

  // ── 데이터 ──────────────────────────────────────────────────────────────────
  /// 서버 추천순 원본 (불변 source — sort/filter 복원 기준, append-only)
  List<AvailableWorkerModel> _recommendedOrder = [];

  /// filter + sort 적용 후 display 목록
  List<AvailableWorkerModel> _displayCandidates = [];

  /// [R7.2A] CF poolComplete 파싱값 — 응답 누락 시 false (보수적 default)
  bool _poolComplete = false;
  bool _hasMore = false;
  String? _nextCursor;
  bool _isLoading = true;
  bool _isLoadingMore = false;
  String? _error;

  // ── 초대 상태 ────────────────────────────────────────────────────────────────
  final Set<String> _invitedUids = {};
  final Map<String, bool> _invitingUids = {};

  // ── [R7.2A] Filter / Sort 상태 ────────────────────────────────────────────
  bool _filterWorkExperience = false;
  _WeeklyRange _filterWeeklyRange = _WeeklyRange.all;
  Set<String> _filterDistricts = {};
  _SortMode _sortMode = _SortMode.recommended;

  // ── Computed ─────────────────────────────────────────────────────────────────
  /// FULL_POOL 조건: poolComplete==true AND hasMore==false (§13)
  bool get _isFullPool => _poolComplete && !_hasMore;

  /// FULL_POOL 기준 전체 pool의 non-null/non-empty district distinct 목록 (정렬됨)
  List<String> get _availableDistricts {
    if (!_isFullPool) return [];
    return _recommendedOrder
        .map((w) => w.district)
        .whereType<String>()
        .where((d) => d.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
  }

  /// 활성 filter category 수 (버튼 badge용)
  int get _activeFilterCount {
    int n = 0;
    if (_filterWorkExperience) n++;
    if (_filterWeeklyRange != _WeeklyRange.all) n++;
    if (_filterDistricts.isNotEmpty) n++;
    return n;
  }

  // ── Lifecycle ────────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _load();
  }

  // ── 데이터 로딩 ──────────────────────────────────────────────────────────────
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
          // append — 추천순 원본에 새 page 추가
          _recommendedOrder = [..._recommendedOrder, ...result.candidates];
        } else {
          // 초기 로드 — 상태 초기화
          _recommendedOrder = result.candidates;
          _filterWorkExperience = false;
          _filterWeeklyRange = _WeeklyRange.all;
          _filterDistricts = {};
          _sortMode = _SortMode.recommended;
        }
        _poolComplete = result.poolComplete;
        _hasMore = result.hasMore;
        _nextCursor = result.nextCursor;
        _isLoading = false;
        _isLoadingMore = false;
      });
      _applyFilterSort();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = _parseError(e);
        _isLoading = false;
        _isLoadingMore = false;
      });
    }
  }

  // ── [R7.2A] Filter + Sort 적용 ───────────────────────────────────────────────
  /// _recommendedOrder → filter → sort → _displayCandidates
  /// FULL_POOL에서만 실질적으로 동작 (PAGED에서는 filter/sort UI 자체 미노출)
  void _applyFilterSort() {
    var list = List.of(_recommendedOrder);

    // ── Filter ──────────────────────────────────────────────────────────────
    if (_filterWorkExperience) {
      list = list.where((w) => w.hasSameWorkExperience).toList();
    }
    if (_filterWeeklyRange != _WeeklyRange.all) {
      list = list.where((w) {
        final c = w.weeklyBusinessCount;
        switch (_filterWeeklyRange) {
          case _WeeklyRange.zero:      return c == 0;
          case _WeeklyRange.oneToTwo:  return c >= 1 && c <= 2;
          case _WeeklyRange.threePlus: return c >= 3;
          case _WeeklyRange.all:       return true;
        }
      }).toList();
    }
    if (_filterDistricts.isNotEmpty) {
      list = list.where((w) =>
          w.district != null && _filterDistricts.contains(w.district)).toList();
    }

    // ── Sort ─────────────────────────────────────────────────────────────────
    // Dart List.sort() stable 가정 금지 (§16).
    // tie-break: 명시적 추천 index map 사용 (§17-19).
    if (_sortMode != _SortMode.recommended) {
      final indexMap = <String, int>{
        for (var i = 0; i < _recommendedOrder.length; i++)
          _recommendedOrder[i].uid: i,
      };
      list.sort((a, b) {
        final cntA = a.weeklyBusinessCount;
        final cntB = b.weeklyBusinessCount;
        final primary = _sortMode == _SortMode.weeklyAsc
            ? cntA.compareTo(cntB)
            : cntB.compareTo(cntA);
        if (primary != 0) return primary;
        // tie-break: 추천 index 오름차순 (두 sort 모드 공통)
        return (indexMap[a.uid] ?? 0).compareTo(indexMap[b.uid] ?? 0);
      });
    }
    // 추천순: list는 이미 _recommendedOrder 기반 filter 결과 = 추천순 유지 (§21)

    setState(() => _displayCandidates = list);
  }

  void _resetFilter() {
    setState(() {
      _filterWorkExperience = false;
      _filterWeeklyRange = _WeeklyRange.all;
      _filterDistricts = {};
    });
    _applyFilterSort();
  }

  // ── Filter Sheet ────────────────────────────────────────────────────────────
  Future<void> _openFilterSheet() async {
    var tmpExp = _filterWorkExperience;
    var tmpRange = _filterWeeklyRange;
    var tmpDistricts = Set<String>.from(_filterDistricts);
    final districts = _availableDistricts;

    await DialogHelper.showSheet<void>(
      context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom,
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(ctx).size.height * 0.7,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 핸들
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
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                  child: Text(
                    '필터',
                    style: ResponsiveHelper.subtitleStyle(ctx)
                        .copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
                const Divider(),
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // ─ 업무 경험 ───────────────────────────────────────
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                          child: Text(
                            '업무 경험',
                            style: ResponsiveHelper.bodyStyle(ctx)
                                .copyWith(fontWeight: FontWeight.w600),
                          ),
                        ),
                        CheckboxListTile(
                          value: tmpExp,
                          onChanged: (v) => setSt(() => tmpExp = v ?? false),
                          title: Text(
                            '이 업무 경험 있음',
                            style: ResponsiveHelper.bodyStyle(ctx),
                          ),
                          dense: true,
                          contentPadding:
                              const EdgeInsets.symmetric(horizontal: 16),
                        ),
                        // ─ 이번 주 이 사업장 근무 ──────────────────────────
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                          child: Text(
                            '이번 주 이 사업장 근무',
                            style: ResponsiveHelper.bodyStyle(ctx)
                                .copyWith(fontWeight: FontWeight.w600),
                          ),
                        ),
                        for (final opt in _WeeklyRange.values)
                          RadioListTile<_WeeklyRange>(
                            value: opt,
                            groupValue: tmpRange,
                            onChanged: (v) =>
                                setSt(() => tmpRange = v ?? _WeeklyRange.all),
                            title: Text(
                              _weeklyRangeLabel(opt),
                              style: ResponsiveHelper.bodyStyle(ctx),
                            ),
                            dense: true,
                            contentPadding:
                                const EdgeInsets.symmetric(horizontal: 16),
                          ),
                        // ─ 지역 (FULL_POOL + district 있을 때만) ─────────
                        if (districts.isNotEmpty) ...[
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                            child: Text(
                              '지역',
                              style: ResponsiveHelper.bodyStyle(ctx)
                                  .copyWith(fontWeight: FontWeight.w600),
                            ),
                          ),
                          for (final d in districts)
                            CheckboxListTile(
                              value: tmpDistricts.contains(d),
                              onChanged: (v) => setSt(() {
                                if (v == true) {
                                  tmpDistricts.add(d);
                                } else {
                                  tmpDistricts.remove(d);
                                }
                              }),
                              title: Text(
                                d,
                                style: ResponsiveHelper.bodyStyle(ctx),
                              ),
                              dense: true,
                              contentPadding:
                                  const EdgeInsets.symmetric(horizontal: 16),
                            ),
                        ],
                        const SizedBox(height: 8),
                      ],
                    ),
                  ),
                ),
                const Divider(height: 1),
                // ─ 하단 버튼 ─────────────────────────────────────────────
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                    child: Row(
                      children: [
                        TextButton(
                          onPressed: () => setSt(() {
                            tmpExp = false;
                            tmpRange = _WeeklyRange.all;
                            tmpDistricts = {};
                          }),
                          child: const Text('초기화'),
                        ),
                        const Spacer(),
                        // 미리보기 count
                        _FilterPreviewCount(
                          recommendedOrder: _recommendedOrder,
                          filterExp: tmpExp,
                          filterRange: tmpRange,
                          filterDistricts: tmpDistricts,
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          onPressed: () {
                            setState(() {
                              _filterWorkExperience = tmpExp;
                              _filterWeeklyRange = tmpRange;
                              _filterDistricts = Set.from(tmpDistricts);
                            });
                            _applyFilterSort();
                            Navigator.pop(ctx);
                          },
                          child: const Text('적용'),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _weeklyRangeLabel(_WeeklyRange r) {
    switch (r) {
      case _WeeklyRange.all:       return '전체';
      case _WeeklyRange.zero:      return '0회';
      case _WeeklyRange.oneToTwo:  return '1~2회';
      case _WeeklyRange.threePlus: return '3회 이상';
    }
  }

  // ── 초대 ─────────────────────────────────────────────────────────────────────
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

  String _parseError(Object e) {
    final s = e.toString().toLowerCase();
    if (s.contains('not-found')) return '공고 또는 슬롯 정보를 찾을 수 없습니다.';
    if (s.contains('permission-denied')) return '조회 권한이 없습니다.';
    if (s.contains('failed-precondition')) {
      return '사업장 위치 정보가 설정되지 않았습니다.\n사업장 설정에서 도시를 입력해주세요.';
    }
    return '인력 조회에 실패했습니다. 다시 시도해주세요.';
  }

  // ── Build ─────────────────────────────────────────────────────────────────
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

          // ── [R7.2A] FULL_POOL 전용 filter/sort control row ──────────────
          // PAGED(poolComplete=false || hasMore=true)에서 미노출 (§36)
          // PAGED에서 추천순 거짓 label, 기본 순서 control 추가 모두 금지 (§26, §36)
          if (!_isLoading && _error == null && _isFullPool) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Row(
                children: [
                  // 필터 버튼 (활성 시 count badge)
                  TextButton.icon(
                    onPressed: _openFilterSheet,
                    icon: const Icon(Icons.tune_rounded, size: 16),
                    label: _activeFilterCount > 0
                        ? Text('필터 $_activeFilterCount')
                        : const Text('필터'),
                    style: TextButton.styleFrom(
                      foregroundColor: _activeFilterCount > 0
                          ? AppColors.info
                          : AppColors.textSecondary,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                    ),
                  ),
                  const Spacer(),
                  // 정렬 팝업
                  PopupMenuButton<_SortMode>(
                    initialValue: _sortMode,
                    onSelected: (mode) {
                      setState(() => _sortMode = mode);
                      _applyFilterSort();
                    },
                    itemBuilder: (_) => [
                      PopupMenuItem(
                        value: _SortMode.recommended,
                        child: _SortMenuItem(
                          label: '추천순',
                          selected: _sortMode == _SortMode.recommended,
                        ),
                      ),
                      PopupMenuItem(
                        value: _SortMode.weeklyAsc,
                        child: _SortMenuItem(
                          label: '이번 주 근무 적은 순',
                          selected: _sortMode == _SortMode.weeklyAsc,
                        ),
                      ),
                      PopupMenuItem(
                        value: _SortMode.weeklyDesc,
                        child: _SortMenuItem(
                          label: '이번 주 근무 많은 순',
                          selected: _sortMode == _SortMode.weeklyDesc,
                        ),
                      ),
                    ],
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _sortModeLabel(_sortMode),
                          style: ResponsiveHelper.smallStyle(
                              context, color: AppColors.textSecondary),
                        ),
                        const Icon(Icons.arrow_drop_down_rounded,
                            size: 18, color: AppColors.grey500),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],

          const Divider(height: 1),

          // ── 본문 ─────────────────────────────────────────────────────────
          Flexible(child: _buildBody()),
        ],
      ),
    );
  }

  String _sortModeLabel(_SortMode m) {
    switch (m) {
      case _SortMode.recommended: return '추천순';
      case _SortMode.weeklyAsc:   return '근무 적은 순';
      case _SortMode.weeklyDesc:  return '근무 많은 순';
    }
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

    // 기본 pool 자체 비어있음 (§48)
    if (_recommendedOrder.isEmpty && !_hasMore) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.person_search_outlined,
                size: 48, color: AppColors.grey400),
            const SizedBox(height: 12),
            Text(
              '현재 초대 가능한 인력이 없습니다.',
              style: ResponsiveHelper.bodyStyle(
                  context, color: AppColors.grey500),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    // FULL_POOL filter 결과 없음 (§49-50)
    // poolComplete==true일 때만 — false empty 금지 (PAGED partial 기반 empty state 금지)
    if (_isFullPool && _displayCandidates.isEmpty && _activeFilterCount > 0) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.search_off_rounded,
                size: 48, color: AppColors.grey400),
            const SizedBox(height: 12),
            Text(
              '조건에 맞는 초대 가능 인력이 없습니다.',
              style: ResponsiveHelper.bodyStyle(
                  context, color: AppColors.grey500),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: _resetFilter,
              child: const Text('필터 초기화'),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      shrinkWrap: true,
      physics: const BouncingScrollPhysics(),
      itemCount: _displayCandidates.length + (_hasMore ? 1 : 0),
      itemBuilder: (ctx, i) {
        if (i == _displayCandidates.length) {
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
        return _buildCandidateRow(_displayCandidates[i]);
      },
    );
  }

  Widget _buildCandidateRow(AvailableWorkerModel worker) {
    final isInviting = _invitingUids[worker.uid] == true;
    final isInvited = _invitedUids.contains(worker.uid);

    // [R7.2A] 통합 메타데이터 줄 (§38-40)
    // "이 업무 경험 있음 · 이번 주 이 사업장 N회" or "이번 주 이 사업장 N회"
    // exact workType count / totalWorkDays / 신규 badge 미노출 (R3-D / §41-43)
    // 0회도 표시, neutral color — 강조/평가 표현 금지 (§39)
    final weeklyText = '이번 주 이 사업장 ${worker.weeklyBusinessCount}회';
    final metaText = worker.hasSameWorkExperience
        ? '이 업무 경험 있음 · $weeklyText'
        : weeklyText;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // ── 이름 + 지역 + 통합 메타데이터 ──────────────────────────────
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  worker.maskedName,
                  style: ResponsiveHelper.bodyStyle(context)
                      .copyWith(fontWeight: FontWeight.w600),
                ),
                if (worker.locationLabel.isNotEmpty)
                  Text(
                    worker.locationLabel,
                    style: ResponsiveHelper.smallStyle(
                        context, color: AppColors.grey500),
                  ),
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    metaText,
                    style: ResponsiveHelper.smallStyle(
                        context, color: AppColors.grey500),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),

          // ── 버튼 ─────────────────────────────────────────────────────
          if (isInvited)
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
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

// ── Helper Widgets ────────────────────────────────────────────────────────────

/// PopupMenu 정렬 항목 (선택됨 check 표시용)
class _SortMenuItem extends StatelessWidget {
  final String label;
  final bool selected;

  const _SortMenuItem({required this.label, required this.selected});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 20,
          child: selected
              ? Icon(Icons.check_rounded, size: 16, color: AppColors.info)
              : null,
        ),
        Text(label),
      ],
    );
  }
}

/// Filter sheet 하단 "N명" 미리보기 count (StatefulBuilder 내부에서 동적 rebuild)
class _FilterPreviewCount extends StatelessWidget {
  final List<AvailableWorkerModel> recommendedOrder;
  final bool filterExp;
  final _WeeklyRange filterRange;
  final Set<String> filterDistricts;

  const _FilterPreviewCount({
    required this.recommendedOrder,
    required this.filterExp,
    required this.filterRange,
    required this.filterDistricts,
  });

  @override
  Widget build(BuildContext context) {
    var list = List.of(recommendedOrder);
    if (filterExp) list = list.where((w) => w.hasSameWorkExperience).toList();
    if (filterRange != _WeeklyRange.all) {
      list = list.where((w) {
        final c = w.weeklyBusinessCount;
        switch (filterRange) {
          case _WeeklyRange.zero:      return c == 0;
          case _WeeklyRange.oneToTwo:  return c >= 1 && c <= 2;
          case _WeeklyRange.threePlus: return c >= 3;
          case _WeeklyRange.all:       return true;
        }
      }).toList();
    }
    if (filterDistricts.isNotEmpty) {
      list = list.where((w) =>
          w.district != null && filterDistricts.contains(w.district)).toList();
    }
    return Text(
      '${list.length}명',
      style: ResponsiveHelper.smallStyle(
          context, color: AppColors.textSecondary),
    );
  }
}
