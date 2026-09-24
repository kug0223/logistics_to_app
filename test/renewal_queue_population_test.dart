// [BLOCKER-RENEWAL-DECISION-QUEUE-POPULATION-PARITY]
//
// .4B 에서 판정식은 하나로 모았다. 그런데 **후보를 모으는 질의**가 서로
// 달랐다.
//
//     Home 서버 집계   : 과거 하한 없음
//     계약 확인 필요 화면 : workEndDate >= today - 180일
//
// 그래서 종료 후 181일이 지난 미결정 건은
//
//     Home      → 1건
//     목적지     → 0건
//
// 이 될 수 있었다. 판정식이 같아도 universe 가 다르면 parity 가 아니다.
//
// 시간이 오래 지난 것은 EXTEND 도 TERMINATE 도 아니다. 결정 queue 에서
// 빠지는 근거는 시간 경과가 아니라 domain state 다. 그래서 하한을 키우지
// 않고 **없앤다** — 180을 365로 바꾸는 것은 같은 결함을 미루는 것이다.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:ALfit/models/core/application_model.dart';
import 'package:ALfit/utils/format_helper.dart';
import 'package:ALfit/utils/renewal_decision_state.dart';

const _cfPath = 'functions/src/index.ts';
const _appSvcPath = 'lib/services/firestore/application_firestore.dart';
const _expiringPath = 'lib/screens/business_admin/expiring_contracts_screen.dart';

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

ApplicationModel _app({
  required DateTime end,
  String status = AppStatus.confirmed,
  String? renewalDecision,
  String? resignStatus,
  String? terminationStatus,
  String businessId = 'biz1',
  bool longTerm = true,
}) =>
    ApplicationModel(
      id: 'app-${end.toIso8601String()}-$status',
      businessId: businessId,
      businessName: '위워커',
      toTitle: '[테스트] 장기',
      workDate: longTerm ? end.subtract(const Duration(days: 30)) : end,
      workEndDate: end,
      workDays: longTerm ? const ['월', '화', '수', '목', '금'] : null,
      startTime: '09:00',
      endTime: '18:00',
      uid: 'worker1',
      selectedWorkType: '사무업무',
      wage: 12000,
      wageType: 'hourly',
      status: status,
      appliedAt: end.subtract(const Duration(days: 60)),
      confirmedAt: end.subtract(const Duration(days: 45)),
      renewalDecision: renewalDecision,
      resignStatus: resignStatus,
      terminationStatus: terminationStatus,
    );

/// 서버 `srvHomeExpiringContract` 의 후보 조건 — 하한 없음, 상한 today+16일.
bool _homeCandidate(ApplicationModel a, DateTime today) =>
    kRenewalDecisionStatuses.contains(a.status) &&
    a.workEndDate != null &&
    a.workEndDate!.isBefore(renewalCandidateEndBefore(today));

/// 목적지 조회(`getExpiringLongTermApplications`)의 후보 조건 — 같아야 한다.
bool _listCandidate(ApplicationModel a, DateTime today) =>
    kRenewalDecisionStatuses.contains(a.status) &&
    a.workEndDate != null &&
    a.workEndDate!.isBefore(renewalCandidateEndBefore(today));

/// 회귀 재현용 — 사라진 옛 하한.
bool _legacyListCandidate(ApplicationModel a, DateTime today) =>
    _listCandidate(a, today) &&
    !a.workEndDate!.isBefore(today.subtract(const Duration(days: 180)));

void main() {
  final cf = _codeOf(_src(_cfPath));
  final appSvc = _codeOf(_src(_appSvcPath));
  final expiring = _codeOf(_src(_expiringPath));

  // ══════════════════════════════════════════════════════════════
  // 01. 과거 하한이 없다 (§3·§6)
  // ══════════════════════════════════════════════════════════════
  group('01. 과거 하한 없음', () {
    ApplicationModel overdue(int days) =>
        _app(end: _today.subtract(Duration(days: days)));

    for (final days in [1, 15, 179, 180, 181, 365, 400, 1000]) {
      test('01 $days일 전 종료 · 미결정 → 두 reader 모두 후보', () {
        final a = overdue(days);
        expect(renewalDecisionStateOf(a, _today),
            RenewalDecisionState.expired, reason: '$days일');
        expect(_homeCandidate(a, _today), true, reason: 'Home $days일');
        expect(_listCandidate(a, _today), true, reason: '목적지 $days일');
      });
    }

    test('01-x 옛 180일 하한이 만들던 mismatch — 회귀 재현', () {
      // 이것이 BLOCKER 였다. 고친 뒤에는 나타날 수 없다.
      final a181 = overdue(181);
      expect(_homeCandidate(a181, _today), true);
      expect(_legacyListCandidate(a181, _today), false,
          reason: '옛 reader 는 이 건을 못 찾았다');
      expect(_listCandidate(a181, _today), true,
          reason: '지금은 찾는다');
    });

    test('01-y 179 / 181 경계가 더 이상 의미를 갖지 않는다', () {
      for (final d in [179, 180, 181]) {
        expect(_listCandidate(overdue(d), _today), true, reason: '$d일');
      }
    });
  });

  // ══════════════════════════════════════════════════════════════
  // 02. 미래 상한은 유지 (§7)
  // ══════════════════════════════════════════════════════════════
  group('02. 미래 상한', () {
    ApplicationModel ahead(int days) =>
        _app(end: _today.add(Duration(days: days)));

    test('02-a D-15 는 후보이자 결정 대상', () {
      final a = ahead(15);
      expect(_listCandidate(a, _today), true);
      expect(needsRenewalDecision(a, _today), true);
    });

    test('02-b D-16 은 아직 결정할 때가 아니다', () {
      expect(needsRenewalDecision(ahead(16), _today), false);
    });

    test('02-c 상한은 D-15 창에서 나온 실제 KST 자정 instant 다', () {
      // 서버는 `todayMs(KST 자정) + 16일` 을 쓴다. 같은 instant 여야 한다.
      final key = FormatHelper.toKstDate(_today);
      expect(
        renewalCandidateEndBefore(_today),
        key
            .add(const Duration(days: kRenewalUpcomingWindowDays + 1))
            .subtract(const Duration(hours: 9)),
      );
      // 비교 키(UTC 자정)를 그대로 쓰면 9시간이 어긋난다 — 그 실수 고정.
      expect(
        renewalCandidateEndBefore(_today),
        isNot(key.add(const Duration(days: kRenewalUpcomingWindowDays + 1))),
      );
    });
  });

  // ══════════════════════════════════════════════════════════════
  // 03. status universe (§8)
  // ══════════════════════════════════════════════════════════════
  group('03. status', () {
    test('03-a CONFIRMED · CONTRACT_PENDING 둘 다 포함', () {
      expect(kRenewalDecisionStatuses,
          [AppStatus.confirmed, AppStatus.contractPending]);
      for (final s in kRenewalDecisionStatuses) {
        final a = _app(end: _today.subtract(const Duration(days: 400)),
            status: s);
        expect(_homeCandidate(a, _today), true, reason: s);
        expect(_listCandidate(a, _today), true, reason: s);
        expect(needsRenewalDecision(a, _today), true, reason: s);
      }
    });

    test('03-b 그 밖의 status 는 넓히지 않았다', () {
      for (final s in [AppStatus.pending, AppStatus.canceled,
        AppStatus.rejected, AppStatus.autoCanceled]) {
        final a = _app(end: _today.subtract(const Duration(days: 400)),
            status: s);
        expect(_homeCandidate(a, _today), false, reason: s);
        expect(needsRenewalDecision(a, _today), false, reason: s);
      }
    });
  });

  // ══════════════════════════════════════════════════════════════
  // 04. 해결된 관계는 되살아나지 않는다 (§19)
  // ══════════════════════════════════════════════════════════════
  group('04. resolved 제외', () {
    ApplicationModel old({
      String? renewalDecision,
      String? resignStatus,
      String? terminationStatus,
    }) =>
        _app(
          end: _today.subtract(const Duration(days: 400)),
          renewalDecision: renewalDecision,
          resignStatus: resignStatus,
          terminationStatus: terminationStatus,
        );

    test('04-a EXTEND 는 queue 에 없다', () {
      expect(needsRenewalDecision(old(renewalDecision: 'EXTEND'), _today),
          false);
    });

    test('04-b TERMINATE 는 queue 에 없다', () {
      expect(needsRenewalDecision(old(renewalDecision: 'TERMINATE'), _today),
          false);
    });

    test('04-c 퇴사 승인 · 자동승인 제외', () {
      expect(needsRenewalDecision(old(resignStatus: AppStatus.approved),
          _today), false);
      expect(needsRenewalDecision(old(resignStatus: AppStatus.autoApproved),
          _today), false);
    });

    test('04-d 해지 승인 · 자동승인 제외', () {
      expect(needsRenewalDecision(
          old(terminationStatus: AppStatus.approved), _today), false);
      expect(needsRenewalDecision(
          old(terminationStatus: AppStatus.autoApproved), _today), false);
    });

    test('04-e 하한 제거가 history 전체를 살려내지 않는다', () {
      // 오래된 건이라도 결정이 끝났으면 queue 에 없다.
      final resolvedOld = [
        old(renewalDecision: 'EXTEND'),
        old(renewalDecision: 'TERMINATE'),
        old(resignStatus: AppStatus.approved),
        old(terminationStatus: AppStatus.autoApproved),
      ];
      expect(resolvedOld.where((a) => needsRenewalDecision(a, _today)).length,
          0);
    });
  });

  // ══════════════════════════════════════════════════════════════
  // 05. Home ↔ 목적지 집합 일치 (§9·§20)
  // ══════════════════════════════════════════════════════════════
  group('05. population parity', () {
    final universe = <ApplicationModel>[
      _app(end: _today.subtract(const Duration(days: 1))),
      _app(end: _today.subtract(const Duration(days: 179))),
      _app(end: _today.subtract(const Duration(days: 181)),
          status: AppStatus.contractPending),
      _app(end: _today.subtract(const Duration(days: 400))),
      _app(end: _today.subtract(const Duration(days: 300)),
          renewalDecision: 'EXTEND'),
      _app(end: _today.add(const Duration(days: 10))),
      _app(end: _today.add(const Duration(days: 30))),
      _app(end: _today.subtract(const Duration(days: 5)),
          status: AppStatus.canceled),
      _app(end: _today.subtract(const Duration(days: 5)), longTerm: false),
    ];

    Set<String> decisionIds(bool Function(ApplicationModel, DateTime) cand) =>
        universe
            .where((a) => cand(a, _today))
            .where((a) => needsRenewalDecision(a, _today))
            .map((a) => a.id)
            .toSet();

    test('05-a 같은 universe 에서 같은 applicationId 집합', () {
      expect(decisionIds(_homeCandidate), decisionIds(_listCandidate));
    });

    test('05-b 집합이 비어 있지 않다 — 빈 집합끼리 같은 것은 증명이 아니다', () {
      // 만료 4건(1·179·181·400일) + 곧 종료 1건(D+10).
      expect(decisionIds(_homeCandidate).length, 5);
    });

    test('05-c 옛 하한에서는 집합이 어긋났다 — 회귀 재현', () {
      expect(decisionIds(_homeCandidate),
          isNot(decisionIds(_legacyListCandidate)));
      expect(
        decisionIds(_homeCandidate)
            .difference(decisionIds(_legacyListCandidate))
            .length,
        2, // 181일 · 400일
      );
    });

    test('05-d Home count == 목적지 결정 대상 수', () {
      expect(decisionIds(_homeCandidate).length,
          decisionIds(_listCandidate).length);
    });
  });

  // ══════════════════════════════════════════════════════════════
  // 06. 소스 — cutoff 로 되돌아가지 않는다 (§3·§37)
  // ══════════════════════════════════════════════════════════════
  group('06. 소스 고정', () {
    test('06-a 조회에 과거 하한이 없다', () {
      // 다른 기능의 조회에는 workEndDateGteMs 가 정당하게 쓰인다.
      // 결정 queue 조회 안에서만 사라졌는지 본다.
      final seg = _after(appSvc, 'getExpiringLongTermApplications(', 1600);
      expect(seg.contains('Duration lookBack'), false);
      expect(seg.contains('fromDate.subtract('), false);
      expect(seg.contains('workEndDateGteMs'), false);
    });

    test('06-b 상한만 쓴다 — 공용 helper 에서 나온다', () {
      final seg = _after(appSvc, 'getExpiringLongTermApplications(', 1600);
      expect(seg, contains('renewalCandidateEndBefore(fromDate)'));
      expect(seg, contains("'workEndDateLtMs': endBeforeMs"));
    });

    test('06-c status 는 서버에서 좁힌다 — 두 질의의 union', () {
      final seg = _after(appSvc, 'getExpiringLongTermApplications(', 1600);
      expect(seg, contains('kRenewalDecisionStatuses.map('));
      expect(seg, contains("'status': status"));
    });

    test('06-d 서버 Home 집계에도 과거 하한이 없다', () {
      final h = _after(cf, 'async function srvHomeExpiringContract(', 3400);
      expect(h.contains('.where("workEndDate", ">="'), false);
      expect(h, contains('.where("workEndDate", "<", in16DaysTs)'));
    });

    test('06-e 더 큰 임의 cutoff 로 바꾸지 않았다', () {
      for (final banned in ['days: 180', 'days: 365', 'days: 730']) {
        expect(appSvc.contains(banned), false, reason: banned);
      }
    });

    test('06-f 화면은 여전히 공용 판정식으로 거른다', () {
      expect(expiring, contains('needsManagerRenewalAction(app, todayOnly, waiting)'));
    });

    test('06-g 새 persisted field 를 만들지 않았다', () {
      for (final banned in ['isExpired', 'needsRenewal:', 'renewalOverdue:']) {
        expect(cf.contains(banned), false, reason: banned);
      }
    });
  });

  // ══════════════════════════════════════════════════════════════
  // 07. business 격리 (§22)
  // ══════════════════════════════════════════════════════════════
  group('07. business 격리', () {
    test('07-a 조회는 businessId 로 먼저 좁힌다', () {
      final seg = _after(appSvc, 'getExpiringLongTermApplications(', 1600);
      expect(seg, contains("'businessId': businessId"));
    });

    test('07-b 서버 집계도 사업장 단위다', () {
      final h = _after(cf, 'async function srvHomeExpiringContract(', 3400);
      expect(h, contains('.where("businessId", "==", bizId)'));
    });

    test('07-c 판정식은 사업장을 보지 않는다 — 좁히는 일은 질의가 한다', () {
      final a = _app(
          end: _today.subtract(const Duration(days: 400)), businessId: 'bizB');
      expect(needsRenewalDecision(a, _today), true);
    });
  });

  // ══════════════════════════════════════════════════════════════
  // 08. ERROR ≠ ZERO (§24)
  // ══════════════════════════════════════════════════════════════
  group('08. 실패를 0건으로 바꾸지 않는다', () {
    test('08-a 조회 실패는 rethrow 한다', () {
      final seg = _after(appSvc, 'getExpiringLongTermApplications(', 2000);
      expect(seg, contains('rethrow;'));
      expect(seg.contains('return [];'), false);
    });

    test('08-b 두 질의 중 하나만 성공한 것을 전부라고 말하지 않는다', () {
      final seg = _after(appSvc, 'getExpiringLongTermApplications(', 1600);
      expect(seg, contains('Future.wait('));
    });

    test('08-c 페이지를 다 쓰고도 남으면 던진다 — 조용히 자르지 않는다', () {
      expect(appSvc, contains('페이지를 읽고도 남아 있다'));
    });

    test('08-d 화면은 실패를 빈 목록과 구분한다', () {
      expect(expiring, contains('_hasError = true'));
    });
  });
}
