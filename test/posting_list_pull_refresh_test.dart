// [SIM-ADJ-3] 공고 탭 — 실제 당겨서 새로고침 제스처가 서버를 다시 읽는가.
//
// DEVICE 관찰(DEV 확정 셀): 확정 뒤 공고 탭에서 당겨서 새로고침을 해도 카드가
//   `충원 0 / 필요 1 · 대기 1` 로 진행중 탭에 남았다. DEV 원장은 이미 FULL
//   (확정 1·대기 0)이었다.
//
// root cause (이 하네스로 재현): 목록 `ListView.builder` 는 자기 controller 를
//   가지므로 primary 가 아니고, physics 를 지정하지 않아
//   AlwaysScrollableScrollPhysics 가 붙지 않는다. 카드가 화면보다 짧으면
//   (DEV: 2장) 끌어도 스크롤이 생기지 않고 RefreshIndicator 가 **발동하지 않는다**.
//
// 하네스: 실제 WorkforceListView + 실제 WorkforceController.reload.
//   공고 목록은 callableGetAdminTOs 플랫폼 채널, 슬롯·업무 통계는 controller 의
//   기존 읽기 주입점으로 같은 서버 상태를 돌려준다. DEV 호출 없음.
import 'support/visible_text.dart';
import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';

import 'package:ALfit/controllers/workforce_controller.dart';
import 'package:ALfit/models/core/business_member_model.dart'
    show MemberPermissions;
import 'package:ALfit/models/core/slot_model.dart' show SlotModel, SlotStatus;
import 'package:ALfit/models/core/to_model.dart';
import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/models/core/work_detail_data.dart';
import 'package:ALfit/models/ui/admin_to_list_ui_models.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/screens/business_admin/workforce_management/workforce_list_view.dart';
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

class _AdminP extends UserProvider {
  @override
  UserModel? get currentUser => UserModel(
      uid: 'OWNER', username: 'owner', name: '관리자',
      email: 'owner@test.local', role: UserRole.BUSINESS_ADMIN,
      managedBusinessIds: const ['BIZ']);
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

/// 근무일 = **오늘(KST)부터 7일 뒤의 KST 자정**. 오늘보다 미래여야 진행중이다.
///   [SIM-ADJ-3 fixture 정정 10-20] 예전에는 DEV 셀과 같은 2026-10-20 KST 로 고정해
///   그 날 08:00(지원 마감)이 지나자 카드가 진행중 탭에서 빠져 PR-0~2 가 실패했다
///   (시한부 fixture). 화면이 실제 시계를 쓰므로 날짜를 시계 기준으로 잡는다.
final _workDate = () {
  final kstNow = DateTime.now().toUtc().add(const Duration(hours: 9));
  return DateTime.utc(kstNow.year, kstNow.month, kstNow.day)
      .add(const Duration(days: 7))
      .subtract(const Duration(hours: 9))
      .toLocal();
}();

WorkDetailData _wd() => WorkDetailData(
      wdId: 'wd1', workType: 'QA 분류', startTime: '10:00', endTime: '11:00',
      requiredCount: 1, wage: 12000, wageType: 'hourly',
      applicationDeadline: _workDate.add(const Duration(hours: 8)),
    );

/// 서버 원장 — 확정이 커밋됐는지에 따라 공고·슬롯·통계가 함께 바뀐다.
class _Server {
  bool committed = false;
  int adminTOsReads = 0;
  int slotReads = 0;

  TOModel to() => TOModel(
        id: 'TO', businessId: 'BIZ', businessName: 'QA 사업장', type: 'flex',
        title: 'QA-SIM confirm', creatorUID: 'OWNER',
        status: committed ? TOStatus.full : TOStatus.active,
        workDetails: const [], totalRequired: 1,
        totalConfirmed: committed ? 1 : 0,
        totalPending: committed ? 0 : 1,
        isPublished: true, publishMode: 'immediate',
        rangeStart: _workDate, rangeEnd: _workDate,
        createdAt: DateTime.now().subtract(const Duration(days: 1)),
        statusUpdatedAt: DateTime.now().subtract(const Duration(days: 1)),
      );

  Object? _wire(Object? v) {
    if (v is Timestamp) {
      return {'_seconds': v.seconds, '_nanoseconds': v.nanoseconds};
    }
    if (v is DateTime) {
      final ms = v.millisecondsSinceEpoch;
      return {'_seconds': ms ~/ 1000, '_nanoseconds': (ms % 1000) * 1000000};
    }
    if (v is Map) return v.map((k, x) => MapEntry(k, _wire(x)));
    if (v is List) return v.map(_wire).toList();
    return v;
  }

  Future<ByteData?> handle(ByteData? message) async {
    final args = (const StandardMessageCodec().decodeMessage(message) as List)
        .first as Map;
    final name = args['functionName'] as String;
    if (name == 'callableGetAdminTOs') {
      adminTOsReads++;
      final m = Map<String, Object?>.from(_wire(to().toMap()) as Map)
        ..['id'] = 'TO';
      return const StandardMessageCodec().encodeMessage(<Object?>[
        <String, Object?>{'items': <Object?>[m]}
      ]);
    }
    return const StandardMessageCodec().encodeMessage(<Object?>[
      'not-found', 'unexpected $name', <String, Object?>{'code': 'not-found'}
    ]);
  }

  Future<FlexSlotLoadResult> slots(String toId, {TOModel? masterTO}) async {
    slotReads++;
    final model = masterTO ?? to();
    return (
      groupTOs: [
        TOItem(
          to: model,
          slot: SlotModel(
            id: 'S', toId: 'TO', date: _workDate,
            status: committed ? SlotStatus.full : SlotStatus.open,
            workDetails: [_wd()],
            createdAt: DateTime.now().subtract(const Duration(days: 1)),
          ),
          confirmedCount: committed ? 1 : 0,
          pendingCount: committed ? 0 : 1,
          totalRequired: 1,
        ),
      ],
      slotDates: [_workDate],
    );
  }

  Future<Map<String, dynamic>> capacity() async => {
        'workDetails': [_wd()],
        'workStats': {
          'wd1': {
            'confirmed': committed ? 1 : 0,
            'pending': committed ? 0 : 1,
          },
        },
        'statsFailed': false,
      };
}

typedef FlexSlotLoadResult = ({List<TOItem> groupTOs, List<DateTime> slotDates});

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

Future<WorkforceController> _pump(WidgetTester t, _Server server) async {
  t.view.physicalSize = const Size(411, 900);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  t.binding.defaultBinaryMessenger.setMockMessageHandler(_channel, server.handle);
  addTearDown(() =>
      t.binding.defaultBinaryMessenger.setMockMessageHandler(_channel, null));
  final controller = WorkforceController(
    loadSlots: server.slots,
    loadWorkDetailStats: (to, {slotId, slotWorkDetails}) => server.capacity(),
  );
  addTearDown(controller.dispose);
  await t.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider<UserProvider>(create: (_) => _AdminP()),
      ChangeNotifierProvider<WorkforceController>.value(value: controller),
    ],
    child: MaterialApp(
      navigatorKey: navigatorKey,
      home: const Scaffold(body: WorkforceListView()),
    ),
  ));
  // 공고 탭 root 가 하는 첫 로드와 같다.
  await controller.load(t.element(find.byType(WorkforceListView)));
  await _settle(t, 20);
  return controller;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
  });

  testWidgets('PR-0 출발점 — 진행중 탭 카드가 충원 0 · 대기 1', (t) async {
    final server = _Server();
    await _pump(t, server);
    final s = _texts(t);
    expect(s, contains('QA-SIM confirm'), reason: s);
    expect(s, contains('대기 1'), reason: s);
    expect(server.adminTOsReads, 1);
  });

  testWidgets('PR-1 카드가 화면보다 짧아도 당겨서 새로고침이 서버를 다시 읽는다',
      (t) async {
    final server = _Server();
    await _pump(t, server);
    expect(_texts(t), contains('대기 1'));
    final readsBefore = server.adminTOsReads;

    // 다른 화면에서 확정이 커밋됐다(DEV 셀과 같은 원장).
    server.committed = true;

    // 실제 제스처 — 목록을 아래로 끌어 놓는다.
    await t.fling(find.byType(ListView).first, const Offset(0, 400), 1200);
    await t.pump();
    await t.pump(const Duration(seconds: 1)); // 인디케이터 고정 → onRefresh
    await _settle(t, 40);

    expect(server.adminTOsReads, greaterThan(readsBefore),
        reason: '당겨서 새로고침이 공고 목록을 다시 읽어야 한다');
    final s = _texts(t);
    expect(s, isNot(contains('대기 1')),
        reason: '서버는 확정 1·대기 0 이다 — 낡은 카드가 남으면 안 된다: $s');
  });

  testWidgets('PR-2 새로고침 뒤 마감됨 탭에서 같은 공고가 충원 1 · 대기 0', (t) async {
    final server = _Server();
    await _pump(t, server);
    server.committed = true;
    await t.fling(find.byType(ListView).first, const Offset(0, 400), 1200);
    await t.pump();
    await t.pump(const Duration(seconds: 1));
    await _settle(t, 40);

    // 진행중이 비면 `…마감됨 탭에서…` 안내도 뜬다 — 탭 라벨 자체를 누른다.
    await t.tap(findVisibleText('마감됨'));
    await _settle(t, 20);
    final s = _texts(t);
    expect(s, contains('QA-SIM confirm'), reason: s);
    expect(s, contains('충원 1'), reason: s);
    expect(s, isNot(contains('대기 1')), reason: s);
  });
}
