// [DU1 후속20 §1.2] 시험 전용 candidate 소비경계(test/support/du1_candb_wire_consumer.dart) — 보존 실제 wire r2·r3 입력.
//   r3 = test/fixtures/du1_candb_seam19c_wire.json (D:\AlFit-evidence\DU1\candB\seam19\gen\wire_w_joined.r3.json, d939baf9…)
//   r2 = test/fixtures/du1_candb_seam19b_wire.json (…\wire_w_joined.r2.json, f285aba7… — 지원서 selectedWorkType 'x' 원문 그대로)
//   production 호출부·급여창 prefetch(composite key, wage_confirm_dialog.dart:253)는 바꾸지 않았다 — 이 시험은 그 경로를 말하지 않는다.
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/du1_candb_wire_consumer.dart';

Map<String, dynamic> _load(String p, String sha) {
  final b = File(p).readAsBytesSync();
  expect(sha256.convert(b).toString(), sha, reason: '$p 는 보존 wire 바이트 그대로');
  return Map<String, dynamic>.from(jsonDecode(utf8.decode(b)) as Map);
}

const _r3 = 'test/fixtures/du1_candb_seam19c_wire.json';
const _r3Sha = 'd939baf93e5b934a68caa14dc0506064b89d8294479e33f3f758bd9c7fa8768f';
const _r2 = 'test/fixtures/du1_candb_seam19b_wire.json';
const _r2Sha = 'f285aba7d9e0dd8d1e736d65488be139803ec9876be8aa277af659b0ad39a39a';

void main() {
  final day = DateTime(2026, 11, 3);

  test('CC-1 r3 — 응답 불완전(부모거절·missing·mismatch)이 근태 분류 완전성과 따로 남고 일괄 판정은 보류', () {
    final c = consumeCandidateWageDay(_load(_r3, _r3Sha), businessId: 'biz1', civilDay: day);
    expect(c.attendance.isComplete, isTrue, reason: '근태 파싱·중복 기준으로는 완전');
    expect(c.attendance.applicationVerified, isFalse, reason: '기존 상수 — 바꾸지 않는다');
    expect(c.responseComplete, isFalse);
    expect(c.wageDay!['applicationMissing'], 1);
    expect(c.wageDay!['applicationMismatch'], 1);
    expect(c.wageDay!['inputIncomplete'], 2);
    expect(Map<String, dynamic>.from(c.wageDay!['incompleteReasons'] as Map), {'parentBusinessMismatch': 1, 'parentMissing': 1});
    expect(c.batchHoldReasons, containsAll(['responseIncomplete', 'rowNotLinked']));
    expect(c.batchHoldReasons, isNot(contains('attendanceClassificationIncomplete')));
    for (final id in ['t3', 't4', 't6', 't7']) {
      expect(c.rows[id]!.link, CandidateLink.none, reason: '$id projection 없음 — 정상 0·검증된 지원서로 바꾸지 않는다');
    }
    expect(c.attendance.needsWorkerOps, 7, reason: 'seed 근태 adminConfirmed 없음 — 입력 연결과 별개의 근태 전제');
  });

  test('CC-2 r3 t1·t2·t5 — workDetailId 키로 live 업무 연결, 약속 임금 우선·live 시각 유지', () {
    final c = consumeCandidateWageDay(_load(_r3, _r3Sha), businessId: 'biz1', civilDay: day);
    final want = {
      // id: [지원서 startTime, live startTime, live endTime, live wage, 약속 wage]
      't1': ['09:00', '09:00', '18:00', 12000, 12000],
      't2': ['09:00', '08:00', '17:00', 11000, 12000], // 지원서 시각 ≠ live 시각 — composite 키로는 못 찾는다
      't5': ['09:00', '13:00', '22:00', 13500, 12000],
    };
    want.forEach((id, w) {
      final r = c.rows[id]!;
      expect(r.link, CandidateLink.linked, reason: id);
      expect(r.application!.startTime, w[0], reason: '$id 지원서 원문 시각');
      expect(r.resolved!['startTime'], w[1], reason: '$id live 시각(effectiveStart 계열은 현재 정의 우선)');
      expect(r.resolved!['endTime'], w[2], reason: id);
      expect(r.resolved!['wage'], w[4], reason: '$id 약속 임금(${w[4]})이 live(${w[3]})를 이긴다');
    });
  });

  test('CC-3 r2(원문 selectedWorkType=x) — 이름이 달라도 이미 확인된 workDetailId 관계로 연결', () {
    final c = consumeCandidateWageDay(_load(_r2, _r2Sha), businessId: 'biz1', civilDay: day);
    final r = c.rows['t1']!;
    expect(r.application!.selectedWorkType, 'x', reason: '보존 r2 원문 그대로');
    expect(r.link, CandidateLink.linked, reason: '이름 추정 없이 그 지원서의 workDetailId(wd1) 키');
    expect([r.resolved!['startTime'], r.resolved!['endTime'], r.resolved!['wage']], ['09:00', '18:00', 12000]);
    expect(c.responseComplete, isFalse);
    expect(c.batchHoldReasons, contains('responseIncomplete'));
  });

  test('CC-4 projection 없는 wire(K-only 모양) — 후보 응답 아님을 완전으로 바꾸지 않는다', () {
    final w = _load(_r3, _r3Sha);
    final bare = {
      'items': (w['items'] as List).map((e) => Map<String, dynamic>.from(e as Map)..remove('wageApplication')..remove('wageWorkDetail')).toList(),
      'limitReached': false,
    };
    final c = consumeCandidateWageDay(bare, businessId: 'biz1', civilDay: day);
    expect(c.wageDay, isNull);
    expect(c.responseComplete, isFalse);
    expect(c.batchHoldReasons, contains('noCandidateResponse'));
  });
}
