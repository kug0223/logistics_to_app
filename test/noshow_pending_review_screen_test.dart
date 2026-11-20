import 'dart:async';
import 'dart:io';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';

import 'package:ALfit/models/core/notification_model.dart';
import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/providers/notification_provider.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/screens/common/notification_screen.dart';
import 'package:ALfit/screens/super_admin/noshow_pending_reads.dart';
import 'package:ALfit/screens/super_admin/noshow_pending_review_screen.dart';
import 'package:ALfit/utils/navigation_key.dart';

// [.56] 검토 화면 글자가 낱말 단위(TextLayout)로 바뀌어 보이는 글자로 찾는다.
import 'support/visible_text.dart';

// ═══════════════════════════════════════════════════════════════
// [NS-PENDING-DEST] 노쇼 원장 보류 처리 화면 — 실제 위젯, LOCAL 가짜 서버 응답.
//
//   NPR-A: 화면 상태(열린 건·해소된 건·같은 키 옛 발생·근거 부족·권한 없음·해소 없는 원인)
//   NPR-B: 해소 요청(중복 탭 1회·응답 불명확 → 같은 requestId 재전송·PENDING_CHANGED → 재조회)
//   NPR-C: 320·360·411dp 넘침(번들 NotoSansKR · 테스트 기본 폰트 둘 다)
//   NPR-D: 알림 목록 → 상세 → 뒤로(실제 NotificationScreen dispatcher, callable 은 pigeon 채널 가짜)
//   실제 DEV 해소 호출은 하지 않는다. Pixel 5 확인을 대신하지 않는다.
// ═══════════════════════════════════════════════════════════════

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

class _User extends UserProvider {
  _User(this.role);
  final UserRole role;
  @override
  UserModel? get currentUser => UserModel(uid: 'sa1', username: 'sa1', name: '운영', email: 'sa1@ALfit-system.com', role: role);
  @override
  bool get isUser => role == UserRole.USER;
  @override
  bool get isSubAdmin => false;
  @override
  bool get isBusinessAdmin => role == UserRole.BUSINESS_ADMIN;
  @override
  bool get permissionsLoaded => true;
}

class _Notif extends NotificationProvider {
  _Notif(this.items);
  final List<NotificationModel> items;
  final marked = <String>[];
  @override
  List<NotificationModel> get notifications => items;
  @override
  bool get isLoading => false;
  @override
  bool get hasError => false;
  @override
  bool get hasMore => false;
  @override
  bool get isLoadingMore => false;
  @override
  bool get loadMoreFailed => false;
  @override
  Future<void> markAsRead(String id) async => marked.add(id);
}

const _key = 'w1__app9__20261020__cancel';
final _at = DateTime.utc(2026, 10, 21, 1, 0).millisecondsSinceEpoch; // KST 10:00

Map<String, dynamic> _pendingRow({String status = 'OPEN', int occurrence = 0, String? manualWhy}) => {
      'id': _key, 'status': status, 'occurrence': occurrence, 'reason': 'LEGACY_COUNT_DATES_MISMATCH', 'cause': 'cancel',
      'applicationId': 'app9', 'day': '20261020', 'atMs': _at, 'firstSeenAtMs': _at + 600000,
      'resolvedAtMs': status == 'RESOLVED' ? _at + 3600000 : null, 'resolvedBy': status == 'RESOLVED' ? 'resolution' : null,
      'manualInvestigation': manualWhy == null ? null : {'resolution': 'COUNT_FROM_DATES', 'why': manualWhy, 'atMs': _at},
    };

Map<String, dynamic> _resp({String plan = 'SKIPPED', String? planReason = 'LEGACY_COUNT_DATES_MISMATCH', List<Map<String, dynamic>>? pending, Map<String, dynamic>? report}) => {
      'dryRun': true, 'count': 1,
      'report': [report ?? {'uid': 'w1', 'status': plan, if (planReason != null) 'reason': planReason, 'before': {'count': 3, 'datesMs': [1, 2], 'recent': 3, 'restriction': null}}],
      'pending': pending ?? [_pendingRow()],
    };

/// 가짜 서버 — 호출을 기록하고, 차례로 준비된 응답(또는 예외·대기)을 돌려준다.
class _Server {
  _Server(this.script);
  final List<Object> script; // Map 응답 | Exception | Completer<Map>
  final calls = <Map<String, dynamic>>[];
  late final reads = NoShowPendingReads(migrate: (data) async {
    calls.add(Map<String, dynamic>.from(data));
    final next = script.isEmpty ? _resp() : script.removeAt(0);
    if (next is Completer<Map<String, dynamic>>) return next.future;
    if (next is Exception) throw next;
    return next as Map<String, dynamic>;
  });
}

Future<void> _pump(WidgetTester t, _Server s, {UserRole role = UserRole.SUPER_ADMIN, int? occurrence = 0, double width = 411, bool bundledFont = true}) async {
  t.view.physicalSize = Size(width, 1400);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(ChangeNotifierProvider<UserProvider>.value(
    value: _User(role),
    child: MaterialApp(
      navigatorKey: navigatorKey,
      theme: bundledFont ? ThemeData(fontFamily: 'NotoSansKR') : null,
      home: NoShowPendingReviewScreen(pendingId: _key, occurrence: occurrence, targetUid: 'w1', reads: s.reads),
    ),
  ));
  await t.pump();
  await t.pump(const Duration(milliseconds: 50));
}

Future<void> _selectAndType(WidgetTester t, String label) async {
  await t.tap(findVisibleText(label));
  await t.pump();
  await t.enterText(find.byType(TextField), '날짜 원본 확인');
  await t.pump();
}

/// 확인 단계 열기 — 서버 미리보기(dryRun)를 한 번 부른다.
Future<void> _openConfirm(WidgetTester t) async {
  await t.ensureVisible(findVisibleText('함께 처리될 보류 확인'));
  await t.tap(findVisibleText('함께 처리될 보류 확인'));
  await t.pump();
  await t.pump(const Duration(milliseconds: 50));
}

/// 확인 단계에서 제출.
Future<void> _commitTap(WidgetTester t, {String label = '이대로 해소'}) async {
  await t.ensureVisible(findVisibleText(label));
  await t.tap(findVisibleText(label));
  await t.pump();
}

Map<String, dynamic> _preview(String status, {List<Map<String, dynamic>>? pending, String? why}) => _resp(
      report: {'uid': 'w1', 'status': status, if (why != null) 'why': why, 'before': {'count': 3, 'datesMs': [1, 2], 'recent': 3}},
      pending: pending,
    );

final _key2 = 'w1__app8__20261021__trigger-on';
Map<String, dynamic> _second({String reason = 'LEGACY_RESET_DATES_REMAIN', String? manualWhy}) => {
      ..._pendingRow(manualWhy: manualWhy), 'id': _key2, 'cause': 'trigger-on', 'reason': reason, 'applicationId': 'app8', 'day': '20261021',
      'atMs': _at + 86400000,
    };

void main() {
  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
    await initializeDateFormatting('ko_KR', null);
    for (final f in ['assets/fonts/NotoSansKR-Regular.ttf', 'assets/fonts/NotoSansKR-Bold.ttf']) {
      final file = File(f);
      if (!file.existsSync()) fail('번들 폰트 없음: $f');
      final loader = FontLoader('NotoSansKR')..addFont(file.readAsBytes().then((b) => ByteData.view(b.buffer)));
      await loader.load();
    }
  });

  group('NPR-A 화면 상태', () {
    testWidgets('NPR-A1 열린 발생 — 근거가 보이고, 해소는 기본 선택 없이 잠겨 있다', (t) async {
      final s = _Server([_resp()]);
      await _pump(t, s);
      expect(s.calls.single, {'uids': ['w1'], 'dryRun': true, 'includePending': true}, reason: '열 때 서버에서 다시 읽는다');
      expect(findVisibleText('열린 보류 — 발생 0'), findsOneWidget);
      expect(findVisibleText('기존 노쇼 횟수와 날짜 수가 맞지 않습니다'), findsOneWidget);
      expect(findVisibleText('늦은 확정 취소의 벌점'), findsOneWidget);
      expect(findVisibleText('2026.10.20'), findsOneWidget);
      expect(findVisibleText('2026년 10월 21일 오전 10시'), findsOneWidget, reason: '보류 시작 = KST');
      expect(findVisibleText('횟수 3 · 날짜 2개 — 1개 차이 · 최근 90일 3'), findsOneWidget);
      expect(findVisibleText('날짜가 사실'), findsOneWidget);
      expect(findVisibleText('리셋이 사실'), findsOneWidget);
      expect(findVisibleText('최근 90일 값이 낡음'), findsNothing, reason: '이 원인에 쓸 수 없는 해소는 보이지 않는다');
      final radios = t.widgetList<RadioListTile<String>>(find.byType(RadioListTile<String>));
      final group = t.widget<RadioGroup<String>>(find.byType(RadioGroup<String>));
      expect(radios.length, 2);
      expect(group.groupValue, isNull, reason: '기본 선택 금지');
      final btn = t.widget<ElevatedButton>(find.ancestor(of: findVisibleText('함께 처리될 보류 확인'), matching: find.byType(ElevatedButton)));
      expect(btn.onPressed, isNull, reason: '선택·사유 전에는 누를 수 없다');
    });

    testWidgets('NPR-A2 이미 해소된 발생 — 그 사실만 보이고 변경 동작이 없다', (t) async {
      final s = _Server([_resp(plan: 'ALREADY', planReason: null, pending: [_pendingRow(status: 'RESOLVED', occurrence: 0)])]);
      await _pump(t, s);
      expect(findVisibleTextContaining('이미 해소된 보류입니다'), findsOneWidget);
      expect(findVisibleText('함께 처리될 보류 확인'), findsNothing);
      expect(find.byType(RadioListTile<String>), findsNothing);
    });

    testWidgets('NPR-A3 같은 키 옛 발생(__o0) — 새 발생(o1)이 열려 있어도 해소를 열지 않는다', (t) async {
      final s = _Server([_resp(pending: [_pendingRow(status: 'OPEN', occurrence: 1)])]);
      await _pump(t, s, occurrence: 0);
      expect(findVisibleText('이 알림은 이전 발생(0)입니다. 현재는 발생 1 · 열림'), findsOneWidget);
      expect(findVisibleText('함께 처리될 보류 확인'), findsNothing);
      expect(find.byType(RadioListTile<String>), findsNothing);
    });

    testWidgets('NPR-A3b 이 발생이 해소됨(닫힌 문서 번호 = 발생+1) — 해소됨으로 보이고, +2 부터는 다른 발생', (t) async {
      final s = _Server([_resp(plan: 'ALREADY', planReason: null, pending: [_pendingRow(status: 'RESOLVED', occurrence: 1)])]);
      await _pump(t, s, occurrence: 0);
      expect(findVisibleTextContaining('이미 해소된 보류입니다'), findsOneWidget);
      expect(findVisibleTextContaining('이전 발생'), findsNothing);
    });

    testWidgets('NPR-A3c 대조 — 닫힌 문서 번호가 발생+2 면 그 뒤 다시 열렸다 닫힌 다른 발생이다', (t) async {
      final s = _Server([_resp(plan: 'ALREADY', planReason: null, pending: [_pendingRow(status: 'RESOLVED', occurrence: 2)])]);
      await _pump(t, s, occurrence: 0);
      expect(findVisibleTextContaining('이전 발생(0)'), findsOneWidget);
    });

    testWidgets('NPR-A4 대상 없음 — 찾을 수 없다고 말하고 변경 동작이 없다', (t) async {
      final s = _Server([_resp(pending: [])]);
      await _pump(t, s);
      expect(findVisibleText('이 보류를 찾을 수 없습니다'), findsOneWidget);
      expect(findVisibleText('함께 처리될 보류 확인'), findsNothing);
    });

    testWidgets('NPR-A5 권한 없는 계정(일반 관리자·근로자) — 서버를 부르지 않고 근거를 보이지 않는다', (t) async {
      for (final role in [UserRole.BUSINESS_ADMIN, UserRole.USER]) {
        final s = _Server([_resp()]);
        await _pump(t, s, role: role);
        expect(s.calls, isEmpty, reason: '$role');
        expect(findVisibleText('슈퍼관리자만 볼 수 있습니다.'), findsOneWidget);
        expect(findVisibleTextContaining('횟수'), findsNothing);
      }
    });

    testWidgets('NPR-A6 서버가 권한 거절 — 근거 대신 권한 안내', (t) async {
      final s = _Server([FirebaseFunctionsException(code: 'permission-denied', message: '슈퍼어드민만 사용 가능합니다.')]);
      await _pump(t, s);
      expect(findVisibleText('슈퍼관리자만 볼 수 있습니다.'), findsOneWidget);
    });

    testWidgets('NPR-A7 조회 실패 — 없음으로 바꾸지 않고 다시 시도', (t) async {
      final s = _Server([FirebaseFunctionsException(code: 'unavailable', message: 'x'), _resp()]);
      await _pump(t, s);
      expect(findVisibleText('보류 상태를 확인하지 못했어요.'), findsOneWidget);
      await t.tap(findVisibleText('다시 시도'));
      await t.pump(); await t.pump(const Duration(milliseconds: 50));
      expect(findVisibleText('열린 보류 — 발생 0'), findsOneWidget);
      expect(s.calls.length, 2);
    });

    testWidgets('NPR-A8 앱에서 고를 해소가 없는 원인 — 추측 해소를 내놓지 않는다', (t) async {
      final s = _Server([_resp(planReason: 'MIGRATION_EQUALITY_FAILED')]);
      await _pump(t, s);
      expect(findVisibleText('이 원인에 앱에서 고를 수 있는 해소가 없습니다. 수동 조사가 필요합니다.'), findsOneWidget);
      expect(find.byType(RadioListTile<String>), findsNothing);
    });

    testWidgets('NPR-A9 링크에 발생 번호가 없다 — 서버를 부르지 않는다', (t) async {
      final s = _Server([_resp()]);
      await _pump(t, s, occurrence: null);
      expect(findVisibleText('알림에 보류 정보가 없어 열 수 없습니다.'), findsOneWidget);
      expect(s.calls, isEmpty);
    });
  });

  group('NPR-B 해소 요청(확인 단계 → 제출)', () {
    testWidgets('NPR-B1 한 건 — 확인 단계가 서버 미리보기로 예상 결과를 보이고, 본 집합 그대로 제출한다', (t) async {
      // 실제 서버처럼: 해소는 occurrence 를 +1 하고(srvNsResolvePending), 응답 report.before 는 해소 '전' 값이다.
      final s = _Server([
        _resp(), _preview('MIGRATED'),
        _resp(report: {'uid': 'w1', 'status': 'MIGRATED', 'before': {'count': 3, 'datesMs': [1, 2], 'recent': 3}}, pending: [_pendingRow(status: 'RESOLVED', occurrence: 1)]),
        _resp(report: {'uid': 'w1', 'status': 'ALREADY', 'before': {'count': 2, 'datesMs': [1, 2], 'recent': 2}}, pending: [_pendingRow(status: 'RESOLVED', occurrence: 1)]),
      ]);
      await _pump(t, s);
      await _selectAndType(t, '날짜가 사실');
      await _openConfirm(t);
      final pv = s.calls[1];
      expect(pv['dryRun'], true, reason: '확인 단계는 쓰지 않는다');
      expect(pv['expectedOpenPending'], [{'id': _key, 'occurrence': 0}]);
      expect(findVisibleText('해소 확인 — 「날짜가 사실」로 아래 1건을 함께 처리합니다'), findsOneWidget);
      expect(findVisibleText('이 알림의 보류 · 발생 0'), findsOneWidget);
      expect(findVisibleText(_key), findsOneWidget);
      expect(findVisibleText('닫힘 — 원장으로 옮겨 해소'), findsOneWidget);
      await _commitTap(t);
      await t.pump(const Duration(milliseconds: 50));
      final c = s.calls[2];
      expect(c['dryRun'], false);
      expect(c['expectedOpenPending'], pv['expectedOpenPending'], reason: '확인한 집합 그대로');
      expect(c['requestId'], pv['requestId'], reason: '한 결정 = 한 requestId');
      expect(RegExp(r'^nsp-[0-9a-f]{24}$').hasMatch(c['requestId'] as String), true);
      expect(c.containsKey('expectedPending'), false, reason: '단건 확인은 집합 확인으로 대체됐다');
      expect(findVisibleText('해소했습니다. 이 보류는 닫혔습니다.'), findsOneWidget);
      // 닫힌 문서의 번호가 알림 발생 + 1 이면 닫힌 것은 이 발생이다 — '이전 발생' 이라고 말하지 않는다.
      expect(findVisibleTextContaining('이미 해소된 보류입니다'), findsOneWidget);
      expect(findVisibleTextContaining('이전 발생'), findsNothing);
      // '지금 사용자 값'은 해소 뒤 다시 읽은 값(해소 응답의 before 가 아니다).
      expect(s.calls[3], {'uids': ['w1'], 'dryRun': true, 'includePending': true}, reason: '해소 뒤 쓰지 않는 조회로 다시 읽는다');
      expect(findVisibleText('횟수 2 · 날짜 2개 · 최근 90일 2'), findsOneWidget);
      expect(findVisibleTextContaining('최근 90일 3'), findsNothing);
    });

    testWidgets('NPR-B10 해소 뒤 다시 읽기 실패 — 해소 전 값을 지금 값으로 두지 않는다', (t) async {
      final s = _Server([
        _resp(), _preview('MIGRATED'),
        _resp(report: {'uid': 'w1', 'status': 'MIGRATED', 'before': {'count': 3, 'datesMs': [1, 2], 'recent': 3}}, pending: [_pendingRow(status: 'RESOLVED', occurrence: 1)]),
        FirebaseFunctionsException(code: 'unavailable', message: 'x'),
      ]);
      await _pump(t, s);
      await _selectAndType(t, '날짜가 사실');
      await _openConfirm(t);
      await _commitTap(t);
      await t.pump(const Duration(milliseconds: 50));
      expect(findVisibleText('해소했습니다. 이 보류는 닫혔습니다.'), findsOneWidget);
      expect(findVisibleText('확인하지 못함'), findsOneWidget);
      expect(findVisibleTextContaining('최근 90일 3'), findsNothing);
    });

    testWidgets('NPR-B2 두 건 — 함께 처리될 다른 보류의 id·원인·시작 시각·예상 결과를 모두 보이고 두 건 집합을 보낸다', (t) async {
      final both = [_pendingRow(), _second()];
      final s = _Server([_resp(pending: both), _preview('MIGRATED', pending: both),
        _resp(report: {'uid': 'w1', 'status': 'MIGRATED'}, pending: [_pendingRow(status: 'RESOLVED'), {..._second(), 'status': 'RESOLVED'}])]);
      await _pump(t, s);
      expect(findVisibleText('열린 보류 2건 — 해소는 사용자 단위라 모두 함께 처리됩니다(확인 단계에서 전부 보여 줍니다)'), findsOneWidget);
      await _selectAndType(t, '날짜가 사실');
      await _openConfirm(t);
      expect(findVisibleText('해소 확인 — 「날짜가 사실」로 아래 2건을 함께 처리합니다'), findsOneWidget);
      expect(findVisibleText('함께 처리될 다른 보류 · 발생 0'), findsOneWidget);
      expect(findVisibleText(_key2), findsOneWidget);
      expect(findVisibleText('리셋된 횟수인데 이전 날짜가 남아 있습니다'), findsOneWidget);
      expect(findVisibleText('근태 노쇼 처리의 벌점'), findsOneWidget);
      expect(findVisibleText('2026년 10월 22일 오전 10시'), findsOneWidget, reason: '두 번째 보류의 시작 시각');
      expect(findVisibleText('닫힘 — 원장으로 옮겨 해소'), findsNWidgets(2));
      await _commitTap(t);
      await t.pump(const Duration(milliseconds: 50));
      expect(s.calls[2]['expectedOpenPending'], [{'id': _key, 'occurrence': 0}, {'id': _key2, 'occurrence': 0}]);
      expect(findVisibleText('해소했습니다. 확인한 보류 2건이 모두 닫혔습니다.'), findsOneWidget);
    });

    testWidgets('NPR-B3 원인이 다른 두 건 — 한 해소로 다룰 수 없어 해소 버튼이 없다', (t) async {
      final s = _Server([_resp(pending: [_pendingRow(), _second(reason: 'LEGACY_RECENT_WITHOUT_DATES')])]);
      await _pump(t, s);
      expect(findVisibleText('원인이 다른 보류가 섞여 있어 한 해소로 처리할 수 없습니다. 수동 조사가 필요합니다.'), findsOneWidget);
      expect(find.byType(RadioListTile<String>), findsNothing);
      expect(findVisibleText('함께 처리될 보류 확인'), findsNothing);
    });

    testWidgets('NPR-B4 근거 부족(수동 조사 중) 보류가 섞임 — 해소 버튼이 없다', (t) async {
      final s = _Server([_resp(pending: [_pendingRow(), _second(manualWhy: '원본과 맞지 않는 날짜 1개')])]);
      await _pump(t, s);
      expect(findVisibleText('근거 부족으로 수동 조사 중인 보류가 있어 앱에서 해소하지 않습니다.'), findsOneWidget);
      expect(findVisibleText('함께 처리될 보류 확인'), findsNothing);
    });

    testWidgets('NPR-B5 미리보기가 근거 부족 — 바꾸지 않음을 보이고 제출 버튼이 없다', (t) async {
      final s = _Server([_resp(), _preview('EVIDENCE_INSUFFICIENT', why: '원본과 맞지 않는 날짜 1개')]);
      await _pump(t, s);
      await _selectAndType(t, '날짜가 사실');
      await _openConfirm(t);
      expect(findVisibleText('바꾸지 않음 — 근거 부족'), findsOneWidget);
      expect(findVisibleText('서버 확인: 원본과 맞지 않는 날짜 1개'), findsOneWidget);
      expect(findVisibleText('이대로 해소'), findsNothing);
      expect(s.calls.length, 2);
    });

    testWidgets('NPR-B6 확인 뒤 집합이 바뀜(PENDING_CHANGED) — 적용하지 않고 다시 읽는다', (t) async {
      final s = _Server([
        _resp(), _preview('MIGRATED'),
        FirebaseFunctionsException(code: 'failed-precondition', message: '열린 보류가 그 사이 바뀌었습니다.',
            details: {'code': 'PENDING_CHANGED', 'current': [{'id': _key, 'occurrence': 0}, {'id': _key2, 'occurrence': 0}]}),
        _resp(pending: [_pendingRow(), _second()]),
      ]);
      await _pump(t, s);
      await _selectAndType(t, '날짜가 사실');
      await _openConfirm(t);
      await _commitTap(t);
      await t.pump(); await t.pump(const Duration(milliseconds: 50));
      expect(s.calls.length, 4, reason: '거절 뒤 재조회');
      expect(s.calls[3]['dryRun'], true);
      expect(s.calls[3].containsKey('resolution'), false);
      expect(findVisibleText('확인한 뒤 열린 보류가 바뀌어 해소하지 않았습니다. 현재 상태를 다시 불러왔습니다.'), findsOneWidget);
      expect(findVisibleText('열린 보류 2건 — 해소는 사용자 단위라 모두 함께 처리됩니다(확인 단계에서 전부 보여 줍니다)'), findsOneWidget);
      expect(findVisibleText('이대로 해소'), findsNothing, reason: '새 집합은 다시 확인해야 한다');
    });

    testWidgets('NPR-B7 중복 탭 — 제출 대기 중 두 번 눌러도 1회', (t) async {
      final gate = Completer<Map<String, dynamic>>();
      final s = _Server([_resp(), _preview('MIGRATED'), gate]);
      await _pump(t, s);
      await _selectAndType(t, '날짜가 사실');
      await _openConfirm(t);
      await _commitTap(t);
      expect(findVisibleText('요청 중…'), findsOneWidget);
      await t.tap(findVisibleText('요청 중…'), warnIfMissed: false);
      await t.pump();
      expect(s.calls.length, 3, reason: '조회 1 + 미리보기 1 + 제출 1');
      gate.complete(_resp(report: {'uid': 'w1', 'status': 'MIGRATED'}, pending: [_pendingRow(status: 'RESOLVED')]));
      await t.pump(); await t.pump(const Duration(milliseconds: 50));
      expect(findVisibleText('해소했습니다. 이 보류는 닫혔습니다.'), findsOneWidget);
    });

    testWidgets('NPR-B8 응답 불명확 — 입력 잠금, 같은 requestId·같은 집합으로만 재전송(REPLAY)', (t) async {
      final s = _Server([
        _resp(), _preview('MIGRATED'),
        FirebaseFunctionsException(code: 'deadline-exceeded', message: 'timeout'),
        _resp(report: {'uid': 'w1', 'status': 'REPLAY', 'result': 'RESOLVED', 'resolution': 'COUNT_FROM_DATES'}, pending: [_pendingRow(status: 'RESOLVED')]),
      ]);
      await _pump(t, s);
      await _selectAndType(t, '날짜가 사실');
      await _openConfirm(t);
      await _commitTap(t);
      await t.pump(const Duration(milliseconds: 50));
      expect(findVisibleText('같은 요청으로 결과 확인'), findsOneWidget);
      expect(t.widget<OutlinedButton>(find.ancestor(of: findVisibleText('다시 고르기'), matching: find.byType(OutlinedButton))).onPressed, isNull, reason: '결과를 모르는 동안 결정을 바꾸지 않는다');
      await _commitTap(t, label: '같은 요청으로 결과 확인');
      await t.pump(const Duration(milliseconds: 50));
      expect(s.calls.length, 5, reason: '재전송 1회 + 해소 뒤 다시 읽기 1회');
      expect(s.calls[4]['dryRun'], true);
      expect(s.calls[3]['requestId'], s.calls[2]['requestId']);
      expect(s.calls[3]['expectedOpenPending'], s.calls[2]['expectedOpenPending']);
      expect(s.calls[3]['resolution'], s.calls[2]['resolution']);
      expect(findVisibleText('해소했습니다. 이 보류는 닫혔습니다.'), findsOneWidget);
    });

    testWidgets('NPR-B9 확인 뒤 선택을 바꾸면 확인이 버려지고, 다시 고르기는 서버를 부르지 않는다', (t) async {
      final s = _Server([_resp(), _preview('MIGRATED')]);
      await _pump(t, s);
      await _selectAndType(t, '날짜가 사실');
      await _openConfirm(t);
      expect(findVisibleText('이대로 해소'), findsOneWidget);
      await _commitTap(t, label: '다시 고르기');
      await t.pump();
      expect(findVisibleText('이대로 해소'), findsNothing);
      expect(findVisibleText('함께 처리될 보류 확인'), findsOneWidget);
      expect(s.calls.length, 2);
    });
  });

  group('NPR-C 폭', () {
    for (final w in [320.0, 360.0, 411.0]) {
      for (final font in [true, false]) {
        testWidgets('NPR-C ${w.toInt()}dp ${font ? 'NotoSansKR' : '테스트 폰트(보수적)'} — 열린 건·옛 발생·근거 부족', (t) async {
          for (final s in [
            _Server([_resp()]),
            _Server([_resp(pending: [_pendingRow(occurrence: 1)])]),
            _Server([_resp(pending: [_pendingRow(manualWhy: '원본과 맞지 않는 날짜 1개(근태·취소·apply 어느 것과도 하나로 대응되지 않음)')])]),
          ]) {
            await _pump(t, s, width: w, bundledFont: font);
            expect(t.takeException(), isNull, reason: '넘침 없음');
          }
        });
      }
    }
  });

  group('NPR-D 알림 목록 → 상세 → 뒤로', () {
    testWidgets('NPR-D1 슈퍼관리자가 보류 경보를 누르면 그 발생의 처리 화면, 뒤로 가면 목록', (t) async {
      t.view.physicalSize = const Size(360, 780);
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.reset);
      const ch = 'dev.flutter.pigeon.cloud_functions_platform_interface.CloudFunctionsHostApi.call';
      final seen = <Map>[];
      t.binding.defaultBinaryMessenger.setMockMessageHandler(ch, (msg) async {
        final args = (const StandardMessageCodec().decodeMessage(msg) as List).first as Map;
        seen.add({'name': args['functionName'], 'params': args['parameters']});
        return const StandardMessageCodec().encodeMessage(<Object?>[_resp()]);
      });
      addTearDown(() => t.binding.defaultBinaryMessenger.setMockMessageHandler(ch, null));
      final notif = _Notif([
        NotificationModel(id: 'n1', userId: 'sa1', type: NotificationType.noShowLedgerPending, title: '노쇼 원장 보류 — 건별 심사 필요',
            body: '사용자 w1의 노쇼 기록을 자동으로 판정할 수 없어 보류했습니다.', isRead: false,
            createdAt: DateTime.now().subtract(const Duration(minutes: 3)),
            data: {'pendingId': _key, 'occurrence': 0, 'uid': 'w1', 'reason': 'LEGACY_COUNT_DATES_MISMATCH'}),
      ]);
      await t.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<NotificationProvider>.value(value: notif),
          ChangeNotifierProvider<UserProvider>.value(value: _User(UserRole.SUPER_ADMIN)),
        ],
        child: MaterialApp(navigatorKey: navigatorKey, home: const NotificationScreen()),
      ));
      await t.pump(); await t.pump(const Duration(milliseconds: 100));
      await t.tap(findVisibleText('노쇼 원장 보류 — 건별 심사 필요'));
      for (var i = 0; i < 5; i++) {
        await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
        await t.pump(const Duration(milliseconds: 50));
      }
      expect(find.byType(NoShowPendingReviewScreen), findsOneWidget);
      expect(notif.marked, ['n1']);
      expect(seen.single['name'], 'callableMigrateNoShowLedger');
      expect((seen.single['params'] as Map)['includePending'], true);
      expect(findVisibleText('열린 보류 — 발생 0'), findsOneWidget);
      await t.pageBack();
      await t.pump(); await t.pump(const Duration(milliseconds: 300));
      expect(find.byType(NoShowPendingReviewScreen), findsNothing);
      expect(findVisibleText('노쇼 원장 보류 — 건별 심사 필요'), findsOneWidget);
    });

    testWidgets('NPR-D2 일반 관리자가 같은 알림을 누르면 열리지 않는다', (t) async {
      t.view.physicalSize = const Size(360, 780);
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.reset);
      final notif = _Notif([
        NotificationModel(id: 'n1', userId: 'adm', type: NotificationType.noShowLedgerPending, title: '노쇼 원장 보류 — 건별 심사 필요',
            body: 'b', isRead: false, createdAt: DateTime.now(), data: {'pendingId': _key, 'occurrence': 0, 'uid': 'w1'}),
      ]);
      await t.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<NotificationProvider>.value(value: notif),
          ChangeNotifierProvider<UserProvider>.value(value: _User(UserRole.BUSINESS_ADMIN)),
        ],
        child: MaterialApp(navigatorKey: navigatorKey, home: const NotificationScreen()),
      ));
      await t.pump(); await t.pump(const Duration(milliseconds: 100));
      await t.tap(findVisibleText('노쇼 원장 보류 — 건별 심사 필요'));
      await t.pump(); await t.pump(const Duration(milliseconds: 300));
      expect(find.byType(NoShowPendingReviewScreen), findsNothing);
      await t.pump(const Duration(seconds: 4));
    });
  });

  // [.56] 근거: perf-20261028/c56 — 기기에서 검토 화면이 대상 근로자를 보이지 않았고(uid 만 있음),
  //   미리보기가 '닫힘'만 말해 해소가 거는 1일 자동 제한을 확인 전에 알 수 없었다.
  group('NPR-56 대상·처리 효과', () {
    Future<void> pumpWith(WidgetTester t, List<Object> script, {Future<String?> Function(String)? label}) async {
      final s = _Server(script);
      final reads = NoShowPendingReads(migrate: s.reads.migrate, targetLabel: label);
      t.view.physicalSize = const Size(411, 1400);
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.reset);
      await t.pumpWidget(ChangeNotifierProvider<UserProvider>.value(
        value: _User(UserRole.SUPER_ADMIN),
        child: MaterialApp(
          navigatorKey: navigatorKey,
          theme: ThemeData(fontFamily: 'NotoSansKR'),
          home: NoShowPendingReviewScreen(pendingId: _key, occurrence: 0, targetUid: 'w1', reads: reads),
        ),
      ));
      await t.pump();
      await t.pump(const Duration(milliseconds: 50));
    }

    testWidgets('NPR-56a 검토 화면이 대상 근로자를 이름·아이디로 보인다(읽기 실패면 확인하지 못함)', (t) async {
      await pumpWith(t, [_resp()], label: (uid) async => uid == 'w1' ? '합성 초대 (@e7c5_inv)' : null);
      await t.pump();
      expect(findVisibleText('합성 초대 (@e7c5_inv)'), findsOneWidget);
    });

    testWidgets('NPR-56b 읽기 실패는 이름을 지어내지 않는다', (t) async {
      await pumpWith(t, [_resp()], label: (uid) async => throw Exception('denied'));
      await t.pump();
      expect(findVisibleText('확인하지 못함'), findsOneWidget);
    });

    testWidgets('NPR-56c 미리보기가 해소 전·후 횟수·최근 90일·이용 제한을 서버 값 그대로 보인다', (t) async {
      final until = DateTime.utc(2026, 11, 2, 13, 13).millisecondsSinceEpoch; // KST 11-02 22:13
      final preview = _resp(report: {'uid': 'w1', 'status': 'MIGRATED',
        'before': {'count': 3, 'datesMs': [1, 2], 'recent': 2, 'restriction': null},
        'after': {'count': 3, 'datesMs': [1, 2, 3], 'recent': 3, 'restriction': until}});
      await pumpWith(t, [_resp(), preview], label: (uid) async => '합성 초대 (@e7c5_inv)');
      await _selectAndType(t, '날짜가 사실');
      await _openConfirm(t);
      expect(findVisibleText('3 → 3'), findsOneWidget);
      expect(findVisibleText('2 → 3'), findsOneWidget);
      expect(findVisibleTextContaining('까지 제한됩니다'), findsOneWidget);
      expect(findVisibleTextContaining('2026년 11월 2일 오후 10시 13분'), findsOneWidget);
    });

    testWidgets('NPR-56e 큰 글자(2.0)에서는 이름 위·값 아래로 쌓아 "최근 902 → 3" 처럼 붙어 읽히지 않는다', (t) async {
      final preview = _resp(report: {'uid': 'w1', 'status': 'MIGRATED',
        'before': {'count': 3, 'datesMs': [1, 2], 'recent': 2, 'restriction': null},
        'after': {'count': 3, 'datesMs': [1, 2, 3], 'recent': 3, 'restriction': null}});
      final s = _Server([_resp(), preview]);
      t.view.physicalSize = const Size(392, 1600);
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.reset);
      await t.pumpWidget(ChangeNotifierProvider<UserProvider>.value(
        value: _User(UserRole.SUPER_ADMIN),
        child: MaterialApp(
          navigatorKey: navigatorKey,
          theme: ThemeData(fontFamily: 'NotoSansKR'),
          builder: (c, child) => MediaQuery(data: MediaQuery.of(c).copyWith(textScaler: const TextScaler.linear(2.0)), child: child!),
          home: NoShowPendingReviewScreen(pendingId: _key, occurrence: 0, targetUid: 'w1', reads: s.reads),
        ),
      ));
      await t.pump();
      await t.pump(const Duration(milliseconds: 50));
      await _selectAndType(t, '날짜가 사실');
      await _openConfirm(t);
      final label = findVisibleText('최근 90일');
      final value = findVisibleText('2 → 3');
      expect(label, findsOneWidget);
      expect(value, findsOneWidget);
      expect(t.getTopLeft(value).dy, greaterThan(t.getBottomLeft(label).dy - 1), reason: '값은 이름 아래 줄에 온다');
      expect(t.takeException(), isNull);
    });

    testWidgets('NPR-56d 제한 예측이 없는 서버 응답이면 "제한 없음"으로 단정하지 않는다', (t) async {
      final preview = _resp(report: {'uid': 'w1', 'status': 'MIGRATED',
        'before': {'count': 3, 'datesMs': [1, 2], 'recent': 2, 'restriction': null},
        'after': {'count': 3, 'datesMs': [1, 2, 3], 'recent': 3, 'restriction': null}});
      await pumpWith(t, [_resp(), preview]);
      await _selectAndType(t, '날짜가 사실');
      await _openConfirm(t);
      expect(findVisibleText('서버 미리보기에 제한 표시 없음'), findsOneWidget);
      expect(findVisibleTextContaining('제한 없음'), findsNothing);
    });
  });
}
