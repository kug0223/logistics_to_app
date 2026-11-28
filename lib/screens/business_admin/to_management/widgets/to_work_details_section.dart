import 'package:flutter/material.dart';
import '../../../../models/work_detail_input.dart';
import '../../../../models/core/work_detail_model.dart';
import '../../../../utils/responsive_helper.dart';
import '../../../../utils/text_layout.dart';
import '../../../../utils/expected_daily_wage.dart';
import 'to_section_container.dart';
import 'to_work_detail_card.dart';
import '../../../../theme/app_colors.dart';

/// ✨ TO 업무 상세 섹션
/// create_to_screen, edit_to_screen에서 공통으로 사용
class TOWorkDetailsSection extends StatelessWidget {
  /// WorkDetailInput 리스트 (create용)
  final List<WorkDetailInput>? workDetailInputs;

  /// WorkDetailModel 리스트 (레거시 edit용)
  final List<WorkDetailModel>? workDetailModels;

  /// WorkDetailData 리스트 (새 아키텍처 edit용)
  final List<WorkDetailData>? workDetailData;

  /// 업무 추가 콜백
  final VoidCallback onAddWork;

  /// 업무 삭제 콜백 (index 기반 - create용)
  final void Function(int index)? onRemoveWorkByIndex;

  /// 업무 수정 콜백 (index 기반 - create용)
  final void Function(int index)? onEditWorkByIndex;

  /// 업무 수정 콜백 (WorkDetailModel - 레거시 edit용)
  final void Function(WorkDetailModel work)? onEditWork;

  /// 업무 삭제 콜백 (WorkDetailModel - 레거시 edit용)
  final void Function(WorkDetailModel work)? onDeleteWork;

  /// 업무 수정 콜백 (WorkDetailData - 새 아키텍처 edit용)
  final void Function(WorkDetailData work)? onEditWorkData;

  /// 업무 삭제 콜백 (WorkDetailData - 새 아키텍처 edit용)
  final void Function(WorkDetailData work)? onDeleteWorkData;

  /// 업무 유형 없음 경고 표시
  final bool showNoWorkTypeWarning;

  const TOWorkDetailsSection({
    super.key,
    this.workDetailInputs,
    this.workDetailModels,
    this.workDetailData,
    required this.onAddWork,
    this.onRemoveWorkByIndex,
    this.onEditWorkByIndex,
    this.onEditWork,
    this.onDeleteWork,
    this.onEditWorkData,
    this.onDeleteWorkData,
    this.showNoWorkTypeWarning = false,
  }) : assert(
         workDetailInputs != null || workDetailModels != null || workDetailData != null,
         'One of workDetailInputs, workDetailModels, or workDetailData must be provided',
       );

  int get _workCount {
    if (workDetailInputs != null) return workDetailInputs!.length;
    if (workDetailModels != null) return workDetailModels!.length;
    if (workDetailData != null) return workDetailData!.length;
    return 0;
  }

  bool get _isEmpty {
    if (workDetailInputs != null) return workDetailInputs!.isEmpty;
    if (workDetailModels != null) return workDetailModels!.isEmpty;
    if (workDetailData != null) return workDetailData!.isEmpty;
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return TOSectionContainer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 헤더
          // [DU1 구현48 C1 S031] 320·2.0 에서 제목+업무 추가 버튼 한 줄이 오른쪽으로 122px 넘쳤다 —
          //   폭이 모자라면 버튼을 다음 줄로 내린다(Wrap).
          // [DU1 구현49 · 감사49 §2] 부모 Column 이 start 정렬이라 Wrap 이 내용 폭으로 접혀 넓은 한 줄에서 spaceBetween 이
          //   양 끝으로 벌리지 못했다 — 전체 폭을 주어 넓은 폭은 기존처럼 양 끝(제목 왼쪽·버튼 오른쪽) 배치를 지킨다.
          SizedBox(
            width: double.infinity,
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: ResponsiveHelper.spacing(context, 8),
              runSpacing: ResponsiveHelper.spacing(context, 8),
              children: [
                Text(
                  TextLayout.keepWords('업무 목록 ($_workCount개)'),
                  style: ResponsiveHelper.subtitleStyle(context).copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                _buildAddButton(context, theme),
              ],
            ),
          ),
          
          // 업무 유형 없음 경고
          if (showNoWorkTypeWarning) ...[
            SizedBox(height: ResponsiveHelper.spacing(context, 16)),
            _buildNoWorkTypeWarning(context),
          ],
          
          // 빈 상태
          if (_isEmpty && !showNoWorkTypeWarning) ...[
            SizedBox(height: ResponsiveHelper.spacing(context, 24)),
            _buildEmptyState(context),
          ],
          
          // 업무 카드 목록
          if (!_isEmpty) ...[
            SizedBox(height: ResponsiveHelper.spacing(context, 16)),
            _buildWorkDetailCards(context),
            // [F293-WAGE-01] 시급 업무가 하나라도 있으면 카드의 '하루 예상' 금액이 무엇인지 한 번 말한다(고지 정본 그대로).
            if (_hasHourlyWork) ...[
              SizedBox(height: ResponsiveHelper.spacing(context, 4)),
              Text(
                TextLayout.keepWords(ExpectedWageText.disclosure),
                key: const ValueKey('to-work-expected-wage-disclosure'),
                semanticsLabel: ExpectedWageText.disclosure,
                style: ResponsiveHelper.smallStyle(context, color: AppColors.textSecondary),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildAddButton(BuildContext context, ThemeData theme) {
    // [DU319] '업무 추가' 는 일반 진행 행동 — 성공색(successBg · successDark) 대신 brand 톤(Standards §304)
    return Material(
      color: AppColors.brandSurface,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onAddWork,
        borderRadius: BorderRadius.circular(12),
        // [DU1 구현49] 실측 39(360·1.0) — 공통 기준 터치 최소 48
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: ResponsiveHelper.spacing(context, 16),
            vertical: ResponsiveHelper.spacing(context, 10),
          ),
          // [DU1 구현48] Wrap 안에서 버튼이 줄 전체로 늘지 않게 내용 폭만 쓴다
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.add_circle_outline,
                size: ResponsiveHelper.iconSize(context, 18),
                color: AppColors.brand,
              ),
              SizedBox(width: ResponsiveHelper.spacing(context, 8)),
              Text(
                '업무 추가',
                style: ResponsiveHelper.bodyStyle(context).copyWith(
                  color: AppColors.brand,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
        ),
      ),
    );
  }

  Widget _buildNoWorkTypeWarning(BuildContext context) {
    return Container(
      padding: ResponsiveHelper.cardPadding(context),
      decoration: BoxDecoration(
        color: AppColors.warningBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.warningLight,
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.warning_amber,
            color: AppColors.warningDark,
            size: ResponsiveHelper.iconSize(context, 20),
          ),
          SizedBox(width: ResponsiveHelper.spacing(context, 12)),
          Expanded(
            child: Text(
              '업무를 먼저 등록해주세요',
              style: ResponsiveHelper.bodyStyle(context).copyWith(
                color: AppColors.warningDarkest,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Column(
        children: [
          Icon(
            Icons.work_outline,
            size: ResponsiveHelper.iconSize(context, 48),
            color: AppColors.grey400,
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 12)),
          // [DU319] 320·2.0 에서 '없습니 / 다' 로 끊겼다 — 낱말 단위
          Text(
            TextLayout.keepWords('등록된 업무가 없습니다'),
            semanticsLabel: '등록된 업무가 없습니다',
            style: ResponsiveHelper.bodyStyle(
              context,
              color: AppColors.grey600,
            ),
          ),
        ],
      ),
    );
  }

  /// [F293-WAGE-01] 카드에 '하루 예상' 금액이 나오는 업무(시급)가 있는가 — 고지 문장 위치.
  bool get _hasHourlyWork =>
      (workDetailInputs?.any((d) => d.wageType == 'hourly') ?? false) ||
      (workDetailModels?.any((w) => w.wageType == 'hourly') ?? false) ||
      (workDetailData?.any((w) => w.wageType == 'hourly') ?? false);

  Widget _buildWorkDetailCards(BuildContext context) {
    // WorkDetailInput 리스트 (create 모드)
    if (workDetailInputs != null) {
      // 정렬 후 화면 위치(i)를 원본 인덱스(entry.key)와 분리해서 사용
      // entry.key = 원본 리스트 인덱스 → onEdit/onDelete에 전달
      final sorted = workDetailInputs!.asMap().entries.toList()
        ..sort((a, b) {
          final typeCompare = (a.value.workType ?? '').compareTo(b.value.workType ?? '');
          if (typeCompare != 0) return typeCompare;
          final timeCompare = (a.value.startTime ?? '').compareTo(b.value.startTime ?? '');
          if (timeCompare != 0) return timeCompare;
          return (a.value.endTime ?? '').compareTo(b.value.endTime ?? '');
        });
      return Column(
        children: sorted.map((entry) {
          final originalIndex = entry.key; // 정렬 전 원본 인덱스 사용
          final detail = entry.value;
          return TOWorkDetailCard.fromInput(
            detail: detail,
            onEdit: onEditWorkByIndex != null ? () => onEditWorkByIndex!(originalIndex) : null,
            onDelete: onRemoveWorkByIndex != null ? () => onRemoveWorkByIndex!(originalIndex) : null,
          );
        }).toList(),
      );
    }

    // WorkDetailModel 리스트 (레거시 edit 모드)
    if (workDetailModels != null) {
      final sorted = [...workDetailModels!]
        ..sort((a, b) {
          final typeCompare = a.workType.compareTo(b.workType);
          if (typeCompare != 0) return typeCompare;
          final timeCompare = a.startTime.compareTo(b.startTime);
          if (timeCompare != 0) return timeCompare;
          return a.endTime.compareTo(b.endTime);
        });
      return Column(
        children: sorted.map((work) {
          return TOWorkDetailCard.fromModel(
            work: work,
            onEdit: onEditWork != null ? () => onEditWork!(work) : null,
            onDelete: onDeleteWork != null ? () => onDeleteWork!(work) : null,
          );
        }).toList(),
      );
    }

    // WorkDetailData 리스트 (새 아키텍처 edit 모드)
    if (workDetailData != null) {
      final sorted = [...workDetailData!]
        ..sort((a, b) {
          final typeCompare = a.workType.compareTo(b.workType);
          if (typeCompare != 0) return typeCompare;
          final timeCompare = a.startTime.compareTo(b.startTime);
          if (timeCompare != 0) return timeCompare;
          return a.endTime.compareTo(b.endTime);
        });
      return Column(
        children: sorted.map((work) {
          return TOWorkDetailCard.fromData(
            work: work,
            onEdit: onEditWorkData != null ? () => onEditWorkData!(work) : null,
            onDelete: onDeleteWorkData != null ? () => onDeleteWorkData!(work) : null,
          );
        }).toList(),
      );
    }

    return const SizedBox.shrink();
  }
}
