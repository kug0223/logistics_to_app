import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import '../../utils/format_helper.dart';
import '../../utils/responsive_helper.dart';

/// 텍스트 + 카운트 배지로 구성된 탭 라벨 공통 위젯
///
/// TabBar의 Tab(child: AppTabLabel(...)) 형태로 사용
/// count가 null이면 배지 없이 텍스트만 표시
class AppTabLabel extends StatelessWidget {
  final String label;

  /// null이면 배지 미표시
  final int? count;

  /// null이면 theme.primaryColor 사용
  final Color? badgeColor;

  /// true면 배지가 solid red로 강조 (예: 미완료 항목이 있을 때)
  final bool urgent;

  /// count 뒤에 붙는 접미사 (예: "+" — 더 많은 항목이 있음을 표시)
  final String countSuffix;

  const AppTabLabel({
    super.key,
    required this.label,
    this.count,
    this.badgeColor,
    this.urgent = false,
    this.countSuffix = '',
  });

  @override
  Widget build(BuildContext context) {
    if (count == null && !urgent) {
      return Text(label);
    }

    final effectiveColor = badgeColor ?? Theme.of(context).primaryColor;
    final displayCount = count ?? 0;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // [DEVICE-MISMATCH-FIX] 탭 라벨은 **잘리지 않는다**.
        //   예전에는 라벨과 배지를 둘 다 같은 flex 로 감싸, 탭 폭이 충분해도
        //   라벨이 남은 폭의 절반까지만 받았다(배지가 다 쓰지 않은 몫이 라벨로
        //   돌아오지 않는다). 그 위에 한 줄 + 말줄임이라 Pixel 5 실기에서
        //   `미…`·`확인…`·`처리…`로 탭 이름이 사라졌다.
        //   이제 배지는 자기 폭만 쓰고 라벨이 나머지를 모두 받는다. 그래도
        //   자리가 모자라면(작은 폭·큰 글자 배율) 줄여 숨기지 않고 줄을 바꾼다.
        Flexible(
          child: Text(label, softWrap: true, textAlign: TextAlign.center),
        ),
        SizedBox(width: ResponsiveHelper.spacing(context, 3)),
        AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: EdgeInsets.symmetric(
            horizontal: ResponsiveHelper.spacing(context, 3),
            vertical: ResponsiveHelper.spacing(context, 2),
          ),
          decoration: BoxDecoration(
            color: urgent
                ? AppColors.error
                : effectiveColor.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(10),
          ),
          // [UI-INTEGRATION.33] 대량 사업장 건수('8,230') — 천 단위 구분.
          child: Text(
            '${FormatHelper.formatNumber(displayCount)}$countSuffix',
            style: ResponsiveHelper.tinyStyle(
              context,
              color: urgent ? Colors.white : effectiveColor,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ],
    );
  }
}
