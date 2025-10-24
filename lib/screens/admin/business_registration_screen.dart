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
  final _displayNameController = TextEditingController(); // ✅ NEW: 공개 표시명
  bool _useDisplayName = false; // ✅ NEW: 표시명 사용 여부
  final _addressController = TextEditingController();
  final _detailAddressController = TextEditingController();
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
    _displayNameController.dispose(); // ✅ NEW
    _addressController.dispose();
    _detailAddressController.dispose();
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
    
    // ✅ NEW: displayName 사용 시 입력 검증
    if (_useDisplayName && _displayNameController.text.trim().isEmpty) {
      ToastHelper.showError('공개 표시명을 입력해주세요');
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
        
        if (result.latitude != null && result.longitude != null) {
          _latitude = result.latitude;
          _longitude = result.longitude;
          print('✅ 좌표 자동 입력: $_latitude, $_longitude');
        } else {
          print('⚠️ 좌표 정보 없음');
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

  /// 사업장 등록
  Future<void> _handleSubmit() async {
    setState(() => _isSaving = true);

    try {
      final userProvider = Provider.of<UserProvider>(context, listen: false);
      final uid = userProvider.currentUser?.uid;

      if (uid == null) {
        ToastHelper.showError('로그인이 필요합니다');
        return;
      }

      // 주소 조합 (기본 주소 + 상세 주소)
      String fullAddress = _addressController.text.trim();
      if (_detailAddressController.text.trim().isNotEmpty) {
        fullAddress += ', ${_detailAddressController.text.trim()}';
      }

      final business = BusinessModel(
        id: '',
        businessNumber: _businessNumberController.text.replaceAll('-', ''),
        name: _nameController.text.trim(),
        displayName: _useDisplayName ? _displayNameController.text.trim() : null, // ✅ NEW
        useDisplayName: _useDisplayName, // ✅ NEW
        category: _selectedCategory!,
        subCategory: _selectedSubCategory!,
        address: fullAddress,
        latitude: _latitude,
        longitude: _longitude,
        ownerId: uid,
        phone: _phoneController.text.trim().isNotEmpty ? _phoneController.text.trim() : null,
        description: _descriptionController.text.trim().isNotEmpty ? _descriptionController.text.trim() : null,
        isApproved: false,
        createdAt: DateTime.now(),
      );

      final businessId = await _firestoreService.createBusiness(business);

      if (businessId != null) {
        // UserModel의 businessId 업데이트
        await _firestoreService.updateUserBusinessId(uid, businessId);

        if (!mounted) return;

        ToastHelper.showSuccess('사업장이 등록되었습니다!');

        if (widget.isFromSignUp) {
          // 회원가입 후 → 로그인 화면으로
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(builder: (context) => const LoginScreen()),
            (route) => false,
          );
        } else {
          // 일반 등록 → 뒤로가기
          Navigator.pop(context, true);
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

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        if (widget.isFromSignUp) {
          // 회원가입 후라면 뒤로가기 방지
          final confirmed = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('등록 취소'),
              content: const Text('사업장 등록을 취소하시겠습니까?\n로그인 화면으로 이동합니다.'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('계속 등록'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('취소', style: TextStyle(color: Colors.red)),
                ),
              ],
            ),
          );

          if (confirmed == true && mounted) {
            Navigator.pushAndRemoveUntil(
              context,
              MaterialPageRoute(builder: (context) => const LoginScreen()),
              (route) => false,
            );
          }
          return false;
        }
        return true;
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('사업장 등록'),
          backgroundColor: Colors.blue[700],
          automaticallyImplyLeading: !widget.isFromSignUp,
        ),
        body: _isSaving
            ? const LoadingWidget(message: '사업장을 등록하는 중...')
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
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue[700],
                            foregroundColor: Colors.white,
                          ),
                          child: Text(_currentStep == 1 ? '완료' : '다음'),
                        ),
                        if (_currentStep > 0) ...[
                          const SizedBox(width: 12),
                          OutlinedButton(
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
              labelText: '사업장명 (정식 명칭)',
              hintText: '예: A물류센터',
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

          // ✅ NEW: 공개 표시명 사용 여부
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.blue[50],
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.blue[200]!),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.blue[700], size: 20),
                    const SizedBox(width: 8),
                    const Text(
                      '공개 표시명 설정',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'TO 공고에 회사명이나 브랜드명을 표시하고 싶다면 설정하세요.',
                  style: TextStyle(fontSize: 13, color: Colors.grey[700]),
                ),
                const SizedBox(height: 12),
                CheckboxListTile(
                  value: _useDisplayName,
                  onChanged: (value) {
                    setState(() {
                      _useDisplayName = value ?? false;
                    });
                  },
                  title: const Text('공개 표시명 사용'),
                  subtitle: const Text('예: 주식회사 위워커'),
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                ),
                
                // displayName 입력 필드 (체크박스 선택 시만 표시)
                if (_useDisplayName) ...[
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _displayNameController,
                    decoration: const InputDecoration(
                      labelText: '공개 표시명',
                      hintText: '예: 주식회사 위워커',
                      border: OutlineInputBorder(),
                      filled: true,
                      fillColor: Colors.white,
                    ),
                    validator: (value) {
                      if (_useDisplayName && (value == null || value.trim().isEmpty)) {
                        return '공개 표시명을 입력해주세요';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.preview, color: Colors.grey[600], size: 16),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'TO 공고 표시: ${_displayNameController.text.isEmpty ? "공개 표시명" : _displayNameController.text}',
                            style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
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

          // 상세주소 입력
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