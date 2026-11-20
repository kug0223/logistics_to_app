// ignore_for_file: depend_on_referenced_packages
// [DU1 candB · 미리보기 금액 동치] 실제 WageConfirmDialog 가 후보 B 응답(wire → production _cfHydrate)으로 만든 입력에서
//   보여 주는 금액 == 서버 production 계산부(srvWageCalculate + srvApplyDeduction, handler 미호출·무쓰기)의 결과.
//   서버 쪽 값: test/fixtures/du1_candb_server_preview.json (D:\AlFit-evidence\DU1\candB\run.js 출력).
//   급여창은 확정 버튼을 누르지 않는다 — CF 쓰기·DEV 호출 없음(가짜 플랫폼). UI 연결(SubAdmin 진입)은 여전히 미연결.
import 'dart:convert';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';

import 'package:ALfit/models/core/application_model.dart';
import 'package:ALfit/models/core/attendance_model.dart';
import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/screens/business_admin/dialogs/wage_confirm_dialog.dart';
import 'package:ALfit/services/firestore_service.dart';
import 'package:ALfit/utils/format_helper.dart';

import 'support/visible_text.dart';

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
  UserModel? get currentUser => UserModel(
      uid: 'owner1', username: 'owner1', name: '사장', email: 'o@t.local', role: UserRole.BUSINESS_ADMIN,
      businessId: 'b1', createdAt: DateTime(2026, 1, 1));
}

Map<String, dynamic> _json(String p) => Map<String, dynamic>.from(jsonDecode(File(p).readAsStringSync()) as Map);

void main() {
  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
  });

  final wire = cfHydrateForTest(_json('test/fixtures/du1_candb_wire.json'));
  final server = _json('test/fixtures/du1_candb_server_preview.json');
  final items = (wire['items'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();

  for (final id in const ['manual', 'auto', 'legacy']) {
    testWidgets('PV-$id 급여창 미리보기 금액 == 서버 계산부', (t) async {
      final it = items.firstWhere((e) => e['applicationId'] == id);
      final pa = Map<String, dynamic>.from(it['wageApplication'] as Map)..remove('applicationId');
      final app = ApplicationModel.tryFromMap(pa, id)!;
      final am = Map<String, dynamic>.from(it)..remove('wageApplication')..remove('wageWorkDetail');
      final attId = am.remove('id') as String;
      am['status'] = AttendanceModel.displayStatusOfRaw(am['status']);
      final att = AttendanceModel.tryFromMap(am, attId)!;
      final wd = Map<String, dynamic>.from(it['wageWorkDetail'] as Map);
      final timeMap = <String, dynamic>{'${wd['workType']}_${wd['startTime']}_${wd['endTime']}': wd};

      t.view.physicalSize = const Size(430, 1600);
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.reset);
      await t.pumpWidget(ChangeNotifierProvider<UserProvider>(
        create: (_) => _Owner(),
        child: MaterialApp(
          home: Scaffold(
            body: WageConfirmDialog(
              date: FormatHelper.toKstDate(att.workDate), businessId: 'b1', businessName: 'B',
              workers: [app], attendanceMap: {app.id: att},
              userMap: {app.uid: UserModel(uid: app.uid, username: app.uid, name: '근로자$id', email: 'w@t.local', role: UserRole.USER)},
              workDetailTimeMap: timeMap,
            ),
          ),
        ),
      ));
      for (var i = 0; i < 30; i++) {
        await t.pump(const Duration(milliseconds: 50));
      }
      final s = Map<String, dynamic>.from(server[id] as Map);
      final total = (s['totalAmount'] as num).toInt();
      final net = (s['netWage'] as num).toInt();
      final shown = t.widgetList<RichText>(find.byType(RichText)).map((w) => visibleText(w.text.toPlainText())).where((x) => x.contains('원')).toList();
      // ignore: avoid_print
      print('PV-$id server total=$total net=$net shown=$shown');
      final shownNums = shown.expand((x) => RegExp(r'[0-9][0-9,]*').allMatches(x).map((m) => int.tryParse(m.group(0)!.replaceAll(',', '')) ?? -1)).toSet();
      expect(shownNums.contains(net), isTrue,
          reason: '급여창 미리보기 실수령 == 서버 계산 netWage $net (total $total) — 보이는 금액 $shown');
      await t.pumpWidget(const SizedBox.shrink());
    });
  }
}
