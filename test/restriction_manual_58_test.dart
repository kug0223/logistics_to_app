// [.58] SA 수동·영구 제한 해제 — 별도 행동, 대상·해제할 것·남는 것, 읽을 수 없는 값.
//
// 서버(callableReleaseManualRestriction, A 묶음 00001-yex)는 base(수동·영구·기존) 성분만 지운다 —
//   노쇼 자동 제한·원장·블랙리스트는 그대로. 낡은 화면은 expectedBaseUntilMs 로 거절된다.
// 쓰기는 한 번도 호출하지 않는다 — 사유 창은 '취소'로 닫는다.
// ignore_for_file: depend_on_referenced_packages
import 'support/visible_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';

import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/screens/super_admin/all_users_reads.dart';
import 'package:ALfit/screens/super_admin/all_users_screen.dart';
import 'package:ALfit/utils/format_helper.dart';

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

class _Super extends UserProvider {
  @override
  UserModel? get currentUser => UserModel(
        uid: 'sa1',
        username: 'sa1',
        name: '운영자',
        email: 'sa@alfit.local',
        role: UserRole.SUPER_ADMIN,
        createdAt: DateTime(2026, 1, 1),
      );
  @override
  bool get isSuperAdmin => true;
  @override
  bool get isBusinessAdmin => false;
  @override
  bool get isSubAdmin => false;
  @override
  bool get isAdminMode => true;
  @override
  bool get permissionsLoaded => true;
}

Map<String, int> _ts(DateTime t) =>
    {'_seconds': t.millisecondsSinceEpoch ~/ 1000, '_nanoseconds': 0};
DateTime _sec(DateTime t) =>
    DateTime.fromMillisecondsSinceEpoch((t.millisecondsSinceEpoch ~/ 1000) * 1000);

final _now = DateTime.now();
final _auto = _sec(_now.add(const Duration(days: 1)));
final _manual = _sec(_now.add(const Duration(days: 30)));
// 서버 영구 경계(KST 9999-01-01)
final _perm = DateTime.utc(9998, 12, 31, 15);

Map<String, dynamic> _row({
  DateTime? auto,
  DateTime? base,
  String? baseSource,
  bool blacklisted = false,
  int noShow = 0,
}) {
  final eff = [auto, base].whereType<DateTime>().fold<DateTime?>(
      null, (a, b) => a == null || b.isAfter(a) ? b : a);
  return {
    'uid': 'w1',
    'username': 'worker01',
    'name': '박근로',
    'email': 'worker01@alfit.local',
    'role': 'USER',
    'createdAt': _ts(DateTime(2026, 1, 1)),
    'noShowCount': noShow,
    'recentNoShowCount': noShow,
    if (blacklisted) 'isBlacklisted': true,
    if (blacklisted) 'blacklistReason': '시험',
    if (eff != null) 'restrictedUntil': _ts(eff),
    if (eff != null) 'restrictionSource': eff == base ? baseSource : 'auto',
    'restrictionParts': {
      if (auto != null) 'auto': _ts(auto),
      if (base != null) 'base': _ts(base),
      if (base != null) 'baseSource': baseSource,
    },
  };
}

String _kst(DateTime t) => FormatHelper.formatKstDateTimeKorean(t);

Future<void> _openDetail(
  WidgetTester tester, {
  required Map<String, dynamic> row,
  Size size = const Size(392, 1600),
  double textScale = 1.0,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpWidget(
    ChangeNotifierProvider<UserProvider>(
      create: (_) => _Super(),
      child: MaterialApp(
        builder: (ctx, child) => MediaQuery(
          data: MediaQuery.of(ctx)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: AllUsersScreen(
            reads: AllUsersReads(allUsersRaw: () async => [row])),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 200));
  await tester.tap(findVisibleText('박근로').first);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

Finder get _sheetScroll => find
    .descendant(of: find.byType(BottomSheet), matching: find.byType(Scrollable))
    .first;

Future<void> _tapAction(WidgetTester tester, String label) async {
  final btn = findVisibleText(label);
  await tester.dragUntilVisible(btn, _sheetScroll, const Offset(0, -200));
  await tester.pump();
  await tester.tap(btn);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

Future<void> _cancel(WidgetTester tester) async {
  await tester.tap(findVisibleText('취소'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
  });

  testWidgets('[RM58-a] 수동만 — 수동 해제는 따로, 노쇼 리셋 버튼은 열지 않는다 · 창 내용 · 취소',
      (tester) async {
    await _openDetail(tester, row: _row(base: _manual, baseSource: 'manual'));
    expect(findVisibleTextContaining('관리자 수동 제한 ${_kst(_manual)}까지'), findsOneWidget);
    expect(findVisibleText('노쇼 제한 해제 (기록 초기화)'), findsNothing);
    await _tapAction(tester, '관리자 수동 제한 해제');

    expect(findVisibleText('관리자 수동 제한 해제'), findsOneWidget); // 창 제목
    expect(findVisibleTextContaining('박근로 · @worker01 · 지원자'), findsOneWidget);
    expect(findVisibleTextContaining('해제할 것: 관리자 수동 제한(${_kst(_manual)}까지)'),
        findsOneWidget);
    expect(findVisibleTextContaining('해제 뒤 바로 로그인·지원할 수 있어요.'), findsOneWidget);
    expect(findVisibleTextContaining('남는 것'), findsNothing);
    expect(findVisibleTextContaining('사유는 감사 기록에만 남고 이 사용자에게는 보이지 않아요.'),
        findsOneWidget);
    await _cancel(tester);
    expect(findVisibleTextContaining('해제할 것'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('[RM58-b] 자동+수동+블랙리스트 — 자동·블랙리스트가 남는다고 말한다', (tester) async {
    await _openDetail(tester,
        row: _row(auto: _auto, base: _manual, baseSource: 'manual', blacklisted: true, noShow: 3));
    // 두 행동이 따로 있다.
    expect(findVisibleText('노쇼 제한 해제 (기록 초기화)'), findsOneWidget);
    await _tapAction(tester, '관리자 수동 제한 해제');
    expect(
        findVisibleTextContaining(
            '남는 것: 노쇼 자동 제한(${_kst(_auto)}까지) — 이 버튼으로는 풀리지 않아요'),
        findsOneWidget);
    expect(findVisibleTextContaining('남는 것: 계정 이용 차단 — 이 버튼으로는 풀리지 않아요'),
        findsOneWidget);
    expect(findVisibleTextContaining('해제 뒤에도 로그인·지원이 제한돼요.'), findsOneWidget);
    expect(findVisibleTextContaining('바로 로그인'), findsNothing);
    await _cancel(tester);
  });

  testWidgets('[RM58-b2] 노쇼 리셋 창도 남는 블랙리스트를 말한다', (tester) async {
    await _openDetail(tester, row: _row(auto: _auto, blacklisted: true, noShow: 3));
    await _tapAction(tester, '노쇼 제한 해제 (기록 초기화)');
    expect(findVisibleTextContaining('남는 것: 계정 이용 차단 — 이 버튼으로는 풀리지 않아요'),
        findsOneWidget);
    expect(findVisibleTextContaining('해제 뒤에도 로그인·지원이 제한돼요.'), findsOneWidget);
    await _cancel(tester);
  });

  testWidgets('[RM58-c] 영구 — 이름이 영구 제한 해제, 만료처럼 말하지 않는다', (tester) async {
    await _openDetail(tester, row: _row(base: _perm, baseSource: 'permanent'));
    expect(findVisibleText('이용 제한(기한 없음)'), findsOneWidget); // 상태 카드 설명(시각 없음)
    expect(findVisibleTextContaining('이용 제한(기한 없음) 기한 없음'), findsNothing);
    await _tapAction(tester, '이용 제한(기한 없음) 해제');
    expect(findVisibleTextContaining('해제할 것: 이용 제한(기한 없음)\n'), findsOneWidget);
    await _cancel(tester);
  });

  testWidgets('[RM58-d] 제한 값을 읽지 못하면 정상이라 하지 않고 실행 버튼을 열지 않는다',
      (tester) async {
    await _openDetail(tester, row: {
      ..._row(),
      'restrictedUntil': {'unexpected': 1},
      'restrictionSource': 'manual',
    });
    expect(findVisibleText('제한 상태 확인 불가'), findsOneWidget);
    expect(findVisibleText('정상'), findsNothing);
    expect(findVisibleTextContaining('제한 해제'), findsNothing);
    expect(findVisibleText('노쇼 제한 해제 (기록 초기화)'), findsNothing);
  });

  testWidgets('[RM58-e] 성분 기록 없는 원장 이전 문서 — 서버와 같이 기존 제한으로 해석',
      (tester) async {
    await _openDetail(tester, row: {
      ..._row(),
      'restrictionParts': null,
      'restrictedUntil': _ts(_manual),
    });
    await _tapAction(tester, '기존 제한 해제');
    expect(findVisibleTextContaining('해제할 것: 기존 제한(${_kst(_manual)}까지)'),
        findsOneWidget);
    await _cancel(tester);
  });

  for (final c in const [
    (Size(392, 844), 1.0),
    (Size(320, 640), 1.3),
    (Size(392, 844), 2.0),
  ]) {
    testWidgets('[RM58-f] 해제 사유 창 넘침 없음 ${c.$1.width.toInt()}·${c.$2}',
        (tester) async {
      await _openDetail(tester,
          row: _row(auto: _auto, base: _manual, baseSource: 'manual', blacklisted: true, noShow: 3),
          size: c.$1,
          textScale: c.$2);
      await _tapAction(tester, '관리자 수동 제한 해제');
      expect(tester.takeException(), isNull);
      expect(findVisibleTextContaining('해제 뒤에도 로그인·지원이 제한돼요.'), findsOneWidget);
      await _cancel(tester);
    });
  }
}
