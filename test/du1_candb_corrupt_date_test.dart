// [DU1 candB v3 · B-INPUT-PARSE] 손상된 필수 날짜(appliedAt 문자열) — 후보 응답 → production `_cfHydrate` → ApplicationModel.
//   CD-1 v2 결함 재현: v2 후보는 complete=true 로 projection 을 붙였지만 실제 앱 모델 파싱은 null(조용히 빠지면 정상 0 이 된다)
//   CD-2 v3: 같은 지원서에 projection 을 붙이지 않고 complete=false · inputIncomplete 사유 'app:appliedAt:notTimestamp'
//   입력 fixture 는 D:\AlFit-evidence\DU1\candB\run.js(v3) 가 production serializeFirestoreData 로 만든 JSON.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:ALfit/models/core/application_model.dart';
import 'package:ALfit/services/firestore_service.dart';

Map<String, dynamic> _wire(String p) =>
    cfHydrateForTest(Map<String, dynamic>.from(jsonDecode(File(p).readAsStringSync()) as Map));

void main() {
  test('CD-1 v2 — complete=true 였지만 앱 모델은 그 지원서를 읽지 못한다', () {
    final w = _wire('test/fixtures/du1_candb_v2_corrupt_appliedAt.json');
    expect((w['wageDay'] as Map)['complete'], isTrue, reason: 'v2 응답은 완전하다고 말했다');
    final it = Map<String, dynamic>.from((w['items'] as List).single as Map);
    final pa = Map<String, dynamic>.from(it['wageApplication'] as Map)..remove('applicationId');
    expect(pa['appliedAt'], isA<String>(), reason: '문자열은 재수화돼도 Timestamp 가 되지 않는다');
    expect(ApplicationModel.tryFromMap(pa, 'manual'), isNull, reason: '실제 파싱 실패 — 조용히 빠지면 정상 0');
  });

  test('CD-2 v3 — 명시 불완전, projection 없음', () {
    final w = _wire('test/fixtures/du1_candb_v3_corrupt_appliedAt.json');
    final d = Map<String, dynamic>.from(w['wageDay'] as Map);
    expect(d['complete'], isFalse);
    expect(d['inputIncomplete'], 1);
    expect(Map<String, dynamic>.from(d['incompleteReasons'] as Map), {'app:appliedAt:notTimestamp': 1});
    final it = Map<String, dynamic>.from((w['items'] as List).single as Map);
    expect(it.containsKey('wageApplication'), isFalse);
  });
}
