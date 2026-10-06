// [DATE-HERO-ONE-LINE / RECRUITABLE-CARD-OVERFLOW] 지원자 홈 첫 화면의 가로 예산.
//
// ── 기기에서 본 두 현상 ─────────────────────────────────────────────────
//   ① `언제 일하고 싶으세요?` 가 정상 폭·기본 배율에서 두 줄로 꺾였다.
//   ② `지금 지원 가능한 일자리` 카드가 `RIGHT OVERFLOWED BY 24 PIXELS`.
//
// ── 원인 (숫자) ─────────────────────────────────────────────────────────
//   ① 제목이 `날짜 더보기`(고정 폭 ≈79.5px)와 한 Row 를 공유했다.
//      제목 필요 폭 216.0px 에 대해 가용 폭이
//        320dp 180.9(−35.1) · 360dp 216.3(+0.3) · 390dp 246.3 · 411dp 258.1
//      였다. **360dp 의 여유가 0.3px** — 기기 폰트가 조금만 다르거나 시스템
//      배율이 1.0 을 조금만 넘으면 꺾인다.
//   ② 카드 하단 행의 세 조각(급여·추천사유·화살표)에 flex 가 **하나도** 없고
//      `Spacer` 만 있었다. 공간이 모자라면 Spacer 가 0 이 되고 그대로 넘쳤다.
//        360dp 가용 204.0 / 시급+업무경험 237.5 → 33.5px
//        390dp 가용 234.0 / 일급+업무경험 257.7 → **23.7px** (기기의 24px)
//
// ── 고친 방식 ───────────────────────────────────────────────────────────
//   글자를 줄이지 않았다. 타이포 토큰(24sp w700 / 18sp w700)은 그대로다.
//   ① 제목이 카드 전폭을 쓰게 하고 `날짜 더보기` 를 부제목 줄로 옮겼다.
//      부제목 `일할 날짜를 선택해보세요.` 가 바로 그 입구의 안내다.
//   ② 급여와 추천사유를 `Wrap` 에 넣고 화살표를 바깥에 고정했다.
//      자리가 모자라면 **다음 줄로 내려간다** — 자르거나 줄이지 않는다.
//
// ── 측정 등급 (과장하지 않기 위해) ──────────────────────────────────────
//   · W 셀 — 번들 `NotoSansKR` 을 실제로 로드해 `TextPainter` 로 잰다.
//     앱 UI 는 `fontFamily` 를 지정하지 않아 기기의 기본 한글 폰트(Android:
//     Noto Sans CJK KR)를 쓴다. 번들본은 그 **proxy** 이고, 이 프로젝트에서
//     구할 수 있는 가장 가까운 자다.
//   · R 셀 — production 위젯을 실제로 그린다. 이때 글꼴은 `flutter test` 의
//     기본 폰트이고 **글자마다 fontSize 정사각**이라 한글이 실제보다 약 30%
//     넓다(제목 282.0 vs 216.0). 그래서 R 셀은 **보수적**이다 — 여기서 넘치지
//     않으면 기기에서도 넘치지 않는다. 반대로 R 셀에서 제목이 두 줄인 폭은
//     기기에서 한 줄일 수 있으므로, 줄 수 판정은 W 셀이 담당한다.
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ALfit/models/core/application_model.dart';
import 'package:ALfit/models/core/attendance_model.dart';
import 'package:ALfit/models/core/business_model.dart';
import 'package:ALfit/models/core/slot_model.dart';
import 'package:ALfit/models/core/to_model.dart';
import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/models/core/work_detail_data.dart';
import 'package:ALfit/services/payroll_correction_service.dart';
import 'package:ALfit/models/core/user_region.dart';
import 'package:ALfit/providers/notification_provider.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/screens/user/user_home_reads.dart';
import 'package:ALfit/screens/user/user_home_screen.dart';
import 'package:ALfit/theme/app_text_styles.dart';
import 'package:ALfit/utils/format_helper.dart';

// ══ 공용 ════════════════════════════════════════════════════════════════

const _headline = '언제 일하고 싶으세요?';
const _subtitle = '일할 날짜를 선택해보세요.';
const _more = '날짜 더보기';
const _legend = '확정 근무';

/// `ResponsiveHelper.getScale` 과 같은 계단.
double _scaleOf(double w) => w < 360 ? 0.85 : (w < 400 ? 0.9 : 1.0);

const _widths = <double>[320, 360, 390, 411];

String _read(String p) => File(p).readAsStringSync();

double _tw(String text, TextStyle style, {double scale = 1.0}) {
  final tp = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: TextDirection.ltr,
    textScaler: TextScaler.linear(scale),
    maxLines: 1,
  )..layout();
  return tp.width;
}

/// 번들 폰트를 실제로 등록한다 — 기기 한글 폰트의 proxy.
Future<void> _loadBundledFonts() async {
  for (final e in {
    'NKB': 'assets/fonts/NotoSansKR-Bold.ttf',
    'NKR': 'assets/fonts/NotoSansKR-Regular.ttf',
  }.entries) {
    final loader = FontLoader(e.key);
    final b = File(e.value).readAsBytesSync();
    loader.addFont(
        Future.value(ByteData.view(b.buffer, b.offsetInBytes, b.length)));
    await loader.load();
  }
}

// ══ production 위젯 하네스 (R 셀) ═══════════════════════════════════════

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

class _UserDouble extends UserProvider {
  static const homeRegion =
      UserRegion(province: '서울특별시', city: '강남구', district: '역삼동');

  @override
  UserModel? get currentUser => UserModel(
        uid: 'u1',
        username: 'u1',
        name: '김근로',
        email: 'u1@alfit.local',
        role: UserRole.USER,
        homeRegion: homeRegion,
        accountStatus: 'active',
        passVerifiedAt: DateTime.now().subtract(const Duration(days: 30)),
        totalWorkDays: 3,
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

final DateTime _today = FormatHelper.toKstDate(DateTime.now());
DateTime _day(int o) => _today.add(Duration(days: o));
const _biz = 'biz1';

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

/// 확정 단기 — 홈이 `확정 근무` 범례를 띄우도록 **스트립 안** 날짜로 둔다.
ApplicationModel _confirmed({required DateTime workDate, String id = 'a1'}) =>
    ApplicationModel(
      id: id,
      toId: 'to_$id',
      uid: 'u1',
      businessId: _biz,
      businessName: '강남 물류센터',
      toTitle: '단기 공고',
      status: AppStatus.confirmed,
      selectedWorkType: '상하차',
      startTime: '09:00',
      endTime: '18:00',
      wage: 12000,
      workDate: workDate,
      appliedAt: _day(-3),
    );

/// 근태 1건 — `_cachedWorkTypeStats` 를 채워 추천사유를 **가장 긴 문구**
///   (`내 업무 경험과 일치`)로 만든다. 최악 조합을 그린다.
AttendanceModel _att({required DateTime workDate, String appId = 'a1'}) =>
    AttendanceModel(
      id: 'att1',
      applicationId: appId,
      userId: 'u1',
      businessId: _biz,
      businessName: '강남 물류센터',
      workDate: workDate,
      workType: '상하차',
      status: AttendanceModel.statusPresent,
      wageStatus: AttendanceModel.wagePending,
      adminConfirmed: false,
      createdAt: workDate,
    );

/// 추천 카드용 TO — 내 city · 60일 안 슬롯 · 급여가 **가장 긴 표기**가 되게.
TOModel _recTo({
  String id = 'toRec',
  int wage = 3000000,
  String wageType = 'monthly',
  int maxWage = 4000000,
}) {
  final d = _day(4);
  final key = '${d.year}-${d.month.toString().padLeft(2, "0")}'
      '-${d.day.toString().padLeft(2, "0")}';
  return TOModel(
    id: id,
    businessId: _biz,
    businessName: '강남 물류센터',
    businessCity: _UserDouble.homeRegion.city,
    businessDistrict: _UserDouble.homeRegion.district,
    type: 'flex',
    title: '물류센터 상하차 야간 지원',
    creatorUID: 'admin1',
    status: TOStatus.active,
    deadlineType: 'NONE',
    hoursBeforeStart: 0,
    // 최저≠최고 → `월급 3,000,000원~` (물결 포함, 가장 긴 급여 표기)
    workDetails: [
      WorkDetailData(
        wdId: 'wd1',
        workType: '상하차',
        wage: wage,
        wageType: wageType,
        requiredCount: 2,
        startTime: '22:00',
        endTime: '06:00',
      ),
      WorkDetailData(
        wdId: 'wd2',
        workType: '상하차',
        wage: maxWage,
        wageType: wageType,
        requiredCount: 2,
        startTime: '09:00',
        endTime: '18:00',
      ),
    ],
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

UserHomeReads _reads({
  List<ApplicationModel> applications = const [],
  List<AttendanceModel> attendances = const [],
  List<TOModel> tos = const [],
}) =>
    UserHomeReads(
      slotsForTO: (toId) async => const <SlotModel>[],
      myApplications: (uid) async => applications,
      myMonthlyAttendances: (
              {required String userId,
              required int year,
              required int month}) async =>
          attendances,
      publishedTOs: () async => tos,
      pendingIdCardRequests: (uid) async => const [],
      myRenewalProposals: () async => const [],
      businessById: (id) async => _business(),
      invalidatePublishedTOsCache: () {},
      documentCorrections: () async => DocumentCorrectionSurface.empty,
    );

Future<void> _pump(
  WidgetTester tester, {
  required UserHomeReads reads,
  required double width,
  double textScale = 1.0,
}) async {
  if (tester.binding.rootElement != null) {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 50));
  }
  // 세로는 넉넉히 — 세로 부족으로 생기는 overflow 를 가로 결함과 섞지 않는다.
  tester.view.physicalSize = Size(width, 4000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final key = UniqueKey();
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<UserProvider>.value(value: _UserDouble()),
        ChangeNotifierProvider<NotificationProvider>(
            create: (_) => NotificationProvider()),
      ],
      child: MaterialApp(
        builder: (ctx, child) => MediaQuery(
          data: MediaQuery.of(ctx)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: KeyedSubtree(key: key, child: child!),
        ),
        home: UserHomeScreen(reads: reads),
      ),
    ),
  );
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
    // 첫 실행 가이드 투어가 홈을 덮는다 — 이 Phase 의 대상이 아니므로 끈다.
    SharedPreferences.setMockInitialValues({'tour_completed_user_home': true});
    await _loadBundledFonts();
  });

  // ══ W — 가로 예산 (실제 폰트 proxy) ═══════════════════════════════════
  group('HRW-W 가로 예산', () {
    final hero = AppTextStyles.heroTitle().copyWith(fontFamily: 'NKB');
    final subS = AppTextStyles.heroDescription().copyWith(fontFamily: 'NKR');
    final moreS = const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)
        .copyWith(fontFamily: 'NKB');
    final legendS = const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)
        .copyWith(fontFamily: 'NKR');
    final payS = AppTextStyles.pay().copyWith(fontFamily: 'NKB');
    final reasonS = const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)
        .copyWith(fontFamily: 'NKB');

    /// Hero 카드 안쪽 가용 폭 — 화면폭 − 바깥 16s·2 − 카드 16s·2 − 테두리 3.
    double heroAvail(double w) {
      final s = _scaleOf(w);
      return w - 2 * 16 * s - 2 * 18 * s - 3.0;
    }

    test('W1 제목은 320·360·390·411dp 에서 한 줄이다 (배율 1.0)', () {
      final need = _tw(_headline, hero);
      for (final w in _widths) {
        final avail = heroAvail(w);
        expect(avail, greaterThanOrEqualTo(need),
            reason: '${w.toInt()}dp 에서 제목이 꺾인다 — '
                'need=${need.toStringAsFixed(1)} avail=${avail.toStringAsFixed(1)}');
      }
      // 가장 좁은 폭에서도 여유가 30px 이상이어야 기기 폰트 차이를 견딘다.
      expect(heroAvail(320) - need, greaterThan(30),
          reason: '320dp 여유가 얇으면 기기에서 다시 꺾인다');
    });

    test('W1b 고정 폭 형제가 같은 줄에 있던 예전 구조는 360dp 여유가 0.3px 였다',
        () {
      // 결함 재현 — 이 산식이 다시 들어오면 안 된다는 근거.
      final need = _tw(_headline, hero);
      // 360dp: 가용 − 더보기 블록 − 제목 필요폭 = 남은 여유
      final slack360 =
          heroAvail(360) - (8 * .9 + _tw(_more, moreS) + 16 * .9) - need;
      expect(slack360, lessThan(1.0),
          reason: '예전 구조의 여유가 1px 미만이었다는 사실 자체가 결함이다 '
              '(실측 ${slack360.toStringAsFixed(1)}px)');
      expect(slack360, greaterThan(0),
          reason: '360dp 는 아슬아슬하게 들어갔다 — 그래서 기기에서만 꺾였다');
      // 320dp: 30px 이상 부족했다
      final short320 =
          need - (heroAvail(320) - (8 * .85 + _tw(_more, moreS) + 16 * .85));
      expect(short320, greaterThan(30),
          reason: '320dp 부족분 ${short320.toStringAsFixed(1)}px');
    });

    test('W2 배율 1.3 에서도 제목은 한 줄로 들어간다 (360dp 이상)', () {
      for (final w in [360.0, 390.0, 411.0]) {
        final need = _tw(_headline, hero, scale: 1.3);
        expect(heroAvail(w), greaterThanOrEqualTo(need),
            reason: '${w.toInt()}dp x1.3');
      }
    });

    test('W3 배율 2.0 은 물리적으로 두 줄이다 — 축소하지 않고 늘어난다', () {
      final need = _tw(_headline, hero, scale: 2.0);
      for (final w in _widths) {
        expect(need, greaterThan(heroAvail(w)),
            reason: '${w.toInt()}dp x2.0 에서 한 줄이면 이 셀의 전제가 바뀐 것');
      }
      // 축소로 맞추지 않았다는 근거 — 토큰은 24sp 그대로.
      expect(AppTextStyles.heroTitle().fontSize, 24);
      expect(AppTextStyles.heroTitle().fontWeight, FontWeight.w700);
    });

    test('W4 부제목 줄 — 범례 없으면 한 줄, 있으면 다음 줄로 내려간다', () {
      for (final w in _widths) {
        final s = _scaleOf(w);
        final avail = heroAvail(w);
        final sub = _tw(_subtitle, subS);
        final more = _tw(_more, moreS) + 16 * s;
        final legend = 5 * s + 4 * s + _tw(_legend, legendS) + 10 * s;
        // 범례 없음 → 한 줄 (간격 8s 포함)
        expect(sub + 8 * s + more, lessThanOrEqualTo(avail),
            reason: '${w.toInt()}dp 부제목+더보기가 한 줄에 안 들어간다');
        // 각 조각은 어떤 폭에서도 혼자서는 들어간다 → 넘침 0
        expect(sub, lessThanOrEqualTo(avail));
        expect(more + legend, lessThanOrEqualTo(avail));
      }
    });

    test('W5 카드 하단 — 급여·추천사유 각 조각이 혼자서는 항상 들어간다', () {
      const wages = ['시급 12,000원', '일급 150,000원~', '월급 3,000,000원~'];
      const reasons = ['내 일정과 일치', '내 업무 경험과 일치', '내 지역 일자리'];
      for (final w in _widths) {
        final s = _scaleOf(w);
        // 섹션 20s·2 · 카드 12s·2 · 테두리 3 · 이미지 96s · 간격 10s
        final row = w - 2 * 20 * s - 2 * 12 * s - 3.0 - 96 * s - 10 * s;
        final wrap = row - 4 * s - 18 * s; // 간격 + 고정 화살표
        for (final wg in wages) {
          expect(_tw(wg, payS), lessThanOrEqualTo(wrap),
              reason: '${w.toInt()}dp "$wg" 가 혼자서도 안 들어간다');
        }
        for (final r in reasons) {
          expect(12 * s + 3 * s + _tw(r, reasonS), lessThanOrEqualTo(wrap),
              reason: '${w.toInt()}dp "$r" 가 혼자서도 안 들어간다');
        }
      }
    });

    test('W5b 예전 구조는 네 대표 폭 전부에서 넘쳤다 — 재현', () {
      const wg = '시급 12,000원';
      const r = '내 업무 경험과 일치';
      for (final w in _widths) {
        final s = _scaleOf(w);
        final row = w - 2 * 20 * s - 2 * 12 * s - 3.0 - 96 * s - 10 * s;
        final old = _tw(wg, payS) + 12 * s + 3 * s + _tw(r, reasonS) +
            4 * s + 18 * s;
        expect(old, greaterThan(row),
            reason: '${w.toInt()}dp 에서 예전 구조가 넘치지 않았다면 전제가 다르다');
      }
      // 기기에서 본 24px — 390dp · 일급 + 업무경험
      const s = 0.9;
      final row390 = 390 - 2 * 20 * s - 2 * 12 * s - 3.0 - 96 * s - 10 * s;
      final old390 = _tw('일급 150,000원~', payS) + 12 * s + 3 * s +
          _tw(r, reasonS) + 4 * s + 18 * s;
      expect((old390 - row390).round(), 24,
          reason: '기기 보고치 24px 와 산식이 맞지 않는다');
    });
  });

  // ══ R — production 위젯 렌더 (보수적: 테스트 폰트가 더 넓다) ═══════════
  group('HRW-R 렌더', () {
    for (final w in _widths) {
      for (final sc in [1.0, 1.3, 2.0]) {
        testWidgets('R ${w.toInt()}dp x$sc — 넘침 0 · 잘림 0', (tester) async {
          await _pump(
            tester,
            reads: _reads(
              applications: [_confirmed(workDate: _day(2))],
              attendances: [_att(workDate: _day(-5))],
              tos: [_recTo()],
            ),
            width: w,
            textScale: sc,
          );
          expect(tester.takeException(), isNull,
              reason: '${w.toInt()}dp x$sc 에서 overflow/예외');
          // 제목·부제목·입구가 모두 살아 있다(글자 소실 0).
          expect(find.text(_headline), findsOneWidget);
          expect(find.text(_subtitle), findsOneWidget);
          expect(find.text(_more), findsOneWidget);
        });
      }
    }

    testWidgets('R-W 급여가 통째로 그려진다 — 끝자리 잘림 0', (tester) async {
      await _pump(
        tester,
        reads: _reads(
          applications: [_confirmed(workDate: _day(2))],
          attendances: [_att(workDate: _day(-5))],
          tos: [_recTo()],
        ),
        width: 360,
      );
      expect(tester.takeException(), isNull);
      // 최저≠최고 → 물결 표기. 금액은 한 글자도 줄이지 않는다.
      expect(find.text('월급 3,000,000원~'), findsOneWidget);
    });

    testWidgets('R-R 추천사유가 가장 긴 문구일 때도 넘치지 않는다', (tester) async {
      await _pump(
        tester,
        reads: _reads(
          applications: [_confirmed(workDate: _day(2))],
          attendances: [_att(workDate: _day(-5))],
          tos: [_recTo()],
        ),
        width: 360,
      );
      expect(tester.takeException(), isNull);
      // 근태 1건이 `상하차` 경험을 만들어 가장 긴 사유가 선택된다.
      expect(find.text('내 업무 경험과 일치'), findsOneWidget);
    });

    testWidgets('R-L 범례가 있어도 넘치지 않는다 (부제목 줄이 늘어난다)',
        (tester) async {
      for (final w in [320.0, 360.0]) {
        await _pump(
          tester,
          reads: _reads(
            applications: [_confirmed(workDate: _day(2))],
            tos: [_recTo()],
          ),
          width: w,
        );
        expect(tester.takeException(), isNull, reason: '${w.toInt()}dp');
        expect(find.text(_legend), findsOneWidget);
        expect(find.text(_more), findsOneWidget);
      }
    });
  });

  // ══ S — 소스 계약 (금지 수단을 쓰지 않았다) ════════════════════════════
  group('HRW-S 소스 계약', () {
    late String src;
    setUpAll(() => src = _read('lib/screens/user/user_home_screen.dart'));

    String heroBlock() {
      final i = src.indexOf('[DATE-HERO-ONE-LINE]');
      expect(i, greaterThan(-1), reason: 'Hero 블록 마커가 없다');
      final j = src.indexOf('// 날짜 스트립', i);
      expect(j, greaterThan(i));
      return src.substring(i, j);
    }

    String cardBlock() {
      final i = src.indexOf('[RECRUITABLE-CARD-OVERFLOW]');
      expect(i, greaterThan(-1), reason: '카드 블록 마커가 없다');
      final j = src.indexOf('), // IntrinsicHeight', i);
      expect(j, greaterThan(i));
      return src.substring(i, j);
    }

    test('S1 제목은 전폭을 쓴다 — 같은 줄에 고정 폭 형제가 없다', () {
      final b = heroBlock();
      expect(b.contains("Text('언제 일하고 싶으세요?', style: AppTextStyles.heroTitle())"),
          isTrue);
      // 제목과 더보기 사이에 Row 가 끼어 있지 않다.
      final titleAt = b.indexOf("Text('언제 일하고 싶으세요?'");
      final subAt = b.indexOf("Text('일할 날짜를 선택해보세요.'");
      expect(subAt, greaterThan(titleAt));
      final between = b.substring(titleAt, subAt);
      expect(between.contains('Row('), isFalse,
          reason: '제목 줄에 형제가 다시 들어왔다');
      expect(between.contains('Expanded('), isFalse);
    });

    test('S2 더보기·범례는 부제목 줄의 Wrap 안에 있다', () {
      final b = heroBlock();
      expect(b.contains('alignment: WrapAlignment.spaceBetween'), isTrue);
      expect(b.contains("Text('날짜 더보기'"), isTrue);
      expect(b.contains("'확정 근무',"), isTrue);
      // 두 조각 모두 큰 배율에서 흐를 수 있게 flex 를 가진다(자르지 않는다).
      expect(b.contains('Flexible('), isTrue);
      // 입구의 터치 표적은 세로로만 넓힌다(폭을 다시 먹지 않는다).
      expect(b.contains('padding: EdgeInsets.symmetric(vertical: 4 * s)'), isTrue);
      expect(b.contains('behavior: HitTestBehavior.opaque'), isTrue);
    });

    test('S3 카드 하단은 Wrap + 고정 화살표다', () {
      final b = cardBlock();
      expect(b.contains('child: Wrap('), isTrue);
      expect(b.contains('alignment: WrapAlignment.spaceBetween'), isTrue);
      // 화살표는 Wrap **바깥**의 Row 자식이다 — 오른쪽 끝이 흔들리지 않는다.
      //   들여쓰기 깊이가 그 위치를 말한다(22칸 = Row 직속).
      expect(
          b.contains('                      SizedBox(width: 4 * s),\n'
                  '                      Icon(Icons.chevron_right_rounded,\n'
                  '                          size: 18 * s, color: AppColors.grey400),') ||
              b.contains('                      SizedBox(width: 4 * s),\r\n'
                  '                      Icon(Icons.chevron_right_rounded,\r\n'
                  '                          size: 18 * s, color: AppColors.grey400),'),
          isTrue,
          reason: '화살표가 Wrap 안으로 들어가거나 크기가 바뀌었다');
      // Wrap 의 자식은 급여와 추천사유 둘뿐이다.
      final wrapAt = b.indexOf('child: Wrap(');
      final iconAt = b.indexOf('Icon(Icons.chevron_right_rounded');
      expect(iconAt, greaterThan(wrapAt));
      expect(b.substring(wrapAt, iconAt).contains('chevron'), isFalse);
      // Spacer 는 공간이 모자라면 0 이 되고 그대로 넘친다 — 쓰지 않는다.
      expect(b.contains('Spacer()'), isFalse);
    });

    test('S4 금지 수단을 쓰지 않았다', () {
      for (final b in [heroBlock(), cardBlock()]) {
        for (final banned in [
          'FittedBox',
          'Transform.scale',
          'TextOverflow.clip',
          'TextOverflow.ellipsis',
          'maxLines: 1',
          'ClipRect',
          'textScaleFactor',
        ]) {
          expect(b.contains(banned), isFalse, reason: '$banned 를 썼다');
        }
        // 고정 높이로 봉투를 만들지 않는다.
        expect(RegExp(r'height:\s*\d+\s*\*\s*s\s*,\s*\)').hasMatch(b), isFalse);
      }
    });

    test('S5 타이포 토큰을 줄이지 않았다', () {
      final t = _read('lib/theme/app_text_styles.dart');
      expect(t.contains('fontSize: 24,'), isTrue, reason: 'heroTitle 24sp');
      final i = t.indexOf('static TextStyle heroTitle()');
      expect(t.substring(i, i + 200).contains('fontSize: 24'), isTrue);
      final p = t.indexOf('static TextStyle pay()');
      expect(t.substring(p, p + 200).contains('fontSize: 18'), isTrue);
    });

    test('S6 폭별 magic number 분기가 없다', () {
      // 주석에는 측정값(320dp 180.9 …)이 들어 있다 — 그것은 근거다.
      //   금지하는 것은 **코드의 폭 분기**다. 실행문만 본다.
      for (final b in [heroBlock(), cardBlock()]) {
        final code = b
            .split(RegExp(r'\r?\n'))
            .where((l) => !l.trimLeft().startsWith('//'))
            .join('\n');
        expect(code.contains('MediaQuery'), isFalse,
            reason: '이 블록에서 폭을 직접 읽지 않는다');
        for (final bad in [
          'width <', 'width >', 'width ==',
          '< 400', '>= 360', '< 360', '> 390',
        ]) {
          expect(code.contains(bad), isFalse, reason: '폭 분기($bad) 금지');
        }
        // 대표 폭 숫자가 **실행문**에 박혀 있지 않다.
        for (final bad in ['320', '360', '390', '411']) {
          expect(code.contains(bad), isFalse,
              reason: '실행문에 폭 상수($bad)가 있다');
        }
      }
    });
  });
}
