// [R8-RELEASE-HYGIENE §4] **실제 알림 화면을 그린다.**
//
//   이 화면은 lib 31곳에서 진입하는데, 계약 테스트는 10곳이 넘는 반면
//   `testWidgets` 로 한 번도 pump 된 적이 없었다(R8-CLOSURE §F 실측:
//   핵심 8영역 중 유일한 RENDER NOT TESTED). 그래서 "코드가 맞다"와
//   "화면에 보인다" 사이가 비어 있었다.
//
//   바꿔 끼우는 것은 `NotificationProvider` 의 읽기 결과 하나뿐이다.
//   빈 상태·오류·필터·역할 분기·카드 문구는 production 경로를 그대로 지난다.
//   테스트용 카드나 문구를 복제하지 않는다.
//
//   새 알림 기능은 만들지 않는다 — 지금 있는 상태를 보이는지만 본다.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ALfit/models/core/notification_model.dart';
import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/providers/notification_provider.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/screens/common/notification_screen.dart';
import 'package:ALfit/utils/navigation_key.dart';

class _FakeApp extends Fake
    with MockPlatformInterfaceMixin
    implements FirebaseAppPlatform {
  @override
  String get name => defaultFirebaseAppName;
  @override
  FirebaseOptions get options => const FirebaseOptions(
      apiKey: 'k',
      appId: 'a',
      messagingSenderId: 's',
      projectId: 'p',
      storageBucket: 'p.appspot.com');
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

/// 읽기 결과만 고정한다. 목록 가공(최근 N일 창·삭제 대기 숨김)은
/// production getter 가 하던 일이므로 여기서 흉내내지 않고, 화면이 보는
/// 표면(`notifications`·`isLoading`·`hasError`)만 바꿔 끼운다.
class _NotifDouble extends NotificationProvider {
  _NotifDouble({
    List<NotificationModel>? items,
    this.loading = false,
    this.error = false,
    this.more = false,
  }) : items = items ?? const [];

  List<NotificationModel> items;
  bool loading;
  bool error;
  bool more;

  /// 화면이 도메인 상태를 건드렸는지 추적한다 — 눌렀을 때 무엇이 일어나는지.
  final List<String> markedRead = [];
  int markAllCalls = 0;
  int retryCalls = 0;

  @override
  List<NotificationModel> get notifications => items;
  @override
  bool get isLoading => loading;
  @override
  bool get hasError => error;
  @override
  bool get hasMore => more;
  @override
  bool get isLoadingMore => false;
  @override
  bool get loadMoreFailed => false;

  @override
  Future<void> markAsRead(String id) async => markedRead.add(id);
  @override
  Future<bool> markAllAsRead() async {
    markAllCalls++;
    return true;
  }

  @override
  void retry() => retryCalls++;
}

/// 역할만 바꾼다. 알림 화면은 `isSubAdmin` 으로 탭 수를 가른다.
class _UserDouble extends UserProvider {
  _UserDouble({this.role = UserRole.USER, this.subAdminOf = const []});

  final UserRole role;
  final List<String> subAdminOf;

  @override
  UserModel? get currentUser => UserModel(
        uid: 'u1',
        name: '김근무',
        username: 'qaworker1',
        // 앱이 계산하는 system email 형식을 그대로 둔다.
        email: 'qaworker1@ALfit-system.com',
        phone: '01000000000',
        role: role,
        createdAt: DateTime(2026, 1, 1),
        subAdminBusinessIds: subAdminOf,
      );

  @override
  bool get isUser => role == UserRole.USER;
  @override
  bool get isBusinessAdmin => role == UserRole.BUSINESS_ADMIN;
  @override
  bool get isSubAdmin => role == UserRole.USER && subAdminOf.isNotEmpty;
  @override
  bool get isAdminMode => role == UserRole.BUSINESS_ADMIN;
  @override
  bool get permissionsLoaded => true;
}

NotificationModel _n({
  required String id,
  NotificationType type = NotificationType.applicationConfirmed,
  String title = '지원이 확정되었습니다',
  String body = '10월 15일 상하차 근무가 확정되었습니다.',
  bool isRead = false,
  int daysAgo = 0,
  bool createdAtKnown = true,
  Map<String, dynamic>? data,
}) =>
    NotificationModel(
      id: id,
      userId: 'u1',
      type: type,
      title: title,
      body: body,
      isRead: isRead,
      createdAt: DateTime.now().subtract(Duration(days: daysAgo, minutes: 5)),
      createdAtKnown: createdAtKnown,
      data: data,
    );

Future<_NotifDouble> _pump(
  WidgetTester t, {
  List<NotificationModel>? items,
  bool loading = false,
  bool error = false,
  bool more = false,
  UserRole role = UserRole.USER,
  List<String> subAdminOf = const [],
  Size size = const Size(360, 780),
  double textScale = 1.0,
  double bottomInset = 0,
  Map<String, dynamic>? autoDispatchPayload,
}) async {
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);

  final notif = _NotifDouble(
      items: items, loading: loading, error: error, more: more);

  await t.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider<NotificationProvider>.value(value: notif),
      ChangeNotifierProvider<UserProvider>.value(
          value: _UserDouble(role: role, subAdminOf: subAdminOf)),
    ],
    child: MaterialApp(
      // 권한 차단 안내는 전역 overlay 토스트로 나온다 — 같은 key 를 붙여야 읽힌다.
      navigatorKey: navigatorKey,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(textScale),
          viewPadding: EdgeInsets.only(bottom: bottomInset),
          padding: EdgeInsets.only(bottom: bottomInset),
        ),
        child: child!,
      ),
      home: NotificationScreen(autoDispatchPayload: autoDispatchPayload),
    ),
  ));
  // initState 의 postFrameCallback(payload dispatch) 까지 흘린다.
  await t.pump();
  await t.pump(const Duration(milliseconds: 100));
  return notif;
}

/// 토스트가 뜬 뒤 프레임을 흘린다.
///
///   `ToastHelper` 는 자동 닫기용 2초 타이머를 건다. 그래서 `pumpAndSettle` 은
///   "Pending timers" 로 끝나지 않는다 — 토스트가 **떴기 때문에** 실패한다.
///   토스트를 읽으려면 settle 하지 말고 프레임만 흘려야 한다.
Future<void> _settleToast(WidgetTester t) async {
  await t.pump();
  await t.pump(const Duration(milliseconds: 350));
}

/// 셀을 끝내기 전에 토스트 타이머를 비운다 — 안 비우면 다음 셀로 샌다.
Future<void> _drainToast(WidgetTester t) async =>
    t.pump(const Duration(seconds: 3));

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
    await initializeDateFormatting('ko_KR', null);
  });

  // ══════════════════════════════════════════════════════════════════
  // 1. 상태별 렌더 — 모름·오류·없음을 서로 섞지 않는다
  // ══════════════════════════════════════════════════════════════════

  testWidgets('NTF-01 알림 없음 — 비어 있다고 말하고 다음을 안내한다', (t) async {
    await _pump(t, items: const []);
    expect(find.text('알림'), findsOneWidget);          // AppBar
    expect(find.text('알림이 없습니다'), findsOneWidget);
    expect(find.text('새로운 알림이 오면 여기에서 확인할 수 있어요.'), findsOneWidget);
    // 빈 상태에서 "모두 읽음" 을 내밀지 않는다 — 읽을 것이 없다.
    expect(find.text('모두 읽음'), findsNothing);
    expect(t.takeException(), isNull);
  });

  testWidgets('NTF-02 조회 오류 — 빈 목록과 다른 화면이고 재시도가 있다', (t) async {
    final p = await _pump(t, error: true, items: const []);
    // ERROR ≠ EMPTY. 이 문구가 '알림이 없습니다'로 바뀌면 사용자는
    // 조회가 실패한 줄 모르고 "알림이 안 왔다"고 믿는다.
    expect(find.text('알림을 불러오지 못했습니다'), findsOneWidget);
    expect(find.text('알림이 없습니다'), findsNothing);
    expect(find.text('다시 시도'), findsOneWidget);

    await t.tap(find.text('다시 시도'));
    await t.pump();
    expect(p.retryCalls, 1, reason: '재시도가 실제로 provider 에 닿아야 한다');
    expect(t.takeException(), isNull);
  });

  testWidgets('NTF-03 로딩 — 없음이라고 말하지 않는다', (t) async {
    await _pump(t, loading: true, items: const []);
    expect(find.text('알림 불러오는 중...'), findsOneWidget);
    expect(find.text('알림이 없습니다'), findsNothing);
    expect(t.takeException(), isNull);
  });

  testWidgets('NTF-04 정상 목록 — 제목과 본문이 보인다', (t) async {
    await _pump(t, items: [
      _n(id: 'a', title: '지원이 확정되었습니다'),
      _n(id: 'b', title: '계약서 서명이 필요합니다', isRead: true, daysAgo: 1),
      _n(id: 'c', title: '급여가 지급되었습니다', isRead: true, daysAgo: 3),
    ]);
    expect(find.text('지원이 확정되었습니다'), findsOneWidget);
    expect(find.text('계약서 서명이 필요합니다'), findsOneWidget);
    expect(find.text('급여가 지급되었습니다'), findsOneWidget);
    expect(find.text('알림이 없습니다'), findsNothing);
    expect(t.takeException(), isNull);
  });

  testWidgets('NTF-05 읽음·안 읽음 — 미읽음이 있으면 모두 읽음이 뜬다', (t) async {
    final p = await _pump(t, items: [
      _n(id: 'a', isRead: false),
      _n(id: 'b', isRead: true, daysAgo: 1),
    ]);
    expect(find.text('모두 읽음'), findsOneWidget);
    await t.tap(find.text('모두 읽음'));
    await _settleToast(t);
    expect(p.markAllCalls, 1);
    expect(t.takeException(), isNull);
    await _drainToast(t);
  });

  testWidgets('NTF-06 전부 읽음 — 모두 읽음 액션이 사라진다', (t) async {
    await _pump(t, items: [
      _n(id: 'a', isRead: true),
      _n(id: 'b', isRead: true, daysAgo: 1),
    ]);
    expect(find.text('모두 읽음'), findsNothing);
    expect(t.takeException(), isNull);
  });

  testWidgets('NTF-07 미읽음만 보기 — 읽은 알림이 목록에서 빠진다', (t) async {
    await _pump(t, items: [
      _n(id: 'a', title: '안 읽은 알림', isRead: false),
      _n(id: 'b', title: '읽은 알림', isRead: true, daysAgo: 1),
    ]);
    expect(find.text('읽은 알림'), findsOneWidget);

    await t.tap(find.text('미읽음만'));
    await t.pumpAndSettle();

    expect(find.text('안 읽은 알림'), findsOneWidget);
    expect(find.text('읽은 알림'), findsNothing);
    expect(t.takeException(), isNull);
  });

  testWidgets('NTF-08 미읽음만 보기 + 미읽음 0 — 전용 문구를 쓴다', (t) async {
    await _pump(t, items: [_n(id: 'a', isRead: true)]);
    await t.tap(find.text('미읽음만'));
    await t.pumpAndSettle();
    // '알림이 없습니다'가 아니다 — 알림은 있고, 안 읽은 것만 없다.
    expect(find.text('새로운 알림이 없습니다'), findsOneWidget);
    expect(find.text('모든 알림을 확인했어요.'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  // ══════════════════════════════════════════════════════════════════
  // 2. 정보가 모자란 알림 — 사라지지 않고, 깨지지도 않는다
  // ══════════════════════════════════════════════════════════════════

  testWidgets('NTF-09 시각을 모르는 알림도 목록에 남는다', (t) async {
    // 깨진 createdAt 하나 때문에 "그 일이 있었다"는 사실까지 지우지 않는다.
    await _pump(t, items: [
      _n(id: 'a', title: '시각 미상 알림', createdAtKnown: false),
      _n(id: 'b', title: '정상 알림'),
    ]);
    expect(find.text('시각 미상 알림'), findsOneWidget);
    expect(find.text('정상 알림'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('NTF-10 제목·본문이 비어도 카드가 깨지지 않는다', (t) async {
    await _pump(t, items: [
      _n(id: 'a', title: '', body: ''),
      _n(id: 'b', title: '정상 알림', body: ''),
    ]);
    expect(find.text('정상 알림'), findsOneWidget);
    expect(find.text('알림이 없습니다'), findsNothing);
    expect(t.takeException(), isNull);
  });

  testWidgets('NTF-11 data 가 비어도 렌더는 멀쩡하다', (t) async {
    // 대상 식별자(applicationId 등)가 없는 옛 알림.
    await _pump(t, items: [
      _n(id: 'a', title: '대상 없는 지원 알림', data: const {}),
      _n(id: 'b', title: '대상 null 지원 알림'),
    ]);
    expect(find.text('대상 없는 지원 알림'), findsOneWidget);
    expect(find.text('대상 null 지원 알림'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  // ══════════════════════════════════════════════════════════════════
  // 3. 누르면 무엇이 일어나는가 — 정보성은 이동하지 않는다
  // ══════════════════════════════════════════════════════════════════

  testWidgets('NTF-12 정보성 알림 — 눌러도 다른 화면으로 가지 않는다', (t) async {
    final p = await _pump(t, items: [
      _n(id: 'a', type: NotificationType.systemNotice, title: '점검 안내'),
    ]);
    await t.tap(find.text('점검 안내'));
    await t.pumpAndSettle();

    // 알림 화면이 그대로다 — 공지는 카드에 이미 다 쓰여 있으므로
    // 이동할 목적지가 없다. 없는 곳으로 밀지 않는다.
    expect(find.text('알림'), findsOneWidget);
    expect(find.text('점검 안내'), findsOneWidget);
    // 읽음 처리는 도메인 업무 완료가 아니다 — 읽음만 기록한다.
    expect(p.markedRead, ['a']);
    expect(t.takeException(), isNull);
  });

  testWidgets('NTF-13 deep link payload 가 비정상이어도 목록은 열린다', (t) async {
    // FCM payload 로 바로 들어온 경우. type 이 없으면 dispatch 를 건너뛰고
    // 목록만 보여야 한다 — 추측해서 엉뚱한 화면을 열지 않는다.
    await _pump(t,
        items: [_n(id: 'a', title: '정상 알림')],
        autoDispatchPayload: const {'screen': ''});
    expect(find.text('알림'), findsOneWidget);
    expect(find.text('정상 알림'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('NTF-12b 순수 USER 가 관리자 알림을 눌러도 이동하지 않는다', (t) async {
    // 알림은 30일 남는다 — 발송 시점 권한과 탭 시점 권한이 다를 수 있다.
    //   순수 USER 에게 관리자 알림이 남아 있으면 그 목적지는 그의 것이 아니다.
    //   막되, 왜 막혔는지는 말한다.
    await _pump(t, role: UserRole.USER, items: [
      _n(
          id: 'm',
          type: NotificationType.newApplication,
          title: '새 지원자가 있습니다',
          data: const {'businessId': 'b1', 'toId': 't1'}),
    ]);
    await t.tap(find.text('새 지원자가 있습니다'));
    await _settleToast(t);

    expect(find.text('현재 처리할 수 없는 알림입니다.'), findsOneWidget);
    // 알림 목록에 그대로 있다 — 엉뚱한 화면으로 밀려나지 않았다.
    expect(find.text('알림'), findsOneWidget);
    expect(t.takeException(), isNull);
    await _drainToast(t);
  });

  testWidgets('NTF-12c SubAdmin — 소속이 아닌 사업장 알림은 사유와 함께 막는다', (t) async {
    await _pump(t, role: UserRole.USER, subAdminOf: const ['b1'], items: [
      _n(
          id: 'm',
          type: NotificationType.newApplication,
          title: '다른 사업장 지원자 알림',
          data: const {'businessId': 'bX', 'toId': 't1'}),
    ]);
    await t.tap(find.text('다른 사업장 지원자 알림'));
    await _settleToast(t);

    // '권한이 없다'와 '확인하지 못했다'를 섞지 않는다. 여기는 소속이 아닌 경우다.
    expect(find.text('해당 사업장에 대한 관리자 권한이 없습니다.'), findsOneWidget);
    expect(find.text('알림'), findsOneWidget);
    expect(t.takeException(), isNull);
    await _drainToast(t);
  });

  // ══════════════════════════════════════════════════════════════════
  // 4. 역할 — 수신자와 탭 구성이 다르다
  // ══════════════════════════════════════════════════════════════════

  testWidgets('NTF-14 순수 USER — 탭이 없다', (t) async {
    await _pump(t, role: UserRole.USER, items: [_n(id: 'a')]);
    expect(find.byType(TabBar), findsNothing);
    expect(find.text('관리 알림'), findsNothing);
    expect(t.takeException(), isNull);
  });

  testWidgets('NTF-15 BUSINESS_ADMIN — 단일 목록이다', (t) async {
    await _pump(t, role: UserRole.BUSINESS_ADMIN, items: [_n(id: 'a')]);
    expect(find.byType(TabBar), findsNothing);
    expect(t.takeException(), isNull);
  });

  testWidgets('NTF-16 SubAdmin — 전체·내 알림·관리 알림 세 탭', (t) async {
    await _pump(t,
        role: UserRole.USER, subAdminOf: const ['b1'], items: [_n(id: 'a')]);
    expect(find.byType(TabBar), findsOneWidget);
    expect(find.text('전체'), findsOneWidget);
    expect(find.text('내 알림'), findsOneWidget);
    expect(find.text('관리 알림'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('NTF-17 SubAdmin — 관리 알림이 내 알림 탭에 섞이지 않는다', (t) async {
    await _pump(t, role: UserRole.USER, subAdminOf: const ['b1'], items: [
      _n(id: 'p', title: '내 지원이 확정됐어요',
          type: NotificationType.applicationConfirmed),
      _n(id: 'm', title: '새 지원자가 있습니다',
          type: NotificationType.newApplication),
    ]);

    // 전체 탭: 둘 다
    expect(find.text('내 지원이 확정됐어요'), findsOneWidget);
    expect(find.text('새 지원자가 있습니다'), findsOneWidget);

    // 내 알림 탭: 관리 알림은 없다
    await t.tap(find.text('내 알림'));
    await t.pumpAndSettle();
    expect(find.text('내 지원이 확정됐어요'), findsOneWidget);
    expect(find.text('새 지원자가 있습니다'), findsNothing);

    // 관리 알림 탭: 개인 알림은 없다
    await t.tap(find.text('관리 알림'));
    await t.pumpAndSettle();
    expect(find.text('새 지원자가 있습니다'), findsOneWidget);
    expect(find.text('내 지원이 확정됐어요'), findsNothing);
    expect(t.takeException(), isNull);
  });

  // ══════════════════════════════════════════════════════════════════
  // 5. 폭 × 글자배율 — 긴 제목·본문으로 넘침을 본다
  // ══════════════════════════════════════════════════════════════════

  const longTitle = '장기 근무 계약 갱신 제안이 도착했습니다 — 확인 후 회신해 주세요';
  const longBody = '2026년 10월 15일부터 2027년 1월 14일까지의 장기 근무 계약 갱신 '
      '제안입니다. 시급과 근무 요일이 기존과 달라졌으니 조건을 확인한 뒤 수락 또는 '
      '거절을 선택해 주세요. 회신이 없으면 제안은 7일 후 자동으로 만료됩니다.';

  for (final w in [320.0, 360.0, 411.0]) {
    for (final s in [1.0, 1.3, 2.0]) {
      testWidgets('NTF-18 긴 알림 ${w.toStringAsFixed(0)}dp × 배율 $s', (t) async {
        await _pump(t,
            size: Size(w, 820),
            textScale: s,
            items: [
              _n(id: 'a', title: longTitle, body: longBody),
              _n(id: 'b', title: '짧은 알림', body: '한 줄', isRead: true, daysAgo: 2),
            ]);
        // 넘침은 예외로 나온다 — 어느 조합에서든 없어야 한다.
        expect(t.takeException(), isNull,
            reason: '폭 $w · 배율 $s 에서 넘쳤다');
      });
    }
  }

  // SubAdmin 3탭 + 미읽음 배지가 실제로 넘쳤던 지점이다(360dp 에서 3px).
  // 라벨 세 개와 배지 세 개가 한 줄에 들어가야 하므로 폭이 가장 빡빡하다.
  for (final w in [320.0, 360.0, 411.0]) {
    for (final s in [1.0, 1.3, 2.0]) {
      testWidgets('NTF-18b SubAdmin 3탭 ${w.toStringAsFixed(0)}dp × 배율 $s',
          (t) async {
        await _pump(t,
            role: UserRole.USER,
            subAdminOf: const ['b1'],
            size: Size(w, 820),
            textScale: s,
            items: [
              _n(
                  id: 'p',
                  title: '내 지원이 확정됐어요',
                  type: NotificationType.applicationConfirmed),
              _n(
                  id: 'm',
                  title: '새 지원자가 있습니다',
                  type: NotificationType.newApplication),
              _n(
                  id: 'm2',
                  title: '계약 서명이 완료됐습니다',
                  type: NotificationType.contractSigned,
                  daysAgo: 1),
            ]);
        expect(find.byType(TabBar), findsOneWidget);
        expect(t.takeException(), isNull,
            reason: '탭 라벨 + 미읽음 배지가 폭 $w · 배율 $s 에서 넘쳤다');
      });
    }
  }

  testWidgets('NTF-19 빈 상태도 320dp × 배율 2.0 에서 넘치지 않는다', (t) async {
    await _pump(t,
        items: const [], size: const Size(320, 640), textScale: 2.0);
    expect(find.text('알림이 없습니다'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('NTF-20 오류 상태도 320dp × 배율 2.0 에서 넘치지 않는다', (t) async {
    await _pump(t,
        error: true, items: const [], size: const Size(320, 640), textScale: 2.0);
    expect(find.text('알림을 불러오지 못했습니다'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  // ══════════════════════════════════════════════════════════════════
  // 6. 스크롤과 하단 — 마지막 알림에 닿을 수 있어야 한다
  // ══════════════════════════════════════════════════════════════════

  testWidgets('NTF-21 많은 알림 — 끝까지 스크롤해 마지막에 닿는다', (t) async {
    final many = [
      for (var i = 0; i < 24; i++)
        _n(id: 'n$i', title: '알림 $i', isRead: i.isEven, daysAgo: i ~/ 4),
    ];
    await _pump(t, items: many);
    expect(find.text('알림 0'), findsOneWidget);

    final sc = find.byType(Scrollable).last;
    await t.dragUntilVisible(
        find.text('알림 23'), sc, const Offset(0, -300),
        maxIteration: 60);
    await t.pumpAndSettle();
    expect(find.text('알림 23'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('NTF-22 하단 시스템 inset 48 — 마지막 알림이 가려지지 않는다', (t) async {
    final many = [
      for (var i = 0; i < 24; i++) _n(id: 'n$i', title: '알림 $i', daysAgo: i ~/ 4),
    ];
    await _pump(t, items: many, bottomInset: 48);

    final sc = find.byType(Scrollable).last;
    await t.dragUntilVisible(
        find.text('알림 23'), sc, const Offset(0, -300),
        maxIteration: 60);
    await t.pumpAndSettle();

    // 마지막 카드의 아래끝이 화면 바닥에서 inset 만큼 위에 있어야 한다.
    final box = t.getRect(find.text('알림 23'));
    final screenH = t.view.physicalSize.height / t.view.devicePixelRatio;
    expect(box.bottom, lessThanOrEqualTo(screenH - 48),
        reason: '마지막 알림이 홈 인디케이터 영역에 들어갔다');
    expect(t.takeException(), isNull);
  });

  // ══════════════════════════════════════════════════════════════════
  // 7. 문구 — 알림을 치우는 것과 업무가 끝나는 것은 다르다
  // ══════════════════════════════════════════════════════════════════

  testWidgets('NTF-23 목록 끝 안내 — 알림이 사라지는 것은 일이 끝난 것이 아니다', (t) async {
    await _pump(t, items: [
      for (var i = 0; i < 6; i++) _n(id: 'n$i', title: '알림 $i', daysAgo: i)
    ]);
    final sc = find.byType(Scrollable).last;
    await t.dragUntilVisible(
        find.textContaining('지난 기록은'), sc, const Offset(0, -300),
        maxIteration: 60);
    await t.pumpAndSettle();
    expect(find.textContaining('지난 기록은 지원·계약·일정·근태·급여 화면에서'),
        findsOneWidget);
    expect(t.takeException(), isNull);
  });
}
