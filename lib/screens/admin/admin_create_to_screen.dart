import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/business_model.dart';
import '../../services/firestore_service.dart';
import '../../providers/user_provider.dart';
import '../../utils/toast_helper.dart';
import '../../utils/constants.dart';
import '../../models/business_work_type_model.dart';

/// TO 생성 화면 (사업장 관리자 전용)
/// Phase 1: 마감 시간 기능 추가
class AdminCreateTOScreen extends StatefulWidget {
  const AdminCreateTOScreen({super.key});

  @override
  State<AdminCreateTOScreen> createState() => _AdminCreateTOScreenState();
}

class _AdminCreateTOScreenState extends State<AdminCreateTOScreen> {
  final _formKey = GlobalKey<FormState>();
  final _firestoreService = FirestoreService();

  // 컨트롤러
  final TextEditingController _requiredCountController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();

  // 상태 변수
  bool _isLoading = true;
  bool _isCreating = false;
  List<BusinessModel> _myBusinesses = [];
  BusinessModel? _selectedBusiness;
  List<BusinessWorkTypeModel> _businessWorkTypes = [];

  // 입력 값
  DateTime? _selectedDate;
  String? _selectedStartTime;
  String? _selectedEndTime;
  String? _selectedWorkType;

  // ✅ Phase 1: 마감 시간 변수 추가
  DateTime? _selectedDeadlineDate;
  TimeOfDay? _selectedDeadlineTime;

  @override
  void initState() {
    super.initState();
    _loadMyBusinesses();
  }

  @override
  void dispose() {
    _requiredCountController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  /// 내 사업장 불러오기 (디버깅 강화)
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
          // ✅ 사업장이 하나면 바로 업무 유형 로드
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
  // 4. 새 메서드 추가 - 사업장별 업무 유형 로드
  Future<void> _loadBusinessWorkTypes(String businessId) async {
    try {
      final workTypes = await _firestoreService.getBusinessWorkTypes(businessId);
      
      setState(() {
        _businessWorkTypes = workTypes;
        // 기존에 선택된 업무 유형이 새 목록에 없으면 초기화
        if (_selectedWorkType != null && 
            !workTypes.any((wt) => wt.name == _selectedWorkType)) {
          _selectedWorkType = null;
        }
      });

      if (workTypes.isEmpty) {
        ToastHelper.showWarning('등록된 업무 유형이 없습니다.\n설정에서 업무 유형을 먼저 등록하세요.');
      }
    } catch (e) {
      print('❌ 업무 유형 로드 실패: $e');
      ToastHelper.showError('업무 유형을 불러올 수 없습니다');
    }
  }

  /// 날짜 선택
  Future<void> _pickDate() async {
    final DateTime now = DateTime.now();
    final DateTime today = DateTime(now.year, now.month, now.day);

    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? today,
      firstDate: today,
      lastDate: DateTime(now.year + 1),
      locale: const Locale('ko', 'KR'),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(
              primary: Colors.blue.shade700,
              onPrimary: Colors.white,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        _selectedDate = picked;
      });
    }
  }

  /// 시작 시간 선택
  Future<void> _pickStartTime() async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: _selectedStartTime != null
          ? TimeOfDay(
              hour: int.parse(_selectedStartTime!.split(':')[0]),
              minute: int.parse(_selectedStartTime!.split(':')[1]),
            )
          : const TimeOfDay(hour: 9, minute: 0),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(
              primary: Colors.blue.shade700,
              onPrimary: Colors.white,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        _selectedStartTime = '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
      });
    }
  }

  /// 종료 시간 선택
  Future<void> _pickEndTime() async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: _selectedEndTime != null
          ? TimeOfDay(
              hour: int.parse(_selectedEndTime!.split(':')[0]),
              minute: int.parse(_selectedEndTime!.split(':')[1]),
            )
          : const TimeOfDay(hour: 18, minute: 0),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(
              primary: Colors.blue.shade700,
              onPrimary: Colors.white,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        _selectedEndTime = '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
      });
    }
  }

  // ✅ Phase 1: 마감 날짜 선택
  Future<void> _pickDeadlineDate() async {
    final DateTime now = DateTime.now();
    final DateTime today = DateTime(now.year, now.month, now.day);
    
    // 근무 날짜가 선택되어 있으면 그 날짜까지만 선택 가능
    final DateTime? maxDate = _selectedDate;

    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDeadlineDate ?? today,
      firstDate: today, // 오늘부터 선택 가능
      lastDate: maxDate ?? DateTime(now.year + 1), // 근무 날짜 or 1년 후
      locale: const Locale('ko', 'KR'),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(
              primary: Colors.blue.shade700,
              onPrimary: Colors.white,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        _selectedDeadlineDate = picked;
      });
    }
  }

  // ✅ Phase 1: 마감 시간 선택
  Future<void> _pickDeadlineTime() async {
    if (_selectedDeadlineDate == null) {
      ToastHelper.showWarning('먼저 마감 날짜를 선택해주세요');
      return;
    }

    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: _selectedDeadlineTime ?? const TimeOfDay(hour: 18, minute: 0),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(
              primary: Colors.blue.shade700,
              onPrimary: Colors.white,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        _selectedDeadlineTime = picked;
      });
    }
  }

  /// TO 생성
  Future<void> _createTO() async {
    // 기본 유효성 검증
    if (!_formKey.currentState!.validate()) {
      ToastHelper.showWarning('모든 필수 항목을 입력해주세요');
      return;
    }

    if (_selectedBusiness == null) {
      ToastHelper.showWarning('사업장을 선택해주세요');
      return;
    }

    if (_selectedDate == null) {
      ToastHelper.showWarning('근무 날짜를 선택해주세요');
      return;
    }

    if (_selectedStartTime == null || _selectedEndTime == null) {
      ToastHelper.showWarning('근무 시간을 선택해주세요');
      return;
    }

    // ✅ Phase 1: 마감 일시 유효성 검증
    if (_selectedDeadlineDate == null || _selectedDeadlineTime == null) {
      ToastHelper.showWarning('지원 마감 일시를 선택해주세요');
      return;
    }

    // ✅ Phase 1: 마감 일시 생성
    final DateTime applicationDeadline = DateTime(
      _selectedDeadlineDate!.year,
      _selectedDeadlineDate!.month,
      _selectedDeadlineDate!.day,
      _selectedDeadlineTime!.hour,
      _selectedDeadlineTime!.minute,
    );

    // ✅ Phase 1: 마감 일시가 현재 시간 이후인지 확인
    if (applicationDeadline.isBefore(DateTime.now())) {
      ToastHelper.showError('마감 일시는 현재 시간 이후여야 합니다');
      return;
    }

    // ✅ Phase 1: 마감 일시가 근무 시작 전인지 확인
    final DateTime workStartDateTime = DateTime(
      _selectedDate!.year,
      _selectedDate!.month,
      _selectedDate!.day,
      int.parse(_selectedStartTime!.split(':')[0]),
      int.parse(_selectedStartTime!.split(':')[1]),
    );

    if (applicationDeadline.isAfter(workStartDateTime)) {
      ToastHelper.showError('마감 일시는 근무 시작 시간 이전이어야 합니다');
      return;
    }

    // 종료 시간 > 시작 시간 확인
    final startHour = int.parse(_selectedStartTime!.split(':')[0]);
    final startMinute = int.parse(_selectedStartTime!.split(':')[1]);
    final endHour = int.parse(_selectedEndTime!.split(':')[0]);
    final endMinute = int.parse(_selectedEndTime!.split(':')[1]);

    if (endHour < startHour || (endHour == startHour && endMinute <= startMinute)) {
      ToastHelper.showWarning('종료 시간은 시작 시간보다 늦어야 합니다');
      return;
    }

    if (_selectedWorkType == null) {
      ToastHelper.showWarning('업무 유형을 선택해주세요');
      return;
    }

    if (_requiredCountController.text.isEmpty ||
        int.tryParse(_requiredCountController.text) == null ||
        int.parse(_requiredCountController.text) <= 0) {
      ToastHelper.showWarning('필요 인원을 올바르게 입력해주세요');
      return;
    }

    setState(() => _isCreating = true);

    try {
      final userProvider = Provider.of<UserProvider>(context, listen: false);
      final uid = userProvider.currentUser?.uid;

      if (uid == null) {
        ToastHelper.showError('로그인 정보를 찾을 수 없습니다');
        return;
      }

      // ✅ Phase 1: applicationDeadline 파라미터 추가
      final toId = await _firestoreService.createTO(
        businessId: _selectedBusiness!.id,
        businessName: _selectedBusiness!.name,
        date: _selectedDate!,
        startTime: _selectedStartTime!,
        endTime: _selectedEndTime!,
        applicationDeadline: applicationDeadline, // ✅ Phase 1: 추가!
        workType: _selectedWorkType!,
        requiredCount: int.parse(_requiredCountController.text),
        description: _descriptionController.text.trim().isEmpty
            ? null
            : _descriptionController.text.trim(),
        creatorUID: uid,
      );

      if (toId != null) {
        ToastHelper.showSuccess('TO가 생성되었습니다');
        Navigator.pop(context, true); // true 반환 (성공)
      } else {
        ToastHelper.showError('TO 생성에 실패했습니다');
      }
    } catch (e) {
      print('❌ TO 생성 실패: $e');
      ToastHelper.showError('TO 생성 중 오류가 발생했습니다');
    } finally {
      if (mounted) {
        setState(() => _isCreating = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('TO 생성'),
        backgroundColor: Colors.blue.shade700,
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _myBusinesses.isEmpty
              ? _buildNoBusinessState()
              : _buildCreateForm(),
    );
  }

  /// 사업장 미등록 상태
  Widget _buildNoBusinessState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.business_outlined,
              size: 100,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 24),
            Text(
              '등록된 사업장이 없습니다',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.grey[800],
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'TO를 생성하려면 먼저 사업장을 등록해주세요',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 32),
            ElevatedButton.icon(
              onPressed: () {
                Navigator.pop(context);
                ToastHelper.showInfo('사업장 등록 화면으로 이동하세요');
              },
              icon: const Icon(Icons.arrow_back),
              label: const Text('뒤로 가기'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                textStyle: const TextStyle(fontSize: 16),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// TO 생성 폼
  Widget _buildCreateForm() {
    return Form(
      key: _formKey,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ✅ 사업장 선택 드롭다운 (여러 개일 때만 표시)
            if (_myBusinesses.length > 1) ...[
              _buildSectionTitle('🏢 사업장 선택', isRequired: true),
              const SizedBox(height: 8),
              _buildBusinessDropdown(),
              const SizedBox(height: 24),
            ],
            
            // 선택된 사업장 정보 카드
            if (_selectedBusiness != null) ...[
              _buildBusinessInfoCard(_selectedBusiness!),
              const SizedBox(height: 24),
            ],
            
            // 1. 날짜 선택
            _buildSectionTitle('📅 근무 날짜', isRequired: true),
            const SizedBox(height: 8),
            _buildDatePicker(),
            
            const SizedBox(height: 20),
            
            // 2. 시간 선택
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
            
            // ✅ Phase 1: 3. 마감 일시 입력 (NEW!)
            _buildSectionTitle('🕐 지원 마감 일시', isRequired: true),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.orange[700], size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '근무 시작 전까지 지원 마감 시간을 설정하세요',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.orange[900],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            
            // 마감 날짜/시간 선택
            Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: _pickDeadlineDate,
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.calendar_today, color: Colors.blue[700], size: 20),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              _selectedDeadlineDate == null
                                  ? '마감 날짜 선택'
                                  : '${_selectedDeadlineDate!.year}년 ${_selectedDeadlineDate!.month}월 ${_selectedDeadlineDate!.day}일',
                              style: TextStyle(
                                fontSize: 15,
                                color: _selectedDeadlineDate == null
                                    ? Colors.grey[600]
                                    : Colors.black87,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                
                // 마감 시간 선택
                Expanded(
                  child: InkWell(
                    onTap: _pickDeadlineTime,
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.access_time, color: Colors.blue[700], size: 20),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              _selectedDeadlineTime == null
                                  ? '마감 시간 선택'
                                  : '${_selectedDeadlineTime!.hour.toString().padLeft(2, '0')}:${_selectedDeadlineTime!.minute.toString().padLeft(2, '0')}',
                              style: TextStyle(
                                fontSize: 15,
                                color: _selectedDeadlineTime == null
                                    ? Colors.grey[600]
                                    : Colors.black87,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
            
            const SizedBox(height: 20),
            
            // 4. 업무 유형
            _buildSectionTitle('💼 업무 유형', isRequired: true),
            const SizedBox(height: 8),
            _buildWorkTypeDropdown(),
            
            const SizedBox(height: 20),
            
            // 5. 필요 인원
            _buildSectionTitle('👥 필요 인원', isRequired: true),
            const SizedBox(height: 8),
            _buildRequiredCountField(),
            
            const SizedBox(height: 20),
            
            // 6. 설명 (선택)
            _buildSectionTitle('📝 설명', isRequired: false),
            const SizedBox(height: 8),
            _buildDescriptionField(),
            
            const SizedBox(height: 32),
            
            // 생성 버튼
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _isCreating ? null : _createTO,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue.shade700,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _isCreating
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : const Text(
                        'TO 생성',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
              ),
            ),
            
            const SizedBox(height: 32),
          ],
        ),
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

  /// 사업장 선택 드롭다운
  Widget _buildBusinessDropdown() {
    return DropdownButtonFormField<BusinessModel>(
      value: _selectedBusiness,
      decoration: InputDecoration(
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        prefixIcon: const Icon(Icons.business),
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
          _selectedWorkType = null; // ✅ 업무 유형 초기화
        });
        // ✅ 사업장 변경 시 해당 사업장의 업무 유형 로드
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

  /// 사업장 정보 카드
  Widget _buildBusinessInfoCard(BusinessModel business) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.blue[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blue.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.business, color: Colors.blue[700], size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  business.name,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.blue[900],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(Icons.location_on, color: Colors.blue[600], size: 16),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  business.address,
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey[700],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 날짜 선택
  Widget _buildDatePicker() {
    return InkWell(
      onTap: _pickDate,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade300),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(Icons.calendar_today, color: Colors.blue[700], size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                _selectedDate == null
                    ? '날짜를 선택하세요'
                    : '${_selectedDate!.year}년 ${_selectedDate!.month}월 ${_selectedDate!.day}일',
                style: TextStyle(
                  fontSize: 15,
                  color: _selectedDate == null ? Colors.grey[600] : Colors.black87,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 시작 시간 선택
  Widget _buildStartTimePicker() {
    return InkWell(
      onTap: _pickStartTime,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade300),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(Icons.access_time, color: Colors.blue[700], size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                _selectedStartTime ?? '시작 시간',
                style: TextStyle(
                  fontSize: 15,
                  color: _selectedStartTime == null ? Colors.grey[600] : Colors.black87,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 종료 시간 선택
  Widget _buildEndTimePicker() {
    return InkWell(
      onTap: _pickEndTime,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade300),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(Icons.access_time, color: Colors.blue[700], size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                _selectedEndTime ?? '종료 시간',
                style: TextStyle(
                  fontSize: 15,
                  color: _selectedEndTime == null ? Colors.grey[600] : Colors.black87,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 업무 유형 드롭다운
  Widget _buildWorkTypeDropdown() {
    // ✅ 업무 유형이 없으면 안내 메시지
    if (_businessWorkTypes.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.orange[50],
          border: Border.all(color: Colors.orange[300]!),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(Icons.warning_amber, color: Colors.orange[700]),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                '등록된 업무 유형이 없습니다.\n설정에서 업무 유형을 먼저 등록하세요.',
                style: TextStyle(color: Colors.orange[900]),
              ),
            ),
          ],
        ),
      );
    }

    return DropdownButtonFormField<String>(
      value: _selectedWorkType,
      decoration: InputDecoration(
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        prefixIcon: const Icon(Icons.work),
        hintText: '업무 유형 선택',
      ),
      items: _businessWorkTypes.map((workType) {
        final color = Color(
          int.parse(workType.color.replaceFirst('#', '0xFF')),
        );
        
        return DropdownMenuItem(
          value: workType.name,
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Center(
                  child: Text(workType.icon, style: const TextStyle(fontSize: 16)),
                ),
              ),
              const SizedBox(width: 12),
              Text(workType.name),
            ],
          ),
        );
      }).toList(),
      onChanged: (value) {
        setState(() {
          _selectedWorkType = value;
        });
      },
      validator: (value) {
        if (value == null || value.isEmpty) return '업무 유형을 선택하세요';
        return null;
      },
    );
  }

  /// 필요 인원 입력
  Widget _buildRequiredCountField() {
    return TextFormField(
      controller: _requiredCountController,
      keyboardType: TextInputType.number,
      decoration: InputDecoration(
        hintText: '필요한 인원 수를 입력하세요',
        suffixText: '명',
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      ),
    );
  }

  /// 설명 입력
  Widget _buildDescriptionField() {
    return TextFormField(
      controller: _descriptionController,
      maxLines: 4,
      decoration: InputDecoration(
        hintText: '업무에 대한 상세 설명을 입력하세요 (선택사항)',
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        contentPadding: const EdgeInsets.all(16),
      ),
    );
  }
}