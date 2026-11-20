// [INVITE-WD-1] 계약서를 만들 업무 정의 — 같은 업무명 두 시간대(A 12:10–13:10 · B 14:20–14:50).
//
//   입력은 LOCAL 하네스(core-invite-wd-20261026/runW2)에서 **배포 writer 가 만든** 문서다:
//   초대(00049)→수락(00061)한 B 초대 지원서(workDetailId 없음 · wdId=슬롯 B), 직접 지원(00104) B 지원서,
//   마스터 공고 workDetails(슬롯과 다른 무작위 wdId). 손으로 연결 필드를 채우지 않았다.
//
//   예전 세 입구(contract_dispatch_flow · worker_detail_dialog · admin_contract_management)는
//   workDetailId 가 없으면 '업무명 첫 일치 → 첫 원소' 로 A 를 골라 계약 번들 키·휴게·지급 조건이 A 로 갔다.
import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:flutter_test/flutter_test.dart';

import 'package:ALfit/models/core/application_model.dart';
import 'package:ALfit/models/core/work_detail_data.dart';
import 'package:ALfit/utils/work_detail_helper.dart';

Object? _restore(Object? v) => v is Map
    ? (v.length == 1 && v.containsKey('__ts')
        ? Timestamp.fromMillisecondsSinceEpoch((v['__ts'] as num).toInt())
        : v.map((k, x) => MapEntry(k as String, _restore(x))))
    : v is List
        ? v.map(_restore).toList()
        : v;

/// 변경 전 세 입구의 선택식(그대로 옮김) — 부정 대조용. 제품 코드에는 더 이상 없다.
WorkDetailData _legacySelect(ApplicationModel app, List<WorkDetailData> wds) {
  if (app.workDetailId?.isNotEmpty == true) {
    return wds.firstWhere(
      (w) => w.id == app.workDetailId || w.legacyId == app.workDetailId,
      orElse: () => wds.firstWhere((w) => w.workType == app.selectedWorkType, orElse: () => wds.first),
    );
  }
  return wds.firstWhere((w) => w.workType == app.selectedWorkType, orElse: () => wds.first);
}

String _src(String p) => File(p).readAsStringSync();

void main() {
  final j = (_restore(jsonDecode(File('test/fixtures/invite_wd_for_app.json').readAsStringSync())) as Map)
      .cast<String, dynamic>();
  final inv = ApplicationModel.fromMap((j['invApp'] as Map).cast<String, dynamic>(), 'inv');
  final dir = ApplicationModel.fromMap((j['dirApp'] as Map).cast<String, dynamic>(), 'dir');
  final master = ((j['to'] as Map)['workDetails'] as List)
      .map((m) => WorkDetailData.fromMap((m as Map).cast<String, dynamic>()))
      .toList();
  final b = j['B'] as Map;
  final bId = '분류_${b['startTime']}_${b['endTime']}';

  test('전제: 배포 writer 출력 그대로 — 초대는 workDetailId 없음, 직접 지원은 composite', () {
    expect(inv.workDetailId, isNull);
    expect(inv.wdId, (j['slotWd'] as Map)['B']);
    expect(dir.workDetailId, bId);
    expect(master.map((w) => w.workType).toSet(), {'분류'});
    expect(master.length, 2);
    expect(master.first.id, isNot(bId), reason: '배열 0번은 A');
  });

  test('부정 대조: 변경 전 선택식은 초대 B 지원서에 A 를 고른다', () {
    expect(_legacySelect(inv, master).id, isNot(bId));
  });

  test('초대 B 지원서 → B · 계약 번들 키가 직접 지원 B 와 같다', () {
    final w = WorkDetailHelper.contractWorkDetailFor(inv, master);
    expect(w?.id, bId);
    final d = WorkDetailHelper.contractWorkDetailFor(dir, master);
    expect(d?.id, bId);
    // ContractService 의 번들 키 = application.workDetailId ?? workDetail.id
    expect(inv.workDetailId ?? w!.id, dir.workDetailId ?? d!.id);
    expect(w!.breakMinutes, d!.breakMinutes);
    expect(w.payScheduleType, d.payScheduleType);
  });

  test('특정할 수 없으면 null — 첫 원소로 대신하지 않는다', () {
    final noTime = inv.copyWith(startTime: '', endTime: '', wdId: 'unknown-wd');
    expect(WorkDetailHelper.contractWorkDetailFor(noTime, master), isNull);
  });

  test('업무명이 하나뿐인 옛 지원서는 그 업무', () {
    final single = [master.last];
    final legacy = inv.copyWith(startTime: '', endTime: '', wdId: 'unknown-wd');
    expect(WorkDetailHelper.contractWorkDetailFor(legacy, single)?.id, bId);
  });

  test('세 입구가 같은 해석을 쓴다 — 첫 원소 대체가 남아 있지 않다', () {
    for (final p in [
      'lib/screens/business_admin/contract_dispatch_flow.dart',
      'lib/widgets/dialogs/worker_detail_dialog.dart',
      'lib/screens/business_admin/admin_contract_management_screen.dart',
    ]) {
      final s = _src(p);
      expect(s.contains('WorkDetailHelper.contractWorkDetailFor('), isTrue, reason: p);
      expect(s.contains('orElse: () => workDetails.first'), isFalse, reason: p);
    }
  });
}
