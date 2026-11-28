// ignore_for_file: depend_on_referenced_packages
// [DU585b · 장부 BL-19 · 판정148 §5 F148-B-TASK-READING(:54) · F148-N-UPCOMING-REFLOW(:56) · 판정170 §2 DU578(:35)] DU-S010 관리자 홈 행 배치 —
//   B 처리할 일 행의 낱말 쌓임(좁은 문장 폭) · N 다가오는 근무 행 · 다시 시도 도달 비교.
//   before = 지금 A(business_admin_home_screen 78951f7c = DU578 후보) 기록 · strict = 후보(prep/mk_cand.py · 처리할 일 행만 pairWords).
//   하네스 = 블록 재사용(prep/mk_test.py 가 원본 바이트 대조 · 정규화 목록 그대로):
//     DU578 시험(d66803ec · 지금 A 홈 바이트 위 정규 DONE 5/5 21:30) — 가짜 Firebase · _Owner · 고정 시각 · 대역 꼴 · AdminHomeReads 주입 · 채널/HTTP 관찰 ·
//       글꼴 · 넘침 수집 · _spansOf/_sig · max 판 _fullShown · _textObs · _area · _lineCount · 보기 W/B/N · opt-in · setUpAll · 사례 진입/정리/집계 뼈대 ·
//       _txt · _bringBuilt · _hex · _fills.
//     DU562 시험(2c2ac83a) — _hitWithin(받는 자리 중심 hit) · DU555 r2 시험(2f73569f) — _fut(다가오는 날짜 이름).
//   새로 쓴 것: 이 머리 · 사례 2(NORM = DU578 NORM 대역 값 그대로 · LONG = DU555 LONG 대역 값 그대로 = DU578 MULTI + 부분 실패 1곳) · 행 표(_tasksOf · _nextOf) ·
//     _layAt(DU307 du1_admin_home_307_test.dart:633 D307-PARA 의 TextPainter 재구성 꼴 — 같은 문단을 다른 폭에 다시 놓은 줄 수 · 낱말 하나뿐인 줄 수) ·
//     행 측정(_taskObs · _nextObs · _rtObs) · 출력 줄(sub 마다 리터럴).
//   누르는 것 0 · 입력 0 · 끌기 0(ensureVisible · 안 지어졌을 때만 scrollUntilVisible) · 업무 writer 0. 기본 skip — TB before/du585bbl19-tb/DU_BEFORE_OBSERVE=585 · TA after/du585bbl19-ta/없음.
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui show BoxHeightStyle;

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
import 'package:ALfit/utils/text_layout.dart';

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

/// [DU585b] 상태별 대역 — 각 사례가 새로 만든다(공유 상태 0).
///   NORM = DU578 NORM(= DU555 NORM = CP04 ownerSingle) 값 그대로 — 판정148 :54 의 B 할 일 행(첫 행 `퇴사 요청`)이 나온 대역.
///   LONG = DU555 LONG(= CP04 ownerMulti + partial 2곳 중 1곳 실패) 값 그대로 — 판정148 :56 의 N-LONG 다가오는 행 · 부분 실패 `다시 시도` 2곳(같은 행 판정기 소비처).
_Fx _fixture(String id) {
  final single = [_business(_biz1, _bizName)];
  final multi = [_business(_biz1, _bizName), _business(_biz2, _longBiz)];
  if (id == 'NORM') {
    return (
      bizIds: const [_biz1],
      businesses: single,
      staffing: _staffing([_day(0, 5, 3, 2), _day(1, 3, 2, 1, pending: 2), _day(3, 2, 2, 0)]),
      summary: _summary(resign: 1, manual: 1, soon: 1, approval: 3, approvalOverdue: 1, schedule: 2, unsent: 1,
          unclosed: 4, oldest: '2026-11-03'),
      roster: [
        _app('r1', _biz1, _bizName, '피킹', '09:00', '18:00'),
        _app('r2', _biz1, _bizName, '피킹', '09:00', '18:00'),
        _app('r3', _biz1, _bizName, '피킹', '09:00', '18:00'),
      ],
    );
  }
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
}

/// 다가오는 근무 날짜 이름(홈 _futureDateLabel 과 같은 식 — 내일이면 '내일').
String _fut(int o) {
  final d = _today.add(Duration(days: o));
  return o == 1 ? '내일' : FormatHelper.formatDate(DateTime(d.year, d.month, d.day));
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
const _authFake = 'du585b.fake.auth.';

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
    throw const SocketException('DU585b 관측 — 외부 HTTP 차단');
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

final String _wj = String.fromCharCode(0x2060);
final String _zw = String.fromCharCode(0x200B);

bool _gap(String ch) => ch == ' ' || ch == '\n' || ch == '\t' || ch == _zw;

/// 그려진 글(표시 제어 문자 포함) 기준 — 낱말(공백 · 개행 · ZWSP 사이) 안에서 줄이 바뀐 횟수. NBSP · WORD JOINER 로 묶은 덩어리는 한 낱말이다.
int _midBreaks(RenderParagraph rp) {
  final s = rp.text.toPlainText(includeSemanticsLabels: false);
  var n = 0;
  double? lastTop;
  var lastIdx = -1;
  for (var i = 0; i < s.length; i++) {
    final ch = s[i];
    if (ch == '\n') {
      lastTop = null;
      lastIdx = i;
      continue;
    }
    if (ch == _wj || ch == _zw) continue;
    final bx = rp.getBoxesForSelection(TextSelection(baseOffset: i, extentOffset: i + 1));
    if (bx.isEmpty) continue;
    final top = bx.first.top;
    final half = (bx.first.bottom - bx.first.top) / 2;
    final wrapped = lastTop != null && top > lastTop + half;
    if (wrapped) {
      var gap = _gap(ch) || (lastIdx >= 0 && _gap(s[lastIdx]));
      for (var k = lastIdx + 1; k < i; k++) {
        if (_gap(s[k])) gap = true;
      }
      if (!gap) n++;
    }
    if (lastTop == null || wrapped) lastTop = top;
    lastIdx = i;
  }
  return n;
}

/// 글 전문이 그려졌는가 — 마지막 글자까지 자리(box)가 문단 크기 안에 있다(말줄임으로 잘린 글자는 자리가 없다).
bool _fullShown(RenderParagraph rp, Size size) {
  final s = rp.text.toPlainText(includeSemanticsLabels: false);
  for (var i = s.length - 1; i >= 0; i--) {
    final ch = s[i];
    if (ch == _wj || _gap(ch)) continue;
    // [DU560 repair 3 proposed / decision168] Vertical max selection box; horizontal tight right; tolerance unchanged.
    // This measures selection-box placement, not ink bounds or ancestor clipping.
    final sel = TextSelection(baseOffset: i, extentOffset: i + 1);
    final tight = rp.getBoxesForSelection(sel);
    final mx = rp.getBoxesForSelection(sel, boxHeightStyle: ui.BoxHeightStyle.max);
    return tight.isNotEmpty && mx.isNotEmpty && mx.first.bottom <= size.height + 0.5 && tight.first.right <= size.width + 0.5;
  }
  return false;
}

typedef _TextObs = ({bool shown, bool name, bool full, bool ell0, int brk, Size size});

/// Text 하나의 관측값(잰 즉시 값으로 굳힌다) — 그려진 글(표시 제어 문자를 뺀 것) · 읽는 이름이 각각 [want] 원문과 같은가 · 전문 · 말줄임 설정 · 낱말 안 끊김 수.
_TextObs _textObs(WidgetTester t, Finder textF, String want) {
  final rp = t.renderObject<RenderParagraph>(find.descendant(of: textF, matching: find.byType(RichText), skipOffstage: true).first);
  final size = rp.size;
  final shown = TextLayout.plain(rp.text.toPlainText(includeSemanticsLabels: false));
  final name = rp.text.toPlainText();
  return (shown: shown == want, name: name == want, full: _fullShown(rp, size), ell0: rp.overflow != TextOverflow.ellipsis, brk: _midBreaks(rp), size: size);
}

/// [f] 가 실제로 보일 수 있는 칸 — 화면 ∩ 조상 스크롤 칸 전부.
Rect _area(Finder f, Rect screen) {
  var a = screen;
  for (final e in find.ancestor(of: f, matching: find.byType(Scrollable)).evaluate()) {
    final ro = e.renderObject;
    if (ro is RenderBox && ro.hasSize) a = a.intersect(ro.localToGlobal(Offset.zero) & ro.size);
  }
  return a;
}

/// 그려진 문단의 줄 수 — 글자 자리(box)의 서로 다른 top 개수.
int _lineCount(RenderParagraph rp) {
  final n = rp.text.toPlainText(includeSemanticsLabels: false).length;
  final tops = <int>{};
  for (final b in rp.getBoxesForSelection(TextSelection(baseOffset: 0, extentOffset: n))) {
    tops.add(b.top.round());
  }
  return tops.length;
}

typedef _V = ({String id, double w, double h, double s});
const _views = <_V>[(id: 'W', w: 390.0, h: 844.0, s: 1.0), (id: 'B', w: 320.0, h: 640.0, s: 2.0), (id: 'N', w: 320.0, h: 640.0, s: 1.0)];
const _cases = <({String id, int shots})>[(id: 'NORM', shots: 3), (id: 'LONG', shots: 3)];

/// [DU585b] 처리할 일 설명 글자 역할(판정148 :54 '글자 축소 · 기준완화로 해결하지 않는다') — 판단 본문 16/1.5/400 textPrimary(DU555 · 두 모드 같아야 한다).
const _sigDesc = '16.0/1.50/400/0.0/ff21242d';

/// [DU585b] 부분 실패 고지(LONG · 오늘 · 다가오는 두 곳) — `_partialStaffingNotice` 문구 그대로.
const _partialMsg = '사업장 1곳의 정보를 불러오지 못해 나머지 사업장 기준으로 표시했어요';

typedef _Task = ({String sub, String title, String desc, List<String> subs, String pill});
typedef _Next = ({String sub, String date, String detail, String? need});

/// [DU585b] 처리할 일 행(화면 순서 · `_makeActionRows` 의 제목 · 설명 · 보조줄 · 알약 그대로) — 받는 자리 = 의미 이름 `제목, 설명[, 보조줄], 열기` 인 Semantics 하나.
List<_Task> _tasksOf(String id) => id == 'NORM'
    ? const [
        (sub: 'kr1', title: '퇴사 요청', desc: '퇴사 요청을 검토해 주세요', subs: ['수동 검토 1건', '빠른 검토 필요 1건'], pill: '1건'),
        (sub: 'kr2', title: '지원 검토', desc: '대기 중인 지원을 확인해 주세요', subs: ['긴급 1건'], pill: '3건'),
        (sub: 'kr3', title: '일정 변경 요청', desc: '근로자의 일정 변경 요청이 있어요', subs: <String>[], pill: '2건'),
        (sub: 'kr4', title: '계약 미발송', desc: '발송이 필요한 계약이 있어요', subs: <String>[], pill: '1건'),
        (sub: 'kr5', title: '마감 필요', desc: '사업장별 미마감 근무일 합계', subs: ['가장 오래된 날 2026.11.03'], pill: '4일'),
      ]
    : const [
        (sub: 'kr1', title: '이체 대기', desc: '이체 확인이 필요한 급여가 있어요', subs: ['연체 1건', '지급일 확인 필요 1건'], pill: '3건'),
        (sub: 'kr2', title: '중간정산 요청', desc: '대기 중인 중간정산 요청이 있어요', subs: <String>[], pill: '1건'),
        (sub: 'kr3', title: '급여 변경 요청', desc: '지급방식 변경 요청을 확인해 주세요', subs: <String>[], pill: '1건'),
        (sub: 'kr4', title: '계약 확인 필요', desc: '연장·종료를 정할 계약을 확인해 주세요', subs: ['만료 후 미결정 1건'], pill: '3건'),
      ];

/// [DU585b] 다가오는 근무 행(부족 먼저 · 날짜순 — `_buildFutureStaffing` 정렬 그대로) — 찾는 글 = 상태 줄(사례 안에서 하나뿐인 문구).
List<_Next> _nextOf(String id) => id == 'NORM'
    ? [
        (sub: 'nr1', date: _fut(1), detail: '3명 중 2명 확정 · 지원 대기 2건', need: '1명 추가 필요'),
        (sub: 'nr2', date: _fut(3), detail: '2명 전원 확정', need: null),
      ]
    : [(sub: 'nr1', date: _fut(2), detail: '4명 중 1명 확정 · 강남 물류센터 외 1곳 · 지원 대기 1건', need: '3명 추가 필요')];

final bool _before = Platform.environment['DU_BEFORE_OBSERVE'] == '585';
final Map<String, String> _env = Platform.environment;
final bool _optIn =
    (_env['DU1_VQ_PHASE'] == 'before' && _env['DU1_VQ_RUN'] == 'du585bbl19-tb' && _env['DU_BEFORE_OBSERVE'] == '585') ||
        (_env['DU1_VQ_PHASE'] == 'after' && _env['DU1_VQ_RUN'] == 'du585bbl19-ta' && _env['DU_BEFORE_OBSERVE'] == null);
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
    _out('R585 setup init cf=$nCf unexpected=$nUnexp http=$nHttp auth=${wire.auth.length} un64=${_enc(wire.unexpected.join('|'))}');
    final initOk = nCf == 0 && nUnexp == 0 && nHttp == 0;
    if (!initOk) _halt = 'setUpAll 초기화 안전 대역';
    expect(initOk, isTrue, reason: 'setUpAll 초기화 중 CF 0 · 예상 밖 채널 0 · HTTP 0 — [${wire.unexpected.join(' | ')}]');
  });

  for (final v in _views) {
    for (final c in _cases) {
      testWidgets('S585BR-${v.id}-${c.id} 관리자 홈 행 배치(판정148 F148-B-TASK-READING · N-UPCOMING-REFLOW) — 낱말 쌓임 · 전문 · 받는 자리 · 넘침', (t) async {
        final tok = 'S585BR-${v.id}-${c.id}';
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
        _out('D585 $tok begin mode=$mode phase=${Platform.environment['DU1_VQ_PHASE'] ?? '(unset)'} env=$_envLine manifest=$_manifest');
        final seen = _Seen();
        void need(String k, bool ok, [String why = '']) => expect(ok, isTrue, reason: '$tok $k $why');
        void safe(String step) => need('안전 대역($step) — 예상 밖 채널 · CF · HTTP 0', !wire.tripped && net.tries.isEmpty,
            'cf ${wire.cf.length} 예상 밖 [${wire.unexpected.join(' | ')}] http ${net.tries.length}');
        final checks = <(String, bool, String)>[];
        void chk(String k, bool ok, [String why = '']) => checks.add((k, ok, why));

        final fx = _fixture(c.id);
        final owner = _Owner(bizIds: fx.bizIds);
        final homeCalls = <String, int>{};
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
            _out('D585 $tok shot $id ovf=${seen.overflows.length}');
            await vqCapture(t, key, '${tok}_$id', conditions: {
              'viewport': '${v.w.toInt()}x${v.h.toInt()}', 'textScaler': v.s, 'run': vqRun, 'manifest': _manifest, 'mode': mode,
              'fixture': c.id, 'state': state,
            });
            shots++;
          }

          // ① [DU585b] 처리할 일 행 — 행마다 안 지어졌으면 짓고(_bringBuilt · 점검표 A4) · 받는 자리(의미 이름이 정확한 Semantics 안 첫 GestureDetector =
          //   DU555 CTA 와 같은 InkWell)를 ensureVisible 로 넣고 **같은 받는 자리**의 화면 안 · 중심 hit · 48 을 잰다(A1). 행 안 글은 놓인 자리 · 줄 ·
          //   전문 · 끊김 · 같은 문단을 행 전체 본문 폭에 다시 놓은 줄(_layAt)을 잰다(스크롤과 무관한 값). 누르기 0.
          final rawRows = <String>[];
          final tasks = _tasksOf(c.id);
          for (final k in tasks) {
            final o = await _taskObs(t, home, k, screen);
            _taskOut(tok, k.sub, o);
            rawRows.add('${k.sub} ${o.pl} stk${o.stk} grow${o.grow} ${o.dl}/${o.df} ${o.rcv}');
            chk('할 일 행 하나 ${k.sub}', o.n == 1, k.title);
            chk('알약 · 꺾쇠 받는 자리 안 · 말줄임 0 · 설명 역할 그대로 ${k.sub}', o.pin && o.ell0 && o.dsig == _sigDesc,
                '${k.title} pin ${o.pin} ell0 ${o.ell0} dsig ${o.dsig}');
            if (!_before) {
              chk('strict 알약 · 꺾쇠 때문에 생긴 낱말 쌓임 0 ${k.sub}', o.stk == 0, '${k.title} stk ${o.stk} pl ${o.pl} ${o.dl}/${o.df}');
              chk('strict 전문 · 음절 끊김 0 ${k.sub}', o.full && o.brk == 0, '${k.title} full ${o.full} brk ${o.brk}');
              chk('strict 받는 자리 화면 안 · 중심 hit · 48 ${k.sub}', o.vis && o.hit && o.m48, '${k.title} ${o.rcv} ${o.vis}/${o.hit}/${o.m48}');
            }
          }
          Future<void> head(String title) async {
            await _bringBuilt(t, home, title);
            final f = _txt(home, title, onstage: false);
            need('섹션 머리 하나 $title', f.evaluate().length == 1, '개수 ${f.evaluate().length}');
            await t.ensureVisible(f);
            for (var m = 0; m < 4; m++) {
              await t.pump(const Duration(milliseconds: 50));
            }
          }
          await head('처리할 일');
          _fillsOut(tok, 1, _fills(t));
          await shot('1task', 'tasks-head');
          // 끝 행 받는 자리를 화면 위로(처리할 일 카드 끝 화면).
          await _bringBuilt(t, home, tasks.last.title);
          final lastSem = _taskSem(tasks.last);
          need('끝 행 받는 자리 하나', lastSem.evaluate().length == 1, tasks.last.title);
          await t.ensureVisible(find.descendant(of: lastSem, matching: find.byType(GestureDetector), skipOffstage: false).first);
          for (var m = 0; m < 4; m++) {
            await t.pump(const Duration(milliseconds: 50));
          }
          _fillsOut(tok, 2, _fills(t));
          await shot('2task', 'tasks-end');

          // ② [DU585b] 다가오는 근무 행 — 바꾸지 않은 소비처(pairWords 끔). 판정148 :56 비교 항목(배치 · 줄 · 전 폭 줄 · 받는 자리)을 두 모드 기록 · strict 는 불변식만.
          for (final k in _nextOf(c.id)) {
            final o = await _nextObs(t, home, k, screen);
            _nextOut(tok, k.sub, o);
            rawRows.add('${k.sub} ${o.pl} stk${o.stk} grow${o.grow} ${o.dl}/${o.df} ${o.rcv}');
            chk('다가오는 행 하나 ${k.sub}', o.n == 1, k.detail);
            chk('부족 글 · 꺾쇠 받는 자리 안 · 말줄임 0 ${k.sub}', o.pin && o.ell0, '${k.detail} pin ${o.pin} ell0 ${o.ell0}');
            if (!_before) {
              chk('strict 다가오는 행 전문 · 음절 끊김 0 ${k.sub}', o.full && o.brk == 0, '${k.detail} full ${o.full} brk ${o.brk}');
              chk('strict 다가오는 행 받는 자리 화면 안 · 중심 hit · 48 ${k.sub}', o.vis && o.hit && o.m48, '${k.detail} ${o.rcv} ${o.vis}/${o.hit}/${o.m48}');
            }
          }

          // ③ [DU585b] 다시 시도(LONG 부분 실패 두 곳 · 같은 행 판정기의 바꾸지 않은 소비처) — 판정148 :56 'retry 도달'.
          if (c.id == 'LONG') {
            for (var i = 0; i < 2; i++) {
              final o = await _rtObs(t, home, i, screen);
              _rtOut(tok, i + 1, o);
              rawRows.add('rt${i + 1} ${o.pl} stk${o.stk} ${o.ml}/${o.mf} ${o.rcv}');
              chk('다시 시도 둘 이상 rt${i + 1}', o.n >= 2, 'n ${o.n}');
              if (!_before) {
                chk('strict 다시 시도 화면 안 · 중심 hit · 48 rt${i + 1}', o.vis && o.hit && o.m48, '${o.rcv} ${o.vis}/${o.hit}/${o.m48}');
              }
            }
          }
          await head('다가오는 근무');
          _fillsOut(tok, 3, _fills(t));
          await shot('3next', 'upcoming-head');
          raw = 'rows ${rawRows.join(' | ')}';
          safe('측정 · 캡처');
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
        _out('D585 $tok att wire cf=$nCf unexpected=$nUnexp http=$nHttp summary=${homeCalls['summary'] ?? 0} staffing=${homeCalls['staffing'] ?? 0} roster=${homeCalls['roster'] ?? 0} attendance=${homeCalls['attendance'] ?? 0}');

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
        _out('R585 $tok raw m64=${_enc(raw)} ovf64=${_enc(ovfRaw)} fw64=${_enc(fwRaw)} un64=${_enc(unText)} cleanup64=${_enc(cleanupErr)} '
            'fail64=${_enc(failure?.toString() ?? '')}');
        _out('D585 $tok att fw n=$nFw');
        _out('D585 $tok done state=${c.id} mode=$mode captures=$shots overflows=$nOvf exc=${exc != null}');

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

// 측정 도우미(DU578 과 같이 main 뒤).

/// 그려진 글(묶음 문자를 뺀 것) · 위젯 글이 [want] 인 Text(Text.rich 포함) — DU523 의 찾기 술어와 같다.
///   [onstage] true = 화면에 그려지는 것만(머리 — O003 은 좁은 창 판정용 머리 사본을 Offstage 로 한 번 더 짓는다 · work_applicants_dialog:2038).
///   false = 지어진 것 전부(본문 — O002 본문은 지연 생성 목록 CustomScrollView/SliverList · ListView.separated · day_applicants_dialog:1457/:1476 —
///   B 에서 머리가 커지면 첫 묶음이 칸 밖(캐시 안)에 지어져 onstage 개수 0 이 될 수 있다 · DU573/DU581 TB STOP 교훈).
Finder _txt(Finder scope, String want, {bool onstage = true}) => find.descendant(
    of: scope,
    matching: find.byWidgetPredicate((w) => w is Text && TextLayout.plain(w.data ?? w.textSpan?.toPlainText() ?? '') == want),
    skipOffstage: onstage);

/// [DU581 r3 _bringBuilt 와 같은 대비 · 판정167 교훈] [want] 글이 [host] 안에 아직 안 지어졌을 때만 그 host 의 세로 Scrollable 을 끌어 짓는다
///   (누르기 아님 · 찾는 식 = _txt 와 같은 정규화 · 단언 없음 — 개수 판정은 뒤 _textLine/_btnReach 출력과 cell 선언). 지어져 있으면 아무것도 하지 않는다.
Future<void> _bringBuilt(WidgetTester t, Finder host, String? want) async {
  final tf = find.descendant(
      of: host, matching: find.byWidgetPredicate((w) => w is Text && TextLayout.plain(w.data ?? w.textSpan?.toPlainText() ?? '') == want), skipOffstage: false);
  if (tf.evaluate().isNotEmpty) return;
  final sc = find.descendant(
      of: host, matching: find.byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.down), skipOffstage: false);
  await t.scrollUntilVisible(tf, 120, scrollable: sc.first, maxScrolls: 40);
  await t.pump(const Duration(milliseconds: 50));
}

bool _hitWithin(WidgetTester t, Finder f, Offset pos) {
  final own = <Object>{};
  void walk(Element e) {
    final ro = e.renderObject;
    if (ro != null) own.add(ro);
    e.visitChildren(walk);
  }

  walk(f.evaluate().first);
  return t.hitTestOnBinding(pos).path.any((x) => own.contains(x.target));
}

String _hex(Color c) => '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

/// [DU575 · 점검표 A8] 화면에 그려진(onstage) ButtonStyleButton 전부의 채움 — 단추 자신의 Material 색(투명 · 없음 = none) · 글 = 첫 RichText(Icon 글리프 제외).
///   기록만(브랜드 밖 채움은 보고서 색 조화 표 '후보'). 카드 행 단추(_inviteActionButton = GestureDetector + Container)는 여기 들지 않는다 — README A8 표.
typedef _FillObs = ({int n, int brand, int err, int none, int other, String list});

_FillObs _fills(WidgetTester t) {
  final rows = <String>[];
  var b = 0, er = 0, no = 0, ot = 0;
  for (final e in find.byWidgetPredicate((w) => w is ButtonStyleButton).evaluate()) {
    final bf = find.byElementPredicate((x) => identical(x, e));
    final mats = find.descendant(of: bf, matching: find.byType(Material), skipOffstage: false).evaluate().toList();
    final Color? fc = mats.isEmpty ? null : (mats.first.widget as Material).color;
    final texts = find
        .descendant(of: bf, matching: find.byType(RichText), skipOffstage: false)
        .evaluate()
        .where((r) => find.ancestor(of: find.byElementPredicate((x) => identical(x, r), skipOffstage: false), matching: find.byType(Icon)).evaluate().isEmpty)
        .toList();
    final lab = texts.isEmpty ? '-' : TextLayout.plain((texts.first.widget as RichText).text.toPlainText(includeSemanticsLabels: false));
    if (fc == null || fc.a == 0) {
      no++;
      rows.add('$lab:none');
    } else {
      if (fc.toARGB32() == AppColors.brand.toARGB32()) {
        b++;
      } else if (fc.toARGB32() == AppColors.errorDark.toARGB32()) {
        er++;
      } else {
        ot++;
      }
      rows.add('$lab:${_hex(fc)}');
    }
  }
  return (n: rows.length, brand: b, err: er, none: no, other: ot, list: _enc(rows.join('|')));
}

/// [DU585b] 문단 [para] 를 폭 [w] 에 다시 놓은 결과 — 줄 수 · 낱말 하나뿐인 줄 수(끝 줄 제외 · 묶음 문자를 뺀 글을 공백으로 나눈다).
///   재구성 = DU307 시험(du1_admin_home_307_test.dart:633 D307-PARA)의 TextPainter 꼴 — 같은 글 조각 · 정렬 · 방향 · 배율 · 줄 제한 · locale · strut · 폭 기준 · 높이 규칙.
({int lines, int solo}) _layAt(RenderParagraph para, double w) {
  final tp = TextPainter(
    text: para.text, textAlign: para.textAlign, textDirection: para.textDirection, textScaler: para.textScaler, maxLines: para.maxLines,
    locale: para.locale, strutStyle: para.strutStyle, textWidthBasis: para.textWidthBasis, textHeightBehavior: para.textHeightBehavior,
  )..layout(maxWidth: w);
  final plain = tp.plainText;
  final ms = tp.computeLineMetrics();
  var solo = 0;
  for (var i = 0; i + 1 < ms.length; i++) {
    final lm = ms[i];
    final b = tp.getLineBoundary(tp.getPositionForOffset(Offset(lm.left + lm.width / 2, lm.baseline - lm.ascent / 2)));
    final words = TextLayout.plain(plain.substring(b.start, b.end)).trim().split(' ').where((x) => x.isNotEmpty).length;
    if (words == 1) solo++;
  }
  final n = ms.length;
  tp.dispose();
  return (lines: n, solo: solo);
}

/// Text 하나의 문단(RichText 하나).
RenderParagraph _paraOf(WidgetTester t, Finder tf) =>
    t.renderObject<RenderParagraph>(find.descendant(of: tf, matching: find.byType(RichText), skipOffstage: false).first);

/// 받는 자리 [r] 의 크기 'WxH'.
String _wh(Rect r) => '${r.width.toStringAsFixed(1)}x${r.height.toStringAsFixed(1)}';

/// [DU585b] 본문 글 묶음 한 행의 값 — 각 글: 전문(max 판 _fullShown) · 말줄임 · 음절 끊김 · 지금 폭과 행 전체 본문 폭([fullRight] − 글 왼쪽)의 줄/낱말 쌓임 차.
///   [descText] 의 그려진 줄(_lineCount) · 전 폭 줄 · 서명을 따로 돌려준다. 글이 받는 자리 안에 정확히 하나가 아니면 full=false.
typedef _Body = ({bool ok, bool full, bool ell0, int brk, int stk, int grow, int dl, int df, String dsig, double bottom});

_Body _rowBody(WidgetTester t, Finder rf, List<String> texts, String descText, double fullRight) {
  var ok = true, full = true, ell0 = true;
  var brk = 0, stk = 0, grow = 0, dl = 0, df = 0;
  var dsig = '-';
  var bottom = 0.0;
  for (final w in texts) {
    final f = _txt(rf, w, onstage: false);
    if (f.evaluate().length != 1) {
      ok = false;
      full = false;
      continue;
    }
    final o = _textObs(t, f, w);
    final rp = _paraOf(t, f);
    final fr = t.getRect(f);
    final now = _layAt(rp, rp.constraints.maxWidth);
    final at = _layAt(rp, fullRight - fr.left);
    if (!o.full || !o.shown) full = false;
    if (!o.ell0) ell0 = false;
    brk += o.brk;
    if (now.solo > at.solo) stk += now.solo - at.solo;
    if (now.lines > at.lines) grow += now.lines - at.lines;
    if (w == descText) {
      dl = _lineCount(rp);
      df = at.lines;
      final sigs = <String>{for (final (_, st) in _spansOf(rp)) _sig(st)};
      dsig = sigs.isEmpty ? '-' : (sigs.toList()..sort()).join('|');
    }
    if (fr.bottom > bottom) bottom = fr.bottom;
  }
  return (ok: ok, full: full, ell0: ell0, brk: brk, stk: stk, grow: grow, dl: dl, df: df, dsig: dsig, bottom: bottom);
}

typedef _RowObs = ({int n, String pl, int stk, int grow, int dl, int df, String dsig, bool full, int brk, bool ell0, bool pin, bool vis, bool hit, bool m48, String rcv});

/// 행을 다 잴 수 없을 때(받는 자리 개수 ≠ 1 · 꺾쇠/알약 개수 ≠ 1) — 잰 것만 남기고 나머지는 실패 값.
_RowObs _rowMiss(int n, {bool vis = false, bool hit = false, bool m48 = false, String rcv = '-'}) =>
    (n: n, pl: '-', stk: 0, grow: 0, dl: 0, df: 0, dsig: '-', full: false, brk: 0, ell0: false, pin: false, vis: vis, hit: hit, m48: m48, rcv: rcv);

/// 처리할 일 행 [k] 의 받는 자리 — 의미 이름이 정확히 `제목, 설명[, 보조줄], 열기` 인 단추 Semantics(행 콜백 · 의미 이름 · 읽기 순서 그대로의 증거).
Finder _taskSem(_Task k) => find.byWidgetPredicate(
    (w) => w is Semantics && w.properties.button == true && w.properties.label == [k.title, k.pill, k.desc, ...k.subs, '열기'].join(', '), // [판정283 A안 갱신 2026-11-26] 설명은 총수를 되풀이하지 않고 알약 = 총수+단위 · 의미 이름 = 제목, 알약, 설명[, 보조줄], 열기 · 놓인 자리 pl 은 이제 알약(제목 묶음)이라 옛 'side/below' 뜻과 다르다(이 opt-in 하네스 재실행 시 재정의 필요)
    skipOffstage: false);

/// [DU585b] 처리할 일 행 하나 — 받는 자리를 ensureVisible 로 넣고 같은 받는 자리를 잰다(A1). 놓인 자리 pl = 알약 글 윗변이 본문 글 아랫변 아래면 below.
Future<_RowObs> _taskObs(WidgetTester t, Finder home, _Task k, Rect screen) async {
  await _bringBuilt(t, home, k.title);
  final sem = _taskSem(k);
  final n = sem.evaluate().length;
  if (n != 1) return _rowMiss(n);
  final rf = find.descendant(of: sem, matching: find.byType(GestureDetector), skipOffstage: false).first;
  await t.ensureVisible(rf);
  for (var m = 0; m < 4; m++) {
    await t.pump(const Duration(milliseconds: 50));
  }
  final r = t.getRect(rf);
  final vis = _inside(r, _area(rf, screen));
  final hit = _hitWithin(t, rf, r.center);
  final m48 = r.width >= 48 - 0.01 && r.height >= 48 - 0.01;
  final chev = find.descendant(of: rf, matching: find.byIcon(Icons.chevron_right), skipOffstage: false);
  final pillF = _txt(rf, k.pill, onstage: false);
  if (chev.evaluate().length != 1 || pillF.evaluate().length != 1) {
    return _rowMiss(n, vis: vis, hit: hit, m48: m48, rcv: _wh(r));
  }
  final cr = t.getRect(chev);
  final pr = t.getRect(pillF);
  final b = _rowBody(t, rf, [k.title, k.desc, ...k.subs], k.desc, cr.right);
  final pillFull = _textObs(t, pillF, k.pill);
  return (
    n: n, pl: pr.top >= b.bottom - 0.5 ? 'below' : 'side', stk: b.stk, grow: b.grow, dl: b.dl, df: b.df, dsig: b.dsig,
    full: b.ok && b.full && pillFull.full && pillFull.shown, brk: b.brk + pillFull.brk, ell0: b.ell0 && pillFull.ell0,
    pin: _inside(pr, r) && _inside(cr, r), vis: vis, hit: hit, m48: m48, rcv: _wh(r),
  );
}

/// [DU585b] 다가오는 근무 행 하나 — 상태 줄 글의 가장 가까운 GestureDetector(행 InkWell · DU555 CTA 대상)를 ensureVisible 로 넣고 같은 받는 자리를 잰다(A1).
///   놓인 자리 pl = 꺾쇠 윗변이 본문(날짜 · 상태 줄) 아랫변 아래면 below. 부족 글(있으면)도 전문 · 말줄임 · 끊김에 넣는다.
Future<_RowObs> _nextObs(WidgetTester t, Finder home, _Next k, Rect screen) async {
  await _bringBuilt(t, home, k.detail);
  final tf = _txt(home, k.detail, onstage: false);
  final n = tf.evaluate().length;
  if (n != 1) return _rowMiss(n);
  final rf = find.ancestor(of: tf, matching: find.byType(GestureDetector)).first;
  await t.ensureVisible(rf);
  for (var m = 0; m < 4; m++) {
    await t.pump(const Duration(milliseconds: 50));
  }
  final r = t.getRect(rf);
  final vis = _inside(r, _area(rf, screen));
  final hit = _hitWithin(t, rf, r.center);
  final m48 = r.width >= 48 - 0.01 && r.height >= 48 - 0.01;
  final chev = find.descendant(of: rf, matching: find.byIcon(Icons.chevron_right), skipOffstage: false);
  if (chev.evaluate().length != 1) {
    return _rowMiss(n, vis: vis, hit: hit, m48: m48, rcv: _wh(r));
  }
  final cr = t.getRect(chev);
  final b = _rowBody(t, rf, [k.date, k.detail], k.detail, cr.right);
  var needOk = true, needFull = true, needEll0 = true, needBrk = 0;
  final needText = k.need;
  if (needText != null) {
    final nf = _txt(rf, needText, onstage: false);
    if (nf.evaluate().length != 1) {
      needOk = false;
    } else {
      final o = _textObs(t, nf, needText);
      needFull = o.full && o.shown;
      needEll0 = o.ell0;
      needBrk = o.brk;
      needOk = _inside(t.getRect(nf), r);
    }
  }
  return (
    n: n, pl: cr.top >= b.bottom - 0.5 ? 'below' : 'side', stk: b.stk, grow: b.grow, dl: b.dl, df: b.df, dsig: b.dsig,
    full: b.ok && b.full && needFull, brk: b.brk + needBrk, ell0: b.ell0 && needEll0, pin: needOk && _inside(cr, r), vis: vis, hit: hit, m48: m48, rcv: _wh(r),
  );
}

typedef _RtObs = ({int n, String pl, int stk, int ml, int mf, bool vis, bool hit, bool m48, String rcv});

/// [DU585b] [i] 번째 `다시 시도`(LONG 부분 실패 — 오늘 · 다가오는 순) — 그 글의 가장 가까운 GestureDetector(DU555 CTA 대상)를 ensureVisible 로 넣고 같은 받는 자리를 잰다(A1).
///   같은 번째 고지 문장의 지금 줄(_lineCount) · 행 전체 본문 폭 줄 · 낱말 쌓임 차 · 놓인 자리(다시 시도 윗변이 문장 아랫변 아래면 below).
Future<_RtObs> _rtObs(WidgetTester t, Finder home, int i, Rect screen) async {
  await _bringBuilt(t, home, '다시 시도');
  await _bringBuilt(t, home, _partialMsg);
  final all = _txt(home, '다시 시도', onstage: false);
  final msgs = _txt(home, _partialMsg, onstage: false);
  final n = all.evaluate().length;
  if (n <= i || msgs.evaluate().length <= i) {
    return (n: n, pl: '-', stk: 0, ml: 0, mf: 0, vis: false, hit: false, m48: false, rcv: '-');
  }
  final rf = find.ancestor(of: all.at(i), matching: find.byType(GestureDetector)).first;
  await t.ensureVisible(rf);
  for (var m = 0; m < 4; m++) {
    await t.pump(const Duration(milliseconds: 50));
  }
  final r = t.getRect(rf);
  final mf = msgs.at(i);
  final rp = _paraOf(t, mf);
  final mr = t.getRect(mf);
  final now = _layAt(rp, rp.constraints.maxWidth);
  final at = _layAt(rp, r.right - mr.left);
  return (
    n: n, pl: r.top >= mr.bottom - 0.5 ? 'below' : 'side', stk: now.solo > at.solo ? now.solo - at.solo : 0, ml: _lineCount(rp), mf: at.lines,
    vis: _inside(r, _area(rf, screen)), hit: _hitWithin(t, rf, r.center), m48: r.width >= 48 - 0.01 && r.height >= 48 - 0.01, rcv: _wh(r),
  );
}

/// [DU585b] 처리할 일 행 출력 한 줄 — sub 마다 리터럴 줄(preflight 2-5 가 'att <sub>' 키를 정적 대조 · lgate 가 같은 줄을 판정). 키 순서 = prep/lines_du585b.py TASK_KEYS.
void _taskOut(String tok, String sub, _RowObs o) {
  switch (sub) {
    case 'kr1':
      _out('D585 $tok att kr1 n=${o.n} pl=${o.pl} stk=${o.stk} grow=${o.grow} dl=${o.dl} df=${o.df} dsig=${o.dsig} full=${o.full} brk=${o.brk} ell0=${o.ell0} pin=${o.pin} vis=${o.vis} hit=${o.hit} m48=${o.m48} rcv=${o.rcv}');
    case 'kr2':
      _out('D585 $tok att kr2 n=${o.n} pl=${o.pl} stk=${o.stk} grow=${o.grow} dl=${o.dl} df=${o.df} dsig=${o.dsig} full=${o.full} brk=${o.brk} ell0=${o.ell0} pin=${o.pin} vis=${o.vis} hit=${o.hit} m48=${o.m48} rcv=${o.rcv}');
    case 'kr3':
      _out('D585 $tok att kr3 n=${o.n} pl=${o.pl} stk=${o.stk} grow=${o.grow} dl=${o.dl} df=${o.df} dsig=${o.dsig} full=${o.full} brk=${o.brk} ell0=${o.ell0} pin=${o.pin} vis=${o.vis} hit=${o.hit} m48=${o.m48} rcv=${o.rcv}');
    case 'kr4':
      _out('D585 $tok att kr4 n=${o.n} pl=${o.pl} stk=${o.stk} grow=${o.grow} dl=${o.dl} df=${o.df} dsig=${o.dsig} full=${o.full} brk=${o.brk} ell0=${o.ell0} pin=${o.pin} vis=${o.vis} hit=${o.hit} m48=${o.m48} rcv=${o.rcv}');
    case 'kr5':
      _out('D585 $tok att kr5 n=${o.n} pl=${o.pl} stk=${o.stk} grow=${o.grow} dl=${o.dl} df=${o.df} dsig=${o.dsig} full=${o.full} brk=${o.brk} ell0=${o.ell0} pin=${o.pin} vis=${o.vis} hit=${o.hit} m48=${o.m48} rcv=${o.rcv}');
    default:
      throw StateError('DU585b 할 일 sub 선언 밖 $sub');
  }
}

/// [DU585b] 다가오는 근무 행 출력 한 줄 — 키 순서 = NEXT_KEYS.
void _nextOut(String tok, String sub, _RowObs o) {
  switch (sub) {
    case 'nr1':
      _out('D585 $tok att nr1 n=${o.n} pl=${o.pl} stk=${o.stk} grow=${o.grow} dl=${o.dl} df=${o.df} full=${o.full} brk=${o.brk} ell0=${o.ell0} pin=${o.pin} vis=${o.vis} hit=${o.hit} m48=${o.m48} rcv=${o.rcv}');
    case 'nr2':
      _out('D585 $tok att nr2 n=${o.n} pl=${o.pl} stk=${o.stk} grow=${o.grow} dl=${o.dl} df=${o.df} full=${o.full} brk=${o.brk} ell0=${o.ell0} pin=${o.pin} vis=${o.vis} hit=${o.hit} m48=${o.m48} rcv=${o.rcv}');
    default:
      throw StateError('DU585b 다가오는 sub 선언 밖 $sub');
  }
}

/// [DU585b] 다시 시도 출력 한 줄 — 키 순서 = RT_KEYS.
void _rtOut(String tok, int i, _RtObs o) {
  switch (i) {
    case 1:
      _out('D585 $tok att rt1 n=${o.n} pl=${o.pl} stk=${o.stk} ml=${o.ml} mf=${o.mf} vis=${o.vis} hit=${o.hit} m48=${o.m48} rcv=${o.rcv}');
    case 2:
      _out('D585 $tok att rt2 n=${o.n} pl=${o.pl} stk=${o.stk} ml=${o.ml} mf=${o.mf} vis=${o.vis} hit=${o.hit} m48=${o.m48} rcv=${o.rcv}');
    default:
      throw StateError('DU585b 다시 시도 번호 선언 밖 $i');
  }
}

/// [DU585b · 점검표 A8] 캡처 직전 화면 채움 단추 기록 한 줄 — 캡처 번호마다 리터럴 줄(키 순서 = FILL_KEYS).
void _fillsOut(String tok, int i, _FillObs fl) {
  switch (i) {
    case 1:
      _out('D585 $tok att fills1 n=${fl.n} brand=${fl.brand} err=${fl.err} none=${fl.none} other=${fl.other} list=${fl.list}');
    case 2:
      _out('D585 $tok att fills2 n=${fl.n} brand=${fl.brand} err=${fl.err} none=${fl.none} other=${fl.other} list=${fl.list}');
    case 3:
      _out('D585 $tok att fills3 n=${fl.n} brand=${fl.brand} err=${fl.err} none=${fl.none} other=${fl.other} list=${fl.list}');
    default:
      throw StateError('DU585b 채움 기록 번호 선언 밖 $i');
  }
}
