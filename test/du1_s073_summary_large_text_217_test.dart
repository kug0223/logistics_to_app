// ignore_for_file: depend_on_referenced_packages
// [DU217 S073-D217] 큰 글자 수입 값 구분 — 현재 MS의 정상 수치 상태(baseline)와 배치 교정 뒤(after)를 같은 시험으로 본다.
//   env D217_PHASE=baseline|after, D217_OUT=<dir>. 조건 c360(360×780@1.0)·c320(320×640@2.0), DPR1, inset0.
//   fixture: 기존 aA(D0+1 09:00~13:00 시급 12,000 확정) + 월 근태 [] → 1건·0일·48,000원·0원.
//   read 4종 즉시 정상(uid·year·month 대조), 쓰기 채널 차단. 실제 pointer drag 조건당 최대 4회, 최초 전체 도달에서 멈춘다.
//   baseline 은 수치 신원·노출만 단언하고 B(값 붙음)는 기록만 한다. after 만 간격·겹침·칸 이탈·읽기 순서를 단언한다.
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
import 'package:ALfit/screens/user/my_schedule_reads.dart';
import 'package:ALfit/screens/user/my_schedule_screen.dart';
import 'package:ALfit/theme/role_theme.dart';
import 'package:ALfit/utils/navigation_key.dart';
import 'package:ALfit/utils/text_layout.dart';
import 'package:ALfit/widgets/calendar/schedule_calendar.dart';

import 'support/du1_vq_capture.dart';

class _FakeApp217 extends Fake with MockPlatformInterfaceMixin implements FirebaseAppPlatform {
  @override
  String get name => defaultFirebaseAppName;
  @override
  FirebaseOptions get options => const FirebaseOptions(apiKey: 'k', appId: 'a', messagingSenderId: 's', projectId: 'p');
}

class _FakeCore217 extends FirebasePlatform with MockPlatformInterfaceMixin {
  @override
  FirebaseAppPlatform app([String name = defaultFirebaseAppName]) => _FakeApp217();
  @override
  Future<FirebaseAppPlatform> initializeApp({String? name, FirebaseOptions? options}) async => _FakeApp217();
  @override
  List<FirebaseAppPlatform> get apps => [_FakeApp217()];
}

const kUid217 = 'worker-local-c67';

class _Worker217 extends UserProvider {
  @override
  UserModel? get currentUser => UserModel(
        uid: kUid217, username: 'worker', name: 'QA 근로자', email: 'w@test.local', role: UserRole.USER,
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
    FirebasePlatform.instance = _FakeCore217();
    await Firebase.initializeApp();
  });

  testWidgets('S073-D217 summary 큰 글자 수입 구분', (t) async {
    await _d217Run(t);
  });
}

Future<void> _d217Run(WidgetTester t) async {
  final phase = Platform.environment['D217_PHASE'] ?? '';
  expect(phase == 'baseline' || phase == 'after', isTrue, reason: 'D217_PHASE 는 baseline|after');
  final after = phase == 'after';
  final outRoot = Platform.environment['D217_OUT'] ?? '';
  expect(outRoot.isNotEmpty, isTrue, reason: 'D217_OUT');
  final outDir = Directory('$outRoot/$phase');
  await t.runAsync(vqLoadFonts);
  expect(t.takeException(), isNull, reason: 'D217 글꼴 등록');

  const fnChannel =
      'dev.flutter.pigeon.cloud_functions_platform_interface.CloudFunctionsHostApi.call';
  const fsBase =
      'dev.flutter.pigeon.cloud_firestore_platform_interface.FirebaseFirestoreHostApi';
  const fsOps = [
    'documentReferenceGet', 'queryGet', 'documentReferenceSet', 'documentReferenceUpdate',
    'documentReferenceDelete', 'writeBatchCommit', 'transactionCreate', 'aggregateQuery',
    'querySnapshot', 'documentReferenceSnapshot',
  ];
  final blocked = <String>[];
  final msgr = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  msgr.setMockMessageHandler(fnChannel, (msg) async {
    blocked.add('functions');
    return const StandardMessageCodec().encodeMessage(
        <Object?>['not-found', 'blocked', <String, Object?>{'code': 'not-found'}]);
  });
  for (final op in fsOps) {
    msgr.setMockMessageHandler('$fsBase.$op', (msg) async {
      blocked.add('firestore $op');
      return null;
    });
  }
  addTearDown(() {
    msgr.setMockMessageHandler(fnChannel, null);
    for (final op in fsOps) {
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

  var pumps = 0;
  var drags = 0;
  var pngs = 0;
  void budget() {
    pumps++;
    expect(pumps, lessThanOrEqualTo(120), reason: 'D217 pump 예산 120 초과');
  }

  Future<void> frames(int n) async {
    for (var i = 0; i < n; i++) {
      budget();
      await t.pump(const Duration(milliseconds: 100));
    }
  }

  // ── 날짜: 실행일 KST D0 ──
  final kNow = DateTime.now().toUtc().add(const Duration(hours: 9));
  final d0 = DateTime.utc(kNow.year, kNow.month, kNow.day);
  DateTime dd(int plus) => DateTime.utc(d0.year, d0.month, d0.day + plus);
  DateTime kstAt(DateTime d, int h) =>
      DateTime.utc(d.year, d.month, d.day, h).subtract(const Duration(hours: 9));
  final local = DateTime.now();
  print('D217ENV ${jsonEncode({
        'phase': phase,
        'utc': DateTime.now().toUtc().toIso8601String(),
        'tz': local.timeZoneName,
        'offsetMin': local.timeZoneOffset.inMinutes,
        'd0': '${d0.year}-${d0.month}-${d0.day}',
        'out': outDir.path,
        'fonts': 'vqLoadFonts NotoSansKR·Roboto·MaterialIcons(SDK) — 기기 글꼴 아님',
      })}');
  expect(dd(1).month == d0.month, isTrue, reason: 'D217 D0+1 이 M0 안');
  expect(local.year == d0.year && local.month == d0.month && local.day == d0.day, isTrue,
      reason: 'D217 기기 로컬 날짜 = KST D0');

  final aA = ApplicationModel(
    id: 'd213-a', toId: 'to-d213-a', slotId: 'slot-d213-a', workDetailId: 'wd-d213-a', uid: kUid217,
    applicantName: 'QA 근로자', businessId: 'biz-d213', businessName: 'D213 사업장 d213-a',
    toTitle: 'D213 d213-a', status: AppStatus.confirmed, selectedWorkType: '상하차',
    startTime: '09:00', endTime: '13:00', wage: 12000, wageType: 'hourly',
    workDate: kstAt(dd(1), 0), appliedAt: kstAt(dd(1), 0).subtract(const Duration(days: 3)),
  );
  const exA = ['1건', '0일', '48,000원', '0원'];

  final calls = <String, int>{};
  final violations = <String>[];
  int nCall(String k) => calls[k] = (calls[k] ?? 0) + 1;
  MyScheduleReads reads() => MyScheduleReads(
        myApplications: (uid) async {
          nCall('myApplications');
          if (uid != kUid217) violations.add('apps-uid');
          return [aA];
        },
        myMonthlyAttendances: ({required String userId, required int year, required int month}) async {
          final c = nCall('myMonthlyAttendances');
          if (userId != kUid217) violations.add('att-uid');
          if (year != d0.year || month != d0.month) violations.add('att-month-n$c');
          return const <AttendanceModel>[];
        },
        myAvailability: (uid) async {
          nCall('myAvailability');
          if (uid != kUid217) violations.add('avail-uid');
          return WorkerAvailabilityModel(uid: uid, dates: const [], city: '송파구');
        },
        invitePreference: (uid) async {
          nCall('invitePreference');
          if (uid != kUid217) violations.add('invite-uid');
          return const InviteRegionPreference(
              enabled: true, regions: [UserRegion(province: '서울특별시', city: '송파구')]);
        },
      );
  const calls1 = {'myApplications': 1, 'myMonthlyAttendances': 1, 'myAvailability': 1, 'invitePreference': 1};

  void guard(String step) {
    expect(t.takeException(), isNull, reason: 'D217 $step 예외·overflow');
    expect(violations, isEmpty, reason: 'D217 $step fake 계약 위반');
    expect(blocked, isEmpty, reason: 'D217 $step 쓰기·원격 채널 0');
  }

  final key = GlobalKey();
  Future<void> mount() async {
    calls.clear();
    budget();
    await t.pumpWidget(const SizedBox.shrink());
    await frames(1);
    budget();
    await t.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<UserProvider>(create: (_) => _Worker217()),
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
              data: MediaQuery.of(ctx).copyWith(textScaler: TextScaler.linear(scale)),
              child: child!),
          home: MyScheduleScreen(reads: reads()),
        ),
      ),
    ));
    await frames(12);
    expect(Localizations.localeOf(t.element(find.byType(MyScheduleScreen))), const Locale('ko', 'KR'),
        reason: 'D217 resolved locale');
    guard('mount');
  }

  // ── 표시문자 정규화 finder(TextLayout.plain, toast 제외) ──
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

  List<Element> body(String s) => find
      .byWidgetPredicate((w) {
        if (w is! Text) return false;
        final d = w.data ?? w.textSpan?.toPlainText();
        return d != null && TextLayout.plain(d) == s;
      })
      .evaluate()
      .where((e) => !isToast(e))
      .toList();
  Rect rectOf(Element e) => t.getRect(find.byElementPredicate((x) => identical(x, e)));
  List<double> lt(Rect r) => [r.left, r.top, r.right, r.bottom];
  bool inside(Rect r, Rect c) =>
      r.left >= c.left && r.top >= c.top && r.right <= c.right && r.bottom <= c.bottom;
  Finder vsf() => find.descendant(
      of: find.descendant(of: find.byType(MyScheduleScreen), matching: find.byType(CustomScrollView)),
      matching: find.byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.down));

  // 라벨 → (셀 Column, 값 Text). 셀은 라벨의 가장 가까운 Column 조상(_kpiItem)이다.
  Map<String, Object?> item(String label) {
    final ls = body(label);
    if (ls.length != 1) return {'label': label, 'tree': ls.length};
    final cellF = find
        .ancestor(of: find.byElementPredicate((x) => identical(x, ls.first)), matching: find.byType(Column))
        .first;
    final texts = find.descendant(of: cellF, matching: find.byType(Text)).evaluate().toList();
    if (texts.length < 2) return {'label': label, 'tree': 1, 'texts': texts.length};
    final ve = texts[1];
    final rf = find.descendant(of: find.byElementPredicate((x) => identical(x, ve)), matching: find.byType(RichText));
    final rp = t.renderObject<RenderParagraph>(rf);
    final txt = rp.text.toPlainText();
    final boxes = rp.getBoxesForSelection(TextSelection(baseOffset: 0, extentOffset: txt.length));
    final o = rp.localToGlobal(Offset.zero);
    var gl = 0.0, gt = 0.0, gr = 0.0, gb = 0.0;
    final tops = <int>{};
    for (var k = 0; k < boxes.length; k++) {
      final b = boxes[k];
      if (k == 0 || b.left < gl) gl = b.left;
      if (k == 0 || b.top < gt) gt = b.top;
      if (k == 0 || b.right > gr) gr = b.right;
      if (k == 0 || b.bottom > gb) gb = b.bottom;
      tops.add(b.top.round());
    }
    return {
      'label': label, 'tree': 1,
      'labelRect': lt(rectOf(ls.first)), 'cellRect': lt(t.getRect(cellF)),
      'value': TextLayout.plain((ve.widget as Text).data ?? ''), 'valueRect': lt(rectOf(ve)),
      'glyph': boxes.isEmpty ? null : [o.dx + gl, o.dy + gt, o.dx + gr, o.dy + gb],
      'lines': tops.length, 'didExceedMaxLines': rp.didExceedMaxLines,
    };
  }

  Rect rr(Object? l) {
    final v = (l! as List).cast<double>();
    return Rect.fromLTRB(v[0], v[1], v[2], v[3]);
  }

  Future<void> capture(String id, Map<String, Object?> meta) async {
    await frames(8);
    guard('$id 캡처 전');
    expect(pngs, lessThan(2), reason: 'D217 PNG 예산 2');
    final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    await t.runAsync(() async {
      outDir.createSync(recursive: true);
      final img = await boundary.toImage(pixelRatio: 1.0);
      final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
      final png = File('${outDir.path}/$id.png');
      if (png.existsSync()) throw StateError('D217 캡처를 덮지 않는다: ${png.path}');
      png.writeAsBytesSync(bytes!.buffer.asUint8List());
      final js = File('${outDir.path}/$id.json');
      if (js.existsSync()) throw StateError('D217 sidecar 를 덮지 않는다: ${js.path}');
      js.writeAsStringSync(jsonEncode(meta));
    });
    pngs++;
    guard('$id 캡처');
  }

  final header = '${d0.month}월 요약';
  Future<void> runCondition(String cid, double w, double h, double s) async {
    setView(w, h, s);
    await mount();
    expect(calls, calls1, reason: 'D217 $cid mount 호출');
    final kp = ['확정 근무', '실근무', '예상수입', '확정수입'].map((l) => item(l)['value']).toList();
    expect(kp, exA, reason: 'D217 $cid 정상 수치 신원(손 계산)');
    var condDrags = 0;
    double? prev;
    late Map<String, Object?> eI;
    late Map<String, Object?> cI;
    late Map<String, Object?> last;
    for (var i = 0;; i++) {
      final sf = vsf();
      expect(sf, findsOneWidget, reason: 'D217 $cid 탐색 $i 세로 scrollable 하나');
      expect(find.byType(ScheduleCalendar), findsOneWidget, reason: 'D217 $cid 탐색 $i 달력 하나');
      final pos = t.state<ScrollableState>(sf).position;
      final sr = t.getRect(sf);
      final clip = sr.intersect(Rect.fromLTWH(0, 0, vw, vh));
      final cal = t.getRect(find.byType(ScheduleCalendar));
      final hs = body(header);
      expect(hs.length, 1, reason: 'D217 $cid 요약 머리 하나');
      final hr = rectOf(hs.first);
      eI = item('예상수입');
      cI = item('확정수입');
      final rects = <Rect>[
        hr,
        rr(eI['labelRect']), rr(eI['valueRect']), rr(eI['glyph']),
        rr(cI['labelRect']), rr(cI['valueRect']), rr(cI['glyph']),
      ];
      final full = rects.every((r) => inside(r, clip));
      final dims = pos.hasContentDimensions;
      final dp = prev == null ? null : pos.pixels - prev;
      last = {
        'phase': phase, 'cond': cid, 'i': i, 'condDrags': condDrags, 'pixels': pos.pixels,
        'max': dims ? pos.maxScrollExtent : null, 'extentAfter': dims ? pos.extentAfter : null,
        'viewportDimension': pos.viewportDimension, 'isScrolling': pos.isScrollingNotifier.value,
        'deltaPixels': dp, 'clip': lt(clip), 'calendarRect': lt(cal), 'headerRect': lt(hr),
        'expected': eI, 'confirmed': cI, 'full': full,
        'calls': Map<String, int>.from(calls), 'violations': violations.length, 'blocked': blocked.length,
        'pumps': pumps, 'drags': drags, 'pngs': pngs,
      };
      print('D217S ${jsonEncode(last)}');
      expect(calls, calls1, reason: 'D217 $cid 탐색 $i 호출 불변');
      guard('$cid 탐색 $i');
      expect(pos.isScrollingNotifier.value, isFalse, reason: 'D217 $cid 탐색 $i 스크롤 진행 중');
      if (full) break;
      expect(dims, isTrue, reason: 'D217 $cid 탐색 $i 범위 미측정');
      final ea = pos.extentAfter;
      expect(ea <= 0.01 && !pos.outOfRange, isFalse, reason: 'D217 $cid 끝도달/목표미관측 $i');
      if (dp != null) {
        expect(dp <= 0.01 && ea > 0.01, isFalse, reason: 'D217 $cid 무진행 $i');
      }
      expect(condDrags < 4, isTrue, reason: 'D217 $cid 탐색상한미도달 $i');
      // 다음 끌기 거리: 목표 블록 아래 끝을 clip 아래 8px 안으로. 위 끝이 clip 위로 나가면 한 화면 미수용 실패.
      var top = rects.first.top;
      var bottom = rects.first.bottom;
      for (final r in rects) {
        if (r.top < top) top = r.top;
        if (r.bottom > bottom) bottom = r.bottom;
      }
      final need = bottom - (clip.bottom - 8);
      expect(top - need >= clip.top + 8, isTrue, reason: 'D217 $cid 목표 블록 한 화면 미수용 $i');
      final p0 = Offset(8, vh - 40);
      expect(!cal.contains(p0) && clip.contains(p0), isTrue, reason: 'D217 $cid 시작점 $p0 달력 밖·clip 안');
      final maxStep = p0.dy - 20 - (clip.top + 8);
      final d = need < maxStep ? need : maxStep;
      expect(d > 0.5, isTrue, reason: 'D217 $cid 끌기 거리 $d');
      print('D217PTR ${jsonEncode({
            'phase': phase, 'cond': cid, 'i': i, 'start': [p0.dx, p0.dy], 'need': need, 'maxStep': maxStep, 'd': d,
            'hitPath': t.hitTestOnBinding(p0).path.map((e) => e.target.runtimeType.toString()).toList(),
          })}');
      prev = pos.pixels;
      condDrags++;
      drags++;
      expect(drags, lessThanOrEqualTo(8), reason: 'D217 drag 예산 8');
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
    // ── 기하 판정 재료 ──
    final eCell = rr(eI['cellRect']);
    final cCell = rr(cI['cellRect']);
    final eG = rr(eI['glyph']);
    final cG = rr(cI['glyph']);
    final sameRow = (eCell.top - cCell.top).abs() < 0.5;
    final gap = sameRow ? cG.left - eG.right : null;
    const tol = 0.5;
    bool inCell(Rect g, Rect c) =>
        g.left >= c.left - tol && g.right <= c.right + tol && g.top >= c.top - tol && g.bottom <= c.bottom + tol;
    final order = sameRow ? eCell.left < cCell.left : eCell.bottom <= cCell.top + tol;
    final labelAbove = rr(eI['labelRect']).bottom <= rr(eI['valueRect']).top + tol &&
        rr(cI['labelRect']).bottom <= rr(cI['valueRect']).top + tol;
    final geo = {
      'phase': phase, 'cond': cid, 'viewport': [vw, vh], 'textScaler': scale, 'dpr': 1.0, 'inset': 0,
      'condDrags': condDrags, 'sameRow': sameRow, 'gapGlyph': gap,
      'overlapGlyph': eG.overlaps(cG), 'inCellExpected': inCell(eG, eCell), 'inCellConfirmed': inCell(cG, cCell),
      'readingOrder': order, 'labelAboveValue': labelAbove,
      'kpi': kp, 'reach': last,
    };
    print('D217G ${jsonEncode(geo)}');
    if (after) {
      expect(eG.overlaps(cG), isFalse, reason: 'D217 after $cid 두 수입 값 겹침 0');
      expect(inCell(eG, eCell) && inCell(cG, cCell), isTrue, reason: 'D217 after $cid 값이 자기 칸 안');
      expect(order, isTrue, reason: 'D217 after $cid 읽기 순서 예상수입 → 확정수입');
      expect(labelAbove, isTrue, reason: 'D217 after $cid 라벨이 값 위');
      expect(eI['didExceedMaxLines'] == false && cI['didExceedMaxLines'] == false, isTrue,
          reason: 'D217 after $cid 값 넘침 없음');
      if (gap != null) {
        expect(gap, greaterThanOrEqualTo(8.0), reason: 'D217 after $cid 같은 줄 값 간격 8 이상');
      }
      if (cid == 'c360') {
        expect(sameRow, isTrue, reason: 'D217 after c360 기존 2×2 유지');
      }
    }
    await capture(cid, geo);
  }

  await runCondition('c360', 360, 780, 1.0);
  await runCondition('c320', 320, 640, 2.0);
  setView(360, 780, 1.0);

  final endNow = DateTime.now().toUtc().add(const Duration(hours: 9));
  expect(DateTime.utc(endNow.year, endNow.month, endNow.day), d0, reason: 'D217 자정 경계');
  print('D217END ${jsonEncode({
        'phase': phase, 'pumps': pumps, 'drags': drags, 'pngs': pngs,
        'blocked': blocked.length, 'utc': DateTime.now().toUtc().toIso8601String(),
      })}');
}
