import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart'; // ✅ 추가
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
  final _businessNumberController = TextEditingController(); // ✅ 사업자등록번호 추가!
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

  /// 주소 검색
  Future<void> _searchAddress() async {
    final result = await DaumAddressService.searchAddress(context);
    
    if (result != null) {
      setState(() {
        _addressController.text = result.fullAddress;
        
        // ✅ 좌표 자동 입력 (사용자에게는 보이지 않음)
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
    
    // 하이픈 제거
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
    final userProvider = context.read<UserProvider>();
    final uid = userProvider.currentUser?.uid;
    
    if (uid == null) {
      ToastHelper.showError('로그인 정보를 찾을 수 없습니다');
      return;
    }

    setState(() => _isSaving = true);

    try {
      // 사업자등록번호 정리 (하이픈 제거)
      final cleanBusinessNumber = _businessNumberController.text.replaceAll('-', '');
      
      final business = BusinessModel(
        id: '', // Firestore에서 자동 생성
        businessNumber: cleanBusinessNumber, // ✅ 사업자등록번호
        name: _nameController.text.trim(),
        category: _selectedCategory!,
        subCategory: _selectedSubCategory!,
        address: _addressController.text.trim(),
        latitude: _latitude, // ✅ 자동 입력된 좌표
        longitude: _longitude, // ✅ 자동 입력된 좌표
        ownerId: uid,
        phone: _phoneController.text.trim().isNotEmpty 
            ? _phoneController.text.trim() 
            : null,
        description: _descriptionController.text.trim().isNotEmpty 
            ? _descriptionController.text.trim() 
            : null,
        isApproved: true, // ✅ 바로 승인 (슈퍼관리자 승인 불필요)
        createdAt: DateTime.now(),
      );

      final businessId = await _firestoreService.createBusiness(business);
      
      if (businessId != null && mounted) {
        // ✅ 사용자의 businessId 업데이트 (Firestore 직접 호출)
        await FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .update({'businessId': businessId});
        
        await userProvider.refreshUserData();
        
        ToastHelper.showSuccess('사업장 등록이 완료되었습니다!');
        
        // ✅ 사업장 관리자 홈으로 이동 (기존 스택 모두 제거)
        if (mounted) {
          Navigator.of(context).pushNamedAndRemoveUntil(
            '/',
            (route) => false,
          );
        }
      }
    } catch (e) {
      print('사업장 등록 실패: $e');
      ToastHelper.showError('사업장 등록 중 오류가 발생했습니다');
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // ✅ 회원가입에서 온 경우만 뒤로가기 방지
    if (widget.isFromSignUp) {
      return WillPopScope(
        onWillPop: () async {
          final shouldPop = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('등록 취소'),
              content: const Text('사업장 등록을 나중에 하시겠습니까?'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('계속 등록'),
                ),
                TextButton(
                  onPressed: () {
                    Navigator.pop(context, true);
                    // ✅ 홈으로 이동 (사업장 없이)
                    Navigator.of(context).pushNamedAndRemoveUntil(
                      '/',
                      (route) => false,
                    );
                  },
                  style: TextButton.styleFrom(foregroundColor: Colors.blue),
                  child: const Text('나중에 하기'),
                ),
              ],
            ),
          );
          return shouldPop ?? false;
        },
        child: _buildScaffold(),
      );
    }
    
    // ✅ 일반 접근 (홈에서 온 경우): 뒤로가기 허용
    return _buildScaffold();
  }

  Widget _buildScaffold() {
    return Scaffold(
      appBar: AppBar(
        title: const Text('사업장 등록'),
        automaticallyImplyLeading: !widget.isFromSignUp, // ✅ 회원가입에서 온 경우만 뒤로가기 숨김
        elevation: 0,
      ),
      body: SafeArea(
        child: Stepper(
          currentStep: _currentStep,
          onStepContinue: _isSaving ? null : _onStepContinue,
          onStepCancel: _currentStep > 0 ? _onStepCancel : null,
          controlsBuilder: (context, details) {
            return Padding(
              padding: const EdgeInsets.only(top: 24.0),
              child: Row(
                children: [
                  if (_currentStep == 0)
                    Expanded(
                      child: ElevatedButton(
                        onPressed: details.onStepContinue,
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: const Text('다음', style: TextStyle(fontSize: 16)),
                      ),
                    )
                  else ...[
                    Expanded(
                      child: OutlinedButton(
                        onPressed: details.onStepCancel,
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: const Text('이전'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _isSaving ? null : details.onStepContinue,
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: _isSaving
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text('등록 완료', style: TextStyle(fontSize: 16)),
                      ),
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
              subtitle: const Text('사업장 업종을 선택해주세요'),
              isActive: _currentStep >= 0,
              state: _currentStep > 0 ? StepState.complete : StepState.indexed,
              content: _buildCategorySelection(),
            ),
            
            // Step 2: 사업장 정보
            Step(
              title: const Text('사업장 정보'),
              subtitle: const Text('사업장 정보를 입력해주세요'),
              isActive: _currentStep >= 1,
              state: _currentStep > 1 ? StepState.complete : StepState.indexed,
              content: _buildBusinessInfoForm(),
            ),
          ],
        ),
      ),
    );
  }

  /// Step 1: 업종 선택 UI
  Widget _buildCategorySelection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 16),
        
        // 안내 문구
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.blue[50],
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Icon(Icons.business, color: Colors.blue[700]),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  '어떤 업종의 사업장인가요?',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.blue[900],
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        // 업종 카테고리
        ...AppConstants.jobCategories.entries.map((entry) {
          final category = entry.key;
          final subCategories = entry.value;
          final isExpanded = _selectedCategory == category;

          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              border: Border.all(
                color: isExpanded ? Colors.blue : Colors.grey[300]!,
                width: isExpanded ? 2 : 1,
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Theme(
              data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                title: Text(
                  category,
                  style: TextStyle(
                    fontWeight: isExpanded ? FontWeight.bold : FontWeight.normal,
                    color: isExpanded ? Colors.blue : Colors.black87,
                  ),
                ),
                initiallyExpanded: isExpanded,
                onExpansionChanged: (expanded) {
                  if (expanded) {
                    setState(() {
                      _selectedCategory = category;
                      _selectedSubCategory = null;
                    });
                  }
                },
                children: subCategories.map((subCategory) {
                  final isSelected = _selectedSubCategory == subCategory;
                  return RadioListTile<String>(
                    title: Text(subCategory),
                    value: subCategory,
                    groupValue: _selectedSubCategory,
                    selected: isSelected,
                    activeColor: Colors.blue,
                    onChanged: (value) {
                      setState(() {
                        _selectedCategory = category;
                        _selectedSubCategory = value;
                      });
                    },
                  );
                }).toList(),
              ),
            ),
          );
        }),
      ],
    );
  }

  /// Step 2: 사업장 정보 입력 UI
  Widget _buildBusinessInfoForm() {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 16),
          
          // 안내 문구
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.green[50],
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline, color: Colors.green[700]),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '사업장 정보를 정확히 입력해주세요',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.green[900],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // ✅ 사업자등록번호 (필수)
          TextFormField(
            controller: _businessNumberController,
            decoration: InputDecoration(
              labelText: '사업자등록번호 *',
              hintText: '000-00-00000',
              prefixIcon: const Icon(Icons.business_center),
              helperText: '10자리 숫자를 입력해주세요',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              filled: true,
              fillColor: Colors.grey[50],
            ),
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9-]')),
              LengthLimitingTextInputFormatter(12), // 000-00-00000
            ],
            onChanged: (value) {
              // 자동 포맷팅
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

          // 사업장명 (필수)
          TextFormField(
            controller: _nameController,
            decoration: InputDecoration(
              labelText: '사업장명 *',
              hintText: '스타벅스 강남점',
              prefixIcon: const Icon(Icons.store),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              filled: true,
              fillColor: Colors.grey[50],
            ),
            validator: (value) {
              if (value == null || value.isEmpty) {
                return '사업장명을 입력해주세요';
              }
              if (value.length < 2) {
                return '사업장명은 2자 이상이어야 합니다';
              }
              return null;
            },
          ),
          const SizedBox(height: 16),

          // 주소 (필수)
          TextFormField(
            controller: _addressController,
            decoration: InputDecoration(
              labelText: '주소 *',
              hintText: '주소를 검색해주세요',
              prefixIcon: const Icon(Icons.location_on),
              suffixIcon: IconButton(
                icon: const Icon(Icons.search),
                onPressed: _searchAddress,
                tooltip: '주소 검색',
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              filled: true,
              fillColor: Colors.grey[50],
            ),
            readOnly: true,
            onTap: _searchAddress,
            validator: (value) {
              if (value == null || value.isEmpty) {
                return '주소를 입력해주세요';
              }
              return null;
            },
          ),
          const SizedBox(height: 8),
          
          // ✅ 좌표 정보 표시 (참고용)
          if (_latitude != null && _longitude != null)
            Padding(
              padding: const EdgeInsets.only(left: 12),
              child: Text(
                '📍 좌표: ${_latitude!.toStringAsFixed(6)}, ${_longitude!.toStringAsFixed(6)}',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                ),
              ),
            ),
          const SizedBox(height: 16),

          // 연락처 (선택)
          TextFormField(
            controller: _phoneController,
            decoration: InputDecoration(
              labelText: '연락처 (선택)',
              hintText: '010-1234-5678',
              prefixIcon: const Icon(Icons.phone),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              filled: true,
              fillColor: Colors.grey[50],
            ),
            keyboardType: TextInputType.phone,
          ),
          const SizedBox(height: 16),

          // 설명 (선택)
          TextFormField(
            controller: _descriptionController,
            decoration: InputDecoration(
              labelText: '설명 (선택)',
              hintText: '사업장에 대한 간단한 설명을 입력해주세요',
              prefixIcon: const Icon(Icons.description),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              filled: true,
              fillColor: Colors.grey[50],
            ),
            maxLines: 3,
            maxLength: 200,
          ),
        ],
      ),
    );
  }
}