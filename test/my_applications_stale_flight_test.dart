// [MY-APPS-STALE-FLIGHT] 옛 GetMyApplications 응답이 **마지막에** 도착할 때 화면이 되돌아가는가.
//
//   순서: 첫 진입(세 탭이 같은 진행 중 조회를 기다림 — 응답 보류)
//         → 지원 변경 + 캐시 무효화
//         → 일정·일자리 탭 새로고침 → 새 응답 먼저 완료(화면에 새 값)
//         → 보류했던 옛 응답 완료
//   그 뒤 각 화면의 최종 표시와 서비스 캐시를 본다.
//     A 확정: 옛=대기, 새=확정 → 일정 탭 `확정 근무` 1일이어야 한다
//     B 취소: 옛=대기, 새=취소 → 일자리 탭 카드에 `지원완료` 가 없어야 한다
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ALfit/models/core/to_model.dart';
import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/models/core/user_region.dart';
import 'package:ALfit/models/core/work_detail_data.dart';
import 'package:ALfit/providers/notification_provider.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/screens/user/my_schedule_screen.dart';
import 'package:ALfit/screens/user/tabs/user_job_tab.dart';
import 'package:ALfit/screens/user/user_home_screen.dart';
import 'package:ALfit/screens/user/user_root_screen.dart';
import 'package:ALfit/services/firestore_service.dart';
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

class _User extends UserProvider {
  static const region =
      UserRegion(province: '서울특별시', city: '강남구', district: '역삼동');
  @override
  UserModel? get currentUser => UserModel(
        uid: 'u1', username: 'u1', name: '김근로', email: 'u1@alfit.local',
        role: UserRole.USER, homeRegion: region, accountStatus: 'active',
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

final DateTime _today = FormatHelper.toKstDate(DateTime.now());
Map<String, Object?> _ts(DateTime d) =>
    {'_seconds': d.millisecondsSinceEpoch ~/ 1000, '_nanoseconds': 0};

Map<String, Object?> _app(String status) => {
      'id': 'a1', 'uid': 'u1', 'toId': 'to1', 'businessId': 'biz1',
      'businessName': '합성 사업장', 'toTitle': '합성 공고', 'status': status,
      'selectedWorkType': '상하차', 'startTime': '09:00', 'endTime': '18:00',
      'wage': 12000, 'wageType': 'hourly',
      'workDate': _ts(_today.add(const Duration(days: 1))),
      'appliedAt': _ts(_today.subtract(const Duration(days: 1))),
    };

Object? _wire(Object? v) {
  if (v is Timestamp) return {'_seconds': v.seconds, '_nanoseconds': v.nanoseconds};
  if (v is DateTime) return _ts(v);
  if (v is Map) return v.map((k, e) => MapEntry('$k', _wire(e)));
  if (v is List) return v.map(_wire).toList();
  return v;
}

Map<String, Object?> _toWire() {
  final d = _today.add(const Duration(days: 1));
  final key = '${d.year}-${d.month.toString().padLeft(2, "0")}-${d.day.toString().padLeft(2, "0")}';
  final to = TOModel(
    id: 'to1', businessId: 'biz1', businessName: '합성 사업장',
    businessCity: _User.region.city, businessDistrict: _User.region.district,
    type: 'flex', title: '합성 공고', creatorUID: 'admin1', status: TOStatus.active,
    deadlineType: 'NONE', hoursBeforeStart: 0,
    workDetails: [
      WorkDetailData(wdId: 'wd1', workType: '상하차', wage: 12000, wageType: 'hourly',
          requiredCount: 2, startTime: '09:00', endTime: '18:00'),
    ],
    slotDateKeys: [key], totalRequired: 2, totalConfirmed: 0, totalPending: 1,
    isPublished: true, publishMode: 'immediate',
    createdAt: _today.subtract(const Duration(days: 2)),
    statusUpdatedAt: _today.subtract(const Duration(days: 2)),
  );
  // 서버 응답 파서는 슬롯 날짜를 'dates'·'totalSlots' 로 읽는다(toMap 에는 없다) — 없으면 '슬롯 없음'으로 숨겨진다.
  return {'id': 'to1', ...(_wire(to.toMap()) as Map<String, Object?>), 'dates': [key], 'totalSlots': 1};
}

class _Server {
  _Server(this.freshStatus);
  final String freshStatus;
  final oldGate = Completer<void>();
  int my = 0;
  int paged = 0;
  bool failFirstPaged = false;
  Future<ByteData?> handle(ByteData? data) async {
    final args = (const StandardMessageCodec().decodeMessage(data) as List).first as Map;
    final name = args['functionName'] as String;
    if (name == 'callableGetMyApplications') {
      final n = ++my;
      if (n == 1) {
        await oldGate.future; // 옛 응답 — 마지막에 도착시킨다
        return _ok({'applications': [_app('PENDING')]});
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
      return _ok({'applications': [_app(freshStatus)]});
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));
    if (name == 'callableGetPublishedTOsPaged') {
      paged++;
      if (failFirstPaged && paged == 1) {
        await oldGate.future; // 첫 로드가 진행 중인 동안 실패한다
        return const StandardMessageCodec().encodeMessage(<Object?>['unavailable', 'mock', null]);
      }
      return _ok({'tos': [_toWire()], 'hasMore': false});
    }
    if (name == 'callableGetPublishedTOs') {
      return _ok({'tos': [_toWire()], 'hasMore': false});
    }
    return _ok({
      'applications': <Object?>[], 'items': <Object?>[], 'tos': <Object?>[],
      'requests': <Object?>[], 'proposals': <Object?>[], 'contracts': <Object?>[],
      'hasMore': false,
    });
  }

  ByteData? _ok(Map<String, Object?> body) =>
      const StandardMessageCodec().encodeMessage(<Object?>[body]);
}

void _install(WidgetTester t, _Server s) {
  final m = t.binding.defaultBinaryMessenger;
  m.setMockMessageHandler(_callCh, s.handle);
  for (final api in ['documentReferenceGet', 'queryGet', 'aggregateQuery']) {
    m.setMockMessageHandler('$_fsBase$api', (_) async {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      return const StandardMessageCodec().encodeMessage(<Object?>['unavailable', 'mock', null]);
    });
  }
  addTearDown(() {
    m.setMockMessageHandler(_callCh, null);
    for (final api in ['documentReferenceGet', 'queryGet', 'aggregateQuery']) {
      m.setMockMessageHandler('$_fsBase$api', null);
    }
  });
}

Future<void> _pumpFor(WidgetTester t, int ms) async {
  for (var e = 0; e < ms; e += 50) {
    await t.pump(const Duration(milliseconds: 50));
  }
}

List<String> _textsIn(WidgetTester t, Type screen) => t
    .widgetList<Text>(find.descendant(
        of: find.byType(screen, skipOffstage: false),
        matching: find.byType(Text, skipOffstage: false)))
    .map((w) => w.data ?? w.textSpan?.toPlainText() ?? '')
    .where((s) => s.isNotEmpty)
    .toList();

String _after(List<String> xs, String label) {
  final i = xs.indexOf(label);
  return i >= 0 && i + 1 < xs.length ? xs[i + 1] : '-';
}

String _before(List<String> xs, String label) {
  final i = xs.indexOf(label);
  return i > 0 ? xs[i - 1] : '-';
}

Map<String, String> _snapshot(WidgetTester t) {
  final sch = _textsIn(t, MyScheduleScreen);
  final job = _textsIn(t, UserJobTab);
  final home = _textsIn(t, UserHomeScreen);
  return {
    '일정 확정근무': _after(sch, '확정 근무'),
    '일자리 지원완료': '${job.where((s) => s == '지원완료').length}',
    '일자리 카드': '${job.where((s) => s.contains('합성 공고')).length}',
    '홈 검토중': _before(home, '검토중'),
    '홈 확정': _before(home, '확정'),
  };
}

/// 일정 탭: 첫 조회가 끝나기 전에는 로딩 화면이라 당겨서 새로고침이 없다 — 겹치는 두 번째 조회를 만들 수 없다.
Future<bool> _scheduleRefreshAvailable(WidgetTester t) async {
  await t.tap(find.text('일정').last);
  await _pumpFor(t, 300);
  return find.byType(RefreshIndicator).evaluate().isNotEmpty;
}

/// 일자리 탭: 로딩 중에도 검색창은 쓸 수 있다 — 검색어를 바꾸면 `_loadAllTOs` 가 다시 돈다.
Future<void> _jobSearch(WidgetTester t, String q) async {
  await t.tap(find.text('일자리').last);
  await _pumpFor(t, 300);
  await t.enterText(find.descendant(of: find.byType(UserJobTab), matching: find.byType(TextField)).first, q);
  await _pumpFor(t, 1500); // 디바운스 500ms + 응답
}

Future<Map<String, Object>> _run(WidgetTester t, String fresh) async {
  final s = _Server(fresh);
  _install(t, s);
  FirestoreService().invalidateMyApplicationsCache('u1');
  t.view.physicalSize = const Size(390, 1600);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider<UserProvider>(create: (_) => _User()),
      ChangeNotifierProvider<NotificationProvider>(create: (_) => NotificationProvider()),
    ],
    child: const MaterialApp(home: UserRootScreen()),
  ));
  await _pumpFor(t, 1000);
  final callsWhileHeld = s.my;
  // 지원 변경이 커밋됐다 — 서비스가 하는 것과 같은 무효화
  FirestoreService().invalidateMyApplicationsCache('u1');
  final schRefresh = await _scheduleRefreshAvailable(t);
  await _jobSearch(t, '합성');
  final mid = _snapshot(t);
  s.oldGate.complete();
  await _pumpFor(t, 1500);
  final fin = _snapshot(t);
  final cacheF = FirestoreService().getMyApplications('u1');
  await _pumpFor(t, 300); // 가짜 시계 — 캐시가 없으면 응답 지연이 pump 로만 흐른다
  final cache = await cacheF;
  t.takeException();
  return {
    'callsWhileHeld': callsWhileHeld, 'calls': s.my, 'scheduleRefreshWhileLoading': schRefresh,
    'mid': mid, 'final': fin, 'cache': cache.map((a) => a.status).join(','),
    'paged': s.paged,
  };
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
    await initializeDateFormatting('ko_KR', null);
  });
  setUp(() => SharedPreferences.setMockInitialValues({'tour_completed_user_home': true}));

  testWidgets('MSF-A 일정 탭 — 첫 조회 중에는 새로고침 입구가 없어 겹치는 조회가 생기지 않는다', (t) async {
    final r = await _run(t, 'CONFIRMED');
    // ignore: avoid_print
    print('[MSF-A] $r');
    expect(r['scheduleRefreshWhileLoading'], isFalse);
    expect(r['cache'], 'CONFIRMED', reason: '옛 응답이 캐시를 덮으면 안 된다');
  });

  testWidgets('MSF-B 일자리 탭 — 로딩 중 검색으로 버려졌던 재조회가 첫 로드 직후 한 번 돌아 CANCELED 가 반영된다', (t) async {
    final r = await _run(t, 'CANCELED');
    // ignore: avoid_print
    print('[MSF-B] $r');
    final fin = r['final'] as Map;
    expect(fin['일자리 카드'], '1');
    expect(fin['일자리 지원완료'], '0', reason: '옛(대기) 응답이 최종 결과로 남으면 안 된다');
    expect(r['paged'], 2, reason: '첫 로드 + 보류된 재조회 1회');
    expect(r['cache'], 'CANCELED');
  });

  Future<_Server> mount(WidgetTester t, {bool failFirstPaged = false}) async {
    final s = _Server('CANCELED')..failFirstPaged = failFirstPaged;
    _install(t, s);
    FirestoreService().invalidateMyApplicationsCache('u1');
    t.view.physicalSize = const Size(390, 1600);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    await t.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<UserProvider>(create: (_) => _User()),
        ChangeNotifierProvider<NotificationProvider>(create: (_) => NotificationProvider()),
      ],
      child: const MaterialApp(home: UserRootScreen()),
    ));
    await _pumpFor(t, 1000);
    return s;
  }

  testWidgets('JLR-2 로딩 중 검색을 연달아 바꿔도 재조회는 한 번, 마지막 조건으로 수렴', (t) async {
    final s = await mount(t);
    FirestoreService().invalidateMyApplicationsCache('u1'); // 지원서 변경(취소) 커밋
    await t.tap(find.text('일자리').last);
    await _pumpFor(t, 300);
    final field = find.descendant(of: find.byType(UserJobTab), matching: find.byType(TextField)).first;
    await t.enterText(field, '없는말');
    await _pumpFor(t, 700);
    await t.enterText(field, '합성');
    await _pumpFor(t, 700);
    s.oldGate.complete();
    await _pumpFor(t, 2000);
    final job = _textsIn(t, UserJobTab);
    // ignore: avoid_print
    print('[JLR-2] paged=${s.paged} · ${job.where((x) => x.contains('일자리') && x.contains('개')).join(',')}');
    expect(s.paged, 2, reason: '보류 요청은 몇 번이 와도 한 번');
    expect(job.any((x) => x.contains('"합성" 일자리 1개')), isTrue, reason: '마지막 검색어로 수렴');
    expect(job.where((x) => x == '지원완료').length, 0);
    t.takeException();
  });

  testWidgets('JLR-3 첫 로드가 실패하면 보류 요청을 자동으로 돌리지 않는다(무한 반복 없음)', (t) async {
    final s = await mount(t, failFirstPaged: true);
    await t.tap(find.text('일자리').last);
    await _pumpFor(t, 300);
    await t.enterText(find.descendant(of: find.byType(UserJobTab), matching: find.byType(TextField)).first, '합성');
    await _pumpFor(t, 700);
    s.oldGate.complete();
    await _pumpFor(t, 3000);
    expect(s.paged, 1, reason: '실패 뒤 자동 재조회 없음');
    t.takeException();
  });

  testWidgets('JLR-4 화면이 닫히면 보류 요청을 돌리지 않는다', (t) async {
    final s = await mount(t);
    await t.tap(find.text('일자리').last);
    await _pumpFor(t, 300);
    await t.enterText(find.descendant(of: find.byType(UserJobTab), matching: find.byType(TextField)).first, '합성');
    await _pumpFor(t, 700);
    await t.pumpWidget(const SizedBox.shrink()); // 화면 종료
    s.oldGate.complete();
    await _pumpFor(t, 2000);
    expect(s.paged, 1);
    t.takeException();
  });


}
