import 'package:flutter/material.dart';
import '../../models/core/insurance_rate_model.dart';
import '../../theme/app_colors.dart';
import '../../utils/responsive_helper.dart';

/// 세금 공제 타입 배지 위젯
///
/// - [TaxDeductionBadge.chip]: 배경색이 있는 칩 스타일 (공고 화면 등)
/// - [TaxDeductionBadge.row]: 아이콘+텍스트만 인라인 스타일 (리스트 행 등)
///
/// taxDeductionType == [InsuranceRateModel.typeNone]이면 [SizedBox.shrink] 반환.
class TaxDeductionBadge extends StatelessWidget {
  final String taxDeductionType;
  final _TaxBadgeStyle _style;

  const TaxDeductionBadge.chip({
    super.key,
    required this.taxDeductionType,
  }) : _style = _TaxBadgeStyle.chip;

  const TaxDeductionBadge.row({
    super.key,
    required this.taxDeductionType,
  }) : _style = _TaxBadgeStyle.row;

  /// 공제 타입에 대응하는 Color (외부에서 색상만 필요할 때 사용)
  static Color colorFor(String type) {
    switch (type) {
      case InsuranceRateModel.typeFreelancer33:       return AppColors.grey700;
      case InsuranceRateModel.typeDailyWorker:        return AppColors.infoDark;
      case InsuranceRateModel.typeDailyAuto8:         return AppColors.warningDeep;
      case InsuranceRateModel.typeFourInsuranceFixed: return AppColors.purpleDark;
      default:                                        return AppColors.grey500;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (taxDeductionType == InsuranceRateModel.typeNone) {
      return const SizedBox.shrink();
    }

    final color = colorFor(taxDeductionType);
    final label = InsuranceRateModel.typeLabel(taxDeductionType);

    final iconSize = _style == _TaxBadgeStyle.chip
        ? ResponsiveHelper.iconSize(context, 11)
        : ResponsiveHelper.iconSize(context, 12);
    final gap = _style == _TaxBadgeStyle.chip
        ? ResponsiveHelper.spacing(context, 3)
        : ResponsiveHelper.spacing(context, 4);
    final textStyle = (_style == _TaxBadgeStyle.chip
            ? ResponsiveHelper.captionStyle(context)
            : ResponsiveHelper.smallStyle(context))
        .copyWith(color: color, fontWeight: FontWeight.w600);

    final content = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.receipt_long_outlined, size: iconSize, color: color),
        SizedBox(width: gap),
        Text(label, style: textStyle),
      ],
    );

    if (_style == _TaxBadgeStyle.chip) {
      return Container(
        padding: EdgeInsets.symmetric(
          horizontal: ResponsiveHelper.spacing(context, 8),
          vertical: ResponsiveHelper.spacing(context, 2),
        ),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(6),
        ),
        child: content,
      );
    }

    return content;
  }
}

enum _TaxBadgeStyle { chip, row }
