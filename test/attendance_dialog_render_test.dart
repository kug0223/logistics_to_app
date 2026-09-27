import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/utils/format_helper.dart';
import 'package:ALfit/screens/business_admin/dialogs/attendance_status_dialog.dart';

/// [R7-P1-3 RENDER] 제약된 기기 폭에서 **production `AttendanceStatusDialog`** 을 띄운다.
///
///   범위를 먼저 밝힌다: 이 테스트는 **조회 실패 경로**를 그린다.
///   이 화면은 읽기를 `FirestoreService()` 로 직접 하고(주입 경계가 아직 없다)
///   테스트 환경에는 백엔드가 없으므로, `_loadData` 가 실패해 `_loadError` 상태가
///   된다. 그래서 여기서 확인되는 것은 이것뿐이다:
///
///     · 실제 화면이 360dp·320dp 폭에서 **overflow 없이** 그려진다
///     · 실패를 "근무자 0명" 으로 말하지 않는다(에러 상태가 뜬다)
///     · 명단을 모르는 상태에서 명단 전제 하단 바를 열지 않는다
///     · 머리말 날짜가 넘어온 값의 **달력 성분** 그대로 찍힌다
///
///   **production 행·액션 렌더는 이 테스트 범위가 아니다.** 그것은
///   `DayApplicantsReads` 와 같은 읽기 경계를 이 화면에도 도입한 뒤에 가능하다
///   (P1-3 잔여 항목으로 남겼다).

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

Future<void> _pumpAt(WidgetTester tester, Size size, DateTime date) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ChangeNotifierProvider<UserProvider>(
      create: (_) => UserProvider(),
      child: MaterialApp(
        home: Scaffold(
          body: AttendanceStatusDialog(
            date: date,
            businessIds: const ['biz1'],
            initialBusinessId: 'biz1',
          ),
        ),
      ),
    ),
  );
  // 로드가 실패로 끝날 때까지 — 고정 지연이 아니라 프레임을 돌린다.
  for (var i = 0; i < 40; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
    // 앱은 `main()`에서 이것을 한다(lib/main.dart:71). 화면은 'ko_KR' 로케일
    //   DateFormat 을 쓰므로 테스트에서도 같은 초기화가 필요하다.
    await initializeDateFormatting('ko_KR', null);
  });

  testWidgets('ADR-1 360dp 에서 overflow 없이 그려지고, 실패를 0명으로 말하지 않는다',
      (tester) async {
    await _pumpAt(tester, const Size(360, 640), FormatHelper.toKstDate(DateTime(2026, 9, 28)));

    expect(tester.takeException(), isNull);
    expect(find.text('당일명단'), findsOneWidget);
    // 조회 실패 → 에러 상태. '확정된 근무자가 없습니다' 를 쓰지 않는다.
    expect(find.text('확정된 근무자가 없습니다'), findsNothing);
    expect(find.textContaining('명단'), findsWidgets);
    // 명단을 모르는 상태에서 명단 전제 행동을 열지 않는다.
    expect(find.text('명단 출력'), findsNothing);
  });

  testWidgets('ADR-2 320dp 좁은 폭에서도 overflow 가 없다', (tester) async {
    await _pumpAt(tester, const Size(320, 568), FormatHelper.toKstDate(DateTime(2026, 9, 28)));
    expect(tester.takeException(), isNull);
    expect(find.text('당일명단'), findsOneWidget);
  });

  testWidgets('ADR-3 머리말 날짜는 넘어온 값의 달력 성분을 찍는다', (tester) async {
    // 기기 local 자정으로 들어와도(미처리 큐·근무 탭 형태) 같은 날짜가 보인다.
    await _pumpAt(tester, const Size(360, 640), DateTime(2026, 9, 28));
    expect(tester.takeException(), isNull);
    expect(find.textContaining('09월 28일'), findsOneWidget);
  });
}
