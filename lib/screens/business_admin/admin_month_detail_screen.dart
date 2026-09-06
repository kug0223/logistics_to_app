import 'dart:io';

import 'package:excel/excel.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../models/core/attendance_model.dart';
import '../../services/admin_stats_service.dart';
import '../../theme/app_colors.dart';
import '../../utils/format_helper.dart';
import '../../utils/responsive_helper.dart';
import '../../utils/toast_helper.dart';
import '../../screens/common/notification_screen.dart';
import '../../utils/navigation_helper.dart';
import '../../widgets/common/app_empty_state.dart';
import '../../widgets/common/app_page_scaffold.dart';
import '../../widgets/common/loading_widget.dart';
import '../../widgets/common/notification_badge.dart';

class AdminMonthDetailScreen extends StatefulWidget {
  final List<String> businessIds;
  final String? filterBusinessId;
  final int year;
  final int month;
  final List<BusinessOption> businesses;

  const AdminMonthDetailScreen({
    super.key,
    required this.businessIds,
    required this.filterBusinessId,
    required this.year,
    required this.month,
    required this.businesses,
  });

  @override
  State<AdminMonthDetailScreen> createState() => _AdminMonthDetailScreenState();
}

enum _SortType { days, wage, name }

class _AdminMonthDetailScreenState extends State<AdminMonthDetailScreen> {
  final _service = AdminStatsService();

  bool _isLoading = true;
  bool _fetchInProgress = false;
  bool _isExporting = false;
  bool _hasError = false;
  MonthDetailData? _data;
  _SortType _sortType = _SortType.days;
  List<WorkerMonthSummary>? _cachedSortedWorkers; // 정렬 캐시 — sortType 변경 시만 재계산

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _loadData();
    });
  }

  Future<void> _loadData() async {
    if (_fetchInProgress) return;
    _fetchInProgress = true;
    setState(() { _isLoading = true; _hasError = false; });
    try {
      final data = await _service.getMonthDetail(
        businessIds: widget.businessIds,
        filterBusinessId: widget.filterBusinessId,
        year: widget.year,
        month: widget.month,
      );
      if (mounted) setState(() { _data = data; _cachedSortedWorkers = null; });
    } catch (e) {
      debugPrint('❌ 월 상세 로드 실패: $e');
      if (mounted) setState(() => _hasError = true);
    } finally {
      _fetchInProgress = false;
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ─── Excel 내보내기 ──────────────────────────────────────────

  static const _excelHeaders = [
    '사업장명', '근무일자', '파트', '이름', '성별', '연락처',
    '출근시간', '퇴근시간', '비고',
  ];

  void _writeHeaderRow(Sheet sheet) {
    for (int i = 0; i < _excelHeaders.length; i++) {
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0))
          .value = TextCellValue(_excelHeaders[i]);
    }
  }

  int _writeAttendanceRows(Sheet sheet, List<AttendanceModel> records,
      Map<String, UserInfo> infoMap, int startRow) {
    // 근무일자 → 이름 순 정렬
    final sorted = List<AttendanceModel>.from(records)
      ..sort((a, b) {
        final biz = a.businessName.compareTo(b.businessName);
        if (biz != 0) return biz;
        final d = a.workDate.compareTo(b.workDate);
        if (d != 0) return d;
        return (infoMap[a.userId]?.name ?? '').compareTo(
            infoMap[b.userId]?.name ?? '');
      });

    int row = startRow;
    for (final r in sorted) {
      final info = infoMap[r.userId];
      final dateStr = FormatHelper.formatDateISO(r.workDate);
      final checkIn  = r.checkIn  ?? '-';
      final checkOut = r.checkOut ?? '-';
      final note = r.statusLabel +
          (r.modifyReason?.isNotEmpty ?? false ? ' / ${r.modifyReason}' : '');

      final cells = [
        r.businessName,
        dateStr,
        r.workType,
        info?.name ?? '알 수 없음',
        info?.gender ?? '',
        info?.phone ?? '',
        checkIn,
        checkOut,
        note,
      ];
      for (int c = 0; c < cells.length; c++) {
        sheet
            .cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: row))
            .value = TextCellValue(cells[c]);
      }
      row++;
    }
    return row;
  }

  Future<void> _exportExcel() async {
    final data = _data;
    if (data == null) return;
    setState(() => _isExporting = true);
    try {
      final excel = Excel.createExcel();
      excel.delete('Sheet1');

      // 사업장별로 레코드 분류
      final bizGroups = <String, List<AttendanceModel>>{};
      for (final r in data.rawAttendance) {
        bizGroups.putIfAbsent(r.businessName, () => []).add(r);
      }

      if (bizGroups.length <= 1) {
        // 단일 사업장(또는 필터 적용) — 시트 하나
        final sheetName = bizGroups.keys.firstOrNull ?? '근태현황';
        final sheet = excel[sheetName];
        _writeHeaderRow(sheet);
        _writeAttendanceRows(sheet, data.rawAttendance, data.userInfoMap, 1);
      } else {
        // 복수 사업장 — 사업장별 시트 + 전체 시트
        final allSheet = excel['전체'];
        _writeHeaderRow(allSheet);
        int allRow = 1;
        for (final entry in bizGroups.entries) {
          final bizSheet = excel[entry.key];
          _writeHeaderRow(bizSheet);
          _writeAttendanceRows(bizSheet, entry.value, data.userInfoMap, 1);
          allRow = _writeAttendanceRows(
              allSheet, entry.value, data.userInfoMap, allRow);
        }
        excel.setDefaultSheet('전체');
      }

      // 파일 저장 + 공유
      final dir = await getTemporaryDirectory();
      final fileName = '근태현황_${widget.year}년${widget.month}월.xlsx';
      final file = File('${dir.path}/$fileName');
      final bytes = excel.encode();
      if (bytes == null) {
        if (mounted) ToastHelper.showError('엑셀 생성에 실패했습니다');
        return;
      }
      await file.writeAsBytes(bytes);

      // [BUG-수정] Share 예외 발생 시에도 임시 파일이 반드시 삭제되도록 try-finally 적용 (D-H-1)
      try {
        await Share.shareXFiles([XFile(file.path)], subject: fileName);
      } finally {
        try { await file.delete(); } catch (_) {}
      }
    } catch (e) {
      debugPrint('❌ 엑셀 내보내기 실패: $e');
      if (mounted) {
        ToastHelper.showError('엑셀 내보내기에 실패했습니다');
      }
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  // ─── 정렬 ─────────────────────────────────────────────────

  List<WorkerMonthSummary> _sortedWorkers(MonthDetailData data) {
    if (_cachedSortedWorkers != null) return _cachedSortedWorkers!;
    final list = List<WorkerMonthSummary>.from(data.workers);
    switch (_sortType) {
      case _SortType.days:
        list.sort((a, b) => b.totalDays.compareTo(a.totalDays));
      case _SortType.wage:
        list.sort((a, b) => b.totalWage.compareTo(a.totalWage));
      case _SortType.name:
        list.sort((a, b) => a.userName.compareTo(b.userName));
    }
    _cachedSortedWorkers = list;
    return list;
  }

  // ─── 빌드 ─────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final bizName = widget.filterBusinessId != null
        ? widget.businesses
            .where((b) => b.id == widget.filterBusinessId)
            .map((b) => b.name)
            .firstOrNull
        : (widget.businesses.length == 1 ? widget.businesses.first.name : null);

    // [DESIGN-PATCH-2] GradientScaffold → AppPageScaffold — 관리자 정산 화면 flat admin 정렬
    // onRefresh 자동 버튼 제거 → AppBar refresh action + body RefreshIndicator 유지
    return AppPageScaffold(
      title: bizName != null
          ? '${widget.year}년 ${widget.month}월 · $bizName'
          : '${widget.year}년 ${widget.month}월',
      actions: [
        IconButton(
          icon: const Icon(Icons.refresh_rounded),
          onPressed: _loadData,
          color: AppColors.textSecondary,
        ),
        IconButton(
          icon: const Icon(Icons.home_outlined),
          onPressed: () => NavigationHelper.goHome(context),
          color: AppColors.textSecondary,
        ),
        NotificationBadge(
          child: IconButton(
            icon: const Icon(Icons.notifications_outlined),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const NotificationScreen()),
            ),
            color: AppColors.textSecondary,
          ),
        ),
        if (_isExporting)
          const Padding(
            padding: EdgeInsets.all(8),
            child: SizedBox(
                width: 18, height: 18,
                child: CircularProgressIndicator(strokeWidth: 2)),
          )
        else
          IconButton(
            icon: const Icon(Icons.download_outlined),
            tooltip: '엑셀 내보내기',
            onPressed: (_data == null ||
                    _data!.attendanceStatsState ==
                        AttendanceStatsState.unavailable)
                ? null
                : _exportExcel,
            color: AppColors.textSecondary,
          ),
      ],
      body: _isLoading
          ? const LoadingWidget()
          : RefreshIndicator(
              onRefresh: _loadData,
              child: _buildContent(),
            ),
    );
  }

  Widget _buildContent() {
    if (_hasError) {
      return AppEmptyState(
        icon: Icons.error_outline,
        title: '데이터를 불러오지 못했습니다',
        iconColor: AppColors.error,
        action: TextButton.icon(
          onPressed: _loadData,
          icon: const Icon(Icons.refresh),
          label: const Text('다시 시도'),
        ),
      );
    }

    final data = _data;
    if (data == null) {
      return const AppEmptyState(
        icon: Icons.event_busy_outlined,
        title: '근무 데이터가 없습니다',
      );
    }

    // [SECURITY-ADMIN-STATS-ATTENDANCE-COMPLETENESS 2026-09-05]
    // AVAILABLE + 0 records = genuine empty month (not a failure)
    if (data.attendanceStatsState == AttendanceStatsState.available &&
        data.totalAttendanceCount == 0) {
      return const AppEmptyState(
        icon: Icons.event_busy_outlined,
        title: '근무 데이터가 없습니다',
      );
    }

    // UNAVAILABLE 또는 정상 데이터 — sections이 state-aware하게 렌더링
    return ListView(
      padding: ResponsiveHelper.listPadding(context),
      children: [
        // 근태 현황 + 리뷰 인라인 통합
        _buildAttendanceSummary(data),
        SizedBox(height: ResponsiveHelper.spacing(context, 14)),
        _buildWorkerSection(data),
        SizedBox(height: ResponsiveHelper.spacing(context, 32)),
      ],
    );
  }

  // ─── 근태 요약 ────────────────────────────────────────────

  Widget _buildAttendanceSummary(MonthDetailData data) {
    // [SECURITY-ADMIN-STATS-ATTENDANCE-COMPLETENESS 2026-09-05]
    // UNAVAILABLE: 출근 수치를 0으로 표시하면 관리자 오인 위험
    if (data.attendanceStatsState == AttendanceStatsState.unavailable) {
      return Container(
        padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 16)),
        decoration: _cardDecoration(),
        child: Row(
          children: [
            Icon(Icons.cloud_off_outlined,
                color: AppColors.error,
                size: ResponsiveHelper.iconSize(context, 18)),
            SizedBox(width: ResponsiveHelper.spacing(context, 8)),
            Text(
              '출근 데이터 확인 불가',
              style: ResponsiveHelper.smallStyle(context,
                  color: AppColors.error),
            ),
          ],
        ),
      );
    }

    final total = data.totalAttendanceCount;
    final presRatio = total == 0 ? 0.0 : data.presentCount / total;
    final lateRatio = total == 0 ? 0.0 : data.lateCount / total;
    final absRatio = total == 0 ? 0.0 : data.absentCount / total;

    return Container(
      padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 16)),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '근태 현황',
            style: ResponsiveHelper.bodyStyle(context)
                .copyWith(fontWeight: FontWeight.bold),
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 12)),

          // 비율 바
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: SizedBox(
              height: 14,
              child: Row(
                children: [
                  if (presRatio > 0)
                    Expanded(
                      flex: (presRatio * 1000).round(),
                      child: Container(color: AppColors.success),
                    ),
                  if (lateRatio > 0)
                    Expanded(
                      flex: (lateRatio * 1000).round(),
                      child: Container(color: AppColors.warning),
                    ),
                  if (absRatio > 0)
                    Expanded(
                      flex: (absRatio * 1000).round(),
                      child: Container(color: AppColors.error),
                    ),
                ],
              ),
            ),
          ),

          SizedBox(height: ResponsiveHelper.spacing(context, 12)),

          // 통계 행
          Row(
            children: [
              _AttStat(
                color: AppColors.success,
                label: '정상',
                count: data.presentCount,
                total: total,
              ),
              if (data.lateCount > 0)
                _AttStat(
                  color: AppColors.warning,
                  label: '지각',
                  count: data.lateCount,
                  total: total,
                ),
              if (data.absentCount > 0)
                _AttStat(
                  color: AppColors.error,
                  label: '결근',
                  count: data.absentCount,
                  total: total,
                ),
              const Spacer(),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    _fmtWageFull(data.totalWage),
                    style: ResponsiveHelper.bodyStyle(context)
                        .copyWith(fontWeight: FontWeight.bold),
                  ),
                  Text('총 인건비',
                      style: ResponsiveHelper.tinyStyle(context,
                          color: AppColors.grey500)),
                ],
              ),
            ],
          ),

          // 리뷰 요약 — [SECURITY-ADMIN-REVIEW-STATS-AGGREGATE 2026-09-05]
          // AVAILABLE: 기존 UI 유지 / SUPPRESSED·UNAVAILABLE: 인라인 텍스트 / NODATA: 숨김
          if (data.reviewStatsState == ReviewStatsState.available &&
              (data.avgRating > 0 ||
                  data.rehireCount + data.noRehireCount > 0)) ...[
            SizedBox(height: ResponsiveHelper.spacing(context, 10)),
            const Divider(height: 1, color: AppColors.grey100),
            SizedBox(height: ResponsiveHelper.spacing(context, 10)),
            Row(
              children: [
                if (data.avgRating > 0) ...[
                  Icon(Icons.star_rounded,
                      size: ResponsiveHelper.iconSize(context, 14),
                      color: AppColors.amber),
                  SizedBox(width: ResponsiveHelper.spacing(context, 3)),
                  Text(data.avgRating.toStringAsFixed(1),
                      style: ResponsiveHelper.smallStyle(context,
                          color: AppColors.amber,
                          fontWeight: FontWeight.w700)),
                  SizedBox(width: ResponsiveHelper.spacing(context, 12)),
                ],
                if (data.rehireCount + data.noRehireCount > 0) ...[
                  Icon(Icons.replay_rounded,
                      size: ResponsiveHelper.iconSize(context, 14),
                      color: AppColors.success),
                  SizedBox(width: ResponsiveHelper.spacing(context, 3)),
                  Text(
                    '재고용 ${(data.rehireCount / (data.rehireCount + data.noRehireCount) * 100).toStringAsFixed(0)}%',
                    style: ResponsiveHelper.smallStyle(context,
                        color: AppColors.success,
                        fontWeight: FontWeight.w600),
                  ),
                  SizedBox(width: ResponsiveHelper.spacing(context, 4)),
                  Text(
                    '(${data.rehireCount + data.noRehireCount}건)',
                    style: ResponsiveHelper.tinyStyle(context,
                        color: AppColors.grey400),
                  ),
                ],
                const Spacer(),
                // 상위 태그 2개 인라인
                ..._topTags(data.posTagFreq, 2).map((e) => Padding(
                      padding: EdgeInsets.only(
                          left: ResponsiveHelper.spacing(context, 4)),
                      child: Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: ResponsiveHelper.spacing(context, 7),
                          vertical: ResponsiveHelper.spacing(context, 2),
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.success.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(e.key,
                            style: ResponsiveHelper.tinyStyle(context,
                                color: AppColors.successDark)),
                      ),
                    )),
              ],
            ),
          ],
          // SUPPRESSED(표본 부족) / UNAVAILABLE(조회 실패) — 인라인 텍스트
          if (data.reviewStatsState == ReviewStatsState.suppressed ||
              data.reviewStatsState == ReviewStatsState.unavailable) ...[
            SizedBox(height: ResponsiveHelper.spacing(context, 10)),
            const Divider(height: 1, color: AppColors.grey100),
            SizedBox(height: ResponsiveHelper.spacing(context, 10)),
            Text(
              data.reviewStatsState == ReviewStatsState.suppressed
                  ? '표본 부족'
                  : '확인 불가',
              style: ResponsiveHelper.smallStyle(context,
                  color: AppColors.grey400),
            ),
          ],
        ],
      ),
    );
  }

  // ─── 직원별 요약 ──────────────────────────────────────────

  Widget _buildWorkerSection(MonthDetailData data) {
    // [SECURITY-ADMIN-STATS-ATTENDANCE-COMPLETENESS 2026-09-05]
    // UNAVAILABLE: 0명으로 표시하면 "이달 근무자 없음"으로 오인 위험
    if (data.attendanceStatsState == AttendanceStatsState.unavailable) {
      return Container(
        padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 16)),
        decoration: _cardDecoration(),
        child: Row(
          children: [
            Icon(Icons.info_outline,
                color: AppColors.grey400,
                size: ResponsiveHelper.iconSize(context, 18)),
            SizedBox(width: ResponsiveHelper.spacing(context, 8)),
            Text(
              '출근 데이터를 불러올 수 없습니다',
              style: ResponsiveHelper.smallStyle(context,
                  color: AppColors.grey500),
            ),
          ],
        ),
      );
    }

    final workers = _sortedWorkers(data);
    return Container(
      padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 16)),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 헤더 + 정렬
          Row(
            children: [
              Text(
                '직원별 요약 (${workers.length}명)',
                style: ResponsiveHelper.bodyStyle(context)
                    .copyWith(fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              _SortChip(
                label: '근무일',
                selected: _sortType == _SortType.days,
                onTap: () => setState(() { _sortType = _SortType.days; _cachedSortedWorkers = null; }),
              ),
              SizedBox(width: ResponsiveHelper.spacing(context, 4)),
              _SortChip(
                label: '임금',
                selected: _sortType == _SortType.wage,
                onTap: () => setState(() { _sortType = _SortType.wage; _cachedSortedWorkers = null; }),
              ),
              SizedBox(width: ResponsiveHelper.spacing(context, 4)),
              _SortChip(
                label: '이름',
                selected: _sortType == _SortType.name,
                onTap: () => setState(() { _sortType = _SortType.name; _cachedSortedWorkers = null; }),
              ),
            ],
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 10)),

          // 컬럼 라벨
          Padding(
            padding: EdgeInsets.symmetric(
                horizontal: ResponsiveHelper.spacing(context, 2)),
            child: Row(
              children: [
                SizedBox(width: ResponsiveHelper.spacing(context, 80)),
                SizedBox(
                  width: ResponsiveHelper.spacing(context, 36),
                  child: Text('근무일',
                      textAlign: TextAlign.center,
                      style: ResponsiveHelper.tinyStyle(context,
                          color: AppColors.grey500)),
                ),
                Expanded(
                  child: Text('출결 현황',
                      textAlign: TextAlign.center,
                      style: ResponsiveHelper.tinyStyle(context,
                          color: AppColors.grey500)),
                ),
                SizedBox(
                  width: ResponsiveHelper.spacing(context, 72),
                  child: Text('임금',
                      textAlign: TextAlign.right,
                      style: ResponsiveHelper.tinyStyle(context,
                          color: AppColors.grey500)),
                ),
              ],
            ),
          ),

          const Divider(height: 8),

          ...workers.map((w) => _WorkerRow(worker: w)),
        ],
      ),
    );
  }

  // ─── 유틸 ─────────────────────────────────────────────────

  BoxDecoration _cardDecoration() => BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      );

  String _fmtWageFull(int wage) {
    if (wage == 0) return '-';
    final s = wage.toString();
    final buf = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
      buf.write(s[i]);
    }
    return '$buf원';
  }

  List<MapEntry<String, int>> _topTags(Map<String, int> freq, int n) {
    final entries = freq.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return entries.take(n).toList();
  }
}

// ─── 서브 위젯 ────────────────────────────────────────────────

class _AttStat extends StatelessWidget {
  final Color color;
  final String label;
  final int count;
  final int total;
  const _AttStat(
      {required this.color,
      required this.label,
      required this.count,
      required this.total});

  @override
  Widget build(BuildContext context) {
    final pct = total == 0 ? 0.0 : count / total * 100;
    return Padding(
      padding:
          EdgeInsets.only(right: ResponsiveHelper.spacing(context, 14)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          SizedBox(width: ResponsiveHelper.spacing(context, 4)),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$count건',
                style: ResponsiveHelper.smallStyle(context)
                    .copyWith(fontWeight: FontWeight.bold),
              ),
              Text(
                '$label ${pct.toStringAsFixed(0)}%',
                style: ResponsiveHelper.tinyStyle(context,
                    color: AppColors.grey500),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _WorkerRow extends StatelessWidget {
  final WorkerMonthSummary worker;
  const _WorkerRow({required this.worker});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(
          vertical: ResponsiveHelper.spacing(context, 7)),
      child: Row(
        children: [
          // 이름 (80dp 고정)
          SizedBox(
            width: ResponsiveHelper.spacing(context, 80),
            child: Text(worker.userName,
                style: ResponsiveHelper.smallStyle(context)
                    .copyWith(fontWeight: FontWeight.w500),
                overflow: TextOverflow.ellipsis),
          ),
          // 근무일
          SizedBox(
            width: ResponsiveHelper.spacing(context, 36),
            child: Text('${worker.totalDays}일',
                textAlign: TextAlign.center,
                style: ResponsiveHelper.smallStyle(context,
                    color: AppColors.grey600)),
          ),
          // 상태 — 지각/결근 있을 때만 뱃지, 정상이면 초록 점
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (worker.lateDays > 0)
                  _StatusBadge('지각 ${worker.lateDays}', AppColors.warning),
                if (worker.absentDays > 0) ...[
                  if (worker.lateDays > 0)
                    SizedBox(width: ResponsiveHelper.spacing(context, 4)),
                  _StatusBadge('결근 ${worker.absentDays}', AppColors.error),
                ],
                if (worker.lateDays == 0 && worker.absentDays == 0)
                  Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(
                          color: AppColors.success,
                          shape: BoxShape.circle)),
              ],
            ),
          ),
          // 임금
          SizedBox(
            width: ResponsiveHelper.spacing(context, 72),
            child: worker.totalWage > 0
                ? Text(_fmtWage(worker.totalWage),
                    textAlign: TextAlign.right,
                    style: ResponsiveHelper.smallStyle(context)
                        .copyWith(fontWeight: FontWeight.w700))
                : Text('미확정',
                    textAlign: TextAlign.right,
                    style: ResponsiveHelper.tinyStyle(context,
                        color: AppColors.grey400)),
          ),
        ],
      ),
    );
  }

  String _fmtWage(int w) {
    if (w == 0) return '-';
    if (w >= 10000000) return '${(w / 10000000).toStringAsFixed(1)}천만';
    if (w >= 10000) return '${(w / 10000).toStringAsFixed(0)}만';
    return '${w ~/ 1000}천';
  }
}

class _StatusBadge extends StatelessWidget {
  final String label;
  final Color color;
  const _StatusBadge(this.label, this.color);

  @override
  Widget build(BuildContext context) => Container(
        padding: EdgeInsets.symmetric(
          horizontal: ResponsiveHelper.spacing(context, 6),
          vertical: ResponsiveHelper.spacing(context, 2),
        ),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(label,
            style: ResponsiveHelper.tinyStyle(context,
                color: color, fontWeight: FontWeight.w600)),
      );
}

class _SortChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _SortChip(
      {required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: ResponsiveHelper.spacing(context, 8),
          vertical: 3,
        ),
        decoration: BoxDecoration(
          color: selected
              ? theme.primaryColor.withValues(alpha: 0.12)
              : AppColors.grey100,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          label,
          style: ResponsiveHelper.tinyStyle(context).copyWith(
            color: selected ? theme.primaryColor : AppColors.grey600,
            fontWeight: selected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}

