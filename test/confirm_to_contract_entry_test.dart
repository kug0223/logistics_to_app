// [CONFIRM-TO-CONTRACT.21] 관리자 확정 → 계약서 작성(템플릿 선택) 진입.
//
// 예전: 확정 응답 뒤 명단 전체 재조회(2라운드 ~10건)를 다 기다린 다음에야 템플릿을 열었다
//   (LOCAL 실측 확정 탭 → 템플릿 시트 조작 가능 2.5~2.7초).
// 지금: 재조회를 출발시켜 두고, 이 한 명의 확정 지원서·계약 상태·근태만 한 라운드로 읽어
//   같은 판정(_needsContractIssue 의 세 사실)으로 바로 잇는다.
//
// 이 파일이 지키는 것:
//   CT-1 명단 재조회가 끝나지 않아도 템플릿 시트가 열린다(기다림 제거)
//   CT-2 확정 실패 — 판정 읽기도 시트도 없다
//   CT-3 판정 읽기 실패 — 확정은 다시 요청하지 않고 재조회 결과로 판정한다(예전 경로)
//   CT-4 연타·중도 이탈 — 확정 요청 1번, 떠난 뒤 시트 없음·예외 없음
//   CT-5 기존 차단 — 계약 있음·노쇼 근태·근태 모름·계약 권한 없음이면 잇지 않는다
//   CT-6 명단 재조회 실패가 판정된 진입을 오염시키지 않는다
//   CT-7 확정자 명단 동시 읽기는 한 번으로 합쳐진다(운영 reads)
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';

import 'package:ALfit/models/core/application_model.dart';
import 'package:ALfit/models/core/attendance_model.dart';
import 'package:ALfit/models/core/business_member_model.dart'
    show MemberPermissions;
import 'package:ALfit/models/core/business_model.dart';
import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/models/core/work_detail_data.dart';
import 'package:ALfit/models/ui/day_staffing_row.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/screens/business_admin/dialogs/day_applicants_dialog.dart';
import 'package:ALfit/screens/business_admin/dialogs/day_applicants_reads.dart';
import 'package:ALfit/services/contract_service.dart';
import 'package:ALfit/utils/action_guard.dart';
import 'package:ALfit/utils/format_helper.dart';
import 'package:ALfit/utils/navigation_key.dart';

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

const kBiz = 'BIZ';

class _Admin extends UserProvider {
  _Admin({this.contract = true});
  final bool contract;
  MemberPermissions get _p => MemberPermissions(
      canManageTo: true, canManageWorkers: true, canManageWage: true,
      canManageContract: contract);
  @override
  UserModel? get currentUser => UserModel(
      uid: 'OWNER', username: 'owner', name: '관리자',
      email: 'owner@test.local', role: UserRole.BUSINESS_ADMIN);
  @override
  bool get isSubAdmin => false;
  @override
  bool can(bool Function(MemberPermissions p) check) => check(_p);
  @override
  bool canForBusiness(String b, bool Function(MemberPermissions p) check) =>
      check(_p);
  @override
  PermissionCheck checkForBusiness(
          String businessId, bool Function(MemberPermissions p) check) =>
      check(_p) ? PermissionCheck.allowed : PermissionCheck.denied;
}

const _channel =
    'dev.flutter.pigeon.cloud_functions_platform_interface.CloudFunctionsHostApi.call';

/// 근무일 = 3일 뒤 KST 자정(저장 규칙).
final DateTime kDay = () {
  final k = DateTime.now().toUtc().add(const Duration(hours: 9));
  return DateTime.utc(k.year, k.month, k.day + 3)
      .subtract(const Duration(hours: 9));
}();

ApplicationModel _app(String status) => ApplicationModel(
      id: 'APP', uid: 'W', toId: 'TO', slotId: 'S', businessId: kBiz,
      businessName: 'QA 사업장', toTitle: 'QA 확정',
      selectedWorkType: 'QA 분류', wdId: 'wd1', startTime: '10:00',
      endTime: '11:00', wage: 12000, wageType: 'hourly', status: status,
      workDate: kDay, appliedAt: kDay.subtract(const Duration(days: 2)),
    );

WorkDetailData _wd() => WorkDetailData(
      wdId: 'wd1', workType: 'QA 분류', startTime: '10:00', endTime: '11:00',
      requiredCount: 2, wage: 12000, wageType: 'hourly',
      applicationDeadline: DateTime.now().add(const Duration(days: 2)),
    );

/// 서버 — 확정 커밋 여부로 읽기가 바뀐다. 각 읽기를 셀 수 있고 실패·지연을 줄 수 있다.
class _Server {
  bool deny = false;
  bool committed = false;
  int confirmCalls = 0;
  int confirmedReads = 0;
  int statusReads = 0;
  int attReads = 0;

  /// 확정 응답을 붙잡는 문(연타).
  Completer<void>? confirmGate;

  /// 커밋 뒤 명단 재조회 2라운드(사용자 일괄)를 붙잡는 문 — 기다림 제거 증명.
  Completer<void>? reloadGate;

  /// 커밋 뒤 확정자 명단 읽기를 붙잡는 문(중도 이탈).
  Completer<void>? confirmedGate;

  /// 커밋 뒤 첫 계약 상태 읽기를 실패시킨다(판정 읽기 실패).
  bool failFirstStatusAfterCommit = false;

  /// 커밋 뒤 사용자 일괄 읽기를 실패시킨다(명단 재조회 실패).
  bool failUsersAfterCommit = false;

  String? contractStatus; // 'pending_worker' 등 — 계약 있음
  String? attStatus; // 'no_show' 등 — 근태
  bool attFails = false;

  Future<ByteData?> handle(ByteData? message) async {
    final args = (const StandardMessageCodec().decodeMessage(message) as List)
        .first as Map;
    final name = args['functionName'] as String;
    if (name != 'callableConfirmApplication') return _err('not-found');
    confirmCalls++;
    if (confirmGate != null) await confirmGate!.future;
    if (deny) return _err('permission-denied');
    committed = true;
    return const StandardMessageCodec().encodeMessage(<Object?>[
      <String, Object?>{
        'success': true,
        'alreadyConfirmed': false,
        'autoCanceledDetails': <Object?>[],
        'appInfo': <String, Object?>{'toId': 'TO', 'uid': 'W'},
      }
    ]);
  }

  ByteData? _err(String code) => const StandardMessageCodec().encodeMessage(
      <Object?>[code, 'mock $code', <String, Object?>{'code': code}]);

  DayApplicantsReads reads() => DayApplicantsReads(
        pendingApplications: ({required date, required businessId, purpose}) async =>
            committed ? const [] : [_app(AppStatus.pending)],
        confirmedWorkers: ({required date, required businessId}) async {
          if (committed) {
            confirmedReads++;
            if (confirmedGate != null) await confirmedGate!.future;
          }
          return committed ? [_app(AppStatus.contractPending)] : const [];
        },
        dayStaffing: ({required businessId, required dayStartMs}) async => [
          DayStaffingRow(
            toId: 'TO', toTitle: 'QA 확정', slotId: 'S', wdId: 'wd1',
            workType: 'QA 분류', startTime: '10:00', endTime: '11:00',
            requiredCount: 2, confirmedCount: committed ? 1 : 0,
            pendingCount: committed ? 0 : 1,
          ),
        ],
        dayInvitations: ({required date, required businessId}) async => const [],
        hasWorkedMap: ({required businessId, required date}) async => const {},
        noShowApplicationIds: ({required businessId, required date}) async =>
            <String>{},
        usersBatch: (uids, {required businessId, purpose}) async {
          if (committed && reloadGate != null) await reloadGate!.future;
          if (committed && failUsersAfterCommit) throw Exception('users down');
          return {
            for (final u in uids)
              u: UserModel(uid: u, username: u, name: 'QA 근로자',
                  email: '$u@test.local', role: UserRole.USER),
          };
        },
        weeklyAttendance: ({required businessId, required weekStart,
                required weekEnd}) async =>
            <String, List<AttendanceModel>>{},
        slotWorkDetailCapacities: (toId, slotId) async => const {'wd1': 2},
        slotWorkDetails: (toId, slotId) async => [_wd()],
        to: (toId) async => null,
        contractStatusBatch: (ids, {required businessId}) async {
          if (committed) {
            statusReads++;
            if (failFirstStatusAfterCommit && statusReads == 1) {
              throw Exception('status down');
            }
          }
          return ContractStatusBatch(
              statuses: {for (final id in ids) id: contractStatus});
        },
        contractAttendances: ({required businessId, required date}) async {
          if (committed) attReads++;
          if (attFails) throw Exception('att down');
          if (attStatus == null) return const <AttendanceModel>[];
          final a = _app(AppStatus.contractPending);
          return [
            AttendanceModel(
              id: '${a.id}_${FormatHelper.formatDateStamp(a.workDate)}',
              applicationId: a.id, userId: a.uid, businessId: kBiz,
              businessName: 'QA 사업장', workDate: a.workDate,
              workType: 'QA 분류', status: attStatus!, createdAt: a.workDate,
            ),
          ];
        },
      );
}

Future<void> _settle(WidgetTester t, [int n = 30]) async {
  for (var i = 0; i < n; i++) {
    await t.pump(const Duration(milliseconds: 50));
  }
}

void _stubAuthChannels(WidgetTester t) {
  const base =
      'dev.flutter.pigeon.firebase_auth_platform_interface.FirebaseAuthHostApi';
  for (final m in ['registerIdTokenListener', 'registerAuthStateListener']) {
    t.binding.defaultBinaryMessenger.setMockMessageHandler('$base.$m',
        (_) async => const StandardMessageCodec()
            .encodeMessage(<Object?>['test/auth-events']));
  }
  t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('test/auth-events'), (_) async => null);
}

Future<void> _pump(WidgetTester t, _Server server, {bool contract = true}) async {
  t.view.physicalSize = const Size(411, 2400);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  _stubAuthChannels(t);
  t.binding.defaultBinaryMessenger.setMockMessageHandler(_channel, server.handle);
  addTearDown(() =>
      t.binding.defaultBinaryMessenger.setMockMessageHandler(_channel, null));
  await t.pumpWidget(ChangeNotifierProvider<UserProvider>(
    create: (_) => _Admin(contract: contract),
    child: MaterialApp(
      navigatorKey: navigatorKey,
      home: Scaffold(
        body: DayApplicantsDialog(
          key: UniqueKey(),
          date: kDay,
          businessIds: const [kBiz],
          businesses: [
            BusinessModel(id: kBiz, name: 'QA 사업장', businessNumber: '000-00-00000',
                category: '음식점', subCategory: '한식', address: '서울특별시 강남구 테헤란로 1',
                ownerId: 'OWNER', createdAt: DateTime(2026, 9, 1)),
          ],
          reads: server.reads(),
        ),
      ),
    ),
  ));
  await _settle(t);
}

Finder _confirmButton() => find.descendant(
    of: find.byType(DayApplicantsDialog),
    matching: find.byWidgetPredicate((w) =>
        w is InkWell &&
        w.child is Container &&
        (w.child as Container).child is Text &&
        ((w.child as Container).child as Text).data == '확정'));

Future<void> _tapConfirm(WidgetTester t, {bool settle = true}) async {
  final btn = _confirmButton();
  await t.ensureVisible(btn.first);
  await t.tap(btn.first);
  await _settle(t, 6);
  await t.tap(find.text('확정').last); // 확인창
  if (settle) await _settle(t, 40);
}

final _sheet = find.text('계약서 템플릿 선택');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
  });
  tearDown(ActionGuard.resetForTest);

  testWidgets('CT-0 출발점 — 대기 지원자 `확정` 버튼', (t) async {
    await _pump(t, _Server());
    expect(_confirmButton(), findsOneWidget);
  });

  testWidgets('CT-1 명단 재조회가 끝나기 전에 템플릿 시트가 열린다', (t) async {
    final server = _Server()..reloadGate = Completer<void>();
    await _pump(t, server);
    await _tapConfirm(t);

    expect(server.confirmCalls, 1);
    expect(_sheet, findsOneWidget,
        reason: '판정은 이 한 명의 세 사실로 끝난다 — 명단 재조회(2라운드)를 기다리지 않는다');
    expect(server.reloadGate!.isCompleted, isFalse,
        reason: '재조회 2라운드(사용자 일괄)는 아직 붙잡혀 있다');

    server.reloadGate!.complete();
    await _settle(t, 20);
    expect(_sheet, findsOneWidget, reason: '재조회가 끝나도 시트는 그대로');
    expect(server.confirmCalls, 1);
  });

  testWidgets('CT-2 확정 실패 — 판정 읽기·시트 없음, 대기 그대로', (t) async {
    final server = _Server()..deny = true;
    await _pump(t, server);
    await _tapConfirm(t);

    expect(server.confirmCalls, 1);
    expect(server.statusReads + server.confirmedReads, 0);
    expect(_sheet, findsNothing);
    expect(_confirmButton(), findsOneWidget);
    await t.pump(const Duration(seconds: 5)); // 토스트 타이머
  });

  testWidgets('CT-3 판정 읽기 실패 — 확정 재요청 없이 재조회 결과로 잇는다', (t) async {
    final server = _Server()..failFirstStatusAfterCommit = true;
    await _pump(t, server);
    await _tapConfirm(t);

    expect(server.confirmCalls, 1, reason: '확정은 다시 요청하지 않는다');
    expect(server.statusReads, 2, reason: '판정 1(실패) + 재조회 1');
    expect(_sheet, findsOneWidget, reason: '재조회 결과로 같은 판정 — 계약 없음 확인');
  });

  testWidgets('CT-4a 응답 대기 중 연타 — 확정 요청 1번', (t) async {
    final server = _Server()..confirmGate = Completer<void>();
    await _pump(t, server);
    await _tapConfirm(t, settle: false);
    await _settle(t, 4);
    if (_confirmButton().evaluate().isNotEmpty) {
      await t.tap(_confirmButton().first, warnIfMissed: false);
      await _settle(t, 4);
    }
    server.confirmGate!.complete();
    await _settle(t, 40);
    expect(server.confirmCalls, 1);
    expect(_sheet, findsOneWidget);
  });

  testWidgets('CT-4b 판정 읽기 중 화면을 떠나면 — 시트·예외 없음', (t) async {
    final server = _Server()..confirmedGate = Completer<void>();
    await _pump(t, server);
    await _tapConfirm(t, settle: false);
    await _settle(t, 6);
    await t.pumpWidget(const SizedBox.shrink());
    server.confirmedGate!.complete();
    await _settle(t, 20);
    expect(server.confirmCalls, 1);
    expect(_sheet, findsNothing);
    expect(t.takeException(), isNull);
    await t.pump(const Duration(seconds: 5)); // 확정 성공 토스트 타이머
  });

  group('CT-5 기존 차단 유지', () {
    testWidgets('계약서가 이미 있다 — 잇지 않는다', (t) async {
      final server = _Server()..contractStatus = 'pending_worker';
      await _pump(t, server);
      await _tapConfirm(t);
      expect(_sheet, findsNothing);
      expect(server.confirmCalls, 1);
    });
    testWidgets('그 근무일 노쇼 — 잇지 않는다', (t) async {
      final server = _Server()..attStatus = AttendanceModel.statusNoShow;
      await _pump(t, server);
      await _tapConfirm(t);
      expect(_sheet, findsNothing);
    });
    testWidgets('근태를 모른다(조회 실패) — 단기는 잇지 않는다', (t) async {
      final server = _Server()..attFails = true;
      await _pump(t, server);
      await _tapConfirm(t);
      expect(_sheet, findsNothing);
    });
    testWidgets('계약 권한 없음 — 판정 읽기도 하지 않고 잇지 않는다', (t) async {
      final server = _Server();
      await _pump(t, server, contract: false);
      await _tapConfirm(t);
      expect(_sheet, findsNothing);
      expect(server.statusReads, 1, reason: '재조회의 계약 상태만 — 판정 읽기 없음');
      await t.pump(const Duration(seconds: 5));
    });
  });

  testWidgets('CT-6 명단 재조회 실패 — 판정된 진입은 그대로 열린다', (t) async {
    final server = _Server()..failUsersAfterCommit = true;
    await _pump(t, server);
    await _tapConfirm(t);
    expect(server.confirmCalls, 1);
    expect(_sheet, findsOneWidget,
        reason: '재조회 실패가 이미 확인된 판정(확정·계약 없음·근태 통과)을 지우지 않는다');
    await t.pump(const Duration(seconds: 5));
  });

  test('CT-7 운영 reads — 확정자 명단·계약 판정 근태 동시 읽기는 한 요청을 함께 쓴다(소스 계약)', () {
    // 운영 구현은 FirestoreService 를 부른다 — 여기서는 공유 키가 걸려 있는지만 본다.
    final src = File('lib/screens/business_admin/dialogs/day_applicants_reads.dart')
        .readAsStringSync();
    expect(src.contains("'confirmed|\$businessId|"), isTrue);
    // [STATUS-DIALOG-READS.27] 계약 판정 근태는 같은 날 근태 공유 요청(dayRaw)을 쓴다 — 행동은 DSA-5·6.
    expect(src.contains('contractAttendances: ({required businessId, required date}) =>'), isTrue);
    expect(src.contains('dayRaw(businessId, date).then((r) {'), isTrue);
  });
}
