// [SUBADMIN-SCOPE.40] 서브관리자 권한 혼합 — 공고 목록 범위와 홈 조회 범위
//
// .39-A1 LOCAL 기기 재현(서브관리자 A=공고·인력, B=급여만):
//   1. A 에서 공고 탭을 열면 목록 전체가 실패했다. 앱이 배정 사업장 전부를
//      `callableGetAdminTOs` 로 보냈고, 서버는 사업장마다 canManageTo 를 보고
//      하나라도 어긋나면 요청 전체를 거절한다(MODEL A — 서버는 바꾸지 않는다).
//      화면은 '네트워크 상태를 확인'이라고 말했다.
//   2. B 홈이 거절될 조회 4건을 보냈다 — 확정 명단(workerOperation) ×2,
//      날인 준비, 사업주 문서. 화면은 이미 그 구역을 그리지 않았다.
//
// 하네스: 실제 WorkforceListView + WorkforceController(공고 목록은 플랫폼 채널),
//   실제 BusinessAdminHomeScreen + 읽기 주입(AdminHomeReads). 권한 상태는
//   production 판정 함수(`subAdminBusinessesFor`·`checkCurrentBusiness`)가 읽는
//   공개 값만 대역으로 바꾼다. 서버·DEV 호출 없음.
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ALfit/controllers/workforce_controller.dart';
import 'package:ALfit/models/core/application_model.dart';
import 'package:ALfit/models/core/attendance_model.dart';
import 'package:ALfit/models/core/business_member_model.dart'
    show MemberPermissions;
import 'package:ALfit/models/core/business_model.dart';
import 'package:ALfit/models/core/contract_template_model.dart';
import 'package:ALfit/models/core/slot_model.dart' show SlotModel, SlotStatus;
import 'package:ALfit/models/core/to_model.dart';
import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/models/core/work_detail_data.dart';
import 'package:ALfit/models/ui/admin_home_summary_model.dart';
import 'package:ALfit/models/ui/admin_to_list_ui_models.dart';
import 'package:ALfit/models/ui/staffing_readiness_model.dart';
import 'package:ALfit/providers/notification_provider.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/screens/business_admin/admin_home_reads.dart';
import 'package:ALfit/screens/business_admin/business_admin_home_screen.dart';
import 'package:ALfit/screens/business_admin/workforce_management/workforce_list_view.dart';
import 'package:ALfit/services/business_posting_readiness.dart';
import 'package:ALfit/utils/navigation_key.dart';

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

const _channel =
    'dev.flutter.pigeon.cloud_functions_platform_interface.CloudFunctionsHostApi.call';

const _toPerm = MemberPermissions(canManageTo: true, canManageWorkers: true);
const _wagePerm = MemberPermissions(canManageWage: true);

// ══════════════════════════════════════════════════════════════════
// 권한 대역 — production 판정 함수가 읽는 공개 값만 바꾼다
// ══════════════════════════════════════════════════════════════════

/// 서브관리자. [perms] 에 없는 사업장은 확인된 거부(문서 없음)다.
/// [watchError] 사업장은 구독이 error — 값이 있어도 미확인이다.
class _SubP extends UserProvider {
  _SubP({
    required List<String> assigned,
    required this.perms,
    this.loaded = true,
    Set<String>? watchError,
    String? selected,
  })  : watchError = watchError ?? <String>{},
        _selected = selected ?? assigned.first {
    debugSetCurrentUser(UserModel(
      uid: 'sub1', username: 'sub1', name: '합성 하위관리',
      email: 'sub1@alfit.local', role: UserRole.USER,
      subAdminBusinessIds: assigned,
    ));
  }

  final Map<String, MemberPermissions> perms;
  final Set<String> watchError;
  bool loaded;
  String _selected;

  /// '다시 시도'가 권한을 다시 읽을 때 일어날 일.
  void Function()? onAccessRefresh;
  int accessRefreshes = 0;

  void switchTo(String id) {
    _selected = id;
    notifyListeners();
  }

  void changed() => notifyListeners();

  @override
  String? get effectiveBusinessId => _selected;

  @override
  bool get subAdminPermissionsLoaded => loaded;

  @override
  MemberPermissions? permissionsForBusiness(String businessId) =>
      perms[businessId];

  @override
  PermissionWatchState permissionWatchStateFor(String businessId) =>
      watchError.contains(businessId)
          ? PermissionWatchState.error
          : PermissionWatchState.verified;

  @override
  PermissionWatchState get currentBusinessPermissionHealth =>
      permissionWatchStateFor(_selected);

  @override
  bool canForBusiness(String businessId, bool Function(MemberPermissions p) check) {
    final p = perms[businessId];
    return p != null && check(p);
  }

  @override
  PermissionCheck checkForBusiness(
      String businessId, bool Function(MemberPermissions p) check) {
    if (!loaded) return PermissionCheck.unknown;
    if (watchError.contains(businessId)) return PermissionCheck.error;
    return canForBusiness(businessId, check)
        ? PermissionCheck.allowed
        : PermissionCheck.denied;
  }

  @override
  PermissionCheck checkCurrentBusiness(bool Function(MemberPermissions p) check) =>
      checkForBusiness(_selected, check);

  @override
  bool can(bool Function(MemberPermissions p) check) =>
      canForBusiness(_selected, check);

  @override
  bool canForAnyBusiness(bool Function(MemberPermissions p) check,
          {required bool whenUnknown}) =>
      !loaded
          ? whenUnknown
          : (currentUser?.subAdminBusinessIds ?? const <String>[])
              .any((id) => canForBusiness(id, check));

  @override
  VoidCallback watchBusinessPermissions(String businessId) => () {};

  @override
  Future<void> refreshSubAdminAccessState() async {
    accessRefreshes++;
    onAccessRefresh?.call();
    notifyListeners();
  }

  @override
  Future<void> refreshAdminScopeState() => refreshSubAdminAccessState();
}

/// 사업장 소유자 — 기존 전체 범위가 그대로인지 보는 쪽.
class _OwnerP extends UserProvider {
  _OwnerP(List<String> managed) {
    debugSetCurrentUser(UserModel(
      uid: 'owner', username: 'owner', name: '관리자',
      email: 'owner@alfit.local', role: UserRole.BUSINESS_ADMIN,
      managedBusinessIds: managed, sealBase64: 'seal',
    ));
  }
  @override
  bool get subAdminPermissionsLoaded => true;
  @override
  bool can(bool Function(MemberPermissions p) check) => true;
  @override
  bool canForBusiness(String b, bool Function(MemberPermissions p) c) => true;
  @override
  PermissionCheck checkForBusiness(String b, bool Function(MemberPermissions p) c) =>
      PermissionCheck.allowed;
  @override
  PermissionCheck checkCurrentBusiness(bool Function(MemberPermissions p) c) =>
      PermissionCheck.allowed;
  @override
  bool canForAnyBusiness(bool Function(MemberPermissions p) c,
          {required bool whenUnknown}) =>
      true;
  @override
  PermissionWatchState get currentBusinessPermissionHealth =>
      PermissionWatchState.verified;
}

// ══════════════════════════════════════════════════════════════════
// 공고 목록 서버 — MODEL A (요청 중 하나라도 불허면 전체 거절)
// ══════════════════════════════════════════════════════════════════

final _workDate = () {
  final kstNow = DateTime.now().toUtc().add(const Duration(hours: 9));
  return DateTime.utc(kstNow.year, kstNow.month, kstNow.day)
      .add(const Duration(days: 7))
      .subtract(const Duration(hours: 9))
      .toLocal();
}();

String _title(String biz) => '공고-$biz';

TOModel _to(String biz) => TOModel(
      id: 'TO-$biz', businessId: biz, businessName: '사업장 $biz', type: 'flex',
      title: _title(biz), creatorUID: 'owner', status: TOStatus.active,
      workDetails: const [], totalRequired: 1, totalConfirmed: 0,
      totalPending: 0, isPublished: true, publishMode: 'immediate',
      rangeStart: _workDate, rangeEnd: _workDate,
      createdAt: DateTime.now().subtract(const Duration(days: 1)),
      statusUpdatedAt: DateTime.now().subtract(const Duration(days: 1)),
    );

class _Server {
  _Server(this.toAllowed);

  /// 서버가 실제로 공고 권한을 인정하는 사업장.
  Set<String> toAllowed;

  /// null 이 아니면 그 코드로 실패한다(예: unavailable = 네트워크).
  String? failWith;

  /// 응답을 붙잡아 두는 자리 — 읽는 도중의 권한 변화 재현용.
  Completer<void>? hold;

  final List<List<String>> requests = [];

  Object? _wire(Object? v) {
    if (v is Timestamp) {
      return {'_seconds': v.seconds, '_nanoseconds': v.nanoseconds};
    }
    if (v is DateTime) {
      final ms = v.millisecondsSinceEpoch;
      return {'_seconds': ms ~/ 1000, '_nanoseconds': (ms % 1000) * 1000000};
    }
    if (v is Map) return v.map((k, x) => MapEntry(k, _wire(x)));
    if (v is List) return v.map(_wire).toList();
    return v;
  }

  Future<ByteData?> handle(ByteData? message) async {
    final args = (const StandardMessageCodec().decodeMessage(message) as List)
        .first as Map;
    final name = args['functionName'] as String;
    if (name != 'callableGetAdminTOs') {
      return const StandardMessageCodec().encodeMessage(<Object?>[
        'not-found', 'unexpected $name', <String, Object?>{'code': 'not-found'}
      ]);
    }
    final params = Map<String, Object?>.from(args['parameters'] as Map);
    final ids = List<String>.from(params['businessIds'] as List);
    requests.add(ids);
    final h = hold;
    if (h != null) await h.future;
    final code = failWith ??
        (ids.every(toAllowed.contains) ? null : 'permission-denied');
    if (code != null) {
      return const StandardMessageCodec().encodeMessage(
          <Object?>[code, 'x', <String, Object?>{'code': code}]);
    }
    final items = [
      for (final b in ids)
        Map<String, Object?>.from(_wire(_to(b).toMap()) as Map)
          ..['id'] = 'TO-$b',
    ];
    return const StandardMessageCodec().encodeMessage(<Object?>[
      <String, Object?>{'items': items}
    ]);
  }

  Future<({List<TOItem> groupTOs, List<DateTime> slotDates})> slots(
      String toId, {TOModel? masterTO}) async {
    final model = masterTO ?? _to(toId.replaceFirst('TO-', ''));
    return (
      groupTOs: [
        TOItem(
          to: model,
          slot: SlotModel(
            id: 'S-$toId', toId: toId, date: _workDate, status: SlotStatus.open,
            workDetails: [
              WorkDetailData(
                wdId: 'wd1', workType: 'QA 분류', startTime: '10:00',
                endTime: '11:00', requiredCount: 1, wage: 12000,
                wageType: 'hourly',
                applicationDeadline: _workDate.add(const Duration(hours: 8)),
              ),
            ],
            createdAt: DateTime.now().subtract(const Duration(days: 1)),
          ),
          confirmedCount: 0,
          pendingCount: 0,
          totalRequired: 1,
        ),
      ],
      slotDates: [_workDate],
    );
  }
}

Future<void> _settle(WidgetTester t, [int n = 30]) async {
  for (var i = 0; i < n; i++) {
    await t.pump(const Duration(milliseconds: 50));
  }
}

String _texts(WidgetTester t) => [
      ...t.widgetList<Text>(find.byType(Text))
          .map((w) => w.data ?? w.textSpan?.toPlainText() ?? ''),
      ...t.widgetList<RichText>(find.byType(RichText))
          .map((w) => w.text.toPlainText()),
    ].map(visibleText).where((s) => s.isNotEmpty).join(' | ');

Future<WorkforceController> _pumpList(
    WidgetTester t, _Server server, UserProvider up) async {
  t.view.physicalSize = const Size(411, 900);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  t.binding.defaultBinaryMessenger.setMockMessageHandler(_channel, server.handle);
  addTearDown(() =>
      t.binding.defaultBinaryMessenger.setMockMessageHandler(_channel, null));
  final controller = WorkforceController(
    loadSlots: server.slots,
    loadWorkDetailStats: (to, {slotId, slotWorkDetails}) async => {
      'workDetails': const <WorkDetailData>[],
      'workStats': const <String, dynamic>{},
      'statsFailed': false,
    },
  );
  addTearDown(controller.dispose);
  await t.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider<UserProvider>.value(value: up),
      ChangeNotifierProvider<WorkforceController>.value(value: controller),
    ],
    child: MaterialApp(
      navigatorKey: navigatorKey,
      home: const Scaffold(body: WorkforceListView()),
    ),
  ));
  // 공고 탭 root 가 하는 첫 로드와 같다.
  unawaited(controller.load(t.element(find.byType(WorkforceListView))));
  await _settle(t, 20);
  return controller;
}

// ══════════════════════════════════════════════════════════════════
// 홈 읽기 경계 — loader 별 호출 수를 센다
// ══════════════════════════════════════════════════════════════════

class _Template extends Fake implements ContractTemplateModel {
  @override
  bool get isSupportedForNewUse => true;
}

final String _todayStr = () {
  final d = DateTime.now().toUtc().add(const Duration(hours: 9));
  return '${d.year}-${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}();

AdminHomeSummaryModel _summary() {
  Map<String, dynamic> e() =>
      {'available': true, 'count': 0, 'byBusiness': const <Object>[]};
  return AdminHomeSummaryModel.fromMap({
    'actions': {
      'resignRequest': {...e(), 'soonCount': 0},
      'approval': {...e(), 'overdueCount': 0},
      'scheduleChangeRequest': e(),
      'unsentContract': e(),
      'unclosed': {...e(), 'oldestDate': null},
      'settlementRequest': e(),
      'wageChangeRequest': e(),
      'unpaidWage': {...e(), 'overdueCount': 0, 'missingDueDateCount': 0},
    },
    'upcoming': {
      'expiringContract': {...e(), 'upcomingCount': 0, 'expiredCount': 0},
    },
  });
}

StaffingReadinessModel _staffing() => StaffingReadinessModel(
      available: true, partial: false, failedBusinessCount: 0,
      publishedPostingCount: 1,
      days: [
        StaffingDayData.fromMap({
          'date': _todayStr, 'requiredCount': 1, 'confirmedCount': 1,
          'shortageCount': 0, 'pendingAvailable': false,
          'byBusiness': const <Object>[],
        }),
      ],
    );

BusinessModel _biz(String id) => BusinessModel(
      id: id, name: '사업장 $id', ownerId: 'owner',
      businessNumber: '000-00-00000', address: '서울시 어딘가',
      category: '물류', subCategory: '창고', isApproved: true,
      createdAt: DateTime(2026, 1, 1),
    );

/// 오늘 확정 1명(출근 전) — 출근 줄이 실제 값을 갖게 한다.
ApplicationModel _confirmed(String biz) => ApplicationModel.tryFromMap({
      'toId': 'TO-$biz', 'businessId': biz, 'businessName': '사업장 $biz',
      'uid': 'w1', 'userName': '근로자', 'status': 'CONFIRMED',
      'selectedWorkType': 'QA 분류', 'startTime': '23:58', 'endTime': '23:59',
      'workDate': Timestamp.fromDate(DateTime.now()),
      'appliedAt': Timestamp.fromDate(DateTime.now()),
    }, 'APP-$biz')!;

class _Calls {
  final Map<String, List<String>> byKind = {};
  void hit(String kind, String biz) => (byKind[kind] ??= []).add(biz);
  int count(String kind) => byKind[kind]?.length ?? 0;
  List<String> of(String kind) => byKind[kind] ?? const [];
}

AdminHomeReads _reads(_Calls calls) => AdminHomeReads(
      summary: ({String? selectedBusinessId}) async {
        calls.hit('summary', selectedBusinessId ?? '*');
        return _summary();
      },
      businessesByIds: (ids) async => [for (final id in ids) _biz(id)],
      staffingReadiness: ({String? selectedBusinessId}) async {
        calls.hit('staffing', selectedBusinessId ?? '*');
        return _staffing();
      },
      attendanceByDate: ({required String businessId, required DateTime date}) async {
        calls.hit('attendance', businessId);
        return const <AttendanceModel>[];
      },
      confirmedWorkers: ({required DateTime date, required String businessId}) async {
        calls.hit('roster', businessId);
        return [_confirmed(businessId)];
      },
      workDetailTimes: (_) async => <String, dynamic>{},
      postingReadiness: (bizs) async {
        for (final b in bizs) {
          calls.hit('readiness', b.id);
        }
        return {
          for (final b in bizs)
            b.id: BusinessPostingReadiness(
              bizId: b.id, isApproved: true, hasCanonicalLicense: true,
              hasOwnerLegacyLicense: false, hasActiveWorkTypes: true,
              hasEmployerSeal: true,
            ),
        };
      },
      contractTemplates: (_) async => <ContractTemplateModel>[_Template()],
      tourCompleted: () => Future<bool>.value(true),
    );

Future<void> _pumpHome(WidgetTester t, UserProvider up, _Calls calls) async {
  t.view.physicalSize = const Size(390, 1800);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider<UserProvider>.value(value: up),
      ChangeNotifierProvider<NotificationProvider>(
          create: (_) => NotificationProvider()),
    ],
    child: MaterialApp(home: BusinessAdminHomeScreen(reads: _reads(calls))),
  ));
  for (var i = 0; i < 20; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _frames(WidgetTester t) async {
  for (var i = 0; i < 20; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({'tour_completed_admin_home': true});
  });
  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
    await initializeDateFormatting('ko_KR', null);
  });

  // ════════════════════════════════════════════════════════════
  // A — 공고 목록 범위
  // ════════════════════════════════════════════════════════════

  group('SPQ 공고 목록 범위', () {
    testWidgets('SPQ-1 A=공고 허용·B=불허 → A 만 묻고 A 목록이 보인다', (t) async {
      final server = _Server({'A'});
      final up = _SubP(assigned: ['A', 'B'], perms: {'A': _toPerm, 'B': _wagePerm});
      final c = await _pumpList(t, server, up);
      final s = _texts(t);
      expect(server.requests, [
        ['A']
      ], reason: '배정 전체 [A,B] 를 보내면 서버가 전체를 거절한다');
      expect(c.loadError, isNull);
      expect(s, contains(_title('A')), reason: s);
      expect(s, isNot(contains(_title('B'))), reason: s);
      expect(s, isNot(contains('불러오지 못했습니다')), reason: s);
      expect(s, isNot(contains('권한을 확인하지 못해')), reason: s);
    });

    testWidgets('SPQ-1b 수정 전 범위(배정 전체)는 서버가 실제로 거절한다 — 재현 고정',
        (t) async {
      // 앱 범위와 무관하게 서버 대역이 MODEL A 인지 확인한다(이 시험의 전제).
      final server = _Server({'A'});
      final reply = await server.handle(
          const StandardMessageCodec().encodeMessage(<Object?>[
        <String, Object?>{
          'functionName': 'callableGetAdminTOs',
          'parameters': <String, Object?>{
            'businessIds': <Object?>['A', 'B']
          },
        }
      ]));
      final decoded =
          const StandardMessageCodec().decodeMessage(reply) as List<Object?>;
      expect(decoded.first, 'permission-denied');
    });

    testWidgets('SPQ-2 공고 권한 0곳 → 조회 0건, "접근 권한이 없습니다"(공고 없음 아님)',
        (t) async {
      final server = _Server(<String>{});
      final up = _SubP(assigned: ['A', 'B'], perms: {'A': _wagePerm, 'B': _wagePerm});
      final c = await _pumpList(t, server, up);
      final s = _texts(t);
      expect(server.requests, isEmpty);
      expect(c.scopeDenied, isTrue);
      expect(s, contains('접근 권한이 없습니다'), reason: s);
      expect(s, isNot(contains('등록된 공고가 없습니다')), reason: s);
      expect(s, isNot(contains('네트워크')), reason: s);
    });

    testWidgets('SPQ-3 정상 단일 사업장 서브관리자는 그 사업장 하나를 묻는다', (t) async {
      final server = _Server({'A'});
      final up = _SubP(assigned: ['A'], perms: {'A': _toPerm});
      await _pumpList(t, server, up);
      expect(server.requests, [
        ['A']
      ]);
      expect(_texts(t), contains(_title('A')));
    });

    testWidgets('SPQ-4 소유자는 관리 사업장 전체를 그대로 묻는다', (t) async {
      final server = _Server({'A', 'B'});
      await _pumpList(t, server, _OwnerP(['A', 'B']));
      expect(server.requests, [
        ['A', 'B']
      ]);
      final s = _texts(t);
      expect(s, contains(_title('A')));
      expect(s, contains(_title('B')));
    });

    testWidgets('SPQ-5 권한 확인 실패 → 묻지 않고 "확인하지 못함", 다시 시도로 회복',
        (t) async {
      final server = _Server({'A'});
      // A 는 구독 error(값이 있어도 미확인), B 는 확인된 거부.
      final up = _SubP(
          assigned: ['A', 'B'],
          perms: {'A': _toPerm, 'B': _wagePerm},
          watchError: {'A'});
      final c = await _pumpList(t, server, up);
      var s = _texts(t);
      expect(server.requests, isEmpty, reason: '확인하지 못한 사업장은 묻지 않는다');
      expect(c.loadError, isA<PostingScopeUnresolved>());
      expect(s, contains('공고 권한을 확인하지 못했습니다'), reason: s);
      expect(s, isNot(contains('등록된 공고가 없습니다')), reason: s);
      expect(s, isNot(contains('접근 권한이 없습니다')), reason: '모름은 거부가 아니다: $s');

      // 다시 시도 → 권한을 먼저 다시 읽는다(구독 회복) → 그 다음 목록.
      up.onAccessRefresh = () => up.watchError.clear();
      await t.tap(findVisibleText('다시 시도'));
      await _settle(t, 30);
      s = _texts(t);
      expect(up.accessRefreshes, 1);
      expect(server.requests, [
        ['A']
      ]);
      expect(s, contains(_title('A')), reason: s);
      expect(c.loadError, isNull);
    });

    testWidgets('SPQ-5b 하이드레이션 전에는 아무 사업장도 묻지 않는다', (t) async {
      final server = _Server({'A'});
      final up = _SubP(
          assigned: ['A', 'B'], perms: {'A': _toPerm}, loaded: false);
      final c = await _pumpList(t, server, up);
      expect(server.requests, isEmpty);
      expect(c.loadError, isA<PostingScopeUnresolved>());
      expect(c.items, isEmpty);
    });

    testWidgets('SPQ-6 일부 미확인 → 허용분은 보이고, 빠진 사업장을 배너로 말한다',
        (t) async {
      final server = _Server({'A', 'C'});
      final up = _SubP(
          assigned: ['A', 'B', 'C'],
          perms: {'A': _toPerm, 'B': _wagePerm, 'C': _toPerm},
          watchError: {'C'});
      final c = await _pumpList(t, server, up);
      final s = _texts(t);
      expect(server.requests, [
        ['A']
      ]);
      expect(c.unresolvedScopeIds, ['C']);
      expect(s, contains(_title('A')), reason: s);
      expect(s, contains('사업장 1곳의 공고 권한을 확인하지 못해 빠져 있습니다'),
          reason: s);
    });

    testWidgets('SPQ-7 서버 거절과 네트워크 실패를 다르게 말한다', (t) async {
      // 앱은 A 를 허용으로 알지만 서버는 이미 회수했다(권한 재조회도 그대로).
      final denied = _Server(<String>{});
      final up1 = _SubP(assigned: ['A'], perms: {'A': _toPerm});
      await _pumpList(t, denied, up1);
      var s = _texts(t);
      expect(s, contains('공고 목록을 볼 권한이 확인되지 않았습니다'), reason: s);
      expect(s, isNot(contains('네트워크')), reason: s);
      expect(s, isNot(contains('등록된 공고가 없습니다')), reason: s);

      final offline = _Server({'A'})..failWith = 'unavailable';
      final up2 = _SubP(assigned: ['A'], perms: {'A': _toPerm});
      await _pumpList(t, offline, up2);
      s = _texts(t);
      expect(s, contains('네트워크 상태를 확인한 뒤 다시 시도해주세요'), reason: s);
      expect(s, isNot(contains('권한이 확인되지 않았습니다')), reason: s);
    });

    testWidgets('SPQ-7b 서버 거절 뒤 권한 재조회가 회수를 확인하면 남은 범위로 한 번 다시 묻는다',
        (t) async {
      final server = _Server({'A'});
      // 앱은 A·C 둘 다 허용으로 안다. 서버는 C 를 이미 회수했다.
      final up = _SubP(
          assigned: ['A', 'C'], perms: {'A': _toPerm, 'C': _toPerm});
      up.onAccessRefresh = () => up.perms['C'] = _wagePerm;
      final c = await _pumpList(t, server, up);
      expect(server.requests, [
        ['A', 'C'],
        ['A'],
      ]);
      expect(c.loadError, isNull);
      final s = _texts(t);
      expect(s, contains(_title('A')));
      expect(s, isNot(contains(_title('C'))));
    });

    testWidgets('SPQ-8 읽는 도중 권한 회수 → 늦은 응답의 그 사업장 결과를 커밋하지 않는다',
        (t) async {
      final server = _Server({'A', 'C'})..hold = Completer<void>();
      final up = _SubP(
          assigned: ['A', 'C'], perms: {'A': _toPerm, 'C': _toPerm});
      final c = await _pumpList(t, server, up);
      expect(server.requests, [
        ['A', 'C']
      ]);
      // 응답이 오기 전에 C 의 공고 권한이 회수됐다(구독 snapshot).
      //   서버 응답은 회수 **전에** 만들어졌다 — C 공고를 담은 성공 응답이 늦게 온다.
      up.perms['C'] = _wagePerm;
      up.changed();
      server.hold!.complete();
      server.hold = null;
      await _settle(t, 40);
      final s = _texts(t);
      expect(c.items.map((g) => g.businessId).toSet(), {'A'});
      expect(s, isNot(contains(_title('C'))), reason: s);
      expect(server.requests.last, ['A'], reason: '줄어든 범위로 한 번 더 확인한다');
    });

    testWidgets('SPQ-9 읽는 도중 권한 부여 → 끝난 뒤 늘어난 범위로 한 번 더 묻는다',
        (t) async {
      final server = _Server({'A', 'B'})..hold = Completer<void>();
      final up = _SubP(
          assigned: ['A', 'B'], perms: {'A': _toPerm, 'B': _wagePerm});
      final c = await _pumpList(t, server, up);
      up.perms['B'] = _toPerm;
      up.changed();
      server.hold!.complete();
      server.hold = null;
      await _settle(t, 40);
      expect(server.requests, [
        ['A'],
        ['A', 'B'],
      ]);
      expect(c.items.map((g) => g.businessId).toSet(), {'A', 'B'});
    });
  });

  // ════════════════════════════════════════════════════════════
  // B — 홈 조회 범위
  // ════════════════════════════════════════════════════════════

  group('SPH 홈 조회 범위', () {
    testWidgets('SPH-1 급여만 허용된 사업장 홈 — 명단·근태·준비 조회 0, 허용 조회는 유지',
        (t) async {
      final calls = _Calls();
      final up = _SubP(
          assigned: ['A', 'B'],
          perms: {'A': _toPerm, 'B': _wagePerm},
          selected: 'B');
      await _pumpHome(t, up, calls);
      expect(t.takeException(), isNull);
      expect(calls.count('roster'), 0, reason: '확정 명단은 canManageWorkers 가 필요하다');
      expect(calls.count('attendance'), 0);
      expect(calls.count('readiness'), 0, reason: '날인·사업주 문서는 공고 권한이 필요하다');
      // 서버가 이 사업장에서도 허용하는 조회는 그대로 나간다.
      expect(calls.of('summary'), ['B']);
      expect(calls.of('staffing'), ['B']);
      final s = _texts(t);
      expect(s, isNot(contains('출근 현황을 불러오지 못했습니다')), reason: s);
      expect(s, isNot(contains('출근 ')), reason: '권한 없는 구역은 그리지 않는다: $s');
    });

    testWidgets('SPH-2 공고·인력이 허용된 사업장 홈 — 기존 조회가 그대로 나간다',
        (t) async {
      final calls = _Calls();
      final up = _SubP(
          assigned: ['A', 'B'], perms: {'A': _toPerm, 'B': _wagePerm});
      await _pumpHome(t, up, calls);
      expect(calls.of('roster'), ['A']);
      expect(calls.of('attendance'), ['A']);
      expect(calls.of('readiness'), ['A']);
      expect(_texts(t), contains('출근 예정 전'));
    });

    testWidgets('SPH-3 A↔B 전환 — B 에서 금지 조회 0, A 값이 남지 않고, A 로 돌아오면 다시 읽는다',
        (t) async {
      final calls = _Calls();
      final up = _SubP(
          assigned: ['A', 'B'], perms: {'A': _toPerm, 'B': _wagePerm});
      await _pumpHome(t, up, calls);
      expect(_texts(t), contains('출근 예정 전'));

      up.switchTo('B');
      await _frames(t);
      expect(calls.of('roster'), ['A'], reason: 'B 로 바꾼 뒤 명단을 묻지 않는다');
      expect(calls.of('readiness'), ['A']);
      expect(calls.of('staffing'), ['A', 'B']);
      expect(_texts(t), isNot(contains('출근 예정 전')), reason: 'A 의 출근 값이 B 에 남으면 안 된다');

      up.switchTo('A');
      await _frames(t);
      expect(calls.of('roster'), ['A', 'A']);
      expect(calls.of('readiness').last, 'A');
      expect(_texts(t), contains('출근 예정 전'));
    });

    testWidgets('SPH-4 같은 사업장에서 권한이 바뀌면 그 loader 만 다시 돈다', (t) async {
      final calls = _Calls();
      final up = _SubP(assigned: ['B'], perms: {'B': _wagePerm});
      await _pumpHome(t, up, calls);
      expect(calls.count('roster'), 0);
      final staffingBefore = calls.count('staffing');

      // 인력 권한 부여 → 명단을 읽는다.
      up.perms['B'] = const MemberPermissions(
          canManageWage: true, canManageWorkers: true);
      up.changed();
      await _frames(t);
      expect(calls.of('roster'), ['B']);
      expect(calls.count('readiness'), 0, reason: '공고 권한은 그대로다');
      expect(calls.count('staffing'), staffingBefore, reason: '권한과 무관한 loader 는 다시 돌지 않는다');
      expect(_texts(t), contains('출근 예정 전'));

      // 회수 → 묻지 않고 값을 지운다.
      up.perms['B'] = _wagePerm;
      up.changed();
      await _frames(t);
      expect(calls.of('roster'), ['B']);
      expect(_texts(t), isNot(contains('출근 예정 전')));
    });

    testWidgets('SPH-5 권한 확인 전에는 묻지 않고, 확인되면 그때 읽는다', (t) async {
      final calls = _Calls();
      final up = _SubP(assigned: ['A'], perms: {'A': _toPerm}, loaded: false);
      await _pumpHome(t, up, calls);
      expect(calls.count('roster'), 0);
      expect(calls.count('readiness'), 0);
      up.loaded = true;
      up.changed();
      await _frames(t);
      expect(calls.of('roster'), ['A']);
      expect(calls.of('readiness'), ['A']);
    });

    testWidgets('SPH-6 소유자 홈은 기존과 같다', (t) async {
      final calls = _Calls();
      await _pumpHome(t, _OwnerP(['A']), calls);
      expect(calls.of('roster'), ['A']);
      expect(calls.of('attendance'), ['A']);
      expect(calls.of('readiness'), ['A']);
      expect(calls.of('summary'), ['*']);
    });
  });
}
