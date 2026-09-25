// [.5-PATCH] TERMINATION EFFECTIVE-DATE / WORKER TASK / EXIT MUTEX
//
//   해지 승인은 **결정**이지 효력이 아니다.
//
//   예전에는 미래 효력일 D 를 기록하면서 같은 트랜잭션에서 status 를
//   CANCELED 로 바꾸고 정원을 줄이고 계약서를 void 하고 계정 세션까지
//   끊었다. 그래서 canonical worker-day resolver 는 "D 까지 근무"라고
//   말하는데 좌석·달력·고정근무자 명단은 "승인 즉시 끝"이라고 말했다.
//   같은 관계에 두 개의 진실이 있었고, 그 사이 기간의 근태·급여·연락을
//   아무도 처리할 수 없었다.
//
//       APPROVED ≠ EFFECTIVE
//       actualResignDate = D = 마지막으로 일할 수 있는 날 (inclusive)
//       D+1 부터 종료 효력
//
//   그리고 응답해야 할 사람은 근로자인데 홈에 그 일이 없었다. 알림이
//   유일한 경로였고, 알림을 지우면 D+3 에 조용히 자동 승인됐다.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:ALfit/models/core/application_model.dart';
import 'package:ALfit/models/ui/pending_termination_surface.dart';

const _cfPath = 'functions/src/index.ts';

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

ApplicationModel _app({
  String status = AppStatus.confirmed,
  String? resignStatus,
  String? terminationStatus,
  DateTime? actualResignDate,
  DateTime? workEndDate,
  String id = 'app1',
  String businessName = '위워커',
}) =>
    ApplicationModel(
      id: id,
      businessId: 'biz1',
      businessName: businessName,
      toTitle: '[테스트] 장기',
      workDate: _d(2026, 9, 1),
      workEndDate: workEndDate ?? _d(2026, 12, 31),
      workDays: const ['월', '화', '수', '목', '금'],
      startTime: '09:00',
      endTime: '18:00',
      uid: 'worker1',
      selectedWorkType: '사무업무',
      wage: 12000,
      wageType: 'hourly',
      status: status,
      appliedAt: _d(2026, 8, 25),
      confirmedAt: _d(2026, 9, 1),
      resignStatus: resignStatus,
      terminationStatus: terminationStatus,
      actualResignDate: actualResignDate,
    );

void main() {
  final cf = _codeOf(_src(_cfPath));

  // ════════════════════════════════════════════════════════════════
  group('§48 수동 승인 — 결정만 쓴다', () {
    // 측정된 실제 span: callableApproveTermination → callableApproveResignation
    final approve = _after(cf, 'callableApproveTermination = onCall', 6800);

    test('T-01 terminationStatus=APPROVED 와 승인자를 기록한다', () {
      expect(approve.contains('terminationStatus: "APPROVED"'), isTrue);
      expect(approve.contains('terminationApprovedBy: callerUid'), isTrue);
      expect(approve.contains('terminationRespondedAt:'), isTrue);
    });

    test('T-02 actualResignDate = terminationEffectiveDate (D 를 확정한다)', () {
      // [.5-PATCH.1] fallback 이 제거되면서 D 를 **그대로** 복사한다.
      expect(approve.contains('actualResignDate: terminationEffectiveDate,'), isTrue);
    });

    test('T-03 status 를 CANCELED 로 바꾸지 않는다', () {
      expect(approve.contains('status: "CANCELED"'), isFalse);
    });

    test('T-04 confirmedDecrementedAt 를 쓰지 않는다 — 효력 전환의 마커다', () {
      expect(approve.contains('confirmedDecrementedAt'), isFalse);
    });

    test('T-05 정원을 줄이지 않는다', () {
      expect(approve.contains('totalConfirmed'), isFalse);
      expect(approve.contains('confirmedCount'), isFalse);
    });

    test('T-06 계약서를 void 하지 않는다', () {
      expect(approve.contains('status: "voided"'), isFalse);
      expect(approve.contains('voidReason'), isFalse);
    });

    test('T-07 승인 시점에 계정 세션을 끊지 않는다', () {
      expect(approve.contains('revokeRefreshTokens'), isFalse);
    });

    test('T-08 근로자 본인 또는 canManageWorkers 관리자만 — 권한 불변', () {
      expect(approve.contains('const isWorker = callerUid === workerUid'), isTrue);
      expect(approve.contains('canManageWorkers'), isTrue);
    });

    test('T-09 요청자 자기승인 차단이 남아 있다', () {
      expect(approve.contains('requestedBy === callerUid'), isTrue);
    });
  });

  // ════════════════════════════════════════════════════════════════
  // [.5-PATCH.1] MISSING-D FAIL-CLOSED
  //
  //   `terminationEffectiveDate ?? serverTimestamp()` 는 D 를 모를 때
  //   **승인을 누른 순간**을 마지막 근무일로 만들었다. 모르는 값을
  //   그럴듯한 정상값으로 바꾼 것이다 — UNKNOWN ≠ 추론된 정상값.
  group('§2–8 종료일이 없으면 승인하지 않는다', () {
    // 측정된 실제 span: callableApproveTermination → callableApproveResignation
    final approve = _after(cf, 'callableApproveTermination = onCall', 7050);

    test('P1-01 D 가 없으면 failed-precondition 으로 닫힌다', () {
      expect(approve.contains('if (!terminationEffectiveDate) {'), isTrue);
      expect(approve.contains('"failed-precondition"'), isTrue);
    });

    test('P1-02 §30 timestamp fallback 리터럴이 사라졌다', () {
      expect(
        approve.contains(
            'terminationEffectiveDate ?? admin.firestore.FieldValue.serverTimestamp()'),
        isFalse,
      );
    });

    test('P1-03 D 를 그대로 복사한다 — 재계산하지 않는다', () {
      expect(approve.contains('actualResignDate: terminationEffectiveDate,'), isTrue);
    });

    test('P1-04 §5 today / requestedAt+N / workEndDate 로 보정하지 않는다', () {
      final guardToWrite = approve.substring(
        approve.indexOf('if (!terminationEffectiveDate) {'),
        approve.indexOf('actualResignDate: terminationEffectiveDate,'),
      );
      expect(guardToWrite.contains('Date.now()'), isFalse);
      expect(guardToWrite.contains('workEndDate'), isFalse);
      expect(guardToWrite.contains('24 * 60 * 60 * 1000'), isFalse);
    });

    test('P1-05 §29 guard 가 모든 write 앞에 있다 — 상태 변화 0', () {
      expect(
        approve.indexOf('if (!terminationEffectiveDate) {') <
            approve.indexOf('tx.update(appRef'),
        isTrue,
      );
    });

    test('P1-06 신분증 창 단축도 근사치를 쓰지 않는다', () {
      expect(approve.contains('terminationEffectiveDate.toMillis()'), isTrue);
      expect(approve.contains('?? Date.now()'), isFalse);
    });

    test('P1-07 §7 legacy malformed 문서를 조용히 복구하지 않는다', () {
      // 승인이 실패해야 데이터 문제가 드러난다 — 로그만 남긴다.
      expect(approve.contains('terminationEffectiveDate 없음 — 승인 거부'), isTrue);
    });

    test('P1-08 §6 D 의 writer 는 요청 경로다 (회귀)', () {
      final req = _after(cf, 'callableRequestTermination = onCall', 9200);
      expect(req.contains('terminationEffectiveDate: terminationDate'), isTrue);
    });

    test('P1-09 §4 manual/auto 가 같은 fail-closed 정책을 쓴다', () {
      final auto = _after(cf, 'const pendingTerminationSnap', 1450);
      expect(auto.contains('if (!d3Effective)'), isTrue);
      expect(approve.contains('if (!terminationEffectiveDate) {'), isTrue);
    });
  });

  // ════════════════════════════════════════════════════════════════
  // [.5-PATCH.1] BUSINESS-SCOPED EXIT SESSION
  //
  //   종료되는 것은 한 사업장과의 근무 관계인데, revokeRefreshTokens 는
  //   ALfit 계정 전체의 세션을 끊는다. 범위가 다르다.
  group('§9–20 종료는 계정 세션 사건이 아니다', () {
    final tr = _after(cf, 'async function processExitEffectiveTransition', 11350);

    test('P1-10 §32 효력 전환이 계정 세션을 끊지 않는다', () {
      expect(tr.contains('revokeRefreshTokens'), isFalse);
    });

    test('P1-11 실패 재시도 큐에도 넣지 않는다', () {
      expect(tr.contains('pending_token_revocations'), isFalse);
    });

    test('P1-12 §15 퇴사·해지 모두 동일하다 — 한쪽만 남기지 않았다', () {
      // 공용 전환이므로 exitKind 분기 안에도 세션 조작이 없다.
      expect(tr.contains('admin.auth()'), isFalse);
    });

    test('P1-13 §21 관계 종료 책임은 그대로 남아 있다', () {
      expect(tr.contains('status: "CANCELED"'), isTrue);
      expect(tr.contains('confirmedDecrementedAt'), isTrue);
      expect(tr.contains('voidablePendingStatuses'), isTrue);
    });

    test('P1-14 §33 계정 보안 경로의 무효화는 보존됐다', () {
      // 블랙리스트(계정 정지) · 비밀번호 재설정 · 본인 세션 무효화
      expect(cf.contains('export const callableBlacklistUser'), isTrue);
      final bl = _after(cf, 'callableBlacklistUser = onCall', 3000);
      expect(bl.contains('revokeRefreshTokens'), isTrue);

      final pw = _after(cf, 'resetPasswordWithCode', 4000);
      expect(pw.contains('revokeRefreshTokens'), isTrue);

      final self = _after(cf, 'export const revokeUserSession', 600);
      expect(self.contains('revokeRefreshTokens'), isTrue);
    });

    test('P1-15 §16 종료된 관계의 접근은 authorization 이 막는다', () {
      // check-in: 소유권 · businessId · 확정상태 · 마지막 근무일
      final ci = _after(cf, 'export const callableCheckIn', 4000);
      expect(ci.contains('appData.businessId !== businessId'), isTrue);
      expect(ci.contains('confirmedStatuses.includes(appData.status'), isTrue);
      expect(ci.contains('actualResignDate'), isTrue);
    });

    test('P1-16 §18 다른 사업장 관계를 건드리지 않는다', () {
      // 전환이 쓰는 대상은 이 Application 과 그 TO/slot/계약서뿐이다.
      expect(tr.contains('collection("users")'), isFalse);
      expect(tr.contains('subAdminBusinessIds'), isFalse);
    });
  });

  // ════════════════════════════════════════════════════════════════
  // [.5-PATCH.2] EXIT ≠ MEMBERSHIP
  //
  //   SubAdmin 멤버십은 근로계약에서 생기지 않는다. member_invitations
  //   (관리자 초대) 수락으로만 만들어지고, member 문서는 invitationId 를
  //   가리킬 뿐 applicationId 를 갖지 않는다. 서로 다른 entity 다.
  //
  //   그런데 종료 writer 들이 그 멤버십을 말없이 지우고 있었다. 게다가
  //   해지 승인은 근로자 본인도 호출할 수 있어서, callableRemoveMember 가
  //   사업장 관리자 전용으로 막아 둔 제거를 우회했다.
  group('§3–8 근로 종료는 관리자 멤버십을 건드리지 않는다', () {
    // 측정된 실제 span (주석 제거 기준)
    final approveTerm = _after(cf, 'callableApproveTermination = onCall', 6200);
    final approveResign = _after(cf, 'callableApproveResignation = onCall', 4150);
    final autoResign =
        _after(cf, '.where("resignRequestedAt", "<=", threeDaysAgoUTC)', 3200);
    final autoTerm = _after(cf, 'const pendingTerminationSnap', 1450);
    final transition =
        _after(cf, 'async function processExitEffectiveTransition', 11350);

    // mutation 마커만 본다. 호출자 **자신의** 권한 조회
    //   (`collection("members").doc(callerUid).get()`) 는 authorization 이므로
    //   남아 있어야 한다 — 그것까지 금지하면 권한 검증이 사라진다.
    const forbidden = [
      'subAdminBusinessIds',
      'SEC-SUBADMIN-CLEAR',
      'revokeBatch',
      'arrayRemove',
    ];

    test('P2-01 §3 수동 해지 승인에 멤버십 변경이 없다', () {
      for (final f in forbidden) {
        expect(approveTerm.contains(f), isFalse, reason: f);
      }
    });

    test('P2-02 §4 수동 퇴사 승인에 멤버십 변경이 없다', () {
      for (final f in forbidden) {
        expect(approveResign.contains(f), isFalse, reason: f);
      }
    });

    test('P2-03 §5 D+3 자동 퇴사 승인에 멤버십 변경이 없다', () {
      for (final f in forbidden) {
        expect(autoResign.contains(f), isFalse, reason: f);
      }
    });

    test('P2-04 §6·§39 자동 해지 승인에 멤버십 변경을 새로 넣지 않았다', () {
      for (final f in forbidden) {
        expect(autoTerm.contains(f), isFalse, reason: f);
      }
    });

    test('P2-05 §7·§40 D+1 효력 전환에도 멤버십 변경이 없다', () {
      for (final f in forbidden) {
        expect(transition.contains(f), isFalse, reason: f);
      }
      // Model B(권한을 D+1 로 이동)로 가지 않았다는 확인이기도 하다.
    });

    test('P2-06 §18 legacy subAdminOf 정리도 종료 writer 가 하지 않는다', () {
      for (final w in [approveTerm, approveResign, autoResign, autoTerm]) {
        expect(w.contains('subAdminOf'), isFalse);
      }
    });

    test('P2-07 §13·§29·§32 manual/auto parity — 양쪽 모두 unchanged', () {
      // 같은 forbidden 집합이 네 경로 모두에서 부재 = 결과 동일.
      for (final w in [approveTerm, autoTerm, approveResign, autoResign]) {
        expect(w.contains('subAdminBusinessIds'), isFalse);
        expect(w.contains('arrayRemove'), isFalse);
      }
    });

    test('P2-07b 남은 members 접근은 호출자 자신의 권한 조회뿐이다', () {
      for (final w in [approveTerm, approveResign]) {
        final refs = w
            .split('\n')
            .where((l) => l.contains('collection("members")'))
            .toList();
        expect(refs.length, 1);
        expect(refs.single.contains('doc(callerUid).get()'), isTrue);
      }
    });

    test('P2-08 §15·§52 종료 성공 / 권한정리 실패 partial 경로가 사라졌다', () {
      // post-TX db.batch() + try/catch warn 조합 자체가 없어졌다.
      expect(cf.contains('subAdminBusinessIds 초기화 실패'), isFalse);
    });
  });

  // ════════════════════════════════════════════════════════════════
  group('§8·§34·§35 canonical membership writer 는 그대로다', () {
    final removeMember = _after(cf, 'callableRemoveMember = onCall', 2300);
    final leave = _after(cf, 'callableLeaveAsSubAdmin = onCall', 1200);

    test('P2-09 §34 관리자 멤버 제거가 여전히 멤버십을 지운다', () {
      expect(removeMember.contains('tx.delete(memberRef)'), isTrue);
      expect(
        removeMember.contains(
            'subAdminBusinessIds: admin.firestore.FieldValue.arrayRemove(businessId)'),
        isTrue,
      );
    });

    test('P2-10 제거 권한은 사업장 관리자에 머문다 — 근로자 우회 없음', () {
      expect(
        removeMember.contains('해당 사업장 관리자만 멤버를 제거할 수 있습니다'),
        isTrue,
      );
    });

    test('P2-11 §35 본인 직책 해제가 여전히 동작한다', () {
      expect(leave.contains('tx.delete(memberRef)'), isTrue);
      expect(
        leave.contains(
            'subAdminBusinessIds: admin.firestore.FieldValue.arrayRemove(businessId)'),
        isTrue,
      );
    });

    test('P2-12 §1 멤버십 생성은 초대 수락이 소유한다 (회귀)', () {
      expect(cf.contains('export const onMemberInvitationAccepted'), isTrue);
      expect(
        cf.contains(
            'subAdminBusinessIds: admin.firestore.FieldValue.arrayUnion(businessId)'),
        isTrue,
      );
    });

    test('P2-13 §42 member 문서는 고용이 아니라 초대를 가리킨다', () {
      final accept = _after(cf, 'tx.set(memberRef, {', 400);
      expect(accept.contains('invitationId'), isTrue);
      expect(accept.contains('applicationId'), isFalse);
    });
  });

  // ════════════════════════════════════════════════════════════════
  group('§9–17 종료 후에도 남아야 하는 것', () {
    test('P2-14 §22·§23 종료 lifecycle 자체는 그대로다', () {
      final approveTerm =
          _after(cf, 'callableApproveTermination = onCall', 6200);
      expect(approveTerm.contains('terminationStatus: "APPROVED"'), isTrue);
      expect(approveTerm.contains('actualResignDate: terminationEffectiveDate,'), isTrue);
      final approveResign =
          _after(cf, 'callableApproveResignation = onCall', 4150);
      expect(approveResign.contains('resignStatus: "APPROVED"'), isTrue);
    });

    test('P2-15 §24 exit-side 계정 세션 무효화는 여전히 없다 (.5-PATCH.1 유지)', () {
      final transition =
          _after(cf, 'async function processExitEffectiveTransition', 11350);
      expect(transition.contains('revokeRefreshTokens'), isFalse);
    });

    test('P2-16 §14·§15 capability 게이트는 멤버 문서에 그대로 의존한다', () {
      // 멤버 문서가 남으므로 canManage* 판정 경로도 그대로다.
      expect(cf.contains('memberPerms.canManageWage'), isTrue);
      expect(cf.contains('atPerms.canManageWorkers'), isTrue);
    });
  });

  // ════════════════════════════════════════════════════════════════
  group('§49 D+3 자동 승인 — manual 과 같은 operational truth', () {
    // 측정된 span: 이 블록의 마지막 단정 대상(actualResignDate: d3Effective)이
    //   +1305 에 있고, 금지 토큰(status:"CANCELED" 등)은 +19,246 이후다.
    final auto = _after(cf, 'const pendingTerminationSnap', 1450);

    test('T-10 terminationStatus=AUTO_APPROVED', () {
      expect(auto.contains('terminationStatus: "AUTO_APPROVED"'), isTrue);
    });

    test('T-11 종료일을 발명하지 않는다 — requestedAt + 24h 금지', () {
      expect(auto.contains('24 * 60 * 60 * 1000'), isFalse);
      expect(auto.contains('terminationEffectiveDate: Timestamp.fromDate'), isFalse);
    });

    test('T-12 요청이 이미 가진 terminationEffectiveDate 를 D 로 쓴다', () {
      expect(auto.contains('freshD3.terminationEffectiveDate'), isTrue);
      expect(auto.contains('actualResignDate: d3Effective'), isTrue);
    });

    test('T-13 D 가 없으면 자동승인을 보류한다 — 날짜를 만들지 않는다', () {
      expect(auto.contains('if (!d3Effective)'), isTrue);
    });

    test('T-14 status/정원/마커를 건드리지 않는다', () {
      expect(auto.contains('status: "CANCELED"'), isFalse);
      expect(auto.contains('confirmedDecrementedAt'), isFalse);
      expect(auto.contains('totalConfirmed'), isFalse);
    });

    test('T-15 승인 시점에 세션을 끊지 않는다', () {
      expect(auto.contains('revokeRefreshTokens'), isFalse);
    });

    test('T-16 PENDING 일 때만 전이 — 멱등', () {
      expect(auto.contains('terminationStatus !== "PENDING"'), isTrue);
    });
  });

  // ════════════════════════════════════════════════════════════════
  group('§9/§12 효력 전환 — 퇴사와 해지가 같은 전환을 쓴다', () {
    final tr = _after(cf, 'async function processExitEffectiveTransition', 11800);

    test('T-17 퇴사 population 이 그대로 있다 (회귀)', () {
      expect(tr.contains('exitQuery("resignStatus", "APPROVED", "CONFIRMED")'), isTrue);
      expect(
        tr.contains('exitQuery("resignStatus", "AUTO_APPROVED", "CONTRACT_PENDING")'),
        isTrue,
      );
    });

    test('T-18 해지 population 이 추가됐다', () {
      expect(
        tr.contains('exitQuery("terminationStatus", "APPROVED", "CONFIRMED")'),
        isTrue,
      );
      expect(
        tr.contains('exitQuery("terminationStatus", "AUTO_APPROVED", "CONTRACT_PENDING")'),
        isTrue,
      );
    });

    test('T-19 새 scheduler 를 복제하지 않았다 — 하나의 전환', () {
      expect(cf.contains('processTerminationEffectiveTransition'), isFalse);
      expect(cf.contains('processResignEffectiveTransition'), isFalse);
    });

    test('T-20 §15 KST 달력 경계 — raw Timestamp < now 를 쓰지 않는다', () {
      expect(tr.contains('const todayKstMidnight'), isTrue);
      expect(tr.contains('.where("actualResignDate", "<", todayKstMidnight)'), isTrue);
      expect(tr.contains('actualResignDate", "<", now'), isFalse);
    });

    test('T-21 §16 D 당일은 전환하지 않는다 — 오늘 > D 일 때만', () {
      expect(
        tr.contains('nowDateNum <= srvKstDateNum(actualResignDate)'),
        isTrue,
      );
      expect(
        tr.contains('nowDateNum <= srvKstDateNum(freshActualResignDate)'),
        isTrue,
      );
    });

    test('T-22 §17 confirmedDecrementedAt 는 여기서만 쓴다', () {
      expect(tr.contains('confirmedDecrementedAt: admin.firestore.FieldValue.serverTimestamp()'), isTrue);
    });

    test('T-23 §52 멱등 — 이미 전환된 건은 두 번 줄이지 않는다', () {
      expect(tr.contains('if (freshApp.confirmedDecrementedAt) return;'), isTrue);
    });

    test('T-24 승인된 종료만 전환한다 — fresh 재확인', () {
      expect(tr.contains('freshApproved.includes(freshApp.terminationStatus'), isTrue);
    });

    test('T-25 §19/§53 completed 계약서는 절대 void 하지 않는다', () {
      expect(tr.contains('voidablePendingStatuses'), isTrue);
      expect(
        tr.contains('const voidablePendingStatuses = ["pending_employer", "pending_worker"]'),
        isTrue,
      );
    });

    test('T-26 종료 사유가 퇴사/해지를 구분한다', () {
      expect(tr.contains('cancelReason: `\${exitKind}_EFFECTIVE`'), isTrue);
    });

    test('T-27 §11 승인 시점에 세션을 끊지 않는다', () {
      // [.5-PATCH] 승인 → D+1 이동. [.5-PATCH.1] D+1 에서도 제거 —
      //   종료는 사업장 관계 사건이지 계정 세션 사건이 아니다.
      //   자세한 단정은 P1-10~P1-16.
      final approveWindow =
          _after(cf, 'callableApproveTermination = onCall', 7050);
      expect(approveWindow.contains('revokeRefreshTokens'), isFalse);
    });

    test('T-28 §54 D 이전 실제 근태는 건드리지 않는다 — strict > 만 absent', () {
      expect(tr.contains('workDate > actualResignDate'), isTrue);
      expect(tr.contains('workDate >= actualResignDate'), isFalse);
    });

    test('T-29 재시도 population 이 해지도 포함한다', () {
      expect(
        tr.contains('["RESIGNATION_EFFECTIVE", "TERMINATION_EFFECTIVE"]'),
        isTrue,
      );
    });

    test('T-30 자정 스케줄러가 이 전환을 부른다', () {
      expect(cf.contains('processExitEffectiveTransition(timestamp)'), isTrue);
    });
  });

  // ════════════════════════════════════════════════════════════════
  group('§36–39 퇴사 ↔ 해지 상호배제', () {
    test('T-31 conflict 상태는 PENDING/APPROVED/AUTO_APPROVED 뿐', () {
      expect(
        cf.contains(
            'const EXIT_CONFLICT_STATUSES = ["PENDING", "APPROVED", "AUTO_APPROVED"]'),
        isTrue,
      );
    });

    test('T-32 REJECTED/CANCELED 는 영구히 막지 않는다', () {
      expect(cf.contains('EXIT_CONFLICT_STATUSES = ["PENDING", "APPROVED", "AUTO_APPROVED", "REJECTED"'), isFalse);
    });

    test('T-33 퇴사 요청이 진행 중인 해지를 확인한다', () {
      final req = _after(cf, 'callableRequestResignation = onCall', 5000);
      expect(
        req.contains('EXIT_CONFLICT_STATUSES.includes(\n        (data.terminationStatus'),
        isTrue,
      );
    });

    test('T-34 해지 요청이 진행 중인 퇴사를 확인한다', () {
      final req = _after(cf, 'callableRequestTermination = onCall', 9200);
      expect(
        req.contains('EXIT_CONFLICT_STATUSES.includes(\n        (snap.data()?.resignStatus'),
        isTrue,
      );
    });

    test('T-35 §38 두 검증 모두 트랜잭션 fresh read 안에 있다', () {
      final rr = _after(cf, 'callableRequestResignation = onCall', 5000);
      final rt = _after(cf, 'callableRequestTermination = onCall', 9200);
      final rrTx = rr.indexOf('runTransaction');
      final rtTx = rt.indexOf('runTransaction');
      expect(rrTx >= 0 && rr.indexOf('EXIT_CONFLICT_STATUSES') > rrTx, isTrue);
      expect(rtTx >= 0 && rt.indexOf('EXIT_CONFLICT_STATUSES') > rtTx, isTrue);
    });

    test('T-36 §40 renewal 쪽 approvedExitStatuses guard 는 그대로다 (회귀)', () {
      expect(
        cf.contains('const approvedExitStatuses = ["APPROVED", "AUTO_APPROVED"]'),
        isTrue,
      );
    });
  });

  // ════════════════════════════════════════════════════════════════
  group('§21/§22 승인과 효력을 가르는 predicate', () {
    test('T-37 isTerminationApproved 는 이름 그대로 승인 여부다', () {
      final app = _app(
        terminationStatus: AppStatus.approved,
        actualResignDate: DateTime.now().add(const Duration(days: 5)),
      );
      // 승인됐다 — status 가 아직 살아 있어도 참이어야 한다.
      expect(app.isTerminationApproved, isTrue);
    });

    test('T-38 승인 + 미래 D → 아직 효력 아님', () {
      final app = _app(
        terminationStatus: AppStatus.approved,
        actualResignDate: DateTime.now().add(const Duration(days: 5)),
      );
      expect(app.isExitEffectiveNow, isFalse);
    });

    test('T-39 §50 D 당일은 여전히 근무 관계', () {
      final d = DateTime.now();
      final app = _app(terminationStatus: AppStatus.approved, actualResignDate: d);
      expect(app.isExitEffectiveOn(d), isFalse);
    });

    test('T-40 §51 D+1 부터 효력', () {
      final d = DateTime.now();
      final app = _app(terminationStatus: AppStatus.approved, actualResignDate: d);
      expect(app.isExitEffectiveOn(d.add(const Duration(days: 1))), isTrue);
    });

    test('T-41 D-1 은 당연히 근무 관계', () {
      final d = DateTime.now().add(const Duration(days: 3));
      final app = _app(terminationStatus: AppStatus.approved, actualResignDate: d);
      expect(app.isExitEffectiveOn(DateTime.now()), isFalse);
    });

    test('T-42 퇴사 경로도 같은 규칙 (회귀)', () {
      final d = DateTime.now();
      final app = _app(resignStatus: AppStatus.autoApproved, actualResignDate: d);
      expect(app.isExitEffectiveOn(d), isFalse);
      expect(app.isExitEffectiveOn(d.add(const Duration(days: 1))), isTrue);
    });

    test('T-43 결정이 없으면 효력도 없다', () {
      final app = _app(actualResignDate: _d(2020, 1, 1));
      expect(app.isExitEffectiveOn(DateTime.now()), isFalse);
    });

    test('T-44 종료일을 모르면 끝났다고 단정하지 않는다 — UNKNOWN ≠ ENDED', () {
      final app = ApplicationModel(
        id: 'a', businessId: 'b', businessName: 'n', toTitle: 't',
        workDate: _d(2026, 9, 1), workEndDate: null,
        workDays: const ['월'], startTime: '09:00', endTime: '18:00',
        uid: 'u', selectedWorkType: '사무업무', wage: 1, wageType: 'hourly',
        status: AppStatus.confirmed, appliedAt: _d(2026, 8, 1),
        terminationStatus: AppStatus.approved,
      );
      expect(app.isExitEffectiveNow, isFalse);
    });

    test('T-45 §16 KST 자정 경계 — D 23:59 와 D+1 00:00', () {
      final d = _d(2026, 10, 10);
      final app = _app(terminationStatus: AppStatus.approved, actualResignDate: d);
      expect(app.isExitEffectiveOn(DateTime(2026, 10, 10, 0, 0)), isFalse);
      expect(app.isExitEffectiveOn(DateTime(2026, 10, 10, 23, 59)), isFalse);
      expect(app.isExitEffectiveOn(DateTime(2026, 10, 11, 0, 0)), isTrue);
    });
  });

  // ════════════════════════════════════════════════════════════════
  group('§23/§24 운영 화면은 승인이 아니라 효력을 본다', () {
    test('T-46 Calendar 가 효력 기준으로 바뀌었다', () {
      final cal = _codeOf(_src('lib/utils/calendar_helper.dart'));
      expect(cal.contains('app.isLongTermApplication && app.isExitEffectiveNow'), isTrue);
      expect(cal.contains('app.isLongTermApplication && app.isTerminationApproved'), isFalse);
    });

    test('T-47 FixedWorker 가 효력 기준으로 바뀌었다', () {
      final fw = _codeOf(_src(
          'lib/screens/business_admin/dialogs/fixed_worker_management_dialog.dart'));
      expect(fw.contains('app.isExitEffectiveOn(exitAsOf)'), isTrue);
    });

    test('T-48 FixedWorker 가 날짜 모드에서는 그 날짜로 판정한다', () {
      final fw = _codeOf(_src(
          'lib/screens/business_admin/dialogs/fixed_worker_management_dialog.dart'));
      expect(fw.contains('_isDateMode ? widget.focusDate! : DateTime.now()'), isTrue);
    });

    test('T-49 §40 연장 판정은 승인 기준 그대로 (회귀)', () {
      final rds = _codeOf(_src('lib/utils/renewal_decision_state.dart'));
      expect(rds.contains('app.isTerminationApproved'), isTrue);
    });
  });

  // ════════════════════════════════════════════════════════════════
  group('§29–35 근로자 홈 계약해지 Task', () {
    test('T-50 §34 PENDING 만 센다', () {
      final s = PendingTerminationSurface.from(
        [_app(terminationStatus: AppStatus.pending)],
        available: true,
      );
      expect(s.isVisible, isTrue);
      expect(s.count, 1);
    });

    test('T-51 §34 APPROVED/AUTO_APPROVED/REJECTED/CANCELED 는 빠진다', () {
      for (final st in [
        AppStatus.approved,
        AppStatus.autoApproved,
        AppStatus.rejected,
        AppStatus.canceled,
      ]) {
        final s = PendingTerminationSurface.from(
          [_app(terminationStatus: st)],
          available: true,
        );
        expect(s.isVisible, isFalse, reason: st);
      }
    });

    test('T-52 §35 조회 실패는 0건이 아니다 — ERROR ≠ EMPTY', () {
      final s = PendingTerminationSurface.from([], available: false);
      expect(s.isVisible, isFalse);
      expect(s.isUnavailable, isTrue);
      expect(PendingTerminationSurface.none.isUnavailable, isFalse);
    });

    test('T-53 여러 건이면 건수로 말한다', () {
      final s = PendingTerminationSurface.from([
        _app(id: 'a', terminationStatus: AppStatus.pending),
        _app(id: 'b', terminationStatus: AppStatus.pending),
      ], available: true);
      expect(s.count, 2);
      expect(s.title.contains('2건'), isTrue);
      expect(s.applicationId, isNull);
    });

    test('T-54 §32 1건이면 그 지원서를 가리킨다', () {
      final s = PendingTerminationSurface.from(
        [_app(id: 'appX', terminationStatus: AppStatus.pending)],
        available: true,
      );
      expect(s.applicationId, 'appX');
      expect(s.title.contains('위워커'), isTrue);
    });

    test('T-55 §30 신분증 요청 표면과 합치지 않았다', () {
      final home = _codeOf(_src('lib/screens/user/user_home_screen.dart'));
      // 두 표면이 각각 자기 카드를 갖는다.
      expect(home.contains('_buildIdRequestCard(context, s, up)'), isTrue);
      expect(home.contains('_buildTerminationRequestCard(context, s, up)'), isTrue);
      // ID 표면에 해지 건수를 더하지 않았다.
      expect(home.contains('_idRequestSurface.count +'), isFalse);
    });

    test('T-56 §33 알림이 아니라 도메인 상태에서 파생된다', () {
      final surf = _codeOf(_src('lib/models/ui/pending_termination_surface.dart'));
      expect(surf.contains('a.terminationStatus == AppStatus.pending'), isTrue);
      expect(surf.contains('notification'), isFalse);
      final home = _codeOf(_src('lib/screens/user/user_home_screen.dart'));
      expect(
        home.contains('PendingTerminationSurface.from(\n      _applications,'),
        isTrue,
      );
    });

    test('T-57 §35 홈이 실패를 별도 상태로 렌더한다', () {
      final home = _codeOf(_src('lib/screens/user/user_home_screen.dart'));
      expect(home.contains('surface.isUnavailable'), isTrue);
      expect(home.contains('available: !_homeLoadFailed'), isTrue);
    });

    test('T-58 §32 기존 응답 화면으로 간다 — 새 화면을 만들지 않았다', () {
      final home = _codeOf(_src('lib/screens/user/user_home_screen.dart'));
      final card = _after(home, 'Widget _buildTerminationRequestCard', 4200);
      expect(card.contains('_openMyRequests(uid)'), isTrue);
    });
  });

  // ════════════════════════════════════════════════════════════════
  group('§44–45 NO-PATCH 회귀 — 이번 변경이 건드리지 않은 것', () {
    test('T-59 급여 미지급 집계는 attendance 기반 그대로', () {
      final unpaid = _after(cf, 'async function srvHomeUnpaidWage', 900);
      expect(unpaid.contains('.where("wageStatus", "==", "confirmed")'), isTrue);
      expect(unpaid.contains('Application'), isFalse);
    });

    test('T-60 이체 writer 는 Application status 를 게이트로 쓰지 않는다', () {
      final xfer = _after(cf, 'callableMarkTransferredBatch = onCall', 4000);
      expect(xfer.contains('"CANCELED"'), isFalse);
    });

    test('T-61 §26 근무일 resolver 는 그대로 — terminationEffectiveDate 를 읽지 않는다', () {
      final res = _after(cf, 'function srvLongTermEligibleOnDay', 1800);
      expect(res.contains('terminationEffectiveDate'), isFalse);
      expect(res.contains('terminationStatus'), isFalse);
    });

    test('T-62 §44 리뷰 요청 population 은 손대지 않았다', () {
      expect(
        cf.contains('.where("status", "in", CONFIRMED_STATUSES)'),
        isTrue,
      );
    });

    test('T-63 §43 C04 주석이 실제 계약을 설명한다', () {
      final raw = _src(_cfPath);
      expect(raw.contains('operational effective end = actualResignDate ?? workEndDate'),
          isTrue);
      expect(raw.contains('[C04 설계 의도]'), isFalse);
    });
  });
}
