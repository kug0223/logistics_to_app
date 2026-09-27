import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// [R8 O01] 공고 합계(`to.totalPending` / `to.totalConfirmed`) 쓰기 계약.
///
///   슬롯·업무 축은 7차에 transaction 안으로 옮겨 닫았다. TO 축은 아직
///   transaction 밖 읽기 + 무조건 update 다. 그래도 실측에서 어긋나지 않는
///   이유는 **읽기와 쓰기가 붙어 있기** 때문이다:
///
///     · 트리거(`_syncTOCounters`): 느린 일(슬롯 transaction)이 **읽기 앞**에
///       있고, 원장 읽기 직후에 바로 쓴다.
///     · 재집계(`callableRecalculateTOStats`): 원장 스캔 직후에 바로 쓰고,
///       느린 일(슬롯별 transaction)은 **쓰기 뒤**에 있다.
///
///   그래서 "먼저 읽고 한참 뒤에 쓰는" 낡은 쓰기가 만들어지지 않는다.
///   이 테스트는 **그 배치가 깨지면 실패한다** — 누군가 읽기와 쓰기 사이에
///   오래 걸리는 일을 넣으면 stale 창이 열리기 때문이다.
///
///   실행 증거는 `scripts/r8-emu-to-total-race.js` 에 있다(T2·T3·T4·T5).

String _src(String p) => File(p).readAsStringSync();
String _codeOf(String b) => b
    .split('\n')
    .where((l) => !l.trimLeft().startsWith('//') && !l.trimLeft().startsWith('*'))
    .join('\n');

const _cfPath = 'functions/src/index.ts';

/// [from] 이후 [to] 까지의 구간. 못 찾으면 예외로 실패시킨다.
String _slice(String s, String from, String to) {
  final i = s.indexOf(from);
  if (i < 0) throw StateError('시작 표지 없음: $from');
  final j = s.indexOf(to, i + from.length);
  if (j < 0) throw StateError('끝 표지 없음: $to');
  return s.substring(i, j);
}

void main() {
  final cf = _codeOf(_src(_cfPath));

  group('TTW-A 절대 쓰기 owner 는 셋뿐이다', () {
    test('A-1 TO 합계를 절대값으로 쓰는 곳을 고정한다', () {
      // 절대 쓰기는 트리거 두 분기 + 재집계 하나.
      expect('totalPending: toPendingSnap.data().count,'.allMatches(cf).length, 1,
          reason: 'flex 분기');
      expect('totalPending: pendingSnap.data().count,'.allMatches(cf).length, 1,
          reason: '비슬롯 분기');
      expect(cf.contains('const toUpdate: Record<string, unknown> = {totalPending, totalConfirmed};'),
          isTrue, reason: '재집계');
    });

    test('A-2 delta 쓰기는 transaction 안에서만 한다', () {
      // 클라이언트는 파생 집계를 쓰지 않는다(7차에 helper 제거).
      final appFs = _codeOf(_src('lib/services/firestore/application_firestore.dart'));
      expect(appFs.contains("'totalPending': FieldValue.increment("), isFalse);
      expect(appFs.contains("'totalConfirmed': FieldValue.increment("), isFalse);
    });
  });

  group('TTW-B 읽기와 쓰기가 붙어 있다', () {
    test('B-1 트리거 flex — 원장 읽기 직후에 TO 를 쓴다', () {
      // 읽기가 **끝난 뒤**부터 쓰기까지의 구간만 본다.
      final gap = _codeOf(_slice(
        cf,
        'const confirmedCount = seats.bySlot.get(slotId) ?? 0;',
        'await toRef.update({',
      ));
      // 읽기와 쓰기 사이에 await 이 남아 있으면 stale 창이 열린다.
      expect(gap.contains('await '), isFalse,
          reason: '원장 읽기와 TO 쓰기 사이에 기다리는 일을 넣으면 낡은 값이 생긴다');
    });

    test('B-2 트리거 flex — 느린 슬롯 transaction 은 읽기 **앞**에 있다', () {
      final body = cf.substring(cf.indexOf('async function _syncTOCounters('));
      final slotTx = body.indexOf('await srvSyncSlotCountersTx(toRef, slotId, occupiesSeatToday);');
      final read = body.indexOf('const [seats, toPendingSnap, slotDoc] = await Promise.all([');
      expect(slotTx, greaterThan(0));
      expect(read, greaterThan(0));
      expect(slotTx, lessThan(read),
          reason: '느린 일이 읽기 뒤로 가면 읽기→쓰기 간격이 벌어진다');
    });

    test('B-3 재집계 — 스캔 직후 TO 를 쓰고, 슬롯 작업은 그 **뒤**다', () {
      final body = cf.substring(cf.indexOf('export const callableRecalculateTOStats'));
      final toWrite = body.indexOf('await db.collection("tos").doc(toId).update(toUpdate);');
      final slotPhase = body.indexOf('const slotsSnap = await db.collection("tos").doc(toId).collection("slots").get();');
      expect(toWrite, greaterThan(0));
      expect(slotPhase, greaterThan(0));
      expect(toWrite, lessThan(slotPhase),
          reason: '슬롯 구간이 TO 쓰기 앞으로 오면 그만큼 낡은 값이 된다');
    });
  });

  group('TTW-C 슬롯·업무 축은 transaction 이 지킨다', () {
    test('C-1 슬롯 범위는 쓰기 시점에 다시 센다', () {
      final tx = _codeOf(_slice(cf,
          'async function srvSyncSlotCountersTx(', 'async function _syncTOCounters('));
      final flat = tx.replaceAll(RegExp(r'\s+'), '');
      expect(flat.contains('returndb.runTransaction(async(tx)=>{'), isTrue);
      // 읽기가 transaction 안에 있어야 conflict 가 잡힌다.
      expect(flat.contains('tx.get(slotRef)'), isTrue);
      expect(flat.contains('tx.get(slotAppsRef.where("status","in",PENDING_STATUSES)'), isTrue);
      expect(flat.contains('tx.get(slotAppsRef.where("status","in",CONFIRMED_STATUSES)'), isTrue);
      // 쓰기도 같은 transaction 안이다.
      expect(flat.contains('tx.update(slotRef,{'), isTrue);
    });

    test('C-2 트리거와 재집계가 같은 writer 를 쓴다', () {
      expect('srvSyncSlotCountersTx('.allMatches(cf).length, 3,
          reason: '정의 1 + 트리거 1 + 재집계 1. 늘어나면 책임이 갈라진 것이다');
    });
  });
}
