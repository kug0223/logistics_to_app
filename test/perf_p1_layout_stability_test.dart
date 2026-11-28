// [판정289 C289-03 · P1] 근로자 홈 「필수응답 + 약속」 구역 — 첫 표시 조정·흔들림 계약 시험 **초안**.
//
//   상태: 준비 단계 초안(2026-11-26). lib 수정 전 작성 — 지금 실행하면 일부는 **실패하는 것이 정상**이다
//   (설계 노트 records/work/perf-first-load-1/prep_p1_l5.md §3 의 '지금 기대 결과' 열).
//   구현 뒤 이 파일 자체를 완화하지 않는다. 기대를 바꿔야 하면 사유를 이 머리 주석과 노트에 남긴다.
//
//   계약(판정289 §4 · 인계289 §6):
//     · 600ms 는 첫 뼈대(첫 프레임) 기준 **최초 표시 잠정 상한** — 최소 대기 · 조회 timeout · 정상0 기한이 아니다.
//       모든 필수 출처가 그 전에 끝나면 즉시 한 번에 보인다(P1L-2). 끝나지 않은 출처는 상한 뒤 '확인 중'으로 남는다(P1L-3/4).
//     · 출처별 0 / 비0 / ERROR / PARTIAL / LOADING 을 섞지 않는다 — UNKNOWN 을 정상 0 으로 접지 않는다(P1L-5/6).
//     · 늦은 필수응답·자정 퇴근은 반드시 반영한다(P1L-3/4).
//     · 286/287 순서·부분성 보존(P1L-1 순서 · P1L-6).
//     · 절대 기하 0 이 아니라 **불필요한 위 삽입 · 같은 데이터 반복 높이 변화 제거**(P1L-1 · P1L-7),
//       필요한 늦은 추가는 별도로 세고 스크롤·포커스·접근성을 지킨다(P1L-8/9).
//
//   측정 도구: [LayoutShiftRecorder] — 기준 요소(날짜 영역 · 일자리 섹션)의 전역 y 를 프레임(16ms)마다 표본으로 남기고
//     연속 표본 사이 |Δy| > 0.5 인 횟수를 '흔들림'으로 센다. P1L-0 이 양성/음성 대조로 도구 자체를 먼저 검사한다.
//
//   미래 키(구현이 추가할 이름 — 지금은 없어서 찾기가 실패한다):
//     ValueKey('worker-home-required-pending') — 필수 출처 중 아직 끝나지 않은 것이 있다는 '확인 중' 표지(첫 뼈대 자리표시 포함).
//       의미 이름(label)이 비어 있지 않아야 한다. 문구 자체는 구현 셀에서 정한다(이 시험은 문구를 고정하지 않는다).
// ignore_for_file: depend_on_referenced_packages, avoid_print
import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ALfit/models/core/application_model.dart';
import 'package:ALfit/models/core/attendance_model.dart';
import 'package:ALfit/models/core/business_model.dart';
import 'package:ALfit/models/core/employment_contract_model.dart';
import 'package:ALfit/models/core/id_card_access_request_model.dart';
import 'package:ALfit/models/core/legal_readiness.dart';
import 'package:ALfit/models/core/renewal_proposal_model.dart';
import 'package:ALfit/models/core/slot_model.dart';
import 'package:ALfit/models/core/to_model.dart';
import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/providers/notification_provider.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/screens/user/user_home_reads.dart';
import 'package:ALfit/screens/user/user_home_screen.dart';
import 'package:ALfit/screens/user/user_tab_scope.dart';
import 'package:ALfit/services/payroll_correction_service.dart';
import 'package:ALfit/theme/role_theme.dart';

import 'support/checkin_contract_fixture.dart';
import 'support/du1_vq_capture.dart';
import 'support/visible_text.dart';

// ─────────────────────────────────────────────────────────────────────────────
// 흔들림 측정 도구
// ─────────────────────────────────────────────────────────────────────────────

/// 기준 요소의 전역 y 를 표본으로 남기고 '위치가 바뀐 횟수'를 센다.
///
///   · 표본이 없는(아직 트리에 없음·숨음) 프레임은 null — null↔값 전환은 흔들림으로 세지 않는다(처음 나타남/사라짐).
///   · [shifts] = 연속된 두 값 표본의 |Δy| > [tolerance] 횟수.
///   · [downShifts] = 그중 아래로 밀린(Δy > 0) 횟수 — 위쪽 삽입의 표지.
///   · [log] 는 실패 메시지에 붙여 어느 시각에 몇 px 움직였는지 남긴다.
class LayoutShiftRecorder {
  LayoutShiftRecorder(this.name, this.finder, {this.tolerance = 0.5});

  final String name;
  final Finder finder;
  final double tolerance;
  final List<(int, double?)> samples = [];

  double? _y(WidgetTester t) {
    final els = finder.evaluate();
    if (els.isEmpty) return null;
    final ro = els.first.renderObject;
    if (ro is! RenderBox || !ro.attached || !ro.hasSize) return null;
    return ro.localToGlobal(Offset.zero).dy;
  }

  void sample(WidgetTester t, int ms) => samples.add((ms, _y(t)));

  Iterable<(int, double)> get _moves sync* {
    double? prev;
    for (final (ms, y) in samples) {
      if (y != null && prev != null && (y - prev).abs() > tolerance) yield (ms, y - prev);
      if (y != null) prev = y;
    }
  }

  int get shifts => _moves.length;
  int get downShifts => _moves.where((m) => m.$2 > 0).length;

  /// [fromMs] 이후 표본만 센 흔들림.
  int shiftsAfter(int fromMs) => _moves.where((m) => m.$1 > fromMs).length;

  String get log => '$name moves=${_moves.map((m) => '${m.$1}ms:${m.$2 >= 0 ? '+' : ''}${m.$2.toStringAsFixed(1)}').join(' ')}';
}

/// [ms] 동안 [step] 간격으로 pump 하며 모든 기록기에 표본을 남긴다. 반환 = 끝난 시각(ms, 첫 프레임 기준).
Future<int> pumpAndRecord(WidgetTester t, List<LayoutShiftRecorder> recs,
    {required int fromMs, required int ms, int step = 16}) async {
  var now = fromMs;
  while (now < fromMs + ms) {
    await t.pump(Duration(milliseconds: step));
    now += step;
    for (final r in recs) {
      r.sample(t, now);
    }
  }
  return now;
}

// ─────────────────────────────────────────────────────────────────────────────
// 하네스 (worker_home_285_test 와 같은 대역 모양)
// ─────────────────────────────────────────────────────────────────────────────

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

class _W extends UserProvider {
  _W(this.user);
  final UserModel user;
  @override
  UserModel? get currentUser => user;
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
}

UserModel _worker() => UserModel(
      uid: 'u1', username: '', name: '김알핏', email: '', role: UserRole.USER,
      accountStatus: 'active', passVerifiedAt: DateTime(2026, 11, 25),
      nationalityStatus: 'unknown', authProviders: const ['kakao'], signupSource: 'kakao_v1',
    );

// 고정 시각 2026-11-26(목) KST 10:00.
final DateTime _clock = DateTime.utc(2026, 11, 26, 1);
DateTime _k(int m, int d) => DateTime.utc(2026, m, d);

ApplicationModel _app(String id, DateTime day, String status,
        {String start = '09:00', String end = '18:00', String biz = '가람 물류센터', String? termination}) =>
    ApplicationModel(
      id: id, toId: 'to_$id', uid: 'u1', businessId: 'b_$id', businessName: biz, toTitle: '단기 공고',
      status: status, selectedWorkType: '피킹', startTime: start, endTime: end, wage: 12000, wageType: 'hourly',
      workDate: day, appliedAt: _k(11, 20), applicationType: AppType.shortTerm,
      confirmedAt: status == AppStatus.pending ? null : _k(11, 1), terminationStatus: termination,
    );

/// 오늘 확정(계약 완료) — 약속 B.
ApplicationModel _today() => _app('t1', _k(11, 26), AppStatus.confirmed, start: '13:00', end: '18:00');

/// 해지 응답 대기 — 다른 날 확정 근무.
ApplicationModel _terminating() =>
    _app('x1', _k(11, 30), AppStatus.confirmed, biz: '나래 센터', termination: AppStatus.pending);

/// 자정 넘긴 근무 — 어제(11/25) 22:00 KST 출근 · 퇴근 없음.
ApplicationModel _overnightApp() => _app('n1', _k(11, 25), AppStatus.confirmed, start: '22:00', end: '06:00');
AttendanceModel _overnightAtt() => AttendanceModel(
      id: 'att_n1', applicationId: 'n1', userId: 'u1', businessId: 'b_n1', businessName: '가람 물류센터',
      workDate: _k(11, 25), workType: '피킹', status: AttendanceModel.statusPresent,
      wageStatus: AttendanceModel.wagePending, adminConfirmed: false,
      checkInAt: DateTime.utc(2026, 11, 25, 13), checkOutAt: null, createdAt: _k(11, 25),
    );

RenewalProposalModel _proposal() => RenewalProposalModel(
      id: 'rp1', businessId: 'b_x1', businessName: '위워커', workerUid: 'u1', oldApplicationId: 'x1',
      status: RenewalProposalStatus.pending, effectiveStart: _k(12, 10), effectiveEnd: _k(12, 10).add(const Duration(days: 90)),
      workDays: const ['월', '화', '수', '목', '금'], startTime: '09:00', endTime: '18:00', wage: 12000, wageType: 'hourly',
      selectedWorkType: '사무업무',
    );

const _reconsent = LegalReadiness(status: LegalReadinessStatus.reconsentRequired, reconsentRequired: ['service_terms']);
const _legalCurrent = LegalReadiness(status: LegalReadinessStatus.current);

/// 출처 한 개의 응답 계획 — [ms] 뒤 [value] 또는 실패. [gate] 가 있으면 gate 완료까지 붙잡는다(상한 뒤 도착).
class _Plan<T> {
  const _Plan(this.value, {this.ms = 0, this.fail = false, this.gate});
  final T value;
  final int ms;
  final bool fail;
  final Completer<void>? gate;

  Future<T> run(String what) async {
    if (gate != null) await gate!.future;
    if (ms > 0) await Future<void>.delayed(Duration(milliseconds: ms)); // 0 이면 timer 없이 microtask 로 끝난다(P1L-8f)
    if (fail) throw Exception('P1 $what 실패 fixture');
    return value;
  }
}

class _Calls {
  final counts = <String, int>{};
  void hit(String k) => counts[k] = (counts[k] ?? 0) + 1;
  int n(String k) => counts[k] ?? 0;
}

UserHomeReads _reads(
  _Calls calls, {
  _Plan<List<ApplicationModel>> apps = const _Plan([]),
  _Plan<List<AttendanceModel>> atts = const _Plan([]),
  _Plan<List<IdCardAccessRequestModel>> idReqs = const _Plan([]),
  _Plan<List<EmploymentContractModel>>? contracts,
  _Plan<DocumentCorrectionSurface> corrections = const _Plan(DocumentCorrectionSurface.empty),
  _Plan<List<RenewalProposalModel>> renewals = const _Plan([]),
  _Plan<LegalReadiness> legal = const _Plan(_legalCurrent),
  List<_Plan<List<IdCardAccessRequestModel>>>? idSeq,
  List<_Plan<List<RenewalProposalModel>>>? renewalSeq,
}) =>
    UserHomeReads(
      slotsForTO: (_) async => const <SlotModel>[],
      myContracts: (_) {
        calls.hit('contracts');
        // 기본: 확정 지원마다 양측 서명 계약(오늘 약속 B 가 출근 가능 상태가 되게) · 지원과 같은 시각에 도착
        final derived = apps.fail
            ? const <EmploymentContractModel>[]
            : apps.value.where((x) => x.status == AppStatus.confirmed).map((x) => checkInContractFor(x)).toList();
        return (contracts ?? _Plan<List<EmploymentContractModel>>(derived, ms: apps.ms, gate: apps.gate)).run('계약');
      },
      myApplications: (_) {
        calls.hit('apps');
        return apps.run('지원');
      },
      myMonthlyAttendances: ({required String userId, required int year, required int month}) {
        calls.hit('atts');
        return atts.run('근태');
      },
      publishedTOs: () async => const <TOModel>[],
      pendingIdCardRequests: (_) {
        final i = calls.n('id');
        calls.hit('id');
        // idSeq: 호출 순서대로 쓰고, 넘치면 마지막 계획을 반복한다.
        final plan = idSeq == null ? idReqs : idSeq[i < idSeq.length ? i : idSeq.length - 1];
        return plan.run('신분증 요청');
      },
      myRenewalProposals: () {
        final i = calls.n('renewal');
        calls.hit('renewal');
        final plan = renewalSeq == null ? renewals : renewalSeq[i < renewalSeq.length ? i : renewalSeq.length - 1];
        return plan.run('연장 제안');
      },
      businessById: (id) async => BusinessModel(
          id: id, name: 'b', ownerId: 'o', businessNumber: '0', address: 'a', category: 'c',
          subCategory: 's', isApproved: true, createdAt: DateTime(2026)),
      invalidatePublishedTOsCache: () {},
      documentCorrections: () {
        calls.hit('corrections');
        return corrections.run('보완 요청');
      },
      legalReadiness: () {
        calls.hit('legal');
        return legal.run('약관');
      },
    );

/// 첫 프레임까지 그린다(t=0). 이후 시간은 [pumpAndRecord] 로 흘린다.
Future<void> _mount(WidgetTester t, UserHomeReads reads,
    {double width = 360, double height = 2400, double scale = 1.0}) async {
  t.view.physicalSize = Size(width, height);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(const SizedBox.shrink());
  await t.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider<UserProvider>.value(value: _W(_worker())),
      ChangeNotifierProvider<NotificationProvider>(create: (_) => NotificationProvider()),
    ],
    child: MaterialApp(
      theme: RoleTheme.workerTheme,
      debugShowCheckedModeBanner: false,
      builder: (ctx, child) => MediaQuery(
        data: MediaQuery.of(ctx).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: UserTabScope(
        switchToTab: (_) {},
        switchToTabWithDate: (_, __) {},
        pendingJobDate: null,
        clearPendingJobDate: () {},
        pendingScheduleMonth: null,
        clearPendingScheduleMonth: () {},
        switchToScheduleNow: () {},
        switchToScheduleDate: (_) {},
        child: UserHomeScreen(reads: reads, clock: () => _clock, tourCompleted: () async => true),
      ),
    ),
  ));
}

final _area = find.byKey(const ValueKey('worker-home-date-area'));
final _jobs = find.byKey(const ValueKey('worker-home-jobs-section'));
final _pending = find.byKey(const ValueKey('worker-home-required-pending'));
final _errRow = find.byKey(const ValueKey('worker-home-required-error'));

double _y(WidgetTester t, Finder f) => t.getTopLeft(f.first).dy;

/// 그 시각의 사실을 적어 두고 시험 끝에 한 번에 판정한다 — 미래 키 검사가 먼저 실패해 내용(fixture) 검사가 묻히지 않게.
class _Later {
  final _fails = <String>[];
  void check(bool ok, String what) {
    if (!ok) _fails.add(what);
  }

  void verify() => expect(_fails, isEmpty, reason: _fails.join(' | '));
}

/// '확인 중' 표지가 하나 있고 의미 이름이 비어 있지 않다(ensureSemantics 필요).
bool _pendingShown(WidgetTester t) =>
    _pending.evaluate().length == 1 && t.getSemantics(_pending).label.trim().isNotEmpty;

void main() {
  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
    await initializeDateFormatting('ko_KR');
    await vqLoadFonts();
  });
  setUp(() => SharedPreferences.setMockInitialValues({'tour_completed_user_home': true}));

  // ── P1L-0 도구 자체 검사(양성/음성 대조) ────────────────────────────────
  testWidgets('P1L-0 흔들림 기록기 — 위 상자 높이가 2번 바뀌면 2, 아래 상자만 바뀌면 0', (t) async {
    final top = ValueNotifier<double>(10);
    final bottom = ValueNotifier<double>(10);
    await t.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        ValueListenableBuilder<double>(valueListenable: top, builder: (_, h, __) => SizedBox(height: h)),
        const SizedBox(key: ValueKey('anchor'), height: 20, width: 20),
        ValueListenableBuilder<double>(valueListenable: bottom, builder: (_, h, __) => SizedBox(height: h)),
      ]),
    ));
    final rec = LayoutShiftRecorder('anchor', find.byKey(const ValueKey('anchor')));
    var now = await pumpAndRecord(t, [rec], fromMs: 0, ms: 48);
    bottom.value = 50; // 음성 대조 — 아래 변화는 기준을 움직이지 않는다
    now = await pumpAndRecord(t, [rec], fromMs: now, ms: 48);
    expect(rec.shifts, 0, reason: rec.log);
    top.value = 40; // 양성 대조 — 위 삽입 1
    now = await pumpAndRecord(t, [rec], fromMs: now, ms: 48);
    top.value = 40; // 같은 값 — 변화 0
    now = await pumpAndRecord(t, [rec], fromMs: now, ms: 48);
    top.value = 5; // 위 축소 1
    await pumpAndRecord(t, [rec], fromMs: now, ms: 48);
    expect(rec.shifts, 2, reason: rec.log);
    expect(rec.downShifts, 1, reason: rec.log);
  });

  // ── P1L-1 서로 다른 시각에 도착하는 비0 필수응답 — 상한 안이면 한 번에 ──────
  testWidgets('P1L-1 약관100·지원(해지+오늘)300·보완 실패/연장 늦게 — 600 안 도착은 날짜 영역 흔들림 ≤1 · 순서 보존', (t) async {
    final calls = _Calls();
    await _mount(
        t,
        _reads(calls,
            legal: const _Plan(_reconsent, ms: 100),
            apps: _Plan([_today(), _terminating()], ms: 300),
            atts: const _Plan([], ms: 300),
            idReqs: const _Plan([], ms: 300),
            corrections: const _Plan(DocumentCorrectionSurface.failed, ms: 150),
            renewals: _Plan([_proposal()], ms: 250)));
    final area = LayoutShiftRecorder('date-area', _area);
    area.sample(t, 0);
    await pumpAndRecord(t, [area], fromMs: 0, ms: 1500);
    expect(t.takeException(), isNull);
    print('[P1L-1] ${area.log} shifts=${area.shifts}');

    // 최종 내용 — 모두 보인다(늦은 것도 버리지 않는다)
    final term = findVisibleText('나래 센터에서 계약해지를 요청했어요');
    final renewal = findVisibleTextContaining('계약 연장 제안');
    final corr = findVisibleText('서류 요청을 확인하지 못했어요');
    final legal = findVisibleText('이용약관이 변경되었습니다');
    final promise = findVisibleText('오늘의 약속');
    for (final f in [term, renewal, corr, legal, promise]) {
      expect(f, findsOneWidget);
    }
    // 판정285/286 순서: 해지 → 연장 → 보완 → 약관 → 약속 → 날짜 영역
    final ys = [term, renewal, corr, legal, promise, _area].map((f) => _y(t, f)).toList();
    for (var i = 1; i < ys.length; i++) {
      expect(ys[i - 1] < ys[i], isTrue, reason: '순서 $i: $ys');
    }
    // 핵심 계약: 첫 뼈대 뒤 위 구역이 한 번에 정해진다 — 날짜 영역이 여러 번 밀리지 않는다.
    expect(area.shifts, lessThanOrEqualTo(1), reason: area.log);
    expect(_pending, findsNothing, reason: '모두 끝났으면 확인 중 표지가 남지 않는다');
  });

  // ── P1L-2 600ms 는 최소 대기가 아니다 ───────────────────────────────────
  testWidgets('P1L-2 모든 출처 40ms 정상0 — 600 을 기다리지 않고 ≤120ms 안에 안정 · 흔들림 ≤1', (t) async {
    final calls = _Calls();
    await _mount(
        t,
        _reads(calls,
            legal: const _Plan(_legalCurrent, ms: 40),
            apps: const _Plan([], ms: 40),
            atts: const _Plan([], ms: 40),
            idReqs: const _Plan([], ms: 40),
            corrections: const _Plan(DocumentCorrectionSurface.empty, ms: 0),
            renewals: const _Plan([], ms: 0)));
    final area = LayoutShiftRecorder('date-area', _area);
    area.sample(t, 0);
    await pumpAndRecord(t, [area], fromMs: 0, ms: 1200);
    print('[P1L-2] ${area.log}');
    expect(area.shiftsAfter(120), 0, reason: '120ms 뒤에는 움직이지 않는다(600 대기 0) · ${area.log}');
    expect(area.shifts, lessThanOrEqualTo(1), reason: area.log);
    expect(findVisibleText('오늘 확정된 근무가 없어요'), findsOneWidget, reason: '정상 0 은 확인된 뒤에만');
    expect(_pending, findsNothing);
    expect(t.takeException(), isNull);
  });

  // ── P1L-3 상한 뒤: 끝난 것은 보이고, 안 끝난 것은 확인 중 · 늦게 와도 반영 ──────
  testWidgets('P1L-3 연장 제안이 2초 붙잡힘 — 650ms 에 해지 카드 보임 + 확인 중 표지 · 도착하면 연장 카드 · 표지 사라짐', (t) async {
    final gate = Completer<void>();
    final calls = _Calls();
    await _mount(
        t,
        _reads(calls,
            apps: _Plan([_terminating()], ms: 100),
            atts: const _Plan([], ms: 100),
            idReqs: const _Plan([], ms: 100),
            renewals: _Plan([_proposal()], gate: gate)));
    final sem = t.ensureSemantics();
    final later = _Later();
    final area = LayoutShiftRecorder('date-area', _area);
    area.sample(t, 0);
    var now = await pumpAndRecord(t, [area], fromMs: 0, ms: 650);
    expect(findVisibleText('나래 센터에서 계약해지를 요청했어요'), findsOneWidget,
        reason: '상한이 지나면 끝난 필수응답은 더 붙잡지 않는다');
    later.check(_pendingShown(t), '650ms: 끝나지 않은 필수 출처는 의미 이름 있는 확인 중 표지로 남는다(정상 0 단정 0)');
    gate.complete();
    now = await pumpAndRecord(t, [area], fromMs: now, ms: 600);
    expect(findVisibleTextContaining('계약 연장 제안'), findsOneWidget, reason: '늦은 필수응답 반영 필수');
    expect(_pending, findsNothing);
    print('[P1L-3] ${area.log}');
    expect(t.takeException(), isNull);
    sem.dispose();
    later.verify();
  });

  // ── P1L-10 긴급 행동은 표시 조정 때문에 늦추지 않는다 ─────────────────────────
  testWidgets('P1L-10 자정 퇴근(긴급) 100ms 확정 · 연장 제안 2초 — 퇴근 카드는 600 을 기다리지 않고 ≤200ms 에 보인다', (t) async {
    final gate = Completer<void>();
    final calls = _Calls();
    await _mount(
        t,
        _reads(calls,
            apps: _Plan([_overnightApp()], ms: 100),
            atts: _Plan([_overnightAtt()], ms: 100),
            idReqs: const _Plan([], ms: 100),
            renewals: _Plan([_proposal()], gate: gate)));
    await pumpAndRecord(t, const [], fromMs: 0, ms: 200);
    expect(findVisibleText('퇴근 기록이 필요해요'), findsOneWidget,
        reason: '판정289 §4 — 긴급 행동(퇴근)은 다른 출처를 기다리느라 늦추지 않는다');
    gate.complete();
    await pumpAndRecord(t, const [], fromMs: 200, ms: 600);
    expect(findVisibleTextContaining('계약 연장 제안'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  // ── P1L-4 늦은 자정 퇴근 ─────────────────────────────────────────────
  testWidgets('P1L-4 근태 1.5초 — 650ms 에 퇴근 카드·오늘0 단정 없음 + 확인 중 · 1.6초 뒤 퇴근 기록 카드', (t) async {
    final calls = _Calls();
    await _mount(
        t,
        _reads(calls,
            apps: _Plan([_overnightApp()], ms: 100),
            atts: _Plan([_overnightAtt()], ms: 1500),
            idReqs: const _Plan([], ms: 100)));
    final sem = t.ensureSemantics();
    final later = _Later();
    var now = await pumpAndRecord(t, const [], fromMs: 0, ms: 650);
    expect(findVisibleText('퇴근 기록이 필요해요'), findsNothing);
    expect(findVisibleText('오늘 확정된 근무가 없어요'), findsNothing, reason: '근태를 모르는 동안 정상 0 을 말하지 않는다');
    later.check(_pendingShown(t), '650ms: 약속·퇴근 출처가 끝나지 않았다 — 확인 중 표지');
    now = await pumpAndRecord(t, const [], fromMs: now, ms: 1000);
    expect(findVisibleText('퇴근 기록이 필요해요'), findsOneWidget, reason: '늦은 퇴근 반영 필수');
    expect(_pending, findsNothing);
    expect(t.takeException(), isNull);
    sem.dispose();
    later.verify();
  });

  // ── P1L-5 ERROR ≠ 0 ────────────────────────────────────────────────
  testWidgets('P1L-5 지원·근태·보완 실패 · 약관/신분증/연장 오류 — 실패 카드 유지 · 정상0 0 · 무기한 확인 중 0', (t) async {
    final calls = _Calls();
    await _mount(
        t,
        _reads(calls,
            apps: const _Plan([], ms: 200, fail: true),
            atts: const _Plan([], ms: 200, fail: true),
            idReqs: const _Plan([], ms: 200, fail: true),
            corrections: const _Plan(DocumentCorrectionSurface.failed, ms: 100),
            renewals: const _Plan([], ms: 100, fail: true),
            legal: const _Plan(_legalCurrent, ms: 100, fail: true)));
    await pumpAndRecord(t, const [], fromMs: 0, ms: 1500);
    expect(findVisibleText('계약해지 요청을 확인하지 못했어요'), findsOneWidget);
    expect(findVisibleText('어제 근무의 퇴근 여부를 확인하지 못했어요'), findsOneWidget);
    expect(findVisibleText('서류 요청을 확인하지 못했어요'), findsOneWidget);
    expect(findVisibleText('오늘 확정된 근무가 없어요'), findsNothing);
    expect(findVisibleText('이용약관이 변경되었습니다'), findsNothing, reason: '모르는 약관 상태를 미동의로 그리지 않는다(R7-LEGAL)');
    expect(_pending, findsNothing, reason: 'ERROR 는 끝난 상태다 — 확인 중으로 영원히 붙잡지 않는다');
    expect(t.takeException(), isNull);
  });

  // ── P1L-6 PARTIAL(200 건 상한) ─────────────────────────────────────────
  testWidgets('P1L-6 지원 200건(오늘 없음) — 오늘0 단정 0 · 일부 확인 안내(판정287 C287-01)', (t) async {
    final many = [for (var i = 0; i < 200; i++) _app('p$i', _k(12, 1 + (i % 20)), AppStatus.pending)];
    final calls = _Calls();
    await _mount(t, _reads(calls, apps: _Plan(many, ms: 100), atts: const _Plan([], ms: 100), idReqs: const _Plan([], ms: 100)));
    await pumpAndRecord(t, const [], fromMs: 0, ms: 1200);
    expect(findVisibleText('오늘 확정된 근무가 없어요'), findsNothing);
    expect(findVisibleText('오늘 일정을 모두 확인하지 못했어요. 내 일정에서 확인해 주세요'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  // ── P1L-7 같은 데이터 재조회 — 반복 변화 0 ───────────────────────────────
  testWidgets('P1L-7 앱 복귀 재조회(같은 응답 300ms) — 약속·해지 카드 유지 · 날짜 영역 흔들림 0', (t) async {
    final calls = _Calls();
    await _mount(
        t,
        _reads(calls,
            apps: _Plan([_today(), _terminating()], ms: 300),
            atts: const _Plan([], ms: 300),
            idReqs: const _Plan([], ms: 300)));
    var now = await pumpAndRecord(t, const [], fromMs: 0, ms: 1500);
    expect(findVisibleText('오늘의 약속'), findsOneWidget);
    final apps0 = calls.n('apps');
    final area = LayoutShiftRecorder('date-area', _area);
    area.sample(t, now);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    var heldEveryFrame = true;
    for (var i = 0; i < 60; i++) {
      await t.pump(const Duration(milliseconds: 16));
      now += 16;
      area.sample(t, now);
      if (findVisibleText('오늘의 약속').evaluate().isEmpty ||
          findVisibleText('나래 센터에서 계약해지를 요청했어요').evaluate().isEmpty) {
        heldEveryFrame = false;
      }
    }
    print('[P1L-7] held=$heldEveryFrame ${area.log}');
    expect(calls.n('apps'), apps0 + 1, reason: '재조회는 실제로 일어났다(대조)');
    expect(heldEveryFrame, isTrue, reason: '재조회 중에도 마지막 성공 값을 내리지 않는다(같은 데이터 반복 변화 0)');
    expect(area.shifts, 0, reason: area.log);
    expect(t.takeException(), isNull);
  });

  // ── P1L-8 스크롤 보존(위쪽 늦은 삽입) ────────────────────────────────────
  testWidgets('P1L-8 360×780 아래로 스크롤한 뒤 연장 제안이 늦게 도착 — 보이던 일자리 섹션 화면 위치 유지', (t) async {
    final gate = Completer<void>();
    final calls = _Calls();
    await _mount(t, _reads(calls, renewals: _Plan([_proposal()], gate: gate)), height: 780);
    var now = await pumpAndRecord(t, const [], fromMs: 0, ms: 1000);
    // 사용자가 일자리 섹션이 보일 때까지 내린다(수동 스크롤)
    await t.drag(find.byType(SingleChildScrollView).first, const Offset(0, -320));
    now = await pumpAndRecord(t, const [], fromMs: now, ms: 400);
    expect(_jobs, findsOneWidget);
    final before = _y(t, _jobs);
    final scrollBefore = t.state<ScrollableState>(find.byType(Scrollable).first).position.pixels;
    expect(scrollBefore, greaterThan(0));
    gate.complete();
    now = await pumpAndRecord(t, const [], fromMs: now, ms: 600);
    expect(findVisibleTextContaining('계약 연장 제안'), findsWidgets, reason: '늦은 필수응답은 트리에 들어온다');
    final after = _y(t, _jobs);
    print('[P1L-8] jobs y $before → $after · scroll $scrollBefore → '
        '${t.state<ScrollableState>(find.byType(Scrollable).first).position.pixels}');
    expect((after - before).abs(), lessThanOrEqualTo(1.0),
        reason: '보고 있던 내용은 위쪽 삽입으로 밀리지 않는다(판정290 D290-02 · 준비 노트 §1.4-G)');
    expect(t.takeException(), isNull);
  });

  // ── P1L-9 접근성 · 320/2.0 ─────────────────────────────────────────────
  testWidgets('P1L-9 320/2.0 — 첫 뼈대 확인 중 의미 이름 · 해지 카드 의미 tap · 최종 일자리 행동 도달 · 넘침 0', (t) async {
    final sem = t.ensureSemantics();
    final calls = _Calls();
    await _mount(
        t,
        _reads(calls,
            legal: const _Plan(_reconsent, ms: 100),
            apps: _Plan([_today(), _terminating()], ms: 300),
            atts: const _Plan([], ms: 300),
            idReqs: const _Plan([], ms: 300),
            corrections: const _Plan(DocumentCorrectionSurface.failed, ms: 150),
            renewals: _Plan([_proposal()], ms: 250)),
        width: 320,
        height: 1400,
        scale: 2.0);
    final later = _Later();
    await t.pump(const Duration(milliseconds: 16));
    later.check(_pendingShown(t), '16ms: 첫 뼈대 = 의미 이름 있는 확인 중 표지');
    await pumpAndRecord(t, const [], fromMs: 16, ms: 1500);
    expect(t.takeException(), isNull, reason: '넘침·예외 0');
    final term = findVisibleText('나래 센터에서 계약해지를 요청했어요');
    await t.scrollUntilVisible(term, 200, scrollable: find.byType(Scrollable).first);
    // 여기서는 tap action **존재**만 본다(실행 확인 아님). 의미 tap 실행은 P1L-5e(실패 행 다시 시도)가 맡는다.
    expect(t.getSemantics(term), containsSemantics(hasTapAction: true), reason: '해지 응답 카드에 의미 tap action 이 있다');
    await t.scrollUntilVisible(find.descendant(of: _jobs, matching: findVisibleText('일자리 더 보기')), 300,
        scrollable: find.byType(Scrollable).first);
    expect(find.descendant(of: _jobs, matching: findVisibleText('일자리 더 보기')), findsOneWidget);
    sem.dispose();
    later.verify();
  });

  // ═════════════════════════════════════════════════════════════════════
  // [판정290 D290-01] 일반 실패 행 — 신분증·연장 현재 ERROR 만 · 최대 1행 · 실재 카드 숨김 유지 · 실제 재조회
  // ═════════════════════════════════════════════════════════════════════
  group('P1L-5 D290-01 일반 실패 행', () {
    const errLabel = '일부 정보를 확인하지 못했어요 · 다시 시도';
    Future<SemanticsHandle> run(WidgetTester t, _Calls calls,
        {bool idFail = false, bool renewalFail = false, bool legalFail = false}) async {
      final sem = t.ensureSemantics();
      await _mount(
          t,
          _reads(calls,
              apps: _Plan([_terminating()], ms: 100),
              atts: const _Plan([], ms: 100),
              idReqs: _Plan(const [], ms: 100, fail: idFail),
              renewals: _Plan(const [], ms: 150, fail: renewalFail),
              legal: _Plan(_legalCurrent, ms: 50, fail: legalFail)));
      await pumpAndRecord(t, const [], fromMs: 0, ms: 1200);
      return sem;
    }

    for (final (id, idFail, renewalFail, legalFail, rows) in const [
      ('a 신분증만', true, false, false, 1),
      ('b 연장만', false, true, false, 1),
      ('c 둘 다', true, true, false, 1),
      ('d 약관만(R7-LEGAL 숨김 · 대상 아님)', false, false, true, 0),
      ('0 대조 — 오류 없음', false, false, false, 0),
    ]) {
      testWidgets('P1L-5$id — 일반 행 $rows · 실재 카드 오표시 0 · 출처 이름 0', (t) async {
        final calls = _Calls();
        final sem = await run(t, calls, idFail: idFail, renewalFail: renewalFail, legalFail: legalFail);
        expect(_errRow, rows == 1 ? findsOneWidget : findsNothing);
        expect(findVisibleText('일부 정보를 확인하지 못했어요'), rows == 1 ? findsOneWidget : findsNothing);
        if (rows == 1) {
          expect(t.getSemantics(_errRow).label, errLabel, reason: '출처·건수를 말하지 않는 일반 이름');
          expect(t.getSemantics(_errRow), containsSemantics(isButton: true, hasTapAction: true));
          expect(find.descendant(of: _errRow, matching: findVisibleTextContaining('신분증')), findsNothing);
          expect(find.descendant(of: _errRow, matching: findVisibleTextContaining('연장')), findsNothing);
        }
        expect(findVisibleTextContaining('계약 연장 제안'), findsNothing, reason: '못 읽은 제안을 지어내지 않는다');
        expect(findVisibleText('이용약관이 변경되었습니다'), findsNothing, reason: '모르는 약관을 미동의로 그리지 않는다');
        expect(findVisibleText('나래 센터에서 계약해지를 요청했어요'), findsOneWidget, reason: '성공한 다른 카드는 그대로');
        expect(_pending, findsNothing, reason: 'ERROR 는 terminal — 확인 중에 갇히지 않는다');
        expect(findVisibleText('계약해지 요청을 확인하지 못했어요'), findsNothing, reason: '자기 실패 카드와 겹치지 않는다(대조)');
        expect(t.takeException(), isNull);
        sem.dispose();
      });
    }

    testWidgets('P1L-5e 다시 시도(의미 tap 실행) — 실패 출처만 실제 재조회 · 진행 중 중복 0 · 성공(정상0)으로 해소 · 성공 카드 유지', (t) async {
      final calls = _Calls();
      final sem = t.ensureSemantics();
      await _mount(
          t,
          _reads(calls,
              apps: _Plan([_terminating()], ms: 100),
              atts: const _Plan([], ms: 100),
              idSeq: const [_Plan([], ms: 100, fail: true), _Plan([], ms: 300)]));
      await pumpAndRecord(t, const [], fromMs: 0, ms: 1200);
      expect(_errRow, findsOneWidget);
      final id0 = calls.n('id');
      final renewal0 = calls.n('renewal');
      final node = t.getSemantics(_errRow);
      node.owner!.performAction(node.id, SemanticsAction.tap);
      await t.pump(const Duration(milliseconds: 50));
      expect(calls.n('id'), id0 + 1, reason: '실패한 신분증 출처를 실제로 다시 읽는다');
      expect(calls.n('renewal'), renewal0, reason: '성공한 출처는 다시 읽지 않는다');
      expect(t.getSemantics(_errRow).label, '일부 정보를 다시 확인하고 있어요', reason: '재시도 중 표시');
      await t.tap(_errRow, warnIfMissed: false); // 진행 중 두 번째 탭
      await t.pump(const Duration(milliseconds: 50));
      expect(calls.n('id'), id0 + 1, reason: '진행 중에는 겹쳐 부르지 않는다');
      expect(findVisibleText('나래 센터에서 계약해지를 요청했어요'), findsOneWidget, reason: '재시도 중 성공 카드 유지');
      await pumpAndRecord(t, const [], fromMs: 0, ms: 500);
      expect(_errRow, findsNothing, reason: '현재 회차 성공(정상 0)만 실패를 지운다');
      expect(findVisibleText('나래 센터에서 계약해지를 요청했어요'), findsOneWidget);
      expect(t.takeException(), isNull);
      sem.dispose();
    });

    testWidgets('P1L-5f 다시 시도 중 홈 재조회가 출발 — 옛 회차의 늦은 성공은 버리고 새 회차 실패를 유지', (t) async {
      final calls = _Calls();
      final sem = t.ensureSemantics();
      final gate = Completer<void>();
      await _mount(
          t,
          _reads(calls,
              apps: const _Plan([], ms: 100),
              atts: const _Plan([], ms: 100),
              idSeq: [const _Plan([], ms: 100, fail: true), _Plan(const [], gate: gate), const _Plan([], ms: 50, fail: true)]));
      await pumpAndRecord(t, const [], fromMs: 0, ms: 1200);
      final node = t.getSemantics(_errRow);
      node.owner!.performAction(node.id, SemanticsAction.tap);
      await t.pump(const Duration(milliseconds: 50));
      expect(calls.n('id'), 2);
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed); // 새 홈 회차
      await pumpAndRecord(t, const [], fromMs: 0, ms: 400);
      expect(calls.n('id'), 3);
      gate.complete(); // 옛 회차(재시도)의 성공이 늦게 도착
      await pumpAndRecord(t, const [], fromMs: 0, ms: 400);
      expect(_errRow, findsOneWidget, reason: '새 회차가 실패했으면 옛 성공으로 오류를 지우지 않는다');
      expect(t.getSemantics(_errRow).label, errLabel, reason: '재시도가 끝나 다시 누를 수 있다');
      expect(t.takeException(), isNull);
      sem.dispose();
    });
  });

  // ═════════════════════════════════════════════════════════════════════
  // [판정290 D290-02] 위쪽 변화 보정 — 구역이 화면 위로 지나갔고 조작이 없을 때만 · 순Δ · 프레임당 1회
  // ═════════════════════════════════════════════════════════════════════
  group('P1L-8 D290-02 보정', () {
    final scroller = find.byType(Scrollable).first;
    double px(WidgetTester t) => t.state<ScrollableState>(scroller).position.pixels;
    double viewTop(WidgetTester t) => t.getTopLeft(scroller).dy;

    /// 360×780 · 공고·지원 0 · 연장 제안만 붙잡힘 → 600ms 상한 뒤 '확인 중' 행이 구역 하단에 남는다.
    Future<(Completer<void>, _Calls)> mountHeld(WidgetTester t,
        {List<RenewalProposalModel> late = const [], double drag = 320}) async {
      UserHomeScreen.debugZoneAnchorStats.clear();
      final gate = Completer<void>();
      final calls = _Calls();
      await _mount(t, _reads(calls, renewals: _Plan(late, gate: gate)), height: 780);
      await pumpAndRecord(t, const [], fromMs: 0, ms: 1000);
      expect(_pending, findsOneWidget, reason: '전제: 끝나지 않은 출처의 확인 중 행');
      if (drag > 0) {
        await t.drag(find.byType(SingleChildScrollView).first, Offset(0, -drag));
        await pumpAndRecord(t, const [], fromMs: 0, ms: 600);
      }
      return (gate, calls);
    }

    int stat(String k) => UserHomeScreen.debugZoneAnchorStats[k] ?? 0;

    testWidgets('P1L-8a 정지 · 구역 전체가 위 — 늦은 연장 카드(확인 중 행 교체) → 보던 일자리 ≤1px · 보정 1회 · 대상 정체성 유지', (t) async {
      final sem = t.ensureSemantics();
      final (gate, _) = await mountHeld(t, late: [_proposal()]);
      expect(t.getBottomLeft(_pending).dy, lessThanOrEqualTo(viewTop(t) + 0.5), reason: '변경 구역이 실제 viewport 위로 지나갔다');
      final cta = find.descendant(of: _jobs, matching: findVisibleText('일자리 더 보기'));
      final el0 = t.element(_jobs);
      final semId0 = t.getSemantics(cta).id;
      final y0 = _y(t, _jobs);
      final px0 = px(t);
      final rec = LayoutShiftRecorder('jobs', _jobs);
      rec.sample(t, 0);
      final pxs = <double>[px0];
      // 그려진 프레임의 위치 — 지속 콜백은 그리기(drawFrame) **뒤**·post-frame(보정) **앞**에 돈다. 다음 프레임 보정의 순간 이동을 잰다.
      final painted = <double>[];
      var recording = true;
      t.binding.addPersistentFrameCallback((_) {
        if (!recording) return;
        final e = _jobs.evaluate();
        if (e.isEmpty) return;
        final ro = e.first.renderObject;
        if (ro is RenderBox && ro.attached && ro.hasSize) painted.add(ro.localToGlobal(Offset.zero).dy);
      });
      addTearDown(() => recording = false);
      gate.complete();
      for (var ms = 16; ms <= 800; ms += 16) {
        await t.pump(const Duration(milliseconds: 16));
        rec.sample(t, ms);
        pxs.add(px(t));
      }
      var corrections = 0;
      for (var i = 1; i < pxs.length; i++) {
        if ((pxs[i] - pxs[i - 1]).abs() > 0.5) corrections++;
      }
      final maxMove = rec.samples.map((e) => e.$2).whereType<double>().map((y) => (y - y0).abs()).fold<double>(0, (a, b) => b > a ? b : a);
      recording = false;
      final paintedMax = painted.map((y) => (y - y0).abs()).fold<double>(0, (a, b) => b > a ? b : a);
      final paintedFrames = painted.where((y) => (y - y0).abs() > 0.5).length;
      print('[P1L-8a] y0=$y0 final=${_y(t, _jobs)} px $px0→${px(t)} corrections=$corrections '
          'postFrameMoves=${rec.shifts} postFrameMax=${maxMove.toStringAsFixed(1)} '
          'paintedShiftedFrames=$paintedFrames paintedMax=${paintedMax.toStringAsFixed(1)} '
          'stats=${UserHomeScreen.debugZoneAnchorStats} ${rec.log}');
      expect(paintedFrames, lessThanOrEqualTo(1), reason: '다음 프레임 보정 — 그려진 순간 이동은 최대 1프레임(0 이라고 주장하지 않는다)');
      expect(findVisibleTextContaining('계약 연장 제안'), findsOneWidget, reason: '늦은 필수응답은 들어온다(숨겨서 0 만들기 0)');
      expect(_pending, findsNothing);
      expect((_y(t, _jobs) - y0).abs(), lessThanOrEqualTo(1.0), reason: '정지 anchor 최종 오차 ≤1 논리px');
      expect(corrections, 1, reason: '순Δ 한 번 — 행 제거·카드 삽입을 따로 보정하지 않는다 · 중복 보정 0');
      expect(stat('applied'), 1);
      expect(stat('discarded'), 0);
      expect(identical(t.element(_jobs), el0), isTrue, reason: '보던 섹션 Element 유지');
      expect(t.getSemantics(cta).id, semId0, reason: '보던 버튼 의미 노드 유지(플랫폼 화면읽기 초점 자체는 미확인)');
      await t.scrollUntilVisible(cta, 200, scrollable: scroller);
      expect(cta, findsOneWidget, reason: '수동 도달');
      expect(t.takeException(), isNull);
      sem.dispose();
    });

    testWidgets('P1L-8b 최상단(offset 0) — 보정 0 · 자연 삽입(필요한 추가로 셈)', (t) async {
      final (gate, _) = await mountHeld(t, late: [_proposal()], drag: 0);
      expect(px(t), 0);
      final y0 = _y(t, _jobs);
      gate.complete();
      await pumpAndRecord(t, const [], fromMs: 0, ms: 600);
      print('[P1L-8b] jobs ${y0.toStringAsFixed(1)}→${_y(t, _jobs).toStringAsFixed(1)} stats=${UserHomeScreen.debugZoneAnchorStats}');
      expect(px(t), 0, reason: '최상단에서는 offset 을 바꾸지 않는다');
      expect(stat('scheduled'), 0);
      expect(_y(t, _jobs), greaterThan(y0), reason: '눈앞 삽입 — 필요한 추가');
      expect(t.takeException(), isNull);
    });

    testWidgets('P1L-8c 구역 일부가 보임(조금만 내림) — 보정 0', (t) async {
      final (gate, _) = await mountHeld(t, late: [_proposal()], drag: 40);
      expect(t.getBottomLeft(_pending).dy, greaterThan(viewTop(t)), reason: '전제: 구역 아래끝이 화면 안');
      final px0 = px(t);
      gate.complete();
      await pumpAndRecord(t, const [], fromMs: 0, ms: 600);
      expect(px(t), px0);
      expect(stat('scheduled'), 0);
      expect(t.takeException(), isNull);
    });

    testWidgets('P1L-8d 손가락 hold 중 도착 — 보정 0 · 손 뗀 뒤 누적 보정 0', (t) async {
      final (gate, _) = await mountHeld(t, late: [_proposal()]);
      final px0 = px(t);
      final g = await t.startGesture(t.getCenter(_jobs));
      gate.complete();
      await pumpAndRecord(t, const [], fromMs: 0, ms: 400);
      expect(px(t), px0, reason: 'hold 중 offset 변경 0');
      await g.cancel();
      await pumpAndRecord(t, const [], fromMs: 0, ms: 600);
      expect(px(t), px0, reason: '조작 종료 뒤 뒤늦은 보정 0');
      expect(stat('scheduled'), 0);
      expect(stat('applied'), 0);
      expect(t.takeException(), isNull);
    });

    testWidgets('P1L-8e 끌기·관성 중 도착 — 보정 0(이동은 사용자 것만) · 끝난 뒤 누적 0', (t) async {
      final (gate, _) = await mountHeld(t, late: [_proposal()]);
      final g = await t.startGesture(t.getCenter(_jobs));
      await g.moveBy(const Offset(0, -30));
      await t.pump(const Duration(milliseconds: 16));
      gate.complete();
      for (var i = 0; i < 5; i++) {
        await g.moveBy(const Offset(0, -10));
        await t.pump(const Duration(milliseconds: 16));
      }
      await g.up();
      await pumpAndRecord(t, const [], fromMs: 0, ms: 1200); // 관성 끝까지
      expect(stat('applied'), 0, reason: '끌기/관성 중 jumpTo 0 · 끝난 뒤 누적 Δ 적용 0');
      expect(t.takeException(), isNull);
    });

    testWidgets('P1L-8f 예약 뒤 입력(탭 시작) — 실행 직전 재검사로 폐기', (t) async {
      final (gate, _) = await mountHeld(t, late: [_proposal()]);
      final px0 = px(t);
      gate.complete();
      for (var i = 0; i < 20; i++) {
        await Future<void>.value(); // 프레임 없이 microtask 만 — 응답 반영(setState)과 보정 예약까지
      }
      expect(stat('scheduled'), 1, reason: '전제: 바뀌기 전 기하로 보정이 예약됐다');
      final g = await t.startGesture(t.getCenter(_jobs)); // 예약과 실행 사이의 새 입력
      await t.pump();
      expect(stat('discarded'), 1);
      expect(stat('applied'), 0);
      expect(px(t), px0);
      await g.cancel();
      await pumpAndRecord(t, const [], fromMs: 0, ms: 600);
      expect(px(t), px0, reason: '조작 종료 뒤 뒤늦은 보정 0');
      expect(t.takeException(), isNull);
    });

    testWidgets('P1L-8g 늦은 정상0(확인 중 행만 빠짐) — 음의 순Δ 보정 · ≤1px · 중복 0', (t) async {
      final (gate, _) = await mountHeld(t);
      final y0 = _y(t, _jobs);
      gate.complete();
      await pumpAndRecord(t, const [], fromMs: 0, ms: 800);
      print('[P1L-8g] jobs ${y0.toStringAsFixed(1)}→${_y(t, _jobs).toStringAsFixed(1)} stats=${UserHomeScreen.debugZoneAnchorStats}');
      expect(_pending, findsNothing);
      expect((_y(t, _jobs) - y0).abs(), lessThanOrEqualTo(1.0));
      expect(stat('applied'), 1);
      expect(t.takeException(), isNull);
    });
  });
}
