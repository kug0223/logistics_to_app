import 'package:flutter/material.dart';

import '../../services/posting_quota_summary.dart';
import '../../theme/app_colors.dart';
import '../../utils/dialog_helper.dart';
import '../../utils/responsive_helper.dart';
import '../../utils/text_layout.dart';

/// [POSTING-QUOTA-45] 공고 탭 머리말의 한도 요약.
///
///   숫자는 서버 요약 응답에서만 온다([PostingQuotaStore]). 확인하지 못하면 숫자를 쓰지 않는다 —
///   0·기본 4·무제한 어느 것도 사실이 아니다. 등록 버튼은 건드리지 않는다(막는 것은 서버다).
///   권한이 없는 사업장(denied)은 여기서 말하지 않는다 — 공고 탭의 권한 안내가 그 자리다.
class PostingQuotaSummaryBar extends StatelessWidget {
  const PostingQuotaSummaryBar({
    super.key,
    required this.snapshot,
    required this.selectedBusinessId,
    required this.businessNameOf,
    required this.onRetry,
    this.onShowActivePostings,
  });

  final PostingQuotaSnapshot snapshot;

  /// 필터로 고른 사업장. null 이면 요청한 사업장 전체.
  final String? selectedBusinessId;
  final String Function(String businessId) businessNameOf;
  final VoidCallback onRetry;

  /// 한도에 닿았을 때 '진행 중 공고 보기'.
  final VoidCallback? onShowActivePostings;

  /// 화면 읽기용 한 문장 — 숫자·남은 수·공용 범위를 한 번에 읽는다.
  @visibleForTesting
  static String sentenceOf(PostingQuotaScope s, {bool withShared = true}) {
    final head = '진행 중 공고 ${s.used} / ${s.limit}개';
    final String tail;
    if (s.isOverLimit) {
      tail = '한도가 낮아져 새 공고는 등록할 수 없어요';
    } else if (s.isAtLimit) {
      tail = '한도에 도달했어요';
    } else {
      tail = '${s.remaining}개 더 등록할 수 있어요';
    }
    return withShared ? '$head · $tail · $_shared' : '$head · $tail';
  }

  static const String _shared = '관리자·서브관리자 공용 한도';

  @override
  Widget build(BuildContext context) {
    final snap = snapshot;
    // 권한 거절(denied)은 숫자도 '확인 불가' 도 아니다 — 공고 탭의 권한 안내가 그 자리다.
    if (snap.status == PostingQuotaStatus.idle || snap.status == PostingQuotaStatus.denied) {
      return const SizedBox.shrink();
    }
    final value = snap.value;
    if (value == null) {
      if (snap.status == PostingQuotaStatus.failed) return _unavailable(context);
      return _line(context, text: '공고 한도 확인 중', color: AppColors.grey500);
    }

    final sel = selectedBusinessId;
    final List<PostingQuotaScope> shown;
    if (sel != null) {
      final s = value.scopeOf(sel);
      if (s == null) {
        // 고른 사업장의 한도를 확인하지 못했다(권한 없음은 다른 자리에서 말한다).
        return value.denied.contains(sel) ? const SizedBox.shrink() : _unavailable(context);
      }
      shown = [s];
    } else {
      shown = value.scopes;
    }
    final anyFailed = value.failed.isNotEmpty;
    if (shown.isEmpty) return anyFailed ? _unavailable(context) : const SizedBox.shrink();

    final labelled = shown.length > 1;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final s in shown) _scopeRow(context, s, labelled: labelled),
        // 범위가 여럿이면 '공용 한도' 는 줄마다 반복하지 않고 한 번만 말한다.
        if (labelled) _line(context, text: '모두 $_shared', color: AppColors.grey500),
        if (anyFailed && sel == null) _unavailable(context, partial: true),
      ],
    );
  }

  Widget _scopeRow(BuildContext context, PostingQuotaScope s, {required bool labelled}) {
    final reached = s.isAtLimit;
    final color = reached ? AppColors.warning : AppColors.grey600;
    final prefix = labelled ? '${_scopeLabel(s)} · ' : '';
    final sentence = '$prefix${sentenceOf(s, withShared: !labelled)}';
    return Padding(
      padding: EdgeInsets.only(top: ResponsiveHelper.spacing(context, 4)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Semantics(
                  container: true,
                  label: sentence,
                  excludeSemantics: true,
                  child: Text(
                    TextLayout.phrases(sentence),
                    style: ResponsiveHelper.captionStyle(context, color: color,
                        fontWeight: reached ? FontWeight.w600 : FontWeight.w500),
                  ),
                ),
              ),
              IconButton(
                tooltip: '공고 한도 기준',
                onPressed: () => showRuleSheet(context),
                constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
                padding: EdgeInsets.zero,
                icon: Icon(Icons.info_outline, size: ResponsiveHelper.iconSize(context, 16), color: AppColors.grey500),
              ),
            ],
          ),
          // 문장 칸을 좁히지 않도록 링크는 아래 줄에 둔다(큰 글자에서 문장이 세로로 길어졌다).
          if (reached && onShowActivePostings != null)
            TextButton(
              onPressed: onShowActivePostings,
              style: TextButton.styleFrom(
                foregroundColor: AppColors.brand,
                padding: EdgeInsets.symmetric(horizontal: ResponsiveHelper.spacing(context, 2)),
                minimumSize: const Size(48, 36),
                tapTargetSize: MaterialTapTargetSize.padded,
              ),
              child: Text(TextLayout.keepWords('진행 중 공고 보기'), semanticsLabel: '진행 중 공고 보기',
                  style: ResponsiveHelper.captionStyle(context, color: AppColors.brand, fontWeight: FontWeight.w700)),
            ),
        ],
      ),
    );
  }

  String _scopeLabel(PostingQuotaScope s) {
    final names = s.businessIds.map(businessNameOf).toList();
    if (names.isEmpty) return '사업장';
    return names.length == 1 ? names.first : '${names.first} 외 ${names.length - 1}곳';
  }

  Widget _unavailable(BuildContext context, {bool partial = false}) {
    final text = partial ? '일부 사업장은 공고 한도 확인 불가' : '공고 한도 확인 불가';
    return Padding(
      padding: EdgeInsets.only(top: ResponsiveHelper.spacing(context, 4)),
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              container: true,
              label: text,
              excludeSemantics: true,
              child: Text(TextLayout.keepWords(text), semanticsLabel: text,
                  style: ResponsiveHelper.captionStyle(context, color: AppColors.grey600, fontWeight: FontWeight.w500)),
            ),
          ),
          TextButton(
            onPressed: onRetry,
            style: TextButton.styleFrom(
              foregroundColor: AppColors.brand,
              padding: EdgeInsets.symmetric(horizontal: ResponsiveHelper.spacing(context, 6)),
              minimumSize: const Size(48, 40),
            ),
            child: Text(TextLayout.keepWords('다시 시도'), semanticsLabel: '다시 시도',
                style: ResponsiveHelper.captionStyle(context, color: AppColors.brand, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  Widget _line(BuildContext context, {required String text, required Color color}) => Padding(
        padding: EdgeInsets.only(top: ResponsiveHelper.spacing(context, 4)),
        child: Text(TextLayout.keepWords(text),
            semanticsLabel: text, style: ResponsiveHelper.captionStyle(context, color: color)),
      );

  /// 한도 기준 설명 — 무엇이 들어가고 빠지는지.
  static Future<void> showRuleSheet(BuildContext context) {
    return DialogHelper.showSheet<void>(
      context,
      useRootNavigator: true,
      builder: (ctx) => SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(20, 20, 20, ResponsiveHelper.spacing(ctx, 16)),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(TextLayout.keepWords('공고 한도는 이렇게 세요'), semanticsLabel: '공고 한도는 이렇게 세요',
                  style: ResponsiveHelper.subtitleStyle(ctx, fontWeight: FontWeight.w700)),
              SizedBox(height: ResponsiveHelper.spacing(ctx, 10)),
              Text(TextLayout.keepWords('같은 소유자의 모든 사업장에서 관리자와 서브관리자가 등록한 대상 공고를 합산합니다.'), semanticsLabel: '같은 소유자의 모든 사업장에서 관리자와 서브관리자가 등록한 대상 공고를 합산합니다.',
                  style: ResponsiveHelper.bodyStyle(ctx)),
              SizedBox(height: ResponsiveHelper.spacing(ctx, 12)),
              _ruleLine(ctx, '포함', '모집 중인 공고, 인원이 모두 찬 공고'),
              SizedBox(height: ResponsiveHelper.spacing(ctx, 6)),
              _ruleLine(ctx, '제외', '임시 저장·예약 공개 공고, 종료한 공고, 모집 기간이 지난 공고, 삭제한 공고'),
              SizedBox(height: ResponsiveHelper.spacing(ctx, 12)),
              Text(TextLayout.keepWords('한도가 낮아져도 진행 중인 공고는 그대로 유지되고, 새 공고 등록만 막혀요. 한도는 운영자가 정해요.'), semanticsLabel: '한도가 낮아져도 진행 중인 공고는 그대로 유지되고, 새 공고 등록만 막혀요. 한도는 운영자가 정해요.',
                  style: ResponsiveHelper.smallStyle(ctx, color: AppColors.textSecondary)),
            ],
          ),
        ),
      ),
    );
  }

  static Widget _ruleLine(BuildContext ctx, String head, String body) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(TextLayout.keepWords(head), semanticsLabel: head,
              style: ResponsiveHelper.smallStyle(ctx, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
          SizedBox(width: ResponsiveHelper.spacing(ctx, 8)),
          Expanded(child: Text(TextLayout.keepWords(body), semanticsLabel: body, style: ResponsiveHelper.smallStyle(ctx, color: AppColors.textSecondary))),
        ],
      );
}
