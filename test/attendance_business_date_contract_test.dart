// [PREDEVICE] 근태 영업일은 Asia/Seoul 달력 날짜다
//
// READ에서 확인된 것:
//   · AttendanceStatusDialog는 쿼리 창을 `DateTime(y,m,d)`(기기 로컬 자정)로
//     만들면서, 같은 함수 안의 비교 키는 FormatHelper.toKstDate(KST)로 만들었다.
//     한 화면이 두 달력을 섞어 쓴 것이다.
//   · getTodayAttendance는 문서 ID의 날짜 문자열을 기기 로컬 자정으로 만들었다.
//     서버(callableCheckIn)는 그 ID를 KST로 만든다.
//   · getTodayAttendanceByBusiness / getTodayConfirmedWorkers /
//     getWeeklyAttendanceByBusiness도 같은 로컬 자정 창을 썼다.
//
// DEV runtime(America/New_York):
//   관리자가 2026-07-26을 고르면
//     로컬 자정 창 = KST 07-26 13:00 ~ 07-27 13:00 → 0건
//     KST 창       = KST 07-26 00:00 ~ 07-27 00:00 → 1건
//   즉 비KST 기기에서 그 날의 근무가 통째로 사라졌다.
//
// 계약:
//   영업일 창과 비교 키는 같은 달력에서 나와야 하고, 그 달력은 KST다.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ALfit/utils/format_helper.dart';

const _dialogPath =
    'lib/screens/business_admin/dialogs/attendance_status_dialog.dart';
const _attFsPath = 'lib/services/firestore/attendance_firestore.dart';

String _src(String p) {
  final f = File(p);
  if (!f.existsSync()) throw StateError('$p 를 찾지 못함');
  return f.readAsStringSync();
}

String _codeOf(String b) =>
    b.split('\n').where((l) => !l.trimLeft().startsWith('//')).join('\n');

void main() {
  group('영업일 창을 기기 로컬 자정으로 만들지 않는다', () {
    test('AttendanceStatusDialog의 두 창 모두 kstDayRange를 쓴다', () {
      final code = _codeOf(_src(_dialogPath));
      expect(
        code.contains('DateTime(widget.date.year, widget.date.month'),
        false,
        reason: '기기 로컬 자정 창이 남아 있으면 비KST 기기에서 하루가 밀린다',
      );
      // [CROSS-SLICE-1A] 개수를 못 박지 않는다. 이 단언이 지키려는 것은
      //   "이 화면의 날짜 창은 전부 KST"이지 "창이 두 개"가 아니다.
      //   실제로 모집 단위 종료 여부를 읽는 세 번째 창이 생겼고, 그것도 KST다.
      //   개수를 고정하면 올바른 창이 늘어날 때마다 깨진다.
      //   진짜 가드는 위의 기기 로컬 자정 금지다.
      expect(
        'FormatHelper.kstDayRange(widget.date)'.allMatches(code).length >= 2,
        true,
        reason: '확정 명단 창과 근태 조회 창을 포함해 모든 창이 KST여야 한다',
      );
    });

    test('오늘 근태/확정자 조회도 KST 영업일 창을 쓴다', () {
      final code = _codeOf(_src(_attFsPath));
      expect(
        'FormatHelper.kstDayRange(DateTime.now())'.allMatches(code).length >= 2,
        true,
        reason: '오늘 창이 기기 로컬이면 근태와 확정 명단이 어긋난다',
      );
    });

    // [BACKLOG-DEAD-UNCLOSED-DART] getUnclosedDaysCount는 호출자가 없다.
    //   관리자 홈의 "마감 필요"는 CF srvHomeUnclosed(KST)가 계산한다. 이 Dart
    //   구현은 기기 로컬 달력으로 날짜를 세고 close 조건도 다르다
    //   (totalConfirmed != closedCount). 살아 있는 화면이 아니므로 이번
    //   범위에서 고치지 않되, 되살리면 두 숫자가 갈라진다는 사실을 고정한다.
    test('죽은 Dart 마감 카운터가 되살아나면 알아차린다', () {
      final code = _codeOf(_src(_attFsPath));
      final hasDead =
          code.contains('Future<int> getUnclosedDaysCount({');
      if (!hasDead) return; // 제거됐다면 이 계약도 끝난다.
      expect(
        code.contains('final todayOnly = DateTime(today.year'),
        true,
        reason: 'KST로 고쳤다면 이 테스트를 삭제하고 BACKLOG 항목도 닫아야 한다',
      );
    });

    test('근태 문서 ID의 날짜도 KST로 만든다 — 서버와 같은 규칙', () {
      final code = _codeOf(_src(_attFsPath));
      expect(code.contains('FormatHelper.toKstDate(DateTime.now())'), true,
          reason: 'callableCheckIn이 KST로 만든 ID를 로컬 날짜로 찾을 수 없다');
    });

    test('주간 창의 양 끝도 KST 경계다', () {
      final code = _codeOf(_src(_attFsPath));
      expect(code.contains('DateTime(weekStart.year'), false);
      expect(code.contains('FormatHelper.kstDayRange(weekStart)'), true);
      expect(code.contains('FormatHelper.kstDayRange(weekEnd)'), true);
    });
  });

  group('kstDayRange는 기기 시간대와 무관하게 같은 KST 하루를 고른다', () {
    test('입력이 어떤 offset이든 창은 KST 자정에서 자정까지다', () {
      // 같은 순간을 서로 다른 표현으로 주어도 같은 창이 나와야 한다.
      final kstNoon = DateTime.utc(2026, 7, 26, 3); // = KST 07-26 12:00
      final (s1, e1) = FormatHelper.kstDayRange(kstNoon);
      final (s2, e2) = FormatHelper.kstDayRange(kstNoon.toLocal());
      expect(s1, s2);
      expect(e1, e2);

      // 창의 시작은 KST 07-26 00:00 = UTC 07-25 15:00
      expect(s1.toUtc(), DateTime.utc(2026, 7, 25, 15));
      expect(e1.toUtc(), DateTime.utc(2026, 7, 26, 15));
      expect(e1.difference(s1), const Duration(days: 1));
    });

    test('KST 자정 직후와 직전이 서로 다른 날에 들어간다', () {
      final justAfterMidnightKst = DateTime.utc(2026, 7, 25, 15, 1);
      final justBeforeMidnightKst = DateTime.utc(2026, 7, 25, 14, 59);
      final (a, _) = FormatHelper.kstDayRange(justAfterMidnightKst);
      final (b, _) = FormatHelper.kstDayRange(justBeforeMidnightKst);
      expect(a.difference(b), const Duration(days: 1),
          reason: 'KST 자정이 경계여야 한다');
    });
  });
}
