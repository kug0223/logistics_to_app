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

  // Step 1 검증
  bool _validateStep1() {
    if (_selectedCategory == null || _selectedSubCategory == null) {
      ToastHelper.showError('업종을 선택해주세요');
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
      ToastHelper.showError('주소를 입력해주세요');
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
        _handleSubmit();
      }
    }
  }

  // 이전 단계로
  void _onStepCancel() {
    if (_currentStep > 0) {
      setState(() => _currentStep -= 1);
    }
  }

  /// 주소 검색 (✅ 수정됨)
  Future<void> _searchAddress() async {
    // ✅ DaumAddressService.searchAddress 사용 (올바른 방법)
    final result = await DaumAddressService.searchAddress(context);
    
    if (result != null) {
      setState(() {
        _addressController.text = result.fullAddress;
        
        // 좌표 자동 입력
        if (result.latitude != null && result.longitude != null) {
          _latitude = result.latitude;
          _longitude = result.longitude;
          print('✅ 좌표 자동 입력: $_latitude, $_longitude');
        }
      });
    }
  }

  /// 사업자등록번호 검증 (10자리 숫자)
  String? _validateBusinessNumber(String? value) {
    if (value == null || value.isEmpty) {
      return '사업자등록번호를 입력해주세요';
    }
    
    final cleanValue = value.replaceAll('-', '');
    
    if (cleanValue.length != 10) {
      return '사업자등록번호는 10자리여야 합니다';
    }
    
    if (!RegExp(r'^[0-9]+$').hasMatch(cleanValue)) {
      return '숫자만 입력해주세요';
    }
    
    return null;
  }

  /// 사업자등록번호 포맷팅 (000-00-00000)
  String _formatBusinessNumber(String value) {
    final cleaned = value.replaceAll('-', '');
    if (cleaned.length <= 3) {
      return cleaned;
    } else if (cleaned.length <= 5) {
      return '${cleaned.substring(0, 3)}-${cleaned.substring(3)}';
    } else {
      return '${cleaned.substring(0, 3)}-${cleaned.substring(3, 5)}-${cleaned.substring(5, cleaned.length > 10 ? 10 : cleaned.length)}';
    }
  }

  /// 사업장 등록
  Future<void> _handleSubmit() async {
    if (_latitude == null || _longitude == null) {
      ToastHelper.showError('주소 검색을 통해 좌표를 입력해주세요');
      return;
    }

    setState(() => _isSaving = true);

    try {
      final userProvider = context.read<UserProvider>();
      final currentUser = userProvider.currentUser;
      
      if (currentUser == null) {
        ToastHelper.showError('로그인이 필요합니다');
        return;
      }

      // 사업자등록번호에서 하이픈 제거
      final cleanBusinessNumber = _businessNumberController.text.replaceAll('-', '');

      final business = BusinessModel(
        id: '',
        name: _nameController.text.trim(),
        category: _selectedCategory!,
        subCategory: _selectedSubCategory!,
        businessNumber: cleanBusinessNumber,
        address: _addressController.text.trim(),
        latitude: _latitude!,
        longitude: _longitude!,
        ownerId: currentUser.uid,
        phone: _phoneController.text.trim().isEmpty ? null : _phoneController.text.trim(),
        description: _descriptionController.text.trim().isEmpty ? null : _descriptionController.text.trim(),
        isApproved: false,
        createdAt: DateTime.now(),
        updatedAt: null,
      );

      final businessId = await _firestoreService.createBusiness(business);

      if (businessId != null && mounted) {
        // ✅ 사용자의 businessId 업데이트 (Firestore 직접 호출)
        await FirebaseFirestore.instance
            .collection('users')
            .doc(currentUser.uid)
            .update({'businessId': businessId});

        // ✅ UserProvider 새로고침 (refreshUserData 사용)
        await userProvider.refreshUserData();

        // 성공 다이얼로그
        if (mounted) {
          await showDialog(
            context: context,
            barrierDismissible: false,
            builder: (context) => AlertDialog(
              title: const Text('사업장 등록 완료'),
              content: const Text(
                '사업장 등록이 완료되었습니다.\n'
                '슈퍼관리자의 승인 후 TO 생성이 가능합니다.',
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.pop(context); // 다이얼로그 닫기
                    
                    // ✅ 회원가입에서 온 경우: 로그인 화면으로
                    // ✅ 홈에서 온 경우: 홈으로
                    if (widget.isFromSignUp) {
                      Navigator.pushNamedAndRemoveUntil(
                        context,
                        '/login',
                        (route) => false,
                      );
                    } else {
                      Navigator.pop(context); // 사업장 등록 화면 닫기 (홈으로)
                    }
                  },
                  child: const Text('확인'),
                ),
              ],
            ),
          );
        }
      }
    } catch (e) {
      print('❌ 사업장 등록 실패: $e');
      ToastHelper.showError('사업장 등록에 실패했습니다');
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  /// 뒤로가기 처리
  Future<bool> _onWillPop() async {
    // ✅ 회원가입에서 온 경우: 확인 다이얼로그
    if (widget.isFromSignUp) {
      final shouldPop = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('사업장 등록'),
          content: const Text(
            '사업장 등록을 나중에 하시겠습니까?\n'
            '마이페이지에서 언제든 등록할 수 있습니다.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('계속 등록'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('나중에 하기'),
            ),
          ],
        ),
      );
      return shouldPop ?? false;
    }
    
    // ✅ 홈에서 온 경우: 바로 뒤로가기
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: _onWillPop,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('사업장 등록'),
          leading: widget.isFromSignUp 
              ? null  // ✅ 회원가입에서 온 경우: 뒤로가기 버튼 숨김
              : IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () => Navigator.pop(context),
                ),
        ),
        body: _isSaving
            ? const Center(child: CircularProgressIndicator())
            : Stepper(
                currentStep: _currentStep,
                onStepContinue: _onStepContinue,
                onStepCancel: _currentStep > 0 ? _onStepCancel : null,
                controlsBuilder: (context, details) {
                  return Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Row(
                      children: [
                        ElevatedButton(
                          onPressed: details.onStepContinue,
                          child: Text(_currentStep == 1 ? '등록하기' : '다음'),
                        ),
                        if (details.onStepCancel != null) ...[
                          const SizedBox(width: 12),
                          TextButton(
                            onPressed: details.onStepCancel,
                            child: const Text('이전'),
                          ),
                        ],
                      ],
                    ),
                  );
                },
                steps: [
                  // Step 1: 업종 선택
                  Step(
                    title: const Text('업종 선택'),
                    content: _buildCategorySelection(),
                    isActive: _currentStep >= 0,
                    state: _currentStep > 0 ? StepState.complete : StepState.indexed,
                  ),
                  
                  // Step 2: 사업장 정보
                  Step(
                    title: const Text('사업장 정보'),
                    content: _buildBusinessInfoForm(),
                    isActive: _currentStep >= 1,
                    state: _currentStep > 1 ? StepState.complete : StepState.indexed,
                  ),
                ],
              ),
      ),
    );
  }

  /// Step 1: 업종 선택 (가치업 스타일)
  Widget _buildCategorySelection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: AppConstants.jobCategories.entries.map((entry) {
        final category = entry.key;
        final subCategories = entry.value;

        return ExpansionTile(
          title: Text(
            category,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          initiallyExpanded: _selectedCategory == category,
          children: subCategories.map((subCategory) {
            return RadioListTile<String>(
              title: Text(subCategory),
              value: subCategory,
              groupValue: _selectedSubCategory,
              onChanged: (value) {
                setState(() {
                  _selectedCategory = category;
                  _selectedSubCategory = value;
                });
              },
            );
          }).toList(),
        );
      }).toList(),
    );
  }

  /// Step 2: 사업장 정보 입력 폼
  Widget _buildBusinessInfoForm() {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ✅ 사업자등록번호
          TextFormField(
            controller: _businessNumberController,
            decoration: const InputDecoration(
              labelText: '사업자등록번호',
              hintText: '000-00-00000',
              helperText: '10자리 숫자를 입력해주세요',
            ),
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9-]')),
              LengthLimitingTextInputFormatter(12), // 000-00-00000 (12자)
            ],
            validator: _validateBusinessNumber,
            onChanged: (value) {
              final formatted = _formatBusinessNumber(value);
              if (formatted != value) {
                _businessNumberController.value = TextEditingValue(
                  text: formatted,
                  selection: TextSelection.collapsed(offset: formatted.length),
                );
              }
            },
          ),
          const SizedBox(height: 16),

          // 사업장명
          TextFormField(
            controller: _nameController,
            decoration: const InputDecoration(
              labelText: '사업장명',
              hintText: '예: 스타벅스 강남점',
            ),
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return '사업장명을 입력해주세요';
              }
              return null;
            },
          ),
          const SizedBox(height: 16),

          // 주소
          TextFormField(
            controller: _addressController,
            decoration: InputDecoration(
              labelText: '주소',
              hintText: '주소 검색 버튼을 눌러주세요',
              suffixIcon: IconButton(
                icon: const Icon(Icons.search),
                onPressed: _searchAddress,
                tooltip: '주소 검색',
              ),
            ),
            readOnly: true,
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return '주소를 입력해주세요';
              }
              return null;
            },
          ),
          const SizedBox(height: 8),
          
          // 좌표 안내 텍스트
          if (_latitude != null && _longitude != null)
            Padding(
              padding: const EdgeInsets.only(left: 12),
              child: Text(
                '✅ 좌표: $_latitude, $_longitude',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.green.shade700,
                ),
              ),
            ),
          const SizedBox(height: 16),

          // 연락처 (선택)
          TextFormField(
            controller: _phoneController,
            decoration: const InputDecoration(
              labelText: '연락처 (선택)',
              hintText: '010-1234-5678',
            ),
            keyboardType: TextInputType.phone,
          ),
          const SizedBox(height: 16),

          // 설명 (선택)
          TextFormField(
            controller: _descriptionController,
            decoration: const InputDecoration(
              labelText: '설명 (선택)',
              hintText: '사업장에 대한 간단한 설명을 입력해주세요',
            ),
            maxLines: 3,
            maxLength: 500,
          ),
        ],
      ),
    );
  }
}