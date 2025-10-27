/// 근로기준법 관련 상수 및 계산 로직
class LaborStandards {
  // ==================== 최저임금 ====================
  
  /// 2025년 최저시급 (원)
  static const int minimumWage2025 = 10030;
  
  /// 현재 연도 최저시급 (나중에 Firestore로 전환 예정)
  static int get currentMinimumWage => minimumWage2025;
  
  // ==================== 근로시간 ====================
  
  /// 주 법정 근로시간
  static const int weeklyStandardHours = 40;
  
  /// 월 소정근로시간 (주 40시간 기준)
  /// 계산식: (40시간 × 52주) ÷ 12개월 = 173.33... ≈ 174시간
  static const double monthlyStandardHours = 174.0;
  
  /// 1일 기본 근로시간
  static const int dailyStandardHours = 8;
  
  // ==================== 주휴수당 ====================
  
  /// 주휴수당 지급 기준: 주 15시간 이상 근무
  static const int weeklyHolidayPayThreshold = 15;
  
  /// 주휴수당 비율 (20% = 하루치 추가)
  /// 예: 주 5일 근무 시, 1일 추가 = 20% 증가
  static const double weeklyHolidayPayRate = 0.2;
  
  // ==================== 포맷팅 ====================
  
  /// 금액을 천단위 콤마 형식으로 변환
  static String formatCurrency(int amount) {
    return amount.toString().replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (Match m) => '${m[1]},',
    );
  }
  
  /// 금액을 "원" 단위 문자열로 변환
  static String formatCurrencyWithUnit(int amount) {
    return '${formatCurrency(amount)}원';
  }
  
  // ==================== 검증 ====================
  
  /// 시급이 최저시급 이상인지 확인
  static bool isValidHourlyWage(int wage) {
    return wage >= currentMinimumWage;
  }
  
  /// 최저시급 미달 시 경고 메시지
  static String? getWageWarningMessage(int wage) {
    if (!isValidHourlyWage(wage)) {
      return '⚠️ ${DateTime.now().year}년 최저시급(${formatCurrencyWithUnit(currentMinimumWage)})보다 낮습니다.';
    }
    return null;
  }
  
  // ==================== 급여 계산 ====================
  
  /// 일급 계산 (시급 × 근무시간)
  static int calculateDailyWage(int hourlyWage, double workHours) {
    return (hourlyWage * workHours).round();
  }
  
  /// 주휴수당 포함 일급 계산
  static int calculateDailyWageWithHolidayPay(int hourlyWage, double workHours) {
    final baseWage = calculateDailyWage(hourlyWage, workHours);
    return (baseWage * (1 + weeklyHolidayPayRate)).round();
  }
  
  /// 월급을 시급으로 환산
  static int convertMonthlyToHourly(int monthlySalary, double monthlyHours) {
    return (monthlySalary / monthlyHours).round();
  }
  
  /// 시급을 월급으로 환산 (주 40시간 기준)
  static int convertHourlyToMonthly(int hourlyWage) {
    return (hourlyWage * monthlyStandardHours).round();
  }
}