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
import 'package:ALfit/providers/notification_provider.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/services/business_posting_readiness.dart';
import 'package:ALfit/screens/business_admin/admin_home_reads.dart';
import 'package:ALfit/screens/business_admin/business_admin_home_screen.dart';

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
}) {
  return AdminHomeReads(
    summary: ({String? selectedBusinessId}) async {
      if (summaryError != null) throw summaryError;
      return summary ?? _summary();
    },
    businessesByIds: (ids) async {
      if (businessesError != null) throw businessesError;
      return businesses ?? [_business(_biz1, '강남 물류센터')];
    },
    staffingReadiness: ({String? selectedBusinessId}) async {
      if (staffingError != null) throw staffingError;
      return staffing ??
          _staffing(days: [
            _staffingDay(date: '2026-09-28', required_: 5, confirmed: 0, shortage: 2),
          ]);
    },
    attendanceByDate: ({required String businessId, required DateTime date}) async =>
        attendance ?? const [],
    confirmedWorkers: ({required DateTime date, required String businessId}) async {
      if (rosterError != null) throw rosterError;
      return confirmed ?? const [];
    },
    workDetailTimes: (_) async => <String, dynamic>{},
    postingReadiness: (bizs) async => _ready(bizs),
    contractTemplates: (_) async => <ContractTemplateModel>[_Template()],
  );
}

Future<void> _pump(
  WidgetTester tester, {
  required AdminHomeReads reads,
  Size size = const Size(390, 1800),
  double textScale = 1.0,
  List<String> bizIds = const [_biz1],
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<UserProvider>(
            create: (_) => _AdminProvider(bizIds: bizIds)),
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
          _staffingDay(date: '2026-09-28', required_: 4, confirmed: 4, shortage: 0),
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
                  date: '2026-09-28', required_: 5, confirmed: 3, shortage: 2),
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
                date: '2026-09-28', required_: 128, confirmed: 96, shortage: 32),
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
              date: '2026-09-28',
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
                    date: '2026-09-28', required_: 12, confirmed: 7, shortage: 5),
              ]),
              summary: _summary(approval: 6, approvalOverdue: 2, unsent: 3)));

      expect(tester.takeException(), isNull, reason: ' dp 에서 예외');
      expect(find.text('12명 중 7명 확정'), findsOneWidget, reason: ' dp');
      expect(find.textContaining('5명 부족'), findsOneWidget, reason: ' dp');
      expect(find.text('6건'), findsWidgets, reason: ' dp');
      expect(find.text('처리할 일'), findsOneWidget, reason: ' dp');
    }
  });
}
