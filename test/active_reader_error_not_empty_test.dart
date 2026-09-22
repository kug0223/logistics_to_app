// [R8-P7.2] 조회 실패를 "없음"으로 바꾸지 않는다.
//
//   DEV 런타임 스모크에서 두 reader 가 계속 INTERNAL 이었다 —
//   복합 인덱스가 정의된 적이 없었다. 그런데 아무도 몰랐다.
//   서비스가 실패를 빈 목록으로 삼켜서, 화면에는 "중간정산 없음",
//   "변경 요청 없음" 으로 보였기 때문이다.
//
//   인덱스는 firestore.indexes.json 에 넣었고, 삼키던 자리는 rethrow 로 바꿨다.
//   이 테스트는 그 둘이 함께 되돌아가지 않도록 고정한다.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String p) {
  final f = File(p);
  if (!f.existsSync()) throw StateError('파일을 찾지 못했다: $p');
  return f.readAsStringSync();
}

/// 주석을 지운 코드만 남긴다 — 표지를 주석에 두지 않기 위해.
String _codeOf(String src) => src
    .split('\n')
    .where((l) => !l.trimLeft().startsWith('//'))
    .join('\n');

String _slice(String raw, String from, String to) {
  final s = raw.indexOf(from);
  if (s < 0) throw StateError('시작 표지를 찾지 못했다: $from');
  final e = raw.indexOf(to, s + from.length);
  if (e < 0) throw StateError('끝 표지를 찾지 못했다: $to');
  return raw.substring(s, e);
}

String _flat(String s) => s.replaceAll(RegExp(r'\s+'), ' ');

/// 함수 본문의 **catch 블록만** 본다.
///   조기 반환(`if (ids.isEmpty) return [];`)은 정당한 빈 결과이므로 건드리지 않는다.
///   문제는 오류를 빈 값으로 바꾸는 것뿐이다.
void _expectPropagates(String file, String fnStart, String reason) {
  final code = _codeOf(_read(file));
  final s = code.indexOf(fnStart);
  if (s < 0) throw StateError('함수를 찾지 못했다: $fnStart');
  final c = code.indexOf('} catch (', s);
  if (c < 0) throw StateError('catch 블록을 찾지 못했다: $fnStart');
  // catch 블록 끝 = 중괄호 균형
  final open = code.indexOf('{', c + 2);
  var depth = 0;
  var end = open;
  for (var k = open; k < code.length; k++) {
    if (code[k] == '{') depth++;
    if (code[k] == '}') { depth--; if (depth == 0) { end = k; break; } }
  }
  final body = _flat(code.substring(open, end + 1));
  expect(body.contains('rethrow'), isTrue, reason: reason);
  expect(RegExp(r'return\s*(const\s*)?(<[^>]*>)?\s*\[\s*\]\s*;').hasMatch(body), isFalse,
      reason: '$reason — catch 안에서 빈 목록을 돌려준다');
  expect(RegExp(r'return\s*(const\s*)?(<[^>]*>)?\s*\{\s*\}\s*;').hasMatch(body), isFalse,
      reason: '$reason — catch 안에서 빈 맵을 돌려준다');
}

void main() {
  group('[R8P7.2] 돈 — 실패를 "정산 없음"으로 말하지 않는다', () {
    const f = 'lib/services/payroll_payment_service.dart';

    test('AR-1 내 중간정산 목록', () {
      _expectPropagates(f,
          'Future<List<InterimSettlementRequestModel>> getMyInterimSettlements(',
          '근로자가 신청이 사라진 줄 안다');
    });

    test('AR-2 관리자 중간정산 요청 목록', () {
      _expectPropagates(f,
          'Future<List<InterimSettlementRequestModel>> getPendingSettlementRequests(',
          '처리해야 할 요청이 화면에서 사라진다');
    });
  });

  group('[R8P7.2] 근태·일정 — 실패를 "기록 없음"으로 말하지 않는다', () {
    const f = 'lib/services/firestore/attendance_firestore.dart';

    test('AR-3 날짜별 스케줄 변경 요청', () {
      _expectPropagates(f,
          'Future<List<ScheduleChangeRequestModel>> getScheduleChangeRequestsForDate(',
          '승인해야 할 일이 사라진다');
    });

    test('AR-4 주간 출근 기록', () {
      _expectPropagates(f,
          'Future<Map<String, List<AttendanceModel>>> getWeeklyAttendanceByBusiness(',
          '그 주에 아무도 출근하지 않은 것과 구분되지 않는다');
    });
  });

  group('[R8P7.2] 확정자 — 삼키는 변형을 쓰지 않는다', () {
    test('AR-5 날짜별 지원자 화면이 OrThrow 를 쓴다', () {
      final code = _codeOf(_read('lib/screens/business_admin/dialogs/day_applicants_dialog.dart'));
      expect(code.contains('getConfirmedWorkersByDateAndBusinessOrThrow('), isTrue,
          reason: '그날 누가 일하는지를 말하는 자리다');
    });

    test('AR-6 운영 뷰가 OrThrow 를 쓴다', () {
      final code = _codeOf(
          _read('lib/screens/business_admin/workforce_management/workforce_operational_view.dart'));
      expect(code.contains('getConfirmedWorkersByDateAndBusinessOrThrow('), isTrue,
          reason: '_loadError 를 갖고 있는데 서비스가 실패를 삼키면 그 상태가 발동하지 않는다');
    });

    test('AR-7 Home 은 계속 OrThrow 를 쓴다', () {
      final code = _codeOf(_read('lib/screens/business_admin/business_admin_home_screen.dart'));
      expect(code.contains('getConfirmedWorkersByDateAndBusinessOrThrow('), isTrue);
    });
  });

  group('[R8P7.2] 인덱스', () {
    final idx = _flat(_read('firestore.indexes.json'));

    test('AR-8 schedule_change_requests businessId+status+targetDate', () {
      expect(
        idx.contains('"fieldPath": "businessId", "order": "ASCENDING" }, '
            '{ "fieldPath": "status", "order": "ASCENDING" }, '
            '{ "fieldPath": "targetDate", "order": "ASCENDING"'),
        isTrue,
        reason: '이 인덱스가 없으면 날짜별 스케줄 변경 요청이 항상 INTERNAL 이다',
      );
    });

    test('AR-9 interim_settlement_requests workerId+createdAt', () {
      expect(
        idx.contains('"fieldPath": "workerId", "order": "ASCENDING" }, '
            '{ "fieldPath": "createdAt", "order": "DESCENDING"'),
        isTrue,
        reason: '이 인덱스가 없으면 내 중간정산 목록이 항상 INTERNAL 이다',
      );
    });

    test('AR-10 interim_settlement_requests businessId+workerId+createdAt', () {
      expect(
        idx.contains('"fieldPath": "businessId", "order": "ASCENDING" }, '
            '{ "fieldPath": "workerId", "order": "ASCENDING" }, '
            '{ "fieldPath": "createdAt", "order": "DESCENDING"'),
        isTrue,
      );
    });
  });
}
