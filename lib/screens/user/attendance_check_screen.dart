import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../models/core/application_model.dart';
import '../../models/core/attendance_model.dart';
import '../../models/core/business_model.dart';
import '../../widgets/common/loading_button.dart';
import '../../services/firestore_service.dart';
import '../../services/analytics_service.dart';
import '../../providers/user_provider.dart';
import '../../utils/beacon_helper.dart';
import '../../utils/location_helper.dart';
import '../../utils/toast_helper.dart';
import '../../utils/dialog_helper.dart';
import '../../utils/responsive_helper.dart';
import '../../utils/format_helper.dart';
import '../../theme/app_colors.dart';
import '../../widgets/common/loading_widget.dart';
import '../../widgets/common/gradient_scaffold.dart';
import '../../services/device_integrity_service.dart';
import '../../services/fcm_service.dart';
import '../../widgets/common/app_empty_state.dart';

/// 출퇴근 체크 화면
class AttendanceCheckScreen extends StatefulWidget {
  const AttendanceCheckScreen({super.key});

  @override
  State<AttendanceCheckScreen> createState() => _AttendanceCheckScreenState();
}

class _AttendanceCheckScreenState extends State<AttendanceCheckScreen>
    with WidgetsBindingObserver {
  final FirestoreService _firestoreService = FirestoreService();

  List<ApplicationModel> _todayWorks = [];
  final Map<String, AttendanceModel?> _attendanceMap = {};
  bool _isLoading = true;
  bool _isProcessing = false;

  // 위치 추적
  bool _locationTrackingActive = false;
  bool _isGrantingConsent = false;
  bool _bannerDismissed = false;
  Timer? _locationTimer;
  final Map<String, double?> _businessLat = {};
  final Map<String, double?> _businessLng = {};
  // 근무지 이탈 경고 — 알림 스팸 방지 (workId → 마지막 경고 시각)
  final Map<String, DateTime> _lastDepartureAlert = {};
  final Map<String, double> _businessRadius = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadTodayWorks();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _locationTimer?.cancel();
    super.dispose();
  }

  /// 앱 라이프사이클 변화 감지 — 포그라운드 복귀 시 타이머 재개
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _locationTrackingActive) {
      // 포그라운드 복귀 → 즉시 1회 갱신 + 타이머 재시작
      debugPrint('📍 [위치추적] 포그라운드 복귀 → 타이머 재시작');
      _startLocationTimer();
    } else if (state == AppLifecycleState.paused) {
      // 백그라운드 진입 → 타이머 일시 중지 (배터리 절약)
      debugPrint('📍 [위치추적] 백그라운드 진입 → 타이머 일시 중지');
      _locationTimer?.cancel();
      _locationTimer = null;
    }
  }

  /// 오늘 확정된 근무 조회
  Future<void> _loadTodayWorks() async {
    setState(() => _isLoading = true);

    try {
      final userProvider = Provider.of<UserProvider>(context, listen: false);
      final uid = userProvider.currentUser?.uid;

      if (uid == null) {
        ToastHelper.showError('로그인이 필요합니다.');
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      final allApplications = await _firestoreService.getMyApplications(uid);

      final today = DateTime.now();
      final todayStart = DateTime(today.year, today.month, today.day);
      final todayWorks = <ApplicationModel>[];

      for (final app in allApplications) {
        if (!AppStatus.confirmedStatuses.contains(app.status)) continue;

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

  /// 예정 출근 60분 전 ~ 출근 완료 후 2시간 구간인지 확인
  ///
  /// 야간 근무(자정 경계) 대응:
  /// 현재 시각을 중심으로 ±3시간 범위의 오늘 날짜 기준 스케줄 시간을 비교.
  /// 출근 시각이 자정 이후(예: 00:30)이면 workDate 기준일을 사용해 정확히 계산.
  bool _isInTrackingWindow(ApplicationModel work) {
    if (work.startTime.isEmpty) return false;
    final parts = work.startTime.split(':');
    if (parts.length < 2) return false;

    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null) return false;

    final now = DateTime.now();

    // 장기 근무는 오늘 날짜 기준, 단기 근무는 workDate 기준으로 scheduledStart 구성
    final baseDate = (work.workDays != null && work.workDays!.isNotEmpty)
        ? now
        : work.workDate;
    final scheduledStart = DateTime(
      baseDate.year, baseDate.month, baseDate.day, h, m,
    );

    // h < 6 (자정 근처 새벽 근무)이면 workDate + 1일 기준으로도 체크
    // ex: workDate = 5/30, startTime = "00:30" → scheduledStart = 5/30 00:30
    final windowStart = scheduledStart.subtract(const Duration(minutes: 60));
    final windowEnd   = scheduledStart.add(const Duration(hours: 2));

    // 기본 체크
    if (now.isAfter(windowStart) && now.isBefore(windowEnd)) return true;

    // 야간 근무 보정: 전날 23시대 → baseDate의 자정 근처 체크
    // (ex: 5/31 00:30 근무 → 5/30 23:30에 체크)
    if (h <= 3) {
      // day-1=0은 이전 달 말일로 해석됨 → subtract로 안전하게 처리
      final prevDay = baseDate.subtract(const Duration(days: 1));
      final prevDayStart = DateTime(prevDay.year, prevDay.month, prevDay.day, h, m);
      final prevWindowStart = prevDayStart.subtract(const Duration(minutes: 60));
      final prevWindowEnd   = prevDayStart.add(const Duration(hours: 2));
      if (now.isAfter(prevWindowStart) && now.isBefore(prevWindowEnd)) return true;
    }

    return false;
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
    if (_isGrantingConsent) return;
    _isGrantingConsent = true;
    final userProvider = Provider.of<UserProvider>(context, listen: false);
    final uid = userProvider.currentUser?.uid;
    if (uid == null) { _isGrantingConsent = false; return; }

    // 사업장 좌표 + 반경 캐싱
    for (final work in _todayWorks) {
      if (_businessLat.containsKey(work.businessId)) continue;
      final biz = await _firestoreService.getBusinessById(work.businessId);
      _businessLat[work.businessId] = biz?.latitude;
      _businessLng[work.businessId] = biz?.longitude;
      _businessRadius[work.businessId] = biz?.gpsRadius.toDouble() ?? 100.0;
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

    if (!mounted) { _isGrantingConsent = false; return; }
    setState(() => _locationTrackingActive = true);
    _isGrantingConsent = false;
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
        final lat = _businessLat[work.businessId];
        final lng = _businessLng[work.businessId];

        final double? distance = (lat != null && lng != null)
            ? LocationHelper.calculateDistance(
                lat1: position.latitude, lon1: position.longitude,
                lat2: lat, lon2: lng,
              )
            : null;

        // 출근 전: 위치 기록 전송
        if (!(attendance?.hasCheckedIn ?? false) && _isInTrackingWindow(work)) {
          await _firestoreService.updateWorkerLocation(
            applicationId: work.id,
            lat: position.latitude,
            lng: position.longitude,
            accuracy: position.accuracy,
            distanceMeters: distance,
          );
        }

        // 출근 후 퇴근 전: 근무지 이탈 감지 (15분 쿨다운)
        if ((attendance?.hasCheckedIn ?? false) &&
            !(attendance?.hasCheckedOut ?? false) &&
            distance != null) {
          final radius = _businessRadius[work.businessId] ?? 100.0;
          // 반경 + 50m 버퍼 (GPS 오차 보정)
          if (distance > radius + 50) {
            final lastAlert = _lastDepartureAlert[work.id];
            final now = DateTime.now();
            if (lastAlert == null ||
                now.difference(lastAlert).inMinutes >= 15) {
              _lastDepartureAlert[work.id] = now;
              debugPrint('⚠️ [이탈 감지] ${work.businessName}: ${distance.toStringAsFixed(0)}m');
              await FCMService().showGeofenceAlert(work.businessName);
            }
          } else {
            // 복귀 시 쿨다운 초기화
            _lastDepartureAlert.remove(work.id);
          }
        }
      }
    } catch (e) {
      debugPrint('⚠️ [위치 갱신] 실패: $e');
    }
  }

  /// 출근 체크 — 사업장 attendanceType에 따라 GPS/비콘 자동 분기
  Future<void> _checkIn(ApplicationModel work) async {
    if (_isProcessing) return;
    setState(() => _isProcessing = true);

    final uid = Provider.of<UserProvider>(context, listen: false).currentUser?.uid;
    if (uid == null) { setState(() => _isProcessing = false); return; }

    try {
      // 0. 기기 시간 변조 감지 (서버 시각과 5분 이상 차이 시 차단)
      final timeValid = await DeviceIntegrityService().isDeviceTimeValid();
      if (!timeValid) {
        if (mounted) {
          await DialogHelper.showError(
            context,
            message: '기기 시간이 실제 시간과 크게 다릅니다.\n'
                '설정에서 "자동 날짜/시간"을 켠 후 다시 시도해주세요.',
          );
        }
        return;
      }

      // 1. 사업장 정보 로드 (attendanceType 확인)
      final business = await _firestoreService.getBusinessById(work.businessId);
      if (business == null) {
        if (mounted) await DialogHelper.showError(context, message: '사업장 정보를 찾을 수 없습니다.');
        return;
      }

      final type = business.attendanceType; // 'gps' | 'beacon' | 'both' | 'manual'

      // 2. 방식별 검증
      String usedMethod = type;
      double? lat, lng;

      // 수동 방식: 관리자만 처리 가능, 근로자는 직접 체크 불가
      if (type == 'manual') {
        if (mounted) {
          await DialogHelper.showError(
            context,
            title: '수동 출근 방식',
            message: '이 사업장은 관리자가 직접 출퇴근을 처리합니다.\n관리자에게 문의해주세요.',
          );
        }
        return;
      }

      if (type == 'gps') {
        // ── GPS 전용 ───────────────────────────────────────────
        final ok = await _verifyByGPS(business, loadingMsg: 'GPS 확인 중...');
        if (ok == null) return; // 권한 거부 등
        if (!ok.$1) return;    // 범위 밖
        lat = ok.$2; lng = ok.$3;
        usedMethod = 'gps';

      } else if (type == 'beacon') {
        // ── 비콘 전용 ─────────────────────────────────────────
        final ok = await _verifyByBeacon(business);
        if (!ok) return;
        // 비콘 성공 시 GPS 좌표는 null (위치 저장 불필요)
        usedMethod = 'beacon';

      } else {
        // ── GPS + 비콘 병행 (both) ─────────────────────────────
        // GPS를 먼저 시도
        final gpsResult = await _verifyByGPS(business, silent: true);

        if (gpsResult != null && gpsResult.$1) {
          // GPS 성공
          lat = gpsResult.$2; lng = gpsResult.$3;
          usedMethod = 'gps';
        } else {
          // GPS 실패 또는 권한 없음 → 비콘 폴백
          // Toast를 먼저 표시하고 잠시 후 비콘 스캔 (로딩 다이얼로그와 겹침 방지)
          if (mounted) ToastHelper.showInfo('GPS 확인 불가 — 비콘으로 재시도합니다.');
          await Future.delayed(const Duration(milliseconds: 600));
          if (!mounted) return;
          final beaconOk = await _verifyByBeacon(business);
          if (!beaconOk) return;
          usedMethod = 'beacon';
        }
      }

      // 3. Firestore 출근 기록 저장 (비콘 방식은 lat/lng null — 불필요)
      final attendanceId = await _firestoreService.checkIn(
        applicationId: work.id,
        userId: uid,
        businessId: work.businessId,
        businessName: work.businessName,
        workDate: DateTime.now(),
        workType: work.selectedWorkType,
        latitude: lat,
        longitude: lng,
        scheduledStartTime: work.startTime.isNotEmpty ? work.startTime : null,
        method: usedMethod,
      );

      if (attendanceId != null && mounted) {
        ToastHelper.showSuccess('출근이 완료되었습니다!');
        AnalyticsService.logCheckIn(method: usedMethod);
        if (_locationTrackingActive) await _firestoreService.stopWorkerTracking(work.id);
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
      // mounted 여부와 무관하게 상태값 리셋 (영구 잠금 방지)
      _isProcessing = false;
      if (mounted) setState(() {});
    }
  }

  // ── GPS 검증 헬퍼 ──────────────────────────────────────────────
  /// 반환: null=권한없음/오류, (bool verified, double? lat, double? lng)
  Future<(bool, double?, double?)?> _verifyByGPS(
    BusinessModel business, {
    String loadingMsg = 'GPS 확인 중...',
    bool silent = false,
  }) async {
    // GPS 권한/서비스 상세 체크 — 서비스 Off와 권한 거부 메시지 분기
    final locationResult = await LocationHelper.checkAndRequestPermissionDetailed();
    if (locationResult != LocationCheckResult.ok) {
      if (!silent && mounted) {
        final isServiceOff  = locationResult == LocationCheckResult.serviceDisabled;
        final isDeniedForever = locationResult == LocationCheckResult.permissionDeniedForever;
        await showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(isServiceOff ? 'GPS를 켜주세요' : '위치 권한 필요'),
            content: Text(
              isServiceOff
                  ? '기기의 위치 서비스(GPS)가 꺼져 있습니다.\n설정 앱에서 위치 서비스를 켜주세요.'
                  : isDeniedForever
                      ? '위치 권한이 영구적으로 거부되었습니다.\n설정 앱에서 위치 권한을 허용해주세요.'
                      : '출퇴근 체크를 위해 위치 권한이 필요합니다.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('취소'),
              ),
              TextButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  if (isServiceOff) {
                    LocationHelper.openLocationSettings();
                  } else {
                    LocationHelper.openAppSettings();
                  }
                },
                child: const Text('설정 열기'),
              ),
            ],
          ),
        );
      }
      return null;
    }

    if (!silent && mounted) DialogHelper.showLoading(context, message: loadingMsg);
    final position = await LocationHelper.getCurrentPosition();
    if (!silent && mounted) Navigator.pop(context);

    if (position == null) {
      // LocationHelper.getCurrentPosition이 null 반환 = GPS 실패 또는 Mock GPS 감지
      if (!silent && mounted) {
        await DialogHelper.showError(
          context,
          message: 'GPS 위치를 가져올 수 없습니다.\n가짜 GPS 앱을 사용 중이거나 위치 서비스에 문제가 있습니다.',
        );
      }
      return null;
    }

    // GPS 정확도 경고 (100m 초과 시 — 실내 GPS 등)
    if (!silent && position.accuracy > 100 && mounted) {
      ToastHelper.showWarning(
        'GPS 정확도가 낮습니다 (${position.accuracy.toStringAsFixed(0)}m).\n'
        '야외에서 다시 시도하면 더 정확합니다.',
      );
    }

    // 사업장 GPS 좌표 미설정 체크
    if (business.latitude == null || business.longitude == null) {
      if (!silent && mounted) {
        await DialogHelper.showError(
          context,
          title: '사업장 위치 미설정',
          message: '사업장의 GPS 위치가 등록되어 있지 않습니다.\n관리자에게 사업장 위치 등록을 요청하세요.',
        );
      }
      return null;
    }

    final gpsRadius = business.gpsRadius.toDouble();
    final isNearby = LocationHelper.isWithinRadius(
      currentLat: position.latitude,
      currentLon: position.longitude,
      businessLat: business.latitude!,
      businessLon: business.longitude!,
      radiusInMeters: gpsRadius,
    );

    if (!isNearby && !silent && mounted) {
      final distance = LocationHelper.calculateDistance(
        lat1: position.latitude, lon1: position.longitude,
        lat2: business.latitude!, lon2: business.longitude!,
      );
      await DialogHelper.showError(
        context,
        title: '출근 위치 오류',
        message: '사업장에서 너무 멉니다.\n'
            '현재 거리: ${LocationHelper.formatDistance(distance)}\n'
            '사업장 근처(${gpsRadius.toInt()}m 이내)에서 출근해주세요.',
      );
    }

    return (isNearby, position.latitude, position.longitude);
  }

  // ── 비콘 검증 헬퍼 ─────────────────────────────────────────────
  /// 반환: true = 비콘 인식 성공, false = 실패
  Future<bool> _verifyByBeacon(BusinessModel business) async {
    final uuid = business.beaconUUID;
    if (uuid == null || uuid.isEmpty) {
      if (mounted) {
        await DialogHelper.showError(
          context,
          title: '비콘 설정 오류',
          message: '사업장에 비콘 UUID가 등록되어 있지 않습니다.\n관리자에게 문의하세요.',
        );
      }
      return false;
    }

    if (mounted) {
      DialogHelper.showLoading(context, message: '비콘 스캔 중...\n(최대 10초 소요)');
    }

    final result = await BeaconHelper.isBeaconNearby(
      uuid: uuid,
      major: business.beaconMajor,
      minor: business.beaconMinor,
      rssiThreshold: business.beaconRssiThreshold,
    );

    if (mounted) Navigator.pop(context); // 로딩 닫기

    if (result == null) {
      if (mounted) {
        await DialogHelper.showError(
          context,
          title: '블루투스 오류',
          message: '블루투스 권한이 없거나 비콘 스캔에 실패했습니다.\n'
              '블루투스가 켜져 있는지 확인해주세요.',
        );
      }
      return false;
    }

    if (!result) {
      if (mounted) {
        await DialogHelper.showError(
          context,
          title: '비콘 미감지',
          message: '사업장 비콘을 감지하지 못했습니다.\n'
              '사업장 내부에서 다시 시도해주세요.',
        );
      }
      return false;
    }

    return true;
  }

  /// 퇴근 체크 — attendanceType에 따라 GPS/비콘 분기
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
      final business = await _firestoreService.getBusinessById(work.businessId);
      if (business == null) {
        if (mounted) await DialogHelper.showError(context, message: '사업장 정보를 찾을 수 없습니다.');
        return;
      }

      final type = business.attendanceType;
      String usedMethod = type;
      double? lat, lng;

      if (type == 'manual') {
        if (mounted) {
          await DialogHelper.showError(
            context,
            title: '수동 출근 방식',
            message: '이 사업장은 관리자가 직접 출퇴근을 처리합니다.\n관리자에게 문의해주세요.',
          );
        }
        return;
      }

      if (type == 'beacon') {
        // 비콘 전용: 근접 확인 (GPS 좌표 불필요)
        final ok = await _verifyByBeacon(business);
        if (!ok) return;
        usedMethod = 'beacon';
      } else {
        // GPS 또는 both: GPS 반경 확인 후 퇴근 처리
        final result = await _verifyByGPS(business, loadingMsg: 'GPS 확인 중...');
        if (result == null) return;
        final (ok, resultLat, resultLng) = result;
        if (!ok) return;
        lat = resultLat;
        lng = resultLng;
        usedMethod = 'gps';
      }

      final success = await _firestoreService.checkOut(
        attendanceId: attendance.id,
        latitude: lat,
        longitude: lng,
        method: usedMethod,
        scheduledEndTime: work.endTime.isNotEmpty ? work.endTime : null,
      );

      if (success && mounted) {
        ToastHelper.showSuccess('퇴근이 완료되었습니다!');
        AnalyticsService.logCheckOut(method: usedMethod);
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
    return GradientScaffold(
      title: '출퇴근 체크',
      actions: [
        IconButton(
          icon: Icon(Icons.refresh,
              color: Colors.white,
              size: ResponsiveHelper.iconSize(context, 24)),
          tooltip: '새로고침',
          onPressed: _loadTodayWorks,
        ),
      ],
      body: _isLoading
          ? const LoadingWidget(message: '근무 정보를 불러오는 중...')
          : _todayWorks.isEmpty
              ? _buildEmptyState()
              : RefreshIndicator(
                  onRefresh: _loadTodayWorks,
                  child: ListView.builder(
                    padding: ResponsiveHelper.listPadding(context),
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
      padding: ResponsiveHelper.listPadding(context),
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
    return const AppEmptyState(
      icon: Icons.event_busy,
      title: '오늘 확정된 근무가 없습니다',
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
        padding: ResponsiveHelper.listPadding(context),
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
        Expanded(
          child: Text(
            text,
            style: ResponsiveHelper.bodyStyle(context, color: AppColors.grey700),
            overflow: TextOverflow.ellipsis,
          ),
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