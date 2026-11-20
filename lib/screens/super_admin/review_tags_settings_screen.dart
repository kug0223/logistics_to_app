// lib/screens/super_admin/review_tags_settings_screen.dart
// [R7-P1-7 P17-A] GradientScaffold → AppPageScaffold(D0 flat admin shell).
//   이 화면은 헤더에 TabBar 가 있고 라벨·인디케이터가 흰색이었다 — 파란 그라디언트
//   위에서만 읽히는 색이다. 밝은 app bar 에 그대로 두면 라벨이 보이지 않으므로
//   같은 전환에서 **대비까지 함께** 옮긴다(계약 관리 화면이 쓰는 flat TabBar 계약).

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import '../../utils/responsive_helper.dart';
import '../../utils/text_layout.dart';
import '../../models/settings/trust_settings_model.dart';
import '../../widgets/common/app_empty_state.dart';
import '../../providers/user_provider.dart';
import '../../utils/toast_helper.dart';
import '../../utils/dialog_helper.dart';
import '../../theme/app_colors.dart';
import '../../widgets/dialogs/styled_dialog.dart';
import '../../widgets/common/app_page_scaffold.dart';
import '../../widgets/common/loading_widget.dart';
import '../../widgets/common/app_tab_label.dart';

/// 리뷰 태그 관리 화면
///
/// [.62] 리뷰는 태그를 **글자 그대로** 저장한다(`monthly_reviews.positiveTags` 등).
///   그래서 여기서 지우거나 새로 넣어도 이미 쓴 리뷰의 태그는 바뀌지 않는다.
///   - 읽기 실패: 기본 목록을 현재 설정처럼 보여 주고, 그 상태로 추가·삭제하면
///     문서 전체를 기본값 ± 1개로 덮었다 → 실패 화면을 보이고 쓰기를 막는다.
///   - 저장: 화면이 들고 있던 네 목록 전체를 `set()` 했다 → 다른 SA 가 그 사이
///     넣은 태그가 사라졌다 → 태그 한 개만 arrayUnion/arrayRemove 한다.
///   - 저장 실패: 오류를 삼켜 되돌림이 돌지 않았다(화면 ≠ 저장값) → 서버 값을 다시 읽는다.
class ReviewTagsSettingsScreen extends StatefulWidget {
  const ReviewTagsSettingsScreen({super.key, this.load, this.mutate});

  /// 시험용 — 문서 읽기(없으면 null). production 은 null → Firestore.
  final Future<Map<String, dynamic>?> Function()? load;

  /// 시험용 — 태그 한 개 추가/삭제. production 은 null → Firestore.
  final Future<void> Function(String field, String tag, {required bool add})? mutate;

  @override
  State<ReviewTagsSettingsScreen> createState() => _ReviewTagsSettingsScreenState();
}

class _ReviewTagsSettingsScreenState extends State<ReviewTagsSettingsScreen> 
    with SingleTickerProviderStateMixin {
  FirebaseFirestore get _firestore => FirebaseFirestore.instance;
  late TabController _tabController;
  
  bool _isLoading = true;
  bool _isSaving = false;
  Object? _loadError;

  static const _fields = {
    'positive': 'positiveTags',
    'improvement': 'improvementTags',
    'businessPositive': 'businessPositiveTags',
    'businessImprovement': 'businessImprovementTags',
  };

  DocumentReference<Map<String, dynamic>> get _doc =>
      _firestore.collection('settings').doc('review_tags');

  List<String> _listOf(String type) => switch (type) {
        'positive' => _positiveTags,
        'improvement' => _improvementTags,
        'businessPositive' => _businessPositiveTags,
        _ => _businessImprovementTags,
      };

  // 태그 목록
  List<String> _positiveTags = [];
  List<String> _improvementTags = [];
  List<String> _businessPositiveTags = [];
  List<String> _businessImprovementTags = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!context.read<UserProvider>().isSuperAdmin) {
        Navigator.pop(context);
        return;
      }
      _loadTags();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<Map<String, dynamic>?> _read() async {
    if (widget.load != null) return widget.load!();
    final doc = await _doc.get();
    return doc.exists ? doc.data() : null;
  }

  void _apply(Map<String, dynamic> data) {
    _positiveTags = List<String>.from(data['positiveTags'] ?? []);
    _improvementTags = List<String>.from(data['improvementTags'] ?? []);
    _businessPositiveTags = List<String>.from(data['businessPositiveTags'] ?? []);
    _businessImprovementTags = List<String>.from(data['businessImprovementTags'] ?? []);
  }

  Future<void> _loadTags() async {
    if (mounted) setState(() { _isLoading = true; _loadError = null; });
    try {
      var data = await _read();
      if (data == null) {
        // 문서가 없으면 기본 목록으로 한 번 만든다. 이미 누가 만들었으면 덮지 않는다.
        final defaults = ReviewTagsModel.defaults().toMap();
        if (widget.load == null) {
          await _firestore.runTransaction((tx) async {
            if ((await tx.get(_doc)).exists) return;
            tx.set(_doc, {...defaults, 'updatedAt': FieldValue.serverTimestamp()});
          });
          data = await _read() ?? defaults;
        } else {
          data = defaults;
        }
      }
      _apply(data);
    } catch (e) {
      debugPrint('❌ 태그 로드 실패: $e');
      _loadError = e;
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  /// 태그 한 개만 바꾼다 — 다른 SA 가 그 사이 바꾼 태그를 덮지 않는다.
  Future<void> _mutate(String type, String tag, {required bool add}) async {
    final field = _fields[type]!;
    if (widget.mutate != null) return widget.mutate!(field, tag, add: add);
    await _doc.update({
      field: add ? FieldValue.arrayUnion([tag]) : FieldValue.arrayRemove([tag]),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// 저장 뒤(성공·실패 모두) 서버 값으로 화면을 맞춘다.
  Future<void> _refresh() async {
    try {
      final data = await _read();
      if (data != null && mounted) setState(() => _apply(data));
    } catch (e) {
      debugPrint('❌ 태그 다시 읽기 실패: $e');
    }
  }

  Future<void> _addTag(String type) async {
    if (_isSaving || _loadError != null) return;
    // [FC-TAG-01 OWNERSHIP FIX] _TagInputDialog(StatefulWidget)이 ctrl을
    // 직접 소유하고 State.dispose()에서 해제한다.
    final result = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) => const _TagInputDialog(title: '태그 추가'),
    );
    if (result == null || result.isEmpty || !mounted) return;
    if (_listOf(type).contains(result)) {
      ToastHelper.showError('이미 있는 태그입니다');
      return;
    }
    setState(() => _isSaving = true);
    try {
      await _mutate(type, result, add: true);
      if (mounted) ToastHelper.showSuccess('태그가 저장되었습니다');
    } catch (e) {
      debugPrint('❌ 태그 추가 실패: $e');
      if (mounted) ToastHelper.showError('저장하지 못했습니다. 저장된 목록을 다시 불러왔습니다');
    } finally {
      await _refresh();
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _removeTag(String type, String tag) async {
    if (_isSaving || _loadError != null) return;
    final confirmed = await DialogHelper.showConfirm(
      context,
      title: '태그 삭제',
      message: TextLayout.keepWords('"$tag" 태그를 삭제하시겠습니까?\n'
          '새 리뷰에서 더 이상 고를 수 없습니다. 이미 작성된 리뷰에는 이 태그가 그대로 남습니다.'),
      confirmText: '삭제',
    );

    if (!confirmed || !mounted) return;

    setState(() => _isSaving = true);
    try {
      await _mutate(type, tag, add: false);
      if (mounted) ToastHelper.showSuccess('태그를 삭제했습니다');
    } catch (e) {
      debugPrint('❌ 태그 삭제 실패: $e');
      if (mounted) ToastHelper.showError('삭제하지 못했습니다. 저장된 목록을 다시 불러왔습니다');
    } finally {
      await _refresh();
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // [DU506] 큰 글자 · 좁은 폭(B 320@2.0)에서 고정 두 탭 이름이 '지원자 평' · '사업장 평'으로 잘렸다 — 한 줄에 안 들어가면 가로 스크롤(DU495 · DU497 과 같은 판정).
    //   perTab 110 = '사업장 평가' 글자 + 좌우 여백(DU497 '관리자 FAQ' 와 같다).
    final tabsFit = TextLayout.tabsFit(context, MediaQuery.sizeOf(context).width, 2, perTab: 110);
    return AppPageScaffold(
      title: '리뷰 태그 관리',
      bottom: TabBar(
        controller: _tabController,
        isScrollable: !tabsFit,
        tabAlignment: tabsFit ? null : TabAlignment.start,
        indicatorColor: theme.primaryColor,
        indicatorWeight: 2.5,
        labelColor: theme.primaryColor,
        unselectedLabelColor: AppColors.textSecondary, // [DU494] grey500(2.68) → 보조 글자색(DU242 · DU429 와 같다)
        dividerColor: Colors.transparent,
        tabs: const [
          Tab(child: AppTabLabel(label: '지원자 평가')),
          Tab(child: AppTabLabel(label: '사업장 평가')),
        ],
      ),
      body: _isLoading
          ? const LoadingWidget()
          : _loadError != null
          ? AppEmptyState(
              icon: Icons.cloud_off_outlined,
              title: '리뷰 태그를 불러오지 못했습니다',
              subtitle: '현재 설정을 모르는 상태라 추가·삭제를 막았습니다.',
              action: TextButton(onPressed: _loadTags, child: const Text('다시 시도')),
            )
          : TabBarView(
              controller: _tabController,
              children: [
                // 지원자 평가 태그
                _buildTagsTab(
                  context,
                  positiveTags: _positiveTags,
                  positiveType: 'positive',
                  positiveTitle: '긍정 태그',
                  positiveSubtitle: '관리자가 지원자에게 부여하는 긍정적 평가',
                  improvementTags: _improvementTags,
                  improvementType: 'improvement',
                  improvementTitle: '개선 태그',
                  improvementSubtitle: '관리자가 지원자에게 부여하는 개선점',
                ),
                // 사업장 평가 태그
                _buildTagsTab(
                  context,
                  positiveTags: _businessPositiveTags,
                  positiveType: 'businessPositive',
                  positiveTitle: '긍정 태그',
                  positiveSubtitle: '지원자가 사업장에 부여하는 긍정적 평가',
                  improvementTags: _businessImprovementTags,
                  improvementType: 'businessImprovement',
                  improvementTitle: '개선 태그',
                  improvementSubtitle: '지원자가 사업장에 부여하는 개선점',
                ),
              ],
            ),
    );
  }

  Widget _buildTagsTab(
    BuildContext context, {
    required List<String> positiveTags,
    required String positiveType,
    required String positiveTitle,
    required String positiveSubtitle,
    required List<String> improvementTags,
    required String improvementType,
    required String improvementTitle,
    required String improvementSubtitle,
  }) {
    return SingleChildScrollView(
      padding: ResponsiveHelper.cardPadding(context),
      child: Column(
        children: [
          // 긍정 태그 섹션
          _buildTagSection(
            context,
            title: positiveTitle,
            subtitle: positiveSubtitle,
            tags: positiveTags,
            type: positiveType,
            color: AppColors.success,
            icon: Icons.thumb_up_outlined,
          ),
          
          SizedBox(height: ResponsiveHelper.spacing(context, 20)),
          
          // 개선 태그 섹션
          _buildTagSection(
            context,
            title: improvementTitle,
            subtitle: improvementSubtitle,
            tags: improvementTags,
            type: improvementType,
            color: AppColors.warning,
            icon: Icons.build_outlined,
          ),
          
          SizedBox(height: ResponsiveHelper.spacing(context, 20)),
        ],
      ),
    );
  }

  Widget _buildTagSection(
    BuildContext context, {
    required String title,
    required String subtitle,
    required List<String> tags,
    required String type,
    required Color color,
    required IconData icon,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 헤더
          Container(
            padding: ResponsiveHelper.cardPadding(context),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
              ),
            ),
            child: Row(
              children: [
                Icon(icon, size: ResponsiveHelper.iconSize(context, 20), color: color),
                SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        TextLayout.keepWords('$title (${tags.length}개)'),
                        // [DU494] 구역 색 제목(구역 색 10% 면 위 2.0–2.5) → 섹션 제목 규칙(본문색 bold · DU490). 구역 색은 아이콘 · 면이 말한다.
                        style: ResponsiveHelper.subtitleStyle(context).copyWith(
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      // [.62] 392·2.0 에서 '부/여하는' 으로 음절이 끊겼다.
                      Text(
                        TextLayout.keepWords(subtitle),
                        // [DU494] grey600(구역 색 10% 면 위 4.2–4.3) → 보조 글자색.
                        style: ResponsiveHelper.smallStyle(context, color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                ),
                // 추가 버튼
                IconButton(
                  onPressed: () => _addTag(type),
                  icon: Icon(
                    Icons.add_circle_outline,
                    // [DU494] 조작 아이콘 — 구역 색 10% 면 위 구역 색 2.0–2.5(3:1 미달) → 진한 짝.
                    color: _tagInk(color),
                    size: ResponsiveHelper.iconSize(context, 24),
                  ),
                  tooltip: '태그 추가',
                ),
              ],
            ),
          ),
          
          // 태그 목록
          Padding(
            padding: ResponsiveHelper.cardPadding(context),
            child: tags.isEmpty
                ? Center(
                    child: Padding(
                      padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 20)),
                      child: Text(
                        '등록된 태그가 없습니다',
                        // [DU494] grey400(1.88) → 보조 글자색.
                        style: ResponsiveHelper.bodyStyle(context, color: AppColors.textSecondary),
                      ),
                    ),
                  )
                : Wrap(
                    spacing: ResponsiveHelper.spacing(context, 8),
                    runSpacing: ResponsiveHelper.spacing(context, 8),
                    children: tags.map((tag) => _buildTagChip(
                      context,
                      tag: tag,
                      type: type,
                      color: color,
                    )).toList(),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildTagChip(
    BuildContext context, {
    required String tag,
    required String type,
    required Color color,
  }) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 12),
        vertical: ResponsiveHelper.spacing(context, 8),
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Flexible 필수: 긴 태그명은 칩 안에서 줄을 바꾼다(말줄임 없음 — 이름 전체가 보여야 지울지 판단한다).
          Flexible(
            child: Text(
              TextLayout.keepWords(tag),
              // [DU494] 구역 색 10% 면 위 구역 색 글자 → 진한 짝(면 · 테두리는 구역 색 그대로).
              style: ResponsiveHelper.bodyStyle(context).copyWith(
                color: _tagInk(color),
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          SizedBox(width: ResponsiveHelper.spacing(context, 6)),
          Semantics(
            button: true,
            label: '태그 $tag 삭제',
            child: GestureDetector(
              onTap: () => _removeTag(type, tag),
              child: Icon(
                Icons.close,
                size: ResponsiveHelper.iconSize(context, 16),
                color: _tagInk(color), // [DU494] 삭제 조작 아이콘 — 진한 짝(3:1 이상)
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// [DU494] 구역 색 옅은 면 위 글자 · 조작 아이콘 — 진한 짝(StatusBadge 짝 · DU425–427 · DU491).
Color _tagInk(Color c) {
  if (c == AppColors.success) return AppColors.successDark;
  if (c == AppColors.warning) return AppColors.warningDark;
  return c;
}

/// 태그 입력 다이얼로그
/// [FC-TAG-01 OWNERSHIP FIX] controller를 외부에서 받지 않고 State가 직접 소유·해제
class _TagInputDialog extends StatefulWidget {
  final String title;
  const _TagInputDialog({required this.title});

  @override
  State<_TagInputDialog> createState() => _TagInputDialogState();
}

class _TagInputDialogState extends State<_TagInputDialog> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return StyledDialog(
      title: widget.title,
      icon: Icons.label_outline,
      headerColor: theme.primaryColor,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          StyledDialogTextField(
            controller: _ctrl,
            labelText: '태그 이름',
            hintText: '예: 성실함',
            prefixIcon: Icons.tag,
          ),
        ],
      ),
      actions: [
        StyledDialogButton.cancel(
          onPressed: () {
            FocusManager.instance.primaryFocus?.unfocus();
            Navigator.pop(context);
          },
        ),
        StyledDialogButton.primary(
          text: '추가',
          onPressed: () {
            final text = _ctrl.text.trim();
            if (text.isEmpty) {
              ToastHelper.showError('태그 이름을 입력하세요');
              return;
            }
            FocusManager.instance.primaryFocus?.unfocus();
            Navigator.pop(context, text);
          },
        ),
      ],
    );
  }
}