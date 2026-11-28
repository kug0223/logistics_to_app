// [F293-WAGE-01 · 판정293 §C · 인계 §6–9] 하루 예상 금액 — 표시 전용 계산·서식의 의미 시험.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:ALfit/models/core/work_detail_data.dart';
import 'package:ALfit/utils/expected_daily_wage.dart';

ExpectedDailyWage _h(int? rate, String? s, String? e, int? brk) => ExpectedDailyWage.compute(
    wageType: 'hourly', rate: rate, startTime: s, endTime: e, breakMinutes: brk);

WorkDetailData _wd({String type = 'hourly', int wage = 11000, String s = '09:00', String e = '11:00', int brk = 0}) =>
    WorkDetailData(workType: '분류', wage: wage, wageType: type, requiredCount: 1, startTime: s, endTime: e,
        breakMinutes: brk);

void main() {
  group('EW-1 계산식', () {
    test('2시간 · 시급 11,000 → 하루 예상 22,000원 · 시급 11,000원', () {
      final r = _h(11000, '09:00', '11:00', 0);
      expect(r.kind, ExpectedWageKind.estimate);
      expect(r.amount, 22000);
      expect(r.netMinutes, 120);
      expect(ExpectedWageText.daily(r), '하루 예상 22,000원');
      expect(ExpectedWageText.rate(r), '시급 11,000원');
    });

    test('무급 휴게를 뺀다 — 9시간 체류 · 휴게 60분 → 88,000원', () {
      final r = _h(11000, '09:00', '18:00', 60);
      expect(r.stayMinutes, 540);
      expect(r.netMinutes, 480);
      expect(r.amount, 88000);
    });

    test('분 단위 반올림 — 원 단위 round(시급 × 순분 ÷ 60)', () {
      expect(_h(10001, '09:00', '09:07', 0).amount, (10001 * 7 / 60).round()); // 1166.78 → 1167
      expect(_h(10030, '09:00', '09:03', 0).amount, 502); // 501.5 → 502(반올림)
      expect(_h(9999, '09:00', '09:01', 0).amount, 167); // 166.65 → 167
    });

    test('8시간 초과도 기본 시급 1배 — 연장·야간 가산 0', () {
      final r = _h(10000, '20:00', '08:00', 0); // 12시간 · 야간 포함
      expect(r.amount, 120000, reason: '1.5배·야간 가산을 넣었다');
    });

    test('익일 종료는 종료 < 시작일 때만 +1,440 · 시작일 귀속', () {
      final r = _h(10000, '22:00', '06:00', 30);
      expect(r.stayMinutes, 480);
      expect(r.netMinutes, 450);
      expect(r.amount, 75000);
    });

    test('종료 = 시작은 24시간으로 만들지 않는다 → 확인 필요', () {
      final r = _h(10000, '09:00', '09:00', 0);
      expect(r.kind, ExpectedWageKind.needsCheck);
      expect(r.amount, isNull);
      expect(ExpectedWageText.daily(r), '예상 금액 확인 필요');
      expect(ExpectedWageText.rate(r), '시급 10,000원', reason: '시급 원값은 남긴다');
    });
  });

  group('EW-2 잘못된 값 · 모르는 조건 — 0원으로 만들지 않는다', () {
    final cases = <String, ExpectedDailyWage>{
      '시급 0': _h(0, '09:00', '11:00', 0),
      '시급 음수': _h(-1, '09:00', '11:00', 0),
      '시급 모름': _h(null, '09:00', '11:00', 0),
      '시각 형식 오류': _h(10000, '9:00', '11:00', 0),
      '시각 범위 오류': _h(10000, '24:00', '11:00', 0),
      '시각 모름': _h(10000, null, '11:00', 0),
      '휴게 모름(약속 null)': _h(10000, '09:00', '11:00', null),
      '음수 휴게': _h(10000, '09:00', '11:00', -10),
      '체류 이상 휴게': _h(10000, '09:00', '11:00', 120),
    };
    cases.forEach((name, r) {
      test(name, () {
        expect(r.kind, ExpectedWageKind.needsCheck);
        expect(r.amount, isNull);
        expect(ExpectedWageText.daily(r), '예상 금액 확인 필요');
      });
    });

    test('휴게 0(공고 정본에서 생략된 0)과 휴게 모름(null)은 다르다', () {
      expect(_h(10000, '09:00', '11:00', 0).isEstimate, isTrue);
      expect(_h(10000, '09:00', '11:00', null).isEstimate, isFalse);
    });

    test('공고 map 에 시각이 없으면 fromMap 기본 09–18 로 금액을 만들지 않는다', () {
      final wd = WorkDetailData.fromMap({'workType': '분류', 'wage': 10000, 'wageType': 'hourly', 'requiredCount': 1});
      expect(wd.startTime, '09:00', reason: '기본값은 그대로 들어간다(기존 계약)');
      expect(wd.scheduleFromSource, isFalse);
      expect(ExpectedDailyWage.forWorkDetail(wd).kind, ExpectedWageKind.needsCheck);
    });

    test('공고 map 의 휴게 부재 = 정상 0(정본 writer 가 0 을 생략)', () {
      final wd = WorkDetailData.fromMap(
          {'workType': '분류', 'wage': 11000, 'wageType': 'hourly', 'requiredCount': 1, 'startTime': '09:00', 'endTime': '11:00'});
      expect(ExpectedDailyWage.forWorkDetail(wd).amount, 22000);
    });

    test('공고 map 의 급여 유형이 없거나 모르면 시급이라 부르지 않는다', () {
      final wd = WorkDetailData.fromMap(
          {'workType': '분류', 'wage': 11000, 'requiredCount': 1, 'startTime': '09:00', 'endTime': '11:00'});
      expect(wd.wageType, 'hourly', reason: '모델 기본값은 그대로(기존 계약)');
      expect(wd.wageTypeFromSource, isFalse);
      final r = ExpectedDailyWage.forWorkDetail(wd);
      expect(r.kind, ExpectedWageKind.notHourly);
      expect(ExpectedWageText.rate(r), isNull);
    });

    test('일급 · 월급은 이 helper 가 금액을 만들지 않는다(기존 표시)', () {
      expect(ExpectedDailyWage.forWorkDetail(_wd(type: 'daily', wage: 120000)).kind, ExpectedWageKind.notHourly);
      expect(ExpectedDailyWage.forWorkDetail(_wd(type: 'monthly', wage: 2500000)).kind, ExpectedWageKind.notHourly);
      expect(ExpectedWageText.daily(ExpectedDailyWage.forWorkDetail(_wd(type: 'daily'))), isNull);
    });
  });

  group('EW-3 여러 업무 — 업무별 환산 뒤 범위', () {
    test('모두 같으면 단일 금액', () {
      final r = ExpectedWageRange.ofWorkDetails([_wd(), _wd()]);
      expect(ExpectedWageText.dailyRange(r), '하루 예상 22,000원');
      expect(ExpectedWageText.rateRange(r), '시급 11,000원');
    });

    test('같은 시급 · 다른 시간도 범위', () {
      final r = ExpectedWageRange.ofWorkDetails([_wd(), _wd(e: '13:00')]);
      expect(ExpectedWageText.dailyRange(r), '하루 예상 22,000~44,000원');
      expect(ExpectedWageText.rateRange(r), '시급 11,000원');
    });

    test('다른 시급 — 금액 범위는 업무별 환산의 min–max (시간폭 × 최고 시급 아님)', () {
      // A: 10,000 × 8h = 80,000 · B: 20,000 × 2h = 40,000 → 40,000~80,000 (20,000 × 8h = 160,000 이 아님)
      final r = ExpectedWageRange.ofWorkDetails(
          [_wd(wage: 10000, s: '09:00', e: '17:00'), _wd(wage: 20000, s: '09:00', e: '11:00')]);
      expect(ExpectedWageText.dailyRange(r), '하루 예상 40,000~80,000원');
      expect(ExpectedWageText.rateRange(r), '시급 10,000~20,000원');
    });

    test('범위 역전 0 — 높은 시급이 더 적은 금액이어도 min ≤ max', () {
      final r = ExpectedWageRange.ofWorkDetails(
          [_wd(wage: 30000, s: '09:00', e: '10:00'), _wd(wage: 10000, s: '09:00', e: '18:00')]);
      expect(r.minAmount, 30000);
      expect(r.maxAmount, 90000);
    });

    test('일부 업무 계산 불가 — 부분 범위를 완전한 범위처럼 말하지 않는다', () {
      final r = ExpectedWageRange.ofWorkDetails([_wd(), _wd(s: '09:00', e: '09:00')]);
      expect(r.complete, isFalse);
      expect(ExpectedWageText.dailyRange(r), '업무별 예상 금액 확인');
    });

    test('시급 · 일급 혼합 → 업무별 급여 확인 · 시급 범위도 말하지 않는다(유형 분리)', () {
      final r = ExpectedWageRange.ofWorkDetails([_wd(), _wd(type: 'daily', wage: 100000)]);
      expect(r.mixed, isTrue);
      expect(ExpectedWageText.dailyRange(r), '업무별 급여 확인');
      expect(ExpectedWageText.rateRange(r), isNull);
    });

    test('월급 포함 → 하루 환산하지 않는다', () {
      final r = ExpectedWageRange.ofWorkDetails([_wd(), _wd(type: 'monthly', wage: 2500000)]);
      expect(ExpectedWageText.dailyRange(r), '업무별 급여 확인');
    });

    test('시급 업무가 없으면 null(기존 표시 유지)', () {
      expect(ExpectedWageText.dailyRange(ExpectedWageRange.ofWorkDetails([_wd(type: 'daily')])), isNull);
      expect(ExpectedWageText.dailyRange(ExpectedWageRange.ofWorkDetails(const [])), isNull);
    });
  });

  group('EW-4 지원 확인 선택 합계', () {
    test('근무별 반올림 금액의 합 · 하루라고 부르지 않는다', () {
      final a = _h(10001, '09:00', '09:07', 0); // 1,167
      final b = _h(10001, '09:00', '09:07', 0); // 1,167
      final t = ExpectedWageText.selectedTotal([a, b]);
      expect(t, '선택한 근무 예상 합계 2,334원', reason: '합친 뒤 반올림(2,333)이 아니라 근무별 반올림의 합');
      expect(t!.contains('하루'), isFalse);
    });

    test('하나라도 금액이 없으면 합계를 만들지 않는다 · 1건은 합계 없음', () {
      expect(ExpectedWageText.selectedTotal([_h(10000, '09:00', '11:00', 0), _h(10000, '09:00', '09:00', 0)]), isNull);
      expect(ExpectedWageText.selectedTotal([_h(10000, '09:00', '11:00', 0)]), isNull);
    });
  });

  group('EW-5 약속 조건 vs 표시 시각 · 확정 급여 보호', () {
    test('약속 금액·휴게 + 화면이 보여 주는 시각으로 계산(표시 시각 = 계산 입력)', () {
      // 지원서 약속: 시급 10,000 · 휴게 30 · 화면은 live 시각 10:00–14:00 을 보여 준다.
      final shown = ExpectedDailyWage.forPromise(
          wageType: 'hourly', rate: 10000, startTime: '10:00', endTime: '14:00', breakMinutes: 30);
      expect(shown.amount, 35000);
      expect(ExpectedWageText.netTime(shown.netMinutes), '실근무 3시간 30분');
    });

    test('약속 휴게 null 은 0 으로 만들지 않는다', () {
      final r = ExpectedDailyWage.forPromise(
          wageType: 'hourly', rate: 10000, startTime: '10:00', endTime: '14:00', breakMinutes: null);
      expect(r.kind, ExpectedWageKind.needsCheck);
    });

    test('helper 는 확정 급여 엔진을 부르지 않는다(가산 자동 주입 0) · 확정 값을 바꾸지 않는다', () {
      final src = File('lib/utils/expected_daily_wage.dart').readAsStringSync();
      final code = src.split('\n').where((l) => !l.trimLeft().startsWith('///') && !l.trimLeft().startsWith('//')).join('\n');
      for (final banned in ['wage_calculator', 'WageCalculator', 'overtimeRate', 'nightRate', '1.5']) {
        expect(code.contains(banned), isFalse, reason: banned);
      }
    });
  });

  // [F294-WAGE-01 · 판정294 §3] 유형 모름 · 비시급 혼합 · 누락 단가 · 일정 상세 단계 판정.
  group('EW-8 유형 출처 · 비시급 혼합 · 누락 단가(F294)', () {
    WorkDetailData noType({int wage = 11000}) => WorkDetailData.fromMap(
        {'workType': '분류', 'wage': wage, 'requiredCount': 1, 'startTime': '09:00', 'endTime': '11:00'});

    test('A1 유형 모름 업무 하나 — 시급으로 돌아가지 않고 \'급여 확인 필요\'', () {
      final e = ExpectedDailyWage.forWorkDetail(noType());
      expect(e.typeUnknown, isTrue);
      expect(ExpectedWageText.daily(e), '급여 확인 필요');
      expect(ExpectedWageText.combined(e), '급여 확인 필요');
      expect(ExpectedWageText.rate(e), isNull);
      final r = ExpectedWageRange.ofWorkDetails([noType()]);
      expect(r.mixed, isTrue);
      expect(ExpectedWageText.dailyRange(r), '급여 확인 필요');
      expect(ExpectedWageText.rateRange(r), isNull);
    });

    test('A2 지원하지 않는 유형 문자열(weekly) 도 유형 모름', () {
      final e = ExpectedDailyWage.compute(
          wageType: 'weekly', rate: 50000, startTime: '09:00', endTime: '18:00', breakMinutes: 60);
      expect(e.typeUnknown, isTrue);
      expect(ExpectedWageText.combined(e), '급여 확인 필요');
    });

    test('A3 유형 모름 + 시급 업무 → 업무별 급여 확인(시급 범위 0)', () {
      final r = ExpectedWageRange.ofWorkDetails([_wd(), noType()]);
      expect(r.unknownType, 1);
      expect(ExpectedWageText.dailyRange(r), '업무별 급여 확인');
      expect(ExpectedWageText.rateRange(r), isNull);
    });

    test('B1 일급 + 월급 → 한 단위 범위로 합치지 않는다(업무별 급여 확인)', () {
      final r = ExpectedWageRange.ofWorkDetails(
          [_wd(type: 'daily', wage: 100000), _wd(type: 'monthly', wage: 2500000)]);
      expect(r.knownTypes, 2);
      expect(r.mixed, isTrue);
      expect(ExpectedWageText.dailyRange(r), '업무별 급여 확인');
    });

    test('B2 같은 비시급 유형만 → null(기존 표시 · 같은 단위의 금액)', () {
      final r = ExpectedWageRange.ofWorkDetails(
          [_wd(type: 'daily', wage: 100000), _wd(type: 'daily', wage: 120000)]);
      expect(r.mixed, isFalse);
      expect(ExpectedWageText.dailyRange(r), isNull);
    });

    test('C1 누락 단가(모델 0) — rawWage 는 \'0원\' 을 만들지 않는다', () {
      expect(ExpectedWageText.rawWage(0), '급여 확인 필요');
      expect(ExpectedWageText.rawWage(-1), '급여 확인 필요');
      expect(ExpectedWageText.rawWage(11000), '11,000원');
      final wd = WorkDetailData.fromMap(
          {'workType': '분류', 'wageType': 'hourly', 'requiredCount': 1, 'startTime': '09:00', 'endTime': '11:00'});
      expect(wd.wage, 0, reason: '모델 기본값은 그대로(기존 계약)');
      final e = ExpectedDailyWage.forWorkDetail(wd);
      expect(e.kind, ExpectedWageKind.needsCheck);
      expect(e.rate, isNull);
      expect(ExpectedWageText.combined(e), '예상 금액 확인 필요');
      expect(ExpectedWageText.combined(e)!.contains('0원'), isFalse);
    });

    test('C2 비시급 누락 단가는 rate 를 남기지 않는다', () {
      final e = ExpectedDailyWage.compute(
          wageType: 'daily', rate: 0, startTime: '09:00', endTime: '18:00', breakMinutes: 60);
      expect(e.rate, isNull);
      expect(e.typeUnknown, isFalse);
    });

    test('C3 레거시 지원서 유형 null — 유형 모름으로 바꾸지 않는다(예전 단위 없는 금액)', () {
      final e = ExpectedDailyWage.forPromise(
          wageType: null, rate: 11000, startTime: '09:00', endTime: '11:00', breakMinutes: 0);
      expect(e.kind, ExpectedWageKind.notHourly);
      expect(e.typeUnknown, isFalse);
      expect(ExpectedWageText.combined(e), isNull);
    });
  });

  group('EW-7 한 줄 요약', () {
    test('주금액 먼저 · 시급 보조 · 확인 필요 · 시급 아님', () {
      expect(ExpectedWageText.combined(_h(11000, '09:00', '11:00', 0)), '하루 예상 22,000원 · 시급 11,000원');
      expect(ExpectedWageText.combined(_h(11000, '09:00', '09:00', 0)), '시급 11,000원 · 예상 금액 확인 필요');
      expect(ExpectedWageText.combined(_h(null, '09:00', '11:00', 0)), '예상 금액 확인 필요');
      expect(ExpectedWageText.combined(ExpectedDailyWage.compute(
          wageType: 'daily', rate: 100000, startTime: '09:00', endTime: '18:00', breakMinutes: 60)), isNull);
    });
  });

  group('EW-6 문구 정본', () {
    test('고지 · 짧은 말', () {
      expect(ExpectedWageText.disclosure,
          '등록된 시급과 근무시간에서 무급 휴게를 뺀 세전 예상 금액이에요. 별도 수당을 추가 계산하거나 공제를 차감하지 않았어요. 최종 급여는 실제 근무와 급여 확정 내역에 따라 달라져요.');
      expect(ExpectedWageText.shortNote, '예상·세전');
    });

    test('실근무 시간 보조는 같은 분 계산', () {
      expect(ExpectedWageText.netTime(_h(10000, '09:00', '11:00', 0).netMinutes), '실근무 2시간');
      expect(ExpectedWageText.netTime(_h(10000, '09:00', '09:00', 0).netMinutes), isNull);
    });
  });
}
