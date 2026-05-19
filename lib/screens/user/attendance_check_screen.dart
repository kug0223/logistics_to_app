import 'dart:async';
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
import '../../utils/format_helper.dart';
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

  // 위치 추적
  bool _locationTrackingActive = false;
  bool _bannerDismissed = false;
  Timer? _locationTimer;
  final Map<String, double?> _businessLat = {};
  final Map<String, double?> _businessLng = {};

  @override
  void initState() {
    super.initState();
    _loadTodayWorks();
  }

  @override
  void dispose() {
    _locationTimer?.cancel();
    super.dispose();
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

        final todayWeekday = FormatHelper.weekday(today);

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
      _checkAndStartTracking();
    } catch (e) {
      debugPrint('❌ 오늘 근무 조회 실패: $e');
      if (mounted) {
        setState(() => _isLoading = false);
        ToastHelper.showError('근무 정보를 불러오는데 실패했습니다.');
      }
    }
  }

  // ─────────────────────────────────────────────────────────
  // 위치 추적
  // ─────────────────────────────────────────────────────────

  /// 예정 출근 60분 전 ~ 출근 완료 전 구간인지 확인
  bool _isInTrackingWindow(ApplicationModel work) {
    if (work.startTime.isEmpty) return false;
    final parts = work.startTime.split(':');
    if (parts.length < 2) return false;
    final now = DateTime.now();
    final scheduledStart = DateTime(
      now.year, now.month, now.day,
      int.tryParse(parts[0]) ?? 0,
      int.tryParse(parts[1]) ?? 0,
    );
    final windowStart = scheduledStart.subtract(const Duration(minutes: 60));
    final windowEnd = scheduledStart.add(const Duration(hours: 2));
    return now.isAfter(windowStart) && now.isBefore(windowEnd);
  }

  /// 로드 후 / 체크인 후 호출 — 추적 윈도우 내 미출근 근무가 있으면 배너 표시,
  /// 없으면 진행 중인 추적 중지
  void _checkAndStartTracking() {
    final hasActiveWork = _todayWorks.any((work) {
      final attendance = _attendanceMap[work.id];
      if (attendance?.hasCheckedIn ?? false) return false;
      return _isInTrackingWindow(work);
    });

    if (!hasActiveWork) {
      _stopLocationTracking();
    }
    // 배너 표시 여부는 build()에서 _isInTrackingWindow로 판단
  }

  /// 사용자가 위치 공유 허용을 누를 때
  Future<void> _onLocationConsentGranted() async {
    final userProvider = Provider.of<UserProvider>(context, listen: false);
    final uid = userProvider.currentUser?.uid;
    if (uid == null) return;

    setState(() => _locationTrackingActive = true);

    // 사업장 좌표 캐싱
    for (final work in _todayWorks) {
      if (_businessLat.containsKey(work.businessId)) continue;
      final biz = await _firestoreService.getBusinessById(work.businessId);
      _businessLat[work.businessId] = biz?.latitude;
      _businessLng[work.businessId] = biz?.longitude;
    }

    // Firestore에 동의 + 문서 생성
    final now = DateTime.now();
    for (final work in _todayWorks) {
      final attendance = _attendanceMap[work.id];
      if (attendance?.hasCheckedIn ?? false) continue;
      if (!_isInTrackingWindow(work)) continue;
      await _firestoreService.grantLocationConsent(
        applicationId: work.id,
        userId: uid,
        businessId: work.businessId,
        workDate: now,
        scheduledStart: work.startTime,
      );
    }

    setState(() => _locationTrackingActive = true);
    _startLocationTimer();
  }

  void _startLocationTimer() {
    _locationTimer?.cancel();
    _pushLocationUpdate(); // 즉시 1회
    _locationTimer = Timer.periodic(const Duration(minutes: 2), (_) {
      _pushLocationUpdate();
    });
  }

  void _stopLocationTracking() {
    _locationTimer?.cancel();
    _locationTimer = null;
    if (mounted) {
      setState(() {
        _locationTrackingActive = false;
      });
    }
  }

  Future<void> _pushLocationUpdate() async {
    if (!_locationTrackingActive || !mounted) return;
    try {
      final position = await LocationHelper.getCurrentPosition();
      if (position == null || !mounted) return;

      for (final work in _todayWorks) {
        final attendance = _attendanceMap[work.id];
        if (attendance?.hasCheckedIn ?? false) continue;
        if (!_isInTrackingWindow(work)) continue;

        double? distance;
        final lat = _businessLat[work.businessId];
        final lng = _businessLng[work.businessId];
        if (lat != null && lng != null) {
          distance = LocationHelper.calculateDistance(
            lat1: position.latitude,
            lon1: position.longitude,
            lat2: lat,
            lon2: lng,
          );
        }

        await _firestoreService.updateWorkerLocation(
          applicationId: work.id,
          lat: position.latitude,
          lng: position.longitude,
          accuracy: position.accuracy,
          distanceMeters: distance,
        );
      }
    } catch (e) {
      debugPrint('⚠️ [위치 갱신] 실패: $e');
    }
  }

  /// 출근 체크
  Future<void> _checkIn(ApplicationModel work) async {
    if (_isProcessing) return;
    setState(() => _isProcessing = true);

    final uid = Provider.of<UserProvider>(context, listen: false).currentUser?.uid;

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

      final attendanceId = await _firestoreService.checkIn(
        applicationId: work.id,
        userId: uid!,
        businessId: work.businessId,
        businessName: work.businessName,
        workDate: DateTime.now(),
        workType: work.selectedWorkType,
        latitude: position.latitude,
        longitude: position.longitude,
        scheduledStartTime: work.startTime.isNotEmpty ? work.startTime : null,
        method: 'gps',
      );

      if (attendanceId != null && mounted) {
        ToastHelper.showSuccess('출근이 완료되었습니다!');
        if (_locationTrackingActive) {
          await _firestoreService.stopWorkerTracking(work.id);
        }
        await _loadTodayWorks();
        _checkAndStartTracking();
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
        scheduledEndTime: work.endTime.isNotEmpty ? work.endTime : null,
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
                    itemCount: _todayWorks.length + 1,
                    itemBuilder: (context, index) {
                      if (index == 0) return _buildLocationBanner();
                      final work = _todayWorks[index - 1];
                      final attendance = _attendanceMap[work.id];
                      return _buildWorkCard(work, attendance);
                    },
                  ),
                ),
    );
  }

  /// 위치 공유 배너 (동의 요청 또는 추적 중 표시)
  Widget _buildLocationBanner() {
    final hasTrackingWork = _todayWorks.any((work) {
      final attendance = _attendanceMap[work.id];
      if (attendance?.hasCheckedIn ?? false) return false;
      return _isInTrackingWindow(work);
    });

    if (!hasTrackingWork && !_locationTrackingActive) return const SizedBox.shrink();

    // 추적 중 상태
    if (_locationTrackingActive) {
      return Container(
        margin: EdgeInsets.only(bottom: ResponsiveHelper.spacing(context, 12)),
        padding: EdgeInsets.symmetric(
          horizontal: ResponsiveHelper.spacing(context, 16),
          vertical: ResponsiveHelper.spacing(context, 10),
        ),
        decoration: BoxDecoration(
          color: AppColors.infoBg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.infoLight),
        ),
        child: Row(
          children: [
            Icon(Icons.location_on, color: AppColors.infoDark,
                size: ResponsiveHelper.iconSize(context, 18)),
            SizedBox(width: ResponsiveHelper.spacing(context, 8)),
            Expanded(
              child: Text(
                '위치 공유 중 · 출근 완료 후 자동 중지됩니다',
                style: ResponsiveHelper.smallStyle(context).copyWith(
                  color: AppColors.infoDark,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            TextButton(
              onPressed: _stopLocationTracking,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(
                '중지',
                style: ResponsiveHelper.smallStyle(context)
                    .copyWith(color: AppColors.grey600),
              ),
            ),
          ],
        ),
      );
    }

    // 동의 요청 배너 (dismissed면 숨김)
    if (_bannerDismissed) return const SizedBox.shrink();

    return Container(
      margin: EdgeInsets.only(bottom: ResponsiveHelper.spacing(context, 12)),
      padding: ResponsiveHelper.cardPadding(context),
      decoration: BoxDecoration(
        color: AppColors.infoBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.infoLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.location_searching,
                  color: AppColors.infoDark,
                  size: ResponsiveHelper.iconSize(context, 20)),
              SizedBox(width: ResponsiveHelper.spacing(context, 8)),
              Text(
                '위치 공유 요청',
                style: ResponsiveHelper.bodyStyle(context).copyWith(
                  fontWeight: FontWeight.bold,
                  color: AppColors.infoDark,
                ),
              ),
            ],
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 6)),
          Text(
            '출근 예정 시간이 다가오고 있습니다.\n관리자가 출근 전 위치를 확인할 수 있도록\n위치 공유를 허용해주세요.',
            style: ResponsiveHelper.smallStyle(context, color: AppColors.grey700),
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 10)),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => setState(() => _bannerDismissed = true),
                child: Text(
                  '나중에',
                  style: ResponsiveHelper.smallStyle(context)
                      .copyWith(color: AppColors.grey600),
                ),
              ),
              SizedBox(width: ResponsiveHelper.spacing(context, 8)),
              ElevatedButton.icon(
                onPressed: _onLocationConsentGranted,
                icon: Icon(Icons.location_on,
                    size: ResponsiveHelper.iconSize(context, 16)),
                label: const Text('위치 공유 허용'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.infoDark,
                  foregroundColor: Colors.white,
                  padding: EdgeInsets.symmetric(
                    horizontal: ResponsiveHelper.spacing(context, 12),
                    vertical: ResponsiveHelper.spacing(context, 8),
                  ),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ],
          ),
        ],
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

    return Card(
      margin: EdgeInsets.only(bottom: ResponsiveHelper.spacing(context, 16)),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      elevation: 2,
      shadowColor: Colors.black.withValues(alpha: 0.08),
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

  /// "HH:mm:ss" → "HH:mm"
  String _trimSeconds(String? t) {
    if (t == null) return '-';
    final parts = t.split(':');
    return parts.length >= 2 ? '${parts[0]}:${parts[1]}' : t;
  }

  /// 출근 정보 카드
  Widget _buildAttendanceInfo(AttendanceModel attendance) {
    // 상태에 따른 색상/아이콘/라벨
    final Color bgColor;
    final Color borderColor;
    final Color iconColor;
    final IconData icon;
    final String label;

    if (attendance.hasCheckedOut) {
      if (attendance.isEarlyLeave) {
        bgColor = AppColors.warningBg;
        borderColor = AppColors.warningLight;
        iconColor = AppColors.warningDark;
        icon = Icons.directions_run;
        label = '조퇴';
      } else {
        bgColor = AppColors.successBg;
        borderColor = AppColors.successLight;
        iconColor = AppColors.successDark;
        icon = Icons.check_circle;
        label = '출퇴근 완료';
      }
    } else if (attendance.isLate) {
      bgColor = AppColors.warningBg;
      borderColor = AppColors.warningLight;
      iconColor = AppColors.warningDark;
      icon = Icons.warning_amber_rounded;
      label = '지각';
    } else {
      bgColor = AppColors.infoBg;
      borderColor = AppColors.infoLight;
      iconColor = AppColors.infoDark;
      icon = Icons.check_circle;
      label = '출근 완료';
    }

    return Container(
      padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 12)),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: iconColor, size: ResponsiveHelper.iconSize(context, 20)),
              SizedBox(width: ResponsiveHelper.spacing(context, 8)),
              Text(
                label,
                style: ResponsiveHelper.bodyStyle(context).copyWith(
                  fontWeight: FontWeight.bold,
                  color: iconColor,
                ),
              ),
            ],
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 8)),
          Text(
            '출근 시각: ${_trimSeconds(attendance.checkIn)}',
            style: ResponsiveHelper.smallStyle(context, color: AppColors.grey700),
          ),
          if (attendance.hasCheckedOut) ...[
            SizedBox(height: ResponsiveHelper.spacing(context, 4)),
            Text(
              '퇴근 시각: ${_trimSeconds(attendance.checkOut)}',
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