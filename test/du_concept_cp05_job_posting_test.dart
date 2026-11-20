// ignore_for_file: depend_on_referenced_packages
// [CP05] 일자리 상세 — 8장면 × W/B = 16사례.
//   지시: records/requests/DU_concept_CP05_start_2026-11-12.md(정밀 §4·§6·§8·§9, 문구 Q6/CP05, 원 CP05 계약).
//   phase = DU1_VQ_PHASE=before|after. before = 원본 관측 기록(단언 없음), after = 확정 구성·문구·R 단언.
//   기존 LOCAL 진입 재사용: JobPostingScreen(to:, workDetails:, business:, slotDate:, myApplication:, reads:) + JobPostingReads 메모리 대역
//   (posting_apply_tax_prefetch_test.dart:186–230 모양). 세무 미리 받기(taxStatus·now)까지 대역이다. 새 production seam 0, 무쓰기·무네트워크.
//   실제 시각 예외(지시 §2): 화면·모델은 DateTime.now 를 직접 읽는다 — 주입하지 않는다. 고정 날짜 fixture(열림 11-16 이후, 종료 11-09 이전)와
//   runner 의 실행 구간(2026-11-12 KST 02:30–21:30) 안에서 분기가 같다(plan/inv_time.md T01–T19).
//   장면: normal(선택 전후 한 mount) · multi(다중 날짜·업무, 주말·야간·월급) · full(정원) · ended(종료) · document(서류 준비) ·
//         applied(기지원) · invited(초대) · slotError(근무일 조회 실패).
//   실제 지원·초대 수락/거절·지원 취소·서류 등록 화면·확인 시트는 열지 않는다(writer·seam 없는 조회 0).
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

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
import 'package:ALfit/models/core/business_model.dart';
import 'package:ALfit/models/core/insurance_rate_model.dart';
import 'package:ALfit/models/core/slot_model.dart';
import 'package:ALfit/models/core/to_model.dart';
import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/models/core/user_region.dart';
import 'package:ALfit/models/core/work_detail_model.dart';
import 'package:ALfit/models/ui/invite_accept_readiness.dart';
import 'package:ALfit/models/ui/invite_capacity_state.dart';
import 'package:ALfit/providers/notification_provider.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/screens/common/job_posting_reads.dart';
import 'package:ALfit/screens/common/job_posting_screen.dart';
import 'package:ALfit/services/tax_identity_service.dart';
import 'package:ALfit/services/work_type_guide_resolver.dart';
import 'package:ALfit/theme/app_colors.dart';
import 'package:ALfit/theme/role_theme.dart';
import 'package:ALfit/utils/identity_identifier.dart';
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

const _kUid = 'u1';
const _bizId = 'biz1';
const _bizName = '평택 서정동 물류센터';
const _longBiz = '강남구 테헤란로 제2물류센터 야간 상하차 전용 창고'; // CP01 인계
const _title = '평택 물류센터 단기 근무자 모집';
const _desc = '상품 피킹과 포장, 상하차 보조 업무예요. 첫 근무 전 10분 안전 교육이 있어요.';
const _window = '2026-11-12 KST 02:30–21:30';

/// 세무 미리 받기 나이(reads.now)만 고정한다 — 화면·모델의 DateTime.now 는 실제 시각 그대로다(지시 §2).
final _readsNow = DateTime.utc(2026, 11, 12, 3); // 2026-11-12 12:00 KST

/// KST 달력일 자정 instant — 운영 데이터(slot.date = KST 자정)와 같은 표현.
DateTime _kstDay(int month, int day) => DateTime.utc(2026, month, day).subtract(const Duration(hours: 9));

/// 지원자 — 서류 준비 완료(bankbook=false 면 통장사본만 없음 → `지원 준비하기`).
class _P extends UserProvider {
  _P({this.bankbook = true});
  final bool bankbook;
  @override
  UserModel? get currentUser => UserModel(
        uid: _kUid,
        username: _kUid,
        name: '김지원',
        email: '$_kUid@alfit.local',
        role: UserRole.USER,
        homeRegion: const UserRegion(province: '경기도', city: '평택시'),
        accountStatus: 'active',
        passVerifiedAt: DateTime(2026, 9, 1),
        idCardImagePath: 'id_cards/$_kUid/front.jpg',
        isIdVerified: true,
        bankName: '국민은행',
        accountNumber: '000000000000',
        accountHolder: '김지원',
        bankbookImagePath: bankbook ? 'bankbooks/$_kUid/b.jpg' : null,
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
}

WorkDetailData _w(String id, String type, String start, String end, int wage, String wageType, int req,
        {int breakMin = 0, String? pay, String tax = InsuranceRateModel.typeNone, bool night = false}) =>
    WorkDetailData(
      wdId: id,
      workType: type,
      workTypeIcon: 'box',
      workTypeColor: '#000000',
      workTypeBackgroundColor: '#FFFFFF',
      wage: wage,
      wageType: wageType,
      requiredCount: req,
      startTime: start,
      endTime: end,
      order: 0,
      breakMinutes: breakMin,
      payScheduleType: pay,
      taxDeductionType: tax,
      nightIncluded: night,
    );

// 임금 3종·휴게·야간·지급 방식·공제 — 원천 그대로(새 총액 계산 0).
final _pick = _w('wdA', '피킹', '09:00', '18:00', 13000, 'hourly', 5,
    breakMin: 60, pay: 'next_day', tax: InsuranceRateModel.typeFreelancer33);
final _load = _w('wdB', '상하차', '13:00', '22:00', 120000, 'daily', 3, breakMin: 60);
final _night = _w('wdC', '야간 분류', '22:00', '06:00', 150000, 'daily', 2, breakMin: 60, night: true);
final _office = _w('wdD', '사무 보조', '09:00', '18:00', 2500000, 'monthly', 1, breakMin: 60);

SlotModel _slot(String id, DateTime date, List<WorkDetailData> wds) => SlotModel(
      id: id,
      toId: 'to1',
      date: date,
      workDetails: wds,
      status: SlotStatus.open,
      confirmedCount: 0,
      createdAt: DateTime(2026, 11, 1),
    );

final _s16 = _slot('s16', _kstDay(11, 16), [_pick, _load]); // 월
final _s20 = _slot('s20', _kstDay(11, 20), [_pick, _night]); // 금
final _s21 = _slot('s21', _kstDay(11, 21), [_office]); // 토
final _s05 = _slot('s05', _kstDay(11, 5), [_pick, _load]); // 지난 날(필터로 빠짐)

TOModel _to({String status = TOStatus.active, String businessName = _bizName}) => TOModel(
      id: 'to1',
      businessId: _bizId,
      businessName: businessName,
      type: 'flex',
      title: _title,
      description: _desc,
      creatorUID: 'admin1',
      status: status,
      deadlineType: 'NONE',
      hoursBeforeStart: 0,
      workDetails: const [],
      totalRequired: 8,
      totalConfirmed: 0,
      totalPending: 0,
      isPublished: true,
      publishMode: 'immediate',
      createdAt: DateTime(2026, 11, 1),
      statusUpdatedAt: DateTime(2026, 11, 1),
    );

BusinessModel _business({String name = _bizName}) => BusinessModel(
      id: _bizId,
      name: name,
      ownerId: 'admin1',
      businessNumber: '000-00-00000',
      address: '경기도 평택시 서정동 123',
      detailAddress: '물류동 2층',
      category: '물류',
      subCategory: '창고 작업',
      isApproved: true,
      createdAt: DateTime(2025),
      phone: '0311234567',
      oneLineIntro: '상하차·분류 전문 물류센터예요',
      nearestStation: '서정리역',
      walkingMinutes: 10,
      busInfo: '1-1번 서정리역 정류장 하차',
      precautions: ['편한 운동화', '작업 장갑 필수', '신분증 지참'].join(String.fromCharCode(10)),
      parkingAvailable: true,
      mealsProvided: const ['중식'],
      facilities: const ['휴게실'],
    );

ApplicationModel _app(String status, WorkDetailData wd, SlotModel slot,
        {InviteCapacityState cap = InviteCapacityState.unknown,
        InviteAcceptReadiness ready = InviteAcceptReadiness.unknown,
        DateTime? invitedAt}) =>
    ApplicationModel(
      id: 'app_${wd.wdId}',
      toId: 'to1',
      slotId: slot.id,
      wdId: wd.wdId,
      uid: _kUid,
      businessId: _bizId,
      businessName: _bizName,
      toTitle: _title,
      status: status,
      selectedWorkType: wd.workType,
      startTime: wd.startTime,
      endTime: wd.endTime,
      wage: wd.wage,
      wageType: wd.wageType,
      workDate: slot.date,
      appliedAt: DateTime.utc(2026, 11, 10, 1),
      invitedAt: invitedAt,
      workInstanceCapacityState: cap,
      inviteAcceptReadiness: ready,
    );

typedef _Fx = ({
  TOModel to,
  BusinessModel business,
  List<WorkDetailModel> master,
  List<SlotModel> slots,
  bool slotsFail,
  DateTime? slotDate,
  List<ApplicationModel> myApps,
  ApplicationModel? myApplication,
  bool bankbook,
});

_Fx _fixture(String state) {
  _Fx fx({
    TOModel? to,
    BusinessModel? business,
    List<WorkDetailModel> master = const [],
    List<SlotModel>? slots,
    bool slotsFail = false,
    DateTime? slotDate,
    List<ApplicationModel> myApps = const [],
    ApplicationModel? myApplication,
    bool bankbook = true,
  }) =>
      (
        to: to ?? _to(),
        business: business ?? _business(),
        master: master,
        slots: slots ?? [_s16],
        slotsFail: slotsFail,
        slotDate: slotDate,
        myApps: myApps,
        myApplication: myApplication,
        bankbook: bankbook,
      );
  switch (state) {
    case 'normal':
      return fx(slotDate: _s16.date);
    case 'multi':
      return fx(
          to: _to(businessName: _longBiz),
          business: _business(name: _longBiz),
          slots: [_s16, _s20, _s21],
          slotDate: _s16.date);
    case 'full':
      return fx(to: _to(status: TOStatus.full), slotDate: _s16.date);
    case 'ended':
      // 지난 날짜 슬롯은 load 필터로 빠지고(T11), 공고 상태 EXPIRED 가 머리·CTA·카드를 닫는다(T11 '모집중' 함정 회피).
      return fx(to: _to(status: TOStatus.expired), master: [_pick, _load], slots: [_s05]);
    case 'document':
      return fx(slotDate: _s16.date, bankbook: false);
    case 'applied':
      return fx(slotDate: _s16.date, myApps: [_app('PENDING', _pick, _s16)]);
    case 'invited':
      final inv = _app('INVITED', _pick, _s16,
          cap: InviteCapacityState.available,
          ready: InviteAcceptReadiness.ready,
          invitedAt: DateTime.utc(2026, 11, 11, 15, 30)); // 11-12 00:30 KST(+24h 가 실행 구간 뒤)
      return fx(myApps: [inv], myApplication: inv);
    default: // slotError
      return fx(slotsFail: true);
  }
}

JobPostingReads _reads(_Fx fx, Map<String, int> calls) => JobPostingReads(
      taxStatus: () async {
        calls['tax'] = (calls['tax'] ?? 0) + 1;
        return const TaxIdentityStatus(
          registered: true,
          identifierType: 'RRN',
          collectionEnabled: false,
          documentMatch: DocFieldOutcome.unassessed,
          documentMatchCurrent: false,
          loadFailed: false,
        );
      },
      now: () => _readsNow,
      toOrFailure: (id) async {
        calls['to'] = (calls['to'] ?? 0) + 1;
        return (to: fx.to, failed: false);
      },
      workDetails: (id) async {
        calls['workDetails'] = (calls['workDetails'] ?? 0) + 1;
        return fx.master;
      },
      businessById: (id) async {
        calls['business'] = (calls['business'] ?? 0) + 1;
        return fx.business;
      },
      slots: (id, {bool visibleOnly = true}) async {
        calls['slots'] = (calls['slots'] ?? 0) + 1;
        if (fx.slotsFail) throw StateError('CP05 LOCAL 근무일 조회 실패 fixture');
        return fx.slots;
      },
      myApplications: (uid) async {
        calls['myApps'] = (calls['myApps'] ?? 0) + 1;
        return fx.myApps;
      },
      workTypeCatalog: (id) async {
        calls['catalog'] = (calls['catalog'] ?? 0) + 1;
        return WorkTypeCatalog.empty;
      },
      applicationOnce: (id) async {
        calls['applicationOnce'] = (calls['applicationOnce'] ?? 0) + 1;
        return null;
      },
    );

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

// ── 실행량(CP05 상한: 사례·mount 16 · 물리탭+의미 dispatch 28 · scroll/drag/ensureVisible 16 · pump+mount 1000 · PNG 10쌍) ──
int _mounts = 0, _pumps = 0, _pngs = 0, _taps = 0, _actions = 0, _scrolls = 0;
final _cases = <String>{};
final _diag = Expando<String>('cp05-diag');

typedef _V = ({String id, Size size, double scale});
const _V _w0 = (id: 'W', size: Size(390, 844), scale: 1.0);
const _V _b0 = (id: 'B', size: Size(320, 640), scale: 2.0);

void main() {
  final phase = vqPhase ?? '';
  final env = Platform.environment;
  final meta = env['CP05_META'] ?? '';
  final after = phase == 'after';
  test('CP05 실행 조건', () {
    expect(phase == 'before' || phase == 'after', isTrue, reason: 'DU1_VQ_PHASE=before|after');
    expect(env['DU1_VQ_DATE'], '2026-11-12', reason: '실행일(실제 시각 구간의 날짜)');
    expect((env['DU1_VQ_RUN'] ?? '').isNotEmpty, isTrue);
    expect((env['DU1_VQ_OUT'] ?? '').contains('cp05-job-detail'), isTrue);
    expect(meta.contains('runner='), isTrue, reason: 'CP05_META(runner SHA 포함)');
    final now = DateTime.now();
    expect(now.timeZoneOffset, const Duration(hours: 9), reason: '기기 offset +09:00');
  });
  setUp(() => SharedPreferences.setMockInitialValues({}));
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

  Future<GlobalKey> open(WidgetTester t, _V v, _Fx fx, Map<String, int> calls) async {
    final key = GlobalKey();
    t.view.physicalSize = v.size;
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    await t.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<UserProvider>(create: (_) => _P(bankbook: fx.bankbook)),
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
          home: JobPostingScreen(
            to: fx.to,
            workDetails: fx.master,
            business: fx.business,
            slotDate: fx.slotDate,
            myApplication: fx.myApplication,
            reads: _reads(fx, calls),
          ),
        ),
      ),
    ));
    _mounts++;
    await settle(t, 25);
    return key;
  }

  // ── 찾기·측정 ──
  Finder plain(String s) => find.byWidgetPredicate((w) => w is Text && TextLayout.plain(w.data ?? '') == s);
  Finder plainRich(String s) =>
      find.byWidgetPredicate((w) => w is Text && w.textSpan != null && TextLayout.plain(w.textSpan!.toPlainText()) == s);
  Finder semLabel(String s) => find.byWidgetPredicate((w) => w is Semantics && w.properties.label == s);
  /// receiver 의미 node — container Semantics 만(안쪽 Text 가 같은 semanticsLabel 로 만드는 Semantics 제외, CP04 감사 채택 방식).
  Finder semRecv(String s) => find.byWidgetPredicate((w) => w is Semantics && w.container && w.properties.label == s);
  RenderParagraph para(WidgetTester t, Finder text) =>
      t.renderObject<RenderParagraph>(find.descendant(of: text, matching: find.byType(RichText)).first);
  SemanticsNode node(WidgetTester t, Finder f) => t.semantics.find(f);
  final ctl = RegExp('[${String.fromCharCode(0x2060)}${String.fromCharCode(0x200B)}${String.fromCharCode(0x00A0)}]');

  Map<String, Object?> textRec(WidgetTester t, String s) {
    final f = plain(s);
    final n = f.evaluate().length;
    if (n == 0) return {'text': s, 'count': 0};
    final r = t.getRect(f.first);
    final rp = para(t, f.first);
    final st = rp.text.style;
    return {
      'text': s, 'count': n, 'rect': [r.left, r.top, r.width, r.height], 'exceeded': rp.didExceedMaxLines,
      'size': st?.fontSize, 'weight': st?.fontWeight?.value, 'color': st?.color?.toARGB32().toRadixString(16),
    };
  }

  bool hitAt(WidgetTester t, Offset p, Finder receiver) {
    final ro = t.renderObject(receiver);
    final hit = HitTestResult();
    WidgetsBinding.instance.hitTestInView(hit, p, t.view.viewId);
    return hit.path.any((e) => identical(e.target, ro));
  }

  void log(String id, Map<String, Object?> m) {
    // ignore: avoid_print
    print('CP05-MEASURE $id ${jsonEncode(m)}');
  }

  void judgeErrors(String id, List<FlutterErrorDetails> errs) {
    final lines = [
      for (final e in errs)
        '${e.exceptionAsString().split(String.fromCharCode(10)).first} @ ${RegExp(r'[A-Za-z_]+[.]dart:[0-9]+:[0-9]+').allMatches(_diag[e] ?? '').map((x) => x.group(0)).toSet().join(',')}',
    ];
    // ignore: avoid_print
    print('CP05-ERRORS $id ${jsonEncode(lines)}');
    if (after) expect(lines, isEmpty, reason: '$id 렌더 오류 0');
  }

  Finder vScroll() => find.descendant(of: find.byType(CustomScrollView), matching: find.byType(Scrollable)).first;
  double vOffset(WidgetTester t) => t.state<ScrollableState>(vScroll()).position.pixels;

  Future<void> shot(WidgetTester t, GlobalKey key, String id, _V v, String fixture, {required String frame}) async {
    await vqCapture(t, key, id, conditions: {
      'id': id, 'phase': phase, 'fixture': fixture, 'viewport': '${v.size.width.toInt()}x${v.size.height.toInt()}', 'dpr': 1.0,
      'textScaler': v.scale, 'locale': 'ko_KR', 'realNow': DateTime.now().toIso8601String(),
      'realNowUtc': DateTime.now().toUtc().toIso8601String(), 'window': _window,
      'fixtureInput': '열림 근무일 2026-11-16·20·21 KST, 종료 2026-11-05 KST, reads.now 2026-11-12 12:00 KST(세무 나이만), 화면·모델 now 미주입',
      'date': env['DU1_VQ_DATE'], 'run': env['DU1_VQ_RUN'], 'meta': meta, 'frame': frame, 'offset': vOffset(t),
      'semantics': 'ensureSemantics 켬', 'fonts': 'NotoSansKR Regular+Bold(Roboto 별칭) · FlutterTest=Regular · MaterialIcons(SDK)',
    });
    if (vqEnabled) _pngs++;
  }

  /// 대상을 viewport 안 지정 위치(기본 가운데)로 데려온다(scroll 1). 기본 ensureVisible(맨 위 정렬)은 고정 앱바 밑으로
  ///   보내 탭이 앱바에 떨어지거나 가려진 채 '도달'로 잴 수 있다. CustomScrollView 는 멀리 벗어난 의미 node 를 트리에서
  ///   빼므로 의미 node 검사·dispatch 전에도 이 함수로 화면 안에 둔다.
  Future<void> reach(WidgetTester t, Finder f, {double alignment = 0.5}) async {
    await Scrollable.ensureVisible(t.element(f.first), alignment: alignment);
    _scrolls++;
    await settle(t, 3);
  }

  /// 고정 앱바 아래~viewport 아래 사이(실제로 보이는 본문 영역).
  Rect bodyRect(WidgetTester t) {
    final vr = t.getRect(find.descendant(of: find.byType(CustomScrollView), matching: find.byType(Scrollable)).first);
    final bar = t.getRect(find.byType(AppBar).first);
    return Rect.fromLTRB(vr.left, bar.bottom > vr.top ? bar.bottom : vr.top, vr.right, vr.bottom);
  }

  /// 화면 안(고정 하단 바·시트 등)에 이미 있는 물리 receiver 를 누른다.
  Future<void> tapAt(WidgetTester t, Finder f) async {
    await t.tap(f.first);
    _taps++;
    await settle(t, 6);
  }

  /// 스크롤 본문 안의 receiver — 먼저 보이게 한 뒤(scroll 1) 누른다(tap 1). 보이지 않는 좌표 탭이 하단 바에 떨어지는 것을 막는다.
  Future<void> reachTap(WidgetTester t, Finder f) async {
    final r = t.getRect(f.first);
    final body = bodyRect(t);
    final visible = r.top >= body.top - 0.5 && r.bottom <= body.bottom + 0.5;
    if (!visible) await reach(t, f);
    await tapAt(t, f);
  }

  Finder typed<T extends Widget>() => find.byWidgetPredicate((w) => w is T); // .icon 생성자의 하위 타입까지

  /// 대상 rect 가 실제로 보이는 본문(앱바 아래~viewport 아래) 안에 있는가.
  bool inBody(WidgetTester t, Finder f) {
    final r = t.getRect(f.first);
    final body = bodyRect(t);
    return r.top >= body.top - 0.5 && r.bottom <= body.bottom + 0.5;
  }

  /// 의미 node 검사 전 — 본문 밖이면 가운데로 데려온다(필요할 때만 scroll 1).
  Future<void> ensureNode(WidgetTester t, Finder f) async {
    if (!inBody(t, f)) await reach(t, f);
  }

  /// B(좁은 폭·큰 글자)는 의미 node 대신 위젯 의미 속성으로 같은 구성을 본다(node 검사는 W, B 는 receiver·도달 R).
  void expectSemProps(WidgetTester t, Finder f, String id, {required String label, bool? selected, bool? enabled}) {
    final p = t.widget<Semantics>(f).properties;
    expect(p.label, label, reason: '$id 의미 이름(위젯)');
    expect(p.button, isTrue, reason: '$id button(위젯)');
    expect(p.onTap, isNotNull, reason: '$id onTap(위젯)');
    if (selected != null) expect(p.selected, selected, reason: '$id selected(위젯)');
    if (enabled != null) expect(p.enabled, enabled, reason: '$id enabled(위젯)');
  }

  Future<void> dispatchTap(WidgetTester t, Finder f) async {
    final n = node(t, f);
    n.owner!.performAction(n.id, SemanticsAction.tap);
    _actions++;
    await settle(t, 6);
  }

  /// 최종 의미 node 의 label·button·tap(·selected·enabled).
  void expectNode(WidgetTester t, Finder f, String id,
      {required String label, required bool tap, bool? selected, bool? enabled}) {
    final d = node(t, f).getSemanticsData();
    expect(d.label, label, reason: '$id 의미 이름 원문');
    expect(ctl.hasMatch(d.label), isFalse, reason: '$id 의미 이름 제어문자 0');
    expect(d.flagsCollection.isButton, isTrue, reason: '$id button');
    expect(d.hasAction(SemanticsAction.tap), tap, reason: '$id tap action');
    if (selected != null) expect(d.flagsCollection.isSelected, selected, reason: '$id selected');
    if (enabled != null) {
      expect(d.flagsCollection.hasEnabledState, isTrue, reason: '$id enabled 상태 있음');
      expect(d.flagsCollection.isEnabled, enabled, reason: '$id enabled');
    }
  }

  /// receiver ≥min·이 스크롤 위치에서 화면 안·중심 hit.
  void expectReceiver(WidgetTester t, Finder recv, _V v, String id, {double min = 48, bool onScreen = true}) {
    final r = t.getRect(recv);
    expect(r.width, greaterThanOrEqualTo(48), reason: '$id receiver 폭 ≥48');
    expect(r.height, greaterThanOrEqualTo(min), reason: '$id receiver 높이 ≥$min');
    if (onScreen) {
      final top = t.getRect(find.byType(Scaffold).first);
      expect(r.top >= top.top - 0.5 && r.bottom <= top.bottom + 0.5 && r.left >= -0.5 && r.right <= v.size.width + 0.5, isTrue,
          reason: '$id 화면 안');
      expect(hitAt(t, r.center, recv), isTrue, reason: '$id 중심 hit');
    }
  }

  /// [r3] 문단 span 트리에서 표시 구간 [start,end) 만 잘라 **같은 span 중첩·style 그대로** 돌려준다(상속·override 보존,
  ///   얕은 merge 로 다른 스타일을 만들지 않는다). TextSpan 이 아닌 span(placeholder 등)을 만나면 null(계측 불가).
  InlineSpan? sliceSpan(InlineSpan root, int start, int end) {
    var pos = 0;
    var unsupported = false;
    InlineSpan? walk(InlineSpan s) {
      if (s is! TextSpan) {
        unsupported = true;
        return null;
      }
      final t = s.text ?? '';
      final tStart = pos, tEnd = pos + t.length;
      pos = tEnd;
      String? part;
      if (t.isNotEmpty) {
        final a = start < tStart ? tStart : (start > tEnd ? tEnd : start);
        final b = end < tStart ? tStart : (end > tEnd ? tEnd : end);
        if (b > a) part = t.substring(a - tStart, b - tStart);
      }
      final kids = <InlineSpan>[];
      for (final ch in s.children ?? const <InlineSpan>[]) {
        final k = walk(ch);
        if (k != null) kids.add(k);
      }
      if (part == null && kids.isEmpty) return null;
      return TextSpan(text: part, style: s.style, children: kids.isEmpty ? null : kids);
    }
    final out = walk(root);
    return unsupported ? null : out;
  }

  /// 대상 낱말(공백 기준)의 글자가 같은 줄에 있는가(실제 줄상자).
  /// [r3] 실제 표시 낱말 구간(내부 U+2060 포함)의 제한 없는 한 줄 advance 폭을 이 문단의 실제 span·style·textScaler·locale·
  ///   textDirection 으로 잰다. 한 줄 제약(softWrap/ellipsis 일 때 `rp.constraints.maxWidth`, 아니면 무한)이 유한·양수이고
  ///   [r4] 정밀값 `oneLine > maxWidth`(엔진 wrap 과 같은 경계, 반올림 없음)이며 실제로 갈렸을 때만 분할을
  ///   허용하고 `exceedsLine:true`·`splitException:true`·초과량 `excess`·`band`(0 < excess ≤ 0.5) 로 기록한다.
  ///   그 밖(들어가는 낱말·계측 불가·제약 불명)은 기존대로 `hi − lo < 1.0` 을 단언한다.
  ///   진단은 단언 전에 log 로 남긴다.
  void expectWordsKept(RenderParagraph rp, String original, String id) {
    final disp = rp.text.toPlainText(includeSemanticsLabels: false);
    final idx = <int>[];
    for (var i = 0; i < disp.length; i++) {
      final c = disp.codeUnitAt(i);
      if (c != 0x2060 && c != 0x200B) idx.add(i);
    }
    final p = TextLayout.plain(disp);
    expect(p, original, reason: '$id 표시 원문 전문');
    // RenderParagraph._adjustMaxWidth 와 같은 wrap 조건: softWrap 또는 ellipsis 일 때만 constraints.maxWidth 로 줄을 나눈다.
    final wraps = rp.softWrap || rp.overflow == TextOverflow.ellipsis;
    final maxWidth = wraps ? rp.constraints.maxWidth : double.infinity;
    final constraintOk = maxWidth.isFinite && maxWidth > 0;
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
      // 실제 표시 구간: 첫 글자 ~ 마지막 글자(그 사이 결합 문자 포함).
      final rawStart = idx[at], rawEnd = idx[at + w.length - 1] + 1;
      final raw = disp.substring(rawStart, rawEnd);
      double? oneLine;
      final slice = sliceSpan(rp.text, rawStart, rawEnd);
      if (slice != null) {
        final tp = TextPainter(
          text: slice,
          textDirection: rp.textDirection,
          textScaler: rp.textScaler,
          locale: rp.locale,
        )..layout();
        oneLine = tp.maxIntrinsicWidth; // 제한 없는 한 줄 advance 폭
        tp.dispose();
      }
      final measured = oneLine != null && oneLine.isFinite && oneLine > 0;
      final exceedsLine = constraintOk && oneLine != null && oneLine.isFinite && oneLine > 0 && oneLine > maxWidth;
      final excess = (constraintOk && oneLine != null && oneLine.isFinite && oneLine > 0) ? oneLine - maxWidth : null;
      final band = excess != null && excess > 0 && excess <= 0.5;
      final lo = tops.isEmpty ? double.nan : tops.reduce((a, b) => a < b ? a : b);
      final hi = tops.isEmpty ? double.nan : tops.reduce((a, b) => a > b ? a : b);
      final split = tops.isNotEmpty && hi - lo >= 1.0;
      final splitException = exceedsLine && split;
      log('$id-word', {
        'word': w, 'raw': raw, 'plain': TextLayout.plain(raw), 'range': [rawStart, rawEnd],
        'oneLine': oneLine == null ? null : (oneLine.isFinite ? oneLine : oneLine.toString()),
        'maxWidth': maxWidth.isFinite ? maxWidth : maxWidth.toString(), 'constraintOk': constraintOk, 'measured': measured,
        'softWrap': rp.softWrap, 'overflow': rp.overflow.toString(),
        'scale1': rp.textScaler.scale(1), 'locale': rp.locale.toString(), 'direction': rp.textDirection.toString(),
        'tops': tops, 'split': split, 'exceedsLine': exceedsLine,
        'excess': excess, 'band': band, 'splitException': splitException,
      });
      expect(tops, isNotEmpty, reason: '$id 낱말 `$w` 글자 상자');
      if (!exceedsLine) {
        expect(hi - lo, lessThan(1.0), reason: '$id 낱말 `$w` 한 줄(lo=$lo hi=$hi, oneLine=$oneLine ≤ maxWidth=$maxWidth)');
      }
      from = at + w.length;
    }
  }

  /// [지시 §3.3] 중요 글자의 실제 clip — 말줄임 flag 와 별개로 잰다.
  ///   측정 단위: 공백이 아닌 글자 덩어리마다 줄 높이 상자(BoxHeightStyle.max — 잉크 아님)를 전역 좌표로 옮기고,
  ///   ① 자기 문단 상자, ② 실제로 자르는 조상(RenderClipRect/RRect/Path/Oval), ③ (viewport:true 일 때) 스크롤 viewport 와 교차한다.
  ///   반환: 위반 이름 목록(빈 목록 = 잘림 없음). 구조 rect(①②)와 실제 가시(③)를 따로 부른다.
  List<String> clipIssues(WidgetTester t, Finder text, {required bool viewport}) {
    final rp = para(t, text);
    final s = rp.text.toPlainText(includeSemanticsLabels: false);
    final runs = <TextSelection>[];
    var st = -1;
    for (var i = 0; i <= s.length; i++) {
      final ws = i == s.length || s[i] == ' ' || s[i] == String.fromCharCode(10);
      if (!ws && st < 0) st = i;
      if (ws && st >= 0) {
        runs.add(TextSelection(baseOffset: st, extentOffset: i));
        st = -1;
      }
    }
    final issues = <String>[];
    if (rp.didExceedMaxLines) issues.add('self:exceeded');
    final local = <Rect>[
      for (final sel in runs)
        for (final b in rp.getBoxesForSelection(sel, boxHeightStyle: ui.BoxHeightStyle.max)) b.toRect(),
    ];
    for (final r in local) {
      if (r.left < -0.5 || r.top < -0.5 || r.right > rp.size.width + 0.5 || r.bottom > rp.size.height + 0.5) {
        issues.add('self:box');
        break;
      }
    }
    final global = [for (final r in local) MatrixUtils.transformRect(rp.getTransformTo(null), r)];
    //   조상 탐색은 스크롤 viewport 에서 멈춘다 — 그 위(라우트·앱 수준)의 화면 크기 clip 이 스크롤로 화면 밖에 있는 글자를
    //   '잘림'으로 오판하지 않게. 구조(viewport:false)는 viewport 아래 콘텐츠 안의 clip 만, 가시(viewport:true)는 viewport 까지 본다.
    RenderObject? a = rp.parent;
    while (a != null) {
      final isViewport = a is RenderViewportBase;
      String? kind;
      if (a is RenderClipRect || a is RenderClipRRect || a is RenderClipPath || a is RenderClipOval) {
        kind = a.runtimeType.toString();
      } else if (viewport && isViewport) {
        kind = 'viewport';
      }
      if (kind != null && a is RenderBox) {
        final clip = MatrixUtils.transformRect(a.getTransformTo(null), Offset.zero & a.size);
        for (final r in global) {
          if (r.left < clip.left - 0.5 || r.top < clip.top - 0.5 || r.right > clip.right + 0.5 || r.bottom > clip.bottom + 0.5) {
            issues.add(kind);
            break;
          }
        }
      }
      if (isViewport) break;
      a = a.parent;
    }
    return issues;
  }

  /// 요율 숫자(예: `13,000`)가 줄 안에서 갈렸는가 + 그 숫자 한 줄 폭이 문단 최대 폭에 들어가는가.
  ///   한 줄 폭은 같은 문단의 병합 스타일(DefaultTextStyle+span)·실제 배율·locale 로 잰다(잉크 아님, advance 폭).
  Map<String, Object?> numberKept(RenderParagraph rp, String number) {
    final disp = rp.text.toPlainText(includeSemanticsLabels: false);
    final idx = <int>[];
    for (var i = 0; i < disp.length; i++) {
      final ch = disp.codeUnitAt(i);
      if (ch != 0x2060 && ch != 0x200B) idx.add(i);
    }
    final at = TextLayout.plain(disp).indexOf(number);
    final tops = <double>[];
    for (var k = at; k < at + number.length; k++) {
      for (final b in rp.getBoxesForSelection(TextSelection(baseOffset: idx[k], extentOffset: idx[k] + 1))) {
        tops.add(b.top);
      }
    }
    final lo = tops.reduce((a, b) => a < b ? a : b), hi = tops.reduce((a, b) => a > b ? a : b);
    TextStyle? numberStyle;
    rp.text.visitChildren((span) {
      if (span is TextSpan && span.text != null && TextLayout.plain(span.text!) == number) {
        numberStyle = span.style;
        return false;
      }
      return true;
    });
    final merged = (rp.text.style ?? const TextStyle()).merge(numberStyle);
    final tp = TextPainter(
      text: TextSpan(text: number, style: merged),
      textDirection: TextDirection.ltr,
      textScaler: rp.textScaler,
      locale: rp.locale,
    )..layout();
    final oneLine = tp.width;
    tp.dispose();
    return {
      'split': hi - lo >= 1.0,
      'oneLine': double.parse(oneLine.toStringAsFixed(1)),
      'maxWidth': double.parse(rp.constraints.maxWidth.toStringAsFixed(1)),
      'fits': oneLine <= rp.constraints.maxWidth + 0.5,
      'lines': (hi - lo) / ((rp.text.style?.fontSize ?? 14) * rp.textScaler.scale(1)),
    };
  }

  /// [C1] 문단의 **실제 글자 span 별** 유효 fontFamily.
  ///   InlineSpan 규칙대로 `자식 명시값 ?? 부모값` 으로 추적한다(`TextStyle.merge` 는 inherit:false 자식만 돌려주므로 쓰지 않는다).
  ///   시작은 Text 가 이미 병합한 RenderParagraph 루트이고, 바깥 앱 family 를 임의로 채우지 않는다. 글자가 없는 컨테이너 span 은 세지 않는다.
  List<({String path, String text, String? family})> spanFamilies(RenderParagraph rp) {
    final out = <({String path, String text, String? family})>[];
    void walk(InlineSpan s, String? parentFamily, String path) {
      final family = s.style?.fontFamily ?? parentFamily;
      if (s is TextSpan) {
        final txt = s.text;
        if (txt != null && txt.isNotEmpty) out.add((path: path, text: txt, family: family));
        final ch = s.children ?? const <InlineSpan>[];
        for (var i = 0; i < ch.length; i++) {
          walk(ch[i], family, '$path/$i');
        }
      }
    }
    walk(rp.text, null, 'r');
    return out;
  }

  /// [C1] 이 문단을 그리는 실제 Icon 위젯(문단의 가장 가까운 Icon 조상 — Icon 은 자식이 없어 다른 글자를 품지 않는다).
  Icon? owningIcon(Element paragraphElement) {
    Icon? found;
    paragraphElement.visitAncestorElements((a) {
      if (a.widget is Icon) {
        found = a.widget as Icon;
        return false;
      }
      return true;
    });
    return found;
  }

  /// [C1] span 별 판정 기록. MaterialIcons 예외는 **실제 Icon 의 IconData.codePoint 와 같은 글자**에만 준다.
  ///   일반 글자는 NotoSansKR, null·다른 family·아이콘 family 의 일반 글자는 위반.
  List<Map<String, Object?>> fontRecords(RenderParagraph rp, Icon? icon) {
    final iconChar = icon?.icon == null ? null : String.fromCharCode(icon!.icon!.codePoint);
    return [
      for (final sp in spanFamilies(rp))
        () {
          final isIcon = iconChar != null && sp.text == iconChar;
          final want = isIcon ? icon!.icon!.fontFamily : 'NotoSansKR';
          return <String, Object?>{
            'path': sp.path, 'raw': sp.text, 'plain': TextLayout.plain(sp.text), 'family': sp.family,
            'icon': isIcon ? 'Icon(0x${icon!.icon!.codePoint.toRadixString(16)})' : null, 'ok': sp.family == want,
          };
        }(),
    ];
  }

  /// [C1] 버튼 label 문단의 유효 family 를 직접 본다. 존재/관측 수와 span 기록을 **단언 전에** 남긴다(빈 finder 를 통과로 세지 않는다).
  void buttonFont(WidgetTester t, Finder label, String id, String name) {
    final count = label.evaluate().length;
    final recs = count == 0 ? const <Map<String, Object?>>[] : fontRecords(para(t, label.first), null);
    log('$id-font-button', {'name': name, 'count': count, 'spans': recs});
    expect(label, findsWidgets, reason: '$id 버튼 `$name` 이 이 상태에 있다');
    if (after) {
      expect(recs.where((r) => r['ok'] != true).toList(), isEmpty, reason: '$id 버튼 `$name` 글자 NotoSansKR(span 별)');
    }
  }

  /// 홈 안의 모든 문단: 말줄임/잘림 flag 0·실제 배율·[C1] span 별 유효 글꼴(전체 그물 — 실제 clip 은 clipIssues 가 따로 본다).
  ///   family 단언은 글리프 화소 증명이 아니다(PNG 직접 판독을 함께 한다). 진단은 단언 전에 log 로 남긴다.
  Map<String, Object?> sweepParagraphs(WidgetTester t, _V v, String id) {
    var n = 0, spans = 0;
    final bad = <String>[];
    final fontBad = <Map<String, Object?>>[];
    final families = <String, int>{};
    final all = <String>[];
    for (final e in find.byType(RichText).evaluate()) {
      final ro = e.renderObject;
      if (ro is! RenderParagraph) continue;
      final p = n++;
      if (ro.didExceedMaxLines) bad.add('exceeded:${TextLayout.plain(ro.text.toPlainText(includeSemanticsLabels: false))}');
      for (final r in fontRecords(ro, owningIcon(e))) {
        spans++;
        families['${r['family']}'] = (families['${r['family']}'] ?? 0) + 1;
        all.add('#$p/${r['path']}|${r['plain']}|${r['family']}|${r['icon'] ?? '-'}');
        if (r['ok'] != true) fontBad.add({'paragraph': p, ...r});
      }
    }
    log('$id-font', {'paragraphs': n, 'spans': spans, 'families': families, 'fontBad': fontBad, 'all': all, 'exceeded': bad});
    if (after) {
      expect(bad, isEmpty, reason: '$id 말줄임/잘림 flag 문단 0');
      expect(fontBad, isEmpty, reason: '$id 문단 span 유효 글꼴(일반 NotoSansKR·실제 아이콘 MaterialIcons)');
    }
    return {'paragraphs': n, 'spans': spans, 'families': families, 'bad': bad, 'fontBad': fontBad.length};
  }

  /// 하단 주CTA(ElevatedButton) — 보이는 원문으로 찾는다.
  Finder ctaButton(String text) => find.ancestor(of: plain(text), matching: typed<ElevatedButton>());

  final cases = <({String state, bool pngW, bool pngB, String fixture})>[
    (state: 'normal', pngW: true, pngB: true, fixture: '단기 1일(11-16 월)·업무 2(피킹 시급 13,000·휴게 1시간·익일·3.3% / 상하차 일급 120,000) · 피킹 선택 뒤'),
    (state: 'multi', pngW: true, pngB: false, fixture: '긴 사업장 · 3일(11-16 월/11-20 금/11-21 토) · 야간 분류 22:00–06:00 일급 · 사무 보조 월급 · 날짜별 선택 2'),
    (state: 'full', pngW: true, pngB: false, fixture: '공고 FULL(정원) · 슬롯 열림 · 인원 마감'),
    (state: 'ended', pngW: true, pngB: false, fixture: '공고 EXPIRED · 지난 슬롯(11-05) 필터 · 마스터 업무 2'),
    (state: 'document', pngW: true, pngB: false, fixture: '통장사본 미등록 → 지원 준비하기(시트 열고 나중에)'),
    (state: 'applied', pngW: true, pngB: false, fixture: '피킹 PENDING 기지원 · 상하차 선택 가능'),
    (state: 'invited', pngW: true, pngB: false, fixture: '피킹 INVITED(수용 가능·준비됨) · 내 지원에서 진입'),
    (state: 'slotError', pngW: true, pngB: false, fixture: '근무일 조회 실패 · 마스터 업무 0'),
  ];

  for (final v in const [_w0, _b0]) {
    for (final c in cases) {
      testWidgets('CP05 ${c.state} ${v.id}', (t) async {
        _cases.add('${c.state}-${v.id}');
        final semH = t.ensureSemantics();
        try {
          await collecting(t, (errs) async {
            final id = '${c.state}-${v.id}';
            final fx = _fixture(c.state);
            final calls = <String, int>{};
            final key = await open(t, v, fx, calls);
            final g = v.id == 'W' ? 20.0 : 16.0;

            // ── PNG·자연 전환(before·after 같은 물리 동작) ──
            //   W normal 만 선택 뒤 offset0(V 기준 프레임, 주CTA 활성), 나머지 PNG 는 mount 직후 offset0(전환 전)이다.
            final pngHere = (v.id == 'W' && c.pngW) || (v.id == 'B' && c.pngB);
            final pngAfterSelect = c.state == 'normal' && v.id == 'W';
            if (pngHere && !pngAfterSelect) await shot(t, key, 'CP05-${c.state}-${v.id}', v, c.fixture, frame: 'offset0');
            if (c.state == 'normal') {
              // 선택 전 → 피킹 `선택` 물리 탭 → 선택 후(한 mount).
              final pre = {'선택': plain('선택').evaluate().length, '선택됨': plain('선택됨').evaluate().length};
              // [C1] 선택 전 상태의 버튼 글자 글꼴 — 비활성 주CTA·`선택`·`업무 자세히 보기`(존재 먼저, 추가 mount/tap/scroll 0).
              if (after) {
                buttonFont(t, plain('지원할 업무를 선택해 주세요'), '$id-pre', '주CTA(비활성)');
                buttonFont(t, plain('선택'), '$id-pre', '선택');
                buttonFont(t, plain('업무 자세히 보기'), '$id-pre', '업무 자세히 보기');
              }
              await reachTap(t, plain('선택'));
              log('$id-select', {'pre': pre, 'post': {'선택': plain('선택').evaluate().length, '선택됨': plain('선택됨').evaluate().length}});
            }
            if (c.state == 'multi') {
              await reachTap(t, plain('선택')); // 11-16 피킹
              await reachTap(t, plain('11/20')); // 열람일만 바꾼다
              log('$id-view20', {'선택': plain('선택').evaluate().length, '선택됨': plain('선택됨').evaluate().length});
              await reachTap(t, plain('선택').last); // 11-20 야간 분류(두 번째 카드)
            }
            if (pngAfterSelect) {
              // 선택 뒤 offset0 으로 되돌려 첫 화면을 찍는다(스크롤 위치 직접 지정 — 드래그·탭 아님, scroll 1 로 센다).
              if (vOffset(t) != 0) {
                t.state<ScrollableState>(vScroll()).position.jumpTo(0);
                _scrolls++;
                await settle(t, 2);
              }
              await shot(t, key, 'CP05-${c.state}-${v.id}', v, c.fixture, frame: 'offset0-selected');
            }
            if (c.state == 'normal' && v.id == 'B') {
              // B 업무 카드 도달 프레임(두 phase 같은 동작) — 업무명을 앱바 바로 아래(20%)에 두어 시간·요율 덩어리를 본다.
              await reach(t, plain('피킹'), alignment: 0.2);
              await shot(t, key, 'CP05-normal-B-card', v, c.fixture, frame: 'card-reach');
              if (after) {
                // [r2] 위 `피킹` 20% 프레임은 before 비교용 PNG 프레임이다(카드 전체 동시 가시 계약 아님).
                //   after 에서만 요율 라벨을 가운데로 데려온 뒤(scroll 1) 시간·라벨·숫자+단위의 실제 가시(앱바 아래 본문 안 +
                //   viewport 교차)와 낱말을 같은 오차로 단언한다. 두 프레임의 offset/body/세 대상 rect 를 단언 전에 남긴다.
                final targets = <String, Finder>{
                  '13,000원': plainRich('13,000원'), '09:00–18:00': plain('09:00–18:00'), '시급 · 익일': plain('시급 · 익일'),
                };
                Map<String, Object?> frame() => {
                      'offset': vOffset(t), 'body': bodyRect(t).toString(),
                      for (final e in targets.entries) e.key: t.getRect(e.value.first).toString(),
                    };
                log('${c.state}-B-card-frame', {'pngFrame': frame()});
                await reach(t, plain('시급 · 익일'));
                final checks = <String, Object?>{
                  for (final e in targets.entries)
                    e.key: {'inBody': inBody(t, e.value), 'viewportClip': clipIssues(t, e.value.first, viewport: true)},
                };
                log('${c.state}-B-card-frame', {'measureFrame': frame(), 'checks': checks});
                for (final e in targets.entries) {
                  expect(inBody(t, e.value), isTrue, reason: '${c.state}-B `${e.key}` 본문 안(앱바에 가림 0)');
                  expect(clipIssues(t, e.value.first, viewport: true), isEmpty, reason: '${c.state}-B `${e.key}` 도달·잘림 0');
                }
                expectWordsKept(para(t, plain('시급 · 익일').first), '시급 · 익일', '${c.state}-B 요율 라벨 낱말');
              }
            }

            final rec = <String, Object?>{
              'state': c.state, 'calls': Map.of(calls),
              for (final s in [
                '일자리 상세', _bizName, _longBiz, '물류 · 창고 작업', '단기 근무', '익일', _title, '모집중', '인원 마감', '모집 종료',
                '근무 날짜', '날짜를 고르면 그날의 업무가 보여요', '근무할 날짜를 선택하세요', '어떤 날짜에 지원할 수 있어요',
                '피킹', '상하차', '야간 분류', '사무 보조', '09:00–18:00', '13:00–22:00', '22:00–06:00', '(휴게 1시간)', '실근무 8시간',
                '시급 · 익일', '일급', '월급', '13,000', '3.3% 원천징수', '선택', '선택됨', '업무 자세히 보기',
                '근태 인정 기준', '준비사항', '시설 및 환경', '찾아오는 길', '근무 장소', '경기도 평택시 서정동 123',
                '지원하기', '지원할 업무를 선택해 주세요', '지원할 업무를 선택해주세요', '지원 준비하기', '모집 인원이 찼어요',
                '마감된 공고예요', '마감된 공고입니다', '지금 지원할 수 있는 업무가 없어요', '1개 업무 선택됨', '2개 업무 선택됨',
                '현재 선택 가능한 근무 날짜가 없습니다.', '지원완료', '초대 수락',
              ])
                s: textRec(t, s),
              'sweep': sweepParagraphs(t, v, id),
            };
            log('$id-open', rec);

            if (after) {
              // ── 앱바·머리(정밀 §4·§8·§9) ──
              //   같은 글자가 지원 요약·초대 카드에도 나올 수 있다 — 머리는 트리 순서 첫 번째(.first)로 잡는다.
              expect(plain('일자리 상세'), findsOneWidget, reason: '$id 화면 타이틀');
              final bizText = c.state == 'multi' ? _longBiz : _bizName;
              expect(plain(bizText), findsWidgets, reason: '$id 사업장명');
              final biz = plain(bizText).first;
              expect(para(t, biz).text.style?.fontSize, 28, reason: '$id 사업장 28');
              expect(para(t, biz).text.style?.fontWeight, FontWeight.w700);
              expect(t.getRect(biz).left, closeTo(g, 0.5), reason: '$id 사업장 left = gutter $g(Text 상자)');
              expect(semLabel(bizText), findsWidgets, reason: '$id 사업장 의미 이름 원문');
              expectWordsKept(para(t, biz), bizText, '$id 사업장 낱말');
              final cat = plain('물류 · 창고 작업');
              expect(cat, findsOneWidget, reason: '$id 실제 분류 필(업종·세부 업종)');
              expect(para(t, cat).text.style?.color, AppColors.conceptNavy, reason: '$id 분류 필 글자 #25325B');
              expect(para(t, cat).text.style?.fontSize, 13);
              final catBox = t.widget<Container>(find.ancestor(of: cat, matching: find.byType(Container)).first);
              expect((catBox.decoration as BoxDecoration?)?.color, AppColors.conceptCategoryBg, reason: '$id 분류 필 바탕 #E4ECFD');
              expect(t.getRect(cat).bottom < t.getRect(biz).top, isTrue, reason: '$id 분류 필 → 사업장(시안 순서)');
              expect(plain('단기 근무'), findsWidgets, reason: '$id 근무 유형 필');
              expect(plain(_title), findsWidgets);
              final title = plain(_title).first;
              expect(para(t, title).text.style?.fontSize, 16);
              expect(t.getRect(title).top > t.getRect(biz).bottom, isTrue, reason: '$id 사업장 → 공고 제목');
              final status = switch (c.state) { 'full' => '인원 마감', 'ended' => '모집 종료', _ => '모집중' };
              expect(plain(status), findsWidgets, reason: '$id 머리 상태 `$status`');
              expect(plain(_desc), findsOneWidget, reason: '$id 공고 설명 전문');

              // ── 날짜(열람 문맥) ──
              final hasDates = !['ended', 'slotError', 'invited'].contains(c.state);
              if (hasDates) {
                final sec = plain('근무 날짜');
                expect(sec, findsOneWidget, reason: '$id 날짜 섹션 제목');
                expect(para(t, sec).text.style?.fontSize, 20);
                expect(t.getRect(sec).left, closeTo(g, 0.5), reason: '$id 날짜 제목 left = gutter');
                expect(plain('날짜를 고르면 그날의 업무가 보여요'), findsOneWidget, reason: '$id 열람 문맥(열람≠선택)');
                expect(plain('근무할 날짜를 선택하세요'), findsNothing);
                final d16 = semRecv('11월 16일 월요일, 업무 2개');
                expect(d16, findsOneWidget, reason: '$id 11/16 칩 의미 node');
                // multi 는 열람일을 11/20 로 바꾼 뒤라 11/16 은 선택 아님.
                if (v.id == 'W') {
                  await ensureNode(t, d16);
                  expectNode(t, d16, '$id 11/16 칩', label: '11월 16일 월요일, 업무 2개', tap: true,
                      selected: c.state != 'multi', enabled: true);
                } else {
                  expectSemProps(t, d16, '$id 11/16 칩', label: '11월 16일 월요일, 업무 2개',
                      selected: c.state != 'multi', enabled: true);
                }
                final chipGd = find.descendant(of: d16, matching: find.byType(GestureDetector)).first;
                expect(t.widget<Semantics>(d16).properties.onTap == t.widget<GestureDetector>(chipGd).onTap, isTrue,
                    reason: '$id 칩 의미 onTap = 물리 onTap(같은 콜백)');
                expectReceiver(t, d16, v, '$id 11/16 칩', onScreen: false);
              }
              if (c.state == 'ended') {
                expect(plain('현재 선택 가능한 근무 날짜가 없습니다.'), findsOneWidget, reason: '$id 날짜 없음(오류 아님)');
                expect(para(t, plain('현재 선택 가능한 근무 날짜가 없습니다.')).text.style?.color, AppColors.textSecondary);
              }
              if (c.state == 'slotError') {
                final err = plain('근무 일정을 불러오지 못했습니다.${String.fromCharCode(10)}잠시 후 다시 시도해주세요.');
                expect(err, findsOneWidget, reason: '$id 조회 실패 문구(날짜 없음과 구별)');
                expect(para(t, err).text.style?.color, AppColors.errorDark, reason: '$id 조회 실패 errorDark');
                expect(plain('현재 선택 가능한 근무 날짜가 없습니다.'), findsNothing);
              }

              // ── 업무 카드(시간 20·요율 30/16·conceptValue) ──
              if (c.state != 'slotError' && c.state != 'invited') {
                final time = plain('09:00–18:00');
                expect(time, findsWidgets, reason: '$id 피킹 시간(en dash)');
                expect(para(t, time.first).text.style?.fontSize, 20, reason: '$id 시간 20');
                expect(para(t, time.first).text.style?.fontWeight, FontWeight.w700);
                expect(plain('09:00~18:00'), findsNothing, reason: '$id 옛 물결 시간 0');
                final rate = plainRich('13,000원');
                expect(rate, findsWidgets, reason: '$id 피킹 요율 원천 그대로');
                final spans = (t.widget<Text>(rate.first).textSpan! as TextSpan).children!.cast<TextSpan>();
                expect(TextLayout.plain(spans.first.text ?? ''), '13,000');
                expect(spans.first.style?.fontSize, 30, reason: '$id 요율 30');
                expect(spans.first.style?.color, AppColors.brand, reason: '$id 요율 brand');
                expect(spans.last.text, '원');
                expect(spans.last.style?.fontSize, 16, reason: '$id 단위 16');
                expect(semLabel('시급 13,000원'), findsWidgets, reason: '$id 요율 의미 이름(유형+원천 금액)');
                final valueBox = t.widget<Container>(find.ancestor(of: rate.first, matching: find.byType(Container)).first);
                expect((valueBox.decoration as BoxDecoration?)?.color, AppColors.brandSurface, reason: '$id conceptValue #EEF2FF');
                expect(plain('시급 · 익일'), findsWidgets, reason: '$id 요율 유형·지급 방식 라벨');
                expect(plain('3.3% 원천징수'), findsWidgets, reason: '$id 공제 방식 보존');
                expect(plain('(휴게 1시간)'), findsWidgets, reason: '$id 휴게 원천');
                expect(plain('실근무 8시간'), findsWidgets, reason: '$id 실근무');
                expect(plain('52,000원'), findsNothing, reason: '$id 새 예상 총액 0');
                expect(find.textContaining('예상'), findsNothing, reason: '$id 예상 총액 문구 0');
                // 업무별 다른 요율(일급) — normal 은 같은 날 상하차, multi 는 열람일 11/20 의 야간 분류.
                if (c.state == 'normal') expect(plainRich('120,000원'), findsOneWidget, reason: '$id 업무별 다른 요율(상하차 일급)');
                if (c.state == 'multi') expect(plainRich('150,000원'), findsOneWidget, reason: '$id 업무별 다른 요율(야간 일급)');
                if (c.state == 'normal' || c.state == 'multi') expect(plain('일급'), findsWidgets);
              }

              // ── 선택(열람 ≠ 선택)·receiver·의미 ──
              if (c.state == 'normal') {
                final sel = semRecv('피킹 선택됨');
                expect(sel, findsOneWidget, reason: '$id 피킹 선택됨 의미 node');
                if (v.id == 'W') {
                  await ensureNode(t, sel);
                  expectNode(t, sel, '$id 피킹 선택됨', label: '피킹 선택됨', tap: true, selected: true);
                } else {
                  expectSemProps(t, sel, '$id 피킹 선택됨', label: '피킹 선택됨', selected: true);
                }
                expectReceiver(t, sel, v, '$id 피킹 선택됨', onScreen: false);
                final sw = t.widget<Semantics>(sel);
                final btn = t.widget<ElevatedButton>(find.descendant(of: sel, matching: typed<ElevatedButton>()).first);
                expect(sw.properties.onTap == btn.onPressed, isTrue, reason: '$id 의미 onTap = 버튼 onPressed(같은 콜백)');
                expect(plain('1개 업무 선택됨'), findsOneWidget, reason: '$id 선택 수');
                // [C1] 선택 뒤 상태의 버튼 글자 글꼴 — 활성 주CTA·`선택됨`(존재 먼저).
                buttonFont(t, plain('지원하기'), '$id-post', '주CTA(활성)');
                buttonFont(t, plain('선택됨'), '$id-post', '선택됨');
                final cta = ctaButton('지원하기');
                expect(cta, findsOneWidget, reason: '$id 주CTA 지원하기');
                expect(t.widget<ElevatedButton>(cta).onPressed, isNotNull, reason: '$id 주CTA 활성');
                expectReceiver(t, cta, v, '$id 주CTA', min: 52);
                final other = semRecv('상하차 선택');
                if (v.id == 'W') {
                  // 의미 dispatch — 상하차 선택(같은 날 1개 규칙: 피킹 해제, 수는 그대로 1)
                  await ensureNode(t, other);
                  expectNode(t, other, '$id 상하차 선택', label: '상하차 선택', tap: true, selected: false);
                  await dispatchTap(t, other);
                  expect(semRecv('상하차 선택됨'), findsOneWidget, reason: '$id 의미 tap → 상하차 선택됨');
                  expect(semRecv('피킹 선택'), findsOneWidget, reason: '$id 같은 날 한 업무 — 피킹 해제');
                  expect(plain('1개 업무 선택됨'), findsOneWidget, reason: '$id 선택 수 = 선택 카드 수(1)');
                } else {
                  expectSemProps(t, other, '$id 상하차 선택', label: '상하차 선택', selected: false);
                }
                final detail = find.ancestor(of: plain('업무 자세히 보기'), matching: typed<TextButton>());
                expect(detail, findsNWidgets(2), reason: '$id 업무 자세히 보기(보조)');
                expectReceiver(t, detail.first, v, '$id 업무 자세히 보기', onScreen: false);
                expectWordsKept(para(t, plain('업무 자세히 보기').first), '업무 자세히 보기', '$id 보조 낱말');
              }
              if (c.state == 'multi') {
                expect(plain('2개 업무 선택됨'), findsOneWidget, reason: '$id 날짜별 선택 합 2(열람일 바꿔도 11/16 선택 유지)');
                expect(plain('11월 20일(금) · 업무 2개'), findsOneWidget, reason: '$id 열람일 = 11/20');
                expect(semRecv('야간 분류 선택됨'), findsOneWidget, reason: '$id 11/20 야간 분류 선택');
                expect(plain('22:00–06:00'), findsOneWidget, reason: '$id 야간 시간 원천');
                expect(plain('실근무 7시간'), findsOneWidget, reason: '$id 자정 넘는 실근무');
                final d21 = semRecv('11월 21일 토요일, 업무 1개');
                final sat = find.descendant(of: d21, matching: plain('토'));
                expect(para(t, sat).text.style?.color, AppColors.textSecondary, reason: '$id 주말 보조 글자색(빨강 0)');
                if (v.id == 'W') {
                  await ensureNode(t, d21);
                  expectNode(t, d21, '$id 11/21 칩', label: '11월 21일 토요일, 업무 1개', tap: true, selected: false, enabled: true);
                  await dispatchTap(t, d21);
                } else {
                  expectSemProps(t, d21, '$id 11/21 칩', label: '11월 21일 토요일, 업무 1개', selected: false, enabled: true);
                  await reachTap(t, plain('11/21')); // B 는 물리 탭으로 열람일만 바꾼다(월급 큰 금액의 B 줄바꿈 관측)
                }
                expect(plain('11월 21일(토) · 업무 1개'), findsOneWidget, reason: '$id 열람일 11/21');
                expect(plain('월급'), findsWidgets, reason: '$id 월급 라벨 원천');
                expect(plainRich('2,500,000원'), findsOneWidget, reason: '$id 월급 금액 원천');
                expect(plain('2개 업무 선택됨'), findsOneWidget, reason: '$id 열람일만 바꿈 — 선택 수 그대로');
                expectWordsKept(para(t, biz), _longBiz, '$id 긴 사업장 낱말');
              }
              if (c.state == 'full') {
                final cta = ctaButton('모집 인원이 찼어요');
                expect(cta, findsOneWidget, reason: '$id FULL CTA(종료와 다른 말)');
                expect(t.widget<ElevatedButton>(cta).onPressed, isNull);
                expectReceiver(t, cta, v, '$id 주CTA', min: 52);
                expect(plain('선택'), findsNothing, reason: '$id 정원 마감 — 선택 없음');
                expect(plain('마감'), findsWidgets, reason: '$id 카드 마감 필');
                final pill = para(t, plain('마감').first);
                expect(pill.text.style?.color, AppColors.textSecondary, reason: '$id 마감 중립 글자(오류 아님)');
              }
              if (c.state == 'ended') {
                final cta = ctaButton('마감된 공고예요');
                expect(cta, findsOneWidget, reason: '$id 종료 CTA 해요체');
                expect(t.widget<ElevatedButton>(cta).onPressed, isNull);
                expectReceiver(t, cta, v, '$id 주CTA', min: 52);
                expect(plain('선택'), findsNothing);
              }
              if (c.state == 'document') {
                final cta = ctaButton('지원 준비하기');
                expect(cta, findsOneWidget, reason: '$id 서류 준비 CTA');
                expect(t.widget<ElevatedButton>(cta).onPressed, isNotNull, reason: '$id 준비 시트로 가는 활성');
                expectReceiver(t, cta, v, '$id 주CTA', min: 52);
                await tapAt(t, cta);
                final sheet = find.byType(BottomSheet);
                expect(sheet, findsOneWidget, reason: '$id 지원 준비 시트(순수 UI)');
                expect(find.descendant(of: sheet, matching: plain('지원 준비가 필요해요')), findsOneWidget);
                await tapAt(t, find.descendant(of: sheet, matching: plain('나중에')));
                expect(find.byType(BottomSheet), findsNothing, reason: '$id 나중에 → 닫힘(서류 화면 미진입)');
              }
              if (c.state == 'applied') {
                expect(plain('지원완료'), findsWidgets, reason: '$id 기지원 관계 칩');
                expect(semRecv('상하차 선택'), findsOneWidget, reason: '$id 다른 업무는 선택 가능');
                expect(semRecv('피킹 선택'), findsNothing, reason: '$id 기지원 업무 선택 없음');
                final cta = ctaButton('지원할 업무를 선택해 주세요');
                expect(cta, findsOneWidget, reason: '$id CTA 해요체·띄어쓰기');
                expect(t.widget<ElevatedButton>(cta).onPressed, isNull);
                expectReceiver(t, cta, v, '$id 주CTA', min: 52);
                expectWordsKept(para(t, plain('지원할 업무를 선택해 주세요')), '지원할 업무를 선택해 주세요', '$id CTA 낱말');
              }
              if (c.state == 'invited') {
                expect(plain('초대 수락'), findsWidgets, reason: '$id 초대 행동(누르지 않음)');
                expect(plain('지원하기'), findsNothing, reason: '$id 초대는 새 지원 CTA 가 아니다');
                expect(calls['applicationOnce'] ?? 0, 0, reason: '$id 다른 업무 제안 아님');
              }
              if (c.state == 'slotError') {
                final cta = ctaButton('지금 지원할 수 있는 업무가 없어요');
                expect(cta, findsOneWidget);
                expect(t.widget<ElevatedButton>(cta).onPressed, isNull);
              }

              // ── 섹션 제목·정보행(정밀 §8) ──
              //   섹션 제목은 트리 순서 첫 번째(공용 위젯 안의 같은 글자보다 앞), 찾아오는 길의 행은 맨 아래라 마지막(.last).
              for (final s in ['근태 인정 기준', '준비사항', '시설 및 환경', '찾아오는 길']) {
                expect(plain(s), findsWidgets, reason: '$id 섹션 $s');
                final f = plain(s).first;
                expect(para(t, f).text.style?.fontSize, 20, reason: '$id 섹션 $s 20');
                expect(t.getRect(f).left, closeTo(g, 0.5), reason: '$id 섹션 $s left = gutter');
              }
              expect(plain('근무 장소'), findsWidgets, reason: '$id 정보행 라벨');
              final place = plain('근무 장소').last;
              expect(para(t, place).text.style?.fontSize, 14);
              expect(para(t, place).text.style?.color, AppColors.textSecondary);
              final addr = plain('경기도 평택시 서정동 123').last;
              expect(para(t, addr).text.style?.fontSize, 16, reason: '$id 정보행 값 16');
              final pin = find.byIcon(Icons.place_outlined).last;
              expect(t.widget<Icon>(pin).size, 18, reason: '$id 정보행 아이콘 18');
              expect(t.widget<Icon>(pin).color, AppColors.conceptNavy, reason: '$id 정보행 아이콘 #25325B');
              expect(plain('작업 장갑 필수'), findsOneWidget, reason: '$id 준비사항 전문(삭제 0)');
              expect(para(t, plain('작업 장갑 필수')).text.style?.color, AppColors.warningDark, reason: '$id 필수 항목 경고 진한 글자');
              final copyBtn = find.ancestor(of: find.byIcon(Icons.copy), matching: find.byType(IconButton));
              expectReceiver(t, copyBtn, v, '$id 주소 복사', onScreen: false);

              // ── 실제 clip(구조) — 중요 글자 ──
              //   머리 글자는 첫 번째(머리) 것만, 카드·정보행 글자는 보이는 모든 것을 잰다.
              final headFirst = <String>[bizText, _title, _desc, '물류 · 창고 작업'];
              final everyOne = <String>[
                if (c.state != 'slotError' && c.state != 'invited') ...['09:00–18:00', '시급 · 익일', '3.3% 원천징수'],
                '경기도 평택시 서정동 123', '작업 장갑 필수',
              ];
              final clip = <String, List<String>>{};
              for (final s in headFirst) {
                final iss = clipIssues(t, plain(s).first, viewport: false);
                if (iss.isNotEmpty) clip[s] = iss;
              }
              var checked = headFirst.length;
              for (final s in everyOne) {
                for (final e in plain(s).evaluate()) {
                  checked++;
                  final iss = clipIssues(t, find.byWidget(e.widget), viewport: false);
                  if (iss.isNotEmpty) clip[s] = iss;
                }
              }
              // 요율(Text.rich) — 구조 clip + 숫자 내부 줄바꿈(한 줄에 들어갈 수 있을 때는 0, 못 들어가면 기록).
              final rates = <String, Object?>{};
              for (final amount in const ['13,000', '120,000', '150,000', '2,500,000']) {
                for (final e in plainRich('$amount원').evaluate()) {
                  checked++;
                  final f = find.byWidget(e.widget);
                  final iss = clipIssues(t, f, viewport: false);
                  if (iss.isNotEmpty) clip['$amount원'] = iss;
                  final k = numberKept(para(t, f), amount);
                  rates['$amount원'] = k;
                  if (k['fits'] == true) expect(k['split'], isFalse, reason: '$id `$amount` 숫자 안 줄바꿈 0(한 줄 폭 ${k['oneLine']} ≤ ${k['maxWidth']})');
                }
              }
              log('$id-clip', {'structure': clip, 'checked': checked, 'rates': rates});
              expect(clip, isEmpty, reason: '$id 중요 글자 구조 clip 0');

              // ── B: 후반 정보 도달(실제 가시) — 대표 normal 에서 마지막 정보행까지(나머지 장면은 구조 clip 까지) ──
              if (v.id == 'B' && c.state == 'normal') {
                final bus = plain('1-1번 서정리역 정류장 하차');
                await reach(t, bus);
                expect(inBody(t, bus), isTrue, reason: '$id 마지막 정보행 도달(앱바 아래 본문 안)');
                expect(clipIssues(t, bus, viewport: true), isEmpty, reason: '$id 마지막 정보행 본문 잘림 0(viewport 교차)');
                log('$id-reach', {'bus': t.getRect(bus).toString(), 'body': bodyRect(t).toString(), 'offset': vOffset(t)});
              }
            }
            log('$id-end', {'taps': _taps, 'actions': _actions, 'scrolls': _scrolls, 'calls': calls});
            await t.pumpWidget(const SizedBox.shrink());
            _pumps++;
            await t.pump(const Duration(seconds: 2));
            _pumps++;
            judgeErrors(id, errs);
          });
        } finally {
          semH.dispose();
        }
      });
    }
  }

  tearDown(() {
    // ignore: avoid_print
    print('CP05-COUNT cases=${_cases.length} mounts=$_mounts pumps=$_pumps pumpPlusMount=${_pumps + _mounts} '
        'taps=$_taps actions=$_actions tapsPlusActions=${_taps + _actions} scrolls=$_scrolls pngPairs=$_pngs');
  });

  tearDownAll(() {
    // ignore: avoid_print
    print('CP05-FINAL phase=$phase cases=${_cases.length} mounts=$_mounts pumps=$_pumps pumpPlusMount=${_pumps + _mounts} '
        'taps=$_taps actions=$_actions scrolls=$_scrolls pngPairs=$_pngs');
    expect(_cases.length, lessThanOrEqualTo(16));
    expect(_mounts, lessThanOrEqualTo(16));
    expect(_taps + _actions, lessThanOrEqualTo(28));
    expect(_scrolls, lessThanOrEqualTo(16));
    expect(_pumps + _mounts, lessThanOrEqualTo(1000));
    expect(_pngs, lessThanOrEqualTo(10));
  });
}
