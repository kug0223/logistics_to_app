import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/core/wage_detail_model.dart';

/// 급여 계산 유틸리티 클래스
/// 
/// 최저시급 적용:
/// - 근무일 기준 연도의 최저시급 적용
/// - Firestore settings/wage_config에서 연도별 최저시급 관리
/// - 로컬 백업으로 네트워크 오류 대비
class WageCalculator {
  // ============================================================
  // 최저시급 관리
  // ============================================================
  
  /// 로컬 백업 - 연도별 최저시급
  static const Map<int, int> _minimumWageByYear = {
    2026: 10360,  // 예정 (미리 세팅)
    2025: 10030,
    2024: 9860,
    2023: 9620,
    2022: 9160,
    2021: 8720,
    2020: 8590,
  };
  
  /// Firestore에서 로드된 최저시급 캐시
  static Map<int, int>? _cachedMinimumWages;
  
  /// Firestore에서 최저시급 로드 (앱 시작 시 1회 호출)
  static Future<void> loadMinimumWages() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('settings')
          .doc('wage_config')
          .get();
      
      if (doc.exists && doc.data()?['minimumWages'] != null) {
        final data = doc.data()!['minimumWages'] as Map<String, dynamic>;
        _cachedMinimumWages = data.map(
          (key, value) => MapEntry(int.parse(key), value as int),
        );
        debugPrint('✅ 최저시급 로드 완료: $_cachedMinimumWages');
      }
    } catch (e) {
      debugPrint('⚠️ 최저시급 로드 실패, 로컬 백업 사용: $e');
    }
  }
  
  /// 특정 연도의 최저시급 반환
  /// 
  /// [year]: 근무일 기준 연도
  static int getMinimumWage(int year) {
    // 1순위: Firestore 캐시
    if (_cachedMinimumWages != null && _cachedMinimumWages!.containsKey(year)) {
      return _cachedMinimumWages![year]!;
    }
    
    // 2순위: 로컬 백업
    if (_minimumWageByYear.containsKey(year)) {
      return _minimumWageByYear[year]!;
    }
    
    // 3순위: 가장 최근 연도 값
    final latestYear = _minimumWageByYear.keys.reduce((a, b) => a > b ? a : b);
    return _minimumWageByYear[latestYear]!;
  }
  
  /// 현재 연도 최저시급
  static int get currentMinimumWage => getMinimumWage(DateTime.now().year);

  // ============================================================
  // 상수
  // ============================================================
  
  /// 연장수당 배율 (1.5배)
  static const double overtimeRate = 1.5;
  
  /// 야간수당 배율 (0.5배 가산)
  static const double nightRate = 0.5;
  
  /// 기본 근무시간 (8시간 = 480분)
  static const int standardWorkMinutes = 480;

  // ============================================================
  // 메인 계산 메서드
  // ============================================================
  
  /// 급여 계산 (WageDetailModel 반환)
  /// 
  /// [wageType]: 'hourly' | 'daily'
  /// [baseWage]: 시급 또는 일급
  /// [workDate]: 근무일 (최저시급 연도 기준)
  /// [scheduledStart]: 예정 시작 시간 (HH:mm)
  /// [scheduledEnd]: 예정 종료 시간 (HH:mm)
  /// [actualStart]: 실제 출근 시간 (HH:mm)
  /// [actualEnd]: 실제 퇴근 시간 (HH:mm)
  /// [breakMinutes]: 휴게시간 (분)
  /// [nightAllowanceApplied]: 야간수당 별도 적용 여부
  /// [additionalAmount]: 추가수당
  /// [memo]: 메모
  static WageDetailModel calculate({
    required String wageType,
    required int baseWage,
    required DateTime workDate,
    required String scheduledStart,
    required String scheduledEnd,
    required String actualStart,
    required String actualEnd,
    int breakMinutes = 0,
    bool nightAllowanceApplied = false,
    int additionalAmount = 0,
    String? memo,
  }) {
    // 근무일 기준 최저시급
    final minimumWage = getMinimumWage(workDate.year);
    
    // 1. 시간 계산
    final scheduledMinutes = _calculateMinutesBetween(scheduledStart, scheduledEnd);
    final actualMinutes = _calculateMinutesBetween(actualStart, actualEnd);
    final workMinutes = (actualMinutes - breakMinutes).clamp(0, 9999);
    
    // 2. 연장근무 계산
    int overtimeMinutes = 0;
    if (wageType == 'hourly') {
      // 시급제: 8시간(480분) 초과분
      overtimeMinutes = (workMinutes - standardWorkMinutes).clamp(0, 9999);
    } else {
      // 일급제: 예정 시간 초과분
      final scheduledWorkMinutes = (scheduledMinutes - breakMinutes).clamp(0, 9999);
      overtimeMinutes = (workMinutes - scheduledWorkMinutes).clamp(0, 9999);
    }
    
    // 3. 야간근무 계산
    int nightMinutes = 0;
    if (nightAllowanceApplied) {
      nightMinutes = _calculateNightMinutes(actualStart, actualEnd);
    }
    
    // 4. 금액 계산
    int baseAmount = 0;
    int overtimeAmount = 0;
    int nightAmount = 0;
    
    if (wageType == 'hourly') {
      // 시급제 계산
      final result = _calculateHourlyWage(
        hourlyWage: baseWage,
        workMinutes: workMinutes,
        overtimeMinutes: overtimeMinutes,
        nightMinutes: nightMinutes,
        nightAllowanceApplied: nightAllowanceApplied,
        minimumWage: minimumWage,
      );
      baseAmount = result['baseAmount']!;
      overtimeAmount = result['overtimeAmount']!;
      nightAmount = result['nightAmount']!;
    } else {
      // 일급제 계산
      final result = _calculateDailyWage(
        dailyWage: baseWage,
        scheduledMinutes: scheduledMinutes,
        workMinutes: workMinutes,
        breakMinutes: breakMinutes,
        overtimeMinutes: overtimeMinutes,
        nightMinutes: nightMinutes,
        nightAllowanceApplied: nightAllowanceApplied,
        minimumWage: minimumWage,
      );
      baseAmount = result['baseAmount']!;
      overtimeAmount = result['overtimeAmount']!;
      nightAmount = result['nightAmount']!;
    }
    
    final totalAmount = baseAmount + overtimeAmount + nightAmount + additionalAmount;
    
    return WageDetailModel(
      wageType: wageType,
      baseWage: baseWage,
      scheduledMinutes: scheduledMinutes,
      actualMinutes: actualMinutes,
      breakMinutes: breakMinutes,
      workMinutes: workMinutes,
      overtimeMinutes: overtimeMinutes,
      nightMinutes: nightMinutes,
      baseAmount: baseAmount,
      overtimeAmount: overtimeAmount,
      nightAmount: nightAmount,
      additionalAmount: additionalAmount,
      totalAmount: totalAmount,
      nightAllowanceApplied: nightAllowanceApplied,
      memo: memo,
      appliedMinimumWage: minimumWage,
    );
  }

  // ============================================================
  // 시급제 계산
  // ============================================================
  
  /// 시급제 급여 계산
  static Map<String, int> _calculateHourlyWage({
    required int hourlyWage,
    required int workMinutes,
    required int overtimeMinutes,
    required int nightMinutes,
    required bool nightAllowanceApplied,
    required int minimumWage,
  }) {
    // 기본급: (근무시간 - 연장시간) × 시급
    final regularMinutes = workMinutes - overtimeMinutes;
    final baseAmount = (regularMinutes * hourlyWage / 60).round();
    
    // 연장수당 계산 (8시간 기준)
    int overtimeAmount = 0;
    if (overtimeMinutes > 0) {
    if (workMinutes <= standardWorkMinutes) {
      // 총 근무 8시간 이하: 연장분 1배
      overtimeAmount = (overtimeMinutes * minimumWage / 60).round();
    } else {
      // 총 근무 8시간 초과: 8시간 초과분만 1.5배
      final over8Hours = workMinutes - standardWorkMinutes;  // 8시간 초과분
      final within8Hours = overtimeMinutes - over8Hours;     // 8시간 이내 연장분
      
      final amount1x = (within8Hours.clamp(0, 9999) * minimumWage / 60).round();
      final amount15x = (over8Hours.clamp(0, 9999) * minimumWage * overtimeRate / 60).round();
      
      overtimeAmount = amount1x + amount15x;
   }
 }
    
    // 야간수당: 야간시간 × 최저시급 × 0.5
    int nightAmount = 0;
    if (nightAllowanceApplied && nightMinutes > 0) {
      nightAmount = (nightMinutes * minimumWage * nightRate / 60).round();
    }
    
    return {
      'baseAmount': baseAmount,
      'overtimeAmount': overtimeAmount,
      'nightAmount': nightAmount,
    };
  }

  // ============================================================
  // 일급제 계산
  // ============================================================
  
  /// 일급제 급여 계산
  static Map<String, int> _calculateDailyWage({
    required int dailyWage,
    required int scheduledMinutes,
    required int workMinutes,
    required int breakMinutes,
    required int overtimeMinutes,
    required int nightMinutes,
    required bool nightAllowanceApplied,
    required int minimumWage,
  }) {
    final scheduledWorkMinutes = (scheduledMinutes - breakMinutes).clamp(0, 9999);
    
    int baseAmount = 0;
    
    if (workMinutes >= scheduledWorkMinutes) {
      // 정상 근무 이상: 일급 전액
      baseAmount = dailyWage;
    } else {
      // 미달: 비율 계산
      baseAmount = (dailyWage * workMinutes / scheduledWorkMinutes).round();
    }
    
    // 연장수당: 총 근무 8시간 이하면 1배, 8시간 초과분만 1.5배
    int overtimeAmount = 0;
    if (overtimeMinutes > 0) {
      if (workMinutes <= standardWorkMinutes) {
        // 총 근무 8시간 이하: 연장분 전체 1배
        overtimeAmount = (overtimeMinutes * minimumWage / 60).round();
      } else {
        // 총 근무 8시간 초과: 8시간 초과분만 1.5배
        final over8Hours = workMinutes - standardWorkMinutes;
        final within8Hours = (overtimeMinutes - over8Hours).clamp(0, overtimeMinutes);
        
        final amount1x = (within8Hours * minimumWage / 60).round();
        final amount15x = (over8Hours.clamp(0, overtimeMinutes) * minimumWage * overtimeRate / 60).round();
        
        overtimeAmount = amount1x + amount15x;
      }
    }
    
    // 야간수당: 야간시간 × 최저시급 × 0.5
    int nightAmount = 0;
    if (nightAllowanceApplied && nightMinutes > 0) {
      nightAmount = (nightMinutes * minimumWage * nightRate / 60).round();
    }
    
    return {
      'baseAmount': baseAmount,
      'overtimeAmount': overtimeAmount,
      'nightAmount': nightAmount,
    };
  }

  // ============================================================
  // 시간 계산 유틸
  // ============================================================
  
  /// 두 시간 사이의 분(minutes) 계산
  static int _calculateMinutesBetween(String startTime, String endTime) {
    final startMinutes = _timeToMinutes(startTime);
    var endMinutes = _timeToMinutes(endTime);
    
    // 자정 넘김 처리 (예: 22:00 ~ 06:00)
    if (endMinutes <= startMinutes) {
      endMinutes += 24 * 60;
    }
    
    return endMinutes - startMinutes;
  }
  
  /// 시간 문자열을 분으로 변환
  static int _timeToMinutes(String time) {
    try {
      final parts = time.split(':');
      final hour = int.parse(parts[0]);
      final minute = int.parse(parts[1].substring(0, 2)); // 초 제거
      return hour * 60 + minute;
    } catch (e) {
      return 0;
    }
  }
  
  /// 분을 시간 문자열로 변환
  static String minutesToTimeString(int minutes) {
    final hours = minutes ~/ 60;
    final mins = minutes % 60;
    
    if (hours == 0) {
      return '$mins분';
    } else if (mins == 0) {
      return '$hours시간';
    } else {
      return '$hours시간 $mins분';
    }
  }
  
  /// 야간 근무 시간 계산 (22:00 ~ 06:00)
  static int _calculateNightMinutes(String startTime, String endTime) {
    final startMinutes = _timeToMinutes(startTime);
    var endMinutes = _timeToMinutes(endTime);
    
    // 자정 넘김 처리
    if (endMinutes <= startMinutes) {
      endMinutes += 24 * 60;
    }
    
    int nightMinutes = 0;
    
    const nightStart = 22 * 60;  // 1320분
    const nightEnd = 6 * 60;     // 360분
    
    for (int m = startMinutes; m < endMinutes; m++) {
      final normalizedMinute = m % (24 * 60);
      
      if (normalizedMinute >= nightStart || normalizedMinute < nightEnd) {
        nightMinutes++;
      }
    }
    
    return nightMinutes;
  }

  // ============================================================
  // 포맷팅 헬퍼
  // ============================================================
  
  /// 금액 포맷팅 (천단위 콤마)
  static String formatAmount(int amount) {
    return '${amount.toString().replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (Match m) => '${m[1]},',
    )}원';
  }
  
  /// 급여 타입 라벨
  static String getWageTypeLabel(String wageType) {
    switch (wageType) {
      case 'hourly':
        return '시급';
      case 'daily':
        return '일급';
      default:
        return '급여';
    }
  }
  
  /// 급여 요약 문자열
  static String formatWageWithType(int wage, String wageType) {
    return '${getWageTypeLabel(wageType)} ${formatAmount(wage)}';
  }
}
