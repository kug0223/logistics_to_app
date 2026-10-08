// lib/screens/super_admin/legal_terms_management_screen.dart
// [R7-P1-6 P16-A] GradientScaffold(지원자 공통 레이아웃) → AppPageScaffold
//   (D0 관리자 표준 flat shell). 이 화면은 headerContent 를 쓰지 않고 헤더에
//   TabBar 도 없으며 가로 스크롤 표도 없다 — 그래서 위젯 이름만 바뀐다.
//   본문의 흰 카드는 flat 배경(grey100) 위에서 그대로 카드로 읽힌다.
//
// 슈퍼관리자 약관 관리 화면
// - 각 약관 항목 내용 수정
// - 활성/비활성 토글
// - 버전 관리

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/core/legal_terms_model.dart';
import '../../providers/user_provider.dart';
import '../../services/legal_terms_service.dart';
import '../../theme/app_colors.dart';
import '../../utils/responsive_helper.dart';
import '../../utils/toast_helper.dart';
import '../../widgets/common/app_page_scaffold.dart';
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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!context.read<UserProvider>().isSuperAdmin) {
        Navigator.pop(context);
        return;
      }
      _loadTerms();
    });
  }

  Future<void> _loadTerms() async {
    setState(() => _isLoading = true);
    try {
      // [R7-PAYROLL-POLICY.5B] 발행 화면은 **편집용** 경로를 쓴다.
      //   아직 발행되지 않은 항목도 기본값으로 꺼내 편집해야 하기 때문이다.
      //   동의를 받는 화면은 fetchEffectiveTerms() 를 쓴다.
      final terms = await _service.getTermsForEditing();
      if (mounted) setState(() { _terms = terms; });
    } catch (e) {
      if (mounted) ToastHelper.showError('약관을 불러오는데 실패했습니다');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _editItem(LegalTermsItem item) async {
    if (_isLoading) return;
    final result = await Navigator.push<_PublishDraft>(
      context,
      MaterialPageRoute(
        builder: (_) => _TermsEditScreen(item: item),
      ),
    );
    if (result == null || !mounted) return;

    final uid = context.read<UserProvider>().currentUser?.uid ?? '';
    setState(() => _isLoading = true);
    try {
      await _service.updateItem(result.item,
          updatedBy: uid,
          changeType: result.changeType,
          effectiveAt: result.effectiveAt);
      if (!mounted) return;
      ToastHelper.showSuccess('발행했습니다. 시행일부터 적용됩니다');
      await _loadTerms();
    } on FirebaseFunctionsException catch (e) {
      // [R7-PAYROLL-POLICY.5A] 왜 거절됐는지 그대로 보여 준다.
      //   고지기간 숫자를 클라이언트가 들고 있지 않으므로, 가장 이른
      //   시행일은 **서버가 알려 준 값**을 쓴다. 두 곳에 기간을 적어 두면
      //   앱 버전에 따라 다른 기간을 주장하게 된다.
      if (mounted) ToastHelper.showError(_publishFailureMessage(e));
    } catch (e) {
      if (mounted) ToastHelper.showError('발행에 실패했습니다');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _publishFailureMessage(FirebaseFunctionsException e) {
    final details = e.details;
    final reason = details is Map ? details['reason'] : null;
    final earliest = details is Map ? details['earliestEffectiveAtMs'] : null;
    String whenEarliest() {
      if (earliest is! int) return '';
      final d = DateTime.fromMillisecondsSinceEpoch(earliest)
          .add(const Duration(hours: 9));
      return '${d.year}년 ${d.month}월 ${d.day}일';
    }

    switch (reason) {
      case 'NOTICE_PERIOD_TOO_SHORT':
        final w = whenEarliest();
        return w.isEmpty
            ? '사전고지 기간이 모자랍니다. 시행일을 뒤로 미뤄 주세요'
            : '사전고지 기간이 모자랍니다\n가장 이른 시행일은 $w입니다';
      case 'EFFECTIVE_AT_IMMUTABLE':
        return '이미 발행된 버전의 시행일은 바꿀 수 없습니다\n새 버전으로 발행해 주세요';
      case 'EFFECTIVE_AT_IN_PAST':
        return '이미 지난 시행일로는 현재 약관을 바꿀 수 없습니다';
      case 'INITIAL_NOT_ALLOWED':
        return '이미 시행 중인 약관이 있어 첫 발행으로 낼 수 없습니다';
      case 'INITIAL_REQUIRED':
        return '아직 시행 중인 판이 없습니다. 첫 발행으로 선택해 주세요';
      case 'INITIAL_MUST_BE_IMMEDIATE':
        final w = whenEarliest();
        return w.isEmpty
            ? '첫 발행은 오늘 시행이어야 합니다'
            : '첫 발행은 $w 시행이어야 합니다';
      case 'EFFECTIVE_AT_NOT_KST_MIDNIGHT':
        return '시행일을 날짜로 다시 선택해 주세요';
      default:
        return '발행에 실패했습니다';
    }
  }

  Future<void> _toggleActive(LegalTermsItem item) async {
    if (_isLoading) return;
    setState(() => _isLoading = true);
    final uid = context.read<UserProvider>().currentUser?.uid ?? '';
    try {
      await _service.toggleActive(item.id, !item.isActive, updatedBy: uid);
      if (!mounted) return;
      await _loadTerms();
      if (mounted) ToastHelper.showSuccess(item.isActive ? '비활성화되었습니다' : '활성화되었습니다');
    } catch (e) {
      if (mounted) ToastHelper.showError('변경에 실패했습니다');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppPageScaffold(
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
                  // Flexible 필수: 긴 약관 제목 + 필수/선택 배지 조합 시 overflow 방지
                  Flexible(
                    child: Text(
                      item.title,
                      style: ResponsiveHelper.bodyStyle(context).copyWith(
                        fontWeight: FontWeight.w600,
                        color: isActive ? null : AppColors.grey400,
                      ),
                      overflow: TextOverflow.ellipsis,
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

/// [R7-PAYROLL-POLICY.5A] 발행 요청 한 건.
///
/// 예전에는 편집 화면이 `LegalTermsItem` 만 돌려줬다. 그 모양으로는
/// "언제부터 적용되는가" 를 말할 수 없었고, 발행이 곧 시행이었다.
class _PublishDraft {
  const _PublishDraft({
    required this.item,
    required this.changeType,
    required this.effectiveAt,
  });

  final LegalTermsItem item;
  final LegalChangeType changeType;

  /// KST 자정. 변환은 `kstMidnightOfDate` 한 곳에서만 한다.
  final DateTime effectiveAt;
}

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

  /// [R7-PAYROLL-POLICY.5A] 변경 방향. 기본값을 두지 않는다 — 고르지
  /// 않으면 발행할 수 없다. 기본값이 있으면 아무 생각 없이 짧은 쪽으로
  /// 발행된다.
  LegalChangeType? _changeType;

  /// 시행일(날짜). 비어 있으면 발행할 수 없다.
  DateTime? _effectiveDate;

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
  );

  String get _effectiveLabel {
    final d = _effectiveDate;
    if (d == null) return '시행일을 선택하세요';
    return '${d.year}년 ${d.month}월 ${d.day}일부터 적용';
  }

  Future<void> _pickEffectiveDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _effectiveDate ?? now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 3),
      helpText: '시행일 선택',
    );
    if (picked == null || !mounted) return;
    setState(() {
      _effectiveDate = DateTime(picked.year, picked.month, picked.day);
      _hasChanges = true;
    });
  }

  Widget _buildPublicationControls() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('변경 방향',
              style: ResponsiveHelper.tinyStyle(context,
                  color: AppColors.grey500)),
          SizedBox(height: ResponsiveHelper.spacing(context, 6)),
          // 좁은 화면에서 세 칩이 한 줄에 안 들어간다 — 줄바꿈을 허용한다.
          Wrap(
            spacing: ResponsiveHelper.spacing(context, 8),
            runSpacing: ResponsiveHelper.spacing(context, 8),
            children: [
              for (final t in LegalChangeType.values)
                ChoiceChip(
                  label: Text(t.label,
                      style: ResponsiveHelper.smallStyle(context)),
                  selected: _changeType == t,
                  onSelected: (_) => setState(() {
                    _changeType = t;
                    _hasChanges = true;
                  }),
                ),
            ],
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 6)),
          // 고지기간 숫자는 **서버가** 갖는다. 여기 적어 두면 앱 버전에 따라
          // 다른 기간을 주장하게 되므로, 모자라면 서버가 알려 준다.
          Text('사전고지 기간은 서버가 약관 제3조 ②에 따라 검사합니다',
              style: ResponsiveHelper.tinyStyle(context,
                  color: AppColors.grey500)),
          SizedBox(height: ResponsiveHelper.spacing(context, 12)),
          Text('시행일',
              style: ResponsiveHelper.tinyStyle(context,
                  color: AppColors.grey500)),
          SizedBox(height: ResponsiveHelper.spacing(context, 6)),
          OutlinedButton.icon(
            onPressed: _pickEffectiveDate,
            icon: const Icon(Icons.event_outlined, size: 18),
            label: Flexible(
              child: Text(_effectiveLabel,
                  style: ResponsiveHelper.smallStyle(context)),
            ),
          ),
        ],
      );

  @override
  Widget build(BuildContext context) {
    return AppPageScaffold(
      title: '약관 편집',
      actions: [
        if (_hasChanges)
          TextButton(
            onPressed: () {
              if (_titleCtrl.text.trim().isEmpty) {
                ToastHelper.showError('제목을 입력하세요');
                return;
              }
              if (_contentCtrl.text.trim().isEmpty) {
                ToastHelper.showError('내용을 입력하세요');
                return;
              }
              // [R7-PAYROLL-POLICY.5A] 발행은 시행이다 — 언제부터인지
              //   말하지 않고 발행할 수 없다.
              final changeType = _changeType;
              if (changeType == null) {
                ToastHelper.showError('변경 방향을 선택하세요');
                return;
              }
              final date = _effectiveDate;
              if (date == null) {
                ToastHelper.showError('시행일을 선택하세요');
                return;
              }
              Navigator.pop(
                  context,
                  _PublishDraft(
                    item: _buildResult(),
                    changeType: changeType,
                    effectiveAt:
                        kstMidnightOfDate(date.year, date.month, date.day),
                  ));
            },
            child: Text('발행',
                style: ResponsiveHelper.bodyStyle(context,
                    color: Colors.white, fontWeight: FontWeight.bold)),
          ),
      ],
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

          // [R7-PAYROLL-POLICY.5A] 발행 ≠ 시행
          _buildPublicationControls(),

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
