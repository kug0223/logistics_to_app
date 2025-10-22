import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/firestore_service.dart';
import '../../providers/user_provider.dart';
import '../../utils/toast_helper.dart';
import '../../utils/constants.dart';

/// 관리자 TO 생성 화면
class AdminCreateTOScreen extends StatefulWidget {
  const AdminCreateTOScreen({Key? key}) : super(key: key);

  @override
  State<AdminCreateTOScreen> createState() => _AdminCreateTOScreenState();
}

class _AdminCreateTOScreenState extends State<AdminCreateTOScreen> {
  final FirestoreService _firestoreService = FirestoreService();
  final _formKey = GlobalKey<FormState>();
  
  // 선택된 값들
  String? _selectedCenterId;
  String? _selectedCenterName;
  DateTime? _selectedDate;
  String? _startTime;
  String? _endTime;
  String? _selectedWorkType;
  
  // TextField Controllers
  final TextEditingController _requiredCountController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  
  bool _isCreating = false;

  @override
  void dispose() {
    _requiredCountController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('TO 생성'),
        backgroundColor: Colors.purple[700],
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 안내 카드
              _buildInfoCard(),
              
              const SizedBox(height: 24),
              
              // 1. 센터 선택
              _buildSectionTitle('🏢 센터 선택', isRequired: true),
              const SizedBox(height: 8),
              _buildCenterDropdown(),
              
              const SizedBox(height: 20),
              
              // 2. 날짜 선택
              _buildSectionTitle('📅 날짜 선택', isRequired: true),
              const SizedBox(height: 8),
              _buildDatePicker(),
              
              const SizedBox(height: 20),
              
              // 3. 시간 선택
              _buildSectionTitle('⏰ 근무 시간', isRequired: true),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(child: _buildStartTimePicker()),
                  const SizedBox(width: 12),
                  const Icon(Icons.arrow_forward, color: Colors.grey),
                  const SizedBox(width: 12),
                  Expanded(child: _buildEndTimePicker()),
                ],
              ),
              
              const SizedBox(height: 20),
              
              // 4. 업무 유형 선택
              _buildSectionTitle('💼 업무 유형', isRequired: true),
              const SizedBox(height: 8),
              _buildWorkTypeDropdown(),
              
              const SizedBox(height: 20),
              
              // 5. 필요 인원
              _buildSectionTitle('👥 필요 인원', isRequired: true),
              const SizedBox(height: 8),
              _buildRequiredCountField(),
              
              const SizedBox(height: 20),
              
              // 6. 설명 (선택사항)
              _buildSectionTitle('📝 설명', isRequired: false),
              const SizedBox(height: 8),
              _buildDescriptionField(),
              
              const SizedBox(height: 32),
              
              // 생성 버튼
              _buildCreateButton(),
              
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  /// 안내 카드
  Widget _buildInfoCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.purple[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.purple[200]!),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, color: Colors.purple[700], size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              '새로운 TO를 생성합니다.\n모든 필수 항목을 입력해주세요.',
              style: TextStyle(
                color: Colors.purple[900],
                fontSize: 13,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 섹션 제목
  Widget _buildSectionTitle(String title, {required bool isRequired}) {
    return Row(
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
        ),
        if (isRequired) ...[
          const SizedBox(width: 4),
          const Text(
            '*',
            style: TextStyle(
              color: Colors.red,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ],
    );
  }

  /// 센터 선택 드롭다운
  Widget _buildCenterDropdown() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _selectedCenterId,
          hint: const Text('센터를 선택하세요'),
          isExpanded: true,
          items: AppConstants.centers.map((center) {
            return DropdownMenuItem(
              value: center['id'],
              child: Row(
                children: [
                  Icon(Icons.warehouse, size: 20, color: Colors.purple[700]),
                  const SizedBox(width: 8),
                  Text(center['name']!),
                ],
              ),
            );
          }).toList(),
          onChanged: (value) {
            setState(() {
              _selectedCenterId = value;
              _selectedCenterName = AppConstants.centers
                  .firstWhere((c) => c['id'] == value)['name'];
            });
          },
        ),
      ),
    );
  }

  /// 날짜 선택
  Widget _buildDatePicker() {
    return InkWell(
      onTap: _selectDate,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey[300]!),
        ),
        child: Row(
          children: [
            Icon(Icons.calendar_today, color: Colors.purple[700]),
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

  /// 시작 시간 선택
  Widget _buildStartTimePicker() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _startTime,
          hint: const Text('시작', style: TextStyle(fontSize: 14)),
          isExpanded: true,
          items: _generateTimeSlots(),
          onChanged: (value) {
            setState(() {
              _startTime = value;
            });
          },
        ),
      ),
    );
  }

  /// 종료 시간 선택
  Widget _buildEndTimePicker() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _endTime,
          hint: const Text('종료', style: TextStyle(fontSize: 14)),
          isExpanded: true,
          items: _generateTimeSlots(),
          onChanged: (value) {
            setState(() {
              _endTime = value;
            });
          },
        ),
      ),
    );
  }

  /// 업무 유형 드롭다운
  Widget _buildWorkTypeDropdown() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _selectedWorkType,
          hint: const Text('업무 유형을 선택하세요'),
          isExpanded: true,
          items: AppConstants.workTypes.map((workType) {
            return DropdownMenuItem(
              value: workType,
              child: Row(
                children: [
                  Icon(_getWorkTypeIcon(workType), size: 20, color: Colors.purple[700]),
                  const SizedBox(width: 8),
                  Text(workType),
                ],
              ),
            );
          }).toList(),
          onChanged: (value) {
            setState(() {
              _selectedWorkType = value;
            });
          },
        ),
      ),
    );
  }

  /// 필요 인원 입력 필드
  Widget _buildRequiredCountField() {
    return TextFormField(
      controller: _requiredCountController,
      keyboardType: TextInputType.number,
      decoration: InputDecoration(
        hintText: '필요한 인원 수를 입력하세요',
        prefixIcon: Icon(Icons.people, color: Colors.purple[700]),
        suffixText: '명',
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey[300]!),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey[300]!),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.purple[700]!, width: 2),
        ),
      ),
      validator: (value) {
        if (value == null || value.isEmpty) {
          return '필요 인원을 입력하세요';
        }
        final count = int.tryParse(value);
        if (count == null || count <= 0) {
          return '1명 이상 입력하세요';
        }
        return null;
      },
    );
  }

  /// 설명 입력 필드
  Widget _buildDescriptionField() {
    return TextFormField(
      controller: _descriptionController,
      maxLines: 4,
      decoration: InputDecoration(
        hintText: '업무에 대한 추가 설명을 입력하세요 (선택사항)',
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey[300]!),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey[300]!),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.purple[700]!, width: 2),
        ),
      ),
    );
  }

  /// TO 생성 버튼
  Widget _buildCreateButton() {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton.icon(
        onPressed: _isCreating ? null : _createTO,
        icon: _isCreating
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              )
            : const Icon(Icons.add_circle, size: 24),
        label: Text(
          _isCreating ? 'TO 생성 중...' : 'TO 생성하기',
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.purple[700],
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          elevation: 2,
        ),
      ),
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
            child: Text(timeStr, style: const TextStyle(fontSize: 14)),
          ),
        );
      }
    }
    
    return items;
  }

  /// 업무 유형 아이콘
  IconData _getWorkTypeIcon(String workType) {
    switch (workType) {
      case '피킹':
        return Icons.shopping_cart;
      case '패킹':
        return Icons.inventory_2;
      case '배송':
        return Icons.local_shipping;
      case '분류':
        return Icons.sort;
      case '하역':
        return Icons.handyman;
      case '검수':
        return Icons.fact_check;
      default:
        return Icons.work;
    }
  }

  /// 날짜 선택
  Future<void> _selectDate() async {
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 90)),
    );

    if (pickedDate != null) {
      setState(() {
        _selectedDate = pickedDate;
      });
    }
  }

  /// TO 생성
  Future<void> _createTO() async {
    // 유효성 검증
    if (!_formKey.currentState!.validate()) {
      return;
    }

    if (_selectedCenterId == null) {
      ToastHelper.showError('센터를 선택하세요');
      return;
    }

    if (_selectedDate == null) {
      ToastHelper.showError('날짜를 선택하세요');
      return;
    }

    if (_startTime == null || _endTime == null) {
      ToastHelper.showError('근무 시간을 선택하세요');
      return;
    }

    // 종료 시간 > 시작 시간 검증
    if (_endTime!.compareTo(_startTime!) <= 0) {
      ToastHelper.showError('종료 시간은 시작 시간보다 커야 합니다');
      return;
    }

    if (_selectedWorkType == null) {
      ToastHelper.showError('업무 유형을 선택하세요');
      return;
    }

    setState(() {
      _isCreating = true;
    });

    try {
      final userProvider = Provider.of<UserProvider>(context, listen: false);
      final uid = userProvider.currentUser?.uid;

      if (uid == null) {
        throw Exception('로그인 정보를 찾을 수 없습니다');
      }

      final requiredCount = int.parse(_requiredCountController.text);

      await _firestoreService.createTO(
        centerId: _selectedCenterId!,
        centerName: _selectedCenterName!,
        date: _selectedDate!,
        startTime: _startTime!,
        endTime: _endTime!,
        workType: _selectedWorkType!,
        requiredCount: requiredCount,
        description: _descriptionController.text.trim(),
        creatorUID: uid,
      );

      ToastHelper.showSuccess('TO가 생성되었습니다');
      Navigator.pop(context, true); // 생성 성공 플래그 전달

    } catch (e) {
      print('❌ TO 생성 실패: $e');
      ToastHelper.showError('TO 생성에 실패했습니다: ${e.toString()}');
    } finally {
      if (mounted) {
        setState(() {
          _isCreating = false;
        });
      }
    }
  }
}