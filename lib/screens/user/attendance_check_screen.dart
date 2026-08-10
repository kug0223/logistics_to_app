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
import '../../theme/app_colors.dart';
import '../../widgets/common/loading_widget.dart';
import '../../widgets/common/gradient_scaffold.dart';
import '../../services/device_integrity_service.dart';
import '../../widgets/common/app_empty_state.dart';
import '../../screens/contract/contract_sign_screen.dart';
import 'all_to_list_screen.dart';

/// 출퇴근 체크 화면
class AttendanceCheckScreen extends StatefulWidget {
  const AttendanceCheckScreen({super.key});

  @override
  State<AttendanceCheckScreen> createState() => _AttendanceCheckScreenState();
}

class _AttendanceCheckScreenState extends State<AttendanceCheckScreen> {
  static final _fmt = NumberFormat('#,###'); // 카드 build마다 인스턴스 생성 방지
  final FirestoreService _firestoreService = FirestoreService();

  List<ApplicationModel> _todayWorks = [];
  final Map<String, AttendanceModel?> _attendanceMap = {};
  bool _isLoading = false; // 초기값 false — initState에서 _loadTodayWorks() 첫 호출 시 재진입 방어에 걸리지 않도록
  bool _isProcessing = false;
  bool _isReconfirming = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _loadTodayWorks();
    });
  }

  /// 오늘 확정된 근무 조회
  // finally 블록 없음 — 정상 경로(149행)와 catch(160행) 양쪽에서 _isLoading=false 처리되어 실질 고착 없음
  Future<void> _loadTodayWorks() async {
    if (!mounted) return;
    if (_isLoading) return; // [M-2] pull-to-refresh + 체크인 완료 후 자동 재조회 동시 재진입 방어
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
      // [C-001] yesterday를 루프 밖으로 — 퇴근 완료 필터에서도 사용
      final yesterday = todayStart.subtract(const Duration(days: 1));
      final todayWorks = <ApplicationModel>[];

      for (final app in allApplications) {
        if (!AppStatus.confirmedStatuses.contains(app.status)) continue;

        // [A-H1-FIX] isLongTermApplication 게터 사용 — applicationType·workDays·workEndDate 3조건 모두 반영
      final isReallyLongTerm = app.isLongTermApplication;

        if (!isReallyLongTerm) {
          // 어제 시작한 야간 근무(자정 이후 퇴근 대기)도 포함
          if (DateUtils.isSameDay(app.workDate, todayStart) ||
              DateUtils.isSameDay(app.workDate, yesterday)) {
            todayWorks.add(app);
          }
          continue;
        }

        // isWorkingOnDate: actualResignDate·leaveDates·extraWorkDates·workDays 모두 반영
        if (app.isWorkingOnDate(todayStart)) {
          todayWorks.add(app);
        }
      }

      // 각 근무의 출근 기록 병렬 조회 — 로컬 맵으로 수집 후 한번에 반영
      // (클로저 내 직접 변이 시 부분 실패 때 stale/new 데이터 혼재 방지)
      final tempMap = <String, AttendanceModel?>{};
      await Future.wait(
        todayWorks.map((work) async {
          final attendance = await _firestoreService.getTodayAttendance(
            userId: uid,
            applicationId: work.id,
          );
          tempMap[work.id] = attendance;
        }),
      );
      // [FIX] addAll은 기존 키를 삭제하지 않음 — 재로드 시 이전 근무의 stale 데이터가 남아
      // _showRoundingFeedback에서 잘못된 시간을 읽을 수 있으므로 clear() 후 교체.
      // setState 내부로 이동해 _todayWorks와 원자적으로 반영.

      // [C-001] 어제 날짜 출근 기록이 퇴근 완료인 항목은 오늘 화면에서 제외 (stale 방지)
      // work.workDate 대신 att.workDate 기준으로 어제를 판단:
      //   - 단기: att.workDate = work.workDate (실제 근무일) → 동일하게 동작
      //   - 장기: work.workDate = 계약 시작일(고정값)이라 isSameDay(work.workDate, yesterday) 항상 false
      //           → att.workDate = checkIn 시점 오늘 날짜로 기록 → 어제 기록을 정확히 식별 가능
      // [M-1 수정] tempMap 사용 — _attendanceMap은 아직 setState 전이라 이전 값(stale)을 가리킴
      //   최초 로드 시 _attendanceMap={} → att=null → 어제 완료 기록이 필터 통과 → 오늘 목록에 표시됨
      final visibleWorks = todayWorks.where((work) {
        final att = tempMap[work.id];
        if (att == null) return true;
        if (DateUtils.isSameDay(att.workDate, yesterday)) {
          // [G-3 수정] 어제 기록은 퇴근 완료 또는 missed_checkout 상태 모두 오늘 화면에서 숨김
          // [BUG-M2 수정 2026-07-27] NO_SHOW/absent 상태도 어제 기록이면 숨김
          // — 배치 자동처리 후 어제 카드가 "출근하기" 버튼과 함께 오늘 화면에 남는 UX 버그 방지
          if (att.checkOut != null ||
              att.status == 'missed_checkout' ||
              att.status == AttendanceModel.statusNoShow ||
              att.status == AttendanceModel.statusAbsent) {
            return false;
          }
        }
        return true;
      }).toList();

      if (mounted) {
        setState(() {
          _attendanceMap.clear();       // stale 키 제거
          _attendanceMap.addAll(tempMap);
          _todayWorks = visibleWorks;
          _isLoading = false;
        });
      }

      debugPrint('✅ 오늘 근무: ${visibleWorks.length}개 (전체 후보: ${todayWorks.length}개)');
    } catch (e) {
      debugPrint('❌ 오늘 근무 조회 실패: $e');
      if (mounted) {
        setState(() => _isLoading = false);
        ToastHelper.showError('근무 정보를 불러오는데 실패했습니다.');
      }
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
        if (!ok || !mounted) return;
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
          if (!beaconOk || !mounted) return;
          usedMethod = 'beacon';
        }
      }

      // 3. Firestore 출근 기록 저장 (비콘 방식은 lat/lng null — 불필요)
      // 단기 근무: work.workDate 사용 — 야간 근무 자정 이후 체크인 시 docId가 다음 날로 밀리는 것 방지 [060]
      // 장기 근무: 오늘 날짜 사용 — work.workDate는 계약 시작일(고정값)이라 날짜별 docId 분리 불가
      final todayDate = DateTime.now();
      final attendanceWorkDate = work.isLongTermApplication
          ? DateTime(todayDate.year, todayDate.month, todayDate.day)
          : work.workDate;
      final attendanceId = await _firestoreService.checkIn(
        applicationId: work.id,
        userId: uid,
        businessId: work.businessId,
        businessName: work.businessName,
        workDate: attendanceWorkDate,
        workType: work.selectedWorkType,
        latitude: lat,
        longitude: lng,
        scheduledStartTime: work.startTime.isNotEmpty ? work.startTime : null,
        scheduledEndTime: work.endTime.isNotEmpty ? work.endTime : null,
        method: usedMethod,
        attendanceRules: business.attendanceRules,
      );

      if (attendanceId != null && mounted) {
        ToastHelper.showSuccess('출근이 완료되었습니다!');
        AnalyticsService.logCheckIn(method: usedMethod);
        if (!mounted) return;
        await _loadTodayWorks();
        if (!mounted) return;
        _showRoundingFeedback(work.id, isCheckIn: true);
      }
    } catch (e) {
      debugPrint('❌ 출근 체크 실패: $e');
      if (mounted) {
        await DialogHelper.showError(
          context,
          message: e.toString().replaceAll('Exception: ', ''),
        );
      }
      // [BUG-M1 수정 2026-07-27] 에러 후에도 재조회 — 배치 선처리(NO_SHOW 등)로 상태가 바뀐 경우 UI 동기화
      if (mounted) await _loadTodayWorks();
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      } else {
        _isProcessing = false; // mounted 아닐 때도 잠금 해제
      }
    }
  }

  // ── 반올림 피드백 ──────────────────────────────────────────────
  /// _loadTodayWorks() 완료 후 호출. 반올림이 발생한 경우에만 안내 토스트 표시.
  void _showRoundingFeedback(String workId, {required bool isCheckIn}) {
    final att = _attendanceMap[workId];
    if (att == null) return;

    final String? original;
    final String? rounded;
    if (isCheckIn) {
      original = att.originalCheckIn;
      rounded = att.checkIn;
    } else {
      original = att.originalCheckOut;
      rounded = att.checkOut;
    }

    if (original == null || rounded == null || rounded.isEmpty) return;
    final originalTrimmed = original.split(':').take(2).join(':');
    final roundedTrimmed  = rounded.split(':').take(2).join(':');
    if (originalTrimmed == roundedTrimmed) return;

    final label = isCheckIn ? '출근' : '퇴근';
    ToastHelper.showInfo('$label 시간 $originalTrimmed → $roundedTrimmed 으로 처리됐어요');
  }

  // ── GPS 검증 헬퍼 ──────────────────────────────────────────────
  /// 반환: null=권한없음/오류, (bool verified, double? lat, double? lng)
  Future<(bool, double?, double?)?> _verifyByGPS(
    BusinessModel business, {
    String loadingMsg = 'GPS 확인 중...',
    bool silent = false,
  }) async {
    // GPS 권한/서비스 상세 체크 — silent 모드에서는 OS 팝업 억제(both 모드 폴백 분기)
    final locationResult = await LocationHelper.checkAndRequestPermissionDetailed(
      requestIfNeeded: !silent,
    );
    if (locationResult != LocationCheckResult.ok) {
      if (!silent && mounted) {
        final isServiceOff  = locationResult == LocationCheckResult.serviceDisabled;
        final isDeniedForever = locationResult == LocationCheckResult.permissionDeniedForever;
        final goToSettings = await DialogHelper.showConfirm(
          context,
          title: isServiceOff ? 'GPS를 켜주세요' : '위치 권한 필요',
          message: isServiceOff
              ? '기기의 위치 서비스(GPS)가 꺼져 있습니다.\n설정 앱에서 위치 서비스를 켜주세요.'
              : isDeniedForever
                  ? '위치 권한이 영구적으로 거부되었습니다.\n설정 앱에서 위치 권한을 허용해주세요.'
                  : '출퇴근 체크를 위해 위치 권한이 필요합니다.',
          confirmText: '설정 열기',
          icon: isServiceOff ? Icons.gps_off : Icons.location_off,
          iconColor: AppColors.warning,
        );
        if (goToSettings) {
          if (isServiceOff) {
            LocationHelper.openLocationSettings();
          } else {
            LocationHelper.openAppSettings();
          }
        }
      }
      return null;
    }

    bool loadingDialogShown = false;
    if (!silent && mounted) {
      DialogHelper.showLoading(context, message: loadingMsg);
      loadingDialogShown = true;
    }
    final position = await LocationHelper.getCurrentPosition().whenComplete(() {
      if (loadingDialogShown && mounted) Navigator.pop(context);
    });

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

    // [BUG-M3 수정 2026-07-27] gpsRadius=0(미설정) 시 GPS 검증 항상 실패하는 버그 — 100m 기본값 적용
    final gpsRadius = business.gpsRadius > 0 ? business.gpsRadius.toDouble() : 100.0;
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

    // [FIX-HIGH] getBusinessById 이후 unmount 가능 — mounted 체크 후 Navigator.of(context) 호출
    if (!mounted) return false;
    final nav = Navigator.of(context);
    // [FIX-HIGH] GPS와 동일하게 loadingShown 플래그 도입 — mounted=false 시 다이얼로그가
    //            표시되지 않았음에도 nav.pop()이 실행돼 다른 라우트를 팝하는 버그 방지
    bool loadingShown = false;
    if (mounted) {
      DialogHelper.showLoading(context, message: '비콘 스캔 중...\n(최대 10초 소요)');
      loadingShown = true;
    }

    final result = await BeaconHelper.isBeaconNearby(
      uuid: uuid,
      major: business.beaconMajor,
      minor: business.beaconMinor,
      rssiThreshold: business.beaconRssiThreshold,
    );

    if (loadingShown && nav.canPop()) nav.pop(); // 로딩 다이얼로그를 열었을 때만 닫기
    if (!mounted) return false;

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
    setState(() => _isProcessing = true);

    try {
      final confirmed = await DialogHelper.showConfirm(
        context,
        title: '퇴근 확인',
        message: '퇴근 처리하시겠습니까?',
        confirmText: '퇴근',
      );
      if (!confirmed || !mounted) return;
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
        if (!ok || !mounted) return;
        usedMethod = 'beacon';
      } else if (type == 'both') {
        // GPS + 비콘 병행: 출근과 동일하게 GPS 먼저, 실패 시 비콘 폴백
        final gpsResult = await _verifyByGPS(business, silent: true);
        if (gpsResult != null && gpsResult.$1) {
          lat = gpsResult.$2; lng = gpsResult.$3;
          usedMethod = 'gps';
        } else {
          if (mounted) ToastHelper.showInfo('GPS 확인 불가 — 비콘으로 재시도합니다.');
          await Future.delayed(const Duration(milliseconds: 600));
          if (!mounted) return;
          final beaconOk = await _verifyByBeacon(business);
          if (!beaconOk || !mounted) return;
          usedMethod = 'beacon';
        }
      } else {
        // GPS 전용: 반경 확인 후 퇴근 처리
        final result = await _verifyByGPS(business, loadingMsg: 'GPS 확인 중...');
        if (result == null) return;
        final (ok, resultLat, resultLng) = result;
        if (!ok) return;
        lat = resultLat;
        lng = resultLng;
        usedMethod = 'gps';
      }

      // endTime < startTime 검증은 _firestoreService.checkOut() 내부에만 있음.
      //           클라이언트에서는 사전 차단 없이 서비스 계층의 에러 응답에만 의존.
      final success = await _firestoreService.checkOut(
        attendanceId: attendance.id,
        workDate: attendance.workDate,
        latitude: lat,
        longitude: lng,
        method: usedMethod,
        scheduledEndTime: work.endTime.isNotEmpty ? work.endTime : null,
        scheduledStartTime: work.startTime.isNotEmpty ? work.startTime : null,
        attendanceRules: business.attendanceRules,
      );

      if (success && mounted) {
        final uid = context.read<UserProvider>().currentUser?.uid;
        if (uid != null) _firestoreService.invalidateMyAttendanceCache(uid);
        ToastHelper.showSuccess('퇴근이 완료되었습니다!');
        AnalyticsService.logCheckOut(method: usedMethod);
        await _loadTodayWorks();
        if (!mounted) return;
        _showRoundingFeedback(work.id, isCheckIn: false);
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

  /// 리컨펌 응답 처리 — confirmed: 출근 확인, declined: 취소 후 목록 갱신
  Future<void> _respondToReconfirm(ApplicationModel work, String response) async {
    if (_isReconfirming) return;
    setState(() => _isReconfirming = true);
    try {
      final success = await _firestoreService.respondToReconfirm(
        work.id,
        response: response,
      );
      if (!mounted) return;
      if (success) {
        if (response == 'confirmed') {
          ToastHelper.showSuccess('출근 확인이 완료되었습니다!');
        } else {
          ToastHelper.showInfo('근무가 취소되었습니다.');
        }
        await _loadTodayWorks();
      }
    } finally {
      if (mounted) setState(() => _isReconfirming = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GradientScaffold(
      title: '출퇴근 체크',
      onRefresh: _loadTodayWorks,
      body: _isLoading
          ? const LoadingWidget(message: '근무 정보를 불러오는 중...')
          : _todayWorks.isEmpty
              ? _buildEmptyState()
              : RefreshIndicator(
                  onRefresh: _loadTodayWorks,
                  child: ListView.builder(
                    padding: ResponsiveHelper.listPadding(context),
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
    return AppEmptyState(
      icon: Icons.event_busy,
      title: '오늘 확정된 근무가 없습니다',
      subtitle: '새로운 공고에 지원해보세요',
      action: FilledButton.icon(
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const AllTOListScreen()),
        ),
        icon: const Icon(Icons.search, size: 18),
        label: const Text('공고 보러가기'),
      ),
    );
  }

  /// 출근 버튼 영역 — 미서명 계약서가 있으면 차단 UI, 없으면 출근하기 버튼
  Widget _buildCheckInArea(ApplicationModel work) {
    final userProvider = Provider.of<UserProvider>(context, listen: false);
    final pendingContract = userProvider.pendingContractForTo(work.toId ?? '');

    if (pendingContract != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 12)),
            decoration: BoxDecoration(
              color: AppColors.yellowWarnBg,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.yellowWarnBorder),
            ),
            child: Row(
              children: [
                const Icon(Icons.warning_amber_rounded,
                    color: AppColors.yellowWarnDark, size: 18),
                SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                Expanded(
                  child: Text(
                    '계약서 서명이 완료되지 않았습니다',
                    style: ResponsiveHelper.smallStyle(context).copyWith(
                      color: AppColors.yellowWarnText,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 8)),
          ElevatedButton.icon(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ContractSignScreen(
                  contract: pendingContract,
                  role: 'worker',
                ),
              ),
            ).then((_) {
              if (mounted) setState(() {});
            }),
            icon: const Icon(Icons.draw_outlined, size: 18),
            label: const Text('작성하기'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.yellowWarnDark,
              foregroundColor: Colors.white,
              minimumSize: const Size(double.infinity, 44),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ],
      );
    }

    return LoadingButton.primary(
      text: '출근하기',
      icon: Icons.login,
      expand: true,
      isLoading: _isProcessing,
      onPressed: () async => _checkIn(work),
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
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
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
              '${_fmt.format(work.wage)}원/${work.wageType == 'daily' ? '일' : '시간'}',
            ),

            Divider(
              height: ResponsiveHelper.spacing(context, 24),
              color: AppColors.dividerLight,
            ),

            // 리컨펌 요청 섹션 (단기 미출근 + reconfirmStatus=='pending'일 때만)
            if (!work.isLongTermApplication &&
                !hasCheckedIn &&
                work.reconfirmStatus == 'pending')
              _buildReconfirmSection(work),

            // 출근 상태 정보
            if (hasCheckedIn) ...[
              _buildAttendanceInfo(attendance!),
              SizedBox(height: ResponsiveHelper.spacing(context, 12)),
            ],

            // 출근/퇴근 버튼
            if (attendance?.status == AttendanceModel.statusNoShow ||
                attendance?.status == AttendanceModel.statusAbsent)
              _buildNoShowBanner(attendance!.status)
            else if (!hasCheckedIn)
              _buildCheckInArea(work)
            else if (!hasCheckedOut)
              LoadingButton(
                text: '퇴근하기',
                icon: Icons.logout,
                expand: true,
                backgroundColor: AppColors.warningDark,
                isLoading: _isProcessing,
                onPressed: () async => _checkOut(work, attendance!),
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

  /// 리컨펌 섹션 — 단기 근무 중 reconfirmStatus=='pending'이고 미출근일 때 카드 내 표시
  Widget _buildReconfirmSection(ApplicationModel work) {
    return Container(
      width: double.infinity,
      margin: EdgeInsets.only(bottom: ResponsiveHelper.spacing(context, 12)),
      padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 14)),
      decoration: BoxDecoration(
        color: AppColors.infoBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.infoLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.help_outline_rounded,
                color: AppColors.infoDark,
                size: ResponsiveHelper.iconSize(context, 16),
              ),
              SizedBox(width: ResponsiveHelper.spacing(context, 6)),
              Text(
                '출근 확인 요청',
                style: ResponsiveHelper.smallStyle(context).copyWith(
                  fontWeight: FontWeight.bold,
                  color: AppColors.infoDark,
                ),
              ),
            ],
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 8)),
          Text(
            '오늘 근무에 출근하실 수 있으신가요?',
            style: ResponsiveHelper.smallStyle(context, color: AppColors.grey700),
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 10)),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _isReconfirming
                      ? null
                      : () async {
                          final confirmed = await DialogHelper.showDangerConfirm(
                            context,
                            title: '근무 취소',
                            message: '취소하면 TrustScore가 소폭 감점됩니다.\n정말 취소하시겠습니까?',
                            confirmText: '취소하기',
                          );
                          if (confirmed && mounted) {
                            await _respondToReconfirm(work, 'declined');
                          }
                        },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.grey600,
                    side: BorderSide(color: AppColors.grey300),
                    padding: EdgeInsets.symmetric(
                      vertical: ResponsiveHelper.spacing(context, 8),
                    ),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                  ),
                  child: Text(
                    '아니요, 취소할게요',
                    style: ResponsiveHelper.smallStyle(context, color: AppColors.grey600),
                  ),
                ),
              ),
              SizedBox(width: ResponsiveHelper.spacing(context, 8)),
              Expanded(
                child: FilledButton(
                  onPressed: _isReconfirming
                      ? null
                      : () => _respondToReconfirm(work, 'confirmed'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.infoDark,
                    padding: EdgeInsets.symmetric(
                      vertical: ResponsiveHelper.spacing(context, 8),
                    ),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                  ),
                  child: Text(
                    '네, 출근합니다',
                    style: ResponsiveHelper.smallStyle(context)
                        .copyWith(color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 노쇼/결근 안내 배너
  Widget _buildNoShowBanner(String status) {
    final isNoShow = status == AttendanceModel.statusNoShow;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 12)),
      decoration: BoxDecoration(
        color: isNoShow ? AppColors.errorBg : AppColors.warningBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isNoShow ? AppColors.errorLight : AppColors.warningLight,
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.block,
            color: isNoShow ? AppColors.errorDark : AppColors.warningDark,
            size: ResponsiveHelper.iconSize(context, 20),
          ),
          SizedBox(width: ResponsiveHelper.spacing(context, 8)),
          Text(
            isNoShow ? '노쇼 처리됨' : '결근 처리됨',
            style: ResponsiveHelper.bodyStyle(context).copyWith(
              fontWeight: FontWeight.bold,
              color: isNoShow ? AppColors.errorDark : AppColors.warningDark,
            ),
          ),
        ],
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