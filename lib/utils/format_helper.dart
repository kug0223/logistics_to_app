import 'package:flutter/material.dart';

/// 포맷팅 및 파싱 유틸리티 클래스
class FormatHelper {
  // ============================================================
  // 색상 관련
  // ============================================================
  
  /// HEX 색상 문자열을 Color 객체로 변환
  /// 
  /// 예시:
  /// - parseColor('#2196F3') → Color(0xFF2196F3)
  /// - parseColor(null) → Colors.blue (기본값)
  static Color parseColor(String? colorString, {Color defaultColor = Colors.blue}) {
    if (colorString == null || colorString.isEmpty) {
      return defaultColor;
    }
    
    try {
      // '#'로 시작하면 제거하고 '0xFF' 추가
      final hex = colorString.replaceFirst('#', '');
      return Color(int.parse('FF$hex', radix: 16));
    } catch (e) {
      return defaultColor;
    }
  }

  // ============================================================
  // 시간 관련
  // ============================================================
  
  /// 00:00 ~ 23:30까지 30분 단위 시간 리스트 생성
  /// 
  /// 반환 예시: ['00:00', '00:30', '01:00', ..., '23:00', '23:30']
  static List<String> generateTimeList() {
    final times = <String>[];
    for (int hour = 0; hour < 24; hour++) {
      for (int minute = 0; minute < 60; minute += 30) {
        times.add(
          '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}',
        );
      }
    }
    return times;
  }

  /// 시간 문자열 비교 (HH:mm 형식)
  /// 
  /// 반환값:
  /// - 음수: time1이 time2보다 이전
  /// - 0: 같은 시간
  /// - 양수: time1이 time2보다 이후
  static int compareTime(String time1, String time2) {
    try {
      final parts1 = time1.split(':');
      final parts2 = time2.split(':');
      
      final hour1 = int.parse(parts1[0]);
      final minute1 = int.parse(parts1[1]);
      final hour2 = int.parse(parts2[0]);
      final minute2 = int.parse(parts2[1]);
      
      if (hour1 != hour2) return hour1 - hour2;
      return minute1 - minute2;
    } catch (e) {
      return 0;
    }
  }

  // ============================================================
  // 금액 관련
  // ============================================================
  
  /// 금액을 천단위 콤마 형식으로 포맷팅
  /// 
  /// 예시:
  /// - formatWage(10000) → '10,000원'
  /// - formatWage(1500000) → '1,500,000원'
  static String formatWage(int wage) {
    return '${wage.toString().replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (Match m) => '${m[1]},',
    )}원';
  }

  /// 금액을 천단위 콤마 형식으로 포맷팅 (단위 없이)
  /// 
  /// 예시:
  /// - formatNumber(10000) → '10,000'
  /// - formatNumber(1500000) → '1,500,000'
  static String formatNumber(int number) {
    return number.toString().replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (Match m) => '${m[1]},',
    );
  }

  // ============================================================
  // Material 아이콘 관련
  // ============================================================
  
  /// Material 아이콘 문자열을 IconData로 변환
  /// 
  /// 지원 형식:
  /// - 'material:58718' → IconData(58718)
  /// - 'work' → Icons.work
  static IconData parseIcon(String iconString, {IconData defaultIcon = Icons.work}) {
    // material:codePoint 형식
    if (iconString.startsWith('material:')) {
      try {
        final codePoint = int.parse(iconString.substring(9));
        return IconData(codePoint, fontFamily: 'MaterialIcons');
      } catch (e) {
        return defaultIcon;
      }
    }

    // 아이콘 이름 매핑
    const iconMap = {
      'work': Icons.work,
      'work_outline': Icons.work_outline,
      'business': Icons.business,
      'local_shipping': Icons.local_shipping,
      'inventory': Icons.inventory,
      'category': Icons.category,
      'warehouse': Icons.warehouse,
      'factory': Icons.factory,
      'construction': Icons.construction,
      'handyman': Icons.handyman,
      'build': Icons.build,
      'cleaning_services': Icons.cleaning_services,
      'assignment': Icons.assignment,
      'description': Icons.description,
    };

    return iconMap[iconString.toLowerCase()] ?? defaultIcon;
  }

  // ============================================================
  // 이모지 관련
  // ============================================================
  
  /// 문자열이 이모지인지 확인
  static bool isEmoji(String text) {
    if (text.isEmpty) return false;
    
    final firstChar = text.runes.first;
    
    // 이모지 유니코드 범위
    return (firstChar >= 0x1F300 && firstChar <= 0x1F9FF) || // 기타 심볼
           (firstChar >= 0x2600 && firstChar <= 0x26FF) ||   // 기타 심볼
           (firstChar >= 0x2700 && firstChar <= 0x27BF) ||   // Dingbats
           (firstChar >= 0xFE00 && firstChar <= 0xFE0F) ||   // Variation Selectors
           (firstChar >= 0x1F600 && firstChar <= 0x1F64F) || // 이모티콘
           (firstChar >= 0x1F680 && firstChar <= 0x1F6FF) || // 교통/지도 심볼
           (firstChar >= 0x1F900 && firstChar <= 0x1F9FF);   // 보조 심볼
  }
}