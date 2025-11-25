
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../models/core/application_model.dart';
import '../../models/core/attendance_model.dart';
import '../../models/core/business_model.dart';
import '../../services/firestore_service.dart';
import '../../providers/user_provider.dart';
import '../../utils/location_helper.dart';
import '../../utils/toast_helper.dart';
import '../../utils/dialog_helper.dart';
import '../../widgets/common/loading_widget.dart';

/// 출퇴근 체크 화면
class AttendanceCheckScreen extends StatefulWidget {
  const AttendanceCheckScreen({super.key});

  @override
  State<AttendanceCheckScreen> createState() => _AttendanceCheckScreenState();
}

class _AttendanceCheckScreenState extends State<AttendanceCheckScreen> {
  final FirestoreService _firestoreService = FirestoreService();
  
  List<ApplicationModel> _todayWorks = [];
  final Map<String, AttendanceModel?> _attendanceMap = {}; // applicationId -> AttendanceModel
  bool _isLoading = true;
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    _loadTodayWorks();
  }

  /// 오늘 확정된 근무 조회
  Future<void> _loadTodayWorks() async {
    setState(() => _isLoading = true);

    try {
      final userProvider = Provider.of<UserProvider>(context, listen: false);
      final uid = userProvider.currentUser?.uid;

      if (uid == null) {
        ToastHelper.showError('로그인이 필요합니다.');
        return;
      }

      // 1. 내 전체 지원 내역 조회
      final allApplications = await _firestoreService.getMyApplications(uid);
      
      // 2. 오늘 확정된 근무만 필터링
      final today = DateTime.now();
      final todayStart = DateTime(today.year, today.month, today.day);
      
      final todayWorks = allApplications.where((app) {
        if (app.status != 'CONFIRMED') return false;
        
        // 단기 근무
        if (!app.isLongTermApplication) {
          return DateUtils.isSameDay(app.workDate, todayStart);
        }

        
        // 장기 근무
        if (app.isLongTermApplication && app.workEndDate != null) {
          // 기간 체크
          if (todayStart.isBefore(app.workDate) || todayStart.isAfter(app.workEndDate!)) {
            return false;
          }
          
          // 요일 체크
          if (app.workDays != null && app.workDays!.isNotEmpty) {
            final weekdays = ['월', '화', '수', '목', '금', '토', '일'];
            final todayWeekday = weekdays[today.weekday - 1];
            return app.workDays!.contains(todayWeekday);
          }
          
          return true;
        }
        
        return false;
      }).toList();

      // 3. 각 근무의 출근 기록 조회
      for (var work in todayWorks) {
        final attendance = await _firestoreService.getTodayAttendance(
          userId: uid,
          applicationId: work.id,
        );
        _attendanceMap[work.id] = attendance;
      }

      setState(() {
        _todayWorks = todayWorks;
        _isLoading = false;
      });

      print('✅ 오늘 근무: ${todayWorks.length}개');
    } catch (e) {
      print('❌ 오늘 근무 조회 실패: $e');
      setState(() => _isLoading = false);
      ToastHelper.showError('근무 정보를 불러오는데 실패했습니다.');
    }
  }

  /// 출근 체크
  Future<void> _checkIn(ApplicationModel work) async {
    if (_isProcessing) return;

    setState(() => _isProcessing = true);

    try {
      // 1. GPS 권한 확인
      final hasPermission = await LocationHelper.checkAndRequestPermission();
      if (!hasPermission) {
        await DialogHelper.showError(
          context,
          title: '위치 권한 필요',
          message: '출퇴근 체크를 위해 위치 권한이 필요합니다.\n설정에서 권한을 허용해주세요.',
        );
        setState(() => _isProcessing = false);
        return;
      }

      // 2. 현재 위치 가져오기
      DialogHelper.showLoading(context, message: 'GPS 확인 중...');
      
      final position = await LocationHelper.getCurrentPosition();
      
      if (!mounted) return;
      Navigator.pop(context); // 로딩 닫기

      if (position == null) {
        await DialogHelper.showError(
          context,
          message: 'GPS 위치를 가져올 수 없습니다.\n잠시 후 다시 시도해주세요.',
        );
        setState(() => _isProcessing = false);
        return;
      }

      // 3. 사업장 정보 조회
      final business = await _firestoreService.getBusinessById(work.businessId);
      if (business == null) {
        await DialogHelper.showError(context, message: '사업장 정보를 찾을 수 없습니다.');
        setState(() => _isProcessing = false);
        return;
      }
      // ⭐ GPS 반경 설정 (사업장별 또는 기본값 100m)
      final gpsRadius = business.gpsRadius.toDouble();

      // 4. 거리 확인 (100m 반경)
      final isNearby = LocationHelper.isWithinRadius(
        currentLat: position.latitude,
        currentLon: position.longitude,
        businessLat: business.latitude ?? 0.0,
        businessLon: business.longitude ?? 0.0,
        radiusInMeters: gpsRadius,
      );

      if (!isNearby) {
      final distance = LocationHelper.calculateDistance(
        lat1: position.latitude,
        lon1: position.longitude,
        lat2: business.latitude ?? 0.0,
        lon2: business.longitude ?? 0.0,
      );
        
        await DialogHelper.showError(
          context,
          title: '출근 위치 오류',
          message: '사업장에서 너무 멉니다.\n'
              '현재 거리: ${LocationHelper.formatDistance(distance)}\n'
              '사업장 근처(${gpsRadius.toInt()}m 이내)에서 출근해주세요.', 
        );
        setState(() => _isProcessing = false);
        return;
      }

      // 5. 출근 체크
      final userProvider = Provider.of<UserProvider>(context, listen: false);
      final uid = userProvider.currentUser?.uid;

      final attendanceId = await _firestoreService.checkIn(
        applicationId: work.id,
        userId: uid!,
        businessId: work.businessId,
        businessName: work.businessName,
        workDate: DateTime.now(),
        workType: work.selectedWorkType,
        latitude: position.latitude,
        longitude: position.longitude,
        method: 'gps',
      );

      if (attendanceId != null) {
        ToastHelper.showSuccess('출근이 완료되었습니다!');
        await _loadTodayWorks(); // 새로고침
      }
    } catch (e) {
      print('❌ 출근 체크 실패: $e');
      if (mounted) {
        await DialogHelper.showError(
          context,
          message: e.toString().replaceAll('Exception: ', ''),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  /// 퇴근 체크
  Future<void> _checkOut(ApplicationModel work, AttendanceModel attendance) async {
    if (_isProcessing) return;

    // 확인 다이얼로그
    final confirmed = await DialogHelper.showConfirm(
      context,
      title: '퇴근 확인',
      message: '퇴근 처리하시겠습니까?',
      confirmText: '퇴근',
    );

    if (!confirmed) return;

    setState(() => _isProcessing = true);

    try {
      // 1. 현재 위치 가져오기
      DialogHelper.showLoading(context, message: 'GPS 확인 중...');
      
      final position = await LocationHelper.getCurrentPosition();
      
      if (!mounted) return;
      Navigator.pop(context);

      if (position == null) {
        await DialogHelper.showError(
          context,
          message: 'GPS 위치를 가져올 수 없습니다.',
        );
        setState(() => _isProcessing = false);
        return;
      }

      // 2. 퇴근 체크
      final success = await _firestoreService.checkOut(
        attendanceId: attendance.id,
        latitude: position.latitude,
        longitude: position.longitude,
        method: 'gps',
      );

      if (success) {
        ToastHelper.showSuccess('퇴근이 완료되었습니다!');
        await _loadTodayWorks();
      }
    } catch (e) {
      print('❌ 퇴근 체크 실패: $e');
      if (mounted) {
        await DialogHelper.showError(
          context,
          message: e.toString().replaceAll('Exception: ', ''),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('출퇴근 체크'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadTodayWorks,
          ),
        ],
      ),
      body: _isLoading
          ? const LoadingWidget(message: '근무 정보를 불러오는 중...')
          : _todayWorks.isEmpty
              ? _buildEmptyState()
              : RefreshIndicator(
                  onRefresh: _loadTodayWorks,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _todayWorks.length,
                    itemBuilder: (context, index) {
                      final work = _todayWorks[index];
                      final attendance = _attendanceMap[work.id];
                      return _buildWorkCard(work, attendance);
                    },
                  ),
                ),
    );
  }

  /// 빈 상태
  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.event_busy, size: 80, color: Colors.grey[300]),
          const SizedBox(height: 16),
          Text(
            '오늘 확정된 근무가 없습니다',
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }

  /// 근무 카드
  Widget _buildWorkCard(ApplicationModel work, AttendanceModel? attendance) {
    final hasCheckedIn = attendance?.hasCheckedIn ?? false;
    final hasCheckedOut = attendance?.hasCheckedOut ?? false;

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 사업장 정보
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Theme.of(context).primaryColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    work.isLongTermApplication ? '장기' : '단기',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).primaryColor,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    work.businessName,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // 근무 정보
            _buildInfoRow(Icons.work, work.selectedWorkType),
            const SizedBox(height: 4),
            _buildInfoRow(
              Icons.access_time,
              '${work.startTime} ~ ${work.endTime}',
            ),
            const SizedBox(height: 4),
            _buildInfoRow(
              Icons.payments,
              '${NumberFormat('#,###').format(work.wage)}원/시간',
            ),

            const Divider(height: 24),

            // 출근 상태
            if (hasCheckedIn) ...[
              _buildAttendanceInfo(attendance!),
              const SizedBox(height: 12),
            ],

            // 출근/퇴근 버튼
            if (!hasCheckedIn)
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _isProcessing ? null : () => _checkIn(work),
                  icon: const Icon(Icons.login),
                  label: const Text('출근하기'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
              )
            else if (!hasCheckedOut)
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _isProcessing ? null : () => _checkOut(work, attendance!),
                  icon: const Icon(Icons.logout),
                  label: const Text('퇴근하기'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange[700],
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
              )
            else
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.green[200]!),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.check_circle, color: Colors.green[700]),
                    const SizedBox(width: 8),
                    Text(
                      '출퇴근 완료',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.green[700],
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// 정보 행
  Widget _buildInfoRow(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 16, color: Colors.grey[600]),
        const SizedBox(width: 8),
        Text(
          text,
          style: TextStyle(
            fontSize: 14,
            color: Colors.grey[700],
          ),
        ),
      ],
    );
  }

  /// 출근 정보
  Widget _buildAttendanceInfo(AttendanceModel attendance) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.blue[50],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.blue[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.check_circle, color: Colors.blue[700], size: 20),
              const SizedBox(width: 8),
              Text(
                '출근 완료',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Colors.blue[700],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '출근 시각: ${attendance.checkIn}',
            style: const TextStyle(fontSize: 13),
          ),
          if (attendance.hasCheckedOut) ...[
            const SizedBox(height: 4),
            Text(
              '퇴근 시각: ${attendance.checkOut}',
              style: const TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 4),
            Text(
              '근무 시간: ${attendance.workHours?.toStringAsFixed(1) ?? '-'}시간',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ],
      ),
    );
  }
}