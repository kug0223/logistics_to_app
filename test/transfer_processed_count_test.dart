// [SIM-XFER-COUNT] 이체 완료 처리 응답의 '처리 0건'을 성공으로 말하지 않는다.
//
// 근거: DEV 배포본 callableMarkTransferredBatch(rev 00084)를 격리 에뮬레이터에서
//   실행했을 때의 응답 모양(LOCAL, 2026-10-17):
//     스냅샷 없음 → HTTP 200 {success:true, processed:0, skipped:[id],
//                            blocked:{id:'reviewRequired'}, alreadyTransferred:[]}
//     정상        → {processed:1, skipped:[], blocked:{}}
//   이미 이체된 건은 skipped 가 아니라 alreadyTransferred 로 온다(같은 번들 코드).
//
// 결함(수정 전): 근로자 카드 경로(_markWorker)가 성공 건수를
//   `보낸 수 − skipped` 로 셌다. 이미 이체된 건은 skipped 가 아니어서
//   **아무것도 바뀌지 않았는데 "N건 이체 완료 처리되었습니다"** 가 떴다.
//
// 전체 화면은 띄우지 않는다 — 권한 게이트가 Firestore 를 직접 읽고 실패하면
//   pop 한다. 대신 실제 서비스가 같은 채널 응답을 해석한 결과를, 화면이 쓰는
//   판정 함수(workerTransferOutcome)에 그대로 넣는다. 목록 행은 처리 뒤 서버에서
//   다시 읽으므로(_refreshAfterMutation) 클라이언트가 행 상태를 추측하지 않는다.
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'package:ALfit/screens/business_admin/payroll/payroll_payment_dashboard_screen.dart';
import 'package:ALfit/services/payroll_payment_service.dart';
import 'package:ALfit/utils/transfer_export_plan.dart';

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

const _channel =
    'dev.flutter.pigeon.cloud_functions_platform_interface.CloudFunctionsHostApi.call';

/// 배포 함수의 응답 모양.
Map<String, Object?> _reply({
  int processed = 0,
  List<String> skipped = const [],
  Map<String, String> blocked = const {},
  List<String> already = const [],
}) =>
    {
      'success': true,
      'processed': processed,
      'alreadyTransferred': already,
      'skipped': skipped,
      'blocked': blocked,
      'blockedActors': {for (final k in blocked.keys) k: 'WORKER_OR_REVIEW'},
      'lockedBySettlement': <String>[],
    };

void _serve(Map<String, Object?> body, List<Map> calls) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMessageHandler(_channel, (message) async {
    final args = (const StandardMessageCodec().decodeMessage(message) as List)
        .first as Map;
    calls.add(args);
    return const StandardMessageCodec().encodeMessage(<Object?>[body]);
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
  });
  tearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMessageHandler(_channel, null));

  // Firebase 초기화 뒤에 만든다(생성자가 FirebaseFirestore.instance 를 잡는다).
  late final PayrollPaymentService svc = PayrollPaymentService();

  test('XC-0 DEV 6HB9 모양 — 단건 처리 0건·reviewRequired 는 예외로 올라온다(성공 아님)', () async {
    final calls = <Map>[];
    _serve(_reply(skipped: ['a1'], blocked: {'a1': 'reviewRequired'}), calls);
    Object? caught;
    try {
      await svc.markTransferred(attendanceId: 'a1', businessId: 'b');
    } catch (e) {
      caught = e;
    }
    expect(calls.single['functionName'], 'callableMarkTransferredBatch');
    expect(caught, isA<TransferBlockedException>());
    expect((caught as TransferBlockedException).code, 'reviewRequired');
    // 화면이 띄우는 안내의 재료 — 성공 문구가 아니다.
    expect(TransferBlockCode.labelOf('reviewRequired'), isNot(contains('완료')));
    expect(TransferBlockCode.actionOf('reviewRequired'), isNotEmpty);
  });

  test('XC-1 단건 정상 처리 → 1건 이체 완료', () async {
    _serve(_reply(processed: 1), []);
    final r = await svc.markTransferred(attendanceId: 'a1', businessId: 'b');
    final o = workerTransferOutcome(requested: 1, result: r);
    expect((o.processed, o.already), (1, 0));
  });

  test('XC-2 단건이 이미 이체됨 → 새 이체 0건, 이미 1건', () async {
    _serve(_reply(processed: 0, already: ['a1']), []);
    final r = await svc.markTransferred(attendanceId: 'a1', businessId: 'b');
    final o = workerTransferOutcome(requested: 1, result: r);
    expect(o.processed, 0, reason: '아무것도 바뀌지 않았는데 이체 완료라고 말하면 안 된다');
    expect(o.already, 1);
  });

  test('XC-3 여러 건 중 일부만 — 1건 처리·1건 제외·1건 이미 이체', () async {
    _serve(
        _reply(
            processed: 1,
            skipped: ['a2'],
            blocked: {'a2': 'reviewRequired'},
            already: ['a3']),
        []);
    final r = await svc.markTransferredBatch(
        attendanceIds: ['a1', 'a2', 'a3'], businessId: 'b');
    expect(r.transferredNow, 1);
    expect(r.allSkipped, ['a2']);
    expect(r.reasonCounts, {'reviewRequired': 1});
    final o = workerTransferOutcome(requested: 3, result: r);
    expect(o.processed, 1, reason: '서버가 이번에 바꾼 건수만 성공으로 말한다');
    expect(o.already, 1);
  });

  test('XC-4 여러 건 모두 제외 → 0건', () async {
    _serve(
        _reply(skipped: ['a1', 'a2'],
            blocked: {'a1': 'reviewRequired', 'a2': 'noAccountSnapshot'}),
        []);
    final r = await svc.markTransferredBatch(
        attendanceIds: ['a1', 'a2'], businessId: 'b');
    final o = workerTransferOutcome(requested: 2, result: r);
    expect((o.processed, o.already), (0, 0));
    expect(r.reasonCounts, {'reviewRequired': 1, 'noAccountSnapshot': 1});
  });
}
