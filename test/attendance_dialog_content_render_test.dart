import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:ALfit/models/core/application_model.dart';
import 'package:ALfit/models/core/attendance_model.dart';
import 'package:ALfit/models/core/business_model.dart';
import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/models/ui/day_staffing_row.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/widgets/common/app_checkbox.dart';
import 'package:ALfit/utils/format_helper.dart';
import 'package:ALfit/screens/business_admin/dialogs/attendance_reads.dart';
import 'package:ALfit/screens/business_admin/dialogs/attendance_status_dialog.dart';

/// [R7-P1-3 P13-R] **정상 명단**을 실제로 그린다.
///
///   첫 보고의 렌더 증거는 조회 실패 경로뿐이었다. 여기서는 `AttendanceReads`
///   경계만 갈아끼워 production 로드·분류·탭·업무 그룹·행·액션 구성을 그대로
///   돌린다. 테스트용 카드나 계산식을 따로 만들지 않는다.
///
///   대표 콘텐츠: 한 사람이 **다른 업무 2건**을 가진 데이터 + 출근 전/출근/퇴근
///   섞인 행 + 긴 이름·긴 업무명.

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
final _day = DateTime(2026, 9, 28); // 달력에서 고른 날(civil day)
final _dayKey = FormatHelper.kstDayKeyOfCivil(_day);

/// CF 가 Timestamp 를 내려보내는 모양 — `parseTimestamp` 가 이것을 받는다.
Map<String, dynamic> _ts(DateTime d) =>
    {'_seconds': d.millisecondsSinceEpoch ~/ 1000, '_nanoseconds': 0};

/// CF 페이징 helper 가 돌려주는 모양(파싱 전 Map).
Map<String, dynamic> _appMap({
  required String id,
  required String uid,
  required String wdId,
  String? workDetailId,
  required String workType,
  required String start,
  required String end,
}) =>
    {
      'id': id,
      'uid': uid,
      'toId': 'to1',
      'slotId': 'slot1',
      'businessId': _biz,
      'wdId': wdId,
      if (workDetailId != null) 'workDetailId': workDetailId,
      'status': 'CONFIRMED',
      'type': 'short_term',
      'selectedWorkType': workType,
      'startTime': start,
      'endTime': end,
      'workDate': _ts(_dayKey),
      'createdAt': _ts(_dayKey),
      'appliedAt': _ts(_dayKey),
    };

Map<String, dynamic> _attMap({
  required String id,
  required String applicationId,
  String? checkIn,
  String? checkOut,
  required String status,
}) =>
    {
      'id': id,
      'applicationId': applicationId,
      'uid': 'u-long',
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
      name: '아주아주 긴 이름의 테스트 사업장 주식회사',
      businessNumber: '000-00-00000',
      category: '음식점',
      subCategory: '한식',
      address: '서울특별시 강남구 테헤란로 1',
      ownerId: 'owner1',
      createdAt: DateTime(2026, 1, 1),
    );

/// 정상 조회 + 대표 혼합 명단. `fail` 이 true 면 첫 호출만 실패시킨다.
AttendanceReads _reads({bool failFirstLoad = false}) {
  var calls = 0;
  const longType = '홀서빙 및 매장 정리(오후 피크타임 집중 근무)';
  return AttendanceReads(
    applicationsPaged: (payload) async {
      if (failFirstLoad && calls++ == 0) {
        throw StateError('조회 실패(테스트)');
      }
      // 장기 호출은 빈 목록 — 이 fixture 는 단기만 쓴다.
      if (payload['type'] != null) return const [];
      return [
        // 같은 사람(u-long)이 다른 업무 2건 — 상단 건수와 그룹 인원이 갈린다.
        _appMap(id: 'a1', uid: 'u-long', wdId: 'wd1', workType: longType,
            workDetailId: 'wd-a', start: '09:00', end: '13:00'),
        _appMap(id: 'a2', uid: 'u-long', wdId: 'wd2', workType: '주방 보조',
            workDetailId: 'wd-b', start: '14:00', end: '18:00'),
        _appMap(id: 'a3', uid: 'u2', wdId: 'wd1', workType: longType,
            workDetailId: 'wd-a', start: '09:00', end: '13:00'),
      ];
    },
    workTypeDocs: (_) async => const {},
    adminAttendances: ({required businessId, required startMs, required endMs}) async => [
      // a1: 출근만 / a3: 퇴근까지 / a2: 기록 없음(출근 전)
      _attMap(id: 'att1', applicationId: 'a1', checkIn: '09:02', status: 'CHECKED_IN'),
      _attMap(id: 'att3', applicationId: 'a3', checkIn: '08:58', checkOut: '13:05',
          status: 'CHECKED_OUT'),
    ],
    workDetailTimes: (_) async => const {},
    usersBatch: ({required uids, required businessId}) async => {
      'u-long': _user('u-long', '김아주아주긴이름테스트'),
      'u2': _user('u2', '박둘'),
    },
    contractStatus: ({required appIds, required businessId}) async =>
        {for (final id in appIds) id: 'signed'},
    dayStaffing: ({required businessId, required dayStartMs}) async =>
        const <DayStaffingRow>[],
    businessById: (_) async => _business(),
    businessNames: (ids) async => {for (final i in ids) i: _business().name},
  );
}

/// [R7-P1-3] **workDetailId 가 없는 구 문서** 형태. 같은 uid 의 서로 다른 관계 2건이
///   같은 슬롯에 있으면 `wdSeg` 가 빈 문자열이라 **한 그룹**으로 합쳐진다.
///   그래서 그 자리의 숫자는 인원이 아니라 관계(근무 건) 수다.
AttendanceReads _legacyReads() => AttendanceReads(
      applicationsPaged: (payload) async {
        if (payload['type'] != null) return const [];
        return [
          _appMap(id: 'L1', uid: 'u-legacy', wdId: 'wdA', workType: '홀서빙',
              start: '09:00', end: '13:00'),
          _appMap(id: 'L2', uid: 'u-legacy', wdId: 'wdB', workType: '주방 보조',
              start: '14:00', end: '18:00'),
        ];
      },
      workTypeDocs: (_) async => const {},
      adminAttendances: ({required businessId, required startMs, required endMs}) async =>
          const [],
      workDetailTimes: (_) async => const {},
      usersBatch: ({required uids, required businessId}) async =>
          {'u-legacy': _user('u-legacy', '한사람두관계')},
      contractStatus: ({required appIds, required businessId}) async =>
          {for (final id in appIds) id: 'signed'},
      dayStaffing: ({required businessId, required dayStartMs}) async =>
          const <DayStaffingRow>[],
      businessById: (_) async => _business(),
      businessNames: (ids) async => {for (final i in ids) i: _business().name},
    );

Future<void> _pump(
  WidgetTester tester, {
  required Size size,
  required AttendanceReads reads,
  double textScale = 1.0,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ChangeNotifierProvider<UserProvider>(
      create: (_) => UserProvider(),
      child: MaterialApp(
        builder: (ctx, child) => MediaQuery(
          data: MediaQuery.of(ctx).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
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
}

/// 탭을 눌러 그 탭의 행을 그린다 — production TabBar 동작 그대로.
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

  testWidgets('ACR-1 정상 명단이 로드되고 상단 수치가 건 단위로 그려진다', (tester) async {
    await _pump(tester, size: const Size(390, 780), reads: _reads());

    expect(tester.takeException(), isNull);
    expect(find.text('당일명단'), findsOneWidget);
    expect(find.textContaining('09월 28일'), findsOneWidget);
    // 정상 조회 + 결과 있음 → "확정된 근무자가 없습니다"(조회 0건)가 아니다.
    expect(find.text('확정된 근무자가 없습니다'), findsNothing);
    expect(find.text('명단을 확인하지 못했습니다'), findsNothing);
    // 상단 통계가 **건** 으로 말한다(fixture: 확정 3 / 출근 2 / 미출근 1).
    expect(find.text('3건'), findsWidgets);
    expect(find.text('2건'), findsWidgets);
    expect(find.text('1건'), findsWidgets);
    expect(find.text('0/3건'), findsOneWidget);
    // 명단을 아는 상태이므로 명단 전제 행동이 열린다.
    expect(find.text('명단 출력'), findsOneWidget);
  });

  testWidgets('ACR-2 정상 탭에 행이 그려지고, 업무 그룹은 사람 수로 센다', (tester) async {
    await _pump(tester, size: const Size(390, 780), reads: _reads());
    // 기본 탭은 '확인필요'(0건) — 그 탭의 빈 문구는 조회 0건과 다른 말이다.
    expect(find.text('해당 근무자가 없습니다'), findsOneWidget);

    await _openTab(tester, '정상');
    expect(tester.takeException(), isNull);
    // 실제 행이 그려진다 — 긴 이름도 포함.
    expect(find.textContaining('김아주아주긴이름'), findsWidgets);
    expect(find.textContaining('박둘'), findsWidgets);
    // 같은 사람(u-long)이 **다른 업무 2건** → 업무 그룹이 둘로 갈린다.
    //   그룹 키의 조각은 workDetailId 다(index 기준: businessId|toId|slotId|workDetailId).
    //   첫 그룹 헤더는 업무명·시간과 '출근 n/m'(그 그룹 기준)을 말한다.
    expect(find.textContaining('홀서빙 및 매장 정리'), findsWidgets);
    //   a1·a3 둘 다 출근 기록이 있다 → 그 그룹은 2/2.
    expect(find.text('출근 2/2'), findsOneWidget);
    // 동질 그룹(같은 업무·시간)은 기존 표현 그대로 — 혼합 문구가 끼지 않는다.
    expect(find.textContaining('여러 업무'), findsNothing);
    // 두 번째 업무 그룹은 아래에 있다 — 스크롤해서 같은 사람이 또 나오는지 본다.
    await tester.drag(find.text('상태순').first, const Offset(0, -400));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('주방 보조'), findsWidgets);
  });

  testWidgets('ACR-3 좁은 폭 + 큰 글자에서도 행이 그려지고 overflow 가 없다',
      (tester) async {
    await _pump(tester, size: const Size(320, 640), reads: _reads(), textScale: 1.3);
    await _openTab(tester, '정상');
    expect(tester.takeException(), isNull);
    expect(find.textContaining('김아주아주긴이름'), findsWidgets);
    // 마지막 행까지 스크롤로 닿는다.
    await tester.drag(find.textContaining('김아주아주긴이름').first, const Offset(0, -260));
    await tester.pump(const Duration(milliseconds: 200));
    expect(tester.takeException(), isNull);
  });

  testWidgets('ACR-4 실패 → 재시도 → 정상 목록', (tester) async {
    await _pump(tester, size: const Size(390, 780), reads: _reads(failFirstLoad: true));

    // 1) 실패: 조회 0건으로 말하지 않고, 명단 전제 행동도 열지 않는다.
    expect(find.text('확정된 근무자가 없습니다'), findsNothing);
    expect(find.text('명단 출력'), findsNothing);
    final retry = find.text('다시 시도');
    expect(retry, findsOneWidget);

    // 2) 재시도 → 정상 목록
    await tester.tap(retry);
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(tester.takeException(), isNull);
    expect(find.text('명단 출력'), findsOneWidget);
    await _openTab(tester, '정상');
    expect(find.textContaining('김아주아주긴이름'), findsWidgets);
  });

  testWidgets('ACR-5 구 문서(workDetailId 없음) — 한 사람의 두 관계가 한 그룹, 숫자는 건',
      (tester) async {
    await _pump(tester, size: const Size(390, 780), reads: _legacyReads());
    expect(tester.takeException(), isNull);

    // 상단: 관계 2건.
    expect(find.text('2건'), findsWidgets);
    expect(find.text('0/2건'), findsOneWidget);

    // 두 관계가 모두 살아 있다 — 행을 지우거나 합치지 않았다.
    // 출근 전(미출근)은 '정상' 탭에 있다 — 확인필요가 아니다.
    await _openTab(tester, '정상');
    expect(find.textContaining('한사람두관계'), findsNWidgets(2));
    // [R7-P1-3] 혼합 그룹 헤더는 **첫 업무로 대표하지 않는다**.
    expect(find.text('여러 업무 2종'), findsOneWidget);
    expect(find.textContaining('시간 2종'), findsOneWidget);
    // 두 관계를 행에서 각각 식별할 수 있다 — 업무명 · 예정 시간.
    expect(find.text('홀서빙 · 09:00 ~ 13:00'), findsOneWidget);
    expect(find.text('주방 보조 · 14:00 ~ 18:00'), findsOneWidget);

    // 그룹 헤더의 분자/분모는 같은 단위(관계)다 — 아직 아무도 출근하지 않았다.
    expect(find.text('출근 0/2'), findsOneWidget);
  });

  testWidgets('ACR-6 혼합 그룹 문맥이 좁은 폭·큰 글자에서도 가려지지 않는다',
      (tester) async {
    await _pump(tester, size: const Size(320, 640), reads: _legacyReads(), textScale: 1.3);
    await _openTab(tester, '정상');
    expect(tester.takeException(), isNull);

    // 두 관계의 문맥이 각각 보인다(줄바꿈/축약이 필수 정보를 지우지 않는다).
    expect(find.text('홀서빙 · 09:00 ~ 13:00'), findsOneWidget);
    expect(find.text('주방 보조 · 14:00 ~ 18:00'), findsOneWidget);
    // 행동 버튼에 닿는다.
    expect(find.text('출근'), findsWidgets);
    // 마지막 행까지 스크롤된다.
    await tester.drag(find.text('상태순').first, const Offset(0, -260));
    await tester.pump(const Duration(milliseconds: 200));
    expect(tester.takeException(), isNull);
  });

  testWidgets('ACR-7 개별 선택이 그 관계(applicationId)에 붙는다', (tester) async {
    await _pump(tester, size: const Size(390, 780), reads: _legacyReads());
    await _openTab(tester, '정상');

    // L2(주방 보조) 행의 체크박스만 누른다 — 문맥 줄로 그 행을 특정한다.
    //   카드 탭은 상세 열기이고, 선택은 별도 GestureDetector 다(production 구조).
    final l2Row = find.ancestor(
      of: find.text('주방 보조 · 14:00 ~ 18:00'),
      matching: find.byType(Material),
    );
    expect(l2Row, findsWidgets);
    final l2Check = find.descendant(of: l2Row.first, matching: find.byType(AppCheckbox));
    expect(l2Check, findsOneWidget);
    await tester.tap(l2Check);
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);

    // 선택은 **그 관계 하나**에만 붙는다 — 같은 사람의 다른 관계까지 묶이지 않는다.
    final checked = tester
        .widgetList<AppCheckbox>(find.byType(AppCheckbox))
        .where((c) => c.value)
        .length;
    expect(checked, 1);
    // 그리고 그 행은 주방 보조 관계다.
    final selectedRow = find.ancestor(
      of: find.text('주방 보조 · 14:00 ~ 18:00'),
      matching: find.byType(Material),
    );
    final selectedCheck = tester.widget<AppCheckbox>(
        find.descendant(of: selectedRow.first, matching: find.byType(AppCheckbox)));
    expect(selectedCheck.value, isTrue);
  });
}
