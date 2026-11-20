// [MISSED-CHECKOUT-WRITER] 출근만 한 근태가 미퇴근 처리에서 영구히 빠졌다
//
// `processMissedCheckouts` 는 `where("checkOut", "==", null)` 로 대상을 찾는다.
// Firestore 는 필드가 **없는** 문서를 그 조회에 넣지 않는다. 그런데 근태를
// 만드는 두 writer(앱 출근·관리자 일괄 출근)는 `checkOut` 키를 아예 쓰지
// 않았다 — 출근만 하고 퇴근하지 않은 근태가 24시간이 지나도 present 로 남았다.
// (격리 에뮬레이터에서 DEV 배포본으로 재현, DEV 에 같은 상태 5건.)
//
// 고치는 쪽은 writer 다. 조회를 바꾸면 기존 문서가 한꺼번에 처리 대상이 된다.
//
// 고정하는 것
//   MCW-1  앱 출근 생성 payload 에 checkOut: null 이 있다
//   MCW-2  일괄 출근 신규 생성(merge set)은 null 을 싣되, 기존 퇴근 시각은 지우지 않는다
//   MCW-3  일괄 출근의 기존 문서 갱신 경로도 "출근 없음 → 출근" 전이에만 null, 퇴근 시각은 보존
//   MCW-4  스케줄러 조회는 그대로다 (checkOut == null + createdAt <= 24h 전)
//   MCW-5  퇴근 가드는 null 을 "아직 퇴근 안 함"으로 본다 (!= null)
//   MCW-6  생성 트리거는 생성 시점 스냅샷이 아니라 현재 문서를 보고 status 를 고친다
//          (늦은·중복 전달이 missed_checkout·early_leave·급여 진행 상태를 되돌리지 않는다)
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _src(String p) {
  final f = File(p);
  if (!f.existsSync()) throw StateError('소스를 찾지 못했다: $p');
  return f.readAsStringSync().replaceAll('\r\n', '\n');
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
  final cf = _code(_src('functions/src/index.ts'));

  test('MCW-1 앱 출근 생성 payload 에 checkOut: null 이 있다', () {
    final checkIn = _callable(cf, 'callableCheckIn');
    final payload = _slice(checkIn, 'const docData: Record<string, unknown> = {', '};');
    expect(payload, contains('checkOut: null,'));
    expect(payload, contains('checkIn: admin.firestore.Timestamp.fromDate(effectiveCheckIn),'));
    // 같은 tx 에서 문서가 없음을 먼저 확인한다 — 기존 퇴근 시각을 덮을 수 없다.
    final tx = _slice(checkIn, 'await db.runTransaction(', 'tx.set(ref, srvOmitUndefined(docData));');
    expect(tx, contains('if (snap.exists) {'));
  });

  test('MCW-2 일괄 출근 신규 생성은 null 을 싣되 기존 퇴근 시각은 지우지 않는다', () {
    final batch = _callable(cf, 'callableBatchCheckIn');
    final create = _slice(batch, 'const newCiRef = db.collection("attendance").doc(docId);', '}), {merge: true});');
    final existing = create.indexOf('const existingSnap = await tx.get(newCiRef);');
    final keep = create.indexOf(
        'const keepExistingCheckOut = existingSnap.exists && existingSnap.data()?.checkOut != null;');
    final spread = create.indexOf('...(keepExistingCheckOut ? {} : {checkOut: null}),');
    expect(existing, greaterThan(0));
    expect(keep, greaterThan(existing));
    expect(spread, greaterThan(keep));
    expect(create, contains('tx.set(newCiRef, srvOmitUndefined({'));
  });

  test('MCW-3 일괄 출근 갱신 경로는 출근을 새로 채우는 전이에만 null 을 남기고 퇴근 시각은 덮지 않는다', () {
    final batch = _callable(cf, 'callableBatchCheckIn');
    final tx = _slice(batch, 'const snap = await tx.get(ref);', 'tx.update(ref, {');
    // 이미 출근한 문서는 이 경로에 오지 않는다 — null 은 "출근 없음 → 출근" 전이에만 쓰인다.
    expect(tx, contains('if (snapData.checkIn != null) return "alreadyCheckedIn";'));
    expect(tx, contains('const keepUpdateCheckOut = snap.exists && snap.data()?.checkOut != null;'));
    final update = _slice(batch, 'tx.update(ref, {\n                  checkIn: checkInTs,', '});');
    expect(update, contains('...(keepUpdateCheckOut ? {} : {checkOut: null}),'));
    expect(update, isNot(contains('checkOut: null,')));
  });

  test('MCW-4 스케줄러 조회는 그대로다', () {
    final pmc = _slice(cf, 'async function processMissedCheckouts(', '\n}\n');
    expect(pmc, contains('.where("checkOut", "==", null)'));
    expect(pmc, contains('.where("createdAt", "<=", Timestamp.fromDate(cutoff))'));
    expect(pmc, contains('const cutoff = new Date(now.toDate().getTime() - 24 * 60 * 60 * 1000);'));
    expect(pmc, contains('data.status === "missed_checkout"'));
  });

  test('MCW-6 생성 트리거는 현재 문서를 다시 읽고 이후 상태를 덮지 않는다', () {
    final trig = _slice(cf, 'export const onAttendanceCreated = onDocumentCreated(', '\nexport const ');
    // 스냅샷만 보고 쓰던 직접 update 가 사라졌다
    expect(trig, isNot(contains('await event.data!.ref.update(updates);')));
    final tx = _slice(trig, 'await db.runTransaction(async (tx) => {', 'tx.update(ref, patch);');
    expect(tx, contains('const cur = await tx.get(ref);'));
    expect(tx, contains('const moved = c.status !== data.status;'));
    expect(tx, contains('const checkedOut = c.checkOut != null;'));
    expect(tx, contains('["calculated", "confirmed", "transferred"].includes(c.wageStatus as string)'));
    // [ATT-CORRECTION-GUARD] 생성 때와 같은 status 로 되돌린 관리자 정정도 덮지 않는다
    //   (정정 writer 가 남기는 isModified·modifiedAt·modifiedBy·출근 시각이 스냅샷과 다르면 낡은 판정)
    expect(tx, contains('(c.isModified === true && data.isModified !== true)'));
    expect(tx, contains('tsMs(c.modifiedAt) !== tsMs(data.modifiedAt)'));
    expect(tx, contains('(c.modifiedBy ?? null) !== (data.modifiedBy ?? null)'));
    expect(tx, contains('tsMs(c.checkIn) !== tsMs(data.checkIn)'));
    expect(tx, contains('if (moved || checkedOut || wageClosed || corrected) {'));
    expect(tx, contains('delete patch.status;'));
    expect(tx, contains('if (patch.yearMonth !== undefined && c.yearMonth) delete patch.yearMonth;'));
    // 첫 전달의 정상 지각 판정은 그대로다
    expect(trig, contains('const serverStatus = isLate ? "late" : "present";'));
    expect(trig, contains('updates.checkInDistance = Math.round(distM);'));
  });

  test('MCW-5 퇴근 가드는 null 을 아직 퇴근 안 함으로 본다', () {
    final checkOut = _callable(cf, 'callableCheckOut');
    expect(checkOut, contains('if (data.checkOut != null) {'));
    expect(checkOut, isNot(contains('"checkOut" in data')));
  });

  test('MCW-7 미퇴근 전환은 조회 스냅샷으로 덮지 않는다 — 문서마다 트랜잭션에서 퇴근·상태를 다시 본다', () {
    final fn = _slice(cf, 'async function processMissedCheckouts(now: Timestamp)', '\n}\n');
    expect(fn, isNot(contains('db.batch()')));
    expect(fn, contains('await db.runTransaction(async (tx) => {'));
    expect(fn, contains('c.checkOut != null || !c.checkIn || c.status !== data.status'));
    // 판정 기준(생성 24시간)은 그대로다 — 새 기준을 만들지 않았다
    expect(fn, contains('now.toDate().getTime() - 24 * 60 * 60 * 1000'));
  });

  test('MCW-8 미퇴근 조회의 복합 색인이 저장소 정의에 있다(checkOut ASC · createdAt ASC)', () {
    final idx = File('firestore.indexes.json').readAsStringSync();
    expect(RegExp(r'"collectionGroup": "attendance",\s*"queryScope": "COLLECTION",\s*"fields": \[\s*\{ "fieldPath": "checkOut", "order": "ASCENDING" \},\s*\{ "fieldPath": "createdAt", "order": "ASCENDING" \}').hasMatch(idx), isTrue);
  });
}
