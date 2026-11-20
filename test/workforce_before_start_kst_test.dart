// [ADM-TZ] 관리자 Workforce 의 '근무 시작 전' 판정이 서버와 같은 시각을 본다.
//
// ── canonical (서버) ──────────────────────────────────────────────────
//   `srvShiftStartMsFrom(workDateMs, startTime)`:
//
//     return workDateMs + (hh * 60 + mm) * 60000;   // workDateMs = KST 자정
//
//   노쇼 확정 guard 는 여기에 lateGrace 를 더한 `srvNoShowJudgeableFromMs`
//   이후에만 허용한다(`callableBatchSetNoShow`). 즉 **시작 시각의 원천은
//   KST 자정 + 벽시계**다.
//
// ── 화면이 쓰던 식 ────────────────────────────────────────────────────
//   `DateTime(now.year, now.month, now.day, h, m)`
//   — **기기 local 날짜 + local 벽시계**. KST 기기에서는 서버와 같은
//   순간이 되지만, 그 밖에서는 기기 offset 만큼 어긋난다
//   (GMT 기기에서 9시간). 지원자 화면의 오류(`toKstDate` = UTC 자정)와
//   원인이 달라서, 거기서 본 9시간을 그대로 복사해 단정하면 안 된다.
//
// ── 영향 ──────────────────────────────────────────────────────────────
//   호출부 세 곳 모두 **표시·집계**다 — 미출근 카운트 제외, `미출근` 필터,
//   상태 칩(`출근 전` vs `미출근`). 서버 mutation guard 와는 별개이므로
//   실제 관리 행동이 잘못 차단되거나 허용되지는 않는다.
//
// 이 파일은 KST 기본 환경과 `TZ=UTC` 양쪽에서 통과해야 한다.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:ALfit/utils/format_helper.dart';

/// 근무일 2026-10-15 — 달력 셀과 같은 **civil** 값(기기 local 성분).
final DateTime _civilDay = DateTime(2026, 10, 15);

/// 서버와 같은 식: 그 날 KST 자정 instant + 벽시계.
DateTime _serverStart(String hhmm) {
  final p = hhmm.split(':');
  return FormatHelper.kstDayKeyOfCivil(_civilDay)
      .subtract(const Duration(hours: 9))
      .add(Duration(hours: int.parse(p[0]), minutes: int.parse(p[1])));
}

/// 화면이 쓰게 된 식(패치 후).
DateTime? _clientStart(String hhmm) => FormatHelper.kstWallClockInstant(
    FormatHelper.kstDayKeyOfCivil(_civilDay), hhmm);

/// 화면이 쓰던 옛 식 — 기기 local 날짜 + local 벽시계.
DateTime _legacyStart(DateTime now, String hhmm) {
  final p = hhmm.split(':');
  return DateTime(now.year, now.month, now.day, int.parse(p[0]),
      int.parse(p[1]));
}

void main() {
  group('[WB-A] 시작 instant 가 서버와 같다', () {
    test('WB-1 16:00 근무 → KST 16:00 (= UTC 07:00)', () {
      expect(_clientStart('16:00')!.toUtc().toIso8601String(),
          '2026-10-15T07:00:00.000Z');
      expect(_clientStart('16:00'), _serverStart('16:00'));
    });

    test('WB-2 KST 00:30 근무 — UTC 로는 전날', () {
      expect(_clientStart('00:30')!.toUtc().toIso8601String(),
          '2026-10-14T15:30:00.000Z');
      expect(_clientStart('00:30'), _serverStart('00:30'));
    });

    test('WB-3 KST 23:00 시작(익일 종료) — 시작만 본다', () {
      expect(_clientStart('23:00'), _serverStart('23:00'));
    });

    test('WB-4 기기 시간대와 무관하다', () {
      // 어떤 환경에서 돌려도 같은 절대 시각이다.
      expect(_clientStart('16:00')!.toUtc(), DateTime.utc(2026, 10, 15, 7));
    });
  });

  group('[WB-B] 재현 — 옛 식은 기기 시간대를 탔다', () {
    test('WB-5 오차는 정확히 (기기 offset - 9시간)', () {
      final now = DateTime(2026, 10, 15, 12);
      final gap = _serverStart('16:00').difference(_legacyStart(now, '16:00'));
      expect(gap, now.timeZoneOffset - const Duration(hours: 9),
          reason: 'KST 기기에서는 0, GMT 기기에서는 -9시간이다');
    });

    test('WB-6 KST 기기에서는 옛 식도 같은 순간이었다', () {
      // 그래서 한국에서 쓰는 동안에는 드러나지 않았다.
      final now = DateTime(2026, 10, 15, 12);
      if (now.timeZoneOffset == const Duration(hours: 9)) {
        // DateTime == 는 isUtc 까지 본다 — 같은 '순간'인지로 비교한다.
        expect(_legacyStart(now, '16:00').isAtSameMomentAs(_serverStart('16:00')),
            isTrue);
      } else {
        expect(_legacyStart(now, '16:00').isAtSameMomentAs(_serverStart('16:00')),
            isFalse,
            reason: 'KST 가 아닌 환경에서는 어긋난다');
      }
    });
  });

  group('[WB-C] 시작 전·정각·후 경계', () {
    final start = _serverStart('16:00');
    bool beforeStart(DateTime now) => now.isBefore(_clientStart('16:00')!);

    test('WB-7 1초 전 → 시작 전', () {
      expect(beforeStart(start.subtract(const Duration(seconds: 1))), isTrue);
    });

    test('WB-8 정각 → 시작 전 아님', () {
      expect(beforeStart(start), isFalse);
    });

    test('WB-9 1초 후 → 시작 전 아님', () {
      expect(beforeStart(start.add(const Duration(seconds: 1))), isFalse);
    });

    test('WB-10 같은 instant 를 어떤 표현으로 줘도 결론이 같다', () {
      final probe = start.subtract(const Duration(minutes: 1));
      expect(beforeStart(probe.toUtc()), isTrue);
      expect(beforeStart(probe.toLocal()), isTrue);
      expect(
          beforeStart(DateTime.fromMillisecondsSinceEpoch(
              probe.millisecondsSinceEpoch)),
          isTrue);
    });
  });

  group('[WB-D] 시각을 못 읽으면 단정하지 않는다', () {
    test('WB-11 형식 오류는 null — 호출부가 기존 false 동작을 유지한다', () {
      for (final bad in ['', 'abc', '16', '24:00', '16:99']) {
        expect(
            FormatHelper.kstWallClockInstant(
                FormatHelper.kstDayKeyOfCivil(_civilDay), bad),
            isNull,
            reason: bad);
      }
    });
  });

  group('[WB-E] 소스 계약', () {
    String code(String p) => File(p)
        .readAsStringSync()
        .replaceAll('\r\n', '\n')
        .split('\n')
        .where((l) => !l.trimLeft().startsWith('//'))
        .join('\n');

    const path =
        'lib/screens/business_admin/workforce_management/workforce_operational_view.dart';

    test('WB-12 화면이 canonical KST 결합을 쓴다', () {
      final c = code(path);
      expect(c.contains('kstWallClockInstant'), isTrue);
      expect(c.contains('DateTime(now.year, now.month, now.day, h, m)'), isFalse,
          reason: '기기 local 날짜·벽시계 결합이 이번 결함이었다');
    });

    test('WB-13 오늘 판정도 KST 기준이다', () {
      final c = code(path);
      expect(c.contains('FormatHelper.toKstDate(DateTime.now())'), isTrue,
          reason: '_today() 가 기기 날짜면 KST 자정 근처에서 날짜가 어긋난다');
    });

    test('WB-14 서버 writer·권한 조건은 건드리지 않았다', () {
      final c = code(path);
      for (final banned in [
        'callableBatchSetNoShow',
        'lateGrace',
        'canManageWorkers =',
      ]) {
        expect(c.contains(banned), isFalse, reason: banned);
      }
    });

    test('WB-15 표시 전용 — 판정이 mutation 을 막지 않는다', () {
      final c = code(path);
      // _isBeforeStart 는 집계·필터·칩에서만 쓰인다.
      final uses = RegExp(r'_isBeforeStart\(').allMatches(c).length;
      expect(uses, greaterThanOrEqualTo(3),
          reason: '정의 1 + 호출 3 — 호출부가 늘었다면 영향 범위를 다시 본다');
      expect(uses, lessThanOrEqualTo(4));
    });
  });
}
