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
      expect(block.contains('srvLongTermCommitmentRange('), isTrue,
          reason: '장기 후보 ↔ 장기 약속은 canonical 구간을 쓴다');
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
        '매주 \${conflictDay}에 \${appStartTime}~\${appEndTime} 확정된 근무가 있어 지원할 수 없습니다.',
      ]) {
        expect(block.contains(msg), isTrue, reason: msg);
      }
    });

    test('PXD-25 날짜를 모르는 단기 약속을 조용히 넘기지 않는다', () {
      expect(block.contains('console.warn('), isTrue);
      expect(block.contains('겹침 판정 불가'), isTrue);
    });
  });

  group('PXD-3x 좌석 확정 엔진도 같은 식이다', () {
    test('PXD-30 엔진이 canonical 술어에 위임한다', () {
      expect(engine.contains('srvLongTermCommitmentOnDay('), isTrue);
      expect(engine.contains('srvLongTermCommitmentRange('), isTrue);
      expect(engine.contains('srvIsLongTermCommitment('), isTrue);
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
    test('PXD-50 클라이언트 resolver 는 이번에 바꾸지 않았다', () {
      final c = _read(_kClient);
      // 1C 에서 서버 parity 를 위해 **이른 쪽**을 쓰기로 적어 둔 그 자리.
      expect(c.contains('둘 중 **이른 쪽**을 쓴다'), isTrue,
          reason: 'client 정확도 수렴은 1C.2 owner 다');
    });

    test('PXD-51 알림·카운터 경로를 건드리지 않았다', () {
      final b = block;
      expect(b.contains('srvNotify'), isFalse);
      expect(b.contains('FieldValue.increment'), isFalse);
      expect(b.contains('workDetailCounts'), isFalse);
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
