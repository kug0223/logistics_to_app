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

import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/core/legal_terms_model.dart';
import '../../providers/user_provider.dart';
import '../../services/legal_terms_service.dart';
import '../../theme/app_colors.dart';
import '../../utils/dialog_helper.dart';
import '../../utils/responsive_helper.dart';
import '../../utils/text_layout.dart';
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
      // [.54] 읽기 실패를 기본값으로 바꾸지 않는다(서비스가 throw) — 이전 목록도 지운다.
      //   낡은 목록을 그대로 두면 그 위에서 다시 발행할 수 있다.
      if (mounted) setState(() => _terms = null);
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

    // [.55] 누르기 전에 무엇이 언제 적용되는지 말한다. 앱은 서버가 시행일 예약을 처리하는 판인지 미리 알 수 없다 —
    //   그래서 예약을 보장하지 않고, 처리 못 하는 서버면 즉시 적용될 수 있다고 적는다(결과는 발행 직후 안내).
    final when = _kstDateLabel(result.effectiveAt);
    final up = result.item.upcoming;
    final ok = await DialogHelper.showConfirm(
      context,
      title: '약관 발행',
      message: TextLayout.keepWords('「${result.item.title}」 v${result.item.version} 을 발행합니다.\n'
          '선택한 시행일: $when 0시(한국 시간)\n'
          '지금 시행 중: v${item.version}'
          '${up != null ? '\n시행 예정 v${up.version} 은 이 발행으로 대체됩니다' : ''}\n'
          '서버가 시행일 예약을 처리하지 못하면 발행 즉시 적용될 수 있습니다. 결과는 발행 직후 알려 드립니다.'),
      confirmText: '발행',
    );
    if (!ok || !mounted) return;

    final uid = context.read<UserProvider>().currentUser?.uid ?? '';
    setState(() => _isLoading = true);
    try {
      final scheduled = await _service.updateItem(result.item,
          updatedBy: uid,
          changeType: result.changeType,
          effectiveAt: result.effectiveAt);
      if (!mounted) return;
      // [.54] 시행일을 처리하지 않는 이전 판 서버는 지금 바로 시행한다 — 그때는 그렇게 말한다.
      ToastHelper.showSuccess(TextLayout.keepWords(scheduled
          ? '발행했습니다. $when 0시(한국 시간)부터 적용됩니다'
          : '발행했습니다. 서버가 시행일을 받지 않아 지금부터 적용됩니다'));
      await _loadTerms();
    } on FirebaseFunctionsException catch (e) {
      // [R7-PAYROLL-POLICY.5A] 왜 거절됐는지 그대로 보여 준다.
      //   고지기간 숫자를 클라이언트가 들고 있지 않으므로, 가장 이른
      //   시행일은 **서버가 알려 준 값**을 쓴다. 두 곳에 기간을 적어 두면
      //   앱 버전에 따라 다른 기간을 주장하게 된다.
      if (!mounted) return;
      // [.55] 응답을 못 받은 실패는 저장 여부를 모른다 — 실패로 단정하지 않고 다시 보내지도 않는다. 목록으로 확인한다.
      if (_uncertainCodes.contains(e.code)) {
        ToastHelper.showError(TextLayout.keepWords('발행 결과를 확인하지 못했습니다. 목록을 다시 불러와 확인해 주세요'));
        unawaited(_loadTerms());
        return;
      }
      ToastHelper.showError(TextLayout.keepWords(_publishFailureMessage(e)));
      // 다른 관리자가 예정 판을 바꿨다 — 저장 전 거절이다. 지금 목록을 다시 보여 준다.
      if (LegalTermsService.isUpcomingStale(e)) unawaited(_loadTerms());
    } catch (e) {
      if (mounted) ToastHelper.showError('발행에 실패했습니다');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _publishFailureMessage(FirebaseFunctionsException e) {
    if (LegalTermsService.isVersionReused(e)) {
      return '이미 발행된 버전의 본문은 바꿀 수 없습니다\n버전을 바꿔 발행해 주세요';
    }
    if (LegalTermsService.isVersionMeaningChanged(e)) {
      return '이미 발행된 버전의 제목·필수 여부는 바꿀 수 없습니다\n버전을 바꿔 발행해 주세요';
    }
    if (LegalTermsService.isUpcomingStale(e)) {
      return '다른 관리자가 시행 예정 약관을 바꿨습니다\n목록을 다시 불러왔습니다. 확인한 뒤 다시 발행해 주세요';
    }
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
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Text('약관을 불러오지 못했습니다.',
                        style: ResponsiveHelper.bodyStyle(context,
                            color: AppColors.grey500)),
                    SizedBox(height: ResponsiveHelper.spacing(context, 12)),
                    OutlinedButton.icon(
                      onPressed: _loadTerms,
                      icon: const Icon(Icons.refresh, size: 18),
                      label: const Text('다시 시도'),
                    ),
                  ]))
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
                          // [.54] 큰 글자에서 '화면에|서' 로 끊겼다 — 낱말 단위(표시만).
                          // [.80] 발행 서버(00002-sok)는 새 버전을 시행일에 적용한다 — '즉시 반영' 은 틀린 안내가 됐다.
                          child: Text(
                            TextLayout.keepWords('새 버전은 정한 시행일(한국 시간 0시)부터 적용되고, 그 전까지는 지금 약관이 유지됩니다.\n비활성화하면 회원가입 화면에서 숨겨집니다.'),
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
                // [.54] 큰 글자에서 제목이 '[합성] 서비…' 로 말줄임됐다 — 제목은 낱말 단위로
                //   줄을 바꾸고, 배지는 자리가 없으면 다음 줄로 간다(Wrap).
                Wrap(
                  spacing: ResponsiveHelper.spacing(context, 6),
                  runSpacing: 2,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                  Text(
                    TextLayout.keepWords(item.title),
                    semanticsLabel: item.title,
                    style: ResponsiveHelper.bodyStyle(context).copyWith(
                      fontWeight: FontWeight.w600,
                      color: isActive ? null : AppColors.grey400,
                    ),
                  ),
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
                // [.54] 시행 예정 판이 있으면 목록에서 보인다 — 안 보이면 다른 SA 가
                //   그 위에 새 판을 내 예정 판을 모르게 바꾼다.
                if (item.upcoming != null)
                  Text(
                    TextLayout.keepWords(_upcomingLabel(item.upcoming!)),
                    style: ResponsiveHelper.tinyStyle(context,
                        color: AppColors.infoDark, fontWeight: FontWeight.w600),
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

/// [.55] 응답을 받지 못해 저장 여부를 모르는 오류 코드.
const _uncertainCodes = {'deadline-exceeded', 'unavailable', 'internal', 'unknown', 'cancelled'};

/// [.55] KST 날짜 — 시행일은 KST 자정 instant 다(`kstMidnightOfDate`). 기기 시간대로 바꾸지 않는다.
String _kstDateLabel(DateTime instant) {
  final k = instant.toUtc().add(const Duration(hours: 9));
  return '${k.year}년 ${k.month}월 ${k.day}일';
}

/// [.54] 시행 예정 판 한 줄 — 목록과 편집 화면이 같은 문장을 쓴다.
String _upcomingLabel(UpcomingLegalRevision up) {
  // 시행일은 KST 자정이다 — 기기 시간대로 바꾸면 GMT 기기에서 하루 앞 날짜로 보인다(기기 확인).
  final at = up.effectiveAt?.toUtc().add(const Duration(hours: 9));
  final when = at == null ? '' : ' · ${at.year}.${at.month}.${at.day} 시행';
  return '시행 예정 v${up.version}$when';
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
          Text(TextLayout.keepWords('사전고지 기간은 서버가 약관 제3조 ②에 따라 검사합니다'),
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
              // [.54] 같은 버전·같은 본문에 제목만 바꾸면 서버는 공개 목록의 제목만 바꾸고
              //   발행본 제목은 그대로 둔다 — 이 목록에는 새 제목, 사용자 동의 화면에는 옛 제목이 보인다.
              final it = widget.item;
              if (_versionCtrl.text.trim() == it.version &&
                  _contentCtrl.text.trim() == it.content.trim() &&
                  _titleCtrl.text.trim() != it.title) {
                ToastHelper.showError(TextLayout.keepWords('제목을 바꾸려면 버전도 바꿔 새 판으로 발행해 주세요'));
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

          // [.54] 시행 예정 판이 이미 있다 — 새로 발행하면 그 판을 대체한다(서버 계약).
          //   이 편집 화면의 본문은 지금 시행 중인 판이다.
          if (widget.item.upcoming != null) ...[
            Container(
              width: double.infinity,
              padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 12)),
              decoration: BoxDecoration(
                color: AppColors.infoBg,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.infoLight),
              ),
              child: Text(
                TextLayout.keepWords('${_upcomingLabel(widget.item.upcoming!)}이 있습니다. '
                    '아래 본문은 지금 시행 중인 판이며, 새로 발행하면 예정 판을 대체합니다.'),
                style: ResponsiveHelper.smallStyle(context, color: AppColors.infoDeep),
              ),
            ),
            SizedBox(height: ResponsiveHelper.spacing(context, 16)),
          ],

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
