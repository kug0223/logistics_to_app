// [RENEWAL-PROPOSAL-COMMITMENT]
//
//   관리자가 연장 버튼을 누르면 곧바로 새 계약이 CONTRACT_PENDING 으로
//   만들어졌다. 그런데 ALfit 에서 그 상태는 좌석이 있고, 출근할 수 있고,
//   결근 대상이 되고, 계약 발송 의무가 생기는 상태다.
//
//       관리자 혼자 누른 버튼이 근로자에게 새 근무 의무를 만들었다.
//
//   근로자는 새 기간에 아직 아무 말도 하지 않았는데.
//
//   그래서 writer 경계를 옮겼다.
//
//       Manager Proposal  → Worker Accept → CONTRACT_PENDING
//                         → Contract      → Signature → CONFIRMED
//
//   Worker renewal acceptance      = commitment event
//   Worker electronic signature    = documentation / completion event
//
//   Policy C(CONTRACT_PENDING 에서도 출근 가능)는 바꾸지 않았다. 문제는
//   그 상태를 너무 일찍 만든 것이지 Policy C 자체가 아니다.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:ALfit/models/core/application_model.dart';
import 'package:ALfit/models/core/renewal_proposal_model.dart';
import 'package:ALfit/utils/renewal_decision_state.dart';

const _cfPath = 'functions/src/index.ts';
const _rulesPath = 'firestore.rules';
const _fixedWorkerPath =
    'lib/screens/business_admin/dialogs/fixed_worker_management_dialog.dart';
const _expiringPath = 'lib/screens/business_admin/expiring_contracts_screen.dart';
const _workerHomePath = 'lib/screens/user/user_home_screen.dart';
const _workerScreenPath = 'lib/screens/user/renewal_proposal_screen.dart';
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

DateTime _k(int y, int m, int d, [int h = 0, int min = 0]) =>
    DateTime.utc(y, m, d, h, min).subtract(const Duration(hours: 9));

RenewalProposalModel _proposal({
  required DateTime start,
  String status = RenewalProposalStatus.pending,
  List<String>? workDays,
  String? startTime = '09:00',
}) =>
    RenewalProposalModel(
      id: 'p1',
      businessId: 'biz1',
      businessName: '위워커',
      workerUid: 'w1',
      oldApplicationId: 'old1',
      status: status,
      effectiveStart: start,
      effectiveEnd: start.add(const Duration(days: 90)),
      workDays: workDays ?? const ['월', '화', '수', '목', '금', '토', '일'],
      startTime: startTime,
      endTime: '18:00',
      wage: 12000,
      wageType: 'hourly',
      selectedWorkType: '사무업무',
    );

ApplicationModel _app({required DateTime end, String? renewalDecision}) =>
    ApplicationModel(
      id: 'old1',
      businessId: 'biz1',
      businessName: '위워커',
      toTitle: '[테스트] 장기',
      workDate: end.subtract(const Duration(days: 90)),
      workEndDate: end,
      workDays: const ['월', '화', '수', '목', '금'],
      startTime: '09:00',
      endTime: '18:00',
      uid: 'w1',
      selectedWorkType: '사무업무',
      wage: 12000,
      wageType: 'hourly',
      status: AppStatus.confirmed,
      appliedAt: end.subtract(const Duration(days: 120)),
      confirmedAt: end.subtract(const Duration(days: 100)),
      renewalDecision: renewalDecision,
    );

void main() {
  final cf = _codeOf(_src(_cfPath));
  final rules = _src(_rulesPath);
  final fixedWorker = _codeOf(_src(_fixedWorkerPath));
  final expiring = _codeOf(_src(_expiringPath));
  final workerHome = _codeOf(_src(_workerHomePath));
  final workerScreen = _codeOf(_src(_workerScreenPath));
  final appSvc = _codeOf(_src(_appSvcPath));

  final propose =
      _after(cf, 'export const callableCreateRenewalProposal', 6200);
  final accept =
      _after(cf, 'export const callableAcceptRenewalProposal', 9500);
  final decline =
      _after(cf, 'export const callableDeclineRenewalProposal', 2200);
  final cancel =
      _after(cf, 'export const callableCancelRenewalProposal', 2200);

  // ══════════════════════════════════════════════════════════════
  // 01. 관리자 혼자서는 약속을 만들 수 없다 (§98)
  // ══════════════════════════════════════════════════════════════
  group('01. 관리자 단독 commitment 차단', () {
    test('01-a 제안 writer 는 새 지원서를 만들지 않는다', () {
      expect(propose.contains('status: "CONTRACT_PENDING"'), false);
      expect(propose.contains('renewalDecision: "EXTEND"'), false);
      expect(propose.contains('renewedToApplicationId'), false);
    });

    test('01-b 제안 writer 는 좌석·근태·계약서를 만들지 않는다', () {
      for (final banned in [
        'collection("attendance")', 'employment_contracts',
        'totalConfirmed', 'NO_SHOW',
      ]) {
        expect(propose.contains(banned), false, reason: banned);
      }
    });

    test('01-c 예전 우회로는 막혔다 — 구버전 앱에 이유를 말한다', () {
      final old =
          _after(cf, 'export const callableCreateContractRenewal', 700);
      expect(old, contains('failed-precondition'));
      expect(old, contains('계약 연장은 근무자의 수락이 필요합니다'));
      expect(old.contains('runTransaction'), false);
    });

    test('01-d 클라이언트에 예전 writer 호출이 남아 있지 않다', () {
      expect(appSvc.contains('callableCreateContractRenewal'), false);
      expect(fixedWorker.contains('createRenewedApplication'), false);
    });

    test('01-e 개별 · 일괄 연장 모두 제안 writer 를 쓴다', () {
      expect(fixedWorker, contains('createRenewalProposal('));
      expect('createRenewalProposal('.allMatches(fixedWorker).length,
          greaterThanOrEqualTo(2));
    });
  });

  // ══════════════════════════════════════════════════════════════
  // 02. renewalDecision 의미 보존 (§8·§77)
  // ══════════════════════════════════════════════════════════════
  group('02. renewalDecision', () {
    test('02-a EXTEND 는 수락 writer 에서만 적힌다', () {
      expect(accept, contains('renewalDecision: "EXTEND"'));
      expect(propose.contains('renewalDecision: "EXTEND"'), false);
      expect(decline.contains('renewalDecision'), false);
      expect(cancel.contains('renewalDecision'), false);
    });

    test('02-b 제안 단계에서 원본은 미결정 그대로다', () {
      // 제안 writer 가 OLD 에 쓰는 것은 찾아가기용 참조뿐이다.
      expect(propose, contains('renewalProposalId: proposalId'));
      expect(propose.contains('renewalDecision:'), false);
    });

    test('02-c 거절은 TERMINATE 로 치환되지 않는다', () {
      expect(decline.contains('TERMINATE'), false);
      expect(decline.contains('resignStatus'), false);
      expect(decline.contains('terminationStatus'), false);
    });

    test('02-d 거절 뒤 관리자는 다시 결정할 수 있다', () {
      // renewalDecision 이 여전히 null 이므로 결정 queue 로 돌아온다.
      final app = _app(end: _k(2026, 10, 20));
      expect(needsRenewalDecision(app, _k(2026, 10, 10)), true);
      expect(needsManagerRenewalAction(app, _k(2026, 10, 10), const {}), true);
    });
  });

  // ══════════════════════════════════════════════════════════════
  // 03. 수락이 commitment event (§22·§76)
  // ══════════════════════════════════════════════════════════════
  group('03. 수락 writer', () {
    test('03-a 근로자 본인만 수락한다', () {
      expect(accept, contains('(proposal.workerUid as string) !== callerUid'));
      expect(accept, contains('(originalData.uid as string) !== callerUid'));
    });

    test('03-b 관리자 권한 검증이 이 경로에 남아 있지 않다', () {
      expect(accept.contains('memberPermsForRenewal.canManageContract'), false);
    });

    test('03-c 한 트랜잭션에서 제안·원본·신규를 함께 쓴다', () {
      expect(accept, contains('tx.update(proposalRef, {'));
      expect(accept, contains('status: "ACCEPTED"'));
      expect(accept, contains('newApplicationId,'));
      expect(accept, contains('tx.set(newRef, newData)'));
      expect(accept, contains('renewedToApplicationId: newApplicationId'));
    });

    test('03-d 트랜잭션 안에서 제안 상태를 다시 읽는다 — race', () {
      expect(accept, contains('const freshProposalSnap = await tx.get(proposalRef)'));
      expect(accept,
          contains('(freshProposal.status as string) !== RENEWAL_PROPOSAL_PENDING'));
    });

    test('03-e 제안과 계약이 같은 관계인지 본다', () {
      expect(accept,
          contains("(freshProposal.oldApplicationId as string) !== originalApplicationId"));
      expect(accept, contains('(proposal.businessId as string) !== businessId'));
    });

    test('03-f 수락된 약속은 제안 snapshot 이다 — 지금 공고가 아니다', () {
      expect(accept, contains('...srvRenewalPromiseSnapshot(freshProposal)'));
      final snap = _after(cf, 'function srvRenewalPromiseSnapshot(', 900);
      for (final f in ['wage', 'workDays', 'startTime', 'endTime',
        'taxDeductionType', 'selectedWorkType']) {
        expect(snap, contains('"$f"'), reason: f);
      }
    });

    test('03-g NEW 는 CONTRACT_PENDING 이다 — dual-sign 흐름 유지', () {
      expect(accept, contains('status: "CONTRACT_PENDING"'));
    });
  });

  // ══════════════════════════════════════════════════════════════
  // 04. 거절 / 철회 / 대체 (§26·§36·§37)
  // ══════════════════════════════════════════════════════════════
  group('04. 거절·철회·대체', () {
    test('04-a 거절은 상태와 응답 기록만 남긴다', () {
      expect(decline, contains('status: "DECLINED"'));
      expect(decline.contains('collection("applications").doc()'), false);
      expect(decline.contains('CONTRACT_PENDING'), false);
    });

    test('04-b 거절은 신뢰도를 건드리지 않는다', () {
      for (final banned in [
        'restrictedUntil', 'noShowCount', 'trustScore', 'recentNoShowCount',
      ]) {
        expect(decline.contains(banned), false, reason: banned);
      }
    });

    test('04-c 철회는 이미 수락된 제안을 되돌리지 않는다', () {
      expect(cancel,
          contains("(p.status as string) !== RENEWAL_PROPOSAL_PENDING"));
      expect(cancel, contains('status: "CANCELED"'));
    });

    test('04-d 대체는 기존 제안을 명시적으로 닫는다', () {
      expect(propose, contains('status: "SUPERSEDED"'));
      expect(propose, contains('supersededByProposalId: proposalId'));
    });

    test('04-f 수락 단계에서 막힐 조건은 제안 단계에서 먼저 말한다', () {
      // 제안은 통과하는데 수락은 늘 실패하는 막다른 길을 만들지 않는다.
      expect(propose, contains('(f.status as string) !== "CONFIRMED"'));
      expect(propose, contains('현재 계약서 서명이 끝난 뒤에 연장을 제안할 수 있습니다.'));
      expect(accept, contains('확정 상태의 계약만 연장할 수 있습니다.'));
    });

    test('04-e 응답 대기 제안은 한 관계에 하나뿐이다', () {
      expect(propose, contains('.where("oldApplicationId", "==", oldApplicationId)'));
      expect(propose, contains('already-exists'));
      // client 질의만 믿지 않는다 — 트랜잭션 안에서 본다.
      expect(propose, contains('await tx.get(\n        db.collection("renewal_proposals")'));
    });
  });

  // ══════════════════════════════════════════════════════════════
  // 05. derived STALE — 과거 의무를 만들지 않는다 (§31~§35·§80)
  // ══════════════════════════════════════════════════════════════
  group('05. stale', () {
    test('05-a 어제 시작 제안은 수락할 수 없다', () {
      final p = _proposal(start: _k(2026, 10, 20));
      expect(p.effectiveStatusAt(_k(2026, 10, 21, 9)),
          RenewalProposalStatus.stale);
      expect(p.isActionableAt(_k(2026, 10, 21, 9)), false);
    });

    test('05-b 내일 시작 제안은 오늘 수락할 수 있다', () {
      final p = _proposal(start: _k(2026, 10, 22));
      expect(p.isActionableAt(_k(2026, 10, 21, 23)), true);
    });

    test('05-c 오늘 시작 · 근무 시작 전이면 수락할 수 있다', () {
      final p = _proposal(start: _k(2026, 10, 21));
      expect(p.isActionableAt(_k(2026, 10, 21, 8, 59)), true);
    });

    test('05-d 오늘 시작 · 근무 시작이 지났으면 STALE', () {
      // 오늘 09:00 근무를 15:00 에 뒤늦게 의무로 만들지 않는다.
      final p = _proposal(start: _k(2026, 10, 21));
      expect(p.effectiveStatusAt(_k(2026, 10, 21, 15)),
          RenewalProposalStatus.stale);
    });

    test('05-e 오늘이 근무일이 아니면 시각과 무관하다', () {
      final p = _proposal(start: _k(2026, 10, 21), workDays: const ['일']);
      expect(p.isActionableAt(_k(2026, 10, 21, 23)), true);
    });

    test('05-f 서버도 같은 판정을 한다', () {
      final srv =
          _after(cf, 'function srvRenewalProposalEffectiveStatus(', 2200);
      expect(srv, contains('if (startNum < todayNum) return "STALE"'));
      expect(srv, contains('srvKstWeekdayKo(now)'));
      expect(srv, contains('nowMinutes > shiftMinutes ? "STALE"'));
    });

    test('05-g 수락 writer 가 stale 을 막는다 — scheduler 를 기다리지 않는다', () {
      expect(accept,
          contains('srvRenewalProposalEffectiveStatus(proposal, new Date())'));
      expect(accept, contains('제안한 계약 시작일이 지났습니다'));
    });

    test('05-h 시작일을 오늘로 자동 보정하지 않는다', () {
      // 그것도 관리자가 보낸 제안을 시스템이 고쳐 쓰는 일이다.
      expect(accept.contains('effectiveStart: admin.firestore'), false);
      expect(accept, contains('(proposal.effectiveStart as Timestamp).toMillis()'));
    });
  });

  // ══════════════════════════════════════════════════════════════
  // 06. 효력일 — .4C invariant 유지 (§13·§49·§85)
  // ══════════════════════════════════════════════════════════════
  group('06. effective date', () {
    test('06-a 제안 단계에서 원본 종료일 다음 날 규칙이 산다', () {
      expect(propose,
          contains('갱신 계약 시작일은 원본 계약 종료일 다음 날부터여야 합니다.'));
    });

    test('06-b 만료 뒤 과거 시작 제안은 거절된다', () {
      expect(propose, contains('todayNum > oldEndNum && startNum < todayNum'));
      expect(propose,
          contains('이미 계약이 만료되어 오늘 이후 날짜부터 새 계약을 시작할 수 있습니다.'));
    });

    test('06-c 수락 경로에도 같은 검증이 남아 있다 — 이중 방어', () {
      expect(accept, contains('todayNum > originalEndNum && newStartNum < todayNum'));
      expect(accept, contains('if (newStartNum <= originalEndNum)'));
    });

    test('06-d Application/Contract/eligibility 가 같은 E 를 말한다', () {
      expect(accept,
          contains('desiredStartDate: admin.firestore.Timestamp.fromMillis(newStartDateMs)'));
      expect(accept,
          contains('workDate: admin.firestore.Timestamp.fromMillis(newStartDateMs)'));
    });
  });

  // ══════════════════════════════════════════════════════════════
  // 07. gap 에 의무를 만들지 않는다 (§50·§79)
  // ══════════════════════════════════════════════════════════════
  group('07. 공백 = NO WORK', () {
    test('07-a 수락 writer 가 과거 근태·임금을 만들지 않는다', () {
      for (final banned in ['collection("attendance")', 'NO_SHOW']) {
        expect(accept.contains(banned), false, reason: banned);
      }
    });

    test('07-b 새 계약의 운영 상태는 비어 있다', () {
      expect(accept, contains('leaveDates: []'));
      expect(accept, contains('extraWorkDates: []'));
      expect(accept, contains('wageStatus: "pending"'));
    });

    test('07-c E 이전은 eligibility 가 막는다', () {
      final r = _after(cf, 'function srvLongTermEligibleOnDay(', 1400);
      expect(r,
          contains('if (dayNum < startNum) return {eligible: false, reason: "BEFORE_START"}'));
    });

    test('07-d Policy C 는 그대로다 — CONTRACT_PENDING 은 여전히 출근 가능', () {
      expect(cf,
          contains('const CONFIRMED_STATUSES = ["CONFIRMED", "CONTRACT_PENDING"]'));
    });
  });

  // ══════════════════════════════════════════════════════════════
  // 08. 좌석 — 제안은 자리를 잡지 않는다 (§51·§52·§78)
  // ══════════════════════════════════════════════════════════════
  group('08. seat', () {
    test('08-a 좌석 집합에 제안이 없다 — 별도 컬렉션이라 셀 수가 없다', () {
      final occupancy = _after(cf, 'const OCCUPANCY_STATUSES = ', 120);
      expect(occupancy, contains('["CONFIRMED", "CONTRACT_PENDING"]'));
      expect(occupancy.contains('renewal_proposals'), false);
    });

    test('08-b 제안 writer 가 공고 카운터를 건드리지 않는다', () {
      for (final banned in ['totalPending', 'pendingCount', 'totalConfirmed']) {
        expect(propose.contains(banned), false, reason: banned);
      }
    });

    test('08-c INVITED 를 재사용하지 않았다', () {
      expect(propose.contains('"INVITED"'), false);
      expect(propose, contains('collection("renewal_proposals")'));
    });
  });

  // ══════════════════════════════════════════════════════════════
  // 09. 관리자 화면 — 응답 대기 ≠ 할 일 (§29·§70·§71·§83)
  // ══════════════════════════════════════════════════════════════
  group('09. manager surface', () {
    test('09-a 서버 Home 이 응답 대기를 제외한다', () {
      final home = _after(cf, 'async function srvHomeExpiringContract(', 4200);
      expect(home, contains('srvOldAppsWithActiveProposal(candidateIds, new Date())'));
      expect(home, contains('if (waitingWorker.has(doc.id)) continue;'));
    });

    test('09-b 응답 대기 판정도 derived status 를 쓴다', () {
      final h = _after(cf, 'async function srvOldAppsWithActiveProposal(', 1400);
      expect(h, contains('srvRenewalProposalEffectiveStatus(data, now)'));
    });

    test('09-c 계약 확인 필요 화면도 같은 helper 를 쓴다', () {
      expect(expiring, contains('needsManagerRenewalAction(app, todayOnly, waiting)'));
      expect(expiring, contains('getPendingRenewalProposals(bizId)'));
    });

    test('09-d 고정근무자도 같은 helper 를 쓴다', () {
      expect(fixedWorker, contains('needsManagerRenewalAction('));
      expect(fixedWorker, contains('_waitingProposalOldAppIds'));
    });

    test('09-e 응답 대기는 정보로만 말한다', () {
      expect(fixedWorker, contains('_buildWaitingProposalBanner'));
      expect(fixedWorker, contains('연장 응답 대기'));
    });

    test('09-f 공용 helper 가 두 상태를 가른다', () {
      final app = _app(end: _k(2026, 10, 20));
      final today = _k(2026, 10, 10);
      expect(needsManagerRenewalAction(app, today, {'old1'}), false);
      expect(isWaitingWorkerRenewalResponse(app, today, {'old1'}), true);
      expect(needsManagerRenewalAction(app, today, const {}), true);
      expect(isWaitingWorkerRenewalResponse(app, today, const {}), false);
    });

    test('09-g 버튼 이름이 하는 일과 같다', () {
      expect(fixedWorker, contains("title: '계약 연장 제안'"));
      expect(fixedWorker, contains("confirmText: '연장 제안 보내기'"));
    });
  });

  // ══════════════════════════════════════════════════════════════
  // 10. 근로자 화면 — 실제 할 일 (§19·§30·§72·§73)
  // ══════════════════════════════════════════════════════════════
  group('10. worker surface', () {
    test('10-a 홈 Task 의 출처는 제안 문서다 — 알림이 아니다', () {
      expect(workerHome, contains('getMyRenewalProposals()'));
      expect(workerHome, contains('_buildRenewalProposalCard'));
      final card =
          _after(workerHome, 'Widget _buildRenewalProposalCard(', 700);
      expect(card.contains('notification'), false);
    });

    test('10-b 조회 실패를 "제안 없음"으로 바꾸지 않는다', () {
      expect(workerScreen, contains('_hasError = true'));
      expect(workerScreen, contains('연장 제안을 불러오지 못했어요'));
    });

    test('10-c 수락 전에 조건을 모두 보여준다', () {
      for (final label in ['기간', '업무', '근무요일', '근무시간', '임금']) {
        expect(workerScreen, contains("'$label'"), reason: label);
      }
    });

    test('10-d 수락 · 거절 둘 다 있다', () {
      expect(workerScreen, contains('acceptRenewalProposal('));
      expect(workerScreen, contains('declineRenewalProposal('));
      expect(workerScreen, contains('현재 계약은 기존 종료일까지 유지됩니다.'));
    });

    test('10-e 화면도 stale 을 먼저 거른다', () {
      expect(workerScreen, contains('p.isActionableAt(now)'));
    });

    test('10-f 처리 실패 뒤 현재 상태를 다시 읽는다', () {
      final acceptFn = _after(workerScreen, 'Future<void> _accept(', 1200);
      expect(acceptFn, contains('await _load();'));
    });
  });

  // ══════════════════════════════════════════════════════════════
  // 11. 권한 · 사업장 격리 · rules (§62~§65)
  // ══════════════════════════════════════════════════════════════
  group('11. 권한', () {
    test('11-a 제안·철회는 canManageContract', () {
      expect(propose, contains('perms.canManageContract'));
      expect(cancel, contains('perms.canManageContract'));
    });

    test('11-b 수락·거절은 제안 소유 근로자만', () {
      expect(accept, contains('본인의 제안만 응답할 수 있습니다.'));
      expect(decline, contains('(p.workerUid as string) !== callerUid'));
    });

    test('11-c 관리자 reader 는 사업장 소속을 확인한다', () {
      final reader =
          _after(cf, 'export const callableGetRenewalProposalsByBiz', 900);
      // [R5-D2] 소속 확인 위에 계약 자격이 하나 더 필요하다 — 제안을 만드는
      //   쪽(callableCreateRenewalProposal)이 canManageContract 를 요구한다.
      expect(reader, contains('srvAssertContractAuthority(callerUid, businessId)'));
      expect(reader, contains('.where("businessId", "==", businessId)'));
    });

    test('11-d 근로자 reader 는 본인 것만 읽는다', () {
      final reader =
          _after(cf, 'export const callableGetMyRenewalProposals', 900);
      expect(reader, contains('.where("workerUid", "==", uid)'));
    });

    test('11-e rules — 클라이언트 직접 쓰기 금지', () {
      final block = _after(rules, 'match /renewal_proposals/{proposalId}', 900);
      expect(block, contains('allow create, update, delete: if false;'));
      expect(block, contains('allow list: if false;'));
      expect(block, contains('isOwner(resource.data.workerUid)'));
      expect(block, contains('isAdminOf(resource.data.businessId)'));
    });
  });

  // ══════════════════════════════════════════════════════════════
  // 12. 알림 (§57~§60·§84)
  // ══════════════════════════════════════════════════════════════
  group('12. notification', () {
    test('12-a 제안 알림은 정확히 그 제안을 가리킨다', () {
      final n = _after(cf, 'async function srvNotifyRenewalProposal(', 1600);
      expect(n, contains('proposalId: a.proposalId'));
      expect(n, contains('screen: "renewalProposal"'));
      // 같은 제안에 두 번 보내지 않는다 — 고정 id + create().
      expect(n, contains(r'renewal_proposal_${a.proposalId}'));
      expect(n, contains('.create('));
    });

    test('12-b 수락 · 거절은 관리자에게 정보로 간다', () {
      final n = _after(cf, 'async function srvNotifyRenewalResponse(', 2200);
      expect(n, contains('renewalAccepted'));
      expect(n, contains('renewalDeclined'));
      expect(n, contains('category: "business"'));
    });

    test('12-c 알림 실패가 제안·응답을 되돌리지 않는다', () {
      expect(propose, contains('알림 실패 (제안은 생성됨)'));
      expect(decline, contains('알림 실패 (거절은 처리됨)'));
    });

    test('12-d 세 타입이 서버·클라이언트 양쪽에 등록됐다', () {
      for (final t in ['renewalProposal', 'renewalAccepted', 'renewalDeclined']) {
        expect(cf, contains('"$t"'), reason: 'cf $t');
      }
      final nm = _codeOf(_src('lib/models/core/notification_model.dart'));
      for (final t in ['renewalProposal', 'renewalAccepted', 'renewalDeclined']) {
        expect(nm, contains("case '$t': return NotificationType.$t;"),
            reason: 'dart $t');
      }
    });

    test('12-e deep link 가 제안 화면으로 간다', () {
      final scr = _codeOf(_src('lib/screens/common/notification_screen.dart'));
      expect(scr, contains('RenewalProposalScreen('));
      expect(scr, contains("notification.data?['proposalId']"));
    });
  });

  // ══════════════════════════════════════════════════════════════
  // 13. 금지 목록 (§97)
  // ══════════════════════════════════════════════════════════════
  group('13. 하지 않은 것', () {
    test('13-a Application 에 새 전역 status 를 만들지 않았다', () {
      expect(cf.contains('RENEWAL_PROPOSED'), false);
      final valid = _after(cf, 'const VALID_APP_STATUSES = ', 300);
      expect(valid.contains('RENEWAL'), false);
    });

    test('13-b 자동 연장을 되살리지 않았다', () {
      final scheduler =
          _after(cf, 'async function processContractRenewalChecks(', 12000);
      expect(scheduler.contains('status: "CONFIRMED"'), false);
      expect(scheduler.contains('renewalDecision: "EXTEND"'), false);
    });

    test('13-c 법적 단정 문구를 쓰지 않는다', () {
      for (final banned in ['재입사', '계속근로가 단절', '근로관계가 완전히 종료']) {
        expect(cf.contains(banned), false, reason: banned);
        expect(workerScreen.contains(banned), false, reason: banned);
        expect(fixedWorker.contains(banned), false, reason: banned);
      }
    });

    test('13-d 계약 lineage 를 법적 결론으로 저장하지 않는다', () {
      for (final banned in [
        'continuousService', 'isRehire', 'employmentContinuity',
      ]) {
        expect(cf.contains(banned), false, reason: banned);
      }
    });

    test('13-e 제안 참조는 편의일 뿐 진실이 아니다', () {
      // 수락·거절·철회 모두 참조를 지우고, 진실은 제안 문서에 남는다.
      expect(accept, contains('renewalProposalId: admin.firestore.FieldValue.delete()'));
      expect(decline, contains('renewalProposalId: admin.firestore.FieldValue.delete()'));
      expect(cancel, contains('renewalProposalId: admin.firestore.FieldValue.delete()'));
    });
  });
}
