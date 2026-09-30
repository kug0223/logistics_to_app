import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
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
import '../../services/geocoding_service.dart';
import '../../utils/business_location_status.dart';
import '../../services/storage_service.dart';

// Utils
import '../../utils/responsive_helper.dart';
import '../../utils/toast_helper.dart';
import '../../utils/constants.dart';
// Widgets
import '../../widgets/common/common_widgets.dart';
import '../../widgets/common/loading_widget.dart';
import '../../widgets/inputs/daum_address_search.dart';

// Screen
import '../../utils/navigation_helper.dart';
import '../../utils/format_helper.dart';
import '../../utils/ocr_verification_helper.dart';
import '../../theme/app_colors.dart';
import '../../widgets/dialogs/styled_dialog.dart';
import '../../widgets/app_select_field.dart';
import '../../widgets/common/app_page_scaffold.dart';
import '../../widgets/common/notification_badge.dart';
import '../common/notification_screen.dart';

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

  // 사업자등록증 이미지 (신규 등록 필수)
  File? _businessLicenseImage;
  String? _businessLicenseImageUrl;

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
  final List<File> _transportImages = [];
  List<String> _transportImageUrls = [];
  final _transportDescriptionController = TextEditingController();

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

  // 근태 반올림 규칙
  AttendanceRules _attendanceRules = AttendanceRules.defaults();

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
    // user가 null이면 자동완성 없이 종료 — 로그인 직후 provider 미초기화 시 발생 가능
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
    // [P4.3A-LOC-01] 이미 저장된 좌표는 저장된 주소의 것이다. 그 사실을
    //   같이 들고 와야 수정 화면이 멀쩡한 사업장을 "위치 미확인" 으로 말하지
    //   않는다. 주소를 고치면 문자열이 달라져 자동으로 낡은 좌표가 된다.
    if (business.latitude != null && business.longitude != null) {
      _resolvedAddress = business.address.trim();
    }
    _city = business.city;
    _district = business.district;

    if (business.phone != null) _phoneController.text = business.phone!;
    if (business.oneLineIntro != null) _oneLineIntroController.text = business.oneLineIntro!;
    if (business.detailedDescription != null) _detailedDescriptionController.text = business.detailedDescription!;
    _transportImageUrls = business.transportImageUrls ?? [];
    if (business.transportDescription != null) _transportDescriptionController.text = business.transportDescription!;
    if (business.precautions != null) _precautionsController.text = business.precautions!;

    _mainImageUrl = business.mainImageUrl;
    _additionalImageUrls = business.imageUrls ?? [];
    _businessLicenseImageUrl = business.businessLicenseImageUrl;

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

    // 근태 반올림 규칙
    _attendanceRules = business.attendanceRules ?? AttendanceRules.defaults();
  }


  @override
  void dispose() {
    // TMP-01: 저장되지 않고 남은 임시 압축 파일 정리 (fire-and-forget)
    _mainImage?.delete().ignore();
    _businessLicenseImage?.delete().ignore();
    for (final file in _additionalImages) {
      file.delete().ignore();
    }
    for (final file in _transportImages) {
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
    _transportDescriptionController.dispose();
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
      // 수정 모드: 뒤로가기 가로채서 확인 다이얼로그 표시
      // 신규 등록(ADMIN HOME에서 진입): 바로 pop 허용
      canPop: !_isEditMode,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        if (_isEditMode) {
          final nav = Navigator.of(context);
          final confirmed = await showDialog<bool>(
            context: context,
            barrierDismissible: false,
            builder: (context) => StyledDialog(
              title: '수정 취소',
              icon: Icons.edit_off,
              headerColor: AppColors.warning,
              content: const Text('저장하지 않은 변경사항이 있을 수 있습니다.\n나가시겠습니까?'),
              actions: [
                StyledDialogButton.cancel(
                  text: '계속 수정',
                  onPressed: () => Navigator.pop(context, false),
                ),
                StyledDialogButton.danger(
                  text: '나가기',
                  onPressed: () => Navigator.pop(context, true),
                ),
              ],
            ),
          );
          if (confirmed == true && nav.context.mounted) nav.pop();
        }
      },
      child: AppPageScaffold(
        title: _isEditMode ? '사업장 수정' : '사업장 등록',
        actions: [
          IconButton(
            icon: const Icon(Icons.home_outlined),
            onPressed: () => NavigationHelper.goHome(context),
            color: AppColors.textSecondary,
            tooltip: '홈',
          ),
          NotificationBadge(
            child: IconButton(
              icon: const Icon(Icons.notifications_outlined),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const NotificationScreen()),
              ),
              color: AppColors.textSecondary,
            ),
          ),
        ],
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
              color: AppColors.surface,
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

          // [P4.3A-LOC-01] 사업장 위치 상태 — 원인마다 다른 말을 한다.
          //   'GPS' 라고 부르지 않는다. 이 값은 주소로 찾은 **사업장 위치**
          //   이지 관리자 기기의 현재 위치가 아니다.
          if (_addressController.text.isNotEmpty) _buildLocationChip(context),

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

          // 사업자등록증 (신규 등록 필수 / 수정 시 선택)
          CommonWidgets.sectionHeader(
            context: context,
            title: '사업자등록증${_isEditMode ? (widget.business?.isApproved == true ? ' (잠금)' : ' (선택)') : ' (필수)'}',
            icon: Icons.description_outlined,
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 4)),
          if (!_isEditMode)
            Padding(
              padding: EdgeInsets.only(bottom: ResponsiveHelper.spacing(context, 8)),
              child: Text(
                '신규 사업장 등록 시 사업자등록증 이미지가 필요합니다.',
                style: ResponsiveHelper.tinyStyle(context, color: AppColors.warning),
              ),
            ),
          _buildBusinessLicensePicker(context, theme),

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
                          image: CachedNetworkImageProvider(_mainImageUrl!),
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
                // TMP-01: 선택 취소된 임시 압축 파일 즉시 정리 (fire-and-forget)
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

  /// 사업자등록증 이미지 선택 (신규 등록 필수 / 수정 선택)
  ///
  /// [REG-2 SEC] 신규 업로드된 사업자등록증은 Storage license/ 경로에 토큰 없이 저장.
  ///   수정 모드에서 기존 URL(_businessLicenseImageUrl)은 직접 로드 불가 (403) — "제출됨" 배지 표시.
  ///   새 파일을 선택한 경우(_businessLicenseImage != null)만 로컬 파일 미리보기 표시.
  Widget _buildBusinessLicensePicker(BuildContext context, ThemeData theme) {
    final hasNewLocal = _businessLicenseImage != null;
    final hasExistingUrl = _businessLicenseImageUrl != null;
    final hasImage = hasNewLocal || hasExistingUrl;
    // [LICENSE-GATE] 승인된 사업장은 클라이언트 직접 라이선스 교체 불가 (P1 fix 2026-09-08)
    // isApproved=true 상태에서 서버(Firestore Rules)가 businessLicenseImageUrl 변경을 거부함.
    final isApprovedBiz = _isEditMode && (widget.business?.isApproved == true);

    // [P4.3B-DOC-03] 선택한 이미지가 사업자등록증으로 보이는지 결과를
    //   그림 바로 아래에 붙인다. 이전에는 아무 이미지나 미리보기만 뜨고
    //   그대로 다음 단계로 넘어갔다.
    final check = _licenseCheckCopy();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildLicenseBox(context, theme,
            hasNewLocal: hasNewLocal,
            hasExistingUrl: hasExistingUrl,
            hasImage: hasImage,
            isApprovedBiz: isApprovedBiz),
        if (check != null)
          Padding(
            padding: EdgeInsets.only(top: ResponsiveHelper.spacing(context, 8)),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_isCheckingLicense)
                  SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.6,
                      valueColor: AlwaysStoppedAnimation(check.color),
                    ),
                  )
                else
                  Icon(check.icon, size: 16, color: check.color),
                SizedBox(width: ResponsiveHelper.spacing(context, 6)),
                // 문장이 두 줄이 될 수 있다 — 좁은 화면에서 넘치지 않게.
                Expanded(
                  child: Text(
                    check.text,
                    style: ResponsiveHelper.tinyStyle(context,
                        color: check.color),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildLicenseBox(
    BuildContext context,
    ThemeData theme, {
    required bool hasNewLocal,
    required bool hasExistingUrl,
    required bool hasImage,
    required bool isApprovedBiz,
  }) {
    return Stack(
      children: [
        GestureDetector(
          onTap: isApprovedBiz
              ? null  // 승인된 사업장: 탭 비활성 (서버 차단과 UI 일치)
              : () async {
            final image = await ImageHelper.pickAndCompressImage(
              context,
              // [P4.3B-DOC-03] 이건 서류다 — 글자가 읽혀야 한다.
              type: ImageType.document,
              useBottomSheet: true,
            );
            if (!mounted || image == null) return;
            final prev = _businessLicenseImage;
            setState(() => _businessLicenseImage = image);
            prev?.delete().ignore(); // 교체 전 임시 파일 정리
            // [P4.3B-DOC-03] 새 이미지를 고른 순간 이전 확인 결과는 무효다.
            await _precheckLicense(image);
          },
          child: Container(
            width: double.infinity,
            height: 160,
            decoration: BoxDecoration(
              color: AppColors.grey200,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: (!_isEditMode && !hasImage) ? AppColors.warning : AppColors.grey300,
                width: (!_isEditMode && !hasImage) ? 1.5 : 1,
              ),
              // 새 로컬 파일이 있을 때만 이미지 표시.
              // 기존 URL은 토큰 없는 Storage 경로 URL → 직접 로드 불가 → "제출됨" 배지로 대체.
              image: hasNewLocal
                  ? DecorationImage(
                      image: FileImage(_businessLicenseImage!),
                      fit: BoxFit.contain,
                    )
                  : null,
            ),
            child: hasNewLocal
                ? null
                : hasExistingUrl
                    // 기존 사업자등록증 제출 상태 표시 (이미지 직접 로드 X)
                    ? Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.check_circle_outline,
                            size: ResponsiveHelper.iconSize(context, 40),
                            color: AppColors.success,
                          ),
                          SizedBox(height: ResponsiveHelper.spacing(context, 8)),
                          Text(
                            '사업자등록증 제출됨',
                            style: ResponsiveHelper.bodyStyle(context).copyWith(
                              color: AppColors.success,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          SizedBox(height: ResponsiveHelper.spacing(context, 4)),
                          Text(
                            isApprovedBiz ? '관리자를 통해서만 변경 가능' : '탭하여 재업로드',
                            style: ResponsiveHelper.tinyStyle(
                              context,
                              color: isApprovedBiz ? AppColors.warning : AppColors.grey500,
                            ),
                          ),
                        ],
                      )
                    : Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.upload_file_outlined,
                            size: ResponsiveHelper.iconSize(context, 40),
                            color: AppColors.grey400,
                          ),
                          SizedBox(height: ResponsiveHelper.spacing(context, 8)),
                          Text(
                            '사업자등록증 이미지 업로드',
                            style: ResponsiveHelper.bodyStyle(context)
                                .copyWith(color: AppColors.grey600),
                          ),
                          SizedBox(height: ResponsiveHelper.spacing(context, 4)),
                          Text(
                            'JPG / PNG',
                            style: ResponsiveHelper.tinyStyle(
                              context,
                              color: AppColors.grey500,
                            ),
                          ),
                        ],
                      ),
          ),
        ),
        // 삭제 버튼 (이미지가 있을 때만 표시)
        if (hasImage)
          Positioned(
            top: ResponsiveHelper.spacing(context, 8),
            right: ResponsiveHelper.spacing(context, 8),
            child: GestureDetector(
              onTap: () {
                _businessLicenseImage?.delete().ignore();
                setState(() {
                  _businessLicenseImage = null;
                  // 기존 URL은 null로 설정만 (삭제 목록 관리는 Firestore update로 처리)
                  _businessLicenseImageUrl = null;
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

        SizedBox(height: ResponsiveHelper.spacing(context, 24)),

        // 근태 반올림 규칙
        CommonWidgets.sectionHeader(
          context: context,
          title: '근태 반올림 규칙',
          icon: Icons.tune_outlined,
        ),
        SizedBox(height: ResponsiveHelper.spacing(context, 8)),
        Text(
          'GPS/비콘 체크 시각에 자동 적용할 반올림 규칙입니다. 기본값으로 대부분의 사업장에 적합합니다.',
          style: ResponsiveHelper.smallStyle(context, color: AppColors.grey600),
        ),
        SizedBox(height: ResponsiveHelper.spacing(context, 12)),
        _buildAttendanceRulesSection(context, theme),

        SizedBox(height: ResponsiveHelper.spacing(context, 16)),
      ],
    );
  }

  /// 근태 반올림 규칙 섹션
  Widget _buildAttendanceRulesSection(BuildContext context, ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 출근 규칙 카드
        Container(
          padding: ResponsiveHelper.cardPadding(context),
          decoration: CommonWidgets.cardDecoration(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.login, size: ResponsiveHelper.iconSize(context, 18), color: AppColors.infoDark),
                  SizedBox(width: ResponsiveHelper.spacing(context, 6)),
                  Text('출근 처리 규칙',
                      style: ResponsiveHelper.bodyStyle(context)
                          .copyWith(fontWeight: FontWeight.bold, color: AppColors.infoDark)),
                ],
              ),
              SizedBox(height: ResponsiveHelper.spacing(context, 12)),
              _buildRuleSlider(context, theme,
                label: '조출 인정 범위',
                description: '정시보다 N분 이상 일찍 도착하면 조출 처리',
                value: _attendanceRules.earlyWindow,
                min: 0, max: 120, divisions: 24, unit: '분',
                onChanged: (v) => _attendanceRules = _attendanceRules.copyWith(earlyWindow: v),
              ),
              _buildRuleSlider(context, theme,
                label: '조출 반올림 단위',
                description: '조출 도착 시각을 N분 단위로 올림 처리',
                value: _attendanceRules.earlyArrivalUnit,
                min: 5, max: 60, divisions: 11, unit: '분',
                onChanged: (v) => _attendanceRules = _attendanceRules.copyWith(earlyArrivalUnit: v),
              ),
              _buildRuleSlider(context, theme,
                label: '지각 유예 시간',
                description: '정시 후 N분 이내 도착은 지각 없이 정시 처리',
                value: _attendanceRules.lateGrace,
                min: 0, max: 30, divisions: 30, unit: '분',
                onChanged: (v) => _attendanceRules = _attendanceRules.copyWith(lateGrace: v),
              ),
              _buildRuleSlider(context, theme,
                label: '지각 반올림 단위',
                description: '지각 시간을 N분 단위로 올림 처리',
                value: _attendanceRules.lateUnit,
                min: 5, max: 60, divisions: 11, unit: '분',
                onChanged: (v) => _attendanceRules = _attendanceRules.copyWith(lateUnit: v),
              ),
            ],
          ),
        ),
        SizedBox(height: ResponsiveHelper.spacing(context, 12)),
        // 퇴근 규칙 카드
        Container(
          padding: ResponsiveHelper.cardPadding(context),
          decoration: CommonWidgets.cardDecoration(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.logout, size: ResponsiveHelper.iconSize(context, 18), color: AppColors.successDark),
                  SizedBox(width: ResponsiveHelper.spacing(context, 6)),
                  Text('퇴근 처리 규칙',
                      style: ResponsiveHelper.bodyStyle(context)
                          .copyWith(fontWeight: FontWeight.bold, color: AppColors.successDark)),
                ],
              ),
              SizedBox(height: ResponsiveHelper.spacing(context, 12)),
              _buildRuleSlider(context, theme,
                label: '정시 퇴근 인정 범위',
                description: '퇴근 예정 후 N분 이내 퇴근도 정시로 처리',
                value: _attendanceRules.lateWindow,
                min: 0, max: 60, divisions: 12, unit: '분',
                onChanged: (v) => _attendanceRules = _attendanceRules.copyWith(lateWindow: v),
              ),
              _buildRuleSlider(context, theme,
                label: '연장 반올림 단위',
                description: '연장 근무 시간을 N분 단위로 내림 처리',
                value: _attendanceRules.overtimeUnit,
                min: 5, max: 30, divisions: 5, unit: '분',
                onChanged: (v) => _attendanceRules = _attendanceRules.copyWith(overtimeUnit: v),
              ),
              _buildRuleSlider(context, theme,
                label: '조퇴 반올림 단위',
                description: '조퇴 시간을 N분 단위로 내림 처리',
                value: _attendanceRules.earlyLeaveUnit,
                min: 5, max: 60, divisions: 11, unit: '분',
                onChanged: (v) => _attendanceRules = _attendanceRules.copyWith(earlyLeaveUnit: v),
              ),
            ],
          ),
        ),
        SizedBox(height: ResponsiveHelper.spacing(context, 8)),
        // 요약 프리뷰
        Container(
          padding: ResponsiveHelper.cardPadding(context),
          decoration: BoxDecoration(
            color: AppColors.infoBg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.info.withValues(alpha: 0.3)),
          ),
          child: Row(
            children: [
              Icon(Icons.info_outline,
                  size: ResponsiveHelper.iconSize(context, 16), color: AppColors.infoDark),
              SizedBox(width: ResponsiveHelper.spacing(context, 8)),
              Expanded(
                child: Text(
                  _attendanceRules.summary,
                  style: ResponsiveHelper.smallStyle(context, color: AppColors.infoDark),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// 규칙 슬라이더 행 (근태 반올림 규칙 공용)
  Widget _buildRuleSlider(
    BuildContext context,
    ThemeData theme, {
    required String label,
    required String description,
    required int value,
    required double min,
    required double max,
    required int divisions,
    required String unit,
    required void Function(int) onChanged,
  }) {
    return Padding(
      padding: EdgeInsets.only(bottom: ResponsiveHelper.spacing(context, 8)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label,
                        style: ResponsiveHelper.smallStyle(context)
                            .copyWith(fontWeight: FontWeight.w600)),
                    Text(description,
                        style: ResponsiveHelper.tinyStyle(context,
                            color: AppColors.grey500)),
                  ],
                ),
              ),
              SizedBox(width: ResponsiveHelper.spacing(context, 8)),
              Container(
                padding: EdgeInsets.symmetric(
                  horizontal: ResponsiveHelper.spacing(context, 10),
                  vertical: ResponsiveHelper.spacing(context, 3),
                ),
                decoration: BoxDecoration(
                  color: theme.primaryColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text('$value$unit',
                    style: ResponsiveHelper.smallStyle(context,
                            color: theme.primaryColor)
                        .copyWith(fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 3,
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
            ),
            child: Slider(
              value: value.toDouble().clamp(min, max),
              min: min,
              max: max,
              divisions: divisions,
              activeColor: theme.primaryColor,
              onChanged: (v) => setState(() => onChanged(v.round())),
            ),
          ),
        ],
      ),
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
                // TMP-01: 선택 취소된 임시 압축 파일 즉시 정리 (fire-and-forget)
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
                    : CachedNetworkImageProvider(networkUrl!),
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
    final totalImages = _transportImages.length + _transportImageUrls.length;

    return Container(
      padding: ResponsiveHelper.cardPadding(context),
      decoration: CommonWidgets.cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 사진 (최대 5장)
          SizedBox(
            height: 100,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: totalImages + (totalImages < 5 ? 1 : 0),
              itemBuilder: (context, index) {
                if (index < _transportImageUrls.length) {
                  return _buildImageThumbnail(
                    context,
                    networkUrl: _transportImageUrls[index],
                    onRemove: () {
                      setState(() {
                        _imagesToDelete.add(_transportImageUrls[index]);
                        _transportImageUrls.removeAt(index);
                      });
                    },
                  );
                }

                final fileIndex = index - _transportImageUrls.length;
                if (fileIndex < _transportImages.length) {
                  return _buildImageThumbnail(
                    context,
                    file: _transportImages[fileIndex],
                    onRemove: () {
                      _transportImages[fileIndex].delete().ignore();
                      setState(() => _transportImages.removeAt(fileIndex));
                    },
                  );
                }

                return GestureDetector(
                  onTap: _pickTransportImages,
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
              },
            ),
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 16)),
          // 상세설명 (선택)
          TextFormField(
            controller: _transportDescriptionController,
            maxLines: 3,
            maxLength: 300,
            style: ResponsiveHelper.bodyStyle(context),
            decoration: InputDecoration(
              labelText: '상세설명 (선택)',
              hintText: '예: 1번 출구에서 나와 직진 후 편의점 옆 골목으로 진입',
              alignLabelWithHint: true,
              prefixIcon: Icon(Icons.directions, color: theme.primaryColor),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickTransportImages() async {
    final totalImages = _transportImages.length + _transportImageUrls.length;

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
    setState(() => _transportImages.addAll(images));
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
      if (_validateStep3()) _saveBusiness();
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
    if (!(_formKey.currentState?.validate() ?? false)) {
      setState(() => _autoValidate = true);
      return false;
    }
    // 신규 등록 시 사업자등록증 필수
    if (!_isEditMode &&
        _businessLicenseImage == null &&
        _businessLicenseImageUrl == null) {
      ToastHelper.showError('사업자등록증 이미지를 업로드해주세요');
      return false;
    }
    // [P4.3B-DOC-03] "파일이 있다" 를 "사업자등록증 준비 완료" 로 쓰지 않는다.
    //
    //   예전에는 이 검증이 `File != null` 하나였고, 풍경 사진을 골라도
    //   그대로 통과했다. 새로 고른 이미지는 **확인을 통과해야** 넘어간다.
    //   기존에 제출된 서류(`_businessLicenseImageUrl` 만 있는 수정 모드)는
    //   여기서 다시 검사하지 않는다 — 이미 올라간 파일은 손에 없다.
    if (_businessLicenseImage != null) {
      if (_isCheckingLicense) {
        ToastHelper.showError('사업자등록증을 확인하는 중이에요\n잠시만 기다려주세요');
        return false;
      }
      if (!_licenseCheckPassed) {
        // 왜 안 되는지는 그림 아래 안내가 이미 말하고 있다 — 여기서는
        // 같은 말을 반복하지 않고 그 자리를 가리킨다.
        ToastHelper.showError('사업자등록증을 확인하지 못했어요\n아래 안내를 확인해 주세요');
        setState(() => _autoValidate = true);
        return false;
      }
    }
    // [P4.3A-LOC-03] 좌표 없이 다음 단계로 보내지 않는다.
    //
    //   예전에는 세 단계 어디에서도 좌표를 보지 않았고, 저장 payload 는
    //   `'latitude': _latitude` 를 **null 인 채로** 보냈다. 그래서 화면에
    //   'GPS 위치 미확인' 이 떠 있어도 사업장은 그대로 만들어졌다.
    //   그 대가는 관리자가 아니라 **근로자**가 치렀다 — 근무 당일 출근을
    //   찍으려는 순간 "사업장의 GPS 위치가 등록되어 있지 않습니다" 로 막힌다
    //   (`attendance_check_screen`). 그때는 이미 늦다.
    //
    //   기기 위치를 요구하는 것이 아니다. 이 폼은 관리자 기기의 GPS 를 한
    //   번도 읽지 않는다 — 본사에서 다른 지점을 등록해도 된다. 여기서 막는
    //   것은 **주소로 찾은 사업장 위치**가 비어 있는 경우뿐이다.
    if (_isResolvingLocation) {
      ToastHelper.showError('주소의 위치를 확인하는 중이에요\n잠시만 기다려주세요');
      return false;
    }
    if (!_hasUsableLocation) {
      ToastHelper.showError(
          '사업장 위치를 확인해야 등록할 수 있어요\n위치가 없으면 근로자가 이곳에서 출퇴근을 찍을 수 없습니다');
      setState(() => _autoValidate = true);
      return false;
    }
    return true;
  }

  bool _validateStep3() {
    if (_attendanceType == 'beacon' || _attendanceType == 'both') {
      final uuid = _beaconUUIDController.text.trim();
      if (uuid.isEmpty) {
        ToastHelper.showError('비콘 UUID를 입력해주세요');
        return false;
      }
      final uuidRegex = RegExp(
        r'^[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}$',
      );
      if (!uuidRegex.hasMatch(uuid.toUpperCase())) {
        ToastHelper.showError('UUID 형식이 올바르지 않습니다\n(예: XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX)');
        return false;
      }
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
    final prev = _mainImage;
    setState(() => _mainImage = image);
    prev?.delete().ignore(); // [WAGE-L2] 교체 전 임시 파일 삭제
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

      if (result != null && mounted) {
        setState(() {
          _addressController.text = result.fullAddress;
          _city = result.sigungu?.isNotEmpty == true
              ? result.sigungu
              : FormatHelper.parseAddressCity(result.fullAddress);
          _district = result.bname?.isNotEmpty == true
              ? result.bname
              : FormatHelper.parseAddressDistrict(result.fullAddress);
        });
        // [P4.3A-LOC-01] 좌표는 여기서부터 이 화면이 책임진다.
        await _resolveCoordinates(result.fullAddress);
      }
    } catch (e) {
      debugPrint('⚠️ 주소 검색 실패, 수기 입력 모드: $e');
      if (mounted) _showManualAddressDialog();
    }
  }

  // ── [P4.3A-LOC-01] 주소 → 좌표 ────────────────────────────────────
  //
  //   왜 이 상태가 필요한가:
  //     예전에는 좌표가 `null` 이냐 아니냐 둘뿐이었고, 화면은 그것을
  //     'GPS 위치 미확인' 한 문장으로 말했다. 그 하나에 **여섯 가지**가
  //     섞여 있었다 — 아직 주소를 안 골랐다 / 조회 중이다 / 그 주소에
  //     등록된 좌표가 없다 / 네트워크가 안 됐다 / 빌드에 키가 없다 /
  //     키가 거부됐다. 다음 행동이 전부 다른데 문장이 같으니, 관리자는
  //     되지도 않을 주소 재검색만 반복하게 된다.
  //
  //     'GPS' 라는 말도 틀렸다. 이 값은 **주소로 찾은 사업장 위치**이지
  //     관리자 기기의 현재 위치가 아니다. 이 폼은 기기 위치를 한 번도
  //     읽지 않는다 — 본사에서 다른 지점을 등록해도 된다.

  /// 지금 좌표가 어느 주소의 것인지. 주소를 손으로 고치면 좌표가 그 주소의
  /// 것이 아니게 되므로, 문자열을 맞춰 보고 낡은 좌표를 쓰지 않는다.
  String? _resolvedAddress;

  /// [P4.3A-LOC-02] 늦게 끝난 옛 요청이 새 주소의 좌표를 덮지 않도록.
  int _geocodeRequestId = 0;

  bool _isResolvingLocation = false;
  GeocodeStatus? _locationFailure;

  /// 저장해도 되는 상태인가 — 주소와 좌표가 **같은 주소의 것**이어야 한다.
  bool get _hasUsableLocation =>
      _latitude != null &&
      _longitude != null &&
      _resolvedAddress != null &&
      _resolvedAddress == _addressController.text.trim();

  Future<void> _resolveCoordinates(String address) async {
    final requestId = ++_geocodeRequestId;
    setState(() {
      _isResolvingLocation = true;
      _locationFailure = null;
      // 조회 중에는 이전 주소의 좌표를 들고 있지 않는다 — 그 사이에 저장하면
      // 주소와 좌표가 서로 다른 곳을 가리킨다.
      _latitude = null;
      _longitude = null;
      _resolvedAddress = null;
    });

    final result = await GeocodingService.resolveAddress(address);

    // 내가 마지막 요청이 아니면 아무것도 쓰지 않는다. 사용자가 A 를 고른 뒤
    // 곧바로 B 를 골랐다면 화면의 주소는 B 인데 이 결과는 A 의 것이다.
    if (!mounted || requestId != _geocodeRequestId) return;

    setState(() {
      _isResolvingLocation = false;
      if (result.isResolved) {
        _latitude = result.latitude;
        _longitude = result.longitude;
        _resolvedAddress = address;
        _locationFailure = null;
      } else {
        _locationFailure = result.status;
      }
    });
  }

  /// 상태 칩에 쓸 문구. 원인마다 다음 행동이 다르므로 문장도 다르다.
  /// 문구·행동은 `business_location_status.dart` 가 정한다(그쪽이 테스트
  /// 대상이다). 여기서는 그 결과에 아이콘·색만 붙인다.
  ({String text, IconData icon, Color color, LocationAction action})
      _locationChip() {
    final copy = businessLocationCopy(
      resolving: _isResolvingLocation,
      resolved: _hasUsableLocation,
      failure: _locationFailure,
    );

    final (IconData icon, Color color) = switch (copy.action) {
      _ when _isResolvingLocation =>
        (Icons.location_searching, AppColors.textSecondary),
      _ when _hasUsableLocation => (Icons.place, AppColors.success),
      LocationAction.retry => (Icons.cloud_off_outlined, AppColors.warning),
      LocationAction.manual when _locationFailure == GeocodeStatus.notFound =>
        (Icons.wrong_location_outlined, AppColors.warning),
      LocationAction.manual => (Icons.error_outline, AppColors.error),
      LocationAction.none =>
        (Icons.location_on_outlined, AppColors.textSecondary),
    };

    return (text: copy.text, icon: icon, color: color, action: copy.action);
  }

  Widget _buildLocationChip(BuildContext context) {
    final chip = _locationChip();
    final address = _addressController.text.trim();
    // 재시도는 "같은 주소로 다시 조회" 다 — 주소 검색창을 다시 열지 않는다.
    final onTap = switch (chip.action) {
      LocationAction.retry when address.isNotEmpty =>
        () => _resolveCoordinates(address),
      LocationAction.manual => _showManualAddressDialog,
      _ => null,
    };

    return Padding(
      padding: EdgeInsets.only(top: ResponsiveHelper.spacing(context, 6)),
      child: GestureDetector(
        onTap: onTap,
        child: Row(
          children: [
            if (_isResolvingLocation)
              SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(
                  strokeWidth: 1.6,
                  valueColor: AlwaysStoppedAnimation(chip.color),
                ),
              )
            else
              Icon(chip.icon, size: 14, color: chip.color),
            SizedBox(width: ResponsiveHelper.spacing(context, 4)),
            // [CLAUDE.md 모바일 UI] 문장이 길어졌다 — 좁은 화면에서 넘치지
            //   않게 남은 폭 안에서 줄바꿈시킨다.
            Expanded(
              child: Text(
                chip.text,
                style: ResponsiveHelper.tinyStyle(context, color: chip.color),
              ),
            ),
            if (onTap != null) ...[
              SizedBox(width: ResponsiveHelper.spacing(context, 4)),
              Icon(Icons.refresh, size: 12, color: chip.color),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _showManualAddressDialog() async {
    // [FC-BIZ-01 OWNERSHIP FIX] _ManualAddressDialog(StatefulWidget)이 controller 3개를
    // 직접 소유하고 State.dispose()에서 해제한다.
    final result = await showDialog<_ManualAddressResult>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const _ManualAddressDialog(),
    );
    if (mounted && result != null && result.address.isNotEmpty) {
      setState(() => _addressController.text = result.address);
      // [P4.3A-LOC-01] 수기 입력에서 좌표를 직접 적었으면 그것을 쓴다 —
      //   지도 검색이 못 찾는 주소를 위한 탈출구다. 적지 않았으면 여기서도
      //   주소로 좌표를 찾는다. 예전에는 좌표 칸을 비워 두면 그대로 좌표
      //   없는 사업장이 만들어졌다.
      if (result.lat != null && result.lng != null) {
        setState(() {
          _geocodeRequestId++; // 진행 중이던 조회 결과를 무효화한다
          _isResolvingLocation = false;
          _locationFailure = null;
          _latitude = result.lat;
          _longitude = result.lng;
          _resolvedAddress = result.address;
        });
      } else {
        await _resolveCoordinates(result.address);
      }
    }
  }

  // ── [P4.3B-DOC-03] 사업자등록증 precheck ──────────────────────────
  //
  //   예전에는 "파일이 있다" 가 곧 "사업자등록증 준비 완료" 였다. 풍경
  //   사진을 골라도 다음 단계로 넘어갔다.
  //
  //   여기서 하는 것은 **공식 진위 확인이 아니다.** 국세청 조회가 아니고,
  //   통과했다고 사업자가 인증된 것도 아니다. 그래서 문구에 '인증'·'검증
  //   완료' 를 쓰지 않는다. 하는 일은 셋뿐이다 — 명백히 다른 이미지를
  //   거르고, 못 읽은 이미지는 재촬영을 유도하고, 읽힌 번호를 입력과
  //   대조한다.

  /// 지금 확인 결과가 **어느 파일의 것**인지. 재선택하면 즉시 무효가 된다.
  String? _precheckedLicensePath;

  /// 늦게 끝난 옛 OCR 이 새 이미지의 상태를 덮지 않도록.
  int _licenseCheckId = 0;

  bool _isCheckingLicense = false;
  String? _licenseCheckStatus;
  String? _licenseNumberPrefix;

  /// 지금 들고 있는 파일이 확인을 통과했는가.
  /// 파일이 바뀌면 경로가 달라져 자동으로 false 가 된다.
  bool get _licenseCheckPassed =>
      _licenseCheckStatus == OcrVerificationHelper.checkPassed &&
      _precheckedLicensePath != null &&
      _precheckedLicensePath == _businessLicenseImage?.path;

  Future<void> _precheckLicense(File image) async {
    final checkId = ++_licenseCheckId;
    setState(() {
      _isCheckingLicense = true;
      _licenseCheckStatus = null;
      _licenseNumberPrefix = null;
      _precheckedLicensePath = null;
    });

    final result = await OcrVerificationHelper.precheckBusinessLicense(
      image.path,
      _businessNumberController.text,
    );

    // 내가 마지막 요청이 아니면 아무것도 쓰지 않는다 — 사용자가 A 를 고른
    // 뒤 곧바로 B 를 골랐다면 화면의 파일은 B 인데 이 결과는 A 의 것이다.
    if (!mounted || checkId != _licenseCheckId) return;

    setState(() {
      _isCheckingLicense = false;
      _licenseCheckStatus = result['status'] as String?;
      _licenseNumberPrefix = result['numberPrefix'] as String?;
      // [P4.3B §15] 확인한 파일과 나중에 업로드할 파일이 **같아야** 한다.
      //   경로를 함께 적어 두고, 저장 직전에 다시 맞춰 본다.
      _precheckedLicensePath = image.path;
    });
  }

  /// 상태별 안내. 사용자가 **무엇을 고쳐야 하는지**를 말한다.
  ({String text, IconData icon, Color color})? _licenseCheckCopy() {
    if (_isCheckingLicense) {
      return (
        text: '사업자등록증을 확인하고 있어요',
        icon: Icons.document_scanner_outlined,
        color: AppColors.textSecondary,
      );
    }
    if (_businessLicenseImage == null) return null;
    return switch (_licenseCheckStatus) {
      // '인증되었습니다' 라고 하지 않는다 — 공식 진위 확인이 아니다.
      OcrVerificationHelper.checkPassed => (
          text: '사업자등록증 정보를 확인했어요',
          icon: Icons.task_alt,
          color: AppColors.success,
        ),
      OcrVerificationHelper.checkNotDocument => (
          text: '사업자등록증으로 확인하기 어려운 이미지예요\n사업자등록증 전체가 보이도록 다시 등록해 주세요',
          icon: Icons.image_not_supported_outlined,
          color: AppColors.error,
        ),
      OcrVerificationHelper.checkUnreadable ||
      OcrVerificationHelper.checkNumberUnread =>
        (
          text: '사업자등록증 정보를 읽지 못했어요\n글자가 선명하게 보이도록 다시 촬영해 주세요',
          icon: Icons.visibility_off_outlined,
          color: AppColors.warning,
        ),
      OcrVerificationHelper.checkNumberMismatch => (
          text: _licenseNumberPrefix == null
              ? '입력한 사업자등록번호와 서류의 번호가 달라요\n입력 정보 또는 서류를 확인해 주세요'
              : '입력한 사업자등록번호와 서류의 번호가 달라요\n'
                  '서류에는 ${_licenseNumberPrefix!.trim()}… 로 적혀 있어요',
          icon: Icons.rule,
          color: AppColors.error,
        ),
      _ => null,
    };
  }

  // ── [P4.3B-SAVE-02] 첨부 수명 ─────────────────────────────────────
  //
  //   첨부는 선택 시점과 저장 시점 사이에 **단계 두 개**를 건너온다.
  //   그 사이에 파일이 사라져 있을 수 있다는 것을 실기기가 증명했다.
  //   ImageHelper 가 앱 소유 사본을 주도록 고쳤지만(TEMP-01), 그래도 저장
  //   직전에 한 번 더 본다 — 디스크 정리·외부 삭제는 여전히 가능하다.

  /// 읽을 수 없는 첨부가 있으면 그 이름을 돌려준다. 없으면 null.
  Future<String?> _firstMissingAttachment() async {
    final targets = <(String, File?)>[
      ('사업자등록증', _businessLicenseImage),
      ('대표 이미지', _mainImage),
      for (final f in _additionalImages) ('추가 이미지', f),
      for (final f in _transportImages) ('교통편 이미지', f),
    ];
    for (final (label, file) in targets) {
      if (file == null) continue;
      if (!await file.exists()) {
        debugPrint('❌ [저장] 첨부 소실: $label / ${file.path}');
        return label;
      }
    }
    return null;
  }

  /// 첨부를 다시 고를 수 있는 단계로 되돌린다.
  /// 사업자등록증·대표 이미지 모두 2단계(정보·서류)에 있다.
  void _focusAttachmentSection() {
    if (_currentStep != 1) setState(() => _currentStep = 1);
  }

  Future<void> _saveBusiness() async {
    if (_isLoading || !mounted) return;
    setState(() => _isLoading = true);

    // catch 블록에서 orphan Storage 정리를 위해 try 밖에서 선언
    final newlyUploadedUrls = <String>[];
    try {
      final userProvider = context.read<UserProvider>();
      final user = userProvider.currentUser;

      if (user == null) {
        ToastHelper.showError('로그인이 필요합니다.');
        return;
      }

      final ownerId = user.uid;

      // [P4.3A-LOC-03] writer 쪽 마지막 방어.
      //   단계 게이트(`_validateStep2`) 하나에만 기대지 않는다 — 단계 순서가
      //   바뀌거나 다른 경로가 생기면 좌표 없는 사업장이 다시 만들어질 수
      //   있고, 그 비용은 근무 당일 출근을 못 찍는 근로자가 치른다.
      //   0,0 같은 기본값으로 채우지 않는다 — 그건 실제로 존재하는 바다 한
      //   가운데 좌표이고, 반경 판정을 조용히 통과시키는 것이 아니라 조용히
      //   틀리게 만든다.
      if (_latitude == null || _longitude == null) {
        ToastHelper.showError('사업장 위치를 확인해야 등록할 수 있어요');
        return;
      }

      if (kDebugMode) debugPrint('📍 [저장] 위도: $_latitude / 경도: $_longitude');

      // 업로드 경로에 사용할 bizId: 수정=기존 ID, 신규=미리 생성 (Storage 규칙이 businesses/{bizId}/ 구조 요구)
      final uploadBizId = _isEditMode
          ? widget.business!.id
          : FirebaseFirestore.instance.collection('businesses').doc().id;

      // [P4.3B-SAVE-02] 업로드를 **시작하기 전에** 첨부가 아직 읽히는지 본다.
      //
      //   실기기에서 여기가 터졌다 —
      //     PathNotFoundException: .../cache/scaled_....webp (errno = 2)
      //   첨부 하나가 사라진 상태로 업로드를 시작하면, 먼저 끝난 다른
      //   이미지는 Storage 에 올라가 있는데 `Future.wait` 가 예외로 끊겨
      //   그 URL 들을 아무도 받지 못한다. 사용자에게는 "저장 실패" 인데
      //   Storage 에는 주인 없는 객체가 남는 상태다.
      //   그래서 **하나라도 읽히지 않으면 아무것도 올리지 않는다.**
      // [P4.3B §15] 확인한 파일과 올릴 파일이 같은지 마지막으로 맞춘다.
      //   OCR 은 A 를 보고 통과했는데 B 가 업로드되면 안 된다.
      if (_businessLicenseImage != null && !_licenseCheckPassed) {
        if (mounted) {
          ToastHelper.showError('사업자등록증을 다시 확인해 주세요');
          _focusAttachmentSection();
        }
        return;
      }

      final missing = await _firstMissingAttachment();
      if (missing != null) {
        if (mounted) {
          ToastHelper.showError('첨부한 $missing 파일을 불러올 수 없습니다\n다시 선택해 주세요');
          _focusAttachmentSection();
        }
        return;
      }

      // CLAUDE.md 삭제 순서 규칙:
      // Storage 삭제는 Firestore 업데이트 성공 후에만 수행한다.
      // 이 시점에서는 새 이미지 업로드만 먼저 진행한다.

      // 이미지 병렬 업로드 (대표 + 사업자등록증 + 추가 + 교통편 동시)
      String? mainImageUrl = _mainImageUrl;
      String? businessLicenseImageUrl = _businessLicenseImageUrl;
      List<String> additionalUrls = List.from(_additionalImageUrls);
      List<String> transportUrls = List.from(_transportImageUrls);

      // [R7-P4.4E.1A] 신규 등록은 이 시점에 `businesses/` 로 아무것도 올리지 않는다.
      //
      //   `callableUploadBusinessImage` 는 `assertBizAdmin` 으로 **사업장 문서가
      //   이미 있을 것**을 요구한다(`if (!bizSnap.exists) throw not-found`).
      //   그런데 신규 등록은 문서를 업로드 **뒤에** 만들었다. 그래서 실기기에서
      //   항상 이렇게 끝났다:
      //     [firebase_functions/not-found] 사업장을 찾을 수 없습니다.
      //   등록증이 신규 필수라 업로드는 반드시 실행됐고, 결과적으로
      //   **신규 사업장 등록이 구조적으로 불가능**했다(af1a6f5 이후).
      //
      //   순서를 바꾼다. 새 권한 구멍을 내지 않는 방향으로:
      //     ① 등록증 → `users/{uid}/businessLicense_*` (사업장이 필요 없는
      //        호출자 소유 경로. 서류 관리 화면이 이미 쓰는 그 경로다)
      //        → `callableRegisterBusinessLicense` 가 소유권·존재를 확인하고
      //          `businessLicenseImagePath` 를 **서버가** 기록한다.
      //          `checkBusinessLicense` 의 owner 분기가 이미 인정하는 값이라
      //          readiness 계약은 그대로다.
      //     ② 사업장 문서 생성 — 이때 등록증은 이미 확정돼 있으므로
      //        `onBusinessCreated` 의 자동승인 license 판정도 통과한다.
      //     ③ 표시용 이미지(대표·추가·교통)는 사업장이 생긴 뒤에 올린다.
      //
      //   `callableUploadBusinessImage` 와 `assertBizAdmin`(83개 호출처)은
      //   건드리지 않는다. 업로드 표면도 하나도 늘지 않는다.
      final bool deferBusinessUploads = !_isEditMode;

      if (deferBusinessUploads && _businessLicenseImage != null) {
        // 사업장 문서에는 등록증 URL 을 넣지 않는다 — owner 경로가 진실이다.
        businessLicenseImageUrl = null;
        await _registerOwnerBusinessLicense(ownerId, _businessLicenseImage!);
      }

      // 업로드 인덱스 추적
      int uploadIdx = 0;
      int? mainUploadIdx;
      int? licenseUploadIdx;
      final uploadFutures = <Future<String?>>[];

      if (_mainImage != null && !deferBusinessUploads) {
        mainUploadIdx = uploadIdx++;
        uploadFutures.add(_uploadImage(_mainImage!, uploadBizId, 'main'));
      }
      if (_businessLicenseImage != null && !deferBusinessUploads) {
        licenseUploadIdx = uploadIdx++;
        uploadFutures.add(_uploadImage(_businessLicenseImage!, uploadBizId, 'license'));
      }
      final additionalUploadStart = uploadIdx;
      if (!deferBusinessUploads) {
        uploadFutures.addAll(_additionalImages.map((img) => _uploadImage(img, uploadBizId, 'additional')));
      }
      final transportUploadStart = additionalUploadStart +
          (deferBusinessUploads ? 0 : _additionalImages.length);
      if (!deferBusinessUploads) {
        uploadFutures.addAll(_transportImages.map((img) => _uploadImage(img, uploadBizId, 'transport')));
      }

      if (uploadFutures.isNotEmpty) {
        final results = await Future.wait(uploadFutures);
        if (!mounted) {
          final uploaded = results.whereType<String>().toList();
          if (uploaded.isNotEmpty) await _storageService.deleteMultipleByUrls(uploaded);
          return;
        }

        // 선택한 이미지 중 하나라도 업로드 실패 → 전체 등록 취소
        // (App Check 실패, 네트워크 오류 등)
        if (results.any((url) => url == null)) {
          final uploaded = results.whereType<String>().toList();
          if (uploaded.isNotEmpty) {
            await _storageService.deleteMultipleByUrls(uploaded);
          }
          throw Exception('이미지 업로드에 실패했습니다. 인터넷 연결을 확인 후 다시 시도해주세요.');
        }

        if (mainUploadIdx != null) {
          mainImageUrl = results[mainUploadIdx]!;
          newlyUploadedUrls.add(mainImageUrl);
        }
        if (licenseUploadIdx != null) {
          businessLicenseImageUrl = results[licenseUploadIdx]!;
          newlyUploadedUrls.add(businessLicenseImageUrl);
        }
        for (int i = additionalUploadStart; i < transportUploadStart; i++) {
          final url = results[i]!;
          newlyUploadedUrls.add(url);
          additionalUrls.add(url);
        }
        for (int i = transportUploadStart; i < results.length; i++) {
          final url = results[i]!;
          newlyUploadedUrls.add(url);
          transportUrls.add(url);
        }
      }

      // 저장 시점의 타임스탬프/변경자 주입 — 감사 이력
      _attendanceRules = _attendanceRules.copyWith(
        rulesUpdatedAt: DateTime.now(),
        rulesUpdatedBy: ownerId,
      );

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
        // C-05: 수정 모드에서 ownerId를 businessData에 포함하지 않음 — 공동 관리자가
        // 저장 시 소유권이 바뀌는 것 방지. 신규 등록 시에만 ownerId 설정.
        if (!_isEditMode) 'ownerId': ownerId,
        // isApproved는 관리자가 편집할 수 없는 서버 관리 필드 — update 맵 제외
        // (포함 시 슈퍼어드민이 isApproved 변경 후 BUSINESS_ADMIN이 저장하면 diff에 포함돼 PERMISSION_DENIED 발생)
        if (!_isEditMode) 'isApproved': false,
        // 사업자등록증: 신규=필수(업로드 URL), 수정=업로드했을 때만 갱신
        if (businessLicenseImageUrl != null)
          'businessLicenseImageUrl': businessLicenseImageUrl,
        'mainImageUrl': mainImageUrl,
        'imageUrls': additionalUrls,
        'oneLineIntro': _oneLineIntroController.text.trim().isEmpty ? null : _oneLineIntroController.text.trim(),
        'detailedDescription': _detailedDescriptionController.text.trim().isEmpty ? null : _detailedDescriptionController.text.trim(),
        'parkingAvailable': _parkingAvailable,
        'mealsProvided': _selectedMeals.isEmpty ? null : _selectedMeals,
        'uniformProvided': _uniformProvided,
        'facilities': _selectedFacilities,
        'transportImageUrls': transportUrls.isEmpty ? null : transportUrls,
        'transportDescription': _transportDescriptionController.text.trim().isEmpty ? null : _transportDescriptionController.text.trim(),
        'precautions': _precautionsController.text.trim().isEmpty ? null : _precautionsController.text.trim(),
        'ownerName': _ownerNameController.text.trim().isEmpty ? null : _ownerNameController.text.trim(),
        'updatedAt': FieldValue.serverTimestamp(),
        // 출퇴근 설정
        'attendanceType': _attendanceType,
        'gpsRadius': _gpsRadius.toInt(),
        if (_beaconUUIDController.text.trim().isNotEmpty)
          'beaconUUID': _beaconUUIDController.text.trim().toUpperCase(),
        if (int.tryParse(_beaconMajorController.text.trim()) != null)
          'beaconMajor': int.tryParse(_beaconMajorController.text.trim()),
        if (int.tryParse(_beaconMinorController.text.trim()) != null)
          'beaconMinor': int.tryParse(_beaconMinorController.text.trim()),
        'beaconRssiThreshold': _beaconRssiThreshold,
        'attendanceRules': _attendanceRules.toMap(),
      };

      if (_isEditMode) {
        // businesses doc + users doc을 WriteBatch로 원자적 처리
        // (CLAUDE.md: 두 write 중 하나라도 실패하면 전체 롤백)
        final editBatch = FirebaseFirestore.instance.batch();
        editBatch.update(
          FirebaseFirestore.instance.collection('businesses').doc(widget.business!.id),
          businessData,
        );
        // H-05: businesses.adminIds ↔ users.managedBusinessIds 양방향 동기화
        // [RISK] adminIds arrayUnion: ownerId가 이미 adminIds에 포함된 경우 arrayUnion은 no-op →
        //   affectedKeys()에 adminIds 없음 → 보안 규칙 통과. 미포함 시(레거시 데이터) 규칙 차단.
        //   신규 사업장은 create 시 항상 adminIds=[ownerId]로 생성되므로 정상 플로우에서는 no-op.
        editBatch.update(
          FirebaseFirestore.instance.collection('users').doc(ownerId),
          {'managedBusinessIds': FieldValue.arrayUnion([widget.business!.id])},
        );
        editBatch.update(
          FirebaseFirestore.instance.collection('businesses').doc(widget.business!.id),
          {'adminIds': FieldValue.arrayUnion([ownerId])},
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
        // uploadBizId: 이미지 업로드 경로와 동일한 ID 사용 (Storage 규칙 일관성 보장)
        final batch = FirebaseFirestore.instance.batch();
        final bizRef = FirebaseFirestore.instance.collection('businesses').doc(uploadBizId);
        batch.set(bizRef, businessData);

        batch.update(
          FirebaseFirestore.instance.collection('users').doc(ownerId),
          {
            'managedBusinessIds': FieldValue.arrayUnion([bizRef.id]),
          },
        );
        await batch.commit();

        // [R7-P4.4E.1A ③] 사업장이 생겼으니 이제 표시용 이미지를 올린다.
        //
        //   여기서 실패해도 등록을 되돌리지 않는다. 등록의 본체(사업장 +
        //   등록증)는 이미 성립했고, 대표·추가·교통 사진은 **선택 항목**이며
        //   사업장 정보 수정에서 언제든 다시 올릴 수 있다. 되돌리면 사용자가
        //   처음부터 다시 입력해야 하는데, 잃는 것이 얻는 것보다 크다.
        final finalized = await _uploadDeferredImages(uploadBizId);

        await userProvider.refreshCurrentUser();
        if (!mounted) return;

        if (!finalized) {
          ToastHelper.showError(
              const _SaveFailure(_SaveFailureKind.finalizeIncomplete).message);
        } else {
          ToastHelper.showSuccess('사업장 등록 완료\n운영팀 검토 후 서비스가 활성화됩니다');
        }
      }

      if (mounted) {
        // 등록/수정 완료 → 뒤로가기 (변경됨 표시)
        // ADMIN HOME 복귀 시 STATE B 배너로 전환됨 (AuthWrapper 라우팅 불필요)
        NavigationHelper.popWithChange(context);
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
      // [P4.3B-RAW-EXCEPTION-UX] 예외 문자열을 그대로 보여주지 않는다.
      //   실기기에서 사용자가 본 것은 이것이었다:
      //     저장에 실패했습니다: PathNotFoundException: Cannot open file,
      //     path='/data/user/0/com.alfit.app/cache/scaled_....webp'
      //     (OS Error: No such file or directory, errno = 2)
      //   이건 제품 메시지가 아니다. 기술 진단은 위 debugPrint 에 남기고,
      //   사용자에게는 **무엇을 하면 되는지**를 말한다.
      //
      // [R7-P4.4E.1A §12] 원인이 다르면 **할 일도 다르다.** 파일을 다시 골라야
      //   하는 것과, 잠시 후 재시도하면 되는 것과, 권한이 없어 재시도가 소용없는
      //   것을 같은 문장으로 말하면 사용자는 무엇을 해야 할지 알 수 없다.
      //   내부 코드·경로는 여전히 노출하지 않는다 — 위 debugPrint 의 몫이다.
      if (mounted) {
        if (e is PathNotFoundException || e is FileSystemException) {
          ToastHelper.showError('첨부한 파일을 불러올 수 없습니다\n이미지를 다시 선택해 주세요');
          _focusAttachmentSection();
        } else if (e is _SaveFailure) {
          ToastHelper.showError(e.message);
          if (e.kind == _SaveFailureKind.uploadFailed ||
              e.kind == _SaveFailureKind.uploadNotAuthorized) {
            _focusAttachmentSection();
          }
        } else if (e is FirebaseException && e.code == 'permission-denied') {
          ToastHelper.showError('저장 권한이 없습니다\n입력한 사업자등록번호를 확인해 주세요');
        } else if (e is FirebaseException && e.code == 'unavailable') {
          ToastHelper.showError('네트워크에 연결할 수 없습니다\n연결을 확인 후 다시 시도해 주세요');
        } else {
          ToastHelper.showError('저장하지 못했습니다\n잠시 후 다시 시도해주세요');
        }
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  // [SEC-BIZ-UPLOAD] CF 경유 업로드 — callableUploadBusinessImage → assertBizAdmin 검증 후 저장
  // [REG-2 SEC] type == 'license' 시 fileType: 'businessLicense' 전달
  //   → CF가 license/ 서브경로 + 토큰 없이 저장 (Storage rules allow get: if false)
  /// [R7-P4.4E.1A ③] 사업장 생성 **후** 표시용 이미지를 올리고 문서에 붙인다.
  ///
  ///   이제 사업장 문서가 있으므로 `callableUploadBusinessImage` 의
  ///   `assertBizAdmin` 이 정상 통과한다 — CF 계약을 바꾸지 않은 이유다.
  ///   하나라도 못 올리면 올라간 것만 문서에 반영하고 false 를 돌려준다.
  ///   부분 성공을 지우지 않는다: 사용자가 고른 사진을 이유 없이 버리는 셈이다.
  Future<bool> _uploadDeferredImages(String bizId) async {
    if (_mainImage == null &&
        _additionalImages.isEmpty &&
        _transportImages.isEmpty) {
      return true;
    }

    String? mainUrl;
    final additional = <String>[];
    final transport = <String>[];
    var allOk = true;

    Future<void> put(File f, String type, void Function(String) sink) async {
      try {
        final url = await _uploadImage(f, bizId, type);
        if (url == null) {
          allOk = false;
        } else {
          sink(url);
        }
      } catch (e) {
        debugPrint('❌ 등록 후 이미지 업로드 실패($type): $e');
        allOk = false;
      }
    }

    if (_mainImage != null) await put(_mainImage!, 'main', (u) => mainUrl = u);
    for (final img in _additionalImages) {
      await put(img, 'additional', additional.add);
    }
    for (final img in _transportImages) {
      await put(img, 'transport', transport.add);
    }

    final updates = <String, dynamic>{
      if (mainUrl != null) 'mainImageUrl': mainUrl,
      if (additional.isNotEmpty) 'imageUrls': additional,
      if (transport.isNotEmpty) 'transportImageUrls': transport,
    };
    if (updates.isEmpty) return allOk;

    try {
      await FirebaseFirestore.instance
          .collection('businesses')
          .doc(bizId)
          .update(updates);
    } catch (e) {
      debugPrint('❌ 등록 후 이미지 URL 반영 실패: $e');
      return false;
    }
    return allOk;
  }

  /// [R7-P4.4E.1A] 신규 등록용 사업자등록증 확정 — 사업장 문서가 없어도 된다.
  ///
  ///   서류 관리 화면이 쓰는 경로·순서를 그대로 쓴다. 새 경로도, 새 callable 도
  ///   만들지 않는다. 소유권은 경로(`users/{uid}/`)가 증명하고, 그것을
  ///   `businessLicenseImagePath` 로 **서버가** 기록한다 — 클라이언트는 그 필드를
  ///   쓸 수 없다(R8-P5.1). 그래서 임의 업로드로 readiness 를 열 수 없다.
  Future<void> _registerOwnerBusinessLicense(String ownerId, File image) async {
    final path =
        'users/$ownerId/businessLicense_${DateTime.now().millisecondsSinceEpoch}.jpg';

    bool uploaded = false;
    try {
      uploaded = await _storageService.uploadImageNoUrl(image.path, path);
    } on PathNotFoundException {
      rethrow; // 첨부가 사라진 경우 — 재선택 안내로 간다.
    } on FileSystemException {
      rethrow;
    } catch (e) {
      debugPrint('❌ 등록증 업로드 실패: $e');
      throw const _SaveFailure(_SaveFailureKind.uploadFailed);
    }
    if (!uploaded) throw const _SaveFailure(_SaveFailureKind.uploadFailed);

    try {
      await FirebaseFunctions.instanceFor(region: 'asia-northeast3')
          .httpsCallable('callableRegisterBusinessLicense')
          .call({'storagePath': path});
    } catch (e) {
      // CF 가 거부했다 → 방금 올린 객체는 주인이 없다. 즉시 지운다.
      debugPrint('❌ 등록증 등록(CF) 실패: $e');
      try {
        await _storageService.deleteImage(path);
      } catch (cleanupErr) {
        debugPrint('⚠️ 등록증 정리 실패 (orphan 가능): $cleanupErr');
      }
      if (e is FirebaseFunctionsException && e.code == 'permission-denied') {
        throw const _SaveFailure(_SaveFailureKind.uploadNotAuthorized);
      }
      throw const _SaveFailure(_SaveFailureKind.uploadFailed);
    }

    // 업로드가 확인된 뒤에만 임시 파일을 치운다 — 실패 시 재시도할 수 있게.
    try {
      if (await image.exists()) await image.delete();
    } catch (_) {
      debugPrint('⚠️ 임시 이미지 파일 삭제 실패 (무시 가능)');
    }
  }

  Future<String?> _uploadImage(File imageFile, String bizId, String type) async {
    final url = await _storageService.uploadBusinessImage(
      await imageFile.readAsBytes(),
      bizId,
      fileType: type == 'license' ? 'businessLicense' : null,
    );
    // [P4.3B-SAVE-02] 예전에는 `finally` 에서 **성공·실패 무관하게** 지웠다.
    //   그래서 업로드가 네트워크로 실패하면 파일이 사라지고, 사용자가
    //   "다시 저장" 을 눌러도 이제는 첨부가 없어 영영 못 올린다 —
    //   한 번 실패하면 이미지를 다시 고르는 것 말고는 길이 없었다.
    //   올라간 것이 확인됐을 때만 치운다. 실패해 남은 파일은 화면을 닫을 때
    //   (`dispose`)와 staging 청소가 정리한다.
    if (url != null) {
      try {
        if (await imageFile.exists()) await imageFile.delete();
      } catch (_) {
        debugPrint('⚠️ 임시 이미지 파일 삭제 실패 (무시 가능)');
      }
    }
    return url;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// FC-BIZ-01 OWNERSHIP FIX: _ManualAddressDialog
// controller 3개를 Dialog State가 직접 소유하고 dispose().
// ─────────────────────────────────────────────────────────────────────────────

/// [R7-P4.4E.1A §12] 저장 실패의 **종류**. 원인이 세 번 삼켜지던 자리를 막는다.
///
///   예전에는 StorageService 가 null 을 돌려주고, 폼이 일반 Exception 을 던지고,
///   마지막 catch 가 그것마저 "저장하지 못했습니다" 로 덮었다. 그래서 화면에도
///   서버 로그에도 원인이 남지 않았고, 사용자는 무엇을 하면 되는지 알 수 없었다.
///   여기서는 **무엇을 하면 되는지가 다른 것**만 구분한다.
enum _SaveFailureKind {
  /// 권한이 없어 거부됐다 — 다시 시도해도 같다.
  uploadNotAuthorized,

  /// 올리지 못했다 — 잠시 후 재시도로 풀릴 수 있다.
  uploadFailed,

  /// 사업장은 만들어졌는데 이미지 등 마무리가 남았다.
  finalizeIncomplete,
}

class _SaveFailure implements Exception {
  const _SaveFailure(this.kind);
  final _SaveFailureKind kind;

  /// 사용자에게 보여줄 문구. 내부 코드·경로는 절대 넣지 않는다.
  String get message {
    switch (kind) {
      case _SaveFailureKind.uploadNotAuthorized:
        return '첨부 파일을 업로드할 권한이 없습니다\n로그인 상태를 확인해 주세요';
      case _SaveFailureKind.uploadFailed:
        return '첨부 파일을 업로드하지 못했습니다\n잠시 후 다시 시도해 주세요';
      case _SaveFailureKind.finalizeIncomplete:
        return '사업장은 등록됐지만 사진을 올리지 못했습니다\n사업장 정보에서 다시 추가해 주세요';
    }
  }

  @override
  String toString() => '_SaveFailure(${kind.name})';
}

class _ManualAddressResult {
  final String address;
  final double? lat;
  final double? lng;
  const _ManualAddressResult({required this.address, this.lat, this.lng});
}

class _ManualAddressDialog extends StatefulWidget {
  const _ManualAddressDialog();

  @override
  State<_ManualAddressDialog> createState() => _ManualAddressDialogState();
}

class _ManualAddressDialogState extends State<_ManualAddressDialog> {
  final _addressCtrl = TextEditingController();
  final _latCtrl = TextEditingController(text: '37.5665');
  final _lngCtrl = TextEditingController(text: '126.9780');

  @override
  void dispose() {
    _addressCtrl.dispose();
    _latCtrl.dispose();
    _lngCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StyledDialog(
      title: '주소 직접 입력',
      icon: Icons.location_on,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _addressCtrl,
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
                    controller: _latCtrl,
                    decoration: const InputDecoration(labelText: '위도'),
                    keyboardType: TextInputType.number,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _lngCtrl,
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
          onPressed: () => Navigator.pop(context),
        ),
        StyledDialogButton.primary(
          text: '확인',
          onPressed: () => Navigator.pop(
            context,
            _ManualAddressResult(
              address: _addressCtrl.text,
              lat: double.tryParse(_latCtrl.text),
              lng: double.tryParse(_lngCtrl.text),
            ),
          ),
        ),
      ],
    );
  }
}
