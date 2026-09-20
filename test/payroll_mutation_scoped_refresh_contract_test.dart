// [R8-P1D] 급여 화면에서 뭘 하나 처리할 때마다 화면 전체를 다시 읽었다.
//
//   이체 하나 눌러도 변경요청 목록과 중간정산 목록까지 다시 받았다. 그 둘은
//   이체로 바뀌지 않는다. 반대로 지급방식 변경을 승인하면 급여 목록 전체를
//   다시 읽었는데, 그 승인은 요청 문서 하나만 바꾼다.
//
//   무엇을 다시 읽을지는 버튼 이름이 아니라 **서버가 무엇을 썼는지**로 정한다.
//   그래서 이 계약은 클라이언트만 보지 않고 CF writer 의 write-set 도 함께 건다.
//
//   돈 이야기는 성능보다 앞선다: 응답값으로 행 상태를 지어내지 않고,
//   중간정산 lock 은 그대로 두고, 한쪽만 갱신된 화면을 만들지 않는다.
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

String _src() => File(
    'lib/screens/business_admin/payroll/payroll_payment_dashboard_screen.dart')
    .readAsStringSync();
String _fn() => File('functions/src/index.ts').readAsStringSync();

/// 주석으로 시작하는 줄만 제거한다 (문서 주석은 남는다).
String _codeOf(String raw) => raw
    .split('\n')
    .where((l) => !l.trimLeft().startsWith('//'))
    .join('\n');

String _flat(String s) => s.replaceAll(RegExp(r'\s+'), ' ');

/// 그룹 수집 시점에도 불리므로 expect 대신 예외로 실패시킨다.
String _sliceOf(String raw, String from, String to) {
  final i = raw.indexOf(from);
  if (i < 0) throw StateError('시작 표지를 찾지 못함: $from');
  final j = raw.indexOf(to, i + from.length);
  if (j < 0) throw StateError('끝 표지를 찾지 못함: $to');
  return raw.substring(i, j);
}

/// CF 하나의 본문 — 다음 `export const` 직전까지.
String _cf(String fn, String name) {
  final i = fn.indexOf('export const $name =');
  if (i < 0) throw StateError('CF 를 찾지 못함: $name');
  final j = fn.indexOf('\nexport const ', i + 20);
  return fn.substring(i, j < 0 ? fn.length : j);
}

/// 이 CF 가 attendance 문서를 쓰는가 — collection("attendance") 접근 여부.
bool _touchesAttendance(String body) => body.contains('collection("attendance")');

void main() {
  final raw = _src();
  final code = _codeOf(raw);
  final f = _flat(code);
  final fn = _fn();

  /// mutation handler 안에서 실제로 호출하는 갱신 경로만 뽑는다.
  String handler(String from, String to) => _flat(_sliceOf(code, from, to));

  group('PM-1 — 서버가 attendance 만 바꾼 mutation은 요청 목록을 다시 읽지 않는다', () {
    test('PM-10 callableMarkTransferredBatch 는 attendance 만 쓴다', () {
      final body = _codeOf(_cf(fn, 'callableMarkTransferredBatch'));
      expect(_touchesAttendance(body), true);
      expect(body.contains('collection("payment_change_requests")'), false);
      expect(body.contains('collection("interim_settlement_requests")'), false);
    });

    test('PM-11 callableCancelTransfer 도 attendance 만 쓴다', () {
      final body = _codeOf(_cf(fn, 'callableCancelTransfer'));
      expect(_touchesAttendance(body), true);
      expect(body.contains('collection("payment_change_requests")'), false);
      expect(body.contains('collection("interim_settlement_requests")'), false);
    });

    test('PM-12 단건 이체는 base 만 갱신한다', () {
      final h = handler("ToastHelper.showSuccess('\$processedCount건 이체 완료 처리되었습니다')",
          '} on TransferBlockedException catch (e) {');
      expect(h, contains('_refreshAfterMutation(base: true)'));
      expect(h, isNot(contains('settlements: true')));
      expect(h, isNot(contains('changeRequests: true')));
    });

    test('PM-13 일괄 이체도 base 만 갱신한다', () {
      final h = handler('final processedCount = batchResult.transferredNow;',
          '_showTransferNoteDialog() async {');
      expect(h, contains('_refreshAfterMutation(base: true)'));
      expect(h, isNot(contains('settlements: true')));
      expect(h, isNot(contains('changeRequests: true')));
    });

    test('PM-14 이체 취소(상세화면 복귀)도 base 만 갱신한다', () {
      expect('_refreshAfterMutation(base: true)'.allMatches(code).length,
          greaterThanOrEqualTo(4)); // 단건·차단·일괄·상세복귀×2
      // 상세화면의 mutation 은 이체 취소뿐이다
      final detail = _sliceOf(code, 'class _WorkerPayDetailScreen', 'static const _weekdays');
      expect(_flat(detail), contains('_payService.cancelTransfer('));
      expect(detail.contains('approveChangeRequest'), false);
      expect(detail.contains('InterimSettlement'), false);
    });
  });

  group('PM-2 — request-only mutation은 급여 목록을 다시 읽지 않는다', () {
    test('PM-20 지급방식 변경 승인/거절은 요청 문서만 쓴다', () {
      for (final n in [
        'callableApprovePaymentChangeRequest',
        'callableRejectPaymentChangeRequest',
      ]) {
        final body = _codeOf(_cf(fn, n));
        expect(body.contains('collection("payment_change_requests")'), true, reason: n);
        expect(_touchesAttendance(body), false, reason: '$n 은 attendance 를 쓰지 않는다');
      }
    });

    test('PM-21 승인은 변경요청 목록만 갱신한다', () {
      final h = handler("ToastHelper.showSuccess('변경 요청이 승인되었습니다')",
          'Future<void> _rejectChangeRequest');
      expect(h, contains('_refreshAfterMutation(changeRequests: true)'));
      expect(h, isNot(contains('base: true')));
    });

    test('PM-22 거절도 변경요청 목록만 갱신한다', () {
      final h = handler('Future<void> _rejectChangeRequest', 'void _toggleBatchMode()');
      expect(h, contains('_refreshAfterMutation(changeRequests: true)'));
      expect(h, isNot(contains('base: true')));
    });

    test('PM-23 중간정산 거절은 요청 문서만 쓴다 — 목록만 갱신', () {
      final body = _codeOf(_cf(fn, 'callableRejectInterimSettlement'));
      expect(body.contains('collection("interim_settlement_requests")'), true);
      expect(_touchesAttendance(body), false);
      // PENDING 에서만 거절된다 — lock 이 걸리기 전 상태
      expect(_flat(body), contains('reqData.status !== "PENDING"'));

      final h = handler('Future<void> _rejectSettlement(', 'Future<void> _approveChangeRequest(');
      expect(h, contains('_refreshAfterMutation(settlements: true)'));
      expect(h, isNot(contains('base: true')));
    });
  });

  group('PM-3 — 양쪽을 쓰는 mutation은 양쪽을 함께 갱신한다', () {
    test('PM-30 중간정산 승인은 요청 + attendance lock 을 쓴다', () {
      final body = _codeOf(_cf(fn, 'callableApproveInterimSettlement'));
      expect(body.contains('collection("interim_settlement_requests")'), true);
      expect(_touchesAttendance(body), true);
      expect(_flat(body), contains('activeInterimSettlementId: d.settlementRequestId'));

      final h = handler('Future<void> _approveSettlement(', 'Future<void> _processSettlement(');
      expect(h, contains('_refreshAfterMutation(base: true, settlements: true)'));
    });

    test('PM-31 중간정산 이체처리는 요청 PROCESSED + attendance transferred', () {
      final body = _codeOf(_cf(fn, 'callableProcessInterimSettlement'));
      expect(_touchesAttendance(body), true);
      expect(_flat(body), contains('activeInterimSettlementId: admin.firestore.FieldValue.delete()'));

      final h = handler('Future<void> _processSettlement(', 'Future<void> _rejectSettlement(');
      expect(h, contains('_refreshAfterMutation(base: true, settlements: true)'));
      // [§30] 한쪽만 갱신하면 요청은 PROCESSED 인데 급여는 미이체로 보인다
      expect(h, isNot(contains('_refreshAfterMutation(settlements: true)')));
    });

    test('PM-32 승인 취소는 lock 해제 + 요청 CANCELED — 양쪽 갱신', () {
      final body = _codeOf(_cf(fn, 'callableCancelApprovedInterimSettlement'));
      expect(_touchesAttendance(body), true);
      expect(_flat(body), contains('activeInterimSettlementId: admin.firestore.FieldValue.delete()'));

      final h = handler("ToastHelper.showSuccess('중간정산 승인이 취소되었습니다.')",
          'Future<void> _approveSettlement(');
      expect(h, contains('_refreshAfterMutation(base: true, settlements: true)'));
    });
  });

  group('PM-4 — 응답으로 행 상태를 지어내지 않는다', () {
    test('PM-40 서버는 처리된 attendanceId 를 돌려주지 않는다', () {
      final body = _cf(fn, 'callableMarkTransferredBatch');
      final ret = _flat(_sliceOf(body, 'return {', '};'));
      expect(ret, contains('processed,'));          // 건수
      expect(ret, contains('alreadyTransferred,'));
      expect(ret, contains('skipped,'));
      expect(ret, contains('lockedBySettlement:'));
      // 처리된 id 목록은 응답에 없다 → 클라이언트가 추정할 근거가 없다
      expect(ret.contains('processedAttendanceIds'), false);
    });

    test('PM-41 클라이언트가 급여 행을 직접 만들거나 옮기지 않는다', () {
      // _allRecords 는 서버 재조회 결과로만 통째로 바뀐다 — 선언 1 + 대입 1
      expect(RegExp(r'_allRecords\s*=').allMatches(code).length, 2);
      expect(f, contains('_allRecords = allRecs;'));
      expect(code.contains('_allRecords.removeWhere'), false);
      expect(code.contains('_allRecords.add'), false);
      // 비교(==)는 되지만 대입(=)은 없다
      expect(RegExp(r'wageStatus\s*=(?!=)').hasMatch(code), false);
    });

    test('PM-42 base 갱신은 서버 재조회 하나로 이뤄진다', () {
      final load = _flat(_sliceOf(code,
          'Future<void> _load({bool withRequestTabs = true, bool afterMutation = false}) async {',
          'void _refreshAfterMutation({'));
      expect(load, contains('_payService.getPayrollRecords('));
      expect(load, contains('_allRecords = allRecs'));
    });

    test('PM-43 partial 안내 문구가 그대로다', () {
      expect(f, contains("'\$processedCount건 이체 완료 처리되었습니다'"));
      expect(f, contains('건은 이미 이체 완료된 항목이에요'));
      expect(f, contains('확인된 완료 \${e.confirmedProcessedCount}건'));
    });
  });

  group('PM-5 — users/readiness 는 근거 없이 다시 읽지 않는다', () {
    test('PM-50 이름은 캐시에 없는 uid 만 조회한다', () {
      final bank = _flat(_sliceOf(code, 'Future<void> _loadBankInfo(Set<String> uids) async {',
          'Future<void> _loadWorkerNames('));
      expect(bank, contains('uids.where((u) => !_userBankCache.containsKey(u))'));
      expect(bank, contains('if (uncached.isEmpty) return;'));
    });

    test('PM-51 이체 mutation 이 프로필/지급준비를 직접 다시 부르지 않는다', () {
      for (final h in [
        handler("ToastHelper.showSuccess('\$processedCount건 이체 완료 처리되었습니다')",
            '} on TransferBlockedException catch (e) {'),
        handler('final processedCount = batchResult.transferredNow;',
            '_showTransferNoteDialog() async {'),
      ]) {
        expect(h.contains('_loadWorkerNames('), false);
        expect(h.contains('_loadPayrollReadiness('), false);
        expect(h.contains('_loadBankInfo('), false);
      }
    });
  });

  group('PM-6 — 갱신 실패를 처리 실패로 말하지 않는다', () {
    test('PM-60 base 갱신 실패 문구가 처리 성공을 지운다', () {
      final load = _flat(_sliceOf(code,
          'Future<void> _load({bool withRequestTabs = true, bool afterMutation = false}) async {',
          'void _refreshAfterMutation({'));
      expect(load, contains("afterMutation ? '처리는 완료됐어요. 최신 급여 현황을 불러오지 못했습니다' : '데이터를 불러오지 못했습니다'"));
    });

    test('PM-61 요청 목록 갱신 실패도 같다', () {
      expect(f, contains("_changeRequestsError = afterMutation ? '처리는 완료됐어요. 목록을 새로 불러오지 못했습니다.'"));
      expect(f, contains("_settlementRequestsError = afterMutation ? '처리는 완료됐어요. 목록을 새로 불러오지 못했습니다.'"));
    });

    test('PM-62 mutation 실패 경로도 서버에서 다시 읽는다 — 추측하지 않는다', () {
      // 실패해도 서버가 일부를 바꿨을 수 있다
      expect('_load(withRequestTabs: false)'.allMatches(code).length,
          greaterThanOrEqualTo(2));
    });
  });

  group('PM-7 — 겹친 갱신이 서로를 덮지 않는다', () {
    test('PM-70 base 는 기존 in-flight 가드를 그대로 쓴다', () {
      final load = _flat(_sliceOf(code,
          'Future<void> _load({bool withRequestTabs = true, bool afterMutation = false}) async {',
          'try {'));
      expect(load, contains('if (_fetchInProgress) { _pendingReload = true;'));
    });

    test('PM-71 밀린 재로드는 범위를 잃지 않는다 — 합집합으로 이어받는다', () {
      expect(f, contains('_pendingWithRequests = _pendingWithRequests || withRequestTabs'));
      expect(f, contains('_pendingAfterMutation = _pendingAfterMutation || afterMutation'));
      expect(f, contains('_load(withRequestTabs: _pendingWithRequests, afterMutation: _pendingAfterMutation)'));
    });

    test('PM-72 요청 목록도 각자 중복 호출을 막는다', () {
      expect(f, contains('if (!mounted || _changeRequestsInFlight) return'));
      expect(f, contains('if (!mounted || _settlementsInFlight) return'));
    });
  });

  group('PM-8 — cross-flow lock 과 이력 불변이 그대로다', () {
    test('PM-80 ISR 이체건의 개별 취소 차단이 유지된다', () {
      expect(f, contains('if (isXfer && !r.isFromInterimSettlement)'));
    });

    test('PM-81 lock 이 걸린 건의 이체 제외를 서버가 계속 판정한다', () {
      final body = _flat(_codeOf(_cf(fn, 'callableMarkTransferredBatch')));
      expect(body, contains('lockedBySettlement'));
      // 클라이언트가 lock 을 스스로 풀지 않는다
      expect(code.contains('activeInterimSettlementId'), false);
    });

    test('PM-82 승인이 확정된 급여의 지급방식을 클라이언트에서 고치지 않는다', () {
      final h = handler("ToastHelper.showSuccess('변경 요청이 승인되었습니다')",
          'Future<void> _rejectChangeRequest');
      expect(h.contains('payScheduleType'), false);
      expect(h.contains('paymentDueDate'), false);
      expect(h.contains('wageDetail'), false);
    });
  });
}
