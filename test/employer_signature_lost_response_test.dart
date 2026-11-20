// [E2-EMPLOYER-SIG-LOST-RESPONSE] 사업주 서명 — 서버는 커밋했는데 응답을 못 받으면 앱이 실패로 말했다
//
// callableFinalizeEmployerSignature(DEV 00066)는 한 트랜잭션에서 계약 문서를 쓰고(신규면 set,
// 기존이면 pending_employer → pending_worker), 커밋 뒤 근로자 알림을 한 번 남긴다. 응답이
// 타임아웃·연결 끊김으로 사라지면 앱은 그 오류만 보고 "서명 저장 실패"를 띄웠다 — 계약서는
// 근로자에게 이미 가 있는데 관리자는 다시 누르고, 다시 누르면 already-exists·failed-precondition 이 났다.
//
// 고치는 방식: **불명확한 code 일 때만** 같은 계약 문서를 단건 get 으로 읽어(최대 2회)
//   같은 지원서·사업장·근로자 + 근로자 서명 대기/완료 + 사업주 서명 시각 +
//   employerSignatureHash == sha256(이번 서명 바이트) 가 모두 맞으면 성공으로 복구한다.
//   그 밖에는 원래 code 를 그대로 가진 SignatureOutcomeUnknown 을 던진다
//   (일괄 발송 경로는 code 로 '불명확'을 판정해 확정을 되돌리지 않는다 — 동작 불변).
//   명확한 거절은 읽지도 않고 그대로 실패다.
//
// 고정하는 것
//   ESL-1  커밋 후 응답 유실 → 성공(pendingWorker), 호출 1회(재발송 없음)
//   ESL-2  명확한 거절(permission-denied) → 그대로 실패, 원장 읽기 0
//   ESL-3  다른 지원서 / 다른 서명 해시 / 다른 contractId → 성공 금지(불명확)
//   ESL-4  원장 읽기 실패 → 불명확, 원래 code 유지, 재발송 없음
//   ESL-5  응답 유실 + 문서 없음 → 제한된 재조회 2회 뒤 불명확
//   ESL-6  정상 응답 → 원장 읽기 0 (기존 경로 불변)
//   ESL-7  서명 화면은 불명확이면 같은 화면에서 다시 보내지 못한다 (소스 앵커)
import 'dart:io';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:crypto/crypto.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'package:ALfit/models/core/contract_template_model.dart';
import 'package:ALfit/models/core/employment_contract_model.dart';
import 'package:ALfit/services/contract_service.dart';

class _FakeApp extends Fake
    with MockPlatformInterfaceMixin
    implements FirebaseAppPlatform {
  @override
  String get name => defaultFirebaseAppName;
  @override
  FirebaseOptions get options => const FirebaseOptions(
      apiKey: 'k', appId: 'a', messagingSenderId: 's', projectId: 'p');
}

class _FakeCore extends FirebasePlatform with MockPlatformInterfaceMixin {
  @override
  FirebaseAppPlatform app([String name = defaultFirebaseAppName]) => _FakeApp();
  @override
  Future<FirebaseAppPlatform> initializeApp({String? name, FirebaseOptions? options}) async => _FakeApp();
  @override
  List<FirebaseAppPlatform> get apps => [_FakeApp()];
}

ContractSnapshot _snapshot() => ContractSnapshot(
      businessName: '합성 사업장',
      businessNumber: '000-00-00000',
      businessAddress: '서울',
      ownerName: '사업주',
      workerName: '근로자',
      workType: '홀서빙',
      workPlace: '서울',
      isLongTerm: false,
      contractStart: '2026-10-20',
      contractEnd: '2026-10-20',
      workDays: const [],
      startTime: '10:00',
      endTime: '11:00',
      breakMinutes: 0,
      wage: 12000,
      wageType: 'hourly',
      paymentMethod: '계좌이체',
      wagePaymentDay: 10,
      taxDeductionType: 'none',
    );

/// 신규(아직 저장 전) 단기 계약 — 앱이 확정 직후 만드는 모양.
EmploymentContractModel _newContract({String id = 'ctNew'}) => EmploymentContractModel(
      id: id,
      applicationId: 'appZ',
      businessId: 'biz1',
      workerId: 'wk1',
      isLongTerm: false,
      toId: 'to1',
      workDetailId: 'wd1',
      status: ContractStatus.pendingEmployer,
      snapshot: _snapshot(),
      createdAt: DateTime(2026, 10, 17),
      isNewUnsaved: true,
    );

final Uint8List _sig = Uint8List.fromList(List<int>.generate(64, (i) => (i * 7) % 256));
final String _sigHash = sha256.convert(_sig).toString();

/// 서버(00066)가 커밋 때 남기는 계약 문서 모양.
Map<String, dynamic> _committedDoc({
  String applicationId = 'appZ',
  String businessId = 'biz1',
  String workerId = 'wk1',
  String status = 'pending_worker',
  String? hash,
}) =>
    {
      'applicationId': applicationId,
      'applicationIds': [applicationId],
      'businessId': businessId,
      'workerId': workerId,
      'status': status,
      'employerSignatureStoragePath': 'contracts/x/attempt/signature_employer.png',
      'employerSignatureHash': hash ?? _sigHash,
      'employerSignedAt': Timestamp.fromMillisecondsSinceEpoch(1760683320000),
    };

class _World {
  int calls = 0;
  int reads = 0;
  Object Function()? throwOnCall;
  Map<String, dynamic>? response;
  final Map<String, Map<String, dynamic>> docs = {};
  bool readThrows = false;

  Map<String, dynamic>? lastData;
  ContractService service() => ContractService(
        employerSignatureCall: (data) async {
          calls++;
          lastData = Map<String, dynamic>.from(data);
          final t = throwOnCall;
          if (t != null) throw t();
          return response;
        },
        contractDocReader: (id) async {
          reads++;
          if (readThrows) throw FirebaseException(plugin: 'cloud_firestore', code: 'unavailable');
          return docs[id];
        },
        employerSignatureRecheckDelay: Duration.zero,
      );
}

FirebaseFunctionsException _fx(String code) =>
    FirebaseFunctionsException(message: code.toUpperCase(), code: code);

void main() {
  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
  });

  test('ESL-0 클라이언트 해시 = 배포본이 커밋한 employerSignatureHash (같은 64바이트)', () {
    // 격리 에뮬레이터에서 DEV 00066(g096) 번들로 같은 바이트를 커밋해 읽은 값(10-19 LOCAL,
    //   scratchpad/miss/employer-sig-runtime.js). 서버는 Buffer.from(base64) 의 sha256 hex 를 쓴다.
    expect(_sigHash, 'd8bc63b4fc1156e5e7d95a418b9bf54cd3174bedbc2db40f74895349b229b3c0');
  });

  test('ESL-1 커밋 후 응답 유실 → 성공으로 복구, 호출 1회', () async {
    final w = _World()..throwOnCall = (() => _fx('deadline-exceeded'));
    w.docs['ctNew'] = _committedDoc(); // 서버는 커밋했다 (계약 1건 · 알림은 서버가 1회)
    final updated = await w.service().saveEmployerSignature(contract: _newContract(), signatureBytes: _sig);
    expect(updated.status, ContractStatus.pendingWorker);
    expect(updated.hasEmployerSignature, isTrue);
    expect(w.calls, 1, reason: '다시 보내지 않는다');
    expect(w.reads, 1);
  });

  test('ESL-1b unavailable(연결 끊김)도 같은 복구 — 근로자가 이미 서명해 completed 여도 같은 계약', () async {
    final w = _World()..throwOnCall = (() => _fx('unavailable'));
    w.docs['ctNew'] = _committedDoc(status: 'completed');
    final updated = await w.service().saveEmployerSignature(contract: _newContract(), signatureBytes: _sig);
    expect(updated.status, ContractStatus.pendingWorker);
    expect(w.calls, 1);
  });

  test('ESL-2 명확한 거절은 그대로 실패 — 원장을 읽지 않는다', () async {
    for (final code in ['permission-denied', 'failed-precondition', 'already-exists', 'invalid-argument', 'not-found']) {
      final w = _World()..throwOnCall = (() => _fx(code));
      w.docs['ctNew'] = _committedDoc(); // 있어도 보지 않는다
      await expectLater(
        w.service().saveEmployerSignature(contract: _newContract(), signatureBytes: _sig),
        throwsA(isA<FirebaseFunctionsException>()
            .having((e) => e.code, 'code', code)
            .having((e) => e is SignatureOutcomeUnknown, 'unknown 아님', isFalse)),
      );
      expect(w.reads, 0, reason: '$code 는 확인 대상이 아니다');
      expect(w.calls, 1);
    }
  });

  group('ESL-3 다른 계약을 성공으로 읽지 않는다', () {
    Future<SignatureOutcomeUnknown> run(void Function(_World) seed) async {
      final w = _World()..throwOnCall = (() => _fx('deadline-exceeded'));
      seed(w);
      try {
        await w.service().saveEmployerSignature(contract: _newContract(), signatureBytes: _sig);
      } on SignatureOutcomeUnknown catch (e) {
        expect(w.calls, 1);
        return e;
      }
      fail('성공으로 복구하면 안 된다');
    }

    test('다른 지원서', () async {
      final e = await run((w) => w.docs['ctNew'] = _committedDoc(applicationId: 'appOther'));
      expect(e.reason, 'mismatch');
      expect(e.code, 'deadline-exceeded');
    });
    test('다른 사업장·근로자', () async {
      expect((await run((w) => w.docs['ctNew'] = _committedDoc(businessId: 'biz2'))).reason, 'mismatch');
      expect((await run((w) => w.docs['ctNew'] = _committedDoc(workerId: 'wk2'))).reason, 'mismatch');
    });
    test('같은 계약이지만 다른 서명(다른 관리자가 먼저 서명)', () async {
      final e = await run((w) => w.docs['ctNew'] = _committedDoc(hash: sha256.convert([1, 2, 3]).toString()));
      expect(e.reason, 'mismatch');
    });
    test('다른 contractId 에만 커밋된 문서가 있다', () async {
      final e = await run((w) => w.docs['ctOther'] = _committedDoc());
      expect(e.reason, 'absent');
    });
  });

  test('ESL-4 원장 읽기 실패 → 불명확, 원래 code 유지, 재발송 없음', () async {
    final w = _World()
      ..throwOnCall = (() => _fx('deadline-exceeded'))
      ..readThrows = true;
    await expectLater(
      w.service().saveEmployerSignature(contract: _newContract(), signatureBytes: _sig),
      throwsA(isA<SignatureOutcomeUnknown>()
          .having((e) => e.reason, 'reason', 'readFailed')
          .having((e) => e.code, 'code', 'deadline-exceeded')
          .having((e) => e.message, 'message', contains('확인하지 못했습니다'))),
    );
    expect(w.calls, 1);
    expect(w.reads, 1);
  });

  test('ESL-5 응답 유실 + 문서 없음 → 제한된 재조회 2회 뒤 불명확(실패로 단정하지 않는다)', () async {
    final w = _World()..throwOnCall = (() => _fx('internal'));
    await expectLater(
      w.service().saveEmployerSignature(contract: _newContract(), signatureBytes: _sig),
      throwsA(isA<SignatureOutcomeUnknown>()
          .having((e) => e.reason, 'reason', 'absent')
          .having((e) => e.code, 'code', 'internal')),
    );
    expect(w.reads, 2);
    expect(w.calls, 1);
  });

  test('ESL-6 정상 응답 → 원장을 읽지 않는다', () async {
    final w = _World()
      ..response = {'success': true, 'employerSignatureStoragePath': 'contracts/x/a/signature_employer.png'};
    final updated = await w.service().saveEmployerSignature(contract: _newContract(), signatureBytes: _sig);
    expect(updated.status, ContractStatus.pendingWorker);
    expect(w.reads, 0);
    expect(w.calls, 1);
  });

  // [CONTRACT-DISPATCH.4 B1] 발송 화면은 날인 바이트를 보내지 않는다 — 서버가 owner 날인을 찍는다.
  //   그러면 앱은 저장될 해시를 모른다. 이번 시도의 요청 id 를 보내고, 서버가 그 id 를 계약에 남긴다.
  group('ESL-8 바이트 없이 보낼 때(서버 owner 날인)', () {
    test('ESL-8a 바이트를 싣지 않고 요청 id 를 싣는다', () async {
      final w = _World()..response = {'employerSignatureStoragePath': 'p'};
      await w.service().saveEmployerSignature(contract: _newContract());
      expect(w.lastData!.containsKey('signatureBase64'), isFalse);
      expect((w.lastData!['signRequestId'] as String).isNotEmpty, isTrue);
    });

    test('ESL-8b 응답 유실 + 이번 요청 id 가 저장됨 → 성공 복구, 재발송 없음', () async {
      final w = _World();
      // 서버는 이 요청을 커밋했다 — 받은 요청 id 를 그대로 남기고(해시는 owner 날인의 것이라 앱이 모른다)
      //   응답만 잃었다.
      w.throwOnCall = () {
        w.docs['ctNew'] = {
          ..._committedDoc(hash: 'owner-seal-hash-unknown-to-app'),
          'employerSignRequestId': w.lastData!['signRequestId'],
        };
        return _fx('deadline-exceeded');
      };
      final updated = await w.service().saveEmployerSignature(contract: _newContract());
      expect(updated.status, ContractStatus.pendingWorker);
      expect(w.calls, 1);
    });

    test('ESL-8c 응답 유실 + 다른 요청 id(다른 관리자가 먼저 서명) → 불명확', () async {
      final w = _World()..throwOnCall = (() => _fx('deadline-exceeded'));
      w.docs['ctNew'] = {
        ..._committedDoc(hash: 'owner-seal-hash'),
        'employerSignRequestId': 'someone-else',
      };
      await expectLater(w.service().saveEmployerSignature(contract: _newContract()),
          throwsA(isA<SignatureOutcomeUnknown>()));
      expect(w.calls, 1);
    });
  });

  test('ESL-7 서명 화면: 불명확이면 같은 화면에서 다시 보내지 못한다', () {
    final src = File('lib/screens/contract/contract_sign_screen.dart').readAsStringSync().replaceAll('\r\n', '\n');
    expect(src, contains('if (e is SignatureOutcomeUnknown && mounted) {'));
    expect(src, contains('setState(() => _signOutcomeUnknown = true);'));
    expect(src, contains('onPressed: (_agreed && !_isSigning && !_signOutcomeUnknown) ? _sign : null,'));
    // 문구는 FirebaseFunctionsException.message 경로로 그대로 보인다
    expect(src, contains('final msg = e is FirebaseFunctionsException'));
  });
}
