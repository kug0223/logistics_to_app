// [POSTING-ENDED-STAFFING.27] 운영이 끝난 공고에서 `운영 종료` 가 인원 정보를 **대신하지** 않는다.
//
//   접힌 카드 · 펼친 업무 행 모두 상태(`운영 종료`)와 기록된 인원(`충원 c / 필요 r`)을 함께 말한다.
//   끝난 공고에 지금 할 일을 부르는 `부족`·`대기`·`미충원` 은 붙이지 않는다.
//   통계를 모르면 숫자 대신 `인원 확인 불가`(0 으로 말하지 않는다). 실제 위젯을 띄워 본다.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'package:ALfit/controllers/workforce_controller.dart';
import 'package:ALfit/models/core/slot_model.dart' show SlotModel, SlotStatus;
import 'package:ALfit/models/core/to_model.dart';
import 'package:ALfit/models/core/work_detail_data.dart';
import 'package:ALfit/models/ui/admin_to_list_ui_models.dart';
import 'package:ALfit/screens/business_admin/dialogs/to_list_dialogs.dart';
import 'package:ALfit/services/firestore_service.dart';
import 'package:ALfit/utils/posting_presentation_mode.dart';
import 'package:ALfit/widgets/admin/cards/admin_to_group_card.dart';
import 'package:ALfit/widgets/admin/cards/admin_work_detail.dart';

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

DateTime _day(int plus) {
  final n = DateTime.now();
  return DateTime(n.year, n.month, n.day).add(Duration(days: plus));
}

TOModel _to({int totalRequired = 3, int totalConfirmed = 1}) => TOModel(
      id: 'to1',
      businessId: 'biz1',
      businessName: '테스트 사업장',
      type: 'flex',
      title: '종료 공고',
      creatorUID: 'uid1',
      status: 'CLOSED',
      workDetails: const [],
      totalRequired: totalRequired,
      totalConfirmed: totalConfirmed,
      totalPending: 0,
      isPublished: true,
      publishMode: 'immediate',
      createdAt: _day(-30),
      statusUpdatedAt: _day(-30),
    );

WorkDetailData _wd(String id, {int required = 3}) => WorkDetailData(
      wdId: id,
      workType: '분류',
      startTime: '09:00',
      endTime: '18:00',
      requiredCount: required,
      wage: 10320,
      wageType: 'hourly',
      applicationDeadline: _day(-4),
      closedAt: _day(-4),
    );

TOItem _slot({int plusDays = -3, int required = 3, int confirmed = 1, int pending = 0}) => TOItem(
      to: _to(totalRequired: required, totalConfirmed: confirmed),
      slot: SlotModel(
        id: 's1',
        toId: 'to1',
        date: _day(plusDays),
        status: SlotStatus.closed,
        workDetails: [_wd('wd-s1', required: required)],
      ),
      confirmedCount: confirmed,
      pendingCount: pending,
      totalRequired: required,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
  });

  Future<String> collapsed(WidgetTester t, TOItem slot) async {
    t.view.physicalSize = const Size(1080, 2400);
    t.view.devicePixelRatio = 3.0;
    addTearDown(t.view.reset);
    final group = TOGroupItem(singleTO: _to(totalRequired: slot.totalRequired, totalConfirmed: slot.confirmedCount))
      ..setGroupTOs([slot])
      ..setSlotDates([slot.slot!.date]);
    final controller = WorkforceController(
        loadWorkDetailStats: (to, {slotId, slotWorkDetails}) async => {
              'workDetails': const <WorkDetailData>[],
              'workStats': const <String, dynamic>{},
              'statsFailed': false,
            });
    addTearDown(controller.dispose);
    final svc = FirestoreService();
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: Builder(
            builder: (ctx) => TOGroupCard(
              groupItem: group,
              firestoreService: svc,
              onRetryWorkDetailStats: controller.loadWorkDetails,
              onRetryGroupWorkDetailStats: controller.loadGroupWorkDetailStats,
              dialogs: TOListDialogs(context: ctx, firestoreService: svc, onChanged: () {}),
              onChanged: () {},
              isExpanded: false,
              expandedTOs: const <String>{},
              onToggleExpand: () {},
              onToggleTOExpand: (_) {},
            ),
          ),
        ),
      ),
    ));
    await t.pump();
    return [
      ...t.widgetList<RichText>(find.byType(RichText)).map((w) => w.text.toPlainText()),
    ].join(' | ');
  }

  Future<String> row(WidgetTester t, TOItem slot,
      {required PostingPresentationMode mode, bool statsFailed = false}) async {
    t.view.physicalSize = const Size(1080, 2400);
    t.view.devicePixelRatio = 3.0;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: WorkDetailRow(
          work: slot.slot!.workDetails.first,
          confirmedCount: slot.confirmedCount,
          pendingCount: slot.pendingCount,
          toItem: slot,
          firestoreService: FirestoreService(),
          onChanged: () {},
          statsFailed: statsFailed,
          mode: mode,
          onRetryStats: () {},
        ),
      ),
    ));
    await t.pump();
    return t.widgetList<RichText>(find.byType(RichText)).map((w) => w.text.toPlainText()).join(' | ');
  }

  testWidgets('PES-1 접힌 카드 — 운영 종료와 충원·필요를 함께, 부족·대기 없음', (t) async {
    final text = await collapsed(t, _slot(required: 3, confirmed: 1, pending: 2));
    expect(text, contains('운영 종료'));
    expect(text, contains('충원 1'));
    expect(text, contains('필요 3'));
    expect(text.contains('부족'), isFalse, reason: text);
    expect(text.contains('대기'), isFalse, reason: text);
  });

  testWidgets('PES-2 접힌 카드 — 충족된 종료 공고도 같은 단위로', (t) async {
    final text = await collapsed(t, _slot(required: 2, confirmed: 2));
    expect(text, contains('운영 종료'));
    expect(text, contains('충원 2'));
    expect(text, contains('필요 2'));
  });

  testWidgets('PES-3 펼친 업무 행 — 운영 종료 · 충원 c / 필요 r, 미충원 없음', (t) async {
    final text = await row(t, _slot(required: 3, confirmed: 1), mode: PostingPresentationMode.pastEnded);
    expect(text, contains('운영 종료  ·  충원 1 / 필요 3'));
    expect(text.contains('미충원'), isFalse, reason: text);
  });

  testWidgets('PES-4 펼친 업무 행 — 통계를 모르면 0 이 아니라 인원 확인 불가', (t) async {
    final text = await row(t, _slot(required: 3, confirmed: 0),
        mode: PostingPresentationMode.pastEnded, statsFailed: true);
    expect(text, contains('운영 종료  ·  인원 확인 불가'));
    expect(text.contains('충원 0'), isFalse, reason: text);
    expect(find.text('재시도'), findsOneWidget);
  });

  testWidgets('PES-5 운영 중 행은 그대로 — 충원·대기·미충원 (대조군)', (t) async {
    final text = await row(t, _slot(plusDays: 2, required: 3, confirmed: 1), mode: PostingPresentationMode.active);
    expect(text, contains('미충원'));
    expect(text.contains('운영 종료'), isFalse);
  });
}
