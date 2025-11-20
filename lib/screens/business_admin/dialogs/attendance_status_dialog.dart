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
import '../../../utils/responsive_helper.dart';

// Widgets
import '../../../widgets/common/loading_widget.dart';

/// 인원현황 다이얼로그 - 세련된 디자인 (로그인 스타일)
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
  Map<String, Map<String, dynamic>> _userDetailMap = {};  // ✨ 추가
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
      
      // 3. 사용자 상세 정보 조회 (이름, 나이, 성별, 평점 등)
      final userDetailMap = await _getUserDetailInfo(
        confirmedWorkers.map((app) => app.uid).toSet().toList(),
      );
      
      // 4. 이름맵 생성 (호환성 유지)
      final userNameMap = <String, String>{};
      userDetailMap.forEach((uid, detail) {
        userNameMap[uid] = detail['name'] as String;
      });

      setState(() {
        _confirmedWorkers = confirmedWorkers;
        _attendanceMap = attendanceMap;
        _userDetailMap = userDetailMap;  // ✨ 상세 정보 저장
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

  /// ✨ 사용자 상세 정보 조회 (나이, 성별 포함)
  Future<Map<String, Map<String, dynamic>>> _getUserDetailInfo(List<String> uids) async {
    if (uids.isEmpty) return {};

    final Map<String, Map<String, dynamic>> detailMap = {};

    // 배치로 조회 (10개씩)
    for (int i = 0; i < uids.length; i += 10) {
      final chunk = uids.skip(i).take(10).toList();

      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .where(FieldPath.documentId, whereIn: chunk)
          .get();

      for (var doc in snapshot.docs) {
        final data = doc.data();
        
        // 나이 계산
        int? age;
        if (data['birthDate'] != null) {
          final birthDate = (data['birthDate'] as Timestamp).toDate();
          final now = DateTime.now();
          age = now.year - birthDate.year;
          if (now.month < birthDate.month ||
              (now.month == birthDate.month && now.day < birthDate.day)) {
            age--;
          }
        }
        
        detailMap[doc.id] = {
          'name': data['name'] ?? 'Unknown',
          'age': age,
          'gender': data['gender'],
          'phone': data['phone'],
          'averageRating': (data['averageRating'] ?? 0.0).toDouble(),
          'reviewCount': data['reviewCount'] ?? 0,
          'totalWorkDays': data['totalWorkDays'] ?? 0,
        };
      }
    }

    return detailMap;
  }

  /// ✨ 이름(나이, 성별) 형식으로 문자열 생성
  String _buildUserNameWithInfo(String uid) {
    final detail = _userDetailMap[uid];
    if (detail == null) {
      return _userNameMap[uid] ?? 'Unknown';
    }
    
    final name = detail['name'] as String;
    final age = detail['age'] as int?;
    final gender = detail['gender'] as String?;
    
    // 나이와 성별 모두 있으면
    if (age != null && gender != null) {
      final genderShort = gender == '남성' ? '남' : '여';
      return '$name ($age, $genderShort)';
    }
    // 나이만 있으면
    else if (age != null) {
      return '$name ($age)';
    }
    // 성별만 있으면
    else if (gender != null) {
      final genderShort = gender == '남성' ? '남' : '여';
      return '$name ($genderShort)';
    }
    // 둘 다 없으면 이름만
    else {
      return name;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dateStr = DateFormat('MM월 dd일 (E)', 'ko_KR').format(widget.date);

    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),  // ✨ 24px로 증가
      ),
      child: Container(
        width: MediaQuery.of(context).size.width * 0.9,
        constraints: const BoxConstraints(maxHeight: 650),  // ✨ 높이 증가
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),  // ✨ 부드러운 그림자
              blurRadius: 30,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ✨ 그라데이션 헤더
            Container(
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
                  Row(
                    children: [
                      // ✨ 아웃라인 아이콘
                      Container(
                        padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 8)),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          Icons.groups_outlined,  // ✨ 아웃라인 스타일
                          color: Colors.white, 
                          size: ResponsiveHelper.iconSize(context, 28),
                        ),
                      ),
                      SizedBox(width: ResponsiveHelper.spacing(context, 12)),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '인원 현황',
                              style: ResponsiveHelper.titleStyle(context).copyWith(
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            SizedBox(height: ResponsiveHelper.spacing(context, 4)),
                            Text(
                              dateStr,
                              style: ResponsiveHelper.bodyStyle(
                                context,
                                color: Colors.white.withOpacity(0.9),
                              ),
                            ),
                          ],
                        ),
                      ),
                      // ✨ 둥근 닫기 버튼
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
                  
                  // ✨ 사업장 선택 드롭다운 (세련된 스타일)
                  if (widget.businessIds.length > 1) ...[
                    SizedBox(height: ResponsiveHelper.spacing(context, 16)),
                    Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: ResponsiveHelper.spacing(context, 16),
                        vertical: ResponsiveHelper.spacing(context, 4),
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(12),  // ✨ 둥근 모서리
                        border: Border.all(
                          color: Colors.white.withOpacity(0.3),
                          width: 1.5,
                        ),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          isExpanded: true,
                          value: _selectedBusinessId,
                          dropdownColor: theme.primaryColor.withOpacity(0.95),
                          style: ResponsiveHelper.bodyStyle(
                            context,
                            color: Colors.white,
                          ).copyWith(
                            fontWeight: FontWeight.w500,
                          ),
                          icon: Icon(
                            Icons.arrow_drop_down_rounded,  // ✨ 둥근 아이콘
                            color: Colors.white,
                            size: ResponsiveHelper.iconSize(context, 24),
                          ),
                          items: widget.businessIds.map((id) {
                            return DropdownMenuItem(
                              value: id,
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.business_outlined,  // ✨ 아웃라인 스타일
                                    color: Colors.white, 
                                    size: ResponsiveHelper.iconSize(context, 18),
                                  ),
                                  SizedBox(width: ResponsiveHelper.spacing(context, 12)),
                                  Expanded(
                                    child: Text(
                                      _businessNameMap[id] ?? 'Loading...',
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
                ],
              ),
            ),

            // ✨ 내용 (반응형)
            Expanded(
              child: _isLoading
                  ? const LoadingWidget(message: '인원현황 조회 중...')
                  : SingleChildScrollView(
                      padding: ResponsiveHelper.cardPadding(context),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(height: ResponsiveHelper.spacing(context, 8)),
                          
                          // 전체 통계
                          _buildOverallStats(),

                          SizedBox(height: ResponsiveHelper.spacing(context, 24)),
                          
                          // ✨ 구분선
                          Container(
                            height: 1,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  Colors.transparent,
                                  theme.dividerColor,
                                  Colors.transparent,
                                ],
                              ),
                            ),
                          ),
                          
                          SizedBox(height: ResponsiveHelper.spacing(context, 24)),

                          // 업무별 인원
                          _buildWorkTypeGroups(),
                        ],
                      ),
                    ),
            ),

            // ✨ 하단 버튼 영역
            Container(
              padding: ResponsiveHelper.cardPadding(context),
              decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(24),
                  bottomRight: Radius.circular(24),
                ),
                border: Border(
                  top: BorderSide(
                    color: theme.dividerColor,
                    width: 1,
                  ),
                ),
              ),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: theme.primaryColor,
                    foregroundColor: Colors.white,
                    padding: EdgeInsets.symmetric(
                      vertical: ResponsiveHelper.spacing(context, 16),
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                  child: Text(
                    '닫기',
                    style: ResponsiveHelper.bodyStyle(context).copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: ResponsiveHelper.bodyStyle(context).fontSize! * 1.1,
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

  /// ✨ 전체 통계 (세련된 카드)
  Widget _buildOverallStats() {
    final theme = Theme.of(context);
    final total = _confirmedWorkers.length;
    final checkedIn =
        _attendanceMap.values.where((att) => att.checkIn != null).length;
    final checkedOut =
        _attendanceMap.values.where((att) => att.checkOut != null).length;
    final notCheckedIn = total - checkedIn;

    final checkedInPercentage = total > 0 ? (checkedIn / total * 100).round() : 0;

    return Container(
      padding: ResponsiveHelper.cardPadding(context),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            theme.primaryColor.withOpacity(0.08),
            theme.primaryColor.withOpacity(0.05),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: theme.primaryColor.withOpacity(0.2),
          width: 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // ✨ 아이콘 배경
              Container(
                padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 8)),
                decoration: BoxDecoration(
                  color: theme.primaryColor.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.assessment_outlined,  // ✨ 아웃라인 스타일
                  color: theme.primaryColor,
                  size: ResponsiveHelper.iconSize(context, 24),
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
          
          // ✨ 통계 그리드
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildStatItem(
                label: '확정 인원',
                value: '$total명',
                icon: Icons.people_outline,  // ✨ 아웃라인
                color: Colors.blue,
              ),
              _buildStatItem(
                label: '출근 완료',
                value: '$checkedIn명',
                subValue: '($checkedInPercentage%)',
                icon: Icons.check_circle_outline,  // ✨ 아웃라인
                color: Colors.green,
              ),
              _buildStatItem(
                label: '미출근',
                value: '$notCheckedIn명',
                icon: Icons.schedule_outlined,  // ✨ 아웃라인
                color: Colors.orange,
              ),
              _buildStatItem(
                label: '퇴근 완료',
                value: '$checkedOut명',
                icon: Icons.home_outlined,  // ✨ 아웃라인
                color: Colors.purple,
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// ✨ 통계 아이템 (세련된 스타일) - 고정 높이
  Widget _buildStatItem({
    required String label,
    required String value,
    String? subValue,
    required IconData icon,
    required MaterialColor color,
  }) {
    return SizedBox(
      height: ResponsiveHelper.spacing(context, 120),  // ✨ 고정 높이
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,  // ✨ 중앙 정렬
        children: [
          // ✨ 아이콘 배경
          Container(
            padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 10)),
            decoration: BoxDecoration(
              color: color[50],
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: color[200]!,
                width: 1.5,
              ),
            ),
            child: Icon(
              icon, 
              color: color[600], 
              size: ResponsiveHelper.iconSize(context, 26),
            ),
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 8)),
          Text(
            label,
            style: ResponsiveHelper.tinyStyle(
              context,
              color: Colors.grey[600],
            ).copyWith(
              fontWeight: FontWeight.w500,
            ),
            textAlign: TextAlign.center,
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 4)),
          Text(
            value,
            style: ResponsiveHelper.bodyStyle(context).copyWith(
              fontWeight: FontWeight.bold,
              fontSize: ResponsiveHelper.bodyStyle(context).fontSize! * 1.1,
              color: color[700],
            ),
          ),
          // ✨ 서브텍스트 공간 확보 (없어도 공간 유지)
          SizedBox(
            height: ResponsiveHelper.spacing(context, 16),
            child: subValue != null
                ? Text(
                    subValue,
                    style: ResponsiveHelper.tinyStyle(
                      context,
                      color: color[600],
                    ).copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  /// ✨ 업무별 그룹
  Widget _buildWorkTypeGroups() {
    final theme = Theme.of(context);
    
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
          padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 40)),
          child: Column(
            children: [
              Icon(
                Icons.inbox_outlined,  // ✨ 아웃라인 스타일
                size: ResponsiveHelper.iconSize(context, 48),
                color: Colors.grey[400],
              ),
              SizedBox(height: ResponsiveHelper.spacing(context, 16)),
              Text(
                '확정된 근무자가 없습니다',
                style: ResponsiveHelper.bodyStyle(
                  context,
                  color: Colors.grey[600],
                ).copyWith(
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: workTypeGroups.entries.map((entry) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: ResponsiveHelper.spacing(context, 16),
          ),
          child: _buildWorkTypeGroup(entry.key, entry.value),
        );
      }).toList(),
    );
  }

  /// ✨ 업무 유형 그룹 (세련된 카드)
  Widget _buildWorkTypeGroup(String workType, List<ApplicationModel> workers) {
    final theme = Theme.of(context);
    
    return Container(
      padding: ResponsiveHelper.cardPadding(context),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.grey[200]!,
          width: 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ✨ 업무 유형 헤더
          Row(
            children: [
              Container(
                padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 8)),
                decoration: BoxDecoration(
                  color: theme.primaryColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.work_outline,  // ✨ 아웃라인 스타일
                  color: theme.primaryColor,
                  size: ResponsiveHelper.iconSize(context, 20),
                ),
              ),
              SizedBox(width: ResponsiveHelper.spacing(context, 12)),
              Text(
                workType,
                style: ResponsiveHelper.bodyStyle(context).copyWith(
                  fontWeight: FontWeight.bold,
                  fontSize: ResponsiveHelper.bodyStyle(context).fontSize! * 1.05,
                ),
              ),
              SizedBox(width: ResponsiveHelper.spacing(context, 8)),
              Container(
                padding: EdgeInsets.symmetric(
                  horizontal: ResponsiveHelper.spacing(context, 8),
                  vertical: ResponsiveHelper.spacing(context, 4),
                ),
                decoration: BoxDecoration(
                  color: theme.primaryColor,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${workers.length}명',
                  style: ResponsiveHelper.smallStyle(
                    context,
                    color: Colors.white,
                  ).copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 16)),

          // 근무자 목록
          ...workers.map((app) => _buildWorkerItem(app)),
        ],
      ),
    );
  }

  /// ✨ 근무자 아이템 (2줄 레이아웃 + 탭 가능)
  Widget _buildWorkerItem(ApplicationModel app) {
    final theme = Theme.of(context);
    final attendance = _attendanceMap[app.id];
    final hasCheckedIn = attendance?.checkIn != null;
    final hasCheckedOut = attendance?.checkOut != null;

    // ✨ 모든 상태에서 사람 아이콘 사용
    const IconData icon = Icons.person_outline;
    Color iconColor;
    String statusText;
    String? timeText;

    if (hasCheckedOut) {
      iconColor = Colors.purple;
      statusText = '퇴근';
      timeText = '${attendance!.checkIn} ~ ${attendance.checkOut}';
    } else if (hasCheckedIn) {
      iconColor = Colors.green;
      statusText = '출근';
      timeText = attendance!.checkIn;
    } else {
      iconColor = Colors.orange;
      statusText = '미출근';
      timeText = null;
    }

    return InkWell(  // ✨ 탭 가능하게 변경
      onTap: () => _showWorkerDetailDialog(app, attendance),  // ✨ 상세 팝업
      borderRadius: BorderRadius.circular(12),
      child: Container(
        margin: EdgeInsets.only(
          bottom: ResponsiveHelper.spacing(context, 8),  // ✨ 10 → 8
        ),
        padding: EdgeInsets.symmetric(  // ✨ cardPadding 대신 세밀한 조정
          horizontal: ResponsiveHelper.spacing(context, 14),
          vertical: ResponsiveHelper.spacing(context, 12),  // ✨ 상하 패딩 줄임
        ),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: Colors.grey[200]!,
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.03),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,  // ✨ 상단 정렬
          children: [
            // ✨ 상태 아이콘 배경 (크기 증가)
            Container(
              padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 12)),  // ✨ 10 → 12
              decoration: BoxDecoration(
                gradient: LinearGradient(  // ✨ 그라데이션 추가
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    iconColor.withOpacity(0.15),
                    iconColor.withOpacity(0.08),
                  ],
                ),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: iconColor.withOpacity(0.4),  // ✨ 0.3 → 0.4
                  width: 2,  // ✨ 1.5 → 2
                ),
              ),
              child: Icon(
                icon, 
                color: iconColor, 
                size: ResponsiveHelper.iconSize(context, 26),  // ✨ 22 → 26
              ),
            ),
            SizedBox(width: ResponsiveHelper.spacing(context, 12)),
            
            // ✨ 2줄 레이아웃
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 첫째 줄: 이름(나이,성별) + 근무유형 배지
                  Row(
                    children: [
                      // 이름 (Expanded로 말줄임 처리)
                      Expanded(
                        child: Text(
                          _buildUserNameWithInfo(app.uid),
                          style: ResponsiveHelper.bodyStyle(context).copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                          overflow: TextOverflow.ellipsis,  // ✨ 말줄임
                          maxLines: 1,
                        ),
                      ),
                      SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                      
                      // ✨ 근무 유형 배지
                      Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: ResponsiveHelper.spacing(context, 8),
                          vertical: ResponsiveHelper.spacing(context, 3),
                        ),
                        decoration: BoxDecoration(
                          color: app.isLongTermApplication
                              ? Colors.purple[50]
                              : theme.primaryColor.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: app.isLongTermApplication
                                ? Colors.purple[200]!
                                : theme.primaryColor.withOpacity(0.3),
                            width: 1,
                          ),
                        ),
                        child: Text(
                          app.isLongTermApplication ? '장기' : '단기',
                          style: ResponsiveHelper.tinyStyle(
                            context,
                            color: app.isLongTermApplication
                                ? Colors.purple[700]
                                : theme.primaryColor,
                          ).copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  
                  // 둘째 줄: [시계] 시간 + [미출근] 배지 (좌우 균형)
                  SizedBox(height: ResponsiveHelper.spacing(context, 8)),
                  Row(
                    children: [
                      // 시계 아이콘 (크기 증가)
                      Icon(
                        Icons.access_time_outlined,
                        size: ResponsiveHelper.iconSize(context, 16),  // ✨ 14 → 16
                        color: Colors.grey[600],
                      ),
                      SizedBox(width: ResponsiveHelper.spacing(context, 6)),  // ✨ 4 → 6
                      
                      // 시간 텍스트 (크기 증가)
                      Text(
                        timeText ?? '--:--',
                        style: ResponsiveHelper.bodyStyle(  // ✨ smallStyle → bodyStyle
                          context,
                          color: Colors.grey[700],  // ✨ 600 → 700 (더 진하게)
                        ).copyWith(
                          fontWeight: FontWeight.w600,  // ✨ w500 → w600
                        ),
                      ),
                      
                      const Spacer(),  // ✨ 공간 밀어내기
                      
                      // ✨ 상태 배지 (오른쪽)
                      Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: ResponsiveHelper.spacing(context, 12),  // ✨ 10 → 12
                          vertical: ResponsiveHelper.spacing(context, 6),  // ✨ 5 → 6
                        ),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(  // ✨ 그라데이션 추가
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              iconColor.withOpacity(0.2),
                              iconColor.withOpacity(0.12),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(10),  // ✨ 8 → 10
                          border: Border.all(
                            color: iconColor.withOpacity(0.4),  // ✨ 0.3 → 0.4
                            width: 1.5,
                          ),
                        ),
                        child: Text(
                          statusText,
                          style: ResponsiveHelper.smallStyle(
                            context,
                            fontWeight: FontWeight.bold,
                            color: iconColor,  // ✨ iconColor[700] → iconColor
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// ✨ 근무자 상세 정보 팝업
  Future<void> _showWorkerDetailDialog(ApplicationModel app, AttendanceModel? attendance) async {
    final theme = Theme.of(context);
    final detail = _userDetailMap[app.uid];
    
    if (detail == null) {
      ToastHelper.showError('사용자 정보를 불러올 수 없습니다');
      return;
    }

    // ✨ WorkDetail에서 근무시간 조회
    String workStartTime = app.startTime;
    String workEndTime = app.endTime;
    
    // 비어있으면 WorkDetail에서 조회
    if (workStartTime.isEmpty || workEndTime.isEmpty) {
      try {
        // TO 찾기
        final toQuery = await FirebaseFirestore.instance
            .collection('tos')
            .where('businessId', isEqualTo: app.businessId)
            .where('title', isEqualTo: app.toTitle)
            .where('date', isEqualTo: Timestamp.fromDate(app.workDate))
            .limit(1)
            .get();
        
        if (toQuery.docs.isNotEmpty) {
          final toId = toQuery.docs.first.id;
          
          // WorkDetail 조회
          final workDetails = await FirebaseFirestore.instance
              .collection('tos')
              .doc(toId)
              .collection('workDetails')
              .where('workType', isEqualTo: app.selectedWorkType)
              .limit(1)
              .get();
          
          if (workDetails.docs.isNotEmpty) {
            final workData = workDetails.docs.first.data();
            workStartTime = workData['startTime'] ?? '--:--';
            workEndTime = workData['endTime'] ?? '--:--';
          }
        }
      } catch (e) {
        print('❌ WorkDetail 조회 실패: $e');
      }
    }

    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 500, maxHeight: 600),
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
              // ✨ 그라데이션 헤더
              Container(
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
                child: Row(
                  children: [
                    Container(
                      padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 10)),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        Icons.person_outline,
                        color: Colors.white,
                        size: ResponsiveHelper.iconSize(context, 28),
                      ),
                    ),
                    SizedBox(width: ResponsiveHelper.spacing(context, 12)),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '근무자 상세정보',
                            style: ResponsiveHelper.titleStyle(context).copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          SizedBox(height: ResponsiveHelper.spacing(context, 4)),
                          Text(
                            detail['name'] as String,
                            style: ResponsiveHelper.bodyStyle(
                              context,
                              color: Colors.white.withOpacity(0.9),
                            ),
                          ),
                        ],
                      ),
                    ),
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
              ),

              // ✨ 내용
              Expanded(
                child: SingleChildScrollView(
                  padding: ResponsiveHelper.cardPadding(context),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 기본 정보
                      _buildDetailSection(
                        title: '기본 정보',
                        icon: Icons.person_outline,
                        children: [
                          _buildDetailRow('이름', detail['name'] as String),
                          _buildDetailRow('성별', detail['gender'] as String? ?? '-'),
                          _buildDetailRow('나이', detail['age'] != null ? '${detail['age']}세' : '-'),
                          _buildDetailRow('연락처', detail['phone'] as String? ?? '-'),
                        ],
                      ),

                      SizedBox(height: ResponsiveHelper.spacing(context, 20)),

                      // 근무 정보
                      _buildDetailSection(
                        title: '근무 정보',
                        icon: Icons.work_outline,
                        children: [
                          _buildDetailRow('업무 유형', app.selectedWorkType),
                          _buildDetailRow(
                            '근무 시간',
                            '$workStartTime ~ $workEndTime',  // ✨ 조회한 시간 사용
                          ),
                          if (attendance?.checkIn != null)
                            _buildDetailRow('출근 시각', attendance!.checkIn!),
                          if (attendance?.checkOut != null)
                            _buildDetailRow('퇴근 시각', attendance!.checkOut!),
                        ],
                      ),

                      SizedBox(height: ResponsiveHelper.spacing(context, 20)),

                      // 평가 & 이력
                      _buildDetailSection(
                        title: '평가 & 이력',
                        icon: Icons.star_outline,
                        children: [
                          _buildDetailRow(
                            '평점',
                            '${(detail['averageRating'] as double).toStringAsFixed(1)} / 5.0 ⭐',
                          ),
                          _buildDetailRow(
                            '리뷰 수',
                            '${detail['reviewCount']}개',
                          ),
                          _buildDetailRow(
                            '총 근무 일수',
                            '${detail['totalWorkDays']}일',
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

              // ✨ 하단 버튼
              Container(
                padding: ResponsiveHelper.cardPadding(context),
                decoration: BoxDecoration(
                  color: Colors.grey[50],
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(24),
                    bottomRight: Radius.circular(24),
                  ),
                  border: Border(
                    top: BorderSide(color: theme.dividerColor),
                  ),
                ),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: theme.primaryColor,
                      foregroundColor: Colors.white,
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
      ),
    );
  }

  /// ✨ 상세 정보 섹션
  Widget _buildDetailSection({
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    final theme = Theme.of(context);
    
    return Container(
      padding: ResponsiveHelper.cardPadding(context),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.grey[200]!,
          width: 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 8)),
                decoration: BoxDecoration(
                  color: theme.primaryColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  icon,
                  color: theme.primaryColor,
                  size: ResponsiveHelper.iconSize(context, 20),
                ),
              ),
              SizedBox(width: ResponsiveHelper.spacing(context, 12)),
              Text(
                title,
                style: ResponsiveHelper.subtitleStyle(context).copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 16)),
          ...children,
        ],
      ),
    );
  }

  /// ✨ 상세 정보 행
  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: ResponsiveHelper.spacing(context, 12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: ResponsiveHelper.spacing(context, 100),
            child: Text(
              label,
              style: ResponsiveHelper.bodyStyle(
                context,
                color: Colors.grey[600],
              ).copyWith(
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: ResponsiveHelper.bodyStyle(context).copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}