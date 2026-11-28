// ignore_for_file: depend_on_referenced_packages
// [impl_32 · 2026-11-27] 급여 일괄 이체(callableMarkTransferredBatch) 200건 청크와 근로자 알림 분배.
//
//   결함(고치기 전 · l60_spec.md §5): 앱이 200건씩 나눠 부르면서 **알림 전체**를 첫 청크(성공할 때까지)에만 실었다.
//   서버(index.ts callableMarkTransferredBatch)는
//     ① 알림이 200개를 넘으면 거래 전에 invalid-argument 로 거절하고
//     ② 알림을 **그 호출에서 실제 처리한** attendanceId 로만 거른다.
//   그래서 (a) 선택 > 200(알림 = 근태마다 1개라 > 200) → 모든 청크가 같은 거절 → 이체 0건,
//         (b) 알림이 일부만 있어도 둘째 청크 이후 근태의 알림은 첫 청크 호출에서 걸러져 발송 0.
//   수리: 청크마다 **그 청크 근태의 알림만** 싣는다(문구·수신자·필드 그대로 · 서버 계약 변경 0).
//
//   이 시험은 실제 PayrollPaymentService 를 쓰고 Functions 플랫폼 채널만 가짜로 바꾼다.
//   가짜 서버는 위 ①② 를 index.ts 와 같은 규칙으로 흉내 낸다(처리 = 청크 전부 성공).
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'package:ALfit/services/payroll_payment_service.dart';

class _FakeApp extends Fake with MockPlatformInterfaceMixin implements FirebaseAppPlatform {
  @override
  String get name => defaultFirebaseAppName;
  @override
  FirebaseOptions get options => const FirebaseOptions(apiKey: 'k', appId: 'a', messagingSenderId: 's', projectId: 'p');
}

class _FakeCore extends FirebasePlatform with MockPlatformInterfaceMixin {
  @override
  FirebaseAppPlatform app([String name = defaultFirebaseAppName]) => _FakeApp();
  @override
  Future<FirebaseAppPlatform> initializeApp({String? name, FirebaseOptions? options}) async => _FakeApp();
  @override
  List<FirebaseAppPlatform> get apps => [_FakeApp()];
}

const _channel = 'dev.flutter.pigeon.cloud_functions_platform_interface.CloudFunctionsHostApi.call';

/// 가짜 서버 — index.ts 의 두 규칙(알림 > 200 거절 · 처리한 id 로 알림 거름).
class _Server {
  final calls = <({List<String> ids, List<Map> notifs})>[];
  final delivered = <String>[]; // 실제로 '발송'된 알림의 attendanceId(서버 거름 뒤)
  final transferred = <String>{};
  int rejected = 0;

  void serve() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMessageHandler(_channel, (message) async {
      const c = StandardMessageCodec();
      final args = (c.decodeMessage(message) as List).first as Map;
      final p = args['parameters'] as Map;
      final ids = (p['attendanceIds'] as List).cast<String>();
      final notifs = ((p['notifications'] as List?) ?? const []).cast<Map>();
      calls.add((ids: ids, notifs: notifs));
      if (ids.length > 200) {
        rejected++;
        return c.encodeMessage(<Object?>['invalid-argument', 'x', {'code': 'invalid-argument', 'message': '최대 200건까지 처리 가능합니다.'}]);
      }
      if (notifs.length > 200) {
        rejected++;
        return c.encodeMessage(<Object?>['invalid-argument', 'x', {'code': 'invalid-argument', 'message': '알림은 최대 200개까지 전송할 수 있습니다.'}]);
      }
      final processed = ids.toSet();
      transferred.addAll(processed);
      for (final n in notifs) {
        final aid = n['attendanceId'] as String?;
        if (aid == null || processed.contains(aid)) delivered.add(aid ?? '(no-id)');
      }
      return c.encodeMessage(<Object?>[<String, Object?>{
        'success': true, 'processed': processed.length, 'alreadyTransferred': <String>[], 'skipped': <String>[],
        'blocked': <String, String>{}, 'lockedBySettlement': <String>[],
      }]);
    });
  }
}

List<String> _ids(int n) => [for (var i = 0; i < n; i++) 'att${i.toString().padLeft(4, '0')}'];

List<TransferNotificationInfo> _infos(Iterable<String> ids) => [
      for (final id in ids)
        TransferNotificationInfo(
          workerUserId: 'u_$id', workerName: '근로자$id', businessName: '강남 물류센터', businessId: 'b1',
          finalWage: 100000, attendanceId: id, applicationId: 'app_$id'),
    ];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
  });
  tearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMessageHandler(_channel, null));
  late final PayrollPaymentService svc = PayrollPaymentService();

  test('TC-1 450건 선택(알림 450) — 청크 3개 모두 처리 · 알림은 청크마다 그 청크 근태만 · 450건 모두 발송', () async {
    final s = _Server()..serve();
    final ids = _ids(450);
    final r = await svc.markTransferredBatch(attendanceIds: ids, businessId: 'b1', notificationInfos: _infos(ids));
    expect(s.rejected, 0, reason: '고치기 전: 알림 450개를 실은 청크가 매번 거절 → 이체 0건(PartialBatchException)');
    expect(s.calls.map((c) => c.ids.length), [200, 200, 50]);
    for (final c in s.calls) {
      expect(c.notifs.length, c.ids.length);
      expect(c.notifs.every((n) => c.ids.contains(n['attendanceId'])), isTrue, reason: '다른 청크 근태의 알림을 싣지 않는다');
    }
    expect(r.transferredNow, 450);
    expect(s.delivered.toSet(), ids.toSet(), reason: '모든 근태의 알림이 그 근태를 처리한 호출에서 발송된다');
    expect(s.delivered.length, 450, reason: '중복 발송 0');
  });

  test('TC-2 250건 · 알림은 그중 180건만(청크 경계에 걸침) — 둘째 청크 근태의 알림도 발송된다', () async {
    final s = _Server()..serve();
    final ids = _ids(250);
    final withInfo = [...ids.take(130), ...ids.skip(200).take(50)]; // 첫 청크 130 + 둘째 청크 50
    await svc.markTransferredBatch(attendanceIds: ids, businessId: 'b1', notificationInfos: _infos(withInfo));
    expect(s.rejected, 0);
    expect(s.calls.map((c) => c.notifs.length), [130, 50], reason: '고치기 전: [180, 0] — 둘째 청크 알림 50개가 첫 호출에서 걸러져 사라졌다');
    expect(s.delivered.toSet(), withInfo.toSet());
  });

  test('TC-3 알림 문구 재료(수신자·이름·사업장·금액·applicationId) 는 예전과 같은 키·값', () async {
    final s = _Server()..serve();
    await svc.markTransferredBatch(attendanceIds: ['att0001'], businessId: 'b1', notificationInfos: _infos(['att0001']));
    expect(Map<String, Object?>.from(s.calls.single.notifs.single), {
      'userId': 'u_att0001', 'workerName': '근로자att0001', 'businessName': '강남 물류센터', 'businessId': 'b1',
      'finalWage': 100000, 'attendanceId': 'att0001', 'applicationId': 'app_att0001',
    });
  });

  test('TC-4 청크 하나가 실패하면 그 청크의 알림은 실리지 않은 채 끝나고(허위 알림 0), 다른 청크는 자기 알림을 보낸다', () async {
    final s = _Server();
    var n = 0;
    final delivered = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMessageHandler(_channel, (message) async {
      const c = StandardMessageCodec();
      final p = ((c.decodeMessage(message) as List).first as Map)['parameters'] as Map;
      final ids = (p['attendanceIds'] as List).cast<String>();
      final notifs = ((p['notifications'] as List?) ?? const []).cast<Map>();
      s.calls.add((ids: ids, notifs: notifs));
      n++;
      if (n == 1 || notifs.length > 200) {
        return c.encodeMessage(<Object?>['unavailable', 'x', {'code': 'unavailable', 'message': '일시 오류'}]);
      }
      for (final m in notifs) {
        if (ids.contains(m['attendanceId'])) delivered.add(m['attendanceId'] as String);
      }
      return c.encodeMessage(<Object?>[<String, Object?>{
        'success': true, 'processed': ids.length, 'alreadyTransferred': <String>[], 'skipped': <String>[],
        'blocked': <String, String>{}, 'lockedBySettlement': <String>[],
      }]);
    });
    final ids = _ids(300);
    Object? caught;
    try {
      await svc.markTransferredBatch(attendanceIds: ids, businessId: 'b1', notificationInfos: _infos(ids));
    } catch (e) {
      caught = e;
    }
    expect(caught, isA<PartialBatchException>());
    expect((caught as PartialBatchException).confirmedProcessedCount, 100);
    expect(delivered.toSet(), ids.skip(200).toSet(), reason: '실패한 첫 청크의 근태에는 알림 0 · 둘째 청크 100건만');
    expect(s.calls[1].notifs.length, 100, reason: '고치기 전: 첫 청크 실패 → 둘째 청크가 알림 300개 전체를 실었다(서버 거절 > 200)');
  });

  test('TC-5 알림 목록 순서가 근태 순서와 달라도 청크마다 정확히 그 청크 근태의 알림', () async {
    final s = _Server()..serve();
    final ids = _ids(450);
    await svc.markTransferredBatch(attendanceIds: ids, businessId: 'b1', notificationInfos: _infos(ids.reversed));
    expect(s.rejected, 0);
    for (final c in s.calls) {
      expect(c.notifs.map((n) => n['attendanceId']).toSet(), c.ids.toSet());
    }
    expect(s.delivered.length, 450);
  });
}
