// [BUSINESS-ARCHIVE · CREATE-ROLLBACK · INVITE-DECLINE-INTENT 2026-10-16] 3단계 펜스
//
// 무엇이 잘못됐었나 (DEV 배포본 에뮬레이터 역검증 — scripts/fence-runtime.js BUNDLE=)
//
//   1. 운영 종료한 사업장의 이미 시작한 장기 근무는 남은 근무일마다 자동 노쇼
//      (NO_SHOW·임금 0·신뢰도 감점)와 "내일 근무" 알림을 받았다.
//   2. 장기 근무의 "시작 전" 판정이 workDate 만 봐서, 시작일(desiredStartDate)이 미래인
//      약속도 "이미 시작"으로 보존됐다.
//   3. 소유자 탈퇴 gate 가 운영 종료(비활성) 사업장의 미지급 급여·승인 정산을 보지 않았고,
//      근로자 gate 는 일했지만 계산 전(pending) 급여를 보지 않았다.
//   4. totalSlots 필드가 없는 옛 슬롯 공고는 완성 증거 없이 공개됐다.
//   5. 구 앱의 "초대 정리"(정원 찬 초대)가 명시 거절로 기록돼 재초대 후보에서 빠졌다.
//   6. 삭제된 공고의 슬롯에 만료 마감·공고 상태 전이를 썼다.
//
// 이 파일은 그 경계가 코드에 남아 있는지 고정한다(실행 검증은 fence-runtime.js).
import 'dart:io';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ALfit/screens/business_admin/to_management/edit_to_screen.dart';
import 'package:ALfit/services/firestore_service.dart';

String _read(String p) => File(p).readAsStringSync().replaceAll('\r\n', '\n');

void main() {
  final cf = _read('functions/src/index.ts');
  String fnBody(String head) {
    final i = cf.indexOf(head);
    expect(i, greaterThanOrEqualTo(0), reason: head);
    return cf.substring(i, cf.indexOf('\n}\n', i));
  }

  group('FX-1 운영 종료 장기 근무', () {
    test('FX-11 자동 노쇼·내일 근무 알림 모두 종료일 판정을 먼저 본다', () {
      final ns = fnBody('async function processAutoNoShow(');
      // [NOSHOW-ATOMICITY 2026-10-27] 두 근무일 창 — 근무일마다 종료일 판정을 먼저 본다(자격 판정보다 앞).
      expect(ns, contains('if (srvClosedOnDay(nsClosure, d.businessId as string, srvKstDateNum(day.startUTC))) continue;'));
      expect(ns.indexOf('srvClosedOnDay(nsClosure'), lessThan(ns.indexOf('srvLongTermEligibleOnDay(d, srvKstDateNum(day.startUTC)')));
      final rem = fnBody('async function sendWorkReminders(');
      expect(rem, contains('if (srvClosedOnDay(remClosure, d.businessId as string, remDayNum)) continue;'));
    });
    test('FX-12 사업장을 못 읽으면 "닫힘(모름)" — 벌점을 추측으로 쓰지 않는다', () {
      final b = fnBody('function srvClosedOnDay(');
      expect(b, contains('if (c === undefined || c === -1) return true;'));
      expect(fnBody('async function srvBusinessClosureDayNums('), contains('chunk.forEach((id) => out.set(id, -1));'));
    });
    test('FX-13 장기 근무를 끝내지는 않는다(종료 정책 미정) — 상태 쓰기 없음', () {
      final b = fnBody('async function srvBusinessClosureDayNums(');
      // Firestore 쓰기만 본다(Map.set 은 결과 집계다).
      expect(RegExp(r'\.(update|delete)\(').hasMatch(b), isFalse);
      expect(RegExp(r'\.doc\([^)]*\)\.set\(').hasMatch(b), isFalse);
      expect(b.contains('batch'), isFalse);
    });
    test('FX-14 장기 "시작 전"은 canonical 시작일로 본다', () {
      final b = fnBody('function srvScheduleNotStarted(');
      expect(b, contains('isLongTermCommitment('));
      expect(b, contains('longTermEffectiveStartNum('));
      expect(b, contains('if (startNum <= 0) return false;'));
    });
  });

  group('FX-2 탈퇴 차단', () {
    test('FX-21 소유자 돈 의무는 운영 종료 사업장까지 본다(서버 gate)', () {
      final b = fnBody('async function srvCountOrphanMoneyObligations(');
      expect(b, contains('const live = bizSnap.docs;'));
      expect(b.contains('!d.data()["deactivatedAt"]'), isFalse);
    });
    test('FX-22 사전 조회도 돈은 전체 사업장, 공고·계약은 살아 있는 사업장', () {
      final i = cf.indexOf('export const callableGetWithdrawBlockers');
      final seg = cf.substring(i, cf.indexOf('\nexport const ', i + 10));
      expect(seg, contains('const moneyBizIds = bizSnap.docs.map((d) => d.id);'));
      expect(seg, contains('if (moneyBizIds.length === 0) {'));
      expect('moneyBatches.map('.allMatches(seg).length, 2, reason: '미지급 급여 + 정산 대기');
    });
    test('FX-23 근로자: 일했지만 계산 전(pending + 실근무)을 세고 미래 예정은 세지 않는다', () {
      final b = fnBody('async function srvCountWorkerUnpaidPayableWages(');
      expect(b, contains('"pending"'));
      expect(b, contains('if (srvActualWorkReasonOf(d.data())) n++;'));
      expect(b, contains('wd.toMillis() > todayStart) continue;'));
    });
  });

  group('FX-3 옛 슬롯 공고 완성 판정', () {
    test('FX-31 필드 없음은 완성 증거가 아니다 — 날짜 목록·슬롯으로만 증명', () {
      final b = fnBody('async function srvFlexSlotCompleteness(');
      expect(b, contains('if (!dates || dates.length === 0) return "UNVERIFIED";'));
      expect(b, contains('if (snap.empty) return "UNVERIFIED";'));
      expect(b, contains('dates.every((x) => have.has(x)) ? "COMPLETE" : "UNVERIFIED"'));
    });
    test('FX-32 예약 공개는 판정 READ 를 쓰기 전에 끝내고, 막히면 이유를 적는다', () {
      final p = fnBody('async function processScheduledPublish(');
      final reads = p.indexOf('const slotVerdicts = await Promise.all(');
      final writes = p.indexOf('// ── WRITES (모든 READ 완료 후)');
      expect(reads, greaterThan(0));
      expect(reads, lessThan(writes));
      expect(p, contains('tx.update(freshSnap.ref, {publishBlockedReason: code, publishBlockedAt: now});'));
    });
    test('FX-33 즉시 공개도 같은 판정', () {
      final i = cf.indexOf('export const callablePublishTO');
      final seg = cf.substring(i, cf.indexOf('\nexport const ', i + 10));
      expect(seg, contains('srvFlexSlotCompleteness(freshTo.ref, freshTo.data()!, tx)'));
    });
    test('FX-34 관리자 화면은 막힌 이유를 말한다(준비 단계 문구와 다르다)', () {
      expect(publishSlotBlockNotice('SLOTS_INCOMPLETE'), contains('다시 등록'));
      expect(publishSlotBlockNotice('SLOTS_UNVERIFIED'), contains('확인할 수 없어'));
      expect(publishSlotBlockNotice('NO_EMPLOYER_SEAL'), isNull);
      expect(publishSlotBlockNotice(null), isNull);
    });
    test('FX-35 삭제된 공고의 슬롯은 만료 마감하지 않는다', () {
      final b = fnBody('async function processSlotWorkDetailExpiry(');
      final skip = b.indexOf('if (t && deleted.has(t)) pending.splice(i, 1);');
      // [RETRY-OVERLAP 2026-10-27] 쓰기 자리가 슬롯별 루프(자동취소 → 슬롯 마감 거래)로 바뀌었다.
      //   건너뛰기는 여전히 그 루프(첫 쓰기)보다 앞이어야 한다.
      final write = b.indexOf('pending.map(async ({slotDoc, expiredTypes, toId})');
      expect(skip, greaterThan(0));
      expect(write, greaterThan(0), reason: '슬롯별 쓰기 루프를 찾지 못했다');
      expect(skip, lessThan(write));
      // 부정 대조: 루프 밖에서 슬롯을 먼저 쓰던 예전 일괄 update 가 남아 있지 않다.
      expect(b, isNot(contains('slotDoc.ref.update(slotUpdate)')));
    });
  });

  group('FX-4 응답 불명확한 생성', () {
    test('FX-41 서버가 분명히 거절한 오류는 재확인하지 않는다', () {
      for (final code in ['invalid-argument', 'failed-precondition', 'permission-denied', 'not-found', 'resource-exhausted']) {
        expect(TOFirestore.isAmbiguousCallableError(
            FirebaseFunctionsException(code: code, message: 'x')), isFalse, reason: code);
      }
    });
    test('FX-42 시간 초과·연결 끊김·내부 오류는 재확인 대상', () {
      for (final code in ['deadline-exceeded', 'unavailable', 'unknown', 'internal', 'cancelled']) {
        expect(TOFirestore.isAmbiguousCallableError(
            FirebaseFunctionsException(code: code, message: 'x')), isTrue, reason: code);
      }
      expect(TOFirestore.isAmbiguousCallableError(Exception('socket')), isTrue);
    });
    test('FX-43 재확인은 서버 원본(캐시 아님)·삭제 아님·totalSlots>0 일 때만 성공', () {
      final s = _read('lib/services/firestore/to_firestore.dart');
      expect(s, contains('.get(const GetOptions(source: Source.server));'));
      expect(s, contains("if (d == null || d['isDeleted'] == true) return false;"));
      expect(s, contains('return total is int && total > 0;'));
    });
  });

  group('FX-5 초대 거절 의도', () {
    test('FX-51 새 앱의 두 거절 호출은 명시 의도를 싣는다', () {
      expect(_read('lib/screens/user/my_applications_screen.dart'), contains("'declineIntent': 'EXPLICIT'"));
      expect(_read('lib/screens/common/job_posting_screen.dart'), contains("'declineIntent': 'EXPLICIT'"));
    });
    test('FX-52 서버: 의도 없는 요청 × 열려 있지 않은 슬롯 초대 → 업데이트 안내(접두어 없는 문구)', () {
      final i = cf.indexOf('export const callableDeclineTOInvitation');
      final seg = cf.substring(i, cf.indexOf('\nexport const ', i + 10));
      expect(seg, contains('const explicit = declineIntent === "EXPLICIT";'));
      // 조건식은 FX-55(배포 중간 보호 포함)가 고정한다.
      expect(seg, contains('"앱을 최신 버전으로 업데이트한 뒤 다시 확인해 주세요. "'));
      expect(seg, contains('{code: "INVITE_DECLINE_UPDATE_REQUIRED", state: proj.state}'));
    });
    test('FX-53 판정과 쓰기가 한 트랜잭션 — 철회·수락·마감을 근로자 거절로 덮지 않는다', () {
      final i = cf.indexOf('export const callableDeclineTOInvitation');
      final seg = cf.substring(i, cf.indexOf('\nexport const ', i + 10));
      final tx = seg.indexOf('const outcome = await db.runTransaction(');
      expect(tx, greaterThan(0));
      final body = seg.substring(tx);
      // 지원서·공고·슬롯을 트랜잭션 안에서 다시 읽는다
      expect(body, contains('const fresh = await tx.get(appRef);'));
      expect(body, contains('await Promise.all([tx.get(toRef), tx.get(slotRef)])'));
      // 이미 철회·수락된 건은 쓰지 않는다
      expect(body.indexOf('if (st === "CANCELED") {'), lessThan(body.indexOf('tx.update(appRef')));
      expect(body, contains('if (st === "CONFIRMED" || st === "CONTRACT_PENDING") {'));
      // 새 앱의 명시 거절도 사업장 쪽에서 끝난 초대는 쓰지 않는다
      expect(body, contains('if (explicit && proj.state === "closed") {'));
      expect(body, contains('{code: "INVITE_ALREADY_ENDED", state: proj.state}'));
      // 없는 업무 키에 집계를 만들지 않는다
      expect(body, contains('{code: "INVITE_UNIT_MISSING"}'));
      // 트랜잭션 밖의 batch 쓰기는 없다
      expect(seg.contains('declineBatch'), isFalse);
    });
    test('FX-54 만료는 근로자 거절이 아니다 — EXPIRED 는 쓰지 않고, 기한 지난 INVITED 는 기존 만료 writer 로', () {
      final i = cf.indexOf('export const callableDeclineTOInvitation');
      final seg = cf.substring(i, cf.indexOf('\nexport const ', i + 10));
      final body = seg.substring(seg.indexOf('const outcome = await db.runTransaction('));
      expect(body, contains('{code: "INVITE_ALREADY_EXPIRED"}'));
      // 기존 만료 writer(스케줄러와 같은 helper·같은 기준)를 재사용 — 새 만료 규칙 없음
      expect(body, contains('await srvTerminateWaitingApplicationInTx(tx, appRef, {'));
      expect(body, contains('expectStatus: "INVITED",'));
      expect(body, contains('action: "AUTO_EXPIRE",'));
      expect(fnBody('async function processExpiredTOInvitations('),
          contains('srvTerminateWaitingApplicationInTx(tx, doc.ref, {'));
      // EXPIRED → REJECTED 경로는 없다
      expect(body.indexOf('if (st === "EXPIRED") {'),
          lessThan(body.indexOf('tx.update(appRef')));
      expect(seg, contains('{code: "INVITE_EXPIRED"}'));
    });
    test('FX-55 배포 중간 보호 — 의도 없는 요청은 공개 자동 마감된 유효 초대도 쓰지 않는다', () {
      final i = cf.indexOf('export const callableDeclineTOInvitation');
      final seg = cf.substring(i, cf.indexOf('\nexport const ', i + 10));
      expect(seg, contains('if (!explicit && (proj.state !== "available" || proj.publicIntakeClosed)) {'));
    });
  });

  group('FX-6 운영 종료 뒤 새 출근·새 약속 (4단계)', () {
    test('FX-61 본인 출근: 장기 근무는 종료일부터 거절, 사업장 문서가 없으면 거절', () {
      final i = cf.indexOf('export const callableCheckIn = ');
      final seg = cf.substring(i, cf.indexOf('\nexport const ', i + 10));
      expect(seg, contains('if (!bizSnap.exists) {'));
      expect(seg, contains('ciDayNum >= srvKstDateNum(ciClosedAt.toDate())'));
      expect(seg, contains('{code: "BUSINESS_CLOSED"}'));
      // 장기 분기 안에만 있다 — 단기(이미 시작해 보존된 건) 출근 규칙은 그대로
      final longAt = seg.indexOf('if ((appData.type as string) === "long_term") {');
      final elseAt = seg.indexOf('} else {', longAt);
      expect(seg.indexOf('BUSINESS_CLOSED'), greaterThan(longAt));
      expect(seg.indexOf('BUSINESS_CLOSED'), lessThan(elseAt));
    });
    test('FX-62 퇴근은 사업장 종료를 보지 않는다(이미 출근한 날 마무리)', () {
      final i = cf.indexOf('export const callableCheckOut = ');
      final seg = cf.substring(i, cf.indexOf('\nexport const ', i + 10));
      expect(seg.contains('deactivatedAt'), isFalse);
      expect(seg.contains('BUSINESS_CLOSED'), isFalse);
    });
    test('FX-63 관리자 일괄 출근: 종료 전에 시작한 근무만 기록(종료일은 종료 시각 이전 출근만)', () {
      final i = cf.indexOf('export const callableBatchCheckIn = ');
      final seg = cf.substring(i, cf.indexOf('\nexport const ', i + 10));
      // 두 경로(기존 행 최초 출근·신규 기록) 공통 — attendanceId 분기보다 앞이다
      final gate = seg.indexOf('if (srvArchivedNewWorkBlocked(');
      expect(gate, greaterThan(0));
      expect(gate, lessThan(seg.indexOf('if (attendanceId) {')));
      expect(seg, contains('return "businessClosed";'));
      final b = fnBody('function srvArchivedNewWorkBlocked(');
      expect(b, contains('if (dayNum > closeDay) return true;'));
      expect(b, contains('return !(typeof checkInMs === "number" && checkInMs < closedAt.toMillis());'));
    });
    test('FX-64 계약 연장: 제안·수락 모두 운영 종료 사업장이면 거절, D-15 알림 미발송', () {
      expect('await srvAssertBusinessOpenForNewCommitment(businessId);'.allMatches(cf).length, 2);
      final b = fnBody('async function srvAssertBusinessOpenForNewCommitment(');
      expect(b, contains('if (!b || !b.exists) {'));
      expect(b, contains('if (b.get("deactivatedAt") != null) {'));
      expect(fnBody('async function processContractRenewalChecks('),
          contains('if (bizData?.deactivatedAt != null) return;'));
    });
    test('FX-65 화면: 닫힌 사업장 장기 근무는 위치 확인 전에 출근을 막는다', () {
      final s = _read('lib/screens/user/attendance_check_screen.dart');
      final gate = s.indexOf('if (AttendanceCheckScreen.closedForNewCheckIn(');
      final loc = s.indexOf("final type = business.attendanceType;");
      expect(gate, greaterThan(0));
      expect(gate, lessThan(loc));
      expect(s, contains('if (!work.isLongTermApplication) return false;'));
    });
  });

  group('FX-7 소유자 탈퇴 최종 검사 · 거절 문구 (4단계)', () {
    test('FX-71 최종 서버 검사는 승인된 정산만 막는다 — 승인 대기는 기존 설계 결정(WBP-SUB-02)대로 세지 않는다', () {
      // 4단계에서 PENDING 을 최종 검사에 넣었다가 되돌렸다. PENDING 은 승인된 지급
      // 의무가 아니고, 이체 뒤 남은 낡은 PENDING 까지 막으면 영구 차단이 된다는 기록된
      // 결정이 있다. 사전 조회(INTERIM_PENDING)와의 기준 차이는 제품 결정으로 남긴다.
      final b = fnBody('async function srvCountOrphanMoneyObligations(');
      expect(b, contains('.where("status", "==", "APPROVED")'));
      expect(b.contains('"PENDING"'), isFalse);
      final g = fnBody('async function srvAssertAccountDeletionAllowed(');
      expect(g, contains('[INTERIM_SETTLEMENT_UNPROCESSED]'));
      expect(g.contains('[INTERIM_PENDING]'), isFalse);
    });
    test('FX-73 운영 종료 트리거는 deactivatedAt: null(앱 생성 사업장)을 활성으로 본다', () {
      final i = cf.indexOf('export const onBusinessDeactivated');
      final seg = cf.substring(i, i + 2500);
      expect(seg, contains('if (before.deactivatedAt != null || after.deactivatedAt == null) return;'));
      expect(seg.contains('before.deactivatedAt !== undefined'), isFalse);
      // 앱은 여전히 null 을 쓴다 — 그래서 위 비교가 필요하다
      expect(_read('lib/models/core/business_model.dart'),
          contains("'deactivatedAt': deactivatedAt != null ? Timestamp.fromDate(deactivatedAt!) : null,"));
    });
    test('FX-72 이미 철회된 초대: 상태 코드를 문구에 넣지 않는다(구 앱은 e.message 를 그대로 띄운다)', () {
      final i = cf.indexOf('export const callableDeclineTOInvitation');
      final seg = cf.substring(i, cf.indexOf('\nexport const ', i + 10));
      expect(seg, contains('"사업장이 이미 정리한 초대예요. 목록을 새로고침해 주세요."'));
      expect(seg, contains('{code: "INVITE_ALREADY_WITHDRAWN"}'));
      expect(seg.indexOf('currentStatus === "CANCELED"'),
          lessThan(seg.indexOf('처리할 수 없는 상태입니다')));
    });
  });
}
