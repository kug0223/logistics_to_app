// lib/theme/app_text_styles.dart
//
// ALfit 지원자 화면 Typography 시스템
//
// 사용법:
//   Text('언제 일하고 싶으세요?', style: AppTextStyles.heroTitle(s: s))
//   Text('8월 12일 일자리', style: AppTextStyles.sectionTitle(s: s))
//   Text('3개 모두보기 ›', style: AppTextStyles.sectionAction(s: s))
//
// 모든 메서드는 `s` 파라미터로 ResponsiveHelper 스케일 적용 가능.
// s 기본값은 1.0이므로 스케일 불필요한 context에서도 그대로 사용 가능.

import 'package:flutter/material.dart';

import 'app_colors.dart';

class AppTextStyles {
  AppTextStyles._();

  // ══════════════════════════════════════════════════════════
  // Hero — "언제 일하고 싶으세요?" 수준의 가장 큰 제목
  // ══════════════════════════════════════════════════════════

  /// 히어로 타이틀 — 24sp, w700, textPrimary
  static TextStyle heroTitle() => TextStyle(
        fontSize: 24,
        fontWeight: FontWeight.w700,
        color: AppColors.textPrimary,
        letterSpacing: -0.5,
        height: 1.2,
      );

  /// 히어로 설명 — 15sp, w400, textSecondary
  static TextStyle heroDescription() => TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w400,
        color: AppColors.textSecondary,
        height: 1.4,
      );

  // ══════════════════════════════════════════════════════════
  // Section — 홈 섹션 헤더
  // ══════════════════════════════════════════════════════════

  /// 섹션 제목 — 20sp, w700, textPrimary
  /// 예: "8월 12일 일자리", "지원 현황", "이번 주 일정", "수입 현황", "나의 ALfit"
  static TextStyle sectionTitle() => TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w700,
        color: AppColors.textPrimary,
        letterSpacing: -0.3,
        height: 1.2,
      );

  /// 섹션 부제목 — 13sp, w400, textTertiary
  /// 예: "오산시 주변"
  static TextStyle sectionSubtitle() => TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w400,
        color: AppColors.textTertiary,
      );

  /// 섹션 액션 링크 — 15sp, w600, brand (#1565C0)
  /// 예: "3개 모두보기 ›", "전체보기 ›", "일정 ›", "2026년 8월 ›"
  static TextStyle sectionAction() => TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w600,
        color: AppColors.brand,
      );

  // ══════════════════════════════════════════════════════════
  // Job Card — 공고 카드 텍스트 위계
  // ══════════════════════════════════════════════════════════

  /// 공고 제목 — 17sp, w700, textPrimary (maxLines: 1)
  static TextStyle jobTitle() => TextStyle(
        fontSize: 17,
        fontWeight: FontWeight.w700,
        color: AppColors.textPrimary,
        overflow: TextOverflow.ellipsis,
      );

  /// 사업장명 — 14sp, w500, textSecondary
  static TextStyle businessName() => TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w500,
        color: AppColors.textSecondary,
      );

  /// 메타 정보 (날짜, 지역, 시간 등) — 14sp, w400, textSecondary
  static TextStyle jobMeta() => TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w400,
        color: AppColors.textSecondary,
      );

  /// 급여 — 18sp, w700, brand (#1565C0)
  static TextStyle pay() => TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w700,
        color: AppColors.brand,
        letterSpacing: -0.5,
      );

  /// 상태 배지 텍스트 — 12sp, w600
  static TextStyle statusBadge({Color? color}) => TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: color ?? AppColors.textSecondary,
      );

  // ══════════════════════════════════════════════════════════
  // General — 범용 텍스트 레벨
  // ══════════════════════════════════════════════════════════

  /// 본문 — 15sp, w400, textSecondary
  static TextStyle body({Color? color}) => TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w400,
        color: color ?? AppColors.textSecondary,
        height: 1.5,
      );

  /// 메타/부가정보 — 14sp, w400, textSecondary
  static TextStyle meta({Color? color}) => TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w400,
        color: color ?? AppColors.textSecondary,
      );

  /// 캡션 — 12sp, w500, textTertiary
  static TextStyle caption({Color? color}) => TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        color: color ?? AppColors.textTertiary,
      );

  /// 통계 숫자 — 20sp, w800, textPrimary (또는 상태색)
  static TextStyle statNumber({Color? color}) => TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w800,
        color: color ?? AppColors.textPrimary,
        letterSpacing: -0.5,
      );

  /// 통계 라벨 — 12sp, w500, textTertiary
  static TextStyle statLabel() => TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        color: AppColors.textTertiary,
      );
}
