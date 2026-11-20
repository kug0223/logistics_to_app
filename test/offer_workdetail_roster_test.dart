// [CLOSEOUT.2 · D2] 다른 업무 제안 수락 지원서가 새 업무(B)의 명단·계약 대상에 정확히 한 번 나오는가.
//
//   입력은 LOCAL 에뮬레이터에서 **DEV 라이브 lib** 로 만든 문서다(test/fixtures/offer_wd_for_app.json):
//   A 직접 지원(Apply 00104) → 관리자 B 제안(Offer 00015) → 근로자 수락(Accept 00061).
//   제안 writer 는 workDetailId 에 **슬롯 wdId 값**을 쓴다(composite 아님). 같은 업무명 A/B, 슬롯·마스터 wdId 는 무작위.
//   비교 대상: 같은 B 의 초대 수락 지원서(workDetailId 없음).
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
import 'package:ALfit/services/firestore_service.dart';
import 'package:ALfit/utils/work_detail_helper.dart';

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
  UserModel? get currentUser => UserModel(uid: 'owner1', username: 'owner1', name: '합성 관리자', email: 'o@alfit.local',
      role: UserRole.BUSINESS_ADMIN, businessId: 'biz_e7', createdAt: DateTime(2026, 1, 1));
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
  PermissionCheck checkForBusiness(String businessId, bool Function(MemberPermissions p) check) => PermissionCheck.allowed;
}

Object? _restore(Object? v) => v is Map
    ? (v.length == 1 && v.containsKey('__ts')
        ? Timestamp.fromMillisecondsSinceEpoch((v['__ts'] as num).toInt())
        : v.map((k, x) => MapEntry(k as String, _restore(x))))
    : v is List
        ? v.map(_restore).toList()
        : v;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final j = (_restore(jsonDecode(File('test/fixtures/offer_wd_for_app.json').readAsStringSync())) as Map).cast<String, dynamic>();
  final offer = ApplicationModel.fromMap((j['app'] as Map).cast<String, dynamic>(), 'OFFER_APP');
  final inv = ApplicationModel.fromMap((j['invApp'] as Map).cast<String, dynamic>(), 'INV_APP');
  List<WorkDetailData> wds(String k) =>
      (j[k] as List).map((m) => WorkDetailData.fromMap((m as Map).cast<String, dynamic>())).toList();
  final master = wds('masterWorkDetails');
  final slotWds = wds('slotWorkDetails');
  final slotB = (j['slotWd'] as Map)['B'] as String;
  final b = slotWds.firstWhere((w) => w.wdId == slotB);

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

  test('전제: 제안 writer 출력 — workDetailId = 슬롯 B wdId(composite 아님), 시간 B, CONFIRMED', () {
    expect(offer.status, AppStatus.confirmed);
    expect(offer.wdId, slotB);
    expect(offer.workDetailId, slotB);
    expect(offer.workDetailId, isNot(b.id));
    expect((offer.startTime, offer.endTime), (b.startTime, b.endTime));
    expect(inv.workDetailId, isNull);
    expect(slotWds.where((w) => w.workType == b.workType).length, 2, reason: '같은 업무명 두 시간대');
  });

  test('계약 대상: 제안 수락 지원서 → B 정의(마스터 공고 workDetails 기준)', () {
    final t = WorkDetailHelper.contractWorkDetailFor(offer, master);
    expect(t, isNotNull);
    expect((t!.startTime, t.endTime, t.breakMinutes, t.payScheduleType), (b.startTime, b.endTime, b.breakMinutes, b.payScheduleType));
  });

  Future<(int, int)> pumpFor(WidgetTester t, WorkDetailData work) async {
    final to = TOModel(id: 'to_wd2', businessId: 'biz_e7', businessName: '[합성] E7 사업장', type: 'flex', title: '[합성] 같은 업무명 두 시간대',
        creatorUID: 'owner1', status: 'ACTIVE', workDetails: master, totalRequired: 10, totalConfirmed: 2, totalPending: 0,
        isPublished: true, publishMode: 'immediate', createdAt: DateTime.now().subtract(const Duration(days: 1)),
        statusUpdatedAt: DateTime.now().subtract(const Duration(days: 1)));
    final item = TOItem(to: to,
        slot: SlotModel(id: 's1', toId: 'to_wd2', date: offer.workDate, status: SlotStatus.open, workDetails: slotWds,
            createdAt: DateTime.now().subtract(const Duration(days: 1))),
        confirmedCount: 2, pendingCount: 0, totalRequired: 10);
    WorkApplicantsReads.debugOverride = WorkApplicantsReads(
      applications: (to, {slotId, required purpose}) async => [inv, offer],
      usersBatch: (uids, {required businessId, purpose}) async => {
        for (final u in uids)
          u: UserModel(uid: u, username: u, name: u == 'U_OFFER' ? '합성 제안' : '합성 초대1', email: '$u@test.local', role: UserRole.USER),
      },
      weeklyAttendance: ({required businessId, required weekStart, required weekEnd}) async => <String, List<AttendanceModel>>{},
      contractStatusBatch: (ids, {required businessId}) async => const ContractStatusBatch(),
      hasWorkedMap: ({required businessId, required date}) async => const {},
      idCardStatusBatch: ({required requesterId, required targetUserIds}) async => const {},
      capacity: (to, {slotId, slotWorkDetails}) async => {
        'workDetails': slotWds,
        'workStats': {for (final w in slotWds) w.wdId!: {'confirmed': w.wdId == slotB ? 2 : 0, 'pending': 0}},
        'statsFailed': false,
      },
      reassignProposals: (bizId) async => const [],
      contractAttendances: ({required businessId, required first, required last}) async => const <AttendanceModel>[],
    );
    t.view.physicalSize = const Size(411, 3200);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    await t.pumpWidget(ChangeNotifierProvider<UserProvider>(
      create: (_) => _Owner(),
      child: MaterialApp(home: Scaffold(body: WorkApplicantsDialog(key: UniqueKey(), toItem: item, work: work, onChanged: () {}))),
    ));
    for (var i = 0; i < 40; i++) {
      await t.pump(const Duration(milliseconds: 50));
    }
    return (find.textContaining('합성 초대1').evaluate().length, find.textContaining('합성 제안').evaluate().length);
  }

  testWidgets('명단: B 업무별 지원자 창 — 초대 수락과 제안 수락이 각각 한 번씩 보인다', (t) async {
    final (invN, offN) = await pumpFor(t, b);
    debugPrint('[D2] B 명단 표시 — 초대 수락 $invN회 · 제안 수락 $offN회');
    expect(invN, 1, reason: '대조: 초대 수락(workDetailId 없음)은 B 명단에 한 번');
    expect(offN, 1, reason: '제안 수락(workDetailId = 슬롯 wdId)도 B 명단에 한 번');
  });

  testWidgets('대조: 같은 업무명 A 창에는 둘 다 나오지 않는다(창이 업무로 거른다)', (t) async {
    final a = slotWds.firstWhere((w) => w.wdId != slotB);
    final (invN, offN) = await pumpFor(t, a);
    debugPrint('[D2] A 명단 표시 — 초대 수락 $invN회 · 제안 수락 $offN회');
    expect((invN, offN), (0, 0));
  });
}
