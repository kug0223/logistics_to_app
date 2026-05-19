import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:io';

// Models
import '../../models/core/business_work_type_model.dart';

// Utils
import '../../utils/responsive_helper.dart';
import '../../utils/toast_helper.dart';
import '../../utils/navigation_helper.dart';
import '../../utils/image_helper.dart';
import '../../../utils/format_helper.dart';

// Widgets
import '../../widgets/common/common_widgets.dart';
import '../../../widgets/work_type_icon.dart';

// Services
import '../../services/storage_service.dart';
import '../../theme/app_colors.dart';

/// 📦 업무유형 상세 화면
class WorkTypeDetailScreen extends StatefulWidget {
  final BusinessWorkTypeModel workType;
  final bool initialEditMode;  // ⭐ 추가

  const WorkTypeDetailScreen({
    super.key,
    required this.workType,
    this.initialEditMode = false,  // ⭐ 기본값 false
  });

  @override
  State<WorkTypeDetailScreen> createState() => _WorkTypeDetailScreenState();
}

class _WorkTypeDetailScreenState extends State<WorkTypeDetailScreen> {
  late BusinessWorkTypeModel _currentWorkType;
  final StorageService _storageService = StorageService();
  
  bool _isLoading = false;
  bool _isEditing = false;
  bool _hasChanges = false;
  int _currentImageIndex = 0;

  // 수정용 컨트롤러
  final _oneLineIntroController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _requirementsController = TextEditingController();
  final _dutiesController = TextEditingController();
  final _precautionsController = TextEditingController();
  String? _selectedWorkEnvironment;

  // 이미지 관련
  File? _newThumbnail;
  final List<File> _newImages = [];
  final List<String> _imagesToDelete = [];

  @override
  void initState() {
    super.initState();
    _currentWorkType = widget.workType;
    _isEditing = widget.initialEditMode;  // ⭐ 추가
    _initControllers();
  }

  void _initControllers() {
    _oneLineIntroController.text = _currentWorkType.oneLineIntro ?? '';
    _descriptionController.text = _currentWorkType.description ?? '';
    _requirementsController.text = _currentWorkType.requirements ?? '';
    _dutiesController.text = _currentWorkType.duties ?? '';
    _precautionsController.text = _currentWorkType.precautions ?? '';
    _selectedWorkEnvironment = _currentWorkType.workEnvironment;
  }

  @override
  void dispose() {
    _oneLineIntroController.dispose();
    _descriptionController.dispose();
    _requirementsController.dispose();
    _dutiesController.dispose();
    _precautionsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return PopScope(
      canPop: !_hasChanges,
      onPopInvokedWithResult: (didPop, result) async {
        if (!didPop && _hasChanges) {
          NavigationHelper.popWithChange(context);
        }
      },
      child: Scaffold(
        backgroundColor: AppColors.grey50,
        appBar: AppBar(
          title: Text(_isEditing ? '업무유형 수정' : '업무유형 상세'),
          backgroundColor: theme.primaryColor,
          foregroundColor: Colors.white,
          actions: [
            if (!_isEditing)
              IconButton(
                icon: const Icon(Icons.edit),
                onPressed: () => setState(() => _isEditing = true),
                tooltip: '수정',
              )
            else
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: _cancelEditing,
                tooltip: '취소',
              ),
          ],
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                padding: ResponsiveHelper.screenPadding(context),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 헤더 카드 (아이콘 + 이름)
                    _buildHeaderCard(context),
                    SizedBox(height: ResponsiveHelper.spacing(context, 16)),

                    // 이미지 갤러리
                    _buildImageSection(context),
                    SizedBox(height: ResponsiveHelper.spacing(context, 16)),

                    // 상세 설명
                    _buildDescriptionSection(context),
                    SizedBox(height: ResponsiveHelper.spacing(context, 16)),

                    // 근무 환경
                    if (_currentWorkType.workEnvironment != null || _isEditing) ...[
                      _buildWorkEnvironmentSection(context),
                      SizedBox(height: ResponsiveHelper.spacing(context, 16)),
                    ],

                    // 준비사항
                    if (_currentWorkType.precautions?.isNotEmpty == true || _isEditing) ...[
                      _buildPrecautionsSection(context),
                      SizedBox(height: ResponsiveHelper.spacing(context, 16)),
                    ],

                    // 업무 상세
                    _buildDetailSection(context),
                    SizedBox(height: ResponsiveHelper.spacing(context, 16)),

                    // 저장 버튼 (수정 모드일 때)
                    if (_isEditing) ...[
                      SizedBox(height: ResponsiveHelper.spacing(context, 24)),
                      _buildSaveButton(context),
                    ],

                    SizedBox(height: ResponsiveHelper.spacing(context, 32)),
                  ],
                ),
              ),
      ),
    );
  }

  /// 헤더 카드 (아이콘 + 이름 + 한 줄 소개)
  Widget _buildHeaderCard(BuildContext context) {
    return Container(
      padding: ResponsiveHelper.cardPadding(context),
      decoration: CommonWidgets.cardDecoration(),
      child: Column(
        children: [
          // 아이콘 + 이름
          Row(
            children: [
              Container(
                width: ResponsiveHelper.spacing(context, 60),
                height: ResponsiveHelper.spacing(context, 60),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      FormatHelper.parseColor(_currentWorkType.backgroundColor ?? '#2196F3'),
                      FormatHelper.parseColor(_currentWorkType.backgroundColor ?? '#2196F3').withValues(alpha: 0.8),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: FormatHelper.parseColor(_currentWorkType.backgroundColor ?? '#2196F3').withValues(alpha: 0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Center(
                  child: WorkTypeIcon.build(
                    _currentWorkType,
                    size: ResponsiveHelper.spacing(context, 32),
                  ),
                ),
              ),
              SizedBox(width: ResponsiveHelper.spacing(context, 16)),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                      Text(
                      _currentWorkType.name,
                      style: ResponsiveHelper.titleStyle(context).copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          // 한 줄 소개
          if (_isEditing) ...[
            SizedBox(height: ResponsiveHelper.spacing(context, 16)),
            TextField(
              controller: _oneLineIntroController,
              decoration: InputDecoration(
                labelText: '한 줄 소개',
                hintText: '예: 상품을 찾아 바구니에 담는 업무입니다',
                prefixIcon: Icon(Icons.format_quote, color: Theme.of(context).primaryColor),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              maxLength: 50,
            ),
          ] else if (_currentWorkType.oneLineIntro?.isNotEmpty == true) ...[
            SizedBox(height: ResponsiveHelper.spacing(context, 16)),
            Container(
              padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 12)),
              decoration: BoxDecoration(
                color: Theme.of(context).primaryColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.format_quote,
                    size: ResponsiveHelper.iconSize(context, 18),
                    color: Theme.of(context).primaryColor,
                  ),
                  SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                  Expanded(
                    child: Text(
                      _currentWorkType.oneLineIntro!,
                      style: ResponsiveHelper.bodyStyle(context).copyWith(
                        fontStyle: FontStyle.italic,
                        color: Theme.of(context).primaryColor,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// 이미지 섹션
  Widget _buildImageSection(BuildContext context) {
    final allImages = <dynamic>[];
    
    // 대표 이미지
    if (_newThumbnail != null) {
      allImages.add(_newThumbnail);
    } else if (_currentWorkType.thumbnailUrl != null) {
      allImages.add(_currentWorkType.thumbnailUrl);
    }
    
    // 추가 이미지 (대표 이미지와 중복 제외)
    if (_currentWorkType.images != null) {
      for (var url in _currentWorkType.images!) {
        if (!_imagesToDelete.contains(url) && url != _currentWorkType.thumbnailUrl) {
          allImages.add(url);
        }
      }
    }
    allImages.addAll(_newImages);

    return Container(
      decoration: CommonWidgets.cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 헤더
          Padding(
            padding: ResponsiveHelper.cardPadding(context),
            child: Row(
              children: [
                Icon(
                  Icons.photo_library,
                  size: ResponsiveHelper.iconSize(context, 20),
                  color: Theme.of(context).primaryColor,
                ),
                SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                Text(
                  '업무 사진',
                  style: ResponsiveHelper.subtitleStyle(context).copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                if (_isEditing)
                  TextButton.icon(
                    onPressed: _pickImages,
                    icon: Icon(Icons.add_photo_alternate, size: ResponsiveHelper.iconSize(context, 18)),
                    label: const Text('추가'),
                  ),
              ],
            ),
          ),

          // 이미지 영역
          if (allImages.isEmpty)
            Container(
              height: ResponsiveHelper.spacing(context, 200),
              margin: EdgeInsets.all(ResponsiveHelper.spacing(context, 16)),
              decoration: BoxDecoration(
                color: AppColors.grey100,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.grey300),
              ),
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.image_outlined,
                      size: ResponsiveHelper.iconSize(context, 48),
                      color: AppColors.grey400,
                    ),
                    SizedBox(height: ResponsiveHelper.spacing(context, 8)),
                    Text(
                      _isEditing ? '사진을 추가해주세요' : '등록된 사진이 없습니다',
                      style: ResponsiveHelper.bodyStyle(context).copyWith(
                        color: AppColors.grey500,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            Column(
              children: [
                // 메인 이미지
                Container(
                  height: ResponsiveHelper.spacing(context, 200),
                  margin: EdgeInsets.symmetric(
                    horizontal: ResponsiveHelper.spacing(context, 16),
                  ),
                  child: Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: _buildImageWidget(allImages[_currentImageIndex]),
                      ),
                      // 삭제 버튼 (수정 모드)
                      if (_isEditing)
                        Positioned(
                          top: 8,
                          right: 8,
                          child: IconButton(
                            onPressed: () => _deleteImage(_currentImageIndex, allImages),
                            icon: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: const BoxDecoration(
                                color: AppColors.error,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.close, color: Colors.white, size: 16),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),

                // 썸네일 리스트
                if (allImages.length > 1)
                  Container(
                    height: ResponsiveHelper.spacing(context, 70),
                    margin: EdgeInsets.only(
                      top: ResponsiveHelper.spacing(context, 12),
                      bottom: ResponsiveHelper.spacing(context, 16),
                    ),
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      padding: EdgeInsets.symmetric(
                        horizontal: ResponsiveHelper.spacing(context, 16),
                      ),
                      itemCount: allImages.length,
                      itemBuilder: (context, index) {
                        final isSelected = index == _currentImageIndex;
                        return GestureDetector(
                          onTap: () => setState(() => _currentImageIndex = index),
                          child: Container(
                            width: ResponsiveHelper.spacing(context, 70),
                            margin: EdgeInsets.only(
                              right: ResponsiveHelper.spacing(context, 8),
                            ),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: isSelected
                                    ? Theme.of(context).primaryColor
                                    : Colors.transparent,
                                width: 2,
                              ),
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(6),
                              child: _buildImageWidget(allImages[index], fit: BoxFit.cover),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildImageWidget(dynamic image, {BoxFit fit = BoxFit.cover}) {
    return ImageHelper.buildCachedImageWidget(
      image,
      fit: fit,
      width: double.infinity,
    );
  }

  /// 상세 설명 섹션
  Widget _buildDescriptionSection(BuildContext context) {
    return Container(
      padding: ResponsiveHelper.cardPadding(context),
      decoration: CommonWidgets.cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CommonWidgets.sectionHeader(
            context: context,
            title: '상세 설명',
            icon: Icons.description_outlined,
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 16)),

          // 상세 설명
          if (_isEditing) ...[
            TextField(
              controller: _descriptionController,
              decoration: InputDecoration(
                hintText: '업무에 대한 상세 설명을 입력하세요',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              maxLines: 4,
            ),
          ] else if (_currentWorkType.description?.isNotEmpty == true) ...[
            Container(
              width: double.infinity,
              padding: ResponsiveHelper.cardPadding(context),
              decoration: BoxDecoration(
                color: AppColors.grey50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                _currentWorkType.description!,
                style: ResponsiveHelper.bodyStyle(context).copyWith(
                  color: AppColors.grey700,
                  height: 1.5,
                ),
              ),
            ),
          ] else ...[
            Text(
              '등록된 상세 설명이 없습니다',
              style: ResponsiveHelper.bodyStyle(context).copyWith(
                color: AppColors.grey500,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ],
      ),
    );
  }
  /// 근무 환경 섹션 (사업장 상세 스타일)
  Widget _buildWorkEnvironmentSection(BuildContext context) {
    final theme = Theme.of(context);
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CommonWidgets.sectionHeader(
          context: context,
          title: '근무 환경',
          icon: Icons.location_on_outlined,
        ),
        SizedBox(height: ResponsiveHelper.spacing(context, 12)),
        
        Container(
          width: double.infinity,  // ← 너비 맞춤 추가
          decoration: CommonWidgets.cardDecoration(),
          padding: ResponsiveHelper.cardPadding(context),
          child: _isEditing
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '근무 환경을 선택하세요',
                      style: ResponsiveHelper.bodyStyle(context).copyWith(
                        color: AppColors.grey600,
                      ),
                    ),
                    SizedBox(height: ResponsiveHelper.spacing(context, 12)),
                    Wrap(
                      spacing: ResponsiveHelper.spacing(context, 8),
                      runSpacing: ResponsiveHelper.spacing(context, 8),  // ← 줄바꿈 간격 추가
                      children: ['실내(상온)', '실내(냉장)', '실내(냉동)', '실외', '혼합'].map((env) {
                        final isSelected = _selectedWorkEnvironment == env;
                        return ChoiceChip(
                          label: Text(env),
                          selected: isSelected,
                          onSelected: (selected) {
                            setState(() {
                              _selectedWorkEnvironment = selected ? env : null;
                            });
                          },
                          selectedColor: theme.primaryColor,
                          checkmarkColor: Colors.white,
                          labelStyle: ResponsiveHelper.bodyStyle(context).copyWith(
                            color: isSelected ? Colors.white : AppColors.grey700,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                          ),
                          side: BorderSide(
                            color: isSelected ? theme.primaryColor : AppColors.grey300,
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                )
              : _buildEnvironmentItem(
                  context,
                  _getWorkEnvironmentIcon(_currentWorkType.workEnvironment!),
                  '근무 장소',
                  _currentWorkType.workEnvironment!,
                ),
        ),
      ],
    );
  }

  /// 환경 항목 (사업장 상세 _buildFacilityItem 스타일)
  Widget _buildEnvironmentItem(
    BuildContext context,
    IconData icon,
    String label,
    String value,
  ) {
    final theme = Theme.of(context);
    
    return Row(
      children: [
        Container(
          padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 8)),
          decoration: BoxDecoration(
            color: theme.primaryColor.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            icon,
            size: ResponsiveHelper.iconSize(context, 20),
            color: theme.primaryColor,
          ),
        ),
        SizedBox(width: ResponsiveHelper.spacing(context, 12)),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: ResponsiveHelper.smallStyle(context).copyWith(
                  color: AppColors.grey600,
                ),
              ),
              SizedBox(height: ResponsiveHelper.spacing(context, 2)),
              Text(
                value,
                style: ResponsiveHelper.bodyStyle(context).copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        Icon(
          Icons.check_circle,
          size: ResponsiveHelper.iconSize(context, 20),
          color: AppColors.success,
        ),
      ],
    );
  }

  /// 근무환경별 아이콘 반환
  IconData _getWorkEnvironmentIcon(String env) {
    switch (env) {
      case '실내(상온)':
        return Icons.warehouse_outlined;
      case '실내(냉장)':
        return Icons.ac_unit_outlined;
      case '실내(냉동)':
        return Icons.severe_cold;
      case '실외':
        return Icons.wb_sunny_outlined;
      case '혼합':
        return Icons.sync_alt;
      default:
        return Icons.location_on_outlined;
    }
  }

  /// 업무 상세 섹션
  Widget _buildDetailSection(BuildContext context) {
    return Container(
      padding: ResponsiveHelper.cardPadding(context),
      decoration: CommonWidgets.cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CommonWidgets.sectionHeader(
            context: context,
            title: '업무 상세',
            icon: Icons.assignment_outlined,
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 16)),

          // 자격 요건
          _buildDetailField(
            context,
            label: '자격 요건',
            controller: _requirementsController,
            hint: '예: 성인 남녀 누구나, 무거운 물건(10kg 이상) 들 수 있는 분',
            value: _currentWorkType.requirements,
            icon: Icons.check_circle_outline,
          ),

          SizedBox(height: ResponsiveHelper.spacing(context, 16)),

          // 주요 업무
          _buildDetailField(
            context,
            label: '주요 업무',
            controller: _dutiesController,
            hint: '예: 상품 피킹, 바코드 스캔, 포장 작업',
            value: _currentWorkType.duties,
            icon: Icons.work_outline,
          ),
        ],
      ),
    );
  }

  Widget _buildDetailField(
    BuildContext context, {
    required String label,
    required TextEditingController controller,
    required String hint,
    required String? value,
    required IconData icon,
  }) {
    if (_isEditing) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: ResponsiveHelper.bodyStyle(context).copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 8)),
          TextField(
            controller: controller,
            decoration: InputDecoration(
              hintText: hint,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            maxLines: 3,
          ),
        ],
      );
    } else if (value?.isNotEmpty == true) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: Theme.of(context).primaryColor),
              SizedBox(width: ResponsiveHelper.spacing(context, 8)),
              Text(
                label,
                style: ResponsiveHelper.bodyStyle(context).copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 8)),
          Container(
            width: double.infinity,
            padding: ResponsiveHelper.cardPadding(context),
            decoration: BoxDecoration(
              color: AppColors.grey50,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              value!,
              style: ResponsiveHelper.bodyStyle(context).copyWith(
                color: AppColors.grey700,
                height: 1.5,
              ),
            ),
          ),
        ],
      );
    }
    return const SizedBox.shrink();
  }

  /// 주의사항 섹션
  Widget _buildPrecautionsSection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CommonWidgets.sectionHeader(
          context: context,
          title: '준비사항',
          icon: Icons.warning_amber_outlined,
        ),
        SizedBox(height: ResponsiveHelper.spacing(context, 12)),

        if (_isEditing)
          Container(
            padding: ResponsiveHelper.cardPadding(context),
            decoration: CommonWidgets.cardDecoration(),
            child: TextField(
              controller: _precautionsController,
              decoration: InputDecoration(
                hintText: '예: 냉장 3~5도(따뜻한 복장 권장)\n냉동 -18도(냉동복 제공)',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              maxLines: 3,
            ),
          )
        else
          CommonWidgets.infoCard(
            context: context,
            message: _currentWorkType.precautions!,
            icon: Icons.info_outline,
            color: AppColors.warningDark,
          ),
      ],
    );
  }

  /// 저장 버튼
  Widget _buildSaveButton(BuildContext context) {
    return CommonWidgets.primaryButton(
      context: context,
      text: '저장',
      onPressed: _saveChanges,
      icon: Icons.save,
    );
  }

  // ==================== 기능 메서드 ====================

  /// 이미지 선택
  Future<void> _pickImages() async {
    final image = await ImageHelper.pickAndCompressImage(
      context,
      type: ImageType.general,
      useBottomSheet: true,
    );

    if (image != null) {
      setState(() => _newImages.add(image));
    }
  }

  /// 이미지 삭제
  void _deleteImage(int index, List<dynamic> allImages) {
    final image = allImages[index];
    
    setState(() {
      if (image is File) {
        if (_newThumbnail == image) {
          _newThumbnail = null;
        } else {
          _newImages.remove(image);
        }
      } else if (image is String) {
        _imagesToDelete.add(image);
        // 대표 이미지도 삭제 목록에 포함되었는지 체크
        if (image == _currentWorkType.thumbnailUrl) {
          // 대표 이미지 삭제 시 처리됨
        }
      }
      
      // 현재 인덱스 조정
      if (_currentImageIndex >= allImages.length - 1 && _currentImageIndex > 0) {
        _currentImageIndex--;
      }
    });
  }

  /// 수정 취소
  void _cancelEditing() {
    setState(() {
      _isEditing = false;
      _initControllers();
      _newThumbnail = null;
      _newImages.clear();
      _imagesToDelete.clear();
    });
  }

  /// 변경사항 저장
  Future<void> _saveChanges() async {
    setState(() => _isLoading = true);

    try {
      // 1. 삭제할 이미지 처리
      for (var url in _imagesToDelete) {
        await _storageService.deleteImageByUrl(url);
      }

      // 2. 새 이미지 업로드
      String? thumbnailUrl = _currentWorkType.thumbnailUrl;
      if (_imagesToDelete.contains(thumbnailUrl)) {
        thumbnailUrl = null;
      }
      
      if (_newThumbnail != null) {
        thumbnailUrl = await _uploadImage(_newThumbnail!, 'thumbnail');
      }

      List<String> imageUrls = [];
      if (_currentWorkType.images != null) {
        imageUrls = _currentWorkType.images!
            .where((url) => !_imagesToDelete.contains(url))
            .toList();
      }

      for (var image in _newImages) {
        final url = await _uploadImage(image, 'image');
        if (url != null) imageUrls.add(url);
      }

      // 첫 번째 이미지를 대표이미지로 (images 배열에서는 제외)
      if (thumbnailUrl == null && imageUrls.isNotEmpty) {
        thumbnailUrl = imageUrls.removeAt(0);  // 첫 번째 이미지를 꺼내서 대표로
      }

      // 3. Firestore 업데이트
      final updateData = {
        'oneLineIntro': _oneLineIntroController.text.trim().isEmpty 
            ? null 
            : _oneLineIntroController.text.trim(),
        'description': _descriptionController.text.trim().isEmpty 
            ? null 
            : _descriptionController.text.trim(),
        'workEnvironment': _selectedWorkEnvironment,
        'requirements': _requirementsController.text.trim().isEmpty 
            ? null 
            : _requirementsController.text.trim(),
        'duties': _dutiesController.text.trim().isEmpty 
            ? null 
            : _dutiesController.text.trim(),
        'precautions': _precautionsController.text.trim().isEmpty 
            ? null 
            : _precautionsController.text.trim(),
        'thumbnailUrl': thumbnailUrl,
        'images': imageUrls.isEmpty ? null : imageUrls,
      };

      await FirebaseFirestore.instance
          .collection('businesses')
          .doc(_currentWorkType.businessId)
          .collection('workTypes')
          .doc(_currentWorkType.id)
          .update(updateData);

      // 4. 로컬 상태 업데이트
      setState(() {
        _currentWorkType = _currentWorkType.copyWith(
          oneLineIntro: updateData['oneLineIntro'] as String?,
          description: updateData['description'] as String?,
          workEnvironment: updateData['workEnvironment'] as String?,
          requirements: updateData['requirements'] as String?,
          duties: updateData['duties'] as String?,
          precautions: updateData['precautions'] as String?,
          thumbnailUrl: thumbnailUrl,
          images: imageUrls.isEmpty ? null : imageUrls,
        );
        _isEditing = false;
        _hasChanges = true;
        _newThumbnail = null;
        _newImages.clear();
        _imagesToDelete.clear();
      });

      ToastHelper.showSuccess('업무유형이 수정되었습니다');
    } catch (e) {
      debugPrint('❌ 저장 실패: $e');
      ToastHelper.showError('저장에 실패했습니다');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  /// 이미지 업로드
  Future<String?> _uploadImage(File imageFile, String type) async {
    try {
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final fileName = 'workType_${_currentWorkType.id}_${type}_$timestamp.jpg';
      final storagePath = 'businesses/${_currentWorkType.businessId}/workTypes/$fileName';
      
      return await _storageService.uploadImage(imageFile.path, storagePath);
    } catch (e) {
      debugPrint('❌ 이미지 업로드 실패: $e');
      return null;
    }
  }
}
