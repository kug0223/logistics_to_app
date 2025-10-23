import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../services/firestore_service.dart';
import '../../providers/user_provider.dart';
import '../../models/business_model.dart';
import '../../utils/toast_helper.dart';
import '../../utils/constants.dart';

/// 중간관리자 TO 생성 화면 (여러 사업장 선택 가능)
class AdminCreateTOScreen extends StatefulWidget {
  const AdminCreateTOScreen({Key? key}) : super(key: key);

  @override
  State<AdminCreateTOScreen> createState() => _AdminCreateTOScreenState();
}

class _AdminCreateTOScreenState extends State<AdminCreateTOScreen> {
  final FirestoreService _firestoreService = FirestoreService();
  final _formKey = GlobalKey<FormState>();
  
  // 내 사업장 목록 ✅ 리스트로 변경
  List<BusinessModel> _myBusinesses = [];
  BusinessModel? _selectedBusiness; // ✅ 선택된 사업장
  bool _isLoadingBusinesses = true;
  
  // TO 생성 입력값
  DateTime? _selectedDate;
  String? _startTime;
  String? _endTime;
  String? _selectedWorkType;
  
  // TextField Controllers
  final TextEditingController _requiredCountController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  
  bool _isCreating = false;

  @override
  void initState() {
    super.initState();
    _loadMyBusinesses(); // ✅ 복수형
  }

  @override
  void dispose() {
    _requiredCountController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  /// 내가 소유한 모든 사업장 로드 ✅
  Future<void> _loadMyBusinesses() async {
    setState(() {
      _isLoadingBusinesses = true;
    });

    try {
      final userProvider = Provider.of<UserProvider>(context, listen: false);
      final user = userProvider.currentUser;

      if (user == null) {
        ToastHelper.showError('로그인 정보를 찾을 수 없습니다');
        return;
      }

      final uid = user.uid;
      print('🔍 내 사업장 조회 중... uid: $uid');

      // ✅ ownerId로 내 사업장 모두 조회
      final snapshot = await FirebaseFirestore.instance
          .collection('businesses')
          .where('ownerId', isEqualTo: uid)
          .get();

      final businesses = snapshot.docs
          .map((doc) => BusinessModel.fromMap(doc.data(), doc.id))
          .toList();

      print('✅ 조회된 사업장: ${businesses.length}개');

      setState(() {
        _myBusinesses = businesses;
        // 사업장이 1개면 자동 선택
        if (businesses.length == 1) {
          _selectedBusiness = businesses.first;
        }
        _isLoadingBusinesses = false;
      });
    } catch (e) {
      print('❌ 사업장 로드 실패: $e');
      setState(() {
        _isLoadingBusinesses = false;
      });
      ToastHelper.showError('사업장 정보를 불러오는데 실패했습니다');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('TO 생성'),
        backgroundColor: Colors.blue[700],
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      
      body: _isLoadingBusinesses
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
            
            // 3. 업무 유형
            _buildSectionTitle('💼 업무 유형', isRequired: true),
            const SizedBox(height: 8),
            _buildWorkTypeDropdown(),
            
            const SizedBox(height: 20),
            
            // 4. 필요 인원
            _buildSectionTitle('👥 필요 인원', isRequired: true),
            const SizedBox(height: 8),
            _buildRequiredCountField(),
            
            const SizedBox(height: 20),
            
            // 5. 설명 (선택)
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
                  backgroundColor: Colors.blue[700],
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

  /// ✅ 사업장 선택 드롭다운 (NEW!)
  Widget _buildBusinessDropdown() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<BusinessModel>(
          value: _selectedBusiness,
          hint: const Text('사업장을 선택하세요'),
          isExpanded: true,
          items: _myBusinesses.map((business) {
            return DropdownMenuItem(
              value: business,
              child: Row(
                children: [
                  Icon(Icons.business, size: 20, color: Colors.blue[700]),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      business.name,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
          onChanged: (value) {
            setState(() {
              _selectedBusiness = value;
            });
          },
        ),
      ),
    );
  }

  /// 사업장 정보 카드
  Widget _buildBusinessInfoCard(BusinessModel business) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.blue[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blue[200]!),
      ),
      child: Row(
        children: [
          Icon(Icons.business, color: Colors.blue[700], size: 40),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _myBusinesses.length > 1 ? '선택된 사업장' : '내 사업장',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.grey,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  business.name,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  business.address,
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey[700],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
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
            Icon(Icons.calendar_today, color: Colors.blue[700]),
            const SizedBox(width: 12),
            Text(
              _selectedDate == null
                  ? '날짜를 선택하세요'
                  : '${_selectedDate!.year}년 ${_selectedDate!.month}월 ${_selectedDate!.day}일',
              style: TextStyle(
                fontSize: 15,
                color: _selectedDate == null ? Colors.grey : Colors.black87,
              ),
            ),
          ],
        ),
      ),
    );
  }

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

  /// 시작 시간 선택
  Widget _buildStartTimePicker() {
    return InkWell(
      onTap: () => _selectTime(isStartTime: true),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey[300]!),
        ),
        child: Text(
          _startTime ?? '시작 시간',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 15,
            color: _startTime == null ? Colors.grey : Colors.black87,
          ),
        ),
      ),
    );
  }

  /// 종료 시간 선택
  Widget _buildEndTimePicker() {
    return InkWell(
      onTap: () => _selectTime(isStartTime: false),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey[300]!),
        ),
        child: Text(
          _endTime ?? '종료 시간',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 15,
            color: _endTime == null ? Colors.grey : Colors.black87,
          ),
        ),
      ),
    );
  }

  Future<void> _selectTime({required bool isStartTime}) async {
    final pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
    );

    if (pickedTime != null) {
      final timeString = '${pickedTime.hour.toString().padLeft(2, '0')}:${pickedTime.minute.toString().padLeft(2, '0')}';
      
      setState(() {
        if (isStartTime) {
          _startTime = timeString;
        } else {
          _endTime = timeString;
        }
      });
    }
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
              child: Text(workType),
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

  /// 필요 인원 입력
  Widget _buildRequiredCountField() {
    return TextFormField(
      controller: _requiredCountController,
      keyboardType: TextInputType.number,
      decoration: InputDecoration(
        hintText: '예: 5',
        prefixIcon: const Icon(Icons.people),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
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

  /// 설명 입력
  Widget _buildDescriptionField() {
    return TextFormField(
      controller: _descriptionController,
      maxLines: 3,
      decoration: InputDecoration(
        hintText: '업무 설명을 입력하세요 (선택사항)',
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }

  /// TO 생성
  Future<void> _createTO() async {
    // ✅ 사업장 선택 확인
    if (_selectedBusiness == null) {
      ToastHelper.showError('사업장을 선택하세요');
      return;
    }

    // 유효성 검증
    if (!_formKey.currentState!.validate()) {
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

      // ✅ 선택된 사업장으로 TO 생성
      await _firestoreService.createTO(
        businessId: _selectedBusiness!.id,
        businessName: _selectedBusiness!.name,
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