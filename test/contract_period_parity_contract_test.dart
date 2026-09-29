// [OPEN-CONTRACT-MONTHEND] 계약 기간 종료일 — 클라이언트 식과 서버 식의 대조.
//
//   이 파일은 **결함을 고정한다.** 아래 기대값은 바람직한 결과가 아니라
//   지금 실제로 벌어지는 차이다. 어느 쪽 식이든 바뀌면 이 셀들이 먼저
//   깨지고, 그때 정책 결정을 다시 꺼내게 된다.
//
// ── 사실 관계 (R7-FS-MONTHEND 감사) ──────────────────────────────
//
//   `workEndDate` 의 의미는 **마지막 근무 가능일(inclusive)** 이다.
//     · `ApplicationModel.effectiveEndDate` 주석: "이 약속의 마지막 근무 가능일"
//     · `occupiesSeatOn(day)`: `!end.isBefore(day)` → end 당일도 좌석을 차지
//     · `isWorkingOnDate`: `target.isAfter(end)` 면 근무 아님
//
//   그 값을 만드는 식이 **두 벌**이다.
//
//     1) 클라이언트 `TOModel.computeContractEndDate`
//        `(start + N개월, 월말 clamp) - 1일`  → 시작일 포함 N개월
//        쓰이는 곳: 지원 화면의 기간 카드 표시,
//                   `application.workEndDate` 최초 저장(PENDING)
//
//     2) 서버 `callableConfirmApplication` (functions/src/index.ts)
//        `d.setMonth(d.getMonth() + N)`  → **`-1일` 이 없고 clamp 도 없다**
//        쓰이는 곳: 확정 시 `workEndDate` **덮어쓰기**([M2-FIX] 주석이
//                   "클라이언트 조작값 무시, 항상 서버 TO 기준 계산" 이라 적고 있다)
//                   → 계약서 제2조 `contractEnd`, 만료 알림, 좌석·근무 판정
//
//   그래서 근로자가 지원할 때 본 종료일과 계약서에 찍히는 종료일이 다르다.
//   차이는 월말에 국한되지 않는다 — **모든 기간 유형에서 최소 1일**이고,
//   월말 시작에서는 2~4일까지 벌어진다.
//
//   어느 쪽으로 맞출지는 법률·제품 결정이다. 이 감사에서는 **식을 고치지
//   않았다.** 판정·근거·영향은 `docs/r7-contract-monthend-audit.md`.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ALfit/models/core/to_model.dart';

// ── 서버 식을 Dart 로 옮긴 것 ─────────────────────────────────────
//   `Date#setMonth` / `setFullYear` 의 오버플로 동작을 그대로 재현한다.
//   Dart `DateTime(y, m, d)` 도 같은 방식으로 넘치는 날짜를 이월한다.
DateTime serverEndDate(DateTime start, String periodType) {
  switch (periodType) {
    case '15days':
      return DateTime(start.year, start.month, start.day + 15);
    case '1month':
      return DateTime(start.year, start.month + 1, start.day);
    case '3months':
      return DateTime(start.year, start.month + 3, start.day);
    case '6months':
      return DateTime(start.year, start.month + 6, start.day);
    case '1year':
      return DateTime(start.year + 1, start.month, start.day);
  }
  throw ArgumentError(periodType);
}

TOModel _to(String periodType) => TOModel(
      id: 'to1',
      businessId: 'biz1',
      businessName: '테스트 사업장',
      title: '테스트 공고',
      type: TOType.contract,
      contractPeriodType: periodType,
      creatorUID: 'uid-001',
      createdAt: DateTime(2026, 1, 1),
    );

String _d(DateTime v) =>
    '${v.year}-${v.month.toString().padLeft(2, '0')}-'
    '${v.day.toString().padLeft(2, '0')}';

int _dayGap(DateTime a, DateTime b) =>
    DateTime(b.year, b.month, b.day)
        .difference(DateTime(a.year, a.month, a.day))
        .inDays;

void main() {
  // ══════════════════════════════════════════════════════════════
  // CPP-A. 서버 식이 소스에 그대로 있는지 — 앵커
  // ══════════════════════════════════════════════════════════════
  group('CPP-A. 서버 식 앵커', () {
    late final String cf;

    setUpAll(() {
      final f = File('functions/src/index.ts');
      expect(f.existsSync(), isTrue);
      cf = f.readAsStringSync().replaceAll('\r\n', '\n');
    });

    test('CPP-A1 확정 시 서버가 workEndDate 를 다시 계산해 덮어쓴다', () {
      expect(cf.contains('[M2-FIX] !appDataPre.workEndDate 조건 제거'), isTrue,
          reason: '클라이언트 값을 무시한다는 기록');
      expect(cf.contains('if (computedWorkEndDate) '
          'batchUpdate.workEndDate = computedWorkEndDate;'), isTrue);
    });

    test('CPP-A2 서버 식에는 -1일도, 월말 clamp도 없다', () {
      expect(
          cf.contains('if (periodType === "15days") '
              'd.setDate(d.getDate() + 15);'),
          isTrue);
      expect(
          cf.contains('else if (periodType === "1month") '
              'd.setMonth(d.getMonth() + 1);'),
          isTrue);
      expect(
          cf.contains('else if (periodType === "1year") '
              'd.setFullYear(d.getFullYear() + 1);'),
          isTrue);
      // 서버 쪽 helper 는 폐기됐고 이 인라인 식이 유일하다.
      expect(
          cf.contains('[DECOMMISSIONED] _addMonthsKST, _kstDaysDiff, '
              '_fmtKST, computeContractEndDateMs 제거됨'),
          isTrue);
    });

    test('CPP-A3 계약서 제2조는 그 저장값을 그대로 찍는다', () {
      final svc = File('lib/services/contract_service.dart')
          .readAsStringSync()
          .replaceAll('\r\n', '\n');
      expect(
          svc.contains('contractEnd: isLong && application.workEndDate != null'),
          isTrue,
          reason: '계약서는 재계산하지 않는다');
    });
  });

  // ══════════════════════════════════════════════════════════════
  // CPP-B. 두 식의 실측 차이 — 전 기간 유형
  // ══════════════════════════════════════════════════════════════
  group('CPP-B. 클라이언트 != 서버 (측정값 고정)', () {
    // 기산일 2026-01-01 (월 첫날), 기기 달력 기준.
    final start = DateTime(2026, 1, 1);

    // periodType : [클라이언트, 서버]
    const expected = <String, List<String>>{
      '15days': ['2026-01-15', '2026-01-16'],
      '1month': ['2026-01-31', '2026-02-01'],
      '3months': ['2026-03-31', '2026-04-01'],
      '6months': ['2026-06-30', '2026-07-01'],
      '1year': ['2026-12-31', '2027-01-01'],
    };

    expected.forEach((type, pair) {
      test('CPP-B $type — 서버가 하루 더 길다', () {
        final c = _to(type).computeContractEndDate(start);
        final s = serverEndDate(start, type);
        expect(_d(c), pair[0], reason: '클라이언트 식');
        expect(_d(s), pair[1], reason: '서버 식(확정 시 덮어쓰는 값)');
        expect(_dayGap(c, s), 1,
            reason: '서버 식에 `- 1일` 이 없다 — inclusive 의미에서 하루 길다');
      });
    });

    test('CPP-B0 클라이언트 식은 시작일 포함 N개월과 일치한다', () {
      // 이 줄이 "클라이언트가 맞고 서버가 틀렸다" 는 근거다.
      expect(_dayGap(start, _to('1month').computeContractEndDate(start)) + 1,
          31, reason: '2026-01-01 ~ 01-31 = 31일 = 1월 전체');
      expect(_dayGap(start, _to('15days').computeContractEndDate(start)) + 1,
          15, reason: '시작일 포함 15일');
      expect(_dayGap(start, _to('1year').computeContractEndDate(start)) + 1,
          365, reason: '2026 전체');
    });
  });

  // ══════════════════════════════════════════════════════════════
  // CPP-C. 월말 시작 — 차이가 더 벌어진다
  // ══════════════════════════════════════════════════════════════
  group('CPP-C. 월말 기산 경계', () {
    // [기산일, 기간, 클라이언트, 서버, 차이(일), 민법 160③ 해석]
    const cases = <List<Object>>[
      // 평년 2월: 해당일(31일)이 없다
      [2026, 1, 31, '1month', '2026-02-27', '2026-03-03', 4, '2026-02-28'],
      // 윤년 2월: 29일까지 있다
      [2028, 1, 31, '1month', '2028-02-28', '2028-03-02', 3, '2028-02-29'],
      // 30일 시작 — 2월에 해당일 없음
      [2026, 1, 30, '1month', '2026-02-27', '2026-03-02', 3, '2026-02-28'],
      [2026, 1, 29, '1month', '2026-02-27', '2026-03-01', 2, '2026-02-28'],
      // 31일 → 30일 달
      [2026, 3, 31, '1month', '2026-04-29', '2026-05-01', 2, '2026-04-30'],
      [2026, 8, 31, '6months', '2027-02-27', '2027-03-03', 4, '2027-02-28'],
      // 윤일 기산
      [2028, 2, 29, '1year', '2029-02-27', '2029-03-01', 2, '2029-02-28'],
    ];

    for (final c in cases) {
      final y = c[0] as int, m = c[1] as int, day = c[2] as int;
      final type = c[3] as String;
      test('CPP-C $y-$m-$day + $type', () {
        final start = DateTime(y, m, day);
        final cl = _to(type).computeContractEndDate(start);
        final sv = serverEndDate(start, type);
        expect(_d(cl), c[4] as String, reason: '클라이언트: clamp 후 -1일');
        expect(_d(sv), c[5] as String, reason: '서버: clamp 없이 이월');
        expect(_dayGap(cl, sv), c[6] as int);

        // 민법 160조 ②③ 해석값(기산일 해당일의 전일, 해당일 없으면 그 월의
        // 말일)과도 **양쪽 모두** 어긋난다는 것을 함께 적는다.
        //   클라이언트는 하루 짧고, 서버는 그보다 더 길다.
        final civil = c[7] as String;
        expect(_d(cl) == civil, isFalse,
            reason: '클라이언트도 민법 해석과 다르다(하루 짧다)');
        expect(_d(sv) == civil, isFalse, reason: '서버도 다르다(더 길다)');
      });
    }

    test('CPP-C0 월중 기산에서는 클라이언트가 민법 해석과 일치한다 (정상 대조)', () {
      // 월말이 아니면 해당일이 있으므로 160②(해당일의 전일)이 곧
      // `(start + N개월) - 1일` 이다. 즉 클라이언트 식의 결손은
      // **월말 시작 한 경우에 국한**된다.
      final start = DateTime(2026, 5, 15);
      expect(_d(_to('1month').computeContractEndDate(start)), '2026-06-14');
      // 서버는 이 정상 경우에도 하루 길다.
      expect(_d(serverEndDate(start, '1month')), '2026-06-15');
    });
  });

  // ══════════════════════════════════════════════════════════════
  // CPP-D. 클라이언트 식 자체는 기기 달력 성분을 쓴다
  // ══════════════════════════════════════════════════════════════
  group('CPP-D. 계산의 자(尺)', () {
    test('CPP-D1 입력의 달력 성분만 쓴다 — `toKstDate` 를 지나지 않는다', () {
      // 같은 KST 하루를 서로 다른 instant 로 주면 결과가 갈린다.
      // 기산일을 어느 자로 만들어 넘기는지는 호출부 책임이고,
      // 지원 화면은 캘린더가 고른 **기기 로컬** 날짜를 그대로 넘긴다.
      final to = _to('1month');

      // 월중 기산: 성분이 하루 다르면 결과도 하루 다르다.
      expect(_d(to.computeContractEndDate(DateTime(2026, 5, 15))),
          '2026-06-14');
      expect(
          _d(to.computeContractEndDate(DateTime.utc(2026, 5, 14, 15))),
          '2026-06-13',
          reason: 'KST 5/15 00:00 과 같은 순간인데 UTC 성분은 5/14 다');

      // 월말 기산에서는 clamp 가 차이를 흡수해 **우연히** 같아진다 —
      // 같은 값이 나온다고 시간대 안전한 것이 아니다.
      expect(_d(to.computeContractEndDate(DateTime(2026, 1, 31))),
          '2026-02-27');
      expect(_d(to.computeContractEndDate(DateTime.utc(2026, 1, 30, 15))),
          '2026-02-27', reason: 'clamp 가 흡수한 우연한 일치');
    });
  });
}
