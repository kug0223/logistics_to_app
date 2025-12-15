// lib/screens/business_admin/dialogs/wage_confirm_dialog.dart
// 급여 확정 다이얼로그
// 
// 기능:
// - 당일 확정 근무자 급여 계산
// - 개별/일괄 급여 확정
// - 시급제/일급제 자동 계산
// - 연장/야간수당 적용
// - 추가수당/메모 입력

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

// Models
import '../../../models/core/application_model.dart';
import '../../../models/core/attendance_model.dart';
import '../../../models/core/user_model.dart';
import '../../../models/core/wage_detail_model.dart';

// Utils
import '../../../utils/toast_helper.dart';
import '../../../utils/responsive_helper.dart';
import '../../../utils/dialog_helper.dart';
import '../../../utils/wage_calculator.dart';
import '../../../theme/app_colors.dart';

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

class _WageConfirmDialogState extends State<WageConfirmDialog> {
  // ═══════════════════════════════════════════════════════════
  // 상태 변수
  // ═══════════════════════════════════════════════════════════
  
  bool _isProcessing = false;
  bool _hasChanges = false;
  
  // 선택 상태
  final Set<String> _selectedIds = {};
  bool _selectAll = false;
  
  // 계산된 급여 정보 캐시
  final Map<String, WageDetailModel> _calculatedWages = {};
  
  // 확정 가능한 근무자 (출퇴근 완료)
  List<ApplicationModel> _confirmableWorkers = [];

  @override
  void initState() {
    super.initState();
    _initData();
  }

  /// 초기 데이터 설정
  void _initData() {
    // 퇴근 완료된 근무자만 필터 (급여 확정 가능)
    _confirmableWorkers = widget.workers.where((app) {
      final attendance = widget.attendanceMap[app.id];
      if (attendance == null) return false;
      
      // 퇴근 완료 & 급여 미확정
      final hasCheckOut = attendance.checkOut != null;
      final notConfirmed = attendance.wageStatus != 'confirmed';
      return hasCheckOut && notConfirmed;
    }).toList();
    
    // 급여 미리 계산
    _calculateAllWages();
  }

  /// 전체 급여 계산
  void _calculateAllWages() {
    for (var app in _confirmableWorkers) {
      final wage = _calculateWageForWorker(app);
      if (wage != null) {
        _calculatedWages[app.id] = wage;
      }
    }
  }

  /// 개별 급여 계산
  WageDetailModel? _calculateWageForWorker(ApplicationModel app) {
    final attendance = widget.attendanceMap[app.id];
    if (attendance == null || attendance.checkIn == null || attendance.checkOut == null) {
      return null;
    }
    
    // WorkDetail에서 시간/급여 정보 가져오기
    final workTimeInfo = widget.workDetailTimeMap[app.selectedWorkType];
    final scheduledStart = workTimeInfo?['startTime'] ?? app.startTime;
    final scheduledEnd = workTimeInfo?['endTime'] ?? app.endTime;
    
    // 급여 타입 및 단가 (workDetailTimeMap에서 가져오기)
    final wageType = workTimeInfo?['wageType'] ?? 'hourly';
    final baseWage = workTimeInfo?['wage'] ?? 0;
    
    // 휴게시간 (기본 0분)
    final breakMinutes = workTimeInfo?['breakMinutes'] ?? 0;
    
    try {
      return WageCalculator.calculate(
        wageType: wageType,
        baseWage: baseWage,
        workDate: widget.date,
        scheduledStart: scheduledStart,
        scheduledEnd: scheduledEnd,
        actualStart: attendance.checkIn!,
        actualEnd: attendance.checkOut!,
        breakMinutes: breakMinutes,
        nightAllowanceApplied: true,
      );
    } catch (e) {
      debugPrint('❌ 급여 계산 실패 (${app.id}): $e');
      return null;
    }
  }

  // ═══════════════════════════════════════════════════════════
  // 선택 관련
  // ═══════════════════════════════════════════════════════════

  void _toggleSelectAll(bool value) {
    setState(() {
      _selectAll = value;
      if (value) {
        _selectedIds.clear();
        _selectedIds.addAll(_confirmableWorkers.map((a) => a.id));
      } else {
        _selectedIds.clear();
      }
    });
  }

  void _toggleSelection(String appId) {
    setState(() {
      if (_selectedIds.contains(appId)) {
        _selectedIds.remove(appId);
        _selectAll = false;
      } else {
        _selectedIds.add(appId);
        _selectAll = _selectedIds.length == _confirmableWorkers.length;
      }
    });
  }

  // ═══════════════════════════════════════════════════════════
  // 급여 확정 처리
  // ═══════════════════════════════════════════════════════════

  Future<void> _confirmSelectedWages() async {
    if (_selectedIds.isEmpty) {
      ToastHelper.showWarning('급여 확정할 인원을 선택해주세요');
      return;
    }
    
    final confirmed = await DialogHelper.showConfirm(
      context,
      title: '급여 확정',
      message: '선택한 ${_selectedIds.length}명의 급여를 확정하시겠습니까?\n확정 후에는 수정이 제한됩니다.',
      confirmText: '확정',
    );
    
    if (!confirmed) return;
    
    setState(() => _isProcessing = true);
    
    try {
      final userProvider = Provider.of<UserProvider>(context, listen: false);
      final adminUid = userProvider.currentUser?.uid;
      
      int successCount = 0;
      int failCount = 0;
      
      for (var appId in _selectedIds) {
        final wage = _calculatedWages[appId];
        final attendance = widget.attendanceMap[appId];
        
        if (wage == null || attendance == null) {
          failCount++;
          continue;
        }
        
        try {
          final confirmedWage = wage.copyWith(
            calculatedBy: adminUid,
            calculatedAt: DateTime.now(),
            confirmedBy: adminUid,
            confirmedAt: DateTime.now(),
          );
          
          await FirebaseFirestore.instance
              .collection('attendance')
              .doc(attendance.id)
              .update({
            'wageStatus': 'confirmed',
            'finalWage': confirmedWage.totalAmount,
            'wageDetail': confirmedWage.toMap(),
            'updatedAt': FieldValue.serverTimestamp(),
          });
          
          successCount++;
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
          _selectedIds.clear();
          _selectAll = false;
          _confirmableWorkers.removeWhere((app) => 
            _calculatedWages.containsKey(app.id) && successCount > 0
          );
        });
      }
      
      if (failCount > 0) {
        ToastHelper.showWarning('$failCount명 처리 실패');
      }
    } catch (e) {
      debugPrint('❌ 일괄 급여 확정 실패: $e');
      ToastHelper.showError('급여 확정에 실패했습니다');
    } finally {
      setState(() => _isProcessing = false);
    }
  }

  /// 개별 급여 상세 다이얼로그
  Future<void> _showWageDetailDialog(ApplicationModel app) async {
    final wage = _calculatedWages[app.id];
    final user = widget.userMap[app.uid];
    final attendance = widget.attendanceMap[app.id];
    
    if (wage == null || attendance == null) {
      ToastHelper.showWarning('급여 정보를 계산할 수 없습니다');
      return;
    }
    
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => _WageDetailSubDialog(
        app: app,
        user: user,
        attendance: attendance,
        wage: wage,
        onConfirm: (updatedWage) async {
          try {
            final userProvider = Provider.of<UserProvider>(context, listen: false);
            final adminUid = userProvider.currentUser?.uid;
            
            final confirmedWage = updatedWage.copyWith(
              calculatedBy: adminUid,
              calculatedAt: DateTime.now(),
              confirmedBy: adminUid,
              confirmedAt: DateTime.now(),
            );
            
            await FirebaseFirestore.instance
                .collection('attendance')
                .doc(attendance.id)
                .update({
              'wageStatus': 'confirmed',
              'finalWage': confirmedWage.totalAmount,
              'wageDetail': confirmedWage.toMap(),
              'updatedAt': FieldValue.serverTimestamp(),
            });
            
            return true;
          } catch (e) {
            debugPrint('❌ 개별 급여 확정 실패: $e');
            return false;
          }
        },
      ),
    );
    
    if (result == true) {
      _hasChanges = true;
      widget.onConfirmed?.call();
      
      setState(() {
        _confirmableWorkers.removeWhere((a) => a.id == app.id);
        _calculatedWages.remove(app.id);
        _selectedIds.remove(app.id);
      });
      
      ToastHelper.showSuccess('${user?.name ?? '근무자'} 급여 확정 완료');
    }
  }

  // ═══════════════════════════════════════════════════════════
  // 합계 계산
  // ═══════════════════════════════════════════════════════════

  int get _selectedTotalWage {
    int total = 0;
    for (var appId in _selectedIds) {
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
    final dateStr = DateFormat('M월 d일 (E)', 'ko_KR').format(widget.date);
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
              if (_confirmableWorkers.isNotEmpty)
                _buildSelectionBar(context, theme),
              Expanded(
                child: _confirmableWorkers.isEmpty
                    ? _buildEmptyState(context, theme)
                    : _buildWorkerList(context, theme),
              ),
              _buildBottomSection(context, theme),
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
            theme.primaryColor.withOpacity(0.85),
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
              color: Colors.white.withOpacity(0.2),
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
                  '급여 확정',
                  style: ResponsiveHelper.subtitleStyle(context).copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: ResponsiveHelper.spacing(context, 2)),
                Text(
                  '$dateStr · ${widget.businessName}',
                  style: ResponsiveHelper.smallStyle(context).copyWith(
                    color: Colors.white.withOpacity(0.9),
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

  /// 선택 바
  Widget _buildSelectionBar(BuildContext context, ThemeData theme) {
    final hasSelection = _selectedIds.isNotEmpty;
    
    return Container(
      padding: ResponsiveHelper.symmetricPadding(context, horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        border: Border(bottom: BorderSide(color: theme.dividerColor)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: ResponsiveHelper.spacing(context, 24),
            height: ResponsiveHelper.spacing(context, 24),
            child: Checkbox(
              value: _selectAll,
              onChanged: (value) => _toggleSelectAll(value ?? false),
              activeColor: theme.primaryColor,
            ),
          ),
          SizedBox(width: ResponsiveHelper.spacing(context, 8)),
          Text(
            '전체 선택',
            style: ResponsiveHelper.bodyStyle(context).copyWith(color: Colors.black87),
          ),
          if (hasSelection) ...[
            SizedBox(width: ResponsiveHelper.spacing(context, 8)),
            Container(
              padding: ResponsiveHelper.symmetricPadding(context, horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: theme.primaryColor,
                borderRadius: BorderRadius.circular(ResponsiveHelper.spacing(context, 10)),
              ),
              child: Text(
                '${_selectedIds.length}명',
                style: ResponsiveHelper.tinyStyle(context).copyWith(color: Colors.white),
              ),
            ),
          ],
          const Spacer(),
          Text(
            '총 ${_confirmableWorkers.length}명',
            style: ResponsiveHelper.smallStyle(context, color: AppColors.grey600),
          ),
        ],
      ),
    );
  }

  /// 빈 상태
  Widget _buildEmptyState(BuildContext context, ThemeData theme) {
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
            '급여 확정할 인원이 없습니다',
            style: ResponsiveHelper.subtitleStyle(context).copyWith(
              color: AppColors.grey500,
            ),
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 8)),
          Text(
            '퇴근 완료된 근무자만 급여를 확정할 수 있습니다',
            style: ResponsiveHelper.smallStyle(context, color: AppColors.grey400),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  /// 근무자 목록
  Widget _buildWorkerList(BuildContext context, ThemeData theme) {
    return ListView.builder(
      padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 16)),
      itemCount: _confirmableWorkers.length,
      itemBuilder: (context, index) {
        final app = _confirmableWorkers[index];
        return _buildWorkerCard(context, theme, app);
      },
    );
  }

  /// 근무자 카드
  Widget _buildWorkerCard(BuildContext context, ThemeData theme, ApplicationModel app) {
    final user = widget.userMap[app.uid];
    final attendance = widget.attendanceMap[app.id];
    final wage = _calculatedWages[app.id];
    final isSelected = _selectedIds.contains(app.id);
    
    final name = user?.name ?? '이름 없음';
    final genderAge = _formatGenderAge(user);
    final workTime = '${attendance?.checkIn ?? '-'} ~ ${attendance?.checkOut ?? '-'}';
    final workHours = wage?.workHours.toStringAsFixed(1) ?? '-';
    final totalAmount = wage?.formattedTotal ?? '계산 불가';
    
    return Container(
      margin: EdgeInsets.only(bottom: ResponsiveHelper.spacing(context, 12)),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(ResponsiveHelper.spacing(context, 16)),
        border: Border.all(
          color: isSelected ? theme.primaryColor : theme.dividerColor,
          width: isSelected ? 2 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: ResponsiveHelper.spacing(context, 8),
            offset: Offset(0, ResponsiveHelper.spacing(context, 2)),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _showWageDetailDialog(app),
          borderRadius: BorderRadius.circular(ResponsiveHelper.spacing(context, 16)),
          child: Padding(
            padding: ResponsiveHelper.cardPadding(context),
            child: Row(
              children: [
                // 체크박스
                SizedBox(
                  width: ResponsiveHelper.spacing(context, 24),
                  height: ResponsiveHelper.spacing(context, 24),
                  child: Checkbox(
                    value: isSelected,
                    onChanged: (_) => _toggleSelection(app.id),
                    activeColor: theme.primaryColor,
                  ),
                ),
                SizedBox(width: ResponsiveHelper.spacing(context, 12)),
                
                // 정보
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 이름
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              name,
                              style: ResponsiveHelper.bodyStyle(context).copyWith(
                                fontWeight: FontWeight.bold,
                                color: Colors.black87,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (genderAge.isNotEmpty) ...[
                            SizedBox(width: ResponsiveHelper.spacing(context, 4)),
                            Text(
                              genderAge,
                              style: ResponsiveHelper.smallStyle(context, color: AppColors.grey500),
                            ),
                          ],
                        ],
                      ),
                      SizedBox(height: ResponsiveHelper.spacing(context, 6)),
                      
                      // 업무 + 시간 (한 줄로)
                      Row(
                        children: [
                          Container(
                            padding: ResponsiveHelper.symmetricPadding(context, horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: theme.primaryColor.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(ResponsiveHelper.spacing(context, 6)),
                            ),
                            child: Text(
                              app.selectedWorkType,
                              style: ResponsiveHelper.tinyStyle(context).copyWith(
                                color: theme.primaryColor,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                          Flexible(
                            child: Text(
                              '$workTime · ${workHours}h',
                              style: ResponsiveHelper.smallStyle(context, color: AppColors.grey600),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                
                SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                
                // 급여
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      totalAmount,
                      style: ResponsiveHelper.subtitleStyle(context).copyWith(
                        fontWeight: FontWeight.bold,
                        color: theme.primaryColor,
                      ),
                    ),
                    Text(
                      wage?.wageTypeLabel ?? '',
                      style: ResponsiveHelper.tinyStyle(context, color: AppColors.grey500),
                    ),
                  ],
                ),
                
                SizedBox(width: ResponsiveHelper.spacing(context, 4)),
                Icon(
                  Icons.chevron_right,
                  color: theme.disabledColor,
                  size: ResponsiveHelper.iconSize(context, 20),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 하단 섹션
  Widget _buildBottomSection(BuildContext context, ThemeData theme) {
    final hasSelection = _selectedIds.isNotEmpty;
    
    return Container(
      padding: ResponsiveHelper.cardPadding(context),
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(ResponsiveHelper.spacing(context, 20)),
          bottomRight: Radius.circular(ResponsiveHelper.spacing(context, 20)),
        ),
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
                color: theme.primaryColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(ResponsiveHelper.spacing(context, 12)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.payments,
                    color: theme.primaryColor,
                    size: ResponsiveHelper.iconSize(context, 20),
                  ),
                  SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                  Text(
                    '선택 급여 합계: ',
                    style: ResponsiveHelper.bodyStyle(context).copyWith(color: Colors.black87),
                  ),
                  Text(
                    _formatCurrency(_selectedTotalWage),
                    style: ResponsiveHelper.subtitleStyle(context).copyWith(
                      fontWeight: FontWeight.bold,
                      color: theme.primaryColor,
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
                      ? _confirmSelectedWages 
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
                      : Icon(Icons.check, size: ResponsiveHelper.iconSize(context, 20)),
                  label: Text(
                    _isProcessing ? '처리 중...' : '선택 급여 확정 (${_selectedIds.length}명)',
                    style: ResponsiveHelper.bodyStyle(context).copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: hasSelection ? theme.primaryColor : theme.disabledColor,
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

// ═══════════════════════════════════════════════════════════
// 개별 급여 상세 서브 다이얼로그
// ═══════════════════════════════════════════════════════════

class _WageDetailSubDialog extends StatefulWidget {
  final ApplicationModel app;
  final UserModel? user;
  final AttendanceModel attendance;
  final WageDetailModel wage;
  final Future<bool> Function(WageDetailModel) onConfirm;

  const _WageDetailSubDialog({
    required this.app,
    required this.user,
    required this.attendance,
    required this.wage,
    required this.onConfirm,
  });

  @override
  State<_WageDetailSubDialog> createState() => _WageDetailSubDialogState();
}

class _WageDetailSubDialogState extends State<_WageDetailSubDialog> {
  late WageDetailModel _wage;
  final _additionalController = TextEditingController();
  final _memoController = TextEditingController();
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    _wage = widget.wage;
    _additionalController.text = widget.wage.additionalAmount > 0 
        ? widget.wage.additionalAmount.toString() 
        : '';
    _memoController.text = widget.wage.memo ?? '';
  }

  @override
  void dispose() {
    _additionalController.dispose();
    _memoController.dispose();
    super.dispose();
  }

  void _updateWage() {
    final additional = int.tryParse(_additionalController.text) ?? 0;
    final newTotal = _wage.baseAmount + _wage.overtimeAmount + _wage.nightAmount + additional;
    
    setState(() {
      _wage = _wage.copyWith(
        additionalAmount: additional,
        totalAmount: newTotal,
        memo: _memoController.text.trim().isNotEmpty ? _memoController.text.trim() : null,
      );
    });
  }

  Future<void> _confirm() async {
    setState(() => _isProcessing = true);
    
    _updateWage();
    final success = await widget.onConfirm(_wage);
    
    if (success && mounted) {
      Navigator.pop(context, true);
    } else {
      setState(() => _isProcessing = false);
      ToastHelper.showError('급여 확정에 실패했습니다');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = widget.user?.name ?? '이름 없음';
    final screenWidth = MediaQuery.of(context).size.width;

    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(ResponsiveHelper.spacing(context, 20)),
      ),
      child: Container(
        width: screenWidth * 0.9,
        constraints: BoxConstraints(maxWidth: screenWidth * 0.95),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 헤더
            Container(
              padding: ResponsiveHelper.cardPadding(context),
              decoration: BoxDecoration(
                color: theme.primaryColor,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(ResponsiveHelper.spacing(context, 20)),
                  topRight: Radius.circular(ResponsiveHelper.spacing(context, 20)),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.receipt_long,
                    color: Colors.white,
                    size: ResponsiveHelper.iconSize(context, 24),
                  ),
                  SizedBox(width: ResponsiveHelper.spacing(context, 12)),
                  Expanded(
                    child: Text(
                      '$name 급여 상세',
                      style: ResponsiveHelper.subtitleStyle(context).copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
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
            ),

            // 내용
            Flexible(
              child: SingleChildScrollView(
                padding: ResponsiveHelper.cardPadding(context),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildInfoSection(context, theme),
                    Divider(height: ResponsiveHelper.spacing(context, 24)),
                    _buildWageSection(context, theme),
                    Divider(height: ResponsiveHelper.spacing(context, 24)),
                    _buildAdditionalSection(context, theme),
                    SizedBox(height: ResponsiveHelper.spacing(context, 16)),
                    _buildMemoSection(context, theme),
                  ],
                ),
              ),
            ),

            // 하단 버튼
            Container(
              padding: ResponsiveHelper.cardPadding(context),
              decoration: BoxDecoration(
                color: theme.scaffoldBackgroundColor,
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(ResponsiveHelper.spacing(context, 20)),
                  bottomRight: Radius.circular(ResponsiveHelper.spacing(context, 20)),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _isProcessing ? null : () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        padding: EdgeInsets.symmetric(
                          vertical: ResponsiveHelper.spacing(context, 14),
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(ResponsiveHelper.spacing(context, 12)),
                        ),
                      ),
                      child: Text(
                        '취소',
                        style: ResponsiveHelper.bodyStyle(context),
                      ),
                    ),
                  ),
                  SizedBox(width: ResponsiveHelper.spacing(context, 12)),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton.icon(
                      onPressed: _isProcessing ? null : _confirm,
                      icon: _isProcessing
                          ? SizedBox(
                              width: ResponsiveHelper.spacing(context, 18),
                              height: ResponsiveHelper.spacing(context, 18),
                              child: CircularProgressIndicator(
                                strokeWidth: ResponsiveHelper.spacing(context, 2),
                                color: Colors.white,
                              ),
                            )
                          : Icon(Icons.check, size: ResponsiveHelper.iconSize(context, 20)),
                      label: Text(
                        _isProcessing ? '처리 중...' : '급여 확정',
                        style: ResponsiveHelper.bodyStyle(context).copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: theme.primaryColor,
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
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoSection(BuildContext context, ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '근무 정보',
          style: ResponsiveHelper.bodyStyle(context).copyWith(
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
        ),
        SizedBox(height: ResponsiveHelper.spacing(context, 12)),
        _buildInfoRow(context, theme, '업무', widget.app.selectedWorkType),
        _buildInfoRow(context, theme, '출근', widget.attendance.checkIn ?? '-'),
        _buildInfoRow(context, theme, '퇴근', widget.attendance.checkOut ?? '-'),
        _buildInfoRow(context, theme, '근무시간', '${_wage.workHours.toStringAsFixed(1)}시간'),
        if (_wage.overtimeMinutes > 0)
          _buildInfoRow(context, theme, '연장근무', '${_wage.overtimeHours.toStringAsFixed(1)}시간', highlight: true),
        if (_wage.nightMinutes > 0)
          _buildInfoRow(context, theme, '야간근무', '${_wage.nightHours.toStringAsFixed(1)}시간', highlight: true),
      ],
    );
  }

  Widget _buildWageSection(BuildContext context, ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '급여 상세',
          style: ResponsiveHelper.bodyStyle(context).copyWith(
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
        ),
        SizedBox(height: ResponsiveHelper.spacing(context, 12)),
        _buildWageRow(context, theme, '기본급', _wage.baseAmount),
        if (_wage.overtimeAmount > 0)
          _buildWageRow(context, theme, '연장수당', _wage.overtimeAmount, highlight: true),
        if (_wage.nightAmount > 0)
          _buildWageRow(context, theme, '야간수당', _wage.nightAmount, highlight: true),
        if (_wage.additionalAmount > 0)
          _buildWageRow(context, theme, '추가수당', _wage.additionalAmount),
        SizedBox(height: ResponsiveHelper.spacing(context, 8)),
        Container(
          padding: ResponsiveHelper.symmetricPadding(context, horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: theme.primaryColor.withOpacity(0.1),
            borderRadius: BorderRadius.circular(ResponsiveHelper.spacing(context, 8)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '총 급여',
                style: ResponsiveHelper.bodyStyle(context).copyWith(
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              Text(
                _formatCurrency(_wage.totalAmount),
                style: ResponsiveHelper.subtitleStyle(context).copyWith(
                  fontWeight: FontWeight.bold,
                  color: theme.primaryColor,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildAdditionalSection(BuildContext context, ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '추가수당',
          style: ResponsiveHelper.bodyStyle(context).copyWith(
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
        ),
        SizedBox(height: ResponsiveHelper.spacing(context, 8)),
        TextField(
          controller: _additionalController,
          keyboardType: TextInputType.number,
          style: ResponsiveHelper.bodyStyle(context).copyWith(color: Colors.black87),
          decoration: InputDecoration(
            hintText: '0',
            hintStyle: ResponsiveHelper.bodyStyle(context, color: AppColors.grey400),
            suffixText: '원',
            suffixStyle: ResponsiveHelper.bodyStyle(context),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(ResponsiveHelper.spacing(context, 12)),
            ),
            contentPadding: ResponsiveHelper.symmetricPadding(context, horizontal: 12, vertical: 12),
          ),
          onChanged: (_) => _updateWage(),
        ),
      ],
    );
  }

  Widget _buildMemoSection(BuildContext context, ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '메모',
          style: ResponsiveHelper.bodyStyle(context).copyWith(
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
        ),
        SizedBox(height: ResponsiveHelper.spacing(context, 8)),
        TextField(
          controller: _memoController,
          maxLines: 2,
          style: ResponsiveHelper.bodyStyle(context).copyWith(color: Colors.black87),
          decoration: InputDecoration(
            hintText: '메모 입력 (선택)',
            hintStyle: ResponsiveHelper.bodyStyle(context, color: AppColors.grey400),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(ResponsiveHelper.spacing(context, 12)),
            ),
            contentPadding: EdgeInsets.all(ResponsiveHelper.spacing(context, 12)),
          ),
        ),
      ],
    );
  }

  Widget _buildInfoRow(BuildContext context, ThemeData theme, String label, String value, {bool highlight = false}) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: ResponsiveHelper.spacing(context, 4)),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: ResponsiveHelper.smallStyle(context, color: AppColors.grey600),
          ),
          Text(
            value,
            style: ResponsiveHelper.bodyStyle(context).copyWith(
              color: highlight ? theme.primaryColor : Colors.black87,
              fontWeight: highlight ? FontWeight.w600 : null,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWageRow(BuildContext context, ThemeData theme, String label, int amount, {bool highlight = false}) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: ResponsiveHelper.spacing(context, 4)),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: ResponsiveHelper.smallStyle(context, color: AppColors.grey600),
          ),
          Text(
            _formatCurrency(amount),
            style: ResponsiveHelper.bodyStyle(context).copyWith(
              color: highlight ? theme.primaryColor : Colors.black87,
              fontWeight: highlight ? FontWeight.w600 : null,
            ),
          ),
        ],
      ),
    );
  }

  String _formatCurrency(int amount) {
    return '${amount.toString().replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (Match m) => '${m[1]},',
    )}원';
  }
}