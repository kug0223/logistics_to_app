import 'package:flutter/material.dart';

import '../../models/core/legal_terms_model.dart';
import '../../utils/responsive_helper.dart';
import '../../utils/text_layout.dart';
import '../../theme/app_colors.dart';

/// 약관 전문 뷰어 — 내국인·외국인 가입 공용
///
/// 디자인: 화이트 베이스, 가입 플로우 통일 스타일
/// - 파란 AppBar 제거 → 인라인 헤더 (닫기 X 아이콘 + 타이틀 + 버전)
/// - 약관 본문 스크롤 → 끝 도달 시 '동의하고 닫기' 활성화
/// - 반환값: true (동의), null (미동의/닫기)
class TermsViewerScreen extends StatefulWidget {
  final LegalTermsItem item;
  const TermsViewerScreen({super.key, required this.item});

  @override
  State<TermsViewerScreen> createState() => _TermsViewerScreenState();
}

class _TermsViewerScreenState extends State<TermsViewerScreen> {
  final _scrollCtrl = ScrollController();
  bool _reachedBottom = false;

  @override
  void initState() {
    super.initState();
    _scrollCtrl.addListener(_onScroll);
    // 짧은 약관은 처음부터 동의 가능
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients &&
          _scrollCtrl.position.maxScrollExtent < 50) {
        setState(() => _reachedBottom = true);
      }
    });
  }

  void _onScroll() {
    if (_reachedBottom) return;
    final pos = _scrollCtrl.position;
    if (pos.pixels >= pos.maxScrollExtent - 80) {
      setState(() => _reachedBottom = true);
    }
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sp = ResponsiveHelper.spacing;

    return Scaffold(
      backgroundColor: Colors.white,
      // AppBar 없음 — 인라인 헤더로 대체
      body: Column(
        children: [
          // ── 상단 헤더 ─────────────────────────────────────────────
          SafeArea(
            bottom: false,
            child: _buildHeader(context, theme, sp),
          ),

          // ── 구분선 ────────────────────────────────────────────────
          const Divider(height: 1, thickness: 1, color: AppColors.grey200),

          // ── 스크롤 안내 배너 (끝까지 읽지 않았을 때만) ────────────
          if (!_reachedBottom) _buildScrollHint(context, sp),

          // ── 약관 본문 ─────────────────────────────────────────────
          Expanded(
            child: SingleChildScrollView(
              controller: _scrollCtrl,
              padding: EdgeInsets.symmetric(
                horizontal: sp(context, 20),
                vertical: sp(context, 20),
              ),
              child: _titleInBody(context)
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildTitleBlock(context, sp),
                        SizedBox(height: sp(context, 12)),
                        _buildBody(context),
                      ],
                    )
                  : _buildBody(context),
            ),
          ),

          // ── 하단 CTA ─────────────────────────────────────────────
          const Divider(height: 1, thickness: 1, color: AppColors.grey200),
          SafeArea(
            top: false,
            child: _buildCta(context, theme, sp),
          ),
        ],
      ),
    );
  }

  // ── 헤더 ─────────────────────────────────────────────────────────
  Widget _buildHeader(BuildContext context, ThemeData theme,
      double Function(BuildContext, double) sp) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        sp(context, 4),
        sp(context, 8),
        sp(context, 16),
        sp(context, 12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // 닫기 X 아이콘 버튼
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.close, color: AppColors.grey700),
            iconSize: ResponsiveHelper.iconSize(context, 22),
            splashRadius: 24,
            tooltip: '닫기',
          ),
          SizedBox(width: sp(context, 4)),

          // 타이틀 + 버전 — 큰 글자 배율에서는 본문 맨 위로 옮긴다(_titleInBody)
          if (!_titleInBody(context)) Expanded(child: _buildTitleBlock(context, sp)),
        ],
      ),
    );
  }

  /// [DU1 후속43 S091] 큰 글자 배율(>1.5)에서 전체 제목을 고정 머리에 두면 머리가 커져 본문 읽기 영역이 104px 까지 줄었다
  ///   (320·2.0 실측). 그때만 제목·버전을 **스크롤 본문 맨 위**로 옮긴다 — 말줄임 없이 전문, 머리에는 닫기만 남는다.
  ///   기본 배율은 기존처럼 머리에 둔다(말줄임 없음).
  bool _titleInBody(BuildContext context) => MediaQuery.textScalerOf(context).scale(1) > 1.5;

  Widget _buildTitleBlock(BuildContext context, double Function(BuildContext, double) sp) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // [DU1 후속43 S091] 320·2.0 에서 긴 약관 제목이 2줄 말줄임으로 잘렸다(didExceedMaxLines true) — 어떤 약관인지가
        //   사라진다. 말줄임 없이 단어 단위로 줄바꿈한다(제목 문구 그대로).
        Text(
          TextLayout.keepWords(widget.item.title),
          style: ResponsiveHelper.bodyStyle(
            context,
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w700,
          ),
        ),
        SizedBox(height: sp(context, 2)),
        Text(
          'v${widget.item.version}',
          style: ResponsiveHelper.tinyStyle(
            context,
            color: AppColors.textTertiary,
          ),
        ),
      ],
    );
  }

  // ── 스크롤 안내 배너 ─────────────────────────────────────────────
  Widget _buildScrollHint(BuildContext context,
      double Function(BuildContext, double) sp) {
    return Container(
      width: double.infinity,
      color: AppColors.grey50,
      padding: EdgeInsets.symmetric(
        horizontal: sp(context, 20),
        vertical: sp(context, 8),
      ),
      child: Row(
        children: [
          const Icon(Icons.keyboard_arrow_down,
              size: 15, color: AppColors.grey500),
          SizedBox(width: sp(context, 6)),
          // [DU1 후속43 S091] 320·2.0 에서 안내 글이 줄지 않아 오른쪽으로 69px 넘쳤다 — 남은 폭 안에서 줄바꿈(문구 그대로)
          Expanded(
            child: Text(
              TextLayout.keepWords('끝까지 읽으면 동의할 수 있습니다'),
              style: ResponsiveHelper.tinyStyle(
                context,
                color: AppColors.textTertiary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── 약관 본문 ─────────────────────────────────────────────────────
  Widget _buildBody(BuildContext context) {
    // 조문 제목(제N조, 제 N 조 등) 강조: 줄 단위로 파싱
    final lines = widget.item.content.split('\n');
    final articleRe = RegExp(r'^(제\s*\d+\s*조|제\s*\d+\s*장|■|▶|【|[①②③④⑤⑥⑦⑧⑨⑩])');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: lines.map((line) {
        final isArticle = articleRe.hasMatch(line.trimLeft());
        return Padding(
          padding: EdgeInsets.only(
            bottom: isArticle
                ? ResponsiveHelper.spacing(context, 6)
                : ResponsiveHelper.spacing(context, 2),
            top: isArticle
                ? ResponsiveHelper.spacing(context, 12)
                : 0,
          ),
          // [DU338] 본문 줄 낱말 단위(S048 과 같은 보존 규칙, 소급 5 채택) — 줄 · 순서 · 원문 그대로, 낭독은 원문 줄.
          //   한 낱말이 줄보다 길면 Flutter 가 낱말 안에서 강제로 끊으므로 잘리지 않는다.
          child: Text(
            TextLayout.keepWords(line),
            semanticsLabel: line,
            style: isArticle
                ? ResponsiveHelper.smallStyle(
                    context,
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ).copyWith(height: 1.6)
                : ResponsiveHelper.smallStyle(
                    context,
                    color: AppColors.textSecondary,
                  ).copyWith(height: 1.75),
          ),
        );
      }).toList(),
    );
  }

  // ── 하단 CTA ─────────────────────────────────────────────────────
  Widget _buildCta(BuildContext context, ThemeData theme,
      double Function(BuildContext, double) sp) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        sp(context, 16),
        sp(context, 12),
        sp(context, 16),
        sp(context, 16),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 주 버튼: 동의하고 닫기
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed:
                  _reachedBottom ? () => Navigator.pop(context, true) : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: theme.primaryColor,
                disabledBackgroundColor: AppColors.grey200,
                foregroundColor: Colors.white,
                // [DU315] 비활성 글자 grey400 은 grey200 면 위 1.5:1 이라 '내용을 끝까지 확인해주세요'(왜 누를 수 없는지)가
                //   읽히지 않았다. 안내 문장이므로 읽기용 보조색 textSecondary(grey200 위 5.1:1). 면(grey200)은 그대로라 비활성으로 보인다.
                disabledForegroundColor: AppColors.textSecondary,
                elevation: 0,
                // [DU1 후속43 S091] 실측 48(392·1.0) — 공통 기준 주 버튼 52
                minimumSize: const Size.fromHeight(52),
                padding: EdgeInsets.symmetric(
                  vertical: sp(context, 14),
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                // [BTN-FG-01] 글자 스타일을 **버튼 style 로** 준다.
                //   자식 `Text(style: ...)` 에 주면 그 색이 DefaultTextStyle 을
                //   이겨서 위 `foregroundColor`/`disabledForegroundColor` 가
                //   무시된다. `ResponsiveHelper.bodyStyle` 은 색을 안 넘기면
                //   `AppColors.grey700` 을 넣으므로, 파란 버튼 위에 회색
                //   글자가 찍히고 있었다.
                //   `ButtonStyle.textStyle` 의 색은 Flutter 가
                //   `textStyle.copyWith(color: resolvedForegroundColor)` 로
                //   덮으므로(button_style_button.dart), 활성=흰색 ·
                //   비활성=textSecondary([DU315], 이전 grey400) 가 그대로 따라온다.
                textStyle: ResponsiveHelper.bodyStyle(
                  context,
                  fontWeight: FontWeight.w600,
                ),
              ),
              // [DU1 후속43 S091] 320·2.0 에서 '확인해주/세요' 로 낱말이 끊겼다 — 단어 단위(문구·상태 분기 그대로)
              child: Text(
                // [DU1 구현46] 활성 '동의하고 닫기' 는 큰 배율에서도 한 줄(구현43 PNG) — 원문 그대로 두어 문자열 계약(여러 시험의
                //   widgetWithText)을 지킨다. 끊김이 관찰된 비활성 안내 글자만 단어 단위로 묶는다.
                _reachedBottom ? '동의하고 닫기' : TextLayout.keepWords('내용을 끝까지 확인해주세요'),
                // [DU315 b] 큰 배율에서 두 줄이 되면 버튼 왼쪽으로 쏠렸다(320·2.0 캡처) — 가운데 정렬
                textAlign: TextAlign.center,
              ),
            ),
          ),

          // 보조 버튼: 동의하지 않고 닫기
          TextButton(
            onPressed: () => Navigator.pop(context),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.textTertiary,
              padding: EdgeInsets.symmetric(vertical: sp(context, 8)),
            ),
            child: Text(
              TextLayout.keepWords('동의하지 않고 닫기'),
              style: ResponsiveHelper.smallStyle(
                context,
                color: AppColors.textTertiary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
