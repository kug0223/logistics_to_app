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
import '../../../utils/toast_helper.dart';
import '../../../utils/responsive_helper.dart';
import '../../../theme/app_colors.dart';

// Widgets
import '../../../widgets/common/loading_widget.dart';

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

class _CloseManagementDialogState extends State<CloseManagementDialog> {
  // ═══════════════════════════════════════════════════════════
  // 상태 변수
  // ═══════════════════════════════════════════════════════════
  
  late DateTime _currentMonth;
  bool _isLoading = true;
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

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    try {
      // 1. 사업장 이름 로드
      await _loadBusinessNames();
      
      // 2. 마감 현황 로드
      await _loadCloseStatus();
      
      // 3. 요약 통계 계산
      _calculateSummary();
      
    } catch (e) {
      debugPrint('❌ 마감 현황 로드 실패: $e');
      ToastHelper.showError('마감 현황을 불러오는데 실패했습니다');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  /// 사업장 이름 로드
  Future<void> _loadBusinessNames() async {
    final Map<String, String> nameMap = {};
    
    for (final businessId in widget.businessIds) {
      final doc = await FirebaseFirestore.instance
          .collection('businesses')
          .doc(businessId)
          .get();
      
      if (doc.exists) {
        nameMap[businessId] = doc.data()?['name'] ?? '알 수 없음';
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
    
    for (final businessId in widget.businessIds) {
      final List<DateCloseStatus> dateStatuses = [];
      
      // 1. 해당 월의 확정된 Application 조회 (날짜별로 그룹화)
      final appsSnapshot = await FirebaseFirestore.instance
          .collection('applications')
          .where('businessId', isEqualTo: businessId)
          .where('status', isEqualTo: 'CONFIRMED')
          .where('workDate', isGreaterThanOrEqualTo: Timestamp.fromDate(monthStart))
          .where('workDate', isLessThanOrEqualTo: Timestamp.fromDate(monthEnd))
          .get();
      
      // 날짜별로 그룹화
      final Map<String, List<ApplicationModel>> appsByDate = {};
      for (final doc in appsSnapshot.docs) {
        final app = ApplicationModel.fromFirestore(doc);
        final dateKey = DateFormat('yyyy-MM-dd').format(app.workDate);
        appsByDate.putIfAbsent(dateKey, () => []);
        appsByDate[dateKey]!.add(app);
      }
      
      // 2. 각 날짜별 마감 상태 확인
      for (final entry in appsByDate.entries) {
        final dateKey = entry.key;
        final apps = entry.value;
        final date = DateTime.parse(dateKey);
        
        // 해당 날짜의 attendance 조회
        int totalConfirmed = apps.length;
        int closedCount = 0;
        int noshowCount = 0;
        
        for (final app in apps) {
          final attSnapshot = await FirebaseFirestore.instance
              .collection('attendance')
              .where('applicationId', isEqualTo: app.id)
              .limit(1)
              .get();
          
          if (attSnapshot.docs.isNotEmpty) {
            final att = AttendanceModel.fromFirestore(attSnapshot.docs.first);
            if (att.status == 'NO_SHOW') {
              noshowCount++;
              closedCount++;  // 노쇼도 마감 처리된 것으로 간주
            } else if (att.wageStatus == 'confirmed') {
              closedCount++;
            }
          }
        }
        
        // 마감 상태 결정 (전원 마감 = closed, 아니면 unclosed)
        final statusType = (totalConfirmed == closedCount) 
            ? CloseStatusType.closed 
            : CloseStatusType.unclosed;
        
        dateStatuses.add(DateCloseStatus(
          date: date,
          totalConfirmed: totalConfirmed,
          closedCount: closedCount,
          noshowCount: noshowCount,
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
    
    // 중복 날짜 제거를 위해 Set 사용
    final Set<String> allDates = {};
    final Set<String> closedDates = {};
    
    for (final statuses in _closeStatusByBusiness.values) {
      for (final status in statuses) {
        final dateKey = DateFormat('yyyy-MM-dd').format(status.date);
        allDates.add(dateKey);
        
        if (status.statusType == CloseStatusType.closed) {
          closedDates.add(dateKey);
        }
      }
    }
    
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
          vertical: ResponsiveHelper.spacing(context, 24),
        ),
        child: Container(
          width: double.infinity,
          height: MediaQuery.of(context).size.height * 0.7,  // ✅ 고정 비율 높이
          child: Column(
            children: [
              // 헤더
              _buildHeader(theme, monthStr),
              
              // 요약 카드
              if (!_isLoading) _buildSummaryCard(theme),
              
              // 컨텐츠 (스크롤 가능)
              Expanded(
                child: _isLoading
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
            AppColors.success.withOpacity(0.85),
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
                  color: Colors.white.withOpacity(0.2),
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
                      color: Colors.white.withOpacity(0.8),
                    ),
                  ),
                ],
              ),
              const Spacer(),
              IconButton(
                onPressed: () => Navigator.pop(context, _hasChanges),
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
        color: Colors.grey[50],
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
            color: Colors.black.withOpacity(0.04),
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
              color: theme.primaryColor.withOpacity(0.05),
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
        color: isAllClosed ? AppColors.success.withOpacity(0.1) : AppColors.warning.withOpacity(0.1),
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
    
    return InkWell(
      onTap: () => _openAttendanceDialog(businessId, status.date),
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
            
            // 확정 인원
            Text(
              '${status.totalConfirmed}명',
              style: ResponsiveHelper.bodyStyle(context).copyWith(
                fontWeight: FontWeight.w600,
                color: AppColors.grey600,
              ),
            ),
            
            const Spacer(),
            
            // 상태 배지
            _buildStatusBadge(status),
          ],
        ),
      ),
    );
  }

  /// 상태 배지
  Widget _buildStatusBadge(DateCloseStatus status) {
    final isClosed = status.statusType == CloseStatusType.closed;
    final unclosedCount = status.totalConfirmed - status.closedCount;
    
    final bgColor = isClosed 
        ? AppColors.success.withOpacity(0.1) 
        : AppColors.error.withOpacity(0.1);
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
        color: Colors.grey[50],
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
  final int totalConfirmed;   // 확정 인원
  final int closedCount;      // 마감된 인원 (confirmed + noshow)
  final int noshowCount;      // 노쇼 인원
  final CloseStatusType statusType;
  
  DateCloseStatus({
    required this.date,
    required this.totalConfirmed,
    required this.closedCount,
    required this.noshowCount,
    required this.statusType,
  });
}