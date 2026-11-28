import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/visible_text.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:ALfit/services/contract_service.dart';
import 'package:ALfit/models/core/business_model.dart';
import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/models/ui/day_staffing_row.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/utils/format_helper.dart';
import 'package:ALfit/screens/business_admin/dialogs/attendance_reads.dart';
import 'package:ALfit/screens/business_admin/dialogs/attendance_status_dialog.dart';

/// [RECONFIRM-ADMIN-BADGE] 출근한 사람에게 "미응답"을 붙이지 않는다.
///
///   리컨펌 요청(전날 21:00)에 응답하지 않아도 출근은 막히지 않는다. 그리고
///   `reconfirmStatus` 는 출퇴근으로 바뀌지 않는다 — 출근·퇴근이 끝난 지원서도
///   `pending` 으로 남는다. 관리자 근태 다이얼로그는 이 값만 보고 "미응답"
///   배지를 그렸다. 퇴근까지 마친 행에 "미응답"이 붙으면 관리자는 출근 의사를
///   아직 모르는 사람으로 읽는다.
///
///   판정 재료는 화면이 이미 가진 `_attendanceMap[app.id]`(그 지원서의 근태)
///   뿐이다 — 새 조회를 더하지 않는다. 지원서의 `reconfirmStatus` 는 그대로다.
///
///   고정하는 것 (AttendanceReads 경계만 바꿔 production 화면을 그린다)
///     RAB-1  출근 전 pending → "미응답" 유지
///     RAB-2  출근 후 pending → "미응답" 없음
///     RAB-3  퇴근 후 pending → "미응답" 없음
///     RAB-4  응답한 지원서(confirmed) → "출근확인" 유지
///     RAB-5  다른 지원서의 근태가 섞여도 자기 근태만 본다

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
  Future<FirebaseAppPlatform> initializeApp({
    String? name,
    FirebaseOptions? options,
  }) async =>
      _FakeApp();
  @override
  List<FirebaseAppPlatform> get apps => [_FakeApp()];
}

const _biz = 'biz1';
/// 선택일은 내일 — 시계에 따라 '미출근 → 확인필요' 로 탭이 갈리지 않게 한다
/// (attendance_dialog_content_render_test 와 같은 이유).
final DateTime _day = () {
  final t = DateTime.now().add(const Duration(days: 1));
  return DateTime(t.year, t.month, t.day);
}();
final _dayKey = FormatHelper.kstDayKeyOfCivil(_day);

Map<String, dynamic> _ts(DateTime d) =>
    {'_seconds': d.millisecondsSinceEpoch ~/ 1000, '_nanoseconds': 0};

Map<String, dynamic> _appMap(String id, String uid, {String? reconfirmStatus}) => {
      'id': id,
      'uid': uid,
      'toId': 'to1',
      'slotId': 'slot1',
      'businessId': _biz,
      'wdId': 'wd1',
      'workDetailId': 'wd-a',
      'status': 'CONFIRMED',
      'type': 'short_term',
      'selectedWorkType': '홀서빙',
      'startTime': '10:00',
      'endTime': '11:00',
      'workDate': _ts(_dayKey),
      'createdAt': _ts(_dayKey),
      'appliedAt': _ts(_dayKey),
      if (reconfirmStatus != null) 'reconfirmStatus': reconfirmStatus,
      if (reconfirmStatus != null) 'reconfirmSentAt': _ts(_dayKey.subtract(const Duration(hours: 3))),
    };

Map<String, dynamic> _attMap(String id, String applicationId, String uid,
        {String? checkIn, String? checkOut, required String status}) =>
    {
      'id': id,
      'applicationId': applicationId,
      'uid': uid,
      'businessId': _biz,
      'status': status,
      if (checkIn != null) 'checkIn': checkIn,
      if (checkOut != null) 'checkOut': checkOut,
      'workDate': _ts(_dayKey),
      'createdAt': _ts(_dayKey),
    };

UserModel _user(String uid, String name) => UserModel(
      uid: uid,
      username: name,
      name: name,
      email: '$uid@example.com',
      role: UserRole.USER,
      createdAt: DateTime(2026, 1, 1),
    );

BusinessModel _business() => BusinessModel(
      id: _biz,
      name: '테스트 사업장',
      businessNumber: '000-00-00000',
      category: '음식점',
      subCategory: '한식',
      address: '서울특별시 강남구 테헤란로 1',
      ownerId: 'owner1',
      createdAt: DateTime(2026, 1, 1),
    );

AttendanceReads _reads({
  required List<Map<String, dynamic>> apps,
  required List<Map<String, dynamic>> atts,
  required Map<String, String> names,
}) =>
    AttendanceReads(
      applicationsPaged: (payload) async => payload['type'] != null ? const [] : apps,
      workTypeDocs: (_) async => const {},
      adminAttendances: ({required businessId, required startMs, required endMs}) async => atts,
      workDetailTimes: (_) async => const {},
      usersBatch: ({required uids, required businessId}) async =>
          {for (final e in names.entries) e.key: _user(e.key, e.value)},
      contractStatus: ({required appIds, required businessId}) async =>
          ContractStatusBatch(statuses: {for (final id in appIds) id: 'signed'}),
      dayStaffing: ({required businessId, required dayStartMs}) async => const <DayStaffingRow>[],
      businessById: (_) async => _business(),
      businessNames: (ids) async => {for (final i in ids) i: _business().name},
    );

Future<void> _pumpAndOpen(WidgetTester tester, AttendanceReads reads, {bool openNormal = true}) async {
  tester.view.physicalSize = const Size(430, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ChangeNotifierProvider<UserProvider>(
      create: (_) => UserProvider(),
      child: MaterialApp(
        home: Scaffold(
          body: AttendanceStatusDialog(
            date: _day,
            businessIds: const [_biz],
            initialBusinessId: _biz,
            reads: reads,
          ),
        ),
      ),
    ),
  );
  for (var i = 0; i < 40; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  if (openNormal) await _openTab(tester, '정상');
}

Future<void> _openTab(WidgetTester tester, String label) async {
  await tester.tap(find.text(label));
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
    await initializeDateFormatting('ko_KR', null);
  });

  testWidgets('RAB-1~4 출근 전만 "미응답", 출근·퇴근 뒤엔 없음, 응답한 건은 "출근확인"', (tester) async {
    await _pumpAndOpen(
      tester,
      _reads(
        apps: [
          _appMap('r0', 'u0', reconfirmStatus: 'pending'), // 출근 전
          _appMap('r1', 'u1', reconfirmStatus: 'pending'), // 출근 후
          _appMap('r2', 'u2', reconfirmStatus: 'pending'), // 퇴근 후
          _appMap('r3', 'u3', reconfirmStatus: 'confirmed'), // 응답함, 출근 전
        ],
        atts: [
          _attMap('t1', 'r1', 'u1', checkIn: '10:00', status: 'present'),
          _attMap('t2', 'r2', 'u2', checkIn: '10:00', checkOut: '11:00', status: 'present'),
        ],
        names: {'u0': '영출근전', 'u1': '일출근후', 'u2': '이퇴근후', 'u3': '삼응답함'},
      ),
    );
    expect(tester.takeException(), isNull);
    for (final n in ['영출근전', '일출근후', '이퇴근후', '삼응답함']) {
      expect(findVisibleTextContaining(n), findsWidgets, reason: '$n 행이 그려진다');
    }
    // RAB-1 + RAB-2 + RAB-3: pending 3건 중 출근 전(r0) 1건만 "미응답"
    expect(find.text('미응답'), findsOneWidget);
    // RAB-4: 다른 상태 배지는 그대로
    expect(find.text('출근확인'), findsOneWidget);
  });

  // RAB-6 배포 응답 모양 그대로 — callableGetAdminAttendances 00099 는 Timestamp 를
  //   serializeFirestoreData 로 `{_seconds, _nanoseconds}` 맵으로 내리고(비급여 권한이면
  //   NONWAGE_TOP_LEVEL_ALLOWLIST 로 applicationId·checkIn·status 등만 남긴다), 플랫폼
  //   채널을 지난 중첩 맵은 `Map<Object?, Object?>` 다. production 어댑터는 바깥만
  //   `Map<String, dynamic>.from` 한다 — 그 모양을 그대로 실제 파서(AttendanceModel.tryFromMap)에 넣는다.
  testWidgets('RAB-6 배포 응답 모양(Timestamp 맵)이 실제 파서를 지나 배지까지 이어진다', (tester) async {
    Map<Object?, Object?> tsWire(DateTime d) =>
        <Object?, Object?>{'_seconds': d.millisecondsSinceEpoch ~/ 1000, '_nanoseconds': 0};
    final checkInInstant = _dayKey.add(const Duration(hours: 10)); // 그날 10:00 KST
    // 비급여 권한 allowlist 에 있는 키만 싣는다(id 는 서버가 따로 붙인다).
    Map<String, dynamic> wire(Map<Object?, Object?> raw) => Map<String, dynamic>.from(raw);
    final items = [
      wire(<Object?, Object?>{
        'id': 'w1_20261020', 'applicationId': 'w1', 'userId': 'x1', 'businessId': _biz,
        'workDate': tsWire(_dayKey), 'checkIn': tsWire(checkInInstant), 'originalCheckIn': tsWire(checkInInstant),
        'checkInMethod': 'gps', 'status': 'present', 'wageStatus': 'pending', 'checkInDistance': 3,
        'createdAt': tsWire(checkInInstant),
      }),
      // 출근 기록이 없는 근태 문서(초기화 뒤 형태) — checkIn 키 없음
      wire(<Object?, Object?>{
        'id': 'w2_20261020', 'applicationId': 'w2', 'userId': 'x2', 'businessId': _biz,
        'workDate': tsWire(_dayKey), 'wageStatus': 'pending', 'createdAt': tsWire(_dayKey),
      }),
      // 명단 밖 지원서의 출근 — w3 의 것이 아니다
      wire(<Object?, Object?>{
        'id': 'zz_20261020', 'applicationId': 'not-listed', 'userId': 'x3', 'businessId': _biz,
        'workDate': tsWire(_dayKey), 'checkIn': tsWire(checkInInstant), 'checkInMethod': 'gps',
        'status': 'present', 'wageStatus': 'pending', 'createdAt': tsWire(checkInInstant),
      }),
    ];
    await _pumpAndOpen(
      tester,
      _reads(
        apps: [
          _appMap('w1', 'x1', reconfirmStatus: 'pending'), // 출근 기록 있음 → 숨김
          _appMap('w2', 'x2', reconfirmStatus: 'pending'), // 근태 문서는 있으나 출근 없음 → 유지
          _appMap('w3', 'x3', reconfirmStatus: 'pending'), // 자기 근태 없음(남의 것만) → 유지
        ],
        atts: items,
        names: {'x1': '육배포출근', 'x2': '칠출근없음', 'x3': '팔남의근태'},
      ),
      openNormal: false,
    );
    expect(tester.takeException(), isNull);
    // 행은 상태에 따라 탭이 갈린다 — 탭마다 그려진 행과 배지를 모은다(합계로 판정).
    final rows = <String>{};
    var pendingBadges = 0;
    var gpsBadges = 0;
    void collect() {
      for (final n in ['육배포출근', '칠출근없음', '팔남의근태']) {
        if (findVisibleTextContaining(n).evaluate().isNotEmpty) rows.add(n);
      }
      pendingBadges += find.text('미응답').evaluate().length;
      gpsBadges += findVisibleText('GPS').evaluate().length;
    }
    collect(); // 기본 탭(확인필요)
    for (final tab in ['정상', '확인완료', '처리완료']) {
      await _openTab(tester, tab);
      collect();
    }
    expect(tester.takeException(), isNull);
    expect(rows, {'육배포출근', '칠출근없음', '팔남의근태'}, reason: '세 행이 어느 탭에든 그려진다');
    expect(pendingBadges, 2, reason: 'w2(출근 기록 없음)·w3(자기 근태 없음)만 미응답'); // w1 숨김
    // 같은 행의 출근 방식 배지가 같은 근태(w1)를 읽었다 — 파서가 Timestamp 맵 checkIn 을 살렸다는 대조
    expect(gpsBadges, 1);
  });

  testWidgets('RAB-5 다른 지원서의 근태가 섞여도 자기 근태만 본다', (tester) async {
    await _pumpAndOpen(
      tester,
      _reads(
        apps: [
          _appMap('m1', 'v1', reconfirmStatus: 'pending'), // 자기 근태 없음
          _appMap('m2', 'v2'), // 리컨펌 필드 없음, 출근함
        ],
        atts: [
          // m2 의 근태 + 명단 밖 지원서의 근태(같은 사람 v1) — 둘 다 m1 의 것이 아니다
          _attMap('s2', 'm2', 'v2', checkIn: '10:00', status: 'present'),
          _attMap('sx', 'other-app', 'v1', checkIn: '10:00', status: 'present'),
        ],
        names: {'v1': '사본인없음', 'v2': '오남의근태'},
      ),
    );
    expect(tester.takeException(), isNull);
    expect(findVisibleTextContaining('사본인없음'), findsWidgets);
    expect(find.text('미응답'), findsOneWidget); // m1 은 아직 출근 전 → 유지
    expect(find.text('출근확인'), findsNothing);
  });
}
