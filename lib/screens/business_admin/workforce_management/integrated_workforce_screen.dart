import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../theme/app_colors.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../providers/user_provider.dart';
import '../../../utils/toast_helper.dart';
import '../../../utils/responsive_helper.dart';
import '../../../services/firestore_service.dart';
import 'workforce_list_view.dart';
import 'workforce_calendar_view.dart';
import '../../../utils/test_data_helper.dart';
import '../../../models/core/to_model.dart';
import '../dialogs/schedule_request_management_dialog.dart';
import '../../../utils/dialog_helper.dart';

/// ✨ 세련된 통합 인력 관리 화면 (business_home_screen 테마 적용)
class IntegratedWorkforceScreen extends StatefulWidget {
  const IntegratedWorkforceScreen({super.key});

  @override
  State<IntegratedWorkforceScreen> createState() =>
      _IntegratedWorkforceScreenState();
}

class _IntegratedWorkforceScreenState extends State<IntegratedWorkforceScreen> {
  final FirestoreService _firestoreService = FirestoreService();
  List<String> _allBusinessIds = [];
  String? _selectedBusinessId;
  bool _isCalendarView = false;

  @override
  void initState() {
    super.initState();
    _loadBusinessIds();
  }

  /// 관리자의 모든 사업장 ID 로드
  Future<void> _loadBusinessIds() async {
    try {
      final userProvider = context.read<UserProvider>();
      final uid = userProvider.currentUser?.uid;

      if (uid == null) {
        ToastHelper.showWarning('로그인 정보를 찾을 수 없습니다.');
        return;
      }

      final businesses = await _firestoreService.getMyBusiness(uid);

      if (businesses.isEmpty) {
        ToastHelper.showWarning('등록된 사업장이 없습니다.');
        return;
      }

      setState(() {
        _allBusinessIds = businesses.map((b) => b.id).toList();
        _selectedBusinessId = _allBusinessIds.first;
      });

      debugPrint('✅ 관리 사업장: ${_allBusinessIds.length}개');
    } catch (e) {
      debugPrint('❌ 사업장 조회 실패: $e');
      ToastHelper.showError('사업장 정보를 불러올 수 없습니다.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    if (_selectedBusinessId == null) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 24)),
                decoration: BoxDecoration(
                  color: theme.primaryColor.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.business_center,
                  size: ResponsiveHelper.iconSize(context, 64),
                  color: theme.primaryColor.withOpacity(0.5),
                ),
              ),
              SizedBox(height: ResponsiveHelper.spacing(context, 24)),
              Text(
                '등록된 사업장이 없습니다',
                style: ResponsiveHelper.titleStyle(context).copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      // ✨ 깔끔한 AppBar (홈 화면 스타일)
      appBar: AppBar(
        title: Text(_isCalendarView ? '공고-캘린더' : '공고-리스트'),
            actions: [
              
              // ✅ 통계 재계산 버튼 (임시 디버그용)
              IconButton(
                icon: Icon(
                  Icons.sync,
                  size: ResponsiveHelper.iconSize(context, 24),
                ),
                onPressed: _recalculateAllStats,
                tooltip: '통계 재계산',
              ),
              // 더미 데이터 버튼
              IconButton(
                icon: Icon(
                  Icons.science,
                  size: ResponsiveHelper.iconSize(context, 24),
                ),
                onPressed: _showDummyDataDialog,
                tooltip: '테스트 데이터',
              ),
              
              // 스케줄 변경 요청 관리 버튼
              FutureBuilder<int>(
                future: _firestoreService.getPendingScheduleChangeRequestCount(_selectedBusinessId ?? ''),
                builder: (context, snapshot) {
                  final count = snapshot.data ?? 0;
                  
                  return Stack(
                    children: [
                      IconButton(
                        icon: Icon(
                          Icons.edit_calendar,
                          size: ResponsiveHelper.iconSize(context, 24),
                        ),
                        onPressed: _showScheduleRequestManagement,
                        tooltip: '스케줄 변경 요청',
                      ),
                      if (count > 0)
                        Positioned(
                          right: 8,
                          top: 8,
                          child: Container(
                            padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 4)),
                            decoration: BoxDecoration(
                              color: Colors.red,
                              shape: BoxShape.circle,
                            ),
                            constraints: BoxConstraints(
                              minWidth: ResponsiveHelper.iconSize(context, 18),
                              minHeight: ResponsiveHelper.iconSize(context, 18),
                            ),
                            child: Text(
                              '$count',
                              style: ResponsiveHelper.tinyStyle(context).copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
              
              
              // 리스트/캘린더 토글 (탭바 스타일)
              Container(
                margin: EdgeInsets.only(right: ResponsiveHelper.spacing(context, 8)),
                padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 4)),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    _buildToggleButton(
                      icon: Icons.view_list,
                      label: '목록',
                      isSelected: !_isCalendarView,
                      onTap: () {
                        setState(() {
                          _isCalendarView = false;
                        });
                      },
                    ),
                    SizedBox(width: ResponsiveHelper.spacing(context, 4)),
                    _buildToggleButton(
                      icon: Icons.calendar_month,
                      label: '캘린더',
                      isSelected: _isCalendarView,
                      onTap: () {
                        setState(() {
                          _isCalendarView = true;
                        });
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
      // ✨ 깔끔한 흰색 배경 (홈 화면과 일치)
      body: _isCalendarView
          ? const WorkforceCalendarView()
          : const WorkforceListView(),
    );
  }

  /// ✨ 토글 버튼 (탭바 스타일 - 명확하게 보임)
  Widget _buildToggleButton({
    required IconData icon,
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: ResponsiveHelper.spacing(context, 12),
          vertical: ResponsiveHelper.spacing(context, 8),
        ),
        decoration: BoxDecoration(
          color: isSelected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: ResponsiveHelper.iconSize(context, 18),
              color: isSelected ? Theme.of(context).primaryColor : Colors.white,
            ),
            SizedBox(width: ResponsiveHelper.spacing(context, 6)),
            Text(
              label,
              style: ResponsiveHelper.smallStyle(context).copyWith(
                fontWeight: FontWeight.w600,
                color: isSelected ? Theme.of(context).primaryColor : Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  /// 스케줄 변경 요청 관리 다이얼로그 표시
  void _showScheduleRequestManagement() {
    if (_selectedBusinessId == null) {
      ToastHelper.showWarning('사업장 정보를 찾을 수 없습니다.');
      return;
    }
    
    showDialog(
      context: context,
      builder: (context) => ScheduleRequestManagementDialog(
        businessId: _selectedBusinessId!,
        onChanged: () {
          setState(() {});
        },
      ),
    );
  }

  /// ⭐ 더미 데이터 다이얼로그 (반응형 + 테마)
  Future<void> _showDummyDataDialog() async {
    if (_selectedBusinessId == null) {
      ToastHelper.showError('사업장이 선택되지 않았습니다.');
      return;
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(
              Icons.science, 
              color: Colors.orange,
              size: ResponsiveHelper.iconSize(context, 24),
            ),
            SizedBox(width: ResponsiveHelper.spacing(context, 8)),
            Text(
              '테스트 데이터 관리',
              style: ResponsiveHelper.titleStyle(context),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '개발/테스트용 더미 데이터를 관리합니다.',
              style: ResponsiveHelper.bodyStyle(
                context,
                color: Theme.of(context).textTheme.bodySmall?.color,
              ),
            ),
            SizedBox(height: ResponsiveHelper.spacing(context, 16)),
            
            // ⭐ TO 선택하여 지원자 생성
            ListTile(
              leading: Icon(
                Icons.group_add, 
                color: Theme.of(context).primaryColor,
                size: ResponsiveHelper.iconSize(context, 24),
              ),
              title: Text(
                'TO에 지원자 추가',
                style: ResponsiveHelper.bodyStyle(context).copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              subtitle: Text(
                'TO 선택 → 확정/대기 인원 생성',
                style: ResponsiveHelper.smallStyle(context),
              ),
              onTap: () async {
                Navigator.pop(context);
                await _showCreateApplicantsDialog();
              },
            ),
            
            const Divider(),
            // ⭐ 리뷰 생성
            ListTile(
              leading: Icon(
                Icons.star, 
                color: Colors.amber,
                size: ResponsiveHelper.iconSize(context, 24),
              ),
              title: Text(
                '더미 리뷰 생성',
                style: ResponsiveHelper.bodyStyle(context).copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              subtitle: Text(
                '확정 지원서에 랜덤 리뷰 추가',
                style: ResponsiveHelper.smallStyle(context),
              ),
              onTap: () async {
                Navigator.pop(context);
                await _createDummyReviews();
              },
            ),
            
            const Divider(),
            
            // ⭐ 출근 데이터 생성
            ListTile(
              leading: Icon(
                Icons.add_circle, 
                color: Colors.green,
                size: ResponsiveHelper.iconSize(context, 24),
              ),
              title: Text(
                '오늘 출근 데이터 생성',
                style: ResponsiveHelper.bodyStyle(context).copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              subtitle: Text(
                '확정 인원의 70% 출근 처리',
                style: ResponsiveHelper.smallStyle(context),
              ),
              onTap: () async {
                Navigator.pop(context);
                await _createTodayAttendance();
              },
            ),
            
            const Divider(),
            
            // ⭐ 출근 데이터 삭제
            ListTile(
              leading: Icon(
                Icons.delete_sweep, 
                color: Colors.orange,
                size: ResponsiveHelper.iconSize(context, 24),
              ),
              title: Text(
                '출근 데이터 삭제',
                style: ResponsiveHelper.bodyStyle(context).copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              subtitle: Text(
                '모든 더미 출근 기록 삭제',
                style: ResponsiveHelper.smallStyle(context),
              ),
              onTap: () async {
                Navigator.pop(context);
                await _clearAttendanceData();
              },
            ),

            const Divider(),
            
            // ⭐ 더미 리뷰 삭제
            ListTile(
              leading: Icon(
                Icons.star_border, 
                color: AppColors.amberDark,
                size: ResponsiveHelper.iconSize(context, 24),
              ),
              title: Text(
                '더미 리뷰 삭제',
                style: ResponsiveHelper.bodyStyle(context).copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              subtitle: Text(
                '모든 더미 리뷰 삭제',
                style: ResponsiveHelper.smallStyle(context),
              ),
              onTap: () async {
                Navigator.pop(context);
                await _clearDummyReviews();
              },
            ),
            
            const Divider(),
            
            // ⭐ 지원자 데이터 삭제
            ListTile(
              leading: Icon(
                Icons.delete_forever, 
                color: Theme.of(context).colorScheme.error,
                size: ResponsiveHelper.iconSize(context, 24),
              ),
              title: Text(
                '모든 더미 데이터 삭제',
                style: ResponsiveHelper.bodyStyle(context).copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              subtitle: Text(
                '지원자 + 지원서 + 출근 기록',
                style: ResponsiveHelper.smallStyle(context),
              ),
              onTap: () async {
                Navigator.pop(context);
                await _clearAllDummyData();
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('닫기'),
          ),
        ],
      ),
    );
  }
  
  /// ⭐ TO 선택하여 지원자 생성 다이얼로그 (반응형 + 테마)
  Future<void> _showCreateApplicantsDialog() async {
    String? targetBusinessId = _selectedBusinessId;
    
    if (_allBusinessIds.length > 1) {
      targetBusinessId = await _selectBusinessForDummyData();
      if (targetBusinessId == null) return;
    }
    
    debugPrint('🔍 [DummyData] 선택된 사업장: $targetBusinessId');
    
    List<TOModel> allSelectableTOs = [];
    
    // ✅ Step 1: groups 컬렉션에서 active 그룹 조회
    final activeGroups = await _firestoreService.getActiveGroups(
      businessId: targetBusinessId,
    );
    debugPrint('   active 그룹: ${activeGroups.length}개');
    
    // 각 그룹의 하위 TO들 가져오기
    for (var group in activeGroups) {
      final groupTOs = await _firestoreService.getTOsByGroup(group.id);
      debugPrint('   📋 그룹 "${group.groupName}": ${groupTOs.length}개 TO');
      allSelectableTOs.addAll(groupTOs);
    }
    
    // ✅ Step 2: 단일 TO 조회 (groupId가 null인 것들)
    final activeTOs = await _firestoreService.getActiveTOs();
    final singleTOs = activeTOs.where((to) => 
        to.groupId == null && 
        to.businessId == targetBusinessId
    ).toList();
    debugPrint('   단일 TO: ${singleTOs.length}개');
    allSelectableTOs.addAll(singleTOs);
    
    debugPrint('   🎯 총 선택 가능한 TO: ${allSelectableTOs.length}개');
    
    if (allSelectableTOs.isEmpty) {
      ToastHelper.showWarning('선택 가능한 TO가 없습니다.');
      return;
    }

    debugPrint('   🎯 선택 가능한 TO: ${allSelectableTOs.length}개');
    if (allSelectableTOs.isEmpty) {
      ToastHelper.showWarning('선택 가능한 TO가 없습니다.');
      return;
    }

    allSelectableTOs.sort((a, b) => a.date.compareTo(b.date));

    TOModel? selectedTO = allSelectableTOs.isNotEmpty ? allSelectableTOs.first : null;
    
    final confirmedController = TextEditingController();
    final pendingController = TextEditingController();

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(
            '지원자 생성',
            style: ResponsiveHelper.titleStyle(context),
          ),
          content: SizedBox(
            width: MediaQuery.of(context).size.width * 0.8,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // TO 선택
                Text(
                  'TO 선택',
                  style: ResponsiveHelper.bodyStyle(context).copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: ResponsiveHelper.spacing(context, 8)),
                Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: ResponsiveHelper.spacing(context, 12),
                  ),
                  decoration: BoxDecoration(
                    border: Border.all(color: Theme.of(context).dividerColor),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<TOModel>(
                      isExpanded: true,
                      value: selectedTO,
                      style: ResponsiveHelper.bodyStyle(context),
                      items: allSelectableTOs.map((to) {
                        final dateStr = DateFormat('M/d (E)', 'ko_KR').format(to.date);
                        final timeStr = to.isGrouped ? '(그룹)' : '';
                        return DropdownMenuItem(
                          value: to,
                          child: Text(
                            '$dateStr - ${to.title} $timeStr',
                            overflow: TextOverflow.ellipsis,
                          ),
                        );
                      }).toList(),
                      onChanged: (value) {
                        setState(() {
                          selectedTO = value;
                        });
                      },
                    ),
                  ),
                ),
                
                SizedBox(height: ResponsiveHelper.spacing(context, 24)),
                
                // 확정 인원
                Text(
                  '확정 인원',
                  style: ResponsiveHelper.bodyStyle(context).copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: ResponsiveHelper.spacing(context, 8)),
                TextField(
                  controller: confirmedController,
                  keyboardType: TextInputType.number,
                  style: ResponsiveHelper.bodyStyle(context),
                  decoration: InputDecoration(
                    border: OutlineInputBorder(),
                    suffixText: '명',
                    hintText: '0',
                    hintStyle: ResponsiveHelper.bodyStyle(
                      context,
                      color: Theme.of(context).hintColor,
                    ),
                  ),
                ),
                
                SizedBox(height: ResponsiveHelper.spacing(context, 16)),
                
                // 대기 인원
                Text(
                  '대기 인원',
                  style: ResponsiveHelper.bodyStyle(context).copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: ResponsiveHelper.spacing(context, 8)),
                TextField(
                  controller: pendingController,
                  keyboardType: TextInputType.number,
                  style: ResponsiveHelper.bodyStyle(context),
                  decoration: InputDecoration(
                    border: OutlineInputBorder(),
                    suffixText: '명',
                    hintText: '0',
                    hintStyle: ResponsiveHelper.bodyStyle(
                      context,
                      color: Theme.of(context).hintColor,
                    ),
                  ),
                ),
                
                SizedBox(height: ResponsiveHelper.spacing(context, 16)),
                
                // 안내
                Container(
                  padding: ResponsiveHelper.cardPadding(context),
                  decoration: BoxDecoration(
                    color: Theme.of(context).primaryColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.info_outline, 
                        size: ResponsiveHelper.iconSize(context, 20),
                        color: Theme.of(context).primaryColor,
                      ),
                      SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                      Expanded(
                        child: Text(
                          '업무 유형별로 랜덤 배분됩니다',
                          style: ResponsiveHelper.smallStyle(
                            context,
                            color: Theme.of(context).primaryColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('취소'),
            ),
            ElevatedButton(
              onPressed: selectedTO == null
                  ? null
                  : () => Navigator.pop(context, true),
              child: const Text('생성하기'),
            ),
          ],
        ),
      ),
    );

    if (result != true || selectedTO == null) return;

    try {
      final confirmedCount = int.tryParse(confirmedController.text) ?? 0;
      final pendingCount = int.tryParse(pendingController.text) ?? 0;

      if (confirmedCount == 0 && pendingCount == 0) {
        ToastHelper.showWarning('인원을 1명 이상 입력하세요.');
        return;
      }

      ToastHelper.showInfo('지원자 생성 중...');

      final workDetails = await _firestoreService.getWorkDetails(selectedTO!.id);
      final workTypes = workDetails.map((wd) => wd.workType).toList();

      await TestDataHelper.createDummyApplications(
        toId: selectedTO!.id,
        workTypes: workTypes,
        pendingCount: pendingCount,
        confirmedCount: confirmedCount,
      );

      ToastHelper.showSuccess('지원자가 생성되었습니다!');

      _firestoreService.clearCache(toId: selectedTO!.id);
      _firestoreService.invalidateListCache();  // 🔥 목록 캐시도 무효화
      
      if (mounted) {
        setState(() {});
      }
    } catch (e) {
      debugPrint('❌ 지원자 생성 실패: $e');
      ToastHelper.showError('지원자 생성 실패: $e');
    }
  }

  /// 오늘 출근 데이터 생성
  Future<void> _createTodayAttendance() async {
    try {
      ToastHelper.showInfo('출근 데이터 생성 중...');
      
      await TestDataHelper.createDummyAttendance(
        businessId: _selectedBusinessId!,
        date: DateTime.now(),
      );
      
      ToastHelper.showSuccess('출근 데이터가 생성되었습니다!');
      
      _firestoreService.clearCache();
      _firestoreService.invalidateListCache();  // 🔥 목록 캐시도 무효화
      
      if (mounted) {
        setState(() {});
      }
    } catch (e) {
      debugPrint('❌ 출근 데이터 생성 실패: $e');
      ToastHelper.showError('출근 데이터 생성 실패: $e');
    }
  }

  /// 출근 데이터 삭제
  Future<void> _clearAttendanceData() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('출근 데이터 삭제'),
        content: const Text('모든 더미 출근 기록을 삭제하시겠습니까?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('삭제'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      ToastHelper.showInfo('출근 데이터 삭제 중...');
      
      await TestDataHelper.clearDummyAttendance();
      
      ToastHelper.showSuccess('출근 데이터가 삭제되었습니다!');
      
      _firestoreService.clearCache();
      
      if (mounted) {
        setState(() {});
      }
    } catch (e) {
      debugPrint('❌ 출근 데이터 삭제 실패: $e');
      ToastHelper.showError('출근 데이터 삭제 실패: $e');
    }
  }

  /// 더미 리뷰 삭제
  Future<void> _clearDummyReviews() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('더미 리뷰 삭제'),
        content: const Text('모든 더미 리뷰를 삭제하시겠습니까?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('삭제'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      ToastHelper.showInfo('더미 리뷰 삭제 중...');
      
      await TestDataHelper.clearDummyReviews();
      
      ToastHelper.showSuccess('더미 리뷰가 삭제되었습니다!');
      
      _firestoreService.clearCache();
      
      if (mounted) {
        setState(() {});
      }
    } catch (e) {
      debugPrint('❌ 더미 리뷰 삭제 실패: $e');
      ToastHelper.showError('더미 리뷰 삭제 실패: $e');
    }
  }
  /// 더미 리뷰 생성
  Future<void> _createDummyReviews() async {
    if (_selectedBusinessId == null) {
      ToastHelper.showWarning('사업장을 선택해주세요');
      return;
    }

    try {
      final userProvider = context.read<UserProvider>();
      final currentUser = userProvider.currentUser;
      
      if (currentUser == null) {
        ToastHelper.showError('로그인 정보를 확인할 수 없습니다');
        return;
      }

      // 사업장 이름 가져오기
      String businessName = '사업장';
      try {
        final businessDoc = await FirebaseFirestore.instance
            .collection('businesses')
            .doc(_selectedBusinessId)
            .get();
        if (businessDoc.exists) {
          businessName = businessDoc.data()?['name'] ?? '사업장';
        }
      } catch (e) {
        debugPrint('⚠️ 사업장명 조회 실패: $e');
      }

      ToastHelper.showInfo('리뷰 생성 중...');
      
      await TestDataHelper.createDummyReviews(
        businessId: _selectedBusinessId!,
        businessName: businessName,
        reviewerId: currentUser.uid,
        reviewerName: currentUser.name,
      );
      
      ToastHelper.showSuccess('더미 리뷰 생성 완료!');
      
      if (mounted) {
        setState(() {});
      }
    } catch (e) {
      debugPrint('❌ 리뷰 생성 실패: $e');
      ToastHelper.showError('리뷰 생성 실패: $e');
    }
  }
  

  /// 모든 더미 데이터 삭제
  Future<void> _clearAllDummyData() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('⚠️ 모든 더미 데이터 삭제'),
        content: const Text(
          '지원자, 지원서, 출근 기록을 모두 삭제합니다.\n'
          '이 작업은 되돌릴 수 없습니다.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('삭제'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      ToastHelper.showInfo('모든 더미 데이터 삭제 중...');
      
      await TestDataHelper.clearDummyAttendance();
      await TestDataHelper.clearAllDummyData();
      
      _firestoreService.clearCache();
      _firestoreService.invalidateListCache();
      
      ToastHelper.showSuccess('모든 더미 데이터가 삭제되었습니다!');
      
      if (mounted) {
        setState(() {});
      }
    } catch (e) {
      debugPrint('❌ 더미 데이터 삭제 실패: $e');
      ToastHelper.showError('더미 데이터 삭제 실패: $e');
    }
  }
  
  /// ⭐ 더미 데이터용 사업장 선택 (반응형 + 테마)
  Future<String?> _selectBusinessForDummyData() async {
    final businessNames = <String, String>{};
    
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('businesses')
          .where(FieldPath.documentId, whereIn: _allBusinessIds)
          .get();

      for (var doc in snapshot.docs) {
        final data = doc.data();
        businessNames[doc.id] = data['name'] ?? 'Unknown';
      }
    } catch (e) {
      debugPrint('❌ 사업장명 조회 실패: $e');
    }

    return await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          '사업장 선택',
          style: ResponsiveHelper.titleStyle(context),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: _allBusinessIds.map((id) {
            return ListTile(
              leading: Icon(
                Icons.business,
                size: ResponsiveHelper.iconSize(context, 24),
                color: Theme.of(context).primaryColor,
              ),
              title: Text(
                businessNames[id] ?? id,
                style: ResponsiveHelper.bodyStyle(context),
              ),
              onTap: () => Navigator.pop(context, id),
            );
          }).toList(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('취소'),
          ),
        ],
      ),
    );
  }
  /// ✅ 전체 TO 통계 재계산 (디버그용)
  Future<void> _recalculateAllStats() async {
    final confirmed = await DialogHelper.showConfirm(
      context,
      title: '통계 재계산',
      message: '모든 TO의 통계를 재계산합니다.\n시간이 걸릴 수 있습니다.\n\n계속하시겠습니까?',
      confirmText: '재계산',
    );
    
    if (!confirmed) return;
    
    // 로딩 표시
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => PopScope(
        canPop: false,
        child: Center(
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 16),
                Text(
                  '통계 재계산 중...',
                  style: ResponsiveHelper.bodyStyle(context),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    
    try {
      // 1. 모든 TO 통계 재계산
      final snapshot = await FirebaseFirestore.instance.collection('tos').get();
      int count = 0;
      
      for (var doc in snapshot.docs) {
        await _firestoreService.recalculateTOStats(doc.id);
        count++;
        debugPrint('📊 [$count/${snapshot.docs.length}] ${doc.id} 재계산 완료');
      }
      
      // 2. 그룹 마스터 통계 동기화
      final groupCount = await _firestoreService.migrateAllGroupMasterStats();
      
      // 3. 캐시 클리어
      _firestoreService.clearCache();
      
      if (mounted) Navigator.pop(context);
      
      ToastHelper.showSuccess('$count개 TO, $groupCount개 그룹 통계 재계산 완료');
      
      // 화면 새로고침
      setState(() {});
      
    } catch (e) {
      if (mounted) Navigator.pop(context);
      debugPrint('❌ 통계 재계산 실패: $e');
      ToastHelper.showError('통계 재계산 실패: $e');
    }
  }
  
}