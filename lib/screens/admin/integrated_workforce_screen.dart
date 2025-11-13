import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../providers/user_provider.dart';
import '../../utils/toast_helper.dart';
import '../../services/firestore_service.dart';
import 'widgets/workforce_list_view.dart';
import 'widgets/workforce_calendar_view.dart';
import 'dialogs/resign_request_management_dialog.dart';
import '../../utils/test_data_helper.dart';
import '../../models/core/to_model.dart';


/// 통합 인력 관리 화면 (TO 관리 + 캘린더)
class IntegratedWorkforceScreen extends StatefulWidget {
  const IntegratedWorkforceScreen({super.key});

  @override
  State<IntegratedWorkforceScreen> createState() =>
      _IntegratedWorkforceScreenState();
}

class _IntegratedWorkforceScreenState extends State<IntegratedWorkforceScreen> {
  final FirestoreService _firestoreService = FirestoreService();
  List<String> _allBusinessIds = [];  // ⭐ 모든 사업장 ID
  String? _selectedBusinessId;
  bool _isCalendarView = false;

  @override
  void initState() {
    super.initState();
    _loadBusinessIds();  // ⭐ 변경
  }

  /// ⭐ 관리자의 모든 사업장 ID 로드
  Future<void> _loadBusinessIds() async {
    try {
      final userProvider = context.read<UserProvider>();
      final uid = userProvider.currentUser?.uid;

      if (uid == null) {
        ToastHelper.showWarning('로그인 정보를 찾을 수 없습니다.');
        return;
      }

      // 내가 관리하는 모든 사업장 조회
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
              Icon(Icons.business_center, size: 64, color: Colors.grey[400]),
              const SizedBox(height: 16),
              Text(
                '등록된 사업장이 없습니다',
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.grey[600],
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
          // ⭐ 더미 데이터 버튼
          IconButton(
            icon: const Icon(Icons.science),
            onPressed: _showDummyDataDialog,
            tooltip: '테스트 데이터',
          ),
          // 퇴사 요청 알림 아이콘
          FutureBuilder<int>(
            future: _getResignRequestCount(),
            builder: (context, snapshot) {
              final count = snapshot.data ?? 0;
              return Stack(
                children: [
                  IconButton(
                    icon: const Icon(Icons.exit_to_app),
                    onPressed: _showResignRequestManagement,
                    tooltip: '퇴사 요청',
                  ),
                  if (count > 0)
                    Positioned(
                      right: 8,
                      top: 8,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(
                          color: Colors.red,
                          shape: BoxShape.circle,
                        ),
                        constraints: const BoxConstraints(
                          minWidth: 16,
                          minHeight: 16,
                        ),
                        child: Text(
                          '$count',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
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
          
          // 리스트/캘린더 토글
          Container(
            margin: const EdgeInsets.only(right: 8),
            decoration: BoxDecoration(
              color: Theme.of(context).primaryColor.withOpacity(0.2),
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

  /// 토글 버튼
  Widget _buildToggleButton({
    required IconData icon,
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 18,
              color: isSelected ? Theme.of(context).primaryColor : Colors.white,
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: isSelected ? Theme.of(context).primaryColor : Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 퇴사 요청 개수 조회
  Future<int> _getResignRequestCount() async {
    if (_selectedBusinessId == null) return 0;
    
    try {
      final requests = await _firestoreService.getResignRequests(_selectedBusinessId!);
      return requests.length;
    } catch (e) {
      return 0;
    }
  }

  /// 퇴사 요청 관리 다이얼로그 표시
  void _showResignRequestManagement() {
    if (_selectedBusinessId == null) {
      ToastHelper.showWarning('사업장 정보를 찾을 수 없습니다.');
      return;
    }
    
    showDialog(
      context: context,
      builder: (context) => ResignRequestManagementDialog(
        businessId: _selectedBusinessId!,
        onChanged: () {
          setState(() {}); // 배지 업데이트
        },
      ),
    );
  }
  /// ⭐ 더미 데이터 다이얼로그
  Future<void> _showDummyDataDialog() async {
    if (_selectedBusinessId == null) {
      ToastHelper.showError('사업장이 선택되지 않았습니다.');
      return;
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.science, color: Colors.orange),
            SizedBox(width: 8),
            Text('테스트 데이터 관리'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '개발/테스트용 더미 데이터를 관리합니다.',
              style: TextStyle(fontSize: 14, color: Colors.grey),
            ),
            const SizedBox(height: 16),
            
            // TO 선택하여 지원자 생성
            ListTile(
              leading: const Icon(Icons.group_add, color: Colors.blue),
              title: const Text('TO에 지원자 추가'),
              subtitle: const Text('TO 선택 → 확정/대기 인원 생성'),
              onTap: () async {
                Navigator.pop(context);
                await _showCreateApplicantsDialog();
              },
            ),
            
            const Divider(),
            
            // 출근 데이터 생성
            ListTile(
              leading: const Icon(Icons.add_circle, color: Colors.green),
              title: const Text('오늘 출근 데이터 생성'),
              subtitle: const Text('확정 인원의 70% 출근 처리'),
              onTap: () async {
                Navigator.pop(context);
                await _createTodayAttendance();
              },
            ),
            
            const Divider(),
            
            // 출근 데이터 삭제
            ListTile(
              leading: const Icon(Icons.delete_sweep, color: Colors.orange),
              title: const Text('출근 데이터 삭제'),
              subtitle: const Text('모든 더미 출근 기록 삭제'),
              onTap: () async {
                Navigator.pop(context);
                await _clearAttendanceData();
              },
            ),
            
            const Divider(),
            
            // 지원자 데이터 삭제
            ListTile(
              leading: const Icon(Icons.delete_forever, color: Colors.red),
              title: const Text('모든 더미 데이터 삭제'),
              subtitle: const Text('지원자 + 지원서 + 출근 기록'),
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
 /// ⭐ TO 선택하여 지원자 생성 다이얼로그
  Future<void> _showCreateApplicantsDialog() async {
    // ⭐ 사업장이 여러 개면 선택하도록
    String? targetBusinessId = _selectedBusinessId;
    
    if (_allBusinessIds.length > 1) {
      targetBusinessId = await _selectBusinessForDummyData();
      if (targetBusinessId == null) return; // 취소
    }
    
    print('🔍 [DummyData] 선택된 사업장: $targetBusinessId');
    
    // 1. 활성 TO 목록 조회
    final activeTOs = await _firestoreService.getActiveTOs();
    
    print('   활성 TO: ${activeTOs.length}개');
    
    if (activeTOs.isEmpty) {
      ToastHelper.showWarning('활성화된 TO가 없습니다.');
      return;
    }

    // 내 사업장 TO만 필터링
    final myTOs = activeTOs.where((to) => to.businessId == targetBusinessId).toList();
    
    print('   내 사업장 TO: ${myTOs.length}개');
    
    if (myTOs.isEmpty) {
      ToastHelper.showWarning('내 사업장의 활성 TO가 없습니다.');
      return;
    }

    // 2. 그룹 TO 확장 (개별 TO들 포함)
    List<TOModel> allSelectableTOs = [];
    
    for (var masterTO in myTOs) {
      print('   📋 TO 체크: ${masterTO.title} (그룹: ${masterTO.isGrouped})');
      
      if (masterTO.isGrouped && masterTO.groupId != null) {
        // 그룹 TO → 그룹 내 모든 TO 가져오기
        final groupTOs = await _firestoreService.getTOsByGroup(masterTO.groupId!);
        print('      그룹 TO: ${groupTOs.length}개');
        allSelectableTOs.addAll(groupTOs);
      } else {
        // 단일 TO
        allSelectableTOs.add(masterTO);
      }
    }

    print('   🎯 선택 가능한 TO: ${allSelectableTOs.length}개');
    if (allSelectableTOs.isEmpty) {
      ToastHelper.showWarning('선택 가능한 TO가 없습니다.');
      return;
    }

    // 날짜순 정렬
    allSelectableTOs.sort((a, b) => a.date.compareTo(b.date));

    TOModel? selectedTO = allSelectableTOs.isNotEmpty ? allSelectableTOs.first : null;  // ⭐ 초기값 설정
    final confirmedController = TextEditingController(text: '5');
    final pendingController = TextEditingController(text: '3');

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('TO에 지원자 추가'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // TO 선택
                const Text(
                  'TO 선택',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<TOModel>(
                      isExpanded: true,
                      hint: const Text('TO를 선택하세요'),
                      value: selectedTO,
                      items: allSelectableTOs.map((to) {
                        final dateStr = DateFormat('MM/dd (E)', 'ko_KR').format(to.date);
                        final timeStr = to.isGrouped && to.groupId != null 
                            ? '(그룹)' 
                            : '';
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
                
                const SizedBox(height: 24),
                
                // 확정 인원
                const Text(
                  '확정 인원',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: confirmedController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    suffixText: '명',
                    hintText: '0',
                  ),
                ),
                
                const SizedBox(height: 16),
                
                // 대기 인원
                const Text(
                  '대기 인원',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: pendingController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    suffixText: '명',
                    hintText: '0',
                  ),
                ),
                
                const SizedBox(height: 16),
                
                // 안내
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.info_outline, size: 20, color: Colors.blue),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '업무 유형별로 랜덤 배분됩니다',
                          style: TextStyle(fontSize: 13, color: Colors.blue),
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

    // 지원자 생성
    try {
      final confirmedCount = int.tryParse(confirmedController.text) ?? 0;
      final pendingCount = int.tryParse(pendingController.text) ?? 0;

      if (confirmedCount == 0 && pendingCount == 0) {
        ToastHelper.showWarning('인원을 1명 이상 입력하세요.');
        return;
      }

      ToastHelper.showInfo('지원자 생성 중...');

      // WorkDetails 조회
      final workDetails = await _firestoreService.getWorkDetails(selectedTO!.id);
      final workTypes = workDetails.map((wd) => wd.workType).toList();

      await TestDataHelper.createDummyApplications(
        toId: selectedTO!.id,
        workTypes: workTypes,
        pendingCount: pendingCount,
        confirmedCount: confirmedCount,
      );

      ToastHelper.showSuccess('지원자가 생성되었습니다!');

      // ⭐ 캐시 클리어 및 화면 새로고침
      _firestoreService.clearCache(toId: selectedTO!.id);
      
      if (mounted) {
        setState(() {});
      }
    } catch (e) {
      print('❌ 지원자 생성 실패: $e');
      ToastHelper.showError('지원자 생성 실패: $e');
    }
  }

  /// ⭐ 오늘 출근 데이터 생성
  Future<void> _createTodayAttendance() async {
    try {
      ToastHelper.showInfo('출근 데이터 생성 중...');
      
      await TestDataHelper.createDummyAttendance(
        businessId: _selectedBusinessId!,
        date: DateTime.now(),
      );
      
      ToastHelper.showSuccess('출근 데이터가 생성되었습니다!');
      
      // ⭐ 캐시 클리어 및 화면 새로고침
      _firestoreService.clearCache();
      
      if (mounted) {
        setState(() {});
      }
    } catch (e) {
      print('❌ 출근 데이터 생성 실패: $e');
      ToastHelper.showError('출근 데이터 생성 실패: $e');
    }
  }

  /// ⭐ 출근 데이터 삭제
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
            style: TextButton.styleFrom(foregroundColor: Colors.red),
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
      
      // ⭐ 캐시 클리어 및 화면 새로고침
      _firestoreService.clearCache();
      
      if (mounted) {
        setState(() {});
      }
    } catch (e) {
      print('❌ 출근 데이터 삭제 실패: $e');
      ToastHelper.showError('출근 데이터 삭제 실패: $e');
    }
  }

  /// ⭐ 모든 더미 데이터 삭제
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
            style: TextButton.styleFrom(foregroundColor: Colors.red),
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
      
      // ⭐ 캐시 클리어 및 화면 새로고침
      _firestoreService.clearCache();
      
      if (mounted) {
        setState(() {});
      }
    } catch (e) {
      print('❌ 더미 데이터 삭제 실패: $e');
      ToastHelper.showError('더미 데이터 삭제 실패: $e');
    }
  }
  /// ⭐ 더미 데이터용 사업장 선택
  Future<String?> _selectBusinessForDummyData() async {
    // 사업장 이름 조회
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
        title: const Text('사업장 선택'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: _allBusinessIds.map((id) {
            return ListTile(
              leading: const Icon(Icons.business),
              title: Text(businessNames[id] ?? id),
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