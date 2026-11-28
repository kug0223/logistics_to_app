// [PERF impl_22 · 2026-11-27] 남은 클라 속도 셀 + 같은 파일 기능 결함 시험.
//
//   R  첫 공고 준비 저장소(Q31) — resolve 가 동기로 던져도 실패가 굳지 않는다 · 앞 scope 의 늦은 결과·정리가
//      새 scope 를 덮지/지우지 않는다 · reset 뒤 늦은 결과가 되살아나지 않는다
//   Q  공고 한도 요약(L32 Quota) — 20개씩 나눈 묶음을 제한 병렬로 · 입력 순서 합치기 · 실패 의미(입력 순서 첫 실패)
//   P  급여 지급 현황(L49 · 판정291 B8) — 처리 뒤 갱신 중에도 목록을 지우지 않고(전체 스피너 0) 누르기만 막는다
//   T  출근 기기 시간 확인(L38 · 판정291 B1) — 미리 받은 서버 시각 표본은 같은 계정·화면 수명·앱 이탈 없음·
//      monotonic 차이 5분 안일 때만 쓰고, 아니면 예전 서버 확인 그대로
// ignore_for_file: depend_on_referenced_packages
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ALfit/models/core/application_model.dart';
import 'package:ALfit/models/core/attendance_model.dart';
import 'package:ALfit/models/core/business_member_model.dart' show MemberPermissions;
import 'package:ALfit/models/core/business_model.dart';
import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/models/core/user_region.dart';
import 'package:ALfit/providers/notification_provider.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/screens/business_admin/payroll/payroll_payment_dashboard_screen.dart';
import 'package:ALfit/screens/user/attendance_check_reads.dart';
import 'package:ALfit/screens/user/attendance_check_screen.dart';
import 'package:ALfit/services/business_posting_readiness.dart';
import 'package:ALfit/services/posting_quota_summary.dart';
import 'package:ALfit/utils/format_helper.dart';

import 'support/checkin_contract_fixture.dart';
import 'support/visible_text.dart';

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

const _fnCh =
    'dev.flutter.pigeon.cloud_functions_platform_interface.CloudFunctionsHostApi.call';

FirstPostingReadiness _rd({bool businessReady = false}) => FirstPostingReadiness(
      hasAnyBusiness: true,
      businessReady: businessReady,
      workTypesReady: false,
      contractTemplateReady: false,
      sealReady: false,
    );

// ── P: 급여 지급 현황 ─────────────────────────────────────────────────────────
class _AdminP extends UserProvider {
  @override
  UserModel? get currentUser => UserModel(
      uid: 'OWNER', username: 'owner', name: '관리자',
      email: 'owner@test.local', role: UserRole.BUSINESS_ADMIN);
  @override
  bool get isBusinessAdmin => true;
  @override
  bool get isSubAdmin => false;
  @override
  bool can(bool Function(MemberPermissions p) check) => true;
  @override
  bool canForBusiness(String businessId, bool Function(MemberPermissions p) check) => true;
  @override
  PermissionCheck checkForBusiness(
          String businessId, bool Function(MemberPermissions p) check) =>
      PermissionCheck.allowed;
}

const _biz = 'BIZ';
Map<String, Object?> _ts(DateTime d) =>
    {'_seconds': d.millisecondsSinceEpoch ~/ 1000, '_nanoseconds': 0};

class _PayRec {
  _PayRec(this.id, this.uid, this.workDate, this.net);
  final String id, uid;
  final DateTime workDate;
  final int net;
  String wageStatus = 'confirmed';
  Map<String, Object?> wire() => {
        'id': id, 'userId': uid, 'businessId': _biz, 'businessName': 'QA 사업장',
        'workDate': _ts(workDate), 'workType': 'QA', 'status': 'present',
        'wageStatus': wageStatus, 'adminConfirmed': true,
        'createdAt': _ts(workDate), 'paymentDueDate': _ts(DateTime.now()),
        'wageDetail': {'totalAmount': net, 'wageType': 'daily'},
        'wageAccountSourceBankAccountVersion': 1,
        'wageAccountSourceBankbookDocumentVersion': 1,
      };
}

/// 시간은 [_advance] 가 10ms 씩 민다. 월 조회는 [monthDelay] 뒤 **도착 시각의** 데이터로 답한다.
class _PaySrv {
  _PaySrv(this.recs);
  final List<_PayRec> recs;
  int monthDelay = 300;
  final calls = <String>[];

  Future<ByteData?> handle(ByteData? data) async {
    final args = (const StandardMessageCodec().decodeMessage(data) as List).first as Map;
    final fn = args['functionName'] as String;
    final p = Map<Object?, Object?>.from(args['parameters'] as Map? ?? const {});
    calls.add(fn);
    Object? body;
    switch (fn) {
      case 'callableGetAdminAttendances':
        await Future<void>.delayed(Duration(milliseconds: monthDelay));
        final s = p['startMs'] as int, e = p['endMs'] as int;
        final ws = p['wageStatus'] as String?;
        body = {
          'items': [
            for (final r in recs)
              if (r.workDate.millisecondsSinceEpoch >= s &&
                  r.workDate.millisecondsSinceEpoch < e &&
                  (ws == null || r.wageStatus == ws))
                r.wire()
          ],
          'limitReached': false,
        };
      case 'callableGetPayrollReadinessBatch':
        await Future<void>.delayed(const Duration(milliseconds: 100));
        body = {
          'readiness': {
            for (final u in (p['workerUids'] as List).cast<String>())
              u: {'ready': true, 'state': 'READY_AUTO', 'actor': 'NONE',
                  'accountVersion': 1, 'bankbookVersion': 1},
          },
          'failed': <String>[],
        };
      case 'callableGetUsersBatch':
        await Future<void>.delayed(const Duration(milliseconds: 100));
        body = {
          'users': {
            for (final u in (p['uids'] as List).cast<String>())
              u: {'name': 'N$u', 'username': u, 'role': 'USER'}
          }
        };
      case 'callableMarkTransferredBatch':
        await Future<void>.delayed(const Duration(milliseconds: 100));
        final ids = (p['attendanceIds'] as List).cast<String>();
        for (final r in recs) {
          if (ids.contains(r.id)) r.wageStatus = 'transferred';
        }
        body = {
          'processed': ids.length,
          'skipped': <String>[], 'alreadyTransferred': <String>[], 'blocked': {},
        };
      default:
        await Future<void>.delayed(const Duration(milliseconds: 100));
        body = {'requests': <Object?>[], 'items': <Object?>[]};
    }
    return const StandardMessageCodec().encodeMessage(<Object?>[body]);
  }
}

Future<void> _advance(WidgetTester t, int ms) async {
  for (var e = 0; e < ms; e += 10) {
    await t.pump(const Duration(milliseconds: 10));
  }
}

// ── T: 출근 ───────────────────────────────────────────────────────────────────
class _WorkerP extends UserProvider {
  @override
  UserModel? get currentUser => UserModel(
        uid: 'u1', username: 'u1', name: '김근로', email: 'u1@alfit.local',
        role: UserRole.USER,
        homeRegion: const UserRegion(province: '경기도', city: '평택시'),
        accountStatus: 'active',
      );
  @override
  bool get isSubAdmin => false;
  @override
  bool get isBusinessAdmin => false;
  @override
  bool get isSuperAdmin => false;
  @override
  bool get isAdminMode => false;
  @override
  bool get permissionsLoaded => true;
}

DateTime _kst(int y, int mo, int d, [int h = 0, int mi = 0]) =>
    DateTime.utc(y, mo, d, h, mi).subtract(const Duration(hours: 9));

ApplicationModel _work() => ApplicationModel(
      id: 'app1', toId: 'to1', uid: 'u1', businessId: 'biz1',
      businessName: 'QA 사업장', toTitle: '당일 QA', status: AppStatus.confirmed,
      selectedWorkType: 'QA 분류', startTime: '20:00', endTime: '21:00', wage: 12000,
      workDate: _kst(2026, 10, 17).toLocal(),
      appliedAt: _kst(2026, 10, 17, 17, 57).toLocal(),
    );

/// 출근 화면 한 판 — 서버 시각 표본(미리 받기)·누를 때 서버 확인(getServerTime) 횟수를 센다.
class _TimeRig {
  int sampleCalls = 0;
  int freshCalls = 0;
  DateTime now = _kst(2026, 10, 17, 19, 45).toLocal();
  final business = Completer<BusinessModel?>(); // 끝나지 않는 사업장 읽기 — 시간 확인 다음 단계에서 멈춘다
  int businessReads = 0;

  Future<ByteData?> fn(ByteData? data) async {
    final args = (const StandardMessageCodec().decodeMessage(data) as List).first as Map;
    final f = args['functionName'] as String;
    if (f == 'getServerTime') {
      freshCalls++;
      return const StandardMessageCodec().encodeMessage(<Object?>[
        {'serverTimeMs': DateTime.now().millisecondsSinceEpoch}
      ]);
    }
    return const StandardMessageCodec().encodeMessage(<Object?>['internal', 'mock', null]);
  }

  Future<void> mount(WidgetTester t,
      {Future<int?> Function()? sample, bool checkedIn = false, bool seam = true}) async {
    final apps = [_work()];
    t.binding.defaultBinaryMessenger.setMockMessageHandler(_fnCh, fn);
    addTearDown(() => t.binding.defaultBinaryMessenger.setMockMessageHandler(_fnCh, null));
    final reads = AttendanceCheckReads(
      myApplications: (uid) async => apps,
      myContracts: (uid) async => completedContractsFor(apps),
      todayAttendance: ({required String userId, required String applicationId}) async =>
          checkedIn
              ? AttendanceModel.fromMap({
                  'userId': 'u1', 'applicationId': 'app1', 'businessId': 'biz1',
                  'workDate': Timestamp.fromDate(_kst(2026, 10, 17)),
                  'createdAt': Timestamp.fromDate(_kst(2026, 10, 17, 19, 50)),
                  'checkIn': Timestamp.fromDate(_kst(2026, 10, 17, 19, 50)),
                  'status': 'present', 'workType': 'QA',
                }, 'att1')
              : null,
      businessById: (id) {
        businessReads++;
        return business.future;
      },
      serverTimeMs: !seam
          ? null
          : () {
              sampleCalls++;
              return (sample ?? () async => now.millisecondsSinceEpoch)();
            },
    );
    t.view.physicalSize = const Size(390, 2200);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    await t.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<UserProvider>(create: (_) => _WorkerP()),
        ChangeNotifierProvider<NotificationProvider>(create: (_) => NotificationProvider()),
      ],
      child: MaterialApp(home: AttendanceCheckScreen(reads: reads, clock: () => now)),
    ));
    for (var i = 0; i < 20; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> tapCheckIn(WidgetTester t) async {
    final btn = find.text('출근하기');
    expect(btn, findsOneWidget);
    await t.tap(btn);
    for (var i = 0; i < 20; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
  }
}

Future<void> _leaveAndReturn(WidgetTester t) async {
  for (final s in [
    AppLifecycleState.inactive,
    AppLifecycleState.hidden,
    AppLifecycleState.paused,
    AppLifecycleState.hidden,
    AppLifecycleState.inactive,
    AppLifecycleState.resumed,
  ]) {
    t.binding.handleAppLifecycleStateChanged(s);
    await t.pump();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
    await initializeDateFormatting('ko_KR', null);
  });

  group('R 첫 공고 준비 저장소(Q31)', () {
    setUp(FirstPostingReadinessStore.reset);
    tearDown(FirstPostingReadinessStore.reset);

    test('R1 resolve 가 동기로 던져도 실패가 굳지 않는다 — 같은 scope 의 다음 요청은 다시 센다', () async {
      var calls = 0;
      Future<FirstPostingReadiness> boom() {
        calls++;
        throw StateError('sync'); // async 가 아닌 함수가 바로 던진다
      }

      await FirstPostingReadinessStore.ensureLoaded(uid: 'u', scopeKey: 'A', resolve: boom);
      expect(FirstPostingReadinessStore.current.value.status, FirstPostingReadinessStatus.failed);
      await FirstPostingReadinessStore.ensureLoaded(
          uid: 'u', scopeKey: 'A', resolve: () async {
        calls++;
        return _rd(businessReady: true);
      });
      expect(calls, 2, reason: '끝난 future 에 합류해 다시 세지 않았다(실패가 굳음)');
      expect(FirstPostingReadinessStore.current.value.isResolved, isTrue);
    });

    test('R2 앞 scope 의 늦은 결과·정리가 새 scope 를 덮거나 진행 중 세기를 지우지 않는다', () async {
      final a = Completer<FirstPostingReadiness>();
      final b = Completer<FirstPostingReadiness>();
      var bCalls = 0;
      final fa = FirstPostingReadinessStore.ensureLoaded(
          uid: 'u', scopeKey: 'A', resolve: () => a.future);
      final fb = FirstPostingReadinessStore.ensureLoaded(
          uid: 'u', scopeKey: 'B', resolve: () {
        bCalls++;
        return b.future;
      });
      a.complete(_rd(businessReady: true)); // 앞 scope 가 늦게 끝난다
      await fa;
      final snap = FirstPostingReadinessStore.current.value;
      expect(snap.scopeKey, 'B', reason: '앞 scope 결과가 새 scope 판정을 덮었다');
      expect(snap.status, FirstPostingReadinessStatus.loading);
      // 같은 B 를 또 물으면 진행 중 세기에 합류해야 한다(앞 scope 정리가 _inFlight 를 지웠다면 한 번 더 센다).
      final fb2 = FirstPostingReadinessStore.ensureLoaded(
          uid: 'u', scopeKey: 'B', resolve: () {
        bCalls++;
        return b.future;
      });
      expect(bCalls, 1, reason: '앞 scope 의 정리가 새 scope 의 진행 중 세기를 지웠다');
      b.complete(_rd());
      await Future.wait([fb, fb2]);
      expect(FirstPostingReadinessStore.current.value.scopeKey, 'B');
      expect(FirstPostingReadinessStore.current.value.isResolved, isTrue);
    });

    test('R3 reset(로그아웃 등) 뒤 늦게 끝난 세기는 값을 되살리지 않는다', () async {
      final a = Completer<FirstPostingReadiness>();
      final fa = FirstPostingReadinessStore.ensureLoaded(
          uid: 'u', scopeKey: 'A', resolve: () => a.future);
      FirstPostingReadinessStore.reset();
      a.complete(_rd(businessReady: true));
      await fa;
      expect(FirstPostingReadinessStore.current.value.status, FirstPostingReadinessStatus.idle);
    });
  });

  group('Q 공고 한도 요약(L32 Quota 제한 병렬)', () {
    Map<String, Object?> resp(List<String> ids, {String token = 't', int used = 1}) => {
          'scopes': [
            {'scopeToken': token, 'businessIds': ids, 'used': used, 'limit': 4, 'remaining': 4 - used}
          ],
          'denied': <String>[],
          'failed': <String>[],
        };
    setUp(() {
      PostingQuotaStore.reset();
      PostingQuotaStore.fetchCount = 0;
      PostingQuotaStore.maxConcurrentChunks = 3;
    });

    test('Q1 45곳 = 3묶음 — 첫 응답 전에 세 묶음이 모두 출발 · 같은 범위는 하나로(사용량 합산 0)', () async {
      final ids = [for (var i = 0; i < 45; i++) 'b${i.toString().padLeft(2, '0')}'];
      final pending = <Completer<Object?>>[];
      final asked = <List<String>>[];
      PostingQuotaStore.fetch = (chunk) {
        asked.add(chunk);
        final c = Completer<Object?>();
        pending.add(c);
        return c.future;
      };
      final f = PostingQuotaStore.ensure(uid: 'u', businessIds: ids);
      await Future<void>.delayed(Duration.zero);
      expect(asked.length, 3, reason: '묶음을 하나씩 차례로 묻는다(병렬 아님)');
      // 역순으로 답한다 — 합치기는 입력 순서다.
      for (var i = pending.length - 1; i >= 0; i--) {
        pending[i].complete(resp(asked[i]));
      }
      await f;
      final v = PostingQuotaStore.current.value;
      expect(v.status, PostingQuotaStatus.loaded);
      expect(v.value!.scopes.single.businessIds.length, 45);
      expect(v.value!.scopes.single.used, 1, reason: '같은 범위의 사용량을 더했다');
      expect(PostingQuotaStore.fetchCount, 3);
    });

    test('Q2 동시 묶음 수 상한 — 5묶음이어도 동시에 3개까지', () async {
      final ids = [for (var i = 0; i < 100; i++) 'b$i'];
      var inFlight = 0, peak = 0;
      PostingQuotaStore.fetch = (chunk) async {
        inFlight++;
        if (inFlight > peak) peak = inFlight;
        await Future<void>.delayed(const Duration(milliseconds: 5));
        inFlight--;
        return resp(chunk);
      };
      await PostingQuotaStore.ensure(uid: 'u', businessIds: ids);
      expect(PostingQuotaStore.current.value.status, PostingQuotaStatus.loaded);
      expect(PostingQuotaStore.fetchCount, 5);
      expect(peak, 3);
    });

    test('Q3 실패 의미 = 입력 순서 첫 실패 — 앞 묶음 확인 불가 + 뒤 묶음 권한 거절 → 확인 불가(예전 차례 읽기와 같다)', () async {
      final ids = [for (var i = 0; i < 25; i++) 'b$i'];
      PostingQuotaStore.fetch = (chunk) async {
        if (chunk.first == 'b0') {
          await Future<void>.delayed(const Duration(milliseconds: 20)); // 늦게 실패
          throw StateError('network');
        }
        throw FirebaseFunctionsException(message: 'no', code: 'permission-denied');
      };
      await PostingQuotaStore.ensure(uid: 'u', businessIds: ids);
      expect(PostingQuotaStore.current.value.status, PostingQuotaStatus.failed);
      expect(PostingQuotaStore.current.value.value, isNull, reason: '성공한 묶음만으로 숫자를 만들었다');

      PostingQuotaStore.reset();
      PostingQuotaStore.fetch = (chunk) async {
        if (chunk.first == 'b0') return resp(chunk);
        throw FirebaseFunctionsException(message: 'no', code: 'permission-denied');
      };
      await PostingQuotaStore.ensure(uid: 'u', businessIds: ids);
      expect(PostingQuotaStore.current.value.status, PostingQuotaStatus.denied);
    });
  });

  group('P 급여 지급 현황(L49 · 처리 뒤 목록 유지)', () {
    testWidgets('P1 이체 처리 뒤 갱신 중 — 전체 스피너 0 · 목록 유지 · 얇은 진행 표시 · 누르기 잠금 → 새 목록이 앉으면 풀림',
        (t) async {
      final kst = DateTime.now().toUtc().add(const Duration(hours: 9));
      final day = DateTime(kst.year, kst.month, 10);
      final s = _PaySrv([_PayRec('p-a', 'pA', day, 10000), _PayRec('p-b', 'pB', day, 20000)]);
      t.view.physicalSize = const Size(1080, 4000);
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.reset);
      t.binding.defaultBinaryMessenger.setMockMessageHandler(_fnCh, s.handle);
      addTearDown(() => t.binding.defaultBinaryMessenger.setMockMessageHandler(_fnCh, null));
      await t.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<UserProvider>(create: (_) => _AdminP()),
          ChangeNotifierProvider<NotificationProvider>(create: (_) => NotificationProvider()),
        ],
        child: MaterialApp(
          home: PayrollPaymentDashboardScreen(
              businessId: _biz, businessName: 'QA 사업장', year: kst.year, month: kst.month),
        ),
      ));
      await _advance(t, 2500);
      expect(findVisibleText('이체처리'), findsNWidgets(2));

      // 2만 원 카드 이체 처리
      final cards = find.ancestor(
          of: findVisibleText('이체처리'),
          matching: find.byWidgetPredicate((w) => w.runtimeType.toString() == '_WorkerPayCard'));
      final target = cards.evaluate().where((e) => find
          .descendant(of: find.byWidget(e.widget), matching: findVisibleText(FormatHelper.formatWage(20000)))
          .evaluate()
          .isNotEmpty);
      await t.tap(find.descendant(
          of: find.byWidget(target.single.widget), matching: findVisibleText('이체처리')));
      await _advance(t, 300);
      await t.tap(findVisibleText('이체 완료 처리').last);
      await _advance(t, 300);
      s.monthDelay = 1500; // 처리 뒤 월 조회를 느리게 — 갱신 중 화면을 본다
      await t.tap(findVisibleText('건너뛰기'));
      await _advance(t, 400); // 처리 호출(100ms) 끝 → 처리 뒤 갱신 시작
      expect(s.calls.where((c) => c == 'callableMarkTransferredBatch').length, 1);

      expect(find.text('급여 현황 불러오는 중...'), findsNothing,
          reason: '처리 뒤 갱신이 목록을 지우고 전체 스피너를 띄웠다');
      expect(find.byKey(const ValueKey('payroll-refresh-after-mutation')), findsOneWidget,
          reason: '갱신 중 진행 표시가 없다');
      expect(findVisibleText('이체처리'), findsWidgets, reason: '갱신 중 목록이 사라졌다');
      // 잠금 — 처리 전 목록으로 다시 쓰지 않는다(확인 창이 열리지 않는다).
      await t.tap(findVisibleText('이체처리').first, warnIfMissed: false);
      await _advance(t, 300);
      expect(findVisibleText('이체 완료 처리'), findsNothing, reason: '갱신 중 처리 전 목록으로 다시 쓸 수 있다');

      await _advance(t, 3000); // 처리 뒤 월 조회가 앉는다
      expect(find.byKey(const ValueKey('payroll-refresh-after-mutation')), findsNothing);
      expect(findVisibleText('이체처리'), findsOneWidget, reason: '서버 결과(이체완료 1)가 앉은 새 목록');
      expect(s.calls.where((c) => c == 'callableMarkTransferredBatch').length, 1);
    });
  });

  group('T 출근 기기 시간 확인(L38)', () {
    testWidgets('T1 미리 받은 표본이 조건을 맞으면 누를 때 getServerTime 왕복 0', (t) async {
      final r = _TimeRig();
      await r.mount(t);
      expect(r.sampleCalls, 1, reason: '출근할 근무가 있으면 목록을 읽으며 한 번 미리 받는다');
      await r.tapCheckIn(t);
      expect(r.freshCalls, 0, reason: '조건을 맞는 표본이 있는데 누를 때 서버 시각을 또 물었다');
      expect(r.sampleCalls, 1);
      expect(findVisibleTextContaining('기기 시간이 실제 시간과 크게 다릅니다'), findsNothing);
      expect(r.businessReads, greaterThanOrEqualTo(1), reason: '시간 확인 다음 단계(사업장)로 가지 않았다');
    });

    testWidgets('T2 미리 받기 경계가 없으면(시험 대역) 예전처럼 누를 때 확인 1회', (t) async {
      final r = _TimeRig();
      await r.mount(t, seam: false);
      await r.tapCheckIn(t);
      expect(r.freshCalls, 1);
    });

    testWidgets('T3 앱을 떠났다 돌아오면 표본을 버린다 → 누를 때 확인 1회', (t) async {
      final r = _TimeRig();
      await r.mount(t);
      await _leaveAndReturn(t);
      await r.tapCheckIn(t);
      expect(r.freshCalls, 1, reason: '앱 이탈 뒤에도 옛 표본을 썼다');
    });

    testWidgets('T4 표본 뒤 기기 시계가 10분 바뀌면(monotonic 대조 실패) 누를 때 확인 1회', (t) async {
      final r = _TimeRig();
      await r.mount(t);
      r.now = r.now.add(const Duration(minutes: 10));
      await r.tapCheckIn(t);
      expect(r.freshCalls, 1, reason: '시계가 바뀌었는데 옛 표본으로 정상 판정했다');
    });

    testWidgets('T5 표본 실패(null)는 정상 근거가 아니다 → 누를 때 확인 1회', (t) async {
      final r = _TimeRig();
      await r.mount(t, sample: () async => null);
      await r.tapCheckIn(t);
      expect(r.freshCalls, 1);
    });

    testWidgets('T6 출근할 근무가 없으면(이미 출근) 미리 묻지 않는다', (t) async {
      final r = _TimeRig();
      await r.mount(t, checkedIn: true);
      expect(r.sampleCalls, 0);
    });

    testWidgets('T7 받는 중에 누르면 같은 요청을 기다린다(중복 0)', (t) async {
      final r = _TimeRig();
      final slow = Completer<int?>();
      await r.mount(t, sample: () => slow.future);
      final btn = find.text('출근하기');
      await t.tap(btn);
      await t.pump(const Duration(milliseconds: 100));
      expect(r.freshCalls, 0);
      slow.complete(r.now.millisecondsSinceEpoch);
      for (var i = 0; i < 10; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
      expect(r.sampleCalls, 1);
      expect(r.freshCalls, 0, reason: '받는 중인 표본을 기다리지 않고 따로 물었다');
    });
  });
}
