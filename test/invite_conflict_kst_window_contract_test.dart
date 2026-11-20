// [CROSS-DOMAIN-R5.1G.2] 초대 사전 충돌검사의 날짜 창
//
// R5.1G.2의 초대 dedupe 측정 중에 드러난 결함이다.
//
//   workDate는 **KST 자정** 타임스탬프로 저장된다(2026-09-18 → 09-17T15:00Z).
//   그런데 초대의 충돌 사전검사는 `new Date("2026-09-18")`(= UTC 자정)부터
//   24시간을 창으로 잡고 있었다. 그 창은 같은 KST 날짜의 확정 근무를
//   통째로 건너뛴다.
//
//   실측: 09-18 13:00~19:00 확정을 가진 근로자에게 09-18 09:00~18:00 초대가
//   **HTTP 200으로 생성됐고**(Application·알림·대기 1건), 수락 단계에서야
//   "이미 확정된 근무가 있어 수락할 수 없습니다"로 거부됐다.
//   이중예약은 일어나지 않지만(수락 경로가 최종 권한), 받을 수 없는 초대와
//   알림이 남고 관리자 화면의 대기 1건이 영영 풀리지 않는다.
//
//   수락 경로는 KST 달력일로 비교해 제대로 막고 있었다. 두 자리가 같은
//   규칙을 쓰게 맞췄다 — 창은 ±1일로 넉넉히 잡고 날짜는 KST로 비교한다.
//   수정 후 실측: 같은 초대가 HTTP 400 "동일 시간대에 이미 확정된 일정이
//   있습니다"로 막히고, Application·카운터를 남기지 않는다.

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

const _cf = 'functions/src/index.ts';

void main() {
  final raw = _codeOf(_src(_cf));
  final cf = _flat(raw);

  group('초대 충돌검사는 KST 달력일로 본다', () {
    test('UTC 자정 24시간 창을 더 이상 쓰지 않는다', () {
      expect(
          cf.contains('const invWdObjNext = '
              'new Date(invWdObj.getTime() + 24 * 60 * 60 * 1000);'),
          false,
          reason: '그 창은 같은 KST 날짜의 확정 근무를 건너뛴다');
    });

    test('창을 ±1일로 넉넉히 잡는다', () {
      expect(
          cf.contains('const invQryFrom = '
              'new Date(invWdObj.getTime() - 24 * 60 * 60 * 1000); '
              'const invQryTo = new Date(invWdObj.getTime() + 24 * 60 * 60 * 1000);'),
          true);
      expect(
          cf.contains('.where("workDate", ">=", '
              'admin.firestore.Timestamp.fromDate(invQryFrom))'),
          true);
    });

    test('넓힌 창에서 같은 KST 날짜만 골라낸다', () {
      expect(cf.contains('const cKst = new Date(cWdTs.toMillis() + KST_OFF);'), true);
      expect(cf.contains('if (cKey !== invDateKey) continue;'), true,
          reason: '창을 넓힌 채 그대로 두면 다른 날 근무까지 충돌로 본다');
    });

    test('날짜 라벨을 가용일 검사와 같은 식으로 만든다', () {
      // 같은 함수 안에서 두 검사가 서로 다른 날짜 라벨을 쓰면 또 갈라진다.
      expect(
          cf.contains('const invKstDate = '
              'new Date(new Date(workDate).getTime() + 9 * 3600 * 1000); '
              'const invDateKey = `\${invKstDate.getUTCFullYear()}-` + '
              '`\${String(invKstDate.getUTCMonth() + 1).padStart(2, "0")}-` + '
              '`\${String(invKstDate.getUTCDate()).padStart(2, "0")}`;'),
          true);
      expect('invDateKey'.allMatches(cf).length, greaterThanOrEqualTo(3),
          reason: '정의 1 + 가용일 검사 1 + 충돌 검사 1');
    });

    test('수락 경로의 판정 규칙은 그대로다 — 최종 권한', () {
      expect(cf.contains('const cKst = new Date(cWorkDateTs.toMillis() + KST_OFF);'), true);
      expect(
          cf.contains('if (txKst.getUTCFullYear() !== cKst.getUTCFullYear() || '
              'txKst.getUTCMonth() !== cKst.getUTCMonth() || '
              'txKst.getUTCDate() !== cKst.getUTCDate()) continue;'),
          true,
          reason: '초대는 사전 안내이고, 수락이 여전히 최종 검증이다');
    });

    test('두 자리가 같은 겹침 판정 함수를 쓴다', () {
      expect(cf.contains('_hasTimeOverlap(startTime, endTime, cStart, cEnd)'), true);
      expect(cf.contains('_hasTimeOverlap(txFreshStart, txFreshEnd, cStart, cEnd)'), true);
    });
  });

  group('초대 자연키와 중복 가드는 그대로다', () {
    test('Application id가 자연키다', () {
      expect(
          cf.contains('const inviteComplexId = slotId ? '
              '`\${toId}_\${slotId}_\${inviteDiscriminator}_\${targetUid}` : '
              '`\${toId}_\${inviteDiscriminator}_\${targetUid}`;'),
          true);
    });

    test('트랜잭션 안에서 같은 문서를 다시 본다', () {
      // [R7-P4.4E.11C.0C.0b] 계정 freeze fence 가 TX 의 첫 read 다. 중복 가드는 그 뒤에 그대로 있다.
      // [INVITE-TERMINAL] freeze fence 뒤에 공고·슬롯 재검증(종료·단위 정원)이 들어왔다.
      //   fence 가 첫 read 이고 같은 문서 재확인이 쓰기 전에 있다는 계약은 그대로다.
      // [POSTING-AUTH-46] 계약은 "fence 가 **첫** read" 라는 위치가 아니라 다음 셋이다:
      //   ① 계정 freeze fence 가 트랜잭션 **안**, 쓰기 전에 있다(사전검사만으로는 동시 호출이 둘 다 통과한다).
      //   ② 같은 문서 재확인이 쓰기 전에 있다.
      //   ③ [POSTING-AUTH-43] 초대 권한 판정도 같은 트랜잭션 안에 있다 — 그래서 fence 가 둘째 read 가 됐다.
      //   권한 회수 보호의 실제 동작은 서버 경합 시험(.44 quota44 초대 회수, 45/0)이 보장한다.
      //   트랜잭션 안 read 순서는 정합성에 영향이 없다(모든 read 가 write 앞이다).
      final txAt = cf.indexOf('await db.runTransaction(async (invTx) => {');
      expect(txAt, isNot(-1));
      final setAt = cf.indexOf('invTx.set(newAppRef,', txAt);
      final fenceAt = cf.indexOf('await srvAssertAccountNotFrozenInTx(invTx, targetUid, "근로자");', txAt);
      final authAt = cf.indexOf('await srvAssertPostingAuthorityInTx(invTx, callerUid, businessId);', txAt);
      final existingAt = cf.indexOf('const existing = await invTx.get(newAppRef);', txAt);
      expect(fenceAt > txAt && fenceAt < setAt, true,
          reason: '비-트랜잭션 사전검사만으로는 동시 호출이 둘 다 통과한다');
      expect(authAt > txAt && authAt < setAt, true, reason: '권한 판정이 쓰기와 같은 트랜잭션에 있어야 한다');
      expect(existingAt > txAt && existingAt < setAt, true);
    });

    test('재초대가 허용되는 상태는 명시된 셋뿐이다', () {
      expect(cf.contains('const REINVITABLE = ["REJECTED", "CANCELED", "AUTO_CANCELED"];'),
          true);
    });

    test('초대 알림 id도 결정적이다', () {
      expect(cf.contains('`to_invite_\${newAppRef.id}_\${inviteTime.toMillis()}`'),
          true);
    });
  });
}
