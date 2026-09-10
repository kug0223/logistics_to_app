import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../models/core/contract_template_model.dart';
import '../../screens/business_admin/contract_import_paste_screen.dart';
import '../../screens/business_admin/contract_template_list_screen.dart';
import '../../services/contract_template_service.dart';
import '../../services/firestore_service.dart';
import '../../theme/app_colors.dart';
import '../../utils/dialog_helper.dart';
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
    return DialogHelper.showSheet<List<ContractArticle>?>(
      context,
      isScrollControlled: true,
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
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      // 통합운영: 관리자의 모든 사업장 템플릿을 합쳐서 표시
      final uid = FirebaseAuth.instance.currentUser?.uid;
      List<ContractTemplateModel> list = [];

      if (uid != null) {
        final businesses = await FirestoreService().getMyBusiness(uid);
        if (businesses.isNotEmpty) {
          final allLists = await Future.wait(
            businesses.map((b) => _service.getTemplates(b.id)),
          );
          list = allLists.expand((l) => l).toList();
        }
      }

      // fallback: uid 취득 실패 or 사업장 없으면 TO의 businessId로 시도
      if (list.isEmpty) {
        list = await _service.getTemplates(widget.businessId);
      }

      if (mounted) setState(() { _templates = list; _loadError = null; });
    } catch (e) {
      debugPrint('❌ 계약 템플릿 로드 실패: $e');
      if (mounted) setState(() { _templates = []; _loadError = e.toString(); });
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
                    ? _buildEmpty(context, error: _loadError)
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
            top: false,
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                ResponsiveHelper.spacing(context, 16),
                ResponsiveHelper.spacing(context, 8),
                ResponsiveHelper.spacing(context, 16),
                ResponsiveHelper.spacing(context, 16),
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

  // ── 유형 선택 후 Import Flow 진입 ─────────────────────────────
  Future<void> _startImportFromEmpty() async {
    // 1. 유형 선택
    final type = await DialogHelper.showSheet<String>(
      context,
      isScrollControlled: true,
      builder: (ctx) => _TypeSelectorSheetInline(),
    );
    if (type == null || !mounted) return;

    // 2. PasteScreen push (바텀시트 위에 전체 화면으로 열림)
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => ContractImportPasteScreen(
          businessId: widget.businessId,
          templateType: type,
        ),
      ),
    );
    if (saved == true && mounted) {
      // 저장 완료 → 목록 재조회
      setState(() { _templates = null; _loadError = null; });
      _load();
    }
  }

  Widget _buildEmpty(BuildContext context, {String? error}) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        ResponsiveHelper.spacing(context, 20),
        ResponsiveHelper.spacing(context, 24),
        ResponsiveHelper.spacing(context, 20),
        ResponsiveHelper.spacing(context, 8),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.description_outlined, size: 48, color: AppColors.grey300),
          SizedBox(height: ResponsiveHelper.spacing(context, 12)),
          Text(
            error != null ? '템플릿 불러오기 실패' : '등록된 템플릿이 없습니다',
            style: ResponsiveHelper.bodyStyle(context).copyWith(
                color: error != null ? AppColors.error : AppColors.grey500),
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 4)),
          Text(
            error != null
                ? '오류가 발생했습니다. 아래에서 다시 시도하거나\n빈 계약서로 진행하세요.'
                : '계약서 조항 템플릿을 추가해두면\n빠르게 계약서를 작성할 수 있습니다.',
            textAlign: TextAlign.center,
            style:
                ResponsiveHelper.smallStyle(context, color: AppColors.grey400),
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 20)),

          if (error != null) ...[
            // 에러 시: 다시 시도
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () {
                  setState(() {
                    _templates = null;
                    _loadError = null;
                  });
                  _load();
                },
                icon: const Icon(Icons.refresh, size: 16),
                label: Text('다시 시도',
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
          ] else ...[
            // 빈 상태 3개 선택지
            // 1) 기존 계약서로 시작
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _startImportFromEmpty,
                icon: const Icon(Icons.upload_file_outlined, size: 16),
                label: Text('기존 계약서로 시작',
                    style: ResponsiveHelper.smallStyle(context,
                        color: Colors.white, fontWeight: FontWeight.w600)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: theme.primaryColor,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: EdgeInsets.symmetric(
                      vertical: ResponsiveHelper.spacing(context, 12)),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
            SizedBox(height: ResponsiveHelper.spacing(context, 8)),

            // 2) ALfit 기본 계약서 (템플릿 관리 이동)
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ContractTemplateListScreen(
                          businessId: widget.businessId),
                    ),
                  );
                  if (mounted) {
                    setState(() {
                      _templates = null;
                      _loadError = null;
                    });
                    _load();
                  }
                },
                icon: const Icon(Icons.auto_awesome_outlined, size: 16),
                label: Text('ALfit 기본 계약서',
                    style: ResponsiveHelper.smallStyle(context,
                        fontWeight: FontWeight.w600)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: theme.primaryColor,
                  side: BorderSide(color: theme.primaryColor.withValues(alpha: 0.5)),
                  padding: EdgeInsets.symmetric(
                      vertical: ResponsiveHelper.spacing(context, 12)),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
            SizedBox(height: ResponsiveHelper.spacing(context, 8)),

            // 3) 빈 계약서로 진행
            TextButton(
              onPressed: () =>
                  Navigator.pop(context, <ContractArticle>[]),
              child: Text(
                '빈 계약서로 진행',
                style: ResponsiveHelper.smallStyle(context,
                    color: AppColors.grey500),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ─── 유형 선택 시트 (SelectorDialog 내부 전용) ────────────────────

class _TypeSelectorSheetInline extends StatelessWidget {
  const _TypeSelectorSheetInline();

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * AppDialogSize.maxHeightRatio,
      ),
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              ResponsiveHelper.spacing(context, 20),
              ResponsiveHelper.spacing(context, 8),
              ResponsiveHelper.spacing(context, 20),
              ResponsiveHelper.spacing(context, 16),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 36, height: 4,
                    margin: EdgeInsets.only(
                        bottom: ResponsiveHelper.spacing(context, 20)),
                    decoration: BoxDecoration(
                      color: AppColors.grey300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Text(
                  '어떤 계약서 유형인가요?',
                  style: ResponsiveHelper.titleStyle(context)
                      .copyWith(fontWeight: FontWeight.bold),
                ),
                SizedBox(height: ResponsiveHelper.spacing(context, 6)),
                Text(
                  '불러올 기존 계약서의 유형을 선택해 주세요.',
                  style: ResponsiveHelper.smallStyle(context,
                      color: AppColors.grey500),
                ),
                SizedBox(height: ResponsiveHelper.spacing(context, 20)),

                _InlineTypeRow(
                  icon: Icons.calendar_today_outlined,
                  color: AppColors.info,
                  bg: AppColors.infoBg,
                  label: '단기 일용직',
                  onTap: () =>
                      Navigator.pop(context, ContractTemplateType.daily),
                ),
                SizedBox(height: ResponsiveHelper.spacing(context, 10)),
                _InlineTypeRow(
                  icon: Icons.date_range_outlined,
                  color: AppColors.success,
                  bg: AppColors.successBg,
                  label: '기간제 (장기)',
                  onTap: () =>
                      Navigator.pop(context, ContractTemplateType.period),
                ),
                SizedBox(height: ResponsiveHelper.spacing(context, 10)),
                _InlineTypeRow(
                  icon: Icons.handshake_outlined,
                  color: AppColors.warning,
                  bg: AppColors.warningBg,
                  label: '업무위탁 (3.3%)',
                  onTap: () => Navigator.pop(
                      context, ContractTemplateType.outsource),
                ),

                SizedBox(height: ResponsiveHelper.spacing(context, 8)),
                Center(
                  child: TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text('취소',
                        style: ResponsiveHelper.bodyStyle(context,
                            color: AppColors.grey500)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _InlineTypeRow extends StatelessWidget {
  final IconData icon;
  final Color color;
  final Color bg;
  final String label;
  final VoidCallback onTap;

  const _InlineTypeRow({
    required this.icon,
    required this.color,
    required this.bg,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 14)),
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.grey200),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Container(
                width: 40, height: 40,
                decoration: BoxDecoration(
                  color: bg, borderRadius: BorderRadius.circular(10)),
                child: Icon(icon, color: color,
                    size: ResponsiveHelper.iconSize(context, 20)),
              ),
              SizedBox(width: ResponsiveHelper.spacing(context, 14)),
              Expanded(
                child: Text(label,
                    style: ResponsiveHelper.bodyStyle(context)
                        .copyWith(fontWeight: FontWeight.w600)),
              ),
              Icon(Icons.chevron_right, color: AppColors.grey400,
                  size: ResponsiveHelper.iconSize(context, 20)),
            ],
          ),
        ),
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
