// [LIFECYCLE-ACTUAL-WORK-INTEGRITY-R0/R0.1] 고용관계의 끝 ≠ 일한 적 없음
//
// 이 파일이 고정하는 것:
//
//   INV-1  실근무 경계는 정의가 하나다 (lifecycle용 사본 금지)
//   INV-2  판정과 쓰기가 같은 트랜잭션 안에 있다 (stale batch 금지)
//   INV-3  일괄 writer 전부가 그 경계를 지난다
//   INV-4  보존한 건은 좌석·근태도 건드리지 않는다
//   INV-5  모르면 보존한다 (ERROR ≠ ZERO)
//   INV-6  NO_SHOW/ABSENT는 여전히 실근무가 아니다
//   INV-7  미래 확정 취소는 계속 가능하다

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

String _sliceOf(String raw, String from, String to) {
  final a = raw.indexOf(from);
  if (a < 0) throw StateError('$from 를 찾지 못함');
  final b = raw.indexOf(to, a + from.length);
  if (b < 0) throw StateError('$to 를 찾지 못함');
  return raw.substring(a, b);
}

const _cfPath = 'functions/src/index.ts';

void main() {
  final cfRaw = _src(_cfPath);
  final cf = _codeOf(cfRaw);

  final one = _flat(_codeOf(_sliceOf(cfRaw,
      'async function srvLifecycleCancelOne(', 'return "canceled";')));
  final bulk = _flat(_codeOf(_sliceOf(cfRaw,
      'async function srvLifecycleCancelBulk(',
      'return {canceled, preserved, skipped};')));

  group('INV-1 — 경계의 정의는 하나다 (§5)', () {
    test('01 R5.3E.1 판정 함수를 그대로 쓴다', () {
      expect(one, contains('srvActualWorkReasonOf(s.data())'));
      expect(one, contains('srvActualWorkAttendanceRefs(doc.id, doc.data())'));
      // lifecycle 전용 사본을 만들지 않았다.
      expect(cf, isNot(contains('lifecycleHasWorked')));
      expect(cf, isNot(contains('srvLifecycleActualWork')));
    });

    test('02 순서가 그대로다 — 비근무 terminal이 먼저 (§6)', () {
      final r = _codeOf(_sliceOf(cfRaw,
          'function srvActualWorkReasonOf(', '\n}'));
      final nonWork = r.indexOf('ATTENDANCE_NON_WORK_STATUSES.includes(st)');
      final checkIn = r.indexOf('attData["checkIn"] != null');
      final wage = r.indexOf('WAGE_SETTLEMENT_STARTED_STATUSES.includes(ws)');
      expect(nonWork, greaterThan(0));
      expect(nonWork, lessThan(checkIn));
      expect(checkIn, lessThan(wage));
    });

    test('03 정산 개시 어휘가 그대로다', () {
      expect(cf, contains(
          'const WAGE_SETTLEMENT_STARTED_STATUSES = ["calculated", "confirmed", "transferred"];'));
      expect(cf, contains(
          'const ATTENDANCE_NON_WORK_STATUSES = ["absent", "NO_SHOW"];'));
    });
  });

  group('INV-2 — 판정과 쓰기가 같은 경계 안 (§2·§3·§4)', () {
    test('04 취소가 트랜잭션 안에서 일어난다', () {
      expect(one, contains('return db.runTransaction(async (tx) => {'));
      expect(one, contains('tx.update(doc.ref, cancelData);'));
    });

    test('05 트랜잭션이 지원서를 fresh로 다시 읽는다', () {
      expect(one, contains('const fresh = await tx.get(doc.ref);'));
      expect(one, contains('if (!allowedStatuses.includes(st)) return "skipped";'));
    });

    test('06 트랜잭션이 attendance도 읽는다 — 체크인과 직렬화된다', () {
      expect(one, contains('const snaps = await Promise.all(refs.map((r) => tx.get(r)));'));
      // 읽기 순서: 지원서 → attendance → 쓰기. Firestore는 쓰기 뒤 읽기를 막는다.
      final freshAt = one.indexOf('tx.get(doc.ref)');
      final attAt = one.indexOf('refs.map((r) => tx.get(r))');
      final writeAt = one.indexOf('tx.update(doc.ref, cancelData)');
      expect(freshAt, lessThan(attAt));
      expect(attAt, lessThan(writeAt));
    });

    test('07 ref 확보는 트랜잭션 밖 — 결정적 id가 포함된다', () {
      // 쿼리는 트랜잭션에서 쓸 수 없다. 그래서 ref만 밖에서 모은다.
      final refsAt = one.indexOf('srvActualWorkAttendanceRefs');
      final txAt = one.indexOf('db.runTransaction');
      expect(refsAt, lessThan(txAt));
      // 결정적 id — 아직 없는 오늘 체크인 문서도 읽는다.
      final refs = _flat(_codeOf(_sliceOf(cfRaw,
          'async function srvActualWorkAttendanceRefs(', 'return [...byId.values()];')));
      expect(refs, contains(r'${applicationId}_${kstDateStr(Date.now())}'));
    });

    test('08 stale batch 경로가 남아 있지 않다 (§1)', () {
      // R0의 "먼저 판정하고 나중에 batch" helper는 사라졌다.
      expect(cf, isNot(contains('srvPartitionLifecycleCancelable')));
      // lifecycle 취소를 batch.update로 직접 쓰는 확정 계열 경로도 없다.
      final f = _flat(cf);
      for (final banned in [
        'batch.update(appDoc.ref, { status: "CANCELED", cancelReason: "BUSINESS_DEACTIVATED"',
        'appBatch.update(doc.ref, { status: "CANCELED", cancelReason: "BUSINESS_DELETED"',
      ]) {
        expect(f, isNot(contains(banned)), reason: banned);
      }
    });
  });

  group('INV-3 — 일괄 writer 전부가 경계를 지난다 (§1)', () {
    test('09 계정 탈퇴', () {
      final f = _flat(_codeOf(_sliceOf(cfRaw,
          'export const callableDeleteAccountApplications', 'return {')));
      expect(f, contains('const delReport = await srvLifecycleCancelBulk('));
      expect(f, contains('[...contractSnap.docs, ...confirmedSnap.docs],'));
      expect(f, contains('const allAppDocs = [...pendingSnap.docs, ...delReport.canceled];'));
    });

    test('10 사업장 비활성화 — TO 루프', () {
      expect(cf, contains('const deactivateReport = await srvLifecycleCancelBulk('));
      expect(cf, contains('const canceledCount = deactivateReport.canceled.length;'));
    });

    test('11 사업장 비활성화 — 잔여 CONFIRMED 경로', () {
      expect(cf, contains('const closedReport = await srvLifecycleCancelBulk('));
      expect(cf, contains('closedConfirmedSnap.docs,'));
    });

    test('12 사업장 삭제', () {
      expect(cf, contains('const bizDelReport = await srvLifecycleCancelBulk(appsSnap.docs, {'));
    });

    test('13 공고 삭제', () {
      expect(cf, contains('const toDelReport = await srvLifecycleCancelBulk(toDelCandidates, {'));
      expect(cf, contains('if (!toDelHandledIds.has(doc.id)) {'));
      // 확정 계열만 판정 대상 — PENDING/INVITED는 약속이 아니다.
      expect(cf, contains(
          'const toDelCandidates = pageSnap.docs.filter((doc) =>'));
    });

    test('14 다섯 호출부가 같은 helper를 쓴다', () {
      expect('srvLifecycleCancelBulk('.allMatches(cf).length, 6,
          reason: '정의 1 + 탈퇴 1 + 비활성화 2 + 사업장삭제 1 + 공고삭제 1');
      expect('srvLifecycleCancelOne('.allMatches(cf).length, 2,
          reason: '정의 1 + bulk 내부 1');
    });
  });

  group('INV-4 — 보존한 건은 좌석·근태도 그대로 (§14·§16)', () {
    test('15 탈퇴: 카운터 집계가 취소된 건에서만 나온다', () {
      final f = _flat(_codeOf(_sliceOf(cfRaw,
          'const allAppDocs = [...pendingSnap.docs, ...delReport.canceled];',
          '// [BUG-C027 FIX]')));
      expect(f, contains('for (const doc of allAppDocs)'));
      expect(f, contains('confirmedApps.push('));
    });

    test('16 탈퇴: 보존 건의 근태를 absent로 만들지 않는다', () {
      expect(cf, contains('if (appId && delPreservedIds.has(appId)) continue;'));
    });

    test('17 사업장 삭제: attendance 대상이 취소한 건으로 좁혀졌다', () {
      expect(cf, contains('const appIds = bizDelReport.canceled.map((d) => d.id);'));
      expect(cf, isNot(contains('const appIds = appsSnap.docs.map((d) => d.id);')));
    });

    test('18 공고 삭제: 보존 건은 알림·grant 회수도 하지 않는다', () {
      expect(cf, contains(
          'if (toDelReport.preserved.some((p) => p.id === doc.id)) continue;'));
    });

    test('19 보존 건수를 응답과 로그에 남긴다', () {
      expect(cf, contains('preservedCount: delPreserved.length'));
      expect(cf, contains('[lifecycle] 실근무 보존'));
      expect(cf, contains(r'실근무 보존 ${closedReport.preserved.length}건'));
    });
  });

  group('INV-5 — 모르면 보존한다 (§7)', () {
    test('20 트랜잭션 실패는 보존으로 센다', () {
      expect(bulk, contains('} catch (e) {'));
      expect(bulk, contains('return "preserved" as SrvLifecycleCancelOutcome;'));
    });

    test('21 실패를 "취소함"으로 바꾸는 분기가 없다', () {
      expect(bulk, isNot(contains('return "canceled" as')));
      expect(bulk, isNot(contains('catch (e) { canceled.push')));
    });

    test('22 실패한 트랜잭션은 아무것도 쓰지 않는다', () {
      // tx.update는 커밋 성공 시에만 반영된다 — 부분 쓰기 경로가 없다.
      expect(one, isNot(contains('await doc.ref.update(')));
      expect(one, isNot(contains('batch.commit()')));
    });
  });

  group('INV-6 — NO_SHOW는 실근무가 아니다 (§6)', () {
    test('23 좌석 회수 경로가 막히지 않았다', () {
      expect(cf, contains('const releaseWorkRefs = await srvActualWorkAttendanceRefs('));
      final r = _codeOf(_sliceOf(cfRaw,
          'function srvActualWorkReasonOf(', '\n}'));
      expect(r, contains('if (ATTENDANCE_NON_WORK_STATUSES.includes(st)) return null;'));
    });

    test('24 NO_SHOW의 wageStatus=confirmed에 속지 않는다', () {
      final r = _codeOf(_sliceOf(cfRaw,
          'function srvActualWorkReasonOf(', '\n}'));
      expect(r.indexOf('ATTENDANCE_NON_WORK_STATUSES'),
          lessThan(r.indexOf('WAGE_SETTLEMENT_STARTED_STATUSES')));
    });
  });

  group('INV-7 — 미래 확정 취소는 계속 가능 (§8)', () {
    test('25 한 건 보존이 전체를 세우지 않는다', () {
      expect(bulk, contains('canceled.push(d)'));
      expect(bulk, contains('preserved.push('));
      // 보존 발생 시 throw하지 않는다.
      expect(bulk, isNot(contains('throw new HttpsError')));
    });

    test('26 PENDING은 판정 대상이 아니다', () {
      final f = _flat(_codeOf(_sliceOf(cfRaw,
          'export const callableDeleteAccountApplications', 'return {')));
      expect(f, contains('[...contractSnap.docs, ...confirmedSnap.docs],'));
      expect(f, isNot(contains('[...pendingSnap.docs, ...contractSnap.docs, ...confirmedSnap.docs]')));
    });

    test('27 단건 취소 경로는 차단(throw)을 유지한다', () {
      expect(cf, contains('srvAssertNoActualWorkInTx(tx, cancelWorkRefs, ACTUAL_WORK_BLOCK_MESSAGE)'));
      expect(cf, contains('const ACTUAL_WORK_BLOCK_MESSAGE ='));
    });

    test('28 퇴사·해지 경로를 건드리지 않았다', () {
      expect(cf, contains('cancelReason: "RESIGNATION_EFFECTIVE"'));
      expect(cf, contains('cancelReason: "TERMINATION_APPROVED"'));
      final resign = _flat(_codeOf(_sliceOf(cfRaw,
          'cancelReason: "RESIGNATION_EFFECTIVE"', 'contractFreshSnaps')));
      expect(resign, isNot(contains('srvLifecycleCancelBulk')));
    });
  });

  group('범위 — 만들지 않은 것 (§21)', () {
    test('29 새 status·새 컬렉션을 만들지 않았다', () {
      for (final banned in [
        'ARCHIVED', 'LIFECYCLE_CANCELED', 'WORK_PRESERVED',
        'archivedApplications',
      ]) {
        expect(cf, isNot(contains(banned)), reason: banned);
      }
    });

    test('30 급여를 0으로 만드는 lifecycle 경로가 없다', () {
      for (final w in [
        'finalWage: 0, cancelReason',
        'wageStatus: "pending", cancelReason',
      ]) {
        expect(_flat(cf), isNot(contains(w)), reason: w);
      }
    });
  });
}
