// [LATE-RENEW-EFFECTIVE-DATE-POLICY]
//
// Post-expiry renewal must use an explicit effective date.
// Core V1 ordinary renewal does not silently infer retroactive D+1
// continuity.
//
// This is a product-safety rule, not a legal determination that
// employment continuity is broken by a calendar gap.
//
// ─────────────────────────────────────────────────────────────────
//
//   OLD 종료 = 9/20 · 오늘 = 9/26 · 관리자가 연장
//     → 예전 결과: NEW 시작 = 9/21
//
// 9/21~9/25 에는 근무 자격도 근태도 결근 의무도 좌석도 없었다.
// 나중에 버튼을 눌렀다는 이유로 그 기간이 새 계약기간이 되면 안 된다.
//
// 그리고 그 어긋남은 보이지도 않았다 — Application 과 Contract 는
// 9/21 이라 말하고, eligibility 만 confirmedAt 보정으로 9/26 으로
// 당겨졌다. 한 진실이 다른 진실을 덮고 있었다.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:ALfit/models/core/application_model.dart';
import 'package:ALfit/utils/format_helper.dart';
import 'package:ALfit/utils/renewal_effective_date.dart';

const _cfPath = 'functions/src/index.ts';
const _fixedWorkerPath =
    'lib/screens/business_admin/dialogs/fixed_worker_management_dialog.dart';
const _contractSvcPath = 'lib/services/contract_service.dart';

String _src(String p) {
  final f = File(p);
  if (!f.existsSync()) throw StateError('$p 를 찾지 못함');
  return f.readAsStringSync();
}

/// 주석 줄을 지운 본문. 앵커는 주석이 아니라 **코드**여야 한다.
String _codeOf(String s) =>
    s.split('\n').where((l) => !l.trimLeft().startsWith('//')).join('\n');

String _after(String src, String name, int chars) {
  final i = src.indexOf(name);
  if (i < 0) throw StateError('$name 를 찾지 못함');
  return src.substring(i, (i + chars).clamp(0, src.length));
}

DateTime _k(int y, int m, int d) => DateTime.utc(y, m, d);

/// 2026-06-21 ~ 2026-09-20 (3개월) 장기 계약.
ApplicationModel _app({
  DateTime? start,
  DateTime? end,
  DateTime? actualResignDate,
}) =>
    ApplicationModel(
      id: 'app1',
      businessId: 'biz1',
      businessName: '위워커',
      toTitle: '[테스트] 장기',
      workDate: start ?? _k(2026, 6, 21),
      workEndDate: end ?? _k(2026, 9, 20),
      workDays: const ['월', '화', '수', '목', '금'],
      startTime: '09:00',
      endTime: '18:00',
      uid: 'worker1',
      selectedWorkType: '사무업무',
      wage: 12000,
      wageType: 'hourly',
      status: AppStatus.confirmed,
      appliedAt: _k(2026, 6, 1),
      confirmedAt: _k(2026, 6, 15),
      actualResignDate: actualResignDate,
    );

void main() {
  final cf = _codeOf(_src(_cfPath));
  final fixedWorker = _codeOf(_src(_fixedWorkerPath));
  final contractSvc = _codeOf(_src(_contractSvcPath));

  // ══════════════════════════════════════════════════════════════
  // A~C. 만료 전 / 종료 당일 / 만료 후 기본값 (§30 A·B·C)
  // ══════════════════════════════════════════════════════════════
  group('01. 기본 시작일', () {
    test('A 만료 전(D-5) → D+1', () {
      final p = defaultRenewalPeriod(_app(), _k(2026, 9, 15));
      expect(p.isLate, false);
      expect(p.start, _k(2026, 9, 21));
    });

    test('B 종료 당일(D) → D+1 — D 는 마지막 근무일이지 만료가 아니다', () {
      final p = defaultRenewalPeriod(_app(), _k(2026, 9, 20));
      expect(p.isLate, false);
      expect(p.start, _k(2026, 9, 21));
    });

    test('C 만료 후(D+6) → 오늘 — 소급 D+1 아님', () {
      final p = defaultRenewalPeriod(_app(), _k(2026, 9, 26));
      expect(p.isLate, true);
      expect(p.start, _k(2026, 9, 26));
      expect(p.start, isNot(_k(2026, 9, 21)));
    });

    test('C-2 만료 다음 날(D+1) → 오늘 = D+1 — 값은 같아도 late 다', () {
      final p = defaultRenewalPeriod(_app(), _k(2026, 9, 21));
      expect(p.isLate, true);
      expect(p.start, _k(2026, 9, 21));
    });

    test('C-3 아주 오래 지난 뒤(D+400) → 오늘', () {
      final today = _k(2027, 10, 25);
      final p = defaultRenewalPeriod(_app(), today);
      expect(p.isLate, true);
      expect(p.start, today);
    });

    test('C-4 퇴사 효력일이 있으면 그것이 종료 기준이다', () {
      final app = _app(actualResignDate: _k(2026, 8, 31));
      expect(isLateRenewal(app, _k(2026, 9, 1)), true);
      expect(defaultRenewalPeriod(app, _k(2026, 9, 5)).start, _k(2026, 9, 5));
    });
  });

  // ══════════════════════════════════════════════════════════════
  // 02. 기간 승계 (§25)
  // ══════════════════════════════════════════════════════════════
  group('02. 계약기간 승계', () {
    test('02-a 원본 개월 수를 그대로 가져온다', () {
      expect(renewalMonthsOf(_app()), 3);
    });

    test('02-b 만료 전: 예전 계산과 결과가 같다 — 회귀 고정', () {
      final p = defaultRenewalPeriod(_app(), _k(2026, 9, 15));
      // 예전: oldEnd(9/20) + 3개월, 일자 clamp → 12/20
      expect(p.start, _k(2026, 9, 21));
      expect(p.end, _k(2026, 12, 20));
    });

    test('02-c 만료 후: 시작일 기준으로 계산해 기간이 짧아지지 않는다', () {
      final p = defaultRenewalPeriod(_app(), _k(2026, 9, 26));
      expect(p.start, _k(2026, 9, 26));
      expect(p.end, _k(2026, 12, 25)); // 9/25 + 3개월
      // 예전처럼 oldEnd 기준이면 12/20 — 5일 짧은 계약이 됐다.
      expect(p.end, isNot(_k(2026, 12, 20)));
    });

    test('02-d 월말 일자는 그 달의 마지막 날로 clamp 된다', () {
      final app = _app(start: _k(2026, 5, 31), end: _k(2026, 8, 30));
      final p = renewalPeriodFrom(app, _k(2026, 11, 1), isLate: true);
      expect(p.months, 3);
      expect(p.end, _k(2027, 1, 31));
    });

    test('02-e 시작 < 종료 는 항상 성립한다', () {
      for (final today in [
        _k(2026, 9, 1), _k(2026, 9, 20), _k(2026, 9, 21), _k(2027, 3, 3),
      ]) {
        final p = defaultRenewalPeriod(_app(), today);
        expect(p.start.isBefore(p.end), true, reason: '$today');
      }
    });
  });

  // ══════════════════════════════════════════════════════════════
  // 03. 서버 검증 (§10 · §30 D·E·F·G)
  // ══════════════════════════════════════════════════════════════
  group('03. 서버가 마지막 판단을 한다', () {
    final renewal =
        _after(cf, 'export const callableCreateContractRenewal', 7900);

    test('03-a D 만료 후 과거 시작 요청을 거절한다', () {
      expect(renewal, contains('todayNum > originalEndNum && newStartNum < todayNum'));
      expect(renewal,
          contains('이미 계약이 만료되어 오늘 이후 날짜부터 새 계약을 시작할 수 있습니다.'));
    });

    test('03-b G newStart == oldEnd 거절은 그대로다 — 회귀 고정', () {
      expect(renewal, contains('if (newStartNum <= originalEndNum)'));
      expect(renewal,
          contains('갱신 계약 시작일은 원본 계약 종료일 다음 날부터여야 합니다.'));
    });

    test('03-c 오늘 기준 비교는 KST 달력일로 한다', () {
      expect(renewal, contains('const todayNum = srvKstDateNum(new Date());'));
      expect(renewal.contains('new Date().getDate()'), false);
    });

    test('03-d 만료 전에는 새 규칙이 끼어들지 않는다', () {
      // 게이트가 `todayNum > originalEndNum` 안에만 있다.
      final at = renewal.indexOf('todayNum > originalEndNum');
      expect(at, isNot(-1));
      expect(renewal.substring(at, at + 120), contains('newStartNum < todayNum'));
    });

    test('03-e 법적 단정 문구를 쓰지 않는다', () {
      for (final banned in ['재입사', '계속근로가 단절', '근로관계가 완전히 종료']) {
        expect(renewal.contains(banned), false, reason: banned);
      }
    });
  });

  // ══════════════════════════════════════════════════════════════
  // 04. Application / Contract / eligibility 가 같은 날을 말한다 (§12·§13)
  // ══════════════════════════════════════════════════════════════
  group('04. 세 값이 같은 E 를 말한다', () {
    final renewal =
        _after(cf, 'export const callableCreateContractRenewal', 7900);

    test('04-a 명시적 효력일을 저장한다 — desiredStartDate', () {
      expect(renewal,
          contains('desiredStartDate: admin.firestore.Timestamp.fromMillis(newStartDateMs)'));
      expect(renewal.contains('desiredStartDate: null'), false);
    });

    test('04-b Application.workDate 도 같은 값이다', () {
      expect(renewal,
          contains('workDate: admin.firestore.Timestamp.fromMillis(newStartDateMs)'));
    });

    test('04-c Contract 시작일은 desiredStartDate 를 먼저 본다', () {
      expect(contractSvc,
          contains('_fmtDate(application.desiredStartDate ?? application.workDate)'));
    });

    test('04-d eligibility 도 desiredStartDate 를 먼저 본다', () {
      final r = _after(cf, 'function srvLongTermEligibleOnDay(', 1400);
      expect(r, contains('const desired = ts("desiredStartDate");'));
      // confirmedAt 보정은 desiredStartDate 가 없을 때만 걸린다.
      expect(r, contains('if (!desired) {'));
    });

    test('04-e confirmedAt 보정 기능 자체는 제거하지 않았다', () {
      final r = _after(cf, 'function srvLongTermEligibleOnDay(', 1400);
      expect(r, contains('const confirmed = ts("confirmedAt");'));
      expect(r, contains('if (cNum > startNum) startNum = cNum;'));
    });
  });

  // ══════════════════════════════════════════════════════════════
  // 05. gap 기간에 아무 의무도 만들지 않는다 (§18·§32)
  // ══════════════════════════════════════════════════════════════
  group('05. 공백 기간 = NO WORK', () {
    final renewal =
        _after(cf, 'export const callableCreateContractRenewal', 7900);

    test('05-a 연장 writer 가 과거 근태/임금을 만들지 않는다', () {
      for (final banned in [
        'collection("attendance")', 'NO_SHOW', 'collection("payrolls")',
      ]) {
        expect(renewal.contains(banned), false, reason: banned);
      }
    });

    test('05-b 새 계약의 휴무·추가근무는 빈 상태로 시작한다', () {
      expect(renewal, contains('leaveDates: []'));
      expect(renewal, contains('extraWorkDates: []'));
    });

    test('05-c 임금 집계는 0 에서 시작한다', () {
      expect(renewal, contains('wageStatus: "pending"'));
      expect(renewal, contains('finalWage: null'));
    });

    test('05-d E 이전은 eligibility 가 BEFORE_START 로 막는다', () {
      final r = _after(cf, 'function srvLongTermEligibleOnDay(', 1400);
      expect(r,
          contains('if (dayNum < startNum) return {eligible: false, reason: "BEFORE_START"}'));
    });
  });

  // ══════════════════════════════════════════════════════════════
  // 06. 진입점이 달라도 결과는 같다 (§23 · §30 H)
  // ══════════════════════════════════════════════════════════════
  group('06. 진입점 parity', () {
    test('06-a 개별 연장이 공용 정책 helper 를 쓴다', () {
      expect(fixedWorker, contains('defaultRenewalPeriod(app, todayKst)'));
    });

    test('06-b 일괄 연장도 같은 helper 를 쓴다', () {
      expect(fixedWorker,
          contains('defaultRenewalPeriod(app, FormatHelper.toKstDate(DateTime.now()))'));
    });

    test('06-c 어디에도 지역 D+1 계산이 남아 있지 않다', () {
      expect(
        fixedWorker.contains("app.workEndDate!.add(const Duration(days: 1))"),
        false,
      );
    });

    test('06-f 배너도 기간을 다시 계산하지 않고 실제 지원서를 읽는다', () {
      final seg = _after(fixedWorker,
          'Widget _buildRenewalDecisionBanner(', 900);
      expect(seg, contains('_renewedApps[app.id]'));
      expect(seg, contains('renewed.desiredStartDate ?? renewed.workDate'));
      // 못 읽으면 틀린 날짜 대신 날짜를 말하지 않는다.
      expect(seg, contains("'다음 계약 연장됨'"));
    });

    test('06-d 쓰기 경로는 호출자가 정한 시작일을 그대로 넘긴다', () {
      final seg = _after(fixedWorker, 'Future<ApplicationModel?> _processRenewal(', 1700);
      expect(seg, contains('newStartDate: newStartDate,'));
    });

    test('06-e 같은 fixture + 같은 오늘 → 같은 기간', () {
      final a = defaultRenewalPeriod(_app(), _k(2026, 9, 26));
      final b = defaultRenewalPeriod(_app(), _k(2026, 9, 26));
      expect(a.start, b.start);
      expect(a.end, b.end);
      expect(a.months, b.months);
    });
  });

  // ══════════════════════════════════════════════════════════════
  // 07. UI — 명시적 선택과 문구 (§8·§9·§29)
  // ══════════════════════════════════════════════════════════════
  group('07. 만료 후 UI', () {
    test('07-a 만료 뒤에는 시작일을 고르게 한다', () {
      expect(fixedWorker, contains('_pickLateRenewalStart(app, todayKst, period)'));
      expect(fixedWorker, contains("title: '새 계약 시작일'"));
    });

    test('07-b 과거는 고를 수 없다', () {
      final seg = _after(fixedWorker, 'Future<RenewalPeriod?> _pickLateRenewalStart(', 1100);
      expect(seg, contains('minDate: minStart'));
      expect(seg, contains('!FormatHelper.toKstDate(date).isBefore(minStart)'));
    });

    test('07-c 기본 날짜는 고를 수 있는 가장 이른 날 = 오늘', () {
      final seg = _after(fixedWorker, 'Future<RenewalPeriod?> _pickLateRenewalStart(', 1100);
      expect(seg, contains('initialDate: current.start'));
      expect(seg, contains('earliestRenewalStart(app, todayKst)'));
    });

    test('07-d 법적 단정 문구를 쓰지 않는다', () {
      for (final banned in [
        '재입사', '계속근로가 단절', '근로관계가 완전히 종료',
      ]) {
        expect(fixedWorker.contains(banned), false, reason: banned);
      }
    });

    test('07-e 허용된 문구를 쓴다', () {
      expect(fixedWorker, contains('기존 계약기간이 종료되었습니다.'));
      expect(fixedWorker, contains('계약 시작일부터 새로운 근무 일정이 적용됩니다.'));
    });

    test('07-f 일괄 연장은 시작일이 사람마다 다를 수 있음을 말한다', () {
      expect(fixedWorker, contains('기간이 이미 종료된 \$lateCount명은 오늘부터 시작합니다.'));
      expect(fixedWorker.contains('동일 기간으로 일괄 연장합니다'), false);
    });
  });

  // ══════════════════════════════════════════════════════════════
  // 08. 건드리지 않은 것 (§14·§26·§27·§34·§39)
  // ══════════════════════════════════════════════════════════════
  group('08. 무회귀', () {
    final renewal =
        _after(cf, 'export const callableCreateContractRenewal', 7900);

    test('08-a NEW 는 여전히 CONTRACT_PENDING 이다', () {
      expect(renewal, contains('status: "CONTRACT_PENDING"'));
    });

    test('08-b promise snapshot 은 날짜 때문에 바뀌지 않는다', () {
      // 임금·요일·시간·세금은 원본 spread 로 승계된다.
      expect(renewal, contains('...freshData,'));
      for (final banned in ['wage:', 'workDays:', 'startTime:', 'endTime:']) {
        expect(renewal.contains('\n        $banned'), false, reason: banned);
      }
    });

    test('08-c OLD 에는 관계 정보만 더한다', () {
      expect(renewal, contains('renewalDecision: "EXTEND"'));
      expect(renewal, contains('renewedToApplicationId: newApplicationId'));
      expect(renewal.contains('tx.update(originalRef, {workEndDate'), false);
    });

    test('08-d 계약 lineage 를 법적 결론으로 저장하지 않는다', () {
      for (final banned in [
        'continuousService', 'isRehire', 'employmentContinuity',
      ]) {
        expect(cf.contains(banned), false, reason: banned);
      }
    });

    test('08-e 권한은 canManageContract 그대로다', () {
      expect(renewal, contains('memberPermsForRenewal.canManageContract'));
      expect(fixedWorker, contains('_canManageContract()'));
    });

    test('08-f 자동 연장을 되살리지 않았다', () {
      final scheduler =
          _after(cf, 'async function processContractRenewalChecks(', 12000);
      expect(scheduler.contains('status: "CONFIRMED"'), false);
      expect(scheduler.contains('renewalDecision: "EXTEND"'), false);
    });

    test('08-g 30일 소급 하한도 그대로 남아 있다 — 이중 방어', () {
      expect(renewal, contains('계약 시작일은 30일 이전으로 소급할 수 없습니다.'));
    });
  });
}
