// ignore_for_file: depend_on_referenced_packages
// [DU307 DU-ADMIN-HOME-PREP-307] 관리자 홈 머리(8/4/8) + 부분/완전 실패 표현 한 묶음 — before/after 같은 순서.
//   근거: requests/DU_implementation_307.md §1–4, reports/DU_audit_307.md, reports/DU_preparation_307.md §5. production 편집 0.
//   DU307_RUN=1, DU307_PHASE=before|after, DU307_DAY=2026-11-15 일 때만 실행(기본 skip). 실제 KST 날짜·08:00–21:30 도 검증한다.
//   [11-15 자체검토 허브] 실행일 고정만 2026-11-14 → 2026-11-15 로 옮겼다(판정 · 측정 · fixture 무변경).
//   PNG 는 DU1_VQ_PHASE 를 쓰지 않는다(요청 §3 — 회귀 PNG 비활성). 새 시험의 독립 출력 DU307_OUT 에만 쓴다(덮어쓰기 거부).
//   상태(같은 순서, 원점 offset 0, 배너 숨김): G1 W/B/N · G2 W · G3 W/B · G3i W · G4 W/B · G5 W — home mount 10.
//   after 는 준비보고 §5 의 머리 관계·실패 표현·색·receiver·배치 규칙을 단언하고, before 는 같은 측정을 같은 순서로 기록만 한다.
//   입력·무네트워크·무업무쓰기·FlutterError/overflow·계측 유효성·도달 한도(대상당 drag ≤2)는 두 phase 공통이다.
//   하네스: du_concept_cp04_admin_home_test.dart 의 provider·Reads 대역·fixture·폰트를 읽기/축약 복사했다(원 파일 import·등록 0).
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:flutter/foundation.dart' show DiagnosticsTreeStyle, TextTreeRenderer;
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
import 'package:ALfit/utils/text_layout.dart';
import 'package:ALfit/widgets/common/alfit_wordmark.dart';
import 'package:ALfit/widgets/common/notification_badge.dart';

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

class _NoNet extends HttpOverrides {
  int created = 0;
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    created++;
    throw StateError('DU307 network guard');
  }
}

void _out(String l) {
  // ignore: avoid_print
  print(l);
}

const _kDay = '2026-11-15';
const _biz1 = 'biz1';
const _biz2 = 'biz2';
const _bizName = '강남 물류센터';
const _longBiz = '강남구 테헤란로 제2물류센터 야간 상하차 전용 창고'; // CP04 정확 문자열(:66)
const _longName = '응우옌 티 프엉 타오 쩐'; // CP04 정확 문자열(:67)
const _fsBase = 'dev.flutter.pigeon.cloud_firestore_platform_interface.FirebaseFirestoreHostApi';
const _fsOps = [
  'aggregateQuery', 'clearPersistence', 'disableNetwork', 'documentReferenceDelete', 'documentReferenceGet',
  'documentReferenceSet', 'documentReferenceSnapshot', 'documentReferenceUpdate', 'enableNetwork', 'loadBundle',
  'namedQueryGet', 'persistenceCacheIndexManagerRequest', 'queryGet', 'querySnapshot', 'setIndexConfiguration',
  'setLoggingEnabled', 'snapshotsInSyncSetup', 'terminate', 'transactionCreate', 'transactionGet',
  'transactionStoreResult', 'waitForPendingWrites', 'writeBatchCommit',
];
const _fnBase = 'dev.flutter.pigeon.cloud_functions_platform_interface.CloudFunctionsHostApi';
const _fnOps = ['call', 'registerEventChannel'];
const _fnLegacy = 'plugins.flutter.io/firebase_functions';
const _kTol = 0.01;
const _kEps = 1e-6;
// phase 동적 상한 C(요청 §4) — (pump, home mount, tap+dispatch, drag, 명시 route, text, PNG). teardown 빈 mount 는 pump 로 세고 따로 공개한다.
const _kC = (pump: 507, mount: 10, tap: 2, drag: 16, route: 0, text: 0, png: 9); // [307 r1] +G1_N(open 20+teardown 2 pump, mount 1, PNG 1)

// ── 고정 fixture 시각(KST) — 2026-11-13 10:00 KST (실행 허용일과 별도) ──
final DateTime _clock = DateTime.utc(2026, 11, 13, 1);
final DateTime _today = FormatHelper.toKstDate(_clock);
String _ymd(int o) {
  final d = _today.add(Duration(days: o));
  return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

/// 소유자(BUSINESS_ADMIN) — CP04 :70 과 같은 게터 덮개.
class _Owner extends UserProvider {
  _Owner({this.bizIds = const [_biz1], this.displayName = '김관리'});
  final List<String> bizIds;
  final String displayName;
  @override
  UserModel? get currentUser => UserModel(
      uid: 'admin1', username: 'admin1', name: displayName, email: 'admin1@alfit.local',
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
}

/// SubAdmin — CP04 :95 와 같은 판정에 이름만 긴 표본(요청 §2).
class _Sub extends UserProvider {
  _Sub({required this.perms, required this.names, required String current}) : _current = current;
  final Map<String, MemberPermissions> perms;
  final Map<String, String> names;
  final String displayName = _longName;
  final String _current;
  @override
  UserModel? get currentUser => UserModel(
      uid: 'sub1', username: 'sub1', name: displayName, email: 'sub1@alfit.local', role: UserRole.USER,
      subAdminBusinessIds: perms.keys.toList());
  @override
  bool get isSubAdmin => true;
  @override
  bool get permissionsLoaded => true;
  @override
  String? get effectiveBusinessId => _current;
  @override
  Map<String, String> get subAdminBusinessNames => names;
  @override
  bool get subAdminPermissionsLoaded => true;
  @override
  PermissionWatchState get currentBusinessPermissionHealth => PermissionWatchState.verified;
  @override
  PermissionCheck checkCurrentBusiness(bool Function(MemberPermissions p) check) =>
      check(perms[_current] ?? const MemberPermissions()) ? PermissionCheck.allowed : PermissionCheck.denied;
  @override
  bool can(bool Function(MemberPermissions p) check) => check(perms[_current] ?? const MemberPermissions());
  @override
  bool canForAnyBusiness(bool Function(MemberPermissions p) check, {required bool whenUnknown}) => perms.values.any(check);
}

BusinessModel _business(String id, String name) => BusinessModel(
    id: id, name: name, ownerId: 'admin1', businessNumber: '000-00-00000', address: '서울시 어딘가',
    category: '물류', subCategory: '창고', isApproved: true, createdAt: DateTime(2026, 1, 1));

Map<String, dynamic> _bizRow(String id, String name, int req, int conf, int short) =>
    {'businessId': id, 'businessName': name, 'requiredCount': req, 'confirmedCount': conf, 'shortageCount': short};

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

/// 할 일 canonical — CP04 :181 과 같은 CF 직렬화 모양.
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
  UserProvider Function() provider,
  List<BusinessModel> businesses,
  StaffingReadinessModel staffing,
  AdminHomeSummaryModel summary,
  List<ApplicationModel> roster,
});

_Fx _fixture(String g) {
  final single = [_business(_biz1, _bizName)];
  final multi = [_business(_biz1, _bizName), _business(_biz2, _longBiz)];
  final rosterSingle = [
    _app('r1', _biz1, _bizName, '피킹', '09:00', '18:00'),
    _app('r2', _biz1, _bizName, '피킹', '09:00', '18:00'),
    _app('r3', _biz1, _bizName, '피킹', '09:00', '18:00'),
  ];
  switch (g) {
    case 'G1': // CP04 ownerSingle 의 사업장 이름만 긴 정확 문자열
      return (
        provider: () => _Owner(),
        businesses: [_business(_biz1, _longBiz)],
        staffing: _staffing([_day(0, 5, 3, 2), _day(1, 3, 2, 1, pending: 2), _day(3, 2, 2, 0)]),
        summary: _summary(resign: 1, manual: 1, soon: 1, approval: 3, approvalOverdue: 1, schedule: 2, unsent: 1, unclosed: 4, oldest: '2026-11-03'),
        roster: [for (final a in rosterSingle) _app(a.id, _biz1, _longBiz, '피킹', '09:00', '18:00')],
      );
    case 'G2': // CP04 ownerMulti(긴 이름)
      return (
        provider: () => _Owner(bizIds: const [_biz1, _biz2], displayName: _longName),
        businesses: multi,
        staffing: _staffing([
          _day(0, 8, 5, 2, byBusiness: [_bizRow(_biz1, _bizName, 3, 3, 0), _bizRow(_biz2, _longBiz, 5, 2, 2)]),
          _day(2, 4, 1, 3, pending: 1, byBusiness: [_bizRow(_biz1, _bizName, 2, 1, 1), _bizRow(_biz2, _longBiz, 2, 0, 2)]),
        ]),
        summary: _summary(settlement: 1, wageChange: 1, unpaid: 2, unpaidOverdue: 1, missing: 1, expiring: 3, expired: 1),
        roster: [_app('m1', _biz1, _bizName, '피킹', '09:00', '18:00'), _app('m2', _biz2, _longBiz, '포장', '09:30', '13:30')],
      );
    case 'G3': // CP04 subContract(긴 이름)
      return (
        provider: () => _Sub(
            perms: const {_biz1: MemberPermissions(canManageContract: true), _biz2: MemberPermissions(canManageContract: true)},
            names: const {_biz1: _longBiz, _biz2: '강남 물류센터 2공장'},
            current: _biz1),
        businesses: [_business(_biz1, _longBiz)],
        staffing: _staffing([_day(0, 2, 2, 0)]),
        summary: _summary(unsent: 1, expiring: 2),
        roster: const [],
      );
    case 'G4': // CP04 partial(2곳 중 1곳 실패 + summary unsent 미확인)
      return (
        provider: () => _Owner(bizIds: const [_biz1, _biz2]),
        businesses: multi,
        staffing: _staffing([_day(0, 3, 3, 0), _day(1, 2, 1, 1)], partial: true, failed: 1),
        summary: _summary(approval: 2, unavailable: const {'unsent'}),
        roster: rosterSingle,
      );
    default: // G5 인력 완전 실패(hasUsableData=false — 서버 empty 모양)
      return (
        provider: () => _Owner(),
        businesses: single,
        staffing: StaffingReadinessModel.empty(),
        summary: _summary(approval: 1),
        roster: rosterSingle,
      );
  }
}

typedef _V = ({String id, Size size, double scale});
const _V _w = (id: 'W', size: Size(390, 844), scale: 1.0);
const _V _b = (id: 'B', size: Size(320, 640), scale: 2.0);
const _V _n = (id: 'N', size: Size(320, 640), scale: 1.0); // [307 r1] 좁은 화면·정상 글씨(원점 머리 표본만)

/// [307 r1] 배지 표시 입력 고정 — 실제 NotificationProvider 를 상속해 Selector 가 읽는 getter 3개만 고정한다(HTTP·업무 쓰기 0).
///   G1_B·G1_N 에만 쓰고 양 phase 같다. 원 회귀 fixture·사전 106 목록은 바꾸지 않는다.
class _Unread1Notifs extends NotificationProvider {
  @override
  int get unreadCount => 1;
  @override
  bool get hasMore => false;
  @override
  bool get hasError => false;
}

/// [CP03/CP04 C1 r2] 조상 활성 clip 정확 도형(CP03 :222–303 그대로).
class _Clip {
  const _Clip(this.kind, this.type, {this.rect, this.rrect});
  final String kind;
  final String type;
  final Rect? rect;
  final RRect? rrect;
}

bool _inside(_Clip c, Rect r) {
  final corners = [r.topLeft, r.topRight, r.bottomLeft, r.bottomRight];
  switch (c.kind) {
    case 'rect':
      final kr = c.rect!;
      return r.left >= kr.left - 0.5 && r.top >= kr.top - 0.5 && r.right <= kr.right + 0.5 && r.bottom <= kr.bottom + 0.5;
    case 'rrect':
      final kq = c.rrect!.inflate(0.5);
      return corners.every(kq.contains);
    case 'oval':
      final e = c.rect!.inflate(0.5);
      final rx = e.width / 2, ry = e.height / 2;
      if (rx <= 0 || ry <= 0) return false;
      return corners.every((o) {
        final dx = (o.dx - e.center.dx) / rx, dy = (o.dy - e.center.dy) / ry;
        return dx * dx + dy * dy <= 1.0;
      });
  }
  return false;
}

_Clip? _activeClip(RenderObject p, RenderObject c) {
  final type = p.runtimeType.toString();
  if (p is RenderClipRect) {
    if (p.clipBehavior == Clip.none) return null;
    return _Clip('rect', type, rect: p.clipper?.getClip(p.size) ?? Offset.zero & p.size);
  }
  if (p is RenderClipRRect) {
    if (p.clipBehavior == Clip.none) return null;
    return _Clip('rrect', type,
        rrect: p.clipper?.getClip(p.size) ?? p.borderRadius.resolve(p.textDirection).toRRect(Offset.zero & p.size));
  }
  if (p is RenderClipOval) {
    if (p.clipBehavior == Clip.none) return null;
    return _Clip('oval', type, rect: p.clipper?.getClip(p.size) ?? Offset.zero & p.size);
  }
  if (p is RenderClipPath) {
    if (p.clipBehavior == Clip.none) return null;
    if (p.clipper == null) return _Clip('rect', '$type(기본 사각 path)', rect: Offset.zero & p.size);
    return _Clip('unsupported', '$type(사용자 path clipper)');
  }
  if (p is RenderClipRSuperellipse) {
    if (p.clipBehavior == Clip.none) return null;
    return _Clip('unsupported', type);
  }
  if (p is RenderPhysicalModel) {
    if (p.clipBehavior == Clip.none) return null;
    final r = Offset.zero & p.size;
    return _Clip('rrect', type,
        rrect: p.clipper?.getClip(p.size) ??
            (p.shape == BoxShape.circle
                ? RRect.fromRectXY(r, r.width / 2, r.height / 2)
                : (p.borderRadius ?? BorderRadius.zero).toRRect(r)));
  }
  if (p is RenderPhysicalShape) {
    if (p.clipBehavior == Clip.none) return null;
    return _Clip('unsupported', '$type(path clipper)');
  }
  if (p is RenderWrap && p.clipBehavior != Clip.none) return _Clip('unsupported', '$type(넘침 비공개)');
  if (p is RenderAnimatedSize && p.clipBehavior != Clip.none) return _Clip('unsupported', '$type(넘침 비공개)');
  if (p is RenderFittedBox && p.clipBehavior != Clip.none) return _Clip('unsupported', '$type(넘침 비공개)');
  final a = p.describeApproximatePaintClip(c);
  if (a == null) return null;
  if (p is RenderFlex || p is RenderStack || p is RenderConstraintsTransformBox ||
      type == '_RenderSingleChildViewport' || type == '_RenderTheater') {
    return _Clip('rect', type, rect: a);
  }
  return _Clip('unsupported', '$type(근사 clip 만 공개)');
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

void main() {
  final env = Platform.environment;
  final phase = env['DU307_PHASE'] ?? '';
  final dayArg = env['DU307_DAY'] ?? '';
  final outDir = env['DU307_OUT'] ?? '';
  final run = env['DU307_RUN'] == '1' && (phase == 'before' || phase == 'after') && dayArg == _kDay;
  final after = phase == 'after';
  final nl = String.fromCharCode(10);

  setUpAll(() async {
    if (!run) return;
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
    await initializeDateFormatting('ko_KR');
    await _loadFonts();
  });

  testWidgets('D307 $phase', (t) async {
    DateTime kstNow() => DateTime.now().toUtc().add(const Duration(hours: 9));
    final sem = t.ensureSemantics();
    final prevOnError = FlutterError.onError;
    final prevHttp = HttpOverrides.current;
    final net = _NoNet();
    HttpOverrides.global = net;
    final biz = <String, int>{};
    final m = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    for (final op in _fsOps) {
      m.setMockMessageHandler('$_fsBase.$op', (msg) async {
        biz['fs.$op'] = (biz['fs.$op'] ?? 0) + 1;
        return const StandardMessageCodec().encodeMessage(<Object?>['du307-blocked', 'firestore $op 차단', null]);
      });
    }
    for (final op in _fnOps) {
      m.setMockMessageHandler('$_fnBase.$op', (msg) async {
        biz['fn.$op'] = (biz['fn.$op'] ?? 0) + 1;
        return const StandardMessageCodec().encodeMessage(<Object?>['du307-blocked', 'functions $op 차단', null]);
      });
    }
    m.setMockMethodCallHandler(const MethodChannel(_fnLegacy), (call) async {
      biz['fn.legacy.${call.method}'] = (biz['fn.legacy.${call.method}'] ?? 0) + 1;
      throw PlatformException(code: 'du307-blocked', message: 'functions legacy ${call.method} 차단');
    });

    var nPump = 0, nMount = 0, nTap = 0, nDrag = 0, nRoute = 0, nText = 0, nPng = 0, nEmpty = 0;
    Map<String, Object?> counts() => {'phase': phase, 'pump': nPump, 'homeMount': nMount, 'tapDispatch': nTap, 'drag': nDrag,
      'route': nRoute, 'text': nText, 'png': nPng, 'emptyMount': nEmpty};
    var cond = '-';
    var stage = 'start';
    final errors = <({String cond, String stage, int pump, String first, String full})>[];
    FlutterError.onError = (d) => errors.add((
          cond: cond, stage: stage, pump: nPump, first: d.exceptionAsString().split(nl).first,
          full: TextTreeRenderer(wrapWidth: 400).render(d.toDiagnosticsNode(style: DiagnosticsTreeStyle.error)).trimRight(),
        ));
    final visited = <String>[];
    var live = false;
    var completed = false;

    Never stop(String why) {
      _out('D307-STOP ${jsonEncode({'phase': phase, 'cond': cond, 'stage': stage, 'why': why,
        'pendingErrors': errors.map((e) => '${e.cond}/${e.stage}#${e.pump}: ${e.first}').toList(), 'counts': counts(),
        'http': net.created, 'business': biz})}');
      for (final e in errors) {
        _out('D307-STOPERR ${jsonEncode({'cond': e.cond, 'stage': e.stage, 'pump': e.pump, 'full': e.full})}');
      }
      fail('$phase/$cond/$stage: $why');
    }

    void need(bool ok, String why) {
      if (!ok) stop(why);
    }

    void check(bool ok, String what, [Object? detail]) {
      _out('D307-CHECK ${jsonEncode({'phase': phase, 'cond': cond, 'stage': stage, 'what': what, 'ok': ok, 'assert': after, 'detail': detail})}');
      if (after) need(ok, '$what ${detail ?? ''}');
    }

    void budget() {
      final ok = nPump <= _kC.pump && nMount <= _kC.mount && nTap <= _kC.tap && nDrag <= _kC.drag && nRoute <= _kC.route &&
          nText <= _kC.text && nPng <= _kC.png;
      need(ok, '한도 C 초과 ${counts()}');
    }

    void clockGuard(String where) {
      final k = kstNow();
      final min = k.hour * 60 + k.minute;
      final key = '${k.year.toString().padLeft(4, '0')}-${k.month.toString().padLeft(2, '0')}-${k.day.toString().padLeft(2, '0')}';
      need(key == _kDay, '$where 실행일 이탈 kst=$k pin=$dayArg');
      need(min >= 8 * 60 && min < 21 * 60 + 30, '$where 실행 시각 구간 이탈 kst=$k');
    }

    void guard(String where) {
      final ex = t.takeException();
      need(ex == null, '$where 예외: $ex');
      for (final e in errors) {
        _out('D307-ERR ${jsonEncode({'phase': phase, 'cond': e.cond, 'stage': e.stage, 'pump': e.pump, 'first': e.first, 'full': e.full})}');
        stop('FlutterError(허용 0) ${e.first} at $where');
      }
      errors.clear();
      need(net.created == 0, '$where HttpClient ${net.created}');
      need(biz.isEmpty, '$where 업무 채널 $biz');
    }

    Future<void> frames(int n, String where, {int ms = 100}) async {
      for (var i = 0; i < n; i++) {
        nPump++;
        budget();
        await t.pump(Duration(milliseconds: ms));
        guard('$where#$i');
      }
    }

    Finder fe(Element e) => find.byElementPredicate((x) => identical(x, e), skipOffstage: false);
    String plainOf(Element e) => TextLayout.plain((e.widget as RichText).text.toPlainText(includeSemanticsLabels: false));
    Finder richExact(String s, {Finder? within}) {
      bool p(Widget w) => w is RichText && TextLayout.plain(w.text.toPlainText(includeSemanticsLabels: false)) == s;
      return within == null ? find.byWidgetPredicate(p) : find.descendant(of: within, matching: find.byWidgetPredicate(p));
    }

    Finder one(String s, {Finder? within}) {
      final f = richExact(s, within: within);
      need(f.evaluate().length == 1, '"$s" 수 ${f.evaluate().length}');
      return f;
    }

    List<double> rl(Rect r) => [r.left, r.top, r.right, r.bottom];
    bool near(double a, double b, double tol) => (a - b).abs() <= tol;
    Rect boxRect(RenderBox b) => MatrixUtils.transformRect(b.getTransformTo(null), Offset.zero & b.size);
    Rect rectOf(Element e) => boxRect(e.renderObject! as RenderBox);

    Element? nearest(Element e, bool Function(Widget w) p) {
      Element? hit;
      e.visitAncestorElements((a) {
        if (p(a.widget)) {
          hit = a;
          return false;
        }
        return true;
      });
      return hit;
    }

    bool under(Element e, Element anc) {
      var yes = false;
      e.visitAncestorElements((a) {
        if (identical(a, anc)) {
          yes = true;
          return false;
        }
        return true;
      });
      return yes;
    }

    Color? colorOf(Element e) => ((e.widget as RichText).text as TextSpan).style?.color;
    String hex(Color? c) => c == null ? 'null' : c.toARGB32().toRadixString(16);

    bool hitAt(Offset p, Element receiver) {
      final ro = receiver.renderObject;
      final hit = HitTestResult();
      WidgetsBinding.instance.hitTestInView(hit, p, t.view.viewId);
      return hit.path.any((e) => identical(e.target, ro));
    }

    ({bool full, List<String> failures}) clipOf(Element e, Rect screen) {
      final ro = e.renderObject! as RenderBox;
      final failures = <String>[];
      RenderObject c = ro;
      RenderObject? p = ro.parent;
      while (p != null) {
        final clip = _activeClip(p, c);
        if (clip != null) {
          final tr = MatrixUtils.getAsTranslation(ro.getTransformTo(p));
          if (clip.kind == 'unsupported') {
            failures.add('미지원 활성 clip ${clip.type}');
          } else if (tr == null) {
            failures.add('미지원 변환 ~${clip.type}');
          } else if (!_inside(clip, (Offset.zero & ro.size).shift(tr))) {
            failures.add('${clip.type} 밖');
          }
        }
        c = p;
        p = p.parent;
      }
      final g = boxRect(ro);
      final onScreen = g.left >= screen.left - 0.5 && g.top >= screen.top - 0.5 && g.right <= screen.right + 0.5 && g.bottom <= screen.bottom + 0.5;
      if (!onScreen) failures.add('화면 밖 ${rl(g)}');
      return (full: failures.isEmpty, failures: failures);
    }

    void visHit(Element e, String what, Rect screen, {Element? receiver}) {
      final c = clipOf(e, screen);
      final r = rectOf(e);
      final rec = receiver ?? e;
      final hit = hitAt(r.center, rec);
      _out('D307-VIS ${jsonEncode({'phase': phase, 'cond': cond, 'stage': stage, 'what': what, 'rect': rl(r), 'full': c.full,
        'failures': c.failures, 'hit': hit})}');
      if (after) need(c.full && hit, '$what 가시/hit 아님 ${c.failures} hit=$hit');
    }

    Map<String, Object?> para(Element e, String what) {
      final ro = e.renderObject;
      need(ro is RenderParagraph, '$what RenderParagraph 아님');
      final p = ro! as RenderParagraph;
      var placeholder = false;
      p.text.visitChildren((s) {
        if (s is PlaceholderSpan) {
          placeholder = true;
          return false;
        }
        return true;
      });
      need(!placeholder, '$what placeholder — 치수 없이 재구성하지 않는다');
      final ellipsis = p.overflow == TextOverflow.ellipsis;
      final tp = TextPainter(
        text: p.text, textAlign: p.textAlign, textDirection: p.textDirection, textScaler: p.textScaler, maxLines: p.maxLines,
        ellipsis: ellipsis ? '\u2026' : null, locale: p.locale, strutStyle: p.strutStyle, textWidthBasis: p.textWidthBasis,
        textHeightBehavior: p.textHeightBehavior,
      )..layout(minWidth: p.constraints.minWidth, maxWidth: (p.softWrap || ellipsis) ? p.constraints.maxWidth : double.infinity);
      final ts = p.textSize;
      final tpSize = tp.size;
      final cs = p.constraints.constrain(tpSize);
      final ok = near(tpSize.width, ts.width, _kTol) && near(tpSize.height, ts.height, _kTol) && near(cs.width, p.size.width, _kTol) &&
          near(cs.height, p.size.height, _kTol);
      final plain = tp.plainText;
      final lines = <String>[];
      for (final lm in tp.computeLineMetrics()) {
        final b = tp.getLineBoundary(tp.getPositionForOffset(Offset(lm.left + lm.width / 2, lm.baseline - lm.ascent / 2)));
        lines.add(visibleText(plain.substring(b.start, b.end)).trim());
      }
      tp.dispose();
      final textW = nearest(e, (w) => w is Text);
      final st = p.text.style;
      final rec = {'phase': phase, 'cond': cond, 'stage': stage, 'what': what, 'plain': TextLayout.plain(plain), 'lines': lines,
        'scale': p.textScaler.scale(10) / 10, 'size': [p.size.width, p.size.height], 'textSize': [ts.width, ts.height],
        'maxLines': p.maxLines, 'overflow': p.overflow.name, 'didExceedMaxLines': p.didExceedMaxLines,
        'intrinsicH': p.getMinIntrinsicHeight(p.size.width), 'semanticsLabel': textW == null ? null : (textW.widget as Text).semanticsLabel,
        'color': hex(st?.color), 'fontSize': st?.fontSize, 'weight': st?.fontWeight?.value, 'family': st?.fontFamily,
        'locale': p.locale?.toLanguageTag(), 'rect': rl(boxRect(p)), 'reconstructOk': ok};
      _out('D307-PARA ${jsonEncode(rec)}');
      need(ok, '$what TextPainter 재구성 불일치');
      return rec;
    }

    void fullText(Element e, String original, String what) {
      final pr = para(e, what);
      check(pr['plain'] == original, '$what 전문', pr['plain']);
      check(pr['maxLines'] == null && pr['didExceedMaxLines'] == false && pr['overflow'] != 'ellipsis', '$what 말줄임/잘림 0',
          [pr['maxLines'], pr['overflow'], pr['didExceedMaxLines']]);
      final sz = pr['size'] as List;
      check(near(sz[1] as double, pr['intrinsicH'] as double, 0.5), '$what 자연 높이', [sz[1], pr['intrinsicH']]);
      final sl = pr['semanticsLabel'];
      if (sl != null) check(sl == original, '$what 원문 semantics', sl);
    }

    Element? homeScroll() {
      final els = find.descendant(of: find.byType(BusinessAdminHomeScreen),
          matching: find.byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.down)).evaluate().toList();
      return els.isEmpty ? null : els.first;
    }

    double offsetOf(Element? se) => se == null ? 0.0 : ((se as StatefulElement).state as ScrollableState).position.pixels;

    // bounded 세로 drag(대상마다 최대 2회, 위쪽 되돌림 drag 0 — pull-to-refresh 방지)
    //   [11-13 DU306 r3 준비와 같은 식 — 판정 전 임시, 관리자 홈도 AlwaysScrollable(parent: Bouncing)]
    //   dragFrom 은 20 + (D−20) 두 move 다. 인식기는 첫 20 을 버리거나(start) 첫 update 로 넘긴다(down). Bouncing 은 첫 update u 가
    //   3.5 를 넘을 때 u > 24 면 그대로, 아니면 3.5/3 만 움직인다. 그래서 m ≥ 24.5, 보낼 거리 m + 20, 예측 이동 [m, m + 3.5/3] 이다.
    //   위끝·extent 보호로 고를 수 없으면 멈추고, 루프 뒤 목표영역이 창 안인지 확인한다(보고서 DU_preparation_306_r3 §1).
    const kBig = 24.5;
    const kDownExtra = 3.5 / 3;
    Future<void> reach(Element target, String what, Rect screen) async {
      final se0 = homeScroll();
      need(se0 != null, '홈 세로 스크롤 없음');
      final se = se0!;
      final pos = ((se as StatefulElement).state as ScrollableState).position;
      for (var i = 0; i < 2; i++) {
        final r = rectOf(target);
        final vp = boxRect(se.renderObject! as RenderBox).intersect(screen);
        if (r.top >= vp.top - 0.5 && r.bottom <= vp.bottom + 0.5) break;
        need(r.height <= vp.height + 0.5, '$what 높이 ${r.height} > 창 ${vp.height}');
        need(r.bottom > vp.bottom, '$what 가 창 위쪽 — 되돌림 drag 는 쓰지 않는다 ${rl(r)}');
        final d = r.bottom - vp.bottom;
        final hi = r.top - vp.top;
        final slack = (vp.height - r.height) / 2;
        final a = slack < 0 ? 0.0 : (slack > 16 ? 16.0 : slack);
        final room = pos.maxScrollExtent - pos.pixels;
        var m = d + a < kBig ? kBig : d + a;
        if (m + kDownExtra > hi - 0.5) m = hi - 0.5 - kDownExtra;
        if (m + kDownExtra > room) m = room - kDownExtra;
        need(m >= kBig && m >= d, '$what 단일 drag 정확 도달 불가 d=$d hi=$hi room=$room m=$m');
        final send = m + kDragSlopDefault;
        final p0 = pos.pixels;
        nDrag++;
        budget();
        await t.dragFrom(vp.center, Offset(0, -send));
        guard('drag:$what');
        await frames(3, 'drag:$what');
        final moved = pos.pixels - p0;
        _out('D307-REACH ${jsonEncode({'phase': phase, 'cond': cond, 'what': what, 'try': i, 'd': d, 'a': a, 'hi': hi, 'room': room, 'req': m,
          'send': send, 'predicted': [m, m + kDownExtra], 'before': p0, 'after': pos.pixels, 'moved': moved, 'max': pos.maxScrollExtent})}');
      }
      final rf = rectOf(target);
      final vpf = boxRect(se.renderObject! as RenderBox).intersect(screen);
      need(rf.top >= vpf.top - 0.5 && rf.bottom <= vpf.bottom + 0.5, '$what reach 뒤 목표영역이 창 밖 ${rl(rf)} 창 ${rl(vpf)}');
    }

    final capKey = GlobalKey();

    Future<void> open(String id, _V v, UserProvider prov, AdminHomeReads reads, {double topInset = 0, bool unread1 = false}) async {
      cond = id;
      stage = 'mount';
      clockGuard('mount $id');
      SharedPreferences.setMockInitialValues({'tour_completed_business_admin_home': true});
      t.view.physicalSize = v.size;
      t.view.devicePixelRatio = 1.0;
      t.view.padding = topInset > 0 ? FakeViewPadding(top: topInset) : FakeViewPadding.zero;
      t.view.viewPadding = topInset > 0 ? FakeViewPadding(top: topInset) : FakeViewPadding.zero;
      t.platformDispatcher.textScaleFactorTestValue = v.scale;
      t.platformDispatcher.localesTestValue = const [Locale('ko', 'KR')];
      t.platformDispatcher.localeTestValue = const Locale('ko', 'KR');
      nMount++;
      budget();
      await t.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<UserProvider>.value(value: prov),
          ChangeNotifierProvider<NotificationProvider>(create: (_) => unread1 ? _Unread1Notifs() : NotificationProvider()),
        ],
        child: RepaintBoundary(
          key: capKey,
          child: MaterialApp(
            key: ValueKey('D307-$phase-$id'),
            debugShowCheckedModeBanner: false,
            theme: RoleTheme.businessAdminTheme,
            locale: const Locale('ko', 'KR'),
            supportedLocales: const [Locale('ko', 'KR'), Locale('en', 'US')],
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            home: BusinessAdminHomeScreen(reads: reads),
          ),
        ),
      ));
      live = true;
      guard('mount');
      await frames(20, 'load');
      stage = 'origin';
      need(offsetOf(homeScroll()) <= _kEps, '원점 offset 0 아님 ${offsetOf(homeScroll())}');
      final head = one('오늘 운영을 한눈에').evaluate().first;
      need(near((head.renderObject! as RenderParagraph).textScaler.scale(10) / 10, v.scale, 1e-6), '실제 배율 ${v.scale} 아님');
      // [11-13 보완] 환경값은 문자열 상수가 아니라 mount 된 머리 글자 context 에서 실제로 읽는다(요청 §2:21 의 textScaler/locale/
      //   font/굵기 + platform·density·tapTarget). 값의 정확성 판정은 기록이 하고, 이 줄은 기록만 한다.
      final hp = head.renderObject! as RenderParagraph;
      final hTheme = Theme.of(head);
      final hMq = MediaQuery.of(head);
      _out('D307-OPEN ${jsonEncode({'phase': phase, 'cond': id, 'viewport': '${v.size.width.toInt()}x${v.size.height.toInt()}',
        'scale': v.scale, 'topInset': topInset, 'unread1': unread1, 'clock': _clock.toIso8601String(), 'counts': counts(),
        'runtime': {'textScaler10': hp.textScaler.scale(10), 'locale': hp.locale?.toLanguageTag(), 'appLocale': Localizations.localeOf(head).toLanguageTag(),
          'direction': hp.textDirection.name, 'fontFamily': hp.text.style?.fontFamily, 'fontWeight': hp.text.style?.fontWeight?.value,
          'boldText': hMq.boldText, 'mqTextScaler10': hMq.textScaler.scale(10), 'dpr': hMq.devicePixelRatio, 'padding': [hMq.padding.top, hMq.padding.bottom],
          'platform': hTheme.platform.name, 'visualDensity': [hTheme.visualDensity.horizontal, hTheme.visualDensity.vertical],
          'materialTapTargetSize': hTheme.materialTapTargetSize.name, 'useMaterial3': hTheme.useMaterial3,
          'brightness': hTheme.brightness.name, 'primary': hTheme.colorScheme.primary.toARGB32()}})}');
    }

    Future<void> teardown() async {
      stage = 'teardown';
      nPump++;
      nEmpty++;
      budget();
      await t.pumpWidget(const SizedBox.shrink());
      live = false;
      guard('teardown');
      await frames(1, 'teardown', ms: 50);
      t.view.resetPadding();
      t.view.resetViewPadding();
      visited.add(cond);
    }

    // 독립 PNG(DU1_VQ_PHASE 미사용): DU307_OUT/<phase>/D307-<phase>-<cond>-<step>.png + .run.txt(덮어쓰기 거부)
    Future<void> png(String step, _V v) async {
      nPng++;
      budget();
      need(outDir.isNotEmpty, 'DU307_OUT 없음');
      final dir = Directory('$outDir/$phase')..createSync(recursive: true);
      final base = '${dir.path}/D307-$phase-$cond-$step';
      final out = File('$base.png');
      final rj = File('$base.run.txt');
      need(!out.existsSync() && !rj.existsSync(), '이미 있는 캡처를 덮지 않는다 $base');
      final boundary = capKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      await t.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 1.0);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        out.writeAsBytesSync(bytes!.buffer.asUint8List());
      });
      rj.writeAsStringSync({'phase': phase, 'cond': cond, 'step': step, 'viewport': '${v.size.width.toInt()}x${v.size.height.toInt()}',
        'dpr': 1.0, 'textScaler': v.scale, 'locale': 'ko_KR', 'clock': _clock.toIso8601String(), 'offset': offsetOf(homeScroll()),
        'realNow': DateTime.now().toIso8601String(), 'pinDay': dayArg}.entries.map((e) => '${e.key}=${e.value}').join('\n'));
    }

    // [307 r4 정정] 제품 레이아웃 배율 ResponsiveHelper.getScale 표(<360 0.85, <400 0.9, 그 외 1.0)와 같게 둔다.
    //   이전 표(0.82/0.92/1.0/1.08)는 제품 값이 아니었다(r3 TB before 메타→토글 관측 W 9.0·B 8.5 = 10×0.9·10×0.85).
    double sOf(_V v) {
      final w = v.size.width;
      if (w < 360) return 0.85;
      if (w < 400) return 0.9;
      return 1.0;
    }

    double gutterOf(_V v) => v.size.width < 360 ? 16 : 20;

    AdminHomeReads reads(_Fx fx, Map<String, int> calls) {
      void c(String k) => calls[k] = (calls[k] ?? 0) + 1;
      return AdminHomeReads(
        summary: ({String? selectedBusinessId}) {
          c('summary');
          return Future.value(fx.summary);
        },
        businessesByIds: (ids) async {
          c('businesses');
          return fx.businesses;
        },
        staffingReadiness: ({String? selectedBusinessId}) {
          c('staffing');
          return Future.value(fx.staffing);
        },
        attendanceByDate: ({required String businessId, required DateTime date}) async {
          c('attendance');
          return [for (final a in fx.roster) if (a.businessId == businessId) _checkedIn(a)];
        },
        confirmedWorkers: ({required DateTime date, required String businessId}) async {
          c('roster');
          return [for (final a in fx.roster) if (a.businessId == businessId) a];
        },
        workDetailTimes: (_) async {
          c('workDetail');
          return <String, dynamic>{};
        },
        postingReadiness: (bizs) async {
          c('posting');
          return _ready(bizs);
        },
        contractTemplates: (_) async {
          c('templates');
          return <ContractTemplateModel>[_Template()];
        },
        tourCompleted: () {
          c('tour');
          return Future<bool>.value(true);
        },
        clock: () => _clock,
        legalReadiness: () async {
          c('legal');
          return const LegalReadiness(status: LegalReadinessStatus.current);
        },
      );
    }

    // ── S-H 머리 관계 ──
    // [307 r1 L2] 배지(unread 1·hasMore false·hasError false 고정 입력) — 같은 frame 에서 위 끝 ≥ 머리 시작·SafeArea, 아래 끝 ≤ 행동행 아래,
    //   로고 잉크·관리 버튼 receiver 와 겹침 0, 숫자 전문 가시, 종 침범 기준(Icon layout rect: 중심 밖·겹침 ≤25%). 실제 잉크 가림은 PNG 직접 열람.
    void badgeCheck(Rect header, Rect row, Rect? ink, Rect manage, Rect screen, double safeTop) {
      stage = 'badge';
      final nb = find.byType(NotificationBadge);
      need(nb.evaluate().length == 1, '알림 배지 위젯 수 ${nb.evaluate().length}');
      final txt = find.descendant(of: nb, matching: find.text('1'));
      need(txt.evaluate().length == 1, '배지 숫자 1 수 ${txt.evaluate().length}');
      final br = rectOf(find.ancestor(of: txt, matching: find.byType(Container)).evaluate().first);
      final tr = rectOf(txt.evaluate().first);
      final gl = find.descendant(of: nb, matching: find.byIcon(Icons.notifications_outlined)).evaluate().toList();
      final gr = gl.isEmpty ? null : rectOf(gl.first);
      final gi = gr == null ? null : br.intersect(gr);
      final glyphOv = gi == null || gi.width <= 0 || gi.height <= 0 ? 0.0 : gi.width * gi.height;
      final glyphArea = gr == null ? 0.0 : gr.width * gr.height;
      final logoOv = ink != null && br.overlaps(ink);
      final manageOv = br.overlaps(manage);
      final c = clipOf(txt.evaluate().first, screen);
      _out('D307-BADGE ${jsonEncode({'phase': phase, 'cond': cond, 'badge': rl(br), 'text': rl(tr), 'header': rl(header), 'row': rl(row),
        'safeTop': safeTop, 'glyph': gr == null ? null : rl(gr), 'glyphOverlapArea': glyphOv, 'glyphArea': glyphArea, 'logoOverlap': logoOv,
        'manage': rl(manage), 'manageOverlap': manageOv, 'textFull': c.full, 'failures': c.failures})}');
      check(br.top >= header.top - _kTol && br.top >= safeTop - _kTol, 'S-BADGE 위 끝 ≥ 머리 시작·SafeArea', [br.top, header.top, safeTop]);
      check(br.bottom <= row.bottom + _kTol, 'S-BADGE 아래 끝 ≤ 행동행 아래', [br.bottom, row.bottom]);
      check(!logoOv, 'S-BADGE 로고 잉크 겹침 0', rl(br));
      check(!manageOv, 'S-BADGE 관리 버튼 겹침 0', [rl(br), rl(manage)]);
      check(c.full, 'S-BADGE 숫자 전문 가시', c.failures);
      check(gr != null && !br.contains(gr.center) && glyphOv <= 0.25 * glyphArea + _kTol, 'S-BADGE 종 침범 기준(중심 밖·겹침 ≤25%)',
          [gr == null ? null : rl(gr), glyphOv, glyphArea]);
      stage = 'header';
    }

    void headerCheck(_V v, String name, {bool sub = false, double topInset = 0, bool badge = false}) {
      stage = 'header';
      final screen = Offset.zero & v.size;
      final s = sOf(v);
      final wm = find.byType(AlfitWordmark).evaluate().toList();
      need(wm.length == 1, '로고 수 ${wm.length}');
      final logoEl = wm.first;
      final headerEl = nearest(logoEl, (w) => w is Container)!;
      final rowEl = nearest(logoEl, (w) => w is Row)!;
      final header = rectOf(headerEl), row = rectOf(rowEl), logo = rectOf(logoEl);
      Element btn(IconData icon) {
        final ic = find.descendant(of: fe(headerEl), matching: find.byIcon(icon)).evaluate().toList();
        need(ic.length == 1, '머리 아이콘 $icon 수 ${ic.length}');
        return nearest(ic.first, (w) => w is InkWell)!;
      }

      final bell = rectOf(btn(Icons.notifications_outlined)), manage = rectOf(btn(Icons.settings_outlined));
      final nameEl = one('$name님').evaluate().first;
      final nameR = rectOf(nameEl);
      final wrapEl = nearest(nameEl, (w) => w is Wrap)!;
      final wrapR = rectOf(wrapEl);
      // [307 r4 정정] 요청 §1:17 'Wrap 내부 다음행 4'는 layout box 사이다 — 배지 안 첫 RichText(아이콘 글리프, 48 배지 안 세로 중앙)가
      //   아니라 identity Wrap 의 둘째 자식 상자(역할 배지)를 잰다. 자식은 이름·역할 배지 정확 2개다.
      final wrapRo = wrapEl.renderObject! as RenderWrap;
      final wrapKids = <RenderBox>[];
      var wk = wrapRo.firstChild;
      while (wk != null) {
        wrapKids.add(wk);
        wk = wrapRo.childAfter(wk);
      }
      need(wrapKids.length == 2, 'identity Wrap 자식 수 ${wrapKids.length}');
      final Rect? badgeR = wrapKids.length < 2 ? null : boxRect(wrapKids[1]);
      final badgeNextLine = badgeR != null && badgeR.top >= nameR.bottom - 0.5;
      final metaCol = nearest(wrapEl, (w) => w is Column)!;
      final metaR = rectOf(metaCol);
      final metaKids = find.descendant(of: fe(metaCol), matching: find.byType(RichText)).evaluate()
          .where((e) => !under(e, wrapEl)).toList();
      final scopeR = metaKids.isEmpty ? null : rectOf(metaKids.first);
      final head = one('오늘 운영을 한눈에').evaluate().first;
      final headR = rectOf(head);
      final safe = find.descendant(of: find.byType(BusinessAdminHomeScreen), matching: find.byType(SafeArea)).evaluate().first;
      final safePad = (safe.renderObject! as RenderPadding).padding.resolve(TextDirection.ltr);
      final semData = t.getSemantics(fe(logoEl)).getSemanticsData();
      final inkEls = find.descendant(of: fe(logoEl), matching: find.byType(CustomPaint)).evaluate().toList();
      final ink = inkEls.isEmpty ? null : rectOf(inkEls.first);
      // 뒤 역할 전환 줄 = 머리 Column 의 마지막 자식(SubAdmin 만). 그 앞 자식이 SizedBox(10s), 그 앞이 메타 Column 이다.
      final hcol = find.descendant(of: fe(headerEl), matching: find.byType(Column)).evaluate().first.renderObject! as RenderFlex;
      final kids = <RenderBox>[];
      var kc = hcol.firstChild;
      while (kc != null) {
        kids.add(kc);
        kc = hcol.childAfter(kc);
      }
      final Rect? toggleR = sub ? boxRect(kids.last) : null;
      final rec = {'phase': phase, 'cond': cond, 's': s, 'gutter': gutterOf(v), 'header': rl(header), 'row': rl(row), 'logo': rl(logo),
        'bell': rl(bell), 'manage': rl(manage), 'name': rl(nameR), 'badge': badgeR == null ? null : rl(badgeR), 'badgeNextLine': badgeNextLine,
        'wrap': rl(wrapR), 'scope': scopeR == null ? null : rl(scopeR), 'meta': rl(metaR), 'toggle': toggleR == null ? null : rl(toggleR),
        'head': rl(headR), 'rowTopGap': row.top - header.top, 'rowToName': nameR.top - row.bottom,
        'wrapRun': badgeNextLine ? badgeR.top - nameR.bottom : null, 'wrapToScope': scopeR == null ? null : scopeR.top - wrapR.bottom,
        'metaToToggle': toggleR == null ? null : toggleR.top - metaR.bottom, 'lastToHead': headR.top - header.bottom,
        'safeTop': safePad.top, 'logoSem': [semData.label, semData.flagsCollection.isImage], 'ink': ink == null ? null : rl(ink)};
      _out('D307-HEADER ${jsonEncode(rec)}');
      if (topInset > 0) need(near(safePad.top, topInset, _kTol) && near(header.top, topInset, _kTol), 'SafeArea 실제 inset ${safePad.top}/머리 ${header.top}');
      // [307 r1 L2] 머리 위 8 → 0. 잉크 top 일반식 = 행 top + (실제 행 높이 − 28)/2 + 2 — 행 48·배너 숨김이면 SafeArea top + 12, G3i(inset 24)면 36.
      check(near(row.top - header.top, 0, _kTol), 'S-H 행동행 위 − 머리 시작 = 0(L2)', row.top - header.top);
      if (topInset > 0) check(near(row.top, topInset, _kTol), 'S-H G3i 행동행 위 = inset', row.top);
      final inkTopWant = row.top + (row.height - 28) / 2 + 2;
      check(ink != null && near(ink.top, inkTopWant, _kTol), 'S-H 잉크 top = 행 top + (행높이−28)/2 + 2', [ink?.top, inkTopWant, row.height]);
      if (near(row.height, 48, _kTol)) {
        check(ink != null && near(ink.top, safePad.top + 12, _kTol), 'S-H 행 48 잉크 top = SafeArea + 12', [ink?.top, safePad.top]);
      }
      check(ink != null && near(ink.width, 24 * 2558.55 / 794.8, _kTol), 'S-H 잉크 폭 = 24×2558.55/794.8', ink?.width);
      check(near(logo.left, gutterOf(v), _kTol) && near(logo.left, headR.left, _kTol), 'S-H 로고 왼쪽 = gutter = 큰머리 왼쪽', [logo.left, headR.left]);
      check(logo.width >= 84 - _kEps && logo.height >= 28 - _kEps && semData.label == 'ALfit' && semData.flagsCollection.isImage,
          'S-H 로고 slot ≥84×28·이미지 의미', [logo.width, logo.height]);
      check(ink != null && near(ink.height, 24, _kTol), 'S-H 로고 잉크 24(slot 과 분리)', ink == null ? null : rl(ink));
      for (final (n, r) in [('알림', bell), ('관리', manage)]) {
        check(r.width >= 48 - _kEps && r.height >= 48 - _kEps && (logo.center.dy - r.center.dy).abs() <= 0.5, 'S-H $n 48·세로 중심',
            [r.width, r.height, (logo.center.dy - r.center.dy).abs()]);
      }
      // [307 r4 정정] 요청 §1:17 '행동행→계정메타 8'은 layout box 사이다 — 메타 Column(첫 자식 identity Wrap) 위 끝을 잰다.
      //   이름 글자 top 은 같은 줄 배지가 더 크면 Wrap 세로 중앙 정렬로 그만큼 내려간다(기록 rowToName 으로 남긴다).
      check(near(metaR.top - row.bottom, 8, _kTol), 'S-H 행동행 → 계정 메타 = 8', metaR.top - row.bottom);
      if (badgeNextLine) check(near(badgeR.top - nameR.bottom, 4, _kTol), 'S-H Wrap 다음 행 4', badgeR.top - nameR.bottom);
      if (scopeR != null) check(near(scopeR.top - wrapR.bottom, 4, _kTol), 'S-H identity → 사업장/권한 = 4', scopeR.top - wrapR.bottom);
      if (toggleR != null) check(near(toggleR.top - metaR.bottom, 10 * s, _kTol), 'S-H 메타 → 토글 = 10s(보존)', toggleR.top - metaR.bottom);
      check(near(headR.top - header.bottom, 8, _kTol), 'S-H 마지막 머리 → 큰머리 = 8', headR.top - header.bottom);
      fullText(nameEl, '$name님', '이름');
      visHit(nameEl, '이름', screen);
      if (badge) badgeCheck(header, row, ink, manage, screen, safePad.top);
      if (!sub && scopeR != null) {
        final se = metaKids.first;
        final plain = plainOf(se);
        fullText(se, plain, '사업장 줄');
        visHit(se, '사업장 줄', screen);
      }
    }

    // 실패 행(부분합 고지·업무 부분/전체·인력 완전 실패) — 색·아이콘·receiver·배치 규칙
    Map<String, Object?> failRow(Element body, String what, _V v, {required bool partialExpected}) {
      final screen = Offset.zero & v.size;
      final lb = nearest(body, (w) => w is LayoutBuilder);
      need(lb != null, '$what 배치 LayoutBuilder 없음');
      final lbEl = lb!;
      final retry = one('다시 시도', within: fe(lbEl)).evaluate().first;
      final rcv = nearest(retry, (w) => w is GestureDetector)!;
      final rr = rectOf(rcv);
      final icons = find.descendant(of: fe(lbEl), matching: find.byIcon(Icons.cloud_off_outlined)).evaluate().toList();
      final iconEl = icons.isEmpty ? null : icons.first;
      final iconW = iconEl == null ? null : iconEl.widget as Icon;
      final iconR = iconEl == null ? null : rectOf(iconEl);
      final excluded = iconEl != null && nearest(iconEl, (w) => w is ExcludeSemantics) != null;
      final bodyR = rectOf(body);
      final stacked = rr.top >= bodyR.bottom - 0.01;
      // 기대 배치(독립 측정): need = 공백으로 나눈 한 단위 최대 폭, inline = maxW − leading16 − gap6 − 8 − max(48, retry 한 줄)
      final p = body.renderObject! as RenderParagraph;
      var needW = 0.0;
      for (final u in p.text.toPlainText(includeSemanticsLabels: false).split(' ')) {
        if (u.isEmpty) continue;
        final tp = TextPainter(text: TextSpan(text: u, style: p.text.style), textDirection: p.textDirection, textScaler: p.textScaler,
            locale: p.locale, textWidthBasis: p.textWidthBasis, textHeightBehavior: p.textHeightBehavior, maxLines: 1)
          ..layout();
        needW = math.max(needW, tp.maxIntrinsicWidth);
        tp.dispose();
      }
      final rp = retry.renderObject! as RenderParagraph;
      final retryW = math.max(48.0, rp.getMaxIntrinsicWidth(double.infinity));
      final maxW = rectOf(lbEl).width;
      final lead = iconEl != null ? 16.0 + 6.0 : 0.0;
      final inlineBody = maxW - lead - 8 - retryW;
      final ok = inlineBody >= needW && inlineBody >= maxW * 0.5;
      final bnd = (inlineBody - needW).abs() <= 0.5 || (inlineBody - maxW * 0.5).abs() <= 0.5;
      final expect = bnd ? 'boundary' : (ok ? 'inline' : 'stacked');
      final align = iconR == null ? null : (stacked ? iconR.top - bodyR.top : iconR.center.dy - bodyR.center.dy);
      final rec = {'phase': phase, 'cond': cond, 'what': what, 'text': plainOf(body), 'textColor': hex(colorOf(body)),
        'icon': iconW == null ? null : {'size': iconW.size, 'color': hex(iconW.color), 'excludeSemantics': excluded, 'rect': rl(iconR!)},
        'retry': hex(colorOf(retry)), 'receiver': rl(rr), 'layout': stacked ? 'stacked' : 'inline', 'expect': expect, 'maxW': maxW,
        'need': needW, 'inlineBody': inlineBody, 'align': align, 'body': rl(bodyR)};
      _out('D307-FAILROW ${jsonEncode(rec)}');
      if (partialExpected) {
        check(colorOf(body) == AppColors.textSecondary, '$what 문장 textSecondary', hex(colorOf(body)));
        check(iconW != null && iconW.size == 16 && iconW.color == AppColors.warningDark && excluded, '$what 앞 아이콘 16/warningDark/의미 0');
        check(align != null && near(align, 0, _kTol), '$what 아이콘↔문장 ${stacked ? '위' : '세로 중심'} 정렬', align);
      } else {
        check(colorOf(body) == AppColors.errorDark, '$what 문장 errorDark', hex(colorOf(body)));
      }
      check(colorOf(retry) == AppColors.brand, '$what 다시 시도 brand', hex(colorOf(retry)));
      check(rr.width >= 48 - _kEps && rr.height >= 48 - _kEps, '$what 다시 시도 receiver ≥48×48', rl(rr));
      check(expect == 'boundary' || expect == (stacked ? 'stacked' : 'inline'), '$what 배치 = _rowWithTrailing 규칙', [expect, stacked]);
      fullText(body, plainOf(body), what);
      visHit(retry, '$what 다시 시도', screen, receiver: rcv);
      return {'receiver': rcv, 'rec': rec};
    }

    Element heroIconCircle(String message) {
      final msg = one(message).evaluate().first;
      final rowE = nearest(msg, (w) => w is Row)!;
      final circ = find.descendant(of: fe(rowE), matching: find.byWidgetPredicate((w) => w is Container &&
          w.decoration is BoxDecoration && (w.decoration! as BoxDecoration).shape == BoxShape.circle)).evaluate().toList();
      need(circ.length == 1, 'Hero 아이콘 원 수 ${circ.length}');
      return circ.first;
    }

    void heroCheck(String message, Color want, String what) {
      final c = heroIconCircle(message);
      final deco = (c.widget as Container).decoration! as BoxDecoration;
      final ic = find.descendant(of: fe(c), matching: find.byIcon(Icons.cloud_off_outlined)).evaluate().toList();
      final icColor = ic.length == 1 ? (ic.first.widget as Icon).color : null;
      _out('D307-HERO ${jsonEncode({'phase': phase, 'cond': cond, 'message': message, 'circle': hex(deco.color), 'icon': hex(icColor)})}');
      check(icColor == want && deco.color == want.withValues(alpha: 0.10), '$what Hero 아이콘·원 색', [hex(icColor), hex(deco.color)]);
    }

    final sw = Stopwatch()..start();
    try {
      clockGuard('start');
      _out('D307-ENV ${jsonEncode({'phase': phase, 'pinDay': dayArg, 'realNow': DateTime.now().toIso8601String(), 'kst': kstNow().toIso8601String(),
        'clock': _clock.toIso8601String(), 'injected': {'theme': 'RoleTheme.businessAdminTheme', 'locale': 'ko_KR', 'dpr': 1.0, 'boldText': false},
        'C': '$_kC', 'out': outDir, 'vqPhase': env['DU1_VQ_PHASE'] ?? '(unset)'})}');
      need((env['DU1_VQ_PHASE'] ?? '').isEmpty, 'DU1_VQ_PHASE 가 설정됨(요청 §3: unset)');

      // ═══ G1 W/B — ownerSingle 긴 사업장 ═══
      for (final v in const [_w, _b]) {
        final calls = <String, int>{};
        final fx = _fixture('G1');
        await open('G1_${v.id}', v, fx.provider(), reads(fx, calls), unread1: v.id == 'B');
        need(richExact(_longBiz).evaluate().isNotEmpty, 'G1 긴 사업장 줄 없음');
        headerCheck(v, '김관리', badge: v.id == 'B');
        await png('origin', v);
        await teardown();
      }
      // ═══ [307 r1] G1_N — 320×640·1.0(좁은 화면·정상 글씨) 원점 머리 표본 1장. reach·tap·route·text 0, 배지 입력 unread 1 ═══
      {
        final v = _n;
        final calls = <String, int>{};
        final fx = _fixture('G1');
        await open('G1_N', v, fx.provider(), reads(fx, calls), unread1: true);
        need(richExact(_longBiz).evaluate().isNotEmpty, 'G1_N 긴 사업장 줄 없음');
        headerCheck(v, '김관리', badge: true);
        await png('origin', v);
        await teardown();
      }
      // ═══ G2 W — ownerMulti 긴 이름 ═══
      {
        final calls = <String, int>{};
        final fx = _fixture('G2');
        await open('G2_W', _w, fx.provider(), reads(fx, calls));
        headerCheck(_w, _longName);
        await png('origin', _w);
        await teardown();
      }
      // ═══ G3 W/B — subContract(뒤 역할 전환) ═══
      for (final v in const [_w, _b]) {
        final calls = <String, int>{};
        final fx = _fixture('G3');
        await open('G3_${v.id}', v, fx.provider(), reads(fx, calls));
        need(richExact('지원자').evaluate().length == 1 && richExact('관리자').evaluate().isNotEmpty, 'G3 뒤 역할 전환 노출 아님');
        headerCheck(v, _longName, sub: true);
        await png('origin', v);
        await teardown();
      }
      // ═══ G3i W — G3 + 실제 상단 inset 24 ═══
      {
        final calls = <String, int>{};
        final fx = _fixture('G3');
        await open('G3i_W', _w, fx.provider(), reads(fx, calls), topInset: 24);
        headerCheck(_w, _longName, sub: true, topInset: 24);
        await teardown();
      }
      // ═══ G4 W/B — partial(부분합 고지·업무 일부 미확인·Hero partial) + 부분합 다시 시도 물리 탭 ═══
      for (final v in const [_w, _b]) {
        final screen = Offset.zero & v.size;
        final calls = <String, int>{};
        final fx = _fixture('G4');
        await open('G4_${v.id}', v, fx.provider(), reads(fx, calls));
        stage = 'partial';
        need(richExact('오늘 상황을 일부만 확인했어요').evaluate().length == 1, 'G4 Hero partial 분기 아님');
        heroCheck('오늘 상황을 일부만 확인했어요', AppColors.warningDark, 'G4');
        await png('origin', v);
        const staffingMsg = '사업장 1곳의 정보를 불러오지 못해 나머지 사업장 기준으로 표시했어요';
        const taskMsg = '일부 업무 상태를 확인하지 못했어요';
        need(richExact(staffingMsg).evaluate().length == 2, 'G4 부분합 고지 수 2 아님');

        Element staffingNoticeIn(String title, String otherTitle) {
          final titleEl = one(title).evaluate().single;
          Element? section;
          titleEl.visitAncestorElements((a) {
            if (a.widget is! Column) return true;
            if (richExact(staffingMsg, within: fe(a)).evaluate().length != 1) return true;
            section = a;
            return false;
          });
          need(section != null, 'G4 $title 부분합 고지 구획 없음');
          final scope = fe(section!);
          need(richExact(title, within: scope).evaluate().length == 1, 'G4 $title 구획 제목 수 1 아님');
          need(richExact(otherTitle, within: scope).evaluate().isEmpty, 'G4 $title 구획에 $otherTitle 포함');
          return one(staffingMsg, within: scope).evaluate().single;
        }

        final sm = staffingNoticeIn('오늘의 근무', '다가오는 근무');
        final upcomingSm = staffingNoticeIn('다가오는 근무', '오늘의 근무');
        need(!identical(sm, upcomingSm), 'G4 두 구획의 부분합 고지가 같음');
        await reach(nearest(sm, (w) => w is LayoutBuilder)!, '부분합 고지', screen);
        final r1 = failRow(staffingNoticeIn('오늘의 근무', '다가오는 근무'), '부분합 고지', v, partialExpected: true);
        // 부분합 다시 시도 물리 탭 → staffing +1, 다른 loader 불변
        stage = 'retryTap';
        final before = Map<String, int>.of(calls);
        final rcv = r1['receiver']! as Element;
        need(hitAt(rectOf(rcv).center, rcv), '부분합 다시 시도 중심 hit 아님');
        nTap++;
        budget();
        await t.tapAt(rectOf(rcv).center);
        guard('tap:부분합 다시 시도');
        await frames(6, 'retryTap');
        final diff = {for (final k in {...before.keys, ...calls.keys}) k: (calls[k] ?? 0) - (before[k] ?? 0)}..removeWhere((k, d) => d == 0);
        _out('D307-RETRY-TAP ${jsonEncode({'phase': phase, 'cond': cond, 'before': before, 'after': calls, 'diff': diff})}');
        need(diff.length == 1 && diff['staffing'] == 1, '부분합 다시 시도 → staffing +1 만이 아님 $diff');
        stage = 'partial';
        final tm = one(taskMsg).evaluate().first;
        await reach(nearest(tm, (w) => w is LayoutBuilder)!, '업무 일부 미확인', screen);
        failRow(one(taskMsg).evaluate().first, '업무 일부 미확인', v, partialExpected: true);
        await teardown();
      }
      // ═══ G5 W — 인력 완전 실패(hasUsableData=false) ═══
      {
        final v = _w;
        final screen = Offset.zero & v.size;
        final calls = <String, int>{};
        final fx = _fixture('G5');
        await open('G5_W', v, fx.provider(), reads(fx, calls));
        stage = 'fail';
        need(richExact('오늘 상황을 확인하지 못했어요').evaluate().length == 1, 'G5 Hero error 분기 아님');
        heroCheck('오늘 상황을 확인하지 못했어요', AppColors.errorDark, 'G5');
        await png('origin', v);
        final heroMsg = one('오늘 상황을 확인하지 못했어요').evaluate().first;
        final heroCol = nearest(heroMsg, (w) => w is Column)!;
        final rows = richExact('인력 정보를 불러오지 못했어요').evaluate().where((e) => !under(e, heroCol)).toList();
        need(rows.length == 1, 'G5 오늘 운영 실패 행 수 ${rows.length}');
        await reach(nearest(rows.first, (w) => w is LayoutBuilder)!, '오늘 운영 실패 행', screen);
        final again = richExact('인력 정보를 불러오지 못했어요').evaluate().where((e) => !under(e, nearest(one('오늘 상황을 확인하지 못했어요').evaluate().first, (w) => w is Column)!)).toList();
        need(again.length == 1, 'G5 reach 뒤 오늘 운영 실패 행 수 ${again.length}');
        failRow(again.first, '인력 완전 실패 행', v, partialExpected: false);
        await teardown();
      }

      const want = 'G1_W|G1_B|G1_N|G2_W|G3_W|G3_B|G3i_W|G4_W|G4_B|G5_W';
      need(visited.join('|') == want, '방문 $visited');
      // [307 r1] G1_N 포함 10장면 — 방문 10·C.mount 10 과 같은 종료 계수(단언 유지, 상한 확대 0)
      need(nMount == 10 && nPng == 9 && nTap == 2 && nRoute == 0 && nText == 0, '실행량 ${counts()}');
      clockGuard('end');
      need(net.created == 0 && biz.isEmpty && errors.isEmpty && !live, '최종 상태 http=${net.created} business=$biz pending=${errors.length} live=$live');
      _out('D307-END ${jsonEncode({...counts(), 'visited': visited, 'http': net.created, 'business': biz, 'elapsedMs': sw.elapsedMilliseconds})}');
      completed = true;
    } finally {
      var cleanup = 'not-needed';
      var cleanPump = 0, cleanEmpty = 0;
      final cleanErrors = <String>[for (final e in errors) 'pending-before-cleanup ${e.cond}/${e.stage}#${e.pump}: ${e.first}'];
      errors.clear();
      if (live) {
        try {
          cleanEmpty++;
          await t.pumpWidget(const SizedBox.shrink());
          live = false;
          for (var i = 0; i < 2; i++) {
            cleanPump++;
            await t.pump(const Duration(milliseconds: 50));
          }
          final ex = t.takeException();
          if (ex != null) cleanErrors.add('cleanup-exception $ex');
          cleanup = 'done';
        } catch (e) {
          cleanup = 'failed $e';
        }
        for (final e in errors) {
          cleanErrors.add('during-cleanup ${e.cond}/${e.stage}#${e.pump}: ${e.first}');
        }
      }
      _out('D307-FINAL ${jsonEncode({...counts(), 'outcome': completed ? 'completed' : 'failed', 'cleanup': cleanup, 'cleanupEmptyMount': cleanEmpty,
        'cleanupPump': cleanPump, 'stillMounted': live, 'visited': visited, 'http': net.created, 'business': biz, 'cleanupErrors': cleanErrors,
        'elapsedMs': sw.elapsedMilliseconds})}');
      for (final op in _fsOps) {
        m.setMockMessageHandler('$_fsBase.$op', null);
      }
      for (final op in _fnOps) {
        m.setMockMessageHandler('$_fnBase.$op', null);
      }
      m.setMockMethodCallHandler(const MethodChannel(_fnLegacy), null);
      FlutterError.onError = prevOnError;
      HttpOverrides.global = prevHttp;
      t.platformDispatcher.clearLocalesTestValue();
      t.platformDispatcher.clearLocaleTestValue();
      t.platformDispatcher.clearTextScaleFactorTestValue();
      t.view.reset();
      sem.dispose();
    }
  }, skip: !run, timeout: const Timeout(Duration(minutes: 4)));
}
