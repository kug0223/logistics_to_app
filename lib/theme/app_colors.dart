// lib/theme/app_colors.dart

import 'package:flutter/material.dart';

/// ALfit 앱 공통 색상 시스템
/// 
/// 사용법:
/// ```dart
/// import '../../theme/app_colors.dart';
/// 
/// Container(
///   color: AppColors.successBg,
///   child: Text('확정', style: TextStyle(color: AppColors.successDark)),
/// )
/// ```
/// 
/// 참고: 역할별 색상은 RoleTheme 또는 Theme.of(context).primaryColor 사용
class AppColors {
  AppColors._(); // 인스턴스화 방지
  
  // ═══════════════════════════════════════════════════════════
  // 🟢 성공 (확정, 승인, 완료, 출근)
  // ═══════════════════════════════════════════════════════════
  
  /// 성공 배경색 (연한 초록)
  static const Color successBg = Color(0xFFE8F5E9);      // green[50]
  
  /// 성공 연한색 (보조 배경)
  static const Color successLight = Color(0xFFA5D6A7);   // green[200]
  
  /// 성공 기본색
  static const Color success = Color(0xFF4CAF50);        // green
  
  /// 성공 진한색 (텍스트, 아이콘)
  static const Color successDark = Color(0xFF388E3C);    // green[700]
  
  // ═══════════════════════════════════════════════════════════
  // 🟠 경고 (대기, 주의, 예약)
  // ═══════════════════════════════════════════════════════════
  
  /// 경고 배경색 (연한 주황)
  static const Color warningBg = Color(0xFFFFF3E0);      // orange[50]
  
  /// 경고 연한색 (보조 배경)
  static const Color warningLight = Color(0xFFFFCC80);   // orange[200]
  
  /// 경고 기본색
  static const Color warning = Color(0xFFFF9800);        // orange
  
  /// 경고 진한색 (텍스트, 아이콘)
  static const Color warningDark = Color(0xFFF57C00);    // orange[700]
  
  // ═══════════════════════════════════════════════════════════
  // 🔴 에러 (거절, 실패, 삭제)
  // ═══════════════════════════════════════════════════════════
  
  /// 에러 배경색 (연한 빨강)
  static const Color errorBg = Color(0xFFFFEBEE);        // red[50]
  
  /// 에러 연한색 (보조 배경)
  static const Color errorLight = Color(0xFFEF9A9A);     // red[200]
  
  /// 에러 기본색
  static const Color error = Color(0xFFF44336);          // red
  
  /// 에러 진한색 (텍스트, 아이콘)
  static const Color errorDark = Color(0xFFD32F2F);      // red[700]
  
  // ═══════════════════════════════════════════════════════════
  // 🔵 정보 (일반 정보, 단기 근무)
  // ═══════════════════════════════════════════════════════════
  
  /// 정보 배경색 (연한 파랑)
  static const Color infoBg = Color(0xFFE3F2FD);         // blue[50]
  
  /// 정보 연한색 (보조 배경)
  static const Color infoLight = Color(0xFF90CAF9);      // blue[200]
  
  /// 정보 기본색
  static const Color info = Color(0xFF2196F3);           // blue
  
  /// 정보 진한색 (텍스트, 아이콘)
  static const Color infoDark = Color(0xFF1976D2);       // blue[700]
  
  // ═══════════════════════════════════════════════════════════
  // 🟣 보라 (장기 근무, 특수)
  // ═══════════════════════════════════════════════════════════
  
  /// 보라 배경색 (연한 보라)
  static const Color purpleBg = Color(0xFFF3E5F5);       // purple[50]
  
  /// 보라 연한색 (보조 배경)
  static const Color purpleLight = Color(0xFFCE93D8);    // purple[200]
  
  /// 보라 기본색
  static const Color purple = Color(0xFF9C27B0);         // purple
  
  /// 보라 진한색 (텍스트, 아이콘)
  static const Color purpleDark = Color(0xFF7B1FA2);     // purple[700]
  
  // ═══════════════════════════════════════════════════════════
  // ⚫ 중립 (회색 계열)
  // ═══════════════════════════════════════════════════════════
  
  /// 가장 연한 회색 (배경)
  static const Color grey50 = Color(0xFFFAFAFA);         // grey[50]
  
  /// 연한 회색 (카드 배경, 비활성)
  static const Color grey100 = Color(0xFFF5F5F5);        // grey[100]
  
  /// 테두리용 회색
  static const Color grey200 = Color(0xFFEEEEEE);        // grey[200]
  
  /// 기본 테두리
  static const Color grey300 = Color(0xFFE0E0E0);        // grey[300]
  
  /// 비활성 아이콘, 힌트
  static const Color grey400 = Color(0xFFBDBDBD);        // grey[400]
  
  /// 보조 텍스트
  static const Color grey500 = Color(0xFF9E9E9E);        // grey[500]
  
  /// 본문 보조 텍스트
  static const Color grey600 = Color(0xFF757575);        // grey[600]
  
  /// 활성 아이콘, 라벨
  static const Color grey700 = Color(0xFF616161);        // grey[700]
  
  /// 강조 텍스트
  static const Color grey800 = Color(0xFF424242);        // grey[800]
  
  /// 기본 텍스트
  static const Color grey900 = Color(0xFF212121);        // grey[900]
  
  // ═══════════════════════════════════════════════════════════
  // 🏷️ 기능별 색상 (시맨틱)
  // ═══════════════════════════════════════════════════════════
  
  // --- 근무 유형 ---
  
  /// 단기 근무 색상
  static const Color shortTerm = info;
  static const Color shortTermBg = infoBg;
  static const Color shortTermLight = infoLight;
  static const Color shortTermDark = infoDark;
  
  /// 장기 근무 색상
  static const Color longTerm = purple;
  static const Color longTermBg = purpleBg;
  static const Color longTermLight = purpleLight;
  static const Color longTermDark = purpleDark;
  
  // --- 지원 상태 ---
  
  /// 대기중
  static const Color pending = warning;
  static const Color pendingBg = warningBg;
  static const Color pendingDark = warningDark;
  
  /// 확정됨
  static const Color confirmed = success;
  static const Color confirmedBg = successBg;
  static const Color confirmedDark = successDark;
  
  /// 거절됨
  static const Color rejected = error;
  static const Color rejectedBg = errorBg;
  static const Color rejectedDark = errorDark;
  
  /// 취소됨 / 마감
  static const Color canceled = grey500;
  static const Color canceledBg = grey100;
  static const Color canceledDark = grey700;
  
  // --- 예약/스케줄 ---
  
  /// 예약 공개
  static const Color scheduled = warning;
  static const Color scheduledBg = warningBg;
  static const Color scheduledDark = warningDark;
  
  // --- 출근 상태 ---
  
  /// 출근 완료
  static const Color checkedIn = success;
  static const Color checkedInBg = successBg;
  
  /// 퇴근 완료
  static const Color checkedOut = purple;
  static const Color checkedOutBg = purpleBg;
  
  /// 미출근
  static const Color notCheckedIn = warning;
  static const Color notCheckedInBg = warningBg;
  
  // ═══════════════════════════════════════════════════════════
  // 🎨 공통 UI 색상
  // ═══════════════════════════════════════════════════════════
  
  // --- 테두리 ---
  
  /// 기본 테두리
  static const Color border = grey300;
  
  /// 연한 테두리
  static const Color borderLight = grey200;
  
  /// 포커스 테두리 (Theme.primaryColor 사용 권장)
  // static const Color borderFocus = info;
  
  // --- 배경 ---
  
  /// 화면 배경
  static const Color background = grey100;
  
  /// 표면 (카드, 다이얼로그)
  static const Color surface = Color(0xFFFFFFFF);
  
  /// 카드 배경
  static const Color cardBackground = Color(0xFFFFFFFF);
  
  /// 입력 필드 배경
  static const Color inputBackground = grey50;
  
  /// 비활성 배경
  static const Color disabledBackground = grey100;
  
  // --- 텍스트 ---
  
  /// 기본 텍스트 (제목, 본문)
  static const Color textPrimary = grey900;
  
  /// 보조 텍스트 (설명, 부제목)
  static const Color textSecondary = grey600;
  
  /// 힌트 텍스트 (placeholder)
  static const Color textHint = grey400;
  
  /// 비활성 텍스트
  static const Color textDisabled = grey500;
  
  /// 흰색 텍스트 (어두운 배경용)
  static const Color textOnDark = Color(0xFFFFFFFF);
  
  // --- 아이콘 ---
  
  /// 활성 아이콘
  static const Color iconActive = grey700;
  
  /// 비활성 아이콘
  static const Color iconInactive = grey400;
  
  /// 흰색 아이콘 (어두운 배경용)
  static const Color iconOnDark = Color(0xFFFFFFFF);
  
  // --- 구분선 ---
  
  /// 기본 구분선
  static const Color divider = grey300;
  
  /// 연한 구분선
  static const Color dividerLight = grey200;
  
  // ═══════════════════════════════════════════════════════════
  // 🎨 중간 단계 색상
  // ═══════════════════════════════════════════════════════════

  // --- 초록 중간 단계 ---
  static const Color successSoft    = Color(0xFF81C784);  // green[300]
  static const Color successFaded   = Color(0xFF66BB6A);  // green[400]
  static const Color successMedium  = Color(0xFF43A047);  // green[600]
  static const Color successDeep    = Color(0xFF1B5E20);  // green[900]

  // --- 파랑 중간 단계 ---
  static const Color infoExtraLight = Color(0xFFBBDEFB);  // blue[100]
  static const Color infoMedium     = Color(0xFF1E88E5);  // blue[600]
  static const Color infoDeep       = Color(0xFF0D47A1);  // blue[900]

  // --- 주황 중간 단계 ---
  static const Color warningExtraLight = Color(0xFFFFE0B2); // orange[100]
  static const Color warningSoft    = Color(0xFFFFB74D);  // orange[300]
  static const Color warningFaded   = Color(0xFFFFA726);  // orange[400]
  static const Color warningMedium  = Color(0xFFFB8C00);  // orange[600]
  static const Color warningDeep    = Color(0xFFEF6C00);  // orange[800]
  static const Color warningDarkest = Color(0xFFE65100);  // orange[900]

  // --- 빨강 중간 단계 ---
  static const Color errorFaded     = Color(0xFFEF5350);  // red[400]
  static const Color errorMedium    = Color(0xFFE53935);  // red[600]
  static const Color errorDeep      = Color(0xFFB71C1C);  // red[900]

  // --- 황금/노랑 ---
  static const Color amberDark      = Color(0xFFFFA000);  // amber[700]
  static const Color yellowDark     = Color(0xFFFBC02D);  // yellow[700]

  // ═══════════════════════════════════════════════════════════
  // 🛠️ 헬퍼 메서드
  // ═══════════════════════════════════════════════════════════
  
  /// 상태에 따른 배경색 반환
  static Color getStatusBackground(String status) {
    switch (status.toUpperCase()) {
      case 'PENDING':
        return pendingBg;
      case 'CONFIRMED':
        return confirmedBg;
      case 'REJECTED':
        return rejectedBg;
      case 'CANCELED':
      case 'CLOSED':
        return canceledBg;
      default:
        return grey100;
    }
  }
  
  /// 상태에 따른 텍스트/아이콘 색상 반환
  static Color getStatusColor(String status) {
    switch (status.toUpperCase()) {
      case 'PENDING':
        return pendingDark;
      case 'CONFIRMED':
        return confirmedDark;
      case 'REJECTED':
        return rejectedDark;
      case 'CANCELED':
      case 'CLOSED':
        return canceledDark;
      default:
        return grey700;
    }
  }
  
  /// 근무 유형에 따른 색상 반환
  static Color getJobTypeColor(String jobType) {
    switch (jobType.toLowerCase()) {
      case 'short':
      case 'short_term':
        return shortTermDark;
      case 'long':
      case 'long_term':
        return longTermDark;
      default:
        return infoDark;
    }
  }
  
  /// 근무 유형에 따른 배경색 반환
  static Color getJobTypeBackground(String jobType) {
    switch (jobType.toLowerCase()) {
      case 'short':
      case 'short_term':
        return shortTermBg;
      case 'long':
      case 'long_term':
        return longTermBg;
      default:
        return infoBg;
    }
  }
  
  /// 그라데이션 생성 헬퍼
  static LinearGradient getGradient(Color color, {double opacity = 0.1}) {
    return LinearGradient(
      colors: [
        color.withValues(alpha: opacity),
        color.withValues(alpha: opacity * 0.5),
      ],
    );
  }
  
  /// 성공 그라데이션
  static LinearGradient get successGradient => LinearGradient(
    colors: [successBg, successLight.withValues(alpha: 0.3)],
  );
  
  /// 경고 그라데이션
  static LinearGradient get warningGradient => LinearGradient(
    colors: [warningBg, warningLight.withValues(alpha: 0.3)],
  );
  
  /// 에러 그라데이션
  static LinearGradient get errorGradient => LinearGradient(
    colors: [errorBg, errorLight.withValues(alpha: 0.3)],
  );
  
  /// 정보 그라데이션
  static LinearGradient get infoGradient => LinearGradient(
    colors: [infoBg, infoLight.withValues(alpha: 0.3)],
  );
  
  /// 보라 그라데이션
  static LinearGradient get purpleGradient => LinearGradient(
    colors: [purpleBg, purpleLight.withValues(alpha: 0.3)],
  );
}