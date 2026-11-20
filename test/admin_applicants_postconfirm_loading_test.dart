// [ADMIN-APPLICANTS-POSTCONFIRM] 지원자 다이얼로그 확정 뒤 대기 경로 측정 — CS 하네스(confirm_stale_after_success_test) 재사용.
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
    ].where((s) => s.isNotEmpty).join(' | ');

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
  final cta = find.text('인력 현황');
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
  await t.tap(find.text('확정').last);
  if (settle) await _settle(t, 40);
}

Future<void> _closeRoster(WidgetTester t) async {
  await t.tap(find.text('닫기').last);
  await _settle(t, 30);
  expect(find.byType(DayApplicantsDialog), findsNothing);
}


/// 시간·호출 계측 서버 — CS 서버에 지연(확정 500ms · 읽기 100ms)과 읽기별 호출 수를 더한다.
class _Timed extends _Server {
  _Timed({this.confirmMs = 500, this.readMs = 100});
  final int confirmMs;
  final int readMs;
  int now = 0;
  int? respondedAt;
  final reads0 = <String, int>{};
  bool _counting = false;
  void startCountingReload() {
    _counting = true;
    reads0.clear();
  }

  @override
  Future<ByteData?> handle(ByteData? message) async {
    await Future<void>.delayed(Duration(milliseconds: confirmMs));
    final r = await super.handle(message);
    respondedAt = now;
    return r;
  }

  Future<T> _w<T>(String k, Future<T> Function() f) async {
    if (_counting) reads0[k] = (reads0[k] ?? 0) + 1;
    await Future<void>.delayed(Duration(milliseconds: readMs));
    return f();
  }

  @override
  DayApplicantsReads reads() {
    final b = super.reads();
    return DayApplicantsReads(
      pendingApplications: ({required date, required businessId, purpose}) =>
          _w('pending(GetApplicationsByBiz)', () => b.pendingApplications(date: date, businessId: businessId, purpose: purpose)),
      confirmedWorkers: ({required date, required businessId}) =>
          _w('confirmed(GetApplicationsByBiz×2)', () => b.confirmedWorkers(date: date, businessId: businessId)),
      dayStaffing: ({required businessId, required dayStartMs}) =>
          _w('dayStaffing(GetDayStaffingDetail)', () => b.dayStaffing(businessId: businessId, dayStartMs: dayStartMs)),
      dayInvitations: ({required date, required businessId}) =>
          _w('invitations(GetApplicationsByBiz)', () => b.dayInvitations(date: date, businessId: businessId)),
      hasWorkedMap: ({required businessId, required date}) =>
          _w('hasWorked(GetAdminAttendances)', () => b.hasWorkedMap(businessId: businessId, date: date)),
      noShowApplicationIds: ({required businessId, required date}) =>
          _w('noShow(GetAdminAttendances)', () => b.noShowApplicationIds(businessId: businessId, date: date)),
      usersBatch: (uids, {required businessId, purpose}) =>
          _w('usersBatch(GetUsersBatch)', () => b.usersBatch(uids, businessId: businessId, purpose: purpose)),
      weeklyAttendance: ({required businessId, required weekStart, required weekEnd}) =>
          _w('weekly(GetAdminAttendances)', () => b.weeklyAttendance(businessId: businessId, weekStart: weekStart, weekEnd: weekEnd)),
      slotWorkDetailCapacities: (toId, slotId) =>
          _w('capacities(slot doc)', () => b.slotWorkDetailCapacities(toId, slotId)),
      slotWorkDetails: (toId, slotId) => _w('slotWorkDetails', () => b.slotWorkDetails(toId, slotId)),
      to: (toId) => _w('to(tos doc)', () => b.to(toId)),
      contractStatusBatch: (ids, {required businessId}) =>
          _w('contracts(GetContractsByBiz)', () => b.contractStatusBatch(ids, businessId: businessId)),
    );
  }
}

/// 확인창의 `확정` 을 누른 순간을 0 으로 두고 50ms 마다 화면을 본다.
Future<Map<String, Object?>> _measure(WidgetTester t, _Timed s) async {
  final card = _Card(s);
  await card.pump(t);
  await _openRoster(t);
  final btn = _confirmButton();
  await t.ensureVisible(btn.first);
  await t.tap(btn.first);
  await _settle(t, 6);
  s.startCountingReload();
  s.now = 0;
  await t.tap(find.text('확정').last); // 확인창의 확정
  int? feedback, spinnerOn, spinnerOff, finalAt, listHiddenFrom;
  var falseConfirmBeforeResponse = false;
  var spinnerFrames = 0;
  for (var i = 0; i < 80; i++) {
    await t.pump(const Duration(milliseconds: 50));
    s.now += 50;
    final txt = _texts(t);
    final spin = txt.contains('인력 현황 불러오는 중...');
    final busy = txt.contains('처리 중...') || !_confirmEnabled(t);
    feedback ??= busy ? s.now : null;
    if (spin) {
      spinnerOn ??= s.now;
      spinnerFrames++;
    } else if (spinnerOn != null) {
      spinnerOff ??= s.now;
    }
    final listShown = txt.contains('지원 (1건)') || txt.contains('확정 (1명)');
    if (!listShown) listHiddenFrom ??= s.now;
    if (s.respondedAt == null && txt.contains('확정 (1명)')) falseConfirmBeforeResponse = true;
    finalAt ??= (txt.contains('확정 (1명)') && !spin) ? s.now : null;
  }
  return {
    'feedback': feedback, 'serverResponse': s.respondedAt, 'spinnerOn': spinnerOn,
    'spinnerOff': spinnerOff, 'spinnerMs': spinnerFrames * 50, 'listHiddenFrom': listHiddenFrom,
    'finalConfirmedShown': finalAt, 'falseConfirmBeforeResponse': falseConfirmBeforeResponse,
    'reloadReads': Map.of(s.reads0), 'confirmCalls': s.confirmCalls,
  };
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
  });
  tearDown(() {
    DayApplicantsReads.debugOverride = null;
    ActionGuard.resetForTest();
  });

  testWidgets('PCL-1 확정 성공 — 탭→피드백→서버 응답→명단 정확 표시, 재조회 동안 명단 상태', (t) async {
    final s = _Timed();
    final m = await _measure(t, s);
    // ignore: avoid_print
    print('[PCL-1] $m');
    expect(m['confirmCalls'], 1);
    expect(m['falseConfirmBeforeResponse'], isFalse, reason: '서버 응답 전에 확정으로 보이면 안 된다');
    expect(m['finalConfirmedShown'], isNotNull);
  });
}
