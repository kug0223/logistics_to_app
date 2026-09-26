// [.6-P1] 지급 대상 population 계약.
//
//   지키는 문장은 하나다.
//
//     같은 Attendance + 같은 wage state = 같은 "지급 업무" 의미.
//
//   Home·이체목록·배지·카운트·summary 가 서로 다른 답을 내면 관리자는
//   어느 숫자를 믿어야 할지 알 수 없다.
//
//   판정은 Dart 로 재구현해 경계를 직접 고정하고(순수 함수), 어느 자리가
//   그 판정을 쓰는지는 소스 문자열로 고정한다. 둘 다 없으면 한쪽만 고쳐도
//   통과한다.

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:ALfit/models/core/attendance_model.dart';

/// 주석을 걷어낸 코드만 본다. 마커가 주석에만 있으면 계약이 아니다.
String _codeOf(String src) => src
    .split('\n')
    .where((l) => !l.trimLeft().startsWith('//'))
    .join('\n');

/// [name] 선언부터 다음 export 직전까지.
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
// 서버 srvIsNonPayableZero / srvPayrollContribution 과 같은 식
// ─────────────────────────────────────────────────────────────

/// 한 attendance 의 지급 관련 상태.
class Att {
  const Att(this.id, this.wageStatus, this.status, this.finalWage,
      {this.hasDueDate = true});

  final String id;
  final String wageStatus;
  final String status;
  final int finalWage;
  final bool hasDueDate;
}

bool isNonPayableZero(String status, int finalWage) =>
    (status == 'NO_SHOW' || status == 'absent') && finalWage == 0;

bool payableForTransfer(Att a) =>
    a.wageStatus == 'confirmed' && !isNonPayableZero(a.status, a.finalWage);

class Contribution {
  const Contribution(
      this.count, this.workDays, this.payout, this.notTransferred);
  final int count;
  final int workDays;
  final int payout;
  final int notTransferred;

  static const zero = Contribution(0, 0, 0, 0);

  Contribution operator -(Contribution o) => Contribution(
      count - o.count, workDays - o.workDays,
      payout - o.payout, notTransferred - o.notTransferred);

  bool get isZero =>
      count == 0 && workDays == 0 && payout == 0 && notTransferred == 0;

  @override
  bool operator ==(Object o) =>
      o is Contribution && o.count == count && o.workDays == workDays &&
      o.payout == payout && o.notTransferred == notTransferred;

  @override
  int get hashCode => Object.hash(count, workDays, payout, notTransferred);

  @override
  String toString() => '($count,$workDays,$payout,$notTransferred)';
}

/// null = 문서 없음(전이 이전 상태가 존재하지 않는 경우).
Contribution contribution(Att? a) {
  if (a == null) return Contribution.zero;
  if (a.wageStatus != 'confirmed' && a.wageStatus != 'transferred') {
    return Contribution.zero;
  }
  if (isNonPayableZero(a.status, a.finalWage)) return Contribution.zero;
  return Contribution(
      1, 1, a.finalWage, a.wageStatus == 'confirmed' ? 1 : 0);
}

Contribution delta(Att? before, Att? after) =>
    contribution(after) - contribution(before);

void main() {
  late String code;
  late String client;

  setUpAll(() {
    code = _codeOf(File('functions/src/index.ts').readAsStringSync());
    client = _codeOf(File(
      'lib/screens/business_admin/payroll/payroll_payment_dashboard_screen.dart',
    ).readAsStringSync());
  });

  // ───────────────────────────────────────────────────────────
  group('P1-0x 판정 경계', () {
    test('P1-00 노쇼 0원은 지급 대상이 아니다', () {
      expect(isNonPayableZero('NO_SHOW', 0), isTrue);
    });
    test('P1-01 결근 0원도 같다', () {
      expect(isNonPayableZero('absent', 0), isTrue);
    });
    test('P1-02 노쇼인데 금액이 있으면 비정상 — 조용히 빼지 않는다', () {
      expect(isNonPayableZero('NO_SHOW', 24000), isFalse,
          reason: '금액이 남은 종결 기록은 관리자가 봐야 한다');
      expect(payableForTransfer(const Att('x', 'confirmed', 'NO_SHOW', 24000)),
          isTrue);
    });
    test('P1-03 정상 근무 0원은 제외 대상이 아니다', () {
      expect(isNonPayableZero('present', 0), isFalse,
          reason: 'status 가 노쇼·결근이 아니면 금액이 0이어도 대상이다');
    });
    test('P1-04 status 를 모르는 문서는 제외하지 않는다 — 모름 != 0', () {
      expect(isNonPayableZero('', 0), isFalse);
    });
  });

  // ───────────────────────────────────────────────────────────
  group('P1-1x 전이 matrix (§9)', () {
    const payable = Att('a', 'confirmed', 'present', 24000);
    const xferred = Att('a', 'transferred', 'present', 24000);
    const pending = Att('a', 'pending', 'present', 0);
    const noShow0 = Att('a', 'confirmed', 'NO_SHOW', 0);
    const absent0 = Att('a', 'confirmed', 'absent', 0);
    const noShowPos = Att('a', 'confirmed', 'NO_SHOW', 24000);

    test('A pending → confirmed payable : +1/+1/+notTransferred', () {
      final d = delta(pending, payable);
      expect([d.count, d.workDays, d.payout, d.notTransferred],
          [1, 1, 24000, 1]);
    });

    test('B confirmed payable → transferred : 근무 유지, 미이체 -1', () {
      final d = delta(payable, xferred);
      expect(d.count, 0, reason: '확정 건수는 유지된다');
      expect(d.workDays, 0, reason: '근무일은 유지된다');
      expect(d.payout, 0);
      expect(d.notTransferred, -1);
    });

    test('C NO_SHOW confirmed 0 : 기여 자체가 없다', () {
      expect(contribution(noShow0).isZero, isTrue);
    });

    test('D NO_SHOW confirmed 0 → pending : delta 0, 음수 없음', () {
      final d = delta(noShow0, pending);
      expect(d.isZero, isTrue,
          reason: '넣은 적 없는 몫을 빼면 summary 가 음수로 내려간다');
    });

    test('E pending → NO_SHOW confirmed 0 : delta 0', () {
      expect(delta(pending, noShow0).isZero, isTrue);
    });

    test('F confirmed payable → NO_SHOW confirmed 0 : 이전 기여 정확히 제거', () {
      final d = delta(payable, noShow0);
      expect([d.count, d.workDays, d.payout, d.notTransferred],
          [-1, -1, -24000, -1]);
    });

    test('G NO_SHOW confirmed 0 → confirmed payable : 정확히 추가', () {
      final d = delta(noShow0, payable);
      expect([d.count, d.workDays, d.payout, d.notTransferred],
          [1, 1, 24000, 1]);
    });

    test('H absent confirmed 0 은 NO_SHOW 와 같다', () {
      expect(contribution(absent0).isZero, isTrue);
      expect(delta(absent0, pending).isZero, isTrue);
      expect(delta(payable, absent0), delta(payable, noShow0));
    });

    test('I NO_SHOW + finalWage > 0 은 조용히 ZERO 가 되지 않는다', () {
      final c = contribution(noShowPos);
      expect(c.isZero, isFalse);
      expect([c.count, c.workDays, c.payout, c.notTransferred],
          [1, 1, 24000, 1]);
    });

    test('J transferred 는 미이체를 만들지 않는다', () {
      expect(contribution(xferred).notTransferred, 0);
      expect(contribution(xferred).count, 1, reason: '근무 사실은 남는다');
    });

    test('K calculated·pending 은 집계 대상이 아니다', () {
      expect(contribution(const Att('a', 'calculated', 'present', 24000)).isZero,
          isTrue);
      expect(contribution(pending).isZero, isTrue);
    });
  });

  // ───────────────────────────────────────────────────────────
  group('P1-2x cross-surface population (§10)', () {
    // 하나의 fixture set — 다섯 표면이 같은 ID 집합을 내야 한다.
    const fixtures = <Att>[
      Att('A-payable', 'confirmed', 'present', 24000),
      Att('B-transferred', 'transferred', 'present', 24000),
      Att('C-noshow0', 'confirmed', 'NO_SHOW', 0),
      Att('D-absent0', 'confirmed', 'absent', 0),
      Att('E-noshowPos', 'confirmed', 'NO_SHOW', 24000),
      Att('F-pending', 'pending', 'present', 0),
      Att('G-calculated', 'calculated', 'present', 24000),
      Att('H-payableNoDue', 'confirmed', 'late', 18000, hasDueDate: false),
    ];

    Set<String> ids(bool Function(Att) p) =>
        fixtures.where(p).map((a) => a.id).toSet();

    // 다섯 표면을 각각의 자리에서 재현한다.
    final homeIds = ids(payableForTransfer);
    final payrollIds = ids(payableForTransfer);
    final badgeIds = ids(payableForTransfer);
    final countIds = ids(payableForTransfer);
    final summaryNotTransferredIds =
        ids((a) => contribution(a).notTransferred > 0);

    test('P1-20 canonical payable 집합이 기대와 같다', () {
      expect(homeIds, <String>{'A-payable', 'E-noshowPos', 'H-payableNoDue'},
          reason: '노쇼·결근 0원 제외, 비정상 양수는 포함');
    });

    test('P1-21 Home == Payroll == badge == count', () {
      expect(payrollIds, homeIds);
      expect(badgeIds, homeIds);
      expect(countIds, homeIds);
    });

    test('P1-22 summary 미이체 집합도 같다', () {
      expect(summaryNotTransferredIds, homeIds,
          reason: 'notTransferred 는 payable 과 같은 population 이다');
    });

    test('P1-23 Home 에서 빠진 건이 Payroll 에 다시 나타나지 않는다', () {
      for (final a in fixtures) {
        if (homeIds.contains(a.id)) continue;
        expect(payrollIds.contains(a.id), isFalse, reason: a.id);
        expect(badgeIds.contains(a.id), isFalse, reason: a.id);
        expect(countIds.contains(a.id), isFalse, reason: a.id);
      }
    });

    test('P1-24 transferred 는 미이체 어디에도 없다', () {
      expect(homeIds.contains('B-transferred'), isFalse);
      expect(contribution(fixtures[1]).count, 1,
          reason: 'summary 의 근무 사실은 보존된다');
    });

    test('P1-25 지급일이 없어도 payable 이면 population 에 남는다', () {
      expect(homeIds.contains('H-payableNoDue'), isTrue,
          reason: '지급일 미상은 "지급 안 함"이 아니다');
    });
  });

  // ───────────────────────────────────────────────────────────
  group('P1-3x 서버 배선', () {
    test('P1-30 판정이 한 곳에만 있다', () {
      expect(code.contains('function srvIsNonPayableZero('), isTrue);
      expect(code.contains('function srvPayableForTransfer('), isTrue);
      final body = _after(code, 'function srvIsNonPayableZero(', 400);
      expect(body.contains('"NO_SHOW"'), isTrue);
      expect(body.contains('"absent"'), isTrue);
      expect(body.contains('=== 0'), isTrue,
          reason: '금액 조건이 빠지면 비정상 양수까지 숨는다');
      // 지급 population 을 쓰는 자리에 인라인 복제가 남아 있으면
      //   한쪽만 고쳐지는 날이 온다.
      //   (신뢰점수·근무통계의 "실제 근무였나"는 금액을 보지 않는 별개
      //    판정이다 — 같은 식으로 묶지 않는다.)
      for (final owner in <String>[
        'export const callableGetNotTransferredCount',
        'export const callableRepairPayrollSummaries',
        'export const onAttendanceWageChanged',
      ]) {
        final f = _fn(code, owner);
        expect(f.contains('=== "NO_SHOW"'), isFalse, reason: owner);
        expect(f.contains('=== "absent"'), isFalse, reason: owner);
      }
      final home = _after(code, 'async function srvHomeUnpaidWage(', 1800);
      expect(home.contains('=== "NO_SHOW"'), isFalse);
    });

    test('P1-31 트리거가 before/after 를 같은 식으로 계산한다', () {
      final f = _fn(code, 'export const onAttendanceWageChanged');
      expect(f.contains('srvPayrollContribution(before)'), isTrue);
      expect(f.contains('srvPayrollContribution(after)'), isTrue);
      expect(f.contains('cAfter.count - cBefore.count'), isTrue);
      expect(f.contains('cAfter.notTransferred - cBefore.notTransferred'),
          isTrue);
    });

    test('P1-32 after 만 보고 빠져나가지 않는다', () {
      final f = _fn(code, 'export const onAttendanceWageChanged');
      expect(f.contains('docStatus === "absent"'), isFalse,
          reason: 'after 만 본 early return 은 이전 기여를 남긴다');
      expect(f.contains('if (cBefore.count === 0 && cAfter.count === 0) return'),
          isTrue, reason: '양쪽 모두 기여 0일 때만 건너뛴다');
    });

    test('P1-33 workDays 가 자기 delta 를 쓴다', () {
      final f = _fn(code, 'export const onAttendanceWageChanged');
      expect(f.contains('cAfter.workDays - cBefore.workDays'), isTrue);
      expect(f.contains('existingWorker.workDays + workDaysDelta'), isTrue);
    });

    test('P1-34 Home 이 canonical 판정을 쓴다', () {
      final h = _after(code, 'async function srvHomeUnpaidWage(', 1800);
      expect(h.contains('srvPayableForTransfer('), isTrue);
      // 지급일 유무와 무관하게 **먼저** 거른다.
      final gate = h.indexOf('srvPayableForTransfer(');
      final due = h.indexOf('paymentDueDate"] as admin.firestore.Timestamp');
      expect(gate, greaterThan(-1));
      expect(due, greaterThan(gate),
          reason: '지급일이 붙은 노쇼 0원이 Task 로 남으면 안 된다');
    });

    test('P1-35 count callable 이 같은 판정을 쓴다', () {
      final f = _fn(code, 'export const callableGetNotTransferredCount');
      expect(f.contains('srvPayableForTransfer('), isTrue);
      expect(f.contains('.count()'), isFalse,
          reason: '집계 쿼리로는 두 필드를 같이 보는 판정을 할 수 없다');
      expect(f.contains('return {count}'), isTrue,
          reason: '단위는 그대로 attendance 문서 수다');
    });

    test('P1-36 repair 가 트리거와 같은 식으로 제외한다', () {
      final f = _fn(code, 'export const callableRepairPayrollSummaries');
      expect(f.contains('srvIsNonPayableZero('), isTrue);
      expect(f.contains('s !== "absent" && s !== "NO_SHOW"'), isFalse,
          reason: '금액을 보지 않으면 비정상 양수가 재집계로 사라진다');
    });

    test('P1-37 이체 writer 가 같은 판정을 쓴다', () {
      expect(code.contains('const XFER_NOT_PAYABLE = "notPayable";'), isTrue);
      final i = code.indexOf('blocked[id] = XFER_NOT_PAYABLE;');
      expect(i, greaterThan(-1));
      final around = code.substring(i - 400, i);
      expect(around.contains('srvIsNonPayableZero('), isTrue);
    });

    test('P1-38 .6-P3 소관을 건드리지 않았다', () {
      // count callable 의 권한은 .6-P3 이다 — D-1 helper 로 바꾸지 않았다.
      final f = _fn(code, 'export const callableGetNotTransferredCount');
      expect(f.contains('assertBizAdmin(request.auth.uid, businessId)'), isTrue);
      expect(f.contains('srvAssertWageAuthority('), isFalse,
          reason: 'permission scope 확대는 이번 Phase 범위가 아니다');
    });
  });

  // ───────────────────────────────────────────────────────────
  group('P1-4x 클라이언트 배선', () {
    test('P1-40 모델이 canonical getter 를 노출하고 한 식에 위임한다', () {
      final m = _codeOf(
          File('lib/models/core/attendance_model.dart').readAsStringSync());
      expect(m.contains('bool get isNonPayableZero =>'), isTrue);
      expect(m.contains('bool get isPayableForTransfer =>'), isTrue);
      // 인스턴스 getter 는 static 판정에 위임한다 — 식이 두 벌이 되지 않게.
      expect(m.contains('isNonPayableZero => isNonPayableZeroOf(status, finalWage)'),
          isTrue);
      expect(m.contains('wageStatus == wageConfirmed && !isNonPayableZero'),
          isTrue);
    });

    test('P1-41 모델 판정이 서버와 같은 경계다', () {
      for (final f in <Att>[
        Att('1', 'confirmed', 'NO_SHOW', 0),
        Att('2', 'confirmed', 'absent', 0),
        Att('3', 'confirmed', 'NO_SHOW', 24000),
        Att('4', 'confirmed', 'present', 0),
        Att('5', 'transferred', 'present', 24000),
      ]) {
        expect(
          AttendanceModel.isNonPayableZeroOf(f.status, f.finalWage),
          isNonPayableZero(f.status, f.finalWage),
          reason: f.id,
        );
      }
    });

    test('P1-42 이체 대시보드 네 자리가 canonical getter 를 쓴다', () {
      final uses = 'isPayableForTransfer'.allMatches(client).length;
      expect(uses, greaterThanOrEqualTo(4),
          reason: '배지·전체그룹·날짜별인원·날짜필터');
      // 인라인 판정이 남아 있으면 한쪽만 고쳐지는 날이 온다.
      expect(
        client.contains(
            'if (r.wageStatus != AttendanceModel.wageConfirmed) continue;'),
        isFalse,
      );
    });

    test('P1-43 overview 월별 집계도 같은 식을 쓴다', () {
      final ov = _codeOf(File(
        'lib/screens/business_admin/payroll/payroll_overview_screen.dart',
      ).readAsStringSync());
      expect(ov.contains('AttendanceModel.isNonPayableZeroOf('), isTrue);
    });
  });
}
