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

  /// 제안할 업무를 고르게 한다. 고르지 않으면 null.
  static Future<String?> pickTarget(
    BuildContext context, {
    required String workerName,
    required WorkDetailModel? currentWork,
    required List<WorkDetailModel> candidates,
    required int Function(WorkDetailModel) confirmedCountOf,
  }) {
    return DialogHelper.showSheet<String>(
      context,
      isScrollControlled: true,
      builder: (sheetCtx) => SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$workerName님에게 다른 업무 제안',
                style: ResponsiveHelper.subtitleStyle(sheetCtx)
                    .copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              Text(
                '제안을 보내면 근로자가 조건을 보고 직접 선택합니다.\n'
                '지금 지원은 그대로 유지되고, 근로자가 제안을 수락할 때만 정리됩니다.',
                style: ResponsiveHelper.smallStyle(sheetCtx,
                    color: AppColors.grey600),
              ),
              const SizedBox(height: 12),
              if (currentWork != null)
                _tile(
                  sheetCtx,
                  work: currentWork,
                  headline: '지금 지원한 업무',
                  confirmedCount: confirmedCountOf(currentWork),
                  muted: true,
                  onTap: null,
                ),
              const SizedBox(height: 12),
              Text(
                '제안할 업무 선택',
                style: ResponsiveHelper.bodyStyle(sheetCtx)
                    .copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              ...candidates.map((w) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _tile(
                      sheetCtx,
                      work: w,
                      headline: null,
                      confirmedCount: confirmedCountOf(w),
                      muted: false,
                      onTap: () => Navigator.pop(sheetCtx, w.id),
                    ),
                  )),
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
  }) async {
    final ok = await DialogHelper.showConfirm(
      context,
      title: '업무 제안 보내기',
      message: '$workerName님에게 ‘${target.workType}’ 업무를 제안합니다.\n'
          '${target.startTime}~${target.endTime} · ${target.formattedWage}\n\n'
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
        // [R5.3B PART F] Core v1은 제안 업무의 기본 조건으로만 제안한다.
        //   원 지원의 임금을 그대로 옮기면 아무도 작성하지 않은
        //   (wage, baseHourlyWage, wageType) 조합이 만들어진다.
        'compensationOption': 'TARGET_BASE',
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
