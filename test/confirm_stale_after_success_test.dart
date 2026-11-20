// [SIM-A] 확정 성공 직후 관리자 창·공고 카드가 낡은 상태로 남았다.
//
// DEVICE 반례(DEV 확정 셀, 설치 앱 1.0.21+25):
//   공고 카드 `인력 현황` → 확정 → DEV 원장은 CONTRACT_PENDING·충원 1/1 인데
//   창은 계속 `지원(1건)`·`확정` 버튼, 카드는 `충원 0 / 필요 1 · 대기 1`.
//   창을 다시 열어야 `확정 1건`이 보였다.
//
// root cause (CODE + 이 하네스로 재현):
//   서버는 확정 트랜잭션 **뒤에** 슬롯을 다시 읽어 마지막 자리가 찼으면
//   `capacityWarning` 을 돌려준다(정원 1 → 항상). 플러그인은 최상위만
//   `Map<String, dynamic>` 으로 바꾸고 안쪽 map 은 `Map<Object?, Object?>` 로
//   둔다. 클라이언트가 그것을 `as Map<String, dynamic>?` 로 캐스팅해
//   **확정이 커밋된 뒤** TypeError 를 던졌고, 그래서
//     · 창은 `_hasChanges`·`_load()` 를 건너뛰고 `확정 처리 중 오류` 를 띄웠고
//     · 닫으면 hasChanges=false → 카드가 다시 읽지 않았다.
//
// 이 하네스: 실제 TOGroupCard → `인력 현황` → 실제 DayApplicantsDialog →
//   실제 FirestoreService 확정 경로. 확정 응답은 플랫폼 채널(StandardMessageCodec)
//   을 거치므로 안쪽 map 의 실제 타입이 그대로 재현된다. DEV 호출 없음.
import 'support/visible_text.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';

import 'package:ALfit/controllers/workforce_controller.dart';
import 'package:ALfit/models/core/application_model.dart';
import 'package:ALfit/models/core/attendance_model.dart';
import 'package:ALfit/models/core/business_member_model.dart'
    show MemberPermissions;
import 'package:ALfit/models/core/slot_model.dart' show SlotModel, SlotStatus;
import 'package:ALfit/models/core/to_model.dart';
import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/models/core/work_detail_data.dart';
import 'package:ALfit/models/ui/admin_to_list_ui_models.dart';
import 'package:ALfit/models/ui/day_staffing_row.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/screens/business_admin/dialogs/day_applicants_dialog.dart';
import 'package:ALfit/screens/business_admin/dialogs/day_applicants_reads.dart';
import 'package:ALfit/screens/business_admin/dialogs/to_list_dialogs.dart';
import 'package:ALfit/services/contract_service.dart';
import 'package:ALfit/services/firestore_service.dart';
import 'package:ALfit/utils/action_guard.dart';
import 'package:ALfit/utils/format_helper.dart';
import 'package:ALfit/utils/navigation_key.dart';
import 'package:ALfit/utils/staffing_clock.dart';
import 'package:ALfit/widgets/admin/cards/admin_to_group_card.dart';

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
  bool canForBusiness(
          String businessId, bool Function(MemberPermissions p) check) =>
      true;
  @override
  PermissionCheck checkForBusiness(
          String businessId, bool Function(MemberPermissions p) check) =>
      PermissionCheck.allowed;
}

const _channel =
    'dev.flutter.pigeon.cloud_functions_platform_interface.CloudFunctionsHostApi.call';

/// KST 2026-10-20 00:00 — DEV 셀과 같은 근무일.
final _workDate = DateTime.utc(2026, 10, 19, 15).toLocal();

WorkDetailData _wd() => WorkDetailData(
      wdId: 'wd1', workType: 'QA 분류', startTime: '10:00', endTime: '11:00',
      requiredCount: 1, wage: 12000, wageType: 'hourly',
      applicationDeadline: DateTime.now().add(const Duration(days: 2)),
    );

TOModel _to() => TOModel(
      id: 'TO', businessId: 'BIZ', businessName: 'QA 사업장', type: 'flex',
      title: 'QA-SIM confirm', creatorUID: 'OWNER', status: 'ACTIVE',
      workDetails: const [], totalRequired: 1, totalConfirmed: 0,
      totalPending: 1, isPublished: true, publishMode: 'immediate',
      createdAt: DateTime.now().subtract(const Duration(days: 1)),
      statusUpdatedAt: DateTime.now().subtract(const Duration(days: 1)),
    );

TOItem _slot() => TOItem(
      to: _to(),
      slot: SlotModel(
        id: 'S', toId: 'TO', date: _workDate, status: SlotStatus.open,
        workDetails: [_wd()],
        createdAt: DateTime.now().subtract(const Duration(days: 1)),
      ),
      confirmedCount: 0, pendingCount: 1, totalRequired: 1,
    );

ApplicationModel _app(String status) => ApplicationModel(
      id: 'APP', uid: 'W', toId: 'TO', slotId: 'S', businessId: 'BIZ',
      businessName: 'QA 사업장', toTitle: 'QA-SIM confirm',
      selectedWorkType: 'QA 분류', wdId: 'wd1', startTime: '10:00',
      endTime: '11:00', wage: 12000, wageType: 'hourly', status: status,
      workDate: _workDate, appliedAt: DateTime.now(),
    );

enum _Reply { success, denied, lost }

/// 서버 — 확정이 커밋됐는지에 따라 모든 읽기가 바뀐다.
class _Server {
  _Reply reply = _Reply.success;
  bool committed = false;
  int confirmCalls = 0;
  int pendingReads = 0;
  int statsReads = 0;

  /// 확정 응답을 붙잡아 두는 문(연타 검증).
  Completer<void>? confirmGate;

  /// 확정 뒤 재조회를 붙잡아 두는 문(재조회 중 연타 검증).
  Completer<void>? reloadGate;

  Future<ByteData?> handle(ByteData? message) async {
    final args = (const StandardMessageCodec().decodeMessage(message) as List)
        .first as Map;
    final name = args['functionName'] as String;
    if (name != 'callableConfirmApplication') {
      return _err('not-found');
    }
    confirmCalls++;
    if (confirmGate != null) await confirmGate!.future;
    switch (reply) {
      case _Reply.denied:
        return _err('permission-denied');
      case _Reply.lost:
        committed = true; // 서버는 커밋했는데 응답이 오지 않았다
        return _err('deadline-exceeded');
      case _Reply.success:
        committed = true;
        // 운영 서버와 같은 모양 — 트랜잭션 뒤 다시 읽은 슬롯이 1/1 이므로
        //   capacityWarning 이 **항상** 온다(정원 1).
        return const StandardMessageCodec().encodeMessage(<Object?>[
          <String, Object?>{
            'success': true,
            'alreadyConfirmed': false,
            'capacityWarning': <String, Object?>{
              'workType': 'QA 분류', 'required': 1, 'confirmed': 1,
            },
            'autoCanceledDetails': <Object?>[],
            'appInfo': <String, Object?>{'toId': 'TO', 'uid': 'W'},
          }
        ]);
    }
  }

  ByteData? _err(String code) => const StandardMessageCodec().encodeMessage(
      <Object?>[code, 'mock $code', <String, Object?>{'code': code}]);

  DayApplicantsReads reads() => DayApplicantsReads(
        pendingApplications: ({required date, required businessId, purpose}) async {
          pendingReads++;
          if (committed && reloadGate != null) await reloadGate!.future;
          return committed ? const [] : [_app('PENDING')];
        },
        confirmedWorkers: ({required date, required businessId}) async =>
            committed ? [_app('CONTRACT_PENDING')] : const [],
        dayStaffing: ({required businessId, required dayStartMs}) async => [
          DayStaffingRow(
            toId: 'TO', toTitle: 'QA-SIM confirm', slotId: 'S', wdId: 'wd1',
            workType: 'QA 분류', startTime: '10:00', endTime: '11:00',
            requiredCount: 1,
            confirmedCount: committed ? 1 : 0,
            pendingCount: committed ? 0 : 1,
          ),
        ],
        dayInvitations: ({required date, required businessId}) async =>
            const [],
        hasWorkedMap: ({required businessId, required date}) async => const {},
        noShowApplicationIds: ({required businessId, required date}) async =>
            <String>{},
        usersBatch: (uids, {required businessId, purpose}) async => {
          for (final u in uids)
            u: UserModel(uid: u, username: u, name: 'QA 지원자2',
                email: '$u@test.local', role: UserRole.USER),
        },
        weeklyAttendance: ({required businessId, required weekStart,
                required weekEnd}) async =>
            <String, List<AttendanceModel>>{},
        slotWorkDetailCapacities: (toId, slotId) async => const {'wd1': 1},
        slotWorkDetails: (toId, slotId) async => [_wd()],
        to: (toId) async => null,
        contractStatusBatch: (ids, {required businessId}) async =>
            const ContractStatusBatch(),
      );

  /// 공고 카드의 업무 통계 — 같은 원장에서 나온다.
  Future<Map<String, dynamic>> capacity() async {
    statsReads++;
    return {
      'workDetails': [_wd()],
      'workStats': {
        'wd1': {'confirmed': committed ? 1 : 0, 'pending': committed ? 0 : 1},
      },
      'statsFailed': false,
    };
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

/// 카드 하네스 — onChanged(상위 재조회 신호)가 오면 실제 앱처럼 통계를 다시 읽는다.
class _Card {
  _Card(this.server);
  final _Server server;
  late final TOItem slot = _slot();
  late final WorkforceController controller = WorkforceController(
      loadWorkDetailStats: (to, {slotId, slotWorkDetails}) =>
          server.capacity());
  int parentRefreshes = 0;

  Future<void> refreshParent() async {
    slot.resetWorkDetailLoad();
    await controller.loadWorkDetails(slot);
  }

  Future<void> pump(WidgetTester t) async {
    t.view.physicalSize = const Size(411, 1600);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    addTearDown(controller.dispose);
    DayApplicantsReads.debugOverride = server.reads();
    _stubAuthChannels(t);
    t.binding.defaultBinaryMessenger
        .setMockMessageHandler(_channel, server.handle);
    addTearDown(() => t.binding.defaultBinaryMessenger
        .setMockMessageHandler(_channel, null));
    await controller.loadWorkDetails(slot);
    final group = TOGroupItem(singleTO: _to())
      ..setGroupTOs([slot])
      ..setSlotDates([_workDate])
      // 운영 컨트롤러가 채우는 값 — `인력 현황` 이 그 날짜 명단을 연다.
      ..setOperationalDate(FormatHelper.toKstDate(_workDate));
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
                onRetryGroupWorkDetailStats:
                    controller.loadGroupWorkDetailStats,
                dialogs: TOListDialogs(
                    context: ctx, firestoreService: svc, onChanged: () {}),
                onChanged: () {
                  parentRefreshes++;
                  refreshParent();
                },
                isExpanded: false,
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

Future<void> _openRoster(WidgetTester t) async {
  final cta = findVisibleText('인력 현황');
  await t.ensureVisible(cta.first);
  await t.tap(cta.first);
  // 카드는 열기 전에 사업장 문서를 실제 플러그인으로 읽는다(실패해도 연다).
  //   그 응답은 가짜 시계로는 오지 않는다 — 진짜 async 를 준다.
  for (var i = 0; i < 3; i++) {
    await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 150)));
    await _settle(t, 10);
  }
  await _settle(t, 30);
  expect(find.byType(DayApplicantsDialog), findsOneWidget,
      reason: '공고 카드의 `인력 현황` 이 날짜 명단을 열어야 한다');
}

/// 명단 행의 `확정` 버튼(`_actionButton` = InkWell › Container › Text).
///   머리말 수치 `확정` 칸과 구별한다.
Finder _confirmButton() => find.descendant(
    of: find.byType(DayApplicantsDialog),
    matching: find.byWidgetPredicate((w) =>
        w is InkWell &&
        w.child is Container &&
        (w.child as Container).child is Text &&
        ((w.child as Container).child as Text).data == '확정'));

/// 그 버튼이 지금 눌리는가(처리 중이면 onTap 이 null 이다).
bool _confirmEnabled(WidgetTester t) => _confirmButton()
    .evaluate()
    .any((e) => (e.widget as InkWell).onTap != null);

/// 화면이 FirebaseAuth 를 만지면 리스너 등록 채널이 열린다 — 테스트에서는 답만 한다.
void _stubAuthChannels(WidgetTester t) {
  const base = 'dev.flutter.pigeon.firebase_auth_platform_interface.FirebaseAuthHostApi';
  for (final m in ['registerIdTokenListener', 'registerAuthStateListener']) {
    t.binding.defaultBinaryMessenger.setMockMessageHandler('$base.$m',
        (_) async => const StandardMessageCodec()
            .encodeMessage(<Object?>['test/auth-events']));
  }
  t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('test/auth-events'), (_) async => null);
}

/// 명단의 `확정` → 확인창의 `확정`.
Future<void> _tapConfirm(WidgetTester t, {bool settle = true}) async {
  final btn = _confirmButton();
  await t.ensureVisible(btn.first);
  await t.tap(btn.first);
  await _settle(t, 6);
  // 확인창 — 명단 밖의 마지막 `확정`
  await t.tap(findVisibleText('확정').last);
  if (settle) await _settle(t, 40);
}

Future<void> _closeRoster(WidgetTester t) async {
  await t.tap(findVisibleText('닫기').last);
  await _settle(t, 30);
  expect(find.byType(DayApplicantsDialog), findsNothing);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
  });
  // 근무일(KST 10-20)이 지나면 카드가 `운영 종료` 로 내려가 숫자가 사라진다 — 근무 전날 정오로 고정.
  setUp(() => StaffingClock.debugOverride = () => DateTime.utc(2026, 10, 19, 3).toLocal());
  tearDown(() {
    StaffingClock.debugOverride = null;
    DayApplicantsReads.debugOverride = null;
    // 앞 테스트가 열어 둔 명단의 중복 실행 키가 다음 테스트를 막지 않게 한다.
    ActionGuard.resetForTest();
  });

  testWidgets('CS-0 출발점 — 카드 대기 1·창 `확정` 버튼 (DEV 셀과 같은 상태)',
      (t) async {
    final card = _Card(_Server());
    await card.pump(t);
    expect(_texts(t), contains('대기 1'));
    await _openRoster(t);
    expect(_confirmButton(), findsOneWidget);
  });

  testWidgets('CS-1 확정 성공 직후 창이 서버의 최신 상태(확정 1건)로 바뀐다', (t) async {
    final server = _Server();
    final card = _Card(server);
    await card.pump(t);
    await _openRoster(t);
    await _tapConfirm(t);

    expect(server.confirmCalls, 1);
    expect(server.committed, isTrue);
    expect(_confirmButton(), findsNothing,
        reason: '확정된 사람에게 `확정` 버튼이 남으면 안 된다: ${_texts(t)}');
    expect(_texts(t), contains('확정 (1명)'),
        reason: '서버 재조회 결과(CONTRACT_PENDING)를 보여야 한다');
    expect(_texts(t), isNot(contains('지원 (1건)')));
    expect(_texts(t), isNot(contains('확정 처리 중 오류')),
        reason: '커밋된 확정을 오류라고 말하면 안 된다');
  });

  testWidgets('CS-2 창을 닫으면 카드가 다시 읽어 충원 1 · 대기 0', (t) async {
    final server = _Server();
    final card = _Card(server);
    await card.pump(t);
    await _openRoster(t);
    await _tapConfirm(t);
    await _closeRoster(t);

    expect(card.parentRefreshes, 1, reason: '상위 카드 재조회 신호');
    final s = _texts(t);
    expect(s, contains('충원 1'), reason: s);
    expect(s, isNot(contains('대기 1')), reason: s);
  });

  testWidgets('CS-3 재진입·상위 재조회에서도 같은 숫자', (t) async {
    final server = _Server();
    final card = _Card(server);
    await card.pump(t);
    await _openRoster(t);
    await _tapConfirm(t);
    final inDialog = _texts(t);
    await _closeRoster(t);

    // 재진입
    await _openRoster(t);
    expect(_texts(t), contains('확정 (1명)'));
    expect(_confirmButton(), findsNothing);
    expect(_texts(t).contains('확정 (1명)'), inDialog.contains('확정 (1명)'),
        reason: '확정 직후와 재진입이 같은 말을 해야 한다');
    await _closeRoster(t);

    // 상위 재조회(새로고침과 같은 통계 경로)
    await card.refreshParent();
    await _settle(t, 10);
    final s = _texts(t);
    expect(s, contains('충원 1'), reason: s);
    expect(s, isNot(contains('대기 1')), reason: s);
  });

  testWidgets('CS-4 응답 대기·재조회 중 같은 `확정` 을 다시 눌러도 요청은 1번', (t) async {
    final server = _Server()
      ..confirmGate = Completer<void>()
      ..reloadGate = Completer<void>();
    final card = _Card(server);
    await card.pump(t);
    await _openRoster(t);
    await _tapConfirm(t, settle: false);
    await _settle(t, 4);

    // 응답 대기 중 — 같은 버튼이 보여도 눌리지 않는다
    expect(_confirmEnabled(t), isFalse, reason: '응답 대기 중 확정 버튼이 살아 있다');
    if (_confirmButton().evaluate().isNotEmpty) {
      await t.tap(_confirmButton().first, warnIfMissed: false);
      await _settle(t, 4);
    }

    server.confirmGate!.complete();
    await _settle(t, 6);
    // 재조회 중 — 다시 누를 수 없다
    expect(_confirmEnabled(t), isFalse, reason: '재조회 중 확정 버튼이 살아 있다');
    if (_confirmButton().evaluate().isNotEmpty) {
      await t.tap(_confirmButton().first, warnIfMissed: false);
      await _settle(t, 4);
    }
    server.reloadGate!.complete();
    await _settle(t, 40);

    expect(server.confirmCalls, 1, reason: '확정 요청은 한 번만 나간다');
    expect(_confirmButton(), findsNothing);
  });

  testWidgets('CS-5 서버 거절 — 성공으로 말하지 않고 카드도 그대로', (t) async {
    final server = _Server()..reply = _Reply.denied;
    final card = _Card(server);
    await card.pump(t);
    await _openRoster(t);
    await _tapConfirm(t);

    expect(server.committed, isFalse);
    expect(_texts(t), isNot(contains('확정되었습니다')));
    expect(_confirmButton(), findsOneWidget, reason: '지원자는 그대로 대기다');
    await _closeRoster(t);
    expect(card.parentRefreshes, 0, reason: '바뀐 것이 없다');
    expect(_texts(t), contains('대기 1'));
    await t.pump(const Duration(seconds: 5)); // 오류 토스트 타이머
  });

  testWidgets('CS-6 응답 불명확(서버는 커밋) — 성공을 추정하지 않고 서버를 다시 읽는다',
      (t) async {
    final server = _Server()..reply = _Reply.lost;
    final card = _Card(server);
    await card.pump(t);
    await _openRoster(t);
    final before = server.pendingReads;
    await _tapConfirm(t);

    expect(_texts(t), isNot(contains('확정되었습니다')),
        reason: '응답을 못 받았는데 성공이라고 말하면 안 된다');
    expect(server.pendingReads, greaterThan(before),
        reason: '모르면 서버를 다시 읽는다');
    expect(_texts(t), contains('확정 (1명)'),
        reason: '다시 읽은 서버 상태(커밋됨)를 보여 준다');
    expect(_confirmButton(), findsNothing);
    await _closeRoster(t);
    expect(card.parentRefreshes, 1, reason: '상위도 서버를 다시 읽는다');
    expect(_texts(t), contains('충원 1'));
  });
}
