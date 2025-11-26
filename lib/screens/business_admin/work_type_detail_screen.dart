import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'dart:io';

// Models
import '../../models/core/business_work_type_model.dart';

// Utils
import '../../utils/responsive_helper.dart';
import '../../utils/toast_helper.dart';
import '../../utils/dialog_helper.dart';
import '../../utils/navigation_helper.dart';
import '../../utils/image_helper.dart';

// Widgets
import '../../widgets/common/common_widgets.dart';

// Services
import '../../services/storage_service.dart';

/// 📦 업무유형 상세 화면
class WorkTypeDetailScreen extends StatefulWidget {
  final BusinessWorkTypeModel workType;

  const WorkTypeDetailScreen({
    super.key,
    required this.workType,
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
  List<File> _newImages = [];
  List<String> _imagesToDelete = [];

  @override
  void initState() {
    super.initState();
    _currentWorkType = widget.workType;
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
        backgroundColor: Colors.grey[50],
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

                    // 기본 정보
                    _buildBasicInfoSection(context),
                    SizedBox(height: ResponsiveHelper.spacing(context, 16)),

                    // 업무 상세
                    _buildDetailSection(context),
                    SizedBox(height: ResponsiveHelper.spacing(context, 16)),

                    // 주의사항
                    if (_currentWorkType.precautions?.isNotEmpty == true || _isEditing)
                      _buildPrecautionsSection(context),

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
    final iconColor = _currentWorkType.color != null
        ? Color(int.parse(_currentWorkType.color!.replaceFirst('#', '0xFF')))
        : Theme.of(context).primaryColor;

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
                  color: iconColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Center(
                  child: Text(
                    _currentWorkType.icon,
                    style: TextStyle(
                      fontSize: ResponsiveHelper.spacing(context, 32),
                    ),
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
                    if (_currentWorkType.oneLineIntro?.isNotEmpty == true && !_isEditing)
                      Padding(
                        padding: EdgeInsets.only(top: ResponsiveHelper.spacing(context, 4)),
                        child: Text(
                          _currentWorkType.oneLineIntro!,
                          style: ResponsiveHelper.bodyStyle(context).copyWith(
                            color: Colors.grey[600],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),

          // 수정 모드: 한 줄 소개 입력
          if (_isEditing) ...[
            SizedBox(height: ResponsiveHelper.spacing(context, 16)),
            TextField(
              controller: _oneLineIntroController,
              decoration: InputDecoration(
                labelText: '한 줄 소개',
                hintText: '예: 상품을 찾아 바구니에 담는 업무입니다',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              maxLength: 50,
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
    
    // 추가 이미지
    if (_currentWorkType.images != null) {
      for (var url in _currentWorkType.images!) {
        if (!_imagesToDelete.contains(url)) {
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
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey[300]!),
              ),
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.image_outlined,
                      size: ResponsiveHelper.iconSize(context, 48),
                      color: Colors.grey[400],
                    ),
                    SizedBox(height: ResponsiveHelper.spacing(context, 8)),
                    Text(
                      _isEditing ? '사진을 추가해주세요' : '등록된 사진이 없습니다',
                      style: ResponsiveHelper.bodyStyle(context).copyWith(
                        color: Colors.grey[500],
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
                                color: Colors.red,
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
    return ImageHelper.buildImageWidget(
      image,
      fit: fit,
      width: double.infinity,
    );
  }

  /// 기본 정보 섹션
  Widget _buildBasicInfoSection(BuildContext context) {
    return Container(
      padding: ResponsiveHelper.cardPadding(context),
      decoration: CommonWidgets.cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CommonWidgets.sectionHeader(
            context: context,
            title: '기본 정보',
            icon: Icons.info_outline,
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 16)),

          // 근무 환경
          if (_isEditing) ...[
            Text(
              '근무 환경',
              style: ResponsiveHelper.bodyStyle(context).copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            SizedBox(height: ResponsiveHelper.spacing(context, 8)),
            Wrap(
              spacing: ResponsiveHelper.spacing(context, 8),
              children: ['실내', '실외', '혼합'].map((env) {
                final isSelected = _selectedWorkEnvironment == env;
                return ChoiceChip(
                  label: Text(env),
                  selected: isSelected,
                  onSelected: (selected) {
                    setState(() {
                      _selectedWorkEnvironment = selected ? env : null;
                    });
                  },
                );
              }).toList(),
            ),
            SizedBox(height: ResponsiveHelper.spacing(context, 16)),
          ] else if (_currentWorkType.workEnvironment != null) ...[
            _buildInfoRow(
              context,
              icon: Icons.location_on_outlined,
              label: '근무 환경',
              value: _currentWorkType.workEnvironment!,
            ),
            SizedBox(height: ResponsiveHelper.spacing(context, 12)),
          ],

          // 상세 설명
          if (_isEditing) ...[
            Text(
              '상세 설명',
              style: ResponsiveHelper.bodyStyle(context).copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            SizedBox(height: ResponsiveHelper.spacing(context, 8)),
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
            Text(
              '상세 설명',
              style: ResponsiveHelper.bodyStyle(context).copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            SizedBox(height: ResponsiveHelper.spacing(context, 8)),
            Text(
              _currentWorkType.description!,
              style: ResponsiveHelper.bodyStyle(context).copyWith(
                color: Colors.grey[700],
                height: 1.5,
              ),
            ),
          ],
        ],
      ),
    );
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
              color: Colors.grey[50],
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              value!,
              style: ResponsiveHelper.bodyStyle(context).copyWith(
                color: Colors.grey[700],
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
    return Container(
      padding: ResponsiveHelper.cardPadding(context),
      decoration: CommonWidgets.cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CommonWidgets.sectionHeader(
            context: context,
            title: '주의사항',
            icon: Icons.warning_amber_outlined,
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 16)),

          if (_isEditing)
            TextField(
              controller: _precautionsController,
              decoration: InputDecoration(
                hintText: '근무 시 주의사항을 입력하세요',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              maxLines: 3,
            )
          else
            Container(
              width: double.infinity,
              padding: ResponsiveHelper.cardPadding(context),
              decoration: BoxDecoration(
                color: Colors.orange[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange[200]!),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.info_outline,
                    size: 18,
                    color: Colors.orange[700],
                  ),
                  SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                  Expanded(
                    child: Text(
                      _currentWorkType.precautions!,
                      style: ResponsiveHelper.bodyStyle(context).copyWith(
                        color: Colors.orange[800],
                        height: 1.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Row(
      children: [
        Icon(icon, size: 18, color: Colors.grey[600]),
        SizedBox(width: ResponsiveHelper.spacing(context, 8)),
        Text(
          '$label: ',
          style: ResponsiveHelper.bodyStyle(context).copyWith(
            color: Colors.grey[600],
          ),
        ),
        Text(
          value,
          style: ResponsiveHelper.bodyStyle(context).copyWith(
            fontWeight: FontWeight.w600,
          ),
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
        if (index == 0 && _newThumbnail != null) {
          _newThumbnail = null;
        } else {
          _newImages.remove(image);
        }
      } else if (image is String) {
        _imagesToDelete.add(image);
      }
      
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

      // 첫 번째 이미지를 대표이미지로
      if (thumbnailUrl == null && imageUrls.isNotEmpty) {
        thumbnailUrl = imageUrls.first;
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
      print('❌ 저장 실패: $e');
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
      print('❌ 이미지 업로드 실패: $e');
      return null;
    }
  }
}