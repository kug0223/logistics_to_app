import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/core/wage_detail_model.dart';
import 'format_helper.dart';

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
        _cachedMinimumWages = Map.fromEntries(
          data.entries
              .where((e) => int.tryParse(e.key) != null)
              .map((e) => MapEntry(int.parse(e.key), (e.value as num).toInt())),
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

  /// 근로기준법 제54조 기준 최대 허용 휴게시간 (분)
  ///
  /// - 4시간 미만 : 0분 (휴게 의무 없음)
  /// - 4시간 ~ 8시간 미만 : 30분
  /// - 8시간 이상 : 60분
  static int legalMaxBreakMinutes(int elapsedMinutes) {
    if (elapsedMinutes < 240) return 0;
    if (elapsedMinutes < 480) return 30;
    return 60;
  }

  /// 실제 출퇴근 시간으로 체류 시간(분) 계산
  static int elapsedMinutes(String actualStart, String actualEnd) =>
      _calculateMinutesBetween(actualStart, actualEnd);

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

    // 연장·야간수당 기초 시급 — 사업주 설정값 우선, 없으면 통상임금 계산
    final int appliedSupplementWage;
    if (wageType == 'hourly') {
      appliedSupplementWage = baseWage;
    } else {
      final schedMins = _calculateMinutesBetween(scheduledStart, scheduledEnd);
      final schedWorkMins = (schedMins - schedBreak).clamp(0, 9999);
      final rawOrdinary = schedWorkMins > 0 ? (baseWage / schedWorkMins * 60).round() : 0;
      appliedSupplementWage = baseHourlyWage ?? max(rawOrdinary, minimumWage);
    }

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

    // 조출 분 계산 (예정 시작보다 일찍 출근한 분) — overtimeMinutes 이하로 제한
    final schedStartMin = _parseTime(scheduledStart) ?? 0;
    final actualStartMin = _parseTime(actualStart) ?? 0;
    // 자정 넘김 보정: actualStart가 scheduledStart보다 수치상 크면 전날로 해석
    final adjustedActualStart = actualStartMin > schedStartMin
        ? actualStartMin - 24 * 60
        : actualStartMin;
    final rawEarlyArrivalMinutes = (schedStartMin - adjustedActualStart).clamp(0, 9999);
    final earlyArrivalMinutes = rawEarlyArrivalMinutes.clamp(0, overtimeMinutes);
    
    // 3. 야간근무 계산 (휴게는 주간 구간 먼저 소진 — 야간 시간대 공제 최소화)
    int nightMinutes = 0;
    if (nightAllowanceApplied) {
      if (wageType == 'daily' && nightIncluded) {
        // 일급에 야간수당 포함 → 계약 구간 내 야간분은 제외, 초과분만 적용
        if (overtimeMinutes > 0) {
          nightMinutes = _calculateNightMinutes(scheduledEnd, actualEnd);
          debugPrint('🌙 야간(nightIncluded OT): scheduledEnd=$scheduledEnd, actualEnd=$actualEnd → ${nightMinutes}min');
        }
      } else {
        final rawNightMinutes = _calculateNightMinutes(actualStart, actualEnd);
        // 휴게를 주간 구간에서 먼저 차감, 남은 경우에만 야간에서 차감
        final dayPortion = actualMinutes - rawNightMinutes;
        final breakInNight = max(0, breakMinutes - dayPortion.clamp(0, actualMinutes));
        nightMinutes = max(0, rawNightMinutes - breakInNight);
        if (rawNightMinutes > 0) {
          debugPrint('🌙 야간: actualStart=$actualStart, actualEnd=$actualEnd → raw=${rawNightMinutes}min, final=${nightMinutes}min');
        }
      }
    }
    
    // 4. 금액 계산
    int baseAmount = 0;
    int overtimeAmount = 0;
    int earlyArrivalAmt = 0;
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
        earlyArrivalMinutes: earlyArrivalMinutes,
        nightMinutes: nightMinutes,
        nightAllowanceApplied: nightAllowanceApplied,
        minimumWage: minimumWage,
        baseHourlyWage: baseHourlyWage,
      );
      baseAmount = result['baseAmount']!;
      overtimeAmount = result['overtimeAmount']!;
      nightAmount = result['nightAmount']!;
      earlyArrivalAmt = result['earlyArrivalAmount'] ?? 0;
    }
    
    // additionalAmount는 추가 공제에 음수 입력이 가능하지만 UI에서 검증하지 않으므로,
    // 극단적인 음수 입력 시 totalAmount가 음수가 될 수 있다. 호출 측에서 범위를 보장해야 한다.
    final totalAmount = baseAmount + overtimeAmount + nightAmount + additionalAmount;
    
    return WageDetailModel(
      wageType: wageType,
      baseWage: baseWage,
      scheduledMinutes: scheduledMinutes,
      actualMinutes: actualMinutes,
      breakMinutes: breakMinutes,
      workMinutes: workMinutes,
      overtimeMinutes: overtimeMinutes,
      earlyArrivalMinutes: earlyArrivalMinutes,
      nightMinutes: nightMinutes,
      baseAmount: baseAmount,
      overtimeAmount: overtimeAmount,
      earlyArrivalAmount: earlyArrivalAmt,
      nightAmount: nightAmount,
      additionalAmount: additionalAmount,
      totalAmount: totalAmount,
      nightAllowanceApplied: nightAllowanceApplied,
      memo: memo,
      appliedMinimumWage: minimumWage,
      appliedSupplementWage: appliedSupplementWage,
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
    required int earlyArrivalMinutes,
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

    // 연장수당: 총 근무 8시간 이하면 1배, 8시간 초과분만 1.5배 (근로기준법 제56조)
    // 조출도 연장의 일종으로 동일 기준 적용
    // scheduledWorkMinutes==0이면 일급 전액이 이미 baseAmount — 연장수당 중복 방지
    int earlyArrivalAmt = 0;
    int overtimeAmount = 0;
    if (overtimeMinutes > 0 && scheduledWorkMinutes > 0) {
      if (workMinutes <= standardWorkMinutes) {
        // 총 근무 8시간 이하: 연장분 전체 1배
        overtimeAmount = (overtimeMinutes * supplementWage / 60).round();
        // 조출도 8h 이내이므로 1배
        earlyArrivalAmt = (earlyArrivalMinutes * supplementWage / 60).round();
      } else {
        // 총 근무 8시간 초과: 8시간 초과분만 1.5배
        final over8Hours = workMinutes - standardWorkMinutes;
        final within8Hours = (overtimeMinutes - over8Hours).clamp(0, overtimeMinutes);

        final amount1x = (within8Hours * supplementWage / 60).round();
        final amount15x = (over8Hours.clamp(0, overtimeMinutes) * supplementWage * overtimeRate / 60).round();
        overtimeAmount = amount1x + amount15x;

        // 조출이 within8Hours 내이면 1배, 8h 초과에 걸치면 해당 부분 1.5배
        final earlyIn8h = min(earlyArrivalMinutes, within8Hours);
        final earlyOver8h = (earlyArrivalMinutes - earlyIn8h).clamp(0, 9999);
        earlyArrivalAmt = (earlyIn8h * supplementWage / 60).round() +
            (earlyOver8h * supplementWage * overtimeRate / 60).round();
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
      'earlyArrivalAmount': earlyArrivalAmt,
      'nightAmount': nightAmount,
    };
  }

  // ============================================================
  // 시간 계산 유틸
  // ============================================================
  
  /// 두 시간 사이의 분(minutes) 계산
  static int _calculateMinutesBetween(String startTime, String endTime) {
    final s = _parseTime(startTime);
    final e0 = _parseTime(endTime);
    if (s == null || e0 == null) {
      debugPrint('⚠️ _calculateMinutesBetween: 파싱 실패 — start=$startTime, end=$endTime');
      return 0;
    }
    var e = e0;
    // e < s 만 자정 넘김으로 처리 (e == s는 0분, e <= s 이면 24h로 잘못 계산됨)
    if (e < s) e += 24 * 60;
    return e - s;
  }

  /// 시간 문자열을 분으로 변환 (파싱 실패 시 null 반환)
  static int? _parseTime(String time) {
    try {
      final parts = time.split(':');
      if (parts.length < 2) return null;
      final hour = int.parse(parts[0]);
      final minute = int.parse(parts[1].substring(0, 2));
      if (hour < 0 || hour > 23 || minute < 0 || minute > 59) return null;
      return hour * 60 + minute;
    } catch (_) {
      return null;
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
    final s = _parseTime(startTime);
    final e0 = _parseTime(endTime);
    if (s == null || e0 == null) {
      debugPrint('⚠️ _calculateNightMinutes: 파싱 실패 — start=$startTime, end=$endTime');
      return 0;
    }
    var e = e0;
    if (e < s) e += 24 * 60;

    int overlap(int a, int b) => max(0, min(e, b) - max(s, a));

    return overlap(0, 360) + overlap(1320, 1440) + overlap(1440, 1800);
  }

  // ============================================================
  // 포맷팅 헬퍼
  // ============================================================
  
  /// 금액 포맷팅 (천단위 콤마)
  static String formatAmount(int amount) => FormatHelper.formatWage(amount);
  
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
  static String getWageTypeLabel(String wageType) =>
      FormatHelper.getWageTypeLabel(wageType);
  
  // ============================================================
  // 주휴수당 계산
  // ============================================================

  /// 주휴수당 참고 금액 계산 (자동 적용 없음)
  ///
  /// ⚠️ 설계 방침: 주휴수당은 급여 계산에 자동 포함되지 않음.
  /// 주휴수당의 인정 범위·지급 방식은 계약 형태·근무 일정에 따라 복잡하며,
  /// 이미 시급/일급에 포함해 계약한 경우도 많으므로 사업주가 직접 판단해
  /// additionalAmount로 수동 적용하도록 설계함.
  /// 이 메서드는 참고값(사업주 안내용) 계산 전용.
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
