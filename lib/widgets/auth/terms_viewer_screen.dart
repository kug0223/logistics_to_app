import 'package:flutter/material.dart';

import '../../models/core/legal_terms_model.dart';
import '../../utils/responsive_helper.dart';
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
              child: _buildBody(context),
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

          // 타이틀 + 버전
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.item.title,
                  style: ResponsiveHelper.bodyStyle(
                    context,
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
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
            ),
          ),
        ],
      ),
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
          Text(
            '끝까지 읽으면 동의할 수 있습니다',
            style: ResponsiveHelper.tinyStyle(
              context,
              color: AppColors.textTertiary,
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
          child: Text(
            line,
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
                disabledForegroundColor: AppColors.grey400,
                elevation: 0,
                padding: EdgeInsets.symmetric(
                  vertical: sp(context, 14),
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(
                _reachedBottom ? '동의하고 닫기' : '내용을 끝까지 확인해주세요',
                style: ResponsiveHelper.bodyStyle(
                  context,
                  fontWeight: FontWeight.w600,
                ),
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
              '동의하지 않고 닫기',
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
