// [.66] SA 알림 종·목록 — 배지가 불러온 범위·실패를 숨기지 않는가, 열 화면이 없는 알림이 무반응이 아닌가,
//   제목이 잘리지 않고 읽지 않음이 화면 읽기에 전해지는가.
//
// 근거(기기 c65d, 합성 SA 알림):
//   - 서버 미읽음 31건인데 종 배지는 '읽지 않은 알림 25건'(불러온 30건 안에서만 셈) — 더 보기 뒤에야 31.
//   - 알림 읽기가 거절돼 목록은 '불러오지 못했습니다'인데 홈 배지는 캐시 값 25건, 오류 화면 위에 '모두 읽음'.
//   - 앱이 모르는 type 알림을 누르면 아무 반응이 없었다(카드 본문은 2줄로 잘림).
import 'support/visible_text.dart';
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
import 'package:ALfit/screens/super_admin/noshow_pending_review_screen.dart';
import 'package:ALfit/utils/navigation_key.dart';
import 'package:ALfit/widgets/common/notification_badge.dart';

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

class _Notif extends NotificationProvider {
  _Notif({this.items = const [], this.count = 0, this.more = false, this.error = false});
  final List<NotificationModel> items;
  final int count;
  final bool more;
  final bool error;
  final List<String> markedRead = [];
  @override
  List<NotificationModel> get notifications => items;
  @override
  int get unreadCount => count;
  @override
  bool get hasUnread => count > 0;
  @override
  bool get hasMore => more;
  @override
  bool get hasError => error;
  @override
  bool get isLoading => false;
  @override
  bool get isLoadingMore => false;
  @override
  bool get loadMoreFailed => false;
  @override
  Future<void> markAsRead(String id) async => markedRead.add(id);
}

class _SA extends UserProvider {
  @override
  UserModel? get currentUser => UserModel(uid: 'sa', name: '합성 운영', username: 'e7sa', email: 'e7sa@ALfit-system.com', role: UserRole.SUPER_ADMIN);
  @override
  bool get isSubAdmin => false;
  @override
  bool get isUser => false;
  @override
  bool get permissionsLoaded => true;
}

Future<void> _badge(WidgetTester t, _Notif p, {double scale = 1.0}) async {
  t.view.physicalSize = const Size(392, 800);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(const SizedBox.shrink());
  await t.pumpWidget(ChangeNotifierProvider<NotificationProvider>.value(
    value: p,
    child: MaterialApp(
      builder: (ctx, child) => MediaQuery(data: MediaQuery.of(ctx).copyWith(textScaler: TextScaler.linear(scale)), child: child!),
      home: Scaffold(body: Center(child: NotificationBadge(child: IconButton(tooltip: '알림', icon: const Icon(Icons.notifications_outlined), onPressed: () {})))),
    ),
  ));
  await t.pump();
}

String? _badgeValue(WidgetTester t) {
  final w = t.widgetList<Semantics>(find.descendant(of: find.byType(NotificationBadge), matching: find.byType(Semantics)))
      .firstWhere((s) => s.properties.value != null);
  return w.properties.value;
}

NotificationModel _n(String id, NotificationType type, {String title = '제목', String body = '본문', bool isRead = false}) =>
    NotificationModel(id: id, userId: 'sa', type: type, title: title, body: body, isRead: isRead,
        createdAt: DateTime.now().subtract(const Duration(minutes: 5)), createdAtKnown: true);

Future<_Notif> _screen(WidgetTester t, _Notif p, {Size size = const Size(392, 844), double scale = 1.0}) async {
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(const SizedBox.shrink());
  await t.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider<NotificationProvider>.value(value: p),
      ChangeNotifierProvider<UserProvider>(create: (_) => _SA()),
    ],
    child: MaterialApp(
      navigatorKey: navigatorKey,
      builder: (ctx, child) => MediaQuery(data: MediaQuery.of(ctx).copyWith(textScaler: TextScaler.linear(scale)), child: child!),
      home: const NotificationScreen(),
    ),
  ));
  await t.pump();
  await t.pump(const Duration(milliseconds: 100));
  return p;
}

const _longTitle = '노쇼 원장 보류 — 건별 심사 필요 · 같은 사용자의 다른 보류가 함께 열려 있습니다';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
    await initializeDateFormatting('ko_KR', null);
  });

  testWidgets('[F66-a] 배지 — 더 오래된 알림이 남아 있으면 최소값(N+), 다 불러왔으면 정확한 수', (t) async {
    await _badge(t, _Notif(count: 25, more: true));
    expect(find.text('25+'), findsOneWidget);
    expect(_badgeValue(t), '읽지 않은 알림 25건 이상');
    await _badge(t, _Notif(count: 3));
    expect(find.text('3'), findsOneWidget);
    expect(_badgeValue(t), '읽지 않은 알림 3건');
    await _badge(t, _Notif(count: 120, more: true));
    expect(find.text('99+'), findsOneWidget);
    expect(_badgeValue(t), '읽지 않은 알림 99건 이상');
  });

  testWidgets('[F66-b] 배지 — 목록을 못 불러왔으면 남은 숫자 대신 실패를 알린다(0 이어도)', (t) async {
    await _badge(t, _Notif(count: 25, error: true));
    expect(find.text('25'), findsNothing);
    expect(find.text('!'), findsOneWidget);
    expect(_badgeValue(t), '알림을 불러오지 못했습니다');
    await _badge(t, _Notif(count: 0, error: true));
    expect(find.text('!'), findsOneWidget);
  });

  testWidgets('[F66-c] 배지 — N+ 는 늘어난 글자만큼 오른쪽으로 자란다(종 아이콘 대부분이 보인다)', (t) async {
    double covered() {
      final icon = t.getRect(find.byIcon(Icons.notifications_outlined));
      final badge = t.getRect(find.descendant(of: find.byType(NotificationBadge), matching: find.byType(Container)).last);
      final o = icon.intersect(badge);
      return (o.width <= 0 || o.height <= 0) ? 0.0 : o.width * o.height / (icon.width * icon.height);
    }
    for (final s in const [1.0, 2.0]) {
      await _badge(t, _Notif(count: 25, more: true), scale: s);
      expect(t.takeException(), isNull);
      expect(find.text('25+'), findsOneWidget);
      expect(covered(), lessThan(0.4), reason: '배율 $s');
    }
  });

  testWidgets('[F66-d] 오류 화면 위에는 모두 읽음을 두지 않는다', (t) async {
    await _screen(t, _Notif(items: [_n('a', NotificationType.noShowLedgerPending)], count: 1, error: true));
    expect(findVisibleText('알림을 불러오지 못했습니다'), findsOneWidget);
    expect(findVisibleText('모두 읽음'), findsNothing);
  });

  testWidgets('[F66-e] 열 화면이 없는 알림(모르는 type → other) — 무반응 대신 전문과 안내', (t) async {
    const long = '첫 문단입니다. 카드에서는 두 줄까지만 보입니다.\n\n둘째 문단: 끝까지 읽을 수 있어야 하는 내용입니다.\n\n셋째 문단: 마지막 줄.';
    final p = await _screen(t, _Notif(items: [_n('u', NotificationType.other, title: '모르는 종류 알림', body: long)], count: 1));
    await t.tap(findVisibleText('모르는 종류 알림'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 300));
    final inDialog = find.descendant(of: find.byType(Dialog), matching: findVisibleTextContaining('셋째 문단: 마지막 줄.'));
    expect(inDialog, findsOneWidget);
    expect(findVisibleTextContaining('따로 열 수 있는 화면이 없는 알림'), findsOneWidget);
    expect(p.markedRead, ['u']);
    await t.tap(find.text('확인'));
    await t.pump(const Duration(milliseconds: 300));
  });

  testWidgets('[F66-f] 시스템 공지 — 전문만(열 화면 없음 문구 없음)', (t) async {
    await _screen(t, _Notif(items: [_n('s', NotificationType.systemNotice, title: '점검 안내', body: '오늘 밤 점검합니다.')], count: 1));
    await t.tap(findVisibleText('점검 안내'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 300));
    expect(find.descendant(of: find.byType(Dialog), matching: findVisibleTextContaining('오늘 밤 점검합니다.')), findsOneWidget);
    expect(findVisibleTextContaining('따로 열 수 있는 화면이 없는 알림'), findsNothing);
    await t.tap(find.text('확인'));
    await t.pump(const Duration(milliseconds: 300));
  });

  testWidgets('[F66-h] 푸시로 들어온 보류 경보(data 값이 문자열) — 처리 화면이 같은 발생 번호로 열린다', (t) async {
    t.view.physicalSize = const Size(392, 844);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    await t.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<NotificationProvider>.value(value: _Notif()),
        ChangeNotifierProvider<UserProvider>(create: (_) => _SA()),
      ],
      child: MaterialApp(
        navigatorKey: navigatorKey,
        home: const NotificationScreen(autoDispatchPayload: {
          'type': 'noShowLedgerPending', 'notificationId': 'ledger_pending_k__o0',
          'pendingId': 'k', 'occurrence': '0', 'uid': 'w1',
        }),
      ),
    ));
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));
    final screen = t.widget<NoShowPendingReviewScreen>(find.byType(NoShowPendingReviewScreen));
    expect(screen.occurrence, 0);
    expect(screen.pendingId, 'k');
    expect(screen.targetUid, 'w1');
    await t.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('[F67-h] 푸시 보류 경보의 잘못된 값(occurrence 숫자 아님·pendingId 없음) — 예외 없이 열 수 없다고 말한다', (t) async {
    for (final bad in const [
      {'type': 'noShowLedgerPending', 'notificationId': 'x1', 'pendingId': 'k', 'occurrence': 'abc', 'uid': 'w1'},
      {'type': 'noShowLedgerPending', 'notificationId': 'x2', 'occurrence': '0', 'uid': 'w1'},
    ]) {
      t.view.physicalSize = const Size(392, 844);
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.reset);
      await t.pumpWidget(const SizedBox.shrink());
      await t.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<NotificationProvider>.value(value: _Notif()),
          ChangeNotifierProvider<UserProvider>(create: (_) => _SA()),
        ],
        child: MaterialApp(navigatorKey: navigatorKey, home: NotificationScreen(autoDispatchPayload: bad)),
      ));
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));
      expect(t.takeException(), isNull);
      expect(findVisibleText('알림에 보류 정보가 없어 열 수 없습니다.'), findsOneWidget, reason: '$bad');
    }
    await t.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('[F66-i] 푸시로 들어온 공지(제목·본문 없음) — 빈 안내 창을 띄우지 않는다', (t) async {
    t.view.physicalSize = const Size(392, 844);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    await t.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<NotificationProvider>.value(value: _Notif()),
        ChangeNotifierProvider<UserProvider>(create: (_) => _SA()),
      ],
      child: MaterialApp(navigatorKey: navigatorKey, home: const NotificationScreen(autoDispatchPayload: {'type': 'systemNotice', 'notificationId': 'n1'})),
    ));
    await t.pump();
    await t.pump(const Duration(milliseconds: 300));
    expect(find.byType(Dialog), findsNothing);
    expect(t.takeException(), isNull);
  });

  for (final c in const [(Size(392, 844), 1.0), (Size(320, 640), 1.3), (Size(392, 844), 2.0)]) {
    testWidgets('[F66-g] 카드 제목 말줄임 없음 · 읽지 않음 낭독 ${c.$1.width.toInt()}·${c.$2}', (t) async {
      final h = t.ensureSemantics();
      await _screen(t, _Notif(items: [_n('l', NotificationType.noShowLedgerPending, title: _longTitle, body: '사용자 x 의 노쇼 기록을 자동으로 판정할 수 없어 보류했습니다.')], count: 1),
          size: c.$1, scale: c.$2);
      expect(t.takeException(), isNull);
      final title = t.widget<Text>(findVisibleTextContaining('건별 심사 필요'));
      expect(title.maxLines, isNull);
      expect(title.overflow, isNot(TextOverflow.ellipsis));
      expect(find.bySemanticsLabel(RegExp('읽지 않음')), findsWidgets);
      h.dispose();
    });
  }
}
