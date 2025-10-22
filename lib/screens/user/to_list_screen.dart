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

/// TO 목록 화면 (3단계 필터: 날짜/업무 유형/시간대)
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
  DateTime? _selectedDate; // 단일 날짜 선택용
  DateTime? _startDate; // 범위 시작 (3일/7일 버튼용)
  DateTime? _endDate; // 범위 종료 (3일/7일 버튼용)
  String _selectedWorkType = 'ALL'; // ALL, 피킹, 패킹, 배송, 분류, 하역, 검수
  String? _startTime; // 시작 시간 (예: "08:00")
  String? _endTime; // 종료 시간 (예: "17:00")
  
  List<TOModel> _allTOList = []; // Firestore에서 가져온 전체 TO
  List<TOModel> _filteredTOList = []; // 필터 적용 후 TO
  List<ApplicationModel> _myApplications = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadTOs();
  }

  /// TO 목록 + 내 지원 내역 병렬 로드 (날짜 필터 제거!)
  Future<void> _loadTOs() async {
    setState(() {
      _isLoading = true;
    });

    try {
      print('🔍 센터 ID: ${widget.centerId}');
      
      final userProvider = Provider.of<UserProvider>(context, listen: false);
      final uid = userProvider.currentUser?.uid;
      
      // ⚡ 병렬로 TO 목록과 내 지원 내역을 동시에 조회!
      // 날짜 필터는 메모리에서 처리하므로 date 파라미터 제거
      final results = await Future.wait([
        _firestoreService.getTOsByCenter(widget.centerId), // date 파라미터 제거!
        uid != null 
            ? _firestoreService.getMyApplications(uid)
            : Future.value(<ApplicationModel>[]),
      ]);

      final toList = results[0] as List<TOModel>;
      final myApps = results[1] as List<ApplicationModel>;

      print('✅ 조회된 TO 개수: ${toList.length}');
      print('✅ 내 지원 내역 개수: ${myApps.length}');

      setState(() {
        _allTOList = toList;
        _myApplications = myApps;
        _applyFilters(); // 필터 적용
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

  /// 필터 적용 (날짜 범위 + 업무 유형 + 시간대)
  void _applyFilters() {
    List<TOModel> filtered = _allTOList;

    // 0. 날짜 필터 (오늘 이전 TO는 무조건 제외!)
    final today = DateTime.now();
    final todayStart = DateTime(today.year, today.month, today.day);
    
    filtered = filtered.where((to) {
      final toDate = DateTime(to.date.year, to.date.month, to.date.day);
      return toDate.isAtSameMomentAs(todayStart) || toDate.isAfter(todayStart);
    }).toList();

    // 1. 날짜 범위 필터 (3일/7일 버튼)
    if (_startDate != null && _endDate != null) {
      filtered = filtered.where((to) {
        final toDate = DateTime(to.date.year, to.date.month, to.date.day);
        final start = DateTime(_startDate!.year, _startDate!.month, _startDate!.day);
        final end = DateTime(_endDate!.year, _endDate!.month, _endDate!.day);
        
        return (toDate.isAtSameMomentAs(start) || toDate.isAfter(start)) &&
               (toDate.isAtSameMomentAs(end) || toDate.isBefore(end));
      }).toList();
    }
    // 1-1. 단일 날짜 필터 (날짜 선택)
    else if (_selectedDate != null) {
      filtered = filtered.where((to) {
        final toDate = DateTime(to.date.year, to.date.month, to.date.day);
        final selected = DateTime(_selectedDate!.year, _selectedDate!.month, _selectedDate!.day);
        return toDate.isAtSameMomentAs(selected);
      }).toList();
    }

    // 2. 업무 유형 필터
    if (_selectedWorkType != 'ALL') {
      filtered = filtered.where((to) => to.workType == _selectedWorkType).toList();
    }

    // 3. 시간 필터
    if (_startTime != null || _endTime != null) {
      filtered = filtered.where((to) {
        final toStartTime = to.startTime; // "09:00"
        final toEndTime = to.endTime; // "18:00"
        
        // 케이스 1: 시작 시간만 설정 → TO 시작 시간이 설정 시간 이후
        if (_startTime != null && _endTime == null) {
          return toStartTime.compareTo(_startTime!) >= 0;
        }
        
        // 케이스 2: 종료 시간만 설정 → TO 종료 시간이 설정 시간 이전
        if (_startTime == null && _endTime != null) {
          return toEndTime.compareTo(_endTime!) <= 0;
        }
        
        // 케이스 3: 둘 다 설정 → TO가 범위 내에 있음
        if (_startTime != null && _endTime != null) {
          return toStartTime.compareTo(_startTime!) >= 0 && 
                 toEndTime.compareTo(_endTime!) <= 0;
        }
        
        return true;
      }).toList();
    }

    setState(() {
      _filteredTOList = filtered;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.centerName),
        backgroundColor: Colors.blue[700],
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      
      body: Column(
        children: [
          _buildFilters(),
          Expanded(
            child: _buildTOList(),
          ),
        ],
      ),
    );
  }

  /// 통합 필터 위젯 (2단계: 날짜 + 업무 유형 + 시간)
  Widget _buildFilters() {
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
          // 1단계: 날짜 필터
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                '📅 날짜',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Row(
                children: [
                  _buildDateQuickButton('오늘', 0),
                  const SizedBox(width: 6),
                  _buildDateQuickButton('3일', 3),
                  const SizedBox(width: 6),
                  _buildDateQuickButton('7일', 7),
                  const SizedBox(width: 6),
                  _buildDateQuickButton('전체', null),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),
          ElevatedButton.icon(
            onPressed: _selectDate,
            icon: const Icon(Icons.calendar_today, size: 16),
            label: Text(
              _getDateRangeText(),
              style: const TextStyle(fontSize: 13),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: Colors.blue[700],
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
              minimumSize: const Size(double.infinity, 40),
            ),
          ),
          
          const SizedBox(height: 16),

          // 2단계: 업무 유형 필터
          const Text(
            '💼 업무 유형',
            style: TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildFilterChip('전체', 'ALL', _selectedWorkType, (value) {
                setState(() {
                  _selectedWorkType = value;
                  _applyFilters();
                });
              }),
              _buildFilterChip('피킹', '피킹', _selectedWorkType, (value) {
                setState(() {
                  _selectedWorkType = value;
                  _applyFilters();
                });
              }),
              _buildFilterChip('패킹', '패킹', _selectedWorkType, (value) {
                setState(() {
                  _selectedWorkType = value;
                  _applyFilters();
                });
              }),
              _buildFilterChip('배송', '배송', _selectedWorkType, (value) {
                setState(() {
                  _selectedWorkType = value;
                  _applyFilters();
                });
              }),
              _buildFilterChip('분류', '분류', _selectedWorkType, (value) {
                setState(() {
                  _selectedWorkType = value;
                  _applyFilters();
                });
              }),
              _buildFilterChip('하역', '하역', _selectedWorkType, (value) {
                setState(() {
                  _selectedWorkType = value;
                  _applyFilters();
                });
              }),
              _buildFilterChip('검수', '검수', _selectedWorkType, (value) {
                setState(() {
                  _selectedWorkType = value;
                  _applyFilters();
                });
              }),
            ],
          ),
          
          const SizedBox(height: 16),

          // 3단계: 시간 필터 (30분 단위 선택)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                '⏰ 시간',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
              // 시간 초기화 버튼
              if (_startTime != null || _endTime != null)
                TextButton.icon(
                  onPressed: () {
                    setState(() {
                      _startTime = null;
                      _endTime = null;
                      _applyFilters();
                    });
                  },
                  icon: const Icon(Icons.refresh, size: 14, color: Colors.white),
                  label: const Text(
                    '초기화',
                    style: TextStyle(color: Colors.white, fontSize: 11),
                  ),
                  style: TextButton.styleFrom(
                    backgroundColor: Colors.white.withOpacity(0.2),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    minimumSize: const Size(0, 0),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              // 시작 시간
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '시작',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.9),
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: DropdownButton<String>(
                        value: _startTime,
                        hint: Text(
                          '선택 안함',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey[600],
                          ),
                        ),
                        isExpanded: true,
                        underline: const SizedBox(),
                        items: _generateTimeSlots(),
                        onChanged: (value) {
                          setState(() {
                            _startTime = value;
                            _applyFilters();
                          });
                        },
                      ),
                    ),
                  ],
                ),
              ),
              
              const SizedBox(width: 12),
              
              // 종료 시간
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '종료',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.9),
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: DropdownButton<String>(
                        value: _endTime,
                        hint: Text(
                          '선택 안함',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey[600],
                          ),
                        ),
                        isExpanded: true,
                        underline: const SizedBox(),
                        items: _generateTimeSlots(),
                        onChanged: (value) {
                          setState(() {
                            _endTime = value;
                            _applyFilters();
                          });
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 날짜 범위 텍스트 생성
  String _getDateRangeText() {
    if (_startDate != null && _endDate != null) {
      // 3일/7일 버튼으로 범위 설정된 경우
      return '${_startDate!.year}.${_startDate!.month}.${_startDate!.day} - ${_endDate!.year}.${_endDate!.month}.${_endDate!.day}';
    } else if (_selectedDate != null) {
      // 날짜 선택으로 단일 날짜 설정된 경우
      return '${_selectedDate!.year}.${_selectedDate!.month}.${_selectedDate!.day}';
    } else {
      // 전체 선택된 경우
      return '전체 기간';
    }
  }

  /// 날짜 빠른 선택 버튼
  Widget _buildDateQuickButton(String label, int? days) {
    return ElevatedButton(
      onPressed: () {
        setState(() {
          if (days == null) {
            // 전체
            _selectedDate = null;
            _startDate = null;
            _endDate = null;
          } else if (days == 0) {
            // 오늘
            _selectedDate = DateTime.now();
            _startDate = null;
            _endDate = null;
          } else {
            // 3일 또는 7일 (범위)
            _selectedDate = null;
            _startDate = DateTime.now();
            _endDate = DateTime.now().add(Duration(days: days));
          }
          _applyFilters(); // 필터 적용!
        });
        
        final message = days == null 
            ? '전체 TO를 표시합니다' 
            : days == 0
                ? '오늘 TO를 표시합니다'
                : '오늘부터 ${days}일간의 TO를 표시합니다';
        ToastHelper.showInfo(message);
      },
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.blue[600],
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        minimumSize: const Size(0, 0),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: Text(label, style: const TextStyle(fontSize: 11)),
    );
  }

  /// 30분 단위 시간 슬롯 생성
  List<DropdownMenuItem<String>> _generateTimeSlots() {
    List<DropdownMenuItem<String>> items = [];
    
    for (int hour = 0; hour < 24; hour++) {
      for (int minute = 0; minute < 60; minute += 30) {
        final timeStr = '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
        items.add(
          DropdownMenuItem(
            value: timeStr,
            child: Text(
              timeStr,
              style: const TextStyle(fontSize: 13),
            ),
          ),
        );
      }
    }
    
    return items;
  }

  /// 필터 칩 (업무 유형용)
  Widget _buildFilterChip(String label, String value, String currentValue, Function(String) onSelected) {
    final isSelected = currentValue == value;
    return FilterChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (selected) => onSelected(value),
      selectedColor: Colors.white,
      checkmarkColor: Colors.blue[700],
      backgroundColor: Colors.blue[600],
      labelStyle: TextStyle(
        color: isSelected ? Colors.blue[700] : Colors.white,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        fontSize: 12,
      ),
      side: BorderSide(
        color: isSelected ? Colors.white : Colors.transparent,
        width: isSelected ? 2 : 0,
      ),
    );
  }

  /// TO 목록 위젯
  Widget _buildTOList() {
    if (_isLoading) {
      return const LoadingWidget(message: 'TO 목록을 불러오는 중...');
    }

    if (_filteredTOList.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.inbox, size: 80, color: Colors.grey[300]),
            const SizedBox(height: 16),
            Text(
              '조건에 맞는 TO가 없습니다',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.grey[700],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '필터를 변경해보세요',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[500],
              ),
            ),
          ],
        ),
      );
    }

    print('📋 ListView 빌드 - TO 개수: ${_filteredTOList.length}, 지원 내역: ${_myApplications.length}');

    return RefreshIndicator(
      onRefresh: _refreshList,
      child: ListView.builder(
        key: ValueKey('${_filteredTOList.length}-${_myApplications.length}'),
        padding: const EdgeInsets.all(16),
        itemCount: _filteredTOList.length,
        itemBuilder: (context, index) {
          final to = _filteredTOList[index];
          
          String? applicationStatus;
          try {
            final myApp = _myApplications.firstWhere(
              (app) => app.toId == to.id && 
                       (app.status == 'PENDING' || app.status == 'CONFIRMED'),
            );
            applicationStatus = myApp.status;
            print('🎯 TO ${to.id} 지원 상태: $applicationStatus');
          } catch (e) {
            applicationStatus = null;
          }
          
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: TOCardWidget(
              key: ValueKey('${to.id}-$applicationStatus'),
              to: to,
              onTap: () => _onTOTap(to),
              applicationStatus: applicationStatus,
            ),
          );
        },
      ),
    );
  }

  /// 날짜 선택 다이얼로그 (오늘 이후만 선택 가능)
  Future<void> _selectDate() async {
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? DateTime.now(),
      firstDate: DateTime.now(), // 🔥 오늘부터만 선택 가능!
      lastDate: DateTime.now().add(const Duration(days: 90)),
    );

    if (pickedDate != null) {
      setState(() {
        _selectedDate = pickedDate;
        _startDate = null; // 범위 초기화
        _endDate = null;
        _applyFilters(); // 필터 적용!
      });
    }
  }

  /// 목록 새로고침
  Future<void> _refreshList() async {
    await _loadTOs();
    ToastHelper.showSuccess('목록을 새로고침했습니다');
  }

  /// TO 카드 탭 이벤트
  void _onTOTap(TOModel to) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => TODetailScreen(to: to),
      ),
    );

    if (result == true) {
      _loadTOs();
    }
  }
}