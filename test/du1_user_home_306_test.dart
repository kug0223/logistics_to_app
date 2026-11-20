// ignore_for_file: depend_on_referenced_packages
// [DU306 DU-USER-HOME-PREP-306] 지원자 홈 묶음 — 머리 관계(8/4/8) + 초대·요청·일반 진행·재시도 색, before/after 같은 순서.
//   근거: requests/DU_implementation_306.md §1–5, reports/DU_audit_306.md §3, reports/DU_preparation_306.md §5.1–5.3,
//         reports/DU_audit_305_preexec.md(306 선행 허용). production 편집 0(시험은 관측만, 새 seam·계측 0).
//   DU306_RUN=1, DU306_PHASE=before|after, DU306_DAY=2026-11-13 일 때만 실행(기본 skip). 실제 KST 날짜·08:00–21:30 도 검증한다.
//   상태(같은 순서, 원점 offset 0 에서 시작, 배너 숨김): F1 W/B · F2 W/B · F2i W · F3 W/B · F4 W/B · F5 W · F7 W(첫 로드 → resume).
//   after 는 준비보고 §5.3 의 전문·배치·색·실receiver 계약을 단언하고, before 는 같은 측정을 같은 순서로 기록만 한다.
//   입력·무네트워크·무업무쓰기·FlutterError/overflow·계측 유효성·도달 한도(대상당 drag ≤2)는 두 phase 공통이다.
//   하네스: du_concept_cp03_worker_home_test.dart 의 provider 대역·UserHomeReads 주입·폰트 등록·고정 KST 시각·활성 clip 도형을
//   복사·축약했다(원 파일 import·등록 0). 행동은 실제 drag·tap·resume dispatch 만 쓴다(ensureVisible·pumpAndSettle·route 열기 0).
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

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
import 'package:ALfit/models/core/employment_contract_model.dart';
import 'package:ALfit/models/core/id_card_access_request_model.dart';
import 'package:ALfit/models/core/legal_readiness.dart';
import 'package:ALfit/models/core/renewal_proposal_model.dart';
import 'package:ALfit/models/core/slot_model.dart';
import 'package:ALfit/models/core/to_model.dart';
import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/models/core/user_region.dart';
import 'package:ALfit/providers/notification_provider.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/screens/user/user_home_reads.dart';
import 'package:ALfit/screens/user/user_home_screen.dart';
import 'package:ALfit/screens/user/user_tab_scope.dart';
import 'package:ALfit/services/payroll_correction_service.dart';
import 'package:ALfit/theme/app_colors.dart';
import 'package:ALfit/theme/role_theme.dart';
import 'package:ALfit/utils/format_helper.dart';
import 'package:ALfit/utils/text_layout.dart';
import 'package:ALfit/widgets/common/alfit_wordmark.dart';
import 'package:ALfit/widgets/common/notification_badge.dart';

import 'support/checkin_contract_fixture.dart';
import 'support/du1_vq_capture.dart';
import 'support/visible_text.dart';

class _FakeApp extends Fake with MockPlatformInterfaceMixin implements FirebaseAppPlatform {
  @override
  String get name => defaultFirebaseAppName;
  @override
  FirebaseOptions get options => const FirebaseOptions(apiKey: 'k', appId: 'a', messagingSenderId: 's', projectId: 'p');
}

/// 초기화용 platform 대역(Firebase core). 업무 호출 허용이 아니다.
class _FakeCore extends FirebasePlatform with MockPlatformInterfaceMixin {
  @override
  FirebaseAppPlatform app([String name = defaultFirebaseAppName]) => _FakeApp();
  @override
  Future<FirebaseAppPlatform> initializeApp({String? name, FirebaseOptions? options}) async => _FakeApp();
  @override
  List<FirebaseAppPlatform> get apps => [_FakeApp()];
}

/// 네트워크 접근 guard(HttpClient 생성 계수·차단).
class _NoNet extends HttpOverrides {
  int created = 0;
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    created++;
    throw StateError('DU306 network guard');
  }
}

void _out(String l) {
  // ignore: avoid_print
  print(l);
}

const _kDay = '2026-11-13'; // 실행 허용일(요청 §1). 다른 날이면 skip 이고 자동 이월하지 않는다.
const _biz = 'biz1';
const _bizName = '강남 물류센터';
const _longName = '응우옌 티 프엉 타오 쩐'; // CP01/CP03 긴 이름 표본 — F1·F2·F2i
const _longBiz = '강남구 테헤란로 제2물류센터 야간 상하차 전용 창고'; // CP01 긴 사업장 표본 — F3 연장 제안
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
// phase 동적 상한 C(요청 §4) — (pump, home mount, tap+dispatch, drag, 명시 route, text, PNG). teardown 빈 mount 는 pump 로 센다.
const _kC = (pump: 547, mount: 12, tap: 6, drag: 24, route: 0, text: 0, png: 11); // [r3c] +F1_N(open 25+teardown 2 pump, mount 1, PNG 1)
const _kPng = 11;

// ── 고정 시각(KST) — 실행 허용일 2026-11-13 10:00 KST ──
final DateTime _clock = DateTime.utc(2026, 11, 13, 1);
final DateTime _today = FormatHelper.toKstDate(_clock);
DateTime _day(int o) => _today.add(Duration(days: o));
DateTime _kstAt(DateTime day, int h, int m) => DateTime.utc(day.year, day.month, day.day, h, m).subtract(const Duration(hours: 9));

/// 지원자 provider 대역(CP03 :81 과 같은 게터 덮개). 이름·근무 이력만 사례별로 바꾼다.
class _Worker extends UserProvider {
  _Worker({required this.displayName, required this.workDays});
  final String displayName;
  final int workDays;
  @override
  UserModel? get currentUser => UserModel(
      uid: 'u1', username: 'u1', name: displayName, email: 'u1@alfit.local', role: UserRole.USER,
      homeRegion: const UserRegion(province: '서울특별시', city: '강남구', district: '역삼동'),
      accountStatus: 'active', passVerifiedAt: DateTime.utc(2026, 10, 1), totalWorkDays: workDays);
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

/// SubAdmin(지원자 모드) 대역 — CP01 :91 의 게터 덮개를 지원자 모드·긴 이름으로 쓴다. 전환 호출은 기록만 한다(tap 0).
class _Sub extends UserProvider {
  _Sub({required this.calls});
  final List<String> calls;
  @override
  Future<void> switchToAdminMode(String businessId) async => calls.add('switchToAdminMode:$businessId');
  @override
  void toggleAdminMode() => calls.add('toggleAdminMode');
  @override
  UserModel? get currentUser => UserModel(
      uid: 'u1', username: 'u1', name: _longName, email: 'u1@alfit.local', role: UserRole.USER,
      homeRegion: const UserRegion(province: '서울특별시', city: '강남구', district: '역삼동'),
      accountStatus: 'active', passVerifiedAt: DateTime.utc(2026, 10, 1), totalWorkDays: 3,
      subAdminBusinessIds: const [_biz], sealBase64: 'seal');
  @override
  bool get isSubAdmin => true;
  @override
  bool get isBusinessAdmin => false;
  @override
  bool get isSuperAdmin => false;
  @override
  bool get isAdminMode => false;
  @override
  bool get permissionsLoaded => true;
  @override
  Map<String, String> get subAdminBusinessNames => const {_biz: _bizName};
  @override
  String? get effectiveBusinessId => _biz;
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

ApplicationModel _app(String id, DateTime workDate,
        {String status = AppStatus.confirmed, String start = '13:00', String end = '18:00', DateTime? confirmedAt}) =>
    ApplicationModel(
        id: id, toId: 'to_$id', uid: 'u1', businessId: _biz, businessName: _bizName, toTitle: '단기 공고',
        status: status, selectedWorkType: '피킹', startTime: start, endTime: end, wage: 12000, wageType: 'hourly',
        workDate: workDate, appliedAt: _day(-3), confirmedAt: confirmedAt);

BusinessModel _business() => BusinessModel(
    id: _biz, name: _bizName, ownerId: 'a1', businessNumber: '000-00-00000', address: '서울특별시 강남구 테헤란로 1',
    category: '물류', subCategory: '창고', isApproved: true, createdAt: _day(-200));

/// 지금 응답할 수 있는 연장 제안(UHR :195 모양) — 사업장 이름만 긴 표본.
RenewalProposalModel _proposal() => RenewalProposalModel(
      id: 'rp1',
      businessId: _biz,
      businessName: _longBiz,
      workerUid: 'u1',
      oldApplicationId: 'long1',
      status: RenewalProposalStatus.pending,
      effectiveStart: _day(1),
      effectiveEnd: _day(60),
    );

/// F5 오늘 근무 출퇴근 완료 근태 — 06:00 출근·09:00 퇴근(KST).
AttendanceModel _doneAtt() => AttendanceModel(
      id: 'att_d1',
      applicationId: 'd1',
      userId: 'u1',
      businessId: _biz,
      businessName: _bizName,
      workDate: _today,
      workType: '피킹',
      status: AttendanceModel.statusPresent,
      wageStatus: AttendanceModel.wagePending,
      adminConfirmed: false,
      checkInAt: _kstAt(_today, 6, 0),
      checkOutAt: _kstAt(_today, 9, 0),
      createdAt: _today,
    );

/// [CP03 C1 r2] 조상이 자식에게 실제로 거는 clip 의 정확 도형(CP03 :222–303 그대로).
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

// 상대 휘도·대비(WCAG) — 글자색이 반투명이면 실제 바탕 위에 합성한다.
double _lum(Color c) {
  double ch(double v) => v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * ch(c.r) + 0.7152 * ch(c.g) + 0.0722 * ch(c.b);
}

Color _over(Color fg, Color bg) => Color.from(
    alpha: 1, red: fg.r * fg.a + bg.r * (1 - fg.a), green: fg.g * fg.a + bg.g * (1 - fg.a), blue: fg.b * fg.a + bg.b * (1 - fg.a));

double _contrast(Color a, Color b) {
  final la = _lum(a), lb = _lum(b);
  final hi = la > lb ? la : lb, lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

typedef _V = ({String id, Size size, double scale});
const _V _w = (id: 'W', size: Size(390, 844), scale: 1.0);
const _V _b = (id: 'B', size: Size(320, 640), scale: 2.0);
const _V _n = (id: 'N', size: Size(320, 640), scale: 1.0); // [r3c] 좁은 화면·정상 글씨(원점 머리 표본만)

/// [r3c] 배지 표시 입력 고정 — 실제 NotificationProvider 를 상속해 Selector 가 읽는 getter 3개만 고정한다(HTTP·업무 쓰기 0).
///   F1_B·F1_N 에만 쓰고 양 phase 같다. 원 회귀 fixture 는 바꾸지 않는다.
class _Unread1Notifs extends NotificationProvider {
  @override
  int get unreadCount => 1;
  @override
  bool get hasMore => false;
  @override
  bool get hasError => false;
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
  final phase = Platform.environment['DU306_PHASE'] ?? '';
  final dayArg = Platform.environment['DU306_DAY'] ?? '';
  final run = Platform.environment['DU306_RUN'] == '1' && (phase == 'before' || phase == 'after') && dayArg == _kDay;
  final after = phase == 'after';
  final nl = String.fromCharCode(10);

  setUpAll(() async {
    if (!run) return;
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
    await initializeDateFormatting('ko_KR');
    await _loadFonts();
  });

  testWidgets('D306 $phase', (t) async {
    DateTime kstNow() => DateTime.now().toUtc().add(const Duration(hours: 9));
    final sem = t.ensureSemantics(); // 로고 이미지 의미 노드 관측(행동 아님)
    final prevOnError = FlutterError.onError;
    final prevHttp = HttpOverrides.current;
    final net = _NoNet();
    HttpOverrides.global = net;
    final biz = <String, int>{};
    final m = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    for (final op in _fsOps) {
      m.setMockMessageHandler('$_fsBase.$op', (msg) async {
        biz['fs.$op'] = (biz['fs.$op'] ?? 0) + 1;
        return const StandardMessageCodec().encodeMessage(<Object?>['du306-blocked', 'firestore $op 차단', null]);
      });
    }
    for (final op in _fnOps) {
      m.setMockMessageHandler('$_fnBase.$op', (msg) async {
        biz['fn.$op'] = (biz['fn.$op'] ?? 0) + 1;
        return const StandardMessageCodec().encodeMessage(<Object?>['du306-blocked', 'functions $op 차단', null]);
      });
    }
    m.setMockMethodCallHandler(const MethodChannel(_fnLegacy), (call) async {
      biz['fn.legacy.${call.method}'] = (biz['fn.legacy.${call.method}'] ?? 0) + 1;
      throw PlatformException(code: 'du306-blocked', message: 'functions legacy ${call.method} 차단');
    });

    var nPump = 0, nMount = 0, nTap = 0, nDrag = 0, nRoute = 0, nText = 0, nPng = 0;
    Map<String, Object?> counts() =>
        {'phase': phase, 'pump': nPump, 'homeMount': nMount, 'tapDispatch': nTap, 'drag': nDrag, 'route': nRoute, 'text': nText, 'png': nPng};
    var cond = '-';
    var stage = 'start';
    final errors = <({String cond, String stage, int pump, String first, String full})>[];
    FlutterError.onError = (d) => errors.add((
          cond: cond,
          stage: stage,
          pump: nPump,
          first: d.exceptionAsString().split(nl).first,
          full: TextTreeRenderer(wrapWidth: 400).render(d.toDiagnosticsNode(style: DiagnosticsTreeStyle.error)).trimRight(),
        ));
    final visited = <String>[];
    var live = false;
    var completed = false;

    Never stop(String why) {
      _out('D306-STOP ${jsonEncode({'phase': phase, 'cond': cond, 'stage': stage, 'why': why,
        'pendingErrors': errors.map((e) => '${e.cond}/${e.stage}#${e.pump}: ${e.first}').toList(), 'counts': counts(),
        'http': net.created, 'business': biz})}');
      for (final e in errors) {
        _out('D306-STOPERR ${jsonEncode({'cond': e.cond, 'stage': e.stage, 'pump': e.pump, 'full': e.full})}');
      }
      fail('$phase/$cond/$stage: $why');
    }

    void need(bool ok, String why) {
      if (!ok) stop(why);
    }

    // after 단언 / before 기록 — 값은 항상 먼저 출력한다(D306-CHECK).
    void check(bool ok, String what, [Object? detail]) {
      _out('D306-CHECK ${jsonEncode({'phase': phase, 'cond': cond, 'stage': stage, 'what': what, 'ok': ok, 'assert': after, 'detail': detail})}');
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
        _out('D306-ERR ${jsonEncode({'phase': phase, 'cond': e.cond, 'stage': e.stage, 'pump': e.pump, 'first': e.first, 'full': e.full})}');
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

    Color? colorOf(Element e) => ((e.widget as RichText).text as TextSpan).style?.color;
    TextStyle? styleOf(Element e) => ((e.widget as RichText).text as TextSpan).style;
    String hex(Color? c) => c == null ? 'null' : c.toARGB32().toRadixString(16);

    bool hitAt(Offset p, Element receiver) {
      final ro = receiver.renderObject;
      final hit = HitTestResult();
      WidgetsBinding.instance.hitTestInView(hit, p, t.view.viewId);
      return hit.path.any((e) => identical(e.target, ro));
    }

    // 활성 clip 사슬(CP03 정확 도형) + 화면 안 — 대상 render box 사각의 네 모서리 기준
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

    // 가시·hit 관측(값 출력) → after 단언 / before 기록
    void visHit(Element e, String what, Rect screen, {Element? receiver, bool always = false}) {
      final c = clipOf(e, screen);
      final r = rectOf(e);
      final rec = receiver ?? e;
      final hit = hitAt(r.center, rec);
      _out('D306-VIS ${jsonEncode({'phase': phase, 'cond': cond, 'stage': stage, 'what': what, 'rect': rl(r), 'full': c.full,
        'failures': c.failures, 'hit': hit})}');
      if (after || always) need(c.full && hit, '$what 가시/hit 아님 ${c.failures} hit=$hit');
    }

    // RenderParagraph → TextPainter 재구성(DU305 감사 r2 §3-1 과 같은 제약·±0.01). placeholder 가 있으면 재구성하지 않는다.
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
      final cs = p.constraints.constrain(tp.size);
      final ok = near(tp.width, ts.width, _kTol) && near(tp.height, ts.height, _kTol) && near(cs.width, p.size.width, _kTol) &&
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
      _out('D306-PARA ${jsonEncode(rec)}');
      need(ok, '$what TextPainter 재구성 불일치');
      return rec;
    }

    // 전문(after): 원문 = 보이는 글자, maxLines 없음, 말줄임 0, 자연 높이
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
      final f = find.descendant(of: find.byType(UserHomeScreen),
          matching: find.byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.down));
      final els = f.evaluate().toList();
      return els.isEmpty ? null : els.first;
    }

    double offsetOf(Element? se) => se == null ? 0.0 : ((se as StatefulElement).state as ScrollableState).position.pixels;

    // bounded 세로 drag(대상마다 최대 2회, 위쪽 되돌림 drag 0 — pull-to-refresh 방지).
    //   [r3 — 요청 DU_prep_306_r3 §2, 감사 306 r1 §4] SDK 경로를 피해 한 번에 정확히 도달한다:
    //   - flutter_test dragFrom 은 먼저 kDragSlopDefault(20)만큼 움직인다(controller.dart:1582·:1620). 인식기는 그 20을 버리거나
    //     (DragStartBehavior.start) 첫 update 로 넘긴다(down) — R1T 12·R2T 24, 합계 36개 REACH 가 두 수치분기(slop 폐기/첫 20 전달)를 모두 보였다(repair/r3/plan/drag_model.json). 실제 DragStartBehavior 설정 전환은 미관측이다.
    //   - 홈의 BouncingScrollPhysics 는 첫 update u 가 문턱 3.5 를 넘을 때 u > 24 면 그대로, 아니면 min(3.5/3, u)만 움직인다
    //     (scroll_physics.dart:801, scroll_activity.dart:319·:371) — 작은 요청이 1.1667 만 움직인 원인이다.
    //   그래서 이동량 m 을 24.5 이상으로 잡고(감쇠 구간 회피) 보낼 거리 = m + 20 이다. 예측 이동은 [m, m + 3.5/3] 이다.
    //   m 은 최소 이동 d(아래끝이 창 안) 이상, 위끝이 창 위로 나가지 않는 상한 hi 와 남은 extent 안에서만 고른다. 고를 수 없으면
    //   추측 drag 를 하지 않고 멈춘다(하네스 한계, 보고 대상). 루프 뒤 목표영역 전체가 창 안인지 확인한다(최종 도달 검증).
    const kBig = 24.5; // scroll_activity.dart _bigThresholdBreakDistance(24) 초과
    const kDownExtra = 3.5 / 3; // DragStartBehavior.down 경로의 첫 update 감쇠분(관측 1.1667)
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
        final d = r.bottom - vp.bottom; // 최소 이동
        final hi = r.top - vp.top; // 위끝 보호 상한(= d + 창 − 높이)
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
        _out('D306-REACH ${jsonEncode({'phase': phase, 'cond': cond, 'what': what, 'try': i, 'd': d, 'a': a, 'hi': hi, 'room': room, 'req': m,
          'send': send, 'predicted': [m, m + kDownExtra], 'before': p0, 'after': pos.pixels, 'moved': moved, 'max': pos.maxScrollExtent})}');
      }
      final rf = rectOf(target);
      final vpf = boxRect(se.renderObject! as RenderBox).intersect(screen);
      need(rf.top >= vpf.top - 0.5 && rf.bottom <= vpf.bottom + 0.5, '$what reach 뒤 목표영역이 창 밖 ${rl(rf)} 창 ${rl(vpf)}');
    }

    final capKey = GlobalKey();
    final scopeLog = <String>[];

    Future<void> open(String id, _V v, UserProvider prov, UserHomeReads reads, {double topInset = 0, bool unread1 = false}) async {
      cond = id;
      stage = 'mount';
      clockGuard('mount $id');
      SharedPreferences.setMockInitialValues({'onboarding_completed_u1': true, 'tour_completed_user_home': true});
      t.view.physicalSize = v.size;
      t.view.devicePixelRatio = 1.0;
      t.view.padding = topInset > 0 ? FakeViewPadding(top: topInset) : FakeViewPadding.zero;
      t.view.viewPadding = topInset > 0 ? FakeViewPadding(top: topInset) : FakeViewPadding.zero;
      t.platformDispatcher.textScaleFactorTestValue = v.scale;
      t.platformDispatcher.localesTestValue = const [Locale('ko', 'KR')];
      t.platformDispatcher.localeTestValue = const Locale('ko', 'KR');
      scopeLog.clear();
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
            key: ValueKey('D306-$phase-$id'),
            debugShowCheckedModeBanner: false,
            theme: RoleTheme.workerTheme,
            locale: const Locale('ko', 'KR'),
            supportedLocales: const [Locale('ko', 'KR'), Locale('en', 'US')],
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            home: UserTabScope(
              switchToTab: (i) => scopeLog.add('switchToTab:$i'),
              switchToTabWithDate: (i, d) => scopeLog.add('switchToTabWithDate:$i/${d.year}-${d.month}-${d.day}'),
              pendingJobDate: null,
              clearPendingJobDate: () {},
              pendingScheduleMonth: null,
              clearPendingScheduleMonth: () {},
              switchToScheduleNow: () => scopeLog.add('switchToScheduleNow'),
              child: UserHomeScreen(reads: reads, clock: () => _clock),
            ),
          ),
        ),
      ));
      live = true;
      guard('mount');
      await frames(25, 'load');
      stage = 'origin';
      need(offsetOf(homeScroll()) <= _kEps, '원점 offset 0 아님 ${offsetOf(homeScroll())}');
      // 배너 숨김(계정 상태·PASS 복구) — 머리가 SafeArea 바로 아래에 온다
      final banners = find.byWidgetPredicate((w) => w.runtimeType.toString() == 'AccountStatusBanner').evaluate().toList();
      final bannerH = banners.isEmpty ? 0.0 : (banners.first.renderObject as RenderBox?)?.size.height ?? 0.0;
      need(richExact('지원을 위해 본인인증이 필요해요').evaluate().isEmpty && bannerH <= _kEps, '배너 숨김 아님 h=$bannerH');
      // 실제 배율 — 본문 글자 문단(`오늘도, 내 일정에 맞게`)의 textScaler.
      //   [수리 r1] 화면 첫 RichText 는 알림 Icon 글리프였다(Icon 은 배율을 받지 않음) — 본문 글자로 바꾼다. 기준값·장면은 그대로다.
      final heroText = one('오늘도, 내 일정에 맞게').evaluate().first;
      need(near((heroText.renderObject! as RenderParagraph).textScaler.scale(10) / 10, v.scale, 1e-6), '실제 배율 ${v.scale} 아님');
      _out('D306-OPEN ${jsonEncode({'phase': phase, 'cond': id, 'viewport': '${v.size.width.toInt()}x${v.size.height.toInt()}',
        'scale': v.scale, 'topInset': topInset, 'unread1': unread1, 'clock': _clock.toIso8601String(), 'counts': counts()})}');
    }

    Future<void> teardown() async {
      stage = 'teardown';
      nPump++; // teardown 빈 mount 는 home mount 와 분리해 pump 로 센다(요청 §4)
      budget();
      await t.pumpWidget(const SizedBox.shrink());
      live = false;
      guard('teardown');
      await frames(1, 'teardown', ms: 50);
      t.view.resetPadding();
      t.view.resetViewPadding();
      visited.add(cond);
    }

    Future<void> png(String step, _V v) async {
      nPng++;
      budget();
      await vqCapture(t, capKey, 'D306-$phase-$cond-$step', conditions: {
        'phase': phase, 'cond': cond, 'step': step, 'viewport': '${v.size.width.toInt()}x${v.size.height.toInt()}', 'dpr': 1.0,
        'textScaler': v.scale, 'locale': 'ko_KR', 'clock': _clock.toIso8601String(), 'offset': offsetOf(homeScroll()),
        'realNow': DateTime.now().toIso8601String(), 'pinDay': dayArg,
      });
    }

    double sOf(_V v) => v.size.width < 360 ? 0.82 : (v.size.width < 400 ? 0.92 : 1.0);
    double gutterOf(_V v) => v.size.width < 360 ? 16 : 20;

    // ── Reads 대역(호출 계수) ──
    UserHomeReads reads({
      required Map<String, int> calls,
      List<ApplicationModel> apps = const [],
      bool Function()? appsFail,
      bool attsFail = false,
      List<AttendanceModel> atts = const [],
      List<EmploymentContractModel> contracts = const [],
      List<RenewalProposalModel> proposals = const [],
      DocumentCorrectionSurface corrections = DocumentCorrectionSurface.empty,
    }) {
      void c(String k) => calls[k] = (calls[k] ?? 0) + 1;
      return UserHomeReads(
        slotsForTO: (_) async {
          c('slots');
          return const <SlotModel>[];
        },
        myContracts: (_) async {
          c('contracts');
          return contracts;
        },
        myApplications: (_) async {
          c('apps');
          if (appsFail != null && appsFail()) throw Exception('DU306 LOCAL 지원 조회 실패 fixture');
          return apps;
        },
        myMonthlyAttendances: ({required String userId, required int year, required int month}) async {
          c('atts');
          if (attsFail) throw Exception('DU306 LOCAL 근태 조회 실패 fixture');
          return (year == _today.year && month == _today.month) ? atts : const <AttendanceModel>[];
        },
        publishedTOs: () async {
          c('tos');
          return const <TOModel>[];
        },
        pendingIdCardRequests: (_) async {
          c('id');
          return const <IdCardAccessRequestModel>[];
        },
        myRenewalProposals: () async {
          c('renewal');
          return proposals;
        },
        businessById: (_) async {
          c('biz');
          return _business();
        },
        invalidatePublishedTOsCache: () => c('invalidate'),
        documentCorrections: () async {
          c('corr');
          return corrections;
        },
        legalReadiness: () async {
          c('legal');
          return const LegalReadiness(status: LegalReadinessStatus.current);
        },
      );
    }

    // [r3c L2] 배지(unread 1·hasMore false·hasError false 고정 입력) — 같은 frame 에서 위 끝 ≥ 머리 시작·SafeArea, 아래 끝 ≤ 행동행 아래,
    //   로고 잉크와 겹침 0, 숫자 전문 가시(배지는 IgnorePointer 라 hit 은 보지 않는다). 종 글리프와의 겹침은 기존 설계(오른쪽 위 모서리)라 기록만 한다.
    void badgeCheck(Rect header, Rect row, Rect? ink, Rect screen, double safeTop) {
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
      final logoOv = ink != null && br.overlaps(ink);
      final c = clipOf(txt.evaluate().first, screen);
      _out('D306-BADGE ${jsonEncode({'phase': phase, 'cond': cond, 'badge': rl(br), 'text': rl(tr), 'header': rl(header), 'row': rl(row),
        'safeTop': safeTop, 'glyph': gr == null ? null : rl(gr), 'glyphOverlapArea': glyphOv, 'logoOverlap': logoOv, 'textFull': c.full,
        'failures': c.failures})}');
      check(br.top >= header.top - _kTol && br.top >= safeTop - _kTol, 'S-BADGE 위 끝 ≥ 머리 시작·SafeArea', [br.top, header.top, safeTop]);
      check(br.bottom <= row.bottom + _kTol, 'S-BADGE 아래 끝 ≤ 행동행 아래', [br.bottom, row.bottom]);
      check(!logoOv, 'S-BADGE 로고 잉크 겹침 0', rl(br));
      check(c.full, 'S-BADGE 숫자 전문 가시', c.failures);
      // [r3d] 종 침범 기준(Icon layout rect 기준 — 실제 paint 가림 판단이 아님): (a) 종 중심점이 배지 밖, (b) 겹침 ≤ 종 rect 면적의 25%.
      final glyphArea = gr == null ? 0.0 : gr.width * gr.height;
      check(gr != null && !br.contains(gr.center) && glyphOv <= 0.25 * glyphArea + _kTol, 'S-BADGE 종 침범 기준(중심 밖·겹침 ≤25%)',
          [gr == null ? null : rl(gr), glyphOv, glyphArea]);
      stage = 'header';
    }

    // ── S-H 머리 관계(F1·F2·F2i) ──
    void headerCheck(_V v, String name, {bool sub = false, double topInset = 0, bool badge = false}) {
      stage = 'header';
      final screen = Offset.zero & v.size;
      final s = sOf(v);
      final wm = find.byType(AlfitWordmark).evaluate().toList();
      need(wm.length == 1, '로고 수 ${wm.length}');
      final logoEl = wm.first;
      final headerEl = nearest(logoEl, (w) => w is Container)!;
      final contentEl = nearest(logoEl, (w) => w is LayoutBuilder)!;
      final rowEl = nearest(logoEl, (w) => w is Row)!;
      final header = rectOf(headerEl), content = rectOf(contentEl), row = rectOf(rowEl), logo = rectOf(logoEl);
      final bellIcon = find.descendant(of: fe(headerEl), matching: find.byIcon(Icons.notifications_outlined)).evaluate().toList();
      need(bellIcon.length == 1, '알림 아이콘 수 ${bellIcon.length}');
      final bellEl = nearest(bellIcon.first, (w) => w is InkWell)!;
      final bell = rectOf(bellEl);
      final nameEl = one('$name님').evaluate().first;
      final heroEl = one('오늘도, 내 일정에 맞게').evaluate().first;
      final dateEl = one('11월 13일 금요일').evaluate().first;
      final nameR = rectOf(nameEl), heroR = rectOf(heroEl), dateR = rectOf(dateEl);
      final strip = find.byWidgetPredicate((w) => w is Semantics && w.properties.label == '일할 날짜 선택').evaluate().toList();
      final stripTop = strip.isEmpty ? null : rectOf(strip.first).top;
      final safe = find.descendant(of: find.byType(UserHomeScreen), matching: find.byType(SafeArea)).evaluate().first;
      final safePad = (safe.renderObject! as RenderPadding).padding.resolve(TextDirection.ltr);
      final semData = t.getSemantics(fe(logoEl)).getSemanticsData();
      final logoSem = find.bySemanticsLabel('ALfit').evaluate().length;
      final inkEls = find.descendant(of: fe(logoEl), matching: find.byType(CustomPaint)).evaluate().toList();
      final ink = inkEls.isEmpty ? null : rectOf(inkEls.first);
      final rec = {'phase': phase, 'cond': cond, 's': s, 'gutter': gutterOf(v), 'header': rl(header), 'content': rl(content), 'row': rl(row),
        'logo': rl(logo), 'bell': rl(bell), 'name': rl(nameR), 'hero': rl(heroR), 'date': rl(dateR), 'stripTop': stripTop,
        'rowTopGap': row.top - header.top, 'metaGap': nameR.top - content.bottom, 'nameToHero': heroR.top - nameR.bottom,
        'heroToDate': dateR.top - heroR.bottom, 'dateToStrip': stripTop == null ? null : stripTop - dateR.bottom,
        'centerDiff': (logo.center.dy - bell.center.dy).abs(), 'safeTop': safePad.top, 'logoSemLabel': semData.label,
        'logoSemImage': semData.flagsCollection.isImage, 'logoSemCount': logoSem, 'ink': ink == null ? null : rl(ink)};
      _out('D306-HEADER ${jsonEncode(rec)}');
      if (topInset > 0) need(near(safePad.top, topInset, _kTol) && near(header.top, topInset, _kTol), 'SafeArea 실제 inset ${safePad.top}/머리 ${header.top}');
      // [r3c L2] 머리 위 8 → 0. 잉크 top 일반식 = 행 top + (실제 행 높이 − 28)/2 + 2 — 행 48·배너 숨김이면 SafeArea top + 12, inset 24 면 36.
      check(near(row.top - header.top, 0, _kTol), 'S-H 행동행 위 − 머리 시작 = 0(L2)', row.top - header.top);
      if (topInset > 0) check(near(row.top, topInset, _kTol), 'S-H F2i 행동행 위 = inset', row.top);
      final inkTopWant = row.top + (row.height - 28) / 2 + 2;
      check(ink != null && near(ink.top, inkTopWant, _kTol), 'S-H 잉크 top = 행 top + (행높이−28)/2 + 2', [ink?.top, inkTopWant, row.height]);
      if (near(row.height, 48, _kTol)) {
        check(ink != null && near(ink.top, safePad.top + 12, _kTol), 'S-H 행 48 잉크 top = SafeArea + 12', [ink?.top, safePad.top]);
      }
      check(ink != null && near(ink.width, 24 * 2558.55 / 794.8, _kTol), 'S-H 잉크 폭 = 24×2558.55/794.8', ink?.width);
      check(near(logo.left, gutterOf(v), _kTol) && near(logo.left, nameR.left, _kTol), 'S-H 로고 왼쪽 = gutter = 이름 왼쪽', [logo.left, nameR.left]);
      check(logo.width >= 84 - _kEps && logo.height >= 28 - _kEps && semData.label == 'ALfit' && semData.flagsCollection.isImage && logoSem == 1,
          'S-H 로고 slot ≥84×28·이미지 의미 1', [logo.width, logo.height, logoSem]);
      check(ink != null && near(ink.height, 24, _kTol), 'S-H 로고 잉크 24(slot 과 분리)', ink == null ? null : rl(ink));
      check(bell.width >= 48 - _kEps && bell.height >= 48 - _kEps && (logo.center.dy - bell.center.dy).abs() <= 0.5, 'S-H 알림 48·세로 중심',
          [bell.width, bell.height, (logo.center.dy - bell.center.dy).abs()]);
      check(near(nameR.top - content.bottom, 8, _kTol), 'S-H 마지막 머리 줄 → 이름 = 8', nameR.top - content.bottom);
      check(near(heroR.top - nameR.bottom, 4, _kTol) && near(dateR.top - heroR.bottom, 4, _kTol), 'S-H 이름→큰머리 4·큰머리→날짜 4',
          [heroR.top - nameR.bottom, dateR.top - heroR.bottom]);
      fullText(nameEl, '$name님', '이름');
      visHit(nameEl, '이름', screen, receiver: nameEl);
      if (badge) badgeCheck(header, row, ink, screen, safePad.top);
      if (sub) {
        final opts = <Map<String, Object?>>[];
        Element? stackEl;
        for (final l in const ['지원자', '관리자']) {
          final le = one(l, within: fe(headerEl)).evaluate().first;
          final rcv = nearest(le, (w) => w is GestureDetector || w is InkWell)!;
          final rr = rectOf(rcv);
          opts.add({'label': l, 'receiver': rl(rr)});
          check(rr.width >= 48 - _kEps && rr.height >= 48 - _kEps, 'S-H 토글 $l receiver ≥48×48', rl(rr));
          stackEl ??= nearest(le, (w) => w is Stack);
        }
        need(stackEl != null, '토글 Stack 없음');
        final st = stackEl!;
        final toggle = rectOf(st);
        final sameLine = identical(nearest(st, (w) => w is Row), rowEl);
        final need0 = logo.width + 8 * s + toggle.width + 8 * s + 48;
        final expectSame = content.width >= need0;
        final boundary = (content.width - need0).abs() <= 0.5;
        _out('D306-TOGGLE ${jsonEncode({'phase': phase, 'cond': cond, 'toggle': rl(toggle), 'contentW': content.width, 'need': need0,
          'sameLine': sameLine, 'expectSame': expectSame, 'boundary': boundary, 'opts': opts})}');
        check(boundary || sameLine == expectSame, 'S-H 토글 배치 = need 식', [sameLine, expectSame]);
        check(v.id == 'W' ? sameLine : !sameLine, 'S-H 토글 W 같은 줄 / B 다음 줄', sameLine);
      }
    }

    // CTA(ElevatedButton) — 색·시각 높이·실 receiver
    void ctaCheck(String label, _V v, {required bool primary}) {
      stage = 'cta';
      final screen = Offset.zero & v.size;
      final le = one(label).evaluate().first;
      final be = nearest(le, (w) => w is ElevatedButton)!;
      final style = (be.widget as ElevatedButton).style;
      final bg = style?.backgroundColor?.resolve(<WidgetState>{});
      final fg = style?.foregroundColor?.resolve(<WidgetState>{});
      final shape = style?.shape?.resolve(<WidgetState>{});
      final side = shape is OutlinedBorder ? shape.side : null;
      final mat = find.descendant(of: fe(be), matching: find.byType(Material)).evaluate().first;
      final visual = rectOf(mat), outer = rectOf(be);
      _out('D306-CTA ${jsonEncode({'phase': phase, 'cond': cond, 'label': label, 'bg': hex(bg), 'fg': hex(fg), 'text': hex(colorOf(le)),
        'side': side == null ? null : hex(side.color), 'sideStyle': side?.style.name, 'visual': rl(visual), 'outer': rl(outer)})}');
      if (primary) {
        check(bg == AppColors.brand && fg == Colors.white, 'CTA $label brand 채움·흰 글자', [hex(bg), hex(fg)]);
      } else {
        check(bg == Colors.white && fg == AppColors.grey600 && colorOf(le) == AppColors.grey600 && side?.color == AppColors.border &&
            side?.style == BorderStyle.solid, 'CTA $label 흰 바탕·grey600·border', [hex(bg), hex(fg), hex(side?.color)]);
      }
      check(visual.height >= 52 - _kEps, 'CTA $label 시각 높이 ≥52', visual.height);
      check(outer.width >= 48 - _kEps && outer.height >= 48 - _kEps, 'CTA $label receiver ≥48×48', rl(outer));
      fullText(le, label, 'CTA $label');
      visHit(be, 'CTA $label', screen);
    }

    // 진행 라벨·막대(F1·F5) — 오늘 약속 카드(CTA ElevatedButton 이 같은 Column 에 있는) 안의 막대 하나
    void progressCheck(Color want, String what) {
      stage = 'progress';
      final lpi = find.byType(LinearProgressIndicator).evaluate().where((e) {
        final col = nearest(e, (x) => x is Column);
        return col != null && find.descendant(of: fe(col), matching: find.byWidgetPredicate((x) => x is ElevatedButton)).evaluate().isNotEmpty;
      }).toList();
      need(lpi.length == 1, '오늘 약속 진행 막대 수 ${lpi.length}');
      final w = lpi.first.widget as LinearProgressIndicator;
      final col = nearest(lpi.first, (x) => x is Column)!;
      final lr = rectOf(lpi.first);
      Element? label0;
      for (final r in find.descendant(of: fe(col), matching: find.byType(RichText)).evaluate()) {
        final rr = rectOf(r);
        final cur = label0;
        if (rr.bottom <= lr.top + 0.5 && (cur == null || rr.bottom > rectOf(cur).bottom)) label0 = r;
      }
      need(label0 != null, '진행 라벨 없음');
      final label = label0!;
      _out('D306-PROGRESS ${jsonEncode({'phase': phase, 'cond': cond, 'label': plainOf(label), 'labelColor': hex(colorOf(label)),
        'bar': hex(w.color), 'barBg': hex(w.backgroundColor)})}');
      check(colorOf(label) == want, '$what 진행 라벨 색', [plainOf(label), hex(colorOf(label))]);
      if (want == AppColors.brand) {
        check(w.color == AppColors.brand && w.backgroundColor == AppColors.brandSurface, 'S-PROG 막대 brand/brandSurface',
            [hex(w.color), hex(w.backgroundColor)]);
      }
    }

    // 경력 링크(F1 `근무 기록 보기`, F3 `일자리 찾기`) — brand·receiver 높이 ≥48
    Element careerCheck(Element le, String label, _V v) {
      stage = 'career';
      final screen = Offset.zero & v.size;
      final rcv = nearest(le, (w) => w is GestureDetector)!;
      final rr = rectOf(rcv);
      _out('D306-CAREER ${jsonEncode({'phase': phase, 'cond': cond, 'label': label, 'color': hex(colorOf(le)), 'receiver': rl(rr)})}');
      check(colorOf(le) == AppColors.brand, 'S-CAREER $label brand', hex(colorOf(le)));
      check(rr.height >= 48 - _kEps, 'S-CAREER $label receiver 높이 ≥48', rr.height);
      visHit(le, 'S-CAREER $label', screen, receiver: rcv);
      return rcv;
    }

    final sw = Stopwatch()..start();
    try {
      clockGuard('start');
      need(vqEnabled, 'PNG 캡처 비활성(DU1_VQ_PHASE 없음)');
      _out('D306-ENV ${jsonEncode({'phase': phase, 'pinDay': dayArg, 'realNow': DateTime.now().toIso8601String(), 'kst': kstNow().toIso8601String(),
        'clock': _clock.toIso8601String(), 'today': _today.toIso8601String(), 'theme': 'RoleTheme.workerTheme', 'locale': 'ko_KR',
        'dpr': 1.0, 'boldText': false, 'C': '$_kC', 'fonts': 'NotoSansKR Regular+Bold(Roboto 별칭)·FlutterTest=Regular·MaterialIcons(SDK)'})}');

      // ═══ F1 W/B — 오늘 13:00 출근 전(계약 완료)·긴 이름·근무 이력 3 ═══
      for (final v in const [_w, _b]) {
        final calls = <String, int>{};
        final today = _app('t1', _day(0));
        await open('F1_${v.id}', v, _Worker(displayName: _longName, workDays: 3),
            reads(calls: calls, apps: [today], contracts: [checkInContractFor(today)]), unread1: v.id == 'B');
        headerCheck(v, _longName, badge: v.id == 'B');
        await png('origin', v);
        progressCheck(AppColors.brand, 'S-PROG');
        final cta = one('출근하기').evaluate().first;
        await reach(nearest(cta, (w) => w is ElevatedButton)!, 'CTA 출근하기', Offset.zero & v.size);
        ctaCheck('출근하기', v, primary: true);
        final rec = one('근무 기록 보기').evaluate().first;
        await reach(nearest(rec, (w) => w is GestureDetector)!, '근무 기록 보기', Offset.zero & v.size);
        careerCheck(rec, '근무 기록 보기', v);
        await teardown();
      }

      // ═══ [r3c] F1_N — 320×640·1.0(좁은 화면·정상 글씨) 원점 머리 표본 1장. reach·tap·route·text 0, 배지 입력 unread 1 ═══
      {
        final v = _n;
        final calls = <String, int>{};
        final today = _app('t1', _day(0));
        await open('F1_N', v, _Worker(displayName: _longName, workDays: 3),
            reads(calls: calls, apps: [today], contracts: [checkInContractFor(today)]), unread1: true);
        headerCheck(v, _longName, badge: true);
        await png('origin', v);
        await teardown();
      }

      // ═══ F2 W/B — SubAdmin(지원자 모드)·긴 이름 ═══
      for (final v in const [_w, _b]) {
        final calls = <String, int>{};
        final subCalls = <String>[];
        await open('F2_${v.id}', v, _Sub(calls: subCalls), reads(calls: calls));
        headerCheck(v, _longName, sub: true);
        await png('origin', v);
        need(subCalls.isEmpty, 'SubAdmin 전환 호출 $subCalls');
        await teardown();
      }

      // ═══ F2i W — F2 + 실제 상단 inset 24(배너 없음) ═══
      {
        final calls = <String, int>{};
        await open('F2i_W', _w, _Sub(calls: <String>[]), reads(calls: calls), topInset: 24);
        headerCheck(_w, _longName, sub: true, topInset: 24);
        await teardown();
      }

      // ═══ F3 W/B — 초대 2건 + 연장 제안 1건(긴 사업장)·근무 이력 0 ═══
      for (final v in const [_w, _b]) {
        final screen = Offset.zero & v.size;
        final s = sOf(v);
        final calls = <String, int>{};
        await open('F3_${v.id}', v, _Worker(displayName: '김근로', workDays: 0),
            reads(calls: calls, apps: [
              _app('inv1', _day(4), status: AppStatus.invited),
              _app('inv2', _day(5), status: AppStatus.invited),
            ], proposals: [_proposal()]));
        await png('origin', v);
        // S-REN
        stage = 'renewal';
        final start = FormatHelper.toKstDate(_proposal().effectiveStart);
        final end = FormatHelper.toKstDate(_proposal().effectiveEnd);
        final renSub = '$_longBiz · ${start.month}/${start.day}~${end.month}/${end.day}';
        final rt = one('계약 연장 제안').evaluate().first;
        final rcard = nearest(rt, (w) => w is Container && w.decoration is BoxDecoration && (w.decoration! as BoxDecoration).border != null)!;
        await reach(rcard, '연장 카드', screen);
        final rs = one(renSub, within: fe(rcard)).evaluate().first;
        final ra = one('확인하기', within: fe(rcard)).evaluate().first;
        final rcircle = find.descendant(of: fe(rcard), matching: find.byWidgetPredicate((w) => w is Container &&
            w.decoration is BoxDecoration && (w.decoration! as BoxDecoration).shape == BoxShape.circle)).evaluate().toList();
        final rcColor = rcircle.length == 1 ? ((rcircle.first.widget as Container).decoration! as BoxDecoration).color : null;
        final rdeco = (rcard.widget as Container).decoration! as BoxDecoration;
        final cardBg = _over(rdeco.color ?? Colors.white, Colors.white);
        final subColor = colorOf(rs) ?? Colors.black;
        final ratio = _contrast(_over(subColor, cardBg), cardBg);
        final inner = find.descendant(of: fe(rcard), matching: find.byType(LayoutBuilder)).evaluate().toList();
        final titleR = rectOf(rt), subR = rectOf(rs), actR = rectOf(ra);
        final bodyBottom = titleR.bottom > subR.bottom ? titleR.bottom : subR.bottom;
        final stacked = actR.top >= bodyBottom - 0.01;
        // 기대 배치(독립 측정): 본문 남는 폭 = 안쪽 폭 − 아이콘 − 12s − 8s − 행동 한 줄 폭, 필요 폭 = 공백으로 나눈 한 단위 최대 폭
        double unitMax(Element e) {
          final p = e.renderObject! as RenderParagraph;
          var mx = 0.0;
          for (final u in p.text.toPlainText(includeSemanticsLabels: false).split(' ')) {
            if (u.isEmpty) continue;
            final tp = TextPainter(text: TextSpan(text: u, style: p.text.style), textDirection: p.textDirection, textScaler: p.textScaler,
                locale: p.locale, textWidthBasis: p.textWidthBasis, textHeightBehavior: p.textHeightBehavior, maxLines: 1)
              ..layout();
            if (tp.maxIntrinsicWidth > mx) mx = tp.maxIntrinsicWidth;
            tp.dispose();
          }
          return mx;
        }

        String? expectLay;
        Map<String, Object?> layRec = {};
        if (inner.isNotEmpty) {
          final innerW = rectOf(inner.first).width;
          final iconW = rcircle.isEmpty ? 0.0 : rectOf(rcircle.first).width;
          final actW = (ra.renderObject! as RenderParagraph).getMaxIntrinsicWidth(double.infinity);
          final needW = math.max(unitMax(rt), unitMax(rs));
          final inlineBody = innerW - iconW - 12 * s - 8 * s - actW;
          final ok = inlineBody >= needW && inlineBody >= innerW * 0.5;
          final bnd = (inlineBody - needW).abs() <= 0.5 || (inlineBody - innerW * 0.5).abs() <= 0.5;
          expectLay = bnd ? 'boundary' : (ok ? 'inline' : 'stacked');
          layRec = {'innerW': innerW, 'iconW': iconW, 'actW': actW, 'need': needW, 'inlineBody': inlineBody};
        }
        _out('D306-RENEWAL ${jsonEncode({'phase': phase, 'cond': cond, 'circle': hex(rcColor), 'action': hex(colorOf(ra)), 'sub': hex(subColor),
          'cardBg': hex(cardBg), 'contrast': ratio, 'layout': stacked ? 'stacked' : 'inline', 'expect': expectLay, ...layRec,
          'title': rl(titleR), 'subRect': rl(subR), 'actionRect': rl(actR)})}');
        check(rcColor == AppColors.brand && colorOf(ra) == AppColors.brand, 'S-REN 원·행동 brand', [hex(rcColor), hex(colorOf(ra))]);
        fullText(rt, '계약 연장 제안', 'S-REN 제목');
        fullText(rs, renSub, 'S-REN 부제');
        check(ratio >= 4.5, 'S-REN 부제 대비 ≥4.5', ratio);
        check(expectLay != null && (expectLay == 'boundary' || expectLay == (stacked ? 'stacked' : 'inline')), 'S-REN 배치 = _taskCardRow 규칙',
            [expectLay, stacked]);
        visHit(rt, 'S-REN 제목', screen, receiver: nearest(rcard, (w) => w is GestureDetector || w is InkWell));
        visHit(rs, 'S-REN 부제', screen, receiver: nearest(rcard, (w) => w is GestureDetector || w is InkWell));
        // S-INV
        stage = 'invite';
        const invTitle = '업무 초대가 2건 있어요';
        const invSub = '초대 후 24시간과 근무 시작 중 빠른 때까지 수락할 수 있어요';
        final it = one(invTitle).evaluate().first;
        final card = nearest(it, (w) => w is Container)!;
        await reach(card, '초대 카드', screen);
        final deco = (card.widget as Container).decoration as BoxDecoration?;
        final border = deco?.border is Border ? (deco!.border! as Border).top.color : null;
        final circles = find.descendant(of: fe(card), matching: find.byWidgetPredicate((w) => w is Container &&
            w.decoration is BoxDecoration && (w.decoration! as BoxDecoration).shape == BoxShape.circle)).evaluate().toList();
        final circleColor = circles.length == 1 ? ((circles.first.widget as Container).decoration! as BoxDecoration).color : null;
        final mail = find.descendant(of: fe(card), matching: find.byIcon(Icons.mail_outlined)).evaluate().toList();
        final chev = find.descendant(of: fe(card), matching: find.byIcon(Icons.chevron_right)).evaluate().toList();
        final ise = one(invSub, within: fe(card)).evaluate().first;
        final rcv = nearest(card, (w) => w is GestureDetector || w is InkWell)!;
        _out('D306-INVITE ${jsonEncode({'phase': phase, 'cond': cond, 'bg': hex(deco?.color), 'border': hex(border), 'gradient': deco?.gradient != null,
          'shadow': (deco?.boxShadow ?? const []).length, 'circle': hex(circleColor), 'mail': mail.length == 1 ? hex((mail.first.widget as Icon).color) : null,
          'chevron': chev.length == 1 ? hex((chev.first.widget as Icon).color) : null, 'title': [hex(colorOf(it)), styleOf(it)?.fontSize, styleOf(it)?.fontWeight?.value],
          'sub': [hex(colorOf(ise)), styleOf(ise)?.fontSize], 'card': rl(rectOf(card)), 'receiver': rl(rectOf(rcv))})}');
        check(deco?.color == AppColors.brand.withValues(alpha: 0.07) && border == AppColors.brand.withValues(alpha: 0.32) &&
            deco?.gradient == null && (deco?.boxShadow ?? const []).isEmpty, 'S-INV 바탕 brand .07·테두리 .32·gradient/그림자 0');
        check(circleColor == AppColors.brand && mail.length == 1 && (mail.first.widget as Icon).color == Colors.white &&
            chev.length == 1 && (chev.first.widget as Icon).color == AppColors.brand, 'S-INV 원 brand·아이콘 흰색·꺾쇠 brand');
        check(colorOf(it) == AppColors.textPrimary && styleOf(it)?.fontSize == 15 && styleOf(it)?.fontWeight == FontWeight.w700,
            'S-INV 제목 textPrimary 15/700');
        check(colorOf(ise) == AppColors.textSecondary && styleOf(ise)?.fontSize == 13, 'S-INV 부제 textSecondary 13');
        fullText(it, invTitle, 'S-INV 제목');
        fullText(ise, invSub, 'S-INV 부제');
        check(rectOf(rcv).height >= 48 - _kEps, 'S-INV 카드 receiver 높이 ≥48', rectOf(rcv).height);
        visHit(it, 'S-INV 제목', screen, receiver: rcv);
        visHit(ise, 'S-INV 부제', screen, receiver: rcv);
        // 지원 준비 부제(있을 때만) — 속성색/실바탕 대비 ≥4.5
        final ready = richExact('지원 준비').evaluate().toList();
        if (ready.length == 1) {
          final rc = nearest(ready.first, (w) => w is Container && w.decoration is BoxDecoration && (w.decoration! as BoxDecoration).color != null)!;
          final bg = _over(((rc.widget as Container).decoration! as BoxDecoration).color!, Colors.white);
          final subs = find.descendant(of: fe(rc), matching: find.byType(RichText)).evaluate()
              .where((e) => styleOf(e)?.fontSize == 13 && plainOf(e) != '지원 준비' && !RegExp(r'^[0-9] / 2$').hasMatch(plainOf(e))).toList();
          for (final e in subs) {
            final cr = _contrast(_over(colorOf(e) ?? Colors.black, bg), bg);
            _out('D306-READY ${jsonEncode({'phase': phase, 'cond': cond, 'text': plainOf(e), 'color': hex(colorOf(e)), 'bg': hex(bg), 'contrast': cr})}');
            check(cr >= 4.5, 'S-부제 지원 준비 대비 ≥4.5', cr);
          }
        }
        // S-CAREER(빈 상태): 설명 textSecondary + `일자리 찾기` brand·48·물리 탭 → switchToTab:1
        //   같은 문구가 약속 없음 카드(OutlinedButton)에도 있으므로 설명과 같은 Column 안의 링크만 쓴다.
        final desc = one('근무를 마치면 기록이 쌓여요').evaluate().first;
        final careerCol = nearest(desc, (w) => w is Column)!;
        final findLink = one('일자리 찾기', within: fe(careerCol)).evaluate().first;
        await reach(nearest(findLink, (w) => w is GestureDetector)!, '일자리 찾기', screen);
        check(colorOf(desc) == AppColors.textSecondary, 'S-CAREER 설명 textSecondary', hex(colorOf(desc)));
        final linkRcv = careerCheck(findLink, '일자리 찾기', v);
        stage = 'careerTap';
        final before = List<String>.of(scopeLog);
        need(hitAt(rectOf(linkRcv).center, linkRcv), '일자리 찾기 receiver 중심 hit 아님');
        nTap++;
        budget();
        await t.tapAt(rectOf(linkRcv).center);
        guard('tap:일자리 찾기');
        await frames(4, 'careerTap');
        need(scopeLog.length == before.length + 1 && scopeLog.last == 'switchToTab:1', '일자리 찾기 → switchToTab:1 아님 $scopeLog');
        await teardown();
      }

      // ═══ F4 W/B — 지원·근태 조회 실패 + 서류 보완 조회 실패(DocumentCorrectionSurface.failed) ═══
      for (final v in const [_w, _b]) {
        final screen = Offset.zero & v.size;
        final calls = <String, int>{};
        await open('F4_${v.id}', v, _Worker(displayName: '김근로', workDays: 3),
            reads(calls: calls, appsFail: () => true, attsFail: true, corrections: DocumentCorrectionSurface.failed));
        stage = 'retry';
        const composite = '이번 달 근무 기록을 불러오지 못했어요 · 다시 시도';
        final singles = richExact('다시 시도').evaluate().toList();
        final comp = richExact(composite).evaluate().toList();
        _out('D306-RETRY-COUNT ${jsonEncode({'phase': phase, 'cond': cond, 'singles': singles.length, 'composite': comp.length, 'calls': calls})}');
        need(singles.length == 4 && comp.length == 1, 'F4 단독 다시 시도 4·수입 복합 1 아님 ${singles.length}/${comp.length}');
        await png('origin', v);
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

        Element correctionCard() {
          final ct = one('서류 요청을 확인하지 못했어요').evaluate().first;
          return nearest(ct, (w) => w is Container && w.decoration is BoxDecoration && (w.decoration! as BoxDecoration).color == AppColors.grey100)!;
        }

        // 위에서 아래 순서로 도달(되돌림 drag 0). 매 회 다시 찾는다(서류 카드 재조회가 그 부분을 다시 그린다).
        var corrTapped = false;
        for (var i = 0; i < 5; i++) {
          final all = [...richExact('다시 시도').evaluate(), ...richExact(composite).evaluate()]
            ..sort((a, b) => rectOf(a).top.compareTo(rectOf(b).top));
          need(all.length == 5, 'F4 재시도 5곳 유지 아님 ${all.length}');
          final e = all[i];
          final label = plainOf(e);
          final appBox = nearest(one('지원 현황을 불러오지 못했어요').evaluate().first, (w) => w is Column)!;
          final ccard = correctionCard();
          final ctx = label == composite ? 'income' : (under(e, appBox) ? 'applications' : (under(e, ccard) ? 'correction' : 'card'));
          final rcv = nearest(e, (w) => w is GestureDetector) ?? e;
          // [r3] 목표영역 = 이 단계가 단언하는 영역: correction 은 빈 곳 탭(카드 위 padding 띠)과 글자가 함께 든 카드,
          //   그 밖(card·applications·income)은 visHit 대상인 글자 e(receiver 크기는 따로 잰다 — 카드 전체 가시를 새 기준으로 더하지 않는다).
          await reach(ctx == 'correction' ? ccard : e, 'retry $label($ctx)', screen);
          final rr = rectOf(rcv);
          _out('D306-RETRY ${jsonEncode({'phase': phase, 'cond': cond, 'i': i, 'label': label, 'ctx': ctx, 'color': hex(colorOf(e)), 'receiver': rl(rr)})}');
          check(colorOf(e) == AppColors.brand, 'S-RETRY $label($ctx) brand', hex(colorOf(e)));
          if (ctx == 'applications' || ctx == 'income') check(rr.height >= 48 - _kEps, 'S-RETRY $ctx receiver 높이 ≥48', rr.height);
          visHit(e, 'S-RETRY $label($ctx)', screen, receiver: rcv);
          if (ctx == 'correction') {
            // 서류 카드 글자 밖 내부 빈 곳(위 padding 띠) 물리 탭 → documentCorrections +1(after 단언, before 기록)
            stage = 'correctionTap';
            final cr = rectOf(ccard);
            final pt = Offset(cr.center.dx, cr.top + 3);
            final onText = find.descendant(of: fe(ccard), matching: find.byType(RichText)).evaluate().any((x) => rectOf(x).contains(pt));
            need(cr.contains(pt) && !onText, '서류 카드 빈 곳 좌표 아님 $pt');
            final c0 = calls['corr'] ?? 0;
            nTap++;
            budget();
            await t.tapAt(pt);
            guard('tap:서류 카드 빈 곳');
            await frames(6, 'correctionTap');
            final c1 = calls['corr'] ?? 0;
            _out('D306-CORR-TAP ${jsonEncode({'phase': phase, 'cond': cond, 'point': [pt.dx, pt.dy], 'card': rl(cr), 'before': c0, 'after': c1,
              'checking': richExact('확인 중').evaluate().length})}');
            check(c1 == c0 + 1, 'S-RETRY 서류 카드 빈 곳 탭 → 보완 읽기 +1', [c0, c1]);
            corrTapped = true;
            stage = 'retry';
          }
        }
        need(corrTapped, 'F4 서류 카드 재시도를 만나지 못함');
        await teardown();
      }

      // ═══ F5 W — 오늘 근무 출퇴근 완료 ═══
      {
        final v = _w;
        final calls = <String, int>{};
        final today = _app('d1', _day(0), start: '06:00', end: '09:00');
        await open('F5_W', v, _Worker(displayName: '김근로', workDays: 3),
            reads(calls: calls, apps: [today], atts: [_doneAtt()], contracts: [checkInContractFor(today)]));
        await png('origin', v);
        progressCheck(AppColors.successDark, 'S-DONE');
        final cta = one('출퇴근 기록 보기').evaluate().first;
        await reach(nearest(cta, (w) => w is ElevatedButton)!, 'CTA 출퇴근 기록 보기', Offset.zero & v.size);
        ctaCheck('출퇴근 기록 보기', v, primary: false);
        await teardown();
      }

      // ═══ F7 W — 첫 로드 성공 → resume 재로드에서 지원 조회 실패(stale) ═══
      {
        final v = _w;
        final screen = Offset.zero & v.size;
        final calls = <String, int>{};
        var failNow = false;
        await open('F7_W', v, _Worker(displayName: '김근로', workDays: 3),
            reads(calls: calls, appsFail: () => failNow, apps: [
              _app('c1', _day(2), confirmedAt: _day(-2)),
              _app('p1', _day(3), status: AppStatus.pending),
            ]));
        stage = 'preResume';
        Map<String, String> statVals() {
          final lab = one('검토 중').evaluate().first;
          final rowEl = nearest(lab, (w) => w is Row)!;
          final out = <String, String>{};
          for (final l in const ['검토 중', '확정', '계약 대기']) {
            final le = one(l, within: fe(rowEl)).evaluate().first;
            final col = nearest(le, (w) => w is Column)!;
            final vals = find.descendant(of: fe(col), matching: find.byType(RichText)).evaluate().map(plainOf).where((x) => x != l).toList();
            need(vals.length == 1, '요약 $l 값 수 ${vals.length}');
            out[l] = vals.single;
          }
          return out;
        }

        int rows() => richExact('$_bizName · 피킹').evaluate().length;
        final pre = statVals();
        final preRows = rows();
        _out('D306-F7-PRE ${jsonEncode({'phase': phase, 'stats': pre, 'rows': preRows, 'calls': calls})}');
        need(pre['검토 중'] == '1' && pre['확정'] == '1' && preRows == 2, 'F7 사전 고정값(검토 중 1·확정 1·행 2) 아님 $pre/$preRows');
        need(richExact('최신 정보를 불러오지 못해 이전 내용을 보여드려요').evaluate().isEmpty, 'resume 전 stale 띠가 있음');
        failNow = true;
        final a0 = calls['apps'] ?? 0;
        stage = 'resume';
        nTap++; // resume dispatch 1(tap+dispatch 상한에 포함)
        budget();
        t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
        await frames(20, 'resume');
        need((calls['apps'] ?? 0) == a0 + 1, 'resume 재로드 1회 아님 ${calls['apps']}');
        stage = 'stale';
        final post = statVals();
        final postRows = rows();
        _out('D306-F7-POST ${jsonEncode({'phase': phase, 'stats': post, 'rows': postRows, 'calls': calls})}');
        need(jsonEncode(post) == jsonEncode(pre) && postRows == preRows, 'resume 실패 뒤 이전 숫자·카드가 바뀜 $post/$postRows');
        final txt = one('최신 정보를 불러오지 못해 이전 내용을 보여드려요').evaluate().first;
        final band = nearest(txt, (w) => w is Container && w.decoration is BoxDecoration)!;
        final rcv = nearest(band, (w) => w is GestureDetector)!;
        await reach(rcv, 'stale 띠', screen);
        final bdeco = (band.widget as Container).decoration! as BoxDecoration;
        final icon = find.descendant(of: fe(band), matching: find.byIcon(Icons.cloud_off_rounded)).evaluate().toList();
        final retry = one('다시 시도', within: fe(band)).evaluate().first;
        final rr = rectOf(rcv);
        _out('D306-STALE ${jsonEncode({'phase': phase, 'bg': hex(bdeco.color), 'icon': icon.length == 1 ? hex((icon.first.widget as Icon).color) : null,
          'retry': hex(colorOf(retry)), 'receiver': rl(rr)})}');
        check(bdeco.color == AppColors.background, 'S-STALE 띠 바탕 background', hex(bdeco.color));
        check(icon.length == 1 && (icon.first.widget as Icon).color == AppColors.warning, 'S-STALE 아이콘 warning');
        check(colorOf(retry) == AppColors.brand, 'S-STALE 다시 시도 brand', hex(colorOf(retry)));
        check(rr.height >= 48 - _kEps, 'S-STALE 띠 높이 ≥48', rr.height);
        fullText(txt, '최신 정보를 불러오지 못해 이전 내용을 보여드려요', 'S-STALE 설명');
        visHit(retry, 'S-STALE 다시 시도', screen, receiver: rcv);
        await png('stale', v);
        await teardown();
      }

      const want = 'F1_W|F1_B|F1_N|F2_W|F2_B|F2i_W|F3_W|F3_B|F4_W|F4_B|F5_W|F7_W';
      need(visited.join('|') == want, '방문 $visited');
      // [r3d] F1_N 포함 12장면 — 방문 12·C.mount 12 와 같은 종료 계수(단언 유지, 상한 확대 0)
      need(nMount == 12 && nPng == _kPng && nTap == 5 && nRoute == 0 && nText == 0, '실행량 ${counts()}');
      clockGuard('end');
      need(net.created == 0 && biz.isEmpty && errors.isEmpty && !live, '최종 상태 http=${net.created} business=$biz pending=${errors.length} live=$live');
      _out('D306-END ${jsonEncode({...counts(), 'visited': visited, 'http': net.created, 'business': biz, 'elapsedMs': sw.elapsedMilliseconds})}');
      completed = true;
    } finally {
      // 실패 정리 F ≤ (2,1,0,0,0,0,0): 아직 mount 돼 있으면 빈 mount 1 + pump 2(원 실패를 덮지 않게 need/stop 을 부르지 않는다).
      var cleanup = 'not-needed';
      var cleanMount = 0, cleanPump = 0;
      final cleanErrors = <String>[for (final e in errors) 'pending-before-cleanup ${e.cond}/${e.stage}#${e.pump}: ${e.first}'];
      errors.clear();
      if (live) {
        try {
          cleanMount++;
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
      _out('D306-FINAL ${jsonEncode({...counts(), 'outcome': completed ? 'completed' : 'failed', 'cleanup': cleanup, 'cleanupMount': cleanMount,
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
