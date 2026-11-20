// [CONFIRM-BATCH-CONTRACT] 일괄 확정+계약 발송 processOne 의 계약 단계 — Dart 경계.
//
// processOne 은 WorkApplicantsDialog 안의 클로저라 단독 실행할 수 없다. 그 뒤 단계가
// 부르는 production 서비스를 같은 인자로 실행해, 서버로 나가는 두 요청을 캡처한다:
//   ① callableGetContractsByBiz — 번들(pending_employer) 탐색
//   ② callableFinalizeEmployerSignature — 신규 계약 생성·사업주 서명(isNewUnsaved)
// 캡처한 ② payload 는 에뮬레이터 체인(배포 번들 g185 → g006 → g096)에 그대로 넣는다.
//   ALFIT_CAPTURE_OUT 이 있으면 그 경로에 JSON 으로 쓴다(값은 합성).
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'package:ALfit/models/core/application_model.dart';
import 'package:ALfit/models/core/business_model.dart';
import 'package:ALfit/models/core/contract_template_model.dart';
import 'package:ALfit/models/core/employment_contract_model.dart';
import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/models/core/work_detail_data.dart';
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
  Future<FirebaseAppPlatform> initializeApp(
          {String? name, FirebaseOptions? options}) async =>
      _FakeApp();
  @override
  List<FirebaseAppPlatform> get apps => [_FakeApp()];
}

const _callChannel =
    'dev.flutter.pigeon.cloud_functions_platform_interface.CloudFunctionsHostApi.call';

ApplicationModel _app() => ApplicationModel(
      id: 'APP', uid: 'W', toId: 'TO', slotId: 'S', wdId: 'wdA',
      workDetailId: 'QA_14:00_15:00',
      businessId: 'BIZ', businessName: '합성 사업장', toTitle: 't',
      selectedWorkType: 'QA', startTime: '14:00', endTime: '15:00',
      wage: 12000, wageType: 'hourly', status: 'CONTRACT_PENDING',
      workDate: DateTime.utc(2026, 10, 22, 15), appliedAt: DateTime(2026, 10, 19),
    );

BusinessModel _biz() => BusinessModel(
      id: 'BIZ', name: '합성 사업장', ownerId: 'OWNER', ownerName: '대표',
      businessNumber: '000-00-00000', address: '경기도 평택시 1',
      category: '물류', subCategory: '창고', isApproved: true,
      createdAt: DateTime(2025),
    );

WorkDetailData _wd() => WorkDetailData(
      wdId: 'wdA', workType: 'QA', startTime: '14:00', endTime: '15:00',
      requiredCount: 2, wage: 12000, wageType: 'hourly');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
  });

  test('CBC-1 번들 탐색은 pending_employer 1건을 묻고, 없으면 신규 계약을 isNewUnsaved 로 보낸다',
      () async {
    final calls = <Map<Object?, Object?>>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler(_callChannel, (data) async {
      final args = (const StandardMessageCodec().decodeMessage(data) as List)
          .first as Map;
      calls.add({
        'functionName': args['functionName'],
        'parameters': args['parameters'],
      });
      return const StandardMessageCodec().encodeMessage(<Object?>[
        <String, Object?>{'contracts': <Object?>[]}
      ]);
    });
    Map<String, dynamic>? sent;
    final svc = ContractService(employerSignatureCall: (data) async {
      sent = Map<String, dynamic>.from(data);
      return <String, Object?>{'employerSignatureStoragePath': 'contracts/x/signature_employer.png'};
    });
    final contract = await svc.findOrCreateContract(
      application: _app(),
      business: _biz(),
      worker: UserModel(uid: 'W', username: 'w', name: '합성 근로자',
          email: 'w@test.local', role: UserRole.USER),
      workDetail: _wd(),
      articles: const [ContractArticle(title: '제1조', content: '합성 조항')],
    );
    final seal = Uint8List.fromList(List<int>.generate(64, (i) => i));
    final saved = await svc.saveEmployerSignature(contract: contract, signatureBytes: seal);

    // ① 번들 탐색
    final bundle = calls.where((c) => c['functionName'] == 'callableGetContractsByBiz').toList();
    expect(bundle, hasLength(1));
    final bp = Map<Object?, Object?>.from(bundle.single['parameters'] as Map);
    expect(bp['status'], 'pending_employer');
    expect(bp['businessId'], 'BIZ');
    expect(bp['workerId'], 'W');
    // ② 신규 계약
    expect(sent, isNotNull);
    expect(sent!['isNewUnsaved'], isTrue);
    expect(sent!['contractId'], contract.id);
    final cd = Map<String, dynamic>.from(sent!['contractData'] as Map);
    expect(cd['applicationId'], 'APP');
    expect(cd['businessId'], 'BIZ');
    expect(cd['workerId'], 'W');
    expect(cd.containsKey('status'), isTrue, reason: '서버가 허용 목록으로 걸러낸다(CPP-2)');
    expect(saved.status, ContractStatus.pendingWorker);

    final out = Platform.environment['ALFIT_CAPTURE_OUT'];
    if (out != null && out.isNotEmpty) {
      File(out).writeAsStringSync(jsonEncode({
        'bundleQuery': bp.map((k, v) => MapEntry('$k', v)),
        'finalize': {
          ...sent!..remove('signatureBase64'),
          'signatureBase64Length': base64Encode(seal).length,
        },
      }, toEncodable: (o) => o is DateTime ? o.toIso8601String() : '$o'));
    }
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler(_callChannel, null);
  });
}
