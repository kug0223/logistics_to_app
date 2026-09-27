import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// [R9 O01] 공고 합계(`to.totalPending` / `to.totalConfirmed`) 쓰기 계약.
///
///   8차에는 이 파일이 "읽기와 쓰기가 붙어 있다"를 고정했다. 그 배치는 창을
///   줄이지만 **서로 다른 invocation 의 저장 순서를 직렬화하지 않는다.**
///   9차에 그 순서를 실제로 만들어 재현했다
///   (`scripts/r9-emu-to-order.js`, 지원서 4008건 = 스캔 9페이지):
///
///     t=+0ms    재집계가 1페이지를 읽는다(대기 6)
///     t=+139ms  취소가 커밋된다(원장 대기 5)
///     t=+269ms  트리거가 대기 5 를 커밋한다      ← statsUpdatedAt 전진
///     t=+923ms  재집계가 대기 6 을 커밋한다      ← statsUpdatedAt 그대로
///     그 뒤 8초간 후속 이벤트 없음 → 원장 5 / 저장 6 으로 남는다
///
///   그래서 계약을 바꿨다. **값과 함께 그 값을 만든 읽기 시각을 적고, 더 낡은
///   스냅샷은 쓰지 않는다**(`srvCommitToTotals`). 기준은 누가 먼저 썼는지가
///   아니라 누가 더 최신 원장을 보았는지다 — "TO 가 그 사이에 바뀌었는가"로
///   막으면 최신 쪽이 거부되는 경우가 생긴다.
///
///   슬롯·업무 축은 7차부터 transaction 이 지킨다(TTW-C, 변경 없음).

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
  final flatCf = cf.replaceAll(RegExp(r'\s+'), '');

  group('TTW-A 절대 쓰기 owner 는 셋뿐이다', () {
    test('A-1 TO 합계를 절대값으로 쓰는 곳을 고정한다', () {
      // 절대 쓰기는 트리거 두 분기 + 재집계 하나.
      expect('totalPending: toPendingSnap.data().count,'.allMatches(cf).length, 1,
          reason: 'flex 분기');
      expect('totalPending: pendingSnap.data().count,'.allMatches(cf).length, 1,
          reason: '비슬롯 분기');
      expect(
          cf.contains(
              'const toUpdate: Record<string, unknown> = {totalPending, totalConfirmed};'),
          isTrue,
          reason: '재집계');
    });

    test('A-2 delta 쓰기는 transaction 안에서만 한다', () {
      // 클라이언트는 파생 집계를 쓰지 않는다(7차에 helper 제거).
      final appFs = _codeOf(_src('lib/services/firestore/application_firestore.dart'));
      expect(appFs.contains("'totalPending': FieldValue.increment("), isFalse);
      expect(appFs.contains("'totalConfirmed': FieldValue.increment("), isFalse);
    });
  });

  group('TTW-B 낡은 스냅샷이 최신을 덮지 않는다', () {
    test('B-1 절대 writer 셋 모두 fence 를 지나간다', () {
      // 정의 1 + 트리거 비슬롯 1 + 트리거 flex 1 + 재집계 1.
      expect('srvCommitToTotals('.allMatches(cf).length, 4,
          reason: '늘거나 줄면 fence 를 우회하는 경로가 생긴 것이다');
      // 우회 쓰기가 남아 있지 않다 — 합계를 직접 update 하지 않는다.
      expect(flatCf.contains('toRef.update({totalConfirmed:'), isFalse,
          reason: '트리거가 fence 없이 직접 쓰면 9차 재현이 되살아난다');
      expect(cf.contains('await db.collection("tos").doc(toId).update(toUpdate);'),
          isFalse, reason: '재집계의 무조건 쓰기는 제거됐다');
    });

    test('B-2 fence 는 transaction 안에서 저장된 읽기 시각과 비교한다', () {
      final fn = _codeOf(_slice(cf,
          'async function srvCommitToTotals(', 'function srvEarliestReadAt('));
      final flat = fn.replaceAll(RegExp(r'\s+'), '');
      expect(flat.contains('returndb.runTransaction(async(tx)=>{'), isTrue,
          reason: '비교와 쓰기가 같은 transaction 안이어야 한다');
      expect(flat.contains('awaittx.get(toRef)'), isTrue);
      expect(flat.contains('cur.get("statsSourceReadAt")'), isTrue);
      // 더 낡거나 같으면 쓰지 않는다.
      expect(flat.contains('if(prev&&srvTsAtLeast(prev,sourceReadAt)){'), isTrue);
      expect(flat.contains('returnfalse;'), isTrue);
      // 쓸 때는 읽기 시각을 함께 남긴다 — 다음 writer 의 비교 기준이다.
      expect(flat.contains('tx.update(toRef,{...totals,statsSourceReadAt:sourceReadAt})'),
          isTrue);
    });

    test('B-3 신선도는 **가장 이른** 읽기 시각이다', () {
      // 값의 신선도는 가장 오래된 입력이 정한다.
      final earliest = _codeOf(_slice(cf,
          'function srvEarliestReadAt(', 'type SrvSlotWdShape'));
      final flat = earliest.replaceAll(RegExp(r'\s+'), '');
      expect(flat.contains('if(!out||srvTsAtLeast(out,t))out=t;'), isTrue);

      // 페이지네이션은 **첫 페이지**의 읽기 시각만 기억한다.
      expect('if (!readAt) readAt = page.readTime;'.allMatches(cf).length, 1,
          reason: '트리거의 좌석 스캔');
      expect('if (!scanReadAt) scanReadAt = pageSnap.readTime;'.allMatches(cf).length, 1,
          reason: '재집계의 원장 스캔');

      // 트리거는 좌석 스캔과 대기 count() 중 이른 쪽을 쓴다.
      expect(flatCf.contains('srvEarliestReadAt([seats.readAt,pendingSnap.readTime])'),
          isTrue, reason: '비슬롯 분기');
      expect(flatCf.contains('srvEarliestReadAt([seats.readAt,toPendingSnap.readTime])'),
          isTrue, reason: 'flex 분기');
    });

    test('B-4 합계를 건너뛰면 status 도 쓰지 않는다', () {
      // status 는 같은 스냅샷의 confirmedCnt 로 판정한다 — 함께 건너뛴다.
      expect(flatCf.contains('if(applied)awaitsrvSyncToStatusSafely(toRef,totalRequired,confirmedCnt);'),
          isTrue, reason: '비슬롯 분기');
      expect(flatCf.contains('if(flexApplied){awaitsrvSyncToStatusSafely(toRef,flexTotalRequired,flexConfirmedCnt);}'),
          isTrue, reason: 'flex 분기');
    });

    test('B-5 재집계는 건너뛴 사실을 응답으로 알린다', () {
      expect(cf.contains('return {success: true, applied: toTotalsApplied,'), isTrue,
          reason: 'applied=false 는 실패가 아니라 더 최신 값이 있다는 뜻이다');
    });

    test('B-6 슬롯 구간은 여전히 TO 쓰기 뒤에 있다', () {
      // 순서 자체가 안전의 근거는 아니지만(그건 fence 가 한다),
      // 슬롯 재집계를 앞으로 옮기면 스캔과 쓰기의 간격이 더 벌어진다.
      final body = cf.substring(cf.indexOf('export const callableRecalculateTOStats'));
      final toWrite = body.indexOf('const toTotalsApplied = await srvCommitToTotals(');
      final slotPhase = body.indexOf(
          'const slotsSnap = await db.collection("tos").doc(toId).collection("slots").get();');
      expect(toWrite, greaterThan(0));
      expect(slotPhase, greaterThan(0));
      expect(toWrite, lessThan(slotPhase));
    });
  });

  group('TTW-D 좌석 정의는 한 벌이고, 그 변화는 재계산을 깨운다 (R10)', () {
    test('D-1 재집계도 트리거와 같은 좌석 술어를 쓴다', () {
      // 반납한 좌석과 기간이 끝난 장기 약속은 정원을 차지하지 않는다.
      //   재집계가 `CONFIRMED_STATUSES` 만 세던 동안, 경합이 전혀 없어도
      //   두 절대 writer 가 같은 원장에서 다른 값을 만들었다
      //   (실측 R10-2: 원장 1 / 재집계 2, 그리고 fence 가 그 값을 고정했다).
      expect(
          flatCf.contains('constoccupiesSeat=!!status&&CONFIRMED_STATUSES.includes(status)&&'
              'd.staffingReleasedAt==null&&srvOccupiesSeatToday(doc)'),
          isTrue);
      // TO 합계와 업무유형 카운터가 같은 판정을 쓴다.
      expect(flatCf.contains('if(occupiesSeat)totalConfirmed++;'), isTrue);
      expect(flatCf.contains('if(!isFlexType&&selectedWorkType&&occupiesSeat){'), isTrue);
      // 옛 술어로 돌아가지 않는다.
      expect(cf.contains('if (status && CONFIRMED_STATUSES.includes(status)) totalConfirmed++;'),
          isFalse);
    });

    test('D-2 좌석 표식이 바뀌면 status 가 같아도 재계산한다', () {
      // `staffingReleasedAt` 는 status 를 그대로 두고 정원만 되돌린다.
      //   status 만 보던 가드 때문에 그 경로에는 canonical 재계산이 돌지 않았고,
      //   delta 는 fence 시각을 남기지 않으므로 낡은 절대 쓰기가 반납을 지우면
      //   되돌릴 이벤트가 없었다(실측 R10-4).
      expect(flatCf.contains('constseatMarkChanged='), isTrue);
      expect(
          flatCf.contains('(before?.staffingReleasedAt==null)!=='
              '(after?.staffingReleasedAt==null)'),
          isTrue);
      expect(flatCf.contains('if(beforeStatus===afterStatus&&!seatMarkChanged)return;'), isTrue);
    });

    test('D-4 이미 반영된 전이에 delta 를 얹지 않는다', () {
      // 클라이언트 취소는 두 걸음이다(원장 쓰기 → delta command). 원장 쓰기가
      //   트리거를 깨우고 그 절대 재계산이 먼저 커밋되면 같은 전이가 두 번
      //   반영됐다 — 멱등 플래그는 중복 **호출**만 막는다.
      //   실측 R10-3(수정 전): 원장 대기 2 인데 저장 1.
      //   판단은 fence(저장된 값이 본 원장 시점) vs 지원서 문서의 updateTime.
      expect(flatCf.contains('constfence=incToSnap.get("statsSourceReadAt")'), isTrue);
      expect(flatCf.contains('constappWrittenAt=freshApp.updateTime;'), isTrue);
      expect(flatCf.contains('if(fence&&appWrittenAt&&srvTsAtLeast(fence,appWrittenAt)){'),
          isTrue);
      // 생략할 때도 멱등 플래그는 남긴다 — 같은 요청이 다시 와도 여기서 끝난다.
      expect(
          flatCf.contains('tx.update(appRef,{[flagField]:admin.firestore.FieldValue.serverTimestamp(),});'),
          isTrue);
    });

    test('D-3 슬롯 합계를 재집계에서 따로 모으지 않는다', () {
      // 7차에 슬롯 쓰기를 `srvSyncSlotCountersTx` 로 옮긴 뒤 읽는 곳이 없었고,
      // 반납을 보지 않는 옛 술어를 들고 있었다 — 죽은 채 두면 되살아난다.
      expect(cf.contains('const slotStats:'), isFalse);
      expect(cf.contains('const slotWorkDetailCounts:'), isFalse);
      // 진단은 남는다 — 응답으로 나간다.
      expect(cf.contains('resolvedByWdId: diagResolvedByWdId,'), isTrue);
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
