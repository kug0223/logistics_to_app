import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// ═══════════════════════════════════════════════════════════════
// AH-V2-05B.2 UNPAID-WAGE-MISSING-DUE-DATE-CANONICAL-FIX
//
// '지급일 확인 필요'는 지급할 임금이 있는데 지급예정일이 없는 경우여야 한다.
//
// 노쇼·결근은 지급할 임금이 없는 종결 상태인데
//   status + finalWage:0 + wageStatus:"confirmed", paymentDueDate 없음
// 으로 저장돼 이 숫자에 영구히 남아 있었다.
//
// 확실한 false positive만 제거한다 — 분류 불가 문서는 계속 포함한다.
// ═══════════════════════════════════════════════════════════════

const _cfPath = 'functions/src/index.ts';

String _src(String p) => File(p).readAsStringSync();
String _codeOf(String b) =>
    b.split('\n').where((l) => !l.trimLeft().startsWith('//')).join('\n');

String _fnBody(String source, String signature) {
  final start = source.indexOf(signature);
  expect(start, isNot(-1), reason: '$signature 를 찾지 못함');
  final end = source.indexOf('\n}', start);
  expect(end, isNot(-1));
  return source.substring(start, end + 2);
}

// ── 서버 분류 재현 ────────────────────────────────────────────
/// attendance 문서 한 건 (서버가 select하는 필드만)
class _Att {
  final String userId;
  final String wageStatus;
  final String? status;
  final int? finalWage;
  final DateTime? paymentDueDate;
  const _Att({
    required this.userId,
    this.wageStatus = 'confirmed',
    this.status,
    this.finalWage,
    this.paymentDueDate,
  });
}

class _Result {
  final int count;
  final int overdue;
  final int missingDueDate;
  const _Result(this.count, this.overdue, this.missingDueDate);
  @override
  String toString() => 'count=$count overdue=$overdue missing=$missingDueDate';
}

/// srvHomeUnpaidWage(bizId, todayMs) 재현.
/// 쿼리는 wageStatus == "confirmed"만 싣는다.
_Result _srvUnpaidWage(List<_Att> docs, DateTime todayKstMidnight) {
  final todayMs = todayKstMidnight.millisecondsSinceEpoch;
  final groups = <String, int>{};
  final missingUserIds = <String>{};

  for (final d in docs.where((a) => a.wageStatus == 'confirmed')) {
    final pd = d.paymentDueDate;
    if (pd == null) {
      // [AH-V2-05B.2] terminal non-payable 제외
      final nonPayable =
          (d.status == 'NO_SHOW' || d.status == 'absent') &&
              (d.finalWage ?? 0) == 0;
      if (nonPayable) continue;
      missingUserIds.add(d.userId);
      continue;
    }
    final key = '${d.userId}_${pd.toUtc().toIso8601String().substring(0, 10)}';
    groups.putIfAbsent(key, () => pd.millisecondsSinceEpoch);
  }

  var overdue = 0;
  for (final ms in groups.values) {
    if (ms < todayMs) overdue++;
  }
  return _Result(groups.length, overdue, missingUserIds.length);
}

/// KST 달력일의 자정에 해당하는 UTC instant
DateTime _kstDay(int y, int m, int d) =>
    DateTime.utc(y, m, d).subtract(const Duration(hours: 9));

void main() {
  late String cf;

  setUpAll(() => cf = _src(_cfPath));

  final today = _kstDay(2026, 9, 13);
  final yesterday = _kstDay(2026, 9, 12);
  final tomorrow = _kstDay(2026, 9, 14);

  // ───────────────────────────────────────────────────────────
  // §15~18 분류
  // ───────────────────────────────────────────────────────────
  group('WAGE-MISSING-01/02 노쇼·결근은 제외', () {
    test('01 NO_SHOW + finalWage 0 → missing 미포함', () {
      final r = _srvUnpaidWage(
          [const _Att(userId: 'u1', status: 'NO_SHOW', finalWage: 0)], today);
      expect(r.missingDueDate, 0);
      expect(r.count, 0);
      expect(r.overdue, 0);
    });

    test('02 absent + finalWage 0 → missing 미포함', () {
      final r = _srvUnpaidWage(
          [const _Att(userId: 'u1', status: 'absent', finalWage: 0)], today);
      expect(r.missingDueDate, 0);
    });

    test('자동노쇼(단기·장기)·자동결근·수동노쇼 다섯 경로 모두 같은 모양', () {
      // 다섯 writer 전부 status + finalWage:0 + wageStatus:confirmed, dueDate 없음
      final docs = [
        const _Att(userId: 'u1', status: 'NO_SHOW', finalWage: 0), // 자동노쇼 단기
        const _Att(userId: 'u2', status: 'NO_SHOW', finalWage: 0), // 자동노쇼 장기
        const _Att(userId: 'u3', status: 'absent', finalWage: 0), // 자동결근
        const _Att(userId: 'u4', status: 'NO_SHOW', finalWage: 0), // 수동노쇼 update
        const _Att(userId: 'u5', status: 'NO_SHOW', finalWage: 0), // 수동노쇼 create
      ];
      expect(_srvUnpaidWage(docs, today).missingDueDate, 0);
    });

    test('누적돼도 0 — 처리할 필요 없는 상태는 task count를 만들지 않는다', () {
      final docs = List.generate(
          50, (i) => _Att(userId: 'u$i', status: 'NO_SHOW', finalWage: 0));
      expect(_srvUnpaidWage(docs, today).missingDueDate, 0);
    });
  });

  group('WAGE-MISSING-03/04 진짜 누락과 분류 불가는 유지', () {
    test('03 지급 대상인데 dueDate 없음 → missing 포함', () {
      final r = _srvUnpaidWage(
          [const _Att(userId: 'u1', status: 'present', finalWage: 90000)],
          today);
      expect(r.missingDueDate, 1);
    });

    test('04 status null/unknown → 숨기지 않고 포함', () {
      expect(_srvUnpaidWage([const _Att(userId: 'u1')], today).missingDueDate, 1);
      expect(
          _srvUnpaidWage([const _Att(userId: 'u2', status: 'unknown_legacy')],
                  today)
              .missingDueDate,
          1);
    });

    test('§4 확실한 false positive만 제거 — NO_SHOW인데 급여가 있으면 남긴다', () {
      final r = _srvUnpaidWage(
          [const _Att(userId: 'u1', status: 'NO_SHOW', finalWage: 50000)],
          today);
      expect(r.missingDueDate, 1,
          reason: '이상 데이터를 숨기면 실제 미지급을 놓친다');
    });

    test('finalWage 필드 자체가 없어도 남긴다 (status만으로 단정 금지)', () {
      final r = _srvUnpaidWage(
          [const _Att(userId: 'u1', status: 'late')], today);
      expect(r.missingDueDate, 1);
    });

    test('unique userId 단위 — 한 사람이 여러 건이어도 1', () {
      final docs = [
        const _Att(userId: 'u1', status: 'present', finalWage: 10000),
        const _Att(userId: 'u1', status: 'present', finalWage: 20000),
        const _Att(userId: 'u2', status: 'present', finalWage: 30000),
      ];
      expect(_srvUnpaidWage(docs, today).missingDueDate, 2);
    });
  });

  // ───────────────────────────────────────────────────────────
  // §5 / §6 count · overdue 불변
  // ───────────────────────────────────────────────────────────
  group('WAGE-MISSING-05/06/07 count·overdue 계약 불변', () {
    test('05 미래 지급예정일 → count만', () {
      final r = _srvUnpaidWage(
          [_Att(userId: 'u1', paymentDueDate: tomorrow, finalWage: 90000)],
          today);
      expect(r.count, 1);
      expect(r.overdue, 0);
      expect(r.missingDueDate, 0);
    });

    test('06 지난 지급예정일 → count + overdue', () {
      final r = _srvUnpaidWage(
          [_Att(userId: 'u1', paymentDueDate: yesterday, finalWage: 90000)],
          today);
      expect(r.count, 1);
      expect(r.overdue, 1);
      expect(r.missingDueDate, 0);
    });

    test('당일 지급예정일은 연체 아님 (< 오늘 자정)', () {
      final r = _srvUnpaidWage(
          [_Att(userId: 'u1', paymentDueDate: today, finalWage: 90000)], today);
      expect(r.overdue, 0);
    });

    test('07 transferred → 셋 다 제외', () {
      final docs = [
        _Att(userId: 'u1', wageStatus: 'transferred', paymentDueDate: yesterday),
        const _Att(userId: 'u2', wageStatus: 'transferred', status: 'NO_SHOW'),
      ];
      final r = _srvUnpaidWage(docs, today);
      expect(r.count, 0);
      expect(r.overdue, 0);
      expect(r.missingDueDate, 0);
    });

    test('count는 (userId × 지급일) 그룹 단위', () {
      final docs = [
        _Att(userId: 'u1', paymentDueDate: tomorrow, finalWage: 1),
        _Att(userId: 'u1', paymentDueDate: tomorrow, finalWage: 2), // 같은 그룹
        _Att(userId: 'u1', paymentDueDate: yesterday, finalWage: 3), // 다른 지급일
        _Att(userId: 'u2', paymentDueDate: tomorrow, finalWage: 4),
      ];
      final r = _srvUnpaidWage(docs, today);
      expect(r.count, 3);
      expect(r.overdue, 1);
    });

    test('노쇼·결근은 애초에 dueDate가 없어 count/overdue에 영향이 없다', () {
      final base = [
        _Att(userId: 'u1', paymentDueDate: yesterday, finalWage: 90000),
        _Att(userId: 'u2', paymentDueDate: tomorrow, finalWage: 80000),
      ];
      final before = _srvUnpaidWage(base, today);
      final after = _srvUnpaidWage([
        ...base,
        const _Att(userId: 'u3', status: 'NO_SHOW', finalWage: 0),
        const _Att(userId: 'u4', status: 'absent', finalWage: 0),
      ], today);
      expect(after.count, before.count);
      expect(after.overdue, before.overdue);
    });
  });

  // ───────────────────────────────────────────────────────────
  // §22 혼합 시나리오
  // ───────────────────────────────────────────────────────────
  group('§22 A센터 혼합 시나리오', () {
    test('정상 3 + 연체 1 + 노쇼 2 + 진짜 누락 1', () {
      final docs = [
        _Att(userId: 'a', paymentDueDate: tomorrow, finalWage: 10000),
        _Att(userId: 'b', paymentDueDate: tomorrow, finalWage: 20000),
        _Att(userId: 'c', paymentDueDate: tomorrow, finalWage: 30000),
        _Att(userId: 'd', paymentDueDate: yesterday, finalWage: 40000), // 연체
        const _Att(userId: 'e', status: 'NO_SHOW', finalWage: 0),
        const _Att(userId: 'f', status: 'NO_SHOW', finalWage: 0),
        const _Att(userId: 'g', status: 'present', finalWage: 50000), // 진짜 누락
      ];
      final r = _srvUnpaidWage(docs, today);
      expect(r.count, 4);
      expect(r.overdue, 1);
      expect(r.missingDueDate, 1, reason: '노쇼 2명은 제외');
    });

    test('Home 총계가 노쇼로 부풀지 않는다', () {
      // wageTotal = count + missingDueDateCount (클라이언트 산식, 변경 없음)
      final withNoShow = [
        _Att(userId: 'a', paymentDueDate: tomorrow, finalWage: 10000),
        const _Att(userId: 'b', status: 'NO_SHOW', finalWage: 0),
        const _Att(userId: 'c', status: 'absent', finalWage: 0),
      ];
      final r = _srvUnpaidWage(withNoShow, today);
      expect(r.count + r.missingDueDate, 1, reason: '실제 이체 대기 1건만');
    });
  });

  // ───────────────────────────────────────────────────────────
  // 서버 배선
  // ───────────────────────────────────────────────────────────
  group('서버 구현 배선', () {
    test('terminal non-payable predicate가 존재한다', () {
      // [.6-P1] 판정이 canonical helper 로 옮겨갔다. Home 이 지급 대상을
      //   직접 가린다는 사실은 그대로이고, 이제 이체목록·배지·카운트가
      //   같은 식을 쓴다.
      final fn = _codeOf(_fnBody(cf, 'async function srvHomeUnpaidWage('));
      expect(fn.contains('srvPayableForTransfer('), isTrue);
      expect(fn.contains(')) continue;'), isTrue);
    });

    test('§3 finalWage만으로 제외하지 않는다', () {
      // 제외 조건은 status AND finalWage 둘 다를 요구한다 — 판정 정의를 본다.
      final p = _codeOf(_fnBody(cf, 'function srvIsNonPayableZero('));
      expect(p.contains('=== 0'), isTrue);
      expect(p.contains('"NO_SHOW"'), isTrue);
      expect(p.contains('"absent"'), isTrue);
      // status를 보지 않고 finalWage만으로 거르는 분기는 없다
      final fn = _codeOf(_fnBody(cf, 'async function srvHomeUnpaidWage('));
      expect(fn.contains('if (fw === 0) continue;'), isFalse);
    });

    test('§13 projection만 넓혔고 쿼리는 그대로다', () {
      final fn = _codeOf(_fnBody(cf, 'async function srvHomeUnpaidWage('));
      expect(
        fn.contains('.select("userId", "paymentDueDate", "wageStatus", '
            '"status", "finalWage")'),
        isTrue,
      );
      expect('db.collection('.allMatches(fn).length, 1, reason: '쿼리 1개 유지');
      expect(fn.contains('.where("businessId", "==", bizId)'), isTrue);
      expect(fn.contains('.where("wageStatus", "==", "confirmed")'), isTrue);
    });

    test('§5 count 계약 불변', () {
      final fn = _codeOf(_fnBody(cf, 'async function srvHomeUnpaidWage('));
      expect(fn.contains(r'const key = `${uid}_${srvHomeDateStr(pdTs.toDate())}`;'),
          isTrue);
      expect(fn.contains('if (!groups.has(key)) groups.set(key, pdTs.toMillis());'),
          isTrue);
      expect(fn.contains('count: groups.size'), isTrue);
    });

    test('§6 overdue 계약 불변', () {
      final fn = _codeOf(_fnBody(cf, 'async function srvHomeUnpaidWage('));
      expect(fn.contains('if (ms < todayMs) overdue++;'), isTrue);
    });

    test('§8 aggregate와 byBusiness가 같은 결과를 쓴다', () {
      expect(cf.contains('unpaidMissing += r.unpaidWage.missingDueDate;'), isTrue);
      expect(
        cf.contains('missingDueDateCount: r.unpaidWage.missingDueDate,'),
        isTrue,
      );
    });

    test('§11 writer를 건드리지 않았다', () {
      // 다섯 non-payable writer가 그대로 있어야 한다
      expect('wageStatus: "confirmed"'.allMatches(cf).length >= 5, isTrue);
      expect(cf.contains('autoNoShowAt:  admin.firestore.FieldValue.serverTimestamp()'),
          isTrue);
      expect(cf.contains('autoAbsentAt: admin.firestore.FieldValue.serverTimestamp()'),
          isTrue);
      // 급여 확정 prevalidation 유지
      expect(cf.contains('급여 지급일을 확인할 수 없습니다.'), isTrue);
      expect(cf.contains('srvCalculatePaymentDueDate(pvPst, pvPsd, pvWorkDate) === null'),
          isTrue);
    });

    test('같은 판정을 쓰는 기존 트리거와 조건이 일치한다', () {
      // review_request 트리거도 absent/NO_SHOW를 '실제 근무 없음'으로 제외한다.
      // [SYSTEM-INTEGRATION-R0.2] 그 제외 목록이 trigger 안의 인라인 조건에서
      //   canonical helper로 올라갔다 — scheduler가 같은 판정을 쓰게 하려면
      //   두 곳에 복제하지 않고 한 곳에 두어야 했다. 판정 자체는 같다.
      expect(
        cf.contains(
            'const ACTUAL_WORK_STATUSES = ["present", "late", "early_leave"]'),
        isTrue,
        reason: '새 정책이 아니라 기존 canonical 판정의 재사용',
      );
      expect(
        cf.contains('srvIsActualFinalizedWork(after.status, after.wageStatus)'),
        isTrue,
      );
    });

    test('§9 클라이언트 산식을 건드리지 않았다', () {
      final home = _src(
          'lib/screens/business_admin/business_admin_home_screen.dart');
      expect(
        home.contains(
            'final wageTotal = (wage?.count ?? 0) + (wage?.missingDueDateCount ?? 0);'),
        isTrue,
      );
      expect(home.contains("secondaryLabel: '지급일 확인 필요'"), isTrue);
    });

    test('§10 destination 미변경', () {
      final home = _src(
          'lib/screens/business_admin/business_admin_home_screen.dart');
      expect(home.contains('showAllOutstanding: true'), isTrue);
      expect(home.contains("tab: 0, sheetTitle: '이체 대기'"), isTrue);
    });

    test('AH-V2-04C.1 approval overdue 계약이 그대로다', () {
      expect(cf.contains('if (wdTs && wdTs.toMillis() < todayMs) overdue++;'), isTrue);
      expect(cf.contains('.select("workDate")'), isTrue);
    });
  });
}
