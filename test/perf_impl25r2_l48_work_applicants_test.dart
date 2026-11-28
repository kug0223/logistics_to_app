// [PERF impl_25 r2 · L48 · 2026-11-27] 업무별 지원자 다이얼로그 — 읽기 차례 + 처리 뒤 화면 유지(SWR · 잠금).
//
//   W1 동치 — 같은 입력이면 명단 유지 다시 읽기의 최종 화면 = 처음 화면 · 바뀐 입력이면 = 새로 연 화면
//   W2 명단 유지 다시 읽는 중 — 전체 스피너 0 · 이전 명단 유지 · 진행 표시 · 누르기 잠금
//   W3 늦은 응답 — 먼저 시작한 읽기(옛 데이터)가 나중에 끝나도 새 명단을 덮지 않는다
//   W4 다시 읽기 실패 — 예전과 같은 결과(이전 명단 + '최신 정보를 불러오지 못했어요' 배너) · 잠금 해제
//   W5 겹친 읽기의 표식 — 늦게 끝난 옛 읽기의 성공이 마지막 읽기의 실패(배너)를 지우지 않는다
// ignore_for_file: depend_on_referenced_packages
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';

import 'package:ALfit/models/core/application_model.dart';
import 'package:ALfit/models/core/attendance_model.dart';
import 'package:ALfit/models/core/business_member_model.dart';
import 'package:ALfit/models/core/slot_model.dart' show SlotModel, SlotStatus;
import 'package:ALfit/models/core/to_model.dart';
import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/models/core/work_detail_data.dart';
import 'package:ALfit/models/ui/admin_to_list_ui_models.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/screens/business_admin/dialogs/work_applicants_dialog.dart';
import 'package:ALfit/screens/business_admin/dialogs/work_applicants_reads.dart';
import 'package:ALfit/services/contract_service.dart';

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

class _Owner extends UserProvider {
  @override
  UserModel? get currentUser => UserModel(uid: 'owner1', username: 'owner1', name: '관리자', email: 'o@alfit.local',
      role: UserRole.BUSINESS_ADMIN, businessId: 'biz1', createdAt: DateTime(2026, 1, 1));
  @override
  bool get isBusinessAdmin => true;
  @override
  bool get isSubAdmin => false;
  @override
  bool get isSuperAdmin => false;
  @override
  bool get isAdminMode => true;
  @override
  bool get permissionsLoaded => true;
  @override
  bool can(bool Function(MemberPermissions p) c) => true;
  @override
  bool canForBusiness(String b, bool Function(MemberPermissions p) c) => true;
  @override
  PermissionCheck checkForBusiness(String businessId, bool Function(MemberPermissions p) check) =>
      PermissionCheck.allowed;
}

final _day = DateTime.now().add(const Duration(days: 3));
const _work = WorkDetailData(
    wdId: 'wd1', workType: '홀서빙', wage: 12000, requiredCount: 3, startTime: '09:00', endTime: '18:00');

ApplicationModel _app(String id, String uid, String status) => ApplicationModel(
      id: id, uid: uid, toId: 'to1', slotId: 's1', businessId: 'biz1', businessName: '테스트 사업장',
      toTitle: '테스트 공고', selectedWorkType: '홀서빙', wdId: 'wd1', startTime: '09:00', endTime: '18:00',
      wage: 12000, wageType: 'hourly', status: status, workDate: _day, appliedAt: _day,
    );

final _d1 = [_app('a1', 'u1', AppStatus.pending), _app('a3', 'u3', AppStatus.pending), _app('a2', 'u2', AppStatus.confirmed)];
final _d2 = [_app('a1', 'u1', AppStatus.confirmed), _app('a2', 'u2', AppStatus.confirmed)]; // u1 확정 · u3 거절(빠짐)

class _Reads {
  _Reads(this.data);
  List<ApplicationModel> data;
  final gates = <Completer<void>>[];
  bool holdNext = false;
  bool failNext = false;

  WorkApplicantsReads build() => WorkApplicantsReads(
        applications: (to, {slotId, required purpose}) async {
          final snap = data;
          final fail = failNext;
          failNext = false;
          if (holdNext) {
            holdNext = false;
            final g = Completer<void>();
            gates.add(g);
            await g.future;
          }
          if (fail) throw StateError('applications read failed');
          return snap;
        },
        usersBatch: (uids, {required businessId, purpose}) async => {
          for (final u in uids)
            u: UserModel(uid: u, username: u, name: '근로자 $u', email: '$u@test.local', role: UserRole.USER),
        },
        weeklyAttendance: ({required businessId, required weekStart, required weekEnd}) async =>
            <String, List<AttendanceModel>>{},
        contractStatusBatch: (ids, {required businessId}) async => const ContractStatusBatch(),
        hasWorkedMap: ({required businessId, required date}) async => const {},
        idCardStatusBatch: ({required requesterId, required targetUserIds}) async => const {},
        capacity: (to, {slotId, slotWorkDetails}) async => {
          'workDetails': [_work],
          'workStats': {'wd1': {'confirmed': data.where((a) => a.status == AppStatus.confirmed).length, 'pending': 0}},
          'statsFailed': false,
        },
        reassignProposals: (bizId) async => const [],
        contractAttendances: ({required businessId, required first, required last}) async =>
            const <AttendanceModel>[],
      );
}

TOItem _item() {
  final to = TOModel(id: 'to1', businessId: 'biz1', businessName: '테스트 사업장', type: 'flex', title: '테스트 공고',
      creatorUID: 'owner1', status: 'ACTIVE', workDetails: const [_work], totalRequired: 3, totalConfirmed: 1,
      totalPending: 2, isPublished: true, publishMode: 'immediate',
      createdAt: DateTime.now().subtract(const Duration(days: 1)),
      statusUpdatedAt: DateTime.now().subtract(const Duration(days: 1)));
  return TOItem(
      to: to,
      slot: SlotModel(id: 's1', toId: 'to1', date: _day, status: SlotStatus.open, workDetails: const [_work],
          createdAt: DateTime.now().subtract(const Duration(days: 1))),
      confirmedCount: 1, pendingCount: 2, totalRequired: 3);
}

Future<void> _settle(WidgetTester t) async {
  for (var i = 0; i < 40; i++) {
    await t.pump(const Duration(milliseconds: 50));
  }
}

Future<Future<void> Function()> _open(WidgetTester t, _Reads r) async {
  WorkApplicantsReads.debugOverride = r.build();
  t.view.physicalSize = const Size(411, 3200);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  late Future<void> Function() reload;
  await t.pumpWidget(ChangeNotifierProvider<UserProvider>(
    create: (_) => _Owner(),
    child: MaterialApp(
      home: Scaffold(
        body: WorkApplicantsDialog(
            key: UniqueKey(), toItem: _item(), work: _work, onChanged: () {},
            debugReloadHook: (f) => reload = f),
      ),
    ),
  ));
  await _settle(t);
  return reload;
}

String _texts(WidgetTester t) => t
    .widgetList<Text>(find.byType(Text))
    .map((w) => visibleText(w.data ?? w.textSpan?.toPlainText() ?? ''))
    .where((s) => s.isNotEmpty)
    .join(' | ');

const _progress = ValueKey('work-applicants-refresh-after-mutation');
bool _spinnerShown(WidgetTester t) =>
    find.byWidgetPredicate((w) => w.runtimeType.toString() == 'LoadingWidget').evaluate().isNotEmpty;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
  });
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMessageHandler(
        'dev.flutter.pigeon.cloud_functions_platform_interface.CloudFunctionsHostApi.call',
        (data) async => const StandardMessageCodec().encodeMessage(<Object?>['unavailable', 'test harness', null]));
  });
  tearDown(() => WorkApplicantsReads.debugOverride = null);

  testWidgets('W1 동치 — 같은 입력 = 처음 화면 · 바뀐 입력 = 새로 연 화면', (t) async {
    final r = _Reads(_d1);
    final reload = await _open(t, r);
    final fresh1 = _texts(t);
    expect(fresh1, contains('근로자 u3'));
    unawaited(reload());
    await _settle(t);
    expect(_texts(t), fresh1);
    r.data = _d2;
    unawaited(reload());
    await _settle(t);
    final viaReload = _texts(t);
    await _open(t, _Reads(_d2));
    expect(viaReload, _texts(t), reason: '명단을 유지한 채 다시 읽은 최종 상태가 새로 연 화면과 다르다');
    expect(viaReload, isNot(contains('근로자 u3')));
  });

  testWidgets('W2 명단 유지 다시 읽는 중 — 전체 스피너 0 · 이전 명단 · 진행 표시 · 잠금', (t) async {
    final r = _Reads(_d1);
    final reload = await _open(t, r);
    r.holdNext = true;
    r.data = _d2;
    unawaited(reload());
    await t.pump(const Duration(milliseconds: 100));
    expect(_spinnerShown(t), isFalse, reason: '처리 뒤 다시 읽기가 명단을 지우고 스피너를 띄웠다');
    expect(find.byKey(_progress), findsOneWidget);
    expect(_texts(t), contains('근로자 u3'));
    final absorbing = t
        .widgetList<AbsorbPointer>(
            find.ancestor(of: findVisibleTextContaining('근로자 u3').first, matching: find.byType(AbsorbPointer)))
        .any((w) => w.absorbing);
    expect(absorbing, isTrue, reason: '처리 전 명단으로 다시 처리할 수 있다');
    r.gates.single.complete();
    await _settle(t);
    expect(find.byKey(_progress), findsNothing);
    expect(_texts(t), isNot(contains('근로자 u3')));
  });

  testWidgets('W3 늦은 응답 — 먼저 시작한 옛 읽기가 나중에 끝나도 새 명단 유지', (t) async {
    final r = _Reads(_d1);
    final reload = await _open(t, r);
    r.holdNext = true;
    unawaited(reload()); // 옛 데이터(_d1)를 들고 멈춤
    await t.pump(const Duration(milliseconds: 50));
    r.data = _d2;
    unawaited(reload());
    await _settle(t);
    final after2 = _texts(t);
    expect(after2, isNot(contains('근로자 u3')));
    r.gates.single.complete();
    await _settle(t);
    expect(_texts(t), after2, reason: '늦게 끝난 옛 읽기가 새 명단을 덮었다');
    expect(find.byKey(_progress), findsNothing);
  });

  testWidgets('W4 다시 읽기 실패 — 이전 명단 + 새로고침 실패 배너(예전과 같음) · 잠금 해제', (t) async {
    final r = _Reads(_d1);
    final reload = await _open(t, r);
    r.failNext = true;
    unawaited(reload());
    await _settle(t);
    expect(_texts(t), contains('근로자 u3'));
    expect(findVisibleTextContaining('최신 정보를 불러오지 못했어요'), findsOneWidget);
    expect(find.byKey(_progress), findsNothing);
    expect(_spinnerShown(t), isFalse);
  });

  testWidgets('W5 겹친 읽기 표식 — 늦게 끝난 옛 읽기의 성공이 새 읽기의 실패를 지우지 않는다(낡은 명단을 최신처럼 말하지 않음)', (t) async {
    final r = _Reads(_d1);
    final reload = await _open(t, r);
    r.holdNext = true; // 옛 읽기: 멈췄다가 성공(옛 데이터)
    unawaited(reload());
    await t.pump(const Duration(milliseconds: 50));
    r.failNext = true; // 새 읽기: 실패
    unawaited(reload());
    await _settle(t);
    expect(findVisibleTextContaining('최신 정보를 불러오지 못했어요'), findsOneWidget);
    r.gates.single.complete(); // 옛 읽기의 성공이 이제 도착
    await _settle(t);
    expect(findVisibleTextContaining('최신 정보를 불러오지 못했어요'), findsOneWidget,
        reason: '늦게 끝난 옛 읽기의 성공이 마지막 읽기의 실패를 지웠다 — 낡은 명단을 최신처럼 말한다');
    expect(find.byKey(_progress), findsNothing);
  });
}
