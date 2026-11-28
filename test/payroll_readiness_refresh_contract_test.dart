// [R8-P2.1] 통장사본을 확인해 놓고도 다음 버튼이 뜨지 않았다.
//
//   지급 준비 판정(readiness)은 users 문서와 businessApplicantDocumentReviews
//   두 곳에서 나온다. 통장사본 검토는 두 번째를 쓰므로 판정이 바뀐다 —
//   DEV 실측으로 STALE_MANUAL_REVIEW(ready=false) → READY_MANUAL(ready=true).
//
//   그런데 화면은 이름 캐시가 차 있으면 지급 준비 조회까지 함께 건너뛰었다.
//   그래서 "확인 완료했습니다. 지급정보를 갱신하면 이체할 수 있어요" 라고
//   안내한 직후에도 그 갱신 버튼이 뜨지 않았다. 이름과 판정은 무효화 조건이
//   다른데 한 덩어리로 묶여 있었던 것이다.
//
//   성능 최적화가 아니라 운영 정합성 수정이다.
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

/// CF 하나의 본문 — 다음 top-level 선언 직전까지.
String _cf(String fn, String name) {
  final i = fn.indexOf('export const $name =');
  if (i < 0) throw StateError('CF 를 찾지 못함: $name');
  final j = fn.indexOf('\nexport const ', i + 20);
  return fn.substring(i, j < 0 ? fn.length : j);
}

void main() {
  final code = _codeOf(_src());
  final f = _flat(code);
  final fn = _fn();

  group('PR-1 — 판정의 canonical source (서버 계약)', () {
    test('PR-10 readiness 는 users + 검토 문서 두 곳에서 나온다', () {
      final b = _flat(_codeOf(_cf(fn, 'callableGetPayrollReadinessBatch')));
      expect(b, contains('db.collection("users").doc(uid).get()'));
      expect(b, contains('db.collection(BIZ_DOC_REVIEW_COL)'));
      expect(b, contains('srvResolvePayrollReadiness(u.data(), r.data())'));
    });

    test('PR-11 통장사본 검토는 검토 문서를 쓴다 → 판정이 바뀔 수 있다', () {
      final b = _codeOf(_cf(fn, 'callableReviewPayrollBankDocument'));
      expect(_flat(b), contains('const reviewRef = db.collection(BIZ_DOC_REVIEW_COL)'));
      expect(_flat(b), contains('tx.set(reviewRef, patch, {merge: true})'));
      // attendance 는 쓰지 않는다 — 급여 목록을 다시 읽을 이유가 없다
      expect(b.contains('collection("attendance")'), false);
    });

    test('PR-12 스냅샷 갱신은 attendance 만 쓴다 → 판정은 그대로다', () {
      final b = _codeOf(_cf(fn, 'callableRefreshWagePaymentSnapshot'));
      // [AUD-3 H1 · 정책 7 · server_295/296] 예전 핀: 'db.collection("attendance").doc(id).update(' (거래 밖 조건 없는 쓰기).
      //   이체·잠금 경합에서 '보낸 계좌' 기록을 덮어서, 근태를 거래 안에서 다시 읽고 지금도 같은 사업장·근로자·confirmed·잠금 없음일
      //   때만 거래 안 update 로 쓴다. 쓰는 문서는 여전히 attendance 하나다(이 핀의 뜻 = 판정 문서를 쓰지 않는다 — 그대로).
      expect(_flat(b), contains('const attRef = db.collection("attendance").doc(id);'));
      expect(_flat(b), contains('const fresh = await tx.get(attRef);'));
      expect(_flat(b), contains('if (fd.wageStatus === "transferred") return "alreadyTransferred";'));
      expect(_flat(b), contains('tx.update(attRef, {'));
      expect(_flat(b).contains('db.collection("attendance").doc(id).update('), false);
      // users / 검토 문서는 읽기만 한다
      expect(b.contains('db.collection("users").doc(u)'), true);
      expect(_flat(b).contains('collection("users").doc(uid).update('), false);
      expect(_flat(b).contains('tx.set(reviewRef'), false);
    });
  });

  group('PR-2 — 이름 캐시가 판정 갱신을 막지 않는다', () {
    final bank = _sliceOf(code, 'Future<void> _loadBankInfo(Set<String> uids) async {',
        'Set<String> get _visibleWorkerUids');
    final reload = _sliceOf(code, 'Future<void> _reloadReadiness() async {',
        'Future<void> _loadPayrollReadiness(');

    test('PR-20 판정만 다시 읽는 별도 경로가 있다', () {
      // [PAYROLL-V3-RECOVERY 갱신] 예전: '_loadPayrollReadiness(uids, guard:'. 늦은 응답 순번을 안쪽으로 옮겼다(PR-51).
      expect(_flat(reload), contains('await _loadPayrollReadiness(uids);'));
    });

    test('PR-21 그 경로는 이름 캐시를 보지 않는다', () {
      expect(reload.contains('_userBankCache'), false);
      expect(reload.contains('uncached'), false);
    });

    test('PR-22 이름 캐시는 여전히 유효하다 — 캐시 미스일 때만 조회', () {
      expect(_flat(bank), contains('uids.where((u) => !_userBankCache.containsKey(u))'));
      // [PAYROLL-V3-RECOVERY 갱신] 예전: bank 에도 'if (uncached.isEmpty) return;' — 그 줄이 지급 준비까지
      //   건너뛰었다. 캐시 미스일 때만 묻는 가드는 아래 _loadWorkerNames 하나로 충분하다.
      final bankOnly = _sliceOf(code, 'Future<void> _loadBankInfo(Set<String> uids) async {',
          'Future<void> _loadWorkerNames(');
      expect(_flat(bankOnly), isNot(contains('if (uncached.isEmpty) return;')));
      final names = _sliceOf(code, 'Future<void> _loadWorkerNames(',
          'Set<String> get _visibleWorkerUids');
      expect(_flat(names), contains('if (uncached.isEmpty) return;'));
    });

    test('PR-23 P1A 병렬 구조가 그대로다', () {
      // [PAYROLL-ALL-UNTRANSFERRED] 두 조회는 여전히 같은 Future.wait 안에서 함께 출발한다.
      //   '전체 미이체' 모드에서만 월 경로가 지급 준비를 쓰지 않는다(그 모드의 지급 준비는
      //   _loadAllOutstanding 하나가 쓴다). 실제 동작은 payroll_all_outstanding_critical_path_test PAO-M1·PAO-1.
      expect(f, contains('await Future.wait([ _loadWorkerNames(uncached), if (!widget.showAllOutstanding) _loadPayrollReadiness(uids), ])'));
    });
  });

  group('PR-3 — mutation별 무효화', () {
    test('PR-30 통장사본 검토 성공 → 판정만 다시 읽는다', () {
      final h = _flat(_sliceOf(code, 'Future<void> _reviewBankDocument(',
          'Future<void> _refreshSnapshots('));
      expect(h, contains('await _reloadReadiness();'));
      // 급여 목록을 통째로 다시 읽던 경로로 돌아가지 않는다
      expect(h.contains('_loadAllOutstanding()'), false);
      expect(h.contains('_load(withRequestTabs'), false);
    });

    test('PR-31 스냅샷 갱신 → 판정은 그대로, 급여 행만 다시 읽는다', () {
      final h = _flat(_sliceOf(code, 'Future<void> _refreshSnapshots(',
          'Future<void> _explainTransferBlocks('));
      expect(h, contains('await _loadAllOutstanding();'));
      expect(h, contains('_load(withRequestTabs: false)'));
      expect(h.contains('_reloadReadiness()'), false);
    });

    test('PR-32 일반 이체·지급방식 승인은 판정을 다시 읽지 않는다', () {
      for (final marker in [
        "ToastHelper.showSuccess('\$processedCount건 이체 완료 처리되었습니다')",
        "ToastHelper.showSuccess('변경 요청이 승인되었습니다')",
      ]) {
        final at = code.indexOf(marker);
        expect(at, greaterThan(-1), reason: marker);
        final win = code.substring(at, at + 400);
        expect(win.contains('_reloadReadiness'), false, reason: marker);
      }
      // 판정 재조회는 검토 경로 단 한 곳에서만 불린다 (정의 1 + 호출 1)
      expect('_reloadReadiness()'.allMatches(code).length, 2);
    });
  });

  group('PR-4 — 실패는 UNKNOWN 으로 남는다', () {
    final load = _sliceOf(code, 'Future<void> _loadPayrollReadiness(Set<String> uids)' /* [PAYROLL-V3-RECOVERY] guard 인자 제거 */,
        'bool _needsSnapshotRefresh(');
    final lf = _flat(load);

    test('PR-40 조회 실패를 READY 로 바꾸지 않는다', () {
      // [PAYROLL-V3-RECOVERY 갱신] 월 경로도 200명 분할 조회(_fetchReadinessAll)를 쓴다 — 같은 계약을 그 함수에서 본다.
      //   예전: batch = PayrollReadinessBatch.failed; / _readinessUnknown = batch.loadFailed ? uids.toSet() : batch.failedUids.toSet()
      expect(lf, contains('return PayrollReadinessBatch.failed;'));
      expect(lf, contains('if (b.loadFailed) { unknown.addAll(chunks[i]); continue; }'));
      expect(lf, contains('if (failed.contains(u) || info == null) { unknown.add(u);'), reason: '답에 없는 사람도 모름');
      expect(lf, contains('_readinessUnknown = r.unknown;'));
      expect(load.contains('ready: true'), false);
    });

    test('PR-41 UNKNOWN 은 CTA 도 문구도 추측하지 않는다', () {
      expect(f, contains('if (_readinessUnknown.contains(uid)) return false;'));
      expect(f, contains("if (_readinessUnknown.contains(uid)) return '지급 준비 상태 조회 실패';"));
    });

    test('PR-42 판정 실패가 은행 표시·급여 행을 지우지 않는다', () {
      // 판정 로더는 _allRecords / _userBankCache 를 건드리지 않는다
      expect(load.contains('_allRecords'), false);
      expect(load.contains('_userBankCache'), false);
      expect(load.contains('_outstandingAll'), false);
    });
  });

  group('PR-5 — 갱신이 화면을 빼앗지 않는다', () {
    final reload = _sliceOf(code, 'Future<void> _reloadReadiness() async {',
        'Future<void> _loadPayrollReadiness(');
    final load = _sliceOf(code, 'Future<void> _loadPayrollReadiness(Set<String> uids)' /* [PAYROLL-V3-RECOVERY] guard 인자 제거 */,
        'bool _needsSnapshotRefresh(');

    test('PR-50 전체 스피너를 띄우지 않는다', () {
      for (final body in [reload, load]) {
        expect(body.contains('_isLoading'), false);
        expect(body.contains('_loadError'), false);
      }
    });

    test('PR-51 늦게 온 응답이 최신 판정을 덮지 않는다', () {
      // [PAYROLL-V3-RECOVERY 갱신] 예전: 재조회 쪽이 순번을 매기고 guard 로 넘겼다. 이제 월 조회 경로(_loadBankInfo)도
      //   같은 보호가 필요해(월 이동 중 늦은 응답) 순번을 _loadPayrollReadiness 안에서 매긴다. 같은 계약이다.
      expect(_flat(load), contains('final seq = ++_readinessSeq;'));
      expect(_flat(load), contains('if (seq != _readinessSeq) return;'));
      expect(_flat(reload).contains('guard:'), false, reason: '바깥에서 한 번 더 순번을 올리면 안쪽 결과가 늘 버려진다');
    });

    test('PR-52 판정은 화면이 보여주는 근로자 전부를 함께 읽는다', () {
      // 부분 목록으로 부르면 clear 때문에 나머지 판정이 사라진다
      // [PAYROLL-V3-RECOVERY 갱신] 예전: addAll(batch.byUid) — 한 번에 묻고 take(200) 으로 잘렸다. 이제 200명씩 나눈 결과.
      expect(_flat(load), contains('_readiness ..clear() ..addAll(r.byUid)'));
      expect(_flat(load), contains('final r = await _fetchReadinessAll(uids);'));
      expect(_flat(reload), contains('final uids = _visibleWorkerUids;'));
      expect(f, contains('Set<String> get _visibleWorkerUids => { ..._allRecords.map((r) => r.userId), ..._outstandingAll.map((r) => r.userId), };'));
    });
  });

  group('PR-6 — 사업장 스코프와 서버 권위', () {
    test('PR-60 판정 조회는 이 화면의 businessId 로만 한다', () {
      // [PAYROLL-V3-RECOVERY 갱신] 월 경로도 200명 분할 조회(_fetchReadinessAll)를 쓴다 — 같은 계약을 그 함수에서 본다. 예전: workerUids: uids.toList()
      expect(f, contains('PayrollReadinessService.loadBatch( businessId: widget.businessId, workerUids: c)'));
    });

    test('PR-61 이체 허용은 여전히 서버가 정한다 — 판정은 표시용이다', () {
      // 클라이언트가 readiness 로 이체를 허용/차단하지 않는다
      final mark = _flat(_sliceOf(code, 'Future<void> _markWorker(',
          'Future<void> _markBatch('));
      expect(mark.contains('_readiness['), false);
      expect(mark.contains('_readinessUnknown'), false);
      // 서버가 제외 사유를 돌려주고 화면은 그것을 설명만 한다
      expect(f, contains('_explainTransferBlocks('));
    });

    test('PR-62 판정 자체를 클라이언트가 만들지 않는다', () {
      expect(code.contains('PayrollReadinessInfo('), false);
      expect(f, contains('PayrollReadinessService.loadBatch('));
    });
  });
}
