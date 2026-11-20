// ignore_for_file: depend_on_referenced_packages
// [CP03] 지원자 홈 구조·문구 — 6상태 × W/B = 12사례.
//   지시: records/requests/DU_concept_CP03_start_2026-11-11.md, 구성 확정 requests/DU_concept_CP03_composition_decision_2026-11-11.md.
//   phase = DU1_VQ_PHASE=before|after(없으면 실패). before = 원본 관측 기록(사전 결손은 실패로 만들지 않는다), after = 확정 구성 단언.
//   기존 LOCAL 진입 재사용: UserHomeScreen(reads:, clock:) + UserTabScope 기록 대역(user_home_content_render_test.dart:425–435).
//   무쓰기·무네트워크: reads 메모리 fixture, Firebase 가짜 플랫폼. 새 위젯 타입은 import 하지 않는다(이름·Semantics 로 찾는다 — before 컴파일).
//   상태: today(B 오늘 출근 전) · newConfirm(A 새 확정) · empty(정상 약속 0 + 긴 이름) · overnight(자정 넘긴 미퇴근 + 오늘 약속)
//         · contract(계약 서명 필수 + 신분증 열람 요청) · fail(지원 조회 실패).
// [CP03 C1] records/requests/DU_concept_CP03_c1_followup_2026-11-11.md — after 12사례에 더한다:
//   의미 트리(ensureSemantics: label·button·enabled·selected·SemanticsAction.tap, 콜백 동일성) · 의미 action dispatch
//   (날짜 선택/해제 · 날짜 시트 열기/닫기 · `일정 보기` → 일정 탭) · B 마지막 날짜 가로 도달/receiver/hit ·
//   ID/미퇴근 카드 전문·줄상자·paint bounds·조상 clip·화면 안·겹침 0·receiver 중심 hit · 낱말/`님`/CTA 줄 위치.
//   상한: 사례 12 · 물리탭+의미 dispatch 24 · scroll/drag/ensureVisible 24 · pump+mount 800 · PNG 10쌍.
// [C1 r2] records/requests/DU_concept_CP03_c1_resume_2026-11-11.md — 시험 판정 수리만: tight 상자 세로 `⊂ 문단 높이` 를
//   실제 self clip(재현 TextPainter)·조상 활성 clip(정확 도형)·가시 프레임 viewport/화면 판정으로 바꾸고 수치를 먼저 남긴다.
//   긴 이름 원문 비교는 TextLayout.plain(표시 문자열). 홈·사례·fixture·배율·상한·PNG 배정 그대로.
// [C1 r3] records/requests/DU_concept_CP03_c1_r3_resume_2026-11-12.md — 가로 문단폭 비교만 U+0020 범위를 빼고(비공백 범위는
//   같은 문단에서 다시 selection 해 ±0.5), 원 raw 상자의 self/조상/viewport/화면 검사는 그대로. 상자·문자 범위 진단을 먼저 남긴다.
//   카드 배치 회귀: W 미퇴근/ID 같은 줄·W ID 제목 2줄, B 미퇴근/ID 행동 아래 오른쪽·본문이 안쪽 오른쪽까지·본문 ≥ 안쪽 폭 50%.
import 'dart:convert';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:flutter/foundation.dart';
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
import 'package:ALfit/models/core/business_model.dart';
import 'package:ALfit/models/core/employment_contract_model.dart';
import 'package:ALfit/models/core/id_card_access_request_model.dart';
import 'package:ALfit/models/core/legal_readiness.dart';
import 'package:ALfit/models/core/renewal_proposal_model.dart';
import 'package:ALfit/models/core/slot_model.dart';
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

import 'support/checkin_contract_fixture.dart';
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

const _biz = 'biz1';
const _bizName = '강남 물류센터';
const _longName = '응우옌 티 프엉 타오 쩐'; // CP01 긴 이름 표본(du_concept_cp01_header_test.dart:136)

/// 지원자 provider 대역(du_concept_cp01_header_test.dart:72–88 과 같은 게터 덮개). 이름만 사례별로 바꾼다.
class _Worker extends UserProvider {
  _Worker({this.displayName = '김근로'});
  final String displayName;
  @override
  UserModel? get currentUser => UserModel(
      uid: 'u1', username: 'u1', name: displayName, email: 'u1@alfit.local', role: UserRole.USER,
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

// ── 고정 시각(KST) — DU1_VQ_DATE 날의 10:00 (CP01 과 같은 산식) ──
final DateTime _clock = () {
  final k = vqNow().toUtc().add(const Duration(hours: 9));
  return DateTime.utc(k.year, k.month, k.day, 10).subtract(const Duration(hours: 9));
}();
final DateTime _today = FormatHelper.toKstDate(_clock);
DateTime _day(int o) => _today.add(Duration(days: o));
const _wd = ['월', '화', '수', '목', '금', '토', '일'];
String _kDate(DateTime d) => '${d.month}월 ${d.day}일 ${_wd[d.weekday - 1]}요일';

ApplicationModel _app(String id, DateTime workDate,
        {String status = AppStatus.confirmed, String start = '13:00', String end = '18:00', DateTime? confirmedAt}) =>
    ApplicationModel(
        id: id, toId: 'to_$id', uid: 'u1', businessId: _biz, businessName: _bizName, toTitle: '단기 공고',
        status: status, selectedWorkType: '피킹', startTime: start, endTime: end, wage: 12000, wageType: 'hourly',
        workDate: workDate, appliedAt: _day(-3), confirmedAt: confirmedAt);

BusinessModel _business() => BusinessModel(
    id: _biz, name: _bizName, ownerId: 'a1', businessNumber: '000-00-00000', address: '서울특별시 강남구 테헤란로 1',
    category: '물류', subCategory: '창고', isApproved: true, createdAt: _day(-200));

/// 자정 넘긴 근무 근태(user_home_content_render_test.dart:206–229 모양). 어제 22:00 KST 출근, 퇴근 없음.
AttendanceModel _overnightAtt() => AttendanceModel(
      id: 'att_n1',
      applicationId: 'n1',
      userId: 'u1',
      businessId: _biz,
      businessName: _bizName,
      workDate: _day(-1),
      workType: '피킹',
      status: AttendanceModel.statusPresent,
      wageStatus: AttendanceModel.wagePending,
      adminConfirmed: false,
      checkInAt: DateTime.utc(_day(-1).year, _day(-1).month, _day(-1).day, 13),
      checkOutAt: null,
      createdAt: _day(-1),
    );

IdCardAccessRequestModel _idRequest() => IdCardAccessRequestModel(
      id: 'req1',
      requesterId: 'admin1',
      requesterName: '박사장',
      requesterBusinessId: _biz,
      requesterBusinessName: _bizName,
      targetUserId: 'u1',
      targetUserName: '김근로',
      reason: IdCardAccessReason.incomeTax,
      status: IdCardAccessStatus.pending,
      requestedAt: _day(-1),
    );

UserHomeReads _reads(String state) {
  final today = _app('t1', _day(0));
  final List<ApplicationModel> apps;
  List<EmploymentContractModel> contracts = const [];
  List<IdCardAccessRequestModel> idReqs = const [];
  List<AttendanceModel> atts = const [];
  switch (state) {
    case 'today':
      apps = [today];
      contracts = [checkInContractFor(today)];
    case 'newConfirm':
      apps = [_app('a1', _day(2), start: '09:00', end: '18:00', confirmedAt: _clock.subtract(const Duration(hours: 1)))];
    case 'empty':
      apps = [_app('p1', _day(3), status: AppStatus.pending)];
    case 'overnight':
      apps = [_app('n1', _day(-1), start: '22:00', end: '06:00'), today];
      contracts = [checkInContractFor(today)];
      atts = [_overnightAtt()];
    case 'contract':
      apps = [today];
      contracts = [checkInContractFor(today, status: ContractStatus.pendingWorker)];
      idReqs = [_idRequest()];
    default: // fail
      apps = const [];
  }
  return UserHomeReads(
    slotsForTO: (_) async => const <SlotModel>[],
    myContracts: (_) async => contracts,
    myApplications: (_) async {
      if (state == 'fail') throw Exception('CP03 LOCAL 지원 조회 실패 fixture');
      return apps;
    },
    myMonthlyAttendances: ({required String userId, required int year, required int month}) async =>
        (year == _today.year && month == _today.month) ? atts : const <AttendanceModel>[],
    publishedTOs: () async => const [],
    pendingIdCardRequests: (_) async => idReqs,
    myRenewalProposals: () async => const <RenewalProposalModel>[],
    businessById: (_) async => _business(),
    invalidatePublishedTOsCache: () {},
    documentCorrections: () async => DocumentCorrectionSurface.empty,
    legalReadiness: () async => const LegalReadiness(status: LegalReadinessStatus.current),
  );
}

// 폰트(CP01 과 같은 등록)
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

// ── 실행량(C1 상한: 사례·mount 12 · 물리탭+의미 dispatch 24 · scroll/drag/ensureVisible 24 · pump+mount 800 · PNG 10쌍) ──
int _mounts = 0, _pumps = 0, _pngs = 0, _taps = 0, _scrolls = 0, _actions = 0;
final _cases = <String>{};
final _diag = Expando<String>('cp03-diag');

typedef _V = ({String id, Size size, double scale});
const _V _w = (id: 'W', size: Size(390, 844), scale: 1.0);
const _V _b = (id: 'B', size: Size(320, 640), scale: 2.0);

/// [C1 r2] 조상이 자식에게 실제로 거는 clip 의 정확 도형(그 조상 좌표). kind = rect | rrect | oval | unsupported.
///   oval 은 [rect] 에 내접한 타원이다. unsupported 는 정확 도형을 공개 API 로 알 수 없는 활성 clip(자동 통과 금지).
class _Clip {
  const _Clip(this.kind, this.type, {this.rect, this.rrect});
  final String kind;
  final String type;
  final Rect? rect;
  final RRect? rrect;
}

/// selection 상자 [r](clip 조상 좌표)가 clip 도형 안인가 — 허용 오차 0.5(기존 가로 단언과 같은 값).
///   rrect·oval 은 볼록 도형이라 네 모서리가 모두 안이면 상자 전체가 안이다(외접 사각형 비교로 대신하지 않는다).
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

/// 조상 [p] 가 자식 [c] 에 지금 거는 clip(없으면 null). 정확 도형을 공개 값으로 얻을 수 있는 형만 지원한다.
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
  // clip 할 수 있지만 활성 여부(넘침)를 공개하지 않는 형 — clipBehavior 가 켜져 있으면 미지원으로 실패시킨다.
  if (p is RenderWrap && p.clipBehavior != Clip.none) return _Clip('unsupported', '$type(넘침 비공개)');
  if (p is RenderAnimatedSize && p.clipBehavior != Clip.none) return _Clip('unsupported', '$type(넘침 비공개)');
  if (p is RenderFittedBox && p.clipBehavior != Clip.none) return _Clip('unsupported', '$type(넘침 비공개)');
  // SDK 가 clip 을 설명하는 형 — 사각 clip(Offset.zero & size)을 거는 형만 정확 사각으로 받는다.
  final a = p.describeApproximatePaintClip(c);
  if (a == null) return null;
  if (p is RenderFlex || p is RenderStack || p is RenderConstraintsTransformBox ||
      type == '_RenderSingleChildViewport' || type == '_RenderTheater') {
    return _Clip('rect', type, rect: a);
  }
  return _Clip('unsupported', '$type(근사 clip 만 공개)');
}

void main() {
  final phase = vqPhase ?? '';
  final env = Platform.environment;
  final meta = env['CP03_META'] ?? '';
  final after = phase == 'after';
  test('CP03 실행 조건', () {
    expect(phase == 'before' || phase == 'after', isTrue, reason: 'DU1_VQ_PHASE=before|after');
    expect(env['DU1_VQ_DATE'], '2026-11-11', reason: '고정 KST 날짜');
    expect((env['DU1_VQ_RUN'] ?? '').isNotEmpty, isTrue);
    expect((env['DU1_VQ_OUT'] ?? '').contains('cp03-worker-home'), isTrue);
    expect(meta.contains('runner='), isTrue, reason: 'CP03_META(runner SHA 포함)');
  });
  setUp(() => SharedPreferences.setMockInitialValues({
        'onboarding_completed_u1': true,
        'tour_completed_user_home': true,
      }));
  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
    await initializeDateFormatting('ko_KR');
    await _loadFonts();
  });

  Future<void> collecting(WidgetTester t, Future<void> Function(List<FlutterErrorDetails> errors) body) async {
    final errors = <FlutterErrorDetails>[];
    final prev = FlutterError.onError;
    FlutterError.onError = (d) {
      _diag[d] = TextTreeRenderer(wrapWidth: 400).render(d.toDiagnosticsNode(style: DiagnosticsTreeStyle.error));
      errors.add(d);
    };
    try {
      await body(errors);
    } finally {
      FlutterError.onError = prev;
    }
  }

  Future<void> settle(WidgetTester t, int n) async {
    for (var i = 0; i < n; i++) {
      await t.pump(const Duration(milliseconds: 100));
      _pumps++;
    }
  }

  Future<GlobalKey> open(WidgetTester t, String state, _V v, List<String> log, {String name = '김근로'}) async {
    final key = GlobalKey();
    t.view.physicalSize = v.size;
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    await t.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<UserProvider>.value(value: _Worker(displayName: name)),
        ChangeNotifierProvider<NotificationProvider>(create: (_) => NotificationProvider()),
      ],
      child: RepaintBoundary(
        key: key,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: RoleTheme.workerTheme,
          locale: const Locale('ko', 'KR'),
          supportedLocales: const [Locale('ko', 'KR'), Locale('en', 'US')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          builder: (ctx, child) =>
              MediaQuery(data: MediaQuery.of(ctx).copyWith(textScaler: TextScaler.linear(v.scale)), child: child!),
          home: UserTabScope(
            switchToTab: (i) => log.add('switchToTab:$i'),
            switchToTabWithDate: (i, d) => log.add('switchToTabWithDate:$i/${d.year}-${d.month}-${d.day}'),
            pendingJobDate: null,
            clearPendingJobDate: () {},
            pendingScheduleMonth: null,
            clearPendingScheduleMonth: () {},
            switchToScheduleNow: () => log.add('switchToScheduleNow'),
            child: UserHomeScreen(reads: _reads(state), clock: () => _clock),
          ),
        ),
      ),
    ));
    _mounts++;
    await settle(t, 25);
    return key;
  }

  // ── 찾기·측정(두 phase 공통 기록) ──
  /// 표시 문자열의 줄바꿈 제어문자를 뺀 원문으로 찾는다(keepWords 문구 포함).
  Finder plain(String s) => find.byWidgetPredicate((w) => w is Text && TextLayout.plain(w.data ?? '') == s);
  Finder semLabel(String s) =>
      find.byWidgetPredicate((w) => w is Semantics && w.properties.label == s);
  Finder semPrefix(String s) =>
      find.byWidgetPredicate((w) => w is Semantics && (w.properties.label ?? '').startsWith(s));
  RenderParagraph para(WidgetTester t, Finder text) =>
      t.renderObject<RenderParagraph>(find.descendant(of: text, matching: find.byType(RichText)).first);
  Map<String, Object?> textRec(WidgetTester t, String s) {
    final f = plain(s);
    final n = f.evaluate().length;
    if (n == 0) return {'text': s, 'count': 0};
    final r = t.getRect(f.first);
    final rp = para(t, f.first);
    final st = rp.text.style;
    return {
      'text': s, 'count': n, 'rect': [r.left, r.top, r.width, r.height], 'exceeded': rp.didExceedMaxLines,
      'maxLines': rp.maxLines, 'overflow': rp.overflow.name, 'scale': rp.textScaler.scale(10) / 10,
      'size': st?.fontSize, 'weight': st?.fontWeight?.value, 'color': st?.color?.toARGB32().toRadixString(16),
    };
  }

  bool hits(WidgetTester t, Finder f) {
    final ro = t.renderObject(f);
    final hit = HitTestResult();
    WidgetsBinding.instance.hitTestInView(hit, t.getRect(f).center, t.view.viewId);
    return hit.path.any((e) => identical(e.target, ro));
  }

  List<Map<String, Object?>> slots(WidgetTester t) {
    final f = find.byWidgetPredicate((w) => w.runtimeType.toString() == '_RhythmSlot');
    return [
      for (var i = 0; i < f.evaluate().length; i++)
        {
          'kind': ((t.widget(f.at(i)) as dynamic).kind as Object).toString().split('.').last,
          'rect': () {
            final r = t.getRect(f.at(i));
            return [r.left, r.top, r.width, r.height];
          }(),
        },
    ];
  }

  void judgeErrors(String id, List<FlutterErrorDetails> errs) {
    final lines = [
      for (final e in errs)
        '${e.exceptionAsString().split(String.fromCharCode(10)).first} @ ${RegExp(r'[A-Za-z_]+[.]dart:[0-9]+:[0-9]+').allMatches(_diag[e] ?? '').map((x) => x.group(0)).toSet().join(',')}',
    ];
    // ignore: avoid_print
    print('CP03-ERRORS $id ${jsonEncode(lines)}');
    if (after) expect(lines, isEmpty, reason: '$id 렌더 오류 0');
  }

  void log(String id, Map<String, Object?> m) {
    // ignore: avoid_print
    print('CP03-MEASURE $id ${jsonEncode(m)}');
  }

  // [C1] 세로 본문 스크롤(가장 바깥 아래 방향 Scrollable)과 B 날짜띠 가로 스크롤의 실제 offset.
  Finder vScroll() => find.byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.down);
  double vOffset(WidgetTester t) => t.state<ScrollableState>(vScroll().first).position.pixels;
  Rect viewRect(WidgetTester t) => t.getRect(vScroll().first);
  Object hOffset(WidgetTester t) {
    final h = find.descendant(of: semLabel('일할 날짜 선택'), matching: find.byType(Scrollable));
    return h.evaluate().isEmpty ? 'none(띠 균등 배치)' : t.state<ScrollableState>(h.first).position.pixels;
  }

  /// [C1] frame = offset0 | 도달 프레임 이름. offset 은 측정값을 그대로 적는다(도달 프레임을 offset0 이라 적지 않는다).
  Future<void> shot(WidgetTester t, GlobalKey key, String id, _V v, String fixture, {required String frame}) async {
    await vqCapture(t, key, id, conditions: {
      'id': id, 'phase': phase, 'fixture': fixture, 'viewport': '${v.size.width.toInt()}x${v.size.height.toInt()}', 'dpr': 1.0,
      'textScaler': v.scale, 'locale': 'ko_KR', 'clock': _clock.toIso8601String(), 'date': env['DU1_VQ_DATE'],
      'run': env['DU1_VQ_RUN'], 'meta': meta, 'frame': frame, 'offset': vOffset(t), 'hOffset': hOffset(t),
      'semantics': 'ensureSemantics 켬',
      'fonts': 'NotoSansKR Regular+Bold(Roboto 별칭) · FlutterTest=Regular · MaterialIcons(SDK)',
    });
    if (vqEnabled) _pngs++;
  }

  /// 세로 스크롤로 대상을 화면 안에 데려온다(programmatic, 스크롤 1회로 셈).
  Future<void> reach(WidgetTester t, Finder f) async {
    await t.ensureVisible(f.first);
    _scrolls++;
    await settle(t, 3);
  }

  Future<void> tapCenter(WidgetTester t, Finder f) async {
    await t.tapAt(t.getRect(f).center);
    _taps++;
    await settle(t, 4);
  }

  // ── [C1] 의미 트리 ──
  final ctl = RegExp('[${String.fromCharCode(0x2060)}${String.fromCharCode(0x200B)}${String.fromCharCode(0x00A0)}]');
  SemanticsNode node(WidgetTester t, Finder f) => t.semantics.find(f);

  /// 최종 의미 node 의 label·button·tap action(+ enabled·selected) — 위젯 label 존재·좌표 탭으로 대신하지 않는다.
  Map<String, Object?> expectNode(WidgetTester t, Finder f, String id,
      {required String label, required bool tap, bool? enabled, bool? selected}) {
    final d = node(t, f).getSemanticsData();
    expect(d.label, label, reason: '$id 의미 이름 원문(중복 0)');
    expect(ctl.hasMatch(d.label), isFalse, reason: '$id 의미 이름 제어문자 0');
    expect(d.flagsCollection.isButton, isTrue, reason: '$id button');
    expect(d.hasAction(SemanticsAction.tap), tap, reason: '$id SemanticsAction.tap ${tap ? '있음' : '없음'}');
    if (enabled != null) {
      expect(d.flagsCollection.hasEnabledState, isTrue, reason: '$id enabled 상태 있음');
      expect(d.flagsCollection.isEnabled, enabled, reason: '$id enabled=$enabled');
    }
    if (selected != null) expect(d.flagsCollection.isSelected, selected, reason: '$id selected=$selected');
    return {'label': d.label, 'tap': d.hasAction(SemanticsAction.tap), 'enabled': d.flagsCollection.isEnabled,
      'selected': d.flagsCollection.isSelected, 'hidden': d.flagsCollection.isHidden};
  }

  /// 의미 node 의 onTap 과 실제 GestureDetector 의 onTap 이 같은 콜백인가(목적지를 실행하지 않고 등록 동일성만).
  void expectSameCallback(WidgetTester t, Finder sem, String id, {required bool present}) {
    final sw = t.widget<Semantics>(sem);
    final gd = t.widget<GestureDetector>(find.descendant(of: sem, matching: find.byType(GestureDetector)).first);
    if (present) {
      expect(sw.properties.onTap, isNotNull, reason: '$id 의미 onTap');
      expect(sw.properties.onTap == gd.onTap, isTrue, reason: '$id 의미 onTap = GestureDetector onTap(같은 콜백)');
    } else {
      expect(sw.properties.onTap, isNull, reason: '$id 비활성 — 의미 onTap 없음');
      expect(gd.onTap, isNull, reason: '$id 비활성 — 탭 없음');
    }
  }

  /// 의미 action 실제 dispatch(SemanticsOwner.performAction) — 물리탭과 합쳐 상한 24.
  Future<void> dispatchTap(WidgetTester t, Finder f) async {
    final n = node(t, f);
    n.owner!.performAction(n.id, SemanticsAction.tap);
    _actions++;
    await settle(t, 4);
  }

  bool hitAt(WidgetTester t, Offset p, Finder receiver) {
    final ro = t.renderObject(receiver);
    final hit = HitTestResult();
    WidgetsBinding.instance.hitTestInView(hit, p, t.view.viewId);
    return hit.path.any((e) => identical(e.target, ro));
  }

  Rect gRect(RenderBox rb) => MatrixUtils.transformRect(rb.getTransformTo(null), Offset.zero & rb.size);
  List<double> rl(Rect r) => [r.left, r.top, r.width, r.height];

  // ── [C1 r2] selection bounds(tight) 와 실제 활성 clip ──
  String n2(double x) => x.toStringAsFixed(2);
  String rs(Rect r) => '[${n2(r.left)},${n2(r.top)},${n2(r.right)},${n2(r.bottom)}]';

  /// self clip 근거 — RenderParagraph 와 같은 공개 입력(span·정렬·방향·배율·maxLines·ellipsis·locale·strut·
  ///   textWidthBasis·textHeightBehavior)과 같은 layout 제약(softWrap=false 이고 ellipsis 가 아니면 maxWidth=∞)으로
  ///   TextPainter 를 다시 배치해 SDK 와 같은 식으로 넘침/자기 clip 을 판정한다(paragraph.dart:845·918). 쓰고 나서 dispose.
  Map<String, Object?> selfClip(RenderParagraph rp) {
    final tp = TextPainter(
      text: rp.text,
      textAlign: rp.textAlign,
      textDirection: rp.textDirection,
      textScaler: rp.textScaler,
      maxLines: rp.maxLines,
      ellipsis: rp.overflow == TextOverflow.ellipsis ? String.fromCharCode(0x2026) : null,
      locale: rp.locale,
      strutStyle: rp.strutStyle,
      textWidthBasis: rp.textWidthBasis,
      textHeightBehavior: rp.textHeightBehavior,
    );
    final c = rp.constraints;
    final maxW = (rp.softWrap || rp.overflow == TextOverflow.ellipsis) ? c.maxWidth : double.infinity;
    tp.layout(minWidth: c.minWidth, maxWidth: maxW);
    final ts = tp.size;
    final exceeded = tp.didExceedMaxLines;
    tp.dispose();
    final size = c.constrain(ts);
    final oh = size.height < ts.height || exceeded;
    final ow = size.width < ts.width;
    return {
      'placeholders': rp.firstChild != null,
      'constraints': '${n2(c.minWidth)}..${c.maxWidth.isFinite ? n2(c.maxWidth) : 'inf'} x ${n2(c.minHeight)}..${c.maxHeight.isFinite ? n2(c.maxHeight) : 'inf'}',
      'layoutMaxWidth': maxW.isFinite ? maxW : 'inf',
      'painter': [ts.width, ts.height],
      'constrained': [size.width, size.height],
      'paragraph': [rp.size.width, rp.size.height],
      'reproduced': (size.width - rp.size.width).abs() < 0.01 && (size.height - rp.size.height).abs() < 0.01,
      'overflowWidth': ow,
      'overflowHeight': oh,
      'exceeded': exceeded,
      'overflow': rp.overflow.name,
      'selfClip': (ow || oh) && rp.overflow != TextOverflow.visible,
    };
  }

  /// 조상 clip 사슬 — 모든 tight 상자를 각 조상 좌표로 옮겨 그 조상의 실제 활성 clip 도형과 대조한다.
  ///   [toRoot] = true(가시 프레임)면 scroll viewport 자신을 포함해 root 까지, false(도달 전 구조 확인)면 첫 viewport 앞에서 멈춘다.
  ///   미지원 clip·이동이 아닌 변환은 실패 문자열로 남긴다(자동 통과 0).
  ({List<Map<String, Object?>> chain, List<String> failures, String stop}) clipChain(
      RenderParagraph rp, List<TextBox> boxes, {required bool toRoot}) {
    final chain = <Map<String, Object?>>[];
    final failures = <String>[];
    var stop = 'root';
    RenderObject c = rp;
    RenderObject? p = rp.parent;
    while (p != null) {
      if (!toRoot && p is RenderAbstractViewport) {
        stop = 'viewport 앞(${p.runtimeType})';
        break;
      }
      final clip = _activeClip(p, c);
      if (clip != null) {
        final tr = MatrixUtils.getAsTranslation(rp.getTransformTo(p));
        if (clip.kind == 'unsupported') {
          failures.add('미지원 활성 clip ${clip.type}');
          chain.add({'type': clip.type, 'kind': clip.kind});
        } else if (tr == null) {
          failures.add('미지원 변환(이동 아님) ~${clip.type}');
          chain.add({'type': clip.type, 'kind': clip.kind, 'transform': 'non-translation'});
        } else {
          final shape = clip.rect ?? clip.rrect!.outerRect;
          String? bad;
          for (final b in boxes) {
            final r = b.toRect().shift(tr);
            if (!_inside(clip, r)) bad ??= rs(r);
          }
          chain.add({
            'type': clip.type, 'kind': clip.kind, 'shape': rs(shape),
            if (clip.rrect != null) 'radiusTL': [clip.rrect!.tlRadiusX, clip.rrect!.tlRadiusY],
            'translation': [tr.dx, tr.dy], 'ok': bad == null,
          });
          if (bad != null) failures.add('${clip.type} ${clip.kind} ${rs(shape)} 밖 상자 $bad');
        }
      }
      c = p;
      p = p.parent;
    }
    return (chain: chain, failures: failures, stop: stop);
  }

  /// 대상 낱말(공백으로 나눈 원문 낱말, `·` 제외)의 글자가 모두 같은 줄에 있는가 — 실제 줄상자(getBoxesForSelection).
  Map<String, Object?> expectWordsKept(RenderParagraph rp, String original, String id) {
    final disp = rp.text.toPlainText(includeSemanticsLabels: false);
    final idx = <int>[];
    for (var i = 0; i < disp.length; i++) {
      final c = disp.codeUnitAt(i);
      if (c != 0x2060 && c != 0x200B) idx.add(i);
    }
    final p = TextLayout.plain(disp);
    expect(p, original, reason: '$id 표시 원문 전문');
    final lines = <String, int>{};
    var from = 0;
    for (final w in original.split(' ')) {
      if (w.isEmpty || w == '·') continue;
      final at = p.indexOf(w, from);
      expect(at >= 0, isTrue, reason: '$id 낱말 $w');
      final tops = <double>[];
      for (var k = at; k < at + w.length; k++) {
        for (final b in rp.getBoxesForSelection(TextSelection(baseOffset: idx[k], extentOffset: idx[k] + 1))) {
          tops.add(b.top);
        }
      }
      final lo = tops.reduce((a, b) => a < b ? a : b), hi = tops.reduce((a, b) => a > b ? a : b);
      expect(hi - lo, lessThan(1.0), reason: '$id 낱말 `$w` 한 줄(음절 분절 0)');
      lines[w] = lo.round();
      from = at + w.length;
    }
    return lines;
  }

  /// 글자 전문·실제 배율·자연 높이 + selection bounds(tight).
  ///   [C1 r2] 가로: tight 상자 left/right ⊂ 문단 폭(±0.5) 유지. 세로: `상자 ⊂ 문단 높이` 는 쓰지 않는다 — SDK 는 넘침이 있을 때만
  ///   자기 clip 을 켜므로, self clip(재현 TextPainter)·조상 활성 clip(정확 도형)·(가시 프레임) viewport·화면으로 판정한다.
  ///   [onScreen] = false 는 도달 전 구조 확인(visibilityChecked=false, 첫 viewport 앞까지의 국소 clip 만).
  ///   수치는 단언 전에 `CP03-MEASURE <id>-bounds` 로 먼저 남긴다. 이것은 selection bounds 이고 잉크 픽셀 검증이 아니다.
  Map<String, Object?> expectFullText(WidgetTester t, Finder f, String original, _V v, String id, {bool onScreen = true}) {
    final rp = para(t, f);
    final disp = rp.text.toPlainText(includeSemanticsLabels: false);
    final boxes = rp.getBoxesForSelection(TextSelection(baseOffset: 0, extentOffset: disp.length));
    final finite = boxes.every((b) => b.left.isFinite && b.top.isFinite && b.right.isFinite && b.bottom.isFinite);
    double mn(double Function(TextBox) side) => boxes.map(side).reduce((a, b) => a < b ? a : b);
    double mx(double Function(TextBox) side) => boxes.map(side).reduce((a, b) => a > b ? a : b);
    final hasBoxes = boxes.isNotEmpty && finite;
    final sc = selfClip(rp);
    final cc = clipChain(rp, boxes, toRoot: onScreen);
    final g = gRect(rp);
    final toGlobal = rp.getTransformTo(null);
    final globalBoxes = [for (final b in boxes) MatrixUtils.transformRect(toGlobal, b.toRect())];
    final vr = viewRect(t);
    final intrinsic = rp.getMinIntrinsicHeight(rp.size.width);
    // [C1 r3] 가로 문단폭 비교용 문자 범위 — 실제 표시 문자열을 U+0020 경계로 나눈 최대 연속 범위(UTF-16 offset).
    //   같은 문단·같은 layout 에서 범위별로 selection 한다(문자열을 바꾸거나 새로 layout 하지 않는다).
    final ranges = <({int start, int end, bool space, List<TextBox> boxes})>[];
    var rStart = 0;
    for (var i = 1; i <= disp.length; i++) {
      final cut = i == disp.length || (disp.codeUnitAt(i) == 0x20) != (disp.codeUnitAt(rStart) == 0x20);
      if (cut) {
        ranges.add((
          start: rStart,
          end: i,
          space: disp.codeUnitAt(rStart) == 0x20,
          boxes: rp.getBoxesForSelection(TextSelection(baseOffset: rStart, extentOffset: i)),
        ));
        rStart = i;
      }
    }
    final nonSpace = [for (final r in ranges) if (!r.space) r];
    final nsBoxes = [for (final r in nonSpace) ...r.boxes];
    final nsFinite = nsBoxes.every((b) => b.left.isFinite && b.right.isFinite);
    Object fv(double x) => x.isFinite ? x : x.toString();
    List<Object> bx(TextBox b) => [fv(b.left), fv(b.top), fv(b.right), fv(b.bottom)];
    String cps(String s) => s.runes.map((r) => r.toRadixString(16).padLeft(4, '0')).join(' ');
    String attribution = 'none(가로 초과 없음)';
    if (hasBoxes && mx((b) => b.right) > rp.size.width + 0.5) {
      final top = mx((b) => b.right);
      final owners = [
        for (final r in ranges)
          if (r.boxes.any((b) => (b.right - top).abs() < 0.01)) '${r.space ? 'U+0020' : '비공백'} [${r.start},${r.end})',
      ];
      attribution = owners.isEmpty ? '불명' : owners.join(' · ');
    }
    final rec = <String, Object?>{
      'visibilityChecked': onScreen,
      'scale': rp.textScaler.scale(10) / 10,
      'local': [rp.size.width, rp.size.height],
      'intrinsicHeight': intrinsic,
      'global': rs(g),
      'boxes': boxes.length,
      'finite': finite,
      if (hasBoxes) 'tight': {'minLeft': mn((b) => b.left), 'minTop': mn((b) => b.top), 'maxRight': mx((b) => b.right), 'maxBottom': mx((b) => b.bottom)},
      if (hasBoxes) 'tightGlobal': {
        'minLeft': globalBoxes.map((r) => r.left).reduce((a, b) => a < b ? a : b),
        'minTop': globalBoxes.map((r) => r.top).reduce((a, b) => a < b ? a : b),
        'maxRight': globalBoxes.map((r) => r.right).reduce((a, b) => a > b ? a : b),
        'maxBottom': globalBoxes.map((r) => r.bottom).reduce((a, b) => a > b ? a : b),
      },
      'self': sc,
      'clipStop': cc.stop,
      'clips': cc.chain,
      'clipFailures': cc.failures,
      if (onScreen) 'viewport': rs(vr),
      if (onScreen) 'screen': [v.size.width, v.size.height],
      'offset': vOffset(t),
      // [C1 r3] 진단 — raw 상자별 좌표(줄 top/bottom 포함)·문자 범위별 start/end·표시 문자·code point·공백 여부·상자, 가로 초과.
      'rawBoxes': [for (final b in boxes) bx(b)],
      'ranges': [
        for (final r in ranges)
          {
            'start': r.start, 'end': r.end, 'space': r.space,
            'text': disp.substring(r.start, r.end), 'cp': cps(disp.substring(r.start, r.end)),
            'boxes': [for (final b in r.boxes) bx(b)],
          },
      ],
      if (hasBoxes) 'rawExcess': {'minLeft': mn((b) => b.left), 'maxRightMinusWidth': mx((b) => b.right) - rp.size.width},
      if (nsBoxes.isNotEmpty && nsFinite)
        'nonSpaceExcess': {
          'minLeft': nsBoxes.map((b) => b.left).reduce((a, b) => a < b ? a : b),
          'maxRightMinusWidth': nsBoxes.map((b) => b.right).reduce((a, b) => a > b ? a : b) - rp.size.width,
        },
      'rawExcessAttribution': attribution,
    };
    log('$id-bounds', rec);
    expect(TextLayout.plain(disp), original, reason: '$id 전문');
    expect(rp.maxLines, isNull, reason: '$id maxLines 없음');
    expect(rp.didExceedMaxLines, isFalse, reason: '$id 말줄임/잘림 0');
    expect(rp.textScaler.scale(10) / 10, closeTo(v.scale, 1e-6), reason: '$id 실제 배율');
    expect(rp.size.height, closeTo(intrinsic, 0.5), reason: '$id 자연 높이 size=${n2(rp.size.height)} intrinsic=${n2(intrinsic)}');
    expect(hasBoxes, isTrue, reason: '$id tight 상자 ${boxes.length}개·유한=$finite');
    // [C1 r3] 가로 문단폭 비교 — U+0020 범위만 뺀다. 비공백 범위(NBSP·구분점·제어문자 포함)의 모든 tight 상자는 ±0.5.
    //   raw 상자의 self/조상/viewport/화면 검사는 아래에서 그대로 한다.
    expect(ranges.isNotEmpty && ranges.first.start == 0 && ranges.last.end == disp.length, isTrue,
        reason: '$id 문자 범위가 전문을 덮지 않음(${ranges.length}개, 길이 ${disp.length})');
    expect(nonSpace, isNotEmpty, reason: '$id 비공백 범위 0개');
    for (final r in nonSpace) {
      final label = TextLayout.plain(disp.substring(r.start, r.end));
      expect(r.boxes, isNotEmpty, reason: '$id 비공백 [${r.start},${r.end}) `$label` 상자 0개');
      for (final b in r.boxes) {
        expect(b.left.isFinite && b.right.isFinite, isTrue, reason: '$id 비공백 [${r.start},${r.end}) `$label` 비유한 상자');
        expect(b.left >= -0.5 && b.right <= rp.size.width + 0.5, isTrue,
            reason: '$id 비공백 [${r.start},${r.end}) `$label` tight 가로 left=${n2(b.left)} right=${n2(b.right)} 문단폭=${n2(rp.size.width)}');
      }
    }
    expect(sc['placeholders'], isFalse, reason: '$id 미지원 — WidgetSpan placeholder 있는 문단');
    expect(sc['reproduced'], isTrue, reason: '$id self clip 재현 불일치 painter=${sc['painter']} constrained=${sc['constrained']} paragraph=${sc['paragraph']}');
    if (sc['selfClip'] == true) {
      for (final b in boxes) {
        expect(b.left >= -0.5 && b.top >= -0.5 && b.right <= rp.size.width + 0.5 && b.bottom <= rp.size.height + 0.5, isTrue,
            reason: '$id self clip(${sc['overflow']}) 경계 [0,0,${n2(rp.size.width)},${n2(rp.size.height)}] 밖 상자 ${rs(b.toRect())}');
      }
    }
    expect(cc.failures, isEmpty, reason: '$id 조상 clip(${cc.stop}): ${cc.failures.join(' | ')}');
    if (onScreen) {
      for (final r in globalBoxes) {
        expect(r.top >= vr.top - 0.5 && r.bottom <= vr.bottom + 0.5 && r.left >= vr.left - 0.5 && r.right <= vr.right + 0.5, isTrue,
            reason: '$id 이 스크롤 위치에서 viewport ${rs(vr)} 밖 상자 ${rs(r)}');
        expect(r.top >= -0.5 && r.left >= -0.5 && r.bottom <= v.size.height + 0.5 && r.right <= v.size.width + 0.5, isTrue,
            reason: '$id 화면 [0,0,${n2(v.size.width)},${n2(v.size.height)}] 밖 상자 ${rs(r)}');
      }
    }
    final lineTops = <int>{for (final b in boxes) b.top.round()};
    rec['lines'] = lineTops.length;
    return rec;
  }

  /// [C1] 필수응답 카드(미퇴근·ID) — 전문·줄상자·clip·화면 안·겹침 0·receiver(카드 전체) ≥48·행동 글자 중심 hit·낱말 줄.
  Map<String, Object?> checkTask(WidgetTester t, _V v, String id,
      {required String title, required String sub, required String action, required IconData icon}) {
    final tf = plain(title), sf = plain(sub), af = plain(action);
    expect(tf, findsOneWidget, reason: '$id 제목');
    final card = find.ancestor(of: tf, matching: find.byType(GestureDetector)).first;
    expect(find.descendant(of: card, matching: sf), findsOneWidget, reason: '$id 부제 같은 카드');
    expect(find.descendant(of: card, matching: af), findsOneWidget, reason: '$id 행동 같은 카드');
    expect(find.descendant(of: card, matching: semLabel(title)), findsOneWidget, reason: '$id 제목 의미 원문');
    expect(find.descendant(of: card, matching: semLabel(sub)), findsOneWidget, reason: '$id 부제 의미 원문');
    final rec = <String, Object?>{
      'title': expectFullText(t, tf, title, v, '$id 제목'),
      'sub': expectFullText(t, sf, sub, v, '$id 부제'),
      'action': expectFullText(t, af, action, v, '$id 행동'),
      'titleWords': expectWordsKept(para(t, tf), title, '$id 제목'),
      'subWords': expectWordsKept(para(t, sf), sub, '$id 부제'),
    };
    final rt = t.getRect(tf), rs = t.getRect(sf);
    final ra = t.getRect(find.ancestor(of: af, matching: find.byType(Row)).first);
    final ri = t.getRect(find.ancestor(of: find.descendant(of: card, matching: find.byIcon(icon)), matching: find.byType(Container)).first);
    bool apart(Rect a, Rect b) {
      final i = a.intersect(b);
      return i.width <= 0.01 || i.height <= 0.01;
    }
    expect(apart(rt, ra), isTrue, reason: '$id 제목↔행동 겹침 0');
    expect(apart(rs, ra), isTrue, reason: '$id 부제↔행동 겹침 0');
    expect(apart(ri, rt), isTrue, reason: '$id 아이콘↔제목 겹침 0');
    expect(apart(ri, rs), isTrue, reason: '$id 아이콘↔부제 겹침 0');
    expect(apart(ri, ra), isTrue, reason: '$id 아이콘↔행동 겹침 0');
    final rc = t.getRect(card);
    expect(rc.height, greaterThanOrEqualTo(48), reason: '$id receiver 높이 ≥48');
    expect(rc.width, greaterThanOrEqualTo(48), reason: '$id receiver 폭 ≥48');
    expect(hitAt(t, t.getRect(af).center, card), isTrue, reason: '$id 행동 글자 중심 hit = 카드 receiver');
    expect(hitAt(t, rc.center, card), isTrue, reason: '$id 카드 중심 hit');
    final vr = viewRect(t);
    expect(rc.top >= vr.top - 0.5 && rc.bottom <= vr.bottom + 0.5, isTrue, reason: '$id 카드 전체 화면 안');
    rec['layout'] = ra.top >= (rt.bottom > rs.bottom ? rt.bottom : rs.bottom) - 0.01 ? 'stacked(행동 아래 오른쪽 줄)' : 'inline';
    rec['rects'] = {'card': rl(rc), 'title': rl(rt), 'sub': rl(rs), 'action': rl(ra), 'icon': rl(ri)};
    rec['offset'] = vOffset(t);
    // [C1 r3] 카드 배치 회귀(지정 fixture) — 안쪽 = 카드 LayoutBuilder(아이콘 포함 전체 가용 폭), 본문 = 제목·부제 Column.
    //   수치를 먼저 남기고 단언한다. W = 같은 줄, B = 행동이 제목·부제 아래 오른쪽 + 본문이 안쪽 오른쪽까지 + 본문 ≥ 안쪽 50%.
    final inner = t.getRect(find.descendant(of: card, matching: find.byType(LayoutBuilder)).first);
    final body = t.getRect(find.ancestor(of: tf, matching: find.byType(Column)).first);
    final stacked = ra.top >= body.bottom - 0.01;
    final lay = <String, Object?>{
      'viewport': v.id, 'scale': v.scale, 'layout': stacked ? 'stacked' : 'inline',
      'card': rl(rc), 'inner': rl(inner), 'body': rl(body), 'action': rl(ra),
      'bodyRatio': body.width / inner.width,
      'titleLines': (rec['title'] as Map)['lines'], 'subLines': (rec['sub'] as Map)['lines'],
    };
    log('$id-layout', lay);
    rec['layoutCheck'] = lay;
    if (v.id == 'W') {
      expect(stacked, isFalse, reason: '$id W 같은 줄 — 행동 top=${n2(ra.top)} 본문 bottom=${n2(body.bottom)}');
      expect(ra.left >= body.right - 0.5, isTrue, reason: '$id W 행동이 본문 오른쪽 — 행동 left=${n2(ra.left)} 본문 right=${n2(body.right)}');
      expect(ra.top < body.bottom && ra.bottom > body.top, isTrue,
          reason: '$id W 행동·본문 세로 겹침(같은 줄) — 행동 ${n2(ra.top)}–${n2(ra.bottom)} 본문 ${n2(body.top)}–${n2(body.bottom)}');
    } else {
      expect(stacked, isTrue, reason: '$id B 행동이 제목·부제 아래 — 행동 top=${n2(ra.top)} 본문 bottom=${n2(body.bottom)}');
      expect((ra.right - inner.right).abs() <= 0.5, isTrue,
          reason: '$id B 행동 오른쪽 정렬 — 행동 right=${n2(ra.right)} 안쪽 right=${n2(inner.right)}');
      expect((body.right - inner.right).abs() <= 0.5, isTrue,
          reason: '$id B 본문이 안쪽 오른쪽까지 — 본문 right=${n2(body.right)} 안쪽 right=${n2(inner.right)}');
      expect(body.width >= inner.width * 0.5, isTrue,
          reason: '$id B 본문 ≥ 안쪽 폭 50% — 본문 ${n2(body.width)} 안쪽 ${n2(inner.width)}');
    }
    return rec;
  }

  // ── after 공통 단언 ──
  void expectHeader(WidgetTester t, _V v, String name) {
    final n = plain('$name님');
    final h = plain('오늘도, 내 일정에 맞게');
    final d = plain(_kDate(_today));
    expect(n, findsOneWidget, reason: '${v.id} 계정 이름 메타');
    expect(h, findsOneWidget, reason: '${v.id} 큰 머리');
    expect(d, findsOneWidget, reason: '${v.id} KST 날짜');
    final rn = t.getRect(n), rh = t.getRect(h), rd = t.getRect(d);
    expect(rh.top - rn.bottom, closeTo(4, 0.01), reason: '${v.id} 이름 →4→ 큰 머리');
    expect(rd.top - rh.bottom, closeTo(4, 0.01), reason: '${v.id} 큰 머리 →4→ 날짜');
    for (final f in [n, h, d]) {
      final rp = para(t, f);
      expect(rp.didExceedMaxLines, isFalse, reason: '${v.id} 머리 글자 전문');
      expect(rp.textScaler.scale(10) / 10, closeTo(v.scale, 1e-6), reason: '${v.id} 실제 배율');
      final r = t.getRect(f);
      expect(r.left >= 0 && r.right <= v.size.width, isTrue, reason: '${v.id} 머리 글자 가로 화면 안');
    }
    expect(para(t, h).text.style?.fontSize, 24, reason: '${v.id} 큰 머리 24');
    expect(para(t, h).text.style?.fontWeight, FontWeight.w700);
    expect(para(t, n).text.style?.fontSize, 14, reason: '${v.id} 이름 14');
    expect(plain('언제 일하고 싶으세요?'), findsNothing, reason: '${v.id} 질문 시각 삭제');
    expect(plain('일할 날짜를 선택해보세요.'), findsNothing, reason: '${v.id} 부제 시각 삭제');
    // 날짜띠: 그룹 의미, 7날짜 각 receiver ≥48×48, 주말 중립색, `날짜 선택` receiver ≥48
    expect(semLabel('일할 날짜 선택'), findsOneWidget, reason: '${v.id} 날짜 그룹 의미');
    for (var i = 0; i < 7; i++) {
      final dd = _day(i);
      final cell = semPrefix(_kDate(dd));
      expect(cell, findsOneWidget, reason: '${v.id} ${_kDate(dd)} 의미');
      final r = t.getSize(cell); // [r1] 레이아웃 크기(화면 좌표 차의 부동소수 오차 제외)
      expect(r.width, greaterThanOrEqualTo(48), reason: '${v.id} 날짜 폭 ≥48');
      expect(r.height, greaterThanOrEqualTo(48), reason: '${v.id} 날짜 높이 ≥48');
      final dow = find.descendant(of: cell, matching: find.text(_wd[dd.weekday - 1]));
      expect(t.widget<Text>(dow).style?.color, AppColors.textSecondary, reason: '${v.id} 요일 중립색(주말 포함)');
    }
    final pick = semLabel('날짜 선택');
    expect(pick, findsOneWidget, reason: '${v.id} 날짜 선택');
    expect(t.getSize(pick).height, greaterThanOrEqualTo(48));
    expect(t.getSize(pick).width, greaterThanOrEqualTo(48));
    // 날짜 →16→ 띠
    expect(t.getRect(semLabel('일할 날짜 선택')).top - rd.bottom, closeTo(16, 0.01), reason: '${v.id} 날짜 →16→ 띠');
  }

  /// 보이는 블록 사이 간격: 같은 수준 카드끼리 12, 그 밖 24.
  void expectRhythm(WidgetTester t, _V v, List<Map<String, Object?>> sl) {
    final vis = [for (final s in sl) if (((s['rect'] as List)[3] as double) > 0) s];
    for (var i = 1; i < vis.length; i++) {
      final a = vis[i - 1], b = vis[i];
      final ra = (a['rect'] as List).cast<double>(), rb = (b['rect'] as List).cast<double>();
      final want = (a['kind'] == 'card' && b['kind'] == 'card') ? 12.0 : 24.0;
      expect(rb[1] - (ra[1] + ra[3]), closeTo(want, 0.01), reason: '${v.id} 블록 $i 간격 ${a['kind']}→${b['kind']}');
      expect(ra[2], closeTo(v.size.width, 0.01), reason: '${v.id} 블록 폭 = 화면 폭');
    }
  }

  Finder ctaButton(String label) => find.ancestor(of: plain(label), matching: find.byWidgetPredicate((w) => w is ButtonStyleButton));

  final cases = <({String state, String name, bool png, String fixture})>[
    (state: 'today', name: '김근로', png: true, fixture: 'B 오늘 13:00 출근 전 · 계약 완료 · 근태 0'),
    (state: 'newConfirm', name: '김근로', png: true, fixture: 'A 새 확정(11월 13일, 1시간 전 확정·미확인)'),
    (state: 'empty', name: _longName, png: true, fixture: '정상 약속 0(대기 지원 1) · 긴 이름'),
    (state: 'overnight', name: '김근로', png: true, fixture: '어제 22:00 출근·미퇴근 + 오늘 13:00 약속'),
    (state: 'contract', name: '김근로', png: true, fixture: '오늘 약속 · 계약 근로자 서명 대기 · 신분증 열람 요청 1'),
    (state: 'fail', name: '김근로', png: false, fixture: '지원 조회 실패(raw 단언만)'),
  ];

  for (final v in const [_w, _b]) {
    for (final c in cases) {
      testWidgets('CP03 ${c.state} ${v.id}', (t) async {
        _cases.add('${c.state}-${v.id}');
        // [C1] 의미 트리 — 마운트 전에 켜서 최종 node 를 읽는다. 끝에서 닫는다(실패해도).
        final semH = t.ensureSemantics();
        try {
        await collecting(t, (errs) async {
          final tabLog = <String>[];
          final key = await open(t, c.state, v, tabLog, name: c.name);
          // [C1] PNG 배정 — today W0/B0 · newConfirm W0 · empty W0/B0 · overnight W0(+B 카드 도달) · contract W0(+B ID 도달·B CTA 도달)
          final pngAtOpen = c.png && (v.id == 'W' || c.state == 'today' || c.state == 'empty');
          if (pngAtOpen) await shot(t, key, 'CP03C1-${c.state}-${v.id}', v, c.fixture, frame: 'offset0');
          final sl = slots(t);
          final rec = <String, Object?>{
            'state': c.state,
            'name': textRec(t, '${c.name}님'),
            'hero': textRec(t, '오늘도, 내 일정에 맞게'),
            'date': textRec(t, _kDate(_today)),
            'question': plain('언제 일하고 싶으세요?').evaluate().length,
            'slots': sl,
            for (final s in ['오늘의 약속', '새로 확정된 근무', '내 지원 현황', '둘러볼 일자리', '이번 주 일정', '수입 현황', '내 근무 기록',
              '퇴근 기록이 필요해요', '$_bizName에서 신분증 열람을 요청했어요', '오늘 확정된 근무가 없어요', '지원 현황을 불러오지 못했어요',
              '오늘 13:00 출근이에요', '출근하기', '계약서 확인하고 동의하기', '근무 확정', '근무가 확정됐어요', '근무 확인하기', _bizName, '피킹'])
              s: textRec(t, s),
          };
          log('${c.state}-${v.id}-open', rec);

          if (after) {
            expectHeader(t, v, c.name);
            expectRhythm(t, v, sl);
            final y = <String, double>{
              for (final s in ['오늘의 약속', '새로 확정된 근무', '내 지원 현황', '둘러볼 일자리', '이번 주 일정', '수입 현황', '내 근무 기록',
                '퇴근 기록이 필요해요', '$_bizName에서 신분증 열람을 요청했어요'])
                if (plain(s).evaluate().isNotEmpty) s: t.getRect(plain(s).first).top,
            };
            // 섹션 순서(Q2): 미퇴근 → ID → 약속 → 내 지원 현황 → 발견 → 이번 주 일정 → 수입 → 내 근무 기록
            final order = ['퇴근 기록이 필요해요', '$_bizName에서 신분증 열람을 요청했어요', '오늘의 약속', '새로 확정된 근무', '내 지원 현황',
              '둘러볼 일자리', '이번 주 일정', '수입 현황', '내 근무 기록'].where(y.containsKey).toList();
            for (var i = 1; i < order.length; i++) {
              expect(y[order[i]]! > y[order[i - 1]]!, isTrue, reason: '${v.id} 순서 ${order[i - 1]} < ${order[i]}');
            }
            for (final s in ['내 지원 현황', '이번 주 일정', '수입 현황', '내 근무 기록']) {
              expect(plain(s), findsOneWidget, reason: '${v.id} 섹션 $s');
              expect(para(t, plain(s)).text.style?.fontSize, 20, reason: '${v.id} 섹션 제목 20');
            }
            for (final a in ['전체 보기', '일정 보기', '${_today.year}년 ${_today.month}월']) {
              final f = semLabel(a);
              expect(f, findsOneWidget, reason: '${v.id} 행동 $a');
              expect(t.getSize(f).height, greaterThanOrEqualTo(48));
              expect(t.getSize(f).width, greaterThanOrEqualTo(48));
            }
            expect(find.textContaining('›'), findsNothing, reason: '${v.id} 문자열 꺾쇠 0');
            expect(plain('모집중'), findsNothing);
            expect(plain('마감임박'), findsNothing);

            // ── [C1] 의미 트리(이 사례의 시작 위치 — 본문 SingleChildScrollView 는 화면 밖 node 도 트리에 둔다) ──
            final id = '${c.state}-${v.id}';
            final semRec = <String, Object?>{};
            for (final a in ['전체 보기', '일정 보기', '${_today.year}년 ${_today.month}월']) {
              semRec[a] = expectNode(t, semLabel(a), '$id 섹션 행동 $a', label: a, tap: true);
              expectSameCallback(t, semLabel(a), '$id 섹션 행동 $a', present: true);
            }
            // 날짜: 공고 0(publishedTOs 비어 있음) — 확정 근무가 있는 날만 탭 가능(기존 술어). 그 밖은 enabled=false·tap 없음.
            final confirmed = switch (c.state) { 'today' || 'overnight' || 'contract' => {0}, 'newConfirm' => {2}, _ => <int>{} };
            for (var i = 0; i < 7; i++) {
              final dd = _day(i);
              final on = confirmed.contains(i);
              final cell = semPrefix(_kDate(dd));
              semRec[_kDate(dd)] = expectNode(t, cell, '$id ${_kDate(dd)}',
                  label: [_kDate(dd), if (on) '확정 근무 있음'].join(', '), tap: on, enabled: on, selected: false);
              expectSameCallback(t, cell, '$id ${_kDate(dd)}', present: on);
            }
            semRec['날짜 선택'] = expectNode(t, semLabel('날짜 선택'), '$id 날짜 선택', label: '날짜 선택', tap: true);
            expectSameCallback(t, semLabel('날짜 선택'), '$id 날짜 선택', present: true);
            // 이름 — 마지막 낱말과 `님` 이 같은 줄(표시만 결합, 원문·의미 이름 그대로)
            semRec['nameWords'] = expectWordsKept(para(t, plain('${c.name}님')), '${c.name}님', '$id 이름');
            expect(semLabel('${c.name}님'), findsOneWidget, reason: '$id 이름 의미 원문');
            log('$id-semantics', semRec);

            // ── [C1] 의미 action dispatch(안전한 기존 fixture 안에서만) ──
            if (id == 'today-B') {
              // 오늘(확정) 날짜 선택 → 선택 CTA 등장 → 다시 → 해제
              final cell = semPrefix(_kDate(_today));
              final pickCta = ctaButton('${_today.month}월 ${_today.day}일 일자리 0개 보기');
              expect(pickCta, findsNothing);
              await dispatchTap(t, cell);
              expect(node(t, cell).getSemanticsData().flagsCollection.isSelected, isTrue, reason: '$id 의미 tap → 선택');
              expect(pickCta, findsOneWidget, reason: '$id 선택 CTA 등장');
              await dispatchTap(t, cell);
              expect(node(t, cell).getSemanticsData().flagsCollection.isSelected, isFalse, reason: '$id 의미 tap → 해제');
              expect(pickCta, findsNothing, reason: '$id 해제 → CTA 없음');
              // 마지막 날짜까지 가로 도달 · receiver ≥48 · 중심 hit (가로 띠 = B 만)
              final last = semPrefix(_kDate(_day(6)));
              final h0 = hOffset(t);
              await reach(t, last);
              final r = t.getRect(last);
              final vr = viewRect(t);
              expect(r.left >= -0.01 && r.right <= v.size.width + 0.01 && r.top >= vr.top - 0.5 && r.bottom <= vr.bottom + 0.5, isTrue,
                  reason: '$id 마지막 날짜 화면 안');
              expect(t.getSize(last).width, greaterThanOrEqualTo(48));
              expect(t.getSize(last).height, greaterThanOrEqualTo(48));
              expect(hitAt(t, r.center, find.descendant(of: last, matching: find.byType(GestureDetector)).first), isTrue,
                  reason: '$id 마지막 날짜 중심 hit');
              final h1 = hOffset(t);
              expect(h1 is double && h1 > 0, isTrue, reason: '$id 띠 가로 스크롤 실제 이동');
              log('$id-lastDate', {'hOffsetBefore': h0, 'hOffsetAfter': h1, 'rect': rl(r), 'vOffset': vOffset(t)});
            }
            if (id == 'newConfirm-W') {
              // `날짜 선택` 의미 tap → 날짜 시트 표시 → 바깥(장벽) 탭으로 닫기 → 띠·선택 그대로
              expect(find.byType(BottomSheet), findsNothing);
              await dispatchTap(t, semLabel('날짜 선택'));
              expect(find.byType(BottomSheet), findsOneWidget, reason: '$id 의미 tap → 날짜 시트');
              expect(find.text('공고 있음'), findsOneWidget, reason: '$id 시트 범례');
              await t.tapAt(Offset(v.size.width / 2, 8));
              _taps++;
              await settle(t, 6);
              expect(find.byType(BottomSheet), findsNothing, reason: '$id 시트 닫힘');
              expect(semPrefix(_kDate(_today)), findsOneWidget, reason: '$id 띠 시작 그대로');
              expect(node(t, semPrefix(_kDate(_day(2)))).getSemanticsData().flagsCollection.isSelected, isFalse,
                  reason: '$id 선택 없음 그대로');
            }
            if (id == 'fail-W') {
              // 대표 섹션 행동 — `일정 보기` 의미 tap → 기존 탭 목적지(일정 탭). 무거운 목적지(전체 보기·수입)는 콜백 동일성만.
              await dispatchTap(t, semLabel('일정 보기'));
              expect(tabLog.contains('switchToTab:2'), isTrue, reason: '$id 의미 tap → 일정 탭');
            }

            // ── [C1] B 상태 제목 낱말 줄(W·B) ──
            if (c.state == 'today' || c.state == 'overnight' || c.state == 'contract') {
              const ht = '오늘 13:00 출근이에요';
              log('$id-heroTitle', {
                'full': expectFullText(t, plain(ht), ht, v, '$id B 상태 제목', onScreen: false),
                'words': expectWordsKept(para(t, plain(ht)), ht, '$id B 상태 제목'),
              });
              expect(semLabel(ht), findsOneWidget, reason: '$id B 상태 제목 의미 원문');
            }

            // ── [C1] 필수응답 카드 — W 는 시작 위치, B 는 카드 도달 프레임 ──
            final overSub = '${_day(-1).month}/${_day(-1).day} 근무 · $_bizName · 22:00 출근';
            const idTitle = '$_bizName에서 신분증 열람을 요청했어요';
            const idSub = '확인하고 승인 또는 거절해 주세요';
            if (c.state == 'overnight') {
              if (v.id == 'B') {
                await reach(t, find.ancestor(of: plain('퇴근 기록이 필요해요'), matching: find.byType(GestureDetector)).first);
                await shot(t, key, 'CP03C1-overnight-B-card', v, '${c.fixture} · 미퇴근 카드 도달', frame: 'overnight-card-reach');
              }
              log('$id-overnightCard',
                  checkTask(t, v, '$id 미퇴근', title: '퇴근 기록이 필요해요', sub: overSub, action: '퇴근하기', icon: Icons.logout_rounded));
            }
            if (c.state == 'contract') {
              if (v.id == 'B') {
                await reach(t, find.ancestor(of: plain(idTitle), matching: find.byType(GestureDetector)).first);
                await shot(t, key, 'CP03C1-contract-B-id', v, '${c.fixture} · 신분증 열람 요청 카드 도달', frame: 'id-card-reach');
              }
              final idRec = checkTask(t, v, '$id 신분증 요청', title: idTitle, sub: idSub, action: '요청 확인', icon: Icons.badge_outlined);
              log('$id-idCard', idRec);
              // [C1 r3] 고정 W ID fixture 의 제목은 2줄(제품 최대 줄 수를 정하는 것이 아니라 이 fixture 의 회귀 확인)
              if (v.id == 'W') expect((idRec['title'] as Map)['lines'], 2, reason: '$id W ID 제목 2줄');
            }

            if (c.state == 'today' || c.state == 'overnight' || c.state == 'contract') {
              // B: 상태 제목 →12→ 사업장 →4→ 업무 →8→ 시간 →4→ 요율 … CTA ≥52
              final title = plain('오늘 13:00 출근이에요');
              expect(title, findsOneWidget, reason: '${v.id} B 상태 제목');
              final card = find.ancestor(of: title, matching: find.byType(Column)).first;
              final biz = find.descendant(of: card, matching: plain(_bizName));
              final work = find.descendant(of: card, matching: plain('피킹'));
              final wage = find.descendant(of: card, matching: plain(FormatHelper.formatWageWithType(12000, 'hourly')));
              expect(t.getRect(biz).top - t.getRect(title).bottom, closeTo(12, 0.01), reason: '${v.id} 제목→사업장 12');
              expect(t.getRect(work).top - t.getRect(biz).bottom, closeTo(4, 0.01), reason: '${v.id} 사업장→업무 4');
              final time = semLabel('13:00–18:00');
              expect(time, findsOneWidget, reason: '${v.id} 큰 시간 의미 원문');
              expect(t.getRect(time).top - t.getRect(work).bottom, closeTo(8, 0.01), reason: '${v.id} 업무→시간 8');
              expect(t.getRect(wage).top - t.getRect(time).bottom, closeTo(4, 0.01), reason: '${v.id} 시간→요율 4');
              expect(para(t, find.descendant(of: time, matching: plain('13:00'))).text.style?.fontSize, 28, reason: '${v.id} 시간 28');
              expect(para(t, biz).text.style?.fontSize, 20, reason: '${v.id} 사업장 20');
              expect(t.getRect(plain('오늘의 약속')).bottom < t.getRect(title).top, isTrue, reason: '${v.id} 섹션 제목 카드 밖');
              final ctaLabel = c.state == 'contract' ? '계약서 확인하고 동의하기' : '출근하기';
              final cta = ctaButton(ctaLabel);
              expect(cta, findsOneWidget, reason: '${v.id} 기존 CTA $ctaLabel');
              expect(t.getSize(cta).height, greaterThanOrEqualTo(52), reason: '${v.id} CTA ≥52');
              expect(para(t, plain(ctaLabel)).didExceedMaxLines, isFalse);
              // [C1] 기존 CTA 표시 — 낱말 사이에서만 줄바꿈, 의미 이름 원문
              expect(find.descendant(of: cta, matching: semLabel(ctaLabel)), findsOneWidget, reason: '$id CTA 의미 원문');
              final ctaRec = <String, Object?>{
                'words': expectWordsKept(para(t, plain(ctaLabel)), ctaLabel, '$id CTA'),
                'full': expectFullText(t, plain(ctaLabel), ctaLabel, v, '$id CTA', onScreen: false),
              };
              if (v.id == 'B') {
                // B: 스크롤로 도달 + 중심 hit(W 는 크기만 — 스크롤 상한)
                await reach(t, cta);
                final rc = t.getRect(cta);
                expect(rc.top >= 0 && rc.bottom <= v.size.height, isTrue, reason: '${v.id} CTA 스크롤 도달');
                expect(hits(t, cta), isTrue, reason: '${v.id} CTA 중심 hit');
                if (c.state == 'contract') {
                  // [C1] 계약 CTA — 도달한 뒤 줄상자와 PNG 로 판독(원 offset0 PNG 로는 보이지 않았다)
                  await shot(t, key, 'CP03C1-contract-B-cta', v, '${c.fixture} · 계약 CTA 도달', frame: 'cta-reach');
                  ctaRec['reached'] = expectFullText(t, plain(ctaLabel), ctaLabel, v, '$id CTA 도달');
                  ctaRec['rect'] = rl(rc);
                  ctaRec['offset'] = vOffset(t);
                }
              }
              log('$id-cta', ctaRec);
              expect(plain('근무 확정'), findsNothing, reason: '${v.id} B 확정 필 없음');
            }
            if (c.state == 'newConfirm') {
              expect(plain('새로 확정된 근무'), findsOneWidget);
              final pill = plain('근무 확정');
              final desc = plain('근무가 확정됐어요');
              final date = plain('11월 ${_day(2).day}일(${_wd[_day(2).weekday - 1]})');
              expect(pill, findsOneWidget, reason: '${v.id} A 확정 필');
              expect(desc, findsOneWidget);
              expect(date, findsOneWidget, reason: '${v.id} A 날짜');
              final time = semLabel('09:00–18:00');
              expect(t.getRect(time).top - t.getRect(date).bottom, closeTo(4, 0.01), reason: '${v.id} 날짜→시간 4');
              final biz = plain(_bizName);
              expect(t.getRect(biz).top - t.getRect(time).bottom, closeTo(12, 0.01), reason: '${v.id} 시간→사업장 12');
              expect(t.getRect(plain('피킹')).top - t.getRect(biz).bottom, closeTo(4, 0.01), reason: '${v.id} 사업장→업무 4');
              expect(t.widget<Text>(pill).style?.color, AppColors.successDark, reason: '${v.id} 확정 필 #166534');
              final cta = find.ancestor(of: plain('근무 확인하기'), matching: find.byType(Container)).first;
              expect(t.getSize(cta).height, greaterThanOrEqualTo(52), reason: '${v.id} A CTA ≥52');
              if (v.id == 'B') {
                await reach(t, plain('근무 확인하기'));
                final rcta = t.getRect(cta);
                expect(rcta.top >= 0 && rcta.bottom <= v.size.height, isTrue, reason: '${v.id} A CTA 도달');
              }
            }
            if (c.state == 'empty') {
              expect(plain('오늘 확정된 근무가 없어요'), findsOneWidget, reason: '${v.id} 정상0 안내');
              final btn = ctaButton('일자리 찾기');
              expect(btn, findsOneWidget, reason: '${v.id} 정상0 보조 탐색');
              expect(t.getSize(btn).height, greaterThanOrEqualTo(48));
              expect(t.getSize(btn).width, greaterThanOrEqualTo(48));
              await reach(t, btn);
              await tapCenter(t, btn);
              expect(tabLog.contains('switchToTab:1'), isTrue, reason: '${v.id} 일자리 찾기 → 일자리 탭');
              // 긴 이름 — 전문·자연 높이·화면 안(헤더 측정은 expectHeader)
              // [C1 r2] 표시 문자열은 keepWords(낱말 안 U+2060) — 제어문자를 뺀 원문과 정확 비교한다(전문·의미 원문·낱말 줄은 그대로).
              expect(TextLayout.plain(para(t, plain('$_longName님')).text.toPlainText(includeSemanticsLabels: false)), '$_longName님');
            }
            if (c.state == 'overnight') {
              expect(plain('퇴근 기록이 필요해요'), findsOneWidget, reason: '${v.id} 미퇴근 카드');
              final sub = plain('${_day(-1).month}/${_day(-1).day} 근무 · $_bizName · 22:00 출근');
              expect(sub, findsOneWidget, reason: '${v.id} 미퇴근 부제 전문');
              expect(para(t, sub).didExceedMaxLines, isFalse);
              expect(plain('오늘의 약속'), findsOneWidget, reason: '${v.id} 오늘 약속 동시 표시');
            }
            if (c.state == 'contract') {
              expect(plain('$_bizName에서 신분증 열람을 요청했어요'), findsOneWidget, reason: '${v.id} 독립 필수응답');
            }
            if (c.state == 'fail') {
              expect(plain('오늘의 약속'), findsNothing, reason: '${v.id} 실패를 정상0 으로 말하지 않음');
              expect(plain('오늘 확정된 근무가 없어요'), findsNothing);
              final err = plain('지원 현황을 불러오지 못했어요');
              expect(err, findsOneWidget, reason: '${v.id} 지원 조회 실패 표면');
              final retry = find.ancestor(
                  of: find.descendant(of: find.ancestor(of: err, matching: find.byType(Column)).first, matching: find.text('다시 시도')),
                  matching: find.byType(GestureDetector)).first;
              expect(t.getSize(retry).height, greaterThanOrEqualTo(48), reason: '${v.id} 다시 시도 ≥48');
              expect(t.getSize(retry).width, greaterThanOrEqualTo(48));
              if (v.id == 'B') await reach(t, retry);
            }
            if (c.state == 'today' && v.id == 'W') {
              // 탐색 날짜 선택 → 선택 CTA(≥52) → 일자리 탭에 날짜 전달
              await tapCenter(t, semPrefix(_kDate(_today)));
              final pickCta = ctaButton('11월 ${_today.day}일 일자리 0개 보기');
              expect(pickCta, findsOneWidget, reason: 'W 선택 CTA');
              expect(t.getSize(pickCta).height, greaterThanOrEqualTo(52));
              await tapCenter(t, pickCta);
              expect(tabLog.contains('switchToTabWithDate:1/${_today.year}-${_today.month}-${_today.day}'), isTrue);
            }
            if (c.state == 'newConfirm') {
              final f = semLabel('일정 보기');
              await reach(t, f);
              await tapCenter(t, f);
              expect(tabLog.contains('switchToTab:2'), isTrue, reason: '${v.id} 일정 보기 → 일정 탭');
            }
            if (v.id == 'B') {
              final last = plain('내 근무 기록');
              await reach(t, last);
              final r = t.getRect(last);
              expect(r.top >= 0 && r.bottom <= v.size.height, isTrue, reason: 'B 마지막 섹션 도달');
            }
          }
          log('${c.state}-${v.id}-end', {'tabLog': tabLog, 'taps': _taps, 'actions': _actions, 'scrolls': _scrolls});
          await t.pumpWidget(const SizedBox.shrink());
          _pumps++;
          await t.pump(const Duration(seconds: 5));
          _pumps++;
          judgeErrors('${c.state}-${v.id}', errs);
        });
        } finally {
          semH.dispose();
        }
      });
    }
  }

  // [C1] 사례마다(실패한 사례 포함) 누계 — 실패 시점까지의 실행량을 남긴다.
  tearDown(() {
    // ignore: avoid_print
    print('CP03C1-COUNT cases=${_cases.length} mounts=$_mounts pumps=$_pumps pumpPlusMount=${_pumps + _mounts} '
        'taps=$_taps actions=$_actions tapsPlusActions=${_taps + _actions} scrolls=$_scrolls pngPairs=$_pngs');
  });

  tearDownAll(() {
    // ignore: avoid_print
    print('CP03-FINAL phase=$phase cases=${_cases.length} mounts=$_mounts pumps=$_pumps pumpPlusMount=${_pumps + _mounts} '
        'taps=$_taps actions=$_actions scrolls=$_scrolls pngPairs=$_pngs');
    expect(_cases.length, lessThanOrEqualTo(12));
    expect(_mounts, lessThanOrEqualTo(12));
    expect(_taps + _actions, lessThanOrEqualTo(24));
    expect(_scrolls, lessThanOrEqualTo(24));
    expect(_pumps + _mounts, lessThanOrEqualTo(800));
    expect(_pngs, lessThanOrEqualTo(10));
  });
}
