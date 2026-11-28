// [DU411 S080 · 소급 41 §6 · 인계 41 §5–§6] 지원자 홈 '이번 주 일정' 숫자 상자 간격 — 새 전용 시험 · 정확 2 public · 캡처 4쌍(뷰 2 × first/last).
//   F = 320×640@3.0(가로 스크롤 분기 · 간격 대상) · B = 320×640@2.0(7칸 균등 분기 · 무변화 확인). 원 VQ 파일(du1_vq_capture_test.dart)은 변경 0.
//   하네스: D397FB(VQ :4320) 의 fixture(확정 +1 · 대기 오늘/+2) · 본문 스크롤 · 섹션/칸/상자 찾기 · 불변(도달 · 요일/숫자 · 한 줄 · 숫자 ⊂ 상자 ⊂ 칸 · 오늘 채움 1 · 점 귀속 · 비겹침 · 왼→오)을 옮겼다.
//   간격 = 이웃 날짜 숫자 상자 Container rect. 날짜별 ensureVisible 로 가로 offset 이 바뀌므로 rect + 그때의 hpos.pixels(콘텐츠 좌표)로 인접 6쌍을 잰다.
//   하한 4.0 logical px · 부동소수 epsilon 1e-6(±0.5 아님) · 실제 최소값을 출력한다.
//   모드: DU_BEFORE_OBSERVE=411 이면 before(현행 — 간격 관측만), 아니면 strict(F 최소 간격 ≥ 4.0 단언). 기준일 = DU1_VQ_DATE(셀이 2026-11-16 고정).
//   출력 줄은 lkit 선언형 계약 형식: 'D411 <tok> <kind> k=v …' — 뷰에 따라 다른 사실은 시험이 단언하고 줄에는 branchOk/gapOk/geoOk 판정값으로 낸다.
// ignore_for_file: depend_on_referenced_packages
import 'dart:io';
import 'dart:math' as math;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ALfit/models/core/application_model.dart';
import 'package:ALfit/models/core/business_model.dart';
import 'package:ALfit/models/core/legal_readiness.dart';
import 'package:ALfit/models/core/renewal_proposal_model.dart';
import 'package:ALfit/models/core/slot_model.dart';
import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/models/core/user_region.dart';
import 'package:ALfit/providers/notification_provider.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/screens/user/user_home_reads.dart';
import 'package:ALfit/screens/user/user_home_screen.dart';
import 'package:ALfit/services/payroll_correction_service.dart';
import 'package:ALfit/theme/role_theme.dart';
import 'package:ALfit/utils/format_helper.dart';

import 'support/checkin_contract_fixture.dart';
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

class _Worker extends UserProvider {
  @override
  UserModel? get currentUser => UserModel(
      uid: 'u1', username: 'u1', name: '김근로', email: 'u1@alfit.local', role: UserRole.USER,
      homeRegion: const UserRegion(province: '서울특별시', city: '강남구', district: '역삼동'),
      accountStatus: 'active', passVerifiedAt: DateTime.now().subtract(const Duration(days: 30)), totalWorkDays: 3);
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

// 기준일 — VQ 와 같은 규칙(DU1_VQ_DATE = KST 자정, 그날 KST 10:00 이 clock)
final DateTime? _baseDate = () {
  final v = Platform.environment['DU1_VQ_DATE'];
  if (v == null || v.isEmpty) return null;
  final p = v.split('-').map(int.parse).toList();
  return DateTime.utc(p[0], p[1], p[2]).subtract(const Duration(hours: 9));
}();
final DateTime _today = FormatHelper.toKstDate(_baseDate ?? DateTime.now());
DateTime _day(int o) => _today.add(Duration(days: o));
final DateTime _clock = () {
  final k = (_baseDate ?? DateTime.now()).toUtc().add(const Duration(hours: 9));
  return DateTime.utc(k.year, k.month, k.day, 10).subtract(const Duration(hours: 9));
}();
String _ymd(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
List<DateTime> _weekDays(DateTime today) {
  final mon = today.subtract(Duration(days: today.weekday - 1));
  return [for (var i = 0; i < 7; i++) mon.add(Duration(days: i))];
}

ApplicationModel _short(String id, int dayOffset) => ApplicationModel(
      id: id, toId: 'to_$id', uid: 'u1', businessId: 'biz1', businessName: '강남 물류센터', toTitle: '단기 공고',
      status: AppStatus.confirmed, selectedWorkType: '피킹', startTime: '09:00', endTime: '18:00', wage: 12000, wageType: 'hourly',
      workDate: _day(dayOffset), appliedAt: _day(-3));

UserHomeReads _reads(List<ApplicationModel> apps) {
  Future<List<ApplicationModel>>? last;
  return UserHomeReads(
    slotsForTO: (_) async => const <SlotModel>[],
    myContracts: (_) async => completedContractsFor(await (last ?? Future.value(const <ApplicationModel>[]))),
    myApplications: (_) => last = Future.value(apps),
    myMonthlyAttendances: ({required String userId, required int year, required int month}) async => const [],
    publishedTOs: () async => const [],
    pendingIdCardRequests: (_) async => const [],
    myRenewalProposals: () async => const <RenewalProposalModel>[],
    businessById: (_) async => BusinessModel(
        id: 'biz1', name: '강남 물류센터', ownerId: 'a1', businessNumber: '000-00-00000', address: '서울특별시 강남구 테헤란로 1',
        category: '물류', subCategory: '창고', isApproved: true, createdAt: _day(-200)),
    invalidatePublishedTOsCache: () {},
    documentCorrections: () async => DocumentCorrectionSurface.empty,
    legalReadiness: () async => const LegalReadiness(status: LegalReadinessStatus.current),
  );
}

final bool _before = Platform.environment['DU_BEFORE_OBSERVE'] == '411';
final String _manifest = Platform.environment['DUL_MANIFEST'] ?? '(unset)';
const _envKeys = ['DU_BEFORE_OBSERVE', 'DU1_VQ_PHASE', 'DU1_VQ_OUT', 'DU1_VQ_RUN', 'DU1_VQ_DATE', 'DU397_DIAG', 'DU397_MANIFEST', 'DU400_MANIFEST',
  'DU401_MANIFEST', 'DU398_MANIFEST', 'DU406_MANIFEST', 'DU407_MANIFEST', 'DU296_PHASE', 'DUL_MANIFEST'];
final String _envLine = [for (final k in _envKeys) '$k:${Platform.environment[k] ?? '(unset)'}'].join(',');
const double _minGap = 4.0;
const double _eps = 1e-6;

void _out(String s) {
  // ignore: avoid_print
  print(s);
}

String _f2(double v) => v.toStringAsFixed(2);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(
      {'onboarding_completed_u1': true, 'onboarding_completed_a1': true, 'tour_completed_user_home': true, 'tour_completed_admin_home': true}));
  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
    await initializeDateFormatting('ko_KR');
  });

  const views = [
    // [판정285] strict = 섹션 삭제 확인 · before(DU_BEFORE_OBSERVE=411) = 옛 간격 관측 그대로.
    (id: 'F', s: 3.0, title: '이번 주 일정 숫자 상자 간격 320×640@3.0 — 가로 스크롤 · 이웃 상자 ≥ 4'),
    (id: 'B', s: 2.0, title: '이번 주 일정 7칸 균등 320×640@2.0 — 가로 스크롤 0 · 무변화'),
  ];
  for (final v in views) {
    testWidgets('S080F-${v.id}-WEEK ${v.title}', (t) async {
      final tok = 'S080F-${v.id}-WEEK';
      final mode = _before ? 'before' : 'strict';
      _out('D411 $tok begin mode=$mode phase=${Platform.environment['DU1_VQ_PHASE'] ?? '(unset)'} env=$_envLine manifest=$_manifest');
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
      const size = Size(320, 640);
      t.view.physicalSize = size;
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.reset);
      void must(String k, bool ok, [String why = '']) => expect(ok, isTrue, reason: '$tok $k $why');
      Future<void> settle([int n = 6]) async {
        for (var i = 0; i < n; i++) {
          await t.pump(const Duration(milliseconds: 100));
        }
      }

      bool inR(Rect o, Rect r) => r.top >= o.top - 0.5 && r.bottom <= o.bottom + 0.5 && r.left >= o.left - 0.5 && r.right <= o.right + 0.5;
      final key = GlobalKey();
      final cond = {'viewport': '320x640', 'textScaler': v.s, 'run': vqRun, 'manifest': _manifest, 'mode': mode, 'fixture': 'WEEK'};
      var captures = 0;
      Future<void> shot(String id, String stage) async {
        await vqCapture(t, key, '${tok}_$id', conditions: {...cond, 'state': stage});
        captures++;
      }

      final apps = [
        _short('wk1', 1),
        _short('wp0', 0).copyWith(status: AppStatus.pending),
        _short('wp2', 2).copyWith(status: AppStatus.pending),
      ];
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
              home: UserHomeScreen(reads: _reads(apps), clock: () => _clock)),
        ),
      ));
      await settle(25);
      // 본문(세로) Scrollable — 가장 높은 것
      final all = find.byType(Scrollable);
      final cands = [for (var i = 0; i < all.evaluate().length; i++) all.at(i)]
          .where((f) => t.state<ScrollableState>(f).position.axis == Axis.vertical)
          .toList()
        ..sort((a, b) => t.getRect(b).height.compareTo(t.getRect(a).height));
      final bodyEl = cands.first.evaluate().single; // 본문 Scrollable 요소를 처음에 고정(인덱스 finder 는 스크롤 중 대상이 바뀔 수 있다)
      Rect bodyNow() => t.getRect(find.byElementPredicate((e) => identical(e, bodyEl)));
      final vp = bodyNow();
      final title = findVisibleText('이번 주 일정');
      var k = 0;
      while (title.evaluate().isEmpty && k < 30) {
        await t.dragFrom(Offset(vp.left + 4, vp.center.dy), const Offset(0, -300));
        await settle(8);
        k++;
      }
      if (!_before) {
        // [판정285 갱신 2026-11-26 — CP03 주간 존재 대체] `이번 주 일정` 섹션(그 일주일 행·가로 스크롤 행)은 지웠다 —
        //   같은 7칸 날짜 줄이 홈에 두 번 있었다. 확정·지원 중 점은 위 날짜띠가 말한다(worker_home_285_test WH-2·WH-5).
        //   이 시험의 대상 표면이 없어졌으므로 strict 는 끝까지 내려도 그 섹션이 없음을 단언하고 끝낸다.
        //   (간격 계측은 표면과 함께 사라졌다 — 날짜띠 숫자 한 줄·receiver ≥48·마지막 날짜 도달은 WH-5 가 320/2.0 에서 본다.)
        must('이번 주 일정 섹션 0(판정285)', title.evaluate().isEmpty, '${title.evaluate().length}');
        expect(find.text('일정 보기'), findsNothing);
        final exc0 = t.takeException();
        await t.pumpWidget(const SizedBox.shrink());
        await settle(4);
        expect(exc0, isNull);
        expect(overflows, isEmpty, reason: '$tok 넘침');
        return;
      }
      must('이번 주 일정 제목 1', title.evaluate().length == 1);
      final sec = find
          .ancestor(of: title, matching: find.byWidgetPredicate((w) => w is Container && w.color == Colors.white && w.padding != null && w.child is Column))
          .first;
      final hs = find.descendant(of: sec, matching: find.byType(Scrollable));
      final scroll = hs.evaluate().length == 1;
      final branch = scroll ? 'scroll' : 'even';
      final branchOk = v.id == 'F' ? scroll : hs.evaluate().isEmpty;
      must('분기 = ${v.id == 'F' ? '가로 스크롤(필요 칸 × 7 > 가용)' : '7칸 균등(가로 스크롤 0)'}', branchOk, '${hs.evaluate().length}');
      final hpos = scroll ? t.state<ScrollableState>(hs).position : null;
      const wdn = ['월', '화', '수', '목', '금', '토', '일'];
      final week = _weekDays(_today);
      Finder digitF(DateTime d) => find.descendant(of: sec, matching: findVisibleText('${d.day}'));
      Finder cellF(DateTime d) => find.ancestor(of: digitF(d), matching: find.byType(Column)).first;
      Finder boxF(DateTime d) => find.ancestor(of: digitF(d), matching: find.byType(Container)).first;
      for (final d in week) {
        must('숫자 ${_ymd(d)} 정확 1', digitF(d).evaluate().length == 1);
      }
      // [감사42 예방 교정 1] 첫 shot 전에 주간 행을 실제로 화면에 들인다 — findVisibleText 는 제어문자 정규화일 뿐 viewport 가시성이 아니다.
      //   F = 가로 스크롤 viewport(hs), B = 7칸 Row(첫 칸의 가장 가까운 Row 조상). 섹션 전체 fit 은 요구하지 않는다.
      final rowF = scroll ? hs : find.ancestor(of: cellF(week.first), matching: find.byType(Row)).first;
      await t.ensureVisible(rowF);
      await settle();
      Rect frameNow() => t.getRect(rowF); // 현재 프레임의 가로 viewport(F) / 7칸 행(B)
      final vpNow0 = bodyNow();
      final hvp = frameNow();
      must('주간 행 실제 가시(본문 viewport · 화면 안) — 첫 shot 전', inR(vpNow0, hvp) && inR(Offset.zero & size, hvp), '$hvp / $vpNow0');
      final secW = t.getRect(sec).width; // 7칸 판정용 섹션 폭(세로 위치와 무관)
      final todayIx = week.indexWhere((d) => d == _today);
      must('오늘이 이번 주 안', todayIx >= 0);
      final cellW = [for (final d in week) t.getSize(cellF(d)).width];
      final pitch = cellW.first;
      must('칸 폭 7개 같음', cellW.every((w) => (w - pitch).abs() <= 0.5), '$cellW');
      // 기하: 스크롤 분기면 maxOff = 7·pitch − 가용, 처음 offset = clamp(오늘·pitch − (가용 − pitch)/2) — 제품과 같은 pitch 로 맞는지
      var geoOk = true;
      double maxOff = 0, initial = 0;
      if (scroll) {
        maxOff = hpos!.maxScrollExtent;
        initial = hpos.pixels;
        final wantMax = pitch * 7 - hvp.width;
        final wantInit = math.min(math.max(todayIx * pitch - (hvp.width - pitch) / 2, 0.0), wantMax);
        geoOk = (maxOff - wantMax).abs() <= 0.5 && (initial - wantInit).abs() <= 0.5;
        must('가로 기하 maxOff/처음 offset = 같은 pitch', geoOk, 'max $maxOff/$wantMax init $initial/$wantInit pitch $pitch');
        must('오늘 칸이 처음 화면에 보임', inR(hvp, t.getRect(cellF(week[todayIx]))));
      } else {
        geoOk = pitch * 7 <= secW + 0.5;
        must('7칸 균등 — 칸 × 7 ≤ 섹션 폭', geoOk, 'pitch $pitch sec $secW');
      }
      await shot('1first', '처음 위치(가로 offset ${_f2(initial)})');
      int wantDot(DateTime d) => d == _day(1) ? 0xFF166534 : ((d == _today || d == _day(2)) ? 0xFFE65100 : 0x00000000);
      final boxL = <double>[], boxR = <double>[], cellL = <double>[];
      var fills = 0, overlapN = 0;
      var reachAll = true, textsOk = true, oneLine = true, inside = true, dotsOk = true;
      for (var i = 0; i < 7; i++) {
        final d = week[i];
        final cf = cellF(d);
        await t.ensureVisible(cf);
        await settle();
        final px = hpos?.pixels ?? 0.0;
        final cr = t.getRect(cf);
        final br = t.getRect(boxF(d));
        final tr = t.getRect(digitF(d));
        // [감사42 예방 교정 2] 이동 뒤 현재 프레임의 가로 viewport/행 · 본문 viewport 를 다시 읽어 비교한다(이동 전 낡은 rect 0)
        reachAll &= inR(frameNow(), cr) && inR(Offset.zero & size, cr) && inR(bodyNow(), cr);
        cellL.add(cr.left + px);
        boxL.add(br.left + px);
        boxR.add(br.right + px);
        final texts = [for (final e in find.descendant(of: cf, matching: find.byType(Text)).evaluate()) visibleText((e.widget as Text).data ?? '')];
        textsOk &= texts.length == 2 && texts[0] == wdn[d.weekday - 1] && texts[1] == '${d.day}';
        final dp = t.renderObject<RenderParagraph>(find.descendant(of: digitF(d), matching: find.byType(RichText), matchRoot: true).first);
        final tp = TextPainter(text: dp.text, textScaler: dp.textScaler, textDirection: TextDirection.ltr)..layout();
        oneLine &= (dp.size.height / tp.height).round() == 1 && dp.size.width + 0.5 >= tp.width && dp.size.height + 0.5 >= tp.height && !dp.didExceedMaxLines;
        tp.dispose();
        inside &= inR(br, tr) && inR(cr, br);
        final dec = t.widget<Container>(boxF(d)).decoration;
        final fill = dec is BoxDecoration && dec.color != null && dec.color!.a > 0;
        if (fill) fills++;
        must('칸 $i 오늘 채움', fill == (d == _today));
        final dots = [
          for (final e in find.descendant(of: cf, matching: find.byType(Container)).evaluate())
            if ((e.widget as Container).decoration is BoxDecoration && ((e.widget as Container).decoration! as BoxDecoration).shape == BoxShape.circle)
              ((e.widget as Container).decoration! as BoxDecoration).color?.toARGB32() ?? 0
        ];
        dotsOk &= dots.length == 1 && dots.first == wantDot(d);
        for (var j = 0; j < 7; j++) {
          if (j == i) continue;
          final x = cr.intersect(t.getRect(cellF(week[j])));
          if (x.width > 0.5 && x.height > 0.5) overlapN++;
        }
      }
      must('7칸 실제 도달(가로 viewport · 화면 · 본문 안)', reachAll);
      must('요일 · 숫자 정확(full date)', textsOk);
      must('숫자 한 줄 · 말줄임 0', oneLine);
      must('숫자 ⊂ 상자 ⊂ 칸', inside);
      must('오늘 채움 정확 1', fills == 1, '$fills');
      must('점 귀속 · 색', dotsOk);
      must('이웃 칸 비겹침', overlapN == 0, '$overlapN');
      final order = [for (var i = 1; i < 7; i++) cellL[i] > cellL[i - 1] + 0.5].every((x) => x);
      must('칸 왼→오 = 월–일', order, '$cellL');
      // 두 분기 모두 칸 왼쪽 간격 = pitch(맞닿은 7칸 · 콘텐츠 좌표)
      final stepOk = [for (var i = 1; i < 7; i++) ((cellL[i] - cellL[i - 1]) - pitch).abs() <= 0.5].every((x) => x);
      geoOk = geoOk && stepOk;
      must('칸 왼쪽 간격 = pitch', stepOk, '$cellL pitch $pitch');
      // 이웃 숫자 상자 간격(콘텐츠 좌표) 인접 6쌍
      final gaps = [for (var i = 0; i < 6; i++) boxL[i + 1] - boxR[i]];
      final minG = gaps.reduce(math.min);
      final gapOk = branch == 'even' || minG >= _minGap - _eps;
      if (!_before && v.id == 'F') {
        must('이웃 숫자 상자 최소 간격 ≥ ${_f2(_minGap)}(eps $_eps)', minG >= _minGap - _eps, 'min ${minG.toStringAsFixed(6)} gaps $gaps');
      }
      await shot('2last', '마지막 칸 ensureVisible(가로 offset ${_f2(hpos?.pixels ?? 0.0)})');
      _out('D411 $tok week branch=$branch branchOk=$branchOk cells=${week.length} pitch=${_f2(pitch)} maxOff=${_f2(maxOff)} initial=${_f2(initial)} '
          'minGap=${_f2(minG)} gaps=${gaps.map(_f2).join(',')} gapOk=$gapOk geoOk=$geoOk order=$order fill=$fills dots=$dotsOk oneLine=$oneLine '
          'inside=$inside overlap=$overlapN reach=$reachAll');
      _out('D411 $tok min minExact=${minG.toStringAsFixed(6)}');
      final exc = t.takeException();
      _out('D411 $tok done state=WEEK mode=$mode captures=$captures overflows=${overflows.length} exc=${exc != null}');
      await t.pumpWidget(const SizedBox.shrink());
      expect(exc, isNull);
      expect(overflows, isEmpty, reason: '$tok 넘침 ${overflows.join(' | ')}');
    });
  }
}
