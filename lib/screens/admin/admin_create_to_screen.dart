import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/business_model.dart';
import '../../services/firestore_service.dart';
import '../../providers/user_provider.dart';
import '../../utils/toast_helper.dart';
import '../../models/business_work_type_model.dart';

/// TO 생성 화면 - 업무 상세(최대 3개) 추가 방식
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
  String? _selectedStartTime;
  String? _selectedEndTime;
  DateTime? _selectedDeadlineDate;
  TimeOfDay? _selectedDeadlineTime;

  // ✅ NEW: 업무 상세 리스트 (최대 3개)
  List<WorkDetailInput> _workDetails = [];

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

    if (_selectedStartTime == null || _selectedEndTime == null) {
      ToastHelper.showWarning('근무 시간을 선택해주세요.');
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
      }).toList();

      // TO 생성
      final toId = await _firestoreService.createTOWithDetails(
        businessId: _selectedBusiness!.id,
        businessName: _selectedBusiness!.name,
        title: _titleController.text.trim(),
        date: _selectedDate!,
        startTime: _selectedStartTime!,
        endTime: _selectedEndTime!,
        applicationDeadline: deadlineDateTime,
        workDetailsData: workDetailsData,
        description: _descriptionController.text.trim().isNotEmpty
            ? _descriptionController.text.trim()
            : null,
        creatorUID: uid,
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

  /// 업무 추가 다이얼로그
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

    // 이미 추가된 업무유형 제외
    final availableWorkTypes = _businessWorkTypes.where((wt) {
      return !_workDetails.any((detail) => detail.workType == wt.name);
    }).toList();

    if (availableWorkTypes.isEmpty) {
      ToastHelper.showWarning('모든 업무 유형이 추가되었습니다.');
      return;
    }

    final result = await showDialog<WorkDetailInput>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('업무 추가'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 업무 유형 선택
                const Text('업무 유형', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: selectedWorkType,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                  items: availableWorkTypes.map((wt) {
                    return DropdownMenuItem(
                      value: wt.name,
                      child: Row(
                        children: [
                          Text(wt.icon, style: const TextStyle(fontSize: 20)),
                          const SizedBox(width: 8),
                          Text(wt.name),
                        ],
                      ),
                    );
                  }).toList(),
                  onChanged: (value) {
                    setDialogState(() => selectedWorkType = value);
                  },
                ),
                const SizedBox(height: 16),

                // 금액 입력
                const Text('금액 (원)', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                TextField(
                  controller: wageController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    hintText: '예: 50000',
                    suffixText: '원',
                  ),
                ),
                const SizedBox(height: 16),

                // 필요 인원 입력
                const Text('필요 인원 (명)', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                TextField(
                  controller: countController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    hintText: '예: 5',
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
                if (selectedWorkType == null) {
                  ToastHelper.showWarning('업무 유형을 선택하세요.');
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
                );

                Navigator.pop(context, detail);
              },
              child: const Text('추가'),
            ),
          ],
        ),
      ),
    );

    if (result != null) {
      setState(() {
        _workDetails.add(result);
      });
    }
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
                hintText: '예: 물류센터 파트타임알바',
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

            // 근무 날짜
            _buildSectionTitle('📅 근무 날짜'),
            _buildDatePicker(),
            const SizedBox(height: 24),

            // 근무 시간
            _buildSectionTitle('⏰ 근무 시간'),
            Row(
              children: [
                Expanded(child: _buildStartTimePicker()),
                const SizedBox(width: 16),
                Expanded(child: _buildEndTimePicker()),
              ],
            ),
            const SizedBox(height: 24),

            // 지원 마감 시간
            _buildSectionTitle('⏱️ 지원 마감 시간'),
            _buildDeadlinePicker(),
            const SizedBox(height: 24),

            // 업무 상세 (최대 3개)
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
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.blue[900],
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
        prefixIcon: Icon(Icons.business),
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
          _workDetails.clear(); // 사업장 변경 시 업무 목록 초기화
        });
        if (value != null) {
          _loadBusinessWorkTypes(value.id);
        }
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
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(Icons.location_on, size: 16, color: Colors.grey[600]),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              business.address,
              style: TextStyle(fontSize: 13, color: Colors.grey[700]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDatePicker() {
    return InkWell(
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: _selectedDate ?? DateTime.now(),
          firstDate: DateTime.now(),
          lastDate: DateTime.now().add(const Duration(days: 90)),
        );
        if (picked != null) {
          setState(() => _selectedDate = picked);
        }
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey[300]!),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(Icons.calendar_today, color: Colors.blue[700]),
            const SizedBox(width: 12),
            Text(
              _selectedDate == null
                  ? '날짜를 선택하세요'
                  : '${_selectedDate!.year}년 ${_selectedDate!.month}월 ${_selectedDate!.day}일',
              style: TextStyle(
                fontSize: 15,
                color: _selectedDate == null ? Colors.grey[600] : Colors.black87,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStartTimePicker() {
    return InkWell(
      onTap: () async {
        final picked = await showTimePicker(
          context: context,
          initialTime: const TimeOfDay(hour: 9, minute: 0),
        );
        if (picked != null) {
          setState(() {
            _selectedStartTime = '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
          });
        }
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey[300]!),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(Icons.access_time, color: Colors.blue[700], size: 20),
            const SizedBox(width: 8),
            Text(
              _selectedStartTime ?? '시작',
              style: TextStyle(
                fontSize: 15,
                color: _selectedStartTime == null ? Colors.grey[600] : Colors.black87,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEndTimePicker() {
    return InkWell(
      onTap: () async {
        final picked = await showTimePicker(
          context: context,
          initialTime: const TimeOfDay(hour: 18, minute: 0),
        );
        if (picked != null) {
          setState(() {
            _selectedEndTime = '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
          });
        }
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey[300]!),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(Icons.access_time, color: Colors.blue[700], size: 20),
            const SizedBox(width: 8),
            Text(
              _selectedEndTime ?? '종료',
              style: TextStyle(
                fontSize: 15,
                color: _selectedEndTime == null ? Colors.grey[600] : Colors.black87,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDeadlinePicker() {
    return InkWell(
      onTap: () async {
        // 날짜 선택
        final pickedDate = await showDatePicker(
          context: context,
          initialDate: _selectedDeadlineDate ?? DateTime.now(),
          firstDate: DateTime.now(),
          lastDate: _selectedDate ?? DateTime.now().add(const Duration(days: 90)),
        );

        if (pickedDate != null) {
          // 시간 선택
          if (!mounted) return;
          final pickedTime = await showTimePicker(
            context: context,
            initialTime: _selectedDeadlineTime ?? const TimeOfDay(hour: 18, minute: 0),
          );

          if (pickedTime != null) {
            setState(() {
              _selectedDeadlineDate = pickedDate;
              _selectedDeadlineTime = pickedTime;
            });
          }
        }
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey[300]!),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(Icons.alarm, color: Colors.orange[700]),
            const SizedBox(width: 12),
            Text(
              _selectedDeadlineDate == null || _selectedDeadlineTime == null
                  ? '마감 시간을 선택하세요'
                  : '${_selectedDeadlineDate!.month}/${_selectedDeadlineDate!.day} '
                    '${_selectedDeadlineTime!.hour.toString().padLeft(2, '0')}:'
                    '${_selectedDeadlineTime!.minute.toString().padLeft(2, '0')}',
              style: TextStyle(
                fontSize: 15,
                color: _selectedDeadlineDate == null ? Colors.grey[600] : Colors.black87,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWorkDetailCard(WorkDetailInput detail, int index) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blue[200]!),
      ),
      child: Row(
        children: [
          // 순서 표시
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: Colors.blue[700],
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                '${index + 1}',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),

          // 업무 정보
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
                const SizedBox(height: 4),
                Text(
                  '${detail.formattedWage} | ${detail.requiredCount}명',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[700],
                  ),
                ),
              ],
            ),
          ),

          // 삭제 버튼
          IconButton(
            onPressed: () {
              setState(() {
                _workDetails.removeAt(index);
              });
            },
            icon: const Icon(Icons.delete, color: Colors.red),
          ),
        ],
      ),
    );
  }
}

/// 업무 상세 입력 클래스
class WorkDetailInput {
  final String? workType;
  final int? wage;
  final int? requiredCount;

  WorkDetailInput({
    this.workType,
    this.wage,
    this.requiredCount,
  });

  bool get isValid =>
      workType != null &&
      wage != null &&
      wage! > 0 &&
      requiredCount != null &&
      requiredCount! > 0;

  String get formattedWage {
    if (wage == null) return '';
    return '${wage!.toString().replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (Match m) => '${m[1]},',
    )}원';
  }
}