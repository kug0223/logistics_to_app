// [DU1 후속22 §2.3] 전용 reader 후보(WageDayCandidateReader) → 기존 lib loader(WageDayCandidateLoader) → 같은 lib 소비 구현.
//   fake transport 가 보존 r3 바이트(test/fixtures/du1_candb_seam19c_wire.json, d939baf9…)를 decode 해 돌려준다.
//   같은 SHA 의 응답을 du22 실제 onCall wrapper(로컬 express·emulator, skipTokenVerification) 도 냈다
//   (D:\AlFit-evidence\DU1\candB\du22\gen\wire_du22_callable_w.json) — 이 시험 자체는 transport 주입 LOCAL 이며 실제 네트워크 호출이 아니다.
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ALfit/screens/business_admin/dialogs/wage_day_candidate.dart';
import 'package:ALfit/services/wage_day_candidate_reader.dart';

const _r3 = 'test/fixtures/du1_candb_seam19c_wire.json';
const _r3Sha = 'd939baf93e5b934a68caa14dc0506064b89d8294479e33f3f758bd9c7fa8768f';

void main() {
  final day = DateTime(2026, 11, 3);
  final bytes = File(_r3).readAsBytesSync();

  test('RD-0 입력은 보존 r3 바이트', () => expect(sha256.convert(bytes).toString(), _r3Sha));

  test('RD-1 reader 가 loader 요청을 그대로 1회 보내고 원 envelope 를 보존 → 불완전·보류·행 연결', () async {
    final calls = <(String, Map<String, dynamic>)>[];
    final reader = WageDayCandidateReader(transport: (name, data) async {
      calls.add((name, data));
      return jsonDecode(utf8.decode(bytes)); // callable result.data 와 같은 모양(Map)
    });
    final c = await WageDayCandidateLoader.load(read: reader.read, businessId: 'biz1', civilDay: day);
    expect(calls, hasLength(1));
    expect(calls.single.$1, 'callableGetAdminAttendances');
    expect(calls.single.$2, WageDayCandidateLoader.requestFor(businessId: 'biz1', civilDay: day), reason: 'purpose·businessId·startMs·endMs 그대로');
    expect(c.wageDay, isNotNull, reason: 'envelope 의 wageDay 가 reader 에서 사라지지 않는다');
    expect(c.responseComplete, isFalse);
    expect(c.batchHoldReasons, contains('responseIncomplete'));
    expect(c.rows['t2']!.link, CandidateLink.linked);
    expect(c.rows['t6']!.link, CandidateLink.none);
  });

  test('RD-2 transport 오류 → load 실패로 전달', () async {
    final reader = WageDayCandidateReader(transport: (name, data) async => throw StateError('가짜 transport 실패'));
    await expectLater(WageDayCandidateLoader.load(read: reader.read, businessId: 'biz1', civilDay: day), throwsA(isA<StateError>()));
  });

  test('RD-3 map 이 아닌 응답 → 형식 오류(정상 0 아님)', () async {
    final reader = WageDayCandidateReader(transport: (name, data) async => null);
    await expectLater(WageDayCandidateLoader.load(read: reader.read, businessId: 'biz1', civilDay: day), throwsA(isA<StateError>()));
  });
}
