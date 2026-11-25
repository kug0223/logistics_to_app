import 'package:flutter/material.dart';
import 'navigation_key.dart';
import 'responsive_helper.dart';
import 'text_layout.dart';
import '../theme/app_colors.dart';

/// CF 함수 호출 등 비동기 작업 중 전역 로딩 오버레이를 표시합니다.
///
/// 사용 예:
///   GlobalLoadingController.show('공고 공개 중...');
///   try {
///     await someCFCall();
///   } finally {
///     GlobalLoadingController.hide();
///   }
///
/// 또는 runWithLoading() 헬퍼 사용:
///   final result = await GlobalLoadingController.runWithLoading(
///     () => someService.doSomething(),
///     '처리 중...',
///   );
class GlobalLoadingController {
  static OverlayEntry? _entry;
  static int _depth = 0;

  /// 로딩 오버레이를 표시합니다.
  /// 중첩 호출 시 내부적으로 카운트하여 모든 hide()가 호출된 뒤 숨겨집니다.
  static void show([String message = '처리 중...']) {
    _depth++;
    if (_depth > 1) return; // 이미 표시 중

    final overlay = navigatorKey.currentState?.overlay;
    if (overlay == null) return;

    _entry?.remove();
    _entry = OverlayEntry(
      builder: (_) => _GlobalLoadingOverlay(message: message),
    );
    overlay.insert(_entry!);
  }

  /// 로딩 오버레이를 숨깁니다.
  /// show()와 쌍으로 호출해야 합니다. try-finally 패턴 권장.
  static void hide() {
    if (_depth > 0) _depth--;
    if (_depth > 0) return;

    _entry?.remove();
    _entry = null;
  }

  /// CF 호출 등 비동기 작업을 로딩 오버레이와 함께 실행합니다.
  /// show/hide를 자동으로 처리하므로 try-finally 없이도 안전합니다.
  static Future<T> run<T>(Future<T> Function() fn, [String message = '처리 중...']) async {
    show(message);
    try {
      return await fn();
    } finally {
      hide();
    }
  }
}

class _GlobalLoadingOverlay extends StatelessWidget {
  final String message;
  const _GlobalLoadingOverlay({required this.message});

  @override
  Widget build(BuildContext context) {
    // [DU642 · B03] 하드코딩 Colors.black/white → 테마 scrim/shadow 역할 · AppColors.surface(앱 테마에서 같은 값 · 알파 그대로).
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.scrim.withValues(alpha: 0.45),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 28),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: scheme.shadow.withValues(alpha: 0.15),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(
                  Theme.of(context).primaryColor,
                ),
                strokeWidth: 3,
              ),
              const SizedBox(height: 16),
              // [DU642 · B03 · BL148] 메시지 — 하드코딩 14/w500/grey700 → RH 본문 양식 · 보조 글 토큰 · 낱말 단위 줄바꿈 · 가운데(showLoading 과 같은 양식).
              Text(
                TextLayout.keepWords(message),
                textAlign: TextAlign.center,
                style: ResponsiveHelper.bodyStyle(context, color: AppColors.textSecondary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
