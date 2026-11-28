// [PERF impl_25 · L48 · 2026-11-27] 날짜별 지원명단 다이얼로그 — 읽기 구조 전환(이번 결과를 모아 차례 확인 뒤 한 번에 커밋)
//   위에 처리 뒤 화면 유지(SWR · 잠금 · 숫자/확정 미리 표시 0).
//
//   E1 동치 — 같은 입력이면 처리 뒤 다시 읽기(명단 유지)의 최종 화면 = 처음부터 새로 연 화면
//   E2 처리 뒤 다시 읽는 중 — 전체 스피너 0 · 이전 명단 유지 · 진행 표시 · 누르기 잠금
//   E3 늦은 응답 — 먼저 시작한 읽기가 나중에 끝나도 새 결과를 덮지 않는다
//   E4 실패 — 명단을 유지한 채 읽다 실패해도 최종 상태는 예전 실패와 같다(옛 명단을 정상처럼 남기지 않는다)
//   E5 부수 결과(정원 모름) — 옛 읽기의 실패가 새 읽기의 정원 표시를 오염시키지 않는다
// ignore_for_file: depend_on_referenced_packages
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
import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/models/core/work_detail_data.dart';
import 'package:ALfit/models/ui/day_staffing_row.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/screens/business_admin/dialogs/day_applicants_dialog.dart';
import 'package:ALfit/screens/business_admin/dialogs/day_applicants_reads.dart';
import 'package:ALfit/services/contract_service.dart';

import 'support/visible_text.dart';

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
  Future<FirebaseAppPlatform> initializeApp({String? name, FirebaseOptions? options}) async =>
      _FakeApp();
  @override
  List<FirebaseAppPlatform> get apps => [_FakeApp()];
}

const _biz = 'biz1';
final _day = DateTime(2026, 9, 29);

BusinessModel _business() => BusinessModel(
      id: _biz, name: '테스트 사업장', businessNumber: '000-00-00000',
      category: '음식점', subCategory: '한식', address: '서울특별시 강남구 테헤란로 1',
      ownerId: 'owner1', createdAt: DateTime(2026, 9, 1),
    );

ApplicationModel _app(String id, String uid, String status) => ApplicationModel(
      id: id, uid: uid, toId: 'to1', slotId: 'slot1', businessId: _biz,
      businessName: '테스트 사업장', toTitle: '테스트 공고', selectedWorkType: '홀서빙',
      wdId: 'wd1', startTime: '09:00', endTime: '18:00', wage: 12000, wageType: 'hourly',
      status: status, workDate: _day, appliedAt: _day,
    );

DayStaffingRow _row(int required_, int confirmed) => DayStaffingRow(
      toId: 'to1', toTitle: '테스트 공고', slotId: 'slot1', wdId: 'wd1', workType: '홀서빙',
      startTime: '09:00', endTime: '18:00', requiredCount: required_,
      confirmedCount: confirmed, pendingCount: 0,
    );

typedef _Data = ({List<ApplicationModel> pending, List<ApplicationModel> confirmed, int required_});

final _d1 = (
  pending: [_app('a1', 'u1', 'PENDING'), _app('a3', 'u3', 'PENDING')],
  confirmed: [_app('a2', 'u2', 'CONFIRMED')],
  required_: 3,
);
// 처리 뒤: u1 확정 · u3 거절(목록에서 빠짐)
final _d2 = (
  pending: <ApplicationModel>[],
  confirmed: [_app('a2', 'u2', 'CONFIRMED'), _app('a1', 'u1', 'CONFIRMED')],
  required_: 3,
);

/// 읽기 경계 — 읽기마다 [next] 의 데이터로 답한다. [gate] 가 있으면 대기 지원자 읽기가 그 문을 기다린다.
class _Reads {
  _Reads(this.data);
  _Data data;
  final gates = <Completer<void>>[];
  bool holdNext = false;
  bool failPending = false;
  /// 정원 읽기마다 하나씩 꺼낸다 — 'ok' · 'holdThenFail'(문 [capGates] 를 기다린 뒤 실패). 비면 'ok'.
  final capPlan = <String>[];
  final capGates = <Completer<void>>[];
  int pendingCalls = 0;
  bool failStaffing = false;

  DayApplicantsReads build() => DayApplicantsReads(
        pendingApplications: ({required date, required businessId, purpose}) async {
          pendingCalls++;
          final snap = data; // 출발 시각의 데이터
          final fail = failPending;
          if (holdNext) {
            holdNext = false;
            final g = Completer<void>();
            gates.add(g);
            await g.future;
          }
          if (fail) throw StateError('pending read failed');
          return snap.pending;
        },
        confirmedWorkers: ({required date, required businessId}) async => data.confirmed,
        dayStaffing: ({required businessId, required dayStartMs}) async {
          if (failStaffing) throw StateError('staffing read failed'); // 그러면 정원 표시는 슬롯 정원 읽기에 기댄다
          return [_row(data.required_, data.confirmed.length)];
        },
        dayInvitations: ({required date, required businessId}) async => const [],
        hasWorkedMap: ({required businessId, required date}) async => const {},
        noShowApplicationIds: ({required businessId, required date}) async => <String>{},
        usersBatch: (uids, {required businessId, purpose}) async => {
          for (final u in uids)
            u: UserModel(uid: u, username: u, name: '근로자 $u', email: '$u@test.local', role: UserRole.USER),
        },
        weeklyAttendance: ({required businessId, required weekStart, required weekEnd}) async =>
            <String, List<AttendanceModel>>{},
        slotWorkDetailCapacities: (toId, slotId) async {
          final plan = capPlan.isEmpty ? 'ok' : capPlan.removeAt(0);
          if (plan == 'holdThenFail') {
            final g = Completer<void>();
            capGates.add(g);
            await g.future;
            throw StateError('capacity read failed');
          }
          return {'wd1': data.required_};
        },
        slotWorkDetails: (toId, slotId) async => <WorkDetailData>[],
        to: (toId) async => null,
        contractStatusBatch: (ids, {required businessId}) async => const ContractStatusBatch(),
      );
}

Future<void> _settle(WidgetTester t) async {
  for (var i = 0; i < 30; i++) {
    await t.pump(const Duration(milliseconds: 50));
  }
}

/// 화면을 열고, 처리 뒤 다시 읽기 함수를 돌려준다.
Future<Future<void> Function()> _open(WidgetTester t, _Reads r, {Key? key}) async {
  t.view.physicalSize = const Size(1080, 2400);
  t.view.devicePixelRatio = 3.0;
  addTearDown(t.view.reset);
  late Future<void> Function() reload;
  await t.pumpWidget(ChangeNotifierProvider<UserProvider>(
    create: (_) => UserProvider(),
    child: MaterialApp(
      home: Scaffold(
        body: DayApplicantsDialog(
          key: key ?? UniqueKey(),
          date: _day,
          businessIds: const [_biz],
          businesses: [_business()],
          reads: r.build(),
          debugReloadHook: (f) => reload = f,
        ),
      ),
    ),
  ));
  await _settle(t);
  return reload;
}

String _texts(WidgetTester t) => t
    .widgetList<Text>(find.byType(Text))
    .map((w) => visibleText(w.data ?? w.textSpan?.toPlainText() ?? ''))
    .where((s) => s.isNotEmpty)
    .join(' | ');

const _spinner = '지원·근무 현황 불러오는 중...';
const _progress = ValueKey('day-applicants-refresh-after-mutation');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
  });

  testWidgets('E1 동치 — 같은 입력이면 처리 뒤 다시 읽기의 최종 화면 = 새로 연 화면(데이터 그대로 · 바뀐 데이터 둘 다)', (t) async {
    final r = _Reads(_d1);
    final reload = await _open(t, r);
    final fresh1 = _texts(t);
    expect(fresh1, contains('근로자 u1'));
    unawaited(reload());
    await _settle(t);
    expect(_texts(t), fresh1, reason: '같은 입력인데 다시 읽은 화면이 처음과 다르다');

    r.data = _d2;
    unawaited(reload());
    await _settle(t);
    final viaReload = _texts(t);

    final r2 = _Reads(_d2);
    await _open(t, r2);
    final fresh2 = _texts(t);
    expect(viaReload, fresh2, reason: '명단을 유지한 채 다시 읽은 최종 상태가 새로 연 화면과 다르다');
    expect(viaReload, isNot(contains('근로자 u3')), reason: '처리한(빠진) 지원자가 남았다');
  });

  testWidgets('E2 처리 뒤 다시 읽는 중 — 전체 스피너 0 · 이전 명단 유지 · 진행 표시 · 누르기 잠금', (t) async {
    final r = _Reads(_d1);
    final reload = await _open(t, r);
    r.holdNext = true;
    r.data = _d2;
    unawaited(reload());
    await t.pump(const Duration(milliseconds: 100));
    expect(find.text(_spinner), findsNothing, reason: '처리 뒤 다시 읽기가 명단을 지우고 전체 스피너를 띄웠다');
    expect(find.byKey(_progress), findsOneWidget);
    expect(_texts(t), contains('근로자 u3'), reason: '새 결과가 앉기 전에 이전 명단이 사라졌다');
    final absorbing = t
        .widgetList<AbsorbPointer>(find.ancestor(
            of: findVisibleTextContaining('근로자 u3').first, matching: find.byType(AbsorbPointer)))
        .any((w) => w.absorbing);
    expect(absorbing, isTrue, reason: '처리 전 명단으로 다시 처리할 수 있다');
    r.gates.single.complete();
    await _settle(t);
    expect(find.byKey(_progress), findsNothing);
    expect(_texts(t), isNot(contains('근로자 u3')));
  });

  testWidgets('E3 늦은 응답 — 먼저 시작한 읽기(옛 데이터)가 나중에 끝나도 새 결과를 덮지 않는다', (t) async {
    final r = _Reads(_d1);
    final reload = await _open(t, r);
    r.holdNext = true; // 첫 다시 읽기: 옛 데이터(_d1)를 들고 멈춤
    unawaited(reload());
    await t.pump(const Duration(milliseconds: 50));
    r.data = _d2; // 두 번째 다시 읽기: 새 데이터
    unawaited(reload());
    await _settle(t);
    final afterSecond = _texts(t);
    expect(afterSecond, isNot(contains('근로자 u3')));
    r.gates.single.complete(); // 옛 읽기가 이제 끝난다
    await _settle(t);
    expect(_texts(t), afterSecond, reason: '늦게 끝난 옛 읽기가 새 결과를 덮었다');
    expect(find.byKey(_progress), findsNothing);
  });

  testWidgets('E4 명단 유지 중 실패 — 최종 상태는 새로 열다 실패한 화면과 같다(옛 명단을 정상처럼 남기지 않는다)', (t) async {
    final r = _Reads(_d1);
    final reload = await _open(t, r);
    r.failPending = true;
    unawaited(reload());
    await _settle(t);
    final viaReload = _texts(t);
    expect(find.byKey(_progress), findsNothing);
    expect(find.text(_spinner), findsNothing);
    expect(viaReload, isNot(contains('근로자 u3')), reason: '실패했는데 처리 전 명단이 정상처럼 남았다');

    final r2 = _Reads(_d1)..failPending = true;
    await _open(t, r2);
    expect(viaReload, _texts(t));
  });

  testWidgets('E5 정원 모름은 그 읽기의 결과로만 — 옛 읽기의 정원 실패가 새 읽기를 오염시키지 않는다', (t) async {
    final r = _Reads(_d1)..failStaffing = true; // 충원 행이 없으면 정원은 슬롯 정원 읽기 결과로만 보인다
    final reload = await _open(t, r);
    final ok = _texts(t);
    // 옛 읽기: 정원 읽기가 멈췄다가 실패 · 새 읽기: 정원 정상
    r.capPlan.addAll(['holdThenFail', 'ok']);
    unawaited(reload());
    await _settle(t);
    unawaited(reload());
    await _settle(t);
    r.capGates.single.complete(); // 옛 읽기의 정원 실패가 이제 도착
    await _settle(t);
    expect(_texts(t), ok, reason: '옛 읽기의 정원 실패가 새 읽기 화면(정원 표시)에 섞였다');
  });
}
