// [CROSS-DOMAIN-R5.3E.1] 실근무 개시 경계 — 서버 권위
//
// 이 파일이 고정하는 것:
//
//   1. "이미 근무했는가"의 정의는 **한 곳**에만 있다.
//      화면(loadHasWorkedMap)이 그 판정을 갖고 확정취소 버튼을 숨기지만,
//      숨기는 것은 authority가 아니다. 같은 callable을 직접 부르면 통했다.
//
//   2. 판정 순서가 정해져 있다: 비근무 terminal(absent/NO_SHOW)이 먼저다.
//      NO_SHOW는 wageStatus를 "confirmed"로 쓰므로, 순서를 뒤집으면 모든
//      NO_SHOW가 "근무함"이 되어 R5.1 대체충원 경로가 통째로 막힌다.
//
//   3. attendance row의 **존재**는 판정 근거가 아니다.
//      row는 근무하지 않았다는 기록으로도 만들어진다.
//
//   4. 차단은 transaction 안에서 다시 확인된다. TX 밖 pre-check만으로는
//      cancel ‖ check-in이 둘 다 성공할 수 있다.
//
//   5. 확정을 되돌리는 writer 전부가 같은 경계를 쓴다 —
//      확정취소 · 리컨펌 거절 · 좌석 반납 · 계약 무효화.
//      계약 권한이 근태 사실을 뒤집는 경로를 남기지 않는다.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _src(String p) {
  final f = File(p);
  if (!f.existsSync()) throw StateError('$p 를 찾지 못함');
  return f.readAsStringSync();
}

String _codeOf(String b) =>
    b.split('\n').where((l) => !l.trimLeft().startsWith('//')).join('\n');

String _flat(String b) => b.replaceAll(RegExp(r'\s+'), ' ');

String _callableBody(String raw, String name) {
  final start = raw.indexOf('export const $name = onCall(');
  if (start < 0) throw StateError('$name 을 찾지 못함');
  final end = raw.indexOf('\n);', start);
  if (end < 0) throw StateError('$name 본문 끝을 찾지 못함');
  return raw.substring(start, end);
}

String _fnBody(String raw, String signature) {
  final start = raw.indexOf(signature);
  if (start < 0) throw StateError('$signature 를 찾지 못함');
  var depth = 0;
  var seen = false;
  for (var i = start; i < raw.length; i++) {
    final c = raw[i];
    if (c == '{') {
      depth++;
      seen = true;
    } else if (c == '}') {
      depth--;
      if (seen && depth == 0) return raw.substring(start, i + 1);
    }
  }
  throw StateError('$signature 본문 끝을 찾지 못함');
}

const _cf = 'functions/src/index.ts';
const _attFs = 'lib/services/firestore/attendance_firestore.dart';

void main() {
  final rawCf = _codeOf(_src(_cf));
  final cf = _flat(rawCf);
  final reasonOf =
      _flat(_fnBody(rawCf, 'function srvActualWorkReasonOf('));
  final refsOf =
      _flat(_fnBody(rawCf, 'async function srvActualWorkAttendanceRefs('));
  final assertInTx =
      _flat(_fnBody(rawCf, 'async function srvAssertNoActualWorkInTx('));
  final cancel =
      _flat(_callableBody(rawCf, 'callableCancelConfirmedApplication'));
  final reconfirm = _flat(_callableBody(rawCf, 'callableRespondToReconfirm'));
  final release = _flat(_callableBody(rawCf, 'callableReleaseNoshowSeat'));
  final checkIn = _flat(_callableBody(rawCf, 'callableCheckIn'));
  final batchCheckIn = _flat(_callableBody(rawCf, 'callableBatchCheckIn'));
  final voidLifecycle =
      _flat(_fnBody(rawCf, 'async function voidContractAtomicLifecycle('));

  group('R5.3E.1 — 경계의 정의는 한 곳에', () {
    test('canonical helper가 존재한다', () {
      expect(cf, contains('function srvActualWorkReasonOf('));
      expect(cf, contains('async function srvHasActualWorkStarted('));
      expect(cf, contains('async function srvAssertNoActualWorkInTx('));
    });

    test('비근무 terminal 상태와 정산 개시 상태가 상수로 고정돼 있다', () {
      expect(cf, contains('const ATTENDANCE_NON_WORK_STATUSES = ["absent", "NO_SHOW"]'));
      expect(
        cf,
        contains('const WAGE_SETTLEMENT_STARTED_STATUSES = '
            '["calculated", "confirmed", "transferred"]'),
      );
    });

    test('차단 문구도 한 곳에서만 만들어진다', () {
      expect(cf, contains('const ACTUAL_WORK_BLOCK_MESSAGE ='));
    });
  });

  group('R5.3E.1 — 판정 순서', () {
    test('absent/NO_SHOW를 checkIn·wageStatus보다 먼저 본다', () {
      final iNonWork = reasonOf.indexOf('ATTENDANCE_NON_WORK_STATUSES');
      final iCheckIn = reasonOf.indexOf('"checkIn"');
      final iWage = reasonOf.indexOf('WAGE_SETTLEMENT_STARTED_STATUSES');
      expect(iNonWork, greaterThanOrEqualTo(0));
      expect(iCheckIn, greaterThan(iNonWork),
          reason: 'NO_SHOW보다 checkIn을 먼저 보면 NO_SHOW 대체충원이 막힌다');
      expect(iWage, greaterThan(iNonWork),
          reason: 'NO_SHOW는 wageStatus를 confirmed로 쓴다 — 순서가 뒤집히면 전부 "근무함"이 된다');
    });

    test('비근무 terminal은 즉시 null을 돌려준다', () {
      expect(
        reasonOf,
        contains('if (ATTENDANCE_NON_WORK_STATUSES.includes(st)) return null;'),
      );
    });

    test('checkIn 존재와 정산 개시가 각각 사유를 갖는다', () {
      expect(reasonOf, contains('return "CHECKED_IN"'));
      expect(reasonOf, contains('return "WAGE_SETTLED"'));
    });

    test('row 존재만으로 판정하지 않는다 — exists 하나로 true를 내지 않는다', () {
      expect(reasonOf.contains('return true'), isFalse);
    });
  });

  group('R5.3E.1 — race에서 읽을 문서를 결정적으로 모은다', () {
    test('근무일과 오늘의 결정적 docId를 포함한다', () {
      expect(refsOf, contains(r'${applicationId}_${kstDateStr('));
      expect(refsOf, contains('Date.now()'));
    });

    test('기존 row도 함께 모은다 (legacy/수동 생성 대비)', () {
      expect(refsOf, contains('.where("applicationId", "==", applicationId)'));
    });

    test('TX 재확인은 tx.get으로 읽는다 — 쿼리가 아니다', () {
      expect(assertInTx, contains('tx.get(r)'));
      expect(assertInTx, contains('srvActualWorkReasonOf'));
      expect(assertInTx, contains('throw new HttpsError("failed-precondition"'));
    });
  });

  group('R5.3E.1 — 확정을 되돌리는 writer 전부가 같은 경계를 쓴다', () {
    test('확정취소 — pre-check + TX 내 재확인', () {
      expect(cancel, contains('srvHasActualWorkStarted('));
      expect(cancel, contains('srvAssertNoActualWorkInTx('));
      expect(cancel, contains('ACTUAL_WORK_BLOCK_MESSAGE'));
    });

    test('리컨펌 거절 — 확정취소와 같은 경계', () {
      expect(reconfirm, contains('srvHasActualWorkStarted('));
      expect(reconfirm, contains('srvAssertNoActualWorkInTx('));
    });

    test('좌석 반납 — 실근무자의 자리를 반납하지 않는다', () {
      expect(release, contains('srvHasActualWorkStarted('));
      expect(release, contains('srvAssertNoActualWorkInTx('));
    });

    test('계약 무효화 — 계약 권한이 근태 사실을 뒤집지 못한다', () {
      expect(voidLifecycle, contains('srvHasActualWorkStarted('));
      expect(voidLifecycle, contains('srvAssertNoActualWorkInTx('));
    });

    test('completed 계약은 여전히 무효화 불가 (기존 계약 유지)', () {
      expect(
        voidLifecycle,
        contains('if (contractStatus === "completed")'),
      );
    });
  });

  group('R5.3E.1 — check-in 쪽 승자 규칙', () {
    test('callableCheckIn이 TX 안에서 Application 상태를 다시 읽는다', () {
      expect(checkIn, contains('tx.get(checkInAppRef)'));
      expect(
        checkIn,
        contains('if (!confirmedStatuses.includes(freshAppStatus))'),
        reason: 'TX 밖 pre-read만으로는 확정취소와 둘 다 성공할 수 있다',
      );
    });

    test('관리자 일괄 출근도 확정 상태를 본다', () {
      expect(batchCheckIn, contains('CONFIRMED_STATUSES.includes(batchCiStatus)'));
    });
  });

  group('R5.3E.1 — 화면 사본은 그대로 두되 권위가 아니다', () {
    test('loadHasWorkedMap은 여전히 UI 가드로 남아 있다', () {
      final att = _flat(_codeOf(_src(_attFs)));
      expect(att, contains('loadHasWorkedMap'));
      expect(att, contains('statusNoShow'));
    });
  });
}
