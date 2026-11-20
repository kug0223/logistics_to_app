// [DU1 SubAdmin §3] 급여 권한만 가진 관리자의 일자 급여 분류 adapter (LOCAL).
//   WD-1 급여창 _initData 와 같은 술어·순서(퇴근 없음 먼저, 마감은 adminConfirmed 무관, 미확인은 인력 확인 필요)
//   WD-2 KST 하루 창(전날로 넓히지 않음) · 다른 KST 날·다른 사업장 행 제외 · 비KST 기기 무관
//   WD-3 같은 지원서 근태 2건 → 정본 id 우선, 정본 없으면 모호로 남김
//   WD-4 상한 도달 → throw(0 아님) · 파싱 실패/모호 → isComplete=false · 출근 없음 → missingCheckIn(처리 가능 아님)
//   WD-5 금지 경로 소스 계약 — workerOperation/capacity 목적·지원서 문서 GET 을 쓰지 않는다
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ALfit/screens/business_admin/dialogs/wage_day_inputs_loader.dart';

Timestamp _kst(int y, int m, int d, [int hh = 0, int mm = 0]) =>
    Timestamp.fromMillisecondsSinceEpoch(DateTime.utc(y, m, d, hh, mm).millisecondsSinceEpoch - 9 * 3600 * 1000);

Map<String, dynamic> _a(String appId, String ws,
        {bool out = true, bool inn = true, bool confirmed = true, String biz = 'b1', int day = 3, String? id, String uid = 'u'}) =>
    {
      'id': id ?? '${appId}_202611${day.toString().padLeft(2, '0')}',
      'applicationId': appId,
      'userId': '$uid$appId',
      'businessId': biz,
      'businessName': 'B',
      'workDate': _kst(2026, 11, day),
      'workType': 'QA',
      if (inn) 'checkIn': _kst(2026, 11, day, 9),
      if (out) 'checkOut': _kst(2026, 11, day, 18),
      'status': 'present',
      'wageStatus': ws,
      'adminConfirmed': confirmed,
      'createdAt': _kst(2026, 11, day, 9),
    };

final _day = DateTime(2026, 11, 3);

WageDayClassification _c(List<Map<String, dynamic>> items, {bool limit = false}) =>
    WageDayInputsAdapter.classify(items: items, limitReached: limit, businessId: 'b1', civilDay: _day);

void main() {
  test('WD-1 분류 술어 — 급여창 _initData 와 같은 순서', () {
    final r = _c([
      _a('p1', 'pending'),
      _a('p2', 'pending'),
      _a('c1', 'calculated'),
      _a('s1', 'confirmed', confirmed: false), // 마감은 adminConfirmed 무관
      _a('s2', 'transferred'),
      _a('n1', 'pending', confirmed: false), // 근태 확인 전
      _a('n2', 'calculated', confirmed: false),
      _a('n3', 'pending', out: false), // 퇴근 전
      _a('x1', 'confirmed', out: false), // 마감이지만 퇴근 없음 → 창에 없음
      _a('o1', 'weird'),
      _a('m1', 'pending', inn: false), // 출근 시각 없음 → 계산 실패, 처리 가능 아님
    ]);
    expect(r.pending, 2);
    expect(r.calculated, 1);
    expect(r.wageTabRows, 4, reason: '실제 탭 편입 — 출근 기록 없는 pending 도 탭에 들어간다');
    expect(r.tabRowsWithCheckIn, 3);
    expect(r.missingCheckIn, 1);
    expect(r.isComplete, isTrue);
    expect(r.applicationVerified, isFalse, reason: '지원서·약속은 확인하지 못한다 — 처리 가능 보증 아님');
    expect(r.settled, 2);
    expect(r.needsWorkerOps, 3);
    expect(r.settledWithoutCheckout, 1);
    expect(r.otherStatus, 1);
    expect(r.userIds.length, 11);
    expect(WageDayClassification.scheduleFieldsUnavailable,
        containsAll(<String>['toId', 'slotId', 'workDetailId', 'startTime', 'endTime']));
  });

  test('WD-2 KST 하루 창 · 다른 날/사업장 제외 · 날짜 키', () {
    final w = WageDayInputsAdapter.queryWindow(_day);
    expect(w.endMs - w.startMs, 24 * 3600 * 1000);
    expect(w.startMs, _kst(2026, 11, 3).millisecondsSinceEpoch, reason: '전날로 넓히지 않는다');
    expect(WageDayInputsAdapter.instantDayKey(_kst(2026, 11, 3).toDate()), '20261103',
        reason: 'KST 자정 instant 는 기기 시간대와 무관하게 그 날');
    // 달력일 입력은 성분 기준 — local/UTC 어느 DateTime 이든 같은 창·키(UTC+13 기기에서 instant 해석하면 전날이 된다)
    expect(WageDayInputsAdapter.civilDayKey(DateTime(2026, 11, 3)), '20261103');
    expect(WageDayInputsAdapter.civilDayKey(DateTime.utc(2026, 11, 3)), '20261103');
    expect(WageDayInputsAdapter.queryWindow(DateTime.utc(2026, 11, 3)), WageDayInputsAdapter.queryWindow(DateTime(2026, 11, 3)));
    // 비KST 반례: UTC+13 기기의 local 11/3 자정 = 2026-11-02T11:00Z 를 instant 로 읽으면 KST 11/2 다 — civil 경로는 그 값을 받지 않는다
    final plus13Midnight = DateTime.utc(2026, 11, 2, 11);
    expect(WageDayInputsAdapter.instantDayKey(plus13Midnight), '20261102', reason: 'instant 해석은 하루가 밀린다(그래서 civil 입력을 분리)');
    final r = _c([_a('a', 'pending'), _a('b', 'pending', day: 2), _a('c', 'pending', biz: 'other')]);
    expect(r.pending, 1);
  });

  test('WD-3 같은 지원서 근태 2건 — 정본 id 우선, 없으면 모호', () {
    final ok = _c([_a('a', 'pending', id: 'stray1'), _a('a', 'calculated')]);
    expect(ok.calculated, 1);
    expect(ok.pending, 0);
    expect(ok.ambiguousApplicationIds, isEmpty);
    final amb = _c([_a('a', 'pending', id: 'stray1'), _a('a', 'pending', id: 'stray2')]);
    expect(amb.ambiguousApplicationIds, {'a'});
    expect(amb.wageTabRows, 0, reason: '조용히 하나를 고르지 않는다');
    expect(amb.isComplete, isFalse, reason: '모호가 있으면 0 을 정상 0 으로 말하지 않는다');
  });

  test('WD-4 상한 도달은 모름 — throw / 파싱 실패는 불완전', () {
    expect(() => _c([_a('a', 'pending')], limit: true), throwsStateError);
    final bad = _c([<String, dynamic>{'id': 'x', 'businessId': 'b1'}]);
    expect(bad.unparsed, 1);
    expect(bad.isComplete, isFalse);
    expect(bad.wageTabRows, 0);
  });

  test('WD-5 금지 경로를 쓰지 않는다(소스 계약)', () {
    final src = File('lib/screens/business_admin/dialogs/wage_day_inputs_loader.dart')
        .readAsLinesSync()
        .where((l) => !l.trimLeft().startsWith('//'))
        .join('\n');
    for (final banned in ["'workerOperation'", "'capacity'", "collection('applications')", 'callableGetApplicationsByBiz']) {
      expect(src.contains(banned), isFalse, reason: banned);
    }
  });
}
