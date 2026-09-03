// test/unit/wage_calculator_test.dart
// WageCalculator 계산 로직 단위 테스트 — 기존 test/wage_calculator_test.dart 보완
//
// 커버 범위:
//   - elapsedMinutes: 자정 넘김, 동일 시간
//   - 야간분 계산: 완전 주간·야간, 경계값, 자정 넘김 복합
//   - legalMaxBreakMinutes: 경계값 (239/240, 479/480)
//   - 시급제: 연장+야간 복합, 연장 없음 야간만
//   - 일급제: 정상·미달·연장(8h 이하/이상)·조출·nightIncluded
//   - scheduledBreakMinutes vs breakMinutes 분리
//   - breakMinutes > actualMinutes → workMinutes=0 안전장치
//   - calculateWeeklyHolidayPay: 900분 경계·비례·상한
//   - computeOrdinaryHourlyWage: 정상·불가 케이스

import 'package:flutter_test/flutter_test.dart';
import 'package:ALfit/utils/wage_calculator.dart';

const int _w = 12000;          // 테스트용 시급
const int _daily = 120000;     // 테스트용 일급
final DateTime _d = DateTime(2026, 6, 1);

void main() {
  // ══════════════════════════════════════════════════════
  // elapsedMinutes — _calculateMinutesBetween 래퍼
  // ══════════════════════════════════════════════════════
  group('elapsedMinutes', () {
    test('동일 시간 → 0분', () {
      expect(WageCalculator.elapsedMinutes('09:00', '09:00'), equals(0));
    });

    test('같은 날 일반 구간', () {
      expect(WageCalculator.elapsedMinutes('09:00', '18:00'), equals(9 * 60));
    });

    test('자정 넘김: 23:00~02:00 → 3시간', () {
      expect(WageCalculator.elapsedMinutes('23:00', '02:00'), equals(3 * 60));
    });

    test('자정 넘김: 22:00~06:00 → 8시간', () {
      expect(WageCalculator.elapsedMinutes('22:00', '06:00'), equals(8 * 60));
    });

    test('파싱 실패 → 0', () {
      expect(WageCalculator.elapsedMinutes('invalid', '09:00'), equals(0));
    });
  });

  // ══════════════════════════════════════════════════════
  // legalMaxBreakMinutes — 경계값 집중 검증
  // ══════════════════════════════════════════════════════
  group('legalMaxBreakMinutes', () {
    test('239분 미만 → 0', () => expect(WageCalculator.legalMaxBreakMinutes(239), equals(0)));
    test('240분(4시간) → 30', () => expect(WageCalculator.legalMaxBreakMinutes(240), equals(30)));
    test('479분 → 30', () => expect(WageCalculator.legalMaxBreakMinutes(479), equals(30)));
    test('480분(8시간) → 60', () => expect(WageCalculator.legalMaxBreakMinutes(480), equals(60)));
    test('600분(10시간) → 60', () => expect(WageCalculator.legalMaxBreakMinutes(600), equals(60)));
  });

  // ══════════════════════════════════════════════════════
  // 야간수당 계산 — nightMinutes 검증
  // (nightAllowanceApplied=true, breakMinutes=0으로 야간분 직접 측정)
  // ══════════════════════════════════════════════════════
  group('야간분 계산 (nightMinutes)', () {
    test('완전 주간 08:00~17:00 → nightMinutes=0', () {
      final r = WageCalculator.calculate(
        wageType: 'hourly', baseWage: _w, workDate: _d,
        scheduledStart: '08:00', scheduledEnd: '17:00',
        actualStart: '08:00', actualEnd: '17:00',
        breakMinutes: 0, nightAllowanceApplied: true,
      );
      expect(r.nightMinutes, equals(0));
      expect(r.nightAmount, equals(0));
    });

    test('완전 야간 22:00~06:00 → nightMinutes=480', () {
      final r = WageCalculator.calculate(
        wageType: 'hourly', baseWage: _w, workDate: _d,
        scheduledStart: '22:00', scheduledEnd: '06:00',
        actualStart: '22:00', actualEnd: '06:00',
        breakMinutes: 0, nightAllowanceApplied: true,
      );
      expect(r.nightMinutes, equals(480));
      // nightAmount = 480 * 12000 * 0.5 / 60 = 48000
      expect(r.nightAmount, equals(48000));
    });

    test('일부 야간 20:00~23:00 → nightMinutes=60 (22:00~23:00)', () {
      final r = WageCalculator.calculate(
        wageType: 'hourly', baseWage: _w, workDate: _d,
        scheduledStart: '20:00', scheduledEnd: '23:00',
        actualStart: '20:00', actualEnd: '23:00',
        breakMinutes: 0, nightAllowanceApplied: true,
      );
      expect(r.nightMinutes, equals(60));
    });

    test('자정 넘김 23:00~02:00 → nightMinutes=180 (23:00~00:00=60+00:00~02:00=120)', () {
      final r = WageCalculator.calculate(
        wageType: 'hourly', baseWage: _w, workDate: _d,
        scheduledStart: '23:00', scheduledEnd: '02:00',
        actualStart: '23:00', actualEnd: '02:00',
        breakMinutes: 0, nightAllowanceApplied: true,
      );
      expect(r.nightMinutes, equals(180));
      // totalAmount = 3h기본 + 3h야간0.5 = 3*12000 + 3*12000*0.5 = 36000+18000 = 54000
      expect(r.totalAmount, equals(54000));
    });

    test('야간 시작 경계 21:59~22:01 → nightMinutes=1', () {
      final r = WageCalculator.calculate(
        wageType: 'hourly', baseWage: _w, workDate: _d,
        scheduledStart: '21:59', scheduledEnd: '22:01',
        actualStart: '21:59', actualEnd: '22:01',
        breakMinutes: 0, nightAllowanceApplied: true,
      );
      expect(r.nightMinutes, equals(1));
    });

    test('야간 종료 경계 05:59~06:01 → nightMinutes=1', () {
      final r = WageCalculator.calculate(
        wageType: 'hourly', baseWage: _w, workDate: _d,
        scheduledStart: '05:59', scheduledEnd: '06:01',
        actualStart: '05:59', actualEnd: '06:01',
        breakMinutes: 0, nightAllowanceApplied: true,
      );
      expect(r.nightMinutes, equals(1));
    });

    test('야간수당 미적용(nightAllowanceApplied=false) → nightAmount=0', () {
      final r = WageCalculator.calculate(
        wageType: 'hourly', baseWage: _w, workDate: _d,
        scheduledStart: '22:00', scheduledEnd: '06:00',
        actualStart: '22:00', actualEnd: '06:00',
        breakMinutes: 0, nightAllowanceApplied: false,
      );
      expect(r.nightAmount, equals(0));
    });
  });

  // ══════════════════════════════════════════════════════
  // 시급제 — 연장+야간 복합
  // ══════════════════════════════════════════════════════
  group('시급제 연장+야간 복합', () {
    test('10시간 근무(연장2h) + 야간 22:00~06:00 포함', () {
      // 20:00~07:00(11h), 휴게 60분 → 실근무 10h(600min)
      // 연장 = 600-480 = 120분
      // 야간: 22:00~06:00 범위에서 실제 구간 20:00~07:00
      //   rawNight = overlap(0,360)+(1320,1440)+(1440,1800) for s=1200, e=1620(+24h→07:00→420+1440)
      //   Wait: 20:00=1200, 07:00=420, 420<1200 → e=420+1440=1860
      //   overlap(0,360)=max(0,min(1860,360)-max(1200,0))=max(0,360-1200)=0
      //   overlap(1320,1440)=max(0,min(1860,1440)-max(1200,1320))=max(0,1440-1320)=120
      //   overlap(1440,1800)=max(0,min(1860,1800)-max(1200,1440))=max(0,1800-1440)=360
      //   rawNight = 480
      //   dayPortion = 660-480=180, breakInNight=max(0,60-180)=0, nightMin=480
      final r = WageCalculator.calculate(
        wageType: 'hourly', baseWage: _w, workDate: _d,
        scheduledStart: '20:00', scheduledEnd: '07:00',
        actualStart: '20:00', actualEnd: '07:00',
        breakMinutes: 60, nightAllowanceApplied: true,
      );
      expect(r.workMinutes, equals(600));
      expect(r.overtimeMinutes, equals(120));
      expect(r.nightMinutes, equals(480));
      // baseAmount = (480 * 12000 / 60) = 96000
      // overtimeAmount = (120 * 12000 * 1.5 / 60) = 36000
      // nightAmount = (480 * 12000 * 0.5 / 60) = 48000
      expect(r.baseAmount, equals(96000));
      expect(r.overtimeAmount, equals(36000));
      expect(r.nightAmount, equals(48000));
      expect(r.totalAmount, equals(180000));
    });
  });

  // ══════════════════════════════════════════════════════
  // 시급제 — 안전장치
  // ══════════════════════════════════════════════════════
  group('시급제 안전장치', () {
    test('breakMinutes > actualMinutes → workMinutes=0, totalAmount=0', () {
      // 20분 근무인데 휴게 30분 설정 (입력 오류 시뮬레이션)
      final r = WageCalculator.calculate(
        wageType: 'hourly', baseWage: _w, workDate: _d,
        scheduledStart: '09:00', scheduledEnd: '09:20',
        actualStart: '09:00', actualEnd: '09:20',
        breakMinutes: 30,
        nightAllowanceApplied: false,
      );
      expect(r.workMinutes, equals(0));
      expect(r.totalAmount, equals(0));
    });
  });

  // ══════════════════════════════════════════════════════
  // 일급제 — 연장수당 8시간 경계 분기
  // ══════════════════════════════════════════════════════
  group('일급제 연장수당', () {
    // baseHourlyWage=16667 고정 (테스트 값 안정화)
    // schedule: 09:00~15:00 (6h), break 0, daily 100000

    test('연장 2시간(총 8h ≤ 480분) → 1배 적용', () {
      // actual 09:00~17:00 (8h), schedWork=360min, work=480min, OT=120min
      // total work(480) <= 480 → 1배
      // supplementWage = max((100000/360*60).round(), 10320) = max(16667, 10320) = 16667
      // overtimeAmount = (120 * 16667 / 60).round() = 33334
      final r = WageCalculator.calculate(
        wageType: 'daily', baseWage: 100000, workDate: _d,
        scheduledStart: '09:00', scheduledEnd: '15:00',
        actualStart: '09:00', actualEnd: '17:00',
        breakMinutes: 0, nightAllowanceApplied: false,
        baseHourlyWage: 16667,
      );
      expect(r.overtimeMinutes, equals(120));
      expect(r.baseAmount, equals(100000));
      expect(r.overtimeAmount, equals(33334)); // 120 * 16667 / 60 = 33334
      expect(r.totalAmount, equals(133334));
    });

    test('연장 4시간(총 10h > 480분) → 8h 이내분 1배 + 초과분 1.5배', () {
      // actual 09:00~19:00 (10h), schedWork=360min, work=600min, OT=240min
      // total work(600) > 480
      // over8Hours = 600-480 = 120, within8Hours = 240-120 = 120
      // amount1x = (120 * 16667 / 60).round() = 33334
      // amount15x = (120 * 16667 * 1.5 / 60).round() = 50001
      // overtimeAmount = 33334 + 50001 = 83335
      final r = WageCalculator.calculate(
        wageType: 'daily', baseWage: 100000, workDate: _d,
        scheduledStart: '09:00', scheduledEnd: '15:00',
        actualStart: '09:00', actualEnd: '19:00',
        breakMinutes: 0, nightAllowanceApplied: false,
        baseHourlyWage: 16667,
      );
      expect(r.overtimeMinutes, equals(240));
      expect(r.overtimeAmount, equals(83335));
      expect(r.totalAmount, equals(183335));
    });

    test('예정 시간 미달 → 비율 계산', () {
      // schedule 09:00~18:00 (9h, break 60 → 8h work), actual 10:00~18:00 (7h net)
      // workMins = 7*60=420, schedWorkMins=480 → 420<480 → 비율
      // baseAmount = (120000 * 420 / 480).round() = 105000
      final r = WageCalculator.calculate(
        wageType: 'daily', baseWage: _daily, workDate: _d,
        scheduledStart: '09:00', scheduledEnd: '18:00',
        actualStart: '10:00', actualEnd: '18:00',
        breakMinutes: 60, nightAllowanceApplied: false,
      );
      expect(r.workMinutes, equals(420));
      expect(r.baseAmount, equals(105000));
      expect(r.overtimeAmount, equals(0));
    });

    test('일급제 야간수당 — supplementWage 기준 0.5배 가산', () {
      // schedule 22:00~06:00 (8h, break 0), actual same
      // schedWorkMins=480, ordinaryHourly=(120000/480*60).round()=15000
      // nightMinutes = 480 (전체 야간)
      // nightAmount = (480 * 15000 * 0.5 / 60).round() = 60000
      final r = WageCalculator.calculate(
        wageType: 'daily', baseWage: _daily, workDate: _d,
        scheduledStart: '22:00', scheduledEnd: '06:00',
        actualStart: '22:00', actualEnd: '06:00',
        breakMinutes: 0, nightAllowanceApplied: true,
      );
      expect(r.nightMinutes, equals(480));
      expect(r.nightAmount, equals(60000));
      expect(r.baseAmount, equals(_daily));
    });
  });

  // ══════════════════════════════════════════════════════
  // 일급제 — 조출(earlyArrival)
  // ══════════════════════════════════════════════════════
  group('일급제 조출', () {
    test('예정 09:00, 실제 08:00 출근 (1시간 조출)', () {
      // schedule 09:00~18:00 (9h, break 60 → 8h=480min)
      // actual 08:00~18:00 (10h-60min break = 9h=540min)
      // OT = 540-480 = 60min, earlyArrival = 60min
      // work(540) > 480 → 8h 초과
      // over8Hours = 60, within8Hours = (60-60).clamp(0,60) = 0
      // earlyIn8h = min(60,0)=0, earlyOver8h = 60
      final r = WageCalculator.calculate(
        wageType: 'daily', baseWage: _daily, workDate: _d,
        scheduledStart: '09:00', scheduledEnd: '18:00',
        actualStart: '08:00', actualEnd: '18:00',
        breakMinutes: 60, nightAllowanceApplied: false,
        baseHourlyWage: 15000,
      );
      expect(r.earlyArrivalMinutes, equals(60));
      expect(r.overtimeMinutes, equals(60));
      expect(r.baseAmount, equals(_daily));
      // overtimeAmount = 0(1×) + (60 * 15000 * 1.5 / 60).round() = 22500
      expect(r.overtimeAmount, equals(22500));
      // earlyArrivalAmount = 22500 (조출분이 8h초과에 해당)
      expect(r.earlyArrivalAmount, equals(22500));
    });

    test('예정보다 늦게 출근(지각) → earlyArrivalMinutes=0', () {
      final r = WageCalculator.calculate(
        wageType: 'daily', baseWage: _daily, workDate: _d,
        scheduledStart: '09:00', scheduledEnd: '18:00',
        actualStart: '09:30', actualEnd: '18:00',
        breakMinutes: 60, nightAllowanceApplied: false,
      );
      expect(r.earlyArrivalMinutes, equals(0));
    });
  });

  // ══════════════════════════════════════════════════════
  // 일급제 — nightIncluded 플래그
  // ══════════════════════════════════════════════════════
  group('일급제 nightIncluded', () {
    test('nightIncluded=true, 연장 없음 → nightAmount=0', () {
      // 일급에 야간 포함, 실제=예정 → 초과 없음 → 야간수당 추가 0
      final r = WageCalculator.calculate(
        wageType: 'daily', baseWage: _daily, workDate: _d,
        scheduledStart: '22:00', scheduledEnd: '06:00',
        actualStart: '22:00', actualEnd: '06:00',
        breakMinutes: 0, nightAllowanceApplied: true, nightIncluded: true,
      );
      expect(r.overtimeMinutes, equals(0));
      expect(r.nightAmount, equals(0));
    });

    test('nightIncluded=true, 연장 1시간(주간) → 연장 구간 야간분만 적용', () {
      // schedule 22:00~06:00 (8h), actual 22:00~07:00 (9h)
      // OT=60min, nightIncluded → nightMins = _calculateNightMinutes("06:00","07:00")
      // s=360, e=420 → overlap(0,360)=max(0,360-360)=0 → all 0
      // nightMinutes = 0 (06:00~07:00은 주간)
      final r = WageCalculator.calculate(
        wageType: 'daily', baseWage: _daily, workDate: _d,
        scheduledStart: '22:00', scheduledEnd: '06:00',
        actualStart: '22:00', actualEnd: '07:00',
        breakMinutes: 0, nightAllowanceApplied: true, nightIncluded: true,
        baseHourlyWage: 15000,
      );
      expect(r.overtimeMinutes, equals(60));
      expect(r.nightMinutes, equals(0));
      expect(r.nightAmount, equals(0));
    });

    test('nightIncluded=true, 연장 1시간(야간) → 초과 야간분 적용', () {
      // schedule 22:00~04:00 (6h, break 0), actual 22:00~05:00 (7h)
      // OT=60min, nightIncluded → nightMins = _calculateNightMinutes("04:00","05:00")
      // s=240, e=300 → overlap(0,360)=max(0,300-240)=60 → total=60
      // nightAmount = (60 * supplementWage * 0.5 / 60) = supplementWage * 0.5
      final r = WageCalculator.calculate(
        wageType: 'daily', baseWage: _daily, workDate: _d,
        scheduledStart: '22:00', scheduledEnd: '04:00',
        actualStart: '22:00', actualEnd: '05:00',
        breakMinutes: 0, nightAllowanceApplied: true, nightIncluded: true,
        baseHourlyWage: 15000,
      );
      expect(r.overtimeMinutes, equals(60));
      expect(r.nightMinutes, equals(60));
      expect(r.nightAmount, equals(7500)); // 60 * 15000 * 0.5 / 60
    });
  });

  // ══════════════════════════════════════════════════════
  // 일급제 — scheduledBreakMinutes 분리
  // ══════════════════════════════════════════════════════
  group('scheduledBreakMinutes vs breakMinutes', () {
    test('추가공제 있을 때 기준근무시간은 예정 휴게 기준', () {
      // schedule 09:00~18:00 (9h), schedBreak=60 → schedWork=480
      // 실제 break=90 (추가 30분 공제), workMins=540-90=450
      // 450 < 480 → 비율: (120000 * 450 / 480).round() = 112500
      final r = WageCalculator.calculate(
        wageType: 'daily', baseWage: _daily, workDate: _d,
        scheduledStart: '09:00', scheduledEnd: '18:00',
        actualStart: '09:00', actualEnd: '18:00',
        breakMinutes: 90, scheduledBreakMinutes: 60,
        nightAllowanceApplied: false,
      );
      expect(r.workMinutes, equals(450));
      expect(r.baseAmount, equals(112500));
    });

    test('scheduledBreakMinutes=breakMinutes(기본) → 동일 동작', () {
      // 같은 공제라면 scheduledBreakMinutes 명시 여부 무관하게 동일
      final r1 = WageCalculator.calculate(
        wageType: 'daily', baseWage: _daily, workDate: _d,
        scheduledStart: '09:00', scheduledEnd: '18:00',
        actualStart: '09:00', actualEnd: '18:00',
        breakMinutes: 60, nightAllowanceApplied: false,
      );
      final r2 = WageCalculator.calculate(
        wageType: 'daily', baseWage: _daily, workDate: _d,
        scheduledStart: '09:00', scheduledEnd: '18:00',
        actualStart: '09:00', actualEnd: '18:00',
        breakMinutes: 60, scheduledBreakMinutes: 60,
        nightAllowanceApplied: false,
      );
      expect(r1.baseAmount, equals(r2.baseAmount));
      expect(r1.overtimeAmount, equals(r2.overtimeAmount));
    });
  });

  // ══════════════════════════════════════════════════════
  // calculateWeeklyHolidayPay — 주휴수당 경계값
  // ══════════════════════════════════════════════════════
  group('calculateWeeklyHolidayPay', () {
    const int hourlyWage = 10320;

    test('899분(14.98h) → 0 (15시간 미만)', () {
      expect(
        WageCalculator.calculateWeeklyHolidayPay(
          ordinaryHourlyWage: hourlyWage, weeklyWorkMinutes: 899,
        ),
        equals(0),
      );
    });

    test('900분(15시간) → 비례 계산', () {
      // (15/40) * 8 * 10320 = 0.375 * 8 * 10320 = 30960
      expect(
        WageCalculator.calculateWeeklyHolidayPay(
          ordinaryHourlyWage: hourlyWage, weeklyWorkMinutes: 900,
        ),
        equals(30960),
      );
    });

    test('2400분(40시간) → 최대 8시간 상한', () {
      // (40/40) * 8 * 10320 = 82560
      expect(
        WageCalculator.calculateWeeklyHolidayPay(
          ordinaryHourlyWage: hourlyWage, weeklyWorkMinutes: 2400,
        ),
        equals(82560),
      );
    });

    test('2400분 초과(40h 초과) → clamp 40h → 동일 결과', () {
      final at40h = WageCalculator.calculateWeeklyHolidayPay(
        ordinaryHourlyWage: hourlyWage, weeklyWorkMinutes: 2400,
      );
      final over40h = WageCalculator.calculateWeeklyHolidayPay(
        ordinaryHourlyWage: hourlyWage, weeklyWorkMinutes: 3000,
      );
      expect(over40h, equals(at40h));
    });

    test('서로 다른 시급으로 비례 계산', () {
      // 1800분(30h) → (30/40) * 8 * 12000 = 72000
      expect(
        WageCalculator.calculateWeeklyHolidayPay(
          ordinaryHourlyWage: 12000, weeklyWorkMinutes: 1800,
        ),
        equals(72000),
      );
    });
  });

  // ══════════════════════════════════════════════════════
  // computeOrdinaryHourlyWage — 일급 통상시급 계산
  // ══════════════════════════════════════════════════════
  group('computeOrdinaryHourlyWage', () {
    test('일급 80,000 / 예정 8시간(break 60) → 10,000원', () {
      // scheduledMins = 540, schedWorkMins = 480 → 80000/480*60 = 10000
      final result = WageCalculator.computeOrdinaryHourlyWage(
        scheduledStart: '09:00', scheduledEnd: '18:00',
        breakMinutes: 60, dailyWage: 80000,
      );
      expect(result, equals(10000));
    });

    test('일급 120,000 / 예정 8시간(break 60) → 15,000원', () {
      final result = WageCalculator.computeOrdinaryHourlyWage(
        scheduledStart: '09:00', scheduledEnd: '18:00',
        breakMinutes: 60, dailyWage: 120000,
      );
      expect(result, equals(15000));
    });

    test('dailyWage=0 → null (계산 불가)', () {
      expect(
        WageCalculator.computeOrdinaryHourlyWage(
          scheduledStart: '09:00', scheduledEnd: '18:00',
          breakMinutes: 60, dailyWage: 0,
        ),
        isNull,
      );
    });

    test('scheduledStart==scheduledEnd → null (근무시간 0)', () {
      expect(
        WageCalculator.computeOrdinaryHourlyWage(
          scheduledStart: '09:00', scheduledEnd: '09:00',
          breakMinutes: 0, dailyWage: 100000,
        ),
        isNull,
      );
    });
  });

  // ══════════════════════════════════════════════════════
  // appliedSupplementWage 검증
  // ══════════════════════════════════════════════════════
  group('appliedSupplementWage', () {
    test('시급제 → baseWage 그대로 사용', () {
      final r = WageCalculator.calculate(
        wageType: 'hourly', baseWage: 12000, workDate: _d,
        scheduledStart: '09:00', scheduledEnd: '18:00',
        actualStart: '09:00', actualEnd: '18:00',
        breakMinutes: 60, nightAllowanceApplied: false,
      );
      expect(r.appliedSupplementWage, equals(12000));
    });

    test('일급제, baseHourlyWage 명시 → 해당 값 우선', () {
      final r = WageCalculator.calculate(
        wageType: 'daily', baseWage: _daily, workDate: _d,
        scheduledStart: '09:00', scheduledEnd: '18:00',
        actualStart: '09:00', actualEnd: '18:00',
        breakMinutes: 60, nightAllowanceApplied: false,
        baseHourlyWage: 14000,
      );
      expect(r.appliedSupplementWage, equals(14000));
    });

    test('일급제, 통상임금이 최저시급 미만 → 최저시급 적용', () {
      // daily=40000, schedWork=480min → ordinaryHourly=(40000/480*60)=5000 < 10320
      // → supplementWage=10320
      final r = WageCalculator.calculate(
        wageType: 'daily', baseWage: 40000, workDate: _d,
        scheduledStart: '09:00', scheduledEnd: '18:00',
        actualStart: '09:00', actualEnd: '18:00',
        breakMinutes: 60, nightAllowanceApplied: false,
      );
      expect(r.appliedSupplementWage, greaterThanOrEqualTo(10320));
    });
  });

  // ══════════════════════════════════════════════════════
  // [PHASE5.2] nightIncluded=true break allocation 테스트
  // ALfit 정책: 무급 추가휴게는 비야간 초과시간 우선 소진
  // ══════════════════════════════════════════════════════
  group('[PHASE5.2] nightIncluded break allocation', () {
    // NIGHT-01: 조출 야간 (earlyNight), additionalBreak=0
    // 계약 01:00~09:00, 실제 23:00~09:00, break=60, additionalBreak=0
    // earlyNight(23:00~01:00)=120, lateNight=0
    // additionalBreak=0 → nightAllocatedBreak=0 → nightMinutes=120
    test('NIGHT-01: 조출 야간 120min, break 없음 → nightMinutes=120, nightAmount=10000', () {
      final r = WageCalculator.calculate(
        wageType: 'daily', baseWage: 96000, workDate: _d,
        scheduledStart: '01:00', scheduledEnd: '09:00',
        actualStart: '23:00', actualEnd: '09:00',
        breakMinutes: 60, scheduledBreakMinutes: 60,
        nightAllowanceApplied: true, nightIncluded: true,
        baseHourlyWage: 10000,
      );
      expect(r.nightMinutes, equals(120), reason: 'NIGHT-01: nightMinutes');
      expect(r.nightAmount, equals(10000), reason: 'NIGHT-01: nightAmount = 120×10000×0.5/60 = 10000');
      // snapshot 필드 저장 확인
      expect(r.nightIncluded, isTrue, reason: 'NIGHT-01: nightIncluded snapshot');
    });

    // NIGHT-04: 후반 야간 (lateNight), additionalBreak=0
    // 계약 14:00~22:00, 실제 14:00~23:00, break=60, additionalBreak=0
    // lateNight(22:00~23:00)=60, earlyNight=0
    // additionalBreak=0 → nightMinutes=60
    test('NIGHT-04: 후반 야간 60min, break 없음 → nightMinutes=60, nightAmount=5000', () {
      final r = WageCalculator.calculate(
        wageType: 'daily', baseWage: 96000, workDate: _d,
        scheduledStart: '14:00', scheduledEnd: '22:00',
        actualStart: '14:00', actualEnd: '23:00',
        breakMinutes: 60, scheduledBreakMinutes: 60,
        nightAllowanceApplied: true, nightIncluded: true,
        baseHourlyWage: 10000,
      );
      expect(r.nightMinutes, equals(60), reason: 'NIGHT-04: nightMinutes');
      expect(r.nightAmount, equals(5000), reason: 'NIGHT-04: nightAmount = 60×10000×0.5/60 = 5000');
    });

    // NIGHT-BREAK-02: 비야간 초과가 있어 break가 주간에 흡수
    // 계약 12:00~20:00, 실제 12:00~23:00, schedBreak=60, additionalBreak=30
    // lateNight(22:00~23:00)=60, rawExtraNonNight=120(20:00~22:00)
    // additionalBreak=30 → rawExtraNonNight(120) 흡수 → nightAllocatedBreak=0
    // nightMinutes=60
    test('NIGHT-BREAK-02: 비야간 초과가 break 흡수 → nightMinutes=60', () {
      final r = WageCalculator.calculate(
        wageType: 'daily', baseWage: 96000, workDate: _d,
        scheduledStart: '12:00', scheduledEnd: '20:00',
        actualStart: '12:00', actualEnd: '23:00',
        breakMinutes: 90, scheduledBreakMinutes: 60,
        nightAllowanceApplied: true, nightIncluded: true,
        baseHourlyWage: 10000,
      );
      expect(r.nightMinutes, equals(60), reason: 'NIGHT-BREAK-02: nightMinutes');
      expect(r.nightAmount, equals(5000), reason: 'NIGHT-BREAK-02: nightAmount = 60×10000×0.5/60');
    });

    // NIGHT-BREAK-03: 초과가 전부 야간 → break가 야간에서 차감
    // 계약 14:00~22:00, 실제 14:00~00:00, schedBreak=60, additionalBreak=30
    // lateNight(22:00~00:00)=120, rawExtraNonNight=0
    // additionalBreak=30 → rawExtraNonNight(0) 부족 → nightAllocatedBreak=30
    // nightMinutes=120-30=90
    test('NIGHT-BREAK-03: 초과 전부 야간, break 야간 차감 → nightMinutes=90', () {
      final r = WageCalculator.calculate(
        wageType: 'daily', baseWage: 96000, workDate: _d,
        scheduledStart: '14:00', scheduledEnd: '22:00',
        actualStart: '14:00', actualEnd: '00:00',
        breakMinutes: 90, scheduledBreakMinutes: 60,
        nightAllowanceApplied: true, nightIncluded: true,
        baseHourlyWage: 10000,
      );
      expect(r.nightMinutes, equals(90), reason: 'NIGHT-BREAK-03: nightMinutes');
      expect(r.nightAmount, equals(7500), reason: 'NIGHT-BREAK-03: nightAmount = 90×10000×0.5/60');
    });

    // nightIncluded=false regression: else 분기 미변경 확인
    // 계약 14:00~22:00, 실제 14:00~23:00, break=60, nightIncluded=false
    // rawNightMinutes(14:00~23:00) = 60 (22:00~23:00)
    // dayPortion=480, breakInNight=0 → nightMinutes=60
    test('nightIncluded=false regression: else 분기 동작 확인 → nightMinutes=60', () {
      final r = WageCalculator.calculate(
        wageType: 'daily', baseWage: 96000, workDate: _d,
        scheduledStart: '14:00', scheduledEnd: '22:00',
        actualStart: '14:00', actualEnd: '23:00',
        breakMinutes: 60, scheduledBreakMinutes: 60,
        nightAllowanceApplied: true, nightIncluded: false,
        baseHourlyWage: 10000,
      );
      expect(r.nightMinutes, equals(60), reason: 'regression: nightMinutes');
      expect(r.nightAmount, equals(5000), reason: 'regression: nightAmount');
      // nightIncluded=false → snapshot은 false
      expect(r.nightIncluded, isFalse, reason: 'regression: nightIncluded snapshot');
    });
  });

  // ══════════════════════════════════════════════════════
  // Phase 6: Canonical Extra Work Breakdown
  // contractExcessMinutes  = max(0, workMinutes - scheduledWorkMins)
  // premiumOvertimeMinutes = max(0, workMinutes - 480)
  // extraWork15xMinutes    = min(contractExcess, premiumOvertime)
  // extraWork1xMinutes     = contractExcess - extraWork15x
  // ══════════════════════════════════════════════════════
  group('Phase 6: Canonical Extra Work Breakdown', () {
    // CANON-01: scheduled paid=330, actual paid=390, break=0
    // contractExcess=60, premiumOvertime=0, extra1x=60, extra15x=0
    test('CANON-01: scheduled=330, actual=390 → extra1x=60, extra15x=0', () {
      final r = WageCalculator.calculate(
        wageType: 'hourly', baseWage: 10000, workDate: _d,
        scheduledStart: '09:00', scheduledEnd: '14:30',
        actualStart: '09:00', actualEnd: '15:30',
        breakMinutes: 0, nightAllowanceApplied: false,
      );
      expect(r.contractExcessMinutes, equals(60));
      expect(r.premiumOvertimeMinutes, equals(0));
      expect(r.extraWork15xMinutes, equals(0));
      expect(r.extraWork1xMinutes, equals(60));
      expect(r.hasCanonicalExtraWorkBreakdown, isTrue);
    });

    // CANON-02: scheduled paid=330, actual paid=480, break=0
    // contractExcess=150, premiumOvertime=0, extra1x=150, extra15x=0
    test('CANON-02: scheduled=330, actual=480 → extra1x=150, extra15x=0', () {
      final r = WageCalculator.calculate(
        wageType: 'hourly', baseWage: 10000, workDate: _d,
        scheduledStart: '09:00', scheduledEnd: '14:30',
        actualStart: '09:00', actualEnd: '17:00',
        breakMinutes: 0, nightAllowanceApplied: false,
      );
      expect(r.contractExcessMinutes, equals(150));
      expect(r.premiumOvertimeMinutes, equals(0));
      expect(r.extraWork15xMinutes, equals(0));
      expect(r.extraWork1xMinutes, equals(150));
      expect(r.hasCanonicalExtraWorkBreakdown, isTrue);
    });

    // CANON-03: scheduled paid=330, actual paid=510, break=0
    // contractExcess=180, premiumOvertime=30, extra1x=150, extra15x=30
    test('CANON-03: scheduled=330, actual=510 → extra1x=150, extra15x=30', () {
      final r = WageCalculator.calculate(
        wageType: 'hourly', baseWage: 10000, workDate: _d,
        scheduledStart: '09:00', scheduledEnd: '14:30',
        actualStart: '09:00', actualEnd: '17:30',
        breakMinutes: 0, nightAllowanceApplied: false,
      );
      expect(r.contractExcessMinutes, equals(180));
      expect(r.premiumOvertimeMinutes, equals(30));
      expect(r.extraWork15xMinutes, equals(30));
      expect(r.extraWork1xMinutes, equals(150));
      expect(r.hasCanonicalExtraWorkBreakdown, isTrue);
    });

    // CANON-04: scheduled paid=480, actual paid=510, break=0
    // contractExcess=30, premiumOvertime=30, extra1x=0, extra15x=30
    test('CANON-04: scheduled=480, actual=510 → extra1x=0, extra15x=30', () {
      final r = WageCalculator.calculate(
        wageType: 'hourly', baseWage: 10000, workDate: _d,
        scheduledStart: '09:00', scheduledEnd: '17:00',
        actualStart: '09:00', actualEnd: '17:30',
        breakMinutes: 0, nightAllowanceApplied: false,
      );
      expect(r.contractExcessMinutes, equals(30));
      expect(r.premiumOvertimeMinutes, equals(30));
      expect(r.extraWork15xMinutes, equals(30));
      expect(r.extraWork1xMinutes, equals(0));
      expect(r.hasCanonicalExtraWorkBreakdown, isTrue);
    });

    // CANON-05: DAILY 9h계약 정시근무 — scheduled=540, actual=540, break=0
    // contractExcess=0, premiumOvertime=60(540-480), extra1x=0, extra15x=0
    // (초과분 없으므로 분류할 extraWork 없음 — 9h 기본임금에 이미 포함)
    test('CANON-05: DAILY scheduled=540, actual=540 → contractExcess=0, premiumOvertime=60, extra1x=0, extra15x=0', () {
      final r = WageCalculator.calculate(
        wageType: 'daily', baseWage: 150000, workDate: _d,
        scheduledStart: '09:00', scheduledEnd: '18:00',
        actualStart: '09:00', actualEnd: '18:00',
        breakMinutes: 0, nightAllowanceApplied: false,
      );
      expect(r.contractExcessMinutes, equals(0));
      expect(r.premiumOvertimeMinutes, equals(60));
      expect(r.extraWork15xMinutes, equals(0));
      expect(r.extraWork1xMinutes, equals(0));
      expect(r.hasCanonicalExtraWorkBreakdown, isTrue);
    });

    // CANON-06: DAILY 9h계약 1h초과 — scheduled=540, actual=600, break=0
    // contractExcess=60, premiumOvertime=120, extra1x=0, extra15x=60
    // (계약초과 60min 전부가 8h 초과 구간에 해당 → 모두 1.5x)
    test('CANON-06: DAILY scheduled=540, actual=600 → extra1x=0, extra15x=60', () {
      final r = WageCalculator.calculate(
        wageType: 'daily', baseWage: 150000, workDate: _d,
        scheduledStart: '09:00', scheduledEnd: '18:00',
        actualStart: '09:00', actualEnd: '19:00',
        breakMinutes: 0, nightAllowanceApplied: false,
      );
      expect(r.contractExcessMinutes, equals(60));
      expect(r.premiumOvertimeMinutes, equals(120));
      expect(r.extraWork15xMinutes, equals(60));
      expect(r.extraWork1xMinutes, equals(0));
      expect(r.hasCanonicalExtraWorkBreakdown, isTrue);
    });

    // CANON-07: DAILY 9h계약 미달 — scheduled=540, actual=510, break=0
    // contractExcess=0, premiumOvertime=30(510-480), extra1x=0, extra15x=0
    test('CANON-07: DAILY scheduled=540, actual=510 → contractExcess=0, premiumOvertime=30, extra1x=0, extra15x=0', () {
      final r = WageCalculator.calculate(
        wageType: 'daily', baseWage: 150000, workDate: _d,
        scheduledStart: '09:00', scheduledEnd: '18:00',
        actualStart: '09:30', actualEnd: '18:00',
        breakMinutes: 0, nightAllowanceApplied: false,
      );
      expect(r.contractExcessMinutes, equals(0));
      expect(r.premiumOvertimeMinutes, equals(30));
      expect(r.extraWork15xMinutes, equals(0));
      expect(r.extraWork1xMinutes, equals(0));
      expect(r.hasCanonicalExtraWorkBreakdown, isTrue);
    });

    // DAILY-9H-02 Regression (Phase 5.3에서 누락된 테스트)
    // scheduled: 09:00~19:00, break=60 → scheduledPaid=540
    // actual: 09:00~20:00, break=60 → actualPaid=600
    // contractExcess=60, premiumOvertime=120, extra15x=60, extra1x=0
    // suppW = max(round(150000/540*60), 10320) = max(16667, 10320) = 16667
    // 계약초과 60min 전부가 8h 초과 구간 → overtimeAmount = round(60×16667×1.5/60) = 25001
    // totalAmount = 150000 + 25001 = 175001
    test('DAILY-9H-02: scheduled paid=540, actual paid=600, 기존 monetary 유지', () {
      final r = WageCalculator.calculate(
        wageType: 'daily', baseWage: 150000, workDate: _d,
        scheduledStart: '09:00', scheduledEnd: '19:00',
        actualStart: '09:00', actualEnd: '20:00',
        breakMinutes: 60, nightAllowanceApplied: false,
      );
      // canonical breakdown
      expect(r.contractExcessMinutes, equals(60));
      expect(r.premiumOvertimeMinutes, equals(120));
      expect(r.extraWork15xMinutes, equals(60));
      expect(r.extraWork1xMinutes, equals(0));
      // monetary regression
      expect(r.overtimeAmount, equals(25001));
      expect(r.totalAmount, equals(175001));
    });

    // CANON-INVARIANT: 동일 paid → wageType 무관 canonical 동일
    // scheduled=480, actual=540, break=0
    // contractExcess=60, premiumOvertime=60
    test('CANON-INVARIANT: 동일 paid에서 wageType 무관 canonical 동일', () {
      final hourly = WageCalculator.calculate(
        wageType: 'hourly', baseWage: 10000, workDate: _d,
        scheduledStart: '09:00', scheduledEnd: '17:00',
        actualStart: '09:00', actualEnd: '18:00',
        breakMinutes: 0, nightAllowanceApplied: false,
      );
      final daily = WageCalculator.calculate(
        wageType: 'daily', baseWage: 80000, workDate: _d,
        scheduledStart: '09:00', scheduledEnd: '17:00',
        actualStart: '09:00', actualEnd: '18:00',
        breakMinutes: 0, nightAllowanceApplied: false,
      );
      expect(hourly.contractExcessMinutes, equals(daily.contractExcessMinutes));
      expect(hourly.premiumOvertimeMinutes, equals(daily.premiumOvertimeMinutes));
    });
  });
}
