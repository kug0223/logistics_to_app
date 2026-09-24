// [RENEWAL-PROPOSAL-STALE-RECOVERY]
//
//   .4C.1A 에서 수락 writer 가 만료된 제안을 거절하게 했다. 그것만으로는
//   복구가 안 된다.
//
//       proposal.status = PENDING
//       effectiveStart  = 9/25
//       today           = 9/27
//
//   근로자는 수락할 수 없다. 그런데 관리자 화면은 계속 "연장 응답 대기"
//   라 말하고, 새 제안을 보내려 하면 "이미 응답을 기다리는 제안이 있다"
//   고 막는다. 아무도 아무것도 할 수 없는 상태가 된다.
//
//   그래서 이번에는 **복구 루프**를 닫는다.
//
//       저장은 PENDING 이어도 지금 쓸 수 없으면 STALE 이다.
//       → 근로자 할 일에서 사라진다
//       → 관리자 할 일로 돌아온다
//       → 새 제안을 보낼 수 있다
//       → 그 순간 옛 제안은 저장 수준에서도 STALE 로 은퇴한다
//
//   시간이 지나 못 쓰게 된 것은 STALE 이지 SUPERSEDED 가 아니다.
//   SUPERSEDED 는 **아직 유효한** 제안을 관리자가 조건을 바꿔 대체한
//   경우다. 둘을 섞으면 나중에 이유를 구분할 수 없다.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:ALfit/models/core/application_model.dart';
import 'package:ALfit/models/core/renewal_proposal_model.dart';
import 'package:ALfit/utils/renewal_decision_state.dart';

const _cfPath = 'functions/src/index.ts';
const _fixedWorkerPath =
    'lib/screens/business_admin/dialogs/fixed_worker_management_dialog.dart';
const _expiringPath = 'lib/screens/business_admin/expiring_contracts_screen.dart';
const _workerHomePath = 'lib/screens/user/user_home_screen.dart';
const _workerScreenPath = 'lib/screens/user/renewal_proposal_screen.dart';

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

/// KST 달력 [y-m-d] [h:min] 에 해당하는 instant.
DateTime _kst(int y, int m, int d, [int h = 0, int min = 0]) =>
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

ApplicationModel _oldApp({required DateTime end}) => ApplicationModel(
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
    );

/// 서버 `srvRenewalProposalEffectiveStatus` 의 거울.
///
/// 이 함수가 Dart 구현과 **다른 말을 하면** 테스트가 깨진다 — parity 는
/// 주장이 아니라 고정이어야 한다.
String _serverEffectiveStatus(RenewalProposalModel p, DateTime now) {
  if (p.status != RenewalProposalStatus.pending) return p.status;
  int dateNum(DateTime t) {
    final k = t.toUtc().add(const Duration(hours: 9));
    return k.year * 10000 + k.month * 100 + k.day;
  }

  final startNum = dateNum(p.effectiveStart);
  final todayNum = dateNum(now);
  if (startNum < todayNum) return RenewalProposalStatus.stale;
  if (startNum > todayNum) return RenewalProposalStatus.pending;

  const ko = ['일', '월', '화', '수', '목', '금', '토'];
  final kstNow = now.toUtc().add(const Duration(hours: 9));
  final wd = ko[kstNow.weekday % 7];
  final days = p.workDays;
  if (days != null && days.isNotEmpty && !days.contains(wd)) {
    return RenewalProposalStatus.pending;
  }
  final t = p.startTime;
  if (t == null) return RenewalProposalStatus.pending;
  final m = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(t);
  if (m == null) return RenewalProposalStatus.pending;
  final nowMinutes = kstNow.hour * 60 + kstNow.minute;
  final shiftMinutes = int.parse(m.group(1)!) * 60 + int.parse(m.group(2)!);
  return nowMinutes > shiftMinutes
      ? RenewalProposalStatus.stale
      : RenewalProposalStatus.pending;
}

void main() {
  final cf = _codeOf(_src(_cfPath));
  final fixedWorker = _codeOf(_src(_fixedWorkerPath));
  final expiring = _codeOf(_src(_expiringPath));
  final workerHome = _codeOf(_src(_workerHomePath));
  final workerScreen = _codeOf(_src(_workerScreenPath));

  final propose =
      _after(cf, 'export const callableCreateRenewalProposal', 7000);
  final accept =
      _after(cf, 'export const callableAcceptRenewalProposal', 9500);
  final decline =
      _after(cf, 'export const callableDeclineRenewalProposal', 2800);

  // ══════════════════════════════════════════════════════════════
  // 01. 유효 상태 판정 (§6·§39)
  // ══════════════════════════════════════════════════════════════
  group('01. effective state', () {
    test('01-a 시작일이 미래면 PENDING', () {
      final p = _proposal(start: _kst(2026, 10, 25));
      expect(p.effectiveStatusAt(_kst(2026, 10, 21, 12)),
          RenewalProposalStatus.pending);
    });

    test('01-b 오늘 시작 · 근무 시작 전이면 PENDING', () {
      final p = _proposal(start: _kst(2026, 10, 21));
      expect(p.effectiveStatusAt(_kst(2026, 10, 21, 8, 59)),
          RenewalProposalStatus.pending);
    });

    test('01-c 오늘 시작 · 근무 시작 후면 STALE', () {
      final p = _proposal(start: _kst(2026, 10, 21));
      expect(p.effectiveStatusAt(_kst(2026, 10, 21, 9, 1)),
          RenewalProposalStatus.stale);
    });

    test('01-d 어제 시작이면 STALE', () {
      final p = _proposal(start: _kst(2026, 10, 20));
      expect(p.effectiveStatusAt(_kst(2026, 10, 21, 0, 1)),
          RenewalProposalStatus.stale);
    });

    test('01-e 종결 상태는 시작일과 무관하게 그대로다', () {
      for (final s in [
        RenewalProposalStatus.accepted,
        RenewalProposalStatus.declined,
        RenewalProposalStatus.canceled,
        RenewalProposalStatus.superseded,
        RenewalProposalStatus.stale,
      ]) {
        final past = _proposal(start: _kst(2026, 1, 1), status: s);
        final future = _proposal(start: _kst(2027, 1, 1), status: s);
        expect(past.effectiveStatusAt(_kst(2026, 10, 21, 12)), s, reason: s);
        expect(future.effectiveStatusAt(_kst(2026, 10, 21, 12)), s, reason: s);
      }
    });

    test('01-f 오늘이 근무일이 아니면 시각과 무관하다', () {
      // 2026-10-21 은 수요일.
      final p = _proposal(start: _kst(2026, 10, 21), workDays: const ['일']);
      expect(p.effectiveStatusAt(_kst(2026, 10, 21, 23, 59)),
          RenewalProposalStatus.pending);
    });
  });

  // ══════════════════════════════════════════════════════════════
  // 02. 서버 ↔ 클라이언트 parity (§7)
  // ══════════════════════════════════════════════════════════════
  group('02. parity', () {
    test('02-a 같은 제안 · 같은 지금 → 같은 유효 상태', () {
      final starts = [
        _kst(2026, 10, 19), _kst(2026, 10, 20), _kst(2026, 10, 21),
        _kst(2026, 10, 22), _kst(2026, 11, 1),
      ];
      final nows = [
        _kst(2026, 10, 21, 0, 0), _kst(2026, 10, 21, 8, 59),
        _kst(2026, 10, 21, 9, 0), _kst(2026, 10, 21, 9, 1),
        _kst(2026, 10, 21, 23, 59),
      ];
      final statuses = [
        RenewalProposalStatus.pending,
        RenewalProposalStatus.accepted,
        RenewalProposalStatus.declined,
      ];
      var checked = 0;
      for (final s in starts) {
        for (final n in nows) {
          for (final st in statuses) {
            for (final wd in [
              const ['월', '화', '수', '목', '금', '토', '일'],
              const ['일'],
            ]) {
              final p = _proposal(start: s, status: st, workDays: wd);
              expect(p.effectiveStatusAt(n), _serverEffectiveStatus(p, n),
                  reason: 'start=$s now=$n status=$st workDays=$wd');
              checked++;
            }
          }
        }
      }
      expect(checked, 150);
    });

    test('02-b 서버 helper 가 같은 세 가지를 본다', () {
      final srv =
          _after(cf, 'function srvRenewalProposalEffectiveStatus(', 2400);
      expect(srv, contains('if (startNum < todayNum) return "STALE"'));
      expect(srv, contains('workDays.includes(srvKstWeekdayKo(now))'));
      expect(srv, contains('nowMinutes > shiftMinutes ? "STALE"'));
      // 종결 상태는 그대로 돌려준다.
      expect(srv,
          contains('if (persisted !== RENEWAL_PROPOSAL_PENDING) return persisted'));
    });

    test('02-c 어느 쪽도 device timezone 을 권위로 쓰지 않는다', () {
      final srv =
          _after(cf, 'function srvRenewalProposalEffectiveStatus(', 2400);
      expect(srv, contains('SRV_KST_MS'));
      final model = _codeOf(_src('lib/models/core/renewal_proposal_model.dart'));
      expect(model, contains("now.toUtc().add(const Duration(hours: 9))"));
      expect(model, contains('FormatHelper.toKstDate('));
    });
  });

  // ══════════════════════════════════════════════════════════════
  // 03. 수락 · 거절 — 만료된 제안에는 아무 행동도 없다 (§9·§24·§41)
  // ══════════════════════════════════════════════════════════════
  group('03. worker action', () {
    test('03-a 수락 writer 가 저장 상태만 보지 않는다', () {
      expect(accept,
          contains('srvRenewalProposalEffectiveStatus(proposal, new Date())'));
      expect(accept, contains('제안한 계약 시작일이 지났습니다'));
    });

    test('03-b 거절도 만료되면 막는다 — 아무도 거절하지 않았다', () {
      expect(decline,
          contains('srvRenewalProposalEffectiveStatus(p, new Date())'));
      expect(decline,
          contains('이 연장 제안은 계약 시작일이 지나 더 이상 응답할 수 없습니다.'));
    });

    test('03-c 근로자 화면이 만료 제안을 먼저 거른다', () {
      expect(workerScreen, contains('p.isActionableAt(now)'));
    });

    test('03-d 홈 Task 도 같은 기준으로 거른다', () {
      expect(workerHome, contains('p.isActionableAt(now)'));
    });

    test('03-e 만료 제안은 행동 대상이 아니다', () {
      final p = _proposal(start: _kst(2026, 10, 20));
      expect(p.isActionableAt(_kst(2026, 10, 21, 9)), false);
    });
  });

  // ══════════════════════════════════════════════════════════════
  // 04. 재제안 복구 (§10~§13·§40)
  // ══════════════════════════════════════════════════════════════
  group('04. manager recovery', () {
    test('04-a 만료된 제안이 새 제안을 영구히 막지 않는다', () {
      // 유효한 제안이 있을 때만 거절한다.
      expect(propose, contains('srvRenewalProposalEffectiveStatus(d.data(), now) ===\n'
          '            RENEWAL_PROPOSAL_PENDING'));
      expect(propose, contains('이미 응답을 기다리는 연장 제안이 있습니다.'));
    });

    test('04-b 만료된 제안을 저장 수준에서도 은퇴시킨다', () {
      expect(propose, contains('status: "STALE"'));
      expect(propose, contains('staledAt:'));
    });

    test('04-c STALE 과 SUPERSEDED 를 섞지 않는다', () {
      // SUPERSEDED 는 명시적 대체 경로에서만 쓴다.
      final supersede = _after(propose, 'if (supersedeProposalId) {', 800);
      expect(supersede, contains('status: "SUPERSEDED"'));
      expect(supersede, contains('supersededByProposalId: proposalId'));
      // 은퇴 경로에는 supersede 링크를 달지 않는다.
      final retire = _after(propose, 'tx.update(d.ref, {', 300);
      expect(retire.contains('supersededByProposalId'), false);
    });

    test('04-d 응답하지 않은 제안에 respondedAt 을 적지 않는다', () {
      final retire = _after(propose, 'tx.update(d.ref, {', 300);
      expect(retire.contains('respondedAt'), false);
      expect(retire.contains('respondedByUid'), false);
    });

    test('04-e 은퇴와 새 제안이 같은 트랜잭션이다', () {
      final txStart = propose.indexOf('await db.runTransaction');
      final retireAt = propose.indexOf('tx.update(d.ref, {');
      final createAt = propose.indexOf('tx.set(proposalRef, {');
      expect(txStart, greaterThan(-1));
      expect(retireAt, greaterThan(txStart));
      expect(createAt, greaterThan(retireAt));
    });

    test('04-f 포인터가 새 제안을 가리킨다', () {
      expect(propose, contains('renewalProposalId: proposalId'));
    });

    test('04-g 새 제안도 .4C 효력일 규칙을 다시 적용한다', () {
      expect(propose, contains('todayNum > oldEndNum && startNum < todayNum'));
      expect(propose,
          contains('이미 계약이 만료되어 오늘 이후 날짜부터 새 계약을 시작할 수 있습니다.'));
    });

    test('04-h 새 status 를 만들지 않았다', () {
      for (final banned in ['EXPIRED_PROPOSAL', 'TIMED_OUT', 'NEEDS_REPROPOSAL']) {
        expect(cf.contains(banned), false, reason: banned);
      }
    });
  });

  // ══════════════════════════════════════════════════════════════
  // 05. 관리자 화면 복귀 (§16~§20·§42)
  // ══════════════════════════════════════════════════════════════
  group('05. manager surface', () {
    final app = _oldApp(end: _kst(2026, 10, 20));
    final today = _kst(2026, 10, 21);

    test('05-a 유효한 제안이면 할 일이 아니다', () {
      expect(needsManagerRenewalAction(app, today, {'old1'}), false);
      expect(isWaitingWorkerRenewalResponse(app, today, {'old1'}), true);
    });

    test('05-b 만료된 제안이면 할 일로 돌아온다', () {
      // 만료 제안은 waiting 집합에 들어가지 않는다.
      expect(needsManagerRenewalAction(app, today, const {}), true);
      expect(isWaitingWorkerRenewalResponse(app, today, const {}), false);
    });

    test('05-c 서버 Home 이 derived 판정으로 waiting 을 만든다', () {
      final h = _after(cf, 'async function srvOldAppsWithActiveProposal(', 1600);
      expect(h, contains('srvRenewalProposalEffectiveStatus(data, now)'));
      expect(h, contains('!==\n          RENEWAL_PROPOSAL_PENDING) continue;'));
    });

    test('05-d Home 판정 시각은 지금이다 — KST 자정이 아니다', () {
      final home = _after(cf, 'async function srvHomeExpiringContract(', 4400);
      expect(home,
          contains('srvOldAppsWithActiveProposal(candidateIds, new Date())'));
    });

    test('05-e 계약 확인 필요 화면도 같은 기준이다', () {
      expect(expiring, contains('p.isActionableAt(today)'));
      expect(expiring, contains('needsManagerRenewalAction(app, todayOnly, waiting)'));
    });

    test('05-f 고정근무자도 같은 기준이다', () {
      expect(fixedWorker, contains('p.isActionableAt(DateTime.now())'));
      expect(fixedWorker, contains('needsManagerRenewalAction('));
    });

    test('05-g 세 화면이 각자 stale 식을 복제하지 않는다', () {
      // 판정은 모델 한 곳(effectiveStatusAt)에서만 한다.
      for (final s in [expiring, fixedWorker, workerHome]) {
        expect(s.contains('RenewalProposalStatus.stale'), false);
        expect(s.contains('shiftMinutes'), false);
      }
    });
  });

  // ══════════════════════════════════════════════════════════════
  // 06. 포인터는 진실이 아니다 (§14·§15·§45)
  // ══════════════════════════════════════════════════════════════
  group('06. pointer', () {
    test('06-a 어떤 reader 도 포인터만 보고 waiting 이라 하지 않는다', () {
      for (final s in [expiring, fixedWorker, workerHome, workerScreen]) {
        expect(s.contains('renewalProposalId'), false);
      }
      final home = _after(cf, 'async function srvHomeExpiringContract(', 4400);
      expect(home.contains('renewalProposalId'), false);
    });

    test('06-b 응답이 끝나면 포인터를 지운다', () {
      expect(accept,
          contains('renewalProposalId: admin.firestore.FieldValue.delete()'));
      expect(decline,
          contains('renewalProposalId: admin.firestore.FieldValue.delete()'));
    });
  });

  // ══════════════════════════════════════════════════════════════
  // 07. race (§28·§29·§44)
  // ══════════════════════════════════════════════════════════════
  group('07. race', () {
    test('07-a 늦은 수락과 재제안 중 하나만 이긴다', () {
      // 재제안은 트랜잭션에서 OLD 를 다시 읽고 이미 결정됐으면 멈춘다.
      expect(propose, contains('const fresh = await tx.get(oldRef)'));
      expect(propose, contains('if (f.renewalDecision != null) {'));
      // 수락도 트랜잭션에서 제안을 다시 읽는다.
      expect(accept, contains('const freshProposalSnap = await tx.get(proposalRef)'));
      expect(accept,
          contains('(freshProposal.status as string) !== RENEWAL_PROPOSAL_PENDING'));
    });

    test('07-b 수락된 제안 위에 새 제안이 생기지 않는다', () {
      // OLD.renewalDecision = EXTEND 이므로 재제안이 막힌다.
      expect(accept, contains('renewalDecision: "EXTEND"'));
      expect(propose,
          contains('이미 계약 갱신/종료 결정이 처리된 근무자입니다.'));
    });

    test('07-c 은퇴 대상 조회가 트랜잭션 read-set 에 들어간다', () {
      // tx.get(query) 여야 동시 수락이 재시도를 유발한다.
      expect(propose, contains('const activeSnap = await tx.get(\n'
          '        db.collection("renewal_proposals")'));
    });

    test('07-d 철회도 유효한 제안에만 적용된다', () {
      final cancel =
          _after(cf, 'export const callableCancelRenewalProposal', 2400);
      expect(cancel,
          contains('(p.status as string) !== RENEWAL_PROPOSAL_PENDING'));
    });
  });

  // ══════════════════════════════════════════════════════════════
  // 08. deep link (§22·§23·§46)
  // ══════════════════════════════════════════════════════════════
  group('08. deep link', () {
    test('08-a 만료 제안을 "없다"고 말하지 않는다', () {
      expect(workerScreen, contains('_focusExpired'));
      expect(workerScreen,
          contains('이 연장 제안은 계약 시작일이 지나 종료되었어요'));
    });

    test('08-b 만료 제안에는 수락·거절 버튼이 없다', () {
      // 목록에 들어가지 않으므로 카드 자체가 그려지지 않는다.
      final load = _after(workerScreen, 'Future<void> _load() async {', 1400);
      expect(load, contains('all.where((p) => p.isActionableAt(now))'));
    });

    test('08-c 알림이 아니라 제안 상태를 다시 읽는다', () {
      final load = _after(workerScreen, 'Future<void> _load() async {', 1400);
      expect(load, contains('getMyRenewalProposals()'));
      expect(load.contains('notification'), false);
    });
  });

  // ══════════════════════════════════════════════════════════════
  // 09. ERROR ≠ 없음 (§37·§38)
  // ══════════════════════════════════════════════════════════════
  group('09. error', () {
    test('09-a 근로자 화면은 실패를 제안 없음으로 바꾸지 않는다', () {
      expect(workerScreen, contains('_hasError = true'));
      expect(workerScreen, contains('연장 제안을 불러오지 못했어요'));
    });

    test('09-b 관리자 화면은 제안 조회 실패를 삼키지 않는다', () {
      // 실패하면 던진다 — catch 해서 빈 집합으로 만들지 않는다.
      final load =
          _after(fixedWorker, 'final waitingProposals =', 400);
      expect(load.contains('.catchError'), false);
      expect(load.contains('?? const {}'), false);
    });

    test('09-c 근로자 reader 가 빈 목록과 실패를 구분한다', () {
      final reader =
          _after(cf, 'export const callableGetMyRenewalProposals', 1200);
      expect(reader, contains('return {proposals};'));
      expect(reader.contains('catch'), false);
    });
  });

  // ══════════════════════════════════════════════════════════════
  // 10. 앞 Phase 회귀 (§47·§48·§49)
  // ══════════════════════════════════════════════════════════════
  group('10. 회귀', () {
    test('10-a 제안만으로 새 계약이 생기지 않는다', () {
      expect(propose.contains('status: "CONTRACT_PENDING"'), false);
      expect(propose.contains('renewalDecision: "EXTEND"'), false);
    });

    test('10-b 수락에서만 EXTEND 가 적힌다', () {
      expect(accept, contains('renewalDecision: "EXTEND"'));
      expect(decline.contains('renewalDecision'), false);
    });

    test('10-c 옛 우회로는 여전히 막혀 있다', () {
      final old =
          _after(cf, 'export const callableCreateContractRenewal', 700);
      expect(old, contains('failed-precondition'));
      expect(old.contains('runTransaction'), false);
    });

    test('10-d 과거 미결정 건에 나이 제한이 없다 — .4B.1 유지', () {
      final home = _after(cf, 'async function srvHomeExpiringContract(', 4400);
      expect(home.contains('.where("workEndDate", ">="'), false);
      expect(home, contains('.where("workEndDate", "<", in16DaysTs)'));
    });

    test('10-e Policy C 는 그대로다', () {
      expect(cf,
          contains('const CONFIRMED_STATUSES = ["CONFIRMED", "CONTRACT_PENDING"]'));
    });

    test('10-f 자동 연장은 여전히 없다', () {
      final scheduler =
          _after(cf, 'async function processContractRenewalChecks(', 12000);
      expect(scheduler.contains('status: "CONFIRMED"'), false);
      expect(scheduler.contains('renewalDecision: "EXTEND"'), false);
    });
  });
}
