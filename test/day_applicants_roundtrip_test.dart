import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';

import 'package:ALfit/models/core/application_model.dart';
import 'package:ALfit/models/core/attendance_model.dart';
import 'package:ALfit/models/core/business_model.dart';
import 'package:ALfit/models/core/to_model.dart';
import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/models/core/work_detail_data.dart';
import 'package:ALfit/models/ui/day_staffing_row.dart';
import 'package:ALfit/utils/format_helper.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/screens/business_admin/dialogs/day_applicants_dialog.dart';
import 'package:ALfit/screens/business_admin/dialogs/day_applicants_reads.dart';

/// [R8 O03] **실제 `DayApplicantsDialog` 을 띄워서** 날짜 왕복을 확인한다.
///
///   7차에는 "한 번 로드에 서비스 호출이 10개라 최소 seam 이 안 된다"고 적었다.
///   그건 의존성 규모의 설명이고 불가의 증거가 아니었다. 읽는 경계를
///   `DayApplicantsReads` 한 곳에 모으니 화면은 그대로 두고 바깥만 갈아끼울 수
///   있다. 그룹 구성·캐시·상단 수치·scope label 은 여전히 production State 가 한다.
///
///   navigation 구조가 날짜마다 새 인스턴스를 여는 형태이므로, 그 구조 그대로
///   열고 닫고 다시 연다.

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

BusinessModel _business() => BusinessModel(
      id: _biz,
      name: '테스트 사업장',
      businessNumber: '000-00-00000',
      category: '음식점',
      subCategory: '한식',
      address: '서울특별시 강남구 테헤란로 1',
      ownerId: 'owner1',
      createdAt: DateTime(2026, 9, 1),
    );

ApplicationModel _app({
  required String id,
  required String uid,
  required DateTime date,
  required String status,
  String toId = 'to1',
  String slotId = 'slot1',
  String wdId = 'wd1',
  String workType = '홀서빙',
  String start = '09:00',
  String end = '18:00',
}) =>
    ApplicationModel(
      id: id,
      uid: uid,
      toId: toId,
      slotId: slotId,
      businessId: _biz,
      businessName: '테스트 사업장',
      toTitle: '테스트 공고',
      selectedWorkType: workType,
      wdId: wdId,
      startTime: start,
      endTime: end,
      wage: 12000,
      wageType: 'hourly',
      status: status,
      workDate: date,
      appliedAt: date,
    );

DayStaffingRow _row({
  required int required_,
  required int confirmed,
  String toId = 'to1',
  String slotId = 'slot1',
  String wdId = 'wd1',
}) =>
    DayStaffingRow(
      toId: toId,
      toTitle: '테스트 공고',
      slotId: slotId,
      wdId: wdId,
      workType: '홀서빙',
      startTime: '09:00',
      endTime: '18:00',
      requiredCount: required_,
      confirmedCount: confirmed,
      pendingCount: 0,
    );

/// 화면이 넘기는 KST 하루 시작 instant → 날짜 키. 화면과 같은 규칙을 쓴다.
int _dayKeyOfStartMs(int ms) {
  final d = FormatHelper.kstDayRange(
      DateTime.fromMillisecondsSinceEpoch(ms)).$1;
  return d.year * 10000 + d.month * 100 + d.day;
}

/// 날짜별로 다른 수치를 주는 읽기 경계. 지연·실패도 여기서 만든다.
class _Reads {
  _Reads({required this.byDate});

  /// 날짜 → (대기, 확정, 충원행)
  final Map<int, ({List<ApplicationModel> pending, List<ApplicationModel> confirmed, List<DayStaffingRow>? rows})> byDate;

  final List<String> calls = [];
  Completer<void>? gate;
  bool failStaffing = false;
  bool failPending = false;

  int _key(DateTime d) => d.year * 10000 + d.month * 100 + d.day;

  DayApplicantsReads build() => DayApplicantsReads(
        pendingApplications: ({required date, required businessId, purpose}) async {
          calls.add('pending:${_key(date)}');
          if (gate != null) await gate!.future;
          if (failPending) throw StateError('pending read failed');
          return byDate[_key(date)]?.pending ?? const [];
        },
        confirmedWorkers: ({required date, required businessId}) async {
          calls.add('confirmed:${_key(date)}');
          if (gate != null) await gate!.future;
          return byDate[_key(date)]?.confirmed ?? const [];
        },
        dayStaffing: ({required businessId, required dayStartMs}) async {
          // 화면이 `FormatHelper.kstDayRange(date).$1` 을 넘긴다 — 그 값으로
          // 어느 날짜를 물었는지 되짚는다.
          final k = _dayKeyOfStartMs(dayStartMs);
          calls.add('staffing:$k');
          if (failStaffing) throw StateError('staffing read failed');
          return byDate[k]?.rows ?? const [];
        },
        dayInvitations: ({required date, required businessId}) async => const [],
        hasWorkedMap: ({required businessId, required date}) async => const {},
        noShowApplicationIds: ({required businessId, required date}) async =>
            <String>{},
        usersBatch: (uids, {required businessId, purpose}) async => {
          for (final u in uids)
            u: UserModel(uid: u, username: u, name: '근로자 $u',
                email: '$u@test.local', role: UserRole.USER),
        },
        weeklyAttendance: ({required businessId, required weekStart,
                required weekEnd}) async =>
            <String, List<AttendanceModel>>{},
        slotWorkDetailCapacities: (toId, slotId) async => const {'wd1': 1},
        slotWorkDetails: (toId, slotId) async => <WorkDetailData>[],
        to: (toId) async => null,
        contractStatusBatch: (ids, {required businessId}) async =>
            <String, String?>{},
      );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
  });

  final d929 = DateTime(2026, 9, 29);
  final d930 = DateTime(2026, 9, 30);

  _Reads makeReads() => _Reads(byDate: {
        20260929: (
          pending: [_app(id: 'a1', uid: 'u1', date: d929, status: 'PENDING')],
          confirmed: [
            _app(id: 'a2', uid: 'u2', date: d929, status: 'CONFIRMED')
          ],
          rows: [_row(required_: 1, confirmed: 1)],
        ),
        20260930: (
          pending: const [],
          confirmed: const [],
          rows: [_row(required_: 1, confirmed: 0)],
        ),
      });

  /// 실제 navigation 구조 그대로 — 날짜마다 새 인스턴스를 연다.
  Future<void> openDay(
    WidgetTester tester, {
    required DateTime date,
    required DayApplicantsReads reads,
  }) async {
    await tester.pumpWidget(ChangeNotifierProvider<UserProvider>(
      create: (_) => UserProvider(),
      child: MaterialApp(
        home: Scaffold(
          body: DayApplicantsDialog(
            // 실제 navigation 은 날짜마다 새 인스턴스를 연다.
            // 같은 State 를 재사용하면 그 구조가 아니다.
            key: ValueKey(date),
            date: date,
            businessIds: const [_biz],
            businesses: [_business()],
            reads: reads,
          ),
        ),
      ),
    ));
    // 로드는 여러 단계로 나뉘어 있다 — 정착할 때까지 돌린다.
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  /// 다이얼로그로 띄운 경우에도 같은 방식으로 정착시킨다.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  String texts(WidgetTester tester) => tester
      .widgetList<Text>(find.byType(Text))
      .map((t) => t.data ?? t.textSpan?.toPlainText() ?? '')
      .where((s) => s.isNotEmpty)
      .join(' | ');

  testWidgets('DAY-1 9/29 → 9/30 → 9/29 — 날짜별 수치가 섞이지 않는다',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final r = makeReads();

    await openDay(tester, date: d929, reads: r.build());
    final t929 = texts(tester);
    expect(t929, contains('인력 현황'));
    expect(t929, contains('9월 29일'), reason: 'scope label 의 날짜');
    expect(t929, contains('1건'), reason: '지원·확정이 각각 1건');

    // 9/30 — 다른 수치
    await openDay(tester, date: d930, reads: r.build());
    final t930 = texts(tester);
    expect(t930, contains('9월 30일'));
    expect(t930, contains('0건'), reason: '지원 0 · 확정 0');
    expect(t930, isNot(contains('9월 29일')));

    // 9/29 복귀
    await openDay(tester, date: d929, reads: r.build());
    final back = texts(tester);
    expect(back, contains('9월 29일'));
    expect(back, contains('1건'));

    // 실제로 날짜별 읽기가 갔다.
    expect(r.calls.where((c) => c.startsWith('pending:')).toList(),
        ['pending:20260929', 'pending:20260930', 'pending:20260929']);
  });

  testWidgets('DAY-2 닫기 → 진입점 복귀 → 다시 열기', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final r = makeReads();
    final reads = r.build();

    await tester.pumpWidget(ChangeNotifierProvider<UserProvider>(
      create: (_) => UserProvider(),
      child: MaterialApp(
        home: Builder(builder: (ctx) {
          return Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => showDialog<void>(
                  context: ctx,
                  barrierDismissible: false,
                  builder: (_) => DayApplicantsDialog(
                    date: d929,
                    businessIds: const [_biz],
                    businesses: [_business()],
                    reads: reads,
                  ),
                ),
                child: const Text('명단 보기'),
              ),
            ),
          );
        }),
      ),
    ));

    // 열기
    await tester.tap(find.text('명단 보기'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(texts(tester), contains('인력 현황'));
    expect(texts(tester), contains('1건'));

    // 닫기 → 진입점으로 복귀
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    navigator.pop();
    await tester.pumpAndSettle();
    expect(find.text('명단 보기'), findsOneWidget);
    expect(texts(tester), isNot(contains('인력 현황')));

    // 다시 열기 — 같은 값이 다시 나온다
    await tester.tap(find.text('명단 보기'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(texts(tester), contains('인력 현황'));
    expect(texts(tester), contains('1건'));
    // 다시 열 때 다시 읽는다 — stale 캐시를 재사용하지 않는다.
    expect(r.calls.where((c) => c == 'pending:20260929').length, 2);
  });

  testWidgets('DAY-3 지연된 A 응답이 B 화면을 덮지 않는다', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    // A(9/29) 를 열고 응답을 붙잡아 둔 뒤 B(9/30) 로 넘어간다.
    final rA = makeReads()..gate = Completer<void>();
    await openDay(tester, date: d929, reads: rA.build());
    // 아직 응답이 오지 않았다 — 수치를 0 으로 단정하지 않아야 한다.
    expect(texts(tester), contains('인력 현황'));

    final rB = makeReads();
    await openDay(tester, date: d930, reads: rB.build());
    expect(texts(tester), contains('9월 30일'));

    // 이제 A 의 늦은 응답이 도착한다.
    rA.gate!.complete();
    await tester.pump(const Duration(milliseconds: 300));

    final after = texts(tester);
    expect(after, contains('9월 30일'), reason: '늦은 A 응답이 B 화면을 덮었다');
    expect(after, isNot(contains('9월 29일')));
  });

  testWidgets('DAY-4 충원 읽기 실패는 UNKNOWN 이고 0 이 아니다', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final r = makeReads()..failStaffing = true;
    await openDay(tester, date: d929, reads: r.build());
    final t = texts(tester);
    // 지원자 명단은 살아 있다 — 전체를 ERROR 로 만들지 않는다.
    expect(t, contains('인력 현황'));
    expect(t, contains('1건'));
    // 충원 축은 모른다고 말한다 — scope label 이 업무 수를 단정하지 않는다.
    expect(t, contains('9월 29일'));
    expect(t, isNot(contains('부족 0명')),
        reason: '못 읽은 충원을 0 으로 적으면 그게 그 증상이다');

    // 재시도: 성공하는 경계로 다시 열면 값이 나온다.
    final ok = makeReads();
    await openDay(tester, date: d929, reads: ok.build());
    expect(texts(tester), contains('1건'));
  });
}
