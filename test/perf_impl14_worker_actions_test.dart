// ignore_for_file: depend_on_referenced_packages
// [PERF impl_14 · 2026-11-26] 근로자 행동 — P12 · L44 · L45 · L46 · L18 같은 패턴(내 지원).
//
//   A  누른 즉시 잠금·처리 중(공고 상세 지원·초대 수락) — 첫 await 전에 잠근다
//   B  세무 축 미리 읽기(L44) — 공고 상세·내 지원·지원 시트(AWD)가 같은 규칙(60초 · 성공만)으로 쓴다
//   C  장기 지원(L45) — 업무별 직렬 for-await 0 · 동시 최대 4 · 결과 순서 보존 · 예외는 '결과 모름'
//   D  확정 취소 뒤 재조회(L46) — 독립 3개 동시 · 지원 상태에 기대는 장기 범위 재계산은 그 뒤
//   E  내 지원 목록(L46 SWR · L18 같은 패턴) — 다시 읽는 동안 비우지 않음 · 자동 이어읽기 두 상한 ·
//      상한에 닿아도 '없다'고 하지 않음 · 처음 연 묶음이 비면 이어 읽음 · 대기 취소 진행 표시
//   F  퇴사 요청 다이얼로그 — 성공하면 닫는다(낡은 목록을 남기지 않음)
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ALfit/models/core/application_model.dart';
import 'package:ALfit/models/core/attendance_model.dart';
import 'package:ALfit/models/core/employment_contract_model.dart';
import 'package:ALfit/models/core/to_model.dart';
import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/models/core/user_region.dart';
import 'package:ALfit/providers/notification_provider.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/screens/user/my_applications_reads.dart';
import 'package:ALfit/screens/user/my_applications_screen.dart';
import 'package:ALfit/services/tax_identity_service.dart';
import 'package:ALfit/utils/format_helper.dart';

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
        homeRegion: const UserRegion(province: '서울특별시', city: '강남구'),
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

String _src(String p) => File(p).readAsStringSync();
String _code(String s) => s
    .split('\n')
    .map((l) {
      final i = l.indexOf('//');
      return i >= 0 ? l.substring(0, i) : l;
    })
    .join('\n');
String _body(String code, String start) {
  final i = code.indexOf(start);
  expect(i, greaterThan(-1), reason: start);
  final next = code.indexOf('\n  Future<', i + start.length);
  return code.substring(i, next < 0 ? code.length : next);
}

final DateTime _today = FormatHelper.toKstDate(DateTime.now());

ApplicationModel _pending(String id) => ApplicationModel(
      id: id,
      toId: 'to_$id',
      uid: 'u1',
      businessId: 'biz1',
      businessName: 'QA 사업장',
      toTitle: '공고 $id',
      status: AppStatus.pending,
      selectedWorkType: 'QA 분류',
      startTime: '09:00',
      endTime: '18:00',
      wage: 12000,
      workDate: _today.add(const Duration(days: 10)),
      appliedAt: _today,
    );

class _Calls {
  int paged = 0;
}

MyApplicationsReads _myReads(
  List<List<ApplicationModel>> pages,
  _Calls calls, {
  Future<void> Function(int idx)? onPaged,
}) =>
    MyApplicationsReads(
      myApplicationsPaged: ({required String uid, required int pageSize, String? startAfterDocId}) async {
        calls.paged++;
        final idx = startAfterDocId == null ? 0 : int.parse(startAfterDocId);
        await onPaged?.call(idx);
        final hasMore = idx + 1 < pages.length;
        return {
          'items': idx < pages.length ? pages[idx] : <ApplicationModel>[],
          'lastDocId': hasMore ? '${idx + 1}' : null,
          'hasMore': hasMore,
        };
      },
      toOrFailure: (toId) async => (to: null as TOModel?, failed: false),
      contractsByWorker: (uid) async => const <EmploymentContractModel>[],
      autoExpirePending: (uid) async {},
      monthlyAttendances: ({required String userId, required int year, required int month}) async =>
          const <AttendanceModel>[],
      reviewById: (key) async => null,
      taxStatus: () async => const TaxIdentityStatus.unknown(),
    );

Future<void> _settle(WidgetTester t, [int n = 25]) async {
  for (var i = 0; i < n; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _pumpMy(WidgetTester t, MyApplicationsReads reads,
    {int initialTab = 0, DateTime Function()? clock}) async {
  t.view.physicalSize = const Size(390, 1600);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider<UserProvider>(create: (_) => _P()),
      ChangeNotifierProvider<NotificationProvider>(create: (_) => NotificationProvider()),
    ],
    child: MaterialApp(
      home: MyApplicationsScreen(reads: reads, initialTabIndex: initialTab, clock: clock),
    ),
  ));
  await _settle(t);
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
    await initializeDateFormatting('ko_KR', null);
  });

  group('A 누른 즉시 잠금(P12)', () {
    test('A1 공고 상세 지원 — 세무 조회(첫 await) 전에 _isApplying 을 켜고 finally 에서 끈다', () {
      final c = _code(_src('lib/screens/common/job_posting_screen.dart'));
      final outer = _body(c, 'Future<void> _showConfirmAndApply() async {');
      final lock = outer.indexOf('setState(() => _isApplying = true);');
      expect(lock, greaterThan(-1));
      expect(outer.indexOf('await '), greaterThan(lock));
      expect(outer, contains('if (mounted) setState(() => _isApplying = false);'));
      expect(outer, contains('await _takeTaxStatus()'));
      expect(outer, contains('if (_to!.isFlexType && _slotLoadError) {'),
          reason: '판정 계약 GETSLOTS-05-d — 지원 동작 안의 게이트');
    });

    test('A2 공고 상세 초대 수락 — 세무 조회 전에 잠그고, 미리 읽은 세무 축을 쓴다', () {
      final c = _code(_src('lib/screens/common/job_posting_screen.dart'));
      final outer = _body(c, 'Future<void> _acceptInviteFromDetail() async {');
      final lock = outer.indexOf('setState(() => _isAcceptingInvite = true);');
      expect(lock, greaterThan(-1));
      expect(outer.indexOf('await '), greaterThan(lock));
      expect(outer, contains('await _takeTaxStatus()'));
      expect(outer.contains('TaxIdentityService.loadStatus()'), isFalse);
      expect(outer, contains('meetsApplyPrerequisites('), reason: '판정 계약 34 — 수락 동작 안의 게이트');
    });
  });

  group('B 세무 축 미리 읽기(L44)', () {
    test('B1 지원 시트(AWD) — 열 때 출발 · 누를 때 같은 규칙으로 쓴다', () {
      final c = _code(_src('lib/widgets/dialogs/apply/apply_work_dialog.dart'));
      expect(_body(c, 'Future<void> _initializeData() async {'), contains('_startTaxPrefetch();'));
      expect(_body(c, 'Future<void> _applyForWork('), contains('await _takeTaxStatus()'));
      expect(c, contains('Duration(seconds: 60)'));
      expect(c, contains('if (!status.loadFailed) return status;'));
      expect(c, contains('final read = _reads.taxStatus;'), reason: '읽기 경계로 — 대역이 없으면 미리 읽지 않는다');
      expect(_code(_src('lib/widgets/dialogs/apply/apply_work_reads.dart')),
          contains('taxStatus: TaxIdentityService.loadStatus,'));
    });

    test('B2 내 지원 — 초대가 있으면 목록 직후 출발 · 수락은 미리 읽은 값을 쓴다', () {
      final c = _code(_src('lib/screens/user/my_applications_screen.dart'));
      expect(c, contains('_maybePrefetchTax();'));
      expect(_body(c, 'Future<void> _acceptInviteFlow('), contains('await _takeTaxStatus()'));
    });
  });

  group('C 장기 지원(L45)', () {
    test('C1 업무별 직렬 for-await 0 · 동시 최대 4 · 결과는 고른 순서 · 예외는 결과 모름', () {
      final c = _code(_src('lib/widgets/dialogs/apply/longterm_apply_sheet.dart'));
      expect(c.contains('for (final work in widget.selectedWorks)'), isFalse);
      expect(c, contains('works.length < 4 ? works.length : 4'));
      expect(c, contains('List<ApplyResult?>.filled(works.length, null)'));
      expect(c, contains('for (final result in results.whereType<ApplyResult>())'));
      expect(c, contains("ApplyResult.unknown('지원 결과를 확인하지 못했어요.', code: 'unknown')"));
      expect(c, contains('if (result.isUnknown) anyUnknown = true;'));
    });
  });

  group('D 확정 취소 뒤 재조회(L46)', () {
    test('D1 독립 3개 동시 · 장기 범위 재계산은 지원 상태 갱신 뒤', () {
      final c = _code(_src('lib/widgets/dialogs/apply/apply_work_dialog.dart'));
      final b = _body(c, 'Future<void> _cancelConfirm(');
      final wait = b.indexOf('await Future.wait([');
      final range = b.indexOf('if (_isLongTerm) await _loadConfirmedDatesInRange();');
      expect(wait, greaterThan(-1));
      expect(range, greaterThan(wait));
      expect(b.contains('await _refreshApplicationStatus('), isFalse);
    });
  });

  group('E 내 지원 목록', () {
    testWidgets('E1 처음 연 묶음이 비면 이어 읽고, 두 상한에서 멈추되 "없다"고 하지 않는다', (t) async {
      final calls = _Calls();
      final pages = [for (var i = 0; i < 12; i++) [_pending('p$i')]];
      await _pumpMy(t, _myReads(pages, calls), initialTab: 4); // '초대' 묶음 — 대기 건만 있다
      expect(calls.paged, 7, reason: '첫 + 초기 이어읽기 1 + 자동 5');
      expect(findVisibleText('여기까지 확인했어요 · 더 찾아볼 수 있어요'), findsOneWidget);
      expect(findVisibleText('더 찾아보기'), findsOneWidget);
      await _settle(t, 20);
      expect(calls.paged, 7);
      await t.tap(findVisibleText('더 찾아보기'));
      await _settle(t);
      expect(calls.paged, greaterThan(7), reason: '사용자 다음 묶음은 새 예산');
    });

    testWidgets('E2 시간 상한 — 페이지가 남아도 8초가 지나면 자동으로 잇지 않는다', (t) async {
      final calls = _Calls();
      var now = DateTime(2026, 11, 26, 10);
      final pages = [for (var i = 0; i < 12; i++) [_pending('p$i')]];
      await _pumpMy(
          t,
          _myReads(pages, calls, onPaged: (_) async => now = now.add(const Duration(seconds: 5))),
          initialTab: 4,
          clock: () => now);
      expect(calls.paged, lessThan(7));
      expect(findVisibleText('여기까지 확인했어요 · 더 찾아볼 수 있어요'), findsOneWidget);
    });

    test('E4 SWR 소스 계약 — 받은 목록이 있으면 비우지 않고, 실패는 DU554 그대로', () {
      final c = _code(_src('lib/screens/user/my_applications_screen.dart'));
      final b = _body(c, 'Future<void> _loadApplications({bool refreshTOs = false}) async {');
      final swrAt = b.indexOf('final swr = prev != null;');
      final clearAt = b.indexOf('_applications  = [];');
      expect(swrAt, greaterThan(-1));
      expect(clearAt, greaterThan(swrAt), reason: '목록 비우기는 SWR 아닌 경로에만');
      expect(b, contains('if (refreshTOs) _toCache.clear();'));
      expect(b, contains('_stale      = prev != null;'), reason: '실패 정책(DU554) 그대로');
      expect(c, contains('onRefresh: _refreshByUser,'));
    });

    test('E5 상한에 닿아도 hasMore 를 false 로 바꾸지 않는다', () {
      final c = _code(_src('lib/screens/user/my_applications_screen.dart'));
      final b = _body(c, 'Future<void> _loadMore() async {');
      expect(b.contains('_hasMore = false'), isFalse);
      expect(b, contains('setState(() => _autoLoadStopped = true);'));
      expect(c, contains('Duration(seconds: 8)'));
    });

    test('E6 대기 취소 — 누른 뒤 진행 표시', () {
      final c = _code(_src('lib/screens/user/my_applications_screen.dart'));
      expect(c, contains("Text('취소 중'"));
    });
  });

  group('F 퇴사 요청 다이얼로그', () {
    test('F1 요청·취소 성공 뒤 닫는다', () {
      final c = _code(_src('lib/widgets/dialogs/long_term_work_management_dialog.dart'));
      expect(RegExp(r'widget\.onChanged\(\);\s*Navigator\.pop\(context\);').allMatches(c).length, 2);
    });
  });
}
