// [DU1 후속21 §1.2] 필수 주입 reader → lib 격리 loader(WageDayCandidateLoader) → lib 소비 구현(consumeCandidateWageDay).
//   reader 는 보존 r3 wire(test/fixtures/du1_candb_seam19c_wire.json, d939baf9…) 바이트를 decode 해 돌려준다 — 서버 재실행·새 seed 없음.
//   범위: '주입 reader → 앱 코드 소비' LOCAL. 실제 callable·Auth/AppCheck·권한·기본 서비스 라우팅·UI·버튼은 말하지 않는다.
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ALfit/screens/business_admin/dialogs/wage_day_candidate.dart';
import 'package:ALfit/screens/business_admin/dialogs/wage_day_inputs_loader.dart';

const _r3 = 'test/fixtures/du1_candb_seam19c_wire.json';
const _r3Sha = 'd939baf93e5b934a68caa14dc0506064b89d8294479e33f3f758bd9c7fa8768f';

void main() {
  final day = DateTime(2026, 11, 3);
  final bytes = File(_r3).readAsBytesSync();

  test('CL-0 입력 wire 는 보존 r3 바이트 그대로', () {
    expect(sha256.convert(bytes).toString(), _r3Sha);
  });

  test('CL-1 주입 read 1회·정확한 KST 일자 요청 → 같은 lib 소비 구현의 불완전·보류·행 연결 유지', () async {
    final requests = <Map<String, dynamic>>[];
    final c = await WageDayCandidateLoader.load(
      read: (req) async {
        requests.add(req);
        return Map<String, dynamic>.from(jsonDecode(utf8.decode(bytes)) as Map);
      },
      businessId: 'biz1',
      civilDay: day,
    );
    expect(requests, hasLength(1), reason: '주입 read 호출 1회');
    final w = WageDayInputsAdapter.queryWindow(day);
    expect(requests.single, {'purpose': 'wageDay', 'businessId': 'biz1', 'startMs': w.startMs, 'endMs': w.endMs});
    // 정확한 KST 하루: 2026-11-03 00:00 KST = 2026-11-02T15:00Z, 길이 24h
    expect(requests.single['startMs'], DateTime.utc(2026, 11, 2, 15).millisecondsSinceEpoch);
    expect((requests.single['endMs'] as int) - (requests.single['startMs'] as int), 24 * 3600 * 1000);

    expect(c.responseComplete, isFalse);
    expect(Map<String, dynamic>.from(c.wageDay!['incompleteReasons'] as Map), {'parentBusinessMismatch': 1, 'parentMissing': 1});
    expect(c.batchHoldReasons, containsAll(['responseIncomplete', 'rowNotLinked']));
    expect(c.attendance.isComplete, isTrue);
    expect(c.attendance.applicationVerified, isFalse);
    expect(c.attendance.needsWorkerOps, 7, reason: '근태 전제(adminConfirmed)는 입력 연결과 별개');
    for (final id in ['t3', 't4', 't6', 't7']) {
      expect(c.rows[id]!.link, CandidateLink.none, reason: id);
    }
    final t2 = c.rows['t2']!;
    expect(t2.link, CandidateLink.linked);
    expect([t2.resolved!['startTime'], t2.resolved!['endTime'], t2.resolved!['wage']], ['08:00', '17:00', 12000],
        reason: 'live 시각 + 약속 임금(live 11000 보다 우선)');
    final t5 = c.rows['t5']!;
    expect([t5.resolved!['startTime'], t5.resolved!['endTime'], t5.resolved!['wage']], ['13:00', '22:00', 12000]);
  });

  test('CL-2 주입 read 오류 → 로드 실패로 전달(빈 결과·정상 0 으로 바꾸지 않는다)', () async {
    var calls = 0;
    await expectLater(
      WageDayCandidateLoader.load(
        read: (req) async {
          calls++;
          throw StateError('가짜 read 실패');
        },
        businessId: 'biz1',
        civilDay: day,
      ),
      throwsA(isA<StateError>()),
    );
    expect(calls, 1);
  });
}
