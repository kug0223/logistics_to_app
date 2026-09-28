// [R7-P1-5] 급여 화면군 — 모름·단위·범위 계약
//
//   실제 행동/렌더 증거는 payroll_overview_unknown_render_test 가 들고 있다.
//   이 파일은 **소스 배선**만 본다(둘을 섞지 않는다).

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _ovPath = 'lib/screens/business_admin/payroll/payroll_overview_screen.dart';
const _seamPath =
    'lib/screens/business_admin/payroll/payroll_overview_reads.dart';
const _dashPath =
    'lib/screens/business_admin/payroll/payroll_payment_dashboard_screen.dart';
const _wdPath =
    'lib/screens/business_admin/payroll/payroll_worker_detail_screen.dart';
const _calcPath = 'lib/utils/payment_due_date_calculator.dart';
const _fnsPath = 'functions/src/index.ts';

/// 줄바꿈에 기대지 않는다 — 체크아웃 방식(core.autocrlf)이 대조를 바꾸면 안 된다.
String _src(String p) {
  final f = File(p);
  if (!f.existsSync()) throw StateError('$p 를 찾지 못함');
  return f.readAsStringSync().replaceAll('\r\n', '\n');
}

String _bodyOf(String src, String signature, String nextSignature) {
  final i = src.indexOf(signature);
  if (i == -1) throw StateError('$signature 를 찾지 못함');
  final j = src.indexOf(nextSignature, i);
  if (j == -1) throw StateError('$nextSignature 를 찾지 못함');
  return src.substring(i, j);
}

void main() {
  late String ov;
  late String seam;
  late String dash;
  late String wd;
  late String calc;
  late String fns;

  setUpAll(() {
    ov = _src(_ovPath);
    seam = _src(_seamPath);
    dash = _src(_dashPath);
    wd = _src(_wdPath);
    calc = _src(_calcPath);
    fns = _src(_fnsPath);
  });

  // ══════════════════════════════════════════════════════════
  group('PAY-1 모름을 0 으로 말하지 않는다', () {
    test('U-1 출근 집계 실패를 상태로 들고 있다', () {
      expect(ov.contains('bool _attCountsUnknown = false;'), isTrue);
      expect(
          ov.contains(
              'final attUnknown = attResult == null || attResult!.limitReached;'),
          isTrue,
          reason: '실패(null)와 상한 도달(limitReached) 둘 다 모름이다');
      expect(ov.contains('_attCountsUnknown = attUnknown;'), isTrue);
    });

    test('U-2 월 카드가 모름을 지우지 않고 말한다', () {
      expect(ov.contains("'미이체 확인 못함'"), isTrue);
      // 모름 분기가 0 비교보다 **먼저** 와야 한다 — 아니면 줄이 사라진다.
      final unknownAt = ov.indexOf('if (_attCountsUnknown) ...[');
      final zeroAt = ov.indexOf('summary.notTransferredCount > 0');
      expect(unknownAt, greaterThan(-1));
      expect(unknownAt, lessThan(zeroAt));
    });

    test('U-3 월 상세로 모름이 전달되고, 받으면 파생값을 주장하지 않는다', () {
      expect(ov.contains('countsUnknown: _attCountsUnknown,'), isTrue);
      expect(ov.contains('final bool countsUnknown;'), isTrue);
      expect(ov.contains('late bool _countsUnknown = widget.countsUnknown;'), isTrue);
      // 이체 완료·미이체 두 자리 모두 모름을 말한다.
      expect("countsUnknown ? '확인 못함'".allMatches(ov).length, 2);
      // 집계 문서를 실제로 받으면 해제된다.
      expect(ov.contains('_countsUnknown = false;'), isTrue);
    });

    test('U-4 근무자 조회 실패와 집계 없음을 구분한다', () {
      expect(ov.contains('bool _workersLoadFailed = false;'), isTrue);
      expect(ov.contains('_workersLoadFailed = true;'), isTrue);
      expect(ov.contains("'근무자 목록을 불러오지 못했습니다'"), isTrue);
      // 실패 분기가 '집계 데이터가 없습니다'(복원 권유)보다 먼저 온다.
      final failAt = ov.indexOf('_workersLoadFailed');
      final repairAt = ov.indexOf("'집계 데이터가 없습니다'");
      expect(repairAt, greaterThan(-1));
      expect(ov.indexOf('? _workersLoadFailed'), lessThan(repairAt),
          reason: '조회 실패에 서버 재집계를 권하면 원인을 틀리게 말한다');
      expect(failAt, greaterThan(-1));
    });
  });

  // ══════════════════════════════════════════════════════════
  group('PAY-1 단위는 서버가 세는 것에 맞춘다', () {
    test('U-5 서버 projection 의 workDays 는 attendance 1건당 +1 이다', () {
      expect(fns.contains('workDays: 1,'), isTrue,
          reason: 'srvPayrollContribution — 날짜가 아니라 기록 하나의 몫이다');
      expect(fns.contains('const cBefore = srvPayrollContribution(before);'), isTrue);
    });

    test('U-6 개요 근무자 행과 상세가 건으로 말한다', () {
      expect(ov.contains(r"'확정 근무 ${worker.workDays}건'"), isTrue);
      expect(ov.contains(r"'${worker.workDays}일 근무'"), isFalse);
      expect(wd.contains(r"Text('${_records.length}건',"), isTrue);
      expect(wd.contains(r"Text('${_records.length}일',"), isFalse);
      expect(wd.contains("Text('확정 근무',"), isTrue);
      expect(wd.contains("Text('근무일수',"), isFalse);
    });

    test('U-7 상세의 모집단은 확정·이체된 기록이다', () {
      expect(wd.contains('AttendanceModel.wageConfirmed'), isTrue);
      expect(wd.contains('AttendanceModel.wageTransferred'), isTrue);
      expect(wd.contains('allowedStatuses.contains(r.wageStatus)'), isTrue);
    });
  });

  // ══════════════════════════════════════════════════════════
  group('PAY-2 낡은 결과가 현재 선택을 덮지 않는다', () {
    test('S-1 새 로드가 밀려 있으면 이전 결과를 적용하지 않는다', () {
      final body = _bodyOf(dash, 'Future<void> _load({',
          'void _refreshAfterMutation({');
      final guardAt = body.indexOf('if (_pendingReload) return;');
      final applyAt = body.indexOf('_allRecords         = allRecs;');
      expect(guardAt, greaterThan(-1),
          reason: '월을 바꾸면 in-flight 결과는 다른 달 것이다');
      expect(guardAt, lessThan(applyAt));
      // 직렬화 계약은 그대로다 — finally 가 최신 범위로 다시 읽는다.
      expect(body.contains('if (_pendingReload) {'), isTrue);
      expect(body.contains('_load(withRequestTabs: _pendingWithRequests,'), isTrue);
    });

    test('S-2 연체·당일 판정은 저장값과 같은 기준으로 정규화한다', () {
      expect(dash.contains('static DateTime get _today => FormatHelper.toKstDate'), isTrue);
      final due = _bodyOf(dash, 'DateTime? _earliestDue(', 'bool _groupIsOverdue(');
      expect(due.contains('.map(FormatHelper.toKstDate)'), isTrue,
          reason: '저장된 instant 를 KST 달력일로 맞춘 뒤 비교한다');
    });
  });

  // ══════════════════════════════════════════════════════════
  group('PAY-2 지급 예정일은 기기 시간대에 좌우되지 않는다', () {
    test('D-1 계산기가 전부 UTC 플래그 달력일을 만든다', () {
      final monthly = _bodyOf(calc, 'static DateTime _nextMonthlyDay(',
          'static int _lastDayOf(');
      expect(monthly.contains('DateTime.utc('), isTrue);
      // 실제로 잘못됐던 세 생성자 자리를 직접 본다(주석·시그니처 제외).
      expect(monthly.contains('DateTime(from.'), isFalse,
          reason: 'local DateTime 이 남으면 기기마다 하루가 밀린다');
      expect(monthly.contains('DateTime(nextMonth.'), isFalse);
      expect(calc.contains('DateTime.utc(year, month + 1, 0).day'), isTrue);
    });

    test('D-2 서버가 writer 이고 같은 모양을 만든다', () {
      expect(fns.contains('function srvCalculatePaymentDueDate('), isTrue);
      expect(fns.contains('const paymentDueDate = srvCalculatePaymentDueDate('), isTrue);
      // 같은 요일이면 다음 주 — 클라이언트도 같은 정책이어야 한다.
      expect(fns.contains('|| 7;'), isTrue);
      expect(calc.contains('diff == 0 ? 7 : diff'), isTrue);
    });
  });

  // ══════════════════════════════════════════════════════════
  group('PAY-4 반응형 — 잘리는 것을 글자 축소로 덮지 않는다', () {
    test('R-1 월 카드 높이가 OS 글자 배율을 반영한다', () {
      expect(ov.contains('MediaQuery.textScalerOf(context).scale(baseTextPx)'), isTrue);
      expect(ov.contains('const itemHeight = 100.0;'), isFalse,
          reason: '고정 높이는 배율 1.3 에서 아래를 잘랐다');
      // 글자를 줄이는 우회를 쓰지 않았다.
      expect(ov.contains('FittedBox'), isFalse);
      expect(ov.contains('textScaleFactor: 1'), isFalse);
    });

    test('R-2 금액 줄과 상태 줄이 넘치지 않게 flex·Wrap 을 쓴다', () {
      expect(ov.contains('Expanded(\n                child: Row(mainAxisSize: MainAxisSize.min'), isTrue,
          reason: '금액 묶음이 남는 공간을 차지하고, 모자라면 라벨부터 줄인다');
      final statusAt = ov.indexOf('// ── 2행: 이체완료 | 미이체 상태');
      expect(statusAt, greaterThan(-1));
      expect(ov.substring(statusAt, statusAt + 900).contains('Wrap('), isTrue);
      expect(ov.substring(statusAt, statusAt + 900).contains('const Spacer(),'), isFalse);
    });
  });

  // ══════════════════════════════════════════════════════════
  group('PAY-3 기존 계약 유지 (재사용 — 이번에 바꾸지 않았다)', () {
    test('P-1 이체·취소가 앱 내부 기록임을 문구가 말한다', () {
      expect(dash.contains('실제 은행 이체를 완료한 건만 처리해 주세요.'), isTrue);
      expect(dash.contains('실제 은행 이체는 취소되지 않습니다'), isTrue);
    });

    test('P-2 취소는 canManageWage + canCancelTransfer 를 요구한다', () {
      expect(dash.contains('(p) => p.canManageWage && p.canCancelTransfer'), isTrue);
      // 다이얼로그 뒤 재검증 + unknown 은 거부.
      expect(dash.contains("ToastHelper.showWarning('이체 취소 권한을 확인하지 못했습니다.')"),
          isTrue);
    });

    test('P-3 급여 화면 진입은 확인된 허용에서만', () {
      expect(ov.contains('userProvider.checkCurrentBusiness((p) => p.canManageWage)'), isTrue);
      expect(ov.contains('_accessUnverified = entryCheck == PermissionCheck.error'), isTrue);
    });
  });
// ══════════════════════════════════════════════════════════
  // [R7-P1-5 후속] 미이체 건수의 owner 는 원장 하나다
  // ══════════════════════════════════════════════════════════
  group('OWN 미이체 owner 수렴', () {
    test('OWN-1 계산이 한 곳에만 있다 (공유 reading)', () {
      expect(ov.contains('class _LedgerMonthCounts'), isTrue);
      // 월별 집계 루프가 화면에 중복으로 남아 있지 않다.
      expect("data['wageStatus'] as String?".allMatches(ov).length, 1,
          reason: '같은 판정을 두 곳에서 하면 다시 갈린다');
      expect("AttendanceModel.isNonPayableZeroOf".allMatches(ov).length, 1);
    });

    test('OWN-2 로더와 복귀 갱신이 같은 계산을 쓴다', () {
      final loader = _bodyOf(ov, 'Future<void> _loadYear(', 'Future<void> _loadTodayCount(');
      final refresh = _bodyOf(ov, 'Future<void> _refreshSummary(', 'Future<void> _loadWorkers(');
      expect(loader.contains('_LedgerMonthCounts.of('), isTrue);
      expect(refresh.contains('_LedgerMonthCounts.of('), isTrue);
      expect(refresh.contains('_reads.adminAttendances('), isTrue,
          reason: '복귀 갱신도 원장을 읽는다 — 집계 문서로 건수를 덮지 않는다');
    });

    test('OWN-3 파생(이체 완료)이 한 owner 안에서 끝난다', () {
      final loader = _bodyOf(ov, 'Future<void> _loadYear(', 'Future<void> _loadTodayCount(');
      // 문서가 있어도 원장을 쓸 수 있으면 확정 건수도 원장에서 온다.
      expect(
          loader.contains(
              'attUnknown ? existing.confirmedCount : (ntCount + tCount)'),
          isTrue);
      final refresh = _bodyOf(ov, 'Future<void> _refreshSummary(', 'Future<void> _loadWorkers(');
      expect(
          refresh.contains(
              'ledger.notTransferred[monthIdx] + ledger.transferred[monthIdx]'),
          isTrue);
    });

    test('OWN-4 상한 도달은 모름이다 (fail-closed)', () {
      expect(ov.contains('attResult!.limitReached'), isTrue);
      expect(seam.contains("r.data['limitReached'] == true"), isTrue);
      final refresh = _bodyOf(ov, 'Future<void> _refreshSummary(', 'Future<void> _loadWorkers(');
      expect(refresh.contains('ledgerResult.limitReached'), isTrue);
    });

    test('OWN-5 모르는 달을 빈 달이라고 말하지 않는다', () {
      expect(ov.contains("_attCountsUnknown ? '확인 못함' : '데이터 없음'"), isTrue);
    });

    test('OWN-6 세 번째 정의(전 기간 count)의 죽은 호출부를 없앴다', () {
      final svc = _src('lib/services/payroll_payment_service.dart');
      expect(svc.contains('Future<int?> getTotalNotTransferredCount'), isFalse,
          reason: '메서드 선언이 남아 있으면 다음 호출부가 생긴다');
      expect(svc.contains("httpsCallable('callableGetNotTransferredCount'"), isFalse);
      // 서버 함수는 배포 범위라 남겨 두었다 — 그 사실을 주석으로 남긴다.
      expect(svc.contains('callableGetNotTransferredCount'), isTrue);
      expect(fns.contains('export const callableGetNotTransferredCount'), isTrue);
    });

    test('OWN-7 이 값을 읽는 곳은 표시 두 자리뿐이다 (행동 gate 아님)', () {
      // 대시보드의 이체·취소·전체선택은 자기 목록(_allRecords)만 본다.
      expect(dash.contains('notTransferredCount'), isFalse);
      // 화면 밖 소비자도 없다.
      for (final path in const [
        'lib/screens/business_admin/business_admin_home_screen.dart',
        'lib/screens/business_admin/payroll/payroll_worker_detail_screen.dart',
      ]) {
        expect(_src(path).contains('notTransferredCount'), isFalse, reason: path);
      }
    });
  });
}
