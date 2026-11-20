import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';

import 'package:ALfit/providers/notification_provider.dart';
import 'package:ALfit/widgets/common/notification_badge.dart';

/// [NOTIFICATION-BADGE.32] 공용 알림 배지 — 표시 정책(0 숨김·99+ 그대로), 화면 읽기 한 번,
///   큰 글자에서 종 아이콘을 덮지 않는다.
///   NB-1 0/1/두 자리/상한  NB-2 semantics: 값 한 번, 배지 숫자 따로 읽지 않음
///   NB-3 글자 2.0 — 대표 호출 두 곳(관리자 홈 header 버튼 모양 · AppBar IconButton): 배율 상한 없음, 커진 만큼 버튼 오른쪽 여유 폭  NB-4 탭 통과
class _FakeApp extends Fake with MockPlatformInterfaceMixin implements FirebaseAppPlatform {
  @override
  String get name => defaultFirebaseAppName;
  @override
  FirebaseOptions get options =>
      const FirebaseOptions(apiKey: 'k', appId: 'a', messagingSenderId: 's', projectId: 'p');
}

class _FakeCore extends FirebasePlatform with MockPlatformInterfaceMixin {
  @override
  FirebaseAppPlatform app([String name = defaultFirebaseAppName]) => _FakeApp();
  @override
  Future<FirebaseAppPlatform> initializeApp({String? name, FirebaseOptions? options}) async => _FakeApp();
  @override
  List<FirebaseAppPlatform> get apps => [_FakeApp()];
}

class _Unread extends NotificationProvider {
  _Unread(this.n);
  final int n;
  @override
  int get unreadCount => n;
}

/// 관리자 홈 `_headerBtn` 과 같은 모양(Material + InkWell + 8 여백 + 22 아이콘).
Widget _homeLikeButton() => Material(
      color: Colors.grey.shade100,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: () {},
        borderRadius: BorderRadius.circular(12),
        child: const Padding(
          padding: EdgeInsets.all(8),
          child: Icon(Icons.notifications_outlined, size: 22),
        ),
      ),
    );

Future<void> _pump(WidgetTester t, int n, {double scale = 1.0, bool appBar = false}) async {
  t.view.physicalSize = const Size(392, 800);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(ChangeNotifierProvider<NotificationProvider>(
    key: ValueKey('n$n-$scale-$appBar'),
    create: (_) => _Unread(n),
    child: MaterialApp(
      builder: (ctx, child) => MediaQuery(
          data: MediaQuery.of(ctx).copyWith(textScaler: TextScaler.linear(scale)), child: child!),
      home: appBar
          ? Scaffold(
              appBar: AppBar(actions: [
                NotificationBadge(
                  child: IconButton(
                      tooltip: '알림', icon: const Icon(Icons.notifications_outlined), onPressed: () {}),
                ),
              ]),
            )
          : Scaffold(body: Center(child: NotificationBadge(child: _homeLikeButton()))),
    ),
  ));
  await t.pump();
}

Rect _badgeRect(WidgetTester t) => t.getRect(find
    .descendant(of: find.byType(NotificationBadge), matching: find.byType(Container))
    .last);

void main() {
  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
  });

  testWidgets('NB-1 0 은 배지 없음, 1·12 는 그대로, 100 이상은 기존 99+', (t) async {
    await _pump(t, 0);
    expect(find.descendant(of: find.byType(NotificationBadge), matching: find.byType(Text)), findsNothing);
    for (final (n, shown) in const [(1, '1'), (12, '12'), (150, '99+')]) {
      await _pump(t, n);
      expect(find.text(shown), findsOneWidget, reason: '$n');
    }
  });

  testWidgets('NB-2 화면 읽기 — 버튼 이름은 호출부 그대로, 건수는 값으로 한 번', (t) async {
    final handle = t.ensureSemantics();
    await _pump(t, 3, appBar: true);
    final labels = <String>[];
    final values = <String>[];
    void walk(SemanticsNode n) {
      if (n.label.isNotEmpty) labels.add(n.label);
      if (n.value.isNotEmpty) values.add(n.value);
      if (n.tooltip.isNotEmpty) labels.add(n.tooltip);
      n.visitChildren((c) {
        walk(c);
        return true;
      });
    }
    walk(t.binding.pipelineOwner.semanticsOwner!.rootSemanticsNode!);
    expect(values.where((v) => v == '읽지 않은 알림 3건'), hasLength(1));
    expect(labels.where((l) => l == '3'), isEmpty, reason: '배지 숫자를 따로 읽지 않는다');
    expect(labels.where((l) => l == '알림'), hasLength(1), reason: '버튼 이름은 tooltip 한 번');
    handle.dispose();
  });

  testWidgets('NB-4 배지 자리를 눌러도 버튼이 눌린다(배지는 탭을 가로채지 않는다)', (t) async {
    var taps = 0;
    t.view.physicalSize = const Size(392, 800);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    await t.pumpWidget(ChangeNotifierProvider<NotificationProvider>(
      create: (_) => _Unread(3),
      child: MaterialApp(
        home: Scaffold(
          body: Center(
            child: NotificationBadge(
              child: IconButton(icon: const Icon(Icons.notifications_outlined), onPressed: () => taps++),
            ),
          ),
        ),
      ),
    ));
    await t.pump();
    final badge = _badgeRect(t);
    final button = t.getRect(find.byType(IconButton));
    final p = Offset((badge.left + button.right) / 2, (badge.top + badge.bottom) / 2);
    expect(button.contains(p), isTrue);
    await t.tapAt(p);
    expect(taps, 1);
  });

  for (final appBar in [false, true]) {
    testWidgets('NB-3 글자 2.0 · ${appBar ? 'AppBar IconButton' : '관리자 홈 header 버튼'} — 배지가 종 아이콘을 덮지 않는다',
        (t) async {
      double coveredOf(Rect icon, Rect badge) {
        final o = icon.intersect(badge);
        return (o.width <= 0 || o.height <= 0) ? 0.0 : o.width * o.height / (icon.width * icon.height);
      }

      await _pump(t, 3, scale: 1.0, appBar: appBar);
      final icon1 = t.getRect(find.byIcon(Icons.notifications_outlined));
      final base = _badgeRect(t);
      final host1 = t.getRect(find.descendant(of: find.byType(NotificationBadge), matching: find.byType(Stack)).first);
      final button1 = t.getRect(find.descendant(of: find.byType(NotificationBadge), matching: find.byType(Padding)).first);
      expect(host1.width, closeTo(button1.width, 0.01), reason: '1.0 에서는 여유 폭이 없다(배치 변화 0)');

      await _pump(t, 3, scale: 2.0, appBar: appBar);
      expect(t.takeException(), isNull);
      final icon = t.getRect(find.byIcon(Icons.notifications_outlined));
      final badge = _badgeRect(t);
      final host = t.getRect(find.descendant(of: find.byType(NotificationBadge), matching: find.byType(Stack)).first);
      // [.33] 상한 없음 — 배지는 사용자 글자 배율대로 커진다.
      expect(badge.height, greaterThan(base.height * 1.6), reason: '배지 숫자를 줄이지 않는다');
      // 자리: 위로는 예전 −4 그대로(AppBar 툴바 경계에서 잘림 방지).
      expect(badge.top, closeTo(host.top - 4, 0.01));
      // 커진 만큼은 버튼 오른쪽 여유 폭으로 — 아이콘 기준 배지 왼쪽 끝이 1.0 때와 같다.
      expect(badge.left - icon.right, closeTo(base.left - icon1.right, 1.0));
      // 위가 고정이라 아래로는 자란다 — 덮는 비율은 늘지만 아이콘의 왼쪽·아래 대부분이 보인다.
      //   (시험 글꼴 기준 홈 모양 1.0 0.19 → 2.0 0.34, 예전 상한 없던 배치는 2.0 에서 대부분 덮음)
      debugPrint('NB3 covered 1.0=${coveredOf(icon1, base).toStringAsFixed(2)} 2.0=${coveredOf(icon, badge).toStringAsFixed(2)}');
      expect(coveredOf(icon, badge), lessThan(0.4), reason: '아이콘 대부분이 보인다');
    });
  }
}
