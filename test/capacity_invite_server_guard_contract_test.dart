// [CORE-CAPACITY-ATTENDANCE-INVITE-FIX.3] 서버 두 가드의 계약을 고정한다(작업트리 index.ts).
//
//   A  callableUpdateSlotWorkDetails 정원 하한 — composite workDetailId 로만 세던 점유에
//      초대(workDetailId 없음)·제안(workDetailId=wdId)이 빠져, 확정 5명 업무를 필요 1명으로 저장했다
//      (LOCAL 에뮬레이터 · live 00014 재현). 대상 wdId 는 클라이언트 값이 아니라 지금 슬롯에서 정하고,
//      내리는 변경만 막는다(이미 낮게 저장된 값의 유지·상향은 회복 경로).
//   C  callableInviteWorker 업무 식별 — 업무명·시간을 빼거나 없는 업무명을 보내면 업무·임금 없는
//      INVITED 와 알림을 만들었고, 그 초대는 수락도 되지 않았다(LOCAL 재현).
//
//   실제 동작 증거는 core-invite-wd-20261026/run-A3*·run-C3* (live lib 대조). 여기서는 소스 계약만 본다.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _src(String p) => File(p).readAsStringSync().replaceAll('\r\n', '\n');

String _slice(String src, String start, String end) {
  final i = src.indexOf(start);
  if (i < 0) throw StateError('구간 시작을 찾지 못했다: $start');
  final j = src.indexOf(end, i + start.length);
  if (j <= i) throw StateError('구간 끝을 찾지 못했다: $end');
  return src.substring(i, j);
}

void main() {
  final cf = _src('functions/src/index.ts');

  group('A 정원 하한', () {
    final fn = _slice(cf, 'const checkRequiredCountLowerBound = async (', '\n    // ── SINGLE 처리 ──');

    test('A-1 점유는 정본 resolver 로 귀속을 정하고 composite 만으로 세지 않는다', () {
      expect(fn, contains('srvResolveAppWdId(doc.data(), {wds: oldWDs, isNewSchema: true})'));
      expect(fn, isNot(contains('.where("workDetailId", "==", workDetailId)')));
    });

    test('A-2 대상 wdId 는 지금 슬롯(oldWDs)의 같은 정의에서 정한다 — 클라이언트 d.wdId 를 쓰지 않는다', () {
      expect(fn, contains('const old = oldWDs.find((w) => compOf(w) === workDetailId);'));
      expect(fn, contains('r.wdId === old["wdId"]'));
      expect(RegExp(r'\bd\["wdId"\]').hasMatch(fn), isFalse, reason: '클라이언트가 보낸 업무 정의의 wdId');
    });

    test('A-3 내리는 변경만 막는다 — 유지·상향은 회복 경로', () {
      expect(fn, contains('if (newRequired >= oldRequired) continue;'));
    });

    test('A-4 귀속을 정하지 못한 점유가 있으면 내리는 변경을 막고 이유를 남긴다', () {
      expect(fn, contains('{code: "OCCUPANCY_UNRESOLVED"}'));
    });

    test('A-5 두 호출 모두 트랜잭션 안의 지금 슬롯 정의를 넘긴다', () {
      expect(cf, contains('await checkRequiredCountLowerBound(toId, slotId!, newWDs!, oldWDs);'));
      expect(cf, contains('await checkRequiredCountLowerBound(toId, update.slotId, update.workDetails, oldWDs);'));
    });
  });

  group('C 초대 업무 식별', () {
    final inv = _slice(cf, 'export const callableInviteWorker = onCall(', '\nexport const ');

    test('C-1 빈 문자열·공백·문자열 아닌 업무명/시간은 형식 오류', () {
      expect(inv, contains('(typeof v !== "string" || v.trim().length === 0)'));
      expect(inv, contains('형식이 올바르지 않습니다.'));
    });

    test('C-2 업무명이 없으면 정의가 하나뿐일 때만 그 업무 — 여럿·없음은 거절', () {
      expect(inv, contains('const only = wdsAll.length === 1 ? wdsAll[0]["workType"] : undefined;'));
      expect(inv, contains('"초대할 업무를 특정할 수 없습니다. 업무와 근무 시간을 함께 지정해주세요.", {code: "INVITE_WORK_UNRESOLVED"}'));
    });

    test('C-3 업무를 찾지 못하면 저장 전에 거절한다(시간 없는 업무명 포함)', () {
      final guard = inv.indexOf('if (!inviteMatchedWD) {');
      final write = inv.indexOf('invTx.set(newAppRef');
      expect(guard, greaterThan(0));
      expect(write, greaterThan(guard), reason: '거절은 지원서 저장·카운터·알림보다 앞이다');
    });
  });
}
