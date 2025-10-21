import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/to_model.dart';
import '../../models/application_model.dart';
import '../../services/firestore_service.dart';
import '../../providers/user_provider.dart';
import '../../widgets/to_card_widget.dart';
import '../../widgets/loading_widget.dart';
import '../../utils/toast_helper.dart';
import 'to_detail_screen.dart';

/// TO 목록 화면
class TOListScreen extends StatefulWidget {
  final String centerId;
  final String centerName;

  const TOListScreen({
    Key? key,
    required this.centerId,
    required this.centerName,
  }) : super(key: key);

  @override
  State<TOListScreen> createState() => _TOListScreenState();
}

class _TOListScreenState extends State<TOListScreen> {
  final FirestoreService _firestoreService = FirestoreService();
  DateTime? _selectedDate;
  List<TOModel> _toList = [];
  List<ApplicationModel> _myApplications = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadTOs();
  }

  Future<void> _loadTOs() async {
    setState(() {
      _isLoading = true;
    });

    try {
      print('🔍 센터 ID: ${widget.centerId}');
      print('🔍 선택된 날짜: $_selectedDate');
      
      final toList = await _firestoreService.getTOsByCenter(
        widget.centerId,
        date: _selectedDate,
      );

      print('✅ 조회된 TO 개수: ${toList.length}');
      
      if (toList.isEmpty) {
        print('⚠️ TO 목록이 비어있습니다!');
      } else {
        print('✅ 첫 번째 TO: ${toList[0].centerName}');
      }

      // 내 지원 내역도 함께 조회
      final userProvider = Provider.of<UserProvider>(context, listen: false);
      final uid = userProvider.currentUser?.uid;
      
      List<ApplicationModel> myApps = [];
      if (uid != null) {
        myApps = await _firestoreService.getMyApplications(uid);
        print('✅ 내 지원 내역 개수: ${myApps.length}');
        for (var app in myApps) {
          print('  - TO ID: ${app.toId}, 상태: ${app.status}');
        }
      } else {
        print('⚠️ UID가 없습니다!');
      }

      setState(() {
        _toList = toList;
        _myApplications = myApps;
        _isLoading = false;
      });
    } catch (e) {
      print('❌ 에러 발생: $e');
      setState(() {
        _isLoading = false;
      });
      ToastHelper.showError('TO 목록을 불러올 수 없습니다');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // AppBar
      appBar: AppBar(
        title: Text(widget.centerName),
        backgroundColor: Colors.blue[700],
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      
      // 본문
      body: Column(
        children: [
          // 날짜 필터 헤더
          _buildDateFilter(),
          
          // TO 목록
          Expanded(
            child: _buildTOList(),
          ),
        ],
      ),
    );
  }

  /// 날짜 필터 위젯
  Widget _buildDateFilter() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.blue[700],
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '📅 날짜 필터',
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              // 날짜 선택
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _selectDate,
                  icon: const Icon(Icons.calendar_today, size: 18),
                  label: Text(
                    _selectedDate == null
                        ? '날짜 선택'
                        : '${_selectedDate!.year}.${_selectedDate!.month}.${_selectedDate!.day}',
                    style: const TextStyle(fontSize: 14),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.blue[700],
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              
              const SizedBox(width: 8),
              
              // 오늘 버튼
              ElevatedButton(
                onPressed: _setToday,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue[600],
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                ),
                child: const Text('오늘', style: TextStyle(fontSize: 14)),
              ),
              
              const SizedBox(width: 8),
              
              // 전체 버튼
              ElevatedButton(
                onPressed: _showAll,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.grey[600],
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                ),
                child: const Text('전체', style: TextStyle(fontSize: 14)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// TO 목록 위젯
  Widget _buildTOList() {
    // 로딩 중
    if (_isLoading) {
      return const LoadingWidget(message: 'TO 목록을 불러오는 중...');
    }

    // 데이터 없음
    if (_toList.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.inbox, size: 80, color: Colors.grey[300]),
            const SizedBox(height: 16),
            Text(
              '등록된 TO가 없습니다',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.grey[700],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _selectedDate == null
                  ? '앞으로 등록될 TO를 기다려주세요'
                  : '선택한 날짜에 등록된 TO가 없습니다',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[500],
              ),
            ),
          ],
        ),
      );
    }

    print('📋 ListView 빌드 - TO 개수: ${_toList.length}, 지원 내역: ${_myApplications.length}');

    // TO 목록 표시
    return RefreshIndicator(
      onRefresh: _refreshList,
      child: ListView.builder(
        key: ValueKey('${_toList.length}-${_myApplications.length}'), // Key 추가!
        padding: const EdgeInsets.all(16),
        itemCount: _toList.length,
        itemBuilder: (context, index) {
          final to = _toList[index];
          
          // 이 TO에 대한 내 지원 상태 찾기
          String? applicationStatus;
          try {
            final myApp = _myApplications.firstWhere(
              (app) => app.toId == to.id && 
                       (app.status == 'PENDING' || app.status == 'CONFIRMED'),
            );
            applicationStatus = myApp.status;
            print('🎯 TO ${to.id} 지원 상태: $applicationStatus');
          } catch (e) {
            // 지원 내역 없음
            applicationStatus = null;
          }
          
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: TOCardWidget(
              key: ValueKey('${to.id}-$applicationStatus'), // Key 추가!
              to: to,
              onTap: () => _onTOTap(to),
              applicationStatus: applicationStatus,
            ),
          );
        },
      ),
    );
  }

  /// 날짜 선택 다이얼로그
  Future<void> _selectDate() async {
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? DateTime.now(),
      firstDate: DateTime.now().subtract(const Duration(days: 30)),
      lastDate: DateTime.now().add(const Duration(days: 90)),
    );

    if (pickedDate != null) {
      setState(() {
        _selectedDate = pickedDate;
      });
      _loadTOs();
    }
  }

  /// 오늘 날짜로 설정
  void _setToday() {
    setState(() {
      _selectedDate = DateTime.now();
    });
    _loadTOs();
    ToastHelper.showInfo('오늘 날짜로 필터링합니다');
  }

  /// 전체 보기
  void _showAll() {
    setState(() {
      _selectedDate = null;
    });
    _loadTOs();
    ToastHelper.showInfo('전체 TO를 표시합니다');
  }

  /// 목록 새로고침
  Future<void> _refreshList() async {
    await _loadTOs();
    ToastHelper.showSuccess('목록을 새로고침했습니다');
  }

  /// TO 카드 탭 이벤트 - 상세 화면으로 이동
  void _onTOTap(TOModel to) async {
    // 상세 화면에서 돌아올 때 결과를 받음
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => TODetailScreen(to: to),
      ),
    );

    // 지원했다면 목록 새로고침
    if (result == true) {
      _loadTOs();
    }
  }
}