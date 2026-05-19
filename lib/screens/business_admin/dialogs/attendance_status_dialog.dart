// lib/screens/business_admin/dialogs/attendance_status_dialog.dart
// 당일명단 다이얼로그 - 출퇴근 관리 기능 포함
// 
// 주요 기능:
// - 사업장별 확정 인원 조회
// - 업무별 그룹화 + 성별/나이순 정렬
// - 전체/개별 체크박스 선택
// - 일괄/개별 출근/퇴근 시간 입력
// - 노쇼 처리 및 해제
// - 지각 자동 감지
// - (추후) 명단 출력

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

// Models
import '../../../models/core/application_model.dart';
import '../../../models/core/attendance_model.dart';
import '../../../models/core/user_model.dart';
import '../../../models/core/business_work_type_model.dart';
import '../../../models/core/wage_detail_model.dart';
import '../../../models/core/worker_location_model.dart';

// Services
import '../../../services/firestore_service.dart';

// Utils
import '../../../utils/toast_helper.dart';
import '../../../services/trust_score_service.dart';
import '../../../utils/responsive_helper.dart';
import '../../../utils/dialog_helper.dart';
import '../../../utils/format_helper.dart';
import '../../../utils/attendance_status_helper.dart';
import '../../../utils/week_helper.dart';
import '../../../theme/app_colors.dart';
import '../../../widgets/common/app_checkbox.dart';
import '../../../widgets/common/app_menu_sheet.dart';

// Widgets
import '../../../widgets/common/loading_widget.dart';
import '../../../widgets/dialogs/worker_detail_dialog.dart';
import '../../../widgets/work_type_icon.dart';
import '../../../widgets/pickers/time_picker_bottom_sheet.dart';
import '../../../widgets/pickers/attendance_quick_time_sheet.dart';
import '../../../widgets/dialogs/wage/wage_detail_dialog.dart';

// PDF
import '../../../utils/attendance_list_pdf.dart';
// Dialogs
import 'wage_confirm_dialog.dart';
import '../../../providers/user_provider.dart';
import '../../../widgets/dialogs/styled_dialog.dart';
import '../../../widgets/app_select_field.dart';

/// 당일명단 다이얼로그 - 출퇴근 관리 기능 포함
class AttendanceStatusDialog extends StatefulWidget {
  final DateTime date;
  final List<String> businessIds;
  final String? initialBusinessId;

  const AttendanceStatusDialog({
    super.key,
    required this.date,
    required this.businessIds,
    this.initialBusinessId,
  });

  @override
  State<AttendanceStatusDialog> createState() => _AttendanceStatusDialogState();
}

class _AttendanceStatusDialogState extends State<AttendanceStatusDialog> {
  // ═══════════════════════════════════════════════════════════
  // 상태 변수
  // ═══════════════════════════════════════════════════════════
  
  final FirestoreService _firestoreService = FirestoreService();

  // 데이터
  List<ApplicationModel> _confirmedWorkers = [];
  Map<String, AttendanceModel> _attendanceMap = {};
  Map<String, UserModel> _userMap = {};
  Map<String, String> _businessNameMap = {};
  Map<String, BusinessWorkTypeModel> _workTypeMap = {};  // 업무유형 정보
  Map<String, dynamic> _workDetailTimeMap = {};  // 업무별 근무시간 (WorkDetail)
  Map<String, WorkerLocationModel> _locationMap = {};  // 근로자 위치
  Map<String, WeeklyHolidayEligibility> _weeklyHolidayMap = {};  // 주휴수당 자격
  
  // UI 상태
  bool _isLoading = true;
  String? _selectedBusinessId;
  bool _hasChanges = false;  // ✅ 변경 여부 추적
  
  // 선택 상태
  final Set<String> _selectedIds = {};
  bool _selectAll = false;

  // ═══════════════════════════════════════════════════════════
  // 처리현황 계산
  // ═══════════════════════════════════════════════════════════

  /// 처리 완료된 인원 수 (급여확정 또는 노쇼 - 마감 대기 상태)
  int get _processedCount {
    int count = 0;
    for (var app in _confirmedWorkers) {
      final attendance = _attendanceMap[app.id];
      if (attendance == null) continue;
      
      // 노쇼 처리됨
      if (attendance.status == 'NO_SHOW') {
        count++;
      } 
      // 급여확정 (calculated) - 마감 대기
      else if (attendance.wageStatus == 'calculated') {
        count++;
      }
      // 최종확정 (confirmed) - 이미 마감됨
      else if (attendance.wageStatus == 'confirmed') {
        count++;
      }
    }
    return count;
  }

  /// 전체 처리 완료 여부 (마감 가능)
  bool get _isAllProcessed => _confirmedWorkers.isNotEmpty && _processedCount == _confirmedWorkers.length;

  /// 마감 가능 여부 (calculated 인원이 1명이라도 있으면 마감 가능)
  bool get _canClose {
    for (var app in _confirmedWorkers) {
      final attendance = _attendanceMap[app.id];
      if (attendance == null) continue;
      if (attendance.wageStatus == 'calculated') {
        return true;
      }
    }
    return false;
  }

  /// 마감 완료 여부 (모두 confirmed 또는 noshow)
  bool get _isAllClosed {
    if (_confirmedWorkers.isEmpty) return false;
    for (var app in _confirmedWorkers) {
      final attendance = _attendanceMap[app.id];
      if (attendance == null) return false;
      
      // noshow가 아니고 confirmed도 아니면 마감 미완료
      if (attendance.status != 'NO_SHOW' && attendance.wageStatus != 'confirmed') {
        return false;
      }
    }
    return true;
  }

  @override
  void initState() {
    super.initState();
    _selectedBusinessId = widget.initialBusinessId ?? widget.businessIds.first;
    _initializeData();
  }

  /// 초기 데이터 로드 (병렬)
  Future<void> _initializeData() async {
    await Future.wait([
      _loadBusinessNames(),
      _loadData(),
    ]);
  }

  // ═══════════════════════════════════════════════════════════
  // 데이터 로드
  // ═══════════════════════════════════════════════════════════

  /// 사업장명 조회
  Future<void> _loadBusinessNames() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('businesses')
          .where(FieldPath.documentId, whereIn: widget.businessIds)
          .get();

      final Map<String, String> nameMap = {};
      for (var doc in snapshot.docs) {
        final data = doc.data();
        nameMap[doc.id] = data['name'] ?? 'Unknown';
      }

      if (!mounted) return;
      setState(() {
        _businessNameMap = nameMap;
      });
    } catch (e) {
      debugPrint('❌ 사업장명 조회 실패: $e');
    }
  }

  /// 전체 데이터 로드 (병렬 처리로 최적화)
  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _selectedIds.clear();
      _selectAll = false;
    });

    try {
      // ✅ 1단계: 독립적인 쿼리들 병렬 실행
      final step1Results = await Future.wait([
        _getConfirmedWorkersForDate(),  // [0] 확정 근무자
        _getWorkTypeInfo(),              // [1] 업무유형 정보
        _getWorkDetailTimes(),           // [2] WorkDetail 시간 정보
      ]);
      
      final confirmedWorkers = step1Results[0] as List<ApplicationModel>;
      final workTypeMap = step1Results[1] as Map<String, BusinessWorkTypeModel>;
      final workDetailTimeMap = step1Results[2] as Map<String, dynamic>;
      
      // ✅ 2단계: 근무자 기반 쿼리들 병렬 실행
      final uids = confirmedWorkers.map((app) => app.uid).toSet().toList();
      final appIds = confirmedWorkers.map((app) => app.id).toList();

      final step2Results = await Future.wait([
        _getAttendanceRecords(appIds),                              // [0] 출근 기록
        _getUserInfoBatch(uids),                                     // [1] 사용자 정보
        _firestoreService.getLocationsForApplications(appIds),       // [2] 위치 정보
      ]);

      final attendanceMap = step2Results[0] as Map<String, AttendanceModel>;
      final userMap = step2Results[1] as Map<String, UserModel>;
      final locationMap = step2Results[2] as Map<String, WorkerLocationModel>;

      if (!mounted) return;
      setState(() {
        _confirmedWorkers = confirmedWorkers;
        _attendanceMap = attendanceMap;
        _userMap = userMap;
        _workTypeMap = workTypeMap;
        _workDetailTimeMap = workDetailTimeMap;
        _locationMap = locationMap;
        _weeklyHolidayMap = {};
        _isLoading = false;
      });

      // 주휴수당 자격은 별도 비동기로 계산 (UI 블로킹 없음)
      _computeWeeklyHolidayEligibility(confirmedWorkers, workDetailTimeMap);

      debugPrint('✅ 당일명단 로드 완료: ${confirmedWorkers.length}명');
    } catch (e) {
      debugPrint('❌ 당일명단 데이터 로드 실패: $e');
      if (!mounted) return;
      setState(() => _isLoading = false);
      ToastHelper.showError('데이터 로드 실패');
    }
  }

  /// 확정 근무자 조회 (해당 날짜) - 최적화
  Future<List<ApplicationModel>> _getConfirmedWorkersForDate() async {
    final dateStart = DateTime(widget.date.year, widget.date.month, widget.date.day);
    final dateEnd = dateStart.add(const Duration(days: 1));
    
    final result = <ApplicationModel>[];

    // ✅ 1. 단기 공고: 서버에서 workDate 필터링 (빠름!)
    final shortTermSnapshot = await FirebaseFirestore.instance
        .collection('applications')
        .where('businessId', isEqualTo: _selectedBusinessId)
        .where('status', isEqualTo: AppStatus.confirmed)
        .where('workDate', isGreaterThanOrEqualTo: Timestamp.fromDate(dateStart))
        .where('workDate', isLessThan: Timestamp.fromDate(dateEnd))
        .get();
    
    // 단기만 필터 (workDays가 없는 것)
    for (var doc in shortTermSnapshot.docs) {
      final app = ApplicationModel.fromFirestore(doc);
      if (app.workDays == null || app.workDays!.isEmpty) {
        result.add(app);
      }
    }
    
    debugPrint('📋 [당일명단] 단기 확정자: ${result.length}명');

    // ✅ 2. 장기 공고: 전체 조회 후 클라이언트 필터링 (workDays 필터는 Firestore에서 지원 안함)
    final longTermSnapshot = await FirebaseFirestore.instance
        .collection('applications')
        .where('businessId', isEqualTo: _selectedBusinessId)
        .where('status', isEqualTo: AppStatus.confirmed)
        .get();

    int longTermCount = 0;
    for (var doc in longTermSnapshot.docs) {
      final app = ApplicationModel.fromFirestore(doc);
      
      // 장기가 아니면 스킵 (단기는 위에서 이미 처리)
      if (app.workDays == null || app.workDays!.isEmpty) continue;
      
      // 🔥 퇴사일이 있으면 그 날짜까지만
      final endDate = app.actualResignDate ?? app.workEndDate;

      // 🔥 시작일 계산: desiredStartDate 우선 → confirmedAt → workDate
      DateTime effectiveStartDate = app.desiredStartDate ?? app.workDate;
      if (app.confirmedAt != null && app.desiredStartDate == null) {
        final confirmedDate = DateTime(
          app.confirmedAt!.year,
          app.confirmedAt!.month,
          app.confirmedAt!.day,
        );
        if (confirmedDate.isAfter(app.workDate)) {
          effectiveStartDate = confirmedDate;
        }
      }

      // 기간 체크 (시간 제거하고 날짜만 비교)
      final startDateOnly = DateTime(effectiveStartDate.year, effectiveStartDate.month, effectiveStartDate.day);

      if (endDate != null) {
        final endDateOnly = DateTime(endDate.year, endDate.month, endDate.day);
        if (dateStart.isBefore(startDateOnly) || dateStart.isAfter(endDateOnly)) {
          continue;
        }
      } else {
        // 퇴사일 없음 = 오픈 엔드 계약, 시작일 이후는 모두 포함
        if (dateStart.isBefore(startDateOnly)) {
          continue;
        }
      }

      // 🔥 휴무일 체크 - 휴무일이면 제외
      if (app.leaveDates != null && app.leaveDates!.isNotEmpty) {
        final isLeaveDay = app.leaveDates!.any((leaveDate) =>
            leaveDate.year == dateStart.year &&
            leaveDate.month == dateStart.month &&
            leaveDate.day == dateStart.day);
        if (isLeaveDay) continue;
      }

      // 요일 체크
      final dayWeekday = FormatHelper.weekday(dateStart);
      
      if (app.workDays!.contains(dayWeekday)) {
        result.add(app);
        longTermCount++;
      }
    }
    
    debugPrint('📋 [당일명단] 장기 확정자: $longTermCount명');
    debugPrint('📋 [당일명단] 총 확정자: ${result.length}명');

    return result;
  }

  /// 출근 기록 조회
  Future<Map<String, AttendanceModel>> _getAttendanceRecords(
    List<String> applicationIds,
  ) async {
    if (applicationIds.isEmpty) return {};

    final dateStart = DateTime(widget.date.year, widget.date.month, widget.date.day);
    final dateEnd = dateStart.add(const Duration(days: 1));

    final snapshot = await FirebaseFirestore.instance
        .collection('attendance')
        .where('businessId', isEqualTo: _selectedBusinessId)
        .where('workDate', isGreaterThanOrEqualTo: Timestamp.fromDate(dateStart))
        .where('workDate', isLessThan: Timestamp.fromDate(dateEnd))
        .get();

    final Map<String, AttendanceModel> attendanceMap = {};

    for (var doc in snapshot.docs) {
      final attendance = AttendanceModel.fromFirestore(doc);
      attendanceMap[attendance.applicationId] = attendance;
    }

    return attendanceMap;
  }

  /// 사용자 정보 일괄 조회
  Future<Map<String, UserModel>> _getUserInfoBatch(List<String> uids) async {
    if (uids.isEmpty) return {};

    final Map<String, UserModel> userMap = {};

    // 배치로 조회 (10개씩)
    for (int i = 0; i < uids.length; i += 10) {
      final chunk = uids.skip(i).take(10).toList();

      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .where(FieldPath.documentId, whereIn: chunk)
          .get();

      for (var doc in snapshot.docs) {
        final user = UserModel.fromMap(doc.data(), doc.id);
        userMap[doc.id] = user;
      }
    }

    return userMap;
  }

  /// 업무유형 정보 조회
  Future<Map<String, BusinessWorkTypeModel>> _getWorkTypeInfo() async {
    final Map<String, BusinessWorkTypeModel> workTypeMap = {};
    
    if (_selectedBusinessId == null) return workTypeMap;

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('businesses')
          .doc(_selectedBusinessId)
          .collection('workTypes')
          .where('isActive', isEqualTo: true)
          .get();

      for (var doc in snapshot.docs) {
        final workType = BusinessWorkTypeModel.fromFirestore(doc);
        workTypeMap[workType.name] = workType;
      }
    } catch (e) {
      debugPrint('업무유형 조회 실패: $e');
    }

    return workTypeMap;
  }

  // ═══════════════════════════════════════════════════════════
  // 유틸리티 메서드
  // ═══════════════════════════════════════════════════════════

  /// 사용자 표시명 (이름만)
  String _getDisplayName(String uid) {
    final user = _userMap[uid];
    return user?.name ?? 'Unknown';
  }

  /// 성별/나이 표시 문자열
  String _getGenderAge(String uid) {
    final user = _userMap[uid];
    if (user == null) return '';

    final parts = <String>[];
    if (user.age != null) parts.add('${user.age}');
    if (user.gender != null) {
      final genderShort = user.gender == '남성' ? '남' : '여';
      parts.add(genderShort);
    }
    
    return parts.isNotEmpty ? '(${parts.join(', ')})' : '';
  }

  /// 출퇴근 상태 판단 (UI 레벨 — DB status와 별개)
  Map<String, dynamic> _getAttendanceStatus(ApplicationModel app) {
    final attendance = _attendanceMap[app.id];
    final expectedStart = app.startTime.isNotEmpty ? app.startTime : '09:00';
    final expectedEnd   = app.endTime.isNotEmpty   ? app.endTime   : '18:00';

    // 노쇼
    if (attendance?.status == AttendanceModel.statusNoShow) {
      return {
        'status': 'noshow',
        'color': AppColors.error,
        'icon': Icons.cancel,
        'text': '노쇼',
        'timeText': null,
        'isPast': false,
      };
    }

    // 퇴근 완료
    if (attendance?.checkOut != null) {
      final timeText = '${_trimSeconds(attendance!.checkIn!)} ~ ${_trimSeconds(attendance.checkOut!)}';

      // 조퇴 판단 — 출근 시간 기준으로 익일 자정 넘김 보정
      final isEarly = AttendanceStatusHelper.isEarlyLeave(
          attendance.checkOut!, expectedEnd, checkIn: attendance.checkIn);

      // 최종 확정
      if (attendance.wageStatus == AttendanceModel.wageConfirmed) {
        return {
          'status': 'final_confirmed',
          'color': AppColors.success,
          'icon': Icons.verified,
          'text': isEarly ? '최종확정(조퇴)' : '최종확정',
          'timeText': timeText,
          'isPast': false,
        };
      }
      // 급여 확정
      if (attendance.wageStatus == AttendanceModel.wageCalculated) {
        return {
          'status': 'wage_confirmed',
          'color': AppColors.warning,
          'icon': Icons.paid,
          'text': isEarly ? '급여확정(조퇴)' : '급여확정',
          'timeText': timeText,
          'isPast': false,
        };
      }
      // 조퇴
      if (isEarly) {
        return {
          'status': 'early_leave',
          'color': AppColors.warningDark,
          'icon': Icons.directions_run,
          'text': '조퇴',
          'timeText': timeText,
          'isPast': false,
        };
      }
      // 정상 퇴근
      return {
        'status': 'checkout',
        'color': AppColors.purple,
        'icon': Icons.home,
        'text': '퇴근',
        'timeText': timeText,
        'isPast': false,
      };
    }

    // 출근 완료 (퇴근 미체크)
    if (attendance?.checkIn != null) {
      final isLate = AttendanceStatusHelper.isLate(attendance!.checkIn!, expectedStart);
      // 과거 날짜이고 퇴근을 안 찍은 경우 → 퇴근 미체크 경고
      final isPastDay = widget.date.isBefore(
        DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day),
      );
      if (isPastDay) {
        return {
          'status': 'missed_checkout',
          'color': AppColors.error,
          'icon': Icons.logout,
          'text': isLate ? '지각·퇴근미체크' : '퇴근미체크',
          'timeText': _trimSeconds(attendance.checkIn!),
          'isPast': true,
        };
      }
      if (isLate) {
        return {
          'status': 'late',
          'color': AppColors.warning,
          'icon': Icons.warning_amber,
          'text': '지각',
          'timeText': _trimSeconds(attendance.checkIn!),
          'isPast': false,
        };
      }
      return {
        'status': 'checkin',
        'color': AppColors.success,
        'icon': Icons.check_circle,
        'text': '출근',
        'timeText': _trimSeconds(attendance.checkIn!),
        'isPast': false,
      };
    }

    // 미출근
    return {
      'status': 'pending',
      'color': AppColors.grey500,
      'icon': Icons.schedule,
      'text': '미출근',
      'timeText': null,
      'isPast': false,
    };
  }

  /// "HH:mm:ss" → "HH:mm"  (초 제거)
  String _trimSeconds(String timeStr) {
    final parts = timeStr.split(':');
    if (parts.length < 2) return timeStr;
    return '${parts[0]}:${parts[1]}';
  }



  /// 통계 계산
  Map<String, int> _calculateStats() {
    int total = _confirmedWorkers.length;
    int checkedIn = 0;
    int checkedOut = 0;
    int late = 0;
    int earlyLeave = 0;
    int missedCheckout = 0;
    int noShow = 0;

    for (var app in _confirmedWorkers) {
      final s = _getAttendanceStatus(app)['status'] as String;
      switch (s) {
        case 'checkout':
        case 'wage_confirmed':
        case 'final_confirmed':
          checkedIn++;
          checkedOut++;
          break;
        case 'early_leave':
          checkedIn++;
          checkedOut++;
          earlyLeave++;
          break;
        case 'checkin':
          checkedIn++;
          break;
        case 'late':
          checkedIn++;
          late++;
          break;
        case 'missed_checkout':
          checkedIn++;
          missedCheckout++;
          break;
        case 'noshow':
          noShow++;
          break;
      }
    }

    return {
      'total': total,
      'checkedIn': checkedIn,
      'checkedOut': checkedOut,
      'notCheckedIn': total - checkedIn - noShow,
      'late': late,
      'earlyLeave': earlyLeave,
      'missedCheckout': missedCheckout,
      'noShow': noShow,
    };
  }

  // ═══════════════════════════════════════════════════════════
  // BUILD 메서드
  // ═══════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dateStr = DateFormat('MM월 dd일 (E)', 'ko_KR').format(widget.date);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          Navigator.pop(context, _hasChanges);
        }
      },
      child: Dialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(ResponsiveHelper.spacing(context, 24)),
        ),
        child: Container(
          width: MediaQuery.of(context).size.width * 0.95,
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.9,
          ),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(ResponsiveHelper.spacing(context, 24)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.1),
                blurRadius: 30,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 헤더
              _buildHeader(theme, dateStr),

              // 내용
              Flexible(
                child: _isLoading
                    ? const LoadingWidget(message: '당일명단 조회 중...')
                    : _confirmedWorkers.isEmpty
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

  /// 헤더 (그라데이션 + 사업장 드롭다운)
  Widget _buildHeader(ThemeData theme, String dateStr) {
    return Container(
      padding: ResponsiveHelper.cardPadding(context),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            theme.primaryColor,
            theme.primaryColor.withValues(alpha: 0.85),
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
                  Icons.how_to_reg,
                  color: Colors.white,
                  size: ResponsiveHelper.iconSize(context, 24),
                ),
              ),
              SizedBox(width: ResponsiveHelper.spacing(context, 12)),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '당일명단',
                      style: ResponsiveHelper.titleStyle(context).copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      dateStr,
                      style: ResponsiveHelper.smallStyle(context, color: Colors.white70),
                    ),
                  ],
                ),
              ),
              // 닫기 버튼
              Material(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(12),
                child: InkWell(
                  onTap: () => Navigator.pop(context),
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 8)),
                    child: Icon(
                      Icons.close,
                      color: Colors.white,
                      size: ResponsiveHelper.iconSize(context, 24),
                    ),
                  ),
                ),
              ),
            ],
          ),

          SizedBox(height: ResponsiveHelper.spacing(context, 16)),

          // 사업장 선택
          AppSelectField<String>(
            value: _selectedBusinessId,
            hintText: '사업장을 선택하세요',
            sheetTitle: '사업장 선택',
            items: widget.businessIds,
            labelOf: (id) => _businessNameMap[id] ?? id,
            prefixIcon: Icons.business,
            onChanged: (value) {
              if (value != null && value != _selectedBusinessId) {
                setState(() => _selectedBusinessId = value);
                _loadData();
              }
            },
          ),
        ],
      ),
    );
  }

  /// 빈 상태
  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 40)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.people_outline,
              size: ResponsiveHelper.iconSize(context, 64),
              color: AppColors.grey400,
            ),
            SizedBox(height: ResponsiveHelper.spacing(context, 16)),
            Text(
              '확정된 근무자가 없습니다',
              style: ResponsiveHelper.subtitleStyle(context, color: AppColors.grey600),
            ),
          ],
        ),
      ),
    );
  }

  /// 메인 콘텐츠
  Widget _buildContent(ThemeData theme) {
    return SingleChildScrollView(
      padding: ResponsiveHelper.cardPadding(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(height: ResponsiveHelper.spacing(context, 8)),

          // 전체 통계
          _buildOverallStats(theme),

          SizedBox(height: ResponsiveHelper.spacing(context, 16)),

          // 전체 선택 + 일괄 버튼
          _buildBatchActionBar(theme),

          SizedBox(height: ResponsiveHelper.spacing(context, 16)),

          // 업무별 그룹
          _buildWorkTypeGroups(theme),
        ],
      ),
    );
  }

  /// 전체 통계 카드
  Widget _buildOverallStats(ThemeData theme) {
    final stats = _calculateStats();

    return Container(
      padding: ResponsiveHelper.cardPadding(context),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            theme.primaryColor.withValues(alpha: 0.08),
            theme.primaryColor.withValues(alpha: 0.04),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: theme.primaryColor.withValues(alpha: 0.2),
          width: 1.5,
        ),
      ),
      child: Column(
        children: [
          // 헤더
          Row(
            children: [
              Container(
                padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 8)),
                decoration: BoxDecoration(
                  color: theme.primaryColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.assessment_outlined,
                  color: theme.primaryColor,
                  size: ResponsiveHelper.iconSize(context, 22),
                ),
              ),
              SizedBox(width: ResponsiveHelper.spacing(context, 12)),
              Text(
                '전체 통계',
                style: ResponsiveHelper.subtitleStyle(context).copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),

          SizedBox(height: ResponsiveHelper.spacing(context, 20)),

          // 통계 그리드
          Row(
            children: [
              Expanded(child: _buildStatItem('확정', '${stats['total']}명', Icons.people_outline, AppColors.info)),
              Expanded(child: _buildStatItem('출근', '${stats['checkedIn']}명', Icons.login, AppColors.success)),
              Expanded(child: _buildStatItem('미출근', '${stats['notCheckedIn']}명', Icons.schedule, AppColors.warning)),
              Expanded(child: _buildStatItem('노쇼', '${stats['noShow']}명', Icons.cancel, AppColors.error)),
            ],
          ),

          // 추가 상세 통계
          if (stats['late']! > 0 ||
              stats['earlyLeave']! > 0 ||
              stats['missedCheckout']! > 0 ||
              stats['checkedOut']! > 0) ...[
            SizedBox(height: ResponsiveHelper.spacing(context, 12)),
            Divider(color: theme.dividerColor),
            SizedBox(height: ResponsiveHelper.spacing(context, 12)),
            Wrap(
              spacing: ResponsiveHelper.spacing(context, 20),
              runSpacing: ResponsiveHelper.spacing(context, 8),
              alignment: WrapAlignment.center,
              children: [
                if (stats['late']! > 0)
                  _buildMiniStat('지각', stats['late']!, AppColors.warning),
                if (stats['earlyLeave']! > 0)
                  _buildMiniStat('조퇴', stats['earlyLeave']!, AppColors.warningDark),
                if (stats['missedCheckout']! > 0)
                  _buildMiniStat('퇴근미체크', stats['missedCheckout']!, AppColors.error),
                _buildMiniStat('퇴근완료', stats['checkedOut']!, AppColors.purple),
              ],
            ),
          ],
        ],
      ),
    );
  }

  /// 통계 아이템
  Widget _buildStatItem(String label, String value, IconData icon, Color color) {
    return Column(
      children: [
        Container(
          padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 10)),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withValues(alpha: 0.3), width: 1),
          ),
          child: Icon(
            icon,
            color: color,
            size: ResponsiveHelper.iconSize(context, 22),
          ),
        ),
        SizedBox(height: ResponsiveHelper.spacing(context, 8)),
        Text(
          label,
          style: ResponsiveHelper.tinyStyle(context, color: AppColors.grey600),
        ),
        SizedBox(height: ResponsiveHelper.spacing(context, 2)),
        Text(
          value,
          style: ResponsiveHelper.bodyStyle(context).copyWith(
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }

  /// 미니 통계
  Widget _buildMiniStat(String label, int count, Color color) {
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        SizedBox(width: ResponsiveHelper.spacing(context, 6)),
        Text(
          '$label: $count명',
          style: ResponsiveHelper.smallStyle(context, color: AppColors.grey700),
        ),
      ],
    );
  }

  /// 일괄 처리 액션 바
  Widget _buildBatchActionBar(ThemeData theme) {
    // 선택된 직원들의 상태별 실제 처리 가능 인원 계산
    int checkInCount = 0;   // 미출근(pending) → 출근 가능
    int adjustCount = 0;    // 출근 기록 있음 → 시간조정 가능
    int checkOutCount = 0;  // 출근 완료 → 퇴근 가능

    for (final id in _selectedIds) {
      final app = _confirmedWorkers.firstWhere((a) => a.id == id);
      final s = _getAttendanceStatus(app)['status'] as String;
      if (s == 'pending') {
        checkInCount++;
      } else {
        adjustCount++;
        if (s == 'checkin' || s == 'late' || s == 'missed_checkout') {
          checkOutCount++;
        }
      }
    }

    return Container(
      padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 12)),
      decoration: BoxDecoration(
        color: AppColors.grey100,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Row 1: 전체 선택 + 스마트 선택 칩
          Row(
            children: [
              AppCheckbox(
                value: _selectAll,
                onTap: () => _toggleSelectAll(!_selectAll),
              ),
              SizedBox(width: ResponsiveHelper.spacing(context, 8)),
              Text('전체', style: ResponsiveHelper.bodyStyle(context)),
              if (_selectedIds.isNotEmpty) ...[
                SizedBox(width: ResponsiveHelper.spacing(context, 6)),
                Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: ResponsiveHelper.spacing(context, 8),
                    vertical: ResponsiveHelper.spacing(context, 3),
                  ),
                  decoration: BoxDecoration(
                    color: theme.primaryColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${_selectedIds.length}명',
                    style: ResponsiveHelper.smallStyle(context, color: theme.primaryColor),
                  ),
                ),
              ],
              const Spacer(),
              // 스마트 선택: 미출근만
              _buildSmartSelectChip(
                label: '미출근만',
                onTap: () => _selectByStatus(['pending']),
              ),
              SizedBox(width: ResponsiveHelper.spacing(context, 6)),
              // 스마트 선택: 출근완료만
              _buildSmartSelectChip(
                label: '출근만',
                onTap: () => _selectByStatus(['checkin', 'late', 'missed_checkout']),
              ),
            ],
          ),

          SizedBox(height: ResponsiveHelper.spacing(context, 10)),

          // Row 2: 일괄 액션 버튼 — 실제 처리 가능 인원 표시
          Row(
            children: [
              Expanded(
                child: _buildActionButton(
                  icon: Icons.login,
                  label: '출근',
                  color: AppColors.success,
                  count: checkInCount,
                  onPressed: checkInCount > 0 ? () => _showBatchCheckInDialog() : null,
                ),
              ),
              SizedBox(width: ResponsiveHelper.spacing(context, 6)),
              Expanded(
                child: _buildActionButton(
                  icon: Icons.tune,
                  label: '시간조정',
                  color: AppColors.info,
                  count: adjustCount,
                  onPressed: adjustCount > 0 ? () => _showBatchAdjustTimeDialog() : null,
                ),
              ),
              SizedBox(width: ResponsiveHelper.spacing(context, 6)),
              Expanded(
                child: _buildActionButton(
                  icon: Icons.logout,
                  label: '퇴근',
                  color: AppColors.purple,
                  count: checkOutCount,
                  onPressed: checkOutCount > 0 ? () => _showBatchCheckOutDialog() : null,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 액션 버튼
  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required Color color,
    int count = 0,
    VoidCallback? onPressed,
  }) {
    final isEnabled = onPressed != null;

    return Material(
      color: isEnabled ? color.withValues(alpha: 0.1) : AppColors.grey200,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: ResponsiveHelper.spacing(context, 8),
            vertical: ResponsiveHelper.spacing(context, 8),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    icon,
                    size: ResponsiveHelper.iconSize(context, 15),
                    color: isEnabled ? color : AppColors.grey400,
                  ),
                  SizedBox(width: ResponsiveHelper.spacing(context, 4)),
                  Text(
                    label,
                    style: ResponsiveHelper.smallStyle(
                      context,
                      color: isEnabled ? color : AppColors.grey400,
                    ).copyWith(fontWeight: FontWeight.w600),
                  ),
                ],
              ),
              if (_selectedIds.isNotEmpty) ...[
                SizedBox(height: ResponsiveHelper.spacing(context, 3)),
                Text(
                  isEnabled ? '$count명' : '0명',
                  style: ResponsiveHelper.tinyStyle(
                    context,
                    color: isEnabled ? color : AppColors.grey400,
                  ).copyWith(fontWeight: FontWeight.bold),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// 업무별 그룹
  Widget _buildWorkTypeGroups(ThemeData theme) {
    // ✅ workType + 시간 조합으로 그룹화 (장기/단기 합침)
    final Map<String, List<ApplicationModel>> workTypeGroups = {};

    for (var app in _confirmedWorkers) {
      // 항상 workType + startTime + endTime 조합으로 그룹화
      final groupKey = '${app.selectedWorkType}_${app.startTime}_${app.endTime}';
      
      workTypeGroups.putIfAbsent(groupKey, () => []);
      workTypeGroups[groupKey]!.add(app);
    }

    // 각 그룹 내 이름순 정렬
    for (var workers in workTypeGroups.values) {
      workers.sort((a, b) {
        final userA = _userMap[a.uid];
        final userB = _userMap[b.uid];
        if (userA == null || userB == null) return 0;
        return userA.name.compareTo(userB.name);
      });
    }

    // 업무명 → 시작시간 → 종료시간 순 정렬
    final sortedEntries = workTypeGroups.entries.toList()
      ..sort((a, b) {
        final appA = a.value.first;
        final appB = b.value.first;

        final typeCompare = appA.selectedWorkType.compareTo(appB.selectedWorkType);
        if (typeCompare != 0) return typeCompare;

        final timeCompare = appA.startTime.compareTo(appB.startTime);
        if (timeCompare != 0) return timeCompare;

        return appA.endTime.compareTo(appB.endTime);
      });

    return Column(
      children: sortedEntries.map((entry) {
        // ✅ 그룹의 첫 번째 앱에서 실제 workType 추출
        final firstApp = entry.value.first;
        final displayWorkType = firstApp.selectedWorkType;
        final displayStartTime = firstApp.startTime;
        final displayEndTime = firstApp.endTime;
        
        return Padding(
          padding: EdgeInsets.only(bottom: ResponsiveHelper.spacing(context, 16)),
          child: _buildWorkTypeSection(
            theme, 
            displayWorkType, 
            entry.value,
            startTime: displayStartTime,
            endTime: displayEndTime,
          ),
        );
      }).toList(),
    );
  }

  /// 업무 유형 섹션
  Widget _buildWorkTypeSection(
    ThemeData theme, 
    String workType, 
    List<ApplicationModel> workers, {
    String? startTime,
    String? endTime,
  }) {
    // ✅ 파라미터로 받은 시간 우선 사용
    String timeStr = '';
    if (startTime != null && startTime.isNotEmpty && 
        endTime != null && endTime.isNotEmpty) {
      timeStr = '$startTime ~ $endTime';
    }
    
    // 폴백: WorkDetail에서 시간 조회 (composite key 우선, workType 폴백)
    if (timeStr.isEmpty) {
      final compositeKey = startTime != null && endTime != null
          ? '${workType}_${startTime}_$endTime'
          : null;
      final workDetailTime = (compositeKey != null ? _workDetailTimeMap[compositeKey] : null)
          ?? _workDetailTimeMap[workType];
      if (workDetailTime != null) {
        final wdStartTime = workDetailTime['startTime'] ?? '';
        final wdEndTime = workDetailTime['endTime'] ?? '';
        if (wdStartTime.isNotEmpty && wdEndTime.isNotEmpty) {
          timeStr = '$wdStartTime ~ $wdEndTime';
        }
      }
    }
    
    // 최종 폴백: Application에서 시간 정보 가져오기
    if (timeStr.isEmpty && workers.isNotEmpty) {
      final firstApp = workers.first;
      if (firstApp.startTime.isNotEmpty && firstApp.endTime.isNotEmpty) {
        timeStr = '${firstApp.startTime} ~ ${firstApp.endTime}';
      }
    }
    
    // 업무유형 정보 가져오기
    final workTypeInfo = _workTypeMap[workType];
    final iconColor = workTypeInfo?.color != null 
        ? FormatHelper.parseColor(workTypeInfo!.color!)
        : theme.primaryColor;
    final bgColor = workTypeInfo?.backgroundColor != null
        ? FormatHelper.parseColor(workTypeInfo!.backgroundColor!)
        : theme.primaryColor.withValues(alpha: 0.1);

    return Container(
      decoration: BoxDecoration(
        color: AppColors.grey50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 업무 유형 헤더
          Builder(builder: (ctx) {
            // 파트 내 출근 현황 계산
            final checkedInCount = workers.where((a) {
              final s = _getAttendanceStatus(a)['status'] as String;
              return s != 'pending' && s != 'noshow';
            }).length;
            final noShowCount = workers.where((a) {
              return (_getAttendanceStatus(a)['status'] as String) == 'noshow';
            }).length;
            final selectableWorkers = workers.where((a) {
              return (_getAttendanceStatus(a)['status'] as String) != 'noshow';
            }).toList();
            final allSelected = selectableWorkers.isNotEmpty &&
                selectableWorkers.every((a) => _selectedIds.contains(a.id));

            final attendBadgeColor = checkedInCount == workers.length - noShowCount
                ? AppColors.success
                : checkedInCount > 0
                    ? AppColors.warning
                    : AppColors.grey500;

            return GestureDetector(
              onTap: () {
                setState(() {
                  if (allSelected) {
                    for (final a in selectableWorkers) { _selectedIds.remove(a.id); }
                  } else {
                    for (final a in selectableWorkers) { _selectedIds.add(a.id); }
                  }
                  final total = _confirmedWorkers.where((a) =>
                      (_getAttendanceStatus(a)['status'] as String) != 'noshow').length;
                  _selectAll = _selectedIds.length >= total;
                });
              },
              child: Container(
                padding: ResponsiveHelper.cardPadding(context),
                decoration: BoxDecoration(
                  color: theme.primaryColor.withValues(alpha: 0.05),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(16),
                    topRight: Radius.circular(16),
                  ),
                ),
                child: Row(
                  children: [
                    // 파트 체크박스
                    AppCheckbox(value: allSelected),
                    SizedBox(width: ResponsiveHelper.spacing(context, 10)),
                    // 업무유형 아이콘
                    Container(
                      padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 8)),
                      decoration: BoxDecoration(
                        color: bgColor,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: workTypeInfo != null
                          ? WorkTypeIcon.build(
                              workTypeInfo,
                              color: iconColor,
                              size: ResponsiveHelper.iconSize(context, 20),
                            )
                          : Icon(
                              Icons.work_outline,
                              color: iconColor,
                              size: ResponsiveHelper.iconSize(context, 20),
                            ),
                    ),
                    SizedBox(width: ResponsiveHelper.spacing(context, 12)),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            workType,
                            style: ResponsiveHelper.subtitleStyle(context).copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          if (timeStr.isNotEmpty)
                            Text(
                              timeStr,
                              style: ResponsiveHelper.smallStyle(context, color: AppColors.grey600),
                            ),
                        ],
                      ),
                    ),
                    // 출근 현황 배지
                    Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: ResponsiveHelper.spacing(context, 10),
                        vertical: ResponsiveHelper.spacing(context, 5),
                      ),
                      decoration: BoxDecoration(
                        color: attendBadgeColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: attendBadgeColor.withValues(alpha: 0.4)),
                      ),
                      child: Text(
                        '출근 $checkedInCount/${workers.length - noShowCount}',
                        style: ResponsiveHelper.tinyStyle(context, color: attendBadgeColor)
                            .copyWith(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),

          // 근무자 목록
          Padding(
            padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 12)),
            child: Column(
              children: workers.map((app) => _buildWorkerCard(app)).toList(),
            ),
          ),
        ],
      ),
    );
  }

  /// 퇴근 미처리 여부: 출근은 했으나 퇴근 미처리 + 예정 퇴근시간 초과
  bool _isMissedCheckout(ApplicationModel app) {
    final s = _getAttendanceStatus(app)['status'] as String;
    if (s != 'checkin' && s != 'late') return false;
    if (app.endTime.isEmpty) return false;
    final parts = app.endTime.split(':');
    if (parts.length != 2) return false;
    final endH = int.tryParse(parts[0]);
    final endM = int.tryParse(parts[1]);
    if (endH == null || endM == null) return false;
    final now = DateTime.now();
    final endAt = DateTime(now.year, now.month, now.day, endH, endM);
    return now.isAfter(endAt);
  }

  /// 근무자 카드
  Widget _buildWorkerCard(ApplicationModel app) {
    final theme = Theme.of(context);
    final statusInfo = _getAttendanceStatus(app);
    final isSelected = _selectedIds.contains(app.id);
    final displayName = _getDisplayName(app.uid);
    final genderAge = _getGenderAge(app.uid);
    final overdueCheckout = _isMissedCheckout(app);

    return Container(
      margin: EdgeInsets.only(bottom: ResponsiveHelper.spacing(context, 8)),
      decoration: BoxDecoration(
        color: isSelected
            ? theme.primaryColor.withValues(alpha: 0.08)
            : overdueCheckout
                ? AppColors.warning.withValues(alpha: 0.04)
                : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isSelected
              ? theme.primaryColor
              : overdueCheckout
                  ? AppColors.warning.withValues(alpha: 0.6)
                  : AppColors.border,
          width: isSelected || overdueCheckout ? 1.5 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _toggleSelection(app.id),
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 12)),
            child: Row(
              children: [
                // 체크박스 (행 InkWell이 탭 처리)
                AppCheckbox(value: isSelected),

                SizedBox(width: ResponsiveHelper.spacing(context, 12)),

                // 정보
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 장기 태그 + 이름 + 성별/나이
                      Row(
                        children: [
                          // 장기 배지 (이름 앞에)
                          if (app.isLongTermApplication) ...[
                            Container(
                              padding: EdgeInsets.symmetric(
                                horizontal: ResponsiveHelper.spacing(context, 6),
                                vertical: ResponsiveHelper.spacing(context, 2),
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.longTermBg,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                '장기',
                                style: ResponsiveHelper.tinyStyle(
                                  context,
                                  color: AppColors.longTermDark,
                                ).copyWith(fontWeight: FontWeight.bold),
                              ),
                            ),
                            SizedBox(width: ResponsiveHelper.spacing(context, 6)),
                          ],
                          // 이름
                          Text(
                            displayName,
                            style: ResponsiveHelper.bodyStyle(context).copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          // 성별/나이
                          if (genderAge.isNotEmpty) ...[
                            SizedBox(width: ResponsiveHelper.spacing(context, 4)),
                            Text(
                              genderAge,
                              style: ResponsiveHelper.smallStyle(context, color: AppColors.grey600),
                            ),
                          ],
                        ],
                      ),

                      SizedBox(height: ResponsiveHelper.spacing(context, 4)),

                      // 상태 뱃지 + 부가 정보
                      Row(
                        children: [
                          // 상태 뱃지
                          Container(
                            padding: EdgeInsets.symmetric(
                              horizontal: ResponsiveHelper.spacing(context, 8),
                              vertical: ResponsiveHelper.spacing(context, 2),
                            ),
                            decoration: BoxDecoration(
                              color: (statusInfo['color'] as Color).withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              statusInfo['text'] as String,
                              style: ResponsiveHelper.tinyStyle(
                                context,
                                color: statusInfo['color'] as Color,
                              ).copyWith(fontWeight: FontWeight.w600),
                            ),
                          ),

                          // 퇴근 미처리 경고 배지
                          if (overdueCheckout) ...[
                            SizedBox(width: ResponsiveHelper.spacing(context, 6)),
                            Container(
                              padding: EdgeInsets.symmetric(
                                horizontal: ResponsiveHelper.spacing(context, 7),
                                vertical: ResponsiveHelper.spacing(context, 2),
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.warning.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(
                                    color: AppColors.warning.withValues(alpha: 0.4)),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.warning_amber_rounded,
                                      size: ResponsiveHelper.iconSize(context, 11),
                                      color: AppColors.warning),
                                  SizedBox(width: ResponsiveHelper.spacing(context, 3)),
                                  Text(
                                    '퇴근 미처리',
                                    style: ResponsiveHelper.tinyStyle(context,
                                            color: AppColors.warning)
                                        .copyWith(fontWeight: FontWeight.w600),
                                  ),
                                ],
                              ),
                            ),
                          ],

                          // 주휴수당 발생 배지
                          if (_weeklyHolidayMap[app.id]?.isEligible == true) ...[
                            SizedBox(width: ResponsiveHelper.spacing(context, 6)),
                            Container(
                              padding: EdgeInsets.symmetric(
                                horizontal: ResponsiveHelper.spacing(context, 7),
                                vertical: ResponsiveHelper.spacing(context, 2),
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.success.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(color: AppColors.success.withValues(alpha: 0.4)),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.event_available,
                                      size: ResponsiveHelper.iconSize(context, 11),
                                      color: AppColors.successDark),
                                  SizedBox(width: ResponsiveHelper.spacing(context, 3)),
                                  Text(
                                    '주휴수당 발생',
                                    style: ResponsiveHelper.tinyStyle(context,
                                            color: AppColors.successDark)
                                        .copyWith(fontWeight: FontWeight.w600),
                                  ),
                                ],
                              ),
                            ),
                          ],

                          // 미출근일 때 시계 아이콘 + 위치 배지
                          if (statusInfo['status'] == 'pending') ...[
                            SizedBox(width: ResponsiveHelper.spacing(context, 4)),
                            Icon(
                              Icons.access_time,
                              size: ResponsiveHelper.iconSize(context, 14),
                              color: AppColors.grey500,
                            ),
                            _buildLocationBadge(app.id),
                          ],

                          // 시간 정보
                          if (statusInfo['timeText'] != null) ...[
                            SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                            Text(
                              statusInfo['timeText'] as String,
                              style: ResponsiveHelper.smallStyle(context, color: AppColors.grey600),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),

                // 더보기 메뉴
                _buildMoreMenu(app, statusInfo),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 미출근 워커 위치 배지
  Widget _buildLocationBadge(String applicationId) {
    final loc = _locationMap[applicationId];
    if (loc == null || !loc.isActive || !loc.consentGiven) {
      return const SizedBox.shrink();
    }

    final distance = loc.distanceMeters;
    final Color dotColor;
    final String label;

    if (distance == null) {
      dotColor = AppColors.grey400;
      label = '위치확인중';
    } else if (distance <= 200) {
      dotColor = AppColors.successDark;
      label = loc.formattedDistance;
    } else if (distance <= 500) {
      dotColor = AppColors.warningDark;
      label = loc.formattedDistance;
    } else {
      dotColor = AppColors.errorDark;
      label = loc.formattedDistance;
    }

    return Padding(
      padding: EdgeInsets.only(left: ResponsiveHelper.spacing(context, 4)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
          ),
          SizedBox(width: ResponsiveHelper.spacing(context, 3)),
          Text(
            label,
            style: ResponsiveHelper.tinyStyle(context, color: dotColor)
                .copyWith(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  /// 더보기 버튼 → 바텀시트 실행
  Widget _buildMoreMenu(ApplicationModel app, Map<String, dynamic> statusInfo) {
    return IconButton(
      icon: Icon(
        Icons.more_vert,
        color: AppColors.grey400,
        size: ResponsiveHelper.iconSize(context, 20),
      ),
      padding: EdgeInsets.zero,
      constraints: BoxConstraints(
        minWidth: ResponsiveHelper.spacing(context, 36),
        minHeight: ResponsiveHelper.spacing(context, 36),
      ),
      onPressed: () => _showMoreMenuSheet(app, statusInfo),
    );
  }

  /// 더보기 바텀시트 — AppMenuSheet 공통 컴포넌트 사용
  void _showMoreMenuSheet(ApplicationModel app, Map<String, dynamic> statusInfo) {
    final status = statusInfo['status'] as String;
    final user = _userMap[app.uid];
    final primaryColor = Theme.of(context).primaryColor;

    // 상태별 액션 그룹 구성
    final List<List<AppMenuSheetItem>> actionGroups = [];

    // 그룹 1: 상세보기 (항상)
    actionGroups.add([
      AppMenuSheetItem(
        icon: Icons.person_outline,
        label: '상세보기',
        color: primaryColor,
        onTap: () {
          if (user != null) {
            WorkerDetailDialog.show(
              context: context,
              user: user,
              application: app,
              businessId: _selectedBusinessId,
              isConfirmed: true,
              showApprovalButtons: false,
              attendanceStatus: status,
              onStatusChanged: () {
                _hasChanges = true;
                _loadData();
              },
            );
          }
        },
      ),
    ]);

    // 그룹 2: 상태별 주요 액션
    if (status == 'pending') {
      actionGroups.add([
        AppMenuSheetItem(
          icon: Icons.login,
          label: '출근 처리',
          color: AppColors.success,
          onTap: () => _showCheckInDialog(app),
        ),
      ]);
      // 그룹 3: 위험 액션 (노쇼) - 별도 구분선
      actionGroups.add([
        AppMenuSheetItem(
          icon: Icons.person_off_outlined,
          label: '노쇼 처리',
          color: AppColors.error,
          isDanger: true,
          onTap: () => _markNoShow(app),
        ),
      ]);
    } else if (status == 'checkin' || status == 'late' || status == 'missed_checkout') {
      actionGroups.add([
        AppMenuSheetItem(
          icon: Icons.logout,
          label: status == 'missed_checkout' ? '퇴근 수동 입력' : '퇴근 처리',
          color: AppColors.purple,
          onTap: () => _showCheckOutDialog(app),
        ),
        AppMenuSheetItem(
          icon: Icons.schedule_outlined,
          label: '시간 수정',
          color: AppColors.info,
          onTap: () => _showEditTimeDialog(app),
        ),
      ]);
    } else if (status == 'checkout' || status == 'early_leave') {
      actionGroups.add([
        AppMenuSheetItem(
          icon: Icons.schedule_outlined,
          label: '시간 수정',
          color: AppColors.info,
          onTap: () => _showEditTimeDialog(app),
        ),
      ]);
    } else if (status == 'wage_confirmed') {
      actionGroups.add([
        AppMenuSheetItem(
          icon: Icons.edit_outlined,
          label: '급여 수정',
          color: AppColors.warning,
          onTap: () => _showEditWageDialog(app),
        ),
      ]);
      actionGroups.add([
        AppMenuSheetItem(
          icon: Icons.undo,
          label: '급여 취소',
          color: AppColors.error,
          isDanger: true,
          onTap: () => _processCancelWage(app),
        ),
      ]);
    } else if (status == 'final_confirmed') {
      actionGroups.add([
        AppMenuSheetItem(
          icon: Icons.receipt_long_outlined,
          label: '급여 상세',
          color: AppColors.success,
          onTap: () => _showViewWageDialog(app),
        ),
      ]);
      actionGroups.add([
        AppMenuSheetItem(
          icon: Icons.lock_open_outlined,
          label: '마감 취소',
          color: AppColors.warning,
          isDanger: true,
          onTap: () => _processCancelFinal(app),
        ),
      ]);
    } else if (status == 'noshow') {
      actionGroups.add([
        AppMenuSheetItem(
          icon: Icons.refresh,
          label: '노쇼 해제',
          color: AppColors.info,
          onTap: () => _cancelNoShow(app),
        ),
      ]);
    }

    AppMenuSheet.show(
      context: context,
      headerTitle: user?.name ?? '알 수 없음',
      headerSubtitle: '${app.selectedWorkType}  ${app.startTime}~${app.endTime}',
      headerAvatarLetter: user?.name.isNotEmpty == true ? user!.name[0] : '?',
      headerAvatarColor: primaryColor,
      itemGroups: actionGroups,
    );
  }

  /// 하단 버튼 바
  Widget _buildBottomBar(ThemeData theme) {
    return Container(
      padding: ResponsiveHelper.cardPadding(context),
      decoration: BoxDecoration(
        color: AppColors.grey50,
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(24),
          bottomRight: Radius.circular(24),
        ),
        border: Border(
          top: BorderSide(color: AppColors.border),
        ),
      ),
      child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 처리현황 + 마감 버튼
        _buildProgressRow(theme),
        SizedBox(height: ResponsiveHelper.spacing(context, 12)),
        // 기존 버튼들
        Row(
          children: [
            // 명단 출력 버튼
            Expanded(
            child: OutlinedButton.icon(
              onPressed: _confirmedWorkers.isNotEmpty ? _showPrintPreview : null,
              icon: Icon(Icons.print_outlined, size: ResponsiveHelper.iconSize(context, 18)),
              label: const Text('명단 출력'),
              style: OutlinedButton.styleFrom(
                foregroundColor: _confirmedWorkers.isNotEmpty ? theme.primaryColor : AppColors.grey500,
                side: BorderSide(
                  color: _confirmedWorkers.isNotEmpty ? theme.primaryColor : AppColors.grey300,
                ),
                padding: EdgeInsets.symmetric(
                  vertical: ResponsiveHelper.spacing(context, 12),
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),

          SizedBox(width: ResponsiveHelper.spacing(context, 12)),

          // 마감 버튼
          Expanded(
            child: ElevatedButton.icon(
              onPressed: _canClose ? _showFinalCloseDialog : null,
              icon: Icon(
                _isAllClosed ? Icons.lock : Icons.lock_outline, 
                size: ResponsiveHelper.iconSize(context, 18),
              ),
              label: Text(_isAllClosed ? '마감완료' : '마감'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _canClose 
                    ? AppColors.success 
                    : AppColors.grey300,
                foregroundColor: Colors.white,
                padding: EdgeInsets.symmetric(
                  vertical: ResponsiveHelper.spacing(context, 12),
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
            ],
          ),
        ],
      ),
    );
  }

  /// 처리현황 + 마감 버튼 Row
  Widget _buildProgressRow(ThemeData theme) {
    final isAllProcessed = _isAllProcessed;
    
    return Row(
      children: [
        Icon(
          isAllProcessed ? Icons.check_circle : Icons.pending,
          size: ResponsiveHelper.iconSize(context, 18),
          color: isAllProcessed ? AppColors.success : AppColors.grey500,
        ),
        SizedBox(width: ResponsiveHelper.spacing(context, 6)),
        Text(
          '처리현황: ',
          style: ResponsiveHelper.bodyStyle(context, color: AppColors.grey600),
        ),
        Text(
          '$_processedCount/${_confirmedWorkers.length}명',
          style: ResponsiveHelper.bodyStyle(context).copyWith(
            fontWeight: FontWeight.bold,
            color: isAllProcessed ? AppColors.success : theme.primaryColor,
          ),
        ),
        if (isAllProcessed)
          Text(' ✓', style: ResponsiveHelper.bodyStyle(context, color: AppColors.success)),
          const Spacer(),
          SizedBox(
            height: ResponsiveHelper.spacing(context, 36),
            child: ElevatedButton.icon(
              onPressed: _confirmedWorkers.isNotEmpty ? _showWageConfirmDialog : null,
              icon: Icon(Icons.payments, size: ResponsiveHelper.iconSize(context, 16)),
              label: Text(
                '급여관리',
                style: ResponsiveHelper.smallStyle(context, color: Colors.white).copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: _confirmedWorkers.isNotEmpty ? theme.primaryColor : AppColors.grey300,
              foregroundColor: Colors.white,
              padding: EdgeInsets.symmetric(
                horizontal: ResponsiveHelper.spacing(context, 16),
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// 마감 확인 다이얼로그
  Future<void> _showFinalCloseDialog() async {
    // 급여확정된 인원 수 계산
    int calculatedCount = 0;
    int noshowCount = 0;
    for (var app in _confirmedWorkers) {
      final attendance = _attendanceMap[app.id];
      if (attendance?.status == 'NO_SHOW') {
        noshowCount++;
      } else if (attendance?.wageStatus == 'calculated') {
        calculatedCount++;
      }
    }
    
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StyledDialog(
        title: '당일명단 마감',
        icon: Icons.lock_outline,
        headerColor: AppColors.success,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '마감 처리하시겠습니까?',
              style: ResponsiveHelper.bodyStyle(context),
            ),
            SizedBox(height: ResponsiveHelper.spacing(context, 16)),
            Container(
              padding: ResponsiveHelper.cardPadding(context),
              decoration: BoxDecoration(
                color: AppColors.grey100,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('급여확정 → 최종확정', style: ResponsiveHelper.smallStyle(context)),
                      Text('$calculatedCount명', style: ResponsiveHelper.bodyStyle(context).copyWith(fontWeight: FontWeight.bold)),
                    ],
                  ),
                  if (noshowCount > 0) ...[
                    SizedBox(height: ResponsiveHelper.spacing(context, 4)),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('노쇼', style: ResponsiveHelper.smallStyle(context, color: AppColors.error)),
                        Text('$noshowCount명', style: ResponsiveHelper.bodyStyle(context, color: AppColors.error)),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            SizedBox(height: ResponsiveHelper.spacing(context, 12)),
            Text(
              '※ 마감 후 지원자에게 급여내역이 표시됩니다.',
              style: ResponsiveHelper.smallStyle(context, color: AppColors.grey600),
            ),
          ],
        ),
        actions: [
          StyledDialogButton.cancel(
            onPressed: () => Navigator.pop(dialogContext, false),
          ),
          StyledDialogButton.primary(
            text: '마감하기',
            onPressed: () => Navigator.pop(dialogContext, true),
          ),
        ],
      ),
    );
    
    if (confirmed == true) {
      await _processFinalClose();
    }
  }

  /// 마감 처리 실행
  Future<void> _processFinalClose() async {


    final adminUid = Provider.of<UserProvider>(context, listen: false).currentUser?.uid;

    try {
      int successCount = 0;

      for (var app in _confirmedWorkers) {
        final attendance = _attendanceMap[app.id];
        if (attendance == null) continue;

        // 노쇼는 건너뜀
        if (attendance.status == 'NO_SHOW') continue;

        // 급여확정 상태만 최종확정으로 변경
        if (attendance.wageStatus == 'calculated') {
          await FirebaseFirestore.instance
              .collection('attendance')
              .doc(attendance.id)
              .update({
            'wageStatus': 'confirmed',
            'finalConfirmedAt': FieldValue.serverTimestamp(),
            if (adminUid != null) 'confirmedBy': adminUid,
          });
          
          // 🆕 근무 완료 신뢰도 반영 + totalWorkDays 증가
          final trustService = TrustScoreService();
          await trustService.onWorkComplete(app.uid);
          await FirebaseFirestore.instance
              .collection('users')
              .doc(app.uid)
              .update({
            'totalWorkDays': FieldValue.increment(1),
          });
          
          successCount++;
        }
      }
      
      _hasChanges = true;
      await _loadData();
      
      ToastHelper.showSuccess('$successCount명 최종확정 완료');
    } catch (e) {
      debugPrint('❌ 마감 처리 실패: $e');
      ToastHelper.showError('마감 처리 중 오류가 발생했습니다');
    }
  }

  /// 급여 확정 다이얼로그 열기
  Future<void> _showWageConfirmDialog() async {
    if (_confirmedWorkers.isEmpty) {
      ToastHelper.showWarning('급여 확정할 인원이 없습니다');
      return;
    }

    if (_selectedBusinessId == null) {
      ToastHelper.showWarning('사업장을 선택해주세요');
      return;
    }

    final businessName = _businessNameMap[_selectedBusinessId] ?? '사업장';

    // TO 수정 후 최신 nightIncluded 등이 반영되도록 항상 Firestore에서 재조회
    _workDetailTimeMap = await _getWorkDetailTimes();
    if (!mounted) return;

    final hasChanges = await showDialog<bool>(
      context: context,
      builder: (context) => WageConfirmDialog(
        date: widget.date,
        businessId: _selectedBusinessId!,
        businessName: businessName,
        workers: _confirmedWorkers,
        attendanceMap: _attendanceMap,
        userMap: _userMap,
        workDetailTimeMap: _workDetailTimeMap,
        onConfirmed: () {
          // 급여 확정 시 데이터 새로고침
          _loadData();
        },
      ),
    );

    // 변경사항 있으면 당일명단도 변경 표시
    if (hasChanges == true && mounted) {
      _hasChanges = true;
      await _loadData();
    }
  }

  // ═══════════════════════════════════════════════════════════
  // 명단 출력
  // ═══════════════════════════════════════════════════════════

  /// PDF 명단 미리보기 표시
  Future<void> _showPrintPreview() async {
    if (_confirmedWorkers.isEmpty) {
      ToastHelper.showWarning('출력할 인원이 없습니다');
      return;
    }

    // 로딩 다이얼로그 표시
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (loadingContext) => PopScope(
        canPop: false,
        child: Center(
          child: Container(
            padding: ResponsiveHelper.cardPadding(loadingContext),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(ResponsiveHelper.spacing(loadingContext, 16)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(),
                SizedBox(height: ResponsiveHelper.spacing(loadingContext, 16)),
                Text(
                  '명단 생성 중...',
                  style: ResponsiveHelper.bodyStyle(loadingContext),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    try {
      // 사업장 이름 가져오기
      final businessName = _businessNameMap[_selectedBusinessId] ?? '사업장';

      // 데이터 변환 (이미 로드된 _workDetailTimeMap 사용)
      final data = AttendanceListPdf.convertFromDialogData(
        businessName: businessName,
        date: widget.date,
        confirmedWorkers: _confirmedWorkers,
        userMap: _userMap,
        workTypeMap: _workDetailTimeMap,
      );

      // ✅ PDF 생성 (폰트는 generatePdf 내부에서 자동 로드)
      final pdfBytes = await AttendanceListPdf.generatePdf(data);

      // 로딩 닫기
      if (mounted) Navigator.pop(context);

      // ✅ 미리 생성된 PDF로 바로 미리보기 표시
      if (mounted) {
        await AttendanceListPdf.showPreviewWithBytes(
          context: context,
          data: data,
          pdfBytes: pdfBytes,
          confirmedWorkers: _confirmedWorkers,
          userMap: _userMap,
          businessName: businessName,
          date: widget.date,
        );
      }
    } catch (e, stack) {
      // 로딩 닫기
      if (mounted) Navigator.pop(context);
      
      debugPrint('❌ 명단 출력 실패: $e\n$stack');
      ToastHelper.showError('명단 출력 실패');
    }
  }

  /// 슬롯별 workDetails에서 업무유형별 시간·급여 정보 조회
  ///
  /// TO 템플릿이 아닌 슬롯 문서를 우선 읽어 날짜별 수정 사항을 반영한다.
  /// workers를 넘기면 해당 근무자들의 slotId 기반으로 조회; null이면 _confirmedWorkers 사용.
  Future<Map<String, dynamic>> _getWorkDetailTimes([List<ApplicationModel>? workers]) async {
    final Map<String, dynamic> timeInfoMap = {};

    final targetWorkers = workers ?? _confirmedWorkers;
    if (targetWorkers.isEmpty) return timeInfoMap;

    // 고유한 (toId, slotId) 쌍 수집
    final slotPairs = <String, String>{}; // toId → slotId
    final toIds = <String>{};             // slotId 없는 경우 TO 폴백용
    for (final app in targetWorkers) {
      if (app.toId == null || app.toId!.isEmpty) continue;
      if (app.slotId != null && app.slotId!.isNotEmpty) {
        slotPairs[app.toId!] = app.slotId!;
      } else {
        toIds.add(app.toId!);
      }
    }

    void extractFromWorkDetails(List<dynamic> raw) {
      for (var wd in raw) {
        final data = Map<String, dynamic>.from(wd as Map);
        final workType = data['workType'] as String? ?? '';
        final startTime = data['startTime'] as String? ?? '';
        final endTime = data['endTime'] as String? ?? '';
        if (workType.isEmpty) continue;
        final compositeKey = '${workType}_${startTime}_$endTime';
        final entry = {
          'startTime': startTime,
          'endTime': endTime,
          'wage': data['wage'] ?? 0,
          'wageType': data['wageType'] ?? 'hourly',
          'breakMinutes': data['breakMinutes'] ?? 0,
          'nightAllowanceApplied': data['nightAllowanceApplied'] ?? true,
          'nightIncluded': data['nightIncluded'] ?? false,
          'shiftType': data['shiftType'],
          'baseHourlyWage': data['baseHourlyWage'] as int?,
          'weeklyHolidayIncluded': data['weeklyHolidayIncluded'] as bool? ?? false,
          'scheduledDaysPerWeek': data['scheduledDaysPerWeek'] as int?,
        };
        timeInfoMap[compositeKey] = entry;
        timeInfoMap[workType] ??= entry; // 레거시 폴백 키 (마지막 값 덮어씀)
      }
    }

    try {
      // 슬롯 문서 병렬 조회
      final slotFutures = slotPairs.entries.map((e) => FirebaseFirestore.instance
          .collection('tos').doc(e.key)
          .collection('slots').doc(e.value)
          .get());
      final slotDocs = await Future.wait(slotFutures);
      for (final doc in slotDocs) {
        if (!doc.exists) continue;
        final raw = doc.data()?['workDetails'] as List<dynamic>?;
        if (raw != null && raw.isNotEmpty) extractFromWorkDetails(raw);
      }

      // slotId 없는 경우 TO 문서 폴백
      if (toIds.isNotEmpty) {
        final toFutures = toIds.map((id) =>
            FirebaseFirestore.instance.collection('tos').doc(id).get());
        final toDocs = await Future.wait(toFutures);
        for (final doc in toDocs) {
          if (!doc.exists) continue;
          final raw = doc.data()?['workDetails'] as List<dynamic>?;
          if (raw != null) extractFromWorkDetails(raw);
        }
      }
    } catch (e) {
      debugPrint('❌ WorkDetail 시간 조회 실패: $e');
    }

    return timeInfoMap;
  }

  /// 주휴수당 자격 일괄 계산 (UI 비동기 — _loadData 이후 호출)
  Future<void> _computeWeeklyHolidayEligibility(
    List<ApplicationModel> workers,
    Map<String, dynamic> workDetailTimeMap,
  ) async {
    final weekStart = WeekHelper.weekStart(widget.date);
    final weekEnd = WeekHelper.weekEnd(widget.date);

    // 주휴 별도지급 활성화 & 소정근로일 설정된 워커만 계산
    final targets = workers.where((app) {
      final detail = (app.workDetailId != null
              ? workDetailTimeMap[app.workDetailId]
              : null) ??
          workDetailTimeMap[app.selectedWorkType];
      if (detail is! Map<String, dynamic>) return false;
      final separate = detail['weeklyHolidayIncluded'] as bool? ?? false;
      final days = detail['scheduledDaysPerWeek'] as int?;
      return separate && days != null;
    }).toList();

    if (targets.isEmpty) return;

    // businessId별 주간 출근 일괄 조회
    final byBusiness = <String, List<ApplicationModel>>{};
    for (final app in targets) {
      byBusiness.putIfAbsent(app.businessId, () => []).add(app);
    }

    final result = <String, WeeklyHolidayEligibility>{};

    for (final entry in byBusiness.entries) {
      Map<String, List<AttendanceModel>> weeklyAttMap;
      try {
        weeklyAttMap = await _firestoreService.getWeeklyAttendanceByBusiness(
          businessId: entry.key,
          weekStart: weekStart,
          weekEnd: weekEnd,
        );
      } catch (e) {
        debugPrint('❌ 주휴 자격 조회 실패 (${entry.key}): $e');
        continue;
      }

      for (final app in entry.value) {
        final detail = ((app.workDetailId != null
                    ? workDetailTimeMap[app.workDetailId]
                    : null) ??
                workDetailTimeMap[app.selectedWorkType])
            as Map<String, dynamic>;
        final scheduledDays = detail['scheduledDaysPerWeek'] as int;
        final wage = detail['wage'] as int? ?? 0;

        final eligibility = _firestoreService.computeWeeklyHolidayEligibility(
          weeklyAttendances: weeklyAttMap[app.uid] ?? [],
          scheduledDaysPerWeek: scheduledDays,
          ordinaryHourlyWage: wage,
          weekStart: weekStart,
          weekEnd: weekEnd,
        );
        result[app.id] = eligibility;
      }
    }

    if (!mounted) return;
    setState(() {
      _weeklyHolidayMap = result;
    });
  }

  // ═══════════════════════════════════════════════════════════
  // 선택 관련 메서드
  // ═══════════════════════════════════════════════════════════

  /// 전체 선택/해제
  void _toggleSelectAll(bool value) {
    setState(() {
      _selectAll = value;
      if (value) {
        // 노쇼가 아닌 인원만 선택
        _selectedIds.clear();
        for (var app in _confirmedWorkers) {
          final status = _getAttendanceStatus(app);
          if (status['status'] != 'noshow') {
            _selectedIds.add(app.id);
          }
        }
      } else {
        _selectedIds.clear();
      }
    });
  }

  /// 상태 기반 스마트 선택
  void _selectByStatus(List<String> statuses) {
    setState(() {
      _selectedIds.clear();
      for (final app in _confirmedWorkers) {
        final s = _getAttendanceStatus(app)['status'] as String;
        if (statuses.contains(s)) {
          _selectedIds.add(app.id);
        }
      }
      final total = _confirmedWorkers.where((a) =>
          (_getAttendanceStatus(a)['status'] as String) != 'noshow').length;
      _selectAll = _selectedIds.length >= total;
    });
  }

  /// 스마트 선택 칩 위젯
  Widget _buildSmartSelectChip({required String label, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: ResponsiveHelper.spacing(context, 10),
          vertical: ResponsiveHelper.spacing(context, 5),
        ),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.border),
        ),
        child: Text(
          label,
          style: ResponsiveHelper.tinyStyle(context, color: AppColors.grey700)
              .copyWith(fontWeight: FontWeight.w600),
        ),
      ),
    );
  }

  /// 개별 선택/해제
  void _toggleSelection(String appId) {
    setState(() {
      if (_selectedIds.contains(appId)) {
        _selectedIds.remove(appId);
        _selectAll = false;
      } else {
        _selectedIds.add(appId);
        // 전체 선택 상태 체크
        final selectableCount = _confirmedWorkers.where((app) {
          final status = _getAttendanceStatus(app);
          return status['status'] != 'noshow';
        }).length;
        _selectAll = _selectedIds.length == selectableCount;
      }
    });
  }

  // ═══════════════════════════════════════════════════════════
  // 시간 입력 다이얼로그
  // ═══════════════════════════════════════════════════════════

  /// 시간 선택 다이얼로그 (휠 피커 바텀시트)
  Future<String?> _showTimePickerDialog({
    required String title,
    String? initialTime,
  }) async {
    TimeOfDay initial = TimeOfDay.now();
    
    if (initialTime != null) {
      try {
        final parts = initialTime.split(':');
        initial = TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
      } catch (e) {
        // 파싱 실패 시 현재 시간 사용
      }
    }

    final picked = await TimePickerBottomSheet.show(
      context: context,
      initialTime: initial,
      title: title,
      minuteInterval: 5,
      use24HourFormat: true,
    );

    if (picked != null) {
      return '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
    }
    return null;
  }

  /// 일괄 시간 조정 다이얼로그 (이미 출근/퇴근한 인원의 시간을 일괄 수정)
  Future<void> _showBatchAdjustTimeDialog() async {
    if (_selectedIds.isEmpty) return;

    // 선택된 인원 중 출근 기록이 있는 인원만 대상
    final targets = _selectedIds
        .map((id) => _confirmedWorkers.firstWhere((a) => a.id == id))
        .where((app) {
          final s = _getAttendanceStatus(app)['status'] as String;
          return s != 'pending' && s != 'noshow' && s != 'final_confirmed';
        })
        .toList();

    if (targets.isEmpty) {
      ToastHelper.showWarning('시간 조정 가능한 인원이 없습니다\n(출근 처리된 인원만 조정 가능)');
      return;
    }

    // 대표 예정 시간 (첫 번째 대상자 기준)
    final sampleApp = targets.first;
    final defaultCheckIn  = sampleApp.startTime.isNotEmpty ? sampleApp.startTime : '09:00';
    final defaultCheckOut = sampleApp.endTime.isNotEmpty   ? sampleApp.endTime   : '18:00';

    String? adjustCheckIn;
    String? adjustCheckOut;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (ctx, setDialogState) => Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          child: Container(
            width: 340,
            padding: ResponsiveHelper.cardPadding(context),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 헤더
                Row(
                  children: [
                    Container(
                      padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 10)),
                      decoration: BoxDecoration(
                        color: AppColors.info.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(Icons.tune, color: AppColors.info, size: ResponsiveHelper.iconSize(context, 24)),
                    ),
                    SizedBox(width: ResponsiveHelper.spacing(context, 12)),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '일괄 시간 조정',
                            style: ResponsiveHelper.subtitleStyle(context).copyWith(fontWeight: FontWeight.bold),
                          ),
                          Text(
                            '${targets.length}명 대상',
                            style: ResponsiveHelper.smallStyle(context, color: AppColors.grey600),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(dialogContext, false),
                      icon: Icon(Icons.close, color: AppColors.grey500, size: ResponsiveHelper.iconSize(context, 20)),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),

                SizedBox(height: ResponsiveHelper.spacing(context, 8)),
                Divider(color: AppColors.border),
                SizedBox(height: ResponsiveHelper.spacing(context, 8)),

                // 안내
                Container(
                  padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 10)),
                  decoration: BoxDecoration(
                    color: AppColors.infoBg,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.infoLight),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline, color: AppColors.infoDark, size: ResponsiveHelper.iconSize(context, 16)),
                      SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                      Expanded(
                        child: Text(
                          '입력한 시간으로만 조정됩니다.\n비워두면 해당 시간은 변경되지 않습니다.',
                          style: ResponsiveHelper.tinyStyle(context, color: AppColors.infoDark),
                        ),
                      ),
                    ],
                  ),
                ),

                SizedBox(height: ResponsiveHelper.spacing(context, 16)),

                // 출근 시간 조정
                _buildAdjustRow(
                  icon: Icons.login,
                  iconColor: AppColors.success,
                  iconBgColor: AppColors.successBg,
                  label: '출근 시간',
                  value: adjustCheckIn,
                  quickLabel: '예정($defaultCheckIn)',
                  onQuickTap: () => setDialogState(() => adjustCheckIn = defaultCheckIn),
                  onTap: () async {
                    final t = await _showTimePickerDialog(
                      title: '출근 시간 조정',
                      initialTime: adjustCheckIn ?? defaultCheckIn,
                    );
                    if (t != null) setDialogState(() => adjustCheckIn = t);
                  },
                  onClear: adjustCheckIn != null ? () => setDialogState(() => adjustCheckIn = null) : null,
                ),

                SizedBox(height: ResponsiveHelper.spacing(context, 10)),

                // 퇴근 시간 조정
                _buildAdjustRow(
                  icon: Icons.logout,
                  iconColor: AppColors.purple,
                  iconBgColor: AppColors.purpleBg,
                  label: '퇴근 시간',
                  value: adjustCheckOut,
                  quickLabel: '예정($defaultCheckOut)',
                  onQuickTap: () => setDialogState(() => adjustCheckOut = defaultCheckOut),
                  onTap: () async {
                    final t = await _showTimePickerDialog(
                      title: '퇴근 시간 조정',
                      initialTime: adjustCheckOut ?? defaultCheckOut,
                    );
                    if (t != null) setDialogState(() => adjustCheckOut = t);
                  },
                  onClear: adjustCheckOut != null ? () => setDialogState(() => adjustCheckOut = null) : null,
                ),

                SizedBox(height: ResponsiveHelper.spacing(context, 20)),

                // 버튼
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(dialogContext, false),
                        style: OutlinedButton.styleFrom(
                          padding: EdgeInsets.symmetric(vertical: ResponsiveHelper.spacing(context, 14)),
                          side: BorderSide(color: AppColors.grey300),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: Text('취소', style: ResponsiveHelper.bodyStyle(context, color: AppColors.grey600)),
                      ),
                    ),
                    SizedBox(width: ResponsiveHelper.spacing(context, 12)),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: (adjustCheckIn != null || adjustCheckOut != null)
                            ? () => Navigator.pop(dialogContext, true)
                            : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.info,
                          foregroundColor: Colors.white,
                          padding: EdgeInsets.symmetric(vertical: ResponsiveHelper.spacing(context, 14)),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: Text(
                          '조정하기',
                          style: ResponsiveHelper.bodyStyle(context, color: Colors.white).copyWith(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (confirmed == true) {
      await _processBatchAdjustTime(targets, adjustCheckIn, adjustCheckOut);
    }
  }

  /// 일괄 시간 조정 행 위젯
  Widget _buildAdjustRow({
    required IconData icon,
    required Color iconColor,
    required Color iconBgColor,
    required String label,
    required String? value,
    required String quickLabel,
    required VoidCallback onQuickTap,
    required VoidCallback onTap,
    VoidCallback? onClear,
  }) {
    return Container(
      padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 12)),
      decoration: BoxDecoration(
        color: value != null ? iconColor.withValues(alpha: 0.06) : AppColors.grey100,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: value != null ? iconColor.withValues(alpha: 0.3) : AppColors.border,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 8)),
            decoration: BoxDecoration(color: iconBgColor, borderRadius: BorderRadius.circular(8)),
            child: Icon(icon, color: iconColor, size: ResponsiveHelper.iconSize(context, 18)),
          ),
          SizedBox(width: ResponsiveHelper.spacing(context, 10)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: ResponsiveHelper.tinyStyle(context, color: AppColors.grey600)),
                Text(
                  value ?? '미설정',
                  style: ResponsiveHelper.bodyStyle(context).copyWith(
                    fontWeight: FontWeight.w600,
                    color: value != null ? iconColor : AppColors.grey400,
                  ),
                ),
              ],
            ),
          ),
          // 예정시간 퀵버튼
          GestureDetector(
            onTap: onQuickTap,
            child: Container(
              padding: EdgeInsets.symmetric(
                horizontal: ResponsiveHelper.spacing(context, 8),
                vertical: ResponsiveHelper.spacing(context, 4),
              ),
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                quickLabel,
                style: ResponsiveHelper.tinyStyle(context, color: iconColor).copyWith(fontWeight: FontWeight.bold),
              ),
            ),
          ),
          SizedBox(width: ResponsiveHelper.spacing(context, 6)),
          // 직접 입력
          GestureDetector(
            onTap: onTap,
            child: Container(
              padding: EdgeInsets.symmetric(
                horizontal: ResponsiveHelper.spacing(context, 8),
                vertical: ResponsiveHelper.spacing(context, 4),
              ),
              decoration: BoxDecoration(
                color: AppColors.grey200,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '직접',
                style: ResponsiveHelper.tinyStyle(context, color: AppColors.grey700).copyWith(fontWeight: FontWeight.bold),
              ),
            ),
          ),
          if (onClear != null) ...[
            SizedBox(width: ResponsiveHelper.spacing(context, 4)),
            GestureDetector(
              onTap: onClear,
              child: Icon(Icons.close, color: AppColors.grey400, size: ResponsiveHelper.iconSize(context, 16)),
            ),
          ],
        ],
      ),
    );
  }

  /// 일괄 시간 조정 처리
  Future<void> _processBatchAdjustTime(
    List<ApplicationModel> targets,
    String? newCheckIn,
    String? newCheckOut,
  ) async {
    try {
      int successCount = 0;
      int failCount = 0;

      for (final app in targets) {
        final attendance = _attendanceMap[app.id];
        if (attendance == null) continue;

        try {
          final effectiveCheckIn  = newCheckIn  ?? attendance.checkIn  ?? app.startTime;
          final effectiveCheckOut = newCheckOut ?? attendance.checkOut;

          final updates = <String, dynamic>{
            'isModified': true,
            'modifiedAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
            'status': _deriveStatus(app, effectiveCheckIn, effectiveCheckOut),
          };

          if (newCheckIn != null) {
            updates['checkIn'] = newCheckIn;
            updates['checkInMethod'] = 'manual';
          }
          if (newCheckOut != null) {
            updates['checkOut'] = newCheckOut;
            updates['checkOutMethod'] = 'manual';
          }
          if (effectiveCheckOut != null) {
            updates['workHours'] = _calcWorkHoursCompat(effectiveCheckIn, effectiveCheckOut);
          }

          await FirebaseFirestore.instance
              .collection('attendance')
              .doc(attendance.id)
              .update(updates);
          successCount++;
        } catch (_) {
          failCount++;
        }
      }

      if (successCount > 0) ToastHelper.showSuccess('$successCount명 시간 조정 완료');
      if (failCount > 0) ToastHelper.showWarning('$failCount명 처리 실패');

      _hasChanges = true;
      await _loadData();
    } catch (e) {
      debugPrint('❌ 일괄 시간 조정 실패: $e');
      ToastHelper.showError('일괄 시간 조정 실패');
    }
  }

  /// 일괄 출근 다이얼로그
  Future<void> _showBatchCheckInDialog() async {
    if (_selectedIds.isEmpty) return;

    // 파트별 그룹화
    final Map<String, List<ApplicationModel>> groups = {};
    for (final id in _selectedIds) {
      final app = _confirmedWorkers.firstWhere((a) => a.id == id);
      final key = '${app.selectedWorkType}_${app.startTime}_${app.endTime}';
      groups.putIfAbsent(key, () => []).add(app);
    }

    if (groups.length <= 1) {
      // 단일 파트 → 기존 시트
      final scheduledTimes = _selectedIds
          .map((id) => _confirmedWorkers.firstWhere((a) => a.id == id).startTime)
          .where((t) => t.isNotEmpty)
          .toSet()
          .toList();
      final time = await AttendanceQuickTimeSheet.show(
        context: context,
        title: '일괄 출근 (${_selectedIds.length}명)',
        scheduledTimes: scheduledTimes.isEmpty ? null : scheduledTimes,
        isCheckIn: true,
      );
      if (time != null) await _processBatchCheckIn(time);
    } else {
      // 복수 파트 → 파트별 다이얼로그
      final groupTimes = await _showBatchByGroupDialog(groups, isCheckIn: true);
      if (groupTimes != null) await _processBatchCheckInByGroup(groupTimes);
    }
  }

  /// 일괄 퇴근 다이얼로그
  Future<void> _showBatchCheckOutDialog() async {
    if (_selectedIds.isEmpty) return;

    // 출근했으나 퇴근 미처리 인원만 필터 (checkin / late / missed_checkout)
    final checkedInIds = _selectedIds.where((id) {
      final app = _confirmedWorkers.firstWhere((a) => a.id == id);
      final s = _getAttendanceStatus(app)['status'] as String;
      return s == 'checkin' || s == 'late' || s == 'missed_checkout';
    }).toList();

    if (checkedInIds.isEmpty) {
      ToastHelper.showWarning('출근 처리된 인원만 퇴근 처리할 수 있습니다');
      return;
    }

    // 파트별 그룹화 (퇴근 가능 인원 기준)
    final Map<String, List<ApplicationModel>> groups = {};
    for (final id in checkedInIds) {
      final app = _confirmedWorkers.firstWhere((a) => a.id == id);
      final key = '${app.selectedWorkType}_${app.startTime}_${app.endTime}';
      groups.putIfAbsent(key, () => []).add(app);
    }

    if (groups.length <= 1) {
      // 단일 파트 → 기존 시트
      final scheduledTimes = checkedInIds
          .map((id) => _confirmedWorkers.firstWhere((a) => a.id == id).endTime)
          .where((t) => t.isNotEmpty)
          .toSet()
          .toList();
      final time = await AttendanceQuickTimeSheet.show(
        context: context,
        title: '일괄 퇴근 (${checkedInIds.length}명)',
        scheduledTimes: scheduledTimes.isEmpty ? null : scheduledTimes,
        isCheckIn: false,
      );
      if (time != null) await _processBatchCheckOut(time, checkedInIds);
    } else {
      // 복수 파트 → 파트별 다이얼로그
      final groupTimes = await _showBatchByGroupDialog(groups, isCheckIn: false);
      if (groupTimes != null) await _processBatchCheckOutByGroup(groupTimes, checkedInIds);
    }
  }

  /// 파트별 시간 설정 다이얼로그 (출근/퇴근 공용)
  /// Returns: groupKey → time 맵, 취소 시 null
  Future<Map<String, String>?> _showBatchByGroupDialog(
    Map<String, List<ApplicationModel>> groups, {
    required bool isCheckIn,
  }) async {
    final now = DateTime.now();
    final roundedMin = (now.minute / 10).round() >= 6 ? 0 : (now.minute / 10).round() * 10;
    final roundedHour = (now.minute / 10).round() >= 6 ? (now.hour + 1) % 24 : now.hour;
    final nowStr =
        '${roundedHour.toString().padLeft(2, '0')}:${roundedMin.toString().padLeft(2, '0')}';

    final Map<String, String> selectedTimes = {};
    for (final entry in groups.entries) {
      final firstApp = entry.value.first;
      selectedTimes[entry.key] =
          isCheckIn ? (firstApp.startTime.isNotEmpty ? firstApp.startTime : nowStr)
                    : (firstApp.endTime.isNotEmpty ? firstApp.endTime : nowStr);
    }

    final actionColor = isCheckIn ? AppColors.success : AppColors.purple;
    final actionLabel = isCheckIn ? '출근' : '퇴근';
    final actionIcon = isCheckIn ? Icons.login : Icons.logout;
    final totalCount = groups.values.fold(0, (s, l) => s + l.length);

    return showDialog<Map<String, String>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final theme = Theme.of(ctx);
          return Dialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(ctx).size.height * 0.8,
                maxWidth: 420,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // ── 헤더 ──
                  Container(
                    padding: ResponsiveHelper.cardPadding(ctx),
                    decoration: BoxDecoration(
                      color: actionColor.withValues(alpha: 0.1),
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: EdgeInsets.all(ResponsiveHelper.spacing(ctx, 10)),
                          decoration: BoxDecoration(
                            color: actionColor.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(actionIcon, color: actionColor,
                              size: ResponsiveHelper.iconSize(ctx, 22)),
                        ),
                        SizedBox(width: ResponsiveHelper.spacing(ctx, 12)),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('파트별 일괄 $actionLabel',
                                  style: ResponsiveHelper.subtitleStyle(ctx)
                                      .copyWith(fontWeight: FontWeight.bold)),
                              Text('$totalCount명 선택 · ${groups.length}개 파트',
                                  style: ResponsiveHelper.smallStyle(ctx,
                                      color: AppColors.grey600)),
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.pop(dialogContext),
                          icon: const Icon(Icons.close, color: AppColors.grey500),
                          padding: EdgeInsets.zero,
                        ),
                      ],
                    ),
                  ),

                  // ── 바디 ──
                  Flexible(
                    child: SingleChildScrollView(
                      padding: ResponsiveHelper.cardPadding(ctx),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // 현재 시간 전체 설정 버튼
                          OutlinedButton.icon(
                            onPressed: () {
                              final n = DateTime.now();
                              final rs = (n.minute / 10).round();
                              final h = rs >= 6 ? (n.hour + 1) % 24 : n.hour;
                              final m = rs >= 6 ? 0 : rs * 10;
                              final t = '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
                              setDialogState(() {
                                for (final k in selectedTimes.keys.toList()) {
                                  selectedTimes[k] = t;
                                }
                              });
                            },
                            icon: Icon(Icons.access_time,
                                size: ResponsiveHelper.iconSize(ctx, 16),
                                color: AppColors.grey700),
                            label: Text('현재 시간으로 전체 설정',
                                style: ResponsiveHelper.smallStyle(ctx,
                                    color: AppColors.grey700)),
                            style: OutlinedButton.styleFrom(
                              side: BorderSide(color: AppColors.border),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10)),
                              padding: EdgeInsets.symmetric(
                                  vertical: ResponsiveHelper.spacing(ctx, 10)),
                            ),
                          ),

                          SizedBox(height: ResponsiveHelper.spacing(ctx, 14)),

                          // 파트별 행
                          ...groups.entries.map((entry) {
                            final groupKey = entry.key;
                            final workers = entry.value;
                            final firstApp = workers.first;
                            final workTypeInfo = _workTypeMap[firstApp.selectedWorkType];
                            final dotColor = workTypeInfo?.color != null
                                ? FormatHelper.parseColor(workTypeInfo!.color!)
                                : theme.primaryColor;

                            return Container(
                              margin: EdgeInsets.only(
                                  bottom: ResponsiveHelper.spacing(ctx, 10)),
                              padding: ResponsiveHelper.cardPadding(ctx),
                              decoration: BoxDecoration(
                                color: AppColors.grey50,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: AppColors.border),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // 파트명 + 인원
                                  Row(
                                    children: [
                                      Container(
                                        width: 10, height: 10,
                                        decoration: BoxDecoration(
                                            color: dotColor, shape: BoxShape.circle),
                                      ),
                                      SizedBox(width: ResponsiveHelper.spacing(ctx, 8)),
                                      Expanded(
                                        child: Text(
                                          firstApp.selectedWorkType,
                                          style: ResponsiveHelper.bodyStyle(ctx)
                                              .copyWith(fontWeight: FontWeight.bold),
                                        ),
                                      ),
                                      Container(
                                        padding: EdgeInsets.symmetric(
                                          horizontal: ResponsiveHelper.spacing(ctx, 8),
                                          vertical: ResponsiveHelper.spacing(ctx, 3),
                                        ),
                                        decoration: BoxDecoration(
                                          color: theme.primaryColor.withValues(alpha: 0.1),
                                          borderRadius: BorderRadius.circular(10),
                                        ),
                                        child: Text('${workers.length}명',
                                            style: ResponsiveHelper.tinyStyle(ctx,
                                                color: theme.primaryColor)),
                                      ),
                                    ],
                                  ),
                                  SizedBox(height: ResponsiveHelper.spacing(ctx, 4)),
                                  Text(
                                    '예정 ${firstApp.startTime} ~ ${firstApp.endTime}',
                                    style: ResponsiveHelper.smallStyle(ctx,
                                        color: AppColors.grey500),
                                  ),
                                  SizedBox(height: ResponsiveHelper.spacing(ctx, 10)),
                                  // 시간 표시 + 변경 버튼
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Container(
                                          padding: EdgeInsets.symmetric(
                                            horizontal: ResponsiveHelper.spacing(ctx, 14),
                                            vertical: ResponsiveHelper.spacing(ctx, 10),
                                          ),
                                          decoration: BoxDecoration(
                                            color: actionColor.withValues(alpha: 0.08),
                                            borderRadius: BorderRadius.circular(10),
                                            border: Border.all(
                                                color: actionColor.withValues(alpha: 0.3)),
                                          ),
                                          child: Row(
                                            children: [
                                              Icon(Icons.check_circle_outline,
                                                  size: ResponsiveHelper.iconSize(ctx, 15),
                                                  color: actionColor),
                                              SizedBox(width: ResponsiveHelper.spacing(ctx, 6)),
                                              Text(
                                                selectedTimes[groupKey] ?? '--:--',
                                                style: ResponsiveHelper.bodyStyle(ctx).copyWith(
                                                  color: actionColor,
                                                  fontWeight: FontWeight.bold,
                                                  letterSpacing: 1,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                      SizedBox(width: ResponsiveHelper.spacing(ctx, 8)),
                                      OutlinedButton(
                                        onPressed: () async {
                                          final t = await AttendanceQuickTimeSheet.show(
                                            context: ctx,
                                            title:
                                                '${firstApp.selectedWorkType} $actionLabel 시간',
                                            scheduledTimes: isCheckIn
                                                ? (firstApp.startTime.isNotEmpty
                                                    ? [firstApp.startTime]
                                                    : null)
                                                : (firstApp.endTime.isNotEmpty
                                                    ? [firstApp.endTime]
                                                    : null),
                                            isCheckIn: isCheckIn,
                                          );
                                          if (t != null) {
                                            setDialogState(() => selectedTimes[groupKey] = t);
                                          }
                                        },
                                        style: OutlinedButton.styleFrom(
                                          side: BorderSide(color: actionColor.withValues(alpha: 0.5)),
                                          foregroundColor: actionColor,
                                          shape: RoundedRectangleBorder(
                                              borderRadius: BorderRadius.circular(10)),
                                          padding: EdgeInsets.symmetric(
                                            horizontal: ResponsiveHelper.spacing(ctx, 14),
                                            vertical: ResponsiveHelper.spacing(ctx, 10),
                                          ),
                                        ),
                                        child: Text('변경',
                                            style: ResponsiveHelper.smallStyle(ctx,
                                                color: actionColor)
                                                .copyWith(fontWeight: FontWeight.bold)),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            );
                          }),
                        ],
                      ),
                    ),
                  ),

                  // ── 푸터 ──
                  Padding(
                    padding: ResponsiveHelper.cardPadding(ctx),
                    child: Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(dialogContext),
                            style: OutlinedButton.styleFrom(
                              side: BorderSide(color: AppColors.grey300),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
                              padding: EdgeInsets.symmetric(
                                  vertical: ResponsiveHelper.spacing(ctx, 14)),
                            ),
                            child: Text('취소',
                                style: ResponsiveHelper.bodyStyle(ctx,
                                    color: AppColors.grey700)
                                    .copyWith(fontWeight: FontWeight.w600)),
                          ),
                        ),
                        SizedBox(width: ResponsiveHelper.spacing(ctx, 12)),
                        Expanded(
                          flex: 2,
                          child: ElevatedButton(
                            onPressed: () => Navigator.pop(
                                dialogContext, Map<String, String>.from(selectedTimes)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: actionColor,
                              foregroundColor: Colors.white,
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
                              padding: EdgeInsets.symmetric(
                                  vertical: ResponsiveHelper.spacing(ctx, 14)),
                            ),
                            child: Text('$actionLabel 처리 ($totalCount명)',
                                style: ResponsiveHelper.bodyStyle(ctx,
                                    color: Colors.white)
                                    .copyWith(fontWeight: FontWeight.bold)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  /// 개별 출근 다이얼로그
  Future<void> _showCheckInDialog(ApplicationModel app) async {
    final userName = _getDisplayName(app.uid);

    final time = await AttendanceQuickTimeSheet.show(
      context: context,
      title: '$userName 출근',
      scheduledTimes: app.startTime.isNotEmpty ? [app.startTime] : null,
      isCheckIn: true,
    );

    if (time != null) {
      await _processCheckIn(app, time);
    }
  }

  /// 개별 퇴근 다이얼로그
  Future<void> _showCheckOutDialog(ApplicationModel app) async {
    final userName = _getDisplayName(app.uid);

    final time = await AttendanceQuickTimeSheet.show(
      context: context,
      title: '$userName 퇴근',
      scheduledTimes: app.endTime.isNotEmpty ? [app.endTime] : null,
      isCheckIn: false,
    );

    if (time != null) {
      await _processCheckOut(app, time);
    }
  }

  /// 시간 수정 다이얼로그
  Future<void> _showEditTimeDialog(ApplicationModel app) async {
    final attendance = _attendanceMap[app.id];
    if (attendance == null) return;

    final theme = Theme.of(context);
    final userName = _getDisplayName(app.uid);
    String? newCheckIn = attendance.checkIn;
    String? newCheckOut = attendance.checkOut;

    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          child: Container(
            width: 320,
            padding: ResponsiveHelper.cardPadding(context),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 헤더
                Container(
                  padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 12)),
                  decoration: BoxDecoration(
                    color: AppColors.info.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(
                    Icons.edit_outlined,
                    color: AppColors.info,
                    size: ResponsiveHelper.iconSize(context, 32),
                  ),
                ),
                
                SizedBox(height: ResponsiveHelper.spacing(context, 12)),
                
                Text(
                  '시간 수정',
                  style: ResponsiveHelper.subtitleStyle(context).copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                
                Text(
                  userName,
                  style: ResponsiveHelper.smallStyle(context, color: AppColors.grey600),
                ),
                
                SizedBox(height: ResponsiveHelper.spacing(context, 20)),
                
                // 출근 시간
                _buildTimeEditRow(
                  icon: Icons.login,
                  iconColor: AppColors.success,
                  iconBgColor: AppColors.successBg,
                  label: '출근 시간',
                  value: newCheckIn,
                  onTap: () async {
                    final time = await _showTimePickerDialog(
                      title: '출근 시간 수정',
                      initialTime: newCheckIn,
                    );
                    if (time != null) {
                      setDialogState(() => newCheckIn = time);
                    }
                  },
                  onDelete: newCheckIn != null
                      ? () => setDialogState(() {
                          newCheckIn = null;
                          newCheckOut = null; // 출근 삭제 시 퇴근도 함께 삭제
                        })
                      : null,
                ),
                
                SizedBox(height: ResponsiveHelper.spacing(context, 12)),
                
                // 퇴근 시간
                _buildTimeEditRow(
                  icon: Icons.logout,
                  iconColor: AppColors.purple,
                  iconBgColor: AppColors.purpleBg,
                  label: '퇴근 시간',
                  value: newCheckOut,
                  onTap: newCheckIn != null // 출근 있을 때만 퇴근 수정 가능
                      ? () async {
                          final time = await _showTimePickerDialog(
                            title: '퇴근 시간 수정',
                            initialTime: newCheckOut,
                          );
                          if (time != null) {
                            setDialogState(() => newCheckOut = time);
                          }
                        }
                      : () {
                          ToastHelper.showWarning('출근 시간을 먼저 입력해주세요');
                        },
                  onDelete: newCheckOut != null
                      ? () => setDialogState(() => newCheckOut = null)
                      : null,
                ),
                
                // 둘 다 삭제되면 안내 메시지
                if (newCheckIn == null) ...[
                  SizedBox(height: ResponsiveHelper.spacing(context, 12)),
                  Container(
                    padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 12)),
                    decoration: BoxDecoration(
                      color: AppColors.warningBg,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.info_outline,
                          color: AppColors.warning,
                          size: ResponsiveHelper.iconSize(context, 18),
                        ),
                        SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                        Expanded(
                          child: Text(
                            '저장 시 미출근 상태로 변경됩니다',
                            style: ResponsiveHelper.smallStyle(context, color: AppColors.warningDark),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                
                SizedBox(height: ResponsiveHelper.spacing(context, 24)),
                
                // 버튼
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(dialogContext, false),
                        style: OutlinedButton.styleFrom(
                          padding: EdgeInsets.symmetric(
                            vertical: ResponsiveHelper.spacing(context, 14),
                          ),
                          side: BorderSide(color: AppColors.grey300),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: Text(
                          '취소',
                          style: ResponsiveHelper.bodyStyle(context, color: AppColors.grey600),
                        ),
                      ),
                    ),
                    SizedBox(width: ResponsiveHelper.spacing(context, 12)),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () => Navigator.pop(dialogContext, true),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: theme.primaryColor,
                          foregroundColor: Colors.white,
                          padding: EdgeInsets.symmetric(
                            vertical: ResponsiveHelper.spacing(context, 14),
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: Text(
                          '저장',
                          style: ResponsiveHelper.bodyStyle(context, color: Colors.white).copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (result == true && (newCheckIn != attendance.checkIn || newCheckOut != attendance.checkOut)) {
      await _updateAttendanceTime(app, newCheckIn, newCheckOut);
    }
  }

  /// 시간 편집 행 위젯
  Widget _buildTimeEditRow({
    required IconData icon,
    required Color iconColor,
    required Color iconBgColor,
    required String label,
    String? value,
    required VoidCallback onTap,
    VoidCallback? onDelete,
  }) {
    return Container(
      padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 12)),
      decoration: BoxDecoration(
        color: AppColors.grey100,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 8)),
            decoration: BoxDecoration(
              color: iconBgColor,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: iconColor, size: ResponsiveHelper.iconSize(context, 20)),
          ),
          SizedBox(width: ResponsiveHelper.spacing(context, 12)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: ResponsiveHelper.smallStyle(context, color: AppColors.grey600),
                ),
                Text(
                  value ?? '-',
                  style: ResponsiveHelper.bodyStyle(context).copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          if (onDelete != null)
            IconButton(
              icon: Icon(Icons.close, color: AppColors.error, size: ResponsiveHelper.iconSize(context, 20)),
              onPressed: onDelete,
              constraints: BoxConstraints(),
              padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 4)),
            ),
          SizedBox(width: ResponsiveHelper.spacing(context, 4)),
          Material(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: ResponsiveHelper.spacing(context, 12),
                  vertical: ResponsiveHelper.spacing(context, 8),
                ),
                child: Text(
                  '변경',
                  style: ResponsiveHelper.smallStyle(context, color: iconColor).copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  // 출퇴근 처리 로직
  // ═══════════════════════════════════════════════════════════

  /// 근무 시간 계산 (HH:mm(:ss) → 시간 단위 double)
  double _calcWorkHoursCompat(String checkIn, String checkOut) =>
      AttendanceStatusHelper.workMinutes(checkIn, checkOut) / 60.0;

  /// 출근/퇴근 시간으로 DB status 결정
  String _deriveStatus(ApplicationModel app, String checkIn, String? checkOut) =>
      AttendanceStatusHelper.deriveStatus(app, checkIn, checkOut);

  /// 일괄 출근 처리
  Future<void> _processBatchCheckIn(String time) async {


    try {
      int successCount = 0;
      int failCount = 0;

      for (var appId in _selectedIds) {
        final app = _confirmedWorkers.firstWhere((a) => a.id == appId);
        final status = _getAttendanceStatus(app);

        // 이미 출근했거나 노쇼면 스킵
        if (status['status'] != 'pending') continue;

        try {
          await _createOrUpdateAttendance(
            app: app,
            checkIn: time,
          );

          // 지각 여부 체크 및 신뢰도 반영
          final expectedStartTime = app.startTime.isNotEmpty ? app.startTime : '09:00';
          if (AttendanceStatusHelper.isLate(time, expectedStartTime)) {
            final trustService = TrustScoreService();
            await trustService.onLate(app.uid);
          }

          successCount++;
        } catch (e) {
          failCount++;
        }
      }

      if (successCount > 0) {
        ToastHelper.showSuccess('$successCount명 출근 처리 완료');
      }
      if (failCount > 0) {
        ToastHelper.showWarning('$failCount명 처리 실패');
      }

      await _loadData();
    } catch (e) {
      debugPrint('❌ 일괄 출근 처리 실패: $e');
      ToastHelper.showError('일괄 출근 처리 실패');
    } finally {

    }
  }

  /// 일괄 퇴근 처리
  Future<void> _processBatchCheckOut(String time, List<String> targetIds) async {
    try {
      int successCount = 0;
      int failCount = 0;

      for (var appId in targetIds) {
        final app = _confirmedWorkers.firstWhere((a) => a.id == appId);
        final attendance = _attendanceMap[app.id];
        if (attendance == null) continue;

        try {
          final checkIn = attendance.checkIn ?? app.startTime;
          final workHours = _calcWorkHoursCompat(checkIn, time);
          final newStatus = _deriveStatus(app, checkIn, time);

          await FirebaseFirestore.instance
              .collection('attendance')
              .doc(attendance.id)
              .update({
            'checkOut': time,
            'checkOutMethod': 'manual',
            'checkOutTime': FieldValue.serverTimestamp(),
            'workHours': workHours,
            'status': newStatus,
            'updatedAt': FieldValue.serverTimestamp(),
          });
          successCount++;
        } catch (e) {
          failCount++;
        }
      }

      if (successCount > 0) ToastHelper.showSuccess('$successCount명 퇴근 처리 완료');
      if (failCount > 0) ToastHelper.showWarning('$failCount명 처리 실패');

      await _loadData();
    } catch (e) {
      debugPrint('❌ 일괄 퇴근 처리 실패: $e');
      ToastHelper.showError('일괄 퇴근 처리 실패');
    }
  }

  /// 파트별 일괄 출근 처리
  Future<void> _processBatchCheckInByGroup(Map<String, String> groupTimes) async {
    try {
      int successCount = 0;
      int failCount = 0;

      for (final appId in _selectedIds) {
        final app = _confirmedWorkers.firstWhere((a) => a.id == appId);
        final groupKey = '${app.selectedWorkType}_${app.startTime}_${app.endTime}';
        final time = groupTimes[groupKey];
        if (time == null) continue;

        final status = _getAttendanceStatus(app);
        if (status['status'] != 'pending') continue;

        try {
          await _createOrUpdateAttendance(app: app, checkIn: time);
          final expectedStartTime = app.startTime.isNotEmpty ? app.startTime : '09:00';
          if (AttendanceStatusHelper.isLate(time, expectedStartTime)) {
            await TrustScoreService().onLate(app.uid);
          }
          successCount++;
        } catch (e) {
          failCount++;
        }
      }

      if (successCount > 0) ToastHelper.showSuccess('$successCount명 출근 처리 완료');
      if (failCount > 0) ToastHelper.showWarning('$failCount명 처리 실패');

      _hasChanges = true;
      await _loadData();
    } catch (e) {
      debugPrint('❌ 파트별 일괄 출근 처리 실패: $e');
      ToastHelper.showError('일괄 출근 처리 실패');
    }
  }

  /// 파트별 일괄 퇴근 처리
  Future<void> _processBatchCheckOutByGroup(
      Map<String, String> groupTimes, List<String> targetIds) async {
    try {
      int successCount = 0;
      int failCount = 0;

      for (final appId in targetIds) {
        final app = _confirmedWorkers.firstWhere((a) => a.id == appId);
        final groupKey = '${app.selectedWorkType}_${app.startTime}_${app.endTime}';
        final time = groupTimes[groupKey];
        if (time == null) continue;

        final attendance = _attendanceMap[app.id];
        if (attendance == null) continue;

        try {
          final checkIn = attendance.checkIn ?? app.startTime;
          final workHours = _calcWorkHoursCompat(checkIn, time);
          final newStatus = _deriveStatus(app, checkIn, time);

          await FirebaseFirestore.instance
              .collection('attendance')
              .doc(attendance.id)
              .update({
            'checkOut': time,
            'checkOutMethod': 'manual',
            'checkOutTime': FieldValue.serverTimestamp(),
            'workHours': workHours,
            'status': newStatus,
            'updatedAt': FieldValue.serverTimestamp(),
          });
          successCount++;
        } catch (e) {
          failCount++;
        }
      }

      if (successCount > 0) ToastHelper.showSuccess('$successCount명 퇴근 처리 완료');
      if (failCount > 0) ToastHelper.showWarning('$failCount명 처리 실패');

      _hasChanges = true;
      await _loadData();
    } catch (e) {
      debugPrint('❌ 파트별 일괄 퇴근 처리 실패: $e');
      ToastHelper.showError('일괄 퇴근 처리 실패');
    }
  }

  /// 개별 출근 처리
  Future<void> _processCheckIn(ApplicationModel app, String time) async {


    try {
      await _createOrUpdateAttendance(app: app, checkIn: time);
      
      // 🆕 지각 여부 체크 및 신뢰도 반영
      final expectedStartTime = app.startTime.isNotEmpty ? app.startTime : '09:00';
      if (AttendanceStatusHelper.isLate(time, expectedStartTime)) {
        final trustService = TrustScoreService();
        await trustService.onLate(app.uid);
        ToastHelper.showWarning('지각 처리 완료 (신뢰도 -1)');
      } else {
        ToastHelper.showSuccess('출근 처리 완료');
      }
      
      await _loadData();
    } catch (e) {
      debugPrint('❌ 출근 처리 실패: $e');
      ToastHelper.showError('출근 처리 실패');
    } finally {

    }
  }

  /// 개별 퇴근 처리
  Future<void> _processCheckOut(ApplicationModel app, String time) async {
    final attendance = _attendanceMap[app.id];
    if (attendance == null) {
      ToastHelper.showError('출근 기록이 없습니다');
      return;
    }

    try {
      final checkIn = attendance.checkIn ?? app.startTime;
      final workHours = _calcWorkHoursCompat(checkIn, time);
      final newStatus = _deriveStatus(app, checkIn, time);

      await FirebaseFirestore.instance
          .collection('attendance')
          .doc(attendance.id)
          .update({
        'checkOut': time,
        'checkOutMethod': 'manual',
        'checkOutTime': FieldValue.serverTimestamp(),
        'workHours': workHours,
        'status': newStatus,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      ToastHelper.showSuccess('퇴근 처리 완료');
      await _loadData();
    } catch (e) {
      debugPrint('❌ 퇴근 처리 실패: $e');
      ToastHelper.showError('퇴근 처리 실패');
    }
  }

  /// 시간 수정 (출근·퇴근 재계산 포함)
  Future<void> _updateAttendanceTime(ApplicationModel app, String? checkIn, String? checkOut) async {
    try {
      final attendance = _attendanceMap[app.id];
      if (attendance == null) return;

      // 둘 다 null → attendance 문서 삭제 (미출근 상태로 되돌림)
      if (checkIn == null && checkOut == null) {
        await FirebaseFirestore.instance
            .collection('attendance')
            .doc(attendance.id)
            .delete();
        ToastHelper.showSuccess('미출근 상태로 변경되었습니다');
        await _loadData();
        return;
      }

      final effectiveCheckIn  = checkIn  ?? attendance.checkIn;
      final effectiveCheckOut = checkOut ?? attendance.checkOut;

      final Map<String, dynamic> updates = {
        'isModified': true,
        'modifiedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      };

      if (checkIn != null) {
        updates['checkIn'] = checkIn;
        updates['checkInMethod'] = 'manual';
      }

      if (checkOut != null) {
        updates['checkOut'] = checkOut;
        updates['checkOutMethod'] = 'manual';
      } else if (attendance.checkOut != null && checkOut == null) {
        updates['checkOut'] = FieldValue.delete();
        updates['checkOutMethod'] = FieldValue.delete();
        updates['checkOutTime'] = FieldValue.delete();
      }

      // status 재계산
      if (effectiveCheckIn != null) {
        updates['status'] = _deriveStatus(app, effectiveCheckIn, effectiveCheckOut);
      }

      // workHours 재계산
      if (effectiveCheckIn != null && effectiveCheckOut != null) {
        updates['workHours'] = _calcWorkHoursCompat(effectiveCheckIn, effectiveCheckOut);
      }

      await FirebaseFirestore.instance
          .collection('attendance')
          .doc(attendance.id)
          .update(updates);

      ToastHelper.showSuccess('시간이 수정되었습니다');
      await _loadData();
    } catch (e) {
      debugPrint('❌ 시간 수정 실패: $e');
      ToastHelper.showError('시간 수정 실패');
    }
  }


  /// Attendance 생성 또는 업데이트 (출근 처리)
  Future<void> _createOrUpdateAttendance({
    required ApplicationModel app,
    required String checkIn,
  }) async {
    final existingAttendance = _attendanceMap[app.id];
    final status = _deriveStatus(app, checkIn, null);

    if (existingAttendance != null) {
      await FirebaseFirestore.instance
          .collection('attendance')
          .doc(existingAttendance.id)
          .update({
        'checkIn': checkIn,
        'checkInMethod': 'manual',
        'checkInTime': FieldValue.serverTimestamp(),
        'status': status,
        'isModified': true,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } else {
      await FirebaseFirestore.instance.collection('attendance').add({
        'applicationId': app.id,
        'userId': app.uid,
        'businessId': app.businessId,
        'businessName': app.businessName,
        'workDate': Timestamp.fromDate(widget.date),
        'workType': app.selectedWorkType,
        'checkIn': checkIn,
        'checkInMethod': 'manual',
        'checkInTime': FieldValue.serverTimestamp(),
        'status': status,
        'isModified': false,
        'modifyRequested': false,
        'wageStatus': AttendanceModel.wagePending,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
  }

  // ═══════════════════════════════════════════════════════════
  // 노쇼 처리
  // ═══════════════════════════════════════════════════════════

  /// 노쇼 처리
  Future<void> _markNoShow(ApplicationModel app) async {
    final confirmed = await DialogHelper.showDangerConfirm(
      context,
      title: '노쇼 처리',
      message: '${_getDisplayName(app.uid)}님을 노쇼로 처리하시겠습니까?\n\n이 기록은 해당 근무자의 이력에 남습니다.',
      confirmText: '노쇼 처리',
    );

    if (!confirmed) return;



    try {
      final existingAttendance = _attendanceMap[app.id];

      if (existingAttendance != null) {
        await FirebaseFirestore.instance
            .collection('attendance')
            .doc(existingAttendance.id)
            .update({
          'status': 'NO_SHOW',
          'updatedAt': FieldValue.serverTimestamp(),
        });
       } else {
        await FirebaseFirestore.instance.collection('attendance').add({
          'applicationId': app.id,
          'userId': app.uid,
          'businessId': app.businessId,
          'businessName': app.businessName,
          'workDate': Timestamp.fromDate(widget.date),
          'workType': app.selectedWorkType,
          'status': 'NO_SHOW',                // ✅ 노쇼 상태
          'isModified': false,
          'modifyRequested': false,
          'wageStatus': 'pending',
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }

      // 🆕 신뢰도 서비스로 노쇼 처리 (noShowCount 증가 + 점수 감점)
      final trustService = TrustScoreService();
      await trustService.onNoShow(app.uid);

      ToastHelper.showSuccess('노쇼 처리 완료');
      await _loadData();
    } catch (e) {
      debugPrint('❌ 노쇼 처리 실패: $e');
      ToastHelper.showError('노쇼 처리 실패');
    } finally {

    }
  }

  /// 노쇼 해제
  Future<void> _cancelNoShow(ApplicationModel app) async {
    final confirmed = await DialogHelper.showConfirm(
      context,
      title: '노쇼 해제',
      message: '${_getDisplayName(app.uid)}님의 노쇼를 해제하시겠습니까?',
      confirmText: '해제',
    );

    if (!confirmed) return;



    try {
      final attendance = _attendanceMap[app.id];
      if (attendance != null) {
        // 출근 기록이 있으면 상태만 변경
        await FirebaseFirestore.instance
            .collection('attendance')
            .doc(attendance.id)
            .update({
          'status': 'absent',     // ✅ 노쇼 해제 → 미출근(결근) 상태
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }

      // 사용자 noShowCount 감소
      await FirebaseFirestore.instance
          .collection('users')
          .doc(app.uid)
          .update({
        'noShowCount': FieldValue.increment(-1),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      ToastHelper.showSuccess('노쇼 해제 완료');
      await _loadData();
    } catch (e) {
      debugPrint('❌ 노쇼 해제 실패: $e');
      ToastHelper.showError('노쇼 해제 실패');
    } finally {

    }
  }
  /// 급여 수정 다이얼로그
  Future<void> _showEditWageDialog(ApplicationModel app) async {
    final attendance = _attendanceMap[app.id];
    final user = _userMap[app.uid];
    if (attendance == null || attendance.wageDetail == null) {
      ToastHelper.showWarning('급여 정보가 없습니다');
      return;
    }

    final detailCached = (app.workDetailId != null
            ? _workDetailTimeMap[app.workDetailId]
            : null) ??
        _workDetailTimeMap[app.selectedWorkType];
    final shiftType = detailCached is Map<String, dynamic>
        ? detailCached['shiftType'] as String?
        : null;
    final weeklyHolidayIncluded = detailCached is Map<String, dynamic>
        ? (detailCached['weeklyHolidayIncluded'] as bool? ?? false)
        : false;

    final result = await WageDetailDialog.show(
      context: context,
      app: app,
      user: user,
      attendance: attendance,
      wage: attendance.wageDetail!,
      mode: WageDialogMode.editOnly,
      businessName: _businessNameMap[app.businessId],
      shiftType: shiftType,
      weeklyHolidayIncluded: weeklyHolidayIncluded,
      weeklyHolidayEligibility: _weeklyHolidayMap[app.id],
    );
    
    if (result != null && result.action == 'update') {
      await _processWageUpdate(app, attendance, result.wage);
    }
  }

  /// 급여 업데이트 처리
  Future<void> _processWageUpdate(ApplicationModel app, AttendanceModel attendance, WageDetailModel wage) async {

    
    try {
      final userProvider = Provider.of<UserProvider>(context, listen: false);
      final adminUid = userProvider.currentUser?.uid;
      final user = _userMap[app.uid];
      
      final updatedWage = wage.copyWith(
        calculatedBy: adminUid,
        calculatedAt: DateTime.now(),
      );
      
      await FirebaseFirestore.instance
          .collection('attendance')
          .doc(attendance.id)
          .update({
        'finalWage': updatedWage.totalAmount,
        'wageDetail': updatedWage.toMap(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      
      _hasChanges = true;
      ToastHelper.showSuccess('${user?.name ?? '근무자'} 급여 수정 완료');
      await _loadData();
    } catch (e) {
      debugPrint('❌ 급여 수정 실패: $e');
      ToastHelper.showError('급여 수정에 실패했습니다');
    } finally {

    }
  }

  /// 최종 확정 처리
  Future<void> _processFinalConfirm(ApplicationModel app) async {
    final attendance = _attendanceMap[app.id];
    final user = _userMap[app.uid];
    if (attendance == null) return;

    final adminUid = Provider.of<UserProvider>(context, listen: false).currentUser?.uid;

    final confirmed = await DialogHelper.showConfirm(
      context,
      title: '최종 확정',
      message: '${user?.name ?? '근무자'}의 급여를 최종 확정하시겠습니까?\n\n⚠️ 최종 확정 후에는 수정이 불가합니다.',
      confirmText: '최종 확정',
    );

    if (!confirmed) return;



    try {
      
      final wageDetail = attendance.wageDetail?.copyWith(
        confirmedBy: adminUid,
        confirmedAt: DateTime.now(),
      );
      
      await FirebaseFirestore.instance
          .collection('attendance')
          .doc(attendance.id)
          .update({
        'wageStatus': 'confirmed',
        'wageDetail': wageDetail?.toMap(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      
      // 🆕 근무 완료 신뢰도 반영 + totalWorkDays 증가
      final trustService = TrustScoreService();
      await trustService.onWorkComplete(app.uid);
      await FirebaseFirestore.instance
          .collection('users')
          .doc(app.uid)
          .update({
        'totalWorkDays': FieldValue.increment(1),
      });
      
      _hasChanges = true;
      ToastHelper.showSuccess('${user?.name ?? '근무자'} 최종 확정 완료');
      await _loadData();
    } catch (e) {
      debugPrint('❌ 최종 확정 실패: $e');
      ToastHelper.showError('최종 확정에 실패했습니다');
    } finally {

    }
  }

  /// 급여 취소 처리 (calculated → pending)
  Future<void> _processCancelWage(ApplicationModel app) async {
    final attendance = _attendanceMap[app.id];
    final user = _userMap[app.uid];
    if (attendance == null) return;
    
    final confirmed = await DialogHelper.showConfirm(
      context,
      title: '급여 확정 취소',
      message: '${user?.name ?? '근무자'}의 급여 확정을 취소하시겠습니까?\n\n미확정 상태로 되돌아갑니다.',
      confirmText: '취소하기',
    );
    
    if (!confirmed) return;
    

    
    try {
      await FirebaseFirestore.instance
          .collection('attendance')
          .doc(attendance.id)
          .update({
        'wageStatus': 'pending',
        'finalWage': FieldValue.delete(),
        'wageDetail': FieldValue.delete(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      
      _hasChanges = true;
      ToastHelper.showSuccess('${user?.name ?? '근무자'} 급여 확정 취소');
      await _loadData();
    } catch (e) {
      debugPrint('❌ 급여 취소 실패: $e');
      ToastHelper.showError('급여 취소에 실패했습니다');
    } finally {

    }
  }

  /// 급여 상세 보기 (읽기 전용)
  Future<void> _showViewWageDialog(ApplicationModel app) async {
    final attendance = _attendanceMap[app.id];
    final user = _userMap[app.uid];
    if (attendance == null || attendance.wageDetail == null) {
      ToastHelper.showWarning('급여 정보가 없습니다');
      return;
    }

    final detailCached = (app.workDetailId != null
            ? _workDetailTimeMap[app.workDetailId]
            : null) ??
        _workDetailTimeMap[app.selectedWorkType];
    final shiftType = detailCached is Map<String, dynamic>
        ? detailCached['shiftType'] as String?
        : null;
    final weeklyHolidayIncluded = detailCached is Map<String, dynamic>
        ? (detailCached['weeklyHolidayIncluded'] as bool? ?? false)
        : false;

    await WageDetailDialog.show(
      context: context,
      app: app,
      user: user,
      attendance: attendance,
      wage: attendance.wageDetail!,
      mode: WageDialogMode.confirmed,
      businessName: _businessNameMap[app.businessId],
      shiftType: shiftType,
      weeklyHolidayIncluded: weeklyHolidayIncluded,
      weeklyHolidayEligibility: _weeklyHolidayMap[app.id],
    );
  }
  /// 마감 취소 처리 (confirmed → calculated)
  Future<void> _processCancelFinal(ApplicationModel app) async {
    final attendance = _attendanceMap[app.id];
    final user = _userMap[app.uid];
    if (attendance == null) return;
    
    final confirmed = await DialogHelper.showConfirm(
      context,
      title: '마감 취소',
      message: '${user?.name ?? '근무자'}의 마감을 취소하시겠습니까?\n\n급여확정 상태로 되돌아가며, 지원자에게 급여가 숨겨집니다.',
      confirmText: '마감 취소',
    );
    
    if (!confirmed) return;
    

    
    try {
      // wageDetail에서 confirmedBy, confirmedAt 제거
      final wageDetail = attendance.wageDetail?.copyWith(
        confirmedBy: null,
        confirmedAt: null,
      );
      
      await FirebaseFirestore.instance
          .collection('attendance')
          .doc(attendance.id)
          .update({
        'wageStatus': 'calculated',
        'wageDetail': wageDetail?.toMap(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      
      _hasChanges = true;
      ToastHelper.showSuccess('${user?.name ?? '근무자'} 마감 취소 완료');
      await _loadData();
    } catch (e) {
      debugPrint('❌ 마감 취소 실패: $e');
      ToastHelper.showError('마감 취소에 실패했습니다');
    } finally {

    }
  }

}
