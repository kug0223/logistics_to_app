// ignore_for_file: depend_on_referenced_packages
// [CORE-CONTRACT-GATE-AND-INVITE.2 · B] G1 — 출근 화면이 계약 상태별로 출근을 막는가.
//
//   .2(2026-10-25 오전)에는 "막지 않는다"(a713dbc 2026-09-16 동작)를 기록했다.
//   [CONTRACT-BEFORE-CHECKIN.3] 같은 날 사용자 지시("미동의면 출근 버튼 비활성")로 기대를 바꿨다:
//   양측 서명 완료(G1-4)만 열리고 나머지는 닫힌다. 계약 문서는 화면이 새로 읽은 목록(myContracts)이다.
//
//   계약 문서는 CORE.1 사슬에서 **배포 서명 writer 가 만든 실제 문서**(GP_RUN/dump-final.json)를
//   앱 모델로 읽어, 상태만 바꿔 넣는다(미서명 목록에는 pending_worker 만 들어간다 — UserProvider.refreshPendingContracts).
//   GP_RUN 이 없으면 건너뛴다.
import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ALfit/models/core/application_model.dart';
import 'package:ALfit/models/core/attendance_model.dart';
import 'package:ALfit/models/core/employment_contract_model.dart';
import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/models/core/user_region.dart';
import 'package:ALfit/providers/notification_provider.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/screens/user/attendance_check_reads.dart';
import 'package:ALfit/screens/user/attendance_check_screen.dart';
import 'package:ALfit/widgets/common/loading_button.dart';
import '../support/visible_text.dart'; // [impl_21] TextLayout 문구는 보이는 글자로 찾는다

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

class _P extends UserProvider {
  _P(this.pending);
  final EmploymentContractModel? pending;
  @override
  UserModel? get currentUser => UserModel(
      uid: 'gp_w1', username: 'gp_w1', name: '합성 근로자', email: '', role: UserRole.USER,
      homeRegion: const UserRegion(province: '서울특별시', city: '강남구'), accountStatus: 'active');
  @override
  bool get isSubAdmin => false;
  @override
  bool get isBusinessAdmin => false;
  @override
  bool get isSuperAdmin => false;
  @override
  bool get isAdminMode => false;
  @override
  bool get permissionsLoaded => true;
  @override
  EmploymentContractModel? pendingContractForTo(String toId) =>
      pending != null && pending!.toId == toId ? pending : null;
}

final _run = Platform.environment['GP_RUN'];
Object? _restore(Object? v) => v is Map
    ? (v.length == 1 && v.containsKey('__ts')
        ? Timestamp.fromMillisecondsSinceEpoch((v['__ts'] as num).toInt())
        : v.map((k, x) => MapEntry(k as String, _restore(x))))
    : v is List
        ? v.map(_restore).toList()
        : v;

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
    await initializeDateFormatting('ko_KR', null);
  });
  final ok = _run != null && File('$_run/dump-final.json').existsSync();

  late Map<String, dynamic> dump;
  late Map<String, dynamic> st;
  if (ok) {
    dump = (_restore(jsonDecode(File('$_run/dump-final.json').readAsStringSync())) as Map).cast<String, dynamic>();
    st = (jsonDecode(File('$_run/state.json').readAsStringSync()) as Map).cast<String, dynamic>();
  }

  // 출근 가능 시각 안의 '지금' — 그 근무 시작 시각(KST)
  DateTime nowAtStart(ApplicationModel a) {
    final k = a.workDate.toUtc().add(const Duration(hours: 9));
    final hm = a.startTime.split(':').map(int.parse).toList();
    return DateTime.utc(k.year, k.month, k.day, hm[0], hm[1]).subtract(const Duration(hours: 9));
  }

  Future<void> pump(WidgetTester t, ApplicationModel app, EmploymentContractModel? pending,
      List<EmploymentContractModel> contracts) async {
    t.view.physicalSize = const Size(390, 2200);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    final reads = AttendanceCheckReads(
      myApplications: (uid) async => [app],
      todayAttendance: ({required String userId, required String applicationId}) async => null as AttendanceModel?,
      myContracts: (uid) async => contracts,
    );
    final now = nowAtStart(app);
    await t.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<UserProvider>(create: (_) => _P(pending)),
        ChangeNotifierProvider<NotificationProvider>(create: (_) => NotificationProvider()),
      ],
      child: MaterialApp(home: AttendanceCheckScreen(reads: reads, clock: () => now)),
    ));
    for (var i = 0; i < 20; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
  }

  LoadingButton btn(WidgetTester t) =>
      t.widget<LoadingButton>(find.ancestor(of: findVisibleText('출근하기'), matching: find.byType(LoadingButton)));

  // (지원서 상태, 계약 상태) — 계약 상태 null = 계약 문서 없음
  final cases = <(String, String, ContractStatus?)>[
    ('G1-1', 'CONTRACT_PENDING', null),
    ('G1-2', 'CONTRACT_PENDING', ContractStatus.pendingEmployer),
    ('G1-3', 'CONTRACT_PENDING', ContractStatus.pendingWorker),
    ('G1-4', 'CONFIRMED', ContractStatus.completed),
  ];
  for (final (id, appStatus, cs) in cases) {
    testWidgets('$id 지원서 $appStatus · 계약 ${cs?.value ?? '없음'} — 출근 버튼·안내', (t) async {
      final appMap = Map<String, dynamic>.from(dump['application'] as Map)..['status'] = appStatus;
      final app = ApplicationModel.fromMap(appMap, st['applicationId'] as String);
      final base = EmploymentContractModel.fromMap(Map<String, dynamic>.from(dump['contract'] as Map), 'c1');
      // 미서명 목록 = pending_worker 만(앱 refreshPendingContracts 의 statusFilter)
      final pending = cs == ContractStatus.pendingWorker ? base.copyWith(status: cs) : null;
      // 화면 gate 근거 = 근로자 계약 목록(getMyContracts) — 이 근무의 계약 한 건을 그 상태로
      final contracts = cs == null ? <EmploymentContractModel>[] : [base.copyWith(status: cs)];
      await pump(t, app, pending, contracts);
      final enabled = btn(t).onPressed != null;
      final warn = findVisibleText('계약서 확인하고 동의하기').evaluate().isNotEmpty;
      // ignore: avoid_print
      print('   $id app=$appStatus contract=${cs?.value ?? '-'} → 출근 버튼 ${enabled ? '활성' : '비활성'} · 서명 안내 ${warn ? '표시' : '없음'}');
      expect(findVisibleText('출근하기'), findsOneWidget);
      expect(enabled, cs == ContractStatus.completed,
          reason: '양측 서명 완료만 출근을 연다(2026-10-25 사용자 지시) — a713dbc 의 "막지 않는다"는 폐기');
      expect(warn, cs == ContractStatus.pendingWorker);
    }, skip: !ok);
  }
}
