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
import 'package:intl/intl.dart';

// Models
import '../../../models/core/application_model.dart';
import '../../../models/core/attendance_model.dart';

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

  const CloseManagementDialog({
    super.key,
    required this.initialMonth,
    required this.businessIds,
  });

  @override
  State<CloseManagementDialog> createState() => _CloseManagementDialogState();
}

class _CloseManagementDialogState extends State<CloseManagementDialog>
    with LoadingStateMixin {
  // ═══════════════════════════════════════════════════════════
  // 상태 변수
  // ═══════════════════════════════════════════════════════════

  late DateTime _currentMonth;
  bool _hasChanges = false;
  
  // 사업장 정보
  Map<String, String> _businessNameMap = {};
  
  // 마감 현황 데이터: businessId -> List<DateCloseStatus>
  Map<String, List<DateCloseStatus>> _closeStatusByBusiness = {};
  
  // 요약 통계
  int _totalDays = 0;
  int _closedDays = 0;
  int _unclosedDays = 0;

  @override
  void initState() {
    super.initState();
    _currentMonth = DateTime(widget.initialMonth.year, widget.initialMonth.month, 1);
    _loadData();
  }

  // ═══════════════════════════════════════════════════════════
  // 데이터 로드
  // ═══════════════════════════════════════════════════════════

  Future<void> _loadData() => runWithLoading(() async {
    try {
      await _loadBusinessNames();
    } catch (e) {
      debugPrint('❌ [마감관리] 사업장 이름 로드 실패: $e');
      // 이름 로드 실패해도 현황 조회는 계속 진행
    }
    await _loadCloseStatus();
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

  /// 마감 현황 로드
  Future<void> _loadCloseStatus() async {
    final Map<String, List<DateCloseStatus>> statusByBusiness = {};

    // 해당 월의 시작/끝 날짜
    final monthStart = DateTime(_currentMonth.year, _currentMonth.month, 1);
    final monthEnd = DateTime(_currentMonth.year, _currentMonth.month + 1, 0, 23, 59, 59);
    final daysInMonth = monthEnd.day;

    debugPrint('🔍 [마감관리] 조회 시작 ${DateFormat('yyyy-MM').format(_currentMonth)} '
        '| businessIds: ${widget.businessIds}');
    debugPrint('   monthStart=$monthStart, monthEnd=$monthEnd');

    for (final businessId in widget.businessIds) {
      final List<DateCloseStatus> dateStatuses = [];

      // 1. 단기 확정자: 해당 월의 workDate 범위로 조회 (CONTRACT_PENDING 포함)
      final shortTermSnapshot = await FirebaseFirestore.instance
          .collection('applications')
          .where('businessId', isEqualTo: businessId)
          .where('status', whereIn: AppStatus.confirmedStatuses)
          .where('workDate', isGreaterThanOrEqualTo: Timestamp.fromDate(monthStart))
          .where('workDate', isLessThan: Timestamp.fromDate(monthEnd))
          .get();

      debugPrint('  [단기] businessId=$businessId → ${shortTermSnapshot.docs.length}건');

      final Map<String, List<ApplicationModel>> appsByDate = {};
      for (final doc in shortTermSnapshot.docs) {
        final app = ApplicationModel.fromFirestore(doc);
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

      // 2. 장기 확정자: 전체 조회 후 해당 월의 활성 날짜로 확장 (CONTRACT_PENDING 포함)
      final longTermSnapshot = await FirebaseFirestore.instance
          .collection('applications')
          .where('businessId', isEqualTo: businessId)
          .where('status', whereIn: AppStatus.confirmedStatuses)
          .get();

      debugPrint('  [장기 전체] businessId=$businessId → ${longTermSnapshot.docs.length}건');

      for (final doc in longTermSnapshot.docs) {
        final app = ApplicationModel.fromFirestore(doc);
        if (app.workDays == null || app.workDays!.isEmpty) continue;
        debugPrint('    장기 app: id=${app.id}, workDate=${app.workDate}, workDays=${app.workDays}');

        final endDate = app.actualResignDate ?? app.workEndDate;
        // 종료일 없는 장기 지원서는 영구 활성으로 잘못 집계되는 것 방지
        if (endDate == null) continue;
        final effectiveStartDate = app.desiredStartDate ?? app.workDate;
        final startDateOnly = DateTime(effectiveStartDate.year, effectiveStartDate.month, effectiveStartDate.day);

        for (int d = 1; d <= daysInMonth; d++) {
          final date = DateTime(_currentMonth.year, _currentMonth.month, d);
          if (date.isBefore(startDateOnly)) continue;
          final endDateOnly = DateTime(endDate.year, endDate.month, endDate.day);
          if (date.isAfter(endDateOnly)) continue;
          // 휴무일 체크
          if (app.leaveDates != null && app.leaveDates!.any((ld) =>
              ld.year == date.year && ld.month == date.month && ld.day == date.day)) {
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

      // 3. 배치로 attendance 조회 (N+1 방지)
      // applicationId whereIn 방식: 단일 필드 자동 인덱스 사용, 복합 인덱스 불필요
      // key: '{applicationId}_{yyyy-MM-dd}'
      final Map<String, AttendanceModel> attendanceByKey = {};

      if (appsByDate.isNotEmpty) {
        final allAppIds = appsByDate.values
            .expand((apps) => apps.map((a) => a.id))
            .toSet()
            .toList();

        // whereIn 최대 30개 제한 → 배치 처리
        for (int i = 0; i < allAppIds.length; i += 30) {
          final batchIds = allAppIds.sublist(
            i,
            (i + 30).clamp(0, allAppIds.length),
          );
          final snap = await FirebaseFirestore.instance
              .collection('attendance')
              .where('applicationId', whereIn: batchIds)
              .get();
          for (final doc in snap.docs) {
            final att = AttendanceModel.fromFirestore(doc);
            // 코드에서 월 범위 필터링
            if (att.workDate.isBefore(monthStart) || att.workDate.isAfter(monthEnd)) {
              continue;
            }
            final dateKey = DateFormat('yyyy-MM-dd').format(att.workDate);
            attendanceByKey['${att.applicationId}_$dateKey'] = att;
          }
        }
        debugPrint('  [attendance] 이번달 레코드: ${attendanceByKey.length}건');
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
          } else if (att.status == AttendanceModel.statusNoShow) {
            noshowCount++;
            closedCount++;
          } else if (att.wageStatus == AttendanceModel.wageConfirmed) {
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

      if (dateStatuses.isNotEmpty) {
        statusByBusiness[businessId] = dateStatuses;
      }
    }

    _closeStatusByBusiness = statusByBusiness;
  }

  /// 요약 통계 계산
  void _calculateSummary() {
    int totalDays = 0;
    int closedDays = 0;
    int unclosedDays = 0;
    
    // 날짜별 모든 사업장이 마감됐는지 추적
    // (한 사업장이라도 미마감이면 해당 날짜는 미마감으로 집계)
    final Set<String> allDates = {};
    final Map<String, bool> dateAllClosed = {};

    for (final statuses in _closeStatusByBusiness.values) {
      for (final status in statuses) {
        final dateKey = DateFormat('yyyy-MM-dd').format(status.date);
        allDates.add(dateKey);
        final isClosed = status.statusType == CloseStatusType.closed;
        dateAllClosed[dateKey] = (dateAllClosed[dateKey] ?? true) && isClosed;
      }
    }

    final closedDates = dateAllClosed.entries
        .where((e) => e.value)
        .map((e) => e.key)
        .toSet();

    totalDays = allDates.length;
    closedDays = closedDates.length;
    unclosedDays = totalDays - closedDays;
    
    _totalDays = totalDays;
    _closedDays = closedDays;
    _unclosedDays = unclosedDays;
  }

  // ═══════════════════════════════════════════════════════════
  // 월 변경
  // ═══════════════════════════════════════════════════════════

  void _previousMonth() {
    setState(() {
      _currentMonth = DateTime(_currentMonth.year, _currentMonth.month - 1, 1);
    });
    _loadData();
  }

  void _nextMonth() {
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
    final monthStr = DateFormat('yyyy년 M월').format(_currentMonth);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          Navigator.pop(context, _hasChanges);
        }
      },
      child: Dialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
        insetPadding: EdgeInsets.symmetric(
          horizontal: ResponsiveHelper.spacing(context, 16),
          vertical: AppDialogSize.insetV,
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * AppDialogSize.maxHeightRatio),
          child: Column(
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
        ),
      ),
    );
  }

  /// 헤더 (그라데이션)
  Widget _buildHeader(ThemeData theme, String monthStr) {
    return Container(
      padding: ResponsiveHelper.cardPadding(context),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.success,
            AppColors.success.withValues(alpha: 0.85),
          ],
        ),
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(ResponsiveHelper.spacing(context, 24)),
          topRight: Radius.circular(ResponsiveHelper.spacing(context, 24)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 제목 + 닫기 버튼
          Row(
            children: [
              Container(
                padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 10)),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.lock_outline,
                  color: Colors.white,
                  size: ResponsiveHelper.iconSize(context, 24),
                ),
              ),
              SizedBox(width: ResponsiveHelper.spacing(context, 12)),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '마감관리',
                    style: ResponsiveHelper.titleStyle(context).copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    '당일명단 마감 현황',
                    style: ResponsiveHelper.smallStyle(context).copyWith(
                      color: Colors.white.withValues(alpha: 0.8),
                    ),
                  ),
                ],
              ),
              const Spacer(),
              IconButton(
                onPressed: () => Navigator.pop(context, _hasChanges),
                tooltip: '닫기',
                icon: Icon(
                  Icons.close,
                  color: Colors.white,
                  size: ResponsiveHelper.iconSize(context, 24),
                ),
              ),
            ],
          ),
          
          SizedBox(height: ResponsiveHelper.spacing(context, 16)),
          
          // 월 선택
          Container(
            padding: EdgeInsets.symmetric(
              horizontal: ResponsiveHelper.spacing(context, 12),
              vertical: ResponsiveHelper.spacing(context, 8),
            ),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                InkWell(
                  onTap: _previousMonth,
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 4)),
                    child: Icon(
                      Icons.chevron_left,
                      color: AppColors.success,
                      size: ResponsiveHelper.iconSize(context, 24),
                    ),
                  ),
                ),
                SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                Text(
                  monthStr,
                  style: ResponsiveHelper.subtitleStyle(context).copyWith(
                    fontWeight: FontWeight.bold,
                    color: AppColors.success,
                  ),
                ),
                SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                InkWell(
                  onTap: _nextMonth,
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 4)),
                    child: Icon(
                      Icons.chevron_right,
                      color: AppColors.success,
                      size: ResponsiveHelper.iconSize(context, 24),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
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
    return ListView.builder(
      padding: ResponsiveHelper.cardPadding(context),
      shrinkWrap: true,
      itemCount: _closeStatusByBusiness.length,
      itemBuilder: (context, index) {
        final businessId = _closeStatusByBusiness.keys.elementAt(index);
        final statuses = _closeStatusByBusiness[businessId]!;
        final businessName = _businessNameMap[businessId] ?? '알 수 없음';
        
        return _buildBusinessSection(theme, businessId, businessName, statuses);
      },
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
    final dateStr = DateFormat('M/d(E)', 'ko_KR').format(status.date);
    final isClosed = status.statusType == CloseStatusType.closed;
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
                  // 날짜
                  Text(
                    dateStr,
                    style: ResponsiveHelper.bodyStyle(context).copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                  ),

                  SizedBox(width: ResponsiveHelper.spacing(context, 12)),

                  // 마감 진행률
                  Text(
                    '${status.closedCount}/${status.totalConfirmed}명',
                    style: ResponsiveHelper.bodyStyle(context).copyWith(
                      fontWeight: FontWeight.w600,
                      color: isClosed ? AppColors.success : AppColors.grey600,
                    ),
                  ),

                  const Spacer(),

                  // 상태 배지
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

    // 미마감 이유 분류 문자열 구성
    String text;
    if (isClosed) {
      text = '마감완료';
    } else {
      final reasons = <String>[];
      if (status.wagePendingCount > 0) reasons.add('급여${status.wagePendingCount}');
      if (status.noAttendanceCount > 0) reasons.add('미출근${status.noAttendanceCount}');
      if (reasons.isEmpty) {
        text = '미마감 $unclosedCount명';
      } else {
        text = '미마감 $unclosedCount명 (${reasons.join(' + ')})';
      }
    }

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
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            icon,
            size: ResponsiveHelper.iconSize(context, 14),
            color: textColor,
          ),
          SizedBox(width: ResponsiveHelper.spacing(context, 4)),
          Text(
            text,
            style: ResponsiveHelper.smallStyle(context).copyWith(
              fontWeight: FontWeight.w600,
              color: textColor,
            ),
          ),
          // 상세보기 아이콘 (항상 표시)
          SizedBox(width: ResponsiveHelper.spacing(context, 4)),
          Icon(
            Icons.chevron_right,
            size: ResponsiveHelper.iconSize(context, 16),
            color: textColor,
          ),
        ],
      ),
    );
  }

  /// 하단 버튼 바
  Widget _buildBottomBar(ThemeData theme) {
    return Container(
      padding: ResponsiveHelper.cardPadding(context),
      decoration: BoxDecoration(
        color: AppColors.grey50,
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(24),
          bottomRight: Radius.circular(24),
        ),
        border: Border(
          top: BorderSide(color: AppColors.border),
        ),
      ),
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