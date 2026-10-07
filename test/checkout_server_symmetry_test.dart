// [R7-ATTENDANCE.1] 출근과 퇴근이 서로 다른 규칙을 갖고 있었다
//
// 같은 self-attendance 인데 들어올 때와 나갈 때가 달랐다.
//
//   출근: 좌표 필수 · 서버 Haversine · gpsRadius · attendanceType 바인딩 ·
//         method 화이트리스트 · manual 차단
//   퇴근: 좌표 선택 · 반경 검증 없음 · 바인딩 없음 · 미구현 `qr` 기록 가능 ·
//         알 수 없는 방식은 조용히 `gps`
//
// 앱은 양쪽을 다 막고 있었지만, 클라이언트에만 있는 조건은 boundary 가 아니다 —
// 출근 검증을 서버로 옮긴 이유가 바로 그것이었다.
//
// 그래서 판정을 **한 함수**로 모으고 양쪽이 부른다. 정책을 두 벌로 복사하면
// 한쪽만 고쳐지는 날이 온다.
//
// 고정하는 것
//   CS-1   공용 helper 가 하나이고 출근·퇴근이 **그것을** 부른다
//   CS-2   좌표 필수 (null 거절)
//   CS-3   서버 Haversine + 반경 비교
//   CS-4   attendanceType ↔ method 바인딩
//   CS-5   method 화이트리스트 — unknown → gps 추정 없음
//   CS-6   manual 사업장 self 거절
//   CS-7   퇴근은 **서버가 계산한** 거리를 저장한다
//   CS-8   퇴근 입력에 거리 파라미터가 없다 (클라이언트 값을 받을 수 없다)
//   CS-9   관리자 보정 경로는 이 게이트를 쓰지 않는다
//   CS-10  기본 반경이 한 곳에만 있다
//   CS-11  앱이 출근·퇴근에 같은 방식 값을 보낸다
//   CS-12  퇴근이 미구현 `qr` 을 기록하지 않는다
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _src(String p) {
  final f = File(p);
  if (!f.existsSync()) throw StateError('소스를 찾지 못했다: $p');
  return f.readAsStringSync();
}

/// 주석 줄을 지운 소스 — 설명문이 검사에 걸리지 않게 한다.
String _code(String s) => s
    .split('\n')
    .where((l) {
      final t = l.trimLeft();
      return !t.startsWith('//') && !t.startsWith('*') && !t.startsWith('/*');
    })
    .join('\n');

/// 구간 잘라내기. `main()` 본문에서도 쓰므로 `expect` 가 아니라 throw 한다
/// (테스트 밖 `expect` 는 OutsideTestException 이 된다).
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
  // 공용 helper 본문 — 다음 top-level 선언 앞에서 끊는다.
  final helper = _code(_slice(
      cfRaw, 'function srvAssertSelfAttendanceLocation(', '\n// ─── callableCheckIn'));
  final checkIn = _code(_callable(cfRaw, 'callableCheckIn'));
  final checkOut = _code(_callable(cfRaw, 'callableCheckOut'));

  group('self 출퇴근 위치·방식 — 한 벌', () {
    test('CS-1 출근·퇴근이 같은 helper 를 부른다', () {
      // 정의는 하나뿐이어야 한다.
      expect(
          RegExp(r'function srvAssertSelfAttendanceLocation\(')
              .allMatches(cf)
              .length,
          1,
          reason: '정책이 두 벌이 되면 한쪽만 고쳐진다');
      expect(checkIn.contains('srvAssertSelfAttendanceLocation('), isTrue,
          reason: '출근이 공용 게이트를 불러야 한다');
      expect(checkOut.contains('srvAssertSelfAttendanceLocation('), isTrue,
          reason: '퇴근이 공용 게이트를 불러야 한다');
      // 라벨로 문구만 갈린다.
      expect(checkIn.contains('"출근")'), isTrue);
      expect(checkOut.contains('"퇴근")'), isTrue);
    });

    test('CS-0 게이트를 비활성화한 분기가 없다', () {
      // `if (false && ...)` 처럼 조건을 살려 둔 채 무력화하면 문구 고정만으로는
      //   잡히지 않는다. 그 모양 자체를 막는다.
      expect(helper.contains('if (false'), isFalse,
          reason: '조건을 남겨 둔 채 끄는 변형');
      expect(helper.contains('|| true'), isFalse);
      expect(helper.contains('return {distanceMeters: 0'), isFalse,
          reason: '거리를 0 으로 고정하면 반경 비교가 무의미하다');
    });

    test('CS-2 좌표가 없으면 거절한다', () {
      expect(helper.contains('if (latitude == null || longitude == null) {'), isTrue);
      expect(helper.contains('위치 정보(GPS)가 필요합니다'), isTrue);
    });

    test('CS-3 서버 Haversine 과 반경 비교가 있다', () {
      expect(helper.contains('haversineDistanceMeters('), isTrue,
          reason: '거리는 서버가 계산한다');
      expect(helper.contains('if (distM > bizGpsRadius) {'), isTrue,
          reason: '반경 비교가 없으면 게이트가 아니다');
      expect(helper.contains('사업장 반경을 벗어났습니다'), isTrue);
    });

    test('CS-4 attendanceType ↔ method 바인딩', () {
      for (final pair in [
        ['if (serverAttendanceType === "gps" && method !== "gps") {', 'GPS'],
        ['if (serverAttendanceType === "beacon" && method !== "beacon") {', '비콘'],
      ]) {
        expect(helper.contains(pair[0]), isTrue, reason: '${pair[1]} 바인딩이 없다');
      }
      expect(helper.contains('KNOWN_ATTENDANCE_TYPES'), isTrue,
          reason: '알 수 없는 attendanceType 은 fail-closed 여야 한다');
    });

    test('CS-5 method 화이트리스트 — 추정하지 않는다', () {
      expect(helper.contains('ALLOWED_SELF_ATTENDANCE_METHODS'), isTrue);
      expect(helper.contains('["gps", "beacon"]'), isTrue);
      expect(helper.contains('유효하지 않은'), isTrue);
      // 알 수 없는 **method** 를 gps 로 떨어뜨리는 폴백이 없어야 한다.
      //   (`attendanceType ?? "gps"` 는 사업장 기본값이고 별개다.)
      expect(helper.contains('method ?? "gps"'), isFalse,
          reason: 'method 를 gps 로 추정하면 화이트리스트가 무의미하다');
      expect(helper.contains('method === "qr"'), isFalse,
          reason: '구현 없는 방식을 받아들이지 않는다');
      // 화이트리스트 검사가 바인딩보다 **앞**에 있어야 한다 —
      //   알 수 없는 값이 바인딩 분기를 먼저 통과하면 안 된다.
      expect(helper.indexOf('ALLOWED_SELF_ATTENDANCE_METHODS.includes'),
          lessThan(helper.indexOf('serverAttendanceType === "gps"')));
    });

    test('CS-6 manual 사업장은 self 처리를 거절한다', () {
      expect(helper.contains('if (serverAttendanceType === "manual") {'), isTrue);
      expect(helper.contains('관리자가 ${'\$'}{label}을 직접 처리합니다'), isTrue);
    });

    test('CS-7 퇴근은 서버가 계산한 거리를 저장한다', () {
      expect(checkOut.contains('update.checkOutDistance = checkOutLoc.distanceMeters'),
          isTrue,
          reason: '출근에는 checkInDistance 가 있는데 퇴근에 없으면 사후 감사가 안 된다');
      expect(checkOut.contains('update.checkOutLat = latitude'), isTrue);
      expect(checkOut.contains('update.checkOutLng = longitude'), isTrue);
    });

    test('CS-8 퇴근 입력에 거리 파라미터가 없다', () {
      // 클라이언트가 거리를 보낼 수 있으면 그 값을 믿게 되는 날이 온다.
      final destructure = _slice(checkOut, 'const {', '} = request.data');
      expect(destructure.contains('distance'), isFalse,
          reason: '거리는 입력이 아니라 서버 계산 결과다');
    });

    test('CS-9 관리자 보정 경로는 이 게이트를 쓰지 않는다', () {
      // 관리자가 현장 반경 안에 있어야 할 이유가 없다.
      for (final name in [
        'callableBatchAdjustAttendanceTime',
        'callableBatchCheckOut',
        'callableBatchCheckIn',
      ]) {
        final body = _code(_callable(cfRaw, name));
        expect(body.contains('srvAssertSelfAttendanceLocation('), isFalse,
            reason: '$name 에 self 게이트가 걸리면 관리자 복구가 막힌다');
      }
    });

    test('CS-10 기본 반경은 한 곳에서만 정한다', () {
      expect(
          RegExp(r'rawRadius === "number" && rawRadius > 0 \? rawRadius : 100')
              .allMatches(cf)
              .length,
          1,
          reason: '출근·퇴근이 서로 다른 기본 반경을 쓰면 안 된다');
      expect(helper.contains('rawRadius'), isTrue);
    });

    test('CS-11 앱이 출근·퇴근에 같은 방식 값을 보낸다', () {
      final screen = _code(_src('lib/screens/user/attendance_check_screen.dart'));
      // 두 경로 모두 사업장 설정에서 출발한다.
      expect(RegExp(r'String usedMethod = type;').allMatches(screen).length, 2,
          reason: '한쪽만 사업장 설정을 쓰면 서버 바인딩에서 갈린다');
      expect(screen.contains("usedMethod = 'beacon'"), isTrue);
    });

    test('CS-12 퇴근이 미구현 qr 을 기록하지 않는다', () {
      expect(checkOut.contains('checkOutMethod: checkOutLoc.method'), isTrue);
      expect(checkOut.contains('"qr"'), isFalse,
          reason: '구현이 없는 방식이 기록에 남으면 안 된다');
    });
  });
}
