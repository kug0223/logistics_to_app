// lib/widgets/dialogs/business_review_dialog.dart

import 'package:flutter/material.dart';
import '../../utils/responsive_helper.dart';
import '../../utils/text_layout.dart';
import '../../theme/app_colors.dart';
import '../../models/settings/trust_settings_model.dart';
import '../../services/monthly_review_service.dart';
import '../../utils/toast_helper.dart';
import 'styled_dialog.dart';
import 'review_dialog_shell.dart';

/// 지원자 → 사업장 리뷰 작성 다이얼로그
/// 
/// 정책:
/// - 월 1회만 작성 가능
/// - 작성 후 수정 불가
/// - 즉시공개(상대방 작성 시) or review_requests.deadline(요청을 만든 근무일 + 14일)이 지난 자정 처리에서 공개
/// - 익명 작성
class BusinessReviewDialog extends StatefulWidget {
  /// 작성자 (지원자) UID
  final String reviewerId;
  
  /// 사업장 ID
  final String businessId;
  
  /// 사업장 이름
  final String businessName;
  
  /// 리뷰 대상 년도
  final int reviewYear;
  
  /// 리뷰 대상 월
  final int reviewMonth;
  
  /// 해당 월 근무 일수
  final int workDaysInMonth;

  /// review_requests 문서 ID (양방향 공개 연동)
  final String? requestId;

  /// 미리 로드된 태그 목록 (showBusinessReviewDialog에서 주입)
  final ReviewTagsModel preloadedTags;

  /// [.62] 태그 설정을 읽지 못했다 — 기본 목록을 현재 설정처럼 보이지 않고 안내한다.
  final bool tagsUnavailable;

  const BusinessReviewDialog({
    super.key,
    required this.reviewerId,
    required this.businessId,
    required this.businessName,
    required this.reviewYear,
    required this.reviewMonth,
    required this.workDaysInMonth,
    this.requestId,
    required this.preloadedTags,
    this.tagsUnavailable = false,
    this.loadLatestTags,
  });

  /// 시험용 — 제출 직전 최신 태그 읽기. production 은 null → 서비스.
  final Future<ReviewTagsModel> Function()? loadLatestTags;

  @override
  State<BusinessReviewDialog> createState() => _BusinessReviewDialogState();
}

class _BusinessReviewDialogState extends State<BusinessReviewDialog> {
  final _commentController = TextEditingController();
  final _reviewService = MonthlyReviewService();
  
  // 상태
  int _rating = 4;
  bool? _wouldWorkAgain;
  List<String> _selectedPositiveTags = [];
  List<String> _selectedImprovementTags = [];
  /// 제출 직전 대조에서 빠진 선택(작성 창을 연 사이 SA 가 지운 태그).
  List<String> _droppedTags = [];
  bool _isSubmitting = false;

  // 태그 목록 (showBusinessReviewDialog에서 미리 로드 후 주입)
  late ReviewTagsModel _tags;

  @override
  void initState() {
    super.initState();
    _tags = widget.preloadedTags;
  }

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  /// [.63] 제출 직전 최신 태그 목록과 대조한다 — 관리자 작성 창과 같은 규칙(사업장 목록 기준).
  Future<bool> _tagsStillValid() async {
    if (_selectedPositiveTags.isEmpty && _selectedImprovementTags.isEmpty) return true;
    final ReviewTagsModel latest;
    try {
      latest = await (widget.loadLatestTags ?? _reviewService.getReviewTags)();
    } catch (e) {
      debugPrint('❌ 리뷰 태그 확인 실패: $e');
      if (mounted) ToastHelper.showError('태그 목록을 확인하지 못했습니다. 다시 시도해 주세요.');
      return false;
    }
    final gone = MonthlyReviewService.unavailableTags(latest,
        positive: _selectedPositiveTags,
        improvement: _selectedImprovementTags,
        business: true);
    if (gone.isEmpty) return true;
    if (mounted) {
      setState(() {
        _tags = latest;
        _selectedPositiveTags = _selectedPositiveTags.where((t) => !gone.contains(t)).toList();
        _selectedImprovementTags = _selectedImprovementTags.where((t) => !gone.contains(t)).toList();
        _droppedTags = gone;
      });
      ToastHelper.showWarning('선택한 태그가 바뀌었습니다. 확인 후 다시 작성해 주세요.');
    }
    return false;
  }

  Future<void> _submitReview() async {
    // 유효성 검사
    if (_wouldWorkAgain == null) {
      ToastHelper.showWarning('다시 근무할 의향을 선택해주세요.');
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      if (!await _tagsStillValid()) return;
      final result = await _reviewService.createReviewForBusiness(
        reviewerId: widget.reviewerId,
        businessId: widget.businessId,
        businessName: widget.businessName,
        reviewYear: widget.reviewYear,
        reviewMonth: widget.reviewMonth,
        workDaysInMonth: widget.workDaysInMonth,
        rating: _rating,
        wouldWorkAgain: _wouldWorkAgain!,
        positiveTags: _selectedPositiveTags,
        improvementTags: _selectedImprovementTags,
        comment: _commentController.text.trim().isEmpty
            ? null
            : _commentController.text.trim(),
        requestId: widget.requestId,
      );

      if (!mounted) return;

      if (result.reviewId != null) {
        // 성공 다이얼로그
        await showDialog(
          context: context,
          barrierDismissible: false,
          builder: (resultContext) => StyledDialog(
            title: '리뷰 작성 완료',
            subtitle: null,
            icon: Icons.check_circle,
            headerColor: AppColors.success,
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.schedule,
                  size: ResponsiveHelper.iconSize(resultContext, 48),
                  color: AppColors.info,
                ),
                SizedBox(height: ResponsiveHelper.spacing(resultContext, 16)),
                Text(
                  // [.64] 공개 기산점을 실제 계약대로(요청이 온 근무일 + 14일)
                  // [.82 F4] 공개는 서버 trigger 가 비동기로 한다 — 제출 응답은 공개 여부를 모른다.
                  //   상대가 이미 작성했어도 맞는 규칙 문장만 쓴다(.82 기기: 즉시 공개됐는데 '관리자도 작성하면'이라 했다).
                  TextLayout.keepWords('리뷰가 등록되었습니다.\n양쪽 리뷰가 모두 등록되거나, 리뷰 요청이 온 근무일로부터 14일이 지나면 공개됩니다.'),
                  style: ResponsiveHelper.bodyStyle(resultContext),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
            actions: [
              StyledDialogButton.primary(
                text: '확인',
                onPressed: () {
                  // [FC-10 FIX] 중첩 다이얼로그 확인 — pop 전 unfocus (_commentController 보호)
                  FocusManager.instance.primaryFocus?.unfocus();
                  Navigator.pop(resultContext);
                },
              ),
            ],
          ),
        );
        // [.62] 뒤로 키로 확인 창만 닫히면 저장된 작성 창이 남아 다시 제출할 수 있어 보였다.
        //   확인 창이 어떻게 닫히든 작성 창도 닫는다.
        if (mounted) Navigator.pop(context, true);
      } else {
        // 대조와 저장 사이에 태그가 지워져 서버가 거절했을 수 있다 — 그렇다면 같은 안내를 한다.
        if (!await _tagsStillValid()) return;
        if (mounted) ToastHelper.showError(result.error ?? '리뷰 작성에 실패했습니다.');
      }
    } catch (e) {
      debugPrint('❌ 리뷰 제출 실패: $e');
      if (mounted) ToastHelper.showError('리뷰 작성에 실패했습니다.');
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ReviewDialogShell(
      header: _buildHeader(context, theme),
      body: [
        _buildBusinessInfo(context),
        SizedBox(height: ResponsiveHelper.spacing(context, 24)),
        _buildRatingSection(context),
        SizedBox(height: ResponsiveHelper.spacing(context, 24)),
        _buildWorkAgainSection(context, theme),
        SizedBox(height: ResponsiveHelper.spacing(context, 24)),
        if (_droppedTags.isNotEmpty) _buildDroppedNotice(context),
        _buildTagSection(
          context,
          title: '좋았던 점',
          icon: Icons.thumb_up_outlined,
          iconColor: AppColors.success,
          tags: _tags.businessPositiveTags,
          selectedTags: _selectedPositiveTags,
          onChanged: (tags) => setState(() => _selectedPositiveTags = tags),
        ),
        SizedBox(height: ResponsiveHelper.spacing(context, 24)),
        _buildTagSection(
          context,
          title: '아쉬운 점',
          icon: Icons.lightbulb_outline,
          iconColor: AppColors.warning,
          tags: _tags.businessImprovementTags,
          selectedTags: _selectedImprovementTags,
          onChanged: (tags) => setState(() => _selectedImprovementTags = tags),
        ),
        SizedBox(height: ResponsiveHelper.spacing(context, 24)),
        _buildCommentSection(context, theme),
        SizedBox(height: ResponsiveHelper.spacing(context, 16)),
        _buildNotice(context),
      ],
      actions: _buildActions(context, theme),
    );
  }

  /// 헤더 — flat AppModalHeader (ALfit Modal Grammar)
  Widget _buildHeader(BuildContext context, ThemeData theme) {
    return AppModalHeader(
      title: '사업장 리뷰 작성',
      subtitle: '${widget.reviewYear}년 ${widget.reviewMonth}월',
      onClose: () {
        FocusManager.instance.primaryFocus?.unfocus();
        Navigator.pop(context);
      },
    );
  }

  /// 사업장 정보
  Widget _buildBusinessInfo(BuildContext context) {
    // [DU268] 회색 면 radius 12 → 시안 카드(흰 면·radius 16·grey200 선). 아이콘·보조 글자 textSecondary(grey600 은 grey50 위 4.41).
    return Container(
      padding: ResponsiveHelper.cardPadding(context),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.grey200),
      ),
      child: Row(
        children: [
          Icon(
            Icons.business,
            color: AppColors.textSecondary,
            size: ResponsiveHelper.iconSize(context, 24),
          ),
          SizedBox(width: ResponsiveHelper.spacing(context, 12)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  TextLayout.identity(widget.businessName),
                  semanticsLabel: widget.businessName,
                  style: ResponsiveHelper.subtitleStyle(context).copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  '${widget.workDaysInMonth}일 근무',
                  style: ResponsiveHelper.smallStyle(context, color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 평점 섹션
  Widget _buildRatingSection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle(context, '전체 평점'),
        SizedBox(height: ResponsiveHelper.spacing(context, 12)),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(5, (index) {
            final starValue = index + 1;
            return Semantics(
              label: '$starValue점',
              button: true,
              selected: _rating == starValue,
              // [DU268] 터치 48×48 고정 칸(이전 좌우 4 → 약 44×36). 빈 별 amber 테두리(흰 위 1.6) → textTertiary.
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => setState(() => _rating = starValue),
                child: SizedBox.square(
                  dimension: 48,
                  child: Center(
                    child: Icon(
                      index < _rating ? Icons.star : Icons.star_border,
                      color: index < _rating ? AppColors.amber : AppColors.textTertiary,
                      size: ResponsiveHelper.iconSize(context, 40),
                    ),
                  ),
                ),
              ),
            );
          }),
        ),
        SizedBox(height: ResponsiveHelper.spacing(context, 8)),
        Center(
          child: Text(
            _getRatingText(_rating),
            style: ResponsiveHelper.bodyStyle(context, color: AppColors.textSecondary), // [DU268] grey600
          ),
        ),
      ],
    );
  }

  String _getRatingText(int rating) {
    switch (rating) {
      case 5: return '최고예요! ⭐';
      case 4: return '좋아요 👍';
      case 3: return '보통이에요';
      case 2: return '아쉬워요';
      case 1: return '별로예요';
      default: return '';
    }
  }

  /// 재근무 의사
  Widget _buildWorkAgainSection(BuildContext context, ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // [.62] 392·2.0 에서 '싶으신가/요?' 로 음절이 끊겼다 — 섹션 제목 도우미가 낱말 단위로 바꾼다.
        _sectionTitle(context, '다시 근무하고 싶으신가요?', required: true),
        SizedBox(height: ResponsiveHelper.spacing(context, 12)),
        // [DU268 r3] 큰 글자에서 '네, / 좋아요' 만 두 줄이 되어 두 선택지 높이가 달랐다(108 vs 65) — 같은 높이로 맞춘다.
        IntrinsicHeight(
          child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: _buildChoiceButton(
                context,
                label: '네, 좋아요',
                icon: Icons.thumb_up,
                isSelected: _wouldWorkAgain == true,
                color: AppColors.success,
                onTap: () => setState(() => _wouldWorkAgain = true),
              ),
            ),
            SizedBox(width: ResponsiveHelper.spacing(context, 12)),
            Expanded(
              child: _buildChoiceButton(
                context,
                label: '아니요',
                icon: Icons.thumb_down,
                isSelected: _wouldWorkAgain == false,
                color: AppColors.error,
                onTap: () => setState(() => _wouldWorkAgain = false),
              ),
            ),
          ],
        ),
        ),
      ],
    );
  }

  Widget _buildChoiceButton(
    BuildContext context, {
    required String label,
    required IconData icon,
    required bool isSelected,
    required Color color,
    required VoidCallback onTap,
  }) {
    // [DU268] 선택 = 대표색(UI-1) — 의미색(success 2.53·error) 글자·테두리 대신 brandSurface 면·brand 2 선·brand 굵은 글자.
    //   미선택은 흰 면·grey300 선·본문색 글자. 의미(좋아요/아니요)는 엄지 아이콘이 맡는다([color] 는 남겨 두고 쓰지 않는다).
    //   최소 높이 48, 글자는 좁은 칸에서 줄을 바꾼다(B320 27px 넘침). 선택 상태를 낭독한다.
    return Semantics(
      button: true,
      selected: isSelected,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 48),
          padding: EdgeInsets.symmetric(
            horizontal: ResponsiveHelper.spacing(context, 8),
            vertical: ResponsiveHelper.spacing(context, 12),
          ),
          decoration: BoxDecoration(
            color: isSelected ? AppColors.brandSurface : AppColors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected ? AppColors.brand : AppColors.grey300,
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                color: isSelected ? AppColors.brand : AppColors.textSecondary,
                size: ResponsiveHelper.iconSize(context, 20),
              ),
              SizedBox(width: ResponsiveHelper.spacing(context, 8)),
              Flexible(
                child: Text(
                  TextLayout.keepWords(label),
                  semanticsLabel: label,
                  style: ResponsiveHelper.bodyStyle(context).copyWith(
                    color: isSelected ? AppColors.brand : AppColors.textPrimary,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// [.63] 빠진 선택 안내 — 무엇이 빠졌는지 글자로 보여 준다.
  Widget _buildDroppedNotice(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: EdgeInsets.only(bottom: ResponsiveHelper.spacing(context, 12)),
      padding: ResponsiveHelper.cardPadding(context),
      decoration: BoxDecoration(
        // [DU268] 주황 8% 면·40% 선·주황 아이콘(약 2.0) → warningBg 면·warningDark 아이콘, 글자 본문색
        color: AppColors.warningBg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline,
              size: ResponsiveHelper.iconSize(context, 18), color: AppColors.warningDark),
          SizedBox(width: ResponsiveHelper.spacing(context, 8)),
          Expanded(
            child: Text(
              TextLayout.keepWords('지금은 고를 수 없는 태그를 선택에서 뺐습니다: '
                  '${_droppedTags.map((t) => '"$t"').join(', ')}. '
                  '남은 선택을 확인하고 다시 작성해 주세요.'),
              style: ResponsiveHelper.smallStyle(context, color: AppColors.textPrimary),
            ),
          ),
        ],
      ),
    );
  }

  /// 태그 섹션
  Widget _buildTagSection(
    BuildContext context, {
    required String title,
    required IconData icon,
    required Color iconColor,
    required List<String> tags,
    required List<String> selectedTags,
    required ValueChanged<List<String>> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // [DU268] [icon]·[iconColor] 는 남겨 두고 그리지 않는다(시안 섹션 제목은 글자만, 선택은 대표색).
        _sectionTitle(context, title, aux: '복수 선택'),
        SizedBox(height: ResponsiveHelper.spacing(context, 12)),
        if (widget.tagsUnavailable || tags.isEmpty)
          Text(
            TextLayout.keepWords(widget.tagsUnavailable
                ? '태그 목록을 불러오지 못했습니다. 태그 없이 작성할 수 있습니다.'
                : '고를 수 있는 태그가 없습니다.'),
            style: ResponsiveHelper.smallStyle(context, color: AppColors.textSecondary), // [DU268] grey500 2.68
          )
        else
        Wrap(
          spacing: ResponsiveHelper.spacing(context, 8),
          // [DU268] 줄 간격은 칩 겉 상하 8 여백(터치 48)이 맡는다 — 보이는 간격 16
          runSpacing: 0,
          children: tags.map((tag) {
            final isSelected = selectedTags.contains(tag);
            // [.62] 선택을 색으로만 알렸다 — 체크 표시와 선택 상태(낭독)를 함께 준다.
            return Semantics(
              button: true,
              selected: isSelected,
              label: tag,
              excludeSemantics: true,
              child: GestureDetector(
                // [DU268] 칩 겉 보이지 않는 상하 8 여백까지 눌린다 — 터치 48 이상(이전 약 35)
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  final newTags = List<String>.from(selectedTags);
                  if (isSelected) {
                    newTags.remove(tag);
                  } else {
                    newTags.add(tag);
                  }
                  onChanged(newTags);
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: ResponsiveHelper.spacing(context, 12),
                      vertical: ResponsiveHelper.spacing(context, 8),
                    ),
                    // [DU268] 선택 = 대표색(UI-1) — 의미색 10% 면·글자(1.99~2.53) 대신 brandSurface·brand.
                    //   미선택은 화면 바탕색 면·본문색 글자(grey600 은 grey50 위 4.41).
                    decoration: BoxDecoration(
                      color: isSelected ? AppColors.brandSurface : AppColors.background,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: isSelected ? AppColors.brand : AppColors.grey200,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (isSelected) ...[
                          Icon(Icons.check, size: ResponsiveHelper.iconSize(context, 14), color: AppColors.brand),
                          SizedBox(width: ResponsiveHelper.spacing(context, 4)),
                        ],
                        Flexible(
                          child: Text(
                            TextLayout.keepWords(tag),
                            style: ResponsiveHelper.smallStyle(context).copyWith(
                              color: isSelected ? AppColors.brand : AppColors.textPrimary,
                              fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  /// 코멘트 섹션
  Widget _buildCommentSection(BuildContext context, ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle(context, '상세 후기', aux: '선택'),
        SizedBox(height: ResponsiveHelper.spacing(context, 12)),
        TextField(
          controller: _commentController,
          maxLines: 3,
          maxLength: 200,
          decoration: InputDecoration(
            // [.64] 320·1.3 에서 '자유/롭게' 로 끊겼다.
            hintText: TextLayout.keepWords('근무하면서 느낀 점을 자유롭게 작성해주세요.'),
            hintMaxLines: 3,
            // [DU268] 힌트 grey400(1.88) → textTertiary, 면 흰색, 경계 grey200(약 1.2) → 테마 입력과 같은 border(grey300)
            hintStyle: ResponsiveHelper.bodyStyle(context, color: AppColors.textTertiary),
            filled: true,
            fillColor: AppColors.surface,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppColors.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: theme.primaryColor),
            ),
          ),
        ),
      ],
    );
  }

  /// 안내 문구
  Widget _buildNotice(BuildContext context) {
    return Container(
      padding: ResponsiveHelper.cardPadding(context),
      decoration: BoxDecoration(
        color: AppColors.infoBg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // [DU268] infoBg 위 info 아이콘·글자(약 2.7) → infoDark 아이콘·infoDeep 글자(Standards 공통 안내 본문)
          Icon(
            Icons.info_outline,
            color: AppColors.infoDark,
            size: ResponsiveHelper.iconSize(context, 18),
          ),
          SizedBox(width: ResponsiveHelper.spacing(context, 8)),
          Expanded(
            // [.63] '작성됩니/다', '미작성/시' 로 음절이 끊겼다.
            child: Text(
              TextLayout.keepWords('리뷰는 익명으로 작성됩니다. 관리자도 리뷰를 작성하면 바로 함께 공개되며, 관리자가 작성하지 않으면 리뷰 요청이 온 근무일로부터 14일이 지난 뒤 공개됩니다.\n작성 후에는 수정할 수 없습니다.'),
              style: ResponsiveHelper.smallStyle(context, color: AppColors.infoDeep),
            ),
          ),
        ],
      ),
    );
  }

  /// [DU268] 섹션 제목 — 시안·DU241/246/259 와 같은 16 bold 본문색, 글자만(앞 의미색 아이콘을 그리지 않는다).
  ///   보조 표시(복수 선택·선택)는 오른쪽 끝 textSecondary(이전 grey500 2.68), 필수 '*' 는 제목 바로 뒤 errorDark(이전 error 3.68).
  Widget _sectionTitle(BuildContext context, String title, {String? aux, bool required = false}) {
    final text = Text(
      TextLayout.keepWords(title),
      semanticsLabel: title,
      style: ResponsiveHelper.subtitleStyle(context).copyWith(
          fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
    );
    return Row(
      children: [
        if (aux != null) Expanded(child: text) else Flexible(child: text),
        if (required)
          Text(
            ' *',
            semanticsLabel: '필수',
            style: ResponsiveHelper.subtitleStyle(context).copyWith(
                fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.errorDark),
          ),
        if (aux != null)
          Text(
            aux,
            style: ResponsiveHelper.smallStyle(context, color: AppColors.textSecondary),
          ),
      ],
    );
  }

  /// 버튼 — ReviewDialogShell scroll 내부에 위치 (keyboard-safe)
  Widget _buildActions(BuildContext context, ThemeData theme) {
    return Row(
      children: [
        Expanded(
          child: StyledDialogButton.cancel(
            onPressed: _isSubmitting ? null : () {
              FocusManager.instance.primaryFocus?.unfocus();
              Navigator.pop(context);
            },
          ),
        ),
        SizedBox(width: ResponsiveHelper.spacing(context, 12)),
        Expanded(
          flex: 2,
          child: StyledDialogButton.primary(
            text: '리뷰 작성',
            onPressed: _isSubmitting ? null : _submitReview,
            isLoading: _isSubmitting,
          ),
        ),
      ],
    );
  }
}

/// 사업장 리뷰 다이얼로그 표시 헬퍼
Future<bool?> showBusinessReviewDialog(
  BuildContext context, {
  required String reviewerId,
  required String businessId,
  required String businessName,
  required int reviewYear,
  required int reviewMonth,
  required int workDaysInMonth,
  String? requestId,
}) async {
  // 다이얼로그 열기 전 태그 미리 로드 — 빈 폼 플래시 방지
  ReviewTagsModel tags;
  var tagsUnavailable = false;
  try {
    tags = await MonthlyReviewService().getReviewTags();
  } catch (e) {
    debugPrint('❌ 리뷰 태그 조회 실패: $e');
    tags = ReviewTagsModel();
    tagsUnavailable = true;
  }
  if (!context.mounted) return null;

  return showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (context) => BusinessReviewDialog(
      reviewerId: reviewerId,
      businessId: businessId,
      businessName: businessName,
      reviewYear: reviewYear,
      reviewMonth: reviewMonth,
      workDaysInMonth: workDaysInMonth,
      requestId: requestId,
      preloadedTags: tags,
      tagsUnavailable: tagsUnavailable,
    ),
  );
}