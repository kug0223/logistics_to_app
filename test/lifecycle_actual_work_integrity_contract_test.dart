// [LIFECYCLE-ACTUAL-WORK-INTEGRITY-R0] 고용관계의 끝 ≠ 일한 적 없음
//
// 이 파일이 고정하는 것:
//
//   INV-1  실근무 경계는 정의가 하나다 (lifecycle용 사본 금지)
//   INV-2  일괄 lifecycle 취소가 그 경계를 지난다
//   INV-3  건너뛴 건은 좌석·근태도 건드리지 않는다
//   INV-4  모르면 보존한다 (ERROR ≠ ZERO)
//   INV-5  NO_SHOW/ABSENT는 여전히 실근무가 아니다
//   INV-6  미래 확정 취소는 계속 가능하다

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

  group('INV-1 — 경계의 정의는 하나다 (§3)', () {
    test('01 R5.3E.1 predicate를 그대로 쓴다', () {
      final part = _flat(_codeOf(_sliceOf(cfRaw,
          'async function srvPartitionLifecycleCancelable(',
          'return {cancelable, preserved};')));
      expect(part, contains('srvHasActualWorkStarted(d.id, d.data())'));
      // lifecycle 전용 사본을 만들지 않았다.
      expect(cf, isNot(contains('lifecycleHasWorked')));
      expect(cf, isNot(contains('srvLifecycleActualWork')));
    });

    test('02 순서가 그대로다 — 비근무 terminal이 먼저', () {
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

  group('INV-2 — 일괄 writer가 경계를 지난다 (§1·§4)', () {
    test('04 계정 탈퇴', () {
      final f = _flat(_codeOf(_sliceOf(cfRaw,
          'export const callableDeleteAccountApplications',
          'return {')));
      expect(f, contains('srvPartitionLifecycleCancelable( [...contractSnap.docs, ...confirmedSnap.docs])'));
      // 취소·카운터 집계가 걸러진 목록만 본다.
      expect(f, contains('const allAppDocs = [...pendingSnap.docs, ...liveConfirmedDocs];'));
    });

    test('05 사업장 비활성화 — TO 루프', () {
      expect(cf, contains(
          'const {cancelable: deactivateCancelable} ='));
      expect(cf, contains('...deactivateCancelable.map((appDoc) => ({'));
      // 원본 snapshot을 직접 쓰던 경로가 사라졌다.
      final f = _flat(cf);
      expect(f, isNot(contains(
          '...confirmedSnap.docs.map((appDoc) => ({ ref: appDoc.ref, data: { '
          'status: "CANCELED", cancelReason: "BUSINESS_DEACTIVATED"')));
    });

    test('06 사업장 비활성화 — 잔여 CONFIRMED 경로', () {
      expect(cf, contains(
          'srvPartitionLifecycleCancelable(closedConfirmedSnap.docs)'));
      expect(cf, contains('for (let i = 0; i < closedCancelable.length; i += CLOSED_BATCH_LIMIT)'));
    });

    test('07 사업장 삭제', () {
      expect(cf, contains(
          'const {cancelable: bizDelCancelable} ='));
      expect(cf, contains('if (bizDelCancelable.length > 0) {'));
    });

    test('08 공고 삭제', () {
      final f = _flat(_codeOf(_sliceOf(cfRaw,
          'const toDelCandidates = pageSnap.docs.filter', 'const batch = db.batch();')));
      expect(f, contains('CONFIRMED_STATUSES.includes'));
      expect(f, contains('srvPartitionLifecycleCancelable(toDelCandidates)'));
      expect(cf, contains('if (toDelPreservedIds.has(doc.id)) continue;'));
    });

    test('09 네 곳이 같은 helper를 쓴다', () {
      expect('srvPartitionLifecycleCancelable('.allMatches(cf).length, 6,
          reason: '정의 1 + 탈퇴 1 + 비활성화 2 + 사업장삭제 1 + 공고삭제 1');
    });
  });

  group('INV-3 — 보존한 건은 좌석·근태도 그대로 (§17)', () {
    test('10 탈퇴: 카운터 집계가 걸러진 목록에서만 나온다', () {
      final f = _flat(_codeOf(_sliceOf(cfRaw,
          'const allAppDocs = [...pendingSnap.docs, ...liveConfirmedDocs];',
          '// [BUG-C027 FIX]')));
      // confirmedApps(좌석 감소 입력)는 allAppDocs 순회에서만 채워진다.
      expect(f, contains('for (const doc of allAppDocs)'));
      expect(f, contains('confirmedApps.push('));
    });

    test('11 사업장 삭제: attendance 대상이 취소한 건으로 좁혀졌다', () {
      expect(cf, contains(
          'const appIds = bizDelCancelable.map((d) => d.id);'));
      expect(cf, isNot(contains('const appIds = appsSnap.docs.map((d) => d.id);')));
    });

    test('12 보존 건수를 응답과 로그에 남긴다', () {
      expect(cf, contains('preservedCount: delPreserved.length'));
      expect(cf, contains('[lifecycle] 실근무 보존'));
      expect(cf, contains(
          r'실근무 보존 ${closedConfirmedSnap.size - closedCancelable.length}건'));
    });
  });

  group('INV-4 — 모르면 보존한다 (§22)', () {
    final part = _flat(_codeOf(_sliceOf(cfRaw,
        'async function srvPartitionLifecycleCancelable(',
        'return {cancelable, preserved};')));

    test('13 읽기 실패는 UNKNOWN이고, 취소 대상이 아니다', () {
      expect(part, contains('} catch (e) {'));
      expect(part, contains('return {started: true, reason: "UNKNOWN", attendanceId: null};'));
    });

    test('14 실패를 "근무 없음"으로 바꾸는 분기가 없다', () {
      expect(part, isNot(contains('return SRV_NO_ACTUAL_WORK; }')));
      expect(part, isNot(contains('started: false, reason: "UNKNOWN"')));
    });
  });

  group('INV-5 — NO_SHOW는 실근무가 아니다 (§12)', () {
    test('15 좌석 회수 경로가 막히지 않았다', () {
      // callableReleaseNoshowSeat는 기존 경계를 그대로 쓴다.
      expect(cf, contains('const releaseWorkRefs = await srvActualWorkAttendanceRefs('));
      // NO_SHOW는 판정에서 비근무로 먼저 걸러진다(INV-1 02와 같은 순서).
      final r = _codeOf(_sliceOf(cfRaw,
          'function srvActualWorkReasonOf(', '\n}'));
      expect(r, contains('if (ATTENDANCE_NON_WORK_STATUSES.includes(st)) return null;'));
    });

    test('16 NO_SHOW의 wageStatus=confirmed에 속지 않는다', () {
      final r = _codeOf(_sliceOf(cfRaw,
          'function srvActualWorkReasonOf(', '\n}'));
      final nonWork = r.indexOf('ATTENDANCE_NON_WORK_STATUSES');
      final wage = r.indexOf('WAGE_SETTLEMENT_STARTED_STATUSES');
      expect(nonWork, lessThan(wage));
    });
  });

  group('INV-6 — 미래 확정 취소는 계속 가능 (§13)', () {
    test('17 PENDING/INVITED는 판정 대상이 아니다', () {
      final f = _flat(_codeOf(_sliceOf(cfRaw,
          'export const callableDeleteAccountApplications', 'return {')));
      // pendingSnap은 필터를 거치지 않고 그대로 취소된다.
      expect(f, contains('[...contractSnap.docs, ...confirmedSnap.docs]'));
      expect(f, isNot(contains('[...pendingSnap.docs, ...contractSnap.docs, ...confirmedSnap.docs])')));
    });

    test('18 단건 취소 경로는 그대로다', () {
      // 기존 R5.3E.1 writer들은 차단(throw)을 유지한다 — 건너뛰기가 아니다.
      expect(cf, contains('srvAssertNoActualWorkInTx(tx, cancelWorkRefs, ACTUAL_WORK_BLOCK_MESSAGE)'));
      expect(cf, contains('const ACTUAL_WORK_BLOCK_MESSAGE ='));
    });

    test('19 퇴사·해지 경로를 건드리지 않았다 (§11)', () {
      // 고용관계 종료는 날짜 게이트가 있는 별도 정책이다.
      expect(cf, contains('cancelReason: "RESIGNATION_EFFECTIVE"'));
      expect(cf, contains('cancelReason: "TERMINATION_APPROVED"'));
      final resign = _flat(_codeOf(_sliceOf(cfRaw,
          'cancelReason: "RESIGNATION_EFFECTIVE"', 'contractFreshSnaps')));
      expect(resign, isNot(contains('srvPartitionLifecycleCancelable')));
    });
  });

  group('범위 — 만들지 않은 것 (§24·§27)', () {
    test('20 새 status·새 컬렉션을 만들지 않았다', () {
      for (final banned in [
        'ARCHIVED', 'LIFECYCLE_CANCELED', 'WORK_PRESERVED',
        'archivedApplications',
      ]) {
        expect(cf, isNot(contains(banned)), reason: banned);
      }
    });

    test('21 급여를 0으로 만드는 lifecycle 경로가 없다 (§14)', () {
      for (final w in [
        'finalWage: 0, cancelReason',
        'wageStatus: "pending", cancelReason',
      ]) {
        expect(_flat(cf), isNot(contains(w)), reason: w);
      }
    });
  });
}
