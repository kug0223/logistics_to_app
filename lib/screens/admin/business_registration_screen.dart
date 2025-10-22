import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/business_model.dart';
import '../../services/firestore_service.dart';
import '../../providers/user_provider.dart';
import '../../utils/constants.dart';
import '../../utils/toast_helper.dart';
import '../../widgets/daum_address_search.dart';

/// 사업장 등록 화면 (회원가입 후)
class BusinessRegistrationScreen extends StatefulWidget {
  final bool isFromSignUp; // ✅ 회원가입에서 온 경우 true
  
  const BusinessRegistrationScreen({
    Key? key,
    this.isFromSignUp = false,
  }) : super(key: key);

  @override
  State<BusinessRegistrationScreen> createState() => _BusinessRegistrationScreenState();
}

class _BusinessRegistrationScreenState extends State<BusinessRegistrationScreen> {
  final _formKey = GlobalKey<FormState>();
  final FirestoreService _firestoreService = FirestoreService();
  
  int _currentStep = 0;
  
  // Step 1: 업종 선택
  String? _selectedCategory;
  String? _selectedSubCategory;
  
  // Step 2: 사업장 정보
  final _businessNumberController = TextEditingController();
  final _nameController = TextEditingController();
  final _addressController = TextEditingController();
  final _phoneController = TextEditingController();
  final _descriptionController = TextEditingController();
  
  // 숨겨진 필드 (자동 입력)
  double? _latitude;
  double? _longitude;
  
  bool _isSaving = false;

  @override
  void dispose() {
    _businessNumberController.dispose();
    _nameController.dispose();
    _addressController.dispose();
    _phoneController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  // ✅ 🆕 로그인 화면으로 돌아가기 (나중에 등록하기)
  void _goToLogin() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('나중에 등록하기'),
        content: const Text(
          '사업장 등록을 나중에 하시겠습니까?\n\n'
          '로그인 후 언제든지 사업장을 등록할 수 있습니다.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context); // 다이얼로그 닫기
              // 로그인 화면으로 이동 (모든 화면 제거)
              Navigator.of(context).pushNamedAndRemoveUntil(
                '/login',
                (route) => false,
              );
            },
            style: TextButton.styleFrom(foregroundColor: Colors.blue),
            child: const Text('나중에 하기'),
          ),
        ],
      ),
    );
  }

  // Step 1 검증
  bool _validateStep1() {
    if (_selectedCategory == null) {
      ToastHelper.showError('업종을 선택해주세요');
      return false;
    }
    if (_selectedSubCategory == null) {
      ToastHelper.showError('세부 업종을 선택해주세요');
      return false;
    }
    return true;
  }

  // Step 2 검증
  bool _validateStep2() {
    if (!_formKey.currentState!.validate()) {
      return false;
    }
    if (_addressController.text.isEmpty) {
      ToastHelper.showError('주소를 검색해주세요');
      return false;
    }
    if (_latitude == null || _longitude == null) {
      ToastHelper.showError('주소 검색 후 위도/경도가 자동 입력됩니다');
      return false;
    }
    return true;
  }

  // 다음 단계로
  void _onStepContinue() {
    if (_currentStep == 0) {
      if (_validateStep1()) {
        setState(() => _currentStep = 1);
      }
    } else if (_currentStep == 1) {
      if (_validateStep2()) {
        _saveBusiness();
      }
    }
  }

  // 이전 단계로
  void _onStepCancel() {
    if (_currentStep > 0) {
      setState(() => _currentStep -= 1);
    }
  }

  // 사업장 저장
  Future<void> _saveBusiness() async {
    if (_isSaving) return;

    setState(() => _isSaving = true);

    try {
      final userProvider = context.read<UserProvider>();
      final uid = userProvider.currentUser?.uid;
      
      if (uid == null) {
        ToastHelper.showError('로그인 정보를 찾을 수 없습니다');
        return;
      }

      // ✅ BusinessModel 생성 (수정됨!)
      final business = BusinessModel(
        id: '',  // 🆕 추가!
        businessNumber: _businessNumberController.text.trim(),
        name: _nameController.text.trim(),
        category: _selectedCategory!,
        subCategory: _selectedSubCategory!,
        address: _addressController.text.trim(),
        latitude: _latitude,
        longitude: _longitude,
        ownerId: uid,
        phone: _phoneController.text.trim().isEmpty   // 🆕 phoneNumber → phone
            ? null 
            : _phoneController.text.trim(),
        description: _descriptionController.text.trim().isEmpty 
            ? null 
            : _descriptionController.text.trim(),
        isApproved: true,
        createdAt: DateTime.now(),
      );

      // Firestore에 저장
      final businessId = await _firestoreService.createBusiness(business);

      // users 컬렉션의 businessId 업데이트
      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .update({'businessId': businessId});

      // UserProvider 업데이트
      await userProvider.refreshUser();

      if (!mounted) return;

      ToastHelper.showSuccess('사업장이 등록되었습니다!');

      // 홈 화면으로 이동
      Navigator.of(context).pushNamedAndRemoveUntil(
        '/home',
        (route) => false,
      );
    } catch (e) {
      if (mounted) {
        ToastHelper.showError('사업장 등록 실패: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  // 주소 검색 완료 콜백
  void _onAddressSelected(String address, double latitude, double longitude) {
    setState(() {
      _addressController.text = address;
      _latitude = latitude;
      _longitude = longitude;
    });
    ToastHelper.showSuccess('주소가 입력되었습니다');
  }

  // 사업자등록번호 자동 포맷팅 (000-00-00000)
  void _formatBusinessNumber(String value) {
    final digitsOnly = value.replaceAll(RegExp(r'[^0-9]'), '');
    String formatted = '';
    
    for (int i = 0; i < digitsOnly.length && i < 10; i++) {
      if (i == 3 || i == 5) {
        formatted += '-';
      }
      formatted += digitsOnly[i];
    }
    
    _businessNumberController.value = TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        // ✅ 회원가입에서 온 경우에만 나중에 하기 다이얼로그 표시
        if (widget.isFromSignUp) {
          _goToLogin();
          return false; // 뒤로가기 차단
        }
        return true; // 홈에서 온 경우 뒤로가기 허용
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('사업장 등록'),
          backgroundColor: Colors.blue.shade700,
          // ✅ 회원가입에서 온 경우 뒤로가기 버튼 숨김
          automaticallyImplyLeading: !widget.isFromSignUp,
          actions: [
            // ✅ 🆕 회원가입에서 온 경우 "나중에 하기" 버튼 표시
            if (widget.isFromSignUp)
              TextButton.icon(
                onPressed: _goToLogin,
                icon: const Icon(Icons.skip_next, color: Colors.white),
                label: const Text(
                  '나중에 하기',
                  style: TextStyle(color: Colors.white),
                ),
              ),
          ],
        ),
        body: Stepper(
          type: StepperType.horizontal,
          currentStep: _currentStep,
          onStepContinue: _onStepContinue,
          onStepCancel: _currentStep > 0 ? _onStepCancel : null,
          controlsBuilder: (context, details) {
            return Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Row(
                children: [
                  // 다음/완료 버튼
                  ElevatedButton(
                    onPressed: _isSaving ? null : details.onStepContinue,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue.shade700,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 32,
                        vertical: 12,
                      ),
                    ),
                    child: _isSaving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Text(
                            _currentStep == 1 ? '등록 완료' : '다음',
                            style: const TextStyle(fontSize: 16),
                          ),
                  ),
                  
                  const SizedBox(width: 12),
                  
                  // 이전 버튼
                  if (_currentStep > 0)
                    OutlinedButton(
                      onPressed: details.onStepCancel,
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 32,
                          vertical: 12,
                        ),
                      ),
                      child: const Text('이전'),
                    ),
                ],
              ),
            );
          },
          steps: [
            // Step 1: 업종 선택
            Step(
              title: const Text('업종 선택'),
              isActive: _currentStep >= 0,
              state: _currentStep > 0 ? StepState.complete : StepState.indexed,
              content: _buildStep1(),
            ),
            
            // Step 2: 사업장 정보
            Step(
              title: const Text('사업장 정보'),
              isActive: _currentStep >= 1,
              state: _currentStep > 1 ? StepState.complete : StepState.indexed,
              content: _buildStep2(),
            ),
          ],
        ),
      ),
    );
  }

  // Step 1: 업종 선택 UI
  Widget _buildStep1() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '사업장의 업종을 선택해주세요',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 24),

        // 대분류 선택
        const Text(
          '대분류',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: Colors.grey,
          ),
        ),
        const SizedBox(height: 8),
        
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: AppConstants.jobCategories.keys.map((category) {
            final isSelected = _selectedCategory == category;
            return ChoiceChip(
              label: Text(category),
              selected: isSelected,
              onSelected: (selected) {
                setState(() {
                  _selectedCategory = selected ? category : null;
                  _selectedSubCategory = null; // 소분류 초기화
                });
              },
              selectedColor: Colors.blue.shade100,
              labelStyle: TextStyle(
                color: isSelected ? Colors.blue.shade700 : Colors.black87,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              ),
            );
          }).toList(),
        ),
        
        if (_selectedCategory != null) ...[
          const SizedBox(height: 24),
          const Text(
            '세부 업종',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: Colors.grey,
            ),
          ),
          const SizedBox(height: 8),
          
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: AppConstants.jobCategories[_selectedCategory]!.map((subCategory) {
              final isSelected = _selectedSubCategory == subCategory;
              return ChoiceChip(
                label: Text(subCategory),
                selected: isSelected,
                onSelected: (selected) {
                  setState(() {
                    _selectedSubCategory = selected ? subCategory : null;
                  });
                },
                selectedColor: Colors.blue.shade100,
                labelStyle: TextStyle(
                  color: isSelected ? Colors.blue.shade700 : Colors.black87,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                ),
              );
            }).toList(),
          ),
        ],
        
        const SizedBox(height: 16),
      ],
    );
  }

  // Step 2: 사업장 정보 UI
  Widget _buildStep2() {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '사업장 정보를 입력해주세요',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 24),

          // 사업자등록번호
          TextFormField(
            controller: _businessNumberController,
            decoration: InputDecoration(
              labelText: '사업자등록번호 *',
              hintText: '000-00-00000',
              border: const OutlineInputBorder(),
              prefixIcon: const Icon(Icons.business_center),
              helperText: '10자리 숫자를 입력하세요',
            ),
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(10),
            ],
            onChanged: _formatBusinessNumber,
            validator: (value) {
              if (value == null || value.isEmpty) {
                return '사업자등록번호를 입력해주세요';
              }
              final digitsOnly = value.replaceAll(RegExp(r'[^0-9]'), '');
              if (digitsOnly.length != 10) {
                return '10자리 숫자를 입력해주세요';
              }
              return null;
            },
          ),
          const SizedBox(height: 16),

          // 사업장명
          TextFormField(
            controller: _nameController,
            decoration: const InputDecoration(
              labelText: '사업장명 *',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.store),
            ),
            validator: (value) {
              if (value == null || value.isEmpty) {
                return '사업장명을 입력해주세요';
              }
              return null;
            },
          ),
          const SizedBox(height: 16),

          // 주소 검색
          TextFormField(
            controller: _addressController,
            decoration: InputDecoration(
              labelText: '주소 *',
              border: const OutlineInputBorder(),
              prefixIcon: const Icon(Icons.location_on),
              suffixIcon: IconButton(
                icon: const Icon(Icons.search),
                onPressed: () {
                  showDialog(
                    context: context,
                    builder: (context) => Dialog(
                      child: SizedBox(
                        width: 600,
                        height: 600,
                        child: DaumAddressSearch(
                          onAddressSelected: _onAddressSelected,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            readOnly: true,
            onTap: () {
              showDialog(
                context: context,
                builder: (context) => Dialog(
                  child: SizedBox(
                    width: 600,
                    height: 600,
                    child: DaumAddressSearch(
                      onAddressSelected: _onAddressSelected,
                    ),
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 16),

          // 연락처 (선택)
          TextFormField(
            controller: _phoneController,
            decoration: const InputDecoration(
              labelText: '연락처 (선택)',
              hintText: '010-1234-5678',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.phone),
            ),
            keyboardType: TextInputType.phone,
          ),
          const SizedBox(height: 16),

          // 설명 (선택)
          TextFormField(
            controller: _descriptionController,
            decoration: const InputDecoration(
              labelText: '사업장 설명 (선택)',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.description),
            ),
            maxLines: 3,
          ),

          const SizedBox(height: 16),
        ],
      ),
    );
  }
}