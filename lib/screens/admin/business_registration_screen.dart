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
import '../auth/login_screen.dart';

/// 사업장 등록 화면 (회원가입 후)
class BusinessRegistrationScreen extends StatefulWidget {
  final bool isFromSignUp;
  
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
  final _detailAddressController = TextEditingController(); // ⭐ 상세주소 추가!
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
    _detailAddressController.dispose(); // ⭐ 추가
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

  /// 주소 검색
  Future<void> _searchAddress() async {
    final result = await DaumAddressService.searchAddress(context);
    
    if (result != null) {
      setState(() {
        _addressController.text = result.fullAddress;
        
        // 좌표 자동 입력
        if (result.latitude != null && result.longitude != null) {
          _latitude = result.latitude;
          _longitude = result.longitude;
          print('✅ 좌표 자동 입력: $_latitude, $_longitude');
        } else {
          print('⚠️ 좌표 정보 없음 (수동 입력 모드)');
      }
      });
    }
  }

  /// 사업자등록번호 검증
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

  /// 사업자등록번호 포맷팅
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

  /// 사업장 등록 처리
  Future<void> _handleSubmit() async {
    if (_isSaving) return;
    
    setState(() => _isSaving = true);
    
    try {
      final userProvider = Provider.of<UserProvider>(context, listen: false);
      final uid = userProvider.currentUser?.uid;
      
      if (uid == null) {
        ToastHelper.showError('로그인 정보를 찾을 수 없습니다');
        return;
      }
      
      // ⭐ 전체 주소 = 기본 주소 + 상세주소
      final fullAddress = _detailAddressController.text.trim().isEmpty
          ? _addressController.text.trim()
          : '${_addressController.text.trim()} ${_detailAddressController.text.trim()}';
      
      // 사업장 모델 생성
      final business = BusinessModel(
        id: '',
        ownerId: uid,
        businessNumber: _businessNumberController.text.replaceAll('-', ''),
        name: _nameController.text.trim(),
        category: _selectedCategory!,
        subCategory: _selectedSubCategory!,
        address: fullAddress, // ⭐ 전체 주소 저장
        latitude: _latitude,
        longitude: _longitude,
        phone: _phoneController.text.trim(),
        description: _descriptionController.text.trim(),
        isApproved: true,
        createdAt: DateTime.now(),
      );
      
      // Firestore에 저장
      final businessId = await _firestoreService.createBusiness(business);
      
      // users 컬렉션에 businessId 업데이트
      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .update({'businessId': businessId});
      
      ToastHelper.showSuccess('사업장 등록이 완료되었습니다!');
      
      if (mounted) {
        // ✅ 이 부분을 수정하세요!
        if (widget.isFromSignUp) {
          // 회원가입에서 온 경우 → 로그인 화면으로
          Navigator.of(context).pushNamedAndRemoveUntil(
            '/login',  // ← '/home'을 '/login'으로 변경!
            (route) => false,
          );
          
          // 추가 안내 메시지
          Future.delayed(const Duration(milliseconds: 500), () {
            if (mounted) {
              ToastHelper.showInfo('등록하신 계정으로 로그인해주세요');
            }
          });
        } else {
          // 홈에서 온 경우 → 단순히 뒤로가기
          Navigator.of(context).pop(true);
        }
      }
    } catch (e) {
      print('❌ 사업장 등록 에러: $e');
      ToastHelper.showError('사업장 등록에 실패했습니다: $e');
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        // ⭐ 회원가입에서 온 경우만 다이얼로그 표시
        if (widget.isFromSignUp) {
          final shouldPop = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('사업장 등록 취소'),
              content: const Text(
                '사업장 등록을 나중에 하시겠습니까?\n'
                '나중에 프로필에서 등록할 수 있습니다.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('계속 등록'),
                ),
                TextButton(
                  onPressed: () {
                    Navigator.pop(context, true);  // 다이얼로그 닫기
                    // ✅ 이 줄을 추가하세요!
                    Navigator.of(context).pushNamedAndRemoveUntil(
                      '/login',
                      (route) => false,
                    );
                  },
                  child: const Text('나중에 하기'),
                ),
              ],
            ),
          );
          return shouldPop ?? false;
        }
        return true; // 홈에서 온 경우 그냥 뒤로가기
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('사업장 등록'),
          backgroundColor: Colors.blue.shade700,
          automaticallyImplyLeading: !widget.isFromSignUp, // ⭐ 회원가입에서 온 경우 뒤로가기 버튼 숨김
        ),
        body: _isSaving
            ? const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text('사업장 등록 중...'),
                  ],
                ),
              )
            : Stepper(
                currentStep: _currentStep,
                onStepContinue: _onStepContinue,
                onStepCancel: _onStepCancel,
                controlsBuilder: (context, details) {
                  return Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Row(
                      children: [
                        ElevatedButton(
                          onPressed: details.onStepContinue,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue.shade700,
                            foregroundColor: Colors.white,
                          ),
                          child: Text(_currentStep == 1 ? '등록 완료' : '다음'),
                        ),
                        if (_currentStep > 0) ...[
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
                    content: _buildCategoryStep(),
                    isActive: _currentStep >= 0,
                    state: _currentStep > 0 ? StepState.complete : StepState.indexed,
                  ),
                  
                  // Step 2: 사업장 정보
                  Step(
                    title: const Text('사업장 정보'),
                    content: _buildBusinessInfoStep(),
                    isActive: _currentStep >= 1,
                    state: _currentStep > 1 ? StepState.complete : StepState.indexed,
                  ),
                ],
              ),
      ),
    );
  }

  /// Step 1: 업종 선택
  Widget _buildCategoryStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: AppConstants.jobCategories.entries.map((entry) {
        return ExpansionTile(
          title: Text(
            entry.key,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          children: entry.value.map((subCategory) {
            return RadioListTile<String>(
              title: Text(subCategory),
              value: subCategory,
              groupValue: _selectedSubCategory,
              onChanged: (value) {
                setState(() {
                  _selectedCategory = entry.key;
                  _selectedSubCategory = value;
                });
              },
            );
          }).toList(),
        );
      }).toList(),
    );
  }

  /// Step 2: 사업장 정보
  Widget _buildBusinessInfoStep() {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 사업자등록번호
          TextFormField(
            controller: _businessNumberController,
            decoration: const InputDecoration(
              labelText: '사업자등록번호',
              hintText: '000-00-00000',
              border: OutlineInputBorder(),
            ),
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9-]')),
              LengthLimitingTextInputFormatter(12),
            ],
            onChanged: (value) {
              final formatted = _formatBusinessNumber(value);
              if (formatted != value) {
                _businessNumberController.value = TextEditingValue(
                  text: formatted,
                  selection: TextSelection.collapsed(offset: formatted.length),
                );
              }
            },
            validator: _validateBusinessNumber,
          ),
          const SizedBox(height: 16),

          // 사업장명
          TextFormField(
            controller: _nameController,
            decoration: const InputDecoration(
              labelText: '사업장명',
              border: OutlineInputBorder(),
            ),
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
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
              labelText: '주소',
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                icon: const Icon(Icons.search),
                onPressed: _searchAddress,
              ),
            ),
            readOnly: true,
            onTap: _searchAddress,
          ),
          const SizedBox(height: 16),

          // ⭐ 상세주소 입력 (NEW!)
          TextFormField(
            controller: _detailAddressController,
            decoration: const InputDecoration(
              labelText: '상세주소 (동/호수 등)',
              hintText: '예: 101동 1502호',
              border: OutlineInputBorder(),
            ),
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 16),

          // 연락처
          TextFormField(
            controller: _phoneController,
            decoration: const InputDecoration(
              labelText: '연락처 (선택)',
              hintText: '010-0000-0000',
              border: OutlineInputBorder(),
            ),
            keyboardType: TextInputType.phone,
          ),
          const SizedBox(height: 16),

          // 설명
          TextFormField(
            controller: _descriptionController,
            decoration: const InputDecoration(
              labelText: '사업장 설명 (선택)',
              border: OutlineInputBorder(),
            ),
            maxLines: 3,
          ),
        ],
      ),
    );
  }
}