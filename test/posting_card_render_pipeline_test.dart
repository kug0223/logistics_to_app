import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'package:ALfit/controllers/workforce_controller.dart';
import 'package:ALfit/models/core/slot_model.dart';
import 'package:ALfit/models/core/to_model.dart';
import 'package:ALfit/models/core/work_detail_data.dart';
import 'package:ALfit/models/ui/admin_to_list_ui_models.dart';
import 'package:ALfit/screens/business_admin/dialogs/to_list_dialogs.dart';
import 'package:ALfit/services/firestore_service.dart';
import 'package:ALfit/widgets/admin/cards/admin_to_group_card.dart';

/// [R7-7 §4] **실제 `TOGroupCard` 를 띄워서** 날짜 선택 순서를 확인한다.
///
///   지난 차수에는 "Provider·FirestoreService 가 Firebase 로 가서 pump 할 수
///   없다"고 적었다. 두 가지가 사실이 아니었다:
///     · Provider 는 **build 가 아니라 액션 핸들러**에서만 읽힌다.
///     · `FirestoreService()` 는 firebase_core 플랫폼을 mock 하면 만들어진다.
///
///   그래서 복제품이 아니라 production 위젯을 그대로 pump 한다. 주입하는 것은
///   읽기 하나(`WorkforceController` 의 로더)뿐이다.

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
  Future<FirebaseAppPlatform> initializeApp({
    String? name,
    FirebaseOptions? options,
  }) async =>
      _FakeApp();
  @override
  List<FirebaseAppPlatform> get apps => [_FakeApp()];
}

// [R7-P4.4B] 시한부 fixture 정정.
//
//   이 파일은 근무일을 `DateTime(2026, 9, 29)` 로 못박고 있었다. 그 날이
//   지나자 카드가 '마감 · 운영 종료 · 근무일 미정' 으로 렌더되면서
//   PCR-2·PCR-3 이 깨졌다 — production 결함이 아니라 **날짜가 지난 것**이다.
//   검증하려는 것은 "집계가 카드에 반영되는가" 이고 특정 날짜가 아니므로,
//   오늘 기준 미래로 잡아 다시 썩지 않게 한다.
DateTime _day(int plusDays) {
  final n = DateTime.now();
  return DateTime(n.year, n.month, n.day).add(Duration(days: plusDays));
}

String _slotId(DateTime d) =>
    '${d.month.toString().padLeft(2, '0')}${d.day.toString().padLeft(2, '0')}';

TOModel _to(String id, {int totalConfirmed = 0, int totalRequired = 1}) => TOModel(
      id: id,
      businessId: 'biz1',
      businessName: '테스트 사업장',
      type: 'flex',
      title: '테스트 공고',
      creatorUID: 'uid1',
      status: 'ACTIVE',
      workDetails: const [],
      totalRequired: totalRequired,
      totalConfirmed: totalConfirmed,
      totalPending: 0,
      isPublished: true,
      publishMode: 'immediate',
      createdAt: _day(-30),
      statusUpdatedAt: _day(-30),
    );

WorkDetailData _wd(String wdId) => WorkDetailData(
      wdId: wdId,
      workType: '홀서빙',
      startTime: '09:00',
      endTime: '18:00',
      requiredCount: 1,
      wage: 12000,
      wageType: 'hourly',
    );

TOItem _slot(String slotId, DateTime date, {required int confirmed}) => TOItem(
      to: _to('to1', totalConfirmed: confirmed),
      slot: SlotModel(
        id: slotId, toId: 'to1', date: date, workDetails: [_wd('wd-$slotId')]),
      confirmedCount: confirmed,
      pendingCount: 0,
      totalRequired: 1,
    );

Map<String, dynamic> _stats(String slotId, {required int confirmed}) => {
      'workDetails': [_wd('wd-$slotId')],
      'workStats': {
        'wd-$slotId': {'confirmed': confirmed, 'pending': 0}
      },
      'statsFailed': false,
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
  });

  /// 부모가 날짜를 골라 카드를 다시 그리는 화면. production 카드를 그대로 쓴다.
  Future<void> pumpCard(
    WidgetTester tester, {
    required TOGroupItem group,
    required DateTime? selectedDate,
    required WorkforceController controller,
  }) async {
    final svc = FirestoreService();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: Builder(builder: (ctx) {
            return TOGroupCard(
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
            );
          }),
        ),
      ),
    ));
    await tester.pump();
  }

  String headerText(WidgetTester tester) {
    final spans = <String>[];
    for (final w in tester.widgetList<RichText>(find.byType(RichText))) {
      spans.add(w.text.toPlainText());
    }
    return spans.join(' | ');
  }

  testWidgets('PCR-1 실제 카드 — 9/29 선택 1/1, 9/30 0/1, 9/29 복귀 1/1',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final d929 = _day(1);
    final d930 = _day(2);
    final id929 = _slotId(d929);
    final id930 = _slotId(d930);
    final s929 = _slot(id929, d929, confirmed: 1);
    final s930 = _slot(id930, d930, confirmed: 0);
    final group = TOGroupItem(singleTO: _to('to1', totalRequired: 2))
      ..setGroupTOs([s929, s930])
      ..setSlotDates([d929, d930]);

    final loaded = <String>[];
    final controller = WorkforceController(
      loadWorkDetailStats: (to, {slotId, slotWorkDetails}) async {
        loaded.add(slotId ?? '(group)');
        return _stats(slotId!, confirmed: slotId == id929 ? 1 : 0);
      },
    );
    addTearDown(controller.dispose);

    // 9/29 선택 — 아직 집계 전, 카운터로 말한다.
    await pumpCard(tester,
        group: group, selectedDate: d929, controller: controller);
    expect(headerText(tester), contains('충원 1'));
    expect(headerText(tester), contains('필요 1'));

    // 집계가 그 인스턴스 안에 채워진다(제자리 수정) → 부모가 다시 그린다.
    await controller.loadWorkDetails(s929);
    await pumpCard(tester,
        group: group, selectedDate: d929, controller: controller);
    expect(headerText(tester), contains('충원 1'),
        reason: '선택 후 0 이 되면 그 증상이다');

    // 9/30
    await controller.loadWorkDetails(s930);
    await pumpCard(tester,
        group: group, selectedDate: d930, controller: controller);
    expect(headerText(tester), contains('충원 0'));
    expect(headerText(tester), contains('필요 1'));

    // 9/29 복귀
    await pumpCard(tester,
        group: group, selectedDate: d929, controller: controller);
    expect(headerText(tester), contains('충원 1'));

    // 날짜 해제 = 요약. 두 날짜의 합이며 날짜별과 어긋나지 않는다.
    await pumpCard(tester,
        group: group, selectedDate: null, controller: controller);
    expect(headerText(tester), contains('충원 1'));
    expect(headerText(tester), contains('필요 2'));

    expect(loaded, [id929, id930], reason: '이미 읽은 것을 다시 읽지 않는다');
  });

  testWidgets('PCR-2 같은 인스턴스에 새 집계가 오면 카드가 그 값을 말한다',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final d = _day(1);
    final s = _slot(_slotId(d), d, confirmed: 1);
    final group = TOGroupItem(singleTO: _to('to1', totalRequired: 1))
      ..setGroupTOs([s])
      ..setSlotDates([d]);

    final controller = WorkforceController(
      loadWorkDetailStats: (to, {slotId, slotWorkDetails}) async =>
          _stats(slotId!, confirmed: 0),
    );
    addTearDown(controller.dispose);

    await pumpCard(tester, group: group, selectedDate: d, controller: controller);
    expect(headerText(tester), contains('충원 1'), reason: '집계 전에는 카운터');

    // 집계 도착 — 같은 인스턴스가 바뀐다. 부모 rebuild 만으로 반영되어야 한다.
    await controller.loadWorkDetails(s);
    await pumpCard(tester, group: group, selectedDate: d, controller: controller);
    expect(headerText(tester), contains('충원 0'),
        reason: 'identical(groupItem) 로 캐시를 거르면 여기서 1 이 남는다');
  });

  testWidgets('PCR-3 로드 실패는 0 이 아니라 카운터로 떨어지고 재시도가 반영된다',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final d = _day(1);
    final s = _slot(_slotId(d), d, confirmed: 1);
    final group = TOGroupItem(singleTO: _to('to1', totalRequired: 1))
      ..setGroupTOs([s])
      ..setSlotDates([d]);

    var attempt = 0;
    final controller = WorkforceController(
      loadWorkDetailStats: (to, {slotId, slotWorkDetails}) async {
        attempt++;
        if (attempt == 1) throw StateError('network');
        return _stats(slotId!, confirmed: 0);
      },
    );
    addTearDown(controller.dispose);

    await controller.loadWorkDetails(s);
    await pumpCard(tester, group: group, selectedDate: d, controller: controller);
    expect(headerText(tester), contains('충원 1'),
        reason: '실패를 확정 0 으로 커밋하지 않는다');

    // 카드가 노출하는 재시도 경로 = controller 위임. 두 번째는 성공한다.
    await controller.loadWorkDetails(s);
    expect(attempt, 2, reason: '실패 뒤 재시도가 막히면 안 된다');
    await pumpCard(tester, group: group, selectedDate: d, controller: controller);
    expect(headerText(tester), contains('충원 0'));
  });
}
