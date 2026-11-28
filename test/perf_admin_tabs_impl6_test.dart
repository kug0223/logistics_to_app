// ignore_for_file: depend_on_referenced_packages
// [PERF-ADMIN-TABS · impl_6] 관리자 탭·다이얼로그 진입 속도 — analysis_2_tabs §6 (L14 · L16 · L22 · L25 · L27 · P8).
//
//   각 셀은 변경을 되돌리면 실패하도록 짰다(역변경 대조는 보고서 · mutation_check6).
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';

import 'package:ALfit/models/core/attendance_model.dart';
import 'package:ALfit/models/core/business_member_model.dart';
import 'package:ALfit/models/core/business_model.dart';
import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/providers/notification_provider.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/screens/business_admin/payroll/payroll_overview_reads.dart';
import 'package:ALfit/screens/business_admin/payroll/payroll_overview_screen.dart';
import 'package:ALfit/services/business_posting_readiness.dart';
import 'package:ALfit/services/firestore_service.dart';

class _FakeApp extends Fake with MockPlatformInterfaceMixin implements FirebaseAppPlatform {
  @override
  String get name => defaultFirebaseAppName;
  @override
  FirebaseOptions get options =>
      const FirebaseOptions(apiKey: 'k', appId: 'a', messagingSenderId: 's', projectId: 'p');
}

class _FakeCore extends FirebasePlatform with MockPlatformInterfaceMixin {
  @override
  FirebaseAppPlatform app([String name = defaultFirebaseAppName]) => _FakeApp();
  @override
  Future<FirebaseAppPlatform> initializeApp({String? name, FirebaseOptions? options}) async => _FakeApp();
  @override
  List<FirebaseAppPlatform> get apps => [_FakeApp()];
}

String _code(String p) => File(p)
    .readAsStringSync()
    .replaceAll('\r\n', '\n')
    .split('\n')
    .where((l) => !l.trimLeft().startsWith('//'))
    .join('\n');

String _bodyOf(String src, String sig) {
  final at = src.indexOf(sig);
  expect(at, isNot(-1), reason: '$sig 가 없다');
  final m = RegExp(r'\)\s*(async\s*)?\{').firstMatch(src.substring(at));
  final open = at + m!.end - 1;
  var depth = 0;
  for (var i = open; i < src.length; i++) {
    if (src[i] == '{') depth++;
    if (src[i] == '}') {
      depth--;
      if (depth == 0) return src.substring(at, i + 1);
    }
  }
  return src.substring(at);
}

String _flat(String s) => s.replaceAll(RegExp(r'\s+'), ' ');

const _ops = 'lib/screens/business_admin/workforce_management/workforce_operational_view.dart';
const _wfRoot = 'lib/screens/business_admin/workforce_management/workforce_root_screen.dart';
const _jobs = 'lib/screens/business_admin/jobs_root_screen.dart';
const _overview = 'lib/screens/business_admin/payroll/payroll_overview_screen.dart';
const _dash = 'lib/screens/business_admin/payroll/payroll_payment_dashboard_screen.dart';
const _att = 'lib/screens/business_admin/dialogs/attendance_status_dialog.dart';
const _wa = 'lib/screens/business_admin/dialogs/work_applicants_dialog.dart';
const _slot = 'lib/screens/business_admin/dialogs/slot_batch_select_dialog.dart';
const _wdts = 'lib/services/work_detail_time_service.dart';
const _fixed = 'lib/screens/business_admin/dialogs/fixed_worker_management_dialog.dart';
const _card = 'lib/widgets/admin/cards/admin_to_group_card.dart';
const _day = 'lib/screens/business_admin/dialogs/day_applicants_dialog.dart';

// ── 급여 개요 하네스(payroll_annual_read_48_test 와 같은 모양) ──────────────────
class _WageAdmin extends UserProvider {
  @override
  UserModel? get currentUser => UserModel(uid: 'admin1', username: 'admin1', name: '김관리', email: 'a@alfit.local',
      role: UserRole.BUSINESS_ADMIN, managedBusinessIds: const ['biz1']);
  @override
  bool get isSubAdmin => false;
  @override
  String? get effectiveBusinessId => null;
  @override
  PermissionCheck checkCurrentBusiness(bool Function(MemberPermissions p) check) => PermissionCheck.allowed;
  @override
  PermissionCheck checkForBusiness(String businessId, bool Function(MemberPermissions p) check) =>
      PermissionCheck.allowed;
  @override
  bool can(bool Function(MemberPermissions p) check) => true;
}

BusinessModel _biz() => BusinessModel(id: 'biz1', name: '강남 물류센터', ownerId: 'admin1', businessNumber: '000-00-00000',
    address: '서울', category: '물류', subCategory: '창고', isApproved: true, createdAt: DateTime(2026, 1, 1));

final int _year = DateTime.now().year;
final int _month = DateTime.now().month;
String _ym(int m) => '$_year-${m.toString().padLeft(2, '0')}';

List<Map<String, dynamic>> _items(int m) => [
      for (var i = 0; i < 5; i++)
        {
          'id': 'a${m}_$i',
          'yearMonth': _ym(m),
          'wageStatus': i.isEven ? 'confirmed' : 'transferred',
          'status': 'present',
          'finalWage': 50000,
          'userId': 'w$i',
        },
    ];

PayrollOverviewReads _reads(Map<String, int> calls,
        {Future<List<AttendanceModel>> Function(String)? outstanding}) =>
    PayrollOverviewReads(
      businesses: ({required bool isSubAdmin, required String? effectiveBusinessId, required List<String> managedIds}) async =>
          [_biz()],
      payrollSummaries: ({required String businessId, required int year}) async {
        calls.update('summaries', (v) => v + 1, ifAbsent: () => 1);
        return const [];
      },
      adminAttendances: ({required String businessId, required String yearMonthGte, required String yearMonthLte}) async {
        calls.update('ledger:$yearMonthGte', (v) => v + 1, ifAbsent: () => 1);
        final m = int.parse(yearMonthGte.split('-')[1]);
        return (items: _items(m), limitReached: false);
      },
      workerSummaries: (_) async => const [],
      repairSummary: ({required String businessId, required String yearMonth}) async {},
      todayPaymentCount: (_) async {
        calls.update('todayCount', (v) => v + 1, ifAbsent: () => 1);
        return 0;
      },
      outstandingRecords: outstanding,
    );

Future<void> _pumpOverview(WidgetTester t, PayrollOverviewReads reads) async {
  t.view.physicalSize = const Size(392, 2400);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider<UserProvider>(create: (_) => _WageAdmin()),
      ChangeNotifierProvider<NotificationProvider>(create: (_) => NotificationProvider()),
    ],
    child: MaterialApp(home: PayrollOverviewScreen(reads: reads)),
  ));
  for (var i = 0; i < 20; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
  });

  // ── L14 ─────────────────────────────────────────────────────────────
  group('[L14] 근무 탭은 공고 controller 를 기다리지 않는다', () {
    test('L14-1 운영 화면 build 에 controller 구독·첫 로드 gate 가 없다', () {
      final build = _flat(_bodyOf(_code(_ops), 'Widget build(BuildContext context)'));
      expect(build.contains('context.watch<WorkforceController>()'), isFalse,
          reason: '공고 notify 마다 근무 화면 전체가 다시 그려진다');
      expect(build.contains('hasLoadedOnce'), isFalse, reason: '공고 첫 로드를 기다리는 전체 스피너');
      expect(build.contains("LoadingWidget(message: '인력 정보를 불러오는 중...')"), isFalse);
      // 자체 로딩·오류 표면은 그대로다.
      expect(build.contains('_isLoadingData'), isTrue);
      expect(build.contains('_buildErrorState()'), isTrue);
    });

    test('L14-2 근무 탭이 공고 목록 로드를 출발시키지 않는다(03O.1 소유권 = 공고 탭)', () {
      final root = _code(_wfRoot);
      expect(root.contains('_controller.load('), isFalse);
      expect(root.contains('_controller.reload('), isFalse);
    });

    test('L14-3 머리말 사업장 이름은 운영 화면 _ensureBusinesses 결과가 먼저 · 없으면 controller', () {
      final ops = _code(_ops);
      final fetch = _bodyOf(ops, 'Future<List<BusinessModel>> _fetchBusinesses(');
      expect(fetch.indexOf('widget.onBusinessesResolved?.call(result)'),
          greaterThan(fetch.indexOf('_cachedBusinesses = result;')),
          reason: '성공(캐시 교체) 뒤에만 알린다 — 실패·이전값 경로는 알리지 않는다');
      final root = _flat(_code(_wfRoot));
      expect(root.contains('onBusinessesResolved: _onBusinessesResolved'), isTrue);
      final label = _flat(_bodyOf(_code(_wfRoot), 'String _computeScopeLabel('));
      expect(label.indexOf('_viewBusinessNames'), lessThan(label.indexOf('controller.items.isNotEmpty')));
      expect(label.contains('controller.knownBusinessNames'), isTrue);
    });
  });

  // ── L16 (+ 근본 수정) ───────────────────────────────────────────────
  group('[L16] 준비 상태를 다시 세는 동안 이전 값으로 그린다', () {
    test('L16-1 공고 탭은 공용 판단(displayValue)으로 그린다', () {
      final b = _flat(_code(_jobs));
      expect(b.contains('final r = snap.displayValue;'), isTrue);
      expect(b.contains('final unknown = r == null;'), isTrue);
      expect(b.contains('final unknown = !snap.isResolved;'), isFalse,
          reason: 'resolved 만 보면 복귀 force 재조회마다 목록이 트리에서 빠진다');
    });

    test('L16-2 displayValue — resolved · loading+이전값 = 값 / idle · failed · 이전값 없는 loading = null', () {
      const v = FirstPostingReadiness(
          hasAnyBusiness: true, businessReady: true, workTypesReady: true,
          contractTemplateReady: true, sealReady: true);
      expect(const FirstPostingReadinessSnapshot(status: FirstPostingReadinessStatus.resolved, value: v).displayValue, v);
      expect(const FirstPostingReadinessSnapshot(status: FirstPostingReadinessStatus.loading, value: v).displayValue, v);
      expect(const FirstPostingReadinessSnapshot(status: FirstPostingReadinessStatus.loading).displayValue, isNull);
      expect(const FirstPostingReadinessSnapshot(status: FirstPostingReadinessStatus.failed, value: v).displayValue,
          isNull, reason: '실패는 모름이다');
      expect(const FirstPostingReadinessSnapshot.idle().displayValue, isNull);
    });

    test('L16-3 재발 방지 — 화면이 `isResolved ? …value : null` 을 따로 쓰지 않는다(lib 전수)', () {
      final hits = <String>[];
      for (final f in Directory('lib').listSync(recursive: true).whereType<File>()) {
        if (!f.path.endsWith('.dart')) continue;
        if (RegExp(r'isResolved\s*\?\s*\w+\.value\s*:\s*null').hasMatch(_code(f.path))) hits.add(f.path);
      }
      expect(hits, isEmpty, reason: '표시 판단은 FirstPostingReadinessSnapshot.displayValue 하나로');
    });
  });

  // ── 근본 수정: 먼저 출발시킨 future 의 실패 ──────────────────────────
  group('[ROOT-FUTURE] 먼저 출발시키고 나중에 await 하는 future', () {
    test('RF-1 재현 — 다른 await 중에 먼저 실패하면 처리되지 않은 오류로 보고된다 · ignore() 면 0', () async {
      Future<int> run({required bool ignore}) async {
        var uncaught = 0;
        final done = Completer<void>();
        runZonedGuarded(() async {
          final early = Future<int>.delayed(const Duration(milliseconds: 5), () => throw StateError('x'));
          if (ignore) early.ignore();
          await Future<void>.delayed(const Duration(milliseconds: 30));
          try {
            await early;
          } catch (_) {}
          done.complete();
        }, (e, s) => uncaught++);
        await done.future;
        return uncaught;
      }

      expect(await run(ignore: false), 1, reason: 'main 은 이것을 Crashlytics fatal 로 기록한다');
      expect(await run(ignore: true), 0);
      // await 하는 쪽은 ignore 뒤에도 같은 오류를 받는다(실패 의미 보존).
      final f = Future<int>.error(StateError('y'))..ignore();
      await expectLater(f, throwsStateError);
    });

    test('RF-2 재발 방지 — 담당 파일의 나중-await future 는 ignore() 가 붙어 있다', () {
      final wa = _code(_wa);
      for (final name in ['userMapFuture', 'weeklyMapFuture', 'contractMapFuture', 'hasWorkedFuture', 'idCardFuture']) {
        expect(wa.contains('$name.ignore();'), isTrue, reason: 'work_applicants_dialog: $name');
      }
      final fx = _code(_fixed);
      for (final name in ['workTypesFuture', 'proposalsFuture']) {
        expect(fx.contains('$name.ignore();'), isTrue, reason: 'fixed_worker: $name');
      }
      expect(fx.contains('scheduleRequestsFuture?.ignore();'), isTrue);
      expect(_code(_wdts).contains('toDocsFuture.ignore();'), isTrue);
      // 같은 패턴의 다른 담당 파일(관리자 · L2 provider) — 근본 수정 범위.
      final more = <String, List<String>>{
        _att: ['workDetailFuture'],
        _day: ['idCardFuture', 'hasWorkedFuture', 'noShowFuture'],
        _overview: ['ledgerFuture'],
        'lib/screens/business_admin/business_admin_home_screen.dart': ['rosterFuture'],
        'lib/providers/user_provider.dart': ['namesFuture', 'permMapFuture'],
      };
      more.forEach((file, names) {
        final c = _code(file);
        for (final n in names) {
          expect(c.contains('$n.ignore();'), isTrue, reason: '$file: $n');
        }
      });
    });
  });

  // ── L22 ─────────────────────────────────────────────────────────────
  group('[L22] 급여 개요 복귀 재조회 범위', () {
    testWidgets('L22-1 월 상세에서 돌아오면 그 달 원장 + 연 요약만 다시 읽는다', (t) async {
      final calls = <String, int>{};
      await _pumpOverview(t, _reads(calls));
      final before = Map<String, int>.from(calls);
      expect(before['ledger:${_ym(_month)}'], 1);
      await t.tap(find.text('$_month월').first);
      for (var i = 0; i < 10; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
      final nav = t.state<NavigatorState>(find.byType(Navigator).first);
      nav.pop();
      for (var i = 0; i < 15; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
      expect(calls['ledger:${_ym(_month)}'], 2, reason: '이 달은 다시 읽는다');
      for (var m = 1; m < _month; m++) {
        expect(calls['ledger:${_ym(m)}'], before['ledger:${_ym(m)}'],
            reason: '$m월 원장을 다시 읽었다(예전 11개월 재조회)');
      }
      expect(calls['summaries'], (before['summaries'] ?? 0) + 1, reason: '연 요약은 한 번');
      expect(t.takeException(), isNull);
    });

    test('L22-2 배너 → 대시보드: 같은 목록 전달 · 바뀌었을 때만 재조회', () {
      final o = _flat(_code(_overview));
      expect(o.contains('initialOutstanding: seedOk ? seed.records : null'), isTrue);
      expect(o.contains('onMutated: () => mutated = true'), isTrue);
      expect(o.indexOf('if (!mutated) return;'), lessThan(o.lastIndexOf('_loadTodayCount(); _loadYear(_selectedYear);')));
      final d = _code(_dash);
      final loadAll = _bodyOf(d, 'Future<void> _loadAllOutstanding(');
      expect(_flat(loadAll).contains('final records = seed ?? await _payService.getAllOutstandingWages('), isTrue);
      // 처리 뒤 갱신 경로 전부가 "바뀌었다" 를 알린다.
      expect(_bodyOf(d, 'void _refreshAfterMutation(').contains('_markMutated();'), isTrue);
      expect(_flat(_bodyOf(d, 'Future<void> _load({')).contains('if (!withRequestTabs || afterMutation) _markMutated();'),
          isTrue);
    });
  });

  // ── L25 ─────────────────────────────────────────────────────────────
  test('[L25] 전체 미이체 모드는 월 조회를 화면 전체 스피너 조건에서 뺀다', () {
    final d = _flat(_code(_dash));
    expect(d.contains("(_isLoading && !widget.showAllOutstanding) ? const LoadingWidget(message: '급여 현황 불러오는 중...')"),
        isTrue);
  });

  // ── L27 ─────────────────────────────────────────────────────────────
  group('[L27] 다이얼로그 중복·직렬 제거', () {
    test('L27-1 근태 현황 — 받은 사업장 문서가 있으면 businessById 를 부르지 않는다', () {
      final a = _flat(_code(_att));
      final given = a.indexOf('final given = widget.businesses?.where((b) => b.id == bizIdForLoad).firstOrNull;');
      expect(given, greaterThan(-1));
      final guard = a.indexOf('if (given != null) { _attendanceRules = given.attendanceRules; _rulesLoadedForBusinessId = bizIdForLoad; return null; }');
      expect(guard, greaterThan(given), reason: '받은 문서가 있으면 그 자리에서 끝낸다');
      expect(guard, lessThan(a.indexOf('await _reads.businessById(bizIdForLoad)')));
    });

    test('L27-2 인력 현황 — 신분증 배치는 지원서 직후 · 슬롯 하루 근무 이력은 주간 근태에서', () {
      final w = _flat(_code(_wa));
      final idCard = w.indexOf('final idCardFuture = _reads.idCardStatusBatch(');
      expect(idCard, greaterThan(-1));
      expect(idCard, lessThan(w.indexOf('final userMap = await userMapFuture;')),
          reason: '사용자 문서를 다 받은 뒤에야 출발했다');
      expect('_reads.idCardStatusBatch('.allMatches(w).length, 1, reason: '신분증 배치는 한 번(앞에서 출발한 것)');
      expect(w.contains('final idCardAll = await idCardFuture;'), isTrue);
      expect(w.contains('weeklyMapFuture.then( (m) => attendanceHasWorkedMap('), isTrue);
      expect(w.contains('onError: (Object _) => separate(),'), isTrue, reason: '주간 실패 시 예전처럼 하루치를 따로');
    });

    test('L27-3 근무 이력 판정식은 하나(공용 함수)다', () {
      final attFs = _code('lib/services/firestore/attendance_firestore.dart');
      expect(_bodyOf(attFs, 'Future<Map<String, bool>> loadHasWorkedMap(').contains('attendanceHasWorkedMap(atts)'), isTrue);
    });

    test('L27-4 판정식 동치 — 체크인(결근·노쇼 제외) 또는 급여 확정/이체', () {
      AttendanceModel a(String uid, {DateTime? checkIn, String status = 'present', String wage = 'pending'}) =>
          AttendanceModel(
            id: uid, applicationId: 'app_$uid', userId: uid, businessId: 'b', businessName: 'b',
            workDate: DateTime.utc(2026, 11, 26), workType: 'x', status: status,
            wageStatus: wage, adminConfirmed: false, createdAt: DateTime.utc(2026, 11, 26), checkInAt: checkIn,
          );
      final m = attendanceHasWorkedMap([
        a('u1', checkIn: DateTime.utc(2026, 11, 26, 1)),
        a('u2', checkIn: DateTime.utc(2026, 11, 26, 1), status: AttendanceModel.statusNoShow),
        a('u3', wage: AttendanceModel.wageConfirmed),
        a('u4'),
      ]);
      expect(m, {'u1': true, 'u3': true});
    });

    test('L27-5 슬롯 선택 — preload 로 바로 그리고 서버 확인 전 실행 잠금', () {
      final s = _flat(_code(_slot));
      expect(s.contains('onPressed: (_selectedIds.isEmpty || _verifying) ? null'), isTrue);
      expect(s.contains('_selectedIds.removeWhere((id) => !valid.contains(id));'), isTrue,
          reason: '서버가 돌려주지 않은 날짜를 선택에 남기지 않는다');
      final init = _flat(_bodyOf(_code(_slot), 'void initState()'));
      expect(init.contains('_loadSlots();'), isTrue, reason: 'seed 가 있어도 서버 재확인');
      // [impl_41] + '종료한 날짜 다시 정리'(batchCleanup) 선택 창도 같은 preload 를 쓴다 → 5.
      expect('seedSlots: _seedSlots(),'.allMatches(_code(_card)).length, 5);
    });

    test('L27-6 WorkDetailTime — 슬롯 문서와 TO 문서를 함께 보낸다(처리 순서는 그대로)', () {
      final b = _flat(_bodyOf(_code(_wdts), 'static Future<Map<String, dynamic>> load('));
      final toStart = b.indexOf('final toDocsFuture =');
      expect(toStart, greaterThan(-1));
      expect(toStart, lessThan(b.indexOf('final slotDocs = await slotDocsFuture;')));
      expect(b.indexOf('for (final doc in slotDocs)'), lessThan(b.indexOf('final toDocs = await toDocsFuture;')),
          reason: '맵에 넣는 순서(슬롯 → TO)가 바뀌면 폴백키 결과가 달라진다');
    });

    test('L27-7 고정 근무자 — 갱신 제안(②)을 지원서(①)와 함께 출발', () {
      final b = _flat(_bodyOf(_code(_fixed), 'Future<void> _readFixedWorkers('));
      expect(b.indexOf('final proposalsFuture = _firestoreService.getPendingRenewalProposals(businessId);'),
          lessThan(b.indexOf('final allApps = await appsFuture;')));
      expect(b.contains('(await proposalsFuture)'), isTrue);
    });
  });

  // ── P8 ──────────────────────────────────────────────────────────────
  group('[P8] 공고 카드 → 당일 명단 즉시 열기', () {
    test('P8-1 카드는 사업장 문서를 기다리지 않고 연다', () {
      final b = _flat(_bodyOf(_code(_card), 'Future<void> _showSlotRoster('));
      expect(b.contains('await widget.firestoreService.getBusinessById'), isFalse);
      expect(b.contains('businessesFuture: bizFuture,'), isTrue);
    });

    test('P8-2 사업장 문서가 필요한 행동은 받기 전 실행 0', () {
      final d = _code(_day);
      expect('if (!_businessesReadyOrHint()) return;'.allMatches(d).length, greaterThanOrEqualTo(4));
      expect(RegExp(r'widget\.businesses(?!Future)').allMatches(d).length, 1,
          reason: '초기값 한 곳 외 모든 사용처가 _businesses(받은 뒤 갱신되는 목록)를 본다');
    });
  });
}
