// [F291-C03 같은 뿌리 · impl_11] 공고 수정 저장의 슬롯 마감시간 일괄 갱신 — 읽어 둔 사본으로 배열을 통째로 덮던
//   batch(갱신 유실 가능) → 슬롯마다 트랜잭션에서 최신 문서를 읽어 같은 계산(`slotDeadlineUpdateData`)으로 쓴다.
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ALfit/models/core/slot_model.dart';
import 'package:ALfit/models/core/work_detail_data.dart';
import 'package:ALfit/services/firestore_service.dart';

String _code(String p) => File(p)
    .readAsStringSync()
    .replaceAll('\r\n', '\n')
    .split('\n')
    .where((l) => !l.trimLeft().startsWith('//'))
    .join('\n');

String _bodyOf(String src, String sig) {
  final at = src.indexOf(sig);
  expect(at, isNot(-1), reason: '$sig 가 없다');
  final m = RegExp(r'\)\s*(async\s*)?\{').firstMatch(src.substring(at));
  final open = at + m!.end - 1;
  var depth = 0;
  for (var i = open; i < src.length; i++) {
    if (src[i] == '{') depth++;
    if (src[i] == '}') {
      depth--;
      if (depth == 0) return src.substring(at, i + 1);
    }
  }
  return src.substring(at);
}

WorkDetailData _wd(String type, {DateTime? closedAt, String? closedBy, int wage = 12000}) => WorkDetailData(
      wdId: 'wd_$type',
      workType: type,
      wage: wage,
      wageType: 'hourly',
      requiredCount: 2,
      startTime: '09:00',
      endTime: '18:00',
      closedAt: closedAt,
      closedBy: closedBy,
    );

SlotModel _slot(List<WorkDetailData> wds) =>
    SlotModel(id: 'S1', toId: 'T1', date: DateTime.utc(2099, 1, 10), workDetails: wds);

List<Map<String, dynamic>> _written(Map<String, dynamic> data) =>
    (data['workDetails'] as List).cast<Map<String, dynamic>>();

void main() {
  final now = DateTime.utc(2099, 1, 1);
  final newDefs = [_wd('상하차', wage: 13000), _wd('분류', wage: 13000)];

  test('SD-1 계산 규칙은 예전 그대로 — 기존 업무는 상태 유지하며 시간·마감·금액 갱신 · 새 업무 추가 · 슬롯 마감 = 가장 이른 업무 마감', () {
    final data = slotDeadlineUpdateData(
      slot: _slot([_wd('상하차')]),
      newWorkDetails: newDefs,
      deadlineType: 'HOURS_BEFORE',
      hoursBeforeStart: 2,
      now: now,
    );
    final wds = _written(data);
    expect(wds.map((m) => m['workType']), ['상하차', '분류']);
    expect(wds.every((m) => m['wage'] == 13000), isTrue);
    // 09:00 KST - 2h = 07:00 KST = 전날 22:00 UTC
    final expected = DateTime.utc(2099, 1, 9, 22);
    expect((data['applicationDeadline'] as Timestamp).toDate().toUtc(), expected);
  });

  test('SD-2 반례 — 읽은 뒤 다른 관리자가 업무를 마감하면: 옛 사본 계산은 그 마감을 지우고, 최신 문서 계산은 둘 다 남긴다', () {
    final stale = _slot([_wd('상하차'), _wd('분류')]); // 내가 처음 읽은 사본(둘 다 열림)
    final closedAt = DateTime.utc(2099, 1, 1, 3);
    // 그 사이 관리자 B 가 '분류' 를 마감했다(같은 슬롯 문서의 workDetails 배열).
    final fresh = _slot([_wd('상하차'), _wd('분류', closedAt: closedAt, closedBy: 'adminB')]);

    Map<String, dynamic> run(SlotModel s) => slotDeadlineUpdateData(
          slot: s, newWorkDetails: newDefs, deadlineType: 'HOURS_BEFORE', hoursBeforeStart: 2, now: now);

    final fromStale = _written(run(stale)).firstWhere((m) => m['workType'] == '분류');
    final fromFresh = _written(run(fresh)).firstWhere((m) => m['workType'] == '분류');
    // 예전 경로(읽어 둔 사본으로 덮어쓰기)는 B 의 마감을 잃는다.
    expect(fromStale.containsKey('closedAt'), isFalse, reason: '옛 사본에는 마감이 없다 — 덮으면 사라진다');
    // 새 경로(트랜잭션 최신 문서)는 B 의 마감과 내 금액 변경을 **둘 다** 남긴다.
    expect(fromFresh['closedBy'], 'adminB');
    expect((fromFresh['closedAt'] as Timestamp).toDate().toUtc(), closedAt);
    expect(fromFresh['wage'], 13000);
  });

  test('SD-3 writer 는 슬롯마다 트랜잭션(tx.get → 계산 → tx.update) · batch 덮어쓰기 0 · 일부 실패는 실패로 던진다', () {
    final b = _bodyOf(_code('lib/services/firestore/to_firestore.dart'), 'Future<void> updateSlotsDeadlines(');
    expect(b.contains('batch.update('), isFalse, reason: '읽어 둔 사본으로 배열을 통째로 덮는 batch 가 남았다');
    final txAt = b.indexOf('_firestore.runTransaction((tx) async {');
    final getAt = b.indexOf('await tx.get(slotRef)');
    final calcAt = b.indexOf('slotDeadlineUpdateData(');
    final updAt = b.indexOf('tx.update(');
    expect(txAt, greaterThan(-1));
    expect([txAt, getAt, calcAt].every((i) => i > -1) && txAt < getAt && getAt < updAt && updAt < calcAt, isTrue);
    expect(b.contains("throw StateError('슬롯 마감시간 갱신 일부 실패"), isTrue, reason: 'PARTIAL WRITE != SUCCESS');
    expect(RegExp(r'slotDeadlineUpdateData\(\s*slot:\s*fresh,').hasMatch(b), isTrue,
        reason: '계산 입력은 트랜잭션에서 읽은 최신 슬롯이어야 한다(목록의 옛 사본 아님)');
  });
}
