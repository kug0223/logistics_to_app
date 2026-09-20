// [R6.0A] 근로자 punch 는 확정된 근무 약속의 시작을 앞당기는 권한이 아니다.
//
//   실측(DEV): 18:00~21:00 근무에 근로자가 15:49:13 에 self check-in 하자
//   조출 반올림이 16:00 을 만들었고 그 시각부터 유급 근로가 시작됐다.
//   날짜 게이트는 있었지만 시각 게이트가 없었다.
//
//   이 파일은 서버 소스 계약을 고정한다 — 인가가 반올림보다 먼저 오고,
//   인가의 기준은 약속 snapshot 이며, 관리자 경로는 별개라는 것.
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

String _src() => File('functions/src/index.ts').readAsStringSync();

/// 주석으로 시작하는 줄만 제거한다 (JSDoc 은 남는다).
String _codeOf(String raw) => raw
    .split('\n')
    .where((l) => !l.trimLeft().startsWith('//'))
    .join('\n');

String _flat(String s) => s.replaceAll(RegExp(r'\s+'), ' ');

/// 테스트 바깥(그룹 수집 시점)에서도 불리므로 expect 대신 예외로 실패시킨다.
String _sliceOf(String raw, String from, String to) {
  final i = raw.indexOf(from);
  if (i < 0) throw StateError('시작 표지를 찾지 못함: $from');
  final j = raw.indexOf(to, i + from.length);
  if (j < 0) throw StateError('끝 표지를 찾지 못함: $to');
  return raw.substring(i, j);
}

void main() {
  final raw = _src();
  final checkIn = _sliceOf(raw, 'export const callableCheckIn = onCall(',
      'export const callableCheckOut = onCall(');
  final code = _codeOf(checkIn);
  final flat = _flat(code);

  group('TA-1 — 근로자 self check-in 에 시각 게이트가 있다', () {
    test('TA-10 약속 시작 - earlyWindow 이전이면 거절한다', () {
      expect(flat, contains('const admitFromMs = committedStartMs -'));
      expect(flat, contains('admitRules.earlyWindow'));
      expect(flat, contains('if (Date.now() < admitFromMs)'));
    });

    test('TA-11 거절은 domain rejection 이다 — INTERNAL/UNKNOWN 아님', () {
      final gate = _sliceOf(code, 'const admitFromMs', '}\n    }');
      expect(gate, contains('"failed-precondition"'));
      expect(gate, isNot(contains('"internal"')));
      expect(gate, isNot(contains('"unknown"')));
    });

    test('TA-12 거절 메시지가 출근 가능 시각을 말한다', () {
      expect(flat, contains('아직 출근할 수 있는 시간이 아닙니다'));
      expect(flat, contains('srvKstHhmm(admitFromMs)'));
    });

    test('TA-13 날짜 게이트는 그대로 남아 있다', () {
      expect(flat, contains('미래 날짜로 출근 기록을 생성할 수 없습니다'));
      expect(flat, contains('7일 이전 날짜로 출근 기록을 생성할 수 없습니다'));
      expect(flat, contains('지원서에 지정된 날짜에만 출근할 수 있습니다'));
    });
  });

  group('TA-2 — authorization 이 rounding 보다 먼저다', () {
    test('TA-20 게이트가 _processCheckin 호출보다 앞에 있다', () {
      final gateAt = code.indexOf('if (Date.now() < admitFromMs)');
      final roundAt = code.indexOf('_processCheckin(now, cStart');
      expect(gateAt, greaterThan(-1));
      expect(roundAt, greaterThan(-1));
      expect(gateAt, lessThan(roundAt),
          reason: '반올림이 만든 시각으로 허용 여부를 정하면 안 된다');
    });

    test('TA-21 게이트가 트랜잭션 바깥에 있다 — 거절 시 mutation 0', () {
      final gateAt = code.indexOf('if (Date.now() < admitFromMs)');
      final txAt = code.indexOf('await db.runTransaction');
      expect(gateAt, lessThan(txAt));
    });

    test('TA-22 게이트는 반올림된 값이 아니라 raw 현재시각으로 판단한다', () {
      final gate = _sliceOf(code, 'const admitRules', 'if (Date.now() < admitFromMs)');
      expect(gate, isNot(contains('_processCheckin')));
      expect(gate, isNot(contains('effectiveCheckIn')));
    });
  });

  group('TA-3 — 약속 시각의 권위', () {
    final resolver = _sliceOf(raw, 'async function srvCommittedStartTime(',
        'function srvKstHhmm(');
    final rCode = _codeOf(resolver);

    test('TA-30 Application snapshot 이 1순위다', () {
      expect(_flat(rCode), contains('appData["startTime"]'));
    });

    test('TA-31 Contract snapshot 이 2순위다', () {
      expect(_flat(rCode), contains('employment_contracts'));
      expect(_flat(rCode), contains('"applicationId", "=="'));
      expect(_flat(rCode), contains('"startTime"'));
    });

    test('TA-32 공고(TO/slot) 현재값은 읽지 않는다 — 확정 후 공고 수정이 약속을 바꾸지 못한다', () {
      expect(rCode, isNot(contains('collection("tos")')));
      expect(rCode, isNot(contains('"slots"')));
      expect(rCode, isNot(contains('workDetails')));
    });

    test('TA-33 둘 다 없으면 UNKNOWN 이고, 열어주지 않는다', () {
      expect(_flat(rCode), contains('"failed-precondition"'));
      expect(_flat(rCode), contains('시작 시간이 확인되지 않아'));
    });

    test('TA-34 클라이언트가 보낸 scheduledStartTime 은 인가 기준이 아니다', () {
      // serverStartTime 은 이제 resolver 결과만으로 정해진다.
      expect(flat, contains('const serverStartTime = await srvCommittedStartTime('));
      expect(flat,
          isNot(contains('const serverStartTime = (appData.startTime as string | undefined) || scheduledStartTime')));
    });
  });

  group('TA-4 — 관리자 경로는 기계적으로 통일하지 않는다', () {
    final batchIn = _sliceOf(raw, 'export const callableBatchCheckIn = onCall(',
        'return {success: true');

    test('TA-40 관리자 batch check-in 에는 이 게이트를 넣지 않았다', () {
      expect(_codeOf(batchIn), isNot(contains('admitFromMs')));
      expect(_codeOf(batchIn), isNot(contains('srvCommittedStartTime')));
    });

    test('TA-41 관리자 보정 경로가 실재한다 — 조기근무는 그쪽에서 기록한다', () {
      expect(raw, contains('export const callableBatchAdjustAttendanceTime = onCall('));
      expect(raw, contains('export const callableBatchCheckIn = onCall('));
    });
  });

  group('TA-5 — 이번 수정이 기존 정책을 건드리지 않았다', () {
    final proc = _sliceOf(raw, 'function _processCheckin(', 'function _processCheckout(');

    test('TA-50 지각 판정(lateGrace)은 그대로다', () {
      expect(_flat(_codeOf(proc)), contains('isLate: offsetMinutes > lateGrace'));
    });

    test('TA-51 조출/정시/지각 3분기 구조가 그대로다', () {
      final f = _flat(_codeOf(proc));
      expect(f, contains('if (offsetMinutes < -earlyWindow)'));
      expect(f, contains('} else if (offsetMinutes <= lateGrace) {'));
      expect(f, contains('roundedOffset = Math.ceil(offsetMinutes / lateUnit) * lateUnit'));
    });

    test('TA-52 조퇴는 실제 근무 상태로 남는다 — scheduled end 이전이라고 막지 않는다', () {
      final out = _sliceOf(raw, 'export const callableCheckOut = onCall(',
          'export const callableCreateContractRenewal');
      expect(_flat(_codeOf(out)), contains('status = "early_leave"'));
    });

    test('TA-53 원본 punch 는 반올림으로 덮이지 않는다', () {
      expect(flat, contains('originalCheckIn: admin.firestore.Timestamp.fromDate(now)'));
      final out = _sliceOf(raw, 'export const callableCheckOut = onCall(',
          'export const callableCreateContractRenewal');
      expect(_flat(_codeOf(out)), contains('if (data.originalCheckOut == null)'));
    });
  });
}
