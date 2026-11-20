import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../utils/navigation_key.dart';
import '../theme/app_colors.dart';
import '../widgets/common/first_line_icon.dart';
import '../widgets/common/keep_words_text.dart';

class ToastHelper {
  static OverlayEntry? _currentEntry;

  /// [DU1 구현57 F56-1] 토스트가 피해야 할 하단 고정 행동 영역의 **윗변(전역 y)**.
  ///   [ToastAvoidArea] 로 감싼 화면만 등록한다(현재 route 일 때). 등록이 없으면 기존 위치 그대로다.
  ///   공고 등록 실패 토스트가 하단 '공고 등록' 위에 떠 재시도 버튼 라벨을 가렸다(320·2.0 / 360·1.0 실측).
  static final ValueNotifier<double?> avoidTop = ValueNotifier<double?>(null);
  static final Map<Object, double> _avoidAreas = {};
  static void _setAvoid(Object owner, double? top) {
    if (top == null) {
      _avoidAreas.remove(owner);
    } else {
      _avoidAreas[owner] = top;
    }
    final next = _avoidAreas.isEmpty ? null : _avoidAreas.values.reduce(math.min);
    if (avoidTop.value != next) avoidTop.value = next;
  }

  // [DU366] 성공 · 안내 · 경고 면도 흰 글이 읽히는 진한 짝으로(오류 errorDark 와 같은 계열, 공용 토스트 면에서만):
  //   success 2.78 → successDark 7.13 · info 3.12 → infoDark 4.60 · warning 2.16 → warningDark 5.24
  static void showSuccess(String message) => _show(
        message: message,
        backgroundColor: AppColors.successDark,
        icon: Icons.check_circle_outline,
      );

  // [DU357] 오류 토스트 면 error #F44336(흰 글 3.68:1) → errorDark #B42318(확인창 손실 실행 · 오류 글과 같은 짝).
  //   [DU366] 성공 · 안내 · 경고도 위처럼 진한 짝으로 바꿨다(소급 12 채택).
  static void showError(String message) => _show(
        message: message,
        backgroundColor: AppColors.errorDark,
        icon: Icons.error_outline,
        duration: const Duration(seconds: 4),
      );

  static void showInfo(String message) => _show(
        message: message,
        backgroundColor: AppColors.infoDark,
        icon: Icons.info_outline,
      );

  static void showWarning(String message) => _show(
        message: message,
        backgroundColor: AppColors.warningDark,
        icon: Icons.warning_amber_outlined,
      );

  static void _show({
    required String message,
    required Color backgroundColor,
    required IconData icon,
    Duration duration = const Duration(seconds: 2),
  }) {
    final overlay = navigatorKey.currentState?.overlay;
    if (overlay == null) return;

    _currentEntry?.remove();
    _currentEntry = null;

    late OverlayEntry entry;
    entry = OverlayEntry(
      // 하단 회피 영역이 바뀌면(키보드·route 전환) 토스트 위치도 다시 잡는다
      builder: (_) => ValueListenableBuilder<double?>(
        valueListenable: avoidTop,
        builder: (_, __, ___) => _ToastWidget(
          message: message,
          backgroundColor: backgroundColor,
          icon: icon,
        ),
      ),
    );
    _currentEntry = entry;
    overlay.insert(entry);

    Future.delayed(duration, () {
      if (entry.mounted) entry.remove();
      if (_currentEntry == entry) _currentEntry = null;
    });
  }
}

const TextStyle _kToastTextStyle = TextStyle(
  color: AppColors.textOnDark,
  fontSize: 14,
  fontWeight: FontWeight.w500,
);

class _ToastWidget extends StatelessWidget {
  final String message;
  final Color backgroundColor;
  final IconData icon;

  const _ToastWidget({
    required this.message,
    required this.backgroundColor,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    // viewInsets.bottom = 키보드 높이, padding.bottom = safe area
    // 키보드가 올라와 있으면 viewInsets.bottom이 더 크므로 둘 중 max 사용
    final bottomPadding = math.max(mq.padding.bottom, mq.viewInsets.bottom);
    // [DU1 구현57 F56-1] 하단 고정 행동이 등록돼 있으면 그 윗변 위 8 로 띄운다(행동 라벨과 동시에 읽히게).
    final avoid = ToastHelper.avoidTop.value;
    final avoidBottom = avoid == null ? 0.0 : (mq.size.height - avoid + 8);
    return Positioned(
      bottom: math.max(24 + bottomPadding, avoidBottom),
      left: 16,
      right: 16,
      // [E1-AMBIGUOUS-INVITE] 토스트는 누를 것이 없다. 화면 하단 버튼 위에
      //   2초 동안 떠서 그 탭을 삼키고 있었다(예: 오류 직후의 `다시 확인`).
      child: IgnorePointer(child: Material(
        color: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.2),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          // [DU361] 여러 줄 토스트(B)에서 아이콘이 글 덩어리 가운데에 놓였다 — 첫 줄 가운데로(크기 그대로)
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              FirstLineIcon(icon, size: 20, color: AppColors.textOnDark, textStyle: _kToastTextStyle),
              const SizedBox(width: 12),
              // [DU357] 원문 보존 낱말 조판(B '불러|오지' · '재|시도') — 위젯 data 는 원문 그대로
              // [DU364] 토스트 전용 _ToastMessageText 를 공용 KeepWordsText 로 옮겼다(같은 동작, 첫 소비자)
              Expanded(
                child: KeepWordsText(
                  message,
                  style: _kToastTextStyle,
                ),
              ),
            ],
          ),
        ),
      )),
    );
  }
}

/// [DU1 구현57 F56-1] 하단 고정 행동(예: 공고 등록 CTA)을 감싸 토스트가 그 위로 뜨게 한다.
///   현재 route 이고 화면에 붙어 있을 때만 윗변을 등록하고, 가려지거나 사라지면 해제한다.
///   감싸지 않은 화면은 기존 토스트 위치 그대로다.
class ToastAvoidArea extends StatefulWidget {
  final Widget child;
  const ToastAvoidArea({super.key, required this.child});

  @override
  State<ToastAvoidArea> createState() => _ToastAvoidAreaState();
}

class _ToastAvoidAreaState extends State<ToastAvoidArea> {
  final _owner = Object();

  void _report() {
    if (!mounted) return;
    final route = ModalRoute.of(context);
    final box = context.findRenderObject();
    if ((route != null && !route.isCurrent) || box is! RenderBox || !box.hasSize || !box.attached) {
      ToastHelper._setAvoid(_owner, null);
      return;
    }
    ToastHelper._setAvoid(_owner, box.localToGlobal(Offset.zero).dy);
  }

  @override
  Widget build(BuildContext context) {
    // 배치가 끝난 뒤 윗변을 잰다(키보드 상승·route 전환 때 다시 빌드되며 갱신)
    WidgetsBinding.instance.addPostFrameCallback((_) => _report());
    return widget.child;
  }

  @override
  void deactivate() {
    ToastHelper._setAvoid(_owner, null);
    super.deactivate();
  }

  @override
  void dispose() {
    ToastHelper._setAvoid(_owner, null);
    super.dispose();
  }
}
