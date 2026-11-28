// [WORKER-HOME-CRITICAL-PATH] 지원자 첫 진입 — 요청 수와 표시 시점 실행 추적 (LOCAL).
//
//   A. 루트(네 탭 동시 마운트) — 실제 FirestoreService·캐시를 그대로 두고 플랫폼 채널만
//      가로챈다. 요청마다 지연을 주고 이름·출발·도착 가짜 시각을 기록한다.
//   B. 홈 — 읽기 경계에 지연을 주입하고 화면 표시 세 시점을 잰다.
//        첫 피드백   : 첫 프레임(인사·스켈레톤)
//        주요 정보   : 수입 진행바가 사라지고 숫자가 보인 시각(_isLoadingData 해제)
//        전체 표시   : 추천 카드 제목이 보인 시각
//   지연 값은 DEV 지표(1분 집계 warm p50)를 근사한 입력일 뿐 측정값이 아니다.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ALfit/models/core/application_model.dart';
import 'package:ALfit/models/core/business_model.dart';
import 'package:ALfit/models/core/slot_model.dart';
import 'package:ALfit/models/core/to_model.dart';
import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/models/core/user_region.dart';
import 'package:ALfit/models/core/work_detail_data.dart';
import 'package:ALfit/providers/notification_provider.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/screens/user/user_home_reads.dart';
import 'package:ALfit/screens/user/user_home_screen.dart';
import 'package:ALfit/screens/user/user_root_screen.dart';
import 'package:ALfit/services/payroll_correction_service.dart';
import 'package:ALfit/utils/format_helper.dart';
import 'support/checkin_contract_fixture.dart';

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

class _User extends UserProvider {
  static const region =
      UserRegion(province: '서울특별시', city: '강남구', district: '역삼동');
  @override
  UserModel? get currentUser => UserModel(
        uid: 'u1', username: 'u1', name: '김근로', email: 'u1@alfit.local',
        role: UserRole.USER, homeRegion: region, accountStatus: 'active',
        passVerifiedAt: DateTime.now().subtract(const Duration(days: 30)),
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
  @override
  bool get hasPendingContract => false;
}

// ── 공통 시계: 이 파일의 pump 루프가 50ms 씩 올린다 ──────────────────────
int _now = 0;
Future<void> _advance(WidgetTester t, int ms, [void Function()? each]) async {
  for (var e = 0; e < ms; e += 50) {
    await t.pump(const Duration(milliseconds: 50));
    _now += 50;
    each?.call();
  }
}

class _Req {
  _Req(this.name, this.start);
  final String name;
  final int start;
  int? end;
}

// ══ A. 루트 ══════════════════════════════════════════════════════════════
const _callCh =
    'dev.flutter.pigeon.cloud_functions_platform_interface.CloudFunctionsHostApi.call';
const _fsBase =
    'dev.flutter.pigeon.cloud_firestore_platform_interface.FirebaseFirestoreHostApi.';

/// 모든 파서가 읽는 키를 담은 빈 응답 — 이번 추적의 대상은 요청 수·시점이다.
ByteData? _emptyOk() => const StandardMessageCodec().encodeMessage(<Object?>[
      <String, Object?>{
        'applications': <Object?>[], 'items': <Object?>[], 'tos': <Object?>[],
        'requests': <Object?>[], 'proposals': <Object?>[], 'contracts': <Object?>[],
        'hasMore': false,
      }
    ]);
ByteData? _err(String code) => const StandardMessageCodec()
    .encodeMessage(<Object?>[code, 'mock $code', null]);

// ══ B. 홈 fixture ═══════════════════════════════════════════════════════
final DateTime _today = FormatHelper.toKstDate(DateTime.now());
DateTime _day(int o) => _today.add(Duration(days: o));

BusinessModel _business(String id) => BusinessModel(
      id: id, name: '강남 물류센터', ownerId: 'admin1',
      businessNumber: '000-00-00000', address: '서울특별시 강남구 테헤란로 1',
      category: '물류', subCategory: '창고', isApproved: true,
      createdAt: _day(-200),
    );

ApplicationModel _confirmed() => ApplicationModel(
      id: 'a1', toId: 'to_a1', uid: 'u1', businessId: 'biz1',
      businessName: '강남 물류센터', toTitle: '단기 공고',
      status: AppStatus.confirmed, selectedWorkType: '상하차',
      startTime: '09:00', endTime: '18:00', wage: 12000,
      workDate: _day(2), appliedAt: _day(-3),
    );

TOModel _recTo(String id, String biz) {
  final d = _day(4);
  final key = '${d.year}-${d.month.toString().padLeft(2, "0")}'
      '-${d.day.toString().padLeft(2, "0")}';
  return TOModel(
    id: id, businessId: biz, businessName: '강남 물류센터',
    businessCity: _User.region.city, businessDistrict: _User.region.district,
    type: 'flex', title: '물류센터 상하차 지원 $id', creatorUID: 'admin1',
    status: TOStatus.active, deadlineType: 'NONE', hoursBeforeStart: 0,
    workDetails: [
      WorkDetailData(wdId: 'wd1', workType: '상하차', wage: 12000,
          wageType: 'hourly', requiredCount: 2, startTime: '09:00', endTime: '18:00'),
    ],
    slotDateKeys: [key], totalRequired: 2, totalConfirmed: 0, totalPending: 0,
    isPublished: true, publishMode: 'immediate',
    createdAt: _day(-2), statusUpdatedAt: _day(-2),
  );
}

class _Lat {
  const _Lat({required this.callable, required this.businessDoc});
  final int callable;
  final int businessDoc;
}

class _HomeTrace {
  final reqs = <_Req>[];
  Future<T> _timed<T>(String name, int ms, T value) async {
    final r = _Req(name, _now);
    reqs.add(r);
    await Future<void>.delayed(Duration(milliseconds: ms));
    r.end = _now + 50 * ((ms ~/ 50)); // 다음 pump 경계 근사
    return value;
  }

  UserHomeReads reads(_Lat lat) => UserHomeReads(
        slotsForTO: (toId) => _timed('slotsForTO', lat.businessDoc, const <SlotModel>[]),
        // [CONTRACT-DISPATCH-B4] 홈 CTA 는 계약 동의 판정을 함께 본다 — 이 시험의 전제: 오늘 근무 계약은 양측 서명 완료
        myContracts: (uid) async => completedContractsFor([_confirmed()]),
        myApplications: (uid) => _timed('GetMyApplications', lat.callable, [_confirmed()]),
        myMonthlyAttendances: ({required String userId, required int year, required int month}) =>
            _timed('getMyMonthlyAttendances', lat.callable, const []),
        publishedTOs: () => _timed('GetPublishedTOs', lat.callable,
            [_recTo('t1', 'biz1'), _recTo('t2', 'biz2')]),
        pendingIdCardRequests: (uid) => _timed('GetMyIdCardRequests', lat.callable, const []),
        myRenewalProposals: () => _timed('GetMyRenewalProposals', lat.callable, const []),
        businessById: (id) => _timed('businessById($id)', lat.businessDoc, _business(id)),
        invalidatePublishedTOsCache: () {},
        documentCorrections: () =>
            _timed('GetMyDocumentCorrections', lat.callable, DocumentCorrectionSurface.empty),
      );
}

Future<Map<String, int?>> _traceHome(WidgetTester t, _HomeTrace tr, _Lat lat) async {
  t.view.physicalSize = const Size(390, 4000);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  _now = 0;
  await t.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider<UserProvider>.value(value: _User()),
      ChangeNotifierProvider<NotificationProvider>(create: (_) => NotificationProvider()),
    ],
    child: MaterialApp(home: UserHomeScreen(reads: tr.reads(lat))),
  ));
  int? first, main, full;
  void probe() {
    first ??= find.textContaining('김근로').evaluate().isNotEmpty ? _now : null;
    main ??= (find.byType(LinearProgressIndicator).evaluate().isEmpty &&
            tr.reqs.isNotEmpty)
        ? _now
        : null;
    full ??= find.textContaining('물류센터 상하차 지원').evaluate().isNotEmpty ? _now : null;
  }
  probe();
  await _advance(t, 4000, probe);
  return {'first': first, 'main': main, 'full': full};
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
    await initializeDateFormatting('ko_KR', null);
  });
  setUp(() => SharedPreferences.setMockInitialValues({'tour_completed_user_home': true}));

  testWidgets('HCP-A 루트 첫 진입 — callable 요청 이름·횟수·출발 시각', (t) async {
    const lat = 300;
    final reqs = <_Req>[];
    final m = t.binding.defaultBinaryMessenger;
    m.setMockMessageHandler(_callCh, (data) async {
      final args = (const StandardMessageCodec().decodeMessage(data) as List).first as Map;
      final r = _Req(args['functionName'] as String, _now);
      reqs.add(r);
      // [impl_15 의도적 갱신] 이 대역은 개별 endpoint 경로(진행 중 공유·횟수)를 잰다 — 묶음 함수는 '구서버(없음)'로 답해
      //   앱이 같은 호출 안에서 개별 호출로 폴백하게 한다(묶음 경로 자체는 perf_l9_bundle_test WHB-* 가 맡는다).
      if (r.name == 'callableGetWorkerHomeBundle') {
        r.end = _now;
        return const StandardMessageCodec().encodeMessage(<Object?>['NOT_FOUND', 'no bundle', {'code': 'not-found', 'message': 'no bundle'}]);
      }
      await Future<void>.delayed(const Duration(milliseconds: lat));
      r.end = _now;
      return _emptyOk();
    });
    for (final api in ['documentReferenceGet', 'queryGet', 'aggregateQuery']) {
      m.setMockMessageHandler('$_fsBase$api', (data) async {
        reqs.add(_Req('firestore.$api', _now)..end = _now + lat);
        await Future<void>.delayed(const Duration(milliseconds: lat));
        return _err('unavailable');
      });
    }
    addTearDown(() {
      m.setMockMessageHandler(_callCh, null);
      for (final api in ['documentReferenceGet', 'queryGet', 'aggregateQuery']) {
        m.setMockMessageHandler('$_fsBase$api', null);
      }
    });
    t.view.physicalSize = const Size(390, 900);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    _now = 0;
    await t.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<UserProvider>(create: (_) => _User()),
        ChangeNotifierProvider<NotificationProvider>(create: (_) => NotificationProvider()),
      ],
      child: const MaterialApp(home: UserRootScreen()),
    ));
    await _advance(t, 3000);
    final byName = <String, List<int>>{};
    for (final r in reqs) {
      (byName[r.name] ??= []).add(r.start);
    }
    // ignore: avoid_print
    print('[HCP-A] 요청(지연 ${lat}ms) ${byName.entries.map((e) => '${e.key}×${e.value.length}@${e.value.join("/")}ms').join(' · ')}');
    expect(byName['callableGetMyApplications'], isNotNull);
    t.takeException();
  });

  for (final (label, lat) in [
    ('warm 근사(callable 100ms · 사업장 문서 300ms)', const _Lat(callable: 100, businessDoc: 300)),
    ('cold 근사(callable 1,000ms · 사업장 문서 300ms)', const _Lat(callable: 1000, businessDoc: 300)),
  ]) {
    testWidgets('HCP-B 홈 표시 시점 — $label', (t) async {
      final tr = _HomeTrace();
      final marks = await _traceHome(t, tr, lat);
      // ignore: avoid_print
      print('[HCP-B $label] 첫 피드백 ${marks['first']}ms · 주요 정보 ${marks['main']}ms · 전체 ${marks['full']}ms · '
          '요청 ${tr.reqs.map((r) => '${r.name}@${r.start}').join(' ')}');
      expect(marks['first'], 0);
      expect(marks['main'], isNotNull);
      expect(marks['full'], isNotNull);
      // 주요 정보는 사업장 문서(추천 이미지용)를 기다릴 이유가 없다.
      expect(marks['main']!, lessThan(lat.callable + lat.businessDoc),
          reason: '주요 정보가 사업장 문서 조회까지 기다린다');
    });
  }
}
