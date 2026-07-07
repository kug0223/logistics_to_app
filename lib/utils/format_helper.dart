import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
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
  /// - parseColor(null) → AppColors.info (기본값)
  static Color parseColor(String? colorString, {Color defaultColor = AppColors.info}) {
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

  static const _weekdays = ['월', '화', '수', '목', '금', '토', '일'];

  /// 요일 한글 (월~일) — ['월','화','수','목','금','토','일'][date.weekday-1] 대체
  static String weekday(DateTime date) => _weekdays[date.weekday - 1];

  /// DateTime을 날짜만 포맷팅 (요일 포함)
  ///
  /// 예시:
  /// - formatDate(DateTime(2024, 11, 27)) → '11/27 (수)'
  static String formatDate(DateTime date) {
    return '${date.month}/${date.day} (${weekday(date)})';
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
  static String formatTime(DateTime dateTime) =>
      formatHourMinute(dateTime.hour, dateTime.minute);

  /// 시/분 정수를 'HH:mm' 형식으로 포맷팅
  /// 예시: formatHourMinute(9, 5) → '09:05'
  static String formatHourMinute(int hour, int minute) {
    return '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
  }

  /// DateTime을 초 포함 시간으로 포맷팅 (출퇴근 기록용)
  /// 예시: '18:30:45'
  static String formatTimeWithSeconds(DateTime dateTime) {
    return '${dateTime.hour.toString().padLeft(2, '0')}:'
           '${dateTime.minute.toString().padLeft(2, '0')}:'
           '${dateTime.second.toString().padLeft(2, '0')}';
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
    // 음수 입력 시 부호를 분리해 처리 — 정규식이 '-' 기호를 건너뛰어 콤마 포맷이 미적용되는 버그 방지
    final abs = wage.abs().toString().replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (Match m) => '${m[1]},',
    );
    return '${wage < 0 ? '-' : ''}$abs원';
  }

  /// 금액을 천단위 콤마 형식으로 포맷팅 (단위 없이)
  /// 
  /// 예시:
  /// - formatNumber(10000) → '10,000'
  /// - formatNumber(1500000) → '1,500,000'
  static String formatNumber(int number) {
    final abs = number.abs().toString().replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (Match m) => '${m[1]},',
    );
    return '${number < 0 ? '-' : ''}$abs';
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
  // ============================================================
  // 공고 카드용 포맷팅 (2024.12.04 추가)
  // ============================================================

  /// 날짜를 ISO 형식으로 포맷팅
  /// 예시: '2024-11-28'
  static String formatDateISO(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  /// 연월을 ISO 형식으로 포맷팅 (급여 문서 키 등에 사용)
  /// 예시: '2024-11'
  static String formatYearMonthISO(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}';

  /// 날짜를 점 구분 형식으로 포맷팅
  /// 예시: '2024.11.28'
  static String formatDateDot(DateTime date) =>
      '${date.year}.${date.month.toString().padLeft(2, '0')}.${date.day.toString().padLeft(2, '0')}';

  /// 날짜를 구분자 없는 숫자 형식으로 포맷팅 (파일명 등에 사용)
  /// 예시: '20241128'
  static String formatDateStamp(DateTime date) =>
      '${date.year}${date.month.toString().padLeft(2, '0')}${date.day.toString().padLeft(2, '0')}';

  /// 날짜를 간결하게 포맷팅 (요일 포함)
  ///
  /// 예시:
  /// - formatDateCompact(DateTime(2024, 11, 28)) → '11/28(목)'
  static String formatDateCompact(DateTime date) =>
      '${date.month}/${date.day}(${weekday(date)})';

  /// 날짜를 한국어 긴 형식으로 포맷팅
  /// 예시: '2024년 5월 13일 (화)'
  static String formatDateLong(DateTime date) =>
      '${date.year}년 ${date.month}월 ${date.day}일 (${weekday(date)})';

  /// 날짜를 한국어 짧은 형식으로 포맷팅 (연도 없음)
  /// 예시: '5월 13일 (화)'
  static String formatDateKorean(DateTime date) =>
      '${date.month}월 ${date.day}일 (${weekday(date)})';

  /// 연월 포맷팅
  /// 예시: '2024년 5월'
  static String formatYearMonth(DateTime date) {
    return '${date.year}년 ${date.month}월';
  }

  /// 근무 기간 포맷팅 (단기/장기 구분)
  /// 
  /// 예시:
  /// - 단기 1일: '11/28(목)'
  /// - 단기 여러일: '11/28(목)~12/7(토) · 5일'
  /// - 장기: '11/28(목)~ · 월,수,금'
  /// - 장기 (요일 없음): '11/28(목)~ 장기'
  static String formatWorkPeriod({
    required DateTime startDate,
    DateTime? endDate,
    bool isLongTerm = false,
    List<String>? workDays,
    int? dayCount,
  }) {
    final startStr = formatDateCompact(startDate);
    
    // 장기 공고
    if (isLongTerm) {
      final endStr = endDate != null ? ' ~ ${formatDateCompact(endDate)}' : '~';
      if (workDays != null && workDays.isNotEmpty) {
        return '$startStr$endStr · ${workDays.join(",")}';
      }
      return '$startStr$endStr';
    }
    
    // 단기 1일
    if (endDate == null || _isSameDay(startDate, endDate)) {
      return startStr;
    }
    
    // 단기 여러일
    final endStr = formatDateCompact(endDate);
    final days = dayCount ?? endDate.difference(startDate).inDays + 1;
    return '$startStr~$endStr · $days일';
  }

  /// 두 날짜가 같은 날인지 비교
  static bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  /// 급여 + 타입 포맷팅
  /// 
  /// 예시:
  /// - formatWageWithType(11000, 'hourly') → '시급 11,000원'
  /// - formatWageWithType(110000, 'daily') → '일급 110,000원'
  /// - formatWageWithType(2500000, 'monthly') → '월급 2,500,000원'
  static String formatWageWithType(int wage, String wageType) {
    return '${getWageTypeLabel(wageType)} ${FormatHelper.formatNumber(wage)}원';
  }

  /// 급여 범위 포맷팅
  static String formatWageRange(int minWage, int maxWage, String wageType) {
    final typeLabel = getWageTypeLabel(wageType);
    if (minWage == maxWage) {
      return '$typeLabel ${FormatHelper.formatNumber(minWage)}원';
    }
    return '$typeLabel ${FormatHelper.formatNumber(minWage)}~${FormatHelper.formatNumber(maxWage)}원';
  }

  /// 급여 타입 라벨
  static String getWageTypeLabel(String wageType) {
    switch (wageType.toLowerCase()) {
      case 'hourly':   return '시급';
      case 'daily':    return '일급';
      case 'monthly':  return '월급';
      case 'per_case': return '건당';
      default:         return '급여';
    }
  }

  /// 주소에서 시/구 추출
  /// 
  /// 예시:
  /// - parseAddressCity('경기도 오산시 세교동 123-45') → '오산시'
  /// - parseAddressCity('서울특별시 강남구 역삼동 123') → '강남구'
  /// - parseAddressCity('부산광역시 해운대구 우동 456') → '해운대구'
  static String? parseAddressCity(String? address) {
    if (address == null || address.isEmpty) return null;
    
    final parts = address.split(' ');
    if (parts.length < 2) return null;
    
    // 시/도 다음에 오는 시/구/군 찾기
    for (int i = 0; i < parts.length; i++) {
      final part = parts[i];
      if (part.endsWith('시') || part.endsWith('구') || part.endsWith('군')) {
        // 첫 번째(시/도)가 아닌 경우만 반환
        if (i > 0 || !part.contains('특별') && !part.contains('광역') && !part.endsWith('도')) {
          return part;
        }
      }
    }
    
    // 못 찾으면 두 번째 요소 반환 시도
    return parts.length > 1 ? parts[1] : null;
  }

  /// 주소에서 동/읍/면 추출
  /// 
  /// 예시:
  /// - parseAddressDistrict('경기도 오산시 세교동 123-45') → '세교동'
  /// - parseAddressDistrict('서울특별시 강남구 역삼동 123') → '역삼동'
  static String? parseAddressDistrict(String? address) {
    if (address == null || address.isEmpty) return null;
    
    final parts = address.split(' ');
    
    // 동/읍/면/리 찾기
    for (final part in parts) {
      if (part.endsWith('동') || part.endsWith('읍') || 
          part.endsWith('면') || part.endsWith('리')) {
        // 숫자가 포함되어 있으면 건너뜀 (번지)
        if (!RegExp(r'\d').hasMatch(part)) {
          return part;
        }
      }
    }
    
    return null;
  }

  /// 지역 전체 포맷팅 (시/구 + 동)
  /// 
  /// 예시:
  /// - formatLocation('경기도 오산시 세교동 123') → '오산시 세교동'
  /// - formatLocation(null, city: '강남구', district: '역삼동') → '강남구 역삼동'
  static String formatLocation({
    String? address,
    String? city,
    String? district,
  }) {
    // 직접 전달된 값 우선
    final finalCity = city ?? parseAddressCity(address);
    final finalDistrict = district ?? parseAddressDistrict(address);
    
    if (finalCity != null && finalDistrict != null) {
      return '$finalCity $finalDistrict';
    } else if (finalCity != null) {
      return finalCity;
    } else if (finalDistrict != null) {
      return finalDistrict;
    }
    
    return '';
  }
  // ============================================================
  // 근무 시간 (분 → 소수 시간) 관련
  // ============================================================

  /// 분(minutes)을 소수 시간 형식으로 변환
  /// - 90분 → "1.5h", 60분 → "1h", 30분 → "0.5h"
  static String formatCompactHours(int mins) {
    if (mins <= 0) return '0h';
    final h = mins / 60;
    final str = h.toStringAsFixed(1);
    return str.endsWith('.0') ? '${str.substring(0, str.length - 2)}h' : '${str}h';
  }

  /// HH:mm 시작/종료 시간과 휴게시간으로 순 근무시간 계산 후 소수 시간 형식 반환
  /// - 자정 넘는 근무 지원 (endTime <= startTime이면 +24h)
  /// - 결과 0 이하면 '' 반환
  static String calcNetWorkTime(String startTime, String endTime, {int breakMinutes = 0}) {
    try {
      int toMins(String t) {
        final p = t.split(':');
        return int.parse(p[0]) * 60 + int.parse(p[1]);
      }
      int s = toMins(startTime);
      int e = toMins(endTime);
      if (e <= s) e += 1440;
      final net = (e - s - breakMinutes).clamp(0, 1440);
      if (net <= 0) return '';
      return formatCompactHours(net);
    } catch (_) {
      return '';
    }
  }

  /// 근무 요일 포맷팅
  /// 
  /// 예시:
  /// - ['월','화','수','목','금'] → '평일(월~금)'
  /// - ['월','화','수','목','금','토','일'] → '매일'
  /// - ['토','일'] → '주말(토,일)'
  /// - ['월','화','수','목','금','토'] → '주6일(일 휴무)'
  /// - ['월','수','금'] → '주3일(월,수,금)'
  static String formatWorkDays(List<String>? workDays) {
    if (workDays == null || workDays.isEmpty) return '';
    
    const allDays = _weekdays;
    const weekdays = ['월', '화', '수', '목', '금'];
    const weekend = ['토', '일'];
    
    // 정렬 (월~일 순서로)
    final sorted = List<String>.from(workDays);
    sorted.sort((a, b) => allDays.indexOf(a).compareTo(allDays.indexOf(b)));
    
    final count = sorted.length;
    
    // 매일 (7일)
    if (count == 7) {
      return '매일';
    }
    
    // 평일 (월~금)
    if (count == 5 && weekdays.every((d) => sorted.contains(d))) {
      return '평일(월~금)';
    }
    
    // 주말 (토,일)
    if (count == 2 && weekend.every((d) => sorted.contains(d))) {
      return '주말(토,일)';
    }
    
    // 주6일 (휴무일 표시)
    if (count == 6) {
      // allDays=7개, sorted=6개 → 반드시 1개 미포함 존재, orElse 불필요
      final offDay = allDays.firstWhere((d) => !sorted.contains(d));
      return '주6일($offDay 휴무)';
    }
    
    // 주5일인데 평일이 아닌 경우 (휴무일 2개 표시)
    if (count == 5) {
      final offDays = allDays.where((d) => !sorted.contains(d)).toList();
      return '주5일(${offDays.join(",")} 휴무)';
    }
    
    // 그 외: 주N일(요일나열)
    return '주$count일(${sorted.join(",")})';
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
    
    if (number == null || number < 0) {
      return oldValue;
    }

    final formatted = FormatHelper.formatNumber(number);
    
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
  
}