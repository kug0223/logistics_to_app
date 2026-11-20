// [SIM-EXPIRED-JOB-CARD] 만료된 초대가 일자리 탭 카드에 "지원완료"로 보였다
//
// DEVICE(10-19 01:13, 원본 APK 6e23a650, 7oZZ): DEV 에서 EXPIRED 인 초대(10/19 14:00–15:00)의
//   공고 카드에 일자리 탭이 `지원완료` 배지를 붙였다. 같은 건이 '내 지원'에서는 "초대 종료"이고,
//   공용 판정 `ApplicationRelationResolver` 는 EXPIRED 를 "관계 없음 → 재지원 가능"으로 본다.
//
// 원인: `UserTOCard` 의 세 판정(`_rebuildAppliedSets`·`_computeHasApplied`·`_appForWork`)이
//   공용 판정 대신 `AppStatus.inactiveStates`(REJECTED·CANCELED·AUTO_CANCELED)만 걸렀다.
//
//   UTC-1  flex compact — EXPIRED 는 지원완료가 아니다 (반례)
//   UTC-2  flex compact 대조군 — PENDING·CONFIRMED·INVITED 는 지원완료, CANCELED 는 아니다
//   UTC-3  계약(비 flex) 펼친 카드 — EXPIRED 는 `지원하기`, 업무 행에 `대기중` 없음 (반례)
//   UTC-4  계약 펼친 카드 대조군 — PENDING 은 `지원관리`·`대기중`, CONFIRMED 는 `확정`
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/visible_text.dart'; // [DU255] keepWords 문구는 보이는 글자로 찾는다
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';

import 'package:ALfit/models/core/application_model.dart';
import 'package:ALfit/models/core/to_model.dart';
import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/models/core/work_detail_data.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/widgets/user/cards/user_to_card.dart';

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

class _UserDouble extends UserProvider {
  @override
  UserModel? get currentUser => UserModel(uid: 'u1', username: 'u1', name: '김근로', email: 'u1@alfit.local', role: UserRole.USER, accountStatus: 'active');
}

DateTime _day(int offset) {
  final n = DateTime.now();
  return DateTime(n.year, n.month, n.day).add(Duration(days: offset));
}

String _key(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, "0")}-${d.day.toString().padLeft(2, "0")}';

const _wd = WorkDetailData(wdId: 'wd1', workType: 'QA 분류', wage: 12000, requiredCount: 1, startTime: '14:00', endTime: '15:00');

TOModel _to({required String id, required String type}) => TOModel(
      id: id, businessId: 'biz1', businessName: '골든패스 테스트 사업장', businessCity: '평택시', type: type,
      title: '공고 $id', creatorUID: 'admin1', status: TOStatus.active, deadlineType: 'NONE', hoursBeforeStart: 0,
      workDetails: const [_wd], slotDateKeys: type == 'flex' ? [_key(_day(2))] : const [], totalSlots: type == 'flex' ? 1 : 0,
      totalRequired: 1, totalConfirmed: 0, totalPending: 0, isPublished: true, publishMode: 'immediate',
      rangeStart: _day(2), rangeEnd: _day(30), createdAt: _day(-3), statusUpdatedAt: _day(-3),
    );

ApplicationModel _app(String toId, String status, {bool longTerm = false}) => ApplicationModel(
      id: '${toId}_slot_wd1_u1_$status', toId: toId, slotId: longTerm ? null : 'slot_$toId', wdId: 'wd1', businessId: 'biz1',
      businessName: '골든패스 테스트 사업장', toTitle: '공고 $toId', uid: 'u1', applicantName: '김근로', status: status,
      appliedAt: _day(-1), workDate: _day(2), selectedWorkType: 'QA 분류', startTime: '14:00', endTime: '15:00',
      wage: 12000, wageType: 'hourly', applicationType: longTerm ? AppType.longTerm : AppType.shortTerm,
    );

Future<void> _pump(WidgetTester tester, TOModel to, List<ApplicationModel> apps, {required bool compact}) async {
  tester.view.physicalSize = const Size(390, 1800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ChangeNotifierProvider<UserProvider>.value(
    value: _UserDouble(),
    child: MaterialApp(home: Scaffold(body: SingleChildScrollView(child: UserTOCard(
      to: to, myApplications: apps, onApplySuccess: () {}, compact: compact,
      workDetails: compact ? null : const [_wd],
      // 일반(펼침) 모드는 선택 상태를 받는다 — 이 카드가 선택(펼침)된 상태로 그린다.
      selectedNotifier: compact ? null : ValueNotifier<String?>(to.id),
    )))),
  ));
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
    await initializeDateFormatting('ko_KR', null);
  });

  testWidgets('UTC-1 flex compact — EXPIRED 는 지원완료가 아니다', (tester) async {
    await _pump(tester, _to(id: 'C', type: 'flex'), [_app('C', AppStatus.expired)], compact: true);
    expect(find.text('지원완료'), findsNothing, reason: '만료된 초대를 지원한 것처럼 보이지 않는다');
  });

  for (final c in [
    (AppStatus.pending, true), (AppStatus.confirmed, true), (AppStatus.invited, true), (AppStatus.canceled, false),
  ]) {
    testWidgets('UTC-2 flex compact 대조군 — ${c.$1} → 지원완료 ${c.$2}', (tester) async {
      await _pump(tester, _to(id: 'C', type: 'flex'), [_app('C', c.$1)], compact: true);
      expect(find.text('지원완료'), c.$2 ? findsOneWidget : findsNothing);
    });
  }

  testWidgets('UTC-3 계약 펼친 카드 — EXPIRED 는 지원하기, 대기중 없음', (tester) async {
    await _pump(tester, _to(id: 'L', type: 'contract'), [_app('L', AppStatus.expired, longTerm: true)], compact: false);
    expect(findVisibleText('지원하기'), findsOneWidget);
    expect(find.text('지원관리'), findsNothing);
    expect(find.text('대기중'), findsNothing);
    expect(find.text('지원완료'), findsNothing);
  });

  testWidgets('UTC-4 계약 펼친 카드 대조군 — PENDING 은 지원관리·대기중', (tester) async {
    await _pump(tester, _to(id: 'L', type: 'contract'), [_app('L', AppStatus.pending, longTerm: true)], compact: false);
    expect(find.text('지원관리'), findsOneWidget);
    expect(find.text('대기중'), findsOneWidget);
  });

  testWidgets('UTC-4b 계약 펼친 카드 대조군 — CONFIRMED 는 확정', (tester) async {
    await _pump(tester, _to(id: 'L', type: 'contract'), [_app('L', AppStatus.confirmed, longTerm: true)], compact: false);
    expect(find.text('지원관리'), findsOneWidget);
    expect(find.text('확정'), findsWidgets);
  });
}
