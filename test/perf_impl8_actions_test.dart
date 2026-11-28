// [PERF impl_8 · 2026-11-26] 행동 응답 속도 셀 + 같은 파일 정합성 교정(F291-C03 · C10) 시험.
//
//   A  출퇴근(L39·L40·P12) — 사업장 문서 미리 읽기는 목록을 막지 않는다 · 계약 목록 재사용은 같은 후보일 때만 ·
//      600ms 고정 대기 제거 · 퇴근 응답 isZeroWork · 단계 문구
//   B  위치 실패 이유(F291-C10) — 시간 초과·권한/서비스·측정 실패를 가짜 GPS 로 안내하지 않는다(가짜 위치는 그대로 거부)
//   C  업무 일괄 마감·재오픈(F291-C03) — 같은 배열을 업무마다 따로 덮어쓰던 구조 → 한 번에 적용(둘 다 반영) ·
//      결과 무시 금지(반영된 업무만 로컬 반영)
//   D  급여 확정 8일차(L50) — 근무일수·이전 세전 합계를 한 원장 응답으로 계산(예전 두 조회와 같은 식)
//   E  계약 발송(L51) — 독립 읽기 동시 시작 · 판정 순서 보존 · 진행 표시
// ignore_for_file: depend_on_referenced_packages
import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart'
    show PermissionDeniedException, LocationServiceDisabledException;
import 'package:intl/date_symbol_data_local.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ALfit/models/core/application_model.dart';
import 'package:ALfit/models/core/attendance_model.dart';
import 'package:ALfit/models/core/business_model.dart';
import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/models/core/user_region.dart';
import 'package:ALfit/models/core/work_detail_data.dart';
import 'package:ALfit/providers/notification_provider.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/screens/user/attendance_check_reads.dart';
import 'package:ALfit/screens/user/attendance_check_screen.dart';
import 'package:ALfit/services/firestore_service.dart';
import 'package:ALfit/services/tax_deduction_service.dart';
import 'package:ALfit/utils/location_helper.dart';

import 'support/checkin_contract_fixture.dart';
import 'support/visible_text.dart'; // [impl_21] TextLayout 문구는 보이는 글자로 찾는다

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

class _P extends UserProvider {
  @override
  UserModel? get currentUser => UserModel(
        uid: 'u1',
        username: 'u1',
        name: '김근로',
        email: 'u1@alfit.local',
        role: UserRole.USER,
        homeRegion: const UserRegion(province: '경기도', city: '평택시'),
        accountStatus: 'active',
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
}

DateTime _kst(int y, int mo, int d, [int h = 0, int mi = 0]) =>
    DateTime.utc(y, mo, d, h, mi).subtract(const Duration(hours: 9));

ApplicationModel _work() => ApplicationModel(
      id: 'app1',
      toId: 'to1',
      uid: 'u1',
      businessId: 'biz1',
      businessName: 'QA 사업장',
      toTitle: '당일 QA',
      status: AppStatus.confirmed,
      selectedWorkType: 'QA 분류',
      startTime: '20:00',
      endTime: '21:00',
      wage: 12000,
      workDate: _kst(2026, 10, 17).toLocal(),
      appliedAt: _kst(2026, 10, 17, 17, 57).toLocal(),
    );

String _src(String p) => File(p).readAsStringSync();

/// 주석을 뺀 코드(줄 주석만) — 문구 대조가 주석에 속지 않게 한다.
String _code(String s) => s
    .split('\n')
    .map((l) {
      final i = l.indexOf('//');
      return i >= 0 ? l.substring(0, i) : l;
    })
    .join('\n');

int _count(String hay, String needle) =>
    needle.allMatches(hay).length;

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
    await initializeDateFormatting('ko_KR', null);
  });

  group('A 출퇴근(L39·L40·P12)', () {
    testWidgets('A1 사업장 문서는 목록을 읽을 때 한 번 미리 받는다 — 응답이 없어도 목록은 그려진다',
        (tester) async {
      final asked = <String>[];
      final never = Completer<BusinessModel?>(); // 끝나지 않는 읽기
      var contractReads = 0;
      final apps = [_work()];
      final reads = AttendanceCheckReads(
        myApplications: (uid) async => apps,
        myContracts: (uid) async {
          contractReads++;
          return completedContractsFor(apps);
        },
        todayAttendance: ({required String userId, required String applicationId}) async =>
            null as AttendanceModel?,
        businessById: (id) {
          asked.add(id);
          return never.future;
        },
      );
      tester.view.physicalSize = const Size(390, 2200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<UserProvider>(create: (_) => _P()),
          ChangeNotifierProvider<NotificationProvider>(
              create: (_) => NotificationProvider()),
        ],
        child: MaterialApp(
            home: AttendanceCheckScreen(
                reads: reads, clock: () => _kst(2026, 10, 17, 19, 45).toLocal())),
      ));
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(asked, ['biz1'], reason: '오늘 근무 사업장을 한 번만 미리 받는다');
      expect(contractReads, 1);
      expect(findVisibleText('출근하기'), findsOneWidget,
          reason: '사업장 미리 읽기는 목록을 기다리게 하지 않는다');
    });

    test('A2 행동 경로 계약 — 화면을 비우지 않는 재조회·계약 재사용 조건·600ms 제거·서버 isZeroWork', () {
      final s = _code(_src('lib/screens/user/attendance_check_screen.dart'));
      expect(_count(s, '_loadTodayWorks(quiet: true, keepContracts: true)'), 2,
          reason: '출근·퇴근 성공 뒤 화면을 비우지 않고, 계약은 같은 후보일 때만 재사용');
      expect(s.contains('Duration(milliseconds: 600)'), isFalse,
          reason: 'both 폴백의 고정 600ms 대기를 두지 않는다');
      expect(s.contains('checkOutWithResult('), isTrue);
      expect(s.contains('final zeroFromServer = result.isZeroWork;'), isTrue);
      expect(s.contains('prevIds.containsAll(workIds)'), isTrue,
          reason: '[F291-C09] 후보가 바뀌면 계약 목록을 새로 받는다');
      expect(_count(s, 'loadingText: _stage'), 2, reason: '출근·퇴근 버튼 단계 문구');
      for (final st in ['시간 확인 중…', '위치 확인 중…', '출근 기록 중…', '퇴근 기록 중…']) {
        expect(s.contains("'$st'"), isTrue, reason: st);
      }
      // 첫 await 전에 잠근다(중복 탭 0).
      final ci = s.indexOf('Future<void> _checkIn(');
      final lock = s.indexOf('setState(() => _isProcessing = true);', ci);
      final firstAwait = s.indexOf('await ', ci);
      expect(lock, greaterThan(ci));
      expect(lock, lessThan(firstAwait));
    });

    test('A3 측정은 사용자가 누른 그 시도에서만 시작 — 화면 진입·lastKnown 0', () {
      final s = _code(_src('lib/screens/user/attendance_check_screen.dart'));
      expect(s.contains('getLastKnownPosition'), isFalse);
      expect(s.contains('getPositionStream'), isFalse);
      final init = s.substring(s.indexOf('void initState()'),
          s.indexOf('Future<void> _loadTodayWorks('));
      expect(init.contains('_startFixIfPermitted'), isFalse,
          reason: '화면을 여는 것만으로 측정하지 않는다');
      expect(s.contains('requestIfNeeded: false'), isTrue,
          reason: '미리 시작은 이미 허용된 권한에서만(요청 팝업 0)');
    });
  });

  group('B 위치 실패 이유(F291-C10)', () {
    test('B1 예외 → 이유 분류', () {
      expect(LocationHelper.classifyFixError(TimeoutException('t')),
          LocationFixFailure.timeout);
      expect(LocationHelper.classifyFixError(const PermissionDeniedException('d')),
          LocationFixFailure.permission);
      expect(LocationHelper.classifyFixError(const LocationServiceDisabledException()),
          LocationFixFailure.permission);
      expect(LocationHelper.classifyFixError(StateError('x')),
          LocationFixFailure.unavailable);
    });

    test('B2 가짜 위치일 때만 가짜 위치를 말한다', () {
      for (final f in [
        LocationFixFailure.timeout,
        LocationFixFailure.permission,
        LocationFixFailure.unavailable,
        null,
      ]) {
        expect(AttendanceCheckScreen.fixFailureMessageFor(f).contains('가짜'), isFalse,
            reason: '$f');
      }
      expect(AttendanceCheckScreen.fixFailureMessageFor(LocationFixFailure.mocked),
          contains('가짜 위치'));
      expect(AttendanceCheckScreen.fixFailureMessageFor(LocationFixFailure.timeout),
          contains('10초'));
    });

    test('B3 가짜 위치는 그대로 거부한다(판정 약화 0)', () {
      final h = _code(_src('lib/utils/location_helper.dart'));
      expect(h.contains('if (position.isMocked) {'), isTrue);
      expect(h.contains('return const LocationFix.failed(LocationFixFailure.mocked);'), isTrue);
      expect(h.contains('LocationAccuracy.high'), isTrue);
      expect(h.contains('timeLimit: Duration(seconds: 10)'), isTrue);
    });
  });

  group('C 업무 일괄 마감·재오픈(F291-C03)', () {
    Map<String, dynamic> wd(String type, String s, String e) =>
        WorkDetailData(workType: type, startTime: s, endTime: e, wage: 10000,
                requiredCount: 2, wageType: 'hourly')
            .toMap();
    WorkDetailData close(WorkDetailData d) => d.copyWith(
        isManualClosed: true, closedAt: DateTime.utc(2026, 11, 26), closedBy: 'admin');
    bool closed(dynamic m) => (m as Map)['isManualClosed'] == true;

    test('C1 반례 — 예전 방식(같은 사본을 업무마다 따로 덮어쓰기)은 하나를 잃는다', () {
      final snapshot = [wd('A', '09:00', '13:00'), wd('B', '14:00', '18:00')];
      // 두 체인이 같은 사본을 읽고 각자 한 업무만 고쳐 배열 전체를 쓴다 — 나중 쓰기가 이긴다.
      final chainA = FirestoreService.applyWorkDetailUpdates(snapshot, {'A_09:00_13:00'}, close);
      final chainB = FirestoreService.applyWorkDetailUpdates(snapshot, {'B_14:00_18:00'}, close);
      final lastWrite = chainB.raw; // A 가 먼저 쓰고 B 가 덮어쓴 결과
      expect(chainA.applied, {'A_09:00_13:00'});
      expect(closed(lastWrite[0]), isFalse, reason: 'A 마감이 유실된다(교정 전 구조의 결과)');
      expect(closed(lastWrite[1]), isTrue);
    });

    test('C2 교정 — 한 번에 적용하면 둘 다 반영된다', () {
      final snapshot = [wd('A', '09:00', '13:00'), wd('B', '14:00', '18:00')];
      final r = FirestoreService.applyWorkDetailUpdates(
          snapshot, {'A_09:00_13:00', 'B_14:00_18:00'}, close);
      expect(r.applied, {'A_09:00_13:00', 'B_14:00_18:00'});
      expect(closed(r.raw[0]), isTrue);
      expect(closed(r.raw[1]), isTrue);
    });

    test('C3 트랜잭션 재시도처럼 최신 배열 위에 다시 적용해도 앞 변경을 보존한다', () {
      final snapshot = [wd('A', '09:00', '13:00'), wd('B', '14:00', '18:00')];
      final first = FirestoreService.applyWorkDetailUpdates(snapshot, {'A_09:00_13:00'}, close);
      final retried = FirestoreService.applyWorkDetailUpdates(first.raw, {'B_14:00_18:00'}, close);
      expect(closed(retried.raw[0]), isTrue);
      expect(closed(retried.raw[1]), isTrue);
    });

    test('C4 찾지 못한 업무는 반영으로 세지 않는다 · 해석 못 한 항목은 떨어뜨리지 않는다', () {
      final snapshot = <dynamic>[wd('A', '09:00', '13:00'), 'garbage'];
      final r = FirestoreService.applyWorkDetailUpdates(
          snapshot, {'A_09:00_13:00', 'Z_00:00_01:00'}, close);
      expect(r.applied, {'A_09:00_13:00'});
      expect(r.raw.length, 2);
      expect(r.raw[1], 'garbage');
    });

    test('C5 서비스·화면 경로 — 트랜잭션 1회 · 결과 무시 금지 · 동시 체인 0', () {
      final svc = _code(_src('lib/services/firestore_service.dart'));
      final body = svc.substring(svc.indexOf('_updateWorkDetailsInArrayAtomic({'));
      expect(body.contains('_firestore.runTransaction('), isTrue);
      expect(body.contains('await tx.get(docRef)'), isTrue);
      final dlg = _code(_src('lib/screens/business_admin/dialogs/work_detail_management_dialog.dart'));
      expect(dlg.contains('Future.wait('), isFalse,
          reason: '같은 배열을 동시에 덮어쓰는 체인을 다시 만들지 않는다');
      for (final call in ['closeWorkDetails(', 'reopenWorkDetails(', 'stopEmergencyRecruitments(']) {
        expect(dlg.contains('firestoreService.$call'), isTrue, reason: call);
      }
      expect(_count(dlg, 'works.where((w) => r.applied.contains(w.id))'), 3,
          reason: '서버가 반영한 업무만 로컬에 반영한다');
      expect(dlg.contains('isLoading: _isProcessing'), isTrue, reason: 'P12 처리 중 표시');
    });
  });

  group('D 급여 확정 8일차(L50)', () {
    Map<String, dynamic> att(String id, String day, String ws,
            {int gross = 0, String status = 'completed'}) =>
        {
          'id': id,
          'userId': 'w1',
          'businessId': 'b1',
          'workDate': Timestamp.fromDate(DateTime.parse('${day}T00:00:00+09:00')),
          'createdAt': Timestamp.fromDate(DateTime.parse('${day}T09:00:00+09:00')),
          'status': status,
          'wageStatus': ws,
          'wageDetail': {'totalAmount': gross},
        };

    test('D1 한 원장으로 근무일수·이전 세전 합계를 예전 식 그대로 계산', () {
      final items = <dynamic>[
        att('self', '2026-11-08', 'pending', gross: 999), // 자기 자신 제외
        att('a', '2026-11-01', 'calculated', gross: 100000),
        att('b', '2026-11-01', 'confirmed', gross: 20000), // 같은 날 → 일수 1
        att('c', '2026-11-02', 'transferred', gross: 30000),
        att('d', '2026-11-03', 'confirmed', gross: 40000, status: 'NO_SHOW'), // 노쇼 제외
        att('e', '2026-11-04', 'pending', gross: 50000), // 미확정 제외
      ];
      expect(TaxDeductionService.monthlyWorkDaysFromItems(items, excludeAttendanceId: 'self'), 2);
      expect(TaxDeductionService.prevGrossTotalFromItems(items, 'self'), 150000);
    });

    test('D2 확정 경로는 같은 조회를 한 번만 부른다 — 열 때 미리 받는 캐시 0', () {
      final d = _code(_src('lib/screens/business_admin/dialogs/wage_confirm_dialog.dart'));
      expect(d.contains('_getPrevGrossTotal('), isFalse);
      expect(d.contains('TaxDeductionService.getMonthlyWorkDays('), isFalse);
      expect(_count(d, '_day8MonthItems('), 2, reason: '정의 1 + 사용 1');
      expect(d.contains('_prefetchDay8MonthItems'), isFalse, reason: '판정291 §L50');
      // payScheduleType 읽기는 8일차 확인 전에 출발하고, CF 확정 전에 끝난다.
      final start = d.indexOf('final payScheduleFetch = Future.wait(');
      final day8 = d.indexOf('final day8AppIds = _pendingSelectedIds');
      final awaitPs = d.indexOf('await payScheduleFetch;');
      final cf = d.indexOf('final cfResults = await Future.wait(');
      expect(start, greaterThan(-1));
      expect(start, lessThan(day8));
      expect(awaitPs, greaterThan(day8));
      expect(awaitPs, lessThan(cf));
    });
  });

  group('E 계약 발송(L51)', () {
    test('E1 독립 읽기는 동시에 시작하고 판정은 예전 순서(업무 → 사업장 → 지원서) · 진행 표시', () {
      final f = _code(_src('lib/screens/business_admin/contract_dispatch_flow.dart'));
      final wdStart = f.indexOf('final workDetailsFuture =');
      final bizStart = f.indexOf('final businessFuture = fs.getBusinessById(businessId);');
      final appStart = f.indexOf('final freshDocFuture = FirebaseFirestore.instance');
      final wdAwait = f.indexOf('await workDetailsFuture;');
      final bizAwait = f.indexOf('await businessFuture;');
      final appAwait = f.indexOf('await freshDocFuture;');
      for (final i in [wdStart, bizStart, appStart, wdAwait, bizAwait, appAwait]) {
        expect(i, greaterThan(-1));
      }
      expect(appStart, lessThan(wdAwait), reason: '세 읽기가 모두 첫 대기 전에 출발');
      expect(wdAwait, lessThan(bizAwait));
      expect(bizAwait, lessThan(appAwait));
      expect(f.contains("GlobalLoadingController.show('계약서를 준비하는 중...')"), isTrue);
      expect(f.contains('hideLoading();'), isTrue);
    });
  });
}
