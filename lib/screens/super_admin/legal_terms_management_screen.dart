// lib/screens/super_admin/legal_terms_management_screen.dart
//
// 슈퍼관리자 약관 관리 화면
// - 각 약관 항목 내용 수정
// - 활성/비활성 토글
// - 버전 관리

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/core/legal_terms_model.dart';
import '../../providers/user_provider.dart';
import '../../services/legal_terms_service.dart';
import '../../theme/app_colors.dart';
import '../../utils/responsive_helper.dart';
import '../../utils/toast_helper.dart';
import '../../widgets/common/gradient_scaffold.dart';
import '../../widgets/common/loading_widget.dart';
import '../../widgets/common/common_widgets.dart';

class LegalTermsManagementScreen extends StatefulWidget {
  const LegalTermsManagementScreen({super.key});

  @override
  State<LegalTermsManagementScreen> createState() =>
      _LegalTermsManagementScreenState();
}

class _LegalTermsManagementScreenState
    extends State<LegalTermsManagementScreen> {
  final _service = LegalTermsService();
  LegalTerms? _terms;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadTerms();
  }

  Future<void> _loadTerms() async {
    setState(() => _isLoading = true);
    try {
      final terms = await _service.getTerms();
      if (mounted) setState(() { _terms = terms; });
    } catch (e) {
      // 예외는 무시하고 finally에서 상태 초기화
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _editItem(LegalTermsItem item) async {
    final result = await Navigator.push<LegalTermsItem>(
      context,
      MaterialPageRoute(
        builder: (_) => _TermsEditScreen(item: item),
      ),
    );
    if (result == null || !mounted) return;

    final uid = context.read<UserProvider>().currentUser?.uid ?? '';
    setState(() => _isLoading = true);
    try {
      await _service.updateItem(result, updatedBy: uid);
      if (!mounted) return;
      ToastHelper.showSuccess('약관이 저장되었습니다');
      await _loadTerms();
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ToastHelper.showError('저장에 실패했습니다');
      }
    }
  }

  Future<void> _toggleActive(LegalTermsItem item) async {
    final uid = context.read<UserProvider>().currentUser?.uid ?? '';
    try {
      await _service.toggleActive(item.id, !item.isActive, updatedBy: uid);
      if (!mounted) return;
      await _loadTerms();
      if (mounted) ToastHelper.showSuccess(item.isActive ? '비활성화되었습니다' : '활성화되었습니다');
    } catch (e) {
      if (mounted) ToastHelper.showError('변경에 실패했습니다');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GradientScaffold(
      title: '약관 관리',
      body: _isLoading
          ? const LoadingWidget()
          : _terms == null
              ? Center(
                  child: Text('약관을 불러오지 못했습니다.',
                      style: ResponsiveHelper.bodyStyle(context,
                          color: AppColors.grey500)))
              : ListView(
                  padding: ResponsiveHelper.listPadding(context),
                  children: [
                    // 안내
                    Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: ResponsiveHelper.spacing(context, 14),
                        vertical: ResponsiveHelper.spacing(context, 10),
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.infoBg,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppColors.infoLight),
                      ),
                      child: Row(children: [
                        Icon(Icons.info_outline,
                            size: 16, color: AppColors.infoDark),
                        SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                        Expanded(
                          child: Text(
                            '약관 수정 시 앱 업데이트 없이 즉시 반영됩니다.\n비활성화하면 회원가입 화면에서 숨겨집니다.',
                            style: ResponsiveHelper.tinyStyle(context,
                                color: AppColors.infoDeep),
                          ),
                        ),
                      ]),
                    ),

                    SizedBox(height: ResponsiveHelper.spacing(context, 20)),

                    _buildSectionLabel('약관 목록'),
                    SizedBox(height: ResponsiveHelper.spacing(context, 8)),

                    Container(
                      decoration: CommonWidgets.compactCardDecoration(),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Column(
                          children: [
                            for (int i = 0; i < _terms!.items.length; i++) ...[
                              _buildTermsRow(_terms!.items[i], theme),
                              if (i < _terms!.items.length - 1)
                                const Divider(
                                    height: 1, indent: 52, thickness: 0.5),
                            ],
                          ],
                        ),
                      ),
                    ),

                    if (_terms!.updatedAt != null) ...[
                      SizedBox(height: ResponsiveHelper.spacing(context, 12)),
                      Text(
                        '마지막 수정: ${_formatDate(_terms!.updatedAt!)}  수정자: ${_terms!.updatedBy ?? '-'}',
                        style: ResponsiveHelper.tinyStyle(context,
                            color: AppColors.grey400),
                        textAlign: TextAlign.right,
                      ),
                    ],

                    SizedBox(height: ResponsiveHelper.spacing(context, 24)),
                  ],
                ),
    );
  }

  Widget _buildTermsRow(LegalTermsItem item, ThemeData theme) {
    final isActive = item.isActive;
    return InkWell(
      onTap: () => _editItem(item),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: ResponsiveHelper.spacing(context, 16),
          vertical: ResponsiveHelper.spacing(context, 12),
        ),
        child: Row(children: [
          // 상태 아이콘
          Container(
            width: ResponsiveHelper.spacing(context, 34),
            height: ResponsiveHelper.spacing(context, 34),
            decoration: BoxDecoration(
              color: isActive
                  ? theme.primaryColor.withValues(alpha: 0.12)
                  : AppColors.grey100,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              Icons.article_outlined,
              size: ResponsiveHelper.iconSize(context, 18),
              color: isActive ? theme.primaryColor : AppColors.grey400,
            ),
          ),
          SizedBox(width: ResponsiveHelper.spacing(context, 12)),

          // 제목·정보
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Text(
                    item.title,
                    style: ResponsiveHelper.bodyStyle(context).copyWith(
                      fontWeight: FontWeight.w600,
                      color: isActive ? null : AppColors.grey400,
                    ),
                  ),
                  SizedBox(width: ResponsiveHelper.spacing(context, 6)),
                  Container(
                    padding: EdgeInsets.symmetric(
                        horizontal: ResponsiveHelper.spacing(context, 6),
                        vertical: 1),
                    decoration: BoxDecoration(
                      color: item.isRequired
                          ? AppColors.errorBg
                          : AppColors.grey100,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      item.isRequired ? '필수' : '선택',
                      style: ResponsiveHelper.tinyStyle(context,
                          color: item.isRequired
                              ? AppColors.error
                              : AppColors.grey500,
                          fontWeight: FontWeight.w600),
                    ),
                  ),
                ]),
                Text(
                  'v${item.version}${item.updatedAt != null ? '  ${_formatDate(item.updatedAt!)}' : ''}',
                  style: ResponsiveHelper.tinyStyle(context,
                      color: AppColors.grey400),
                ),
              ],
            ),
          ),

          // 활성 토글
          GestureDetector(
            onTap: () => _toggleActive(item),
            child: Container(
              padding: EdgeInsets.symmetric(
                  horizontal: ResponsiveHelper.spacing(context, 8),
                  vertical: ResponsiveHelper.spacing(context, 4)),
              decoration: BoxDecoration(
                color: isActive ? AppColors.successBg : AppColors.grey100,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                isActive ? '활성' : '비활성',
                style: ResponsiveHelper.tinyStyle(context,
                    color: isActive ? AppColors.successDark : AppColors.grey500,
                    fontWeight: FontWeight.w600),
              ),
            ),
          ),
          SizedBox(width: ResponsiveHelper.spacing(context, 8)),
          Icon(Icons.chevron_right,
              size: ResponsiveHelper.iconSize(context, 18),
              color: AppColors.grey400),
        ]),
      ),
    );
  }

  Widget _buildSectionLabel(String title) {
    return Padding(
      padding: EdgeInsets.only(left: ResponsiveHelper.spacing(context, 4)),
      child: Row(children: [
        Icon(Icons.description_outlined,
            size: 13, color: AppColors.grey500),
        SizedBox(width: 5),
        Text(title,
            style: ResponsiveHelper.smallStyle(context,
                color: AppColors.grey500, fontWeight: FontWeight.w600)),
      ]),
    );
  }

  String _formatDate(DateTime dt) =>
      '${dt.year}.${dt.month.toString().padLeft(2, '0')}.${dt.day.toString().padLeft(2, '0')}';
}

// ── 약관 편집 화면 ─────────────────────────────────────────────────

class _TermsEditScreen extends StatefulWidget {
  final LegalTermsItem item;
  const _TermsEditScreen({required this.item});

  @override
  State<_TermsEditScreen> createState() => _TermsEditScreenState();
}

class _TermsEditScreenState extends State<_TermsEditScreen> {
  late final TextEditingController _titleCtrl;
  late final TextEditingController _contentCtrl;
  late final TextEditingController _versionCtrl;
  late bool _isRequired;
  bool _hasChanges = false;

  @override
  void initState() {
    super.initState();
    _titleCtrl = TextEditingController(text: widget.item.title);
    _contentCtrl = TextEditingController(text: widget.item.content);
    _versionCtrl = TextEditingController(text: widget.item.version);
    _isRequired = widget.item.isRequired;
    _titleCtrl.addListener(_onChanged);
    _contentCtrl.addListener(_onChanged);
    _versionCtrl.addListener(_onChanged);
  }

  void _onChanged() => setState(() => _hasChanges = true);

  @override
  void dispose() {
    _titleCtrl.dispose();
    _contentCtrl.dispose();
    _versionCtrl.dispose();
    super.dispose();
  }

  LegalTermsItem _buildResult() => widget.item.copyWith(
    title: _titleCtrl.text.trim(),
    content: _contentCtrl.text.trim(),
    version: _versionCtrl.text.trim(),
    isRequired: _isRequired,
    updatedAt: DateTime.now(),
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        backgroundColor: theme.primaryColor,
        foregroundColor: Colors.white,
        title: Text('약관 편집',
            style: ResponsiveHelper.subtitleStyle(context,
                color: Colors.white)),
        actions: [
          if (_hasChanges)
            TextButton(
              onPressed: () => Navigator.pop(context, _buildResult()),
              child: Text('저장',
                  style: ResponsiveHelper.bodyStyle(context,
                      color: Colors.white, fontWeight: FontWeight.bold)),
            ),
        ],
      ),
      body: ListView(
        padding: ResponsiveHelper.listPadding(context),
        children: [
          SizedBox(height: ResponsiveHelper.spacing(context, 8)),

          // 제목
          CommonWidgets.textField(
            context: context,
            controller: _titleCtrl,
            label: '약관 제목',
            icon: Icons.title,
          ),

          SizedBox(height: ResponsiveHelper.spacing(context, 12)),

          // 버전 + 필수 여부
          Row(children: [
            Expanded(
              child: CommonWidgets.textField(
                context: context,
                controller: _versionCtrl,
                label: '버전 (예: 2025.01)',
                icon: Icons.history,
              ),
            ),
            SizedBox(width: ResponsiveHelper.spacing(context, 12)),
            // 필수/선택 토글
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('동의 유형',
                    style: ResponsiveHelper.tinyStyle(context,
                        color: AppColors.grey500)),
                SizedBox(height: ResponsiveHelper.spacing(context, 6)),
                GestureDetector(
                  onTap: () => setState(() {
                    _isRequired = !_isRequired;
                    _hasChanges = true;
                  }),
                  child: Container(
                    padding: EdgeInsets.symmetric(
                        horizontal: ResponsiveHelper.spacing(context, 12),
                        vertical: ResponsiveHelper.spacing(context, 8)),
                    decoration: BoxDecoration(
                      color: _isRequired
                          ? AppColors.errorBg
                          : AppColors.successBg,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: _isRequired
                              ? AppColors.error
                              : AppColors.success),
                    ),
                    child: Text(
                      _isRequired ? '필수' : '선택',
                      style: ResponsiveHelper.smallStyle(context,
                          color: _isRequired
                              ? AppColors.error
                              : AppColors.successDark,
                          fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            ),
          ]),

          SizedBox(height: ResponsiveHelper.spacing(context, 16)),

          // 약관 내용
          Text('약관 내용',
              style: ResponsiveHelper.smallStyle(context,
                  color: AppColors.grey500, fontWeight: FontWeight.w600)),
          SizedBox(height: ResponsiveHelper.spacing(context, 8)),
          Container(
            decoration: CommonWidgets.compactCardDecoration(),
            child: TextField(
              controller: _contentCtrl,
              maxLines: null,
              minLines: 20,
              style: ResponsiveHelper.smallStyle(context),
              decoration: InputDecoration(
                contentPadding: EdgeInsets.all(
                    ResponsiveHelper.spacing(context, 14)),
                border: InputBorder.none,
                hintText: '약관 내용을 입력하세요...',
                hintStyle: ResponsiveHelper.tinyStyle(context,
                    color: AppColors.grey400),
              ),
            ),
          ),

          SizedBox(height: ResponsiveHelper.spacing(context, 32)),
        ],
      ),
    );
  }
}
