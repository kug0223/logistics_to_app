// [CORRECTION-EXPIRED-UNDECIDED-RENEWAL-ACTION-SURFACE]
//
// 자동 연장을 걷어낸 뒤([AUTO-RENEW-POLICY]) 드러난 것:
//
//     action 은 살아 있는데 action required 신호가 사라진다.
//
// Home 은 `workEndDate >= today` 로 조회했고 만료 화면은 `diff >= 0` 으로
// 걸렀다. 둘 다 종료일이 지나는 순간 그 사람을 잊었다. 자동 연장이 그
// 순간 결정을 대신 내려 주던 동안에는 드러나지 않던 결함이다.
//
// 그리고 반대쪽도 있었다 — 이미 연장한 관계를 원래 종료일까지 계속
// "종료 예정"으로 세고 있었다. `renewalDecision` 을 아무도 보지 않았다.
//
//     근무 가능 여부  ≠  계약 결정 처리 여부
//
// 만료는 할 일이 없어진 것이 아니라 **늦은** 것이다.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:ALfit/models/core/application_model.dart';
import 'package:ALfit/utils/renewal_decision_state.dart';

const _cfPath = 'functions/src/index.ts';
const _homePath = 'lib/screens/business_admin/business_admin_home_screen.dart';
const _expiringPath = 'lib/screens/business_admin/expiring_contracts_screen.dart';
const _fixedWorkerPath =
    'lib/screens/business_admin/dialogs/fixed_worker_management_dialog.dart';
const _appSvcPath = 'lib/services/firestore/application_firestore.dart';

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

DateTime _d(int y, int m, int day) => DateTime(y, m, day);
final _today = _d(2026, 10, 1);

/// 종료일 [end] 인 장기 확정 근무관계.
ApplicationModel _app({
  required DateTime end,
  String? renewalDecision,
  String? resignStatus,
  String? terminationStatus,
  DateTime? actualResignDate,
  String status = AppStatus.confirmed,
  bool longTerm = true,
}) =>
    ApplicationModel(
      id: 'app1',
      businessId: 'biz1',
      businessName: '위워커',
      toTitle: '[테스트] 장기',
      workDate: longTerm ? _d(2026, 9, 1) : end,
      workEndDate: end,
      workDays: longTerm ? const ['월', '화', '수', '목', '금'] : null,
      startTime: '09:00',
      endTime: '18:00',
      uid: 'worker1',
      selectedWorkType: '사무업무',
      wage: 12000,
      wageType: 'hourly',
      status: status,
      appliedAt: _d(2026, 8, 25),
      confirmedAt: _d(2026, 9, 1),
      renewalDecision: renewalDecision,
      resignStatus: resignStatus,
      terminationStatus: terminationStatus,
      actualResignDate: actualResignDate,
    );

void main() {
  final cf = _codeOf(_src(_cfPath));
  final home = _codeOf(_src(_homePath));
  final expiring = _codeOf(_src(_expiringPath));
  final fixedWorker = _codeOf(_src(_fixedWorkerPath));
  final appSvc = _codeOf(_src(_appSvcPath));

  // ══════════════════════════════════════════════════════════════
  // 01. 날짜 matrix (§35)
  // ══════════════════════════════════════════════════════════════
  group('01. 날짜 경계', () {
    RenewalDecisionState at(int daysFromToday) => renewalDecisionStateOf(
          _app(end: _today.add(Duration(days: daysFromToday))),
          _today,
        );

    test('01-a D-16 — 아직 이르다', () {
      expect(at(16), RenewalDecisionState.notApplicable);
    });

    test('01-b D-15 — 결정 시점', () {
      expect(at(15), RenewalDecisionState.upcoming);
    });

    test('01-c D — 마지막 근무일이지만 결정은 아직', () {
      expect(at(0), RenewalDecisionState.upcoming);
    });

    test('01-d D+1 — 만료 · 결정 필요', () {
      expect(at(-1), RenewalDecisionState.expired);
    });

    test('01-e D+30 — 시간이 지나도 사라지지 않는다', () {
      expect(at(-30), RenewalDecisionState.expired);
    });

    test('01-f D+365 — 오래돼도 미결정은 미결정이다', () {
      // 만료 쪽에 하한을 두면 그때부터 또 조용히 사라진다.
      expect(at(-365), RenewalDecisionState.expired);
    });

    test('01-g 만료 일수를 센다', () {
      expect(renewalOverdueDays(_app(end: _today.subtract(const Duration(days: 3))), _today), 3);
      expect(renewalOverdueDays(_app(end: _today.add(const Duration(days: 3))), _today), isNull);
    });
  });

  // ══════════════════════════════════════════════════════════════
  // 02. 해결 matrix (§36)
  // ══════════════════════════════════════════════════════════════
  group('02. 같은 D+1 에서 결정 상태별', () {
    final expired = _today.subtract(const Duration(days: 1));

    test('02-a 미결정 → EXPIRED', () {
      expect(renewalDecisionStateOf(_app(end: expired), _today),
          RenewalDecisionState.expired);
    });

    test('02-b EXTEND → 해결', () {
      expect(
        renewalDecisionStateOf(
            _app(end: expired, renewalDecision: AppStatus.renewalExtend), _today),
        RenewalDecisionState.resolved,
      );
    });

    test('02-c TERMINATE → 해결', () {
      expect(
        renewalDecisionStateOf(
            _app(end: expired, renewalDecision: AppStatus.renewalTerminate), _today),
        RenewalDecisionState.resolved,
      );
    });

    test('02-d 퇴사 승인 → 해결', () {
      for (final s in [AppStatus.approved, AppStatus.autoApproved]) {
        expect(renewalDecisionStateOf(_app(end: expired, resignStatus: s), _today),
            RenewalDecisionState.resolved, reason: s);
      }
    });

    test('02-e 해지 승인 → 해결', () {
      for (final s in [AppStatus.approved, AppStatus.autoApproved]) {
        expect(
            renewalDecisionStateOf(_app(end: expired, terminationStatus: s), _today),
            RenewalDecisionState.resolved, reason: s);
      }
    });

    test('02-f 이미 연장한 건은 종료일 이전에도 세지 않는다 — 회귀 고정', () {
      // 예전에는 renewalDecision 을 보지 않아 원래 종료일까지 계속 task 였다.
      expect(
        renewalDecisionStateOf(
          _app(end: _today.add(const Duration(days: 5)),
              renewalDecision: AppStatus.renewalExtend),
          _today,
        ),
        RenewalDecisionState.resolved,
      );
    });

    test('02-g 단기는 대상이 아니다', () {
      expect(
        renewalDecisionStateOf(
            _app(end: _today, longTerm: false, status: AppStatus.confirmed), _today),
        RenewalDecisionState.notApplicable,
      );
    });

    test('02-h 퇴사 효력일이 있으면 그것이 종료 기준이다', () {
      final a = _app(
        end: _today.add(const Duration(days: 20)),
        actualResignDate: _today.subtract(const Duration(days: 2)),
      );
      // resign 이 승인 상태가 아니면(요청만) 결정은 여전히 남아 있고,
      // 기간 기준은 actualResignDate 다.
      expect(renewalDecisionStateOf(a, _today), RenewalDecisionState.expired);
    });
  });

  // ══════════════════════════════════════════════════════════════
  // 03. 근무 eligibility 와 task 는 별개다 (§37)
  // ══════════════════════════════════════════════════════════════
  group('03. 근무 ≠ 결정', () {
    test('03-a D — 근무 YES · task UPCOMING', () {
      // 2026-10-01 목요일, 평일 근무
      final a = _app(end: _today);
      expect(_today.weekday, DateTime.thursday);
      expect(a.isWorkingOnDate(_today), true);
      expect(renewalDecisionStateOf(a, _today), RenewalDecisionState.upcoming);
    });

    test('03-b D+1 미결정 — 근무 NO · task EXPIRED', () {
      final a = _app(end: _today.subtract(const Duration(days: 1)));
      expect(a.isWorkingOnDate(_today), false);
      expect(renewalDecisionStateOf(a, _today), RenewalDecisionState.expired);
    });

    test('03-c D+1 EXTEND — 근무 NO · task 없음', () {
      // 구 계약은 그 뒤로 일하지 않는다. 결정은 끝났다.
      final a = _app(
        end: _today.subtract(const Duration(days: 1)),
        renewalDecision: AppStatus.renewalExtend,
      );
      expect(a.isWorkingOnDate(_today), false);
      expect(needsRenewalDecision(a, _today), false);
    });
  });

  // ══════════════════════════════════════════════════════════════
  // 04. 우선순위 (§10)
  // ══════════════════════════════════════════════════════════════
  group('04. 만료가 먼저다', () {
    test('04-a 만료 건이 예정 건보다 앞선다', () {
      final overdue = _app(end: _today.subtract(const Duration(days: 2)));
      final soon = _app(end: _today.add(const Duration(days: 1)));
      expect(compareRenewalUrgency(overdue, soon, _today), lessThan(0));
      expect(compareRenewalUrgency(soon, overdue, _today), greaterThan(0));
    });

    test('04-b 같은 상태에서는 종료일이 이른 순', () {
      final a = _app(end: _today.subtract(const Duration(days: 5)));
      final b = _app(end: _today.subtract(const Duration(days: 1)));
      expect(compareRenewalUrgency(a, b, _today), lessThan(0));
    });
  });

  // ══════════════════════════════════════════════════════════════
  // 05. 세 화면이 같은 판정식을 쓴다 (§26)
  // ══════════════════════════════════════════════════════════════
  group('05. 하나의 판정식', () {
    test('05-a 만료 화면이 공용 판정식을 쓴다', () {
      expect(expiring.contains('needsRenewalDecision(app, todayOnly)'), true);
      expect(expiring.contains('compareRenewalUrgency(a, b, todayOnly)'), true);
      // 자체 날짜 조건이 남아 있지 않다.
      expect(expiring.contains('diff >= 0 && diff <= _daysWindow'), false);
    });

    test('05-b 고정근무자 목록이 공용 판정식을 쓴다', () {
      expect(fixedWorker.contains('renewalDecisionStateOf('), true);
      expect(fixedWorker.contains('RenewalDecisionState.expired'), true);
    });

    test('05-c 배너가 만료 후에도 뜬다', () {
      expect(
        fixedWorker.contains(
            'needsRenewalDecision(app, FormatHelper.toKstDate(DateTime.now()))'),
        true,
      );
      // 예전 게이트(diff >= 0)가 배너를 끄던 자리.
      expect(
        fixedWorker.contains(
            '_isExpiringWithinDays(app, 15) && app.renewalDecision == null)\n'
            '                _buildRenewalBanner'),
        false,
      );
    });

    test('05-d 서버 Home 도 같은 규칙이다', () {
      final h = _after(cf, 'async function srvHomeExpiringContract(', 3200);
      // 이미 결정한 건은 세지 않는다.
      expect(h.contains('if (d["renewalDecision"]) continue;'), true);
      // 만료 쪽을 잘라내지 않는다.
      expect(h.contains('.where("workEndDate", ">=", todayTs)'), false);
      expect(h.contains('if (endNum < todayNum) expired++;'), true);
      // KST 달력 날짜로 비교한다.
      expect(h.contains('srvKstDateNum(endTs.toDate())'), true);
      expect(h.contains('Math.floor((endTs.toMillis() - todayMs)'), false);
    });

    test('05-e 조회 자체가 만료 쪽으로도 열려 있다', () {
      // 필터를 고쳐도 조회되지 않으면 나타날 수 없다.
      //
      // [BLOCKER-RENEWAL-DECISION-QUEUE-POPULATION-PARITY]
      //   처음에는 180일 하한으로 열었다. 그 하한마저 없앴다 —
      //   더 자세한 고정은 renewal_queue_population_test.dart 에 있다.
      final seg = appSvc.substring(
          appSvc.indexOf('getExpiringLongTermApplications('));
      expect(seg.substring(0, 1600).contains('workEndDateGteMs'), false);
      expect(seg, contains('renewalCandidateEndBefore(fromDate)'));
    });
  });

  // ══════════════════════════════════════════════════════════════
  // 06. Home 표현 (§9·§23·§24)
  // ══════════════════════════════════════════════════════════════
  group('06. Home', () {
    test('06-a 만료를 "예정"이라 부르지 않는다', () {
      expect(home.contains("label: '계약 확인 필요'"), true);
      expect(home.contains("label: '계약 종료 예정'"), false);
    });

    test('06-b 늦은 건수를 따로 말한다', () {
      expect(home.contains('expiredCount > 0'), true);
      expect(home.contains("'\$totalDecisions명 · 만료 \$expiredCount'"), true);
    });

    test('06-c 서버가 만료 건수를 따로 보낸다', () {
      expect(cf.contains('expiredCount: expiredContractTotal'), true);
      expect(cf.contains('expiringContract?.expired ?? 0'), true);
    });

    test('06-d 권한 게이트가 유지된다', () {
      expect(cf.contains('hasBizPerm(r.bizId, "canManageContract")'), true);
      expect(home.contains('_verified(up, (p) => p.canManageContract)'), true);
    });

    test('06-e available 이 ERROR 와 ZERO 를 가른다', () {
      final h = _after(cf, 'const aggSimple =', 900);
      expect(h.contains('available: permCount > 0 && successCount === permCount'),
          true);
    });

    test('06-f 사업장별로 분리된다', () {
      expect(cf.contains('byBusiness.push({businessId: r.bizId, count: v})'), true);
    });
  });

  // ══════════════════════════════════════════════════════════════
  // 07. 현재 근무자 ≠ 만료 근로자 (§16~§18)
  // ══════════════════════════════════════════════════════════════
  group('07. 고정근무자 집계', () {
    test('07-a 정상 집계에서 만료·미결정을 뺀다', () {
      expect(
        fixedWorker.contains(
            'w.application.resignStatus == null && !isExpiredUndecided(w)'),
        true,
      );
    });

    test('07-b 만료·미결정을 따로 센다', () {
      expect(fixedWorker.contains('expiredDecisionCount'), true);
      expect(fixedWorker.contains("_buildStatChip(\n                context, '계약 확인', expiredDecisionCount"),
          true);
    });

    test('07-c 목록에서 빼지는 않는다 — 빼면 연장 경로가 사라진다', () {
      // 기본 필터는 status·장기·퇴사/해지 완료만 본다. 만료 여부로
      // 걸러내면 그 사람에게 닿을 길이 없어진다.
      //   (날짜 모드의 EXTEND 복원 분기는 별개다 — 그 자리는 구 계약이
      //    그 날짜를 덮는지 보는 곳이지 만료를 배제하는 곳이 아니다.)
      final load = _after(fixedWorker, 'final allFiltered = allApps.where((app)', 700);
      expect(load.contains('renewalDecisionStateOf'), false);
      expect(load.contains('RenewalDecisionState'), false);
      expect(load.contains('isTerminationApproved'), true);
    });

    test('07-d 행 액션의 계약 연장에는 날짜 창이 없다', () {
      expect(
        fixedWorker.contains('if (app.workEndDate != null &&\n'
            '                    app.renewalDecision == null &&\n'
            '                    !app.isTerminationApproved) ...['),
        true,
      );
    });
  });

  // ══════════════════════════════════════════════════════════════
  // 08. 알림은 task 가 아니다 (§7·§8)
  // ══════════════════════════════════════════════════════════════
  group('08. Notification ≠ Task', () {
    test('08-a Home 집계가 알림 문서를 읽지 않는다', () {
      final h = _after(cf, 'async function srvHomeExpiringContract(', 3200);
      expect(h.contains('notifications'), false);
      expect(h.contains('isRead'), false);
    });

    test('08-b task 는 applications 에서만 파생된다', () {
      final h = _after(cf, 'async function srvHomeExpiringContract(', 3200);
      expect(h.contains('db.collection("applications")'), true);
    });

    test('08-c 판정식이 알림 상태를 보지 않는다', () {
      final rd = _codeOf(_src('lib/utils/renewal_decision_state.dart'));
      for (final banned in ['notification', 'isRead', 'readAt']) {
        expect(rd.contains(banned), false, reason: banned);
      }
    });
  });

  // ══════════════════════════════════════════════════════════════
  // 09. 새 persisted 상태를 만들지 않았다 (§46)
  // ══════════════════════════════════════════════════════════════
  group('09. 파생 상태', () {
    test('09-a Firestore 중복 필드를 만들지 않았다', () {
      for (final banned in ['isExpired', 'needsRenewal:', 'renewalOverdue:']) {
        expect(cf.contains(banned), false, reason: banned);
      }
    });

    test('09-b 판정식이 저장하지 않는다 — 순수 함수다', () {
      final rd = _codeOf(_src('lib/utils/renewal_decision_state.dart'));
      for (final banned in ['FirebaseFirestore', 'set(', 'update(', 'await ']) {
        expect(rd.contains(banned), false, reason: banned);
      }
    });

    test('09-c 스케줄러가 상태를 추측해 쓰지 않는다 — 회귀 고정', () {
      final scheduler =
          _after(cf, 'async function processContractRenewalChecks(', 12000);
      expect(scheduler.contains('status: "CONFIRMED"'), false);
      expect(scheduler.contains('renewalDecision: "EXTEND"'), false);
    });
  });

  // ══════════════════════════════════════════════════════════════
  // 10. 세 면이 같은 status 집합을 본다
  //
  //   고정근무자 행의 계약 연장 action 은 status 를 보지 않는다
  //   (workEndDate · renewalDecision · 해지승인 만 본다). 그래서
  //   CONTRACT_PENDING 인 만료 건에서도 연장 버튼이 열려 있다.
  //   홈과 조회가 CONFIRMED 만 세면 같은 사람이 한 화면에서는 결정
  //   대상이고 다른 화면에서는 없는 사람이 된다.
  // ══════════════════════════════════════════════════════════════
  group('10. status 집합 일치', () {
    test('10-a 판정식은 CONFIRMED 와 CONTRACT_PENDING 을 본다', () {
      final rd = _codeOf(_src('lib/utils/renewal_decision_state.dart'));
      expect(rd.contains('AppStatus.confirmed'), true);
      expect(rd.contains('AppStatus.contractPending'), true);
    });

    test('10-b 서버 Home 도 두 상태를 읽는다', () {
      final h = _after(cf, 'async function srvHomeExpiringContract(', 3200);
      expect(
        h.contains('.where("status", "in", ["CONFIRMED", "CONTRACT_PENDING"])'),
        true,
      );
      expect(h.contains('.where("status", "==", "CONFIRMED")'), false);
    });

    test('10-c 화면 조회도 두 상태를 읽는다', () {
      // [BLOCKER-RENEWAL-DECISION-QUEUE-POPULATION-PARITY]
      //   post-filter 였던 것이 서버 질의로 내려갔다 — 두 status 를
      //   각각 읽어 합친다. 집합은 그대로다.
      expect(appSvc, contains('kRenewalDecisionStatuses.map('));
      final rd = _codeOf(_src('lib/utils/renewal_decision_state.dart'));
      expect(rd, contains('AppStatus.contractPending,'));
    });

    test('10-d CONTRACT_PENDING 만료 건이 결정 대상이다', () {
      final app = _app(
        end: _d(2026, 9, 23),
        status: AppStatus.contractPending,
      );
      expect(renewalDecisionStateOf(app, _d(2026, 9, 24)),
          RenewalDecisionState.expired);
      expect(needsRenewalDecision(app, _d(2026, 9, 24)), true);
    });

    test('10-e 행 액션 게이트에는 status 가 없다 — 이 정렬의 근거', () {
      final gate = _after(fixedWorker, 'if (app.workEndDate != null &&', 220);
      expect(gate.contains('app.renewalDecision == null'), true);
      expect(gate.contains('!app.isTerminationApproved'), true);
      expect(gate.contains('AppStatus.confirmed'), false);
    });
  });
}
