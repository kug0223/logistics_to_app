// [R8-P1A] 급여 화면의 이름 조회와 지급 준비 조회는 서로를 기다리지 않는다.
//
//   둘 다 uids + businessId 만 있으면 되는데 직렬로 붙어 있어서 왕복 한 번이
//   그냥 더 들었다. 병렬로 바꾸되, 한쪽 실패가 다른 쪽 결과나 급여 목록을
//   지우지 않는다는 기존 의미는 그대로 지킨다.
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

String _src() => File(
    'lib/screens/business_admin/payroll/payroll_payment_dashboard_screen.dart')
    .readAsStringSync();
String _svc() => File(
    'lib/services/payroll_readiness_service.dart').readAsStringSync();

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

void main() {
  final raw = _src();
  final code = _codeOf(raw);
  final f = _flat(code);

  group('PL-1 — 두 조회가 병렬로 돈다', () {
    test('PL-10 이름 조회가 독립 함수로 분리됐다', () {
      expect(f, contains('Future<void> _loadWorkerNames(List<String> uncached)'));
    });

    test('PL-11 둘을 함께 기다린다', () {
      final bank = _sliceOf(code, 'Future<void> _loadBankInfo(Set<String> uids)',
          'Future<void> _loadWorkerNames(');
      final bf = _flat(bank);
      expect(bf, contains('await Future.wait([ _loadWorkerNames(uncached), _loadPayrollReadiness(uids), ])'));
    });

    test('PL-12 직렬 호출이 남아 있지 않다', () {
      // 이전 구조: getUsersBatch 끝난 뒤 await _loadPayrollReadiness(uids)
      final bank = _sliceOf(code, 'Future<void> _loadBankInfo(Set<String> uids)',
          'Future<void> _loadWorkerNames(');
      expect(_flat(bank), isNot(contains('getUsersBatch')));
    });
  });

  group('PL-2 — 의존성이 없다는 것이 코드로 보인다', () {
    test('PL-20 지급 준비 조회는 uids 와 businessId 만 쓴다', () {
      final rd = _sliceOf(code, 'Future<void> _loadPayrollReadiness(Set<String> uids,',
          'bool _needsSnapshotRefresh(');
      final rf = _flat(rd);
      expect(rf, contains('workerUids: uids.toList()'));
      expect(rf, contains('businessId: widget.businessId'));
      // 이름 조회 결과(_userBankCache)를 읽지 않는다
      expect(rf, isNot(contains('_userBankCache')));
    });

    test('PL-21 이름 조회는 지급 준비 결과를 읽지 않는다', () {
      final nm = _sliceOf(code, 'Future<void> _loadWorkerNames(List<String> uncached)',
          'Set<String> get _visibleWorkerUids');
      expect(_flat(nm), isNot(contains('_readiness')));
    });
  });

  group('PL-3 — 실패는 서로 독립이다', () {
    test('PL-30 이름 조회 실패가 밖으로 나가지 않는다', () {
      final nm = _sliceOf(code, 'Future<void> _loadWorkerNames(List<String> uncached)',
          'Set<String> get _visibleWorkerUids');
      expect(_flat(nm), contains('} catch (e) {'));
      expect(_flat(nm), contains('근로자 이름 배치 로드 실패'));
    });

    test('PL-31 지급 준비 실패도 밖으로 나가지 않는다', () {
      final rd = _sliceOf(code, 'Future<void> _loadPayrollReadiness(Set<String> uids,',
          'bool _needsSnapshotRefresh(');
      final rf = _flat(rd);
      expect(rf, contains('} catch (e) {'));
      expect(rf, contains('batch = PayrollReadinessBatch.failed'));
    });

    test('PL-32 서비스 자체도 실패를 삼켜 failed 배치를 돌려준다', () {
      expect(_flat(_codeOf(_svc())), contains('return PayrollReadinessBatch.failed'));
    });

    test('PL-33 모르는 것을 "확인 필요"로 바꾸지 않는다', () {
      final rd = _sliceOf(code, 'Future<void> _loadPayrollReadiness(Set<String> uids,',
          'bool _needsSnapshotRefresh(');
      expect(_flat(rd), contains('_readinessUnknown = batch.loadFailed ? uids.toSet() : batch.failedUids.toSet()'));
    });
  });

  group('PL-4 — 급여 목록 자체는 영향받지 않는다', () {
    test('PL-40 급여 레코드 로드는 별도 단계 그대로다', () {
      expect(f, contains('final results = await Future.wait([ _payService.getPayrollRecords('));
    });

    test('PL-41 ERROR 를 0건으로 위장하지 않는 기존 상태가 유지된다', () {
      expect(f, contains("_loadError = '급여 현황을 불러오지 못했습니다.'"));
    });

    test('PL-42 캐시 가드(기존 동작)를 바꾸지 않았다', () {
      final bank = _sliceOf(code, 'Future<void> _loadBankInfo(Set<String> uids)',
          'Future<void> _loadWorkerNames(');
      expect(_flat(bank), contains('if (uncached.isEmpty) return'));
    });
  });

  group('PL-5 — 중복 호출이 없다', () {
    test('PL-50 지급 준비 조회 호출부는 한 곳뿐이다', () {
      // [R8-P2.1] 정의 1 + _loadBankInfo(첫 로드) 1 + _reloadReadiness(검토 후) 1.
      //   판정만 다시 읽는 경로가 생겼을 뿐, 중복 호출은 여전히 없다.
      expect('_loadPayrollReadiness('.allMatches(code).length, 3);
    });

    test('PL-51 mounted 가드가 유지된다', () {
      final rd = _sliceOf(code, 'Future<void> _loadPayrollReadiness(Set<String> uids,',
          'bool _needsSnapshotRefresh(');
      expect(_flat(rd), contains('if (!mounted) return'));
    });
  });
}
