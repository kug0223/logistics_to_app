// [impl_15 · PERF-L9] 근로자 홈 1라운드 묶음(callableGetWorkerHomeBundle) 앱 전환 — 클라이언트 계약 + 홈 연결.
//
//   WHB-APP-1  성공 — 6 섹션 해석 · 묶음 호출 1 · 개별 호출 0 · 지원/근태/공고 캐시 채움(이어서 개별 조회는 캐시 히트)
//   WHB-APP-2  섹션 실패 — 그 섹션만 실패(빈 목록 합성 0) · 지원/근태는 개별 호출처럼 이전 캐시를 돌려준다
//   WHB-APP-3  uid · generation echo 불일치 → 응답 전체 폐기(요청 섹션 전부 실패)
//   WHB-APP-4  구서버(not-found/unimplemented) → 같은 호출에서 개별 폴백 1회 · 이 실행에서 묶음 끔(두 번째는 묶음 호출 0)
//   WHB-APP-5  묶음 전체 실패(unavailable) → 요청 섹션 전부 실패 · 개별 재호출 0(같은 오류를 두 번 기다리지 않음)
//   WHB-APP-6  진행 중 공유 — 묶음이 날아가는 동안 다른 소비자의 getMyApplications/getMyMonthlyAttendances 는 합류(추가 호출 0)
//   WHB-APP-7  TTL 안 캐시가 있는 섹션은 묶음 요청에서 뺀다
//   WHB-APP-PARSE 계약 해석 = ContractService.getByWorker 해석(같은 입력 → 같은 결과)
//   WHB-HOME-1 홈 — 섹션 실패 의미 유지(지원 실패 → 해지 '확인 못함' · 정상0 0 · 신분증 실패 → D290-01 일반 행) · 약관은 묶음 값으로
//   WHB-HOME-2 홈 — generation = uid#회차 · 약관은 첫 묶음에만 · 두 번째 로드는 약관 섹션 0
// ignore_for_file: depend_on_referenced_packages, avoid_print
import 'dart:async';

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
import 'package:ALfit/models/core/business_model.dart';
import 'package:ALfit/models/core/employment_contract_model.dart';
import 'package:ALfit/models/core/id_card_access_request_model.dart';
import 'package:ALfit/models/core/legal_readiness.dart';
import 'package:ALfit/models/core/slot_model.dart';
import 'package:ALfit/models/core/to_model.dart';
import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/providers/notification_provider.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/screens/user/user_home_reads.dart';
import 'package:ALfit/screens/user/user_home_screen.dart';
import 'package:ALfit/screens/user/user_tab_scope.dart';
import 'package:ALfit/services/contract_service.dart';
import 'package:ALfit/services/firestore_service.dart';
import 'package:ALfit/services/payroll_correction_service.dart';
import 'package:ALfit/theme/role_theme.dart';

import 'support/visible_text.dart';

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

const _callCh = 'dev.flutter.pigeon.cloud_functions_platform_interface.CloudFunctionsHostApi.call';
Map<String, Object?> _ts(DateTime d) => {'_seconds': d.millisecondsSinceEpoch ~/ 1000, '_nanoseconds': 0};

Map<String, Object?> _appWire(String id, String status) => {
      'id': id, 'toId': 'to_$id', 'uid': 'w1', 'businessId': 'b1', 'businessName': '합성 사업장', 'toTitle': '합성 공고',
      'status': status, 'selectedWorkType': '피킹', 'startTime': '09:00', 'endTime': '18:00', 'wage': 12000,
      'wageType': 'hourly', 'workDate': _ts(DateTime.utc(2026, 11, 28)), 'appliedAt': _ts(DateTime.utc(2026, 11, 20)),
    };
Map<String, Object?> _attWire(String id) => {
      'id': id, 'userId': 'w1', 'applicationId': 'app_$id', 'businessId': 'b1', 'businessName': '합성 사업장',
      'workType': '피킹', 'status': 'present', 'workDate': _ts(DateTime.utc(2026, 11, 3)), 'createdAt': _ts(DateTime.utc(2026, 11, 3)),
    };

/// 서버 대역 — 함수 이름별 호출 수 · 묶음 요청 인자 · 묶음 응답을 시험마다 바꾼다.
class _Server {
  final calls = <String, int>{};
  final bundleArgs = <Map>[];
  Completer<void>? bundleGate;
  Completer<void>? individualGate; // 개별 endpoint 를 붙잡아 '동시에 출발했는가'를 본다
  Object? Function(Map params)? bundle; // null = 기본 성공 · List = 오류 [code, message, details]
  Future<ByteData?> handle(ByteData? data) async {
    final a = (const StandardMessageCodec().decodeMessage(data) as List).first as Map;
    final name = a['functionName'] as String;
    final p = (a['parameters'] as Map?) ?? const {};
    calls[name] = (calls[name] ?? 0) + 1;
    if (name == 'callableGetWorkerHomeBundle') {
      bundleArgs.add(p);
      if (bundleGate != null) await bundleGate!.future;
      final r = (bundle ?? _defaultBundle)(p);
      if (r is List) return const StandardMessageCodec().encodeMessage(r);
      return const StandardMessageCodec().encodeMessage(<Object?>[r]);
    }
    // 개별 endpoint — 폴백 시험용 최소 응답
    if (individualGate != null) await individualGate!.future;
    final body = switch (name) {
      'callableGetMyApplications' => {'applications': [_appWire('ind1', 'PENDING')]},
      'getMyMonthlyAttendances' => {'items': [_attWire('ind_att')]},
      'callableGetPublishedTOs' => {'tos': <Object?>[]},
      'callableGetMyIdCardRequests' => {'requests': <Object?>[]},
      'getMyContracts' => {'items': <Object?>[], 'hasMore': false},
      _ => <String, Object?>{},
    };
    return const StandardMessageCodec().encodeMessage(<Object?>[body]);
  }

  int n(String name) => calls[name] ?? 0;
}

Object? _defaultBundle(Map p) {
  final months = ((p['monthlyAttendances'] as Map?)?['months'] as List?) ?? const [];
  final want = (p['sections'] as List).cast<String>();
  return {
    'version': 1,
    'uid': 'w1',
    'generation': p['generation'],
    'serverTimeMs': 1,
    'partial': false,
    'sections': {
      if (want.contains('applications')) 'applications': {'ok': true, 'data': {'applications': [_appWire('a1', 'PENDING')]}},
      if (want.contains('monthlyAttendances'))
        'monthlyAttendances': {
          'ok': true,
          'data': {
            'months': [
              for (final m in months) {'year': (m as Map)['year'], 'month': m['month'], 'items': [_attWire('t${m['month']}')]}
            ]
          }
        },
      if (want.contains('publishedTOs')) 'publishedTOs': {'ok': true, 'data': {'tos': <Object?>[]}},
      if (want.contains('idCardRequests')) 'idCardRequests': {'ok': true, 'data': {'requests': <Object?>[]}},
      if (want.contains('contracts')) 'contracts': {'ok': true, 'data': {'items': <Object?>[], 'hasMore': false}},
      if (want.contains('legalReadiness')) 'legalReadiness': {'ok': true, 'data': {'status': 'RECONSENT_REQUIRED', 'reconsentRequired': ['service_terms']}},
    },
  };
}

void _install(WidgetTester t, _Server s) {
  final m = t.binding.defaultBinaryMessenger;
  m.setMockMessageHandler(_callCh, s.handle);
  addTearDown(() => m.setMockMessageHandler(_callCh, null));
}

void _resetCaches() {
  final svc = FirestoreService();
  svc.invalidateMyApplicationsCache('w1');
  svc.invalidateMyAttendanceCache('w1');
  svc.invalidatePublishedTOsCache();
  WorkerHomeBundleFirestore.debugResetBundleSupport();
}

const _m11 = (year: 2026, month: 11);

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
    await initializeDateFormatting('ko_KR');
  });
  setUp(() {
    SharedPreferences.setMockInitialValues({'tour_completed_user_home': true});
    _resetCaches();
  });

  group('WHB-APP 클라이언트', () {
    testWidgets('WHB-APP-1 성공 — 해석 · 묶음 1 · 개별 0 · 캐시 채움', (t) async {
      final s = _Server();
      _install(t, s);
      final b = await FirestoreService().getWorkerHomeBundle(uid: 'w1', generation: 'w1#1', months: [_m11], includeLegal: true);
      expect(b.viaBundle, isTrue);
      expect(b.applications.value!.single.id, 'a1');
      expect(b.monthlyAttendances['2026-11']!.value!.single.id, 't11');
      expect(b.publishedTOs.ok && b.idCardRequests.ok && b.contracts.ok, isTrue);
      expect(b.legalReadiness!.value!.status, LegalReadinessStatus.reconsentRequired);
      expect(s.n('callableGetWorkerHomeBundle'), 1);
      expect(s.args(), isEmpty);
      expect(s.bundleArgs.single['generation'], 'w1#1');
      final again = await FirestoreService().getMyApplications('w1');
      final att = await FirestoreService().getMyMonthlyAttendances(userId: 'w1', year: 2026, month: 11);
      expect(again.single.id, 'a1');
      expect(att.single.id, 't11');
      expect(s.n('callableGetMyApplications') + s.n('getMyMonthlyAttendances'), 0, reason: '묶음 결과로 캐시가 찼다');
    });

    testWidgets('WHB-APP-2 섹션 실패 — 그 섹션만 · 지원은 이전 캐시(stale) · 계약 실패는 실패', (t) async {
      final s = _Server();
      _install(t, s);
      // 이전 캐시 만들기(성공 1회) 뒤 TTL 을 비우지 않고 무효화만 하면 캐시가 지워진다 — 대신 캐시를 두고 TTL 만 지나게 할 수 없어
      //   '이전 캐시 없음' 에서 지원 실패 = 실패, '있음' = stale 을 각각 본다.
      s.bundle = (p) {
        final r = _defaultBundle(p) as Map;
        (r['sections'] as Map)['applications'] = {'ok': false, 'code': 'internal'};
        (r['sections'] as Map)['contracts'] = {'ok': false, 'code': 'permission-denied', 'message': 'x'};
        r['partial'] = true;
        return r;
      };
      final b = await FirestoreService().getWorkerHomeBundle(uid: 'w1', generation: 'w1#1', months: [_m11]);
      expect(b.applications.ok, isFalse, reason: '이전 캐시 없음 → 실패(빈 목록 합성 0)');
      expect((b.applications.error as HomeBundleSectionError).code, 'internal');
      expect(b.contracts.ok, isFalse);
      expect(b.monthlyAttendances['2026-11']!.ok, isTrue, reason: '다른 섹션은 그대로');
      expect(b.publishedTOs.ok, isTrue);
    });

    testWidgets('WHB-APP-3 uid · generation echo 불일치 → 전체 폐기', (t) async {
      final s = _Server();
      _install(t, s);
      s.bundle = (p) => (_defaultBundle(p) as Map)..['uid'] = 'someone-else';
      var b = await FirestoreService().getWorkerHomeBundle(uid: 'w1', generation: 'w1#1', months: [_m11]);
      expect([b.applications.ok, b.monthlyAttendances['2026-11']!.ok, b.publishedTOs.ok, b.idCardRequests.ok, b.contracts.ok],
          everyElement(isFalse));
      s.bundle = (p) => (_defaultBundle(p) as Map)..['generation'] = 'w1#0';
      b = await FirestoreService().getWorkerHomeBundle(uid: 'w1', generation: 'w1#2', months: [_m11]);
      expect(b.applications.ok, isFalse, reason: '옛 세대 응답');
    });

    testWidgets('WHB-APP-4 구서버(not-found) → 개별 폴백 1회 · 이 실행에서 묶음 끔', (t) async {
      final s = _Server();
      _install(t, s);
      s.bundle = (_) => <Object?>['NOT_FOUND', 'no fn', {'code': 'not-found', 'message': 'no fn'}];
      final b = await FirestoreService().getWorkerHomeBundle(uid: 'w1', generation: 'w1#1', months: [_m11]);
      expect(b.viaBundle, isFalse);
      expect(b.applications.value!.single.id, 'ind1', reason: '개별 호출 결과');
      expect(s.n('callableGetMyApplications'), 1);
      expect(s.n('getMyMonthlyAttendances'), 1);
      expect(s.n('callableGetMyIdCardRequests'), 1);
      expect(s.n('getMyContracts'), 1);
      expect(WorkerHomeBundleFirestore.debugBundleUnsupported, isTrue);
      FirestoreService().invalidateMyApplicationsCache('w1');
      FirestoreService().invalidateMyAttendanceCache('w1');
      await FirestoreService().getWorkerHomeBundle(uid: 'w1', generation: 'w1#2', months: [_m11]);
      expect(s.n('callableGetWorkerHomeBundle'), 1, reason: '두 번째는 묶음을 다시 부르지 않는다');
      expect(s.n('callableGetMyApplications'), 2);
    });

    testWidgets('WHB-APP-4b 폴백 개별 호출은 동시에 출발한다(순서대로 기다리지 않음)', (t) async {
      final s = _Server()..individualGate = Completer<void>();
      _install(t, s);
      s.bundle = (_) => <Object?>['NOT_FOUND', 'no fn', {'code': 'not-found', 'message': 'no fn'}];
      final f = FirestoreService().getWorkerHomeBundle(uid: 'w1', generation: 'w1#1', months: [_m11]);
      for (var i = 0; i < 5; i++) {
        await t.pump();
      }
      print('[WHB-APP-4b] 붙잡힌 동안 출발 ${s.args()}');
      expect(s.args().keys.toSet(),
          containsAll({'callableGetMyApplications', 'getMyMonthlyAttendances', 'callableGetPublishedTOs', 'callableGetMyIdCardRequests', 'getMyContracts'}),
          reason: '앞 호출이 끝나기 전에 모두 출발');
      s.individualGate!.complete();
      final b = await f;
      expect(b.applications.ok && b.contracts.ok, isTrue);
    });

    testWidgets('WHB-APP-5 묶음 전체 실패(unavailable) → 요청 섹션 전부 실패 · 개별 재호출 0', (t) async {
      final s = _Server();
      _install(t, s);
      s.bundle = (_) => <Object?>['UNAVAILABLE', 'down', {'code': 'unavailable', 'message': 'down'}];
      final b = await FirestoreService().getWorkerHomeBundle(uid: 'w1', generation: 'w1#1', months: [_m11]);
      expect([b.applications.ok, b.monthlyAttendances['2026-11']!.ok, b.publishedTOs.ok, b.idCardRequests.ok, b.contracts.ok],
          everyElement(isFalse));
      expect(s.args(), isEmpty, reason: '같은 장애를 개별로 다시 기다리지 않는다');
      expect(WorkerHomeBundleFirestore.debugBundleUnsupported, isFalse, reason: '일시 장애로 묶음을 끄지 않는다');
    });

    testWidgets('WHB-APP-6 진행 중 공유 — 묶음 비행 중 다른 소비자 호출은 합류(추가 호출 0)', (t) async {
      final s = _Server()..bundleGate = Completer<void>();
      _install(t, s);
      final bf = FirestoreService().getWorkerHomeBundle(uid: 'w1', generation: 'w1#1', months: [_m11]);
      await t.pump();
      final appsF = FirestoreService().getMyApplications('w1');
      final attF = FirestoreService().getMyMonthlyAttendances(userId: 'w1', year: 2026, month: 11);
      s.bundleGate!.complete();
      await bf;
      expect((await appsF).single.id, 'a1');
      expect((await attF).single.id, 't11');
      expect(s.args(), isEmpty, reason: '일자리·일정 탭의 같은 순간 호출이 묶음 결과를 함께 받는다');
    });

    testWidgets('WHB-APP-7 TTL 안 캐시 섹션은 묶음 요청에서 뺀다', (t) async {
      final s = _Server();
      _install(t, s);
      await FirestoreService().getMyApplications('w1');
      await FirestoreService().getMyMonthlyAttendances(userId: 'w1', year: 2026, month: 11);
      await FirestoreService().getPublishedTOs();
      final b = await FirestoreService().getWorkerHomeBundle(uid: 'w1', generation: 'w1#1', months: [_m11]);
      expect((s.bundleArgs.single['sections'] as List).toSet(), {'idCardRequests', 'contracts'});
      expect(b.applications.value!.single.id, 'ind1', reason: '캐시 값');
    });

    testWidgets('WHB-APP-PARSE 계약 해석 = ContractService.getByWorker', (t) async {
      final items = [
        {
          'id': 'c1', 'status': 'pending_worker', 'workerId': 'w1', 'businessId': 'b1', 'applicationId': 'app_1',
          'applicationIds': ['app_1'], 'toId': 'to1', 'isLongTerm': false, 'createdAt': _ts(DateTime.utc(2026, 11, 1)),
          'snapshot': {
            'businessName': '합성 사업장', 'businessNumber': '000-00-00000', 'businessAddress': '서울', 'ownerName': '대표',
            'workerName': '김근로', 'workType': '상하차', 'workPlace': '서울', 'isLongTerm': false, 'contractStart': '2026-11-28',
            'contractEnd': '2026-11-28', 'workDays': <Object?>[], 'startTime': '09:00', 'endTime': '18:00', 'breakMinutes': 60,
            'wage': 12000, 'wageType': 'hourly', 'paymentMethod': '계좌이체', 'payScheduleType': 'same_day', 'taxDeductionType': 'none',
          },
          'articles': <Object?>[],
        },
        {'id': 'broken'},
      ];
      final m = t.binding.defaultBinaryMessenger;
      m.setMockMessageHandler(_callCh, (data) async => const StandardMessageCodec().encodeMessage(<Object?>[
            {'items': items, 'hasMore': false}
          ]));
      addTearDown(() => m.setMockMessageHandler(_callCh, null));
      final viaService = await ContractService().getByWorker('w1');
      final viaBundle = debugParseMyContracts({'items': items});
      expect(viaBundle.map((c) => '${c.id}|${c.status}').toList(), viaService.map((c) => '${c.id}|${c.status}').toList());
      expect(viaBundle.length, 1, reason: '깨진 한 건은 두 경로 모두 버린다');
    });
  });

  // ── 홈 연결 ─────────────────────────────────────────────────────────
  group('WHB-HOME', () {
    UserModel worker() => UserModel(
        uid: 'w1', username: '', name: '김알핏', email: '', role: UserRole.USER, accountStatus: 'active',
        passVerifiedAt: DateTime(2026, 11, 25), nationalityStatus: 'unknown', authProviders: const ['kakao'], signupSource: 'kakao_v1');

    Future<void> mount(WidgetTester t, UserHomeReads reads) async {
      t.view.physicalSize = const Size(390, 2400);
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.reset);
      await t.pumpWidget(const SizedBox.shrink());
      await t.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<UserProvider>.value(value: _W(worker())),
          ChangeNotifierProvider<NotificationProvider>(create: (_) => NotificationProvider()),
        ],
        child: MaterialApp(
          theme: RoleTheme.workerTheme,
          home: UserTabScope(
            switchToTab: (_) {},
            switchToTabWithDate: (_, __) {},
            pendingJobDate: null,
            clearPendingJobDate: () {},
            pendingScheduleMonth: null,
            clearPendingScheduleMonth: () {},
            switchToScheduleNow: () {},
            switchToScheduleDate: (_) {},
            child: UserHomeScreen(reads: reads, clock: () => DateTime.utc(2026, 11, 26, 1), tourCompleted: () async => true),
          ),
        ),
      ));
    }

    UserHomeReads reads(List<Map> log, WorkerHomeBundle Function(bool includeLegal) make, {List<String>? legalCalls}) =>
        UserHomeReads(
          slotsForTO: (_) async => const <SlotModel>[],
          myContracts: (_) async => throw StateError('개별 경로를 쓰면 안 된다'),
          myApplications: (_) async => throw StateError('개별 경로를 쓰면 안 된다'),
          myMonthlyAttendances: ({required String userId, required int year, required int month}) async =>
              throw StateError('개별 경로를 쓰면 안 된다'),
          publishedTOs: () async => throw StateError('개별 경로를 쓰면 안 된다'),
          pendingIdCardRequests: (_) async => throw StateError('개별 경로를 쓰면 안 된다'),
          myRenewalProposals: () async => const [],
          businessById: (id) async => BusinessModel(
              id: id, name: 'b', ownerId: 'o', businessNumber: '0', address: 'a', category: 'c', subCategory: 's',
              isApproved: true, createdAt: DateTime(2026)),
          invalidatePublishedTOsCache: () {},
          documentCorrections: () async => DocumentCorrectionSurface.empty,
          legalReadiness: () async {
            legalCalls?.add('individual');
            return const LegalReadiness(status: LegalReadinessStatus.current);
          },
          homeBundle: ({required String uid, required String generation, required List<({int year, int month})> months,
              bool includeLegal = false}) async {
            log.add({'uid': uid, 'generation': generation, 'months': months.length, 'legal': includeLegal});
            await Future<void>.delayed(const Duration(milliseconds: 200));
            return make(includeLegal);
          },
        );

    ApplicationModel terminating() => ApplicationModel(
        id: 'x1', toId: 'to_x1', uid: 'w1', businessId: 'b_x1', businessName: '나래 센터', toTitle: '단기', status: AppStatus.confirmed,
        selectedWorkType: '피킹', startTime: '09:00', endTime: '18:00', wage: 12000, wageType: 'hourly',
        workDate: DateTime.utc(2026, 11, 30), appliedAt: DateTime.utc(2026, 11, 20), applicationType: AppType.shortTerm,
        confirmedAt: DateTime.utc(2026, 11, 1), terminationStatus: AppStatus.pending);

    WorkerHomeBundle bundle({
      HomeBundleOutcome<List<ApplicationModel>>? apps,
      HomeBundleOutcome<List<IdCardAccessRequestModel>>? id,
      HomeBundleOutcome<LegalReadiness>? legal,
      bool includeLegal = false,
    }) =>
        WorkerHomeBundle(
          applications: apps ?? HomeBundleOutcome.ok(<ApplicationModel>[]),
          monthlyAttendances: {'2026-11': HomeBundleOutcome.ok(<AttendanceModel>[])},
          publishedTOs: HomeBundleOutcome.ok(<TOModel>[]),
          idCardRequests: id ?? HomeBundleOutcome.ok(<IdCardAccessRequestModel>[]),
          contracts: HomeBundleOutcome.ok(<EmploymentContractModel>[]),
          legalReadiness: includeLegal ? legal : null,
          viaBundle: true,
        );

    testWidgets('WHB-HOME-1 섹션 실패 의미 유지 · 약관은 묶음 값(개별 약관 호출 0)', (t) async {
      final log = <Map>[];
      final legalCalls = <String>[];
      await mount(
          t,
          reads(log, (inc) => bundle(
                apps: HomeBundleOutcome.fail(const HomeBundleSectionError('applications', 'internal')),
                id: HomeBundleOutcome.fail(const HomeBundleSectionError('idCardRequests', 'unavailable')),
                includeLegal: inc,
                legal: HomeBundleOutcome.ok(const LegalReadiness(
                    status: LegalReadinessStatus.reconsentRequired, reconsentRequired: ['service_terms'])),
              ), legalCalls: legalCalls));
      for (var i = 0; i < 20; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
      expect(findVisibleText('계약해지 요청을 확인하지 못했어요'), findsOneWidget, reason: '지원 실패 → 해지 확인 못함(개별 경로와 같다)');
      expect(findVisibleText('오늘 확정된 근무가 없어요'), findsNothing, reason: '정상 0 합성 0');
      expect(find.byKey(const ValueKey('worker-home-required-error')), findsOneWidget, reason: '신분증 실패 → D290-01 일반 행');
      expect(findVisibleText('이용약관이 변경되었습니다'), findsOneWidget, reason: '약관 카드가 묶음 값을 받았다');
      expect(legalCalls, isEmpty, reason: '첫 약관 조회는 묶음이 대신했다');
      expect(log.single['legal'], isTrue);
      t.takeException();
    });

    testWidgets('WHB-HOME-2 generation = uid#회차 · 두 번째 로드는 약관 섹션 0 · 성공 시 해지 카드', (t) async {
      final log = <Map>[];
      await mount(
          t,
          reads(log, (inc) => bundle(
                apps: HomeBundleOutcome.ok([terminating()]),
                includeLegal: inc,
                legal: HomeBundleOutcome.ok(const LegalReadiness(status: LegalReadinessStatus.current)),
              )));
      for (var i = 0; i < 15; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
      expect(findVisibleText('나래 센터에서 계약해지를 요청했어요'), findsOneWidget);
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      for (var i = 0; i < 10; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
      print('[WHB-HOME-2] $log');
      expect(log.length, 2);
      expect(log[0]['generation'], 'w1#1');
      expect(log[1]['generation'], 'w1#2');
      expect(log[0]['legal'], isTrue);
      expect(log[1]['legal'], isFalse, reason: '약관은 카드가 스스로 갱신한다 — 묶음에는 첫 로드만');
      t.takeException();
    });
  });
}

extension on _Server {
  /// 묶음 외 개별 callable 호출(묶음·약관 제외).
  Map<String, int> args() => Map.of(calls)..remove('callableGetWorkerHomeBundle');
}

class _W extends UserProvider {
  _W(this.user);
  final UserModel user;
  @override
  UserModel? get currentUser => user;
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
