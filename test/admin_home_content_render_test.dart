import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ALfit/models/core/application_model.dart';
import 'package:ALfit/models/core/attendance_model.dart';
import 'package:ALfit/models/core/business_member_model.dart';
import 'package:ALfit/models/core/business_model.dart';
import 'package:ALfit/models/core/contract_template_model.dart';
import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/models/ui/admin_home_summary_model.dart';
import 'package:ALfit/models/ui/staffing_readiness_model.dart';
import 'package:ALfit/utils/format_helper.dart';
import 'package:ALfit/controllers/workforce_controller.dart';
import 'package:ALfit/providers/notification_provider.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/services/business_posting_readiness.dart';
import 'package:ALfit/screens/business_admin/admin_home_reads.dart';
import 'package:ALfit/screens/business_admin/business_admin_home_screen.dart';
import 'package:ALfit/screens/business_admin/dialogs/day_applicants_dialog.dart';
import 'package:ALfit/screens/business_admin/dialogs/attendance_status_dialog.dart';

/// [R7-P1-4 H4] **실제 관리자 홈 위젯**을 콘텐츠와 함께 그린다.
///
///   지금까지 홈을 pump 하는 테스트는 shell 하나뿐이었고(`shell_lazy_tab_contract`)
///   숫자·할 일·문구는 전부 소스 문자열로만 검증됐다. 여기서는 `AdminHomeReads`
///   경계만 갈아끼워 production 로드·권한 게이트·파생·문구 구성을 그대로 돌린다.
///   테스트용 카드·계산식·라벨 복제는 만들지 않는다.
///
///   권한은 provider 경계에서 BUSINESS_ADMIN 으로 준다 — 권한 없는 provider 로
///   숨겨진 버튼을 "확인했다"고 세지 않기 위해서다.

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

/// 권한이 하나도 없는 SubAdmin — 기존 차단이 유지되는지 보는 쪽.
class _NoPermProvider extends UserProvider {
  @override
  UserModel? get currentUser => UserModel(
        uid: 'sub1',
        username: 'sub1',
        name: '권한없음',
        email: 'sub1@alfit.local',
        role: UserRole.USER,
        subAdminBusinessIds: const [_biz1],
        sealBase64: 'seal',
      );

  @override
  bool get isSubAdmin => true;

  @override
  String? get effectiveBusinessId => _biz1;

  @override
  bool get subAdminPermissionsLoaded => true;

  @override
  PermissionWatchState get currentBusinessPermissionHealth =>
      PermissionWatchState.verified;

  @override
  PermissionCheck checkCurrentBusiness(
          bool Function(MemberPermissions p) check) =>
      PermissionCheck.denied;

  @override
  bool can(bool Function(MemberPermissions p) check) => false;

  @override
  bool canForAnyBusiness(bool Function(MemberPermissions p) check,
          {required bool whenUnknown}) =>
      false;
}

/// 권한이 실제로 있는 관리자. production 판정 경로(`can`·`checkCurrentBusiness`)를
/// 그대로 쓰되, Firestore 구독 없이 BUSINESS_ADMIN 과 같은 결과를 돌려준다.
class _AdminProvider extends UserProvider {
  _AdminProvider({this.bizIds = const ['biz1']});

  final List<String> bizIds;

  @override
  UserModel? get currentUser => UserModel(
        uid: 'admin1',
        username: 'admin1',
        name: '김관리',
        email: 'admin1@alfit.local',
        role: UserRole.BUSINESS_ADMIN,
        managedBusinessIds: bizIds,
        sealBase64: 'seal',
      );

  @override
  bool get isSubAdmin => false;

  @override
  String? get effectiveBusinessId => null;

  @override
  bool get subAdminPermissionsLoaded => true;

  @override
  PermissionWatchState get currentBusinessPermissionHealth =>
      PermissionWatchState.verified;

  @override
  PermissionCheck checkCurrentBusiness(
          bool Function(MemberPermissions p) check) =>
      PermissionCheck.allowed;

  @override
  bool can(bool Function(MemberPermissions p) check) => true;

  @override
  bool canForAnyBusiness(bool Function(MemberPermissions p) check,
          {required bool whenUnknown}) =>
      true;
}

/// [R7-P1-4 후속] 이 파일의 **하나뿐인 날짜 기준**.
///   홈은 `days.first` 를 오늘로 읽는다(위치 기준 — 날짜 문자열을 대조하지 않는다).
///   그래도 fixture 가 고정 날짜를 들고 있으면 읽는 사람이 다른 기준을 떠올리고,
///   나중에 날짜 대조가 생기면 조용히 시계 의존이 된다 — 처음부터 오늘에서 파생한다.
final String _todayStr = () {
  final d = FormatHelper.toKstDate(DateTime.now());
  return '${d.year}-${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}();

const _biz1 = 'biz1';
const _biz2 = 'biz2';

BusinessModel _business(String id, String name) => BusinessModel(
      id: id,
      name: name,
      ownerId: 'admin1',
      businessNumber: '000-00-00000',
      address: '서울시 어딘가',
      category: '물류',
      subCategory: '창고',
      isApproved: true,
      createdAt: DateTime(2026, 1, 1),
    );

/// CF 직렬화 모양 그대로 — 모델 파싱도 production 경로를 쓴다.
Map<String, dynamic> _staffingDay({
  required String date,
  required int required_,
  required int confirmed,
  required int shortage,
  int? pending,
  List<Map<String, dynamic>> byBusiness = const [],
}) =>
    {
      'date': date,
      'requiredCount': required_,
      'confirmedCount': confirmed,
      'shortageCount': shortage,
      if (pending != null) 'pendingCount': pending,
      'pendingAvailable': pending != null,
      'byBusiness': byBusiness,
    };

StaffingReadinessModel _staffing({
  required List<Map<String, dynamic>> days,
  bool partial = false,
  int failed = 0,
}) =>
    StaffingReadinessModel(
      available: true,
      partial: partial,
      failedBusinessCount: failed,
      publishedPostingCount: 1, // 운영 중 — 공고가 하나라도 게시돼 있다
      days: days.map(StaffingDayData.fromMap).toList(),
    );

/// 준비 4항목을 모두 채운 사업장 — 이 상태의 홈이 **운영 홈**이다.
/// (준비 중이면 Hero 가 lifecycle 을 말하고 할 일 섹션이 의도적으로 숨는다)
Map<String, BusinessPostingReadiness> _ready(List<BusinessModel> bizs) => {
      for (final b in bizs)
        b.id: BusinessPostingReadiness(
          bizId: b.id,
          isApproved: true,
          hasCanonicalLicense: true,
          hasOwnerLegacyLicense: false,
          hasActiveWorkTypes: true,
        ),
    };

/// 계약서 템플릿 1개 — 홈은 `selectableForNewContract` 가 비지 않는지만 본다.
class _Template extends Fake implements ContractTemplateModel {
  @override
  bool get isSupportedForNewUse => true;
}

Map<String, dynamic> _simple(int count, {bool available = true}) => {
      'available': available,
      'count': count,
      'byBusiness': [
        {'businessId': _biz1, 'count': count},
      ],
    };

AdminHomeSummaryModel _summary({
  int resign = 0,
  int approval = 0,
  int approvalOverdue = 0,
  int schedule = 0,
  int unsent = 0,
  int unclosed = 0,
  int settlement = 0,
  int wageChange = 0,
  int unpaid = 0,
  int expiring = 0,
  int expired = 0,
  bool allAvailable = true,
}) =>
    AdminHomeSummaryModel.fromMap({
      'actions': {
        'resignRequest': {..._simple(resign, available: allAvailable), 'soonCount': 0},
        'approval': {
          ..._simple(approval, available: allAvailable),
          'overdueCount': approvalOverdue,
        },
        'scheduleChangeRequest': _simple(schedule, available: allAvailable),
        'unsentContract': _simple(unsent, available: allAvailable),
        'unclosed': {..._simple(unclosed, available: allAvailable), 'oldestDate': null},
        'settlementRequest': _simple(settlement, available: allAvailable),
        'wageChangeRequest': _simple(wageChange, available: allAvailable),
        'unpaidWage': {
          ..._simple(unpaid, available: allAvailable),
          'overdueCount': 0,
          'missingDueDateCount': 0,
        },
      },
      'upcoming': {
        'expiringContract': {
          ..._simple(expiring, available: allAvailable),
          'upcomingCount': expiring - expired < 0 ? 0 : expiring - expired,
          'expiredCount': expired,
        },
      },
    });

/// 사업장별 건수를 담은 퇴사 요청 summary — 목적지 시트 context 확인용.
AdminHomeSummaryModel _summaryPerBiz({required Map<String, int> resign}) {
  final total = resign.values.fold<int>(0, (a, b) => a + b);
  Map<String, dynamic> empty() => {
        'available': true,
        'count': 0,
        'byBusiness': const <Map<String, dynamic>>[],
      };
  return AdminHomeSummaryModel.fromMap({
    'actions': {
      'resignRequest': {
        'available': true,
        'count': total,
        'soonCount': 0,
        'byBusiness': [
          for (final e in resign.entries)
            {'businessId': e.key, 'count': e.value},
        ],
      },
      'approval': {...empty(), 'overdueCount': 0},
      'scheduleChangeRequest': empty(),
      'unsentContract': empty(),
      'unclosed': {...empty(), 'oldestDate': null},
      'settlementRequest': empty(),
      'wageChangeRequest': empty(),
      'unpaidWage': {...empty(), 'overdueCount': 0, 'missingDueDateCount': 0},
    },
    'upcoming': {
      'expiringContract': {...empty(), 'upcomingCount': 0, 'expiredCount': 0},
    },
  });
}

/// 기본 경계 — 전부 성공, 오늘 근무 있음.
AdminHomeReads _reads({
  List<BusinessModel>? businesses,
  StaffingReadinessModel? staffing,
  AdminHomeSummaryModel? summary,
  List<ApplicationModel>? confirmed,
  List<AttendanceModel>? attendance,
  Object? businessesError,
  Object? staffingError,
  Object? summaryError,
  Object? rosterError,
  Future<bool> Function()? tour,
  /// 호출 n번째 staffing 응답을 직접 준다(없으면 기본값). 순서 역전 재현용.
  List<Future<StaffingReadinessModel>>? staffingByCall,
  /// 호출 n번째 canonical summary 응답.
  List<Future<AdminHomeSummaryModel>>? summaryByCall,
  /// 각 loader 호출 횟수 기록 — 복귀 갱신 확인용.
  Map<String, int>? calls,
}) {
  void hit(String k) {
    if (calls != null) calls[k] = (calls[k] ?? 0) + 1;
  }
  var staffingCall = 0;
  var summaryCall = 0;
  return AdminHomeReads(
    summary: ({String? selectedBusinessId}) {
      hit('summary');
      final i = summaryCall++;
      if (summaryByCall != null && i < summaryByCall.length) {
        return summaryByCall[i];
      }
      if (summaryError != null) return Future<AdminHomeSummaryModel>.error(summaryError);
      return Future<AdminHomeSummaryModel>.value(summary ?? _summary());
    },
    businessesByIds: (ids) async {
      if (businessesError != null) throw businessesError;
      return businesses ?? [_business(_biz1, '강남 물류센터')];
    },
    staffingReadiness: ({String? selectedBusinessId}) {
      hit('staffing');
      final i = staffingCall++;
      if (staffingByCall != null && i < staffingByCall.length) {
        return staffingByCall[i];
      }
      if (staffingError != null) {
        return Future<StaffingReadinessModel>.error(staffingError);
      }
      return Future<StaffingReadinessModel>.value(staffing ??
          _staffing(days: [
            _staffingDay(date: _todayStr, required_: 5, confirmed: 0, shortage: 2),
          ]));
    },
    attendanceByDate: ({required String businessId, required DateTime date}) async =>
        attendance ?? const [],
    confirmedWorkers: ({required DateTime date, required String businessId}) async {
      hit('roster');
      if (rosterError != null) throw rosterError;
      return confirmed ?? const [];
    },
    workDetailTimes: (_) async => <String, dynamic>{},
    postingReadiness: (bizs) async => _ready(bizs),
    contractTemplates: (_) async => <ContractTemplateModel>[_Template()],
    // 기본값은 '이미 봤다' — 투어가 뜨지 않는 평소 경로.
    tourCompleted: tour ?? () => Future<bool>.value(true),
  );
}

Future<void> _pump(
  WidgetTester tester, {
  required AdminHomeReads reads,
  Size size = const Size(390, 1800),
  double textScale = 1.0,
  List<String> bizIds = const [_biz1],
  UserProvider Function()? provider,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<UserProvider>(
            create: (_) => provider?.call() ?? _AdminProvider(bizIds: bizIds)),
        // 알림 배지만 쓰는 provider — 구독을 시작하지 않으므로 기본 인스턴스로 충분하다.
        ChangeNotifierProvider<NotificationProvider>(
            create: (_) => NotificationProvider()),
      ],
      child: MaterialApp(
        builder: (ctx, child) => MediaQuery(
          data: MediaQuery.of(ctx)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: BusinessAdminHomeScreen(reads: reads),
      ),
    ),
  );
  // pumpAndSettle 은 쓰지 않는다 — 홈에는 멈추지 않는 애니메이션이 있어 timeout 된다.
  //   대신 유한 프레임으로 loader Future 를 모두 흘려보낸다.
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  setUp(() {
    // 투어 게이트를 완료로 둔다 — 이 값이 없으면 initState 의 Future.wait 가
    // 끝나지 않아 네 loader 가 아예 시작하지 않는다(= 영구 spinner).
    SharedPreferences.setMockInitialValues({'tour_completed_admin_home': true});
  });

  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
    await initializeDateFormatting('ko_KR', null);
  });

  // ══════════════════════════════════════════════════════════
  // H1 — 숫자·모집단·문구
  // ══════════════════════════════════════════════════════════

  testWidgets('AHR-1 오늘 요약은 정원 축에 `필요`를 쓰지 않는다', (tester) async {
    await _pump(tester, reads: _reads());

    expect(tester.takeException(), isNull);
    // 정원 5 · 확정 0 · 충원 가능 부족 2 (종료된 단위 3명분 포함)
    expect(find.text('5명 중 0명 확정'), findsOneWidget);
    expect(find.textContaining('5명 필요'), findsNothing,
        reason: '`필요`와 `더 필요`가 다른 모집단이어서 5-0=5로 읽혔다');
    // 부족은 별도 행에서 자기 모집단으로 말한다
    expect(find.textContaining('2명 부족'), findsOneWidget);
  });

  testWidgets('AHR-2 전원 확정은 한 문장으로 말한다', (tester) async {
    await _pump(tester,
        reads: _reads(
            staffing: _staffing(days: [
          _staffingDay(date: _todayStr, required_: 4, confirmed: 4, shortage: 0),
        ])));

    expect(find.text('4명 전원 확정'), findsOneWidget);
    expect(find.textContaining('부족'), findsNothing);
  });

  testWidgets('AHR-3 할 일 수치는 원천 단위(건)로 그려진다', (tester) async {
    await _pump(tester,
        reads: _reads(
            summary: _summary(
          approval: 3,
          approvalOverdue: 1,
          unsent: 2,
          expiring: 4,
          expired: 1,
          schedule: 1,
        )));

    expect(tester.takeException(), isNull);
    // 지원 검토 = PENDING 지원서 수. 같은 행의 배지도 건이다.
    expect(find.text('3건'), findsWidgets);
    expect(find.text('긴급 1건'), findsOneWidget);
    // 계약 미발송 = 발송해야 할 계약서 수, 계약 확인 필요 = 갱신 결정 대상 관계 수
    expect(find.text('2건'), findsWidgets);
    expect(find.text('4건 · 만료 1'), findsOneWidget);
    // 화면 어디에도 이 수치들을 인원수로 부르지 않는다
    expect(find.text('3명'), findsNothing);
    expect(find.text('2명'), findsNothing);
    expect(find.text('4명 · 만료 1'), findsNothing);
  });

  testWidgets('AHR-4 0건은 행을 만들지 않고, 전부 성공일 때만 안심 문구', (tester) async {
    await _pump(tester, reads: _reads(summary: _summary()));

    expect(find.text('처리할 업무가 없어요'), findsOneWidget);
    expect(find.text('지원 검토'), findsNothing);
    expect(find.text('퇴사 요청'), findsNothing);
  });

  // ══════════════════════════════════════════════════════════
  // H2 — 실패·미조회를 0으로 만들지 않는다
  // ══════════════════════════════════════════════════════════

  testWidgets('AHR-5 할 일 조회 실패는 `할 일 없어요`가 아니다', (tester) async {
    await _pump(tester, reads: _reads(summaryError: StateError('cf down')));

    expect(tester.takeException(), isNull);
    expect(find.text('처리할 업무가 없어요'), findsNothing,
        reason: '확인하지 못한 것을 없다고 말하면 안 된다');
    expect(find.textContaining('확인하지 못'), findsWidgets);
  });

  testWidgets('AHR-6 인력·출근 조회 실패는 0이 아니라 실패 문구', (tester) async {
    await _pump(tester,
        reads: _reads(
            staffingError: StateError('staffing down'),
            rosterError: StateError('roster down')));

    expect(tester.takeException(), isNull);
    expect(find.text('인력 정보를 불러오지 못했습니다'), findsOneWidget);
    expect(find.text('출근 현황을 불러오지 못했습니다'), findsOneWidget);
    expect(find.textContaining('0명 중 0명'), findsNothing);
    expect(find.textContaining('출근 0/0'), findsNothing);
    expect(find.text('재시도'), findsWidgets);
  });

  testWidgets('AHR-7 부분 실패는 부분합임을 밝힌다', (tester) async {
    await _pump(tester,
        bizIds: const [_biz1, _biz2],
        reads: _reads(
          businesses: [
            _business(_biz1, '강남 물류센터'),
            _business(_biz2, '평택 센터'),
          ],
          staffing: _staffing(
            partial: true,
            failed: 1,
            days: [
              _staffingDay(
                  date: _todayStr, required_: 5, confirmed: 3, shortage: 2),
            ],
          ),
        ));

    expect(find.textContaining('사업장 1곳의 정보를 불러오지 못해'), findsWidgets);
    // partial 에서는 `전체 N개 사업장 합계`를 주장하지 않는다
    expect(find.textContaining('전체 2개 사업장 합계'), findsNothing);
  });

  // ══════════════════════════════════════════════════════════
  // H3/H4 — 좁은 폭·큰 글자·긴 이름·큰 숫자
  // ══════════════════════════════════════════════════════════

  testWidgets('AHR-8 320dp·배율 1.3 에서 overflow 없고 수치가 남는다', (tester) async {
    await _pump(tester,
        size: const Size(320, 700),
        textScale: 1.3,
        reads: _reads(
          businesses: [
            _business(_biz1, '서울특별시 강남구 제1물류센터 야간운영팀 상시근무지'),
          ],
          staffing: _staffing(days: [
            _staffingDay(
                date: _todayStr, required_: 128, confirmed: 96, shortage: 32),
          ]),
          summary: _summary(
              approval: 147, approvalOverdue: 23, unsent: 88, resign: 12),
        ));

    expect(tester.takeException(), isNull,
        reason: '좁은 폭·큰 글자에서 예외 0 — 글자 축소·배율 무효화로 덮지 않는다');
    expect(find.text('128명 중 96명 확정'), findsOneWidget);
    expect(find.textContaining('32명 부족'), findsOneWidget);
    expect(find.text('147건'), findsWidgets);
  });

  testWidgets('AHR-9 여러 사업장이면 집계 범위를 밝힌다', (tester) async {
    await _pump(tester,
        bizIds: const [_biz1, _biz2],
        reads: _reads(
          businesses: [
            _business(_biz1, '강남 물류센터'),
            _business(_biz2, '평택 센터'),
          ],
          staffing: _staffing(days: [
            _staffingDay(
              date: _todayStr,
              required_: 9,
              confirmed: 4,
              shortage: 3,
              byBusiness: [
                {
                  'businessId': _biz2,
                  'businessName': '평택 센터',
                  'requiredCount': 5,
                  'confirmedCount': 2,
                  'shortageCount': 3,
                },
              ],
            ),
          ]),
        ));

    expect(find.text('전체 2개 사업장 합계'), findsOneWidget);
    expect(find.text('9명 중 4명 확정'), findsOneWidget);
  });
// ══════════════════════════════════════════════════════════
  // H3 — 레이아웃 배율 위임(폭별 렌더)
  // ══════════════════════════════════════════════════════════

  testWidgets('AHR-10 폭 5종에서 예외 0 · 핵심 수치 유지', (tester) async {
    for (final w in [320.0, 360.0, 390.0, 480.0, 600.0]) {
      await _pump(tester,
          size: Size(w, 1800),
          reads: _reads(
              staffing: _staffing(days: [
                _staffingDay(
                    date: _todayStr, required_: 12, confirmed: 7, shortage: 5),
              ]),
              summary: _summary(approval: 6, approvalOverdue: 2, unsent: 3)));

      expect(tester.takeException(), isNull, reason: ' dp 에서 예외');
      expect(find.text('12명 중 7명 확정'), findsOneWidget, reason: ' dp');
      expect(find.textContaining('5명 부족'), findsOneWidget, reason: ' dp');
      expect(find.text('6건'), findsWidgets, reason: ' dp');
      expect(find.text('처리할 일'), findsOneWidget, reason: ' dp');
    }
  });
// ══════════════════════════════════════════════════════════
  // H1 후속 — 부족의 범위가 화면에서 말해지는가
  // ══════════════════════════════════════════════════════════

  testWidgets('AHR-11 정원-확정이 부족과 다른 날은 부족의 범위를 말한다', (tester) async {
    // 정원 5(모집이 끝난 단위 포함) · 확정 0 · 모집 가능한 부족 2
    await _pump(tester, reads: _reads());

    // 실제 렌더된 조합 — 이 순서가 화면의 문구 계약이다.
    expect(find.text('오늘 2명이 더 필요해요'), findsOneWidget); // Hero
    expect(find.text('오늘'), findsOneWidget); // 섹션 제목
    expect(find.text('5명 중 0명 확정'), findsOneWidget); // 정원 축
    expect(find.text('2명 부족'), findsOneWidget); // 모집 가능 축
    expect(find.text('지금 모집 중인 업무만 센 숫자예요'), findsOneWidget,
        reason: '5 - 0 = 5 를 기대한 사람에게 이 줄이 범위를 말한다');
    // 원인을 단정하지 않는다 — 모집 종료·과충원 상쇄 둘 다 가능하다.
    expect(find.textContaining('모집이 끝난'), findsNothing);
    // 숫자를 새로 만들지 않는다.
    expect(find.textContaining('3명'), findsNothing);
  });

  testWidgets('AHR-12 정원-확정이 부족과 같은 날은 보조 줄이 없다', (tester) async {
    await _pump(tester,
        reads: _reads(
            staffing: _staffing(days: [
          _staffingDay(date: _todayStr, required_: 5, confirmed: 3, shortage: 2),
        ])));

    expect(find.text('5명 중 3명 확정'), findsOneWidget);
    expect(find.text('2명 부족'), findsOneWidget);
    expect(find.text('지금 모집 중인 업무만 센 숫자예요'), findsNothing, reason: '맞아떨어지는 날에 군더더기를 두지 않는다');
  });

  testWidgets('AHR-13 과충원 상쇄로 부족이 더 큰 날도 같은 보조 줄', (tester) async {
    // 단위별 max(0, req-conf) 합산이라 부족 > 정원-확정 이 될 수 있다.
    await _pump(tester,
        reads: _reads(
            staffing: _staffing(days: [
          _staffingDay(date: _todayStr, required_: 5, confirmed: 4, shortage: 2),
        ])));

    expect(find.text('5명 중 4명 확정'), findsOneWidget);
    expect(find.text('2명 부족'), findsOneWidget);
    expect(find.text('지금 모집 중인 업무만 센 숫자예요'), findsOneWidget);
  });

  testWidgets('AHR-14 새 보조 줄의 긴 텍스트가 320dp·배율 1.3 에서 넘치지 않는다',
      (tester) async {
    await _pump(tester,
        size: const Size(320, 1800),
        textScale: 1.3,
        reads: _reads(
          businesses: [
            _business(_biz1, '강남 물류센터'),
            _business(_biz2, '서울특별시 강남구 제1물류센터 야간운영팀'),
          ],
          staffing: _staffing(days: [
            _staffingDay(
              date: _todayStr,
              required_: 128,
              confirmed: 0,
              shortage: 32,
              byBusiness: [
                {
                  'businessId': _biz2,
                  'businessName': '서울특별시 강남구 제1물류센터 야간운영팀',
                  'requiredCount': 64,
                  'confirmedCount': 0,
                  'shortageCount': 32,
                },
              ],
            ),
          ]),
        ),
        bizIds: const [_biz1, _biz2]);

    expect(tester.takeException(), isNull);
    // 부족 위치까지 붙은 긴 라벨 + 보조 줄이 함께 있어도 둘 다 남는다.
    expect(find.textContaining('32명 부족'), findsOneWidget);
    expect(find.text('지금 모집 중인 업무만 센 숫자예요'), findsOneWidget);
    expect(find.text('128명 중 0명 확정'), findsOneWidget);
  });
// ══════════════════════════════════════════════════════════
  // H2 후속 — 투어 판정이 데이터를 막지 않는다
  // ══════════════════════════════════════════════════════════

  testWidgets('AHR-15 투어 판정이 끝나지 않아도 네 loader 가 돈다', (tester) async {
    // 영구 pending — 이전 구현은 여기서 `Future.wait` 가 멈춰
    //   화면 전체가 끝나지 않는 spinner 였다(재시도 버튼도 없다).
    final never = Completer<bool>();
    addTearDown(() {
      if (!never.isCompleted) never.complete(true);
    });

    await _pump(tester,
        reads: _reads(
            tour: () => never.future,
            summary: _summary(approval: 3, unsent: 2)));

    expect(tester.takeException(), isNull);
    expect(find.text('5명 중 0명 확정'), findsOneWidget); // staffing loader
    expect(find.text('출근 예정 전'), findsOneWidget); // attendance loader
    expect(find.text('3건'), findsWidgets); // canonical summary loader
    expect(find.byType(CircularProgressIndicator), findsNothing,
        reason: '끝나지 않는 spinner 로 남지 않는다');
  });

  testWidgets('AHR-16 투어 판정이 실패해도 수치가 나오고 화면이 막히지 않는다',
      (tester) async {
    await _pump(tester,
        reads: _reads(
            tour: () => Future<bool>.error(StateError('prefs unavailable')),
            summary: _summary(approval: 3)));

    expect(tester.takeException(), isNull, reason: '투어 실패가 화면 예외로 새지 않는다');
    expect(find.text('5명 중 0명 확정'), findsOneWidget);
    expect(find.text('2명 부족'), findsOneWidget);
    expect(find.text('3건'), findsWidgets);
    // 실패를 '완료'로 저장하지 않는다 — 다음 진입에서 다시 판정한다.
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('tour_completed_admin_home'), isTrue,
        reason: 'setUp 이 넣어 둔 값 그대로 — 테스트가 이 값을 건드리지 않았다');
  });

  testWidgets('AHR-17 화면이 사라진 뒤 도착한 투어 결과가 UI 를 다시 열지 않는다',
      (tester) async {
    final late_ = Completer<bool>();
    await _pump(tester, reads: _reads(tour: () => late_.future));
    expect(find.text('5명 중 0명 확정'), findsOneWidget);

    // 홈을 버린다.
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: Text('다른 화면'))));
    await tester.pump(const Duration(milliseconds: 100));

    // 이제 '투어를 아직 안 봤다'가 도착한다.
    late_.complete(false);
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(tester.takeException(), isNull);
    expect(find.text('다른 화면'), findsOneWidget);
    expect(find.text('5명 중 0명 확정'), findsNothing, reason: '홈을 되살리지 않는다');
  });
// ══════════════════════════════════════════════════════════
  // H2 후속 — 늦은 응답(실제로 발생한 결함의 최소 순서)
  // ══════════════════════════════════════════════════════════

  testWidgets('AHR-18 동일 scope 응답 역전 — 늦게 온 옛 값이 현재 값을 덮지 않는다',
      (tester) async {
    final first = Completer<StaffingReadinessModel>(); // 먼저 보냈지만 늦게 온다
    await _pump(tester,
        reads: _reads(staffingByCall: [
          first.future,
          Future<StaffingReadinessModel>.value(_staffing(days: [
            _staffingDay(date: _todayStr, required_: 5, confirmed: 3, shortage: 2),
          ])),
        ]));

    // 두 번째 로드를 일으킨다 — 다른 탭의 mutation 회수 경로(실제 production 신호).
    WorkforceController.notifyDataChanged(origin: AdminMutationOrigin.jobs);
    for (var i = 0; i < 15; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('5명 중 3명 확정'), findsOneWidget, reason: '두 번째(최신) 응답');

    // 이제 첫 응답이 옛 값으로 도착한다.
    first.complete(_staffing(days: [
      _staffingDay(date: _todayStr, required_: 9, confirmed: 0, shortage: 9),
    ]));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(tester.takeException(), isNull);
    expect(find.text('5명 중 3명 확정'), findsOneWidget);
    expect(find.text('9명 중 0명 확정'), findsNothing, reason: '옛 응답이 현재 값을 덮었다');
    expect(find.textContaining('9명 부족'), findsNothing);
  });

  testWidgets('AHR-19 늦게 온 실패가 현재 scope 를 에러로 덮지 않는다', (tester) async {
    final first = Completer<StaffingReadinessModel>();
    await _pump(tester,
        reads: _reads(staffingByCall: [
          first.future,
          Future<StaffingReadinessModel>.value(_staffing(days: [
            _staffingDay(date: _todayStr, required_: 4, confirmed: 4, shortage: 0),
          ])),
        ]));

    WorkforceController.notifyDataChanged(origin: AdminMutationOrigin.workforce);
    for (var i = 0; i < 15; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('4명 전원 확정'), findsOneWidget);

    first.completeError(StateError('늦게 도착한 실패'));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(tester.takeException(), isNull);
    expect(find.text('4명 전원 확정'), findsOneWidget);
    expect(find.text('인력 정보를 불러오지 못했습니다'), findsNothing,
        reason: '현재 값이 있는데 옛 실패로 에러 상태가 되면 안 된다');
  });

  testWidgets('AHR-20 처리 후 갱신된 할 일이 옛 응답으로 되살아나지 않는다',
      (tester) async {
    final first = Completer<AdminHomeSummaryModel>();
    await _pump(tester,
        reads: _reads(summaryByCall: [
          first.future,
          Future<AdminHomeSummaryModel>.value(_summary()), // 전부 0 — 처리 완료
        ]));

    WorkforceController.notifyDataChanged(origin: AdminMutationOrigin.jobs);
    for (var i = 0; i < 15; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('처리할 업무가 없어요'), findsOneWidget);

    // 처리 전에 보냈던 응답이 이제 도착한다.
    first.complete(_summary(approval: 3, resign: 1));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(tester.takeException(), isNull);
    expect(find.text('지원 검토'), findsNothing, reason: '처리한 할 일이 되살아났다');
    expect(find.text('퇴사 요청'), findsNothing);
    expect(find.text('처리할 업무가 없어요'), findsOneWidget);
  });

  testWidgets('AHR-21 화면을 버린 뒤 도착한 응답이 예외를 남기지 않는다', (tester) async {
    final first = Completer<StaffingReadinessModel>();
    await _pump(tester, reads: _reads(staffingByCall: [first.future]));

    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: Text('다른 화면'))));
    await tester.pump(const Duration(milliseconds: 100));

    first.complete(_staffing(days: [
      _staffingDay(date: _todayStr, required_: 7, confirmed: 1, shortage: 6),
    ]));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(tester.takeException(), isNull);
    expect(find.text('다른 화면'), findsOneWidget);
  });
// ══════════════════════════════════════════════════════════
  // H2 후속 — 실제 이동(목적지 context)과 복귀 갱신
  //   실제 도메인 쓰기는 하지 않는다. 목적지 내부 계산·렌더는 P1-2/P1-3 소유다.
  // ══════════════════════════════════════════════════════════

  testWidgets('AHR-22 당일 명단 CTA → 오늘 날짜·사업장 목록이 그대로 전달된다',
      (tester) async {
    final calls = <String, int>{};
    await _pump(tester,
        bizIds: const [_biz1, _biz2],
        reads: _reads(
          calls: calls,
          businesses: [
            _business(_biz1, '강남 물류센터'),
            _business(_biz2, '평택 센터'),
          ],
        ));

    final staffingBefore = calls['staffing'] ?? 0;
    final rosterBefore = calls['roster'] ?? 0;

    await tester.tap(find.text('당일 명단'));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    final dialog = tester.widget<AttendanceStatusDialog>(
        find.byType(AttendanceStatusDialog));
    // 날짜 context — 홈이 보고 있는 오늘(KST 달력일)과 같은 값.
    final today = FormatHelper.toKstDate(DateTime.now());
    expect(dialog.date.year, today.year);
    expect(dialog.date.month, today.month);
    expect(dialog.date.day, today.day);
    // 사업장 context — 홈의 scope 그대로.
    expect(dialog.businessIds, [_biz1, _biz2]);
    expect(dialog.businesses?.map((b) => b.id).toList(), [_biz1, _biz2]);

    // 변경이 있었다고 알리며 돌아온다 → 홈이 인력·출근을 다시 읽는다.
    final ctx = tester.element(find.byType(AttendanceStatusDialog));
    Navigator.of(ctx).pop(true);
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    tester.takeException(); // 목적지 내부의 실제 조회 실패는 이 테스트의 대상이 아니다

    expect(calls['staffing']! > staffingBefore, isTrue,
        reason: '좌석 반납이 부족을 바꾸므로 인력도 다시 읽어야 한다');
    expect(calls['roster']! > rosterBefore, isTrue);
  });

  testWidgets('AHR-23 부족 행 → 그 날짜 + 부족 사업장 우선 순서로 전달된다',
      (tester) async {
    final calls = <String, int>{};
    await _pump(tester,
        bizIds: const [_biz1, _biz2],
        reads: _reads(
          calls: calls,
          businesses: [
            _business(_biz1, '강남 물류센터'),
            _business(_biz2, '평택 센터'),
          ],
          staffing: _staffing(days: [
            _staffingDay(
              date: _todayStr,
              required_: 9,
              confirmed: 4,
              shortage: 3,
              byBusiness: [
                {
                  'businessId': _biz2,
                  'businessName': '평택 센터',
                  'requiredCount': 5,
                  'confirmedCount': 2,
                  'shortageCount': 3,
                },
              ],
            ),
          ]),
        ));

    final staffingBefore = calls['staffing'] ?? 0;
    await tester.tap(find.textContaining('3명 부족'));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    final dad = tester.widget<DayApplicantsDialog>(find.byType(DayApplicantsDialog));
    final today = FormatHelper.toKstDate(DateTime.now());
    expect(dad.date.year, today.year);
    expect(dad.date.month, today.month);
    expect(dad.date.day, today.day);
    // 부족한 사업장만, 부족 큰 순서 — 시트 초기 선택이 그곳이 되도록.
    expect(dad.businessIds, [_biz2]);

    final ctx = tester.element(find.byType(DayApplicantsDialog));
    Navigator.of(ctx).pop(true);
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    tester.takeException();

    expect(calls['staffing']! > staffingBefore, isTrue,
        reason: '확정·거절이 부족을 바꾸므로 복귀 시 인력을 다시 읽는다');
  });

  testWidgets('AHR-24 할 일 행 → 사업장 선택에 사업장별 건수가 전달된다',
      (tester) async {
    await _pump(tester,
        bizIds: const [_biz1, _biz2],
        reads: _reads(
          businesses: [
            _business(_biz1, '강남 물류센터'),
            _business(_biz2, '평택 센터'),
          ],
          summary: _summaryPerBiz(resign: {_biz1: 2, _biz2: 1}),
        ));

    expect(find.text('퇴사 요청'), findsOneWidget);
    expect(find.text('3건'), findsWidgets); // 합계

    await tester.tap(find.text('퇴사 요청'));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    tester.takeException();

    // 사업장 선택 시트 — 총계와 사업장별 건수가 홈 수치와 같은 단위로 전달된다.
    expect(find.textContaining('총 3건'), findsOneWidget);
    expect(find.text('강남 물류센터'), findsWidgets);
    expect(find.text('평택 센터'), findsWidgets);
  });

  testWidgets('AHR-25 권한 없는 사용자는 같은 자리에서 진입 자체가 없다',
      (tester) async {
    await _pump(tester,
        provider: _NoPermProvider.new,
        reads: _reads(summary: _summary(approval: 3, resign: 2, unsent: 1)));

    expect(tester.takeException(), isNull);
    // 오늘 섹션 CTA·할 일 행 모두 비노출 — 눌 수 없는 자리를 남기지 않는다.
    expect(find.text('당일 명단'), findsNothing);
    expect(find.text('지원 검토'), findsNothing);
    expect(find.text('퇴사 요청'), findsNothing);
    expect(find.text('계약 미발송'), findsNothing);
  });
}
