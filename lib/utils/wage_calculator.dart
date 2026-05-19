import 'dart:math';
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
    2026: 10320,
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
  /// [breakMinutes]: 실제 적용 휴게시간 (기본 + 추가공제)
  /// [scheduledBreakMinutes]: 예정 휴게시간 (공고 기준, null이면 breakMinutes와 동일)
  ///   - 일급제 기준근무시간 계산에 사용. 추가공제가 있는 경우 기본값만 전달해야 함.
  /// [nightAllowanceApplied]: 야간수당 별도 적용 여부
  /// [nightIncluded]: 일급에 야간수당이 포함된 경우 true — 계약 구간 내 야간분 제외, 초과분만 적용
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
    int? scheduledBreakMinutes,
    bool nightAllowanceApplied = true,
    bool nightIncluded = false,
    int additionalAmount = 0,
    String? memo,
    /// 일급제 수당 기초 시급 (연장·야간·휴일수당 기준). null이면 최저시급 적용
    int? baseHourlyWage,
  }) {
    // 근무일 기준 최저시급
    final minimumWage = getMinimumWage(workDate.year);

    // scheduledBreakMinutes: 공고 기준 예정 휴게 (null이면 breakMinutes와 동일)
    // 추가공제가 있으면 기본 휴게만 전달해야 기준근무시간이 변하지 않음
    final schedBreak = scheduledBreakMinutes ?? breakMinutes;

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
      // 일급제: 예정 시간 초과분 (예정 휴게 기준 — 추가공제 제외)
      final scheduledWorkMinutes = (scheduledMinutes - schedBreak).clamp(0, 9999);
      overtimeMinutes = (workMinutes - scheduledWorkMinutes).clamp(0, 9999);
    }
    
    // 3. 야간근무 계산
    int nightMinutes = 0;
    if (nightAllowanceApplied) {
      if (wageType == 'daily' && nightIncluded) {
        // 일급에 야간수당 포함 → 계약 구간 내 야간분은 제외, 초과분(scheduledEnd 이후)만 적용
        if (overtimeMinutes > 0) {
          nightMinutes = _calculateNightMinutes(scheduledEnd, actualEnd);
        }
      } else {
        nightMinutes = _calculateNightMinutes(actualStart, actualEnd);
      }
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
        scheduledBreakMinutes: schedBreak,
        overtimeMinutes: overtimeMinutes,
        nightMinutes: nightMinutes,
        nightAllowanceApplied: nightAllowanceApplied,
        minimumWage: minimumWage,
        baseHourlyWage: baseHourlyWage,
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
  ///
  /// - 기본급 + 연장수당 + 야간수당 모두 설정된 시급 기준
  /// - 시급이 최저시급 미만이어도 입력 허용 (UI에서 경고 표시)
  static Map<String, int> _calculateHourlyWage({
    required int hourlyWage,
    required int workMinutes,
    required int overtimeMinutes,
    required int nightMinutes,
    required bool nightAllowanceApplied,
    required int minimumWage,
  }) {
    // 기본급: 정규 근무(8시간 이하) × 실제 시급
    final regularMinutes = workMinutes - overtimeMinutes;
    final baseAmount = (regularMinutes * hourlyWage / 60).round();

    // 연장수당: 8시간 초과분 × 실제 시급 × 1.5
    final overtimeAmount = overtimeMinutes > 0
        ? (overtimeMinutes * hourlyWage * overtimeRate / 60).round()
        : 0;

    // 야간수당: 야간시간 × 실제 시급 × 0.5
    final nightAmount = (nightAllowanceApplied && nightMinutes > 0)
        ? (nightMinutes * hourlyWage * nightRate / 60).round()
        : 0;

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
    required int scheduledBreakMinutes,
    required int overtimeMinutes,
    required int nightMinutes,
    required bool nightAllowanceApplied,
    required int minimumWage,
    int? baseHourlyWage,
  }) {
    final scheduledWorkMinutes = (scheduledMinutes - scheduledBreakMinutes).clamp(0, 9999);

    // 수당 기초 시급: 관리자 설정값 > max(통상임금, 최저시급) 순 우선
    final rawOrdinaryHourly = scheduledWorkMinutes > 0
        ? (dailyWage / scheduledWorkMinutes * 60).round()
        : 0;
    final ordinaryHourlyCalc = max(rawOrdinaryHourly, minimumWage);
    final supplementWage = baseHourlyWage ?? ordinaryHourlyCalc;

    int baseAmount = 0;

    if (scheduledWorkMinutes == 0 || workMinutes >= scheduledWorkMinutes) {
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
        overtimeAmount = (overtimeMinutes * supplementWage / 60).round();
      } else {
        // 총 근무 8시간 초과: 8시간 초과분만 1.5배
        final over8Hours = workMinutes - standardWorkMinutes;
        final within8Hours = (overtimeMinutes - over8Hours).clamp(0, overtimeMinutes);

        final amount1x = (within8Hours * supplementWage / 60).round();
        final amount15x = (over8Hours.clamp(0, overtimeMinutes) * supplementWage * overtimeRate / 60).round();

        overtimeAmount = amount1x + amount15x;
      }
    }

    // 야간수당: 야간시간 × 기초시급 × 0.5
    int nightAmount = 0;
    if (nightAllowanceApplied && nightMinutes > 0) {
      nightAmount = (nightMinutes * supplementWage * nightRate / 60).round();
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
  ///
  /// 야간 구간을 세 개의 절대 구간으로 표현해 O(1) 교집합으로 계산:
  ///   [0, 360)      — 당일 00:00~06:00
  ///   [1320, 1440)  — 당일 22:00~24:00
  ///   [1440, 1800)  — 익일 00:00~06:00 (자정 넘긴 근무 대응)
  static int _calculateNightMinutes(String startTime, String endTime) {
    final s = _timeToMinutes(startTime);
    var e = _timeToMinutes(endTime);
    if (e <= s) e += 24 * 60;

    int overlap(int a, int b) => max(0, min(e, b) - max(s, a));

    return overlap(0, 360) + overlap(1320, 1440) + overlap(1440, 1800);
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
  
  /// 일급제 통상 시급 계산 (연장·야간수당 기준 안내용)
  /// 반환 null = 계산 불가 (입력값 부족)
  static int? computeOrdinaryHourlyWage({
    required String scheduledStart,
    required String scheduledEnd,
    required int breakMinutes,
    required int dailyWage,
  }) {
    if (dailyWage <= 0) return null;
    final scheduledMinutes = _calculateMinutesBetween(scheduledStart, scheduledEnd);
    final scheduledWorkMinutes = (scheduledMinutes - breakMinutes).clamp(0, 9999);
    if (scheduledWorkMinutes <= 0) return null;
    return (dailyWage / scheduledWorkMinutes * 60).round();
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
  
  // ============================================================
  // 주휴수당 계산
  // ============================================================

  /// 주휴수당 계산
  ///
  /// [ordinaryHourlyWage]: 통상시급 (WageDetailModel.appliedMinimumWage 기준)
  /// [weeklyWorkMinutes]: 해당 주 총 근무 분 (조건 확인용)
  /// - 15시간(900분) 미만이면 0 반환
  /// - 주 40시간 기준 비례 계산, 최대 8시간 상한
  static int calculateWeeklyHolidayPay({
    required int ordinaryHourlyWage,
    required int weeklyWorkMinutes,
  }) {
    if (weeklyWorkMinutes < 15 * 60) return 0;
    final weeklyHours = (weeklyWorkMinutes / 60.0).clamp(0.0, 40.0);
    return ((weeklyHours / 40.0) * 8.0 * ordinaryHourlyWage).round();
  }

  /// 급여 요약 문자열
  static String formatWageWithType(int wage, String wageType) {
    return '${getWageTypeLabel(wageType)} ${formatAmount(wage)}';
  }
}
