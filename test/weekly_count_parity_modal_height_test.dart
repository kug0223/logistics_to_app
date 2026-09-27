// [VERIFY-R7-DAY-DIALOG-WEEKLY-COUNT-PARITY] + 모달 높이 계약
//
//   같은 사람·같은 날짜인데 두 화면이 다른 수를 말했다.
//
//     공고탭 인력 현황   주1회
//     홈 일자별 현황     주0회
//
//   DEV 실측(uid tJ8izf… / businessId fLmSOHVKUwmBHcbwQE0I)으로 확인한
//   출근 문서는 11건이고, 그중 세어야 하는 것은 아래 5일이다.
//
//     9/16 present · 9/18 present(같은 날 NO_SHOW 1건 더 있음)
//     9/20 present ×4  ← 같은 날 문서가 4건
//     9/21 present · 9/22 present
//     9/14 NO_SHOW · 9/26 NO_SHOW
//
//   여기에 주간 창을 달리 잡으면 이렇게 갈린다.
//
//     9/22~9/28  → 1      (화면 A 가 말한 값)
//     9/28~10/04 → 0      (화면 B 가 말한 값)
//     9/21~9/27  → 2
//
//   원인은 두 가지였다.
//     ① 홈 일자별은 `WeekHelper` 를 쓰지 않고 `date.weekday` 로 직접 계산했다
//        (기기 달력 성분, KST 정규화 없음). 공고탭은 `WeekHelper` 를 쓰지만
//        기준일이 대상 날짜가 아니라 **오늘**일 수 있었다.
//     ② 둘 다 **문서 수**를 셌다 — 9/20 하루가 `주4회` 가 될 수 있었다.
//        코드 주석은 처음부터 "근무한 날 기준"이라고 적고 있었다.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ALfit/models/core/attendance_model.dart';
import 'package:ALfit/utils/format_helper.dart';
import 'package:ALfit/utils/week_helper.dart';
import 'package:ALfit/widgets/dialogs/styled_dialog.dart';

DateTime _kst(int y, int m, int d, [int h = 0]) =>
    DateTime.utc(y, m, d, h).subtract(const Duration(hours: 9));

/// `checkIn` 은 `checkInAt` 에서 파생되는 getter다 — 저장 필드를 그대로 쓴다.
AttendanceModel _att({
  required DateTime workDate,
  String status = AttendanceModel.statusPresent,
  bool checkedIn = true,
}) =>
    AttendanceModel(
      id: 'a${workDate.millisecondsSinceEpoch}$status${checkedIn ? 1 : 0}',
      applicationId: 'app1',
      userId: 'u1',
      businessId: 'biz1',
      businessName: '위워커',
      workDate: workDate,
      workType: '사무업무',
      status: status,
      checkInAt: checkedIn ? workDate.add(const Duration(hours: 1)) : null,
      createdAt: workDate,
    );

/// DEV 실측 그대로.
List<AttendanceModel> _devRecords() => [
      _att(workDate: _kst(2026, 9, 14), status: AttendanceModel.statusNoShow, checkedIn: false),
      _att(workDate: _kst(2026, 9, 16)),
      _att(workDate: _kst(2026, 9, 18), status: AttendanceModel.statusNoShow, checkedIn: false),
      _att(workDate: _kst(2026, 9, 18)),
      _att(workDate: _kst(2026, 9, 20, 1)),
      _att(workDate: _kst(2026, 9, 20, 2)),
      _att(workDate: _kst(2026, 9, 20, 3)),
      _att(workDate: _kst(2026, 9, 20, 4)),
      _att(workDate: _kst(2026, 9, 21)),
      _att(workDate: _kst(2026, 9, 22)),
      _att(workDate: _kst(2026, 9, 26), status: AttendanceModel.statusNoShow, checkedIn: false),
    ];

/// 주간 창으로 걸러 세는 것 — 두 화면이 공유하는 경로를 그대로 실행한다.
int countIn(DateTime refDate, List<AttendanceModel> recs) {
  final ws = WeekHelper.weekStart(refDate);
  final we = WeekHelper.weekEnd(refDate);
  final inWindow = recs.where((a) {
    final d = FormatHelper.toKstDate(a.workDate);
    return !d.isBefore(ws) && !d.isAfter(we);
  });
  return WeekHelper.workedDayCount(inWindow);
}

void main() {
  // ══════════════════════════════════════════════════════════════
  // A. 세는 규칙 — 문서가 아니라 날
  // ══════════════════════════════════════════════════════════════

  group('WCP-A workedDayCount', () {
    test('WCP-A1 같은 날 문서 4건은 하루다', () {
      final sameDay = [
        _att(workDate: _kst(2026, 9, 20, 1)),
        _att(workDate: _kst(2026, 9, 20, 2)),
        _att(workDate: _kst(2026, 9, 20, 3)),
        _att(workDate: _kst(2026, 9, 20, 4)),
      ];
      expect(sameDay.length, 4);
      expect(WeekHelper.workedDayCount(sameDay), 1,
          reason: '문서 수를 세면 하루가 주4회가 된다');
    });

    test('WCP-A2 결근·노쇼·미출근은 근무한 날이 아니다', () {
      expect(
          WeekHelper.workedDayCount([
            _att(workDate: _kst(2026, 9, 14), status: AttendanceModel.statusNoShow, checkedIn: false),
            _att(workDate: _kst(2026, 9, 15), status: AttendanceModel.statusAbsent),
            _att(workDate: _kst(2026, 9, 16), checkedIn: false),
          ]),
          0);
    });

    test('WCP-A3 지각·조퇴도 출근한 날이다', () {
      expect(
          WeekHelper.workedDayCount([
            _att(workDate: _kst(2026, 9, 16), status: AttendanceModel.statusLate),
            _att(workDate: _kst(2026, 9, 17), status: AttendanceModel.statusEarlyLeave),
          ]),
          2);
    });

    test('WCP-A4 같은 날에 노쇼와 출근이 함께 있으면 하루로 센다', () {
      // DEV 의 9/18 이 그렇다.
      expect(
          WeekHelper.workedDayCount([
            _att(workDate: _kst(2026, 9, 18), status: AttendanceModel.statusNoShow, checkedIn: false),
            _att(workDate: _kst(2026, 9, 18)),
          ]),
          1);
    });

    test('WCP-A5 DEV 실측 전체는 5일이다', () {
      expect(WeekHelper.workedDayCount(_devRecords()), 5);
    });

    test('WCP-A6 map 변환도 같은 규칙을 쓴다', () {
      final m = WeekHelper.workedDayCounts({'u1': _devRecords()});
      expect(m['u1'], 5);
    });
  });

  // ══════════════════════════════════════════════════════════════
  // B. 주간 창 — 한 계약, 기기 무관
  // ══════════════════════════════════════════════════════════════

  group('WCP-B 주간 창', () {
    test('WCP-B1 대상 날짜가 같으면 두 화면이 같은 창을 본다', () {
      // 홈: WeekHelper.weekStart(widget.date)
      // 공고탭: WeekHelper.weekStart(slot?.date ?? initialDate ?? to.date)
      final target = _kst(2026, 9, 28); // 월요일
      expect(WeekHelper.weekStart(target), FormatHelper.toKstDate(_kst(2026, 9, 28)));
      expect(WeekHelper.weekEnd(target), FormatHelper.toKstDate(_kst(2026, 10, 4)));
    });

    test('WCP-B2 같은 대상 날짜 → 같은 수 (parity)', () {
      final recs = _devRecords();
      final target = _kst(2026, 9, 28);
      expect(countIn(target, recs), 0, reason: '9/28~10/4 에는 출근이 없다');
      // 두 화면이 같은 기준일을 쓰므로 값이 같다.
      expect(countIn(target, recs), countIn(target, recs));
    });

    test('WCP-B3 기준일이 오늘이면 다른 주를 본다 — 그것이 화면 A 의 원인이다', () {
      final recs = _devRecords();
      // 대상 9/28(월) vs "오늘" 9/27(일) — 주가 다르다.
      expect(countIn(_kst(2026, 9, 28), recs), 0);
      expect(countIn(_kst(2026, 9, 27), recs), 2,
          reason: '9/21~9/27 → 9/21·9/22 두 날');
    });

    test('WCP-B4 주 경계가 KST 달력이다 — 기기와 무관', () {
      final recs = _devRecords();
      // 9/28 00:00 KST 는 UTC 로 9/27 15:00 — 기기 요일을 읽으면 주가 밀린다.
      final target = _kst(2026, 9, 28);
      expect(WeekHelper.weekStart(target).weekday, 1, reason: '항상 월요일');
      expect(countIn(target, recs), 0);
    });

    test('WCP-B5 주 중간 날짜여도 같은 주를 본다', () {
      final recs = _devRecords();
      for (final d in [
        _kst(2026, 9, 21), // 월
        _kst(2026, 9, 24), // 목
        _kst(2026, 9, 27), // 일
      ]) {
        expect(countIn(d, recs), 2, reason: '9/21~9/27 은 같은 주다');
      }
    });
  });

  // ══════════════════════════════════════════════════════════════
  // C. 모달 높이 계약 — production shell 을 실제로 그린다
  //
  //   전체 다이얼로그는 Firebase 에 의존해 여기서 그리지 않는다.
  //   높이를 정하는 owner 는 `AppModalShell` 이고, 그것과 본문 wrapper 의
  //   조합이 문제였으므로 그 조합을 그대로 실행한다.
  // ══════════════════════════════════════════════════════════════

  group('WCP-C 모달 높이', () {
    Widget shell({required int rows, required bool useExpanded}) {
      final body = SingleChildScrollView(
        child: Column(
          children: [
            for (var i = 0; i < rows; i++)
              SizedBox(height: 80, child: Text('행 $i')),
          ],
        ),
      );
      return MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(size: Size(360, 800)),
          child: AppModalShell(children: [
            const SizedBox(height: 60, child: Text('머리말')),
            if (useExpanded) Expanded(child: body) else Flexible(child: body),
            const SizedBox(height: 56, child: Text('닫기')),
          ]),
        ),
      );
    }

    /// 사용자가 보는 모달 높이 = 머리말 top ~ 닫기 bottom.
    ///   `Dialog` 의 렌더 박스는 오버레이 전체라 그것으로는 측정되지 않는다.
    double modalHeight(WidgetTester tester) =>
        tester.getRect(find.text('닫기')).bottom -
        tester.getRect(find.text('머리말')).top;

    testWidgets('WCP-C1 행이 적으면 모달이 내용만큼 줄어든다', (tester) async {
      await tester.pumpWidget(shell(rows: 1, useExpanded: false));
      final h = modalHeight(tester);
      expect(h, lessThan(300),
          reason: '머리말60 + 행80 + 닫기56 ≈ 196 이어야 한다 (실측 $h)');
    });

    testWidgets('WCP-C2 같은 조건에서 Expanded 는 남은 공간을 채운다 — 회귀 대비',
        (tester) async {
      await tester.pumpWidget(shell(rows: 1, useExpanded: true));
      final expanded = modalHeight(tester);
      await tester.pumpWidget(shell(rows: 1, useExpanded: false));
      final flexible = modalHeight(tester);
      expect(expanded, greaterThan(flexible + 200),
          reason: '이것이 예전 동작이다 — 두 wrapper 의 차이를 실행으로 남긴다 '
              '(Expanded $expanded vs Flexible $flexible)');
    });

    testWidgets('WCP-C3 행이 많으면 상한까지 자라고 그 안에서 스크롤한다',
        (tester) async {
      await tester.pumpWidget(shell(rows: 30, useExpanded: false));
      final h = modalHeight(tester);
      expect(h, greaterThan(400), reason: '많은 행에서는 자란다 (실측 $h)');
      expect(h, lessThanOrEqualTo(800), reason: '화면을 넘지 않는다');
      // 스크롤이 살아 있고 닫기 경로가 남아 있다.
      expect(find.byType(Scrollable), findsWidgets);
      expect(find.text('닫기'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    // ══════════════════════════════════════════════════════════
    // viewport × 글자배율 matrix — production shell/header 를 실제로 그린다.
    //
    //   지원 범위는 저장소가 선언한 것을 쓴다(임의 선언 금지).
    //   `ResponsiveHelper` 계층: width < 360 / < 400 / < 600 / >= 600,
    //   주석은 실사용 폭을 360~412dp 로 적는다.
    //
    //   여기서 그리는 것은 높이·닫기 접근성을 정하는 owner
    //   (`AppModalShell` + `AppModalHeader`) 다. 다이얼로그 전체는 Firebase
    //   의존으로 이 환경에서 그리지 않는다 — 보고서에 미검증으로 남긴다.
    // ══════════════════════════════════════════════════════════

    Widget matrixShell({
      required Size size,
      required double textScale,
      required int rows,
      EdgeInsets padding = EdgeInsets.zero,
      double keyboard = 0,
    }) =>
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(
              size: size,
              textScaler: TextScaler.linear(textScale),
              padding: padding,
              viewInsets: EdgeInsets.only(bottom: keyboard),
            ),
            child: AppModalShell(children: [
              const AppModalHeader(
                title: '아주 긴 업무 이름이 들어간 공고 제목 · 인력 현황',
                subtitle: '2026-09-28 (월) · 09:00~18:00 | 시급 12,000원',
              ),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(children: [
                    for (var i = 0; i < rows; i++)
                      Padding(
                        padding: const EdgeInsets.all(8),
                        child: Text('홍길동(W-0$i) · 010-0000-0000 · 주3회 · '
                            '최근 90일 노쇼 7회 · 계약서 작성 필요'),
                      ),
                  ]),
                ),
              ),
              const SizedBox(height: 56, child: Center(child: Text('닫기'))),
            ]),
          ),
        );

    for (final size in const [
      Size(320, 640), // < 360 계층
      Size(360, 740), // 실사용 하한
      Size(412, 892), // 실사용 상한
      Size(600, 960), // 태블릿 경계
    ]) {
      for (final scale in const [1.0, 1.3, 2.0]) {
        for (final rows in const [1, 20]) {
          testWidgets(
              'WCP-M ${size.width.toInt()}x${size.height.toInt()} '
              'scale$scale rows$rows — overflow 없음 · 닫기 접근 가능',
              (tester) async {
            await tester.pumpWidget(
                matrixShell(size: size, textScale: scale, rows: rows));
            await tester.pump();

            expect(tester.takeException(), isNull,
                reason: 'overflow/clipping 이 발생했다');

            // 닫기가 화면 안에 있다.
            final close = find.text('닫기');
            expect(close, findsOneWidget);
            final r = tester.getRect(close);
            expect(r.bottom, lessThanOrEqualTo(size.height + 0.5),
                reason: '닫기가 화면 아래로 밀려났다 (bottom=${r.bottom})');
            expect(r.top, greaterThanOrEqualTo(-0.5));

            // 머리말도 살아 있다 — 글자를 줄여 숨기지 않는다.
            expect(find.byType(AppModalHeader), findsOneWidget);

            // 행이 많으면 스크롤로 닿는다.
            if (rows > 1) expect(find.byType(Scrollable), findsWidgets);
          });
        }
      }
    }

    testWidgets('WCP-M-KB 키보드가 올라와도 닫기에 닿는다', (tester) async {
      await tester.pumpWidget(matrixShell(
          size: const Size(360, 740), textScale: 1.0, rows: 20, keyboard: 320));
      await tester.pump();
      expect(tester.takeException(), isNull);
      final r = tester.getRect(find.text('닫기'));
      expect(r.bottom, lessThanOrEqualTo(740 - 320 + 0.5),
          reason: '키보드 영역 위에 남아야 한다 (bottom=${r.bottom})');
    });

    testWidgets('WCP-M-SA safe area(노치·홈바)에서도 잘리지 않는다', (tester) async {
      await tester.pumpWidget(matrixShell(
        size: const Size(390, 844),
        textScale: 1.0,
        rows: 20,
        padding: const EdgeInsets.only(top: 47, bottom: 34),
      ));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.text('닫기'), findsOneWidget);
    });

    testWidgets('WCP-C4 긴 제목·확대 글자에서도 잘리지 않는다', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(
              size: Size(320, 640), textScaler: TextScaler.linear(1.5)),
          child: AppModalShell(children: [
            const AppModalHeader(
                title: '아주 긴 업무 이름이 들어간 공고 제목 · 인력 현황',
                subtitle: '2026-09-28 · 09:00~18:00 | 시급 12,000원'),
            Flexible(
                child: SingleChildScrollView(
                    child: Column(children: [
              for (var i = 0; i < 12; i++)
                SizedBox(height: 80, child: Text('행 $i')),
            ]))),
            const SizedBox(height: 56, child: Text('닫기')),
          ]),
        ),
      ));
      expect(tester.takeException(), isNull, reason: 'overflow 없이 그려진다');
      expect(find.text('닫기'), findsOneWidget, reason: '닫기 경로가 남아 있다');
    });
  });
}
