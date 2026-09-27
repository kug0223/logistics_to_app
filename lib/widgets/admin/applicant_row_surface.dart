import 'package:flutter/material.dart';

import '../../utils/responsive_helper.dart';

/// [R7-P1-2 DEVICE.1H.1] 지원자/근무자 한 행의 **표면**.
///
///   DEVICE.1H 는 확정 카드의 전체 tint 를 테두리로 낮췄지만, 그 변경을 실제로
///   그려 본 적이 없었다 — 카드 builder 가 Firebase 의존 State 안의 private
///   메서드였기 때문이다. 정직한 한계 설명이었을 뿐 요구 완료는 아니었다.
///
///   그래서 **표면만** 떼어 낸다. 도메인은 그대로 다이얼로그에 남는다.
///
///     여기 있는 것   margin · radius · 배경 · 테두리 · 탭 영역
///     여기 없는 것   권한 판정 · capacity · 상태 분류 · 어떤 색을 쓸지
///
///   색을 이 위젯이 정하지 않는 이유: 두 화면의 강조 규칙이 실제로 다르다.
///   업무 명단은 알림 딥링크 대상을 파랗게 강조하고 선택색 alpha 도 다르다.
///   그것을 하나로 합치면 한쪽 화면의 모양이 바뀐다 — 이번 범위가 아니다.
///   **caller 가 자기 규칙으로 계산한 색을 넘긴다.**
class ApplicantRowSurface extends StatelessWidget {
  /// 카드 배경.
  final Color background;

  /// 카드 테두리 색.
  final Color border;

  /// 테두리 두께. 선택 상태에서만 굵어지는 화면이 있다.
  final double borderWidth;

  /// 행 내용. 이름·배지·행동 줄은 caller 가 만든다.
  final Widget child;

  /// 행 전체 탭. null 이면 탭 영역을 만들지 않는다.
  final VoidCallback? onTap;

  /// 내부 여백. 두 화면이 다른 값을 쓰므로 caller 가 정한다.
  final EdgeInsetsGeometry? padding;

  const ApplicantRowSurface({
    super.key,
    required this.child,
    this.background = Colors.white,
    this.border = const Color(0xFFE0E0E0),
    this.borderWidth = 1.0,
    this.onTap,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    final radius =
        BorderRadius.circular(ResponsiveHelper.spacing(context, 10));
    final body = Padding(
      padding: padding ??
          EdgeInsets.symmetric(
            horizontal: ResponsiveHelper.spacing(context, 10),
            vertical: ResponsiveHelper.spacing(context, 8),
          ),
      child: child,
    );
    return Container(
      margin: EdgeInsets.only(bottom: ResponsiveHelper.spacing(context, 4)),
      decoration: BoxDecoration(
        color: background,
        borderRadius: radius,
        border: Border.all(color: border, width: borderWidth),
      ),
      child: onTap == null
          ? body
          : Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onTap,
                borderRadius: radius,
                child: body,
              ),
            ),
    );
  }
}

/// 강조 단계 → 색. **화면마다 규칙이 다르므로 각 화면의 함수를 따로 둔다.**
///
///   DEVICE.1H 가 바꾼 것은 `confirmed`(= `!isPending`) 한 줄이다.
///   전체 초록 tint 를 테두리로 낮췄다 — D0 의 반복 강조 축소 · 행당 강한
///   강조 제한 · 완료 정보 낮은 강조.
typedef ApplicantRowColors = ({Color background, Color border, double width});

/// 홈 일자별 현황(`DayApplicantsDialog`)의 규칙.
ApplicantRowColors dayApplicantRowColors({
  required bool isSelected,
  required bool isStarred,
  required bool isPending,
  required Color selectedBg,
  required Color selectedBorder,
  required Color starredBg,
  required Color starredBorder,
  required Color confirmedBorder,
  required Color plainBorder,
}) {
  if (isSelected) {
    return (background: selectedBg, border: selectedBorder, width: 1.5);
  }
  if (isStarred) {
    return (background: starredBg, border: starredBorder, width: 1.0);
  }
  if (!isPending) {
    // [DEVICE.1H] 배경 tint 없음 — 테두리만.
    return (background: Colors.white, border: confirmedBorder, width: 1.0);
  }
  return (background: Colors.white, border: plainBorder, width: 1.0);
}
