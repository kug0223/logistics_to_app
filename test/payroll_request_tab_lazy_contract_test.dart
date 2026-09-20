// [R8-P1B] 급여 화면이 나오는 것을 요청 탭 두 개가 기다리게 하지 않는다.
//
//   급여 조회는 50ms대인데 변경요청·중간정산 CF는 각각 500ms를 넘는다.
//   넷을 함께 기다리는 동안 화면 전체가 스피너였고, 그 시간을 정한 것은
//   정작 지금 보고 있지 않은 탭의 데이터였다.
//
//   다만 탭 배지가 그 값을 쓰므로 아예 안 부르지는 않는다. 받기 전에는
//   "없음"이 아니라 "모름"이라고 말한다.
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

String _src() => File(
    'lib/screens/business_admin/payroll/payroll_payment_dashboard_screen.dart')
    .readAsStringSync();

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

  group('RT-1 — 첫 화면은 급여만 기다린다', () {
    final load = _sliceOf(code, 'Future<void> _load() async {',
        'Future<void> _loadRequestTabs() async {');
    final lf = _flat(load);

    test('RT-10 base 단계에 급여 조회 둘만 있다', () {
      expect(lf, contains('final results = await Future.wait([ _payService.getPayrollRecords('));
      expect(lf, isNot(contains('getPendingChangeRequests')));
      expect(lf, isNot(contains('getPendingSettlementRequests')));
    });

    test('RT-11 요청 탭 로드는 기다리지 않는다', () {
      expect(lf, contains('unawaited(_loadRequestTabs())'));
    });

    test('RT-12 스피너를 끄는 것은 base 완료 시점이다', () {
      expect(lf, contains('_isLoading = false'));
      final offAt = load.indexOf('_isLoading = false');
      final secAt = load.indexOf('unawaited(_loadRequestTabs())');
      expect(offAt, lessThan(secAt), reason: '요청 탭보다 먼저 화면이 나온다');
    });
  });

  group('RT-2 — 두 요청은 서로 독립이다', () {
    final sec = _sliceOf(code, 'Future<void> _loadRequestTabs() async {',
        'Future<void> _loadAllOutstanding() async {');
    final sf = _flat(sec);

    test('RT-20 둘을 병렬로 낸다', () {
      expect(sf, contains('await Future.wait(['));
      expect(sf, contains('getPendingChangeRequests(widget.businessId)'));
      expect(sf, contains('getPendingSettlementRequests(widget.businessId)'));
    });

    test('RT-21 각자 자기 실패를 자기 안에서 끝낸다', () {
      expect('.catchError('.allMatches(sec).length, 2);
      expect(sf, contains("_changeRequestsError = '변경 요청을 불러오지 못했습니다.'"));
      expect(sf, contains("_settlementRequestsError = '중간정산 요청을 불러오지 못했습니다.'"));
    });

    test('RT-22 성공한 쪽만 loaded 로 올린다', () {
      expect(sf, contains('_changeRequests = v; _changeRequestsLoaded = true;'));
      expect(sf, contains('_settlementRequests = v; _settlementsLoaded = true;'));
    });

    test('RT-23 급여 목록 실패 상태와 섞이지 않는다', () {
      expect(sf, isNot(contains('_loadError')));
      expect(sf, isNot(contains('_isLoading')));
    });
  });

  group('RT-3 — 모름을 0건이라고 말하지 않는다', () {
    test('RT-30 배지는 받기 전에는 그리지 않는다', () {
      expect(f, contains('count: _changeRequestsLoaded ? _changeRequests.length : null'));
      expect(f, contains('count: _settlementsLoaded ? _settlementRequests.length : null'));
    });

    test('RT-31 변경요청 탭이 미수신을 "없음"으로 그리지 않는다', () {
      final tab = _sliceOf(code, 'Widget _buildChangeRequestTab() {',
          'Widget _buildSettlementTab() {');
      final tf = _flat(tab);
      final notLoadedAt = tab.indexOf('if (!_changeRequestsLoaded)');
      final emptyAt = tab.indexOf("title: '지급방식 변경 요청이 없습니다'");
      expect(notLoadedAt, greaterThan(-1));
      expect(notLoadedAt, lessThan(emptyAt), reason: '미수신 분기가 없음 분기보다 앞');
      expect(tf, contains('변경 요청 불러오는 중'));
    });

    test('RT-32 중간정산 탭도 같다', () {
      final tab = _sliceOf(code, 'Widget _buildSettlementTab() {',
          'class _NavArrow extends StatelessWidget');
      final tf = _flat(tab);
      expect(tab.indexOf('if (!_settlementsLoaded)'), greaterThan(-1));
      expect(tf, contains('중간정산 요청 불러오는 중'));
    });

    test('RT-33 실패하면 다시 시도할 길이 있다', () {
      expect('unawaited(_loadRequestTabs())'.allMatches(code).length, 3); // _load 1 + 재시도 2
      expect(f, contains("child: const Text('다시 시도')"));
    });
  });

  group('RT-4 — 중복 호출 방지', () {
    final sec = _sliceOf(code, 'Future<void> _loadRequestTabs() async {',
        'Future<void> _loadAllOutstanding() async {');
    test('RT-40 진행 중이면 다시 내지 않는다', () {
      expect(_flat(sec), contains('if (_requestTabsInFlight) return'));
    });

    test('RT-41 끝나면 플래그를 내린다 — 재시도가 막히지 않는다', () {
      expect(_flat(sec), contains('setState(() => _requestTabsInFlight = false)'));
    });

    test('RT-42 실패해도 loaded 를 true 로 고정하지 않는다', () {
      // catchError 경로에서 loaded 를 세우지 않는다
      final catches = sec.split('.catchError(');
      for (final c in catches.skip(1)) {
        final body = c.substring(0, c.indexOf('}),') + 1);
        expect(body.contains('Loaded = true'), false);
      }
    });
  });

  group('RT-5 — P1A 구조가 유지된다', () {
    test('RT-50 users/readiness 병렬이 그대로다', () {
      expect(f, contains('await Future.wait([ _loadWorkerNames(uncached), _loadPayrollReadiness(uids), ])'));
    });

    test('RT-51 급여 실패는 여전히 화면 상태로 남는다', () {
      expect(f, contains("_loadError = '급여 현황을 불러오지 못했습니다.'"));
    });

    test('RT-52 mutation 후 갱신 경로는 그대로 _load() 다', () {
      // 승인/거절 후 _load() 가 base + 요청 탭을 함께 되살린다
      expect(f, contains('await _payService.approveChangeRequest('));
      expect(f, contains('_load();'));
    });
  });
}
