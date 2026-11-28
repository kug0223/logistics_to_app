// [impl_56 · AUD-4 H6] 계약서 관리 — 읽는 중에 탭을 바꾸면 새 탭을 읽지 않고 앞 탭 결과를 지금 탭에 그리던 것.
//   하네스(가짜 Firebase · SubAdmin · 계약/미발송 fixture)는 du1_s006_contract_mgmt_342_test 와 같다.
// ignore_for_file: depend_on_referenced_packages
import 'dart:async';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';

import 'package:ALfit/models/core/application_model.dart';
import 'package:ALfit/models/core/business_member_model.dart';
import 'package:ALfit/models/core/employment_contract_model.dart';
import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/providers/notification_provider.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/screens/business_admin/admin_contract_management_screen.dart';
import 'package:ALfit/screens/business_admin/admin_contract_reads.dart';
import 'package:ALfit/theme/role_theme.dart';

import 'support/visible_text.dart';

const kBiz = 'biz1';

class _FakeApp extends Fake with MockPlatformInterfaceMixin implements FirebaseAppPlatform {
  @override
  String get name => defaultFirebaseAppName;
  @override
  FirebaseOptions get options => const FirebaseOptions(apiKey: 'k', appId: 'a', messagingSenderId: 's', projectId: 'p');
}

class _FakeCore extends FirebasePlatform with MockPlatformInterfaceMixin {
  @override
  FirebaseAppPlatform app([String name = defaultFirebaseAppName]) => _FakeApp();
  @override
  Future<FirebaseAppPlatform> initializeApp({String? name, FirebaseOptions? options}) async => _FakeApp();
  @override
  List<FirebaseAppPlatform> get apps => [_FakeApp()];
}


class _SubAdmin extends UserProvider {
  MemberPermissions get _perms =>
      MemberPermissions(canManageTo: true, canManageWorkers: true, canManageWage: false, canManageContract: true);
  @override
  UserModel? get currentUser => UserModel(
      uid: 'sub1', username: 'sub1', name: '이대리', email: 'sub1@alfit.local', role: UserRole.USER,
      subAdminBusinessIds: const [kBiz], createdAt: DateTime(2026, 1, 1));
  @override
  bool get isSubAdmin => true;
  @override
  bool get isBusinessAdmin => false;
  @override
  bool get isSuperAdmin => false;
  @override
  bool get isAdminMode => true;
  @override
  bool get permissionsLoaded => true;
  @override
  String? get selectedSubAdminBusinessId => kBiz;
  @override
  MemberPermissions? permissionsForBusiness(String businessId) => _perms;
  @override
  PermissionCheck checkCurrentBusiness(bool Function(MemberPermissions p) check) =>
      check(_perms) ? PermissionCheck.allowed : PermissionCheck.denied;
  @override
  bool can(bool Function(MemberPermissions p) check) => check(_perms);
  @override
  bool canForBusiness(String businessId, bool Function(MemberPermissions p) check) => check(_perms);
  @override
  VoidCallback watchBusinessPermissions(String businessId) => () {};
}

EmploymentContractModel _contract(String id, ContractStatus st, String worker) => EmploymentContractModel(
    id: id, applicationId: 'app_$id', businessId: kBiz, workerId: 'wk_$id', isLongTerm: false, toId: '', workDetailId: 'wd1',
    status: st,
    snapshot: ContractSnapshot(
        businessName: '[QA] 아주 긴 이름의 강남 물류센터 평택 2공장', businessNumber: '000-00-00000', businessAddress: '서울',
        ownerName: '사업주', workerName: worker, workType: '냉장 피킹·검수 보조', workPlace: '서울', isLongTerm: false,
        contractStart: '2026-10-20', contractEnd: '2026-10-20', workDays: const [], startTime: '10:00', endTime: '11:00',
        breakMinutes: 0, wage: 12000, wageType: 'hourly', paymentMethod: '계좌이체', wagePaymentDay: 10, taxDeductionType: 'none'),
    createdAt: DateTime(2026, 10, 17));

ApplicationModel _unsent(String id, String name) => ApplicationModel(
    id: id, businessId: kBiz, businessName: '[QA] 아주 긴 이름의 강남 물류센터 평택 2공장', toTitle: 'QA 단기',
    workDate: DateTime(2026, 11, 20), startTime: '09:00', endTime: '18:00', uid: 'u_$id', selectedWorkType: '냉장 피킹·검수 보조',
    wage: 12000, wageType: 'hourly', status: AppStatus.confirmed, appliedAt: DateTime(2026, 11, 1), applicantName: name);



typedef _Page = ({List<EmploymentContractModel> items, String? lastDocId, bool hasMore});

final _all = [
  _contract('c1', ContractStatus.pendingEmployer, '홍길동'),
  _contract('c2', ContractStatus.pendingWorker, '김민수'),
  _contract('c3', ContractStatus.completed, '박지영'),
  _contract('c4', ContractStatus.voided, '이서준'),
];

/// 첫 '전체' 읽기만 늦게 끝나게(Completer) — 그 사이 탭을 바꾼다.
class _SlowReads {
  final first = Completer<_Page>();
  final calls = <String>[];
  late final reads = AdminContractReads(
    contractsPaged: (businessId, {startAfterId, statusFilter}) {
      calls.add('paged:${statusFilter?.name ?? 'all'}');
      if (statusFilter == null && calls.where((c) => c == 'paged:all').length == 1) return first.future;
      return Future.value((items: statusFilter == null ? _all : _all.where((c) => c.status == statusFilter).toList(),
          lastDocId: null, hasMore: false));
    },
    unsentApplications: (businessId) async {
      calls.add('unsent');
      return [_unsent('u1', '최지원')];
    },
  );
}

Future<void> _pump(WidgetTester t, _SlowReads r) async {
  t.view.physicalSize = const Size(411, 1400);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider<UserProvider>(create: (_) => _SubAdmin()),
      ChangeNotifierProvider<NotificationProvider>(create: (_) => NotificationProvider()),
    ],
    child: MaterialApp(
      theme: RoleTheme.businessAdminTheme,
      home: AdminContractManagementScreen(businessId: kBiz, businessName: '[QA] 사업장', initialTab: 0, reads: r.reads),
    ),
  ));
  await t.pump(const Duration(milliseconds: 50));
}

Future<void> _settle(WidgetTester t) async {
  for (var i = 0; i < 20; i++) {
    await t.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
    await initializeDateFormatting('ko_KR');
  });

  testWidgets('T1 전체 읽는 중 → 완료 탭 → 늦게 끝난 전체 결과를 완료 탭에 그리지 않고 완료 탭을 다시 읽는다', (t) async {
    final r = _SlowReads();
    await _pump(t, r);
    await t.tap(find.text('완료'));
    await _settle(t);
    r.first.complete((items: _all, lastDocId: null, hasMore: false));
    await _settle(t);
    expect(r.calls, containsAllInOrder(['paged:all', 'paged:completed']), reason: '${r.calls}');
    expect(findVisibleTextContaining('박지영'), findsWidgets);
    expect(findVisibleTextContaining('김민수'), findsNothing, reason: '앞 탭(전체) 결과가 완료 탭에 남았다');
    expect(findVisibleTextContaining('이서준'), findsNothing);
  });

  testWidgets('T2 전체 읽는 중 → 미발송 탭 → 미발송을 읽어 보여 준다(없음 오표시 0)', (t) async {
    final r = _SlowReads();
    await _pump(t, r);
    await t.tap(find.text('미발송'));
    await _settle(t);
    r.first.complete((items: _all, lastDocId: null, hasMore: false));
    await _settle(t);
    expect(r.calls, contains('unsent'), reason: '${r.calls}');
    expect(findVisibleTextContaining('최지원'), findsWidgets);
  });

  test('T3 소스 — 읽는 중 요청은 끝난 뒤 다시 읽기 · 결과는 시작한 탭일 때만 그린다', () {
    final s = File('lib/screens/business_admin/admin_contract_management_screen.dart').readAsStringSync();
    final b = s.substring(s.indexOf('Future<void> _load({bool useCache = true}) async {'), s.indexOf('// pull-to-refresh'));
    expect(b.contains('_reloadPending = true;'), isTrue);
    expect(b.contains('if (_tabCtrl.index != tabIdx) return;'), isTrue);
    expect(b.contains('_load(useCache: !noCache);'), isTrue);
    expect(b.contains('if (!mounted || _fetchInProgress) return;'), isFalse);
  });
}
