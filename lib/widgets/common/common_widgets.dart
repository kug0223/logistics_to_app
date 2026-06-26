// lib/widgets/common/common_widgets.dart

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../utils/responsive_helper.dart';
import '../../theme/app_colors.dart';

/// 🎨 앱 전체에서 사용하는 공통 위젯 모음
/// 디자인 일관성을 위해 이 위젯들을 사용하세요!
class CommonWidgets {
  
  /// 📦 기본 카드 스타일
  static BoxDecoration cardDecoration({Color? color}) {
    return BoxDecoration(
      color: color ?? AppColors.surface,
      borderRadius: BorderRadius.circular(20),
      boxShadow: [
        BoxShadow(
          color: AppColors.grey500.withValues(alpha: 0.1),
          blurRadius: 10,
          offset: const Offset(0, 4),
        ),
      ],
    );
  }

  /// 설정/프로필/서류 화면 컴팩트 카드 데코레이션 (radius 12, 가벼운 그림자)
  static BoxDecoration compactCardDecoration({Color? color}) {
    return BoxDecoration(
      color: color ?? AppColors.surface,
      borderRadius: BorderRadius.circular(12),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.05),
          blurRadius: 4,
          offset: const Offset(0, 1),
        ),
      ],
    );
  }
  
  /// 🎨 그라데이션 카드 데코레이션
  static BoxDecoration gradientCardDecoration({
    required Color color,
    double opacity = 0.8,
  }) {
    return BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          color,
          color.withValues(alpha: opacity),
        ],
      ),
      borderRadius: BorderRadius.circular(20),
      boxShadow: [
        BoxShadow(
          color: color.withValues(alpha: 0.3),
          blurRadius: 12,
          offset: const Offset(0, 6),
        ),
      ],
    );
  }
  
  /// 🔘 기본 버튼
  /// onPressed == null 이면 disabled 스타일(회색 배경, 회색 텍스트)로 표시
  static Widget primaryButton({
    required BuildContext context,
    required String text,
    required VoidCallback? onPressed,
    bool isLoading = false,
    IconData? icon,
  }) {
    final theme = Theme.of(context);
    final isDisabled = !isLoading && onPressed == null;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: isDisabled
            ? null
            : LinearGradient(
                colors: [
                  theme.primaryColor,
                  theme.primaryColor.withValues(alpha: 0.8),
                ],
              ),
        color: isDisabled ? AppColors.grey200 : null,
        borderRadius: BorderRadius.circular(12),
        boxShadow: isDisabled
            ? null
            : [
                BoxShadow(
                  color: theme.primaryColor.withValues(alpha: 0.4),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
              ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: isLoading || isDisabled ? null : onPressed,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: EdgeInsets.symmetric(
              vertical: ResponsiveHelper.spacing(context, 16),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (isLoading)
                  SizedBox(
                    width: ResponsiveHelper.iconSize(context, 20),
                    height: ResponsiveHelper.iconSize(context, 20),
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                else ...[
                  if (icon != null) ...[
                    Icon(
                      icon,
                      color: isDisabled ? AppColors.grey500 : Colors.white,
                      size: ResponsiveHelper.iconSize(context, 20),
                    ),
                    SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                  ],
                  Text(
                    text,
                    style: ResponsiveHelper.bodyStyle(context).copyWith(
                      color: isDisabled ? AppColors.grey500 : Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
  
  /// 🔘 아웃라인 버튼
  static Widget outlineButton({
    required BuildContext context,
    required String text,
    required VoidCallback onPressed,
    Color? color,
    IconData? icon,
  }) {
    final theme = Theme.of(context);
    final buttonColor = color ?? theme.primaryColor;
    
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        border: Border.all(color: buttonColor, width: 2),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: EdgeInsets.symmetric(
              vertical: ResponsiveHelper.spacing(context, 16),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (icon != null) ...[
                  Icon(
                    icon,
                    color: buttonColor,
                    size: ResponsiveHelper.iconSize(context, 20),
                  ),
                  SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                ],
                Text(
                  text,
                  style: ResponsiveHelper.bodyStyle(context).copyWith(
                    color: buttonColor,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
  
  /// 📝 통일된 텍스트 입력 필드
  static Widget textField({
    required BuildContext context,
    required TextEditingController controller,
    required String label,
    String? hint,
    IconData? icon,
    bool obscureText = false,
    bool readOnly = false,
    bool enabled = true,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
    String? Function(String?)? validator,
    void Function(String)? onChanged,
    Widget? suffixIcon,
    VoidCallback? onTap,
    FocusNode? focusNode,
    TextInputAction? textInputAction,
    void Function(String)? onFieldSubmitted,
    int? maxLength,
  }) {
    final theme = Theme.of(context);
    return TextFormField(
      controller: controller,
      focusNode: focusNode,
      obscureText: obscureText,
      readOnly: readOnly,
      enabled: enabled,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      textInputAction: textInputAction,
      onFieldSubmitted: onFieldSubmitted,
      onChanged: onChanged,
      maxLength: maxLength,
      onTap: onTap,
      style: ResponsiveHelper.bodyStyle(context),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        hintStyle: ResponsiveHelper.smallStyle(context, color: AppColors.grey400),
        prefixIcon: icon != null
            ? Icon(icon,
                color: theme.primaryColor,
                size: ResponsiveHelper.iconSize(context, 18))
            : null,
        suffixIcon: suffixIcon,
        counterText: maxLength != null ? '' : null,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.grey300),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.grey300),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: theme.primaryColor, width: 1.5),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.grey200),
        ),
        filled: true,
        fillColor: !enabled || readOnly ? AppColors.grey100 : AppColors.grey50,
        isDense: true,
        contentPadding: EdgeInsets.symmetric(
          horizontal: ResponsiveHelper.spacing(context, 12),
          vertical: ResponsiveHelper.spacing(context, 12),
        ),
      ),
      validator: validator,
    );
  }
  
  /// 📌 섹션 헤더
  static Widget sectionHeader({
    required BuildContext context,
    required String title,
    required IconData icon,
  }) {
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
        Text(
          title,
          style: ResponsiveHelper.subtitleStyle(context).copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
  
  /// 💡 안내 카드
  static Widget infoCard({
    required BuildContext context,
    required String message,
    IconData icon = Icons.info_outline,
    Color? color,
  }) {
    final theme = Theme.of(context);
    final cardColor = color ?? theme.primaryColor;
    
    return Container(
      padding: ResponsiveHelper.cardPadding(context),
      decoration: BoxDecoration(
        color: cardColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cardColor.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(
            icon,
            color: cardColor,
            size: ResponsiveHelper.iconSize(context, 20),
          ),
          SizedBox(width: ResponsiveHelper.spacing(context, 12)),
          Expanded(
            child: Text(
              message,
              style: ResponsiveHelper.bodyStyle(
                context,
                color: cardColor.withValues(alpha: 0.9),
              ),
            ),
          ),
        ],
      ),
    );
  }
  
  // [특이사항] RoleTheme.getPrimaryColor()와 동일 로직 — 역할 추가 시 두 곳 모두 업데이트 필요
  static Color getRoleColor(String? role) {
    switch (role) {
      case 'SUPER_ADMIN':
        return AppColors.purple;  // 슈퍼 관리자는 보라색
      case 'BUSINESS_ADMIN':
        return AppColors.info;    // 사업장 관리자는 파란색
      case 'USER':
      default:
        return AppColors.success; // 지원자는 초록색
    }
  }
  
  /// 📛 역할 이름 반환
  // [특이사항] RoleTheme.getRoleLabel()과 동일 로직 — 역할 추가 시 두 곳 모두 업데이트 필요
  static String getRoleName(String? role) {
    switch (role) {
      case 'SUPER_ADMIN':
        return '슈퍼 관리자';
      case 'BUSINESS_ADMIN':
        return '사업장 관리자';
      case 'USER':
      default:
        return '지원자';
    }
  }

  /// 이미지 전체화면 미리보기 (핀치줌 + 좌우 스와이프)
  static Future<void> showImagePreview(
    BuildContext context,
    List<String> imageUrls, {
    int initialIndex = 0,
  }) {
    return showDialog<void>(
      context: context,
      useSafeArea: false,
      barrierColor: Colors.black87,
      builder: (ctx) => _ImagePreviewDialog(
        imageUrls: imageUrls,
        initialIndex: initialIndex,
      ),
    );
  }
}

class _ImagePreviewDialog extends StatefulWidget {
  final List<String> imageUrls;
  final int initialIndex;

  const _ImagePreviewDialog({
    required this.imageUrls,
    required this.initialIndex,
  });

  @override
  State<_ImagePreviewDialog> createState() => _ImagePreviewDialogState();
}

class _ImagePreviewDialogState extends State<_ImagePreviewDialog> {
  late final PageController _pageController;
  late int _currentIndex;
  bool _isZoomed = false;

  // 페이지별 TransformationController (줌 상태 감지용)
  late final List<TransformationController> _transformControllers;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
    _transformControllers = List.generate(
      widget.imageUrls.length,
      (_) => TransformationController(),
    );
    // 현재 페이지 컨트롤러만 리스닝 (비활성 페이지에 리스너 불필요)
    _transformControllers[_currentIndex].addListener(_onTransformChanged);
  }

  void _onTransformChanged() {
    final scale = _transformControllers[_currentIndex].value.getMaxScaleOnAxis();
    final zoomed = scale > 1.01;
    if (zoomed != _isZoomed && mounted) {
      setState(() => _isZoomed = zoomed);
    }
  }

  void _switchListenerTo(int newIndex) {
    _transformControllers[_currentIndex].removeListener(_onTransformChanged);
    _transformControllers[newIndex].addListener(_onTransformChanged);
  }

  @override
  void dispose() {
    _transformControllers[_currentIndex].removeListener(_onTransformChanged);
    _pageController.dispose();
    for (final ctrl in _transformControllers) {
      ctrl.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // 이미지 페이지뷰 — 줌인 시 PageView 스크롤 잠금으로 핀치줌 충돌 방지
          PageView.builder(
            controller: _pageController,
            physics: _isZoomed
                ? const NeverScrollableScrollPhysics()
                : const ClampingScrollPhysics(),
            itemCount: widget.imageUrls.length,
            onPageChanged: (i) {
              // 이전 페이지 줌 초기화 + 리스너를 새 페이지로 전환
              _transformControllers[_currentIndex].value = Matrix4.identity();
              _switchListenerTo(i);
              setState(() => _currentIndex = i);
            },
            itemBuilder: (ctx, i) => InteractiveViewer(
              transformationController: _transformControllers[i],
              minScale: 0.8,
              maxScale: 4.0,
              clipBehavior: Clip.none,
              child: Center(
                child: CachedNetworkImage(
                  imageUrl: widget.imageUrls[i],
                  fit: BoxFit.contain,
                  placeholder: (ctx, url) => const Center(
                    child: CircularProgressIndicator(color: Colors.white),
                  ),
                  errorWidget: (ctx, url, e) => const Icon(
                    Icons.broken_image_outlined,
                    color: Colors.white54,
                    size: 60,
                  ),
                ),
              ),
            ),
          ),

          // 닫기 버튼
          SafeArea(
            child: Align(
              alignment: Alignment.topRight,
              child: IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close, color: Colors.white, size: 28),
                style: IconButton.styleFrom(
                  backgroundColor: Colors.black45,
                ),
              ),
            ),
          ),

          // 페이지 인디케이터 (사진 2장 이상, 줌아웃 상태일 때만 표시)
          if (widget.imageUrls.length > 1 && !_isZoomed)
            SafeArea(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 24),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '${_currentIndex + 1} / ${widget.imageUrls.length}',
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}