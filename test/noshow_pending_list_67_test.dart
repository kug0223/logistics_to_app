// [.67 NS-PENDING-LIST] 알림과 무관한 열린 보류 입구 — 실패를 0건으로 보이지 않는가, 이름 조회 실패가 보류를 숨기지 않는가,
//   행을 누르면 같은 보류 키·발생·대상으로 처리 화면이 열리는가, 다른 관리자가 먼저 해소하면 다시 읽어 빠지는가.
//   서버·규칙(후보 RHOLD)은 c67/b67.js 가 에뮬레이터에서 따로 확인한다.
import 'dart:async';

import 'support/visible_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/screens/super_admin/noshow_pending_list_screen.dart';
import 'package:ALfit/screens/super_admin/noshow_pending_reads.dart';
import 'package:ALfit/screens/super_admin/noshow_pending_review_screen.dart';
import 'package:ALfit/screens/super_admin/system_settings_screen.dart';

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

class _SA extends UserProvider {
  @override
  UserModel? get currentUser => UserModel(uid: 'sa1', username: 'sa1', name: '운영', email: 'sa1@ALfit-system.com', role: UserRole.SUPER_ADMIN);
  @override
  bool get isUser => false;
  @override
  bool get isSubAdmin => false;
  @override
  bool get permissionsLoaded => true;
}

final _since = DateTime.utc(2026, 11, 3, 1, 0);
NoShowOpenPending _p(String id, String uid, {int occ = 0, DateTime? since}) =>
    NoShowOpenPending(id: id, uid: uid, occurrence: occ, reason: 'LEGACY_COUNT_DATES_MISMATCH', cause: 'trigger-on', since: since ?? _since);

/// 처리 화면이 여는 순간 부르는 조회 — 가짜(호출만 기록).
NoShowPendingReads _reads({Future<String?> Function(String)? label, List<Map<String, dynamic>>? calls}) => NoShowPendingReads(
      targetLabel: label,
      migrate: (data) async {
        calls?.add(Map<String, dynamic>.from(data));
        return {'dryRun': true, 'report': <Object>[], 'pending': <Object>[]};
      },
    );

Future<void> _pump(WidgetTester t, Widget home, {Size size = const Size(392, 844), double scale = 1.0}) async {
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(const SizedBox.shrink());
  await t.pumpWidget(ChangeNotifierProvider<UserProvider>(
    create: (_) => _SA(),
    child: MaterialApp(
      builder: (ctx, child) => MediaQuery(data: MediaQuery.of(ctx).copyWith(textScaler: TextScaler.linear(scale)), child: child!),
      home: home,
    ),
  ));
  for (var i = 0; i < 4; i++) {
    await t.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
    await initializeDateFormatting('ko_KR', null);
  });

  testWidgets('[F67-a] 조회 실패는 0건이 아니다 — 실패 안내·다시 시도, 회복하면 목록', (t) async {
    var fail = true;
    await _pump(t, NoShowPendingListScreen(reads: _reads(), loadOpen: () async {
      if (fail) throw Exception('permission-denied');
      return [_p('k1', 'w1')];
    }));
    expect(findVisibleText('보류 목록을 불러오지 못했습니다'), findsOneWidget);
    expect(findVisibleText('열린 보류가 없습니다'), findsNothing);
    fail = false;
    await t.tap(findVisibleText('다시 시도'));
    for (var i = 0; i < 4; i++) {
      await t.pump(const Duration(milliseconds: 50));
    }
    expect(findVisibleTextContaining('열린 보류 1건'), findsOneWidget);
  });

  testWidgets('[F68-a] 조회 중 로그아웃(화면 제거) — 늦게 온 응답이 예외·화면 갱신을 일으키지 않는다', (t) async {
    final late = Completer<List<NoShowOpenPending>>();
    var labelCalls = 0;
    await _pump(t, NoShowPendingListScreen(reads: _reads(label: (u) async { labelCalls++; return u; }), loadOpen: () => late.future));
    // 로그아웃: 앱은 스택 전체를 로그인 화면으로 바꾼다 — 여기서는 화면을 걷어낸다.
    await t.pumpWidget(const SizedBox.shrink());
    late.complete([_p('k1', 'w1')]);
    await t.pump(const Duration(milliseconds: 100));
    expect(t.takeException(), isNull);
    expect(labelCalls, 0, reason: '사라진 화면이 이전 계정의 이름 조회를 이어가지 않는다');
  });

  testWidgets('[F67-b] 비어 있음은 따로 말한다', (t) async {
    await _pump(t, NoShowPendingListScreen(reads: _reads(), loadOpen: () async => const []));
    expect(findVisibleText('열린 보류가 없습니다'), findsOneWidget);
  });

  testWidgets('[F67-c] 이름 조회 실패 — 보류는 숨기지 않고 uid 로 보인다', (t) async {
    await _pump(t, NoShowPendingListScreen(
      reads: _reads(label: (uid) async => uid == 'w1' ? throw Exception('offline') : '김근로 (@kim)'),
      loadOpen: () async => [_p('k1', 'w1'), _p('k2', 'w2', since: _since.add(const Duration(hours: 1)))],
    ));
    expect(findVisibleTextContaining('이름을 확인하지 못함 · w1'), findsOneWidget);
    expect(findVisibleText('김근로 (@kim)'), findsOneWidget);
    expect(findVisibleTextContaining('열린 보류 2건'), findsOneWidget);
  });

  testWidgets('[F67-d] 행 → 같은 보류 키·발생·대상의 처리 화면, 돌아오면 다시 읽어 해소된 건이 빠진다', (t) async {
    var loads = 0;
    final calls = <Map<String, dynamic>>[];
    await _pump(t, NoShowPendingListScreen(
      reads: _reads(label: (u) async => '근로자 $u', calls: calls),
      loadOpen: () async => ++loads == 1 ? [_p('w1__k', 'w1', occ: 2), _p('w2__k', 'w2')] : [_p('w2__k', 'w2')],
    ));
    await t.tap(findVisibleText('근로자 w1'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));
    final s = t.widget<NoShowPendingReviewScreen>(find.byType(NoShowPendingReviewScreen));
    expect((s.pendingId, s.occurrence, s.targetUid), ('w1__k', 2, 'w1'));
    expect(calls.first['uids'], ['w1'], reason: '처리 화면은 그 사용자의 지금 상태를 서버에서 다시 읽는다');
    Navigator.of(t.element(find.byType(NoShowPendingReviewScreen))).pop();
    for (var i = 0; i < 6; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    expect(loads, 2);
    expect(findVisibleText('근로자 w1'), findsNothing);
    expect(findVisibleText('근로자 w2'), findsOneWidget);
  });

  testWidgets('[F67-e] 100건 넘음 — 전체 수를 지어내지 않고 일부만 보인다고 말한다', (t) async {
    await _pump(t, NoShowPendingListScreen(reads: _reads(),
        loadOpen: () async => [for (var i = 0; i < kNoShowPendingListLimit + 1; i++) _p('k$i', 'w$i', since: _since.add(Duration(minutes: i)))]));
    expect(findVisibleTextContaining('열린 보류 100건 이상'), findsOneWidget);
  });

  testWidgets('[F67-f] 시스템 설정 — 처리할 업무 · 노쇼 원장 보류 입구', (t) async {
    await _pump(t, const SystemSettingsScreen());
    expect(findVisibleText('노쇼 원장 보류'), findsOneWidget);
    expect(findVisibleText('처리할 업무'), findsOneWidget);
  });

  for (final c in const [(Size(392, 844), 1.0), (Size(320, 640), 1.3), (Size(392, 844), 2.0)]) {
    testWidgets('[F67-g] 목록 넘침 없음 · 말줄임 없음 ${c.$1.width.toInt()}·${c.$2}', (t) async {
      await _pump(t, NoShowPendingListScreen(
        reads: _reads(label: (u) async => '아주 긴 이름의 합성 근로자 (@very_long_username_for_layout)'),
        loadOpen: () async => [_p('k1', 'w1'), _p('k2', 'w2')],
      ), size: c.$1, scale: c.$2);
      expect(t.takeException(), isNull);
      final name = t.widget<Text>(findVisibleText('아주 긴 이름의 합성 근로자 (@very_long_username_for_layout)').first);
      expect(name.maxLines, isNull);
      expect(name.overflow, isNot(TextOverflow.ellipsis));
    });
  }
}
