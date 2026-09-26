// [.6-P3] 급여 기간 권위 · 미이체 건수 권한 계약.
//
//   지키는 문장은 둘이다.
//
//     이 돈이 어느 날·어느 달의 것인지는 근태가 정한다.
//     급여 도메인 숫자는 급여 자격이 있어야 본다.
//
//   KST 파생은 Dart 로 재구현해 경계를 직접 고정하고(순수 함수),
//   어느 소비자가 무엇을 쓰는지는 소스 문자열로 고정한다.
//   둘 다 없으면 한쪽만 고쳐도 통과한다.

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

String _codeOf(String src) => src
    .split('\n')
    .where((l) => !l.trimLeft().startsWith('//'))
    .join('\n');

String _fn(String src, String name) {
  final i = src.indexOf(name);
  expect(i, greaterThan(-1), reason: '$name 을 찾지 못했다');
  final n = src.indexOf('\nexport const ', i + 10);
  return src.substring(i, n > 0 ? n : src.length);
}

String _after(String src, String name, int chars) {
  final i = src.indexOf(name);
  expect(i, greaterThan(-1), reason: '$name 을 찾지 못했다');
  final e = (i + chars) > src.length ? src.length : i + chars;
  return src.substring(i, e);
}

// ─────────────────────────────────────────────────────────────
// KST 파생 — 서버 srvWorkDateParts 와 같은 식
// ─────────────────────────────────────────────────────────────

const _kstMs = 9 * 60 * 60 * 1000;

class Parts {
  const Parts(this.year, this.month, this.date, this.yearMonth);
  final int year;
  final int month;
  final String date;
  final String yearMonth;

  @override
  bool operator ==(Object o) =>
      o is Parts && o.year == year && o.month == month &&
      o.date == date && o.yearMonth == yearMonth;

  @override
  int get hashCode => Object.hash(year, month, date, yearMonth);

  @override
  String toString() => '$date($year/$month, $yearMonth)';
}

/// attendance.workDate(UTC 기준 시각) → KST 달력 값.
Parts workDateParts(DateTime utc) {
  final k = utc.toUtc().add(const Duration(milliseconds: _kstMs));
  final mm = k.month.toString().padLeft(2, '0');
  final dd = k.day.toString().padLeft(2, '0');
  return Parts(k.year, k.month, '${k.year}-$mm-$dd', '${k.year}-$mm');
}

/// KST 자정에 해당하는 UTC 시각 — fixture 만들기용.
DateTime kst(int y, int m, int d, [int h = 0, int min = 0]) =>
    DateTime.utc(y, m, d, h, min).subtract(const Duration(milliseconds: _kstMs));

// ─────────────────────────────────────────────────────────────
// 권한 — D-1 srvAssertWageAuthority 와 같은 식
// ─────────────────────────────────────────────────────────────

String? wageAuthority({
  required String uid,
  required String role,
  required String? ownerId,
  required List<String> adminIds,
  required List<String> subAdminBusinessIds,
  required String targetBiz,
  required Map<String, Map<String, bool>> memberPerms,
}) {
  if (role == 'SUPER_ADMIN') return null;
  final isMember = adminIds.contains(uid) ||
      ownerId == uid ||
      subAdminBusinessIds.contains(targetBiz);
  if (!isMember) return 'not-member';
  if (ownerId == uid || adminIds.contains(uid)) return null;
  final p = memberPerms[uid] ?? const <String, bool>{};
  return p['canManageWage'] == true ? null : 'no-canManageWage';
}

void main() {
  late String code;

  setUpAll(() {
    code = _codeOf(File('functions/src/index.ts').readAsStringSync());
  });

  // ───────────────────────────────────────────────────────────
  group('P3-1x 날짜 권위 (§13)', () {
    test('A 월말 — 근태 9/30, 클라이언트 10/01 → 2026-09', () {
      final p = workDateParts(kst(2026, 9, 30));
      expect(p.yearMonth, '2026-09');
      expect(p.date, '2026-09-30');
      // 클라이언트가 보낸 값은 파생에 관여하지 않는다.
      expect(p, isNot(equals(workDateParts(kst(2026, 10, 1)))));
    });

    test('B 월초 — 근태 10/01, 클라이언트 전월 payload → 2026-10', () {
      final p = workDateParts(kst(2026, 10, 1));
      expect(p.yearMonth, '2026-10');
      expect(p.month, 10);
    });

    test('C 연말 — 근태 2026-12-31 → year 2026', () {
      final p = workDateParts(kst(2026, 12, 31));
      expect(p.year, 2026);
      expect(p.yearMonth, '2026-12');
    });

    test('D 연초 — 근태 2027-01-01 → year 2027', () {
      final p = workDateParts(kst(2027, 1, 1));
      expect(p.year, 2027);
      expect(p.yearMonth, '2027-01');
    });

    test('E UTC/KST 경계 — 23:xx UTC 는 다음날 KST 다', () {
      // 2026-09-30 15:00 UTC = 2026-10-01 00:00 KST
      expect(workDateParts(DateTime.utc(2026, 9, 30, 15, 0)).date,
          '2026-10-01');
      // 2026-09-30 14:59 UTC = 2026-09-30 23:59 KST
      expect(workDateParts(DateTime.utc(2026, 9, 30, 14, 59)).date,
          '2026-09-30');
      // 서버 머신 UTC 날짜를 쓰면 둘 다 09-30 이 된다 — 그것이 버그였다.
    });

    test('E2 연말 자정 경계', () {
      // 2026-12-31 15:00 UTC = 2027-01-01 00:00 KST
      final p = workDateParts(DateTime.utc(2026, 12, 31, 15, 0));
      expect(p.year, 2027);
      expect(p.yearMonth, '2027-01');
    });

    test('E3 KST 자정 직후·직전이 같은 달로 뭉개지지 않는다', () {
      expect(workDateParts(kst(2026, 10, 1, 0, 1)).yearMonth, '2026-10');
      expect(workDateParts(kst(2026, 9, 30, 23, 59)).yearMonth, '2026-09');
    });
  });

  // ───────────────────────────────────────────────────────────
  group('P3-2x 서버 배선 — 다섯 소비자 (§13 F·G·H)', () {
    late String wage;
    setUpAll(() {
      wage = _fn(code, 'export const callableCalculateAndConfirmWage');
    });

    test('P3-20 근태에서 canonical 값을 파생한다', () {
      expect(code.contains('function srvWorkDateParts('), isTrue);
      final h = _after(code, 'function srvWorkDateParts(', 600);
      expect(h.contains('SRV_KST_MS'), isTrue,
          reason: '기존 KST 보정을 쓴다 — 새 파싱 규칙을 만들지 않는다');
      expect(h.contains('getUTCFullYear()'), isTrue);
      expect(wage.contains('srvWorkDateParts(canonWorkTs)'), isTrue);
    });

    test('P3-21 근무일이 없으면 확정하지 않는다 (fail closed)', () {
      expect(wage.contains('근태에 근무일이 없어 급여를 확정할 수 없습니다'), isTrue);
    });

    test('P3-22 F 저장되는 yearMonth 가 근태 파생이다', () {
      expect(wage.contains('yearMonth: canon.yearMonth'), isTrue);
      expect(wage.contains('yearMonth: d.yearMonth'), isFalse,
          reason: '클라이언트 값이 저장되면 같은 근무가 다른 달의 돈이 된다');
    });

    test('P3-23 최저임금 연도가 근태 파생이다', () {
      expect(wage.contains('const workYear2 = canon.year;'), isTrue);
      expect(wage.contains("d.workDate.substring(0, 4)"), isFalse);
    });

    test('P3-24 G 지급일정 입력 날짜가 근태 파생이다', () {
      expect(wage.contains('srvResolveEffectivePaySchedule('), isTrue);
      final i = wage.indexOf('srvResolveEffectivePaySchedule(');
      final slice = wage.substring(i, i + 140);
      expect(slice.contains('canon.date'), isTrue);
      expect(slice.contains('d.workDate'), isFalse);
    });

    test('P3-25 월 공제 모집단이 근태 파생이다', () {
      expect(wage.contains('srvGetMonthlyStatsTx('), isTrue);
      final i = wage.indexOf('srvGetMonthlyStatsTx(');
      final slice = wage.substring(i, i + 160);
      expect(slice.contains('canon.yearMonth'), isTrue);
      expect(slice.contains('d.yearMonth'), isFalse,
          reason: '다른 달 공제 모집단에 들어가면 안 된다');
    });

    test('P3-26 H 안내 문구의 근무일이 근태 파생이다', () {
      expect(wage.contains('workDate: canon.date'), isTrue);
      expect(wage.contains('workDate: d.workDate'), isFalse,
          reason: '사용자에게 다른 날짜를 말하지 않는다');
    });

    test('P3-27 클라이언트 날짜는 권위 구간에 남아 있지 않다', () {
      // 불일치 기록 이후가 계산·저장·집계·안내 구간이다.
      //   거기에 d.workDate / d.yearMonth 가 하나라도 있으면 권위로 쓰인 것이다.
      expect(wage.contains('클라이언트 날짜가 근태와 다르다'), isTrue,
          reason: '불일치는 조용히 넘기지 않고 기록한다');
      // 경고 문자열 자체가 클라이언트 값을 찍으므로, 그 블록의 끝을 기준점으로.
      final mark = wage.indexOf(r'canonical=${canon.date}/${canon.yearMonth}');
      expect(mark, greaterThan(-1), reason: '불일치 로그의 끝을 찾지 못했다');
      final afterCanon = wage.substring(mark);
      final leaks = RegExp(r'd\.(workDate|yearMonth)')
          .allMatches(afterCanon)
          .map((m) => m.group(0))
          .toList();
      expect(leaks, isEmpty, reason: '권위 구간에 남았다: $leaks');
      // 앞 구간에 남은 것들은 전부 형식 검증·경고 문자열이다.
      final before = wage.substring(0, mark);
      expect(before.contains('workDate는 YYYY-MM-DD 형식이어야 합니다'), isTrue);
    });

    test('P3-28 §18 구버전 호환 — 파라미터를 지우지 않았다', () {
      expect(wage.contains('workDate: string;'), isTrue);
      expect(wage.contains('yearMonth: string;'), isTrue);
      expect(wage.contains('workDate는 YYYY-MM-DD 형식이어야 합니다'), isTrue,
          reason: '형식 검증 계약은 그대로 둔다');
    });
  });

  // ───────────────────────────────────────────────────────────
  group('P3-3x 미이체 건수 권한 (§14)', () {
    const biz = 'BIZ_A';
    const perms = <String, Map<String, bool>>{
      'u_wage': <String, bool>{'canManageWage': true},
      'u_nowage': <String, bool>{'canManageWorkers': true},
    };
    String? check(String uid, String role, List<String> subs) => wageAuthority(
          uid: uid, role: role, ownerId: 'u_owner',
          adminIds: const ['u_owner'], subAdminBusinessIds: subs,
          targetBiz: biz, memberPerms: perms,
        );

    test('A owner → ALLOW', () {
      expect(check('u_owner', 'BUSINESS_ADMIN', const []), isNull);
    });
    test('B wage SUB_ADMIN → ALLOW', () {
      expect(check('u_wage', 'USER', const [biz]), isNull);
    });
    test('C wage 없는 SUB_ADMIN → DENY', () {
      expect(check('u_nowage', 'USER', const [biz]), 'no-canManageWage');
    });
    test('D 다른 사업장 → DENY', () {
      expect(check('u_wage', 'USER', const ['BIZ_B']), 'not-member');
    });
    test('E 근로자 → DENY', () {
      expect(check('u_worker', 'USER', const []), 'not-member');
    });
    test('F SUPER_ADMIN → ALLOW', () {
      expect(check('u_super', 'SUPER_ADMIN', const []), isNull);
    });
    test('E2 소속이 회수되면 권한 기록이 남아도 DENY', () {
      expect(
        wageAuthority(
          uid: 'u_wage', role: 'USER', ownerId: 'u_owner',
          adminIds: const ['u_owner'], subAdminBusinessIds: const [],
          targetBiz: biz, memberPerms: perms,
        ),
        'not-member',
      );
    });

    test('P3-30 count 문이 canonical wage 자격을 쓴다', () {
      final f = _fn(code, 'export const callableGetNotTransferredCount');
      expect(f.contains('srvAssertWageAuthority('), isTrue);
      expect(RegExp(r'\bawait assertBizAdmin\(').hasMatch(f), isFalse,
          reason: 'membership-only 판정이 남아 있으면 안 된다');
      // 새 helper 를 복제하지 않았다.
      expect(code.contains('function srvAssertNotTransferredAuthority'),
          isFalse);
    });

    test('P3-31 G·H count 의미·모집단은 그대로다', () {
      final f = _fn(code, 'export const callableGetNotTransferredCount');
      expect(f.contains('srvPayableForTransfer('), isTrue,
          reason: '.6-P1 payable population 불변');
      expect(f.contains('return {count}'), isTrue,
          reason: '단위는 attendance 문서 수');
      expect(f.contains('count: 0'), isFalse,
          reason: '거부를 0으로 돌려주지 않는다');
      // 권한 판정이 쿼리보다 앞이다 — 거부된 호출자는 세지도 않는다.
      final gate = f.indexOf('srvAssertWageAuthority(');
      final query = f.indexOf('.collection("attendance")');
      expect(gate, greaterThan(-1));
      expect(query, greaterThan(gate));
    });

    test('P3-32 D-1 이 만든 자격 판정을 되돌리지 않았다', () {
      // payroll summary 두 문도 같은 helper 를 계속 쓴다.
      for (final owner in <String>[
        'export const callableGetPayrollSummaries',
        'export const callableRepairPayrollSummaries',
      ]) {
        expect(_fn(code, owner).contains('srvAssertWageAuthority('), isTrue,
            reason: owner);
      }
    });
  });
}
