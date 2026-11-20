// ignore_for_file: depend_on_referenced_packages
// [DU311 S073] 내 일정 탭 — 묶음 A(A1 제목 실제 배율·머리 높이, A2 등록 상태 굵기, A3/A4 48 receiver, A5 초대 행 Material·48·값 줄바꿈,
//   A6 확정수입 successDark, A8 범례 점 7)와 묶음 B(B1 '내 일정', B2 해요체 실패 문구, B3 '가능일 설정'·brand, B5 배너 낱말 유지,
//   B6 요약 머리 섹션 위계)를 같은 시험으로 baseline(TB)·after(TA) 두 phase 에서 본다.
//   env D311_PHASE=baseline|after, D311_OUT=<dir>(phase 폴더가 이미 있으면 거부, PNG·sidecar 덮어쓰기 거부).
//   baseline 은 fixture 신원·phase 문구 존재·불변(제목 ⊂ 머리, 링크 오른쪽 끝)·실패 = 확인하지 못함·B0/B1 수입 기하(DU217 수용 조건)·
//     쓰기 0 을 단언하고 나머지는 기록한다. after 는 그 위에 교정(A·B·Q3)을 단언한다.
//   조건: N=360×780@1.0, B=320×640@2.0, DPR1, inset0, ko_KR, RoleTheme.workerTheme, vqLoadFonts(번들 NotoSansKR·SDK 아이콘, 기기 글꼴 아님).
//   제품 mount 5: N0(가능일 0·초대 UNSET) · N1(가능일 2·초대 ON 2지역) · B0(0·UNSET) · B1(2·ON) · BF(일정 조회 실패·0·초대 UNKNOWN).
//     빈 mount(SizedBox) 6 = 각 제품 mount 앞 5 + 끝 1 — 따로 센다.
//   [r2] B0·B1 성공 수입 상대 기하(DU217 수용 조건: 겹침 0·칸 안·읽기 순서·라벨 위·넘침 0·같은 줄이면 간격 ≥ 8)를
//     실제 drag 도달 프레임에서 두 phase 모두 단언한다(baseline = 감사217 수용본이므로 회귀 단언).
//   [r2] BF 초대 지역 UNKNOWN 값 '확인하지 못함' 글자색(Q3, after textSecondary)을 행 안에서 찾아 본다.
//   fixture: aA(D0+1 09:00~13:00 시급 12,000 확정) + 월근태 attC(D0 출퇴근·급여 confirmed finalWage 48,000)
//     → 확정 근무 1건 · 실근무 1일 · 예상수입 48,000원 · 확정수입 48,000원(양수 → A6 색 분기 관측).
//   원격: 쓰기·functions 채널 0. 화면 원격 읽기 0(reads 주입). 초대 지역 화면 왕복 1회 창에서만 Firestore 읽기를 받는다 —
//     차단 응답(null)이라 목적지는 '확인하지 못함'으로 고정된다. 목적지 내용은 판정하지 않고 push·pop·복귀 재조회 계수만 본다.
//   phase 상한: pump 320 · mount 5 · 물리 tap+의미 dispatch 16 · drag 16 · route 2 · text 0 · PNG 5.
//   보이는 범위: 로딩 문구(B4)·월근태 실패·새로고침 실패·다른 배율/폭은 관측하지 않는다(한 실패 mount 로 모든 실패 분기를 말하지 않는다).
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

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
import 'package:ALfit/models/core/invite_region_preference.dart';
import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/models/core/user_region.dart';
import 'package:ALfit/models/core/worker_availability_model.dart';
import 'package:ALfit/providers/notification_provider.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/screens/user/invite_region_settings_screen.dart';
import 'package:ALfit/screens/user/my_schedule_reads.dart';
import 'package:ALfit/screens/user/my_schedule_screen.dart';
import 'package:ALfit/theme/app_colors.dart';
import 'package:ALfit/theme/role_theme.dart';
import 'package:ALfit/utils/navigation_key.dart';
import 'package:ALfit/utils/text_layout.dart';
import 'package:ALfit/widgets/calendar/schedule_calendar.dart';

import 'support/du1_vq_capture.dart';

class _FakeApp311 extends Fake with MockPlatformInterfaceMixin implements FirebaseAppPlatform {
  @override
  String get name => defaultFirebaseAppName;
  @override
  FirebaseOptions get options => const FirebaseOptions(apiKey: 'k', appId: 'a', messagingSenderId: 's', projectId: 'p');
}

class _FakeCore311 extends FirebasePlatform with MockPlatformInterfaceMixin {
  @override
  FirebaseAppPlatform app([String name = defaultFirebaseAppName]) => _FakeApp311();
  @override
  Future<FirebaseAppPlatform> initializeApp({String? name, FirebaseOptions? options}) async => _FakeApp311();
  @override
  List<FirebaseAppPlatform> get apps => [_FakeApp311()];
}

const kUid311 = 'worker-local-d311';

class _Worker311 extends UserProvider {
  @override
  UserModel? get currentUser => UserModel(
        uid: kUid311, username: 'worker', name: 'QA 근로자', email: 'w@test.local', role: UserRole.USER,
        homeRegion: const UserRegion(province: '서울특별시', city: '송파구'), accountStatus: 'active',
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

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  setUpAll(() async {
    await initializeDateFormatting('ko_KR', null);
    FirebasePlatform.instance = _FakeCore311();
    await Firebase.initializeApp();
  });

  // 이름은 메타문자 없는 ASCII 고정(argv 정규식 대안에 그대로 넣는다 — DU310 과 같은 방식).
  testWidgets('D311 S073 my-schedule five scenes', (t) async {
    await _d311Run(t);
  });
}

Future<void> _d311Run(WidgetTester t) async {
  final phase = Platform.environment['D311_PHASE'] ?? '';
  expect(phase == 'baseline' || phase == 'after', isTrue, reason: 'D311_PHASE 는 baseline|after');
  final after = phase == 'after';
  final outRoot = Platform.environment['D311_OUT'] ?? '';
  expect(outRoot.isNotEmpty, isTrue, reason: 'D311_OUT');
  final outDir = Directory('$outRoot/$phase');
  expect(outDir.existsSync(), isFalse, reason: 'D311 phase 출력 폴더를 덮지 않는다: ${outDir.path}');
  await t.runAsync(vqLoadFonts);
  expect(t.takeException(), isNull, reason: 'D311 글꼴 등록');

  // ── phase 별 화면 문구(B1·B2·B3). baseline 은 옛 문구가 그대로 있어야 같은 fixture 다 ──
  final kTitle = after ? '내 일정' : '일정';
  final kAction = after ? '가능일 설정' : '가능일';
  const kEditTitle = '근무 가능일 선택';
  final kAppsFail = after ? '일정을 불러오지 못했어요' : '일정을 불러오지 못했습니다';
  final kAppsSub = after
      ? '일정이 없다는 뜻은 아니에요. 잠시 후 다시 시도해 주세요.'
      : '일정이 없다는 뜻이 아닙니다. 잠시 후 다시 시도해주세요.';
  final kAppsToast = after ? '일정을 불러오지 못했어요' : '데이터를 불러오는데 실패했습니다.';
  const kZeroDesc = "가능일을 등록하면 그 날 새 공고 알림을 받고, '초대 받을 지역'까지 설정하면 사업장의 근무 제안도 받을 수 있어요.";
  const kOnDesc = '등록한 날 내 지역에 새 공고가 열리면 알림을 받아요. 조건이 맞는 사업장이 먼저 제안할 수도 있어요.';

  // ── 원격 채널: 쓰기·functions 0, Firestore 읽기는 route 창에서만 ──
  const fnChannel = 'dev.flutter.pigeon.cloud_functions_platform_interface.CloudFunctionsHostApi.call';
  const fsBase = 'dev.flutter.pigeon.cloud_firestore_platform_interface.FirebaseFirestoreHostApi';
  const fsReads = ['documentReferenceGet', 'queryGet', 'aggregateQuery', 'querySnapshot', 'documentReferenceSnapshot'];
  const fsWrites = [
    'documentReferenceSet', 'documentReferenceUpdate', 'documentReferenceDelete', 'writeBatchCommit', 'transactionCreate',
  ];
  final writes = <String>[];
  final remoteReads = <String>[];
  var routeWindow = false;
  final msgr = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  msgr.setMockMessageHandler(fnChannel, (msg) async {
    writes.add('functions');
    return const StandardMessageCodec()
        .encodeMessage(<Object?>['not-found', 'blocked', <String, Object?>{'code': 'not-found'}]);
  });
  for (final op in fsReads) {
    msgr.setMockMessageHandler('$fsBase.$op', (msg) async {
      remoteReads.add('${routeWindow ? 'route' : 'screen'} $op');
      return null;
    });
  }
  for (final op in fsWrites) {
    msgr.setMockMessageHandler('$fsBase.$op', (msg) async {
      writes.add('firestore $op');
      return null;
    });
  }
  addTearDown(() {
    msgr.setMockMessageHandler(fnChannel, null);
    for (final op in [...fsReads, ...fsWrites]) {
      msgr.setMockMessageHandler('$fsBase.$op', null);
    }
  });

  var vw = 360.0;
  var vh = 780.0;
  var scale = 1.0;
  void setView(double w, double h, double s) {
    t.view.physicalSize = Size(w, h);
    t.view.devicePixelRatio = 1.0;
    vw = w;
    vh = h;
    scale = s;
  }

  setView(360, 780, 1.0);
  addTearDown(t.view.reset);
  // [11-15 자체검토 r2] addTearDown 은 프레임워크의 시험 끝 검증(_verifySemanticsHandlesWereDisposed)보다 늦게 돈다 —
  //   r1 은 본문 완주(D311END) 뒤 'SemanticsHandle was active' 로 실패했다. 본문 끝에서 직접 dispose 한다.
  final semantics = t.ensureSemantics();

  // ── 예산(phase 상한) ──
  var pumps = 0;
  var mounts = 0;
  var blankMounts = 0;
  var taps = 0;
  var drags = 0;
  var routes = 0;
  var pngs = 0;
  void budget() {
    pumps++;
    expect(pumps, lessThanOrEqualTo(320), reason: 'D311 pump 상한 320');
  }

  Future<void> frames(int n) async {
    for (var i = 0; i < n; i++) {
      budget();
      await t.pump(const Duration(milliseconds: 100));
    }
  }

  void countTap(String why) {
    taps++;
    expect(taps, lessThanOrEqualTo(16), reason: 'D311 물리 tap+의미 dispatch 상한 16($why)');
  }

  // ── 날짜: 실행일 KST D0 ──
  final kNow = DateTime.now().toUtc().add(const Duration(hours: 9));
  final d0 = DateTime.utc(kNow.year, kNow.month, kNow.day);
  DateTime dd(int plus) => DateTime.utc(d0.year, d0.month, d0.day + plus);
  DateTime kstAt(DateTime d, int h) => DateTime.utc(d.year, d.month, d.day, h).subtract(const Duration(hours: 9));
  final local = DateTime.now();
  print('D311ENV ${jsonEncode({
        'phase': phase,
        'utc': DateTime.now().toUtc().toIso8601String(),
        'tz': local.timeZoneName,
        'offsetMin': local.timeZoneOffset.inMinutes,
        'd0': '${d0.year}-${d0.month}-${d0.day}',
        'out': outDir.path,
        'fonts': 'vqLoadFonts NotoSansKR·Roboto·MaterialIcons(SDK) — 기기 글꼴 아님',
      })}');
  expect(dd(5).month == d0.month, isTrue, reason: 'D311 D0+5 가 M0 안(월말 실행 금지 — 가능일·근무가 같은 달)');
  expect(local.year == d0.year && local.month == d0.month && local.day == d0.day, isTrue,
      reason: 'D311 기기 로컬 날짜 = KST D0');

  final aA = ApplicationModel(
    id: 'd311-a', toId: 'to-d311-a', slotId: 'slot-d311-a', workDetailId: 'wd-d311-a', uid: kUid311,
    applicantName: 'QA 근로자', businessId: 'biz-d311', businessName: 'D311 사업장 d311-a',
    toTitle: 'D311 d311-a', status: AppStatus.confirmed, selectedWorkType: '상하차',
    startTime: '09:00', endTime: '13:00', wage: 12000, wageType: 'hourly',
    workDate: kstAt(dd(1), 0), appliedAt: kstAt(dd(1), 0).subtract(const Duration(days: 3)),
  );
  final attC = AttendanceModel(
    id: 'att-d311-c', applicationId: 'd311-c', userId: kUid311, businessId: 'biz-d311',
    businessName: 'D311 사업장 d311-c', workDate: kstAt(d0, 0), workType: '상하차',
    checkInAt: kstAt(d0, 9), checkOutAt: kstAt(d0, 13), status: AttendanceModel.statusPresent,
    wageStatus: AttendanceModel.wageConfirmed, finalWage: 48000, createdAt: kstAt(d0, 0),
  );
  const exKpi = ['1건', '1일', '48,000원', '48,000원'];
  final twoDates = [
    WorkerAvailabilityModel.dateKeyFrom(DateTime.now().add(const Duration(days: 3))),
    WorkerAvailabilityModel.dateKeyFrom(DateTime.now().add(const Duration(days: 5))),
  ];
  const prefUnset = InviteRegionPreference();
  const prefOn = InviteRegionPreference(enabled: true, regions: [
    UserRegion(province: '서울특별시', city: '강남구'),
    UserRegion(province: '서울특별시', city: '송파구'),
  ]);
  const kOnLabel = '강남구 · 송파구';
  const prefUnknown = InviteRegionPreference.unknown();

  final calls = <String, int>{};
  final violations = <String>[];
  int nCall(String k) => calls[k] = (calls[k] ?? 0) + 1;
  MyScheduleReads reads({required bool failApps, required List<String> dates, required InviteRegionPreference pref}) =>
      MyScheduleReads(
        myApplications: (uid) async {
          nCall('myApplications');
          if (uid != kUid311) violations.add('apps-uid');
          if (failApps) throw StateError('D311 고정 일정 조회 실패');
          return [aA];
        },
        myMonthlyAttendances: ({required String userId, required int year, required int month}) async {
          final c = nCall('myMonthlyAttendances');
          if (userId != kUid311) violations.add('att-uid');
          if (year != d0.year || month != d0.month) violations.add('att-month-n$c');
          return [attC];
        },
        myAvailability: (uid) async {
          nCall('myAvailability');
          if (uid != kUid311) violations.add('avail-uid');
          return WorkerAvailabilityModel(uid: uid, dates: dates, city: '송파구');
        },
        invitePreference: (uid) async {
          nCall('invitePreference');
          if (uid != kUid311) violations.add('invite-uid');
          return pref;
        },
      );
  const calls1 = {'myApplications': 1, 'myMonthlyAttendances': 1, 'myAvailability': 1, 'invitePreference': 1};

  void guard(String step) {
    expect(t.takeException(), isNull, reason: 'D311 $step 예외·overflow');
    expect(violations, isEmpty, reason: 'D311 $step fake 계약 위반');
    expect(writes, isEmpty, reason: 'D311 $step 쓰기·functions 0');
    expect(remoteReads.where((x) => !x.startsWith('route ')), isEmpty, reason: 'D311 $step 화면 원격 읽기 0');
  }

  final key = GlobalKey();
  Future<void> mount(String id, MyScheduleReads r) async {
    mounts++;
    expect(mounts, lessThanOrEqualTo(5), reason: 'D311 mount 상한 5');
    calls.clear();
    budget();
    blankMounts++;
    await t.pumpWidget(const SizedBox.shrink());
    await frames(1);
    budget();
    await t.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<UserProvider>(create: (_) => _Worker311()),
        ChangeNotifierProvider<NotificationProvider>(create: (_) => NotificationProvider()),
      ],
      child: RepaintBoundary(
        key: key,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          navigatorKey: navigatorKey,
          locale: const Locale('ko', 'KR'),
          supportedLocales: const [Locale('ko', 'KR'), Locale('en', 'US')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          theme: RoleTheme.workerTheme,
          builder: (ctx, child) => MediaQuery(
              data: MediaQuery.of(ctx).copyWith(textScaler: TextScaler.linear(scale)), child: child!),
          home: MyScheduleScreen(reads: r),
        ),
      ),
    ));
    await frames(12);
    expect(Localizations.localeOf(t.element(find.byType(MyScheduleScreen))), const Locale('ko', 'KR'),
        reason: 'D311 $id resolved locale');
    guard('$id mount');
  }

  // ── 찾기·측정(두 phase 공통 기록) ──
  bool isToast(Element e) {
    var hit = false;
    e.visitAncestorElements((a) {
      if (a.widget.runtimeType.toString() == '_ToastWidget') {
        hit = true;
        return false;
      }
      return true;
    });
    return hit;
  }

  /// 표시 문자열의 줄바꿈 제어문자를 뺀 원문으로 찾는다(toast 제외).
  Finder plain(String s) => find.byWidgetPredicate((w) {
        if (w is! Text) return false;
        final d = w.data ?? w.textSpan?.toPlainText();
        return d != null && TextLayout.plain(d) == s;
      });
  List<Element> body(String s) => plain(s).evaluate().where((e) => !isToast(e)).toList();
  List<Element> toasts(String s) => plain(s).evaluate().where(isToast).toList();
  Finder el(Element e) => find.byElementPredicate((x) => identical(x, e));
  Rect rectOf(Element e) => t.getRect(el(e));
  List<double> lt(Rect r) => [r.left, r.top, r.right, r.bottom];
  bool inside(Rect r, Rect c) =>
      r.left >= c.left - 0.5 && r.top >= c.top - 0.5 && r.right <= c.right + 0.5 && r.bottom <= c.bottom + 0.5;
  String? hex(Color? c) => c?.toARGB32().toRadixString(16);
  RenderParagraph para(Finder text) =>
      t.renderObject<RenderParagraph>(find.descendant(of: text, matching: find.byType(RichText)).first);
  Element one(String s, String why) {
    final b = body(s);
    expect(b.length, 1, reason: 'D311 $why `$s` 하나');
    return b.first;
  }

  Map<String, Object?> textRec(Element e) {
    final rp = para(el(e));
    final disp = rp.text.toPlainText(includeSemanticsLabels: false);
    final boxes = rp.getBoxesForSelection(TextSelection(baseOffset: 0, extentOffset: disp.length));
    final st = rp.text.style;
    return {
      'rect': lt(rectOf(e)),
      'size': [rp.size.width, rp.size.height],
      'lines': boxes.map((b) => b.top.round()).toSet().length,
      'exceed': rp.didExceedMaxLines,
      'fontSize': st?.fontSize,
      'scaled': rp.textScaler.scale(st?.fontSize ?? 0),
      'scale10': rp.textScaler.scale(10),
      'weight': st?.fontWeight?.value,
      'color': hex(st?.color),
      'semanticsLabel': (e.widget as Text).semanticsLabel,
      'hasWordJoiner': disp.contains('⁠'),
    };
  }

  /// 원문 낱말(공백 기준, `·` 제외) 가운데 글자가 두 줄에 걸친 것 — 실제 줄상자(getBoxesForSelection).
  List<String> splitWords(Element e, String original) {
    final rp = para(el(e));
    final disp = rp.text.toPlainText(includeSemanticsLabels: false);
    final idx = <int>[];
    for (var i = 0; i < disp.length; i++) {
      final c = disp.codeUnitAt(i);
      if (c != 0x2060 && c != 0x200B) idx.add(i);
    }
    final p = TextLayout.plain(disp);
    expect(p, original, reason: 'D311 표시 원문 전문');
    final split = <String>[];
    var from = 0;
    for (final w in original.split(' ')) {
      if (w.isEmpty || w == '·') continue;
      final at = p.indexOf(w, from);
      expect(at >= 0, isTrue, reason: 'D311 낱말 $w');
      final tops = <double>[];
      for (var k = at; k < at + w.length; k++) {
        for (final b in rp.getBoxesForSelection(TextSelection(baseOffset: idx[k], extentOffset: idx[k] + 1))) {
          tops.add(b.top);
        }
      }
      if (tops.isNotEmpty) {
        final lo = tops.reduce((a, b) => a < b ? a : b);
        final hi = tops.reduce((a, b) => a > b ? a : b);
        if (hi - lo >= 1.0) split.add(w);
      }
      from = at + w.length;
    }
    return split;
  }

  /// 글자 → 가장 가까운 GestureDetector 조상(= 누름 receiver). baseline 은 글자·칩 크기, after 는 최소 48.
  Rect receiverOf(Element e) =>
      t.getRect(find.ancestor(of: el(e), matching: find.byType(GestureDetector)).first);

  void log(String tag, Map<String, Object?> m) => print('D311M ${jsonEncode({'phase': phase, 'tag': tag, ...m})}');

  // A1·B1·B3 머리
  Map<String, Object?> head(String id, String title, String? action) {
    final bar = find.byType(AppBar);
    expect(bar, findsOneWidget, reason: 'D311 $id AppBar 하나');
    final br = t.getRect(bar);
    final tf = find.descendant(of: bar, matching: plain(title));
    expect(tf, findsOneWidget, reason: 'D311 $id 머리 제목 `$title`');
    final te = tf.evaluate().first;
    final tRec = textRec(te);
    Map<String, Object?>? aRec;
    if (action != null) {
      final af = find.descendant(of: bar, matching: plain(action));
      expect(af, findsOneWidget, reason: 'D311 $id 머리 행동 `$action`');
      aRec = textRec(af.evaluate().first);
    }
    final m = {
      'id': id, 'bar': lt(br), 'barH': br.height, 'title': title, 't': tRec, 'action': action, 'a': aRec,
      'titleInBar': inside(rectOf(te), br),
    };
    log('$id-head', m);
    expect(m['titleInBar'], isTrue, reason: 'D311 $id 제목 상자가 머리 안');
    if (after) {
      expect(tRec['scale10'] as double, closeTo(10 * scale, 0.01), reason: 'D311 after $id 제목 실제 배율(상한 1.34 아님)');
      expect(tRec['exceed'], isFalse, reason: 'D311 after $id 제목 줄 넘침 0');
      expect(tRec['lines'] as int, lessThanOrEqualTo(2), reason: 'D311 after $id 제목 최대 2줄');
      final need = (tRec['size'] as List)[1] as double;
      expect(br.height, greaterThanOrEqualTo((need + 16 > 56 ? need + 16 : 56) - 0.01),
          reason: 'D311 after $id 머리 높이 ≥ max(56, 제목 높이 + 16)');
      if (scale == 1.0) expect(br.height, closeTo(56, 0.01), reason: 'D311 after $id 1.0 머리 56 유지');
      if (aRec != null) {
        expect(tRec['scaled'] as double, greaterThanOrEqualTo(aRec['scaled'] as double),
            reason: 'D311 after $id 제목 글자 ≥ 머리 행동 글자(위계)');
        expect(aRec['color'], hex(AppColors.brand), reason: 'D311 after $id 머리 행동 brand(B3)');
      }
    }
    return m;
  }

  // A3 등록·수정 링크
  Map<String, Object?> bannerLink(String id, String label) {
    final e = one(label, '$id 배너 링크');
    final tr = rectOf(e);
    final rr = receiverOf(e);
    final row = t.getRect(find.ancestor(of: el(e), matching: find.byType(Row)).first);
    final m = {'id': id, 'label': label, 'text': lt(tr), 'receiver': lt(rr), 'row': lt(row), 't': textRec(e)};
    log('$id-link', m);
    // 불변(두 phase): 글자 오른쪽 끝 = 배너 Row 오른쪽 끝([SCALE-BALANCE.34] 위 정렬 + 오른쪽 끝, topRight).
    expect(tr.right, closeTo(row.right, 0.5), reason: 'D311 $id `$label` 오른쪽 끝 = 배너 줄 끝');
    if (after) {
      expect(rr.width >= 48 - 0.01 && rr.height >= 48 - 0.01, isTrue, reason: 'D311 after $id `$label` receiver ≥ 48×48');
      expect(inside(tr, rr), isTrue, reason: 'D311 after $id `$label` 글자 ⊂ receiver');
      expect(tr.top, closeTo(rr.top, 0.5), reason: 'D311 after $id `$label` 글자는 receiver 위');
      expect(t.getSemantics(el(e)), containsSemantics(isButton: true, hasTapAction: true),
          reason: 'D311 after $id `$label` 버튼 의미');
    }
    return m;
  }

  // A4 필터 칩
  Finder chipsRow() => find.ancestor(of: plain('전체'), matching: find.byType(Row)).first;
  Element chipText(String label) {
    final f = find.descendant(of: chipsRow(), matching: plain(label));
    expect(f, findsOneWidget, reason: 'D311 칩 `$label` 하나');
    return f.evaluate().first;
  }

  Map<String, Object?> chips(String id) {
    final out = <String, Object?>{'id': id};
    for (final label in const ['전체', '확정', '대기']) {
      final e = chipText(label);
      final vis = t.getRect(find.ancestor(of: el(e), matching: find.byType(Container)).first);
      final rr = receiverOf(e);
      final tp = para(el(e));
      final sem = t.getSemantics(el(e));
      out[label] = {
        'text': lt(rectOf(e)), 'visual': lt(vis), 'receiver': lt(rr), 'textH': tp.size.height,
        'semButton': containsSemantics(isButton: true).matches(sem, <dynamic, dynamic>{}),
        'semSelected': containsSemantics(isSelected: true).matches(sem, <dynamic, dynamic>{}),
      };
      if (after) {
        expect(rr.width >= 48 - 0.01 && rr.height >= 48 - 0.01, isTrue, reason: 'D311 after $id 칩 `$label` receiver ≥ 48×48');
        expect(inside(vis, rr), isTrue, reason: 'D311 after $id 칩 `$label` 보이는 칩 ⊂ receiver');
        expect(vis.center.dy, closeTo(rr.center.dy, 0.5), reason: 'D311 after $id 칩 `$label` 세로 가운데');
        expect(sem, containsSemantics(isButton: true, hasTapAction: true, isSelected: label == '전체'),
            reason: 'D311 after $id 칩 `$label` 버튼·선택 의미');
      }
    }
    log('$id-chips', out);
    return out;
  }

  // A5 초대 지역 행
  Map<String, Object?> inviteRow(String id, String valueLabel) {
    final lab = one('초대 받을 지역', '$id 초대 행');
    final iw = find.ancestor(of: el(lab), matching: find.byType(InkWell)).first;
    final mat = find.ancestor(of: iw, matching: find.byType(Material)).first;
    final mw = t.widget<Material>(mat);
    final shape = mw.shape;
    final side = shape is RoundedRectangleBorder ? shape.side : null;
    final ir = t.getRect(iw);
    // [r2] 값은 행(InkWell) 안에서만 찾는다 — '확인하지 못함' 은 KPI 칸에도 있다.
    final vf = find.descendant(of: iw, matching: plain(valueLabel));
    expect(vf, findsOneWidget, reason: 'D311 $id 초대 값 `$valueLabel` 행 안 하나');
    final ve = vf.evaluate().first;
    final vr = rectOf(ve);
    final m = {
      'id': id, 'ink': lt(ir), 'material': lt(t.getRect(mat)), 'matColor': hex(mw.color),
      'shape': shape?.runtimeType.toString(), 'side': hex(side?.color), 'value': valueLabel, 'v': textRec(ve),
      'valueInRow': inside(vr, ir),
    };
    log('$id-invite', m);
    if (after) {
      expect(ir.height, greaterThanOrEqualTo(48 - 0.01), reason: 'D311 after $id 초대 행 ≥ 48');
      expect(shape is RoundedRectangleBorder, isTrue, reason: 'D311 after $id 행 자체 Material(shape) — 흰 구역 위 ink 층');
      expect(hex(side?.color), hex(AppColors.borderLight), reason: 'D311 after $id 행 테두리 borderLight');
      expect(hex(mw.color), hex(Colors.white), reason: 'D311 after $id 행 바탕 흰색');
      expect(m['valueInRow'], isTrue, reason: 'D311 after $id 값이 행 안');
      expect(vr.width, lessThanOrEqualTo(vw * 0.45 + 0.5), reason: 'D311 after $id 값 폭 ≤ 화면 45%');
    }
    return m;
  }

  // A6·B6·A8 요약·범례
  Map<String, Object?> kpi(String label) {
    final le = one(label, 'KPI 라벨');
    final cell = find.ancestor(of: el(le), matching: find.byType(Column)).first;
    final ts = find.descendant(of: cell, matching: find.byType(Text)).evaluate().toList();
    expect(ts.length >= 2, isTrue, reason: 'D311 KPI `$label` 값');
    final ve = ts[1];
    return {'label': label, 'value': TextLayout.plain((ve.widget as Text).data ?? ''), 'v': textRec(ve)};
  }

  List<Map<String, Object?>> legendDots() {
    final wrap = find.ancestor(of: plain('근무 가능일'), matching: find.byType(Wrap)).first;
    return find
        .descendant(
            of: wrap,
            matching: find.byWidgetPredicate((w) {
              if (w is! Container) return false;
              final d = w.decoration;
              return d is BoxDecoration && d.shape == BoxShape.circle && d.color != null && d.border == null;
            }))
        .evaluate()
        .map((e) {
      final r = rectOf(e);
      return <String, Object?>{'w': r.width, 'h': r.height, 'color': hex(((e.widget as Container).decoration as BoxDecoration).color)};
    }).toList();
  }

  Map<String, Object?> summary(String id, {required bool unknown}) {
    final header = one('${d0.month}월 요약', '$id 요약 머리');
    final ks = [for (final l in const ['확정 근무', '실근무', '예상수입', '확정수입']) kpi(l)];
    final m = {'id': id, 'header': textRec(header), 'kpi': ks, 'legend': legendDots()};
    log('$id-summary', m);
    final values = ks.map((k) => k['value']).toList();
    if (unknown) {
      expect(values, everyElement('확인하지 못함'), reason: 'D311 $id 실패 → 네 KPI 확인하지 못함(DU213)');
      for (final k in ks) {
        expect((k['v'] as Map)['color'], hex(AppColors.textSecondary), reason: 'D311 $id ${k['label']} 미확인 중립색');
      }
    } else {
      expect(values, exKpi, reason: 'D311 $id fixture 신원(손 계산 1건·1일·48,000원·48,000원)');
    }
    if (after) {
      final h = m['header'] as Map;
      expect(h['fontSize'], 20, reason: 'D311 after $id 요약 머리 20(B6 ConceptText.section)');
      expect(h['weight'], FontWeight.w700.value, reason: 'D311 after $id 요약 머리 w700');
      final v = (ks.first['v'] as Map)['scaled'] as double;
      expect(h['scaled'] as double, greaterThan(v), reason: 'D311 after $id 요약 머리 > KPI 값(위계)');
      if (!unknown) {
        expect((ks[3]['v'] as Map)['color'], hex(AppColors.successDark), reason: 'D311 after $id 확정수입 양수 successDark(A6)');
      }
      final dots = m['legend'] as List;
      expect(dots.length, 2, reason: 'D311 after $id 범례 점 2(확정·대기)');
      for (final d in dots) {
        expect((d as Map)['w'], closeTo(7, 0.01), reason: 'D311 after $id 범례 점 7(A8)');
        expect(d['h'], closeTo(7, 0.01), reason: 'D311 after $id 범례 점 7(A8)');
      }
    }
    return m;
  }

  // [r2 C6] 수입 칸 — 라벨 → 가장 가까운 Column(_kpiItem) → 값 Text 와 실제 글자 상자(getBoxesForSelection, DU217 과 같은 재료)
  Map<String, Object?> incomeItem(String label) {
    final le = one(label, '수입 라벨');
    final cellF = find.ancestor(of: el(le), matching: find.byType(Column)).first;
    final ts = find.descendant(of: cellF, matching: find.byType(Text)).evaluate().toList();
    expect(ts.length >= 2, isTrue, reason: 'D311 수입 `$label` 값');
    final ve = ts[1];
    final rp = para(el(ve));
    final txt = rp.text.toPlainText(includeSemanticsLabels: false);
    final boxes = rp.getBoxesForSelection(TextSelection(baseOffset: 0, extentOffset: txt.length));
    expect(boxes, isNotEmpty, reason: 'D311 수입 `$label` 글자 상자');
    final o = rp.localToGlobal(Offset.zero);
    var gl = boxes.first.left, gt = boxes.first.top, gr = boxes.first.right, gb = boxes.first.bottom;
    for (final b in boxes) {
      if (b.left < gl) gl = b.left;
      if (b.top < gt) gt = b.top;
      if (b.right > gr) gr = b.right;
      if (b.bottom > gb) gb = b.bottom;
    }
    return {
      'label': label, 'value': TextLayout.plain((ve.widget as Text).data ?? ''),
      'labelRect': lt(rectOf(le)), 'cellRect': lt(t.getRect(cellF)), 'valueRect': lt(rectOf(ve)),
      'glyph': [o.dx + gl, o.dy + gt, o.dx + gr, o.dy + gb], 'exceed': rp.didExceedMaxLines,
    };
  }

  Rect rr(Object? l) {
    final v = (l! as List).cast<double>();
    return Rect.fromLTRB(v[0], v[1], v[2], v[3]);
  }

  // ── 도달(실제 pointer drag, 고정 AppBar 아래 세로 scrollable clip 안) ──
  Finder vsf() => find.descendant(
      of: find.descendant(of: find.byType(MyScheduleScreen), matching: find.byType(CustomScrollView)),
      matching: find.byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.down));
  // [11-15 자체검토 r1] built: 대상 위젯이 아직 만들어졌는지(슬리버 캐시 밖이면 element 0). 없으면 대상 없이 같은 실제 drag 로
  //   한 단계(maxStep) 끈다. t0 은 BF 실패 안내(SliverFillRemaining, 요약 아래 y>1212)를 끌기 전에 '하나' 단언해 0 에서 멈췄다.
  //   상한(조건당 6 · 전체 16) · 끝 도달 · 무진행 단언은 그대로다.
  Future<int> reach(String id, List<Rect> Function() targets, {bool Function()? built}) async {
    var condDrags = 0;
    double? prev;
    for (var i = 0;; i++) {
      final sf = vsf();
      expect(sf, findsOneWidget, reason: 'D311 $id 도달 $i 세로 scrollable 하나');
      final pos = t.state<ScrollableState>(sf).position;
      final clip = t.getRect(sf).intersect(Rect.fromLTWH(0, 0, vw, vh));
      final bar = t.getRect(find.byType(AppBar));
      final isBuilt = built == null || built();
      final rs = isBuilt ? targets() : const <Rect>[];
      final full = isBuilt && rs.every((r) => inside(r, clip)) && rs.every((r) => r.top >= bar.bottom - 0.5);
      final dims = pos.hasContentDimensions;
      final dp = prev == null ? null : pos.pixels - prev;
      print('D311R ${jsonEncode({
            'phase': phase, 'id': id, 'i': i, 'condDrags': condDrags, 'pixels': pos.pixels,
            'max': dims ? pos.maxScrollExtent : null, 'clip': lt(clip), 'bar': lt(bar),
            'targets': rs.map(lt).toList(), 'built': isBuilt, 'full': full, 'drags': drags, 'pumps': pumps,
          })}');
      guard('$id 도달 $i');
      expect(pos.isScrollingNotifier.value, isFalse, reason: 'D311 $id 도달 $i 스크롤 진행 중');
      if (full) return condDrags;
      expect(dims, isTrue, reason: 'D311 $id 도달 $i 범위 미측정');
      final ea = pos.extentAfter;
      expect(ea <= 0.01 && !pos.outOfRange, isFalse, reason: 'D311 $id 끝 도달/목표 미관측 $i');
      if (dp != null) expect(dp <= 0.01 && ea > 0.01, isFalse, reason: 'D311 $id 무진행 $i');
      expect(condDrags < 6, isTrue, reason: 'D311 $id 도달 상한 6 미도달 $i');
      double? need;
      if (isBuilt) {
        var top = rs.first.top;
        var bottom = rs.first.bottom;
        for (final r in rs) {
          if (r.top < top) top = r.top;
          if (r.bottom > bottom) bottom = r.bottom;
        }
        need = bottom - (clip.bottom - 8);
        expect(top - need >= clip.top + 8, isTrue, reason: 'D311 $id 목표 묶음 한 화면 미수용 $i');
      }
      final p0 = Offset(8, vh - 40);
      final calF = find.byType(ScheduleCalendar);
      final cal = calF.evaluate().isEmpty ? Rect.zero : t.getRect(calF);
      expect(!cal.contains(p0) && clip.contains(p0), isTrue, reason: 'D311 $id 시작점 $p0 달력 밖·clip 안');
      final maxStep = p0.dy - 20 - (clip.top + 8);
      final d = (need != null && need < maxStep) ? need : maxStep;
      expect(d > 0.5, isTrue, reason: 'D311 $id 끌기 거리 $d');
      prev = pos.pixels;
      condDrags++;
      drags++;
      expect(drags, lessThanOrEqualTo(16), reason: 'D311 drag 상한 16');
      final g = await t.startGesture(p0);
      var upSent = false;
      try {
        await g.moveBy(const Offset(0, -20));
        await g.moveBy(Offset(0, -d));
        upSent = true;
        await g.up();
      } finally {
        if (!upSent) {
          upSent = true;
          await g.up();
        }
      }
      await frames(4);
    }
  }

  Future<void> capture(String id, Map<String, Object?> meta) async {
    await frames(6);
    guard('$id 캡처 전');
    expect(pngs, lessThan(5), reason: 'D311 PNG 상한 5');
    final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    await t.runAsync(() async {
      outDir.createSync(recursive: true);
      final img = await boundary.toImage(pixelRatio: 1.0);
      final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
      final png = File('${outDir.path}/$id.png');
      if (png.existsSync()) throw StateError('D311 캡처를 덮지 않는다: ${png.path}');
      png.writeAsBytesSync(bytes!.buffer.asUint8List());
      final js = File('${outDir.path}/$id.json');
      if (js.existsSync()) throw StateError('D311 sidecar 를 덮지 않는다: ${js.path}');
      js.writeAsStringSync(jsonEncode({
        'id': id, 'phase': phase, 'utc': DateTime.now().toUtc().toIso8601String(), 'viewport': [vw, vh],
        'dpr': 1.0, 'textScaler': scale, 'inset': 0, 'theme': 'RoleTheme.workerTheme', 'locale': 'ko_KR(resolved)',
        'fonts': 'vqLoadFonts', 'd0': '${d0.year}-${d0.month}-${d0.day}', ...meta,
      }));
    });
    pngs++;
    guard('$id 캡처');
  }

  Future<void> tapAt(String why, Offset p) async {
    countTap(why);
    await t.tapAt(p);
    await frames(4);
  }

  Future<void> semTap(String why, Finder f) async {
    countTap(why);
    final n = t.semantics.find(f);
    n.owner!.performAction(n.id, SemanticsAction.tap);
    await frames(4);
  }

  Rect bannerRect(String desc) => t.getRect(find
      .ancestor(
          of: plain(desc),
          matching: find.byWidgetPredicate((w) =>
              w is Container && w.decoration is BoxDecoration && (w.decoration as BoxDecoration).color == AppColors.infoBg))
      .first);

  // [r2 C6] 성공 수입 두 값의 상대 기하 — 요약 머리 + 두 수입 칸(라벨·값·글자) 전부가 실제 drag 로 clip 안·머리 아래에 들어온
  //   프레임에서 잰다. 기준은 DU217 수용 조건 그대로(공차 0.5, 같은 줄이면 간격 ≥ 8). baseline 도 수용본이므로 두 phase 단언.
  Future<Map<String, Object?>> incomeGeometry(String id) async {
    final header = '${d0.month}월 요약';
    final drags0 = drags;
    await reach('$id-income', () {
      final e = incomeItem('예상수입');
      final c = incomeItem('확정수입');
      return [
        rectOf(one(header, '$id 요약 머리')),
        rr(e['labelRect']), rr(e['valueRect']), rr(e['glyph']),
        rr(c['labelRect']), rr(c['valueRect']), rr(c['glyph']),
      ];
    });
    final eI = incomeItem('예상수입');
    final cI = incomeItem('확정수입');
    final eCell = rr(eI['cellRect']);
    final cCell = rr(cI['cellRect']);
    final eG = rr(eI['glyph']);
    final cG = rr(cI['glyph']);
    const tol = 0.5;
    bool inCell(Rect g, Rect c) =>
        g.left >= c.left - tol && g.right <= c.right + tol && g.top >= c.top - tol && g.bottom <= c.bottom + tol;
    final sameRow = (eCell.top - cCell.top).abs() < tol;
    final gap = sameRow ? cG.left - eG.right : null;
    final order = sameRow ? eCell.left < cCell.left : eCell.bottom <= cCell.top + tol;
    final labelAbove = rr(eI['labelRect']).bottom <= rr(eI['valueRect']).top + tol &&
        rr(cI['labelRect']).bottom <= rr(cI['valueRect']).top + tol;
    final geo = {
      'id': id, 'viewport': [vw, vh], 'textScaler': scale, 'reachDrags': drags - drags0,
      'expected': eI, 'confirmed': cI, 'sameRow': sameRow, 'gapGlyph': gap, 'overlapGlyph': eG.overlaps(cG),
      'inCellExpected': inCell(eG, eCell), 'inCellConfirmed': inCell(cG, cCell), 'readingOrder': order,
      'labelAboveValue': labelAbove,
    };
    log('$id-income', geo);
    expect([eI['value'], cI['value']], ['48,000원', '48,000원'], reason: 'D311 $id 수입 fixture 신원');
    expect(eG.overlaps(cG), isFalse, reason: 'D311 $id 두 수입 값 겹침 0(DU217)');
    expect(inCell(eG, eCell) && inCell(cG, cCell), isTrue, reason: 'D311 $id 값이 자기 칸 안(DU217)');
    expect(order, isTrue, reason: 'D311 $id 읽기 순서 예상수입 → 확정수입(DU217)');
    expect(labelAbove, isTrue, reason: 'D311 $id 라벨이 값 위(DU217)');
    expect(eI['exceed'] == false && cI['exceed'] == false, isTrue, reason: 'D311 $id 값 넘침 0(DU217)');
    if (gap != null) expect(gap, greaterThanOrEqualTo(8.0), reason: 'D311 $id 같은 줄 값 간격 ≥ 8(DU217)');
    return geo;
  }

  // ════════ N0 — 360×780@1.0, 가능일 0 · 초대 UNSET ════════
  setView(360, 780, 1.0);
  await mount('N0', reads(failApps: false, dates: const [], pref: prefUnset));
  expect(calls, calls1, reason: 'D311 N0 mount 호출');
  final n0Head = head('N0', kTitle, kAction);
  final n0Desc = one(kZeroDesc, 'N0 0일 배너 안내');
  final n0Split = splitWords(n0Desc, kZeroDesc);
  log('N0-banner', {'t': textRec(n0Desc), 'split': n0Split, 'banner': lt(bannerRect(kZeroDesc))});
  if (after) {
    expect(n0Split, isEmpty, reason: 'D311 after N0 배너 낱말 가운데 줄바꿈 0(B5)');
    expect((n0Desc.widget as Text).semanticsLabel, kZeroDesc, reason: 'D311 after N0 배너 읽기는 원문(B5)');
  }
  final n0Link = bannerLink('N0', '등록');
  final n0Invite = inviteRow('N0', '설정하기');
  await capture('N0-top', {'head': n0Head, 'link': n0Link, 'invite': n0Invite, 'split': n0Split});
  // 요약·칩까지 실제 drag 로 도달(칩 receiver 전체 포함)
  await reach('N0-summary', () => [
        rectOf(one('${d0.month}월 요약', 'N0 요약 머리')),
        receiverOf(chipText('전체')), receiverOf(chipText('확정')), receiverOf(chipText('대기')),
      ]);
  summary('N0', unknown: false);
  final n0Chips = chips('N0');
  if (after) {
    // 보이는 칩 밖·receiver 안 실제 tap(물리) → 선택 이동, 의미 dispatch 로 '전체' 복귀
    final cR = receiverOf(chipText('확정'));
    final cV = t.getRect(find.ancestor(of: el(chipText('확정')), matching: find.byType(Container)).first);
    final edge = cR.bottom - cV.bottom;
    log('N0-chip-edge', {'receiver': lt(cR), 'visual': lt(cV), 'edge': edge});
    expect(edge, greaterThanOrEqualTo(4), reason: 'D311 after N0 칩 receiver 아래 여유 ≥ 4(1.0, 칩 < 48)');
    await tapAt('N0 확정 칩 아래 여유', Offset(cV.center.dx, cR.bottom - 2));
    expect(t.getSemantics(el(chipText('확정'))), containsSemantics(isSelected: true), reason: 'D311 after N0 여유 tap → 확정 선택');
    expect(t.getSemantics(el(chipText('전체'))), containsSemantics(isSelected: false), reason: 'D311 after N0 전체 해제');
    await semTap('N0 전체 의미 dispatch', el(chipText('전체')));
    expect(t.getSemantics(el(chipText('전체'))), containsSemantics(isSelected: true), reason: 'D311 after N0 의미 tap → 전체 선택');
    guard('N0 칩 행동');
  }
  log('N0-end', {'chips': n0Chips, 'calls': calls, 'pumps': pumps, 'taps': taps, 'drags': drags});

  // ════════ N1 — 360×780@1.0, 가능일 2 · 초대 ON(2지역) ════════
  await mount('N1', reads(failApps: false, dates: twoDates, pref: prefOn));
  expect(calls, calls1, reason: 'D311 N1 mount 호출');
  final n1Count = one('근무 가능일 2일 등록됨', 'N1 등록 상태 첫 줄');
  final n1CountRec = textRec(n1Count);
  log('N1-count', {'t': n1CountRec});
  if (after) expect(n1CountRec['weight'], FontWeight.w600.value, reason: 'D311 after N1 등록 상태 첫 줄 w600(A2)');
  final n1Desc = one(kOnDesc, 'N1 2일 배너 안내');
  final n1Split = splitWords(n1Desc, kOnDesc);
  log('N1-banner', {'t': textRec(n1Desc), 'split': n1Split});
  if (after) {
    expect(n1Split, isEmpty, reason: 'D311 after N1 배너 낱말 유지(B5)');
    expect((n1Desc.widget as Text).semanticsLabel, kOnDesc, reason: 'D311 after N1 배너 읽기 원문(B5)');
  }
  bannerLink('N1', '수정');
  inviteRow('N1', kOnLabel);
  // A5 실제 push(행 가운데 물리 tap) → 목적지 → pop → 복귀 재조회 +1
  final inviteBefore = calls['invitePreference'] ?? 0;
  final iwRect = t.getRect(find.ancestor(of: el(one('초대 받을 지역', 'N1 초대 행')), matching: find.byType(InkWell)).first);
  routeWindow = true;
  routes++;
  expect(routes, lessThanOrEqualTo(2), reason: 'D311 route 상한 2');
  await tapAt('N1 초대 행', iwRect.center);
  await frames(6);
  expect(find.byType(InviteRegionSettingsScreen), findsOneWidget, reason: 'D311 N1 초대 지역 화면 열림');
  navigatorKey.currentState!.pop();
  await frames(10);
  routeWindow = false;
  expect(find.byType(InviteRegionSettingsScreen), findsNothing, reason: 'D311 N1 초대 지역 화면 닫힘');
  expect(calls['invitePreference'], inviteBefore + 1, reason: 'D311 N1 복귀 뒤 초대 설정 다시 읽기 1회');
  final routeReads = remoteReads.where((x) => x.startsWith('route ')).toList();
  log('N1-route', {'before': inviteBefore, 'after': calls['invitePreference'], 'routeReads': routeReads});
  expect(routeReads.length, lessThanOrEqualTo(2), reason: 'D311 N1 목적지 원격 읽기 ≤ 2(차단 응답)');
  guard('N1 route');

  // ════════ B0 — 320×640@2.0, 가능일 0 · UNSET ════════
  setView(320, 640, 2.0);
  await mount('B0', reads(failApps: false, dates: const [], pref: prefUnset));
  expect(calls, calls1, reason: 'D311 B0 mount 호출');
  final b0Head = head('B0', kTitle, kAction);
  await reach('B0-banner', () => [bannerRect(kZeroDesc), receiverOf(one('등록', 'B0 등록'))]);
  final b0Desc = one(kZeroDesc, 'B0 0일 배너 안내');
  final b0Split = splitWords(b0Desc, kZeroDesc);
  log('B0-banner', {'t': textRec(b0Desc), 'split': b0Split, 'banner': lt(bannerRect(kZeroDesc))});
  if (after) expect(b0Split, isEmpty, reason: 'D311 after B0 배너 낱말 유지(B5)');
  final b0Link = bannerLink('B0', '등록');
  await capture('B0-banner', {'head': b0Head, 'link': b0Link, 'split': b0Split});
  // '등록' — after 는 글자 밖·receiver 안(아래 여유), baseline 은 글자 가운데. → 편집 머리
  final regE = one('등록', 'B0 등록');
  final regT = rectOf(regE);
  final regR = receiverOf(regE);
  final regEdge = regR.bottom - regT.bottom;
  log('B0-reg-edge', {'text': lt(regT), 'receiver': lt(regR), 'edge': regEdge});
  if (after) expect(regEdge, greaterThanOrEqualTo(4), reason: 'D311 after B0 등록 receiver 아래 여유 ≥ 4');
  await tapAt('B0 등록', after ? Offset(regT.center.dx, regR.bottom - 2) : regT.center);
  final b0Edit = head('B0-edit', kEditTitle, null);
  expect(find.text('취소'), findsOneWidget, reason: 'D311 B0 편집 모드 취소 버튼');
  await tapAt('B0 편집 취소', t.getCenter(find.text('취소')));
  expect(find.descendant(of: find.byType(AppBar), matching: plain(kTitle)), findsOneWidget, reason: 'D311 B0 편집 취소 → 머리 복귀');
  final b0Income = await incomeGeometry('B0');
  log('B0-end', {'edit': b0Edit, 'income': b0Income, 'pumps': pumps, 'taps': taps, 'drags': drags});

  // ════════ B1 — 320×640@2.0, 가능일 2 · ON(2지역) ════════
  await mount('B1', reads(failApps: false, dates: twoDates, pref: prefOn));
  expect(calls, calls1, reason: 'D311 B1 mount 호출');
  head('B1', kTitle, kAction);
  await reach('B1-banner', () => [
        bannerRect(kOnDesc), receiverOf(one('수정', 'B1 수정')), rectOf(one('근무 가능일 2일 등록됨', 'B1 등록 상태')),
      ]);
  final b1Count = textRec(one('근무 가능일 2일 등록됨', 'B1 등록 상태'));
  final b1Split = splitWords(one(kOnDesc, 'B1 배너 안내'), kOnDesc);
  log('B1-banner', {'count': b1Count, 'split': b1Split});
  if (after) {
    expect(b1Count['weight'], FontWeight.w600.value, reason: 'D311 after B1 등록 상태 w600(A2)');
    expect(b1Split, isEmpty, reason: 'D311 after B1 배너 낱말 유지(B5)');
  }
  bannerLink('B1', '수정');
  // '수정' — after 는 의미 dispatch(버튼 의미 노드의 tap), baseline 은 글자 가운데 물리 tap → 편집 머리 PNG
  if (after) {
    await semTap('B1 수정 의미 dispatch', el(one('수정', 'B1 수정')));
  } else {
    await tapAt('B1 수정', rectOf(one('수정', 'B1 수정')).center);
  }
  final b1Edit = head('B1-edit', kEditTitle, null);
  await capture('B1-edit', {'edit': b1Edit});
  await tapAt('B1 편집 취소', t.getCenter(find.text('취소')));
  await reach('B1-invite', () {
    final lab = one('초대 받을 지역', 'B1 초대 행');
    return [t.getRect(find.ancestor(of: el(lab), matching: find.byType(InkWell)).first)];
  });
  final b1Invite = inviteRow('B1', kOnLabel);
  await capture('B1-invite', {'invite': b1Invite});
  await incomeGeometry('B1');

  // ════════ BF — 320×640@2.0, 일정 조회 실패 · 0 · 초대 UNKNOWN ════════
  await mount('BF', reads(failApps: true, dates: const [], pref: prefUnknown));
  log('BF-calls', {'calls': calls});
  summary('BF', unknown: true);
  // [r2 Q3] 초대 지역 UNKNOWN 값 — 행 안 '확인하지 못함'. after 는 textSecondary(baseline grey500 기록).
  final bfInvite = inviteRow('BF', '확인하지 못함');
  if (after) {
    expect((bfInvite['v'] as Map)['color'], hex(AppColors.textSecondary), reason: 'D311 after BF 초대 UNKNOWN 값 textSecondary(Q3)');
  }
  await reach('BF-fail', () => [
        rectOf(one(kAppsFail, 'BF 실패 제목')), rectOf(one(kAppsSub, 'BF 실패 안내')), rectOf(one('다시 시도', 'BF 다시 시도')),
      ], built: () => body(kAppsFail).isNotEmpty && body(kAppsSub).isNotEmpty && body('다시 시도').isNotEmpty);
  final bfTitle = textRec(one(kAppsFail, 'BF 실패 제목'));
  final bfSub = textRec(one(kAppsSub, 'BF 실패 안내'));
  final bfToast = toasts(kAppsToast).length;
  log('BF-fail', {'title': bfTitle, 'sub': bfSub, 'toast': bfToast});
  await capture('BF-fail', {'title': bfTitle, 'sub': bfSub, 'toast': bfToast});
  // toast(4초) 소멸까지 — 남은 timer 0
  for (var i = 0; i < 45 && plain(kAppsToast).evaluate().any(isToast); i++) {
    await frames(1);
  }
  expect(plain(kAppsToast).evaluate().any(isToast), isFalse, reason: 'D311 BF toast 소멸');
  await frames(2);
  guard('BF 끝');

  budget();
  blankMounts++;
  await t.pumpWidget(const SizedBox.shrink());
  await frames(1);
  setView(360, 780, 1.0);
  final endNow = DateTime.now().toUtc().add(const Duration(hours: 9));
  expect(DateTime.utc(endNow.year, endNow.month, endNow.day), d0, reason: 'D311 자정 경계');
  print('D311END ${jsonEncode({
        'phase': phase, 'pumps': pumps, 'mounts': mounts, 'blankMounts': blankMounts, 'taps': taps, 'drags': drags,
        'routes': routes, 'pngs': pngs,
        'writes': writes.length, 'remoteReads': remoteReads, 'utc': DateTime.now().toUtc().toIso8601String(),
      })}');
  expect(pngs, 5, reason: 'D311 PNG 5 전부');
  expect(mounts, 5, reason: 'D311 제품 mount 5');
  expect(blankMounts, 6, reason: 'D311 빈 mount 6(제품 앞 5 + 끝 1)');
  semantics.dispose();
}
