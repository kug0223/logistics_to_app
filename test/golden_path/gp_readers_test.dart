// ignore_for_file: depend_on_referenced_packages
// [CORE-GOLDEN-PATH-CONNECTED.1 · LOCAL] 같은 사건의 writer 출력 → 앱 reader.
//
//   노드 하네스가 배포 번들 실핸들러로 받은 **실제 응답(wire)** 을 run/reads-<tag>.json 에 남겼다.
//   여기서는 callable 채널을 그 기록으로 답하게 하고, 앱 화면·서비스·모델이 같은 건을 같은 금액·상태로
//   읽는지 본다. 기록에 없는 연결 필드를 손으로 넣지 않는다. GP_RUN 이 없으면 건너뛴다.
import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';

import 'package:ALfit/models/core/business_member_model.dart' show MemberPermissions;
import 'package:ALfit/models/core/notification_model.dart';
import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/providers/notification_provider.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/screens/business_admin/payroll/payroll_payment_dashboard_screen.dart';
import 'package:ALfit/services/firestore_service.dart';
import 'package:ALfit/utils/format_helper.dart';

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

class _AdminP extends UserProvider {
  @override
  UserModel? get currentUser => UserModel(
      uid: 'gp_admin', username: 'gp_admin', name: '합성 사업주', email: '', role: UserRole.BUSINESS_ADMIN);
  @override
  bool get isBusinessAdmin => true;
  @override
  bool get isSubAdmin => false;
  @override
  bool can(bool Function(MemberPermissions p) check) => true;
  @override
  bool canForBusiness(String businessId, bool Function(MemberPermissions p) check) => true;
  @override
  PermissionCheck checkForBusiness(String businessId, bool Function(MemberPermissions p) check) =>
      PermissionCheck.allowed;
}

const _ch = 'dev.flutter.pigeon.cloud_functions_platform_interface.CloudFunctionsHostApi.call';
final _run = Platform.environment['GP_RUN'];
Map<String, dynamic> _json(String f) => (jsonDecode(File('$_run/$f').readAsStringSync()) as Map).cast<String, dynamic>();

/// 기록된 응답으로 답하는 callable 채널. 무엇을 물었는지도 남긴다.
class _Replay {
  _Replay(this.reads);
  final Map<String, dynamic> reads;
  final asked = <String>[];
  Future<ByteData?> handle(ByteData? data) async {
    final args = (const StandardMessageCodec().decodeMessage(data) as List).first as Map;
    final fn = args['functionName'] as String;
    final p = Map<Object?, Object?>.from(args['parameters'] as Map? ?? const {});
    asked.add('$fn ${p['wageStatus'] ?? ''}');
    Map? rec;
    switch (fn) {
      case 'callableGetAdminAttendances':
        rec = reads['att-${p['wageStatus']}'] as Map?;
      case 'callableGetPayrollReadinessBatch':
        rec = reads['readiness'] as Map?;
      case 'callableGetUsersBatch':
        rec = reads['users'] as Map?;
      case 'getMyMonthlyAttendances':
        rec = reads['worker'] as Map?;
      default:
        return const StandardMessageCodec().encodeMessage(<Object?>[{'requests': <Object?>[], 'items': <Object?>[]}]);
    }
    if (rec == null || rec['ok'] != true) {
      return const StandardMessageCodec().encodeMessage(<Object?>['internal', 'replay: 기록 없음/실패', null]);
    }
    if (fn == 'callableGetAdminAttendances' && p['startMs'] is int && p['endMs'] is int) {
      // 서버와 같은 기준(workDate ∈ [startMs, endMs))으로만 거른다 — 전체 미이체 화면은 기간을 여러 구간으로 나눠 묻는다.
      //   (첫 재생은 구간과 무관하게 같은 응답을 돌려줘 같은 근태가 구간 수만큼 겹쳤다 — 하네스 결함)
      final w = Map<String, dynamic>.from(rec['wire'] as Map);
      w['items'] = (w['items'] as List).where((e) {
        final s = (((e as Map)['workDate'] as Map)['_seconds'] as num).toInt() * 1000;
        return s >= (p['startMs'] as int) && s < (p['endMs'] as int);
      }).toList();
      return const StandardMessageCodec().encodeMessage(<Object?>[w]);
    }
    return const StandardMessageCodec().encodeMessage(<Object?>[rec['wire']]);
  }
}

Future<_Replay> _mountAdmin(WidgetTester t, String tag) async {
  final r = _Replay(_json('reads-$tag.json'));
  t.view.physicalSize = const Size(1080, 4000);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  t.binding.defaultBinaryMessenger.setMockMessageHandler(_ch, r.handle);
  addTearDown(() => t.binding.defaultBinaryMessenger.setMockMessageHandler(_ch, null));
  final st = _json('state.json');
  final k = DateTime.fromMillisecondsSinceEpoch((st['dayKst'] as num).toInt(), isUtc: true).add(const Duration(hours: 9));
  await t.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider<UserProvider>(create: (_) => _AdminP()),
      ChangeNotifierProvider<NotificationProvider>(create: (_) => NotificationProvider()),
    ],
    child: MaterialApp(
      home: PayrollPaymentDashboardScreen(
          businessId: 'biz_gp', businessName: '[합성] GP 사업장', year: k.year, month: k.month, showAllOutstanding: true),
    ),
  ));
  for (var i = 0; i < 60; i++) {
    await t.pump(const Duration(milliseconds: 50));
  }
  return r;
}

int _net(Map att) => ((att['wageDetail'] as Map?)?['netWage'] as num?)?.toInt() ?? -1;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
  });
  bool has(String f) => _run != null && File('$_run/$f').existsSync();

  testWidgets('GP-R1 이체 전 — 관리자 전체 미이체 화면이 그 근태를 그 금액·이름으로, 이체 입구와 함께 보인다', (t) async {
    final reads = _json('reads-before.json');
    final items = ((reads['att-confirmed'] as Map)['wire'] as Map)['items'] as List;
    final att = items.cast<Map>().single;
    final net = _net(att);
    final r = await _mountAdmin(t, 'before');
    final texts = find.byType(Text).evaluate().map((e) => (e.widget as Text).data ?? '').where((s) => s.isNotEmpty).toList();
    // ignore: avoid_print
    print('   GP-R1 asked=${r.asked.toSet()} net=$net texts=${texts.take(30).toList()}');
    expect(find.text('합성 근로자'), findsOneWidget);
    expect(find.text(FormatHelper.formatWage(net)), findsWidgets);
    expect(find.text('이체처리'), findsOneWidget);
    expect(find.text('지급 준비 상태 조회 실패'), findsNothing);
  }, skip: !has('reads-before.json'));

  test('GP-R2 이체 전 — 근로자 수입 reader 가 같은 근태·같은 금액·확정 상태를 읽는다', () async {
    final reads = _json('reads-before.json');
    final att = (((reads['att-confirmed'] as Map)['wire'] as Map)['items'] as List).cast<Map>().single;
    final r = _Replay(reads);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMessageHandler(_ch, r.handle);
    final st = _json('state.json');
    final k = DateTime.fromMillisecondsSinceEpoch((st['dayKst'] as num).toInt(), isUtc: true).add(const Duration(hours: 9));
    final list = await FirestoreService().getMyMonthlyAttendances(userId: 'gp_w1', year: k.year, month: k.month);
    expect(list.length, 1);
    final w = list.single;
    // ignore: avoid_print
    print('   GP-R2 worker id=${w.id} wageStatus=${w.wageStatus} net=${w.wageDetail?.effectiveNetWage} admin net=${_net(att)} due=${w.paymentDueDate}');
    expect(w.id, att['id']);
    expect(w.id, st['attendanceId']);
    expect(w.wageStatus, 'confirmed');
    expect(w.wageDetail?.effectiveNetWage, _net(att));
  }, skip: !has('reads-before.json'));

  testWidgets('GP-R3 이체 후 — 관리자 전체 미이체에서 빠지고, 근로자는 이체 완료로 읽는다', (t) async {
    final r = await _mountAdmin(t, 'after');
    expect(find.text('미이체 급여가 없습니다'), findsOneWidget);
    expect(find.text('이체처리'), findsNothing);
    final reads = _json('reads-after.json');
    final tr = (((reads['att-transferred'] as Map)['wire'] as Map)['items'] as List).cast<Map>();
    expect(tr.single['id'], _json('state.json')['attendanceId']);
    final worker = ((reads['worker'] as Map)['wire'] as Map)['items'] as List;
    expect((worker.cast<Map>().single)['wageStatus'], 'transferred');
    // ignore: avoid_print
    print('   GP-R3 asked=${r.asked.toSet()}');
  }, skip: !has('reads-after.json'));

  test('GP-R4 알림 — 앱 NotificationModel 이 이체 알림을 그 근로자·사업장·지원서로 읽는다', () {
    final n = _json('notifications.json');
    final st = _json('state.json');
    final mine = (n['gp_w1'] as List).cast<Map>().map((m) {
      final mm = Map<String, dynamic>.from(m);
      final id = mm.remove('id') as String;
      return NotificationModel.fromMap(_restoreTs(mm), id);
    }).toList();
    final xfer = mine.where((x) => x.type == NotificationType.wageTransferred).toList();
    // ignore: avoid_print
    print('   GP-R4 types=${mine.map((x) => x.type.name).toList()} body=${xfer.map((x) => x.body).toList()} data=${xfer.map((x) => x.data).toList()}');
    expect(xfer.length, 1, reason: '같은 건 재요청 뒤에도 이체 알림은 1건');
    expect(xfer.single.userId, 'gp_w1');
    expect(xfer.single.data?['businessId'], 'biz_gp');
    expect(xfer.single.data?['applicationId'], st['applicationId']);
    expect(mine.where((x) => x.type == NotificationType.wageTransferred).every((x) => x.createdAtKnown), isTrue);
    expect((n['gp_admin'] as List).cast<Map>().where((m) => m['type'] == 'wageTransferred'), isEmpty);
  }, skip: !has('notifications.json'));
}

Map<String, dynamic> _restoreTs(Map<String, dynamic> m) => m.map((k, v) {
      if (v is Map && v.length == 1 && v.containsKey('__ts')) {
        return MapEntry(k, Timestamp.fromMillisecondsSinceEpoch((v['__ts'] as num).toInt()));
      }
      return MapEntry(k, v);
    });
