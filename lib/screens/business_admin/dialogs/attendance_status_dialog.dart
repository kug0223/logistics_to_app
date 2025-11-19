import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

// Models
import '../../../models/core/application_model.dart';
import '../../../models/core/attendance_model.dart';

// Services
import '../../../services/firestore_service.dart';

// Utils
import '../../../utils/toast_helper.dart';
import '../../../utils/responsive_helper.dart';  // ⭐ 추가

// Widgets
import '../../../widgets/common/loading_widget.dart';

/// 인원현황 다이얼로그 - 완전 반응형 + 테마 적용
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
  final FirestoreService _firestoreService = FirestoreService();

  List<ApplicationModel> _confirmedWorkers = [];
  Map<String, AttendanceModel> _attendanceMap = {};
  Map<String, String> _userNameMap = {};
  Map<String, String> _businessNameMap = {}; 
  bool _isLoading = true;
  String? _selectedBusinessId;

  @override
  void initState() {
    super.initState();
    _selectedBusinessId = widget.initialBusinessId ?? widget.businessIds.first;
    _loadBusinessNames();
    _loadData();
  }
  
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

  /// 데이터 로드
  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    try {
      // 1. 확정 근무자 조회
      final confirmedWorkers = await _getConfirmedWorkersForDate();

      // 2. 출근 기록 조회
      final attendanceMap = await _getAttendanceRecords(
        confirmedWorkers.map((app) => app.id).toList(),
      );
      
      // 3. 사용자 이름 조회
      final userNameMap = await _getUserNames(
        confirmedWorkers.map((app) => app.uid).toSet().toList(),
      );

      setState(() {
        _confirmedWorkers = confirmedWorkers;
        _attendanceMap = attendanceMap;
        _userNameMap = userNameMap; 
        _isLoading = false;
      });
    } catch (e) {
      print('❌ 인원현황 데이터 로드 실패: $e');
      setState(() => _isLoading = false);
      ToastHelper.showError('데이터 로드 실패');
    }
  }

  /// 확정 근무자 조회
  Future<List<ApplicationModel>> _getConfirmedWorkersForDate() async {
    final dateStart = DateTime(widget.date.year, widget.date.month, widget.date.day);

    print('🔍 [인원현황] 조회 시작');
    print('   날짜: ${DateFormat('yyyy-MM-dd').format(dateStart)}');
    print('   사업장: $_selectedBusinessId');

    final snapshot = await FirebaseFirestore.instance
        .collection('applications')
        .where('businessId', isEqualTo: _selectedBusinessId)
        .where('status', isEqualTo: 'CONFIRMED')
        .get();

    print('   📋 전체 확정 지원서: ${snapshot.docs.length}개');

    final allConfirmed = snapshot.docs
        .map((doc) => ApplicationModel.fromFirestore(doc))
        .toList();

    // 단기 + 장기 필터링
    final result = allConfirmed.where((app) {
      print('   ━━━━━━━━━━━━━━━━━━━━');
      print('   📄 지원서: ${app.id}');
      print('      - isLongTermApplication: ${app.isLongTermApplication}');
      print('      - workDate: ${DateFormat('yyyy-MM-dd').format(app.workDate)}');
      
      // 단기 근무
      if (!app.isLongTermApplication) {
        final isSame = DateUtils.isSameDay(app.workDate, dateStart);
        print('      → 단기: ${isSame ? "✅ 포함" : "❌ 제외"}');
        return isSame;
      }

      // 장기 근무
      print('      - workEndDate: ${app.workEndDate}');
      print('      - workDays: ${app.workDays}');
      
      if (app.workEndDate == null) {
        print('      → 장기: workEndDate null, ❌ 제외');
        return false;
      }

      // 기간 체크
      final isInRange = !dateStart.isBefore(app.workDate) && 
                      !dateStart.isAfter(app.workEndDate!);
      
      print('      - 기간 체크: $isInRange');
      
      if (!isInRange) {
        print('      → 장기: 기간 밖, ❌ 제외');
        return false;
      }

      // 요일 체크
      if (app.workDays == null || app.workDays!.isEmpty) {
        print('      → 장기: 매일 근무, ✅ 포함');
        return true; // 매일 근무
      }

      final weekdays = ['월', '화', '수', '목', '금', '토', '일'];
      final dayWeekday = weekdays[widget.date.weekday - 1];
      final hasDay = app.workDays!.contains(dayWeekday);

      print('      - 오늘 요일: $dayWeekday');
      print('      - 근무 요일: ${app.workDays}');
      print('      → 장기: ${hasDay ? "✅ 포함" : "❌ 제외"}');

      return hasDay;
    }).toList();

    print('   ━━━━━━━━━━━━━━━━━━━━');
    print('   ✅ 최종 결과: ${result.length}명');
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
        .where('workDate',
            isGreaterThanOrEqualTo: Timestamp.fromDate(dateStart))
        .where('workDate', isLessThan: Timestamp.fromDate(dateEnd))
        .get();

    final Map<String, AttendanceModel> attendanceMap = {};

    for (var doc in snapshot.docs) {
      final attendance = AttendanceModel.fromFirestore(doc);
      attendanceMap[attendance.applicationId] = attendance;
    }

    return attendanceMap;
  }
  
  /// 사용자 이름 조회
  Future<Map<String, String>> _getUserNames(List<String> uids) async {
    if (uids.isEmpty) return {};

    final Map<String, String> nameMap = {};

    // 배치로 조회 (10개씩)
    for (int i = 0; i < uids.length; i += 10) {
      final chunk = uids.skip(i).take(10).toList();

      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .where(FieldPath.documentId, whereIn: chunk)
          .get();

      for (var doc in snapshot.docs) {
        final data = doc.data();
        nameMap[doc.id] = data['name'] ?? 'Unknown';
      }
    }

    return nameMap;
  }

  @override
  Widget build(BuildContext context) {
    final dateStr = DateFormat('MM월 dd일 (E)', 'ko_KR').format(widget.date);

    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Container(
        width: MediaQuery.of(context).size.width * 0.9,
        constraints: const BoxConstraints(maxHeight: 600),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ⭐ 헤더 (반응형 + 테마)
            Container(
              padding: ResponsiveHelper.cardPadding(context),
              decoration: BoxDecoration(
                color: Theme.of(context).primaryColor,  // ⭐ 테마 색상
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(16),
                  topRight: Radius.circular(16),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.groups, 
                        color: Colors.white, 
                        size: ResponsiveHelper.iconSize(context, 28),  // ⭐ 반응형
                      ),
                      SizedBox(width: ResponsiveHelper.spacing(context, 12)),
                      Expanded(
                        child: Text(
                          '$dateStr 인원 현황',
                          style: ResponsiveHelper.titleStyle(context).copyWith(  // ⭐ 반응형
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: Icon(
                          Icons.close, 
                          color: Colors.white,
                          size: ResponsiveHelper.iconSize(context, 24),  // ⭐ 반응형
                        ),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                  
                  // ⭐ 사업장 선택 드롭다운 (반응형)
                  if (widget.businessIds.length > 1) ...[
                    SizedBox(height: ResponsiveHelper.spacing(context, 12)),
                    Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: ResponsiveHelper.spacing(context, 12),
                        vertical: ResponsiveHelper.spacing(context, 4),
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.white.withOpacity(0.3)),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          isExpanded: true,
                          value: _selectedBusinessId,
                          dropdownColor: Theme.of(context).primaryColor.withOpacity(0.9),  // ⭐ 테마
                          style: ResponsiveHelper.bodyStyle(  // ⭐ 반응형
                            context,
                            color: Colors.white,
                          ),
                          icon: Icon(
                            Icons.arrow_drop_down, 
                            color: Colors.white,
                            size: ResponsiveHelper.iconSize(context, 24),  // ⭐ 반응형
                          ),
                          items: widget.businessIds.map((id) {
                            return DropdownMenuItem(
                              value: id,
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.business, 
                                    color: Colors.white, 
                                    size: ResponsiveHelper.iconSize(context, 16),  // ⭐ 반응형
                                  ),
                                  SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                                  Text(_businessNameMap[id] ?? 'Loading...'),
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
                ],
              ),
            ),

            // ⭐ 내용 (반응형)
            Expanded(
              child: _isLoading
                  ? const LoadingWidget(message: '인원현황 조회 중...')
                  : SingleChildScrollView(
                      padding: ResponsiveHelper.cardPadding(context),  // ⭐ 반응형
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // 전체 통계
                          _buildOverallStats(),

                          SizedBox(height: ResponsiveHelper.spacing(context, 24)),
                          const Divider(),
                          SizedBox(height: ResponsiveHelper.spacing(context, 24)),

                          // 업무별 인원
                          _buildWorkTypeGroups(),
                        ],
                      ),
                    ),
            ),

            // ⭐ 닫기 버튼 (반응형 + 테마)
            Container(
              padding: ResponsiveHelper.cardPadding(context),  // ⭐ 반응형
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(color: Theme.of(context).dividerColor),  // ⭐ 테마
                ),
              ),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                    padding: EdgeInsets.symmetric(
                      vertical: ResponsiveHelper.spacing(context, 14),  // ⭐ 반응형
                    ),
                  ),
                  child: Text(
                    '닫기',
                    style: ResponsiveHelper.bodyStyle(context).copyWith(  // ⭐ 반응형
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// ⭐ 전체 통계 (반응형 + 테마)
  Widget _buildOverallStats() {
    final total = _confirmedWorkers.length;
    final checkedIn =
        _attendanceMap.values.where((att) => att.checkIn != null).length;
    final checkedOut =
        _attendanceMap.values.where((att) => att.checkOut != null).length;
    final notCheckedIn = total - checkedIn;

    final checkedInPercentage = total > 0 ? (checkedIn / total * 100).round() : 0;

    return Container(
      padding: ResponsiveHelper.cardPadding(context),  // ⭐ 반응형
      decoration: BoxDecoration(
        color: Theme.of(context).primaryColor.withOpacity(0.1),  // ⭐ 테마
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Theme.of(context).primaryColor.withOpacity(0.3),  // ⭐ 테마
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.assessment, 
                color: Theme.of(context).primaryColor,  // ⭐ 테마
                size: ResponsiveHelper.iconSize(context, 24),  // ⭐ 반응형
              ),
              SizedBox(width: ResponsiveHelper.spacing(context, 8)),
              Text(
                '전체 통계',
                style: ResponsiveHelper.subtitleStyle(context).copyWith(  // ⭐ 반응형
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 16)),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildStatItem(
                label: '확정 인원',
                value: '$total명',
                icon: Icons.people,
                color: Colors.blue,
              ),
              _buildStatItem(
                label: '출근 완료',
                value: '$checkedIn명',
                subValue: '($checkedInPercentage%)',
                icon: Icons.check_circle,
                color: Colors.green,
              ),
              _buildStatItem(
                label: '미출근',
                value: '$notCheckedIn명',
                icon: Icons.schedule,
                color: Colors.orange,
              ),
              _buildStatItem(
                label: '퇴근 완료',
                value: '$checkedOut명',
                icon: Icons.home,
                color: Colors.purple,
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// ⭐ 통계 아이템 (반응형)
  Widget _buildStatItem({
    required String label,
    required String value,
    String? subValue,
    required IconData icon,
    required MaterialColor color,
  }) {
    return Column(
      children: [
        Icon(
          icon, 
          color: color[600], 
          size: ResponsiveHelper.iconSize(context, 28),  // ⭐ 반응형
        ),
        SizedBox(height: ResponsiveHelper.spacing(context, 4)),
        Text(
          label,
          style: ResponsiveHelper.tinyStyle(  // ⭐ 반응형
            context,
            color: Theme.of(context).textTheme.bodySmall?.color,  // ⭐ 테마
          ),
        ),
        SizedBox(height: ResponsiveHelper.spacing(context, 2)),
        Text(
          value,
          style: ResponsiveHelper.bodyStyle(context).copyWith(  // ⭐ 반응형
            fontWeight: FontWeight.bold,
            color: color[700],
          ),
        ),
        if (subValue != null)
          Text(
            subValue,
            style: ResponsiveHelper.tinyStyle(  // ⭐ 반응형
              context,
              color: color[600],
            ),
          ),
      ],
    );
  }

  /// ⭐ 업무별 그룹 (반응형)
  Widget _buildWorkTypeGroups() {
    // 업무 유형별로 그룹화
    final Map<String, List<ApplicationModel>> workTypeGroups = {};

    for (var app in _confirmedWorkers) {
      final workType = app.selectedWorkType;
      if (!workTypeGroups.containsKey(workType)) {
        workTypeGroups[workType] = [];
      }
      workTypeGroups[workType]!.add(app);
    }

    if (workTypeGroups.isEmpty) {
      return Center(
        child: Padding(
          padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 40)),  // ⭐ 반응형
          child: Text(
            '확정된 근무자가 없습니다',
            style: ResponsiveHelper.bodyStyle(  // ⭐ 반응형
              context,
              color: Theme.of(context).disabledColor,  // ⭐ 테마
            ),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: workTypeGroups.entries.map((entry) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: ResponsiveHelper.spacing(context, 20),  // ⭐ 반응형
          ),
          child: _buildWorkTypeGroup(entry.key, entry.value),
        );
      }).toList(),
    );
  }

  /// ⭐ 업무 유형 그룹 (반응형 + 테마)
  Widget _buildWorkTypeGroup(String workType, List<ApplicationModel> workers) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 업무 유형 헤더
        Row(
          children: [
            Icon(
              Icons.work, 
              color: Theme.of(context).primaryColor,  // ⭐ 테마
              size: ResponsiveHelper.iconSize(context, 20),  // ⭐ 반응형
            ),
            SizedBox(width: ResponsiveHelper.spacing(context, 8)),
            Text(
              '$workType (${workers.length}명)',
              style: ResponsiveHelper.bodyStyle(context).copyWith(  // ⭐ 반응형
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        SizedBox(height: ResponsiveHelper.spacing(context, 12)),

        // 근무자 목록
        ...workers.map((app) => _buildWorkerItem(app)),
      ],
    );
  }

  /// ⭐ 근무자 아이템 (반응형 + 테마)
  Widget _buildWorkerItem(ApplicationModel app) {
    final attendance = _attendanceMap[app.id];
    final hasCheckedIn = attendance?.checkIn != null;
    final hasCheckedOut = attendance?.checkOut != null;

    IconData icon;
    Color iconColor;
    String statusText;
    String? timeText;

    if (hasCheckedOut) {
      icon = Icons.home;
      iconColor = Colors.purple;
      statusText = '퇴근';
      timeText = '${attendance!.checkIn} ~ ${attendance.checkOut}';
    } else if (hasCheckedIn) {
      icon = Icons.check_circle;
      iconColor = Colors.green;
      statusText = '출근';
      timeText = attendance!.checkIn;
    } else {
      icon = Icons.schedule;
      iconColor = Colors.orange;
      statusText = '미출근';
      timeText = null;
    }

    return Container(
      margin: EdgeInsets.only(
        bottom: ResponsiveHelper.spacing(context, 8),  // ⭐ 반응형
      ),
      padding: ResponsiveHelper.cardPadding(context),  // ⭐ 반응형
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,  // ⭐ 테마
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Theme.of(context).dividerColor),  // ⭐ 테마
      ),
      child: Row(
        children: [
          Icon(
            icon, 
            color: iconColor, 
            size: ResponsiveHelper.iconSize(context, 20),  // ⭐ 반응형
          ),
          SizedBox(width: ResponsiveHelper.spacing(context, 12)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      _userNameMap[app.uid] ?? 'Unknown',
                      style: ResponsiveHelper.bodyStyle(context).copyWith(  // ⭐ 반응형
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                    Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: ResponsiveHelper.spacing(context, 6),  // ⭐ 반응형
                        vertical: ResponsiveHelper.spacing(context, 2),
                      ),
                      decoration: BoxDecoration(
                        color: app.isLongTermApplication
                            ? Colors.purple[100]
                            : Theme.of(context).primaryColor.withOpacity(0.2),  // ⭐ 테마
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        app.isLongTermApplication ? '장기' : '단기',
                        style: ResponsiveHelper.tinyStyle(  // ⭐ 반응형
                          context,
                          color: app.isLongTermApplication
                              ? Colors.purple[700]
                              : Theme.of(context).primaryColor,  // ⭐ 테마
                        ),
                      ),
                    ),
                  ],
                ),
                if (timeText != null) ...[
                  SizedBox(height: ResponsiveHelper.spacing(context, 4)),
                  Text(
                    timeText,
                    style: ResponsiveHelper.smallStyle(  // ⭐ 반응형
                      context,
                      color: Theme.of(context).textTheme.bodySmall?.color,  // ⭐ 테마
                    ),
                  ),
                ],
              ],
            ),
          ),
          Container(
            padding: EdgeInsets.symmetric(
              horizontal: ResponsiveHelper.spacing(context, 8),  // ⭐ 반응형
              vertical: ResponsiveHelper.spacing(context, 4),
            ),
            decoration: BoxDecoration(
              color: iconColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              statusText,
              style: ResponsiveHelper.smallStyle(  // ⭐ 반응형
                context,
                fontWeight: FontWeight.bold,
                color: iconColor,
              ),
            ),
          ),
        ],
      ),
    );
  }
}