// lib/widgets/dialogs/styled_dialog.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../utils/responsive_helper.dart';
import '../../theme/app_colors.dart';
import '../../utils/text_layout.dart';
import '../../theme/app_text_styles.dart';

/// 앱 전체 다이얼로그 크기 표준
///
/// 모든 커스텀 Dialog 위젯에서 이 값을 사용해 크기를 통일한다.
/// StyledDialog, WageConfirmDialog, AttendanceStatusDialog 등 동일 적용.
class AppDialogSize {
  /// Dialog 좌우 여백
  static const double insetH = 16.0;
  /// Dialog 상하 여백
  static const double insetV = 8.0;
  /// 화면 높이 대비 최대 높이 비율
  static const double maxHeightRatio = 0.95;
  /// 모서리 반경
  static const double borderRadius = 24.0;
  /// 내부 서브시트 최대 높이 비율 (다이얼로그 내 중첩 시트용)
  static const double subSheetHeightRatio = 0.85;
}

/// [DU287 RF1] 다이얼로그 의미색 — 흰 글을 올리는 채움 면·밝은 면 위 아이콘에 쓸 때, 밝은 의미색(error·warning·success·info)을
///   같은 계열의 읽히는 짝(…Dark)으로 바꾼다. 호출부가 고른 의미(색 계열)는 그대로 두고 대비만 맞춘다(선례 DU265·DU271 호출부 교정).
///   흰 글 대비(시험 실측): error 3.68 → 6.57, warning 2.16 → warningDark, success 2.78 → 7.13, info 3.12 → 4.60. 그 밖의 색은 그대로.
///   StyledDialog·DialogHelper 두 셸이 같이 쓴다.
class AppDialogColors {
  static Color readableFill(Color c) {
    if (c == AppColors.error) return AppColors.errorDark;
    if (c == AppColors.warning) return AppColors.warningDark;
    if (c == AppColors.success) return AppColors.successDark;
    if (c == AppColors.info) return AppColors.infoDark;
    return c;
  }
}

/// 다이얼로그 닫힘 시 포커스 안전 해제 — 버튼/barrier/뒤로가기 모두 대응
///
/// Dialog 루트를 이 위젯으로 감싸면, deactivate() 시점에
/// FocusManager.instance.primaryFocus?.unfocus()를 호출하여
/// '_dependents.isEmpty' assertion 크래시를 방지한다.
///
/// ⚠️ onPressed에서만 unfocus()를 호출하면 마이크로태스크 타이밍으로
///    InheritedElement가 먼저 unmount되어 크래시가 계속 발생한다.
///    deactivate() 시점에 호출해야 올바른 순서가 보장된다.
///
/// 동일 원리: dialog_helper.dart의 _SheetFocusSafeArea (바텀시트 전용)
class DialogFocusSafeArea extends StatefulWidget {
  final Widget child;
  const DialogFocusSafeArea({super.key, required this.child});

  @override
  State<DialogFocusSafeArea> createState() => _DialogFocusSafeAreaState();
}

class _DialogFocusSafeAreaState extends State<DialogFocusSafeArea> {
  @override
  void deactivate() {
    // FocusScope.of(context) 사용 금지 — deactivate 시점에 FocusScope InheritedElement가
    // 먼저 unmount되면 _dependents assertion('_dependents.isEmpty') 크래시 발생.
    // FocusManager.instance로 직접 접근하면 InheritedWidget 탐색 없이 안전하게 해제됨.
    FocusManager.instance.primaryFocus?.unfocus();
    super.deactivate();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// ✨ 세련된 다이얼로그 위젯
/// 
/// 역할별 테마에 맞는 그라데이션 헤더와 통일된 디자인 제공
/// 
/// 사용 예:
/// ```dart
/// await showDialog(
///   context: context,
///   builder: (context) => StyledDialog(
///     title: '비밀번호 변경',
///     subtitle: '보안을 위해 안전한 비밀번호를 사용하세요',
///     icon: Icons.lock_outline,
///     content: YourContentWidget(),
///     actions: [
///       StyledDialogButton.cancel(
///         onPressed: () => Navigator.pop(context),
///       ),
///       StyledDialogButton.primary(
///         text: '변경하기',
///         onPressed: () => Navigator.pop(context, true),
///       ),
///     ],
///   ),
/// );
/// ```
class StyledDialog extends StatelessWidget {
  /// 제목
  final String title;

  /// 부제목 (선택)
  final String? subtitle;

  /// 아이콘
  final IconData icon;

  /// 헤더 색상 (기본값: Theme.of(context).primaryColor)
  final Color? headerColor;

  /// 컨텐츠
  final Widget content;

  /// 하단 버튼들
  final List<Widget>? actions;

  /// 닫기 버튼 표시 여부
  final bool showCloseButton;

  /// 최대 너비
  final double? maxWidth;

  /// 최대 높이 비율 (0.0 ~ 1.0)
  final double maxHeightRatio;

  /// true 이면 minHeight = maxHeight = 화면의 maxHeightRatio
  /// → 데이터 없을 때도 다이얼로그가 항상 같은 크기 유지
  /// 콘텐츠는 직접 SingleChildScrollView 를 감싸야 함
  final bool fillHeight;

  /// Dialog의 insetPadding (기본값: Flutter 기본값과 동일)
  /// landscape 등에서 다이얼로그가 화면 밖으로 나가지 않도록 조정
  final EdgeInsets insetPadding;

  const StyledDialog({
    super.key,
    required this.title,
    this.subtitle,
    required this.icon,
    this.headerColor,
    required this.content,
    this.actions,
    this.showCloseButton = false,
    this.maxWidth,
    this.maxHeightRatio = 0.92,
    this.fillHeight = false,
    this.insetPadding = const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // [DU287 RF3] 머리 아이콘·10% 면 — 밝은 의미색은 읽히는 짝으로(아이콘 3:1)
    final color = AppDialogColors.readableFill(headerColor ?? theme.primaryColor);

    final screenH = MediaQuery.sizeOf(context).height;

    // [FC-FIX] DialogFocusSafeArea — TextField가 있는 모든 StyledDialog를
    // deactivate() 시점에 자동으로 unfocus하여 _dependents.isEmpty 크래시 방지
    return DialogFocusSafeArea(
      child: Dialog(
        backgroundColor: Colors.white,
        insetPadding: insetPadding,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
      child: Container(
        constraints: BoxConstraints(
          maxWidth: maxWidth ?? double.infinity,
          minHeight: fillHeight ? screenH * maxHeightRatio : 0,
          maxHeight: screenH * maxHeightRatio,
        ),
        child: Column(
          mainAxisSize: fillHeight ? MainAxisSize.max : MainAxisSize.min,
          children: [
            _buildHeader(context, color),
            Flexible(
              child: fillHeight
                  ? content
                  : SingleChildScrollView(
                      padding: ResponsiveHelper.cardPadding(context),
                      child: content,
                    ),
            ),
            if (actions case final actions? when actions.isNotEmpty)
              _buildActions(context),
          ],
        ),
      ),
    ),   // Dialog
    );   // DialogFocusSafeArea
  }

  /// 헤더 — [리디자인] 그라데이션 제거 → White 기반, color는 아이콘 컨테이너에만
  ///   [DU286 SD1~SD3] 제목·부제목은 모든 배율에서 낱말 단위(들어가면 원문). 큰 글자에서 아이콘(+닫기) 옆 한 줄에 안 들어가는
  ///   제목은 아이콘 줄을 위에 두고 전체 폭으로 쓴다(DialogHelper F48-1 과 같다). 부제목 2줄 말줄임 제거·textSecondary,
  ///   닫기 #9CA3AF(2.54:1) → textSecondary·터치 48. 기본 배율·들어가는 제목은 기존 가로 배치 그대로.
  Widget _buildHeader(BuildContext context, Color color) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        ResponsiveHelper.spacing(context, 20),
        ResponsiveHelper.spacing(context, 20),
        ResponsiveHelper.spacing(context, 16),
        0,
      ),
      child: LayoutBuilder(builder: (c, cons) {
        // 아이콘 — color 10% 배경 + 아이콘 자체에 color
        final iconBox = Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            icon,
            color: color,
            size: ResponsiveHelper.iconSize(c, 24),
          ),
        );
        // 닫기 버튼 — 터치 48 을 테마 tap target 에 기대지 않고 직접 둔다
        final close = showCloseButton
            ? IconButton(
                tooltip: '닫기',
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close, color: AppColors.textSecondary, size: 20), // [DU286 r1] 크기는 원래 20 그대로
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
              )
            : null;
        final gap = ResponsiveHelper.spacing(c, 12);
        final titleStyle = ResponsiveHelper.subtitleStyle(c).copyWith(
          color: const Color(0xFF111827),
          fontWeight: FontWeight.bold,
        );
        final subStyle = ResponsiveHelper.smallStyle(c).copyWith(color: AppColors.textSecondary);
        final enlarged = MediaQuery.textScalerOf(c).scale(1) > 1.0;
        final besideW = cons.maxWidth - 44 - gap - (close != null ? 48 : 0);
        // 제목 & 부제목
        Widget texts(double w) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _sdWordSafe(c, title, titleStyle, w),
                if (subtitle != null) ...[
                  SizedBox(height: ResponsiveHelper.spacing(c, 3)),
                  _sdWordSafe(c, subtitle!, subStyle, w),
                ],
              ],
            );
        if (!enlarged || _sdFitsLine(c, title, titleStyle, besideW)) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              iconBox,
              SizedBox(width: gap),
              Expanded(child: texts(besideW)),
              if (close != null) close,
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(children: [iconBox, const Spacer(), if (close != null) close]),
            SizedBox(height: gap),
            texts(cons.maxWidth),
          ],
        );
      }),
    );
  }

  /// 버튼 영역 — [리디자인] 구분선 제거 → 여백만으로 콘텐츠와 분리
  ///   [DU286 SD4] 칸에 안 들어가는 StyledDialogButton 글은 셸이 낱말 단위 표시본으로 바꾼다(모든 배율). 큰 글자에서 행동이
  ///   전부 StyledDialogButton(2개 이상)이고 한 칸(안쪽 16 여유)에 안 들어가는 글이 있으면 세로 전체 폭으로 쌓는다 — 채움(주)이
  ///   위, 테두리(보조)가 아래(DialogHelper F48-1 과 같다). 임의 위젯 행동·들어가는 글은 기존 가로 배치 그대로.
  ///   버튼 안에는 LayoutBuilder 를 두지 않는다(IntrinsicHeight·AlertDialog 의 IntrinsicWidth 안에서도 안전).
  Widget _buildActions(BuildContext context) {
    final acts = actions ?? [];
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: ResponsiveHelper.cardPadding(context),
          child: LayoutBuilder(builder: (c, cons) {
            final gap = ResponsiveHelper.spacing(c, 12);
            final enlarged = MediaQuery.textScalerOf(c).scale(1) > 1.0;
            const inner = 16.0;
            final label = StyledDialogButton._labelStyle(c);
            Widget shown(Widget a, double w) {
              if (a is! StyledDialogButton || a.isLoading) return a;
              if (_sdFitsLine(c, a.text, label, w)) return a;
              return a._withShown(TextLayout.keepWords(TextLayout.plain(a.text)));
            }

            final per = acts.isEmpty ? cons.maxWidth : (cons.maxWidth - gap * (acts.length - 1)) / acts.length;
            final btns = acts.whereType<StyledDialogButton>().toList();
            if (enlarged &&
                acts.length >= 2 &&
                btns.length == acts.length &&
                btns.any((b) => !_sdFitsLine(c, b.text, label, per - inner))) {
              final ordered = [...btns.where((b) => !b.isOutlined), ...btns.where((b) => b.isOutlined)];
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var k = 0; k < ordered.length; k++) ...[
                    if (k > 0) SizedBox(height: ResponsiveHelper.spacing(c, 8)),
                    shown(ordered[k], cons.maxWidth),
                  ],
                ],
              );
            }
            return Row(
              children: acts
                  .map((action) => Expanded(child: shown(action, per)))
                  .toList()
                  .fold<List<Widget>>(
                [],
                (list, widget) {
                  if (list.isNotEmpty) {
                    list.add(SizedBox(width: gap));
                  }
                  list.add(widget);
                  return list;
                },
              ),
            );
          }),
        ),
      ],
    );
  }
}

/// [DU286 SD0] 글이 [maxWidth] 안에 한 줄(각 줄)로 들어가는가 — Text 가 그리는 것과 같은 기준(둘레 기본 글자 병합·locale).
///   DialogHelper._fitsLine(DU284)과 같은 규칙이다(공용 도구로 합칠 후보).
bool _sdFitsLine(BuildContext context, String text, TextStyle style, double maxWidth) {
  final eff = style.inherit ? DefaultTextStyle.of(context).style.merge(style) : style;
  final tp = TextPainter(
    text: TextSpan(text: text, style: eff),
    textDirection: TextDirection.ltr,
    textScaler: MediaQuery.textScalerOf(context),
    locale: Localizations.maybeLocaleOf(context),
  )..layout();
  final w = tp.width;
  tp.dispose();
  return w <= maxWidth;
}

/// [DU286 SD0] 들어가면 원문 그대로, 안 들어가면 낱말 단위로 묶는다(음절 끊김 방지). 읽기 이름은 원문.
Widget _sdWordSafe(BuildContext context, String text, TextStyle style, double maxWidth) {
  if (_sdFitsLine(context, text, style, maxWidth)) return Text(text, style: style);
  final plain = TextLayout.plain(text);
  return Text(TextLayout.keepWords(plain), semanticsLabel: plain, style: style);
}

/// 스타일 다이얼로그 버튼
class StyledDialogButton extends StatelessWidget {
  final String text;
  final VoidCallback? onPressed;
  final Color? backgroundColor;
  final Color? foregroundColor;
  final bool isOutlined;
  final bool isLoading;

  /// [DU286 SD5] 셸(StyledDialog)이 칸에 안 들어간다고 잰 글의 낱말 단위 표시본 — 읽기 이름은 [text] 원문
  final String? _shown;

  const StyledDialogButton({
    super.key,
    required this.text,
    required this.onPressed,
    this.backgroundColor,
    this.foregroundColor,
    this.isOutlined = false,
    this.isLoading = false,
  }) : _shown = null;

  const StyledDialogButton._copy({
    super.key,
    required this.text,
    required this.onPressed,
    this.backgroundColor,
    this.foregroundColor,
    this.isOutlined = false,
    this.isLoading = false,
    String? shown,
  }) : _shown = shown;

  StyledDialogButton _withShown(String s) => StyledDialogButton._copy(
        key: key,
        text: text,
        onPressed: onPressed,
        backgroundColor: backgroundColor,
        foregroundColor: foregroundColor,
        isOutlined: isOutlined,
        isLoading: isLoading,
        shown: s,
      );

  static TextStyle _labelStyle(BuildContext context) =>
      ResponsiveHelper.bodyStyle(context).copyWith(fontWeight: FontWeight.w600);

  /// Primary 버튼 (채워진 버튼)
  factory StyledDialogButton.primary({
    required String text,
    required VoidCallback? onPressed,
    Color? backgroundColor,
    bool isLoading = false,
  }) {
    return StyledDialogButton(
      text: text,
      onPressed: onPressed,
      backgroundColor: backgroundColor,
      foregroundColor: AppColors.surface,
      isLoading: isLoading,
    );
  }

  /// Cancel 버튼 (아웃라인 버튼)
  factory StyledDialogButton.cancel({
    String text = '취소',
    required VoidCallback? onPressed,
  }) {
    return StyledDialogButton(
      text: text,
      onPressed: onPressed,
      isOutlined: true,
    );
  }

  /// Danger 버튼 (빨간색)
  factory StyledDialogButton.danger({
    required String text,
    required VoidCallback? onPressed,
    bool isLoading = false,
  }) {
    return StyledDialogButton(
      text: text,
      onPressed: onPressed,
      // [DU286 SD7] 흰 글 on error #F44336 3.68:1(4.5 미달) → errorDark(약 6.6:1)
      backgroundColor: AppColors.errorDark,
      foregroundColor: AppColors.surface,
      isLoading: isLoading,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDisabled = !isLoading && onPressed == null;

    // 색상 결정
    final Color bgColor;
    final Color fgColor;
    final Border? border;

    if (isDisabled) {
      bgColor = AppColors.grey200;
      // [DU286 SD6] grey400 on grey200 1.62:1 → textSecondary(DU 비활성 CTA 기준)
      fgColor = AppColors.textSecondary;
      border = null;
    } else if (isOutlined) {
      // 취소 버튼 — 흰 배경 + 얇은 테두리
      bgColor = Colors.white;
      fgColor = const Color(0xFF4B5563);
      border = Border.all(color: const Color(0xFFE5E7EB));
    } else {
      fgColor = foregroundColor ?? Colors.white;
      // [DU287 RF4] 흰 글 채움일 때만 밝은 의미색을 읽히는 짝으로(다른 글색을 고른 호출부는 그대로)
      final base = backgroundColor ?? theme.primaryColor;
      bgColor = fgColor.toARGB32() == 0xFFFFFFFF ? AppDialogColors.readableFill(base) : base;
      border = null;
    }

    final Widget child = Center(
      child: isLoading
          ? SizedBox(
              height: ResponsiveHelper.iconSize(context, 18),
              width: ResponsiveHelper.iconSize(context, 18),
              child: CircularProgressIndicator(strokeWidth: 2, color: fgColor),
            )
          : Text(
              _shown ?? text,
              semanticsLabel: _shown == null ? null : text,
              textAlign: TextAlign.center,
              style: _labelStyle(context).copyWith(color: fgColor),
            ),
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(10),
        border: border,
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: isLoading || isDisabled ? null : onPressed,
          borderRadius: BorderRadius.circular(10),
          // [DU286 SD5] 실측 44.4(360·1.0) — 공통 기준 행동 최소 52(DialogHelper F48-1 과 같다, 고정 높이 아님)
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 52),
            child: Padding(
              padding: EdgeInsets.symmetric(
                vertical: ResponsiveHelper.spacing(context, 13),
              ),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

/// 다이얼로그용 TextField (통일된 스타일)
class StyledDialogTextField extends StatelessWidget {
  final TextEditingController controller;
  final String labelText;
  final String? hintText;
  final IconData? prefixIcon;
  final Widget? suffixIcon;
  final bool obscureText;
  final TextInputType? keyboardType;
  final void Function(String)? onChanged;
  final int? maxLength;
  final FocusNode? focusNode;
  final void Function(String)? onFieldSubmitted;
  final bool enabled;
  final bool autofocus;
  final List<TextInputFormatter>? inputFormatters;
  final int? maxLines;

  const StyledDialogTextField({
    super.key,
    required this.controller,
    required this.labelText,
    this.hintText,
    this.prefixIcon,
    this.suffixIcon,
    this.obscureText = false,
    this.keyboardType,
    this.onChanged,
    this.maxLength,
    this.focusNode,
    this.onFieldSubmitted,
    this.enabled = true,
    this.autofocus = false,
    this.inputFormatters,
    this.maxLines = 1,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          labelText,
          style: ResponsiveHelper.bodyStyle(context).copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        SizedBox(height: ResponsiveHelper.spacing(context, 8)),
        TextField(
          controller: controller,
          focusNode: focusNode,
          enabled: enabled,
          autofocus: autofocus,
          onSubmitted: onFieldSubmitted,
          obscureText: obscureText,
          keyboardType: keyboardType,
          inputFormatters: inputFormatters,
          onChanged: onChanged,
          maxLength: maxLength,
          maxLines: maxLines,
          minLines: 1,
          style: ResponsiveHelper.bodyStyle(context),
          decoration: InputDecoration(
            hintText: hintText,
            hintStyle: ResponsiveHelper.smallStyle(
              context,
              color: AppColors.grey400,
            ),
            prefixIcon: prefixIcon != null
                ? Icon(
                    prefixIcon,
                    color: theme.primaryColor,
                    size: ResponsiveHelper.iconSize(context, 22),
                  )
                : null,
            suffixIcon: suffixIcon,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: AppColors.border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: AppColors.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: theme.primaryColor, width: 2),
            ),
            disabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: AppColors.grey200),
            ),
            filled: true,
            fillColor: enabled ? AppColors.grey50 : AppColors.grey100,
            contentPadding: EdgeInsets.symmetric(
              horizontal: ResponsiveHelper.spacing(context, 16),
              vertical: ResponsiveHelper.spacing(context, 16),
            ),
            counterText: '', // maxLength 카운터 숨기기
          ),
        ),
      ],
    );
  }
}

/// 다이얼로그용 안내 카드
class StyledDialogInfoCard extends StatelessWidget {
  final String message;
  final IconData icon;
  final Color color;

  /// [R7-P4.4E.6C] 한 덩어리 글을 **문단으로 끊어** 보여줄 때 쓴다.
  ///
  ///   긴 안내문을 `message` 한 줄로 넣으면 줄바꿈만 있는 벽이 되어 읽는
  ///   사람이 어디서 어디까지가 한 조건인지 알 수 없다. 글자는 그대로 두고
  ///   **간격만** 준다 — 문자열을 바꾸지 않는다.
  ///   null 이면 기존처럼 `message` 하나를 그린다(기존 호출부 동작 불변).
  final List<String>? segments;

  const StyledDialogInfoCard({
    super.key,
    required this.message,
    this.icon = Icons.info_outline,
    this.color = AppColors.info,
    this.segments,
  });

  /// Info 카드 (파란색)
  factory StyledDialogInfoCard.info(String message) {
    return StyledDialogInfoCard(
      message: message,
      icon: Icons.info_outline,
      color: AppColors.info,
    );
  }

  /// Warning 카드 (주황색)
  factory StyledDialogInfoCard.warning(String message) {
    return StyledDialogInfoCard(
      message: message,
      icon: Icons.warning_amber,
      color: AppColors.warning,
    );
  }

  /// Warning 카드 — 문단으로 끊어 보여준다. 글자는 바꾸지 않는다.
  factory StyledDialogInfoCard.warningSegments(List<String> segments) {
    return StyledDialogInfoCard(
      message: segments.join('\n'),
      segments: segments,
      icon: Icons.warning_amber,
      color: AppColors.warning,
    );
  }

  /// Success 카드 (초록색)
  factory StyledDialogInfoCard.success(String message) {
    return StyledDialogInfoCard(
      message: message,
      icon: Icons.check_circle_outline,
      color: AppColors.success,
    );
  }

  /// Error 카드 (빨간색)
  factory StyledDialogInfoCard.error(String message) {
    return StyledDialogInfoCard(
      message: message,
      icon: Icons.error_outline,
      color: AppColors.error,
    );
  }

  @override
  Widget build(BuildContext context) {
    // [DU288 IC1] 글은 낱말 단위로 줄바꿈한다(음절 끊김 방지). 보이는 글자·읽기 이름은 원문 그대로다(동의 문구 버전 계약).
    //   폭을 재지 않는다 — 이 카드는 AlertDialog(IntrinsicWidth) content 안에도 들어간다. 줄바꿈 문자는 keepWords 안에서도 강제 줄바꿈이다.
    // [DU288 IC2] 기본 배율: 아이콘을 첫 줄 가운데에 맞춘다(긴 글 덩어리의 세로 가운데에 뜨지 않게).
    // [DU288 IC3] 큰 글자(배율>1.0): 아이콘을 글 위 한 줄로 올려 글이 카드 안쪽 폭을 다 쓴다.
    //   색(면·테두리·글자·아이콘)·글 크기·여백은 그대로다.
    final style = ResponsiveHelper.smallStyle(context, color: _textColor(color));
    final scaler = MediaQuery.textScalerOf(context);
    final iconSz = ResponsiveHelper.iconSize(context, 18);
    final iconW = Icon(icon, color: _getShade(color, 700), size: iconSz);
    final body = segments == null
        ? _words(message, style)
        : Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < segments!.length; i++) ...[
                if (i > 0)
                  SizedBox(
                      height: ResponsiveHelper.spacing(context, 8)),
                _words(segments![i], style),
              ],
            ],
          );
    final Widget inner;
    if (scaler.scale(1) > 1.0) {
      inner = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          iconW,
          SizedBox(height: ResponsiveHelper.spacing(context, 6)),
          body,
        ],
      );
    } else {
      final eff = style.inherit ? DefaultTextStyle.of(context).style.merge(style) : style;
      final tp = TextPainter(
        text: TextSpan(text: ' ', style: eff),
        textDirection: TextDirection.ltr,
        textScaler: scaler,
        locale: Localizations.maybeLocaleOf(context),
      );
      final lineH = tp.preferredLineHeight;
      tp.dispose();
      final top = lineH > iconSz ? (lineH - iconSz) / 2 : 0.0;
      inner = Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(padding: EdgeInsets.only(top: top), child: iconW),
          SizedBox(width: ResponsiveHelper.spacing(context, 10)),
          Expanded(child: body),
        ],
      );
    }
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 14),
        vertical: ResponsiveHelper.spacing(context, 11),
      ),
      decoration: BoxDecoration(
        // [리디자인] 배경 6-8%, 테두리 20-25% — 과도한 색상 강도 낮춤
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: color.withValues(alpha: 0.22),
        ),
      ),
      child: inner,
    );
  }

  /// [DU288 IC1] 낱말 단위 표시본 — 보이는 글자는 원문과 같고(묶음 문자만 더한다), 읽기 이름은 원문이다.
  static Widget _words(String s, TextStyle style) {
    final shown = TextLayout.keepWords(s);
    return Text(shown, semanticsLabel: shown == s ? null : s, style: style);
  }

  /// [DU1-F2] 읽는 본문 글자색 — 의미색을 18% 어둡게 한 값은 주황 경고에서 3.0:1 이었다(7% 바탕 위).
  ///   공통 기준의 진한 글자 토큰에 연결한다: warning 4.96 · success 6.68 · error 6.00 · info(infoDeep). 그 밖은 예전 방식.
  Color _textColor(Color color) {
    if (color == AppColors.warning) return AppColors.warningDark;
    if (color == AppColors.success) return AppColors.successDark;
    if (color == AppColors.error) return AppColors.errorDark;
    if (color == AppColors.info) return AppColors.infoDeep;
    return _getShade(color, 800);
  }

  /// 색상 shade 가져오기 (MaterialColor가 아닌 경우 대체)
  Color _getShade(Color color, int shade) {
    if (color is MaterialColor) {
      return color[shade]!;
    }
    
    // MaterialColor가 아닌 경우 어둡게/밝게 처리
    if (shade >= 700) {
      // 어둡게 (700, 800, 900)
      final factor = (shade - 500) / 500; // 0.4 ~ 0.8
      return Color.lerp(color, Colors.black, factor * 0.3)!;
    } else {
      // 밝게 (100, 200, 300)
      final factor = (500 - shade) / 500; // 0.4 ~ 0.8
      return Color.lerp(color, Colors.white, factor * 0.5)!;
    }
  }
}

/// 비밀번호 강도 표시기
class PasswordStrengthIndicator extends StatelessWidget {
  final int strength; // 0: 약함, 1~2: 보통, 3: 강함

  const PasswordStrengthIndicator({
    super.key,
    required this.strength,
  });

  @override
  Widget build(BuildContext context) {
    Color getColor(int index) {
      if (strength == 0) return AppColors.grey300;
      if (index >= strength) return AppColors.grey300;
      if (strength <= 2) return AppColors.warning;
      return AppColors.success;
    }

    String getLabel() {
      if (strength == 0) return '약함';
      if (strength <= 2) return '보통';
      return '강함';
    }

    Color getLabelColor() {
      if (strength == 0) return AppColors.errorDark;
      if (strength <= 2) return AppColors.warningDark;
      return AppColors.successDark;
    }

    return Row(
      children: [
        Expanded(
          child: Container(
            height: ResponsiveHelper.spacing(context, 4),
            decoration: BoxDecoration(
              color: getColor(1),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
        SizedBox(width: ResponsiveHelper.spacing(context, 4)),
        Expanded(
          child: Container(
            height: ResponsiveHelper.spacing(context, 4),
            decoration: BoxDecoration(
              color: getColor(2),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
        SizedBox(width: ResponsiveHelper.spacing(context, 4)),
        Expanded(
          child: Container(
            height: ResponsiveHelper.spacing(context, 4),
            decoration: BoxDecoration(
              color: getColor(3),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
        SizedBox(width: ResponsiveHelper.spacing(context, 8)),
        Text(
          getLabel(),
          style: ResponsiveHelper.smallStyle(context).copyWith(
            color: getLabelColor(),
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Admin Workflow Modal Primitives
// ──────────────────────────────────────────────────────────────────────────────
// 대형 관리자 워크플로우 다이얼로그용 공통 primitive.
//
// 역할 분리:
//   StyledDialog    — 아이콘+제목+버튼 형식의 소형 시맨틱 다이얼로그
//   DialogHelper    — confirm / alert / sheet 등 시맨틱 호출 전용
//   AppModalShell   — 탭·통계·배치 등 대형 관리자 워크플로우 Dialog 래퍼
//   AppModalHeader  — flat white + 3px brand accent bar 헤더
//   AppModalFooter  — 흰 배경 + grey200 상단 구분선 푸터 wrapper
//
// 새 Admin Dialog 개발 시:
//   AppModalShell(children: [
//     AppModalHeader(title: '...', subtitle: '...', onClose: () => Navigator.pop(context)),
//     Flexible(child: body),
//     AppModalFooter(child: Row([...])),
//   ])
// ══════════════════════════════════════════════════════════════════════════════

/// 대형 워크플로우 다이얼로그 외부 껍데기.
///
/// Dialog 배경·shape·insetPadding·maxHeight·viewInsets를 [AppDialogSize] 기준으로 표준화한다.
/// children에는 [AppModalHeader] / [Flexible(body)] / interstitials / [AppModalFooter]를
/// 순서대로 전달한다.
class AppModalShell extends StatelessWidget {
  final List<Widget> children;

  const AppModalShell({
    super.key,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return DialogFocusSafeArea(
      child: Dialog(
        backgroundColor: Colors.white,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(AppDialogSize.borderRadius)),
        ),
        insetPadding: const EdgeInsets.symmetric(
          horizontal: AppDialogSize.insetH,
          vertical: AppDialogSize.insetV,
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * AppDialogSize.maxHeightRatio
                - MediaQuery.of(context).viewInsets.bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: children,
          ),
        ),
      ),
    );
  }
}

/// ALfit modal grammar 표준 헤더.
///
/// flat white + 3px brand accent bar + title / optional subtitle +
/// optional trailing (사업장 드롭다운 등) + close 버튼 + grey200 하단 구분선.
///
/// 기본 accent는 [Theme.of(context).primaryColor] (#1565C0).
/// 특별한 이유가 있는 화면만 [accentColor]로 override.
class AppModalHeader extends StatelessWidget {
  /// 굵은 제목 — [AppTextStyles.jobTitle()] (17sp / w700)
  final String title;

  /// 부제목 — 날짜·설명 등 — [AppTextStyles.meta()] (14sp / w400, 선택)
  final String? subtitle;

  /// 닫기 버튼 콜백. null이면 닫기 버튼 미표시.
  final VoidCallback? onClose;

  /// 제목 Row 아래에 표시할 위젯 — 사업장 드롭다운 등 (선택).
  final Widget? trailing;

  /// accent bar 색상 기본값: [Theme.of(context).primaryColor]
  final Color? accentColor;

  const AppModalHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.onClose,
    this.trailing,
    this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    final accent = accentColor ?? Theme.of(context).primaryColor;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(AppDialogSize.borderRadius),
          topRight: Radius.circular(AppDialogSize.borderRadius),
        ),
        border: const Border(bottom: BorderSide(color: AppColors.grey200)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // 3px brand accent bar (ALfit modal grammar)
              Container(
                width: 3,
                height: 36,
                decoration: BoxDecoration(
                  color: accent,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: AppTextStyles.jobTitle()),
                    if (subtitle != null)
                      Text(subtitle!,
                          semanticsLabel: TextLayout.plain(subtitle!),
                          style: AppTextStyles.meta()),
                  ],
                ),
              ),
              if (onClose != null)
                IconButton(
                  onPressed: onClose,
                  icon: const Icon(Icons.close, color: AppColors.grey500, size: 20),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
                ),
            ],
          ),
          if (trailing != null) ...[
            const SizedBox(height: 12),
            trailing!,
          ],
        ],
      ),
    );
  }
}

/// 대형 워크플로우 다이얼로그 하단 푸터 wrapper.
///
/// [Colors.white] 배경 + [AppColors.grey200] 상단 구분선 + 표준 padding.
/// [child]에는 실제 버튼 Row 등 footer 콘텐츠를 전달한다.
/// footer가 slim한 경우 [padding]으로 vertical을 조정해 override 가능.
class AppModalFooter extends StatelessWidget {
  final Widget child;

  /// 기본값: symmetric(horizontal: 16, vertical: 10)
  final EdgeInsetsGeometry padding;

  const AppModalFooter({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AppColors.grey200)),
      ),
      child: child,
    );
  }
}