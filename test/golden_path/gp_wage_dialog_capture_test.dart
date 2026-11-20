// ignore_for_file: depend_on_referenced_packages
// [CONTRACT-HANDOFF.5 · B2] 앱 급여 확정 다이얼로그가 **실제로** 어떤 급여 계산 요청을 보내는가.
//
//   입력은 LOCAL 배포 핸들러 사슬(자동 노쇼 → 노쇼 취소 → 일괄 출근(A만) → 일괄 퇴근)이 남긴 근태·지원서·슬롯
//   문서다(GP_RUN/wage/). 다음 단계 필드를 손으로 채우지 않는다 — 다이얼로그가 스스로 계산·선택하고,
//   '전체 일괄 확정' 을 누른 뒤 나가는 callable 요청을 채널에서 기록한다(wage-calls.json).
//   서버 호출은 노드가 배포 핸들러로 다시 보낸다(srv5.js b2b). GP_RUN 이 없으면 건너뛴다.
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
import 'package:intl/date_symbol_data_local.dart';

import 'package:ALfit/models/core/application_model.dart';
import 'package:ALfit/models/core/attendance_model.dart';
import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/screens/business_admin/dialogs/wage_confirm_dialog.dart';

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

class _Owner extends UserProvider {
  @override
  UserModel? get currentUser => UserModel(uid: 'u5_owner', username: 'u5_owner', name: '합성 대표', email: '', role: UserRole.BUSINESS_ADMIN);
  @override
  bool get isBusinessAdmin => true;
  @override
  bool get isSubAdmin => false;
  @override
  bool get isSuperAdmin => false;
  @override
  bool get permissionsLoaded => true;
}

const _ch = 'dev.flutter.pigeon.cloud_functions_platform_interface.CloudFunctionsHostApi.call';
final _run = Platform.environment['GP_RUN'];
Object? _restore(Object? v) => v is Map
    ? (v.length == 1 && v.containsKey('__ts')
        ? Timestamp.fromMillisecondsSinceEpoch((v['__ts'] as num).toInt())
        : v.map((k, x) => MapEntry(k as String, _restore(x))))
    : v is List
        ? v.map(_restore).toList()
        : v;
Map<String, dynamic> _doc(String n) =>
    (_restore(jsonDecode(File('$_run/wage/$n.json').readAsStringSync())) as Map).cast<String, dynamic>();
Object? _wire(Object? v) => v is Map ? v.map((k, x) => MapEntry('$k', _wire(x))) : v is List ? v.map(_wire).toList() : v;

void main() {
  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
    await initializeDateFormatting('ko_KR', null);
  });
  final ok = _run != null && File('$_run/wage/attendance_B.json').existsSync();

  testWidgets('B2 급여 다이얼로그 — 출근 없는 근태(B)·정상 근태(A)', (t) async {
    final calls = <Map<String, dynamic>>[];
    t.binding.defaultBinaryMessenger.setMockMessageHandler(_ch, (data) async {
      final args = (const StandardMessageCodec().decodeMessage(data) as List).first as Map;
      final fn = '${args['functionName']}';
      final p = args['parameters'];
      calls.add({'fn': fn, 'data': _wire(p)});
      // 노드가 배포 핸들러로 다시 보낸다 — 여기서는 "응답 없음"으로 답해 다이얼로그가 결과를 지어내지 않게 한다.
      return const StandardMessageCodec().encodeMessage(<Object?>['unavailable', 'captured-only', null]);
    });
    addTearDown(() => t.binding.defaultBinaryMessenger.setMockMessageHandler(_ch, null));
    t.view.physicalSize = const Size(420, 2400);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    final apps = <ApplicationModel>[];
    final atts = <String, AttendanceModel>{};
    final users = <String, UserModel>{};
    for (final k in ['A', 'B']) {
      final a = _doc('application_$k');
      final app = ApplicationModel.fromMap(a, a['id'] as String);
      apps.add(app);
      final at = _doc('attendance_$k');
      atts[app.id] = AttendanceModel.fromMap(at, at['id'] as String);
      users[app.uid] = UserModel(uid: app.uid, username: app.uid, name: '합성 $k', email: '', role: UserRole.USER);
    }
    final slot = _doc('slot');
    final wd = (slot['workDetails'] as List).first as Map;
    final timeMap = <String, dynamic>{
      '${wd['workType']}_${wd['startTime']}_${wd['endTime']}': {
        'breakMinutes': wd['breakMinutes'] ?? 0, 'wage': wd['wage'], 'wageType': wd['wageType'], 'requiredCount': wd['requiredCount'], 'payScheduleType': wd['payScheduleType'],
      },
    };
    await t.pumpWidget(ChangeNotifierProvider<UserProvider>(
      create: (_) => _Owner(),
      child: MaterialApp(home: Scaffold(body: WageConfirmDialog(
        date: atts.values.first.workDate, businessId: apps.first.businessId, businessName: '[합성] biz5',
        workers: apps, attendanceMap: atts, userMap: users, workDetailTimeMap: timeMap))),
    ));
    for (var i = 0; i < 40; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    final texts = t.widgetList<Text>(find.byType(Text)).map((w) => w.data ?? '').where((s) => s.isNotEmpty).toList();
    final allBtn = find.textContaining('전체 일괄 확정');
    final pendingLabel = texts.where((s) => s.contains('전체 일괄 확정')).toList();
    if (allBtn.evaluate().isNotEmpty) {
      await t.tap(allBtn.first);
      for (var i = 0; i < 10; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
      final confirm = find.text('확정');
      if (confirm.evaluate().isNotEmpty) await t.tap(confirm.last);
      for (var i = 0; i < 40; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
    }
    final wageCalls = calls.where((c) => c['fn'] == 'callableCalculateAndConfirmWage').toList();
    File('$_run/wage/wage-calls.json').writeAsStringSync(const JsonEncoder.withIndent(' ').convert(wageCalls));
    File('$_run/wage/wage-dialog.json').writeAsStringSync(const JsonEncoder.withIndent(' ').convert({
      'pendingButton': pendingLabel,
      'allCalls': calls.map((c) => c['fn']).toList(),
      'calcFor': wageCalls.map((c) => (c['data'] as Map)['attendanceId']).toList(),
      'textsMentioningB': texts.where((s) => s.contains('합성 B')).toList(),
    }));
    // ignore: avoid_print
    print('   wage dialog: pending=$pendingLabel calcFor=${wageCalls.map((c) => (c['data'] as Map)['attendanceId']).toList()}');
  }, skip: !ok);
}
