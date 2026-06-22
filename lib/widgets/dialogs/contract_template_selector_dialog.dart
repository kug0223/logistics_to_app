import 'dart:math' show max;

import 'package:flutter/material.dart';

import '../../models/core/contract_template_model.dart';
import '../../screens/business_admin/contract_template_list_screen.dart';
import '../../services/contract_template_service.dart';
import '../../theme/app_colors.dart';
import '../../utils/responsive_helper.dart';
import '../common/loading_widget.dart';
import 'styled_dialog.dart';

/// 계약서 작성 시 템플릿 선택 바텀시트
///
/// Returns:
///   null  → 취소 (계약 생성 중단)
///   []    → 빈 계약서로 진행
///   [...]  → 선택한 템플릿의 조항 목록
class ContractTemplateSelectorDialog {
  static Future<List<ContractArticle>?> show(
    BuildContext context, {
    required String businessId,
  }) {
    return showModalBottomSheet<List<ContractArticle>?>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _SelectorSheet(businessId: businessId),
    );
  }
}

class _SelectorSheet extends StatefulWidget {
  final String businessId;
  const _SelectorSheet({required this.businessId});

  @override
  State<_SelectorSheet> createState() => _SelectorSheetState();
}

class _SelectorSheetState extends State<_SelectorSheet> {
  final _service = ContractTemplateService();
  List<ContractTemplateModel>? _templates;
  int? _selectedIndex;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final list = await _service.getTemplates(widget.businessId);
      if (mounted) setState(() => _templates = list);
    } catch (e) {
      debugPrint('❌ 계약 템플릿 로드 실패: $e');
      if (mounted) setState(() => _templates = []);
    }
  }

  void _confirm() {
    if (_selectedIndex == null) return;
    Navigator.pop(context, _templates![_selectedIndex!].articles);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final maxH = MediaQuery.sizeOf(context).height * AppDialogSize.subSheetHeightRatio;

    return Container(
      constraints: BoxConstraints(maxHeight: maxH),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 핸들
          Container(
            margin: EdgeInsets.only(
                top: ResponsiveHelper.spacing(context, 12)),
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.grey300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // 헤더
          Padding(
            padding: EdgeInsets.fromLTRB(
              ResponsiveHelper.spacing(context, 20),
              ResponsiveHelper.spacing(context, 16),
              ResponsiveHelper.spacing(context, 20),
              ResponsiveHelper.spacing(context, 8),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '계약서 템플릿 선택',
                    style: ResponsiveHelper.subtitleStyle(context)
                        .copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context, null),
                  icon: const Icon(Icons.close),
                  color: AppColors.grey500,
                ),
              ],
            ),
          ),

          Padding(
            padding: EdgeInsets.symmetric(
                horizontal: ResponsiveHelper.spacing(context, 20)),
            child: Text(
              '계약서 하단에 포함될 조항 템플릿을 선택하세요.\n제1~3조(당사자/근무조건/임금)는 자동으로 입력됩니다.',
              style: ResponsiveHelper.smallStyle(context,
                  color: AppColors.grey500),
            ),
          ),

          SizedBox(height: ResponsiveHelper.spacing(context, 12)),
          const Divider(height: 1, color: AppColors.grey100),

          // 본문
          Flexible(
            child: _templates == null
                ? const Padding(
                    padding: EdgeInsets.all(32),
                    child: LoadingWidget(),
                  )
                : _templates!.isEmpty
                    ? _buildEmpty(context)
                    : ListView.separated(
                        shrinkWrap: true,
                        padding: EdgeInsets.symmetric(
                          vertical:
                              ResponsiveHelper.spacing(context, 8),
                          horizontal:
                              ResponsiveHelper.spacing(context, 16),
                        ),
                        itemCount: _templates!.length,
                        separatorBuilder: (_, __) => SizedBox(
                            height:
                                ResponsiveHelper.spacing(context, 4)),
                        itemBuilder: (ctx, i) {
                          final t = _templates![i];
                          final selected = _selectedIndex == i;
                          return GestureDetector(
                            onTap: () =>
                                setState(() => _selectedIndex = i),
                            child: AnimatedContainer(
                              duration:
                                  const Duration(milliseconds: 150),
                              padding: EdgeInsets.all(
                                  ResponsiveHelper.spacing(
                                      context, 14)),
                              decoration: BoxDecoration(
                                color: selected
                                    ? theme.primaryColor
                                        .withValues(alpha: 0.06)
                                    : Colors.white,
                                borderRadius:
                                    BorderRadius.circular(12),
                                border: Border.all(
                                  color: selected
                                      ? theme.primaryColor
                                      : AppColors.grey200,
                                  width: selected ? 1.5 : 1,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    selected
                                        ? Icons.check_circle
                                        : Icons.radio_button_unchecked,
                                    color: selected
                                        ? theme.primaryColor
                                        : AppColors.grey300,
                                    size: ResponsiveHelper.iconSize(
                                        context, 20),
                                  ),
                                  SizedBox(
                                      width: ResponsiveHelper.spacing(
                                          context, 12)),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Flexible(
                                              child: Text(
                                                t.name,
                                                style: ResponsiveHelper
                                                    .bodyStyle(context)
                                                    .copyWith(
                                                      fontWeight: FontWeight.w600,
                                                    ),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                            SizedBox(width: ResponsiveHelper.spacing(context, 6)),
                                            _TemplateTypeBadge(templateType: t.templateType),
                                          ],
                                        ),
                                        SizedBox(
                                            height:
                                                ResponsiveHelper.spacing(
                                                    context, 2)),
                                        Text(
                                          t.articles
                                              .take(2)
                                              .map((a) => a.title)
                                              .join(' · ')
                                              + (t.articles.length > 2
                                                  ? ' 외 ${t.articles.length - 2}개'
                                                  : ''),
                                          style: ResponsiveHelper
                                              .tinyStyle(context,
                                                  color:
                                                      AppColors.grey500),
                                          maxLines: 1,
                                          overflow:
                                              TextOverflow.ellipsis,
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
          ),

          // 하단 버튼
          SafeArea(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                ResponsiveHelper.spacing(context, 16),
                ResponsiveHelper.spacing(context, 8),
                ResponsiveHelper.spacing(context, 16),
                // edge-to-edge 대응: viewPaddingOf는 SafeArea 소비 무관 물리적 인셋.
                // max로 SafeArea 정상 동작 시 이중 합산 방지.
                max(
                  ResponsiveHelper.spacing(context, 16),
                  MediaQuery.viewPaddingOf(context).bottom,
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_templates != null && _templates!.isNotEmpty)
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed:
                            _selectedIndex != null ? _confirm : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: theme.primaryColor,
                          disabledBackgroundColor: AppColors.grey200,
                          padding: EdgeInsets.symmetric(
                              vertical: ResponsiveHelper.spacing(
                                  context, 15)),
                          shape: RoundedRectangleBorder(
                              borderRadius:
                                  BorderRadius.circular(12)),
                          elevation: 0,
                          foregroundColor: Colors.white,
                        ),
                        child: Text(
                          '선택한 템플릿으로 계약서 작성',
                          style: ResponsiveHelper.bodyStyle(context)
                              .copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  SizedBox(
                      height: ResponsiveHelper.spacing(context, 8)),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: () =>
                          Navigator.pop(context, <ContractArticle>[]),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.grey600,
                        side: const BorderSide(
                            color: AppColors.grey300),
                        padding: EdgeInsets.symmetric(
                            vertical: ResponsiveHelper.spacing(
                                context, 14)),
                        shape: RoundedRectangleBorder(
                            borderRadius:
                                BorderRadius.circular(12)),
                      ),
                      child: Text(
                        '빈 계약서로 진행',
                        style:
                            ResponsiveHelper.bodyStyle(context),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        ResponsiveHelper.spacing(context, 24),
        ResponsiveHelper.spacing(context, 32),
        ResponsiveHelper.spacing(context, 24),
        ResponsiveHelper.spacing(context, 16),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.description_outlined, size: 48, color: AppColors.grey300),
          SizedBox(height: ResponsiveHelper.spacing(context, 12)),
          Text(
            '등록된 템플릿이 없습니다',
            style: ResponsiveHelper.bodyStyle(context)
                .copyWith(color: AppColors.grey500),
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 6)),
          Text(
            '계약서 조항 템플릿을 미리 등록해두면\n빠르게 계약서를 작성할 수 있습니다',
            textAlign: TextAlign.center,
            style: ResponsiveHelper.smallStyle(context, color: AppColors.grey400),
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 16)),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () async {
                // 템플릿 관리 화면으로 이동 후 돌아오면 목록 새로고침
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ContractTemplateListScreen(
                        businessId: widget.businessId),
                  ),
                );
                if (mounted) _load();
              },
              icon: const Icon(Icons.add, size: 16),
              label: Text('템플릿 등록하기',
                  style: ResponsiveHelper.smallStyle(context,
                      fontWeight: FontWeight.w600)),
              style: OutlinedButton.styleFrom(
                padding: EdgeInsets.symmetric(
                    vertical: ResponsiveHelper.spacing(context, 10)),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── 유형 배지 (소형) ─────────────────────────────────────────────

class _TemplateTypeBadge extends StatelessWidget {
  final String templateType;
  const _TemplateTypeBadge({required this.templateType});

  @override
  Widget build(BuildContext context) {
    Color color;
    Color bg;
    switch (templateType) {
      case ContractTemplateType.daily:
        color = AppColors.info;
        bg    = AppColors.infoBg;
        break;
      case ContractTemplateType.period:
        color = AppColors.success;
        bg    = AppColors.successBg;
        break;
      case ContractTemplateType.outsource:
        color = AppColors.warning;
        bg    = AppColors.warningBg;
        break;
      default:
        color = AppColors.grey600;
        bg    = AppColors.grey100;
    }
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 5),
        vertical: ResponsiveHelper.spacing(context, 2),
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        ContractTemplateType.label(templateType),
        style: ResponsiveHelper.tinyStyle(context)
            .copyWith(color: color, fontWeight: FontWeight.w600),
      ),
    );
  }
}
