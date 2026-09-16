// [BULK-OPERATIONS.1A] 두 관리자가 동시에 눌러도 자리는 하나다
//
// 이 파일은 코드 검토가 아니라 DEV 병렬 호출 실측을 고정한다.
// 트랜잭션 코드를 읽어서 PASS로 삼지 않는다 — 아래 숫자는 전부 실행 결과다.
//
//   같은 지원서 동시 확정 ×2   → 둘 다 200, 좌석 1, 확정 1회
//                                 (alreadyConfirmed early return이 알림 블록보다 앞)
//   마지막 한 자리 A/B 동시    → 한쪽 200, 한쪽 400 "정원이 초과되었습니다", 좌석 1
//   정원 10·기존 6·A4+B4 동시  → 성공 4건, 좌석 10, 성공 수와 좌석 정확히 일치
//   confirm vs reject 동시     → confirm 200 / reject 400
//                                 "확정된 지원서는 거절할 수 없습니다", 상태 하나
//   10명 fan-out               → 확정 알림 정확히 1인 1건, applicationId 일치,
//                                 누락 0 · 중복 0 · 오수신 0, deep link applicationDetail
//   재호출(타임아웃 재시도 등가) → 좌석 10 유지, 알림 1→1
//   부분 성공(정원 4 · 8 선택)  → 성공 4, slot·TO·DayApplicants 모두 4
//   Home                       → 승인대기 Δ-10, 계약 미발송 Δ+10 (확정 수와 동일)
//   worker parity              → 서버 status == 내 지원 status (성공·실패 양쪽)
//
// 여기서는 그 결과를 만들어 낸 구조적 근거만 고정한다.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _fnsPath = 'functions/src/index.ts';
const _myAppsPath = 'lib/screens/user/my_applications_screen.dart';

String _src(String p) {
  final f = File(p);
  if (!f.existsSync()) throw StateError('$p 를 찾지 못함');
  return f.readAsStringSync();
}

String _codeOf(String b) =>
    b.split('\n').where((l) => !l.trimLeft().startsWith('//')).join('\n');

String _flat(String b) => b.replaceAll(RegExp(r'\s+'), ' ');

String _callableOf(String source, String name) {
  final start = source.indexOf('export const $name = onCall(');
  if (start < 0) throw StateError('$name 을 찾지 못함');
  final next = source.indexOf('\nexport ', start + 10);
  return source.substring(start, next == -1 ? source.length : next);
}

void main() {
  final raw = _src(_fnsPath);
  final confirm = _codeOf(_callableOf(raw, 'callableConfirmApplication'));
  final flat = _flat(confirm);

  group('같은 건을 두 번 확정해도 부작용은 한 번', () {
    test('이미 확정된 건은 알림 블록 이전에 빠져나간다', () {
      final retAt = flat.indexOf('if (alreadyConfirmed) return');
      final notifAt = flat.indexOf('type: "applicationConfirmed"');
      expect(retAt > 0, true, reason: '멱등 early return이 없다');
      expect(notifAt > retAt, true,
          reason: '알림이 early return보다 앞이면 재호출마다 알림이 쌓인다');
    });

    test('좌석 증감은 트랜잭션 안에서 건당 1', () {
      expect(
        flat.contains('confirmedCount: admin.firestore.FieldValue.increment(1)'),
        true,
      );
    });
  });

  group('거절은 확정된 건을 되돌리지 않는다', () {
    test('reject writer가 확정 상태를 막는다', () {
      final rej = _codeOf(_callableOf(raw, 'callableRejectApplication'));
      expect(rej.contains('확정된 지원서는 거절할 수 없습니다'), true,
          reason: '동시 실행에서 두 mutation이 모두 성공하면 상태와 좌석이 갈라진다');
    });
  });

  group('정원 판정은 트랜잭션 안에서 fresh하다', () {
    test('정원 초과는 커밋 이전에 throw한다', () {
      final capAt = flat.indexOf('정원이 초과되었습니다');
      final incAt = flat.indexOf('confirmedCount: admin.firestore.FieldValue.increment(1)');
      expect(capAt > 0 && incAt > capAt, true,
          reason: '좌석을 올린 뒤 정원을 보면 경쟁에서 초과가 난다');
    });
  });

  group('확정 알림은 지원서 단위로 나간다', () {
    test('수신자와 대상이 한 건에 묶여 있다', () {
      final i = flat.indexOf('type: "applicationConfirmed"');
      expect(i > 0, true);
      final block = flat.substring(i - 300, i + 400);
      expect(block.contains('.doc(uid).collection("notifications")'), true,
          reason: '수신자가 그 지원서의 근로자여야 한다');
      expect(block.contains('applicationId'), true,
          reason: 'deep link가 어느 지원서인지 가리켜야 한다');
    });
  });

  group('겹침 자동취소는 근로자에게 이유로 설명된다', () {
    test('서버가 SCHEDULE_CONFLICT 사유를 남긴다', () {
      expect(_codeOf(raw).contains('cancelReason: "SCHEDULE_CONFLICT"'), true);
    });

    test('근로자 화면이 그 사유를 사람 말로 옮긴다', () {
      final my = _codeOf(_src(_myAppsPath));
      expect(my.contains("case 'SCHEDULE_CONFLICT':"), true);
      expect(my.contains('다른 업무가 확정되어 자동 취소되었어요'), true);
      // 자동취소는 근로자 귀책이 아니다 — 신뢰도 문구가 붙으면 안 된다.
      final i = my.indexOf("case 'SCHEDULE_CONFLICT':");
      final line = my.substring(i, i + 120);
      expect(RegExp('신뢰도|패널티|제재').hasMatch(line), false);
    });
  });
}
