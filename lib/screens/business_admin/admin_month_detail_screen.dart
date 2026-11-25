import 'dart:io';

import 'package:excel/excel.dart' hide Border;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../models/core/attendance_model.dart';
import '../../providers/user_provider.dart';
import '../../services/admin_stats_service.dart';
import '../../theme/app_colors.dart';
import '../../utils/person_label.dart';
import '../../utils/format_helper.dart';
import '../../utils/responsive_helper.dart';
import '../../utils/toast_helper.dart';
import '../../screens/common/notification_screen.dart';
import '../../utils/navigation_helper.dart';
import '../../widgets/common/app_empty_state.dart';
import '../../widgets/common/app_page_scaffold.dart';
import '../../widgets/common/loading_widget.dart';
import '../../widgets/common/notification_badge.dart';
import 'admin_stats_access.dart';
import 'stats_attendance_list_screen.dart';
import '../../utils/text_layout.dart';
import '../../widgets/common/count_chip.dart';

class AdminMonthDetailScreen extends StatefulWidget {
  final List<String> businessIds;
  final String? filterBusinessId;
  final int year;
  final int month;
  final List<BusinessOption> businesses;

  /// [R7-P1-7 후속 P17-S] 통계 reader 주입점 — production 은 null.
  final AdminStatsService? service;

  /// [STATS-TO-ATTENDANCE.27] 시험 주입점 — 내역 목록이 근태 화면 대신 부른다. production 은 null.
  final Future<bool?> Function(AttendanceModel r)? debugOpenAttendance;

  /// [STATS-TO-ATTENDANCE.27] 이 화면 아래(내역 → 근태 화면)에서 정정이 성공하면 부른다 — 연간 화면 갱신용.
  final VoidCallback? onCorrected;

  const AdminMonthDetailScreen({
    super.key,
    required this.businessIds,
    required this.filterBusinessId,
    required this.year,
    required this.month,
    required this.businesses,
    this.service,
    this.debugOpenAttendance,
    this.onCorrected,
  });

  @override
  State<AdminMonthDetailScreen> createState() => _AdminMonthDetailScreenState();
}

enum _SortType { days, wage, name }

class _AdminMonthDetailScreenState extends State<AdminMonthDetailScreen> {
  late final AdminStatsService _service = widget.service ?? AdminStatsService();

  bool _isLoading = true;
  bool _fetchInProgress = false;
  bool _isExporting = false;
  bool _hasError = false;
  /// [ADMIN-STATS-CLOSEOUT] 이 화면 조회 대상의 급여 권한(불러오기·내보내기 직전마다 다시 본다).
  PermissionCheck _access = PermissionCheck.allowed;

  List<String> get _scopeIds =>
      widget.filterBusinessId != null ? [widget.filterBusinessId!] : widget.businessIds;
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

  /// [quiet] 내역에서 정정하고 돌아온 갱신 — 화면을 로딩으로 바꾸지 않아 정렬·스크롤이 그대로다.
  ///   실패하면 이전 숫자를 지우지도 0 으로 바꾸지도 않고, 정정 전 기준이라고 말한다.
  Future<void> _loadData({bool quiet = false}) async {
    if (_fetchInProgress) return;
    _fetchInProgress = true;
    // [ADMIN-STATS-CLOSEOUT] 열린 화면에서 권한이 사라졌으면 다시 부르지 않고 이전 숫자도 지운다.
    final access = AdminStatsAccess.check(context.read<UserProvider>(), _scopeIds);
    if (access != PermissionCheck.allowed) {
      _fetchInProgress = false;
      setState(() { _access = access; _data = null; _cachedSortedWorkers = null; _hasError = false; _isLoading = false; _staleAfterChange = false; });
      return;
    }
    final keepOld = quiet && _data != null;
    setState(() { _access = PermissionCheck.allowed; if (!keepOld) _isLoading = true; _hasError = false; });
    try {
      final data = await _service.getMonthDetail(
        businessIds: widget.businessIds,
        filterBusinessId: widget.filterBusinessId,
        year: widget.year,
        month: widget.month,
      );
      if (!mounted) return;
      // 근태 조회만 실패한 응답(unavailable)도 갱신 실패다 — 정정 전 숫자를 '확인 불가'로 덮지 않는다.
      if (keepOld && data.attendanceStatsState != AttendanceStatsState.available) {
        setState(() => _staleAfterChange = true);
      } else {
        setState(() { _data = data; _cachedSortedWorkers = null; _staleAfterChange = false; });
      }
    } catch (e) {
      debugPrint('❌ 월 상세 로드 실패: $e');
      if (mounted) setState(() { if (keepOld) { _staleAfterChange = true; } else { _hasError = true; } });
    } finally {
      _fetchInProgress = false;
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ─── [STATS-TO-ATTENDANCE.27] 숫자 → 그 근무들 ──────────────────────

  /// 정정 뒤 다시 읽기에 실패했다 — 아래 숫자는 정정 전 기준이다.
  bool _staleAfterChange = false;

  String get _scopeLabel {
    final bizName = widget.filterBusinessId != null
        ? widget.businesses
            .where((b) => b.id == widget.filterBusinessId)
            .map((b) => b.name)
            .firstOrNull
        : (widget.businesses.length == 1 ? widget.businesses.first.name : '전체 사업장');
    return '${widget.year}년 ${widget.month}월${bizName != null ? ' · $bizName' : ''}';
  }

  static const _bucketTitles = {
    StatsAttendanceBucket.present: '정상 출근 내역',
    StatsAttendanceBucket.late: '지각 내역',
    StatsAttendanceBucket.missedCheckout: '퇴근 미확인 내역',
    StatsAttendanceBucket.unconfirmed: '근태 확인 필요 내역',
    StatsAttendanceBucket.absent: '결근 내역',
  };

  Future<void> _openList({
    required String title,
    required String scope,
    required bool Function(AttendanceModel r) matches,
    bool resultOnly = false,
  }) async {
    final data = _data;
    if (data == null) return;
    var corrected = false;
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => StatsAttendanceListScreen(
          onCorrected: () {
            corrected = true;
            widget.onCorrected?.call();
          },
          title: title,
          scopeLabel: scope,
          // 이미 받은 이 달 원본 — 첫 목록에서 다시 읽지 않는다.
          initial: StatsAttendanceSnapshot(
              records: data.rawAttendance, userInfo: data.userInfoMap),
          load: () => _service.getAttendanceSnapshot(
            businessIds: widget.businessIds,
            filterBusinessId: widget.filterBusinessId,
            year: widget.year,
            month: widget.month,
          ),
          matches: matches,
          resultOnly: resultOnly,
          debugOpenAttendance: widget.debugOpenAttendance,
        ),
      ),
    );
    if (!mounted || !corrected) return; // 취소·변경 없음 — 다시 읽지 않는다.
    await _loadData(quiet: true);
  }

  void _openBucket(StatsAttendanceBucket b) => _openList(
        title: _bucketTitles[b]!,
        scope: _scopeLabel,
        matches: (r) => AdminStatsService.bucketOf(r) == b,
        resultOnly: b == StatsAttendanceBucket.absent,
      );

  String _who(WorkerMonthSummary w) =>
      w.personNo != null ? '${w.userName} · ${w.personNo}' : w.userName;

  void _openWorker(WorkerMonthSummary w, [StatsAttendanceBucket? b]) => _openList(
        title: b == null ? '근태 내역' : _bucketTitles[b]!,
        scope: '$_scopeLabel · ${_who(w)}',
        matches: (r) =>
            r.userId == w.userId &&
            (b == null || AdminStatsService.bucketOf(r) == b),
        resultOnly: b == StatsAttendanceBucket.absent,
      );

  // ─── Excel 내보내기 ──────────────────────────────────────────

  // [R7-PRE1A.1] 근로자번호를 넣고 성별·연락처를 뺀다.
  //
  //   이 파일의 목적은 **월 근태 기록**이다. 사람을 구분할 수단이 이름뿐이라
  //   연락처가 사실상 식별자로 쓰이고 있었는데, 그건 PII 를 identity 로 쓰는
  //   모양이다. 번호가 그 일을 대신하면 연락처는 이 파일에 있을 이유가 없다.
  //
  //   당일명단 PDF 의 연락처는 남긴다 — 그쪽은 현장에서 사람에게 전화하려고
  //   들고 다니는 문서다. 목적이 다른 파일을 같은 PII 정책으로 묶지 않는다.
  static final _excelHeaders = [
    PersonLabel.fieldLabel, '사업장명', '근무일자', '파트', '근로자명',
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
        final n = (infoMap[a.userId]?.name ?? '').compareTo(
            infoMap[b.userId]?.name ?? '');
        if (n != 0) return n;
        // [R7-PRE1A.1] 같은 이름·같은 날이면 여기서 순서가 정해지지 않았다.
        //   같은 파일을 두 번 내보내면 행 순서가 달라져 비교할 수 없고,
        //   동명이인이면 어느 줄이 누구인지도 매번 바뀐다.
        //   번호 → 근태 문서 id 순으로 못을 박는다.
        final p = (infoMap[a.userId]?.personNo ?? '').compareTo(
            infoMap[b.userId]?.personNo ?? '');
        if (p != 0) return p;
        return a.id.compareTo(b.id);
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
        info?.personNo ?? '',
        r.businessName,
        dateStr,
        r.workType,
        info?.name ?? '알 수 없음',
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
    // [ADMIN-STATS-CLOSEOUT] 내보내기 직전에도 권한을 다시 본다 — 화면이 열린 사이 권한이 사라졌으면 파일을 만들지 않는다.
    final access = AdminStatsAccess.check(context.read<UserProvider>(), _scopeIds);
    if (access != PermissionCheck.allowed) {
      setState(() { _access = access; _data = null; _cachedSortedWorkers = null; });
      ToastHelper.showWarning(AdminStatsAccess.title(access));
      return;
    }
    setState(() => _isExporting = true);
    try {
      final excel = Excel.createExcel();
      excel.delete('Sheet1');

      // 사업장별로 레코드 분류
      final bizGroups = <String, List<AttendanceModel>>{};
      for (final r in data.rawAttendance) {
        bizGroups.putIfAbsent(r.businessName, () => []).add(r);
      }

      // [R7-PRE1A.1] 시트 이름은 사업장명에서 온다. Excel 은 31자를 넘거나
      //   : \ / ? * [ ] 가 들어가면 파일을 거부하거나 시트를 조용히 버린다 —
      //   내보내기는 성공한 것처럼 보이면서. 사업장명은 사용자 입력이다.
      //   이름을 고치는 것이 아니라 **시트 이름만** 안전하게 만든다.
      //   같은 이름으로 줄어든 시트가 겹치지 않게 뒤에 번호를 붙인다.
      final usedSheetNames = <String>{};
      String sheetNameFor(String raw) {
        var name = PersonLabel.safeSheetName(raw);
        if (!usedSheetNames.add(name)) {
          for (var i = 2;; i++) {
            final base = name.length > 27 ? name.substring(0, 27) : name;
            final alt = '$base($i)';
            if (usedSheetNames.add(alt)) { name = alt; break; }
          }
        }
        return name;
      }

      if (bizGroups.length <= 1) {
        // 단일 사업장(또는 필터 적용) — 시트 하나
        final sheet = excel[sheetNameFor(bizGroups.keys.firstOrNull ?? '근태현황')];
        _writeHeaderRow(sheet);
        _writeAttendanceRows(sheet, data.rawAttendance, data.userInfoMap, 1);
      } else {
        // 복수 사업장 — 사업장별 시트 + 전체 시트
        final allSheet = excel[sheetNameFor('전체')];
        _writeHeaderRow(allSheet);
        int allRow = 1;
        for (final entry in bizGroups.entries) {
          final bizSheet = excel[sheetNameFor(entry.key)];
          _writeHeaderRow(bizSheet);
          _writeAttendanceRows(bizSheet, entry.value, data.userInfoMap, 1);
          allRow = _writeAttendanceRows(
              allSheet, entry.value, data.userInfoMap, allRow);
        }
        excel.setDefaultSheet(sheetNameFor('전체'));
      }

      // 파일 저장 + 공유
      // [R7-PRE1A.1] 파일명에 사업장을 넣는다. 여러 사업장을 차례로 내보내면
      //   받는 쪽에서 같은 이름의 파일이 겹쳐 하나가 덮인다.
      final dir = await getTemporaryDirectory();
      final bizPart = bizGroups.length == 1
          ? '${PersonLabel.safeFileName(bizGroups.keys.first)}_'
          : '';
      final fileName = '$bizPart근태현황_${widget.year}년${widget.month}월.xlsx';
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

  String? get _bizNameForTitle => widget.filterBusinessId != null
      ? widget.businesses
          .where((b) => b.id == widget.filterBusinessId)
          .map((b) => b.name)
          .firstOrNull
      : (widget.businesses.length == 1 ? widget.businesses.first.name : null);

  @override
  Widget build(BuildContext context) {
    // [DESIGN-PATCH-2] GradientScaffold → AppPageScaffold — 관리자 정산 화면 flat admin 정렬
    // onRefresh 자동 버튼 제거 → AppBar refresh action + body RefreshIndicator 유지
    return AppPageScaffold(
      // [STATS-TO-ATTENDANCE.27] 사업장명까지 제목에 넣어 '2026년 10…' 로 잘렸다 — 제목은 기간만,
      //   사업장은 본문 첫 줄에 둔다(글자를 줄이지 않고 다 보인다).
      title: '${widget.month}월',
      actions: [
        // [STATS-TO-ATTENDANCE.27-T1] 320dp 에서는 아이콘 넷이 폭을 다 써 제목 '10월' 도 '1…' 로 잘렸다 —
        //   좁은 폭에서는 새로고침 아이콘을 내린다(당겨서 새로고침·오류의 '다시 시도' 가 같은 일을 한다).
        if (MediaQuery.sizeOf(context).width >= 360)
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
                    _access != PermissionCheck.allowed ||
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
    if (_access != PermissionCheck.allowed) {
      return AppEmptyState(
        icon: Icons.lock_outline,
        title: AdminStatsAccess.title(_access),
        subtitle: AdminStatsAccess.subtitle(_access),
      );
    }
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
        // [DU426] 이 화면 글자는 읽히는 짝으로 — 보조 글자 textSecondary · 낮은 강조 textTertiary · 상태 글자 진한 짝(errorDark · successDark).
        //   별 · 점 · 막대 · 아이콘(채움)은 기본색 그대로다. 문구 · 분류 · 행동 · 데이터는 그대로다.
        ...[
          Text(_bizNameForTitle != null
                  ? '${widget.year}년 ${widget.month}월 · ${_bizNameForTitle!}'
                  : '${widget.year}년 ${widget.month}월',
              style: ResponsiveHelper.smallStyle(context, color: AppColors.textSecondary)
                  .copyWith(fontWeight: FontWeight.w600)),
          SizedBox(height: ResponsiveHelper.spacing(context, 8)),
        ],
        // [STATS-TO-ATTENDANCE.27] 정정 뒤 다시 읽기 실패 — 이전 숫자를 최신이라 하지 않는다.
        if (_staleAfterChange) ...[
          Container(
            padding: EdgeInsets.symmetric(
                horizontal: ResponsiveHelper.spacing(context, 12),
                vertical: ResponsiveHelper.spacing(context, 8)),
            // [DU579] 정정 전 숫자 띠 = 흰 면 + 기존 선(grey200) + warningDark 글(판정141 R1 (b) · 연간 통계 · 근태 내역 띠와 같은 짝) · 문구 · 다시 조회 그대로.
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.grey200),
            ),
            child: Row(children: [
              Expanded(
                child: Text('최신 집계를 불러오지 못했어요. 아래 숫자는 정정 전 기준이에요.',
                    style: ResponsiveHelper.smallStyle(context, color: AppColors.warningDark)),
              ),
              TextButton(
                onPressed: () => _loadData(quiet: true),
                child: const Text('다시 조회'),
              ),
            ]),
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 10)),
        ],
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
                  color: AppColors.errorDark),
            ),
          ],
        ),
      );
    }

    final total = data.totalAttendanceCount;
    final presRatio = total == 0 ? 0.0 : data.presentCount / total;
    final lateRatio = total == 0 ? 0.0 : data.lateCount / total;
    final absRatio = total == 0 ? 0.0 : data.absentCount / total;
    final missRatio = total == 0 ? 0.0 : data.missedCheckoutCount / total;
    // [UNKNOWN-ATTENDANCE] status 를 확인할 수 없는 건 — 결근 칸에 넣지 않고 전체에서도 빼지 않는다.
    final unconfRatio = total == 0 ? 0.0 : data.unconfirmedCount / total;

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
                  if (missRatio > 0)
                    Expanded(
                      flex: (missRatio * 1000).round(),
                      child: Container(color: AppColors.grey400),
                    ),
                  if (unconfRatio > 0)
                    Expanded(
                      flex: (unconfRatio * 1000).round(),
                      child: Container(color: AppColors.purple),
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
          // [R7-P1-7 후속 P17-S] 칩 3개와 금액 묶음이 flex 없이 한 줄에 있었다 —
          //   좁은 폭·큰 글자에서 가로로 넘쳐 금액이 잘렸다. 프로젝트 규칙대로
          //   줄바꿈을 허용한다(수치를 숨기거나 글자를 줄이지 않는다).
          Wrap(
            spacing: ResponsiveHelper.spacing(context, 12),
            runSpacing: ResponsiveHelper.spacing(context, 8),
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _AttStat(
                key: const ValueKey('att-stat-present'),
                color: AppColors.success,
                label: '정상',
                count: data.presentCount,
                total: total,
                onTap: () => _openBucket(StatsAttendanceBucket.present),
              ),
              if (data.lateCount > 0)
                _AttStat(
                  key: const ValueKey('att-stat-late'),
                  color: AppColors.warning,
                  label: '지각',
                  count: data.lateCount,
                  total: total,
                  onTap: () => _openBucket(StatsAttendanceBucket.late),
                ),
              // [ADMIN-MONTHLY-1] 출근 기록은 있고 퇴근이 확인되지 않은 건 — 결근이 아니다.
              if (data.missedCheckoutCount > 0)
                _AttStat(
                  key: const ValueKey('att-stat-missedCheckout'),
                  color: AppColors.grey400,
                  label: '퇴근 미확인',
                  count: data.missedCheckoutCount,
                  total: total,
                  onTap: () => _openBucket(StatsAttendanceBucket.missedCheckout),
                ),
              if (data.unconfirmedCount > 0)
                _AttStat(
                  key: const ValueKey('att-stat-unconfirmed'),
                  color: AppColors.purple,
                  label: '근태 확인 필요',
                  count: data.unconfirmedCount,
                  total: total,
                  onTap: () => _openBucket(StatsAttendanceBucket.unconfirmed),
                ),
              if (data.absentCount > 0)
                _AttStat(
                  key: const ValueKey('att-stat-absent'),
                  color: AppColors.error,
                  label: '결근',
                  count: data.absentCount,
                  total: total,
                  onTap: () => _openBucket(StatsAttendanceBucket.absent),
                ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    // [ADMIN-STATS-CLOSEOUT] 확정 근무가 있는데 합이 0원이면 '0원' — '-' 는 확정 근무가 없을 때만.
                    data.totalWage == 0 && data.settledCount > 0
                        ? '0원'
                        : _fmtWageFull(data.totalWage),
                    style: ResponsiveHelper.bodyStyle(context)
                        .copyWith(fontWeight: FontWeight.bold),
                  ),
                  Text('총 인건비',
                      style: ResponsiveHelper.tinyStyle(context,
                          color: AppColors.textSecondary)),
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
                          color: AppColors.textPrimary,
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
                        color: AppColors.successDark,
                        fontWeight: FontWeight.w600),
                  ),
                  SizedBox(width: ResponsiveHelper.spacing(context, 4)),
                  Text(
                    '(${data.rehireCount + data.noRehireCount}건)',
                    style: ResponsiveHelper.tinyStyle(context,
                        color: AppColors.textTertiary),
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
                  color: AppColors.textSecondary),
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
                  color: AppColors.textSecondary),
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
          // [R7-P1-7 후속 P17-S] 제목과 정렬 칩 3개가 flex 없이 서 있었다 —
          //   좁은 폭에서 칩이 잘려 정렬을 바꿀 수 없었다. 제목부터 줄인다.
          // [STATS-TO-ATTENDANCE.27] 제목과 정렬 칩이 한 줄을 나눠 제목이 '직원별 요…' 로 잘렸다 —
          //   제목은 제 줄을 갖고, 정렬은 다음 줄에 둔다.
          Text(
            '직원별 요약 (${workers.length}명)',
            style: ResponsiveHelper.bodyStyle(context)
                .copyWith(fontWeight: FontWeight.bold),
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 8)),
          Wrap(
            spacing: ResponsiveHelper.spacing(context, 4),
            runSpacing: ResponsiveHelper.spacing(context, 4),
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text('정렬',
                  style: ResponsiveHelper.tinyStyle(context, color: AppColors.textSecondary)),
              _SortChip(
                label: '근무일',
                selected: _sortType == _SortType.days,
                onTap: () => setState(() { _sortType = _SortType.days; _cachedSortedWorkers = null; }),
              ),
              _SortChip(
                label: '임금',
                selected: _sortType == _SortType.wage,
                onTap: () => setState(() { _sortType = _SortType.wage; _cachedSortedWorkers = null; }),
              ),
              _SortChip(
                label: '이름',
                selected: _sortType == _SortType.name,
                onTap: () => setState(() { _sortType = _SortType.name; _cachedSortedWorkers = null; }),
              ),
            ],
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 10)),

          // [STATS-TO-ATTENDANCE.27-T1] 표는 **가용 폭과 글자 배율로** 고른다.
          //   열 폭은 spacing() 이라 360dp 미만에서 85% 로 줄지만 글자는 그대로라, 좁은 화면에서
          //   '합성 다 / 건'·'근무 / 일' 로 음절이 갈렸다. 글자를 줄이지 않고, 표가 들어가지 않으면
          //   한 사람을 몇 줄로 쌓는다. 글자 배율을 곱하므로 큰 글자에서는 더 일찍 쌓는다.
          //   폭은 이 영역에서 **한 번만** 잰다(행마다 재지 않는다).
          LayoutBuilder(builder: (context, c) {
            final ts = MediaQuery.textScalerOf(context).scale(13) / 13;
            final asTable = TextLayout.fits(context, c.maxWidth, _WorkerRow.tableMinWidth);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (asTable) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: Row(
                      children: [
                        SizedBox(width: _WorkerRow.nameWidth * ts),
                        SizedBox(
                          width: _WorkerRow.daysWidth * ts,
                          child: Text('근무일',
                              textAlign: TextAlign.center,
                              softWrap: false,
                              style: ResponsiveHelper.tinyStyle(context,
                                  color: AppColors.textSecondary)),
                        ),
                        Expanded(
                          child: Text('출결 현황',
                              textAlign: TextAlign.center,
                              softWrap: false,
                              style: ResponsiveHelper.tinyStyle(context,
                                  color: AppColors.textSecondary)),
                        ),
                        SizedBox(
                          width: _WorkerRow.wageWidth * ts,
                          child: Text('임금',
                              textAlign: TextAlign.right,
                              softWrap: false,
                              style: ResponsiveHelper.tinyStyle(context,
                                  color: AppColors.textSecondary)),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 8),
                ] else
                  const Divider(height: 8),
                ...workers.map((w) => _WorkerRow(
                      worker: w,
                      asTable: asTable,
                      textScale: ts,
                      onOpen: () => _openWorker(w),
                      onOpenBucket: (b) => _openWorker(w, b),
                    )),
              ],
            );
          }),
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
  /// [STATS-TO-ATTENDANCE.27] 이 칸의 근무 내역을 연다. 0건이면 열 것이 없다.
  final VoidCallback? onTap;
  const _AttStat(
      {super.key,
      required this.color,
      required this.label,
      required this.count,
      required this.total,
      this.onTap});

  @override
  Widget build(BuildContext context) {
    final pct = total == 0 ? 0.0 : count / total * 100;
    final tap = count > 0 ? onTap : null;
    return InkWell(
      onTap: tap,
      borderRadius: BorderRadius.circular(8),
      child: ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 44),
      child: Padding(
      padding: EdgeInsets.only(
          right: ResponsiveHelper.spacing(context, 10),
          top: ResponsiveHelper.spacing(context, 2),
          bottom: ResponsiveHelper.spacing(context, 2)),
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
                    color: AppColors.textSecondary),
              ),
            ],
          ),
          if (tap != null)
            Icon(Icons.chevron_right,
                size: ResponsiveHelper.iconSize(context, 16),
                color: AppColors.grey400),
        ],
      ),
      ),
      ),
    );
  }
}

class _WorkerRow extends StatelessWidget {
  final WorkerMonthSummary worker;
  /// [STATS-TO-ATTENDANCE.27-T1] 표(넓을 때) / 쌓은 행(좁거나 글자가 클 때). 위에서 한 번 정한다.
  final bool asTable;
  final double textScale;
  /// [STATS-TO-ATTENDANCE.27] 행 = 그 직원의 이 달 전체 근태 내역, 배지 = 그 상태만.
  final VoidCallback onOpen;
  final void Function(StatsAttendanceBucket b) onOpenBucket;
  const _WorkerRow({
    required this.worker,
    required this.asTable,
    required this.textScale,
    required this.onOpen,
    required this.onOpenBucket,
  });

  /// 표의 열 폭(글자 배율 1.0 기준, 논리 px) — 글자 배율을 곱해 쓴다.
  static const double nameWidth = 84;
  static const double daysWidth = 44;
  static const double wageWidth = 72;
  /// 상태 칩 칸이 칩 하나('퇴근미확인 3 ›')를 줄바꿈 없이 담을 폭.
  static const double chipsMinWidth = 104;
  static const double tableMinWidth = nameWidth + daysWidth + wageWidth + chipsMinWidth;

  Widget _badge(String label, Color color, Color bg, StatsAttendanceBucket b) => CountChip(
        key: ValueKey('worker-badge-${worker.userId}-${b.name}'),
        label: label,
        color: color,
        background: bg,
        onTap: () => onOpenBucket(b),
      );

  bool get _clean =>
      worker.lateDays == 0 &&
      worker.absentDays == 0 &&
      worker.missedCheckoutDays == 0 &&
      worker.unconfirmedDays == 0;

  // [DU426] 배지 글자는 근태 목록 칩과 같은 진한 짝이다(지각 warningDark · 퇴근미확인 textSecondary · 확인필요 purple · 결근 errorDark).
  //   위 막대 · 범례 점(채움)은 기본색 그대로다 — 글자 = 진한 짝, 채움 = 기본색.
  // [DU427] 배지 바탕도 목록 칩과 같은 앱 기준 Bg 토큰이다(warningBg · grey200 · purpleBg · errorBg). 같은 색 12% 는 지각 4.46:1 이었다.
  List<Widget> _chips() => [
        if (worker.lateDays > 0)
          _badge('지각 ${worker.lateDays}', AppColors.warningDark, AppColors.warningBg, StatsAttendanceBucket.late),
        if (worker.missedCheckoutDays > 0)
          _badge('퇴근미확인 ${worker.missedCheckoutDays}', AppColors.textSecondary, AppColors.grey200,
              StatsAttendanceBucket.missedCheckout),
        if (worker.unconfirmedDays > 0)
          _badge('확인필요 ${worker.unconfirmedDays}', AppColors.purple, AppColors.purpleBg,
              StatsAttendanceBucket.unconfirmed),
        if (worker.absentDays > 0)
          _badge('결근 ${worker.absentDays}', AppColors.errorDark, AppColors.errorBg, StatsAttendanceBucket.absent),
      ];

  // 이름은 식별 정보 — 줄이지 않고, 낱말 사이에서 자연스럽게 두 줄까지.
  // [.29] 이름은 식별 정보 — 줄 수 제한·말줄임 없이 다 보인다(무공백 긴 이름은 가운데·필요하면 강제 줄바꿈).
  Widget _name(BuildContext context) => Text(TextLayout.identity(worker.userName),
      semanticsLabel: worker.userName,
      style: ResponsiveHelper.smallStyle(context).copyWith(fontWeight: FontWeight.w500));

  Widget? _personNo(BuildContext context) => worker.personNo == null
      ? null
      : Text(worker.personNo!,
          softWrap: false,
          style: ResponsiveHelper.tinyStyle(context, color: AppColors.textSecondary));

  // [ADMIN-STATS-CLOSEOUT] 금액 0 을 '미확정'이라 하지 않는다 — 확정 근무가 있으면 '확정 · 0원'.
  Widget _wage(BuildContext context) => worker.totalWage > 0 || worker.hasSettledWage
      ? Text(worker.totalWage > 0 ? _fmtWage(worker.totalWage) : '확정 · 0원',
          textAlign: TextAlign.right,
          softWrap: false,
          style: ResponsiveHelper.smallStyle(context).copyWith(fontWeight: FontWeight.w700))
      : Text('미확정',
          textAlign: TextAlign.right,
          softWrap: false,
          style: ResponsiveHelper.tinyStyle(context, color: AppColors.textTertiary));

  @override
  Widget build(BuildContext context) {
    final pno = _personNo(context);
    return InkWell(
      key: ValueKey('worker-row-${worker.userId}'),
      onTap: onOpen,
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: ResponsiveHelper.spacing(context, 7)),
        child: asTable ? _tableRow(context, pno) : _stackedRow(context, pno),
      ),
    );
  }

  Widget _tableRow(BuildContext context, Widget? pno) => Row(
        children: [
          // [ADMIN-MONTHLY-1] 동명이인이 같은 줄 두 개로 보였다 — 인력번호를 이름 아래에.
          SizedBox(
            width: nameWidth * textScale,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [_name(context), if (pno != null) pno],
            ),
          ),
          SizedBox(
            width: daysWidth * textScale,
            child: Text('${worker.totalDays}일',
                textAlign: TextAlign.center,
                softWrap: false,
                style: ResponsiveHelper.smallStyle(context, color: AppColors.textSecondary)),
          ),
          Expanded(
            child: _clean
                ? Center(child: _okDot())
                : Wrap(
                    alignment: WrapAlignment.center,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 4,
                    runSpacing: 2,
                    children: _chips(),
                  ),
          ),
          SizedBox(width: wageWidth * textScale, child: _wage(context)),
        ],
      );

  /// 좁은 폭·큰 글자: 이름·번호 / 근무일·임금 / 상태 칩 — 각자 제 줄을 갖는다.
  Widget _stackedRow(BuildContext context, Widget? pno) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Wrap(
                  spacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [_name(context), if (pno != null) pno],
                ),
              ),
              const SizedBox(width: 8),
              _wage(context),
            ],
          ),
          const SizedBox(height: 2),
          Text('근무일 ${worker.totalDays}일',
              style: ResponsiveHelper.tinyStyle(context, color: AppColors.textSecondary)),
          if (!_clean) ...[
            const SizedBox(height: 4),
            Wrap(spacing: 4, runSpacing: 2, children: _chips()),
          ],
        ],
      );

  Widget _okDot() => Container(
      width: 6,
      height: 6,
      decoration: const BoxDecoration(color: AppColors.success, shape: BoxShape.circle));

  String _fmtWage(int w) {
    if (w == 0) return '-';
    if (w >= 10000000) return '${(w / 10000000).toStringAsFixed(1)}천만';
    if (w >= 10000) return '${(w / 10000).toStringAsFixed(0)}만';
    return '${w ~/ 1000}천';
  }
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
            color: selected ? theme.primaryColor : AppColors.textSecondary,
            fontWeight: selected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}

