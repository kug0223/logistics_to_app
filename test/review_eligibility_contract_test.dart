// [SYSTEM-INTEGRATION-R0.2] canonical review eligibility
//
// 실기기 증상:
//   지원자 CONFIRMED → 근무하지 않음 → NO_SHOW
//   → 다음날 사업자·지원자 양쪽에 "리뷰를 남겨주세요"
//
// DEV 실데이터가 이를 그대로 담고 있었다:
//   attendance  biz fLmS… / worker tJ8i… / 2026-09
//               rows=1  status=NO_SHOW  wageStatus=confirmed
//   review_requests  fLmS…_tJ8i…_2026_9  createdAt=2026-09-14T15:00:06Z
//                    = KST 2026-09-15 00:00 → 자정 scheduler가 만들었다
//
// 원인: emitter 둘이 서로 다른 정책을 실행했다.
//   attendance trigger  → NO_SHOW/absent 제외 (정상)
//   scheduler           → application.status ∈ CONFIRMED + workDate 경과만 확인
//                         attendance를 아예 보지 않음
//   NO_SHOW는 attendance에 기록되고 application.status는 CONFIRMED로 남으므로
//   scheduler가 trigger의 올바른 결정을 사후에 덮어썼다.
//
// 원칙(Instawork와 동일):
//   실제 근무 경험        → quality / work review
//   NO_SHOW · 결근 · 취소  → reliability / attendance event

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _cfPath = 'functions/src/index.ts';

String _src(String p) {
  final f = File(p);
  if (!f.existsSync()) throw StateError('$p 를 찾지 못함');
  return f.readAsStringSync();
}

String _codeOf(String b) =>
    b.split('\n').where((l) => !l.trimLeft().startsWith('//')).join('\n');

String _sliceOf(String source, String from, String to) {
  final a = source.indexOf(from);
  if (a == -1) throw StateError('$from 를 찾지 못함');
  final b = source.indexOf(to, a + from.length);
  if (b == -1) throw StateError('$to 를 찾지 못함');
  return source.substring(a, b);
}

// ═══════════════════════════════════════════════════════════════
// canonical vocabulary — 코드에 실재하는 값만 (§4, 추측 금지)
//   attendance.status     present · late · early_leave · absent · NO_SHOW
//   attendance.wageStatus pending · calculated · confirmed · transferred
// ═══════════════════════════════════════════════════════════════

const actualWorkStatuses = ['present', 'late', 'early_leave'];
const finalizedWageStatuses = ['confirmed', 'transferred'];

class Att {
  final String status;
  final String wageStatus;
  const Att(this.status, this.wageStatus);
}

/// `srvIsActualFinalizedWork` — attendance 한 건 판정.
bool isActualFinalizedWork(Att a) =>
    actualWorkStatuses.contains(a.status) &&
    finalizedWageStatuses.contains(a.wageStatus);

/// `srvHasActualWorkInMonth` — 월 단위 eligibility.
bool hasActualWorkInMonth(List<Att> month) => month.any(isActualFinalizedWork);

/// review_request 생성 여부 (양 emitter 공통).
bool createsRequest(List<Att> month) => hasActualWorkInMonth(month);

void main() {
  final cf = _src(_cfPath);
  final helperBlock = _sliceOf(
      cf, 'const ACTUAL_WORK_STATUSES', '// 📋 전날 완료된 단기 근무');
  final helperCode = _codeOf(helperBlock);
  final schedulerBlock = _sliceOf(
      cf, 'async function createPendingReviewRequests(', '기한 만료 리뷰 요청 자동 공개');
  final schedulerCode = _codeOf(schedulerBlock);
  final triggerBlock =
      _sliceOf(cf, 'export const onWageConfirmed = onDocumentUpdated(', 'export const');
  final triggerCode = _codeOf(triggerBlock);

  // ═══════════════════════════════════════════════════════════════
  // 01. canonical vocabulary — §4
  // ═══════════════════════════════════════════════════════════════
  group('[R0.2-01] canonical 상태 정의', () {
    test('01-a 실제 근무 status가 코드 상수로 고정됐다', () {
      expect(helperCode,
          contains('const ACTUAL_WORK_STATUSES = ["present", "late", "early_leave"]'));
    });

    test('01-b 근태 확정 wageStatus가 마감 조건과 같다', () {
      expect(helperCode,
          contains('const FINALIZED_WAGE_STATUSES = ["confirmed", "transferred"]'));
      // srvHomeUnclosed의 마감 조건과 동일한 어휘
      expect(cf, contains('ws === "confirmed" || ws === "transferred"'));
    });

    test('01-c NO_SHOW·absent는 실제 근무가 아니다', () {
      expect(actualWorkStatuses.contains('NO_SHOW'), isFalse);
      expect(actualWorkStatuses.contains('absent'), isFalse);
    });

    test('01-d wageStatus만으로 판정하지 않는다 (§9)', () {
      // NO_SHOW는 wageStatus:"confirmed"를 함께 갖는다 — 실측으로 확인됨
      const noShow = Att('NO_SHOW', 'confirmed');
      expect(finalizedWageStatuses.contains(noShow.wageStatus), isTrue);
      expect(isActualFinalizedWork(noShow), isFalse,
          reason: 'wageStatus만 보면 근무 완료로 오해된다');
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // 02. NO_SHOW / ABSENT regression — §10
  // ═══════════════════════════════════════════════════════════════
  group('[R0.2-02] NO_SHOW·ABSENT는 review 대상이 아니다', () {
    test('02-a NO_SHOW only → request 없음', () {
      expect(createsRequest([const Att('NO_SHOW', 'confirmed')]), isFalse);
    });

    test('02-b ABSENT only → request 없음', () {
      expect(createsRequest([const Att('absent', 'confirmed')]), isFalse);
    });

    test('02-c NO_SHOW + ABSENT → request 없음 (CASE B)', () {
      expect(
        createsRequest([
          const Att('NO_SHOW', 'confirmed'),
          const Att('absent', 'confirmed'),
        ]),
        isFalse,
      );
    });

    test('02-d DEV 실데이터 그룹이 재현된다', () {
      // biz fLmS… / worker tJ8i… / 2026-09 — rows=1 NO_SHOW confirmed
      expect(createsRequest([const Att('NO_SHOW', 'confirmed')]), isFalse,
          reason: '이 그룹에 만들어졌던 요청이 바로 보고된 버그다');
    });

    test('02-e request가 없으면 알림도 0이다 (§20)', () {
      // 구현상 알림은 requestRef.create() 성공 뒤에만 호출된다
      final flat = schedulerCode.replaceAll(RegExp(r'\s+'), ' ');
      expect(flat.indexOf('srvHasActualWorkInMonth'),
          lessThan(flat.indexOf('_sendReviewRequestNotification')));
      expect(flat.indexOf('await requestRef.create('),
          lessThan(flat.indexOf('_sendReviewRequestNotification')));
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // 03. 정상 근무 — §11
  // ═══════════════════════════════════════════════════════════════
  group('[R0.2-03] 실제 근무 + 근태 확정 → eligible', () {
    test('03-a present + confirmed', () {
      expect(createsRequest([const Att('present', 'confirmed')]), isTrue);
    });

    test('03-b late + transferred', () {
      expect(createsRequest([const Att('late', 'transferred')]), isTrue);
    });

    test('03-c early_leave + confirmed — 중도귀가도 실제 근무다', () {
      expect(createsRequest([const Att('early_leave', 'confirmed')]), isTrue);
    });

    test('03-d DEV 실데이터 정상 그룹이 재현된다', () {
      // biz fLmS… / worker kN2g… / 2026-07 — 5 rows
      expect(
        createsRequest(const [
          Att('late', 'confirmed'),
          Att('present', 'confirmed'),
          Att('early_leave', 'transferred'),
          Att('present', 'transferred'),
          Att('present', 'transferred'),
        ]),
        isTrue,
      );
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // 04. 월 단위 혼합 — §6, §12
  // ═══════════════════════════════════════════════════════════════
  group('[R0.2-04] mixed month (CASE A)', () {
    test('04-a 정상 3 + NO_SHOW 1 → eligible', () {
      expect(
        createsRequest(const [
          Att('present', 'confirmed'),
          Att('present', 'confirmed'),
          Att('late', 'transferred'),
          Att('NO_SHOW', 'confirmed'),
        ]),
        isTrue,
        reason: '실제 근무 경험이 존재한다',
      );
    });

    test('04-b 혼합 월에서도 request는 1건이다', () {
      // key = businessId_workerId_year_month → 월 1건
      expect(cf, contains(r'const requestKey = `${businessId}_${workerId}_${year}_${month}`'));
      // NO_SHOW 때문에 별도 star rating을 추가 생성하지 않는다
      expect(schedulerCode.contains('noShowReview'), isFalse);
      expect(schedulerCode.contains('reliabilityReview'), isFalse);
    });

    test('04-c NO_SHOW 한 건이 정상 근무를 무효화하지 않는다', () {
      final withNoShow = createsRequest(const [
        Att('present', 'confirmed'),
        Att('NO_SHOW', 'confirmed'),
      ]);
      final without = createsRequest(const [Att('present', 'confirmed')]);
      expect(withNoShow, without);
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // 05. 미확정 근태 — §13
  // ═══════════════════════════════════════════════════════════════
  group('[R0.2-05] 근태 미확정은 보류', () {
    test('05-a present + pending → 생성 금지', () {
      expect(createsRequest([const Att('present', 'pending')]), isFalse);
    });

    test('05-b present + calculated → 생성 금지', () {
      expect(createsRequest([const Att('present', 'calculated')]), isFalse);
    });

    test('05-c attendance 자체가 없으면 생성 금지 (CASE C)', () {
      expect(createsRequest(const []), isFalse);
    });

    test('05-d 날짜 경과만으로 생성하지 않는다', () {
      // scheduler는 application.status + workDate 창 **뒤에** eligibility를 본다
      expect(schedulerCode, contains('srvHasActualWorkInMonth'));
      final flat = schedulerCode.replaceAll(RegExp(r'\s+'), ' ');
      expect(flat, contains('if (!(await srvHasActualWorkInMonth('));
    });

    test('05-e UNKNOWN을 정상 근무로 간주하지 않는다', () {
      expect(createsRequest([const Att('', '')]), isFalse);
      expect(createsRequest([const Att('present', '')]), isFalse);
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // 06. 두 emitter 통합 — §7, §8
  // ═══════════════════════════════════════════════════════════════
  group('[R0.2-06] emitter가 같은 정책을 쓴다', () {
    test('06-a trigger가 canonical helper를 쓴다', () {
      expect(triggerCode, contains('srvIsActualFinalizedWork(after.status, after.wageStatus)'));
      // 제외 목록을 여기서 따로 세지 않는다
      expect(
        triggerCode.contains('docStatus === "absent" || docStatus === "NO_SHOW"'),
        isFalse,
        reason: '정책 복제가 두 emitter를 갈라놓았다',
      );
    });

    test('06-b scheduler가 같은 helper를 쓴다', () {
      expect(schedulerCode, contains('srvHasActualWorkInMonth('));
    });

    test('06-c scheduler에 독립 정책 복제가 없다', () {
      // status 리터럴을 scheduler가 직접 나열하지 않는다
      for (final lit in ['"NO_SHOW"', '"absent"', '"present"', '"early_leave"']) {
        expect(schedulerCode.contains(lit), isFalse, reason: lit);
      }
    });

    test('06-d 단기·장기 두 loop 모두 gate를 통과한다', () {
      expect(
        RegExp(r'srvHasActualWorkInMonth\(').allMatches(schedulerCode).length,
        2,
        reason: '단기 workDate 1 + 장기 workEndDate 1',
      );
    });

    test('06-e helper가 한 곳에만 정의됐다', () {
      expect(
        RegExp(r'async function srvHasActualWorkInMonth\(').allMatches(cf).length,
        1,
      );
      expect(
        RegExp(r'function srvIsActualFinalizedWork\(').allMatches(cf).length,
        1,
      );
    });

    test('06-f application.status만으로 생성하지 않는다', () {
      final flat = schedulerCode.replaceAll(RegExp(r'\s+'), ' ');
      final gateAt = flat.indexOf('srvHasActualWorkInMonth');
      final createAt = flat.indexOf('await requestRef.create(');
      expect(gateAt, greaterThan(-1));
      expect(gateAt, lessThan(createAt));
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // 07. eligibility 쿼리 — §M
  // ═══════════════════════════════════════════════════════════════
  group('[R0.2-07] eligibility 조회', () {
    test('07-a userId+businessId+yearMonth 축을 쓴다', () {
      expect(helperCode, contains('.where("userId", "==", workerId)'));
      expect(helperCode, contains('.where("businessId", "==", businessId)'));
      expect(helperCode, contains('.where("yearMonth", "==", yearMonth)'));
    });

    test('07-b 기존 인덱스의 prefix라 새 인덱스가 필요 없다', () {
      final idx = _src('firestore.indexes.json');
      expect(idx, contains('"fieldPath": "userId"'));
      // (userId, businessId, yearMonth, wageStatus) 복합 인덱스 존재
      final flat = idx.replaceAll(RegExp(r'\s+'), '');
      expect(
        flat.contains('"fieldPath":"userId","order":"ASCENDING"},'
            '{"fieldPath":"businessId","order":"ASCENDING"},'
            '{"fieldPath":"yearMonth","order":"ASCENDING"}'),
        isTrue,
      );
    });

    test('07-c select()로 필요한 필드만 읽는다', () {
      expect(helperCode, contains('.select("status", "wageStatus")'));
    });

    test('07-d yearMonth 포맷이 writer와 같다 (YYYY-MM)', () {
      expect(cf, contains(r'const yearMonth = `${year}-${mm}`'));
      expect(schedulerCode,
          contains(r'`${year}-${String(month).padStart(2, "0")}`'));
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // 08. dedupe / stale — §15, §16
  // ═══════════════════════════════════════════════════════════════
  group('[R0.2-08] dedupe · stale', () {
    test('08-a requestKey 멱등성이 유지된다', () {
      expect(schedulerCode, contains('await requestRef.create('));
      // create()는 이미 존재하면 code 6으로 실패 → 중복 생성 없음
      expect(schedulerCode, contains('if (err?.code !== 6) throw err;'));
    });

    test('08-b 이미 작성된 리뷰는 adminStatus submitted로 반영된다', () {
      expect(schedulerCode, contains('existingReviewSet.has(requestKey)'));
      expect(schedulerCode,
          contains('adminStatus: adminAlreadyReviewed ? "submitted" : "pending"'));
    });

    test('08-c 이미 리뷰한 관리자에게 재알림하지 않는다', () {
      expect(schedulerCode, contains('if (!adminAlreadyReviewed) {'));
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // 09. scope 무회귀 — §21
  // ═══════════════════════════════════════════════════════════════
  group('[R0.2-09] 범위 밖 무변경', () {
    test('09-a NO_SHOW 페널티·TrustScore 정책 무변경', () {
      expect(cf, contains('callableApplyNoShowPenalty'));
      expect(cf, contains('callableBatchSetNoShow'));
    });

    test('09-b NO_SHOW 기록 자체는 그대로 남는다', () {
      // reliability event를 숨겨서 해결하지 않는다
      expect(cf, contains('status: "NO_SHOW"'));
      expect(cf, contains('finalWage: 0'));
    });

    test('09-c staffing readiness(R0)를 건드리지 않았다', () {
      expect(cf, contains('WORKDETAIL_CONTRACT_BROKEN'));
      expect(cf, contains('wdc[wd.wdId]?.confirmedCount'));
    });

    test('09-d review 알림 문구를 바꾸지 않았다', () {
      expect(cf, contains('type: "reviewRequest"'));
    });

    test('09-e 자동 공개·기한 만료 로직 무변경', () {
      expect(cf, contains('기한 만료 리뷰 요청 자동 공개'));
    });
  });
}
