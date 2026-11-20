// [E2-WORKER-SIG-LOST-RESPONSE] 근로자 서명·PDF — 서버는 완료했는데 응답을 못 받으면 앱이 실패로 말했다
//
// callableFinalizeWorkerSignature(DEV 00081)는 서명·PDF 를 올린 뒤 한 트랜잭션에서 계약을
// completed 로 바꾸고 workerSignatureHash·pdfHash(각 바이트의 sha256 hex)·pdfStoragePath·
// workerSignedAt 을 쓴다. 응답이 사라지면 앱은 오류만 보고 실패를 띄웠고, 다시 누르면
// failed-precondition("이미 근무자 서명이 완료된 계약서")이 났다.
//
// 고치는 방식: 불명확한 code 일 때만 같은 계약 문서를 단건 get(근로자 본인 허용)으로 최대 2회
//   읽어, 같은 지원서·사업장·근로자 + completed + workerSignedAt + **서명 해시와 PDF 해시가
//   둘 다 이번 바이트와 같을 때만** 성공으로 복구한다. CF 재호출·파일 재업로드 없음.
//   그 밖에는 원래 code 를 가진 SignatureOutcomeUnknown. 명확한 거절은 읽지도 않는다.
//
// 고정하는 것
//   WSL-1  커밋 후 응답 유실 → completed 로 복구, 저장된 pdfStoragePath 사용, 호출 1회
//   WSL-2  명확한 거절 → 그대로 실패, 원장 읽기 0
//   WSL-3  다른 지원서·근로자·사업장 / 다른 서명 / 다른 PDF / 다른 contractId → 성공 금지
//   WSL-4  원장 읽기 실패 → 불명확(원래 code), 재호출 없음
//   WSL-5  문서 없음 · 아직 pending_worker → 제한된 재조회 2회 뒤 불명확
//   WSL-6  정상 응답 → 원장 읽기 0
//   WSL-7  서명 화면 공통 catch 가 근로자 경로도 잠근다 (소스 앵커)
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

/// 사업주 서명이 끝나 근로자 서명을 기다리는 계약 — 근로자 앱이 받는 모양.
EmploymentContractModel _pendingWorker() => EmploymentContractModel(
      id: 'ctW',
      applicationId: 'appZ',
      businessId: 'biz1',
      workerId: 'wk1',
      isLongTerm: false,
      toId: 'to1',
      workDetailId: 'wd1',
      status: ContractStatus.pendingWorker,
      snapshot: _snapshot(),
      createdAt: DateTime(2026, 10, 17),
      employerSignatureAvailable: true,
      employerSignedAt: DateTime(2026, 10, 17, 15, 42),
    );

final Uint8List _sig = Uint8List.fromList(List<int>.generate(64, (i) => (i * 7) % 256));
final Uint8List _pdf = Uint8List.fromList([...'%PDF-1.4\n'.codeUnits, ...List<int>.generate(200, (i) => (i * 13) % 256)]);
final String _sigHash = sha256.convert(_sig).toString();
final String _pdfHash = sha256.convert(_pdf).toString();

Map<String, dynamic> _completedDoc({
  String applicationId = 'appZ',
  String businessId = 'biz1',
  String workerId = 'wk1',
  String status = 'completed',
  String? sigHash,
  String? pdfHash,
  bool signedAt = true,
}) =>
    {
      'applicationId': applicationId,
      'applicationIds': [applicationId],
      'businessId': businessId,
      'workerId': workerId,
      'status': status,
      'workerSignatureStoragePath': 'contracts/ctW/attempts/x/signature_worker.png',
      'workerSignatureHash': sigHash ?? _sigHash,
      'pdfStoragePath': 'contracts/ctW/attempts/x/contract.pdf',
      'pdfHash': pdfHash ?? _pdfHash,
      if (signedAt) 'workerSignedAt': Timestamp.fromMillisecondsSinceEpoch(1760683860000),
    };

class _World {
  int calls = 0;
  int reads = 0;
  Object Function()? throwOnCall;
  Map<String, dynamic>? response;
  final Map<String, Map<String, dynamic>> docs = {};
  bool readThrows = false;

  ContractService service() => ContractService(
        workerSignatureCall: (data) async {
          calls++;
          final t = throwOnCall;
          if (t != null) throw t();
          return response;
        },
        employerSignatureCall: (data) async => fail('사업주 서명 경로를 부르면 안 된다'),
        contractDocReader: (id) async {
          reads++;
          if (readThrows) throw FirebaseException(plugin: 'cloud_firestore', code: 'unavailable');
          return docs[id];
        },
        employerSignatureRecheckDelay: Duration.zero,
      );

  Future<EmploymentContractModel> sign() =>
      service().saveWorkerSignature(contract: _pendingWorker(), signatureBytes: _sig, pdfBytes: _pdf);
}

FirebaseFunctionsException _fx(String code) =>
    FirebaseFunctionsException(message: code.toUpperCase(), code: code);

void main() {
  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
  });

  test('WSL-0 클라이언트 해시 = 배포본이 커밋한 workerSignatureHash·pdfHash (같은 바이트)', () {
    // 격리 에뮬레이터에서 DEV 00081(g037) 번들로 같은 바이트를 커밋해 읽은 값(10-19 LOCAL,
    //   scratchpad/miss/worker-sig-runtime.js). 서버는 Buffer.from(base64) 의 sha256 hex 를 쓴다.
    expect(_sigHash, 'd8bc63b4fc1156e5e7d95a418b9bf54cd3174bedbc2db40f74895349b229b3c0');
    expect(_pdfHash, 'a9fa413f3dfb602303e5ed97a05c4cd6724d681248ebe43abd9739aac759af3a');
  });

  test('WSL-1 커밋 후 응답 유실 → completed 로 복구, 저장된 경로, 호출 1회(재업로드 없음)', () async {
    for (final code in ['deadline-exceeded', 'unavailable']) {
      final w = _World()..throwOnCall = (() => _fx(code));
      w.docs['ctW'] = _completedDoc();
      final updated = await w.sign();
      expect(updated.status, ContractStatus.completed);
      expect(updated.pdfStoragePath, 'contracts/ctW/attempts/x/contract.pdf');
      expect(updated.hasWorkerSignature, isTrue);
      expect(w.calls, 1, reason: 'CF 를 다시 부르지 않는다($code)');
      expect(w.reads, 1);
    }
  });

  test('WSL-2 명확한 거절은 그대로 실패 — 원장을 읽지 않는다', () async {
    for (final code in ['permission-denied', 'failed-precondition', 'invalid-argument', 'not-found']) {
      final w = _World()..throwOnCall = (() => _fx(code));
      w.docs['ctW'] = _completedDoc();
      await expectLater(
        w.sign(),
        throwsA(isA<FirebaseFunctionsException>()
            .having((e) => e.code, 'code', code)
            .having((e) => e is SignatureOutcomeUnknown, 'unknown 아님', isFalse)),
      );
      expect(w.reads, 0, reason: code);
      expect(w.calls, 1);
    }
  });

  group('WSL-3 다른 계약·서명·PDF 를 성공으로 읽지 않는다', () {
    Future<SignatureOutcomeUnknown> run(Map<String, Map<String, dynamic>> docs) async {
      final w = _World()..throwOnCall = (() => _fx('deadline-exceeded'));
      w.docs.addAll(docs);
      try {
        await w.sign();
      } on SignatureOutcomeUnknown catch (e) {
        expect(w.calls, 1);
        expect(e.code, 'deadline-exceeded');
        return e;
      }
      fail('성공으로 복구하면 안 된다');
    }

    test('다른 지원서·근로자·사업장', () async {
      expect((await run({'ctW': _completedDoc(applicationId: 'appOther')})).reason, 'mismatch');
      expect((await run({'ctW': _completedDoc(workerId: 'wk2')})).reason, 'mismatch');
      expect((await run({'ctW': _completedDoc(businessId: 'biz2')})).reason, 'mismatch');
    });
    test('같은 계약이지만 다른 서명', () async {
      expect((await run({'ctW': _completedDoc(sigHash: sha256.convert([9]).toString())})).reason, 'mismatch');
    });
    test('같은 서명이지만 다른 PDF', () async {
      expect((await run({'ctW': _completedDoc(pdfHash: sha256.convert([8]).toString())})).reason, 'mismatch');
    });
    test('다른 contractId 에만 완료 문서가 있다', () async {
      expect((await run({'ctOther': _completedDoc()})).reason, 'absent');
    });
  });

  test('WSL-4 원장 읽기 실패 → 불명확, 원래 code, 재호출 없음', () async {
    final w = _World()
      ..throwOnCall = (() => _fx('unavailable'))
      ..readThrows = true;
    await expectLater(
      w.sign(),
      throwsA(isA<SignatureOutcomeUnknown>()
          .having((e) => e.reason, 'reason', 'readFailed')
          .having((e) => e.code, 'code', 'unavailable')
          .having((e) => e.message, 'message', contains('확인하지 못했습니다'))),
    );
    expect(w.calls, 1);
    expect(w.reads, 1);
  });

  test('WSL-5 문서 없음 · 아직 pending_worker → 재조회 2회 뒤 불명확', () async {
    for (final seed in <Map<String, Map<String, dynamic>>>[
      {},
      {'ctW': _completedDoc(status: 'pending_worker', signedAt: false)},
    ]) {
      final w = _World()..throwOnCall = (() => _fx('internal'));
      w.docs.addAll(seed);
      await expectLater(w.sign(),
          throwsA(isA<SignatureOutcomeUnknown>().having((e) => e.reason, 'reason', 'absent')));
      expect(w.reads, 2);
      expect(w.calls, 1);
    }
  });

  test('WSL-6 정상 응답 → 원장을 읽지 않는다', () async {
    final w = _World()
      ..response = {
        'success': true,
        'pdfStoragePath': 'contracts/ctW/attempts/y/contract.pdf',
        'workerSignatureStoragePath': 'contracts/ctW/attempts/y/signature_worker.png',
      };
    final updated = await w.sign();
    expect(updated.status, ContractStatus.completed);
    expect(updated.pdfStoragePath, 'contracts/ctW/attempts/y/contract.pdf');
    expect(w.reads, 0);
  });

  test('WSL-7 서명 화면: 공통 catch 가 근로자 경로의 불명확도 잠근다', () {
    final src = File('lib/screens/contract/contract_sign_screen.dart').readAsStringSync().replaceAll('\r\n', '\n');
    final perform = src.substring(src.indexOf('Future<void> _performSign('), src.indexOf('Widget build(BuildContext context)'));
    // 근로자 호출은 같은 try 안에 있고, catch 는 하나다.
    expect(perform.indexOf('_service.saveWorkerSignature('), lessThan(perform.indexOf('} catch (e) {')));
    expect(perform, contains('if (e is SignatureOutcomeUnknown && mounted) {'));
    expect(src, contains('onPressed: (_agreed && !_isSigning && !_signOutcomeUnknown) ? _sign : null,'));
  });
}
