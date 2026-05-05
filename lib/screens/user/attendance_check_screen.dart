import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../models/core/application_model.dart';
import '../../models/core/attendance_model.dart';
import '../../widgets/common/loading_button.dart';
import '../../services/firestore_service.dart';
import '../../providers/user_provider.dart';
import '../../utils/location_helper.dart';
import '../../utils/toast_helper.dart';
import '../../utils/dialog_helper.dart';
import '../../utils/responsive_helper.dart';
import '../../theme/app_colors.dart';
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
  final Map<String, AttendanceModel?> _attendanceMap = {};
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

      final allApplications = await _firestoreService.getMyApplications(uid);

      final today = DateTime.now();
      final todayStart = DateTime(today.year, today.month, today.day);
      final todayWorks = <ApplicationModel>[];

      for (final app in allApplications) {
        if (app.status != 'CONFIRMED') continue;

        final isReallyLongTerm = app.workDays != null && app.workDays!.isNotEmpty;

        if (!isReallyLongTerm) {
          if (DateUtils.isSameDay(app.workDate, todayStart)) {
            todayWorks.add(app);
          }
          continue;
        }

        if (app.workEndDate == null) continue;

        final effectiveStartDate = app.desiredStartDate ?? app.workDate;
        final startDateOnly = DateTime(
          effectiveStartDate.year,
          effectiveStartDate.month,
          effectiveStartDate.day,
        );
        final endDateOnly = DateTime(
          app.workEndDate!.year,
          app.workEndDate!.month,
          app.workEndDate!.day,
        );

        if (todayStart.isBefore(startDateOnly) || todayStart.isAfter(endDateOnly)) {
          continue;
        }

        final weekdays = ['월', '화', '수', '목', '금', '토', '일'];
        final todayWeekday = weekdays[today.weekday - 1];

        if (app.workDays!.contains(todayWeekday)) {
          todayWorks.add(app);
        }
      }

      // 각 근무의 출근 기록 병렬 조회 (성능 개선)
      await Future.wait(
        todayWorks.map((work) async {
          final attendance = await _firestoreService.getTodayAttendance(
            userId: uid,
            applicationId: work.id,
          );
          _attendanceMap[work.id] = attendance;
        }),
      );

      if (mounted) {
        setState(() {
          _todayWorks = todayWorks;
          _isLoading = false;
        });
      }

      debugPrint('✅ 오늘 근무: ${todayWorks.length}개');
    } catch (e) {
      debugPrint('❌ 오늘 근무 조회 실패: $e');
      if (mounted) {
        setState(() => _isLoading = false);
        ToastHelper.showError('근무 정보를 불러오는데 실패했습니다.');
      }
    }
  }

  /// 출근 체크
  Future<void> _checkIn(ApplicationModel work) async {
    if (_isProcessing) return;
    setState(() => _isProcessing = true);

    try {
      final hasPermission = await LocationHelper.checkAndRequestPermission();
      if (!hasPermission) {
        if (mounted) {
          await DialogHelper.showError(
            context,
            title: '위치 권한 필요',
            message: '출퇴근 체크를 위해 위치 권한이 필요합니다.\n설정에서 권한을 허용해주세요.',
          );
        }
        return;
      }

      if (mounted) DialogHelper.showLoading(context, message: 'GPS 확인 중...');

      final position = await LocationHelper.getCurrentPosition();

      if (!mounted) return;
      Navigator.pop(context); // 로딩 닫기

      if (position == null) {
        await DialogHelper.showError(
          context,
          message: 'GPS 위치를 가져올 수 없습니다.\n잠시 후 다시 시도해주세요.',
        );
        return;
      }

      final business = await _firestoreService.getBusinessById(work.businessId);
      if (business == null) {
        if (mounted) {
          await DialogHelper.showError(context, message: '사업장 정보를 찾을 수 없습니다.');
        }
        return;
      }

      final gpsRadius = business.gpsRadius.toDouble();

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
        if (mounted) {
          await DialogHelper.showError(
            context,
            title: '출근 위치 오류',
            message: '사업장에서 너무 멉니다.\n'
                '현재 거리: ${LocationHelper.formatDistance(distance)}\n'
                '사업장 근처(${gpsRadius.toInt()}m 이내)에서 출근해주세요.',
          );
        }
        return;
      }

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

      if (attendanceId != null && mounted) {
        ToastHelper.showSuccess('출근이 완료되었습니다!');
        await _loadTodayWorks();
      }
    } catch (e) {
      debugPrint('❌ 출근 체크 실패: $e');
      if (mounted) {
        await DialogHelper.showError(
          context,
          message: e.toString().replaceAll('Exception: ', ''),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  /// 퇴근 체크
  Future<void> _checkOut(ApplicationModel work, AttendanceModel attendance) async {
    if (_isProcessing) return;

    final confirmed = await DialogHelper.showConfirm(
      context,
      title: '퇴근 확인',
      message: '퇴근 처리하시겠습니까?',
      confirmText: '퇴근',
    );
    if (!confirmed) return;

    setState(() => _isProcessing = true);

    try {
      if (mounted) DialogHelper.showLoading(context, message: 'GPS 확인 중...');

      final position = await LocationHelper.getCurrentPosition();

      if (!mounted) return;
      Navigator.pop(context);

      if (position == null) {
        await DialogHelper.showError(
          context,
          message: 'GPS 위치를 가져올 수 없습니다.',
        );
        return;
      }

      final success = await _firestoreService.checkOut(
        attendanceId: attendance.id,
        latitude: position.latitude,
        longitude: position.longitude,
        method: 'gps',
      );

      if (success && mounted) {
        ToastHelper.showSuccess('퇴근이 완료되었습니다!');
        await _loadTodayWorks();
      }
    } catch (e) {
      debugPrint('❌ 퇴근 체크 실패: $e');
      if (mounted) {
        await DialogHelper.showError(
          context,
          message: e.toString().replaceAll('Exception: ', ''),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          '출퇴근 체크',
          style: ResponsiveHelper.subtitleStyle(context).copyWith(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: theme.primaryColor,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: Icon(
              Icons.refresh,
              size: ResponsiveHelper.iconSize(context, 24),
            ),
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
                    padding: ResponsiveHelper.cardPadding(context),
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
          Icon(
            Icons.event_busy,
            size: ResponsiveHelper.iconSize(context, 80),
            color: AppColors.grey300,
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 16)),
          Text(
            '오늘 확정된 근무가 없습니다',
            style: ResponsiveHelper.bodyStyle(context, color: AppColors.grey600),
          ),
        ],
      ),
    );
  }

  /// 근무 카드
  Widget _buildWorkCard(ApplicationModel work, AttendanceModel? attendance) {
    final hasCheckedIn = attendance?.hasCheckedIn ?? false;
    final hasCheckedOut = attendance?.hasCheckedOut ?? false;
    final theme = Theme.of(context);

    return Card(
      margin: EdgeInsets.only(bottom: ResponsiveHelper.spacing(context, 16)),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      elevation: 2,
      shadowColor: Colors.black.withOpacity(0.08),
      child: Padding(
        padding: ResponsiveHelper.cardPadding(context),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 사업장 정보
            Row(
              children: [
                // 단기/장기 배지
                Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: ResponsiveHelper.spacing(context, 8),
                    vertical: ResponsiveHelper.spacing(context, 4),
                  ),
                  decoration: BoxDecoration(
                    color: work.isLongTermApplication
                        ? AppColors.longTermBg
                        : AppColors.shortTermBg,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    work.isLongTermApplication ? '장기' : '단기',
                    style: ResponsiveHelper.smallStyle(context).copyWith(
                      fontWeight: FontWeight.bold,
                      color: work.isLongTermApplication
                          ? AppColors.longTermDark
                          : AppColors.shortTermDark,
                    ),
                  ),
                ),
                SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                Expanded(
                  child: Text(
                    work.businessName,
                    style: ResponsiveHelper.subtitleStyle(context).copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),

            SizedBox(height: ResponsiveHelper.spacing(context, 12)),

            // 근무 정보
            _buildInfoRow(Icons.work_outline, work.selectedWorkType),
            SizedBox(height: ResponsiveHelper.spacing(context, 4)),
            _buildInfoRow(
              Icons.access_time,
              '${work.startTime} ~ ${work.endTime}',
            ),
            SizedBox(height: ResponsiveHelper.spacing(context, 4)),
            _buildInfoRow(
              Icons.payments_outlined,
              '${NumberFormat('#,###').format(work.wage)}원/시간',
            ),

            Divider(
              height: ResponsiveHelper.spacing(context, 24),
              color: AppColors.dividerLight,
            ),

            // 출근 상태 정보
            if (hasCheckedIn) ...[
              _buildAttendanceInfo(attendance!),
              SizedBox(height: ResponsiveHelper.spacing(context, 12)),
            ],

            // 출근/퇴근 버튼
            if (!hasCheckedIn)
              LoadingButton.primary(
                text: '출근하기',
                icon: Icons.login,
                expand: true,
                isLoading: _isProcessing,
                onPressed: () async => await _checkIn(work),
              )
            else if (!hasCheckedOut)
              LoadingButton(
                text: '퇴근하기',
                icon: Icons.logout,
                expand: true,
                backgroundColor: AppColors.warningDark,
                isLoading: _isProcessing,
                onPressed: () async => await _checkOut(work, attendance!),
              )
            else
              Container(
                width: double.infinity,
                padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 12)),
                decoration: BoxDecoration(
                  color: AppColors.successBg,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.successLight),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.check_circle,
                      color: AppColors.successDark,
                      size: ResponsiveHelper.iconSize(context, 20),
                    ),
                    SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                    Text(
                      '출퇴근 완료',
                      style: ResponsiveHelper.bodyStyle(context).copyWith(
                        fontWeight: FontWeight.bold,
                        color: AppColors.successDark,
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
        Icon(
          icon,
          size: ResponsiveHelper.iconSize(context, 16),
          color: AppColors.grey600,
        ),
        SizedBox(width: ResponsiveHelper.spacing(context, 8)),
        Text(
          text,
          style: ResponsiveHelper.bodyStyle(context, color: AppColors.grey700),
        ),
      ],
    );
  }

  /// 출근 정보 카드
  Widget _buildAttendanceInfo(AttendanceModel attendance) {
    return Container(
      padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 12)),
      decoration: BoxDecoration(
        color: AppColors.infoBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.infoLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.check_circle,
                color: AppColors.infoDark,
                size: ResponsiveHelper.iconSize(context, 20),
              ),
              SizedBox(width: ResponsiveHelper.spacing(context, 8)),
              Text(
                '출근 완료',
                style: ResponsiveHelper.bodyStyle(context).copyWith(
                  fontWeight: FontWeight.bold,
                  color: AppColors.infoDark,
                ),
              ),
            ],
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 8)),
          Text(
            '출근 시각: ${attendance.checkIn}',
            style: ResponsiveHelper.smallStyle(context, color: AppColors.grey700),
          ),
          if (attendance.hasCheckedOut) ...[
            SizedBox(height: ResponsiveHelper.spacing(context, 4)),
            Text(
              '퇴근 시각: ${attendance.checkOut}',
              style: ResponsiveHelper.smallStyle(context, color: AppColors.grey700),
            ),
            SizedBox(height: ResponsiveHelper.spacing(context, 4)),
            Text(
              '근무 시간: ${attendance.workHours?.toStringAsFixed(1) ?? '-'}시간',
              style: ResponsiveHelper.smallStyle(context).copyWith(
                fontWeight: FontWeight.bold,
                color: AppColors.grey800,
              ),
            ),
          ],
        ],
      ),
    );
  }
}