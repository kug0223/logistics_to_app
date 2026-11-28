// [ALFIT-E1-AVAILABILITY-SHEET-INTEGRATION-AND-EXPIRY-READ-GATE.1]
//
//   S  가능일 시트 경로(7oZZ 카나리아가 실제로 쓸 경로) — 실제 위젯 트리:
//        TOGroupCard(펼침, 대기 0) → 업무 행 → WorkApplicantsDialog
//          → `인력 초대` → `근무 가능 인력` → AvailableWorkersBottomSheet
//          → `근무 제안` → `제안 보내기`
//          → **실제** AvailableWorkersService.inviteWorker → (플랫폼 채널) callableInviteWorker 성공
//          → **실제** E1DebugFault 주입(성공 직후 1회 deadline-exceeded)
//          → **실제** InviteSaveVerifier(→ fetchApplicationsByBizPaged → 채널) 확인
//          → `제안 보냄` · 성공 콜백 → 시트 닫힘 → 업무별 창 재조회 → 창 닫힘 → 카드 대기 1
//      서비스·확인 조회는 주입하지 않는다 — Cloud Functions 플랫폼 채널만 모의 서버로 답한다.
//      서버 응답 행·원장 수치는 로컬 에뮬레이터 실제 번들의 것(fixture).
//
//   N  notSaved 와 unknown 의 버튼 — 직접 초대 창과 시트 각각.
//
//   증거 등급: 로컬 위젯 + 에뮬레이터 응답 fixture. DEV 호출이 아니다.
//   직접 초대 창의 E1-W3 검증은 e1_w3_parent_refresh_test 에 따로 있다.
import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/visible_text.dart'; // [DU255] keepWords 문구는 보이는 글자로 찾는다
import 'package:firebase_core/firebase_core.dart';
// ignore: depend_on_referenced_packages
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
// ignore: depend_on_referenced_packages
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';

import 'package:ALfit/controllers/workforce_controller.dart';
import 'package:ALfit/models/core/application_model.dart';
import 'package:ALfit/models/core/attendance_model.dart';
import 'package:ALfit/models/core/business_member_model.dart' show MemberPermissions;
import 'package:ALfit/models/core/slot_model.dart' show SlotModel, SlotStatus;
import 'package:ALfit/models/core/to_model.dart';
import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/models/core/work_detail_data.dart';
import 'package:ALfit/models/ui/admin_to_list_ui_models.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/screens/business_admin/dialogs/available_workers_bottom_sheet.dart';
import 'package:ALfit/screens/business_admin/dialogs/invite_worker_dialog.dart';
import 'package:ALfit/screens/business_admin/dialogs/to_list_dialogs.dart';
import 'package:ALfit/screens/business_admin/dialogs/work_applicants_dialog.dart';
import 'package:ALfit/screens/business_admin/dialogs/work_applicants_reads.dart';
import 'package:ALfit/services/contract_service.dart';
import 'package:ALfit/services/firestore_service.dart';
import 'package:ALfit/services/invite_save_verifier.dart';
import 'package:ALfit/utils/e1_debug_fault.dart';
import 'package:ALfit/utils/navigation_key.dart';
import 'package:ALfit/widgets/admin/cards/admin_to_group_card.dart';
import 'package:ALfit/widgets/admin/cards/admin_work_detail.dart';
import 'package:ALfit/utils/staffing_clock.dart';

/// [E1-FIXTURE-CLOCK] 픽스처 캡처 시각(capturedAt 2026-10-16 18:20:16 KST) 1분 뒤로 고정한다.
///   초대 유효(만료 10/17 18:20:16)·근무 시작 전(10/18 14:00)·슬롯 열림 — 시나리오가 전제한 상태다.
///   실행 날짜와 무관하게 같은 판정을 받는다. 호스트·기기 시계는 바꾸지 않는다.
final DateTime _e1Now = DateTime.utc(2026, 10, 16, 9, 21, 16);


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
  bool can(bool Function(MemberPermissions p) check) => true;
  @override
  bool canForBusiness(String businessId, bool Function(MemberPermissions p) check) =>
      true;
  @override
  PermissionCheck checkForBusiness(
          String businessId, bool Function(MemberPermissions p) check) =>
      PermissionCheck.allowed;
}

// ── 에뮬레이터 fixture ─────────────────────────────────────────────────────
final Map<String, dynamic> _fx = jsonDecode(
        File('test/fixtures/e1_emulator_ambiguous.json').readAsStringSync())
    as Map<String, dynamic>;
List<Map<String, dynamic>> _rows(String k1, String k2) =>
    ((_fx[k1] as Map)[k2] as List).cast<Map>().map(Map<String, dynamic>.from).toList();
Map<String, dynamic> get _ledger =>
    Map<String, dynamic>.from((_fx['saved'] as Map)['ledger'] as Map);

dynamic _hydrate(dynamic v) {
  if (v is Map) {
    final m = Map<String, dynamic>.from(v);
    if (m.containsKey('_seconds')) {
      return Timestamp((m['_seconds'] as num).toInt(),
          (m['_nanoseconds'] as num? ?? 0).toInt());
    }
    return m.map((k, x) => MapEntry(k, _hydrate(x)));
  }
  if (v is List) return v.map(_hydrate).toList();
  return v;
}

List<ApplicationModel> _parse(List<Map<String, dynamic>> rows) => rows
    .map((m) {
      final raw = Map<String, dynamic>.from(_hydrate(m) as Map);
      final id = raw.remove('id') as String? ?? '';
      return ApplicationModel.tryFromMap(raw, id);
    })
    .whereType<ApplicationModel>()
    .toList();

final DateTime _workDate = _parse(_rows('saved', 'post')).single.workDate;

WorkDetailData _wd() => WorkDetailData(
      wdId: 'wd1', workType: 'QA', startTime: '14:00', endTime: '15:00',
      requiredCount: 2, wage: 12000, wageType: 'hourly',
      applicationDeadline: _e1Now.add(const Duration(days: 1)),
    );

TOModel _to() => TOModel(
      id: 'TO', businessId: 'BIZ', businessName: 'biz', type: 'flex',
      title: 'E1 공고', creatorUID: 'OWNER', status: 'ACTIVE',
      workDetails: const [], totalRequired: 2, totalConfirmed: 0,
      totalPending: 0, isPublished: true, publishMode: 'immediate',
      createdAt: _e1Now.subtract(const Duration(days: 2)),
      statusUpdatedAt: _e1Now.subtract(const Duration(days: 2)),
    );

TOItem _slot() => TOItem(
      to: _to(),
      slot: SlotModel(
        id: 'S', toId: 'TO', date: _workDate, status: SlotStatus.open,
        workDetails: [_wd()],
        createdAt: _e1Now.subtract(const Duration(days: 2)),
      ),
      confirmedCount: 0, pendingCount: 0, totalRequired: 2,
    );

const _channel =
    'dev.flutter.pigeon.cloud_functions_platform_interface.CloudFunctionsHostApi.call';

/// Cloud Functions 플랫폼 채널 뒤의 모의 서버. 앱 코드는 실제 서비스를 탄다.
class _Server {
  bool committed = false;
  bool commitOnInvite = true;     // false = 서버가 저장하지 못했다
  bool verifyFails = false;       // 저장 확인 조회 실패(unknown)
  bool listFailsAfterSend = false;
  bool lateVisible = false;       // 첫 확인 조회에는 아직 안 보인다(notSaved)
  bool alreadyExistsOnResend = true;
  int inviteCalls = 0;
  int verifyCalls = 0;
  int candidateCalls = 0;
  final calls = <String>[];

  List<Map<String, dynamic>> _visible() =>
      committed ? _rows('saved', 'post') : const [];

  Future<ByteData?> handle(ByteData? message) async {
    final args = (const StandardMessageCodec().decodeMessage(message) as List)
        .first as Map;
    final name = args['functionName'] as String;
    final params = Map<String, dynamic>.from((args['parameters'] as Map?) ?? {});
    calls.add(name);
    Object? ok(Object? r) => <Object?>[r];
    Object? err(String code) => <Object?>[code, 'mock $code', <String, Object?>{'code': code, 'message': 'mock $code'}];
    Object? reply;
    switch (name) {
      case 'callableGetAvailableWorkers':
        candidateCalls++;
        // 서버는 INVITED 가 있는 근로자를 그 슬롯 후보에서 뺀다.
        reply = ok({
          'candidates': committed
              ? <Object?>[]
              : <Object?>[{'uid': 'W', 'maskedName': '근*W', 'city': '평택시'}],
          'hasMore': false, 'poolComplete': true, 'weeklyContextAvailable': false,
        });
      case 'callableInviteWorker':
        inviteCalls++;
        expect(params['targetUid'], 'W');
        expect(params['slotId'], 'S');
        if (committed) {
          reply = alreadyExistsOnResend ? err('already-exists') : ok({'success': true});
        } else {
          if (commitOnInvite) committed = true;
          reply = commitOnInvite
              ? ok({'success': true, 'applicationId': 'TO_S_wd1_W'})
              : err('internal');
        }
      case 'callableGetApplicationsByBiz':
        verifyCalls++;
        expect(params['purpose'], 'applicantReview');
        expect(params['uid'], 'W');
        if (verifyFails) {
          reply = err('unavailable');
        } else if (lateVisible && verifyCalls == 1) {
          reply = ok({'applications': <Object?>[], 'hasMore': false});
        } else {
          reply = ok({'applications': _visible(), 'hasMore': false});
        }
      default:
        reply = err('unavailable');
    }
    return const StandardMessageCodec().encodeMessage(reply);
  }

  Future<Map<String, dynamic>> capacity() async {
    final stats = {'wd1': {'confirmed': 0, 'pending': 0}};
    FirestoreService.tallyWorkDetailSeats(
        stats, committed ? _parse(_rows('saved', 'capacity')) : const [],
        slotId: 'S', seatDay: _e1Now);
    return {'workDetails': [_wd()], 'workStats': stats, 'statsFailed': false};
  }

  WorkApplicantsReads reads() => WorkApplicantsReads(
        applications: (to, {slotId, required purpose}) async {
          if (committed && listFailsAfterSend) {
            throw FirebaseFunctionsException(message: 'unavailable', code: 'unavailable');
          }
          return _parse(_visible());
        },
        usersBatch: (uids, {required businessId, purpose}) async => {
          for (final u in uids)
            u: UserModel(uid: u, username: u, name: '근로$u',
                email: '$u@test.local', role: UserRole.USER),
        },
        weeklyAttendance: ({required businessId, required weekStart,
                required weekEnd}) async =>
            <String, List<AttendanceModel>>{},
        contractStatusBatch: (ids, {required businessId}) async =>
            const ContractStatusBatch(),
        hasWorkedMap: ({required businessId, required date}) async => const {},
        idCardStatusBatch: ({required requesterId, required targetUserIds}) async =>
            const {},
        capacity: (to, {slotId, slotWorkDetails}) => capacity(),
        reassignProposals: (bizId) async => const [],
      );
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
    ].where((s) => s.isNotEmpty).join(' | ');

String? _statAfter(WidgetTester t, String label) {
  final all = t.widgetList<Text>(find.byType(Text)).map((w) => w.data).toList();
  final i = all.indexOf(label);
  return i < 0 ? null : all[i + 1];
}

class _Card {
  _Card(this.server);
  final _Server server;
  late final TOItem slot = _slot();
  late final WorkforceController controller = WorkforceController(
      loadWorkDetailStats: (to, {slotId, slotWorkDetails}) => server.capacity());
  int parentRefreshes = 0;

  Future<void> pump(WidgetTester t) async {
    t.view.physicalSize = const Size(411, 1600);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    addTearDown(controller.dispose);
    WorkApplicantsReads.debugOverride = server.reads();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler(_channel, server.handle);
    await controller.loadWorkDetails(slot);
    final group = TOGroupItem(singleTO: _to())
      ..setGroupTOs([slot])
      ..setSlotDates([_workDate]);
    final svc = FirestoreService();
    await t.pumpWidget(ChangeNotifierProvider<UserProvider>(
      create: (_) => _AdminP(),
      child: MaterialApp(
        navigatorKey: navigatorKey,
        home: Scaffold(
          body: SingleChildScrollView(
            child: AnimatedBuilder(
              animation: controller,
              builder: (ctx, _) => TOGroupCard(
                groupItem: group,
                firestoreService: svc,
                onRetryWorkDetailStats: controller.loadWorkDetails,
                onRetryGroupWorkDetailStats: controller.loadGroupWorkDetailStats,
                dialogs: TOListDialogs(
                    context: ctx, firestoreService: svc, onChanged: () {}),
                onChanged: () {
                  parentRefreshes++;
                  slot.resetWorkDetailLoad();
                  controller.loadWorkDetails(slot);
                },
                isExpanded: true,
                expandedTOs: const <String>{},
                onToggleExpand: () {},
                onToggleTOExpand: (_) {},
              ),
            ),
          ),
        ),
      ),
    ));
    await _settle(t, 10);
  }
}

Future<void> _openWorkDialog(WidgetTester t) async {
  final row = find.byType(WorkDetailRow);
  await t.ensureVisible(row);
  await t.tap(row);
  await _settle(t);
  expect(find.byType(WorkApplicantsDialog), findsOneWidget);
}

Future<void> _openSheet(WidgetTester t) async {
  await t.tap(findVisibleTextContaining('근무 초대').first);
  await _settle(t);
  await t.tap(find.text('근무 가능 인력'));
  await _settle(t, 40);
  expect(find.byType(AvailableWorkersBottomSheet), findsOneWidget);
}

Future<void> _propose(WidgetTester t) async {
  expect(find.text('근*W'), findsOneWidget, reason: '후보가 보여야 한다');
  await t.tap(find.widgetWithText(OutlinedButton, '근무 제안'));
  await _settle(t);
  await t.tap(find.text('제안 보내기'));
  await _settle(t, 40);
}

Future<void> _closeSheet(WidgetTester t) async {
  await t.binding.handlePopRoute();
  await _settle(t, 40);
  expect(find.byType(AvailableWorkersBottomSheet), findsNothing);
}

Future<void> _closeWorkDialog(WidgetTester t) async {
  await t.tap(findVisibleText('닫기').last);
  await _settle(t, 30);
  expect(find.byType(WorkApplicantsDialog), findsNothing);
}

void main() {
  setUp(() => StaffingClock.debugOverride = () => _e1Now);
  tearDown(() => StaffingClock.debugOverride = null);
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
  });
  tearDown(() {
    WorkApplicantsReads.debugOverride = null;
    InviteSaveVerifier.debugReader = null;
    InviteWorkerDialog.debugFindUser = null;
    InviteWorkerDialog.debugSendInvite = null;
    E1DebugFault.debugReset();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler(_channel, null);
  });

  group('S 가능일 시트 — 카드에서 카드까지', () {
    testWidgets('S-1 성공 직후 주입 → 확인 saved → `제안 보냄` → 카드 대기 1 · 재진입 중복 없음', (t) async {
      E1DebugFault.debugForce = true;
      final server = _Server();
      final card = _Card(server);
      await card.pump(t);
      expect(_texts(t), contains('대기 0'));
      await _openWorkDialog(t);
      await _openSheet(t);
      await _propose(t);
      expect(server.inviteCalls, 1, reason: '서버 요청 1회');
      expect(E1DebugFault.consumed, isTrue, reason: '성공 직후 주입이 실제로 일어났다');
      expect(server.verifyCalls, 1, reason: '확인 조회 1회(실제 InviteSaveVerifier)');
      expect(find.text('제안 보냄'), findsOneWidget);
      await _closeSheet(t);
      expect(_statAfter(t, '초대: '), '1명');
      await _closeWorkDialog(t);
      await _settle(t, 10);
      expect(card.parentRefreshes, 1);
      final s = _texts(t);
      expect(s, isNot(contains('대기 0')));
      expect('대기 1'.allMatches(s).length, greaterThanOrEqualTo(2));
      // 원장(에뮬레이터 실제 번들) — 지원서 1 · 알림 1 · 대기 1/1/1
      expect(card.slot.resolveStats().pending, _ledger['wdPend']);
      expect([_ledger['apps'], _ledger['notes']], [1, 1]);
      expect([_ledger['wdPend'], _ledger['slotPend'], _ledger['toPend']], [1, 1, 1]);

      // 시트를 닫았다 다시 연다 — 서버가 후보에서 뺀다(중복 표시 없음), 카드 그대로.
      await _openWorkDialog(t);
      await _openSheet(t);
      expect(find.text('근*W'), findsNothing, reason: '초대된 사람이 다시 후보로 보였다');
      expect(server.inviteCalls, 1);
      await _closeSheet(t);
      await _closeWorkDialog(t);
      await _settle(t, 10);
      expect(card.slot.resolveStats().pending, 1, reason: '카드가 0 으로 돌아갔다');
      await t.pump(const Duration(seconds: 5));
    });

    testWidgets('S-2 주입 + 확인 조회 실패 → 성공 콜백 0 · `다시 확인` · 재발송 0 · 창 재조회가 읽으면 카드 1',
        (t) async {
      E1DebugFault.debugForce = true;
      final server = _Server()..verifyFails = true;
      final card = _Card(server);
      await card.pump(t);
      await _openWorkDialog(t);
      await _openSheet(t);
      await _propose(t);
      expect(server.inviteCalls, 1);
      expect(find.text('제안 보냄'), findsNothing, reason: '모르는 것을 성공으로 표시했다');
      expect(findVisibleText('다시 확인'), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, '근무 제안'), findsNothing,
          reason: 'unknown 에서 재발송 버튼이 열렸다(STOP 조건)');
      await t.tap(findVisibleText('다시 확인'));
      await _settle(t, 30);
      expect(server.inviteCalls, 1, reason: '다시 확인이 재발송을 했다');
      await _closeSheet(t);
      // 업무별 창 재조회(성공)가 그 대상 INVITED 를 읽었다 → 전파(E1-W3 규칙)
      expect(_statAfter(t, '초대: '), '1명');
      await _closeWorkDialog(t);
      await _settle(t, 10);
      expect(card.parentRefreshes, 1);
      expect(card.slot.resolveStats().pending, 1);
      await t.pump(const Duration(seconds: 5));
    });

    testWidgets('S-3 대조: 주입 + 확인 실패 + 창 재조회도 실패 → 성공 표시·전파 0', (t) async {
      E1DebugFault.debugForce = true;
      final server = _Server()
        ..verifyFails = true
        ..listFailsAfterSend = true;
      final card = _Card(server);
      await card.pump(t);
      await _openWorkDialog(t);
      await _openSheet(t);
      await _propose(t);
      await _closeSheet(t);
      await _closeWorkDialog(t);
      await _settle(t, 10);
      expect(card.parentRefreshes, 0);
      expect(server.inviteCalls, 1);
      expect(_texts(t), isNot(contains('대기 1')));
      await t.pump(const Duration(seconds: 5));
    });

    testWidgets('S-4 대조: 서버가 저장하지 못했다(internal) → 확인 notSaved · 재발송 가능 · 전파 0', (t) async {
      final server = _Server()..commitOnInvite = false;
      final card = _Card(server);
      await card.pump(t);
      await _openWorkDialog(t);
      await _openSheet(t);
      await _propose(t);
      expect(server.inviteCalls, 1);
      expect(find.text('제안 보냄'), findsNothing);
      expect(findVisibleText('다시 확인'), findsNothing);
      expect(find.widgetWithText(OutlinedButton, '근무 제안'), findsOneWidget,
          reason: 'notSaved 는 다시 보낼 수 있다');
      await _closeSheet(t);
      await _closeWorkDialog(t);
      await _settle(t, 10);
      expect(card.parentRefreshes, 0);
      await t.pump(const Duration(seconds: 5));
    });
  });

  group('N notSaved vs unknown 버튼', () {
    Future<void> openSheetOnly(WidgetTester t, _Server server) async {
      t.view.physicalSize = const Size(411, 1000);
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.reset);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMessageHandler(_channel, server.handle);
      await t.pumpWidget(MaterialApp(
        navigatorKey: navigatorKey,
        home: Scaffold(
          body: AvailableWorkersBottomSheet(
            toId: 'TO', slotId: 'S', businessId: 'BIZ', date: _workDate,
            workType: 'QA', startTime: '14:00', endTime: '15:00',
            requiredCount: 2, confirmedCount: 0,
          ),
        ),
      ));
      await _settle(t, 30);
    }

    testWidgets('N-1 시트 notSaved(늦게 보이는 저장) → `근무 제안` 다시 열림 → 재발송 already-exists → 다시 확인 saved',
        (t) async {
      E1DebugFault.debugForce = true;
      final server = _Server()..lateVisible = true;
      await openSheetOnly(t, server);
      await _propose(t);
      expect(server.inviteCalls, 1);
      expect(find.widgetWithText(OutlinedButton, '근무 제안'), findsOneWidget,
          reason: 'notSaved: 읽었고 없었다 → 다시 보낼 수 있다');
      expect(findVisibleText('다시 확인'), findsNothing);
      await _propose(t);
      expect(server.inviteCalls, 2, reason: '사용자가 다시 보냈다');
      expect(server.verifyCalls, 2, reason: 'already-exists 를 실패가 아니라 확인 대상으로');
      expect(find.text('제안 보냄'), findsOneWidget);
      // 서버는 두 번째를 쓰지 않았다(already-exists) — 원장 1건(에뮬레이터 E1-B).
      expect(_ledger['apps'], 1);
      await t.pump(const Duration(seconds: 5));
    });

    testWidgets('N-2 시트 unknown → `다시 확인` 만, 재발송 버튼 없음', (t) async {
      E1DebugFault.debugForce = true;
      final server = _Server()..verifyFails = true;
      await openSheetOnly(t, server);
      await _propose(t);
      expect(findVisibleText('다시 확인'), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, '근무 제안'), findsNothing);
      await t.pump(const Duration(seconds: 5));
    });

    Future<dynamic> openDirect(WidgetTester t,
        {required List<Object?> sendResults,
        required List<Object> verifyResults}) async {
      t.view.physicalSize = const Size(411, 1000);
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.reset);
      InviteWorkerDialog.debugFindUser =
          (_) async => {'uid': 'W', 'name': '근로W', 'phone': '01000000000'};
      InviteWorkerDialog.debugSendInvite = (p) async {
        final r = sendResults.removeAt(0);
        if (r != null) throw r;
      };
      InviteSaveVerifier.debugReader = (_) async {
        final r = verifyResults.removeAt(0);
        if (r is Exception) throw r;
        return r as List<Map<String, dynamic>>;
      };
      await t.pumpWidget(ChangeNotifierProvider<UserProvider>(
        create: (_) => _AdminP(),
        child: MaterialApp(
          navigatorKey: navigatorKey,
          home: Builder(
            builder: (ctx) => Scaffold(
              body: ElevatedButton(
                onPressed: () => showDialog(
                  context: ctx,
                  builder: (_) => InviteWorkerDialog.contextual(
                    toId: 'TO', businessId: 'BIZ', businessName: 'biz',
                    date: _workDate, slotId: 'S', workType: 'QA',
                    startTime: '14:00', endTime: '15:00'),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ));
      await t.tap(find.text('open'));
      await _settle(t);
      await t.enterText(find.byType(TextField), '01000000000');
      await t.tap(find.text('검색'));
      await _settle(t);
      await t.tap(find.widgetWithText(ElevatedButton, '근무 제안'));
      await _settle(t, 40);
    }

    FirebaseFunctionsException ffe(String c) =>
        FirebaseFunctionsException(message: c, code: c);

    testWidgets('N-3 직접 창 notSaved → `근무 제안` 다시 활성 · `다시 확인` 없음', (t) async {
      await openDirect(t,
          sendResults: [ffe('deadline-exceeded')],
          verifyResults: [<Map<String, dynamic>>[]]);
      final btn = t.widget<ElevatedButton>(find.widgetWithText(ElevatedButton, '근무 제안'));
      expect(btn.onPressed, isNotNull, reason: 'notSaved: 다시 보낼 수 있다');
      expect(find.ancestor(of: findVisibleText('다시 확인'), matching: find.byType(ElevatedButton)), findsNothing);
      await t.pump(const Duration(seconds: 5));
    });

    testWidgets('N-4 직접 창 unknown → `다시 확인` 만 · `근무 제안` 없음', (t) async {
      await openDirect(t,
          sendResults: [ffe('deadline-exceeded')],
          verifyResults: [ffe('unavailable'), ffe('unavailable')]);
      expect(find.ancestor(of: findVisibleText('다시 확인'), matching: find.byType(ElevatedButton)), findsOneWidget);
      expect(find.widgetWithText(ElevatedButton, '근무 제안'), findsNothing);
      await t.pump(const Duration(seconds: 5));
    });

    testWidgets('N-5 직접 창 notSaved 뒤 재발송 → already-exists → 다시 확인 saved → sent', (t) async {
      await openDirect(t,
          sendResults: [ffe('deadline-exceeded'), ffe('already-exists')],
          verifyResults: [<Map<String, dynamic>>[], _rows('saved', 'post')]);
      await t.tap(find.widgetWithText(ElevatedButton, '근무 제안'));
      await _settle(t, 40);
      expect(find.byType(InviteWorkerDialog), findsNothing, reason: 'sent 로 닫혔다');
      await t.pump(const Duration(seconds: 5));
    });
  });
}
