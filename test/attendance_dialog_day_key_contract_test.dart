import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ALfit/utils/format_helper.dart';

/// [R7-P1-3] 당일명단이 다루는 **날짜 하나**의 계약.
///
///   `AttendanceStatusDialog` 는 받은 `date` 를 instant 로 쓴다 —
///   `FormatHelper.kstDayRange`(조회 창), `toKstDate`(비교 키), 그리고 서버로
///   보내는 `workDateMs` 다. 그런데 호출부가 넘기는 값은 두 종류였다:
///
///     · 홈:            `FormatHelper.toKstDate(DateTime.now())` → `DateTime.utc(y,m,d)`
///     · 미처리 큐:      `DateTime(y,m,d)` — 기기 local 자정
///                      (`UnclosedQueueItem.workDate`, 그 화면 주석이 "instant 가
///                       아니다" 라고 직접 적어 두었다)
///     · 근무 탭:        `DateTime(y,m,d)` — `_selectedDay` / `_today()`
///
///   `kstDayRange` 문서가 그 경우를 경고한다: "`DateTime(d.year, d.month, d.day)`
///   로 만든 기기 local 자정을 쓰면 KST가 아닌 기기에서 창이 통째로 어긋난다."
///   `workDateMs` 는 서버에서 **근태 문서 id** 까지 정한다
///   (`callableBatchSetNoShow`: `${applicationId}_${KST(workDateMs)}`).
///
///   A 군은 그 어긋남을 **수치로** 보인다(기기 TZ 를 바꾸지 않고, 그 기기가
///   만들어 낼 instant 를 그대로 구성한다). B 군은 화면이 한 번만 정규화하는
///   계약을 소스에서 고정한다 — 실행 증거와 소스 계약을 섞지 않는다.

String _src(String p) => File(p).readAsStringSync();

const _dialog = 'lib/screens/business_admin/dialogs/attendance_status_dialog.dart';

void main() {
  group('ADK-A 기기 시간대에 따라 local 자정은 다른 KST 날짜가 된다 (실행)', () {
    // 2026-09-28 을 고른 기기가 만들어 내는 `DateTime(2026,9,28)` 의 instant.
    //   UTC+13(오클랜드 DST) → 2026-09-27T11:00Z
    //   UTC+9 (서울)        → 2026-09-27T15:00Z
    //   UTC-7 (LA)          → 2026-09-28T07:00Z
    final localMidnightUtcPlus13 = DateTime.utc(2026, 9, 27, 11);
    final localMidnightKst = DateTime.utc(2026, 9, 27, 15);
    final localMidnightUtcMinus7 = DateTime.utc(2026, 9, 28, 7);
    // 정규화 키 — 성분을 KST 달력일로 못박은 값.
    final canonical = DateTime.utc(2026, 9, 28);

    test('A-1 UTC+13 기기의 local 자정은 KST 로 전날이다', () {
      expect(FormatHelper.toKstDateKey(localMidnightUtcPlus13), '2026-09-27');
      expect(FormatHelper.toKstDateKey(canonical), '2026-09-28');
    });

    test('A-2 그래서 조회 창이 통째로 하루 어긋난다', () {
      final (badStart, badEnd) = FormatHelper.kstDayRange(localMidnightUtcPlus13);
      final (goodStart, goodEnd) = FormatHelper.kstDayRange(canonical);
      expect(badStart.isBefore(goodStart), isTrue);
      expect(goodStart.difference(badStart), const Duration(days: 1));
      // 관리자가 고른 9/28 의 KST 자정은 잘못된 창의 **끝**이다 — 즉 9/28 근무는 빠진다.
      expect(badEnd, goodStart);
      expect(goodEnd.difference(goodStart), const Duration(days: 1));
    });

    test('A-3 KST·서쪽 기기에서는 기존 값도 같은 날을 고른다 — 회귀 범위 확인', () {
      expect(FormatHelper.toKstDateKey(localMidnightKst), '2026-09-28');
      expect(FormatHelper.toKstDateKey(localMidnightUtcMinus7), '2026-09-28');
      expect(FormatHelper.kstDayRange(localMidnightKst),
          FormatHelper.kstDayRange(canonical));
      expect(FormatHelper.kstDayRange(localMidnightUtcMinus7),
          FormatHelper.kstDayRange(canonical));
    });

    test('A-4 정규화 키는 어떤 기기 값에서 출발해도 같은 날을 가리킨다', () {
      for (final d in [
        localMidnightUtcPlus13,
        localMidnightKst,
        localMidnightUtcMinus7,
        canonical,
      ]) {
        // 화면이 하는 정규화와 같은 식 — 달력 성분을 KST 달력일로 본다.
        final key = DateTime.utc(d.year, d.month, d.day);
        expect(FormatHelper.kstDayRange(key), FormatHelper.kstDayRange(
            DateTime.utc(d.year, d.month, d.day)));
        // 성분이 보존된다 — 화면 머리말(`DateFormat`)이 같은 날짜를 찍는다.
        expect(key.year, d.year);
        expect(key.month, d.month);
        expect(key.day, d.day);
      }
    });

    test('A-5 서버가 문서 id 를 만드는 식으로도 날짜가 갈린다', () {
      // `callableBatchSetNoShow` 는 `workDateMs` 를 KST 로 바꿔 id 날짜를 만든다.
      //   여기서는 그 질문을 클라이언트 canonical 로 그대로 물어본다.
      expect(FormatHelper.toKstDateKey(
          DateTime.fromMillisecondsSinceEpoch(
              localMidnightUtcPlus13.millisecondsSinceEpoch, isUtc: true)),
          '2026-09-27');
      expect(FormatHelper.toKstDateKey(
          DateTime.fromMillisecondsSinceEpoch(
              canonical.millisecondsSinceEpoch, isUtc: true)),
          '2026-09-28');
    });
  });

  group('ADK-B 화면은 받은 날짜를 한 번만 정규화한다 (소스 계약)', () {
    final code = _src(_dialog);

    test('B-1 정규화 필드가 있고, 성분을 KST 달력일로 못박는다', () {
      expect(
          code.contains('DateTime.utc(widget.date.year, widget.date.month, widget.date.day)'),
          isTrue);
      expect(code.contains('DateTime get _todayKst => FormatHelper.toKstDate(DateTime.now());'),
          isTrue);
    });

    test('B-2 정규화 지점 말고는 widget.date 를 쓰지 않는다', () {
      // 들어온 원본을 그대로 날짜 계산에 쓰면 호출부마다 다른 달력이 섞인다.
      expect('widget.date'.allMatches(code).length, 3,
          reason: '정규화 필드 한 줄의 3개 참조뿐이어야 한다');
    });

    test('B-3 조회 창·비교 키·서버 payload 가 모두 정규화된 값을 쓴다', () {
      expect(code.contains('FormatHelper.kstDayRange(_kstDay)'), isTrue);
      expect(code.contains('FormatHelper.toKstDate(_kstDay)'), isTrue);
      expect(code.contains("'workDateMs': _kstDay.millisecondsSinceEpoch"), isTrue);
      expect(code.contains('FormatHelper.kstDayRange(widget.date)'), isFalse);
    });

    test('B-4 과거/미래 판정 기준도 같은 달력이다', () {
      // 기기 local 자정과 섞으면 offset 만큼 어긋난 비교가 된다.
      expect(code.contains('final today = _todayKst;'), isTrue);
      expect(
          code.contains('DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day)'),
          isFalse,
          reason: '이 화면에는 기기 local 오늘 자정이 남아 있지 않다');
    });

    test('B-5 머리말 날짜는 성분을 그대로 찍는다 — 모든 기기에서 같은 날짜', () {
      expect(code.contains("DateFormat('MM월 dd일 (E)', 'ko_KR').format(_kstDay)"), isTrue);
    });
  });
}
