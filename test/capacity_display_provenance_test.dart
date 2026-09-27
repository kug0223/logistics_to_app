// [CORRECTION-R7-PARTIAL-LOCAL-CAPACITY-AUTHORITY] 잔여 — **표시**까지 막는다.
//
//   DEVICE.1E.2 는 판단(FULL·부족·초대)에서 확인되지 않은 값을 막았다.
//   그러나 표시용 창구(`displayConfirmedFor`)를 함께 열어 두었고, 그 유일한
//   caller 가 이렇게 적고 있었다.
//
//       '처리를 반영했어요. 인력 현황을 다시 확인하는 중이에요. (충원 15)'
//
//   그 15 는 내가 직접 "wdId 충돌로 나올 수 있다"고 증명한 수다. 화면이
//   `갱신 중` 이라고 덧붙여도 관리자는 그것을 현재 충원으로 읽는다.
//
//   그래서 창구를 없애고, 정원 문구를 그리는 production widget 을 실행해서
//   그 숫자가 **렌더에 없다**는 것을 확인한다 — getter 를 읽거나 소스를
//   정규식으로 훑는 것으로는 증명되지 않는다.

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ALfit/models/core/work_detail_data.dart';
import 'package:ALfit/models/ui/capacity_load_state.dart';
import 'package:ALfit/models/ui/invite_capacity_state.dart';
import 'package:ALfit/widgets/admin/capacity_summary_text.dart';

const _key = '사무업무_06:00_08:00';
const _required = 12;

WorkDetailData _work() => WorkDetailData(
      workType: '사무업무',
      startTime: '06:00',
      endTime: '08:00',
      requiredCount: _required,
      wage: 12000,
    );

Map<String, dynamic> _canonical(int confirmed) => {
      'workDetails': [_work()],
      'workStats': {
        _key: {'confirmed': confirmed, 'pending': 0}
      },
      'statsFailed': false,
    };

Map<String, dynamic> _failedRead() => {
      'workDetails': [_work()],
      'workStats': {
        _key: {'confirmed': 0, 'pending': 0}
      },
      'statsFailed': true,
    };

/// wdId 충돌로 화면이 과대 집계한 값.
Map<String, Map<String, int>> _collidingLocal(int confirmed) => {
      _key: {'confirmed': confirmed, 'pending': 0}
    };

/// production widget 을 **그대로** 그린다. 화면의 그 자리와 같은 component 다.
Future<void> _pumpCapacityLine(
  WidgetTester tester,
  CapacityLoadState cap, {
  bool isClosed = false,
}) async {
  final work = _work();
  // 화면이 쓰는 파생 경로를 그대로 통과시킨다.
  final capacity = inviteCapacityStateOf(
    canonicalConfirmed: cap.confirmedFor(work),
    requiredCount: work.requiredCount,
    isClosed: isClosed,
  );
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: CapacitySummaryText(
        requiredCount: work.requiredCount,
        capacity: capacity,
        isPending: cap.isPending,
      ),
    ),
  ));
}

/// 화면에 적힌 모든 텍스트.
List<String> _rendered(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text))
    .map((t) => t.data ?? '')
    .toList();

/// 렌더된 텍스트 어디에도 이 숫자가 없다.
void _expectNoNumber(WidgetTester tester, int n) {
  final all = _rendered(tester).join(' | ');
  expect(RegExp(r'(?<!\d)' + n.toString() + r'(?!\d)').hasMatch(all), isFalse,
      reason: '확인되지 않은 수 $n 이 화면에 적혔다: $all');
}

String _read(String p) => File(p).readAsStringSync();

void main() {
  // ══════════════════════════════════════════════════════════════
  // CDP-0. 위 단정이 공허하지 않다는 확인
  //
  //   `_expectNoNumber` 가 아무것도 못 잡는 함수라면 아래 전부가 의미 없이
  //   통과한다. 실제로 렌더된 숫자(12)는 반드시 잡혀야 한다.
  // ══════════════════════════════════════════════════════════════

  testWidgets('CDP-0 숫자 탐지가 실제로 동작한다', (tester) async {
    final cap = CapacityLoadState(loader: () async => _canonical(11));
    cap.seed(_collidingLocal(10), parentFailed: false);
    await _pumpCapacityLine(tester, cap);

    expect(_rendered(tester).join(' | '), contains('필요 12명'));
    // 렌더된 12 는 잡혀야 한다 — 잡지 못하면 이 파일의 단정이 전부 공허하다.
    var caught = false;
    try {
      _expectNoNumber(tester, 12);
    } on TestFailure {
      caught = true;
    }
    expect(caught, isTrue, reason: '_expectNoNumber 가 렌더된 숫자를 놓친다');
  });

  // ══════════════════════════════════════════════════════════════
  // §4-1. canonical 10/12 → 충돌 local 15 → 지연된 canonical 11
  // ══════════════════════════════════════════════════════════════

  testWidgets('CDP-1 충돌 local 15 가 중간 화면에서 현재 total 로 노출되지 않는다',
      (tester) async {
    final gate = Completer<Map<String, dynamic>>();
    final cap = CapacityLoadState(loader: () => gate.future);
    cap.seed(_collidingLocal(10), parentFailed: false); // canonical 출처

    // ── 시작: canonical 10 / 필요 12 ──
    await _pumpCapacityLine(tester, cap);
    expect(find.text('필요 12명'), findsOneWidget);
    expect(find.text('갱신 중'), findsNothing);
    expect(find.text('정원 확인 불가'), findsNothing);

    // ── mutation 성공 → 화면이 손으로 다시 셌고 wdId 충돌로 15 가 됐다 ──
    cap.applyLocal(_collidingLocal(15));
    await _pumpCapacityLine(tester, cap);

    _expectNoNumber(tester, 15);
    expect(find.text('필요 12명'), findsOneWidget,
        reason: '공고가 정한 값은 조회 상태와 무관하게 유효하다 — 감추지 않는다');
    expect(find.text('갱신 중'), findsOneWidget);
    expect(find.text('정원 확인 불가'), findsNothing,
        reason: '성공한 처리를 실패처럼 말하지 않는다');

    // 판단 차단도 그대로 유지된다(1E.2 에서 증명한 계약).
    expect(cap.confirmedFor(_work()), isNull);
    expect(
        inviteCapacityStateOf(
            canonicalConfirmed: cap.confirmedFor(_work()),
            requiredCount: _required),
        InviteCapacityState.unknown,
        reason: '필요 12 에 15 로 FULL 을 확정하면 초대 경로가 사라진다');

    // ── canonical 11 도착 ──
    gate.complete(_canonical(11));
    await cap.load();
    await _pumpCapacityLine(tester, cap);

    expect(find.text('필요 12명'), findsOneWidget);
    expect(find.text('갱신 중'), findsNothing);
    expect(cap.confirmedFor(_work()), 11, reason: '이제는 판단해도 되는 값이다');
  });

  // ══════════════════════════════════════════════════════════════
  // §4-2. canonical 이 한 번도 없음 + local 15
  // ══════════════════════════════════════════════════════════════

  testWidgets('CDP-2 canonical 없이 local 15 나 임의 0 을 total 로 주장하지 않는다',
      (tester) async {
    final cap = CapacityLoadState(loader: () async => _canonical(11));
    cap.applyLocal(_collidingLocal(15)); // canonical 조회 전

    await _pumpCapacityLine(tester, cap);

    _expectNoNumber(tester, 15);
    _expectNoNumber(tester, 0);
    expect(find.text('필요 12명'), findsOneWidget);
    expect(find.text('갱신 중'), findsOneWidget);
    expect(cap.confirmedFor(_work()), isNull);
    // 없는 이전 snapshot 을 local 값으로 대신하지 않는다.
    expect(cap.isCanonical, isFalse);
  });

  testWidgets('CDP-2b 아무 값도 없으면 확인 불가로 말한다', (tester) async {
    final cap = CapacityLoadState(loader: () async => _canonical(11));
    await _pumpCapacityLine(tester, cap);
    expect(find.text('필요 12명'), findsOneWidget,
        reason: '필요 인원은 독립적으로 유효하다');
    expect(find.text('정원 확인 불가'), findsOneWidget);
    expect(find.text('갱신 중'), findsNothing);
  });

  // ══════════════════════════════════════════════════════════════
  // §4-3. refresh 실패 → retry 성공
  // ══════════════════════════════════════════════════════════════

  testWidgets('CDP-3 실패에 잘못된 local 표시가 남지 않고, retry 가 정원만 회복한다',
      (tester) async {
    var reads = 0;
    final cap = CapacityLoadState(loader: () async {
      reads++;
      return reads == 1 ? _failedRead() : _canonical(11);
    });
    cap.seed(_collidingLocal(10), parentFailed: false);
    cap.applyLocal(_collidingLocal(15)); // mutation 성공

    // ── 정원 갱신 실패 ──
    await cap.load();
    await _pumpCapacityLine(tester, cap);

    _expectNoNumber(tester, 15);
    _expectNoNumber(tester, 10); // 덮여 사라진 옛 canonical 도 되살리지 않는다
    expect(find.text('필요 12명'), findsOneWidget);
    expect(find.text('정원 확인 불가'), findsOneWidget,
        reason: '이제는 오류 표현이 맞다');
    expect(find.text('갱신 중'), findsNothing);
    expect(cap.failed, isTrue);

    // ── retry 성공 ──
    await cap.load();
    await _pumpCapacityLine(tester, cap);

    expect(reads, 2, reason: '정원 조회만 다시 했다');
    expect(find.text('필요 12명'), findsOneWidget);
    expect(find.text('정원 확인 불가'), findsNothing);
    expect(cap.confirmedFor(_work()), 11);

    // 도메인 처리를 다시 하지 않는다 — 이 상태기계는 writer 를 갖지 않는다.
    final src = _read('lib/models/ui/capacity_load_state.dart');
    for (final banned in ['callable', 'FirebaseFunctions', '.set(', '.update(']) {
      expect(src.contains(banned), isFalse, reason: '도메인 재실행 수단: $banned');
    }
  });

  // ══════════════════════════════════════════════════════════════
  // 창구 자체가 사라졌다 — 같은 실수가 반복될 자리를 남기지 않는다
  // ══════════════════════════════════════════════════════════════

  group('CDP-W wiring (보조 증거)', () {
    test('CDP-W1 출처를 묻지 않는 확정 수 창구가 없다', () {
      final s = _read('lib/models/ui/capacity_load_state.dart');
      expect(s.contains('int? displayConfirmedFor('), isFalse);
      // 확정 수를 읽는 창구는 하나이고 canonical 일 때만 답한다.
      expect(s.contains('if (!_isCanonical) return null;'), isTrue);
    });

    test('CDP-W2 갱신 중 안내에 숫자도 재시도도 없다', () {
      final dlg =
          _read('lib/screens/business_admin/dialogs/work_applicants_dialog.dart');
      final i = dlg.indexOf('Widget _buildCapacityPendingNotice(');
      final j = dlg.indexOf('Widget _buildCapacityUnknownNotice(');
      expect(i, greaterThan(-1));
      final pending = dlg.substring(i, j);
      expect(pending.contains('충원 \$'), isFalse);
      expect(pending.contains('displayConfirmedFor'), isFalse);
      expect(pending.contains('다시 시도'), isFalse,
          reason: '여기서 재시도를 권하면 도메인 처리를 다시 하라는 말로 읽힌다');
    });
  });
}
