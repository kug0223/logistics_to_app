// [R8-P9E] 어제 끝난 근무가 오늘의 답이 되지 않는다.
//
//   getTodayAttendance 는 오늘 문서가 없으면 어제 문서를 돌려줬다.
//   야간 근무(어제 22시 출근 → 오늘 새벽 퇴근) 때문에 필요한 폴백인데
//   조건이 없어서, 이미 끝난 어제 근무까지 오늘 기록인 것처럼 내려갔다.
//
//   소비부(attendance_check_screen)는 그것을 보고 오늘 근무 카드를 지운다.
//   장기 근무자는 계약 하나로 매일 일하고 오늘 문서는 출근 전까지 없으므로,
//   어제 정상 퇴근한 다음 날마다 오늘 근무와 출근 버튼이 함께 사라진다.
//
//   ※ DEV 에 장기 확정 근무가 0건이라 런타임 재현은 하지 못했다.
//     아래는 코드 경로를 그대로 옮긴 replica 고정이다.
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

// ── replica ──────────────────────────────────────────────────────
class _Att {
  final DateTime workDate;
  final DateTime? checkIn;
  final DateTime? checkOut;
  final String status;
  const _Att(this.workDate, {this.checkIn, this.checkOut, this.status = 'present'});
}

bool _finished(_Att a) =>
    a.checkOut != null ||
    a.status == 'missed_checkout' ||
    a.status == 'NO_SHOW' ||
    a.status == 'absent';

/// getTodayAttendance 의 조회 순서를 그대로 옮긴다.
_Att? _getTodayAttendance({
  required DateTime today,
  _Att? todayDoc,
  _Att? yesterdayDoc,
}) {
  if (todayDoc != null) return todayDoc;
  if (yesterdayDoc != null) {
    // [R8-P9E] 끝난 근무는 오늘에 대해 아무것도 말해 주지 않는다.
    if (_finished(yesterdayDoc)) return null;
    return yesterdayDoc;
  }
  return null;
}

void main() {
  const attSvc = 'lib/services/firestore/attendance_firestore.dart';
  const toSvc = 'lib/services/firestore/to_firestore.dart';

  final today = DateTime.utc(2026, 9, 22);
  final yesterday = DateTime.utc(2026, 9, 21);

  group('[R8P9E] 오늘 출근 기록의 의미', () {
    test('TA-1 오늘 문서가 있으면 그것을 쓴다', () {
      final t = _Att(today, checkIn: today);
      expect(_getTodayAttendance(today: today, todayDoc: t), same(t));
    });

    test('TA-2 오늘 문서가 없고 어제도 없으면 null', () {
      expect(_getTodayAttendance(today: today), isNull);
    });

    test('TA-3 어제 근무가 아직 진행 중이면 오늘의 답이다 (야간 근무)', () {
      // 어제 22시 출근, 아직 퇴근 전 — 오늘 필요한 것은 '퇴근하기'다.
      final y = _Att(yesterday, checkIn: yesterday);
      expect(_getTodayAttendance(today: today, yesterdayDoc: y), same(y),
          reason: '이 폴백이 존재하는 이유다 — 없애면 야간 근무가 깨진다');
    });

    test('TA-4 어제 정상 퇴근했으면 오늘의 답이 아니다', () {
      final y = _Att(yesterday, checkIn: yesterday, checkOut: yesterday);
      expect(_getTodayAttendance(today: today, yesterdayDoc: y), isNull,
          reason: '끝난 근무를 오늘 기록으로 주면 오늘 카드가 지워진다');
    });

    test('TA-5 어제 종료 상태들 전부 오늘의 답이 아니다', () {
      for (final s in ['missed_checkout', 'NO_SHOW', 'absent']) {
        final y = _Att(yesterday, checkIn: yesterday, status: s);
        expect(_getTodayAttendance(today: today, yesterdayDoc: y), isNull,
            reason: s);
      }
    });

    test('TA-6 오늘 문서가 있으면 어제 상태와 무관하다', () {
      final t = _Att(today, checkIn: today);
      final y = _Att(yesterday, checkIn: yesterday, checkOut: yesterday);
      expect(_getTodayAttendance(today: today, todayDoc: t, yesterdayDoc: y),
          same(t));
    });
  });

  group('[R8P9E] 소비부 계약 — 출근 CTA', () {
    test('TA-7 끝난 어제 기록은 서비스에서 걸러진다', () {
      final code = _flat(_codeOf(_read(attSvc)));
      expect(code.contains('if (date == yesterday && _isAttendanceFinished(att)) continue;'),
          isTrue);
      expect(code.contains('static bool _isAttendanceFinished(AttendanceModel att) =>'),
          isTrue);
    });

    test('TA-8 종료 판정 집합이 화면 쪽과 같다', () {
      final code = _flat(_codeOf(_read(attSvc)));
      for (final t in [
        'att.checkOut != null',
        "att.status == 'missed_checkout'",
        'att.status == AttendanceModel.statusNoShow',
        'att.status == AttendanceModel.statusAbsent',
      ]) {
        expect(code.contains(t), isTrue, reason: t);
      }
    });

    test('TA-9 야간 근무 폴백 자체는 남아 있다', () {
      final code = _flat(_codeOf(_read(attSvc)));
      expect(code.contains('for (final date in [todayStart, yesterday])'), isTrue,
          reason: '폴백을 통째로 없애면 야간 근무가 퇴근하지 못한다');
    });
  });

  group('[R8P9E] 정원 — 슬롯 문서 부재는 0 이 아니다', () {
    test('CAP-1 슬롯이 없으면 UNKNOWN 으로 올린다', () {
      final code = _flat(_codeOf(_read(toSvc)));
      expect(code.contains('if (!doc.exists) return {};'), isFalse,
          reason: '빈 맵은 소비부에서 `?? 0` 으로 읽혀 "정원 0"이 된다');
      expect(
          code.contains("throw StateError( 'getSlotWorkDetailCapacities: 슬롯 문서를 찾지 못했다"),
          isTrue);
    });

    test('CAP-2 조회 실패 rethrow 계약은 그대로다 (P7.3)', () {
      final code = _flat(_codeOf(_read(toSvc)));
      final i = code.indexOf('Future<Map<String, int>> getSlotWorkDetailCapacities(');
      expect(i, greaterThan(0));
      final body = code.substring(i, i + 1400);
      expect(body.contains('rethrow;'), isTrue);
    });
  });
}
