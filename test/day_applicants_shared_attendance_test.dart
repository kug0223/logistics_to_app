// [ADMIN-APPLICANTS-POSTCONFIRM] 지원자 다이얼로그의 근무 이력(hasWorked)·노쇼(noShow) 두 읽기가
// 같은 날의 GetAdminAttendances 를 따로 두 번 불렀다(확정 뒤 재조회마다 포함).
// 운영 읽기 경계(DayApplicantsReads.of)가 **진행 중** 요청 하나를 공유하는지, 결과·실패 의미가
// 그대로인지, 끝난 결과를 다음 로드에 다시 쓰지 않는지 본다.
import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'package:ALfit/screens/business_admin/dialogs/day_applicants_reads.dart';
import 'package:ALfit/services/firestore_service.dart';

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

const _ch =
    'dev.flutter.pigeon.cloud_functions_platform_interface.CloudFunctionsHostApi.call';
Map<String, Object?> _ts(DateTime d) =>
    {'_seconds': d.millisecondsSinceEpoch ~/ 1000, '_nanoseconds': 0};

final _day = DateTime.utc(2026, 10, 19, 15); // KST 10/20 자정

Map<String, Object?> _att(String id, String uid, String appId, String status, {bool checkedIn = false}) => {
      'id': id, 'userId': uid, 'applicationId': appId, 'businessId': 'biz1',
      'businessName': 'b', 'workDate': _ts(_day), 'workType': 'QA', 'status': status,
      'wageStatus': 'pending', 'adminConfirmed': false, 'createdAt': _ts(_day),
      if (checkedIn) 'checkIn': _ts(_day.add(const Duration(hours: 10))),
    };

class _Srv {
  int calls = 0;
  bool fail = false;
  bool limit = false;
  /// [STATUS-DIALOG-READS.27] callableGetApplicationsByBiz — 받은 인자(purpose)를 남긴다.
  final List<Object?> appPurposes = [];
  Future<ByteData?> handle(ByteData? data) async {
    final args = (const StandardMessageCodec().decodeMessage(data) as List).first as Map;
    if (args['functionName'] == 'callableGetApplicationsByBiz') {
      appPurposes.add((args['parameters'] as Map?)?['purpose']);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      return const StandardMessageCodec().encodeMessage(<Object?>[
        <String, Object?>{
          'applications': [
            {'id': 'p1', 'uid': 'w1', 'businessId': 'biz1', 'toId': 'to1', 'status': 'PENDING',
              'workDate': _ts(_day), 'appliedAt': _ts(_day), 'selectedWorkType': 'QA'},
            {'id': 'i1', 'uid': 'w2', 'businessId': 'biz1', 'toId': 'to1', 'status': 'INVITED',
              'workDate': _ts(_day), 'appliedAt': _ts(_day), 'invitedAt': _ts(_day), 'selectedWorkType': 'QA'},
          ],
          'hasMore': false,
        }
      ]);
    }
    if (args['functionName'] != 'callableGetAdminAttendances') {
      return const StandardMessageCodec().encodeMessage(<Object?>['unavailable', 'mock', null]);
    }
    calls++;
    await Future<void>.delayed(const Duration(milliseconds: 100));
    if (fail) {
      return const StandardMessageCodec().encodeMessage(<Object?>['unavailable', 'mock', null]);
    }
    return const StandardMessageCodec().encodeMessage(<Object?>[
      <String, Object?>{
        'items': [
          _att('t1', 'w1', 'a1', 'present', checkedIn: true),
          _att('t2', 'w2', 'a2', 'NO_SHOW'),
        ],
        'limitReached': limit,
      }
    ]);
  }
}

Future<void> _pump(WidgetTester t, [int ms = 300]) async {
  for (var e = 0; e < ms; e += 50) {
    await t.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
  });

  _Srv install(WidgetTester t) {
    final s = _Srv();
    t.binding.defaultBinaryMessenger.setMockMessageHandler(_ch, s.handle);
    addTearDown(() => t.binding.defaultBinaryMessenger.setMockMessageHandler(_ch, null));
    return s;
  }

  testWidgets('DSA-1 같은 로드의 hasWorked·noShow → 서버 1회, 판정은 그대로', (t) async {
    final s = install(t);
    final r = DayApplicantsReads.of(FirestoreService());
    final hw = r.hasWorkedMap(businessId: 'biz1', date: _day);
    final ns = r.noShowApplicationIds(businessId: 'biz1', date: _day);
    await _pump(t);
    expect(await hw, {'w1': true});
    expect(await ns, {'a2'});
    expect(s.calls, 1);
  });

  testWidgets('DSA-2 실패는 둘 다 실패다(빈 값으로 바꾸지 않는다), 서버 1회', (t) async {
    final s = install(t)..fail = true;
    final r = DayApplicantsReads.of(FirestoreService());
    Object? e1, e2;
    final hw = r.hasWorkedMap(businessId: 'biz1', date: _day).then((v) => v, onError: (Object e) { e1 = e; return <String, bool>{}; });
    final ns = r.noShowApplicationIds(businessId: 'biz1', date: _day).then((v) => v, onError: (Object e) { e2 = e; return <String>{}; });
    await _pump(t);
    await Future.wait([hw, ns]);
    expect(e1, isNotNull);
    expect(e2, isNotNull);
    expect(s.calls, 1);
  });

  testWidgets('DSA-3 끝난 결과는 다음 로드(확정 뒤 재조회)에 쓰지 않는다 — 새로 읽는다', (t) async {
    final s = install(t);
    final r = DayApplicantsReads.of(FirestoreService());
    final a = r.hasWorkedMap(businessId: 'biz1', date: _day);
    await _pump(t);
    await a;
    final b = r.noShowApplicationIds(businessId: 'biz1', date: _day);
    await _pump(t);
    await b;
    expect(s.calls, 2);
  });

  testWidgets('DSA-4 다른 날짜·다른 사업장은 공유하지 않는다', (t) async {
    final s = install(t);
    final r = DayApplicantsReads.of(FirestoreService());
    final a = r.hasWorkedMap(businessId: 'biz1', date: _day);
    final b = r.noShowApplicationIds(businessId: 'biz1', date: _day.add(const Duration(days: 1)));
    final c = r.noShowApplicationIds(businessId: 'biz2', date: _day);
    await _pump(t);
    await Future.wait([a, b, c]);
    expect(s.calls, 3);
  });

  // ── [STATUS-DIALOG-READS.27] 계약 판정 근태도 같은 응답을 쓴다 · 상한 판정은 그대로 ──
  testWidgets('DSA-5 hasWorked·noShow·계약 판정 근태 → 서버 1회', (t) async {
    final s = install(t);
    final r = DayApplicantsReads.of(FirestoreService());
    final hw = r.hasWorkedMap(businessId: 'biz1', date: _day);
    final ns = r.noShowApplicationIds(businessId: 'biz1', date: _day);
    final ca = r.contractAttendances!(businessId: 'biz1', date: _day);
    await _pump(t);
    expect(await hw, {'w1': true});
    expect(await ns, {'a2'});
    expect((await ca).map((a) => a.id).toSet(), {'t1', 't2'});
    expect(s.calls, 1);
  });

  testWidgets('DSA-6 상한 도달 — 계약 판정은 던지고(모름), 근무 이력·노쇼는 예전처럼 값을 준다', (t) async {
    final s = install(t)..limit = true;
    final r = DayApplicantsReads.of(FirestoreService());
    final hw = r.hasWorkedMap(businessId: 'biz1', date: _day);
    Object? err;
    final ca = r.contractAttendances!(businessId: 'biz1', date: _day)
        .then((v) => v, onError: (Object e) { err = e; return <Never>[]; });
    await _pump(t);
    await ca;
    expect(err, isA<StateError>());
    expect(await hw, {'w1': true});
    expect(s.calls, 1);
  });

  testWidgets('DSA-7 대기 지원자(applicantReview)·초대 현황 → 같은 요청 1회, 각자 거른다', (t) async {
    final s = install(t);
    final r = DayApplicantsReads.of(FirestoreService());
    final p = r.pendingApplications(date: _day, businessId: 'biz1',
        purpose: FirestoreService.purposeApplicantReview);
    final i = r.dayInvitations(date: _day, businessId: 'biz1');
    await _pump(t);
    expect((await p).map((a) => a.id), ['p1']);
    expect((await i).map((a) => a.id), ['i1']);
    expect(s.appPurposes, [FirestoreService.purposeApplicantReview]);
  });

  testWidgets('DSA-8 다른 purpose 의 대기 지원자는 공유하지 않는다', (t) async {
    final s = install(t);
    final r = DayApplicantsReads.of(FirestoreService());
    final p = r.pendingApplications(date: _day, businessId: 'biz1');
    final i = r.dayInvitations(date: _day, businessId: 'biz1');
    await _pump(t);
    await Future.wait([p, i]);
    expect(s.appPurposes.length, 2);
  });
}
