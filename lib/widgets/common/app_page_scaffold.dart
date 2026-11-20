// lib/widgets/common/app_page_scaffold.dart
//
// ALfit flat screen foundation — role-independent minimal scaffold.
// ADMIN flat header 표준. GradientScaffold의 신규 ADMIN 화면 대안.
//
// 설계 원칙:
// - Business-agnostic: 도메인 파라미터 없음
// - 홈/알림 버튼은 actions 파라미터로 caller가 전달 (재사용·테스트 용이)
// - AppBar(elevation:0, white) + 1px grey200 divider

import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import '../../utils/text_layout.dart';

class AppPageScaffold extends StatelessWidget {
  const AppPageScaffold({
    super.key,
    required this.title,
    required this.body,
    this.actions = const [],
    this.bottom,
    this.backgroundColor,
    this.floatingActionButton,
    this.floatingActionButtonLocation,
    this.resizeToAvoidBottomInset = true,
    this.bottomNavigationBar,
  });

  final String title;
  final Widget body;

  /// AppBar 우상단 액션 목록 (홈·알림·새로고침 등 caller가 전달)
  final List<Widget> actions;

  /// AppBar 하단 위젯 — TabBar 등 PreferredSizeWidget.
  /// 전달 시 내부에서 1px grey200 divider가 자동으로 아래에 추가됨.
  /// null이면 AppBar 아래 1px divider만 표시.
  final PreferredSizeWidget? bottom;

  /// 화면 배경색 (기본: AppColors.background = grey100)
  final Color? backgroundColor;

  final Widget? floatingActionButton;
  final FloatingActionButtonLocation? floatingActionButtonLocation;
  final bool resizeToAvoidBottomInset;

  /// 하단 고정 버튼 영역 — SafeArea(top: false)로 감싸서 전달.
  /// Scaffold.bottomNavigationBar에 그대로 전달됨.
  final Widget? bottomNavigationBar;

  static const _titleStyle = TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.w800,
    color: AppColors.textPrimary,
    letterSpacing: -0.5,
  );

  @override
  Widget build(BuildContext context) {
    PreferredSizeWidget effectiveBottom;
    if (bottom != null) {
      effectiveBottom = _BottomWithDivider(content: bottom!);
    } else {
      effectiveBottom = const _SingleDivider();
    }

    // [COMMON-TEXT-LAYOUT.28] 제목이 툴바 한 줄 자리에 넘칠 때만 — 제목을 툴바 아래 **전체 폭 줄**로 내린다.
    //   좁은 폭·큰 글자·액션이 많은 화면에서 '급여 지…' 로 잘렸다. 툴바 안에서 두 줄로 늘려도
    //   320dp·글자 1.3 에서는 제목 자리가 84dp 뿐이라 '급여 / 지급 …' 이 됐다(기기 실측).
    //   글자는 줄이지 않는다(사용자 글자 배율 그대로). 넘치지 않으면 예전과 똑같다.
    final below = _titleOverflows(context);
    if (below) effectiveBottom = _TitleBelow(title: title, style: _titleStyle, under: effectiveBottom, context: context);

    return Scaffold(
      backgroundColor: backgroundColor ?? AppColors.background,
      resizeToAvoidBottomInset: resizeToAvoidBottomInset,
      floatingActionButton: floatingActionButton,
      floatingActionButtonLocation: floatingActionButtonLocation,
      bottomNavigationBar: bottomNavigationBar,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
        title: below
            ? null
            : Text(title,
                style: _titleStyle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
        actions: actions.isEmpty
            ? null
            : [...actions, const SizedBox(width: 4)],
        bottom: effectiveBottom,
      ),
      body: body,
    );
  }

  /// 제목 한 줄 폭 > 제목 자리(화면 폭 − 뒤로 버튼 − 액션 48씩 − 여백). 화면당 한 번 잰다.
  bool _titleOverflows(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final canPop = ModalRoute.of(context)?.impliesAppBarDismissal ?? false;
    final available = width -
        (canPop ? kToolbarHeight : NavigationToolbar.kMiddleSpacing) -
        actions.length * 48.0 -
        4 -
        NavigationToolbar.kMiddleSpacing * 2;
    final painter = TextPainter(
      text: TextSpan(text: title, style: DefaultTextStyle.of(context).style.merge(_titleStyle)),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    final over = painter.width > available;
    painter.dispose();
    return over;
  }
}

/// 툴바 아래 전체 폭 제목 줄 + 원래 bottom. 두 줄까지(낱말 안에서는 끊지 않는다 — '급여 지 / 급 현황' 방지),
///   그래도 모자라면 그때만 말줄임. 높이는 실제 글자 배치로 잰다.
class _TitleBelow extends StatelessWidget implements PreferredSizeWidget {
  _TitleBelow({
    required String title,
    required this.style,
    required this.under,
    required BuildContext context,
  })  : text = TextLayout.keepWords(title),
        label = title,
        resolved = _resolve(context, style),
        _height = _measure(TextLayout.keepWords(title), _resolve(context, style), context);

  final String text;
  final String label;
  final TextStyle style;
  final PreferredSizeWidget under;
  final double _height;

  /// [DU1 구현91 S012] 측정과 렌더가 **같은 스타일**을 쓴다.
  ///   예전에는 높이를 `DefaultTextStyle.of(context)` 로 쟀다. 이 context 는 Scaffold 의 Material **위**라 테마 글꼴이 아니라
  ///   기본 대체 스타일(줄 높이 다름)이었다. 그러나 실제 Text 는 AppBar(Material) 안에서 테마 본문 스타일을 물려받아 줄이 더 높았고,
  ///   말줄임 설정 때문에 넘친 아래쪽이 잘렸다(사업장 상세: '수도권' 받침이 잘려 '수도귀' 처럼 보임).
  ///   테마 bodyMedium(= Material 이 내리는 기본 글자) 위에 제목 스타일을 합친 값 하나로 재고 그린다. 툴바 안/아래 판정은 무변경.
  final TextStyle resolved;

  static TextStyle _resolve(BuildContext context, TextStyle style) =>
      (Theme.of(context).textTheme.bodyMedium ?? const TextStyle()).merge(style);

  static const double _hPad = NavigationToolbar.kMiddleSpacing;
  static const double _bottomPad = 10;

  static double _measure(String text, TextStyle style, BuildContext context) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 2,
      ellipsis: '…',
    )..layout(maxWidth: MediaQuery.sizeOf(context).width - _hPad * 2);
    final h = painter.height;
    painter.dispose();
    return h + _bottomPad;
  }

  @override
  Size get preferredSize => Size.fromHeight(_height + under.preferredSize.height);

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: _height,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(_hPad, 0, _hPad, _bottomPad),
            child: Text(text,
                semanticsLabel: label,
                style: resolved,
                maxLines: 2,
                overflow: TextOverflow.ellipsis),
          ),
        ),
        under,
      ],
    );
  }
}

/// AppBar bottom이 없을 때 표시되는 1px 구분선
class _SingleDivider extends StatelessWidget implements PreferredSizeWidget {
  const _SingleDivider();

  @override
  Size get preferredSize => const Size.fromHeight(1);

  @override
  Widget build(BuildContext context) =>
      Container(height: 1, color: AppColors.grey200);
}

/// TabBar 등 PreferredSizeWidget 아래에 1px 구분선을 추가하는 래퍼
class _BottomWithDivider extends StatelessWidget implements PreferredSizeWidget {
  const _BottomWithDivider({required this.content});

  final PreferredSizeWidget content;

  @override
  Size get preferredSize => Size.fromHeight(content.preferredSize.height + 1);

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        content,
        Container(height: 1, color: AppColors.grey200),
      ],
    );
  }
}
