import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import 'dart:io';

// Models
import '../../models/core/business_model.dart';
import '../../models/core/user_model.dart';

// Providers
import '../../providers/user_provider.dart';

// Services
import '../../services/firestore_service.dart';

// Utils
import '../../utils/responsive_helper.dart';
import '../../utils/toast_helper.dart';
import '../../utils/constants.dart';

// Widgets
import '../../widgets/common/common_widgets.dart';
import '../../widgets/inputs/daum_address_search.dart';

// Screen
import '../auth/register_screen.dart';
import '../auth/login_screen.dart';

/// 🏢 사업장 등록/수정 화면 (Stepper 방식)
class BusinessFormScreen extends StatefulWidget {
  final BusinessModel? business; // null이면 등록, 있으면 수정
  final bool isFromSignUp;
  

  const BusinessFormScreen({
    super.key,
    this.business,
    this.isFromSignUp = false,
  });

  @override
  State<BusinessFormScreen> createState() => _BusinessFormScreenState();
}

class _BusinessFormScreenState extends State<BusinessFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final FirestoreService _firestoreService = FirestoreService();

  bool _isLoading = false;
  bool _isEditMode = false;
  int _currentStep = 0;
  bool _autoValidate = false; 

  // Step 1: 업종 선택
  String? _selectedCategory;
  String? _selectedSubCategory;

  // Step 2: 기본 정보
  final _nameController = TextEditingController();
  final _businessNumberController = TextEditingController();
  final _displayNameController = TextEditingController();
  bool _useDisplayName = false;
  final _addressController = TextEditingController();
  final _detailAddressController = TextEditingController();
  final _phoneController = TextEditingController();
  double? _latitude;
  double? _longitude;

  // 이미지
  File? _mainImage;
  String? _mainImageUrl;

  // Step 3: 시설 및 환경
  final _oneLineIntroController = TextEditingController();
  final _detailedDescriptionController = TextEditingController();
  bool _parkingAvailable = false;
  String? _mealProvided = '없음';
  String? _uniformProvided = '없음';
  List<String> _selectedFacilities = [];

  // 추가 사진
  List<File> _additionalImages = [];
  List<String> _additionalImageUrls = [];

  // 교통편
  final _nearestStationController = TextEditingController();
  final _walkingMinutesController = TextEditingController();
  final _busInfoController = TextEditingController();

  // 기타
  final _precautionsController = TextEditingController();

  // 선택 옵션
  final List<String> _mealOptions = ['없음', '조식', '중식', '석식', '간식'];
  final List<String> _uniformOptions = ['없음', '유니폼 제공', '자유복', '정장'];
  final List<String> _facilityOptions = ['휴게실', '사물함', '탈의실', '샤워실', '흡연실'];

  @override
  void initState() {
    super.initState();
    _isEditMode = widget.business != null;

    if (_isEditMode) {
      _loadBusinessData();
    } else {
      _loadUserBusinessNumber();
    }
  }

  /// 회원가입 시 입력한 사업자번호 자동 완성
  void _loadUserBusinessNumber() {
    final userProvider = context.read<UserProvider>();
    final user = userProvider.currentUser;

    if (user?.businessNumber != null && user!.businessNumber!.isNotEmpty) {
      _businessNumberController.text = _formatBusinessNumber(user.businessNumber!);
    }
  }

  /// 기존 사업장 데이터 로드
  void _loadBusinessData() {
    final business = widget.business!;

    _selectedCategory = business.category;
    _selectedSubCategory = business.subCategory;

    _nameController.text = business.name;
    _businessNumberController.text = _formatBusinessNumber(business.businessNumber);
    _useDisplayName = business.useDisplayName;
    if (business.displayName != null) {
      _displayNameController.text = business.displayName!;
    }
    _addressController.text = business.address;
    _latitude = business.latitude;
    _longitude = business.longitude;

    if (business.phone != null) _phoneController.text = business.phone!;
    if (business.oneLineIntro != null) _oneLineIntroController.text = business.oneLineIntro!;
    if (business.detailedDescription != null) _detailedDescriptionController.text = business.detailedDescription!;
    if (business.nearestStation != null) _nearestStationController.text = business.nearestStation!;
    if (business.walkingMinutes != null) _walkingMinutesController.text = business.walkingMinutes.toString();
    if (business.busInfo != null) _busInfoController.text = business.busInfo!;
    if (business.precautions != null) _precautionsController.text = business.precautions!;

    _mainImageUrl = business.mainImageUrl;
    _additionalImageUrls = business.imageUrls ?? [];

    _parkingAvailable = business.parkingAvailable;
    _mealProvided = business.mealProvided ?? '없음';
    _uniformProvided = business.uniformProvided ?? '없음';
    _selectedFacilities = business.facilities ?? [];
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

  @override
  void dispose() {
    _nameController.dispose();
    _businessNumberController.dispose();
    _displayNameController.dispose();
    _addressController.dispose();
    _detailAddressController.dispose();
    _phoneController.dispose();
    _oneLineIntroController.dispose();
    _detailedDescriptionController.dispose();
    _nearestStationController.dispose();
    _walkingMinutesController.dispose();
    _busInfoController.dispose();
    _precautionsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return WillPopScope(
      onWillPop: () async {
        if (widget.isFromSignUp) {
          final confirmed = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('등록 취소'),
              content: const Text('사업장 등록을 취소하시겠습니까?\n로그인 화면으로 이동합니다.'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('아니오'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('예'),
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
          title: Text(_isEditMode ? '사업장 수정' : '사업장 등록'),
          automaticallyImplyLeading: !widget.isFromSignUp,  // ✅ 추가
        ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Theme(
              data: theme.copyWith(
                colorScheme: theme.colorScheme.copyWith(
                  primary: theme.primaryColor,
                ),
              ),
              child: Stepper(
                currentStep: _currentStep,
                onStepContinue: _onStepContinue,
                onStepCancel: _currentStep > 0 ? _onStepCancel : null,
                controlsBuilder: _buildStepperControls,
                steps: [
                  // Step 1: 업종 선택
                  Step(
                    title: Text(
                      '업종 선택',
                      style: ResponsiveHelper.subtitleStyle(context),
                    ),
                    content: _buildCategoryStep(context, theme),
                    isActive: _currentStep >= 0,
                    state: _currentStep > 0 ? StepState.complete : StepState.indexed,
                  ),

                  // Step 2: 기본 정보
                  Step(
                    title: Text(
                      '기본 정보',
                      style: ResponsiveHelper.subtitleStyle(context),
                    ),
                    content: _buildBasicInfoStep(context, theme),
                    isActive: _currentStep >= 1,
                    state: _currentStep > 1 ? StepState.complete : StepState.indexed,
                  ),

                  // Step 3: 상세 정보
                  Step(
                    title: Text(
                      '상세 정보',
                      style: ResponsiveHelper.subtitleStyle(context),
                    ),
                    content: _buildDetailStep(context, theme),
                    isActive: _currentStep >= 2,
                    state: _currentStep > 2 ? StepState.complete : StepState.indexed,
                  ),
                ],
              ),
            ),
      ),
    );
  }

  /// Stepper 컨트롤 버튼
  Widget _buildStepperControls(BuildContext context, ControlsDetails details) {
    final theme = Theme.of(context);
    final isLastStep = _currentStep == 2;

    return Padding(
      padding: EdgeInsets.only(top: ResponsiveHelper.spacing(context, 24)),
      child: Row(
        children: [
          // 이전 버튼
          if (_currentStep > 0) ...[
            SizedBox(width: ResponsiveHelper.spacing(context, 12)),
            Expanded(
              child: CommonWidgets.outlineButton(
                context: context,
                text: '이전',
                icon: Icons.arrow_back,
                onPressed: details.onStepCancel!,
              ),
            ),
          ],
          // 다음/완료 버튼
          Expanded(
            child: CommonWidgets.primaryButton(
              context: context,
              text: isLastStep ? '저장하기' : '다음',
              icon: isLastStep ? Icons.check : Icons.arrow_forward,
              onPressed: details.onStepContinue!,
              isLoading: _isLoading,
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // 📍 Step 1: 업종 선택
  // ============================================================

  Widget _buildCategoryStep(BuildContext context, ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CommonWidgets.infoCard(
          context: context,
          message: '사업장의 업종을 선택해주세요',
          icon: Icons.category,
          color: theme.primaryColor,
        ),
        SizedBox(height: ResponsiveHelper.spacing(context, 16)),

        // 업종 카테고리
        ...AppConstants.jobCategories.entries.map((entry) {
          return Container(
            margin: EdgeInsets.only(bottom: ResponsiveHelper.spacing(context, 8)),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: _selectedCategory == entry.key
                    ? theme.primaryColor
                    : Colors.grey[300]!,
                width: _selectedCategory == entry.key ? 2 : 1,
              ),
            ),
            child: ExpansionTile(
              title: Row(
                children: [
                  Icon(
                    _getCategoryIcon(entry.key),
                    color: _selectedCategory == entry.key
                        ? theme.primaryColor
                        : Colors.grey[600],
                    size: ResponsiveHelper.iconSize(context, 24),
                  ),
                  SizedBox(width: ResponsiveHelper.spacing(context, 12)),
                  Text(
                    entry.key,
                    style: ResponsiveHelper.bodyStyle(context).copyWith(
                      fontWeight: FontWeight.bold,
                      color: _selectedCategory == entry.key
                          ? theme.primaryColor
                          : Colors.black87,
                    ),
                  ),
                ],
              ),
              children: entry.value.map((subCategory) {
                final isSelected = _selectedSubCategory == subCategory;
                return Container(
                  margin: EdgeInsets.symmetric(
                    horizontal: ResponsiveHelper.spacing(context, 8),
                    vertical: ResponsiveHelper.spacing(context, 4),
                  ),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? theme.primaryColor.withOpacity(0.1)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: RadioListTile<String>(
                    title: Text(
                      subCategory,
                      style: ResponsiveHelper.bodyStyle(context).copyWith(
                        color: isSelected ? theme.primaryColor : Colors.black87,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                    value: subCategory,
                    groupValue: _selectedSubCategory,
                    activeColor: theme.primaryColor,
                    onChanged: (value) {
                      setState(() {
                        _selectedCategory = entry.key;
                        _selectedSubCategory = value;
                      });
                    },
                  ),
                );
              }).toList(),
            ),
          );
        }),

        SizedBox(height: ResponsiveHelper.spacing(context, 16)),
      ],
    );
  }

  IconData _getCategoryIcon(String category) {
    switch (category) {
      case '회사':
        return Icons.business;
      case '매장':
        return Icons.store;
      case '기타':
        return Icons.more_horiz;
      default:
        return Icons.category;
    }
  }

  // ============================================================
  // 📍 Step 2: 기본 정보
  // ============================================================

  Widget _buildBasicInfoStep(BuildContext context, ThemeData theme) {
    return Form(
        key: _formKey,
        autovalidateMode: _autoValidate 
            ? AutovalidateMode.onUserInteraction 
            : AutovalidateMode.disabled,  // ✅ 추가
        child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 대표 이미지
          CommonWidgets.sectionHeader(
            context: context,
            title: '대표 이미지',
            icon: Icons.image_outlined,
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 12)),
          _buildMainImagePicker(context, theme),

          SizedBox(height: ResponsiveHelper.spacing(context, 24)),

          // 사업장명
          CommonWidgets.sectionHeader(
            context: context,
            title: '사업장 정보',
            icon: Icons.business_outlined,
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 12)),

          CommonWidgets.textField(
            context: context,
            controller: _nameController,
            label: '사업장명 (정식 명칭)',
            hint: '예: OOO사업장',
            icon: Icons.business,
            validator: (value) {
              if (value == null || value.isEmpty) return '사업장명을 입력하세요';
              return null;
            },
          ),

          SizedBox(height: ResponsiveHelper.spacing(context, 16)),

          // 사업자번호
          TextFormField(
            controller: _businessNumberController,
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9-]')),
              LengthLimitingTextInputFormatter(12),
            ],
            style: ResponsiveHelper.bodyStyle(context),
            decoration: InputDecoration(
              labelText: '사업자등록번호',
              hintText: '000-00-00000',
              prefixIcon: Icon(Icons.badge, color: theme.primaryColor),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.grey[300]!),
              ),
            ),
            onChanged: (value) {
              final formatted = _formatBusinessNumber(value);
              if (formatted != value) {
                _businessNumberController.value = TextEditingValue(
                  text: formatted,
                  selection: TextSelection.collapsed(offset: formatted.length),
                );
              }
            },
            validator: (value) {
              if (value == null || value.isEmpty) return '사업자번호를 입력하세요';
              final cleaned = value.replaceAll('-', '');
              if (cleaned.length != 10) return '10자리를 입력하세요';
              return null;
            },
          ),

          SizedBox(height: ResponsiveHelper.spacing(context, 16)),

          // 공개 표시명 설정
          _buildDisplayNameSection(context, theme),

          SizedBox(height: ResponsiveHelper.spacing(context, 16)),

          // 주소
          CommonWidgets.textField(
            context: context,
            controller: _addressController,
            label: '주소',
            hint: '주소 검색 또는 직접 입력',
            icon: Icons.location_on,
            readOnly: false,
            onTap: () => _searchAddress(),
            validator: (value) {
              if (value == null || value.isEmpty) return '주소를 입력하세요';
              return null;
            },
          ),

          SizedBox(height: ResponsiveHelper.spacing(context, 16)),

          // 상세주소
          CommonWidgets.textField(
            context: context,
            controller: _detailAddressController,
            label: '상세주소',
            hint: '동/호수 등',
            icon: Icons.home,
          ),

          SizedBox(height: ResponsiveHelper.spacing(context, 16)),

          // 전화번호
          CommonWidgets.textField(
            context: context,
            controller: _phoneController,
            label: '연락처',
            hint: '02-1234-5678',
            icon: Icons.phone,
            keyboardType: TextInputType.phone,
          ),

          SizedBox(height: ResponsiveHelper.spacing(context, 16)),
        ],
      ),
    );
  }

  /// 대표 이미지 선택
  Widget _buildMainImagePicker(BuildContext context, ThemeData theme) {
    return GestureDetector(
      onTap: () => _pickMainImage(),
      child: Container(
        width: double.infinity,
        height: 180,
        decoration: BoxDecoration(
          color: Colors.grey[200],
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey[300]!),
          image: _mainImage != null
              ? DecorationImage(
                  image: FileImage(_mainImage!),
                  fit: BoxFit.cover,
                )
              : _mainImageUrl != null
                  ? DecorationImage(
                      image: NetworkImage(_mainImageUrl!),
                      fit: BoxFit.cover,
                    )
                  : null,
        ),
        child: _mainImage == null && _mainImageUrl == null
            ? Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.add_photo_alternate,
                    size: ResponsiveHelper.iconSize(context, 48),
                    color: Colors.grey[400],
                  ),
                  SizedBox(height: ResponsiveHelper.spacing(context, 8)),
                  Text(
                    '대표 이미지 추가 (선택)',
                    style: ResponsiveHelper.bodyStyle(context).copyWith(
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              )
            : null,
      ),
    );
  }

  /// 공개 표시명 섹션
  Widget _buildDisplayNameSection(BuildContext context, ThemeData theme) {
    return Container(
      padding: ResponsiveHelper.cardPadding(context),
      decoration: BoxDecoration(
        color: theme.primaryColor.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.primaryColor.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.info_outline,
                color: theme.primaryColor,
                size: ResponsiveHelper.iconSize(context, 20),
              ),
              SizedBox(width: ResponsiveHelper.spacing(context, 8)),
              Text(
                '공개 표시명 설정',
                style: ResponsiveHelper.subtitleStyle(context).copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 8)),
          Text(
            '공고에 회사명이나 브랜드명을 표시하고 싶다면 설정하세요.',
            style: ResponsiveHelper.smallStyle(context).copyWith(
              color: Colors.grey[700],
            ),
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 12)),

          CheckboxListTile(
            value: _useDisplayName,
            onChanged: (value) {
              setState(() => _useDisplayName = value ?? false);
            },
            title: Text(
              '공개 표시명 사용',
              style: ResponsiveHelper.bodyStyle(context),
            ),
            subtitle: Text(
              '예: 주식회사 OOO',
              style: ResponsiveHelper.smallStyle(context),
            ),
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            activeColor: theme.primaryColor,
          ),

          if (_useDisplayName) ...[
            SizedBox(height: ResponsiveHelper.spacing(context, 12)),
            CommonWidgets.textField(
              context: context,
              controller: _displayNameController,
              label: '공개 표시명',
              hint: '예: 주식회사 OOO',
              icon: Icons.storefront,
            ),
          ],
        ],
      ),
    );
  }

  // ============================================================
  // 📍 Step 3: 상세 정보
  // ============================================================

  Widget _buildDetailStep(BuildContext context, ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 한 줄 소개
        CommonWidgets.sectionHeader(
          context: context,
          title: '사업장 소개',
          icon: Icons.description_outlined,
        ),
        SizedBox(height: ResponsiveHelper.spacing(context, 12)),

        TextFormField(
          controller: _oneLineIntroController,
          maxLength: 50,
          style: ResponsiveHelper.bodyStyle(context),
          decoration: InputDecoration(
            labelText: '한 줄 소개',
            hintText: '예: 깔끔하고 체계적인 물류센터',
            prefixIcon: Icon(Icons.format_quote, color: theme.primaryColor),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),

        SizedBox(height: ResponsiveHelper.spacing(context, 16)),

        // 상세 소개
        TextFormField(
          controller: _detailedDescriptionController,
          maxLines: 4,
          maxLength: 500,
          style: ResponsiveHelper.bodyStyle(context),
          decoration: InputDecoration(
            labelText: '상세 소개 (선택)',
            hintText: '사업장에 대한 자세한 설명',
            alignLabelWithHint: true,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),

        SizedBox(height: ResponsiveHelper.spacing(context, 24)),

        // 시설 및 환경
        CommonWidgets.sectionHeader(
          context: context,
          title: '시설 및 환경',
          icon: Icons.check_circle_outline,
        ),
        SizedBox(height: ResponsiveHelper.spacing(context, 12)),

        _buildFacilitiesSection(context, theme),

        SizedBox(height: ResponsiveHelper.spacing(context, 24)),

        // 추가 사진
        CommonWidgets.sectionHeader(
          context: context,
          title: '사업장 사진 (최대 5장)',
          icon: Icons.photo_library_outlined,
        ),
        SizedBox(height: ResponsiveHelper.spacing(context, 12)),

        _buildAdditionalImagesSection(context, theme),

        SizedBox(height: ResponsiveHelper.spacing(context, 24)),

        // 교통편
        CommonWidgets.sectionHeader(
          context: context,
          title: '교통편 안내',
          icon: Icons.directions_transit,
        ),
        SizedBox(height: ResponsiveHelper.spacing(context, 12)),

        _buildTransportSection(context, theme),

        SizedBox(height: ResponsiveHelper.spacing(context, 24)),

        // 준비사항
        CommonWidgets.sectionHeader(
          context: context,
          title: '준비사항 / 주의사항',
          icon: Icons.warning_amber_outlined,
        ),
        SizedBox(height: ResponsiveHelper.spacing(context, 12)),

        TextFormField(
          controller: _precautionsController,
          maxLines: 3,
          maxLength: 300,
          style: ResponsiveHelper.bodyStyle(context),
          decoration: InputDecoration(
            labelText: '준비사항 (선택)',
            hintText: '예: 신분증 필수 지참, 편한 복장 권장',
            alignLabelWithHint: true,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),

        SizedBox(height: ResponsiveHelper.spacing(context, 16)),
      ],
    );
  }

  /// 시설 및 환경 섹션
  Widget _buildFacilitiesSection(BuildContext context, ThemeData theme) {
    return Container(
      padding: ResponsiveHelper.cardPadding(context),
      decoration: CommonWidgets.cardDecoration(),
      child: Column(
        children: [
          // 주차
          CheckboxListTile(
            value: _parkingAvailable,
            onChanged: (value) {
              setState(() => _parkingAvailable = value ?? false);
            },
            title: Text('주차 가능', style: ResponsiveHelper.bodyStyle(context)),
            secondary: Icon(Icons.local_parking, color: theme.primaryColor),
            controlAffinity: ListTileControlAffinity.leading,
            activeColor: theme.primaryColor,
          ),

          Divider(height: ResponsiveHelper.spacing(context, 16)),

          // 식사 제공
          _buildDropdownRow(
            context: context,
            label: '식사 제공',
            icon: Icons.restaurant,
            value: _mealProvided,
            items: _mealOptions,
            onChanged: (value) => setState(() => _mealProvided = value),
          ),

          Divider(height: ResponsiveHelper.spacing(context, 16)),

          // 복장
          _buildDropdownRow(
            context: context,
            label: '복장',
            icon: Icons.checkroom,
            value: _uniformProvided,
            items: _uniformOptions,
            onChanged: (value) => setState(() => _uniformProvided = value),
          ),

          Divider(height: ResponsiveHelper.spacing(context, 16)),

          // 편의시설
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.star_outline, color: Theme.of(context).primaryColor),
                  SizedBox(width: ResponsiveHelper.spacing(context, 12)),
                  Text(
                    '편의시설',
                    style: ResponsiveHelper.bodyStyle(context).copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              SizedBox(height: ResponsiveHelper.spacing(context, 12)),
              Wrap(
                spacing: ResponsiveHelper.spacing(context, 8),
                runSpacing: ResponsiveHelper.spacing(context, 8),
                children: _facilityOptions.map((facility) {
                  final isSelected = _selectedFacilities.contains(facility);
                  return FilterChip(
                    label: Text(facility),
                    selected: isSelected,
                    onSelected: (selected) {
                      setState(() {
                        if (selected) {
                          _selectedFacilities.add(facility);
                        } else {
                          _selectedFacilities.remove(facility);
                        }
                      });
                    },
                    selectedColor: Theme.of(context).primaryColor.withOpacity(0.2),
                    checkmarkColor: Theme.of(context).primaryColor,
                  );
                }).toList(),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 드롭다운 행
  Widget _buildDropdownRow({
    required BuildContext context,
    required String label,
    required IconData icon,
    required String? value,
    required List<String> items,
    required Function(String?) onChanged,
  }) {
    return Row(
      children: [
        Icon(icon, color: Theme.of(context).primaryColor),
        SizedBox(width: ResponsiveHelper.spacing(context, 12)),
        Expanded(
          child: Text(
            label,
            style: ResponsiveHelper.bodyStyle(context).copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        DropdownButton<String>(
          value: value,
          items: items.map((item) {
            return DropdownMenuItem(value: item, child: Text(item));
          }).toList(),
          onChanged: onChanged,
        ),
      ],
    );
  }

  /// 추가 사진 섹션
  Widget _buildAdditionalImagesSection(BuildContext context, ThemeData theme) {
    final totalImages = _additionalImages.length + _additionalImageUrls.length;

    return SizedBox(
      height: 100,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: totalImages + (totalImages < 5 ? 1 : 0),
        itemBuilder: (context, index) {
          if (index < _additionalImageUrls.length) {
            return _buildImageThumbnail(
              context,
              networkUrl: _additionalImageUrls[index],
              onRemove: () {
                setState(() => _additionalImageUrls.removeAt(index));
              },
            );
          }

          final fileIndex = index - _additionalImageUrls.length;
          if (fileIndex < _additionalImages.length) {
            return _buildImageThumbnail(
              context,
              file: _additionalImages[fileIndex],
              onRemove: () {
                setState(() => _additionalImages.removeAt(fileIndex));
              },
            );
          }

          return _buildAddImageButton(context);
        },
      ),
    );
  }

  Widget _buildImageThumbnail(
    BuildContext context, {
    File? file,
    String? networkUrl,
    required VoidCallback onRemove,
  }) {
    return Container(
      width: 100,
      margin: EdgeInsets.only(right: ResponsiveHelper.spacing(context, 12)),
      child: Stack(
        children: [
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              image: DecorationImage(
                image: file != null
                    ? FileImage(file) as ImageProvider
                    : NetworkImage(networkUrl!),
                fit: BoxFit.cover,
              ),
            ),
          ),
          Positioned(
            top: 4,
            right: 4,
            child: GestureDetector(
              onTap: onRemove,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: const BoxDecoration(
                  color: Colors.red,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.close, size: 16, color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAddImageButton(BuildContext context) {
    return GestureDetector(
      onTap: () => _pickAdditionalImage(),
      child: Container(
        width: 100,
        decoration: BoxDecoration(
          color: Colors.grey[200],
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey[400]!),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.add_photo_alternate,
              size: ResponsiveHelper.iconSize(context, 28),
              color: Colors.grey[600],
            ),
            SizedBox(height: ResponsiveHelper.spacing(context, 4)),
            Text(
              '추가',
              style: ResponsiveHelper.smallStyle(context).copyWith(
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 교통편 섹션
  Widget _buildTransportSection(BuildContext context, ThemeData theme) {
    return Container(
      padding: ResponsiveHelper.cardPadding(context),
      decoration: CommonWidgets.cardDecoration(),
      child: Column(
        children: [
          CommonWidgets.textField(
            context: context,
            controller: _nearestStationController,
            label: '가까운 역',
            hint: '예: 강남역 3번 출구',
            icon: Icons.subway,
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 16)),
          TextFormField(
            controller: _walkingMinutesController,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            style: ResponsiveHelper.bodyStyle(context),
            decoration: InputDecoration(
              labelText: '도보 시간 (분)',
              hintText: '5',
              prefixIcon: Icon(Icons.directions_walk, color: theme.primaryColor),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 16)),
          CommonWidgets.textField(
            context: context,
            controller: _busInfoController,
            label: '버스 정보',
            hint: '예: 146, 740',
            icon: Icons.directions_bus,
          ),
        ],
      ),
    );
  }

  // ============================================================
  // 🛠️ 기능 함수들
  // ============================================================

  void _onStepContinue() {
    if (_currentStep == 0) {
      if (_validateStep1()) {
        setState(() {
          _currentStep = 1;
          _autoValidate = false;  // ✅ 추가: 다음 스텝으로 이동 시 초기화
        });
      }
    } else if (_currentStep == 1) {
      if (_validateStep2()) {
        setState(() {
          _currentStep = 2;
          _autoValidate = false;  // ✅ 추가
        });
      }
    } else if (_currentStep == 2) {
      _saveBusiness();
    }
  }

  void _onStepCancel() {
    if (_currentStep > 0) {
      setState(() => _currentStep -= 1);
    }
  }

  bool _validateStep1() {
    if (_selectedCategory == null || _selectedSubCategory == null) {
      ToastHelper.showError('업종을 선택해주세요');
      setState(() => _autoValidate = true);
      return false;
    }
    return true;
  }

  bool _validateStep2() {
    setState(() => _autoValidate = true);
    if (!_formKey.currentState!.validate()) {
      return false;
    }
    if (_useDisplayName && _displayNameController.text.trim().isEmpty) {
      ToastHelper.showError('공개 표시명을 입력해주세요');
      return false;
    }
    return true;
  }

  Future<void> _pickMainImage() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1920,
      maxHeight: 1080,
      imageQuality: 85,
    );

    if (pickedFile != null) {
      setState(() => _mainImage = File(pickedFile.path));
    }
  }

  Future<void> _pickAdditionalImage() async {
    final totalImages = _additionalImages.length + _additionalImageUrls.length;

    if (totalImages >= 5) {
      ToastHelper.showError('최대 5장까지 추가할 수 있습니다');
      return;
    }

    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1920,
      maxHeight: 1080,
      imageQuality: 85,
    );

    if (pickedFile != null) {
      setState(() => _additionalImages.add(File(pickedFile.path)));
    }
  }

  Future<void> _searchAddress() async {
    try {
      final result = await DaumAddressService.searchAddress(context);

      if (result != null) {
        setState(() {
          _addressController.text = result.fullAddress;
          _latitude = result.latitude;
          _longitude = result.longitude;
        });
      }
    } catch (e) {
      print('⚠️ 주소 검색 실패, 수기 입력 모드: $e');
      _showManualAddressDialog();
    }
  }

  Future<void> _showManualAddressDialog() async {
    final addressController = TextEditingController();
    final latController = TextEditingController(text: '37.5665');
    final lngController = TextEditingController(text: '126.9780');

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('주소 입력 (테스트용)'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: addressController,
              decoration: const InputDecoration(
                labelText: '주소',
                hintText: '서울시 강남구 테헤란로 123',
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: latController,
                    decoration: const InputDecoration(labelText: '위도'),
                    keyboardType: TextInputType.number,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: lngController,
                    decoration: const InputDecoration(labelText: '경도'),
                    keyboardType: TextInputType.number,
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('확인'),
          ),
        ],
      ),
    );

    if (result == true && addressController.text.isNotEmpty) {
      setState(() {
        _addressController.text = addressController.text;
        _latitude = double.tryParse(latController.text) ?? 37.5665;
        _longitude = double.tryParse(lngController.text) ?? 126.9780;
      });
    }
  }

  Future<void> _saveBusiness() async {
    setState(() => _isLoading = true);

    try {
      final userProvider = context.read<UserProvider>();
      final ownerId = userProvider.currentUser?.uid;

      if (ownerId == null) {
        throw Exception('로그인이 필요합니다');
      }

      // 위도/경도 기본값
      _latitude ??= 37.5665;
      _longitude ??= 126.9780;

      // 이미지 업로드
      String? mainImageUrl = _mainImageUrl;
      if (_mainImage != null) {
        mainImageUrl = await _uploadImage(_mainImage!, 'main');
      }

      List<String> additionalUrls = List.from(_additionalImageUrls);
      for (var image in _additionalImages) {
        final url = await _uploadImage(image, 'additional');
        if (url != null) additionalUrls.add(url);
      }

      // 주소 조합
      String fullAddress = _addressController.text.trim();
      if (_detailAddressController.text.trim().isNotEmpty) {
        fullAddress += ', ${_detailAddressController.text.trim()}';
      }

      // Firestore 저장
      final businessData = {
        'name': _nameController.text.trim(),
        'businessNumber': _businessNumberController.text.replaceAll('-', ''),
        'displayName': _useDisplayName ? _displayNameController.text.trim() : null,
        'useDisplayName': _useDisplayName,
        'category': _selectedCategory,
        'subCategory': _selectedSubCategory,
        'address': fullAddress,
        'latitude': _latitude,
        'longitude': _longitude,
        'phone': _phoneController.text.trim().isEmpty ? null : _phoneController.text.trim(),
        'ownerId': ownerId,
        'isApproved': _isEditMode ? widget.business!.isApproved : false,
        'mainImageUrl': mainImageUrl,
        'imageUrls': additionalUrls,
        'oneLineIntro': _oneLineIntroController.text.trim().isEmpty ? null : _oneLineIntroController.text.trim(),
        'detailedDescription': _detailedDescriptionController.text.trim().isEmpty ? null : _detailedDescriptionController.text.trim(),
        'parkingAvailable': _parkingAvailable,
        'mealProvided': _mealProvided,
        'uniformProvided': _uniformProvided,
        'facilities': _selectedFacilities,
        'nearestStation': _nearestStationController.text.trim().isEmpty ? null : _nearestStationController.text.trim(),
        'walkingMinutes': _walkingMinutesController.text.trim().isEmpty ? null : int.tryParse(_walkingMinutesController.text.trim()),
        'busInfo': _busInfoController.text.trim().isEmpty ? null : _busInfoController.text.trim(),
        'precautions': _precautionsController.text.trim().isEmpty ? null : _precautionsController.text.trim(),
        'updatedAt': FieldValue.serverTimestamp(),
      };

      if (_isEditMode) {
        await FirebaseFirestore.instance
            .collection('businesses')
            .doc(widget.business!.id)
            .update(businessData);
        ToastHelper.showSuccess('사업장이 수정되었습니다');
      } else {
        businessData['createdAt'] = FieldValue.serverTimestamp();
        businessData['attendanceType'] = 'gps';
        businessData['gpsRadius'] = 100;
        await FirebaseFirestore.instance.collection('businesses').add(businessData);
        ToastHelper.showSuccess('사업장이 등록되었습니다\n관리자 승인 후 사용할 수 있습니다');
      }

      if (mounted) {
        if (widget.isFromSignUp) {
          // 회원가입 후 → 로그인 화면으로
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(builder: (context) => const LoginScreen()),
            (route) => false,
          );
        } else {
          // 일반 등록/수정 → 뒤로가기
          Navigator.pop(context, true);
        }
      }
    } catch (e) {
      print('❌ 사업장 저장 실패: $e');
      ToastHelper.showError('저장에 실패했습니다');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<String?> _uploadImage(File imageFile, String type) async {
    try {
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final fileName = '${type}_$timestamp.jpg';
      final ref = FirebaseStorage.instance.ref().child('businesses').child(fileName);

      await ref.putFile(imageFile);
      return await ref.getDownloadURL();
    } catch (e) {
      print('❌ 이미지 업로드 실패: $e');
      return null;
    }
  }
}