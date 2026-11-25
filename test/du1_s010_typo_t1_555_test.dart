// ignore_for_file: depend_on_referenced_packages
// [DU555 · PP-TYPOGRAPHY-20261120 시범 T1] DU-S010 관리자 홈(BusinessAdminHomeScreen) 글자 역할 — 운영 머리 · Hero 카드 · 섹션 머리 · 오늘의 근무 · 처리할 일 · 다가오는 근무.
//   판정 = reports/DU_typography_independent_review_decision_2026-11-20.md §5 역할표 · §6.2 T1 · §6.3(W/B/N) · §7.
//   before = 현재 A(business_admin_home_screen 04685f27 · app_text_styles df39ef94) 기록 전용 · strict = 후보(4138bee9 화면 + 0ad2d600 AppTextStyles · r2 2파일 판 9 역할 · 감사147 R-1–R-7).
//   하네스 = DU526(du1_o002_close48_526_test.dart) 의 홈 부분 그대로(_FakeCore · _Owner · _Wire · _NoHttp · setUpAll · AdminHomeReads 주입 · 글자 배율 builder) —
//     대역 값 = CP04(du_concept_cp04_admin_home_test.dart) ownerSingle · ownerMulti · partial 과 DU307 G5(StaffingReadinessModel.empty) 의 같은 꼴 값. 예외 · 지연 주입 0.
//   측정(읽기만) = 역할 글마다 실제 TextStyle 서명(크기/줄 높이/굵기/자간/색) · 글꼴 · 전문 · 줄 제한/말줄임 · 낱말 안 끊김(du_word_break) · 넘침 ·
//     읽기 순서(y) · 그룹 간격 · 행동 받는 자리 화면 안/중심 hit/48(DU537 · DU538 r2 · DU552 _tapNow · ensureVisible).
//   누르는 것 0 · 입력 0 · 끌기 0(ensureVisible 만) · 업무 writer 0. 기본 skip — TB before/du555-tb/DU_BEFORE_OBSERVE=555 · TA after/du555-ta/없음.
import 'dart:convert';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
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
import 'package:ALfit/models/core/legal_readiness.dart';
import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/models/ui/admin_home_summary_model.dart';
import 'package:ALfit/models/ui/staffing_readiness_model.dart';
import 'package:ALfit/providers/notification_provider.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/screens/business_admin/admin_home_reads.dart';
import 'package:ALfit/screens/business_admin/business_admin_home_screen.dart';
import 'package:ALfit/services/business_posting_readiness.dart';
import 'package:ALfit/theme/app_colors.dart';
import 'package:ALfit/theme/role_theme.dart';
import 'package:ALfit/utils/format_helper.dart';

import 'support/du1_vq_capture.dart';
import 'support/du_word_break.dart';
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

const _biz1 = 'biz1';
const _biz2 = 'biz2';
const _bizName = '강남 물류센터';
const _longBiz = '강남구 테헤란로 제2물류센터 야간 상하차 전용 창고'; // CP04 · CP01 인계 긴 사업장
const _longWork = '냉장·냉동 식품 분류 및 출고 검수 보조'; // DU526 긴 업무

/// 소유자(BUSINESS_ADMIN) — 홈(CP04 _Owner)과 창(ARO _Owner · PCL _AdminP)이 실제로 부르는 판정을 허용으로 준다.
///   창은 `canForBusiness`(private _currentUser 를 읽는다) · `watchBusinessPermissions` 를 부르므로 둘 다 대역에서 답한다.
class _Owner extends UserProvider {
  _Owner({this.bizIds = const [_biz1]});
  final List<String> bizIds;
  final watched = <String>[];
  @override
  UserModel? get currentUser => UserModel(
      uid: 'admin1', username: 'admin1', name: '김관리', email: 'admin1@alfit.local',
      role: UserRole.BUSINESS_ADMIN, managedBusinessIds: bizIds, sealBase64: 'seal');
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
  @override
  bool canForBusiness(String businessId, bool Function(MemberPermissions p) check) => true;
  @override
  PermissionCheck checkForBusiness(String businessId, bool Function(MemberPermissions p) check) => PermissionCheck.allowed;
  @override
  VoidCallback watchBusinessPermissions(String businessId) {
    watched.add(businessId);
    return () {};
  }
}

// ── 고정 시각(KST) — DU1_VQ_DATE 날의 10:00 (CP04 와 같은 산식) ──
final DateTime _clock = () {
  final k = vqNow().toUtc().add(const Duration(hours: 9));
  return DateTime.utc(k.year, k.month, k.day, 10).subtract(const Duration(hours: 9));
}();
final DateTime _today = FormatHelper.toKstDate(_clock);

/// 오늘 + [o] 일의 'YYYY-MM-DD'(CP04 _ymd 와 같다).
String _ymd(int o) {
  final d = _today.add(Duration(days: o));
  return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

BusinessModel _business(String id, String name) => BusinessModel(
    id: id, name: name, ownerId: 'admin1', businessNumber: '000-00-00000', address: '서울시 어딘가',
    category: '물류', subCategory: '창고', isApproved: true, createdAt: DateTime(2026, 1, 1));

Map<String, dynamic> _biz(String id, String name, int req, int conf, int short) =>
    {'businessId': id, 'businessName': name, 'requiredCount': req, 'confirmedCount': conf, 'shortageCount': short};

/// 날짜 한 날(CP04 _day 와 같은 CF 직렬화 모양 · 파싱은 production).
Map<String, dynamic> _day(int o, int req, int conf, int short, {int? pending, List<Map<String, dynamic>> byBusiness = const []}) => {
      'date': _ymd(o), 'requiredCount': req, 'confirmedCount': conf, 'shortageCount': short,
      if (pending != null) 'pendingCount': pending, 'pendingAvailable': pending != null, 'byBusiness': byBusiness,
    };

StaffingReadinessModel _staffing(List<Map<String, dynamic>> days, {bool partial = false, int failed = 0}) =>
    StaffingReadinessModel(
        available: true, partial: partial, failedBusinessCount: failed, publishedPostingCount: 1,
        days: days.map(StaffingDayData.fromMap).toList());

class _Template extends Fake implements ContractTemplateModel {
  @override
  bool get isSupportedForNewUse => true;
}

Map<String, BusinessPostingReadiness> _ready(List<BusinessModel> bizs) => {
      for (final b in bizs)
        b.id: BusinessPostingReadiness(
            bizId: b.id, isApproved: true, hasCanonicalLicense: true, hasOwnerLegacyLicense: false,
            hasActiveWorkTypes: true, hasEmployerSeal: true),
    };

/// 할 일 canonical(CF 직렬화 모양 그대로 — 모델 파싱은 production).
AdminHomeSummaryModel _summary({
  int resign = 0, int? manual, int soon = 0, int approval = 0, int approvalOverdue = 0, int schedule = 0,
  int unsent = 0, int unclosed = 0, String? oldest, int settlement = 0, int wageChange = 0,
  int unpaid = 0, int unpaidOverdue = 0, int missing = 0, int expiring = 0, int expired = 0,
  Set<String> unavailable = const {},
}) {
  Map<String, dynamic> s(String key, int count) => {
        'available': !unavailable.contains(key), 'count': count,
        'byBusiness': [{'businessId': _biz1, 'count': count}],
      };
  return AdminHomeSummaryModel.fromMap({
    'actions': {
      'resignRequest': {...s('resign', resign), 'soonCount': soon, 'manualReviewCount': manual},
      'approval': {...s('approval', approval), 'overdueCount': approvalOverdue},
      'scheduleChangeRequest': s('schedule', schedule),
      'unsentContract': s('unsent', unsent),
      'unclosed': {...s('unclosed', unclosed), 'oldestDate': oldest},
      'settlementRequest': s('settlement', settlement),
      'wageChangeRequest': s('wageChange', wageChange),
      'unpaidWage': {
        ...s('unpaid', unpaid), 'overdueCount': unpaidOverdue, 'missingDueDateCount': missing,
        'byBusiness': [{'businessId': _biz1, 'count': unpaid, 'missingDueDateCount': missing}],
      },
    },
    'upcoming': {
      'expiringContract': {...s('expiring', expiring), 'upcomingCount': expiring - expired, 'expiredCount': expired},
    },
  });
}

ApplicationModel _app(String id, String bizId, String bizName, String work, String start, String end) => ApplicationModel(
    id: id, toId: 'to_$id', uid: 'w_$id', businessId: bizId, businessName: bizName, toTitle: '단기 공고',
    status: AppStatus.confirmed, selectedWorkType: work, startTime: start, endTime: end, wage: 12000, wageType: 'hourly',
    workDate: _today, appliedAt: _today.subtract(const Duration(days: 3)));

/// 출근 기록 — 오늘 해당 근무 시작에 출근(검토 대상이 되지 않게).
AttendanceModel _checkedIn(ApplicationModel a) {
  final h = int.parse(a.startTime.split(':').first);
  return AttendanceModel(
    id: 'att_${a.id}', applicationId: a.id, userId: a.uid, businessId: a.businessId, businessName: a.businessName,
    workDate: _today, workType: a.selectedWorkType, status: AttendanceModel.statusPresent,
    wageStatus: AttendanceModel.wagePending, adminConfirmed: false,
    checkInAt: DateTime.utc(_today.year, _today.month, _today.day, h).subtract(const Duration(hours: 9)),
    checkOutAt: null, createdAt: _today,
  );
}

typedef _Fx = ({
  List<String> bizIds,
  List<BusinessModel> businesses,
  StaffingReadinessModel staffing,
  AdminHomeSummaryModel summary,
  List<ApplicationModel> roster,
});

/// 상태별 대역 — 각 사례가 새로 만든다(공유 상태 0). 값 꼴 = CP04 ownerSingle · ownerMulti · partial · DU307 G5.
_Fx _fixture(String id) {
  final single = [_business(_biz1, _bizName)];
  final multi = [_business(_biz1, _bizName), _business(_biz2, _longBiz)];
  List<ApplicationModel> three(String bizName, String work) => [
        _app('r1', _biz1, bizName, work, '09:00', '18:00'),
        _app('r2', _biz1, bizName, work, '09:00', '18:00'),
        _app('r3', _biz1, bizName, work, '09:00', '18:00'),
      ];
  switch (id) {
    case 'NORM': // CP04 ownerSingle 그대로
      return (
        bizIds: const [_biz1],
        businesses: single,
        staffing: _staffing([_day(0, 5, 3, 2), _day(1, 3, 2, 1, pending: 2), _day(3, 2, 2, 0)]),
        summary: _summary(resign: 1, manual: 1, soon: 1, approval: 3, approvalOverdue: 1, schedule: 2, unsent: 1,
            unclosed: 4, oldest: '2026-11-03'),
        roster: three(_bizName, '피킹'),
      );
    case 'LONG': // CP04 ownerMulti 대역 + CP04 partial 의 부분 실패 값(2곳 중 1곳)
      return (
        bizIds: const [_biz1, _biz2],
        businesses: multi,
        staffing: _staffing([
          _day(0, 8, 5, 2, byBusiness: [_biz(_biz1, _bizName, 3, 3, 0), _biz(_biz2, _longBiz, 5, 2, 2)]),
          _day(2, 4, 1, 3, pending: 1, byBusiness: [_biz(_biz1, _bizName, 2, 1, 1), _biz(_biz2, _longBiz, 2, 0, 2)]),
        ], partial: true, failed: 1),
        summary: _summary(settlement: 1, wageChange: 1, unpaid: 2, unpaidOverdue: 1, missing: 1, expiring: 3, expired: 1),
        roster: [
          _app('m1', _biz1, _bizName, '피킹', '09:00', '18:00'),
          _app('m2', _biz2, _longBiz, '포장', '09:30', '13:30'),
        ],
      );
    case 'QUIET': // 부족 0 · 할 일 0 · 긴 사업장 + 긴 업무 하나
      return (
        bizIds: const [_biz1],
        businesses: [_business(_biz1, _longBiz)],
        staffing: _staffing([_day(0, 3, 3, 0), _day(2, 2, 2, 0)]),
        summary: _summary(),
        roster: three(_longBiz, _longWork),
      );
    default: // ERR — DU307 G5(인력 완전 실패 · 서버 빈 모양) + CP04 partial 의 할 일 미확인 1
      return (
        bizIds: const [_biz1],
        businesses: single,
        staffing: StaffingReadinessModel.empty(),
        summary: _summary(approval: 1, unavailable: const {'unsent'}),
        roster: three(_bizName, '피킹'),
      );
  }
}

AdminHomeReads _homeReads(_Fx fx, Map<String, int> calls) {
  void hit(String k) => calls[k] = (calls[k] ?? 0) + 1;
  return AdminHomeReads(
    summary: ({String? selectedBusinessId}) {
      hit('summary');
      return Future.value(fx.summary);
    },
    businessesByIds: (ids) async {
      hit('businesses');
      return fx.businesses;
    },
    staffingReadiness: ({String? selectedBusinessId}) {
      hit('staffing');
      return Future.value(fx.staffing);
    },
    attendanceByDate: ({required String businessId, required DateTime date}) async {
      hit('attendance');
      return [for (final a in fx.roster) if (a.businessId == businessId) _checkedIn(a)];
    },
    confirmedWorkers: ({required DateTime date, required String businessId}) async {
      hit('roster');
      return [for (final a in fx.roster) if (a.businessId == businessId) a];
    },
    workDetailTimes: (_) async => <String, dynamic>{},
    postingReadiness: (bizs) async => _ready(bizs),
    contractTemplates: (_) async => <ContractTemplateModel>[_Template()],
    tourCompleted: () => Future<bool>.value(true),
    clock: () => _clock,
    legalReadiness: () async => const LegalReadiness(status: LegalReadinessStatus.current),
  );
}

/// [F120-3 · DU508 r3 와 같은 축] CF Pigeon 채널 — 이 화면은 주입 읽기만 쓰므로 호출 0 이어야 한다(쓰기 callable 포함).
const _cfChannel = 'dev.flutter.pigeon.cloud_functions_platform_interface.CloudFunctionsHostApi.call';

/// [ARO setUpAll 과 같다] 창이 FirebaseAuth.instance.currentUser(:658)를 처음 읽을 때 등록하는 두 리스너 채널과 그 이벤트 채널.
const _authBase = 'dev.flutter.pigeon.firebase_auth_platform_interface.FirebaseAuthHostApi.';
const _authFake = 'du555.fake.auth.';

/// [r1 · DU515 판정 §3-2] Auth 는 **정확히** 이 두 등록 채널과 그 두 이벤트 채널의 listen/cancel 만 허용한다(접두어 허용 0).
const _authListeners = ['registerIdTokenListener', 'registerAuthStateListener'];

/// [r1 · 판정 §3-2] 허용하는 Flutter 기반 채널과 이유 — 그 밖의 'flutter/*' 도 예상 밖으로 막는다.
const _frameworkAllow = <String, String>{
  'flutter/assets': 'AssetBundle(아이콘 글꼴 · 이미지 매니페스트) 읽기',
  'flutter/platform': 'MaterialApp Title(SystemChrome.setApplicationSwitcherDescription) · SystemSound/Haptic(InkWell 탭 피드백)',
  'flutter/navigation': '루트 Navigator 경로 보고(SystemNavigator.routeInformationUpdated · showDialog push/pop)',
  'flutter/mousecursor': 'MouseRegion 커서 갱신(시험 포인터)',
  'flutter/restoration': 'RootRestorationScope 상태 복원 조회',
  'flutter/keyboard': 'HardwareKeyboard 상태 동기화',
  'flutter/accessibility': '의미 트리/알림 전달(시험은 ensureSemantics 하지 않음 · 생기면 기록)',
};

/// 모든 플랫폼 메시지 관찰 — 허용 Flutter 기반 채널은 원래 경로(센다) · Auth 정확 허용은 setUpAll 모의로(센다) ·
///   CF · 그 밖(Firestore · 저장소 · 허용 밖 flutter/*)은 이름을 기록하고 막는다(응답 null) · **막는 순간 tripped**(후속 UI 조작 중단).
class _Wire {
  final unexpected = <String>[];
  final cf = <String>[];
  final framework = <String, int>{};
  final auth = <String>[];
  var tripped = false;

  Future<ByteData?>? route(TestDefaultBinaryMessenger m, String channel, MessageHandler? handler, ByteData? message) {
    if (channel == _cfChannel) {
      cf.add(channel);
      tripped = true;
      return null;
    }
    for (final name in _authListeners) {
      if (channel == '$_authBase$name') {
        auth.add('register:$name');
        return handler?.call(message);
      }
      if (channel == '$_authFake$name') {
        String method;
        try {
          method = const StandardMethodCodec().decodeMethodCall(message).method;
        } catch (_) {
          method = '?';
        }
        if (method == 'listen' || method == 'cancel') {
          auth.add('$method:$name');
          return handler?.call(message);
        }
        unexpected.add('$channel#$method');
        tripped = true;
        return null;
      }
    }
    if (_frameworkAllow.containsKey(channel)) {
      framework.update(channel, (x) => x + 1, ifAbsent: () => 1);
      return handler != null ? handler(message) : m.delegate.send(channel, message);
    }
    unexpected.add(channel);
    tripped = true;
    return null;
  }
}

/// [F120-3] 외부 HTTP 차단 — 만들려는 시도를 기록하고 실패시킨다(끝에 0 단언).
class _NoHttp extends HttpOverrides {
  _NoHttp(this.wire);
  final _Wire wire;
  final tries = <String>[];

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    tries.add('createHttpClient');
    wire.tripped = true;
    throw const SocketException('DU555 관측 — 외부 HTTP 차단');
  }
}

Future<void> _loadFonts() async {
  Future<ByteData> b(String p) => File(p).readAsBytes().then((x) => ByteData.view(x.buffer));
  for (final fam in const ['NotoSansKR', 'Roboto']) {
    await (FontLoader(fam)
          ..addFont(b('assets/fonts/NotoSansKR-Regular.ttf'))
          ..addFont(b('assets/fonts/NotoSansKR-Bold.ttf')))
        .load();
  }
  await (FontLoader('FlutterTest')..addFont(b('assets/fonts/NotoSansKR-Regular.ttf'))).load();
  await (FontLoader('MaterialIcons')
        ..addFont(b('C:/Users/kug02/flutter/bin/cache/artifacts/material_fonts/materialicons-regular.otf')))
      .load();
}

void _out(String s) {
  // ignore: avoid_print
  print(s);
}

String _enc(String s) => s.isEmpty ? '-' : base64Url.encode(utf8.encode(s)).replaceAll('=', '');
/// [a] 가 [b] **안**에 있는가(겹침이 아니라 포함 · 0.5px 허용 — DU508 r3 와 같다).
bool _inside(Rect a, Rect b) => a.left >= b.left - 0.5 && a.top >= b.top - 0.5 && a.right <= b.right + 0.5 && a.bottom <= b.bottom + 0.5;

/// 시각 오류 수집 — 넘침은 원문 전체 + 위치 두 줄, 그 밖 framework 오류도 원문 전체(DU516 r1 과 같다).
class _Seen {
  final overflows = <String>[];
  final other = <String>[];

  void add(FlutterErrorDetails d) {
    final m = d.exceptionAsString();
    if (m.contains('overflowed')) {
      final full = d.toString();
      final k = full.indexOf('The relevant error-causing widget was');
      final loc = k < 0
          ? ''
          : full.substring(k).split('\n').skip(1).where((l) => l.trim().isNotEmpty).take(2).map((l) => l.trim()).join(' ');
      overflows.add('${m.split('\n').first} @ $loc\n$m');
    } else {
      other.add(m);
    }
  }
}

/// 요소 하나가 끌기 없이 보이고 눌리는가 — 창 상자 ∩ 화면(∩ 가까운 Scrollable 이 있으면 그 칸) 안 + 중심 hit(DU537 · DU538 r2 · DU540 · DU543 r3 · DU548 · DU551 `_tapNow` 와 같은 식).
({bool vis, bool hit, bool min48, Rect r}) _tapNow(WidgetTester t, Finder f, Finder dlg, Rect screen) {
  final boxF = find.descendant(of: dlg, matching: find.byType(Dialog), skipOffstage: true);
  var area = boxF.evaluate().isEmpty ? screen : t.getRect(boxF.first).intersect(screen);
  final scF = find.ancestor(of: f, matching: find.byType(Scrollable));
  final nSc = scF.evaluate().length;
  if (nSc > 0) area = area.intersect(t.getRect(scF.first));
  final r = t.getRect(f);
  final vis = _inside(r, area);
  final hit = t.hitTestOnBinding(r.center).path.any((x) => identical(x.target, t.renderObject(f)));
  final min48 = r.width >= 48 - 0.01 && r.height >= 48 - 0.01;
  return (vis: vis, hit: hit, min48: min48, r: r);
}

// ── 글자 역할 측정(읽기만) ──

/// 홈 안 화면 글(Text 위젯) — 의미 이름이 [s] 이거나, 의미 이름이 없으면 보이는 글(표시 제어 문자 제거)이 [s] 인 것. 화면 밖 포함.
///   find.text 는 EditableText 도 센다 — Text 위젯만 본다.
Finder _textOf(Finder home, String s) => find.descendant(of: home, skipOffstage: false,
    matching: find.byWidgetPredicate(
        (w) => w is Text && (w.semanticsLabel == s || (w.semanticsLabel == null && visibleText(w.data ?? '') == s)),
        skipOffstage: false));

/// [f] 의 Text 위젯마다 그 안 RichText 문단 — Text 하나에 문단이 정확히 1 이 아니면 그 Text 는 뺀다(개수는 raw 에 남는다).
List<RenderParagraph> _parasOf(Finder f) {
  final out = <RenderParagraph>[];
  for (final e in f.evaluate()) {
    final rps = <RenderParagraph>[];
    void visit(Element x) {
      final ro = x.renderObject;
      if (x.widget is RichText && ro is RenderParagraph) rps.add(ro);
      x.visitChildren(visit);
    }
    e.visitChildren(visit);
    if (rps.length == 1) out.add(rps.first);
  }
  return out;
}

/// 배경색이 [bg] 인 Container(알약 · 배지) 안 문단 — 전문 기준은 그 문단 자신의 보이는 글.
List<(RenderParagraph, String)> _inBox(Finder home, Color bg) {
  final boxes = find.descendant(of: home, skipOffstage: false,
      matching: find.byWidgetPredicate(
          (w) => w is Container && w.decoration is BoxDecoration && (w.decoration! as BoxDecoration).color == bg,
          skipOffstage: false));
  final out = <(RenderParagraph, String)>[];
  for (final e in boxes.evaluate()) {
    void visit(Element x) {
      final ro = x.renderObject;
      if (x.widget is RichText && ro is RenderParagraph) out.add((ro, visibleText(ro.text.toPlainText())));
      x.visitChildren(visit);
    }
    e.visitChildren(visit);
  }
  return out;
}

/// 글 조각별 실제 스타일 — 조상 스타일부터 차례로 merge(Text = 기본 글 스타일과 합친 하나 · Text.rich = 조각마다). 빈 조각은 뺀다.
List<(String, TextStyle)> _spansOf(RenderParagraph rp) {
  final out = <(String, TextStyle)>[];
  void walk(InlineSpan s, TextStyle eff) {
    final e = s.style == null ? eff : eff.merge(s.style);
    if (s is TextSpan) {
      final tx = s.text;
      if (tx != null && tx.isNotEmpty) out.add((tx, e));
      for (final ch in s.children ?? const <InlineSpan>[]) {
        walk(ch, e);
      }
    }
  }
  walk(rp.text, const TextStyle());
  return out;
}

/// 스타일 서명 '크기/줄 높이/굵기/자간/색' — 크기 · 자간 소수 1 · 줄 높이 소수 2 · 굵기 값 · ARGB 8자리(없으면 n).
String _sig(TextStyle s) {
  String n(double? x, int d) => x == null ? 'n' : x.toStringAsFixed(d);
  final c = s.color;
  return [
    n(s.fontSize, 1),
    n(s.height, 2),
    s.fontWeight == null ? 'n' : s.fontWeight!.value.toString(),
    n(s.letterSpacing, 1),
    c == null ? 'n' : c.toARGB32().toRadixString(16).padLeft(8, '0'),
  ].join('/');
}

/// 칸 하나의 서명 집합 — 글 조각 서명을 모아 정렬 · '|'. [bold] null = 전부 · true = 굵기 700 만 · false = 700 아닌 것만. 없으면 '-'.
String _sigsOf(List<(RenderParagraph, String)> ps, {bool? bold}) {
  final out = <String>{};
  for (final (p, _) in ps) {
    for (final (_, st) in _spansOf(p)) {
      if (bold == null || bold == (st.fontWeight == FontWeight.w700)) out.add(_sig(st));
    }
  }
  final l = out.toList()..sort();
  return l.isEmpty ? '-' : l.join('|');
}

/// 문단의 줄 수 — 전체 선택 상자의 윗변이 1px 넘게 달라지는 횟수.
int _linesOf(RenderParagraph rp) {
  final n = rp.text.toPlainText().length;
  if (n == 0) return 0;
  final tops = <double>[];
  for (final b in rp.getBoxesForSelection(TextSelection(baseOffset: 0, extentOffset: n))) {
    if (tops.every((x) => (x - b.top).abs() > 1)) tops.add(b.top);
  }
  return tops.length;
}

typedef _Fit = ({int ex, int cut, int wb, int full, int lines});

/// 문단 하나 — 줄 제한 넘음(didExceedMaxLines) · 줄 제한/말줄임 설정 · 피할 수 있는 낱말 안 끊김(공용 판정기) · 전문 불일치 · 줄 수.
_Fit _fitOf(RenderParagraph rp, String show) => (
      ex: rp.didExceedMaxLines ? 1 : 0,
      cut: rp.maxLines != null || rp.overflow == TextOverflow.ellipsis ? 1 : 0,
      wb: wordBreaks(rp).where((x) => !x.forced).length,
      full: visibleText(rp.text.toPlainText()) == show ? 0 : 1,
      lines: _linesOf(rp),
    );

Rect _rectOf(RenderParagraph rp) => MatrixUtils.transformRect(rp.getTransformTo(null), Offset.zero & rp.size);

const _wd = ['월', '화', '수', '목', '금', '토', '일'];

/// 운영 머리 날짜(홈 _buildOpsHead 와 같은 식 — 주입 clock 의 KST 날짜).
final String _dateText = '${_today.month}월 ${_today.day}일 ${_wd[_today.weekday - 1]}요일';

/// 다가오는 근무 날짜 이름(홈 _futureDateLabel 과 같은 식 — 내일이면 '내일').
String _fut(int o) {
  final d = _today.add(Duration(days: o));
  return o == 1 ? '내일' : FormatHelper.formatDate(DateTime(d.year, d.month, d.day));
}

(String, String) _a(String s) => (s, s);

/// 상태별 역할 칸 → (찾을 글 = 의미 이름 또는 보이는 글, 보여야 할 전문). 'staff' = 오늘 인원 요약 줄(수량 sq · 라벨 sl 로 나눈다).
///   알약 · 배지(np · kp)는 배경색 상자로 찾는다(_inBox). 없는 칸은 비운다('-').
Map<String, List<(String, String)>> _anchorsOf(String id) {
  final common = <String, List<(String, String)>>{
    'hd': [_a('오늘 운영을 한눈에')],
    'dt': [_a(_dateText)],
    'ad': [('공고 등록', '+ 공고 등록')],
    'st': [_a('오늘의 근무'), _a('처리할 일'), _a('다가오는 근무')],
    'su': [_a('앞으로 7일')],
    'sa': [_a('명단 보기')],
  };
  switch (id) {
    case 'NORM':
      return {
        ...common,
        'wt': [_a('피킹 · 09:00–18:00')],
        'staff': [_a('5명 중 3명 확정')],
        'sv': [_a('인원 현황 보기')],
        'at': [('출근 3명, 현재까지 출근 대상 3명', '출근 3/3')],
        'fd': [_a('내일'), _a(_fut(3))],
        'fx': [_a('3명 중 2명 확정 · 지원 대기 2건'), _a('2명 전원 확정')],
        'fn': [_a('1명 추가 필요')],
        'kt': [_a('퇴사 요청'), _a('지원 검토'), _a('일정 변경 요청'), _a('계약 미발송'), _a('마감 필요')],
        'kd': [
          _a('퇴사 요청 1건을 검토해 주세요'), _a('대기 중인 지원 3건을 확인해 주세요'), _a('근로자의 일정 변경 요청 2건이 있어요'),
          _a('발송이 필요한 계약 1건이 있어요'), _a('사업장별 미마감 근무일 합계 4일이에요'),
        ],
        'ks': [_a('수동 검토 1건'), _a('빠른 검토 필요 1건'), _a('긴급 1건'), _a('가장 오래된 날 2026.11.03')],
      };
    case 'LONG':
      return {
        ...common,
        'staff': [_a('8명 중 5명 확정')],
        'cx': [_a('확정 근무 · 업무 2개 · 시간대 2개')],
        'wh': [_a(_longBiz)],
        'sn': [_a('필요·확정 인원과 추가 필요 인원은 집계 기준이 달라요')],
        'sv': [_a('인원 현황 보기')],
        'at': [('출근 2명, 현재까지 출근 대상 2명', '출근 2/2')],
        'pm': [_a('사업장 1곳의 정보를 불러오지 못해 나머지 사업장 기준으로 표시했어요')],
        'rt': [_a('다시 시도')],
        'fd': [_a(_fut(2))],
        'fx': [_a('4명 중 1명 확정 · 강남 물류센터 외 1곳 · 지원 대기 1건')],
        'fn': [_a('3명 추가 필요')],
        'kt': [_a('이체 대기'), _a('중간정산 요청'), _a('급여 변경 요청'), _a('계약 확인 필요')],
        'kd': [
          _a('이체 확인이 필요한 급여 3건이 있어요'), _a('대기 중인 중간정산 요청 1건이 있어요'), _a('지급방식 변경 요청 1건을 확인해 주세요'),
          _a('연장·종료를 정할 계약 3건을 확인해 주세요'),
        ],
        'ks': [_a('연체 1건'), _a('지급일 확인 필요 1건'), _a('만료 후 미결정 1건')],
      };
    case 'QUIET':
      return {
        ...common,
        'hm': [_a('오늘 근무 현황이에요')],
        'hs': [_a('$_longBiz · $_longWork · 09:00–18:00')],
        'wt': [_a('$_longWork · 09:00–18:00')],
        'staff': [_a('3명 전원 확정')],
        'at': [('출근 3명, 현재까지 출근 대상 3명', '출근 3/3')],
        'fd': [_a(_fut(2))],
        'fx': [_a('2명 전원 확정')],
        're': [_a('처리할 업무가 없어요')],
      };
    default:
      return {
        ...common,
        'hm': [_a('오늘 상황을 확인하지 못했어요')],
        'hs': [_a('인력 정보를 불러오지 못했어요')],
        'at': [('출근 3명, 현재까지 출근 대상 3명', '출근 3/3')],
        'er': [_a('향후 인력 현황을 불러오지 못했어요')],
        'pn': [_a('일부 업무 상태를 확인하지 못했어요')],
        'rt': [_a('다시 시도')],
        'kt': [_a('지원 검토')],
        'kd': [_a('대기 중인 지원 1건을 확인해 주세요')],
      };
  }
}

/// 상태별 행동 받는 자리(보이는 글 · 같은 글의 몇 번째) — 그 글의 가장 가까운 GestureDetector(InkWell 도 안에 GestureDetector 를 만든다).
List<(String, int)> _ctasOf(String id) => switch (id) {
      'NORM' => [('공고 등록', 0), ('명단 보기', 0), ('인원 현황 보기', 0), ('퇴사 요청', 0), ('내일', 0)],
      'LONG' => [('공고 등록', 0), ('명단 보기', 0), ('인원 현황 보기', 0), ('다시 시도', 0), ('다시 시도', 1), ('이체 대기', 0), (_fut(2), 0)],
      'QUIET' => [('공고 등록', 0), ('명단 보기', 0), (_fut(2), 0)],
      _ => [('공고 등록', 0), ('명단 보기', 0), ('다시 시도', 0), ('다시 시도', 1), ('다시 시도', 2), ('다시 시도', 3), ('지원 검토', 0)],
    };

typedef _V = ({String id, double w, double h, double s});
const _views = <_V>[(id: 'W', w: 390.0, h: 844.0, s: 1.0), (id: 'B', w: 320.0, h: 640.0, s: 2.0), (id: 'N', w: 320.0, h: 640.0, s: 1.0)];
const _cases = <({String id, int shots})>[(id: 'NORM', shots: 3), (id: 'LONG', shots: 3), (id: 'QUIET', shots: 3), (id: 'ERR', shots: 3)];

final bool _before = Platform.environment['DU_BEFORE_OBSERVE'] == '555';
final Map<String, String> _env = Platform.environment;
final bool _optIn =
    (_env['DU1_VQ_PHASE'] == 'before' && _env['DU1_VQ_RUN'] == 'du555-tb' && _env['DU_BEFORE_OBSERVE'] == '555') ||
        (_env['DU1_VQ_PHASE'] == 'after' && _env['DU1_VQ_RUN'] == 'du555-ta' && _env['DU_BEFORE_OBSERVE'] == null);
/// 첫 실패 뒤 사례는 본문에 들어가지 않는다(진입 0 · 캡처 0).
String? _halt;
final String _manifest = Platform.environment['DUL_MANIFEST'] ?? '(unset)';
const _envKeys = ['DU_BEFORE_OBSERVE', 'DU1_VQ_PHASE', 'DU1_VQ_OUT', 'DU1_VQ_RUN', 'DU1_VQ_DATE', 'DU397_DIAG', 'DU397_MANIFEST', 'DU400_MANIFEST',
  'DU401_MANIFEST', 'DU398_MANIFEST', 'DU406_MANIFEST', 'DU407_MANIFEST', 'DU296_PHASE', 'DUL_MANIFEST'];
final String _envLine = [for (final k in _envKeys) '$k:${Platform.environment[k] ?? '(unset)'}'].join(',');

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  setUpAll(() async {
    // [r1 · F2] guard 를 초기화보다 먼저 건다 — Firebase 초기화 · 날짜 자료 · 글꼴 · 인증 모의 설치 동안의 채널 · HTTP 도 센다(DU515 r3 와 같다).
    final m = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final wire = _Wire();
    final net = _NoHttp(wire);
    final prevAll = m.allMessagesHandler;
    final prevHttp = HttpOverrides.current;
    m.allMessagesHandler = (channel, handler, message) => wire.route(m, channel, handler, message);
    HttpOverrides.global = net;
    try {
      FirebasePlatform.instance = _FakeCore();
      await Firebase.initializeApp();
      await initializeDateFormatting('ko_KR');
      await _loadFonts();
      // [ARO setUpAll] FirebaseAuth 생성 때의 두 listener 등록 채널 모의(이벤트 0 · 로그인 상태 불변).
      const codec = StandardMessageCodec();
      for (final name in _authListeners) {
        m.setMockMessageHandler('$_authBase$name', (_) async => codec.encodeMessage(<Object?>['$_authFake$name']));
        m.setMockMethodCallHandler(MethodChannel('$_authFake$name'), (_) async => null);
      }
    } finally {
      m.allMessagesHandler = prevAll;
      HttpOverrides.global = prevHttp;
    }
    final nCf = wire.cf.length;
    final nUnexp = wire.unexpected.length;
    final nHttp = net.tries.length;
    _out('R555 setup init cf=$nCf unexpected=$nUnexp http=$nHttp auth=${wire.auth.length} un64=${_enc(wire.unexpected.join('|'))}');
    final initOk = nCf == 0 && nUnexp == 0 && nHttp == 0;
    if (!initOk) _halt = 'setUpAll 초기화 안전 대역';
    expect(initOk, isTrue, reason: 'setUpAll 초기화 중 CF 0 · 예상 밖 채널 0 · HTTP 0 — [${wire.unexpected.join(' | ')}]');
  });

  for (final v in _views) {
    for (final c in _cases) {
      testWidgets('S955TY-${v.id}-${c.id} 관리자 홈 글자 역할 T1 — 역할 값 · 전문 · 말줄임 · 음절 끊김 · 넘침 · 읽기 순서 · 그룹 간격 · 행동 도달', (t) async {
        final tok = 'S955TY-${v.id}-${c.id}';
        if (_halt != null) fail('$tok 진입 0 — 앞 실패: $_halt');

        // guard 를 이 사례의 어떤 초기화보다 먼저 건다(대역 · provider · 홈 생성 전). 이전 값은 모두 잡아 둔다(DU526 그대로).
        final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        final wire = _Wire();
        final net = _NoHttp(wire);
        final prevAll = messenger.allMessagesHandler;
        final prevHttp = HttpOverrides.current;
        final prevOnError = FlutterError.onError;
        messenger.allMessagesHandler = (channel, handler, message) => wire.route(messenger, channel, handler, message);
        HttpOverrides.global = net;
        addTearDown(() {
          messenger.allMessagesHandler = prevAll;
          HttpOverrides.global = prevHttp;
          FlutterError.onError = prevOnError;
        });
        t.view.physicalSize = Size(v.w, v.h);
        t.view.devicePixelRatio = 1.0;
        addTearDown(t.view.reset);
        final screen = Offset.zero & Size(v.w, v.h);
        final mode = _before ? 'before' : 'strict';
        _out('D555 $tok begin mode=$mode phase=${Platform.environment['DU1_VQ_PHASE'] ?? '(unset)'} env=$_envLine manifest=$_manifest');
        final seen = _Seen();
        void need(String k, bool ok, [String why = '']) => expect(ok, isTrue, reason: '$tok $k $why');
        void safe(String step) => need('안전 대역($step) — 예상 밖 채널 · CF · HTTP 0', !wire.tripped && net.tries.isEmpty,
            'cf ${wire.cf.length} 예상 밖 [${wire.unexpected.join(' | ')}] http ${net.tries.length}');
        final checks = <(String, bool, String)>[];
        void chk(String k, bool ok, [String why = '']) => checks.add((k, ok, why));

        final fx = _fixture(c.id);
        final owner = _Owner(bizIds: fx.bizIds);
        final homeCalls = <String, int>{};
        final an = _anchorsOf(c.id);
        Object? failure;
        StackTrace? failureSt;
        var shots = 0;
        var raw = '';
        try {
          FlutterError.onError = seen.add;
          final key = GlobalKey();
          await t.pumpWidget(MultiProvider(
            providers: [
              ChangeNotifierProvider<UserProvider>.value(value: owner),
              ChangeNotifierProvider<NotificationProvider>(create: (_) => NotificationProvider()),
            ],
            child: RepaintBoundary(
              key: key,
              child: MaterialApp(
                debugShowCheckedModeBanner: false,
                theme: RoleTheme.businessAdminTheme,
                locale: const Locale('ko', 'KR'),
                supportedLocales: const [Locale('ko', 'KR'), Locale('en', 'US')],
                localizationsDelegates: const [
                  GlobalMaterialLocalizations.delegate,
                  GlobalWidgetsLocalizations.delegate,
                  GlobalCupertinoLocalizations.delegate,
                ],
                builder: (ctx, child) =>
                    MediaQuery(data: MediaQuery.of(ctx).copyWith(textScaler: TextScaler.linear(v.s)), child: child!),
                home: BusinessAdminHomeScreen(reads: _homeReads(fx, homeCalls)),
              ),
            ),
          ));
          for (var i = 0; i < 20; i++) {
            await t.pump(const Duration(milliseconds: 100));
          }
          safe('홈 열림');
          final home = find.byType(BusinessAdminHomeScreen);
          final nHome = home.evaluate().length;
          need('홈 1', nHome == 1, '개수 $nHome');

          Future<void> shot(String id, String state) async {
            _out('D555 $tok shot $id ovf=${seen.overflows.length}');
            await vqCapture(t, key, '${tok}_$id', conditions: {
              'viewport': '${v.w.toInt()}x${v.h.toInt()}', 'textScaler': v.s, 'run': vqRun, 'manifest': _manifest, 'mode': mode,
              'fixture': c.id, 'state': state,
            });
            shots++;
          }

          // ① 역할 글(원점 · 끌기 0) — 칸마다 글을 찾아 문단을 모은다. 상태 선언의 글은 모두 있어야 한다(없으면 멈춘다).
          final found = <String, List<(RenderParagraph, String)>>{};
          for (final e in an.entries) {
            final ps = <(RenderParagraph, String)>[];
            for (final (q, show) in e.value) {
              final got = _parasOf(_textOf(home, q));
              need('역할 글 있음 ${e.key}', got.isNotEmpty, q);
              for (final p in got) {
                ps.add((p, show));
              }
            }
            found[e.key] = ps;
          }
          found['np'] = _inBox(home, AppColors.conceptStaffingNeedBg);
          found['kp'] = _inBox(home, AppColors.conceptCountBg);
          List<(RenderParagraph, String)> at(String k) => found[k] ?? const [];
          final staff = at('staff');
          final fam = at('hd').isEmpty ? '-' : (at('hd').first.$1.text.style?.fontFamily ?? 'n');
          _out('D555 $tok att head hd=${_sigsOf(at('hd'))} dt=${_sigsOf(at('dt'))} ad=${_sigsOf(at('ad'))} fam=$fam');
          _out('D555 $tok att hero hm=${_sigsOf(at('hm'))} hs=${_sigsOf(at('hs'))}');
          _out('D555 $tok att sect st=${_sigsOf(at('st'))} su=${_sigsOf(at('su'))} sa=${_sigsOf(at('sa'))}');
          _out('D555 $tok att today wt=${_sigsOf(at('wt'))} sq=${_sigsOf(staff, bold: true)} sl=${_sigsOf(staff, bold: false)} np=${_sigsOf(at('np'))} sc=${_sigsOf(at('sc'))} cx=${_sigsOf(at('cx'))} wh=${_sigsOf(at('wh'))} sn=${_sigsOf(at('sn'))} sv=${_sigsOf(at('sv'))} at=${_sigsOf(at('at'))}');
          _out('D555 $tok att fail pm=${_sigsOf(at('pm'))} er=${_sigsOf(at('er'))} pn=${_sigsOf(at('pn'))} rt=${_sigsOf(at('rt'))}');
          _out('D555 $tok att next fd=${_sigsOf(at('fd'))} fx=${_sigsOf(at('fx'))} fn=${_sigsOf(at('fn'))}');
          _out('D555 $tok att task kt=${_sigsOf(at('kt'))} kd=${_sigsOf(at('kd'))} ks=${_sigsOf(at('ks'))} kp=${_sigsOf(at('kp'))} re=${_sigsOf(at('re'))}');

          // ② 전문 · 말줄임 · 줄 제한 · 낱말 안 끊김 — 찾은 문단 전부(칸 · 줄 수는 raw).
          var nAll = 0, nEx = 0, nCut = 0, nWb = 0, nFull = 0;
          final fitBad = <String>[];
          final slotRaw = <String>[];
          for (final e in found.entries) {
            final ls = <int>[];
            for (final (p, show) in e.value) {
              final f = _fitOf(p, show);
              nAll++;
              nEx += f.ex;
              nCut += f.cut;
              nWb += f.wb;
              nFull += f.full;
              ls.add(f.lines);
              if (f.ex + f.cut + f.wb + f.full > 0) fitBad.add('${e.key} ex${f.ex} cut${f.cut} wb${f.wb} full${f.full} "${visibleText(p.text.toPlainText())}"');
            }
            slotRaw.add('${e.key}:${e.value.length}:${ls.join('.')}');
          }
          _out('D555 $tok att fit n=$nAll ex=$nEx cut=$nCut wb=$nWb full=$nFull');
          final fitRaw = 'slots ${slotRaw.join(' ')} bad ${fitBad.join(' | ')}';
          raw = 'fit $fitRaw';
          if (!_before) chk('strict 역할 글 전문 · 줄 제한/말줄임 0 · 낱말 안 끊김 0', nEx == 0 && nCut == 0 && nWb == 0 && nFull == 0, fitRaw);

          // ③ 읽기 순서(y) · 그룹 간격 — 머리 이름 → 대표 문구 → 날짜 → (Hero 문장) → 오늘 → 할 일 → 다가오는 / 섹션 제목 ↔ 표면 카드 / 할 일 첫 행 안.
          final seqQ = <(String, String)>[
            ('name', '김관리님'), ('hd', '오늘 운영을 한눈에'), ('dt', _dateText),
            if (an['hm'] != null) ('hm', an['hm']!.first.$1),
            ('t1', '오늘의 근무'), ('t2', '처리할 일'), ('t3', '다가오는 근무'),
          ];
          final seq = <(String, Rect)>[];
          for (final (k, q) in seqQ) {
            final ps = _parasOf(_textOf(home, q));
            need('순서 글 있음 $k', ps.isNotEmpty, q);
            seq.add((k, _rectOf(ps.first)));
          }
          var ord = true;
          final gaps = <String>[];
          for (var i = 1; i < seq.length; i++) {
            if (!(seq[i].$2.top > seq[i - 1].$2.top + 0.5)) ord = false;
            gaps.add((seq[i].$2.top - seq[i - 1].$2.bottom).toStringAsFixed(1));
          }
          final cards = <Rect>[];
          final cardF = find.descendant(of: home, skipOffstage: false,
              matching: find.byWidgetPredicate(
                  (w) => w is Container && w.decoration is BoxDecoration && ((w.decoration! as BoxDecoration).boxShadow?.isNotEmpty ?? false),
                  skipOffstage: false));
          for (final e in cardF.evaluate()) {
            final ro = e.renderObject;
            if (ro is RenderBox) cards.add(MatrixUtils.transformRect(ro.getTransformTo(null), Offset.zero & ro.size));
          }
          cards.sort((a, b) => a.top.compareTo(b.top));
          need('표면 카드 3(오늘 · 할 일 · 다가오는)', cards.length == 3, '개수 ${cards.length}');
          final titles = [for (final (k, r) in seq) if (k.startsWith('t')) r];
          final sg = [
            for (var i = 0; i < 3; i++) ...[
              (cards[i].top - titles[i].bottom).toStringAsFixed(1),
              if (i < 2) (titles[i + 1].top - cards[i].bottom).toStringAsFixed(1),
            ],
          ].join(',');
          String firstTop(String k) {
            final ps = at(k);
            if (ps.isEmpty) return '-';
            final rs = [for (final (p, _) in ps) _rectOf(p)]..sort((a, b) => a.top.compareTo(b.top));
            return '${rs.first.top.toStringAsFixed(1)}:${rs.first.bottom.toStringAsFixed(1)}';
          }
          final tg = [firstTop('kt'), firstTop('kd'), firstTop('ks')].join(',');
          _out('D555 $tok att order ord=$ord gaps=${gaps.join(',')} sg=$sg tg=$tg');
          final ordRaw = 'seq ${[for (final (k, r) in seq) '$k ${r.top.toStringAsFixed(1)}-${r.bottom.toStringAsFixed(1)}'].join(' ')} cards ${cards.map((r) => '${r.top.toStringAsFixed(1)}-${r.bottom.toStringAsFixed(1)}').join(' ')}';
          raw = '$raw order $ordRaw';
          chk('읽기 순서(y) — 머리 → 대표 문구 → 날짜 → (Hero) → 오늘 → 할 일 → 다가오는(두 모드)', ord, ordRaw);
          await shot('1top', 'origin');

          // ④ 행동 받는 자리 — ensureVisible 로 화면에 넣고(대상마다 한 번 · 4 × 50ms) 화면 안 · 중심 hit · 48 이상. 누르지 않는다.
          final ctas = _ctasOf(c.id);
          var cVis = 0, cHit = 0, c48 = 0;
          final ctaRaw = <String>[];
          for (final (lab, i) in ctas) {
            final labs = _textOf(home, lab);
            final nLab = labs.evaluate().length;
            need('행동 글 $lab #$i', nLab > i, '개수 $nLab');
            final rf = find.ancestor(of: labs.at(i), matching: find.byType(GestureDetector)).first;
            await t.ensureVisible(rf);
            for (var k = 0; k < 4; k++) {
              await t.pump(const Duration(milliseconds: 50));
            }
            final p = _tapNow(t, rf, home, screen);
            if (p.vis) cVis++;
            if (p.hit) cHit++;
            if (p.min48) c48++;
            ctaRaw.add('$lab#$i ${p.r.width.toStringAsFixed(1)}x${p.r.height.toStringAsFixed(1)} ${p.vis}/${p.hit}/${p.min48}');
          }
          _out('D555 $tok att cta n=${ctas.length} vis=$cVis hit=$cHit m48=$c48');
          final ctaText = ctaRaw.join(' | ');
          raw = '$raw cta $ctaText';
          if (!_before) chk('strict 행동 받는 자리 화면 안 · 중심 hit · 48 이상(전부)', cVis == ctas.length && cHit == ctas.length && c48 == ctas.length, ctaText);
          safe('행동 측정');

          // ⑤ 아래 구간 캡처 — 처리할 일 · 다가오는 근무 제목을 화면 위로(ensureVisible · 각 한 번).
          await t.ensureVisible(_textOf(home, '처리할 일'));
          for (var k = 0; k < 4; k++) {
            await t.pump(const Duration(milliseconds: 50));
          }
          await shot('2task', 'tasks-head');
          await t.ensureVisible(_textOf(home, '다가오는 근무'));
          for (var k = 0; k < 4; k++) {
            await t.pump(const Duration(milliseconds: 50));
          }
          await shot('3next', 'upcoming-head');
          safe('캡처');
        } catch (e, st) {
          failure = e;
          failureSt = st;
        } finally {
          FlutterError.onError = prevOnError;
        }

        // ⑥ 성공 · 실패 공통 정리 — 홈을 내리고 남은 timer · 지연 응답이 끝날 시간을 준다. guard 는 아직 걸려 있다.
        var cleanupErr = '';
        try {
          await t.pumpWidget(const SizedBox.shrink());
          for (var i = 0; i < 6; i++) {
            await t.pump(const Duration(seconds: 1));
          }
        } catch (e, st) {
          cleanupErr = e.toString();
          if (failure == null) {
            failure = e;
            failureSt = st;
          }
        }

        // ⑦ 최종 안전 집계 — 해제 · 대기 뒤 guard 아래에서 센다(값 측정과 분리).
        final nUnexp = wire.unexpected.length;
        final nCf = wire.cf.length;
        final nHttp = net.tries.length;
        final tripped = wire.tripped;
        final unText = wire.unexpected.join(' | ');
        _out('D555 $tok att wire cf=$nCf unexpected=$nUnexp http=$nHttp summary=${homeCalls['summary'] ?? 0} staffing=${homeCalls['staffing'] ?? 0} roster=${homeCalls['roster'] ?? 0} attendance=${homeCalls['attendance'] ?? 0}');

        messenger.allMessagesHandler = prevAll;
        HttpOverrides.global = prevHttp;
        final exc = t.takeException();
        if (exc != null && failure == null) {
          failure = exc;
          failureSt = StackTrace.current;
        }
        final nOvf = seen.overflows.length;
        final nFw = seen.other.length;
        final ovfRaw = seen.overflows.take(8).join('\n----\n');
        final fwRaw = seen.other.take(4).map((m) => m.length > 400 ? m.substring(0, 400) : m).join('\n----\n');
        _out('R555 $tok raw m64=${_enc(raw)} ovf64=${_enc(ovfRaw)} fw64=${_enc(fwRaw)} un64=${_enc(unText)} cleanup64=${_enc(cleanupErr)} '
            'fail64=${_enc(failure?.toString() ?? '')}');
        _out('D555 $tok att fw n=$nFw');
        _out('D555 $tok done state=${c.id} mode=$mode captures=$shots overflows=$nOvf exc=${exc != null}');

        final f0 = failure;
        if (f0 != null) {
          _halt ??= '$tok ${f0.toString().split('\n').first}';
          Error.throwWithStackTrace(f0, failureSt ?? StackTrace.current);
        }
        // 넘침: 두 모드 0(§6.3 — 큰 글자에서 길이 증가는 허용 · 넘침 · 숨김은 허용하지 않는다).
        chk('화면 전체 넘침 0(두 모드)', nOvf == 0, ovfRaw);
        chk('미처리 framework 예외 0', nFw == 0, fwRaw);
        chk('캡처 수 = 선언', shots == c.shots, 'shots $shots want ${c.shots}');
        chk('시험 전체 CF 0 · 예상 밖 채널 0 · HTTP 0(해제 · 대기 뒤 · 업무 writer 불실행)', nCf == 0 && nUnexp == 0 && nHttp == 0 && !tripped,
            'cf $nCf 예상 밖 [$unText] http $nHttp tripped $tripped');
        final bad = checks.where((x) => !x.$2).toList();
        if (bad.isNotEmpty) _halt ??= '$tok ${bad.first.$1}';
        for (final x in checks) {
          expect(x.$2, isTrue, reason: '$tok ${x.$1} ${x.$3}');
        }
      }, skip: !_optIn);
    }
  }
}
