// lib/widgets/dialogs/alternative_work_offer_sheet.dart
//
// [CROSS-DOMAIN-R5.3B] 다른 업무 제안 — 관리자 공용 시트.
//
//   R5.3A에서 '파트변경'을 얼린 이유는 그것이 근로자가 동의한 적 없는 조건으로
//   지원서를 덮어썼기 때문이다. 대체 경로는 덮어쓰지 않는다: 같은 슬롯의 다른
//   업무(B)로 **새 제안**을 만들고, 원 지원(A)은 근로자가 수락하는 순간에만
//   서버가 같은 트랜잭션에서 접는다.
//
//   그래서 이 시트의 문구는 "업무를 바로 변경합니다"가 될 수 없다.
//   관리자가 하는 일은 제안을 보내는 것까지다.
//
//   지원자 관리 화면이 둘(WorkApplicantsDialog / DayApplicantsDialog)이라
//   여기 한 곳에 둔다. 같은 행동을 두 벌로 쓰면 한쪽 문구만 바뀐다.

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';

import '../../models/core/work_detail_model.dart';
import '../../theme/app_colors.dart';
import '../../utils/dialog_helper.dart';
import '../../utils/format_helper.dart';
import '../../utils/responsive_helper.dart';
import '../../utils/toast_helper.dart';
import '../work_type_icon.dart';

class AlternativeWorkOfferSheet {
  const AlternativeWorkOfferSheet._();

  /// 이 지원자에게 제안할 수 있는 다른 업무들.
  ///
  /// 지금 지원한 업무는 뺀다(같은 업무 제안은 의미가 없다). 모집이 끝난 업무도
  /// 뺀다 — 제안해도 수락 시점에 서버가 거부한다. wdId가 없는 legacy 업무는
  /// 자연키(`{toId}_{slotId}_{wdId}_{uid}`)를 만들 수 없으므로 제외한다.
  static List<WorkDetailModel> offerableFrom(
    List<WorkDetailModel> all,
    WorkDetailModel? currentWork,
  ) {
    return all.where((w) {
      if (w.id.isEmpty) return false;
      if (currentWork != null && w.id == currentWork.id) return false;
      if (w.isClosed) return false;
      return true;
    }).toList();
  }

  /// 급여 조건 옵션 — 서버 allowlist와 같은 값이다.
  static const String optionTargetBase = 'TARGET_BASE';
  static const String optionMatchSourceWage = 'MATCH_SOURCE_WAGE';

  /// 제안 대상 업무와 급여 조건을 함께 고른다. 취소하면 null.
  ///
  /// [CROSS-DOMAIN-R5.3C.1] 급여 조건은 두 갈래뿐이고 **금액 입력란은 없다**.
  ///   · 공고 기본 급여      — B가 모집 중인 조건 그대로
  ///   · 기존 지원 급여 유지 — B의 근로조건을 유지하되 금액만 A와 같게
  ///
  /// 두 번째는 같은 급여 기준(시급/일급)일 때만, 그리고 개별 급여 제안
  /// 권한이 있을 때만 고를 수 있다. 고를 수 없을 때도 **숨기지 않고**
  /// 이유를 적는다 — 권한이나 조건의 부재를 "그런 기능이 없음"으로 보이게
  /// 하지 않기 위해서다. 그리고 그 경우에도 업무 제안 자체는 막지 않는다.
  static Future<({String wdId, String option})?> pickOffer(
    BuildContext context, {
    required String workerName,
    required WorkDetailModel? currentWork,
    required List<WorkDetailModel> candidates,
    required int Function(WorkDetailModel) confirmedCountOf,
    required int sourceWage,
    required String? sourceWageType,
    required bool canManageWage,
  }) {
    WorkDetailModel? picked;
    String option = optionTargetBase;

    return DialogHelper.showSheet<({String wdId, String option})>(
      context,
      isScrollControlled: true,
      builder: (sheetCtx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          final sel = picked;
          final sameType =
              sel != null && sourceWageType != null && sourceWageType == sel.wageType;
          final matchEnabled = sameType && canManageWage && sourceWage > 0;
          // 고를 수 없게 된 옵션이 선택돼 있으면 되돌린다.
          if (!matchEnabled && option == optionMatchSourceWage) {
            option = optionTargetBase;
          }
          return SafeArea(
            top: false,
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$workerName님에게 다른 업무 제안',
                    style: ResponsiveHelper.subtitleStyle(ctx)
                        .copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '제안을 보내면 근로자가 조건을 보고 직접 선택합니다.\n'
                    '지금 지원은 그대로 유지되고, 근로자가 제안을 수락할 때만 정리됩니다.',
                    style: ResponsiveHelper.smallStyle(ctx,
                        color: AppColors.grey600),
                  ),
                  const SizedBox(height: 12),
                  if (currentWork != null)
                    _tile(
                      ctx,
                      work: currentWork,
                      headline: '지금 지원한 업무',
                      confirmedCount: confirmedCountOf(currentWork),
                      muted: true,
                      onTap: null,
                    ),
                  const SizedBox(height: 12),
                  Text(
                    '제안할 업무 선택',
                    style: ResponsiveHelper.bodyStyle(ctx)
                        .copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  ...candidates.map((w) {
                    final selected = sel?.id == w.id;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: selected
                                ? AppColors.brand
                                : Colors.transparent,
                            width: 2,
                          ),
                        ),
                        child: _tile(
                          ctx,
                          work: w,
                          headline: null,
                          confirmedCount: confirmedCountOf(w),
                          muted: false,
                          onTap: () => setSheetState(() => picked = w),
                        ),
                      ),
                    );
                  }),
                  if (sel != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      '급여 조건',
                      style: ResponsiveHelper.bodyStyle(ctx)
                          .copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    _optionRow(
                      ctx,
                      label: '공고 기본 급여',
                      amount: sel.formattedWage,
                      value: optionTargetBase,
                      groupValue: option,
                      enabled: true,
                      onChanged: (v) => setSheetState(() => option = v),
                    ),
                    _optionRow(
                      ctx,
                      label: '기존 지원 급여 유지',
                      amount: FormatHelper.formatWage(sourceWage),
                      value: optionMatchSourceWage,
                      groupValue: option,
                      enabled: matchEnabled,
                      disabledReason: !canManageWage
                          ? '개별 급여 제안 권한이 필요합니다.'
                          : (!sameType
                              ? '기존 지원은 ${_typeLabel(sourceWageType)}이고, '
                                  '제안할 업무는 ${_typeLabel(sel.wageType)}라 '
                                  '급여 기준을 그대로 승계할 수 없습니다.'
                              : null),
                      onChanged: (v) => setSheetState(() => option = v),
                    ),
                    if (option == optionMatchSourceWage) ...[
                      const SizedBox(height: 8),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppColors.infoBg,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '이 근로자에게만 적용되는 제안 급여입니다.\n'
                          '공고의 기본 급여는 변경되지 않습니다.',
                          style: ResponsiveHelper.smallStyle(ctx,
                              color: AppColors.infoDeep),
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.brand,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: () => Navigator.pop(
                            ctx, (wdId: sel.id, option: option)),
                        child: const Text('다음',
                            style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  static String _typeLabel(String? wageType) => wageType == 'daily'
      ? '일급제'
      : (wageType == 'hourly' ? '시급제' : '다른 급여 기준');

  /// 급여 조건 한 줄. 고를 수 없으면 **숨기지 않고** 이유를 적는다.
  static Widget _optionRow(
    BuildContext ctx, {
    required String label,
    required String amount,
    required String value,
    required String groupValue,
    required bool enabled,
    required ValueChanged<String> onChanged,
    String? disabledReason,
  }) {
    final fg = enabled ? AppColors.grey800 : AppColors.grey400;
    return Opacity(
      opacity: enabled ? 1 : 0.7,
      child: InkWell(
        onTap: enabled ? () => onChanged(value) : null,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                groupValue == value
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                size: ResponsiveHelper.iconSize(ctx, 20),
                color: enabled
                    ? (groupValue == value
                        ? AppColors.brand
                        : AppColors.grey400)
                    : AppColors.grey300,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(label,
                              style:
                                  ResponsiveHelper.bodyStyle(ctx, color: fg)),
                        ),
                        Text(
                          amount,
                          style: ResponsiveHelper.bodyStyle(ctx, color: fg)
                              .copyWith(fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    if (!enabled && disabledReason != null) ...[
                      const SizedBox(height: 2),
                      Text(disabledReason,
                          style: ResponsiveHelper.smallStyle(ctx,
                              color: AppColors.grey500)),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 확인 → CF 호출. 보냈으면 true.
  ///
  /// 확인 문구는 바꾸는 것이 아니라 **보내는** 것이다. 수락 전에는 아무것도
  /// 확정되지 않고 기존 지원도 그대로라는 사실을 여기서 말한다.
  static Future<bool> confirmAndSend(
    BuildContext context, {
    required String workerName,
    required String sourceApplicationId,
    required WorkDetailModel target,
    required String option,
    required int sourceWage,
  }) async {
    final isMatch = option == optionMatchSourceWage;
    final offeredText =
        isMatch ? FormatHelper.formatWage(sourceWage) : target.formattedWage;
    final ok = await DialogHelper.showConfirm(
      context,
      title: '업무 제안 보내기',
      message: '$workerName님에게 ‘${target.workType}’ 업무를 제안합니다.\n'
          '${target.startTime}~${target.endTime} · $offeredText'
          '${isMatch ? ' (기존 지원 급여 유지)' : ''}\n\n'
          '${isMatch ? '이 급여는 이 근로자에게만 적용되며 공고의 기본 급여는 변경되지 않습니다.\n\n' : ''}'
          '근로자가 수락하면 그때 이 업무로 확정되고, 기존 지원은 자동으로 '
          '정리됩니다. 거절하면 기존 지원은 대기 상태 그대로입니다.',
      confirmText: '제안 보내기',
      cancelText: '취소',
    );
    if (ok != true || !context.mounted) return false;

    try {
      final callable = FirebaseFunctions.instanceFor(region: 'asia-northeast3')
          .httpsCallable('callableOfferAlternativeWork');
      await callable.call({
        'sourceApplicationId': sourceApplicationId,
        'targetWdId': target.id,
        // 금액은 보내지 않는다 — 옵션만 보내고 값은 서버가 문서에서 읽는다.
        'compensationOption': option,
      });
      ToastHelper.showSuccess('$workerName님에게 업무 제안을 보냈습니다.');
      return true;
    } on FirebaseFunctionsException catch (e) {
      ToastHelper.showError(e.message ?? '제안을 보내지 못했습니다.');
      return false;
    } catch (_) {
      ToastHelper.showError('제안을 보내지 못했습니다.');
      return false;
    }
  }


  /// 업무 한 칸 — A와 B를 같은 축(시간 · 기본임금 · 휴게 · 남은 자리)으로 본다.
  ///
  /// 남은 자리는 `requiredCount`가 있을 때만 말한다. 정원을 모르면 숫자를
  /// 지어내지 않고 그 줄을 생략한다 — 모름을 0으로 쓰지 않는다.
  static Widget _tile(
    BuildContext ctx, {
    required WorkDetailModel work,
    required String? headline,
    required int confirmedCount,
    required bool muted,
    required VoidCallback? onTap,
  }) {
    final remain =
        work.requiredCount > 0 ? work.requiredCount - confirmedCount : null;
    final fg = muted ? AppColors.grey600 : AppColors.grey800;
    return Material(
      color: muted ? AppColors.grey100 : Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            border:
                Border.all(color: muted ? AppColors.grey200 : AppColors.border),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              WorkTypeIcon.buildWithBackground(
                iconString: work.workTypeIcon,
                backgroundColor: work.workTypeBackgroundColor,
                size: ResponsiveHelper.iconSize(ctx, 18),
                containerSize: ResponsiveHelper.spacing(ctx, 32),
              ),
              SizedBox(width: ResponsiveHelper.spacing(ctx, 10)),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (headline != null)
                      Text(
                        headline,
                        style: ResponsiveHelper.tinyStyle(ctx,
                            color: AppColors.grey500),
                      ),
                    Text(
                      work.workType,
                      style: ResponsiveHelper.bodyStyle(ctx, color: fg)
                          .copyWith(fontWeight: FontWeight.w600),
                    ),
                    Text(
                      '${work.startTime}~${work.endTime} · ${work.formattedWage}',
                      style: ResponsiveHelper.smallStyle(ctx,
                          color: AppColors.grey600),
                    ),
                    Text(
                      [
                        '휴게 ${work.breakMinutes}분',
                        if (remain != null) '남은 자리 $remain명',
                      ].join(' · '),
                      style: ResponsiveHelper.tinyStyle(ctx,
                          color: AppColors.grey500),
                    ),
                  ],
                ),
              ),
              if (onTap != null)
                Icon(Icons.arrow_forward_ios,
                    size: ResponsiveHelper.iconSize(ctx, 12),
                    color: AppColors.grey300),
            ],
          ),
        ),
      ),
    );
  }
}
