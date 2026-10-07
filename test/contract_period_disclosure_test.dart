// [R7-CONTRACT-PERIOD-DISCLOSURE] 종료일이 바뀐 사실을 당사자가 보는가.
//
// 서버는 확정할 때 이미 이것을 알고 저장한다 —
// `workEndDatePresentedAtApply`(지원 당시 본 값)와 `workEndDate`(적용값).
// 관리자에게는 알려 주면서 문구에 "지원자에게 안내가 필요할 수 있습니다"
// 라고 적어 뒀는데, 정작 지원자 쪽 reader 가 **0건**이었다. 날짜가 바뀐
// 당사자만 그 사실을 모른 채 계약서에서 바뀐 날짜를 보게 된다.
//
// 여기서 고정하는 것
//   P  판정 — 같으면 침묵, 다르면 고지, 제시값 없으면 단정 금지
//   S  출처 — 공고 현재값이 아니라 지원서 snapshot
//   U  화면 — before → after 가 보이고 계약 전에 확인 가능
//   A  관리자와 같은 사실을 말한다
//   R  반응형 — 날짜가 길어져도 넘치지 않는다
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ALfit/models/core/application_model.dart';
import 'package:ALfit/utils/format_helper.dart';
import 'package:ALfit/utils/period_revision_disclosure.dart';
import 'package:ALfit/utils/period_revision_notice.dart';
import 'package:ALfit/widgets/user/period_revision_notice_card.dart';

/// KST 자정 기준 instant.
DateTime _kst(int y, int m, int d) =>
    DateTime.utc(y, m, d).subtract(const Duration(hours: 9));

ApplicationModel _app({
  DateTime? presented,
  DateTime? applied,
}) =>
    ApplicationModel(
      id: 'app1',
      businessId: 'b1',
      businessName: '테스트사업장',
      toTitle: '장기 모집',
      workDate: _kst(2026, 10, 1),
      workEndDate: applied,
      workEndDatePresentedAtApply: presented,
      startTime: '09:00',
      endTime: '18:00',
      uid: 'u1',
      selectedWorkType: '피킹',
      wage: 12000,
      status: 'CONFIRMED',
      appliedAt: _kst(2026, 9, 20),
    );

Future<void> _pumpCard(
  WidgetTester t,
  PeriodRevisionDisclosure d, {
  Size size = const Size(360, 740),
  double scale = 1.0,
}) async {
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(
    builder: (ctx, child) => MediaQuery(
      data: MediaQuery.of(ctx).copyWith(textScaler: TextScaler.linear(scale)),
      child: child!,
    ),
    home: Scaffold(
      body: SingleChildScrollView(
        child: PeriodRevisionNoticeCard(disclosure: d),
      ),
    ),
  ));
  await t.pump();
}

void main() {
  // ── P. 판정 ────────────────────────────────────────────────────────

  test('P1 같은 날짜면 고지하지 않는다', () {
    final d = PeriodRevisionDisclosure.of(
        _app(presented: _kst(2026, 10, 31), applied: _kst(2026, 10, 31)));
    expect(d.shouldShow, isFalse);
  });

  test('P1b 같은 KST 달력일이면 시각이 달라도 고지하지 않는다', () {
    // 기기 자정과 KST 자정의 차이를 "변경" 이라고 부르지 않는다 —
    // 서버도 KST 달력일로 판정한다.
    final d = PeriodRevisionDisclosure.from(
      presented: _kst(2026, 10, 31),
      applied: _kst(2026, 10, 31).add(const Duration(hours: 5)),
    );
    expect(d.shouldShow, isFalse);
  });

  test('P2 다르면 고지한다', () {
    final d = PeriodRevisionDisclosure.of(
        _app(presented: _kst(2026, 10, 31), applied: _kst(2026, 11, 15)));
    expect(d.shouldShow, isTrue);
  });

  test('P3 before/after 날짜가 정확하다', () {
    final d = PeriodRevisionDisclosure.of(
        _app(presented: _kst(2026, 10, 31), applied: _kst(2026, 11, 15)));
    expect(d.presentedEndDate, _kst(2026, 10, 31));
    expect(d.appliedEndDate, _kst(2026, 11, 15));
  });

  test('P4 제시값이 없으면 "변경됨" 이라고 단정하지 않는다', () {
    // 적용값만 들고 바뀌었다고 할 수 없다 — 무엇에서 바뀌었는지 모른다.
    final d = PeriodRevisionDisclosure.of(
        _app(presented: null, applied: _kst(2026, 11, 15)));
    expect(d.shouldShow, isFalse);
    expect(d.presentedEndDate, isNull);
  });

  test('P5 적용값이 없어도 단정하지 않는다', () {
    final d = PeriodRevisionDisclosure.of(
        _app(presented: _kst(2026, 10, 31), applied: null));
    expect(d.shouldShow, isFalse);
  });

  // ── S. 출처 ────────────────────────────────────────────────────────

  String _code(String p) => File(p)
      .readAsStringSync()
      .split('\n')
      .where((l) => !l.trimLeft().startsWith('//'))
      .join('\n');

  test('S1 판정이 지원서 snapshot 만 본다 — 공고 현재값이 끼지 않는다', () {
    final c = _code('lib/utils/period_revision_disclosure.dart');
    expect(c.contains('TOModel'), isFalse, reason: '공고를 입력으로 받으면 안 된다');
    expect(c.contains('to.endDate'), isFalse);
    expect(c.contains('workEndDatePresentedAtApply'), isTrue);
  });

  test('S2 화면도 공고값으로 판정하지 않는다', () {
    final c = _code('lib/screens/user/my_applications_screen.dart');
    // 호출은 지원서 하나만 넘긴다.
    expect(c.contains('PeriodRevisionDisclosure.of(app)'), isTrue);
    // 화면이 직접 날짜를 비교하지 않는다.
    expect(c.contains('workEndDatePresentedAtApply'), isFalse,
        reason: '판정 규칙이 화면에 복제됐다');
  });

  test('S3 클라이언트가 이 필드를 쓰지 않는다 (읽기 전용)', () {
    final model = File('lib/models/core/application_model.dart')
        .readAsStringSync();
    final i = model.indexOf('Map<String, dynamic> toMap()');
    final j = model.indexOf('\n  }', i);
    final toMap = model.substring(i, j);
    expect(toMap.contains('workEndDatePresentedAtApply'), isFalse,
        reason: 'writer 는 CF 하나다');
    expect(toMap.contains('workEndDateRevisedAt'), isFalse);
  });

  // ── U. 화면 ────────────────────────────────────────────────────────

  testWidgets('U1 고지가 없으면 아무것도 그리지 않는다', (t) async {
    await _pumpCard(t, PeriodRevisionDisclosure.none);
    expect(find.byType(Container), findsNothing);
    expect(t.takeException(), isNull);
  });

  testWidgets('U2 before → after 가 둘 다 보인다', (t) async {
    await _pumpCard(
        t,
        PeriodRevisionDisclosure.from(
            presented: _kst(2026, 10, 31), applied: _kst(2026, 11, 15)));
    expect(find.text('근무 종료일이 변경되었습니다'), findsOneWidget);

    // "다르다" 만 보면 **뒤집혀도 통과한다**(변이 D3 이 그것을 잡아냈다).
    //   어느 쪽이 어느 날짜인지까지 못박는다 — 뒤집히면 사용자는 정반대로
    //   이해한다.
    final expectedBefore = FormatHelper.formatDateCompact(_kst(2026, 10, 31));
    final expectedAfter = FormatHelper.formatDateCompact(_kst(2026, 11, 15));
    expect(expectedBefore, isNot(expectedAfter), reason: '표본이 구별돼야 한다');

    final before = t.widget<Text>(find.textContaining('지원 당시')).data!;
    final after = t.widget<Text>(find.textContaining('현재 적용')).data!;
    expect(before, contains(expectedBefore),
        reason: '"지원 당시" 자리에 제시값이 와야 한다');
    expect(after, contains(expectedAfter),
        reason: '"현재 적용" 자리에 적용값이 와야 한다');
    expect(before, isNot(contains(expectedAfter)));
    expect(t.takeException(), isNull);
  });

  testWidgets('U3 계약이 변경됐다고 말하지 않는다 — 아직 계약이 아니다', (t) async {
    await _pumpCard(
        t,
        PeriodRevisionDisclosure.from(
            presented: _kst(2026, 10, 31), applied: _kst(2026, 11, 15)));
    expect(find.textContaining('계약이 변경'), findsNothing);
    expect(find.textContaining('계약 전에'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  test('U4 계약 전에 확인할 수 있는 자리에 있다', () {
    // 내 지원 화면은 확정 직후부터 계약 서명 전까지 언제든 열 수 있다.
    final c = _code('lib/screens/user/my_applications_screen.dart');
    expect(c.contains('PeriodRevisionNoticeCard('), isTrue);
  });

  // ── A. 관리자 parity ───────────────────────────────────────────────

  test('A1 관리자와 같은 두 값을 말한다', () {
    final presented = _kst(2026, 10, 31);
    final applied = _kst(2026, 11, 15);
    final adminMsg = periodRevisionMessage(
        presented: presented, applied: applied, applicantName: '김근로');
    final d =
        PeriodRevisionDisclosure.from(presented: presented, applied: applied);

    expect(d.shouldShow, isTrue);
    // 관리자 문구에도 같은 두 날짜가 들어간다.
    expect(adminMsg.contains('2026-10-31'), isTrue);
    expect(adminMsg.contains('2026-11-15'), isTrue);
    expect(d.presentedEndDate, presented);
    expect(d.appliedEndDate, applied);
  });

  test('A2 관리자 쪽 "지원자 안내 필요" 문구가 유지된다', () {
    // 이 Phase 는 관리자 writer·문구를 바꾸지 않는다.
    final c = _code('lib/utils/period_revision_notice.dart');
    expect(c.contains('지원자에게 안내가 필요할 수 있습니다'), isTrue);
  });

  // ── R. 반응형 ──────────────────────────────────────────────────────

  testWidgets('R1 좁은 폭 × 큰 배율에서 넘치지 않는다', (t) async {
    final d = PeriodRevisionDisclosure.from(
        presented: _kst(2026, 12, 31), applied: _kst(2027, 1, 15));
    for (final w in [320.0, 360.0, 411.0]) {
      for (final scale in [1.0, 1.3, 2.0]) {
        await _pumpCard(t, d, size: Size(w, 740), scale: scale);
        expect(t.takeException(), isNull,
            reason: '${w.toInt()}dp × $scale');
      }
    }
  });
}
