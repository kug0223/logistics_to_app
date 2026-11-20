// [DU1 후속19 §1.2] 실제 joined 최종 wire(seam19 emulator 실행이 쓴 W-only 응답 원문) → 기존 앱 수신 경계.
//   입력: test/fixtures/du1_candb_seam19c_wire.json = D:\AlFit-evidence\DU1\candB\seam19\gen\wire_w_joined.r3.json 바이트 사본(seam19c_run.js)
//   (SHA d939baf9… — seam19/caller.log r3 줄의 wire= 와 같다). 손으로 조립하지 않았다. r1 wire(9020363f…)는 seed 근태에 createdAt 이 없어
//   AttendanceModel 파싱에서 실패했고, r2(f285aba7…)는 지원서 selectedWorkType 이 'x' 라 앱 WorkDetailHelper 가 live 업무를 못 찾았다(seed 결함)
//   — 실패 원본은 D 에 보존(du19-seam19-wire.r1.FAILED-no-createdAt.log, r3.FAILED-seed-selectedWorkType.log).
//   경계: production `_cfHydrate`(cfHydrateForTest seam) → ApplicationModel/AttendanceModel.tryFromMap → WorkDetailHelper.resolve
//   → 기존 WageDayInputsAdapter.classify. decoder·모델·날짜 검사는 새로 만들지 않는다.
//   범위 밖: production callable 채택·W-only UI/adapter 연결·wageDay 를 읽는 앱 소비자(아직 없음)·Auth/AppCheck·DEV.
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ALfit/models/core/application_model.dart';
import 'package:ALfit/models/core/attendance_model.dart';
import 'package:ALfit/screens/business_admin/dialogs/wage_day_inputs_loader.dart';
import 'package:ALfit/services/firestore_service.dart';
import 'package:ALfit/utils/format_helper.dart';
import 'package:ALfit/utils/work_detail_helper.dart';

const _fixture = 'test/fixtures/du1_candb_seam19c_wire.json';
const _wireSha = 'd939baf93e5b934a68caa14dc0506064b89d8294479e33f3f758bd9c7fa8768f';

void main() {
  final bytes = File(_fixture).readAsBytesSync();
  final wire = cfHydrateForTest(Map<String, dynamic>.from(jsonDecode(utf8.decode(bytes)) as Map));
  final items = (wire['items'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
  Map<String, dynamic> item(String id) => items.firstWhere((e) => e['id'] == id);
  AttendanceModel att(Map<String, dynamic> it) {
    final m = Map<String, dynamic>.from(it)..remove('wageApplication')..remove('wageWorkDetail');
    final id = m.remove('id') as String;
    return AttendanceModel.tryFromMap(m, id)!;
  }

  test('WS-0 fixture 는 seam19 실제 wire 바이트 그대로', () {
    expect(sha256.convert(bytes).toString(), _wireSha);
  });

  test('WS-1 정상(t1) — 재수화된 projection 이 기존 모델로 파싱되고 근태와 관계가 맞는다', () {
    final it = item('t1');
    final a = att(it);
    final pa = Map<String, dynamic>.from(it['wageApplication'] as Map);
    expect(pa['applicationId'], it['applicationId'], reason: 'envelope = attendance.applicationId');
    final appId = pa.remove('applicationId') as String;
    final app = ApplicationModel.tryFromMap(pa, appId);
    expect(app, isNotNull, reason: 'workDate/appliedAt 가 Timestamp 로 재수화돼야 파싱된다');
    expect(app!.workDate, a.workDate, reason: '같은 serializer 형식 → 같은 instant');
    expect(FormatHelper.toKstDate(app.workDate), DateTime.utc(2026, 11, 3), reason: 'toKstDate 는 UTC 표현 비교 키');
    expect(app.appliedAt, isNotNull);
    expect([app.uid, app.businessId, app.toId, app.slotId, app.workDetailId], [a.userId, a.businessId, 'to1', 's1', 'wd1']);
    final wd = Map<String, dynamic>.from(it['wageWorkDetail'] as Map);
    final r = WorkDetailHelper.resolve(app, {'${wd['workType']}_${wd['startTime']}_${wd['endTime']}': wd});
    expect(r, isNotNull, reason: 'live 업무 projection 이 급여창 resolve 에 쓰인다');
    expect([r!['startTime'], r['endTime'], r['wage'], r['wageType']], ['09:00', '18:00', 12000, 'hourly']);
    expect(wd.containsKey('rawMemo') || wd.containsKey('requiredCount'), isFalse);
  });

  test('WS-2 부모거절(t6 타사 TO · t7 부모 없음) — projection 없음, 불완전 그대로', () {
    for (final id in ['t6', 't7']) {
      final it = item(id);
      expect(it.containsKey('wageApplication') || it.containsKey('wageWorkDetail'), isFalse, reason: id);
      expect(att(it).applicationId, isNotEmpty, reason: '$id 근태 자체는 기존대로 파싱된다');
    }
    final wd = Map<String, dynamic>.from(wire['wageDay'] as Map);
    expect(wd['complete'], isFalse, reason: '부모거절이 있으면 완전하지 않다');
    expect(wd['inputIncomplete'], 2);
    expect(Map<String, dynamic>.from(wd['incompleteReasons'] as Map), {'parentBusinessMismatch': 1, 'parentMissing': 1});
    expect(utf8.decode(bytes).contains('99999'), isFalse, reason: '타사 업무 임금 미노출(wire 원문)');
  });

  test('WS-3 기존 분류기 — 부모거절 행을 지원서 확인된 처리 가능으로 말하지 않는다', () {
    final c = WageDayInputsAdapter.classify(
        items: items.map((e) => Map<String, dynamic>.from(e)..remove('wageApplication')..remove('wageWorkDetail')).toList(),
        limitReached: wire['limitReached'] as bool,
        businessId: 'biz1',
        civilDay: DateTime(2026, 11, 3));
    expect(c.unparsed, 0);
    expect(c.isComplete, isTrue, reason: '근태 분류 완전성(지원서와 무관)');
    expect(c.applicationVerified, isFalse, reason: '근태 분류기는 지원서·부모 확인을 주장하지 않는다 — wageDay.complete 가 그 사실을 따로 말한다');
    // seed 근태에 adminConfirmed 가 없다 — 기존 분류기는 7행 모두 '인력 확인 필요'로 센다(급여 탭 후보 0). 어느 쪽이든 처리 가능 보증이 아니다.
    expect(c.needsWorkerOps, 7);
    expect(c.tabRowsWithCheckIn, 0);
  });
}
