// [PAYROLL-BANNER-DUE-SCOPE] 급여 탭 배너 `오늘 처리할 송금 · … N건` 과 그 배너가 여는 목록이
//   **같은 급여 ID 집합**인가.
//
//   DEV 10-20 실측: 배너 `2건` → 눌러서 열린 `10월 20일 · 오늘` 날짜 화면 `0명`.
//   그 2건(JYAe 10-13·6HB9 10-18 지급 예정)은 이미 기한이 지나 `지급 예정일 == 오늘`
//   필터에 걸리지 않았다. 배너는 `≤ 오늘` 을 셌다.
//
//   배너(서비스 getTodayPaymentCount)와 도착 목록(전체 미이체 + 오늘까지 지급 예정)을
//   같은 가짜 서버에 붙여, 연체·오늘·미래·지급예정일 없음·0원·이체완료를 섞어 비교한다.
//   쓰기 버튼(이체처리·일괄)은 누르지 않는다.
import 'support/visible_text.dart';
import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';

import 'package:ALfit/models/core/attendance_model.dart';
import 'package:ALfit/models/core/business_model.dart';
import 'package:ALfit/screens/business_admin/payroll/payroll_overview_reads.dart';
import 'package:ALfit/screens/business_admin/payroll/payroll_overview_screen.dart';
import 'package:ALfit/models/core/business_member_model.dart' show MemberPermissions;
import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/providers/notification_provider.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/screens/business_admin/payroll/payroll_payment_dashboard_screen.dart';
import 'package:ALfit/services/payroll_payment_service.dart';
import 'package:ALfit/utils/format_helper.dart';
import 'package:ALfit/utils/payroll_due_scope.dart';

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

const _ch = 'dev.flutter.pigeon.cloud_functions_platform_interface.CloudFunctionsHostApi.call';
const _biz = 'BIZ';
const _kst = Duration(hours: 9);

/// KST 벽시계 → 절대 시각.
DateTime kst(int y, int m, int d, [int h = 0, int mi = 0, int s = 0, int ms = 0]) =>
    DateTime.utc(y, m, d, h, mi, s, ms).subtract(_kst);

Map<String, Object?> _ts(DateTime d) =>
    {'_seconds': d.millisecondsSinceEpoch ~/ 1000,
     '_nanoseconds': (d.millisecondsSinceEpoch % 1000) * 1000000};

/// 서버 attendance 한 건. 지급 예정일은 KST 날짜의 자정(저장 규칙)으로 둔다.
class _Rec {
  _Rec(this.id, this.uid, this.workDay, this.net,
      {this.wageStatus = 'confirmed', this.status = 'present', this.dueDay, this.finalWage});
  final String id, uid, wageStatus, status;
  final DateTime workDay; // KST 자정
  final DateTime? dueDay; // KST 자정
  final int net;
  final int? finalWage;
  Map<String, Object?> wire() => {
        'id': id, 'userId': uid, 'businessId': _biz, 'businessName': 'QA 사업장',
        'workDate': _ts(workDay), 'workType': 'QA', 'status': status,
        'wageStatus': wageStatus, 'adminConfirmed': true, 'createdAt': _ts(workDay),
        if (dueDay != null) 'paymentDueDate': _ts(dueDay!),
        if (finalWage != null) 'finalWage': finalWage,
        'wageDetail': {'totalAmount': net, 'wageType': 'daily'},
        'wageAccountSourceBankAccountVersion': 1,
        'wageAccountSourceBankbookDocumentVersion': 1,
        // V3 이체 스냅샷 4필드(가짜 값) — 있어야 `이체처리` 가 달린다(이전 방식 급여 아님).
        'wageAccountSnapshotVersion': 1,
        'wageAccountBankName': '테스트은행',
        'wageAccountNumberEncrypted': 'enc-test',
        'wageAccountHolder': '테스트',
        'wageAccountSnapshotAt': _ts(workDay),
      };
}

/// 가짜 서버가 받은 근태 조회 수.
int attendanceCalls = 0;

/// callableGetAdminAttendances(전 기간 구간)·이름·지급 준비만 답하는 가짜 서버.
///   [cap] 서버 상한(실제 10,000) — workDate 오름차순 앞 cap 건 + limitReached.
///   [failBeforeMs] 이 시각 이전에서 시작하는 구간 조회는 실패(구간 하나 실패).
///   [extraRaw] 읽을 수 없는 항목을 섞는다.
Future<ByteData?> Function(ByteData?) _server(List<_Rec> rows,
        {int cap = 10000, int? failBeforeMs, List<Map<String, Object?>> extraRaw = const []}) =>
    (data) async {
      final args = (const StandardMessageCodec().decodeMessage(data) as List).first as Map;
      final fn = args['functionName'] as String;
      final p = Map<Object?, Object?>.from(args['parameters'] as Map? ?? const {});
      Object? body;
      if (fn == 'callableGetAdminAttendances') {
        attendanceCalls++;
        final s = p['startMs'] as int?, e = p['endMs'] as int?, ws = p['wageStatus'] as String?;
        if (failBeforeMs != null && s != null && s < failBeforeMs) {
          return const StandardMessageCodec()
              .encodeMessage(<Object?>['unavailable', 'mock range failure', null]);
        }
        final hit = [
          for (final r in rows)
            if ((s == null || r.workDay.millisecondsSinceEpoch >= s) &&
                (e == null || r.workDay.millisecondsSinceEpoch < e) &&
                (ws == null || r.wageStatus == ws))
              r
        ]..sort((a, b) => a.workDay.compareTo(b.workDay));
        final limit = hit.length > cap;
        final firstChunk = s != null && s < DateTime(2021, 1, 1).millisecondsSinceEpoch;
        body = {
          'items': [
            for (final r in limit ? hit.sublist(0, cap) : hit) r.wire(),
            if (firstChunk) ...extraRaw,
          ],
          'limitReached': limit,
        };
      } else if (fn == 'callableGetUsersBatch') {
        body = {'users': {for (final u in (p['uids'] as List).cast<String>())
          u: {'name': 'N$u', 'username': u, 'role': 'USER'}}};
      } else if (fn == 'callableGetPayrollReadinessBatch') {
        body = {'readiness': {for (final u in (p['workerUids'] as List).cast<String>())
          u: {'ready': true, 'state': 'READY_AUTO', 'actor': 'NONE',
              'accountVersion': 1, 'bankbookVersion': 1}}, 'failed': <String>[]};
      } else {
        body = {'requests': <Object?>[], 'items': <Object?>[]};
      }
      return const StandardMessageCodec().encodeMessage(<Object?>[body]);
    };

/// 섞은 표본 — 기준 시각 2026-10-20(KST).
List<_Rec> _mixed() => [
      _Rec('overdue', 'U1', kst(2026, 10, 10), 51251, dueDay: kst(2026, 10, 13)),
      _Rec('yday', 'U2', kst(2026, 10, 17), 12000, dueDay: kst(2026, 10, 19)),
      _Rec('today', 'U3', kst(2026, 10, 19), 30000, dueDay: kst(2026, 10, 20)),
      _Rec('future', 'U4', kst(2026, 10, 19), 40000, dueDay: kst(2026, 10, 21)),
      _Rec('nodue', 'U5', kst(2026, 10, 15), 20000),
      _Rec('noshow0', 'U6', kst(2026, 10, 11), 0, status: 'NO_SHOW', finalWage: 0,
          dueDay: kst(2026, 10, 12)),
      _Rec('absent0', 'U6', kst(2026, 10, 12), 0, status: 'absent', finalWage: 0,
          dueDay: kst(2026, 10, 13)),
      _Rec('paid', 'U7', kst(2026, 10, 9), 70000, wageStatus: 'transferred',
          dueDay: kst(2026, 10, 12)),
    ];

typedef _Srv = Future<ByteData?> Function(ByteData?);

Future<int?> _bannerCount(WidgetTester? t, List<_Rec> rows, DateTime now, {_Srv? srv}) async {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMessageHandler(_ch, srv ?? _server(rows));
  return PayrollPaymentService()
      .getTodayPaymentCount(businessId: _biz, referenceDate: now);
}

Future<void> _mountList(WidgetTester t, List<_Rec> rows,
    {required bool dueByToday, _Srv? srv, UserProvider Function()? provider}) async {
  t.view.physicalSize = const Size(1080, 4000);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  t.binding.defaultBinaryMessenger.setMockMessageHandler(_ch, srv ?? _server(rows));
  addTearDown(() => t.binding.defaultBinaryMessenger.setMockMessageHandler(_ch, null));
  await t.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider<UserProvider>(create: (_) => (provider ?? _AdminP.new)()),
      ChangeNotifierProvider<NotificationProvider>(create: (_) => NotificationProvider()),
    ],
    child: MaterialApp(
      home: PayrollPaymentDashboardScreen(
        businessId: _biz, businessName: 'QA 사업장', year: 2026, month: 10,
        showAllOutstanding: true, outstandingDueByToday: dueByToday,
      ),
    ),
  ));
  for (var i = 0; i < 60; i++) {
    await t.pump(const Duration(milliseconds: 20));
  }
}

List<String> _texts() => find.byType(Text).evaluate()
    .map((e) => (e.widget as Text).data ?? '').toList();

/// 화면 카드에 보이는 근로자(이름 `N{uid}`).
Set<String> _cardUids() => {
      for (final s in _texts())
        if (RegExp(r'^NU\d$').hasMatch(s)) s.substring(1)
    };

AttendanceModel _model(_Rec r) {
  final m = Map<String, dynamic>.from(r.wire());
  m.remove('id');
  // 서비스와 같은 재수화 — {_seconds} → Timestamp 는 tryFromMap 이 받는 형태로.
  return AttendanceModel.tryFromMap(_hydrate(m), r.id)!;
}

Map<String, dynamic> _hydrate(Map<String, dynamic> m) => m.map((k, v) {
      if (v is Map && v.containsKey('_seconds')) {
        return MapEntry(k, Timestamp(v['_seconds'] as int, v['_nanoseconds'] as int));
      }
      if (v is Map) return MapEntry(k, _hydrate(Map<String, dynamic>.from(v)));
      return MapEntry(k, v);
    });

/// 버튼의 콜백(오래된 콜백 경로 재현용).
VoidCallback? _onPressedOf(ButtonStyleButton b) => b.onPressed;

/// 급여 권한이 거부된 관리자(멤버십 상실·권한 회수).
class _DeniedP extends _AdminP {
  @override
  PermissionCheck checkForBusiness(
          String businessId, bool Function(MemberPermissions p) check) =>
      PermissionCheck.denied;
}

const _unknownBannerText = '송금 대상을 끝까지 확인하지 못했어요 · 눌러서 다시 시도';

/// 급여 권한이 있는 관리자 — 개요 화면이 실제 판정 경로를 지나게 한다.
class _WageAdmin extends UserProvider {
  @override
  UserModel? get currentUser => UserModel(
      uid: 'admin1', username: 'admin1', name: '김관리', email: 'admin1@alfit.local',
      role: UserRole.BUSINESS_ADMIN, managedBusinessIds: const [_biz]);
  @override
  bool get isSubAdmin => false;
  @override
  String? get effectiveBusinessId => null;
  @override
  PermissionCheck checkCurrentBusiness(bool Function(MemberPermissions p) check) =>
      PermissionCheck.allowed;
  @override
  PermissionCheck checkForBusiness(
          String businessId, bool Function(MemberPermissions p) check) =>
      PermissionCheck.allowed;
  @override
  bool can(bool Function(MemberPermissions p) check) => true;
}

Future<void> _pumpOverview(WidgetTester t, Future<int?> Function() todayCount) async {
  t.view.physicalSize = const Size(390, 900);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  final reads = PayrollOverviewReads(
    businesses: ({required bool isSubAdmin, required String? effectiveBusinessId,
        required List<String> managedIds}) async => [
      BusinessModel(id: _biz, name: 'QA 사업장', ownerId: 'admin1',
          businessNumber: '000-00-00000', address: '서울시', category: '물류',
          subCategory: '창고', isApproved: true, createdAt: DateTime(2026, 1, 1)),
    ],
    payrollSummaries: ({required String businessId, required int year}) async => const [],
    adminAttendances: ({required String businessId, required String yearMonthGte,
        required String yearMonthLte}) async => (items: const <Map<String, dynamic>>[],
        limitReached: false),
    workerSummaries: (summaryId) async => const [],
    repairSummary: ({required String businessId, required String yearMonth}) async {},
    todayPaymentCount: (_) => todayCount(),
  );
  await t.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider<UserProvider>(create: (_) => _WageAdmin()),
      ChangeNotifierProvider<NotificationProvider>(create: (_) => NotificationProvider()),
    ],
    child: MaterialApp(home: PayrollOverviewScreen(reads: reads)),
  ));
  for (var i = 0; i < 20; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
  });
  tearDown(() => PayrollDueScope.debugNow = null);

  final noon20 = kst(2026, 10, 20, 12);

  group('PB-U 한 벌 조건(KST)', () {
    test('PB-U1 연체·어제·오늘만 — 미래·예정일 없음·노쇼/결근 0원·이체완료 제외', () {
      final ids = PayrollDueScope.dueByToday(_mixed().map(_model), noon20)
          .map((r) => r.id).toSet();
      expect(ids, {'overdue', 'yday', 'today'});
    });
    test('PB-U2 KST 자정 직전(23:59:59.999)엔 내일 예정 제외, 자정(00:00)엔 포함', () {
      final recs = _mixed().map(_model).toList();
      final before = PayrollDueScope.dueByToday(recs, kst(2026, 10, 20, 23, 59, 59, 999))
          .map((r) => r.id).toSet();
      final after = PayrollDueScope.dueByToday(recs, kst(2026, 10, 21))
          .map((r) => r.id).toSet();
      expect(before.contains('future'), isFalse);
      expect(after.contains('future'), isTrue);
      expect(after, {'overdue', 'yday', 'today', 'future'});
    });
    test('PB-U3 기기 시간대와 무관 — UTC 자정(=KST 09:00)도 같은 날로 본다', () {
      final r = _model(_Rec('x', 'U1', kst(2026, 10, 19), 1000,
          dueDay: DateTime.utc(2026, 10, 20))); // 저장 형식이 UTC 자정이어도
      expect(PayrollDueScope.isDueByToday(r, kst(2026, 10, 20, 0, 0, 1)), isTrue);
      expect(PayrollDueScope.isDueByToday(r, kst(2026, 10, 19, 23, 59, 59)), isFalse);
    });
  });

  group('PB-S 배너 숫자(서비스)', () {
    testWidgets('PB-S1 섞은 표본 — 배너 3건(연체·어제·오늘)', (t) async {
      expect(await _bannerCount(t, _mixed(), noon20), 3);
    });
    testWidgets('PB-S2 자정 전후 — 3 → 4', (t) async {
      expect(await _bannerCount(t, _mixed(), kst(2026, 10, 20, 23, 59, 59, 999)), 3);
      expect(await _bannerCount(t, _mixed(), kst(2026, 10, 21)), 4);
    });
  });

  // [PAYROLL-V3-CONNECTED 기대 갱신] 머리말 '오늘까지' → 조회 기준 KST 날짜('10월 20일까지') — 자정이 지나도
  //   새 조회 전에는 '오늘'이 아니므로 날짜로 말한다. 기준 시각 noon20 = 2026-10-20 KST.
  group('PB-W 배너 = 도착 목록', () {
    testWidgets('PB-W1 같은 ID 집합·건수·금액 (배너 3건 = 목록 3건 93,251원)', (t) async {
      PayrollDueScope.debugNow = () => noon20;
      final banner = await _bannerCount(t, _mixed(), noon20);
      await _mountList(t, _mixed(), dueByToday: true);
      expect(findVisibleText('10월 20일까지 지급 예정 미이체'), findsOneWidget);
      expect(findVisibleText('$banner건'), findsOneWidget);
      expect(findVisibleText(FormatHelper.formatWage(51251 + 12000 + 30000)), findsOneWidget);
      expect(_cardUids(), {'U1', 'U2', 'U3'}, reason: '미래(U4)·예정일 없음(U5)·0원(U6)·이체완료(U7) 없음');
    });
    testWidgets('PB-W2 KST 자정이 지나면 내일 예정이 목록에도 들어온다', (t) async {
      PayrollDueScope.debugNow = () => kst(2026, 10, 21, 0, 0, 1);
      await _mountList(t, _mixed(), dueByToday: true);
      expect(findVisibleText('4건'), findsOneWidget);
      expect(_cardUids(), {'U1', 'U2', 'U3', 'U4'});
    });
    testWidgets('PB-W3 DEV 모양(JYAe 51,251·6HB9 12,000 + 노쇼 0원 8건) → 2건 63,251원', (t) async {
      final rows = [
        _Rec('JYAe', 'U1', kst(2026, 10, 10), 51251, dueDay: kst(2026, 10, 13)),
        _Rec('6HB9', 'U2', kst(2026, 10, 17), 12000, dueDay: kst(2026, 10, 18)),
        for (var i = 0; i < 8; i++)
          _Rec('ns$i', 'U9', kst(2026, 10, 10 + (i % 5)), 0, status: 'NO_SHOW', finalWage: 0),
      ];
      final now = kst(2026, 10, 20, 21);
      PayrollDueScope.debugNow = () => now;
      expect(await _bannerCount(t, rows, now), 2);
      await _mountList(t, rows, dueByToday: true);
      expect(findVisibleText('2건'), findsOneWidget);
      expect(findVisibleText(FormatHelper.formatWage(63251)), findsOneWidget);
      expect(_cardUids(), {'U1', 'U2'});
    });
    testWidgets('PB-W4 해당 없음 — 0건 안내(배너 숫자 0과 같다)', (t) async {
      PayrollDueScope.debugNow = () => noon20;
      final rows = [_Rec('future', 'U4', kst(2026, 10, 19), 40000, dueDay: kst(2026, 10, 22))];
      expect(await _bannerCount(t, rows, noon20), 0);
      await _mountList(t, rows, dueByToday: true);
      expect(findVisibleText('오늘까지 지급할 미이체 급여가 없습니다'), findsOneWidget);
    });
  });

  group('PB-C 조회 완전성 — 일부를 전체처럼 보이지 않는다', () {
    /// 섞은 표본 + 연체 7건(근로자 U8, 서로 다른 날) — 상한 3 이면 여러 쪽이 필요하다.
    List<_Rec> big() => [
          ..._mixed(),
          for (var i = 0; i < 7; i++)
            _Rec('late$i', 'U8', kst(2026, 9, 1 + i), 1000, dueDay: kst(2026, 9, 5 + i)),
        ];
    testWidgets('PB-C1 상한 도달 → 끝까지 이어 조회 — 배너·목록 같은 ID·건수·금액', (t) async {
      PayrollDueScope.debugNow = () => noon20;
      attendanceCalls = 0;
      final banner = await _bannerCount(t, big(), noon20, srv: _server(big(), cap: 3));
      expect(banner, 3 + 7);
      expect(attendanceCalls, greaterThan(4), reason: '상한 때문에 같은 구간을 이어 물었다');
      await _mountList(t, big(), dueByToday: true, srv: _server(big(), cap: 3));
      expect(findVisibleText('10건'), findsOneWidget);
      expect(findVisibleText(FormatHelper.formatWage(51251 + 12000 + 30000 + 7000)), findsOneWidget);
      expect(_cardUids(), {'U1', 'U2', 'U3', 'U8'});
    });
    testWidgets('PB-C2 한 시각에 상한 초과(더 나아갈 수 없음) → 배너 모름, 목록 미완료 안내·숫자 없음', (t) async {
      PayrollDueScope.debugNow = () => noon20;
      final same = [
        for (var i = 0; i < 5; i++)
          _Rec('same$i', 'U$i', kst(2026, 10, 10), 1000, dueDay: kst(2026, 10, 12)),
      ];
      expect(await _bannerCount(t, same, noon20, srv: _server(same, cap: 3)), isNull);
      await _mountList(t, same, dueByToday: true, srv: _server(same, cap: 3));
      expect(findVisibleText('급여 정보를 끝까지 불러오지 못했습니다'), findsOneWidget);
      expect(findVisibleText('다시 시도'), findsOneWidget);
      expect(findVisibleText('오늘까지 지급할 미이체 급여가 없습니다'), findsNothing, reason: '모름 ≠ 0건');
      expect(findVisibleText('3건'), findsNothing, reason: '잘린 3건을 숫자로 보이지 않는다');
      expect(_cardUids(), isEmpty);
    });
    testWidgets('PB-C3 구간 하나 실패 → 배너 모름, 목록 실패 안내(0건 아님)', (t) async {
      PayrollDueScope.debugNow = () => noon20;
      final failOld = DateTime(2021, 1, 1).millisecondsSinceEpoch;
      expect(await _bannerCount(t, _mixed(), noon20,
          srv: _server(_mixed(), failBeforeMs: failOld)), isNull);
      await _mountList(t, _mixed(), dueByToday: true,
          srv: _server(_mixed(), failBeforeMs: failOld));
      expect(findVisibleText('급여 정보를 불러오지 못했습니다'), findsOneWidget);
      expect(findVisibleText('오늘까지 지급할 미이체 급여가 없습니다'), findsNothing);
      expect(_cardUids(), isEmpty, reason: '나머지 세 구간 결과만으로 목록을 만들지 않는다');
    });
    testWidgets('PB-C4 읽을 수 없는 급여 기록이 섞이면 미완료', (t) async {
      PayrollDueScope.debugNow = () => noon20;
      final bad = [<String, Object?>{'id': 'broken', 'userId': 'U9', 'wageStatus': 'confirmed'}];
      expect(await _bannerCount(t, _mixed(), noon20,
          srv: _server(_mixed(), extraRaw: bad)), isNull);
      await _mountList(t, _mixed(), dueByToday: true, srv: _server(_mixed(), extraRaw: bad));
      expect(findVisibleText('급여 정보를 끝까지 불러오지 못했습니다'), findsOneWidget);
    });
    testWidgets('PB-C5 정상 0건 — 배너 0(모름 아님), 목록 0건 안내(오류 아님)', (t) async {
      PayrollDueScope.debugNow = () => noon20;
      expect(await _bannerCount(t, const [], noon20), 0);
      await _mountList(t, const [], dueByToday: true);
      expect(findVisibleText('오늘까지 지급할 미이체 급여가 없습니다'), findsOneWidget);
      expect(findVisibleText('급여 정보를 불러오지 못했습니다'), findsNothing);
      expect(findVisibleText('급여 정보를 끝까지 불러오지 못했습니다'), findsNothing);
    });
    testWidgets('PB-C6 홈 전체 미이체도 상한을 넘어 끝까지 읽는다(의미 유지)', (t) async {
      PayrollDueScope.debugNow = () => noon20;
      await _mountList(t, big(), dueByToday: false, srv: _server(big(), cap: 3));
      expect(findVisibleText('전체 미이체'), findsOneWidget);
      expect(_cardUids(), {'U1', 'U2', 'U3', 'U4', 'U5', 'U8'});
    });
  });

  // [PERF-A1.F] 서버에 닿지 못한 조회 — 기기 실측 135초(.38 84초) 동안 '불러오는 중'만 보였다.
  //   선언된 30초가 연결 단계에는 걸리지 않았기 때문이다. 화면 쪽에서 같은 30초를 지킨다.
  group('PB-T 응답 없는 읽기는 30초에서 멈춘다', () {
    testWidgets('PB-T1 응답 없음 → 30초 직전엔 기다림, 넘으면 오류·다시 시도 → 회복 → 늦은 응답이 덮지 않음', (t) async {
      PayrollDueScope.debugNow = () => noon20;
      final pending = <Completer<void>>[];
      final normal = _server(_mixed());
      Future<ByteData?> hang(ByteData? data) async {
        final args = (const StandardMessageCodec().decodeMessage(data) as List).first as Map;
        if (args['functionName'] == 'callableGetAdminAttendances') {
          final c = Completer<void>();
          pending.add(c);
          await c.future; // 늦게 오는 응답 — 빈 목록
          return const StandardMessageCodec().encodeMessage(<Object?>[
            {'items': <Object?>[], 'limitReached': false}
          ]);
        }
        return normal(data);
      }

      await _mountList(t, _mixed(), dueByToday: true, srv: hang);
      expect(pending, isNotEmpty);
      await t.pump(PayrollPaymentService.readWait - const Duration(seconds: 3));
      expect(findVisibleText('급여 현황을 불러오지 못했습니다.'), findsNothing,
          reason: '아직 기다리는 중이다');
      await t.pump(const Duration(seconds: 4));
      await t.pump();
      expect(findVisibleText('급여 현황을 불러오지 못했습니다.'), findsOneWidget);
      expect(findVisibleText('다시 시도'), findsOneWidget);

      // 서버가 돌아왔다 — 다시 시도로 회복한다.
      t.binding.defaultBinaryMessenger.setMockMessageHandler(_ch, normal);
      await t.tap(findVisibleText('다시 시도'));
      for (var i = 0; i < 60; i++) {
        await t.pump(const Duration(milliseconds: 20));
      }
      expect(_cardUids(), {'U1', 'U2', 'U3'});
      expect(findVisibleText('급여 현황을 불러오지 못했습니다.'), findsNothing);

      // 처음 보낸 요청의 응답이 이제야 온다 — 회복한 화면을 빈 목록으로 덮지 않는다.
      for (final c in pending) {
        c.complete();
      }
      for (var i = 0; i < 30; i++) {
        await t.pump(const Duration(milliseconds: 20));
      }
      expect(_cardUids(), {'U1', 'U2', 'U3'});
      expect(findVisibleText('오늘까지 지급할 미이체 급여가 없습니다'), findsNothing);
    });
  });

  group('PB-X 진단·이전 목록 쓰기 차단', () {
    Future<void> settle(WidgetTester t) async {
      for (var i = 0; i < 60; i++) {
        await t.pump(const Duration(milliseconds: 20));
      }
    }

    /// 근로자 둘(오늘까지 지급 예정) — 지급 준비 READY 라 정상이면 `이체처리` 가 달린다.
    List<_Rec> two() => [
          _Rec('JYAe', 'U1', kst(2026, 10, 10), 51251, dueDay: kst(2026, 10, 13)),
          _Rec('6HB9', 'U2', kst(2026, 10, 17), 12000, dueDay: kst(2026, 10, 18)),
        ];

    testWidgets('PB-X1 읽을 수 없는 1건 — 집계 차단 + 재시도 후 확인 안내 + 참조 코드, 로그는 id·유형만', (t) async {
      PayrollDueScope.debugNow = () => noon20;
      final logs = <String>[];
      final prev = debugPrint;
      debugPrint = (String? m, {int? wrapWidth}) { if (m != null) logs.add(m); };
      final bad = [<String, Object?>{'id': 'BROKEN_20261012', 'userId': 'U9',
        'wageStatus': 'confirmed', 'accountNumber': '110-123-456789', 'workerName': '홍길동'}];
      try {
        await _mountList(t, two(), dueByToday: true, srv: _server(two(), extraRaw: bad));
      } finally {
        debugPrint = prev; // 테스트 본문 안에서 되돌린다(프레임워크 불변식 검사 전)
      }
      expect(findVisibleText('급여 정보를 끝까지 불러오지 못했습니다'), findsOneWidget);
      final guide = findVisibleTextContaining('읽을 수 없는 급여 기록 1건');
      expect(guide, findsOneWidget);
      final text = (guide.evaluate().single.widget as Text).data!;
      expect(text, contains('다시 시도해도 같으면 확인이 필요합니다'));
      final ref = RegExp(r'참조 ([0-9a-f]{6})').firstMatch(text)!.group(1)!;
      expect(_cardUids(), isEmpty, reason: '나머지 2건으로 숫자를 만들지 않는다');
      final diag = logs.where((l) => l.startsWith('[PAYROLL-INCOMPLETE]')).toList();
      expect(diag, isNotEmpty);
      expect(diag.first, contains('ref=$ref'));
      expect(diag.first, contains('BROKEN_20261012:'));
      expect(diag.join(), isNot(contains('110-123-456789')), reason: '계좌 미기록');
      expect(diag.join(), isNot(contains('홍길동')), reason: '이름 미기록');
    });

    testWidgets('PB-X2 새로고침 실패 → 이전 목록 표시·이전 조회 표시·쓰기 버튼 없음 → 재조회 성공 시 복구', (t) async {
      PayrollDueScope.debugNow = () => noon20;
      var mode = 'ok';
      final ok = _server(two());
      // 전 기간 구간 조회만 실패(월 조회 시작 10-01 은 통과) — 화면 전체 오류가 아니라 이전 목록이 남는 경로.
      final fail = _server(two(), failBeforeMs: DateTime(2026, 10, 1).millisecondsSinceEpoch);
      await _mountList(t, two(), dueByToday: true, srv: (d) => mode == 'ok' ? ok(d) : fail(d));
      // 이 표본(V3 스냅샷만, 지급준비 READY)에서 렌더되는 쓰기 입구는 통장사본 검토다.
      expect(findVisibleText('통장사본 보기'), findsNWidgets(2), reason: '정상 조회 — 쓰기 입구 있음');
      expect(find.byKey(const ValueKey('payroll-stale-notice')), findsNothing);
      mode = 'fail';
      await t.tap(find.byIcon(Icons.refresh_rounded).first);
      await settle(t);
      expect(find.byKey(const ValueKey('payroll-stale-notice')), findsOneWidget);
      expect(findVisibleText('새로고침에 실패해 이전 조회 결과를 보여주고 있어요'), findsOneWidget);
      expect(findVisibleText('10월 20일까지 지급 예정 미이체 · 이전 조회'), findsOneWidget);
      expect(_cardUids(), {'U1', 'U2'}, reason: '이전 목록은 보인다');
      expect(findVisibleText('이체처리'), findsNothing, reason: '이전 결과로 이체하지 않는다');
      expect(findVisibleText('통장사본 보기'), findsNothing, reason: '이전 결과로 검토 결정을 쓰지 않는다');
      expect(findVisibleText('지급정보 갱신'), findsNothing);
      // 다시 조회도 실패하면 여전히 막혀 있다
      await t.tap(findVisibleText('다시 조회'));
      await settle(t);
      expect(findVisibleText('이체처리'), findsNothing);
      // 완전한 재조회 성공 → 해제
      mode = 'ok';
      await t.tap(findVisibleText('다시 조회'));
      await settle(t);
      expect(find.byKey(const ValueKey('payroll-stale-notice')), findsNothing);
      expect(findVisibleText('10월 20일까지 지급 예정 미이체'), findsOneWidget);
      expect(findVisibleText('통장사본 보기'), findsNWidgets(2), reason: '완전한 재조회 뒤 다시 활성');
    });

    testWidgets('PB-X3 새로고침이 상한에서 멈춤(미완료) → 이전 목록·끝까지 못함 안내·쓰기 없음', (t) async {
      PayrollDueScope.debugNow = () => noon20;
      var capped = false;
      final ok = _server(two());
      final same = [for (var i = 0; i < 5; i++)
        _Rec('s$i', 'U$i', kst(2026, 10, 10), 1000, dueDay: kst(2026, 10, 12))];
      final cap = _server(same, cap: 3);
      await _mountList(t, two(), dueByToday: true, srv: (d) => capped ? cap(d) : ok(d));
      capped = true;
      await t.tap(find.byIcon(Icons.refresh_rounded).first);
      await settle(t);
      expect(findVisibleText('새로고침을 끝까지 하지 못해 이전 조회 결과를 보여주고 있어요'), findsOneWidget);
      expect(_cardUids(), {'U1', 'U2'}, reason: '잘린 새 결과(U0~U2)를 앉히지 않았다');
      expect(findVisibleText('이체처리'), findsNothing);
      expect(findVisibleText('통장사본 보기'), findsNothing);
    });

    testWidgets('PB-X4 새로고침에서 읽을 수 없는 기록 → 이전 목록 + 확인 안내·참조, 쓰기 없음', (t) async {
      PayrollDueScope.debugNow = () => noon20;
      var broken = false;
      final ok = _server(two());
      final bad = _server(two(), extraRaw: [<String, Object?>{'id': 'BROKEN_X', 'wageStatus': 'confirmed'}]);
      await _mountList(t, two(), dueByToday: true, srv: (d) => broken ? bad(d) : ok(d));
      broken = true;
      await t.tap(find.byIcon(Icons.refresh_rounded).first);
      await settle(t);
      expect(find.byKey(const ValueKey('payroll-stale-notice')), findsOneWidget);
      expect(findVisibleTextContaining('읽을 수 없는 급여 기록 1건'), findsOneWidget);
      expect(findVisibleText('이체처리'), findsNothing);
      expect(findVisibleText('통장사본 보기'), findsNothing);
    });

    testWidgets('PB-X5 정상 0건은 오류도 이전 목록도 아니다', (t) async {
      PayrollDueScope.debugNow = () => noon20;
      await _mountList(t, const [], dueByToday: true);
      expect(findVisibleText('오늘까지 지급할 미이체 급여가 없습니다'), findsOneWidget);
      expect(find.byKey(const ValueKey('payroll-stale-notice')), findsNothing);
      expect(findVisibleText('급여 정보를 끝까지 불러오지 못했습니다'), findsNothing);
    });
  });

  group('PB-O 급여 탭 배너', () {
    testWidgets('PB-O1 배너 조회 실패·미완료 → 숫자 대신 미완료 안내, 눌러서 다시 시도', (t) async {
      final answers = <int?>[null, 2];
      var calls = 0;
      await _pumpOverview(t, () async { calls++; return answers[calls - 1]; });
      expect(findVisibleText(_unknownBannerText), findsOneWidget);
      expect(findVisibleTextContaining('확정 급여'), findsNothing);
      await t.tap(findVisibleText(_unknownBannerText));
      for (var i = 0; i < 10; i++) {
        await t.pump(const Duration(milliseconds: 50));
      }
      expect(calls, 2);
      expect(findVisibleText('지급 예정일이 오늘 이하인 확정 급여 2건'), findsOneWidget);
      expect(findVisibleText(_unknownBannerText), findsNothing);
    });
    testWidgets('PB-O2 정상 0건 → 배너 없음(미완료 안내도 없음)', (t) async {
      await _pumpOverview(t, () async => 0);
      expect(findVisibleText(_unknownBannerText), findsNothing);
      expect(findVisibleTextContaining('확정 급여'), findsNothing);
    });
  });

  group('PB-H 홈 전체 미이체 의미 유지', () {
    testWidgets('PB-H1 홈 진입(필터 없음)은 미래·예정일 없음까지 보인다', (t) async {
      PayrollDueScope.debugNow = () => noon20;
      await _mountList(t, _mixed(), dueByToday: false);
      expect(findVisibleText('전체 미이체'), findsOneWidget);
      expect(_cardUids(), {'U1', 'U2', 'U3', 'U4', 'U5'},
          reason: '0원 노쇼·결근(U6)·이체완료(U7)만 빠진다 — 기존 의미');
    });
  });

  group('PB-N 배너 이동', () {
    test('PB-N1 배너 탭이 전체 미이체 + 오늘까지 지급 예정으로 연다', () {
      final src = File('lib/screens/business_admin/payroll/payroll_overview_screen.dart')
          .readAsStringSync();
      final i = src.indexOf('_TodayPaymentBanner(');
      final body = src.substring(i, src.indexOf('_loadTodayCount();', i));
      expect(body.contains('showAllOutstanding: true,'), isTrue);
      expect(body.contains('outstandingDueByToday: true,'), isTrue);
    });
    test('PB-N2 홈 이체 대기 진입은 배너 필터를 쓰지 않는다', () {
      final src = File('lib/screens/business_admin/business_admin_home_screen.dart')
          .readAsStringSync();
      expect(src.contains('outstandingDueByToday'), isFalse);
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // [PAYROLL-V3-CONNECTED] 배너 → 목록 → 갱신 실패 → 이전 목록 → 복구를 같은 근로자·같은 근태 id 로.
  //   가짜 서버(callable 채널)만 쓴다 — 실제 이체·서명 URL·DEV 호출 없음. '이체처리' 성공은 화면 기록일 뿐
  //   실제 은행 이체가 아니다.
  // ══════════════════════════════════════════════════════════════════════════
  group('PB-V 연결 흐름', () {
    Future<void> settle(WidgetTester t, [int n = 60]) async {
      for (var i = 0; i < n; i++) {
        await t.pump(const Duration(milliseconds: 20));
      }
    }

    // 세 근로자 — 카드마다 다른 쓰기 입구가 실제로 그려진다.
    //   U1 준비 완료(스냅샷 최신) → 통장사본 보기 + 이체처리
    //   U2 준비 완료, 계좌 버전이 바뀜(스냅샷 낡음) → 통장사본 보기 + 지급정보 갱신
    //   U3 통장사본 자동 판독 실패(사람 확인 필요) → 통장사본 확인만
    List<_Rec> three() => [
          _Rec('a-U1', 'U1', kst(2026, 10, 10), 51251, dueDay: kst(2026, 10, 13)),
          _Rec('a-U2', 'U2', kst(2026, 10, 15), 12000, dueDay: kst(2026, 10, 18)),
          _Rec('a-U3', 'U3', kst(2026, 10, 18), 30000, dueDay: kst(2026, 10, 20)),
        ];

    final readiness = <String, Map<String, Object?>>{
      'U1': {'ready': true, 'state': 'READY_AUTO', 'actor': 'NONE', 'accountVersion': 1, 'bankbookVersion': 1},
      'U2': {'ready': true, 'state': 'READY_AUTO', 'actor': 'NONE', 'accountVersion': 2, 'bankbookVersion': 1},
      'U3': {'ready': false, 'state': 'BANK_OCR_UNCERTAIN', 'actor': 'WORKER_OR_REVIEW', 'accountVersion': 1, 'bankbookVersion': 1},
    };

    /// 쓰기·열람 호출 기록 + 전 기간 구간 조회 실패/지연 + 이체 반영(처리한 id 는 다음 조회에서 빠진다).
    final writes = <String>[];
    final paid = <String>{};
    var fail = false;
    var delayMs = 0;
    setUp(() {
      writes.clear();
      paid.clear();
      fail = false;
      delayMs = 0;
    });
    Future<ByteData?> srv(ByteData? data) async {
      final args = (const StandardMessageCodec().decodeMessage(data) as List).first as Map;
      final fn = args['functionName'] as String;
      final p = Map<Object?, Object?>.from(args['parameters'] as Map? ?? const {});
      final rows = three();
      Object? body;
      switch (fn) {
        case 'callableGetAdminAttendances':
          final s = p['startMs'] as int?, e = p['endMs'] as int?, ws = p['wageStatus'] as String?;
          final range = s != null && s < DateTime(2026, 10, 1).millisecondsSinceEpoch; // 전 기간 구간
          if (range && delayMs > 0) await Future<void>.delayed(Duration(milliseconds: delayMs));
          if (range && fail) {
            return const StandardMessageCodec()
                .encodeMessage(<Object?>['unavailable', 'mock range failure', null]);
          }
          final hit = [
            for (final r in rows)
              if (!paid.contains(r.id) &&
                  (s == null || r.workDay.millisecondsSinceEpoch >= s) &&
                  (e == null || r.workDay.millisecondsSinceEpoch < e) &&
                  (ws == null || r.wageStatus == ws))
                r
          ]..sort((a, b) => a.workDay.compareTo(b.workDay));
          body = {'items': [for (final r in hit) r.wire()], 'limitReached': false};
        case 'callableGetUsersBatch':
          body = {'users': {for (final u in (p['uids'] as List).cast<String>())
            u: {'name': 'N$u', 'username': u, 'role': 'USER'}}};
        case 'callableGetPayrollReadinessBatch':
          body = {'readiness': {for (final u in (p['workerUids'] as List).cast<String>()) u: readiness[u]},
            'failed': <String>[]};
        case 'callableMarkTransferredBatch':
          final ids = (p['attendanceIds'] as List).cast<String>();
          writes.add('mark:${ids.join(',')}');
          paid.addAll(ids);
          body = {'processed': ids.length, 'skipped': <String>[], 'alreadyTransferred': <String>[]};
        case 'callableRefreshWagePaymentSnapshot':
          writes.add('refresh:${(p['attendanceIds'] as List).join(',')}');
          body = {'refreshed': p['attendanceIds'], 'skipped': <String, String>{}};
        case 'callableGetPayrollBankbookUrl':
          writes.add('bankbookUrl:${p['targetUid']}');
          body = {'signedUrl': ''}; // 빈 URL — 화면은 시트를 열지 않는다(원본 이미지 없음)
        case 'callableReviewPayrollBankDocument':
          writes.add('review:${p['targetUid']}');
          body = {'correctionOpened': false};
        default:
          body = {'requests': <Object?>[], 'items': <Object?>[]};
      }
      return const StandardMessageCodec().encodeMessage(<Object?>[body]);
    }

    VoidCallback? cb(String label) {
      final e = find.ancestor(of: findVisibleText(label), matching: find.byWidgetPredicate((w) => w is ButtonStyleButton));
      if (e.evaluate().isEmpty) return null;
      return _onPressedOf(e.evaluate().first.widget as ButtonStyleButton);
    }

    testWidgets('PB-V1 [P1·P6] 배너 3건 = 목록 3명 · 같은 근태 id·금액 · 세 쓰기 입구가 실제로 그려진다', (t) async {
      PayrollDueScope.debugNow = () => noon20;
      final banner = await _bannerCount(t, three(), noon20, srv: srv);
      await _mountList(t, three(), dueByToday: true, srv: srv);
      expect(banner, 3);
      expect(findVisibleText('$banner건'), findsOneWidget);
      expect(findVisibleText(FormatHelper.formatWage(51251 + 12000 + 30000)), findsOneWidget);
      expect(_cardUids(), {'U1', 'U2', 'U3'});
      expect(findVisibleText('이체처리'), findsOneWidget,
          reason: 'U1 — 준비 완료 카드에 이체 입구가 있다(62507e1 이후 통장사본 버튼에 가려졌던 것)');
      expect(findVisibleText('지급정보 갱신'), findsOneWidget, reason: 'U2');
      expect(findVisibleText('통장사본 보기'), findsNWidgets(2), reason: 'U1·U2');
      expect(findVisibleText('통장사본 확인'), findsOneWidget, reason: 'U3');
      expect(writes, isEmpty, reason: '열기만 했다 — 쓰기·열람 호출 0');
    });

    testWidgets('PB-V2 [P5] 갱신 실패 → 이전 목록: 네 버튼 없음 · 쥐고 있던 콜백도 호출 0 · 확인 창 없음', (t) async {
      PayrollDueScope.debugNow = () => noon20;
      await _mountList(t, three(), dueByToday: true, srv: srv);
      final mark = cb('이체처리'), refresh = cb('지급정보 갱신'), view = cb('통장사본 보기'), check = cb('통장사본 확인');
      expect([mark, refresh, view, check].every((x) => x != null), isTrue, reason: '정상 조회에서 입구를 쥔다');
      fail = true;
      await t.tap(find.byIcon(Icons.refresh_rounded).first);
      await settle(t);
      expect(find.byKey(const ValueKey('payroll-stale-notice')), findsOneWidget);
      expect(findVisibleText('10월 20일까지 지급 예정 미이체 · 이전 조회'), findsOneWidget);
      for (final l in ['이체처리', '지급정보 갱신', '통장사본 보기', '통장사본 확인']) {
        expect(findVisibleText(l), findsNothing, reason: '이전 결과의 $l');
      }
      mark!();
      refresh!();
      view!();
      check!(); // 이미 그려졌던 화면의 오래된 콜백 경로
      await settle(t, 20);
      expect(findVisibleText('이체 완료 처리'), findsNothing, reason: '확인 창도 뜨지 않는다');
      expect(writes, isEmpty, reason: '이체·갱신·열람·검토 호출 0');
    });

    testWidgets('PB-V3 [P5] 확인 창을 보는 사이 갱신이 실패하면 확인을 눌러도 이체·갱신 호출 0', (t) async {
      PayrollDueScope.debugNow = () => noon20;
      await _mountList(t, three(), dueByToday: true, srv: srv);
      // 이체처리 — 느린 새로고침이 진행 중(아직 이전 조회 아님)일 때 누른다.
      fail = true;
      delayMs = 600;
      await t.tap(find.byIcon(Icons.refresh_rounded).first);
      await t.pump(const Duration(milliseconds: 50));
      await t.tap(findVisibleText('이체처리'));
      await t.pump(const Duration(milliseconds: 50));
      expect(findVisibleText('이체 완료 처리'), findsWidgets, reason: '확인 창이 떴다');
      await settle(t); // 그 사이 갱신 실패 → 이전 조회
      await t.tap(findVisibleText('이체 완료 처리').last);
      await settle(t, 20);
      if (findVisibleText('건너뛰기').evaluate().isNotEmpty) {
        await t.tap(findVisibleText('건너뛰기'));
        await settle(t, 20);
      }
      expect(writes.where((w) => w.startsWith('mark:')), isEmpty, reason: '이전 조회 목록으로 이체하지 않는다');
      // 지급정보 갱신 — 복구 뒤 다시 느린 실패
      fail = false;
      delayMs = 0;
      await t.tap(findVisibleText('다시 조회'));
      await settle(t);
      expect(findVisibleText('지급정보 갱신'), findsOneWidget);
      fail = true;
      delayMs = 600;
      await t.tap(find.byIcon(Icons.refresh_rounded).first);
      await t.pump(const Duration(milliseconds: 50));
      await t.tap(findVisibleText('지급정보 갱신'));
      await t.pump(const Duration(milliseconds: 50));
      await settle(t);
      await t.tap(findVisibleText('갱신').last);
      await settle(t, 20);
      expect(writes, isEmpty, reason: '이체·갱신 호출 0');
    });

    testWidgets('PB-V4 [P6·P7] 완전 재조회 뒤 복구 · 연타해도 이체 1회 · 처리한 건은 다음 목록에서 빠진다', (t) async {
      PayrollDueScope.debugNow = () => noon20;
      await _mountList(t, three(), dueByToday: true, srv: srv);
      fail = true;
      await t.tap(find.byIcon(Icons.refresh_rounded).first);
      await settle(t);
      expect(findVisibleText('이체처리'), findsNothing);
      fail = false;
      await t.tap(findVisibleText('다시 조회'));
      await settle(t);
      expect(find.byKey(const ValueKey('payroll-stale-notice')), findsNothing);
      expect(findVisibleText('10월 20일까지 지급 예정 미이체'), findsOneWidget);
      final mark = cb('이체처리')!;
      mark();
      mark(); // 같은 프레임 연타
      await t.pump(const Duration(milliseconds: 50));
      await t.tap(findVisibleText('이체 완료 처리').last);
      await settle(t, 20);
      await t.tap(findVisibleText('건너뛰기'));
      await settle(t);
      expect(writes.where((w) => w.startsWith('mark:')).toList(), ['mark:a-U1'],
          reason: '같은 근태 id 로 정확히 1회');
      expect(_cardUids(), {'U2', 'U3'}, reason: '처리한 U1 은 다음 완전 조회에서 빠진다');
    });

    testWidgets('PB-V5 [P2] 열린 채 KST 자정이 지나도 다시 그리기만으로는 대상이 바뀌지 않는다 · 새 조회가 날짜를 바꾼다', (t) async {
      var now = kst(2026, 10, 20, 23, 59, 30);
      PayrollDueScope.debugNow = () => now;
      await _mountList(t, _mixed(), dueByToday: true);
      expect(findVisibleText('10월 20일까지 지급 예정 미이체'), findsOneWidget);
      expect(_cardUids(), {'U1', 'U2', 'U3'});
      now = kst(2026, 10, 21, 0, 0, 30);
      t.element(find.byType(PayrollPaymentDashboardScreen)).markNeedsBuild();
      await t.pump();
      expect(_cardUids(), {'U1', 'U2', 'U3'}, reason: '조회 없이 다시 그리기 — 기준 날짜(10-20) 그대로');
      expect(findVisibleText('10월 20일까지 지급 예정 미이체'), findsOneWidget);
      await t.tap(find.byIcon(Icons.refresh_rounded).first);
      await settle(t);
      expect(findVisibleText('10월 21일까지 지급 예정 미이체'), findsOneWidget);
      expect(_cardUids(), {'U1', 'U2', 'U3', 'U4'}, reason: '새 조회의 기준 — 10-21 예정(U4) 포함');
    });

    testWidgets('PB-V6 [P2·P7] 배너 — 늦게 끝난 옛 조회가 새 숫자를 덮지 않는다', (t) async {
      final answers = <Future<int?> Function()>[
        () async => null, // 첫 조회 실패 → 다시 시도 배너
        () => Future<int?>.delayed(const Duration(milliseconds: 600), () => 3), // 느린 옛 조회
        () => Future<int?>.delayed(const Duration(milliseconds: 50), () => 4), // 빠른 새 조회
      ];
      var calls = 0;
      await _pumpOverview(t, () => answers[calls++]());
      await t.tap(findVisibleText(_unknownBannerText));
      await t.pump(const Duration(milliseconds: 10));
      await t.tap(findVisibleText(_unknownBannerText));
      for (var i = 0; i < 20; i++) {
        await t.pump(const Duration(milliseconds: 50));
      }
      expect(calls, 3);
      expect(findVisibleText('지급 예정일이 오늘 이하인 확정 급여 4건'), findsOneWidget);
      expect(findVisibleText('지급 예정일이 오늘 이하인 확정 급여 3건'), findsNothing);
    });

    testWidgets('PB-V7 [P8] 급여 권한이 거부되면 목록·쓰기 입구 없음 — 조회 상태와 무관', (t) async {
      PayrollDueScope.debugNow = () => noon20;
      await _mountList(t, three(), dueByToday: true, srv: srv, provider: _DeniedP.new);
      expect(findVisibleText('접근 권한이 없습니다'), findsOneWidget);
      for (final l in ['이체처리', '지급정보 갱신', '통장사본 보기', '통장사본 확인']) {
        expect(findVisibleText(l), findsNothing);
      }
      expect(writes, isEmpty);
    });
  });

  // [.81 MONTH-PENDING-SCOPE] 월 상세 `미이체 N건` → `지급 현황` 이 같은 집합을 여는가.
  //   DEV 11-04 재현: 10월 상세 `미이체 2건` → 지급 현황 `2026년 11월 4일 · 오늘` · `미이체 0명`(탭 배지 2).
  //   날짜 보기는 `지급 예정일 == 선택일` 이라 지난 예정일 건이 빠진다.
  group('PB-M 월 상세 지급 현황 = 그 달 미이체', () {
    Future<void> mountMonth(WidgetTester t, {required bool wholeMonth}) async {
      t.view.physicalSize = const Size(1080, 4000);
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.reset);
      t.binding.defaultBinaryMessenger.setMockMessageHandler(_ch, _server(_mixed()));
      addTearDown(() => t.binding.defaultBinaryMessenger.setMockMessageHandler(_ch, null));
      await t.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<UserProvider>(create: (_) => _AdminP()),
          ChangeNotifierProvider<NotificationProvider>(create: (_) => NotificationProvider()),
        ],
        child: MaterialApp(
          home: PayrollPaymentDashboardScreen(
            businessId: _biz, businessName: 'QA 사업장', year: 2026, month: 10,
            pendingWholeMonth: wholeMonth,
          ),
        ),
      ));
      for (var i = 0; i < 60; i++) {
        await t.pump(const Duration(milliseconds: 20));
      }
    }

    // 이체 가능한 10월 미이체 = 연체·어제·당일·미래·예정일 없음(0원 노쇼·결근·이체 완료 제외)
    const monthPayable = {'U1', 'U2', 'U3', 'U4', 'U5'};

    testWidgets('PB-M1 날짜 보기(기존 진입)는 오늘 지급 예정만 — 지난 예정일 건은 목록에 없다', (t) async {
      await mountMonth(t, wholeMonth: false);
      expect(_cardUids().intersection({'U1', 'U2'}), isEmpty,
          reason: '날짜 보기는 지급 예정일 == 오늘(실제 시계)만 보인다');
      expect(findVisibleTextContaining('월 근무 · 미이체 전체'), findsNothing);
    });

    testWidgets('PB-M2 월 범위 진입은 그 달 미이체 전체를 보이고 범위를 말한다', (t) async {
      await mountMonth(t, wholeMonth: true);
      expect(_cardUids(), monthPayable);
      expect(findVisibleTextContaining('2026년 10월 근무 · 미이체 전체'), findsOneWidget);
      expect(findVisibleTextContaining('이체할 내역이 없습니다'), findsNothing);
    });

    test('PB-M3 월 상세 `지급 현황` 버튼만 월 범위로 연다', () {
      final src = File('lib/screens/business_admin/payroll/payroll_overview_screen.dart')
          .readAsStringSync().replaceAll('\r\n', '\n');
      expect('pendingWholeMonth: true,'.allMatches(src).length, 1);
      final i = src.indexOf('pendingWholeMonth: true,');
      expect(src.substring(i - 260, i).contains('month: widget.summary.month,'), isTrue);
    });
  });

}
