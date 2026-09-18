// [CROSS-DOMAIN-R5.3E.2] 확정 근로자 업무 변경(A→B) V1
//
// 이 파일이 고정하는 것:
//
//   1. 제안은 Application이 아니다. 별도 entity에 담기고, B의 Application은
//      **수락 트랜잭션에서 처음** 만들어진다. 제안 단계에서 만들면 그 순간
//      목록·카운터·알림에 활성 관계로 섞이고, 관리자 화면에서 "제안했을 뿐인데
//      B로 확정된 것처럼" 보인다.
//
//   2. 제안 생성은 A를 건드리지 않는다. A의 status·좌석·일정을 쓰는 코드가
//      제안 경로에 있으면 안 된다.
//
//   3. 수락은 한 트랜잭션이다. A 자리 반납과 B 자리 확보가 갈리면 같은 사람이
//      두 자리를 갖거나 한 자리도 못 갖는다.
//
//   4. overlap 제외는 **서버가 읽은 proposal**에서만 나온다. 임의
//      excludeApplicationId를 받으면 "겹치는 확정 금지"가 호출자 선언 하나로
//      무력화된다.
//
//   5. 유일성은 결정적 lock 문서다. 쿼리로 "PROPOSED가 있나" 보는 것은
//      uniqueness가 아니다(R5.3C.2A에서 같은 결론).
//
//   6. V1이 다루지 않는 것은 서버가 거절한다 — 계약 있는 source,
//      근무가 시작된 source, 같은 wdId.
//
//   7. 근로자 CTA는 '거절'이 아니라 '기존 조건 유지'다. 거절은 관계가 끝난다는
//      인상을 주는데, 실제로는 원래 확정이 그대로 남는다.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _src(String p) {
  final f = File(p);
  if (!f.existsSync()) throw StateError('$p 를 찾지 못함');
  return f.readAsStringSync();
}

String _codeOf(String b) =>
    b.split('\n').where((l) => !l.trimLeft().startsWith('//')).join('\n');

String _flat(String b) => b.replaceAll(RegExp(r'\s+'), ' ');

String _callableBody(String raw, String name) {
  final start = raw.indexOf('export const $name = onCall(');
  if (start < 0) throw StateError('$name 을 찾지 못함');
  final end = raw.indexOf('\n);', start);
  if (end < 0) throw StateError('$name 본문 끝을 찾지 못함');
  return raw.substring(start, end);
}

/// 함수 본문. 파라미터 목록에 객체 타입(`args: {...}`)이 있어도 멈추지 않도록
/// **괄호를 먼저 닫고** 나서 중괄호를 센다 — 그러지 않으면 시그니처 안의
/// 첫 `{}`에서 끊겨 본문을 하나도 보지 못한다.
String _fnBody(String raw, String signature) {
  final start = raw.indexOf(signature);
  if (start < 0) throw StateError('$signature 를 찾지 못함');
  var i = raw.indexOf('(', start);
  if (i < 0) throw StateError('$signature 파라미터 목록을 찾지 못함');
  var paren = 0;
  for (; i < raw.length; i++) {
    if (raw[i] == '(') paren++;
    if (raw[i] == ')') {
      paren--;
      if (paren == 0) break;
    }
  }
  final bodyStart = raw.indexOf('{', i);
  if (bodyStart < 0) throw StateError('$signature 본문 시작을 찾지 못함');
  var depth = 0;
  for (var j = bodyStart; j < raw.length; j++) {
    final c = raw[j];
    if (c == '{') depth++;
    if (c == '}') {
      depth--;
      if (depth == 0) return raw.substring(start, j + 1);
    }
  }
  throw StateError('$signature 본문 끝을 찾지 못함');
}

/// 트랜잭션 콜백 본문만 — 괄호 짝을 세어 잘라낸다.
String _txBody(String body, {int skip = 0}) {
  var from = 0;
  for (var n = 0; n <= skip; n++) {
    final idx = body.indexOf('runTransaction(async', from);
    if (idx < 0) throw StateError('runTransaction #$skip 을 찾지 못함');
    if (n == skip) {
      var depth = 0;
      var seen = false;
      for (var i = idx; i < body.length; i++) {
        final c = body[i];
        if (c == '{') {
          depth++;
          seen = true;
        } else if (c == '}') {
          depth--;
          if (seen && depth == 0) return body.substring(idx, i + 1);
        }
      }
      throw StateError('runTransaction 본문 끝을 찾지 못함');
    }
    from = idx + 20;
  }
  throw StateError('unreachable');
}

const _cf = 'functions/src/index.ts';
const _appModel = 'lib/models/core/application_model.dart';
const _proposalModel = 'lib/models/core/confirmed_reassignment_proposal.dart';
const _sheet = 'lib/widgets/dialogs/confirmed_reassignment_sheet.dart';
const _offerSheet = 'lib/widgets/dialogs/alternative_work_offer_sheet.dart';
const _rules = 'firestore.rules';

void main() {
  final rawCf = _codeOf(_src(_cf));
  final cf = _flat(rawCf);
  final proposeRaw = _callableBody(rawCf, 'callableProposeConfirmedReassignment');
  final propose = _flat(proposeRaw);
  final acceptRaw = _callableBody(rawCf, 'callableAcceptConfirmedReassignment');
  final accept = _flat(acceptRaw);
  final acceptTx = _flat(_txBody(acceptRaw));
  final decline =
      _flat(_callableBody(rawCf, 'callableDeclineConfirmedReassignment'));
  final mgrCancel =
      _flat(_callableBody(rawCf, 'callableCancelConfirmedReassignment'));
  final overlapCollect =
      _flat(_fnBody(rawCf, 'async function srvCollectSeatCommitOverlap('));
  final sourceBlock =
      _flat(_fnBody(rawCf, 'function srvConfirmedReassignSourceBlock('));
  final closeFn = _flat(_fnBody(rawCf, 'function srvCloseCrProposal('));

  group('R5.3E.2 — 제안은 별도 entity다', () {
    test('전용 컬렉션과 상태가 정의돼 있다', () {
      expect(cf, contains('const CR_PROPOSAL_COL = "confirmedReassignmentProposals"'));
      expect(cf, contains('const CR_TYPE = "CONFIRMED_WORK_REASSIGNMENT"'));
      for (final s in [
        'CR_PROPOSED = "PROPOSED"',
        'CR_ACCEPTED = "ACCEPTED"',
        'CR_DECLINED = "DECLINED"',
        'CR_CANCELED_BY_MANAGER = "CANCELED_BY_MANAGER"',
        'CR_SUPERSEDED = "SUPERSEDED"',
        'CR_EXPIRED = "EXPIRED"',
      ]) {
        expect(cf, contains(s));
      }
    });

    test('제안 생성이 Application을 쓰지 않는다', () {
      // A를 읽기는 한다(eligibility). 쓰지는 않는다.
      expect(propose.contains('tx.update(crSrcRef'), isFalse);
      expect(propose.contains('crTx.update(crSrcRef'), isFalse);
      expect(propose.contains('crTx.set(acTargetRef'), isFalse);
      expect(propose.contains('applications").doc(crTargetAppId).set('), isFalse);
    });

    test('제안 생성이 좌석 카운터를 건드리지 않는다', () {
      expect(propose.contains('confirmedCount: admin.firestore.FieldValue.increment'),
          isFalse);
      expect(propose.contains('totalConfirmed'), isFalse);
      expect(propose.contains('pendingCount: admin.firestore.FieldValue.increment'),
          isFalse);
    });

    test('B Application은 수락 트랜잭션에서 만들어진다', () {
      expect(acceptTx, contains('tx.set(acTargetRef, bDoc)'));
    });
  });

  group('R5.3E.2 — source eligibility', () {
    test('CONFIRMED만 허용 (CONTRACT_PENDING 제외)', () {
      expect(sourceBlock, contains('if (st !== "CONFIRMED")'));
    });
    test('좌석이 이미 반납된 관계는 제외', () {
      expect(sourceBlock, contains('staffingReleasedAt'));
    });
    test('장기 근무는 V1 대상이 아니다', () {
      expect(sourceBlock, contains('long_term'));
    });
    test('canonical 근무 단위(wdId 포함)가 없으면 제외', () {
      expect(sourceBlock, contains('a["wdId"]'));
    });
    test('계약이 있으면 제안 자체를 막는다', () {
      expect(propose, contains('srvLiveContractRefsFor('));
      expect(propose, contains('이미 근로계약서가 발행된 근무입니다'));
    });
    test('근무가 시작됐으면 제안 자체를 막는다 (R5.3E.1 predicate 재사용)', () {
      expect(propose, contains('srvHasActualWorkStarted('));
    });
    test('같은 wdId로는 제안할 수 없다', () {
      expect(propose, contains('if (crSrcWdId === targetWdId)'));
    });
  });

  group('R5.3E.2 — target은 wdId로만 식별한다', () {
    test('workType 이름이 아니라 wdId로 찾는다', () {
      expect(propose, contains('crWdList.find((w) => w["wdId"] === targetWdId)'));
    });
    test('마감·정원을 제안 시점에 본다', () {
      expect(propose, contains('isManualClosed'));
      expect(propose, contains('getWorkDetailCount('));
    });
    test('수락 시점에 전부 다시 본다', () {
      expect(acceptTx, contains('wdList.find((w) => w["wdId"] === acWdId)'));
      expect(acceptTx, contains('getWorkDetailCount('));
      expect(acceptTx, contains('TARGET_FULL'));
      expect(acceptTx, contains('TARGET_SLOT_CLOSED'));
    });
  });

  group('R5.3E.2 — overlap 제외는 server-owned 한 건뿐', () {
    test('제외 축이 단수이고 이름이 명시적이다', () {
      expect(overlapCollect, contains('excludeCommittedId'));
      expect(
        overlapCollect,
        contains('if (excludeCommittedId && existing.id === excludeCommittedId) continue;'),
      );
    });

    test('수락 경로는 proposal이 가리키는 source만 제외한다', () {
      expect(acceptTx, contains('excludeCommittedId: acSourceId'));
    });

    test('클라이언트 payload에서 제외 대상을 받지 않는다', () {
      // request.data 구조분해에 exclude 계열 필드가 없어야 한다.
      final destructure = accept.substring(
          accept.indexOf('request.data as {'),
          accept.indexOf('};', accept.indexOf('request.data as {')));
      expect(destructure.toLowerCase().contains('exclude'), isFalse);
      expect(destructure.toLowerCase().contains('applicationid'), isFalse);
    });
  });

  group('R5.3E.2 — 수락은 한 트랜잭션', () {
    test('source 종료와 target 확정이 같은 트랜잭션에 있다', () {
      expect(acceptTx, contains('tx.update(acSrcRef'));
      expect(acceptTx, contains('tx.set(acTargetRef'));
    });

    test('source 전용 terminal 사유 — R5.3B와 구분된다', () {
      expect(acceptTx, contains('cancelReason: "CONFIRMED_REASSIGNMENT_ACCEPTED"'));
      expect(acceptTx.contains('cancelReason: "REASSIGNMENT_ACCEPTED"'), isFalse);
    });

    test('필수 audit — staffingReleasedAt · reassignedTo · proposalId', () {
      expect(acceptTx, contains('staffingReleasedAt: acNow'));
      expect(acceptTx, contains('reassignedToApplicationId: acTargetAppId'));
      expect(acceptTx, contains('reassignmentProposalId: proposalId'));
      expect(acceptTx, contains('reassignedAt: acNow'));
    });

    test('B의 약속은 proposal snapshot에서 온다 — 공고를 다시 읽지 않는다', () {
      expect(acceptTx, contains('acTargetPromise["wage"]'));
      expect(acceptTx, contains('acTargetPromise["startTime"]'));
      expect(acceptTx.contains('targetWd["wage"]'), isFalse);
    });

    test('근무 시작 판정은 R5.3E.1 predicate를 재사용한다', () {
      expect(acceptTx, contains('srvActualWorkReasonOf('));
      expect(acceptTx, contains('ACTUAL_WORK_STARTED'));
    });

    test('계약이 생겼으면 수락하지 않는다', () {
      expect(acceptTx, contains('CR_LIVE_CONTRACT_STATUSES.includes('));
      expect(acceptTx, contains('CONTRACT_ISSUED'));
    });

    test('per-wdId 좌석 카운터를 옮긴다', () {
      expect(acceptTx, contains(r'workDetailCounts.${acWdId}.confirmedCount'));
      expect(acceptTx, contains(r'workDetailCounts.${srcWdIdForCount}.confirmedCount'));
    });
  });

  group('R5.3E.2 — 유일성은 결정적 lock', () {
    test('lock 컬렉션이 sourceApplicationId를 문서 id로 쓴다', () {
      expect(cf, contains('const CR_LOCK_COL = "confirmedReassignmentLocks"'));
      expect(propose, contains('db.collection(CR_LOCK_COL).doc(sourceApplicationId)'));
    });

    test('lock을 트랜잭션에서 읽고 claim한다 (쿼리 아님)', () {
      expect(propose, contains('crTx.get(crLockRef)'));
      expect(propose, contains('crTx.set(crLockRef,'));
      expect(propose, contains('이미 진행 중인 업무 변경 제안이 있습니다'));
    });

    test('모든 종료 경로가 같은 헬퍼로 lock을 푼다', () {
      expect(closeFn, contains('activeProposalId: null'));
      for (final body in [acceptTx, decline, mgrCancel]) {
        expect(body, contains('srvCloseCrProposal('));
      }
    });
  });

  group('R5.3E.2 — 실패도 상태로 정리한다', () {
    test('수락 불가는 PROPOSED로 남기지 않는다', () {
      for (final reason in [
        'TARGET_FULL',
        'TARGET_SLOT_CLOSED',
        'TARGET_TO_CLOSED',
        'ACTUAL_WORK_STARTED',
        'CONTRACT_ISSUED',
        'SOURCE_NOT_ELIGIBLE',
      ]) {
        expect(acceptTx, contains(reason), reason: reason);
      }
      expect(acceptTx, contains('status: CR_SUPERSEDED'));
    });

    test('만료는 시간 경과가 아니라 명시적 판정이다', () {
      expect(acceptTx, contains('pExpires.toMillis() <= acNow.toMillis()'));
      expect(acceptTx, contains('status: CR_EXPIRED'));
    });

    test('근로자에게는 기존 근무가 유지된다고 말한다', () {
      expect(accept, contains('현재 변경할 자리가 없어 기존 근무가 유지됩니다.'));
    });
  });

  group('R5.3E.2 — 권한', () {
    test('제안은 canManageTo + canManageWorkers', () {
      expect(propose, contains('crPerms.canManageTo !== true'));
      expect(propose, contains('crPerms.canManageWorkers !== true'));
    });
    test('개별 급여 승계는 canManageWage 추가', () {
      expect(propose, contains('crIsMatch && crPerms.canManageWage !== true'));
    });
    test('계약 권한은 요구하지 않는다 (V1은 계약 없는 관계만)', () {
      expect(propose.contains('canManageContract'), isFalse);
    });
    test('수락은 본인만', () {
      expect(accept, contains('본인의 제안만 수락할 수 있습니다'));
    });
  });

  group('R5.3E.2 — 급여는 R5.3C 정책 그대로', () {
    test('allowlist 두 개뿐', () {
      expect(cf,
          contains('const CR_COMPENSATION_OPTIONS = ["TARGET_BASE", "MATCH_SOURCE_WAGE"]'));
    });
    test('cross wageType MATCH 차단', () {
      expect(propose, contains('crSrcWageType !== crWageType'));
      expect(propose, contains('급여 기준(시급/일급)이 달라'));
    });
    test('AUTO 통상시급은 숫자를 얼리지 않는다', () {
      expect(propose, contains('delete crOfferedSnapshot.baseHourlyWage'));
      expect(propose, contains('crOfferedSnapshot.baseHourlyWageMode = BASE_HOURLY_AUTO'));
    });
    test('최저임금은 제안 전에 본다', () {
      expect(propose, contains('srvValidateMinimumWagePromise('));
    });
    test('근로조건은 언제나 B에서 온다', () {
      expect(propose, contains('buildCompensationSnapshot(crTargetWD)'));
    });
    test('공고 B를 수정하지 않는다', () {
      expect(propose.contains('crSlotRef.update'), isFalse);
      expect(propose.contains('crToRef.update'), isFalse);
    });
  });

  group('R5.3E.2 — 알림', () {
    test('다섯 이벤트가 모두 있다', () {
      for (final t in [
        'confirmedReassignmentProposed',
        'confirmedReassignmentAccepted',
        'confirmedReassignmentDeclined',
        'confirmedReassignmentCanceled',
        'confirmedReassignmentSuperseded',
      ]) {
        expect(cf, contains(t), reason: t);
      }
    });

    test('결정적 id로 한 번만 쓴다', () {
      expect(cf, contains('.doc(docId).create('));
      expect(propose, contains(r'`cr_proposed_${crProposalId}`'));
    });

    test('payload에 금액·상태를 truth로 싣지 않는다', () {
      final notifFn = _flat(_fnBody(rawCf, 'async function srvWriteCrNotification('));
      expect(notifFn.contains('wage'), isFalse);
      // 각 호출의 data 블록에도 금액이 없어야 한다.
      expect(propose.contains('wage: crOfferedWage, action:'), isFalse);
    });
  });

  group('R5.3E.2 — 클라이언트', () {
    test('확정 재배치는 대기 재배치와 구분된 판정을 갖는다', () {
      final m = _flat(_codeOf(_src(_appModel)));
      expect(m, contains('bool get isConfirmedReassignedAway'));
      expect(m, contains("cancelReason == 'CONFIRMED_REASSIGNMENT_ACCEPTED'"));
      expect(m, contains("if (isConfirmedReassignedAway) return '다른 업무로 변경 확정';"));
    });

    test('모르는 제안 상태를 진행 중으로 읽지 않는다', () {
      final m = _flat(_codeOf(_src(_proposalModel)));
      expect(m, contains('return ReassignmentStatus.unknown;'));
      expect(m, contains('bool get isActionable => status == ReassignmentStatus.proposed;'));
    });

    test("근로자 CTA는 '거절'이 아니라 '기존 조건 유지'", () {
      final s = _flat(_codeOf(_src(_sheet)));
      expect(s, contains("Text('기존 조건 유지')"));
      expect(s, contains("Text('변경 수락'"));
      expect(s.contains("Text('거절')"), isFalse);
    });

    test('바뀌는 항목만 강조한다', () {
      final s = _flat(_codeOf(_src(_sheet)));
      expect(s, contains("if (proposal.changesWorkType) 'workType'"));
      expect(s, contains("if (proposal.changesTime) 'time'"));
      expect(s, contains("if (proposal.changesWage) 'wage'"));
    });

    test('제안 중에도 지금 근무가 그대로임을 말한다', () {
      final s = _flat(_codeOf(_src(_sheet)));
      expect(s, contains('선택하기 전까지 지금 확정된 근무는 그대로입니다.'));
    });

    test('관리자 시트는 확정/대기 문구가 한 곳에서 갈린다', () {
      final s = _flat(_codeOf(_src(_offerSheet)));
      expect(s, contains('bool sourceIsConfirmed = false'));
      expect(s, contains('근무 변경 제안'));
      expect(s, contains('제안을 보내도 지금 확정된 근무는 그대로입니다.'));
    });
  });

  group('R5.3E.2 — rules', () {
    test('proposal/lock은 CF 전용이다', () {
      final r = _flat(_src(_rules));
      expect(r, contains('match /confirmedReassignmentProposals/{proposalId} { allow read, write: if false;'));
      expect(r, contains('match /confirmedReassignmentLocks/{sourceApplicationId} { allow read, write: if false;'));
    });
  });
}
