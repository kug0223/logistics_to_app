import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
  /// DateTime을 날짜+시간 형식으로 포맷팅
  /// 
  /// 예시:
  /// - formatDateTime(DateTime(2024, 11, 27, 18, 30)) → '11/27 18:30'
  static String formatDateTime(DateTime dateTime) {
    return '${dateTime.month}/${dateTime.day} '
           '${dateTime.hour.toString().padLeft(2, '0')}:'
           '${dateTime.minute.toString().padLeft(2, '0')}';
  }

  /// DateTime을 날짜만 포맷팅 (요일 포함)
  /// 
  /// 예시:
  /// - formatDate(DateTime(2024, 11, 27)) → '11/27 (수)'
  static String formatDate(DateTime date) {
    final weekdays = ['월', '화', '수', '목', '금', '토', '일'];
    final weekday = weekdays[date.weekday - 1];
    return '${date.month}/${date.day} ($weekday)';
  }

  /// DateTime을 날짜만 포맷팅 (요일 없이)
  /// 
  /// 예시:
  /// - formatDateShort(DateTime(2024, 11, 27)) → '11/27'
  static String formatDateShort(DateTime date) {
    return '${date.month}/${date.day}';
  }

  /// DateTime을 시간만 포맷팅
  /// 
  /// 예시:
  /// - formatTime(DateTime(2024, 11, 27, 18, 30)) → '18:30'
  static String formatTime(DateTime dateTime) {
    return '${dateTime.hour.toString().padLeft(2, '0')}:'
           '${dateTime.minute.toString().padLeft(2, '0')}';
  }

  /// 날짜 범위 포맷팅
  /// 
  /// 예시:
  /// - formatDateRange(start, end) → '11/1 ~ 11/30'
  static String formatDateRange(DateTime start, DateTime end) {
    return '${start.month}/${start.day} ~ ${end.month}/${end.day}';
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
  // ============================================================
  // 전화번호 포맷팅
  // ============================================================
  
  /// 전화번호 포맷팅 (010-1234-5678)
  /// 
  /// 예시:
  /// - formatPhone('01012345678') → '010-1234-5678'
  /// - formatPhone('0212345678') → '02-1234-5678'
  static String formatPhone(String phone) {
    final numbers = phone.replaceAll(RegExp(r'[^0-9]'), '');
    
    if (numbers.length == 11) {
      // 010-1234-5678 (11자리)
      return '${numbers.substring(0, 3)}-${numbers.substring(3, 7)}-${numbers.substring(7)}';
    } else if (numbers.length == 10) {
      // 010-123-4567 또는 02-1234-5678
      if (numbers.startsWith('02')) {
        return '${numbers.substring(0, 2)}-${numbers.substring(2, 6)}-${numbers.substring(6)}';
      }
      return '${numbers.substring(0, 3)}-${numbers.substring(3, 6)}-${numbers.substring(6)}';
    } else if (numbers.length == 9) {
      // 02-123-4567 (서울 지역번호)
      return '${numbers.substring(0, 2)}-${numbers.substring(2, 5)}-${numbers.substring(5)}';
    }
    
    return phone;
  }
  // ============================================================
  // 사업자번호 포맷팅
  // ============================================================
  
  /// 사업자등록번호 포맷팅 (000-00-00000)
  /// 
  /// 예시:
  /// - formatBusinessNumber('1234567890') → '123-45-67890'
  static String formatBusinessNumber(String number) {
    final cleaned = number.replaceAll('-', '');
    
    if (cleaned.length >= 10) {
      return '${cleaned.substring(0, 3)}-${cleaned.substring(3, 5)}-${cleaned.substring(5, 10)}';
    } else if (cleaned.length >= 5) {
      return '${cleaned.substring(0, 3)}-${cleaned.substring(3, 5)}-${cleaned.substring(5)}';
    } else if (cleaned.length >= 3) {
      return '${cleaned.substring(0, 3)}-${cleaned.substring(3)}';
    }
    
    return cleaned;
  }
  
}
  
// ============================================================
// TextInputFormatter 클래스들
// ============================================================

/// 사업자등록번호 입력 포맷터 (자동 하이픈)
class BusinessNumberFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final text = newValue.text.replaceAll('-', '');
    
    if (text.length > 10) {
      return oldValue;
    }
    
    final formatted = FormatHelper.formatBusinessNumber(text);
    
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

/// 전화번호 입력 포맷터 (자동 하이픈)
class PhoneNumberFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final text = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    
    if (text.length > 11) {
      return oldValue;
    }
    
    final formatted = FormatHelper.formatPhone(text);
    
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
  
}
/// 천단위 콤마 입력 포맷터
class NumberInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    // 빈 값 허용
    if (newValue.text.isEmpty) {
      return newValue;
    }
    
    // 콤마 제거 후 숫자만 추출
    final cleanText = newValue.text.replaceAll(',', '');
    final number = int.tryParse(cleanText);
    
    if (number == null) {
      return oldValue;
    }
    
    final formatted = FormatHelper.formatNumber(number);
    
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}