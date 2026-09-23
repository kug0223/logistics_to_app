// [CORRECTION-PRE0-LONGTERM-BACKDATED-ATTENDANCE-SEED]
//
// PRE0 fixture pack 의 목적은 **제품이 만들 수 있는 상태**를 DEV 에 만드는
// 것이다. fixture 가 제품상 불가능한 상태를 만들면, 그 뒤의 검증이 무엇을
// 근거로 통과했는지 알 수 없게 된다.
//
// 장기 fixture 는 "이미 확정되어 일해 온 근로자"를 표현하면서 확정만
// seed 실행 시각에 했다. 오늘 확정된 사람이 지난주에 일한 상태다.
//
//     confirmedAt  2026-09-23 01:10
//     attendance   9/16 · 9/18 · 9/20 · 9/22
//
// 이 파일은 seed 가 다시 그 상태를 만들지 못하게 고정한다.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _buildPath = 'scripts/r7-fixture-build.js';
const _seedPath = 'scripts/seed-r7-fixtures-dev.js';
const _cleanupPath = 'scripts/r7-fixture-cleanup.js';
const _fixPath = 'scripts/pre0-longterm-chronology-fix.js';

String _src(String p) {
  final f = File(p);
  if (!f.existsSync()) throw StateError('$p 를 찾지 못함');
  return f.readAsStringSync();
}

/// 주석 줄을 지운 본문. 앵커는 주석이 아니라 **코드**여야 한다.
String _codeOf(String s) => s
    .split('\n')
    .where((l) {
      final t = l.trimLeft();
      return !t.startsWith('//') && !t.startsWith('*') && !t.startsWith('/*');
    })
    .join('\n');

String _after(String src, String name, int chars) {
  final i = src.indexOf(name);
  if (i < 0) throw StateError('$name 를 찾지 못함');
  return src.substring(i, (i + chars).clamp(0, src.length));
}

// ══════════════════════════════════════════════════════════════════
// seed 가 쓰는 판정의 거울 — assertLongTermFixtureAttendanceEligible.
// ══════════════════════════════════════════════════════════════════

const _wkKo = ['일', '월', '화', '수', '목', '금', '토'];

int _dayNum(DateTime d) => d.year * 10000 + d.month * 100 + d.day;
String _wkd(DateTime d) => _wkKo[d.weekday % 7];

/// [offsets] 근태 날짜들이 이 fixture 의 실제 근무일인가.
/// 어긋나면 이유를 돌려준다 — seed 는 여기서 던진다.
String? fixtureAttendanceViolation({
  required List<int> offsets,
  required DateTime today,
  required DateTime confirmedAt,
  required int workDateOffset,
  required int workEndOffset,
  required List<String> workDays,
}) {
  DateTime day(int o) => today.add(Duration(days: o));
  // desiredStartDate 없음 → workDate, 확정일의 KST 날짜가 더 뒤면 그쪽.
  final startNum = [
    _dayNum(day(workDateOffset)),
    _dayNum(confirmedAt),
  ].reduce((a, b) => a > b ? a : b);
  final endNum = _dayNum(day(workEndOffset));
  for (final o in offsets) {
    final d = day(o);
    if (_dayNum(d) < startNum) return 'BEFORE_START:${_dayNum(d)}';
    if (_dayNum(d) > endNum) return 'AFTER_END:${_dayNum(d)}';
    if (!workDays.contains(_wkd(d))) return 'NON_WORKDAY:${_dayNum(d)}';
  }
  return null;
}

void main() {
  final build = _codeOf(_src(_buildPath));
  final seed = _codeOf(_src(_seedPath));
  final cleanup = _codeOf(_src(_cleanupPath));
  final fix = _codeOf(_src(_fixPath));

  // 실제 seed 가 쓰는 값. 여기와 스크립트가 갈리면 03군이 깨진다.
  const attendanceOffsets = [-7, -5, -3, -1];
  const workDays = ['월', '화', '수', '목', '금', '토', '일'];
  final today = DateTime(2026, 9, 23);
  // -7일 05:00 KST
  final seedConfirmedAt = today.subtract(const Duration(days: 7));

  // ══════════════════════════════════════════════════════════════
  // 01. 연대기 계약 — 확정 전 근무를 만들지 않는다
  // ══════════════════════════════════════════════════════════════
  group('01. fixture 연대기', () {
    test('01-a 수정 전 상태는 거절된다 — 회귀 고정', () {
      // confirmedAt = seed 실행일(오늘) → 과거 근태 전부 확정 이전.
      final v = fixtureAttendanceViolation(
        offsets: attendanceOffsets,
        today: today,
        confirmedAt: today,
        workDateOffset: -14,
        workEndOffset: 30,
        workDays: workDays,
      );
      expect(v, 'BEFORE_START:20260916',
          reason: '이것이 PRE0 이 실제로 만들었던 상태다');
    });

    test('01-b 되돌린 확정일이면 전부 통과한다', () {
      expect(
        fixtureAttendanceViolation(
          offsets: attendanceOffsets,
          today: today,
          confirmedAt: seedConfirmedAt,
          workDateOffset: -14,
          workEndOffset: 30,
          workDays: workDays,
        ),
        isNull,
      );
    });

    test('01-c 확정일 당일 근무는 허용된다 — 경계', () {
      // 가장 이른 근태와 같은 날 확정. 그날 06:00 근무 시작 전이다.
      expect(
        fixtureAttendanceViolation(
          offsets: const [-7],
          today: today,
          confirmedAt: today.subtract(const Duration(days: 7)),
          workDateOffset: -14,
          workEndOffset: 30,
          workDays: workDays,
        ),
        isNull,
      );
    });

    test('01-d 확정 다음날부터는 그 이전 근무가 막힌다', () {
      expect(
        fixtureAttendanceViolation(
          offsets: const [-7],
          today: today,
          confirmedAt: today.subtract(const Duration(days: 6)),
          workDateOffset: -14,
          workEndOffset: 30,
          workDays: workDays,
        ),
        'BEFORE_START:20260916',
      );
    });

    test('01-e 계약 종료 이후 근태는 만들지 않는다', () {
      expect(
        fixtureAttendanceViolation(
          offsets: const [31],
          today: today,
          confirmedAt: seedConfirmedAt,
          workDateOffset: -14,
          workEndOffset: 30,
          workDays: workDays,
        ),
        startsWith('AFTER_END'),
      );
    });

    test('01-f 비근무요일 근태는 만들지 않는다', () {
      // -7 = 2026-09-16 수요일. workDays 에서 수를 뺀다.
      expect(_wkd(today.subtract(const Duration(days: 7))), '수');
      expect(
        fixtureAttendanceViolation(
          offsets: const [-7],
          today: today,
          confirmedAt: seedConfirmedAt,
          workDateOffset: -14,
          workEndOffset: 30,
          workDays: const ['월', '화', '목', '금', '토', '일'],
        ),
        'NON_WORKDAY:20260916',
      );
    });
  });

  // ══════════════════════════════════════════════════════════════
  // 02. seed script 가 그 계약을 실제로 건다
  // ══════════════════════════════════════════════════════════════
  group('02. seed 배선', () {
    test('02-a 근무일 assert 가 존재한다', () {
      expect(build.contains('function assertLongTermFixtureAttendanceEligible('),
          true);
      for (final f in ['BEFORE_START', 'startNum', 'endNum', 'kstWeekday']) {
        // 서버 resolver 와 같은 축을 본다.
        expect(
          build.contains(f) ||
              build.contains('실효 시작일') ||
              build.contains('계약 종료일'),
          true,
          reason: f,
        );
      }
    });

    test('02-b 장기 빌더가 그 assert 를 부른다', () {
      final b = _after(build, 'async function buildLongTermWorker(', 4000);
      expect(b.contains('assertLongTermFixtureAttendanceEligible('), true);
    });

    test('02-c 확정 시각을 근무 이력 앞으로 되돌린다', () {
      final b = _after(build, 'async function buildLongTermWorker(', 4000);
      expect(b.contains('const seedConfirmedAtMs = kstMidnightMs(-7)'), true);
      expect(b.contains('confirmedAt: admin.firestore.Timestamp.fromMillis(seedConfirmedAtMs)'),
          true);
    });

    test('02-d 되돌리기가 근태 생성보다 **먼저** 일어난다', () {
      // 순서가 뒤집히면 canonical 게이트가 먼저 거절한다.
      final b = _after(build, 'async function buildLongTermWorker(', 6000);
      final backdate = b.indexOf('confirmedAt: admin.firestore.Timestamp.fromMillis(');
      final firstCheckIn = b.indexOf("'callableBatchCheckIn'");
      expect(backdate, greaterThan(-1));
      expect(firstCheckIn, greaterThan(-1));
      expect(backdate, lessThan(firstCheckIn));
    });

    test('02-e 약속 필드는 되돌리지 않는다', () {
      final b = _after(build, 'async function buildLongTermWorker(', 6000);
      final i = b.indexOf(".doc(appId).update({");
      expect(i, greaterThan(-1));
      final seg = b.substring(i, i + 260);
      for (final banned in [
        'workDate:', 'workEndDate:', 'workDays:', 'wage:', 'startTime:',
      ]) {
        expect(seg.contains(banned), false, reason: banned);
      }
      expect(seg.contains('appliedAt:'), true);
      expect(seg.contains('confirmedAt:'), true);
    });

    test('02-f 검사한 날짜와 만드는 날짜가 갈리지 않는다', () {
      final b = _after(build, 'async function buildLongTermWorker(', 6000);
      expect(b.contains('const attendanceOffsets = [-7, -5, -3, -1];'), true);
      expect(b.contains('검사한 날짜'), true);
    });
  });

  // ══════════════════════════════════════════════════════════════
  // 03. 범위 — 하나가 어긋났다고 전체를 다시 만들지 않는다
  // ══════════════════════════════════════════════════════════════
  group('03. targeted correction', () {
    test('03-a seed/cleanup 에 --only 가 있다', () {
      expect(seed.contains("args['only']"), true);
      expect(seed.contains('if (ONLY && s.id !== ONLY) continue;'), true);
      expect(seed.contains('.filter(([id]) => !ONLY || id === ONLY)'), true);
    });

    test('03-b cleanup 이 남의 지원서를 가져가지 않는다', () {
      expect(cleanup.contains('const ownerUids = new Set();'), true);
      expect(cleanup.contains('removed.foreign++;'), true);
    });

    test('03-c 남의 지원서가 있으면 공고도 남긴다', () {
      // 공고를 지우면 그 기록이 고아가 된다.
      expect(cleanup.contains('if (entities.toId && removed.foreign === 0) {'),
          true);
    });
  });

  // ══════════════════════════════════════════════════════════════
  // 04. 이미 만들어진 fixture 를 고치는 경로
  // ══════════════════════════════════════════════════════════════
  group('04. 현장 보정 스크립트', () {
    test('04-a DEV 전용 guard 가 있다', () {
      expect(fix.contains("const EXPECTED_DEV_PROJECT = 'alfit-89567';"), true);
      expect(fix.contains('process.exit(2);'), true);
    });

    test('04-b manifest 에 적힌 id 만 읽는다', () {
      expect(fix.contains('rec.entities.yesterdayAttendanceId'), true);
      expect(fix.contains('rec.entities.payroll'), true);
      // 쿼리로 훑지 않는다.
      expect(fix.contains(".collection('attendance').where("), false);
      expect(fix.contains(".collection('applications').where("), false);
    });

    test('04-c 타임스탬프 두 개만 쓴다', () {
      final i = fix.indexOf('await appRef.update({');
      expect(i, greaterThan(-1));
      final seg = fix.substring(i, i + 220);
      expect(seg.contains('appliedAt:'), true);
      expect(seg.contains('confirmedAt:'), true);
      for (final banned in ['workDate', 'workEndDate', 'workDays', 'wage']) {
        expect(seg.contains(banned), false, reason: banned);
      }
    });

    test('04-d 보정 후에도 어긋나면 쓰지 않는다', () {
      expect(fix.contains('보정해도'), true);
      final i = fix.indexOf('const bad = Object.keys(tally)');
      final j = fix.indexOf('await appRef.update({');
      expect(i, greaterThan(-1));
      expect(i, lessThan(j), reason: '검사가 쓰기보다 먼저여야 한다');
    });

    test('04-e 여러 번 실행해도 같다', () {
      expect(fix.contains('const already ='), true);
      expect(fix.contains("if (already) { console.log('\\n변경 없음.'); return; }"),
          true);
    });

    test('04-f 기준 시각을 근태에서 직접 뽑는다 — 언제 돌려도 같다', () {
      // "오늘 - 7일"로 잡으면 실행일마다 값이 달라진다.
      expect(
        fix.contains('const earliestMs = Math.min(...atts.map((a) => a.data.workDate.toMillis()));'),
        true,
      );
    });
  });
}
