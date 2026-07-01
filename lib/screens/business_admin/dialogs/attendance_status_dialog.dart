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
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:intl/intl.dart';
// Models
import '../../../models/core/application_model.dart';
import '../../../models/core/attendance_model.dart';
import '../../../models/core/user_model.dart';
import '../../../models/core/business_work_type_model.dart';
import '../../../models/core/worker_location_model.dart';
import '../../../models/core/notification_model.dart';

// Services
import '../../../services/firestore_service.dart';

// Utils
import '../../../utils/toast_helper.dart';
import '../../../utils/responsive_helper.dart';
import '../../../utils/dialog_helper.dart';
import '../../../utils/format_helper.dart';
import '../../../utils/attendance_badge_helper.dart';
import '../../../utils/attendance_status_helper.dart';
import '../../../utils/work_detail_helper.dart';
import '../../../theme/app_colors.dart';
import '../../../widgets/common/app_checkbox.dart';
import '../../../widgets/common/app_tab_label.dart';

// Widgets
import '../../../widgets/common/loading_widget.dart';
import '../../../widgets/dialogs/worker_detail_dialog.dart';
import '../../../widgets/work_type_icon.dart';
import '../../../widgets/pickers/time_picker_bottom_sheet.dart';
import '../../../widgets/pickers/attendance_quick_time_sheet.dart';

// PDF
import '../../../utils/attendance_list_pdf.dart';
// Dialogs
import 'wage_confirm_dialog.dart';
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
  Map<String, ApplicationModel> _workerIdMap = {};   // id → worker (O(1) 조회용)
  Map<String, Map<String, dynamic>> _statusCache = {};  // _computeStatus 결과 캐시
  
  // UI 상태
  bool _isLoading = true;
  String? _selectedBusinessId;
  bool _hasChanges = false;  // ✅ 변경 여부 추적
  
  // 선택 상태
  final Set<String> _selectedIds = {};
  bool _selectAll = false;

  // 탭 / 검색
  int _currentTabIndex = 0;
  String _nameFilter = '';
  bool _showSearch = false;
  final TextEditingController _searchController = TextEditingController();

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
      // 최종확정 (confirmed) / 송금완료 (transferred) - 이미 마감됨
      else if (attendance.wageStatus == AttendanceModel.wageConfirmed ||
          attendance.wageStatus == AttendanceModel.wageTransferred) {
        count++;
      }
    }
    return count;
  }

  /// 전체 처리 완료 여부 (마감 가능)
  bool get _isAllProcessed => _confirmedWorkers.isNotEmpty && _processedCount == _confirmedWorkers.length;

  /// 선택된 최종확정 근무자 목록 (마감취소 대상)
  List<ApplicationModel> get _selectedFinalConfirmedApps {
    return _confirmedWorkers.where((app) {
      if (!_selectedIds.contains(app.id)) return false;
      final attendance = _attendanceMap[app.id];
      return attendance?.wageStatus == AttendanceModel.wageConfirmed;
    }).toList();
  }

  @override
  void initState() {
    super.initState();
    _selectedBusinessId = widget.initialBusinessId ??
        (widget.businessIds.isNotEmpty ? widget.businessIds.first : null);
    _applySavedBusinessThenLoad();
  }

  Future<void> _applySavedBusinessThenLoad() async {
    if (widget.businessIds.length > 1) {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString('alfit_last_business_id');
      if (saved != null && widget.businessIds.contains(saved) && mounted) {
        setState(() => _selectedBusinessId = saved);
      }
    }
    // SharedPreferences await 이후 두 번째 mounted 체크 — initState에서 호출되므로
    //           다이얼로그가 빠르게 닫힐 경우 dispose 후 _initializeData()가 실행되는 것을 방지.
    if (!mounted) return;
    _initializeData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// 초기 데이터 로드 (병렬)
  Future<void> _initializeData() async {
    try {
      await Future.wait([
        _loadBusinessNames(),
        _loadData(),
      ]);
    } catch (e) {
      debugPrint('❌ [당일명단] 초기화 실패: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════
  // 데이터 로드
  // ═══════════════════════════════════════════════════════════

  /// 사업장명 조회 (30개 초과 청크 처리)
  Future<void> _loadBusinessNames() async {
    try {
      final nameMap = await _firestoreService.getBusinessNames(widget.businessIds);
      if (!mounted) return;
      setState(() {
        _businessNameMap = nameMap;
      });
    } catch (e) {
      debugPrint('❌ 사업장명 조회 실패: $e');
    }
  }

  /// 전체 데이터 로드 (병렬 처리로 최적화)
  // [D05 설계] 데이터 새로고침 시 선택 상태(_selectedIds)를 초기화한다.
  // 의도된 동작: 새로고침 후 서버 데이터가 변경되면 이전 선택이 유효하지 않을 수 있으므로,
  // 잘못된 배치 처리를 방지하기 위해 항상 초기화한다.
  Future<void> _loadData() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _selectedIds.clear();
      _selectAll = false;
      _nameFilter = '';
      _searchController.clear();
    });

    try {
      // ✅ 1단계: 근무자 목록과 업무유형 정보 병렬 로드
      final step1Results = await Future.wait([
        _getConfirmedWorkersForDate(),  // [0] 확정 근무자
        _getWorkTypeInfo(),              // [1] 업무유형 정보
      ]);

      final confirmedWorkers = step1Results[0] as List<ApplicationModel>;
      final workTypeMap = step1Results[1] as Map<String, BusinessWorkTypeModel>;

      // ✅ 2단계: 근무자 기반 쿼리들 병렬 실행
      // _getWorkDetailTimes()는 confirmedWorkers의 toId/slotId가 필요하므로 1단계 완료 후 실행
      final uids = confirmedWorkers.map((app) => app.uid).toSet().toList();
      final appIds = confirmedWorkers.map((app) => app.id).toList();

      final step2Results = await Future.wait([
        _getAttendanceRecords(appIds),                              // [0] 출근 기록
        _firestoreService.getUsersBatch(uids, businessId: _selectedBusinessId ?? ''),                       // [1] 사용자 정보
        _firestoreService.getLocationsForApplications(appIds, businessId: _selectedBusinessId ?? ''),       // [2] 위치 정보
        _getWorkDetailTimes(confirmedWorkers),                        // [3] WorkDetail 시간 정보 (근무자 목록 전달)
      ]);

      final attendanceMap = step2Results[0] as Map<String, AttendanceModel>;
      final userMap = step2Results[1] as Map<String, UserModel>;
      final locationMap = step2Results[2] as Map<String, WorkerLocationModel>;
      final workDetailTimeMap = step2Results[3] as Map<String, dynamic>;

      if (!mounted) return;
      setState(() {
        _confirmedWorkers = confirmedWorkers;
        _workerIdMap = {for (final a in confirmedWorkers) a.id: a};
        _attendanceMap = attendanceMap;
        _userMap = userMap;
        _workTypeMap = workTypeMap;
        _workDetailTimeMap = workDetailTimeMap;
        _locationMap = locationMap;
        _isLoading = false;
        _rebuildStatusCache();
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
    final seenIds = <String>{};  // 단기/장기 중복 entry 방어

    // ✅ 1. 단기 공고: 서버에서 workDate 필터링 (빠름!)
    // status whereIn 복합쿼리 제거 — Firestore 보안 규칙 filters null 반환 버그 방지
    final shortTermSnapshot = await FirebaseFirestore.instance
        .collection('applications')
        .where('businessId', isEqualTo: _selectedBusinessId)
        .where('workDate', isGreaterThanOrEqualTo: Timestamp.fromDate(dateStart))
        .where('workDate', isLessThan: Timestamp.fromDate(dateEnd))
        .get();

    // 단기만 필터 (workDays가 없는 것) + 확정 상태 클라이언트 필터
    const confirmedStatuses = {AppStatus.confirmed, AppStatus.contractPending};
    for (var doc in shortTermSnapshot.docs) {
      final app = ApplicationModel.tryFromFirestore(doc);
      if (app == null) continue;
      if (!confirmedStatuses.contains(app.status)) continue;
      if (app.workDays == null || app.workDays!.isEmpty) {
        if (seenIds.add(app.id)) result.add(app);
      }
    }
    
    debugPrint('📋 [당일명단] 단기 확정자: ${result.length}명');

    // ✅ 2. 장기 공고: type='long_term' 필터로 서버 범위 축소 후 클라이언트 필터링
    // status whereIn 복합쿼리 제거 — Firestore 보안 규칙 filters null 반환 버그 방지
    final longTermSnapshot = await FirebaseFirestore.instance
        .collection('applications')
        .where('businessId', isEqualTo: _selectedBusinessId)
        .where('type', isEqualTo: AppType.longTerm)
        .get();

    int longTermCount = 0;
    for (var doc in longTermSnapshot.docs) {
      final app = ApplicationModel.tryFromFirestore(doc);
      if (app == null) continue;
      if (!confirmedStatuses.contains(app.status)) continue;
      
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
        // 퇴사/계약해지 승인 완료 근무자 제외
        if (app.isTerminationApproved) continue;
      }

      // 🔥 휴무일 체크 - 휴무일이면 제외
      if (app.leaveDates != null && app.leaveDates!.isNotEmpty) {
        final isLeaveDay = app.leaveDates!.any((leaveDate) =>
            leaveDate.year == dateStart.year &&
            leaveDate.month == dateStart.month &&
            leaveDate.day == dateStart.day);
        if (isLeaveDay) continue;
      }

      // extraWorkDates 우선 확인 — 추가 근무 승인일은 정규 요일 외에도 포함
      final isExtraWorkDay = app.isExtraWorkDateOn(dateStart);
      // 요일 체크 — workDays가 없으면 요일 불문 포함 (스케줄 미지정 고정근무자)
      final dayWeekday = FormatHelper.weekday(dateStart);
      if (isExtraWorkDay || app.workDays == null || app.workDays!.isEmpty || app.workDays!.contains(dayWeekday)) {
        if (seenIds.add(app.id)) {
          result.add(app);
          longTermCount++;
        }
      }
    }
    
    debugPrint('📋 [당일명단] 장기 확정자: $longTermCount명');
    debugPrint('📋 [당일명단] 총 확정자: ${result.length}명');

    return result;
  }

  /// 출근 기록 조회
  ///
  /// [C01 설계] applicationIds를 받지만 whereIn 필터로 사용하지 않는다.
  /// 대신 businessId + workDate 범위 쿼리로 당일 사업장 전체 출근 기록을 한 번에 가져온다.
  /// 이유: whereIn은 최대 30개 제한이 있어 N+1 문제를 유발할 수 있고,
  ///       당일 한 사업장의 출근 기록은 수십~수백 건 수준으로 단일 쿼리가 더 효율적이다.
  ///       applicationIds는 결과가 빈 경우 조기 반환을 위한 가드 조건으로만 사용된다.
  ///
  /// [BUG-수정] 야간 단기근무자 당일명단 미반영:
  ///   근무자 앱은 work.workDate(어제) 기준으로 attendance docId를 생성하므로,
  ///   오늘 자정 이후 퇴근하는 야간 단기근무자는 workDate가 전날로 저장됨.
  ///   쿼리 범위를 전날(dateStart - 1일)부터 오늘 자정까지로 확장하여 이를 포함함.
  Future<Map<String, AttendanceModel>> _getAttendanceRecords(
    List<String> applicationIds,
  ) async {
    if (applicationIds.isEmpty) return {};

    final dateStart = DateTime(widget.date.year, widget.date.month, widget.date.day);
    final dateEnd = dateStart.add(const Duration(days: 1));
    // [BUG-수정] 전날 야간 단기근무자 포함: workDate 조회 범위를 전날부터 시작
    final queryRangeStart = dateStart.subtract(const Duration(days: 1));

    final snapshot = await FirebaseFirestore.instance
        .collection('attendance')
        .where('businessId', isEqualTo: _selectedBusinessId)
        .where('workDate', isGreaterThanOrEqualTo: Timestamp.fromDate(queryRangeStart))
        .where('workDate', isLessThan: Timestamp.fromDate(dateEnd))
        .get();

    final Map<String, AttendanceModel> attendanceMap = {};

    for (var doc in snapshot.docs) {
      final attendance = AttendanceModel.tryFromFirestore(doc);
      if (attendance == null) continue;
      // applicationIds에 포함된 근무자만 맵에 저장 (전날 기록이 오늘 명단에 섞이지 않도록 필터)
      if (applicationIds.contains(attendance.applicationId)) {
        attendanceMap[attendance.applicationId] = attendance;
      }
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
        final workType = BusinessWorkTypeModel.tryFromFirestore(doc);
        if (workType != null) workTypeMap[workType.name] = workType;
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

  /// 캐시된 출퇴근 상태 반환 (build당 260회 호출 방지용)
  Map<String, dynamic> _getAttendanceStatus(ApplicationModel app) {
    return _statusCache[app.id] ?? _computeStatus(app);
  }

  /// 전체 statusCache 재빌드 — _confirmedWorkers/_attendanceMap/_workDetailTimeMap 변경 후 호출
  void _rebuildStatusCache() {
    _statusCache = {
      for (final app in _confirmedWorkers) app.id: _computeStatus(app),
    };
  }

  /// 출퇴근 상태 실제 계산 (UI 레벨 — DB status와 별개)
  Map<String, dynamic> _computeStatus(ApplicationModel app) {
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
      final checkInDisplay = attendance!.checkIn != null
          ? _trimSeconds(attendance.checkIn!)
          : '-';
      final timeText = '$checkInDisplay ~ ${_trimSeconds(attendance.checkOut!)}';

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

  /// 탭별 근로자 분류
  /// 0=검토(이슈·미출근), 1=정상, 2=확인(adminConfirmed), 3=완료(급여확정·노쇼)
  List<ApplicationModel> _workersByTab(int tabIndex) {
    const reviewStatuses = {'late', 'missed_checkout', 'early_leave'};
    const doneUiStatuses = {'transferred', 'final_confirmed', 'wage_confirmed', 'noshow'};
    return _confirmedWorkers.where((app) {
      final s = _getAttendanceStatus(app)['status'] as String;
      final attendance = _attendanceMap[app.id];
      final isDone = doneUiStatuses.contains(s) ||
                     attendance?.wageStatus == AttendanceModel.wageCalculated ||
                     attendance?.wageStatus == AttendanceModel.wageConfirmed ||
                     attendance?.wageStatus == AttendanceModel.wageTransferred ||
                     attendance?.status == AttendanceModel.statusNoShow;
      final isAdminConfirmed = attendance?.adminConfirmed == true;
      switch (tabIndex) {
        case 0: return (reviewStatuses.contains(s) || s == 'pending') && !isDone && !isAdminConfirmed;
        case 1: return !reviewStatuses.contains(s) && s != 'pending' && !isDone && !isAdminConfirmed;
        case 2: return isAdminConfirmed && !isDone;
        case 3: return isDone;
        default: return true;
      }
    }).toList();
  }



  /// 통계 계산 — [workers]를 지정하면 해당 목록만 집계 (탭별 통계)
  Map<String, int> _calculateStats({List<ApplicationModel>? workers}) {
    final list = workers ?? _confirmedWorkers;
    int total = list.length;
    int checkedIn = 0;
    int checkedOut = 0;
    int late = 0;
    int earlyArrival = 0;
    int earlyLeave = 0;
    int missedCheckout = 0;
    int noShow = 0;

    for (var app in list) {
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
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppDialogSize.borderRadius),
        ),
        insetPadding: EdgeInsets.symmetric(
          horizontal: AppDialogSize.insetH,
          vertical: AppDialogSize.insetV,
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * AppDialogSize.maxHeightRatio
                - MediaQuery.of(context).viewInsets.bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 헤더
              _buildHeader(theme, dateStr),

              // 내용 (하단 버튼 포함 — 스크롤 영역 안에 위치)
              Flexible(
                child: _isLoading
                    ? const LoadingWidget(message: '당일명단 조회 중...')
                    : _confirmedWorkers.isEmpty
                        ? _buildEmptyState()
                        : _buildContent(theme),
              ),

              // 선택 인원 확인/취소 고정 바 (선택 + 대상 있을 때만 표시)
              if (!_isLoading && _selectedIds.isNotEmpty)
                _buildSelectionConfirmBar(theme),

              // 하단 고정 바 (명단 출력 / 급여관리 / 처리현황 — 항상 표시)
              if (!_isLoading)
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
                      style: ResponsiveHelper.smallStyle(context, color: Colors.white.withValues(alpha: 0.7)),
                    ),
                  ],
                ),
              ),
              // 닫기 버튼
              Material(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(12),
                child: InkWell(
                  onTap: () => Navigator.pop(context, _hasChanges),
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

          // 사업장 선택 (2개 이상일 때만 표시)
          if (widget.businessIds.length > 1)
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
                  SharedPreferences.getInstance().then(
                    (prefs) => prefs.setString('alfit_last_business_id', value),
                  );
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
    final needsReview = _workersByTab(0);
    final normal = _workersByTab(1);
    final adminConfirmedWorkers = _workersByTab(2);
    final done = _workersByTab(3);

    return DefaultTabController(
      length: 4,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 탭 바 + 통계 + 액션바 — 스크롤 영역 밖 고정
          Padding(
            padding: EdgeInsets.fromLTRB(
                padding.left, ResponsiveHelper.spacing(context, 6),
                padding.right, 0),
            child: Column(
              children: [
                // 탭 바
                TabBar(
                  labelPadding: const EdgeInsets.symmetric(horizontal: 6),
                  labelStyle: ResponsiveHelper.smallStyle(context, fontWeight: FontWeight.bold),
                  unselectedLabelStyle: ResponsiveHelper.smallStyle(context),
                  onTap: (index) {
                    setState(() {
                      _currentTabIndex = index;
                      _selectedIds.clear();
                      _selectAll = false;
                      _showSearch = false;
                      _nameFilter = '';
                      _searchController.clear();
                    });
                  },
                  tabs: [
                    Tab(child: AppTabLabel(label: '검토', count: needsReview.length, urgent: needsReview.isNotEmpty)),
                    Tab(child: AppTabLabel(label: '정상', count: normal.length)),
                    Tab(child: AppTabLabel(label: '확인', count: adminConfirmedWorkers.length, badgeColor: AppColors.info)),
                    Tab(child: AppTabLabel(label: '완료', count: done.length, badgeColor: AppColors.grey500)),
                  ],
                ),
                SizedBox(height: ResponsiveHelper.spacing(context, 8)),
                _buildCompactStats(theme, _confirmedWorkers),
                SizedBox(height: ResponsiveHelper.spacing(context, 8)),
                _buildBatchActionBar(theme),
                SizedBox(height: ResponsiveHelper.spacing(context, 8)),
              ],
            ),
          ),

          // 탭별 콘텐츠 — 스크롤
          Flexible(
            child: TabBarView(
              physics: const NeverScrollableScrollPhysics(),
              children: [
                _buildTabContent(theme, needsReview, padding),
                _buildTabContent(theme, normal, padding),
                _buildTabContent(theme, adminConfirmedWorkers, padding),
                _buildTabContent(theme, done, padding),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 탭 라벨 위젯 (카운트 배지 포함)
  /// 탭별 콘텐츠 (빈 상태 또는 업무 그룹 목록)
  Widget _buildTabContent(ThemeData theme, List<ApplicationModel> tabWorkers, EdgeInsets padding) {
    if (tabWorkers.isEmpty) {
      return Center(
        child: Text(
          '해당 근무자가 없습니다',
          style: ResponsiveHelper.bodyStyle(context, color: AppColors.grey500),
        ),
      );
    }
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(padding.left, 0, padding.right, 0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildWorkTypeGroups(theme, workers: tabWorkers),
        ],
      ),
    );
  }

  /// 통계 컴팩트 스트립 — 현재 탭 기준 수치만 표시
  Widget _buildCompactStats(ThemeData theme, List<ApplicationModel> tabWorkers) {
    final stats = _calculateStats(workers: tabWorkers);
    final badges = <_StatChip>[];
    if ((stats['earlyArrival'] ?? 0) > 0) badges.add(_StatChip('조출', stats['earlyArrival']!, AppColors.success));
    if ((stats['late'] ?? 0) > 0)              badges.add(_StatChip('지각', stats['late']!, AppColors.warningDark));
    if ((stats['earlyLeave'] ?? 0) > 0)        badges.add(_StatChip('조퇴', stats['earlyLeave']!, AppColors.amber));
    if ((stats['missedCheckout'] ?? 0) > 0)    badges.add(_StatChip('미퇴근', stats['missedCheckout']!, AppColors.error));

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 10),
        vertical: ResponsiveHelper.spacing(context, 6),
      ),
      decoration: BoxDecoration(
        color: theme.primaryColor.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: theme.primaryColor.withValues(alpha: 0.12)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 주요 4개 — Expanded로 균등 분배 (오버플로우 방지)
          Row(
            children: [
              Expanded(child: _buildStatCell('확정',   stats['total']!,        AppColors.info)),
              _buildStatDivider(),
              Expanded(child: _buildStatCell('출근',   stats['checkedIn']!,    AppColors.success)),
              _buildStatDivider(),
              Expanded(child: _buildStatCell('미출근', stats['notCheckedIn']!, AppColors.warning)),
              _buildStatDivider(),
              Expanded(child: _buildStatCell('노쇼',   stats['noShow']!,       AppColors.error)),
            ],
          ),
          // 보조 통계 — 이상 있을 때만 두 번째 줄
          if (badges.isNotEmpty) ...[
            SizedBox(height: ResponsiveHelper.spacing(context, 4)),
            Wrap(
              spacing: ResponsiveHelper.spacing(context, 10),
              runSpacing: 0,
              children: badges.map((b) => _buildMiniDot(b)).toList(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStatCell(String label, int count, Color color) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$count명',
          style: ResponsiveHelper.smallStyle(context).copyWith(
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(label, style: ResponsiveHelper.tinyStyle(context, color: AppColors.grey500)),
      ],
    );
  }

  Widget _buildStatDivider() => Container(
    width: 1, height: 24, color: AppColors.grey200,
    margin: EdgeInsets.symmetric(horizontal: ResponsiveHelper.spacing(context, 4)),
  );

  Widget _buildMiniDot(_StatChip c) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 6, height: 6, decoration: BoxDecoration(color: c.color, shape: BoxShape.circle)),
        const SizedBox(width: 3),
        Text('${c.label} ${c.count}명', style: ResponsiveHelper.tinyStyle(context, color: AppColors.grey600)),
      ],
    );
  }

  /// 일괄 처리 액션 바
  Widget _buildBatchActionBar(ThemeData theme) {
    int checkInCount = 0;
    int adjustCount = 0;
    int checkOutCount = 0;
    int resetCount = 0;

    for (final id in _selectedIds) {
      final app = _workerIdMap[id];
      if (app == null) continue;
      final s = _getAttendanceStatus(app)['status'] as String;
      final att = _attendanceMap[app.id];
      if (s == 'pending') {
        checkInCount++;
      } else {
        adjustCount++;
        if (s == 'checkin' || s == 'late' || s == 'missed_checkout') checkOutCount++;
      }
      if (att?.checkIn != null) resetCount++;
    }

    // 탭별 조건부 칩
    final tabWorkers = _workersByTab(_currentTabIndex);
    final noShowTargets = _currentTabIndex == 0
        ? tabWorkers.where((a) => _getAttendanceStatus(a)['status'] == 'pending').toList()
        : <ApplicationModel>[];
    final cancelNoShowTargets = _currentTabIndex == 3
        ? tabWorkers.where((a) => _attendanceMap[a.id]?.status == AttendanceModel.statusNoShow).toList()
        : <ApplicationModel>[];

    return Container(
      padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 10)),
      decoration: BoxDecoration(
        color: AppColors.grey100,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Row 1: 전체 선택 + 조건부 칩 + 검색
          Row(
            children: [
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _toggleSelectAll(!_selectAll),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AppCheckbox(value: _selectAll, onTap: () => _toggleSelectAll(!_selectAll)),
                    SizedBox(width: ResponsiveHelper.spacing(context, 6)),
                    Text('전체', style: ResponsiveHelper.smallStyle(context)),
                    Builder(builder: (ctx) {
                      // 현재 탭 workers 중 선택된 수만 표시
                      final tabSelectedCount = tabWorkers
                          .where((a) => _selectedIds.contains(a.id))
                          .length;
                      if (tabSelectedCount == 0) return const SizedBox.shrink();
                      return Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(width: ResponsiveHelper.spacing(context, 4)),
                          Container(
                            padding: EdgeInsets.symmetric(
                              horizontal: ResponsiveHelper.spacing(context, 6),
                              vertical: ResponsiveHelper.spacing(context, 2),
                            ),
                            decoration: BoxDecoration(
                              color: theme.primaryColor.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text('$tabSelectedCount',
                                style: ResponsiveHelper.tinyStyle(context, color: theme.primaryColor, fontWeight: FontWeight.bold)),
                          ),
                        ],
                      );
                    }),
                  ],
                ),
              ),
              const Spacer(),
              // 노쇼 칩 (검토 탭)
              if (noShowTargets.isNotEmpty)
                _buildActionChip(
                  label: '노쇼 (${noShowTargets.length})',
                  color: AppColors.error,
                  onTap: () => _showBatchNoShowDialog(noShowTargets),
                ),
              // 노쇼취소 칩 (완료 탭)
              if (cancelNoShowTargets.isNotEmpty)
                _buildActionChip(
                  label: '노쇼취소 (${cancelNoShowTargets.length})',
                  color: AppColors.info,
                  onTap: () => _showBatchCancelNoShowDialog(cancelNoShowTargets),
                ),
              SizedBox(width: ResponsiveHelper.spacing(context, 6)),
              // 이름 검색 돋보기
              InkWell(
                onTap: () => setState(() {
                  _showSearch = !_showSearch;
                  if (!_showSearch) { _nameFilter = ''; _searchController.clear(); }
                }),
                borderRadius: BorderRadius.circular(6),
                child: Padding(
                  padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 4)),
                  child: Icon(
                    _showSearch ? Icons.search_off : Icons.search,
                    size: ResponsiveHelper.iconSize(context, 18),
                    color: _showSearch ? theme.primaryColor : AppColors.grey500,
                  ),
                ),
              ),
            ],
          ),

          // 검색 필드 (토글)
          if (_showSearch) ...[
            SizedBox(height: ResponsiveHelper.spacing(context, 6)),
            TextField(
              controller: _searchController,
              autofocus: true,
              style: ResponsiveHelper.tinyStyle(context),
              decoration: InputDecoration(
                hintText: '이름 검색',
                hintStyle: ResponsiveHelper.tinyStyle(context, color: AppColors.grey400),
                isDense: true,
                contentPadding: EdgeInsets.symmetric(
                  horizontal: ResponsiveHelper.spacing(context, 10),
                  vertical: ResponsiveHelper.spacing(context, 7),
                ),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: AppColors.border)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: AppColors.border)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: theme.primaryColor)),
                filled: true,
                fillColor: Colors.white,
                suffixIconConstraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                suffixIcon: _nameFilter.isNotEmpty
                    ? GestureDetector(
                        onTap: () => setState(() { _nameFilter = ''; _searchController.clear(); }),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          child: Icon(Icons.clear, size: ResponsiveHelper.iconSize(context, 14), color: AppColors.grey400),
                        ),
                      )
                    : null,
              ),
              onChanged: (v) => setState(() => _nameFilter = v.trim()),
            ),
          ],

          SizedBox(height: ResponsiveHelper.spacing(context, 8)),

          // Row 2: 출근 / 조정 / 퇴근 / 리셋 — 4개 버튼
          Row(
            children: [
              Expanded(child: _buildActionButton(icon: Icons.login,    label: '출근', color: AppColors.success, count: checkInCount,  onPressed: checkInCount > 0  ? _showBatchCheckInDialog  : null)),
              SizedBox(width: ResponsiveHelper.spacing(context, 5)),
              Expanded(child: _buildActionButton(icon: Icons.tune,     label: '조정', color: AppColors.info,    count: adjustCount,   onPressed: adjustCount > 0   ? _showBatchAdjustTimeDialog : null)),
              SizedBox(width: ResponsiveHelper.spacing(context, 5)),
              Expanded(child: _buildActionButton(icon: Icons.logout,   label: '퇴근', color: AppColors.purple,  count: checkOutCount, onPressed: checkOutCount > 0 ? _showBatchCheckOutDialog : null)),
              SizedBox(width: ResponsiveHelper.spacing(context, 5)),
              Expanded(child: _buildActionButton(icon: Icons.refresh,  label: '리셋', color: AppColors.grey600, count: resetCount,    onPressed: resetCount > 0    ? _showBatchResetDialog   : null)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildActionChip({required String label, required Color color, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: ResponsiveHelper.spacing(context, 8),
          vertical: ResponsiveHelper.spacing(context, 4),
        ),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Text(label, style: ResponsiveHelper.tinyStyle(context, color: color, fontWeight: FontWeight.bold)),
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

  /// 시간 문자열 정규화 — HH:mm 앞 5자리만 사용 (HH:mm:ss 형식 차이 제거)
  String _normalizeTimeKey(String t) {
    final s = t.trim();
    return s.length >= 5 ? s.substring(0, 5) : s;
  }

  /// 업무별 그룹
  Widget _buildWorkTypeGroups(ThemeData theme, {List<ApplicationModel>? workers}) {
    // ✅ workType + 시간 조합으로 그룹화 (장기/단기 합침)
    final Map<String, List<ApplicationModel>> workTypeGroups = {};

    final sourceWorkers = workers ?? _confirmedWorkers;
    final filteredSource = _nameFilter.isEmpty
        ? sourceWorkers
        : sourceWorkers.where((app) {
            final name = _userMap[app.uid]?.name ?? '';
            return name.contains(_nameFilter);
          }).toList();

    for (var app in filteredSource) {
      // app.startTime/endTime으로 그룹화 — effectiveStart는 workType 단위 캐시라
      // 같은 workType의 다른 시간대 TO가 섞이므로 사용하지 않음
      final normStart = _normalizeTimeKey(app.startTime);
      final normEnd   = _normalizeTimeKey(app.endTime);
      final groupKey  = '${app.selectedWorkType.trim()}_${normStart}_$normEnd';

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
          padding: EdgeInsets.only(bottom: ResponsiveHelper.spacing(context, 12)),
          child: _buildWorkTypeSection(
            theme,
            firstApp.selectedWorkType,
            entry.value,
            groupKey: entry.key,
            startTime: _normalizeTimeKey(firstApp.startTime),
            endTime: _normalizeTimeKey(firstApp.endTime),
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
    // isNotEmpty 가드 내부 — workers.first 안전
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
                padding: EdgeInsets.symmetric(
                  horizontal: ResponsiveHelper.spacing(context, 12),
                  vertical: ResponsiveHelper.spacing(context, 10),
                ),
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
                      padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 6)),
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
                    // 출근현황 + 전체확인/취소 칩 + 정렬 토글
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        // 출근 현황 배지
                        Builder(builder: (ctx) {
                          return Container(
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
                            );
                        }),
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
            padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 8)),
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
      margin: EdgeInsets.only(bottom: ResponsiveHelper.spacing(context, 6)),
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
          onTap: () {
            final user = _userMap[app.uid];
            if (user != null) {
              final statusInfo = _getAttendanceStatus(app);
              WorkerDetailDialog.show(
                context: context,
                user: user,
                application: app,
                businessId: _selectedBusinessId,
                isConfirmed: true,
                showApprovalButtons: false,
                attendanceStatus: statusInfo['status'] as String,
                onStatusChanged: () {
                  _hasChanges = true;
                  _loadData();
                },
              );
            }
          },
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: ResponsiveHelper.spacing(context, 12),
              vertical: ResponsiveHelper.spacing(context, 8),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // 체크박스 — GestureDetector로 격리하여 카드 탭과 분리
                GestureDetector(
                  onTap: () => _toggleSelection(app.id),
                  behavior: HitTestBehavior.opaque,
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: ResponsiveHelper.spacing(context, 8),
                      vertical: ResponsiveHelper.spacing(context, 10),
                    ),
                    child: AppCheckbox(value: isSelected),
                  ),
                ),

                SizedBox(width: ResponsiveHelper.spacing(context, 8)),

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

                          // GPS 의심 출근 배지 (CF 서버 검증 결과)
                          if (_attendanceMap[app.id]?.checkInSuspicious == true)
                            _buildCheckInSuspiciousBadge(_attendanceMap[app.id]!),

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

                // 확인/취소 버튼
                _buildConfirmButton(app),
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

  /// GPS 의심 출근 배지 — CF 서버 검증에서 반경 초과로 마킹된 경우 표시
  Widget _buildCheckInSuspiciousBadge(AttendanceModel attendance) {
    final distance = attendance.checkInDistance;
    final label = distance != null ? '위치의심 ${distance}m' : '위치의심';
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 6),
        vertical: ResponsiveHelper.spacing(context, 2),
      ),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.location_off_outlined,
              size: ResponsiveHelper.iconSize(context, 11),
              color: AppColors.error),
          SizedBox(width: ResponsiveHelper.spacing(context, 3)),
          Text(
            label,
            style: ResponsiveHelper.tinyStyle(context,
                color: AppColors.error, fontWeight: FontWeight.w600),
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

  /// 확인/취소 버튼
  /// - 완료 탭(isDone): 숨김
  /// - 확인 탭(adminConfirmed): ✕ 버튼
  /// - 그 외 + 출퇴근 둘 다 있음: ✓ 버튼
  Widget _buildConfirmButton(ApplicationModel app) {
    final attendance = _attendanceMap[app.id];
    final isDone = attendance?.wageStatus == AttendanceModel.wageCalculated ||
                   attendance?.wageStatus == AttendanceModel.wageConfirmed ||
                   attendance?.wageStatus == AttendanceModel.wageTransferred ||
                   attendance?.status == AttendanceModel.statusNoShow;
    if (isDone) return const SizedBox.shrink();
    final isAdminConfirmed = attendance?.adminConfirmed == true;
    if (isAdminConfirmed) {
      return IconButton(
        onPressed: () => _unconfirmWorker(app),
        icon: Icon(Icons.close, color: AppColors.error, size: ResponsiveHelper.iconSize(context, 22)),
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(),
        visualDensity: VisualDensity.compact,
      );
    }
    final canConfirm = attendance?.checkIn != null && attendance?.checkOut != null;
    if (!canConfirm) return const SizedBox.shrink();
    return IconButton(
      onPressed: () => _confirmWorker(app),
      icon: Icon(Icons.check_circle_outline, color: AppColors.success, size: ResponsiveHelper.iconSize(context, 22)),
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(),
      visualDensity: VisualDensity.compact,
    );
  }

  // adminConfirmed는 관리자 내부 워크플로 전용 필드다.
  // 지원자 앱(schedule_card)은 wageStatus/checkIn/checkOut/status 기준으로만 상태를 표시하며
  // adminConfirmed를 참조하지 않는다 — 의도된 설계.
  // 알림도 발송하지 않는다: 1차 확인은 관리자 정산 준비 단계이고,
  // 지원자에게는 최종 마감(wageConfirmed) 시점에만 급여 알림이 전송된다.
  Future<void> _confirmWorker(ApplicationModel app) async {
    final attendance = _attendanceMap[app.id];
    if (attendance == null) return;
    try {
      await FirebaseFirestore.instance
          .collection('attendance')
          .doc(attendance.id)
          .update({'adminConfirmed': true, 'updatedAt': FieldValue.serverTimestamp()});
      if (!mounted) return;
      setState(() {
        _attendanceMap[app.id] = attendance.copyWith(adminConfirmed: true);
        _selectedIds.remove(app.id);
        _hasChanges = true;
        _rebuildStatusCache();
      });
    } catch (e) {
      debugPrint('❌ 확인 처리 실패: $e');
      if (!mounted) return;
      ToastHelper.showError('확인 처리 실패');
    }
  }

  Future<void> _unconfirmWorker(ApplicationModel app) async {
    final attendance = _attendanceMap[app.id];
    if (attendance == null) return;
    try {
      await FirebaseFirestore.instance
          .collection('attendance')
          .doc(attendance.id)
          .update({'adminConfirmed': false, 'updatedAt': FieldValue.serverTimestamp()});
      if (!mounted) return;
      setState(() {
        _attendanceMap[app.id] = attendance.copyWith(adminConfirmed: false);
        _hasChanges = true;
        _rebuildStatusCache();
      });
    } catch (e) {
      debugPrint('❌ 확인 취소 실패: $e');
      if (!mounted) return;
      ToastHelper.showError('확인 취소 실패');
    }
  }

  /// 선택 인원 기반 확인/취소 고정 바 — 선택된 근무자 중 대상이 있을 때만 표시
  Widget _buildSelectionConfirmBar(ThemeData theme) {
    final tabWorkers = _workersByTab(_currentTabIndex);
    final selectedWorkers = tabWorkers.where((a) => _selectedIds.contains(a.id)).toList();

    final confirmable = selectedWorkers.where((a) {
      final att = _attendanceMap[a.id];
      final isDone = att?.wageStatus == AttendanceModel.wageCalculated ||
                     att?.wageStatus == AttendanceModel.wageConfirmed ||
                     att?.wageStatus == AttendanceModel.wageTransferred ||
                     att?.status == AttendanceModel.statusNoShow;
      return !isDone &&
          att?.checkIn != null && att?.checkOut != null &&
          att?.adminConfirmed != true &&
          att?.status != AttendanceModel.statusNoShow;
    }).toList();

    final cancellable = selectedWorkers.where((a) {
      final att = _attendanceMap[a.id];
      final isDone = att?.wageStatus == AttendanceModel.wageCalculated ||
                     att?.wageStatus == AttendanceModel.wageConfirmed ||
                     att?.wageStatus == AttendanceModel.wageTransferred ||
                     att?.status == AttendanceModel.statusNoShow;
      return !isDone && att?.adminConfirmed == true;
    }).toList();

    if (confirmable.isEmpty && cancellable.isEmpty) return const SizedBox.shrink();

    return SafeArea(
      top: false,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: ResponsiveHelper.spacing(context, 16),
          vertical: ResponsiveHelper.spacing(context, 10),
        ),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: AppColors.border)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 8,
              offset: const Offset(0, -3),
            ),
          ],
        ),
        child: Row(
          children: [
            if (confirmable.isNotEmpty) Expanded(
              child: ElevatedButton.icon(
                onPressed: () => _batchGroupConfirm(confirmable),
                icon: Icon(Icons.check_circle_outline, size: ResponsiveHelper.iconSize(context, 16)),
                label: Text('확인 ${confirmable.length}명'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.success,
                  foregroundColor: Colors.white,
                  padding: EdgeInsets.symmetric(vertical: ResponsiveHelper.spacing(context, 12)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  textStyle: ResponsiveHelper.bodyStyle(context).copyWith(fontWeight: FontWeight.w600),
                ),
              ),
            ),
            if (confirmable.isNotEmpty && cancellable.isNotEmpty)
              SizedBox(width: ResponsiveHelper.spacing(context, 8)),
            if (cancellable.isNotEmpty) Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _batchGroupCancelConfirm(cancellable),
                icon: Icon(Icons.undo_outlined, size: ResponsiveHelper.iconSize(context, 16)),
                label: Text('취소 ${cancellable.length}명'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.warning,
                  side: BorderSide(color: AppColors.warning.withValues(alpha: 0.6)),
                  padding: EdgeInsets.symmetric(vertical: ResponsiveHelper.spacing(context, 12)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  textStyle: ResponsiveHelper.bodyStyle(context).copyWith(fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // [B01/B02 설계 검토] WriteBatch 500 ops 제한 관련:
  // 그룹 확인/취소는 당일 한 사업장의 한 파트(업무유형+시간대) 단위로 실행된다.
  // 실제 서비스에서 단일 파트에 500명이 동시에 근무하는 경우는 현실적으로 불가능하다.
  // (일반 아르바이트 사업장 최대 규모 기준 파트당 50~100명 수준)
  // 따라서 단순 batch 1개 사용으로 충분하다. 분할 처리 불필요.
  Future<void> _batchGroupConfirm(List<ApplicationModel> confirmable) async {
    if (_isLoading) return;
    final ok = await DialogHelper.showConfirm(
      context,
      title: '그룹 전체 확인',
      message: '${confirmable.length}명을 일괄 확인 처리합니까?',
      confirmText: '확인',
      icon: Icons.check_circle_outline,
      confirmColor: AppColors.success,
    );
    if (!ok || !mounted) return;
    setState(() => _isLoading = true);
    try {
      final batch = FirebaseFirestore.instance.batch();
      for (final a in confirmable) {
        final att = _attendanceMap[a.id];
        if (att == null) continue;
        batch.update(
          FirebaseFirestore.instance.collection('attendance').doc(att.id),
          {'adminConfirmed': true, 'updatedAt': FieldValue.serverTimestamp()},
        );
      }
      await batch.commit();
      if (!mounted) return;
      setState(() {
        for (final a in confirmable) {
          final att = _attendanceMap[a.id];
          if (att != null) _attendanceMap[a.id] = att.copyWith(adminConfirmed: true);
          _selectedIds.remove(a.id);
        }
        _isLoading = false;
        _hasChanges = true;
        _rebuildStatusCache();
      });
    } catch (e) {
      debugPrint('❌ 그룹 전체 확인 실패: $e');
      if (!mounted) return;
      ToastHelper.showError('그룹 전체 확인 실패');
    } finally {
      if (mounted && _isLoading) setState(() => _isLoading = false);
    }
  }

  Future<void> _batchGroupCancelConfirm(List<ApplicationModel> cancellable) async {
    if (_isLoading) return;
    final ok = await DialogHelper.showConfirm(
      context,
      title: '그룹 전체 취소',
      message: '${cancellable.length}명의 확인을 일괄 취소합니까?',
      confirmText: '취소 처리',
      icon: Icons.undo_outlined,
      confirmColor: AppColors.warning,
    );
    if (!ok || !mounted) return;
    setState(() => _isLoading = true);
    try {
      final batch = FirebaseFirestore.instance.batch();
      for (final a in cancellable) {
        final att = _attendanceMap[a.id];
        if (att == null) continue;
        batch.update(
          FirebaseFirestore.instance.collection('attendance').doc(att.id),
          {'adminConfirmed': false, 'updatedAt': FieldValue.serverTimestamp()},
        );
      }
      await batch.commit();
      if (!mounted) return;
      setState(() {
        for (final a in cancellable) {
          final att = _attendanceMap[a.id];
          if (att != null) _attendanceMap[a.id] = att.copyWith(adminConfirmed: false);
        }
        _isLoading = false;
        _hasChanges = true;
        _rebuildStatusCache();
      });
    } catch (e) {
      debugPrint('❌ 그룹 전체 취소 실패: $e');
      if (!mounted) return;
      ToastHelper.showError('그룹 전체 확인 취소 실패');
    } finally {
      if (mounted && _isLoading) setState(() => _isLoading = false);
    }
  }

  /// 하단 버튼 바
  Widget _buildBottomBar(ThemeData theme) {
    return Container(
      padding: ResponsiveHelper.cardPadding(context),
      decoration: BoxDecoration(
        color: AppColors.grey50,
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

          // 급여관리 버튼
          Expanded(
            child: ElevatedButton.icon(
              onPressed: _confirmedWorkers.isNotEmpty ? _showWageConfirmDialog : null,
              icon: Icon(Icons.payments, size: ResponsiveHelper.iconSize(context, 18)),
              label: const Text('급여관리'),
              style: ElevatedButton.styleFrom(
                backgroundColor:
                    _confirmedWorkers.isNotEmpty ? Theme.of(context).primaryColor : AppColors.grey300,
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

  /// 처리현황 Row
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
      ],
    );
  }

  /// 급여 확정 다이얼로그 열기
  Future<void> _showWageConfirmDialog() async {
    if (_isLoading) return;
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
    if (!mounted) return;
    _workDetailTimeMap = await workDetailFuture;
    if (!mounted) return;
    _rebuildStatusCache();

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
        // onConfirmed/onClose에서 _loadData() 미호출
        // — 다이얼로그 열려 있는 동안은 부모 화면이 보이지 않으므로 갱신 불필요
        // — 다이얼로그 닫힌 후 hasChanges 반환값으로 아래에서 1회만 호출
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
      await Future<void>.delayed(Duration.zero);

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
      if (mounted) Navigator.pop(context);
      debugPrint('❌ 명단 출력 실패: $e\n$stack');
      // [BUG-12 수정] Navigator.pop mounted 체크 후 ToastHelper도 mounted 확인
      if (mounted) ToastHelper.showError('명단 출력 실패');
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
        // 'HH:mm:ss' → 'HH:mm' 정규화 (레거시 데이터 대응)
        final rawStart = data['startTime'] as String? ?? '';
        final rawEnd = data['endTime'] as String? ?? '';
        final startTime = rawStart.length >= 5 ? rawStart.substring(0, 5) : rawStart;
        final endTime = rawEnd.length >= 5 ? rawEnd.substring(0, 5) : rawEnd;
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

      // TO 마스터로 slotId 없는 경우의 workType 키 폴백 보정
      // 슬롯 문서가 이미 데이터를 채웠으면 덮어쓰지 않음 (??=)
      // → 슬롯 수정 시 TO 마스터(구시간)가 최신 슬롯값을 되돌리는 버그 방지
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
            timeInfoMap[workType] ??= {
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

  /// 전체 선택/해제 — 검색 필터가 활성화된 경우 화면에 보이는 인원만 대상
  void _toggleSelectAll(bool value) {
    setState(() {
      _selectAll = value;
      if (value) {
        _selectedIds.clear();
        final tabWorkers = _workersByTab(_currentTabIndex);
        final visibleWorkers = _nameFilter.isEmpty
            ? tabWorkers
            : tabWorkers.where((app) {
                final name = _userMap[app.uid]?.name ?? '';
                return name.contains(_nameFilter);
              }).toList();
        for (var app in visibleWorkers) {
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
  // ─── 배치 노쇼 처리 ───────────────────────────────────────────

  // [F-32/A02 설계 검토] 노쇼 배치 WriteBatch 500 ops 제한:
  // 노쇼 대상은 당일 단일 사업장의 '미출근(pending)' 인원에 한정된다.
  // 레코드가 없는 경우 set(), 있는 경우 update() 1 op씩이므로 targets.length개의 op가 발생한다.
  // 현실적 최대 규모(하루 수백 명)는 단일 batch(500 ops)로 충분하다.
  Future<void> _showBatchNoShowDialog(List<ApplicationModel> targets) async {
    if (_isLoading) return; // 중복 실행 방어
    final names = targets.map((a) => _getDisplayName(a.uid)).join(', ');
    final confirmed = await DialogHelper.showDangerConfirm(
      context,
      title: '일괄 노쇼 처리',
      message: '미출근 ${targets.length}명을 노쇼 처리합니다.\n노쇼 이력이 기록됩니다.\n\n$names',
      confirmText: '노쇼 처리',
    );
    if (!confirmed || !mounted) return;

    // [Bug A-NOSHOW-01 수정] 미출근자(pending 상태)는 attendance 레코드가 없을 수 있다.
    // batch.update()는 기존 문서만 수정하므로, 레코드가 없는 경우 batch.set()으로 신규 생성한다.
    // 노쇼 처리 대상은 checkIn이 없는 미출근자이므로, 신규 생성 레코드에는 checkIn/checkOut 없음.
    final batch = FirebaseFirestore.instance.batch();
    final now = FieldValue.serverTimestamp();
    // 신규 생성된 attendance 참조를 로컬 상태 갱신에 쓰기 위해 보관
    final Map<String, String> newAttendanceIds = {}; // appId → newDocId

    for (final app in targets) {
      final att = _attendanceMap[app.id];
      if (att != null) {
        // 기존 레코드 업데이트
        // [BUG-수정] 노쇼 처리 시 wageStatus 영구 wagePending 문제:
        //   노쇼는 실제 근무가 없으므로 급여 확정이 불필요. wageStatus를 wageConfirmed로 설정하여
        //   급여 정산 화면 "미계산" 목록에 계속 표시되는 불편함을 제거함.
        //   기존 레코드의 wageStatus가 아직 wagePending인 경우에만 wageConfirmed로 전환.
        final Map<String, dynamic> updateFields = {
          'status': AttendanceModel.statusNoShow,
          'updatedAt': now,
        };
        if (att.wageStatus == AttendanceModel.wagePending) {
          updateFields['wageStatus'] = AttendanceModel.wageConfirmed;
          updateFields['finalWage'] = 0;
        }
        batch.update(
          FirebaseFirestore.instance.collection('attendance').doc(att.id),
          updateFields,
        );
      } else {
        // 레코드 없는 미출근자 → 신규 노쇼 레코드 생성
        // [BUG-수정] 노쇼 신규 생성 시 wagePending 대신 wageConfirmed(finalWage:0)로 설정하여
        //   급여 정산 화면 "미계산" 목록 누적 방지.
        // 결정적 docId(applicationId_yyyyMMdd)로 중복 생성 방지 — checkIn()과 동일 패턴.
        final noShowDateStr = DateFormat('yyyyMMdd').format(widget.date);
        final noShowDocId = '${app.id}_$noShowDateStr';
        final newRef = FirebaseFirestore.instance.collection('attendance').doc(noShowDocId);
        newAttendanceIds[app.id] = newRef.id;
        batch.set(newRef, {
          'applicationId': app.id,
          'userId': app.uid,
          'businessId': app.businessId,
          'businessName': app.businessName,
          'workDate': Timestamp.fromDate(widget.date),
          'workType': app.selectedWorkType,
          'status': AttendanceModel.statusNoShow,
          'wageStatus': AttendanceModel.wageConfirmed,
          'finalWage': 0,
          'isModified': false,
          'modifyRequested': false,
          'createdAt': now,
          'updatedAt': now,
        });
      }
    }
    try {
      await batch.commit();
      // TrustScore noShowCount/trustScore는 onAttendanceWageStatusChanged CF 트리거에서 서버 자동 처리
      if (!mounted) return;
      setState(() {
        for (final app in targets) {
          final att = _attendanceMap[app.id];
          if (att != null) {
            _attendanceMap[app.id] = att.copyWith(status: AttendanceModel.statusNoShow);
          } else if (newAttendanceIds.containsKey(app.id)) {
            // 새로 생성된 attendance 로컬 반영 — 다음 _loadData() 전까지 상태 표시용
            // [BUG-수정] 로컬 상태도 wageConfirmed/finalWage:0 으로 일치시킴
            _attendanceMap[app.id] = AttendanceModel(
              id: newAttendanceIds[app.id]!,
              applicationId: app.id,
              userId: app.uid,
              businessId: app.businessId,
              businessName: app.businessName,
              workDate: widget.date,
              workType: app.selectedWorkType,
              status: AttendanceModel.statusNoShow,
              wageStatus: AttendanceModel.wageConfirmed,
              finalWage: 0,
              createdAt: DateTime.now(),
            );
          }
        }
        _selectedIds.clear();
        _hasChanges = true;
        _rebuildStatusCache();
      });
      ToastHelper.showSuccess('노쇼 처리 완료 (${targets.length}명)');
    } catch (e) {
      debugPrint('❌ 배치 노쇼 실패: $e');
      if (!mounted) return;
      ToastHelper.showError('노쇼 처리 실패');
    }
  }

  // [F-33/A03 설계 검토] 노쇼 취소 배치 WriteBatch 500 ops 제한:
  // 노쇼 취소 대상은 status == 'NO_SHOW'인 인원만이며, 1인당 1 op.
  // 현실적 규모(하루 수백 명)로 단일 batch 범위 내이다.
  Future<void> _showBatchCancelNoShowDialog(List<ApplicationModel> targets) async {
    if (_isLoading) return; // 중복 실행 방어
    final names = targets.map((a) => _getDisplayName(a.uid)).join(', ');
    final confirmed = await DialogHelper.showConfirm(
      context,
      title: '노쇼 취소',
      message: '${targets.length}명의 노쇼를 취소합니다.\n\n$names',
      confirmText: '취소 확인',
    );
    if (!confirmed || !mounted) return;

    final batch = FirebaseFirestore.instance.batch();
    final now = FieldValue.serverTimestamp();
    for (final app in targets) {
      final att = _attendanceMap[app.id];
      if (att == null) continue;
      // status 필드를 명시적으로 삭제한다.
      // AttendanceModel.fromMap()에서 status가 없으면 'absent'로 폴백하는데,
      // 이는 의도된 동작: 노쇼 취소 후 지원자가 실제로 출근했는지 여부는
      // checkIn/checkOut 필드로 별도 판단하며, status 필드는 NO_SHOW 표시 용도로만 사용.
      // 노쇼 취소 시 wageStatus·finalWage도 함께 초기화: noshow 판정 시
      // 설정됐을 수 있는 확정값을 지워 임금 재계산 흐름이 정상 작동하도록 함
      batch.update(
        FirebaseFirestore.instance.collection('attendance').doc(att.id),
        {
          'status': FieldValue.delete(),
          'wageStatus': AttendanceModel.wagePending,
          'finalWage': FieldValue.delete(),
          'updatedAt': now,
        },
      );
    }
    try {
      await batch.commit();
      // TrustScore noShowCount/trustScore는 onAttendanceWageStatusChanged CF 트리거에서 서버 자동 처리
      if (!mounted) return;
      setState(() {
        for (final app in targets) {
          final att = _attendanceMap[app.id];
          if (att != null) _attendanceMap[app.id] = att.copyWith(status: null);
        }
        _selectedIds.clear();
        _hasChanges = true;
        _rebuildStatusCache();
      });
      ToastHelper.showSuccess('노쇼 취소 완료 (${targets.length}명)');
    } catch (e) {
      debugPrint('❌ 노쇼 취소 실패: $e');
      if (!mounted) return;
      ToastHelper.showError('노쇼 취소 실패');
    }
  }

  // ─── 배치 리셋 ───────────────────────────────────────────────

  // [F-34/A05 설계 검토] 리셋 배치 WriteBatch 500 ops 제한:
  // 당일 단일 사업장 전체 인원 대상이며, 리셋은 출근 기록이 있는 인원(checkIn != null)
  // 또는 결근(statusAbsent) 처리된 인원을 대상으로 한다. 일반 아르바이트 사업장
  // 최대 규모 기준 하루 수백 명 수준으로 단일 batch(500 ops) 내에서 충분히 처리 가능하다.
  Future<void> _showBatchResetDialog() async {
    final targets = _selectedIds
        .map((id) => _workerIdMap[id])
        .whereType<ApplicationModel>()
        .where((app) {
          final att = _attendanceMap[app.id];
          if (att == null) return false;
          // H-3: statusAbsent(결근)도 리셋 대상에 포함 — checkIn이 없어도 처리
          return att.checkIn != null ||
              att.status == AttendanceModel.statusAbsent;
        })
        .toList();
    if (targets.isEmpty) return;

    // [HIGH-04] 급여 1차확정(calculated) · 마감(confirmed) · 이체 완료(transferred) 건은 리셋 제외
    // calculated는 관리자가 계산 검토 중인 상태 — 리셋 시 급여 계산 결과 소실됨
    final wageFinalized = targets.where((app) {
      final s = _attendanceMap[app.id]?.wageStatus;
      return s == AttendanceModel.wageCalculated ||
          s == AttendanceModel.wageConfirmed ||
          s == AttendanceModel.wageTransferred;
    }).toList();

    final resetTargets = targets
        .where((app) => !wageFinalized.contains(app))
        .toList();

    if (resetTargets.isEmpty) {
      ToastHelper.showWarning('선택한 인원 모두 급여가 계산됐거나 확정/이체 완료 상태라 리셋할 수 없습니다.');
      return;
    }

    final skipMsg = wageFinalized.isNotEmpty
        ? '\n\n⚠️ 급여 확정·이체 완료 ${wageFinalized.length}명은 제외됩니다.'
        : '';
    final names = resetTargets.map((a) => _getDisplayName(a.uid)).join(', ');
    final confirmed = await DialogHelper.showDangerConfirm(
      context,
      title: '출퇴근 기록 리셋',
      message: '${resetTargets.length}명의 출퇴근 기록을 초기화합니다.\n'
          '출근·퇴근 시간, 급여 계산 결과가 모두 삭제됩니다.$skipMsg\n\n$names',
      confirmText: '리셋',
    );
    if (!confirmed || !mounted) return;

    final batch = FirebaseFirestore.instance.batch();
    final now = FieldValue.serverTimestamp();
    for (final app in resetTargets) {
      final att = _attendanceMap[app.id];
      if (att == null) continue;
      // H-4: wageStatus·wageDetail·workHours·yearMonth도 함께 초기화
      batch.update(
        FirebaseFirestore.instance.collection('attendance').doc(att.id),
        {
          'checkIn': FieldValue.delete(),
          'checkOut': FieldValue.delete(),
          'status': FieldValue.delete(),
          'workHours': FieldValue.delete(),
          'wageStatus': FieldValue.delete(),
          'wageDetail': FieldValue.delete(),
          'yearMonth': FieldValue.delete(),
          'updatedAt': now,
        },
      );
    }
    try {
      await batch.commit();
      if (!mounted) return;
      setState(() {
        // copyWith가 null 전달 시 기존 값 유지 구조이므로,
        // 리셋된 레코드는 맵에서 제거해 "미출근" 상태로 표시
        for (final app in resetTargets) {
          _attendanceMap.remove(app.id);
        }
        _selectedIds.clear();
        _hasChanges = true;
        _rebuildStatusCache();
      });
      ToastHelper.showSuccess('리셋 완료 (${resetTargets.length}명)');
    } catch (e) {
      debugPrint('❌ 리셋 실패: $e');
      if (!mounted) return;
      ToastHelper.showError('리셋 실패');
    }
  }

  /// 개별 선택/해제
  void _toggleSelection(String appId) {
    setState(() {
      if (_selectedIds.contains(appId)) {
        _selectedIds.remove(appId);
        _selectAll = false;
      } else {
        _selectedIds.add(appId);
        // selectableCount는 _confirmedWorkers 전체가 아닌 현재 탭 기준으로 산정.
        //           _toggleSelectAll()과 동일한 기준을 써야 _selectAll 동기화가 정확함.
        final tabWorkers = _workersByTab(_currentTabIndex);
        final selectableCount = tabWorkers.where((app) {
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
        .map((id) => _workerIdMap[id])
        .whereType<ApplicationModel>()
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
            constraints: const BoxConstraints(maxWidth: 340),
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
    if (_isLoading) return;
    try {
      int successCount = 0;
      int failCount = 0;

      for (final app in targets) {
        final attendance = _attendanceMap[app.id];
        if (attendance == null) continue;

        // [HIGH-01] 급여 마감(confirmed)·이체완료(transferred) 건 스킵
        // confirmed 상태에서 시간 수정을 허용하면 확정된 급여와 실제 근태가 불일치함
        if (attendance.wageStatus == AttendanceModel.wageConfirmed ||
            attendance.wageStatus == AttendanceModel.wageTransferred) {
          failCount++;
          continue;
        }

        try {
          final effectiveCheckIn  = newCheckIn  ?? attendance.checkIn  ?? WorkDetailHelper.effectiveStart(app, _workDetailTimeMap);
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

          // [B02-FIX] 시간 수정 시 1차 확정(calculated) 상태이면 미계산(pending)으로 리셋.
          // 트랜잭션으로 서버 측 wageStatus를 재확인하여 동시에 다른 관리자가
          // wageConfirmed/wageTransferred로 전환한 경우 pending 덮어쓰기를 방지한다.
          if (attendance.wageStatus == AttendanceModel.wageCalculated) {
            updates['wageStatus'] = AttendanceModel.wagePending;
            updates['wageDetail'] = FieldValue.delete();
            updates['yearMonth'] = FieldValue.delete();
            final attRef = FirebaseFirestore.instance
                .collection('attendance')
                .doc(attendance.id);
            await FirebaseFirestore.instance.runTransaction((tx) async {
              final snap = await tx.get(attRef);
              final serverStatus = snap.data()?['wageStatus'] as String?;
              // 이미 마감(wageConfirmed) 또는 송금완료(wageTransferred)이면 리셋 불가
              if (serverStatus == AttendanceModel.wageConfirmed ||
                  serverStatus == AttendanceModel.wageTransferred) {
                throw Exception('이미 마감된 급여입니다. 시간 수정 전 마감을 취소해주세요.');
              }
              tx.update(attRef, updates);
            });
          } else {
            await FirebaseFirestore.instance
                .collection('attendance')
                .doc(attendance.id)
                .update(updates);
          }

          // [LATE-CANCEL] 출근 시간 수정 시 지각 상태 변동 → 신뢰도 연동
          if (newCheckIn != null) {
            final expectedStartTime = WorkDetailHelper.effectiveStart(app, _workDetailTimeMap);
            final oldCheckIn = attendance.checkIn;
            final wasLate = oldCheckIn != null &&
                AttendanceStatusHelper.isLate(oldCheckIn, expectedStartTime);
            final isNowLate = AttendanceStatusHelper.isLate(newCheckIn, expectedStartTime);
            final lateCallable = FirebaseFunctions.instanceFor(region: 'asia-northeast3')
                .httpsCallable('callableReportLate');
            if (wasLate && !isNowLate) {
              await lateCallable.call({
                'userId': app.uid, 'businessId': app.businessId, 'mode': 'late_canceled',
              });
            } else if (!wasLate && isNowLate) {
              await lateCallable.call({
                'userId': app.uid, 'businessId': app.businessId, 'mode': 'late',
              });
            }
          }

          successCount++;
        } catch (e) {
          debugPrint('❌ 출결 시간 일괄 조정 실패 (${attendance.id}): $e');
          failCount++;
        }
      }

      if (!mounted) return;
      if (successCount > 0) ToastHelper.showSuccess('$successCount명 시간 조정 완료');
      if (failCount > 0) ToastHelper.showWarning('$failCount명 처리 실패');

      _hasChanges = true;
      await _loadData();
    } catch (e) {
      debugPrint('❌ 일괄 시간 조정 실패: $e');
      if (!mounted) return;
      ToastHelper.showError('일괄 시간 조정 실패');
    }
  }

  /// 일괄 출근 다이얼로그
  Future<void> _showBatchCheckInDialog() async {
    if (_selectedIds.isEmpty) return;

    // 파트별 그룹화
    final Map<String, List<ApplicationModel>> groups = {};
    for (final id in _selectedIds) {
      final app = _workerIdMap[id];
      if (app == null) continue;
      final key = '${app.selectedWorkType}_${app.startTime}_${app.endTime}';
      groups.putIfAbsent(key, () => []).add(app);
    }

    if (groups.length <= 1) {
      // 단일 파트 → 기존 시트
      final scheduledTimes = _selectedIds
          .map((id) {
            final app = _workerIdMap[id];
            if (app == null) return '';
            return WorkDetailHelper.effectiveStart(app, _workDetailTimeMap);
          })
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
      final app = _workerIdMap[id];
      if (app == null) return false;
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
      final app = _workerIdMap[id];
      if (app == null) continue;
      final key = '${app.selectedWorkType}_${app.startTime}_${app.endTime}';
      groups.putIfAbsent(key, () => []).add(app);
    }

    if (groups.length <= 1) {
      // 단일 파트 → 기존 시트
      final scheduledTimes = checkedInIds
          .map((id) {
            final app = _workerIdMap[id];
            if (app == null) return '';
            return WorkDetailHelper.effectiveEnd(app, _workDetailTimeMap);
          })
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
      final effT = isCheckIn
          ? WorkDetailHelper.effectiveStart(firstApp, _workDetailTimeMap)
          : WorkDetailHelper.effectiveEnd(firstApp, _workDetailTimeMap);
      selectedTimes[entry.key] = effT.isNotEmpty ? effT : nowStr;
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
                maxHeight: MediaQuery.of(ctx).size.height * AppDialogSize.subSheetHeightRatio,
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
                            // groups는 putIfAbsent(...).add() 로 생성 — 각 value 최소 1개 보장, .first 안전
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
                                            scheduledTimes: (() {
                                              final t = isCheckIn
                                                  ? WorkDetailHelper.effectiveStart(firstApp, _workDetailTimeMap)
                                                  : WorkDetailHelper.effectiveEnd(firstApp, _workDetailTimeMap);
                                              return t.isNotEmpty ? [t] : null;
                                            })(),
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


  // ═══════════════════════════════════════════════════════════
  // 출퇴근 처리 로직
  // ═══════════════════════════════════════════════════════════

  /// 근무 시간 계산 (HH:mm(:ss) → 시간 단위 double)
  double _calcWorkHoursCompat(String checkIn, String checkOut) =>
      AttendanceStatusHelper.workMinutes(checkIn, checkOut) / 60.0;

  /// 출근/퇴근 시간으로 DB status 결정 — effectiveStart/End 우선 적용
  String _deriveStatus(ApplicationModel app, String checkIn, String? checkOut) =>
      AttendanceStatusHelper.deriveStatus(
        app, checkIn, checkOut,
        effStart: WorkDetailHelper.effectiveStart(app, _workDetailTimeMap),
        effEnd:   WorkDetailHelper.effectiveEnd(app, _workDetailTimeMap),
      );

  /// 일괄 출근 처리
  Future<void> _processBatchCheckIn(String time) async {
    if (_isLoading) return;
    setState(() => _isLoading = true);
    try {
      int successCount = 0;
      int failCount = 0;

      for (var appId in _selectedIds) {
        // 실시간 리스너가 목록을 갱신한 경우 해당 항목이 사라질 수 있음 — 스킵
        final idx = _confirmedWorkers.indexWhere((a) => a.id == appId);
        if (idx == -1) continue;
        final app = _confirmedWorkers[idx];
        final status = _getAttendanceStatus(app);

        // 이미 출근했거나 노쇼면 스킵
        if (status['status'] != 'pending') continue;

        try {
          await _createOrUpdateAttendance(
            app: app,
            checkIn: time,
          );

          // 지각 여부 체크 및 신뢰도 반영 — CF callableReportLate 서버 처리
          final expectedStartTime = WorkDetailHelper.effectiveStart(app, _workDetailTimeMap);
          if (AttendanceStatusHelper.isLate(time, expectedStartTime)) {
            await FirebaseFunctions.instanceFor(region: 'asia-northeast3')
                .httpsCallable('callableReportLate')
                .call({'userId': app.uid, 'businessId': app.businessId, 'mode': 'late'});
          }

          successCount++;
        } catch (e) {
          failCount++;
        }
      }

      if (!mounted) return;
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
      if (!mounted) return;
      ToastHelper.showError('일괄 출근 처리 실패');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// 일괄 퇴근 처리
  Future<void> _processBatchCheckOut(String time, List<String> targetIds) async {
    if (_isLoading) return;
    setState(() => _isLoading = true);
    try {
      int successCount = 0;
      int failCount = 0;

      for (var appId in targetIds) {
        // 실시간 리스너가 목록을 갱신한 경우 해당 항목이 사라질 수 있음 — 스킵
        final idx = _confirmedWorkers.indexWhere((a) => a.id == appId);
        if (idx == -1) continue;
        final app = _confirmedWorkers[idx];
        final attendance = _attendanceMap[app.id];
        if (attendance == null) continue;

        // [HIGH-01] 급여 마감(confirmed)·이체완료(transferred) 건 스킵 (일괄 퇴근 처리 동일 정책)
        if (attendance.wageStatus == AttendanceModel.wageConfirmed ||
            attendance.wageStatus == AttendanceModel.wageTransferred) {
          failCount++;
          continue;
        }

        try {
          final checkIn = attendance.checkIn ?? WorkDetailHelper.effectiveStart(app, _workDetailTimeMap);

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

      if (!mounted) return;
      if (successCount > 0) {
        ToastHelper.showSuccess('$successCount명 퇴근 처리 완료');
        _hasChanges = true;
      }
      if (failCount > 0) ToastHelper.showWarning('$failCount명 처리 실패');

      await _loadData();
    } catch (e) {
      debugPrint('❌ 일괄 퇴근 처리 실패: $e');
      if (!mounted) return;
      ToastHelper.showError('일괄 퇴근 처리 실패');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// 파트별 일괄 출근 처리
  Future<void> _processBatchCheckInByGroup(Map<String, String> groupTimes) async {
    if (_isLoading) return; // [BUG-01] 중복 실행 방어
    setState(() => _isLoading = true);
    try {
      int successCount = 0;
      int failCount = 0;

      for (final appId in _selectedIds) {
        // 실시간 리스너가 목록을 갱신한 경우 해당 항목이 사라질 수 있음 — 스킵
        final idx = _confirmedWorkers.indexWhere((a) => a.id == appId);
        if (idx == -1) continue;
        final app = _confirmedWorkers[idx];
        final groupKey = '${app.selectedWorkType}_${app.startTime}_${app.endTime}';
        final time = groupTimes[groupKey];
        if (time == null) continue;

        final status = _getAttendanceStatus(app);
        if (status['status'] != 'pending') continue;

        try {
          await _createOrUpdateAttendance(app: app, checkIn: time);
          final expectedStartTime = WorkDetailHelper.effectiveStart(app, _workDetailTimeMap);
          if (AttendanceStatusHelper.isLate(time, expectedStartTime)) {
            await FirebaseFunctions.instanceFor(region: 'asia-northeast3')
                .httpsCallable('callableReportLate')
                .call({'userId': app.uid, 'businessId': app.businessId, 'mode': 'late'});
          }
          successCount++;
        } catch (e) {
          failCount++;
        }
      }

      if (!mounted) return;
      if (successCount > 0) ToastHelper.showSuccess('$successCount명 출근 처리 완료');
      if (failCount > 0) ToastHelper.showWarning('$failCount명 처리 실패');

      _hasChanges = true;
      await _loadData();
    } catch (e) {
      debugPrint('❌ 파트별 일괄 출근 처리 실패: $e');
      if (mounted) ToastHelper.showError('일괄 출근 처리 실패');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// 파트별 일괄 퇴근 처리
  Future<void> _processBatchCheckOutByGroup(
      Map<String, String> groupTimes, List<String> targetIds) async {
    if (_isLoading) return; // [BUG-01] 중복 실행 방어
    setState(() => _isLoading = true);
    try {
      int successCount = 0;
      // [W-3] 실패 이유를 이름과 함께 수집 — 단순 failCount만 표시하면 관리자가 원인 파악 불가
      // 시간 역전과 16시간 초과(야간 장시간 근무 업종)를 구분하여 개별 안내
      final List<String> failMessages = [];

      for (final appId in targetIds) {
        // 실시간 리스너가 목록을 갱신한 경우 해당 항목이 사라질 수 있음 — 스킵
        final idx = _confirmedWorkers.indexWhere((a) => a.id == appId);
        if (idx == -1) continue;
        final app = _confirmedWorkers[idx];
        final groupKey = '${app.selectedWorkType}_${app.startTime}_${app.endTime}';
        final time = groupTimes[groupKey];
        if (time == null) continue;

        final attendance = _attendanceMap[app.id];
        if (attendance == null) continue;

        try {
          final checkIn = attendance.checkIn ?? WorkDetailHelper.effectiveStart(app, _workDetailTimeMap);
          final workerName = _userMap[app.uid]?.name ?? '근무자';

          // [W-3] 실패 이유 구분 — workMinutes로 직접 계산하여 시간 역전 vs 16시간 초과 구별
          final minutes = AttendanceStatusHelper.workMinutes(checkIn, time);
          if (minutes <= 0) {
            failMessages.add('$workerName: 퇴근 시간이 출근 시간보다 앞서 있습니다');
            continue;
          }
          if (minutes > 16 * 60) {
            failMessages.add('$workerName: 16시간 초과 (${minutes ~/ 60}시간 ${minutes % 60}분)');
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
          final workerName = _userMap[app.uid]?.name ?? '근무자';
          failMessages.add('$workerName: 처리 오류');
        }
      }

      if (!mounted) return;
      if (successCount > 0) {
        ToastHelper.showSuccess('$successCount명 퇴근 처리 완료');
        _hasChanges = true;
      }
      if (failMessages.isNotEmpty) {
        ToastHelper.showWarning('${failMessages.length}명 처리 실패\n${failMessages.join('\n')}');
      }

      await _loadData();
    } catch (e) {
      debugPrint('❌ 파트별 일괄 퇴근 처리 실패: $e');
      if (mounted) ToastHelper.showError('일괄 퇴근 처리 실패');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }






  /// Attendance 생성 또는 업데이트 (출근 처리)
  ///
  /// [D01-FIX] 두 관리자가 동시에 같은 근무자를 수동 출근 처리할 때
  /// collection.add() 는 랜덤 ID를 생성하므로 두 개의 attendance 도큐먼트가 만들어진다.
  /// attendance_firestore.dart의 정규 체크인 경로와 동일하게
  /// '{applicationId}_{yyyyMMdd}' 결정적 ID + set(SetOptions(merge: true)) 로 변경한다.
  /// merge: true 이면 제공된 필드를 upsert하고 명시하지 않은 필드는 보존한다.
  /// 동시 실행 시 마지막 write 가 우선(last-write-wins)이므로 중복 문서는 없으나
  /// 두 관리자가 다른 시간을 입력한 경우 하나는 유실된다 (허용된 트레이드오프).
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
      // 결정적 docId — attendance_firestore.dart checkIn() 와 동일 패턴
      final dateStr = '${widget.date.year}'
          '${widget.date.month.toString().padLeft(2, '0')}'
          '${widget.date.day.toString().padLeft(2, '0')}';
      final docId = '${app.id}_$dateStr';
      await FirebaseFirestore.instance
          .collection('attendance')
          .doc(docId)
          .set({
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
      }, SetOptions(merge: true));
    }
  }

  // ═══════════════════════════════════════════════════════════
  // 노쇼 처리
  // ═══════════════════════════════════════════════════════════





  /// 일괄 마감 취소 (선택된 최종확정 근무자 전체)
  // [설계] WriteBatch 500 ops 제한 검토:
  // 1인당 attendance + users 2 ops → 249명까지 단일 batch로 처리 가능.
  // 마감 취소는 선택된 wageConfirmed 근무자 대상으로 관리자가 수동 선택 후 실행하므로
  // 한 번에 수백 명을 선택하는 경우는 현실적으로 없다.
  Future<void> _batchCancelFinal() async {
    if (_isLoading) return;
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
    if (!confirmed || !mounted) return;

    // 1단계: attendance + users를 batch로 원자 업데이트
    final batch = FirebaseFirestore.instance.batch();
    final now = FieldValue.serverTimestamp();
    final processed = <({ApplicationModel app, AttendanceModel attendance})>[];

    for (final app in targets) {
      final attendance = _attendanceMap[app.id];
      if (attendance == null) continue;
      final wageDetail = attendance.wageDetail?.copyWith(
        confirmedBy: null,
        confirmedAt: null,
      );
      batch.update(
        FirebaseFirestore.instance.collection('attendance').doc(attendance.id),
        {
          'wageStatus': AttendanceModel.wageCalculated,
          'wageDetail': wageDetail?.toMap(),
          'finalConfirmedAt': FieldValue.delete(),
          'updatedAt': now,
        },
      );
      processed.add((app: app, attendance: attendance));
    }

    try {
      await batch.commit();
    } catch (e) {
      debugPrint('❌ 마감 취소 batch 실패: $e');
      if (!mounted) return;
      ToastHelper.showError('마감취소에 실패했습니다');
      return;
    }

    // 2단계: 알림 (TrustScore는 onAttendanceWageStatusChanged CF 트리거에서 서버 자동 처리)
    for (final p in processed) {
      if (!mounted) break;
      try {
        final businessName = _businessNameMap[p.app.businessId] ?? '';
        await _firestoreService.createNotification(
          NotificationModel.createWageCancelConfirmed(
            userId: p.app.uid,
            businessName: businessName,
            businessId: p.app.businessId,
            workDate: p.app.workDate,
            attendanceId: p.attendance.id,
          ),
        );
      } catch (e) {
        debugPrint('⚠️ 알림 발송 실패 (${p.app.uid}): $e');
      }
    }

    if (!mounted) return;
    _hasChanges = true;
    ToastHelper.showSuccess('${processed.length}명 마감취소 완료');
    await _loadData();
  }


}

/// 컴팩트 통계 칩 데이터 클래스 (내부용)
class _StatChip {
  final String label;
  final int count;
  final Color color;
  const _StatChip(this.label, this.count, this.color);
}
