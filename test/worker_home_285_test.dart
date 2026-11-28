// [판정285 · 대표 지시 2026-11-26] 근로자 홈 구조·통합 날짜·선택일 행동 — §7 최소 검증.
//
//   WH-1  새 회원 정상0(지역·일정·공고 0) 360/1.0 — 순서 · 이번 주 일정 0 · 오늘 정상0 짧은 안내 · 추천 빈 안내(C285-02) ·
//         모든 날짜 선택 가능(C285-01) · 빈 날 선택 → 선택일 요약·공고0 안내·버튼 유지 · 재탭 유지 · 명시 해제 ·
//         버튼 → 일자리 탭 날짜(선택 KST 하루) · 다른 달(12월) 의미 tap action · Navigator push 0
//   WH-2  확정·계약 진행 중·지원 중 혼합(같은 날 3건) — 두 점 · 범례 · 확정 먼저·시각순 최대 2 · `외 1건` ·
//         「내 일정에서 보기」(pointer + 의미 tap) → 일정 날짜 · 지원 중만 있는 날
//   WH-3  장기 — 확정 점 = 실제 근무일(휴무 제외 · 효력 지난 종료 제외) · 지원 중 장기 = 희망 시작일 하루만
//   WH-4  실패 ≠ 0 — 지원 조회 실패 · 공고 조회 실패(서로 옮기지 않음) · 200 건 상한(일부만)
//   WH-5  320/1.0 · 320/2.0 렌더 — 넘침·말줄임·축소·숫자 분리 0 · receiver ≥48 · 가로 스크롤 뒤 마지막 날짜 도달·선택
//   WH-6  내 일정 탭 소비 — 다른 달 · 같은 달 · 이전 `대기` 필터 → ALL · 이미 열린 탭 · 1회 소비
//   WH-7  root 경로(소스) — 일정 날짜는 일자리 날짜와 별도 · 이미 일정 탭이면 탭 스택 비움 · 탭 전환(push 0)
//   캡처는 별도 파일(worker_home_285_capture_test.dart — 이전/이후 같은 하네스).
// [판정286 갱신 2026-11-26] 일자리 안내·카드·탐색 행동은 날짜 영역이 아니라 바로 아래 **일자리 섹션 하나**가 맡는다.
//   WH-8  공고 있는 fixture(서로 다른 날짜 3+) — 미선택 추천→날짜 A→날짜 B→해제 · 최대 2 · 다른 날로 채움 0 · 단일 CTA(pointer+의미 tap)
//         · 띠/시트 공고 표현 0 · 지역 fallback 안내
// [판정287] WH-4 200건(partial) 오늘0·선택일0 단정 0 + 미확인 안내·같은 날짜 링크 · WH-4b 잔존 목록(stale) 선택일0 단정 0 · C287-02 문구
// [BL287-01] WH-11a–e 확정 근무 겹침으로 빠진 공고 수 — 확인된 사유만 · 부분/실패면 0 · 320/2.0
//   WH-9  현실 논리 높이(360×780) — 수동 스크롤로 날짜 → 선택 → 세로 offset·포커스 유지(자동 스크롤 0) → 일자리 CTA 수동 도달
// ignore_for_file: depend_on_referenced_packages
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ALfit/models/core/application_model.dart';
import 'package:ALfit/models/core/attendance_model.dart';
import 'package:ALfit/models/core/business_model.dart';
import 'package:ALfit/models/core/id_card_access_request_model.dart';
import 'package:ALfit/models/core/invite_region_preference.dart';
import 'package:ALfit/models/core/slot_model.dart';
import 'package:ALfit/models/core/to_model.dart';
import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/models/core/user_region.dart';
import 'package:ALfit/models/core/work_detail_data.dart';
import 'package:ALfit/providers/notification_provider.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/screens/user/my_schedule_reads.dart';
import 'package:ALfit/screens/user/my_schedule_screen.dart';
import 'package:ALfit/screens/user/user_home_reads.dart';
import 'package:ALfit/screens/user/user_home_screen.dart';
import 'package:ALfit/screens/user/user_tab_scope.dart';
import 'package:ALfit/services/payroll_correction_service.dart';
import 'package:ALfit/theme/app_colors.dart';
import 'package:ALfit/theme/role_theme.dart';

import 'support/checkin_contract_fixture.dart';
import 'support/du1_vq_capture.dart';
import 'support/visible_text.dart';
import 'package:ALfit/widgets/user/cards/job_image_placeholder.dart';

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

/// 새 카카오 근무자 — 지역·서류·계좌 없음.
UserModel _newWorker() => UserModel(
      uid: 'u1', username: '', name: '김알핏', email: '', role: UserRole.USER,
      accountStatus: 'active', passVerifiedAt: DateTime(2026, 11, 25),
      nationalityStatus: 'unknown', authProviders: const ['kakao'], signupSource: 'kakao_v1',
    );

// ── 고정 시각: 2026-11-26(목) KST 10:00 — 띠 = 11/26 목 … 12/2 수(달이 바뀐다) ──
final DateTime _clock = DateTime.utc(2026, 11, 26, 1);
DateTime _k(int m, int d) => DateTime.utc(2026, m, d); // 홈의 KST 달력일 키

const _longBiz = '서울특별시 강남구 제1물류센터 야간운영팀 상시근무지';

ApplicationModel _short(String id, DateTime day, String status,
        {String start = '09:00', String end = '18:00', String biz = '가람 물류센터', String type = '피킹'}) =>
    ApplicationModel(
      id: id, toId: 'to_$id', uid: 'u1', businessId: 'b_$id', businessName: biz, toTitle: '단기 공고',
      status: status, selectedWorkType: type, startTime: start, endTime: end, wage: 12000, wageType: 'hourly',
      workDate: day, appliedAt: _k(11, 20), applicationType: AppType.shortTerm,
      confirmedAt: status == AppStatus.pending ? null : _k(11, 1),
    );

/// 같은 날(11/28 토) 3건 — 계약 진행 중 07:00 · 확정 09:00(긴 사업장명) · 지원 중 13:00. 11/29 일은 지원 중만.
List<ApplicationModel> _mixedApps() => [
      _short('c1', _k(11, 28), AppStatus.confirmed, start: '09:00', end: '18:00', biz: _longBiz, type: '분류'),
      _short('c2', _k(11, 28), AppStatus.contractPending, start: '07:00', end: '12:00', biz: '나래 센터'),
      _short('p1', _k(11, 28), AppStatus.pending, start: '13:00', end: '22:00', biz: '다온 창고'),
      _short('p2', _k(11, 29), AppStatus.pending, start: '13:00', end: '22:00', biz: '라온 마트'),
    ];

const _wd = WorkDetailData(wdId: 'wd1', workType: '상하차', wage: 12000, requiredCount: 1, startTime: '10:00', endTime: '15:00');

/// [판정286] 홈 추천 후보가 되는 flex 공고 — 날짜 키 하나(슬롯 미조회 = 모름 → 후보 유지).
/// [BL287-01] 확정 근무(11/28 09–18)와 겹치지 않는 시간의 업무.
const _wdNight = WorkDetailData(wdId: 'wd2', workType: '야간 분류', wage: 13000, requiredCount: 1, startTime: '19:00', endTime: '23:00');

TOModel _flex(String id, String title, String dateKey, {String? city, WorkDetailData work = _wd}) => TOModel(
      id: id, businessId: 'b$id', businessName: '사업장 $id', businessCity: city ?? '강남구', type: 'flex',
      title: title, creatorUID: 'admin1', status: TOStatus.active, deadlineType: 'NONE', hoursBeforeStart: 0,
      workDetails: [work], slotDateKeys: [dateKey], totalSlots: 1, totalRequired: 1,
      totalConfirmed: 0, totalPending: 0, isPublished: true, publishMode: 'immediate',
      createdAt: _k(11, 20), statusUpdatedAt: _k(11, 20),
    );

/// 장기 — L1 확정 월~금(11/27 금 휴무) · L2 확정 토 근무였으나 11/27 퇴사 효력 · P 지원 중(희망 시작 11/30).
List<ApplicationModel> _longApps() => [
      ApplicationModel(
        id: 'L1', toId: 'toL1', uid: 'u1', businessId: 'bL1', businessName: '장기 물류', toTitle: '장기 공고',
        status: AppStatus.confirmed, selectedWorkType: '피킹', startTime: '08:00', endTime: '17:00', wage: 100000,
        workDate: _k(11, 20), appliedAt: _k(11, 10), confirmedAt: _k(11, 19), applicationType: AppType.longTerm,
        workEndDate: _k(12, 31), workDays: const ['월', '화', '수', '목', '금'], leaveDates: [_k(11, 27)],
      ),
      ApplicationModel(
        id: 'L2', toId: 'toL2', uid: 'u1', businessId: 'bL2', businessName: '주말 센터', toTitle: '장기 공고',
        status: AppStatus.confirmed, selectedWorkType: '분류', startTime: '09:00', endTime: '18:00', wage: 100000,
        workDate: _k(11, 1), appliedAt: _k(10, 25), confirmedAt: _k(10, 30), applicationType: AppType.longTerm,
        workEndDate: _k(12, 31), workDays: const ['토'], resignStatus: AppStatus.approved, actualResignDate: _k(11, 27),
      ),
      ApplicationModel(
        id: 'P', toId: 'toP', uid: 'u1', businessId: 'bP', businessName: '희망 센터', toTitle: '장기 공고',
        status: AppStatus.pending, selectedWorkType: '포장', startTime: '09:00', endTime: '18:00', wage: 100000,
        workDate: _k(11, 22), appliedAt: _k(11, 22), applicationType: AppType.longTerm, desiredStartDate: _k(11, 30),
        workEndDate: _k(12, 31), workDays: const ['월', '화', '수', '목', '금'],
      ),
    ];

UserHomeReads _reads({
  List<ApplicationModel> apps = const [],
  bool appsFail = false,
  bool tosFail = false,
  List<TOModel> tos = const [],
  List<IdCardAccessRequestModel> idReqs = const [],
  bool withTodayContract = false,
}) =>
    UserHomeReads(
      slotsForTO: (_) async => const <SlotModel>[],
      myContracts: (_) async => withTodayContract
          ? apps.where((a) => a.status == AppStatus.confirmed).map((a) => checkInContractFor(a)).toList()
          : const [],
      myApplications: (_) async {
        if (appsFail) throw Exception('WH285 지원 조회 실패 fixture');
        return apps;
      },
      myMonthlyAttendances: ({required String userId, required int year, required int month}) async =>
          const <AttendanceModel>[],
      publishedTOs: () async {
        if (tosFail) throw Exception('WH285 공고 조회 실패 fixture');
        return tos;
      },
      pendingIdCardRequests: (_) async => idReqs,
      myRenewalProposals: () async => const [],
      businessById: (id) async => BusinessModel(
          id: id, name: 'b', ownerId: 'o', businessNumber: '0', address: 'a', category: 'c',
          subCategory: 's', isApproved: true, createdAt: DateTime(2026)),
      invalidatePublishedTOsCache: () {},
      documentCorrections: () async => DocumentCorrectionSurface.empty,
    );

/// 탭 전환 기록 대역 — root 가 주는 것과 같은 함수 모양.
class _Rec {
  final tabs = <int>[];
  final jobDates = <(int, DateTime)>[];
  final scheduleDates = <DateTime>[];
}

class _PushCount extends NavigatorObserver {
  int pushes = 0;
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) => pushes++;
}

Future<(_Rec, _PushCount)> _pumpHome(WidgetTester t, UserHomeReads reads,
    {UserModel? user, double width = 360, double height = 4200, double scale = 1.0}) async {
  t.view.physicalSize = Size(width, height);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  final rec = _Rec();
  final nav = _PushCount();
  // 같은 시험 안에서 다시 그릴 때 이전 홈 State(읽기 경계)를 물려받지 않게 한 번 비운다.
  await t.pumpWidget(const SizedBox.shrink());
  await t.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider<UserProvider>.value(value: _W(user ?? _newWorker())),
      ChangeNotifierProvider<NotificationProvider>(create: (_) => NotificationProvider()),
    ],
    child: MaterialApp(
      theme: RoleTheme.workerTheme,
      debugShowCheckedModeBanner: false,
      navigatorObservers: [nav],
      builder: (ctx, child) => MediaQuery(
        data: MediaQuery.of(ctx).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: UserTabScope(
        switchToTab: rec.tabs.add,
        switchToTabWithDate: (i, d) => rec.jobDates.add((i, d)),
        pendingJobDate: null,
        clearPendingJobDate: () {},
        pendingScheduleMonth: null,
        clearPendingScheduleMonth: () {},
        switchToScheduleNow: () {},
        switchToScheduleDate: rec.scheduleDates.add,
        child: UserHomeScreen(reads: reads, clock: () => _clock),
      ),
    ),
  ));
  for (var i = 0; i < 20; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
  nav.pushes = 0; // 첫 화면 경로는 세지 않는다
  return (rec, nav);
}

final _area = find.byKey(const ValueKey('worker-home-date-area'));
final _jobs = find.byKey(const ValueKey('worker-home-jobs-section'));

/// 날짜 칸 — 의미 이름이 `M월 D일 요일요일…` 로 시작하는 단일 버튼 노드.
Finder _cell(String prefix) => find.byWidgetPredicate(
    (w) => w is Semantics && w.properties.button == true && (w.properties.label ?? '').startsWith(prefix));

String _cellLabel(WidgetTester t, String prefix) => t.widget<Semantics>(_cell(prefix)).properties.label!;

Future<void> _settle(WidgetTester t) async {
  for (var i = 0; i < 6; i++) {
    await t.pump(const Duration(milliseconds: 60));
  }
}

const _dayPrefixes = [
  '11월 26일 목요일', '11월 27일 금요일', '11월 28일 토요일', '11월 29일 일요일',
  '11월 30일 월요일', '12월 1일 화요일', '12월 2일 수요일',
];

void main() {
  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
    await initializeDateFormatting('ko_KR');
    await vqLoadFonts();
  });
  setUp(() => SharedPreferences.setMockInitialValues({'tour_completed_user_home': true}));

  testWidgets('WH-1 새 회원 정상0 360/1.0 — 순서 · 빈 날 선택 · 재탭 유지 · 명시 해제 · 일자리 날짜 · 다른 달 의미 tap', (t) async {
    final sem = t.ensureSemantics();
    final (rec, nav) = await _pumpHome(t, _reads());
    expect(t.takeException(), isNull);

    // §2 순서 — 머리 → 시작 준비 → 날짜 영역 → 지원 현황 → 추천 → 수입 → 근무 기록
    double y(String s) => t.getTopLeft(findVisibleText(s).first).dy;
    // [판정286 갱신 2026-11-26] 일자리 섹션(미선택 「추천 일자리」)이 날짜 영역 바로 아래 — 지원 현황 앞.
    final order = ['시작 준비', '날짜별 일정 · 일자리', '추천 일자리', '내 지원 현황', '수입 현황', '내 근무 기록'];
    for (var i = 1; i < order.length; i++) {
      expect(y(order[i - 1]) < y(order[i]), isTrue, reason: '${order[i - 1]} → ${order[i]}');
    }
    // §3 이번 주 일정 섹션 0 · §2 정상0 큰 약속 카드 0 → 날짜 영역의 짧은 안내 1
    expect(findVisibleText('이번 주 일정'), findsNothing);
    expect(findVisibleText('일정 보기'), findsNothing);
    expect(findVisibleText('오늘의 약속'), findsNothing);
    expect(find.descendant(of: find.byType(OutlinedButton), matching: findVisibleText('일자리 찾기')), findsNothing,
        reason: '정상0 큰 카드의 일자리 찾기 버튼 0');
    expect(findVisibleText('오늘 확정된 근무가 없어요'), findsOneWidget);
    expect(y('날짜별 일정 · 일자리') < y('오늘 확정된 근무가 없어요'), isTrue, reason: '안내는 날짜 영역 안');
    // [판정287 C287-02] 시작 준비 지역 줄 — 거리 표현 0 · 실제 동작(선택한 지역 우선)
    expect(findVisibleText('선택한 지역의 일자리를 먼저 보여 드려요'), findsOneWidget);
    expect(findVisibleTextContaining('가까운'), findsNothing);
    // §5 C285-02 지역 없음 + 공고 0 — 제목만 남지 않는다
    expect(findVisibleText('지금 표시할 일자리가 없어요'), findsOneWidget);
    expect(y('추천 일자리') < y('지금 표시할 일자리가 없어요'), isTrue);
    expect(find.descendant(of: _jobs, matching: findVisibleText('일자리 더 보기')), findsOneWidget, reason: '정상0 에도 탐색 행동 하나');

    // §4 C285-01 모든 날짜 = 버튼 + tap action · 초기 선택 0 · 오늘만 `오늘`
    for (final p in _dayPrefixes) {
      expect(_cell(p), findsOneWidget, reason: p);
      final n = t.getSemantics(_cell(p));
      expect(n, containsSemantics(isButton: true, hasTapAction: true, isSelected: false), reason: '$p 선택 가능 · 미선택');
      expect(_cellLabel(t, p).contains('오늘'), p.startsWith('11월 26일'), reason: '$p 오늘 표시');
    }
    expect(findVisibleText('날짜 해제'), findsNothing);
    expect(findVisibleText('11월 28일 일자리 보기'), findsNothing, reason: '미선택이면 선택일 CTA 없음');
    expect(find.descendant(of: _area, matching: findVisibleTextContaining('일자리 보기')), findsNothing, reason: '날짜 영역 일자리 버튼 0');

    // 빈 날(공고·일정 0) pointer 선택
    await t.tap(_cell('11월 28일 토요일'));
    await _settle(t);
    expect(t.getSemantics(_cell('11월 28일 토요일')), containsSemantics(isSelected: true));
    expect(findVisibleText('11월 28일 내 일정'), findsOneWidget);
    expect(findVisibleText('이 날짜의 확정 근무나 지원 중인 일정이 없어요'), findsOneWidget);
    // [판정286 갱신 2026-11-26] 공고 안내·버튼은 일자리 섹션 한 곳 — 날짜 영역에는 0.
    expect(find.descendant(of: _jobs, matching: findVisibleText('이 날짜에 표시할 일자리가 없어요')), findsOneWidget);
    expect(find.descendant(of: _jobs, matching: findVisibleText('다른 날짜도 골라 보세요')), findsOneWidget);
    expect(findVisibleText('이 날짜에 표시할 일자리가 없어요'), findsOneWidget, reason: '같은 뜻 안내 한 번');
    expect(
        find.descendant(
            of: _area,
            matching: find.byWidgetPredicate((w) =>
                w is Text && visibleText(w.data ?? '').contains('일자리') && visibleText(w.data ?? '') != '날짜별 일정 · 일자리')),
        findsNothing,
        reason: '날짜 영역 = 내 일정만(제목 날짜별 일정 · 일자리 제외)');
    expect(find.descendant(of: _jobs, matching: findVisibleText('11월 28일 일자리 보기')), findsOneWidget, reason: '공고 0 이어도 버튼 유지');
    expect(findVisibleText('오늘 확정된 근무가 없어요'), findsNothing, reason: '선택일 상태로 교체');
    expect(find.descendant(of: _jobs, matching: findVisibleText('11월 28일 일자리')), findsOneWidget, reason: '일자리 섹션 제목 = 같은 선택일');
    expect(findVisibleText('내 일정에서 보기'), findsNothing, reason: '빈 날은 일정 링크 생략');
    // 같은 날 재탭 = 선택 유지
    await t.tap(_cell('11월 28일 토요일'));
    await _settle(t);
    expect(t.getSemantics(_cell('11월 28일 토요일')), containsSemantics(isSelected: true));
    expect(findVisibleText('11월 28일 내 일정'), findsOneWidget);
    // 버튼 → 일자리 탭 날짜(선택 KST 하루)
    await t.tap(findVisibleText('11월 28일 일자리 보기'));
    await _settle(t);
    expect(rec.jobDates, [(1, _k(11, 28))]);
    // 명시 해제
    final clear = find.bySemanticsLabel('날짜 해제');
    expect(t.getSemantics(clear), containsSemantics(isButton: true, hasTapAction: true));
    await t.tap(clear);
    await _settle(t);
    expect(findVisibleText('11월 28일 내 일정'), findsNothing);
    expect(t.getSemantics(_cell('11월 28일 토요일')), containsSemantics(isSelected: false));
    expect(findVisibleText('오늘 확정된 근무가 없어요'), findsOneWidget);
    // 다른 달(12/1) — 의미 tap action 으로 선택 → 의미 tap 으로 버튼
    t.semantics.tap(find.semantics.byLabel(RegExp('^12월 1일 화요일')));
    await _settle(t);
    expect(t.getSemantics(_cell('12월 1일 화요일')), containsSemantics(isSelected: true));
    expect(findVisibleText('12월 1일 내 일정'), findsOneWidget);
    t.semantics.tap(find.semantics.byLabel('12월 1일 일자리 보기'));
    await _settle(t);
    expect(rec.jobDates.last, (1, _k(12, 1)));
    // 날짜 탭·해제·버튼 어디에도 홈 Navigator push 0(탭 전환은 root 가 한다)
    expect(nav.pushes, 0);
    expect(rec.tabs, isEmpty);
    sem.dispose();
  });

  testWidgets('WH-2 혼합 일정 360/1.0 — 두 점 · 범례 · 확정 먼저 시각순 2건 · 외 1건 · 내 일정 날짜', (t) async {
    final sem = t.ensureSemantics();
    final (rec, nav) = await _pumpHome(t, _reads(apps: _mixedApps()));
    expect(t.takeException(), isNull);
    final sat = _cellLabel(t, '11월 28일 토요일');
    expect(sat, contains('확정 근무 있음'));
    expect(sat, contains('지원 중 있음'));
    final sun = _cellLabel(t, '11월 29일 일요일');
    expect(sun.contains('확정 근무 있음'), isFalse, reason: '지원 중을 확정으로 부르지 않는다');
    expect(sun, contains('지원 중 있음'));
    // 두 점 — 같은 칸 안에 확정·지원 중 색 점이 함께
    Iterable<Color?> dotColors(String p) => find
        .descendant(of: _cell(p), matching: find.byType(Container))
        .evaluate()
        .map((e) => ((e.widget as Container).decoration as BoxDecoration?))
        .where((d) => d?.shape == BoxShape.circle)
        .map((d) => d!.color);
    expect(dotColors('11월 28일 토요일'), containsAll([AppColors.successDark, AppColors.warningDarkest]));
    expect(dotColors('11월 29일 일요일').toList(), [AppColors.warningDarkest]);
    expect(dotColors('11월 27일 금요일'), isEmpty);
    expect(find.descendant(of: _area, matching: findVisibleText('확정 근무')), findsOneWidget, reason: '범례');
    expect(find.descendant(of: _area, matching: findVisibleText('지원 중')), findsOneWidget, reason: '범례');
    // 혼합 날 선택 — 확정 먼저(계약 진행 중 07:00 → 확정 09:00), 지원 중은 `외 1건`
    await t.tap(_cell('11월 28일 토요일'));
    await _settle(t);
    final first = findVisibleText('계약 진행 중 · 07:00–12:00');
    final second = findVisibleText('확정 · 09:00–18:00');
    expect(first, findsOneWidget);
    expect(second, findsOneWidget);
    expect(t.getTopLeft(first).dy < t.getTopLeft(second).dy, isTrue);
    expect(find.descendant(of: _area, matching: findVisibleText('$_longBiz · 분류')), findsOneWidget, reason: '사업장 전문(말줄임 0)');
    expect(findVisibleText('지원 중 · 13:00–22:00'), findsNothing);
    expect(findVisibleText('외 1건'), findsOneWidget);
    // 「내 일정에서 보기」 — pointer · 의미 tap 모두 같은 날짜
    final link = find.bySemanticsLabel('내 일정에서 보기');
    expect(t.getSemantics(link), containsSemantics(isButton: true, hasTapAction: true));
    await t.tap(link);
    await _settle(t);
    t.semantics.tap(find.semantics.byLabel('내 일정에서 보기'));
    await _settle(t);
    expect(rec.scheduleDates, [_k(11, 28), _k(11, 28)]);
    expect(rec.tabs, isEmpty, reason: '일반 탭 전환으로 물러나지 않는다(날짜 전달)');
    // 지원 중만 있는 날 — 상태 명시
    await t.tap(_cell('11월 29일 일요일'));
    await _settle(t);
    expect(findVisibleText('지원 중 · 13:00–22:00'), findsOneWidget);
    expect(findVisibleText('이 날짜의 확정 근무나 지원 중인 일정이 없어요'), findsNothing);
    expect(nav.pushes, 0);
    sem.dispose();
  });

  testWidgets('WH-3 장기 — 실제 근무일만 확정 점 · 휴무·종료 효력 제외 · 지원 중 장기는 희망 시작일 하루', (t) async {
    final sem = t.ensureSemantics();
    await _pumpHome(t, _reads(apps: _longApps(), withTodayContract: true));
    expect(t.takeException(), isNull);
    bool conf(String p) => _cellLabel(t, p).contains('확정 근무 있음');
    bool pend(String p) => _cellLabel(t, p).contains('지원 중 있음');
    expect(conf('11월 26일 목요일'), isTrue);
    expect(conf('11월 27일 금요일'), isFalse, reason: '휴무일은 확정 근무가 아니다');
    expect(conf('11월 28일 토요일'), isFalse, reason: 'L2 종료 효력(11/27) 뒤 토요일');
    expect(conf('11월 29일 일요일'), isFalse);
    expect(conf('11월 30일 월요일'), isTrue);
    expect(conf('12월 1일 화요일'), isTrue);
    expect(conf('12월 2일 수요일'), isTrue);
    expect([for (final p in _dayPrefixes) pend(p)], [false, false, false, false, true, false, false],
        reason: '지원 중 장기 = 희망 시작일 하루(매주 반복 0)');
    expect(findVisibleText('오늘의 약속'), findsOneWidget, reason: '오늘 근무하는 장기 = B');
    expect(findVisibleText('오늘 확정된 근무가 없어요'), findsNothing);
    // 휴무일 선택 — 확정 근무로 보이지 않는다(점·본문 같은 projection)
    await t.tap(_cell('11월 27일 금요일'));
    await _settle(t);
    expect(findVisibleText('이 날짜의 확정 근무나 지원 중인 일정이 없어요'), findsOneWidget);
    // 확정+지원 중 같은 날(11/30)
    await t.tap(_cell('11월 30일 월요일'));
    await _settle(t);
    expect(findVisibleText('확정 · 08:00–17:00'), findsOneWidget);
    expect(findVisibleText('지원 중 · 09:00–18:00'), findsOneWidget);
    sem.dispose();
  });

  testWidgets('WH-4 실패 ≠ 0 — 지원 실패 · 공고 실패 · 200 건 상한', (t) async {
    // 지원 조회 실패 — 오늘 정상0 안내 0 · 선택일 `없어요` 0 · 확인 경로 · 공고는 공고대로
    await _pumpHome(t, _reads(appsFail: true));
    expect(findVisibleText('오늘 확정된 근무가 없어요'), findsNothing);
    await t.tap(_cell('11월 27일 금요일'));
    await _settle(t);
    expect(findVisibleText('일정을 확인하지 못했어요. 내 일정에서 확인해 주세요'), findsOneWidget);
    expect(findVisibleText('이 날짜의 확정 근무나 지원 중인 일정이 없어요'), findsNothing);
    expect(findVisibleText('내 일정에서 보기'), findsOneWidget);
    expect(find.descendant(of: _jobs, matching: findVisibleText('이 날짜에 표시할 일자리가 없어요')), findsOneWidget,
        reason: '공고 조회는 성공 — 일정 실패를 공고로 옮기지 않는다'); // [판정286 갱신 2026-11-26]
    expect(findVisibleText('11월 27일 일자리 보기'), findsOneWidget);

    // 공고 조회 실패 — `없어요`·`0개` 0 · 일정은 일정대로
    await _pumpHome(t, _reads(tosFail: true));
    await t.tap(_cell('11월 27일 금요일'));
    await _settle(t);
    // [판정286 갱신 2026-11-26] 공고 실패 안내는 일자리 섹션의 기존 실패 카드(재시도 = 별개 복구 행동).
    expect(find.descendant(of: _jobs, matching: findVisibleText('공고를 불러오지 못했어요')), findsOneWidget);
    expect(findVisibleText('이 날짜에 표시할 일자리가 없어요'), findsNothing);
    expect(findVisibleText('이 날짜의 확정 근무나 지원 중인 일정이 없어요'), findsOneWidget);
    expect(findVisibleText('11월 27일 일자리 보기'), findsOneWidget, reason: '실패여도 버튼 유지');

    // 200 건 상한 — 일부만 읽었을 수 있다
    // [판정287 C287-01 갱신 2026-11-26] 미선택 오늘 0 도, 선택일 0 도 정상0 으로 단정하지 않는다 — 미확인 안내 + 같은 날짜 일정 링크.
    final many = [for (var i = 0; i < 200; i++) _short('x$i', _k(12, 25), AppStatus.pending)];
    final (rec200, _) = await _pumpHome(t, _reads(apps: many));
    expect(findVisibleText('오늘 확정된 근무가 없어요'), findsNothing, reason: 'partial 오늘 0 단정 0');
    expect(findVisibleText('오늘 일정을 모두 확인하지 못했어요. 내 일정에서 확인해 주세요'), findsOneWidget);
    await t.tap(_cell('11월 27일 금요일'));
    await _settle(t);
    expect(findVisibleText('이 날짜의 확정 근무나 지원 중인 일정이 없어요'), findsNothing, reason: 'partial 선택일 0 단정 0');
    expect(findVisibleText('이 날짜의 일정을 모두 확인하지 못했어요. 내 일정에서 확인해 주세요'), findsOneWidget);
    expect(findVisibleText('내 일정에서 보기'), findsOneWidget);
    await t.tap(find.bySemanticsLabel('내 일정에서 보기'));
    await _settle(t);
    expect(rec200.scheduleDates, [_k(11, 27)], reason: '같은 날짜 일정 링크');

    // [판정287 C287-01 갱신 2026-11-26] 일부만 읽었어도 읽은 일정이 있으면 그대로 보이고 일부 고지를 붙인다.
    final manyWithDay = [
      for (var i = 0; i < 199; i++) _short('y$i', _k(12, 25), AppStatus.pending),
      _short('d1', _k(11, 28), AppStatus.confirmed, start: '10:00', end: '15:00', biz: '읽은 사업장'),
    ];
    await _pumpHome(t, _reads(apps: manyWithDay));
    await t.tap(_cell('11월 28일 토요일'));
    await _settle(t);
    expect(findVisibleText('확정 · 10:00–15:00'), findsOneWidget);
    expect(findVisibleText('일부 일정만 보여요. 내 일정에서 모두 확인해 주세요'), findsOneWidget);
    expect(findVisibleText('이 날짜의 일정을 모두 확인하지 못했어요. 내 일정에서 확인해 주세요'), findsNothing);
  });

  testWidgets('WH-4b 잔존 목록 — 비어 있지 않은 이전 목록 뒤 재조회 실패 + 선택일 0 ≠ 정상0', (t) async {
    // [판정287 C287-01 갱신 2026-11-26] 첫 조회 성공(11/29 지원 중 1건) → 당겨서 새로고침 실패(이전 목록 유지) → 11/27(그날 0) 선택.
    var calls = 0;
    final reads = UserHomeReads(
      slotsForTO: (_) async => const <SlotModel>[],
      myContracts: (_) async => const [],
      myApplications: (_) async {
        calls++;
        if (calls > 1) throw Exception('WH287 재조회 실패 fixture');
        return [_short('p9', _k(11, 29), AppStatus.pending, start: '13:00', end: '22:00', biz: '라온 마트')];
      },
      myMonthlyAttendances: ({required String userId, required int year, required int month}) async =>
          const <AttendanceModel>[],
      publishedTOs: () async => const <TOModel>[],
      pendingIdCardRequests: (_) async => const [],
      myRenewalProposals: () async => const [],
      businessById: (id) async => null,
      invalidatePublishedTOsCache: () {},
      documentCorrections: () async => DocumentCorrectionSurface.empty,
    );
    final (rec, _) = await _pumpHome(t, reads);
    expect(findVisibleText('오늘 확정된 근무가 없어요'), findsOneWidget, reason: '첫 조회는 정상(전량)');
    final refresh = t.state<RefreshIndicatorState>(find.byType(RefreshIndicator));
    final done = refresh.show();
    for (var i = 0; i < 20; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    await done;
    await _settle(t);
    expect(calls, greaterThanOrEqualTo(2), reason: '재조회가 실제로 일어났다');
    expect(findVisibleText('오늘 확정된 근무가 없어요'), findsNothing, reason: '재조회 실패면 오늘 0 단정 0(기존)');
    await t.tap(_cell('11월 27일 금요일'));
    await _settle(t);
    expect(findVisibleText('이 날짜의 확정 근무나 지원 중인 일정이 없어요'), findsNothing, reason: 'stale 선택일 0 단정 0');
    expect(findVisibleText('이 날짜의 일정을 모두 확인하지 못했어요. 내 일정에서 확인해 주세요'), findsOneWidget);
    await t.tap(find.bySemanticsLabel('내 일정에서 보기'));
    await _settle(t);
    expect(rec.scheduleDates, [_k(11, 27)]);
    // 읽어 둔 일정이 있는 날은 그대로 보이고 최신 아님 고지
    await t.tap(_cell('11월 29일 일요일'));
    await _settle(t);
    expect(findVisibleText('지원 중 · 13:00–22:00'), findsOneWidget);
    expect(findVisibleText('최신 일정이 아닐 수 있어요. 내 일정에서 확인해 주세요'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('WH-0 순서 360/1.0 — 필수응답 → 실제 약속(B) → 시작 준비 → 날짜 영역 → 지원 현황 · 준비 카드 한 번', (t) async {
    final today = _short('t1', _k(11, 26), AppStatus.confirmed, start: '13:00', end: '18:00');
    final req = IdCardAccessRequestModel(
      id: 'req1', requesterId: 'admin1', requesterName: '박사장', requesterBusinessId: 'b_t1',
      requesterBusinessName: '가람 물류센터', targetUserId: 'u1', targetUserName: '김알핏',
      reason: IdCardAccessReason.incomeTax, status: IdCardAccessStatus.pending, requestedAt: _k(11, 25),
    );
    await _pumpHome(t, _reads(apps: [today], idReqs: [req], withTodayContract: true));
    expect(t.takeException(), isNull);
    double y(String s) => t.getTopLeft(findVisibleText(s).first).dy;
    final order = ['가람 물류센터에서 신분증 열람을 요청했어요', '오늘의 약속', '시작 준비', '날짜별 일정 · 일자리', '추천 일자리', '내 지원 현황']; // [판정286 갱신 2026-11-26]
    for (var i = 1; i < order.length; i++) {
      expect(y(order[i - 1]) < y(order[i]), isTrue, reason: '${order[i - 1]} → ${order[i]}');
    }
    expect(findVisibleText('시작 준비'), findsOneWidget, reason: '준비 카드 한 번');
    expect(findVisibleText('오늘 확정된 근무가 없어요'), findsNothing, reason: '실제 약속이 있으면 정상0 안내 0');
    expect(_cellLabel(t, '11월 26일 목요일'), contains('확정 근무 있음'));
  });

  // ── [판정286] 공고 있는 fixture — 서로 다른 날짜 3+ ──
  testWidgets('WH-8 일자리 섹션 — 미선택 추천 → 날짜 A → 날짜 B → 해제 · 최대 2 · 단일 CTA · 띠/시트 공고 표현 0', (t) async {
    final sem = t.ensureSemantics();
    final tos = [
      _flex('A1', '11월28 공고 하나', '2026-11-28'),
      _flex('A2', '11월28 공고 둘', '2026-11-28'),
      _flex('A3', '11월28 공고 셋', '2026-11-28'),
      _flex('B1', '11월30 공고', '2026-11-30'),
      _flex('C1', '12월1 공고', '2026-12-01'),
    ];
    final (rec, nav) = await _pumpHome(t, _reads(tos: tos));
    expect(t.takeException(), isNull);
    Iterable<String> cards() => [
          for (final x in tos)
            if (find.descendant(of: _jobs, matching: findVisibleText(x.title)).evaluate().isNotEmpty) x.title
        ];
    Finder outlined() => find.descendant(of: _jobs, matching: find.byType(OutlinedButton));
    // 미선택 — 「추천 일자리」 · 카드 최대 2 · 탐색 행동 하나 · 전체 보기/모두 보기/후보 수 0
    expect(find.descendant(of: _jobs, matching: findVisibleText('추천 일자리')), findsOneWidget);
    expect(findVisibleText('둘러볼 일자리'), findsNothing);
    expect(cards().length, 2);
    expect(outlined(), findsOneWidget);
    expect(find.descendant(of: _jobs, matching: findVisibleText('일자리 더 보기')), findsOneWidget);
    for (final bad in ['전체 보기', '일자리 5개']) {
      expect(find.descendant(of: _jobs, matching: findVisibleTextContaining(bad)), findsNothing, reason: bad);
    }
    expect(findVisibleTextContaining('모두 보기'), findsNothing);
    expect(findVisibleTextContaining('근처'), findsNothing);
    // 띠 공고 표현 0 — `N개` 글자·의미 이름의 `일자리`
    expect(find.descendant(of: _area, matching: find.byWidgetPredicate((w) => w is Text && RegExp(r'^\d+개$').hasMatch(w.data ?? ''))),
        findsNothing);
    for (final pfx in _dayPrefixes) {
      expect(_cellLabel(t, pfx).contains('일자리'), isFalse, reason: '$pfx 의미 이름 공고 0');
    }
    // 미선택 CTA — 일반 일자리 탭(새 날짜 만들지 않음) · pointer
    await t.ensureVisible(outlined());
    await t.tap(outlined());
    await _settle(t);
    expect(rec.tabs, [1]);
    expect(rec.jobDates, isEmpty);

    // 날짜 A(11/28) — 그날 공고만 · 최대 2 · CTA 날짜
    await t.ensureVisible(_cell('11월 28일 토요일'));
    await t.tap(_cell('11월 28일 토요일'));
    await _settle(t);
    expect(find.descendant(of: _jobs, matching: findVisibleText('11월 28일 일자리')), findsOneWidget);
    expect(cards().length, 2);
    expect(cards().every((c) => c.startsWith('11월28')), isTrue, reason: '선택일 공고만 ${cards()}');
    expect(outlined(), findsOneWidget);
    final ctaA = find.bySemanticsLabel('11월 28일 일자리 보기');
    expect(ctaA, findsOneWidget, reason: 'CTA 의미 노드 하나');
    expect(t.getSemantics(ctaA), containsSemantics(isButton: true, hasTapAction: true));
    t.semantics.tap(find.semantics.byLabel('11월 28일 일자리 보기'));
    await _settle(t);
    expect(rec.jobDates.last, (1, _k(11, 28)));

    // 날짜 B(11/30) — 1건이면 1장 · 다른 날 공고로 채우지 않는다
    await t.ensureVisible(_cell('11월 30일 월요일'));
    await t.tap(_cell('11월 30일 월요일'));
    await _settle(t);
    expect(find.descendant(of: _jobs, matching: findVisibleText('11월 30일 일자리')), findsOneWidget);
    expect(cards().toList(), ['11월30 공고']);
    await t.ensureVisible(outlined());
    await t.tap(outlined());
    await _settle(t);
    expect(rec.jobDates.last, (1, _k(11, 30)));
    // 공고 없는 날(11/29) — 안내 한 번 + 같은 자리 CTA 유지
    await t.ensureVisible(_cell('11월 29일 일요일'));
    await t.tap(_cell('11월 29일 일요일'));
    await _settle(t);
    expect(cards(), isEmpty);
    expect(findVisibleText('이 날짜에 표시할 일자리가 없어요'), findsOneWidget);
    expect(outlined(), findsOneWidget);
    // 명시 해제 → 홈 추천 복귀(탭 이동 0)
    final tabsBefore = rec.tabs.length;
    await t.ensureVisible(find.bySemanticsLabel('날짜 해제'));
    await t.tap(find.bySemanticsLabel('날짜 해제'));
    await _settle(t);
    expect(find.descendant(of: _jobs, matching: findVisibleText('추천 일자리')), findsOneWidget);
    expect(cards().length, 2);
    expect(rec.tabs.length, tabsBefore, reason: '해제로 탭 이동 0');
    expect(nav.pushes, 0, reason: '날짜 탭·해제·CTA 로 홈 Navigator push 0');
    // 날짜 시트 — 공고 점·`공고 있음` 범례 0(시트 자체는 모달 경로라 push 를 센다)
    await t.ensureVisible(find.bySemanticsLabel('날짜 선택'));
    await t.tap(find.bySemanticsLabel('날짜 선택'));
    await _settle(t);
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(find.descendant(of: find.byType(BottomSheet), matching: find.text('공고 있음')), findsNothing);
    sem.dispose();
  });

  testWidgets('WH-8b 지역 fallback — 내 지역 0 · 다른 지역 공고 안내 유지 · 지역 우선 부제(거리 표현 0)', (t) async {
    const region = UserRegion(province: '서울특별시', city: '강남구', district: '역삼동');
    final user = UserModel(
      uid: 'u1', username: '', name: '김알핏', email: '', role: UserRole.USER, accountStatus: 'active',
      passVerifiedAt: DateTime(2026, 11, 25), homeRegion: region);
    await _pumpHome(t, _reads(tos: [_flex('S1', '송파 공고', '2026-11-28', city: '송파구')]), user: user);
    expect(find.descendant(of: _jobs, matching: findVisibleText('강남구에 표시할 일자리가 없어요')), findsOneWidget);
    expect(find.descendant(of: _jobs, matching: findVisibleText('송파 공고')), findsOneWidget);
    await _pumpHome(t, _reads(tos: [
      _flex('G1', '강남 공고 하나', '2026-11-28', city: '강남구'),
      _flex('G2', '강남 공고 둘', '2026-11-30', city: '강남구'),
    ]), user: user);
    expect(find.descendant(of: _jobs, matching: findVisibleText('강남구 일자리를 먼저 보여드려요')), findsOneWidget);
    expect(findVisibleTextContaining('근처'), findsNothing);
    expect(t.takeException(), isNull);
  });

  testWidgets('WH-9 현실 높이 360×780 — 수동 스크롤 → 날짜 선택 → offset 유지(자동 스크롤 0) → 일자리 CTA 수동 도달', (t) async {
    final tos = [_flex('A1', '11월28 공고 하나', '2026-11-28'), _flex('A2', '11월28 공고 둘', '2026-11-28')];
    await _pumpHome(t, _reads(apps: _mixedApps(), tos: tos), height: 780);
    final bodyEl = find.byType(Scrollable).evaluate()
        .where((e) => (e.widget as Scrollable).axisDirection == AxisDirection.down).toList();
    expect(bodyEl, isNotEmpty);
    final st = (bodyEl.first as StatefulElement).state as ScrollableState;
    ScrollPosition pos() => st.position;
    // 손 스크롤 — 화면 가운데에서 위로 끈다
    Future<void> swipe() => t.dragFrom(const Offset(180, 560), const Offset(0, -200));
    // 사용자처럼 끌어서 날짜 칸이 보일 때까지 내린다(ensureVisible 아님 — 손 스크롤)
    var drags = 0;
    // 첫 화면에서 띠가 보이더라도 한 번은 손으로 내려 0 이 아닌 offset 에서 선택한다(자동 복귀·이동 판별용).
    await t.dragFrom(const Offset(180, 560), const Offset(0, -120));
    await _settle(t);
    while (t.getRect(_cell('11월 28일 토요일')).bottom > 700 && drags < 20) {
      await swipe();
      await _settle(t);
      drags++;
    }
    final before = pos().pixels;
    final r = t.getRect(_cell('11월 28일 토요일'));
    expect(r.top >= 0 && r.bottom <= 780, isTrue, reason: '날짜 칸 화면 안 $r');
    await t.tap(_cell('11월 28일 토요일'));
    for (var i = 0; i < 12; i++) {
      await t.pump(const Duration(milliseconds: 60));
    }
    expect(pos().pixels, closeTo(before, 0.5), reason: '선택 뒤 자동 스크롤 0');
    expect(FocusManager.instance.primaryFocus?.context?.widget is EditableText, isFalse, reason: '포커스 강탈 0');
    // 계속 손으로 내려 일자리 섹션 CTA 까지
    final cta = find.descendant(of: _jobs, matching: find.byType(OutlinedButton));
    var more = 0;
    while (t.getRect(cta).bottom > 780 && more < 20) {
      await swipe();
      await _settle(t);
      more++;
    }
    final cr = t.getRect(cta);
    expect(cr.top >= 0 && cr.bottom <= 780, isTrue, reason: 'CTA 수동 도달 $cr');
    expect(find.descendant(of: _jobs, matching: findVisibleText('11월 28일 일자리 보기')), findsOneWidget);
    // ignore: avoid_print
    print('WH9 drags=$drags offsetAtSelect=${before.toStringAsFixed(1)} more=$more ctaRect=$cr');
    expect(t.takeException(), isNull);
  });

  // [대표 지적 2026-11-26] 추천 카드 대표 이미지 문턱 — 이미지 뒤 남는 글자 영역 기준(360/1.0 에서 보인다).
  for (final c in const [(w: 360.0, sc: 1.0, img: true), (w: 320.0, sc: 1.0, img: true), (w: 320.0, sc: 2.0, img: false), (w: 360.0, sc: 2.0, img: false)]) {
    testWidgets('WH-10 카드 이미지 ${c.w.toInt()}/${c.sc} → ${c.img ? '표시' : '숨김'} · 넘침 0', (t) async {
      await _pumpHome(t, _reads(tos: [_flex('I1', '물류센터 상하차 오전 근무', '2026-11-28'), _flex('I2', '창고 포장 보조', '2026-11-30')]),
          width: c.w, height: c.sc > 1 ? 7000 : 4200, scale: c.sc);
      expect(t.takeException(), isNull);
      final ph = find.descendant(of: _jobs, matching: find.byType(JobImagePlaceholder));
      expect(ph.evaluate().length, c.img ? 2 : 0, reason: '카드 2 장의 이미지 자리(사업장 사진 없음 → 업무 아이콘 자리)');
      if (c.img) {
        final r = t.getRect(ph.first);
        expect(r.width, greaterThanOrEqualTo(60), reason: '이미지 폭 ${r.width}');
        // 이미지 뒤 제목이 들어간다 — 말줄임 없이 전문(두 줄 이내)
        final title = find.descendant(of: _jobs, matching: find.text('물류센터 상하차 오전 근무'));
        final rp = t.renderObject<RenderParagraph>(find.descendant(of: title, matching: find.byType(RichText)));
        expect(rp.didExceedMaxLines, isFalse, reason: '제목 말줄임 0');
      }
    });
  }

  // ── [BL287-01] 확정 근무와 시간이 겹쳐 빠진 공고 — 확인된 사유일 때만 그 수를 말한다 ──
  group('WH-11 겹침 제외 안내', () {
    final conf = _short('cf', _k(11, 28), AppStatus.confirmed, start: '09:00', end: '18:00', biz: '확정 사업장');
    final overlapA = _flex('O1', '겹치는 공고 하나', '2026-11-28');
    final overlapB = _flex('O2', '겹치는 공고 둘', '2026-11-28');
    final night = _flex('N1', '야간 공고', '2026-11-28', work: _wdNight);
    const shownNote = '확정된 근무 시간과 겹치는 일자리 2개는 빼고 보여 드려요';
    const emptyNote = '확정된 근무 시간과 겹치는 일자리 2개는 뺐어요';
    Future<void> pick(WidgetTester t) async {
      await t.ensureVisible(_cell('11월 28일 토요일'));
      await t.tap(_cell('11월 28일 토요일'));
      await _settle(t);
    }

    testWidgets('WH-11a 표시 ≥1 + 제외 2 → 카드 아래 한 줄 · CTA 유지', (t) async {
      await _pumpHome(t, _reads(apps: [conf], tos: [overlapA, overlapB, night]));
      await pick(t);
      expect(find.descendant(of: _jobs, matching: findVisibleText('야간 공고')), findsOneWidget);
      expect(find.descendant(of: _jobs, matching: findVisibleText('겹치는 공고 하나')), findsNothing);
      expect(find.descendant(of: _jobs, matching: findVisibleText(shownNote)), findsOneWidget);
      expect(find.descendant(of: _jobs, matching: findVisibleText('11월 28일 일자리 보기')), findsOneWidget);
      expect(t.getTopLeft(find.descendant(of: _jobs, matching: findVisibleText(shownNote))).dy <
          t.getTopLeft(find.descendant(of: _jobs, matching: findVisibleText('11월 28일 일자리 보기'))).dy, isTrue);
      expect(t.takeException(), isNull);
    });

    testWidgets('WH-11b 표시 0 + 제외 2 → 빈 안내와 함께 · CTA 유지', (t) async {
      await _pumpHome(t, _reads(apps: [conf], tos: [overlapA, overlapB]));
      await pick(t);
      expect(findVisibleText('이 날짜에 표시할 일자리가 없어요'), findsOneWidget);
      expect(find.descendant(of: _jobs, matching: findVisibleText(emptyNote)), findsOneWidget);
      expect(find.descendant(of: _jobs, matching: findVisibleText('11월 28일 일자리 보기')), findsOneWidget);
    });

    testWidgets('WH-11c 제외 0 — 확정 일정이 있어도 겹침이 아니면(다른 날 공고) 사유 0 · 확정 없음도 0', (t) async {
      await _pumpHome(t, _reads(apps: [conf], tos: [_flex('D1', '다른 날 공고', '2026-11-30')]));
      await pick(t);
      expect(findVisibleText('이 날짜에 표시할 일자리가 없어요'), findsOneWidget);
      expect(findVisibleTextContaining('겹치는 일자리'), findsNothing, reason: '확정 일정 존재만으로 충돌 탓 0');
      await _pumpHome(t, _reads(tos: [overlapA, night]));
      await pick(t);
      expect(findVisibleTextContaining('겹치는 일자리'), findsNothing);
      expect(find.descendant(of: _jobs, matching: findVisibleText('겹치는 공고 하나')), findsOneWidget);
    });

    testWidgets('WH-11d 부분 조회(200 건) · 공고 실패 · 지원 실패 → 사유 문구 0', (t) async {
      final many = [for (var i = 0; i < 199; i++) _short('z$i', _k(12, 25), AppStatus.pending), conf];
      await _pumpHome(t, _reads(apps: many, tos: [overlapA, overlapB, night]));
      await pick(t);
      expect(findVisibleTextContaining('겹치는 일자리'), findsNothing, reason: '200 건 상한 — 사유를 말하지 않는다');
      await _pumpHome(t, _reads(apps: [conf], tosFail: true));
      await pick(t);
      expect(findVisibleTextContaining('겹치는 일자리'), findsNothing);
      expect(find.descendant(of: _jobs, matching: findVisibleText('공고를 불러오지 못했어요')), findsOneWidget);
      await _pumpHome(t, _reads(appsFail: true, tos: [overlapA, overlapB, night]));
      await pick(t);
      expect(findVisibleTextContaining('겹치는 일자리'), findsNothing, reason: '지원 조회 실패 — 겹침 판정 근거 없음');
    });

    testWidgets('WH-11e 320/2.0 렌더 — 넘침·말줄임 0 · 문구 전문', (t) async {
      await _pumpHome(t, _reads(apps: [conf], tos: [overlapA, overlapB, night]), width: 320, height: 7000, scale: 2.0);
      await pick(t);
      expect(t.takeException(), isNull);
      final note = find.descendant(of: _jobs, matching: findVisibleText(shownNote));
      expect(note, findsOneWidget);
      final rp = t.renderObject<RenderParagraph>(find.descendant(of: note, matching: find.byType(RichText)));
      expect(rp.didExceedMaxLines, isFalse);
      expect(rp.textScaler, const TextScaler.linear(2.0));
    });
  });

  for (final scale in const [1.0, 2.0]) {
    testWidgets('WH-5 320/$scale 혼합 선택 — 넘침·말줄임·축소·숫자 분리 0 · receiver ≥48 · 마지막 날짜 도달', (t) async {
      final sem = t.ensureSemantics();
      await _pumpHome(t, _reads(apps: _mixedApps()), width: 320, height: 6000, scale: scale);
      expect(t.takeException(), isNull);
      await t.tap(_cell('11월 28일 토요일'));
      await _settle(t);
      expect(t.takeException(), isNull, reason: '선택 뒤 넘침 0');
      final paras = find.descendant(of: _area, matching: find.byType(RichText)).evaluate().map((e) => e.renderObject! as RenderParagraph);
      var n = 0;
      for (final rp in paras) {
        final txt = rp.text.toPlainText();
        if (txt.isEmpty || txt.runes.first >= 0xE000) continue; // 아이콘 글리프
        n++;
        expect(rp.overflow == TextOverflow.ellipsis, isFalse, reason: '말줄임 0: $txt');
        expect(rp.didExceedMaxLines, isFalse, reason: txt);
        expect(rp.textScaler, TextScaler.linear(scale), reason: '축소 0: $txt');
      }
      expect(n, greaterThan(10));
      for (final p in _dayPrefixes) {
        final r = t.getRect(_cell(p));
        expect(r.width >= 48 && r.height >= 48, isTrue, reason: '$p receiver ${r.size}');
        // 날짜 숫자 한 줄(두 자리 분리 0)
        final num = find.descendant(of: _cell(p), matching: find.text(p.split(' ')[1].replaceAll('일', '')));
        expect(num, findsOneWidget, reason: p);
        final rp = t.renderObject<RenderParagraph>(find.descendant(of: num, matching: find.byType(RichText)));
        final s = rp.text.toPlainText();
        final tops = rp.getBoxesForSelection(TextSelection(baseOffset: 0, extentOffset: s.length)).map((b) => b.top.round()).toSet();
        expect(tops.length, 1, reason: '$p 숫자 한 줄');
      }
      expect(find.descendant(of: _area, matching: findVisibleText('$_longBiz · 분류')), findsOneWidget, reason: '긴 사업장명 전문');
      // 가로 스크롤이 생기면 마지막 날짜까지 도달해 선택
      await t.ensureVisible(_cell('12월 2일 수요일'));
      await _settle(t);
      await t.tap(_cell('12월 2일 수요일'));
      await _settle(t);
      expect(t.getSemantics(_cell('12월 2일 수요일')), containsSemantics(isSelected: true));
      expect(findVisibleText('12월 2일 일자리 보기'), findsOneWidget);
      expect(t.takeException(), isNull);
      sem.dispose();
    });
  }

  group('WH-6 내 일정 탭 — 홈 선택일 소비', () {
    // MyScheduleScreen 은 실제 시계(DateTime.now)를 쓴다 — 목표 날짜를 그 기준으로 고른다.
    final now = DateTime.now();
    final other = DateTime(now.year, now.month + 2, 15); // 다른 달
    final same = DateTime(now.year, now.month, now.day == 10 ? 11 : 10); // 같은 달 다른 날
    DateTime key(DateTime d) => DateTime.utc(d.year, d.month, d.day); // 홈이 넘기는 KST 달력일 키
    ApplicationModel app(String id, DateTime d, String status, String biz) => ApplicationModel(
          id: id, toId: 'to_$id', uid: 'u1', businessId: 'b_$id', businessName: biz, toTitle: '공고 $id',
          status: status, selectedWorkType: '피킹', startTime: '09:00', endTime: '18:00', wage: 12000, wageType: 'hourly',
          workDate: DateTime.utc(d.year, d.month, d.day).subtract(const Duration(hours: 9)),
          appliedAt: now.subtract(const Duration(days: 1)), applicationType: AppType.shortTerm,
          confirmedAt: status == AppStatus.pending ? null : now.subtract(const Duration(days: 1)));
    final apps = [
      app('o1', other, AppStatus.confirmed, '먼달 확정 사업장'),
      app('o2', other, AppStatus.pending, '먼달 대기 사업장'),
      app('s1', same, AppStatus.confirmed, '이달 확정 사업장'),
    ];

    testWidgets('WH-6a 이전 `대기` 필터 · 다른 달 · 같은 달 · 1회 소비 · 이미 열린 탭', (t) async {
      t.view.physicalSize = const Size(390, 2400);
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.reset);
      final months = <String>[];
      var clears = 0;
      final hostKey = GlobalKey<_HostState>();
      await t.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<UserProvider>.value(value: _W(_newWorker())),
          ChangeNotifierProvider<NotificationProvider>(create: (_) => NotificationProvider()),
        ],
        child: MaterialApp(
          home: _Host(
            key: hostKey,
            onClear: () => clears++,
            child: MyScheduleScreen(
              reads: MyScheduleReads(
                myApplications: (_) async => apps,
                myMonthlyAttendances: ({required String userId, required int year, required int month}) async {
                  months.add('$year-$month');
                  return const <AttendanceModel>[];
                },
                myAvailability: (_) async => null,
                invitePreference: (_) async => const InviteRegionPreference(),
              ),
            ),
          ),
        ),
      ));
      for (var i = 0; i < 20; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
      expect(t.takeException(), isNull);
      // 이미 열린 탭에서 사용자가 `대기` 필터를 골라 둔 상태
      await t.tap(find.text('대기').first);
      await _settle(t);
      // 홈 선택일(다른 달) 도착
      hostKey.currentState!.send(key(other));
      for (var i = 0; i < 20; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
      expect(clears, 1, reason: '1회 소비');
      expect(months, contains('${other.year}-${other.month}'), reason: '다른 달을 새로 읽는다');
      expect(find.text('먼달 확정 사업장'), findsOneWidget, reason: '필터 ALL — 확정도 보인다');
      expect(find.text('먼달 대기 사업장'), findsOneWidget, reason: '필터 ALL — 지원 중도 보인다');
      // 같은 달 다른 날 — 같은 탭에 다시 도착
      hostKey.currentState!.send(key(same));
      for (var i = 0; i < 20; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
      expect(clears, 2);
      expect(find.text('이달 확정 사업장'), findsOneWidget, reason: '같은 달 선택일 당일 목록');
      expect(find.text('먼달 확정 사업장'), findsNothing);
      expect(t.takeException(), isNull);
    });
  });

  group('WH-7 root 경로(소스 계약)', () {
    test('WH-7 일정 날짜는 일자리 날짜와 따로 · 이미 일정 탭이면 탭 스택 비움 · push 0', () {
      final root = File('lib/screens/user/user_root_screen.dart').readAsStringSync();
      final a = root.indexOf('void _switchToScheduleDate(DateTime date) {');
      expect(a, greaterThan(0));
      final fn = root.substring(a, root.indexOf('\n  }\n', a));
      expect(fn, contains('if (_currentIndex == 2) {'));
      expect(fn, contains('_popTab(2);'));
      expect(fn, contains('_currentIndex = 2;'));
      expect(fn, contains('_pendingScheduleDate = date;'));
      expect(fn.contains('_pendingJobDate'), isFalse, reason: '일자리 날짜와 섞지 않는다');
      expect(fn.contains('Navigator'), isFalse);
      expect(root, contains('switchToScheduleDate: _switchToScheduleDate,'));
      expect(root, contains('pendingScheduleDate: _pendingScheduleDate,'));
      expect(root, contains('clearPendingScheduleDate: _clearPendingScheduleDate,'));
      final home = File('lib/screens/user/user_home_screen.dart').readAsStringSync();
      expect(home.contains('_buildThisWeekSchedule'), isFalse);
      expect(home.contains('MaterialPageRoute(builder: (_) => const MyScheduleScreen'), isFalse);
    });
  });
}

/// root 처럼 pendingScheduleDate 를 넘겨 주고 소비(clear)를 받는 대역.
class _Host extends StatefulWidget {
  const _Host({super.key, required this.child, required this.onClear});
  final Widget child;
  final VoidCallback onClear;
  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  DateTime? _pending;
  void send(DateTime d) => setState(() => _pending = d);
  @override
  Widget build(BuildContext context) => UserTabScope(
        switchToTab: (_) {},
        switchToTabWithDate: (_, __) {},
        pendingJobDate: null,
        clearPendingJobDate: () {},
        pendingScheduleMonth: null,
        clearPendingScheduleMonth: () {},
        switchToScheduleNow: () {},
        pendingScheduleDate: _pending,
        clearPendingScheduleDate: () {
          widget.onClear();
          setState(() => _pending = null);
        },
        child: widget.child,
      );
}
