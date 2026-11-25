// ignore_for_file: depend_on_referenced_packages
// [DU586b · 장부 BL-18(068 T1-c · 069 T1-d · 070 T1-b) · 판정147 §6 ④(:72) · 판정148 :58 · 판정170 :64] DU-S010 관리자 홈 글자 역할 —
//   T1-b 준비 카드(제목 · 할 일 이름 · 목적 · 힌트) · T1-c 상태 배너(제목 · 설명 · 단추) · T1-d 머리 이름. 역할값 = 타이포 결정 §5(:62–75) · 명암 :78.
//   before = 지금 A(business_admin_home_screen 905fed42 = DU585b 후보) 기록 · strict = 후보(prep/mk_cand.py).
//   하네스 = 블록 재사용(prep/mk_test.py 가 원본 바이트 대조 · 정규화 목록 그대로):
//     DU585b 시험(bfb41ef0 · 지금 A 홈 905fed42 위 정규 DONE 5/5 23:06) — 가짜 Firebase · _Owner · 고정 시각 · 대역 꼴 · AdminHomeReads 주입 · 채널/HTTP 관찰 ·
//       글꼴 · 넘침 수집 · _spansOf/_sig · max 판 _fullShown · _textObs · _area · _lineCount · 보기 W/B/N · opt-in · setUpAll · 사례 진입/정리/집계 뼈대 ·
//       _txt · _bringBuilt · _hitWithin · _hex · _fills · _wh.
//     DU578 시험(d66803ec · DONE 5/5 21:30) — _semOf · _textLine(ensureVisible 대상 = 잰 Text) · _lum/_contrast · _bgOf · _RoleObs/_roleOf.
//   새로 쓴 것: 이 머리 · 사례 3(NOBIZ 사업장 없음 · PEND 승인 대기 · STOP 운영 중지) · 칸 표(_groupsOf) · 범위 찾기(_scopeOf · _cardOf) ·
//     단추 받는 자리(_btnObs) · 출력 줄(sub 마다 리터럴).
//   누르는 것 0 · 입력 0 · 끌기 0(ensureVisible · 안 지어졌을 때만 scrollUntilVisible) · 업무 writer 0. 기본 skip — TB before/du586bbl18-tb/DU_BEFORE_OBSERVE=586 · TA after/du586bbl18-ta/없음.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
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
const _bizName = '강남 물류센터';

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

BusinessModel _business(String id, String name) => BusinessModel(
    id: id, name: name, ownerId: 'admin1', businessNumber: '000-00-00000', address: '서울시 어딘가',
    category: '물류', subCategory: '창고', isApproved: true, createdAt: DateTime(2026, 1, 1));

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

/// [DU586b] 상태별 대역 — 각 사례가 새로 만든다(공유 상태 0). 이 셀 표면(T1-b/c)이 실제로 그려지는 세 상태(DU578 README §0-2(3) '렌더 0' 보완).
///   NOBIZ = 소유자 · 사업장 0 → STATE A 배너(사업장 등록 · 단추) + 준비 카드(사업장 지금 가능 · 업무/계약서 선행 필요 힌트 · 목적 설명 · 인감 완료).
///   PEND  = 소유자 · 사업장 1 미승인 → STATE B 배너(_stateBannerCard) + 준비 카드(사업장 '승인 진행 중' · 업무 '사업장 승인 후 반영돼요' 힌트 · 계약서/인감 완료).
///   STOP  = 소유자 · 사업장 1 운영 중지(deactivatedAt · archivedAt 없음) → STATE D 배너(긴 안내) · 준비 카드 없음(_allBusinessesClosed).
///   인감 = _Owner.sealBase64('seal') · 템플릿 = _homeReads 의 [_Template()] · 시각 = _clock(대역 모두 시각 무관).
_Fx _fixture(String id) {
  final biz = _business(_biz1, _bizName);
  return (
    bizIds: id == 'NOBIZ' ? const <String>[] : const [_biz1],
    businesses: id == 'NOBIZ'
        ? <BusinessModel>[]
        : [id == 'PEND' ? biz.copyWith(isApproved: false) : biz.copyWith(isApproved: false, deactivatedAt: DateTime(2026, 11, 1))],
    staffing: _staffing(const <Map<String, dynamic>>[]),
    summary: _summary(),
    roster: const <ApplicationModel>[],
  );
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
const _authFake = 'du586b.fake.auth.';

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
    throw const SocketException('DU586b 관측 — 외부 HTTP 차단');
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
const _cases = <({String id, int shots})>[(id: 'NOBIZ', shots: 3), (id: 'PEND', shots: 3), (id: 'STOP', shots: 2)];

/// [DU586b] 결정값(시험 _sig 꼴 '크기/줄 높이/굵기/자간/ARGB') — 역할표 §5 · AppTextStyles 역할 메서드 값. 색: textPrimary ff21242d · textSecondary ff60646f · grey400 ffbdbdbd.
const _sigCard = '17.0/1.30/700/0.0/ff21242d'; // 카드 · 목록 제목(배너 제목 · 준비 카드 제목 · 지금 가능 할 일 이름 · 머리 이름)
const _sigCardDone = '17.0/1.30/700/0.0/ff60646f'; // 같은 역할 · 완료 할 일 이름(상태색 그대로)
const _sigCardOff = '17.0/1.30/700/0.0/ffbdbdbd'; // 같은 역할 · 선행 필요 할 일 이름(상태색 그대로 — 색 표 후보)
const _sigBody = '16.0/1.50/400/0.0/ff21242d'; // 본문 · 판단(배너 설명 — 제한 원인 · 다음 단계)
const _sigHint = '16.0/1.50/400/0.0/ffbdbdbd'; // 본문 역할 · 힌트(색 grey400 그대로 — 색 표 후보)
const _sigSupport = '14.0/1.45/400/0.0/ff60646f'; // 보조 · 도움말(목적 설명)
const _sigBtn = '16.0/1.30/700/0.0/ffffffff'; // 조작(배너 단추 — 글자색 = 단추 foregroundColor 흰색)

const _subA = '사업장을 등록하면 공고·계약·급여 관리를 시작할 수 있어요';
const _subB = '운영팀이 사업장을 검토하고 있어요. 승인되면 이용할 수 있어요';
const _guide = '새 공고와 모집은 할 수 없어요. 지난 근무의 급여·정산은 급여 탭에서, 계약은 관리 탭의 계약 관리에서 계속 처리할 수 있어요';
const _purpose = '한 번 만들면 이후 계약에도 계속 사용할 수 있어요';

/// 배너 설명(배너 범위의 닻) · 준비 카드 제목(카드 범위의 닻) — 사례마다.
String _bannerSub(String id) => id == 'NOBIZ' ? _subA : (id == 'PEND' ? _subB : _guide);
String _setupTitle(String id) => id == 'NOBIZ' ? '공고 등록까지 3단계 남았어요' : '공고 등록까지 2단계 남았어요';

/// [kind] text · label(할 일 이름 + 그 행 받는 자리 크기) · hint(같은 행 할 일 이름 [tile] 에 대한 자리) ·
/// [scope] home · banner(배너 설명을 품은 Column) · button(배너 ElevatedButton) · card(준비 카드 Column) · tile(할 일 [tile] 의 InkWell) · [grey] = 대비 4.5 를 strict 로 요구하지 않음(grey400 그대로 — 후보).
typedef _Tg = ({String sub, String kind, String want, String sig, String scope, String tile, bool grey});
typedef _Grp = ({String shot, String state, bool btn, List<_Tg> tgs});

/// [DU586b] 사례별 칸 묶음 — 묶음 안은 화면 **아래 → 위** 순서로 잰다(ensureVisible 은 대상을 화면 맨 위로 → 마지막 대상 = 묶음 맨 위 글 ·
///   그 아래 글이 같은 캡처에 남는다 · DU578 꼴). [btn] = 묶음 첫머리에 배너 단추 받는 자리(bk)를 잰다. 묶음 끝에 화면 채움 단추(A8) → 캡처.
List<_Grp> _groupsOf(String id) => switch (id) {
      'NOBIZ' => const [
          (shot: '1head', state: 'header-bannerA', btn: true, tgs: [
            (sub: 'bb', kind: 'text', want: '사업장 등록', sig: _sigBtn, scope: 'button', tile: '', grey: false),
            (sub: 'bs', kind: 'text', want: _subA, sig: _sigBody, scope: 'home', tile: '', grey: false),
            (sub: 'bt', kind: 'text', want: '사업장 등록', sig: _sigCard, scope: 'banner', tile: '', grey: false),
            (sub: 'hn', kind: 'text', want: '김관리님', sig: _sigCard, scope: 'home', tile: '', grey: false),
          ]),
          (shot: '2setup', state: 'setup-top', btn: false, tgs: [
            (sub: 'h2', kind: 'hint', want: '사업장 등록 후 가능', sig: _sigHint, scope: 'tile', tile: '업무 등록', grey: true),
            (sub: 'l2', kind: 'label', want: '업무 등록', sig: _sigCardOff, scope: 'card', tile: '', grey: true),
            (sub: 'l1', kind: 'label', want: '사업장 등록', sig: _sigCard, scope: 'card', tile: '', grey: false),
            (sub: 'st', kind: 'text', want: '공고 등록까지 3단계 남았어요', sig: _sigCard, scope: 'home', tile: '', grey: false),
          ]),
          (shot: '3setup', state: 'setup-end', btn: false, tgs: [
            (sub: 'l4', kind: 'label', want: '인감/서명', sig: _sigCardDone, scope: 'card', tile: '', grey: false),
            (sub: 'h3', kind: 'hint', want: '사업장 등록 후 가능', sig: _sigHint, scope: 'tile', tile: '계약서 템플릿', grey: true),
            (sub: 'pp', kind: 'text', want: _purpose, sig: _sigSupport, scope: 'card', tile: '', grey: false),
            (sub: 'l3', kind: 'label', want: '계약서 템플릿', sig: _sigCardOff, scope: 'card', tile: '', grey: true),
          ]),
        ],
      'PEND' => const [
          (shot: '1head', state: 'header-bannerB', btn: false, tgs: [
            (sub: 'bs', kind: 'text', want: _subB, sig: _sigBody, scope: 'home', tile: '', grey: false),
            (sub: 'bt', kind: 'text', want: '사업장 승인 대기', sig: _sigCard, scope: 'banner', tile: '', grey: false),
            (sub: 'hn', kind: 'text', want: '김관리님', sig: _sigCard, scope: 'home', tile: '', grey: false),
          ]),
          (shot: '2setup', state: 'setup-top', btn: false, tgs: [
            (sub: 'h2', kind: 'hint', want: '사업장 승인 후 반영돼요', sig: _sigHint, scope: 'tile', tile: '업무 등록', grey: true),
            (sub: 'l2', kind: 'label', want: '업무 등록', sig: _sigCard, scope: 'card', tile: '', grey: false),
            (sub: 'h1', kind: 'hint', want: '승인 진행 중', sig: _sigHint, scope: 'tile', tile: '사업장 등록', grey: true),
            (sub: 'l1', kind: 'label', want: '사업장 등록', sig: _sigCard, scope: 'card', tile: '', grey: false),
            (sub: 'st', kind: 'text', want: '공고 등록까지 2단계 남았어요', sig: _sigCard, scope: 'home', tile: '', grey: false),
          ]),
          (shot: '3setup', state: 'setup-end', btn: false, tgs: [
            (sub: 'l4', kind: 'label', want: '인감/서명', sig: _sigCardDone, scope: 'card', tile: '', grey: false),
            (sub: 'l3', kind: 'label', want: '계약서 템플릿', sig: _sigCardDone, scope: 'card', tile: '', grey: false),
          ]),
        ],
      _ => const [
          (shot: '1head', state: 'header-bannerD', btn: false, tgs: [
            (sub: 'bt', kind: 'text', want: '운영이 중지된 사업장이에요', sig: _sigCard, scope: 'banner', tile: '', grey: false),
            (sub: 'hn', kind: 'text', want: '김관리님', sig: _sigCard, scope: 'home', tile: '', grey: false),
          ]),
          (shot: '2bend', state: 'bannerD-end', btn: false, tgs: [
            (sub: 'bs', kind: 'text', want: _guide, sig: _sigBody, scope: 'home', tile: '', grey: false),
          ]),
        ],
    };

final bool _before = Platform.environment['DU_BEFORE_OBSERVE'] == '586';
final Map<String, String> _env = Platform.environment;
final bool _optIn =
    (_env['DU1_VQ_PHASE'] == 'before' && _env['DU1_VQ_RUN'] == 'du586bbl18-tb' && _env['DU_BEFORE_OBSERVE'] == '586') ||
        (_env['DU1_VQ_PHASE'] == 'after' && _env['DU1_VQ_RUN'] == 'du586bbl18-ta' && _env['DU_BEFORE_OBSERVE'] == null);
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
    _out('R586 setup init cf=$nCf unexpected=$nUnexp http=$nHttp auth=${wire.auth.length} un64=${_enc(wire.unexpected.join('|'))}');
    final initOk = nCf == 0 && nUnexp == 0 && nHttp == 0;
    if (!initOk) _halt = 'setUpAll 초기화 안전 대역';
    expect(initOk, isTrue, reason: 'setUpAll 초기화 중 CF 0 · 예상 밖 채널 0 · HTTP 0 — [${wire.unexpected.join(' | ')}]');
  });

  for (final v in _views) {
    for (final c in _cases) {
      testWidgets('S586BT-${v.id}-${c.id} 관리자 홈 T1-b/c/d 글자 역할(장부 BL-18) — 역할 서명 · 대비 · 전문 · 음절 끊김 · 힌트 자리 · 넘침', (t) async {
        final tok = 'S586BT-${v.id}-${c.id}';
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
        _out('D586 $tok begin mode=$mode phase=${Platform.environment['DU1_VQ_PHASE'] ?? '(unset)'} env=$_envLine manifest=$_manifest');
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
            _out('D586 $tok shot $id ovf=${seen.overflows.length}');
            await vqCapture(t, key, '${tok}_$id', conditions: {
              'viewport': '${v.w.toInt()}x${v.h.toInt()}', 'textScaler': v.s, 'run': vqRun, 'manifest': _manifest, 'mode': mode,
              'fixture': c.id, 'state': state,
            });
            shots++;
          }

          // ① [DU586b] 칸 묶음마다(아래 → 위) — 찾기 전 안 지어졌으면 짓고(_bringBuilt · 점검표 A4 · 대상 글과 범위 닻 둘 다) · 범위 안 같은 Text 를
          //   ensureVisible 로 넣고 잰다(_textLine · A1) · 그 Text 의 실제 글 조각 서명 · 글자색 · 바탕 · 대비(_roleOf · DU578).
          //   할 일 이름(label)은 그 행 받는 자리(InkWell) 크기 기록 · 힌트(hint)는 같은 행 할 일 이름 아랫변 대비 자리(pl) · 단추(bk)는 받는 자리를
          //   ensureVisible 로 넣고 같은 받는 자리를 잰다(A1). 묶음 끝 화면 채움 단추(A8) → 캡처. 누르기 0.
          final rawRows = <String>[];
          final groups = _groupsOf(c.id);
          for (var gi = 0; gi < groups.length; gi++) {
            final g = groups[gi];
            if (g.btn) {
              await _bringBuilt(t, home, '사업장 등록');
              final b = await _btnObs(t, home, screen);
              _bkOut(tok, b);
              rawRows.add('bk n${b.n} ${b.rcv} ${b.vis}/${b.hit}/${b.m48}');
              chk('배너 단추 하나 bk', b.n == 1, 'n ${b.n}');
              if (!_before) chk('strict 배너 단추 화면 안 · 중심 hit · 48 bk', b.vis && b.hit && b.m48, '${b.rcv} ${b.vis}/${b.hit}/${b.m48}');
            }
            for (final x in g.tgs) {
              await _bringBuilt(t, home, x.want);
              for (final a in _anchorsOf(c.id, x)) {
                await _bringBuilt(t, home, a);
              }
              final tf = _scopeOf(home, c.id, x);
              final o = await _textLine(t, tf, x.want, screen);
              final r = o.n == 1 ? _roleOf(tf, x.sig) : _roleNone;
              var extra = '';
              if (x.kind == 'label') {
                final tile = find.ancestor(of: tf, matching: find.byType(InkWell));
                final rc = (o.n == 1 && tile.evaluate().isNotEmpty) ? t.getRect(tile.first) : Rect.zero;
                final m48 = rc.width >= 48 - 0.01 && rc.height >= 48 - 0.01;
                _lbOut(tok, x.sub, o, r, _wh(rc), m48);
                extra = 'rcv ${_wh(rc)} m48 $m48';
              } else if (x.kind == 'hint') {
                final lf = _txt(_cardOf(home, c.id), x.tile, onstage: false);
                final pl = (o.n == 1 && lf.evaluate().length == 1) ? (t.getRect(tf).top >= t.getRect(lf).bottom - 0.5 ? 'below' : 'side') : '-';
                _hnOut(tok, x.sub, o, r, pl);
                extra = 'pl $pl';
                if (!_before) chk('strict ${x.sub} 힌트 자리 = 할 일 이름 아래 줄(J3)', pl == 'below', '${x.want} pl $pl');
              } else {
                _tgOut(tok, x.sub, o, r);
              }
              rawRows.add('${x.sub} "${x.want}" n${o.n} ${r.sig} ${r.fg}/${r.bg} ${r.cr} $extra');
              chk('대상 글 하나 ${x.sub}', o.n == 1 && o.shown, x.want);
              if (!_before) {
                chk('strict ${x.sub} 역할 서명 = 결정값', r.role, '${x.want} ${r.sig} want ${x.sig}');
                chk('strict ${x.sub} 전문 · 음절 끊김 0 · 말줄임 0 · 보임', o.full && o.brk == 0 && o.ell0 && o.vis,
                    '${x.want} full ${o.full} brk ${o.brk} ell0 ${o.ell0} vis ${o.vis}');
                if (!x.grey) chk('strict ${x.sub} 대비 4.5 이상', r.ok45, '${x.want} ${r.fg} on ${r.bg} ${r.cr}');
              }
            }
            final fl = _fills(t);
            _fillsOut(tok, gi + 1, fl);
            await shot(g.shot, g.state);
          }
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
        _out('D586 $tok att wire cf=$nCf unexpected=$nUnexp http=$nHttp summary=${homeCalls['summary'] ?? 0} staffing=${homeCalls['staffing'] ?? 0} roster=${homeCalls['roster'] ?? 0} attendance=${homeCalls['attendance'] ?? 0}');

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
        _out('R586 $tok raw m64=${_enc(raw)} ovf64=${_enc(ovfRaw)} fw64=${_enc(fwRaw)} un64=${_enc(unText)} cleanup64=${_enc(cleanupErr)} '
            'fail64=${_enc(failure?.toString() ?? '')}');
        _out('D586 $tok att fw n=$nFw');
        _out('D586 $tok done state=${c.id} mode=$mode captures=$shots overflows=$nOvf exc=${exc != null}');

        final f0 = failure;
        if (f0 != null) {
          _halt ??= '$tok ${f0.toString().split('\n').first}';
          Error.throwWithStackTrace(f0, failureSt ?? StackTrace.current);
        }
        // 넘침: strict 0(§6.3 — 큰 글자에서 길이 증가는 허용 · 넘침 · 숨김은 허용하지 않는다) · before 는 기록([DU586b] 옛 오른쪽 힌트 칸이
        //   B 큰 글자에서 할 일 이름 폭을 빼앗아 넘칠 수 있다 — 이 셀 후보가 고치는 것 · README §3).
        if (!_before) chk('화면 전체 넘침 0(strict)', nOvf == 0, ovfRaw);
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

// 측정 도우미(DU578 · DU585b 와 같이 main 뒤).

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

/// 받는 자리 [r] 의 크기 'WxH'.
String _wh(Rect r) => '${r.width.toStringAsFixed(1)}x${r.height.toStringAsFixed(1)}';

/// 읽는 이름 — Text.semanticsLabel(있으면) · 없으면 span 의 읽는 이름을 포함한 평문 · 그다음 data.
String _semOf(Text w) => w.semanticsLabel ?? w.textSpan?.toPlainText() ?? w.data ?? '';

typedef _TO = ({int n, bool shown, bool sem, bool full, bool ell0, int brk, int lines, bool vis});

/// 글 하나 — [tf] 를 ensureVisible 로 화면 안에 넣고 **같은 [tf]** 를 잰다(점검표 A1 · 판정169a §5).
///   shown · full · ell0 · brk = DU560 r3 _textObs(max 판 _fullShown 그대로) · lines = _lineCount · vis = 화면 ∩ 조상 스크롤 칸 안 · n ≠ 1 이면 재지 않는다.
Future<_TO> _textLine(WidgetTester t, Finder tf, String want, Rect screen) async {
  final n = tf.evaluate().length;
  _TextObs o = (shown: false, name: false, full: false, ell0: false, brk: 0, size: Size.zero);
  var sem = false;
  var lines = 0;
  var vis = false;
  if (n == 1) {
    await t.ensureVisible(tf);
    for (var m = 0; m < 4; m++) {
      await t.pump(const Duration(milliseconds: 50));
    }
    o = _textObs(t, tf, want);
    sem = _semOf(t.widget<Text>(tf)) == want;
    lines = _lineCount(t.renderObject<RenderParagraph>(find.descendant(of: tf, matching: find.byType(RichText), skipOffstage: true).first));
    vis = _inside(t.getRect(tf), _area(tf, screen));
  }
  return (n: n, shown: o.shown, sem: sem, full: o.full, ell0: o.ell0, brk: o.brk, lines: lines, vis: vis);
}

double _lum(Color c) {
  double ch(double v) => v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * ch(c.r) + 0.7152 * ch(c.g) + 0.0722 * ch(c.b);
}

double _contrast(Color a, Color b) {
  final x = _lum(a);
  final y = _lum(b);
  return (math.max(x, y) + 0.05) / (math.min(x, y) + 0.05);
}

Color _bgOf(Element e) {
  final layers = <Color>[];
  e.visitAncestorElements((a) {
    final w = a.widget;
    Color? c;
    if (w is ColoredBox) {
      c = w.color;
    } else if (w is DecoratedBox && w.decoration is BoxDecoration) {
      c = (w.decoration as BoxDecoration).color;
    } else if (w is Material && w.type != MaterialType.transparency) {
      c = w.color ?? Theme.of(a).canvasColor;
    }
    if (c == null || c.a == 0) return true;
    layers.add(c);
    return c.a < 1.0;
  });
  var out = layers.isEmpty ? Colors.white : layers.last;
  for (final c in layers.reversed.skip(1)) {
    out = Color.alphaBlend(c, out);
  }
  return out;
}

/// [DU578] 잰 글의 역할 — 그 Text 안 RichText 하나의 실제 글 조각 스타일 서명(DU555 _spansOf · _sig · 여러 조각이면 정렬 '|') ·
///   그린 글자색 · 글 뒤 실제 바탕(_bgOf) · 대비 · 결정값과 같은가. [tf] = _textLine 이 ensureVisible 로 넣고 잰 **같은 Text**(점검표 A1).
typedef _RoleObs = ({String sig, String fg, String bg, String cr, bool ok45, bool role});

const _RoleObs _roleNone = (sig: '-', fg: '-', bg: '-', cr: '0.00', ok45: false, role: false);

_RoleObs _roleOf(Finder tf, String want) {
  final rs = find.descendant(of: tf, matching: find.byType(RichText), skipOffstage: false).evaluate().toList();
  if (rs.length != 1) return _roleNone;
  final rp = rs.first.renderObject;
  if (rp is! RenderParagraph) return _roleNone;
  final sigs = <String>{};
  for (final (_, st) in _spansOf(rp)) {
    sigs.add(_sig(st));
  }
  final sig = sigs.isEmpty ? '-' : (sigs.toList()..sort()).join('|');
  final Color? fg = (rs.first.widget as RichText).text.style?.color;
  final bg = _bgOf(rs.first);
  final cr = fg == null ? 0.0 : _contrast(fg, bg);
  return (sig: sig, fg: fg == null ? '-' : _hex(fg), bg: _hex(bg), cr: cr.toStringAsFixed(2), ok45: cr >= 4.5, role: sig == want);
}

/// [DU586b] 대상 [x] 의 범위 닻(배너 설명 · 준비 카드 제목 · 할 일 이름) — 찾기 전 _bringBuilt 대상(점검표 A4 · 힌트 자리 pl 이 쓰는 카드 · 할 일 이름 포함).
///   닻이 없는 범위는 대상 글 자신.
List<String> _anchorsOf(String id, _Tg x) => switch (x.scope) {
      'banner' => [_bannerSub(id)],
      'card' => [_setupTitle(id)],
      'tile' => [_setupTitle(id), x.tile],
      _ => [x.want],
    };

/// [DU586b] 준비 카드 범위 — 카드 제목 Text 의 가장 가까운 Column(= 카드 본문 Column: 머리 Padding · Divider · 할 일 4 행).
Finder _cardOf(Finder home, String id) =>
    find.ancestor(of: _txt(home, _setupTitle(id), onstage: false), matching: find.byType(Column)).first;

/// [DU586b] 대상 [x] 의 Text — 범위 안에서만 찾는다(NOBIZ 의 '사업장 등록' = 배너 제목 · 배너 단추 · 할 일 이름 셋 · '사업장 등록 후 가능' = 할 일 둘).
Finder _scopeOf(Finder home, String id, _Tg x) {
  switch (x.scope) {
    case 'banner':
      final col = find.ancestor(of: _txt(home, _bannerSub(id), onstage: false), matching: find.byType(Column)).first;
      return _txt(col, x.want, onstage: false);
    case 'button':
      return _txt(find.descendant(of: home, matching: find.byWidgetPredicate((w) => w is ElevatedButton), skipOffstage: false), x.want, onstage: false);
    case 'card':
      return _txt(_cardOf(home, id), x.want, onstage: false);
    case 'tile':
      final row = find.ancestor(of: _txt(_cardOf(home, id), x.tile, onstage: false), matching: find.byType(InkWell)).first;
      return _txt(row, x.want, onstage: false);
    default:
      return _txt(home, x.want, onstage: false);
  }
}

/// [DU586b] 배너 단추(STATE A '사업장 등록' ElevatedButton.icon) 받는 자리 — ensureVisible 로 넣고 **같은 받는 자리**를 잰다(A1). 누르기 0.
typedef _BtnObs = ({int n, bool vis, bool hit, bool m48, String rcv});

Future<_BtnObs> _btnObs(WidgetTester t, Finder home, Rect screen) async {
  final bf = find.descendant(of: home, matching: find.byWidgetPredicate((w) => w is ElevatedButton), skipOffstage: false);
  final n = bf.evaluate().length;
  if (n != 1) return (n: n, vis: false, hit: false, m48: false, rcv: '-');
  await t.ensureVisible(bf);
  for (var m = 0; m < 4; m++) {
    await t.pump(const Duration(milliseconds: 50));
  }
  final r = t.getRect(bf);
  return (n: n, vis: _inside(r, _area(bf, screen)), hit: _hitWithin(t, bf, r.center), m48: r.width >= 48 - 0.01 && r.height >= 48 - 0.01, rcv: _wh(r));
}

/// [DU586b] 글 칸 출력 한 줄 — sub 마다 리터럴 줄(preflight 2-5 가 'att <sub>' 키를 정적 대조 · lgate 가 같은 줄을 판정). 키 순서 = prep/lines_du586b.py TEXT_KEYS.
void _tgOut(String tok, String sub, _TO o, _RoleObs r) {
  switch (sub) {
    case 'hn':
      _out('D586 $tok att hn n=${o.n} shown=${o.shown} sem=${o.sem} full=${o.full} ell0=${o.ell0} brk=${o.brk} lines=${o.lines} vis=${o.vis} sig=${r.sig} fg=${r.fg} bg=${r.bg} cr=${r.cr} ok45=${r.ok45} role=${r.role}');
    case 'bt':
      _out('D586 $tok att bt n=${o.n} shown=${o.shown} sem=${o.sem} full=${o.full} ell0=${o.ell0} brk=${o.brk} lines=${o.lines} vis=${o.vis} sig=${r.sig} fg=${r.fg} bg=${r.bg} cr=${r.cr} ok45=${r.ok45} role=${r.role}');
    case 'bs':
      _out('D586 $tok att bs n=${o.n} shown=${o.shown} sem=${o.sem} full=${o.full} ell0=${o.ell0} brk=${o.brk} lines=${o.lines} vis=${o.vis} sig=${r.sig} fg=${r.fg} bg=${r.bg} cr=${r.cr} ok45=${r.ok45} role=${r.role}');
    case 'bb':
      _out('D586 $tok att bb n=${o.n} shown=${o.shown} sem=${o.sem} full=${o.full} ell0=${o.ell0} brk=${o.brk} lines=${o.lines} vis=${o.vis} sig=${r.sig} fg=${r.fg} bg=${r.bg} cr=${r.cr} ok45=${r.ok45} role=${r.role}');
    case 'st':
      _out('D586 $tok att st n=${o.n} shown=${o.shown} sem=${o.sem} full=${o.full} ell0=${o.ell0} brk=${o.brk} lines=${o.lines} vis=${o.vis} sig=${r.sig} fg=${r.fg} bg=${r.bg} cr=${r.cr} ok45=${r.ok45} role=${r.role}');
    case 'pp':
      _out('D586 $tok att pp n=${o.n} shown=${o.shown} sem=${o.sem} full=${o.full} ell0=${o.ell0} brk=${o.brk} lines=${o.lines} vis=${o.vis} sig=${r.sig} fg=${r.fg} bg=${r.bg} cr=${r.cr} ok45=${r.ok45} role=${r.role}');
    default:
      throw StateError('DU586b 글 칸 sub 선언 밖 $sub');
  }
}

/// [DU586b] 할 일 이름 출력 한 줄 — 키 순서 = LABEL_KEYS(TEXT_KEYS + rcv · m48).
void _lbOut(String tok, String sub, _TO o, _RoleObs r, String rcv, bool m48) {
  switch (sub) {
    case 'l1':
      _out('D586 $tok att l1 n=${o.n} shown=${o.shown} sem=${o.sem} full=${o.full} ell0=${o.ell0} brk=${o.brk} lines=${o.lines} vis=${o.vis} sig=${r.sig} fg=${r.fg} bg=${r.bg} cr=${r.cr} ok45=${r.ok45} role=${r.role} rcv=$rcv m48=$m48');
    case 'l2':
      _out('D586 $tok att l2 n=${o.n} shown=${o.shown} sem=${o.sem} full=${o.full} ell0=${o.ell0} brk=${o.brk} lines=${o.lines} vis=${o.vis} sig=${r.sig} fg=${r.fg} bg=${r.bg} cr=${r.cr} ok45=${r.ok45} role=${r.role} rcv=$rcv m48=$m48');
    case 'l3':
      _out('D586 $tok att l3 n=${o.n} shown=${o.shown} sem=${o.sem} full=${o.full} ell0=${o.ell0} brk=${o.brk} lines=${o.lines} vis=${o.vis} sig=${r.sig} fg=${r.fg} bg=${r.bg} cr=${r.cr} ok45=${r.ok45} role=${r.role} rcv=$rcv m48=$m48');
    case 'l4':
      _out('D586 $tok att l4 n=${o.n} shown=${o.shown} sem=${o.sem} full=${o.full} ell0=${o.ell0} brk=${o.brk} lines=${o.lines} vis=${o.vis} sig=${r.sig} fg=${r.fg} bg=${r.bg} cr=${r.cr} ok45=${r.ok45} role=${r.role} rcv=$rcv m48=$m48');
    default:
      throw StateError('DU586b 할 일 이름 sub 선언 밖 $sub');
  }
}

/// [DU586b] 힌트 출력 한 줄 — 키 순서 = HINT_KEYS(TEXT_KEYS + pl).
void _hnOut(String tok, String sub, _TO o, _RoleObs r, String pl) {
  switch (sub) {
    case 'h1':
      _out('D586 $tok att h1 n=${o.n} shown=${o.shown} sem=${o.sem} full=${o.full} ell0=${o.ell0} brk=${o.brk} lines=${o.lines} vis=${o.vis} sig=${r.sig} fg=${r.fg} bg=${r.bg} cr=${r.cr} ok45=${r.ok45} role=${r.role} pl=$pl');
    case 'h2':
      _out('D586 $tok att h2 n=${o.n} shown=${o.shown} sem=${o.sem} full=${o.full} ell0=${o.ell0} brk=${o.brk} lines=${o.lines} vis=${o.vis} sig=${r.sig} fg=${r.fg} bg=${r.bg} cr=${r.cr} ok45=${r.ok45} role=${r.role} pl=$pl');
    case 'h3':
      _out('D586 $tok att h3 n=${o.n} shown=${o.shown} sem=${o.sem} full=${o.full} ell0=${o.ell0} brk=${o.brk} lines=${o.lines} vis=${o.vis} sig=${r.sig} fg=${r.fg} bg=${r.bg} cr=${r.cr} ok45=${r.ok45} role=${r.role} pl=$pl');
    default:
      throw StateError('DU586b 힌트 sub 선언 밖 $sub');
  }
}

/// [DU586b] 배너 단추 받는 자리 출력 한 줄 — 키 순서 = BTN_KEYS.
void _bkOut(String tok, _BtnObs b) {
  _out('D586 $tok att bk n=${b.n} vis=${b.vis} hit=${b.hit} m48=${b.m48} rcv=${b.rcv}');
}

/// [DU586b · 점검표 A8] 캡처 직전 화면 채움 단추 기록 한 줄 — 묶음 번호마다 리터럴 줄(키 순서 = FILL_KEYS).
void _fillsOut(String tok, int i, _FillObs fl) {
  switch (i) {
    case 1:
      _out('D586 $tok att fills1 n=${fl.n} brand=${fl.brand} err=${fl.err} none=${fl.none} other=${fl.other} list=${fl.list}');
    case 2:
      _out('D586 $tok att fills2 n=${fl.n} brand=${fl.brand} err=${fl.err} none=${fl.none} other=${fl.other} list=${fl.list}');
    case 3:
      _out('D586 $tok att fills3 n=${fl.n} brand=${fl.brand} err=${fl.err} none=${fl.none} other=${fl.other} list=${fl.list}');
    default:
      throw StateError('DU586b 채움 기록 번호 선언 밖 $i');
  }
}
