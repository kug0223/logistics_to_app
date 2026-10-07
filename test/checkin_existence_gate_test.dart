// [R7-ATTENDANCE.2] 찍지도 않았는데 "이미 출근하셨습니다" 라고 말했다
//
// 출근 중복 가드는 `snap.exists` 하나로 판정했다. 그런데 근태 문서는 출근하지
// 않은 상태에서도 존재한다 — 노쇼(자동·관리자), 결근, 미퇴근, 관리자 초기화,
// 노쇼 취소 뒤. 그 근로자는 찍지 않았는데 찍었다는 말을 듣고, 무엇을 해야
// 하는지도 알 수 없었다.
//
// 막는 것 자체는 옳다. 노쇼가 확정되면 좌석이 반납되고 대체 채용이 열리며
// 신뢰도 기록이 생긴다 — self 출근 한 번으로 되돌릴 수 없다.
// 그래서 **차단 범위는 그대로 두고 이유만 나눈다.**
//
// 비어 있는 문서(초기화·노쇼취소 뒤)는 서버가 **구별할 수 없다** — 남는 필드가
// 같다. 그래서 둘에 다른 정책을 말하지 않는다. 구별이 필요해지면 그 writer 가
// 표식을 남기는 것이 먼저다.
//
// 고정하는 것
//   AE-1   가드가 resolver 를 쓴다 (문서 존재 하나로 판정하지 않는다)
//   AE-2   코드 5종이 모두 있고 서로 다르다
//   AE-3   판정 순서 — missed_checkout 은 checkIn 도 갖고 있다
//   AE-4   문구가 상태와 일치한다
//   AE-5   모든 차단에 다음 행동이 있다
//   AE-6   이미 출근만 already-exists, 나머지는 failed-precondition
//   AE-7   details.reason 으로 코드를 보낸다 (문구 파싱 금지)
//   AE-8   관리자 복구 경로는 이 resolver 를 쓰지 않는다
//   AE-9   checkIn 있는 문서를 NO_SHOW 로 만들지 않는 가드가 살아 있다
//   AE-10  앱이 서버 문구를 그대로 보여준다
//   AE-11  모든 경로가 차단이다 (null 로 빠져나가지 않는다)
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _src(String p) {
  final f = File(p);
  if (!f.existsSync()) throw StateError('소스를 찾지 못했다: $p');
  return f.readAsStringSync();
}

String _code(String s) => s
    .split('\n')
    .where((l) {
      final t = l.trimLeft();
      return !t.startsWith('//') && !t.startsWith('*') && !t.startsWith('/*');
    })
    .join('\n');

String _slice(String src, String start, String end) {
  final i = src.indexOf(start);
  if (i < 0) throw StateError('구간 시작을 찾지 못했다: $start');
  final j = src.indexOf(end, i + start.length);
  if (j <= i) throw StateError('구간 끝을 찾지 못했다: $end');
  return src.substring(i, j);
}

String _callable(String ts, String name) =>
    _slice(ts, 'export const $name = onCall(', '\nexport const ');

void main() {
  final cfRaw = _src('functions/src/index.ts');
  final cf = _code(cfRaw);
  final resolver = _code(_slice(cfRaw,
      'function srvResolveCheckInBlock(', '\n/**'));
  final checkIn = _code(_callable(cfRaw, 'callableCheckIn'));

  group('출근 가드 — 문서 존재와 출근은 다르다', () {
    test('AE-1 가드가 resolver 를 쓴다', () {
      expect(checkIn.contains('srvResolveCheckInBlock(snap.data()!)'), isTrue,
          reason: '문서 존재 하나로 판정하면 상태를 구별할 수 없다');
      // 옛 문구는 더 이상 없어야 한다 — 찍지 않은 사람에게 거짓말이었다.
      expect(cf.contains('오늘 이미 출근하셨습니다'), isFalse);
      expect(
          RegExp(r'function srvResolveCheckInBlock\(').allMatches(cf).length, 1,
          reason: '판정이 두 벌이 되면 한쪽만 고쳐진다');
    });

    test('AE-2 코드 5종이 모두 있고 서로 다르다', () {
      const codes = [
        'ALREADY_CHECKED_IN',
        'NO_SHOW_LOCKED',
        'ABSENT_LOCKED',
        'MISSED_CHECKOUT_LOCKED',
        'RECOVERY_REQUIRED',
      ];
      for (final c in codes) {
        expect(resolver.contains('code: "$c"'), isTrue, reason: '$c 누락');
      }
      expect(codes.toSet().length, codes.length);
    });

    test('AE-3 판정 순서 — 상태가 checkIn 보다 앞이다', () {
      // missed_checkout 은 checkIn 을 함께 갖는다. checkIn 을 먼저 보면
      //   미퇴근이 '이미 출근'으로 뭉개진다.
      final iMissed = resolver.indexOf('"missed_checkout"');
      final iNoShow = resolver.indexOf('"NO_SHOW"');
      final iAbsent = resolver.indexOf('"absent"');
      final iCheckIn = resolver.indexOf('data["checkIn"] != null');
      expect(iMissed, greaterThan(-1));
      expect(iMissed, lessThan(iCheckIn), reason: '미퇴근이 이미 출근으로 뭉개진다');
      expect(iNoShow, lessThan(iCheckIn));
      expect(iAbsent, lessThan(iCheckIn));
    });

    test('AE-4 문구가 상태와 일치한다', () {
      for (final pair in [
        ['NO_SHOW_LOCKED', '노쇼'],
        ['ABSENT_LOCKED', '결근'],
        ['MISSED_CHECKOUT_LOCKED', '미퇴근'],
        ['ALREADY_CHECKED_IN', '이미 출근'],
        ['RECOVERY_REQUIRED', '초기화'],
      ]) {
        final i = resolver.indexOf('code: "${pair[0]}"');
        expect(i, greaterThan(-1), reason: '${pair[0]} 없음');
        // 코드 바로 뒤의 message 가 그 상태를 말해야 한다.
        final after = resolver.substring(i, resolver.indexOf('}', i) + 1);
        expect(after.contains(pair[1]), isTrue,
            reason: '${pair[0]} 문구에 "${pair[1]}" 가 없다');
      }
    });

    test('AE-5 막기만 하지 않고 다음 행동을 말한다', () {
      // 이미 출근은 안내가 필요 없다 — 나머지는 전부 요청 경로를 말해야 한다.
      for (final c in [
        'NO_SHOW_LOCKED', 'ABSENT_LOCKED',
        'MISSED_CHECKOUT_LOCKED', 'RECOVERY_REQUIRED',
      ]) {
        final i = resolver.indexOf('code: "$c"');
        final after = resolver.substring(i, resolver.indexOf('};', i));
        expect(after.contains('관리자'), isTrue,
            reason: '$c 에 다음 행동이 없다 — 막기만 하면 사용자가 멈춘다');
      }
    });

    test('AE-6 이미 출근만 already-exists 다', () {
      expect(
          checkIn.contains('block.code === "ALREADY_CHECKED_IN" ?'), isTrue,
          reason: '모든 상태를 already-exists 하나로 숨기지 않는다');
      expect(checkIn.contains('"failed-precondition"'), isTrue);
    });

    test('AE-7 details.reason 으로 코드를 보낸다', () {
      expect(checkIn.contains('{reason: block.code}'), isTrue,
          reason: '화면이 한국어 문구를 파싱해 상태를 역추론하지 않게 한다');
    });

    test('AE-8 관리자 복구 경로는 이 resolver 를 쓰지 않는다', () {
      for (final name in [
        'callableBatchCheckIn',
        'callableBatchAdjustAttendanceTime',
        'callableBatchResetAttendance',
        'callableBatchCancelNoShow',
      ]) {
        expect(_code(_callable(cfRaw, name))
            .contains('srvResolveCheckInBlock('), isFalse,
            reason: '$name 에 self 가드가 걸리면 복구가 막힌다');
      }
    });

    test('AE-9 checkIn 있는 문서를 NO_SHOW 로 만들지 않는다', () {
      // 이 가드가 없으면 status=NO_SHOW + checkIn 공존 문서가 생겨
      //   resolver 의 순서 판정이 거짓이 된다.
      final ns = _code(_callable(cfRaw, 'callableBatchSetNoShow'));
      // 문장 형태까지 고정한다 — `if (false && ...)` 로 조건을 살려 둔 채 끄면
      //   부분문자열 고정은 통과한다(실제로 그 변형이 빠져나갔다).
      expect(ns.contains('if (snap.exists && snap.data()!.checkIn != null) {'),
          isTrue);
      expect(ns.contains('if (false'), isFalse,
          reason: '조건을 남겨 둔 채 끄는 변형');
    });

    test('AE-10 앱이 서버 문구를 그대로 보여준다', () {
      final svc = _code(_src('lib/services/firestore/attendance_firestore.dart'));
      expect(svc.contains("throw Exception(e.message ?? '출근 처리 중 오류가 발생했습니다.')"),
          isTrue, reason: '서버 문구를 버리면 상태별 안내가 사용자에게 닿지 않는다');
      final screen = _code(_src('lib/screens/user/attendance_check_screen.dart'));
      expect(screen.contains("e.toString().replaceAll('Exception: ', '')"),
          isTrue);
    });

    test('AE-11 모든 경로가 차단이다', () {
      // 문서가 있는데 통과시키는 경로가 생기면 노쇼 뒤 재출근이 열린다.
      expect(resolver.contains('return null'), isFalse,
          reason: 'null 로 빠져나가면 좌석·대체채용 truth 가 깨진다');
      expect(resolver.contains('{code: string; message: string}'), isTrue,
          reason: '반환형이 nullable 이 되면 호출부가 통과를 허용한다');
    });
  });
}
