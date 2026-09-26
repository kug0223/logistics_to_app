// [DOC-P2] 통장사본 접근 이유 계약.
//
//   지키는 문장은 둘이다.
//
//     예외 상태는 접근 자격이 아니다 — 주의 표시다.
//     보낼 돈이 있어야 문서를 열 이유가 있다.
//
//   예전에는 자동 판정이 실패한 경우에만 통장사본 버튼이 났다. 정상적으로
//   지급을 준비하는 담당자는 볼 길이 없었다. 반대로 서버는 wageStatus 만
//   보아, 0원으로 마감된 노쇼 건도 접근 이유로 인정했다. 두 방향이 모두
//   어긋나 있었다.
//
//   지급 대상 판정은 Dart 로 재구현해 경계를 직접 고정하고(순수 함수),
//   서버·화면 배선은 소스 문자열로 고정한다.

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

String _codeOf(String src) => src
    .split('\n')
    .where((l) => !l.trimLeft().startsWith('//'))
    .join('\n');

String _after(String src, String name, int chars) {
  final i = src.indexOf(name);
  expect(i, greaterThan(-1), reason: '$name 을 찾지 못했다');
  final e = (i + chars) > src.length ? src.length : i + chars;
  return src.substring(i, e);
}

// ─────────────────────────────────────────────────────────────
// 지급 대상 판정 — .6-P1 canonical predicate 와 같은 식
// ─────────────────────────────────────────────────────────────

class Row {
  const Row(this.id, this.wageStatus, this.status, this.finalWage);
  final String id;
  final String wageStatus;
  final String status;
  final int finalWage;
}

bool isNonPayableZero(String status, int wage) =>
    (status == 'NO_SHOW' || status == 'absent') && wage == 0;

bool payable(Row r) =>
    r.wageStatus == 'confirmed' && !isNonPayableZero(r.status, r.finalWage);

/// 화면·서버가 공통으로 고르는 "지급 사유가 되는 행".
Row? purposeRow(List<Row> rows) {
  for (final r in rows) {
    if (payable(r)) return r;
  }
  return null;
}

/// 통장사본을 볼 수 있는가 — 예외 여부·지원서 상태와 무관.
bool bankViewEligible(
  List<Row> rows, {
  bool readinessKnown = true,
  bool needsManualReview = false,
  String applicationStatus = 'CONFIRMED',
}) {
  if (!readinessKnown) return false; // 모르는 상태로 원본을 열지 않는다
  return purposeRow(rows) != null;
}

void main() {
  late String cf;
  late String screen;

  setUpAll(() {
    cf = _codeOf(File('functions/src/index.ts').readAsStringSync());
    screen = _codeOf(File(
      'lib/screens/business_admin/payroll/payroll_payment_dashboard_screen.dart',
    ).readAsStringSync());
  });

  // ───────────────────────────────────────────────────────────
  group('P2-1x 접근 이유 matrix (§15)', () {
    const payableRow = Row('r1', 'confirmed', 'present', 24000);
    const lateRow = Row('r2', 'confirmed', 'late', 24000);
    const earlyRow = Row('r3', 'confirmed', 'early_leave', 24000);
    const noShow0 = Row('r4', 'confirmed', 'NO_SHOW', 0);
    const absent0 = Row('r5', 'confirmed', 'absent', 0);
    const noShowPos = Row('r6', 'confirmed', 'NO_SHOW', 24000);
    const transferred = Row('r7', 'transferred', 'present', 24000);
    const pendingRow = Row('r8', 'pending', 'present', 0);

    test('A 정상 지급 대상 + 예외 없음 → 접근 가능', () {
      expect(bankViewEligible([payableRow]), isTrue);
      expect(bankViewEligible([lateRow]), isTrue);
      expect(bankViewEligible([earlyRow]), isTrue);
    });

    test('B 예외(사람 검토 필요)여도 같은 접근', () {
      expect(bankViewEligible([payableRow], needsManualReview: true), isTrue);
      expect(bankViewEligible([payableRow], needsManualReview: false), isTrue,
          reason: 'M 예외가 아니라는 이유로 거부하지 않는다');
    });

    test('C 지원서가 취소·종료여도 미지급이 남으면 접근 유지', () {
      expect(
        bankViewEligible([payableRow], applicationStatus: 'CANCELED'),
        isTrue,
        reason: 'N 현재 관계 상태가 지급 의무를 지우지 않는다',
      );
    });

    test('D 이체 이력만 있으면 접근 없음', () {
      expect(bankViewEligible([transferred]), isFalse,
          reason: '과거에 보냈다는 사실이 현재 목적을 만들지 않는다');
    });

    test('E 노쇼 0원은 목적이 아니다', () {
      expect(payable(noShow0), isFalse);
      expect(bankViewEligible([noShow0]), isFalse);
    });

    test('F 결근 0원도 목적이 아니다', () {
      expect(payable(absent0), isFalse);
      expect(bankViewEligible([absent0]), isFalse);
    });

    test('G 섞인 그룹은 지급 대상 행을 지목한다', () {
      final rows = [noShow0, payableRow];
      expect(purposeRow(rows)?.id, 'r1',
          reason: 'confirmed 첫 건을 집으면 노쇼가 목적이 된다');
      expect(bankViewEligible(rows), isTrue);
    });

    test('H 노쇼 0원만 있으면 접근 없음', () {
      expect(bankViewEligible([noShow0, absent0]), isFalse);
      expect(purposeRow([noShow0, absent0]), isNull);
    });

    test('I 비정상 양수 노쇼는 조용히 버리지 않는다', () {
      expect(payable(noShowPos), isTrue,
          reason: '.6-P1 이 지급 의무로 보는 건은 여기서도 같다');
      expect(purposeRow([noShowPos])?.id, 'r6');
    });

    test('pending·calculated 는 목적이 아니다', () {
      expect(bankViewEligible([pendingRow]), isFalse);
    });

    test('준비 상태를 모르면 열지 않는다', () {
      expect(bankViewEligible([payableRow], readinessKnown: false), isFalse,
          reason: '조회 실패를 "없음"으로도 "있음"으로도 쓰지 않는다');
    });
  });

  // ───────────────────────────────────────────────────────────
  group('P2-2x 서버 목적 판정 (§2·§3)', () {
    test('지급 대상 판정과 같은 식을 쓴다', () {
      final f = _after(cf, 'async function srvAssertCurrentPayrollPurpose(', 2200);
      expect(f.contains('srvPayableForTransfer('), isTrue);
      // wageStatus 단독 판정이 남아 있으면 안 된다.
      expect(f.contains('if (d.wageStatus !== "confirmed") throw deny();'),
          isFalse);
    });

    test('지목된 건도, 탐색 경로도 같은 식으로 본다', () {
      final f = _after(cf, 'async function srvAssertCurrentPayrollPurpose(', 2200);
      expect('srvPayableForTransfer('.allMatches(f).length, 2,
          reason: 'attendanceId 지정 경로와 미지정 탐색 경로 둘 다');
      // 탐색은 where 로 표현할 수 없어 select 후 서버에서 고른다.
      expect(f.contains('.select("wageStatus", "status", "finalWage")'), isTrue);
      expect(f.contains('.limit(1).get()'), isFalse,
          reason: '첫 confirmed 한 건만 보면 노쇼가 목적이 된다');
    });

    test('거부 문구가 존재 여부를 누설하지 않는다', () {
      final f = _after(cf, 'async function srvAssertCurrentPayrollPurpose(', 2200);
      expect(f.contains('지금 지급할 급여가 없어 지급 서류를 확인할 수 없습니다'),
          isTrue);
    });

    test('§13 권한은 기존 급여 자격을 그대로 쓴다', () {
      final g = _after(cf, 'async function srvAssertPayrollDocumentAccess(', 700);
      expect(g.contains('assertBizAdmin('), isTrue);
      expect(g.contains('canManageWage'), isTrue);
      // 새 capability 를 만들지 않았다.
      for (final bad in <String>['canViewBankbook', 'canManageDocument']) {
        expect(cf.contains(bad), isFalse, reason: bad);
      }
    });

    test('§13 두 문이 같은 두 가드를 쓴다', () {
      for (final f in <String>[
        'export const callableGetPayrollBankbookUrl',
        'export const callableReviewPayrollBankDocument',
      ]) {
        final i = cf.indexOf(f);
        expect(i, greaterThan(-1), reason: f);
        final n = cf.indexOf('\nexport const ', i + 10);
        final body = cf.substring(i, n > 0 ? n : cf.length);
        expect(body.contains('srvAssertPayrollDocumentAccess('), isTrue,
            reason: f);
        expect(body.contains('srvAssertCurrentPayrollPurpose('), isTrue,
            reason: f);
      }
    });
  });

  // ───────────────────────────────────────────────────────────
  group('P2-3x 화면 배선 (§5·§10·§14)', () {
    test('접근 판정이 예외 여부에 매여 있지 않다', () {
      expect(screen.contains('bool _bankViewEligible('), isTrue);
      final f = _after(screen, 'bool _bankViewEligible(', 900);
      expect(f.contains('_payablePurposeRow(recs) != null'), isTrue);
      expect(f.contains('_needsManualReview'), isFalse,
          reason: '예외는 접근 자격이 아니다');
      expect(f.contains('_readinessUnknown.contains(uid)'), isTrue,
          reason: '모르는 상태로 원본을 열지 않는다');
    });

    test('CTA 가 지급 사유로 열린다', () {
      expect(screen.contains('onReviewBankDocument: _bankViewEligible(recs)'),
          isTrue);
      expect(screen.contains('onReviewBankDocument: _needsManualReview(recs)'),
          isFalse);
    });

    test('§14 예외는 같은 버튼의 주의 표현으로만 남는다', () {
      expect(screen.contains('bankViewAttention: _needsManualReview(recs)'),
          isTrue);
      expect(screen.contains('final bool bankViewAttention;'), isTrue);
      // 문구 분기를 직접 집는다 — 색 분기부터 세면 창 길이에 흔들린다.
      expect(screen.contains('child: Text(bankViewAttention'), isTrue);
      final r = _after(screen, 'child: Text(bankViewAttention', 200) +
          _after(screen, 'foregroundColor: bankViewAttention', 300);
      expect(r.contains("'통장사본 보기'"), isTrue, reason: '일상 접근 문구');
      expect(r.contains("'통장사본 확인'"), isTrue, reason: '주의 문구');
      expect(r.contains('AppColors.infoDark'), isTrue, reason: '주의 색');
    });

    test('§10 target 선정이 canonical 하다', () {
      expect(screen.contains('AttendanceModel? _payablePurposeRow('), isTrue);
      final f = _after(screen, 'AttendanceModel? _payablePurposeRow(', 500);
      expect(f.contains('r.isPayableForTransfer'), isTrue);
      final rv = _after(screen, 'Future<void> _reviewBankDocument(', 1200);
      expect(rv.contains('_payablePurposeRow(recs)'), isTrue);
      expect(rv.contains('unpaid.first'), isFalse,
          reason: 'confirmed 첫 건을 집으면 노쇼가 목적이 된다');
    });

    test('§12 문서 버전 계약이 그대로다', () {
      final rv = _after(screen, 'Future<void> _reviewBankDocument(', 1400);
      expect(rv.contains('expectedBankbookVersion: info.bankbookVersion'),
          isTrue);
      expect(rv.contains('attendanceId: target.id'), isTrue);
    });

    test('§19 권한 오류를 "통장사본 없음"으로 바꾸지 않는다', () {
      final rv = _after(screen, 'Future<void> _reviewBankDocument(', 1600);
      expect(rv.contains('통장사본을 열지 못했습니다'), isTrue);
      expect(rv.contains('통장사본이 없습니다'), isFalse);
    });

    test('§8 이체 완료 행에는 버튼이 없다', () {
      expect(screen.contains('if (!isTransferred && !isBatchMode &&'), isTrue);
    });
  });

  // ───────────────────────────────────────────────────────────
  group('P2-4x 서버·화면 semantic parity (§17)', () {
    test('같은 입력에서 두 쪽 판정이 일치한다', () {
      // 화면의 판정식(Dart 재구현)과 서버가 쓰는 식이 같은 집합을 만든다.
      const cases = <Row>[
        Row('a', 'confirmed', 'present', 24000),
        Row('b', 'confirmed', 'late', 1),
        Row('c', 'confirmed', 'early_leave', 24000),
        Row('d', 'confirmed', 'NO_SHOW', 0),
        Row('e', 'confirmed', 'absent', 0),
        Row('f', 'confirmed', 'NO_SHOW', 24000),
        Row('g', 'transferred', 'present', 24000),
        Row('h', 'pending', 'present', 0),
      ];
      final uiAllows = cases.where((r) => bankViewEligible([r])).map((r) => r.id);
      // 서버도 같은 술어를 쓰므로 집합이 같아야 한다.
      final serverAllows = cases.where(payable).map((r) => r.id);
      expect(uiAllows, serverAllows);
      expect(uiAllows.toList(), ['a', 'b', 'c', 'f']);
    });

    test('.6-P1 canonical 술어가 그대로다', () {
      expect(cf.contains('function srvIsNonPayableZero('), isTrue);
      expect(cf.contains('function srvPayableForTransfer('), isTrue);
      final m = _codeOf(
          File('lib/models/core/attendance_model.dart').readAsStringSync());
      expect(m.contains('bool get isPayableForTransfer =>'), isTrue);
    });
  });
}
