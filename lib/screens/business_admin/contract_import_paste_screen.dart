import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../utils/contract_article_parser.dart';
import '../../utils/dialog_helper.dart';
import '../../utils/navigation_helper.dart';
import '../../utils/responsive_helper.dart';
import '../../widgets/common/app_page_scaffold.dart';
import '../../widgets/common/notification_badge.dart';
import '../common/notification_screen.dart';
import 'contract_import_result_screen.dart';

/// 기존 계약서 텍스트 붙여넣기 화면
///
/// 사용자가 한글/Word/PDF에서 복사한 계약서 본문을 붙여넣고
/// [조항으로 나누기]를 누르면 [ContractImportResultScreen]으로 이동한다.
///
/// Returns: true (결과 화면 → 편집 화면 → 저장 완료)
class ContractImportPasteScreen extends StatefulWidget {
  final String businessId;
  final String templateType;

  const ContractImportPasteScreen({
    super.key,
    required this.businessId,
    required this.templateType,
  });

  @override
  State<ContractImportPasteScreen> createState() =>
      _ContractImportPasteScreenState();
}

class _ContractImportPasteScreenState
    extends State<ContractImportPasteScreen> {
  final _ctrl = TextEditingController();
  bool _hasText = false;

  @override
  void initState() {
    super.initState();
    _ctrl.addListener(() {
      final v = _ctrl.text.isNotEmpty;
      if (v != _hasText) setState(() => _hasText = v);
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  // ─── 뒤로 나가기 안전 확인 ────────────────────────────────────
  Future<bool> _confirmExit() async {
    if (!_hasText) return true;
    final ok = await DialogHelper.showConfirm(
      context,
      title: '나가시겠어요?',
      message: '입력한 내용이 사라집니다.',
      confirmText: '나가기',
      cancelText: '계속 편집',
    );
    return ok;
  }

  // ─── 조항 분석 실행 ────────────────────────────────────────────
  Future<void> _parse() async {
    final text = _ctrl.text;
    if (text.isEmpty) return;

    final result = ArticleParser.parse(text);

    if (!mounted) return;

    // 0개: 폴백 UX
    if (result.isEmpty) {
      await _showParseFailureSheet(text);
      return;
    }

    // 결과 화면으로 이동
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => ContractImportResultScreen(
          businessId: widget.businessId,
          templateType: widget.templateType,
          parseResult: result,
        ),
      ),
    );
    if (saved == true && mounted) Navigator.pop(context, true);
  }

  // ─── 0개 fallback 시트 ────────────────────────────────────────
  Future<void> _showParseFailureSheet(String text) async {
    final choice = await DialogHelper.showSheet<String>(
      context,
      builder: (ctx) => _ParseFailureSheet(hasText: text.isNotEmpty),
    );
    if (!mounted) return;
    switch (choice) {
      case 'whole':
        // 전체를 하나의 조항으로 강제 생성
        final singleResult = ParseResult(
          articles: [
            ParsedArticle(
              title: '(제목을 입력해주세요)',
              content: text.trim(),
              articleNumber: -1,
              warnings: const {},
              included: true,
            ),
          ],
          hasAnyPii: false,
        );
        final saved = await Navigator.push<bool>(
          context,
          MaterialPageRoute(
            builder: (_) => ContractImportResultScreen(
              businessId: widget.businessId,
              templateType: widget.templateType,
              parseResult: singleResult,
            ),
          ),
        );
        if (saved == true && mounted) Navigator.pop(context, true);
        break;
      case 'clear':
        _ctrl.clear();
        break;
      // null (dismiss): 아무것도 안 함
    }
  }

  // ─── build ────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_hasText,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final nav = Navigator.of(context);
        if (await _confirmExit() && context.mounted) nav.pop();
      },
      child: AppPageScaffold(
        title: '기존 계약서로 시작',
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
              onPressed: _hasText ? _parse : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).primaryColor,
                disabledBackgroundColor: AppColors.grey200,
                foregroundColor: Colors.white,
                padding: EdgeInsets.symmetric(
                    vertical: ResponsiveHelper.spacing(context, 16)),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                elevation: 0,
              ),
              child: Text(
                '조항으로 나누기',
                style: ResponsiveHelper.bodyStyle(context).copyWith(
                  color: _hasText ? Colors.white : AppColors.grey400,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ),
        body: ListView(
          padding: ResponsiveHelper.listPadding(context),
          children: [
            // ─── 안내 ────────────────────────────────────────────
            Text(
              '계약서 내용 붙여넣기',
              style: ResponsiveHelper.subtitleStyle(context)
                  .copyWith(fontWeight: FontWeight.bold),
            ),
            SizedBox(height: ResponsiveHelper.spacing(context, 6)),
            Text(
              '한글, Word, PDF에서 계약서 내용을 복사한 후 아래에 붙여넣어 주세요.\n'
              '제N조 형식의 조항 구분이 있으면 자동으로 나눠집니다.',
              style: ResponsiveHelper.smallStyle(context,
                  color: AppColors.grey500),
            ),
            SizedBox(height: ResponsiveHelper.spacing(context, 16)),

            // ─── 입력창 ──────────────────────────────────────────
            Container(
              constraints: const BoxConstraints(minHeight: 320),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.grey200),
              ),
              padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 14)),
              child: TextField(
                controller: _ctrl,
                maxLines: null,
                keyboardType: TextInputType.multiline,
                style: ResponsiveHelper.smallStyle(context),
                decoration: InputDecoration(
                  hintText:
                      '여기에 계약서 내용을 붙여넣어 주세요.\n\n'
                      '예)\n제1조 (근로계약 당사자)\n'
                      '...\n\n제4조 (보안)\n현장 내 사진 촬영을 금지한다.',
                  hintStyle: ResponsiveHelper.smallStyle(context,
                      color: AppColors.grey400),
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ),
            SizedBox(height: ResponsiveHelper.spacing(context, 12)),

            // ─── PII 주의 안내 ────────────────────────────────────
            Container(
              padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 12)),
              decoration: BoxDecoration(
                color: AppColors.infoBg,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: AppColors.info.withValues(alpha: 0.3)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline,
                      size: ResponsiveHelper.iconSize(context, 16),
                      color: AppColors.info),
                  SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                  Expanded(
                    child: Text(
                      '특정 근로자의 개인정보가 포함되어 있다면 '
                      '템플릿 저장 전 삭제하거나 수정해 주세요.',
                      style: ResponsiveHelper.tinyStyle(context,
                          color: AppColors.infoDark),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: ResponsiveHelper.spacing(context, 8)),
          ],
        ),
      ),
    );
  }
}

// ─── 0개 fallback 바텀시트 ────────────────────────────────────────

class _ParseFailureSheet extends StatelessWidget {
  final bool hasText;
  const _ParseFailureSheet({required this.hasText});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          ResponsiveHelper.spacing(context, 20),
          ResponsiveHelper.spacing(context, 20),
          ResponsiveHelper.spacing(context, 20),
          ResponsiveHelper.spacing(context, 16),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 드래그 핸들
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: EdgeInsets.only(
                    bottom: ResponsiveHelper.spacing(context, 16)),
                decoration: BoxDecoration(
                  color: AppColors.grey300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            Icon(Icons.search_off_outlined,
                size: 40, color: AppColors.grey400),
            SizedBox(height: ResponsiveHelper.spacing(context, 12)),
            Text(
              '자동으로 조항을 나누지 못했습니다.',
              style: ResponsiveHelper.subtitleStyle(context)
                  .copyWith(fontWeight: FontWeight.bold),
            ),
            SizedBox(height: ResponsiveHelper.spacing(context, 6)),
            Text(
              '"제N조" 형식의 조항 구분이 없거나,\n'
              '계약서가 아닌 다른 텍스트인 경우 자동 나누기가 어렵습니다.',
              style: ResponsiveHelper.smallStyle(context,
                  color: AppColors.grey500),
            ),
            SizedBox(height: ResponsiveHelper.spacing(context, 20)),

            // 전체 1개 조항으로 가져오기
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: hasText
                    ? () => Navigator.pop(context, 'whole')
                    : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).primaryColor,
                  foregroundColor: Colors.white,
                  padding: EdgeInsets.symmetric(
                      vertical: ResponsiveHelper.spacing(context, 14)),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                  elevation: 0,
                ),
                child: Text(
                  '전체 내용을 하나의 조항으로 가져오기',
                  style: ResponsiveHelper.bodyStyle(context)
                      .copyWith(color: Colors.white),
                ),
              ),
            ),
            SizedBox(height: ResponsiveHelper.spacing(context, 8)),

            // 다시 붙여넣기
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () => Navigator.pop(context, 'clear'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.grey600,
                  side: const BorderSide(color: AppColors.grey300),
                  padding: EdgeInsets.symmetric(
                      vertical: ResponsiveHelper.spacing(context, 14)),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                child: Text(
                  '다시 붙여넣기',
                  style: ResponsiveHelper.bodyStyle(context),
                ),
              ),
            ),
            SizedBox(height: ResponsiveHelper.spacing(context, 8)),

            // 취소
            Center(
              child: TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(
                  '취소',
                  style: ResponsiveHelper.bodyStyle(context,
                      color: AppColors.grey500),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
