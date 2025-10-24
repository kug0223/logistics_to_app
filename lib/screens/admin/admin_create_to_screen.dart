import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../models/business_model.dart';
import '../../models/to_model.dart';
import '../../services/firestore_service.dart';
import '../../providers/user_provider.dart';
import '../../utils/toast_helper.dart';
import '../../models/business_work_type_model.dart';

/// ✅ 업무 상세 입력 데이터 클래스 (시간 정보 포함)
class WorkDetailInput {
  final String? workType;
  final int? wage;
  final int? requiredCount;
  final String? startTime; // ✅ NEW
  final String? endTime; // ✅ NEW

  WorkDetailInput({
    this.workType,
    this.wage,
    this.requiredCount,
    this.startTime, // ✅ NEW
    this.endTime, // ✅ NEW
  });

  bool get isValid =>
      workType != null &&
      wage != null &&
      requiredCount != null &&
      startTime != null && // ✅ NEW
      endTime != null; // ✅ NEW

  Map<String, dynamic> toMap() {
    return {
      'workType': workType!,
      'wage': wage!,
      'requiredCount': requiredCount!,
      'startTime': startTime!, // ✅ NEW
      'endTime': endTime!, // ✅ NEW
    };
  }
}

/// TO 생성 화면 - 업무별 근무시간 포함
class AdminCreateTOScreen extends StatefulWidget {
  const AdminCreateTOScreen({super.key});

  @override
  State<AdminCreateTOScreen> createState() => _AdminCreateTOScreenState();
}

class _AdminCreateTOScreenState extends State<AdminCreateTOScreen> {
  final _formKey = GlobalKey<FormState>();
  final _firestoreService = FirestoreService();

  // 컨트롤러
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();

  // 상태 변수
  bool _isLoading = true;
  bool _isCreating = false;
  List<BusinessModel> _myBusinesses = [];
  BusinessModel? _selectedBusiness;
  List<BusinessWorkTypeModel> _businessWorkTypes = [];

  // 기본 입력 값
  DateTime? _selectedDate;
  // ❌ 제거: String? _selectedStartTime;
  // ❌ 제거: String? _selectedEndTime;
  DateTime? _selectedDeadlineDate;
  TimeOfDay? _selectedDeadlineTime;

  // ✅ 업무 상세 리스트 (최대 3개, 시간 정보 포함)
  List<WorkDetailInput> _workDetails = [];
  
  // ✅ NEW Phase 2: 그룹 연결 관련 변수 추가 (여기에 추가!)
  bool _linkToExisting = false; // 기존 공고와 연결 여부
  String? _selectedGroupId; // 선택한 그룹 ID
  List<TOModel> _myRecentTOs = []; // 최근 TO 목록
  bool _isLoadingRecentTOs = false; // 최근 TO 로딩 상태

  @override
  void initState() {
    super.initState();
    _loadMyBusinesses();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  /// 내 사업장 불러오기
  Future<void> _loadMyBusinesses() async {
    try {
      final userProvider = Provider.of<UserProvider>(context, listen: false);
      final uid = userProvider.currentUser?.uid;

      if (uid == null) {
        ToastHelper.showError('로그인 정보를 찾을 수 없습니다');
        return;
      }

      final businesses = await _firestoreService.getMyBusiness(uid);

      setState(() {
        _myBusinesses = businesses;
        if (_myBusinesses.length == 1) {
          _selectedBusiness = _myBusinesses.first;
          _loadBusinessWorkTypes(_myBusinesses.first.id);
        }
        _isLoading = false;
      });
    } catch (e) {
      print('❌ 사업장 불러오기 실패: $e');
      setState(() => _isLoading = false);
      ToastHelper.showError('사업장 정보를 불러올 수 없습니다');
    }
  }

  /// 사업장별 업무 유형 로드
  Future<void> _loadBusinessWorkTypes(String businessId) async {
    try {
      final workTypes = await _firestoreService.getBusinessWorkTypes(businessId);
      
      setState(() {
        _businessWorkTypes = workTypes;
      });

      if (workTypes.isEmpty) {
        ToastHelper.showWarning('등록된 업무 유형이 없습니다.\n설정에서 업무 유형을 먼저 등록하세요.');
      }
    } catch (e) {
      print('❌ 업무 유형 로드 실패: $e');
      ToastHelper.showError('업무 유형을 불러올 수 없습니다');
    }
  }
  // ✅ NEW Phase 2: 최근 TO 로드 메서드 추가 (여기에 추가!)
  /// 최근 TO 목록 로드 (그룹 연결용)
  Future<void> _loadRecentTOs() async {
    setState(() => _isLoadingRecentTOs = true);

    try {
      final userProvider = Provider.of<UserProvider>(context, listen: false);
      final uid = userProvider.currentUser?.uid;

      if (uid == null) return;

      final recentTOs = await _firestoreService.getRecentTOsByUser(uid, days: 30);
      
      setState(() {
        _myRecentTOs = recentTOs;
        _isLoadingRecentTOs = false;
      });

      print('✅ 최근 TO 로드 완료: ${recentTOs.length}개');
    } catch (e) {
      print('❌ 최근 TO 로드 실패: $e');
      setState(() => _isLoadingRecentTOs = false);
    }
  }

  /// TO 생성
  Future<void> _createTO() async {
    if (!_formKey.currentState!.validate()) return;

    // 업무 상세 검증
    if (_workDetails.isEmpty) {
      ToastHelper.showWarning('최소 1개의 업무를 추가해주세요.');
      return;
    }

    for (var detail in _workDetails) {
      if (!detail.isValid) {
        ToastHelper.showWarning('모든 업무의 정보를 입력해주세요.');
        return;
      }
    }

    if (_selectedDate == null) {
      ToastHelper.showWarning('근무 날짜를 선택해주세요.');
      return;
    }

    if (_selectedDeadlineDate == null || _selectedDeadlineTime == null) {
      ToastHelper.showWarning('지원 마감 시간을 선택해주세요.');
      return;
    }

    setState(() => _isCreating = true);

    try {
      final userProvider = Provider.of<UserProvider>(context, listen: false);
      final uid = userProvider.currentUser?.uid;

      if (uid == null || _selectedBusiness == null) {
        ToastHelper.showError('사용자 정보를 찾을 수 없습니다.');
        return;
      }

      // 마감 일시 생성
      final deadlineDateTime = DateTime(
        _selectedDeadlineDate!.year,
        _selectedDeadlineDate!.month,
        _selectedDeadlineDate!.day,
        _selectedDeadlineTime!.hour,
        _selectedDeadlineTime!.minute,
      );

      // WorkDetails 데이터 변환
      final workDetailsData = _workDetails.map((detail) => {
        'workType': detail.workType!,
        'wage': detail.wage!,
        'requiredCount': detail.requiredCount!,
        'startTime': detail.startTime!,
        'endTime': detail.endTime!,
      }).toList();

      // ✅ 그룹 정보 처리 (수정됨!)
      String? groupId;
      String? groupName;

      if (_linkToExisting && _selectedGroupId != null) {
        // ✅ selectedTO 변수 정의
        TOModel? selectedTO;
        try {
          selectedTO = _myRecentTOs.firstWhere(
            (to) => to.id == _selectedGroupId,  // ✅ id로만 비교
          );
        } catch (e) {
          selectedTO = _myRecentTOs.isNotEmpty ? _myRecentTOs.first : null;
        }

        if (selectedTO != null) {
          // 기존 그룹에 연결
          if (selectedTO.groupId != null) {
            // 이미 그룹이 있음
            groupId = selectedTO.groupId;
            groupName = selectedTO.groupName ?? selectedTO.title;
          } else {
            // ✅ NEW: 첫 TO를 선택했고 groupId가 없으면 새로 생성
            groupId = _firestoreService.generateGroupId();
            groupName = selectedTO.title;
            
            // 첫 번째 TO도 이 그룹에 추가
            await _firestoreService.updateTOGroup(
              toId: selectedTO.id,
              groupId: groupId!,
              groupName: groupName!,
            );
            
            print('✅ 첫 번째 TO에 그룹 정보 추가됨');
          }
        }
      } else if (_linkToExisting) {
        // 체크는 했지만 TO를 선택 안 함
        groupId = _firestoreService.generateGroupId();
        groupName = _titleController.text.trim();
      }

      // TO 생성
      final toId = await _firestoreService.createTOWithDetails(
        businessId: _selectedBusiness!.id,
        businessName: _selectedBusiness!.name,
        title: _titleController.text.trim(),
        date: _selectedDate!,
        applicationDeadline: deadlineDateTime,
        workDetailsData: workDetailsData,
        description: _descriptionController.text.trim().isNotEmpty
            ? _descriptionController.text.trim()
            : null,
        creatorUID: uid,
        groupId: groupId,
        groupName: groupName,
      );

      if (toId != null && mounted) {
        Navigator.pop(context, true);
      }
    } catch (e) {
      print('❌ TO 생성 실패: $e');
      ToastHelper.showError('TO 생성 중 오류가 발생했습니다.');
    } finally {
      if (mounted) {
        setState(() => _isCreating = false);
      }
    }
  }

  /// ✅ 업무 추가 다이얼로그 (시간 입력 포함)
  Future<void> _showAddWorkDetailDialog() async {
    if (_workDetails.length >= 3) {
      ToastHelper.showWarning('최대 3개까지만 추가할 수 있습니다.');
      return;
    }

    if (_businessWorkTypes.isEmpty) {
      ToastHelper.showWarning('등록된 업무 유형이 없습니다.');
      return;
    }

    String? selectedWorkType;
    final wageController = TextEditingController();
    final countController = TextEditingController();
    String? startTime = '09:00'; // ✅ NEW: 기본값
    String? endTime = '18:00'; // ✅ NEW: 기본값

    final result = await showDialog<WorkDetailInput>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('업무 추가'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 업무 유형 선택
              const Text('업무 유형 *', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: selectedWorkType,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: '업무 선택',
                ),
                items: _businessWorkTypes.map((workType) {
                  return DropdownMenuItem(
                    value: workType.name,
                    child: Row(
                      children: [
                        Text(workType.icon, style: const TextStyle(fontSize: 20)),
                        const SizedBox(width: 8),
                        Text(workType.name),
                      ],
                    ),
                  );
                }).toList(),
                onChanged: (value) {
                  selectedWorkType = value;
                },
              ),
              const SizedBox(height: 16),

              // ✅ NEW: 근무 시간 입력
              const Text('근무 시간 *', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: startTime,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        labelText: '시작',
                      ),
                      items: _generateTimeList().map((time) {
                        return DropdownMenuItem(value: time, child: Text(time));
                      }).toList(),
                      onChanged: (value) {
                        startTime = value;
                      },
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8),
                    child: Text('~', style: TextStyle(fontSize: 18)),
                  ),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: endTime,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        labelText: '종료',
                      ),
                      items: _generateTimeList().map((time) {
                        return DropdownMenuItem(value: time, child: Text(time));
                      }).toList(),
                      onChanged: (value) {
                        endTime = value;
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // 금액 입력
              const Text('금액 (원) *', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              TextField(
                controller: wageController,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: '50000',
                  suffixText: '원',
                ),
              ),
              const SizedBox(height: 16),

              // 필요 인원 입력
              const Text('필요 인원 (명) *', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              TextField(
                controller: countController,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: '5',
                  suffixText: '명',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('취소'),
          ),
          ElevatedButton(
            onPressed: () {
              // 유효성 검사
              if (selectedWorkType == null) {
                ToastHelper.showWarning('업무 유형을 선택하세요.');
                return;
              }
              if (startTime == null || endTime == null) {
                ToastHelper.showWarning('근무 시간을 선택하세요.');
                return;
              }
              if (wageController.text.isEmpty) {
                ToastHelper.showWarning('금액을 입력하세요.');
                return;
              }
              if (countController.text.isEmpty) {
                ToastHelper.showWarning('필요 인원을 입력하세요.');
                return;
              }

              final detail = WorkDetailInput(
                workType: selectedWorkType,
                wage: int.tryParse(wageController.text),
                requiredCount: int.tryParse(countController.text),
                startTime: startTime, // ✅ NEW
                endTime: endTime, // ✅ NEW
              );

              Navigator.pop(context, detail);
            },
            child: const Text('추가'),
          ),
        ],
      ),
    );

    if (result != null) {
      setState(() {
        _workDetails.add(result);
      });
    }
  }

  /// ✅ NEW: 시간 목록 생성 (00:00 ~ 23:30, 30분 단위)
  List<String> _generateTimeList() {
    final times = <String>[];
    for (int hour = 0; hour < 24; hour++) {
      for (int minute = 0; minute < 60; minute += 30) {
        final h = hour.toString().padLeft(2, '0');
        final m = minute.toString().padLeft(2, '0');
        times.add('$h:$m');
      }
    }
    return times;
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_myBusinesses.isEmpty) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('TO 생성'),
          backgroundColor: Colors.blue[700],
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.business, size: 80, color: Colors.grey[400]),
              const SizedBox(height: 16),
              Text(
                '등록된 사업장이 없습니다',
                style: TextStyle(fontSize: 18, color: Colors.grey[600]),
              ),
              const SizedBox(height: 8),
              Text(
                '사업장을 먼저 등록해주세요',
                style: TextStyle(fontSize: 14, color: Colors.grey[500]),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('TO 생성'),
        backgroundColor: Colors.blue[700],
        foregroundColor: Colors.white,
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // 제목 입력
            _buildSectionTitle('📝 TO 제목'),
            TextFormField(
              controller: _titleController,
              decoration: const InputDecoration(
                hintText: '예: 파트타임알바구인합니다',
                border: OutlineInputBorder(),
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'TO 제목을 입력하세요';
                }
                return null;
              },
            ),
            const SizedBox(height: 24),

            // 사업장 선택
            _buildSectionTitle('🏢 사업장'),
            _buildBusinessDropdown(),
            if (_selectedBusiness != null) ...[
              const SizedBox(height: 8),
              _buildBusinessInfoCard(_selectedBusiness!),
            ],
            const SizedBox(height: 24),
            
            // ✅ NEW Phase 2: 그룹 연결 섹션 추가 (여기에 추가!)
            _buildSectionTitle('🔗 기존 공고와 연결 (선택사항)'),
            _buildGroupLinkSection(),
            const SizedBox(height: 24),

            // 근무 날짜
            _buildSectionTitle('📅 근무 날짜'),
            _buildDatePicker(),
            const SizedBox(height: 24),

            // ❌ 제거: TO 레벨 근무 시간 입력
            // _buildSectionTitle('⏰ 근무 시간'),
            // Row(
            //   children: [
            //     Expanded(child: _buildStartTimePicker()),
            //     const SizedBox(width: 16),
            //     Expanded(child: _buildEndTimePicker()),
            //   ],
            // ),
            // const SizedBox(height: 24),

            // 지원 마감 시간
            _buildSectionTitle('⏱️ 지원 마감 시간'),
            _buildDeadlinePicker(),
            const SizedBox(height: 24),

            // ✅ 업무 상세 (최대 3개, 시간 정보 포함)
            _buildSectionTitle('💼 업무 상세 (최대 3개)'),
            const SizedBox(height: 8),
            if (_workDetails.isEmpty)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey[300]!),
                ),
                child: Column(
                  children: [
                    Icon(Icons.work_outline, size: 48, color: Colors.grey[400]),
                    const SizedBox(height: 8),
                    Text(
                      '업무를 추가해주세요',
                      style: TextStyle(color: Colors.grey[600]),
                    ),
                  ],
                ),
              )
            else
              ..._workDetails.asMap().entries.map((entry) {
                final index = entry.key;
                final detail = entry.value;
                return _buildWorkDetailCard(detail, index);
              }),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _workDetails.length < 3 ? _showAddWorkDetailDialog : null,
              icon: const Icon(Icons.add),
              label: Text('업무 추가 (${_workDetails.length}/3)'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
            const SizedBox(height: 24),

            // 설명
            _buildSectionTitle('📄 설명 (선택사항)'),
            TextField(
              controller: _descriptionController,
              maxLines: 4,
              decoration: const InputDecoration(
                hintText: '업무에 대한 상세 설명을 입력하세요',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 32),

            // 생성 버튼
            ElevatedButton(
              onPressed: _isCreating ? null : _createTO,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue[700],
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: _isCreating
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : const Text(
                      'TO 생성',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildBusinessDropdown() {
    if (_myBusinesses.length == 1) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.blue[50],
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.blue[200]!),
        ),
        child: Row(
          children: [
            Icon(Icons.business, color: Colors.blue[700]),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                _myBusinesses.first.name,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return DropdownButtonFormField<BusinessModel>(
      value: _selectedBusiness,
      decoration: const InputDecoration(
        border: OutlineInputBorder(),
        hintText: '사업장 선택',
      ),
      items: _myBusinesses.map((business) {
        return DropdownMenuItem(
          value: business,
          child: Text(business.name),
        );
      }).toList(),
      onChanged: (value) {
        setState(() {
          _selectedBusiness = value;
          if (value != null) {
            _loadBusinessWorkTypes(value.id);
          }
        });
      },
      validator: (value) {
        if (value == null) return '사업장을 선택하세요';
        return null;
      },
    );
  }

  Widget _buildBusinessInfoCard(BusinessModel business) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.location_on, size: 16, color: Colors.grey[600]),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  business.address,
                  style: TextStyle(fontSize: 13, color: Colors.grey[700]),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDatePicker() {
    return InkWell(
      onTap: () async {
        final date = await showDatePicker(
          context: context,
          initialDate: _selectedDate ?? DateTime.now(),
          firstDate: DateTime.now(),
          lastDate: DateTime.now().add(const Duration(days: 90)),
        );
        if (date != null) {
          setState(() => _selectedDate = date);
        }
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey[400]!),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(Icons.calendar_today, color: Colors.grey[700]),
            const SizedBox(width: 12),
            Text(
              _selectedDate != null
                  ? '${_selectedDate!.year}-${_selectedDate!.month.toString().padLeft(2, '0')}-${_selectedDate!.day.toString().padLeft(2, '0')}'
                  : '날짜 선택',
              style: TextStyle(
                fontSize: 16,
                color: _selectedDate != null ? Colors.black : Colors.grey[600],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDeadlinePicker() {
    return Column(
      children: [
        // 마감 날짜
        InkWell(
          onTap: () async {
            final date = await showDatePicker(
              context: context,
              initialDate: _selectedDeadlineDate ?? DateTime.now(),
              firstDate: DateTime.now(),
              lastDate: DateTime.now().add(const Duration(days: 90)),
            );
            if (date != null) {
              setState(() => _selectedDeadlineDate = date);
            }
          },
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey[400]!),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(Icons.calendar_today, color: Colors.grey[700]),
                const SizedBox(width: 12),
                Text(
                  _selectedDeadlineDate != null
                      ? '${_selectedDeadlineDate!.year}-${_selectedDeadlineDate!.month.toString().padLeft(2, '0')}-${_selectedDeadlineDate!.day.toString().padLeft(2, '0')}'
                      : '마감 날짜 선택',
                  style: TextStyle(
                    fontSize: 16,
                    color: _selectedDeadlineDate != null ? Colors.black : Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        // 마감 시간
        InkWell(
          onTap: () async {
            final time = await showTimePicker(
              context: context,
              initialTime: _selectedDeadlineTime ?? TimeOfDay.now(),
            );
            if (time != null) {
              setState(() => _selectedDeadlineTime = time);
            }
          },
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey[400]!),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(Icons.access_time, color: Colors.grey[700]),
                const SizedBox(width: 12),
                Text(
                  _selectedDeadlineTime != null
                      ? '${_selectedDeadlineTime!.hour.toString().padLeft(2, '0')}:${_selectedDeadlineTime!.minute.toString().padLeft(2, '0')}'
                      : '마감 시간 선택',
                  style: TextStyle(
                    fontSize: 16,
                    color: _selectedDeadlineTime != null ? Colors.black : Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// ✅ 업무 상세 카드 (시간 정보 표시)
  Widget _buildWorkDetailCard(WorkDetailInput detail, int index) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  detail.workType ?? '',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                // ✅ NEW: 근무 시간 표시
                Row(
                  children: [
                    Icon(Icons.access_time, size: 14, color: Colors.grey[600]),
                    const SizedBox(width: 4),
                    Text(
                      '${detail.startTime} ~ ${detail.endTime}',
                      style: TextStyle(fontSize: 13, color: Colors.grey[700]),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(Icons.payments, size: 14, color: Colors.green[600]),
                    const SizedBox(width: 4),
                    Text(
                      '${detail.wage?.toString().replaceAllMapped(
                        RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
                        (Match m) => '${m[1]},',
                      )}원',
                      style: const TextStyle(
                        fontSize: 13,
                        color: Colors.green,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Icon(Icons.people, size: 14, color: Colors.blue[600]),
                    const SizedBox(width: 4),
                    Text(
                      '${detail.requiredCount}명',
                      style: TextStyle(fontSize: 13, color: Colors.blue[700]),
                    ),
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, color: Colors.red),
            onPressed: () {
              setState(() {
                _workDetails.removeAt(index);
              });
            },
          ),
        ],
      ),
    );
  }
  // ✅ NEW Phase 2: 그룹 연결 섹션 위젯 추가 (여기에 추가!)
  /// 그룹 연결 섹션
  Widget _buildGroupLinkSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.blue[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blue[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 체크박스
          CheckboxListTile(
            value: _linkToExisting,
            onChanged: (value) {
              setState(() {
                _linkToExisting = value ?? false;
                if (_linkToExisting && _myRecentTOs.isEmpty) {
                  _loadRecentTOs(); // 최근 TO 로드
                }
              });
            },
            title: const Text(
              '기존 공고와 같은 TO입니다',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            subtitle: const Text(
              '지원자 명단이 합쳐집니다',
              style: TextStyle(fontSize: 13),
            ),
            contentPadding: EdgeInsets.zero,
          ),

          // 연결할 TO 선택 (체크박스 선택 시에만 표시)
          if (_linkToExisting) ...[
            const SizedBox(height: 12),
            const Divider(),
            const SizedBox(height: 12),
            
            if (_isLoadingRecentTOs)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: CircularProgressIndicator(),
                ),
              )
            else if (_myRecentTOs.isEmpty)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  '최근 30일 이내 생성한 TO가 없습니다.\n새 그룹으로 생성됩니다.',
                  style: TextStyle(fontSize: 13),
                  textAlign: TextAlign.center,
                ),
              )
            else ...[
              const Text(
                '연결할 공고 선택',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: _selectedGroupId,
                decoration: InputDecoration(
                  border: const OutlineInputBorder(),
                  filled: true,
                  fillColor: Colors.white,
                  hintText: '공고 선택',
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                ),
                // ✅ 선택된 항목 표시 (제목만)
                selectedItemBuilder: (BuildContext context) {
                  return _myRecentTOs.map((to) {
                    return Text(
                      to.title,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                      overflow: TextOverflow.ellipsis,
                    );
                  }).toList();
                },
                // ✅ 드롭다운 펼쳤을 때 표시 (제목 + 날짜)
                items: _myRecentTOs.map((to) {
                  return DropdownMenuItem<String>(
                    value: to.id,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          to.title,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${to.formattedDate} (${to.weekday})',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
                onChanged: (value) {
                  setState(() {
                    _selectedGroupId = value;
                  });
                },
              ),
            ],
          ],
        ],
      ),
    );
  }
}