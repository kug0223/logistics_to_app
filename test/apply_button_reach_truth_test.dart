// [R7-P2-2 A1-0] 지원 버튼 도달 진실 검증 — "업무 카드 0개" 의 원인 고정.
//
// 결론(측정으로 확정):
//  · 업무 카드 목록은 **reader 가 아니라 생성자 인자 `widget.workDetails`** 에서 나온다.
//    따라서 카드 0 은 "조회가 비었다" 가 아니다.
//  · 카드를 그리는 `_buildContent` 는 `_isLoading == false` 일 때만 빌드된다.
//    `_isLoading` 은 `_loadInitialData()` 의 finally 에서만 풀린다.
//  · 그 안의 `Future.wait` 세 갈래(`_loadDateApplications` /
//    `_loadMyConfirmedSchedules` / `_loadConflictsForDate`)는 모두
//    `FirestoreService` 로 내려간다. 이 서비스는 **하드 싱글턴**이고
//    (`factory FirestoreService() => _instance`), 내부 `_firestore` 는
//    `FirebaseFirestore.instance` 로 **생성 시점에 고정된 private final** 이며,
//    읽기 메서드들은 `extension ... on FirestoreService` 로 **정적 디스패치**된다.
//    → 하위 클래스·fake 로도 가로챌 수 없고, 다이얼로그에 주입점도 없다.
//  · 격리 환경에서 이 세 future 는 **거부되지도 않고 완료되지도 않는다**
//    (어떤 loader 의 catch 도 찍히지 않는다) → finally 미도달 → 영구 로딩.
//
// 그래서 A1-1(성공/이미지원/실패/모름 네 결과 렌더)은 **격리 실행 불가**다.
// production 에 통과 목적의 쓰기·주입 seam 을 남기지 않는다.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';

import 'package:ALfit/models/core/to_model.dart';
import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/models/core/work_detail_data.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/widgets/common/loading_widget.dart';
import 'package:ALfit/widgets/dialogs/apply/apply_work_dialog.dart';

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

class _LoggedIn extends UserProvider {
  @override
  UserModel? get currentUser => UserModel(
        uid: 'u1',
        username: 'u1',
        name: '김근로',
        email: 'u1@alfit.local',
        role: UserRole.USER,
        createdAt: DateTime(2026, 1, 1),
      );
}

class _LoggedOut extends UserProvider {
  @override
  UserModel? get currentUser => null;
}

TOModel _to() => TOModel(
      id: 'to1',
      businessId: 'biz1',
      businessName: '강남 물류센터',
      type: 'flex',
      title: '단기 모집',
      creatorUID: 'admin1',
      status: TOStatus.active,
      deadlineType: 'NONE',
      hoursBeforeStart: 0,
      workDetails: const [],
      totalRequired: 4,
      totalConfirmed: 0,
      totalPending: 0,
      isPublished: true,
      publishMode: 'immediate',
      createdAt: DateTime(2026, 9, 1),
      statusUpdatedAt: DateTime(2026, 9, 1),
    );

WorkDetailData _work() => WorkDetailData(
      wdId: 'wd1',
      workType: '상하차',
      workTypeIcon: 'box',
      workTypeColor: '#000000',
      workTypeBackgroundColor: '#FFFFFF',
      wage: 12000,
      wageType: 'hourly',
      requiredCount: 4,
      startTime: '09:00',
      endTime: '18:00',
      order: 0,
    );

Widget _app(UserProvider provider) =>
    ChangeNotifierProvider<UserProvider>.value(
      value: provider,
      child: MaterialApp(
        home: Scaffold(
          body: ApplyWorkDialog(
            mainTO: _to(),
            workDetails: [_work()],
            slotId: 'slot1',
            businessName: '강남 물류센터',
          ),
        ),
      ),
    );

Future<void> _settleish(WidgetTester tester) async {
  await tester.pump();
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
  });

  testWidgets('[ABR-1] 로그인 정보가 없으면 다이얼로그가 스스로 닫힌다', (tester) async {
    await tester.pumpWidget(_app(_LoggedOut()));
    await _settleish(tester);

    // `_initializeData` 는 uid 가 없으면 안내 후 pop 하고 **return** 한다.
    // 이 경로는 조회를 시작하지도 않는다 — "카드 0" 의 원인이 아니다.
    expect(find.byType(ApplyWorkDialog), findsNothing);
    expect(find.byType(LoadingWidget), findsNothing);
  });

  testWidgets('[ABR-2] reads 를 주지 않으면 가짜 시계에서 초기 조회가 끝나지 않는다',
      (tester) async {
    await tester.pumpWidget(_app(_LoggedIn()));
    await _settleish(tester);

    // 헤더·하단 버튼은 로딩 분기 **밖**이라 그려진다 — 껍데기는 살아있다.
    expect(find.text('지원하기'), findsOneWidget);
    expect(find.text('강남 물류센터'), findsOneWidget);
    expect(find.text('닫기'), findsOneWidget);

    // 본문은 로딩에 머문다. `widget.workDetails` 에 업무를 1건 넘겼는데도
    // '업무 선택' 섹션과 업무 카드가 없다 → 자료 누락이 아니라 **도달 차단**이다.
    expect(find.byType(LoadingWidget), findsOneWidget);
    expect(find.text('업무 선택'), findsNothing);
    expect(find.text('상하차'), findsNothing);

    // ── [R7-P2-2 A1 후속] 그 신호가 왔다. 읽기 경계가 생겼고(`ApplyWorkReads`)
    //    카드 도달과 네 결과를 실제로 실행했다:
    //      · `apply_dialog_initial_reads_test.dart` — 대기면 스피너(ARR-1),
    //        완료면 카드·지원 버튼(ARR-3)
    //      · `apply_result_render_test.dart` — 확인 시트와 네 결과(APR-1~9)
    //
    //    이 테스트는 **지우지 않는다.** 지금 고정하는 것은 제품 결함이 아니라
    //    하네스 사실이다: `reads` 를 주지 않으면(production 기본값) 초기 읽기가
    //    실제 Firestore/CF 채널로 나가고, `testWidgets` 의 가짜 시계는 그
    //    future 를 돌리지 않으므로 로딩이 풀리지 않는다.
    //    (`runAsync` 로 진짜 async 를 한 틱 돌려야 움직인다 — 새 테스트가 그렇게 한다.)
    //    실기기에서는 응답이 오거나 오류가 오므로 이 상태가 아니다.
  });
}
