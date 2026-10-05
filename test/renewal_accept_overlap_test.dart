// [R7-APPLICATION-LIFECYCLE.1B] 연장 수락이 겹침 계약을 거치지 않았다
//
// renewal 의 canonical 경계는 이렇다.
//
//   관리자 제안  → renewal_proposals/PENDING   ← 아직 약속이 아니다
//   근로자 수락  → NEW Application              ← 여기서 약속이 생긴다
//                  CONTRACT_PENDING
//                  desiredStartDate/workEndDate = proposal.effectiveStart/End
//
// 그런데 `callableAcceptRenewalProposal` 에는 겹침 계약 호출이 없었다.
// 다른 확정 writer 세 곳은 공용 엔진을 쓰는데 이 한 곳만 빠져 있었다.
// 그래서 수락 직후 다음이 조용히 성립할 수 있었다.
//
//   새 갱신 약속 + 그 기간에 겹치는 CONFIRMED/CONTRACT_PENDING  (약속 2개)
//   새 갱신 약속 + 그 기간에 겹치는 PENDING/INVITED 가 그대로 생존
//
// 이 파일이 고정하는 계약
//   RNW-ENGINE-*  공용 엔진 하나를 **모든** 확정 writer 가 공유한다
//   RNW-ORDER-*   수집은 트랜잭션 안, 첫 쓰기보다 앞 (Firestore 제약 + reject 원자성)
//   RNW-FD-*      판정 구간의 권위 = 제안 snapshot + effectiveStart/End
//   RNW-EXCL-*    원본 한 건만 제외 (갱신이 자기 자신에게 막히지 않게)
//   RNW-APPLY-*   loser 접기가 같은 트랜잭션
//   RNW-KEEP-*    범위 밖 무변경 (stale·lineage·좌석 카운터·정책 어휘)
//
// 행동(reject/auto-cancel/생존)은 DEV runtime DEV-A/B/C 가 잰다 —
// 이 파일은 그 행동을 가능하게 하는 **구조와 순서**를 고정한다.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _cf = 'functions/src/index.ts';

String _src(String p) {
  final f = File(p);
  if (!f.existsSync()) throw StateError('소스를 찾지 못했다: $p');
  return f.readAsStringSync();
}

/// 주석을 지운 코드만 — 주석 문구가 바뀌어도 깨지지 않게.
String _codeOf(String path) {
  final out = StringBuffer();
  for (final line in _src(path).split('\n')) {
    final t = line.trimLeft();
    if (t.startsWith('//') || t.startsWith('*') || t.startsWith('/*')) continue;
    out.writeln(line);
  }
  return out.toString();
}

/// 함수 하나의 본문 — 다음 top-level `export const` 까지.
String _fnBody(String code, String name) {
  // `expect` 는 테스트 바깥에서 쓸 수 없다 — 이 helper 는 main() 상단에서도
  //   불리므로 StateError 로 실패한다.
  final a = code.indexOf(name);
  if (a < 0) throw StateError('함수를 찾지 못했다: $name');
  final b = code.indexOf('\nexport const ', a + name.length);
  if (b <= a) throw StateError('함수 끝을 찾지 못했다: $name');
  return code.substring(a, b);
}

void main() {
  final code = _codeOf(_cf);
  final renewal =
      _fnBody(code, 'export const callableAcceptRenewalProposal = onCall(');

  group('RNW-ENGINE 공용 엔진 하나를 모든 확정 writer 가 쓴다', () {
    test('ENGINE-01 네 writer 전부 수집·적용을 호출한다', () {
      for (final w in [
        'export const callableConfirmApplication = onCall(',
        'export const callableApproveApplicationForReview = onCall(',
        'export const callableAcceptTOInvitation = onCall(',
        'export const callableAcceptConfirmedReassignment = onCall(',
        'export const callableAcceptRenewalProposal = onCall(',
      ]) {
        final body = _fnBody(code, w);
        expect(body.contains('srvCollectSeatCommitOverlap('), isTrue,
            reason: '$w 가 수집을 하지 않는다');
        expect(body.contains('srvApplySeatCommitOverlap('), isTrue,
            reason: '$w 가 적용을 하지 않는다');
      }
    });

    test('ENGINE-02 renewal 전용 겹침 정책을 만들지 않았다', () {
      for (final invented in [
        'srvRenewalOverlap',
        'srvCollectRenewalOverlap',
        '_isConflictRenewal',
        'RENEWAL_CONFLICT',
      ]) {
        expect(code.contains(invented), isFalse, reason: invented);
      }
      // renewal 본문에 자체 시간비교를 심지 않았다.
      expect(renewal.contains('_hasTimeOverlap('), isFalse);
      expect(renewal.contains('_isConflictLongTerm('), isFalse);
      expect(renewal.contains('_isConflictShortTerm('), isFalse);
    });

    test('ENGINE-03 V1 차단 상태 = CONFIRMED + CONTRACT_PENDING', () {
      final collect =
          _fnBody(code, 'async function srvCollectSeatCommitOverlap(');
      expect(
          collect.contains('.where("status", "in", ["CONFIRMED", "CONTRACT_PENDING"])'),
          isTrue,
          reason: '이미 성립한 약속은 차단 대상이다');
      expect(collect.contains('throw new HttpsError('), isTrue);
      expect(collect.contains('이미 확정된 근무가 있습니다'), isTrue);
    });

    test('ENGINE-04 V2 자동취소 상태 = PENDING + INVITED', () {
      final collect =
          _fnBody(code, 'async function srvCollectSeatCommitOverlap(');
      expect(collect.contains('.where("status", "in", ["PENDING", "INVITED"])'),
          isTrue);
      final apply = _fnBody(code, 'function srvApplySeatCommitOverlap(');
      expect(apply.contains('status: "AUTO_CANCELED"'), isTrue);
      expect(apply.contains('cancelReason: "SCHEDULE_CONFLICT"'), isTrue);
    });

    test('ENGINE-05 겹치지 않는 관계는 손대지 않는다', () {
      final collect =
          _fnBody(code, 'async function srvCollectSeatCommitOverlap(');
      expect(collect.contains('if (conflictsWith(tentative.data())) toCancel.push(tentative);'),
          isTrue,
          reason: '겹침 판정을 통과한 것만 취소 대상이다');
      expect(collect.contains('if (!conflictsWith(existing.data())) continue;'),
          isTrue);
    });

    test('ENGINE-06 충돌 조회는 사업장 경계를 넘는다', () {
      final collect =
          _fnBody(code, 'async function srvCollectSeatCommitOverlap(');
      expect(collect.contains('.where("uid", "==", applicantUid)'), isTrue);
      expect(collect.contains('businessId'), isFalse,
          reason: 'businessId 로 좁히면 타 사업장 약속을 놓친다');
    });

    test('ENGINE-07 조회를 트랜잭션 안에서 한다 — read-set 직렬화', () {
      final collect =
          _fnBody(code, 'async function srvCollectSeatCommitOverlap(');
      expect(RegExp(r'await tx\.get\(').allMatches(collect).length,
          greaterThanOrEqualTo(2),
          reason: '트랜잭션 밖 조회면 경쟁하는 확정과 직렬화되지 않는다');
    });

    test('ENGINE-08 좌석 카운터를 건드리지 않는다 — 중복 쓰기 금지', () {
      final apply = _fnBody(code, 'function srvApplySeatCommitOverlap(');
      expect(apply.contains('pendingCount'), isTrue);
      expect(apply.contains('confirmedCount'), isFalse,
          reason: 'loser 는 비좌석이다 — 확정 카운터를 줄이면 안 된다');
    });
  });

  group('RNW-ORDER 수집은 트랜잭션 안, 첫 쓰기보다 앞', () {
    test('ORDER-01 수집이 runTransaction 안에 있다', () {
      final txAt = renewal.indexOf('await db.runTransaction(async (tx) => {');
      final collectAt = renewal.indexOf('srvCollectSeatCommitOverlap(');
      expect(txAt, greaterThan(-1));
      expect(collectAt, greaterThan(txAt),
          reason: '트랜잭션 밖에서 판정하면 commit 과 원자적이지 않다');
    });

    test('ORDER-02 수집이 이 트랜잭션의 첫 쓰기보다 앞이다', () {
      final collectAt = renewal.indexOf('srvCollectSeatCommitOverlap(');
      // 이 트랜잭션의 첫 쓰기 = 서명 대기 계약서 voided 루프.
      final firstWriteAt = renewal.indexOf('status: "voided"');
      expect(firstWriteAt, greaterThan(-1));
      expect(collectAt, lessThan(firstWriteAt),
          reason: 'Firestore 는 모든 읽기가 모든 쓰기보다 앞이어야 한다');
    });

    test('ORDER-03 수집이 새 약속·원본 EXTEND·제안 ACCEPTED 보다 앞이다', () {
      final collectAt = renewal.indexOf('srvCollectSeatCommitOverlap(');
      for (final write in <(String, String)>[
        ('새 약속 생성', 'tx.set(newRef, newData)'),
        ('원본 EXTEND', 'renewalDecision: "EXTEND"'),
        ('제안 ACCEPTED', 'status: "ACCEPTED"'),
      ]) {
        final at = renewal.indexOf(write.$2);
        expect(at, greaterThan(-1), reason: write.$1);
        expect(collectAt, lessThan(at),
            reason: '${write.$1} 이 수집보다 앞이면 충돌 거부 시 부분 변경이 남는다');
      }
    });

    test('ORDER-04 적용이 같은 트랜잭션 안이고 제안 닫은 뒤다', () {
      final applyAt = renewal.indexOf('srvApplySeatCommitOverlap(');
      final proposalAt = renewal.indexOf('status: "ACCEPTED"');
      final txEndAt = renewal.indexOf('});', renewal.indexOf('tx.update(proposalRef'));
      expect(applyAt, greaterThan(proposalAt));
      expect(applyAt, greaterThan(-1));
      expect(txEndAt, greaterThan(-1));
      // 트랜잭션 콜백 밖(후속 알림)보다는 앞이어야 한다.
      final notifyAt = renewal.indexOf('srvNotifyRenewalResponse(');
      expect(notifyAt, greaterThan(-1));
      expect(applyAt, lessThan(notifyAt),
          reason: '알림보다 뒤면 트랜잭션 밖이다');
    });
  });

  group('RNW-FD 판정 구간의 권위', () {
    test('FD-01 약속 조건은 제안 snapshot 에서 온다 — 공고를 다시 읽지 않는다', () {
      expect(
          renewal.contains('...srvRenewalPromiseSnapshot(freshProposal),'),
          isTrue);
      final snap = _fnBody(code, 'function srvRenewalPromiseSnapshot(');
      for (final k in ['"startTime"', '"endTime"', '"workDays"', '"wdId"']) {
        expect(snap.contains(k), isTrue, reason: '$k 가 약속 snapshot 에 없다');
      }
    });

    test('FD-02 구간은 proposal.effectiveStart/effectiveEnd 다', () {
      expect(renewal.contains('(proposal.effectiveStart as Timestamp).toMillis()'),
          isTrue);
      expect(renewal.contains('const newEndDateMs = (proposal.effectiveEnd as Timestamp).toMillis();'),
          isTrue);
      // 수집에 넘기는 fd 가 그 구간을 쓴다.
      expect(renewal.contains('workDate: Timestamp.fromMillis(newStartDateMs),'),
          isTrue);
      expect(
          renewal.contains('desiredStartDate: Timestamp.fromMillis(newStartDateMs),'),
          isTrue);
      expect(renewal.contains('workEndDate: Timestamp.fromMillis(newEndDateMs),'),
          isTrue);
    });

    test('FD-03 저장되는 새 약속과 같은 구간으로 판정한다', () {
      // 새 문서도 같은 두 값을 쓴다 — 판정과 저장이 갈리면 의미가 없다.
      expect(renewal.contains('workDate: admin.firestore.Timestamp.fromMillis(newStartDateMs),'),
          isTrue);
      expect(renewal.contains('workEndDate: admin.firestore.Timestamp.fromMillis(newEndDateMs),'),
          isTrue);
      expect(renewal.contains('desiredStartDate: admin.firestore.Timestamp.fromMillis(newStartDateMs),'),
          isTrue);
    });

    test('FD-04 자기 자신은 새 문서 id 로 제외된다', () {
      expect(renewal.contains('applicationId: newApplicationId,'), isTrue);
    });
  });

  group('RNW-EXCL 원본 한 건만 제외', () {
    test('EXCL-01 excludeCommittedId = 원본 지원서다', () {
      expect(renewal.contains('excludeCommittedId: originalApplicationId,'),
          isTrue,
          reason: '원본에 종료일이 없으면 갱신이 자기 자신에게 막힌다');
    });

    test('EXCL-02 그 값은 서버가 fresh read 로 확인한 lineage 에서 온다', () {
      expect(renewal.contains('const originalApplicationId = proposal.oldApplicationId as string;'),
          isTrue);
      // 트랜잭션 안에서 제안·원본을 다시 읽고 검증한다.
      expect(renewal.contains('const freshProposalSnap = await tx.get(proposalRef);'),
          isTrue);
      expect(renewal.contains('const freshSnap = await tx.get(originalRef);'),
          isTrue);
      expect(renewal.contains('"제안과 계약이 일치하지 않습니다."'), isTrue);
      expect(renewal.contains('"확정 상태의 계약만 연장할 수 있습니다."'), isTrue);
    });

    test('EXCL-03 엔진은 한 건만 제외한다', () {
      final collect =
          _fnBody(code, 'async function srvCollectSeatCommitOverlap(');
      expect(
          collect.contains('if (excludeCommittedId && existing.id === excludeCommittedId) continue;'),
          isTrue);
      expect(collect.contains('excludeCommittedId?: string'), isTrue,
          reason: '목록이 아니라 한 건이다');
    });
  });

  group('RNW-APPLY loser 접기가 같은 트랜잭션', () {
    test('APPLY-01 적용 호출이 수집 결과를 그대로 쓴다', () {
      expect(
          renewal.contains('srvApplySeatCommitOverlap(tx, renewalOverlapPlan, {'),
          isTrue);
      expect(renewal.contains('nowTs: renewalNowTs,'), isTrue);
    });

    test('APPLY-02 arrayUnion 안에 serverTimestamp 를 넣지 않는다', () {
      expect(renewal.contains('const renewalNowTs = Timestamp.now();'), isTrue,
          reason: 'statusHistory 배열 원소에는 serverTimestamp 를 쓸 수 없다');
    });
  });

  group('RNW-KEEP 범위 밖 무변경', () {
    test('KEEP-01 stale·소급 가드가 그대로다', () {
      expect(renewal.contains('"계약 시작일은 30일 이전으로 소급할 수 없습니다."'),
          isTrue);
      expect(renewal.contains('"이미 처리된 연장 제안입니다."'), isTrue);
      expect(renewal.contains('"이미 연장 처리된 계약입니다."'), isTrue);
    });

    test('KEEP-02 퇴사·해지 승인 차단이 그대로다', () {
      expect(renewal.contains('"퇴사가 승인된 근무자의 계약은 연장할 수 없습니다."'),
          isTrue);
      expect(renewal.contains('"계약 해지가 승인된 근무자의 계약은 연장할 수 없습니다."'),
          isTrue);
    });

    test('KEEP-03 갱신은 좌석 카운터를 올리지 않는다', () {
      expect(renewal.contains('totalConfirmed'), isFalse,
          reason: '원본이 이미 확정 인원에 포함돼 있다 — 갱신은 기간 연장이다');
    });

    test('KEEP-04 EXTEND 는 수락 시점에만 적는다', () {
      expect(renewal.contains('renewalDecision: "EXTEND"'), isTrue);
      expect(renewal.contains('renewalDecision: null,'), isTrue,
          reason: '새 문서는 아직 갱신 결정이 없다');
    });

    test('KEEP-05 자동갱신을 부활시키지 않았다', () {
      expect(renewal.contains('AUTO_RENEW'), isFalse);
      expect(renewal.contains('autoRenewal'), isFalse);
    });

    test('KEEP-06 scheduler 보정으로 미루지 않았다', () {
      // 수집·적용이 같은 커밋 경계 안에 있다는 것이 이 Phase 의 요점이다.
      final collectAt = renewal.indexOf('srvCollectSeatCommitOverlap(');
      final applyAt = renewal.indexOf('srvApplySeatCommitOverlap(');
      final txAt = renewal.indexOf('await db.runTransaction(async (tx) => {');
      final notifyAt = renewal.indexOf('srvNotifyRenewalResponse(');
      expect(collectAt, greaterThan(txAt));
      expect(applyAt, greaterThan(txAt));
      expect(applyAt, lessThan(notifyAt));
      for (final sched in ['reconcileOverlap', 'repairConflict', 'onSchedule']) {
        expect(renewal.contains(sched), isFalse, reason: sched);
      }
    });

    test('KEEP-07 판정을 상수로 무력화하지 않았다', () {
      final start = renewal.indexOf('const renewalOverlapPlan');
      final end = renewal.indexOf('status: "voided"');
      expect(start, greaterThan(-1));
      expect(end, greaterThan(start));
      final region = renewal.substring(start, end);
      for (final cheat in ['false &&', '&& false', 'true ||', '|| true']) {
        expect(region.contains(cheat), isFalse, reason: cheat);
      }
    });
  });
}
