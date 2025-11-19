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

// Widgets
import '../../../widgets/common/loading_widget.dart';

/// 인원현황 다이얼로그
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
  
  /// ⭐ 사업장명 조회
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
      // ⭐ 3. 사용자 이름 조회
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

    final snapshot = await FirebaseFirestore.instance
        .collection('applications')
        .where('businessId', isEqualTo: _selectedBusinessId)  // ⭐ 변경
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
      if (dateStart.isBefore(app.workDate) || dateStart.isAfter(app.workEndDate!)) {
        return false;
      }

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
            // 헤더
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.blue[700],
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
                      const Icon(Icons.groups, color: Colors.white, size: 28),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          '$dateStr 인원 현황',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                  
                  // ⭐ 사업장 선택 드롭다운
                  if (widget.businessIds.length > 1) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.white.withOpacity(0.3)),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          isExpanded: true,
                          value: _selectedBusinessId,
                          dropdownColor: Colors.blue[800],
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                          ),
                          icon: const Icon(Icons.arrow_drop_down, color: Colors.white),
                          items: widget.businessIds.map((id) {
                            return DropdownMenuItem(
                              value: id,
                              child: Row(
                                children: [
                                  const Icon(Icons.business, color: Colors.white, size: 16),
                                  const SizedBox(width: 8),
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

            // 내용
            Expanded(
              child: _isLoading
                  ? const LoadingWidget(message: '인원현황 조회 중...')
                  : SingleChildScrollView(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // 전체 통계
                          _buildOverallStats(),

                          const SizedBox(height: 24),
                          const Divider(),
                          const SizedBox(height: 24),

                          // 업무별 인원
                          _buildWorkTypeGroups(),
                        ],
                      ),
                    ),
            ),

            // 닫기 버튼
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(color: Colors.grey[300]!),
                ),
              ),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: const Text('닫기'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 전체 통계
  Widget _buildOverallStats() {
    final total = _confirmedWorkers.length;
    final checkedIn =
        _attendanceMap.values.where((att) => att.checkIn != null).length;
    final checkedOut =
        _attendanceMap.values.where((att) => att.checkOut != null).length;
    final notCheckedIn = total - checkedIn;

    final checkedInPercentage = total > 0 ? (checkedIn / total * 100).round() : 0;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.blue[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blue[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.assessment, color: Colors.blue[700], size: 24),
              const SizedBox(width: 8),
              const Text(
                '전체 통계',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
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

  /// 통계 아이템
  Widget _buildStatItem({
    required String label,
    required String value,
    String? subValue,
    required IconData icon,
    required MaterialColor color,
  }) {
    return Column(
      children: [
        Icon(icon, color: color[600], size: 28),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: Colors.grey[600],
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.bold,
            color: color[700],
          ),
        ),
        if (subValue != null)
          Text(
            subValue,
            style: TextStyle(
              fontSize: 11,
              color: color[600],
            ),
          ),
      ],
    );
  }

  /// 업무별 그룹
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
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(40.0),
          child: Text(
            '확정된 근무자가 없습니다',
            style: TextStyle(color: Colors.grey),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: workTypeGroups.entries.map((entry) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 20),
          child: _buildWorkTypeGroup(entry.key, entry.value),
        );
      }).toList(),
    );
  }

  /// 업무 유형 그룹
  Widget _buildWorkTypeGroup(String workType, List<ApplicationModel> workers) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 업무 유형 헤더
        Row(
          children: [
            Icon(Icons.work, color: Colors.blue[700], size: 20),
            const SizedBox(width: 8),
            Text(
              '$workType (${workers.length}명)',
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // 근무자 목록
        ...workers.map((app) => _buildWorkerItem(app)),
      ],
    );
  }

  /// 근무자 아이템
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
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: Row(
        children: [
          Icon(icon, color: iconColor, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      _userNameMap[app.uid] ?? 'Unknown',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: app.isLongTermApplication
                            ? Colors.purple[100]
                            : Colors.blue[100],
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        app.isLongTermApplication ? '장기' : '단기',
                        style: TextStyle(
                          fontSize: 10,
                          color: app.isLongTermApplication
                              ? Colors.purple[700]
                              : Colors.blue[700],
                        ),
                      ),
                    ),
                  ],
                ),
                if (timeText != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    timeText,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: iconColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              statusText,
              style: TextStyle(
                fontSize: 12,
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