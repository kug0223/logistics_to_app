// [DU1 candB · followup_7 §3.2] 후보 B 응답(wire) — 실제 production 직렬화·재수화 경로의 앱 쪽 동치(LOCAL·미배포·미연결).
//   입력: D:\AlFit-evidence\DU1\candB\run.js 가 **production serializeFirestoreData**(functions/src/index.ts 원문 span,
//   gen/prod_extract.meta.json 에 sha) 로 직렬화해 JSON 으로 쓴 test/fixtures/du1_candb_wire.json·du1_candb_full.json.
//   재수화: **production `_cfHydrate`**(lib/services/firestore_service.dart) 를 cfHydrateForTest seam 으로 그대로 부른다.
//   WB-1 projection → ApplicationModel → WorkDetailHelper.resolve(live projection 키) 가 전체 문서 + live 원문과 같다(MANUAL/AUTO/레거시)
//   WB-2 레거시: 약속 wageType(daily) 이 공고 현재(hourly) 를 이긴다 — 클라이언트도 서버(run-result.json)와 같은 방향
//   WB-3 live projection 에 레거시 지급일정 fallback(payScheduleType/Day) 이 있고 원문 전용 필드는 없다
//   WB-4 envelope applicationId == attendance.applicationId, 근태 항목은 기존 AttendanceModel 로 그대로 파싱된다
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:ALfit/models/core/application_model.dart';
import 'package:ALfit/models/core/attendance_model.dart';
import 'package:ALfit/services/firestore_service.dart';
import 'package:ALfit/utils/work_detail_helper.dart';

const _consumerKeys = <String>[
  'wage', 'wageType', 'breakMinutes', 'baseHourlyWage', 'nightAllowanceApplied', 'nightIncluded',
  'taxDeductionType', 'shiftType', 'startTime', 'endTime', 'payScheduleType', 'payScheduleDay',
];

Map<String, dynamic> _json(String p) => Map<String, dynamic>.from(jsonDecode(File(p).readAsStringSync()) as Map);

void main() {
  final wire = cfHydrateForTest(_json('test/fixtures/du1_candb_wire.json'));
  final full = cfHydrateForTest(_json('test/fixtures/du1_candb_full.json'));
  final items = (wire['items'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
  final fullApps = Map<String, dynamic>.from(full['apps'] as Map);
  final fullLive = Map<String, dynamic>.from(full['live'] as Map);

  String keyOf(Map<String, dynamic> wd) => '${wd['workType']}_${wd['startTime']}_${wd['endTime']}';

  test('WB-1 MANUAL/AUTO/레거시 — projection 경로 = 전체 문서 경로(급여창 사용 필드·약속 resolve)', () {
    expect(items.length, 3);
    for (final it in items) {
      final id = it['applicationId'] as String;
      final pa = Map<String, dynamic>.from(it['wageApplication'] as Map)..remove('applicationId');
      final pwd = Map<String, dynamic>.from(it['wageWorkDetail'] as Map);
      final a = ApplicationModel.tryFromMap(Map<String, dynamic>.from(fullApps[id] as Map), id)!;
      final b = ApplicationModel.tryFromMap(pa, id);
      expect(b, isNotNull, reason: '$id projection 파싱(appliedAt/workDate Timestamp 재수화)');
      expect([b!.uid, b.toId, b.slotId, b.selectedWorkType, b.workDetailId, b.startTime, b.endTime, b.wage, b.wageType],
          [a.uid, a.toId, a.slotId, a.selectedWorkType, a.workDetailId, a.startTime, a.endTime, a.wage, a.wageType], reason: id);
      expect(b.workDate, a.workDate);
      expect(b.appliedAt, a.appliedAt);
      final mapFull = <String, dynamic>{keyOf(fullLive): fullLive};
      final mapProj = <String, dynamic>{keyOf(pwd): pwd};
      // 급여창이 resolve 결과에서 읽는 키(WorkDetailHelper getter 전수 + 지급일정 직접 read) — 원문 전용 키(requiredCount 등)는 비교하지 않는다
      final ra = WorkDetailHelper.resolve(a, mapFull)!;
      final rb = WorkDetailHelper.resolve(b, mapProj)!;
      for (final k in _consumerKeys) {
        expect(rb[k], ra[k], reason: '$id resolve[$k]');
      }
    }
  });

  test('WB-2 레거시 — 약속 wageType 이 공고 현재를 이긴다(클라이언트)', () {
    final it = items.firstWhere((e) => e['applicationId'] == 'legacy');
    final pa = Map<String, dynamic>.from(it['wageApplication'] as Map)..remove('applicationId');
    final b = ApplicationModel.tryFromMap(pa, 'legacy')!;
    expect(b.hasCompensationSnapshot, isFalse);
    final pwd = Map<String, dynamic>.from(it['wageWorkDetail'] as Map);
    final r = WorkDetailHelper.resolve(b, {keyOf(pwd): pwd})!;
    expect(pwd['wageType'], 'hourly');
    expect(r['wageType'], 'daily', reason: '서버 srvResolvePromisedCompensation(run-result.json legacy.promised.wageType=daily) 과 같은 방향');
    expect(r['wage'], 110000);
  });

  test('WB-3 live projection — 지급일정 fallback 있음, 원문 전용 필드 없음', () {
    for (final it in items) {
      final pwd = Map<String, dynamic>.from(it['wageWorkDetail'] as Map);
      expect(pwd['payScheduleType'], 'next_day');
      expect(pwd['payScheduleDay'], 1);
      expect(pwd['shiftType'], 'day', reason: 'WorkDetailHelper.shiftType 소비 — 처음 후보에서 빠졌던 필드');
      expect(pwd.containsKey('requiredCount'), isFalse);
      expect(pwd.containsKey('rawSecretMemo'), isFalse);
      final pa = Map<String, dynamic>.from(it['wageApplication'] as Map);
      for (final k in const ['applicationMessage', 'cancelReason', 'attendancePolicyAcknowledgement', 'conflictingBusiness', 'confirmedAt', 'toTitle']) {
        expect(pa.containsKey(k), isFalse, reason: k);
      }
    }
  });

  test('WB-4 envelope·근태 항목 — 기존 AttendanceModel 로 그대로 파싱', () {
    for (final it in items) {
      final pa = Map<String, dynamic>.from(it['wageApplication'] as Map);
      expect(pa['applicationId'], it['applicationId']);
      final m = Map<String, dynamic>.from(it)..remove('wageApplication')..remove('wageWorkDetail');
      final id = m.remove('id') as String;
      final att = AttendanceModel.tryFromMap(m, id);
      expect(att, isNotNull);
      expect(att!.applicationId, it['applicationId']);
      expect(att.checkInAt, isNotNull);
    }
    expect((wire['wageDay'] as Map)['applied'], isTrue);
    expect((wire['wageDay'] as Map)['applicationMissing'], 0);
  });
}
