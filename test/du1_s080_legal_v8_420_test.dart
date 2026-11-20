// [판정67 · 인계67 T3-only 재개] repair r1 d9234c9a 보존. 바뀐 것(V8 철회에 따른 명시 계약 개정 — 작은 시험 수리 아님):
//   strict 관리자 tbBase 는 원 repair r1 run 의 봉인된 TB(_tbE 절대 경로 · 재사용)를 읽는다. TA manifest 는 이번 실행(DUL_MANIFEST).
//   원 TB ↔ 새 TA 입력 차이는 명시 값 정확 2: 카드 68b819dc → d9ebf96a · 시험 d9234c9a → 실행 중인 이 시험 파일 SHA(실측). 홈 ee1f3f31 은 양쪽 같음.
//   TODAY 패딩 기대: before · strict 모두 2·s(PadK 2 · 원 실수 2.0 ±0.01). 그 밖(T3 probe/line/ready/shot/토글·재접기/done/예외/공개 10/캡처 20)은 그대로.
// [판정65 · 인계65 보완 p3] p2 6a649b48 보존. 바뀐 것:
//   F65-1 shot() 안에서 마지막 ready/settle 뒤 최신 넘침 누계를 읽어 'shot <id> ovf=…' 로 출력하고, strict 관리자는 같은 실행 TB 의 같은 shot 기준(같은 수집 시점)과
//     비교한다(지원자/TODAY 는 0). 누계 읽기 → 출력 → must → vqCapture 사이에 pump · scroll · await 0. tbBase 는 TB tok 정확 7줄(begin · card 3 · shot 2 · done)을 읽는다.
//   F65-2 PadR 판정은 원 pad/s 실수(±0.01)로 boxProbe 안에서 — 표시 문자열(num2)을 되읽지 않는다.
// [판정64 · 인계64 보완 p2] 원본 p1 2d46abc2 보존. 바뀐 것:
//   F64-1 strict 관리자 상태는 같은 실행 E 의 봉인된 TB(manifest 직전=직후 · 입력 차이 = 후보 두 파일 · TB meta/finish PROCEED)에서 같은 tok 의
//     card init/body/refold · done 넘침을 정확 1개씩 읽어 TA 누계 ≤ TB 를 그 단계 shot 전에 must 로 막는다(개수 비교 — 같은 수의 다른 오류 동일성 인증 아님).
//     원시 넘침 문구는 done 줄 ovfRaw(base64url · 없으면 -)로 보존한다.
//   F64-2 같은 파일 앞 사례 실패 뒤 본문 · 캡처 0(_anyFail 2층 — runner --fail-fast 와 별개) · 각 shot 직전 미처리 framework 예외 0 must.
//   F64-4 W/B 장면 문구 = 실제 fold · V8 실제 TextStyle(크기 · 굵기 · 글꼴 · 줄높이) · TextScaler · 문단/상자/칸 rect · 미반올림 패딩 비율 · 칸 포함 4방향(±0.5).
// [S080 T3 B 공용 + V8 4·s · DU420 · 판정63 · 인계63] 공용 약관 할 일 카드(지원자 홈 + 관리자 홈) 작은 강조 · 지원자 홈 상단 날짜 숫자 상자 안쪽 여백.
//   새 파일 · 정확 10 public(W 390x844@1.0 · B 320x640@2.0 × USERRC · USERLG · ADMINRC · ADMINLG · TODAY).
//   캡처: T3 네 상태 1card(기본) · 2body(설명 보이는 장면) / TODAY 1init(오늘 외곽선) · 2other(오늘 외곽선 + 다른 날 채움) × W/B = 20쌍.
//     W 는 제목이 한 줄이라 설명이 처음부터 보이고 토글이 없다. lkit 캡처는 뷰 × 상태 × 장면의 곱이라 W 2body 는 W 1card 와 같은 장면의 두 번째 shot 이다(공개 · 의도된 중복).
//     B 는 제목이 접혀 2body = 실제 '설명 보기' 탭 뒤 펼친 장면이다. 재접기는 shot 없이 줄 · must(높이 · 토글 · 의미 원복)로 본다.
//   하네스: 지원자 = UserHomeScreen(reads:, clock:) + UserTabScope 기록 대역(DU419 와 같음) / 관리자 = BusinessAdminHomeScreen(reads:)(admin_home_content_render_test 와 같은 경계).
//     reads 메모리 fixture · Firebase 가짜 · 쓰기 0 · 카드 본 탭(동의 화면 이동)은 하지 않는다(이동/복귀 조회는 기존 legal_effective_55 · legal_reconsent_consumer 가 본다).
//   고정 시각 2026-11-11(수) 10:00 KST. 약관: RC = reconsentRequired(service_terms) · LG = legacyConsentUnknown · TODAY = current(카드 없음).
//   모드: DU_BEFORE_OBSERVE=420 이면 before(현행 카드 68b819dc · 홈 ee1f3f31 관측), 아니면 strict(후보).
//   'card <단계>'(init · body · refold): lead 원/아이콘 · leadBg 원 면 · leadInk 망치 색 · border 카드 선 · bg 카드 면 · title 제목 색 · chev 꺾쇠 색 · tap 카드 탭 콜백 ·
//     hit 제목 중심 hit-test 가 제목에 닿음 · vis 카드 ⊂ 본문 viewport ∩ 화면 · rowOk 글 열 폭 = 내용 폭 − 선행 − 10·s − 18·s(±0.5) · foldOk 접힘 = 한 줄 제목 폭 > 글 열 폭 ·
//     body 설명 색(없으면 -) · tog 토글(-/show/hide) · togC 토글 글 색 · expC 펼침 아이콘 색 · exp 토글 의미 expanded · fold 접힘 · s 호스트 배율 · cw 내용 폭 · colW 글 열 폭 ·
//     leadD 선행 지름/크기 · alignDy 선행 중심 − 제목 첫 줄 중심 · h 카드 높이 · (refold) sameH 처음 높이와 같음 · ovf 넘침 누계.
//   'box <단계>'(init · other): 오늘(t*) · 선택(s*) 숫자 상자 — deco · padK(좌 패딩 ÷ s, s = 최소 폭 ÷ 36) · inBox 문단 ⊂ 상자 · inCell 상자 ⊂ 칸 · one 한 줄 · clip 높이 잘림 ·
//     boxW · boxH · cellW · gapL · gapR(문단 ↔ 상자 가로 여백).
//   출력 줄: lkit 선언형 계약 'D420 <tok> <kind> [<sub>] k=v …' — 값 공백 0.
// ignore_for_file: depend_on_referenced_packages
import 'dart:convert';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ALfit/models/core/application_model.dart';
import 'package:ALfit/models/core/attendance_model.dart';
import 'package:ALfit/models/core/business_member_model.dart';
import 'package:ALfit/models/core/business_model.dart';
import 'package:ALfit/models/core/contract_template_model.dart';
import 'package:ALfit/models/core/employment_contract_model.dart';
import 'package:ALfit/models/core/id_card_access_request_model.dart';
import 'package:ALfit/models/core/legal_readiness.dart';
import 'package:ALfit/models/core/renewal_proposal_model.dart';
import 'package:ALfit/models/core/slot_model.dart';
import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/models/core/user_region.dart';
import 'package:ALfit/models/ui/admin_home_summary_model.dart';
import 'package:ALfit/models/ui/staffing_readiness_model.dart';
import 'package:ALfit/providers/notification_provider.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/screens/business_admin/admin_home_reads.dart';
import 'package:ALfit/screens/business_admin/business_admin_home_screen.dart';
import 'package:ALfit/screens/legal/legal_consent_screen.dart';
import 'package:ALfit/screens/user/user_home_reads.dart';
import 'package:ALfit/screens/user/user_home_screen.dart';
import 'package:ALfit/screens/user/user_tab_scope.dart';
import 'package:ALfit/services/business_posting_readiness.dart';
import 'package:ALfit/services/payroll_correction_service.dart';
import 'package:ALfit/theme/app_colors.dart';
import 'package:ALfit/theme/role_theme.dart';
import 'package:ALfit/utils/format_helper.dart';
import 'package:ALfit/widgets/common/legal_task_card.dart';

import 'support/du1_vq_capture.dart';
import 'support/visible_text.dart';

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

/// 지원자 provider 대역(DU419 시험과 같은 게터 덮개)
class _Worker extends UserProvider {
  @override
  UserModel? get currentUser => UserModel(
      uid: 'u1', username: 'u1', name: '김근로', email: 'u1@alfit.local', role: UserRole.USER,
      homeRegion: const UserRegion(province: '서울특별시', city: '강남구', district: '역삼동'),
      accountStatus: 'active', passVerifiedAt: DateTime.utc(2026, 10, 1), totalWorkDays: 3);
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

/// 관리자 provider 대역(admin_home_content_render_test 의 _AdminProvider 와 같은 판정 — BUSINESS_ADMIN · 권한 허용)
class _Admin extends UserProvider {
  @override
  UserModel? get currentUser => UserModel(
      uid: 'admin1', username: 'admin1', name: '김관리', email: 'admin1@alfit.local', role: UserRole.BUSINESS_ADMIN,
      managedBusinessIds: const ['biz1'], sealBase64: 'seal');
  @override
  bool get isSubAdmin => false;
  @override
  String? get effectiveBusinessId => null;
  @override
  bool get subAdminPermissionsLoaded => true;
  @override
  PermissionWatchState get currentBusinessPermissionHealth => PermissionWatchState.verified;
  @override
  PermissionCheck checkCurrentBusiness(bool Function(MemberPermissions p) check) => PermissionCheck.allowed;
  @override
  bool can(bool Function(MemberPermissions p) check) => true;
  @override
  bool canForAnyBusiness(bool Function(MemberPermissions p) check, {required bool whenUnknown}) => true;
}

class _Template extends Fake implements ContractTemplateModel {
  @override
  bool get isSupportedForNewUse => true;
}

const _biz = 'biz1';
const _bizName = '강남 물류센터';
// 고정 시각: 2026-11-11(수) 10:00 KST
final DateTime _clock = DateTime.utc(2026, 11, 11, 1);
final DateTime _today = FormatHelper.toKstDate(_clock);
const _todayStr = '2026-11-11';
DateTime _day(int o) => _today.add(Duration(days: o));
const _wd = ['월', '화', '수', '목', '금', '토', '일'];
String _kDate(DateTime d) => '${d.month}월 ${d.day}일 ${_wd[d.weekday - 1]}요일';

const _rc = LegalReadiness(status: LegalReadinessStatus.reconsentRequired, reconsentRequired: ['service_terms']);
const _lg = LegalReadiness(status: LegalReadinessStatus.legacyConsentUnknown);
const _cur = LegalReadiness(status: LegalReadinessStatus.current);
// 카드 문구(제품 원문 그대로 — 찾기용)
const _texts = {
  'RC': (title: '이용약관이 변경되었습니다', body: '변경된 내용을 확인하고 동의해 주세요.'),
  'LG': (title: '약관 동의 정보 확인이 필요해요', body: '이전 동의 기록으로는 내용을 확인할 수 없어요.'),
};

ApplicationModel _app(String id, DateTime workDate) => ApplicationModel(
    id: id, toId: 'to_$id', uid: 'u1', businessId: _biz, businessName: _bizName, toTitle: '단기 공고',
    status: AppStatus.confirmed, selectedWorkType: '피킹', startTime: '13:00', endTime: '18:00', wage: 12000, wageType: 'hourly',
    workDate: workDate, appliedAt: _day(-3));

// 소유자 id: 지원자 홈 = 'a1'(DU419 와 같음) · 관리자 홈 = 'admin1'(관리자 대역 uid — admin_home_content_render_test 와 같음)
BusinessModel _business({String owner = 'a1'}) => BusinessModel(
    id: _biz, name: _bizName, ownerId: owner, businessNumber: '000-00-00000', address: '서울특별시 강남구 테헤란로 1',
    category: '물류', subCategory: '창고', isApproved: true, createdAt: _day(-200));

UserHomeReads _userReads(List<ApplicationModel> apps, LegalReadiness legal) => UserHomeReads(
      slotsForTO: (_) async => const <SlotModel>[],
      myContracts: (_) async => const <EmploymentContractModel>[],
      myApplications: (_) async => List.of(apps),
      myMonthlyAttendances: ({required String userId, required int year, required int month}) async => const <AttendanceModel>[],
      publishedTOs: () async => const [],
      pendingIdCardRequests: (_) async => const <IdCardAccessRequestModel>[],
      myRenewalProposals: () async => const <RenewalProposalModel>[],
      businessById: (_) async => _business(),
      invalidatePublishedTOsCache: () {},
      documentCorrections: () async => DocumentCorrectionSurface.empty,
      legalReadiness: () async => legal,
    );

Map<String, dynamic> _simple(int count) => {
      'available': true,
      'count': count,
      'byBusiness': [
        {'businessId': _biz, 'count': count},
      ],
    };

AdminHomeSummaryModel _summary() => AdminHomeSummaryModel.fromMap({
      'actions': {
        'resignRequest': {..._simple(0), 'soonCount': 0},
        'approval': {..._simple(3), 'overdueCount': 0},
        'scheduleChangeRequest': _simple(0),
        'unsentContract': _simple(2),
        'unclosed': {..._simple(0), 'oldestDate': null},
        'settlementRequest': _simple(0),
        'wageChangeRequest': _simple(0),
        'unpaidWage': {..._simple(0), 'overdueCount': 0, 'missingDueDateCount': 0},
      },
      'upcoming': {
        'expiringContract': {..._simple(0), 'upcomingCount': 0, 'expiredCount': 0},
      },
    });

AdminHomeReads _adminReads(LegalReadiness legal) => AdminHomeReads(
      summary: ({String? selectedBusinessId}) async => _summary(),
      businessesByIds: (ids) async => [_business(owner: 'admin1')],
      staffingReadiness: ({String? selectedBusinessId}) async => StaffingReadinessModel(
            available: true,
            partial: false,
            failedBusinessCount: 0,
            publishedPostingCount: 1,
            days: [
              StaffingDayData.fromMap({
                'date': _todayStr,
                'requiredCount': 6,
                'confirmedCount': 4,
                'shortageCount': 2,
                'pendingAvailable': false,
                'byBusiness': const <Map<String, dynamic>>[],
              }),
            ],
          ),
      attendanceByDate: ({required String businessId, required DateTime date}) async => const <AttendanceModel>[],
      confirmedWorkers: ({required DateTime date, required String businessId}) async => const <ApplicationModel>[],
      workDetailTimes: (_) async => <String, dynamic>{},
      postingReadiness: (bizs) async => {
        for (final b in bizs)
          b.id: BusinessPostingReadiness(
            bizId: b.id,
            isApproved: true,
            hasCanonicalLicense: true,
            hasOwnerLegacyLicense: false,
            hasActiveWorkTypes: true,
            hasEmployerSeal: true,
          ),
      },
      contractTemplates: (_) async => <ContractTemplateModel>[_Template()],
      tourCompleted: () => Future<bool>.value(true),
      clock: () => _clock,
      legalReadiness: () async => legal,
    );

final bool _before = Platform.environment['DU_BEFORE_OBSERVE'] == '420';
// [재개 · 판정67] 재사용하는 원 TB(repair r1 run · 성공 TB10) — 명시 출처. 원 TB ↔ 새 TA 입력 차이의 정확 값.
const _tbE = 'C:/Users/kug02/codex-audit/records/work/du-s080-legal-v8-prep/p3/repair/r1/run';
const _cardPath = 'lib/widgets/common/legal_task_card.dart';
const _homePath = 'lib/screens/user/user_home_screen.dart';
const _testPath = 'test/du1_s080_legal_v8_420_test.dart';
const _tbCardSha = '68b819dcbf6e8a8879b56997023213487b94ec98c01962bb980b7b1c0cd811c3';
const _taCardSha = 'd9ebf96aa29911993c134f84777df041054d1c4c21372088705357711d57f0dd';
const _tbTestSha = 'd9234c9a85618bff529a41c175b7df93399cffa77f668d3cdc73271df5d739da';
const _homeSha = 'ee1f3f3180aab214e76bccc14308e12836c4aeb89470ed78c5580a862f3ac27b';
// [F64-2 2층] 같은 파일에서 앞 사례가 실패하면 뒤 사례는 화면을 띄우거나 찍지 않고 바로 실패한다(runner --fail-fast 가 있어도 따로 막는다).
var _anyFail = false;
String _rect(Rect r) => '${_f1(r.left)},${_f1(r.top)},${_f1(r.right)},${_f1(r.bottom)}';
String _b64(List<String> xs) => xs.isEmpty ? '-' : base64Url.encode(utf8.encode(xs.join('\n'))).replaceAll('=', '');
final String _manifest = Platform.environment['DUL_MANIFEST'] ?? '(unset)';
const _envKeys = ['DU_BEFORE_OBSERVE', 'DU1_VQ_PHASE', 'DU1_VQ_OUT', 'DU1_VQ_RUN', 'DU1_VQ_DATE', 'DU397_DIAG', 'DU397_MANIFEST', 'DU400_MANIFEST',
  'DU401_MANIFEST', 'DU398_MANIFEST', 'DU406_MANIFEST', 'DU407_MANIFEST', 'DU296_PHASE', 'DUL_MANIFEST'];
final String _envLine = [for (final k in _envKeys) '$k:${Platform.environment[k] ?? '(unset)'}'].join(',');

void _out(String s) {
  // ignore: avoid_print
  print(s);
}

String _vt(Widget w) => w is Text ? visibleText(w.data ?? w.textSpan?.toPlainText() ?? '') : '';
Finder _el(Element e) => find.byElementPredicate((x) => identical(x, e), skipOffstage: false);

String _code(Color? c) {
  if (c == null) return '-';
  if (c == AppColors.surface) return 'surface';
  if (c == AppColors.textPrimary) return 'primary';
  if (c == AppColors.textSecondary) return 'secondary';
  if (c == AppColors.yellowWarnText) return 'warnText';
  if (c == AppColors.yellowWarnDark) return 'warnDark';
  if (c == AppColors.yellowWarnBorder) return 'warn';
  if (c == AppColors.borderLight) return 'light';
  if (c == AppColors.conceptAmberSurface) return 'amberSurface';
  if (c == AppColors.conceptAmberInk) return 'amberInk';
  if (c == AppColors.grey600) return 'grey600';
  if (c == AppColors.brand) return 'brand';
  return 'other';
}

String _f1(double v) => v.toStringAsFixed(1);
String _f2(double v) => v.toStringAsFixed(2);

// 카드 단계별 정확 기대(뷰 공통). 뷰마다 다른 값(fold · body(init) · tog · togC · expC · exp · s · cw · colW · leadD · alignDy · h)은 typed + 아래 뷰별 must.
const _cardStrict = {'lead': 'circle', 'leadBg': 'amberSurface', 'leadInk': 'amberInk', 'border': 'light', 'bg': 'surface', 'title': 'primary', 'chev': 'grey600'};
const _cardBefore = {'lead': 'icon', 'leadBg': '-', 'leadInk': 'warnDark', 'border': 'warn', 'bg': 'surface', 'title': 'warnText', 'chev': 'warnDark'};
const _bodyStrict = 'secondary';
const _bodyBefore = 'warnText';
const _togStrict = (togC: 'secondary', expC: 'amberInk');
const _togBefore = (togC: 'warnText', expC: 'warnDark');

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({
        'onboarding_completed_u1': true,
        'tour_completed_user_home': true,
        'tour_completed_admin_home': true,
      }));
  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
    await initializeDateFormatting('ko_KR');
  });

  const views = [(id: 'W', w: 390.0, h: 844.0, s: 1.0), (id: 'B', w: 320.0, h: 640.0, s: 2.0)];
  const states = [
    (key: 'USERRC', title: '지원자 홈 약관 재동의 카드 — 기본 · 설명 펼침(B 실제 토글) · 재접기'),
    (key: 'USERLG', title: '지원자 홈 옛 동의 확인 카드 — 기본 · 설명 펼침(B 실제 토글) · 재접기'),
    (key: 'ADMINRC', title: '관리자 홈 약관 재동의 카드 — 기본 · 설명 펼침(B 실제 토글) · 재접기'),
    (key: 'ADMINLG', title: '관리자 홈 옛 동의 확인 카드 — 기본 · 설명 펼침(B 실제 토글) · 재접기'),
    (key: 'TODAY', title: '지원자 홈 날짜 띠 숫자 상자 — 오늘 외곽선 · 다른 날 선택 채움 안쪽 여백'),
  ];
  for (final v in views) {
    for (final st in states) {
      testWidgets('S080LV-${v.id}-${st.key} ${st.title}', (t) async {
        if (_anyFail) fail('앞 사례 실패 — 이 사례 본문 실행 0 · 캡처 0(F64-2)');
        try {
        final tok = 'S080LV-${v.id}-${st.key}';
        final mode = _before ? 'before' : 'strict';
        _out('D420 $tok begin mode=$mode phase=${Platform.environment['DU1_VQ_PHASE'] ?? '(unset)'} env=$_envLine manifest=$_manifest');
        await t.runAsync(vqLoadFonts);
        final isAdmin = st.key.startsWith('ADMIN');
        final overflows = <String>[];
        final fwErrors = <String>[]; // [F64-2] 넘침 밖 framework 오류 — 다음 shot 전에 막는다(끝의 takeException 만 기다리지 않는다)
        final prev = FlutterError.onError;
        FlutterError.onError = (d) {
          final m = d.exceptionAsString();
          if (m.contains('overflowed')) {
            overflows.add(m.split('\n').first);
          } else {
            fwErrors.add(m.split('\n').first);
            prev?.call(d);
          }
        };
        addTearDown(() => FlutterError.onError = prev);
        t.view.physicalSize = Size(v.w, v.h);
        t.view.devicePixelRatio = 1.0;
        addTearDown(t.view.reset);
        void must(String k, bool ok, [String why = '']) => expect(ok, isTrue, reason: '$tok $k $why');
        Future<void> settle([int n = 10]) async {
          for (var i = 0; i < n; i++) {
            await t.pump(const Duration(milliseconds: 100));
          }
        }

        Map<String, int>? tbAll; // [F65-1] strict 관리자 — 같은 실행 TB 기준(card 단계 · shot · done)
        var captures = 0;
        final key = GlobalKey();
        final cond = {'viewport': '${v.w.toInt()}x${v.h.toInt()}', 'textScaler': v.s, 'run': vqRun, 'manifest': _manifest, 'mode': mode, 'fixture': st.key};
        Future<void> shot(String id, String stage) async {
          must('shot $id 직전 미처리 framework 예외 0(F64-2)', fwErrors.isEmpty, '$fwErrors');
          // [F65-1] 마지막 ready/settle 뒤 최신 넘침 누계 — 여기부터 vqCapture 까지 pump · scroll · await 0(TB 도 같은 수집 시점).
          final o = overflows.length;
          final tb = tbAll?[id];
          _out('D420 $tok shot $id ovf=$o${isAdmin ? ' tbOvf=${tb ?? '-'}' : ''}');
          if (!isAdmin) must('shot $id 직전 넘침 0(F65-1)', o == 0, '$overflows');
          if (tb != null) must('shot $id 직전 관리자 넘침 TA $o ≤ 같은 실행 TB $tb(F65-1)', o <= tb, '$overflows');
          await vqCapture(t, key, '${tok}_$id', conditions: {...cond, 'state': stage});
          captures++;
        }

        final log = <String>[];
        final legal = st.key == 'TODAY' ? _cur : (st.key.endsWith('RC') ? _rc : _lg);
        final apps = st.key == 'TODAY' ? [_app('a0', _day(0)), _app('a2', _day(2))] : [_app('a2', _day(2))];
        await t.pumpWidget(MultiProvider(
          providers: [
            ChangeNotifierProvider<UserProvider>.value(value: isAdmin ? _Admin() : _Worker()),
            ChangeNotifierProvider<NotificationProvider>(create: (_) => NotificationProvider()),
          ],
          child: RepaintBoundary(
            key: key,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: isAdmin ? RoleTheme.businessAdminTheme : RoleTheme.workerTheme,
              builder: (ctx, child) => MediaQuery(data: MediaQuery.of(ctx).copyWith(textScaler: TextScaler.linear(v.s)), child: child!),
              home: isAdmin
                  ? BusinessAdminHomeScreen(reads: _adminReads(legal))
                  : UserTabScope(
                      switchToTab: (i) => log.add('switchToTab:$i'),
                      switchToTabWithDate: (i, d) => log.add('switchToTabWithDate:$i'),
                      pendingJobDate: null,
                      clearPendingJobDate: () {},
                      pendingScheduleMonth: null,
                      clearPendingScheduleMonth: () {},
                      switchToScheduleNow: () => log.add('switchToScheduleNow'),
                      child: UserHomeScreen(reads: _userReads(apps, legal), clock: () => _clock),
                    ),
            ),
          ),
        ));
        await settle(25);

        bool inR(Rect o, Rect r) => r.top >= o.top - 0.5 && r.bottom <= o.bottom + 0.5 && r.left >= o.left - 0.5 && r.right <= o.right + 0.5;
        final screenR = Offset.zero & Size(v.w, v.h);
        Rect bodyView() {
          final vs = [
            for (final e in find.byType(Scrollable).evaluate())
              if ((e.widget as Scrollable).axisDirection == AxisDirection.down) e
          ]..sort((a, c) => t.getRect(_el(c)).height.compareTo(t.getRect(_el(a)).height));
          return vs.isEmpty ? screenR : t.getRect(_el(vs.first));
        }

        int? tbDone; // [F64-1] strict 관리자 — 같은 실행 TB done 넘침 기준
        if (st.key != 'TODAY') {
          // ─────────────── T3 카드 ───────────────
          final tx = _texts[st.key.endsWith('RC') ? 'RC' : 'LG']!;
          final card = find.byType(LegalTaskCard);
          must('카드 1', card.evaluate().length == 1, '${card.evaluate().length}');
          await t.ensureVisible(card);
          await settle(4);
          Finder inCard(bool Function(Widget w) p) => find.descendant(of: card, matching: find.byWidgetPredicate(p, skipOffstage: false), skipOffstage: false);
          final titleF = inCard((w) => w is Text && w.semanticsLabel == tx.title);
          final bodyF = inCard((w) => w is Text && w.semanticsLabel == tx.body);
          final togF = inCard((w) => w is Text && (w.data == '설명 보기' || w.data == '설명 접기'));
          final boxF = inCard((w) => w is Container && w.decoration is BoxDecoration && (w.decoration! as BoxDecoration).border != null);
          final circF = inCard((w) => w is Container && w.decoration is BoxDecoration && (w.decoration! as BoxDecoration).shape == BoxShape.circle);
          final gavelF = inCard((w) => w is Icon && w.icon == Icons.gavel_rounded);
          final chevF = inCard((w) => w is Icon && w.icon == Icons.chevron_right);
          final expF = inCard((w) => w is Icon && (w.icon == Icons.expand_more || w.icon == Icons.expand_less));

          // [F64-1] strict 관리자: 같은 실행 E(= DUL_MANIFEST 폴더)의 봉인된 TB 기준을 정확 1개씩 읽는다. 어긋나면 실패(첫 shot 전).
          Map<String, int>? tbBase() {
            if (!isAdmin || _before) return null;
            final ta = File(_manifest);
            must('TA manifest 경로', _manifest != '(unset)' && ta.existsSync(), _manifest);
            final e = _tbE; // [재개] 원 TB 묶음(이번 실행 폴더가 아니다)
            must('원 TB 는 이번 실행 폴더 밖', ta.parent.path.replaceAll('\\', '/') != e, ta.parent.path);
            Map<String, dynamic> j(String p) => jsonDecode(File(p).readAsStringSync()) as Map<String, dynamic>;
            final tbPre = j('$e/manifest_tb_pre.json'), tbPost = j('$e/manifest_tb_post.json'), taPre = j(_manifest);
            must('TB manifest 봉인(직전 = 직후 · tb · du420-tb · problems 0)',
                jsonEncode(tbPre) == jsonEncode(tbPost) && tbPre['stage'] == 'tb' && tbPre['run'] == 'du420-tb' && (tbPre['problems'] as List).isEmpty);
            final fb = tbPre['files'] as Map<String, dynamic>, fa = taPre['files'] as Map<String, dynamic>;
            final diff = {for (final k in {...fb.keys, ...fa.keys}) if (jsonEncode(fb[k]) != jsonEncode(fa[k])) k};
            // [재개] 명시 allowlist — 경로 2 + 양쪽 정확 값(시험 새 값 = 실행 중 파일 실측 SHA) · 홈은 양쪽 ee1f3f31.
            String shaOf(Map<String, dynamic> f, String k) => (f[k] is Map ? (f[k] as Map)['sha256'] : null)?.toString() ?? '-';
            final selfSha = sha256.convert(File(_testPath).readAsBytesSync()).toString();
            must('원 TB ↔ 새 TA 입력 차이 = 카드 · 시험 정확 2(명시 값) · 홈 동일',
                diff.length == 2 && diff.containsAll([_cardPath, _testPath]) && shaOf(fb, _cardPath) == _tbCardSha && shaOf(fa, _cardPath) == _taCardSha &&
                    shaOf(fb, _testPath) == _tbTestSha && shaOf(fa, _testPath) == selfSha && shaOf(fb, _homePath) == _homeSha && shaOf(fa, _homePath) == _homeSha,
                '$diff · card ${shaOf(fb, _cardPath)}→${shaOf(fa, _cardPath)} · test ${shaOf(fb, _testPath)}→${shaOf(fa, _testPath)}(self $selfSha) · home ${shaOf(fa, _homePath)}');
            final meta = <String, String>{
              for (final l in File('$e/logs/TB.meta.txt').readAsLinesSync())
                if (l.contains('=')) l.substring(0, l.indexOf('=')): l.substring(l.indexOf('=') + 1)
            };
            must('TB meta test_rc 0 · run du420-tb · before 420', meta['test_rc'] == '0' && meta['DU1_VQ_RUN'] == 'du420-tb' && meta['DU_BEFORE_OBSERVE'] == '420', '$meta');
            final fin = j('$e/logs/TB.finish.json');
            final ck = fin['checks'] as Map<String, dynamic>? ?? const {};
            must('TB finish PROCEED(wrapper 0 · guard 0 · lgate 0 · lpost 0)', fin['wrapper_rc'] == '0' && fin['guard_rc'] == 0 && ck['lgate'] == 0 && ck['lpost'] == 0, '$fin');
            final mine = <String>[];
            for (final raw in File('$e/logs/TB.jsonl').readAsLinesSync()) {
              if (!raw.startsWith('{')) continue;
              final ev = jsonDecode(raw);
              if (ev is Map && ev['type'] == 'print' && ev['message'] is String && (ev['message'] as String).startsWith('D420 $tok ')) mine.add(ev['message'] as String);
            }
            List<String> of(String head) => [for (final m in mine) if (m.startsWith('D420 $tok $head ')) m];
            final begins = of('begin');
            must('TB 같은 tok 줄 정확 7(begin · card 3 · shot 2 · done)', mine.length == 7, '${mine.length}');
            must('TB begin before · manifest tb · run du420-tb', begins.length == 1 && begins.first.contains(' mode=before phase=before ') &&
                begins.first.contains('DU1_VQ_RUN:du420-tb') && begins.first.endsWith(' manifest=$e/manifest_tb_pre.json'), '$begins');
            final out = <String, int>{};
            for (final sub in const ['init', 'body', 'refold']) {
              final ls = of('card $sub');
              final ms = ls.length == 1 ? RegExp(r' ovf=(\d+)(?= |$)').allMatches(ls.first).toList() : const <RegExpMatch>[];
              must('TB card $sub 정확 1 · ovf 정수 1', ls.length == 1 && ms.length == 1, '$ls');
              out[sub] = int.parse(ms.first.group(1)!);
            }
            final dn = of('done');
            final dm = dn.length == 1 ? RegExp(r' overflows=(\d+)(?= |$)').allMatches(dn.first).toList() : const <RegExpMatch>[];
            must('TB done 정확 1 · mode before · overflows 정수 1', dn.length == 1 && dn.first.contains(' mode=before ') && dm.length == 1, '$dn');
            out['done'] = int.parse(dm.first.group(1)!);
            for (final id in const ['1card', '2body']) {
              final ls = of('shot $id');
              final ms = ls.length == 1 ? RegExp(r' ovf=(\d+)(?= |$)').allMatches(ls.first).toList() : const <RegExpMatch>[];
              must('TB shot $id 정확 1 · ovf 정수 1(같은 수집 시점)', ls.length == 1 && ms.length == 1, '$ls');
              out[id] = int.parse(ms.first.group(1)!);
            }
            return out;
          }

          final tbO = tbBase();
          tbAll = tbO; // [F65-1] shot() 가 같은 shot 기준을 읽는다
          tbDone = tbO?['done'];

          Map<String, String> probe() {
            must('제목 1', titleF.evaluate().length == 1, '${titleF.evaluate().length}');
            must('카드 면 상자 1', boxF.evaluate().length == 1, '${boxF.evaluate().length}');
            must('망치 1', gavelF.evaluate().length == 1, '${gavelF.evaluate().length}');
            must('꺾쇠 1', chevF.evaluate().length == 1, '${chevF.evaluate().length}');
            final outerPad = t.widget<Padding>(find.descendant(of: card, matching: find.byType(Padding), skipOffstage: false).first).padding as EdgeInsets;
            final s = outerPad.left / 16;
            final dec = t.widget<Container>(boxF).decoration! as BoxDecoration;
            final row = find.descendant(of: boxF, matching: find.byType(Row), skipOffstage: false).first;
            final cw = t.getSize(row).width;
            final col = find.ancestor(of: titleF, matching: find.byType(Column)).first;
            final colW = t.getSize(col).width;
            final circles = circF.evaluate().length;
            final leadR = circles == 1 ? t.getRect(circF) : t.getRect(gavelF);
            final leadW = circles == 1 ? leadR.width : t.widget<Icon>(gavelF).size ?? 0;
            // [repair r1] 제목 Text 는 semanticsLabel 이 있어 Semantics 가 RichText 를 감싼다 — 문단 렌더 객체는 RichText 자손에서 읽는다(TB 원 실패: RenderSemanticsAnnotations 캐스트).
            final titleRT = find.descendant(of: titleF, matching: find.byType(RichText), skipOffstage: false);
            must('제목 RichText 1', titleRT.evaluate().length == 1, '${titleRT.evaluate().length}');
            final para = t.renderObject<RenderParagraph>(titleRT);
            final tp = TextPainter(text: para.text, textScaler: para.textScaler, textDirection: TextDirection.ltr)..layout();
            final titleR = t.getRect(titleF);
            final alignDy = leadR.center.dy - (titleR.top + tp.height / 2);
            final titleOne = tp.width;
            tp.dispose();
            final fold = togF.evaluate().isNotEmpty;
            final togText = fold ? t.widget<Text>(togF).data : null;
            final togSem = fold ? find.ancestor(of: togF, matching: find.byWidgetPredicate((w) => w is Semantics && w.properties.button == true)) : null;
            final exp = (togSem == null || togSem.evaluate().isEmpty) ? '-' : '${t.widget<Semantics>(togSem.first).properties.expanded}';
            final hit = t.hitTestOnBinding(t.getCenter(titleF)).path.any((e) => identical(e.target, para)); // [repair r1] 제목 문단(RenderParagraph)
            final cardR = t.getRect(boxF);
            final ink = find.descendant(of: card, matching: find.byType(InkWell), skipOffstage: false).first;
            return {
              'lead': circles == 1 ? 'circle' : 'icon',
              'leadBg': circles == 1 ? _code((t.widget<Container>(circF).decoration! as BoxDecoration).color) : '-',
              'leadInk': _code(t.widget<Icon>(gavelF).color),
              'border': _code((dec.border! as Border).top.color),
              'bg': _code(dec.color),
              'title': _code(t.widget<Text>(titleF).style?.color),
              'chev': _code(t.widget<Icon>(chevF).color),
              'tap': '${t.widget<InkWell>(ink).onTap != null}',
              'hit': '$hit',
              'vis': '${inR(bodyView(), cardR) && inR(screenR, cardR)}',
              'rowOk': '${(colW - (cw - leadW - 10 * s - 18 * s)).abs() <= 0.5}',
              'foldOk': '${fold == (titleOne > colW + 0.01)}',
              'body': bodyF.evaluate().isEmpty ? '-' : _code(t.widget<Text>(bodyF).style?.color),
              'tog': togText == null ? '-' : (togText == '설명 보기' ? 'show' : 'hide'),
              'togC': fold ? _code(t.widget<Text>(togF).style?.color) : '-',
              'expC': expF.evaluate().isEmpty ? '-' : _code(t.widget<Icon>(expF).color),
              'exp': exp,
              'fold': '$fold',
              's': _f2(s),
              'cw': _f1(cw),
              'colW': _f1(colW),
              'leadD': _f1(leadW),
              'alignDy': _f2(alignDy),
              'h': _f1(cardR.height),
              'ovf': '${overflows.length}',
            };
          }

          void line(String sub, Map<String, String> m) {
            if (isAdmin) m['tbOvf'] = tbO == null ? '-' : '${tbO[sub]}';
            final keys = ['lead', 'leadBg', 'leadInk', 'border', 'bg', 'title', 'chev', 'tap', 'hit', 'vis', 'rowOk', 'foldOk', 'body', 'tog', 'togC', 'expC', 'exp', 'fold', 's',
              'cw', 'colW', 'leadD', 'alignDy', 'h', if (sub == 'refold') 'sameH', 'ovf', if (isAdmin) 'tbOvf'];
            _out('D420 $tok card $sub ${[for (final k in keys) '$k=${m[k]}'].join(' ')}');
            final want = _before ? _cardBefore : _cardStrict;
            final miss = [for (final e in want.entries) if (m[e.key] != e.value) '${e.key}=${m[e.key]}≠${e.value}'];
            must('$mode $sub 카드 기대', miss.isEmpty, '$miss');
            for (final k in ['tap', 'hit', 'vis', 'rowOk', 'foldOk']) {
              must('$sub $k', m[k] == 'true', '${m[k]}');
            }
            if (!_before) {
              final s = double.parse(m['s']!);
              must('$sub 원 지름 32·s', (double.parse(m['leadD']!) - 32 * s).abs() <= 0.5, '${m['leadD']} s=$s');
              must('$sub 원 중심 = 제목 첫 줄 중심(±1)', double.parse(m['alignDy']!).abs() <= 1.0, '${m['alignDy']}');
            }
            if (m['tog'] != '-') {
              final tw = _before ? _togBefore : _togStrict;
              must('$sub 토글 글 색', m['togC'] == tw.togC, '${m['togC']}');
              must('$sub 펼침 아이콘 색', m['expC'] == tw.expC, '${m['expC']}');
            }
            if (m['body'] != '-') must('$sub 설명 색', m['body'] == (_before ? _bodyBefore : _bodyStrict), '${m['body']}');
            if (!isAdmin) must('$sub 넘침 0(지원자 홈)', overflows.isEmpty, '$overflows');
            if (tbO != null) must('$sub 관리자 넘침 TA ${m['ovf']} ≤ 같은 실행 TB ${tbO[sub]}(F64-1 · shot 전)', int.parse(m['ovf']!) <= tbO[sub]!, '$overflows');
          }

          Future<void> ready(String what) async {
            await t.ensureVisible(card);
            await settle(4);
            final r = t.getRect(boxF);
            must('캡처 직전 $what 카드 ⊂ 본문 viewport ∩ 화면(같은 frame)', inR(bodyView(), r) && inR(screenR, r), '$r bv=${bodyView()}');
          }

          final m0 = probe();
          final firstH = double.parse(m0['h']!);
          line('init', m0);
          if (v.id == 'B') must('B 제목 접힘(토글 P6 전제 · 예측 비 ≥ 1.33)', m0['fold'] == 'true' && m0['tog'] == 'show' && m0['exp'] == 'false' && m0['body'] == '-', '$m0');
          await ready('기본');
          await shot('1card', m0['fold'] == 'true' ? '카드 기본(제목 접힘 · 설명 보기 · ${v.id})' : '카드 기본(설명 보임 · 토글 없음 · ${v.id})'); // [F64-4] 실제 fold 로
          if (m0['fold'] == 'true') {
            await t.tapAt(t.getCenter(togF));
            await settle(6);
            must('토글 탭 뒤 동의 화면 이동 0', find.byType(LegalConsentScreen).evaluate().isEmpty);
            final m1 = probe();
            line('body', m1);
            must('펼침: 설명 보임 · 토글 접기 · expanded', m1['body'] != '-' && m1['tog'] == 'hide' && m1['exp'] == 'true', '$m1');
            await ready('설명 펼침');
            await shot('2body', '설명 펼침(실제 설명 보기 탭)');
            await t.tapAt(t.getCenter(togF));
            await settle(6);
            final m2 = probe();
            m2['sameH'] ='${(double.parse(m2['h']!) - firstH).abs() <= 0.5}';
            line('refold', m2);
            must('재접기: 설명 숨김 · 토글 보기 · expanded false · 처음 높이', m2['body'] == '-' && m2['tog'] == 'show' && m2['exp'] == 'false' && m2['sameH'] == 'true', '$m2');
          } else {
            final m1 = probe();
            line('body', m1);
            must('W 설명 보임 · 토글 없음', m1['body'] != '-' && m1['tog'] == '-', '$m1');
            await ready('설명 보임(W 같은 장면)');
            await shot('2body', '설명 보임(W 토글 없음 — 1card 와 같은 장면 · lkit 뷰 곱)');
            final m2 = probe();
            m2['sameH'] = '${(double.parse(m2['h']!) - firstH).abs() <= 0.5}';
            line('refold', m2);
            must('W 재접기 단계 무변화', m2['sameH'] == 'true' && m2['tog'] == '-', '$m2');
          }
        } else {
          // ─────────────── V8 날짜 숫자 상자 ───────────────
          final group = find.byWidgetPredicate((w) => w is Semantics && w.properties.label == '일할 날짜 선택', skipOffstage: false);
          must('날짜 탐색 묶음 1', group.evaluate().length == 1, '${group.evaluate().length}');
          Finder cellF(DateTime d) => find.descendant(
              of: group,
              matching: find.byWidgetPredicate(
                  (w) => w is Semantics && w.properties.button == true && (w.properties.label ?? '').startsWith(_kDate(d)),
                  skipOffstage: false),
              skipOffstage: false);
          Finder boxOf(DateTime d) => find.descendant(of: cellF(d), matching: find.byType(AnimatedContainer, skipOffstage: false), skipOffstage: false);
          Finder digOf(DateTime d) =>
              find.descendant(of: cellF(d), matching: find.byWidgetPredicate((w) => w is Text && _vt(w) == '${d.day}', skipOffstage: false), skipOffstage: false);
          Rect stripView() {
            final hs = find.descendant(of: group, matching: find.byType(Scrollable, skipOffstage: false), skipOffstage: false).evaluate().toList();
            return hs.isEmpty ? t.getRect(group) : t.getRect(_el(hs.first));
          }

          Future<void> tapCell(DateTime d) async {
            final f = cellF(d);
            must('${_kDate(d)} 칸 1', f.evaluate().length == 1, '${f.evaluate().length}');
            await t.ensureVisible(f);
            await settle(4);
            await t.tapAt(t.getCenter(f));
            await settle(6);
          }

          Map<String, String> boxProbe(DateTime d, String p) {
            must('${d.day} 상자/숫자 1', boxOf(d).evaluate().length == 1 && digOf(d).evaluate().length == 1);
            final bw = t.widget<AnimatedContainer>(boxOf(d));
            final dec = bw.decoration;
            final fg = bw.foregroundDecoration;
            final filled = dec is BoxDecoration && dec.color == AppColors.brand;
            final outlined = fg is BoxDecoration && fg.border is Border && (fg.border! as Border).top.color == AppColors.brand;
            final s = (bw.constraints?.minWidth ?? 0) / 36;
            final pad = (bw.padding as EdgeInsets?)?.left ?? 0;
            final para = t.renderObject<RenderParagraph>(digOf(d));
            final tp = TextPainter(text: para.text, textScaler: para.textScaler, textDirection: TextDirection.ltr)..layout();
            final one = (para.size.height / tp.height).round() == 1 && para.size.width + 0.5 >= tp.width;
            final clip = para.size.height + 0.5 < tp.height;
            tp.dispose();
            final ts = para.text.style; // [F64-4] 실제 적용 스타일(문단 기준)
            // [F65-2] 패딩 비율 판정은 원 실수(pad/s)로 — 아래 PadR 는 표시(num2)일 뿐 되읽지 않는다.
            const padWant = 2.0; // [재개 · V8 철회] before · strict 모두 2·s
            must('${d.day} 미반올림 패딩 비율 = $padWant(±0.01 · 원 실수)', s > 0 && (pad / s - padWant).abs() <= 0.01, 'pad=$pad s=$s 비율=${s > 0 ? pad / s : double.nan}');
            final pr = t.getRect(digOf(d));
            final br = t.getRect(boxOf(d));
            final cr = t.getRect(find.ancestor(of: digOf(d), matching: find.byType(GestureDetector)).first);
            return {
              '${p}Deco': filled ? 'fill' : (outlined ? 'outline' : 'none'),
              '${p}PadK': s > 0 ? (pad / s).round().toString() : '-',
              '${p}PadR': s > 0 ? _f2(pad / s) : '-', // [F64-4 · F65-2] 비율 표시(num2) — 판정은 위 원 실수
              '${p}Fs': ts?.fontSize == null ? '-' : _f1(ts!.fontSize!),
              '${p}Fw': ts?.fontWeight == null ? '-' : ts!.fontWeight.toString().replaceAll('FontWeight.', ''),
              '${p}Ff': (ts?.fontFamily ?? '-').replaceAll(' ', '_'),
              '${p}Lh': ts?.height == null ? '-' : _f2(ts!.height!),
              '${p}Sc': _f2(para.textScaler.scale(10) / 10),
              '${p}ParaR': _rect(pr),
              '${p}BoxR': _rect(br),
              '${p}CellR': _rect(cr),
              '${p}InBox': '${inR(br, pr)}',
              '${p}InCell': '${inR(cr, br)}', // [F64-4] 칸 ⊃ 상자 4방향(±0.5)
              '${p}One': '$one',
              '${p}Clip': '$clip',
              '${p}BoxW': _f1(br.width),
              '${p}BoxH': _f1(br.height),
              '${p}CellW': _f1(cr.width),
              '${p}GapL': _f1(pr.left - br.left),
              '${p}GapR': _f1(br.right - pr.right),
            };
          }

          Future<void> ready(List<DateTime> days, String what) async {
            await t.ensureVisible(cellF(days.first));
            await settle(4);
            final sv = stripView(), bv = bodyView();
            final why = <String>[];
            for (final d in days) {
              for (final r in [t.getRect(boxOf(d)), t.getRect(digOf(d))]) {
                if (!(inR(sv, r) && inR(bv, r) && inR(screenR, r))) why.add('${d.day} $r sv=$sv bv=$bv');
              }
            }
            must('캡처 직전 $what 숫자 상자 · 숫자 띠 viewport ∩ 본문 viewport ∩ 화면 안(같은 frame)', why.isEmpty, '$why');
          }

          void boxLine(String sub, Map<String, String> m) {
            _out('D420 $tok box $sub ${[for (final e in m.entries) '${e.key}=${e.value}'].join(' ')}');
            const padK = '2'; // [재개 · V8 철회] before · strict 모두 2·s
            for (final p in [if (m.containsKey('tDeco')) 't', if (m.containsKey('sDeco')) 's']) {
              must('$sub $p 패딩 $padK·s', m['${p}PadK'] == padK, '${m['${p}PadK']}'); // 원 실수 판정은 boxProbe 안(F65-2)
              for (final k in ['InBox', 'InCell', 'One']) {
                must('$sub $p$k', m['$p$k'] == 'true', '${m['$p$k']}');
              }
              must('$sub $p 잘림 0', m['${p}Clip'] == 'false');
            }
            must('$sub 오늘 외곽선', m['tDeco'] == 'outline', '${m['tDeco']}');
            if (m.containsKey('sDeco')) must('$sub 선택 채움', m['sDeco'] == 'fill', '${m['sDeco']}');
            must('$sub 넘침 0', overflows.isEmpty, '$overflows');
          }

          await t.ensureVisible(group);
          await settle(4);
          boxLine('init', boxProbe(_today, 't'));
          await ready([_today], '오늘');
          await shot('1init', '오늘 미선택 외곽선(숫자 상자 안쪽 여백)');
          await tapCell(_day(2));
          boxLine('other', {...boxProbe(_today, 't'), ...boxProbe(_day(2), 's')});
          await ready([_today, _day(2)], '오늘 · 선택 모레');
          await shot('2other', '다른 날(모레) 선택 채움 · 오늘 외곽선');
        }

        final exc = t.takeException();
        final tbD = !isAdmin ? '' : ' tbOverflows=${tbDone ?? '-'}';
        _out('D420 $tok done state=${st.key} mode=$mode captures=$captures overflows=${overflows.length} exc=${exc != null} ovfRaw=${_b64(overflows)}$tbD');
        if (tbDone != null) must('done 관리자 넘침 TA ${overflows.length} ≤ 같은 실행 TB $tbDone(F64-1 · RG 전)', overflows.length <= tbDone, '$overflows');
        await t.pumpWidget(const SizedBox.shrink());
        await settle(4);
        expect(exc, isNull);
        if (!isAdmin) expect(overflows, isEmpty, reason: '$tok 넘침');
        } catch (_) {
          _anyFail = true; // [F64-2] 뒤 사례는 본문 실행 0
          rethrow;
        }
      });
    }
  }
}
