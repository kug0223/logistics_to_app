// lib/screens/business_admin/dialogs/close_management_dialog.dart
// 마감관리 다이얼로그 - 월별 당일명단 마감 현황 조회 및 관리
//
// 주요 기능:
// - 월별 마감 현황 요약 (총 일수, 마감완료, 미마감)
// - 사업장별 날짜별 마감 상태 표시
// - 미마감 날짜 클릭 시 당일명단 다이얼로그 연결
// - 콜체인을 통한 실시간 상태 업데이트

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:intl/intl.dart';

// Models
import '../../../models/core/application_model.dart';
import '../../../models/core/attendance_model.dart';
import '../../../models/core/business_model.dart';

// Utils
import '../../../utils/loading_state_mixin.dart';
import '../../../utils/responsive_helper.dart';
import '../../../utils/format_helper.dart';
import '../../../theme/app_colors.dart';

// Widgets
import '../../../widgets/common/loading_widget.dart';
import '../../../widgets/dialogs/styled_dialog.dart';

// Dialogs
import 'attendance_status_dialog.dart';

/// 마감관리 다이얼로그
class CloseManagementDialog extends StatefulWidget {
  final DateTime initialMonth;
  final List<String> businessIds;
  final List<BusinessModel>? businesses;

  const CloseManagementDialog({
    super.key,
    required this.initialMonth,
    required this.businessIds,
    this.businesses,
  });

  @override
  State<CloseManagementDialog> createState() => _CloseManagementDialogState();
}

class _CloseManagementDialogState extends State<CloseManagementDialog>
    with LoadingStateMixin {
  // ─── 포맷터 캐싱 (build/itemBuilder마다 재생성 방지) ─────────
  static final _monthFmt  = DateFormat('yyyy년 M월');
  static final _dateFmtKo = DateFormat('M/d(E)', 'ko_KR');

  // ═══════════════════════════════════════════════════════════
  // 상태 변수
  // ═══════════════════════════════════════════════════════════

  late DateTime _currentMonth;
  bool _hasChanges = false;
  
  // 사업장 정보
  Map<String, String> _businessNameMap = {};
  
  // 마감 현황 데이터: businessId -> List<DateCloseStatus>
  Map<String, List<DateCloseStatus>> _closeStatusByBusiness = {};
  bool _hasClosed = false;
  
  // 요약 통계
  int _totalDays = 0;
  int _closedDays = 0;
  int _unclosedDays = 0;

  @override
  void initState() {
    super.initState();
    _currentMonth = DateTime(widget.initialMonth.year, widget.initialMonth.month, 1);
    if (widget.businesses != null) {
      _businessNameMap = {for (final b in widget.businesses!) b.id: b.name};
    }
    _loadData();
  }

  // ═══════════════════════════════════════════════════════════
  // 데이터 로드
  // ═══════════════════════════════════════════════════════════

  Future<void> _loadData() => runWithLoading(() async {
    // businesses가 생성자로 전달된 경우 _loadBusinessNames() 생략 (이미 initState에서 처리)
    await Future.wait([
      if (widget.businesses == null)
        _loadBusinessNames().catchError((Object e) {
          debugPrint('❌ [마감관리] 사업장 이름 로드 실패: $e');
        }),
      _loadCloseStatus(),
    ]);
    _calculateSummary();
  }, errorTag: '마감 현황 로드', errorMessage: '마감 현황을 불러오는데 실패했습니다');

  /// 사업장 이름 로드
  Future<void> _loadBusinessNames() async {
    final futures = widget.businessIds
        .map((id) => FirebaseFirestore.instance.collection('businesses').doc(id).get())
        .toList();
    final docs = await Future.wait(futures);
    final Map<String, String> nameMap = {};
    for (int i = 0; i < widget.businessIds.length; i++) {
      if (docs[i].exists) {
        nameMap[widget.businessIds[i]] = docs[i].data()?['name'] ?? '알 수 없음';
      }
    }
    _businessNameMap = nameMap;
  }

  /// 마감 현황 로드 — 사업장별 병렬 조회
  Future<void> _loadCloseStatus() async {
    // 해당 월의 시작/끝 날짜
    final monthStart = DateTime(_currentMonth.year, _currentMonth.month, 1);
    // [A06 수정] isLessThan 상한에는 다음 달 1일 자정을 사용해야 함.
    final monthEndExclusive = DateTime(_currentMonth.year, _currentMonth.month + 1, 1);
    final daysInMonth = DateTime(_currentMonth.year, _currentMonth.month + 1, 0).day;

    debugPrint('🔍 [마감관리] 조회 시작 ${DateFormat('yyyy-MM').format(_currentMonth)} '
        '| businessIds: ${widget.businessIds}');

    // [PERF] 사업장별 순차 루프 → Future.wait 병렬 처리
    final results = await Future.wait(
      widget.businessIds.map((businessId) => _loadCloseStatusForBusiness(
        businessId: businessId,
        monthStart: monthStart,
        monthEndExclusive: monthEndExclusive,
        daysInMonth: daysInMonth,
      )),
    );

    final Map<String, List<DateCloseStatus>> statusByBusiness = {};
    for (int i = 0; i < widget.businessIds.length; i++) {
      if (results[i].isNotEmpty) {
        statusByBusiness[widget.businessIds[i]] = results[i];
      }
    }
    _closeStatusByBusiness = statusByBusiness;
    _hasClosed = _closeStatusByBusiness.values
        .any((statuses) => statuses.any((s) => s.statusType == CloseStatusType.closed));
  }

  /// 사업장 1개의 마감 현황 계산
  Future<List<DateCloseStatus>> _loadCloseStatusForBusiness({
    required String businessId,
    required DateTime monthStart,
    required DateTime monthEndExclusive,
    required int daysInMonth,
  }) async {
    try {
      final List<DateCloseStatus> dateStatuses = [];

      // [CF 이전 2026-07-13] callableGetApplicationsByBiz — PERMISSION_DENIED 근본 해결
      final callable = FirebaseFunctions.instanceFor(region: 'asia-northeast3')
          .httpsCallable('callableGetApplicationsByBiz',
              options: HttpsCallableOptions(timeout: const Duration(seconds: 30)));

      // [PERF] 단기/장기 확정자 병렬 조회
      final callResults = await Future.wait([
        callable.call<Map<String, dynamic>>({
          'businessId': businessId,
          'workDateGteMs': monthStart.millisecondsSinceEpoch,
          'workDateLtMs': monthEndExclusive.millisecondsSinceEpoch,
          'limit': 2000,
        }),
        callable.call<Map<String, dynamic>>({
          'businessId': businessId,
          'type': AppType.longTerm,
          'limit': 2000,
        }),
      ]);
      final shortTermResult = callResults[0];
      final longTermResult  = callResults[1];

      // 1. 단기 확정자: 해당 월의 workDate 범위로 조회
      debugPrint('  [단기] businessId=$businessId → ${(shortTermResult.data['applications'] as List? ?? []).length}건');

      final Map<String, List<ApplicationModel>> appsByDate = {};
      for (final e in (shortTermResult.data['applications'] as List? ?? [])) {
        final m = Map<String, dynamic>.from(e as Map);
        final docId = m.remove('id') as String? ?? '';
        final app = ApplicationModel.tryFromMap(m, docId);
        if (app == null) continue;
        if (!AppStatus.confirmedStatuses.contains(app.status)) continue;
        debugPrint('    단기 app: id=${app.id}, workDate=${app.workDate}, '
            'workDays=${app.workDays}, status=${app.status}');
        if (app.workDays == null || app.workDays!.isEmpty) {
          final dateKey = DateFormat('yyyy-MM-dd').format(app.workDate);
          appsByDate.putIfAbsent(dateKey, () => []);
          appsByDate[dateKey]!.add(app);
        } else {
          debugPrint('    → workDays 있음 → 장기 처리로 건너뜀');
        }
      }

      // 2. 장기 확정자: 전체 조회 후 해당 월의 활성 날짜로 확장
      debugPrint('  [장기 전체] businessId=$businessId → ${(longTermResult.data['applications'] as List? ?? []).length}건');

      for (final e in (longTermResult.data['applications'] as List? ?? [])) {
        final m = Map<String, dynamic>.from(e as Map);
        final docId = m.remove('id') as String? ?? '';
        final app = ApplicationModel.tryFromMap(m, docId);
        if (app == null) continue;
        if (!AppStatus.confirmedStatuses.contains(app.status)) continue;
        if (app.workDays == null || app.workDays!.isEmpty) continue;
        debugPrint('    장기 app: id=${app.id}, workDate=${app.workDate}, workDays=${app.workDays}');

        final endDate = app.actualResignDate ?? app.workEndDate;
        // [E01 Bug 수정] 종료일 없는 오픈엔드 장기 근로자도 포함해야 한다.
        // attendance_status_dialog.dart의 _getConfirmedWorkersForDate()와 동일한 로직:
        //   - 퇴사 승인 완료(isTerminationApproved) 근무자만 제외
        //   - 그 외는 시작일 이후 날짜 전체를 활성으로 간주
        // 두 화면 사이 불일치가 있으면 당일명단에는 표시되지만 마감관리에서 누락되는 버그 발생.
        if (endDate == null && app.isTerminationApproved) continue;
        final effectiveStartDate = app.desiredStartDate ?? app.workDate;
        final startDateOnly = FormatHelper.toKstDate(effectiveStartDate);

        for (int d = 1; d <= daysInMonth; d++) {
          final date = DateTime(_currentMonth.year, _currentMonth.month, d);
          if (date.isBefore(startDateOnly)) continue;
          // 종료일이 있는 경우에만 종료일 이후 날짜 skip
          if (endDate != null) {
            final endDateOnly = FormatHelper.toKstDate(endDate);
            if (date.isAfter(endDateOnly)) continue;
          }
          // 휴무일 체크
          if (app.isLeaveDateOn(date)) continue;
          // [B-6] extraWorkDates 우선 처리 — attendance_status_dialog._getConfirmedWorkersForDate()와 동일 우선순위
          // 비근무 요일에 승인된 추가 근무일이면 workDays 체크 건너뛰고 바로 포함 (당일명단 vs 마감관리 불일치 방지)
          final isExtraWork = app.isExtraWorkDateOn(date);
          if (isExtraWork) {
            final dateKey = DateFormat('yyyy-MM-dd').format(date);
            appsByDate.putIfAbsent(dateKey, () => []);
            if (!appsByDate[dateKey]!.any((a) => a.id == app.id)) {
              appsByDate[dateKey]!.add(app);
            }
            continue;
          }
          // 요일 체크
          final dayWeekday = FormatHelper.weekday(date);
          if (!app.workDays!.contains(dayWeekday)) continue;

          final dateKey = DateFormat('yyyy-MM-dd').format(date);
          appsByDate.putIfAbsent(dateKey, () => []);
          if (!appsByDate[dateKey]!.any((a) => a.id == app.id)) {
            appsByDate[dateKey]!.add(app);
          }
        }
      }

      debugPrint('  [appsByDate] ${appsByDate.length}개 날짜: ${appsByDate.keys.toList()}');

      // 3. attendance 조회 — [H-CF-1] callableGetAttendanceForClosing CF 경유
      // assertBizAdmin 서버 교차검증 + 월 범위 서버 필터링
      // key: '{applicationId}_{yyyy-MM-dd}', value: {status, wageStatus}
      final Map<String, Map<String, String?>> attendanceByKey = {};

      if (appsByDate.isNotEmpty) {
        final allAppIds = appsByDate.values
            .expand((apps) => apps.map((a) => a.id))
            .toSet()
            .toList();
        try {
          // 500개 청크 분할 — CF의 applicationIds 상한 제한 대응
          final attCallable = FirebaseFunctions.instanceFor(region: 'asia-northeast3')
              .httpsCallable('callableGetAttendanceForClosing',
                  options: HttpsCallableOptions(timeout: const Duration(seconds: 60)));
          final chunks = [
            for (int i = 0; i < allAppIds.length; i += 500)
              allAppIds.sublist(i, (i + 500).clamp(0, allAppIds.length)),
          ];
          final chunkResults = await Future.wait(chunks.map((chunk) => attCallable.call({
            'businessId': businessId,
            'applicationIds': chunk,
            'monthStartMs': monthStart.millisecondsSinceEpoch,
            'monthEndExclusiveMs': monthEndExclusive.millisecondsSinceEpoch,
          })));
          for (final attResult in chunkResults) {
            for (final rec in (attResult.data['records'] as List? ?? [])) {
              final m = Map<String, dynamic>.from(rec as Map);
              final appId = m['applicationId'] as String? ?? '';
              final wdRaw = m['workDate'] as Map?;
              if (wdRaw == null || appId.isEmpty) continue;
              final seconds = (wdRaw['_seconds'] as num?)?.toInt() ?? 0;
              final workDate = DateTime.fromMillisecondsSinceEpoch(seconds * 1000).toLocal();
              final dateKey = DateFormat('yyyy-MM-dd').format(workDate);
              attendanceByKey['${appId}_$dateKey'] = {
                'status': m['status'] as String? ?? '',
                'wageStatus': m['wageStatus'] as String?,
              };
            }
          }
          debugPrint('  [attendance] 이번달 레코드(CF): ${attendanceByKey.length}건');
        } catch (e) {
          debugPrint('⚠️ [마감관리] attendance CF 조회 실패: $e');
        }
      }

      // 4. 각 날짜별 마감 상태 확인
      for (final entry in appsByDate.entries) {
        final dateKey = entry.key;
        final apps = entry.value;

        int totalConfirmed = apps.length;
        int closedCount = 0;
        int noshowCount = 0;
        int wagePendingCount = 0;
        int noAttendanceCount = 0;

        for (final app in apps) {
          final att = attendanceByKey['${app.id}_$dateKey'];
          if (att == null) {
            noAttendanceCount++;
          } else if (att['status'] == AttendanceModel.statusNoShow) {
            noshowCount++;
            closedCount++;
          } else if (att['wageStatus'] == AttendanceModel.wageConfirmed ||
                     att['wageStatus'] == AttendanceModel.wageTransferred) {
            // wageTransferred(송금완료)도 마감 완료로 집계
            closedCount++;
          } else {
            wagePendingCount++;
          }
        }

        // 마감 상태 결정 (전원 마감 = closed, 아니면 unclosed)
        final statusType = (totalConfirmed > 0 && totalConfirmed == closedCount)
            ? CloseStatusType.closed
            : CloseStatusType.unclosed;

        dateStatuses.add(DateCloseStatus(
          date: DateTime.parse(dateKey),
          totalConfirmed: totalConfirmed,
          closedCount: closedCount,
          noshowCount: noshowCount,
          wagePendingCount: wagePendingCount,
          noAttendanceCount: noAttendanceCount,
          statusType: statusType,
        ));
      }

      // 날짜순 정렬
      dateStatuses.sort((a, b) => a.date.compareTo(b.date));
      return dateStatuses;
    } catch (e) {
      debugPrint('⚠️ [마감관리] businessId=$businessId 조회 실패: $e');
    }
    return [];
  }

  /// 요약 통계 계산
  void _calculateSummary() {
    int totalDays = 0;
    int closedDays = 0;
    int unclosedDays = 0;

    // [P0-C] canonical unit = businessId × date
    // HOME이 business×date 합산을 사용하므로 DETAIL도 동일 단위로 집계
    // (이전: unique date — 복수 사업장에 같은 날짜가 있으면 1로 집계되는 unit mismatch 수정)
    final Set<String> allBizDates = {};
    final Map<String, bool> bizDateAllClosed = {};

    for (final entry in _closeStatusByBusiness.entries) {
      final bizId = entry.key;
      for (final status in entry.value) {
        final dateKey = DateFormat('yyyy-MM-dd').format(status.date);
        final bizDateKey = '${bizId}_$dateKey';
        allBizDates.add(bizDateKey);
        final isClosed = status.statusType == CloseStatusType.closed;
        bizDateAllClosed[bizDateKey] = (bizDateAllClosed[bizDateKey] ?? true) && isClosed;
      }
    }

    final closedBizDates = bizDateAllClosed.entries
        .where((e) => e.value)
        .map((e) => e.key)
        .toSet();

    totalDays = allBizDates.length;
    closedDays = closedBizDates.length;
    unclosedDays = totalDays - closedDays;

    _totalDays = totalDays;
    _closedDays = closedDays;
    _unclosedDays = unclosedDays;
  }

  // ═══════════════════════════════════════════════════════════
  // 월 변경
  // ═══════════════════════════════════════════════════════════

  void _previousMonth() {
    if (isLoading) return;
    setState(() {
      _currentMonth = DateTime(_currentMonth.year, _currentMonth.month - 1, 1);
    });
    _loadData();
  }

  void _nextMonth() {
    if (isLoading) return;
    setState(() {
      _currentMonth = DateTime(_currentMonth.year, _currentMonth.month + 1, 1);
    });
    _loadData();
  }

  // ═══════════════════════════════════════════════════════════
  // 당일명단 다이얼로그 열기
  // ═══════════════════════════════════════════════════════════

  Future<void> _openAttendanceDialog(String businessId, DateTime date) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AttendanceStatusDialog(
        date: date,
        businessIds: [businessId],
        initialBusinessId: businessId,
      ),
    );
    
    // ✅ 콜체인: 당일명단에서 변경 시 마감관리도 갱신
    if (result == true && mounted) {
      _hasChanges = true;
      await _loadData();
    }
  }

  // ═══════════════════════════════════════════════════════════
  // UI 빌드
  // ═══════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final monthStr = _monthFmt.format(_currentMonth);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          Navigator.pop(context, _hasChanges);
        }
      },
      child: AppModalShell(
        children: [
          // 헤더
          _buildHeader(theme, monthStr),

          // 요약 카드
          if (!isLoading) _buildSummaryCard(theme),

          // 컨텐츠 (스크롤 가능)
          Expanded(
            child: isLoading
                ? const LoadingWidget(message: '마감 현황 조회 중...')
                : _closeStatusByBusiness.isEmpty
                    ? _buildEmptyState()
                    : _buildContent(theme),
          ),

          // 하단 버튼
          _buildBottomBar(theme),
        ],
      ),
    );
  }

  /// 헤더
  Widget _buildHeader(ThemeData theme, String monthStr) {
    return AppModalHeader(
      title: '마감관리',
      subtitle: '당일명단 마감 현황',
      onClose: () => Navigator.pop(context, _hasChanges),
      trailing: _buildMonthNav(monthStr),
    );
  }

  /// 월 네비게이션 (← 년/월 →)
  Widget _buildMonthNav(String monthStr) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        InkWell(
          onTap: _previousMonth,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 6)),
            child: Icon(
              Icons.chevron_left,
              color: AppColors.grey600,
              size: ResponsiveHelper.iconSize(context, 24),
            ),
          ),
        ),
        SizedBox(width: ResponsiveHelper.spacing(context, 8)),
        Text(
          monthStr,
          style: ResponsiveHelper.subtitleStyle(context).copyWith(
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
          ),
        ),
        SizedBox(width: ResponsiveHelper.spacing(context, 8)),
        InkWell(
          onTap: _nextMonth,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 6)),
            child: Icon(
              Icons.chevron_right,
              color: AppColors.grey600,
              size: ResponsiveHelper.iconSize(context, 24),
            ),
          ),
        ),
      ],
    );
  }

  /// 요약 카드
  Widget _buildSummaryCard(ThemeData theme) {
    return Container(
      margin: ResponsiveHelper.cardPadding(context),
      padding: ResponsiveHelper.cardPadding(context),
      decoration: BoxDecoration(
        color: AppColors.grey50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _buildSummaryItem('총 일수', '$_totalDays일', AppColors.grey600),
          Container(
            width: 1,
            height: ResponsiveHelper.spacing(context, 30),
            color: AppColors.border,
          ),
          _buildSummaryItem('마감완료', '$_closedDays일', AppColors.success),
          Container(
            width: 1,
            height: ResponsiveHelper.spacing(context, 30),
            color: AppColors.border,
          ),
          _buildSummaryItem('미마감', '$_unclosedDays일', AppColors.error),
        ],
      ),
    );
  }

  Widget _buildSummaryItem(String label, String value, Color color) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: ResponsiveHelper.subtitleStyle(context).copyWith(
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        SizedBox(height: ResponsiveHelper.spacing(context, 2)),
        Text(
          label,
          style: ResponsiveHelper.smallStyle(context, color: AppColors.grey500),
        ),
      ],
    );
  }

  /// 빈 상태
  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: ResponsiveHelper.cardPadding(context),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.event_available,
              size: ResponsiveHelper.iconSize(context, 64),
              color: AppColors.grey300,
            ),
            SizedBox(height: ResponsiveHelper.spacing(context, 16)),
            Text(
              '해당 월에 확정된 인원이 없습니다',
              style: ResponsiveHelper.bodyStyle(context, color: AppColors.grey500),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  /// 컨텐츠 (사업장별 목록)
  Widget _buildContent(ThemeData theme) {
    final hasClosed = _hasClosed;

    return ListView(
      padding: ResponsiveHelper.cardPadding(context),
      children: [
        // 마감완료 날짜 탭 안내 — 마감완료 행이 하나라도 있을 때만 표시
        if (hasClosed)
          Container(
            margin: EdgeInsets.only(bottom: ResponsiveHelper.spacing(context, 12)),
            padding: EdgeInsets.symmetric(
              horizontal: ResponsiveHelper.spacing(context, 12),
              vertical: ResponsiveHelper.spacing(context, 10),
            ),
            decoration: BoxDecoration(
              color: AppColors.success.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.success.withValues(alpha: 0.2)),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline,
                    size: ResponsiveHelper.iconSize(context, 16),
                    color: AppColors.success),
                SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                Expanded(
                  child: Text(
                    '마감완료 날짜를 탭하면 당일명단에서 마감을 취소할 수 있습니다.',
                    style: ResponsiveHelper.smallStyle(context).copyWith(
                      color: AppColors.success,
                    ),
                  ),
                ),
              ],
            ),
          ),

        for (final entry in _closeStatusByBusiness.entries)
          _buildBusinessSection(theme, entry.key,
              _businessNameMap[entry.key] ?? '알 수 없음', entry.value),
      ],
    );
  }

  /// 사업장별 섹션
  Widget _buildBusinessSection(
    ThemeData theme,
    String businessId,
    String businessName,
    List<DateCloseStatus> statuses,
  ) {
    return Container(
      margin: EdgeInsets.only(bottom: ResponsiveHelper.spacing(context, 16)),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 사업장 헤더
          Container(
            padding: EdgeInsets.symmetric(
              horizontal: ResponsiveHelper.spacing(context, 16),
              vertical: ResponsiveHelper.spacing(context, 12),
            ),
            decoration: BoxDecoration(
              color: theme.primaryColor.withValues(alpha: 0.05),
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.business,
                  size: ResponsiveHelper.iconSize(context, 20),
                  color: theme.primaryColor,
                ),
                SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                Expanded(
                  child: Text(
                    businessName,
                    style: ResponsiveHelper.subtitleStyle(context).copyWith(
                      fontWeight: FontWeight.bold,
                      color: theme.primaryColor,
                    ),
                  ),
                ),
                // 사업장별 마감 현황
                _buildBusinessSummary(statuses),
              ],
            ),
          ),
          
          // 날짜별 목록
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: statuses.length,
            separatorBuilder: (_, __) => Divider(
              height: 1,
              color: AppColors.border,
            ),
            itemBuilder: (context, index) {
              return _buildDateRow(theme, businessId, statuses[index]);
            },
          ),
        ],
      ),
    );
  }

  /// 사업장별 마감 요약
  Widget _buildBusinessSummary(List<DateCloseStatus> statuses) {
    final closedCount = statuses.where((s) => s.statusType == CloseStatusType.closed).length;
    final totalCount = statuses.length;
    final isAllClosed = closedCount == totalCount;
    
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 10),
        vertical: ResponsiveHelper.spacing(context, 4),
      ),
      decoration: BoxDecoration(
        color: isAllClosed ? AppColors.success.withValues(alpha: 0.1) : AppColors.warning.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        '$closedCount/$totalCount',
        style: ResponsiveHelper.smallStyle(context).copyWith(
          fontWeight: FontWeight.bold,
          color: isAllClosed ? AppColors.success : AppColors.warning,
        ),
      ),
    );
  }

  /// 날짜별 행
  Widget _buildDateRow(ThemeData theme, String businessId, DateCloseStatus status) {
    final dateStr = _dateFmtKo.format(status.date);
    final isClosed = status.statusType == CloseStatusType.closed;
    // [DESIGN] 미래 날짜도 탭 가능 — 사전 마감 허용이 의도된 설계. 비활성화 복원 금지.
    final indicatorColor = isClosed ? AppColors.success : AppColors.error;

    return InkWell(
      onTap: () => _openAttendanceDialog(businessId, status.date),
      child: Row(
        children: [
          // 왼쪽 상태 인디케이터 바
          Container(
            width: 4,
            height: ResponsiveHelper.spacing(context, 48),
            color: indicatorColor,
          ),
          Expanded(
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: ResponsiveHelper.spacing(context, 16),
                vertical: ResponsiveHelper.spacing(context, 12),
              ),
              child: Row(
                children: [
                  Text(
                    dateStr,
                    style: ResponsiveHelper.bodyStyle(context).copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  SizedBox(width: ResponsiveHelper.spacing(context, 12)),
                  Text(
                    '${status.closedCount}/${status.totalConfirmed}명',
                    style: ResponsiveHelper.bodyStyle(context).copyWith(
                      fontWeight: FontWeight.w600,
                      color: isClosed ? AppColors.success : AppColors.grey600,
                    ),
                  ),
                  const Spacer(),
                  _buildStatusBadge(status),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 상태 배지
  Widget _buildStatusBadge(DateCloseStatus status) {
    final isClosed = status.statusType == CloseStatusType.closed;
    final unclosedCount = status.totalConfirmed - status.closedCount;

    final bgColor = isClosed
        ? AppColors.success.withValues(alpha: 0.1)
        : AppColors.error.withValues(alpha: 0.1);
    final textColor = isClosed ? AppColors.success : AppColors.error;
    final icon = isClosed ? Icons.lock : Icons.lock_open;
    final text = isClosed ? '마감완료' : '미마감 $unclosedCount명';

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 10),
        vertical: ResponsiveHelper.spacing(context, 6),
      ),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: ResponsiveHelper.iconSize(context, 14), color: textColor),
          SizedBox(width: ResponsiveHelper.spacing(context, 4)),
          Text(
            text,
            style: ResponsiveHelper.smallStyle(context).copyWith(
              fontWeight: FontWeight.w600,
              color: textColor,
            ),
          ),
          SizedBox(width: ResponsiveHelper.spacing(context, 4)),
          Icon(Icons.chevron_right, size: ResponsiveHelper.iconSize(context, 16), color: textColor),
        ],
      ),
    );
  }

  /// 하단 버튼 바
  Widget _buildBottomBar(ThemeData theme) {
    return AppModalFooter(
      child: SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: () => Navigator.pop(context, _hasChanges),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.grey200,
            foregroundColor: AppColors.grey700,
            padding: EdgeInsets.symmetric(
              vertical: ResponsiveHelper.spacing(context, 14),
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            elevation: 0,
          ),
          child: Text(
            '닫기',
            style: ResponsiveHelper.bodyStyle(context).copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
// 데이터 모델
// ═══════════════════════════════════════════════════════════

/// 마감 상태 타입
enum CloseStatusType {
  closed,    // 마감완료
  unclosed,  // 미마감
}

/// 날짜별 마감 상태
class DateCloseStatus {
  final DateTime date;
  final int totalConfirmed;     // 확정 인원
  final int closedCount;        // 마감된 인원 (confirmed + noshow)
  final int noshowCount;        // 노쇼 인원
  final int wagePendingCount;   // 급여 미확정 인원 (출퇴근 완료 but 급여 미확정)
  final int noAttendanceCount;  // 출퇴근 기록 없는 인원
  final CloseStatusType statusType;

  DateCloseStatus({
    required this.date,
    required this.totalConfirmed,
    required this.closedCount,
    required this.noshowCount,
    this.wagePendingCount = 0,
    this.noAttendanceCount = 0,
    required this.statusType,
  });
}