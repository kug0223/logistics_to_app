// [R7-P1-2 DEVICE.1] 한국 사업장의 달력은 기기 timezone 을 따르지 않는다.
//
//   실기기(UTC)에서 이렇게 보였다.
//
//     공고 요약    9/26 ~ 9/28
//     날짜별 현황   9/25  9/26  9/27
//
//   같은 카드가 두 달력을 말하고 있었다. 저장값은 멀쩡했다 —
//   `slot.date = 2026-09-25T15:00:00Z` 는 **2026-09-26 00:00 KST** 이고,
//   문서의 `dates: ["2026-09-26"]` 도 같은 날을 가리킨다.
//   요약은 `FormatHelper` 를 지났고, 날짜 칩만 `d.month`/`d.day` 로
//   **기기 성분**을 직접 읽었다. UTC 기기에서 그 성분은 전날이다.
//
//   그래서 세 종류를 갈라 둔다.
//
//     DATE_ONLY    `2026-09-26` — 순간이 아니라 달력상의 날. 기기 무관.
//     WALL_CLOCK   `09:00~18:00` — 한국 사업장 현지 시각. 변환하지 않는다.
//     INSTANT      createdAt 등 — 실제 순간. UTC 저장, 표시할 때만 KST.
//
//   이 파일은 `TZ=UTC` 와 `TZ=Asia/Seoul` 양쪽에서 돌려야 의미가 있다.
//   Dart 는 이 환경에서 TZ 를 따른다 — 그래서 실제로 두 번 돌린다.

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:ALfit/utils/format_helper.dart';

String _read(String p) => File(p).readAsStringSync();

String _codeOf(String dart) => dart
    .split('\n')
    .where((l) => !l.trimLeft().startsWith('//'))
    .join('\n');

/// DEV 에 실제로 저장돼 있는 모양 그대로 — KST 자정 instant.
DateTime _storedKstDate(int y, int m, int d) =>
    DateTime.utc(y, m, d).subtract(const Duration(hours: 9));

void main() {
  // 이 스위트가 어느 timezone 에서 돌았는지 기록에 남긴다.
  setUpAll(() {
    final off = DateTime.now().timeZoneOffset;
    // ignore: avoid_print
    print('[KST-CONTRACT] device timezone offset = $off '
        '(${Platform.environment['TZ'] ?? 'host default'})');
  });

  // ══════════════════════════════════════════════════════════════
  // A·B. DATE_ONLY 는 기기 timezone 으로 움직이지 않는다
  // ══════════════════════════════════════════════════════════════

  group('KST-A DATE_ONLY', () {
    test('KST-A1 저장된 KST 자정 instant 가 그 날로 읽힌다', () {
      // 실기기에서 어긋났던 바로 그 값.
      final d = _storedKstDate(2026, 9, 26);
      expect(d.toUtc().toIso8601String(), '2026-09-25T15:00:00.000Z',
          reason: 'DEV 저장 모양과 같은지 먼저 확인한다');
      expect(FormatHelper.formatDateShort(d), '9/26');
      expect(FormatHelper.toKstDateKey(d), '2026-09-26');
    });

    test('KST-A2 기기 성분 직접 읽기와 달라지는 것이 정상이다', () {
      final d = _storedKstDate(2026, 9, 26);
      final deviceLocal = '${d.month}/${d.day}';
      // UTC 기기에서는 9/25 가 나온다 — 그것이 버그였다.
      // KST 기기에서는 우연히 9/26 이라 문제가 보이지 않았다.
      expect(FormatHelper.formatDateShort(d), '9/26',
          reason: 'canonical 경로는 어느 기기에서도 9/26 (기기값=$deviceLocal)');
    });

    test('KST-B UTC 표현이든 local 표현이든 같은 달력일', () {
      final d = _storedKstDate(2026, 9, 26);
      for (final v in [d, d.toUtc(), d.toLocal()]) {
        expect(FormatHelper.formatDateShort(v), '9/26');
        expect(FormatHelper.toKstDateKey(v), '2026-09-26');
        expect(FormatHelper.weekday(v), '토');
      }
    });

    test('KST-B2 문서의 dates 문자열과 같은 키가 나온다', () {
      // tos/{id}.dates 는 이미 canonical DATE_ONLY 다 — 변환이 필요 없다.
      const stored = '2026-09-26';
      final fromKey = FormatHelper.parseKstDateKey(stored)!;
      final fromTs = _storedKstDate(2026, 9, 26);
      expect(FormatHelper.toKstDateKey(fromTs), stored);
      expect(FormatHelper.toKstDate(fromTs), fromKey);
    });
  });

  // ══════════════════════════════════════════════════════════════
  // C~E. 공고 범위 = 날짜 칩
  // ══════════════════════════════════════════════════════════════

  group('KST-C 공고 범위 parity', () {
    /// 실기기에서 본 두 공고를 그대로 재현한다.
    List<String> chips(List<DateTime> slotDates) =>
        slotDates.map(FormatHelper.formatDateShort).toList();

    String summary(DateTime start, DateTime end) =>
        '${FormatHelper.formatDateShort(start)}'
        '~${FormatHelper.formatDateShort(end)}';

    test('KST-C Fixture A — 9/26~9/28', () {
      final start = _storedKstDate(2026, 9, 26);
      final end = _storedKstDate(2026, 9, 28);
      final slots = [
        _storedKstDate(2026, 9, 26),
        _storedKstDate(2026, 9, 27),
        _storedKstDate(2026, 9, 28),
      ];
      expect(summary(start, end), '9/26~9/28');
      expect(chips(slots), ['9/26', '9/27', '9/28']);
    });

    test('KST-C2 Fixture B — 9/29~9/30', () {
      final start = _storedKstDate(2026, 9, 29);
      final end = _storedKstDate(2026, 9, 30);
      final slots = [
        _storedKstDate(2026, 9, 29),
        _storedKstDate(2026, 9, 30),
      ];
      expect(summary(start, end), '9/29~9/30');
      expect(chips(slots), ['9/29', '9/30']);
    });

    test('KST-D 범위 시작 이전 날짜가 생기지 않는다', () {
      final slots = [
        _storedKstDate(2026, 9, 26),
        _storedKstDate(2026, 9, 27),
        _storedKstDate(2026, 9, 28),
      ];
      final startKey = FormatHelper.toKstDate(_storedKstDate(2026, 9, 26));
      for (final s in slots) {
        expect(FormatHelper.toKstDate(s).isBefore(startKey), isFalse,
            reason: '${FormatHelper.formatDateShort(s)} 가 범위 앞으로 샜다');
      }
    });

    test('KST-E 범위 끝이 빠지지 않는다', () {
      final endKey = FormatHelper.toKstDate(_storedKstDate(2026, 9, 28));
      final slotKeys = [
        _storedKstDate(2026, 9, 26),
        _storedKstDate(2026, 9, 27),
        _storedKstDate(2026, 9, 28),
      ].map(FormatHelper.toKstDate).toList();
      expect(slotKeys.contains(endKey), isTrue);
    });
  });

  // ══════════════════════════════════════════════════════════════
  // F. 요일은 날짜와 같은 곳에서 나온다
  // ══════════════════════════════════════════════════════════════

  test('KST-F 요일 parity (2026)', () {
    const expected = {
      26: '토', 27: '일', 28: '월', 29: '화', 30: '수',
    };
    expected.forEach((day, wd) {
      final d = _storedKstDate(2026, 9, day);
      expect(FormatHelper.weekday(d), wd, reason: '9/$day');
      // 날짜와 요일이 서로 다른 변환을 쓰면 여기서 갈라진다.
      expect(FormatHelper.formatDate(d), '9/$day ($wd)');
      expect(FormatHelper.formatDateShort(d), '9/$day');
    });
  });

  // ══════════════════════════════════════════════════════════════
  // I·J. 경계
  // ══════════════════════════════════════════════════════════════

  group('KST-I 경계', () {
    test('KST-I 월 경계 9/30 → 10/1', () {
      expect(FormatHelper.formatDateShort(_storedKstDate(2026, 9, 30)), '9/30');
      expect(FormatHelper.formatDateShort(_storedKstDate(2026, 10, 1)), '10/1');
      expect(FormatHelper.toKstDateKey(_storedKstDate(2026, 10, 1)),
          '2026-10-01');
    });

    test('KST-J 연 경계 12/31 → 1/1', () {
      expect(FormatHelper.formatDateShort(_storedKstDate(2026, 12, 31)),
          '12/31');
      final ny = _storedKstDate(2027, 1, 1);
      expect(FormatHelper.formatDateShort(ny), '1/1');
      expect(FormatHelper.toKstDateKey(ny), '2027-01-01');
    });

    test('KST-I2 2월 말일 (평년·윤년)', () {
      expect(FormatHelper.toKstDateKey(_storedKstDate(2026, 2, 28)),
          '2026-02-28');
      expect(FormatHelper.toKstDateKey(_storedKstDate(2028, 2, 29)),
          '2028-02-29');
    });

    test('KST-I3 하루짜리 범위', () {
      final d = _storedKstDate(2027, 1, 19);
      expect(
          '${FormatHelper.formatDateShort(d)}~${FormatHelper.formatDateShort(d)}',
          '1/19~1/19');
      // DEV 에 실제로 있는 값이다.
      expect(d.millisecondsSinceEpoch, 1800284400000);
    });

    test('KST-I4 영업일 구간이 자정에서 정확히 끊긴다', () {
      final (s, e) = FormatHelper.kstDayRange(_storedKstDate(2026, 9, 26));
      expect(s.toUtc().toIso8601String(), '2026-09-25T15:00:00.000Z');
      expect(e.toUtc().toIso8601String(), '2026-09-26T15:00:00.000Z');
      // 그 날 23:59 KST 는 안에, 다음 날 00:00 KST 는 밖에.
      final lastMinute =
          _storedKstDate(2026, 9, 26).add(const Duration(hours: 23, minutes: 59));
      expect(lastMinute.isBefore(e), isTrue);
      expect(_storedKstDate(2026, 9, 27).isBefore(e), isFalse);
    });

    test('KST-I5 월 구간이 KST 1일에서 시작한다', () {
      final (s, e) = FormatHelper.kstMonthRange(_storedKstDate(2026, 9, 26));
      expect(s.toUtc().toIso8601String(), '2026-08-31T15:00:00.000Z');
      expect(e.toUtc().toIso8601String(), '2026-09-30T15:00:00.000Z');
    });
  });

  // ══════════════════════════════════════════════════════════════
  // G. 근무시간은 wall-clock — 변환 대상이 아니다
  // ══════════════════════════════════════════════════════════════

  group('KST-G WALL_CLOCK', () {
    test('KST-G1 근무시간은 문자열로 저장·표시된다', () {
      // startTime/endTime 이 DateTime 이면 기기 timezone 이 개입할 여지가 생긴다.
      final app = _codeOf(_read('lib/models/core/application_model.dart'));
      expect(app, contains('final String startTime;'));
      expect(app, contains('final String endTime;'));
      // work_detail_model.dart 는 re-export shim 이다 — 실제 선언은 이쪽.
      final wd = _codeOf(_read('lib/models/core/work_detail_data.dart'));
      expect(wd, contains('final String startTime;'));
      expect(wd, contains('final String endTime;'));
    });

    test('KST-G2 표시 경로에 timezone 변환이 없다', () {
      for (final path in [
        'lib/screens/business_admin/dialogs/work_applicants_dialog.dart',
        'lib/widgets/admin/cards/admin_to_group_card.dart',
      ]) {
        final s = _codeOf(_read(path));
        for (final banned in ['startTime.toLocal()', 'endTime.toLocal()']) {
          expect(s, isNot(contains(banned)),
              reason: '$path — 근무시간을 기기 시간대로 바꾼다');
        }
      }
    });
  });

  // ══════════════════════════════════════════════════════════════
  // H. INSTANT 는 순간 그대로
  // ══════════════════════════════════════════════════════════════

  group('KST-H INSTANT', () {
    test('KST-H1 순간 표시는 KST 로 변환하되 값은 순간이다', () {
      // 2026-09-25 15:00Z = 2026-09-26 00:00 KST
      final instant = DateTime.utc(2026, 9, 25, 15, 0);
      expect(FormatHelper.formatDateTime(instant), contains('9/26'));
      // 기기가 무엇이든 같은 순간을 가리킨다.
      expect(instant.toUtc().millisecondsSinceEpoch,
          instant.toLocal().toUtc().millisecondsSinceEpoch);
    });

    test('KST-H2 이번 패치가 저장 형식을 바꾸지 않았다', () {
      // "모든 DateTime 을 KST 문자열로 저장" 같은 방향이면 여기서 깨진다.
      final to = _codeOf(_read('lib/models/core/to_model.dart'));
      expect(to, contains('Timestamp'));
      expect(to, isNot(contains('kstString')));
    });
  });

  // ══════════════════════════════════════════════════════════════
  // L. 고친 표면에 기기 성분 읽기가 남지 않았다
  // ══════════════════════════════════════════════════════════════

  group('KST-L 표면 가드', () {
    /// `${something.month}` / `${something.day}` 형태의 기기 성분 직접 읽기.
    final deviceComponent = RegExp(r'\$\{[A-Za-z_.!()\[\]]*\.(month|day)\}');

    test('KST-L1 공고 카드 · TO 모델 · 인력 현황', () {
      for (final path in [
        'lib/widgets/admin/cards/admin_to_group_card.dart',
        'lib/models/core/to_model.dart',
        'lib/screens/business_admin/dialogs/work_applicants_dialog.dart',
        'lib/screens/business_admin/dialogs/day_applicants_dialog.dart',
      ]) {
        final code = _codeOf(_read(path));
        final hits = deviceComponent
            .allMatches(code)
            .map((m) => m.group(0)!)
            .toList();
        expect(hits, isEmpty,
            reason: '$path — 기기 달력으로 근무일을 말한다: $hits');
      }
    });

    test('KST-L2 요일도 canonical helper 를 쓴다', () {
      final card = _codeOf(_read('lib/widgets/admin/cards/admin_to_group_card.dart'));
      expect(card, contains('FormatHelper.weekday('));
      expect(card, isNot(contains('.weekday - 1]')),
          reason: '날짜와 요일이 서로 다른 변환을 쓰면 안 된다');
    });

    test('KST-L3 공고 요약과 날짜 칩이 같은 helper 를 쓴다', () {
      final card = _codeOf(_read('lib/widgets/admin/cards/admin_to_group_card.dart'));
      expect('FormatHelper.formatDateShort'.allMatches(card).length,
          greaterThanOrEqualTo(3),
          reason: '요약(2) + 날짜 칩(1) 이상');
    });

    test('KST-L4 canonical helper 자체가 기기 시간대를 쓰지 않는다', () {
      final fh = _codeOf(_read('lib/utils/format_helper.dart'));
      expect(fh, contains('static DateTime _toKst(DateTime dt) => dt.toUtc().add(_kst);'));
      expect(fh, contains('static const _kst = Duration(hours: 9);'));
      // 날짜 포맷이 local 성분을 읽으면 helper 자체가 오염된 것이다.
      final fmt = fh.substring(fh.indexOf('static String formatDateShort'),
          fh.indexOf('static DateTime toKstDate'));
      expect(fmt, contains('_toKst(date)'));
    });
  });
}
