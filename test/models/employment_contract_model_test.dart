import 'package:flutter_test/flutter_test.dart';
import 'package:ALfit/models/core/employment_contract_model.dart';
import 'package:ALfit/models/core/contract_template_model.dart';
import 'package:ALfit/models/core/insurance_rate_model.dart';

// ─────────────────────────────────────────────────────────────────────────────
// 헬퍼: 기본 ContractSnapshot 생성
// ─────────────────────────────────────────────────────────────────────────────

ContractSnapshot _snap({
  String startTime = '09:00',
  String endTime = '18:00',
  int breakMinutes = 0,
  int wage = 10000,
  String wageType = 'hourly',
  int? baseHourlyWage,
  String? payScheduleType,
  int? payScheduleDay,
  String? payScheduleTime,
  int? wagePaymentDay,
  bool isLongTerm = false,
  String? contractStart,
  String? contractEnd,
  List<String>? workDays,
  String taxDeductionType = InsuranceRateModel.typeNone,
}) =>
    ContractSnapshot(
      businessName: '테스트 사업장',
      businessNumber: '123-45-67890',
      businessAddress: '서울시 강남구',
      ownerName: '홍길동',
      workerName: '김직원',
      workType: '피킹',
      workPlace: '서울 물류센터',
      isLongTerm: isLongTerm,
      startTime: startTime,
      endTime: endTime,
      breakMinutes: breakMinutes,
      wage: wage,
      wageType: wageType,
      baseHourlyWage: baseHourlyWage,
      payScheduleType: payScheduleType,
      payScheduleDay: payScheduleDay,
      payScheduleTime: payScheduleTime,
      wagePaymentDay: wagePaymentDay,
      paymentMethod: '계좌이체',
      contractStart: contractStart,
      contractEnd: contractEnd,
      workDays: workDays,
      taxDeductionType: taxDeductionType,
    );

// 기본 EmploymentContractModel 생성
EmploymentContractModel _contract({
  ContractStatus status = ContractStatus.pendingEmployer,
  bool isLongTerm = false,
  List<ContractSlot> slots = const [],
  List<String> applicationIds = const [],
  String? employerSignatureUrl,
  String? workerSignatureUrl,
  String? pdfUrl,
  List<ContractArticle> articles = const [],
  String? templateId,
  ContractSnapshot? snapshot,
}) =>
    EmploymentContractModel(
      id: 'contract1',
      applicationId: 'app1',
      businessId: 'biz1',
      workerId: 'user1',
      isLongTerm: isLongTerm,
      toId: 'to1',
      workDetailId: 'wd1',
      slots: slots,
      applicationIds: applicationIds,
      status: status,
      employerSignatureUrl: employerSignatureUrl,
      workerSignatureUrl: workerSignatureUrl,
      pdfUrl: pdfUrl,
      snapshot: snapshot ?? _snap(),
      articles: articles,
      templateId: templateId,
      createdAt: DateTime(2025, 1, 1),
    );

void main() {
  // ===========================================================================
  // A. ContractStatus enum — value, label, fromString (35+ 케이스)
  // ===========================================================================
  group('A: ContractStatus enum', () {
    // ── A-1. value getter ────────────────────────────────────────────────────
    test('A-01 pendingEmployer.value = pending_employer', () {
      expect(ContractStatus.pendingEmployer.value, 'pending_employer');
    });
    test('A-02 pendingWorker.value = pending_worker', () {
      expect(ContractStatus.pendingWorker.value, 'pending_worker');
    });
    test('A-03 completed.value = completed', () {
      expect(ContractStatus.completed.value, 'completed');
    });
    test('A-04 voided.value = voided', () {
      expect(ContractStatus.voided.value, 'voided');
    });

    // ── A-2. label getter ────────────────────────────────────────────────────
    test('A-10 pendingEmployer.label = 사업주 서명 대기', () {
      expect(ContractStatus.pendingEmployer.label, '사업주 서명 대기');
    });
    test('A-11 pendingWorker.label = 근무자 서명 대기', () {
      expect(ContractStatus.pendingWorker.label, '근무자 서명 대기');
    });
    test('A-12 completed.label = 계약 완료', () {
      expect(ContractStatus.completed.label, '계약 완료');
    });
    test('A-13 voided.label = 무효', () {
      expect(ContractStatus.voided.label, '무효');
    });

    // ── A-3. fromString ──────────────────────────────────────────────────────
    test('A-20 fromString(pending_employer) → pendingEmployer', () {
      expect(ContractStatusX.fromString('pending_employer'), ContractStatus.pendingEmployer);
    });
    test('A-21 fromString(pending_worker) → pendingWorker', () {
      expect(ContractStatusX.fromString('pending_worker'), ContractStatus.pendingWorker);
    });
    test('A-22 fromString(completed) → completed', () {
      expect(ContractStatusX.fromString('completed'), ContractStatus.completed);
    });
    test('A-23 fromString(voided) → voided', () {
      expect(ContractStatusX.fromString('voided'), ContractStatus.voided);
    });
    test('A-24 fromString(unknown) → pendingEmployer (default)', () {
      expect(ContractStatusX.fromString('unknown'), ContractStatus.pendingEmployer);
    });
    test('A-25 fromString 빈 문자열 → pendingEmployer (default)', () {
      expect(ContractStatusX.fromString(''), ContractStatus.pendingEmployer);
    });
    test('A-26 fromString 대문자(COMPLETED) → pendingEmployer (default, case-sensitive)', () {
      expect(ContractStatusX.fromString('COMPLETED'), ContractStatus.pendingEmployer);
    });
    test('A-27 모든 enum 값을 value → fromString 왕복 가능', () {
      for (final s in ContractStatus.values) {
        expect(ContractStatusX.fromString(s.value), s);
      }
    });
    test('A-28 enum values 4개', () {
      expect(ContractStatus.values.length, 4);
    });
    test('A-29 values에 4가지 상태 모두 포함', () {
      expect(ContractStatus.values.contains(ContractStatus.pendingEmployer), true);
      expect(ContractStatus.values.contains(ContractStatus.pendingWorker), true);
      expect(ContractStatus.values.contains(ContractStatus.completed), true);
      expect(ContractStatus.values.contains(ContractStatus.voided), true);
    });
  });

  // ===========================================================================
  // B. ContractSnapshot._timeDiff (간접 테스트) — workTimeText 경유 (50+ 케이스)
  // ===========================================================================
  group('B: ContractSnapshot._timeDiff (간접)', () {
    // ── B-1. 정상 주간 시프트 ────────────────────────────────────────────────
    test('B-01 09:00~18:00 break=0 → 9h', () {
      expect(_snap().workTimeText, '09:00 ~ 18:00 · 9h');
    });
    test('B-02 09:00~18:00 break=60 → 8h (휴게60분)', () {
      expect(_snap(breakMinutes: 60).workTimeText, '09:00 ~ 18:00 (휴게 60분) · 8h');
    });
    test('B-03 08:00~17:00 break=0 → 9h', () {
      expect(_snap(startTime: '08:00', endTime: '17:00').workTimeText, '08:00 ~ 17:00 · 9h');
    });
    test('B-04 09:00~13:00 break=0 → 4h', () {
      expect(_snap(startTime: '09:00', endTime: '13:00').workTimeText, '09:00 ~ 13:00 · 4h');
    });
    test('B-05 09:00~13:30 break=0 → 4.5h', () {
      expect(_snap(startTime: '09:00', endTime: '13:30').workTimeText, '09:00 ~ 13:30 · 4.5h');
    });
    test('B-06 10:00~11:30 break=0 → 1.5h', () {
      expect(_snap(startTime: '10:00', endTime: '11:30').workTimeText, '10:00 ~ 11:30 · 1.5h');
    });
    test('B-07 09:00~18:00 break=30 → 8.5h', () {
      expect(_snap(breakMinutes: 30).workTimeText, '09:00 ~ 18:00 (휴게 30분) · 8.5h');
    });
    test('B-08 09:00~18:00 break=90 → 7.5h', () {
      expect(_snap(breakMinutes: 90).workTimeText, '09:00 ~ 18:00 (휴게 90분) · 7.5h');
    });
    test('B-09 09:00~18:00 break=120 → 7h', () {
      expect(_snap(breakMinutes: 120).workTimeText, '09:00 ~ 18:00 (휴게 120분) · 7h');
    });

    // ── B-2. 야간 시프트 ─────────────────────────────────────────────────────
    test('B-20 22:00~06:00 break=0 → 8h', () {
      expect(_snap(startTime: '22:00', endTime: '06:00').workTimeText, '22:00 ~ 06:00 · 8h');
    });
    test('B-21 22:00~02:00 break=0 → 4h', () {
      expect(_snap(startTime: '22:00', endTime: '02:00').workTimeText, '22:00 ~ 02:00 · 4h');
    });
    test('B-22 21:00~03:00 break=0 → 6h', () {
      expect(_snap(startTime: '21:00', endTime: '03:00').workTimeText, '21:00 ~ 03:00 · 6h');
    });
    test('B-23 23:00~01:00 break=0 → 2h', () {
      expect(_snap(startTime: '23:00', endTime: '01:00').workTimeText, '23:00 ~ 01:00 · 2h');
    });
    test('B-24 23:30~00:30 break=0 → 1h', () {
      expect(_snap(startTime: '23:30', endTime: '00:30').workTimeText, '23:30 ~ 00:30 · 1h');
    });
    test('B-25 22:00~06:00 break=60 → 7h (휴게60분)', () {
      expect(_snap(startTime: '22:00', endTime: '06:00', breakMinutes: 60).workTimeText,
          '22:00 ~ 06:00 (휴게 60분) · 7h');
    });
    test('B-26 20:00~04:00 break=0 → 8h', () {
      expect(_snap(startTime: '20:00', endTime: '04:00').workTimeText, '20:00 ~ 04:00 · 8h');
    });
    test('B-27 00:00~08:00 break=0 → 8h (새벽)', () {
      expect(_snap(startTime: '00:00', endTime: '08:00').workTimeText, '00:00 ~ 08:00 · 8h');
    });

    // ── B-3. 분 단위 정밀 ───────────────────────────────────────────────────
    test('B-30 09:00~09:10 break=0 → 0.2h (소수점 1자리)', () {
      // 10분 = 10/60 = 0.16...666h → toStringAsFixed(1) = '0.2'
      expect(_snap(startTime: '09:00', endTime: '09:10').workTimeText, '09:00 ~ 09:10 · 0.2h');
    });
    test('B-31 09:00~09:20 break=0 → 0.3h', () {
      // 20분 = 20/60 = 0.333h → '0.3'
      expect(_snap(startTime: '09:00', endTime: '09:20').workTimeText, '09:00 ~ 09:20 · 0.3h');
    });
    test('B-32 09:00~10:40 break=10 → 1.5h', () {
      // 100분 - 10 = 90분 = 1.5h → 정수 아님이지만 1.5h 표시
      expect(_snap(startTime: '09:00', endTime: '10:40', breakMinutes: 10).workTimeText,
          '09:00 ~ 10:40 (휴게 10분) · 1.5h');
    });
    test('B-33 09:00~18:00 break=0 → 휴게 없으면 breakText 없음', () {
      final text = _snap(breakMinutes: 0).workTimeText;
      expect(text.contains('휴게'), false);
    });
    test('B-34 09:00~18:00 break=1 → 휴게 1분 포함', () {
      final text = _snap(breakMinutes: 1).workTimeText;
      expect(text.contains('(휴게 1분)'), true);
    });

    // ── B-4. 경계값 ──────────────────────────────────────────────────────────
    test('B-40 같은 시작/종료 09:00~09:00 → em=sm → diff=0 → workMins=0 → 0.0h', () {
      // h = 0.0/60 = 0 → 정수이므로 '0h'
      expect(_snap(startTime: '09:00', endTime: '09:00').workTimeText, '09:00 ~ 09:00 · 0h');
    });
    test('B-41 00:00~00:00 → diff=0 → 0h', () {
      expect(_snap(startTime: '00:00', endTime: '00:00').workTimeText, '00:00 ~ 00:00 · 0h');
    });
    test('B-42 09:00~18:00 break=540 → workMins=0 → 0h', () {
      expect(_snap(breakMinutes: 540).workTimeText, '09:00 ~ 18:00 (휴게 540분) · 0h');
    });
  });

  // ===========================================================================
  // C. ContractSnapshot.hourlyWage (55+ 케이스)
  // ===========================================================================
  group('C: ContractSnapshot.hourlyWage', () {
    // ── C-1. baseHourlyWage 우선 ─────────────────────────────────────────────
    test('C-01 baseHourlyWage=12000 → 12000 (우선)', () {
      expect(_snap(baseHourlyWage: 12000, wageType: 'hourly', wage: 10000).hourlyWage, 12000);
    });
    test('C-02 baseHourlyWage=10320 (최저시급 2026) → 10320', () {
      expect(_snap(baseHourlyWage: 10320).hourlyWage, 10320);
    });
    test('C-03 baseHourlyWage=0 → 0 이하 → wage 계산으로 폴백 (hourly)', () {
      expect(_snap(baseHourlyWage: 0, wageType: 'hourly', wage: 10000).hourlyWage, 10000);
    });
    test('C-04 baseHourlyWage=null, wageType=hourly → wage 사용', () {
      expect(_snap(baseHourlyWage: null, wageType: 'hourly', wage: 15000).hourlyWage, 15000);
    });
    test('C-05 baseHourlyWage 있고 daily → baseHourlyWage 반환', () {
      expect(_snap(baseHourlyWage: 11000, wageType: 'daily', wage: 80000).hourlyWage, 11000);
    });
    test('C-06 baseHourlyWage 있고 monthly → baseHourlyWage 반환', () {
      expect(_snap(baseHourlyWage: 10320, wageType: 'monthly', wage: 2000000).hourlyWage, 10320);
    });

    // ── C-2. wageType=hourly ─────────────────────────────────────────────────
    test('C-10 hourly wage=10000 → 10000', () {
      expect(_snap(wageType: 'hourly', wage: 10000).hourlyWage, 10000);
    });
    test('C-11 hourly wage=10320 (최저시급) → 10320', () {
      expect(_snap(wageType: 'hourly', wage: 10320).hourlyWage, 10320);
    });
    test('C-12 hourly wage=15000 → 15000', () {
      expect(_snap(wageType: 'hourly', wage: 15000).hourlyWage, 15000);
    });
    test('C-13 hourly wage=0 → 0', () {
      expect(_snap(wageType: 'hourly', wage: 0).hourlyWage, 0);
    });

    // ── C-3. wageType=daily ─────────────────────────────────────────────────
    test('C-20 daily 09:00~18:00 break=0 wage=90000 → 90000/9h=10000', () {
      expect(_snap(wageType: 'daily', startTime: '09:00', endTime: '18:00',
          breakMinutes: 0, wage: 90000).hourlyWage, 10000);
    });
    test('C-21 daily 09:00~18:00 break=60 wage=80000 → 80000/8h=10000', () {
      expect(_snap(wageType: 'daily', startTime: '09:00', endTime: '18:00',
          breakMinutes: 60, wage: 80000).hourlyWage, 10000);
    });
    test('C-22 daily 09:00~13:00 break=0 wage=40000 → 40000/4h=10000', () {
      expect(_snap(wageType: 'daily', startTime: '09:00', endTime: '13:00',
          breakMinutes: 0, wage: 40000).hourlyWage, 10000);
    });
    test('C-23 daily 09:00~13:00 break=0 wage=45000 → 45000/4h=11250', () {
      expect(_snap(wageType: 'daily', startTime: '09:00', endTime: '13:00',
          breakMinutes: 0, wage: 45000).hourlyWage, 11250);
    });
    test('C-24 daily 09:00~18:00 break=0 wage=100000 → round(100000/9)=11111', () {
      // 9h = 540min. 100000/9.0 = 11111.111... → round = 11111
      expect(_snap(wageType: 'daily', startTime: '09:00', endTime: '18:00',
          breakMinutes: 0, wage: 100000).hourlyWage, 11111);
    });
    test('C-25 daily 09:00~18:30 break=30 wage=80000 → workMins=540(9h) → round(80000/9)=8889', () {
      // 570min - 30 = 540min = 9h. 80000/9 = 8888.8... → round = 8889
      expect(_snap(wageType: 'daily', startTime: '09:00', endTime: '18:30',
          breakMinutes: 30, wage: 80000).hourlyWage, 8889);
    });
    test('C-26 daily 야간 22:00~06:00 break=0 wage=80000 → 80000/8h=10000', () {
      expect(_snap(wageType: 'daily', startTime: '22:00', endTime: '06:00',
          breakMinutes: 0, wage: 80000).hourlyWage, 10000);
    });
    test('C-27 daily workMins=0 (09:00~09:00) → null', () {
      expect(_snap(wageType: 'daily', startTime: '09:00', endTime: '09:00',
          breakMinutes: 0, wage: 80000).hourlyWage, null);
    });
    test('C-28 daily break > workTime (workMins<0→) null', () {
      // break=600 > 540min (09:00~18:00) → workMins = 540-600 = -60 → <=0 → null
      expect(_snap(wageType: 'daily', breakMinutes: 600, wage: 80000).hourlyWage, null);
    });
    test('C-29 daily 09:00~13:30 break=0 wage=45000 → 45000/4.5h=10000', () {
      expect(_snap(wageType: 'daily', startTime: '09:00', endTime: '13:30',
          breakMinutes: 0, wage: 45000).hourlyWage, 10000);
    });
    test('C-30 daily 09:00~13:30 break=30 wage=40000 → 40000/4h=10000', () {
      expect(_snap(wageType: 'daily', startTime: '09:00', endTime: '13:30',
          breakMinutes: 30, wage: 40000).hourlyWage, 10000);
    });
    test('C-31 daily wage=75000 09:00~15:00 break=0 → 75000/6h=12500', () {
      expect(_snap(wageType: 'daily', startTime: '09:00', endTime: '15:00',
          breakMinutes: 0, wage: 75000).hourlyWage, 12500);
    });

    // ── C-4. wageType=monthly → null ────────────────────────────────────────
    test('C-40 monthly → null', () {
      expect(_snap(wageType: 'monthly', wage: 2000000).hourlyWage, null);
    });
    test('C-41 monthly + baseHourlyWage=0 → null', () {
      expect(_snap(wageType: 'monthly', wage: 2000000, baseHourlyWage: 0).hourlyWage, null);
    });

    // ── C-5. formattedHourlyWage ─────────────────────────────────────────────
    test('C-50 hourly wage=10000 → "10,000원/시간"', () {
      expect(_snap(wageType: 'hourly', wage: 10000).formattedHourlyWage, '10,000원/시간');
    });
    test('C-51 monthly → "-"', () {
      expect(_snap(wageType: 'monthly', wage: 2000000).formattedHourlyWage, '-');
    });
    test('C-52 daily workMins=0 → "-"', () {
      expect(_snap(wageType: 'daily', startTime: '09:00', endTime: '09:00').formattedHourlyWage, '-');
    });
    test('C-53 baseHourlyWage=12000 → "12,000원/시간"', () {
      expect(_snap(baseHourlyWage: 12000).formattedHourlyWage, '12,000원/시간');
    });
    test('C-54 hourly wage=10320 → "10,320원/시간"', () {
      expect(_snap(wageType: 'hourly', wage: 10320).formattedHourlyWage, '10,320원/시간');
    });
    test('C-55 daily 80000/8h=10000 → "10,000원/시간"', () {
      expect(_snap(wageType: 'daily', startTime: '09:00', endTime: '18:00',
          breakMinutes: 60, wage: 80000).formattedHourlyWage, '10,000원/시간');
    });
  });

  // ===========================================================================
  // D. ContractSnapshot.payScheduleLabel (55+ 케이스)
  // ===========================================================================
  group('D: ContractSnapshot.payScheduleLabel', () {
    // ── D-1. same_day ────────────────────────────────────────────────────────
    test('D-01 same_day, time=null → "당일"', () {
      expect(_snap(payScheduleType: 'same_day').payScheduleLabel, '당일');
    });
    test('D-02 same_day, time=09:00 → "당일 09:00"', () {
      expect(_snap(payScheduleType: 'same_day', payScheduleTime: '09:00').payScheduleLabel, '당일 09:00');
    });
    test('D-03 same_day, time=18:00 → "당일 18:00"', () {
      expect(_snap(payScheduleType: 'same_day', payScheduleTime: '18:00').payScheduleLabel, '당일 18:00');
    });
    test('D-04 same_day, time=00:00 → "당일 00:00"', () {
      expect(_snap(payScheduleType: 'same_day', payScheduleTime: '00:00').payScheduleLabel, '당일 00:00');
    });

    // ── D-2. next_day ────────────────────────────────────────────────────────
    test('D-10 next_day, time=null → "익일"', () {
      expect(_snap(payScheduleType: 'next_day').payScheduleLabel, '익일');
    });
    test('D-11 next_day, time=10:00 → "익일 10:00"', () {
      expect(_snap(payScheduleType: 'next_day', payScheduleTime: '10:00').payScheduleLabel, '익일 10:00');
    });
    test('D-12 next_day, time=23:59 → "익일 23:59"', () {
      expect(_snap(payScheduleType: 'next_day', payScheduleTime: '23:59').payScheduleLabel, '익일 23:59');
    });

    // ── D-3. weekly (payScheduleDay 1~7 = 월~일) ─────────────────────────────
    test('D-20 weekly day=1 time=null → "매주 월요일"', () {
      expect(_snap(payScheduleType: 'weekly', payScheduleDay: 1).payScheduleLabel, '매주 월요일');
    });
    test('D-21 weekly day=2 → "매주 화요일"', () {
      expect(_snap(payScheduleType: 'weekly', payScheduleDay: 2).payScheduleLabel, '매주 화요일');
    });
    test('D-22 weekly day=3 → "매주 수요일"', () {
      expect(_snap(payScheduleType: 'weekly', payScheduleDay: 3).payScheduleLabel, '매주 수요일');
    });
    test('D-23 weekly day=4 → "매주 목요일"', () {
      expect(_snap(payScheduleType: 'weekly', payScheduleDay: 4).payScheduleLabel, '매주 목요일');
    });
    test('D-24 weekly day=5 → "매주 금요일"', () {
      expect(_snap(payScheduleType: 'weekly', payScheduleDay: 5).payScheduleLabel, '매주 금요일');
    });
    test('D-25 weekly day=6 → "매주 토요일"', () {
      expect(_snap(payScheduleType: 'weekly', payScheduleDay: 6).payScheduleLabel, '매주 토요일');
    });
    test('D-26 weekly day=7 → "매주 일요일"', () {
      expect(_snap(payScheduleType: 'weekly', payScheduleDay: 7).payScheduleLabel, '매주 일요일');
    });
    test('D-27 weekly day=null → clamp(1,7) 기본값 1 → "매주 월요일"', () {
      expect(_snap(payScheduleType: 'weekly', payScheduleDay: null).payScheduleLabel, '매주 월요일');
    });
    test('D-28 weekly day=0 → clamp(1,7)=1 → "매주 월요일"', () {
      expect(_snap(payScheduleType: 'weekly', payScheduleDay: 0).payScheduleLabel, '매주 월요일');
    });
    test('D-29 weekly day=8 → clamp(1,7)=7 → "매주 일요일"', () {
      expect(_snap(payScheduleType: 'weekly', payScheduleDay: 8).payScheduleLabel, '매주 일요일');
    });
    test('D-30 weekly day=3 time=18:00 → "매주 수요일 18:00"', () {
      expect(_snap(payScheduleType: 'weekly', payScheduleDay: 3, payScheduleTime: '18:00').payScheduleLabel,
          '매주 수요일 18:00');
    });
    test('D-31 weekly day=5 time=15:30 → "매주 금요일 15:30"', () {
      expect(_snap(payScheduleType: 'weekly', payScheduleDay: 5, payScheduleTime: '15:30').payScheduleLabel,
          '매주 금요일 15:30');
    });

    // ── D-4. monthly ─────────────────────────────────────────────────────────
    test('D-40 monthly day=1 → "매월 1일"', () {
      expect(_snap(payScheduleType: 'monthly', payScheduleDay: 1).payScheduleLabel, '매월 1일');
    });
    test('D-41 monthly day=10 → "매월 10일"', () {
      expect(_snap(payScheduleType: 'monthly', payScheduleDay: 10).payScheduleLabel, '매월 10일');
    });
    test('D-42 monthly day=15 → "매월 15일"', () {
      expect(_snap(payScheduleType: 'monthly', payScheduleDay: 15).payScheduleLabel, '매월 15일');
    });
    test('D-43 monthly day=25 → "매월 25일"', () {
      expect(_snap(payScheduleType: 'monthly', payScheduleDay: 25).payScheduleLabel, '매월 25일');
    });
    test('D-44 monthly day=31 → "매월 말일"', () {
      expect(_snap(payScheduleType: 'monthly', payScheduleDay: 31).payScheduleLabel, '매월 말일');
    });
    test('D-45 monthly day=null → d=1 → "매월 1일"', () {
      expect(_snap(payScheduleType: 'monthly', payScheduleDay: null).payScheduleLabel, '매월 1일');
    });
    test('D-46 monthly day=15 time=09:00 → "매월 15일 09:00"', () {
      expect(_snap(payScheduleType: 'monthly', payScheduleDay: 15, payScheduleTime: '09:00').payScheduleLabel,
          '매월 15일 09:00');
    });
    test('D-47 monthly day=31 time=17:00 → "매월 말일 17:00"', () {
      expect(_snap(payScheduleType: 'monthly', payScheduleDay: 31, payScheduleTime: '17:00').payScheduleLabel,
          '매월 말일 17:00');
    });
    test('D-48 monthly day=1 time=00:00 → "매월 1일 00:00"', () {
      expect(_snap(payScheduleType: 'monthly', payScheduleDay: 1, payScheduleTime: '00:00').payScheduleLabel,
          '매월 1일 00:00');
    });

    // ── D-5. default 폴백 ────────────────────────────────────────────────────
    test('D-50 payScheduleType=null, wagePaymentDay=10 → "매월 10일"', () {
      expect(_snap(wagePaymentDay: 10).payScheduleLabel, '매월 10일');
    });
    test('D-51 payScheduleType=null, wagePaymentDay=1 → "매월 1일"', () {
      expect(_snap(wagePaymentDay: 1).payScheduleLabel, '매월 1일');
    });
    test('D-52 payScheduleType=null, wagePaymentDay=null → "별도 협의"', () {
      expect(_snap().payScheduleLabel, '별도 협의');
    });
    test('D-53 payScheduleType=unknown_value → default 폴백', () {
      expect(_snap(payScheduleType: 'bi_weekly', wagePaymentDay: 15).payScheduleLabel, '매월 15일');
    });
    test('D-54 payScheduleType=unknown_value, wagePaymentDay=null → "별도 협의"', () {
      expect(_snap(payScheduleType: 'bi_weekly').payScheduleLabel, '별도 협의');
    });
  });

  // ===========================================================================
  // E. ContractSnapshot.payScheduleTypeLabel (20+ 케이스)
  // ===========================================================================
  group('E: ContractSnapshot.payScheduleTypeLabel', () {
    test('E-01 same_day → "당일"', () => expect(_snap(payScheduleType: 'same_day').payScheduleTypeLabel, '당일'));
    test('E-02 next_day → "익일"', () => expect(_snap(payScheduleType: 'next_day').payScheduleTypeLabel, '익일'));
    test('E-03 weekly → "주급"', () => expect(_snap(payScheduleType: 'weekly').payScheduleTypeLabel, '주급'));
    test('E-04 monthly → "월급"', () => expect(_snap(payScheduleType: 'monthly').payScheduleTypeLabel, '월급'));
    test('E-05 null → ""', () => expect(_snap().payScheduleTypeLabel, ''));
    test('E-06 unknown → ""', () => expect(_snap(payScheduleType: 'bi_weekly').payScheduleTypeLabel, ''));
    test('E-07 빈 문자열 → ""', () => expect(_snap(payScheduleType: '').payScheduleTypeLabel, ''));
  });

  // ===========================================================================
  // F. ContractSnapshot 포맷터 (25+ 케이스)
  // ===========================================================================
  group('F: ContractSnapshot 포맷터', () {
    // ── F-1. formattedWage ───────────────────────────────────────────────────
    test('F-01 wage=10000 → "10,000원"', () {
      expect(_snap(wage: 10000).formattedWage, '10,000원');
    });
    test('F-02 wage=100000 → "100,000원"', () {
      expect(_snap(wage: 100000).formattedWage, '100,000원');
    });
    test('F-03 wage=1000000 → "1,000,000원"', () {
      expect(_snap(wage: 1000000).formattedWage, '1,000,000원');
    });
    test('F-04 wage=10320 → "10,320원"', () {
      expect(_snap(wage: 10320).formattedWage, '10,320원');
    });
    test('F-05 wage=2500000 → "2,500,000원"', () {
      expect(_snap(wage: 2500000).formattedWage, '2,500,000원');
    });
    test('F-06 wage=0 → "0원"', () {
      expect(_snap(wage: 0).formattedWage, '0원');
    });
    test('F-07 wage=999 → "999원"', () {
      expect(_snap(wage: 999).formattedWage, '999원');
    });
    test('F-08 wage=1000 → "1,000원"', () {
      expect(_snap(wage: 1000).formattedWage, '1,000원');
    });

    // ── F-2. wageTypeLabel ────────────────────────────────────────────────────
    test('F-10 hourly → "시급"', () => expect(_snap(wageType: 'hourly').wageTypeLabel, '시급'));
    test('F-11 daily → "일급"', () => expect(_snap(wageType: 'daily').wageTypeLabel, '일급'));
    test('F-12 monthly → "월급"', () => expect(_snap(wageType: 'monthly').wageTypeLabel, '월급'));
    test('F-13 unknown → "시급" (default)', () => expect(_snap(wageType: 'unknown').wageTypeLabel, '시급'));

    // ── F-3. workPeriodText ───────────────────────────────────────────────────
    test('F-20 contractStart/End null → "-"', () {
      expect(_snap().workPeriodText, '-');
    });
    test('F-21 contractStart 있고 End null → "-"', () {
      expect(_snap(contractStart: '2025-01-06').workPeriodText, '-');
    });
    test('F-22 둘 다 있음 → 형식 출력', () {
      expect(_snap(contractStart: '2025-01-06', contractEnd: '2025-01-31').workPeriodText,
          '2025-01-06 ~ 2025-01-31');
    });

    // ── F-4. workDaysText ─────────────────────────────────────────────────────
    test('F-30 workDays null → "-"', () {
      expect(_snap().workDaysText, '-');
    });
    test('F-31 workDays=["월","화","수","목","금"] → "월, 화, 수, 목, 금"', () {
      expect(_snap(workDays: ['월','화','수','목','금']).workDaysText, '월, 화, 수, 목, 금');
    });
    test('F-32 workDays=["월","수","금"] → "월, 수, 금"', () {
      expect(_snap(workDays: ['월','수','금']).workDaysText, '월, 수, 금');
    });
    test('F-33 workDays=["토","일"] → "토, 일"', () {
      expect(_snap(workDays: ['토','일']).workDaysText, '토, 일');
    });
    test('F-34 workDays=[] → ""', () {
      expect(_snap(workDays: []).workDaysText, '');
    });
  });

  // ===========================================================================
  // G. ContractSlot (35+ 케이스)
  // ===========================================================================
  group('G: ContractSlot', () {
    ContractSlot makeSlot({
      String applicationId = 'app1',
      String workDate = '2025-01-06',
      String startTime = '09:00',
      String endTime = '18:00',
      int wage = 10000,
      String wageType = 'hourly',
    }) =>
        ContractSlot(
          applicationId: applicationId,
          workDate: workDate,
          startTime: startTime,
          endTime: endTime,
          wage: wage,
          wageType: wageType,
        );

    // ── G-1. wageTypeLabel ────────────────────────────────────────────────────
    test('G-01 hourly → "시급"', () => expect(makeSlot(wageType: 'hourly').wageTypeLabel, '시급'));
    test('G-02 daily → "일급"', () => expect(makeSlot(wageType: 'daily').wageTypeLabel, '일급'));
    test('G-03 monthly → "월급"', () => expect(makeSlot(wageType: 'monthly').wageTypeLabel, '월급'));
    test('G-04 unknown → "시급" (default)', () => expect(makeSlot(wageType: 'unknown').wageTypeLabel, '시급'));

    // ── G-2. formattedWage ────────────────────────────────────────────────────
    test('G-10 wage=10000 → "10,000원"', () => expect(makeSlot(wage: 10000).formattedWage, '10,000원'));
    test('G-11 wage=80000 → "80,000원"', () => expect(makeSlot(wage: 80000).formattedWage, '80,000원'));
    test('G-12 wage=1000000 → "1,000,000원"', () => expect(makeSlot(wage: 1000000).formattedWage, '1,000,000원'));
    test('G-13 wage=0 → "0원"', () => expect(makeSlot(wage: 0).formattedWage, '0원'));
    test('G-14 wage=999 → "999원"', () => expect(makeSlot(wage: 999).formattedWage, '999원'));

    // ── G-3. fromMap ──────────────────────────────────────────────────────────
    test('G-20 fromMap 정상', () {
      final m = {
        'applicationId': 'app_x',
        'workDate': '2025-03-15',
        'startTime': '10:00',
        'endTime': '19:00',
        'wage': 12000,
        'wageType': 'hourly',
      };
      final slot = ContractSlot.fromMap(m);
      expect(slot.applicationId, 'app_x');
      expect(slot.workDate, '2025-03-15');
      expect(slot.startTime, '10:00');
      expect(slot.endTime, '19:00');
      expect(slot.wage, 12000);
      expect(slot.wageType, 'hourly');
    });
    test('G-21 fromMap null 필드 → 기본값 사용', () {
      final m = <String, dynamic>{};
      final slot = ContractSlot.fromMap(m);
      expect(slot.applicationId, '');
      expect(slot.workDate, '');
      expect(slot.startTime, '09:00');
      expect(slot.endTime, '18:00');
      expect(slot.wage, 0);
      expect(slot.wageType, 'hourly');
    });
    test('G-22 fromMap wage num 타입 → int 변환', () {
      final m = {'wage': 80000.0};
      final slot = ContractSlot.fromMap(m);
      expect(slot.wage, 80000);
    });

    // ── G-4. toMap ────────────────────────────────────────────────────────────
    test('G-30 toMap 왕복 직렬화', () {
      final original = makeSlot(applicationId: 'app_y', workDate: '2025-04-10',
          startTime: '08:00', endTime: '16:00', wage: 75000, wageType: 'daily');
      final m = original.toMap();
      final restored = ContractSlot.fromMap(m);
      expect(restored.applicationId, original.applicationId);
      expect(restored.workDate, original.workDate);
      expect(restored.startTime, original.startTime);
      expect(restored.endTime, original.endTime);
      expect(restored.wage, original.wage);
      expect(restored.wageType, original.wageType);
    });

    // ── G-5. 여러 슬롯 목록 ──────────────────────────────────────────────────
    test('G-40 slots 목록 3개', () {
      final slots = [
        makeSlot(applicationId: 'a1', workDate: '2025-01-06'),
        makeSlot(applicationId: 'a2', workDate: '2025-01-07'),
        makeSlot(applicationId: 'a3', workDate: '2025-01-08'),
      ];
      expect(slots.length, 3);
      expect(slots.map((s) => s.applicationId).toList(), ['a1', 'a2', 'a3']);
    });
  });

  // ===========================================================================
  // H. ContractTemplateType (20+ 케이스)
  // ===========================================================================
  group('H: ContractTemplateType', () {
    // ── H-1. 상수값 ──────────────────────────────────────────────────────────
    test('H-01 daily = daily', () => expect(ContractTemplateType.daily, 'daily'));
    test('H-02 period = period', () => expect(ContractTemplateType.period, 'period'));
    test('H-03 outsource = outsource', () => expect(ContractTemplateType.outsource, 'outsource'));

    // ── H-2. label ────────────────────────────────────────────────────────────
    test('H-10 label(daily) = 단기 일용직', () => expect(ContractTemplateType.label('daily'), '단기 일용직'));
    test('H-11 label(period) = 기간제(장기)', () => expect(ContractTemplateType.label('period'), '기간제(장기)'));
    test('H-12 label(outsource) = 업무위탁(도급)', () => expect(ContractTemplateType.label('outsource'), '업무위탁(도급)'));
    test('H-13 label(unknown) = 기타', () => expect(ContractTemplateType.label('unknown'), '기타'));
    test('H-14 label 빈 문자열 = 기타', () => expect(ContractTemplateType.label(''), '기타'));

    // ── H-3. description ──────────────────────────────────────────────────────
    test('H-20 description(daily) 포함 키워드: 단기', () {
      expect(ContractTemplateType.description('daily').contains('단기'), true);
    });
    test('H-21 description(period) 포함 키워드: 장기', () {
      expect(ContractTemplateType.description('period').contains('장기'), true);
    });
    test('H-22 description(outsource) 포함 키워드: 3.3%', () {
      expect(ContractTemplateType.description('outsource').contains('3.3%'), true);
    });
    test('H-23 description(unknown) = ""', () {
      expect(ContractTemplateType.description('unknown'), '');
    });
  });

  // ===========================================================================
  // I. ContractTemplateModel.defaultArticlesFor (35+ 케이스)
  // ===========================================================================
  group('I: ContractTemplateModel.defaultArticlesFor', () {
    // ── I-1. daily (8개 조항) ─────────────────────────────────────────────────
    test('I-01 daily → 8개 조항', () {
      expect(ContractTemplateModel.defaultArticlesFor('daily').length, 8);
    });
    test('I-02 daily 첫 조항 제목: 제4조 (4대보험 적용)', () {
      expect(ContractTemplateModel.defaultArticlesFor('daily').first.title, '제4조 (4대보험 적용)');
    });
    test('I-03 daily 마지막 조항 제목: 제11조 (기타)', () {
      expect(ContractTemplateModel.defaultArticlesFor('daily').last.title, '제11조 (기타)');
    });
    test('I-04 daily 조항들 모두 title 비어있지 않음', () {
      for (final a in ContractTemplateModel.defaultArticlesFor('daily')) {
        expect(a.title.isNotEmpty, true, reason: '${a.title} should not be empty');
      }
    });
    test('I-05 daily 조항들 모두 content 비어있지 않음', () {
      for (final a in ContractTemplateModel.defaultArticlesFor('daily')) {
        expect(a.content.isNotEmpty, true, reason: '${a.title} content should not be empty');
      }
    });
    test('I-06 daily 제5조 포함: 근태 및 휴일', () {
      final titles = ContractTemplateModel.defaultArticlesFor('daily').map((a) => a.title).toList();
      expect(titles.any((t) => t.contains('근태')), true);
    });
    test('I-07 daily 산재보험 언급 포함', () {
      final all = ContractTemplateModel.defaultArticlesFor('daily')
          .map((a) => a.content).join();
      expect(all.contains('산재보험'), true);
    });
    test('I-08 daily 제목에 제4조~제11조 연속 번호', () {
      final titles = ContractTemplateModel.defaultArticlesFor('daily').map((a) => a.title).toList();
      for (int i = 4; i <= 11; i++) {
        expect(titles.any((t) => t.contains('제${i}조')), true, reason: '제${i}조 not found');
      }
    });

    // ── I-2. period (12개 조항) ────────────────────────────────────────────────
    test('I-10 period → 12개 조항', () {
      expect(ContractTemplateModel.defaultArticlesFor('period').length, 12);
    });
    test('I-11 period 첫 조항: 제4조 (수습기간)', () {
      expect(ContractTemplateModel.defaultArticlesFor('period').first.title, '제4조 (수습기간)');
    });
    test('I-12 period 마지막 조항: 제15조 (기타)', () {
      expect(ContractTemplateModel.defaultArticlesFor('period').last.title, '제15조 (기타)');
    });
    test('I-13 period 4대보험 조항 포함', () {
      final titles = ContractTemplateModel.defaultArticlesFor('period').map((a) => a.title).toList();
      expect(titles.any((t) => t.contains('4대보험')), true);
    });
    test('I-14 period 연차유급휴가 조항 포함', () {
      final titles = ContractTemplateModel.defaultArticlesFor('period').map((a) => a.title).toList();
      expect(titles.any((t) => t.contains('연차')), true);
    });
    test('I-15 period 퇴직급여 조항 포함', () {
      final titles = ContractTemplateModel.defaultArticlesFor('period').map((a) => a.title).toList();
      expect(titles.any((t) => t.contains('퇴직')), true);
    });
    test('I-16 period 제목에 제4조~제15조 연속 번호', () {
      final titles = ContractTemplateModel.defaultArticlesFor('period').map((a) => a.title).toList();
      for (int i = 4; i <= 15; i++) {
        expect(titles.any((t) => t.contains('제${i}조')), true, reason: '제${i}조 not found');
      }
    });
    test('I-17 period 괴롭힘 금지 조항 포함', () {
      final titles = ContractTemplateModel.defaultArticlesFor('period').map((a) => a.title).toList();
      expect(titles.any((t) => t.contains('괴롭힘')), true);
    });
    test('I-18 period 조항들 모두 내용 비어있지 않음', () {
      for (final a in ContractTemplateModel.defaultArticlesFor('period')) {
        expect(a.content.isNotEmpty, true);
      }
    });

    // ── I-3. outsource (7개 조항) ─────────────────────────────────────────────
    test('I-20 outsource → 7개 조항', () {
      expect(ContractTemplateModel.defaultArticlesFor('outsource').length, 7);
    });
    test('I-21 outsource 첫 조항: 제4조 (원천징수 및 세금 처리)', () {
      expect(ContractTemplateModel.defaultArticlesFor('outsource').first.title, '제4조 (원천징수 및 세금 처리)');
    });
    test('I-22 outsource 마지막 조항: 제10조 (기타)', () {
      expect(ContractTemplateModel.defaultArticlesFor('outsource').last.title, '제10조 (기타)');
    });
    test('I-23 outsource 3.3% 원천징수 언급', () {
      final all = ContractTemplateModel.defaultArticlesFor('outsource')
          .map((a) => a.content).join();
      expect(all.contains('3.3%'), true);
    });
    test('I-24 outsource 4대보험 미적용 조항 포함', () {
      final titles = ContractTemplateModel.defaultArticlesFor('outsource').map((a) => a.title).toList();
      expect(titles.any((t) => t.contains('4대보험 미적용')), true);
    });
    test('I-25 outsource 지식재산권 조항 포함', () {
      final titles = ContractTemplateModel.defaultArticlesFor('outsource').map((a) => a.title).toList();
      expect(titles.any((t) => t.contains('지식재산권')), true);
    });
    test('I-26 outsource 독립성 조항 포함', () {
      final titles = ContractTemplateModel.defaultArticlesFor('outsource').map((a) => a.title).toList();
      expect(titles.any((t) => t.contains('독립성')), true);
    });
    test('I-27 outsource 제목에 제4조~제10조 연속 번호', () {
      final titles = ContractTemplateModel.defaultArticlesFor('outsource').map((a) => a.title).toList();
      for (int i = 4; i <= 10; i++) {
        expect(titles.any((t) => t.contains('제${i}조')), true, reason: '제${i}조 not found');
      }
    });

    // ── I-4. unknown → daily (default) ────────────────────────────────────────
    test('I-30 unknown → daily 조항 8개', () {
      expect(ContractTemplateModel.defaultArticlesFor('unknown').length, 8);
    });
    test('I-31 빈 문자열 → daily 조항 8개', () {
      expect(ContractTemplateModel.defaultArticlesFor('').length, 8);
    });
    test('I-32 daily 가 default → unknown 과 daily 동일', () {
      final dailyArticles = ContractTemplateModel.defaultArticlesFor('daily');
      final unknownArticles = ContractTemplateModel.defaultArticlesFor('unknown');
      expect(dailyArticles.length, unknownArticles.length);
      for (int i = 0; i < dailyArticles.length; i++) {
        expect(dailyArticles[i].title, unknownArticles[i].title);
      }
    });
  });

  // ===========================================================================
  // J. ContractArticle (20+ 케이스)
  // ===========================================================================
  group('J: ContractArticle', () {
    test('J-01 생성자 기본', () {
      const a = ContractArticle(title: '제1조', content: '내용');
      expect(a.title, '제1조');
      expect(a.content, '내용');
    });
    test('J-02 toMap', () {
      const a = ContractArticle(title: '제5조 (연차)', content: '연차 관련 내용');
      final m = a.toMap();
      expect(m['title'], '제5조 (연차)');
      expect(m['content'], '연차 관련 내용');
    });
    test('J-03 fromMap 정상', () {
      final m = {'title': '제7조', 'content': '조항 내용'};
      final a = ContractArticle.fromMap(m);
      expect(a.title, '제7조');
      expect(a.content, '조항 내용');
    });
    test('J-04 fromMap null 필드 → 빈 문자열', () {
      final m = <String, dynamic>{};
      final a = ContractArticle.fromMap(m);
      expect(a.title, '');
      expect(a.content, '');
    });
    test('J-05 toMap → fromMap 왕복', () {
      const original = ContractArticle(title: '제9조 (기타)', content: '기타 사항');
      final restored = ContractArticle.fromMap(original.toMap());
      expect(restored.title, original.title);
      expect(restored.content, original.content);
    });
    test('J-06 copyWith title 변경', () {
      const a = ContractArticle(title: '제1조', content: '내용');
      final b = a.copyWith(title: '제2조');
      expect(b.title, '제2조');
      expect(b.content, '내용');
    });
    test('J-07 copyWith content 변경', () {
      const a = ContractArticle(title: '제1조', content: '원본 내용');
      final b = a.copyWith(content: '변경된 내용');
      expect(b.title, '제1조');
      expect(b.content, '변경된 내용');
    });
    test('J-08 copyWith 둘 다 변경', () {
      const a = ContractArticle(title: '제1조', content: '내용1');
      final b = a.copyWith(title: '제2조', content: '내용2');
      expect(b.title, '제2조');
      expect(b.content, '내용2');
    });
    test('J-09 copyWith null → 기존값 유지', () {
      const a = ContractArticle(title: '제1조', content: '내용');
      final b = a.copyWith();
      expect(b.title, a.title);
      expect(b.content, a.content);
    });
    test('J-10 빈 title/content 허용', () {
      const a = ContractArticle(title: '', content: '');
      expect(a.title, '');
      expect(a.content, '');
    });
    test('J-11 조항 목록 직렬화 → toList → fromList', () {
      final articles = [
        const ContractArticle(title: '제4조', content: '내용1'),
        const ContractArticle(title: '제5조', content: '내용2'),
      ];
      final maps = articles.map((a) => a.toMap()).toList();
      final restored = maps.map((m) => ContractArticle.fromMap(m)).toList();
      expect(restored.length, 2);
      expect(restored[0].title, '제4조');
      expect(restored[1].title, '제5조');
    });
  });

  // ===========================================================================
  // K. EmploymentContractModel 상태 헬퍼 (30+ 케이스)
  // ===========================================================================
  group('K: EmploymentContractModel 상태 헬퍼', () {
    // ── K-1. isCompleted ─────────────────────────────────────────────────────
    test('K-01 completed → isCompleted=true', () {
      expect(_contract(status: ContractStatus.completed).isCompleted, true);
    });
    test('K-02 pendingEmployer → isCompleted=false', () {
      expect(_contract(status: ContractStatus.pendingEmployer).isCompleted, false);
    });
    test('K-03 pendingWorker → isCompleted=false', () {
      expect(_contract(status: ContractStatus.pendingWorker).isCompleted, false);
    });
    test('K-04 voided → isCompleted=false', () {
      expect(_contract(status: ContractStatus.voided).isCompleted, false);
    });

    // ── K-2. needsEmployerSignature ───────────────────────────────────────────
    test('K-10 pendingEmployer → needsEmployerSignature=true', () {
      expect(_contract(status: ContractStatus.pendingEmployer).needsEmployerSignature, true);
    });
    test('K-11 pendingWorker → needsEmployerSignature=false', () {
      expect(_contract(status: ContractStatus.pendingWorker).needsEmployerSignature, false);
    });
    test('K-12 completed → needsEmployerSignature=false', () {
      expect(_contract(status: ContractStatus.completed).needsEmployerSignature, false);
    });
    test('K-13 voided → needsEmployerSignature=false', () {
      expect(_contract(status: ContractStatus.voided).needsEmployerSignature, false);
    });

    // ── K-3. needsWorkerSignature ─────────────────────────────────────────────
    test('K-20 pendingWorker → needsWorkerSignature=true', () {
      expect(_contract(status: ContractStatus.pendingWorker).needsWorkerSignature, true);
    });
    test('K-21 pendingEmployer → needsWorkerSignature=false', () {
      expect(_contract(status: ContractStatus.pendingEmployer).needsWorkerSignature, false);
    });
    test('K-22 completed → needsWorkerSignature=false', () {
      expect(_contract(status: ContractStatus.completed).needsWorkerSignature, false);
    });
    test('K-23 voided → needsWorkerSignature=false', () {
      expect(_contract(status: ContractStatus.voided).needsWorkerSignature, false);
    });

    // ── K-4. 3가지 상태 동시 체크 ─────────────────────────────────────────────
    test('K-30 completed: isCompleted=true, needs*=false', () {
      final c = _contract(status: ContractStatus.completed);
      expect(c.isCompleted, true);
      expect(c.needsEmployerSignature, false);
      expect(c.needsWorkerSignature, false);
    });
    test('K-31 pendingEmployer: needsEmployer=true, 나머지 false', () {
      final c = _contract(status: ContractStatus.pendingEmployer);
      expect(c.isCompleted, false);
      expect(c.needsEmployerSignature, true);
      expect(c.needsWorkerSignature, false);
    });
    test('K-32 pendingWorker: needsWorker=true, 나머지 false', () {
      final c = _contract(status: ContractStatus.pendingWorker);
      expect(c.isCompleted, false);
      expect(c.needsEmployerSignature, false);
      expect(c.needsWorkerSignature, true);
    });
    test('K-33 voided: 모두 false', () {
      final c = _contract(status: ContractStatus.voided);
      expect(c.isCompleted, false);
      expect(c.needsEmployerSignature, false);
      expect(c.needsWorkerSignature, false);
    });

    // ── K-5. copyWith ─────────────────────────────────────────────────────────
    test('K-40 copyWith status pendingEmployer → pendingWorker', () {
      final c = _contract(status: ContractStatus.pendingEmployer);
      final c2 = c.copyWith(status: ContractStatus.pendingWorker);
      expect(c2.needsWorkerSignature, true);
      expect(c.needsEmployerSignature, true); // 원본 불변
    });
    test('K-41 copyWith status pendingWorker → completed', () {
      final c = _contract(status: ContractStatus.pendingWorker);
      final c2 = c.copyWith(status: ContractStatus.completed);
      expect(c2.isCompleted, true);
    });
    test('K-42 copyWith employerSignatureUrl', () {
      final c = _contract();
      final c2 = c.copyWith(employerSignatureUrl: 'https://storage/sig.png');
      expect(c2.employerSignatureUrl, 'https://storage/sig.png');
      expect(c.employerSignatureUrl, null);
    });
    test('K-43 copyWith articles 변경', () {
      final c = _contract(articles: []);
      final newArticles = [const ContractArticle(title: '제4조', content: '내용')];
      final c2 = c.copyWith(articles: newArticles);
      expect(c2.articles.length, 1);
      expect(c.articles.length, 0);
    });
    test('K-44 copyWith pdfUrl 설정', () {
      final c = _contract();
      final c2 = c.copyWith(pdfUrl: 'https://storage/contract.pdf');
      expect(c2.pdfUrl, 'https://storage/contract.pdf');
    });
    test('K-45 copyWith slots 추가', () {
      final c = _contract(slots: []);
      final newSlots = [
        const ContractSlot(applicationId: 'a1', workDate: '2025-01-06',
            startTime: '09:00', endTime: '18:00', wage: 10000, wageType: 'hourly'),
      ];
      final c2 = c.copyWith(slots: newSlots);
      expect(c2.slots.length, 1);
      expect(c.slots.length, 0);
    });
    test('K-46 isNewUnsaved는 copyWith에서 변경 불가 (원본 유지)', () {
      final c = EmploymentContractModel(
        id: 'x', applicationId: 'a', businessId: 'b', workerId: 'w',
        isLongTerm: false, toId: 't', workDetailId: 'wd',
        status: ContractStatus.pendingEmployer,
        snapshot: _snap(), createdAt: DateTime(2025, 1, 1), isNewUnsaved: true,
      );
      final c2 = c.copyWith(status: ContractStatus.completed);
      expect(c2.isNewUnsaved, true); // copyWith에서 isNewUnsaved 변경 불가
    });
  });

  // ===========================================================================
  // L. InsuranceRateModel (30+ 케이스)
  // ===========================================================================
  group('L: InsuranceRateModel', () {
    // ── L-1. defaults2026 값 검증 ─────────────────────────────────────────────
    test('L-01 year=2026', () => expect(InsuranceRateModel.defaults2026().year, 2026));
    test('L-02 nationalPensionRate=4.75', () => expect(InsuranceRateModel.defaults2026().nationalPensionRate, 4.75));
    test('L-03 healthInsuranceRate=3.595', () => expect(InsuranceRateModel.defaults2026().healthInsuranceRate, 3.595));
    test('L-04 ltcInsuranceRate=13.14', () => expect(InsuranceRateModel.defaults2026().ltcInsuranceRate, 13.14));
    test('L-05 employmentInsuranceRate=0.9', () => expect(InsuranceRateModel.defaults2026().employmentInsuranceRate, 0.9));
    test('L-06 dailyWageExemption=150000', () => expect(InsuranceRateModel.defaults2026().dailyWageExemption, 150000));
    test('L-07 dailyWorkerTaxRate=2.7', () => expect(InsuranceRateModel.defaults2026().dailyWorkerTaxRate, 2.7));
    test('L-08 localIncomeTaxRate=10.0', () => expect(InsuranceRateModel.defaults2026().localIncomeTaxRate, 10.0));
    test('L-09 businessIncomeRate=3.0', () => expect(InsuranceRateModel.defaults2026().businessIncomeRate, 3.0));
    test('L-10 businessIncomeLocalRate=0.3', () => expect(InsuranceRateModel.defaults2026().businessIncomeLocalRate, 0.3));

    // ── L-2. 공제 타입 상수 ────────────────────────────────────────────────────
    test('L-20 typeNone = none', () => expect(InsuranceRateModel.typeNone, 'none'));
    test('L-21 typeFreelancer33 = freelancer_3_3', () => expect(InsuranceRateModel.typeFreelancer33, 'freelancer_3_3'));
    test('L-22 typeDailyWorker = daily_worker', () => expect(InsuranceRateModel.typeDailyWorker, 'daily_worker'));
    test('L-23 typeDailyAuto8 = daily_auto_8', () => expect(InsuranceRateModel.typeDailyAuto8, 'daily_auto_8'));
    test('L-24 typeFourInsuranceFixed = four_insurance_fixed', () => expect(InsuranceRateModel.typeFourInsuranceFixed, 'four_insurance_fixed'));
    test('L-25 allTypes.length = 5', () => expect(InsuranceRateModel.allTypes.length, 5));
    test('L-26 allTypes에 typeNone 포함', () => expect(InsuranceRateModel.allTypes.contains('none'), true));

    // ── L-3. typeLabel ─────────────────────────────────────────────────────────
    test('L-30 typeLabel(none) = 세금 없음', () => expect(InsuranceRateModel.typeLabel('none'), '세금 없음'));
    test('L-31 typeLabel(freelancer_3_3) = 3.3% 원천징수', () => expect(InsuranceRateModel.typeLabel('freelancer_3_3'), '3.3% 원천징수'));
    test('L-32 typeLabel(daily_worker) = 일용직 소득세', () => expect(InsuranceRateModel.typeLabel('daily_worker'), '일용직 소득세'));
    test('L-33 typeLabel(daily_auto_8) = 일용직 8일 소급', () => expect(InsuranceRateModel.typeLabel('daily_auto_8'), '일용직 8일 소급'));
    test('L-34 typeLabel(four_insurance_fixed) = 4대보험 고정', () => expect(InsuranceRateModel.typeLabel('four_insurance_fixed'), '4대보험 고정'));
    test('L-35 typeLabel(unknown) = 세금 없음 (default)', () => expect(InsuranceRateModel.typeLabel('unknown'), '세금 없음'));

    // ── L-4. fromMap 폴백 검증 ─────────────────────────────────────────────────
    test('L-40 fromMap 빈 map → defaults2026 값', () {
      final m = InsuranceRateModel.fromMap({});
      expect(m.nationalPensionRate, 4.75);
      expect(m.dailyWageExemption, 150000);
    });
    test('L-41 fromMap 일부 값 오버라이드', () {
      final m = InsuranceRateModel.fromMap({'nationalPensionRate': 5.0});
      expect(m.nationalPensionRate, 5.0);
      expect(m.healthInsuranceRate, 3.595); // 나머지는 기본값
    });
  });

  // ===========================================================================
  // M. ContractSnapshot.taxDeductionType (20+ 케이스)
  // ===========================================================================
  group('M: ContractSnapshot.taxDeductionType', () {
    test('M-01 기본값 = typeNone', () {
      expect(_snap().taxDeductionType, InsuranceRateModel.typeNone);
    });
    test('M-02 typeNone = none', () {
      expect(_snap(taxDeductionType: 'none').taxDeductionType, 'none');
    });
    test('M-03 typeFreelancer33 = freelancer_3_3', () {
      expect(_snap(taxDeductionType: 'freelancer_3_3').taxDeductionType, 'freelancer_3_3');
    });
    test('M-04 typeDailyWorker = daily_worker', () {
      expect(_snap(taxDeductionType: 'daily_worker').taxDeductionType, 'daily_worker');
    });
    test('M-05 toMap에서 taxDeductionType 포함 여부 (none은 제외)', () {
      // toMap(): `if (taxDeductionType != InsuranceRateModel.typeNone) 'taxDeductionType': ...`
      final m = _snap(taxDeductionType: 'none').toMap();
      expect(m.containsKey('taxDeductionType'), false);
    });
    test('M-06 toMap에서 non-none taxDeductionType 포함', () {
      final m = _snap(taxDeductionType: 'freelancer_3_3').toMap();
      expect(m['taxDeductionType'], 'freelancer_3_3');
    });
    test('M-07 fromMap null → typeNone', () {
      final snap = ContractSnapshot.fromMap({
        'businessName': '', 'businessNumber': '', 'businessAddress': '',
        'ownerName': '', 'workerName': '', 'workType': '', 'workPlace': '',
        'isLongTerm': false, 'startTime': '09:00', 'endTime': '18:00',
        'breakMinutes': 0, 'wage': 0, 'wageType': 'hourly',
        'paymentMethod': '계좌이체',
      });
      expect(snap.taxDeductionType, InsuranceRateModel.typeNone);
    });
  });

  // ===========================================================================
  // N. 복합 시나리오 (60+ 케이스)
  // ===========================================================================
  group('N: 복합 시나리오', () {
    // ── N-1. 시급 계산 연계 ────────────────────────────────────────────────────
    test('N-01 일급 근무자: 9h 근무 (break=60) wage=80000 → 80000/8=10000원/시간', () {
      final snap = _snap(wageType: 'daily', startTime: '09:00', endTime: '18:00',
          breakMinutes: 60, wage: 80000);
      expect(snap.hourlyWage, 10000);
      expect(snap.formattedHourlyWage, '10,000원/시간');
      expect(snap.workTimeText, '09:00 ~ 18:00 (휴게 60분) · 8h');
    });
    test('N-02 최저시급 2026: 10320원 hourly', () {
      final snap = _snap(wageType: 'hourly', wage: 10320);
      expect(snap.hourlyWage, 10320);
      expect(snap.formattedWage, '10,320원');
    });
    test('N-03 야간 알바: 22:00~02:00, wage=10000/h → workTimeText 4h', () {
      final snap = _snap(wageType: 'hourly', startTime: '22:00', endTime: '02:00', wage: 10000);
      expect(snap.workTimeText, '22:00 ~ 02:00 · 4h');
      expect(snap.hourlyWage, 10000);
    });
    test('N-04 야간 일급: 22:00~06:00 break=60 wage=80000 → 80000/7h=11428.57→round=11429', () {
      final snap = _snap(wageType: 'daily', startTime: '22:00', endTime: '06:00',
          breakMinutes: 60, wage: 80000);
      // workMins = 480-60 = 420min = 7h. 80000/7 = 11428.57... → round = 11429
      expect(snap.hourlyWage, 11429);
    });
    test('N-05 월급: hourlyWage null → formattedHourlyWage "-"', () {
      final snap = _snap(wageType: 'monthly', wage: 2500000);
      expect(snap.hourlyWage, null);
      expect(snap.formattedHourlyWage, '-');
      expect(snap.formattedWage, '2,500,000원');
    });
    test('N-06 baseHourlyWage 있으면 daily 계산 무시', () {
      final snap = _snap(wageType: 'daily', wage: 100000, baseHourlyWage: 12000,
          startTime: '09:00', endTime: '18:00', breakMinutes: 0);
      // 100000/9 = 11111 이지만 baseHourlyWage=12000 우선
      expect(snap.hourlyWage, 12000);
      expect(snap.formattedHourlyWage, '12,000원/시간');
    });

    // ── N-2. 지급 일정 복합 ────────────────────────────────────────────────────
    test('N-10 주급 월요일 18:00 지급', () {
      final snap = _snap(payScheduleType: 'weekly', payScheduleDay: 1, payScheduleTime: '18:00');
      expect(snap.payScheduleLabel, '매주 월요일 18:00');
      expect(snap.payScheduleTypeLabel, '주급');
    });
    test('N-11 월급 말일 17:00 지급', () {
      final snap = _snap(payScheduleType: 'monthly', payScheduleDay: 31, payScheduleTime: '17:00');
      expect(snap.payScheduleLabel, '매월 말일 17:00');
      expect(snap.payScheduleTypeLabel, '월급');
    });
    test('N-12 당일 지급 10:00', () {
      final snap = _snap(payScheduleType: 'same_day', payScheduleTime: '10:00');
      expect(snap.payScheduleLabel, '당일 10:00');
      expect(snap.payScheduleTypeLabel, '당일');
    });
    test('N-13 지급 일정 없음 → 별도 협의', () {
      expect(_snap().payScheduleLabel, '별도 협의');
    });
    test('N-14 레거시 wagePaymentDay=25 → "매월 25일"', () {
      final snap = _snap(wagePaymentDay: 25);
      expect(snap.payScheduleLabel, '매월 25일');
    });

    // ── N-3. 계약 상태 전환 시나리오 ─────────────────────────────────────────
    test('N-20 신규 계약 → 사업주 서명 필요', () {
      final c = _contract(status: ContractStatus.pendingEmployer);
      expect(c.needsEmployerSignature, true);
      expect(c.isCompleted, false);
    });
    test('N-21 사업주 서명 → 근무자 서명 필요로 전환', () {
      final c1 = _contract(status: ContractStatus.pendingEmployer);
      final c2 = c1.copyWith(
        status: ContractStatus.pendingWorker,
        employerSignatureUrl: 'https://storage/employer_sig.png',
        employerSignedAt: DateTime(2025, 1, 10),
      );
      expect(c2.needsWorkerSignature, true);
      expect(c2.employerSignatureUrl, 'https://storage/employer_sig.png');
    });
    test('N-22 근무자 서명 → 완료로 전환', () {
      final c1 = _contract(status: ContractStatus.pendingWorker);
      final c2 = c1.copyWith(
        status: ContractStatus.completed,
        workerSignatureUrl: 'https://storage/worker_sig.png',
        pdfUrl: 'https://storage/contract.pdf',
      );
      expect(c2.isCompleted, true);
      expect(c2.pdfUrl, isNotNull);
    });
    test('N-23 완료 → 무효화', () {
      final c1 = _contract(status: ContractStatus.completed);
      final c2 = c1.copyWith(status: ContractStatus.voided);
      expect(c2.isCompleted, false);
      expect(c2.status.value, 'voided');
      expect(c2.status.label, '무효');
    });

    // ── N-4. 장기/단기 계약 구분 ─────────────────────────────────────────────
    test('N-30 장기 계약 ContractSnapshot workPeriodText', () {
      final snap = _snap(
        isLongTerm: true,
        contractStart: '2025-01-06',
        contractEnd: '2025-03-31',
        workDays: ['월','화','수','목','금'],
      );
      expect(snap.isLongTerm, true);
      expect(snap.workPeriodText, '2025-01-06 ~ 2025-03-31');
      expect(snap.workDaysText, '월, 화, 수, 목, 금');
    });
    test('N-31 단기 계약 ContractSnapshot workPeriodText null → "-"', () {
      final snap = _snap(isLongTerm: false);
      expect(snap.isLongTerm, false);
      expect(snap.workPeriodText, '-');
    });
    test('N-32 단기 계약 슬롯 번들 3개', () {
      final c = _contract(
        isLongTerm: false,
        slots: [
          const ContractSlot(applicationId: 'a1', workDate: '2025-01-06',
              startTime: '09:00', endTime: '18:00', wage: 10000, wageType: 'hourly'),
          const ContractSlot(applicationId: 'a2', workDate: '2025-01-07',
              startTime: '09:00', endTime: '18:00', wage: 10000, wageType: 'hourly'),
          const ContractSlot(applicationId: 'a3', workDate: '2025-01-08',
              startTime: '09:00', endTime: '18:00', wage: 10000, wageType: 'hourly'),
        ],
        applicationIds: ['a1', 'a2', 'a3'],
      );
      expect(c.slots.length, 3);
      expect(c.applicationIds.length, 3);
      expect(c.isLongTerm, false);
    });
    test('N-33 장기 계약 슬롯 없음', () {
      final c = _contract(isLongTerm: true, slots: []);
      expect(c.slots.isEmpty, true);
    });

    // ── N-5. 템플릿 + 계약서 조합 ────────────────────────────────────────────
    test('N-40 daily 템플릿 조항 8개 → 계약서에 추가', () {
      final articles = ContractTemplateModel.defaultArticlesFor('daily');
      final c = _contract(articles: articles);
      expect(c.articles.length, 8);
    });
    test('N-41 period 템플릿 적용 + 계약서 확인', () {
      final articles = ContractTemplateModel.defaultArticlesFor('period');
      final c = _contract(articles: articles, templateId: 'template_period_1');
      expect(c.articles.length, 12);
      expect(c.templateId, 'template_period_1');
    });
    test('N-42 outsource 템플릿 3.3% 조항 포함', () {
      final articles = ContractTemplateModel.defaultArticlesFor('outsource');
      final c = _contract(articles: articles);
      final allContent = c.articles.map((a) => a.content).join();
      expect(allContent.contains('3.3%'), true);
    });
    test('N-43 계약서 조항 copyWith로 수정', () {
      final articles = ContractTemplateModel.defaultArticlesFor('daily');
      final c = _contract(articles: articles);
      final modifiedArticles = [
        ...c.articles.take(3),
        c.articles[3].copyWith(content: '수정된 내용'),
        ...c.articles.skip(4),
      ];
      final c2 = c.copyWith(articles: modifiedArticles);
      expect(c2.articles[3].content, '수정된 내용');
      expect(c2.articles.length, 8);
    });

    // ── N-6. 4대보험 요율 계산 시나리오 ──────────────────────────────────────
    test('N-50 2026년 국민연금 근로자 부담: 100만원 × 4.75% = 47500원', () {
      final rate = InsuranceRateModel.defaults2026();
      final deduction = (1000000 * rate.nationalPensionRate / 100).round();
      expect(deduction, 47500);
    });
    test('N-51 건강보험 근로자 부담: 100만원 × 3.595% = 35950원', () {
      final rate = InsuranceRateModel.defaults2026();
      final deduction = (1000000 * rate.healthInsuranceRate / 100).round();
      expect(deduction, 35950);
    });
    test('N-52 고용보험 근로자 부담: 100만원 × 0.9% = 9000원', () {
      final rate = InsuranceRateModel.defaults2026();
      final deduction = (1000000 * rate.employmentInsuranceRate / 100).round();
      expect(deduction, 9000);
    });
    test('N-53 프리랜서 원천징수 3.3%: 100만원 × 3.3% = 33000원', () {
      final rate = InsuranceRateModel.defaults2026();
      final total = rate.businessIncomeRate + rate.businessIncomeLocalRate; // 3.0 + 0.3
      final deduction = (1000000 * total / 100).round();
      expect(deduction, 33000);
    });
    test('N-54 일용직 소득세: 200000원 − 150000원(비과세) = 50000원 × 2.7% = 1350원', () {
      final rate = InsuranceRateModel.defaults2026();
      final taxableAmount = 200000 - rate.dailyWageExemption; // 50000
      final tax = (taxableAmount * rate.dailyWorkerTaxRate / 100).round();
      expect(tax, 1350);
    });
    test('N-55 일용직 소득세 비과세 한도 이하: 150000원 → 세금 0원', () {
      final rate = InsuranceRateModel.defaults2026();
      final taxableAmount = 150000 - rate.dailyWageExemption; // 0
      final tax = taxableAmount > 0 ? (taxableAmount * rate.dailyWorkerTaxRate / 100).round() : 0;
      expect(tax, 0);
    });
    test('N-56 장기요양보험 공제: 건강보험 공제액에 비율 적용', () {
      final rate = InsuranceRateModel.defaults2026();
      final healthDeduction = (1000000 * rate.healthInsuranceRate / 100).round(); // 35950
      final ltcDeduction = (healthDeduction * rate.ltcInsuranceRate / 100).round(); // 35950 × 13.14% ≈ 4724
      expect(ltcDeduction, closeTo(4724, 5)); // 부동소수점 허용 ±5
    });

    // ── N-7. ContractTemplateModel.copyWith ──────────────────────────────────
    test('N-60 ContractTemplateModel copyWith name 변경', () {
      final original = ContractTemplateModel(
        id: 't1', businessId: 'biz1', name: '원본명',
        templateType: ContractTemplateType.daily,
        articles: ContractTemplateModel.defaultArticlesFor('daily'),
        createdAt: DateTime(2025, 1, 1),
      );
      final copied = original.copyWith(name: '수정명');
      expect(copied.name, '수정명');
      expect(original.name, '원본명');
      expect(copied.templateType, 'daily');
    });
    test('N-61 ContractTemplateModel copyWith articles 비우기', () {
      final original = ContractTemplateModel(
        id: 't1', businessId: 'biz1', name: '이름',
        templateType: ContractTemplateType.period,
        articles: ContractTemplateModel.defaultArticlesFor('period'),
        createdAt: DateTime(2025, 1, 1),
      );
      final copied = original.copyWith(articles: []);
      expect(copied.articles.isEmpty, true);
      expect(original.articles.length, 12);
    });

    // ── N-8. ContractSnapshot toMap → fromMap 왕복 ────────────────────────────
    test('N-70 ContractSnapshot toMap → fromMap 왕복 (기본값)', () {
      final original = _snap(
        startTime: '10:00', endTime: '19:00', breakMinutes: 60,
        wage: 12000, wageType: 'hourly',
        payScheduleType: 'monthly', payScheduleDay: 25, payScheduleTime: '10:00',
      );
      final m = original.toMap();
      final restored = ContractSnapshot.fromMap(m);
      expect(restored.startTime, '10:00');
      expect(restored.endTime, '19:00');
      expect(restored.breakMinutes, 60);
      expect(restored.wage, 12000);
      expect(restored.wageType, 'hourly');
      expect(restored.payScheduleType, 'monthly');
      expect(restored.payScheduleDay, 25);
      expect(restored.payScheduleTime, '10:00');
    });
    test('N-71 ContractSnapshot toMap → fromMap 장기 계약', () {
      final original = _snap(
        isLongTerm: true,
        contractStart: '2025-01-06',
        contractEnd: '2025-06-30',
        workDays: ['월','화','수','목','금'],
      );
      final m = original.toMap();
      final restored = ContractSnapshot.fromMap(m);
      expect(restored.isLongTerm, true);
      expect(restored.contractStart, '2025-01-06');
      expect(restored.contractEnd, '2025-06-30');
      expect(restored.workDays, ['월','화','수','목','금']);
    });
    test('N-72 payScheduleType null → toMap에서 key 없음', () {
      final m = _snap().toMap();
      expect(m.containsKey('payScheduleType'), false);
      expect(m.containsKey('payScheduleDay'), false);
      expect(m.containsKey('payScheduleTime'), false);
    });
    test('N-73 payScheduleType 있으면 → toMap에서 key 있음', () {
      final m = _snap(payScheduleType: 'weekly', payScheduleDay: 3, payScheduleTime: '18:00').toMap();
      expect(m['payScheduleType'], 'weekly');
      expect(m['payScheduleDay'], 3);
      expect(m['payScheduleTime'], '18:00');
    });
  });
}
