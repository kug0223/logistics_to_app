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
import 'package:ALfit/utils/format_helper.dart';
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

/// [R7-P4.4E.6D] 날짜 문자열 길이별 대표일.
///
///   `formatDateCompact` 는 `M/D(요일)` 를 만든다 — 월·일이 각각 한 자리나
///   두 자리가 될 수 있고, 그 차이가 경고 Row 의 폭을 바꿨다. 특정 연·월을
///   박아 두면 테스트가 시간이 지나면서 과거 날짜가 되어(그러면 화면이
///   `_showClosedAlert` 로 덮인다) 썩는다. 그래서 **오늘 이후에서** 원하는
///   자릿수 조합을 가진 첫 날을 찾는다.
DateTime _futureDateWith({required int monthDigits, required int dayDigits}) {
  final now = DateTime.now();
  final base = DateTime(now.year, now.month, now.day);
  for (var i = 1; i <= 400; i++) {
    final d = base.add(Duration(days: i));
    if (d.month.toString().length == monthDigits &&
        d.day.toString().length == dayDigits) {
      return d;
    }
  }
  throw StateError('자릿수 조합을 찾지 못했다: $monthDigits/$dayDigits');
}

TOModel _to({DateTime? date}) => TOModel(
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
      rangeStart: date ?? kWorkDate,
      createdAt: DateTime(2026, 9, 1),
      statusUpdatedAt: DateTime(2026, 9, 1),
    );

WorkDetailData _work({
  int required_ = 4,
  bool full = false,
  // [R7-P4.4E.6E] 업무명·시간이 날짜 카드의 시간 문구와 업무 카드 폭을
  //   정한다. 여러 업무를 서로 다른 시간으로 주면 날짜 카드가
  //   `N개 업무 (시간 상이)` 로 바뀐다.
  String wdId = 'wd1',
  String workType = '상하차',
  String startTime = '09:00',
  String endTime = '18:00',
  int order = 0,
}) =>
    WorkDetailData(
      wdId: wdId,
      workType: workType,
      workTypeIcon: 'box',
      workTypeColor: '#000000',
      workTypeBackgroundColor: '#FFFFFF',
      wage: 12000,
      wageType: 'hourly',
      requiredCount: required_,
      runtimeFull: full,
      startTime: startTime,
      endTime: endTime,
      order: order,
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
  // [R7-P4.4E.6D] 폭과 글자배율이 경고 Row 의 제약을 정한다.
  double textScale = 1.0,
  DateTime? workDate,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpWidget(
    ChangeNotifierProvider<UserProvider>(
      create: (_) => _LoggedIn(),
      child: MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(
            size: size,
            textScaler: TextScaler.linear(textScale),
          ),
          child: Scaffold(
            body: ApplyWorkDialog(
              mainTO: _to(date: workDate),
              workDetails: workDetails ?? [_work()],
              slotId: 'slot1',
              businessName: '강남 물류센터',
              reads: ctl.build(),
            ),
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

  // ══ [R7-P4.4E.6D] 확정근무 경고 Row — 날짜 길이 · 폭 · 글자배율 ═════════
  //
  //   ARR-7 은 날짜가 `10/9(금)` 에서 `10/10(토)` 로 넘어가는 날 깨졌다.
  //   제목 Text 가 Row 에서 flex 를 받지 못해 자기 자연 폭을 요구했고,
  //   390dp(scale 0.9) 가용 337.6 에 icon 16.2 + gap 7.2 + text 320.3 =
  //   343.7 이 들어가려 해서 6.1px 넘쳤다.
  //
  //   날짜 문자열 길이는 정상적인 제품 데이터 변화다. 그래서 overflow 0 만
  //   보지 않고 **경고의 사실이 끝까지 읽히는지**를 함께 고정한다.

  /// 확정근무 fixture 하나 — 경고 블록이 렌더되는 최소 조건.
  _Ctl ctlWithConfirmed({String businessName = '성수 창고'}) {
    final c = _Ctl();
    c.confirmedFixture = [
      ApplicationModel(
        id: 'other1',
        uid: 'u1',
        toId: 'toX',
        slotId: 'slotX',
        businessId: 'bizX',
        businessName: businessName,
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
    return c;
  }

  // 대표 폭 — 320(최소) / 360(scale 경계) / 411(일반 Android)
  const widths = <double>[320, 360, 411];
  // 대표 글자배율
  const scales = <double>[1.0, 1.3, 2.0];
  // 대표 날짜 자릿수 조합 — `M/D` 가 1·2 자리로 갈린다.
  final dateShapes = <String, DateTime>{
    '1/1': _futureDateWith(monthDigits: 1, dayDigits: 1),
    '1/2': _futureDateWith(monthDigits: 1, dayDigits: 2),
    '2/1': _futureDateWith(monthDigits: 2, dayDigits: 1),
    '2/2': _futureDateWith(monthDigits: 2, dayDigits: 2),
  };

  for (final w in widths) {
    for (final s in scales) {
      for (final shape in dateShapes.entries) {
        testWidgets(
            '[ARR-8] 경고 Row 가 넘치지 않고 사실이 읽힌다 '
            '— ${w.toInt()}dp × textScale $s × 날짜 ${shape.key}',
            (tester) async {
          final date = shape.value;
          await _pump(
            tester,
            ctl: ctlWithConfirmed(),
            size: Size(w, 2400),
            textScale: s,
            workDate: date,
          );

          // 1. 경고 Row 가 자기 폭 안에 들어간다.
          //
            //   전역 `takeException() == null` 로 재지 않는다 — 같은 화면의
            //   **다른** 컴포넌트(업무 카드 내부 Row,
            //   `apply_work_dialog.dart:933`)가 320dp×1.3 이상에서 따로
            //   넘친다. 그건 이 Phase 의 owner 가 아니고 날짜와도 무관하다
            //   (넘침 폭이 날짜 네 모양에서 모두 같다). 그래서 이 셀은
            //   경고 Row 의 **기하**를 직접 재서, 다른 컴포넌트의 상태에
            //   흔들리지 않게 한다.
          final title =
              '${FormatHelper.formatDateCompact(date)} 확정된 근무가 있습니다';
          expect(find.text(title), findsOneWidget,
              reason: '문구를 자르거나 날짜를 빼지 않는다');

          final titleRect = tester.getRect(find.text(title));
          final rowRect = tester.getRect(
            find.ancestor(of: find.text(title), matching: find.byType(Row)).first,
          );
          expect(titleRect.right, lessThanOrEqualTo(rowRect.right + 0.01),
              reason: '${w.toInt()}dp / scale $s / ${shape.key} — '
                  '제목이 Row 밖으로 ${(titleRect.right - rowRect.right).toStringAsFixed(1)}px 넘쳤다');
          expect(titleRect.left, greaterThanOrEqualTo(rowRect.left - 0.01));

          // 2. 경고의 나머지 두 사실도 그대로 읽힌다 — 관련 일정 · 의미.
          expect(find.textContaining('성수 창고'), findsWidgets);
          expect(find.text('시간이 겹치는 업무는 지원할 수 없습니다'),
              findsOneWidget);

          // [R7-P4.4E.6E] 업무 카드 Row 도 닫혔으므로 이제 전역으로 본다.
          expect(tester.takeException(), isNull,
              reason: "${w.toInt()}dp / scale $s / ${shape.key} 에서 화면 전체 overflow");
        });
      }
    }
  }

  testWidgets('[ARR-9] 한 자리 날짜도 회귀 없다 — 390dp 기준선', (tester) async {
    final date = _futureDateWith(monthDigits: 1, dayDigits: 1);
    await _pump(tester, ctl: ctlWithConfirmed(), workDate: date);
    expect(tester.takeException(), isNull,
        reason: '390dp / scale 1.0 — 기준 폭에서는 화면 전체가 깨끗해야 한다');
    expect(
        find.text('${FormatHelper.formatDateCompact(date)} 확정된 근무가 있습니다'),
        findsOneWidget);
  });

  testWidgets('[ARR-10] 긴 사업장명도 확정 일정 줄을 넘기지 않는다', (tester) async {
    // 경고 블록의 두 번째 Row(확정 일정 목록)는 이미 Expanded 를 쓴다.
    //   제목 Row 만 고친 뒤에도 그 축이 그대로임을 같은 좁은 폭에서 확인한다.
    await _pump(
      tester,
      ctl: ctlWithConfirmed(businessName: '성수동 제2물류센터 냉장창고 B동'),
      size: const Size(320, 2400),
      textScale: 1.3,
      workDate: _futureDateWith(monthDigits: 2, dayDigits: 2),
    );
    // ARR-8 과 같은 이유로 전역 예외가 아니라 그 줄의 기하를 본다.
    final line = find.textContaining('성수동 제2물류센터');
    expect(line, findsWidgets);
    final lineRect = tester.getRect(line.first);
    final lineRow =
        tester.getRect(find.ancestor(of: line.first, matching: find.byType(Row)).first);
    expect(lineRect.right, lessThanOrEqualTo(lineRow.right + 0.01),
        reason: '확정 일정 줄이 Row 밖으로 나갔다');
    tester.takeException();
  });

  testWidgets('[ARR-11] 제목을 자르거나 한 줄로 묶지 않는다', (tester) async {
    final date = _futureDateWith(monthDigits: 2, dayDigits: 2);
    await _pump(
      tester,
      ctl: ctlWithConfirmed(),
      size: const Size(320, 2400),
      textScale: 2.0,
      workDate: date,
    );
    // 이 셀은 layout 이 아니라 **Text 의 계약**을 본다 — 전역 예외는
    //   범위 밖 컴포넌트 때문에 생길 수 있으므로 분류해서 비운다.
    tester.takeException();
    final title = tester.widget<Text>(find
        .text('${FormatHelper.formatDateCompact(date)} 확정된 근무가 있습니다'));
    expect(title.maxLines, isNull,
        reason: 'maxLines:1 로 묶으면 좁은 폭에서 문장이 사라진다');
    expect(title.overflow, isNot(TextOverflow.ellipsis),
        reason: '핵심 경고를 "확정 근무가 있...") 로 자르지 않는다');
    expect(title.style?.fontSize, 15,
        reason: '폰트를 줄여 맞추지 않는다');
  });

  test('[ARR-13] 매트릭스가 조용히 좁아지지 않는다', () {
    // 대표 폭 셋 · 글자배율 셋 · 날짜 자릿수 네 모양 = 36 셀.
    //   이 중 두 자리 날짜나 textScale 2.0 을 빼면 원래 결함이 다시
    //   숨는다(결함은 한 자리 → 두 자리 전이에서 났다).
    expect(widths, containsAll(<double>[320, 360, 411]));
    expect(scales, containsAll(<double>[1.0, 1.3, 2.0]));
    expect(dateShapes.keys.toSet(), {'1/1', '1/2', '2/1', '2/2'});
    expect(widths.length * scales.length * dateShapes.length, 36);
    // 자릿수 조합이 실제로 그 모양인지 — 조합 생성기가 망가지면 의미가 없다.
    for (final e in dateShapes.entries) {
      final parts = e.key.split('/');
      expect(e.value.month.toString().length, int.parse(parts[0]));
      expect(e.value.day.toString().length, int.parse(parts[1]));
      expect(e.value.isAfter(DateTime.now()), isTrue,
          reason: '지난 날짜면 화면이 마감 안내로 덮인다');
    }
  });

  test('[ARR-12] 제목 Text 가 Row 의 폭을 소유한다 — 구조 고정', () {
    final src =
        File('lib/widgets/dialogs/apply/apply_work_dialog.dart').readAsStringSync();
    final start = src.indexOf('Widget _buildMyScheduleWarning(');
    expect(start, greaterThan(-1));
    final end = src.indexOf('확정된 근무가 있습니다', start);
    expect(end, greaterThan(start));
    final head = src.substring(start, end);
    expect(head.contains('crossAxisAlignment: CrossAxisAlignment.start'), isTrue,
        reason: '여러 줄이 되면 아이콘이 첫 줄 옆에 있어야 한다');
    expect(head.contains('Expanded('), isTrue,
        reason: '제목 Text 가 flex 를 받지 못하면 자연 폭을 요구해 다시 넘친다');
    // ClipRect/FittedBox 같은 은폐 수단으로 닫지 않았다.
    final body = src.substring(start, src.indexOf('시간이 겹치는 업무는', start));
    for (final hide in ['ClipRect', 'OverflowBox', 'FittedBox', 'Transform.scale']) {
      expect(body.contains(hide), isFalse, reason: '$hide 로 가리지 않는다');
    }
  });

  // ══ [R7-P4.4E.6E] 업무 카드 — 좁은 폭 × 큰 글자 ═══════════════════════════
  //
  //   E6D 매트릭스가 드러낸 두 번째 Row 다(날짜 정보 카드 안의 시간 줄).
  //   시간 Text 가 flex 를 받지 못해 자기 자연 폭을 요구했다 — E6D 와
  //   **같은 패턴, 다른 자리**다.
  //
  //     320dp(scale 0.85) 가용 214.3 · icon 11.1 + gap 3.4
  //     '09:00 ~ 18:00' 13자 × (13 × textScale)
  //       1.3 → 219.7  → 23 초과
  //       2.0 → 338.0  → 141 초과
  //
  //   큰 글자는 예외가 아니라 정상적인 접근성 환경이다.

  /// 날짜 정보 카드 안의 시간 Text — 같은 문자열이 업무 카드에도 있으므로
  ///   `근무 날짜` 라벨이 있는 Column 으로 범위를 좁힌다.
  ///   줄번호가 아니라 **위젯 신원**으로 집는다(§35).
  Finder dateCardTimeText(String timeText) {
    final column =
        find.ancestor(of: find.text('근무 날짜'), matching: find.byType(Column)).first;
    return find.descendant(of: column, matching: find.text(timeText));
  }

  /// 그 시간 Text 와 그것을 담은 Row 의 사각형.
  ({Rect text, Rect row}) timeRowRects(WidgetTester tester, String timeText) {
    final t = dateCardTimeText(timeText);
    expect(t, findsOneWidget, reason: '날짜 카드에 시간 문구가 없다: $timeText');
    return (
      text: tester.getRect(t),
      row: tester.getRect(
          find.ancestor(of: t, matching: find.byType(Row)).first),
    );
  }

  for (final w in widths) {
    for (final s in scales) {
      testWidgets(
          '[AWC-1] 업무 카드가 넘치지 않고 핵심 사실이 읽힌다 '
          '— ${w.toInt()}dp × textScale $s', (tester) async {
        await _pump(tester, ctl: _Ctl(), size: Size(w, 2400), textScale: s);

        // 1. 화면 전체에 overflow 가 없다 — 이제 전역으로 본다.
        expect(tester.takeException(), isNull,
            reason: '${w.toInt()}dp / scale $s 에서 overflow');

        // 2. 시간 줄이 자기 Row 안에 들어간다.
        final r = timeRowRects(tester, '09:00 ~ 18:00');
        expect(r.text.right, lessThanOrEqualTo(r.row.right + 0.01),
            reason: '시간이 Row 밖으로 '
                '${(r.text.right - r.row.right).toStringAsFixed(1)}px 넘쳤다');
        expect(r.text.left, greaterThanOrEqualTo(r.row.left - 0.01));

        // 3. 카드의 핵심 사실 — 업무명 · 시간 · 임금 · 근무 날짜.
        expect(find.text('상하차'), findsWidgets, reason: '업무명');
        expect(find.text('12,000원/시급'), findsWidgets, reason: '임금');
        expect(find.text('근무 날짜'), findsOneWidget);
        expect(find.text(FormatHelper.formatDateKorean(kWorkDate)),
            findsOneWidget, reason: '근무 날짜');
      });
    }
  }

  testWidgets('[AWC-2] 긴 업무명도 카드를 넘기지 않는다 — 320dp × 2.0',
      (tester) async {
    await _pump(
      tester,
      ctl: _Ctl(),
      workDetails: [_work(workType: '냉장창고 입출고 및 파렛트 정리')],
      size: const Size(320, 2400),
      textScale: 2.0,
    );
    expect(tester.takeException(), isNull);
    expect(find.text('냉장창고 입출고 및 파렛트 정리'), findsWidgets);
    expect(find.text('12,000원/시급'), findsWidgets);
  });

  testWidgets('[AWC-3] 업무 3건이면 시간 문구가 길어진다 — 320dp × 2.0',
      (tester) async {
    // 시간이 서로 다르면 날짜 카드가 `N개 업무 (시간 상이)` 로 바뀐다 —
    //   이 컴포넌트가 만드는 **가장 긴 한국어 시간 문구**다.
    await _pump(
      tester,
      ctl: _Ctl(),
      workDetails: [
        _work(wdId: 'w1', startTime: '06:00', endTime: '15:00', order: 0),
        _work(wdId: 'w2', workType: '피킹', startTime: '09:00', endTime: '18:00', order: 1),
        _work(wdId: 'w3', workType: '검수', startTime: '13:00', endTime: '22:00', order: 2),
      ],
      size: const Size(320, 2400),
      textScale: 2.0,
    );
    expect(tester.takeException(), isNull);
    final r = timeRowRects(tester, '3개 업무 (시간 상이)');
    expect(r.text.right, lessThanOrEqualTo(r.row.right + 0.01));
    // 세 업무가 모두 렌더된다 — 하나도 밀려나지 않는다.
    for (final n in ['상하차', '피킹', '검수']) {
      expect(find.text(n), findsWidgets, reason: n);
    }
  });

  testWidgets('[AWC-4] 큰 글자에서도 업무별 지원 동작에 닿는다 — 320dp × 2.0',
      (tester) async {
    await _pump(tester, ctl: _Ctl(), size: const Size(320, 2400), textScale: 2.0);
    expect(tester.takeException(), isNull);
    // 카드의 동작 라벨이 렌더돼 있고(존재), 화면 폭 안에 있다.
    final apply = find.text('지원');
    expect(apply, findsWidgets, reason: '업무별 지원 동작이 사라지면 안 된다');
    final rect = tester.getRect(apply.first);
    expect(rect.left, greaterThanOrEqualTo(0));
    expect(rect.right, lessThanOrEqualTo(320 + 0.01),
        reason: '동작이 화면 밖으로 나갔다');
  });

  testWidgets('[AWC-5] 시간 문구는 줄바꿈으로 흡수한다 — 자르지 않는다',
      (tester) async {
    await _pump(tester, ctl: _Ctl(), size: const Size(320, 2400), textScale: 2.0);
    expect(tester.takeException(), isNull);
    final t = dateCardTimeText('09:00 ~ 18:00');
    final time = tester.widget<Text>(t);
    expect(time.maxLines, isNull, reason: 'maxLines:1 로 묶지 않는다');
    expect(time.overflow, isNot(TextOverflow.ellipsis),
        reason: '시간을 "09:00 ~ 1..." 로 자르지 않는다');
    expect(time.style?.fontSize, 13, reason: '폰트를 줄여 맞추지 않는다');
    // 한 줄에 못 들어가면 두 줄 이상이 된다 — 높이로 확인한다.
    final h = tester.getRect(t).height;
    expect(h, greaterThan(13 * 2.0 * 1.2),
        reason: '줄바꿈이 일어나야 전부 읽힌다 (height=$h)');
  });

  test('[AWC-6] 시간 Text 가 Row 의 폭을 소유한다 — 구조 고정', () {
    final src =
        File('lib/widgets/dialogs/apply/apply_work_dialog.dart').readAsStringSync();
    final start = src.indexOf('Widget _buildSingleDateInfo(');
    expect(start, greaterThan(-1));
    final end = src.indexOf('Widget _buildConflictWarningBox(', start);
    expect(end, greaterThan(start));
    final body = src.substring(start, end);
    final rowAt = body.indexOf('Icons.access_time');
    expect(rowAt, greaterThan(-1));
    final timeRow = body.substring(body.lastIndexOf('Row(', rowAt));
    expect(timeRow.contains('crossAxisAlignment: CrossAxisAlignment.start'), isTrue);
    expect(timeRow.contains('Expanded('), isTrue,
        reason: '시간 Text 가 flex 를 받지 못하면 다시 자연 폭을 요구한다');
    for (final hide in [
      'ClipRect', 'OverflowBox', 'FittedBox', 'Transform.scale',
      'TextOverflow.ellipsis',
    ]) {
      expect(body.contains(hide), isFalse, reason: '$hide 로 가리지 않는다');
    }
  });

  testWidgets('[AWC-7] 카드가 높아져도 스크롤 주인은 하나다', (tester) async {
    await _pump(tester, ctl: _Ctl(), size: const Size(320, 900), textScale: 2.0);
    expect(tester.takeException(), isNull);
    // 중첩 스크롤을 새로 만들지 않았다 — E6C 의 single scroll owner 유지.
    expect(find.byType(Scrollable), findsOneWidget,
        reason: '스크롤 주인이 둘이면 제스처가 갈린다');
  });
}
