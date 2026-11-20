// [ADMIN-DOC-REVIEW-UX] 모집이 마감된 공고 카드는 `부족`을 말하지 않는다.
//
//   `부족`은 "지금 처리 가능한 미완료"다(카드 §14 · 날짜 창 `_GroupData.shortage`
//   의 같은 정의). 날짜 창은 마감 공고를 `0명 부족`이라 하는데 카드는 같은
//   공고를 `부족 3` 이라 했다(기기 관찰, 10-15 20:13 KST). 사실인 `충원 / 필요`
//   는 그대로 말한다. 실제 TOGroupCard 를 띄워 본다.
import 'support/visible_text.dart';
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
import 'package:ALfit/models/ui/group_header_totals.dart';
import 'package:ALfit/models/ui/invite_capacity_state.dart';
import 'package:ALfit/utils/close_state_utils.dart';
import 'package:ALfit/screens/business_admin/dialogs/to_list_dialogs.dart';
import 'package:ALfit/services/firestore_service.dart';
import 'package:ALfit/widgets/admin/cards/admin_to_group_card.dart';

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

DateTime _day(int plus) {
  final n = DateTime.now();
  return DateTime(n.year, n.month, n.day).add(Duration(days: plus));
}

TOModel _to({int totalRequired = 3}) => TOModel(
      id: 'to1',
      businessId: 'biz1',
      businessName: '테스트 사업장',
      type: 'flex',
      title: '테스트 공고',
      creatorUID: 'uid1',
      status: 'ACTIVE',
      workDetails: const [],
      totalRequired: totalRequired,
      totalConfirmed: 0,
      totalPending: 0,
      isPublished: true,
      publishMode: 'immediate',
      createdAt: _day(-30),
      statusUpdatedAt: _day(-30),
    );

/// [closed] 면 지원 마감 시각이 지났고 **스케줄러가 저장까지 했다**(업무 closedAt ·
///   슬롯 status closed) — B(10-15 20:00 근무, 20:00:07 저장)와 같은 조건.
/// [deadlinePassed] 만 참이면 마감 시각은 지났지만 아직 저장 전(최대 59분 창).
TOItem _slot(
        {required bool closed,
        bool? deadlinePassed,
        String id = 's1',
        int plusDays = 1,
        int required = 3,
        int confirmed = 0}) =>
    TOItem(
      to: _to(totalRequired: required),
      slot: SlotModel(
        id: id,
        toId: 'to1',
        date: _day(plusDays),
        status: closed ? SlotStatus.closed : SlotStatus.open,
        workDetails: [
          WorkDetailData(
            wdId: 'wd-$id',
            workType: 'QA 분류',
            startTime: '20:00',
            endTime: '22:00',
            requiredCount: required,
            wage: 13000,
            wageType: 'hourly',
            applicationDeadline: (deadlinePassed ?? closed)
                ? DateTime.now().subtract(const Duration(minutes: 1))
                : DateTime.now().add(const Duration(minutes: 1)),
            closedAt: closed ? DateTime.now() : null,
          ),
        ],
      ),
      confirmedCount: confirmed,
      pendingCount: 0,
      totalRequired: required,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
  });

  Future<String> renderSlots(WidgetTester t, List<TOItem> slots,
      {DateTime? selectedDate}) async {
    t.view.physicalSize = const Size(1080, 2400);
    t.view.devicePixelRatio = 3.0;
    addTearDown(t.view.reset);
    final totalReq = slots.fold<int>(0, (a, s) => a + s.totalRequired);
    final group = TOGroupItem(singleTO: _to(totalRequired: totalReq))
      ..setGroupTOs(slots)
      ..setSlotDates([for (final s in slots) s.slot!.date]);
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
              dialogs: TOListDialogs(
                  context: ctx, firestoreService: svc, onChanged: () {}),
              onChanged: () {},
              isExpanded: false,
              expandedTOs: const <String>{},
              onToggleExpand: () {},
              onToggleTOExpand: (_) {},
              selectedDate: selectedDate,
            ),
          ),
        ),
      ),
    ));
    await t.pump();
    return t
        .widgetList<RichText>(find.byType(RichText))
        .map((w) => visibleText(w.text.toPlainText()))
        .join(' | ');
  }

  Future<String> render(WidgetTester t, {required bool closed}) =>
      renderSlots(t, [_slot(closed: closed)]);

  testWidgets('PCS-01 모집 중 — `부족 3` 을 말한다(대조군)', (t) async {
    final text = await render(t, closed: false);
    expect(text, contains('충원 0'));
    expect(text, contains('필요 3'));
    expect(text, contains('부족 3'));
  });

  testWidgets('PCS-02 모집 마감 — 사실(충원·필요)은 말하고 `부족`은 말하지 않는다',
      (t) async {
    final text = await render(t, closed: true);
    expect(text, contains('마감'), reason: '대조: 카드가 마감으로 그려졌다');
    expect(text, contains('충원 0'));
    expect(text, contains('필요 3'));
    expect(text.contains('부족'), isFalse, reason: text);
  });

  // ── [ADMIN-APPROVAL-MIXED-SLOTS] 열린 슬롯 + 마감 슬롯 ───────────────────
  //   마감 슬롯 A: 0/3 (지원 마감 지남) · 열린 슬롯 B: 0/2
  //   날짜 창은 날짜별로 A=0, B=2 → 합 2. 카드 요약도 2 여야 한다.
  List<TOItem> mixed() => [
        _slot(closed: true, id: 'sA', plusDays: 1, required: 3),
        _slot(closed: false, id: 'sB', plusDays: 2, required: 2),
      ];

  testWidgets('PCS-03 혼합 — 날짜 미선택 요약은 열린 슬롯의 부족만 더한다', (t) async {
    final text = await renderSlots(t, mixed());
    expect(text, contains('충원 0'));
    expect(text, contains('필요 5'), reason: '필요는 사실 — 마감 슬롯도 더한다');
    expect(text, contains('부족 2'), reason: text);
    expect(text.contains('부족 5'), isFalse);
  });

  testWidgets('PCS-04 혼합 — 마감 날짜를 고르면 `부족`이 없다', (t) async {
    final m = mixed();
    final text = await renderSlots(t, m, selectedDate: m[0].slot!.date);
    expect(text, contains('필요 3'));
    expect(text.contains('부족'), isFalse, reason: text);
  });

  testWidgets('PCS-05 혼합 — 열린 날짜를 고르면 그 날의 부족만', (t) async {
    final m = mixed();
    final text = await renderSlots(t, m, selectedDate: m[1].slot!.date);
    expect(text, contains('필요 2'));
    expect(text, contains('부족 2'));
  });

  test('PCS-06 합계 대조 — 카드 요약 = 날짜 창 식(staffingShortageOf)의 날짜별 합',
      () {
    final m = mixed();
    final card = projectGroupHeaderTotals(
      targetTOs: m,
      singleFallback: () => m.first,
      openShortageOf: (t) => t.persistedOpenShortage(master: _to()),
    );
    var dialogSum = 0;
    for (final t in m) {
      // 날짜 창의 isClosed = 서버 callableGetDayStaffingDetail 의 저장 상태 판정.
      final closed = t.slot!.isClosed ||
          t.slot!.workDetails.every((w) => w.isClosed);
      dialogSum += staffingShortageOf(
            capacity: inviteCapacityStateOf(
              canonicalConfirmed: t.confirmedCount,
              requiredCount: t.totalRequired,
              isClosed: closed,
            ),
            requiredCount: t.totalRequired,
            seatedConfirmed: t.confirmedCount,
          ) ??
          0;
    }
    expect(card.shortage, 2);
    expect(dialogSum, 2);
    expect(card.shortage, dialogSum);
    // 판정을 넘기지 않으면(옛 동작) 마감 슬롯까지 더해 5 가 된다.
    expect(
        projectGroupHeaderTotals(targetTOs: m, singleFallback: () => m.first)
            .shortage,
        5);
  });

  // ── [CLOSESTATE-BOUNDARY] 정각 전후 — 지원 마감 20:00, 스케줄러는 매시 정각 ──
  //   19:59 (마감 1분 전)           : 카드 부족 3 · 날짜 창 부족 3 · 서버 초대 가능
  //   20:01 (지남, 아직 저장 전)    : 카드 부족 3 · 날짜 창 부족 3 · 서버 초대 가능
  //   20:00:07 이후 (closedAt 저장) : 카드 부족 없음 · 날짜 창 0 · 서버 초대 거절
  //   예전 카드(기기 시계 판정)는 20:01 에 부족을 지워 날짜 창과 갈라졌다.
  int dialogShortage(TOItem t) {
    final closed =
        t.slot!.isClosed || t.slot!.workDetails.every((w) => w.isClosed);
    return staffingShortageOf(
          capacity: inviteCapacityStateOf(
              canonicalConfirmed: t.confirmedCount,
              requiredCount: t.totalRequired,
              isClosed: closed),
          requiredCount: t.totalRequired,
          seatedConfirmed: t.confirmedCount,
        ) ??
        0;
  }

  for (final c in [
    ('19:59 마감 전', _slot(closed: false, deadlinePassed: false), 3),
    ('20:01 지남·저장 전', _slot(closed: false, deadlinePassed: true), 3),
    ('저장 후', _slot(closed: true), 0),
  ]) {
    test('PCS-07 정각 전후 ${c.$1} — 카드 부족 = 날짜 창 부족 = ${c.$3}', () {
      final card = projectGroupHeaderTotals(
        targetTOs: [c.$2],
        singleFallback: () => c.$2,
        openShortageOf: (t) => t.persistedOpenShortage(master: _to()),
      );
      expect(card.shortage, c.$3);
      expect(dialogShortage(c.$2), c.$3);
    });
  }

  testWidgets('PCS-08 20:01 창 — 부족은 초대 기준(저장 상태)이라 아직 3', (t) async {
    // 배지·탭 분류는 지원 접수(callableApplyToTO 의 실시간 마감)와 같은 식이고,
    //   부족은 초대·날짜 창의 저장 상태다. 둘이 다른 질문에 답한다는 것을 고정한다.
    final text =
        await renderSlots(t, [_slot(closed: false, deadlinePassed: true)]);
    expect(text, contains('부족 3'), reason: text);
  });

  test('PCS-09 업무 단위 — 같은 슬롯에서 닫힌 업무의 부족만 뺀다', () {
    final sl = SlotModel(
      id: 'sM',
      toId: 'to1',
      date: _day(1),
      workDetails: [
        WorkDetailData(
            wdId: 'w-open', workType: '분류', startTime: '09:00',
            endTime: '18:00', requiredCount: 2, wage: 1, wageType: 'hourly'),
        WorkDetailData(
            wdId: 'w-closed', workType: '포장', startTime: '09:00',
            endTime: '18:00', requiredCount: 3, wage: 1, wageType: 'hourly',
            closedAt: DateTime.now()),
      ],
    );
    final item = TOItem(
      to: _to(totalRequired: 5),
      slot: sl,
      confirmedCount: 0,
      pendingCount: 0,
      totalRequired: 5,
      workDetails: sl.workDetails,
      isWorkDetailLoaded: true,
      workDetailStats: const {
        'w-open': {'confirmed': 0, 'pending': 0},
        'w-closed': {'confirmed': 0, 'pending': 0},
      },
    );
    // 대조군: 마감을 보지 않는 기존 집계는 둘을 다 더한다.
    expect(item.resolveStats().shortage, 5);
    expect(item.persistedOpenShortage(master: _to()), 2,
        reason: '서버 날짜 창도 업무별 isClosed 로 뺀다');
  });
}
