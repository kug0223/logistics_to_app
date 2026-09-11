import 'package:flutter/material.dart';

import '../../models/core/contract_template_model.dart';
import '../../theme/app_colors.dart';
import '../../utils/contract_article_parser.dart';
import '../../utils/navigation_helper.dart';
import '../../utils/responsive_helper.dart';
import '../../widgets/common/app_page_scaffold.dart';
import '../../widgets/common/notification_badge.dart';
import '../common/notification_screen.dart';
import 'contract_template_edit_screen.dart';

/// 기존 계약서 파싱 결과 확인 화면
///
/// 파싱된 조항 목록을 표시하고, 각 조항의 포함 여부를 관리자가 선택한다.
/// [편집으로 이동] 시 선택된 조항만 [ContractTemplateEditScreen]으로 전달한다.
///
/// Returns: true (편집 화면 → 저장 완료)
class ContractImportResultScreen extends StatefulWidget {
  final String businessId;
  final String templateType;
  final ParseResult parseResult;

  const ContractImportResultScreen({
    super.key,
    required this.businessId,
    required this.templateType,
    required this.parseResult,
  });

  @override
  State<ContractImportResultScreen> createState() =>
      _ContractImportResultScreenState();
}

class _ContractImportResultScreenState
    extends State<ContractImportResultScreen> {
  late final List<ParsedArticle> _articles;

  /// [UX-P2-06] 전문이 펼쳐진 조항 index.
  ///
  /// 화면 세션에만 존재하는 순수 UI 상태다 — ParsedArticle/Firestore/parser
  /// 어디에도 저장하지 않으며 included 여부와 완전히 독립이다.
  /// 여러 조항을 동시에 펼쳐 서로 비교할 수 있도록 Set으로 둔다(아코디언 아님).
  final Set<int> _expanded = {};

  @override
  void initState() {
    super.initState();
    // ParsedArticle.included 는 mutable이므로 UI 토글 시 setState만 필요
    _articles = widget.parseResult.articles;
  }

  int get _includedCount => _articles.where((a) => a.included).length;

  // ─── 편집으로 이동 ────────────────────────────────────────────
  Future<void> _goEdit() async {
    final selectedArticles = _articles
        .where((a) => a.included)
        .map((a) => ContractArticle(title: a.title, content: a.content))
        .toList();

    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => ContractTemplateEditScreen(
          businessId: widget.businessId,
          initialTemplateType: widget.templateType,
          initialArticles: selectedArticles,
        ),
      ),
    );
    if (saved == true && mounted) Navigator.pop(context, true);
  }

  // ─── build ────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final systemCount = widget.parseResult.systemRangeCount;
    final warnCount = widget.parseResult.likelyDuplicateCount;
    final total = widget.parseResult.totalCount;

    return AppPageScaffold(
      title: '가져온 내용 확인',
      actions: [
        IconButton(
          icon: const Icon(Icons.home_outlined),
          color: AppColors.textSecondary,
          onPressed: () => NavigationHelper.goHome(context),
          tooltip: '홈',
        ),
        NotificationBadge(
          child: IconButton(
            icon: const Icon(Icons.notifications_outlined),
            color: AppColors.textSecondary,
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const NotificationScreen()),
            ),
            tooltip: '알림',
          ),
        ),
      ],
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            ResponsiveHelper.spacing(context, 16),
            ResponsiveHelper.spacing(context, 8),
            ResponsiveHelper.spacing(context, 16),
            ResponsiveHelper.spacing(context, 16),
          ),
          child: ElevatedButton(
            onPressed: _goEdit,
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).primaryColor,
              foregroundColor: Colors.white,
              padding: EdgeInsets.symmetric(
                  vertical: ResponsiveHelper.spacing(context, 16)),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              elevation: 0,
            ),
            child: Text(
              _includedCount > 0
                  ? '선택한 조항 $_includedCount개로 편집 시작'
                  : '빈 템플릿으로 편집 시작',
              style: ResponsiveHelper.bodyStyle(context).copyWith(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      ),
      body: ListView(
        padding: ResponsiveHelper.listPadding(context),
        children: [
          // ─── 요약 헤더 ──────────────────────────────────────────
          _SummaryHeader(
            total: total,
            systemCount: systemCount,
            warnCount: warnCount,
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 12)),

          // ─── PII 배너 ────────────────────────────────────────────
          if (widget.parseResult.hasAnyPii) ...[
            _PiiBanner(),
            SizedBox(height: ResponsiveHelper.spacing(context, 12)),
          ],

          // ─── 편집 안내 ──────────────────────────────────────────
          Text(
            '가져올 조항을 선택하세요. 편집 화면에서 내용을 수정하거나 조항을 추가/삭제할 수 있습니다.',
            style: ResponsiveHelper.smallStyle(context,
                color: AppColors.grey500),
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 12)),

          // ─── 조항 목록 ──────────────────────────────────────────
          ..._articles.asMap().entries.map((e) => ImportArticleCard(
                article: e.value,
                index: e.key,
                expanded: _expanded.contains(e.key),
                onToggle: () => setState(() {
                  e.value.included = !e.value.included;
                }),
                onToggleExpand: () => setState(() {
                  // include 상태는 건드리지 않는다 — 표시 전용 토글
                  if (!_expanded.remove(e.key)) _expanded.add(e.key);
                }),
              )),

          SizedBox(height: ResponsiveHelper.spacing(context, 8)),
        ],
      ),
    );
  }
}

// ─── 요약 헤더 ────────────────────────────────────────────────────

class _SummaryHeader extends StatelessWidget {
  final int total;
  final int systemCount;
  final int warnCount;

  const _SummaryHeader({
    required this.total,
    required this.systemCount,
    required this.warnCount,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 14)),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.grey200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.check_circle_outline,
                  color: AppColors.success,
                  size: ResponsiveHelper.iconSize(context, 18)),
              SizedBox(width: ResponsiveHelper.spacing(context, 8)),
              Text(
                '$total개 조항을 찾았습니다.',
                style: ResponsiveHelper.bodyStyle(context)
                    .copyWith(fontWeight: FontWeight.bold),
              ),
            ],
          ),
          if (systemCount > 0) ...[
            SizedBox(height: ResponsiveHelper.spacing(context, 6)),
            Row(
              children: [
                Icon(Icons.info_outline,
                    color: AppColors.info,
                    size: ResponsiveHelper.iconSize(context, 14)),
                SizedBox(width: ResponsiveHelper.spacing(context, 6)),
                Expanded(
                  child: Text(
                    '$systemCount개 항목은 ALfit이 자동 작성합니다. (제1~3조)',
                    style: ResponsiveHelper.tinyStyle(context,
                        color: AppColors.info),
                  ),
                ),
              ],
            ),
          ],
          if (warnCount > 0) ...[
            SizedBox(height: ResponsiveHelper.spacing(context, 4)),
            Row(
              children: [
                Icon(Icons.warning_amber_outlined,
                    color: AppColors.warning,
                    size: ResponsiveHelper.iconSize(context, 14)),
                SizedBox(width: ResponsiveHelper.spacing(context, 6)),
                Expanded(
                  child: Text(
                    '$warnCount개 조항이 ALfit 자동 작성 내용과 겹칠 수 있습니다.',
                    style: ResponsiveHelper.tinyStyle(context,
                        color: AppColors.warning),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

// ─── PII 배너 ──────────────────────────────────────────────────────

class _PiiBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 12)),
      decoration: BoxDecoration(
        color: AppColors.warningBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
            color: AppColors.warning.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.person_search_outlined,
              size: ResponsiveHelper.iconSize(context, 16),
              color: AppColors.warning),
          SizedBox(width: ResponsiveHelper.spacing(context, 8)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '개인정보로 보이는 내용이 있습니다.',
                  style: ResponsiveHelper.smallStyle(context)
                      .copyWith(
                          color: AppColors.warningDark,
                          fontWeight: FontWeight.w600),
                ),
                SizedBox(height: ResponsiveHelper.spacing(context, 2)),
                Text(
                  '특정 근로자의 정보가 포함되어 있다면 '
                  '템플릿 저장 전에 확인해 주세요.',
                  style: ResponsiveHelper.tinyStyle(context,
                      color: AppColors.warningDark),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── 조항 카드 ────────────────────────────────────────────────────

/// 검수용 조항 카드.
///
/// 기본은 compact scan(본문 2줄) 상태를 유지하고, 넘치는 조항만
/// `전문 보기`로 그 자리에서 펼친다. 이 화면은 문서 reader가 아니라
/// "가져올 조항을 선별하는 검수 화면"이므로 전체 펼침을 기본으로 두지 않는다.
///
/// 테스트에서 화면 전체(Provider 의존)를 띄우지 않고 카드만 검증할 수 있도록
/// public으로 노출한다.
class ImportArticleCard extends StatelessWidget {
  final ParsedArticle article;
  final int index;

  /// 전문 펼침 여부 — 표시 전용. include 여부와 독립.
  final bool expanded;

  /// 포함/제외 토글 (카드 본체 탭)
  final VoidCallback onToggle;

  /// 전문 보기/접기 토글 — include 상태를 바꾸지 않는다.
  final VoidCallback onToggleExpand;

  const ImportArticleCard({
    super.key,
    required this.article,
    required this.index,
    required this.expanded,
    required this.onToggle,
    required this.onToggleExpand,
  });

  /// 제외된 조항도 펼쳤을 때는 본문이 읽혀야 한다 —
  /// 카드/칩은 muted로 두되 본문 텍스트는 가독 수준을 유지한다.
  Color _contentColor() =>
      (article.included || expanded) ? AppColors.grey500 : AppColors.grey400;

  Widget _buildContent(BuildContext context) {
    final style = ResponsiveHelper.tinyStyle(context, color: _contentColor());

    // 펼친 상태: 전문 + [접기]. overflow 계산 불필요.
    if (expanded) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(article.content, style: style),
          SizedBox(height: ResponsiveHelper.spacing(context, 6)),
          _ExpandControl(expanded: true, onTap: onToggleExpand),
        ],
      );
    }

    // 접힌 상태: 실제 레이아웃 기준으로 2줄을 넘치는지 판정한다.
    // 문자 수 같은 임의 기준을 쓰지 않는다.
    return LayoutBuilder(
      builder: (ctx, constraints) {
        final painter = TextPainter(
          text: TextSpan(text: article.content, style: style),
          maxLines: 2,
          textDirection: Directionality.of(ctx),
          textScaler: MediaQuery.textScalerOf(ctx),
        )..layout(maxWidth: constraints.maxWidth);
        final overflows = painter.didExceedMaxLines;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              article.content,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: style,
            ),
            // 2줄 안에 다 보이면 컨트롤을 띄우지 않는다.
            if (overflows) ...[
              SizedBox(height: ResponsiveHelper.spacing(context, 6)),
              _ExpandControl(expanded: false, onTap: onToggleExpand),
            ],
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isSystem = article.isExactSystemRange;
    final isWarn = article.isLikelyDuplicate && !isSystem;

    Color borderColor = AppColors.grey200;
    Color bgColor = AppColors.surface;
    if (isSystem && article.included) {
      borderColor = AppColors.info.withValues(alpha: 0.5);
      bgColor = AppColors.infoBg.withValues(alpha: 0.5);
    } else if (!article.included) {
      bgColor = AppColors.grey100;
      borderColor = AppColors.grey200;
    }

    return GestureDetector(
      onTap: onToggle,
      child: Container(
        margin: EdgeInsets.only(
            bottom: ResponsiveHelper.spacing(context, 10)),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: article.included
                ? (isSystem
                    ? AppColors.info.withValues(alpha: 0.4)
                    : Theme.of(context).primaryColor.withValues(alpha: 0.3))
                : borderColor,
          ),
        ),
        child: Padding(
          padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 14)),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 체크박스
              Icon(
                article.included
                    ? Icons.check_box_outlined
                    : Icons.check_box_outline_blank,
                color: article.included
                    ? Theme.of(context).primaryColor
                    : AppColors.grey400,
                size: ResponsiveHelper.iconSize(context, 22),
              ),
              SizedBox(width: ResponsiveHelper.spacing(context, 12)),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 제목
                    Text(
                      article.title.isEmpty
                          ? '(제목 없음)'
                          : article.title,
                      style: ResponsiveHelper.bodyStyle(context).copyWith(
                        fontWeight: FontWeight.w600,
                        color: article.included
                            ? null
                            : AppColors.grey400,
                      ),
                    ),

                    // 내용 — 기본 2줄, 넘칠 때만 [전문 보기] 제공
                    if (article.content.isNotEmpty) ...[
                      SizedBox(height: ResponsiveHelper.spacing(context, 4)),
                      _buildContent(context),
                    ],

                    // 경고 뱃지
                    if (isSystem) ...[
                      SizedBox(height: ResponsiveHelper.spacing(context, 8)),
                      _WarningChip(
                        icon: Icons.info_outline,
                        color: AppColors.info,
                        bgColor: AppColors.infoBg,
                        label: 'ALfit에서 자동 작성되는 항목과 겹칩니다.',
                      ),
                      SizedBox(height: ResponsiveHelper.spacing(context, 4)),
                      Text(
                        '계약 당사자, 근무조건, 임금은 공고·지원서 정보를 이용해 자동 작성됩니다.',
                        style: ResponsiveHelper.tinyStyle(context,
                            color: AppColors.grey500),
                      ),
                    ] else if (isWarn) ...[
                      SizedBox(height: ResponsiveHelper.spacing(context, 8)),
                      _WarningChip(
                        icon: Icons.warning_amber_outlined,
                        color: AppColors.warning,
                        bgColor: AppColors.warningBg,
                        label: 'ALfit에서 자동 작성되는 근로조건과 내용이 겹칠 수 있습니다.',
                      ),
                    ],

                    if (article.hasPii) ...[
                      SizedBox(height: ResponsiveHelper.spacing(context, 6)),
                      _WarningChip(
                        icon: Icons.person_outlined,
                        color: AppColors.errorMedium,
                        bgColor: AppColors.error.withValues(alpha: 0.08),
                        label: '개인정보가 있을 수 있습니다. 저장 전 확인해 주세요.',
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── 전문 보기 / 접기 컨트롤 ──────────────────────────────────────

/// 카드 본체 탭(포함/제외)과 분리된 펼침 컨트롤.
///
/// 중첩 GestureDetector에서는 안쪽이 탭 arena를 가져가므로
/// 이 영역을 눌러도 include/exclude가 바뀌지 않는다.
class _ExpandControl extends StatelessWidget {
  final bool expanded;
  final VoidCallback onTap;

  const _ExpandControl({required this.expanded, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).primaryColor;
    return Semantics(
      button: true,
      expanded: expanded,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Padding(
          // 탭 영역 확보 — 본문과 붙어 오탭되지 않도록 세로 여백을 둔다.
          padding: EdgeInsets.symmetric(
            vertical: ResponsiveHelper.spacing(context, 4),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                expanded ? '접기' : '전문 보기',
                style: ResponsiveHelper.tinyStyle(context, color: color)
                    .copyWith(fontWeight: FontWeight.w600),
              ),
              SizedBox(width: ResponsiveHelper.spacing(context, 2)),
              Icon(
                expanded ? Icons.expand_less : Icons.expand_more,
                size: ResponsiveHelper.iconSize(context, 14),
                color: color,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── 경고 chip ────────────────────────────────────────────────────

class _WarningChip extends StatelessWidget {
  final IconData icon;
  final Color color;
  final Color bgColor;
  final String label;

  const _WarningChip({
    required this.icon,
    required this.color,
    required this.bgColor,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 8),
        vertical: ResponsiveHelper.spacing(context, 4),
      ),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon,
              size: ResponsiveHelper.iconSize(context, 12),
              color: color),
          SizedBox(width: ResponsiveHelper.spacing(context, 4)),
          Flexible(
            child: Text(
              label,
              style: ResponsiveHelper.tinyStyle(context, color: color),
            ),
          ),
        ],
      ),
    );
  }
}
