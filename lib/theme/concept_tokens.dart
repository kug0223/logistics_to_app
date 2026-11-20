// [CP01] Concept 01 대표 화면 토큰 — 표면(깊이)·글자 위계·간격.
//
// 정본: records/reports/DU_concept_precise_spec_audit_2026-11-11.md §5–§8.
// **opt-in 전용**이다. 이 파일을 부르는 곳만 바뀐다 — 기존 CommonWidgets·RoleTheme 의
// 평면 기본값(카드·테마)은 그대로다. 대표 화면(두 홈·일자리 상세)과 지정 부품만 쓴다.
// 크기는 OS 글자 배율(TextScaler)을 그대로 받는다 — 여기서 ResponsiveHelper.s 를 곱하지 않는다.
import 'package:flutter/material.dart';

import 'app_colors.dart';

/// 대표 표면. 같은 수준의 면은 한 겹 — 안쪽 항목에는 그림자를 다시 주지 않는다.
abstract final class ConceptSurface {
  /// 약한 그림자 1개(설계값: #8797B8 alpha .10, (0,2), blur 8, spread 0).
  static const List<BoxShadow> _shadow = [
    BoxShadow(
      color: AppColors.conceptShadow,
      offset: Offset(0, 2),
      blurRadius: 8,
      spreadRadius: 0,
    ),
  ];

  /// 관리자 오늘 근무·처리할 일·다가오는 7일의 최상위 그룹, 지원자 지원 현황 요약.
  static BoxDecoration raised() => BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.conceptCardBorder, width: 1),
        boxShadow: _shadow,
      );

  /// 지원자 오늘·새 확정 약속 카드.
  static BoxDecoration promise() => BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.conceptPromiseStart, AppColors.conceptPromiseEnd],
          stops: [0, 1],
        ),
        border: Border.all(color: AppColors.conceptCardBorder, width: 1),
        boxShadow: _shadow,
      );

  /// 일자리 상세의 출처가 확정된 개별 요율 강조(새 예상 총액 아님).
  static BoxDecoration value() => BoxDecoration(
        color: AppColors.brandSurface,
        borderRadius: BorderRadius.circular(16),
      );

  /// 처리할 일 숫자 알약.
  static BoxDecoration count() => BoxDecoration(
        color: AppColors.conceptCountBg,
        borderRadius: BorderRadius.circular(999),
      );

  /// 관리자 부족 요약 필 — `N명 추가 필요`(빨강 아님).
  static BoxDecoration staffingNeed() => BoxDecoration(
        color: AppColors.conceptStaffingNeedBg,
        borderRadius: BorderRadius.circular(8),
      );

  /// 지원자 확정 필.
  static BoxDecoration confirmed() => BoxDecoration(
        color: AppColors.conceptConfirmBg,
        borderRadius: BorderRadius.circular(8),
      );

  /// 일자리 상세 분류 필.
  static BoxDecoration category() => BoxDecoration(
        color: AppColors.conceptCategoryBg,
        borderRadius: BorderRadius.circular(8),
      );
}

/// 대표 화면 글자 위계(§8). 본문 글꼴은 번들 NotoSansKR(400/700)이다.
abstract final class ConceptText {
  static TextStyle _t(double size, FontWeight w, double h, double ls, Color c) =>
      TextStyle(fontSize: size, fontWeight: w, height: h, letterSpacing: ls, color: c);

  /// 홈 큰 머리 — '오늘도, 내 일정에 맞게' / '오늘 운영을 한눈에'.
  static TextStyle hero() => _t(24, FontWeight.w700, 1.3, -0.2, AppColors.textPrimary);
  static TextStyle section() => _t(20, FontWeight.w700, 1.3, -0.2, AppColors.textPrimary);
  static TextStyle promiseBusiness() => _t(20, FontWeight.w700, 1.3, 0, AppColors.textPrimary);

  /// 약속 큰 시간. 숫자 폭 고정을 지원하는 글꼴이면 쓰고, 아니면 모양을 바꾸지 않는다.
  static TextStyle promiseTime() => _t(28, FontWeight.w700, 1.2, -0.2, AppColors.textPrimary)
      .copyWith(fontFeatures: const [FontFeature.tabularFigures()]);
  static TextStyle adminWorkTime() => _t(20, FontWeight.w700, 1.25, 0, AppColors.textPrimary);
  static TextStyle adminStaffStrong() => _t(18, FontWeight.w700, 1.3, 0, AppColors.textPrimary);
  static TextStyle adminStaffRegular() => _t(18, FontWeight.w400, 1.3, 0, AppColors.textSecondary);
  static TextStyle detailBusiness() => _t(28, FontWeight.w700, 1.25, -0.2, AppColors.textPrimary);
  static TextStyle detailRate() => _t(30, FontWeight.w700, 1.2, -0.2, AppColors.brand);
  static TextStyle detailRateUnit() => _t(16, FontWeight.w700, 1.2, 0, AppColors.brand);
  static TextStyle body({Color color = AppColors.textPrimary}) => _t(16, FontWeight.w400, 1.45, 0, color);
  static TextStyle meta() => _t(14, FontWeight.w400, 1.4, 0, AppColors.textSecondary);
  static TextStyle infoLabel() => _t(14, FontWeight.w400, 1.4, 0, AppColors.textSecondary);
  static TextStyle infoValue() => _t(16, FontWeight.w400, 1.45, 0, AppColors.textPrimary);
  static TextStyle taskTitle() => _t(17, FontWeight.w700, 1.25, 0, AppColors.textPrimary);
  static TextStyle taskDescription() => _t(14, FontWeight.w400, 1.35, 0, AppColors.textSecondary);
  static TextStyle count() => _t(14, FontWeight.w700, 1.2, 0, AppColors.brand);
  static TextStyle pill(Color color) => _t(13, FontWeight.w700, 1.3, 0, color);
  static TextStyle button() => _t(16, FontWeight.w700, 1.3, 0, AppColors.surface);
}

/// 대표 화면 간격(§8 V8). 화면 폭 기준 값에 다시 s 를 곱하지 않는다.
abstract final class ConceptSpace {
  /// 화면 좌우 여백 — 폭 360 미만 16, 그 외 20.
  static double gutter(double screenWidth) => screenWidth < 360 ? 16 : 20;
  static const double headerToHero = 16;
  static const double heroToDate = 4;
  static const double dateToStrip = 16;
  static const double stripToSection = 24;
  static const double sectionTitleToCard = 12;
  static const double sectionGap = 24;
  static const double cardGap = 12;
  static const double cardPadding = 16;
  static const double promiseChipToBusiness = 12;
  static const double promiseBusinessToWork = 4;
  static const double promiseWorkToTime = 8;
  static const double promiseTimeToRate = 4;
  static const double infoGroupGap = 12;
  static const double infoToCta = 16;

  /// 주 CTA 최소 높이(ALfit 기준 52), 터치 최소 48.
  static const double primaryCtaMinHeight = 52;
  static const double minTouch = 48;
}
