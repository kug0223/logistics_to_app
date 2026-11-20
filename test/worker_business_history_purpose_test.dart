import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'package:ALfit/services/firestore_service.dart';

/// [HISTORY-CLOSEOUT.30] 확정 근로자 상세 '우리 사업장 이력'.
///   서버(callableGetApplicationsByBiz)는 purpose 가 필수다(R7-P1-2.3). 확정자 화면이 purpose 없이 불러
///   invalid-argument 로 거절됐고, 서비스가 실패를 '0건'으로 바꿔 '이력 없음'으로 보였다.
///   서버 권한·관계 판정은 그대로다 — 앱은 허용 목록의 workerOperation 을 보내고, 실패를 0건과 구분한다.
Map<String, dynamic> _app(String uid, String id, {String status = 'CONFIRMED', int day = 20}) => {
      'id': id,
      'uid': uid,
      'toId': 'to1',
      'businessId': 'b1',
      'selectedWorkType': '분류',
      'status': status,
      'workDate': Timestamp.fromDate(DateTime(2026, 10, day)),
      'appliedAt': Timestamp.fromDate(DateTime(2026, 10, 1)),
      'startTime': '09:00',
      'endTime': '18:00',
    };

class _FakeApp extends Fake with MockPlatformInterfaceMixin implements FirebaseAppPlatform {
  @override
  String get name => defaultFirebaseAppName;
  @override
  FirebaseOptions get options =>
      const FirebaseOptions(apiKey: 'k', appId: 'a', messagingSenderId: 's', projectId: 'p');
}

class _FakeCore extends FirebasePlatform with MockPlatformInterfaceMixin {
  @override
  FirebaseAppPlatform app([String name = defaultFirebaseAppName]) => _FakeApp();
  @override
  Future<FirebaseAppPlatform> initializeApp({String? name, FirebaseOptions? options}) async => _FakeApp();
  @override
  List<FirebaseAppPlatform> get apps => [_FakeApp()];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
  });
  late List<Map<String, dynamic>> appsCalls;
  tearDown(() {
    FirestoreService.debugWorkHistoryAppsReader = null;
    FirestoreService.debugWorkHistoryReviewsReader = null;
  });
  setUp(() {
    appsCalls = [];
    FirestoreService.debugWorkHistoryReviewsReader = (_) async => {'items': <Map>[]};
  });

  test('BH-1 확정자 목적(workerOperation)과 대상 uid·사업장으로 부른다 — 이력 1건', () async {
    FirestoreService.debugWorkHistoryAppsReader = (p) async {
      appsCalls.add(p);
      return [_app('w1', 'a1')];
    };
    final h = await FirestoreService().getBusinessWorkHistory(
        userId: 'w1', businessId: 'b1', purpose: FirestoreService.purposeWorkerOperation);
    expect(appsCalls.single, {'businessId': 'b1', 'uid': 'w1', 'purpose': 'workerOperation'});
    expect(h['error'], isNull);
    expect(h['workCount'], 1);
    expect(h['lastWorkType'], '분류');
    expect(h['lastWorkDate'], isA<DateTime>());
  });

  test('BH-2 이력 없음은 error 없이 0건', () async {
    FirestoreService.debugWorkHistoryAppsReader = (_) async => [];
    final h = await FirestoreService().getBusinessWorkHistory(
        userId: 'w1', businessId: 'b1', purpose: FirestoreService.purposeWorkerOperation);
    expect(h['error'], isNull);
    expect(h['workCount'], 0);
  });

  test('BH-3 권한 없음·다른 사업장(서버 permission-denied)은 denied — 0건으로 숨기지 않는다', () async {
    FirestoreService.debugWorkHistoryAppsReader =
        (_) async => throw FirebaseFunctionsException(code: 'permission-denied', message: 'x');
    final h = await FirestoreService().getBusinessWorkHistory(
        userId: 'w1', businessId: 'other', purpose: FirestoreService.purposeWorkerOperation);
    expect(h['error'], 'denied');
  });

  test('BH-4 요청 실패(목적 누락 invalid-argument·네트워크)는 failed', () async {
    FirestoreService.debugWorkHistoryAppsReader =
        (_) async => throw FirebaseFunctionsException(code: 'invalid-argument', message: 'purpose');
    expect((await FirestoreService().getBusinessWorkHistory(userId: 'w1', businessId: 'b1'))['error'], 'failed');
    FirestoreService.debugWorkHistoryAppsReader = (_) async => throw StateError('network');
    expect((await FirestoreService().getBusinessWorkHistory(
            userId: 'w1', businessId: 'b1', purpose: FirestoreService.purposeWorkerOperation))['error'],
        'failed');
  });

  test('BH-5 근로자를 바꾸는 중 늦게 온 앞 응답이 뒤 근로자 결과에 섞이지 않는다(uid 범위)', () async {
    final slow = Completer<List<Map<String, dynamic>>>();
    FirestoreService.debugWorkHistoryAppsReader = (p) {
      appsCalls.add(p);
      return p['uid'] == 'wA' ? slow.future : Future.value([_app('wB', 'b1'), _app('wB', 'b2', day: 21)]);
    };
    final a = FirestoreService().getBusinessWorkHistory(
        userId: 'wA', businessId: 'b1', purpose: FirestoreService.purposeWorkerOperation);
    final b = await FirestoreService().getBusinessWorkHistory(
        userId: 'wB', businessId: 'b1', purpose: FirestoreService.purposeWorkerOperation);
    slow.complete([_app('wA', 'x1')]);
    final ra = await a;
    expect(b['workCount'], 2, reason: '뒤 근로자는 자기 이력만');
    expect(ra['workCount'], 1);
    expect(appsCalls.map((p) => p['uid']), ['wA', 'wB']);
    // 화면은 근로자마다 새 다이얼로그 State 이고, 늦은 응답은 mounted 확인 뒤에만 반영한다(BH-6).
  });

  test('BH-6 상세 화면 계약 — 확정자는 workerOperation, 실패·거부·없음을 따로 말한다, 키 이름 일치', () {
    final src = File('lib/widgets/dialogs/worker_detail_dialog.dart').readAsStringSync();
    expect(src.contains('? FirestoreService.purposeWorkerOperation'), isTrue);
    expect(src.contains("purpose: widget.isConfirmed ? null"), isFalse, reason: '목적 누락 회귀');
    expect(src.contains("_businessHistory?['error'] == 'denied'"), isTrue);
    expect(src.contains("_businessHistory?['error'] == 'failed'"), isTrue);
    expect(src.contains("'근무 이력을 볼 권한이 없어요"), isTrue);
    expect(src.contains("_businessHistory!['lastWork']"), isFalse, reason: '서비스는 lastWorkDate 를 돌려준다');
    expect(src.contains("_businessHistory!['avgRating']"), isFalse, reason: '서비스는 averageRating 을 돌려준다');
    expect(src.contains('if (!mounted) return;'), isTrue);
  });
}
