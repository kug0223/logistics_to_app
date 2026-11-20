// [F60-1 · F60-2 사전 보완 · 판정60] TODAY 같은 mount 선택 뒤 데이터 0 전이(data0) · 매 캡처 직전 같은 frame 실제 가시 must. 원본 3908346f 보존.
// [S080 날짜 탐색 줄 · DU419 · 판정59 B · 인계59 §2–§5] 상단 날짜 탐색(_buildHeroStateC) — 오늘 표시(T1) · 칸 흐림 제거(T2).
//   새 파일 · 정확 6 public(W 390x844@1.0 · B 320x640@2.0 × TODAY · OFF · RANGE) · 캡처 4 단계(TODAY 1init · 2other / OFF 1off / RANGE 1range × W/B = 8쌍).
//   하네스: UserHomeScreen(reads:, clock:) + UserTabScope 기록 대역(CP03 시험과 같은 진입) · reads 메모리 fixture · Firebase 가짜 · 쓰기 0.
//   고정 시각 2026-11-11(수) 10:00 KST. TODAY = 오늘 · 모레 확정 / OFF = 모레만 확정(오늘 탭 불가) / RANGE = TODAY 에서 날짜 시트로 오늘+8 선택(띠가 범위 밖으로).
//   모드: DU_BEFORE_OBSERVE=419 이면 before(현행 02499039 — 오늘 표시 없음 · 칸 흐림 관측), 아니면 strict(후보).
//   'strip <단계>' 줄: tIx 오늘 칸 위치 · tDeco 오늘 상자(fill 채움 / outline 외곽선 / none) · tNum 오늘 숫자 색 · tEn 오늘 탭 가능 · tSem 의미 '오늘' ·
//     selIx 선택 위치 · selN 선택 수 · offNum 탭 불가 다른 날 숫자 색 · opac 묶음 안 흐림(Opacity < 1) 수 · cta 선택 뒤 '일자리 0개 보기' 수.
//   출력 줄: lkit 선언형 계약 'D419 <tok> <kind> [<sub>] k=v …' — 값 공백 0.
// ignore_for_file: depend_on_referenced_packages
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:flutter/material.dart';
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

/// 지원자 provider 대역(CP03 시험과 같은 게터 덮개)
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

const _biz = 'biz1';
const _bizName = '강남 물류센터';
// 고정 시각: 2026-11-11(수) 10:00 KST
final DateTime _clock = DateTime.utc(2026, 11, 11, 1);
final DateTime _today = FormatHelper.toKstDate(_clock);
DateTime _day(int o) => _today.add(Duration(days: o));
const _wd = ['월', '화', '수', '목', '금', '토', '일'];
String _kDate(DateTime d) => '${d.month}월 ${d.day}일 ${_wd[d.weekday - 1]}요일';

ApplicationModel _app(String id, DateTime workDate) => ApplicationModel(
    id: id, toId: 'to_$id', uid: 'u1', businessId: _biz, businessName: _bizName, toTitle: '단기 공고',
    status: AppStatus.confirmed, selectedWorkType: '피킹', startTime: '13:00', endTime: '18:00', wage: 12000, wageType: 'hourly',
    workDate: workDate, appliedAt: _day(-3));

BusinessModel _business() => BusinessModel(
    id: _biz, name: _bizName, ownerId: 'a1', businessNumber: '000-00-00000', address: '서울특별시 강남구 테헤란로 1',
    category: '물류', subCategory: '창고', isApproved: true, createdAt: _day(-200));

UserHomeReads _reads(List<ApplicationModel> apps) => UserHomeReads(  // [F60-1] 주입 목록의 사본을 돌려준다
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
      legalReadiness: () async => const LegalReadiness(status: LegalReadinessStatus.current),
    );

final bool _before = Platform.environment['DU_BEFORE_OBSERVE'] == '419';
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

// 단계별 기대(strict = 후보 · before = 현행 관측). 값은 출력 그대로.
const _strict = <String, Map<String, String>>{
  'init': {'tIx': '0', 'tDeco': 'outline', 'tNum': 'brand', 'tEn': 'true', 'tSem': 'true', 'selIx': '-', 'selN': '0', 'offNum': 'secondary', 'opac': '0', 'cta': '0'},
  'todaysel': {'tIx': '0', 'tDeco': 'fill', 'tNum': 'white', 'tEn': 'true', 'tSem': 'true', 'selIx': '0', 'selN': '1', 'offNum': 'secondary', 'opac': '0', 'cta': '1'},
  'clear': {'tIx': '0', 'tDeco': 'outline', 'tNum': 'brand', 'tEn': 'true', 'tSem': 'true', 'selIx': '-', 'selN': '0', 'offNum': 'secondary', 'opac': '0', 'cta': '0'},
  'other': {'tIx': '0', 'tDeco': 'outline', 'tNum': 'brand', 'tEn': 'true', 'tSem': 'true', 'selIx': '2', 'selN': '1', 'offNum': 'secondary', 'opac': '0', 'cta': '1'},
  'off': {'tIx': '0', 'tDeco': 'outline', 'tNum': 'brand', 'tEn': 'false', 'tSem': 'true', 'selIx': '-', 'selN': '0', 'offNum': 'secondary', 'opac': '0', 'cta': '0'},
  'range': {'tIx': '-', 'tDeco': '-', 'tNum': '-', 'tEn': '-', 'tSem': '-', 'selIx': '0', 'selN': '1', 'offNum': 'secondary', 'opac': '0', 'cta': '1'},
  'data0': {'tIx': '0', 'tDeco': 'fill', 'tNum': 'white', 'tEn': 'false', 'tSem': 'true', 'selIx': '0', 'selN': '1', 'offNum': 'secondary', 'opac': '0', 'cta': '1'},
};
const _beforeWant = <String, Map<String, String>>{
  'init': {'tIx': '0', 'tDeco': 'none', 'tNum': 'primary', 'tEn': 'true', 'tSem': 'false', 'selIx': '-', 'selN': '0', 'offNum': 'primary', 'cta': '0'},
  'todaysel': {'tIx': '0', 'tDeco': 'fill', 'tNum': 'white', 'tEn': 'true', 'tSem': 'false', 'selIx': '0', 'selN': '1', 'offNum': 'primary', 'cta': '1'},
  'clear': {'tIx': '0', 'tDeco': 'none', 'tNum': 'primary', 'tEn': 'true', 'tSem': 'false', 'selIx': '-', 'selN': '0', 'offNum': 'primary', 'cta': '0'},
  'other': {'tIx': '0', 'tDeco': 'none', 'tNum': 'primary', 'tEn': 'true', 'tSem': 'false', 'selIx': '2', 'selN': '1', 'offNum': 'primary', 'cta': '1'},
  'off': {'tIx': '0', 'tDeco': 'none', 'tNum': 'primary', 'tEn': 'false', 'tSem': 'false', 'selIx': '-', 'selN': '0', 'offNum': 'primary', 'cta': '0'},
  'range': {'tIx': '-', 'tDeco': '-', 'tNum': '-', 'tEn': '-', 'tSem': '-', 'selIx': '0', 'selN': '1', 'offNum': 'primary', 'cta': '1'},
  'data0': {'tIx': '0', 'tDeco': 'fill', 'tNum': 'white', 'tEn': 'false', 'tSem': 'false', 'selIx': '0', 'selN': '1', 'offNum': 'primary', 'cta': '1'},
};

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({
        'onboarding_completed_u1': true,
        'tour_completed_user_home': true,
      }));
  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
    await initializeDateFormatting('ko_KR');
  });

  const views = [(id: 'W', w: 390.0, h: 844.0, s: 1.0), (id: 'B', w: 320.0, h: 640.0, s: 2.0)];
  const states = [
    (key: 'TODAY', title: '오늘 · 모레 확정 — 오늘 미선택 외곽선 · 오늘 선택 채움 · 해제 · 다른 날 선택'),
    (key: 'OFF', title: '오늘 데이터 없음 — 오늘 탭 불가 · 외곽선 · 탭 무반응'),
    (key: 'RANGE', title: '날짜 시트로 오늘 더하기 8 선택 — 띠 범위 밖 오늘 표시 없음'),
  ];
  for (final v in views) {
    for (final st in states) {
      testWidgets('S080D-${v.id}-${st.key} ${st.title}', (t) async {
        final tok = 'S080D-${v.id}-${st.key}';
        final mode = _before ? 'before' : 'strict';
        _out('D419 $tok begin mode=$mode phase=${Platform.environment['DU1_VQ_PHASE'] ?? '(unset)'} env=$_envLine manifest=$_manifest');
        await t.runAsync(vqLoadFonts);
        final overflows = <String>[];
        final prev = FlutterError.onError;
        FlutterError.onError = (d) {
          final m = d.exceptionAsString();
          if (m.contains('overflowed')) {
            overflows.add(m.split('\n').first);
          } else {
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

        var captures = 0;
        final key = GlobalKey();
        final cond = {'viewport': '${v.w.toInt()}x${v.h.toInt()}', 'textScaler': v.s, 'run': vqRun, 'manifest': _manifest, 'mode': mode, 'fixture': st.key};
        Future<void> shot(String id, String stage) async {
          await vqCapture(t, key, '${tok}_$id', conditions: {...cond, 'state': stage});
          captures++;
        }

        final log = <String>[];
        final apps = st.key == 'OFF' ? [_app('a2', _day(2))] : [_app('a0', _day(0)), _app('a2', _day(2))];
        await t.pumpWidget(MultiProvider(
          providers: [
            ChangeNotifierProvider<UserProvider>.value(value: _Worker()),
            ChangeNotifierProvider<NotificationProvider>(create: (_) => NotificationProvider()),
          ],
          child: RepaintBoundary(
            key: key,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: RoleTheme.workerTheme,
              builder: (ctx, child) => MediaQuery(data: MediaQuery.of(ctx).copyWith(textScaler: TextScaler.linear(v.s)), child: child!),
              home: UserTabScope(
                switchToTab: (i) => log.add('switchToTab:$i'),
                switchToTabWithDate: (i, d) => log.add('switchToTabWithDate:$i'),
                pendingJobDate: null,
                clearPendingJobDate: () {},
                pendingScheduleMonth: null,
                clearPendingScheduleMonth: () {},
                switchToScheduleNow: () => log.add('switchToScheduleNow'),
                child: UserHomeScreen(reads: _reads(apps), clock: () => _clock),
              ),
            ),
          ),
        ));
        await settle(25);

        final group = find.byWidgetPredicate((w) => w is Semantics && w.properties.label == '일할 날짜 선택', skipOffstage: false);
        must('날짜 탐색 묶음 1', group.evaluate().length == 1, '${group.evaluate().length}');
        final dateRe = RegExp(r'^\d{1,2}월 \d{1,2}일 ');
        List<Element> cells() => find
            .descendant(
                of: group,
                matching: find.byWidgetPredicate((w) => w is Semantics && w.properties.button == true && dateRe.hasMatch(w.properties.label ?? ''),
                    skipOffstage: false),
                skipOffstage: false)
            .evaluate()
            .toList();
        Finder cellF(DateTime d) => find.descendant(
            of: group,
            matching: find.byWidgetPredicate(
                (w) => w is Semantics && w.properties.button == true && (w.properties.label ?? '').startsWith(_kDate(d)),
                skipOffstage: false),
            skipOffstage: false);
        String code(Color? c) => c == AppColors.brand
            ? 'brand'
            : (c == Colors.white ? 'white' : (c == AppColors.textPrimary ? 'primary' : (c == AppColors.textSecondary ? 'secondary' : 'other')));
        Future<void> bringStrip() async {
          await t.ensureVisible(group);
          await settle(4);
        }

        Future<void> tapCell(DateTime d) async {
          final f = cellF(d);
          must('${_kDate(d)} 칸 1', f.evaluate().length == 1, '${f.evaluate().length}');
          await t.ensureVisible(f);
          await settle(4);
          await t.tapAt(t.getCenter(f));
          await settle(6);
        }

        Map<String, String> probe() {
          final cs = cells();
          must('날짜 칸 7', cs.length == 7, '${cs.length}');
          String tIx = '-', tDeco = '-', tNum = '-', tEn = '-', tSem = '-', selIx = '-', offNum = '-';
          var selN = 0;
          for (var i = 0; i < cs.length; i++) {
            final sw = cs[i].widget as Semantics;
            final label = sw.properties.label ?? '';
            final isT = label.startsWith(_kDate(_today));
            final sel = sw.properties.selected == true;
            if (sel) {
              selN++;
              if (selIx == '-') selIx = '$i';
            }
            final digits = find
                .descendant(
                    of: _el(cs[i]),
                    matching: find.byWidgetPredicate((w) => w is Text && RegExp(r'^\d{1,2}$').hasMatch(_vt(w)), skipOffstage: false),
                    skipOffstage: false)
                .evaluate()
                .toList();
            final numC = digits.isEmpty ? null : (digits.first.widget as Text).style?.color;
            if (isT) {
              final boxes = find.descendant(of: _el(cs[i]), matching: find.byType(AnimatedContainer, skipOffstage: false), skipOffstage: false).evaluate().toList();
              final box = boxes.isEmpty ? null : boxes.first.widget as AnimatedContainer;
              final dec = box?.decoration;
              final fg = box?.foregroundDecoration;
              final filled = dec is BoxDecoration && dec.color == AppColors.brand;
              final outlined = fg is BoxDecoration && fg.border is Border && (fg.border! as Border).top.color == AppColors.brand;
              tIx = '$i';
              tDeco = filled ? 'fill' : (outlined ? 'outline' : 'none');
              tNum = code(numC);
              tEn = '${sw.properties.enabled == true}';
              tSem = '${label.contains(', 오늘')}';
            } else if (!sel && sw.properties.enabled == false && offNum == '-') {
              offNum = code(numC);
            }
          }
          final opac = find
              .descendant(of: group, matching: find.byWidgetPredicate((w) => w is Opacity && w.opacity < 1.0, skipOffstage: false), skipOffstage: false)
              .evaluate()
              .length;
          final cta = find.byWidgetPredicate((w) => w is Text && _vt(w).contains('일자리 0개 보기'), skipOffstage: false).evaluate().length;
          return {'tIx': tIx, 'tDeco': tDeco, 'tNum': tNum, 'tEn': tEn, 'tSem': tSem, 'selIx': selIx, 'selN': '$selN', 'offNum': offNum, 'opac': '$opac', 'cta': '$cta'};
        }

        void line(String sub, Map<String, String> m) {
          _out('D419 $tok strip $sub tIx=${m['tIx']} tDeco=${m['tDeco']} tNum=${m['tNum']} tEn=${m['tEn']} tSem=${m['tSem']} selIx=${m['selIx']} '
              'selN=${m['selN']} offNum=${m['offNum']} opac=${m['opac']} cta=${m['cta']}');
          final want = _before ? _beforeWant[sub]! : _strict[sub]!;
          final miss = [for (final e in want.entries) if (m[e.key] != e.value) '${e.key}=${m[e.key]}≠${e.value}'];
          must('$mode $sub 기대', miss.isEmpty, '$miss');
        }

        // [F60-2] 캡처 직전 실제 가시: 필요한 정렬 → settle → 대상 다시 획득 → 숫자 상자 · 숫자 rect ⊂ 띠 viewport ∩ 본문 viewport ∩ 화면
        bool inR(Rect o, Rect r) => r.top >= o.top - 0.5 && r.bottom <= o.bottom + 0.5 && r.left >= o.left - 0.5 && r.right <= o.right + 0.5;
        final screenR = Offset.zero & Size(v.w, v.h);
        Rect bodyView() {
          final vs = [
            for (final e in find.byType(Scrollable).evaluate())
              if ((e.widget as Scrollable).axisDirection == AxisDirection.down) e
          ]..sort((a, c) => t.getRect(_el(c)).height.compareTo(t.getRect(_el(a)).height));
          return vs.isEmpty ? screenR : t.getRect(_el(vs.first));
        }

        Rect stripView() {
          final hs = find.descendant(of: group, matching: find.byType(Scrollable, skipOffstage: false), skipOffstage: false).evaluate().toList();
          return hs.isEmpty ? t.getRect(group) : t.getRect(_el(hs.first));
        }

        Future<void> ready(List<DateTime> days, String what) async {
          await t.ensureVisible(cellF(days.first));
          await settle(4);
          final sv = stripView(), bv = bodyView();
          final why = <String>[];
          for (final d in days) {
            final cf = cellF(d);
            final box = find.descendant(of: cf, matching: find.byType(AnimatedContainer, skipOffstage: false), skipOffstage: false);
            final dig = find.descendant(
                of: cf, matching: find.byWidgetPredicate((w) => w is Text && _vt(w) == '${d.day}', skipOffstage: false), skipOffstage: false);
            if (box.evaluate().length != 1 || dig.evaluate().length != 1) {
              why.add('${d.day} 상자/숫자 ${box.evaluate().length}/${dig.evaluate().length}');
              continue;
            }
            for (final r in [t.getRect(box), t.getRect(dig)]) {
              if (!(inR(sv, r) && inR(bv, r) && inR(screenR, r))) why.add('${d.day} $r sv=$sv bv=$bv');
            }
          }
          must('캡처 직전 $what 숫자 상자 · 숫자 띠 viewport ∩ 본문 viewport ∩ 화면 안(같은 frame)', why.isEmpty, '$why');
        }

        await bringStrip();
        if (st.key == 'TODAY') {
          line('init', probe());
          await ready([_today], '오늘');
          await shot('1init', '오늘 미선택(오늘 · 모레 확정)');
          await tapCell(_today);
          line('todaysel', probe());
          await tapCell(_today);
          line('clear', probe());
          await tapCell(_day(2));
          line('other', probe());
          await ready([_today, _day(2)], '오늘 · 선택 모레(오늘 쪽 가로 복구)');
          await shot('2other', '다른 날(모레) 선택 · 오늘 미선택');
          // [F60-1] 같은 mount — 오늘 실제 탭(선택) → 주입 확정 목록 0 → 기존 RefreshIndicator.onRefresh 재조회 → data0
          await tapCell(_today);
          must('data0 전 오늘 선택', cellF(_today).evaluate().length == 1 && (t.widget<Semantics>(cellF(_today)).properties.selected == true));
          apps.clear();
          final ri = find.byType(RefreshIndicator);
          must('RefreshIndicator 1', ri.evaluate().length == 1, '${ri.evaluate().length}');
          final refreshing = t.widget<RefreshIndicator>(ri).onRefresh();
          await settle(10);
          await refreshing;
          await settle(6);
          final m0 = probe();
          line('data0', m0);
          final semT = t.widget<Semantics>(cellF(_today));
          final gdT = find.descendant(of: cellF(_today), matching: find.byType(GestureDetector, skipOffstage: false), skipOffstage: false);
          must('data0 오늘 Semantics · GestureDetector tap 콜백 0', semT.properties.onTap == null && gdT.evaluate().isNotEmpty && t.widget<GestureDetector>(gdT.first).onTap == null);
          await tapCell(_today); // 비활성 오늘 실제 재탭 — 선택/CTA 불변
          final m1 = probe();
          must('data0 비활성 오늘 재탭 뒤 선택 · CTA 불변', m1['selIx'] == m0['selIx'] && m1['selN'] == m0['selN'] && m1['cta'] == m0['cta'], '$m0 → $m1');
        } else if (st.key == 'OFF') {
          await tapCell(_today); // 탭 불가 — 무반응이어야 한다(선택 0 · CTA 0)
          line('off', probe());
          await ready([_today], '오늘(탭 불가)');
          await shot('1off', '오늘 탭 불가(데이터 없음)');
        } else {
          final act = find.byWidgetPredicate((w) => w is Text && _vt(w) == '날짜 선택', skipOffstage: false);
          must('홈 행동 날짜 선택 1', act.evaluate().length == 1, '${act.evaluate().length}');
          await t.ensureVisible(act);
          await settle(4);
          await t.tapAt(t.getCenter(act));
          await settle(10);
          final sheet = find.byType(BottomSheet);
          must('날짜 시트 1', sheet.evaluate().length == 1, '${sheet.evaluate().length}');
          final target = _day(8);
          final dayT = find.descendant(of: sheet, matching: find.text('${target.day}'));
          must('시트 ${target.day} 1', dayT.evaluate().length == 1, '${dayT.evaluate().length}');
          await t.tapAt(t.getCenter(dayT));
          await settle(10);
          must('시트 닫힘', find.byType(BottomSheet).evaluate().isEmpty);
          await bringStrip();
          must('띠 시작 = 오늘 더하기 8', cellF(target).evaluate().length == 1 && cellF(_today).evaluate().isEmpty);
          line('range', probe());
          await ready([target], '선택한 오늘+8');
          await shot('1range', '띠 범위 밖 오늘(오늘 더하기 8 선택)');
        }

        final exc = t.takeException();
        _out('D419 $tok done state=${st.key} mode=$mode captures=$captures overflows=${overflows.length} exc=${exc != null}');
        await t.pumpWidget(const SizedBox.shrink());
        await settle(4);
        expect(exc, isNull);
        expect(overflows, isEmpty, reason: '$tok 넘침');
      });
    }
  }
}
