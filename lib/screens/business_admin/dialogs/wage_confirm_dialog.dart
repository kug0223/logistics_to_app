// lib/screens/business_admin/dialogs/wage_confirm_dialog.dart
// 급여 확정 다이얼로그 - 탭 구조
//
// 탭 1: 미확정 (pending) → 급여 계산·확정 → calculated
// 탭 2: 확정내역 (calculated + confirmed) → 수정·취소 가능 / 최종확정은 당일명단 마감 버튼에서 일괄 처리
// 탭 3: 마감내역 (transferred) → 읽기전용

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';

// Models
import '../../../models/core/application_model.dart';
import '../../../models/core/attendance_model.dart';
import '../../../models/core/user_model.dart';
import '../../../models/core/wage_detail_model.dart';

// Utils
import '../../../utils/attendance_badge_helper.dart';
import '../../../utils/toast_helper.dart';
import '../../../utils/responsive_helper.dart';
import '../../../utils/format_helper.dart';
import '../../../utils/dialog_helper.dart';
import '../../../utils/wage_calculator.dart';
import '../../../utils/work_detail_helper.dart';
import '../../../services/tax_deduction_service.dart';
import '../../../models/core/insurance_rate_model.dart';
import '../../../theme/app_colors.dart';
import '../../../widgets/common/app_checkbox.dart';
import '../../../widgets/common/app_tab_label.dart';
import '../../../widgets/common/app_empty_state.dart';

import '../../../widgets/dialogs/wage/wage_detail_dialog.dart';
import '../../../widgets/dialogs/styled_dialog.dart';
import '../../../models/core/notification_model.dart';
import '../../../services/firestore_service.dart';

// Providers
import '../../../providers/user_provider.dart';
import '../../../utils/payment_due_date_calculator.dart';
import '../../../services/trust_score_service.dart';

/// 급여 확정 다이얼로그
class WageConfirmDialog extends StatefulWidget {
  final DateTime date;
  final String businessId;
  final String businessName;
  final List<ApplicationModel> workers;
  final Map<String, AttendanceModel> attendanceMap;
  final Map<String, UserModel> userMap;
  final Map<String, dynamic> workDetailTimeMap;
  final VoidCallback? onConfirmed;
  final VoidCallback? onClose;

  const WageConfirmDialog({
    super.key,
    required this.date,
    required this.businessId,
    required this.businessName,
    required this.workers,
    required this.attendanceMap,
    required this.userMap,
    required this.workDetailTimeMap,
    this.onConfirmed,
    this.onClose,
  });

  @override
  State<WageConfirmDialog> createState() => _WageConfirmDialogState();
}

class _WageConfirmDialogState extends State<WageConfirmDialog> with SingleTickerProviderStateMixin {
  // ═══════════════════════════════════════════════════════════
  // 상태 변수
  // ═══════════════════════════════════════════════════════════
  
  final _firestoreService = FirestoreService();

  late TabController _tabController;
  bool _isProcessing = false;
  bool _isInitializing = true;
  bool _hasChanges = false;
  
  // 선택 상태 (탭별로 분리)
  final Set<String> _pendingSelectedIds = {};
  final Set<String> _calculatedSelectedIds = {};
  final Set<String> _transferredSelectedIds = {};
  
  // 계산된 급여 정보 캐시
  final Map<String, WageDetailModel> _calculatedWages = {};

  // 파트+시간대 그룹별 칩 선택 상태 — key: workType_startTime_endTime
  final Map<String, int> _groupExtraBreakMinutes = {};

  // 근무자별 실제 적용된 추가공제 시간 (선택된 근무자만 반영)
  final Map<String, int> _workerExtraBreakMinutes = {};
  
  // 근무자 목록 (상태별 분리)
  List<ApplicationModel> _pendingWorkers = [];      // 미확정 (퇴근완료, pending)
  List<ApplicationModel> _calculatedWorkers = [];   // 급여확정 (calculated + confirmed)
  List<ApplicationModel> _transferredWorkers = [];  // 마감완료 (transferred)

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _initData();  // async지만 initState에서 호출 가능 (await 없이)
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  /// 초기 데이터 설정 (async로 변경)
  Future<void> _initData() async {
    _pendingWorkers = [];
    _calculatedWorkers = [];
    _transferredWorkers = [];

    final seenIds = <String>{};
    for (var app in widget.workers) {
      if (!seenIds.add(app.id)) continue; // 중복 entry 방어
      final attendance = widget.attendanceMap[app.id];
      if (attendance == null) continue;

      // 퇴근 완료된 근무자만
      if (attendance.checkOut == null) continue;

      // 마감내역(wageConfirmed, wageTransferred): adminConfirmed 관계없이 항상 표시
      if (attendance.wageStatus == AttendanceModel.wageConfirmed ||
          attendance.wageStatus == AttendanceModel.wageTransferred) {
        _transferredWorkers.add(app);
        continue;
      }

      // 미확정·확정내역: adminConfirmed 된 인원만
      if (attendance.adminConfirmed != true) continue;

      // 확정내역: wageCalculated(급여확정)
      if (attendance.wageStatus == AttendanceModel.wageCalculated) {
        _calculatedWorkers.add(app);
      // 미확정: wagePending만
      } else if (attendance.wageStatus == AttendanceModel.wagePending) {
        _pendingWorkers.add(app);
      }
    }

    // 미확정 탭: 이름순
    String nameOf(ApplicationModel app) => widget.userMap[app.uid]?.name ?? '';
    _pendingWorkers.sort((a, b) => nameOf(a).compareTo(nameOf(b)));

    // 급여 미리 계산 (async)
    await _calculateAllWages();

    // 확정내역 탭: 금액 높은순 (계산 완료 후 정렬 — 이상값 빠른 탐지)
    _calculatedWorkers.sort((a, b) {
      final wA = _calculatedWages[a.id]?.effectiveNetWage ?? 0;
      final wB = _calculatedWages[b.id]?.effectiveNetWage ?? 0;
      return wB.compareTo(wA);
    });

    // 계산 완료 후 UI 갱신 + 초기화 플래그 해제
    if (mounted) setState(() { _isInitializing = false; });
  }

  /// 파트+시간대 그룹 키 생성
  String _getGroupKey(ApplicationModel app) =>
      '${app.selectedWorkType}_${app.startTime}_${app.endTime}';

  /// 전체 급여 계산 — Future.wait으로 병렬 처리
  Future<void> _calculateAllWages() async {
    final allWorkers = [..._pendingWorkers, ..._calculatedWorkers, ..._transferredWorkers];
    final results = await Future.wait(
      allWorkers.map((app) async {
        final extra = _workerExtraBreakMinutes[app.id] ?? 0;
        final wage = await _calculateWageForWorker(app, extraBreakMinutes: extra);
        return (id: app.id, wage: wage);
      }),
    );
    for (final r in results) {
      if (r.wage != null) _calculatedWages[r.id] = r.wage!;
    }
  }

  /// workDetailTimeMap에서 예정 휴게시간 조회
  int _getScheduledBreakMinutes(ApplicationModel app) =>
      WorkDetailHelper.breakMinutes(WorkDetailHelper.resolve(app, widget.workDetailTimeMap));

  /// 연장근무 여부 확인 — 석식/야식공제 적용 가능 조건
  bool _workerHasOvertime(ApplicationModel app) {
    final attendance = widget.attendanceMap[app.id];
    if (attendance?.checkIn == null || attendance?.checkOut == null) return false;
    final elapsed = WageCalculator.elapsedMinutes(attendance!.checkIn!, attendance.checkOut!);
    final schedBreak = _getScheduledBreakMinutes(app);
    final effStart = WorkDetailHelper.effectiveStart(app, widget.workDetailTimeMap);
    final effEnd = WorkDetailHelper.effectiveEnd(app, widget.workDetailTimeMap);
    final scheduledElapsed = WageCalculator.elapsedMinutes(effStart, effEnd);
    final scheduledWorkMins = (scheduledElapsed - schedBreak).clamp(0, 9999);
    final actualWorkMins = (elapsed - schedBreak).clamp(0, 9999);
    return actualWorkMins > scheduledWorkMins;
  }

  /// 그룹 추가 공제 시간 변경 → 선택된 근무자만 급여 재계산
  Future<void> _setGroupBreak(List<ApplicationModel> groupWorkers, int extraMinutes) async {
    final key = _getGroupKey(groupWorkers.first);
    final selectedInGroup = groupWorkers.where((a) => _pendingSelectedIds.contains(a.id)).toList();

    // 선택된 근무자 extra break 반영 — 한 번에 setState
    setState(() {
      _groupExtraBreakMinutes[key] = extraMinutes;
      for (final app in selectedInGroup) {
        _workerExtraBreakMinutes[app.id] = extraMinutes;
      }
    });

    // 급여 병렬 계산 후 한 번에 반영
    final results = await Future.wait(
      selectedInGroup.map((app) async {
        final wage = await _calculateWageForWorker(app, extraBreakMinutes: extraMinutes, forceRecalculate: true);
        return (id: app.id, wage: wage);
      }),
    );
    if (!mounted) return;
    setState(() {
      for (final r in results) {
        if (r.wage != null) _calculatedWages[r.id] = r.wage!;
      }
    });
  }

  /// 근무자 체크박스 토글 — 신규 선택 시 그룹 칩 값 동기화 및 급여 재계산
  Future<void> _handleWorkerCheckboxTap(ApplicationModel app, Set<String> selectedIds) async {
    final wasSelected = selectedIds.contains(app.id);
    setState(() {
      if (wasSelected) {
        selectedIds.remove(app.id);
      } else {
        selectedIds.add(app.id);
      }
    });
    if (!wasSelected) {
      final groupKey = _getGroupKey(app);
      final groupExtra = _groupExtraBreakMinutes[groupKey] ?? 0;
      if (groupExtra > 0) {
        setState(() => _workerExtraBreakMinutes[app.id] = groupExtra);
        final wage = await _calculateWageForWorker(app, extraBreakMinutes: groupExtra, forceRecalculate: true);
        if (wage != null && mounted) {
          setState(() => _calculatedWages[app.id] = wage);
        }
      }
    }
  }

  /// 개별 급여 계산 (async로 변경)
  Future<WageDetailModel?> _calculateWageForWorker(
    ApplicationModel app, {
    int extraBreakMinutes = 0,
    bool forceRecalculate = false,
  }) async {
    final attendance = widget.attendanceMap[app.id];
    if (attendance == null || attendance.checkIn == null || attendance.checkOut == null) {
      return null;
    }

    // 이미 계산된 급여가 있으면 그것 사용 (calculated 상태), 강제 재계산 시 제외
    // 단, 미확정 급여는 TO 수정으로 effective 스케줄 시간이 달라진 경우 캐시 무효화 → 재계산
    if (!forceRecalculate && attendance.wageDetail != null) {
      // 1차 확정된 급여는 TO 수정과 무관하게 보존
      if (attendance.wageDetail!.isCalculated) return attendance.wageDetail;
      // 미확정: TO 수정으로 스케줄 시간이 변경된 경우 캐시 무효화
      final effStart = WorkDetailHelper.effectiveStart(app, widget.workDetailTimeMap);
      final effEnd = WorkDetailHelper.effectiveEnd(app, widget.workDetailTimeMap);
      if (effStart == app.startTime && effEnd == app.endTime) {
        return attendance.wageDetail;
      }
      debugPrint('⚠️ TO 수정 감지(미확정): ${app.startTime}→$effStart, ${app.endTime}→$effEnd → 재계산');
    }
    
    // 스케줄 시간: workDetailTimeMap 우선 (TO 수정 반영) → app 필드 폴백
    final scheduledStart = WorkDetailHelper.effectiveStart(app, widget.workDetailTimeMap);
    final scheduledEnd = WorkDetailHelper.effectiveEnd(app, widget.workDetailTimeMap);
    final baseWage = app.wage;
    
    // ✅ wageType, breakMinutes, nightAllowanceApplied, nightIncluded는 workDetailTimeMap에서 먼저 확인
    String wageType = 'hourly';
    int breakMinutes = 0;
    bool nightAllowanceApplied = true;
    bool nightIncluded = false;
    int? baseHourlyWage;
    String taxDeductionType = InsuranceRateModel.typeNone;

    // 1순위: 이미 로드된 workDetailTimeMap에서 가져오기
    // composite key(workDetailId) 우선, 없으면 workType(selectedWorkType) 폴백
    final detail = WorkDetailHelper.resolve(app, widget.workDetailTimeMap);

    if (detail != null) {
      wageType = WorkDetailHelper.wageType(detail);
      breakMinutes = WorkDetailHelper.breakMinutes(detail);
      nightAllowanceApplied = WorkDetailHelper.nightAllowanceApplied(detail);
      nightIncluded = WorkDetailHelper.nightIncluded(detail);
      baseHourlyWage = WorkDetailHelper.baseHourlyWage(detail);
      taxDeductionType = WorkDetailHelper.taxDeductionType(detail);
      debugPrint('✅ WorkDetail 캐시 사용: wageType=$wageType, taxDeductionType=$taxDeductionType');
    }
    // 2순위: Firestore 문서에서 직접 조회 (슬롯 우선 → TO 폴백)
    else if (app.toId != null && app.toId!.isNotEmpty) {
      try {
        // 슬롯 수정이 TO 템플릿과 다를 수 있으므로 슬롯 문서를 우선 조회
        List<dynamic> rawWorkDetails = [];
        String source = '';

        if (app.slotId != null && app.slotId!.isNotEmpty) {
          final slotDoc = await FirebaseFirestore.instance
              .collection('tos')
              .doc(app.toId)
              .collection('slots')
              .doc(app.slotId)
              .get();
          if (slotDoc.exists) {
            final slotWorkDetails = slotDoc.data()?['workDetails'] as List<dynamic>?;
            if (slotWorkDetails != null && slotWorkDetails.isNotEmpty) {
              rawWorkDetails = slotWorkDetails;
              source = 'slot';
            }
          }
        }

        // 슬롯에 workDetails 없으면 TO 문서 폴백
        if (rawWorkDetails.isEmpty) {
          final toDoc = await FirebaseFirestore.instance
              .collection('tos')
              .doc(app.toId)
              .get();
          if (toDoc.exists) {
            rawWorkDetails = toDoc.data()?['workDetails'] as List<dynamic>? ?? [];
            source = 'to';
          }
        }

        for (var wd in rawWorkDetails) {
          final wdMap = Map<String, dynamic>.from(wd as Map);
          final wdType = wdMap['workType'] as String? ?? '';
          final wdComposite = '${wdType}_${wdMap['startTime'] ?? ''}_${wdMap['endTime'] ?? ''}';
          if (wdType == app.selectedWorkType || wdComposite == app.workDetailId) {
            wageType = wdMap['wageType'] ?? 'hourly';
            breakMinutes = wdMap['breakMinutes'] ?? 0;
            nightAllowanceApplied = wdMap['nightAllowanceApplied'] ?? true;
            nightIncluded = wdMap['nightIncluded'] as bool? ?? false;
            baseHourlyWage = (wdMap['baseHourlyWage'] as num?)?.toInt();
            taxDeductionType = wdMap['taxDeductionType'] as String? ?? InsuranceRateModel.typeNone;
            debugPrint('✅ WorkDetail Firestore 조회($source): wageType=$wageType, taxDeductionType=$taxDeductionType');
            break;
          }
        }
      } catch (e) {
        debugPrint('⚠️ WorkDetail 조회 실패: $e');
      }
    } else {
      // toId=null인 지원서(TO 없이 직접 채용된 경우)는 WorkDetail 조회를 건너뛰고,
      // wageType='hourly', breakMinutes=0 기본값으로 계산된다. 이는 의도된 폴백 동작이다.
      debugPrint('⚠️ WorkDetail 조회 불가: toId=${app.toId}, workDetailId=${app.workDetailId}');
    }

    try {
      // 관리자가 직접 선택한 석식/야식공제 그대로 적용
      final effectiveBreak = breakMinutes + extraBreakMinutes;

      final base = WageCalculator.calculate(
        wageType: wageType,
        baseWage: baseWage,
        workDate: widget.date,
        scheduledStart: scheduledStart,
        scheduledEnd: scheduledEnd,
        actualStart: attendance.checkIn!,
        actualEnd: attendance.checkOut!,
        breakMinutes: effectiveBreak,
        scheduledBreakMinutes: breakMinutes,
        nightAllowanceApplied: nightAllowanceApplied,
        nightIncluded: nightIncluded,
        baseHourlyWage: baseHourlyWage,
      );

      return TaxDeductionService.applyDeduction(
        base: base,
        taxDeductionType: taxDeductionType,
        workYear: widget.date.year,
      );
    } catch (e) {
      debugPrint('❌ 급여 계산 실패 (${app.id}): $e');
      return null;
    }
  }

  // ═══════════════════════════════════════════════════════════
  // 급여 확정 처리 (pending → calculated)
  // ═══════════════════════════════════════════════════════════

  /// 전체 미확정 인원 일괄 확정
  Future<void> _confirmAllPending() async {
    if (_isProcessing || _isInitializing || _pendingWorkers.isEmpty) return;
    setState(() {
      _pendingSelectedIds
        ..clear()
        ..addAll(_pendingWorkers.map((app) => app.id));
    });
    await _confirmWages();
  }

  Future<void> _confirmWages() async {
    if (_isProcessing) return;
    if (_pendingSelectedIds.isEmpty) {
      ToastHelper.showWarning('급여 확정할 인원을 선택해주세요');
      return;
    }
    
    final confirmed = await DialogHelper.showConfirm(
      context,
      title: '급여 확정',
      message: '선택한 ${_pendingSelectedIds.length}명의 급여를 확정하시겠습니까?',
      confirmText: '확정',
    );
    
    if (confirmed != true || !mounted) return;

    final adminUid = Provider.of<UserProvider>(context, listen: false).currentUser?.uid;

    // ── 8일 소급 사전 체크 ──────────────────────────────────────
    setState(() => _isProcessing = true);

    try {
      final day8Previews = <String, WageDetailModel>{};
      for (var appId in _pendingSelectedIds) {
        final w = _calculatedWages[appId];
        final att = widget.attendanceMap[appId];
        if (w == null || att == null) continue;
        if (w.taxDeductionType != InsuranceRateModel.typeDailyAuto8) continue;

        final preview = await _checkAndApplyRetroactive(att, w);
        if (preview.retroactiveDeduction > 0) {
          day8Previews[appId] = preview;
        }
      }

      if (day8Previews.isNotEmpty && mounted) {
        // _isProcessing을 false로 내리지 않음 — 다이얼로그 중 버튼 재진입 방지
        final day8Confirmed = await _showDay8RetroactiveWarning(
          day8Previews.entries.map((e) {
            final app = widget.workers.firstWhere(
              (w) => w.id == e.key,
              orElse: () => throw StateError('worker not found: ${e.key}'),
            );
            final user = widget.userMap[app.uid];
            return (
              name: user?.name ?? '근무자',
              retroactive: e.value.retroactiveDeduction,
              gross: e.value.totalAmount,
              net: e.value.effectiveNetWage,
            );
          }).toList(),
        );
        if (!day8Confirmed || !mounted) return;
      }
      // ────────────────────────────────────────────────────────────


      int successCount = 0;
      int failCount = 0;
      final confirmedIds = <String>{};

      for (var appId in _pendingSelectedIds) {
        // 사전 계산된 8일 소급 결과 재사용, 없으면 원본 사용
        var wage = day8Previews[appId] ?? _calculatedWages[appId];
        final attendance = widget.attendanceMap[appId];

        if (wage == null || attendance == null) {
          failCount++;
          continue;
        }

        try {
          // daily_auto_8이지만 8일차가 아닌 경우(1~7일) 처리
          if (_calculatedWages[appId]?.taxDeductionType == InsuranceRateModel.typeDailyAuto8
              && !day8Previews.containsKey(appId)) {
            wage = await _checkAndApplyRetroactive(attendance, _calculatedWages[appId]!);
          }

          final appIdx = widget.workers.indexWhere((w) => w.id == appId);
          final app = appIdx >= 0 ? widget.workers[appIdx] : null;
          final detail = app != null ? WorkDetailHelper.resolve(app, widget.workDetailTimeMap) : null;
          String? payScheduleType = detail?['payScheduleType'] as String?;
          int?    payScheduleDay  = (detail?['payScheduleDay'] as num?)?.toInt();

          // 캐시에 payScheduleType 없으면 Firestore에서 직접 조회
          if (payScheduleType == null && app != null && app.toId != null) {
            try {
              List<dynamic> rawWd = [];
              if (app.slotId != null && app.slotId!.isNotEmpty) {
                final slotDoc = await FirebaseFirestore.instance
                    .collection('tos').doc(app.toId)
                    .collection('slots').doc(app.slotId).get();
                rawWd = slotDoc.data()?['workDetails'] as List<dynamic>? ?? [];
              }
              if (rawWd.isEmpty) {
                final toDoc = await FirebaseFirestore.instance
                    .collection('tos').doc(app.toId).get();
                rawWd = toDoc.data()?['workDetails'] as List<dynamic>? ?? [];
              }
              for (var wd in rawWd) {
                final wdMap = Map<String, dynamic>.from(wd as Map);
                final wdType = wdMap['workType'] as String? ?? '';
                if (wdType == app.selectedWorkType ||
                    '${wdType}_${wdMap['startTime'] ?? ''}_${wdMap['endTime'] ?? ''}' == app.workDetailId) {
                  payScheduleType = wdMap['payScheduleType'] as String?;
                  payScheduleDay  = (wdMap['payScheduleDay'] as num?)?.toInt();
                  debugPrint('✅ payScheduleType Firestore 폴백: $payScheduleType');
                  break;
                }
              }
            } catch (e) {
              debugPrint('⚠️ payScheduleType 조회 실패: $e');
            }
          }

          final yearMonth = _toYearMonth(attendance.workDate);
          final calculatedWage = wage.copyWith(
            calculatedBy: adminUid,
            calculatedAt: DateTime.now(),
            payScheduleType: payScheduleType ?? wage.payScheduleType,
            payScheduleDay:  payScheduleDay  ?? wage.payScheduleDay,
          );

          // 동시 확정 방지 — 현재 wageStatus가 pending인지 트랜잭션으로 검증
          final attRef = FirebaseFirestore.instance
              .collection('attendance')
              .doc(attendance.id);
          await FirebaseFirestore.instance.runTransaction((tx) async {
            final snap = await tx.get(attRef);
            final currentStatus = snap.data()?['wageStatus'] as String?;
            if (currentStatus == AttendanceModel.wageCalculated ||
                currentStatus == AttendanceModel.wageConfirmed ||
                currentStatus == AttendanceModel.wageTransferred) {
              throw Exception('이미 처리된 급여입니다 ($currentStatus)');
            }
            tx.update(attRef, {
              'wageStatus': AttendanceModel.wageCalculated,
              'finalWage': calculatedWage.effectiveNetWage,
              'wageDetail': calculatedWage.toMap(),
              'yearMonth': yearMonth,
              'updatedAt': FieldValue.serverTimestamp(),
            });
          });

          // 8일 소급 적용된 근로자에게 알림 발송
          if (calculatedWage.retroactiveDeduction > 0 && app != null) {
            _firestoreService.createNotification(
              NotificationModel.createRetroactiveDeductionAlert(
                userId: app.uid,
                businessName: widget.businessName,
                businessId: widget.businessId,
                workDate: attendance.workDate,
                retroactiveAmount: calculatedWage.retroactiveDeduction,
                grossWage: calculatedWage.totalAmount,
                netWage: calculatedWage.effectiveNetWage,
                attendanceId: attendance.id,
              ),
            );
          }

          successCount++;
          confirmedIds.add(appId);
          _calculatedWages[appId] = calculatedWage;
        } catch (e) {
          debugPrint('❌ 급여 확정 실패 ($appId): $e');
          failCount++;
        }
      }
      
      if (successCount > 0) {
        _hasChanges = true;
        ToastHelper.showSuccess('$successCount명 급여 확정 완료');
        widget.onConfirmed?.call();
        if (!mounted) return;

        setState(() {
          // 확정된 근무자를 calculated 탭으로 이동
          final pendingMap = {for (final w in _pendingWorkers) w.id: w};
          for (var id in confirmedIds) {
            final worker = pendingMap[id];
            if (worker != null) _calculatedWorkers.add(worker);
          }
          _pendingWorkers.removeWhere((app) => confirmedIds.contains(app.id));
          _pendingSelectedIds.clear();
        });
        // 확정내역 탭으로 자동 이동
        _tabController.animateTo(1);
      }
      
      if (failCount > 0) {
        ToastHelper.showWarning('$failCount명 처리 실패');
      }
    } catch (e) {
      debugPrint('❌ 일괄 급여 확정 실패: $e');
      ToastHelper.showError('급여 확정에 실패했습니다');
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  // ═══════════════════════════════════════════════════════════
  // 8일 소급 헬퍼
  // ═══════════════════════════════════════════════════════════

  String _toYearMonth(DateTime date) => FormatHelper.formatYearMonthISO(date);

  /// daily_auto_8 타입 근무자의 당일 순서(N번째 근무일)를 확인해 소급 계산 적용
  Future<WageDetailModel> _checkAndApplyRetroactive(
    AttendanceModel attendance,
    WageDetailModel wage,
  ) async {
    final yearMonth = _toYearMonth(attendance.workDate);
    final prevDays = await TaxDeductionService.getMonthlyWorkDays(
      userId: attendance.userId,
      businessId: attendance.businessId,
      yearMonth: yearMonth,
      excludeAttendanceId: attendance.id,
    );

    if (prevDays + 1 == 8) {
      // 8일째: 1~7일 소급 공제
      final prevGrossTotal = await _getPrevGrossTotal(
          attendance.userId, attendance.businessId, yearMonth, attendance.id);
      return TaxDeductionService.applyDay8Retroactive(
        day8Base: wage,
        prevGrossTotal: prevGrossTotal,
        workYear: attendance.workDate.year,
      );
    } else if (prevDays + 1 > 8) {
      // 9일 이상: 4대보험 풀 공제 (소급 없음, 소득세 미포함 — 연말정산으로 처리)
      final baseWage = wage.copyWith(
        taxDeductionType: InsuranceRateModel.typeNone,
        employmentInsuranceDeduction: 0,
        nationalPensionDeduction: 0,
        healthInsuranceDeduction: 0,
        ltcInsuranceDeduction: 0,
        incomeTaxDeduction: 0,
        retroactiveDeduction: 0,
        netWage: wage.totalAmount,
      );
      return TaxDeductionService.applyDeduction(
        base: baseWage,
        taxDeductionType: InsuranceRateModel.typeFourInsuranceFixed,
        workYear: attendance.workDate.year,
      );
    }

    return wage; // 1~7일: 그대로 (고용보험만 공제)
  }

  /// 이전 근무일 세전 총액 합계 조회 (8일 소급 계산용)
  Future<int> _getPrevGrossTotal(
    String userId,
    String businessId,
    String yearMonth,
    String excludeId,
  ) async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('attendance')
          .where('userId', isEqualTo: userId)
          .where('businessId', isEqualTo: businessId)
          .where('yearMonth', isEqualTo: yearMonth)
          .where('wageStatus', whereIn: ['calculated', 'confirmed', 'transferred'])
          .get();
      int total = 0;
      for (final doc in snapshot.docs) {
        if (doc.id == excludeId) continue;
        final wageDetail = doc.data()['wageDetail'] as Map<String, dynamic>?;
        total += (wageDetail?['totalAmount'] as num?)?.toInt() ?? 0;
      }
      return total;
    } catch (e) {
      debugPrint('⚠️ 이전 세전 총액 조회 실패: $e');
      rethrow; // 0으로 폴백하면 소급 계산이 오계산됨 — 상위에서 급여 계산 실패로 처리
    }
  }

  // ═══════════════════════════════════════════════════════════
  // 8일차 소급 경고 다이얼로그
  // ═══════════════════════════════════════════════════════════

  Future<bool> _showDay8RetroactiveWarning(
    List<({String name, int retroactive, int gross, int net})> affected,
  ) async {
    if (!mounted) return false;
    return await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        contentPadding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(ctx).size.height * AppDialogSize.subSheetHeightRatio,
        ),
        title: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: AppColors.warning, size: 22),
            const SizedBox(width: 8),
            Expanded(
              child: Text('8일차 소급 공제 안내', style: ResponsiveHelper.subtitleStyle(ctx)),
            ),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '이번 달 8번째 근무일입니다. 1~7일분 4대보험이 소급 공제됩니다.',
                  style: ResponsiveHelper.smallStyle(ctx, color: AppColors.grey700),
                ),
                const SizedBox(height: 12),
                ...affected.map((w) => _buildDay8WarningCard(w.name, w.retroactive, w.gross, w.net)),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppColors.warningBg,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.warningLight),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline, size: 14, color: AppColors.warningDark),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          '확정 시 근로자에게 자동으로 알림이 발송됩니다.',
                          style: ResponsiveHelper.smallStyle(ctx, color: AppColors.warningDark),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소', style: TextStyle(color: AppColors.grey600)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.warning,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('확인 후 진행'),
          ),
        ],
      ),
    ) ?? false;
  }

  Widget _buildDay8WarningCard(String name, int retroactive, int gross, int net) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.grey200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(name, style: ResponsiveHelper.smallStyle(context).copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          _buildWarningInfoRow('소급 공제', '- ${FormatHelper.formatWage(retroactive)}', AppColors.errorDark),
          _buildWarningInfoRow('세전 급여', FormatHelper.formatWage(gross), AppColors.grey700),
          _buildWarningInfoRow('실수령액', FormatHelper.formatWage(net), AppColors.successDark),
        ],
      ),
    );
  }

  Widget _buildWarningInfoRow(String label, String value, Color valueColor) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 70,
            child: Text(label, style: ResponsiveHelper.tinyStyle(context, color: AppColors.grey500)),
          ),
          Text(value, style: ResponsiveHelper.tinyStyle(context, color: valueColor).copyWith(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  // 개별 급여 상세 다이얼로그
  // ═══════════════════════════════════════════════════════════

  Future<void> _showWageDetailDialog(ApplicationModel app, {bool isCalculated = false}) async {
    final wage = _calculatedWages[app.id];
    final user = widget.userMap[app.uid];
    final attendance = widget.attendanceMap[app.id];

    if (wage == null || attendance == null) {
      ToastHelper.showWarning('급여 정보를 계산할 수 없습니다');
      return;
    }

    // wageTransferred는 송금 완료 → 편집 불가(confirmed 모드)
    final isTransferred = attendance.wageStatus == AttendanceModel.wageTransferred;
    final mode = isTransferred
        ? WageDialogMode.confirmed
        : (isCalculated ? WageDialogMode.calculated : WageDialogMode.pending);

    final detail = WorkDetailHelper.resolve(app, widget.workDetailTimeMap);
    final shiftType = WorkDetailHelper.shiftType(detail);
    final nightIncluded = WorkDetailHelper.nightIncluded(detail);
    final schedBreak = WorkDetailHelper.breakMinutes(detail);
    final baseHourlyWage = WorkDetailHelper.baseHourlyWage(detail);

    final result = await WageDetailDialog.show(
      context: context,
      app: app,
      user: user,
      attendance: attendance,
      wage: wage,
      mode: mode,
      businessName: widget.businessName,
      shiftType: shiftType,
      nightIncluded: nightIncluded,
      scheduledBreakMinutes: schedBreak,
      baseHourlyWage: baseHourlyWage,
      effStart: WorkDetailHelper.effectiveStart(app, widget.workDetailTimeMap),
      effEnd: WorkDetailHelper.effectiveEnd(app, widget.workDetailTimeMap),
    );
    
    if (result == null) return;
    
    switch (result.action) {
      case 'confirm':
        await _processIndividualConfirm(app, attendance, result.wage);
        break;
      case 'update':
        await _processWageUpdate(app, attendance, result.wage);
        break;
      case 'cancel':
        await _processWageCancel(app, attendance);
        break;
    }
  }

  /// 개별 급여 확정
  Future<void> _processIndividualConfirm(ApplicationModel app, AttendanceModel attendance, WageDetailModel wage) async {
    try {
      final userProvider = Provider.of<UserProvider>(context, listen: false);
      final adminUid = userProvider.currentUser?.uid;
      final user = widget.userMap[app.uid];

      // 8일 소급 체크 및 경고
      var finalWage = wage;
      if (wage.taxDeductionType == InsuranceRateModel.typeDailyAuto8) {
        finalWage = await _checkAndApplyRetroactive(attendance, wage);
        if (finalWage.retroactiveDeduction > 0 && mounted) {
          final confirmed = await _showDay8RetroactiveWarning([
            (
              name: user?.name ?? '근무자',
              retroactive: finalWage.retroactiveDeduction,
              gross: finalWage.totalAmount,
              net: finalWage.effectiveNetWage,
            ),
          ]);
          if (!confirmed || !mounted) return;
        }
      }

      // payScheduleType 조회 (_confirmWages와 동일한 경로)
      final detail = WorkDetailHelper.resolve(app, widget.workDetailTimeMap);
      String? payScheduleType = detail?['payScheduleType'] as String?;
      int?    payScheduleDay  = (detail?['payScheduleDay'] as num?)?.toInt();

      if (payScheduleType == null && app.toId != null) {
        try {
          List<dynamic> rawWd = [];
          if (app.slotId != null && app.slotId!.isNotEmpty) {
            final slotDoc = await FirebaseFirestore.instance
                .collection('tos').doc(app.toId)
                .collection('slots').doc(app.slotId).get();
            rawWd = slotDoc.data()?['workDetails'] as List<dynamic>? ?? [];
          }
          if (rawWd.isEmpty) {
            final toDoc = await FirebaseFirestore.instance
                .collection('tos').doc(app.toId).get();
            rawWd = toDoc.data()?['workDetails'] as List<dynamic>? ?? [];
          }
          for (var wd in rawWd) {
            final wdMap = Map<String, dynamic>.from(wd as Map);
            final wdType = wdMap['workType'] as String? ?? '';
            if (wdType == app.selectedWorkType ||
                '${wdType}_${wdMap['startTime'] ?? ''}_${wdMap['endTime'] ?? ''}' == app.workDetailId) {
              payScheduleType = wdMap['payScheduleType'] as String?;
              payScheduleDay  = (wdMap['payScheduleDay'] as num?)?.toInt();
              break;
            }
          }
        } catch (e) {
          debugPrint('⚠️ payScheduleType 조회 실패: $e');
        }
      }

      final yearMonth = _toYearMonth(attendance.workDate);
      final calculatedWage = finalWage.copyWith(
        calculatedBy: adminUid,
        calculatedAt: DateTime.now(),
        payScheduleType: payScheduleType ?? finalWage.payScheduleType,
        payScheduleDay:  payScheduleDay  ?? finalWage.payScheduleDay,
      );

      final attRef = FirebaseFirestore.instance
          .collection('attendance')
          .doc(attendance.id);
      await FirebaseFirestore.instance.runTransaction((tx) async {
        final snap = await tx.get(attRef);
        final currentStatus = snap.data()?['wageStatus'] as String?;
        if (currentStatus == AttendanceModel.wageCalculated ||
            currentStatus == AttendanceModel.wageConfirmed ||
            currentStatus == AttendanceModel.wageTransferred) {
          throw Exception('이미 처리된 급여입니다 ($currentStatus)');
        }
        tx.update(attRef, {
          'wageStatus': 'calculated',
          'finalWage': calculatedWage.effectiveNetWage,
          'wageDetail': calculatedWage.toMap(),
          'yearMonth': yearMonth,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      });

      if (calculatedWage.retroactiveDeduction > 0) {
        _firestoreService.createNotification(
          NotificationModel.createRetroactiveDeductionAlert(
            userId: app.uid,
            businessName: widget.businessName,
            businessId: widget.businessId,
            workDate: attendance.workDate,
            retroactiveAmount: calculatedWage.retroactiveDeduction,
            grossWage: calculatedWage.totalAmount,
            netWage: calculatedWage.effectiveNetWage,
            attendanceId: attendance.id,
          ),
        );
      }

      _hasChanges = true;
      widget.onConfirmed?.call();

      if (mounted) {
        setState(() {
          _calculatedWages[app.id] = calculatedWage;
          _pendingWorkers.removeWhere((w) => w.id == app.id);
          _calculatedWorkers.add(app);
          _pendingSelectedIds.remove(app.id);
        });
      }
      
      ToastHelper.showSuccess('${user?.name ?? '근무자'} 급여 확정 완료');
    } catch (e) {
      debugPrint('❌ 개별 급여 확정 실패: $e');
      ToastHelper.showError('급여 확정에 실패했습니다');
    }
  }

  /// 급여 수정
  Future<void> _processWageUpdate(ApplicationModel app, AttendanceModel attendance, WageDetailModel wage) async {
    try {
      final userProvider = Provider.of<UserProvider>(context, listen: false);
      final adminUid = userProvider.currentUser?.uid;
      final user = widget.userMap[app.uid];
      
      final updatedWage = wage.copyWith(
        calculatedBy: adminUid,
        calculatedAt: DateTime.now(),
      );
      
      // 급여 수정은 이미 calculated 상태인 기록만 대상이며, 단일 관리자가 수정하는 흐름이
      // 일반적이므로 트랜잭션을 사용하지 않는다. 동시 수정 시 last-write-wins이지만
      // 실용적으로 충돌 빈도가 매우 낮아 의도적으로 허용한다.
      await FirebaseFirestore.instance
          .collection('attendance')
          .doc(attendance.id)
          .update({
        'finalWage': updatedWage.effectiveNetWage,
        'wageDetail': updatedWage.toMap(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      _hasChanges = true;
      widget.onConfirmed?.call();
      
      if (mounted) {
        setState(() {
          _calculatedWages[app.id] = updatedWage;
        });
      }
      
      ToastHelper.showSuccess('${user?.name ?? '근무자'} 급여 수정 완료');
    } catch (e) {
      debugPrint('❌ 급여 수정 실패: $e');
      ToastHelper.showError('급여 수정에 실패했습니다');
    }
  }


  /// 급여 취소 (calculated → pending)
  Future<void> _processWageCancel(ApplicationModel app, AttendanceModel attendance) async {
    try {
      final user = widget.userMap[app.uid];
      
      await FirebaseFirestore.instance
          .collection('attendance')
          .doc(attendance.id)
          .update({
        'wageStatus': AttendanceModel.wagePending,
        'finalWage': FieldValue.delete(),
        'wageDetail': FieldValue.delete(),
        // yearMonth도 함께 삭제 — pending 복귀 시 _getPrevGrossTotal 집계에서 제외되지만,
        // 재확정 전까지 stale 필드가 남아있으면 DB 정합성이 어긋나므로 명시적으로 삭제
        'yearMonth': FieldValue.delete(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      
      _hasChanges = true;
      widget.onConfirmed?.call();

      // 급여 확정 취소 알림 발송 (calculated→pending: 지원자에게 재조정 안내)
      _firestoreService.createNotification(
        NotificationModel.createWageCancelConfirmed(
          userId: app.uid,
          businessName: widget.businessName,
          businessId: widget.businessId,
          workDate: attendance.workDate,
          attendanceId: attendance.id,
        ),
      );

      // 급여 재계산 (근무자별 추가 공제 유지, 재계산만)
      final extra = _workerExtraBreakMinutes[app.id] ?? 0;
      final newWage = await _calculateWageForWorker(app, extraBreakMinutes: extra);
      
      if (mounted) {
        setState(() {
          _calculatedWorkers.removeWhere((w) => w.id == app.id);
          _pendingWorkers.add(app);
          _calculatedSelectedIds.remove(app.id);
          if (newWage != null) {
            _calculatedWages[app.id] = newWage;
          }
        });
      }
      
      ToastHelper.showSuccess('${user?.name ?? '근무자'} 급여 확정 취소');
    } catch (e) {
      debugPrint('❌ 급여 취소 실패: $e');
      ToastHelper.showError('급여 취소에 실패했습니다');
    }
  }

  /// 선택된 인원 일괄 급여 확정 취소
  Future<void> _cancelSelectedWages() async {
    if (_calculatedSelectedIds.isEmpty) return;

    final count = _calculatedSelectedIds.length;
    final confirmed = await DialogHelper.showDangerConfirm(
      context,
      title: '급여 확정 취소',
      message: '선택한 $count명의 급여 확정을 취소하시겠습니까?\n미확정 상태로 되돌아갑니다.',
      confirmText: '취소',
    );
    if (!confirmed) return;

    setState(() => _isProcessing = true);
    try {
      final ids = List<String>.from(_calculatedSelectedIds);
      // 루프 전에 앱 스냅샷 확보 — _processWageCancel 내부 setState가 _calculatedWorkers를 수정하기 때문
      final appSnapshots = <String, ApplicationModel>{};
      for (final id in ids) {
        final matches = _calculatedWorkers.where((a) => a.id == id);
        if (matches.isNotEmpty) appSnapshots[id] = matches.first;
      }
      for (final appId in ids) {
        final app = appSnapshots[appId];
        if (app == null) continue;
        final attendance = widget.attendanceMap[appId];
        if (attendance == null) continue;
        await _processWageCancel(app, attendance);
      }
      ToastHelper.showSuccess('$count명 급여 확정 취소 완료');
    } catch (e) {
      debugPrint('❌ 일괄 급여 취소 실패: $e');
      ToastHelper.showError('급여 확정 취소에 실패했습니다');
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  /// 선택된 wageCalculated 항목 → wageConfirmed 마감 처리
  Future<void> _closeWages() async {
    // 선택된 항목 중 wageCalculated 상태인 것만 처리
    final targetIds = _calculatedSelectedIds.where((id) {
      final att = widget.attendanceMap[id];
      return att?.wageStatus == AttendanceModel.wageCalculated;
    }).toList();

    if (targetIds.isEmpty) {
      ToastHelper.showWarning('마감할 항목이 없습니다 (이미 마감됐거나 선택 없음)');
      return;
    }

    final confirmed = await DialogHelper.showConfirm(
      context,
      title: '마감',
      message: '선택한 ${targetIds.length}명을 마감하시겠습니까?\n마감 후에는 급여 취소가 불가합니다.',
      confirmText: '마감',
    );
    if (confirmed != true || !mounted) return;

    final adminUid = Provider.of<UserProvider>(context, listen: false).currentUser?.uid;
    setState(() => _isProcessing = true);

    int successCount = 0;
    int failCount = 0;
    try {
      var batch = FirebaseFirestore.instance.batch();
      int batchCount = 0;
      final processedApps = <ApplicationModel>[];

      for (final appId in targetIds) {
        final attendance = widget.attendanceMap[appId];
        if (attendance == null) { failCount++; continue; }
        final app = _calculatedWorkers.firstWhere((a) => a.id == appId, orElse: () => throw StateError(''));

        final wd = attendance.wageDetail ?? _calculatedWages[appId];
        final paymentDueDate = PaymentDueDateCalculator.calculate(
          payScheduleType: wd?.payScheduleType,
          payScheduleDay:  wd?.payScheduleDay,
          workDate: attendance.workDate,
        );
        final confirmedWageDetail = wd?.copyWith(
          confirmedBy: adminUid,
          confirmedAt: DateTime.now(),
        );

        batch.update(
          FirebaseFirestore.instance.collection('attendance').doc(attendance.id),
          {
            'wageStatus': AttendanceModel.wageConfirmed,
            'finalConfirmedAt': FieldValue.serverTimestamp(),
            if (adminUid != null) 'confirmedBy': adminUid,
            if (confirmedWageDetail != null) 'wageDetail': confirmedWageDetail.toMap(),
            if (paymentDueDate != null) 'paymentDueDate': Timestamp.fromDate(paymentDueDate),
          },
        );
        // totalWorkDays 클라이언트 직접 업데이트 — 의도된 설계.
        // Cloud Function 이관이 이상적이나 현재 단계에서는 클라이언트 처리.
        // FieldValue.increment로 동시 접근 시 원자성 보장.
        batch.update(
          FirebaseFirestore.instance.collection('users').doc(app.uid),
          {'totalWorkDays': FieldValue.increment(1)},
        );
        batchCount += 2;
        processedApps.add(app);

        if (batchCount >= 498) {
          await batch.commit();
          successCount += batchCount ~/ 2;
          batch = FirebaseFirestore.instance.batch();
          batchCount = 0;
        }
      }
      if (batchCount > 0) {
        await batch.commit();
        successCount += batchCount ~/ 2;
      }

      // 신뢰도 업데이트 + 지원자 알림
      for (final app in processedApps) {
        try {
          await TrustScoreService().onWorkComplete(app.uid, app.businessId);
        } catch (e) {
          debugPrint('⚠️ 신뢰도 업데이트 실패 (${app.uid}): $e');
        }
        final att = widget.attendanceMap[app.id];
        if (att != null) {
          // att.finalWage는 다이얼로그 오픈 시점 스냅샷이므로 0일 수 있음.
          // 방금 계산한 _calculatedWages 값을 우선 사용하고, 없으면 att.finalWage로 fallback.
          final wageAmount = _calculatedWages[app.id]?.effectiveNetWage ?? att.finalWage ?? 0;
          _firestoreService.createNotification(
            NotificationModel.createWageConfirmed(
              userId: app.uid,
              businessName: widget.businessName,
              businessId: widget.businessId,
              workDate: att.workDate,
              totalWage: wageAmount,
              attendanceId: att.id,
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('❌ 마감 처리 실패: $e');
      failCount = targetIds.length - successCount;
    }

    if (!mounted) {
      // dispose 이후에도 _isProcessing 플래그 반드시 복원
      _isProcessing = false;
      return;
    }
    _hasChanges = true;
    widget.onClose?.call();

    // UI 상태 업데이트: 처리된 항목을 확정내역 → 마감내역으로 이동
    setState(() {
      final processed = targetIds.toSet();
      final moved = _calculatedWorkers.where((a) => processed.contains(a.id)).toList();
      _calculatedWorkers.removeWhere((a) => processed.contains(a.id));
      _transferredWorkers.addAll(moved);
      _calculatedSelectedIds.removeAll(processed);
      _isProcessing = false;
    });

    if (failCount == 0) {
      ToastHelper.showSuccess('$successCount명 마감 완료');
    } else {
      ToastHelper.showWarning('$successCount명 완료, $failCount명 실패');
    }
    // 마감내역 탭으로 자동 이동
    _tabController.animateTo(2);
  }

  /// 선택된 wageConfirmed 항목 → wageCalculated 마감 취소 처리
  Future<void> _reverseCloseWages() async {
    final targetIds = _transferredSelectedIds.where((id) {
      final att = widget.attendanceMap[id];
      return att?.wageStatus == AttendanceModel.wageConfirmed;
    }).toList();

    if (targetIds.isEmpty) {
      ToastHelper.showWarning('취소할 항목이 없습니다 (이미 송금 완료된 항목은 취소 불가)');
      return;
    }

    final confirmed = await DialogHelper.showConfirm(
      context,
      title: '마감 취소',
      message: '선택한 ${targetIds.length}명을 확정내역으로 되돌리시겠습니까?',
      confirmText: '마감 취소',
    );
    if (confirmed != true || !mounted) return;

    setState(() => _isProcessing = true);

    int successCount = 0;
    int failCount = 0;
    try {
      var batch = FirebaseFirestore.instance.batch();
      int batchCount = 0;

      for (final appId in targetIds) {
        final attendance = widget.attendanceMap[appId];
        if (attendance == null) { failCount++; continue; }
        final app = _transferredWorkers.firstWhere(
          (a) => a.id == appId,
          orElse: () => throw StateError('app not found: $appId'),
        );

        batch.update(
          FirebaseFirestore.instance.collection('attendance').doc(attendance.id),
          {
            'wageStatus': AttendanceModel.wageCalculated,
            'finalConfirmedAt': FieldValue.delete(),
            // wageDetail 내 confirm 정보도 삭제 — 재마감 시 이전 확정자 정보 잔류 방지
            'wageDetail.confirmedBy': FieldValue.delete(),
            'wageDetail.confirmedAt': FieldValue.delete(),
          },
        );
        // _closeWages에서 increment(1)했으므로 취소 시 되돌림
        batch.update(
          FirebaseFirestore.instance.collection('users').doc(app.uid),
          {'totalWorkDays': FieldValue.increment(-1)},
        );
        batchCount += 2;

        if (batchCount >= 498) {
          await batch.commit();
          successCount += batchCount ~/ 2;
          batch = FirebaseFirestore.instance.batch();
          batchCount = 0;
        }
      }
      if (batchCount > 0) {
        await batch.commit();
        successCount += batchCount ~/ 2;
      }

      // 마감 취소 알림 발송 (batch 성공 후)
      for (final appId in targetIds) {
        final attendance = widget.attendanceMap[appId];
        if (attendance == null) continue;
        final app = _transferredWorkers.where((a) => a.id == appId).firstOrNull;
        if (app == null) continue;
        _firestoreService.createNotification(
          NotificationModel.createWageCancelConfirmed(
            userId: app.uid,
            businessName: widget.businessName,
            businessId: widget.businessId,
            workDate: attendance.workDate,
            attendanceId: attendance.id,
          ),
        );
      }
    } catch (e) {
      debugPrint('❌ 마감 취소 실패: $e');
      failCount = targetIds.length - successCount;
    }

    if (!mounted) {
      _isProcessing = false;
      return;
    }
    _hasChanges = true;
    widget.onClose?.call();

    final processed = targetIds.toSet();
    setState(() {
      final moved = _transferredWorkers.where((a) => processed.contains(a.id)).toList();
      _transferredWorkers.removeWhere((a) => processed.contains(a.id));
      _calculatedWorkers.addAll(moved);
      _transferredSelectedIds.removeAll(processed);
      _isProcessing = false;
      // attendanceMap 로컬 상태 갱신 — 마감 취소 후 재마감 시 wageCalculated로 인식하도록
      for (final id in processed) {
        final att = widget.attendanceMap[id];
        if (att != null) {
          widget.attendanceMap[id] = att.copyWith(wageStatus: AttendanceModel.wageCalculated);
        }
      }
    });

    if (failCount == 0) {
      ToastHelper.showSuccess('$successCount명 마감 취소 완료');
    } else {
      ToastHelper.showWarning('$successCount명 완료, $failCount명 실패');
    }
    _tabController.animateTo(1);
  }

  // ═══════════════════════════════════════════════════════════
  // 합계 계산
  // ═══════════════════════════════════════════════════════════

  int _getSelectedTotal(Set<String> selectedIds) {
    int total = 0;
    for (var appId in selectedIds) {
      total += _calculatedWages[appId]?.effectiveNetWage ?? 0;
    }
    return total;
  }

  // ═══════════════════════════════════════════════════════════
  // UI 빌드
  // ═══════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dateStr = FormatHelper.formatDateKorean(widget.date);
    final screenHeight = MediaQuery.sizeOf(context).height;

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
        insetPadding: const EdgeInsets.symmetric(
          horizontal: AppDialogSize.insetH,
          vertical: AppDialogSize.insetV,
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: screenHeight * AppDialogSize.maxHeightRatio),
          child: Column(
            children: [
              _buildHeader(context, theme, dateStr),
              _buildTabBar(context, theme),
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _buildPendingTab(context, theme),
                    _buildCalculatedTab(context, theme),
                    _buildTransferredTab(context, theme),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 헤더
  Widget _buildHeader(BuildContext context, ThemeData theme, String dateStr) {
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
          topLeft: Radius.circular(ResponsiveHelper.spacing(context, 20)),
          topRight: Radius.circular(ResponsiveHelper.spacing(context, 20)),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 10)),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(ResponsiveHelper.spacing(context, 12)),
            ),
            child: Icon(
              Icons.payments,
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
                  '급여 관리',
                  style: ResponsiveHelper.subtitleStyle(context).copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: ResponsiveHelper.spacing(context, 2)),
                Text(
                  '$dateStr · ${widget.businessName}',
                  style: ResponsiveHelper.smallStyle(context).copyWith(
                    color: Colors.white.withValues(alpha: 0.9),
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => Navigator.pop(context, _hasChanges),
            icon: Icon(
              Icons.close,
              color: Colors.white,
              size: ResponsiveHelper.iconSize(context, 24),
            ),
          ),
        ],
      ),
    );
  }

  /// 탭바
  Widget _buildTabBar(BuildContext context, ThemeData theme) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: theme.dividerColor)),
      ),
      child: TabBar(
        controller: _tabController,
        labelColor: theme.primaryColor,
        unselectedLabelColor: AppColors.grey500,
        indicatorColor: theme.primaryColor,
        indicatorWeight: 3,
        labelStyle: ResponsiveHelper.bodyStyle(context).copyWith(fontWeight: FontWeight.bold),
        unselectedLabelStyle: ResponsiveHelper.bodyStyle(context),
        tabs: [
          Tab(
            child: AppTabLabel(
              label: '미확정',
              count: _pendingWorkers.length,
              badgeColor: AppColors.warning,
              urgent: _pendingWorkers.isNotEmpty,
            ),
          ),
          Tab(
            child: AppTabLabel(
              label: '확정내역',
              count: _calculatedWorkers.length,
              badgeColor: theme.primaryColor,
            ),
          ),
          Tab(
            child: AppTabLabel(
              label: '마감내역',
              count: _transferredWorkers.length,
              badgeColor: AppColors.grey500,
            ),
          ),
        ],
      ),
    );
  }

  /// 미확정 탭 — 파트+시간대별 그룹 레이아웃
  Widget _buildPendingTab(BuildContext context, ThemeData theme) {
    if (_pendingWorkers.isEmpty) {
      return const AppEmptyState(
        icon: Icons.check_circle_outline,
        title: '미확정 인원이 없습니다',
        subtitle: '퇴근 완료된 근무자가 여기에 표시됩니다',
      );
    }

    // 파트+시간대별 그룹화 (입력 순서 유지)
    final groups = <String, List<ApplicationModel>>{};
    for (final app in _pendingWorkers) {
      groups.putIfAbsent(_getGroupKey(app), () => []).add(app);
    }

    return Column(
      children: [
        _buildSelectionBar(context, theme, _pendingWorkers, _pendingSelectedIds, true),
        Expanded(
          child: ListView(
            padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 16)),
            children: groups.entries.map((entry) {
              return _buildGroupSection(context, theme, entry.value, _pendingSelectedIds);
            }).toList(),
          ),
        ),
        _buildBottomSection(context, theme, _pendingSelectedIds, true),
      ],
    );
  }

  /// 급여확정 탭 (calculated + confirmed 통합)
  Widget _buildCalculatedTab(BuildContext context, ThemeData theme) {
    if (_calculatedWorkers.isEmpty) {
      return const AppEmptyState(
        icon: Icons.receipt_long_outlined,
        title: '급여 확정된 인원이 없습니다',
        subtitle: '급여 확정 후 여기에 표시됩니다',
      );
    }

    return Column(
      children: [
        _buildSelectionBar(context, theme, _calculatedWorkers, _calculatedSelectedIds, false),
        Expanded(
          child: ListView.builder(
            padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 16)),
            itemCount: _calculatedWorkers.length,
            itemBuilder: (context, index) {
              final app = _calculatedWorkers[index];
              final attendance = widget.attendanceMap[app.id];
              final isConfirmed = attendance?.wageStatus == AttendanceModel.wageConfirmed;
              return Stack(
                children: [
                  _buildWorkerCard(context, theme, app, _calculatedSelectedIds, false),
                  if (isConfirmed)
                    Positioned(
                      top: 10,
                      right: 10,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppColors.success,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '최종확정',
                          style: ResponsiveHelper.tinyStyle(context).copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
        _buildBottomSection(context, theme, _calculatedSelectedIds, false),
      ],
    );
  }

  /// 마감내역 탭 (wageConfirmed = 최종확정, wageTransferred = 송금완료)
  Widget _buildTransferredTab(BuildContext context, ThemeData theme) {
    if (_transferredWorkers.isEmpty) {
      return const AppEmptyState(
        icon: Icons.done_all,
        title: '마감된 내역이 없습니다',
        subtitle: '마감 완료된 급여가 여기에 표시됩니다',
      );
    }

    final confirmedIds = _transferredWorkers
        .where((a) => widget.attendanceMap[a.id]?.wageStatus == AttendanceModel.wageConfirmed)
        .map((a) => a.id)
        .toSet();
    final confirmedCount = confirmedIds.length;
    final transferredCount = _transferredWorkers.length - confirmedCount;
    final isAllSelected = confirmedIds.isNotEmpty &&
        _transferredSelectedIds.containsAll(confirmedIds);

    return Column(
      children: [
        // 안내 바: 최종확정 N명 / 송금완료 N명 + 전체선택
        Container(
          padding: ResponsiveHelper.symmetricPadding(context, horizontal: 16, vertical: 10),
          color: AppColors.grey50,
          child: Row(
            children: [
              if (confirmedCount > 0) ...[
                AppCheckbox(
                  value: isAllSelected,
                  activeColor: AppColors.warning,
                  onTap: () {
                    setState(() {
                      if (isAllSelected) {
                        _transferredSelectedIds.removeAll(confirmedIds);
                      } else {
                        _transferredSelectedIds.addAll(confirmedIds);
                      }
                    });
                  },
                ),
                SizedBox(width: ResponsiveHelper.spacing(context, 6)),
              ],
              Expanded(
                child: Text(
                  [
                    if (confirmedCount > 0) '최종확정 $confirmedCount명',
                    if (transferredCount > 0) '송금완료 $transferredCount명',
                  ].join(' · '),
                  style: ResponsiveHelper.smallStyle(context, color: AppColors.grey500),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 16)),
            itemCount: _transferredWorkers.length,
            itemBuilder: (context, index) {
              final app = _transferredWorkers[index];
              final user = widget.userMap[app.uid];
              final attendance = widget.attendanceMap[app.id];
              final wage = _calculatedWages[app.id];

              final name = user?.name ?? '이름 없음';
              final workTime = '${attendance?.checkIn ?? '-'} ~ ${attendance?.checkOut ?? '-'}';
              final workHours = wage?.workHours.toStringAsFixed(1) ?? '-';
              final netWage = wage != null
                  ? FormatHelper.formatWage(wage.effectiveNetWage)
                  : '계산 정보 없음';
              final isTransferred =
                  attendance?.wageStatus == AttendanceModel.wageTransferred;
              final isConfirmed =
                  attendance?.wageStatus == AttendanceModel.wageConfirmed;
              final isSelected = _transferredSelectedIds.contains(app.id);

              return GestureDetector(
                onTap: () => _showWageDetailDialog(app, isCalculated: true),
                child: Container(
                  margin: EdgeInsets.only(bottom: ResponsiveHelper.spacing(context, 10)),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: isSelected ? AppColors.warning : AppColors.grey200,
                      width: isSelected ? 1.5 : 1,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.04),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: ResponsiveHelper.cardPadding(context),
                    child: Row(
                      children: [
                        // 체크박스 (wageConfirmed만)
                        if (isConfirmed) ...[
                          AppCheckbox(
                            value: isSelected,
                            activeColor: AppColors.warning,
                            onTap: () {
                              setState(() {
                                if (isSelected) {
                                  _transferredSelectedIds.remove(app.id);
                                } else {
                                  _transferredSelectedIds.add(app.id);
                                }
                              });
                            },
                          ),
                          SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                        ],
                        // 좌측: 이름 + 파트 + 시간
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      name,
                                      style: ResponsiveHelper.bodyStyle(context)
                                          .copyWith(fontWeight: FontWeight.bold),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  SizedBox(width: ResponsiveHelper.spacing(context, 6)),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: AppColors.grey100,
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      app.selectedWorkType,
                                      style: ResponsiveHelper.tinyStyle(context).copyWith(
                                        color: AppColors.grey600,
                                        fontWeight: FontWeight.w600,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                      maxLines: 1,
                                    ),
                                  ),
                                ],
                              ),
                              SizedBox(height: ResponsiveHelper.spacing(context, 5)),
                              Row(
                                children: [
                                  Icon(Icons.schedule_outlined, size: 13, color: AppColors.grey400),
                                  SizedBox(width: ResponsiveHelper.spacing(context, 3)),
                                  Flexible(
                                    child: Text(
                                      '$workTime (${workHours}h)',
                                      style: ResponsiveHelper.smallStyle(context, color: AppColors.grey500),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        SizedBox(width: ResponsiveHelper.spacing(context, 12)),
                        // 우측: 배지 + 금액
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                              decoration: BoxDecoration(
                                color: (isTransferred ? AppColors.info : AppColors.success)
                                    .withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                isTransferred ? '송금완료' : '최종확정',
                                style: ResponsiveHelper.tinyStyle(context).copyWith(
                                  color: isTransferred ? AppColors.info : AppColors.success,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            SizedBox(height: ResponsiveHelper.spacing(context, 6)),
                            Text(
                              netWage,
                              style: ResponsiveHelper.subtitleStyle(context).copyWith(
                                fontWeight: FontWeight.bold,
                                color: AppColors.grey700,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        // 하단 버튼
        Container(
          padding: ResponsiveHelper.cardPadding(context),
          decoration: BoxDecoration(
            color: theme.scaffoldBackgroundColor,
            border: Border(top: BorderSide(color: theme.dividerColor)),
          ),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context, _hasChanges),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.grey600,
                    side: BorderSide(color: theme.dividerColor),
                    padding: EdgeInsets.symmetric(
                      vertical: ResponsiveHelper.spacing(context, 14),
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(ResponsiveHelper.spacing(context, 12)),
                    ),
                  ),
                  child: Text(
                    '닫기',
                    style: ResponsiveHelper.bodyStyle(context),
                  ),
                ),
              ),
              if (_transferredSelectedIds.isNotEmpty) ...[
                SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isProcessing ? null : _reverseCloseWages,
                    icon: _isProcessing
                        ? SizedBox(
                            width: ResponsiveHelper.spacing(context, 18),
                            height: ResponsiveHelper.spacing(context, 18),
                            child: const CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Icon(Icons.undo,
                            size: ResponsiveHelper.iconSize(context, 18),
                            color: Colors.white),
                    label: Text(
                      '마감 취소 (${_transferredSelectedIds.length}명)',
                      style: ResponsiveHelper.bodyStyle(context)
                          .copyWith(color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.warning,
                      foregroundColor: Colors.white,
                      padding: EdgeInsets.symmetric(
                        vertical: ResponsiveHelper.spacing(context, 14),
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(ResponsiveHelper.spacing(context, 12)),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  /// 선택 바
  Widget _buildSelectionBar(BuildContext context, ThemeData theme, List<ApplicationModel> workers, Set<String> selectedIds, bool isPending) {
    final hasSelection = selectedIds.isNotEmpty;
    final selectAll = selectedIds.length == workers.length && workers.isNotEmpty;
    final accentColor = isPending ? AppColors.warning : theme.primaryColor;

    return Container(
      padding: ResponsiveHelper.symmetricPadding(context, horizontal: 16, vertical: 10),
      color: AppColors.grey50,
      child: Row(
        children: [
          AppCheckbox(
            value: selectAll,
            activeColor: accentColor,
            onTap: () => setState(() {
              if (!selectAll) {
                selectedIds.addAll(workers.map((a) => a.id));
              } else {
                selectedIds.clear();
              }
            }),
          ),
          SizedBox(width: ResponsiveHelper.spacing(context, 8)),
          Text(
            '전체 선택',
            style: ResponsiveHelper.smallStyle(context).copyWith(
              color: AppColors.grey700,
              fontWeight: FontWeight.w500,
            ),
          ),
          if (hasSelection) ...[
            SizedBox(width: ResponsiveHelper.spacing(context, 6)),
            Container(
              padding: ResponsiveHelper.symmetricPadding(context, horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: accentColor,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '${selectedIds.length}명 선택',
                style: ResponsiveHelper.tinyStyle(context).copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
          const Spacer(),
          Text(
            '총 ${workers.length}명',
            style: ResponsiveHelper.tinyStyle(context, color: AppColors.grey400),
          ),
        ],
      ),
    );
  }

  /// 근무자 카드
  Widget _buildWorkerCard(BuildContext context, ThemeData theme, ApplicationModel app, Set<String> selectedIds, bool isPending) {
    final user = widget.userMap[app.uid];
    final attendance = widget.attendanceMap[app.id];
    final wage = _calculatedWages[app.id];
    final isSelected = selectedIds.contains(app.id);

    final name = user?.name ?? '이름 없음';
    final genderAge = _formatGenderAge(user);
    final workTime = '${attendance?.checkIn ?? '-'} ~ ${attendance?.checkOut ?? '-'}';
    final workHours = wage?.workHours.toStringAsFixed(1) ?? '-';
    final hasDeductions = wage != null &&
        wage.taxDeductionType != InsuranceRateModel.typeNone &&
        wage.totalInsuranceDeduction > 0;
    final totalAmount = hasDeductions
        ? wage.formattedNetWage
        : (wage?.formattedTotal ?? '계산 중...');
    final accentColor = isPending ? AppColors.warning : theme.primaryColor;
    // 실제 적용된 휴게시간 (석식/야식공제는 연장시간 있을 때만 합산)
    final hasOvertime = _workerHasOvertime(app);
    final extraApplied = hasOvertime ? (_workerExtraBreakMinutes[app.id] ?? 0) : 0;
    final breakMins = wage?.breakMinutes ?? (_getScheduledBreakMinutes(app) + extraApplied);
    return Container(
      margin: EdgeInsets.only(bottom: ResponsiveHelper.spacing(context, 10)),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isSelected ? accentColor : AppColors.grey200,
          width: isSelected ? 2 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: () => _showWageDetailDialog(app, isCalculated: !isPending),
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: ResponsiveHelper.cardPadding(context),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── 상단: 체크박스 + 정보 ──────────────────────
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 체크박스
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: AppCheckbox(
                        value: isSelected,
                        activeColor: accentColor,
                        onTap: () => _handleWorkerCheckboxTap(app, selectedIds),
                      ),
                    ),
                    SizedBox(width: ResponsiveHelper.spacing(context, 10)),

                    // 정보 — Expanded로 전체 너비 확보
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // 이름 + 성별나이 + 배지 (한 줄)
                          Row(
                            children: [
                              Flexible(
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Flexible(
                                      child: Text(
                                        name,
                                        style: ResponsiveHelper.bodyStyle(context)
                                            .copyWith(fontWeight: FontWeight.bold),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    if (genderAge.isNotEmpty) ...[
                                      SizedBox(width: ResponsiveHelper.spacing(context, 3)),
                                      Flexible(
                                        child: Text(
                                          genderAge,
                                          style: ResponsiveHelper.tinyStyle(context,
                                              color: AppColors.grey400),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                              ConstrainedBox(
                                constraints: const BoxConstraints(maxWidth: 80),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 7, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: accentColor.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    app.selectedWorkType,
                                    style: ResponsiveHelper.tinyStyle(context)
                                        .copyWith(
                                      color: accentColor,
                                      fontWeight: FontWeight.w600,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                    maxLines: 1,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          SizedBox(height: ResponsiveHelper.spacing(context, 5)),

                          // 출퇴근 시간 + 실근무 시간
                          Row(
                            children: [
                              Icon(Icons.schedule_outlined,
                                  size: 13, color: AppColors.grey400),
                              SizedBox(width: ResponsiveHelper.spacing(context, 3)),
                              Text(
                                '$workTime (실근무 ${workHours}h)',
                                style: ResponsiveHelper.smallStyle(context,
                                    color: AppColors.grey500),
                              ),
                            ],
                          ),

                          // 상태 배지 (지각/조퇴/연장/심야)
                          Builder(builder: (context) {
                            final flagBadges = _buildWageFlagBadges(app);
                            if (flagBadges.isEmpty) return const SizedBox.shrink();
                            return Padding(
                              padding: EdgeInsets.only(top: ResponsiveHelper.spacing(context, 5)),
                              child: Row(children: flagBadges),
                            );
                          }),

                        ],
                      ),
                    ),
                  ],
                ),

                // ── 구분선 ─────────────────────────────────────
                Padding(
                  padding: EdgeInsets.symmetric(
                      vertical: ResponsiveHelper.spacing(context, 10)),
                  child: Divider(height: 1, color: AppColors.grey100),
                ),

                // ── 계산식 한 줄 ────────────────────────────────
                if (wage != null)
                  Padding(
                    padding: EdgeInsets.only(bottom: ResponsiveHelper.spacing(context, 6)),
                    child: _buildWageFormulaLine(context, wage, accentColor),
                  ),

                // ── 하단: 휴게 배지 + 급여 금액 ─────────────────
                Row(
                  children: [
                    if (breakMins > 0) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.successBg,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: AppColors.successDark.withValues(alpha: 0.2)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.pause_circle_outline,
                                size: 11, color: AppColors.successDark),
                            SizedBox(width: ResponsiveHelper.spacing(context, 3)),
                            Text(
                              '휴게 ${FormatHelper.formatCompactHours(breakMins)}',
                              style: ResponsiveHelper.tinyStyle(context).copyWith(
                                color: AppColors.successDark,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const Spacer(),
                    if (wage?.wageTypeLabel != null) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: accentColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          wage!.wageTypeLabel,
                          style: ResponsiveHelper.tinyStyle(context).copyWith(
                            color: accentColor,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                    ],
                    Text(
                      totalAmount,
                      style: ResponsiveHelper.subtitleStyle(context).copyWith(
                        fontWeight: FontWeight.bold,
                        color: accentColor,
                      ),
                    ),
                    SizedBox(width: ResponsiveHelper.spacing(context, 2)),
                    Icon(Icons.chevron_right,
                        color: AppColors.grey300,
                        size: ResponsiveHelper.iconSize(context, 18)),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 계산식 한 줄 요약 (예: "8.0h × 12,000원 +조출 3,000원 +연장 2,000원 +야간 1,000원")
  Widget _buildWageFormulaLine(BuildContext context, WageDetailModel wage, Color accentColor) {
    final parts = <String>[];

    if (wage.wageType == 'hourly') {
      parts.add('${wage.workHours.toStringAsFixed(1)}h × ${FormatHelper.formatWage(wage.baseWage)}');
    } else {
      parts.add('일급 ${FormatHelper.formatWage(wage.baseWage)}');
      // 미근무 공제 (일급제 조퇴 등): 일급 전액 - 실지급 기본급
      final deduction = wage.baseWage - wage.baseAmount;
      if (deduction > 0) {
        parts.add('-미근무 ${FormatHelper.formatWage(deduction)}');
      }
    }
    if (wage.overtimeAmount > 0) {
      // earlyArrivalAmount: WageDetailModel에 저장된 실제 조출수당 (8h 기준 계산)
      // 구형 레코드(earlyArrivalAmount==0)는 비율 fallback
      final earlyMins = wage.earlyArrivalMinutes.clamp(0, wage.overtimeMinutes);
      int earlyAmt = wage.earlyArrivalAmount;
      if (earlyAmt == 0 && earlyMins > 0 && wage.overtimeMinutes > 0) {
        earlyAmt = (wage.overtimeAmount * earlyMins / wage.overtimeMinutes).round();
      }
      final regularAmt = wage.overtimeAmount - earlyAmt;
      if (earlyAmt > 0 && regularAmt > 0) {
        parts.add('+조출 ${FormatHelper.formatWage(earlyAmt)}');
        parts.add('+연장 ${FormatHelper.formatWage(regularAmt)}');
      } else if (earlyAmt > 0) {
        parts.add('+조출 ${FormatHelper.formatWage(earlyAmt)}');
      } else {
        parts.add('+연장 ${FormatHelper.formatWage(wage.overtimeAmount)}');
      }
    }
    if (wage.nightAmount > 0) {
      parts.add('+야간 ${FormatHelper.formatWage(wage.nightAmount)}');
    }
    if (wage.additionalAmount > 0) {
      parts.add('+추가 ${FormatHelper.formatWage(wage.additionalAmount)}');
    }
    if (wage.deductionAmount > 0) {
      parts.add('-공제 ${FormatHelper.formatWage(wage.deductionAmount)}');
    }

    return Row(
      children: [
        Icon(Icons.calculate_outlined,
            size: ResponsiveHelper.iconSize(context, 12), color: AppColors.grey400),
        SizedBox(width: ResponsiveHelper.spacing(context, 4)),
        Flexible(
          child: Text(
            parts.join('  '),
            style: ResponsiveHelper.tinyStyle(context, color: AppColors.grey500),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  /// 하단 섹션
  Widget _buildBottomSection(BuildContext context, ThemeData theme, Set<String> selectedIds, bool isPending) {
    final hasSelection = selectedIds.isNotEmpty;
    final totalWage = _getSelectedTotal(selectedIds);
    
    final buttonColor = isPending ? AppColors.warning : theme.primaryColor;
    final buttonText = '급여 확정 (${selectedIds.length}명)';
    
    return Container(
      padding: ResponsiveHelper.cardPadding(context),
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        border: Border(top: BorderSide(color: theme.dividerColor)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 요약
          if (hasSelection)
            Container(
              padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 12)),
              margin: EdgeInsets.only(bottom: ResponsiveHelper.spacing(context, 12)),
              decoration: BoxDecoration(
                color: buttonColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(ResponsiveHelper.spacing(context, 12)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.payments,
                    color: buttonColor,
                    size: ResponsiveHelper.iconSize(context, 20),
                  ),
                  SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                  Text(
                    '선택 급여 합계: ',
                    style: ResponsiveHelper.bodyStyle(context).copyWith(color: AppColors.grey800),
                  ),
                  Text(
                    FormatHelper.formatWage(totalWage),
                    style: ResponsiveHelper.subtitleStyle(context).copyWith(
                      fontWeight: FontWeight.bold,
                      color: buttonColor,
                    ),
                  ),
                ],
              ),
            ),
          
          // 전체 일괄 마감 버튼 (확정내역 탭 — wageCalculated 항목 있을 때)
          if (!isPending) ...[
            Builder(builder: (context) {
              final closableCount = _calculatedWorkers.where((app) {
                final att = widget.attendanceMap[app.id];
                return att?.wageStatus == AttendanceModel.wageCalculated;
              }).length;
              if (closableCount == 0) return const SizedBox.shrink();
              return Padding(
                padding: EdgeInsets.only(bottom: ResponsiveHelper.spacing(context, 8)),
                child: SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _isProcessing ? null : () {
                      setState(() {
                        _calculatedSelectedIds
                          ..clear()
                          ..addAll(_calculatedWorkers
                            .where((app) => widget.attendanceMap[app.id]?.wageStatus == AttendanceModel.wageCalculated)
                            .map((app) => app.id));
                      });
                      _closeWages();
                    },
                    icon: Icon(Icons.lock_outline, size: ResponsiveHelper.iconSize(context, 18), color: AppColors.success),
                    label: Text(
                      '전체 일괄 마감 ($closableCount명)',
                      style: ResponsiveHelper.bodyStyle(context).copyWith(
                        color: AppColors.success,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.success,
                      side: BorderSide(color: AppColors.success.withValues(alpha: 0.6)),
                      padding: EdgeInsets.symmetric(vertical: ResponsiveHelper.spacing(context, 12)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(ResponsiveHelper.spacing(context, 12)),
                      ),
                    ),
                  ),
                ),
              );
            }),
          ],

          // 전체 일괄 확정 버튼 (미확정 탭에만)
          if (isPending && _pendingWorkers.isNotEmpty)
            Padding(
              padding: EdgeInsets.only(bottom: ResponsiveHelper.spacing(context, 8)),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: (_isProcessing || _isInitializing) ? null : _confirmAllPending,
                  icon: (_isProcessing || _isInitializing)
                      ? SizedBox(
                          width: ResponsiveHelper.spacing(context, 16),
                          height: ResponsiveHelper.spacing(context, 16),
                          child: CircularProgressIndicator(
                            strokeWidth: ResponsiveHelper.spacing(context, 2),
                            color: AppColors.warning,
                          ),
                        )
                      : Icon(Icons.done_all, size: ResponsiveHelper.iconSize(context, 18), color: AppColors.warning),
                  label: Text(
                    _isInitializing ? '계산 중...' : '전체 일괄 확정 (${_pendingWorkers.length}명)',
                    style: ResponsiveHelper.bodyStyle(context).copyWith(
                      color: AppColors.warning,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.warning,
                    side: BorderSide(color: AppColors.warning.withValues(alpha: 0.6)),
                    padding: EdgeInsets.symmetric(vertical: ResponsiveHelper.spacing(context, 12)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(ResponsiveHelper.spacing(context, 12)),
                    ),
                  ),
                ),
              ),
            ),

          // 버튼
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _isProcessing ? null : () => Navigator.pop(context, _hasChanges),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.grey600,
                    side: BorderSide(color: theme.dividerColor),
                    padding: EdgeInsets.symmetric(
                      vertical: ResponsiveHelper.spacing(context, 14),
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(ResponsiveHelper.spacing(context, 12)),
                    ),
                  ),
                  child: Text(
                    '닫기',
                    style: ResponsiveHelper.bodyStyle(context),
                  ),
                ),
              ),
              SizedBox(width: ResponsiveHelper.spacing(context, 12)),
              // 확정내역 탭: 확정 취소 + 마감하기
              if (!isPending) ...[
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: (hasSelection && !_isProcessing) ? _cancelSelectedWages : null,
                    icon: _isProcessing
                        ? SizedBox(
                            width: ResponsiveHelper.spacing(context, 16),
                            height: ResponsiveHelper.spacing(context, 16),
                            child: CircularProgressIndicator(
                              strokeWidth: ResponsiveHelper.spacing(context, 2),
                              color: Colors.white,
                            ),
                          )
                        : Icon(Icons.undo, size: ResponsiveHelper.iconSize(context, 18)),
                    label: Text(
                      '취소',
                      style: ResponsiveHelper.bodyStyle(context).copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: hasSelection ? AppColors.error : theme.disabledColor,
                      foregroundColor: Colors.white,
                      padding: EdgeInsets.symmetric(
                        vertical: ResponsiveHelper.spacing(context, 14),
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(ResponsiveHelper.spacing(context, 12)),
                      ),
                    ),
                  ),
                ),
                SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                Expanded(
                  flex: 2,
                  child: Builder(builder: (context) {
                    final closableSelected = _calculatedSelectedIds.where((id) =>
                      widget.attendanceMap[id]?.wageStatus == AttendanceModel.wageCalculated
                    ).length;
                    return ElevatedButton.icon(
                      onPressed: (closableSelected > 0 && !_isProcessing) ? _closeWages : null,
                      icon: _isProcessing
                          ? SizedBox(
                              width: ResponsiveHelper.spacing(context, 18),
                              height: ResponsiveHelper.spacing(context, 18),
                              child: CircularProgressIndicator(
                                strokeWidth: ResponsiveHelper.spacing(context, 2),
                                color: Colors.white,
                              ),
                            )
                          : Icon(Icons.lock_outline, size: ResponsiveHelper.iconSize(context, 20)),
                      label: Text(
                        _isProcessing ? '처리 중...' : '마감 ($closableSelected명)',
                        style: ResponsiveHelper.bodyStyle(context).copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: closableSelected > 0 ? AppColors.success : theme.disabledColor,
                        foregroundColor: Colors.white,
                        padding: EdgeInsets.symmetric(
                          vertical: ResponsiveHelper.spacing(context, 14),
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(ResponsiveHelper.spacing(context, 12)),
                        ),
                      ),
                    );
                  }),
                ),
              ],
              // 미확정 탭: 급여 확정
              if (isPending)
              Expanded(
                flex: 2,
                child: ElevatedButton.icon(
                  onPressed: (hasSelection && !_isProcessing && !_isInitializing)
                      ? _confirmWages
                      : null,
                  icon: (_isProcessing || _isInitializing)
                      ? SizedBox(
                          width: ResponsiveHelper.spacing(context, 18),
                          height: ResponsiveHelper.spacing(context, 18),
                          child: CircularProgressIndicator(
                            strokeWidth: ResponsiveHelper.spacing(context, 2),
                            color: Colors.white,
                          ),
                        )
                      : Icon(
                          isPending ? Icons.check : Icons.edit_outlined,
                          size: ResponsiveHelper.iconSize(context, 20),
                        ),
                  label: Text(
                    _isInitializing ? '계산 중...' : (_isProcessing ? '처리 중...' : buttonText),
                    style: ResponsiveHelper.bodyStyle(context).copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: hasSelection ? buttonColor : theme.disabledColor,
                    foregroundColor: Colors.white,
                    padding: EdgeInsets.symmetric(
                      vertical: ResponsiveHelper.spacing(context, 14),
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(ResponsiveHelper.spacing(context, 12)),
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

  // ═══════════════════════════════════════════════════════════
  // 그룹 섹션 UI (파트+시간대 단위)
  // ═══════════════════════════════════════════════════════════

  /// 파트+시간대 그룹 섹션 (헤더 + 근무자 카드 목록)
  Widget _buildGroupSection(
    BuildContext context,
    ThemeData theme,
    List<ApplicationModel> groupWorkers,
    Set<String> selectedIds,
  ) {
    return Padding(
      padding: EdgeInsets.only(bottom: ResponsiveHelper.spacing(context, 16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildGroupHeader(context, theme, groupWorkers, selectedIds),
          SizedBox(height: ResponsiveHelper.spacing(context, 6)),
          ...groupWorkers.map(
            (app) => _buildWorkerCard(context, theme, app, selectedIds, true),
          ),
        ],
      ),
    );
  }

  /// 그룹 헤더 — 파트명·시간대·인원 + 그룹 선택 + 추가공제 일괄 칩
  Widget _buildGroupHeader(
    BuildContext context,
    ThemeData theme,
    List<ApplicationModel> groupWorkers,
    Set<String> selectedIds,
  ) {
    final first = groupWorkers.first;
    final groupKey = _getGroupKey(first);
    final workType = first.selectedWorkType;
    final timeRange = '${WorkDetailHelper.effectiveStart(first, widget.workDetailTimeMap)} ~ ${WorkDetailHelper.effectiveEnd(first, widget.workDetailTimeMap)}';
    final schedBreak = _getScheduledBreakMinutes(first);
    final extra = _groupExtraBreakMinutes[groupKey] ?? 0;
    const options = [0, 30, 60, 90];
    final allGroupSelected = groupWorkers.isNotEmpty &&
        groupWorkers.every((a) => selectedIds.contains(a.id));

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 12),
        vertical: ResponsiveHelper.spacing(context, 10),
      ),
      decoration: BoxDecoration(
        color: AppColors.grey50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.grey200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 그룹 체크박스 + 파트 배지 + 시간대 + 인원수
          Row(
            children: [
              AppCheckbox(
                value: allGroupSelected,
                onTap: () => setState(() {
                  if (allGroupSelected) {
                    for (final a in groupWorkers) { selectedIds.remove(a.id); }
                  } else {
                    for (final a in groupWorkers) { selectedIds.add(a.id); }
                  }
                }),
              ),
              SizedBox(width: ResponsiveHelper.spacing(context, 8)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.warning.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  workType,
                  style: ResponsiveHelper.tinyStyle(context).copyWith(
                    color: AppColors.warning,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              SizedBox(width: ResponsiveHelper.spacing(context, 6)),
              Icon(Icons.schedule_outlined, size: 12, color: AppColors.grey400),
              SizedBox(width: ResponsiveHelper.spacing(context, 3)),
              Text(
                timeRange,
                style: ResponsiveHelper.smallStyle(context, color: AppColors.grey500),
              ),
              const Spacer(),
              Text(
                '${groupWorkers.length}명',
                style: ResponsiveHelper.tinyStyle(context, color: AppColors.grey400),
              ),
            ],
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 8)),
          // 석식/야식공제 라벨
          Row(
            children: [
              Icon(Icons.restaurant_outlined, size: 12, color: AppColors.grey500),
              SizedBox(width: ResponsiveHelper.spacing(context, 3)),
              Flexible(
                child: Text(
                  schedBreak > 0
                      ? '석식/야식공제 (기본 ${FormatHelper.formatCompactHours(schedBreak)})'
                      : '석식/야식공제',
                  style: ResponsiveHelper.tinyStyle(context, color: AppColors.grey500),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 5)),
          // 석식/야식공제 칩 (그룹 일괄 적용 — 선택된 근무자 전체에 반영)
          Row(
            children: options.map((min) {
              final isSelected = extra == min;
              final label = min == 0 ? '없음' : '+$min분';
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _setGroupBreak(groupWorkers, min),
                child: Container(
                  margin: EdgeInsets.only(right: ResponsiveHelper.spacing(context, 5)),
                  padding: ResponsiveHelper.symmetricPadding(
                      context, horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: isSelected ? AppColors.amberDark : Colors.white,
                    border: Border.all(
                      color: isSelected ? AppColors.amberDark : AppColors.grey300,
                      width: isSelected ? 1.5 : 1,
                    ),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    label,
                    style: ResponsiveHelper.tinyStyle(context).copyWith(
                      color: isSelected ? Colors.white : AppColors.grey600,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  // 유틸 메서드
  // ═══════════════════════════════════════════════════════════

  String _formatGenderAge(UserModel? user) {
    if (user == null) return '';
    final parts = <String>[];
    if (user.gender != null) {
      parts.add(user.gender == '남성' ? '남' : '여');
    }
    if (user.age != null) {
      parts.add('${user.age}');
    }
    return parts.isNotEmpty ? '(${parts.join(', ')})' : '';
  }

  List<Widget> _buildWageFlagBadges(ApplicationModel app) {
    final attendance = widget.attendanceMap[app.id];
    final flags = AttendanceBadgeHelper.compute(
      checkIn: attendance?.checkIn,
      checkOut: attendance?.checkOut,
      effStart: WorkDetailHelper.effectiveStart(app, widget.workDetailTimeMap),
      effEnd: WorkDetailHelper.effectiveEnd(app, widget.workDetailTimeMap),
      wageDetail: _calculatedWages[app.id],
      graceMinutes: 5,
    );

    return [
      if (flags.isEarlyArrival) _buildFlagBadge('조출', AppColors.success),
      if (flags.isLate) _buildFlagBadge('지각', AppColors.error),
      if (flags.isEarlyLeave) _buildFlagBadge('조퇴', AppColors.warning),
      if (flags.isOvertime) _buildFlagBadge('연장', Colors.blue),
      if (flags.isNight) _buildFlagBadge('심야', AppColors.purpleDark),
    ];
  }

  Widget _buildFlagBadge(String label, Color color) {
    return Container(
      margin: const EdgeInsets.only(right: 4),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        label,
        style: ResponsiveHelper.tinyStyle(context, color: color).copyWith(fontWeight: FontWeight.w600),
      ),
    );
  }

}