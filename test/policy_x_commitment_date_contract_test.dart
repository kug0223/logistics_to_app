// [R7-APPLICATION-LIFECYCLE.1C.1] 장기 약속의 **날짜 판정**이 서버 안에서
// 한 벌인가 — Policy X · 좌석 확정 엔진 · 근태/배치가 같은 식을 쓰는가.
//
// ── 감사 경위 ───────────────────────────────────────────────────
//   같은 장기 약속의 시작일을 세 코드가 다르게 읽었다.
//     근태·배치      desiredStartDate ?? workDate (+ confirmedAt 보정)
//     좌석 확정 엔진  desiredStartDate ?? workDate 의 raw millis
//     지원 충돌       **workDate 만**
//   그래서 10/15 부터 시작하는 약속을 지원 서버만 10/01 부터라고 추측해
//   10/10 의 정상 지원을 "일정 충돌" 로 거부할 수 있었다
//   (`[POLICY-X-IGNORES-DESIRED-START-DATE]`).
//
//   날짜 비교도 `new Date(y, m, d)` = **서버 로컬 달력일**이었다
//   (`[POLICY-X-LOCAL-TIMEZONE-DATE-NORMALIZATION]`). ALfit 의 business
//   date 는 KST 다 — 자정 저장값끼리는 같이 밀려 가려지지만, `confirmedAt`
//   처럼 시각이 있는 값이 들어오면 00:00~09:00 KST 에서 하루가 갈린다.
//
// 이 파일은 **되돌아가지 않음**을 고정한다. 값 판정(행동)은 같은 phase 의
//   `functions/test/commitment_dates.test.js` 가 실제 함수를 불러서 본다 —
//   아래 PXD-10 이 그 러너를 실행한다.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String p) {
  final f = File(p);
  if (!f.existsSync()) throw StateError('없는 파일: $p');
  return f.readAsStringSync();
}

const _kFn = 'functions/src/index.ts';
const _kMod = 'functions/src/commitment_dates.ts';
const _kRunner = 'functions/test/commitment_dates.test.js';
const _kClient = 'lib/widgets/dialogs/apply/commitment_conflict.dart';

/// [name] 부터 [chars] 글자. 함수 **본문만** 보기 위한 자(尺).
String _after(String src, String name, int chars) {
  final i = src.indexOf(name);
  expect(i, greaterThan(-1), reason: '$name 를 찾지 못함');
  return src.substring(i, (i + chars).clamp(0, src.length));
}

/// Policy X 의 확정 충돌 구간만 잘라낸다.
String _policyXBlock(String src) {
  final start = src.indexOf('// ── 6. 시간 충돌 체크 (확정 지원서 조회) ──');
  expect(start, greaterThan(-1), reason: 'Policy X 구간 표지를 찾지 못했다');
  final end = src.indexOf('// ── 7. 트랜잭션', start);
  expect(end, greaterThan(start));
  return src.substring(start, end);
}

/// 좌석 확정 엔진의 두 술어만 잘라낸다.
String _enginePredicates(String src) {
  final start = src.indexOf('function _isConflictShortTerm(');
  expect(start, greaterThan(-1));
  final end = src.indexOf('🪑 CANONICAL SEAT COMMIT', start);
  expect(end, greaterThan(start));
  return src.substring(start, end);
}

void main() {
  late String fn;
  late String block;
  late String engine;

  setUpAll(() {
    fn = _read(_kFn);
    block = _policyXBlock(fn);
    engine = _enginePredicates(fn);
  });

  group('PXD-1x Policy X 가 canonical 날짜 판정을 쓴다', () {
    test('PXD-10 기존 장기 약속의 날짜를 canonical 술어에 위임한다', () {
      expect(block.contains('srvLongTermCommitmentOnDay('), isTrue,
          reason: '단기 후보 ↔ 장기 약속은 근무일 술어 그대로다');
      // [R7-APPLICATION-LIFECYCLE.1C.1A] 장기↔장기도 per-day 진실로 본다 —
      //   구간·요일만 보면 승인된 추가근무·휴무를 놓친다.
      expect(block.contains('srvLongTermConflictDay('), isTrue,
          reason: '장기 후보 ↔ 장기 약속은 override-aware 술어를 쓴다');
    });

    test('PXD-11 workDate 를 약속 시작일로 쓰지 않는다', () {
      // 기존 결함의 형태 — 기존 약속 쪽 시작일을 workDate 로 직접 읽던 줄.
      expect(block.contains('const appWorkDate = appWorkDateTs.toDate();'),
          isFalse);
      expect(block.contains('toDateOnly(appWorkDate)'), isFalse);
      // 기존 약속 쪽 시작·종료 식을 이 자리에 다시 적지 않는다
      //   (후보 쪽 `desiredStartDate ?? workDate` 는 올바른 사용이다).
      expect(block.contains('app["desiredStartDate"]'), isFalse);
      expect(block.contains('app["workEndDate"]'), isFalse);
      expect(block.contains('app["actualResignDate"]'), isFalse);
    });

    test('PXD-12 서버 로컬 달력 성분을 business date 로 쓰지 않는다', () {
      for (final bad in [
        'getFullYear()',
        'getMonth()',
        'getDate()',
        'new Date(9999, 11, 31)',
        'toDateOnly',
      ]) {
        expect(block.contains(bad), isFalse, reason: '$bad 가 남아 있다');
      }
      // KST 자(尺)만 쓴다.
      expect(block.contains('srvKstDateNum('), isTrue);
      expect(block.contains('srvKstWeekdayKo('), isTrue);
    });

    test('PXD-13 후보 쪽 시작일도 희망 시작일을 본다', () {
      expect(
          block.contains('srvKstDateNum(\n      (desiredStartDate ?? workDate).toDate())') ||
              block.replaceAll(RegExp(r'\s+'), ' ').contains(
                  'srvKstDateNum( (desiredStartDate ?? workDate).toDate())'),
          isTrue);
    });
  });

  group('PXD-2x 범위 밖 무변경 — 상태·사업장·시간', () {
    test('PXD-20 약속 상태 집합이 그대로다', () {
      expect(
          block.contains(
              'const confirmedStatuses = ["CONFIRMED", "CONTRACT_PENDING"];'),
          isTrue);
      // 관심(PENDING·INVITED)을 blocker 로 넣지 않았다.
      expect(block.contains('"PENDING"'), isFalse);
      expect(block.contains('"INVITED"'), isFalse);
    });

    test('PXD-21 사업장으로 좁히지 않는다 — worker-global', () {
      expect(block.contains('businessId'), isFalse);
      expect(block.contains('.where("uid", "==", uid)'), isTrue);
    });

    test('PXD-22 확정 조회 수가 늘지 않았다', () {
      final queries = RegExp(r'\.collection\("applications"\)')
          .allMatches(block)
          .length;
      expect(queries, 1, reason: '상태별 병렬 쿼리 하나의 템플릿만 있다');
      expect(block.contains('.limit(200)'), isTrue);
    });

    test('PXD-23 시간 겹침 판정은 손대지 않았다', () {
      expect(block.contains('return _hasTimeOverlap(s1, e1, s2, e2);'), isTrue);
      // 인접 경계(겹침 아님)와 자정 넘김 정규화가 전역 술어에 그대로 있다.
      //   이 축은 이번 phase 가 **건드리지 않는** 것이므로 구조로 고정한다.
      for (final pin in [
        'if (end1 <= start1) end1 += 1440;',
        'if (end2 <= start2) end2 += 1440;',
        'if (start1 > start2 + 720) { start1 -= 1440; end1 -= 1440; }',
        'if (start2 > start1 + 720) { start2 -= 1440; end2 -= 1440; }',
        'return start1 < end2 && start2 < end1;',
      ]) {
        expect(fn.contains(pin), isTrue, reason: pin);
      }
      // 90분 buffer 같은 분리 규칙을 넣지 않았다.
      expect(block.contains('90'), isFalse);
    });

    test('PXD-24 사용자 문구가 그대로다', () {
      for (final msg in [
        '확정된 근무가 있어 지원할 수 없습니다.',
        '이미 \${appStartTime}~\${appEndTime}에 확정된 근무가 있습니다.',
        // [R7-APPLICATION-LIFECYCLE.1C.1A] 요일은 이제 겹친 **그 날**에서
        //   나온다(`hit.wkd`) — 문구 모양은 그대로다. 새 error code 0.
        '매주 \${hit.wkd}에 \${appStartTime}~\${appEndTime} 확정된 근무가 있어 지원할 수 없습니다.',
      ]) {
        expect(block.contains(msg), isTrue, reason: msg);
      }
      // 추가근무 하루 때문에 겹친 경우는 그 날짜를 말한다 — 기존 날짜 문구다.
      expect(
          block.contains(
              '\${hMonth}/\${hDay}에 \${appStartTime}~\${appEndTime} 확정된 근무가 있어 지원할 수 없습니다.'),
          isTrue);
    });

    test('PXD-25 날짜를 모르는 단기 약속을 조용히 넘기지 않는다', () {
      expect(block.contains('console.warn('), isTrue);
      expect(block.contains('겹침 판정 불가'), isTrue);
    });
  });

  group('PXD-3x 좌석 확정 엔진도 같은 식이다', () {
    test('PXD-30 엔진이 canonical 술어에 위임한다', () {
      expect(engine.contains('srvLongTermCommitmentOnDay('), isTrue);
      expect(engine.contains('srvLongTermConflictDay('), isTrue);
      expect(engine.contains('srvIsLongTermCommitment('), isTrue);
    });

    test('PXD-34 엔진의 두 술어도 시간 겹침을 먼저 본다', () {
      // 날짜가 맞아도 시간이 겹치지 않으면 약속이 둘일 수 없다. 이 가드가
      //   빠지면 같은 날 다른 시간대 근무까지 막힌다.
      final guard =
          'if (!_hasTimeOverlap(startTime, endTime, app.startTime ?? "", app.endTime ?? "")) return false;';
      expect(RegExp.escape(guard).isNotEmpty, isTrue);
      expect(engine.split(guard).length - 1, 2,
          reason: '단기·장기 술어 각각 하나');
    });

    test('PXD-31 raw millis 구간 비교와 로컬 달력 성분이 사라졌다', () {
      for (final bad in [
        'toMillis?.() ?? 0',
        'toMillis?.() ?? Infinity',
        'getFullYear()',
        'getMonth()',
        'getDate()',
      ]) {
        expect(engine.contains(bad), isFalse, reason: '$bad 가 남아 있다');
      }
      expect(engine.contains('srvKstDateNum('), isTrue);
      expect(engine.contains('srvKstWeekdayKo('), isTrue);
    });

    test('PXD-32 겹침 판정 쪽 요일 사전이 사라졌다', () {
      // 이 phase 가 소유한 두 자리에는 요일 표가 없다 — 요일은
      //   `srvKstWeekdayKo`(= 모듈의 단일 표)가 뽑는다. 다른 기능의 지역
      //   요일 표는 이번 owner 가 아니다.
      expect(fn.contains('const _KO_WEEKDAY = '), isFalse);
      final table = RegExp(r'\["일", "월", "화", "수", "목", "금", "토"\]');
      expect(table.hasMatch(engine), isFalse);
      expect(table.hasMatch(block), isFalse);
      expect(block.contains('const weekdayNames'), isFalse);
    });

    test('PXD-33 분류가 실제 Firestore 필드를 본다', () {
      // 예전 엔진은 `applicationType === "longTerm"` 를 봤다 — 실제 필드는 `type`.
      expect(engine.contains('applicationType'), isFalse);
      expect(_read(_kMod).contains('appData["type"] === "long_term"'), isTrue);
    });
  });

  group('PXD-4x canonical 모듈이 규칙의 단일 소유자다', () {
    test('PXD-40 index.ts 가 모듈을 import 하고 식을 다시 적지 않는다', () {
      expect(fn.contains('} from "./commitment_dates";'), isTrue);
      expect(fn.contains('const srvLongTermEligibleOnDay = longTermEligibleOnDay;'),
          isTrue);
      expect(fn.contains('const srvLongTermCommitmentOnDay = longTermCommitmentOnDay;'),
          isTrue);
      // 시작일 식이 index.ts 에 복제돼 있지 않다.
      expect(fn.contains('if (cNum > startNum) startNum = cNum;'), isFalse);
    });

    test('PXD-41 모듈이 canonical 규칙을 담고 있다', () {
      final mod = _read(_kMod);
      expect(mod.contains('desiredStartDate ?? workDate'), isTrue);
      expect(mod.contains('confirmedAt'), isTrue);
      expect(mod.contains('actualResignDate'), isTrue);
      expect(mod.contains('extraWorkDates'), isTrue);
      expect(mod.contains('leaveDates'), isTrue);
      expect(mod.contains('OPEN_ENDED_DAY_NUM'), isTrue);
      // 순수하다 — Firestore·admin SDK 를 쓰지 않는다.
      expect(mod.contains('firebase-admin'), isFalse);
      expect(mod.contains('import '), isFalse);
    });

    test('PXD-42 겹침 판정만의 예외는 종료일 모름 하나다', () {
      final mod = _read(_kMod);
      expect(mod.contains("if (r.reason !== \"NO_END\") return false;"), isTrue);
    });
  });

  group('PXD-5x 이번 범위 밖', () {
    test('PXD-50 클라이언트 resolver 가 canonical 로 수렴했다', () {
      final c = _read(_kClient);
      // 1C 에서는 서버 `callableApplyToTO` 가 `workDate` 를 보고 있었으므로
      //   화면이 **이른 쪽**을 쓰는 것이 안전했다. 1C.1 이 서버를 canonical 로
      //   고쳤고, 1C.2 가 그 보수적 해킹을 제거했다 — 남아 있으면 서버가
      //   허용하는 지원을 화면이 과잉 차단한다.
      expect(c.contains('둘 중 **이른 쪽**을 쓴다'), isFalse);
      expect(c.contains('_commitmentStart('), isFalse);
      // 하루 판정은 canonical 근무일 소유자에 위임한다(서버와 같은 규칙).
      expect(c.contains('commitment.isWorkingOnDate(d)'), isTrue);
    });

    test('PXD-51 알림·카운터 경로를 건드리지 않았다', () {
      final b = block;
      expect(b.contains('srvNotify'), isFalse);
      expect(b.contains('FieldValue.increment'), isFalse);
      expect(b.contains('workDetailCounts'), isFalse);
    });
  });

  // ══ [R7-APPLICATION-LIFECYCLE.1C.1A] 승인된 추가근무·휴무 ═══════════════
  //
  //   장기 근무의 실제 약속은 원래 근무요일만으로 결정되지 않는다.
  //   `EXTRA_WORK` 승인은 비근무일을 근무일로 만들고 `NO_WORK/LEAVE` 는
  //   근무일을 지운다. 겹침 판정이 그것을 모르면 추가근무 날의 이중 약속을
  //   놓치고, 휴무로 비워진 날의 정상 지원을 막는다.
  group('PXD-7x override-aware 겹침', () {
    test('PXD-70 canonical 모듈이 두 배열을 모두 본다', () {
      final mod = _read(_kMod);
      final eligible =
          _after(mod, 'export function longTermEligibleOnDay(', 1500);
      expect(eligible.contains('hasDay("extraWorkDates")'), isTrue);
      expect(eligible.contains('hasDay("leaveDates")'), isTrue);
      // 추가근무가 휴무보다 먼저다.
      expect(eligible.indexOf('hasDay("extraWorkDates")'),
          lessThan(eligible.indexOf('hasDay("leaveDates")')));
    });

    test('PXD-71 장기↔장기 술어가 두 배열을 모두 본다', () {
      final clash = _after(
          _read(_kMod), 'export function longTermConflictDay(', 2200);
      expect(clash.contains('overrideDayNums(a, "extraWorkDates")'), isTrue);
      expect(clash.contains('overrideDayNums(b, "extraWorkDates")'), isTrue);
      expect(clash.contains('overrideDayNums(a, "leaveDates")'), isTrue);
      expect(clash.contains('overrideDayNums(b, "leaveDates")'), isTrue);
      // 하루 단위 판정은 근무일 술어에 위임한다 — 규칙이 두 벌이 되지 않는다.
      expect(clash.contains('longTermCommitmentOnDay(a, dayNum, wkd)'), isTrue);
      expect(clash.contains('longTermCommitmentOnDay(b, dayNum, wkd)'), isTrue);
      // 시간 겹침은 호출자가 먼저 본다 — 이 술어는 날짜만 답한다.
      expect(clash.contains('hasTimeOverlap'), isFalse);
    });

    test('PXD-72 기간 전체를 하루씩 훑지 않는다 — 비용은 배열 크기에 비례', () {
      final clash = _after(
          _read(_kMod), 'export function longTermConflictDay(', 2200);
      // 공통 근무요일 스캔은 휴무 개수로 상계된다.
      expect(clash.contains('const budget = overrideDayNums(a, "leaveDates").length'),
          isTrue);
      expect(clash.contains('seen < budget'), isTrue);
      // 임의 상수 cap 을 넣지 않았다.
      for (final cap in ['365', '730', '1000']) {
        expect(clash.contains(cap), isFalse, reason: cap);
      }
    });

    test('PXD-73 Firestore 를 읽지 않는다 — schedule_change_requests 조회 0', () {
      final mod = _read(_kMod);
      expect(mod.contains('schedule_change_requests'), isFalse);
      expect(mod.contains('db.collection'), isFalse);
      expect(mod.contains('await '), isFalse);
      // Policy X 쪽도 추가 조회를 만들지 않았다.
      expect(block.contains('schedule_change_requests'), isFalse);
    });

    test('PXD-74 schedule-change writer 는 변경 0', () {
      // 승인 writer 의 canonical 보장(dual-state 금지)이 그대로다.
      expect(fn.contains('const extraWorkDates = parseDates("extraWorkDates").filter((ts) => !sameDay(ts));'),
          isTrue);
      expect(fn.contains('if (!leaveDates.some(sameDay)) leaveDates.push(scrData.targetDate as admin.firestore.Timestamp);'),
          isTrue);
      expect(fn.contains('if (!extraWorkDates.some(sameDay)) extraWorkDates.push(scrData.targetDate as admin.firestore.Timestamp);'),
          isTrue);
    });

    test('PXD-75 Apply 와 좌석 확정이 같은 술어를 쓴다', () {
      // 한쪽만 override-aware 면 지원은 통과하고 확정에서 막힌다(또는 반대).
      expect(block.contains('srvLongTermConflictDay('), isTrue);
      expect(engine.contains('srvLongTermConflictDay('), isTrue);
      final defs = RegExp(r'srvLongTermConflictDay = longTermConflictDay;')
          .allMatches(fn)
          .length;
      expect(defs, 1);
    });

    test('PXD-76 좌석 엔진이 후보 문서를 그대로 넘긴다 (후보 쪽 override 반영)', () {
      final collect = _after(
          fn, 'async function srvCollectSeatCommitOverlap(', 3000);
      expect(collect.contains('other, fd, startDateMs'), isTrue,
          reason: '후보의 추가근무·휴무도 판정에 들어가야 한다');
      // 후보 분류도 canonical 함수로 — 예전 `applicationType` 조건은 없다.
      //   주석은 그 조건을 **설명**하므로 코드 줄만 본다.
      expect(collect.contains('srvIsLongTermCommitment(fd)'), isTrue);
      final code = collect
          .split('\n')
          .where((l) => !l.trimLeft().startsWith('//'))
          .join('\n');
      expect(code.contains('fd.applicationType'), isFalse);
    });

    test('PXD-77 공용 엔진 소비자 다섯이 그대로 엔진을 지난다', () {
      for (final name in [
        'callableConfirmApplication',
        'callableApproveApplicationForReview',
        'callableAcceptTOInvitation',
        'callableAcceptRenewalProposal',
        'callableAcceptConfirmedReassignment',
      ]) {
        final i = fn.indexOf('export const $name');
        expect(i, greaterThan(-1), reason: name);
        // 각 함수 본문 안에 수집 호출이 있다.
        final body = fn.substring(i, (i + 60000).clamp(0, fn.length));
        expect(body.contains('srvCollectSeatCommitOverlap('), isTrue,
            reason: name);
      }
    });
  });

  group('PXD-6x 행동 — 실제 함수를 부른다', () {
    test('PXD-60 commitment_dates 행동 러너가 통과한다', () {
      final compiled = File('functions/lib/commitment_dates.js');
      if (!compiled.existsSync()) {
        markTestSkipped(
            'functions/lib 미빌드 — `cd functions && npm run build` 후 재실행');
        return;
      }
      final r = Process.runSync('node', ['test/commitment_dates.test.js'],
          workingDirectory: 'functions');
      final out = '${r.stdout}${r.stderr}';
      expect(r.exitCode, 0, reason: out);
      expect(out.contains('PASS'), isTrue, reason: out);
      // 셀이 비어 있지 않다.
      final m = RegExp(r'=== \[CD\] (\d+)/(\d+) PASS').firstMatch(out);
      expect(m, isNotNull, reason: out);
      expect(int.parse(m!.group(1)!), greaterThanOrEqualTo(20));
      expect(m.group(1), m.group(2));
    });

    test('PXD-61 러너가 저장소에 있고 소스 검색이 아니다', () {
      final runner = _read(_kRunner);
      expect(runner.contains("require('../lib/commitment_dates')"), isTrue);
      expect(runner.contains('assert.strictEqual('), isTrue);
    });
  });
}
