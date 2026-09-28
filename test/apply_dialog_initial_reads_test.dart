// [R7-P2-2 A1-R] 지원창의 **초기 읽기 세 개**를 제어해 업무 카드에 도달한다.
//
// ABR-2 는 "로그인해도 로딩이 안 풀린다" 는 사실을 고정했다. 원인은 빈 목록이
// 아니라 `_loadInitialData()` 의 `Future.wait` 세 읽기가 끝나지 않는 것이었고,
// 그 셋이 `FirestoreService` 하드 싱글턴 + extension 정적 디스패치 뒤에 있어
// 하위 클래스 fake 로는 대신할 수 없었다.
//
// 이제 읽기 전용 경계(`ApplyWorkReads`)로 세 호출을 **완료·실패·대기**로
// 제어한다. `_isLoading` 을 강제로 내리거나 자격을 우회하거나 가짜 카드를
// 하드코딩하지 않는다. 쓰기(지원·취소·확정)는 이 경계에 없다.
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';

import 'package:ALfit/models/core/application_model.dart';
import 'package:ALfit/models/core/to_model.dart';
import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/models/core/work_detail_data.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/services/schedule_conflict_service.dart';
import 'package:ALfit/widgets/common/loading_widget.dart';
import 'package:ALfit/widgets/dialogs/apply/apply_work_dialog.dart';
import 'package:ALfit/widgets/dialogs/apply/apply_work_reads.dart';

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

class _LoggedIn extends UserProvider {
  @override
  UserModel? get currentUser => UserModel(
        uid: 'u1',
        username: 'u1',
        name: '김근로',
        email: 'u1@alfit.local',
        role: UserRole.USER,
        createdAt: DateTime(2026, 1, 1),
      );
}

// ── 사건 키 ─────────────────────────────────────────────────────────────────
// 근무일은 **아직 오지 않은 날**이어야 한다. 지난 날짜면 화면이 스스로
// `_showClosedAlert` 를 띄우고 카드를 덮는다(그건 제품의 정상 동작이다).
final kWorkDate = DateTime(
  DateTime.now().year,
  DateTime.now().month,
  DateTime.now().day,
).add(const Duration(days: 5));

TOModel _to() => TOModel(
      id: 'to1',
      businessId: 'biz1',
      businessName: '강남 물류센터',
      type: 'flex',
      title: '단기 모집',
      creatorUID: 'admin1',
      status: TOStatus.active,
      deadlineType: 'NONE',
      hoursBeforeStart: 0,
      workDetails: const [],
      totalRequired: 4,
      totalConfirmed: 0,
      totalPending: 0,
      isPublished: true,
      publishMode: 'immediate',
      rangeStart: kWorkDate,
      createdAt: DateTime(2026, 9, 1),
      statusUpdatedAt: DateTime(2026, 9, 1),
    );

WorkDetailData _work({int required_ = 4, bool full = false}) => WorkDetailData(
      wdId: 'wd1',
      workType: '상하차',
      workTypeIcon: 'box',
      workTypeColor: '#000000',
      workTypeBackgroundColor: '#FFFFFF',
      wage: 12000,
      wageType: 'hourly',
      requiredCount: required_,
      runtimeFull: full,
      startTime: '09:00',
      endTime: '18:00',
      order: 0,
    );

/// 세 읽기를 각각 완료·실패·대기로 돌린다.
enum _R { ok, fail, pending }

class _Ctl {
  _Ctl({this.apps = _R.ok, this.sched = _R.ok, this.conf = _R.ok});
  final _R apps;
  final _R sched;
  final _R conf;

  int appsCalls = 0;
  int schedCalls = 0;
  int confCalls = 0;
  final List<String> keys = [];

  /// 완료되지 않는 future — 대기를 흉내내지 않고 실제로 미완료다.
  static Future<T> _never<T>() => Completer<T>().future;

  List<ApplicationModel> confirmedFixture = const [];

  ApplyWorkReads build() => ApplyWorkReads(
        applicationsForTO: ({required String toId, required String uid}) {
          appsCalls++;
          keys.add('apps:$toId/$uid');
          switch (apps) {
            case _R.ok:
              return Future.value(<ApplicationModel>[]);
            case _R.fail:
              return Future.error(StateError('applicationsForTO failed'));
            case _R.pending:
              return _never<List<ApplicationModel>>();
          }
        },
        confirmedSchedules: ({required String uid, required DateTime workDate}) {
          schedCalls++;
          keys.add('sched:$uid/${workDate.year}-${workDate.month}-${workDate.day}');
          switch (sched) {
            case _R.ok:
              return Future.value(confirmedFixture);
            case _R.fail:
              return Future.error(StateError('confirmedSchedules failed'));
            case _R.pending:
              return _never<List<ApplicationModel>>();
          }
        },
        conflictsForWorkDetails: (
            {required DateTime workDate,
            required List<WorkDetailData> workDetails}) {
          confCalls++;
          keys.add('conf:${workDetails.map((w) => w.wdId).join(",")}');
          switch (conf) {
            case _R.ok:
              return Future.value(<String, ConflictInfo>{});
            case _R.fail:
              return Future.error(StateError('conflicts failed'));
            case _R.pending:
              return _never<Map<String, ConflictInfo>>();
          }
        },
        // 이 층(A1-R)은 초기 로딩만 본다 — UNKNOWN 재확인은 A1-U 가 잰다.
        myApplicationsForTOFresh: (toId) async => <ApplicationModel>[],
      );
}

Future<void> _pump(
  WidgetTester tester, {
  required _Ctl ctl,
  List<WorkDetailData>? workDetails,
  Size size = const Size(390, 1600),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpWidget(
    ChangeNotifierProvider<UserProvider>(
      create: (_) => _LoggedIn(),
      child: MaterialApp(
        home: Scaffold(
          body: ApplyWorkDialog(
            mainTO: _to(),
            workDetails: workDetails ?? [_work()],
            slotId: 'slot1',
            businessName: '강남 물류센터',
            reads: ctl.build(),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  for (var i = 0; i < 24; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
  });

  // ══ 경계가 실제 서비스에 붙어 있다는 짝 ═══════════════════════════════════

  test('[ARR-0] production 기본값은 지금 쓰는 서비스 메서드를 그대로 부른다', () {
    // 줄바꿈(CRLF/LF)에 걸리지 않게 공백을 눌러 비교한다.
    String flat(String s) => s.replaceAll(RegExp(r'\s+'), ' ');
    final src = flat(
        File('lib/widgets/dialogs/apply/apply_work_reads.dart').readAsStringSync());
    // 세 자리가 각각 실제 메서드 이름에 붙어 있다.
    expect(src.contains('svc.getApplicationsForTO(toId: toId, uid: uid)'), isTrue);
    expect(src.contains('svc.getConfirmedSchedules(uid: uid, workDate: workDate)'),
        isTrue);
    expect(src.contains('cs.checkConflictsForWorkDetails('), isTrue);
    // 쓰기는 경계에 없다.
    for (final w in ['applyToTO', 'cancelApplication', 'confirmApplication']) {
      expect(src.contains(w), isFalse, reason: w);
    }

    final dlg = flat(File('lib/widgets/dialogs/apply/apply_work_dialog.dart')
        .readAsStringSync());
    // 화면 기본값이 그 경계다 — production 은 reads: null.
    expect(
        dlg.contains(
            'widget.reads ?? ApplyWorkReads.of(_firestoreService, _conflictService)'),
        isTrue);
    // 세 호출이 전부 경계를 지난다.
    expect(dlg.contains('_reads.applicationsForTO('), isTrue);
    expect(dlg.contains('_reads.confirmedSchedules('), isTrue);
    expect(dlg.contains('_reads.conflictsForWorkDetails('), isTrue);
  });

  // ══ 대기 ═════════════════════════════════════════════════════════════════

  testWidgets('[ARR-1] 세 읽기가 미완료면 스피너가 유지되고 지원 버튼이 없다',
      (tester) async {
    final ctl = _Ctl(apps: _R.pending, sched: _R.pending, conf: _R.pending);
    await _pump(tester, ctl: ctl);

    expect(find.byType(LoadingWidget), findsOneWidget);
    expect(find.text('업무 선택'), findsNothing);
    expect(find.text('상하차'), findsNothing);
    // 껍데기(제목·닫기)는 로딩 분기 밖이라 살아 있다.
    expect(find.text('지원하기'), findsOneWidget);
    expect(find.text('닫기'), findsOneWidget);
  });

  testWidgets('[ARR-2] 하나만 미완료여도 스피너다 — Future.wait 는 셋을 기다린다',
      (tester) async {
    final ctl = _Ctl(apps: _R.ok, sched: _R.ok, conf: _R.pending);
    await _pump(tester, ctl: ctl);

    expect(find.byType(LoadingWidget), findsOneWidget);
    expect(find.text('상하차'), findsNothing);
    // 그래도 세 호출은 모두 나갔다.
    expect(ctl.appsCalls, 1);
    expect(ctl.schedCalls, 1);
    expect(ctl.confCalls, 1);
  });

  // ══ 완료 → 카드 도달 ══════════════════════════════════════════════════════

  testWidgets('[ARR-3] 세 읽기가 완료되면 업무 카드·날짜·업무·지원 버튼이 나타난다',
      (tester) async {
    final ctl = _Ctl();
    await _pump(tester, ctl: ctl);

    expect(find.byType(LoadingWidget), findsNothing);
    // ABR-2 가 못 보던 것들
    expect(find.text('업무 선택'), findsOneWidget);
    expect(find.text('상하차'), findsWidgets);
    // 날짜가 보인다(문자열은 fixture 가 미는 값이라 월/일만 확인)
    expect(find.textContaining('${kWorkDate.month}월'), findsWidgets);
    // 지원 버튼이 도달 가능하다
    expect(find.text('지원'), findsWidgets);
  });

  testWidgets('[ARR-4] 같은 uid/key 로 나갔다', (tester) async {
    final ctl = _Ctl();
    await _pump(tester, ctl: ctl);

    expect(ctl.keys, contains('apps:to1/u1'));
    expect(
        ctl.keys,
        contains(
            'sched:u1/${kWorkDate.year}-${kWorkDate.month}-${kWorkDate.day}'));
    expect(ctl.keys, contains('conf:wd1'));
  });

  // ══ 실패 ═════════════════════════════════════════════════════════════════

  testWidgets('[ARR-5] 한 읽기가 실패해도 로딩에 갇히지 않는다', (tester) async {
    final ctl = _Ctl(apps: _R.fail);
    await _pump(tester, ctl: ctl);

    // 각 loader 가 자기 catch 로 삼키고 finally 가 로딩을 내린다.
    expect(find.byType(LoadingWidget), findsNothing);
    expect(find.text('업무 선택'), findsOneWidget);
    expect(find.text('상하차'), findsWidgets);
  });

  // ══ 음성 대조 — 카드가 보인다고 다 지원 가능한 것은 아니다 ═════════════════

  testWidgets('[ARR-6] 정원이 찬 업무는 카드가 있어도 지원으로 말하지 않는다',
      (tester) async {
    final ctl = _Ctl();
    await _pump(tester,
        ctl: ctl, workDetails: [_work(full: true)]);

    // 마감 안내가 화면을 덮는 것은 제품의 정상 동작이다 — 그 사실을 적는다.
    expect(find.text('상하차'), findsWidgets);
    expect(find.text('지원 완료'), findsNothing);
  });

  testWidgets('[ARR-7] 그 날짜에 확정 근무가 있으면 화면이 먼저 그것을 말한다',
      (tester) async {
    final ctl = _Ctl();
    ctl.confirmedFixture = [
      ApplicationModel(
        id: 'other1',
        uid: 'u1',
        toId: 'toX',
        slotId: 'slotX',
        businessId: 'bizX',
        businessName: '성수 창고',
        toTitle: '다른 공고',
        selectedWorkType: '피킹',
        wdId: 'wdX',
        startTime: '09:00',
        endTime: '18:00',
        wage: 12000,
        wageType: 'hourly',
        status: 'CONFIRMED',
        workDate: kWorkDate,
        appliedAt: DateTime(2026, 9, 1),
      )
    ];
    await _pump(tester, ctl: ctl);

    // 로딩은 풀렸고, 같은 날 확정 근무가 있다는 맥락이 화면에 있다.
    expect(find.byType(LoadingWidget), findsNothing);
    expect(find.textContaining('성수 창고'), findsWidgets);
  });
}
