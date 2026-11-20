// ignore_for_file: depend_on_referenced_packages
// [DU526 · 표시만] DU-O002 '인력 현황' 하단 '닫기' 받는 자리 — 기본 글자 크기(390×844)에서 64×40(DU524 관측) → 세로 48.
//   before = 현재 A(day_applicants_dialog c3008338) 기록 · strict = 후보(O002 버튼 minimumSize 만 · 공용 AppModalFooter 그대로). 상태 MULTI · FAIL × W/B.
//   하네스 = DU524 r3. 기본 skip — TB before/du526-tb/DU_BEFORE_OBSERVE=526 · TA after/du526-ta/없음.
import 'dart:convert';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:flutter/material.dart';
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
import 'package:ALfit/models/core/work_detail_data.dart';
import 'package:ALfit/models/ui/admin_home_summary_model.dart';
import 'package:ALfit/models/ui/day_staffing_row.dart';
import 'package:ALfit/models/ui/staffing_readiness_model.dart';
import 'package:ALfit/providers/notification_provider.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/screens/business_admin/admin_home_reads.dart';
import 'package:ALfit/screens/business_admin/business_admin_home_screen.dart';
import 'package:ALfit/screens/business_admin/dialogs/day_applicants_dialog.dart';
import 'package:ALfit/screens/business_admin/dialogs/day_applicants_reads.dart';
import 'package:ALfit/services/business_posting_readiness.dart';
import 'package:ALfit/services/contract_service.dart';
import 'package:ALfit/theme/role_theme.dart';
import 'package:ALfit/utils/format_helper.dart';
import 'package:ALfit/utils/text_layout.dart';
import 'package:ALfit/widgets/dialogs/styled_dialog.dart';

import 'support/du1_vq_capture.dart';

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
const _longName = '응우옌 티 프엉 타오 쩐'; // CP01-C1 · CP04 인계 긴 이름(띄어쓰기 있음)
const _latinName = 'KHAMPHOUVONGSOUKSAVANH'; // 띄어쓰기 없는 긴 로마자 이름
const _longTitle = '수도권 남부 통합 물류센터 야간 상하차 및 분류 보조 단기 모집';
const _longWork = '냉장·냉동 식품 분류 및 출고 검수 보조';
const _nightTitle = '야간 상하차 단기';

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
final String _ymd = '${_today.year}-${_today.month.toString().padLeft(2, '0')}-${_today.day.toString().padLeft(2, '0')}';
// 상대 시각은 창이 실제 DateTime.now() 로 센다(day_applicants_dialog.dart:4415) — 실행 시각 기준 3시간 전으로 둔다.
final DateTime _applied = DateTime.now().subtract(const Duration(hours: 3));
final DateTime _invAt = DateTime.now().subtract(const Duration(hours: 5));

BusinessModel _business(String id, String name) => BusinessModel(
    id: id, name: name, ownerId: 'admin1', businessNumber: '000-00-00000', address: '서울시 어딘가',
    category: '물류', subCategory: '창고', isApproved: true, createdAt: DateTime(2026, 1, 1));

Map<String, dynamic> _biz(String id, String name, int req, int conf, int short) =>
    {'businessId': id, 'businessName': name, 'requiredCount': req, 'confirmedCount': conf, 'shortageCount': short};

Map<String, dynamic> _day(int req, int conf, int short, {int? pending, List<Map<String, dynamic>> byBusiness = const []}) => {
      'date': _ymd, 'requiredCount': req, 'confirmedCount': conf, 'shortageCount': short,
      if (pending != null) 'pendingCount': pending, 'pendingAvailable': pending != null, 'byBusiness': byBusiness,
    };

StaffingReadinessModel _staffing(Map<String, dynamic> d) =>
    StaffingReadinessModel(available: true, publishedPostingCount: 1, days: [StaffingDayData.fromMap(d)]);

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

/// 할 일 canonical — 전부 0(CP04 _summary 와 같은 CF 직렬화 모양 · 파싱은 production).
AdminHomeSummaryModel _summary() {
  Map<String, dynamic> s() => {'available': true, 'count': 0, 'byBusiness': [{'businessId': _biz1, 'count': 0}]};
  return AdminHomeSummaryModel.fromMap({
    'actions': {
      'resignRequest': {...s(), 'soonCount': 0, 'manualReviewCount': null},
      'approval': {...s(), 'overdueCount': 0},
      'scheduleChangeRequest': s(),
      'unsentContract': s(),
      'unclosed': {...s(), 'oldestDate': null},
      'settlementRequest': s(),
      'wageChangeRequest': s(),
      'unpaidWage': {
        ...s(), 'overdueCount': 0, 'missingDueDateCount': 0,
        'byBusiness': [{'businessId': _biz1, 'count': 0, 'missingDueDateCount': 0}],
      },
    },
    'upcoming': {
      'expiringContract': {...s(), 'upcomingCount': 0, 'expiredCount': 0},
    },
  });
}

ApplicationModel _app(String id, String status,
        {String bizId = _biz1, String bizName = _bizName, String toId = 'to1', String title = '물류 단기 모집',
        String wd = 'wd1', String work = '상하차', String start = '09:00', String end = '18:00', bool starred = false,
        DateTime? invitedAt}) =>
    ApplicationModel(
      id: id, uid: 'u_$id', toId: toId, slotId: 's_$toId', businessId: bizId, businessName: bizName, toTitle: title,
      selectedWorkType: work, wdId: wd, startTime: start, endTime: end, wage: 12000, wageType: 'hourly', status: status,
      workDate: _today, appliedAt: _applied, isStarred: starred, invitedAt: invitedAt,
      invitedBy: invitedAt == null ? null : 'admin1',
    );

DayStaffingRow _row(
        {String toId = 'to1', String title = '물류 단기 모집', String wd = 'wd1', String work = '상하차',
        String start = '09:00', String end = '18:00', required int req, required int conf, int pend = 0}) =>
    DayStaffingRow(
      toId: toId, toTitle: title, slotId: 's_$toId', wdId: wd, workType: work, startTime: start, endTime: end,
      requiredCount: req, confirmedCount: conf, pendingCount: pend,
    );

UserModel _person(String appId) {
  final uid = 'u_$appId';
  UserModel u(String name, {int? personNo, String? phone, int noShow = 0, double rating = 0}) => UserModel(
      uid: uid, username: uid, name: name, email: '$uid@alfit.local', role: UserRole.USER,
      personNo: personNo, phone: phone, recentNoShowCount: noShow, averageRating: rating);
  switch (appId) {
    case 'p1':
      return u('김별표', phone: '01012345678', rating: 4.5);
    case 'p2':
      return u('이선택');
    case 'p3':
      return u('박노쇼', noShow: 1);
    case 'c1':
      return u('최확정');
    case 'c2':
      return u('정미작성');
    case 'c3':
      return u('한서명');
    case 'c4':
      return u('오관리');
    case 'i9':
      return u('문마감');
    case 'l1':
      return u(_longName, personNo: 123);
    case 'l2':
      return u(_latinName);
    case 'l3':
      return u('남궁하늘빛나리');
    case 'm1':
      return u('서다사업');
    case 'm2':
      return u('윤확정');
    case 'm3':
      return u('장미작성');
    case 'i1':
      return u('강초대');
    default:
      return u('근로자 $appId');
  }
}

typedef _Fx = ({
  List<String> bizIds,
  List<BusinessModel> businesses,
  StaffingReadinessModel staffing,
  String dialogBiz,
  List<ApplicationModel> pending,
  List<ApplicationModel> confirmed,
  List<ApplicationModel> invites,
  List<DayStaffingRow> rows,
  Map<String, int> caps,
  Map<String, String> contracts,
  Map<String, UserModel> users,
  bool failFirst,
  bool rowsFail,
  bool invitesFail,
  bool capsFail,
});

_Fx _fx(List<BusinessModel> businesses, StaffingReadinessModel staffing,
    {List<String> bizIds = const [_biz1], String dialogBiz = _biz1, List<ApplicationModel> pending = const [],
    List<ApplicationModel> confirmed = const [], List<ApplicationModel> invites = const [],
    List<DayStaffingRow> rows = const [], Map<String, int> caps = const {}, Map<String, String> contracts = const {},
    bool failFirst = false, bool rowsFail = false, bool invitesFail = false, bool capsFail = false}) {
  final users = {for (final a in [...pending, ...confirmed, ...invites]) a.uid: _person(a.id)};
  return (
    bizIds: bizIds, businesses: businesses, staffing: staffing, dialogBiz: dialogBiz, pending: pending,
    confirmed: confirmed, invites: invites, rows: rows, caps: caps, contracts: contracts, users: users,
    failFirst: failFirst, rowsFail: rowsFail, invitesFail: invitesFail, capsFail: capsFail,
  );
}

/// 상태별 대역 — 각 사례가 새로 만든다(공유 상태 0). 홈 오늘 부족 > 0 이어야 '인원 현황 보기' 행이 선다(:2882).
_Fx _fixture(String id) {
  final single = [_business(_biz1, _bizName)];
  final multi = [_business(_biz1, _bizName), _business(_biz2, _longBiz)];
  ApplicationModel night(String appId, String st, {DateTime? invitedAt}) => _app(appId, st,
      bizId: _biz2, bizName: _longBiz, toId: 'to2', title: _nightTitle, wd: 'wdA', start: '18:00', end: '23:00',
      invitedAt: invitedAt);
  switch (id) {
    case 'SHORT':
    case 'FAIL':
      return _fx(single, _staffing(_day(5, 2, 3, byBusiness: [_biz(_biz1, _bizName, 5, 2, 3)])),
          confirmed: [_app('c1', AppStatus.confirmed), _app('c2', AppStatus.confirmed)],
          rows: [_row(req: 5, conf: 2)], caps: const {'wd1': 5}, contracts: const {'c1': 'completed'},
          failFirst: id == 'FAIL');
    case 'FULL':
      return _fx(single, _staffing(_day(5, 4, 1, byBusiness: [_biz(_biz1, _bizName, 5, 4, 1)])),
          confirmed: [
            _app('c1', AppStatus.confirmed), _app('c2', AppStatus.confirmed), _app('c3', AppStatus.confirmed),
            _app('c4', AppStatus.confirmed, wd: 'wd2', work: '포장', start: '13:00', end: '22:00'),
          ],
          invites: [_app('i9', AppStatus.invited, invitedAt: _invAt)],
          rows: [_row(req: 3, conf: 3), _row(wd: 'wd2', work: '포장', start: '13:00', end: '22:00', req: 2, conf: 1)],
          caps: const {'wd1': 3, 'wd2': 2},
          contracts: const {'c1': 'completed', 'c2': 'pending_worker', 'c3': 'pending_employer'});
    case 'PEND':
      return _fx(single, _staffing(_day(4, 1, 3, pending: 3, byBusiness: [_biz(_biz1, _bizName, 4, 1, 3)])),
          pending: [_app('p1', AppStatus.pending, starred: true), _app('p2', AppStatus.pending), _app('p3', AppStatus.pending)],
          confirmed: [_app('c1', AppStatus.confirmed)], rows: [_row(req: 4, conf: 1, pend: 3)],
          caps: const {'wd1': 4}, contracts: const {'c1': 'completed'});
    case 'UNK':
      return _fx(single, _staffing(_day(5, 2, 3, byBusiness: [_biz(_biz1, _bizName, 5, 2, 3)])),
          pending: [_app('p2', AppStatus.pending)],
          confirmed: [_app('c1', AppStatus.confirmed), _app('c2', AppStatus.confirmed)],
          contracts: const {'c1': 'completed'}, rowsFail: true, invitesFail: true, capsFail: true);
    case 'LONG':
      return _fx(single, _staffing(_day(3, 1, 2, pending: 2, byBusiness: [_biz(_biz1, _bizName, 3, 1, 2)])),
          pending: [
            _app('l1', AppStatus.pending, title: _longTitle, work: _longWork),
            _app('l2', AppStatus.pending, title: _longTitle, work: _longWork),
          ],
          confirmed: [_app('l3', AppStatus.confirmed, title: _longTitle, work: _longWork)],
          rows: [_row(title: _longTitle, work: _longWork, req: 3, conf: 1, pend: 2)], caps: const {'wd1': 3});
    default: // MULTI — 부족 큰 순 biz2(3) · biz1(1) → 창 첫 사업장 biz2(:3548–3553 · :479–480)
      return _fx(multi,
          _staffing(_day(8, 4, 4, byBusiness: [_biz(_biz1, _bizName, 3, 2, 1), _biz(_biz2, _longBiz, 5, 2, 3)])),
          bizIds: const [_biz1, _biz2], dialogBiz: _biz2,
          pending: [night('m1', AppStatus.pending)],
          confirmed: [night('m2', AppStatus.confirmed), night('m3', AppStatus.confirmed)],
          invites: [night('i1', AppStatus.invited, invitedAt: _invAt)],
          rows: [_row(toId: 'to2', title: _nightTitle, wd: 'wdA', start: '18:00', end: '23:00', req: 5, conf: 2, pend: 1)],
          caps: const {'wdA': 5}, contracts: const {'m2': 'completed'});
  }
}

AdminHomeReads _homeReads(_Fx fx, Map<String, int> calls) {
  void hit(String k) => calls[k] = (calls[k] ?? 0) + 1;
  return AdminHomeReads(
    summary: ({String? selectedBusinessId}) {
      hit('summary');
      return Future.value(_summary());
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
      return <AttendanceModel>[];
    },
    confirmedWorkers: ({required DateTime date, required String businessId}) async {
      hit('roster');
      return <ApplicationModel>[];
    },
    workDetailTimes: (_) async => <String, dynamic>{},
    postingReadiness: (bizs) async => _ready(bizs),
    contractTemplates: (_) async => <ContractTemplateModel>[_Template()],
    tourCompleted: () => Future<bool>.value(true),
    clock: () => _clock,
    legalReadiness: () async => const LegalReadiness(status: LegalReadinessStatus.current),
  );
}

/// 창의 읽기 경계 — 호출 수 · 사업장 · 날짜 · KST 자정 · 목적을 기록한다. 실패 대역은 fixture 플래그로만.
class _DayReads {
  _DayReads(this.fx);
  final _Fx fx;
  final calls = <String, int>{};
  final biz = <String>{};
  final dates = <String>{};
  final dayStarts = <int>{};
  final purposes = <String>{};

  /// [r1 · 판정 §3-3] 호출별 날짜 · 주간 경계 원값(읽기 이름 → 호출 순서대로). 끝에서 고정 KST 기대와 단언한다.
  final at = <String, List<String>>{};
  var _pendingTries = 0;

  void _hit(String k, [String? businessId]) {
    calls[k] = (calls[k] ?? 0) + 1;
    if (businessId != null) biz.add(businessId);
  }

  void _on(String k, DateTime d) {
    final v = _dk(d);
    dates.add(v);
    at.putIfAbsent(k, () => <String>[]).add(v);
  }

  DayApplicantsReads reads() => DayApplicantsReads(
        pendingApplications: ({required date, required businessId, purpose}) async {
          _hit('pending', businessId);
          _on('pending', date);
          purposes.add('p:${purpose ?? '-'}');
          _pendingTries++;
          if (fx.failFirst && _pendingTries == 1) throw StateError('NCB-12O 관측 fixture — 첫 조회 실패');
          return fx.pending;
        },
        confirmedWorkers: ({required date, required businessId}) async {
          _hit('confirmed', businessId);
          _on('confirmed', date);
          return fx.confirmed;
        },
        dayStaffing: ({required businessId, required dayStartMs}) async {
          _hit('dayStaffing', businessId);
          dayStarts.add(dayStartMs);
          if (fx.rowsFail) throw StateError('NCB-12O 관측 fixture — 인력 현황 조회 실패');
          return fx.rows;
        },
        dayInvitations: ({required date, required businessId}) async {
          _hit('invites', businessId);
          _on('invites', date);
          if (fx.invitesFail) throw StateError('NCB-12O 관측 fixture — 초대 현황 조회 실패');
          return fx.invites;
        },
        hasWorkedMap: ({required businessId, required date}) async {
          _hit('hasWorked', businessId);
          _on('hasWorked', date);
          return const <String, bool>{};
        },
        noShowApplicationIds: ({required businessId, required date}) async {
          _hit('noShow', businessId);
          _on('noShow', date);
          return <String>{};
        },
        usersBatch: (uids, {required businessId, purpose}) async {
          _hit('users', businessId);
          purposes.add('u:${purpose ?? '-'}');
          return {for (final u in uids) if (fx.users.containsKey(u)) u: fx.users[u]!};
        },
        weeklyAttendance: ({required businessId, required weekStart, required weekEnd}) async {
          _hit('weekly', businessId);
          at.putIfAbsent('weekly', () => <String>[]).add('${_dk(weekStart)}..${_dk(weekEnd)}');
          return <String, List<AttendanceModel>>{};
        },
        slotWorkDetailCapacities: (toId, slotId) async {
          _hit('caps');
          if (fx.capsFail) throw StateError('NCB-12O 관측 fixture — 정원 조회 실패');
          return fx.caps;
        },
        slotWorkDetails: (toId, slotId) async {
          _hit('slotWds');
          return <WorkDetailData>[];
        },
        to: (toId) async {
          _hit('to');
          return null;
        },
        contractStatusBatch: (ids, {required businessId}) async {
          _hit('contracts', businessId);
          return ContractStatusBatch(statuses: {for (final x in ids) if (fx.contracts.containsKey(x)) x: fx.contracts[x]});
        },
        contractAttendances: ({required businessId, required date}) async {
          _hit('contractAtt', businessId);
          _on('contractAtt', date);
          return <AttendanceModel>[];
        },
      );
}

/// 날짜 원값 — 연-월-일T시:분 + 시간대 표시(Z=UTC · L=기기 지역). 창이 넘기는 값을 그대로 적는다.
String _dk(DateTime d) => '${d.year}-${d.month}-${d.day}T${d.hour}:${d.minute}${d.isUtc ? 'Z' : 'L'}';

/// [F120-3 · DU508 r3 와 같은 축] CF Pigeon 채널 — 이 화면은 주입 읽기만 쓰므로 호출 0 이어야 한다(쓰기 callable 포함).
const _cfChannel = 'dev.flutter.pigeon.cloud_functions_platform_interface.CloudFunctionsHostApi.call';

/// [ARO setUpAll 과 같다] 창이 FirebaseAuth.instance.currentUser(:658)를 처음 읽을 때 등록하는 두 리스너 채널과 그 이벤트 채널.
const _authBase = 'dev.flutter.pigeon.firebase_auth_platform_interface.FirebaseAuthHostApi.';
const _authFake = 'ncb12o.fake.auth.';

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
    throw const SocketException('NCB-12O 관측 — 외부 HTTP 차단');
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

/// 1단계 읽기 넷 — '다시 시도' 실제 탭으로 각 1 → 2(DU515 r3 에서 실측된 경로).
const _phase1 = ['pending', 'confirmed', 'dayStaffing', 'invites'];

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

/// '다시 시도' 가 끌기 없이 보이는가 — 창 상자 ∩ 화면(∩ 가까운 Scrollable 이 있으면 그 칸) 안 + 중심 hit.
({bool vis, bool hit, Rect r}) _retryNow(WidgetTester t, Finder retryF, Finder dlg, Rect screen) {
  final boxF = find.descendant(of: dlg, matching: find.byType(Dialog), skipOffstage: true);
  var area = boxF.evaluate().isEmpty ? screen : t.getRect(boxF.first).intersect(screen);
  final scF = find.ancestor(of: retryF, matching: find.byType(Scrollable));
  final nSc = scF.evaluate().length;
  if (nSc > 0) area = area.intersect(t.getRect(scF.first));
  final r = t.getRect(retryF);
  final vis = _inside(r, area);
  final hit = t.hitTestOnBinding(r.center).path.any((x) => identical(x.target, t.renderObject(retryF)));
  return (vis: vis, hit: hit, r: r);
}

/// 상태 대역 — UNK = 인력 현황 · 초대 · 정원 조회 실패(지원 1 · 확정 2 는 유효).
_Fx _stateFx(String id) => _fixture(id);

typedef _V = ({String id, double w, double h, double s});
const _views = <_V>[(id: 'W', w: 390.0, h: 844.0, s: 1.0), (id: 'B', w: 320.0, h: 640.0, s: 2.0)];
const _cases = <({String id, int shots})>[(id: 'MULTI', shots: 2), (id: 'FAIL', shots: 2)];

final bool _before = Platform.environment['DU_BEFORE_OBSERVE'] == '526';
final Map<String, String> _env = Platform.environment;
final bool _optIn =
    (_env['DU1_VQ_PHASE'] == 'before' && _env['DU1_VQ_RUN'] == 'du526-tb' && _env['DU_BEFORE_OBSERVE'] == '526') ||
        (_env['DU1_VQ_PHASE'] == 'after' && _env['DU1_VQ_RUN'] == 'du526-ta' && _env['DU_BEFORE_OBSERVE'] == null);
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
    _out('R526 setup init cf=$nCf unexpected=$nUnexp http=$nHttp auth=${wire.auth.length} un64=${_enc(wire.unexpected.join('|'))}');
    final initOk = nCf == 0 && nUnexp == 0 && nHttp == 0;
    if (!initOk) _halt = 'setUpAll 초기화 안전 대역';
    expect(initOk, isTrue, reason: 'setUpAll 초기화 중 CF 0 · 예상 밖 채널 0 · HTTP 0 — [${wire.unexpected.join(' | ')}]');
  });
  tearDown(() => DayApplicantsReads.debugOverride = null);

  for (final v in _views) {
    for (final c in _cases) {
      testWidgets('S902CL-${v.id}-${c.id} 인력 현황 하단 닫기 받는 자리 — 기본 글자 크기에서 세로 48', (t) async {
        final tok = 'S902CL-${v.id}-${c.id}';
        if (_halt != null) fail('$tok 진입 0 — 앞 실패: $_halt');

        // guard 를 이 사례의 어떤 초기화보다 먼저 건다(대역 · provider · 홈 생성 전). 이전 값은 모두 잡아 둔다.
        final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        final wire = _Wire();
        final net = _NoHttp(wire);
        final prevAll = messenger.allMessagesHandler;
        final prevHttp = HttpOverrides.current;
        final prevOnError = FlutterError.onError;
        final prevOverride = DayApplicantsReads.debugOverride;
        messenger.allMessagesHandler = (channel, handler, message) => wire.route(messenger, channel, handler, message);
        HttpOverrides.global = net;
        addTearDown(() {
          messenger.allMessagesHandler = prevAll;
          HttpOverrides.global = prevHttp;
          FlutterError.onError = prevOnError;
          DayApplicantsReads.debugOverride = prevOverride;
        });
        t.view.physicalSize = Size(v.w, v.h);
        t.view.devicePixelRatio = 1.0;
        addTearDown(t.view.reset);
        final mode = _before ? 'before' : 'strict';
        _out('D526 $tok begin mode=$mode phase=${Platform.environment['DU1_VQ_PHASE'] ?? '(unset)'} env=$_envLine manifest=$_manifest');
        final seen = _Seen();
        void need(String k, bool ok, [String why = '']) => expect(ok, isTrue, reason: '$tok $k $why');
        void safe(String step) => need('안전 대역($step) — 예상 밖 채널 · CF · HTTP 0', !wire.tripped && net.tries.isEmpty,
            'cf ${wire.cf.length} 예상 밖 [${wire.unexpected.join(' | ')}] http ${net.tries.length}');
        final checks = <(String, bool, String)>[];
        void chk(String k, bool ok, [String why = '']) => checks.add((k, ok, why));

        final fx = _stateFx(c.id);
        final owner = _Owner(bizIds: fx.bizIds);
        final homeCalls = <String, int>{};
        final dayReads = _DayReads(fx);
        Object? failure;
        StackTrace? failureSt;
        var shots = 0;
        var closed = false;
        var raw = '';
        try {
          FlutterError.onError = seen.add;
          DayApplicantsReads.debugOverride = dayReads.reads();
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
          final entryF = find.byWidgetPredicate((w) => w is Text && TextLayout.plain(w.data ?? '') == '인원 현황 보기');
          final nEntry = entryF.evaluate().length;
          need('홈 인원 현황 보기 행 ≥1', nEntry >= 1, '개수 $nEntry');
          await t.ensureVisible(entryF.first);
          for (var i = 0; i < 4; i++) {
            await t.pump(const Duration(milliseconds: 100));
          }
          await t.tap(find.ancestor(of: entryF.first, matching: find.byType(InkWell)).first);
          for (var i = 0; i < 24; i++) {
            await t.pump(const Duration(milliseconds: 50));
          }
          final dlg = find.byType(DayApplicantsDialog);
          final nDlg = dlg.evaluate().length;
          need('창 1', nDlg == 1, '개수 $nDlg');
          safe('창 열림');
          Future<void> shot(String id, String state) async {
            _out('D526 $tok shot $id ovf=${seen.overflows.length}');
            await vqCapture(t, key, '${tok}_$id', conditions: {
              'viewport': '${v.w.toInt()}x${v.h.toInt()}', 'textScaler': v.s, 'run': vqRun, 'manifest': _manifest, 'mode': mode,
              'fixture': c.id, 'state': state,
            });
            shots++;
          }

          final screen = Offset.zero & Size(v.w, v.h);
          final boxF = find.descendant(of: dlg, matching: find.byType(Dialog), skipOffstage: true);
          // [r2] find.byType(Dialog) 상자는 화면 전체(0,0,390,844)였다(run TB geo 844.0) — 창의 실제 면은 그 안 첫 Material 이다.
          final dr = t.getRect(find.descendant(of: boxF.first, matching: find.byType(Material), skipOffstage: true).first);
          // 닫기 X(머리) · 하단 닫기 — 받는 자리 · 중심 hit 를 **따로** 잰다(기록). [r2] r1 은 넷을 한 값(ctl)으로 묶어 두 모드에서 단언했다 —
          //   W(390@1.0)의 하단 '닫기'는 지금 64×40 이라(DU515 r2 W-SHORT 관측과 같다 · 이 셀 범위 밖) before 에서 멈췄다.
          bool big(Finder f) => t.getRect(f).width >= 48 - 0.01 && t.getRect(f).height >= 48 - 0.01;
          bool hits(Finder f) => t.hitTestOnBinding(t.getRect(f).center).path.any((x) => identical(x.target, t.renderObject(f)));

          final xF = find.descendant(of: dlg, matching: find.byType(IconButton), skipOffstage: true);
          final footF = find.descendant(of: find.byType(AppModalFooter), matching: find.widgetWithText(TextButton, '닫기'), skipOffstage: true);
          final nX = xF.evaluate().length;
          final nFoot = footF.evaluate().length;
          need('닫기 X ≥1 · 하단 닫기 1', nX >= 1 && nFoot == 1, 'X $nX 닫기 $nFoot');
          final x48 = big(xF.first);
          final xHit = hits(xF.first);
          final foot48 = big(footF);
          final footHit = hits(footF);
          final footR = t.getRect(footF);
          // [DU526] strict 단언 = X ≥48 · X hit · 하단 닫기 ≥48 · hit.
          final ctl = x48 && xHit && foot48 && footHit;
          if (c.id == 'FAIL') {
            // ① 조회 실패 첫 화면 — 끌기 없이 '다시 시도' 가 보이고 눌리는가(DU517 회귀) · 통계는 고정 그대로
            final retryF = find.descendant(of: dlg, matching: find.widgetWithText(TextButton, '다시 시도'), skipOffstage: true);
            final nRetry = retryF.evaluate().length;
            need('다시 시도 1', nRetry == 1, '개수 $nRetry');
            final p0 = _retryNow(t, retryF, dlg, screen);
            _out('D526 $tok att retry0 vis=${p0.vis} hit=${p0.hit} x48=$x48 xhit=$xHit foot48=$foot48 foothit=$footHit');
            raw = 'retry0 ${p0.r} dialog $dr foot $footR';
            if (!_before) chk('strict 첫 화면(끌기 0)에서 다시 시도 보임 · 중심 hit · X ≥48 hit · 하단 닫기 hit', p0.vis && p0.hit && ctl, raw);
            await shot('1error', 'error-first-screen');
            safe('첫 캡처');
            final rd0 = [for (final k in _phase1) dayReads.calls[k] ?? 0];
            await t.tap(retryF);
            for (var i = 0; i < 24; i++) {
              await t.pump(const Duration(milliseconds: 50));
            }
            safe('다시 시도');
            final rd1 = [for (final k in _phase1) dayReads.calls[k] ?? 0];
            final rdOk = rd0.every((x) => x == 1) && rd1.every((x) => x == 2);
            final nGone = find.descendant(of: dlg, matching: find.widgetWithText(TextButton, '다시 시도'), skipOffstage: true).evaluate().length;
            _out('D526 $tok att retry tapped=true rd=$rdOk gone=${nGone == 0}');
            chk('다시 시도 실제 탭 → 1단계 reader 넷 각 1 → 2 · 오류 본문 사라짐', rdOk && nGone == 0, 'before $rd0 after $rd1 남은 $nGone');
            await shot('2retry', 'after-retry');
            safe('재시도 캡처');
          } else {
            // ① 목록 상태 — 본문(목록 스크롤 칸) 가시 높이 · 통계 줄이 고정인지 스크롤 안인지 · 스크롤로 통계 도달
            await shot('1open', 'list-open');
            safe('첫 캡처');
            bool isStats(Widget w) => w is Container && w.child is LayoutBuilder && w.decoration is BoxDecoration;
            final statsF = find.descendant(of: dlg, matching: find.byWidgetPredicate(isStats), skipOffstage: true);
            final nStats = statsF.evaluate().length;
            need('통계 줄 1', nStats == 1, '개수 $nStats');
            final listF = find.descendant(of: dlg, matching: find.byType(Scrollable), skipOffstage: true);
            final nList = listF.evaluate().length;
            need('목록 스크롤 칸 ≥1', nList >= 1, '개수 $nList');
            final vp = t.getRect(listF.first);
            final inList = find.descendant(of: listF.first, matching: find.byWidgetPredicate(isStats), skipOffstage: true).evaluate().isNotEmpty;
            final sr0 = t.getRect(statsF);
            final bodyH = vp.height;
            // 배치 기록 — 창 위 기준 통계 줄 위 · 높이 · 목록 칸 위 · 높이. W 는 TB · TA 가 같아야 한다(실행 뒤 대조).
            final geo = '${(sr0.top - dr.top).toStringAsFixed(1)},${sr0.height.toStringAsFixed(1)},${(vp.top - dr.top).toStringAsFixed(1)},'
                '${vp.height.toStringAsFixed(1)},${dr.height.toStringAsFixed(1)}';
            // 목록을 위로 끈 뒤(통계가 스크롤 안이면 화면 밖으로 나간다) 통계 줄을 다시 화면에 넣는다 — 도달 가능.
            await t.drag(listF.first, const Offset(0, -140));
            for (var m = 0; m < 10; m++) {
              await t.pump(const Duration(milliseconds: 50));
            }
            safe('목록 끌기');
            // [r3] 통계가 스크롤 안이면 끌어 올린 뒤 viewport 밖 sliver 가 되어 onstage finder 에 잡히지 않는다(r2 TA B-MULTI: 0개 → getRect 실패).
            //   없어졌으면 그것이 '함께 움직였다'는 증거다 — 있으면 자리 차이로 본다.
            final nAfterDrag = statsF.evaluate().length;
            final sr1 = nAfterDrag == 0 ? Rect.zero : t.getRect(statsF);
            final moved = nAfterDrag == 0 || (sr1.top - sr0.top).abs() > 1;
            await shot('2scroll', 'list-dragged');
            safe('끌기 캡처');
            // [r3] 다시 아래로 끌어 맨 위로 돌아온다(실제 끌기 — 화면 밖 위젯을 finder 로 찾지 않는다). 그 뒤 통계 줄이 다시 보이면 도달.
            await t.drag(listF.first, const Offset(0, 400));
            for (var m = 0; m < 10; m++) {
              await t.pump(const Duration(milliseconds: 50));
            }
            safe('목록 되돌리기');
            final nBack = statsF.evaluate().length;
            final sr2 = nBack == 0 ? Rect.zero : t.getRect(statsF);
            final reach =
                nBack == 1 && sr2.top >= dr.top - 0.5 && sr2.bottom <= dr.bottom + 0.5 && (!inList || sr2.top >= vp.top - 0.5);
            raw = 'list vp $vp stats $sr0 → $sr1 → $sr2 dialog $dr inList $inList moved $moved afterDrag $nAfterDrag back $nBack foot $footR';
            _out('D526 $tok att body h=${bodyH.toStringAsFixed(1)} inlist=$inList moved=$moved reach=$reach x48=$x48 xhit=$xHit foot48=$foot48 '
                'foothit=$footHit');
            _out('R526 $tok geo ${v.id} ${c.id} $geo foot=${footR.width.toStringAsFixed(1)}x${footR.height.toStringAsFixed(1)}');
            if (!_before) {
              chk('strict 통계 줄 도달 · X ≥48 hit · 하단 닫기 hit · 통계가 스크롤 안이면 함께 움직임', reach && ctl && moved == inList, raw);
              // [DU526] 본문 가시 높이 기준(DU526 r3 TA 실측): W 537.2 · B 222.2. 하단 닫기 상자가 W 에서 40 → 48 이라 W 는 8 줄어 529.2,
              //   B 는 이미 49 라 그대로 222.2 여야 한다(허용 ±0.5).
              if (v.id == 'B') {
                chk('strict B 목록 — 통계 줄이 목록 스크롤 안 · 본문 가시 높이 222.2 ±0.5(변화 0)', inList && (bodyH - 222.2).abs() <= 0.5, raw);
              } else {
                chk('strict W 목록 — 통계 줄 고정 · 본문 가시 높이 529.2 ±0.5(−8)',
                    !inList && sr0.bottom <= vp.top + 0.5 && (bodyH - 529.2).abs() <= 0.5, raw);
              }
            }
          }

          // ② 닫기
          final closeF = find.descendant(of: find.byType(AppModalFooter), matching: find.widgetWithText(TextButton, '닫기'), skipOffstage: true);
          final nClose = closeF.evaluate().length;
          need('하단 닫기 1', nClose == 1, '개수 $nClose');
          await t.tap(closeF);
          for (var i = 0; i < 16; i++) {
            await t.pump(const Duration(milliseconds: 50));
          }
          final nAfter = find.byType(DayApplicantsDialog).evaluate().length;
          closed = nAfter == 0;
          safe('닫기');
        } catch (e, st) {
          failure = e;
          failureSt = st;
        } finally {
          FlutterError.onError = prevOnError;
        }

        // ③ 성공 · 실패 공통 정리 — 홈 · 창을 내리고 남은 timer · 지연 응답이 끝날 시간을 준다. guard 는 아직 걸려 있다.
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

        // ④ 최종 안전 집계 — 해제 · 대기 뒤 guard 아래에서 센다(값 측정과 분리).
        final loads = fx.failFirst ? 2 : 1;
        final p1ok = _phase1.every((k) => (dayReads.calls[k] ?? 0) == loads);
        final p1Text = [for (final k in _phase1) '$k*${dayReads.calls[k] ?? 0}'].join(',');
        final nUnexp = wire.unexpected.length;
        final nCf = wire.cf.length;
        final nHttp = net.tries.length;
        final tripped = wire.tripped;
        final unText = wire.unexpected.join(' | ');
        _out('D526 $tok att reader p1=$p1ok closed=$closed cf=$nCf unexpected=$nUnexp http=$nHttp');

        messenger.allMessagesHandler = prevAll;
        HttpOverrides.global = prevHttp;
        DayApplicantsReads.debugOverride = prevOverride;
        final exc = t.takeException();
        if (exc != null && failure == null) {
          failure = exc;
          failureSt = StackTrace.current;
        }
        final nOvf = seen.overflows.length;
        final nFw = seen.other.length;
        final ovfRaw = seen.overflows.join('\n----\n');
        final fwRaw = seen.other.join('\n----\n');
        _out('R526 $tok raw m64=${_enc(raw)} ovf64=${_enc(ovfRaw)} fw64=${_enc(fwRaw)} cleanup64=${_enc(cleanupErr)} '
            'fail64=${_enc(failure?.toString() ?? '')}');
        _out('D526 $tok done state=${c.id} mode=$mode captures=$shots overflows=$nOvf exc=${exc != null}');

        final f0 = failure;
        if (f0 != null) {
          _halt ??= '$tok ${f0.toString().split('\n').first}';
          Error.throwWithStackTrace(f0, failureSt ?? StackTrace.current);
        }
        if (!_before) chk('strict 넘침 0', nOvf == 0, ovfRaw);
        chk('미처리 framework 예외 0', nFw == 0, fwRaw);
        chk('캡처 수 = 선언', shots == c.shots, 'shots $shots want ${c.shots}');
        chk('읽기 1단계 호출 수(해제 · 대기 뒤) · 닫힘', p1ok && closed, 'p1 $p1Text want 각 $loads closed $closed');
        chk('시험 전체 CF 0 · 예상 밖 채널 0 · HTTP 0(해제 · 대기 뒤)', nCf == 0 && nUnexp == 0 && nHttp == 0 && !tripped,
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
