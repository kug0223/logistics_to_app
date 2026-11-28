// [S080 U1 → U6 → U7 보강 시험 후보 r2 · 2026-11-17 · records 정확 패키지(후속91 → 후속92 개정) · **적용 · 실행 0**]
//   r1(4dc1d802 · 보존) 대비: F92-1 재시도 찾기를 표면별 명시 경계 안으로 한정(밖으로 올라가지 않음) ·
//     F92-3 U7-2 행 · U7-3/4 정상 빈 수입 안내 · U7-6 다른 읽기 +1 · 계약해지 모름 해제 직접 단언 추가 · 공개 이름 11 그대로.
//   적용 시 위치(제안): test/du1_s080_u167_test.dart (신규 파일 · 기존 시험 · 제품 편집 0)
//   기준: 홈 lib/screens/user/user_home_screen.dart 141bf0a6 · 읽기 경계 user_home_reads.dart ca11883d
//   하네스: test/user_home_content_render_test.dart 58d80116 의 :46–128 · :130–159 · :232–242 · :333–379 · :444–470 · :553–563 을
//     **바이트 그대로** 옮겼다(조립 방법 · 대조는 패키지 보고 §6). 그 밖은 이 파일의 새 부분이다.
//   시계: 기존 하네스와 같다 — fixture 날짜는 실행일 KST 에서 파생하고 화면 시계는 실행일 KST 10:00 고정(:113 · :122).
//     공용 달력 · 제품 seam 변경 0. KST 1일의 지난달 꼬리 읽기는 호출 수에서 따로 센다(_Reads).
//   env · skip · 날짜 gate 없음(D306 F7 의 DU306_PHASE/DAY/RUN gate 를 가져오지 않는다).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ALfit/models/core/slot_model.dart';
import 'package:ALfit/models/core/application_model.dart';
import 'package:ALfit/models/core/attendance_model.dart';
import 'package:ALfit/models/core/business_model.dart';
import 'package:ALfit/models/core/employment_contract_model.dart';
import 'package:ALfit/models/core/id_card_access_request_model.dart';
import 'package:ALfit/models/core/renewal_proposal_model.dart';
import 'package:ALfit/models/core/to_model.dart';
import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/models/core/user_region.dart';
import 'package:ALfit/providers/notification_provider.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/utils/format_helper.dart';
import 'package:ALfit/screens/user/user_home_reads.dart';
import 'package:ALfit/screens/user/user_home_screen.dart';
import 'package:ALfit/services/payroll_correction_service.dart';
import 'support/checkin_contract_fixture.dart';
import 'support/visible_text.dart';

// ── 아래 원본 :46–159(_FakeApp · _FakeCore · _UserProviderDouble · 날짜 · 시계 · _biz · _shortTerm) · :232–242(_business) 는
//    user_home_content_render_test.dart 에서 그대로 옮긴 하네스다 ──
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

/// 지원자 provider — 역할은 USER 고정. 관리자 capability 를 덧씌우지 않는다.
class _UserProviderDouble extends UserProvider {
  _UserProviderDouble({this.uid = 'u1', this.totalWorkDays = 0});

  String uid;

  /// [R7-P2 잔여] 경력이 0 이면 홈은 '첫 근무부터…' 안내를 띄우고
  ///   '근무 기록 보기' 링크를 만들지 않는다. 기본값은 기존과 같다.
  final int totalWorkDays;
  static const homeRegion =
      UserRegion(province: '서울특별시', city: '강남구', district: '역삼동');

  @override
  UserModel? get currentUser => UserModel(
        uid: uid,
        username: uid,
        name: '김근로',
        email: '$uid@alfit.local',
        role: UserRole.USER,
        homeRegion: homeRegion,
        accountStatus: 'active',
        passVerifiedAt: DateTime.now().subtract(const Duration(days: 30)),
        totalWorkDays: totalWorkDays,
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

  /// 계정 전환을 흉내 낸다 — 늦은 응답 가드가 uid 를 보는지 확인용.
  void switchAccount(String next) {
    uid = next;
    notifyListeners();
  }
}

// ── 오늘에서 파생한 날짜 ────────────────────────────────────────
final DateTime _today = FormatHelper.toKstDate(DateTime.now());
DateTime _day(int offset) => _today.add(Duration(days: offset));

/// [DEVICE-MISMATCH-FIX] 화면 시계를 **오늘 KST 10:00** 으로 고정한다.
///   예전에는 시계를 주입하지 않아 화면이 실제 시각을 썼다. 홈 Hero 가
///   예정 시간이 끝난 미출근 근무에 `출근하기`를 권하지 않게 바뀐 뒤로,
///   기본 단기 근무(09:00~18:00)가 **18시 이후 실행**에서는 끝난 근무가 되어
///   이 파일의 `출근하기`·제목 기대가 실행 시각에 따라 갈렸다(10-20 18:02 실측 9건).
///   이 파일이 뜻하는 상황은 '오늘 근무가 진행 중인 시간'이다.
final DateTime _clock = () {
  final k = DateTime.now().toUtc().add(const Duration(hours: 9));
  return DateTime.utc(k.year, k.month, k.day, 10)
      .subtract(const Duration(hours: 9));
}();

const _biz = 'biz1';

/// 단기(슬롯) 지원 — `workDate` 가 실제 근무일이다.
ApplicationModel _shortTerm({
  String id = 'short1',
  required DateTime workDate,
  String status = AppStatus.confirmed,
  String businessName = '강남 물류센터',
  String workType = '피킹',
  String start = '09:00',
  String end = '18:00',
  int wage = 12000,
  DateTime? confirmedAt,
  String? terminationStatus,
}) =>
    ApplicationModel(
      id: id,
      toId: 'to_$id',
      uid: 'u1',
      businessId: _biz,
      businessName: businessName,
      toTitle: '단기 공고',
      status: status,
      selectedWorkType: workType,
      startTime: start,
      endTime: end,
      wage: wage,
      workDate: workDate,
      confirmedAt: confirmedAt,
      terminationStatus: terminationStatus,
      appliedAt: _day(-3),
    );

BusinessModel _business() => BusinessModel(
      id: _biz,
      name: '강남 물류센터',
      ownerId: 'admin1',
      businessNumber: '000-00-00000',
      address: '서울특별시 강남구 테헤란로 1',
      category: '물류',
      subCategory: '창고',
      isApproved: true,
      createdAt: _day(-200),
    );

// ══════════════════════════════════════════════════════════
// [S080 U1/U6/U7] 여기부터 이 파일의 새 부분 — 읽기 경계 · 소유 범위 찾기 · 요약 값
// ══════════════════════════════════════════════════════════

/// 실패를 **지금 실패해야 하는지 스위치**로 주는 경계. 읽기마다 호출 수를 센다.
///   홈의 재시도 · resume 은 홈 전체 재조회(`_loadHomeData`)라 실패한 읽기만이 아니라 1라운드 읽기가 모두 한 번씩 더 불린다.
///   그 사실도 호출 수로 단언한다 — 서류 보완 재시도(UHR-49 "그 읽기만")와 다른 경로다.
class _Reads {
  _Reads({this.apps = const [], this.tos = const []});

  List<ApplicationModel> apps;
  List<TOModel> tos;
  bool appsFail = false;
  bool attsFail = false;
  bool tosFail = false;

  /// 사업장 문서 읽기(추천 카드 이미지용 · 홈 :725–736): 'ok' = 문서 · 'throw' = 예외 · 'null' = 문서 없음.
  String biz = 'ok';
  final Map<String, int> calls = {};
  final List<String> bizIds = [];

  void _hit(String k) => calls[k] = (calls[k] ?? 0) + 1;
  int n(String k) => calls[k] ?? 0;

  UserHomeReads build() => UserHomeReads(
        myApplications: (uid) async {
          _hit('apps');
          if (appsFail) throw Exception('apps read failed');
          return apps;
        },
        myMonthlyAttendances: (
            {required String userId, required int year, required int month}) async {
          // KST 1일에는 지난달 꼬리를 한 번 더 읽는다(홈 :567 · :591) — 이번 달 호출만 'atts' 로 센다.
          final k = FormatHelper.toKstDate(_clock);
          _hit(year == k.year && month == k.month ? 'atts' : 'attsTail');
          if (attsFail) throw Exception('attendance read failed');
          return const <AttendanceModel>[];
        },
        publishedTOs: () async {
          _hit('tos');
          if (tosFail) throw Exception('to read failed');
          return tos;
        },
        pendingIdCardRequests: (uid) async {
          _hit('id');
          return const <IdCardAccessRequestModel>[];
        },
        myRenewalProposals: () async {
          _hit('renewal');
          return const <RenewalProposalModel>[];
        },
        businessById: (id) async {
          _hit('biz');
          bizIds.add(id);
          if (biz == 'throw') throw Exception('business read failed');
          if (biz == 'null') return null;
          return _business();
        },
        slotsForTO: (toId) async => const <SlotModel>[],
        invalidatePublishedTOsCache: () {},
        documentCorrections: () async {
          _hit('corr');
          return DocumentCorrectionSurface.empty;
        },
        // [CONTRACT-DISPATCH-B4] 기존 하네스와 같은 전제 — 지원 근무마다 양측 서명 완료 계약(지원 읽기 실패면 빈 목록).
        myContracts: (uid) async {
          _hit('contracts');
          return appsFail
              ? const <EmploymentContractModel>[]
              : completedContractsFor(apps);
        },
      );
}

/// 검토 중 지원 한 건 — 이번 주 밖(오늘+10일 이후)이라 주간 · 오늘 약속 표면과 섞이지 않는다.
ApplicationModel _pend(String id, int day, String businessName) => _shortTerm(
    id: id, workDate: _day(day), status: AppStatus.pending, businessName: businessName);
List<ApplicationModel> _two() => [_pend('pa', 10, '가나 센터'), _pend('pb', 12, '다라 센터')];

const _kStale = '최신 정보를 불러오지 못해 이전 내용을 보여드려요';
const _kAppsErr = '지원 현황을 불러오지 못했어요';
const _kAppsEmpty = '아직 지원한 일자리가 없어요';
const _kTermUnknown = '계약해지 요청을 확인하지 못했어요';
const _kIncomeErr = '이번 달 근무 기록을 불러오지 못했어요 · 다시 시도';
const _kOvernightUnknown = '어제 근무의 퇴근 여부를 확인하지 못했어요';
const _kPostingsErr = '공고를 불러오지 못했어요';
// [판정285 갱신 2026-11-26] 정상0 안내는 큰 약속 카드에서 통합 날짜 영역의 짧은 안내(keepWords)로 옮겨졌다 —
//   같은 조건(로딩 끝·지원 조회 성공·B/A 없음) · 보이는 글자 기준으로 찾는다(findVisibleText). 0/1 기대는 그대로.
const _kPromiseEmpty = '오늘 확정된 근무가 없어요';
// [F92-3] 정상 빈 수입 안내 — 홈은 keepWords 로 그린다(:2878) → 보이는 글자 기준으로 찾는다(findVisibleText).
const _kIncomeEmpty = '아직 표시할 수입 금액이 없어요';

/// 가장 가까운 조상 하나(자기 제외) — 전역 `.first` 대신 소유 관계를 따라 올라간다.
Element? _nearest(Element from, bool Function(Widget w) test) {
  Element? hit;
  from.visitAncestorElements((a) {
    if (test(a.widget)) {
      hit = a;
      return false;
    }
    return true;
  });
  return hit;
}

Finder _el(Element e) => find.byElementPredicate((x) => identical(x, e));

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// e 가 anc 의 (진)자손인가 — 조상 사슬을 따라 올라가며 identical 로 비교한다.
bool _isUnder(Element e, Element anc) {
  var found = false;
  e.visitAncestorElements((a) {
    if (identical(a, anc)) {
      found = true;
      return false;
    }
    return true;
  });
  return found;
}

/// [U7 · F92-1] 재시도 소유 경계의 종류. owner 에서 가장 가까운 그 종류 조상 **하나**만 경계로 쓴다.
///   self = owner 글자 자체가 재시도다(수입 행 홈 :2978 — 글자가 '…· 다시 시도').
enum _Scope { row, column, self }

/// [U7] 그 표면이 **소유한** `다시 시도` 하나를 누른다 — F92-1: 명시 경계 밖으로 올라가지 않는다.
///   1. owner 문구는 정확 1개.
///   2. 경계 = self 면 owner 글자 · row/column 이면 owner 에서 가장 가까운 Row/Column **하나**(그 위로 더 찾지 않는다).
///   3. 재시도 = 경계 안 `다시 시도` 정확 1개(self 는 owner 글자). 0개면 그 자리에서 실패 — 상위 다른 카드의 재시도로 넘어가지 않는다.
///   4. 수신자 = 재시도 글자에서 가장 가까운 rcvType(GestureDetector 또는 TextButton) 조상.
///      수신자가 경계 밖(조상)이면 그 수신자 아래 재시도가 정확 1개(선택한 그 글자)이고 owner 를 품어야 한다 — 여러 표면을 감싼 수신자는 실패.
///   5. 수신자 콜백 non-null — 탭 직전(로드가 끝난 뒤)의 활성만 본다. 로딩 중 비활성 동작은 이 시험이 검증하지 않는다.
Future<void> _tapOwnedRetry(
    WidgetTester tester, Finder owner, String surface, _Scope scope, Type rcvType) async {
  expect(owner, findsOneWidget, reason: '$surface: 소유 문구가 정확 1개가 아니다');
  final ownerEl = owner.evaluate().single;
  final Element boundary;
  final Element retryEl;
  if (scope == _Scope.self) {
    expect((ownerEl.widget as Text).data, contains('다시 시도'), reason: '$surface: 자기 글자에 다시 시도가 없다');
    boundary = ownerEl;
    retryEl = ownerEl;
  } else {
    final b = _nearest(ownerEl, (w) => scope == _Scope.row ? w is Row : w is Column);
    expect(b, isNotNull, reason: '$surface: owner 를 품는 ${scope.name} 경계가 없다');
    boundary = b!;
    final hits =
        find.descendant(of: _el(boundary), matching: findVisibleText('다시 시도')).evaluate().toList();
    expect(hits.length, 1,
        reason: '$surface: 경계(${scope.name}) 안 다시 시도 ${hits.length}개 — 0 이면 자기 재시도 없음(밖으로 찾지 않는다) · 2 이상이면 섞임');
    retryEl = hits.single;
  }
  final rcvOrNull = _nearest(retryEl, (w) => w.runtimeType == rcvType);
  expect(rcvOrNull, isNotNull, reason: '$surface: 다시 시도 위에 $rcvType 수신자가 없다');
  final rcv = rcvOrNull!;
  if (!_isUnder(rcv, boundary)) {
    bool isRetry(Element e) =>
        identical(e, retryEl) || (e.widget is Text && (e.widget as Text).data == '다시 시도');
    final under =
        find.descendant(of: _el(rcv), matching: find.byElementPredicate(isRetry)).evaluate().toList();
    expect(under.length, 1, reason: '$surface: 경계 밖 수신자 아래 재시도 ${under.length}개 — 여러 표면을 감쌌다');
    expect(identical(under.single, retryEl), isTrue, reason: '$surface: 수신자 아래 재시도가 선택한 글자가 아니다');
    expect(_isUnder(ownerEl, rcv), isTrue, reason: '$surface: 경계 밖 수신자가 owner 를 품지 않는다');
  }
  final w = rcv.widget;
  final live = (w is GestureDetector && w.onTap != null) || (w is TextButton && w.onPressed != null);
  expect(live, isTrue, reason: '$surface: 탭 수신자가 비활성이다($rcvType)');
  final target = _el(retryEl);
  await tester.ensureVisible(target);
  await tester.pump(const Duration(milliseconds: 200));
  await tester.tap(target);
  await _settle(tester);
}

/// 지원 현황 3칸 요약 값 — 라벨(semanticsLabel 정확)에서 가장 가까운 Row 안에서만 읽는다(D306 F7 :1274–1286 과 같은 범위 잡기).
Map<String, String> _stats() {
  Finder label(String l, {Finder? within}) {
    final f = find.byWidgetPredicate((w) => w is Text && w.semanticsLabel == l);
    return within == null ? f : find.descendant(of: within, matching: f);
  }

  final anchor = label('검토 중');
  expect(anchor, findsOneWidget, reason: '요약 라벨 검토 중이 정확 1개가 아니다');
  final row = _nearest(anchor.evaluate().single, (w) => w is Row);
  expect(row, isNotNull, reason: '요약 Row 없음');
  final out = <String, String>{};
  for (final l in const ['검토 중', '확정', '계약 대기']) {
    final le = label(l, within: _el(row!));
    expect(le, findsOneWidget, reason: '요약 라벨 $l');
    final col = _nearest(le.evaluate().single, (w) => w is Column);
    expect(col, isNotNull, reason: '요약 $l Column 없음');
    final vals = find
        .descendant(
            of: _el(col!),
            matching: find.byWidgetPredicate((w) => w is Text && w.semanticsLabel == null))
        .evaluate()
        .map((e) => (e.widget as Text).data ?? '')
        .toList();
    expect(vals.length, 1, reason: '요약 $l 값 수 ${vals.length}');
    out[l] = vals.single;
  }
  return out;
}

// ── 아래 :333–379(_pump) · :444–470(_recTo) 는 user_home_content_render_test.dart 에서 그대로 옮긴 하네스다 ──
Future<void> _pump(
  WidgetTester tester, {
  required UserHomeReads reads,
  Size size = const Size(390, 2200),
  double textScale = 1.0,
  _UserProviderDouble? provider,
  NavigatorObserver? observer,
}) async {
  final isolationKey = UniqueKey();
  // 같은 테스트에서 두 번째 화면을 그리기 전에 앞 화면을 **내린다** —
  //   남은 State·타이머가 다음 시나리오의 로드와 섞이지 않게 한다.
  if (tester.binding.rootElement != null) {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 50));
  }
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<UserProvider>.value(
            value: provider ?? _UserProviderDouble()),
        ChangeNotifierProvider<NotificationProvider>(
            create: (_) => NotificationProvider()),
      ],
      child: MaterialApp(
        navigatorObservers: observer == null ? const [] : [observer],
        builder: (ctx, child) => MediaQuery(
          data: MediaQuery.of(ctx)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          // 같은 타입 화면을 연달아 pump 하면 State 가 재사용돼 시나리오가
          // 섞인다 — 매 pump 를 새 State 로 격리한다.
          //   키는 **pump 당 하나**다. builder 안에서 만들면 매 rebuild 마다
          //   State 가 버려져 로드가 처음부터 다시 돈다.
          child: KeyedSubtree(key: isolationKey, child: child!),
        ),
        home: UserHomeScreen(reads: reads, clock: () => _clock),
      ),
    ),
  );
  // pumpAndSettle 은 쓰지 않는다 — 홈에 멈추지 않는 애니메이션이 있다.
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// [R7-P2 잔여] 추천 카드용 TO — 내 city 이고 60일 안에 슬롯 날짜가 있어야
///   추천 목록에 들어간다(`_getRecommendedTos`).
TOModel _recTo({String id = 'toRec', String title = '물류센터 상하차'}) {
  final d = _day(4);
  final key = '${d.year}-${d.month.toString().padLeft(2, "0")}-${d.day.toString().padLeft(2, "0")}';
  return TOModel(
    id: id,
    businessId: _biz,
    businessName: '강남 물류센터',
    businessCity: _UserProviderDouble.homeRegion.city,
    type: 'flex',
    title: title,
    creatorUID: 'admin1',
    status: TOStatus.active,
    deadlineType: 'NONE',
    hoursBeforeStart: 0,
    workDetails: const [],
    slotDateKeys: [key],
    totalRequired: 4,
    totalConfirmed: 0,
    totalPending: 0,
    isPublished: true,
    publishMode: 'immediate',
    createdAt: _day(-2),
    statusUpdatedAt: _day(-2),
  );
}

void main() {
  setUp(() {
    // 투어를 완료로 둔다 — 아니면 첫 프레임에 투어 화면이 덮는다.
    SharedPreferences.setMockInitialValues({'tour_completed_user_home': true});
  });

  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
    await initializeDateFormatting('ko_KR', null);
  });

  // ══════════════════════════════════════════════════════════
  // U1 — 추천 카드 이미지용 사업장 문서 읽기(홈 :725–736)가 throw 하면 바깥 catch(:737–746)로 간다
  //   [현행 관측] 단언은 **지금 동작**이다. 제품 기대(이미지 읽기 실패는 홈 실패가 아니다)는 패키지 보고 §3 에 따로 적었다.
  //   제품 수정이 승인되면 U1-1 · U1-2 의 [현행 관측] 단언은 같은 fixture 로 기대 단언이 된다.
  // ══════════════════════════════════════════════════════════

  testWidgets('U1-1 [현행 관측] 지원이 있을 때 사업장 읽기 실패는 stale 띠와 계약해지 모름으로 번진다', (tester) async {
    final r = _Reads(apps: _two(), tos: [_recTo()])..biz = 'throw';
    await _pump(tester, reads: r.build());

    // 도달: 1라운드 성공 뒤 추천 상위 공고의 사업장 id 로 정확 1회
    expect(r.n('apps'), 1);
    expect(r.bizIds, [_biz]);
    // 1라운드 값은 이번 응답이다 — 숫자 · 행은 그대로 그려진다
    expect(_stats(), {'검토 중': '2', '확정': '0', '계약 대기': '0'});
    expect(find.text('가나 센터 · 피킹'), findsOneWidget);
    expect(find.text('다라 센터 · 피킹'), findsOneWidget);
    // [현행 관측] 이미지용 읽기 하나가 홈 실패 상태로 번진다(PARTIAL 표면 · 계약해지 모름 · 약속 0 숨김)
    expect(find.text(_kStale), findsOneWidget);
    expect(find.text(_kTermUnknown), findsOneWidget);
    expect(findVisibleText(_kPromiseEmpty), findsNothing);
    expect(find.text(_kAppsErr), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('U1-2 [현행 관측] 지원 0건 성공이어도 사업장 읽기 실패면 지원 현황 오류 카드가 선다', (tester) async {
    final r = _Reads(tos: [_recTo()])..biz = 'throw';
    await _pump(tester, reads: r.build());

    expect(r.n('apps'), 1);
    expect(r.bizIds, [_biz]);
    // [현행 관측] 지원 읽기는 성공(0건)했지만 화면은 못 불러왔다고 말한다 — 이전 값이 없어 stale 이 아니라 ERROR 표면이다
    expect(find.text(_kAppsErr), findsOneWidget);
    expect(find.text(_kAppsEmpty), findsNothing);
    expect(find.text(_kStale), findsNothing);
    expect(find.text(_kTermUnknown), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('U1-3 사업장 읽기 실패 뒤 stale 띠 다시 시도 → 사업장 읽기 성공이면 stale 과 계약해지 모름이 걷힌다', (tester) async {
    final r = _Reads(apps: _two(), tos: [_recTo()])..biz = 'throw';
    await _pump(tester, reads: r.build());
    expect(find.text(_kStale), findsOneWidget);
    expect(find.text(_kTermUnknown), findsOneWidget);

    r.biz = 'ok';
    await _tapOwnedRetry(tester, find.text(_kStale), 'stale 띠(U1)', _Scope.row, GestureDetector);

    expect(r.n('apps'), 2);
    expect(r.bizIds, [_biz, _biz]);
    expect(find.text(_kStale), findsNothing);
    expect(find.text(_kTermUnknown), findsNothing);
    expect(findVisibleText(_kPromiseEmpty), findsOneWidget);
    expect(_stats(), {'검토 중': '2', '확정': '0', '계약 대기': '0'});
    expect(tester.takeException(), isNull);
  });

  testWidgets('U1-4 [대조] 사업장 문서가 없으면(null) 실패가 아니다 — stale 과 계약해지 모름이 없다', (tester) async {
    final r = _Reads(apps: _two(), tos: [_recTo()])..biz = 'null';
    await _pump(tester, reads: r.build());

    expect(r.bizIds, [_biz]);
    expect(_stats(), {'검토 중': '2', '확정': '0', '계약 대기': '0'});
    expect(findVisibleText(_kPromiseEmpty), findsOneWidget);
    expect(find.text(_kStale), findsNothing);
    expect(find.text(_kTermUnknown), findsNothing);
    expect(tester.takeException(), isNull);
  });

  // ══════════════════════════════════════════════════════════
  // U6 — 성공 → resume 재조회 실패 → 이전 숫자 · 행 보존 + stale 띠
  //   D306 F7(du1_user_home_306_test.dart :1262) 의 행동 부분을 날짜 · env 무관한 일반 회귀로 둔다.
  //   F7 의 시각 단언(띠 바탕 · 아이콘 · brand · 48 · PNG)은 가져오지 않는다.
  //   resume 은 실제 시계 30초 쿨다운(홈 :465–471) 때문에 시험 하나에서 한 번만 쓴다.
  // ══════════════════════════════════════════════════════════

  testWidgets('U6-1 첫 로드 성공 → resume 재조회 실패 1회 → 이전 숫자와 행을 지키고 stale 띠를 단다', (tester) async {
    final r = _Reads(apps: _two());
    await _pump(tester, reads: r.build());

    final pre = _stats();
    expect(pre, {'검토 중': '2', '확정': '0', '계약 대기': '0'});
    expect(find.text('가나 센터 · 피킹'), findsOneWidget);
    expect(find.text('다라 센터 · 피킹'), findsOneWidget);
    expect(find.text(_kStale), findsNothing);
    final a0 = r.n('apps');

    r.appsFail = true;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await _settle(tester);

    expect(r.n('apps'), a0 + 1, reason: 'resume 재조회는 정확 1회');
    expect(_stats(), pre, reason: '실패한 재조회가 숫자를 0으로 덮지 않는다');
    expect(find.text('가나 센터 · 피킹'), findsOneWidget);
    expect(find.text('다라 센터 · 피킹'), findsOneWidget);
    expect(find.text(_kStale), findsOneWidget);
    expect(find.text(_kAppsErr), findsNothing);
    expect(find.text(_kAppsEmpty), findsNothing);
    expect(tester.takeException(), isNull);
  });

  // ══════════════════════════════════════════════════════════
  // U7 — 서류 외 재시도 회복: 주입 실패 도달 → 그 표면 소유 다시 시도 탭 → 읽기 횟수 → 성공 응답 반영 · 오류 해제
  //   서류 보완 재시도(UHR-49 · 50)는 이미 있고 여기서 세지 않는다.
  //   표면마다 수신자와 비활성 조건이 따로 있다(홈 :2501 · :3494 · :2970 · :1390 · :4441 · :2532).
  // ══════════════════════════════════════════════════════════

  testWidgets('U7-1 지원 현황 오류 카드의 다시 시도 → 지원 읽기 성공 응답이 반영된다', (tester) async {
    final r = _Reads(apps: [_pend('pa', 10, '가나 센터')])..appsFail = true;
    await _pump(tester, reads: r.build());
    expect(r.n('apps'), 1);
    expect(find.text(_kAppsErr), findsOneWidget);
    final atts0 = r.n('atts');
    final tos0 = r.n('tos');

    r.appsFail = false;
    await _tapOwnedRetry(tester, find.text(_kAppsErr), '지원 현황 오류 카드', _Scope.column, GestureDetector);

    expect(r.n('apps'), 2);
    expect(r.n('atts'), atts0 + 1, reason: '재시도는 홈 전체 재조회다');
    expect(r.n('tos'), tos0 + 1, reason: '재시도는 홈 전체 재조회다');
    expect(find.text(_kAppsErr), findsNothing);
    expect(find.text(_kTermUnknown), findsNothing);
    expect(_stats(), {'검토 중': '1', '확정': '0', '계약 대기': '0'});
    expect(find.text('가나 센터 · 피킹'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('U7-2 계약해지 확인 못함 카드의 다시 시도 → 지원 읽기 성공이면 카드가 걷힌다', (tester) async {
    final r = _Reads(apps: [_pend('pa', 10, '가나 센터')])..appsFail = true;
    await _pump(tester, reads: r.build());
    expect(r.n('apps'), 1);
    expect(find.text(_kTermUnknown), findsOneWidget);
    expect(find.text(_kAppsErr), findsOneWidget);
    final atts0 = r.n('atts');

    r.appsFail = false;
    await _tapOwnedRetry(tester, find.text(_kTermUnknown), '계약해지 확인 못함 카드', _Scope.row, GestureDetector);

    expect(r.n('apps'), 2);
    expect(r.n('atts'), atts0 + 1, reason: '재시도는 홈 전체 재조회다');
    expect(find.text(_kTermUnknown), findsNothing);
    expect(find.text(_kAppsErr), findsNothing);
    expect(_stats(), {'검토 중': '1', '확정': '0', '계약 대기': '0'});
    expect(find.text('가나 센터 · 피킹'), findsOneWidget); // [F92-3] 성공 응답의 행
    expect(tester.takeException(), isNull);
  });

  testWidgets('U7-3 수입 행의 다시 시도 → 근태 읽기 성공이면 확인 못함이 걷힌다', (tester) async {
    final r = _Reads()..attsFail = true;
    await _pump(tester, reads: r.build());
    expect(r.n('atts'), 1);
    expect(find.text(_kIncomeErr), findsOneWidget);
    expect(find.text('확인 못함'), findsWidgets);
    expect(findVisibleText(_kIncomeEmpty), findsNothing, reason: '못 읽은 달은 빈 수입이라고 말하지 않는다(사전)');
    final apps0 = r.n('apps');

    r.attsFail = false;
    await _tapOwnedRetry(tester, find.text(_kIncomeErr), '수입 행', _Scope.self, GestureDetector);

    expect(r.n('atts'), 2);
    expect(r.n('apps'), apps0 + 1, reason: '재시도는 홈 전체 재조회다');
    expect(find.text(_kIncomeErr), findsNothing);
    expect(find.text('확인 못함'), findsNothing);
    expect(find.text(_kOvernightUnknown), findsNothing);
    // [F92-3] 빈 근태 성공 응답의 긍정 표면 — 정상 빈 수입 안내(금액 · 비어 있지 않은 근태 반영은 이 시험이 보지 않는다)
    expect(findVisibleText(_kIncomeEmpty), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('U7-4 어제 퇴근 확인 못함 카드의 다시 시도 → 근태 읽기 성공이면 카드가 걷힌다', (tester) async {
    final r = _Reads()..attsFail = true;
    await _pump(tester, reads: r.build());
    expect(r.n('atts'), 1);
    expect(find.text(_kOvernightUnknown), findsOneWidget);
    expect(findVisibleText(_kIncomeEmpty), findsNothing, reason: '못 읽은 달은 빈 수입이라고 말하지 않는다(사전)');
    final apps0 = r.n('apps');

    r.attsFail = false;
    await _tapOwnedRetry(tester, find.text(_kOvernightUnknown), '어제 퇴근 확인 못함 카드', _Scope.row, GestureDetector);

    expect(r.n('atts'), 2);
    expect(r.n('apps'), apps0 + 1, reason: '재시도는 홈 전체 재조회다');
    expect(find.text(_kOvernightUnknown), findsNothing);
    expect(find.text(_kIncomeErr), findsNothing);
    // [F92-3] 빈 근태 성공 응답의 긍정 표면 — 정상 빈 수입 안내(어제 퇴근 CTA 의 실제 판정 · 금액은 보지 않는다)
    expect(findVisibleText(_kIncomeEmpty), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('U7-5 공고 실패 카드의 다시 시도 → 공고 읽기 성공이면 실패 카드가 걷히고 추천 사업장 읽기까지 간다', (tester) async {
    final r = _Reads(tos: [_recTo()])..tosFail = true;
    await _pump(tester, reads: r.build());
    expect(r.n('tos'), 1);
    expect(find.text(_kPostingsErr), findsOneWidget);
    expect(r.n('biz'), 0, reason: '공고를 못 읽으면 추천 상위 사업장도 없다');
    final apps0 = r.n('apps');

    r.tosFail = false;
    await _tapOwnedRetry(tester, find.text(_kPostingsErr), '공고 실패 카드', _Scope.column, TextButton);

    expect(r.n('tos'), 2);
    expect(r.n('apps'), apps0 + 1, reason: '재시도는 홈 전체 재조회다');
    expect(find.text(_kPostingsErr), findsNothing);
    expect(r.bizIds, [_biz], reason: '성공한 공고 응답이 추천 목록에 반영되어 그 사업장 문서를 읽는다');
    expect(tester.takeException(), isNull);
  });

  testWidgets('U7-6 stale 띠의 다시 시도 → 지원 읽기 성공 응답(3건)이 반영되고 띠가 걷힌다', (tester) async {
    final r = _Reads(apps: _two());
    await _pump(tester, reads: r.build());
    r.appsFail = true;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await _settle(tester);
    expect(r.n('apps'), 2);
    expect(find.text(_kStale), findsOneWidget);
    expect(find.text(_kTermUnknown), findsOneWidget); // [F92-3] 실패 도달의 같은 읽기 표면
    expect(_stats(), {'검토 중': '2', '확정': '0', '계약 대기': '0'});
    final atts0 = r.n('atts');
    final tos0 = r.n('tos');

    r
      ..appsFail = false
      ..apps = [..._two(), _pend('pc', 14, '마바 센터')];
    await _tapOwnedRetry(tester, find.text(_kStale), 'stale 띠', _Scope.row, GestureDetector);

    expect(r.n('apps'), 3);
    expect(r.n('atts'), atts0 + 1, reason: '재시도는 홈 전체 재조회다'); // [F92-3]
    expect(r.n('tos'), tos0 + 1, reason: '재시도는 홈 전체 재조회다'); // [F92-3]
    expect(find.text(_kStale), findsNothing);
    expect(find.text(_kTermUnknown), findsNothing); // [F92-3]
    expect(_stats(), {'검토 중': '3', '확정': '0', '계약 대기': '0'});
    expect(tester.takeException(), isNull);
  });
}
