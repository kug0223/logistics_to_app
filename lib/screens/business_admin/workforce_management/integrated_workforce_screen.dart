import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../providers/user_provider.dart';
import '../../../utils/toast_helper.dart';
import '../../../utils/responsive_helper.dart';  // ⭐ 추가
import '../../../services/firestore_service.dart';
import 'workforce_list_view.dart';
import 'workforce_calendar_view.dart';
import '../dialogs/resign_request_management_dialog.dart';
import '../dialogs/fixed_worker_management_dialog.dart';
import '../../../utils/test_data_helper.dart';
import '../../../models/core/to_model.dart';



/// 통합 인력 관리 화면 (TO 관리 + 캘린더) - 완전 반응형 + 테마 적용
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

      print('✅ 관리 사업장: ${_allBusinessIds.length}개');
    } catch (e) {
      print('❌ 사업장 조회 실패: $e');
      ToastHelper.showError('사업장 정보를 불러올 수 없습니다.');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_selectedBusinessId == null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('인력 관리'),
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.business_center, 
                size: ResponsiveHelper.iconSize(context, 64),  // ⭐ 반응형
                color: Theme.of(context).disabledColor,  // ⭐ 테마
              ),
              SizedBox(height: ResponsiveHelper.spacing(context, 16)),
              Text(
                '등록된 사업장이 없습니다',
                style: ResponsiveHelper.subtitleStyle(  // ⭐ 반응형
                  context,
                  color: Theme.of(context).textTheme.bodySmall?.color,  // ⭐ 테마
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(_isCalendarView ? '인력 관리 - 캘린더' : '인력 관리 - 목록'),
        actions: [
          // ⭐ 더미 데이터 버튼 (반응형)
          IconButton(
            icon: Icon(
              Icons.science,
              size: ResponsiveHelper.iconSize(context, 24),  // ⭐ 반응형
            ),
            onPressed: _showDummyDataDialog,
            tooltip: '테스트 데이터',
          ),
          
          // ⭐ 고정근무자 관리 아이콘
          FutureBuilder<Map<String, int>>(
            future: _getFixedWorkerManagementCounts(),
            builder: (context, snapshot) {
              final counts = snapshot.data ?? {'resign': 0, 'schedule': 0};
              final totalCount = counts['resign']! + counts['schedule']!;
              
              return Stack(
                children: [
                  IconButton(
                    icon: Icon(
                      Icons.manage_accounts,
                      size: ResponsiveHelper.iconSize(context, 24),  // ⭐ 반응형
                    ),
                    onPressed: _showFixedWorkerManagement,
                    tooltip: '고정근무자 관리',
                  ),
                  if (totalCount > 0)
                    Positioned(
                      right: ResponsiveHelper.spacing(context, 8),  // ⭐ 반응형
                      top: ResponsiveHelper.spacing(context, 8),
                      child: Container(
                        padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 4)),  // ⭐ 반응형
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.error,  // ⭐ 테마
                          shape: BoxShape.circle,
                        ),
                        constraints: BoxConstraints(
                          minWidth: ResponsiveHelper.iconSize(context, 16),  // ⭐ 반응형
                          minHeight: ResponsiveHelper.iconSize(context, 16),
                        ),
                        child: Text(
                          '$totalCount',
                          style: ResponsiveHelper.tinyStyle(context).copyWith(  // ⭐ 반응형
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
          
          // ⭐ 리스트/캘린더 토글 (반응형 + 테마)
          Container(
            margin: EdgeInsets.only(right: ResponsiveHelper.spacing(context, 8)),  // ⭐ 반응형
            decoration: BoxDecoration(
              color: Theme.of(context).primaryColor.withOpacity(0.2),  // ⭐ 테마
              borderRadius: BorderRadius.circular(8),
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
      body: _isCalendarView
          ? const WorkforceCalendarView()
          : const WorkforceListView(),
    );
  }

  /// ⭐ 토글 버튼 (반응형 + 테마)
  Widget _buildToggleButton({
    required IconData icon,
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: ResponsiveHelper.spacing(context, 12),  // ⭐ 반응형
          vertical: ResponsiveHelper.spacing(context, 8),
        ),
        decoration: BoxDecoration(
          color: isSelected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: ResponsiveHelper.iconSize(context, 18),  // ⭐ 반응형
              color: isSelected ? Theme.of(context).primaryColor : Colors.white,  // ⭐ 테마
            ),
            SizedBox(width: ResponsiveHelper.spacing(context, 4)),
            Text(
              label,
              style: ResponsiveHelper.smallStyle(context).copyWith(  // ⭐ 반응형
                fontWeight: FontWeight.bold,
                color: isSelected ? Theme.of(context).primaryColor : Colors.white,  // ⭐ 테마
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  /// 고정근무자 관리 관련 개수 조회
  Future<Map<String, int>> _getFixedWorkerManagementCounts() async {
    if (_selectedBusinessId == null) {
      return {'resign': 0, 'schedule': 0};
    }
    
    try {
      final resignCount = await _firestoreService.getResignRequests(_selectedBusinessId!);
      final scheduleCount = await _firestoreService.getPendingScheduleChangeRequestCount(_selectedBusinessId!);
      
      return {
        'resign': resignCount.length,
        'schedule': scheduleCount,
      };
    } catch (e) {
      print('❌ 개수 조회 실패: $e');
      return {'resign': 0, 'schedule': 0};
    }
  }

  /// 고정근무자 관리 다이얼로그 표시
  void _showFixedWorkerManagement() {
    if (_selectedBusinessId == null) {
      ToastHelper.showWarning('사업장 정보를 찾을 수 없습니다.');
      return;
    }
    
    showDialog(
      context: context,
      builder: (context) => FixedWorkerManagementDialog(
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
              size: ResponsiveHelper.iconSize(context, 24),  // ⭐ 반응형
            ),
            SizedBox(width: ResponsiveHelper.spacing(context, 8)),
            Text(
              '테스트 데이터 관리',
              style: ResponsiveHelper.titleStyle(context),  // ⭐ 반응형
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '개발/테스트용 더미 데이터를 관리합니다.',
              style: ResponsiveHelper.bodyStyle(  // ⭐ 반응형
                context,
                color: Theme.of(context).textTheme.bodySmall?.color,  // ⭐ 테마
              ),
            ),
            SizedBox(height: ResponsiveHelper.spacing(context, 16)),
            
            // ⭐ TO 선택하여 지원자 생성
            ListTile(
              leading: Icon(
                Icons.group_add, 
                color: Theme.of(context).primaryColor,  // ⭐ 테마
                size: ResponsiveHelper.iconSize(context, 24),  // ⭐ 반응형
              ),
              title: Text(
                'TO에 지원자 추가',
                style: ResponsiveHelper.bodyStyle(context).copyWith(  // ⭐ 반응형
                  fontWeight: FontWeight.bold,
                ),
              ),
              subtitle: Text(
                'TO 선택 → 확정/대기 인원 생성',
                style: ResponsiveHelper.smallStyle(context),  // ⭐ 반응형
              ),
              onTap: () async {
                Navigator.pop(context);
                await _showCreateApplicantsDialog();
              },
            ),
            
            const Divider(),
            
            // ⭐ 출근 데이터 생성
            ListTile(
              leading: Icon(
                Icons.add_circle, 
                color: Colors.green,
                size: ResponsiveHelper.iconSize(context, 24),  // ⭐ 반응형
              ),
              title: Text(
                '오늘 출근 데이터 생성',
                style: ResponsiveHelper.bodyStyle(context).copyWith(  // ⭐ 반응형
                  fontWeight: FontWeight.bold,
                ),
              ),
              subtitle: Text(
                '확정 인원의 70% 출근 처리',
                style: ResponsiveHelper.smallStyle(context),  // ⭐ 반응형
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
                size: ResponsiveHelper.iconSize(context, 24),  // ⭐ 반응형
              ),
              title: Text(
                '출근 데이터 삭제',
                style: ResponsiveHelper.bodyStyle(context).copyWith(  // ⭐ 반응형
                  fontWeight: FontWeight.bold,
                ),
              ),
              subtitle: Text(
                '모든 더미 출근 기록 삭제',
                style: ResponsiveHelper.smallStyle(context),  // ⭐ 반응형
              ),
              onTap: () async {
                Navigator.pop(context);
                await _clearAttendanceData();
              },
            ),
            
            const Divider(),
            
            // ⭐ 지원자 데이터 삭제
            ListTile(
              leading: Icon(
                Icons.delete_forever, 
                color: Theme.of(context).colorScheme.error,  // ⭐ 테마
                size: ResponsiveHelper.iconSize(context, 24),  // ⭐ 반응형
              ),
              title: Text(
                '모든 더미 데이터 삭제',
                style: ResponsiveHelper.bodyStyle(context).copyWith(  // ⭐ 반응형
                  fontWeight: FontWeight.bold,
                ),
              ),
              subtitle: Text(
                '지원자 + 지원서 + 출근 기록',
                style: ResponsiveHelper.smallStyle(context),  // ⭐ 반응형
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
    
    print('🔍 [DummyData] 선택된 사업장: $targetBusinessId');
    
    final activeTOs = await _firestoreService.getActiveTOs();
    
    print('   진행중 TO: ${activeTOs.length}개');
    
    if (activeTOs.isEmpty) {
      ToastHelper.showWarning('진행중인 TO가 없습니다.');
      return;
    }

    final myTOs = activeTOs.where((to) => to.businessId == targetBusinessId).toList();
    
    print('   내 사업장 진행중 TO: ${myTOs.length}개');
    
    if (myTOs.isEmpty) {
      ToastHelper.showWarning('내 사업장의 진행중인 TO가 없습니다.');
      return;
    }

    List<TOModel> allSelectableTOs = [];
    
    for (var masterTO in myTOs) {
      print('   📋 TO 체크: ${masterTO.title} (그룹: ${masterTO.isGrouped})');
      
      if (masterTO.isGrouped && masterTO.groupId != null) {
        final groupTOs = await _firestoreService.getTOsByGroup(masterTO.groupId!);
        print('      그룹 TO: ${groupTOs.length}개');
        allSelectableTOs.addAll(groupTOs);
      } else {
        allSelectableTOs.add(masterTO);
      }
    }

    print('   🎯 선택 가능한 TO: ${allSelectableTOs.length}개');
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
            style: ResponsiveHelper.titleStyle(context),  // ⭐ 반응형
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
                  style: ResponsiveHelper.bodyStyle(context).copyWith(  // ⭐ 반응형
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: ResponsiveHelper.spacing(context, 8)),
                Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: ResponsiveHelper.spacing(context, 12),  // ⭐ 반응형
                  ),
                  decoration: BoxDecoration(
                    border: Border.all(color: Theme.of(context).dividerColor),  // ⭐ 테마
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<TOModel>(
                      isExpanded: true,
                      value: selectedTO,
                      style: ResponsiveHelper.bodyStyle(context),  // ⭐ 반응형
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
                  style: ResponsiveHelper.bodyStyle(context).copyWith(  // ⭐ 반응형
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: ResponsiveHelper.spacing(context, 8)),
                TextField(
                  controller: confirmedController,
                  keyboardType: TextInputType.number,
                  style: ResponsiveHelper.bodyStyle(context),  // ⭐ 반응형
                  decoration: InputDecoration(
                    border: OutlineInputBorder(),
                    suffixText: '명',
                    hintText: '0',
                    hintStyle: ResponsiveHelper.bodyStyle(  // ⭐ 반응형
                      context,
                      color: Theme.of(context).hintColor,  // ⭐ 테마
                    ),
                  ),
                ),
                
                SizedBox(height: ResponsiveHelper.spacing(context, 16)),
                
                // 대기 인원
                Text(
                  '대기 인원',
                  style: ResponsiveHelper.bodyStyle(context).copyWith(  // ⭐ 반응형
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: ResponsiveHelper.spacing(context, 8)),
                TextField(
                  controller: pendingController,
                  keyboardType: TextInputType.number,
                  style: ResponsiveHelper.bodyStyle(context),  // ⭐ 반응형
                  decoration: InputDecoration(
                    border: OutlineInputBorder(),
                    suffixText: '명',
                    hintText: '0',
                    hintStyle: ResponsiveHelper.bodyStyle(  // ⭐ 반응형
                      context,
                      color: Theme.of(context).hintColor,  // ⭐ 테마
                    ),
                  ),
                ),
                
                SizedBox(height: ResponsiveHelper.spacing(context, 16)),
                
                // 안내
                Container(
                  padding: ResponsiveHelper.cardPadding(context),  // ⭐ 반응형
                  decoration: BoxDecoration(
                    color: Theme.of(context).primaryColor.withOpacity(0.1),  // ⭐ 테마
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.info_outline, 
                        size: ResponsiveHelper.iconSize(context, 20),  // ⭐ 반응형
                        color: Theme.of(context).primaryColor,  // ⭐ 테마
                      ),
                      SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                      Expanded(
                        child: Text(
                          '업무 유형별로 랜덤 배분됩니다',
                          style: ResponsiveHelper.smallStyle(  // ⭐ 반응형
                            context,
                            color: Theme.of(context).primaryColor,  // ⭐ 테마
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
      
      if (mounted) {
        setState(() {});
      }
    } catch (e) {
      print('❌ 지원자 생성 실패: $e');
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
      
      if (mounted) {
        setState(() {});
      }
    } catch (e) {
      print('❌ 출근 데이터 생성 실패: $e');
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
              foregroundColor: Theme.of(context).colorScheme.error,  // ⭐ 테마
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
      print('❌ 출근 데이터 삭제 실패: $e');
      ToastHelper.showError('출근 데이터 삭제 실패: $e');
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
              foregroundColor: Theme.of(context).colorScheme.error,  // ⭐ 테마
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
      
      ToastHelper.showSuccess('모든 더미 데이터가 삭제되었습니다!');
      
      _firestoreService.clearCache();
      
      if (mounted) {
        setState(() {});
      }
    } catch (e) {
      print('❌ 더미 데이터 삭제 실패: $e');
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
      print('❌ 사업장명 조회 실패: $e');
    }

    return await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          '사업장 선택',
          style: ResponsiveHelper.titleStyle(context),  // ⭐ 반응형
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: _allBusinessIds.map((id) {
            return ListTile(
              leading: Icon(
                Icons.business,
                size: ResponsiveHelper.iconSize(context, 24),  // ⭐ 반응형
                color: Theme.of(context).primaryColor,  // ⭐ 테마
              ),
              title: Text(
                businessNames[id] ?? id,
                style: ResponsiveHelper.bodyStyle(context),  // ⭐ 반응형
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
}