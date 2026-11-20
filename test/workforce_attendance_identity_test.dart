// [ADMIN-ATT-IDENTITY] 관리자 근무 탭 — 근태는 uid 가 아니라 **그 지원서**에 붙는다.
//
// DEVICE 관찰(Pixel 5, 원본 APK 1.0.21, 10-20 15:10): 같은 날 xZah 의 두 근무
//   (Zdn7 10:00~11:00 근태 없음 / RUBE 13:00~14:00 출퇴근)에서 Zdn7 행에도
//   RUBE 근태 `13:00 출근 · 14:00 퇴근 · 퇴근 완료`가 붙었고, 집계가
//   `출근 2 · 미출근 0` 이었다. DEV 원장: 근태 1건(RUBE). 같은 날 당일명단은
//   `출근 1 · 미출근 1`(applicationId 기준)로 맞았다.
//
// root cause: 행은 `attMap[app.uid]`(uid 당 최신 체크인 1건), 집계는
//   `_attMapByUid`(uid 당 첫 근태 1건) — 둘 다 uid 로 묶었다. 행의 수정 버튼은
//   `initialApplicationId: worker.application.id` 로 열려 대상 자체는 맞았지만,
//   행이 보여 준 근태·버튼 종류(`확인` vs `근태 처리`)가 다른 근무의 것이었다.
//
// 계약
//   LK-* 연결 함수 단위 — 명시 id / 옛 근태 단일·모호 / 다른 근무 근태 / 최신 체크인
//   WF-1 [DEV 재현] 같은 날 같은 근로자 두 근무: 출근 1 · 미출근 1, 근태는 RUBE 행에만
//   WF-2 단일 근무 회귀: 기존처럼 그 근무에 붙는다
//   WF-3 다른 날 NO_SHOW 회귀: 노쇼 1, 그 행만 노쇼
//   WF-4 옛 근태(applicationId 없음) + 두 근무: 어느 행에도 붙이지 않고 근태 미확인, 수정 입구 없음
//
// 하네스: 실제 WorkforceOperationalView + 실제 FirestoreService. 네 callable
//   (callableGetMyBusiness·callableGetApplicationsByBiz·callableGetAdminAttendances·
//   callableGetUsersBatch)을 pigeon 채널에서 같은 DEV 모양으로 돌려준다. DEV 호출 없음.
//   화면은 **실제 오늘(KST)** 로 열리고 미출근은 실제 시계로 시작 전/후를 가른다.
//   그래서 근태 없는 근무의 시작을 00:00 으로 둔다(언제 돌려도 시작 후).
import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ALfit/controllers/workforce_controller.dart';
import 'package:ALfit/models/core/application_model.dart';
import 'package:ALfit/models/core/attendance_model.dart';
import 'package:ALfit/models/core/business_member_model.dart'
    show MemberPermissions;
import 'package:ALfit/models/core/business_model.dart';
import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/screens/business_admin/workforce_management/workforce_operational_view.dart';
import 'package:ALfit/utils/format_helper.dart';
import 'package:ALfit/utils/navigation_key.dart';

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

const _biz = 'BIZ1';
const _worker = 'xZahWORKER';

class _AdminP extends UserProvider {
  @override
  UserModel? get currentUser => UserModel(
      uid: 'OWNER',
      username: 'owner',
      name: '관리자',
      email: 'owner@test.local',
      role: UserRole.BUSINESS_ADMIN,
      managedBusinessIds: const [_biz]);
  @override
  String? get effectiveBusinessId => _biz;
  @override
  bool can(bool Function(MemberPermissions p) check) => true;
  @override
  bool canForBusiness(
          String businessId, bool Function(MemberPermissions p) check) =>
      true;
  @override
  PermissionCheck checkForBusiness(
          String businessId, bool Function(MemberPermissions p) check) =>
      PermissionCheck.allowed;
  @override
  PermissionCheck checkCurrentBusiness(bool Function(MemberPermissions p) check) =>
      PermissionCheck.allowed;
}

/// 공고 탭 첫 로드를 거친 상태 — 이 화면은 그 전까지 스피너만 그린다.
class _LoadedController extends WorkforceController {
  @override
  bool get hasLoadedOnce => true;
}

const _channel =
    'dev.flutter.pigeon.cloud_functions_platform_interface.CloudFunctionsHostApi.call';

/// 오늘 KST 자정(서버 workDate 저장 형식).
DateTime _kstMidnight([int dayOffset = 0]) {
  final k = DateTime.now().toUtc().add(const Duration(hours: 9));
  return DateTime.utc(k.year, k.month, k.day + dayOffset)
      .subtract(const Duration(hours: 9));
}

/// KST 벽시계 시각의 절대 시각.
DateTime _kstAt(int h, int m, [int dayOffset = 0]) =>
    _kstMidnight(dayOffset).add(Duration(hours: h, minutes: m));

ApplicationModel _app(String id,
        {required String start,
        required String end,
        String toId = 'TO',
        String slotId = 'S',
        String uid = _worker,
        int dayOffset = 0,
        String status = AppStatus.confirmed}) =>
    ApplicationModel(
      id: id,
      toId: toId,
      slotId: slotId,
      workDetailId: 'wd-$toId',
      uid: uid,
      applicantName: uid == _worker ? 'QA 지원자2' : 'QA 지원자1',
      businessId: _biz,
      businessName: 'QA 사업장',
      toTitle: 'QA $toId',
      status: status,
      selectedWorkType: 'QA 분류',
      startTime: start,
      endTime: end,
      wage: 12000,
      wageType: 'hourly',
      workDate: _kstMidnight(dayOffset),
      appliedAt: _kstMidnight(dayOffset).subtract(const Duration(days: 2)),
    );

AttendanceModel _att(String appId,
        {String uid = _worker,
        String status = AttendanceModel.statusPresent,
        DateTime? checkIn,
        DateTime? checkOut,
        int dayOffset = 0}) =>
    AttendanceModel(
      id: appId.isEmpty ? 'legacy-att' : '${appId}_day',
      applicationId: appId,
      userId: uid,
      businessId: _biz,
      businessName: 'QA 사업장',
      workDate: _kstMidnight(dayOffset),
      workType: 'QA 분류',
      checkInAt: checkIn,
      checkOutAt: checkOut,
      status: status,
      wageStatus: 'pending',
      createdAt: _kstMidnight(dayOffset),
    );

Object? _wire(Object? v) {
  if (v is Timestamp) {
    return {'_seconds': v.seconds, '_nanoseconds': v.nanoseconds};
  }
  if (v is DateTime) {
    final ms = v.millisecondsSinceEpoch;
    return {'_seconds': ms ~/ 1000, '_nanoseconds': (ms % 1000) * 1000000};
  }
  if (v is Map) return v.map((k, x) => MapEntry(k, _wire(x)));
  if (v is List) return v.map(_wire).toList();
  return v;
}

class _Server {
  _Server(this.apps, this.atts);
  final List<ApplicationModel> apps;
  final List<AttendanceModel> atts;
  final calls = <String>[];

  ByteData? _ok(Object data) =>
      const StandardMessageCodec().encodeMessage(<Object?>[data]);

  Future<ByteData?> handle(ByteData? message) async {
    final args = (const StandardMessageCodec().decodeMessage(message) as List)
        .first as Map;
    final name = args['functionName'] as String;
    final p = Map<String, Object?>.from((args['parameters'] as Map?) ?? {});
    calls.add(name);
    switch (name) {
      case 'callableGetMyBusiness':
        final b = BusinessModel(
          id: _biz,
          businessNumber: '000-00-00000',
          name: 'QA 사업장',
          category: 'QA',
          subCategory: 'QA',
          address: '경기도 평택시',
          ownerId: 'OWNER',
          createdAt: DateTime.utc(2026, 10, 1),
        );
        return _ok({
          'businesses': [
            Map<String, Object?>.from(_wire(b.toMap()) as Map)..['id'] = _biz
          ]
        });
      case 'callableGetApplicationsByBiz':
        // 장기 후보 조회(workEndDateGteMs)는 이 픽스처에 없다.
        final items = p.containsKey('workEndDateGteMs')
            ? const <Object?>[]
            : [
                for (final a in apps)
                  Map<String, Object?>.from(_wire(a.toMap()) as Map)
                    ..['id'] = a.id
              ];
        return _ok({'applications': items, 'hasMore': false});
      case 'callableGetAdminAttendances':
        final s = p['startMs'] as int;
        final e = p['endMs'] as int;
        return _ok({
          'items': [
            for (final a in atts)
              if (a.workDate.millisecondsSinceEpoch >= s &&
                  a.workDate.millisecondsSinceEpoch < e)
                Map<String, Object?>.from(_wire(a.toMap()) as Map)
                  ..['id'] = a.id
          ],
          'limitReached': false,
        });
      case 'callableGetUsersBatch':
        return _ok({'users': <String, Object?>{}});
    }
    return const StandardMessageCodec().encodeMessage(<Object?>[
      'not-found', 'unexpected $name', <String, Object?>{'code': 'not-found'}
    ]);
  }
}

Future<void> _settle(WidgetTester t, [int n = 40]) async {
  for (var i = 0; i < n; i++) {
    await t.pump(const Duration(milliseconds: 50));
  }
}

Future<_Server> _pump(WidgetTester t, _Server server) async {
  t.view.physicalSize = const Size(411, 2400);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  t.binding.defaultBinaryMessenger.setMockMessageHandler(_channel, server.handle);
  addTearDown(() =>
      t.binding.defaultBinaryMessenger.setMockMessageHandler(_channel, null));
  final controller = _LoadedController();
  addTearDown(controller.dispose);
  await t.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider<UserProvider>(create: (_) => _AdminP()),
      ChangeNotifierProvider<WorkforceController>.value(value: controller),
    ],
    child: MaterialApp(
      navigatorKey: navigatorKey,
      home: const Scaffold(body: WorkforceOperationalView()),
    ),
  ));
  await _settle(t);
  return server;
}

List<String> _texts(WidgetTester t) => [
      ...t.widgetList<Text>(find.byType(Text))
          .map((w) => w.data ?? w.textSpan?.toPlainText() ?? ''),
    ].where((s) => s.isNotEmpty).toList();

/// 요약 칩의 숫자 — 라벨 바로 앞의 Text.
int? _kpi(WidgetTester t, String label) {
  final s = _texts(t);
  final i = s.indexOf(label);
  if (i <= 0) return null;
  return int.tryParse(s[i - 1]);
}

/// 그룹 헤더(`HH:MM–HH:MM`)부터 다음 그룹 헤더 전까지의 문자열 — 한 근무 행.
String _rowOf(WidgetTester t, String header) {
  final s = _texts(t);
  final i = s.indexWhere((x) => x.contains(header));
  if (i < 0) return '';
  final rest = s.sublist(i + 1);
  final j = rest.indexWhere((x) => RegExp(r'^\d{2}:\d{2}–\d{2}:\d{2}$').hasMatch(x));
  return (j < 0 ? rest : rest.sublist(0, j)).join(' | ');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  setUpAll(() async {
    await initializeDateFormatting('ko');
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
  });

  // ── 연결 함수 단위 ─────────────────────────────────────────────────────
  group('LK linkWorkforceAttendances', () {
    final zdn7 = _app('Zdn7', start: '10:00', end: '11:00', toId: 'Zdn7');
    final rube = _app('RUBE', start: '13:00', end: '14:00', toId: 'RUBE');
    final rubeAtt = _att('RUBE',
        checkIn: _kstAt(13, 0), checkOut: _kstAt(14, 0));

    test('LK-1 [DEV 재현] 명시 applicationId — RUBE 에만 붙고 Zdn7 은 비어 있다', () {
      final l = linkWorkforceAttendances([zdn7, rube], [rubeAtt]);
      expect(l.byApplicationId.keys, ['RUBE']);
      expect(l.byApplicationId['RUBE']!.id, 'RUBE_day');
      expect(l.unresolvedApplicationIds, isEmpty);
    });

    test('LK-2 목록에 없는 지원서의 근태(다른 날·다른 근무)는 어디에도 붙지 않는다', () {
      final other = _att('OTHER', checkIn: _kstAt(9, 0));
      final l = linkWorkforceAttendances([zdn7, rube], [other]);
      expect(l.byApplicationId, isEmpty);
      expect(l.unresolvedApplicationIds, isEmpty);
    });

    test('LK-3 옛 근태(applicationId 없음) + 그 날 근무 하나 — 그 근무에 붙는다', () {
      final legacy = _att('', checkIn: _kstAt(13, 0));
      final l = linkWorkforceAttendances([rube], [legacy]);
      expect(l.byApplicationId['RUBE']?.id, 'legacy-att');
      expect(l.unresolvedApplicationIds, isEmpty);
    });

    test('LK-4 옛 근태 + 같은 날 같은 근로자 근무 둘 — 모호: 붙이지 않고 미확인', () {
      final legacy = _att('', checkIn: _kstAt(13, 0));
      final l = linkWorkforceAttendances([zdn7, rube], [legacy]);
      expect(l.byApplicationId, isEmpty);
      expect(l.unresolvedApplicationIds, {'Zdn7', 'RUBE'});
    });

    test('LK-5 명시 연결이 있는 근무는 모호 표시에서 빠진다', () {
      final legacy = _att('', checkIn: _kstAt(10, 0));
      final l = linkWorkforceAttendances([zdn7, rube], [rubeAtt, legacy]);
      expect(l.byApplicationId.keys, ['RUBE']);
      expect(l.unresolvedApplicationIds, {'Zdn7'});
    });

    test('LK-6 한 지원서에 근태 여럿 — 출근이 가장 늦은 것', () {
      final early = _att('RUBE', checkIn: _kstAt(12, 0));
      final late = AttendanceModel(
        id: 'RUBE_late',
        applicationId: 'RUBE',
        userId: _worker,
        businessId: _biz,
        businessName: 'QA 사업장',
        workDate: _kstMidnight(),
        workType: 'QA 분류',
        checkInAt: _kstAt(13, 0),
        status: AttendanceModel.statusPresent,
        wageStatus: 'pending',
        createdAt: _kstMidnight(),
      );
      final l = linkWorkforceAttendances([rube], [early, late]);
      expect(l.byApplicationId['RUBE']!.id, 'RUBE_late');
    });

    test('LK-7 다른 근로자의 옛 근태는 이 근로자 근무에 붙지 않는다', () {
      final legacy = _att('', uid: 'someone', checkIn: _kstAt(13, 0));
      final l = linkWorkforceAttendances([rube], [legacy]);
      expect(l.byApplicationId, isEmpty);
    });
  });

  // ── 실제 근무 탭 ───────────────────────────────────────────────────────
  testWidgets('WF-1 [DEV 재현] 같은 날 같은 근로자 두 근무 — 출근 1 · 미출근 1, 근태는 RUBE 행에만',
      (t) async {
    // Zdn7형: 근태 없음(시작 00:00 — 언제 돌려도 시작 후라 미출근으로 센다).
    final zdn7 = _app('Zdn7', start: '00:00', end: '00:01', toId: 'Zdn7');
    final rube = _app('RUBE', start: '00:02', end: '00:03', toId: 'RUBE');
    final server = await _pump(
        t,
        _Server([zdn7, rube], [
          _att('RUBE', checkIn: _kstAt(0, 2), checkOut: _kstAt(0, 3)),
        ]));
    expect(server.calls, contains('callableGetAdminAttendances'));
    expect(_kpi(t, '확정'), 2);
    expect(_kpi(t, '출근'), 1, reason: _texts(t).join(' | '));
    expect(_kpi(t, '미출근'), 1, reason: _texts(t).join(' | '));
    expect(_kpi(t, '노쇼'), 0);

    final zRow = _rowOf(t, '00:00–00:01');
    final rRow = _rowOf(t, '00:02–00:03');
    expect(rRow, contains('00:02 출근 · 00:03 퇴근'));
    expect(rRow, contains('퇴근 완료'));
    expect(rRow.split(' | '), contains('확인'), reason: '퇴근 완료 행은 확인 버튼');
    expect(zRow, isNot(contains('출근 ·')),
        reason: 'Zdn7 행에 다른 근무의 근태가 붙었다: $zRow');
    expect(zRow, contains('00:00 출근 예정'));
    expect(zRow, contains('미출근'));
    expect(zRow, contains('근태 처리'),
        reason: '근태 없는 행은 근태 처리 입구 — 다른 근무의 `확인`이 아니다');
  });

  testWidgets('WF-2 단일 근무 회귀 — 근태가 그 근무에 붙는다', (t) async {
    final rube = _app('RUBE', start: '00:02', end: '00:03', toId: 'RUBE');
    await _pump(
        t,
        _Server([rube], [
          _att('RUBE', checkIn: _kstAt(0, 2), checkOut: _kstAt(0, 3)),
        ]));
    expect(_kpi(t, '출근'), 1);
    expect(_kpi(t, '미출근'), 0);
    expect(_rowOf(t, '00:02–00:03'), contains('퇴근 완료'));
  });

  testWidgets('WF-3 다른 근무의 NO_SHOW 회귀 — 그 행만 노쇼, 노쇼 1', (t) async {
    // 같은 날 두 근로자: 지원자1 노쇼, 지원자2 출퇴근.
    final ns = _app('XNjJ1', start: '00:00', end: '00:01', toId: 'XNjJ', uid: '7oZZ');
    final rube = _app('RUBE', start: '00:02', end: '00:03', toId: 'RUBE');
    await _pump(
        t,
        _Server([ns, rube], [
          _att('XNjJ1', uid: '7oZZ', status: AttendanceModel.statusNoShow),
          _att('RUBE', checkIn: _kstAt(0, 2), checkOut: _kstAt(0, 3)),
        ]));
    expect(_kpi(t, '노쇼'), 1);
    expect(_kpi(t, '출근'), 1);
    expect(_kpi(t, '미출근'), 0, reason: '노쇼는 미출근으로 세지 않는다');
    expect(_rowOf(t, '00:00–00:01'), contains('노쇼'));
    expect(_rowOf(t, '00:02–00:03'), isNot(contains('노쇼')));
  });

  testWidgets('WF-4 옛 근태 + 두 근무 — 어느 행에도 붙이지 않고 근태 미확인, 수정 입구 없음',
      (t) async {
    final zdn7 = _app('Zdn7', start: '00:00', end: '00:01', toId: 'Zdn7');
    final rube = _app('RUBE', start: '00:02', end: '00:03', toId: 'RUBE');
    await _pump(
        t,
        _Server([zdn7, rube], [
          _att('', checkIn: _kstAt(0, 2), checkOut: _kstAt(0, 3)),
        ]));
    final zRow = _rowOf(t, '00:00–00:01');
    final rRow = _rowOf(t, '00:02–00:03');
    for (final r in [zRow, rRow]) {
      expect(r, contains('근태 미확인'), reason: r);
      expect(r, isNot(contains('퇴근 완료')), reason: r);
      final cells = r.split(' | ');
      for (final action in const ['근태 처리', '근태 확인', '확인', '수정', '상세']) {
        expect(cells, isNot(contains(action)),
            reason: '모호한 근무에는 수정 입구가 없다: $r');
      }
    }
    expect(_kpi(t, '출근'), 0, reason: '모르는 것을 출근으로 세지 않는다');
    expect(_kpi(t, '미출근'), 0, reason: '모르는 것을 미출근으로 세지 않는다');
  });

  test('WF-5 KST 날짜 픽스처가 화면의 오늘과 같은 축이다(하네스 자기검증)', () {
    expect(FormatHelper.toKstDate(_kstMidnight()),
        FormatHelper.toKstDate(DateTime.now()));
  });
}
