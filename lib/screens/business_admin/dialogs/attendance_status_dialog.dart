// lib/screens/business_admin/dialogs/attendance_status_dialog.dart
// 인원현황 다이얼로그 - 출퇴근 관리 기능 포함
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

// Models
import '../../../models/core/application_model.dart';
import '../../../models/core/attendance_model.dart';
import '../../../models/core/user_model.dart';
import '../../../models/core/business_work_type_model.dart';

// Utils
import '../../../utils/toast_helper.dart';
import '../../../utils/responsive_helper.dart';
import '../../../utils/dialog_helper.dart';
import '../../../utils/format_helper.dart';
import '../../../theme/app_colors.dart';

// Widgets
import '../../../widgets/common/loading_widget.dart';
import '../../../widgets/dialogs/worker_detail_dialog.dart';
import '../../../widgets/work_type_icon.dart';
import '../../../widgets/pickers/time_picker_bottom_sheet.dart';

// PDF
import '../../../utils/attendance_list_pdf.dart';
// Dialogs
import 'fixed_worker_management_dialog.dart';

/// 인원현황 다이얼로그 - 출퇴근 관리 기능 포함
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
  
  // 데이터
  List<ApplicationModel> _confirmedWorkers = [];
  Map<String, AttendanceModel> _attendanceMap = {};
  Map<String, UserModel> _userMap = {};
  Map<String, String> _businessNameMap = {};
  Map<String, BusinessWorkTypeModel> _workTypeMap = {};  // 업무유형 정보
  Map<String, dynamic> _workDetailTimeMap = {};  // 업무별 근무시간 (WorkDetail)
  
  // UI 상태
  bool _isLoading = true;
  bool _isProcessing = false;
  String? _selectedBusinessId;
  
  // 선택 상태
  final Set<String> _selectedIds = {};
  bool _selectAll = false;

  @override
  void initState() {
    super.initState();
    _selectedBusinessId = widget.initialBusinessId ?? widget.businessIds.first;
    _loadBusinessNames();
    _loadData();
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

      setState(() {
        _businessNameMap = nameMap;
      });
    } catch (e) {
      print('❌ 사업장명 조회 실패: $e');
    }
  }

  /// 전체 데이터 로드
  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _selectedIds.clear();
      _selectAll = false;
    });

    try {
      // 1. 확정 근무자 조회
      final confirmedWorkers = await _getConfirmedWorkersForDate();

      // 2. 출근 기록 조회
      final attendanceMap = await _getAttendanceRecords(
        confirmedWorkers.map((app) => app.id).toList(),
      );

      // 3. 사용자 정보 조회
      final uids = confirmedWorkers.map((app) => app.uid).toSet().toList();
      final userMap = await _getUserInfoBatch(uids);
      
      // 4. 업무유형 정보 조회
      final workTypeMap = await _getWorkTypeInfo();
      
      // 5. WorkDetail 시간 정보 조회
      final workDetailTimeMap = await _getWorkDetailTimes();

      setState(() {
        _confirmedWorkers = confirmedWorkers;
        _attendanceMap = attendanceMap;
        _userMap = userMap;
        _workTypeMap = workTypeMap;
        _workDetailTimeMap = workDetailTimeMap;
        _isLoading = false;
      });
    } catch (e) {
      print('❌ 인원현황 데이터 로드 실패: $e');
      setState(() => _isLoading = false);
      ToastHelper.showError('데이터 로드 실패');
    }
  }

  /// 확정 근무자 조회 (해당 날짜)
  Future<List<ApplicationModel>> _getConfirmedWorkersForDate() async {
    final dateStart = DateTime(widget.date.year, widget.date.month, widget.date.day);

    final snapshot = await FirebaseFirestore.instance
        .collection('applications')
        .where('businessId', isEqualTo: _selectedBusinessId)
        .where('status', isEqualTo: 'CONFIRMED')
        .get();

    final allConfirmed = snapshot.docs
        .map((doc) => ApplicationModel.fromFirestore(doc))
        .toList();

    // 단기 + 장기 필터링
    final result = allConfirmed.where((app) {
      // 단기 근무
      if (!app.isLongTermApplication) {
        return DateUtils.isSameDay(app.workDate, dateStart);
      }

      // 장기 근무
      if (app.workEndDate == null) return false;

      // 기간 체크
      final isInRange = !dateStart.isBefore(app.workDate) &&
          !dateStart.isAfter(app.workEndDate!);

      if (!isInRange) return false;

      // 요일 체크
      if (app.workDays == null || app.workDays!.isEmpty) {
        return true; // 매일 근무
      }

      final weekdays = ['월', '화', '수', '목', '금', '토', '일'];
      final dayWeekday = weekdays[widget.date.weekday - 1];
      return app.workDays!.contains(dayWeekday);
    }).toList();

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
      print('업무유형 조회 실패: $e');
    }

    return workTypeMap;
  }

  // ═══════════════════════════════════════════════════════════
  // 유틸리티 메서드
  // ═══════════════════════════════════════════════════════════

  /// 사용자 정보 가져오기
  UserModel? _getUser(String uid) {
    return _userMap[uid];
  }

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

  /// 출퇴근 상태 판단
  Map<String, dynamic> _getAttendanceStatus(ApplicationModel app) {
    final attendance = _attendanceMap[app.id];
    final expectedStartTime = app.startTime.isNotEmpty ? app.startTime : '09:00';

    // 노쇼 체크
    if (attendance?.status == 'NO_SHOW') {
      return {
        'status': 'noshow',
        'color': AppColors.error,
        'icon': Icons.cancel,
        'text': '노쇼',
        'timeText': null,
      };
    }

    // 퇴근 완료
    if (attendance?.checkOut != null) {
      return {
        'status': 'checkout',
        'color': Colors.purple,
        'icon': Icons.home,
        'text': '퇴근',
        'timeText': '${attendance!.checkIn} ~ ${attendance.checkOut}',
      };
    }

    // 출근 완료
    if (attendance?.checkIn != null) {
      // 지각 체크
      debugPrint('🔍 지각 체크: checkIn=${attendance!.checkIn}, expected=$expectedStartTime');
      final isLate = _isLate(attendance.checkIn!, expectedStartTime);
      debugPrint('🔍 결과: isLate=$isLate');
      if (isLate) {
        return {
          'status': 'late',
          'color': AppColors.warning,
          'icon': Icons.warning_amber,
          'text': '지각',
          'timeText': attendance.checkIn,
        };
      }
      return {
        'status': 'checkin',
        'color': AppColors.success,
        'icon': Icons.check_circle,
        'text': '출근',
        'timeText': attendance.checkIn,
      };
    }

    // 미출근
    return {
      'status': 'pending',
      'color': AppColors.grey500,
      'icon': Icons.schedule,
      'text': '미출근',
      'timeText': null,
    };
  }

  /// 지각 여부 판단 (1분 이상 늦으면 지각)
  bool _isLate(String checkInTime, String expectedTime) {
    try {
      final checkIn = _parseTime(checkInTime);
      final expected = _parseTime(expectedTime);
      // 1분 이상 늦으면 지각 (동일 시간은 지각 아님)
      return checkIn.difference(expected).inMinutes > 0;
    } catch (e) {
      debugPrint('⚠️ 지각 판단 오류: checkIn=$checkInTime, expected=$expectedTime, error=$e');
      return false;
    }
  }

  /// 시간 문자열 파싱
  DateTime _parseTime(String timeStr) {
    final parts = timeStr.split(':');
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day, int.parse(parts[0]), int.parse(parts[1]));
  }

  /// 통계 계산
  Map<String, int> _calculateStats() {
    int total = _confirmedWorkers.length;
    int checkedIn = 0;
    int checkedOut = 0;
    int late = 0;
    int noShow = 0;

    for (var app in _confirmedWorkers) {
      final status = _getAttendanceStatus(app);
      switch (status['status']) {
        case 'checkout':
          checkedIn++;
          checkedOut++;
          break;
        case 'checkin':
          checkedIn++;
          break;
        case 'late':
          checkedIn++;
          late++;
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

    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
      ),
      child: Container(
        width: MediaQuery.of(context).size.width * 0.95,
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.9,
        ),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
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
                  ? const LoadingWidget(message: '인원현황 조회 중...')
                  : _confirmedWorkers.isEmpty
                      ? _buildEmptyState()
                      : _buildContent(theme),
            ),

            // 하단 버튼
            _buildBottomBar(theme),
          ],
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
            theme.primaryColor.withOpacity(0.85),
          ],
        ),
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(24),
          topRight: Radius.circular(24),
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
                  Icons.people_alt,
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
                      '인원현황',
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
                color: Colors.white.withOpacity(0.2),
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

          // 사업장 드롭다운
          Container(
            padding: EdgeInsets.symmetric(
              horizontal: ResponsiveHelper.spacing(context, 16),
              vertical: ResponsiveHelper.spacing(context, 4),
            ),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _selectedBusinessId,
                isExpanded: true,
                icon: Icon(Icons.keyboard_arrow_down, color: theme.primaryColor),
                style: ResponsiveHelper.bodyStyle(context).copyWith(
                  color: Colors.black87,
                  fontWeight: FontWeight.w500,
                ),
                items: widget.businessIds.map((id) {
                  return DropdownMenuItem(
                    value: id,
                    child: Row(
                      children: [
                        Icon(
                          Icons.business,
                          size: ResponsiveHelper.iconSize(context, 18),
                          color: theme.primaryColor,
                        ),
                        SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                        Expanded(
                          child: Text(
                            _businessNameMap[id] ?? id,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
                onChanged: (value) {
                  if (value != null && value != _selectedBusinessId) {
                    setState(() {
                      _selectedBusinessId = value;
                    });
                    _loadData();
                  }
                },
              ),
            ),
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
            theme.primaryColor.withOpacity(0.08),
            theme.primaryColor.withOpacity(0.04),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: theme.primaryColor.withOpacity(0.2),
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
                  color: theme.primaryColor.withOpacity(0.15),
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
              Expanded(child: _buildStatItem('확정', '${stats['total']}명', Icons.people_outline, Colors.blue)),
              Expanded(child: _buildStatItem('출근', '${stats['checkedIn']}명', Icons.login, Colors.green)),
              Expanded(child: _buildStatItem('미출근', '${stats['notCheckedIn']}명', Icons.schedule, Colors.orange)),
              Expanded(child: _buildStatItem('노쇼', '${stats['noShow']}명', Icons.cancel, Colors.red)),
            ],
          ),

          // 추가 정보 (지각, 퇴근)
          if (stats['late']! > 0 || stats['checkedOut']! > 0) ...[
            SizedBox(height: ResponsiveHelper.spacing(context, 12)),
            Divider(color: theme.dividerColor),
            SizedBox(height: ResponsiveHelper.spacing(context, 12)),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (stats['late']! > 0) ...[
                  _buildMiniStat('지각', stats['late']!, AppColors.warning),
                  SizedBox(width: ResponsiveHelper.spacing(context, 24)),
                ],
                _buildMiniStat('퇴근완료', stats['checkedOut']!, Colors.purple),
              ],
            ),
          ],
        ],
      ),
    );
  }

  /// 통계 아이템
  Widget _buildStatItem(String label, String value, IconData icon, MaterialColor color) {
    return Column(
      children: [
        Container(
          padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 10)),
          decoration: BoxDecoration(
            color: color[50],
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color[200]!, width: 1),
          ),
          child: Icon(
            icon,
            color: color[600],
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
            color: color[700],
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
    final hasSelection = _selectedIds.isNotEmpty;
    
    return Container(
      padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 12)),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          // 상단: 전체 선택 + 일괄 버튼
          Row(
            children: [
              // 전체 선택 체크박스
              SizedBox(
                width: 22,
                height: 22,
                child: Checkbox(
                  value: _selectAll,
                  onChanged: (value) => _toggleSelectAll(value ?? false),
                  activeColor: theme.primaryColor,
                ),
              ),
              SizedBox(width: ResponsiveHelper.spacing(context, 8)),
              Text(
                '전체 선택',
                style: ResponsiveHelper.bodyStyle(context),
              ),

              // 선택 수 표시
              if (_selectedIds.isNotEmpty) ...[
                SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: ResponsiveHelper.spacing(context, 8),
                    vertical: ResponsiveHelper.spacing(context, 2),
                  ),
                  decoration: BoxDecoration(
                    color: theme.primaryColor,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${_selectedIds.length}명',
                    style: ResponsiveHelper.tinyStyle(context, color: Colors.white),
                  ),
                ),
              ],

              const Spacer(),

              // 일괄 출근 버튼
              _buildActionButton(
                icon: Icons.login,
                label: '출근',
                color: AppColors.success,
                onPressed: hasSelection ? () => _showBatchCheckInDialog() : null,
              ),

              SizedBox(width: ResponsiveHelper.spacing(context, 8)),

              // 일괄 퇴근 버튼
              _buildActionButton(
                icon: Icons.logout,
                label: '퇴근',
                color: Colors.purple,
                onPressed: hasSelection ? () => _showBatchCheckOutDialog() : null,
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
    VoidCallback? onPressed,
  }) {
    final isEnabled = onPressed != null;

    return Material(
      color: isEnabled ? color.withOpacity(0.1) : Colors.grey[200],
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: ResponsiveHelper.spacing(context, 12),
            vertical: ResponsiveHelper.spacing(context, 8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: ResponsiveHelper.iconSize(context, 16),
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
        ),
      ),
    );
  }

  /// 업무별 그룹
  Widget _buildWorkTypeGroups(ThemeData theme) {
    // 업무 유형별로 그룹화
    final Map<String, List<ApplicationModel>> workTypeGroups = {};

    for (var app in _confirmedWorkers) {
      final workType = app.selectedWorkType;
      workTypeGroups.putIfAbsent(workType, () => []);
      workTypeGroups[workType]!.add(app);
    }

    // 각 그룹 내 정렬 (장단기 → 성별 → 나이순)
    for (var workers in workTypeGroups.values) {
      workers.sort((a, b) {
        // 1. 장단기 정렬 (장기 먼저)
        final isLongA = a.isLongTermApplication ? 0 : 1;
        final isLongB = b.isLongTermApplication ? 0 : 1;
        
        if (isLongA != isLongB) {
          return isLongA.compareTo(isLongB);
        }

        final userA = _userMap[a.uid];
        final userB = _userMap[b.uid];

        if (userA == null || userB == null) return 0;

        // 2. 성별 정렬 (남성 먼저)
        final genderOrder = {'남성': 0, '여성': 1};
        final genderA = genderOrder[userA.gender] ?? 2;
        final genderB = genderOrder[userB.gender] ?? 2;

        if (genderA != genderB) {
          return genderA.compareTo(genderB);
        }

        // 3. 나이순 정렬 (어린순)
        final ageA = userA.age ?? 999;
        final ageB = userB.age ?? 999;
        return ageA.compareTo(ageB);
      });
    }

    return Column(
      children: workTypeGroups.entries.map((entry) {
        return Padding(
          padding: EdgeInsets.only(bottom: ResponsiveHelper.spacing(context, 16)),
          child: _buildWorkTypeSection(theme, entry.key, entry.value),
        );
      }).toList(),
    );
  }

  /// 업무 유형 섹션
  Widget _buildWorkTypeSection(ThemeData theme, String workType, List<ApplicationModel> workers) {
    // WorkDetail에서 해당 업무의 공식 근무시간 가져오기
    final workDetailTime = _workDetailTimeMap[workType];
    String timeStr = '';
    if (workDetailTime != null) {
      final startTime = workDetailTime['startTime'] ?? '';
      final endTime = workDetailTime['endTime'] ?? '';
      if (startTime.isNotEmpty && endTime.isNotEmpty) {
        timeStr = '$startTime ~ $endTime';
      }
    }
    
    // 업무유형 정보 가져오기
    final workTypeInfo = _workTypeMap[workType];
    final iconColor = workTypeInfo?.color != null 
        ? FormatHelper.parseColor(workTypeInfo!.color!)
        : theme.primaryColor;
    final bgColor = workTypeInfo?.backgroundColor != null
        ? FormatHelper.parseColor(workTypeInfo!.backgroundColor!)
        : theme.primaryColor.withOpacity(0.1);

    return Container(
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 업무 유형 헤더
          Container(
            padding: ResponsiveHelper.cardPadding(context),
            decoration: BoxDecoration(
              color: theme.primaryColor.withOpacity(0.05),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
              ),
            ),
            child: Row(
              children: [
                // 업무유형 아이콘 (색상/배경색 적용)
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
                // 인원 배지
                Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: ResponsiveHelper.spacing(context, 12),
                    vertical: ResponsiveHelper.spacing(context, 6),
                  ),
                  decoration: BoxDecoration(
                    color: theme.primaryColor,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${workers.length}명',
                    style: ResponsiveHelper.smallStyle(context, color: Colors.white).copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),

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

  /// 근무자 카드
  Widget _buildWorkerCard(ApplicationModel app) {
    final theme = Theme.of(context);
    final user = _userMap[app.uid];
    final statusInfo = _getAttendanceStatus(app);
    final isSelected = _selectedIds.contains(app.id);
    final displayName = _getDisplayName(app.uid);
    final genderAge = _getGenderAge(app.uid);

    return Container(
      margin: EdgeInsets.only(bottom: ResponsiveHelper.spacing(context, 8)),
      decoration: BoxDecoration(
        color: isSelected 
            ? theme.primaryColor.withOpacity(0.08) 
            : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isSelected ? theme.primaryColor : AppColors.border,
          width: isSelected ? 1.5 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
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
                // 체크박스
                SizedBox(
                  width: 22,
                  height: 22,
                  child: Checkbox(
                    value: isSelected,
                    onChanged: (_) => _toggleSelection(app.id),
                    activeColor: theme.primaryColor,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),

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

                      // 상태 뱃지 + 시계 아이콘(미출근) + 시간
                      Row(
                        children: [
                          // 상태 뱃지
                          Container(
                            padding: EdgeInsets.symmetric(
                              horizontal: ResponsiveHelper.spacing(context, 8),
                              vertical: ResponsiveHelper.spacing(context, 2),
                            ),
                            decoration: BoxDecoration(
                              color: (statusInfo['color'] as Color).withOpacity(0.15),
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

                          // 미출근일 때 시계 아이콘
                          if (statusInfo['status'] == 'pending') ...[
                            SizedBox(width: ResponsiveHelper.spacing(context, 4)),
                            Icon(
                              Icons.access_time,
                              size: ResponsiveHelper.iconSize(context, 14),
                              color: AppColors.grey500,
                            ),
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

  /// 더보기 메뉴 (PopupMenuButton)
  Widget _buildMoreMenu(ApplicationModel app, Map<String, dynamic> statusInfo) {
    final theme = Theme.of(context);
    final status = statusInfo['status'] as String;
    final user = _userMap[app.uid];

    return PopupMenuButton<String>(
      icon: Icon(
        Icons.more_vert,
        color: AppColors.grey500,
        size: ResponsiveHelper.iconSize(context, 22),
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      offset: const Offset(0, 40),
      onSelected: (value) async {
        switch (value) {
          case 'detail':
            if (user != null) {
              WorkerDetailDialog.show(
                context: context,
                user: user,
                application: app,
                businessId: _selectedBusinessId,
                isConfirmed: true,
                showApprovalButtons: false,
                onStatusChanged: _loadData,
              );
            }
            break;
          case 'checkin':
            _showCheckInDialog(app);
            break;
          case 'checkout':
            _showCheckOutDialog(app);
            break;
          case 'edit_time':
            _showEditTimeDialog(app);
            break;
          case 'noshow':
            _markNoShow(app);
            break;
          case 'cancel_noshow':
            _cancelNoShow(app);
            break;
        }
      },
      itemBuilder: (context) {
        final items = <PopupMenuEntry<String>>[];

        // 상세보기 (항상)
        items.add(PopupMenuItem(
          value: 'detail',
          child: Row(
            children: [
              Icon(Icons.person_outline, size: 20, color: theme.primaryColor),
              const SizedBox(width: 12),
              const Text('상세보기'),
            ],
          ),
        ));

        items.add(const PopupMenuDivider());

        // 상태별 메뉴
        if (status == 'pending') {
          // 미출근
          items.add(PopupMenuItem(
            value: 'checkin',
            child: Row(
              children: [
                Icon(Icons.login, size: 20, color: AppColors.success),
                const SizedBox(width: 12),
                const Text('출근 처리'),
              ],
            ),
          ));
          items.add(PopupMenuItem(
            value: 'noshow',
            child: Row(
              children: [
                Icon(Icons.person_off, size: 20, color: AppColors.error),
                const SizedBox(width: 12),
                const Text('노쇼 처리'),
              ],
            ),
          ));
        } else if (status == 'checkin' || status == 'late') {
          // 출근 완료
          items.add(PopupMenuItem(
            value: 'checkout',
            child: Row(
              children: [
                Icon(Icons.logout, size: 20, color: Colors.purple),
                const SizedBox(width: 12),
                const Text('퇴근 처리'),
              ],
            ),
          ));
          items.add(PopupMenuItem(
            value: 'edit_time',
            child: Row(
              children: [
                Icon(Icons.edit_outlined, size: 20, color: AppColors.info),
                const SizedBox(width: 12),
                const Text('시간 수정'),
              ],
            ),
          ));
        } else if (status == 'checkout') {
          // 퇴근 완료
          items.add(PopupMenuItem(
            value: 'edit_time',
            child: Row(
              children: [
                Icon(Icons.edit_outlined, size: 20, color: AppColors.info),
                const SizedBox(width: 12),
                const Text('시간 수정'),
              ],
            ),
          ));
        } else if (status == 'noshow') {
          // 노쇼
          items.add(PopupMenuItem(
            value: 'cancel_noshow',
            child: Row(
              children: [
                Icon(Icons.undo, size: 20, color: AppColors.info),
                const SizedBox(width: 12),
                const Text('노쇼 해제'),
              ],
            ),
          ));
        }

        return items;
      },
    );
  }

  /// 하단 버튼 바
  Widget _buildBottomBar(ThemeData theme) {
    return Container(
      padding: ResponsiveHelper.cardPadding(context),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(24),
          bottomRight: Radius.circular(24),
        ),
        border: Border(
          top: BorderSide(color: AppColors.border),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
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

          // 고정근무 관리 버튼 (WorkerDetailDialog와 동일)
          Expanded(
            child: ElevatedButton.icon(
              onPressed: _selectedBusinessId != null ? _openFixedWorkerManagement : null,
              icon: Icon(Icons.settings, size: ResponsiveHelper.iconSize(context, 18)),
              label: const Text('고정근무 관리'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.longTermDark,
                foregroundColor: Colors.white,
                padding: EdgeInsets.symmetric(
                  vertical: ResponsiveHelper.spacing(context, 12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
  /// 고정근무 관리 다이얼로그 열기
  void _openFixedWorkerManagement() {
    if (_selectedBusinessId == null) {
      ToastHelper.showWarning('사업장을 선택해주세요');
      return;
    }

    showDialog(
      context: context,
      builder: (context) => FixedWorkerManagementDialog(
        businessId: _selectedBusinessId!,
        onChanged: () {
          _loadData(); // 데이터 새로고침
        },
      ),
    );
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
      builder: (context) => PopScope(
        canPop: false,
        child: Center(
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 16),
                Text(
                  '명단 생성 중...',
                  style: ResponsiveHelper.bodyStyle(context),
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

      // 로딩 닫기
      if (mounted) Navigator.pop(context);

      // 미리보기 표시
      await AttendanceListPdf.showPreview(
        context: context,
        data: data,
      );
    } catch (e, stack) {
      // 로딩 닫기
      if (mounted) Navigator.pop(context);
      
      print('❌ 명단 출력 실패: $e');
      print(stack);
      ToastHelper.showError('명단 출력 실패');
    }
  }

  /// TO WorkDetail에서 업무유형별 시간 정보 조회
  Future<Map<String, dynamic>> _getWorkDetailTimes() async {
    final Map<String, dynamic> timeInfoMap = {};
    
    if (_selectedBusinessId == null) return timeInfoMap;

    try {
      // 해당 날짜의 TO 조회
      final toSnapshot = await FirebaseFirestore.instance
          .collection('tos')
          .where('businessId', isEqualTo: _selectedBusinessId)
          .where('date', isEqualTo: Timestamp.fromDate(
            DateTime(widget.date.year, widget.date.month, widget.date.day)
          ))
          .limit(1)
          .get();

      if (toSnapshot.docs.isEmpty) return timeInfoMap;

      final toId = toSnapshot.docs.first.id;

      // WorkDetail 조회
      final workDetailSnapshot = await FirebaseFirestore.instance
          .collection('tos')
          .doc(toId)
          .collection('workDetails')
          .get();

      for (var doc in workDetailSnapshot.docs) {
        final data = doc.data();
        final workType = data['workType'] ?? '';
        if (workType.isNotEmpty) {
          timeInfoMap[workType] = {
            'startTime': data['startTime'] ?? '',
            'endTime': data['endTime'] ?? '',
          };
        }
      }
    } catch (e) {
      print('❌ WorkDetail 시간 조회 실패: $e');
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

  /// 일괄 출근 다이얼로그
  Future<void> _showBatchCheckInDialog() async {
    if (_selectedIds.isEmpty) return;

    final time = await _showTimePickerDialog(
      title: '일괄 출근 (${_selectedIds.length}명)',
    );
    
    if (time != null) {
      await _processBatchCheckIn(time);
    }
  }

  /// 일괄 퇴근 다이얼로그
  Future<void> _showBatchCheckOutDialog() async {
    if (_selectedIds.isEmpty) return;

    // 출근한 인원만 필터
    final checkedInIds = _selectedIds.where((id) {
      final app = _confirmedWorkers.firstWhere((a) => a.id == id);
      final status = _getAttendanceStatus(app);
      return status['status'] == 'checkin' || status['status'] == 'late';
    }).toList();

    if (checkedInIds.isEmpty) {
      ToastHelper.showWarning('출근 처리된 인원만 퇴근 처리할 수 있습니다');
      return;
    }

    final time = await _showTimePickerDialog(
      title: '일괄 퇴근 (${checkedInIds.length}명)',
    );
    
    if (time != null) {
      await _processBatchCheckOut(time, checkedInIds);
    }
  }

  /// 개별 출근 다이얼로그
  Future<void> _showCheckInDialog(ApplicationModel app) async {
    final defaultTime = app.startTime.isNotEmpty ? app.startTime : '09:00';
    final userName = _getDisplayName(app.uid);

    final time = await _showTimePickerDialog(
      title: '$userName 출근',
      initialTime: defaultTime,
    );
    
    if (time != null) {
      await _processCheckIn(app, time);
    }
  }

  /// 개별 퇴근 다이얼로그
  Future<void> _showCheckOutDialog(ApplicationModel app) async {
    final defaultTime = app.endTime.isNotEmpty ? app.endTime : '18:00';
    final userName = _getDisplayName(app.uid);

    final time = await _showTimePickerDialog(
      title: '$userName 퇴근',
      initialTime: defaultTime,
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
                    color: AppColors.info.withOpacity(0.1),
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
                  iconColor: Colors.purple,
                  iconBgColor: Colors.purple[50]!,
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
        color: Colors.grey[100],
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
              icon: Icon(Icons.close, color: AppColors.error, size: 20),
              onPressed: onDelete,
              constraints: const BoxConstraints(),
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

  /// 일괄 출근 처리
  Future<void> _processBatchCheckIn(String time) async {
    setState(() => _isProcessing = true);

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
      print('❌ 일괄 출근 처리 실패: $e');
      ToastHelper.showError('일괄 출근 처리 실패');
    } finally {
      setState(() => _isProcessing = false);
    }
  }

  /// 일괄 퇴근 처리
  Future<void> _processBatchCheckOut(String time, List<String> targetIds) async {
    setState(() => _isProcessing = true);

    try {
      int successCount = 0;
      int failCount = 0;

      for (var appId in targetIds) {
        final app = _confirmedWorkers.firstWhere((a) => a.id == appId);
        final attendance = _attendanceMap[app.id];

        if (attendance == null) continue;

        try {
          await FirebaseFirestore.instance
              .collection('attendance')
              .doc(attendance.id)
              .update({
            'checkOut': time,
            'checkOutMethod': 'manual',
            'checkOutTime': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          });
          successCount++;
        } catch (e) {
          failCount++;
        }
      }

      if (successCount > 0) {
        ToastHelper.showSuccess('$successCount명 퇴근 처리 완료');
      }
      if (failCount > 0) {
        ToastHelper.showWarning('$failCount명 처리 실패');
      }

      await _loadData();
    } catch (e) {
      print('❌ 일괄 퇴근 처리 실패: $e');
      ToastHelper.showError('일괄 퇴근 처리 실패');
    } finally {
      setState(() => _isProcessing = false);
    }
  }

  /// 개별 출근 처리
  Future<void> _processCheckIn(ApplicationModel app, String time) async {
    setState(() => _isProcessing = true);

    try {
      await _createOrUpdateAttendance(app: app, checkIn: time);
      ToastHelper.showSuccess('출근 처리 완료');
      await _loadData();
    } catch (e) {
      print('❌ 출근 처리 실패: $e');
      ToastHelper.showError('출근 처리 실패');
    } finally {
      setState(() => _isProcessing = false);
    }
  }

  /// 개별 퇴근 처리
  Future<void> _processCheckOut(ApplicationModel app, String time) async {
    setState(() => _isProcessing = true);

    try {
      final attendance = _attendanceMap[app.id];
      if (attendance == null) {
        ToastHelper.showError('출근 기록이 없습니다');
        return;
      }

      await FirebaseFirestore.instance
          .collection('attendance')
          .doc(attendance.id)
          .update({
        'checkOut': time,
        'checkOutMethod': 'manual',
        'checkOutTime': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      ToastHelper.showSuccess('퇴근 처리 완료');
      await _loadData();
    } catch (e) {
      print('❌ 퇴근 처리 실패: $e');
      ToastHelper.showError('퇴근 처리 실패');
    } finally {
      setState(() => _isProcessing = false);
    }
  }

  /// 시간 수정
  Future<void> _updateAttendanceTime(ApplicationModel app, String? checkIn, String? checkOut) async {
    setState(() => _isProcessing = true);

    try {
      final attendance = _attendanceMap[app.id];
      if (attendance == null) return;

      // 둘 다 null이면 attendance 문서 삭제 (미출근 상태로 변경)
      if (checkIn == null && checkOut == null) {
        await FirebaseFirestore.instance
            .collection('attendance')
            .doc(attendance.id)
            .delete();

        ToastHelper.showSuccess('미출근 상태로 변경되었습니다');
        await _loadData();
        return;
      }

      final Map<String, dynamic> updates = {
        'isModified': true,
        'modifiedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      };

      if (checkIn != null) {
        updates['checkIn'] = checkIn;
      }
      
      if (checkOut != null) {
        updates['checkOut'] = checkOut;
      } else if (attendance.checkOut != null && checkOut == null) {
        // 퇴근 시간 삭제
        updates['checkOut'] = FieldValue.delete();
        updates['checkOutMethod'] = FieldValue.delete();
        updates['checkOutTime'] = FieldValue.delete();
      }

      await FirebaseFirestore.instance
          .collection('attendance')
          .doc(attendance.id)
          .update(updates);

      ToastHelper.showSuccess('시간이 수정되었습니다');
      await _loadData();
    } catch (e) {
      print('❌ 시간 수정 실패: $e');
      ToastHelper.showError('시간 수정 실패');
    } finally {
      setState(() => _isProcessing = false);
    }
  }

  /// Attendance 생성 또는 업데이트
  Future<void> _createOrUpdateAttendance({
    required ApplicationModel app,
    required String checkIn,
  }) async {
    final existingAttendance = _attendanceMap[app.id];

    if (existingAttendance != null) {
      // 업데이트
      await FirebaseFirestore.instance
          .collection('attendance')
          .doc(existingAttendance.id)
          .update({
        'checkIn': checkIn,
        'checkInMethod': 'manual',
        'checkInTime': FieldValue.serverTimestamp(),
        'status': 'CHECKED_IN',
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } else {
      // 새로 생성
      await FirebaseFirestore.instance.collection('attendance').add({
        'applicationId': app.id,
        'uid': app.uid,
        'businessId': app.businessId,
        'toTitle': app.toTitle,
        'workDate': Timestamp.fromDate(widget.date),
        'workType': app.selectedWorkType,
        'checkIn': checkIn,
        'checkInMethod': 'manual',
        'checkInTime': FieldValue.serverTimestamp(),
        'status': 'CHECKED_IN',
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

    setState(() => _isProcessing = true);

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
          'uid': app.uid,
          'businessId': app.businessId,
          'toTitle': app.toTitle,
          'workDate': Timestamp.fromDate(widget.date),
          'workType': app.selectedWorkType,
          'status': 'NO_SHOW',
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }

      // 사용자 noShowCount 증가
      await FirebaseFirestore.instance
          .collection('users')
          .doc(app.uid)
          .update({
        'noShowCount': FieldValue.increment(1),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      ToastHelper.showSuccess('노쇼 처리 완료');
      await _loadData();
    } catch (e) {
      print('❌ 노쇼 처리 실패: $e');
      ToastHelper.showError('노쇼 처리 실패');
    } finally {
      setState(() => _isProcessing = false);
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

    setState(() => _isProcessing = true);

    try {
      final attendance = _attendanceMap[app.id];
      if (attendance != null) {
        // 출근 기록이 있으면 상태만 변경
        await FirebaseFirestore.instance
            .collection('attendance')
            .doc(attendance.id)
            .update({
          'status': 'PENDING',
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
      print('❌ 노쇼 해제 실패: $e');
      ToastHelper.showError('노쇼 해제 실패');
    } finally {
      setState(() => _isProcessing = false);
    }
  }
}