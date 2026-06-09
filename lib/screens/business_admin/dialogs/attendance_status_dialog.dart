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
import '../../../models/core/notification_model.dart';

// Services
import '../../../services/firestore_service.dart';

// Utils
import '../../../utils/toast_helper.dart';
import '../../../services/trust_score_service.dart';
import '../../../utils/responsive_helper.dart';
import '../../../utils/dialog_helper.dart';
import '../../../utils/format_helper.dart';
import '../../../utils/attendance_badge_helper.dart';
import '../../../utils/attendance_status_helper.dart';
import '../../../utils/work_detail_helper.dart';
import '../../../utils/payment_due_date_calculator.dart';
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
  
  // UI 상태
  bool _isLoading = true;
  String? _selectedBusinessId;
  bool _hasChanges = false;  // ✅ 변경 여부 추적
  
  // 선택 상태
  final Set<String> _selectedIds = {};
  bool _selectAll = false;

  // 파트별 정렬 모드: 0=상태순, 1=배지순, 2=이름순
  final Map<String, int> _groupSortMode = {};

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
      if (attendance.status == AttendanceModel.statusNoShow) {
        count++;
      }
      // 급여확정 (calculated) - 마감 대기
      else if (attendance.wageStatus == AttendanceModel.wageCalculated) {
        count++;
      }
      // 최종확정 (confirmed) - 이미 마감됨
      else if (attendance.wageStatus == AttendanceModel.wageConfirmed) {
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
      if (attendance.wageStatus == AttendanceModel.wageCalculated) {
        return true;
      }
    }
    return false;
  }

  /// 선택된 최종확정 근무자 목록 (마감취소 대상)
  List<ApplicationModel> get _selectedFinalConfirmedApps {
    return _confirmedWorkers.where((app) {
      if (!_selectedIds.contains(app.id)) return false;
      final attendance = _attendanceMap[app.id];
      return attendance?.wageStatus == AttendanceModel.wageConfirmed;
    }).toList();
  }

  /// 마감 완료 여부 (모두 confirmed 또는 noshow)
  bool get _isAllClosed {
    if (_confirmedWorkers.isEmpty) return false;
    for (var app in _confirmedWorkers) {
      final attendance = _attendanceMap[app.id];
      if (attendance == null) return false;
      
      // noshow가 아니고 confirmed도 아니면 마감 미완료
      if (attendance.status != AttendanceModel.statusNoShow && attendance.wageStatus != AttendanceModel.wageConfirmed) {
        return false;
      }
    }
    return true;
  }

  @override
  void initState() {
    super.initState();
    _selectedBusinessId = widget.initialBusinessId ??
        (widget.businessIds.isNotEmpty ? widget.businessIds.first : null);
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
        _firestoreService.getUsersBatch(uids),                       // [1] 사용자 정보
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
        _isLoading = false;
      });

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
        .where('status', whereIn: [AppStatus.confirmed, AppStatus.contractPending])
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

    // ✅ 2. 장기 공고: type='long_term' 필터로 서버 범위 축소 후 클라이언트 필터링
    final longTermSnapshot = await FirebaseFirestore.instance
        .collection('applications')
        .where('businessId', isEqualTo: _selectedBusinessId)
        .where('status', whereIn: [AppStatus.confirmed, AppStatus.contractPending])
        .where('type', isEqualTo: AppType.longTerm)
        .get();

    int longTermCount = 0;
    for (var doc in longTermSnapshot.docs) {
      final app = ApplicationModel.fromFirestore(doc);
      
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

      // 요일 체크 — workDays가 없으면 요일 불문 포함 (스케줄 미지정 고정근무자)
      final dayWeekday = FormatHelper.weekday(dateStart);
      if (app.workDays == null || app.workDays!.isEmpty || app.workDays!.contains(dayWeekday)) {
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
    final expectedStart = WorkDetailHelper.effectiveStart(app, _workDetailTimeMap);
    final expectedEnd   = WorkDetailHelper.effectiveEnd(app, _workDetailTimeMap);

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

      // 송금 완료 (transferred) — 최종확정보다 우선 표시
      if (attendance.wageStatus == AttendanceModel.wageTransferred) {
        return {
          'status': 'transferred',
          'color': AppColors.teal,
          'icon': Icons.check_circle_outline,
          'text': '송금완료',
          'timeText': timeText,
          'isPast': false,
        };
      }
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
      // 과거 날짜이거나 당일 퇴근 예정 시간 초과 → 퇴근 미체크 경고
      final today = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
      final isPastDay = widget.date.isBefore(today);
      bool isOverdue = false;
      if (!isPastDay && expectedEnd.isNotEmpty) {
        final endParts = expectedEnd.split(':');
        if (endParts.length == 2) {
          final endH = int.tryParse(endParts[0]);
          final endM = int.tryParse(endParts[1]);
          if (endH != null && endM != null) {
            final workDay = widget.date;
            var endAt = DateTime(workDay.year, workDay.month, workDay.day, endH, endM);
            final startParts = expectedStart.split(':');
            final startH = int.tryParse(startParts.first) ?? 0;
            if (endH < startH) endAt = endAt.add(const Duration(days: 1));
            isOverdue = DateTime.now().isAfter(endAt);
          }
        }
      }
      if (isPastDay || isOverdue) {
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

  /// 상태 우선순위 (낮을수록 상단 — 처리 필요 순)
  int _workerSortPriority(ApplicationModel app) {
    final status = _getAttendanceStatus(app)['status'] as String;
    const p = {
      'pending':         0,  // 미출근
      'missed_checkout': 1,  // 퇴근미체크
      'late':            2,  // 지각
      'checkin':         3,  // 출근 중
      'early_leave':     4,  // 조퇴
      'checkout':        5,  // 퇴근
      'wage_confirmed':  6,  // 급여확정
      'final_confirmed': 7,  // 최종확정
      'transferred':     8,  // 송금완료
      'noshow':          9,  // 노쇼
    };
    return p[status] ?? 10;
  }

  /// 배지 개수/무게 기반 정렬 키 (배지순 모드)
  /// 지각(4) + 연장(3) + 심야(2) + 조퇴(1) 가중치 합산 — 높을수록 상단
  int _badgeWeight(ApplicationModel app) {
    final statusInfo = _getAttendanceStatus(app);
    final attendance = _attendanceMap[app.id];
    if (attendance == null) return 0;

    final effStart = WorkDetailHelper.effectiveStart(app, _workDetailTimeMap);
    final effEnd   = WorkDetailHelper.effectiveEnd(app, _workDetailTimeMap);
    final flags = AttendanceBadgeHelper.compute(
      checkIn:  attendance.checkIn,
      checkOut: attendance.checkOut,
      effStart: effStart,
      effEnd:   effEnd,
      wageDetail: attendance.wageDetail,
    );

    int weight = 0;
    if (flags.isLate)       weight += 4;
    if (flags.isOvertime)   weight += 3;
    if (flags.isNight)      weight += 2;
    if (flags.isEarlyLeave) weight += 1;
    // 처리 필요한 상태도 가중치에 반영
    final status = statusInfo['status'] as String;
    if (status == 'pending')         weight += 16;
    if (status == 'missed_checkout') weight += 12;
    return weight;
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
    int earlyArrival = 0;
    int earlyLeave = 0;
    int missedCheckout = 0;
    int noShow = 0;

    for (var app in _confirmedWorkers) {
      final statusMap = _getAttendanceStatus(app);
      final s = statusMap['status'] as String;
      final attendance = _attendanceMap[app.id];

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

      // 조출 카운트 (출근 기록 있고 30분 이상 일찍 찍힌 경우)
      if (attendance?.checkIn != null) {
        final effStart = WorkDetailHelper.effectiveStart(app, _workDetailTimeMap);
        if (AttendanceStatusHelper.isEarlyArrival(attendance!.checkIn!, effStart)) {
          earlyArrival++;
        }
      }
    }

    return {
      'total': total,
      'checkedIn': checkedIn,
      'checkedOut': checkedOut,
      'notCheckedIn': total - checkedIn - noShow,
      'late': late,
      'earlyArrival': earlyArrival,
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
          width: MediaQuery.sizeOf(context).width * 0.95,
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.9,
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
    final padding = ResponsiveHelper.cardPadding(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 통계 + 액션바 — 스크롤 영역 밖 고정 (항상 보임)
        Padding(
          padding: EdgeInsets.fromLTRB(
              padding.left, ResponsiveHelper.spacing(context, 8),
              padding.right, 0),
          child: Column(
            children: [
              _buildCompactStats(theme),
              SizedBox(height: ResponsiveHelper.spacing(context, 8)),
              _buildBatchActionBar(theme),
              SizedBox(height: ResponsiveHelper.spacing(context, 8)),
            ],
          ),
        ),

        // 업무별 그룹만 스크롤
        Flexible(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
                padding.left, 0, padding.right, padding.bottom),
            child: _buildWorkTypeGroups(theme),
          ),
        ),
      ],
    );
  }

  /// 통계 컴팩트 스트립 — 한 줄로 핵심 수치만 표시
  Widget _buildCompactStats(ThemeData theme) {
    final stats = _calculateStats();

    // 주요 4개 + 이상 발생 시 보조 통계 추가
    final secondaryStats = <_StatChip>[];
    if ((stats['earlyArrival'] ?? 0) > 0) {
      secondaryStats.add(_StatChip('조출', stats['earlyArrival']!, AppColors.success));
    }
    if (stats['late']! > 0) {
      secondaryStats.add(_StatChip('지각', stats['late']!, AppColors.warningDark));
    }
    if (stats['earlyLeave']! > 0) {
      secondaryStats.add(_StatChip('조퇴', stats['earlyLeave']!, AppColors.amber));
    }
    if (stats['missedCheckout']! > 0) {
      secondaryStats.add(_StatChip('미퇴근', stats['missedCheckout']!, AppColors.error));
    }

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 12),
        vertical: ResponsiveHelper.spacing(context, 8),
      ),
      decoration: BoxDecoration(
        color: theme.primaryColor.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.primaryColor.withValues(alpha: 0.15)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 주요 통계 — 한 줄
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildCompactStatItem('확정', stats['total']!, AppColors.info),
              _buildCompactStatItem('출근', stats['checkedIn']!, AppColors.success),
              _buildCompactStatItem('미출근', stats['notCheckedIn']!, AppColors.warning),
              _buildCompactStatItem('노쇼', stats['noShow']!, AppColors.error),
            ],
          ),
          // 보조 통계 — 이상 발생 시만 한 줄 추가
          if (secondaryStats.isNotEmpty) ...[
            SizedBox(height: ResponsiveHelper.spacing(context, 4)),
            Divider(height: 1, color: theme.primaryColor.withValues(alpha: 0.1)),
            SizedBox(height: ResponsiveHelper.spacing(context, 4)),
            Wrap(
              spacing: ResponsiveHelper.spacing(context, 16),
              runSpacing: ResponsiveHelper.spacing(context, 2),
              alignment: WrapAlignment.center,
              children: secondaryStats.map((c) => _buildMiniStat(c.label, c.count, c.color)).toList(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCompactStatItem(String label, int count, Color color) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$count명',
          style: ResponsiveHelper.bodyStyle(context).copyWith(
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(
          label,
          style: ResponsiveHelper.tinyStyle(context, color: AppColors.grey500),
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
        final firstApp = entry.value.first;
        return Padding(
          padding: EdgeInsets.only(bottom: ResponsiveHelper.spacing(context, 16)),
          child: _buildWorkTypeSection(
            theme,
            firstApp.selectedWorkType,
            entry.value,
            groupKey: entry.key,
            startTime: WorkDetailHelper.effectiveStart(firstApp, _workDetailTimeMap),
            endTime: WorkDetailHelper.effectiveEnd(firstApp, _workDetailTimeMap),
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
    required String groupKey,
    String? startTime,
    String? endTime,
  }) {
    // 정렬 모드: 0=상태순, 1=배지순, 2=이름순
    final sortMode = _groupSortMode[groupKey] ?? 0;
    final sortedWorkers = [...workers];
    switch (sortMode) {
      case 2: // 이름순
        sortedWorkers.sort((a, b) {
          final na = _userMap[a.uid]?.name ?? '';
          final nb = _userMap[b.uid]?.name ?? '';
          return na.compareTo(nb);
        });
        break;
      case 1: // 배지순 (배지 무게 높을수록 상단)
        sortedWorkers.sort((a, b) {
          final wa = _badgeWeight(a);
          final wb = _badgeWeight(b);
          if (wa != wb) return wb.compareTo(wa); // 무게 내림차순
          final na = _userMap[a.uid]?.name ?? '';
          final nb = _userMap[b.uid]?.name ?? '';
          return na.compareTo(nb);
        });
        break;
      default: // 0: 상태순 (처리 필요 순)
        sortedWorkers.sort((a, b) {
          final pa = _workerSortPriority(a);
          final pb = _workerSortPriority(b);
          if (pa != pb) return pa.compareTo(pb);
          // 동일 상태면 배지 무게 내림차순 (복잡한 케이스 우선)
          final wa = _badgeWeight(a);
          final wb = _badgeWeight(b);
          if (wa != wb) return wb.compareTo(wa);
          final na = _userMap[a.uid]?.name ?? '';
          final nb = _userMap[b.uid]?.name ?? '';
          return na.compareTo(nb);
        });
    }
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
                    // 출근현황 + 정렬 토글 — 세로로 쌓아 텍스트 공간 확보
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
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
                        SizedBox(height: ResponsiveHelper.spacing(context, 6)),
                        // 정렬 토글 버튼 (탭마다 순환: 상태순→배지순→이름순)
                        Builder(builder: (ctx) {
                          final sm = _groupSortMode[groupKey] ?? 0;
                          const labels = ['상태순', '배지순', '이름순'];
                          const icons  = [Icons.swap_vert, Icons.filter_list, Icons.sort_by_alpha];
                          final isActive = sm != 0;
                          return GestureDetector(
                            onTap: () => setState(() =>
                                _groupSortMode[groupKey] = (sm + 1) % 3),
                            child: Container(
                              padding: EdgeInsets.symmetric(
                                horizontal: ResponsiveHelper.spacing(context, 7),
                                vertical: ResponsiveHelper.spacing(context, 4),
                              ),
                              decoration: BoxDecoration(
                                color: isActive
                                    ? theme.primaryColor.withValues(alpha: 0.12)
                                    : Colors.white,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: isActive
                                      ? theme.primaryColor.withValues(alpha: 0.4)
                                      : AppColors.border,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    icons[sm],
                                    size: ResponsiveHelper.iconSize(context, 11),
                                    color: isActive ? theme.primaryColor : AppColors.grey500,
                                  ),
                                  SizedBox(width: ResponsiveHelper.spacing(context, 3)),
                                  Text(
                                    labels[sm],
                                    style: ResponsiveHelper.tinyStyle(
                                      context,
                                      color: isActive ? theme.primaryColor : AppColors.grey500,
                                    ).copyWith(fontWeight: FontWeight.w600),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }),
                      ],
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
              children: sortedWorkers.map((app) => _buildWorkerCard(app)).toList(),
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
    final effEnd = WorkDetailHelper.effectiveEnd(app, _workDetailTimeMap);
    if (effEnd.isEmpty) return false;
    final parts = effEnd.split(':');
    if (parts.length != 2) return false;
    final endH = int.tryParse(parts[0]);
    final endM = int.tryParse(parts[1]);
    if (endH == null || endM == null) return false;
    // widget.date 기준으로 퇴근 예정시각 계산 (야간 자정 넘김 보정)
    final workDay = widget.date;
    var endAt = DateTime(workDay.year, workDay.month, workDay.day, endH, endM);
    final effStart = WorkDetailHelper.effectiveStart(app, _workDetailTimeMap);
    final startParts = effStart.split(':');
    final startH = int.tryParse(startParts.first) ?? 0;
    if (endH < startH) endAt = endAt.add(const Duration(days: 1));
    return DateTime.now().isAfter(endAt);
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
                          // 이름 — Flexible로 overflow 방지
                          Flexible(
                            child: Text(
                              displayName,
                              style: ResponsiveHelper.bodyStyle(context).copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                              overflow: TextOverflow.ellipsis,
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

                      // Row 2: 시간 정보 (시간 있거나 위치 배지 있을 때만 표시)
                      Builder(builder: (context) {
                        final timeText = statusInfo['timeText'] as String?;
                        final locationBadge = _buildLocationBadge(app.id);
                        final hasLocation = _locationMap[app.id]?.isActive == true &&
                            _locationMap[app.id]?.consentGiven == true;
                        final attendance = _attendanceMap[app.id];
                        if (timeText == null && !hasLocation) return const SizedBox.shrink();
                        return Padding(
                          padding: EdgeInsets.only(top: ResponsiveHelper.spacing(context, 4)),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    Icons.access_time,
                                    size: ResponsiveHelper.iconSize(context, 13),
                                    color: AppColors.grey500,
                                  ),
                                  SizedBox(width: ResponsiveHelper.spacing(context, 4)),
                                  if (timeText != null)
                                    Flexible(
                                      child: Text(
                                        timeText,
                                        style: ResponsiveHelper.smallStyle(context, color: AppColors.grey600),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  locationBadge,
                                ],
                              ),
                              if (attendance != null && attendance.isModified == true)
                                Padding(
                                  padding: EdgeInsets.only(
                                    top: ResponsiveHelper.spacing(context, 2),
                                    left: ResponsiveHelper.spacing(context, 17),
                                  ),
                                  child: _buildOriginalTimeHint(attendance),
                                ),
                            ],
                          ),
                        );
                      }),

                      SizedBox(height: ResponsiveHelper.spacing(context, 4)),

                      // Row 3: 상태 배지 + 추가 플래그 배지
                      Wrap(
                        spacing: ResponsiveHelper.spacing(context, 6),
                        runSpacing: ResponsiveHelper.spacing(context, 4),
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          // 메인 상태 배지 (출근/퇴근/급여확정/최종확정 등)
                          _buildMainStatusBadge(statusInfo, theme),

                          // 추가 플래그 배지 (지각/조퇴/연장/심야)
                          ..._buildExtraBadges(app),

                          // 출근 방식 배지 (GPS/비콘/수동)
                          _buildCheckInMethodBadge(_attendanceMap[app.id]),

                          // 퇴근 미처리 경고 배지
                          if (overdueCheckout)
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

  /// 메인 상태 배지 (출근/퇴근/급여확정/최종확정 등 워크플로 단계)
  Widget _buildMainStatusBadge(Map<String, dynamic> statusInfo, ThemeData theme) {
    final status = statusInfo['status'] as String;
    final Color color;
    final String text;

    switch (status) {
      case 'late':
        text = '출근';
        color = theme.primaryColor;
        break;
      case 'early_leave':
        text = '퇴근';
        color = AppColors.purple;
        break;
      default:
        // wage_confirmed(조퇴) 같은 조합 텍스트에서 괄호 제거
        text = (statusInfo['text'] as String)
            .replaceAll(RegExp(r'\(.*?\)'), '')
            .trim();
        color = statusInfo['color'] as Color;
    }

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 8),
        vertical: ResponsiveHelper.spacing(context, 2),
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: ResponsiveHelper.tinyStyle(context, color: color)
            .copyWith(fontWeight: FontWeight.w600),
      ),
    );
  }

  /// 추가 플래그 배지 목록 (지각/조퇴/연장/심야)
  List<Widget> _buildExtraBadges(ApplicationModel app) {
    final attendance = _attendanceMap[app.id];
    if (attendance == null) return [];
    if (attendance.status == AttendanceModel.statusNoShow) return [];

    final flags = AttendanceBadgeHelper.compute(
      checkIn: attendance.checkIn,
      checkOut: attendance.checkOut,
      effStart: WorkDetailHelper.effectiveStart(app, _workDetailTimeMap),
      effEnd: WorkDetailHelper.effectiveEnd(app, _workDetailTimeMap),
      wageDetail: attendance.wageDetail,
    );

    return [
      if (flags.isEarlyArrival) _buildFlagBadge('조출', AppColors.success),
      if (flags.isLate) _buildFlagBadge('지각', AppColors.warningDark),
      if (flags.isEarlyLeave) _buildFlagBadge('조퇴', AppColors.amber),
      if (flags.isOvertime) _buildFlagBadge('연장', AppColors.info),
      if (flags.isNight) _buildFlagBadge('심야', AppColors.purple),
    ];
  }

  Widget _buildFlagBadge(String text, Color color) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 6),
        vertical: ResponsiveHelper.spacing(context, 2),
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(
        text,
        style: ResponsiveHelper.tinyStyle(context, color: color)
            .copyWith(fontWeight: FontWeight.w600),
      ),
    );
  }

  /// 관리자가 시간 수정 시 원본 근무자 기록을 작은 텍스트로 표시
  Widget _buildOriginalTimeHint(AttendanceModel attendance) {
    final hasOriginalIn = attendance.originalCheckIn != null &&
        attendance.originalCheckIn != attendance.checkIn;
    final hasOriginalOut = attendance.originalCheckOut != null &&
        attendance.originalCheckOut != attendance.checkOut;
    if (!hasOriginalIn && !hasOriginalOut) return const SizedBox.shrink();

    final parts = <String>[];
    if (hasOriginalIn) parts.add('출근 ${_trimSeconds(attendance.originalCheckIn!)}');
    if (hasOriginalOut) parts.add('퇴근 ${_trimSeconds(attendance.originalCheckOut!)}');

    return Tooltip(
      message: '근무자 원본 기록: ${parts.join(' / ')}',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.history, size: ResponsiveHelper.iconSize(context, 10),
              color: AppColors.grey400),
          SizedBox(width: ResponsiveHelper.spacing(context, 2)),
          Text(
            parts.join(' / '),
            style: ResponsiveHelper.tinyStyle(context, color: AppColors.grey400),
          ),
        ],
      ),
    );
  }

  /// 출근 방식 배지 (GPS / 비콘 / 수동)
  Widget _buildCheckInMethodBadge(AttendanceModel? attendance) {
    final method = attendance?.checkInMethod;
    if (method == null || method.isEmpty) return const SizedBox.shrink();

    final (IconData icon, String label, Color color) = switch (method) {
      'gps'    => (Icons.gps_fixed, 'GPS', AppColors.info),
      'beacon' => (Icons.bluetooth, '비콘', AppColors.purple),
      'manual' => (Icons.edit_outlined, '수동', AppColors.grey500),
      _        => (Icons.help_outline, method, AppColors.grey400),
    };

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 6),
        vertical: ResponsiveHelper.spacing(context, 2),
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: ResponsiveHelper.iconSize(context, 11), color: color),
          SizedBox(width: ResponsiveHelper.spacing(context, 3)),
          Text(
            label,
            style: ResponsiveHelper.tinyStyle(context, color: color,
                fontWeight: FontWeight.w600),
          ),
        ],
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

    // 거리 기준: 200m 이내=근처(초록), 500m 이내=주의(주황), 초과=멀리(빨강)
    // WorkerLocationModel.isNearBusiness 와 동일 기준(200m) 사용
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
      actionGroups.add([
        AppMenuSheetItem(
          icon: Icons.restart_alt,
          label: '출퇴근 초기화',
          color: AppColors.error,
          isDanger: true,
          onTap: () => _resetAttendance(app),
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
      actionGroups.add([
        AppMenuSheetItem(
          icon: Icons.restart_alt,
          label: '출퇴근 초기화',
          color: AppColors.error,
          isDanger: true,
          onTap: () => _resetAttendance(app),
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
        AppMenuSheetItem(
          icon: Icons.edit_outlined,
          label: '급여 수정',
          color: AppColors.warning,
          onTap: () => _showEditWageDialog(app),
        ),
      ]);
      actionGroups.add([
        AppMenuSheetItem(
          icon: Icons.lock_open_outlined,
          label: '마감 취소',
          color: AppColors.error,
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
        // 마감취소 버튼 (최종확정 근무자 선택 시 표시)
        if (_selectedFinalConfirmedApps.isNotEmpty) ...[
          SizedBox(height: ResponsiveHelper.spacing(context, 8)),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _batchCancelFinal,
              icon: Icon(
                Icons.lock_open_outlined,
                size: ResponsiveHelper.iconSize(context, 18),
              ),
              label: Text('마감취소 (${_selectedFinalConfirmedApps.length}명)'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.error,
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
            child: _isAllClosed
                ? OutlinedButton.icon(
                    onPressed: null,
                    icon: Icon(
                      Icons.check_circle,
                      size: ResponsiveHelper.iconSize(context, 18),
                      color: AppColors.success,
                    ),
                    label: Text(
                      '마감완료',
                      style: ResponsiveHelper.bodyStyle(context, color: AppColors.success),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: AppColors.success),
                      padding: EdgeInsets.symmetric(
                        vertical: ResponsiveHelper.spacing(context, 12),
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  )
                : ElevatedButton.icon(
                    onPressed: _canClose ? _showFinalCloseDialog : null,
                    icon: Icon(
                      Icons.lock_outline,
                      size: ResponsiveHelper.iconSize(context, 18),
                    ),
                    label: const Text('마감'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor:
                          _canClose ? AppColors.success : AppColors.grey300,
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
    if (_isLoading) return;
    int calculatedCount = 0;
    int alreadyConfirmedCount = 0;
    int noshowCount = 0;
    for (var app in _confirmedWorkers) {
      final attendance = _attendanceMap[app.id];
      if (attendance?.status == AttendanceModel.statusNoShow) {
        noshowCount++;
      } else if (attendance?.wageStatus == AttendanceModel.wageCalculated) {
        calculatedCount++;
      } else if (attendance?.wageStatus == AttendanceModel.wageConfirmed) {
        alreadyConfirmedCount++;
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
                      Text('$calculatedCount명',
                          style: ResponsiveHelper.bodyStyle(context)
                              .copyWith(fontWeight: FontWeight.bold)),
                    ],
                  ),
                  if (alreadyConfirmedCount > 0) ...[
                    SizedBox(height: ResponsiveHelper.spacing(context, 4)),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('이미 최종확정',
                            style: ResponsiveHelper.smallStyle(context,
                                color: AppColors.grey500)),
                        Text('$alreadyConfirmedCount명',
                            style: ResponsiveHelper.smallStyle(context,
                                color: AppColors.grey500)),
                      ],
                    ),
                  ],
                  if (noshowCount > 0) ...[
                    SizedBox(height: ResponsiveHelper.spacing(context, 4)),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('노쇼',
                            style: ResponsiveHelper.smallStyle(context,
                                color: AppColors.error)),
                        Text('$noshowCount명',
                            style: ResponsiveHelper.bodyStyle(context,
                                color: AppColors.error)),
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

    int successCount = 0;
    int failCount = 0;

    // 처리 대상 수집
    final targets = <({AttendanceModel attendance, ApplicationModel app})>[];
    for (var app in _confirmedWorkers) {
      final attendance = _attendanceMap[app.id];
      if (attendance == null) continue;
      if (attendance.status == AttendanceModel.statusNoShow) continue;
      if (attendance.wageStatus != AttendanceModel.wageCalculated) continue;
      targets.add((attendance: attendance, app: app));
    }

    // 단일 배치로 일괄 처리 (500개 초과 시 청크 분리)
    try {
      var batch = FirebaseFirestore.instance.batch();
      int batchCount = 0;
      final processedApps = <ApplicationModel>[];

      for (final t in targets) {
        final wd = t.attendance.wageDetail;
        final paymentDueDate = PaymentDueDateCalculator.calculate(
          payScheduleType: wd?.payScheduleType,
          payScheduleDay:  wd?.payScheduleDay,
          workDate: t.attendance.workDate,
        );
        final confirmedWageDetail = wd?.copyWith(
          confirmedBy: adminUid,
          confirmedAt: DateTime.now(),
        );

        batch.update(
          FirebaseFirestore.instance.collection('attendance').doc(t.attendance.id),
          {
            'wageStatus': AttendanceModel.wageConfirmed,
            'finalConfirmedAt': FieldValue.serverTimestamp(),
            if (adminUid != null) 'confirmedBy': adminUid,
            if (confirmedWageDetail != null) 'wageDetail': confirmedWageDetail.toMap(),
            if (paymentDueDate != null)
              'paymentDueDate': Timestamp.fromDate(paymentDueDate),
          },
        );
        batch.update(
          FirebaseFirestore.instance.collection('users').doc(t.app.uid),
          {'totalWorkDays': FieldValue.increment(1)},
        );
        batchCount += 2;
        processedApps.add(t.app);

        if (batchCount >= 498) {
          await batch.commit();
          successCount += batchCount ~/ 2;
          batch = FirebaseFirestore.instance.batch();
          batchCount = 0;
        }
      }
      if (batchCount > 0) {
        await batch.commit();
        successCount += batchCount ~/ 2;
      }

      // 배치 성공 후 신뢰도 업데이트 (개별 실패 허용)
      for (final app in processedApps) {
        try {
          await TrustScoreService().onWorkComplete(app.uid, app.businessId);
        } catch (e) {
          debugPrint('⚠️ 신뢰도 업데이트 실패 (${app.uid}): $e');
        }
      }
    } catch (e) {
      debugPrint('❌ 마감 처리 실패: $e');
      failCount = targets.length - successCount;
    }

    if (!mounted) return;

    _hasChanges = true;
    await _loadData();

    if (failCount == 0) {
      ToastHelper.showSuccess('$successCount명 최종확정 완료');
    } else {
      ToastHelper.showWarning('$successCount명 완료, $failCount명 실패');
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

    // 최신 출퇴근 기록·workDetail을 Firestore에서 재조회
    final appIds = _confirmedWorkers.map((w) => w.id).toList();
    final attendanceFuture = _getAttendanceRecords(appIds);
    final workDetailFuture = _getWorkDetailTimes();
    _attendanceMap = await attendanceFuture;
    _workDetailTimeMap = await workDetailFuture;
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
                const LoadingWidget(),
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

    // 고유한 (toId, slotId) 쌍 수집 — 동일 toId에 여러 슬롯 가능하므로 Set으로 보관
    final slotPairs = <String, Set<String>>{}; // toId → Set<slotId>
    final toIds = <String>{};                  // slotId 없는 경우 TO 폴백용
    for (final app in targetWorkers) {
      if (app.toId == null || app.toId!.isEmpty) continue;
      if (app.slotId != null && app.slotId!.isNotEmpty) {
        slotPairs.putIfAbsent(app.toId!, () => {}).add(app.slotId!);
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
          'baseHourlyWage': (data['baseHourlyWage'] as num?)?.toInt(),
          'weeklyHolidayIncluded': data['weeklyHolidayIncluded'] as bool? ?? false,
          'scheduledDaysPerWeek': (data['scheduledDaysPerWeek'] as num?)?.toInt(),
          'taxDeductionType': data['taxDeductionType'] as String?,
          'payScheduleType': data['payScheduleType'] as String?,
          'payScheduleDay': (data['payScheduleDay'] as num?)?.toInt(),
        };
        timeInfoMap[compositeKey] = entry;
        timeInfoMap[workType] ??= entry; // 레거시 폴백 키 (마지막 값 덮어씀)
      }
    }

    try {
      // 슬롯 문서 병렬 조회 (toId당 여러 슬롯 가능)
      final slotFutures = slotPairs.entries.expand((e) =>
          e.value.map((slotId) => FirebaseFirestore.instance
              .collection('tos').doc(e.key)
              .collection('slots').doc(slotId)
              .get()));
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

      // TO 마스터로 workType 단독 키를 덮어씀
      // 슬롯 동기화가 지연되어도 TO 마스터(항상 최신)로 startTime/endTime 보정
      final masterIds = slotPairs.keys.toSet();
      if (masterIds.isNotEmpty) {
        final masterFutures = masterIds.map((id) =>
            FirebaseFirestore.instance.collection('tos').doc(id).get());
        final masterDocs = await Future.wait(masterFutures);
        for (final doc in masterDocs) {
          if (!doc.exists) continue;
          final raw = doc.data()?['workDetails'] as List<dynamic>?;
          if (raw == null) continue;
          for (var wd in raw) {
            final data = Map<String, dynamic>.from(wd as Map);
            final workType = data['workType'] as String? ?? '';
            if (workType.isEmpty) continue;
            timeInfoMap[workType] = {
              'startTime': data['startTime'] ?? '',
              'endTime': data['endTime'] ?? '',
              'wage': data['wage'] ?? 0,
              'wageType': data['wageType'] ?? 'hourly',
              'breakMinutes': data['breakMinutes'] ?? 0,
              'nightAllowanceApplied': data['nightAllowanceApplied'] ?? true,
              'nightIncluded': data['nightIncluded'] ?? false,
              'shiftType': data['shiftType'],
              'baseHourlyWage': (data['baseHourlyWage'] as num?)?.toInt(),
              'weeklyHolidayIncluded': data['weeklyHolidayIncluded'] as bool? ?? false,
              'scheduledDaysPerWeek': (data['scheduledDaysPerWeek'] as num?)?.toInt(),
              'taxDeductionType': data['taxDeductionType'] as String?,
              'payScheduleType': data['payScheduleType'] as String?,
              'payScheduleDay': (data['payScheduleDay'] as num?)?.toInt(),
            };
          }
        }
      }
    } catch (e) {
      debugPrint('❌ WorkDetail 시간 조회 실패: $e');
    }

    return timeInfoMap;
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
      return FormatHelper.formatHourMinute(picked.hour, picked.minute);
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
            Semantics(
              button: true,
              label: '필터 삭제',
              child: GestureDetector(
                onTap: onClear,
                child: Icon(Icons.close, color: AppColors.grey400, size: ResponsiveHelper.iconSize(context, 16)),
              ),
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

        // 이체완료 건 스킵
        if (attendance.wageStatus == AttendanceModel.wageTransferred) {
          failCount++;
          continue;
        }

        try {
          final effectiveCheckIn  = newCheckIn  ?? attendance.checkIn  ?? app.startTime;
          final effectiveCheckOut = newCheckOut ?? attendance.checkOut;

          // 시간 역전 검사 (출퇴근 모두 있을 때만)
          if (effectiveCheckOut != null &&
              !AttendanceStatusHelper.isValidWorkPeriod(effectiveCheckIn, effectiveCheckOut)) {
            failCount++;
            continue;
          }

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

          // 시간 수정 시 1차 확정(calculated) 상태이면 미계산(pending)으로 리셋
          if (attendance.wageStatus == AttendanceModel.wageCalculated) {
            updates['wageStatus'] = AttendanceModel.wagePending;
            updates['wageDetail'] = FieldValue.delete();
          }

          await FirebaseFirestore.instance
              .collection('attendance')
              .doc(attendance.id)
              .update(updates);
          successCount++;
        } catch (e) {
          debugPrint('❌ 출결 시간 일괄 조정 실패 (${attendance.id}): $e');
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
    final nowStr = FormatHelper.formatHourMinute(roundedHour, roundedMin);

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
                              final t = FormatHelper.formatHourMinute(h, m);
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
      scheduledTimes: [WorkDetailHelper.effectiveStart(app, _workDetailTimeMap)],
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
      scheduledTimes: [WorkDetailHelper.effectiveEnd(app, _workDetailTimeMap)],
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
          final expectedStartTime = WorkDetailHelper.effectiveStart(app, _workDetailTimeMap);
          if (AttendanceStatusHelper.isLate(time, expectedStartTime)) {
            final trustService = TrustScoreService();
            await trustService.onLate(app.uid, app.businessId);
          }

          successCount++;
        } catch (e) {
          failCount++;
        }
      }

      if (successCount > 0) {
        ToastHelper.showSuccess('$successCount명 출근 처리 완료');
        _hasChanges = true;
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

        // 이체완료 건 스킵
        if (attendance.wageStatus == AttendanceModel.wageTransferred) {
          failCount++;
          continue;
        }

        try {
          final checkIn = attendance.checkIn ?? app.startTime;

          // 시간 역전 검사
          if (!AttendanceStatusHelper.isValidWorkPeriod(checkIn, time)) {
            failCount++;
            continue;
          }

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

      if (successCount > 0) {
        ToastHelper.showSuccess('$successCount명 퇴근 처리 완료');
        _hasChanges = true;
      }
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
          final expectedStartTime = WorkDetailHelper.effectiveStart(app, _workDetailTimeMap);
          if (AttendanceStatusHelper.isLate(time, expectedStartTime)) {
            await TrustScoreService().onLate(app.uid, app.businessId);
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

          // 시간 역전 검사
          if (!AttendanceStatusHelper.isValidWorkPeriod(checkIn, time)) {
            failCount++;
            continue;
          }

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

      if (successCount > 0) {
        ToastHelper.showSuccess('$successCount명 퇴근 처리 완료');
        _hasChanges = true;
      }
      if (failCount > 0) ToastHelper.showWarning('$failCount명 처리 실패');

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
      
      // 지각 여부 체크 및 신뢰도 반영 (WorkDetail 오버라이드 반영)
      final expectedStartTime = WorkDetailHelper.effectiveStart(app, _workDetailTimeMap);
      if (AttendanceStatusHelper.isLate(time, expectedStartTime)) {
        final trustService = TrustScoreService();
        await trustService.onLate(app.uid, app.businessId);
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

      // 이체완료 건은 수정 불가
      if (attendance.wageStatus == AttendanceModel.wageTransferred) {
        ToastHelper.showError('이체 완료된 급여는 수정할 수 없습니다');
        return;
      }

      // 출퇴근 시간 역전 검사
      final effIn  = checkIn  ?? attendance.checkIn;
      final effOut = checkOut ?? attendance.checkOut;
      if (effIn != null && effOut != null &&
          !AttendanceStatusHelper.isValidWorkPeriod(effIn, effOut)) {
        ToastHelper.showError('퇴근 시간이 출근 시간보다 앞서거나 16시간을 초과합니다');
        return;
      }

      // 둘 다 null → checkIn/checkOut 필드 초기화 (update, 삭제 대신)
      // BUSINESS_ADMIN은 delete 권한이 없으므로 update로 필드를 지워 미출근 상태로 되돌림
      if (checkIn == null && checkOut == null) {
        await FirebaseFirestore.instance
            .collection('attendance')
            .doc(attendance.id)
            .update({
          'checkIn': FieldValue.delete(),
          'checkInMethod': FieldValue.delete(),
          'checkInTime': FieldValue.delete(),
          'checkOut': FieldValue.delete(),
          'checkOutMethod': FieldValue.delete(),
          'checkOutTime': FieldValue.delete(),
          'workHours': FieldValue.delete(),
          'status': 'present',
          'isModified': true,
          'updatedAt': FieldValue.serverTimestamp(),
        });
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

      // 최초 수정 시 근무자 원본 기록 보존 (이후 수정에서는 변경 안 함)
      // attendance.checkIn이 null이면 보존할 원본이 없으므로 skip
      if (checkIn != null &&
          attendance.originalCheckIn == null &&
          attendance.checkIn != null) {
        updates['originalCheckIn'] = attendance.checkIn;
      }
      if (checkOut != null &&
          attendance.originalCheckOut == null &&
          attendance.checkOut != null) {
        updates['originalCheckOut'] = attendance.checkOut;
      }

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

      // 시간 수정 시 확정된 급여를 초기화 — 재계산 필요
      const resetableStatuses = [AttendanceModel.wageConfirmed, AttendanceModel.wageCalculated];
      if (resetableStatuses.contains(attendance.wageStatus)) {
        updates['wageStatus'] = AttendanceModel.wagePending;
        updates['finalWage'] = FieldValue.delete();
        updates['wageDetail'] = FieldValue.delete();
      }

      await FirebaseFirestore.instance
          .collection('attendance')
          .doc(attendance.id)
          .update(updates);

      final wasConfirmed = resetableStatuses.contains(attendance.wageStatus);
      ToastHelper.showSuccess(wasConfirmed
          ? '시간이 수정되었습니다. 급여를 다시 계산해주세요.'
          : '시간이 수정되었습니다');
      await _loadData();
    } catch (e) {
      debugPrint('❌ 시간 수정 실패: $e');
      ToastHelper.showError('시간 수정 실패');
    }
  }


  /// 출퇴근 초기화 — 출퇴근 기록 삭제 후 미출근 상태로 되돌림
  Future<void> _resetAttendance(ApplicationModel app) async {
    final user = _userMap[app.uid];
    final confirmed = await DialogHelper.showDangerConfirm(
      context,
      title: '출퇴근 초기화',
      message: '${user?.name ?? ''}의 출퇴근 기록을 삭제하고\n미출근 상태로 변경합니다.',
      confirmText: '초기화',
    );
    if (!confirmed) return;
    await _updateAttendanceTime(app, null, null);
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
    // 노쇼(패널티) vs 취소(패널티 없음) 선택
    final choice = await showModalBottomSheet<String>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('미출근 처리', style: Theme.of(ctx).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              Text('${_getDisplayName(app.uid)}님의 미출근 처리 방식을 선택하세요.',
                  style: Theme.of(ctx).textTheme.bodySmall?.copyWith(color: AppColors.grey500)),
              const SizedBox(height: 16),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const CircleAvatar(backgroundColor: AppColors.error, radius: 18,
                    child: Icon(Icons.person_off_outlined, color: Colors.white, size: 18)),
                title: Text('노쇼 처리', style: ResponsiveHelper.bodyStyle(ctx).copyWith(fontWeight: FontWeight.w600)),
                subtitle: const Text('신뢰도 감점 · 노쇼 이력 기록'),
                onTap: () => Navigator.pop(ctx, 'noshow'),
              ),
              const Divider(height: 8),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const CircleAvatar(backgroundColor: AppColors.info, radius: 18,
                    child: Icon(Icons.cancel_outlined, color: Colors.white, size: 18)),
                title: Text('취소 처리 (패널티 없음)', style: ResponsiveHelper.bodyStyle(ctx).copyWith(fontWeight: FontWeight.w600)),
                subtitle: const Text('불가피한 사정 등 패널티 없이 확정 취소'),
                onTap: () => Navigator.pop(ctx, 'cancel'),
              ),
            ],
          ),
        ),
      ),
    );

    if (choice == null || !mounted) return;

    if (choice == 'cancel') {
      await _cancelConfirmedNoPenalty(app);
      return;
    }

    // 노쇼 처리 확인
    final confirmed = await DialogHelper.showDangerConfirm(
      context,
      title: '노쇼 처리',
      message: '${_getDisplayName(app.uid)}님을 노쇼로 처리하시겠습니까?\n\n이 기록은 해당 근무자의 이력에 남습니다.',
      confirmText: '노쇼 처리',
    );

    if (!confirmed) return;



    // 1단계: attendance 기록 (핵심 — 실패 시 전체 중단)
    try {
      final existingAttendance = _attendanceMap[app.id];
      if (existingAttendance != null) {
        await FirebaseFirestore.instance
            .collection('attendance')
            .doc(existingAttendance.id)
            .update({
          'status': AttendanceModel.statusNoShow,
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
          'status': AttendanceModel.statusNoShow,
          'isModified': false,
          'modifyRequested': false,
          'wageStatus': AttendanceModel.wagePending,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
    } catch (e) {
      debugPrint('❌ 노쇼 처리 실패: $e');
      ToastHelper.showError('노쇼 처리 실패');
      return;
    }

    // 2단계: 신뢰도 업데이트 (부가 — 실패해도 노쇼 처리는 완료된 것으로 처리)
    try {
      final trustService = TrustScoreService();
      await trustService.onNoShow(app.uid, app.businessId);
    } catch (e) {
      debugPrint('⚠️ 노쇼 신뢰도 업데이트 실패 (무시): $e');
    }

    ToastHelper.showSuccess('노쇼 처리 완료');
    await _loadData();
  }

  /// 노쇼 해제 (+ 선택적으로 바로 출근 처리)
  Future<void> _cancelNoShow(ApplicationModel app) async {
    final name = _getDisplayName(app.uid);
    final confirmed = await DialogHelper.showConfirm(
      context,
      title: '노쇼 해제',
      message: '$name님의 노쇼를 해제하시겠습니까?\n\n해제 후 출근 처리를 이어서 할 수 있습니다.',
      confirmText: '해제',
    );

    if (!confirmed) return;

    // 1단계: attendance 상태 복원 (핵심)
    try {
      final attendance = _attendanceMap[app.id];
      if (attendance != null) {
        // checkIn이 없으면 노쇼 전 상태인 'scheduled'로 복원, 있으면 'present'로 복원
        final restoredStatus = attendance.checkIn != null ? 'present' : 'scheduled';
        await FirebaseFirestore.instance
            .collection('attendance')
            .doc(attendance.id)
            .update({
          'status': restoredStatus,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
    } catch (e) {
      debugPrint('❌ 노쇼 해제 실패: $e');
      ToastHelper.showError('노쇼 해제 실패');
      return;
    }

    // 2단계: 신뢰도 복원 (부가)
    try {
      final trustService = TrustScoreService();
      await trustService.onNoShowCanceled(app.uid, app.businessId);
    } catch (e) {
      debugPrint('⚠️ 노쇼 해제 신뢰도 업데이트 실패 (무시): $e');
    }

    ToastHelper.showSuccess('노쇼 해제 완료');
    await _loadData();

    // 해제 후 바로 출근 처리 여부 확인
    if (!mounted) return;
    final doCheckIn = await DialogHelper.showConfirm(
      context,
      title: '출근 처리',
      message: '$name님의 출근 시간을 바로 입력하시겠습니까?',
      confirmText: '출근 처리',
    );
    if (doCheckIn) _showCheckInDialog(app);
  }
  /// 패널티 없는 확정 취소 (불가피한 사정 등)
  Future<void> _cancelConfirmedNoPenalty(ApplicationModel app) async {
    final adminUid = Provider.of<UserProvider>(context, listen: false).currentUser?.uid;
    final name = _getDisplayName(app.uid);

    final confirmed = await DialogHelper.showConfirm(
      context,
      title: '취소 처리 (패널티 없음)',
      message: '$name님의 확정을 패널티 없이 취소하시겠습니까?\n\n신뢰도 감점 없이 확정이 취소됩니다.',
      confirmText: '취소 처리',
    );
    if (!confirmed || !mounted) return;

    final firestoreService = FirestoreService();
    final success = await firestoreService.cancelConfirmedApplication(
      app.id,
      applyNoShowPenalty: false,
      canceledBy: adminUid,
      cancelReason: 'ADMIN_CANCELED_NO_PENALTY',
    );

    if (success && mounted) {
      ToastHelper.showSuccess('패널티 없이 취소 처리되었습니다');
      await _loadData();
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

    final detail = WorkDetailHelper.resolve(app, _workDetailTimeMap);
    final shiftType = WorkDetailHelper.shiftType(detail);
    final nightIncluded = WorkDetailHelper.nightIncluded(detail);
    final schedBreak = WorkDetailHelper.breakMinutes(detail);
    final baseHourlyWage = WorkDetailHelper.baseHourlyWage(detail);
    final result = await WageDetailDialog.show(
      context: context,
      app: app,
      user: user,
      attendance: attendance,
      wage: attendance.wageDetail!,
      mode: WageDialogMode.editOnly,
      businessName: _businessNameMap[app.businessId],
      shiftType: shiftType,
      nightIncluded: nightIncluded,
      scheduledBreakMinutes: schedBreak,
      baseHourlyWage: baseHourlyWage,
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
        'finalWage': updatedWage.netWage,
        'wageDetail': updatedWage.toMap(),
        'wageStatus': AttendanceModel.wageCalculated,
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

    final detail = WorkDetailHelper.resolve(app, _workDetailTimeMap);
    final shiftType = WorkDetailHelper.shiftType(detail);
    final nightIncluded = WorkDetailHelper.nightIncluded(detail);
    final schedBreak2 = WorkDetailHelper.breakMinutes(detail);
    final baseHourlyWage2 = WorkDetailHelper.baseHourlyWage(detail);
    await WageDetailDialog.show(
      context: context,
      app: app,
      user: user,
      attendance: attendance,
      wage: attendance.wageDetail!,
      mode: WageDialogMode.confirmed,
      businessName: _businessNameMap[app.businessId],
      shiftType: shiftType,
      nightIncluded: nightIncluded,
      scheduledBreakMinutes: schedBreak2,
      baseHourlyWage: baseHourlyWage2,
    );
  }
  /// 일괄 마감 취소 (선택된 최종확정 근무자 전체)
  Future<void> _batchCancelFinal() async {
    final targets = _selectedFinalConfirmedApps;
    if (targets.isEmpty) return;

    final names = targets
        .map((a) => _userMap[a.uid]?.name ?? '알수없음')
        .join(', ');
    final confirmed = await DialogHelper.showConfirm(
      context,
      title: '마감취소 (${targets.length}명)',
      message: '$names\n\n위 근무자들의 마감을 취소하시겠습니까?\n급여확정 상태로 되돌아가며, 지원자에게 급여가 숨겨집니다.',
      confirmText: '마감취소',
    );
    if (!confirmed) return;

    int successCount = 0;
    for (final app in targets) {
      final attendance = _attendanceMap[app.id];
      if (attendance == null) continue;
      try {
        final wageDetail = attendance.wageDetail?.copyWith(
          confirmedBy: null,
          confirmedAt: null,
        );
        await FirebaseFirestore.instance
            .collection('attendance')
            .doc(attendance.id)
            .update({
          'wageStatus': AttendanceModel.wageCalculated,
          'wageDetail': wageDetail?.toMap(),
          'finalConfirmedAt': FieldValue.delete(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
        final trustService = TrustScoreService();
        await trustService.onWorkCanceled(app.uid, app.businessId);
        await FirebaseFirestore.instance
            .collection('users')
            .doc(app.uid)
            .update({'totalWorkDays': FieldValue.increment(-1)});
        final businessName = _businessNameMap[app.businessId] ?? '';
        await _firestoreService.createNotification(
          NotificationModel.createWageCancelConfirmed(
            userId: app.uid,
            businessName: businessName,
            businessId: app.businessId,
            workDate: app.workDate,
            attendanceId: attendance.id,
          ),
        );
        successCount++;
      } catch (e) {
        debugPrint('❌ 마감 취소 실패 (${app.uid}): $e');
      }
    }

    _hasChanges = true;
    if (successCount > 0) {
      ToastHelper.showSuccess('$successCount명 마감취소 완료');
    } else {
      ToastHelper.showError('마감취소에 실패했습니다');
    }
    await _loadData();
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
        'wageStatus': AttendanceModel.wageCalculated,
        'wageDetail': wageDetail?.toMap(),
        'finalConfirmedAt': FieldValue.delete(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      // 마감 시 증가했던 신뢰도·근무일수 롤백
      final trustService = TrustScoreService();
      await trustService.onWorkCanceled(app.uid, app.businessId);
      await FirebaseFirestore.instance
          .collection('users')
          .doc(app.uid)
          .update({
        'totalWorkDays': FieldValue.increment(-1),
      });

      // 지원자에게 급여 수정 중 알림 발송
      final businessName = _businessNameMap[app.businessId] ?? '';
      await _firestoreService.createNotification(
        NotificationModel.createWageCancelConfirmed(
          userId: app.uid,
          businessName: businessName,
          businessId: app.businessId,
          workDate: app.workDate,
          attendanceId: attendance.id,
        ),
      );

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

/// 컴팩트 통계 칩 데이터 클래스 (내부용)
class _StatChip {
  final String label;
  final int count;
  final Color color;
  const _StatChip(this.label, this.count, this.color);
}
