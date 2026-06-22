import 'package:ALfit/screens/common/document_management_screen.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import 'dart:io';

// Models
import '../../models/core/business_model.dart';
import '../../utils/beacon_helper.dart';

// Providers
import '../../providers/user_provider.dart';

// Helper
import '../../utils/image_helper.dart';
// Services
import '../../services/storage_service.dart';

// Utils
import '../../utils/responsive_helper.dart';
import '../../utils/toast_helper.dart';
import '../../utils/constants.dart';
import '../../utils/dialog_helper.dart';

// Widgets
import '../../widgets/common/common_widgets.dart';
import '../../widgets/common/loading_widget.dart';
import '../../widgets/inputs/daum_address_search.dart';

// Screen
import '../auth/login_screen.dart';
import '../../utils/navigation_helper.dart';
import '../../utils/format_helper.dart';
import '../../theme/app_colors.dart';
import '../../widgets/dialogs/styled_dialog.dart';
import '../../widgets/app_select_field.dart';
import '../../widgets/common/gradient_scaffold.dart';

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
  final _companyNameController = TextEditingController();
  final _addressController = TextEditingController();
  final _detailAddressController = TextEditingController();
  final _phoneController = TextEditingController();
  double? _latitude;
  double? _longitude;
  String? _city;      // 시/군/구 (예: 강남구, 수원시)
  String? _district;  // 법정읍면동 (예: 역삼동, 세교동)

  // 이미지
  File? _mainImage;
  String? _mainImageUrl;

  // 삭제할 이미지 URL 추적
  final List<String> _imagesToDelete = [];
  final StorageService _storageService = StorageService();

  // Step 3: 시설 및 환경
  final _oneLineIntroController = TextEditingController();
  final _detailedDescriptionController = TextEditingController();
  bool _parkingAvailable = false;
  List<String> _selectedMeals = [];
  String? _uniformProvided = '없음';
  List<String> _selectedFacilities = [];

  // 추가 사진
  final List<File> _additionalImages = [];
  List<String> _additionalImageUrls = [];

  // 교통편
  final _nearestStationController = TextEditingController();
  final _walkingMinutesController = TextEditingController();
  final _busInfoController = TextEditingController();

  // 기타
  final _precautionsController = TextEditingController();

  // 근로계약서 설정
  final _ownerNameController = TextEditingController();

  // 선택 옵션
  final List<String> _mealOptions = ['조식', '중식', '석식', '야식', '간식'];
  final List<String> _uniformOptions = ['없음', '유니폼 제공', '자유복', '정장'];
  final List<String> _facilityOptions = ['휴게실', '사물함', '탈의실', '샤워실', '흡연실'];

  // 출퇴근 설정
  String _attendanceType = 'gps';
  double _gpsRadius = 100;
  int _beaconRssiThreshold = -75; // dBm 기본값
  final _beaconUUIDController = TextEditingController();
  final _beaconMajorController = TextEditingController();
  final _beaconMinorController = TextEditingController();

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

  /// 회원가입 시 입력한 사업자번호/상호명 자동 완성
  void _loadUserBusinessNumber() {
    final user = context.read<UserProvider>().currentUser;
    // [특이사항] user가 null이면 자동완성 없이 종료 — 로그인 직후 provider 미초기화 시 발생 가능
    if (user == null) return;

    final bizNum = user.businessNumber;
    if (bizNum != null && bizNum.isNotEmpty) {
      _businessNumberController.text = FormatHelper.formatBusinessNumber(bizNum);
    }

    // 상호명 자동 완성
    final bizName = user.businessName;
    if (bizName != null && bizName.isNotEmpty) {
      _companyNameController.text = bizName;
    }

    // 대표자 성명: ceoName 우선 자동 완성
    final ceoName = user.ceoName;
    if (ceoName != null && ceoName.isNotEmpty) {
      _ownerNameController.text = ceoName;
    }
  }

  /// 기존 사업장 데이터 로드
  void _loadBusinessData() {
    final business = widget.business!;

    _selectedCategory = business.category;
    _selectedSubCategory = business.subCategory;

    _nameController.text = business.name;
    _companyNameController.text = business.companyName ?? '';
    _businessNumberController.text = FormatHelper.formatBusinessNumber(business.businessNumber);
    _addressController.text = business.address;
    if (business.detailAddress != null) {
      _detailAddressController.text = business.detailAddress!;
    }
    _latitude = business.latitude;
    _longitude = business.longitude;
    _city = business.city;
    _district = business.district;

    if (business.phone != null) _phoneController.text = business.phone!;
    if (business.oneLineIntro != null) _oneLineIntroController.text = business.oneLineIntro!;
    if (business.detailedDescription != null) _detailedDescriptionController.text = business.detailedDescription!;
    if (business.nearestStation != null) _nearestStationController.text = business.nearestStation!;
    if (business.walkingMinutes != null) _walkingMinutesController.text = business.walkingMinutes.toString();
    if (business.busInfo != null) _busInfoController.text = business.busInfo!;
    if (business.precautions != null) _precautionsController.text = business.precautions!;

    _mainImageUrl = business.mainImageUrl;
    _additionalImageUrls = business.imageUrls ?? [];

    if (business.ownerName != null) _ownerNameController.text = business.ownerName!;

    _parkingAvailable = business.parkingAvailable;
    _selectedMeals = business.mealsProvided ?? [];
    _uniformProvided = business.uniformProvided ?? '없음';
    _selectedFacilities = business.facilities ?? [];

    // 출퇴근 설정
    _attendanceType = business.attendanceType;
    _gpsRadius = business.gpsRadius.toDouble();
    _beaconRssiThreshold = business.beaconRssiThreshold;
    if (business.beaconUUID != null) _beaconUUIDController.text = business.beaconUUID!;
    if (business.beaconMajor != null) _beaconMajorController.text = business.beaconMajor.toString();
    if (business.beaconMinor != null) _beaconMinorController.text = business.beaconMinor.toString();
  }


  @override
  void dispose() {
    // [특이사항] TMP-01: 저장되지 않고 남은 임시 압축 파일 정리 (fire-and-forget)
    _mainImage?.delete().ignore();
    for (final file in _additionalImages) {
      file.delete().ignore();
    }
    _nameController.dispose();
    _businessNumberController.dispose();
    _companyNameController.dispose();
    _addressController.dispose();
    _detailAddressController.dispose();
    _phoneController.dispose();
    _oneLineIntroController.dispose();
    _detailedDescriptionController.dispose();
    _nearestStationController.dispose();
    _walkingMinutesController.dispose();
    _busInfoController.dispose();
    _precautionsController.dispose();
    _ownerNameController.dispose();
    _beaconUUIDController.dispose();
    _beaconMajorController.dispose();
    _beaconMinorController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return PopScope(
      canPop: !widget.isFromSignUp,
      onPopInvokedWithResult: (didPop, result) async {
        if (!didPop && widget.isFromSignUp) {
          final confirmed = await showDialog<bool>(
            context: context,
            builder: (context) => StyledDialog(
              title: '등록 취소',
              icon: Icons.exit_to_app,
              headerColor: AppColors.warning,
              content: const Text('사업장 등록을 취소하시겠습니까?\n로그인 화면으로 이동합니다.'),
              actions: [
                StyledDialogButton.cancel(
                  text: '아니오',
                  onPressed: () => Navigator.pop(context, false),
                ),
                StyledDialogButton.danger(
                  text: '예',
                  onPressed: () => Navigator.pop(context, true),
                ),
              ],
            ),
          );
          if (confirmed == true && context.mounted) {
            Navigator.pushAndRemoveUntil(
              context,
              MaterialPageRoute(builder: (context) => const LoginScreen()),
              (route) => false,
            );
          }
        }
      },
      child: GradientScaffold(
        title: _isEditMode ? '사업장 수정' : '사업장 등록',
        body: _isLoading
          ? const LoadingWidget()
          : Column(
              children: [
                _buildStepIndicator(context, theme),
                const Divider(height: 1, color: AppColors.grey100),
                Expanded(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.symmetric(
                      horizontal: ResponsiveHelper.spacing(context, 16),
                      vertical: ResponsiveHelper.spacing(context, 8),
                    ),
                    child: Column(
                      children: [
                        [
                          _buildCategoryStep(context, theme),
                          _buildBasicInfoStep(context, theme),
                          _buildDetailStep(context, theme),
                        ][_currentStep],
                        _buildNavigationButtons(context),
                      ],
                    ),
                  ),
                ),
              ],
            ),
      ),
    );
  }

  Widget _buildStepIndicator(BuildContext context, ThemeData theme) {
    const stepLabels = ['업종 선택', '기본 정보', '상세 정보'];
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 20),
        vertical: ResponsiveHelper.spacing(context, 14),
      ),
      child: Row(
        children: List.generate(stepLabels.length * 2 - 1, (i) {
          if (i.isOdd) {
            final isCompleted = i ~/ 2 < _currentStep;
            return Expanded(
              child: Container(
                height: 2,
                color: isCompleted ? theme.primaryColor : AppColors.grey200,
              ),
            );
          }
          final stepIndex = i ~/ 2;
          final isCompleted = stepIndex < _currentStep;
          final isCurrent = stepIndex == _currentStep;
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: isCompleted || isCurrent
                      ? theme.primaryColor
                      : AppColors.grey200,
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: isCompleted
                      ? const Icon(Icons.check, size: 14, color: Colors.white)
                      : Text(
                          '${stepIndex + 1}',
                          style: TextStyle(
                            color: isCurrent ? Colors.white : AppColors.grey500,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                ),
              ),
              SizedBox(height: ResponsiveHelper.spacing(context, 4)),
              Text(
                stepLabels[stepIndex],
                style: ResponsiveHelper.tinyStyle(context).copyWith(
                  color: isCurrent ? theme.primaryColor : AppColors.grey500,
                  fontWeight:
                      isCurrent ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ],
          );
        }),
      ),
    );
  }

  Widget _buildNavigationButtons(BuildContext context) {
    final isLastStep = _currentStep == 2;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        0,
        ResponsiveHelper.spacing(context, 16),
        0,
        ResponsiveHelper.spacing(context, 8),
      ),
      child: Row(
        children: [
          if (_currentStep > 0) ...[
            Expanded(
              child: CommonWidgets.outlineButton(
                context: context,
                text: '이전',
                icon: Icons.arrow_back,
                onPressed: _onStepCancel,
              ),
            ),
            SizedBox(width: ResponsiveHelper.spacing(context, 12)),
          ],
          Expanded(
            child: CommonWidgets.primaryButton(
              context: context,
              text: isLastStep ? '저장하기' : '다음',
              icon: isLastStep ? Icons.check : Icons.arrow_forward,
              onPressed: _onStepContinue,
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
                    : AppColors.grey300,
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
                        : AppColors.grey600,
                    size: ResponsiveHelper.iconSize(context, 24),
                  ),
                  SizedBox(width: ResponsiveHelper.spacing(context, 12)),
                  Text(
                    entry.key,
                    style: ResponsiveHelper.bodyStyle(context).copyWith(
                      fontWeight: FontWeight.bold,
                      color: _selectedCategory == entry.key
                          ? theme.primaryColor
                          : AppColors.grey800,
                    ),
                  ),
                ],
              ),
              children: [
              RadioGroup<String>(
                groupValue: _selectedSubCategory,
                onChanged: (value) {
                  setState(() {
                    _selectedCategory = entry.key;
                    _selectedSubCategory = value;
                  });
                },
                child: Column(
                  children: entry.value.map((subCategory) {
                    final isSelected = _selectedSubCategory == subCategory;
                    return Container(
                      margin: EdgeInsets.symmetric(
                        horizontal: ResponsiveHelper.spacing(context, 8),
                        vertical: ResponsiveHelper.spacing(context, 4),
                      ),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? theme.primaryColor.withValues(alpha: 0.1)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: RadioListTile<String>(
                        title: Text(
                          subCategory,
                          style: ResponsiveHelper.bodyStyle(context).copyWith(
                            color: isSelected ? theme.primaryColor : AppColors.grey800,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                        value: subCategory,
                        activeColor: theme.primaryColor,
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],
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
            : AutovalidateMode.disabled,
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
            // D01: 빈 문자열(공백 포함) 저장 방어 — trim() 후 검사
            validator: (value) {
              if (value == null || value.trim().isEmpty) return '사업장명을 입력하세요';
              if (value.trim().length > 100) return '사업장명은 100자 이하로 입력해주세요';
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
                borderSide: BorderSide(color: AppColors.grey300),
              ),
            ),
            onChanged: (value) {
              final formatted = FormatHelper.formatBusinessNumber(value);
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
          CommonWidgets.textField(
            context: context,
            controller: _companyNameController,
            label: '상호명 (법적 회사명)',
            hint: '예: (주)홍길동물류',
            icon: Icons.store,
            // D01: 공백만 입력 시 저장 방어
            validator: (value) {
              if (value == null || value.trim().isEmpty) return '상호명을 입력하세요';
              if (value.trim().length > 100) return '상호명은 100자 이하로 입력해주세요';
              return null;
            },
          ),

          SizedBox(height: ResponsiveHelper.spacing(context, 16)),

          // 대표자 성명
          CommonWidgets.textField(
            context: context,
            controller: _ownerNameController,
            label: '대표자 성명',
            hint: '예: 홍길동',
            icon: Icons.person_outline,
          ),

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

          // GPS 상태 칩
          if (_addressController.text.isNotEmpty)
            Padding(
              padding: EdgeInsets.only(top: ResponsiveHelper.spacing(context, 6)),
              child: GestureDetector(
                onTap: _latitude == null ? _searchAddress : null,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _latitude != null ? Icons.gps_fixed : Icons.gps_not_fixed,
                      size: 14,
                      color: _latitude != null ? AppColors.success : AppColors.warning,
                    ),
                    SizedBox(width: ResponsiveHelper.spacing(context, 4)),
                    Text(
                      _latitude != null
                          ? 'GPS 위치 확인됨'
                          : 'GPS 위치 미확인 — 탭하여 주소 재검색',
                      style: ResponsiveHelper.tinyStyle(
                        context,
                        color: _latitude != null ? AppColors.success : AppColors.warning,
                      ),
                    ),
                    if (_latitude == null) ...[
                      SizedBox(width: ResponsiveHelper.spacing(context, 4)),
                      Icon(Icons.refresh, size: 12, color: AppColors.warning),
                    ],
                  ],
                ),
              ),
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
            validator: (v) {
              if (v != null && v.isNotEmpty &&
                  !RegExp(r'^[\d\-\+\(\)\s]+$').hasMatch(v)) {
                return '숫자, 하이픈(-), 공백만 입력 가능합니다';
              }
              return null;
            },
          ),

          SizedBox(height: ResponsiveHelper.spacing(context, 16)),
        ],
      ),
    );
  }

  /// 대표 이미지 선택
  Widget _buildMainImagePicker(BuildContext context, ThemeData theme) {
    final hasImage = _mainImage != null || _mainImageUrl != null;
    
    return Stack(
      children: [
        GestureDetector(
          onTap: () => _pickMainImage(),
          child: Container(
            width: double.infinity,
            height: 180,
            decoration: BoxDecoration(
              color: AppColors.grey200,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.grey300),
              image: _mainImage != null
                  ? DecorationImage(
                      image: kIsWeb
                          ? NetworkImage(_mainImage!.path) as ImageProvider
                          : FileImage(_mainImage!),
                      fit: BoxFit.cover,
                    )
                  : _mainImageUrl != null
                      ? DecorationImage(
                          image: NetworkImage(_mainImageUrl!),
                          fit: BoxFit.cover,
                        )
                      : null,
            ),
            child: !hasImage
                ? Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.add_photo_alternate,
                        size: ResponsiveHelper.iconSize(context, 48),
                        color: AppColors.grey400,
                      ),
                      SizedBox(height: ResponsiveHelper.spacing(context, 8)),
                      Text(
                        '대표 이미지 추가 (선택)',
                        style: ResponsiveHelper.bodyStyle(context).copyWith(
                          color: AppColors.grey600,
                        ),
                      ),
                    ],
                  )
                : null,
          ),
        ),
        // 삭제 버튼 (이미지가 있을 때만 표시)
        if (hasImage)
          Positioned(
            top: ResponsiveHelper.spacing(context, 8),
            right: ResponsiveHelper.spacing(context, 8),
            child: GestureDetector(
              onTap: () {
                // [특이사항] TMP-01: 선택 취소된 임시 압축 파일 즉시 정리 (fire-and-forget)
                _mainImage?.delete().ignore();
                setState(() {
                  _mainImage = null;
                  // 기존 URL 삭제 목록에 추가
                  if (_mainImageUrl != null) {
                    _imagesToDelete.add(_mainImageUrl!);
                  }
                  _mainImageUrl = null;
                });
              },
              child: Container(
                padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 6)),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.6),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.close,
                  color: Colors.white,
                  size: ResponsiveHelper.iconSize(context, 20),
                ),
              ),
            ),
          ),
      ],
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

        SizedBox(height: ResponsiveHelper.spacing(context, 24)),

        // 출퇴근 설정
        CommonWidgets.sectionHeader(
          context: context,
          title: '출퇴근 방식',
          icon: Icons.location_on_outlined,
        ),
        SizedBox(height: ResponsiveHelper.spacing(context, 8)),
        Text(
          '근로자가 출퇴근 체크 시 사용할 방식을 선택하세요.',
          style: ResponsiveHelper.smallStyle(context, color: AppColors.grey600),
        ),
        SizedBox(height: ResponsiveHelper.spacing(context, 12)),
        _buildAttendanceSection(context, theme),

        SizedBox(height: ResponsiveHelper.spacing(context, 16)),
      ],
    );
  }

  /// 출퇴근 방식 섹션
  Widget _buildAttendanceSection(BuildContext context, ThemeData theme) {
    return Column(
      children: [
        // ── 방식 선택 카드들 ───────────────────────────────────────
        Row(
          children: [
            _attendanceTypeCard(
              context, theme,
              type: 'gps',
              icon: Icons.gps_fixed,
              label: 'GPS',
              desc: '반경 내 위치 확인',
            ),
            SizedBox(width: ResponsiveHelper.spacing(context, 10)),
            _attendanceTypeCard(
              context, theme,
              type: 'beacon',
              icon: Icons.bluetooth,
              label: '비콘',
              desc: 'BLE 기기 신호 감지',
            ),
            SizedBox(width: ResponsiveHelper.spacing(context, 10)),
            _attendanceTypeCard(
              context, theme,
              type: 'both',
              icon: Icons.tune,
              label: '병행',
              desc: 'GPS + 비콘',
            ),
          ],
        ),

        SizedBox(height: ResponsiveHelper.spacing(context, 16)),

        // ── GPS 반경 설정 ──────────────────────────────────────────
        if (_attendanceType == 'gps' || _attendanceType == 'both') ...[
          Container(
            padding: ResponsiveHelper.cardPadding(context),
            decoration: CommonWidgets.cardDecoration(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.radar,
                        size: ResponsiveHelper.iconSize(context, 18),
                        color: theme.primaryColor),
                    SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                    Text('GPS 허용 반경',
                        style: ResponsiveHelper.bodyStyle(context)
                            .copyWith(fontWeight: FontWeight.bold)),
                    const Spacer(),
                    Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: ResponsiveHelper.spacing(context, 10),
                        vertical: ResponsiveHelper.spacing(context, 4),
                      ),
                      decoration: BoxDecoration(
                        color: theme.primaryColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '${_gpsRadius.toInt()}m',
                        style: ResponsiveHelper.bodyStyle(context,
                            color: theme.primaryColor)
                            .copyWith(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: ResponsiveHelper.spacing(context, 4)),
                Text(
                  '사업장 위치에서 이 거리 이내여야 출퇴근 가능합니다.',
                  style: ResponsiveHelper.smallStyle(context, color: AppColors.grey500),
                ),
                Slider(
                  value: _gpsRadius,
                  min: 30,
                  max: 500,
                  divisions: 47,
                  activeColor: theme.primaryColor,
                  label: '${_gpsRadius.toInt()}m',
                  onChanged: (v) => setState(() => _gpsRadius = v),
                ),
                // 눈금 힌트
                Padding(
                  padding: EdgeInsets.symmetric(
                      horizontal: ResponsiveHelper.spacing(context, 8)),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('30m', style: ResponsiveHelper.tinyStyle(context, color: AppColors.grey400)),
                      Text('100m', style: ResponsiveHelper.tinyStyle(context, color: AppColors.grey400)),
                      Text('500m', style: ResponsiveHelper.tinyStyle(context, color: AppColors.grey400)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 12)),
        ],

        // ── 비콘 설정 ──────────────────────────────────────────────
        if (_attendanceType == 'beacon' || _attendanceType == 'both') ...[
          Container(
            padding: ResponsiveHelper.cardPadding(context),
            decoration: CommonWidgets.cardDecoration(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.bluetooth,
                        size: ResponsiveHelper.iconSize(context, 18),
                        color: AppColors.info),
                    SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                    Text('비콘 정보',
                        style: ResponsiveHelper.bodyStyle(context)
                            .copyWith(fontWeight: FontWeight.bold)),
                  ],
                ),
                SizedBox(height: ResponsiveHelper.spacing(context, 4)),
                Text(
                  '사업장에 설치된 iBeacon/Eddystone 기기 정보를 입력하세요.',
                  style: ResponsiveHelper.smallStyle(context, color: AppColors.grey500),
                ),
                SizedBox(height: ResponsiveHelper.spacing(context, 16)),

                // UUID
                TextFormField(
                  controller: _beaconUUIDController,
                  style: ResponsiveHelper.bodyStyle(context),
                  decoration: InputDecoration(
                    labelText: 'Beacon UUID *',
                    hintText: 'E2C56DB5-DFFB-48D2-B060-D0F5A71096E0',
                    prefixIcon: Icon(Icons.vpn_key_outlined, color: AppColors.info),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    helperText: '비콘 기기의 UUID를 대문자로 입력하세요.',
                  ),
                  textCapitalization: TextCapitalization.characters,
                  validator: (_attendanceType == 'beacon' || _attendanceType == 'both')
                      ? (v) {
                          if (v == null || v.isEmpty) return 'UUID를 입력해주세요';
                          final uuidRegex = RegExp(
                            r'^[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}$',
                          );
                          if (!uuidRegex.hasMatch(v.toUpperCase())) {
                            return 'UUID 형식이 올바르지 않습니다\n(예: XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX)';
                          }
                          return null;
                        }
                      : null,
                ),
                SizedBox(height: ResponsiveHelper.spacing(context, 12)),

                // Major / Minor (선택)
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _beaconMajorController,
                        style: ResponsiveHelper.bodyStyle(context),
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: 'Major (선택)',
                          hintText: '0~65535',
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                    SizedBox(width: ResponsiveHelper.spacing(context, 12)),
                    Expanded(
                      child: TextFormField(
                        controller: _beaconMinorController,
                        style: ResponsiveHelper.bodyStyle(context),
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: 'Minor (선택)',
                          hintText: '0~65535',
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: ResponsiveHelper.spacing(context, 8)),
                Container(
                  padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 10)),
                  decoration: BoxDecoration(
                    color: AppColors.infoBg,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline,
                          size: ResponsiveHelper.iconSize(context, 16),
                          color: AppColors.infoDark),
                      SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                      Expanded(
                        child: Text(
                          'Major/Minor를 설정하면 해당 비콘만 인식합니다. '
                          '비워두면 UUID만으로 매칭합니다.',
                          style: ResponsiveHelper.tinyStyle(context,
                              color: AppColors.infoDark),
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: ResponsiveHelper.spacing(context, 16)),

                // 인식 거리 (RSSI 임계값)
                Row(
                  children: [
                    Icon(Icons.signal_wifi_4_bar,
                        size: ResponsiveHelper.iconSize(context, 18),
                        color: AppColors.info),
                    SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                    Text('인식 거리',
                        style: ResponsiveHelper.bodyStyle(context)
                            .copyWith(fontWeight: FontWeight.bold)),
                    const Spacer(),
                    Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: ResponsiveHelper.spacing(context, 10),
                        vertical: ResponsiveHelper.spacing(context, 4),
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.info.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        BeaconHelper.proximityLabel(_beaconRssiThreshold),
                        style: ResponsiveHelper.smallStyle(context,
                            color: AppColors.infoDark,
                            fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
                Slider(
                  value: _beaconRssiThreshold.toDouble(),
                  min: -90,
                  max: -50,
                  divisions: 8,
                  activeColor: AppColors.info,
                  label: '${_beaconRssiThreshold}dBm',
                  onChanged: (v) =>
                      setState(() => _beaconRssiThreshold = v.toInt()),
                ),
                Padding(
                  padding: EdgeInsets.symmetric(
                      horizontal: ResponsiveHelper.spacing(context, 8)),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('멀리(~10m)', style: ResponsiveHelper.tinyStyle(context, color: AppColors.grey400)),
                      Text('보통(~5m)', style: ResponsiveHelper.tinyStyle(context, color: AppColors.grey400)),
                      Text('가까이(~1m)', style: ResponsiveHelper.tinyStyle(context, color: AppColors.grey400)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  /// 출퇴근 방식 선택 카드
  Widget _attendanceTypeCard(
    BuildContext context,
    ThemeData theme, {
    required String type,
    required IconData icon,
    required String label,
    required String desc,
  }) {
    final isSelected = _attendanceType == type;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _attendanceType = type),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: EdgeInsets.symmetric(
            horizontal: ResponsiveHelper.spacing(context, 8),
            vertical: ResponsiveHelper.spacing(context, 12),
          ),
          decoration: BoxDecoration(
            color: isSelected
                ? theme.primaryColor.withValues(alpha: 0.08)
                : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected ? theme.primaryColor : AppColors.grey300,
              width: isSelected ? 2.0 : 1.0,
            ),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: theme.primaryColor.withValues(alpha: 0.12),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    )
                  ]
                : null,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: ResponsiveHelper.iconSize(context, 24),
                color: isSelected ? theme.primaryColor : AppColors.grey500,
              ),
              SizedBox(height: ResponsiveHelper.spacing(context, 6)),
              Text(
                label,
                style: ResponsiveHelper.smallStyle(context,
                    color: isSelected ? theme.primaryColor : AppColors.grey700,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal),
              ),
              SizedBox(height: ResponsiveHelper.spacing(context, 2)),
              Text(
                desc,
                style: ResponsiveHelper.tinyStyle(context,
                    color: isSelected ? theme.primaryColor : AppColors.grey400),
                textAlign: TextAlign.center,
                maxLines: 2,
              ),
            ],
          ),
        ),
      ),
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
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.restaurant, color: Theme.of(context).primaryColor),
                  SizedBox(width: ResponsiveHelper.spacing(context, 12)),
                  Text(
                    '식사 제공',
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
                children: _mealOptions.map((meal) {
                final isSelected = _selectedMeals.contains(meal);
                final theme = Theme.of(context);
                
                return FilterChip(
                  label: Text(meal),
                  selected: isSelected,
                  onSelected: (selected) {
                    setState(() {
                      if (selected) {
                        _selectedMeals.add(meal);
                      } else {
                        _selectedMeals.remove(meal);
                      }
                    });
                  },
                  backgroundColor: theme.colorScheme.surfaceContainerHighest,  // 선택 안 된 것
                  selectedColor: theme.primaryColor,  // 선택된 것
                  checkmarkColor: theme.colorScheme.onPrimary,  // 체크마크 (흰색)
                  labelStyle: ResponsiveHelper.bodyStyle(context).copyWith(
                    color: isSelected 
                        ? theme.colorScheme.onPrimary  // 선택 시 흰색
                        : theme.textTheme.bodyMedium?.color,  // 기본 텍스트 색
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  ),
                  side: BorderSide(
                    color: isSelected 
                        ? theme.primaryColor 
                        : theme.dividerColor,
                    width: isSelected ? 2 : 1,
                  ),
                  elevation: isSelected ? 2 : 0,
                  shadowColor: theme.primaryColor.withValues(alpha: 0.3),
                );
              }).toList(),
              ),
            ],
          ),

          Divider(height: ResponsiveHelper.spacing(context, 16)),

          // 복장
          Row(
            children: [
              Icon(Icons.checkroom, color: Theme.of(context).primaryColor),
              SizedBox(width: ResponsiveHelper.spacing(context, 12)),
              Text(
                '복장',
                style: ResponsiveHelper.bodyStyle(context).copyWith(fontWeight: FontWeight.bold),
              ),
            ],
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 8)),
          AppSelectField<String>(
            value: _uniformProvided,
            hintText: '복장을 선택하세요',
            sheetTitle: '복장 선택',
            items: _uniformOptions,
            labelOf: (v) => v,
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
                  final theme = Theme.of(context);
                  
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
                      backgroundColor: theme.colorScheme.surfaceContainerHighest,  // 선택 안 된 것
                    selectedColor: theme.primaryColor,  // 선택된 것
                    checkmarkColor: theme.colorScheme.onPrimary,  // 체크마크 (흰색)
                    labelStyle: ResponsiveHelper.bodyStyle(context).copyWith(
                      color: isSelected 
                          ? theme.colorScheme.onPrimary  // 선택 시 흰색
                          : theme.textTheme.bodyMedium?.color,  // 기본 텍스트 색
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    ),
                    side: BorderSide(
                      color: isSelected 
                          ? theme.primaryColor 
                          : theme.dividerColor,
                      width: isSelected ? 2 : 1,
                    ),
                    elevation: isSelected ? 2 : 0,
                    shadowColor: theme.primaryColor.withValues(alpha: 0.3),
                  );
                }).toList(),
              ),
            ],
          ),
        ],
      ),
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
                setState(() {
                  _imagesToDelete.add(_additionalImageUrls[index]);
                  _additionalImageUrls.removeAt(index);
                });
              },
            );
          }

          final fileIndex = index - _additionalImageUrls.length;
          if (fileIndex < _additionalImages.length) {
            return _buildImageThumbnail(
              context,
              file: _additionalImages[fileIndex],
              onRemove: () {
                // [특이사항] TMP-01: 선택 취소된 임시 압축 파일 즉시 정리 (fire-and-forget)
                _additionalImages[fileIndex].delete().ignore();
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
                    ? (kIsWeb ? NetworkImage(file.path) as ImageProvider : FileImage(file))
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
                  color: AppColors.error,
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
      onTap: () => _pickAdditionalImages(),
      child: Container(
        width: 100,
        decoration: BoxDecoration(
          color: AppColors.grey200,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.grey400),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.add_photo_alternate,
              size: ResponsiveHelper.iconSize(context, 28),
              color: AppColors.grey600,
            ),
            SizedBox(height: ResponsiveHelper.spacing(context, 4)),
            Text(
              '사진 추가',
              style: ResponsiveHelper.tinyStyle(context).copyWith(
                color: AppColors.grey600,
              ),
            ),
            Text(
              '(복수선택)',
              style: ResponsiveHelper.tinyStyle(context, color: AppColors.grey500),
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
          _autoValidate = false;
        });
      }
    } else if (_currentStep == 1) {
      if (_validateStep2()) {
        setState(() {
          _currentStep = 2;
          _autoValidate = false;
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
    if (!(_formKey.currentState?.validate() ?? false)) {
      return false;
    }
    return true;
  }

  Future<void> _pickMainImage() async {
    final image = await ImageHelper.pickAndCompressImage(
      context,
      type: ImageType.general,
      useBottomSheet: true,
    );

    if (!mounted || image == null) return;
    setState(() => _mainImage = image);
  }

  Future<void> _pickAdditionalImages() async {
    final totalImages = _additionalImages.length + _additionalImageUrls.length;

    if (totalImages >= 5) {
      ToastHelper.showError('최대 5장까지 추가할 수 있습니다');
      return;
    }

    final images = await ImageHelper.pickAndCompressMultipleImages(
      context,
      maxImages: 5,
      currentCount: totalImages,
      type: ImageType.general,
    );

    if (!mounted || images.isEmpty) return;
    setState(() => _additionalImages.addAll(images));
  }

  Future<void> _searchAddress() async {
    try {
      final result = await DaumAddressService.searchAddress(context);

      if (result != null) {
        setState(() {
          _addressController.text = result.fullAddress;
          _latitude = result.latitude;
          _longitude = result.longitude;
          _city = result.sigungu?.isNotEmpty == true
              ? result.sigungu
              : FormatHelper.parseAddressCity(result.fullAddress);
          _district = result.bname?.isNotEmpty == true
              ? result.bname
              : FormatHelper.parseAddressDistrict(result.fullAddress);
        });
        debugPrint('📍 [주소검색] 위도: ${result.latitude} / 경도: ${result.longitude}');
      }
    } catch (e) {
      debugPrint('⚠️ 주소 검색 실패, 수기 입력 모드: $e');
      _showManualAddressDialog();
    }
  }

  Future<void> _showManualAddressDialog() async {
    final addressController = TextEditingController();
    final latController = TextEditingController(text: '37.5665');
    final lngController = TextEditingController(text: '126.9780');

    try {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => StyledDialog(
        title: '주소 직접 입력',
        icon: Icons.location_on,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        content: SingleChildScrollView(
          child: Column(
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
        ),
        actions: [
          StyledDialogButton.cancel(
            onPressed: () => Navigator.pop(context, false),
          ),
          StyledDialogButton.primary(
            text: '확인',
            onPressed: () => Navigator.pop(context, true),
          ),
        ],
      ),
    );

    if (mounted && result == true && addressController.text.isNotEmpty) {
      setState(() {
        _addressController.text = addressController.text;
        _latitude = double.tryParse(latController.text);
        _longitude = double.tryParse(lngController.text);
      });
    }
    } finally {
      addressController.dispose();
      latController.dispose();
      lngController.dispose();
    }
  }

  Future<void> _saveBusiness() async {
    if (_isLoading) return;
    setState(() => _isLoading = true);

    // catch 블록에서 orphan Storage 정리를 위해 try 밖에서 선언
    final newlyUploadedUrls = <String>[];
    try {
      // 사업자등록증 체크 (Firestore에서 최신 데이터 기준)
      final userProvider = context.read<UserProvider>();

      // 최신 사용자 정보 가져오기 (캐시 무시)
      await userProvider.refreshCurrentUser();

      if (!mounted) return;

      final user = userProvider.currentUser;

      if (user == null) {
        ToastHelper.showError('로그인이 필요합니다.');
        return;
      }

      // 사업자등록증 미등록 시 다이얼로그
      if (user.businessLicenseImageUrl == null) {
        final shouldNavigate = await DialogHelper.showDocumentRequired(
          context,
          title: '사업자등록증 등록 필요',
          missingDocuments: ['사업자등록증'],
        );

        if (shouldNavigate && mounted) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => const DocumentManagementScreen(),
            ),
          );
        }
        return;
      }

      final ownerId = user.uid;

      debugPrint('📍 [저장] 위도: $_latitude / 경도: $_longitude');

      // CLAUDE.md 삭제 순서 규칙:
      // Storage 삭제는 Firestore 업데이트 성공 후에만 수행한다.
      // 이 시점에서는 새 이미지 업로드만 먼저 진행한다.

      // 이미지 업로드
      String? mainImageUrl = _mainImageUrl;
      if (_mainImage != null) {
        mainImageUrl = await _uploadImage(_mainImage!, 'main');
        if (mainImageUrl != null) newlyUploadedUrls.add(mainImageUrl);
        if (!mounted) {
          if (newlyUploadedUrls.isNotEmpty) await _storageService.deleteMultipleByUrls(newlyUploadedUrls);
          return;
        }
        if (mainImageUrl == null) {
          debugPrint('⚠️ 대표 이미지 업로드 실패 — 이미지 없이 저장');
          ToastHelper.showWarning('이미지 업로드에 실패했습니다. 이미지 없이 저장됩니다.');
        }
      }

      List<String> additionalUrls = List.from(_additionalImageUrls);
      for (var image in _additionalImages) {
        final url = await _uploadImage(image, 'additional');
        if (url != null) newlyUploadedUrls.add(url);
        if (!mounted) {
          if (newlyUploadedUrls.isNotEmpty) await _storageService.deleteMultipleByUrls(newlyUploadedUrls);
          return;
        }
        if (url != null) additionalUrls.add(url);
      }

      final businessData = {
        'name': _nameController.text.trim(),
        'businessNumber': _businessNumberController.text.replaceAll('-', ''),
        'companyName': _companyNameController.text.trim(),
        'category': _selectedCategory,
        'subCategory': _selectedSubCategory,
        'address': _addressController.text.trim(),
        'detailAddress': _detailAddressController.text.trim().isEmpty ? null : _detailAddressController.text.trim(),
        'city': _city ?? FormatHelper.parseAddressCity(_addressController.text.trim()),
        'district': _district ?? FormatHelper.parseAddressDistrict(_addressController.text.trim()),
        'latitude': _latitude,
        'longitude': _longitude,
        'phone': _phoneController.text.trim().isEmpty ? null : _phoneController.text.trim(),
        'ownerId': ownerId,
        // [특이사항] _isEditMode = (widget.business != null) — 이 블록 내 widget.business! 는 항상 안전
        'isApproved': _isEditMode ? widget.business!.isApproved : true,
        'mainImageUrl': mainImageUrl,
        'imageUrls': additionalUrls,
        'oneLineIntro': _oneLineIntroController.text.trim().isEmpty ? null : _oneLineIntroController.text.trim(),
        'detailedDescription': _detailedDescriptionController.text.trim().isEmpty ? null : _detailedDescriptionController.text.trim(),
        'parkingAvailable': _parkingAvailable,
        'mealsProvided': _selectedMeals.isEmpty ? null : _selectedMeals,
        'uniformProvided': _uniformProvided,
        'facilities': _selectedFacilities,
        'nearestStation': _nearestStationController.text.trim().isEmpty ? null : _nearestStationController.text.trim(),
        'walkingMinutes': _walkingMinutesController.text.trim().isEmpty ? null : int.tryParse(_walkingMinutesController.text.trim()),
        'busInfo': _busInfoController.text.trim().isEmpty ? null : _busInfoController.text.trim(),
        'precautions': _precautionsController.text.trim().isEmpty ? null : _precautionsController.text.trim(),
        'ownerName': _ownerNameController.text.trim().isEmpty ? null : _ownerNameController.text.trim(),
        'updatedAt': FieldValue.serverTimestamp(),
        // 출퇴근 설정
        'attendanceType': _attendanceType,
        'gpsRadius': _gpsRadius.toInt(),
        if (_beaconUUIDController.text.trim().isNotEmpty)
          'beaconUUID': _beaconUUIDController.text.trim().toUpperCase(),
        'beaconMajor': int.tryParse(_beaconMajorController.text.trim()),
        'beaconMinor': int.tryParse(_beaconMinorController.text.trim()),
        'beaconRssiThreshold': _beaconRssiThreshold,
      };

      if (_isEditMode) {
        // businesses doc + users doc을 WriteBatch로 원자적 처리
        // (CLAUDE.md: 두 write 중 하나라도 실패하면 전체 롤백)
        final editBatch = FirebaseFirestore.instance.batch();
        editBatch.update(
          FirebaseFirestore.instance.collection('businesses').doc(widget.business!.id),
          businessData,
        );
        // managedBusinessIds 누락 시 보정
        editBatch.update(
          FirebaseFirestore.instance.collection('users').doc(ownerId),
          {'managedBusinessIds': FieldValue.arrayUnion([widget.business!.id])},
        );
        await editBatch.commit();

        // WriteBatch commit 성공 후에만 구 이미지 Storage 삭제 수행
        // (CLAUDE.md: Firestore 실패 시 Storage 삭제 안 해야 broken URL 방지)
        if (_imagesToDelete.isNotEmpty) {
          try {
            await _storageService.deleteMultipleByUrls(_imagesToDelete);
          } catch (e) {
            // Storage 삭제 실패는 orphan 파일로 남을 수 있으나 기능에 영향 없음
            debugPrint('⚠️ Storage 구 이미지 삭제 실패 (orphan): $e');
          }
        }
        // 교체된 대표 이미지 구 버전도 batch commit 성공 후 삭제
        if (_mainImage != null &&
            widget.business?.mainImageUrl != null &&
            !_imagesToDelete.contains(widget.business!.mainImageUrl)) {
          try {
            await _storageService.deleteImageByUrl(widget.business!.mainImageUrl!);
          } catch (e) {
            debugPrint('⚠️ Storage 대표 이미지 구 버전 삭제 실패: $e');
          }
        }

        await userProvider.refreshCurrentUser();
        if (!mounted) return;

        ToastHelper.showSuccess('사업장이 수정되었습니다');
      } else {
        businessData['createdAt'] = FieldValue.serverTimestamp();
        businessData['adminIds'] = [ownerId];

        // 사업장 생성 + 유저 업데이트를 WriteBatch로 원자적 처리
        // (하나라도 실패하면 전체 롤백)
        final batch = FirebaseFirestore.instance.batch();
        final bizRef = FirebaseFirestore.instance.collection('businesses').doc();
        batch.set(bizRef, businessData);

        final isFirstBusiness = userProvider.currentUser?.managedBusinessIds.isEmpty ?? true;
        batch.update(
          FirebaseFirestore.instance.collection('users').doc(ownerId),
          {
            'managedBusinessIds': FieldValue.arrayUnion([bizRef.id]),
            if (isFirstBusiness) 'businessId': bizRef.id,
          },
        );
        await batch.commit();
        await userProvider.refreshCurrentUser();
        if (!mounted) return;

        ToastHelper.showSuccess('사업장이 등록되었습니다\n바로 사용하실 수 있습니다');
      }

      if (mounted) {
        if (widget.isFromSignUp) {
          // 회원가입 후 → 로그인 화면으로
          NavigationHelper.pushAndRemoveAll(
            context,
            destination: const LoginScreen(),
          );
        } else {
          // 일반 등록/수정 → 뒤로가기 (변경됨 표시)
          NavigationHelper.popWithChange(context);
        }
      }
    } catch (e) {
      debugPrint('❌ 사업장 저장 실패: $e');
      // Firestore 저장 실패 시 이미 업로드된 Storage 이미지 정리 (고아 파일 방지)
      if (newlyUploadedUrls.isNotEmpty) {
        try {
          await _storageService.deleteMultipleByUrls(newlyUploadedUrls);
        } catch (cleanupErr) {
          debugPrint('⚠️ 저장 실패 후 Storage 정리 실패 (orphan 가능): $cleanupErr');
        }
      }
      if (mounted) ToastHelper.showError('저장에 실패했습니다: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<String?> _uploadImage(File imageFile, String type) async {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final fileName = '${type}_$timestamp.jpg';
    final url = await _storageService.uploadImage(imageFile.path, 'businesses/$fileName');
    // TMP-01: pickAndCompressImage()가 반환한 임시 파일(compressed_xxx.jpg)은
    // 업로드 후 반드시 삭제해야 한다. 업로드 성공/실패 무관하게 정리.
    try {
      if (await imageFile.exists()) await imageFile.delete();
    } catch (_) {
      debugPrint('⚠️ 임시 이미지 파일 삭제 실패 (무시 가능)');
    }
    return url;
  }
}
