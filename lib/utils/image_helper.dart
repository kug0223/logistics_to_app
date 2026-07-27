// lib/utils/image_helper.dart

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path_provider/path_provider.dart';
import 'dialog_helper.dart';
import 'responsive_helper.dart';
import 'toast_helper.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shimmer/shimmer.dart';
import '../theme/app_colors.dart';
import '../widgets/common/loading_widget.dart';

/// 🖼️ 이미지 관련 공용 헬퍼
/// 
/// 사용처:
/// - 사업장 이미지 업로드
/// - 업무유형 이미지 업로드
/// - 프로필 이미지
/// - 서류 이미지 (신분증, 통장 등)
class ImageHelper {
  static final ImagePicker _picker = ImagePicker();

  // ==================== 이미지 압축 설정 ====================
  
  /// 이미지 타입별 압축 설정
  static const Map<ImageType, ImageCompressConfig> _compressConfigs = {
    ImageType.profile: ImageCompressConfig(
      maxWidth: 500,
      maxHeight: 500,
      quality: 75,
      minSize: 50,  // 50KB 이하면 압축 안함
    ),
    ImageType.thumbnail: ImageCompressConfig(
      maxWidth: 400,
      maxHeight: 400,
      quality: 70,
      minSize: 30,
    ),
    ImageType.general: ImageCompressConfig(
      maxWidth: 1920,
      maxHeight: 1080,
      quality: 80,
      minSize: 100,
    ),
    ImageType.document: ImageCompressConfig(
      maxWidth: 2048,
      maxHeight: 2048,
      quality: 90,
      minSize: 200,
    ),
  };

  // ==================== 이미지 소스 선택 ====================

  /// 🎯 이미지 소스 선택 다이얼로그 (카메라/갤러리)
  /// 
  /// Returns: ImageSource.camera, ImageSource.gallery, 또는 null (취소)
  static Future<ImageSource?> showImageSourceDialog(BuildContext context) async {
    // 웹에서는 갤러리만 가능
    if (kIsWeb) return ImageSource.gallery;

    return showDialog<ImageSource>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        title: Row(
          children: [
            Icon(
              Icons.add_photo_alternate,
              color: Theme.of(context).primaryColor,
            ),
            SizedBox(width: ResponsiveHelper.spacing(context, 12)),
            Text(
              '이미지 선택',
              style: ResponsiveHelper.subtitleStyle(context),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 📷 카메라
            _buildSourceOption(
              context,
              icon: Icons.camera_alt,
              color: AppColors.info,
              label: '카메라로 촬영',
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            SizedBox(height: ResponsiveHelper.spacing(context, 8)),
            // 🖼️ 갤러리
            _buildSourceOption(
              context,
              icon: Icons.photo_library,
              color: AppColors.success,
              label: '갤러리에서 선택',
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('취소'),
          ),
        ],
      ),
    );
  }

  /// 📷 BottomSheet 스타일 이미지 소스 선택
  static Future<ImageSource?> showImageSourceBottomSheet(BuildContext context) async {
    if (kIsWeb) return ImageSource.gallery;

    return DialogHelper.showSheet<ImageSource>(
      context,
      builder: (ctx) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 핸들바
            Container(
              width: 40,
              height: 4,
              margin: EdgeInsets.symmetric(
                  vertical: ResponsiveHelper.spacing(ctx, 12)),
              decoration: BoxDecoration(
                color: AppColors.grey300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // 헤더
            Padding(
              padding: EdgeInsets.symmetric(
                  horizontal: ResponsiveHelper.spacing(ctx, 20)),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '이미지 선택',
                      style: ResponsiveHelper.subtitleStyle(ctx)
                          .copyWith(fontWeight: FontWeight.bold),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(ctx),
                    visualDensity: VisualDensity.compact,
                    color: AppColors.grey600,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            const Divider(height: 1, color: AppColors.grey200),
            const SizedBox(height: 4),
            // 카메라
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => Navigator.pop(ctx, ImageSource.camera),
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: ResponsiveHelper.spacing(ctx, 20),
                    vertical: ResponsiveHelper.spacing(ctx, 10),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: ResponsiveHelper.spacing(ctx, 44),
                        height: ResponsiveHelper.spacing(ctx, 44),
                        decoration: BoxDecoration(
                          color: AppColors.info.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Icon(Icons.camera_alt,
                            color: AppColors.info,
                            size: ResponsiveHelper.iconSize(ctx, 22)),
                      ),
                      SizedBox(width: ResponsiveHelper.spacing(ctx, 16)),
                      Expanded(
                        child: Text('카메라로 촬영',
                            style: ResponsiveHelper.bodyStyle(ctx)),
                      ),
                      const Icon(Icons.chevron_right,
                          color: AppColors.grey300, size: 20),
                    ],
                  ),
                ),
              ),
            ),
            // 갤러리
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => Navigator.pop(ctx, ImageSource.gallery),
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: ResponsiveHelper.spacing(ctx, 20),
                    vertical: ResponsiveHelper.spacing(ctx, 10),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: ResponsiveHelper.spacing(ctx, 44),
                        height: ResponsiveHelper.spacing(ctx, 44),
                        decoration: BoxDecoration(
                          color: AppColors.success.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Icon(Icons.photo_library,
                            color: AppColors.success,
                            size: ResponsiveHelper.iconSize(ctx, 22)),
                      ),
                      SizedBox(width: ResponsiveHelper.spacing(ctx, 16)),
                      Expanded(
                        child: Text('갤러리에서 선택',
                            style: ResponsiveHelper.bodyStyle(ctx)),
                      ),
                      const Icon(Icons.chevron_right,
                          color: AppColors.grey300, size: 20),
                    ],
                  ),
                ),
              ),
            ),
            SizedBox(height: ResponsiveHelper.spacing(ctx, 12)),
          ],
        );
      },
    );
  }

  static Widget _buildSourceOption(
    BuildContext context, {
    required IconData icon,
    required Color color,
    required String label,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Container(
        padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 8)),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(
          icon,
          color: color,
          size: ResponsiveHelper.iconSize(context, 24),
        ),
      ),
      title: Text(
        label,
        style: ResponsiveHelper.bodyStyle(context),
      ),
      onTap: onTap,
    );
  }

  // ==================== 단일 이미지 선택 ====================

  /// 📸 단일 이미지 선택 (다이얼로그 포함, 압축 없음)
  /// 
  /// [maxWidth]: 최대 너비 (기본 1920)
  /// [maxHeight]: 최대 높이 (기본 1080)
  /// [imageQuality]: 이미지 품질 0-100 (기본 85)
  /// [useBottomSheet]: true면 BottomSheet, false면 Dialog
  /// 
  /// Returns: 선택된 이미지 File, 취소 시 null
  static Future<File?> pickSingleImage(
    BuildContext context, {
    double maxWidth = 1920,
    double maxHeight = 1080,
    int imageQuality = 85,
    bool useBottomSheet = false,
  }) async {
    try {
      ImageSource? source;
      if (useBottomSheet) {
        source = await showImageSourceBottomSheet(context);
      } else {
        source = await showImageSourceDialog(context);
      }

      if (source == null) return null;
      if (!context.mounted) return null;

      final XFile? image = await _picker.pickImage(
        source: source,
        maxWidth: maxWidth,
        maxHeight: maxHeight,
        imageQuality: imageQuality,
      );

      if (image == null) return null;
      return File(image.path);
    } catch (e) {
      debugPrint('❌ 이미지 선택 실패: $e');
      ToastHelper.showError('이미지를 선택할 수 없습니다');
      return null;
    }
  }

  /// 📸 단일 이미지 선택 (소스 직접 지정)
  static Future<File?> pickImageFromSource(
    ImageSource source, {
    double maxWidth = 1920,
    double maxHeight = 1080,
    int imageQuality = 85,
  }) async {
    try {
      final XFile? image = await _picker.pickImage(
        source: source,
        maxWidth: maxWidth,
        maxHeight: maxHeight,
        imageQuality: imageQuality,
      );

      if (image == null) return null;
      return File(image.path);
    } catch (e) {
      debugPrint('❌ 이미지 선택 실패: $e');
      return null;
    }
  }

  // ==================== 다중 이미지 선택 ====================

  /// 🖼️ 다중 이미지 선택 (갤러리만, 압축 없음)
  /// 
  /// [maxImages]: 최대 선택 가능 개수 (0이면 무제한)
  /// [currentCount]: 현재 이미 있는 이미지 개수 (제한 체크용)
  /// 
  /// Returns: 선택된 이미지 File 리스트
  static Future<List<File>> pickMultipleImages(
    BuildContext context, {
    int maxImages = 0,
    int currentCount = 0,
    double maxWidth = 1920,
    double maxHeight = 1080,
    int imageQuality = 85,
  }) async {
    try {
      // 최대 개수 체크
      if (maxImages > 0 && currentCount >= maxImages) {
        ToastHelper.showError('최대 $maxImages장까지 추가할 수 있습니다');
        return [];
      }

      final List<XFile> images = await _picker.pickMultiImage(
        maxWidth: maxWidth,
        maxHeight: maxHeight,
        imageQuality: imageQuality,
      );

      if (images.isEmpty) return [];

      // 최대 개수 초과 시 자르기
      List<XFile> selectedImages = images;
      if (maxImages > 0) {
        final remaining = maxImages - currentCount;
        if (images.length > remaining) {
          selectedImages = images.sublist(0, remaining);
          ToastHelper.showWarning('최대 $maxImages장까지만 선택됩니다');
        }
      }

      return selectedImages.map((e) => File(e.path)).toList();
    } catch (e) {
      debugPrint('❌ 다중 이미지 선택 실패: $e');
      ToastHelper.showError('이미지를 선택할 수 없습니다');
      return [];
    }
  }

  // ==================== 이미지 압축 ====================

  /// 🗜️ 이미지 압축 (File → File)
  /// 
  /// [file]: 원본 이미지 파일
  /// [type]: 이미지 타입 (profile, thumbnail, general, document)
  /// [customConfig]: 커스텀 압축 설정 (선택)
  /// 
  /// Returns: 압축된 이미지 File
  static Future<File?> compressImage(
    File file, {
    ImageType type = ImageType.general,
    ImageCompressConfig? customConfig,
  }) async {
    try {
      if (kIsWeb) {
        debugPrint('⚠️ 웹에서는 이미지 압축 미지원');
        return file;
      }

      final config = customConfig ?? _compressConfigs[type]!;
      
      // 파일 크기 확인 (KB)
      final fileSize = await file.length() ~/ 1024;
      debugPrint('📷 원본 이미지 크기: ${fileSize}KB');
      
      // minSize 이하면 압축 안함
      if (fileSize <= config.minSize) {
        debugPrint('✅ 압축 불필요 (${config.minSize}KB 이하)');
        return file;
      }

      // 압축 실행
      final compressedBytes = await FlutterImageCompress.compressWithFile(
        file.absolute.path,
        minWidth: config.maxWidth,
        minHeight: config.maxHeight,
        quality: config.quality,
        rotate: 0,
        format: CompressFormat.jpeg,
      );

      if (compressedBytes == null) {
        debugPrint('❌ 압축 실패, 원본 반환');
        return file;
      }

      // 임시 파일로 저장 — 반환된 File은 호출자가 업로드 후 delete() 책임
      final tempDir = await getTemporaryDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final compressedFile = File('${tempDir.path}/compressed_$timestamp.jpg');
      await compressedFile.writeAsBytes(compressedBytes);

      final compressedSize = compressedBytes.length ~/ 1024;
      final reduction = ((fileSize - compressedSize) / fileSize * 100).toStringAsFixed(1);
      debugPrint('✅ 압축 완료: ${fileSize}KB → ${compressedSize}KB ($reduction% 감소)');

      return compressedFile;
    } catch (e) {
      debugPrint('❌ 이미지 압축 오류: $e');
      return file; // 실패 시 원본 반환
    }
  }

  /// 🗜️ 여러 이미지 압축
  static Future<List<File>> compressImages(
    List<File> files, {
    ImageType type = ImageType.general,
    ImageCompressConfig? customConfig,
  }) async {
    final List<File> compressedFiles = [];
    
    for (final file in files) {
      final compressed = await compressImage(
        file,
        type: type,
        customConfig: customConfig,
      );
      if (compressed != null) {
        compressedFiles.add(compressed);
      }
    }
    
    return compressedFiles;
  }

  // ==================== 선택 + 압축 통합 ====================

  /// 📸 이미지 선택 + 자동 압축 (추천!)
  /// 
  /// 선택 후 자동으로 압축해서 반환
  static Future<File?> pickAndCompressImage(
    BuildContext context, {
    ImageType type = ImageType.general,
    bool useBottomSheet = false,
  }) async {
    final file = await pickSingleImage(
      context,
      useBottomSheet: useBottomSheet,
      // ImagePicker 자체 리사이징은 최소화 (압축에서 처리)
      maxWidth: 4096,
      maxHeight: 4096,
      imageQuality: 100,
    );

    if (file == null) return null;
    
    return compressImage(file, type: type);
  }

  /// 🖼️ 다중 이미지 선택 + 자동 압축 (추천!)
  static Future<List<File>> pickAndCompressMultipleImages(
    BuildContext context, {
    ImageType type = ImageType.general,
    int maxImages = 0,
    int currentCount = 0,
  }) async {
    final files = await pickMultipleImages(
      context,
      maxImages: maxImages,
      currentCount: currentCount,
      maxWidth: 4096,
      maxHeight: 4096,
      imageQuality: 100,
    );

    if (files.isEmpty) return [];
    
    return compressImages(files, type: type);
  }

  // ==================== 이미지 정보 ====================

  /// 📊 이미지 파일 정보 가져오기
  static Future<ImageFileInfo> getImageInfo(File file) async {
    final bytes = await file.length();
    final decodedImage = await decodeImageFromList(await file.readAsBytes());
    
    return ImageFileInfo(
      width: decodedImage.width,
      height: decodedImage.height,
      sizeInBytes: bytes,
      sizeInKB: bytes ~/ 1024,
      sizeInMB: (bytes / (1024 * 1024)).toStringAsFixed(2),
    );
  }

  /// 📊 이미지 디코딩
  static Future<ui.Image> decodeImageFromList(List<int> bytes) async {
    final codec = await ui.instantiateImageCodec(Uint8List.fromList(bytes));
    final frame = await codec.getNextFrame();
    return frame.image;
  }

  // ==================== 이미지 위젯 ====================

  /// 🖼️ File 또는 URL에서 이미지 위젯 생성
  /// 
  /// [image]: File 또는 String(URL)
  /// [fit]: BoxFit (기본 cover)
  /// [placeholder]: 로딩 중 표시할 위젯
  /// [errorWidget]: 에러 시 표시할 위젯
  static Widget buildImageWidget(
    dynamic image, {
    BoxFit fit = BoxFit.cover,
    double? width,
    double? height,
    Widget? placeholder,
    Widget? errorWidget,
    BorderRadius? borderRadius,
  }) {
    Widget imageWidget;

    if (image is File) {
      // 웹에서는 path가 blob URL이므로 Image.network로 처리
      imageWidget = kIsWeb
          ? Image.network(image.path, fit: fit, width: width ?? double.infinity, height: height)
          : Image.file(image, fit: fit, width: width ?? double.infinity, height: height);
    } else if (image is String && image.isNotEmpty) {
      imageWidget = CachedNetworkImage(
        imageUrl: image,
        fit: fit,
        width: width ?? double.infinity,
        height: height,
        // 메모리 캐시 크기 제한 (원본 해상도 대신 표시 크기에 맞게 디코딩)
        memCacheWidth: width != null ? (width * 2).toInt() : 800,
        memCacheHeight: height != null ? (height * 2).toInt() : null,
        placeholder: (context, url) => placeholder ?? const LoadingWidget(),
        errorWidget: (context, url, error) => errorWidget ?? Container(
          color: AppColors.grey200,
          child: Icon(
            Icons.broken_image,
            color: AppColors.grey400,
            size: 48,
          ),
        ),
      );
    } else {
      return errorWidget ?? Container(
        color: AppColors.grey200,
        child: Icon(
          Icons.image_not_supported,
          color: AppColors.grey400,
          size: 48,
        ),
      );
    }

    if (borderRadius != null) {
      return ClipRRect(
        borderRadius: borderRadius,
        child: imageWidget,
      );
    }

  return imageWidget;
  }

  /// 🖼️ 캐시된 네트워크 이미지 위젯 (추천!)
  /// 
  /// - 디스크/메모리 캐싱 자동
  /// - Shimmer 로딩 효과
  /// - fadeIn 애니메이션
  static Widget buildCachedImage(
    String imageUrl, {
    BoxFit fit = BoxFit.cover,
    double? width,
    double? height,
    BorderRadius? borderRadius,
    Duration fadeInDuration = const Duration(milliseconds: 200),
    int? memCacheWidth,
    int? memCacheHeight,
  }) {
    Widget imageWidget = CachedNetworkImage(
      imageUrl: imageUrl,
      fit: fit,
      width: width ?? double.infinity,
      height: height,
      fadeInDuration: fadeInDuration,
      memCacheWidth: memCacheWidth,
      memCacheHeight: memCacheHeight,
      placeholder: (context, url) => Shimmer.fromColors(
        baseColor: AppColors.grey300,
        highlightColor: AppColors.grey100,
        child: Container(
          width: width ?? double.infinity,
          height: height,
          color: Colors.white,
        ),
      ),
      errorWidget: (context, url, error) => Container(
        width: width ?? double.infinity,
        height: height,
        color: AppColors.grey200,
        child: Icon(
          Icons.broken_image,
          color: AppColors.grey400,
          size: 48,
        ),
      ),
    );

    if (borderRadius != null) {
      return ClipRRect(
        borderRadius: borderRadius,
        child: imageWidget,
      );
    }

    return imageWidget;
  }

  /// 🖼️ File 또는 URL에서 캐시 이미지 위젯 생성 (통합)
  /// 
  /// File이면 Image.file, URL이면 CachedNetworkImage 사용
  static Widget buildCachedImageWidget(
    dynamic image, {
    BoxFit fit = BoxFit.cover,
    double? width,
    double? height,
    BorderRadius? borderRadius,
  }) {
    if (image is File) {
      Widget imageWidget = kIsWeb
          ? Image.network(image.path, fit: fit, width: width ?? double.infinity, height: height)
          : Image.file(image, fit: fit, width: width ?? double.infinity, height: height);

      if (borderRadius != null) {
        return ClipRRect(borderRadius: borderRadius, child: imageWidget);
      }
      return imageWidget;
    } else if (image is String && image.isNotEmpty) {
      return buildCachedImage(
        image,
        fit: fit,
        width: width,
        height: height,
        borderRadius: borderRadius,
      );
    } else {
      return Container(
        width: width ?? double.infinity,
        height: height,
        color: AppColors.grey200,
        child: Icon(
          Icons.image_not_supported,
          color: AppColors.grey400,
          size: 48,
        ),
      );
    }
  }

  /// 📷 빈 이미지 플레이스홀더
  static Widget buildEmptyPlaceholder(
    BuildContext context, {
    String? message,
    IconData icon = Icons.image_outlined,
    double? height,
    VoidCallback? onTap,
  }) {
    final content = Container(
      height: height ?? ResponsiveHelper.spacing(context, 200),
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
              icon,
              size: ResponsiveHelper.iconSize(context, 48),
              color: AppColors.grey400,
            ),
            if (message != null) ...[
              SizedBox(height: ResponsiveHelper.spacing(context, 8)),
              Text(
                message,
                style: ResponsiveHelper.bodyStyle(context).copyWith(
                  color: AppColors.grey500,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
    );

    if (onTap != null) {
      return GestureDetector(
        onTap: onTap,
        child: content,
      );
    }

    return content;
  }

  /// 🗑️ 삭제 버튼이 있는 이미지 썸네일
  static Widget buildThumbnailWithDelete(
    BuildContext context, {
    required dynamic image,
    required VoidCallback onDelete,
    double size = 80,
    BorderRadius? borderRadius,
  }) {
    return Stack(
      children: [
        Container(
          width: size,
          height: size,
          margin: EdgeInsets.only(right: ResponsiveHelper.spacing(context, 8)),
          child: ClipRRect(
            borderRadius: borderRadius ?? BorderRadius.circular(8),
            child: buildImageWidget(image, fit: BoxFit.cover),
          ),
        ),
        Positioned(
          top: 0,
          right: 4,
          child: Semantics(
            label: '이미지 삭제',
            button: true,
            child: GestureDetector(
              onTap: onDelete,
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: const BoxDecoration(
                    color: AppColors.error,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.close,
                    color: Colors.white,
                    size: 14,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// ➕ 이미지 추가 버튼
  static Widget buildAddButton(
    BuildContext context, {
    required VoidCallback onTap,
    double size = 80,
    String? label,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: AppColors.grey100,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: AppColors.grey300,
            style: BorderStyle.solid,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.add_photo_alternate,
              color: AppColors.grey500,
              size: ResponsiveHelper.iconSize(context, 24),
            ),
            if (label != null) ...[
              SizedBox(height: ResponsiveHelper.spacing(context, 4)),
              Text(
                label,
                style: ResponsiveHelper.smallStyle(context).copyWith(
                  color: AppColors.grey500,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
  // ==================== 전체화면 이미지 뷰어 ====================

  /// 🔍 전체화면 이미지 뷰어 표시
  /// 
  /// - 핀치 줌 (확대/축소)
  /// - 90도씩 회전
  /// - 닫기 버튼
  /// 
  /// [imageUrl]: 네트워크 이미지 URL
  /// [imageFile]: 로컬 파일 (imageUrl이 없을 때 사용)
  /// [title]: 상단 타이틀 (선택)
  static Future<void> showFullScreenViewer(
    BuildContext context, {
    String? imageUrl,
    File? imageFile,
    String? title,
  }) async {
    if (imageUrl == null && imageFile == null) {
      ToastHelper.showError('이미지를 불러올 수 없습니다');
      return;
    }

    await showDialog(
      context: context,
      barrierColor: AppColors.textPrimary.withValues(alpha: 0.87),
      builder: (context) => _FullScreenImageViewer(
        imageUrl: imageUrl,
        imageFile: imageFile,
        title: title,
      ),
    );
  }
  
}

// ==================== 지원 클래스 ====================

/// 이미지 타입
enum ImageType {
  profile,    // 프로필 이미지 (500x500, 75%)
  thumbnail,  // 썸네일 (400x400, 70%)
  general,    // 일반 이미지 (1920x1080, 80%)
  document,   // 문서 OCR용 (2048x2048, 90%)
}

/// 이미지 압축 설정
class ImageCompressConfig {
  final int maxWidth;
  final int maxHeight;
  final int quality;    // 0-100
  final int minSize;    // KB, 이 크기 이하면 압축 안함

  const ImageCompressConfig({
    required this.maxWidth,
    required this.maxHeight,
    required this.quality,
    this.minSize = 100,
  });
}

/// 이미지 파일 정보
class ImageFileInfo {
  final int width;
  final int height;
  final int sizeInBytes;
  final int sizeInKB;
  final String sizeInMB;

  ImageFileInfo({
    required this.width,
    required this.height,
    required this.sizeInBytes,
    required this.sizeInKB,
    required this.sizeInMB,
  });

  @override
  String toString() => '${width}x$height, ${sizeInKB}KB ($sizeInMB MB)';
}

/// 🔍 전체화면 이미지 뷰어 위젯
class _FullScreenImageViewer extends StatefulWidget {
  final String? imageUrl;
  final File? imageFile;
  final String? title;

  const _FullScreenImageViewer({
    this.imageUrl,
    this.imageFile,
    this.title,
  });

  @override
  State<_FullScreenImageViewer> createState() => _FullScreenImageViewerState();
}

class _FullScreenImageViewerState extends State<_FullScreenImageViewer> {
  final TransformationController _transformController = TransformationController();
  int _rotationQuarter = 0;  // 0, 1, 2, 3 (90도씩)

  @override
  void dispose() {
    _transformController.dispose();
    super.dispose();
  }

  void _rotateLeft() {
    setState(() {
      _rotationQuarter = (_rotationQuarter - 1) % 4;
    });
  }

  void _rotateRight() {
    setState(() {
      _rotationQuarter = (_rotationQuarter + 1) % 4;
    });
  }

  void _resetView() {
    setState(() {
      _transformController.value = Matrix4.identity();
      _rotationQuarter = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
        title: widget.title != null
            ? Text(
                widget.title!,
                style: const TextStyle(color: Colors.white, fontSize: 16),
              )
            : null,
        centerTitle: true,
        actions: [
          // 왼쪽 회전
          IconButton(
            icon: const Icon(Icons.rotate_left),
            onPressed: _rotateLeft,
            tooltip: '왼쪽으로 회전',
          ),
          // 오른쪽 회전
          IconButton(
            icon: const Icon(Icons.rotate_right),
            onPressed: _rotateRight,
            tooltip: '오른쪽으로 회전',
          ),
          // 초기화
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _resetView,
            tooltip: '초기화',
          ),
        ],
      ),
      body: Center(
        child: InteractiveViewer(
          transformationController: _transformController,
          minScale: 0.5,
          maxScale: 4.0,
          child: RotatedBox(
            quarterTurns: _rotationQuarter,
            child: _buildImage(),
          ),
        ),
      ),
    );
  }

  Widget _buildImage() {
    if (widget.imageFile != null) {
      return Image.file(
        widget.imageFile!,
        fit: BoxFit.contain,
      );
    }

    if (widget.imageUrl != null) {
      return CachedNetworkImage(
        imageUrl: widget.imageUrl!,
        fit: BoxFit.contain,
        placeholder: (context, url) => const Center(
          child: CircularProgressIndicator(color: Colors.white),
        ),
        errorWidget: (context, url, error) => const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.broken_image, color: Colors.white54, size: 48),
              SizedBox(height: 8),
              Text(
                '이미지를 불러올 수 없습니다',
                style: TextStyle(color: Colors.white54),
              ),
            ],
          ),
        ),
      );
    }

    return const Center(
      child: Icon(Icons.image_not_supported, color: Colors.white54, size: 48),
    );
  }
}
