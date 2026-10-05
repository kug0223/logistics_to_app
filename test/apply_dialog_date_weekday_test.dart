// [R7-CROSSCUT-TIME.1A] 날짜 숫자는 기기 시각, 요일은 KST 였다
//
// ApplyWorkDialog 의 세 자리가 라벨을 손으로 조립했다.
//
//   final dayOfWeek = FormatHelper.weekday(d);        // KST 정규화
//   '${d.month}/${d.day}($dayOfWeek)'                 // raw 필드
//
// `FormatHelper.weekday` 는 내부에서 `dt.toUtc().add(9h)` 로 KST 로
// 정규화하지만, 숫자는 그 DateTime 의 **필드를 그대로** 읽는다. 근무일은
// KST 자정 instant 로 저장되고 `Timestamp.toDate()` 는 기기 시각으로
// 읽히므로, KST 서쪽 기기에서는 두 값이 **서로 다른 날**을 말한다.
//
//   2026-10-05 00:00 KST  =  2026-10-04 15:00 UTC
//   UTC 기기:  숫자 10/4 · 요일 월(= 10/5)  → "10/4(월)"
//   그런데 2026-10-04 는 일요일이다.
//
// 이 파일이 고정하는 계약
//   · 한 라벨의 날짜 숫자와 요일은 **같은 canonical KST 영업일**에서 나온다
//   · 그 권위는 이미 있는 `FormatHelper.formatDateCompact` 하나다
//     (`'${kst.month}/${kst.day}(${요일})'` — 모양이 세 자리와 동일하다)
//   · 같은 instant 를 어떤 표현으로 넘겨도 라벨이 같다
//   · 기대 요일은 production helper 로 계산하지 않는다 — literal 이다
//     (테스트가 production 버그를 복제하지 않게)
//
// 범위: **표시(display)만**. `_appsDateKey` 기반 relation 조회(E7),
// wall-clock 시간 문자열, true instant(지원·확정 시각)는 건드리지 않는다.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:ALfit/utils/format_helper.dart';

const _dlg = 'lib/widgets/dialogs/apply/apply_work_dialog.dart';

String _src(String p) {
  final f = File(p);
  if (!f.existsSync()) throw StateError('소스를 찾지 못했다: $p');
  return f.readAsStringSync();
}

/// 주석을 지운 코드만.
String _codeOf(String path) {
  final out = StringBuffer();
  for (final line in _src(path).split('\n')) {
    final t = line.trimLeft();
    if (t.startsWith('//') || t.startsWith('*') || t.startsWith('/*')) continue;
    out.writeln(line);
  }
  return out.toString();
}

/// 같은 instant 의 세 표현 — 기기 timezone 을 바꾸지 않고 축을 재현한다.
///
///   R1 normalized key  : `toKstDate` 가 돌려주는 모양 (`DateTime.utc(y,m,d)`)
///   R2 KST 자정 instant, UTC 필드 : **UTC 기기**가 Timestamp 를 읽은 모양
///   R3 같은 instant, 기기 필드     : 이 테스트를 돌리는 기기의 모양
///
///   Dart 는 실행 중 host timezone 을 바꿀 수 없다. 그래서 "UTC 기기" 와
///   "음수 offset 기기" 를 **그 기기가 만들어 내는 값의 표현**으로 세운다 —
///   라벨 계산은 입력 DateTime 의 필드와 instant 만 보므로 등가다.
({DateTime key, DateTime utcFields, DateTime hostFields}) _reps(
    int y, int m, int d) {
  final key = DateTime.utc(y, m, d);
  final instant = key.subtract(const Duration(hours: 9)); // KST 자정 instant
  return (key: key, utcFields: instant, hostFields: instant.toLocal());
}

/// 한 영업일을 가리키는 **모든 표현** — 세 축을 한 곳에서 정의한다.
///   이 목록이 줄어들면 DW-AUTH-04 가 실패한다(경계 fixture 를 몰래 뺄 수 없다).
List<(String, DateTime)> _allReps(int y, int m, int d) {
  final r = _reps(y, m, d);
  return [
    ('normalized key', r.key),
    ('UTC 필드(UTC 기기)', r.utcFields),
    ('기기 필드', r.hostFields),
  ];
}

/// 프로덕션이 쓰던 조립 방식 — 왜 금지인지 보여주기 위해 테스트에 둔다.
String _splitLabel(DateTime d) =>
    '${d.month}/${d.day}(${FormatHelper.weekday(d)})';

void main() {
  // 대표 경계일 — 기대 요일은 **literal** 이다(§16).
  final cases = <({int y, int m, int d, String weekday})>[
    (y: 2026, m: 1, d: 1, weekday: '목'),
    (y: 2026, m: 2, d: 28, weekday: '토'),
    (y: 2026, m: 3, d: 1, weekday: '일'),
    (y: 2026, m: 10, d: 5, weekday: '월'),
    (y: 2026, m: 12, d: 31, weekday: '목'),
    (y: 2027, m: 1, d: 1, weekday: '금'),
  ];

  group('DW-AUTH canonical 권위 — formatDateCompact', () {
    test('DW-AUTH-01 날짜 숫자와 요일을 같은 KST 값에서 만든다', () {
      final code = _codeOf('lib/utils/format_helper.dart');
      expect(
          code.contains(
              "return '\${kst.month}/\${kst.day}(\${_weekdays[kst.weekday - 1]})';"),
          isTrue,
          reason: '한 번 정규화한 kst 하나로 숫자와 요일을 만든다');
      expect(code.contains('static DateTime _toKst(DateTime dt) => dt.toUtc().add(_kst);'),
          isTrue);
    });

    for (final c in cases) {
      test('DW-AUTH-02 ${c.y}-${c.m}-${c.d} 는 어떤 표현이어도 같은 라벨이다', () {
        final expected = '${c.m}/${c.d}(${c.weekday})';
        for (final rep in _allReps(c.y, c.m, c.d)) {
          expect(FormatHelper.formatDateCompact(rep.$2), expected,
              reason: '${rep.$1} 에서 라벨이 달라졌다');
        }
      });
    }

    test('DW-AUTH-04 세 축을 모두 덮는다 — 경계 fixture 를 몰래 뺄 수 없다', () {
      final reps = _allReps(2026, 10, 5);
      expect(reps.length, 3, reason: '표현 축이 줄어들면 결함이 다시 숨는다');
      final r = _reps(2026, 10, 5);
      expect(r.key.isUtc, isTrue);
      expect(r.key.day, 5);
      expect(r.utcFields.isUtc, isTrue);
      expect(r.utcFields.day, 4,
          reason: 'KST 자정은 UTC 전날이다 — 이것이 핵심 경계 셀이다');
      expect(r.hostFields.isUtc, isFalse);
      expect(r.utcFields.millisecondsSinceEpoch,
          r.hostFields.millisecondsSinceEpoch,
          reason: '같은 instant 의 다른 표현이어야 한다');
      // 대표 경계일 집합도 줄어들 수 없다.
      expect(cases.length, 6);
      for (final must in <(int, int)>[(1, 1), (2, 28), (3, 1), (10, 5), (12, 31)]) {
        expect(cases.any((c) => c.m == must.$1 && c.d == must.$2), isTrue,
            reason: '${must.$1}/${must.$2} 경계가 빠졌다');
      }
      expect(cases.any((c) => c.y == 2027), isTrue, reason: '연 경계가 빠졌다');
    });

    test('DW-AUTH-03 toKstDate 로 정규화해도 같은 라벨이다 — 이중 변환 없음', () {
      for (final c in cases) {
        final r = _reps(c.y, c.m, c.d);
        final expected = '${c.m}/${c.d}(${c.weekday})';
        expect(FormatHelper.formatDateCompact(FormatHelper.toKstDate(r.utcFields)),
            expected,
            reason: 'formatter 가 내부에서 또 KST 로 옮기면 하루가 밀린다');
      }
    });
  });

  group('DW-SPLIT 금지된 조립이 왜 금지인가', () {
    test('DW-SPLIT-01 숫자는 raw 필드, 요일은 KST → 서로 다른 날을 말한다', () {
      // 2026-10-05 00:00 KST = 2026-10-04 15:00 UTC
      final utcFields = _reps(2026, 10, 5).utcFields;
      expect(utcFields.month, 10);
      expect(utcFields.day, 4, reason: 'UTC 필드로는 전날이다');

      final bad = _splitLabel(utcFields);
      expect(bad, '10/4(월)', reason: '현재 결함이 만드는 라벨');
      // 그런데 2026-10-04 는 일요일이다 — 라벨이 자기 모순이다.
      expect(FormatHelper.formatDateCompact(DateTime.utc(2026, 10, 4)),
          '10/4(일)');
      expect(bad, isNot(FormatHelper.formatDateCompact(utcFields)),
          reason: '조립 방식이 canonical 과 갈린다');
    });

    test('DW-SPLIT-02 normalized key 에서는 숨는다 — 그래서 KST 기기에서 안 보였다', () {
      final key = _reps(2026, 10, 5).key;
      expect(_splitLabel(key), '10/5(월)');
      expect(_splitLabel(key), FormatHelper.formatDateCompact(key),
          reason: '표현에 따라 결함이 드러나거나 숨는다');
    });
  });

  group('DW-SRC 세 자리가 canonical formatter 를 쓴다', () {
    // 줄번호가 아니라 **함수 신원**으로 집는다.
    String fnBody(String name, String until) {
      final src = _codeOf(_dlg);
      final a = src.indexOf(name);
      expect(a, greaterThan(-1), reason: '함수를 찾지 못했다: $name');
      final b = src.indexOf(until, a);
      expect(b, greaterThan(a), reason: '끝 앵커를 찾지 못했다: $until');
      return src.substring(a, b);
    }

    test('DW-SRC-01 선택 가능 날짜 안내', () {
      final body = fnBody(
          'Widget _buildConflictWarningBox(', 'selectableText = \'선택 가능한 날짜가 없습니다\'');
      expect(body.contains('FormatHelper.formatDateCompact(_firstSelectableDate!)'),
          isTrue);
      expect(body.contains('_firstSelectableDate!.month'), isFalse,
          reason: 'raw 필드로 숫자를 만들면 요일과 갈린다');
    });

    test('DW-SRC-02 충돌 날짜 목록', () {
      final body = fnBody('Widget _buildConflictWarningBox(', '외 \${sortedDates.length - 3}개 날짜');
      expect(body.contains('FormatHelper.formatDateCompact(date)'), isTrue);
      expect(body.contains('\${date.month}/\${date.day}'), isFalse);
    });

    test('DW-SRC-03 장기공고 충돌 알림', () {
      final body =
          fnBody('Future<void> _showLongTermConflictAlert(', 'final extraCount =');
      expect(body.contains('FormatHelper.formatDateCompact(d)'), isTrue);
      expect(body.contains('\${d.month}/\${d.day}'), isFalse);
    });

    test('DW-SRC-04 날짜 숫자와 요일을 따로 만드는 자리가 남아 있지 않다', () {
      final src = _codeOf(_dlg);
      // `.month}/${...day}(` 뒤에 별도 요일 변수를 끼우는 모양을 금지한다.
      final split = RegExp(r'\$\{[A-Za-z_!.]+\.month\}/\$\{[A-Za-z_!.]+\.day\}\(\$dayOfWeek\)');
      expect(split.hasMatch(src), isFalse,
          reason: '남아 있으면 같은 결함이 그 자리에 다시 있다');
    });

    test('DW-SRC-05 화면 전용 날짜 helper 를 새로 만들지 않았다', () {
      final src = _codeOf(_dlg);
      for (final invented in [
        '_applyDialogDate', '_fixWeekday', 'DateTime _kstOf(',
      ]) {
        expect(src.contains(invented), isFalse, reason: invented);
      }
    });
  });

  group('DW-KEEP 범위 밖 무변경', () {
    test('DW-KEEP-01 relation 조회 키(_appsDateKey)는 그대로다', () {
      final src = _codeOf(_dlg);
      expect(src.contains('_appsDateKey('), isTrue,
          reason: 'E7 에서 닫은 relation 키를 이번에 열지 않는다');
    });

    test('DW-KEEP-02 wall-clock 시간 문자열을 timezone 변환하지 않는다', () {
      final src = _codeOf(_dlg);
      // 시간은 snapshot 문자열 그대로 쓴다.
      expect(src.contains('app.startTime'), isTrue);
      for (final bad in [
        'startTime.toUtc', 'startTime.toLocal', 'DateTime.parse(app.startTime',
      ]) {
        expect(src.contains(bad), isFalse, reason: bad);
      }
    });

    test('DW-KEEP-03 요일 사전과 문구를 바꾸지 않았다', () {
      final fh = _codeOf('lib/utils/format_helper.dart');
      expect(
          fh.contains("static const _weekdays = ['월', '화', '수', '목', '금', '토', '일'];"),
          isTrue);
    });

    test('DW-KEEP-04 DateTime 전역 치환을 하지 않았다 — 비교 키 구성 유지', () {
      final src = _codeOf(_dlg);
      // 장기 충돌 비교는 양쪽을 같은 방식으로 만든다(자기 일관) — 손대지 않았다.
      expect(src.contains('final dateKey = DateTime(currentDate.year, currentDate.month, currentDate.day);'),
          isTrue);
      expect(src.contains('confirmedDates.contains(dateKey)'), isTrue);
    });
  });
}
