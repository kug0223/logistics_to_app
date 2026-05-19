// lib/screens/business_admin/dialogs/wage_confirm_dialog.dart
// 급여 확정 다이얼로그 - 탭 구조
// 
// 탭 1: 미확정 (pending) → 급여 확정 → calculated
// 탭 2: 급여확정 (calculated) → 최종 확정 → confirmed

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';

// Models
import '../../../models/core/application_model.dart';
import '../../../models/core/attendance_model.dart';
import '../../../models/core/user_model.dart';
import '../../../models/core/wage_detail_model.dart';

// Utils
import '../../../utils/toast_helper.dart';
import '../../../utils/responsive_helper.dart';
import '../../../utils/format_helper.dart';
import '../../../utils/dialog_helper.dart';
import '../../../utils/wage_calculator.dart';
import '../../../theme/app_colors.dart';
import '../../../widgets/common/app_checkbox.dart';

import '../../../widgets/dialogs/wage/wage_detail_dialog.dart';

// Providers
import '../../../providers/user_provider.dart';

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
  });

  @override
  State<WageConfirmDialog> createState() => _WageConfirmDialogState();
}

class _WageConfirmDialogState extends State<WageConfirmDialog> with SingleTickerProviderStateMixin {
  // ═══════════════════════════════════════════════════════════
  // 상태 변수
  // ═══════════════════════════════════════════════════════════
  
  late TabController _tabController;
  bool _isProcessing = false;
  bool _hasChanges = false;
  
  // 선택 상태 (탭별로 분리)
  final Set<String> _pendingSelectedIds = {};
  final Set<String> _calculatedSelectedIds = {};
  
  // 계산된 급여 정보 캐시
  final Map<String, WageDetailModel> _calculatedWages = {};

  // 파트+시간대 그룹별 추가 공제 시간 (분) — key: workType_startTime_endTime
  final Map<String, int> _groupExtraBreakMinutes = {};
  
  // 근무자 목록 (상태별 분리)
  List<ApplicationModel> _pendingWorkers = [];      // 미확정 (퇴근완료, pending)
  List<ApplicationModel> _calculatedWorkers = [];   // 급여확정 (calculated)

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
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
    
    for (var app in widget.workers) {
      final attendance = widget.attendanceMap[app.id];
      if (attendance == null) continue;
      
      // 퇴근 완료된 근무자만
      if (attendance.checkOut == null) continue;
      
      // 상태별 분류
      if (attendance.wageStatus == 'calculated') {
        _calculatedWorkers.add(app);
      } else if (attendance.wageStatus == 'pending') {
        _pendingWorkers.add(app);
      }
      // confirmed는 이미 최종확정이므로 표시 안함
    }
    
    // 급여 미리 계산 (async)
    await _calculateAllWages();
    
    // ✅ 계산 완료 후 UI 갱신
    if (mounted) setState(() {});
  }

  /// 파트+시간대 그룹 키 생성
  String _getGroupKey(ApplicationModel app) =>
      '${app.selectedWorkType}_${app.startTime}_${app.endTime}';

  /// 전체 급여 계산 (async로 변경)
  Future<void> _calculateAllWages() async {
    final allWorkers = [..._pendingWorkers, ..._calculatedWorkers];
    for (var app in allWorkers) {
      final extra = _groupExtraBreakMinutes[_getGroupKey(app)] ?? 0;
      final wage = await _calculateWageForWorker(app, extraBreakMinutes: extra);
      if (wage != null) {
        _calculatedWages[app.id] = wage;
      }
    }
  }

  /// workDetailTimeMap에서 예정 휴게시간 조회
  int _getScheduledBreakMinutes(ApplicationModel app) {
    final cached = (app.workDetailId != null
            ? widget.workDetailTimeMap[app.workDetailId]
            : null) ??
        widget.workDetailTimeMap[app.selectedWorkType];
    if (cached is Map<String, dynamic>) {
      return cached['breakMinutes'] as int? ?? 0;
    }
    return 0;
  }

  /// 그룹 추가 공제 시간 변경 → 그룹 내 전체 근무자 급여 재계산
  Future<void> _setGroupBreak(List<ApplicationModel> groupWorkers, int extraMinutes) async {
    final key = _getGroupKey(groupWorkers.first);
    setState(() => _groupExtraBreakMinutes[key] = extraMinutes);
    for (final app in groupWorkers) {
      final wage = await _calculateWageForWorker(app, extraBreakMinutes: extraMinutes);
      if (wage != null && mounted) {
        setState(() => _calculatedWages[app.id] = wage);
      }
    }
  }

  /// 개별 급여 계산 (async로 변경)
  Future<WageDetailModel?> _calculateWageForWorker(ApplicationModel app, {int extraBreakMinutes = 0}) async {
    final attendance = widget.attendanceMap[app.id];
    if (attendance == null || attendance.checkIn == null || attendance.checkOut == null) {
      return null;
    }
    
    // 이미 계산된 급여가 있으면 그것 사용 (calculated 상태)
    if (attendance.wageDetail != null) {
      return attendance.wageDetail;
    }
    
    // ✅ Application에 저장된 기본 정보 사용
    final scheduledStart = app.startTime;
    final scheduledEnd = app.endTime;
    final baseWage = app.wage;
    
    // ✅ wageType, breakMinutes, nightAllowanceApplied, nightIncluded는 workDetailTimeMap에서 먼저 확인
    String wageType = 'hourly';
    int breakMinutes = 0;
    bool nightAllowanceApplied = true;
    bool nightIncluded = false;
    int? baseHourlyWage;

    // 1순위: 이미 로드된 workDetailTimeMap에서 가져오기
    // composite key(workDetailId) 우선, 없으면 workType(selectedWorkType) 폴백
    final detailCached = (app.workDetailId != null
            ? widget.workDetailTimeMap[app.workDetailId]
            : null) ??
        widget.workDetailTimeMap[app.selectedWorkType];

    if (detailCached is Map<String, dynamic>) {
      wageType = detailCached['wageType'] ?? 'hourly';
      breakMinutes = detailCached['breakMinutes'] ?? 0;
      nightAllowanceApplied = detailCached['nightAllowanceApplied'] ?? true;
      nightIncluded = detailCached['nightIncluded'] as bool? ?? false;
      baseHourlyWage = detailCached['baseHourlyWage'] as int?;
      debugPrint('✅ WorkDetail 캐시 사용: wageType=$wageType, nightIncluded=$nightIncluded');
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
            baseHourlyWage = wdMap['baseHourlyWage'] as int?;
            debugPrint('✅ WorkDetail Firestore 조회($source): wageType=$wageType, nightIncluded=$nightIncluded');
            break;
          }
        }
      } catch (e) {
        debugPrint('⚠️ WorkDetail 조회 실패: $e');
      }
    } else {
      debugPrint('⚠️ WorkDetail 조회 불가: toId=${app.toId}, workDetailId=${app.workDetailId}');
    }

    try {
      return WageCalculator.calculate(
        wageType: wageType,
        baseWage: baseWage,
        workDate: widget.date,
        scheduledStart: scheduledStart,
        scheduledEnd: scheduledEnd,
        actualStart: attendance.checkIn!,
        actualEnd: attendance.checkOut!,
        breakMinutes: breakMinutes + extraBreakMinutes,
        scheduledBreakMinutes: breakMinutes,
        nightAllowanceApplied: nightAllowanceApplied,
        nightIncluded: nightIncluded,
        baseHourlyWage: baseHourlyWage,
      );
    } catch (e) {
      debugPrint('❌ 급여 계산 실패 (${app.id}): $e');
      return null;
    }
  }

  // ═══════════════════════════════════════════════════════════
  // 급여 확정 처리 (pending → calculated)
  // ═══════════════════════════════════════════════════════════

  Future<void> _confirmWages() async {
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
    
    if (!confirmed) return;
    if (!mounted) return;

    final adminUid = Provider.of<UserProvider>(context, listen: false).currentUser?.uid;

    setState(() => _isProcessing = true);

    try {
      
      int successCount = 0;
      int failCount = 0;
      final confirmedIds = <String>{};
      
      for (var appId in _pendingSelectedIds) {
        final wage = _calculatedWages[appId];
        final attendance = widget.attendanceMap[appId];
        
        if (wage == null || attendance == null) {
          failCount++;
          continue;
        }
        
        try {
          final calculatedWage = wage.copyWith(
            calculatedBy: adminUid,
            calculatedAt: DateTime.now(),
          );
          
          await FirebaseFirestore.instance
              .collection('attendance')
              .doc(attendance.id)
              .update({
            'wageStatus': 'calculated',
            'finalWage': calculatedWage.totalAmount,
            'wageDetail': calculatedWage.toMap(),
            'updatedAt': FieldValue.serverTimestamp(),
          });
          
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
        
        setState(() {
          // 확정된 근무자를 calculated 탭으로 이동
          for (var id in confirmedIds) {
            final worker = _pendingWorkers.firstWhere((w) => w.id == id);
            _calculatedWorkers.add(worker);
          }
          _pendingWorkers.removeWhere((app) => confirmedIds.contains(app.id));
          _pendingSelectedIds.clear();
        });
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
  // 최종 확정 처리 (calculated → confirmed)
  // ═══════════════════════════════════════════════════════════

  /// 일괄 급여 수정 다이얼로그
  Future<void> _openBatchEditDialog() async {
    // 선택된 인원이 1명이면 개별 수정 다이얼로그로
    if (_calculatedSelectedIds.length == 1) {
      final appId = _calculatedSelectedIds.first;
      final app = _calculatedWorkers.firstWhere((a) => a.id == appId);
      final attendance = widget.attendanceMap[app.id];
      final wage = _calculatedWages[app.id];
      
      if (attendance != null && wage != null) {
        final detailCached = (app.workDetailId != null
                ? widget.workDetailTimeMap[app.workDetailId]
                : null) ??
            widget.workDetailTimeMap[app.selectedWorkType];
        final shiftType = detailCached is Map<String, dynamic>
            ? detailCached['shiftType'] as String?
            : null;
        final result = await WageDetailDialog.show(
          context: context,
          app: app,
          user: widget.userMap[app.uid],
          attendance: attendance,
          wage: wage,
          mode: WageDialogMode.editOnly,
          shiftType: shiftType,
        );
        
        if (result != null && result.action == 'update') {
          await _processWageUpdate(app, attendance, result.wage);  // ✅ 기존 메서드 사용
        }
      }
    } else {
      ToastHelper.showInfo('여러 명 수정은 개별 카드를 클릭해주세요');
    }
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

    final mode = isCalculated ? WageDialogMode.calculated : WageDialogMode.pending;

    final detailCached = (app.workDetailId != null
            ? widget.workDetailTimeMap[app.workDetailId]
            : null) ??
        widget.workDetailTimeMap[app.selectedWorkType];
    final shiftType = detailCached is Map<String, dynamic>
        ? detailCached['shiftType'] as String?
        : null;

    final result = await WageDetailDialog.show(
      context: context,
      app: app,
      user: user,
      attendance: attendance,
      wage: wage,
      mode: mode,
      shiftType: shiftType,
    );
    
    if (result == null) return;
    
    switch (result.action) {
      case 'confirm':
        await _processIndividualConfirm(app, attendance, result.wage);
        break;
      case 'update':
        await _processWageUpdate(app, attendance, result.wage);
        break;
      case 'final_confirm':
        await _processIndividualFinalConfirm(app, attendance, result.wage);
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
      
      final calculatedWage = wage.copyWith(
        calculatedBy: adminUid,
        calculatedAt: DateTime.now(),
      );
      
      await FirebaseFirestore.instance
          .collection('attendance')
          .doc(attendance.id)
          .update({
        'wageStatus': 'calculated',
        'finalWage': calculatedWage.totalAmount,
        'wageDetail': calculatedWage.toMap(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      
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
      
      await FirebaseFirestore.instance
          .collection('attendance')
          .doc(attendance.id)
          .update({
        'finalWage': updatedWage.totalAmount,
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

  /// 개별 최종 확정
  Future<void> _processIndividualFinalConfirm(ApplicationModel app, AttendanceModel attendance, WageDetailModel wage) async {
    try {
      final userProvider = Provider.of<UserProvider>(context, listen: false);
      final adminUid = userProvider.currentUser?.uid;
      final user = widget.userMap[app.uid];
      
      final finalWage = wage.copyWith(
        confirmedBy: adminUid,
        confirmedAt: DateTime.now(),
      );
      
      await FirebaseFirestore.instance
          .collection('attendance')
          .doc(attendance.id)
          .update({
        'wageStatus': 'confirmed',
        'finalWage': finalWage.totalAmount,
        'wageDetail': finalWage.toMap(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      
      _hasChanges = true;
      widget.onConfirmed?.call();
      
      if (mounted) {
        setState(() {
          _calculatedWorkers.removeWhere((w) => w.id == app.id);
          _calculatedWages.remove(app.id);
          _calculatedSelectedIds.remove(app.id);
        });
      }
      
      ToastHelper.showSuccess('${user?.name ?? '근무자'} 최종 확정 완료');
    } catch (e) {
      debugPrint('❌ 개별 최종 확정 실패: $e');
      ToastHelper.showError('최종 확정에 실패했습니다');
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
        'wageStatus': 'pending',
        'finalWage': FieldValue.delete(),
        'wageDetail': FieldValue.delete(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      
      _hasChanges = true;
      widget.onConfirmed?.call();
      
      // 급여 재계산 (그룹 추가 공제 유지, 재계산만)
      final extra = _groupExtraBreakMinutes[_getGroupKey(app)] ?? 0;
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

  // ═══════════════════════════════════════════════════════════
  // 합계 계산
  // ═══════════════════════════════════════════════════════════

  int _getSelectedTotal(Set<String> selectedIds) {
    int total = 0;
    for (var appId in selectedIds) {
      total += _calculatedWages[appId]?.totalAmount ?? 0;
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
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          Navigator.pop(context, _hasChanges);
        }
      },
      child: Dialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(ResponsiveHelper.spacing(context, 20)),
        ),
        child: Container(
          width: screenWidth * 0.92,
          height: screenHeight * 0.85,
          constraints: BoxConstraints(maxWidth: screenWidth * 0.95),
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
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
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
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('미확정'),
                if (_pendingWorkers.isNotEmpty) ...[
                  SizedBox(width: ResponsiveHelper.spacing(context, 6)),
                  Container(
                    padding: ResponsiveHelper.symmetricPadding(context, horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.warning,
                      borderRadius: BorderRadius.circular(ResponsiveHelper.spacing(context, 10)),
                    ),
                    child: Text(
                      '${_pendingWorkers.length}',
                      style: ResponsiveHelper.tinyStyle(context).copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          Tab(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('급여확정'),
                if (_calculatedWorkers.isNotEmpty) ...[
                  SizedBox(width: ResponsiveHelper.spacing(context, 6)),
                  Container(
                    padding: ResponsiveHelper.symmetricPadding(context, horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: theme.primaryColor,
                      borderRadius: BorderRadius.circular(ResponsiveHelper.spacing(context, 10)),
                    ),
                    child: Text(
                      '${_calculatedWorkers.length}',
                      style: ResponsiveHelper.tinyStyle(context).copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 미확정 탭 — 파트+시간대별 그룹 레이아웃
  Widget _buildPendingTab(BuildContext context, ThemeData theme) {
    if (_pendingWorkers.isEmpty) {
      return _buildEmptyState(context, theme, '미확정 인원이 없습니다', '퇴근 완료된 근무자가 여기에 표시됩니다');
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

  /// 급여확정 탭
  Widget _buildCalculatedTab(BuildContext context, ThemeData theme) {
    if (_calculatedWorkers.isEmpty) {
      return _buildEmptyState(context, theme, '급여 확정된 인원이 없습니다', '급여 확정 후 여기에 표시됩니다');
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
              return _buildWorkerCard(context, theme, app, _calculatedSelectedIds, false);
            },
          ),
        ),
        _buildBottomSection(context, theme, _calculatedSelectedIds, false),
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

  /// 빈 상태
  Widget _buildEmptyState(BuildContext context, ThemeData theme, String title, String subtitle) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.check_circle_outline,
            size: ResponsiveHelper.iconSize(context, 64),
            color: theme.disabledColor,
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 16)),
          Text(
            title,
            style: ResponsiveHelper.subtitleStyle(context).copyWith(
              color: AppColors.grey500,
            ),
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 8)),
          Text(
            subtitle,
            style: ResponsiveHelper.smallStyle(context, color: AppColors.grey400),
            textAlign: TextAlign.center,
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
    final totalAmount = wage?.formattedTotal ?? '계산 중...';
    final accentColor = isPending ? AppColors.warning : theme.primaryColor;
    final breakMins = _getScheduledBreakMinutes(app) + (_groupExtraBreakMinutes[_getGroupKey(app)] ?? 0);

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
                        onTap: () => setState(() {
                          if (isSelected) {
                            selectedIds.remove(app.id);
                          } else {
                            selectedIds.add(app.id);
                          }
                        }),
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
                                      Text(
                                        genderAge,
                                        style: ResponsiveHelper.tinyStyle(context,
                                            color: AppColors.grey400),
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

  /// 하단 섹션
  Widget _buildBottomSection(BuildContext context, ThemeData theme, Set<String> selectedIds, bool isPending) {
    final hasSelection = selectedIds.isNotEmpty;
    final totalWage = _getSelectedTotal(selectedIds);
    
    final buttonColor = isPending ? AppColors.warning : theme.primaryColor;
    final buttonText = isPending 
        ? '급여 확정 (${selectedIds.length}명)'
        : '급여 수정 (${selectedIds.length}명)';
    
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
                    style: ResponsiveHelper.bodyStyle(context).copyWith(color: Colors.black87),
                  ),
                  Text(
                    _formatCurrency(totalWage),
                    style: ResponsiveHelper.subtitleStyle(context).copyWith(
                      fontWeight: FontWeight.bold,
                      color: buttonColor,
                    ),
                  ),
                ],
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
              Expanded(
                flex: 2,
                child: ElevatedButton.icon(
                  onPressed: (hasSelection && !_isProcessing) 
                      ? (isPending ? _confirmWages : _openBatchEditDialog)
                      : null,
                  icon: _isProcessing
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
                    _isProcessing ? '처리 중...' : buttonText,
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
    final timeRange = '${first.startTime} ~ ${first.endTime}';
    final schedBreak = _getScheduledBreakMinutes(first);
    final extra = _groupExtraBreakMinutes[groupKey] ?? 0;
    const options = [0, 30, 60, 90];
    final allGroupSelected = groupWorkers.every((a) => selectedIds.contains(a.id));

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
                activeColor: AppColors.warning,
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
          // 추가공제 라벨
          Row(
            children: [
              Icon(Icons.coffee, size: 12, color: AppColors.grey400),
              SizedBox(width: ResponsiveHelper.spacing(context, 3)),
              Text(
                schedBreak > 0 ? '추가공제 (기본 ${FormatHelper.formatCompactHours(schedBreak)})' : '추가공제',
                style: ResponsiveHelper.tinyStyle(context, color: AppColors.grey500),
              ),
            ],
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 5)),
          // 추가공제 칩 (그룹 일괄 적용)
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

  String _formatCurrency(int amount) {
    return '${amount.toString().replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (Match m) => '${m[1]},',
    )}원';
  }
}