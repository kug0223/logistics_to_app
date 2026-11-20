// ignore_for_file: depend_on_referenced_packages
// [DU219 S078-D219] MY 탭 관측(baseline)과 조건부 국소 교정 뒤(after) — 명시 선택 시험.
//   env D219_PHASE=baseline|after, D219_OUT=<dir>, after 에서는 D219_APPLIED=<R1+R6+...|NONE>.
//   D219_PHASE 가 없으면 skip 한다(일반 실행에서 새 실패를 만들지 않는다).
//   production UserMyTab 단독 mount(root·하단 탭 없음), provider fake 주입, live Firebase 0, 쓰기 채널 차단.
//   조건 c360(360×780@1)·c320(320×640@2) × fixture a·b·c. scene 당 offset 0 PNG 1장, 그 뒤 실제 drag 로 기하만 잰다.
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

import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/models/core/user_region.dart';
import 'package:ALfit/models/settings/trust_settings_model.dart';
import 'package:ALfit/providers/badge_provider.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/screens/user/my_activity_screen.dart';
import 'package:ALfit/screens/user/tabs/user_my_tab.dart';
import 'package:ALfit/theme/app_colors.dart';
import 'package:ALfit/theme/role_theme.dart';

import 'support/du1_vq_capture.dart';

class _FakeApp219 extends Fake with MockPlatformInterfaceMixin implements FirebaseAppPlatform {
  @override
  String get name => defaultFirebaseAppName;
  @override
  FirebaseOptions get options => const FirebaseOptions(apiKey: 'k', appId: 'a', messagingSenderId: 's', projectId: 'p');
}

class _FakeCore219 extends FirebasePlatform with MockPlatformInterfaceMixin {
  @override
  FirebaseAppPlatform app([String name = defaultFirebaseAppName]) => _FakeApp219();
  @override
  Future<FirebaseAppPlatform> initializeApp({String? name, FirebaseOptions? options}) async => _FakeApp219();
  @override
  List<FirebaseAppPlatform> get apps => [_FakeApp219()];
}

const kUid219 = 'worker-local-d219';

class _User219 extends UserProvider {
  _User219(this._u);
  final UserModel _u;
  @override
  UserModel? get currentUser => _u;
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

class _Badges219 extends ChangeNotifier implements BadgeProvider {
  _Badges219(this._list);
  final List<BadgeModel> _list;
  @override
  List<BadgeModel> get badges => _list;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  setUpAll(() async {
    await initializeDateFormatting('ko_KR', null);
    FirebasePlatform.instance = _FakeCore219();
    await Firebase.initializeApp();
  });

  testWidgets('S078-D219 my 관측·조건부 교정', (t) async {
    await _d219Run(t);
  }, skip: Platform.environment['D219_PHASE'] == null);
}

Future<void> _d219Run(WidgetTester t) async {
  final phase = Platform.environment['D219_PHASE'] ?? '';
  expect(phase == 'baseline' || phase == 'after', isTrue, reason: 'D219_PHASE 는 baseline|after');
  final after = phase == 'after';
  final outRoot = Platform.environment['D219_OUT'] ?? '';
  expect(outRoot.isNotEmpty, isTrue, reason: 'D219_OUT');
  final appliedRaw = Platform.environment['D219_APPLIED'] ?? '';
  if (after) expect(appliedRaw.isNotEmpty, isTrue, reason: 'D219_APPLIED');
  final applied = appliedRaw.isEmpty || appliedRaw == 'NONE' ? <String>{} : appliedRaw.split('+').toSet();
  final outDir = Directory('$outRoot/$phase');
  await t.runAsync(vqLoadFonts);
  expect(t.takeException(), isNull, reason: 'D219 글꼴 등록');

  // ── 쓰기 채널 차단 ──
  const fnChannel = 'dev.flutter.pigeon.cloud_functions_platform_interface.CloudFunctionsHostApi.call';
  const fsBase = 'dev.flutter.pigeon.cloud_firestore_platform_interface.FirebaseFirestoreHostApi';
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

  // ── 사전 지정 overflow 진단 수집(baseline 의 MY:294 통계 Row·MY:493 배지 Row 만) ──
  final diags = <Map<String, Object?>>[];
  var curScene = '';
  final prevOnError = FlutterError.onError;
  FlutterError.onError = (FlutterErrorDetails d) {
    final s = d.toString();
    final isOverflow = s.contains('A RenderFlex overflowed by');
    String? src;
    if (s.contains('user_my_tab.dart:294:')) {
      src = 'R5';
    } else if (s.contains('user_my_tab.dart:493:')) {
      src = 'R6';
    }
    if (!after && isOverflow && src != null) {
      diags.add({'scene': curScene, 'src': src, 'summary': d.exceptionAsString().split(String.fromCharCode(10)).first});
      return;
    }
    prevOnError?.call(d);
  };
  addTearDown(() => FlutterError.onError = prevOnError);

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
  var taps = 0;
  var drags = 0;
  var pngs = 0;
  var entries = 0;
  void budget() {
    pumps++;
    expect(pumps, lessThanOrEqualTo(600), reason: 'D219 pump 예산 600');
  }

  Future<void> frames(int n) async {
    for (var i = 0; i < n; i++) {
      budget();
      await t.pump(const Duration(milliseconds: 100));
    }
  }

  void guard(String step) {
    expect(t.takeException(), isNull, reason: 'D219 $step 예외');
    expect(blocked, isEmpty, reason: 'D219 $step 쓰기·원격 채널 0');
  }

  // ── fixture ──
  final created = DateTime(2025, 1, 1);
  final cat = <BadgeModel>[
    BadgeModel(id: 'b-100', name: '100회 근무', icon: '', type: BadgeType.experience,
        conditionType: BadgeConditionType.workDays, conditionValue: 100, order: 1, createdAt: created),
    BadgeModel(id: 'b-200', name: '200회 근무', icon: '', type: BadgeType.experience,
        conditionType: BadgeConditionType.workDays, conditionValue: 200, order: 2, createdAt: created),
    BadgeModel(id: 'b-consec', name: '연속 출근', icon: '', type: BadgeType.attendance,
        conditionType: BadgeConditionType.consecutive, conditionValue: 10, order: 3, createdAt: created),
    BadgeModel(id: 'b-unique', name: '5곳 경험', icon: '', type: BadgeType.experience,
        conditionType: BadgeConditionType.uniqueBusinesses, conditionValue: 5, order: 4, createdAt: created),
  ];
  const badgeIds = ['b-100', 'b-200', 'b-consec', 'b-unique'];
  UserModel user(String name, int days, int hours, int noShow, List<String> badges) => UserModel(
        uid: kUid219, username: 'worker', name: name, email: 'w@test.local', role: UserRole.USER,
        homeRegion: const UserRegion(province: '서울특별시', city: '송파구'), accountStatus: 'active',
        createdAt: DateTime(2025, 3, 1), totalWorkDays: days, totalWorkHours: hours, noShowCount: noShow,
        badges: badges,
      );
  final fixtures = <String, UserModel>{
    'a': user('김민지', 0, 0, 0, const []),
    'b': user('남궁가나다라마바사아자차카타파하', 200, 1600, 2, badgeIds),
    'c': user('이서준', 0, 0, 1, const []),
  };
  const expectRate = {'a': '100%', 'b': '99%', 'c': '0%'};

  final key = GlobalKey();
  Future<void> mount(UserModel u) async {
    budget();
    await t.pumpWidget(const SizedBox.shrink());
    await frames(1);
    budget();
    await t.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<UserProvider>(create: (_) => _User219(u)),
        ChangeNotifierProvider<BadgeProvider>(create: (_) => _Badges219(cat)),
      ],
      child: RepaintBoundary(
        key: key,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
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
          home: const UserMyTab(),
        ),
      ),
    ));
    await frames(8);
    guard('$curScene mount');
  }

  // ── 측정 helper ──
  List<Element> texts(String s) => find
      .byWidgetPredicate((w) {
        if (w is! Text) return false;
        final d = w.data ?? w.textSpan?.toPlainText();
        return d == s;
      })
      .evaluate()
      .toList();
  Finder el(Element e) => find.byElementPredicate((x) => identical(x, e));
  List<double> lt(Rect r) => [r.left, r.top, r.right, r.bottom];
  Rect rr(List<double> v) => Rect.fromLTRB(v[0], v[1], v[2], v[3]);
  bool inside(Rect r, Rect c) =>
      r.left >= c.left - 0.5 && r.top >= c.top - 0.5 && r.right <= c.right + 0.5 && r.bottom <= c.bottom + 0.5;
  String? hex(Color? c) => c?.toARGB32().toRadixString(16);
  Finder scrollF() => find.descendant(of: find.byType(UserMyTab), matching: find.byType(Scrollable));
  Rect clip() => t.getRect(scrollF()).intersect(Rect.fromLTWH(0, 0, vw, vh));

  Map<String, Object?>? statCell(String label) {
    final ls = texts(label).where((e) => ((e.widget as Text).style?.fontSize ?? 0) == 12).toList();
    if (ls.length != 1) return null;
    final col = find.ancestor(of: el(ls.first), matching: find.byType(Column)).first;
    final ts = find.descendant(of: col, matching: find.byType(Text)).evaluate().toList();
    final v = ts.first.widget as Text;
    return {
      'label': label, 'value': v.data, 'color': hex(v.style?.color),
      'valueRect': lt(t.getRect(el(ts.first))), 'labelRect': lt(t.getRect(el(ls.first))), 'cellRect': lt(t.getRect(col)),
    };
  }

  Map<String, Object?> measure() {
    final c = clip();
    final pos = t.state<ScrollableState>(scrollF()).position;
    final out = <String, Object?>{
      'offset': pos.pixels, 'max': pos.maxScrollExtent, 'clip': lt(c),
    };
    final cells = <Map<String, Object?>>[];
    for (final l in const ['완료 근무', '총 시간', '출근율']) {
      final m = statCell(l);
      if (m != null) cells.add(m);
    }
    out['statCells'] = cells;
    final rate = cells.where((m) => m['label'] == '출근율').toList();
    if (rate.isNotEmpty) {
      out['rateValueRect'] = rate.first['valueRect'];
      out['rateText'] = rate.first['value'];
      out['rateColor'] = rate.first['color'];
    }
    final done = texts('완료 근무').where((e) => ((e.widget as Text).style?.fontSize ?? 0) == 12).toList();
    if (done.length == 1) {
      final col = find.ancestor(of: el(done.first), matching: find.byType(Column)).first;
      final rowF = find.ancestor(of: col, matching: find.byWidgetPredicate((w) => w is Row || w is Wrap)).first;
      out['statRowRect'] = lt(t.getRect(rowF));
      out['statLayout'] = rowF.evaluate().first.widget is Wrap ? 'wrap' : 'row';
    }
    final career = texts('근무 기록');
    if (career.length == 1) {
      final cont = find.ancestor(of: el(career.first), matching: find.byType(Container)).first;
      out['careerRect'] = lt(t.getRect(cont));
    }
    final act = texts('나의 활동');
    final activity = <String, Object?>{'present': act.isNotEmpty};
    if (act.length == 1) {
      final cont = find.ancestor(of: el(act.first), matching: find.byType(Container)).first;
      final cr = t.getRect(cont);
      activity['rect'] = lt(cr);
      activity['topY'] = cr.top;
      activity['contentRight'] = cr.right - 20;
      activity['headerRect'] = lt(t.getRect(el(act.first)));
      final all = texts('전체보기');
      if (all.length == 1) {
        final hitF = find
            .ancestor(of: el(all.first), matching: find.byWidgetPredicate((w) => w is GestureDetector || w is InkWell))
            .first;
        activity['hitRect'] = lt(t.getRect(hitF));
        activity['hitWidget'] = hitF.evaluate().first.widget.runtimeType.toString();
        activity['textRect'] = lt(t.getRect(el(all.first)));
      }
      final chips = <Map<String, Object?>>[];
      for (final n in const ['100회 근무', '200회 근무', '연속 출근', '5곳 경험']) {
        final ns = texts(n);
        if (ns.length != 1) continue;
        final chipF = find.ancestor(of: el(ns.first), matching: find.byType(Container)).first;
        final rp = t.renderObject<RenderParagraph>(find.descendant(of: el(ns.first), matching: find.byType(RichText)));
        chips.add({
          'name': n, 'chipRect': lt(t.getRect(chipF)), 'nameRect': lt(t.getRect(el(ns.first))),
          'didExceedMaxLines': rp.didExceedMaxLines,
        });
      }
      activity['chips'] = chips;
      final more = texts('+1');
      if (more.length == 1) {
        activity['moreRect'] = lt(t.getRect(find.ancestor(of: el(more.first), matching: find.byType(Container)).first));
      }
    }
    out['activity'] = activity;
    final titles = <Map<String, Object?>>[];
    for (final n in const ['근무 관리', '내 정보', '설정']) {
      final ts = texts(n).where((e) => ((e.widget as Text).style?.fontSize ?? 0) == 12).toList();
      if (ts.length != 1) continue;
      final r = t.getRect(el(ts.first));
      titles.add({'text': n, 'rect': lt(r), 'color': hex((ts.first.widget as Text).style?.color), 'visible': inside(r, c)});
    }
    out['titles'] = titles;
    return out;
  }

  Future<Map<String, Object?>> dragUpBy(double need, Rect c, String next, int i, List<String> missing) async {
    final p0 = Offset(8, vh - 40);
    expect(c.contains(p0), isTrue, reason: 'D219 $curScene 시작점 clip 안');
    // [DU220] 첫 20px 는 인식 구간으로 따로 보낸다. 둘째 이동은 need 에서 20 을 빼지 않고 최소 48,
    //   끝점이 clip 위 8 안쪽에 남도록 maxStep 으로 자른다. 실제 콘텐츠 이동량은 보장하지 않고 매회 실측한다.
    final maxStep = p0.dy - 20 - (c.top + 8);
    expect(maxStep >= 48, isTrue, reason: 'D219 $curScene maxStep $maxStep');
    final want = need < 48 ? 48.0 : need;
    final second = want > maxStep ? maxStep : want;
    final p2 = Offset(p0.dx, p0.dy - 20 - second);
    expect(c.contains(p2), isTrue, reason: 'D219 $curScene 끝점 $p2 clip 안');
    final pos0 = t.state<ScrollableState>(scrollF()).position;
    final before = pos0.pixels;
    final maxBefore = pos0.maxScrollExtent;
    final hitPath = t.hitTestOnBinding(p0).path.map((e) => e.target.runtimeType.toString()).toList();
    drags++;
    expect(drags, lessThanOrEqualTo(24), reason: 'D219 drag 예산 24');
    final g = await t.startGesture(p0);
    var upSent = false;
    try {
      await g.moveBy(const Offset(0, -20));
      await g.moveBy(Offset(0, -second));
      upSent = true;
      await g.up();
    } finally {
      if (!upSent) {
        upSent = true;
        await g.up();
      }
    }
    await frames(4);
    guard('$curScene drag');
    final pos1 = t.state<ScrollableState>(scrollF()).position;
    final raw = <String, Object?>{
      'phase': phase, 'scene': curScene, 'i': i, 'next': next, 'need': need, 'clip': lt(c),
      'start': [p0.dx, p0.dy], 'end': [p2.dx, p2.dy], 'first': 20, 'second': second, 'maxStep': maxStep,
      'pixelsBefore': before, 'pixelsAfter': pos1.pixels, 'maxBefore': maxBefore, 'maxAfter': pos1.maxScrollExtent,
      'delta': pos1.pixels - before, 'missing': missing, 'hitPath': hitPath,
      'pumps': pumps, 'taps': taps, 'drags': drags,
    };
    print('D219D ${jsonEncode(raw)}');
    return raw;
  }

  bool sameList(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  Future<void> capture(String id) async {
    await frames(8);
    guard('$id 캡처 전');
    expect(pngs, lessThan(6), reason: 'D219 PNG 예산 6');
    final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    await t.runAsync(() async {
      outDir.createSync(recursive: true);
      final img = await boundary.toImage(pixelRatio: 1.0);
      final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
      final png = File('${outDir.path}/$id.png');
      if (png.existsSync()) throw StateError('D219 캡처를 덮지 않는다: ${png.path}');
      png.writeAsBytesSync(bytes!.buffer.asUint8List());
    });
    pngs++;
    guard('$id 캡처');
  }

  final results = <String, Object?>{};
  for (final cond in const ['c360', 'c320']) {
    if (cond == 'c360') setView(360, 780, 1.0);
    if (cond == 'c320') setView(320, 640, 2.0);
    for (final fx in const ['a', 'b', 'c']) {
      curScene = '$cond-$fx';
      final u = fixtures[fx]!;
      await mount(u);
      expect(find.byType(UserMyTab), findsOneWidget, reason: 'D219 $curScene MY');
      expect(scrollF(), findsOneWidget, reason: 'D219 $curScene scrollable 하나');
      final atCapture = measure();
      await capture(curScene);
      // 화면 밖 대상(통계·활동·섹션 제목)을 실제 drag 로 도달시켜 처음 전체가 보일 때의 기하를 기록한다.
      final reached = <String, Object?>{};
      var sceneDrags = 0;
      double? lastDelta;
      for (var i = 0;; i++) {
        final m = measure();
        final c = rr((m['clip']! as List).cast<double>());
        final act = m['activity']! as Map<String, Object?>;
        final groups = <String, List<Rect>>{};
        final cells = (m['statCells']! as List).cast<Map<String, Object?>>();
        if (cells.isNotEmpty) groups['stats'] = cells.map((x) => rr((x['cellRect']! as List).cast<double>())).toList();
        if (act['present'] == true && act['hitRect'] != null) {
          groups['activity'] = [
            rr((act['headerRect']! as List).cast<double>()),
            rr((act['hitRect']! as List).cast<double>()),
            ...(act['chips']! as List).cast<Map<String, Object?>>().map((x) => rr((x['chipRect']! as List).cast<double>())),
            if (act['moreRect'] != null) rr((act['moreRect']! as List).cast<double>()),
          ];
        }
        for (final tt in (m['titles']! as List).cast<Map<String, Object?>>()) {
          groups['title:${tt['text']}'] = [rr((tt['rect']! as List).cast<double>())];
        }
        for (final e in groups.entries) {
          if (!reached.containsKey(e.key) && e.value.every((r) => r.top >= c.top - 0.5 && r.bottom <= c.bottom + 0.5)) {
            reached[e.key] = {'at': i, 'offset': m['offset'], 'm': m};
          }
        }
        // 전체보기 진입 검사(c360-b, 활동이 처음 전부 보인 순간 1회). 목적지 화면 자체의 큰 글자 배치는 범위 밖이라 c320 에서는 하지 않는다.
        if (fx == 'b' && cond == 'c360' && reached.containsKey('activity') && !reached.containsKey('entry')) {
          final hit = rr((act['hitRect']! as List).cast<double>());
          final tp = after && applied.contains('R8') ? Offset(hit.center.dx, hit.bottom - 4) : hit.center;
          entries++;
          expect(entries, lessThanOrEqualTo(2), reason: 'D219 진입 검사 2');
          taps++;
          await t.tapAt(tp);
          await frames(10);
          guard('$curScene 전체보기 진입');
          final scr = find.byType(MyActivityScreen);
          expect(scr, findsOneWidget, reason: 'D219 $curScene MyActivityScreen 진입');
          final ids = (t.widget(scr) as MyActivityScreen).userBadgeIds;
          expect(sameList(ids, badgeIds), isTrue, reason: 'D219 $curScene 목적지 인자 raw ID');
          taps++;
          await t.tap(find.byType(BackButton));
          await frames(10);
          guard('$curScene 복귀');
          expect(find.byType(MyActivityScreen), findsNothing, reason: 'D219 $curScene 복귀');
          reached['entry'] = {'tap': [tp.dx, tp.dy], 'ids': ids};
          print('D219E ${jsonEncode({'phase': phase, 'scene': curScene, 'i': i, 'tap': [tp.dx, tp.dy], 'hit': lt(hit), 'ids': ids, 'returned': find.byType(MyActivityScreen).evaluate().isEmpty, 'pumps': pumps, 'taps': taps})}');
        }
        final want = <String>['stats', if (fx == 'b') 'activity', 'title:근무 관리', 'title:내 정보', 'title:설정'];
        final missing = want.where((k) => !reached.containsKey(k)).toList();
        final posM = t.state<ScrollableState>(scrollF()).position;
        print('D219M ${jsonEncode({'phase': phase, 'scene': curScene, 'i': i, 'offset': m['offset'], 'max': m['max'], 'extentAfter': posM.extentAfter, 'missing': missing, 'lastDelta': lastDelta, 'pumps': pumps, 'drags': drags})}');
        if (missing.isEmpty) break;
        // [DU220] 목표 도달을 먼저 본다. 남은 목표가 있는데 직전 drag 가 0.5px 이하였으면 무진행, 아래 여유가 없으면 측정 실패다.
        if (lastDelta != null) {
          expect(lastDelta > 0.5, isTrue, reason: 'D219 $curScene 무진행 $missing delta $lastDelta');
        }
        expect(posM.extentAfter > 0.5, isTrue, reason: 'D219 $curScene 아래 여유 없음·미도달 $missing');
        expect(sceneDrags < 4, isTrue, reason: 'D219 $curScene 도달 상한 4 미도달 $missing');
        // 다음 미도달 그룹의 아래 끝을 clip 아래 8px 안으로. 아직 트리에 없으면 최대 거리.
        final next = missing.first;
        final rs = groups[next];
        double need;
        if (rs == null) {
          need = 10000;
        } else {
          var bottom = rs.first.bottom;
          for (final r in rs) {
            if (r.bottom > bottom) bottom = r.bottom;
          }
          need = bottom - (c.bottom - 8);
        }
        expect(need > 0, isTrue, reason: 'D219 $curScene $next 이미 위로 지나감');
        sceneDrags++;
        final dr = await dragUpBy(need, c, next, i, missing);
        lastDelta = dr['delta']! as double;
      }
      // ── 재현 판정 재료 ──
      final stats = reached['stats'] as Map<String, Object?>;
      final sm = stats['m']! as Map<String, Object?>;
      final sc = rr((sm['clip']! as List).cast<double>());
      final cellsAt = (sm['statCells']! as List).cast<Map<String, Object?>>();
      final cellOver = cellsAt.any((x) => !inside(rr((x['cellRect']! as List).cast<double>()), sc));
      final judge = <String, Object?>{
        'R1': fx == 'a' && sm['rateText'] == '100%',
        'R5': diags.any((d) => d['scene'] == curScene && d['src'] == 'R5') || cellOver,
        'R9': (atCapture['titles']! as List).cast<Map<String, Object?>>().any((x) => x['color'] == hex(AppColors.textHint)) ||
            [for (final k in ['title:근무 관리', 'title:내 정보', 'title:설정']) reached[k]]
                .whereType<Map<String, Object?>>()
                .any((r) => ((r['m']! as Map<String, Object?>)['titles']! as List)
                    .cast<Map<String, Object?>>()
                    .any((x) => x['color'] == hex(AppColors.textHint))),
      };
      if (fx == 'b') {
        final am = ((reached['activity'] as Map<String, Object?>)['m']! as Map<String, Object?>)['activity']! as Map<String, Object?>;
        final hit = rr((am['hitRect']! as List).cast<double>());
        final cr = am['contentRight']! as double;
        final more = am['moreRect'] == null ? null : rr((am['moreRect']! as List).cast<double>());
        judge['R6'] = diags.any((d) => d['scene'] == curScene && d['src'] == 'R6') || (more != null && more.right > cr + 0.5);
        judge['R8'] = hit.width < 48 || hit.height < 48;
        judge['R7'] = (am['chips']! as List).cast<Map<String, Object?>>().any((x) => x['didExceedMaxLines'] == true);
      }
      print('D219C ${jsonEncode({'phase': phase, 'scene': curScene, 'judge': judge, 'diags': diags.where((d) => d['scene'] == curScene).toList()})}');
      // ── 신원 단언(두 phase) ──
      expect(sm['rateText'], after && applied.contains('R1') && fx == 'a' ? '—' : expectRate[fx],
          reason: 'D219 $curScene 출근율 표시');
      final doneV = cellsAt.where((x) => x['label'] == '완료 근무').map((x) => x['value']).toList();
      expect(doneV, [fx == 'b' ? '200회' : '0회'], reason: 'D219 $curScene 완료 근무');
      double absTop(String k) {
        final r = reached[k]! as Map<String, Object?>;
        final mm = r['m']! as Map<String, Object?>;
        final tt = (mm['titles']! as List).cast<Map<String, Object?>>().firstWhere((x) => 'title:${x['text']}' == k);
        return (tt['rect']! as List).cast<double>()[1] + (mm['offset']! as double);
      }

      expect(absTop('title:근무 관리') < absTop('title:내 정보') && absTop('title:내 정보') < absTop('title:설정'), isTrue,
          reason: 'D219 $curScene 메뉴 순서');
      // ── after 단언(적용 항목만) ──
      if (after) {
        expect(diags, isEmpty, reason: 'D219 after 진단 0');
        if (applied.contains('R1')) {
          expect(sm['rateColor'], fx == 'a' ? hex(AppColors.textSecondary) : (fx == 'b' ? hex(AppColors.successDark) : hex(AppColors.error)),
              reason: 'D219 after $curScene R1 색');
        }
        if (applied.contains('R5')) {
          expect(cellOver, isFalse, reason: 'D219 after $curScene R5 셀 clip 안');
          // [DU220] 실제 본문 안쪽(근무 기록 Container 좌우 padding 20 제외)과 셀·값·라벨 가로 포함, 셀끼리 겹침 0(같은 측정 offset).
          final career = rr((sm['careerRect']! as List).cast<double>());
          final innerL = career.left + 20;
          final innerR = career.right - 20;
          final cellRects = <Rect>[];
          for (final x in cellsAt) {
            for (final k in const ['cellRect', 'valueRect', 'labelRect']) {
              final r = rr((x[k]! as List).cast<double>());
              expect(r.left >= innerL - 0.5 && r.right <= innerR + 0.5, isTrue,
                  reason: 'D219 after $curScene R5 ${x['label']} $k 본문 안');
            }
            cellRects.add(rr((x['cellRect']! as List).cast<double>()));
          }
          for (var p = 0; p < cellRects.length; p++) {
            for (var q = p + 1; q < cellRects.length; q++) {
              expect(cellRects[p].overlaps(cellRects[q]), isFalse, reason: 'D219 after $curScene R5 셀 겹침 0');
            }
          }
        }
        if (applied.contains('R9')) {
          expect(judge['R9'], isFalse, reason: 'D219 after $curScene R9 제목 색');
        }
        if (fx == 'b') {
          final am = ((reached['activity'] as Map<String, Object?>)['m']! as Map<String, Object?>)['activity']! as Map<String, Object?>;
          final chipsAt = (am['chips']! as List).cast<Map<String, Object?>>();
          expect(chipsAt.map((x) => x['name']).toList(), ['100회 근무', '200회 근무', '연속 출근'], reason: 'D219 after 미리보기 3·순서');
          expect(am['moreRect'] != null, isTrue, reason: 'D219 after +1 유지');
          if (applied.contains('R6')) {
            expect(judge['R6'], isFalse, reason: 'D219 after $curScene R6 본문 안');
            final rects = [...chipsAt.map((x) => rr((x['chipRect']! as List).cast<double>())), rr((am['moreRect']! as List).cast<double>())];
            for (var i = 0; i < rects.length; i++) {
              for (var j = i + 1; j < rects.length; j++) {
                expect(rects[i].overlaps(rects[j]), isFalse, reason: 'D219 after $curScene 배지 겹침 0');
              }
            }
            // [DU220] 모든 배지 칩과 +1 이 활동 Container 의 본문 안쪽(좌우 padding 20 제외) 가로 범위 안.
            final actRect = rr((am['rect']! as List).cast<double>());
            for (final r in rects) {
              expect(r.left >= actRect.left + 20 - 0.5 && r.right <= actRect.right - 20 + 0.5, isTrue,
                  reason: 'D219 after $curScene R6 배지 본문 가로 안 $r');
            }
          }
          if (applied.contains('R8')) {
            expect(judge['R8'], isFalse, reason: 'D219 after $curScene R8 hit 48');
            // [DU220] hit 가 활동 영역 안이고 머리 글자·배지 칩·+1 과 겹치지 않는다.
            final hitR = rr((am['hitRect']! as List).cast<double>());
            final actR = rr((am['rect']! as List).cast<double>());
            final headR = rr((am['headerRect']! as List).cast<double>());
            expect(hitR.left >= actR.left - 0.5 && hitR.right <= actR.right + 0.5 && hitR.top >= actR.top - 0.5 && hitR.bottom <= actR.bottom + 0.5,
                isTrue, reason: 'D219 after $curScene R8 hit 활동 영역 안');
            expect(hitR.overlaps(headR), isFalse, reason: 'D219 after $curScene R8 hit 머리 겹침 0');
            for (final x in chipsAt) {
              expect(hitR.overlaps(rr((x['chipRect']! as List).cast<double>())), isFalse, reason: 'D219 after $curScene R8 hit 칩 겹침 0');
            }
            expect(hitR.overlaps(rr((am['moreRect']! as List).cast<double>())), isFalse, reason: 'D219 after $curScene R8 hit +1 겹침 0');
          }
        }
      }
      // ── sidecar ──
      await t.runAsync(() async {
        final js = File('${outDir.path}/$curScene.json');
        if (js.existsSync()) throw StateError('D219 sidecar 를 덮지 않는다: ${js.path}');
        js.writeAsStringSync(jsonEncode({
          'phase': phase, 'scene': curScene, 'viewport': [vw, vh], 'dpr': 1.0, 'textScaler': scale, 'inset': 0,
          'theme': 'RoleTheme.workerTheme', 'locale': 'ko_KR', 'fonts': 'vqLoadFonts', 'applied': appliedRaw,
          ...atCapture, 'reached': reached, 'judge': judge,
        }));
      });
      results[curScene] = judge;
    }
  }
  setView(360, 780, 1.0);
  print('D219END ${jsonEncode({'phase': phase, 'pumps': pumps, 'taps': taps, 'drags': drags, 'pngs': pngs, 'entries': entries, 'diags': diags.length, 'blocked': blocked.length, 'results': results})}');
}
