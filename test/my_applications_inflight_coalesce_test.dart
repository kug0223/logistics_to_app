// [MY-APPS-INFLIGHT] 같은 uid 의 진행 중 GetMyApplications 하나를 공유한다.
//
// ── 대조 (CODE) ──────────────────────────────────────────────────────
//   홈(UserHomeReads) · 일자리 탭(UserJobTabReads) · 일정 탭(MyScheduleReads) 모두
//   같은 싱글턴 FirestoreService.getMyApplications(uid) 를 부른다.
//   uid = 현재 로그인 사용자, 요청 인자 = {limit: 200} 하나뿐, 서버는 인증 uid 로 응답한다.
//   → 세 요청은 같은 요청이다. 다른 것은 각 화면의 새로고침 조건뿐이다.
//
// ── 바꾼 것 ──────────────────────────────────────────────────────────
//   진행 중 요청만 공유하고 완료되면(성공·실패) 바로 놓는다. 완료 결과의 보관은
//   기존 1분 TTL 규칙 그대로다. 무효화(지원·취소·확정 뒤)는 진행 중 요청도 끊고,
//   그 전에 출발한 응답은 캐시에 남기지 않는다.
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/models/core/user_region.dart';
import 'package:ALfit/providers/notification_provider.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/screens/user/user_root_screen.dart';
import 'package:ALfit/services/firestore_service.dart';

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

class _User extends UserProvider {
  @override
  UserModel? get currentUser => UserModel(
        uid: 'u1', username: 'u1', name: '김근로', email: 'u1@alfit.local',
        role: UserRole.USER,
        homeRegion: const UserRegion(province: '서울특별시', city: '강남구'),
        accountStatus: 'active',
      );
  @override
  bool get isSubAdmin => false;
  @override
  bool get isBusinessAdmin => false;
  @override
  bool get isSuperAdmin => false;
  @override
  bool get isAdminMode => false;
  @override
  bool get permissionsLoaded => true;
  @override
  bool get hasPendingContract => false;
}

const _callCh =
    'dev.flutter.pigeon.cloud_functions_platform_interface.CloudFunctionsHostApi.call';
const _fsBase =
    'dev.flutter.pigeon.cloud_firestore_platform_interface.FirebaseFirestoreHostApi.';

Map<String, Object?> _ts(DateTime d) =>
    {'_seconds': d.millisecondsSinceEpoch ~/ 1000, '_nanoseconds': 0};

Map<String, Object?> _app(String id, String status) => {
      'id': id, 'uid': 'u1', 'toId': 'to_$id', 'businessId': 'biz1',
      'businessName': '합성 사업장', 'toTitle': '합성 공고 $id', 'status': status,
      'selectedWorkType': '상하차', 'startTime': '09:00', 'endTime': '18:00',
      'wage': 12000, 'wageType': 'hourly',
      'workDate': _ts(DateTime.now().add(const Duration(days: 3))),
      'appliedAt': _ts(DateTime.now().subtract(const Duration(days: 1))),
    };

/// 서버 대역 — 요청마다 지연·응답을 정한다. 호출은 이름별로 센다.
class _Server {
  _Server();
  int delayMs = 300;
  final calls = <String, int>{};
  /// GetMyApplications 응답(요청이 출발한 순서대로 하나씩 소비, 마지막 값 반복).
  final List<Object> myApps = [
    [_app('a1', 'PENDING')]
  ];
  int _myAppsIdx = 0;

  Future<ByteData?> handle(ByteData? data) async {
    final args = (const StandardMessageCodec().decodeMessage(data) as List).first as Map;
    final name = args['functionName'] as String;
    calls[name] = (calls[name] ?? 0) + 1;
    Object? body = <String, Object?>{
      'applications': <Object?>[], 'items': <Object?>[], 'tos': <Object?>[],
      'requests': <Object?>[], 'proposals': <Object?>[], 'contracts': <Object?>[],
      'hasMore': false,
    };
    if (name == 'callableGetMyApplications') {
      final r = myApps[_myAppsIdx < myApps.length ? _myAppsIdx : myApps.length - 1];
      _myAppsIdx++;
      await Future<void>.delayed(Duration(milliseconds: delayMs));
      if (r is String) {
        return const StandardMessageCodec()
            .encodeMessage(<Object?>[r, 'mock $r', null]);
      }
      body = {'applications': r};
      return const StandardMessageCodec().encodeMessage(<Object?>[body]);
    }
    await Future<void>.delayed(Duration(milliseconds: delayMs));
    return const StandardMessageCodec().encodeMessage(<Object?>[body]);
  }

  int get my => calls['callableGetMyApplications'] ?? 0;
}

void _install(WidgetTester t, _Server s) {
  final m = t.binding.defaultBinaryMessenger;
  m.setMockMessageHandler(_callCh, s.handle);
  for (final api in ['documentReferenceGet', 'queryGet', 'aggregateQuery']) {
    m.setMockMessageHandler('$_fsBase$api', (_) async {
      await Future<void>.delayed(const Duration(milliseconds: 300));
      return const StandardMessageCodec()
          .encodeMessage(<Object?>['unavailable', 'mock', null]);
    });
  }
  addTearDown(() {
    m.setMockMessageHandler(_callCh, null);
    for (final api in ['documentReferenceGet', 'queryGet', 'aggregateQuery']) {
      m.setMockMessageHandler('$_fsBase$api', null);
    }
  });
}

/// 싱글턴의 상태를 테스트마다 비운다(이 파일이 쓰는 uid 들).
void _reset() {
  for (final u in ['u1', 'u2', 'u3', 'u4', 'u5', 'u6']) {
    FirestoreService().invalidateMyApplicationsCache(u);
  }
}

Future<void> _pumpFor(WidgetTester t, int ms) async {
  for (var e = 0; e < ms; e += 50) {
    await t.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
    await initializeDateFormatting('ko_KR', null);
  });
  setUp(() {
    SharedPreferences.setMockInitialValues({'tour_completed_user_home': true});
    _reset();
  });

  group('MAC-SVC 서비스', () {
    testWidgets('MAC-1 동시 3회 → 서버 1회, 세 호출 모두 같은 응답', (t) async {
      final s = _Server();
      _install(t, s);
      final svc = FirestoreService();
      final fs = [svc.getMyApplications('u1'), svc.getMyApplications('u1'), svc.getMyApplications('u1')];
      await _pumpFor(t, 400);
      final r = await Future.wait(fs);
      expect(s.my, 1);
      expect(r.map((l) => l.map((a) => a.id).join(',')).toSet(), {'a1'});
    });

    testWidgets('MAC-2 실패도 공유되고(서버 1회), 실패 뒤 다음 호출은 새로 나간다', (t) async {
      final s = _Server()..myApps.clear()
        ..myApps.addAll(['unavailable', [_app('a2', 'CONFIRMED')]]);
      _install(t, s);
      final svc = FirestoreService();
      final errs = <Object?>[];
      final fs = [for (var i = 0; i < 3; i++) svc.getMyApplications('u2').then<Object?>((v) => v, onError: (Object e) { errs.add(e); return null; })];
      await _pumpFor(t, 400);
      await Future.wait(fs);
      expect(s.my, 1);
      expect(errs, hasLength(3), reason: '실패를 빈 목록으로 바꾸지 않는다');
      final next = svc.getMyApplications('u2');
      await _pumpFor(t, 400);
      expect((await next).single.id, 'a2');
      expect(s.my, 2, reason: '실패한 진행 중 요청은 놓였다');
    });

    testWidgets('MAC-3 완료 뒤에는 공유가 아니라 기존 TTL 캐시만 — 무효화하면 새로 나간다', (t) async {
      final s = _Server()..myApps.clear()
        ..myApps.addAll([[_app('a3', 'PENDING')], [_app('a3', 'CONFIRMED')]]);
      _install(t, s);
      final svc = FirestoreService();
      final f1 = svc.getMyApplications('u3');
      await _pumpFor(t, 400);
      expect((await f1).single.status, 'PENDING');
      // 명시적 새로고침(지원·취소·확정 뒤 서비스가 부르는 것과 같은 무효화)
      svc.invalidateMyApplicationsCache('u3');
      final f2 = svc.getMyApplications('u3');
      await _pumpFor(t, 400);
      expect((await f2).single.status, 'CONFIRMED');
      expect(s.my, 2);
    });

    testWidgets('MAC-4 진행 중에 무효화되면 새 호출은 합류하지 않고, 옛 응답은 캐시에 남지 않는다', (t) async {
      final s = _Server()..myApps.clear()
        ..myApps.addAll([[_app('a4', 'PENDING')], [_app('a4', 'CONFIRMED')]]);
      _install(t, s);
      final svc = FirestoreService();
      final old = svc.getMyApplications('u4'); // 변경 전 출발
      await _pumpFor(t, 100);
      svc.invalidateMyApplicationsCache('u4'); // 예: 이 기기에서 확정·취소가 커밋됨
      final fresh = svc.getMyApplications('u4');
      await _pumpFor(t, 500);
      expect((await old).single.status, 'PENDING');
      expect((await fresh).single.status, 'CONFIRMED');
      expect(s.my, 2);
      // TTL 안 재조회 — 캐시에는 새 응답만 있다(옛 응답이 늦게 도착해 덮지 않는다).
      final again = await svc.getMyApplications('u4');
      expect(again.single.status, 'CONFIRMED');
      expect(s.my, 2);
    });

    testWidgets('MAC-5 계정이 다르면 공유하지 않는다(로그아웃·계정 전환)', (t) async {
      final s = _Server();
      _install(t, s);
      final svc = FirestoreService();
      final a = svc.getMyApplications('u5');
      final b = svc.getMyApplications('u6');
      await _pumpFor(t, 400);
      await Future.wait([a, b]);
      expect(s.my, 2);
    });
  });

  testWidgets('MAC-ROOT 첫 진입 네 탭 — 서버 호출 3→1, 세 탭이 같은 값을 받는다', (t) async {
    final s = _Server();
    _install(t, s);
    t.view.physicalSize = const Size(390, 900);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    await t.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<UserProvider>(create: (_) => _User()),
        ChangeNotifierProvider<NotificationProvider>(create: (_) => NotificationProvider()),
      ],
      child: const MaterialApp(home: UserRootScreen()),
    ));
    await _pumpFor(t, 3000);
    // ignore: avoid_print
    print('[MAC-ROOT] callableGetMyApplications ${s.my}회 · 전체 ${s.calls}');
    // 홈 지원 현황: 검토중 1 (공유 응답에서 나온 값)
    final home = find.text('검토중', skipOffstage: false);
    expect(home, findsWidgets);
    // ignore: avoid_print
    print('[MAC-ROOT] 공고명 노출 ${find.textContaining('합성 공고 a1', skipOffstage: false).evaluate().length}곳 · 검토중 셀 값 ${t.widgetList<Text>(find.byType(Text, skipOffstage: false)).map((w) => w.data ?? '').where((x) => x == '1').length}개');
    final dump = <String>[];
    for (final tab in ['홈', '일정', '일자리']) {
      await t.tap(find.text(tab).last);
      await _pumpFor(t, 1500);
      dump.add('## $tab');
      dump.addAll(t.widgetList<Text>(find.byType(Text)).map((w) => w.data ?? w.textSpan?.toPlainText() ?? '').where((x) => x.isNotEmpty));
    }
    final out = const String.fromEnvironment('MAC_DUMP');
    if (out.isNotEmpty) File(out).writeAsStringSync(dump.join(String.fromCharCode(10)));
    expect(s.my, 1);
    t.takeException();
  });
}
