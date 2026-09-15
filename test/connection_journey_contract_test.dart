// [SYSTEM-INTEGRATION-R2] 연결 Journey — shortage recovery + invite contract
//
// 이번 Phase가 반드시 풀어야 했던 Product gap:
//
//   Home `3명 부족 ›`  →  DayApplicantsDialog  →  `지원자 없음`
//
// 부족을 보고 들어왔는데 부족도, 해결 수단도 없다.
//
// 원인 두 겹:
//   1) _buildGroups()가 지원서에서만 그룹을 만든다. `필요 3 · 지원 0 · 확정 0`인
//      모집 단위는 그룹 자체가 생기지 않는다.
//   2) 초대 CTA가 slotId를 지원서에서 유도한다. 지원자가 0명이면 null →
//      버튼이 사라진다. 충원이 가장 필요한 상태에서 충원 수단이 없다.
//   3) _buildBody()가 지원서 0건이면 목록 자체를 건너뛴다.
//
// DEV 실측 (2026-09-15 시점, 위워커):
//   FLEX 슬롯 날짜 8개 중 7개가 `지원자 0명 + 부족 5` 또는 `부족 3`.
//   즉 이 경로는 예외가 아니라 이 사업장의 정상 상태였다.
//
// 부족은 지원서가 아니라 slot capacity에 속한다. canonical join은
// slot.workDetails[].wdId ↔ slot.workDetailCounts[wdId] 이고,
// callableGetStaffingReadiness(Home의 `N명 부족`)가 쓰는 것과 같은 join이다.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:ALfit/models/ui/day_staffing_row.dart';

String _src(String p) {
  final f = File(p);
  if (!f.existsSync()) throw StateError('$p 를 찾지 못함');
  return f.readAsStringSync();
}

String _codeOf(String b) =>
    b.split('\n').where((l) => !l.trimLeft().startsWith('//')).join('\n');

String _after(String source, String signature, [int chars = 2000]) {
  final a = source.indexOf(signature);
  if (a == -1) throw StateError('$signature 를 찾지 못함');
  final end = a + chars;
  return source.substring(a, end > source.length ? source.length : end);
}

String _tsSliceOf(String source, String from, String to) {
  final a = source.indexOf(from);
  if (a == -1) throw StateError('$from 를 찾지 못함');
  final b = source.indexOf(to, a + from.length);
  if (b == -1) throw StateError('$to 를 찾지 못함');
  return source.substring(a, b);
}

const _cfPath = 'functions/src/index.ts';
const _dialogPath =
    'lib/screens/business_admin/dialogs/day_applicants_dialog.dart';
const _toSvcPath = 'lib/services/firestore/to_firestore.dart';

void main() {
  // ═════════════════════════════════════════════════════════════
  // 1. canonical shortage 식
  // ═════════════════════════════════════════════════════════════
  group('R2-01 shortage formula', () {
    DayStaffingRow row(int req, int conf, {int pend = 0}) => DayStaffingRow(
          toId: 't', toTitle: 'T', slotId: 's', wdId: 'w',
          workType: '사무업무', startTime: '13:00', endTime: '19:00',
          requiredCount: req, confirmedCount: conf, pendingCount: pend,
        );

    test('01-a shortage = max(required - confirmed, 0)', () {
      expect(row(3, 0).shortage, 3);
      expect(row(3, 1).shortage, 2);
      expect(row(3, 3).shortage, 0);
    });

    test('01-b 초과 확정은 음수가 아니라 0', () {
      // 초과 확정 wdId의 surplus가 다른 모집 단위의 부족을 상쇄하면 안 되므로
      // 각 단위의 부족은 0 밑으로 내려가지 않는다 (서버 식과 동일).
      expect(row(2, 5).shortage, 0);
    });

    test('01-c PENDING은 부족을 줄이지 않는다 — 지원 = 관심', () {
      // 지원은 약속이 아니다. 대기자가 몇 명이든 확보된 자리는 그대로다.
      expect(row(3, 0, pend: 10).shortage, 3);
    });

    test('01-d wdId/slotId 없는 행은 버린다 (조용한 0 금지)', () {
      expect(DayStaffingRow.tryFromMap({'toId': 't', 'slotId': 's'}), isNull);
      expect(DayStaffingRow.tryFromMap({'toId': 't', 'wdId': 'w'}), isNull);
      expect(DayStaffingRow.tryFromMap('nope'), isNull);
    });

    test('01-e 서버 payload 파싱', () {
      final r = DayStaffingRow.tryFromMap({
        'toId': 'kcwGL5K4SjWFhuPP54bF',
        'toTitle': '[R1-GOLDEN] 사무업무 테스트 공고',
        'slotId': 'lhmg4N00OlXdoomdD4mJ',
        'wdId': 'U7m41UR24YXrozf28Fy8',
        'workType': '사무업무',
        'startTime': '13:00', 'endTime': '19:00',
        'requiredCount': 3, 'confirmedCount': 1, 'pendingCount': 0,
      });
      expect(r, isNotNull);
      expect(r!.shortage, 2);
      expect(r.slotId, 'lhmg4N00OlXdoomdD4mJ');
    });
  });

  // ═════════════════════════════════════════════════════════════
  // 2. 서버 — 부족은 slot에서 읽는다
  // ═════════════════════════════════════════════════════════════
  group('R2-02 callableGetDayStaffingDetail', () {
    final cf = _src(_cfPath);
    final fn = _tsSliceOf(cf, 'export const callableGetDayStaffingDetail',
        '// ─── callableGetAvailableWorkers');

    test('02-a canonical join — slot.workDetails ↔ slot.workDetailCounts', () {
      expect(fn.contains('sd["workDetails"]'), isTrue);
      expect(fn.contains('sd["workDetailCounts"]'), isTrue);
      expect(fn.contains('wdc[wdId]?.confirmedCount'), isTrue);
    });

    test('02-b Home staffing readiness와 같은 공고 population', () {
      // 두 화면이 다른 공고 집합을 세면 `3명 부족`과 `인력 초대 (N명 부족)`가 갈린다.
      expect(fn.contains('"ACTIVE", "SCHEDULED", "FULL"'), isTrue);
      expect(fn.contains('d["isDeleted"] === true'), isTrue);
      expect(fn.contains('"flex"'), isTrue);
    });

    test('02-c wdId 계약이 깨지면 조용히 0으로 넘기지 않는다', () {
      expect(fn.contains('WORKDETAIL_CONTRACT_BROKEN'), isTrue);
      expect(fn.contains('failed-precondition'), isTrue);
    });

    test('02-d 충원 권한 = canManageTo (지원 검토·승인과 같은 capability)', () {
      expect(fn.contains('dsPerms?.canManageTo !== true'), isTrue);
      expect(fn.contains('assertBizAdmin'), isTrue);
    });

    test('02-e 일부 실패를 전체 현황처럼 내려보내지 않는다', () {
      // allSettled가 아니라 all — 한 TO가 실패하면 throw.
      expect(fn.contains('await Promise.all(flexTOs.map'), isTrue);
      expect(fn.contains('allSettled'), isFalse);
    });
  });

  // ═════════════════════════════════════════════════════════════
  // 3. 클라이언트 — 지원자 0명 부족이 보이고 행동할 수 있다
  // ═════════════════════════════════════════════════════════════
  group('R2-03 shortage recovery UX', () {
    final code = _codeOf(_src(_dialogPath));

    test('03-a 그룹을 slot canonical row로 보강한다', () {
      final body = _after(code, 'List<_GroupData> _buildGroups()', 3600);
      expect(body.contains('_dayStaffingRows'), isTrue);
      expect(body.contains('requiredCount: row.requiredCount'), isTrue);
      expect(body.contains('slotId: row.slotId'), isTrue);
    });

    test('03-b 지원서 그룹의 정원·slotId는 slot이 진실', () {
      final body = _after(code, 'List<_GroupData> _buildGroups()', 3600);
      expect(body.contains('existing.requiredCount = row.requiredCount'), isTrue);
      expect(body.contains('existing.slotId ??= row.slotId'), isTrue);
    });

    test('03-c 초대 CTA의 slotId를 지원서에서 유도하지 않는다', () {
      expect(code.contains('final slotId = g.slotId;'), isTrue);
      expect(
        code.contains('g.confirmedApps.first.slotId'),
        isFalse,
        reason: '지원자 0명이면 null이 되어 CTA가 사라지던 경로',
      );
    });

    test('03-d 지원서 0건이어도 모집 단위가 있으면 목록을 그린다', () {
      final body = _after(code, 'Widget _buildBody(BuildContext context)', 1800);
      expect(body.contains('final hasApps ='), isTrue);
      expect(body.contains('rows.isEmpty'), isTrue);
      // 지원서 유무만으로 빈 화면을 내보내던 조건이 남아 있으면 안 된다
      expect(
        body.contains('if (_pendingApps.isEmpty && _confirmedApps.isEmpty) {'),
        isFalse,
      );
    });

    test('03-e 조회 실패를 `충원할 것 없음`으로 바꾸지 않는다', () {
      final body = _after(code, 'Widget _buildBody(BuildContext context)', 1800);
      expect(body.contains('rows == null'), isTrue);
      expect(body.contains("'인력 현황을 불러오지 못했어요'"), isTrue);
      // 실패(null)와 성공-0건(empty)이 같은 화면이면 안 된다
      final nullAt = body.indexOf('rows == null');
      final emptyAt = body.indexOf('rows.isEmpty');
      expect(nullAt, lessThan(emptyAt));
    });

    test('03-f 초대 CTA는 canManageTo에서만 뜬다', () {
      expect(code.contains("_canForSelectedBiz((p) => p.canManageTo)"), isTrue);
    });

    test('03-g 기존 CTA를 재사용한다 — 새 버튼/화면을 만들지 않았다', () {
      expect(code.contains("'인력 초대 (\$shortage명 부족)'"), isTrue);
      expect(code.contains('InviteMethodSheet('), isTrue);
      expect(code.contains('AvailableWorkersBottomSheet('), isTrue);
    });

    test('03-h reader 계약 — 실패는 throw, 빈 목록은 사실', () {
      final svc = _codeOf(_src(_toSvcPath));
      final body = _after(svc, 'getDayStaffingDetail({', 1200);
      expect(body.contains('callableGetDayStaffingDetail'), isTrue);
      expect(body.contains('DayStaffingRow.tryFromMap'), isTrue);
      expect(body.contains('return [];'), isFalse,
          reason: '실패를 빈 목록으로 바꾸면 부족이 사라진다');
    });
  });

  // ═════════════════════════════════════════════════════════════
  // 4. 초대 — 식별자·중복·카운터
  // ═════════════════════════════════════════════════════════════
  group('R2-04 invite writer', () {
    final cf = _src(_cfPath);
    final invite = _tsSliceOf(cf, 'export const callableInviteWorker',
        '// ── callableAcceptTOInvitation');

    test('04-a 초대 Application은 지원과 같은 자연키를 쓴다', () {
      // auto-id였을 때는 중복 검사와 쓰기 사이에 두 번째 호출이 끼어들어
      // Application 2건 · pendingCount +2 · 알림 2건이 만들어졌다.
      expect(invite.contains('const inviteComplexId = slotId'), isTrue);
      expect(
        invite.contains(
            '`\${toId}_\${slotId}_\${inviteDiscriminator}_\${targetUid}`'),
        isTrue,
      );
      expect(
        invite.contains('db.collection("applications").doc(inviteComplexId)'),
        isTrue,
      );
    });

    test('04-b 생성이 트랜잭션 — 동시 호출 중 하나만 통과', () {
      expect(invite.contains('await db.runTransaction(async (invTx)'), isTrue);
      expect(invite.contains('const existing = await invTx.get(newAppRef)'), isTrue);
      expect(invite.contains('"already-exists"'), isTrue);
    });

    test('04-c 재초대는 비활성 상태에서만', () {
      expect(invite.contains('const REINVITABLE = ["REJECTED", "CANCELED", "AUTO_CANCELED"]'),
          isTrue);
    });

    test('04-d INVITED는 pending만 올린다 — 좌석 선점 아님', () {
      expect(invite.contains('pendingCount: admin.firestore.FieldValue.increment(1)'),
          isTrue);
      expect(
        invite.contains('confirmedCount: admin.firestore.FieldValue.increment(1)'),
        isFalse,
        reason: '초대만으로 자리가 찼다고 보면 부족이 거짓으로 줄어든다',
      );
    });

    test('04-e 알림도 결정적 id — 재초대는 새 알림, 재시도는 중복 없음', () {
      expect(invite.contains('`to_invite_\${newAppRef.id}_\${inviteTime.toMillis()}`'),
          isTrue);
      expect(invite.contains('.create({'), isTrue);
    });
  });

  // ═════════════════════════════════════════════════════════════
  // 5. 초대 철회 — canonical counter 반환
  // ═════════════════════════════════════════════════════════════
  group('R2-05 invite withdrawal', () {
    final cf = _src(_cfPath);
    final cancel = _tsSliceOf(cf, 'export const callableCancelTOInvitation',
        '// ─── callableCancelApprovedInterimSettlement');

    test('05-a workDetailCounts를 되돌린다', () {
      expect(
        cancel.contains('`workDetailCounts.\${cancelWdId}.pendingCount`'),
        isTrue,
      );
      expect(cancel.contains('increment(-1)'), isTrue);
    });

    test('05-b slot/TO 집계는 건드리지 않는다 (syncTOStats 소관)', () {
      // 둘 다 count()로 절대값이 다시 써지므로 여기서 또 줄이면 음수가 스친다.
      final tx = _after(cancel, 'await db.runTransaction(async (cTx)', 1400);
      expect(tx.contains('pendingCount: admin.firestore.FieldValue.increment(-1)'),
          isFalse);
      expect(tx.contains('totalPending: admin.firestore.FieldValue.increment(-1)'),
          isFalse);
    });

    test('05-c 그 사이 상태가 바뀌었으면 카운터를 건드리지 않는다', () {
      expect(
        cancel.contains(
            'if (freshStatus !== "INVITED" && freshStatus !== "EXPIRED") return;'),
        isTrue,
      );
    });
  });

  // ═════════════════════════════════════════════════════════════
  // 6. 후보 자격 — 기존 정책이 유지되는지 고정
  // ═════════════════════════════════════════════════════════════
  group('R2-06 candidate eligibility (기존 정책 고정)', () {
    final cf = _src(_cfPath);
    final cand = _tsSliceOf(cf, 'export const callableGetAvailableWorkers',
        'export const callableGetMyScheduleChanges');

    test('06-a 같은 모집 단위에 이미 관계가 있으면 후보에서 뺀다', () {
      expect(
        cand.contains(
            '.where("status", "in", ["PENDING", "INVITED", "CONFIRMED", "CONTRACT_PENDING", "REJECTED", "EXPIRED"])'),
        isTrue,
      );
    });

    test('06-b 초대 거절은 재초대 차단, 관리자 거절은 재초대 허용', () {
      // 거절 주체가 다르면 의미가 다르다 — invitedAt 존재 여부로 구분한다.
      expect(cand.contains('dInvitedAt === undefined || dInvitedAt === null'), isTrue);
    });

    test('06-c 겹치는 CONFIRMED는 후보 제외, 겹치는 PENDING은 후보 유지', () {
      // 지원 = 관심이므로 PENDING은 아직 약속이 아니다.
      expect(
        cand.contains('.where("status", "in", ["CONFIRMED", "CONTRACT_PENDING"])'),
        isTrue,
      );
      final conflict = _after(cand, 'confirmedOnDate', 2000);
      expect(conflict.contains('"PENDING"'), isFalse);
    });

    test('06-d 블랙리스트·비활성·제재 계정 제외', () {
      expect(cand.contains('uData.isBlacklisted === true'), isTrue);
      expect(cand.contains('!== "active"'), isTrue);
      expect(cand.contains('candidateRestrictedUntil'), isTrue);
    });
  });

  // ═════════════════════════════════════════════════════════════
  // 7. 수락 — capacity transaction
  // ═════════════════════════════════════════════════════════════
  group('R2-07 invite accept capacity', () {
    final cf = _src(_cfPath);
    final accept = _tsSliceOf(cf, 'export const callableAcceptTOInvitation',
        'export const callableDeclineTOInvitation');

    test('07-a 정원 재검증이 트랜잭션 안에 있다', () {
      expect(accept.contains('await db.runTransaction(async (tx)'), isTrue);
      final tx = _after(accept, 'await db.runTransaction(async (tx)', 6000);
      expect(tx.contains('getWorkDetailCount'), isTrue);
      expect(tx.contains('업무 정원이 초과되었습니다'), isTrue);
    });

    test('07-b 수락은 canonical wdId counter를 움직인다', () {
      // 이 자리는 syncTOStats가 재계산하지 않는다. 여기서 안 쓰면 부족이 안 준다.
      expect(
        accept.contains('`workDetailCounts.\${inviteAcceptWdId}.confirmedCount`'),
        isTrue,
      );
      expect(
        accept.contains('`workDetailCounts.\${inviteAcceptWdId}.pendingCount`'),
        isTrue,
      );
    });

    test('07-c 겹치는 확정 근무가 있으면 수락을 막는다', () {
      expect(accept.contains('이미 확정된 근무가 있어 수락할 수 없습니다'), isTrue);
    });
  });
}
