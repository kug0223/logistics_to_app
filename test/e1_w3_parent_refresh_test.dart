// [ALFIT-E1-W3-PARENT-REFRESH-AND-CANARY-READY-GATE.1]
//
//   실제 위젯 경로:
//     TOGroupCard(펼침, 대기 0) → 업무 행 → WorkApplicantsDialog
//       → `인력 초대` → `직접 초대` → InviteWorkerDialog 발송
//       → 서버 커밋 뒤 응답 유실(deadline-exceeded)
//       → 첫 저장 확인 읽기 실패(unknown) → `다시 확인` 만 남음 → 직접 초대 창 닫기
//       → 업무별 창 재조회(성공)에서 **그 대상의 이 업무 INVITED** 발견
//       → 업무별 창 닫기 → hasChanges → 카드 재조회 → 카드 `대기 1`
//
//   서버 응답 행과 원장 수치는 로컬 에뮬레이터의 실제 번들이 만든 것이다
//   (test/fixtures/e1_emulator_ambiguous.json — 지원서 1 · 알림 1 · 업무/슬롯/공고 대기 1/1/1).
//   응답 유실은 클라이언트 모의다. DEV 호출이 아니다.
//   가능일 시트 경로는 이 연결에 없다(별도 검증 — invite_ambiguous_save_test IAS-18~21).
import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/visible_text.dart'; // [DU255] keepWords 문구는 보이는 글자로 찾는다
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
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

/// 다른 사람(W2)의 초대 — 같은 업무·같은 슬롯. 이 저장의 증거가 아니다.
List<Map<String, dynamic>> _otherWorkerRows() => _rows('saved', 'post')
    .map((m) => jsonDecode(jsonEncode(m).replaceAll('"W"', '"W2"').replaceAll('_W"', '_W2"'))
        as Map<String, dynamic>)
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

/// 서버 — 발송 커밋 여부에 따라 읽기 응답이 바뀐다.
class _Server {
  bool committed = false;
  bool commitOnSend = true;          // false = 서버는 저장하지 못했다(대조)
  bool verifyFails = true;           // 첫 확인 읽기(그리고 다시 확인)는 실패
  bool listFailsAfterSend = false;   // 업무별 창 재조회도 실패(대조)
  bool otherWorkerOnly = false;      // 재조회에 다른 사람 초대만 보인다(대조)
  int sends = 0;
  int listReads = 0;

  List<Map<String, dynamic>> _listRows() {
    if (!committed) return const [];
    return otherWorkerOnly ? _otherWorkerRows() : _rows('saved', 'post');
  }

  Future<Map<String, dynamic>> capacity() async {
    final stats = {'wd1': {'confirmed': 0, 'pending': 0}};
    FirestoreService.tallyWorkDetailSeats(
        stats,
        committed && !otherWorkerOnly ? _parse(_rows('saved', 'capacity')) : const [],
        slotId: 'S', seatDay: _e1Now);
    return {'workDetails': [_wd()], 'workStats': stats, 'statsFailed': false};
  }

  WorkApplicantsReads reads() => WorkApplicantsReads(
        applications: (to, {slotId, required purpose}) async {
          listReads++;
          if (committed && listFailsAfterSend) {
            throw FirebaseFunctionsException(message: 'unavailable', code: 'unavailable');
          }
          return _parse(_listRows());
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

  Future<List<Map<String, dynamic>>> verify(Map<String, dynamic> p) async {
    if (verifyFails) {
      throw FirebaseFunctionsException(message: 'unavailable', code: 'unavailable');
    }
    return _listRows();
  }

  Future<void> send(Map<String, dynamic> payload) async {
    sends++;
    if (commitOnSend) committed = true;
    throw FirebaseFunctionsException(
        message: 'deadline-exceeded', code: 'deadline-exceeded');
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
    ].where((s) => s.isNotEmpty).join(' | ');

String? _statAfter(WidgetTester t, String label) {
  final all = t.widgetList<Text>(find.byType(Text)).map((w) => w.data).toList();
  final i = all.indexOf(label);
  return i < 0 ? null : all[i + 1];
}

/// 카드 하네스. onChanged(=상위 재조회 신호)가 오면 실제 앱처럼 통계를 다시 읽는다.
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
    InviteSaveVerifier.debugReader = server.verify;
    InviteWorkerDialog.debugFindUser =
        (_) async => {'uid': 'W', 'name': '근로W', 'phone': '01000000000'};
    InviteWorkerDialog.debugSendInvite = server.send;
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
                  // 실제 공고 탭은 이 신호로 다시 읽는다 — 여기서는 같은 통계 경로.
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

/// 업무별 창 → 인력 초대 → 직접 초대 → 발송(응답 유실) → 확인 실패 상태.
Future<void> _sendAmbiguous(WidgetTester t) async {
  await t.tap(find.textContaining('인력 초대').first);
  await _settle(t);
  await t.tap(find.text('직접 초대'));
  await _settle(t);
  await t.enterText(find.byType(TextField), '01000000000');
  await t.tap(find.text('검색'));
  await _settle(t);
  await t.tap(find.widgetWithText(ElevatedButton, '근무 제안'));
  await _settle(t, 40);
}

enum _Close { button, back }

Future<void> _closeInviteDialog(WidgetTester t, _Close how) async {
  if (how == _Close.button) {
    await t.tap(find.widgetWithText(OutlinedButton, '닫기'));
  } else {
    await t.binding.handlePopRoute();
  }
  await _settle(t, 40);
  expect(find.byType(InviteWorkerDialog), findsNothing);
}

Future<void> _closeWorkDialog(WidgetTester t, _Close how) async {
  if (how == _Close.button) {
    await t.tap(find.text('닫기').last);
  } else {
    await t.binding.handlePopRoute();
  }
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
  });

  group('W3 상위 카드 갱신 — 업무별 창 재조회가 대상 초대를 읽었을 때만', () {
    for (final how in _Close.values) {
      testWidgets('W3-${how.name} 확인 실패 → 직접 초대 창 닫기 → 재조회 발견 → 카드 대기 1', (t) async {
        final server = _Server();
        final card = _Card(server);
        await card.pump(t);
        expect(_texts(t), contains('대기 0'));
        await _openWorkDialog(t);
        await _sendAmbiguous(t);
        // 확인 불가 — 재발송 버튼 없이 `다시 확인`
        expect(find.ancestor(of: findVisibleText('다시 확인'), matching: find.byType(ElevatedButton)), findsOneWidget);
        expect(find.widgetWithText(ElevatedButton, '근무 제안'), findsNothing);
        await _closeInviteDialog(t, how);
        // 업무별 창이 다시 읽어 그 대상 초대를 봤다
        expect(_statAfter(t, '초대: '), '1명');
        expect(find.text('근로W'), findsOneWidget);
        await _closeWorkDialog(t, how);
        await _settle(t, 10);
        expect(card.parentRefreshes, 1, reason: '상위 재조회 신호');
        final s = _texts(t);
        expect(s, isNot(contains('대기 0')));
        expect('대기 1'.allMatches(s).length, greaterThanOrEqualTo(2),
            reason: '헤더와 업무 행 모두 대기 1');
        expect(card.slot.resolveStats().pending, 1);
        // 원장(에뮬레이터 실제 번들)과 대조 — 요청 1 · 지원서 1 · 알림 1 · 대기 1/1/1
        expect(server.sends, 1);
        expect(_ledger['apps'], 1);
        expect(_ledger['notes'], 1);
        expect([_ledger['wdPend'], _ledger['slotPend'], _ledger['toPend']], [1, 1, 1]);
        expect(card.slot.resolveStats().pending, _ledger['wdPend']);

        // 창을 다시 열었다 닫아도 공유 TOItem 통계가 0 으로 덮이지 않는다
        await _openWorkDialog(t);
        await _closeWorkDialog(t, _Close.button);
        await _settle(t, 10);
        expect(card.slot.resolveStats().pending, 1);
        expect(card.slot.pendingCount, isNot(0));
        await t.pump(const Duration(seconds: 5));
      });
    }

    for (final (id, name, configure) in <(String, String, void Function(_Server))>[
      ('W3-C1', '업무별 재조회도 실패', (s) => s.listFailsAfterSend = true),
      ('W3-C2', '서버가 저장하지 못했다(재조회에 대상 없음)', (s) => s.commitOnSend = false),
      ('W3-C3', '재조회에 다른 사람의 초대만 있다', (s) => s.otherWorkerOnly = true),
    ]) {
      for (final how in _Close.values) {
        testWidgets('$id-${how.name} $name → 성공으로 표시하지 않는다', (t) async {
          final server = _Server();
          configure(server);
          final card = _Card(server);
          await card.pump(t);
          await _openWorkDialog(t);
          await _sendAmbiguous(t);
          expect(find.widgetWithText(ElevatedButton, '근무 제안'), findsNothing,
              reason: '모르는 상태에서 재발송을 열지 않는다');
          await _closeInviteDialog(t, how);
          await _closeWorkDialog(t, how);
          await _settle(t, 10);
          expect(card.parentRefreshes, 0, reason: '확인되지 않은 저장을 성공으로 전파했다');
          expect(server.sends, 1);
          expect(_texts(t), isNot(contains('대기 1')));
          await t.pump(const Duration(seconds: 5));
        });
      }
    }
  });

  group('FAULT 카나리아용 오류 주입', () {
    test('F-1 일반 빌드 정의 없음 → 꺼짐, 성공 뒤에도 던지지 않는다', () {
      expect(E1DebugFault.defined, isFalse,
          reason: '이 테스트 실행은 --dart-define 없이 돈다');
      expect(E1DebugFault.armed, isFalse);
      E1DebugFault.afterInviteCommitted();
      expect(E1DebugFault.consumed, isFalse);
    });

    test('F-2 켜지면 성공 뒤 정확히 한 번만 deadline-exceeded', () {
      E1DebugFault.debugForce = true;
      expect(() => E1DebugFault.afterInviteCommitted(),
          throwsA(isA<FirebaseFunctionsException>()
              .having((e) => e.code, 'code', 'deadline-exceeded')));
      expect(E1DebugFault.consumed, isTrue);
      expect(E1DebugFault.afterInviteCommitted, returnsNormally, reason: '두 번째는 없다');
      expect(isAmbiguousInviteError(FirebaseFunctionsException(
          message: 'x', code: 'deadline-exceeded')), isTrue,
          reason: '앱은 이것을 불명확으로 분류한다');
    });

    testWidgets('F-3 직접 초대 창: 서버 성공 뒤 주입 → 확인 읽기 saved → sent · 요청 1', (t) async {
      E1DebugFault.debugForce = true;
      final server = _Server()
        ..verifyFails = false;
      var sends = 0;
      InviteWorkerDialog.debugSendInvite = (p) async {
        sends++;
        server.committed = true; // 서버 성공(커밋)
      };
      InviteSaveVerifier.debugReader = server.verify;
      InviteWorkerDialog.debugFindUser =
          (_) async => {'uid': 'W', 'name': '근로W', 'phone': '01000000000'};
      dynamic popped;
      t.view.physicalSize = const Size(411, 1000);
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.reset);
      await t.pumpWidget(ChangeNotifierProvider<UserProvider>(
        create: (_) => _AdminP(),
        child: MaterialApp(
          navigatorKey: navigatorKey,
          home: Builder(
            builder: (ctx) => Scaffold(
              body: ElevatedButton(
                onPressed: () async => popped = await showDialog(
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
      expect(sends, 1);
      expect(E1DebugFault.consumed, isTrue, reason: '성공 뒤 1회 주입됐다');
      expect((popped as dynamic)?.isSent, isTrue, reason: '확인 읽기로 저장을 확인했다');
      await t.pump(const Duration(seconds: 5));
    });

    test('F-4 주입 지점은 성공한 callable 뒤에만 있다(두 발송 경로)', () {
      String code(String p) => File(p).readAsStringSync();
      final dlg = code('lib/screens/business_admin/dialogs/invite_worker_dialog.dart');
      final callIdx = dlg.indexOf(".httpsCallable('callableInviteWorker')");
      final faultIdx = dlg.indexOf('E1DebugFault.afterInviteCommitted();');
      expect(callIdx, greaterThan(0));
      expect(faultIdx, greaterThan(callIdx));
      final svc = code('lib/services/available_workers_service.dart');
      final sIdx = svc.indexOf("httpsCallable('callableInviteWorker')");
      final sFault = svc.indexOf('E1DebugFault.afterInviteCommitted();');
      expect(sFault, greaterThan(sIdx));
      expect('E1DebugFault.afterInviteCommitted();'.allMatches(svc).length, 1);
      // 빌드 설정에 정의가 없다
      for (final f in Directory('config').listSync(recursive: true).whereType<File>()) {
        expect(f.readAsStringSync().contains('E1_DROP_INVITE_RESPONSE'), isFalse,
            reason: '${f.path} 에 카나리아 정의가 있다');
      }
      // 런타임 설정으로 열지 않는다 — 컴파일 상수 + kDebugMode 만
      final fault = code('lib/utils/e1_debug_fault.dart');
      expect(fault, contains("bool.fromEnvironment('E1_DROP_INVITE_RESPONSE')"));
      expect(fault, contains('kDebugMode && (defined || debugForce)'));
      expect(fault, isNot(contains('RemoteConfig')));
    });
  });
}
