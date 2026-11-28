// [PERF impl_27a · L48 같은 꼴 · 2026-11-27] 돈·사람 처리 화면 5곳 — 처리 뒤 다시 읽기의 명단 유지(잠금) + 읽기 차례.
//
//   PW  급여 근무자 상세(_loadRecords)       — 새로고침 중 원장 유지·잠금·중간정산 메뉴 잠금 · 늦은 옛 원장이 새 원장을 덮지 않음 · 동치
//   SR  일정 변경 요청 다이얼로그(_loadRequests) — 다시 읽는 중 목록 유지·잠금 · 늦은 응답 · 동치(새로 연 화면과 같음)
//   MR  내 요청 다이얼로그(_loadAllNotifications) — 같은 세 가지
//   SRC 퇴사 요청·고정근무자 — 같은 꼴의 배선(차례 확인·유지 잠금)을 소스로 확인(이 두 화면은 읽기 경계가 Firestore 직접이라 화면 시험 대신)
// ignore_for_file: depend_on_referenced_packages
import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';

import 'package:ALfit/models/core/application_model.dart';
import 'package:ALfit/models/core/business_member_model.dart' show MemberPermissions;
import 'package:ALfit/models/core/id_card_access_request_model.dart';
import 'package:ALfit/models/core/interim_settlement_request_model.dart';
import 'package:ALfit/models/core/schedule_change_request_model.dart';
import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/providers/notification_provider.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/screens/business_admin/dialogs/schedule_request_management_dialog.dart';
import 'package:ALfit/screens/business_admin/payroll/payroll_worker_detail_screen.dart';
import 'package:ALfit/screens/user/dialogs/my_requests_dialog.dart';
import 'package:ALfit/screens/user/dialogs/my_requests_reads.dart';

import 'support/visible_text.dart';

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

class _Admin extends UserProvider {
  @override
  UserModel? get currentUser => UserModel(uid: 'owner1', username: 'o', name: '관리자', email: 'o@x.local',
      role: UserRole.BUSINESS_ADMIN, createdAt: DateTime(2026, 1, 1));
  @override
  bool get isBusinessAdmin => true;
  @override
  bool get isSubAdmin => false;
  @override
  bool can(bool Function(MemberPermissions p) c) => true;
  @override
  bool canForBusiness(String b, bool Function(MemberPermissions p) c) => true;
  @override
  PermissionCheck checkForBusiness(String businessId, bool Function(MemberPermissions p) check) =>
      PermissionCheck.allowed;
}

const _fnCh = 'dev.flutter.pigeon.cloud_functions_platform_interface.CloudFunctionsHostApi.call';

Future<void> _settle(WidgetTester t, [int n = 20]) async {
  for (var i = 0; i < n; i++) {
    await t.pump(const Duration(milliseconds: 50));
  }
}

String _texts(WidgetTester t) => t
    .widgetList<Text>(find.byType(Text))
    .map((w) => visibleText(w.data ?? w.textSpan?.toPlainText() ?? ''))
    .where((s) => s.isNotEmpty)
    .join(' | ');

bool _spinner(WidgetTester t) =>
    find.byWidgetPredicate((w) => w.runtimeType.toString() == 'LoadingWidget').evaluate().isNotEmpty;

bool _absorbingAbove(WidgetTester t, Finder f) => t
    .widgetList<AbsorbPointer>(find.ancestor(of: f.first, matching: find.byType(AbsorbPointer)))
    .any((w) => w.absorbing);

// ── PW ──────────────────────────────────────────────────────────────────────
Timestamp _kstMid(int d) =>
    Timestamp.fromMillisecondsSinceEpoch(DateTime.utc(2026, 9, d).millisecondsSinceEpoch - 9 * 3600 * 1000);
Map<String, dynamic> _att(String id, int d, String ws, int net) => {
      'id': id, 'userId': 'w1', 'applicationId': 'app_$id', 'businessId': 'b1', 'businessName': '사업장',
      'workDate': _kstMid(d), 'workType': '분류', 'createdAt': Timestamp.fromDate(DateTime(2026, 9, 1)),
      'status': 'present', 'wageStatus': ws, 'finalWage': net,
      'wageDetail': {
        'wageType': 'hourly', 'workMinutes': 480, 'totalAmount': net, 'netWage': net,
        'calculatedAt': Timestamp.fromDate(DateTime(2026, 9, 30)),
        'confirmedAt': Timestamp.fromDate(DateTime(2026, 9, 30)),
      },
    };

class _Ledger {
  List<Map<String, dynamic>> data;
  _Ledger(this.data);
  final gates = <Completer<void>>[];
  bool holdNext = false;
  Future<List<Map<String, dynamic>>> call(Map<String, dynamic> p) async {
    final snap = [for (final m in data) Map<String, dynamic>.from(m)];
    if (holdNext) {
      holdNext = false;
      final g = Completer<void>();
      gates.add(g);
      await g.future;
    }
    return snap;
  }
}

Future<void> _pumpPw(WidgetTester t) async {
  t.view.physicalSize = const Size(392, 1600);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(ChangeNotifierProvider<NotificationProvider>(
    create: (_) => NotificationProvider(),
    child: MaterialApp(
      home: PayrollWorkerDetailScreen(
          key: UniqueKey(), businessId: 'b1', workerId: 'w1', workerName: '합성', year: 2026, month: 9),
    ),
  ));
  await _settle(t, 10);
}

// ── SR ──────────────────────────────────────────────────────────────────────
Map<String, Object?> _ts(DateTime d) => {'_seconds': d.millisecondsSinceEpoch ~/ 1000, '_nanoseconds': 0};
Map<String, Object?> _scr(String id, String reason) => {
      'id': id, 'businessId': 'b1', 'applicationId': 'app-$id', 'applicantUid': 'u-$id', 'applicantName': '근로$id',
      'targetDate': _ts(DateTime(2026, 12, 1)), 'requestType': 'LEAVE', 'requestedBy': 'APPLICANT',
      'requestedByUid': 'u-$id', 'requestedAt': _ts(DateTime(2026, 11, 20)), 'reason': reason, 'status': 'PENDING',
    };

class _SrSrv {
  List<Map<String, Object?>> items;
  _SrSrv(this.items);
  final gates = <Completer<void>>[];
  bool holdNext = false;
  Future<ByteData?> handle(ByteData? data) async {
    final args = (const StandardMessageCodec().decodeMessage(data) as List).first as Map;
    final fn = args['functionName'] as String;
    Object? body;
    if (fn == 'callableGetScheduleChangeRequests') {
      final snap = [...items];
      if (holdNext) {
        holdNext = false;
        final g = Completer<void>();
        gates.add(g);
        await g.future;
      }
      body = {'items': snap};
    } else if (fn == 'callableGetUsersBatch') {
      final uids = ((args['parameters'] as Map)['uids'] as List).cast<String>();
      body = {
        'users': {for (final u in uids) u: {'name': 'N$u', 'username': u, 'role': 'USER'}}
      };
    } else {
      return const StandardMessageCodec().encodeMessage(<Object?>['unavailable', 'mock', null]);
    }
    return const StandardMessageCodec().encodeMessage(<Object?>[body]);
  }
}

Future<Future<void> Function()> _pumpSr(WidgetTester t, _SrSrv s) async {
  t.view.physicalSize = const Size(411, 1600);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  t.binding.defaultBinaryMessenger.setMockMessageHandler(_fnCh, s.handle);
  addTearDown(() => t.binding.defaultBinaryMessenger.setMockMessageHandler(_fnCh, null));
  late Future<void> Function() reload;
  await t.pumpWidget(ChangeNotifierProvider<UserProvider>(
    create: (_) => _Admin(),
    child: MaterialApp(
      home: Scaffold(
        body: ScheduleRequestManagementDialog(
            key: UniqueKey(), businessId: 'b1', onChanged: () {}, debugReloadHook: (f) => reload = f),
      ),
    ),
  ));
  await _settle(t);
  return reload;
}

// ── MR ──────────────────────────────────────────────────────────────────────
ScheduleChangeRequestModel _mreq(String id, String reason) => ScheduleChangeRequestModel(
      id: id, businessId: 'b1', applicationId: 'app-$id', applicantUid: 'me', applicantName: '나',
      targetDate: DateTime(2026, 12, 1), requestType: RequestType.LEAVE, requestedBy: RequesterType.APPLICANT,
      requestedByUid: 'me', requestedAt: DateTime(2026, 11, 20), reason: reason,
      status: RequestStatus.PENDING,
    );

class _MrReads {
  List<ScheduleChangeRequestModel> data;
  _MrReads(this.data);
  final gates = <Completer<void>>[];
  bool holdNext = false;
  MyRequestsReads build() => MyRequestsReads(
        scheduleChangeRequests: (uid) async {
          final snap = [...data];
          if (holdNext) {
            holdNext = false;
            final g = Completer<void>();
            gates.add(g);
            await g.future;
          }
          return snap;
        },
        pendingIdCardRequests: (uid) async => <IdCardAccessRequestModel>[],
        terminationRequests: (uid) async => <ApplicationModel>[],
        interimSettlements: () async => <InterimSettlementRequestModel>[],
      );
}

Future<Future<void> Function()> _pumpMr(WidgetTester t, _MrReads r) async {
  t.view.physicalSize = const Size(411, 1600);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  late Future<void> Function() reload;
  await t.pumpWidget(MaterialApp(
    home: Scaffold(
      body: MyRequestsDialog(
          key: UniqueKey(), applicantUid: 'me', onChanged: () {}, reads: r.build(),
          debugReloadHook: (f) => reload = f),
    ),
  ));
  await _settle(t);
  return reload;
}

String _src(String p) => File(p).readAsStringSync();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
  });
  tearDown(PayrollWorkerDetailScreenTestHooks.reset);

  group('PW 급여 근무자 상세', () {
    testWidgets('PW1 새로고침 중 원장 유지 · 진행 표시 · 잠금 · 중간정산 메뉴 잠금 → 새 원장', (t) async {
      final l = _Ledger([_att('a', 12, 'confirmed', 10000), _att('b', 13, 'confirmed', 20000)]);
      PayrollWorkerDetailScreenTestHooks.attendance = l.call;
      await _pumpPw(t);
      final before = _texts(t);
      expect(before, contains('2건'));
      l.holdNext = true;
      l.data = [_att('a', 12, 'transferred', 10000), _att('b', 13, 'confirmed', 20000)];
      await t.tap(find.byIcon(Icons.refresh_rounded));
      await t.pump(const Duration(milliseconds: 100));
      expect(_spinner(t), isFalse, reason: '새로고침이 원장을 지우고 스피너를 띄웠다');
      expect(find.byKey(const ValueKey('payroll-worker-refresh-after-mutation')), findsOneWidget);
      expect(_texts(t), before, reason: '새 원장이 앉기 전에 화면이 바뀌었다(미리 표시 0)');
      expect(_absorbingAbove(t, findVisibleText('2건')) || _absorbingAbove(t, findVisibleTextContaining('9/13')), isTrue);
      final menu = t.widget<PopupMenuButton<String>>(find.byType(PopupMenuButton<String>));
      expect(menu.enabled, isFalse, reason: '처리 전 원장으로 중간정산을 열 수 있다');
      l.gates.single.complete();
      await _settle(t, 10);
      expect(find.byKey(const ValueKey('payroll-worker-refresh-after-mutation')), findsNothing);
      expect(t.widget<PopupMenuButton<String>>(find.byType(PopupMenuButton<String>)).enabled, isTrue);
    });

    testWidgets('PW2 늦은 응답 — 먼저 시작한 옛 원장이 나중에 끝나도 새 원장 유지 · 동치(새로 연 화면과 같음)', (t) async {
      final l = _Ledger([_att('a', 12, 'confirmed', 10000)]);
      PayrollWorkerDetailScreenTestHooks.attendance = l.call;
      await _pumpPw(t);
      l.holdNext = true; // 옛 원장(1건)을 들고 멈춤
      await t.tap(find.byIcon(Icons.refresh_rounded));
      await t.pump(const Duration(milliseconds: 50));
      l.data = [_att('a', 12, 'confirmed', 10000), _att('b', 13, 'confirmed', 20000)];
      await t.tap(find.byIcon(Icons.refresh_rounded), warnIfMissed: false);
      await _settle(t, 10);
      final after2 = _texts(t);
      l.gates.single.complete();
      await _settle(t, 10);
      expect(_texts(t), after2, reason: '늦게 끝난 옛 원장이 새 원장을 덮었다');
      await _pumpPw(t);
      expect(_texts(t), after2, reason: '다시 읽은 최종 화면이 새로 연 화면과 다르다');
    });
  });

  group('SR 일정 변경 요청 다이얼로그', () {
    testWidgets('SR1 다시 읽는 중 목록 유지·잠금 → 새 목록 · 동치', (t) async {
      final s = _SrSrv([_scr('a', '사유-가'), _scr('b', '사유-나')]);
      final reload = await _pumpSr(t, s);
      expect(_texts(t), contains('사유-나'));
      s.holdNext = true;
      s.items = [_scr('a', '사유-가')];
      unawaited(reload());
      await t.pump(const Duration(milliseconds: 100));
      expect(_spinner(t), isFalse);
      expect(find.byKey(const ValueKey('schedule-request-refresh-after-mutation')), findsOneWidget);
      expect(_texts(t), contains('사유-나'));
      expect(_absorbingAbove(t, findVisibleTextContaining('사유-나')), isTrue);
      s.gates.single.complete();
      await _settle(t);
      final via = _texts(t);
      expect(via, isNot(contains('사유-나')));
      expect(find.byKey(const ValueKey('schedule-request-refresh-after-mutation')), findsNothing);
      await _pumpSr(t, _SrSrv([_scr('a', '사유-가')]));
      expect(_texts(t), via);
    });

    testWidgets('SR2 늦은 응답 — 옛 목록이 나중에 끝나도 새 목록 유지 · 잠금은 마지막 읽기가 끝날 때만 풀림', (t) async {
      final s = _SrSrv([_scr('a', '사유-가'), _scr('b', '사유-나')]);
      final reload = await _pumpSr(t, s);
      s.holdNext = true;
      unawaited(reload()); // 옛 목록(둘)을 들고 멈춤
      await t.pump(const Duration(milliseconds: 50));
      s.items = [_scr('a', '사유-가')];
      unawaited(reload());
      await _settle(t);
      expect(find.byKey(const ValueKey('schedule-request-refresh-after-mutation')), findsOneWidget,
          reason: '먼저 끝난 새 읽기가 아직 진행 중인 옛 읽기의 잠금을 풀었다');
      s.gates.single.complete();
      await _settle(t);
      expect(_texts(t), isNot(contains('사유-나')), reason: '늦게 끝난 옛 읽기가 새 목록을 덮었다');
      expect(find.byKey(const ValueKey('schedule-request-refresh-after-mutation')), findsNothing);
    });
  });

  group('MR 내 요청 다이얼로그', () {
    testWidgets('MR1 다시 읽는 중 목록 유지·잠금 → 새 목록 · 동치', (t) async {
      final r = _MrReads([_mreq('a', '사유-가'), _mreq('b', '사유-나')]);
      final reload = await _pumpMr(t, r);
      expect(_texts(t), contains('사유-나'));
      r.holdNext = true;
      r.data = [_mreq('a', '사유-가')];
      unawaited(reload());
      await t.pump(const Duration(milliseconds: 100));
      expect(_spinner(t), isFalse);
      expect(find.byKey(const ValueKey('my-requests-refresh-after-mutation')), findsOneWidget);
      expect(_absorbingAbove(t, findVisibleTextContaining('사유-나')), isTrue);
      r.gates.single.complete();
      await _settle(t);
      final via = _texts(t);
      expect(via, isNot(contains('사유-나')));
      await _pumpMr(t, _MrReads([_mreq('a', '사유-가')]));
      expect(_texts(t), via);
    });

    testWidgets('MR2 늦은 응답 — 옛 목록이 나중에 끝나도 새 목록 유지', (t) async {
      final r = _MrReads([_mreq('a', '사유-가'), _mreq('b', '사유-나')]);
      final reload = await _pumpMr(t, r);
      r.holdNext = true;
      unawaited(reload());
      await t.pump(const Duration(milliseconds: 50));
      r.data = [_mreq('a', '사유-가')];
      unawaited(reload());
      await _settle(t);
      r.gates.single.complete();
      await _settle(t);
      expect(_texts(t), isNot(contains('사유-나')), reason: '늦게 끝난 옛 읽기가 새 목록을 덮었다');
      expect(find.byKey(const ValueKey('my-requests-refresh-after-mutation')), findsNothing);
    });
  });

  group('SRC 같은 꼴 배선(퇴사 요청 · 고정근무자)', () {
    test('SRC1 퇴사 요청 — 차례 확인 뒤에만 앉고, 첫 읽기 뒤엔 목록 유지 잠금 · 겹친 읽기 잠금은 마지막이 끝날 때만', () {
      final s = _src('lib/screens/business_admin/dialogs/resign_request_management_dialog.dart');
      expect(s, contains('final gen = ++_loadGen;'));
      expect(s, contains('if (!mounted || gen != _loadGen) return;'));
      expect(s, contains('_hasLoadedOnce = true;'));
      expect(s, contains('child: isLoading && !_hasLoadedOnce'));
      expect(s, contains('absorbing: _reloadingKeepRows,'));
      expect(s, contains('if (_loadsInFlight > 0) return;'));
    });

    test('SRC2 고정근무자 — 같은 사업장의 정상 명단일 때만 유지 · 행동은 isLoading 으로 잠김 · 사업장 바꿈은 비우고 로딩', () {
      final s = _src('lib/screens/business_admin/dialogs/fixed_worker_management_dialog.dart');
      expect(s, contains('_rowsBizId != null && _rowsBizId == businessId && !_loadFailed;'));
      expect(s, contains('_rowsBizId = businessId;'));
      expect(s, contains(': isLoading && !_keepRowsWhileLoading'));
      expect(s, contains('absorbing: isLoading && _keepRowsWhileLoading,'));
      // 사업장을 바꾸면 명단을 비운다(DU539) — 다른 사업장 명단은 유지하지 않는다.
      expect(s, contains('_fixedWorkers = [];'));
      // 행동 버튼은 예전처럼 isLoading 으로 잠긴다.
      expect(s, contains('onTap: isLoading || _isProcessing || _showingStale ? null'));
    });
  });
}
