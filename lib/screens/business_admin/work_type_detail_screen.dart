import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import 'dart:io';

// Providers
import '../../providers/user_provider.dart';

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
import '../../widgets/common/loading_widget.dart';
import '../../../widgets/work_type_icon.dart';

// Services
import '../../services/storage_service.dart';
import '../../theme/app_colors.dart';
import '../../widgets/common/gradient_scaffold.dart';

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
  bool _isDirty = false; // 편집 중 미저장 변경사항 여부
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
    // 1. 먼저 리스너 제거 — text 설정 시 _markDirty 트리거 방지 (_cancelEditing에서도 호출됨)
    for (final c in [
      _oneLineIntroController, _descriptionController,
      _requirementsController, _dutiesController, _precautionsController,
    ]) {
      c.removeListener(_markDirty);
    }
    // 2. 텍스트 설정 (리스너 없으므로 _markDirty 미트리거)
    _oneLineIntroController.text = _currentWorkType.oneLineIntro ?? '';
    _descriptionController.text = _currentWorkType.description ?? '';
    _requirementsController.text = _currentWorkType.requirements ?? '';
    _dutiesController.text = _currentWorkType.duties ?? '';
    _precautionsController.text = _currentWorkType.precautions ?? '';
    _selectedWorkEnvironment = _currentWorkType.workEnvironment;
    // 3. 리스너 재등록
    for (final c in [
      _oneLineIntroController, _descriptionController,
      _requirementsController, _dutiesController, _precautionsController,
    ]) {
      c.addListener(_markDirty);
    }
  }

  void _markDirty() {
    if (!_isDirty) setState(() => _isDirty = true);
  }

  @override
  void dispose() {
    // TMP-01: 저장/업로드되지 않고 남은 임시 압축 파일(compressed_xxx.jpg)
    // dispose 시점에 fire-and-forget으로 정리 — await 없이 catchError로 silently 처리.
    for (final file in [_newThumbnail, ..._newImages].whereType<File>()) {
      file.delete().ignore();
    }
    _oneLineIntroController.dispose();
    _descriptionController.dispose();
    _requirementsController.dispose();
    _dutiesController.dispose();
    _precautionsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_isDirty && !_hasChanges,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (_isDirty) {
          _confirmDiscardChanges();
        } else if (_hasChanges) {
          NavigationHelper.popWithChange(context);
        }
      },
      child: GradientScaffold(
        title: _isEditing ? '업무유형 수정' : '업무유형 상세',
        actions: [
          if (!_isEditing && context.select<UserProvider, bool>((p) => p.can((perm) => perm.canManageTo)))
            IconButton(
              icon: const Icon(Icons.edit, color: Colors.white),
              onPressed: () => setState(() => _isEditing = true),
              tooltip: '수정',
            )
          else
            IconButton(
              icon: const Icon(Icons.close, color: Colors.white),
              onPressed: _cancelEditing,
              tooltip: '취소',
            ),
        ],
        body: _isLoading
            ? const LoadingWidget()
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

                    SizedBox(
                      height: ResponsiveHelper.spacing(context, 32) +
                          MediaQuery.viewPaddingOf(context).bottom,
                    ),
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
                            clipBehavior: Clip.hardEdge,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: isSelected
                                    ? Theme.of(context).primaryColor
                                    : Colors.transparent,
                                width: 2,
                              ),
                            ),
                            child: _buildImageWidget(allImages[index], fit: BoxFit.cover),
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
              maxLength: 500,
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
                              _isDirty = true;
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
            maxLength: 500,
          ),
        ],
      );
    } else if (value?.isNotEmpty == true) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: ResponsiveHelper.iconSize(context, 18), color: Theme.of(context).primaryColor),
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
              maxLength: 300,
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
      onPressed: _isLoading ? null : _saveChanges,
      isLoading: _isLoading,
      icon: Icons.save,
    );
  }

  // ==================== 기능 메서드 ====================

  /// 이미지 선택
  Future<void> _pickImages() async {
    try {
      final image = await ImageHelper.pickAndCompressImage(
        context,
        type: ImageType.general,
        useBottomSheet: true,
      );
      if (image != null) {
        if (!mounted) return; // [MOUNTED-01 수정] 이미지 피커 복귀 시 위젯 dispose 경합 방지
        setState(() { _newImages.add(image); _isDirty = true; });
      }
    } catch (e) {
      debugPrint('❌ 이미지 선택 오류: $e');
      if (mounted) ToastHelper.showError('이미지를 불러오는 데 실패했습니다.');
    }
  }

  /// 이미지 삭제
  void _deleteImage(int index, List<dynamic> allImages) {
    final image = allImages[index];

    setState(() {
      _isDirty = true;
      if (image is File) {
        // TMP-01: 선택 취소된 임시 압축 파일 즉시 정리 (fire-and-forget)
        image.delete().ignore();
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

  Future<void> _confirmDiscardChanges() async {
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('변경사항 취소'),
        content: const Text('저장하지 않은 변경사항이 있습니다.\n나가시겠습니까?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('계속 수정')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('나가기')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _isDirty = false);
    if (_hasChanges) {
      NavigationHelper.popWithChange(context);
    } else {
      Navigator.pop(context);
    }
  }

  /// 수정 취소
  void _cancelEditing() {
    // TMP-01: 수정 취소 시 미업로드 임시 압축 파일 정리 (fire-and-forget)
    for (final file in [_newThumbnail, ..._newImages].whereType<File>()) {
      file.delete().ignore();
    }
    setState(() {
      _isEditing = false;
      _isDirty = false;
      _initControllers();
      _newThumbnail = null;
      _newImages.clear();
      _imagesToDelete.clear();
    });
  }

  /// 변경사항 저장
  ///
  /// CLAUDE.md 삭제 순서 규칙: Storage 삭제 전 Firestore를 먼저 업데이트한다.
  /// Firestore 업데이트 실패 시 Storage는 건드리지 않아 broken URL 잔류를 방지한다.
  Future<void> _saveChanges() async {
    if (_isLoading) return; // 이중 탭 방어
    setState(() => _isLoading = true);

    final List<String> newlyUploadedUrls = [];
    try {
      // 1. 새 이미지 업로드 (Firestore 업데이트 전) — 실패 시 catch에서 newlyUploadedUrls 롤백
      String? thumbnailUrl = _currentWorkType.thumbnailUrl;
      if (_imagesToDelete.contains(thumbnailUrl)) {
        thumbnailUrl = null;
      }

      if (_newThumbnail != null) {
        thumbnailUrl = await _uploadImage(_newThumbnail!, 'thumbnail');
        if (thumbnailUrl == null) {
          if (mounted) ToastHelper.showError('썸네일 업로드에 실패했습니다. 다시 시도해주세요.');
          return; // null URL로 Firestore 저장 방지, finally에서 _isLoading 초기화
        }
        newlyUploadedUrls.add(thumbnailUrl);
      }

      List<String> imageUrls = [];
      if (_currentWorkType.images != null) {
        imageUrls = _currentWorkType.images!
            .where((url) => !_imagesToDelete.contains(url))
            .toList();
      }

      // 이미지 업로드 병렬 실행
      final uploadResults = await Future.wait(
        _newImages.map((image) => _uploadImage(image, 'image')),
      );
      if (!mounted) return;
      for (final url in uploadResults) {
        if (url != null) {
          imageUrls.add(url);
          newlyUploadedUrls.add(url);
        }
      }

      // 첫 번째 이미지를 대표이미지로 (images 배열에서는 제외)
      if (thumbnailUrl == null && imageUrls.isNotEmpty) {
        thumbnailUrl = imageUrls.removeAt(0);  // 첫 번째 이미지를 꺼내서 대표로
      }

      // 2. Firestore 업데이트 (삭제 이전에 반드시 선행)
      // 이유: Firestore 실패 시 Storage는 건드리지 않아야 broken URL이 남지 않음
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

      // 3. Firestore 성공 후에만 Storage에서 구 이미지 삭제
      // 이유: Firestore 실패 시 Storage 삭제를 했다면 broken URL이 Firestore에 남음
      await Future.wait(_imagesToDelete.map((url) async {
        try {
          await _storageService.deleteImageByUrl(url);
        } catch (e) {
          debugPrint('⚠️ Storage 구 이미지 삭제 실패 (orphan): $e');
        }
      }));

      // 4. 로컬 상태 업데이트
      if (!mounted) return;
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
        _isDirty = false;
        _hasChanges = true;
        _newThumbnail = null;
        _newImages.clear();
        _imagesToDelete.clear();
      });

      if (mounted) ToastHelper.showSuccess('업무유형이 수정되었습니다');
    } catch (e) {
      // Firestore 실패 시 이미 업로드된 신규 파일 롤백
      await Future.wait(newlyUploadedUrls.map((url) async {
        try { await _storageService.deleteImageByUrl(url); } catch (_) {}
      }));
      debugPrint('❌ 저장 실패: $e');
      if (mounted) ToastHelper.showError('저장에 실패했습니다');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// 이미지 업로드 — CF 경유 (storage.rules: businesses/ if false)
  Future<String?> _uploadImage(File imageFile, String type) async {
    try {
      final bytes = await imageFile.readAsBytes();
      final url = await _storageService.uploadBusinessImage(
        bytes,
        _currentWorkType.businessId,
      );
      // TMP-01: pickAndCompressImage()가 생성한 임시 압축 파일은 업로드 후 즉시 삭제
      try {
        if (await imageFile.exists()) await imageFile.delete();
      } catch (_) {
        debugPrint('⚠️ 임시 이미지 파일 삭제 실패 (무시 가능)');
      }
      return url;
    } catch (e) {
      debugPrint('❌ 이미지 업로드 실패: $e');
      return null;
    }
  }
}
