import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/core/contract_template_model.dart';
import '../../services/contract_template_service.dart';
import '../../theme/app_colors.dart';
import '../../utils/dialog_helper.dart';
import '../../utils/navigation_helper.dart';
import '../../utils/responsive_helper.dart';
import '../../utils/toast_helper.dart';
import '../../widgets/common/app_page_scaffold.dart';
import '../../widgets/common/first_line_icon.dart';
import '../../widgets/common/keep_words_text.dart';
import '../../widgets/common/notification_badge.dart';
import '../common/notification_screen.dart';

class ContractTemplateEditScreen extends StatefulWidget {
  final String businessId;
  final ContractTemplateModel? template;          // null이면 신규
  final String? initialTemplateType;              // 신규 시 선택된 유형
  /// Import flow: 기존 계약서에서 추출한 초기 조항 목록.
  /// template == null 이고 이 값이 있으면 defaultArticlesFor() 대신 사용.
  final List<ContractArticle>? initialArticles;
  /// Import flow: 편집 화면 진입 시 미리 채울 템플릿 이름.
  final String? initialTemplateName;
  /// [DU373 seam] 템플릿 서비스 주입 지점(시험 · 표시 검증용). null 이면 ContractTemplateService() — 기존과 같다.
  final ContractTemplateService? templateService;

  const ContractTemplateEditScreen({
    super.key,
    required this.businessId,
    this.template,
    this.initialTemplateType,
    this.initialArticles,
    this.initialTemplateName,
    this.templateService,
  });

  @override
  State<ContractTemplateEditScreen> createState() =>
      _ContractTemplateEditScreenState();
}

class _ContractTemplateEditScreenState
    extends State<ContractTemplateEditScreen> {
  late final ContractTemplateService _service = widget.templateService ?? ContractTemplateService();
  late final TextEditingController _nameCtrl;
  late List<_ArticleEntry> _entries;
  late String _templateType;
  bool _saving = false;
  bool _hasChanges = false;

  bool get _isNew => widget.template == null;

  @override
  void initState() {
    super.initState();
    // 유형: 기존 템플릿 > 선택된 유형 > 기본(단기 일용직)
    _templateType = widget.template?.templateType
        ?? widget.initialTemplateType
        ?? ContractTemplateType.daily;

    _nameCtrl = TextEditingController(
        text: widget.template?.name ?? widget.initialTemplateName ?? '');
    _nameCtrl.addListener(_onChanged);

    // 우선순위: 기존 template > import initialArticles > type 기본 조항
    final sourceArticles = widget.template?.articles
        ?? widget.initialArticles
        ?? ContractTemplateModel.defaultArticlesFor(_templateType);

    _entries = sourceArticles
        .map((a) => _ArticleEntry(
              titleCtrl: TextEditingController(text: a.title),
              contentCtrl: TextEditingController(text: a.content),
            ))
        .toList();
    for (final e in _entries) {
      e.titleCtrl.addListener(_onChanged);
      e.contentCtrl.addListener(_onChanged);
    }

    // [FIX-IMPORT-DIRTY] import flow에서 initialArticles를 전달받아 열린 경우
    // 사용자가 아무 수정을 하지 않아도 _hasChanges=true로 시작해
    // 저장 없이 back 시 discard 확인이 표시되도록 한다.
    // initialArticles == null인 일반 신규/편집 케이스는 영향 없음.
    if (widget.initialArticles != null) {
      _hasChanges = true;
    }
  }

  void _onChanged() {
    if (!_hasChanges && mounted) setState(() => _hasChanges = true);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _scrollCtrl.dispose();
    for (final e in _entries) {
      e.titleCtrl.dispose();
      e.contentCtrl.dispose();
    }
    super.dispose();
  }

  void _addArticle() {
    if (_saving) return; // [DU380] 저장 중 조항 추가 막음
    final entry = _ArticleEntry(
      titleCtrl: TextEditingController(),
      contentCtrl: TextEditingController(),
    );
    entry.titleCtrl.addListener(_onChanged);
    entry.contentCtrl.addListener(_onChanged);
    setState(() {
      _entries.add(entry);
      _hasChanges = true;
    });
    // 새 항목으로 스크롤
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _removeArticle(int index) {
    if (_saving) return; // [DU380] 저장 중 조항 삭제 막음
    setState(() {
      _entries[index].titleCtrl.dispose();
      _entries[index].contentCtrl.dispose();
      _entries.removeAt(index);
      _hasChanges = true;
    });
  }

  Future<void> _save() async {
    if (_saving) return;
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      ToastHelper.showWarning('템플릿 이름을 입력해주세요');
      return;
    }
    final articles = _entries
        .map((e) => ContractArticle(
              title: e.titleCtrl.text.trim(),
              content: e.contentCtrl.text.trim(),
            ))
        .where((a) => a.title.isNotEmpty || a.content.isNotEmpty)
        .toList();

    // [DU380] 이 편집 route 를 미리 잡아 둔다 — 성공 때 위에 다른 route 가 있어도 그것을 pop 하지 않는다
    final nav = Navigator.of(context);
    final route = ModalRoute.of(context);
    setState(() => _saving = true);
    try {
      if (_isNew) {
        await _service.createTemplate(
          businessId: widget.businessId,
          name: name,
          templateType: _templateType,
          articles: articles,
        );
      } else {
        await _service.updateTemplate(
          widget.template!.copyWith(
            name: name,
            templateType: _templateType,
            articles: articles,
            updatedAt: DateTime.now(),
          ),
        );
      }
      if (mounted) {
        ToastHelper.showSuccess(_isNew ? '템플릿이 저장되었습니다' : '템플릿이 수정되었습니다');
        // [DU380] 이 편집 route 만 true 로 한 번 닫는다(맨 위면 pop · 아니면 그 route 만 제거하며 같은 결과 전달)
        if (route != null && route.isActive) {
          if (route.isCurrent) {
            nav.pop(true);
          } else {
            nav.removeRoute(route, true);
          }
        }
      }
    } catch (e) {
      if (mounted) ToastHelper.showError('저장에 실패했습니다');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  final _scrollCtrl = ScrollController();

  Future<bool> _confirmDiscard(BuildContext ctx) async {
    if (!_hasChanges) return true;
    // [DU377] 기본 AlertDialog → 공용 확인창 셸(DU284–287) — 문구 그대로.
    //   '나가기' = 저장하지 않은 편집을 버리는 실제 손실 실행 → errorDark(DU287). 반환 의미 그대로.
    return DialogHelper.showConfirm(
      ctx,
      title: '편집 취소',
      message: '저장하지 않은 변경사항이 있습니다.\n나가시겠습니까?',
      confirmText: '나가기',
      cancelText: '계속 편집',
      confirmColor: AppColors.errorDark,
      icon: Icons.exit_to_app_outlined,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PopScope(
      // [DU380] 저장 중에는 변경 여부와 상관없이 나가지 않는다(버림 창도 열지 않음)
      canPop: !_hasChanges && !_saving,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop || _saving) return;
        final nav = Navigator.of(context);
        final discard = await _confirmDiscard(context);
        if (!context.mounted) return;
        if (discard) nav.pop();
      },
      child: AppPageScaffold(
        title: _isNew ? '새 템플릿 만들기' : '템플릿 편집',
        actions: [
          IconButton(
            icon: const Icon(Icons.home_outlined),
            color: AppColors.textSecondary,
            onPressed: _saving ? null : () => NavigationHelper.goHome(context), // [DU380] 저장 중 이탈 막음
            tooltip: '홈',
          ),
          NotificationBadge(
            child: IconButton(
              icon: const Icon(Icons.notifications_outlined),
              color: AppColors.textSecondary,
              onPressed: _saving // [DU380] 저장 중 이탈 막음
                  ? null
                  : () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const NotificationScreen()),
                      ),
              tooltip: '알림',
            ),
          ),
          TextButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? SizedBox(
                    width: 18, height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Theme.of(context).primaryColor),
                  )
                : Text('저장',
                    style: ResponsiveHelper.bodyStyle(context).copyWith(
                        color: Theme.of(context).primaryColor,
                        fontWeight: FontWeight.bold)),
          ),
        ],
      // [DU384] 저장 중 짧은 상태 표시 — 본문 맨 위 얇은 진행 막대(겹침 · 레이아웃 이동 0 · 본문 흐림 0)
      body: Stack(
        children: [
      ListView(
        controller: _scrollCtrl,
        padding: ResponsiveHelper.listPadding(context),
        children: [
          // 유형 배지
          _TypeBadge(templateType: _templateType),
          SizedBox(height: ResponsiveHelper.spacing(context, 16)),

          // 템플릿 이름
          _SectionHeader(label: '템플릿 이름'),
          SizedBox(height: ResponsiveHelper.spacing(context, 8)),
          _Card(
            child: TextField(
              controller: _nameCtrl,
              readOnly: _saving, // [DU380] 저장 중 편집 막음(읽기 · 선택은 그대로)
              style: ResponsiveHelper.bodyStyle(context),
              decoration: InputDecoration(
                hintText: '예) 냉장분류 계약서, 일반 단기 계약서',
                // [DU375] grey400 1.88 → textTertiary · B 말줄임 → 두 줄까지
                hintStyle: ResponsiveHelper.smallStyle(context,
                    color: AppColors.textTertiary),
                hintMaxLines: 2,
                border: InputBorder.none,
              ),
            ),
          ),

          // [F-04] 템플릿 재사용 가치 고지 — 편집기에서 한 번만, 신규 작성 시에만.
          //   기존 템플릿을 편집 중인 관리자는 이미 재사용을 경험한 상태다.
          //   "다음 계약에 자동 적용된다"고 말하지 않는다 — 실제 동작은
          //   계약서를 보낼 때 관리자가 템플릿을 직접 고르는 것이다.
          if (_isNew) ...[
            SizedBox(height: ResponsiveHelper.spacing(context, 8)),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // [DU375] 안내 grey500 2.50 → textSecondary · 낱말 조판 · 아이콘 첫 줄 가운데
                FirstLineIcon(Icons.autorenew,
                    size: ResponsiveHelper.iconSize(context, 14),
                    color: AppColors.textTertiary,
                    textStyle: ResponsiveHelper.tinyStyle(context)),
                SizedBox(width: ResponsiveHelper.spacing(context, 6)),
                Expanded(
                  child: KeepWordsText(
                    '저장한 템플릿은 이후 계약서를 만들 때 다시 불러와 사용할 수 있어요.',
                    style: ResponsiveHelper.tinyStyle(context,
                        color: AppColors.textSecondary),
                  ),
                ),
              ],
            ),
          ],

          SizedBox(height: ResponsiveHelper.spacing(context, 24)),

          // 고정 상단 안내
          _SectionHeader(label: '고정 상단 (자동 입력)'),
          SizedBox(height: ResponsiveHelper.spacing(context, 8)),
          Container(
            padding: EdgeInsets.all(
                ResponsiveHelper.spacing(context, 14)),
            decoration: BoxDecoration(
              color: AppColors.grey100,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.grey200),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _FixedRow('제1조 (근로계약 당사자)',
                    '사업장 정보 + 근로자 정보 자동 입력'),
                _FixedRow('제2조 (근무 조건)',
                    '공고 데이터 자동 입력'),
                _FixedRow('제3조 (임금)',
                    '업무상세 임금 정보 자동 입력'),
              ],
            ),
          ),

          SizedBox(height: ResponsiveHelper.spacing(context, 24)),

          // 편집 가능 조항
          // [DU374] B(320 · 2.0)에서 고정 폭 안내가 제목 칸을 좁혔다 — 들어가면 한 줄 양 끝, 아니면 안내가 아래 줄.
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: ResponsiveHelper.spacing(context, 8),
            runSpacing: ResponsiveHelper.spacing(context, 2),
            children: [
              _SectionHeader(label: '편집 가능 조항'),
              Text(
                '드래그로 순서 변경',
                // [DU375] grey400 1.75 → textTertiary
                style: ResponsiveHelper.tinyStyle(context,
                    color: AppColors.textTertiary),
              ),
            ],
          ),
          // [§19] 조항 추가 발견성 — 무엇을 넣어야 하는지 ALfit이 지정하지 않는다.
          //   구체 법률 항목(주휴·보험·연차·퇴직·해고 등)을 나열하면 사실상
          //   법률 체크리스트가 되므로, 추가·수정이 가능하다는 사실만 알린다.
          SizedBox(height: ResponsiveHelper.spacing(context, 4)),
          // [DU375] grey500 2.50 → textSecondary · 낱말 조판(B '있다|면')
          KeepWordsText(
            '사업장에 필요한 내용이 있다면 조항을 추가하거나 수정할 수 있어요.',
            style: ResponsiveHelper.tinyStyle(context, color: AppColors.textSecondary),
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 8)),

          ReorderableListView.builder(
            // [DU384] 저장 중에는 기본 끌기 시작 경로(모바일 길게 누르기 · 데스크톱 기본 핸들)도 끈다
            buildDefaultDragHandles: !_saving,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _entries.length,
            onReorder: (oldIndex, newIndex) {
              if (_saving) return; // [DU380] 저장 중 재정렬 막음
              if (newIndex > oldIndex) newIndex--;
              if (newIndex == oldIndex) return; // 제자리 놓기는 변경이 아니다
              setState(() {
                final item = _entries.removeAt(oldIndex);
                _entries.insert(newIndex, item);
                _hasChanges = true; // [DU380] 순서만 바꿔도 변경 — 뒤로 때 버림 확인 · 저장 순서 반영
              });
            },
            itemBuilder: (ctx, i) {
              final entry = _entries[i];
              return _ArticleCard(
                key: ValueKey(entry),
                index: i,
                entry: entry,
                locked: _saving,
                onDelete: () => _removeArticle(i),
              );
            },
          ),

          SizedBox(height: ResponsiveHelper.spacing(context, 12)),

          // 조항 추가 버튼
          OutlinedButton.icon(
            onPressed: _saving ? null : _addArticle, // [DU380] 저장 중 막음
            icon: const Icon(Icons.add),
            label: const Text('조항 추가'),
            style: OutlinedButton.styleFrom(
              foregroundColor: theme.primaryColor,
              side: BorderSide(color: theme.primaryColor),
              padding: EdgeInsets.symmetric(
                  vertical: ResponsiveHelper.spacing(context, 14)),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
          ),

          // AppPageScaffold는 body에 하단 SafeArea를 적용하지 않는다.
          // 시각적 여백(32) + 기기 하단 인셋(홈 인디케이터/제스처 바)을 더해
          // 마지막 조항/추가 버튼이 시스템 내비게이션 영역에 가려지지 않도록 한다.
          SizedBox(
            height: ResponsiveHelper.spacing(context, 32) +
                MediaQuery.paddingOf(context).bottom,
          ),
        ],
      ),
          if (_saving)
            const Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: LinearProgressIndicator(minHeight: 3),
            ),
        ],
      ),
    ),
  );
  }
}

// ─── 조항 편집 카드 ───────────────────────────────────────────────

/// PDF 상단에 시스템이 고정 생성하는 조항 수 (제1조 당사자·제2조 근무조건·제3조 임금).
/// 편집 가능 조항의 예상 조 번호 표시에만 쓰인다 — 저장 데이터에는 영향이 없다.
const int _fixedArticleCount = 3;

class _ArticleEntry {
  final TextEditingController titleCtrl;
  final TextEditingController contentCtrl;
  _ArticleEntry({required this.titleCtrl, required this.contentCtrl});
}

class _ArticleCard extends StatelessWidget {
  final int index;
  final _ArticleEntry entry;
  final VoidCallback onDelete;
  /// [DU380] 저장 중 — 제목 · 내용 읽기 전용, 끌기 · 삭제 막음
  final bool locked;

  const _ArticleCard({
    super.key,
    required this.index,
    required this.entry,
    required this.onDelete,
    this.locked = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.only(
          bottom: ResponsiveHelper.spacing(context, 12)),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.grey200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 카드 헤더 (번호 + 드래그 핸들 + 삭제)
          // [DU376] 한 줄에 [번호 · 제목 칸 · 끌기 · 삭제]를 두면 B(320 · 2.0)에서 제목 칸이 잘리고
          //   끌기 18 · 삭제 16 터치였다 — 위 줄 [번호 · 끌기 48 · 삭제 48] / 아래 제목 칸(낱말 줄바꿈).
          Padding(
            padding: EdgeInsets.fromLTRB(
              ResponsiveHelper.spacing(context, 12),
              0,
              ResponsiveHelper.spacing(context, 4),
              0,
            ),
            child: Row(
              children: [
                // [UX-P2-01] 표시 전용 — 실제 PDF에서 custom 조항은 고정 제1~3조
                //   뒤에 놓이므로 첫 카드가 제4조 위치다. 배지에 index+1(1,2,3…)을
                //   쓰면 제목의 "제4조"와 항상 어긋나 보인다.
                //   title/content/Firestore/PDF는 일절 건드리지 않는다.
                Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: ResponsiveHelper.spacing(context, 6),
                    vertical: ResponsiveHelper.spacing(context, 3),
                  ),
                  decoration: BoxDecoration(
                    color: Theme.of(context)
                        .primaryColor
                        .withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '제${index + _fixedArticleCount + 1}조',
                    style: ResponsiveHelper.tinyStyle(context,
                            color: Theme.of(context).primaryColor)
                        .copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
                const Spacer(),
                ReorderableDragStartListener(
                  index: index,
                  enabled: !locked,
                  child: SizedBox(
                    width: 48,
                    height: 48,
                    child: Center(
                      child: Icon(Icons.drag_handle,
                          color: locked ? AppColors.grey300 : AppColors.textTertiary, // [DU384] 저장 중 비활성 모양
                          size: ResponsiveHelper.iconSize(context, 20)),
                    ),
                  ),
                ),
                Semantics(
                  button: true,
                  label: '조항 삭제', // [DU380] 화면 용어와 같게(소급 16 채택)
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: locked ? null : onDelete,
                    child: SizedBox(
                      width: 48,
                      height: 48,
                      child: Center(
                        child: Icon(Icons.close,
                            color: locked ? AppColors.grey300 : AppColors.textTertiary, // [DU384] 저장 중 비활성 모양
                            size: ResponsiveHelper.iconSize(context, 18)),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(
              ResponsiveHelper.spacing(context, 12),
              0,
              ResponsiveHelper.spacing(context, 12),
              ResponsiveHelper.spacing(context, 8),
            ),
            child: TextField(
              controller: entry.titleCtrl,
              readOnly: locked,
              // [DU375] 입력 글 grey600 → textPrimary · 예시 글 grey400 1.88 → textTertiary
              style: ResponsiveHelper.smallStyle(context, color: AppColors.textPrimary)
                  .copyWith(fontWeight: FontWeight.w600),
              // [DU376] 긴 제목은 칸 안에서 줄을 바꿔 다 보인다. 줄바꿈 문자는 넣지 않는다(한 줄 칸과 같은 데이터).
              maxLines: null,
              keyboardType: TextInputType.text,
              textInputAction: TextInputAction.done,
              inputFormatters: [FilteringTextInputFormatter.singleLineFormatter],
              decoration: InputDecoration(
                hintText: '조항 제목 (예: 제4조 (연장·야간근로 수당))',
                hintStyle: ResponsiveHelper.tinyStyle(context,
                    color: AppColors.textTertiary),
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
          const Divider(height: 1, color: AppColors.grey100),
          // 내용
          Padding(
            padding: EdgeInsets.all(
                ResponsiveHelper.spacing(context, 12)),
            child: TextField(
              controller: entry.contentCtrl,
              readOnly: locked,
              style: ResponsiveHelper.smallStyle(context, color: AppColors.textPrimary),
              decoration: InputDecoration(
                hintText: '조항 내용을 자유롭게 작성하세요',
                hintStyle: ResponsiveHelper.tinyStyle(context,
                    color: AppColors.textTertiary),
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
              maxLines: null,
              keyboardType: TextInputType.multiline,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── 유형 배지 ───────────────────────────────────────────────────

class _TypeBadge extends StatelessWidget {
  final String templateType;
  const _TypeBadge({required this.templateType});

  @override
  Widget build(BuildContext context) {
    // [DU375] 글자 · 아이콘 = S018 목록(DU344)과 같은 진한 짝(연한 면 위 2.0~2.7 → 4.5 이상).
    //   테두리는 기존 중간 톤 그대로(면 구분용). 이모지(글꼴마다 다르게 그려짐) → 목록과 같은 문서 아이콘.
    Color color;
    Color edge;
    Color bg;
    switch (templateType) {
      case ContractTemplateType.daily:
        color = AppColors.infoDeep;
        edge  = AppColors.info;
        bg    = AppColors.infoBg;
        break;
      case ContractTemplateType.period:
        color = AppColors.successDark;
        edge  = AppColors.success;
        bg    = AppColors.successBg;
        break;
      case ContractTemplateType.outsource:
        color = AppColors.warningDark;
        edge  = AppColors.warning;
        bg    = AppColors.warningBg;
        break;
      default:
        color = AppColors.textSecondary;
        edge  = AppColors.grey600;
        bg    = AppColors.grey100;
    }

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 12),
        vertical: ResponsiveHelper.spacing(context, 8),
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: edge.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FirstLineIcon(Icons.description_outlined,
              size: ResponsiveHelper.iconSize(context, 16),
              color: color,
              textStyle: ResponsiveHelper.smallStyle(context).copyWith(fontWeight: FontWeight.w700)),
          SizedBox(width: ResponsiveHelper.spacing(context, 6)),
          // [DU374] B 에서 설명이 배지 밖으로 넘쳤다(139/166px — DU380 주석 수치 정정) — 남는 폭 안에서 낱말 사이 줄바꿈.
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                KeepWordsText(
                  ContractTemplateType.label(templateType),
                  style: ResponsiveHelper.smallStyle(context)
                      .copyWith(color: color, fontWeight: FontWeight.w700),
                ),
                KeepWordsText(
                  ContractTemplateType.description(templateType),
                  style: ResponsiveHelper.tinyStyle(context, color: color),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── 공통 서브위젯 ────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String label;
  const _SectionHeader({required this.label});

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      // [DU375] grey600 4.30(화면 바탕) → textSecondary
      style: ResponsiveHelper.smallStyle(context,
              color: AppColors.textSecondary)
          .copyWith(fontWeight: FontWeight.w600),
    );
  }
}

class _Card extends StatelessWidget {
  final Widget child;
  const _Card({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding:
          EdgeInsets.all(ResponsiveHelper.spacing(context, 14)),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.grey200),
      ),
      child: child,
    );
  }
}

class _FixedRow extends StatelessWidget {
  final String title;
  final String description;
  const _FixedRow(this.title, this.description);

  @override
  Widget build(BuildContext context) {
    // [DU374] 한 줄 [자물쇠 · 제목 · 설명]이 B(320 · 2.0)에서 폭을 넘었다(19px — DU380 주석 수치 정정) —
    //   모든 폭에서 [자물쇠 | 제목 / 그 아래 설명]으로 쌓는다. 낱말 사이에서만 줄바꿈, 문구 · 색 그대로.
    // [DU375] 제목 grey600 4.23 → textSecondary · 설명 grey400 1.72 → textTertiary(회색 상자 위)
    final titleStyle = ResponsiveHelper.smallStyle(context, color: AppColors.textSecondary)
        .copyWith(fontWeight: FontWeight.w500);
    return Padding(
      padding: EdgeInsets.only(
          bottom: ResponsiveHelper.spacing(context, 6)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FirstLineIcon(Icons.lock_outline,
              size: ResponsiveHelper.iconSize(context, 14),
              color: AppColors.textTertiary,
              textStyle: titleStyle),
          SizedBox(width: ResponsiveHelper.spacing(context, 6)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                KeepWordsText(title, style: titleStyle),
                KeepWordsText(description,
                    style: ResponsiveHelper.tinyStyle(context,
                        color: AppColors.textTertiary)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
