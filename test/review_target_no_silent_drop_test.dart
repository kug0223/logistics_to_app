// [R8-P9D] 리뷰 대상 집계에서 근로자가 조용히 빠지지 않는다.
//
//   장기/단기 분류와 장기 집계가 서로 다른 정의를 쓰고 있었다.
//
//     분류(581-597) : workDays 가 없어도 workDate != workEndDate 면 장기
//     집계(626)     : workDays 가 있어야 장기
//
//   그 사이에 낀 지원서는 단기 집계에서도(longTermIds 라서) 장기 집계에서도
//   (workDays 가 비어서) 세어지지 않았다. 어느 쪽에도 없는 근로자가 된다.
//   DEV 의 장기 확정 지원서 1건이 정확히 이 형태다.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String p) {
  final f = File(p);
  if (!f.existsSync()) throw StateError('파일을 찾지 못했다: $p');
  return f.readAsStringSync();
}

String _codeOf(String src) => src
    .split('\n')
    .where((l) => !l.trimLeft().startsWith('//'))
    .join('\n');

String _flat(String s) => s.replaceAll(RegExp(r'\s+'), ' ');

/// monthly_review_service._countWorkingDaysInMonth 의 replica.
/// 요일 목록이 비면 기간 안의 모든 날을 센다.
int _countWorkingDays(
  List<String> workDayNames,
  int year,
  int month,
  DateTime contractStart,
  DateTime contractEnd,
) {
  const names = ['월', '화', '수', '목', '금', '토', '일'];
  final monthStart = DateTime(year, month, 1);
  final monthEnd = DateTime(year, month + 1, 0);
  final effectiveStart =
      contractStart.isAfter(monthStart) ? contractStart : monthStart;
  final effectiveEnd = contractEnd.isBefore(monthEnd) ? contractEnd : monthEnd;
  if (effectiveStart.isAfter(effectiveEnd)) return 0;
  var count = 0;
  var cursor = effectiveStart;
  while (!cursor.isAfter(effectiveEnd)) {
    if (workDayNames.isEmpty ||
        workDayNames.contains(names[cursor.weekday - 1])) {
      count++;
    }
    cursor = cursor.add(const Duration(days: 1));
  }
  return count;
}

void main() {
  const svc = 'lib/services/monthly_review_service.dart';

  group('[R8P9D] 근무일 집계 — 빈 요일 목록은 "0일"이 아니다', () {
    test('RT-1 요일 목록이 비면 기간 안의 모든 날을 센다', () {
      // 2026-09-10 ~ 2026-09-14, 9월 → 5일
      final n = _countWorkingDays(
        const [],
        2026,
        9,
        DateTime(2026, 9, 10),
        DateTime(2026, 9, 14),
      );
      expect(n, 5, reason: '빈 목록을 "해당 요일 없음"으로 읽으면 0이 된다');
    });

    test('RT-2 요일 목록이 있으면 그 요일만 센다 (기존 동작)', () {
      // 2026-09-01(화) ~ 2026-09-30(수) 중 월요일: 7,14,21,28 → 4일
      final n = _countWorkingDays(
        const ['월'],
        2026,
        9,
        DateTime(2026, 9, 1),
        DateTime(2026, 9, 30),
      );
      expect(n, 4);
    });

    test('RT-3 기간이 달 밖이면 0이다 (정상 0은 유지)', () {
      final n = _countWorkingDays(
        const [],
        2026,
        9,
        DateTime(2026, 10, 1),
        DateTime(2026, 10, 5),
      );
      expect(n, 0, reason: '실제로 그 달 근무가 없는 경우는 여전히 0이다');
    });

    test('RT-4 기간이 달 경계를 넘으면 겹치는 부분만 센다', () {
      // 8/25 ~ 9/3 → 9월분은 9/1,2,3 = 3일
      final n = _countWorkingDays(
        const [],
        2026,
        9,
        DateTime(2026, 8, 25),
        DateTime(2026, 9, 3),
      );
      expect(n, 3);
    });
  });

  group('[R8P9D] 소비부 계약', () {
    test('RT-5 장기 집계가 빈 workDays 로 버리지 않는다', () {
      final code = _flat(_codeOf(_read(svc)));
      expect(
          code.contains('if (uid.isEmpty || workDaysList == null || workDaysList.isEmpty) continue;'),
          isFalse,
          reason: '분류는 장기로 넣어 놓고 집계에서 버리던 자리');
      expect(code.contains('if (uid.isEmpty) continue;'), isTrue);
      expect(code.contains('(workDaysList ?? const []).whereType<String>()'), isTrue);
    });

    test('RT-6 카운터가 빈 목록을 전 요일로 취급한다', () {
      final code = _flat(_codeOf(_read(svc)));
      expect(
          code.contains('if (workDayNames.isEmpty || workDayNames.contains(FormatHelper.weekday(cursor)))'),
          isTrue);
    });

    test('RT-7 분류 규칙 자체는 건드리지 않았다', () {
      final code = _flat(_codeOf(_read(svc)));
      expect(code.contains('if (workDaysList != null && workDaysList.isNotEmpty) { longTermIds.add(docId); continue; }'),
          isTrue, reason: '장기/단기 분류는 이번 변경 대상이 아니다');
      expect(code.contains('if (!sameDay) longTermIds.add(docId);'), isTrue);
    });

    test('RT-8 개방형 계약(workEndDate null) 처리는 그대로다', () {
      final code = _flat(_codeOf(_read(svc)));
      expect(code.contains('if (workEndDate != null && workEndDate.isBefore(monthStart)) continue;'),
          isTrue, reason: 'workEndDate null 을 "제외"로 바꾸면 안 된다');
    });
  });
}
