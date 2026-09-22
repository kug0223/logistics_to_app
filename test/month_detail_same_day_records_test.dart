import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// ═══════════════════════════════════════════════════════════════
// R7-PRE1  MONTH-DETAIL-SAME-DAY-RECORDS
//
//   같은 날 두 건을 근무하는 것은 정상이다.
//   오전 사무, 오후 행사 — 지원서가 다르니 근태 문서도 별개다.
//
//   월 상세는 그 둘을 (userId, workDate) 키로 합쳐 하나만 남겼다.
//   그러면 두 번째 근무가 정상/지각/결근 건수에서도, **급여 합계에서도**
//   사라진다. 그리고 같은 화면의 근태 Excel 은 원본(rawAttendance)을
//   그대로 찍어서, 파일과 화면이 같은 달을 다르게 말했다.
//
//   DEV 실측(2026-09, 위워커):
//     확정·이체 288,000원 → (사람,날짜) 키로 거르면 168,000원
//     같은 날 2건 이상: 09-20 3건 · 09-21 2건
//     Excel 12행 vs 화면 9건
//
//   고친 뒤:
//     중복 제거 키 = 문서 id (진짜 중복만)
//     '일수'만 날짜 수로 따로 센다 — 화면이 '${totalDays}일' 로 찍으므로.
//     Excel 이 쓰는 rawAttendance 도 같은 목록을 본다.
// ═══════════════════════════════════════════════════════════════

const _svcPath = 'lib/services/admin_stats_service.dart';
const _screenPath = 'lib/screens/business_admin/admin_month_detail_screen.dart';

String _src(String p) => File(p).readAsStringSync();

String _codeOf(String b) => b
    .split('\n')
    .where((l) {
      final t = l.trimLeft();
      return !t.startsWith('//') && !t.startsWith('*') && !t.startsWith('/*');
    })
    .join('\n');

String _flat(String s) => s.replaceAll(RegExp(r'\s+'), ' ');

/// `signature` 부터 중괄호가 다시 닫힐 때까지.
/// 테스트 밖(main 최상단)에서도 부르므로 expect/fail 을 쓰지 않는다.
String _bodyOf(String source, String signature) {
  final start = source.indexOf(signature);
  if (start < 0) throw StateError('$signature 를 찾지 못함');
  // 먼저 파라미터 괄호를 닫는다 — 이름있는 파라미터의 `{`를 본문으로 오인하지 않게.
  var paren = 0;
  var afterParams = start;
  for (var i = source.indexOf('(', start); i < source.length; i++) {
    if (source[i] == '(') paren++;
    if (source[i] == ')') {
      paren--;
      if (paren == 0) { afterParams = i; break; }
    }
  }
  final open = source.indexOf('{', afterParams);
  var depth = 0;
  for (var i = open; i < source.length; i++) {
    if (source[i] == '{') depth++;
    if (source[i] == '}') {
      depth--;
      if (depth == 0) return source.substring(start, i + 1);
    }
  }
  throw StateError('$signature 본문의 끝을 찾지 못함');
}

void main() {
  final svc = _src(_svcPath);
  final monthDetail = _codeOf(_bodyOf(svc, 'Future<MonthDetailData> getMonthDetail('));
  final flat = _flat(monthDetail);

  group('MDS-1x 중복 제거는 진짜 중복만 거른다', () {
    test('MDS-10 (userId, workDate) 키를 쓰지 않는다', () {
      expect(
          flat.contains(r"'${a.userId}_${a.workDate.millisecondsSinceEpoch}'"),
          isFalse,
          reason: '이 키는 같은 날 두 번째 근무를 통째로 지운다 — 금액까지.');
    });

    test('MDS-11 문서 id 로 거른다', () {
      expect(flat.contains('attendance.where((a) => seen.add(a.id))'), isTrue,
          reason: '사업장 병렬 조회가 같은 문서를 두 번 담는 경우만 막으면 된다.');
    });
  });

  group('MDS-2x 일수와 건수를 구분한다', () {
    test('MDS-20 totalDays 는 날짜 수다', () {
      // records.length 를 그대로 쓰면 같은 날 2건이 '2일'로 찍힌다.
      expect(flat.contains('totalDays: records.length'), isFalse,
          reason: "화면이 '\${totalDays}일' 로 찍는다 — 건수를 일수로 부르면 안 된다.");
      expect(
          flat.contains(
              'totalDays: records .map((r) => r.workDate.millisecondsSinceEpoch) .toSet() .length'),
          isTrue,
          reason: '일수는 서로 다른 근무일의 개수다.');
    });

    test('MDS-21 화면은 여전히 일 단위로 표시한다', () {
      final screen = _flat(_codeOf(_src(_screenPath)));
      expect(screen.contains(r"'${worker.totalDays}일'"), isTrue,
          reason: '이 라벨이 바뀌면 totalDays 의 의미도 다시 정해야 한다.');
    });
  });

  group('MDS-3x 화면과 파일이 같은 목록을 본다', () {
    test('MDS-30 rawAttendance 가 중복 제거된 목록이다', () {
      expect(flat.contains('rawAttendance: dedupedAttendance'), isTrue,
          reason: 'Excel 이 이것을 그대로 찍는다 — 원본을 주면 파일이 화면보다 많아진다.');
      expect(flat.contains('rawAttendance: attendance,'), isFalse);
    });

    test('MDS-31 금액 집계도 같은 목록에서 나온다', () {
      // 두 곳(직원별·월 합계) 모두 dedupedAttendance 를 순회해야 한다.
      final occurrences =
          'dedupedAttendance'.allMatches(monthDetail).length;
      expect(occurrences >= 3, isTrue,
          reason: '선언 + 직원별 집계 + 월 합계 + rawAttendance — 최소 4회 쓰인다. '
              '한 곳이라도 원본을 보면 그 숫자만 달라진다. (현재 $occurrences회)');
    });

    test('MDS-32 근태 Excel 은 rawAttendance 만 읽는다', () {
      final screen = _flat(_codeOf(_src(_screenPath)));
      expect(screen.contains('for (final r in data.rawAttendance)'), isTrue);
      expect(
          screen.contains('_writeAttendanceRows(sheet, data.rawAttendance'),
          isTrue,
          reason: '파일의 모집단이 화면 집계와 같은 출처라는 것을 고정해 둔다.');
    });
  });
}
