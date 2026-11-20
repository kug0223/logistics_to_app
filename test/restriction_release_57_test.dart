// [.57] SA 제재 해제 — 대상 상태·해제 효과·로그인 안내가 서버 사실과 맞는지 렌더로 잰다.
//
// 기기 결함(Pixel 5, 11-02): callableGetAllUsers 가 Timestamp 를 {_seconds,_nanoseconds} 맵으로 보내
//   제재 중인 근로자가 상세에서 '정상 · 이용 제한 없음'으로 보였고 해제 버튼이 없었다.
// 쓰기(callableResetPenalty)는 한 번도 호출하지 않는다 — 확인 창은 '취소'로 닫는다.
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
import 'package:ALfit/services/auth_service.dart';
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

// callable 응답 모양 그대로 — Timestamp 는 {_seconds, _nanoseconds}.
Map<String, int> _ts(DateTime t) =>
    {'_seconds': t.millisecondsSinceEpoch ~/ 1000, '_nanoseconds': 0};

final _now = DateTime.now();
final _auto = DateTime.fromMillisecondsSinceEpoch(
    (_now.add(const Duration(days: 1)).millisecondsSinceEpoch ~/ 1000) * 1000);
final _manual = DateTime.fromMillisecondsSinceEpoch(
    (_now.add(const Duration(days: 30)).millisecondsSinceEpoch ~/ 1000) * 1000);

Map<String, dynamic> _worker({bool withManual = false}) => {
      'uid': 'w1',
      'username': 'worker01',
      'name': '박근로',
      'email': 'worker01@alfit.local',
      'role': 'USER',
      'createdAt': _ts(DateTime(2026, 1, 1)),
      'noShowCount': 3,
      'recentNoShowCount': 3,
      'restrictedUntil': _ts(withManual ? _manual : _auto),
      'restrictionSource': withManual ? 'manual' : 'auto',
      'restrictionParts': {
        'auto': _ts(_auto),
        if (withManual) 'base': _ts(_manual),
        if (withManual) 'baseSource': 'manual',
      },
    };

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

Future<void> _openResetDialog(WidgetTester tester) async {
  final btn = findVisibleTextContaining('제재 해제 (노쇼 카운트 초기화)');
  // 작은 화면에서는 시트 아래쪽 버튼이 아직 지어지지 않았다 — 시트를 끌어 올린다.
  final sheetScroll = find
      .descendant(of: find.byType(BottomSheet), matching: find.byType(Scrollable))
      .first;
  await tester.dragUntilVisible(btn, sheetScroll, const Offset(0, -200));
  await tester.pump();
  await tester.tap(btn);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
  });

  testWidgets('[RR57-a] callable 시각 맵을 읽어 제재 중으로 보이고 해제 버튼이 있다',
      (tester) async {
    await _openDetail(tester, row: _worker());
    expect(findVisibleText('이용 제한 중'), findsOneWidget);
    expect(findVisibleTextContaining('노쇼 자동 제한 ${_kst(_auto)}까지'),
        findsOneWidget);
    expect(findVisibleTextContaining('이용 제한 없음'), findsNothing);
    expect(findVisibleTextContaining('제재 해제 (노쇼 카운트 초기화)'), findsOneWidget);
  });

  testWidgets('[RR57-b] 자동만 — 확인 창: 대상·풀리는 것·바로 이용 가능, 취소=쓰기 0',
      (tester) async {
    await _openDetail(tester, row: _worker());
    await _openResetDialog(tester);
    expect(findVisibleText('노쇼 제재 해제'), findsOneWidget);
    expect(findVisibleTextContaining('박근로'), findsWidgets);
    expect(findVisibleTextContaining('@worker01'), findsWidgets);
    expect(
        findVisibleTextContaining('풀리는 것: 노쇼 자동 제한(${_kst(_auto)}까지)'),
        findsOneWidget);
    expect(findVisibleTextContaining('노쇼 기록 초기화: 3회(최근 90일 3회) → 0회'),
        findsOneWidget);
    expect(findVisibleTextContaining('해제 뒤 바로 로그인·지원할 수 있습니다.'),
        findsOneWidget);
    expect(findVisibleTextContaining('남는 것'), findsNothing);

    await tester.tap(findVisibleText('취소'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(findVisibleText('노쇼 제재 해제'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('[RR57-c] 자동+수동 — 수동은 남고 이용 가능하다고 말하지 않는다',
      (tester) async {
    await _openDetail(tester, row: _worker(withManual: true));
    expect(findVisibleTextContaining('관리자 수동 제한 ${_kst(_manual)}까지'),
        findsOneWidget);
    await _openResetDialog(tester);
    expect(
        findVisibleTextContaining(
            '남는 것: 관리자 수동 제한(${_kst(_manual)}까지) — 이 버튼으로는 풀리지 않습니다'),
        findsOneWidget);
    expect(findVisibleTextContaining('해제 뒤에도 로그인·지원이 제한됩니다.'),
        findsOneWidget);
    expect(findVisibleTextContaining('바로 로그인'), findsNothing);
    expect(findVisibleTextContaining('즉시 이용 가능'), findsNothing);
    await tester.tap(findVisibleText('취소'));
    await tester.pump(const Duration(milliseconds: 400));
  });

  for (final c in const [
    (Size(392, 844), 1.0),
    (Size(320, 640), 1.3),
    (Size(392, 844), 2.0),
  ]) {
    testWidgets('[RR57-d] 확인 창 넘침 없음 ${c.$1.width.toInt()}·${c.$2}',
        (tester) async {
      await _openDetail(tester,
          row: _worker(withManual: true), size: c.$1, textScale: c.$2);
      expect(tester.takeException(), isNull);
      await _openResetDialog(tester);
      expect(tester.takeException(), isNull);
      expect(findVisibleTextContaining('이 버튼으로는 풀리지 않습니다'), findsOneWidget);
    });
  }

  testWidgets('[RR57-f] 블랙리스트 해제 창 — 남은 이용 제한이 있으면 로그인 가능이라고 하지 않는다',
      (tester) async {
    await _openDetail(tester, row: {..._worker(), 'isBlacklisted': true, 'blacklistReason': '시험'});
    final btn = findVisibleText('블랙리스트 해제');
    await tester.dragUntilVisible(btn.last,
        find.descendant(of: find.byType(BottomSheet), matching: find.byType(Scrollable)).first,
        const Offset(0, -200));
    await tester.tap(btn.last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(
        findVisibleTextContaining(
            '이용 제한(${_kst(_auto)}까지)은 이 버튼으로 풀리지 않아, 해제 뒤에도 로그인·지원이 제한됩니다.'),
        findsOneWidget);
    expect(findVisibleTextContaining('해제 후 로그인이 가능해집니다'), findsNothing);
    await tester.tap(findVisibleText('취소'));
    await tester.pump(const Duration(milliseconds: 400));
  });

  group('[RR57-e] 로그인 차단 안내 — 출처별', () {
    final until = DateTime.utc(2026, 12, 2, 1, 0);
    test('auto = 노쇼 문구', () {
      final m = AuthService.restrictionLoginMessage(until, 'auto');
      expect(m, startsWith('노쇼로 인해 ${_kst(until)}(한국시간)까지'));
    });
    test('manual = 관리자 조치, 노쇼라고 하지 않는다', () {
      final m = AuthService.restrictionLoginMessage(until, 'manual');
      expect(m, startsWith('관리자 조치로 ${_kst(until)}(한국시간)까지'));
      expect(m, isNot(contains('노쇼')));
    });
    test('영구(출처 permanent·없음) = 사유 단정 없음', () {
      for (final s in ['permanent', null]) {
        final m = AuthService.restrictionLoginMessage(DateTime.utc(9999, 1, 1), s);
        expect(m, contains('영구 제한'));
        expect(m, isNot(contains('노쇼')));
      }
    });
    test('[.58] 서버 영구 경계(KST 9999-01-01 = UTC 9998-12-31 15:00)는 출처가 없어도 영구', () {
      final m = AuthService.restrictionLoginMessage(DateTime.utc(9998, 12, 31, 15), null);
      expect(m, contains('영구 제한'));
      expect(m, isNot(contains('9998')));
    });
    // [.58] 출처 없음(원장 이전)도 노쇼라고 단정하지 않는다 — 서버 지원 거절 후보와 같은 원칙.
    test('legacy·unverified·출처 없음 = 사유 단정 없음', () {
      for (final s in ['legacy', 'unverified', null]) {
        final m = AuthService.restrictionLoginMessage(until, s);
        expect(m, startsWith('${_kst(until)}(한국시간)까지 이용이 제한됩니다.'));
        expect(m, isNot(contains('노쇼')));
      }
    });
  });
}
